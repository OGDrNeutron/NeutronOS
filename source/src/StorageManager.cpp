#include "StorageManager.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QTimer>
#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>
#include <functional>

#ifdef Q_OS_LINUX
#include <unistd.h>
#endif

namespace {
QByteArray runBlocking(const QString &program,
                       const QStringList &arguments,
                       int timeoutMs,
                       int *exitCode = nullptr)
{
    QProcess process;
    process.setProgram(program);
    process.setArguments(arguments);
    process.start();

    if (!process.waitForStarted(2500)) {
        if (exitCode)
            *exitCode = -1;
        return {};
    }

    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(1000);
        if (exitCode)
            *exitCode = -2;
        return {};
    }

    if (exitCode)
        *exitCode = process.exitCode();

    return process.readAllStandardOutput() + process.readAllStandardError();
}

bool variantBool(const QVariantMap &map, const QString &key)
{
    const QVariant value = map.value(key);
    if (value.typeId() == QMetaType::Bool)
        return value.toBool();
    return value.toInt() != 0 || value.toString().compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0;
}


bool hasStoragePrivileges()
{
#ifdef Q_OS_LINUX
    return ::geteuid() == 0;
#else
    return false;
#endif
}

QString cleanDevicePath(const QString &path)
{
    const QString trimmed = path.trimmed();
    if (!trimmed.startsWith(QStringLiteral("/dev/")))
        return {};
    if (trimmed.contains(QStringLiteral("..")) || trimmed.contains(QLatin1Char('\n')) || trimmed.contains(QLatin1Char('\r')))
        return {};
    return trimmed;
}
}

StorageManager::StorageManager(QObject *parent)
    : QObject(parent),
      m_process(new QProcess(this)),
      m_catalogProcess(new QProcess(this)),
      m_optimizationWatcher(new QFutureWatcher<QVariantMap>(this))
{
    connect(m_process, &QProcess::readyReadStandardOutput,
            this, &StorageManager::onProcessReadyRead);
    connect(m_process, &QProcess::readyReadStandardError,
            this, &StorageManager::onProcessReadyRead);
    connect(m_process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            &StorageManager::onProcessFinished);
    connect(m_catalogProcess, &QProcess::readyReadStandardOutput,
            this, &StorageManager::onCatalogReadyRead);
    connect(m_catalogProcess, &QProcess::readyReadStandardError,
            this, &StorageManager::onCatalogReadyRead);
    connect(m_catalogProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            &StorageManager::onCatalogFinished);
    connect(m_catalogProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (!m_imagerCatalogLoading || error == QProcess::UnknownError)
            return;
        m_imagerCatalogLoading = false;
        m_imagerCatalogStatus = QStringLiteral("Catalog could not start: %1").arg(m_catalogProcess->errorString());
        emit imagerCatalogChanged();
    });
    connect(m_optimizationWatcher,
            &QFutureWatcher<QVariantMap>::finished,
            this,
            &StorageManager::onOptimizationScanFinished);

    m_optimizationRoot = defaultOptimizationRoot();

    m_performanceTimer.setInterval(1000);
    m_performanceTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_performanceTimer, &QTimer::timeout,
            this, &StorageManager::samplePerformanceTelemetry);
    m_performanceTimer.start();

    appendActivity(QStringLiteral("ready"),
                   QStringLiteral("Storage manager ready"),
                   QStringLiteral("Monitoring connected storage devices."),
                   QStringLiteral("info"));

    QTimer::singleShot(900, this, &StorageManager::refreshDevices);
    QTimer::singleShot(1400, this, &StorageManager::samplePerformanceTelemetry);
}

StorageManager::~StorageManager() = default;

QVariantList StorageManager::devices() const { return m_devices; }
QVariantMap StorageManager::usageBreakdowns() const { return m_usageBreakdowns; }
bool StorageManager::busy() const { return m_busy; }
QString StorageManager::operationName() const { return m_operationName; }
QString StorageManager::operationStatus() const { return m_operationStatus; }
int StorageManager::operationProgress() const { return m_operationProgress; }
QString StorageManager::lastMessage() const { return m_lastMessage; }
QString StorageManager::operationSource() const { return m_operationSource; }
QString StorageManager::operationTarget() const { return m_operationTarget; }
quint64 StorageManager::operationBytesProcessed() const { return m_operationBytesProcessed; }
quint64 StorageManager::operationTotalBytes() const { return m_cloneSourceBytes; }
QString StorageManager::operationBytesText() const
{
    if (m_cloneSourceBytes == 0)
        return m_operationBytesProcessed > 0 ? humanBytes(m_operationBytesProcessed) : QStringLiteral("—");
    return QStringLiteral("%1 / %2").arg(humanBytes(m_operationBytesProcessed), humanBytes(m_cloneSourceBytes));
}
QString StorageManager::operationSpeed() const { return m_operationSpeed.isEmpty() ? QStringLiteral("—") : m_operationSpeed; }
QString StorageManager::operationEta() const { return m_operationEta.isEmpty() ? QStringLiteral("—") : m_operationEta; }
QString StorageManager::operationElapsed() const { return m_operationElapsed.isEmpty() ? QStringLiteral("0s") : m_operationElapsed; }
QString StorageManager::operationVerification() const { return m_operationVerification; }
QVariantList StorageManager::imagerCatalog() const { return m_imagerCatalog; }
bool StorageManager::imagerCatalogLoading() const { return m_imagerCatalogLoading; }
QString StorageManager::imagerCatalogStatus() const { return m_imagerCatalogStatus; }
QString StorageManager::systemDisk() const { return m_systemDisk; }
bool StorageManager::smartctlAvailable() const { return !executable(QStringLiteral("smartctl")).isEmpty(); }
QVariantList StorageManager::optimizationCandidates() const { return m_optimizationCandidates; }
bool StorageManager::optimizationScanning() const { return m_optimizationScanning; }
QString StorageManager::optimizationRoot() const { return m_optimizationRoot; }
quint64 StorageManager::optimizationReclaimableBytes() const { return m_optimizationReclaimableBytes; }
QString StorageManager::optimizationReclaimable() const { return humanBytes(m_optimizationReclaimableBytes); }
QString StorageManager::optimizationSummary() const { return m_optimizationSummary; }
QVariantMap StorageManager::performanceTelemetry() const { return m_performanceTelemetry; }
QVariantList StorageManager::recentActivity() const { return m_recentActivity; }

QStringList StorageManager::supportedFilesystems() const
{
    QStringList values;
    if (!executable(QStringLiteral("mkfs.ext4")).isEmpty())
        values << QStringLiteral("ext4");
    if (!executable(QStringLiteral("mkfs.exfat")).isEmpty())
        values << QStringLiteral("exfat");
    if (!executable(QStringLiteral("mkfs.vfat")).isEmpty())
        values << QStringLiteral("vfat");
    if (!executable(QStringLiteral("mkfs.btrfs")).isEmpty())
        values << QStringLiteral("btrfs");
    return values;
}

QString StorageManager::executable(const QString &name)
{
    return QStandardPaths::findExecutable(name);
}

QString StorageManager::humanBytes(quint64 bytes)
{
    static const char *units[] = {"B", "KiB", "MiB", "GiB", "TiB", "PiB"};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < 5) {
        value /= 1024.0;
        ++unit;
    }
    return QString::number(value, unit == 0 ? 'f' : 'f', unit == 0 ? 0 : 1)
           + QLatin1Char(' ') + QString::fromLatin1(units[unit]);
}

QString StorageManager::humanDuration(qint64 seconds)
{
    seconds = qMax<qint64>(0, seconds);
    const qint64 hours = seconds / 3600;
    const qint64 minutes = (seconds % 3600) / 60;
    const qint64 secs = seconds % 60;
    if (hours > 0)
        return QStringLiteral("%1h %2m %3s").arg(hours).arg(minutes).arg(secs);
    if (minutes > 0)
        return QStringLiteral("%1m %2s").arg(minutes).arg(secs);
    return QStringLiteral("%1s").arg(secs);
}

QString StorageManager::shellQuoted(const QString &value)
{
    QString quoted = value;
    quoted.replace(QStringLiteral("'"), QStringLiteral("'\\''"));
    return QStringLiteral("'") + quoted + QStringLiteral("'");
}

QString StorageManager::imagerScriptPath()
{
    const QString fromBuild = QDir(QCoreApplication::applicationDirPath())
                                      .absoluteFilePath(QStringLiteral("../scripts/neutronos-rpi-imager.py"));
    if (QFileInfo::exists(fromBuild))
        return QFileInfo(fromBuild).canonicalFilePath();

    const QString projectPath = QDir(QCoreApplication::applicationDirPath())
                                    .absoluteFilePath(QStringLiteral("../../scripts/neutronos-rpi-imager.py"));
    if (QFileInfo::exists(projectPath))
        return QFileInfo(projectPath).canonicalFilePath();

    const QString installed = QStringLiteral("/opt/neutronos/scripts/neutronos-rpi-imager.py");
    return QFileInfo::exists(installed) ? installed : QString();
}

quint64 StorageManager::imageExpandedSize(const QString &imagePath, QString *archiveMember)
{
    if (archiveMember)
        archiveMember->clear();

    const QFileInfo info(imagePath);
    if (!info.exists() || !info.isFile())
        return 0;

    const QString lower = info.fileName().toLower();
    if (lower.endsWith(QStringLiteral(".img")) || lower.endsWith(QStringLiteral(".iso")))
        return static_cast<quint64>(qMax<qint64>(0, info.size()));

    int code = -1;
    if (lower.endsWith(QStringLiteral(".xz"))) {
        const QByteArray output = runBlocking(QStringLiteral("xz"),
                                              {QStringLiteral("--robot"), QStringLiteral("--list"), imagePath},
                                              12000, &code);
        if (code == 0) {
            const QList<QByteArray> lines = output.split('\n');
            for (const QByteArray &line : lines) {
                const QList<QByteArray> fields = line.split('\t');
                if (fields.size() >= 5 && fields.at(0) == "totals") {
                    bool ok = false;
                    const quint64 value = fields.at(4).toULongLong(&ok);
                    if (ok)
                        return value;
                }
            }
        }
        return 0;
    }

    if (lower.endsWith(QStringLiteral(".gz"))) {
        const QByteArray output = runBlocking(QStringLiteral("gzip"),
                                              {QStringLiteral("-l"), imagePath},
                                              12000, &code);
        if (code == 0) {
            const QList<QByteArray> lines = output.split('\n');
            for (int i = lines.size() - 1; i >= 0; --i) {
                const QList<QByteArray> fields = lines.at(i).simplified().split(' ');
                if (fields.size() >= 2) {
                    bool ok = false;
                    const quint64 value = fields.at(1).toULongLong(&ok);
                    if (ok)
                        return value;
                }
            }
        }
        return 0;
    }

    if (lower.endsWith(QStringLiteral(".zip"))) {
        const QByteArray output = runBlocking(QStringLiteral("unzip"),
                                              {QStringLiteral("-l"), imagePath},
                                              12000, &code);
        if (code == 0) {
            const QList<QByteArray> lines = output.split('\n');
            for (const QByteArray &line : lines) {
                const QList<QByteArray> fields = line.simplified().split(' ');
                if (fields.size() < 4)
                    continue;
                const QString member = QString::fromLocal8Bit(fields.mid(3).join(" "));
                const QString memberLower = member.toLower();
                if (!memberLower.endsWith(QStringLiteral(".img")) &&
                    !memberLower.endsWith(QStringLiteral(".iso")))
                    continue;
                bool ok = false;
                const quint64 value = fields.at(0).toULongLong(&ok);
                if (ok) {
                    if (archiveMember)
                        *archiveMember = member;
                    return value;
                }
            }
        }
    }

    return 0;
}

QString StorageManager::normalizedFilesystem(const QString &filesystem)
{
    const QString value = filesystem.trimmed().toLower();
    if (value == QStringLiteral("fat32"))
        return QStringLiteral("vfat");
    if (value == QStringLiteral("ext4") || value == QStringLiteral("exfat") ||
        value == QStringLiteral("vfat") || value == QStringLiteral("btrfs"))
        return value;
    return {};
}

QString StorageManager::sanitizedLabel(const QString &label, const QString &filesystem)
{
    QString value = label.trimmed();
    value.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9 _.-]")), QString());
    const int maximum = filesystem == QStringLiteral("vfat") ? 11 : 32;
    return value.left(maximum);
}

QString StorageManager::firstPartitionPath(const QString &diskPath)
{
    if (QRegularExpression(QStringLiteral("\\d$")).match(diskPath).hasMatch())
        return diskPath + QStringLiteral("p1");
    return diskPath + QStringLiteral("1");
}

QStringList StorageManager::stringListFromJson(const QVariant &value)
{
    QStringList resultValues;
    if (value.typeId() == QMetaType::QStringList)
        return value.toStringList();
    if (value.typeId() == QMetaType::QVariantList) {
        const QVariantList list = value.toList();
        for (const QVariant &entry : list) {
            const QString text = entry.toString().trimmed();
            if (!text.isEmpty())
                resultValues << text;
        }
    } else {
        const QString text = value.toString().trimmed();
        if (!text.isEmpty())
            resultValues << text;
    }
    return resultValues;
}

QString StorageManager::canonicalOrAbsolute(const QString &path)
{
    const QFileInfo info(QDir::cleanPath(path.trimmed()));
    const QString canonical = info.canonicalFilePath();
    return canonical.isEmpty() ? info.absoluteFilePath() : canonical;
}

QString StorageManager::sanitizedMountName(const QString &name)
{
    QString clean = name.trimmed();
    clean.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral("_"));
    clean.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_.-]")), QStringLiteral("_"));
    clean.replace(QRegularExpression(QStringLiteral("_+")), QStringLiteral("_"));
    while (clean.startsWith(QLatin1Char('.')) || clean.startsWith(QLatin1Char('-')) || clean.startsWith(QLatin1Char('_')))
        clean.remove(0, 1);
    while (clean.endsWith(QLatin1Char('.')) || clean.endsWith(QLatin1Char(' ')))
        clean.chop(1);
    if (clean == QStringLiteral(".") || clean == QStringLiteral(".."))
        clean.clear();
    return clean.left(48);
}

bool StorageManager::isProtectedOptimizationPath(const QString &path)
{
    const QString cleaned = QDir::cleanPath(path);
    static const QStringList protectedPrefixes{
        QStringLiteral("/boot"), QStringLiteral("/dev"), QStringLiteral("/etc"),
        QStringLiteral("/proc"), QStringLiteral("/run"), QStringLiteral("/sys"),
        QStringLiteral("/usr"), QStringLiteral("/bin"), QStringLiteral("/sbin"),
        QStringLiteral("/lib"), QStringLiteral("/lib32"), QStringLiteral("/lib64"),
        QStringLiteral("/opt"), QStringLiteral("/var/lib"), QStringLiteral("/var/log")
    };
    if (cleaned == QStringLiteral("/") || cleaned.isEmpty())
        return true;
    for (const QString &prefix : protectedPrefixes) {
        if (cleaned == prefix || cleaned.startsWith(prefix + QLatin1Char('/')))
            return true;
    }
    return false;
}

bool StorageManager::isOptimizationRootAllowed(const QString &path)
{
    const QString cleaned = canonicalOrAbsolute(path);
    if (cleaned.isEmpty() || isProtectedOptimizationPath(cleaned))
        return false;

    const QString home = canonicalOrAbsolute(QDir::homePath());
    if (!home.isEmpty() && (cleaned == home || cleaned.startsWith(home + QLatin1Char('/'))))
        return true;

    static const QStringList allowedPrefixes{
        QStringLiteral("/media"), QStringLiteral("/mnt"), QStringLiteral("/tmp"),
        QStringLiteral("/var/tmp"), QStringLiteral("/var/cache/apt/archives")
    };
    for (const QString &prefix : allowedPrefixes) {
        if (cleaned == prefix || cleaned.startsWith(prefix + QLatin1Char('/')))
            return true;
    }
    return false;
}

QString StorageManager::categoryForPath(const QString &path)
{
    const QString lower = path.toLower();
    const QString suffix = QFileInfo(path).suffix().toLower();
    if (lower.contains(QStringLiteral("/.local/share/trash/files/")))
        return QStringLiteral("Trash");
    if (lower.contains(QStringLiteral("/.cache/")) || lower.contains(QStringLiteral("/cache/")))
        return lower.contains(QStringLiteral("thumbnail")) ? QStringLiteral("Thumbnails") : QStringLiteral("Application cache");
    if (lower.startsWith(QStringLiteral("/tmp/")) || lower.startsWith(QStringLiteral("/var/tmp/")))
        return QStringLiteral("Temporary file");
    if (lower.contains(QStringLiteral("/var/cache/apt/archives/")) || suffix == QStringLiteral("deb"))
        return QStringLiteral("Package cache");
    if (suffix == QStringLiteral("log") || lower.contains(QStringLiteral("/logs/")))
        return QStringLiteral("Diagnostic log");
    if (suffix == QStringLiteral("core") || suffix == QStringLiteral("dmp") || lower.contains(QStringLiteral("crash")))
        return QStringLiteral("Crash report");
    if (suffix == QStringLiteral("tmp") || suffix == QStringLiteral("temp") || suffix == QStringLiteral("part") ||
        suffix == QStringLiteral("crdownload"))
        return QStringLiteral("Incomplete or temporary download");
    if (suffix == QStringLiteral("bak") || suffix == QStringLiteral("old") || suffix == QStringLiteral("orig") ||
        suffix == QStringLiteral("save"))
        return QStringLiteral("Backup copy");
    if (lower.contains(QStringLiteral("/downloads/")))
        return QStringLiteral("Downloaded file");
    if (lower.contains(QStringLiteral("/videos/")) || lower.contains(QStringLiteral("/music/")) ||
        lower.contains(QStringLiteral("/pictures/")))
        return QStringLiteral("Media file");
    return QStringLiteral("Large or old file");
}

QString StorageManager::purposeForPath(const QString &path)
{
    const QString category = categoryForPath(path);
    if (category == QStringLiteral("Trash"))
        return QStringLiteral("A previously deleted item retained by the desktop Trash so it can still be restored.");
    if (category == QStringLiteral("Application cache"))
        return QStringLiteral("Regenerable application data used to improve startup or browsing speed.");
    if (category == QStringLiteral("Thumbnails"))
        return QStringLiteral("Regenerable preview images created for media and file browsers.");
    if (category == QStringLiteral("Temporary file"))
        return QStringLiteral("Working data created temporarily by an application or system task.");
    if (category == QStringLiteral("Package cache"))
        return QStringLiteral("A downloaded software package retained so an installation can be repeated without downloading it again.");
    if (category == QStringLiteral("Diagnostic log"))
        return QStringLiteral("Text diagnostics used to investigate application or system activity.");
    if (category == QStringLiteral("Crash report"))
        return QStringLiteral("Diagnostic state captured when an application or process failed.");
    if (category == QStringLiteral("Incomplete or temporary download"))
        return QStringLiteral("An unfinished transfer or temporary download fragment that may no longer be needed.");
    if (category == QStringLiteral("Backup copy"))
        return QStringLiteral("An older safety copy created by an editor, installer, or update process.");
    if (category == QStringLiteral("Downloaded file"))
        return QStringLiteral("A user-downloaded file. Review it before deletion because it may be important.");
    if (category == QStringLiteral("Media file"))
        return QStringLiteral("User media. It is listed only because it is old or large and is never preselected for deletion.");
    return QStringLiteral("A large or old user file. Review its contents and location before deciding whether to delete it.");
}

QVariantMap StorageManager::scanOptimizationRoot(const QString &rootPath, int olderThanDays)
{
    QVariantMap resultMap;
    const QString root = canonicalOrAbsolute(rootPath);
    if (!isOptimizationRootAllowed(root)) {
        resultMap.insert(QStringLiteral("ok"), false);
        resultMap.insert(QStringLiteral("message"), QStringLiteral("That location is protected or is not an approved optimization root."));
        return resultMap;
    }

    const QFileInfo rootInfo(root);
    if (!rootInfo.exists() || !rootInfo.isDir()) {
        resultMap.insert(QStringLiteral("ok"), false);
        resultMap.insert(QStringLiteral("message"), QStringLiteral("The optimization location does not exist or is not a directory."));
        return resultMap;
    }

    const int days = qBound(1, olderThanDays, 3650);
    const QDateTime now = QDateTime::currentDateTimeUtc();
    QVariantList candidates;
    quint64 reclaimableBytes = 0;
    quint64 reviewedBytes = 0;
    int scannedFiles = 0;
    constexpr int maximumScannedFiles = 50000;
    constexpr int maximumCandidates = 800;

    QDirIterator iterator(root,
                          QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot | QDir::Readable,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext() && scannedFiles < maximumScannedFiles) {
        const QString path = iterator.next();
        ++scannedFiles;
        const QFileInfo info = iterator.fileInfo();
        if (info.isSymLink() || !info.isFile())
            continue;

        const QString canonical = canonicalOrAbsolute(path);
        if (canonical.isEmpty() || isProtectedOptimizationPath(canonical))
            continue;
        if (!(canonical == root || canonical.startsWith(root + QLatin1Char('/'))))
            continue;

        const QDateTime modified = info.lastModified().toUTC();
        const QDateTime accessed = info.lastRead().isValid() ? info.lastRead().toUTC() : modified;
        const QDateTime lastUsed = accessed > modified ? accessed : modified;
        const qint64 ageDays = qMax<qint64>(qint64{0}, lastUsed.daysTo(now));
        const quint64 sizeBytes = static_cast<quint64>(qMax<qint64>(qint64{0}, info.size()));
        const QString category = categoryForPath(canonical);

        const bool safeRegenerable = category == QStringLiteral("Trash") ||
                category == QStringLiteral("Application cache") ||
                category == QStringLiteral("Thumbnails") ||
                category == QStringLiteral("Temporary file") ||
                category == QStringLiteral("Package cache") ||
                category == QStringLiteral("Diagnostic log") ||
                category == QStringLiteral("Crash report") ||
                category == QStringLiteral("Incomplete or temporary download");
        const bool userReviewCandidate = ((category == QStringLiteral("Downloaded file") ||
                                           category == QStringLiteral("Backup copy")) && ageDays >= days) ||
                (sizeBytes >= 128ULL * 1024ULL * 1024ULL && ageDays >= days);
        if ((!safeRegenerable || ageDays < days) && !userReviewCandidate)
            continue;

        const bool writable = info.isWritable();
        const bool recommended = safeRegenerable && writable;
        QVariantMap candidate;
        candidate.insert(QStringLiteral("path"), canonical);
        candidate.insert(QStringLiteral("name"), info.fileName());
        candidate.insert(QStringLiteral("directory"), info.absolutePath());
        candidate.insert(QStringLiteral("category"), category);
        candidate.insert(QStringLiteral("purpose"), purposeForPath(canonical));
        candidate.insert(QStringLiteral("reason"), recommended
                         ? QStringLiteral("Old, regenerable or diagnostic data that can usually be recreated if needed.")
                         : QStringLiteral("Large or old user data requiring an explicit personal review."));
        candidate.insert(QStringLiteral("sizeBytes"), QVariant::fromValue(sizeBytes));
        candidate.insert(QStringLiteral("size"), humanBytes(sizeBytes));
        candidate.insert(QStringLiteral("lastAccessed"), accessed.toLocalTime().toString(QStringLiteral("yyyy-MM-dd hh:mm AP")));
        candidate.insert(QStringLiteral("lastModified"), modified.toLocalTime().toString(QStringLiteral("yyyy-MM-dd hh:mm AP")));
        candidate.insert(QStringLiteral("lastUsed"), lastUsed.toLocalTime().toString(QStringLiteral("yyyy-MM-dd hh:mm AP")));
        candidate.insert(QStringLiteral("ageDays"), ageDays);
        candidate.insert(QStringLiteral("writable"), writable);
        candidate.insert(QStringLiteral("recommended"), recommended);
        candidate.insert(QStringLiteral("selected"), recommended);
        candidate.insert(QStringLiteral("protected"), false);
        candidates << candidate;
        reviewedBytes += sizeBytes;
        if (recommended)
            reclaimableBytes += sizeBytes;
        if (candidates.size() >= maximumCandidates)
            break;
    }

    std::sort(candidates.begin(), candidates.end(), [](const QVariant &leftValue, const QVariant &rightValue) {
        const QVariantMap left = leftValue.toMap();
        const QVariantMap right = rightValue.toMap();
        const bool leftRecommended = left.value(QStringLiteral("recommended")).toBool();
        const bool rightRecommended = right.value(QStringLiteral("recommended")).toBool();
        if (leftRecommended != rightRecommended)
            return leftRecommended > rightRecommended;
        return left.value(QStringLiteral("sizeBytes")).toULongLong() >
                right.value(QStringLiteral("sizeBytes")).toULongLong();
    });

    resultMap.insert(QStringLiteral("ok"), true);
    resultMap.insert(QStringLiteral("root"), root);
    resultMap.insert(QStringLiteral("olderThanDays"), days);
    resultMap.insert(QStringLiteral("scannedFiles"), scannedFiles);
    resultMap.insert(QStringLiteral("candidates"), candidates);
    resultMap.insert(QStringLiteral("candidateCount"), candidates.size());
    resultMap.insert(QStringLiteral("reviewedBytes"), QVariant::fromValue(reviewedBytes));
    resultMap.insert(QStringLiteral("reclaimableBytes"), QVariant::fromValue(reclaimableBytes));
    resultMap.insert(QStringLiteral("summary"), QStringLiteral("%1 review items found; %2 is recommended and writable.")
                     .arg(candidates.size()).arg(humanBytes(reclaimableBytes)));
    resultMap.insert(QStringLiteral("message"), candidates.isEmpty()
                     ? QStringLiteral("No old cache, temporary, diagnostic, or large review files were found.")
                     : QStringLiteral("Optimization review completed. Nothing has been deleted."));
    return resultMap;
}

QString StorageManager::defaultOptimizationRoot() const
{
    return QDir::homePath();
}

bool StorageManager::scanOptimization(const QString &rootPath, int olderThanDays)
{
    if (m_optimizationScanning || m_busy) {
        m_lastMessage = QStringLiteral("Wait for the current storage task to finish.");
        emit operationChanged();
        return false;
    }

    const QString requested = rootPath.trimmed().isEmpty() ? defaultOptimizationRoot() : rootPath;
    const QString root = canonicalOrAbsolute(requested);
    if (!isOptimizationRootAllowed(root) || !QFileInfo(root).isDir()) {
        m_lastMessage = QStringLiteral("That location cannot be scanned by Storage Optimize.");
        emit operationChanged();
        return false;
    }

    m_optimizationRoot = root;
    m_optimizationAgeDays = qBound(1, olderThanDays, 3650);
    m_optimizationScanning = true;
    m_optimizationSummary = QStringLiteral("Scanning %1 without deleting anything…").arg(root);
    m_lastMessage = m_optimizationSummary;
    emit optimizationChanged();
    emit operationChanged();

    const int scanAgeDays = m_optimizationAgeDays;
    m_optimizationWatcher->setFuture(QtConcurrent::run([root, scanAgeDays]() {
        return StorageManager::scanOptimizationRoot(root, scanAgeDays);
    }));
    return true;
}

void StorageManager::onOptimizationScanFinished()
{
    const QVariantMap resultMap = m_optimizationWatcher->result();
    m_optimizationScanning = false;
    const bool ok = resultMap.value(QStringLiteral("ok")).toBool();
    if (ok) {
        m_optimizationCandidates = resultMap.value(QStringLiteral("candidates")).toList();
        m_optimizationRoot = resultMap.value(QStringLiteral("root"), m_optimizationRoot).toString();
        m_optimizationReclaimableBytes = resultMap.value(QStringLiteral("reclaimableBytes")).toULongLong();
        m_optimizationSummary = resultMap.value(QStringLiteral("summary")).toString();
    } else {
        m_optimizationCandidates.clear();
        m_optimizationReclaimableBytes = 0;
        m_optimizationSummary = resultMap.value(QStringLiteral("message")).toString();
    }
    m_lastMessage = resultMap.value(QStringLiteral("message"), m_optimizationSummary).toString();
    appendActivity(QStringLiteral("optimize"),
                   ok ? QStringLiteral("Storage analysis completed")
                      : QStringLiteral("Storage analysis failed"),
                   m_lastMessage,
                   ok ? QStringLiteral("success") : QStringLiteral("warning"));
    emit optimizationChanged();
    emit operationChanged();
    emit optimizationFinished(ok, m_lastMessage);
}

QVariantMap StorageManager::optimizationCandidateDetails(const QString &path) const
{
    const QString canonical = canonicalOrAbsolute(path);
    for (const QVariant &entry : m_optimizationCandidates) {
        const QVariantMap candidate = entry.toMap();
        if (candidate.value(QStringLiteral("path")).toString() == canonical)
            return candidate;
    }
    return result(false, QStringLiteral("That item is not part of the current optimization review."));
}

QVariantMap StorageManager::validateOptimizationDelete(const QStringList &paths) const
{
    QVariantMap output;
    QStringList approved;
    quint64 bytes = 0;
    for (const QString &path : paths) {
        const QString canonical = canonicalOrAbsolute(path);
        if (canonical.isEmpty() || isProtectedOptimizationPath(canonical))
            continue;
        QVariantMap candidate;
        for (const QVariant &entry : m_optimizationCandidates) {
            const QVariantMap value = entry.toMap();
            if (value.value(QStringLiteral("path")).toString() == canonical) {
                candidate = value;
                break;
            }
        }
        const QFileInfo info(canonical);
        if (candidate.isEmpty() || !info.exists() || !info.isFile() || info.isSymLink() || !info.isWritable())
            continue;
        if (!m_optimizationRoot.isEmpty() && !(canonical == m_optimizationRoot || canonical.startsWith(m_optimizationRoot + QLatin1Char('/'))))
            continue;
        approved << canonical;
        bytes += static_cast<quint64>(qMax<qint64>(qint64{0}, info.size()));
    }
    output.insert(QStringLiteral("ok"), !approved.isEmpty());
    output.insert(QStringLiteral("paths"), approved);
    output.insert(QStringLiteral("count"), approved.size());
    output.insert(QStringLiteral("bytes"), QVariant::fromValue(bytes));
    output.insert(QStringLiteral("size"), humanBytes(bytes));
    output.insert(QStringLiteral("confirmation"), QStringLiteral("DELETE"));
    output.insert(QStringLiteral("message"), approved.isEmpty()
                  ? QStringLiteral("No currently reviewed writable files were selected.")
                  : QStringLiteral("%1 files totaling %2 will be permanently deleted after confirmation.")
                    .arg(approved.size()).arg(humanBytes(bytes)));
    return output;
}

bool StorageManager::deleteOptimizationCandidates(const QStringList &paths, const QString &confirmation)
{
    if (m_optimizationScanning || m_busy) {
        m_lastMessage = QStringLiteral("Wait for the current storage task to finish.");
        emit operationChanged();
        return false;
    }
    if (confirmation.trimmed() != QStringLiteral("DELETE")) {
        m_lastMessage = QStringLiteral("Deletion confirmation must be exactly DELETE.");
        emit operationChanged();
        return false;
    }

    const QVariantMap validation = validateOptimizationDelete(paths);
    if (!validation.value(QStringLiteral("ok")).toBool()) {
        m_lastMessage = validation.value(QStringLiteral("message")).toString();
        emit operationChanged();
        return false;
    }

    const QStringList approved = validation.value(QStringLiteral("paths")).toStringList();
    int deleted = 0;
    QStringList failures;
    for (const QString &path : approved) {
        if (QFile::remove(path))
            ++deleted;
        else
            failures << path;
    }

    m_lastMessage = failures.isEmpty()
            ? QStringLiteral("Deleted %1 reviewed files. Running a fresh review…").arg(deleted)
            : QStringLiteral("Deleted %1 files; %2 could not be removed.").arg(deleted).arg(failures.size());
    emit operationChanged();
    emit optimizationFinished(failures.isEmpty(), m_lastMessage);
    scanOptimization(m_optimizationRoot, m_optimizationAgeDays);
    return failures.isEmpty();
}

QString StorageManager::describePath(const QString &path) const
{
    return purposeForPath(path);
}

QVariantMap StorageManager::scanUsageBreakdown(const QString &mountPoint)
{
    QVariantMap resultMap;
    const QFileInfo mountInfo(mountPoint);
    QString canonical = mountInfo.canonicalFilePath();
    if (canonical.isEmpty())
        canonical = mountInfo.absoluteFilePath();

    QStorageInfo storage(canonical);
    if (!storage.isValid() || !storage.isReady()) {
        resultMap.insert(QStringLiteral("mountPoint"), mountPoint);
        resultMap.insert(QStringLiteral("error"), QStringLiteral("Storage is not mounted."));
        resultMap.insert(QStringLiteral("entries"), QVariantList{});
        resultMap.insert(QStringLiteral("scanning"), false);
        return resultMap;
    }

    const quint64 totalBytes = static_cast<quint64>(qMax<qint64>(qint64{0}, storage.bytesTotal()));
    const quint64 availableBytes = static_cast<quint64>(qMax<qint64>(qint64{0}, storage.bytesAvailable()));
    const quint64 usedBytes = totalBytes > availableBytes ? totalBytes - availableBytes : 0;

    auto duBytes = [](const QStringList &paths) -> quint64 {
        quint64 total = 0;
        const QString du = QStandardPaths::findExecutable(QStringLiteral("du"));
        if (du.isEmpty())
            return 0;

        const QString nice = QStandardPaths::findExecutable(QStringLiteral("nice"));
        const QString ionice = QStandardPaths::findExecutable(QStringLiteral("ionice"));

        for (const QString &path : paths) {
            if (!QFileInfo(path).exists())
                continue;

            QString program = du;
            QStringList args{QStringLiteral("-s"), QStringLiteral("-x"), QStringLiteral("-B1"), path};

            if (!nice.isEmpty()) {
                if (!ionice.isEmpty()) {
                    program = nice;
                    args = {
                        QStringLiteral("-n"), QStringLiteral("19"),
                        ionice, QStringLiteral("-c"), QStringLiteral("3"),
                        du, QStringLiteral("-s"), QStringLiteral("-x"),
                        QStringLiteral("-B1"), path
                    };
                } else {
                    program = nice;
                    args = {
                        QStringLiteral("-n"), QStringLiteral("19"),
                        du, QStringLiteral("-s"), QStringLiteral("-x"),
                        QStringLiteral("-B1"), path
                    };
                }
            }

            int code = -1;
            const QByteArray output = runBlocking(program, args, 20 * 60 * 1000, &code);
            if (code != 0)
                continue;

            const QByteArray first = output.trimmed().split('\n').value(0);
            bool ok = false;
            const quint64 bytes = first.split('\t').value(0).trimmed().toULongLong(&ok);
            if (ok)
                total += bytes;
        }
        return total;
    };

    auto matchingDirectories = [](const QString &root, const QStringList &names) -> QStringList {
        QStringList paths;
        QDir directory(root);
        if (!directory.exists())
            return paths;

        const QFileInfoList entries = directory.entryInfoList(
            QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable,
            QDir::Name | QDir::IgnoreCase);

        for (const QFileInfo &entry : entries) {
            const QString base = entry.fileName().trimmed();
            for (const QString &candidate : names) {
                if (base.compare(candidate, Qt::CaseInsensitive) == 0) {
                    paths << entry.absoluteFilePath();
                    break;
                }
            }
        }
        paths.removeDuplicates();
        return paths;
    };

    struct Category {
        QString name;
        QString color;
        QStringList paths;
    };

    QList<Category> categories;
    const bool systemVolume = canonical == QStringLiteral("/");

    if (systemVolume) {
        categories = {
            {QStringLiteral("System"), QStringLiteral("#15BFFF"),
             {QStringLiteral("/usr"), QStringLiteral("/boot"), QStringLiteral("/etc"),
              QStringLiteral("/lib"), QStringLiteral("/lib64"), QStringLiteral("/bin"),
              QStringLiteral("/sbin")}},
            {QStringLiteral("Apps"), QStringLiteral("#9D55FF"),
             {QStringLiteral("/opt/neutronos"), QStringLiteral("/opt"),
              QStringLiteral("/var/lib/docker"), QStringLiteral("/var/lib/containers")}},
            {QStringLiteral("Cache"), QStringLiteral("#FFAB43"),
             {QStringLiteral("/var/cache"), QStringLiteral("/home/echo/.cache"),
              QStringLiteral("/tmp")}}
        };
    } else {
        categories = {
            {QStringLiteral("Media"), QStringLiteral("#15BFFF"),
             matchingDirectories(canonical, {QStringLiteral("Movies"), QStringLiteral("Shows"),
                                             QStringLiteral("TV"), QStringLiteral("Videos"),
                                             QStringLiteral("Media")})},
            {QStringLiteral("Photos"), QStringLiteral("#9D55FF"),
             matchingDirectories(canonical, {QStringLiteral("Photos"), QStringLiteral("Pictures"),
                                             QStringLiteral("Images")})},
            {QStringLiteral("Music"), QStringLiteral("#FFAB43"),
             matchingDirectories(canonical, {QStringLiteral("Music"), QStringLiteral("Audio")})},
            {QStringLiteral("Backups"), QStringLiteral("#FF4D91"),
             matchingDirectories(canonical, {QStringLiteral("Backups"), QStringLiteral("Backup"),
                                             QStringLiteral("Snapshots")})}
        };
    }

    QVariantList rows;
    quint64 categorizedBytes = 0;

    auto appendRow = [&](const QString &name, const QString &color, quint64 bytes, bool freeSpace) {
        const double percent = totalBytes > 0
                ? static_cast<double>(bytes) * 100.0 / static_cast<double>(totalBytes)
                : 0.0;

        QVariantMap row;
        row.insert(QStringLiteral("name"), name);
        row.insert(QStringLiteral("value"), humanBytes(bytes));
        row.insert(QStringLiteral("bytes"), QVariant::fromValue(bytes));
        row.insert(QStringLiteral("percent"), percent);
        row.insert(QStringLiteral("color"), color);
        row.insert(QStringLiteral("free"), freeSpace);
        rows << row;
    };

    for (const Category &category : categories) {
        const quint64 bytes = duBytes(category.paths);
        categorizedBytes += bytes;
        appendRow(category.name, category.color, bytes, false);
    }

    const quint64 otherBytes = usedBytes > categorizedBytes ? usedBytes - categorizedBytes : 0;
    appendRow(QStringLiteral("Other"), QStringLiteral("#FF4D91"), otherBytes, false);
    appendRow(QStringLiteral("Free"), QStringLiteral("#8193FF"), availableBytes, true);

    resultMap.insert(QStringLiteral("mountPoint"), canonical);
    resultMap.insert(QStringLiteral("totalBytes"), QVariant::fromValue(totalBytes));
    resultMap.insert(QStringLiteral("usedBytes"), QVariant::fromValue(usedBytes));
    resultMap.insert(QStringLiteral("availableBytes"), QVariant::fromValue(availableBytes));
    resultMap.insert(QStringLiteral("entries"), rows);
    resultMap.insert(QStringLiteral("scanning"), false);
    resultMap.insert(QStringLiteral("scannedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    return resultMap;
}

void StorageManager::requestUsageBreakdown(const QString &mountPoint, bool force)
{
    const QString requested = mountPoint.trimmed();
    if (requested.isEmpty() || !QDir::isAbsolutePath(requested))
        return;

    QFileInfo info(requested);
    QString canonical = info.canonicalFilePath();
    if (canonical.isEmpty())
        canonical = info.absoluteFilePath();

    if (canonical.isEmpty() || !QFileInfo(canonical).exists())
        return;

    if (m_usageBreakdownScanning.contains(canonical))
        return;

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const qint64 last = m_usageBreakdownLastScanMs.value(canonical, 0);
    constexpr qint64 refreshWindowMs = 30 * 60 * 1000;

    if (!force && m_usageBreakdowns.contains(canonical) &&
        last > 0 && now - last < refreshWindowMs)
        return;

    if (!m_usageBreakdownScanning.isEmpty())
        return;

    m_usageBreakdownScanning.insert(canonical);

    QVariantMap pending = m_usageBreakdowns.value(canonical).toMap();
    pending.insert(QStringLiteral("mountPoint"), canonical);
    pending.insert(QStringLiteral("scanning"), true);
    m_usageBreakdowns.insert(canonical, pending);
    emit devicesChanged();

    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcher<QVariantMap>::finished, this,
            [this, watcher, canonical]() {
        QVariantMap resultMap = watcher->result();
        resultMap.insert(QStringLiteral("mountPoint"), canonical);
        resultMap.insert(QStringLiteral("scanning"), false);
        m_usageBreakdowns.insert(canonical, resultMap);
        m_usageBreakdownLastScanMs.insert(canonical, QDateTime::currentMSecsSinceEpoch());
        m_usageBreakdownScanning.remove(canonical);
        watcher->deleteLater();
        emit devicesChanged();
    });

    watcher->setFuture(QtConcurrent::run([canonical]() {
        return StorageManager::scanUsageBreakdown(canonical);
    }));
}

void StorageManager::appendActivity(const QString &kind,
                                    const QString &title,
                                    const QString &detail,
                                    const QString &tone)
{
    QVariantMap entry;
    entry.insert(QStringLiteral("kind"), kind);
    entry.insert(QStringLiteral("title"), title);
    entry.insert(QStringLiteral("detail"), detail);
    entry.insert(QStringLiteral("tone"), tone);
    entry.insert(QStringLiteral("time"), QDateTime::currentDateTime().toString(QStringLiteral("h:mm AP")));
    entry.insert(QStringLiteral("timestamp"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    m_recentActivity.prepend(entry);
    while (m_recentActivity.size() > 8)
        m_recentActivity.removeLast();
    emit activityChanged();
}

void StorageManager::samplePerformanceTelemetry()
{
    QFile file(QStringLiteral("/proc/diskstats"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QVariantMap telemetry;
        telemetry.insert(QStringLiteral("available"), false);
        telemetry.insert(QStringLiteral("readMBps"), 0.0);
        telemetry.insert(QStringLiteral("writeMBps"), 0.0);
        telemetry.insert(QStringLiteral("iops"), 0.0);
        telemetry.insert(QStringLiteral("latencyMs"), 0.0);
        telemetry.insert(QStringLiteral("busyPercent"), 0.0);
        telemetry.insert(QStringLiteral("activeIo"), 0);
        if (m_performanceTelemetry != telemetry) {
            m_performanceTelemetry = telemetry;
            emit performanceTelemetryChanged();
        }
        return;
    }

    QSet<QString> names;
    for (const QVariant &value : m_devices) {
        const QVariantMap device = value.toMap();
        QString name = device.value(QStringLiteral("kname")).toString().trimmed();
        if (name.isEmpty())
            name = QFileInfo(device.value(QStringLiteral("path")).toString()).fileName();
        if (!name.isEmpty())
            names.insert(name);
    }

    quint64 reads = 0;
    quint64 sectorsRead = 0;
    quint64 readMs = 0;
    quint64 writes = 0;
    quint64 sectorsWritten = 0;
    quint64 writeMs = 0;
    quint64 activeIo = 0;
    quint64 ioMs = 0;
    int matchedDevices = 0;

    while (!file.atEnd()) {
        const QList<QByteArray> fields = file.readLine().simplified().split(' ');
        if (fields.size() < 14)
            continue;
        const QString name = QString::fromLocal8Bit(fields.at(2));
        if (!names.contains(name))
            continue;

        bool okReads = false;
        bool okSectorsRead = false;
        bool okReadMs = false;
        bool okWrites = false;
        bool okSectorsWritten = false;
        bool okWriteMs = false;
        bool okActive = false;
        bool okIoMs = false;

        const quint64 deviceReads = fields.at(3).toULongLong(&okReads);
        const quint64 deviceSectorsRead = fields.at(5).toULongLong(&okSectorsRead);
        const quint64 deviceReadMs = fields.at(6).toULongLong(&okReadMs);
        const quint64 deviceWrites = fields.at(7).toULongLong(&okWrites);
        const quint64 deviceSectorsWritten = fields.at(9).toULongLong(&okSectorsWritten);
        const quint64 deviceWriteMs = fields.at(10).toULongLong(&okWriteMs);
        const quint64 deviceActive = fields.at(11).toULongLong(&okActive);
        const quint64 deviceIoMs = fields.at(12).toULongLong(&okIoMs);

        if (!(okReads && okSectorsRead && okReadMs && okWrites && okSectorsWritten && okWriteMs && okActive && okIoMs))
            continue;

        reads += deviceReads;
        sectorsRead += deviceSectorsRead;
        readMs += deviceReadMs;
        writes += deviceWrites;
        sectorsWritten += deviceSectorsWritten;
        writeMs += deviceWriteMs;
        activeIo += deviceActive;
        ioMs += deviceIoMs;
        ++matchedDevices;
    }

    QVariantMap current;
    current.insert(QStringLiteral("reads"), QVariant::fromValue(reads));
    current.insert(QStringLiteral("sectorsRead"), QVariant::fromValue(sectorsRead));
    current.insert(QStringLiteral("readMs"), QVariant::fromValue(readMs));
    current.insert(QStringLiteral("writes"), QVariant::fromValue(writes));
    current.insert(QStringLiteral("sectorsWritten"), QVariant::fromValue(sectorsWritten));
    current.insert(QStringLiteral("writeMs"), QVariant::fromValue(writeMs));
    current.insert(QStringLiteral("ioMs"), QVariant::fromValue(ioMs));

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    double readMBps = 0.0;
    double writeMBps = 0.0;
    double iops = 0.0;
    double latencyMs = 0.0;
    double busyPercent = 0.0;

    if (!m_previousDiskStats.isEmpty() && m_previousDiskStatsMs > 0 && nowMs > m_previousDiskStatsMs) {
        const double elapsedSeconds = static_cast<double>(nowMs - m_previousDiskStatsMs) / 1000.0;
        const quint64 previousReads = m_previousDiskStats.value(QStringLiteral("reads")).toULongLong();
        const quint64 previousSectorsRead = m_previousDiskStats.value(QStringLiteral("sectorsRead")).toULongLong();
        const quint64 previousReadMs = m_previousDiskStats.value(QStringLiteral("readMs")).toULongLong();
        const quint64 previousWrites = m_previousDiskStats.value(QStringLiteral("writes")).toULongLong();
        const quint64 previousSectorsWritten = m_previousDiskStats.value(QStringLiteral("sectorsWritten")).toULongLong();
        const quint64 previousWriteMs = m_previousDiskStats.value(QStringLiteral("writeMs")).toULongLong();
        const quint64 previousIoMs = m_previousDiskStats.value(QStringLiteral("ioMs")).toULongLong();

        const quint64 deltaReads = reads >= previousReads ? reads - previousReads : 0;
        const quint64 deltaWrites = writes >= previousWrites ? writes - previousWrites : 0;
        const quint64 deltaSectorsRead = sectorsRead >= previousSectorsRead ? sectorsRead - previousSectorsRead : 0;
        const quint64 deltaSectorsWritten = sectorsWritten >= previousSectorsWritten ? sectorsWritten - previousSectorsWritten : 0;
        const quint64 deltaReadMs = readMs >= previousReadMs ? readMs - previousReadMs : 0;
        const quint64 deltaWriteMs = writeMs >= previousWriteMs ? writeMs - previousWriteMs : 0;
        const quint64 deltaIoMs = ioMs >= previousIoMs ? ioMs - previousIoMs : 0;
        const quint64 deltaOperations = deltaReads + deltaWrites;

        if (elapsedSeconds > 0.0) {
            readMBps = (static_cast<double>(deltaSectorsRead) * 512.0) / (1024.0 * 1024.0) / elapsedSeconds;
            writeMBps = (static_cast<double>(deltaSectorsWritten) * 512.0) / (1024.0 * 1024.0) / elapsedSeconds;
            iops = static_cast<double>(deltaOperations) / elapsedSeconds;
        }
        if (deltaOperations > 0)
            latencyMs = static_cast<double>(deltaReadMs + deltaWriteMs) / static_cast<double>(deltaOperations);
        if (nowMs > m_previousDiskStatsMs && matchedDevices > 0) {
            busyPercent = (static_cast<double>(deltaIoMs) /
                           static_cast<double>(nowMs - m_previousDiskStatsMs) /
                           static_cast<double>(matchedDevices)) * 100.0;
            busyPercent = qBound(0.0, busyPercent, 100.0);
        }
    }

    m_previousDiskStats = current;
    m_previousDiskStatsMs = nowMs;

    QVariantMap telemetry;
    telemetry.insert(QStringLiteral("available"), matchedDevices > 0);
    telemetry.insert(QStringLiteral("readMBps"), readMBps);
    telemetry.insert(QStringLiteral("writeMBps"), writeMBps);
    telemetry.insert(QStringLiteral("iops"), iops);
    telemetry.insert(QStringLiteral("latencyMs"), latencyMs);
    telemetry.insert(QStringLiteral("busyPercent"), busyPercent);
    telemetry.insert(QStringLiteral("activeIo"), QVariant::fromValue(activeIo));
    telemetry.insert(QStringLiteral("deviceCount"), matchedDevices);
    telemetry.insert(QStringLiteral("sampledAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    m_performanceTelemetry = telemetry;
    emit performanceTelemetryChanged();
}

int StorageManager::parseTemperatureFromSmartJson(const QByteArray &jsonData)
{
    QByteArray payload = jsonData;
    const int begin = payload.indexOf('{');
    const int end = payload.lastIndexOf('}');
    if (begin >= 0 && end > begin)
        payload = payload.mid(begin, end - begin + 1);

    const QJsonDocument document = QJsonDocument::fromJson(payload);
    if (!document.isObject())
        return -1;

    const QJsonObject object = document.object();
    auto validTemperature = [](double value) -> int {
        if (!qIsFinite(value) || value < -20.0 || value > 125.0)
            return -1;
        return qRound(value);
    };

    const QJsonValue temperatureValue = object.value(QStringLiteral("temperature"));
    if (temperatureValue.isObject()) {
        const QJsonObject temperature = temperatureValue.toObject();
        if (temperature.contains(QStringLiteral("current"))) {
            const int parsed = validTemperature(temperature.value(QStringLiteral("current")).toDouble(-999.0));
            if (parsed >= -20)
                return parsed;
        }
    } else if (temperatureValue.isDouble()) {
        const int parsed = validTemperature(temperatureValue.toDouble(-999.0));
        if (parsed >= -20)
            return parsed;
    }

    const QStringList objectKeys = {
        QStringLiteral("nvme_smart_health_information_log"),
        QStringLiteral("scsi_temperature")
    };
    for (const QString &key : objectKeys) {
        const QJsonObject section = object.value(key).toObject();
        if (section.isEmpty())
            continue;
        const QStringList temperatureKeys = {
            QStringLiteral("temperature"),
            QStringLiteral("current")
        };
        for (const QString &temperatureKey : temperatureKeys) {
            if (!section.contains(temperatureKey))
                continue;
            const int parsed = validTemperature(section.value(temperatureKey).toDouble(-999.0));
            if (parsed >= -20)
                return parsed;
        }
    }

    const QJsonArray attributes = object.value(QStringLiteral("ata_smart_attributes"))
                                      .toObject()
                                      .value(QStringLiteral("table"))
                                      .toArray();
    for (const QJsonValue &value : attributes) {
        const QJsonObject attribute = value.toObject();
        const QString name = attribute.value(QStringLiteral("name")).toString().toLower();
        if (!name.contains(QStringLiteral("temp")))
            continue;

        const QJsonObject raw = attribute.value(QStringLiteral("raw")).toObject();
        const QJsonValue rawValue = raw.value(QStringLiteral("value"));
        if (rawValue.isDouble()) {
            const int parsed = validTemperature(rawValue.toDouble(-999.0));
            if (parsed >= -20)
                return parsed;
        }

        const QString rawText = raw.value(QStringLiteral("string")).toString();
        const QRegularExpressionMatch match = QRegularExpression(QStringLiteral("(-?\\d{1,3})")).match(rawText);
        if (match.hasMatch()) {
            const int parsed = validTemperature(match.captured(1).toDouble());
            if (parsed >= -20)
                return parsed;
        }
    }

    const QString text = QString::fromUtf8(jsonData);
    const QStringList temperaturePatterns = {
        QStringLiteral("(?:Temperature_Celsius|Temperature_Internal|Airflow_Temperature_Cel)\\s+[^\\n]*?(-?\\d{1,3})(?:\\s|$)"),
        QStringLiteral("Current Drive Temperature[^0-9-]*(-?\\d{1,3})"),
        QStringLiteral("Temperature:[^0-9-]*(-?\\d{1,3})")
    };
    for (const QString &pattern : temperaturePatterns) {
        const QRegularExpressionMatch match = QRegularExpression(pattern, QRegularExpression::CaseInsensitiveOption).match(text);
        if (!match.hasMatch())
            continue;
        const int parsed = validTemperature(match.captured(1).toDouble());
        if (parsed >= -20)
            return parsed;
    }

    return -1;
}

int StorageManager::probeSysfsTemperature(const QVariantMap &device) const
{
#ifdef Q_OS_LINUX
    QString kname = device.value(QStringLiteral("kname")).toString().trimmed();
    if (kname.isEmpty())
        kname = QFileInfo(device.value(QStringLiteral("path")).toString()).fileName();
    if (kname.isEmpty())
        return -1;

    const QString blockRoot = QStringLiteral("/sys/class/block/") + kname;
    QStringList roots;
    const QString deviceRoot = QFileInfo(blockRoot + QStringLiteral("/device")).canonicalFilePath();
    const QString canonicalBlock = QFileInfo(blockRoot).canonicalFilePath();
    if (!deviceRoot.isEmpty())
        roots << deviceRoot;
    if (!canonicalBlock.isEmpty() && !roots.contains(canonicalBlock))
        roots << canonicalBlock;

    for (const QString &root : roots) {
        QDirIterator iterator(root,
                              QStringList{QStringLiteral("temp*_input")},
                              QDir::Files,
                              QDirIterator::Subdirectories);
        int inspected = 0;
        while (iterator.hasNext() && inspected < 96) {
            ++inspected;
            QFile file(iterator.next());
            if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
                continue;
            bool ok = false;
            double value = QString::fromUtf8(file.readAll()).trimmed().toDouble(&ok);
            if (!ok)
                continue;
            if (qAbs(value) > 1000.0)
                value /= 1000.0;
            if (value >= -20.0 && value <= 125.0)
                return qRound(value);
        }
    }
#else
    Q_UNUSED(device)
#endif
    return -1;
}

int StorageManager::probeTemperature(const QVariantMap &device) const
{
    const int sysfsTemperature = probeSysfsTemperature(device);
    if (sysfsTemperature >= -20)
        return sysfsTemperature;

    const QString smartctl = executable(QStringLiteral("smartctl"));
    const QString target = cleanDevicePath(device.value(QStringLiteral("path")).toString());
    if (smartctl.isEmpty() || target.isEmpty())
        return -1;

    int exitCode = -1;
    QByteArray output = runBlocking(
        smartctl,
        {QStringLiteral("-a"), QStringLiteral("-j"), target},
        3500,
        &exitCode);
    int temperature = parseTemperatureFromSmartJson(output);
    if (temperature >= -20)
        return temperature;

    // A common reason USB disks expose no temperature through the default
    // command is a SAT bridge. Try one explicit SAT passthrough before giving
    // up, rather than running a long matrix of probes on every refresh.
    const QString transport = device.value(QStringLiteral("transport")).toString().trimmed().toLower();
    if (transport == QStringLiteral("usb")) {
        output = runBlocking(
            smartctl,
            {QStringLiteral("-a"), QStringLiteral("-j"), QStringLiteral("-d"), QStringLiteral("sat"), target},
            3500,
            &exitCode);
        temperature = parseTemperatureFromSmartJson(output);
        if (temperature >= -20)
            return temperature;
    }

    return -1;
}

void StorageManager::refreshTemperatureReadings(const QVariantList &devices)
{
    for (const QVariant &value : devices) {
        const QVariantMap device = value.toMap();
        if (deviceType(device) != QStringLiteral("disk"))
            continue;

        const QString path = cleanDevicePath(device.value(QStringLiteral("path")).toString());
        if (path.isEmpty())
            continue;

        const int temperature = probeTemperature(device);
        if (temperature < -20)
            continue;

        QVariantMap smart = m_smartResults.value(path);
        smart.insert(QStringLiteral("temperature"), temperature);
        smart.insert(QStringLiteral("temperatureSource"), QStringLiteral("AUTO"));
        if (!smart.contains(QStringLiteral("status")))
            smart.insert(QStringLiteral("status"), QStringLiteral("NOT CHECKED"));
        m_smartResults.insert(path, smart);
    }
}

void StorageManager::refreshDevices()
{
    if (m_busy)
        return;

    QSet<QString> previousPaths;
    for (const QVariant &value : m_devices) {
        const QString path = value.toMap().value(QStringLiteral("path")).toString();
        if (!path.isEmpty())
            previousPaths.insert(path);
    }

    const QString lsblk = executable(QStringLiteral("lsblk"));
    if (lsblk.isEmpty()) {
        m_devices.clear();
        m_flatDevices.clear();
        m_lastMessage = QStringLiteral("lsblk is not installed.");
        emit devicesChanged();
        emit operationChanged();
        return;
    }

    int exitCode = -1;
    const QByteArray output = runBlocking(
        lsblk,
        {QStringLiteral("--json"), QStringLiteral("--bytes"), QStringLiteral("--paths"),
         QStringLiteral("-o"),
         QStringLiteral("NAME,KNAME,PATH,TYPE,SIZE,FSTYPE,FSVER,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL,VENDOR,SERIAL,TRAN,RM,RO,HOTPLUG,STATE,ROTA,PKNAME")},
        8000,
        &exitCode);

    const QJsonDocument document = QJsonDocument::fromJson(output);
    if (exitCode != 0 || !document.isObject()) {
        m_lastMessage = QStringLiteral("Unable to read block-device inventory.");
        emit operationChanged();
        return;
    }

    const QVariantList rawDevices = document.object().value(QStringLiteral("blockdevices")).toArray().toVariantList();
    QVariantList parsed;
    QString detectedSystemDisk;

    for (const QVariant &raw : rawDevices) {
        bool containsRoot = false;
        QVariantMap device = parseLsblkNode(raw.toMap(), QString(), &containsRoot);
        if (device.isEmpty())
            continue;
        parsed << device;
        if (containsRoot)
            detectedSystemDisk = device.value(QStringLiteral("path")).toString();
    }

    m_systemDisk = detectedSystemDisk;

    std::function<void(QVariantMap &, bool)> markProtected = [&](QVariantMap &device, bool parentProtected) {
        const QString path = device.value(QStringLiteral("path")).toString();
        const QStringList mounts = device.value(QStringLiteral("mountPoints")).toStringList();
        const bool rootMounted = mounts.contains(QStringLiteral("/")) || mounts.contains(QStringLiteral("/boot")) || mounts.contains(QStringLiteral("/boot/firmware"));
        const bool protectedValue = parentProtected || rootMounted || (!m_systemDisk.isEmpty() && path == m_systemDisk);
        device.insert(QStringLiteral("system"), protectedValue);
        device.insert(QStringLiteral("protected"), protectedValue || variantBool(device, QStringLiteral("readOnly")));

        QVariantList children = device.value(QStringLiteral("children")).toList();
        for (QVariant &childVariant : children) {
            QVariantMap child = childVariant.toMap();
            markProtected(child, protectedValue);
            childVariant = child;
        }
        device.insert(QStringLiteral("children"), children);
    };

    for (QVariant &variant : parsed) {
        QVariantMap device = variant.toMap();
        markProtected(device, false);
        variant = device;
    }

    m_devices = parsed;
    rebuildFlatDeviceIndex();
    refreshTemperatureReadings(m_devices);
    QVariantList smartUpdated = m_devices;
    updateSmartFieldsRecursive(smartUpdated);
    m_devices = smartUpdated;
    rebuildFlatDeviceIndex();

    QSet<QString> currentPaths;
    for (const QVariant &value : m_devices) {
        const QVariantMap device = value.toMap();
        const QString path = device.value(QStringLiteral("path")).toString();
        if (!path.isEmpty())
            currentPaths.insert(path);
    }

    if (previousPaths.isEmpty()) {
        appendActivity(QStringLiteral("inventory"),
                       QStringLiteral("Storage inventory ready"),
                       QStringLiteral("%1 physical storage device%2 detected.")
                           .arg(currentPaths.size())
                           .arg(currentPaths.size() == 1 ? QString() : QStringLiteral("s")),
                       QStringLiteral("success"));
    } else {
        for (const QString &path : currentPaths) {
            if (previousPaths.contains(path))
                continue;
            const QVariantMap device = findDevice(path);
            const QString name = device.value(QStringLiteral("model")).toString().trimmed();
            appendActivity(QStringLiteral("connected"),
                           QStringLiteral("Storage connected"),
                           name.isEmpty() ? path : QStringLiteral("%1 • %2").arg(name, path),
                           QStringLiteral("success"));
        }
        for (const QString &path : previousPaths) {
            if (!currentPaths.contains(path))
                appendActivity(QStringLiteral("disconnected"),
                               QStringLiteral("Storage disconnected"),
                               path,
                               QStringLiteral("warning"));
        }
    }

    m_previousDiskStats.clear();
    m_previousDiskStatsMs = 0;
    samplePerformanceTelemetry();
    m_lastMessage = QStringLiteral("Storage inventory refreshed.");
    emit devicesChanged();
    emit operationChanged();
}

QVariantMap StorageManager::parseLsblkNode(const QVariantMap &node,
                                           const QString &parentPath,
                                           bool *containsRoot)
{
    QVariantMap resultMap;
    const QString path = cleanDevicePath(node.value(QStringLiteral("path"), node.value(QStringLiteral("name"))).toString());
    if (path.isEmpty())
        return resultMap;

    const QString type = node.value(QStringLiteral("type")).toString().trimmed().toLower();
    if (type == QStringLiteral("loop") || type == QStringLiteral("rom"))
        return resultMap;

    const quint64 sizeBytes = node.value(QStringLiteral("size")).toULongLong();
    QStringList mountPoints = stringListFromJson(node.value(QStringLiteral("mountpoints")));
    mountPoints.removeAll(QString());

    bool rootHere = mountPoints.contains(QStringLiteral("/")) ||
                    mountPoints.contains(QStringLiteral("/boot")) ||
                    mountPoints.contains(QStringLiteral("/boot/firmware"));

    QVariantList children;
    const QVariantList childNodes = node.value(QStringLiteral("children")).toList();
    for (const QVariant &childVariant : childNodes) {
        bool childRoot = false;
        QVariantMap child = parseLsblkNode(childVariant.toMap(), path, &childRoot);
        if (!child.isEmpty())
            children << child;
        rootHere = rootHere || childRoot;
    }

    if (containsRoot)
        *containsRoot = rootHere;

    resultMap.insert(QStringLiteral("path"), path);
    resultMap.insert(QStringLiteral("name"), QFileInfo(path).fileName());
    resultMap.insert(QStringLiteral("kname"), node.value(QStringLiteral("kname")).toString());
    resultMap.insert(QStringLiteral("type"), type);
    resultMap.insert(QStringLiteral("sizeBytes"), QVariant::fromValue(sizeBytes));
    resultMap.insert(QStringLiteral("size"), humanBytes(sizeBytes));
    resultMap.insert(QStringLiteral("filesystem"), node.value(QStringLiteral("fstype")).toString());
    resultMap.insert(QStringLiteral("filesystemVersion"), node.value(QStringLiteral("fsver")).toString());
    resultMap.insert(QStringLiteral("label"), node.value(QStringLiteral("label")).toString());
    resultMap.insert(QStringLiteral("uuid"), node.value(QStringLiteral("uuid")).toString());
    resultMap.insert(QStringLiteral("partUuid"), node.value(QStringLiteral("partuuid")).toString());
    resultMap.insert(QStringLiteral("mountPoints"), mountPoints);
    resultMap.insert(QStringLiteral("mountText"), mountPoints.join(QStringLiteral(", ")));

    quint64 filesystemBytes = 0;
    quint64 availableBytes = 0;
    quint64 freeBytes = 0;
    for (const QString &mountPoint : mountPoints) {
        QStorageInfo storage(mountPoint);
        if (!storage.isValid() || !storage.isReady())
            continue;
        filesystemBytes = static_cast<quint64>(qMax<qint64>(qint64{0}, storage.bytesTotal()));
        availableBytes = static_cast<quint64>(qMax<qint64>(qint64{0}, storage.bytesAvailable()));
        freeBytes = static_cast<quint64>(qMax<qint64>(qint64{0}, storage.bytesFree()));
        break;
    }
    const quint64 usedBytes = filesystemBytes > availableBytes ? filesystemBytes - availableBytes : 0;
    const int usagePercent = filesystemBytes > 0
            ? static_cast<int>(qMin<quint64>(quint64{100}, usedBytes * quint64{100} / filesystemBytes))
            : 0;
    resultMap.insert(QStringLiteral("filesystemBytes"), QVariant::fromValue(filesystemBytes));
    resultMap.insert(QStringLiteral("usedBytes"), QVariant::fromValue(usedBytes));
    resultMap.insert(QStringLiteral("availableBytes"), QVariant::fromValue(availableBytes));
    resultMap.insert(QStringLiteral("freeBytes"), QVariant::fromValue(freeBytes));
    resultMap.insert(QStringLiteral("used"), humanBytes(usedBytes));
    resultMap.insert(QStringLiteral("available"), humanBytes(availableBytes));
    resultMap.insert(QStringLiteral("free"), humanBytes(freeBytes));
    resultMap.insert(QStringLiteral("usagePercent"), usagePercent);
    resultMap.insert(QStringLiteral("model"), node.value(QStringLiteral("model")).toString().trimmed());
    resultMap.insert(QStringLiteral("vendor"), node.value(QStringLiteral("vendor")).toString().trimmed());
    resultMap.insert(QStringLiteral("serial"), node.value(QStringLiteral("serial")).toString().trimmed());
    resultMap.insert(QStringLiteral("transport"), node.value(QStringLiteral("tran")).toString().trimmed());
    resultMap.insert(QStringLiteral("removable"), node.value(QStringLiteral("rm")).toInt() != 0);
    resultMap.insert(QStringLiteral("readOnly"), node.value(QStringLiteral("ro")).toInt() != 0);
    resultMap.insert(QStringLiteral("hotplug"), node.value(QStringLiteral("hotplug")).toInt() != 0);
    resultMap.insert(QStringLiteral("state"), node.value(QStringLiteral("state")).toString());
    resultMap.insert(QStringLiteral("rotational"), node.value(QStringLiteral("rota")).toInt() != 0);
    resultMap.insert(QStringLiteral("parentPath"), parentPath);
    resultMap.insert(QStringLiteral("children"), children);
    resultMap.insert(QStringLiteral("containsRoot"), rootHere);
    return resultMap;
}

void StorageManager::rebuildFlatDeviceIndex()
{
    m_flatDevices.clear();
    for (const QVariant &device : m_devices)
        indexDevice(device.toMap());
}

void StorageManager::indexDevice(const QVariantMap &device)
{
    const QString path = device.value(QStringLiteral("path")).toString();
    if (!path.isEmpty())
        m_flatDevices.insert(path, device);
    for (const QVariant &child : device.value(QStringLiteral("children")).toList())
        indexDevice(child.toMap());
}

QVariantMap StorageManager::findDevice(const QString &path) const
{
    return m_flatDevices.value(cleanDevicePath(path));
}

QVariantMap StorageManager::findTopLevelDevice(const QString &path) const
{
    QVariantMap device = findDevice(path);
    while (!device.isEmpty() && !device.value(QStringLiteral("parentPath")).toString().isEmpty())
        device = findDevice(device.value(QStringLiteral("parentPath")).toString());
    return device;
}

QStringList StorageManager::mountedPaths(const QVariantMap &device) const
{
    return device.value(QStringLiteral("mountPoints")).toStringList();
}

QStringList StorageManager::mountedPathsRecursive(const QVariantMap &device) const
{
    QStringList values = mountedPaths(device);
    for (const QVariant &child : device.value(QStringLiteral("children")).toList())
        values.append(mountedPathsRecursive(child.toMap()));
    values.removeDuplicates();
    return values;
}


QVariantMap StorageManager::mountableVolume(const QString &path) const
{
    QVariantMap device = findDevice(path);
    if (device.isEmpty())
        return {};
    if (deviceType(device) != QStringLiteral("disk"))
        return device;
    const QVariantList children = device.value(QStringLiteral("children")).toList();
    for (const QVariant &childValue : children) {
        const QVariantMap child = childValue.toMap();
        if (!child.value(QStringLiteral("filesystem")).toString().trimmed().isEmpty())
            return child;
    }
    return device;
}

QString StorageManager::suggestedMountName(const QString &devicePath) const
{
    const QVariantMap device = mountableVolume(devicePath);
    QString name = device.value(QStringLiteral("label")).toString().trimmed();
    if (name.isEmpty())
        name = device.value(QStringLiteral("model")).toString().trimmed();
    if (name.isEmpty())
        name = device.value(QStringLiteral("name")).toString().trimmed();
    name = sanitizedMountName(name);
    return name.isEmpty() ? QStringLiteral("Media") : name;
}

QVariantMap StorageManager::validateMount(const QString &devicePath, const QString &mountName) const
{
    if (!hasStoragePrivileges())
        return result(false, QStringLiteral("NeutronOS does not have permission to mount devices."));
    const QVariantMap selected = findDevice(devicePath);
    const QVariantMap device = mountableVolume(devicePath);
    if (selected.isEmpty() || device.isEmpty())
        return result(false, QStringLiteral("The selected block device is no longer present."));
    if (isProtectedDevice(selected) || isProtectedDevice(device))
        return result(false, QStringLiteral("The active system device cannot be mounted through Storage."));
    if (!mountedPathsRecursive(device).isEmpty())
        return result(false, QStringLiteral("The selected volume is already mounted."));
    if (device.value(QStringLiteral("filesystem")).toString().trimmed().isEmpty())
        return result(false, QStringLiteral("No mountable filesystem was detected. Formatting is a separate destructive action."));
    const QString name = sanitizedMountName(mountName);
    if (name.isEmpty())
        return result(false, QStringLiteral("Enter a mount name using letters, numbers, spaces, dashes, underscores, or periods."));
    const QString mountPoint = QDir(QStringLiteral("/mnt")).filePath(name);
    const QFileInfo mountInfo(mountPoint);
    if (mountInfo.exists() && !mountInfo.isDir())
        return result(false, QStringLiteral("A non-directory item already uses that mount name."));
    if (mountInfo.isDir()) {
        QStorageInfo storage(mountPoint);
        if (storage.isValid() && storage.isReady() && storage.rootPath() == mountPoint)
            return result(false, QStringLiteral("That mount name is already in use."));
        QDir directory(mountPoint);
        if (!directory.entryList(QDir::AllEntries | QDir::NoDotAndDotDot).isEmpty())
            return result(false, QStringLiteral("The selected mount directory is not empty."));
    }
    QVariantMap ok = result(true, QStringLiteral("Ready to mount %1 at %2.")
                            .arg(device.value(QStringLiteral("path")).toString(), mountPoint));
    ok.insert(QStringLiteral("devicePath"), device.value(QStringLiteral("path")));
    ok.insert(QStringLiteral("mountPoint"), mountPoint);
    ok.insert(QStringLiteral("mountName"), name);
    return ok;
}

bool StorageManager::mountDevice(const QString &devicePath, const QString &mountName)
{
    const QVariantMap validation = validateMount(devicePath, mountName);
    if (!validation.value(QStringLiteral("ok")).toBool()) {
        m_lastMessage = validation.value(QStringLiteral("message")).toString();
        emit operationChanged();
        return false;
    }
    const QString targetDevice = validation.value(QStringLiteral("devicePath")).toString();
    const QString mountPoint = validation.value(QStringLiteral("mountPoint")).toString();
    const QString install = executable(QStringLiteral("install"));
    const QString mount = executable(QStringLiteral("mount"));
    if (install.isEmpty() || mount.isEmpty()) {
        m_lastMessage = QStringLiteral("Required mount utilities are not installed.");
        emit operationChanged();
        return false;
    }
    QList<CommandStep> steps;
    steps << CommandStep{install, {QStringLiteral("-d"), QStringLiteral("-m"), QStringLiteral("0755"), mountPoint},
                         QStringLiteral("Creating mount point %1").arg(mountPoint), false};
    const QVariantMap device = findDevice(targetDevice);
    QString options = QStringLiteral("nosuid,nodev");
    if (variantBool(device, QStringLiteral("readOnly")))
        options += QStringLiteral(",ro");
    steps << CommandStep{mount, {QStringLiteral("-o"), options, targetDevice, mountPoint},
                         QStringLiteral("Mounting %1").arg(targetDevice), false};
    return startSteps(QStringLiteral("MOUNT"), targetDevice, steps);
}

QVariantMap StorageManager::validateUnmount(const QString &devicePath) const
{
    if (!hasStoragePrivileges())
        return result(false, QStringLiteral("NeutronOS does not have permission to unmount devices."));
    const QVariantMap selected = findDevice(devicePath);
    if (selected.isEmpty())
        return result(false, QStringLiteral("The selected block device is no longer present."));
    if (isProtectedDevice(selected))
        return result(false, QStringLiteral("The active system device cannot be unmounted."));
    const QStringList mounts = mountedPathsRecursive(selected);
    if (mounts.isEmpty())
        return result(false, QStringLiteral("The selected device is not mounted."));
    QVariantMap ok = result(true, QStringLiteral("Ready to unmount %1.").arg(mounts.join(QStringLiteral(", "))));
    ok.insert(QStringLiteral("mountPoints"), mounts);
    return ok;
}

bool StorageManager::unmountDevice(const QString &devicePath)
{
    const QVariantMap validation = validateUnmount(devicePath);
    if (!validation.value(QStringLiteral("ok")).toBool()) {
        m_lastMessage = validation.value(QStringLiteral("message")).toString();
        emit operationChanged();
        return false;
    }
    QStringList mounts = validation.value(QStringLiteral("mountPoints")).toStringList();
    std::sort(mounts.begin(), mounts.end(), [](const QString &a, const QString &b) { return a.size() > b.size(); });
    const QString sync = executable(QStringLiteral("sync"));
    const QString umount = executable(QStringLiteral("umount"));
    const QString rmdir = executable(QStringLiteral("rmdir"));
    if (umount.isEmpty()) {
        m_lastMessage = QStringLiteral("The unmount utility is not installed.");
        emit operationChanged();
        return false;
    }
    QList<CommandStep> steps;
    if (!sync.isEmpty())
        steps << CommandStep{sync, {}, QStringLiteral("Flushing pending writes"), false};
    for (const QString &mountPoint : mounts) {
        steps << CommandStep{umount, {mountPoint}, QStringLiteral("Unmounting %1").arg(mountPoint), false};
        if (!rmdir.isEmpty() && mountPoint.startsWith(QStringLiteral("/mnt/")))
            steps << CommandStep{rmdir, {mountPoint}, QStringLiteral("Removing empty mount point"), true};
    }
    return startSteps(QStringLiteral("UNMOUNT"), devicePath, steps);
}

bool StorageManager::ejectDevice(const QString &devicePath)
{
    const QVariantMap selected = findDevice(devicePath);
    const QVariantMap top = findTopLevelDevice(devicePath);
    if (selected.isEmpty() || top.isEmpty() || isProtectedDevice(top)) {
        m_lastMessage = QStringLiteral("The selected device cannot be safely ejected.");
        emit operationChanged();
        return false;
    }
    QStringList mounts = mountedPathsRecursive(top);
    std::sort(mounts.begin(), mounts.end(), [](const QString &a, const QString &b) { return a.size() > b.size(); });
    const QString sync = executable(QStringLiteral("sync"));
    const QString umount = executable(QStringLiteral("umount"));
    const QString rmdir = executable(QStringLiteral("rmdir"));
    const QString udisksctl = executable(QStringLiteral("udisksctl"));
    const QString eject = executable(QStringLiteral("eject"));
    QList<CommandStep> steps;
    if (!sync.isEmpty())
        steps << CommandStep{sync, {}, QStringLiteral("Flushing pending writes"), false};
    for (const QString &mountPoint : mounts) {
        if (!umount.isEmpty())
            steps << CommandStep{umount, {mountPoint}, QStringLiteral("Unmounting %1").arg(mountPoint), false};
        if (!rmdir.isEmpty() && mountPoint.startsWith(QStringLiteral("/mnt/")))
            steps << CommandStep{rmdir, {mountPoint}, QStringLiteral("Removing empty mount point"), true};
    }
    const QString topPath = top.value(QStringLiteral("path")).toString();
    if (!udisksctl.isEmpty())
        steps << CommandStep{udisksctl, {QStringLiteral("power-off"), QStringLiteral("-b"), topPath}, QStringLiteral("Powering off removable device"), false};
    else if (!eject.isEmpty())
        steps << CommandStep{eject, {topPath}, QStringLiteral("Ejecting removable device"), false};
    else {
        m_lastMessage = QStringLiteral("udisksctl or eject is required for safe device power-off.");
        emit operationChanged();
        return false;
    }
    return startSteps(QStringLiteral("EJECT"), topPath, steps);
}

bool StorageManager::isKnownBlockDevice(const QString &path) const
{
    return !findDevice(path).isEmpty();
}

bool StorageManager::isProtectedDevice(const QVariantMap &device) const
{
    return device.isEmpty() || variantBool(device, QStringLiteral("protected")) || variantBool(device, QStringLiteral("system"));
}

quint64 StorageManager::deviceSize(const QVariantMap &device) const
{
    return device.value(QStringLiteral("sizeBytes")).toULongLong();
}

QString StorageManager::deviceType(const QVariantMap &device) const
{
    return device.value(QStringLiteral("type")).toString().toLower();
}

QVariantMap StorageManager::result(bool ok, const QString &message) const
{
    return {{QStringLiteral("ok"), ok}, {QStringLiteral("message"), message}};
}

QVariantMap StorageManager::deviceDetails(const QString &devicePath) const
{
    QVariantMap device = findDevice(devicePath);
    if (device.isEmpty())
        return result(false, QStringLiteral("Device is not present."));
    device.insert(QStringLiteral("ok"), true);
    device.insert(QStringLiteral("systemDisk"), m_systemDisk);
    device.insert(QStringLiteral("smartctlAvailable"), smartctlAvailable());
    return device;
}

QVariantMap StorageManager::validateFormat(const QString &devicePath,
                                            const QString &filesystem) const
{
    if (m_busy)
        return result(false, QStringLiteral("Another storage operation is already running."));
    if (!hasStoragePrivileges())
        return result(false, QStringLiteral("Formatting requires the privileged neutronos.service runtime."));

    const QVariantMap device = findDevice(devicePath);
    if (device.isEmpty())
        return result(false, QStringLiteral("Select a connected block device."));
    if (isProtectedDevice(device) || isProtectedDevice(findTopLevelDevice(devicePath)))
        return result(false, QStringLiteral("The active system or boot device can never be formatted."));
    if (variantBool(device, QStringLiteral("readOnly")))
        return result(false, QStringLiteral("The selected device is read-only."));

    const QString type = deviceType(device);
    if (type != QStringLiteral("disk") && type != QStringLiteral("part"))
        return result(false, QStringLiteral("Only disks and partitions can be formatted."));

    const QString fs = normalizedFilesystem(filesystem);
    if (fs.isEmpty())
        return result(false, QStringLiteral("Choose a supported filesystem."));
    if (!supportedFilesystems().contains(fs))
        return result(false, QStringLiteral("The required filesystem utility is not installed."));

    return result(true, type == QStringLiteral("disk")
                         ? QStringLiteral("The entire selected disk will be erased and repartitioned.")
                         : QStringLiteral("The selected volume will be unmounted and erased."));
}

QVariantMap StorageManager::validateBootClone(const QString &targetDevice) const
{
    if (m_busy)
        return result(false, QStringLiteral("Another storage operation is already running."));
    if (!hasStoragePrivileges())
        return result(false, QStringLiteral("Boot cloning requires the privileged neutronos.service runtime."));

    const QVariantMap target = findDevice(targetDevice);
    if (target.isEmpty())
        return result(false, QStringLiteral("Select a connected target disk."));
    if (deviceType(target) != QStringLiteral("disk"))
        return result(false, QStringLiteral("Boot backup requires a whole target disk, not a partition."));
    if (m_systemDisk.isEmpty())
        return result(false, QStringLiteral("The active system disk could not be identified."));
    if (targetDevice == m_systemDisk || isProtectedDevice(target))
        return result(false, QStringLiteral("The active system disk cannot be used as the backup target."));
    if (variantBool(target, QStringLiteral("readOnly")))
        return result(false, QStringLiteral("The target disk is read-only."));

    const QVariantMap source = findDevice(m_systemDisk);
    if (source.isEmpty())
        return result(false, QStringLiteral("The active system disk is no longer present."));
    if (deviceSize(target) < deviceSize(source))
        return result(false, QStringLiteral("The target disk must be at least as large as the active system disk."));
    if (executable(QStringLiteral("dd")).isEmpty())
        return result(false, QStringLiteral("The dd utility is unavailable."));

    return result(true, QStringLiteral("The target disk will be completely overwritten with an exact bootable clone."));
}

QVariantMap StorageManager::validateImageFlash(const QString &imagePath,
                                               const QString &targetDevice) const
{
    if (m_busy)
        return result(false, QStringLiteral("Another storage operation is already running."));
    if (!hasStoragePrivileges())
        return result(false, QStringLiteral("Image flashing requires the privileged neutronos.service runtime."));

    QString cleanImage = imagePath.trimmed();
    if (cleanImage.startsWith(QStringLiteral("file://")))
        cleanImage = QUrl(cleanImage).toLocalFile();
    const QFileInfo imageInfo(cleanImage);
    if (!imageInfo.exists() || !imageInfo.isFile())
        return result(false, QStringLiteral("Select an existing image file."));

    const QString lower = imageInfo.fileName().toLower();
    const bool supported = lower.endsWith(QStringLiteral(".img")) ||
                           lower.endsWith(QStringLiteral(".iso")) ||
                           lower.endsWith(QStringLiteral(".img.xz")) ||
                           lower.endsWith(QStringLiteral(".xz")) ||
                           lower.endsWith(QStringLiteral(".img.gz")) ||
                           lower.endsWith(QStringLiteral(".gz")) ||
                           lower.endsWith(QStringLiteral(".zip"));
    if (!supported)
        return result(false, QStringLiteral("Supported images are .img, .iso, .xz, .gz, and .zip archives containing one image."));

    if (lower.endsWith(QStringLiteral(".xz")) && executable(QStringLiteral("xz")).isEmpty())
        return result(false, QStringLiteral("The xz utility is required for this image."));
    if (lower.endsWith(QStringLiteral(".gz")) && executable(QStringLiteral("gzip")).isEmpty())
        return result(false, QStringLiteral("The gzip utility is required for this image."));
    if (lower.endsWith(QStringLiteral(".zip")) && executable(QStringLiteral("unzip")).isEmpty())
        return result(false, QStringLiteral("The unzip utility is required for this image."));
    if (executable(QStringLiteral("dd")).isEmpty())
        return result(false, QStringLiteral("The dd utility is unavailable."));

    const QVariantMap target = findDevice(targetDevice);
    if (target.isEmpty())
        return result(false, QStringLiteral("Select a connected target disk."));
    if (deviceType(target) != QStringLiteral("disk"))
        return result(false, QStringLiteral("Image flashing requires a whole target disk, not a partition."));
    if (targetDevice == m_systemDisk || isProtectedDevice(target))
        return result(false, QStringLiteral("The active system or boot device can never be flashed."));
    if (variantBool(target, QStringLiteral("readOnly")))
        return result(false, QStringLiteral("The target disk is read-only."));

    QString archiveMember;
    const quint64 expandedBytes = imageExpandedSize(cleanImage, &archiveMember);
    if (expandedBytes == 0)
        return result(false, QStringLiteral("The expanded image size could not be read. The archive may be invalid or contain no .img/.iso file."));
    if (deviceSize(target) < expandedBytes)
        return result(false, QStringLiteral("The target disk is smaller than the expanded image."));

    QVariantMap response = result(true, QStringLiteral("The selected target disk will be completely overwritten."));
    response.insert(QStringLiteral("imagePath"), imageInfo.absoluteFilePath());
    response.insert(QStringLiteral("imageName"), imageInfo.fileName());
    response.insert(QStringLiteral("imageBytes"), QVariant::fromValue(expandedBytes));
    response.insert(QStringLiteral("imageSize"), humanBytes(expandedBytes));
    response.insert(QStringLiteral("targetPath"), targetDevice);
    response.insert(QStringLiteral("targetSize"), target.value(QStringLiteral("size")));
    response.insert(QStringLiteral("archiveMember"), archiveMember);
    return response;
}

bool StorageManager::runSmartCheck(const QString &devicePath)
{
    if (m_busy)
        return false;
    if (!hasStoragePrivileges()) {
        m_lastMessage = QStringLiteral("SMART diagnostics require the privileged neutronos.service runtime.");
        emit operationChanged();
        return false;
    }

    const QVariantMap top = findTopLevelDevice(devicePath);
    const QString target = top.value(QStringLiteral("path")).toString();
    if (target.isEmpty() || deviceType(top) != QStringLiteral("disk")) {
        m_lastMessage = QStringLiteral("SMART checks require a physical disk.");
        emit operationChanged();
        return false;
    }

    const QString smartctl = executable(QStringLiteral("smartctl"));
    if (smartctl.isEmpty()) {
        m_lastMessage = QStringLiteral("smartctl is not installed. Install smartmontools to enable health checks.");
        emit operationChanged();
        return false;
    }

    m_smartTarget = target;
    return startSteps(QStringLiteral("SMART CHECK"), target,
                      {{smartctl,
                        {QStringLiteral("-a"), QStringLiteral("-j"), target},
                        QStringLiteral("Reading drive health data"),
                        true}});
}

bool StorageManager::runHealthCheck(const QString &devicePath)
{
    if (m_busy)
        return false;

    const QVariantMap top = findTopLevelDevice(devicePath);
    const QString target = top.value(QStringLiteral("path")).toString();
    if (target.isEmpty() || deviceType(top) != QStringLiteral("disk")) {
        m_lastMessage = QStringLiteral("Health checks require a physical storage disk.");
        emit operationChanged();
        return false;
    }

    if (smartctlAvailable())
        return runSmartCheck(target);

    bool attention = false;
    QStringList findings;

    const QString state = top.value(QStringLiteral("state")).toString().trimmed().toLower();
    if (!state.isEmpty() && state != QStringLiteral("running") &&
        state != QStringLiteral("live") && state != QStringLiteral("active")) {
        attention = true;
        findings << QStringLiteral("Device state: %1").arg(state.toUpper());
    }

    const QStringList mounts = mountedPathsRecursive(top);
    for (const QString &mountPoint : mounts) {
        QStorageInfo storage(mountPoint);
        if (!storage.isValid() || !storage.isReady()) {
            attention = true;
            findings << QStringLiteral("Mount unavailable: %1").arg(mountPoint);
        }
    }

    QVariantMap health = m_smartResults.value(target);
    health.insert(QStringLiteral("checked"), true);
    health.insert(QStringLiteral("timestamp"), QDateTime::currentDateTime().toString(Qt::ISODate));
    health.insert(QStringLiteral("healthMode"), QStringLiteral("BASIC"));
    health.insert(QStringLiteral("status"), attention ? QStringLiteral("ATTENTION") : QStringLiteral("PASSED"));

    const int temperature = probeTemperature(top);
    if (temperature >= -20) {
        health.insert(QStringLiteral("temperature"), temperature);
        health.insert(QStringLiteral("temperatureSource"), QStringLiteral("AUTO"));
    }

    m_smartResults.insert(target, health);

    QVariantList updated = m_devices;
    updateSmartFieldsRecursive(updated);
    m_devices = updated;
    rebuildFlatDeviceIndex();

    m_lastMessage = attention
            ? QStringLiteral("Basic storage health check found items that need review: %1").arg(findings.join(QStringLiteral(" • ")))
            : QStringLiteral("Basic storage health check passed. Device presence and mounted filesystems are ready.");

    appendActivity(attention ? QStringLiteral("health-warning") : QStringLiteral("health-check"),
                   attention ? QStringLiteral("Storage health needs attention")
                             : QStringLiteral("Storage health check passed"),
                   QStringLiteral("%1 • %2").arg(target, m_lastMessage),
                   attention ? QStringLiteral("warning") : QStringLiteral("success"));

    emit devicesChanged();
    emit operationChanged();
    return true;
}

bool StorageManager::formatDevice(const QString &devicePath,
                                  const QString &filesystem,
                                  const QString &label)
{
    const QVariantMap validation = validateFormat(devicePath, filesystem);
    if (!validation.value(QStringLiteral("ok")).toBool()) {
        m_lastMessage = validation.value(QStringLiteral("message")).toString();
        emit operationChanged();
        return false;
    }

    const QVariantMap device = findDevice(devicePath);
    const QString fs = normalizedFilesystem(filesystem);
    const QString cleanLabel = sanitizedLabel(label, fs);
    QList<CommandStep> steps;

    QStringList mounts = mountedPathsRecursive(device);
    std::sort(mounts.begin(), mounts.end(), [](const QString &a, const QString &b) { return a.size() > b.size(); });
    const QString umount = executable(QStringLiteral("umount"));
    for (const QString &mountPoint : mounts) {
        if (!mountPoint.isEmpty() && !umount.isEmpty())
            steps << CommandStep{umount, {mountPoint}, QStringLiteral("Unmounting %1").arg(mountPoint), false};
    }

    QString targetVolume = devicePath;
    if (deviceType(device) == QStringLiteral("disk")) {
        const QString wipefs = executable(QStringLiteral("wipefs"));
        const QString parted = executable(QStringLiteral("parted"));
        const QString partprobe = executable(QStringLiteral("partprobe"));
        const QString udevadm = executable(QStringLiteral("udevadm"));
        if (wipefs.isEmpty() || parted.isEmpty() || partprobe.isEmpty()) {
            m_lastMessage = QStringLiteral("Formatting a whole disk requires wipefs, parted, and partprobe.");
            emit operationChanged();
            return false;
        }
        steps << CommandStep{wipefs, {QStringLiteral("-a"), devicePath}, QStringLiteral("Removing old filesystem signatures"), false};
        steps << CommandStep{parted, {QStringLiteral("-s"), devicePath, QStringLiteral("mklabel"), QStringLiteral("gpt")}, QStringLiteral("Creating GPT partition table"), false};
        steps << CommandStep{parted, {QStringLiteral("-s"), devicePath, QStringLiteral("mkpart"), QStringLiteral("primary"), QStringLiteral("1MiB"), QStringLiteral("100%")}, QStringLiteral("Creating storage volume"), false};
        steps << CommandStep{partprobe, {devicePath}, QStringLiteral("Refreshing partition table"), false};
        if (!udevadm.isEmpty())
            steps << CommandStep{udevadm, {QStringLiteral("settle")}, QStringLiteral("Waiting for the new volume"), false};
        targetVolume = firstPartitionPath(devicePath);
    } else {
        const QString wipefs = executable(QStringLiteral("wipefs"));
        if (!wipefs.isEmpty())
            steps << CommandStep{wipefs, {QStringLiteral("-a"), devicePath}, QStringLiteral("Removing old filesystem signatures"), false};
    }

    QString mkfs;
    QStringList arguments;
    if (fs == QStringLiteral("ext4")) {
        mkfs = executable(QStringLiteral("mkfs.ext4"));
        arguments << QStringLiteral("-F");
        if (!cleanLabel.isEmpty())
            arguments << QStringLiteral("-L") << cleanLabel;
    } else if (fs == QStringLiteral("exfat")) {
        mkfs = executable(QStringLiteral("mkfs.exfat"));
        arguments << QStringLiteral("-f");
        if (!cleanLabel.isEmpty())
            arguments << QStringLiteral("-L") << cleanLabel;
    } else if (fs == QStringLiteral("vfat")) {
        mkfs = executable(QStringLiteral("mkfs.vfat"));
        arguments << QStringLiteral("-F") << QStringLiteral("32");
        if (!cleanLabel.isEmpty())
            arguments << QStringLiteral("-n") << cleanLabel.toUpper();
    } else if (fs == QStringLiteral("btrfs")) {
        mkfs = executable(QStringLiteral("mkfs.btrfs"));
        arguments << QStringLiteral("-f");
        if (!cleanLabel.isEmpty())
            arguments << QStringLiteral("-L") << cleanLabel;
    }
    arguments << targetVolume;
    steps << CommandStep{mkfs, arguments, QStringLiteral("Creating %1 filesystem").arg(fs.toUpper()), false};

    return startSteps(QStringLiteral("FORMAT"), devicePath, steps);
}

bool StorageManager::cloneBootDevice(const QString &targetDevice)
{
    const QVariantMap validation = validateBootClone(targetDevice);
    if (!validation.value(QStringLiteral("ok")).toBool()) {
        m_lastMessage = validation.value(QStringLiteral("message")).toString();
        emit operationChanged();
        return false;
    }

    const QVariantMap target = findDevice(targetDevice);
    const QVariantMap source = findDevice(m_systemDisk);
    QList<CommandStep> steps;

    QStringList mounts = mountedPathsRecursive(target);
    std::sort(mounts.begin(), mounts.end(), [](const QString &a, const QString &b) { return a.size() > b.size(); });
    const QString umount = executable(QStringLiteral("umount"));
    for (const QString &mountPoint : mounts) {
        if (!mountPoint.isEmpty() && !umount.isEmpty())
            steps << CommandStep{umount, {mountPoint}, QStringLiteral("Unmounting target volume"), false};
    }

    const QString dd = executable(QStringLiteral("dd"));
    const QString sync = executable(QStringLiteral("sync"));
    steps << CommandStep{dd,
                         {QStringLiteral("if=%1").arg(m_systemDisk),
                          QStringLiteral("of=%1").arg(targetDevice),
                          QStringLiteral("bs=16M"),
                          QStringLiteral("iflag=fullblock"),
                          QStringLiteral("conv=fsync"),
                          QStringLiteral("status=progress")},
                         QStringLiteral("Cloning the active boot disk"),
                         false};
    if (!sync.isEmpty())
        steps << CommandStep{sync, {}, QStringLiteral("Flushing backup data"), false};

    return startSteps(QStringLiteral("BOOT BACKUP"), targetDevice, steps, deviceSize(source), m_systemDisk);
}

bool StorageManager::flashImage(const QString &imagePath,
                                const QString &targetDevice)
{
    const QVariantMap validation = validateImageFlash(imagePath, targetDevice);
    if (!validation.value(QStringLiteral("ok")).toBool()) {
        m_lastMessage = validation.value(QStringLiteral("message")).toString();
        emit operationChanged();
        return false;
    }

    const QString cleanImage = validation.value(QStringLiteral("imagePath")).toString();
    const QString archiveMember = validation.value(QStringLiteral("archiveMember")).toString();
    const quint64 expandedBytes = validation.value(QStringLiteral("imageBytes")).toULongLong();
    const QVariantMap target = findDevice(targetDevice);
    QList<CommandStep> steps;

    QStringList mounts = mountedPathsRecursive(target);
    std::sort(mounts.begin(), mounts.end(), [](const QString &a, const QString &b) { return a.size() > b.size(); });
    const QString umount = executable(QStringLiteral("umount"));
    for (const QString &mountPoint : mounts) {
        if (!mountPoint.isEmpty() && !umount.isEmpty())
            steps << CommandStep{umount, {mountPoint}, QStringLiteral("Unmounting target volume"), false};
    }

    const QString lower = QFileInfo(cleanImage).fileName().toLower();
    const QString dd = executable(QStringLiteral("dd"));
    if (lower.endsWith(QStringLiteral(".img")) || lower.endsWith(QStringLiteral(".iso"))) {
        steps << CommandStep{dd,
                             {QStringLiteral("if=%1").arg(cleanImage),
                              QStringLiteral("of=%1").arg(targetDevice),
                              QStringLiteral("bs=16M"),
                              QStringLiteral("iflag=fullblock"),
                              QStringLiteral("conv=fsync"),
                              QStringLiteral("status=progress")},
                             QStringLiteral("Writing image to target"),
                             false};
    } else {
        const QString bash = executable(QStringLiteral("bash"));
        QString producer;
        if (lower.endsWith(QStringLiteral(".xz")))
            producer = QStringLiteral("xz -dc -- %1").arg(shellQuoted(cleanImage));
        else if (lower.endsWith(QStringLiteral(".gz")))
            producer = QStringLiteral("gzip -dc -- %1").arg(shellQuoted(cleanImage));
        else
            producer = QStringLiteral("unzip -p -- %1 %2").arg(shellQuoted(cleanImage), shellQuoted(archiveMember));
        const QString command = QStringLiteral("set -o pipefail; %1 | dd of=%2 bs=16M iflag=fullblock conv=fsync status=progress")
                                    .arg(producer, shellQuoted(targetDevice));
        steps << CommandStep{bash, {QStringLiteral("-c"), command}, QStringLiteral("Expanding and writing image to target"), false};
    }

    const QString sync = executable(QStringLiteral("sync"));
    if (!sync.isEmpty())
        steps << CommandStep{sync, {}, QStringLiteral("Flushing image data"), false};

    const QString cmp = executable(QStringLiteral("cmp"));
    const QString bash = executable(QStringLiteral("bash"));
    if (!cmp.isEmpty()) {
        QString verifyCommand;
        if (lower.endsWith(QStringLiteral(".img")) || lower.endsWith(QStringLiteral(".iso"))) {
            verifyCommand = QStringLiteral("cmp -n %1 -- %2 %3")
                                .arg(expandedBytes)
                                .arg(shellQuoted(cleanImage), shellQuoted(targetDevice));
        } else {
            QString producer;
            if (lower.endsWith(QStringLiteral(".xz")))
                producer = QStringLiteral("xz -dc -- %1").arg(shellQuoted(cleanImage));
            else if (lower.endsWith(QStringLiteral(".gz")))
                producer = QStringLiteral("gzip -dc -- %1").arg(shellQuoted(cleanImage));
            else
                producer = QStringLiteral("unzip -p -- %1 %2").arg(shellQuoted(cleanImage), shellQuoted(archiveMember));
            verifyCommand = QStringLiteral("set -o pipefail; %1 | cmp -n %2 -- - %3")
                                .arg(producer)
                                .arg(expandedBytes)
                                .arg(shellQuoted(targetDevice));
        }
        steps << CommandStep{bash, {QStringLiteral("-c"), verifyCommand}, QStringLiteral("Verifying written image"), false};
    }

    return startSteps(QStringLiteral("IMAGE FLASH"), targetDevice, steps, expandedBytes, cleanImage);
}

void StorageManager::refreshImagerCatalog()
{
    if (m_imagerCatalogLoading || m_catalogProcess->state() != QProcess::NotRunning)
        return;

    const QString python = executable(QStringLiteral("python3"));
    const QString script = imagerScriptPath();
    if (python.isEmpty() || script.isEmpty()) {
        m_imagerCatalogStatus = QStringLiteral("Raspberry Pi Imager helper is unavailable.");
        emit imagerCatalogChanged();
        return;
    }

    m_catalogOutput.clear();
    m_imagerCatalogLoading = true;
    m_imagerCatalogStatus = QStringLiteral("LOADING OPERATING SYSTEMS");
    emit imagerCatalogChanged();

    m_catalogProcess->setProgram(python);
    m_catalogProcess->setArguments({script, QStringLiteral("catalog")});
    m_catalogProcess->start();
}

bool StorageManager::installRecommendedImage(const QVariantMap &osEntry,
                                             const QString &targetDevice,
                                             const QVariantMap &setup)
{
    if (!osEntry.value(QStringLiteral("available"), true).toBool() ||
        osEntry.value(QStringLiteral("url")).toString().trimmed().isEmpty()) {
        m_lastMessage = QStringLiteral("This operating system does not currently publish a flashable image release.");
        emit operationChanged();
        return false;
    }
    return startImagerJob(osEntry, targetDevice, setup);
}

bool StorageManager::installManualImage(const QString &imagePath,
                                        const QString &targetDevice,
                                        const QVariantMap &setup)
{
    const QVariantMap validation = validateImageFlash(imagePath, targetDevice);
    if (!validation.value(QStringLiteral("ok")).toBool()) {
        m_lastMessage = validation.value(QStringLiteral("message")).toString();
        emit operationChanged();
        return false;
    }

    QVariantMap localEntry;
    localEntry.insert(QStringLiteral("id"), QStringLiteral("manual"));
    localEntry.insert(QStringLiteral("name"), QFileInfo(imagePath).fileName());
    localEntry.insert(QStringLiteral("description"), QStringLiteral("Manually selected local image"));
    localEntry.insert(QStringLiteral("available"), true);
    localEntry.insert(QStringLiteral("extractBytes"), validation.value(QStringLiteral("imageBytes")));
    localEntry.insert(QStringLiteral("extractSha256"), QString());
    localEntry.insert(QStringLiteral("downloadBytes"), QFileInfo(imagePath).size());
    localEntry.insert(QStringLiteral("initFormat"), QStringLiteral("systemd"));
    return startImagerJob(localEntry, targetDevice, setup,
                          validation.value(QStringLiteral("imagePath")).toString());
}

bool StorageManager::startImagerJob(const QVariantMap &osEntry,
                                    const QString &targetDevice,
                                    const QVariantMap &setup,
                                    const QString &localPath)
{
    if (m_busy) {
        m_lastMessage = QStringLiteral("Another storage operation is already running.");
        emit operationChanged();
        return false;
    }
    if (!hasStoragePrivileges()) {
        m_lastMessage = QStringLiteral("Raspberry Pi Imager requires the privileged neutronos.service runtime.");
        emit operationChanged();
        return false;
    }

    const QString cleanTarget = cleanDevicePath(targetDevice);
    const QVariantMap target = findTopLevelDevice(cleanTarget);
    if (cleanTarget.isEmpty() || target.isEmpty() || deviceType(target) != QStringLiteral("disk")) {
        m_lastMessage = QStringLiteral("Select a whole target disk, not a partition.");
        emit operationChanged();
        return false;
    }
    if (isProtectedDevice(target)) {
        m_lastMessage = QStringLiteral("The active NeutronOS boot/root disk can never be flashed.");
        emit operationChanged();
        return false;
    }

    const quint64 expandedBytes = osEntry.value(QStringLiteral("extractBytes")).toULongLong();
    if (expandedBytes > 0 && deviceSize(target) < expandedBytes) {
        m_lastMessage = QStringLiteral("The selected target disk is smaller than the expanded image.");
        emit operationChanged();
        return false;
    }

    const QString python = executable(QStringLiteral("python3"));
    const QString script = imagerScriptPath();
    if (python.isEmpty() || script.isEmpty()) {
        m_lastMessage = QStringLiteral("Raspberry Pi Imager helper is unavailable.");
        emit operationChanged();
        return false;
    }

    QVariantMap job;
    job.insert(QStringLiteral("target"), cleanTarget);
    job.insert(QStringLiteral("os"), osEntry);
    job.insert(QStringLiteral("setup"), setup);
    if (!localPath.trimmed().isEmpty())
        job.insert(QStringLiteral("localPath"), QFileInfo(localPath).absoluteFilePath());

    const QString jobPath = QStringLiteral("/run/neutronos-imager-job-%1-%2.json")
                                .arg(QCoreApplication::applicationPid())
                                .arg(QDateTime::currentMSecsSinceEpoch());
    QFile jobFile(jobPath);
    if (!jobFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        m_lastMessage = QStringLiteral("Could not create the protected image job file.");
        emit operationChanged();
        return false;
    }
    jobFile.write(QJsonDocument::fromVariant(job).toJson(QJsonDocument::Compact));
    jobFile.close();
    jobFile.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    QList<CommandStep> steps;
    steps << CommandStep{python,
                         {script, QStringLiteral("install"), QStringLiteral("--job"), jobPath},
                         QStringLiteral("Preparing Raspberry Pi Imager"),
                         false};

    m_imagerJobPath = jobPath;
    const QString source = localPath.trimmed().isEmpty()
            ? osEntry.value(QStringLiteral("name"), QStringLiteral("Operating system image")).toString()
            : QFileInfo(localPath).absoluteFilePath();
    if (!startSteps(QStringLiteral("RPI IMAGER"), cleanTarget, steps, expandedBytes, source)) {
        QFile::remove(jobPath);
        m_imagerJobPath.clear();
        return false;
    }
    return true;
}

bool StorageManager::cancelOperation()
{
    if (!m_busy || !m_process)
        return false;
    m_process->terminate();
    if (!m_process->waitForFinished(1000))
        m_process->kill();
    if (m_busy)
        finishOperation(false, QStringLiteral("Storage operation cancelled. The target may require repair before reuse."));
    return true;
}

void StorageManager::setOperationState(const QString &name,
                                       const QString &status,
                                       int progress,
                                       const QString &message)
{
    m_operationName = name;
    m_operationStatus = status;
    m_operationProgress = progress;
    if (!message.isEmpty())
        m_lastMessage = message;
    emit operationChanged();
}

bool StorageManager::startSteps(const QString &operationName,
                                const QString &target,
                                const QList<CommandStep> &steps,
                                quint64 cloneSourceBytes,
                                const QString &source)
{
    if (m_busy || steps.isEmpty())
        return false;

    for (const CommandStep &step : steps) {
        if (step.program.isEmpty()) {
            m_lastMessage = QStringLiteral("A required storage utility is not installed.");
            emit operationChanged();
            return false;
        }
    }

    m_steps = steps;
    m_stepIndex = -1;
    m_busy = true;
    m_operationTarget = target;
    m_operationSource = source;
    m_cloneSourceBytes = cloneSourceBytes;
    m_operationBytesProcessed = 0;
    m_operationSpeed.clear();
    m_operationEta.clear();
    m_operationElapsed = QStringLiteral("0s");
    m_operationVerification = (operationName == QStringLiteral("IMAGE FLASH") ||
                               operationName == QStringLiteral("RPI IMAGER"))
            ? QStringLiteral("PENDING")
            : QStringLiteral("NOT REQUIRED");
    m_operationTimer.restart();
    m_processOutput.clear();
    m_progressBuffer.clear();
    setOperationState(operationName, QStringLiteral("STARTING"), cloneSourceBytes > 0 ? 0 : -1,
                      QStringLiteral("Operation started. Do not disconnect the selected device."));
    startNextStep();
    return true;
}

void StorageManager::startNextStep()
{
    ++m_stepIndex;
    if (m_stepIndex >= m_steps.size()) {
        if (m_operationName == QStringLiteral("SMART CHECK"))
            parseSmartResult(m_processOutput);

        const QString message = m_operationName == QStringLiteral("BOOT BACKUP")
                ? QStringLiteral("Boot clone complete. Shut down NeutronOS before removing or booting the cloned disk.")
                : QStringLiteral("%1 completed successfully.").arg(m_operationName);
        finishOperation(true, message);
        return;
    }

    const CommandStep &step = m_steps.at(m_stepIndex);
    m_processOutput.clear();
    if (step.description.contains(QStringLiteral("Verifying"), Qt::CaseInsensitive))
        m_operationVerification = QStringLiteral("RUNNING");
    setOperationState(m_operationName, step.description,
                      m_cloneSourceBytes > 0 ? qMax(0, m_operationProgress) : -1);
    m_process->setProgram(step.program);
    m_process->setArguments(step.arguments);
    m_process->start();
    if (!m_process->waitForStarted(2500))
        finishOperation(false, QStringLiteral("Could not start: %1").arg(step.description));
}

void StorageManager::finishOperation(bool success, const QString &message)
{
    m_busy = false;
    m_operationStatus = success ? QStringLiteral("COMPLETE") : QStringLiteral("FAILED");
    if (success && m_cloneSourceBytes > 0) {
        m_operationProgress = 100;
        m_operationBytesProcessed = m_cloneSourceBytes;
    }
    if (m_operationName == QStringLiteral("IMAGE FLASH") ||
        m_operationName == QStringLiteral("RPI IMAGER")) {
        if (success && m_operationVerification == QStringLiteral("RUNNING"))
            m_operationVerification = QStringLiteral("PASSED");
        else if (!success && m_operationVerification == QStringLiteral("RUNNING"))
            m_operationVerification = QStringLiteral("FAILED");
        else if (success && m_operationVerification == QStringLiteral("PENDING"))
            m_operationVerification = QStringLiteral("SKIPPED");
    }
    if (m_operationTimer.isValid())
        m_operationElapsed = humanDuration(m_operationTimer.elapsed() / 1000);
    m_lastMessage = message;
    if (!m_imagerJobPath.isEmpty()) {
        QFile::remove(m_imagerJobPath);
        m_imagerJobPath.clear();
    }
    m_steps.clear();
    m_stepIndex = -1;
    m_cloneSourceBytes = 0;

    appendActivity(success ? QStringLiteral("complete") : QStringLiteral("failed"),
                   success ? QStringLiteral("Storage operation completed")
                           : QStringLiteral("Storage operation failed"),
                   QStringLiteral("%1 • %2").arg(m_operationName, message),
                   success ? QStringLiteral("success") : QStringLiteral("danger"));

    emit operationChanged();
    emit operationFinished(success, message);

    if (success && m_operationName != QStringLiteral("BOOT BACKUP"))
        QTimer::singleShot(700, this, &StorageManager::refreshDevices);
}

void StorageManager::parseSmartResult(const QByteArray &jsonData)
{
    QByteArray payload = jsonData;
    const int begin = payload.indexOf('{');
    const int end = payload.lastIndexOf('}');
    if (begin >= 0 && end > begin)
        payload = payload.mid(begin, end - begin + 1);
    const QJsonDocument document = QJsonDocument::fromJson(payload);
    if (!document.isObject() || m_smartTarget.isEmpty())
        return;

    const QJsonObject object = document.object();
    QVariantMap smart;
    smart.insert(QStringLiteral("checked"), true);
    smart.insert(QStringLiteral("timestamp"), QDateTime::currentDateTime().toString(Qt::ISODate));

    const QJsonObject status = object.value(QStringLiteral("smart_status")).toObject();
    if (!status.isEmpty()) {
        const bool passed = status.value(QStringLiteral("passed")).toBool();
        smart.insert(QStringLiteral("passed"), passed);
        smart.insert(QStringLiteral("status"), passed ? QStringLiteral("PASSED") : QStringLiteral("ATTENTION"));
    } else {
        smart.insert(QStringLiteral("status"), QStringLiteral("UNSUPPORTED"));
    }

    const int detectedTemperature = parseTemperatureFromSmartJson(jsonData);
    if (detectedTemperature >= -20) {
        smart.insert(QStringLiteral("temperature"), detectedTemperature);
        smart.insert(QStringLiteral("temperatureSource"), QStringLiteral("SMART"));
    }

    const QJsonObject powerOn = object.value(QStringLiteral("power_on_time")).toObject();
    if (powerOn.contains(QStringLiteral("hours")))
        smart.insert(QStringLiteral("powerOnHours"), powerOn.value(QStringLiteral("hours")).toVariant());

    if (object.contains(QStringLiteral("power_cycle_count")))
        smart.insert(QStringLiteral("powerCycles"), object.value(QStringLiteral("power_cycle_count")).toVariant());

    const QJsonObject device = object.value(QStringLiteral("device")).toObject();
    smart.insert(QStringLiteral("protocol"), device.value(QStringLiteral("protocol")).toString());
    m_smartResults.insert(m_smartTarget, smart);

    QVariantList updated = m_devices;
    updateSmartFieldsRecursive(updated);
    m_devices = updated;
    rebuildFlatDeviceIndex();
    emit devicesChanged();
}

void StorageManager::updateSmartFields(QVariantMap &device) const
{
    const QString topPath = findTopLevelDevice(device.value(QStringLiteral("path")).toString()).value(QStringLiteral("path")).toString();
    const QVariantMap smart = m_smartResults.value(topPath);
    device.insert(QStringLiteral("smartAvailable"), smartctlAvailable() && deviceType(device) == QStringLiteral("disk"));
    device.insert(QStringLiteral("smartChecked"), smart.value(QStringLiteral("checked"), false));
    device.insert(QStringLiteral("smartStatus"), smart.value(QStringLiteral("status"), QStringLiteral("NOT CHECKED")));
    device.insert(QStringLiteral("smartTemperature"), smart.value(QStringLiteral("temperature"), -1));
    device.insert(QStringLiteral("smartTemperatureSource"), smart.value(QStringLiteral("temperatureSource"), QString()));
    device.insert(QStringLiteral("smartHealthMode"), smart.value(QStringLiteral("healthMode"), smart.value(QStringLiteral("checked"), false).toBool() ? QStringLiteral("SMART") : QStringLiteral("AVAILABLE")));
    device.insert(QStringLiteral("smartPowerOnHours"), smart.value(QStringLiteral("powerOnHours"), 0));
    device.insert(QStringLiteral("smartPowerCycles"), smart.value(QStringLiteral("powerCycles"), 0));
}

void StorageManager::updateSmartFieldsRecursive(QVariantList &devices) const
{
    for (QVariant &variant : devices) {
        QVariantMap device = variant.toMap();
        updateSmartFields(device);
        QVariantList children = device.value(QStringLiteral("children")).toList();
        updateSmartFieldsRecursive(children);
        device.insert(QStringLiteral("children"), children);
        variant = device;
    }
}

void StorageManager::handleProcessOutput(const QByteArray &data)
{
    m_processOutput.append(data);
    m_progressBuffer.append(data);

    bool parsedStructuredProgress = false;
    int newline = -1;
    while ((newline = m_progressBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_progressBuffer.left(newline).trimmed();
        m_progressBuffer.remove(0, newline + 1);
        static const QByteArray prefix("NEUTRON_PROGRESS ");
        if (!line.startsWith(prefix))
            continue;

        const QJsonDocument document = QJsonDocument::fromJson(line.mid(prefix.size()));
        if (!document.isObject())
            continue;
        parsedStructuredProgress = true;
        const QVariantMap payload = document.object().toVariantMap();
        const QString phase = payload.value(QStringLiteral("phase")).toString().trimmed().toUpper();
        const QString message = payload.value(QStringLiteral("message")).toString().trimmed();

        if (!message.isEmpty()) {
            m_operationStatus = message;
            if (phase == QStringLiteral("ERROR"))
                m_lastMessage = message;
        } else if (!phase.isEmpty()) {
            m_operationStatus = phase;
        }

        if (payload.contains(QStringLiteral("percent")))
            m_operationProgress = qBound(-1, payload.value(QStringLiteral("percent")).toInt(), 100);
        if (payload.contains(QStringLiteral("bytes")))
            m_operationBytesProcessed = payload.value(QStringLiteral("bytes")).toULongLong();
        if (payload.contains(QStringLiteral("total")) && payload.value(QStringLiteral("total")).toULongLong() > 0)
            m_cloneSourceBytes = payload.value(QStringLiteral("total")).toULongLong();
        if (payload.contains(QStringLiteral("speed"))) {
            QString speed = payload.value(QStringLiteral("speed")).toString();
            static const QRegularExpression rawSpeed(QStringLiteral("^(\\d+(?:\\.\\d+)?) B/s$"));
            const QRegularExpressionMatch match = rawSpeed.match(speed);
            if (match.hasMatch())
                speed = humanBytes(static_cast<quint64>(match.captured(1).toDouble())) + QStringLiteral("/s");
            m_operationSpeed = speed;
        }
        if (payload.contains(QStringLiteral("eta"))) {
            const QVariant eta = payload.value(QStringLiteral("eta"));
            m_operationEta = eta.canConvert<qlonglong>()
                    ? humanDuration(eta.toLongLong())
                    : eta.toString();
        }
        if (payload.contains(QStringLiteral("verification")))
            m_operationVerification = payload.value(QStringLiteral("verification")).toString().toUpper();
        if (phase == QStringLiteral("VERIFY") && m_operationVerification == QStringLiteral("PENDING"))
            m_operationVerification = QStringLiteral("RUNNING");
        if (phase == QStringLiteral("ERROR"))
            m_operationVerification = QStringLiteral("FAILED");
        if (m_operationTimer.isValid())
            m_operationElapsed = humanDuration(m_operationTimer.elapsed() / 1000);
        emit operationChanged();
    }

    if (parsedStructuredProgress || m_cloneSourceBytes == 0)
        return;

    static const QRegularExpression bytesPattern(QStringLiteral("(?:^|\\s)(\\d+) bytes"));
    const QString text = QString::fromLocal8Bit(data);
    QRegularExpressionMatchIterator iterator = bytesPattern.globalMatch(text);
    quint64 latest = 0;
    while (iterator.hasNext())
        latest = iterator.next().captured(1).toULongLong();
    if (latest == 0)
        return;

    m_operationBytesProcessed = qMax(m_operationBytesProcessed, latest);
    const qint64 elapsedMs = m_operationTimer.isValid() ? qMax<qint64>(1, m_operationTimer.elapsed()) : 1;
    const double bytesPerSecond = static_cast<double>(m_operationBytesProcessed) * 1000.0 / static_cast<double>(elapsedMs);
    m_operationSpeed = bytesPerSecond > 0.0
            ? humanBytes(static_cast<quint64>(bytesPerSecond)) + QStringLiteral("/s")
            : QStringLiteral("—");
    m_operationElapsed = humanDuration(elapsedMs / 1000);
    if (bytesPerSecond > 0.0 && m_operationBytesProcessed < m_cloneSourceBytes) {
        const quint64 remaining = m_cloneSourceBytes - m_operationBytesProcessed;
        m_operationEta = humanDuration(static_cast<qint64>(remaining / bytesPerSecond));
    } else {
        m_operationEta = QStringLiteral("0s");
    }

    const int progress = static_cast<int>(qMin<quint64>(100, m_operationBytesProcessed * 100 / qMax<quint64>(1, m_cloneSourceBytes)));
    if (progress != m_operationProgress)
        m_operationProgress = progress;
    emit operationChanged();
}

void StorageManager::onProcessReadyRead()
{
    handleProcessOutput(m_process->readAllStandardOutput());
    handleProcessOutput(m_process->readAllStandardError());
}

void StorageManager::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (!m_busy || m_stepIndex < 0 || m_stepIndex >= m_steps.size())
        return;

    onProcessReadyRead();
    const CommandStep step = m_steps.at(m_stepIndex);
    const bool success = exitStatus == QProcess::NormalExit && (exitCode == 0 || step.tolerateNonZero);
    if (!success) {
        if (step.description.contains(QStringLiteral("Verifying"), Qt::CaseInsensitive))
            m_operationVerification = QStringLiteral("FAILED");
        QString detail;
        if (m_operationName == QStringLiteral("RPI IMAGER") &&
            !m_lastMessage.isEmpty() &&
            !m_lastMessage.startsWith(QStringLiteral("Operation started"))) {
            detail = m_lastMessage;
        } else {
            detail = QString::fromLocal8Bit(m_processOutput).trimmed();
            if (detail.size() > 420)
                detail = detail.right(420);
        }
        if (m_operationName == QStringLiteral("RPI IMAGER") && !detail.isEmpty())
            finishOperation(false, detail);
        else
            finishOperation(false, detail.isEmpty()
                            ? QStringLiteral("%1 failed with exit code %2.").arg(step.description).arg(exitCode)
                            : QStringLiteral("%1 failed: %2").arg(step.description, detail));
        return;
    }

    if (step.description.contains(QStringLiteral("Verifying"), Qt::CaseInsensitive))
        m_operationVerification = QStringLiteral("PASSED");
    startNextStep();
}

void StorageManager::onCatalogReadyRead()
{
    m_catalogOutput.append(m_catalogProcess->readAllStandardOutput());
    m_catalogOutput.append(m_catalogProcess->readAllStandardError());
}

void StorageManager::onCatalogFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    onCatalogReadyRead();
    m_imagerCatalogLoading = false;

    QByteArray jsonLine;
    const QList<QByteArray> lines = m_catalogOutput.split('\n');
    for (const QByteArray &line : lines) {
        const QByteArray trimmed = line.trimmed();
        if (trimmed.startsWith('{') && trimmed.endsWith('}'))
            jsonLine = trimmed;
    }

    const QJsonDocument document = QJsonDocument::fromJson(jsonLine);
    if (exitStatus != QProcess::NormalExit || exitCode != 0 || !document.isObject()) {
        QString detail = QString::fromLocal8Bit(m_catalogOutput).trimmed();
        if (detail.size() > 320)
            detail = detail.right(320);
        m_imagerCatalogStatus = detail.isEmpty()
                ? QStringLiteral("Operating-system catalog could not be loaded.")
                : QStringLiteral("Catalog error: %1").arg(detail);
        emit imagerCatalogChanged();
        return;
    }

    const QVariantMap root = document.object().toVariantMap();
    m_imagerCatalog = root.value(QStringLiteral("osList")).toList();
    const QString warning = root.value(QStringLiteral("warning")).toString().trimmed();
    m_imagerCatalogStatus = m_imagerCatalog.isEmpty()
            ? QStringLiteral("No compatible operating systems were returned.")
            : QStringLiteral("%1 operating systems ready%2")
                  .arg(m_imagerCatalog.size())
                  .arg(warning.isEmpty() ? QString() : QStringLiteral(" — official catalog fallback used"));
    emit imagerCatalogChanged();
}

