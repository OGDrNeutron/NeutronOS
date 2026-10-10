#include "StorageImageFlasher.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QHash>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>

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

QVariantList flattenBlockDevices(const QJsonArray &nodes,
                                 const QString &parentPath = QString())
{
    QVariantList output;
    for (const QJsonValue &value : nodes) {
        const QJsonObject object = value.toObject();
        QVariantMap item = object.toVariantMap();
        item.insert(QStringLiteral("parentPath"), parentPath);
        const QString path = object.value(QStringLiteral("path")).toString();
        output << item;
        const QJsonArray children = object.value(QStringLiteral("children")).toArray();
        if (!children.isEmpty())
            output.append(flattenBlockDevices(children, path));
    }
    return output;
}

QString topDiskForPath(const QString &path, const QVariantList &devices)
{
    QHash<QString, QVariantMap> index;
    for (const QVariant &entry : devices) {
        const QVariantMap map = entry.toMap();
        index.insert(map.value(QStringLiteral("path")).toString(), map);
    }
    QString currentPath = path;
    QSet<QString> seen;
    while (!currentPath.isEmpty() && !seen.contains(currentPath)) {
        seen.insert(currentPath);
        const QVariantMap current = index.value(currentPath);
        const QString parentName = current.value(QStringLiteral("pkname")).toString();
        const QString parentPath = current.value(QStringLiteral("parentPath")).toString();
        QString next = parentPath;
        if (next.isEmpty() && !parentName.isEmpty())
            next = QStringLiteral("/dev/") + parentName;
        if (next.isEmpty())
            break;
        currentPath = next;
    }
    return currentPath;
}

QString architectureLabel(const QJsonObject &object)
{
    QString architecture = object.value(QStringLiteral("architecture")).toString().trimmed();
    if (architecture.isEmpty())
        architecture = object.value(QStringLiteral("arch")).toString().trimmed();
    if (architecture.isEmpty()) {
        const QString name = object.value(QStringLiteral("name")).toString().toLower();
        if (name.contains(QStringLiteral("64-bit")) || name.contains(QStringLiteral("arm64")))
            architecture = QStringLiteral("64-bit");
        else if (name.contains(QStringLiteral("32-bit")) || name.contains(QStringLiteral("armhf")))
            architecture = QStringLiteral("32-bit");
    }
    return architecture;
}
}

StorageImageFlasher::StorageImageFlasher(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_network(new QNetworkAccessManager(this)),
      m_process(new QProcess(this))
{
    connect(m_process, &QProcess::readyReadStandardOutput,
            this, &StorageImageFlasher::onProcessReadyRead);
    connect(m_process, &QProcess::readyReadStandardError,
            this, &StorageImageFlasher::onProcessReadyRead);
    connect(m_process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            &StorageImageFlasher::onProcessFinished);

    QDir().mkpath(stateDirectory());
    QDir().mkpath(cacheDirectory());
}

StorageImageFlasher::~StorageImageFlasher() = default;

QVariantList StorageImageFlasher::raspberryModels() const
{
    return {
        QVariantMap{{QStringLiteral("id"), QStringLiteral("pi5")},
                    {QStringLiteral("name"), QStringLiteral("Raspberry Pi 5 / Compute Module 5")},
                    {QStringLiteral("description"), QStringLiteral("64-bit images optimized for the newest Raspberry Pi generation.")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("pi4")},
                    {QStringLiteral("name"), QStringLiteral("Raspberry Pi 4 / 400 / Compute Module 4")},
                    {QStringLiteral("description"), QStringLiteral("64-bit or compatible 32-bit images for Pi 4-class hardware.")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("pi3")},
                    {QStringLiteral("name"), QStringLiteral("Raspberry Pi 3 / Zero 2 W / Compute Module 3")},
                    {QStringLiteral("description"), QStringLiteral("Images compatible with ARMv8 Pi 3 and Zero 2 devices.")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("pi2")},
                    {QStringLiteral("name"), QStringLiteral("Raspberry Pi 2")},
                    {QStringLiteral("description"), QStringLiteral("Compatible 32-bit Raspberry Pi operating systems.")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("pi1")},
                    {QStringLiteral("name"), QStringLiteral("Raspberry Pi 1 / Zero / Zero W")},
                    {QStringLiteral("description"), QStringLiteral("Legacy-compatible 32-bit images for early Raspberry Pi models.")}}
    };
}

QVariantList StorageImageFlasher::raspberryImages() const { return m_raspberryImages; }
bool StorageImageFlasher::catalogBusy() const { return m_catalogBusy; }
QString StorageImageFlasher::catalogMessage() const { return m_catalogMessage; }
bool StorageImageFlasher::busy() const { return m_busy; }
QString StorageImageFlasher::stage() const { return m_stage; }
QString StorageImageFlasher::status() const { return m_status; }
int StorageImageFlasher::progress() const { return m_progress; }
qulonglong StorageImageFlasher::bytesDone() const { return m_bytesDone; }
qulonglong StorageImageFlasher::bytesTotal() const { return m_bytesTotal; }
double StorageImageFlasher::bytesPerSecond() const { return m_bytesPerSecond; }
qint64 StorageImageFlasher::etaSeconds() const { return m_etaSeconds; }
QString StorageImageFlasher::logPath() const { return m_logPath; }
bool StorageImageFlasher::canCancel() const { return m_canCancel; }
bool StorageImageFlasher::succeeded() const { return m_succeeded; }
QString StorageImageFlasher::lastError() const { return m_lastError; }

QString StorageImageFlasher::canonicalUserHome() const
{
    const QFileInfo rootInfo(m_neutronRoot);
    const QString parent = rootInfo.dir().absolutePath();
    if (QFileInfo(parent).isDir())
        return parent;
    return QDir::homePath();
}

QString StorageImageFlasher::parentDirectory(const QString &path) const
{
    QDir dir(QDir::cleanPath(path));
    if (!dir.cdUp())
        return dir.absolutePath();
    return dir.absolutePath();
}

QVariantList StorageImageFlasher::imagePickerEntries(const QString &path,
                                                     const QStringList &extensions) const
{
    QVariantList output;
    QDir directory(QDir::cleanPath(path));
    if (!directory.exists())
        directory = QDir(canonicalUserHome());
    QStringList normalized;
    for (const QString &extension : extensions) {
        QString value = extension.trimmed().toLower();
        if (value.startsWith(QLatin1Char('.')))
            value.remove(0, 1);
        if (!value.isEmpty())
            normalized << value;
    }
    const QFileInfoList entries = directory.entryInfoList(
                QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Readable,
                QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &info : entries) {
        if (info.isSymLink())
            continue;
        if (!info.isDir()) {
            const QString suffix = info.completeSuffix().toLower();
            const QString simpleSuffix = info.suffix().toLower();
            bool accepted = normalized.isEmpty();
            for (const QString &extension : normalized) {
                if (suffix == extension || simpleSuffix == extension ||
                    info.fileName().toLower().endsWith(QLatin1Char('.') + extension)) {
                    accepted = true;
                    break;
                }
            }
            if (!accepted)
                continue;
        }
        QVariantMap item;
        item.insert(QStringLiteral("name"), info.fileName());
        item.insert(QStringLiteral("path"), info.absoluteFilePath());
        item.insert(QStringLiteral("directory"), info.isDir());
        item.insert(QStringLiteral("sizeBytes"), info.isFile() ? info.size() : 0);
        item.insert(QStringLiteral("size"), info.isFile() ? humanSize(static_cast<qulonglong>(qMax<qint64>(0, info.size()))) : QString());
        output << item;
    }
    return output;
}

QVariantMap StorageImageFlasher::inspectImage(const QString &path) const
{
    const QString clean = cleanFilePath(path);
    const QFileInfo info(clean);
    if (clean.isEmpty() || !info.isFile() || !info.isReadable())
        return result(false, QStringLiteral("Choose a readable disk image file."));
    const QString lower = info.fileName().toLower();
    static const QStringList endings{
        QStringLiteral(".img"), QStringLiteral(".iso"), QStringLiteral(".raw"),
        QStringLiteral(".img.xz"), QStringLiteral(".img.gz"), QStringLiteral(".img.bz2"),
        QStringLiteral(".img.zst"), QStringLiteral(".zip"), QStringLiteral(".xz"),
        QStringLiteral(".gz"), QStringLiteral(".bz2"), QStringLiteral(".zst")
    };
    bool supported = false;
    for (const QString &ending : endings) {
        if (lower.endsWith(ending)) {
            supported = true;
            break;
        }
    }
    if (!supported)
        return result(false, QStringLiteral("Supported image types are IMG, ISO, RAW, ZIP, XZ, GZ, BZ2, and ZST."));
    QVariantMap output = result(true, QStringLiteral("Image is readable and ready for the final safety review."));
    output.insert(QStringLiteral("path"), info.absoluteFilePath());
    output.insert(QStringLiteral("name"), info.fileName());
    output.insert(QStringLiteral("sizeBytes"), info.size());
    output.insert(QStringLiteral("size"), humanSize(static_cast<qulonglong>(qMax<qint64>(0, info.size()))));
    output.insert(QStringLiteral("compressed"), !lower.endsWith(QStringLiteral(".img")) &&
                  !lower.endsWith(QStringLiteral(".iso")) && !lower.endsWith(QStringLiteral(".raw")));
    return output;
}

QVariantMap StorageImageFlasher::inspectTarget(const QString &devicePath) const
{
    const QVariantMap info = blockDeviceInfo(devicePath);
    if (info.isEmpty())
        return result(false, QStringLiteral("The selected storage device is no longer available."));
    if (info.value(QStringLiteral("type")).toString() != QStringLiteral("disk"))
        return result(false, QStringLiteral("Choose an entire storage device, not a partition."));
    if (info.value(QStringLiteral("readOnly")).toBool())
        return result(false, QStringLiteral("The selected storage device is read-only."));
    const QString system = systemDiskPath();
    if (!system.isEmpty() && cleanDevicePath(devicePath) == system)
        return result(false, QStringLiteral("The active NeutronOS boot drive cannot be flashed."));
    if (info.value(QStringLiteral("sizeBytes")).toULongLong() == 0)
        return result(false, QStringLiteral("The selected device capacity could not be determined."));
    QVariantMap output = result(true, QStringLiteral("Eligible non-boot target. Every partition will be erased after final confirmation."));
    for (auto it = info.cbegin(); it != info.cend(); ++it)
        output.insert(it.key(), it.value());
    return output;
}

QVariantList StorageImageFlasher::eligibleTargets() const
{
    QVariantList output;
    const QString lsblk = executable(QStringLiteral("lsblk"));
    if (lsblk.isEmpty())
        return output;
    int exitCode = -1;
    const QByteArray bytes = runBlocking(lsblk,
                                         {QStringLiteral("-J"), QStringLiteral("-b"),
                                          QStringLiteral("-o"),
                                          QStringLiteral("NAME,PATH,TYPE,PKNAME,MOUNTPOINTS,SIZE,RO,RM,MODEL,SERIAL,TRAN,FSTYPE,LABEL")},
                                         15000, &exitCode);
    if (exitCode != 0)
        return output;
    const QJsonDocument document = QJsonDocument::fromJson(bytes);
    const QVariantList devices = flattenBlockDevices(document.object().value(QStringLiteral("blockdevices")).toArray());
    const QString system = systemDiskPath();
    for (const QVariant &entry : devices) {
        const QVariantMap map = entry.toMap();
        const QString path = cleanDevicePath(map.value(QStringLiteral("path")).toString());
        if (path.isEmpty() || map.value(QStringLiteral("type")).toString() != QStringLiteral("disk"))
            continue;
        if (!system.isEmpty() && path == system)
            continue;
        if (map.value(QStringLiteral("ro")).toInt() != 0)
            continue;
        QVariantMap target;
        target.insert(QStringLiteral("path"), path);
        target.insert(QStringLiteral("name"), map.value(QStringLiteral("name")));
        target.insert(QStringLiteral("model"), map.value(QStringLiteral("model")).toString().trimmed());
        target.insert(QStringLiteral("serial"), map.value(QStringLiteral("serial")).toString().trimmed());
        target.insert(QStringLiteral("transport"), map.value(QStringLiteral("tran")).toString().trimmed());
        target.insert(QStringLiteral("removable"), map.value(QStringLiteral("rm")).toInt() != 0);
        target.insert(QStringLiteral("sizeBytes"), map.value(QStringLiteral("size")).toULongLong());
        target.insert(QStringLiteral("size"), humanSize(map.value(QStringLiteral("size")).toULongLong()));
        target.insert(QStringLiteral("description"), QStringLiteral("%1 · %2 · %3")
                      .arg(target.value(QStringLiteral("model")).toString().isEmpty()
                           ? path : target.value(QStringLiteral("model")).toString(),
                           target.value(QStringLiteral("size")).toString(),
                           target.value(QStringLiteral("transport")).toString().toUpper()));
        output << target;
    }
    return output;
}

void StorageImageFlasher::fetchRaspberryCatalog(const QString &modelId)
{
    if (m_catalogReply) {
        m_catalogReply->abort();
        m_catalogReply->deleteLater();
        m_catalogReply = nullptr;
    }
    m_catalogModelId = modelId.trimmed().toLower();
    m_raspberryImages.clear();
    m_neutronImage = unavailableNeutronImage(QStringLiteral("Scanning GitHub for the latest full NeutronOS image…"));
    m_raspberryImages << m_neutronImage;
    m_catalogBusy = true;
    m_catalogPhase = QStringLiteral("github");
    m_catalogMessage = QStringLiteral("Scanning GitHub for the latest NeutronOS full image…");
    emit catalogChanged();

    QNetworkRequest request{QUrl(QStringLiteral("https://api.github.com/repos/OGDrNeutron/NeutronOS/releases/latest"))};
    request.setRawHeader("User-Agent", "NeutronOS-Storage-Flasher/1.1");
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setRawHeader("X-GitHub-Api-Version", "2022-11-28");
    request.setTransferTimeout(45000);
    m_catalogReply = m_network->get(request);
    connect(m_catalogReply, &QNetworkReply::finished,
            this, &StorageImageFlasher::onCatalogFinished);
}

void StorageImageFlasher::requestOfficialCatalog()
{
    m_catalogPhase = QStringLiteral("official");
    m_catalogBusy = true;
    m_catalogMessage = QStringLiteral("GitHub scan complete. Loading compatible Raspberry Pi images…");
    emit catalogChanged();

    QNetworkRequest request{QUrl(QStringLiteral("https://downloads.raspberrypi.com/os_list_imagingutility_v4.json"))};
    request.setRawHeader("User-Agent", "NeutronOS-Storage-Flasher/1.1");
    request.setTransferTimeout(45000);
    m_catalogReply = m_network->get(request);
    connect(m_catalogReply, &QNetworkReply::finished,
            this, &StorageImageFlasher::onCatalogFinished);
}

bool StorageImageFlasher::startFlash(const QVariantMap &request)
{
    if (m_busy) {
        m_lastError = QStringLiteral("Another image write is already running.");
        emit operationChanged();
        return false;
    }
    const QString source = request.value(QStringLiteral("source")).toString().trimmed();
    const QString target = cleanDevicePath(request.value(QStringLiteral("target")).toString());
    if (source.isEmpty()) {
        m_lastError = QStringLiteral("Choose an image before flashing.");
        emit operationChanged();
        return false;
    }
    const QVariantMap targetValidation = inspectTarget(target);
    if (!targetValidation.value(QStringLiteral("ok")).toBool()) {
        m_lastError = targetValidation.value(QStringLiteral("message")).toString();
        emit operationChanged();
        return false;
    }
    if (!source.startsWith(QStringLiteral("https://")) && !source.startsWith(QStringLiteral("http://"))) {
        const QVariantMap imageValidation = inspectImage(source);
        if (!imageValidation.value(QStringLiteral("ok")).toBool()) {
            m_lastError = imageValidation.value(QStringLiteral("message")).toString();
            emit operationChanged();
            return false;
        }
    }
    const QString helper = helperPath();
    if (!QFileInfo(helper).isExecutable()) {
        m_lastError = QStringLiteral("The privileged image-writer helper is missing or not executable.");
        emit operationChanged();
        return false;
    }
    QString configError;
    if (!saveRequestConfig(request, &configError)) {
        m_lastError = configError;
        emit operationChanged();
        return false;
    }

    resetOperation();
    m_busy = true;
    m_stage = QStringLiteral("preparing");
    m_status = QStringLiteral("Preparing the image and rechecking the target");
    m_progress = 0;
    m_canCancel = true;
    m_targetDevice = target;
    m_logPath = newLogPath();
    emit operationChanged();

    QString program = executable(QStringLiteral("python3"));
    QStringList arguments;
#ifdef Q_OS_LINUX
    if (::geteuid() != 0) {
        const QString sudo = executable(QStringLiteral("sudo"));
        if (sudo.isEmpty()) {
            finish(false, QStringLiteral("Image flashing requires the privileged neutronos.service runtime."));
            return false;
        }
        arguments << QStringLiteral("-n") << program;
        program = sudo;
    }
#endif
    arguments << helper
              << QStringLiteral("--source") << source
              << QStringLiteral("--target") << target
              << QStringLiteral("--config") << m_configPath
              << QStringLiteral("--expected-sha256") << request.value(QStringLiteral("sha256")).toString().trimmed()
              << QStringLiteral("--expected-size") << QString::number(request.value(QStringLiteral("extractSize")).toULongLong())
              << QStringLiteral("--cache-dir") << cacheDirectory()
              << QStringLiteral("--log") << m_logPath;
    m_processBuffer.clear();
    m_process->setProgram(program);
    m_process->setArguments(arguments);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_process->start();
    if (!m_process->waitForStarted(5000)) {
        finish(false, QStringLiteral("The image-writer helper could not start."));
        return false;
    }
    return true;
}

bool StorageImageFlasher::cancel()
{
    if (!m_busy || !m_process || !m_canCancel || m_writeStarted)
        return false;
    m_status = QStringLiteral("Cancelling before destructive writing begins…");
    emit operationChanged();
    m_process->terminate();
    if (!m_process->waitForFinished(1500))
        m_process->kill();
    return true;
}

bool StorageImageFlasher::ejectTarget(const QString &devicePath)
{
    const QString path = cleanDevicePath(devicePath);
    if (path.isEmpty())
        return false;
    const QString udisksctl = executable(QStringLiteral("udisksctl"));
    if (!udisksctl.isEmpty()) {
        int exitCode = -1;
        runBlocking(udisksctl, {QStringLiteral("power-off"), QStringLiteral("-b"), path}, 60000, &exitCode);
        return exitCode == 0;
    }
    const QString eject = executable(QStringLiteral("eject"));
    if (eject.isEmpty())
        return false;
    int exitCode = -1;
    runBlocking(eject, {path}, 60000, &exitCode);
    return exitCode == 0;
}

QString StorageImageFlasher::humanBytes(qulonglong bytes) const { return humanSize(bytes); }

QString StorageImageFlasher::formatDuration(qint64 seconds) const
{
    if (seconds < 0)
        return QStringLiteral("—");
    const qint64 hours = seconds / 3600;
    const qint64 minutes = (seconds % 3600) / 60;
    const qint64 remainder = seconds % 60;
    if (hours > 0)
        return QStringLiteral("%1h %2m").arg(hours).arg(minutes);
    if (minutes > 0)
        return QStringLiteral("%1m %2s").arg(minutes).arg(remainder);
    return QStringLiteral("%1s").arg(remainder);
}

void StorageImageFlasher::onCatalogFinished()
{
    QNetworkReply *reply = m_catalogReply;
    m_catalogReply = nullptr;
    const QString phase = m_catalogPhase;
    if (!reply) {
        if (phase == QStringLiteral("github")) {
            m_neutronImage = unavailableNeutronImage(QStringLiteral("Image not currently available"));
            m_raspberryImages = QVariantList{m_neutronImage};
            requestOfficialCatalog();
            return;
        }
        m_catalogBusy = false;
        m_catalogMessage = QStringLiteral("The Raspberry Pi catalog request ended unexpectedly.");
        emit catalogChanged();
        return;
    }

    const QByteArray payload = reply->readAll();
    const QNetworkReply::NetworkError networkError = reply->error();
    const QString errorText = reply->errorString();
    reply->deleteLater();

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);

    if (phase == QStringLiteral("github")) {
        if (networkError == QNetworkReply::NoError &&
                parseError.error == QJsonParseError::NoError && !document.isNull()) {
            m_neutronImage = parseNeutronRelease(document);
        } else {
            const QString reason = networkError == QNetworkReply::ContentNotFoundError
                    ? QStringLiteral("Image not currently available")
                    : QStringLiteral("GitHub scan unavailable: %1").arg(errorText);
            m_neutronImage = unavailableNeutronImage(reason);
        }
        m_raspberryImages = QVariantList{m_neutronImage};
        emit catalogChanged();
        requestOfficialCatalog();
        return;
    }

    m_catalogBusy = false;
    if (networkError != QNetworkReply::NoError) {
        m_raspberryImages = QVariantList{m_neutronImage};
        m_catalogMessage = QStringLiteral("NeutronOS scan completed, but the Raspberry Pi catalog could not be downloaded: %1").arg(errorText);
        emit catalogChanged();
        return;
    }
    if (parseError.error != QJsonParseError::NoError || document.isNull()) {
        m_raspberryImages = QVariantList{m_neutronImage};
        m_catalogMessage = QStringLiteral("NeutronOS scan completed, but the Raspberry Pi catalog could not be parsed.");
        emit catalogChanged();
        return;
    }

    QVariantList images;
    collectCatalogEntries(document.isArray() ? QJsonValue(document.array()) : QJsonValue(document.object()),
                          m_catalogModelId, &images);
    QSet<QString> urls;
    QVariantList unique;
    for (const QVariant &entry : images) {
        QVariantMap map = entry.toMap();
        const QString url = map.value(QStringLiteral("url")).toString();
        if (url.isEmpty() || urls.contains(url))
            continue;
        urls.insert(url);
        map.insert(QStringLiteral("available"), true);
        map.insert(QStringLiteral("recommended"), false);
        map.insert(QStringLiteral("source"), QStringLiteral("raspberrypi"));
        unique << map;
    }
    std::sort(unique.begin(), unique.end(), [](const QVariant &leftValue, const QVariant &rightValue) {
        const QVariantMap left = leftValue.toMap();
        const QVariantMap right = rightValue.toMap();
        const int leftPriority = StorageImageFlasher::imageSortPriority(left);
        const int rightPriority = StorageImageFlasher::imageSortPriority(right);
        if (leftPriority != rightPriority)
            return leftPriority < rightPriority;
        const QString leftDate = left.value(QStringLiteral("releaseDate")).toString();
        const QString rightDate = right.value(QStringLiteral("releaseDate")).toString();
        if (leftDate != rightDate)
            return leftDate > rightDate;
        return left.value(QStringLiteral("name")).toString().localeAwareCompare(
                    right.value(QStringLiteral("name")).toString()) < 0;
    });

    QVariantList combined;
    combined << m_neutronImage;
    combined.append(unique);
    m_raspberryImages = combined;
    const bool neutronAvailable = m_neutronImage.value(QStringLiteral("available")).toBool();
    m_catalogMessage = QStringLiteral("GitHub scan complete: NeutronOS %1. %2 compatible Raspberry Pi images loaded.")
            .arg(neutronAvailable ? QStringLiteral("image ready") : QStringLiteral("image not currently available"))
            .arg(unique.size());
    emit catalogChanged();
}

QVariantMap StorageImageFlasher::unavailableNeutronImage(const QString &reason) const
{
    return QVariantMap{
        {QStringLiteral("name"), QStringLiteral("NeutronOS")},
        {QStringLiteral("version"), QStringLiteral("Latest release")},
        {QStringLiteral("description"), QStringLiteral("The controller-first NeutronOS full flashable image from OGDrNeutron/NeutronOS.")},
        {QStringLiteral("releaseDate"), QString()},
        {QStringLiteral("architecture"), QStringLiteral("64-bit")},
        {QStringLiteral("group"), QStringLiteral("NeutronOS")},
        {QStringLiteral("url"), QString()},
        {QStringLiteral("sha256"), QString()},
        {QStringLiteral("downloadSize"), qulonglong(0)},
        {QStringLiteral("extractSize"), qulonglong(0)},
        {QStringLiteral("customizationSupported"), true},
        {QStringLiteral("available"), false},
        {QStringLiteral("recommended"), true},
        {QStringLiteral("source"), QStringLiteral("github")},
        {QStringLiteral("unavailableReason"), reason.isEmpty() ? QStringLiteral("Image not currently available") : reason}
    };
}

bool StorageImageFlasher::isFlashableNeutronAsset(const QString &name)
{
    const QString lower = name.trimmed().toLower();
    if (lower.isEmpty())
        return false;
    static const QStringList rejected{
        QStringLiteral("installer"), QStringLiteral("setup"), QStringLiteral("patch"),
        QStringLiteral("source"), QStringLiteral("checksum"), QStringLiteral("sha256"),
        QStringLiteral("signature"), QStringLiteral("manifest"), QStringLiteral("torrent")
    };
    for (const QString &token : rejected) {
        if (lower.contains(token))
            return false;
    }
    static const QStringList accepted{
        QStringLiteral(".img"), QStringLiteral(".img.xz"), QStringLiteral(".img.gz"),
        QStringLiteral(".img.zip"), QStringLiteral(".img.bz2"), QStringLiteral(".img.zst")
    };
    for (const QString &suffix : accepted) {
        if (lower.endsWith(suffix))
            return true;
    }
    return false;
}

QVariantMap StorageImageFlasher::parseNeutronRelease(const QJsonDocument &document) const
{
    if (!document.isObject())
        return unavailableNeutronImage(QStringLiteral("Image not currently available"));
    const QJsonObject release = document.object();
    const QJsonArray assets = release.value(QStringLiteral("assets")).toArray();
    QJsonObject chosen;
    int chosenScore = -1;
    qulonglong chosenSize = 0;
    for (const QJsonValue &value : assets) {
        const QJsonObject asset = value.toObject();
        const QString name = asset.value(QStringLiteral("name")).toString();
        if (!isFlashableNeutronAsset(name))
            continue;
        const QString lower = name.toLower();
        int score = 10;
        if (lower.endsWith(QStringLiteral(".img.xz"))) score = 60;
        else if (lower.endsWith(QStringLiteral(".img.zst"))) score = 55;
        else if (lower.endsWith(QStringLiteral(".img.gz"))) score = 50;
        else if (lower.endsWith(QStringLiteral(".img.zip"))) score = 45;
        else if (lower.endsWith(QStringLiteral(".img.bz2"))) score = 40;
        else if (lower.endsWith(QStringLiteral(".img"))) score = 35;
        const qulonglong size = asset.value(QStringLiteral("size")).toVariant().toULongLong();
        if (score > chosenScore || (score == chosenScore && size > chosenSize)) {
            chosen = asset;
            chosenScore = score;
            chosenSize = size;
        }
    }
    if (chosen.isEmpty())
        return unavailableNeutronImage(QStringLiteral("Image not currently available"));

    QString digest = chosen.value(QStringLiteral("digest")).toString().trimmed();
    if (digest.startsWith(QStringLiteral("sha256:"), Qt::CaseInsensitive))
        digest = digest.mid(7);
    else if (!QRegularExpression(QStringLiteral("^[0-9a-fA-F]{64}$")).match(digest).hasMatch())
        digest.clear();

    const QString tag = release.value(QStringLiteral("tag_name")).toString().trimmed();
    const QString releaseName = release.value(QStringLiteral("name")).toString().trimmed();
    const QString published = release.value(QStringLiteral("published_at")).toString().left(10);
    return QVariantMap{
        {QStringLiteral("name"), QStringLiteral("NeutronOS")},
        {QStringLiteral("version"), tag.isEmpty() ? releaseName : tag},
        {QStringLiteral("description"), QStringLiteral("Latest full NeutronOS flashable image discovered from the official OGDrNeutron GitHub release.")},
        {QStringLiteral("releaseDate"), published},
        {QStringLiteral("architecture"), QStringLiteral("64-bit")},
        {QStringLiteral("group"), QStringLiteral("NeutronOS")},
        {QStringLiteral("url"), chosen.value(QStringLiteral("browser_download_url")).toString()},
        {QStringLiteral("sha256"), digest},
        {QStringLiteral("downloadSize"), chosenSize},
        {QStringLiteral("extractSize"), qulonglong(0)},
        {QStringLiteral("customizationSupported"), true},
        {QStringLiteral("available"), true},
        {QStringLiteral("recommended"), true},
        {QStringLiteral("source"), QStringLiteral("github")},
        {QStringLiteral("assetName"), chosen.value(QStringLiteral("name")).toString()},
        {QStringLiteral("unavailableReason"), QString()}
    };
}

int StorageImageFlasher::imageSortPriority(const QVariantMap &image)
{
    const QString source = image.value(QStringLiteral("source")).toString().toLower();
    const QString name = image.value(QStringLiteral("name")).toString().toLower();
    const QString architecture = image.value(QStringLiteral("architecture")).toString().toLower();
    if (source == QStringLiteral("github") || name == QStringLiteral("neutronos"))
        return 0;
    const bool lite = name.contains(QStringLiteral("raspberry pi os lite"));
    const bool sixtyFour = name.contains(QStringLiteral("64-bit")) || name.contains(QStringLiteral("64 bit")) ||
            architecture.contains(QStringLiteral("64")) || architecture.contains(QStringLiteral("arm64")) ||
            architecture.contains(QStringLiteral("aarch64"));
    if (lite && sixtyFour)
        return 1;
    return 2;
}

void StorageImageFlasher::onProcessReadyRead()
{
    m_processBuffer.append(m_process->readAllStandardOutput());
    m_processBuffer.append(m_process->readAllStandardError());
    while (true) {
        const int newline = m_processBuffer.indexOf('\n');
        if (newline < 0)
            break;
        const QByteArray line = m_processBuffer.left(newline).trimmed();
        m_processBuffer.remove(0, newline + 1);
        if (line.isEmpty())
            continue;
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        if (error.error == QJsonParseError::NoError && document.isObject())
            applyProgressObject(document.object());
    }
}

void StorageImageFlasher::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    onProcessReadyRead();
    if (!m_busy)
        return;
    if (exitStatus == QProcess::NormalExit && exitCode == 0) {
        finish(true, m_status.isEmpty() ? QStringLiteral("Image written and verified successfully.") : m_status);
    } else {
        const QString message = !m_lastError.isEmpty()
                ? m_lastError
                : QStringLiteral("Image flashing failed. Review %1 for details.").arg(m_logPath);
        finish(false, message);
    }
}

QString StorageImageFlasher::executable(const QString &name)
{
    return QStandardPaths::findExecutable(name);
}

QString StorageImageFlasher::cleanDevicePath(const QString &path)
{
    const QString value = QDir::cleanPath(path.trimmed());
    if (!value.startsWith(QStringLiteral("/dev/")) || value.contains(QStringLiteral("..")) ||
        value.contains(QLatin1Char('\n')) || value.contains(QLatin1Char('\r')))
        return {};
    return value;
}

QString StorageImageFlasher::cleanFilePath(const QString &path)
{
    const QString value = QDir::cleanPath(path.trimmed());
    if (value.isEmpty() || value.contains(QLatin1Char('\n')) || value.contains(QLatin1Char('\r')))
        return {};
    return QFileInfo(value).absoluteFilePath();
}

QStringList StorageImageFlasher::stringList(const QJsonValue &value)
{
    QStringList output;
    if (value.isArray()) {
        for (const QJsonValue &entry : value.toArray()) {
            const QString text = entry.toString().trimmed();
            if (!text.isEmpty())
                output << text;
        }
    } else {
        const QString text = value.toString().trimmed();
        if (!text.isEmpty())
            output << text;
    }
    return output;
}

QString StorageImageFlasher::humanSize(qulonglong bytes)
{
    static const char *units[] = {"B", "KiB", "MiB", "GiB", "TiB"};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < 4) {
        value /= 1024.0;
        ++unit;
    }
    return QString::number(value, 'f', unit == 0 ? 0 : 1) + QLatin1Char(' ') + QString::fromLatin1(units[unit]);
}

QVariantMap StorageImageFlasher::result(bool ok, const QString &message)
{
    return QVariantMap{{QStringLiteral("ok"), ok}, {QStringLiteral("message"), message}};
}

void StorageImageFlasher::collectCatalogEntries(const QJsonValue &value,
                                                const QString &modelId,
                                                QVariantList *output,
                                                const QString &group)
{
    if (!output)
        return;
    if (value.isArray()) {
        for (const QJsonValue &entry : value.toArray())
            collectCatalogEntries(entry, modelId, output, group);
        return;
    }
    if (!value.isObject())
        return;
    const QJsonObject object = value.toObject();
    const QString currentGroup = entryString(object, {QStringLiteral("group"), QStringLiteral("category"), QStringLiteral("name")});
    const QString inheritedGroup = group.isEmpty() ? currentGroup : group;

    const QString url = entryString(object, {QStringLiteral("url"), QStringLiteral("image_url"), QStringLiteral("download_url")});
    const QString name = entryString(object, {QStringLiteral("name"), QStringLiteral("os_name"), QStringLiteral("title")});
    if (!url.isEmpty() && !name.isEmpty() && catalogEntryMatchesModel(object, modelId)) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), name);
        item.insert(QStringLiteral("version"), entryString(object, {QStringLiteral("version"), QStringLiteral("release") }));
        item.insert(QStringLiteral("description"), entryString(object, {QStringLiteral("description"), QStringLiteral("short_description") }));
        item.insert(QStringLiteral("releaseDate"), entryString(object, {QStringLiteral("release_date"), QStringLiteral("date") }));
        item.insert(QStringLiteral("architecture"), architectureLabel(object));
        item.insert(QStringLiteral("group"), inheritedGroup);
        item.insert(QStringLiteral("url"), url);
        item.insert(QStringLiteral("sha256"), entryString(object, {QStringLiteral("sha256"), QStringLiteral("image_sha256") }));
        item.insert(QStringLiteral("downloadSize"), entrySize(object, {QStringLiteral("image_download_size"), QStringLiteral("download_size"), QStringLiteral("size") }));
        item.insert(QStringLiteral("extractSize"), entrySize(object, {QStringLiteral("extract_size"), QStringLiteral("uncompressed_size"), QStringLiteral("nominal_size") }));
        item.insert(QStringLiteral("customizationSupported"), object.value(QStringLiteral("init_format")).toString() == QStringLiteral("systemd") ||
                    object.value(QStringLiteral("supports_customization")).toBool(true));
        output->append(item);
    }

    static const QStringList nestedKeys{
        QStringLiteral("os_list"), QStringLiteral("subitems"), QStringLiteral("children"),
        QStringLiteral("items"), QStringLiteral("operating_systems")
    };
    for (const QString &key : nestedKeys) {
        const QJsonValue nested = object.value(key);
        if (!nested.isUndefined())
            collectCatalogEntries(nested, modelId, output, currentGroup.isEmpty() ? inheritedGroup : currentGroup);
    }
}

bool StorageImageFlasher::catalogEntryMatchesModel(const QJsonObject &object,
                                                   const QString &modelId)
{
    QStringList values;
    values.append(stringList(object.value(QStringLiteral("devices"))));
    values.append(stringList(object.value(QStringLiteral("supported_models"))));
    values.append(stringList(object.value(QStringLiteral("compatible"))));
    if (values.isEmpty())
        return true;
    const QString id = modelId.toLower();
    QStringList aliases;
    if (id == QStringLiteral("pi5"))
        aliases << QStringLiteral("pi5") << QStringLiteral("pi 5") << QStringLiteral("2712") << QStringLiteral("cm5");
    else if (id == QStringLiteral("pi4"))
        aliases << QStringLiteral("pi4") << QStringLiteral("pi 4") << QStringLiteral("pi 400") << QStringLiteral("cm4");
    else if (id == QStringLiteral("pi3"))
        aliases << QStringLiteral("pi3") << QStringLiteral("pi 3") << QStringLiteral("zero 2") << QStringLiteral("cm3");
    else if (id == QStringLiteral("pi2"))
        aliases << QStringLiteral("pi2") << QStringLiteral("pi 2");
    else
        aliases << QStringLiteral("pi1") << QStringLiteral("pi 1") << QStringLiteral("pi zero") << QStringLiteral("zero w");
    for (const QString &value : values) {
        const QString lower = value.toLower();
        for (const QString &alias : aliases) {
            if (lower.contains(alias))
                return true;
        }
    }
    return false;
}

QString StorageImageFlasher::entryString(const QJsonObject &object,
                                         const QStringList &keys)
{
    for (const QString &key : keys) {
        const QJsonValue value = object.value(key);
        if (value.isString() && !value.toString().trimmed().isEmpty())
            return value.toString().trimmed();
    }
    return {};
}

qulonglong StorageImageFlasher::entrySize(const QJsonObject &object,
                                          const QStringList &keys)
{
    for (const QString &key : keys) {
        const QJsonValue value = object.value(key);
        if (value.isDouble()) {
            qulonglong size = static_cast<qulonglong>(qMax(0.0, value.toDouble()));
            if (key == QStringLiteral("nominal_size") && size < 1024ULL * 1024ULL)
                size *= 1024ULL * 1024ULL;
            return size;
        }
        bool ok = false;
        const qulonglong size = value.toString().toULongLong(&ok);
        if (ok)
            return size;
    }
    return 0;
}

QString StorageImageFlasher::stateDirectory() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/storage-flash"));
}

QString StorageImageFlasher::cacheDirectory() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("cache"));
}

QString StorageImageFlasher::helperPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("scripts/neutronos-image-flasher.py"));
}

QString StorageImageFlasher::newLogPath() const
{
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
    return QDir(stateDirectory()).filePath(QStringLiteral("flash-%1.log").arg(stamp));
}

QString StorageImageFlasher::newConfigPath() const
{
    const QString stamp = QString::number(QDateTime::currentMSecsSinceEpoch());
    return QDir(stateDirectory()).filePath(QStringLiteral("request-%1.json").arg(stamp));
}

QVariantMap StorageImageFlasher::blockDeviceInfo(const QString &devicePath) const
{
    const QString path = cleanDevicePath(devicePath);
    if (path.isEmpty())
        return {};
    const QString lsblk = executable(QStringLiteral("lsblk"));
    if (lsblk.isEmpty())
        return {};
    int exitCode = -1;
    const QByteArray bytes = runBlocking(lsblk,
                                         {QStringLiteral("-J"), QStringLiteral("-b"),
                                          QStringLiteral("-o"),
                                          QStringLiteral("NAME,PATH,TYPE,PKNAME,MOUNTPOINTS,SIZE,RO,RM,MODEL,SERIAL,TRAN,FSTYPE,LABEL")},
                                         15000, &exitCode);
    if (exitCode != 0)
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(bytes);
    const QVariantList devices = flattenBlockDevices(document.object().value(QStringLiteral("blockdevices")).toArray());
    for (const QVariant &entry : devices) {
        const QVariantMap map = entry.toMap();
        if (cleanDevicePath(map.value(QStringLiteral("path")).toString()) != path)
            continue;
        QVariantMap output;
        output.insert(QStringLiteral("path"), path);
        output.insert(QStringLiteral("type"), map.value(QStringLiteral("type")));
        output.insert(QStringLiteral("model"), map.value(QStringLiteral("model")).toString().trimmed());
        output.insert(QStringLiteral("serial"), map.value(QStringLiteral("serial")).toString().trimmed());
        output.insert(QStringLiteral("transport"), map.value(QStringLiteral("tran")).toString().trimmed());
        output.insert(QStringLiteral("readOnly"), map.value(QStringLiteral("ro")).toInt() != 0);
        output.insert(QStringLiteral("removable"), map.value(QStringLiteral("rm")).toInt() != 0);
        output.insert(QStringLiteral("sizeBytes"), map.value(QStringLiteral("size")).toULongLong());
        output.insert(QStringLiteral("size"), humanSize(map.value(QStringLiteral("size")).toULongLong()));
        return output;
    }
    return {};
}

QString StorageImageFlasher::systemDiskPath() const
{
    const QString findmnt = executable(QStringLiteral("findmnt"));
    const QString lsblk = executable(QStringLiteral("lsblk"));
    if (findmnt.isEmpty() || lsblk.isEmpty())
        return {};
    int exitCode = -1;
    QString source = QString::fromUtf8(runBlocking(findmnt,
                                                    {QStringLiteral("-n"), QStringLiteral("-o"), QStringLiteral("SOURCE"), QStringLiteral("/")},
                                                    5000, &exitCode)).trimmed();
    if (exitCode != 0 || !source.startsWith(QStringLiteral("/dev/"))) {
        source = QString::fromUtf8(runBlocking(findmnt,
                                               {QStringLiteral("-n"), QStringLiteral("-o"), QStringLiteral("SOURCE"), QStringLiteral("/boot")},
                                               5000, &exitCode)).trimmed();
    }
    if (!source.startsWith(QStringLiteral("/dev/")))
        return {};
    const QByteArray bytes = runBlocking(lsblk,
                                         {QStringLiteral("-J"), QStringLiteral("-b"),
                                          QStringLiteral("-o"), QStringLiteral("NAME,PATH,TYPE,PKNAME")},
                                         10000, &exitCode);
    if (exitCode != 0)
        return {};
    const QVariantList devices = flattenBlockDevices(QJsonDocument::fromJson(bytes).object()
                                                      .value(QStringLiteral("blockdevices")).toArray());
    return cleanDevicePath(topDiskForPath(cleanDevicePath(source), devices));
}

bool StorageImageFlasher::saveRequestConfig(const QVariantMap &request, QString *error)
{
    QDir().mkpath(stateDirectory());
    m_configPath = newConfigPath();
    QVariantMap customization = request.value(QStringLiteral("customization")).toMap();
    customization.insert(QStringLiteral("raspberryPi"), request.value(QStringLiteral("raspberryPi")).toBool());
    QSaveFile file(m_configPath);
    file.setDirectWriteFallback(true);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (error)
            *error = QStringLiteral("Could not create the temporary image-customization request.");
        return false;
    }
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    const QByteArray json = QJsonDocument::fromVariant(customization).toJson(QJsonDocument::Compact);
    if (file.write(json) != json.size() || !file.commit()) {
        if (error)
            *error = QStringLiteral("Could not save the temporary image-customization request.");
        return false;
    }
    return true;
}

void StorageImageFlasher::resetOperation()
{
    m_busy = false;
    m_stage.clear();
    m_status.clear();
    m_progress = -1;
    m_bytesDone = 0;
    m_bytesTotal = 0;
    m_bytesPerSecond = 0.0;
    m_etaSeconds = -1;
    m_logPath.clear();
    m_canCancel = false;
    m_succeeded = false;
    m_lastError.clear();
    m_targetDevice.clear();
    m_writeStarted = false;
}

void StorageImageFlasher::applyProgressObject(const QJsonObject &object)
{
    const QString incomingStage = object.value(QStringLiteral("stage")).toString();
    if (!incomingStage.isEmpty())
        m_stage = incomingStage;
    const QString message = object.value(QStringLiteral("message")).toString();
    if (!message.isEmpty())
        m_status = message;
    if (object.contains(QStringLiteral("progress")))
        m_progress = object.value(QStringLiteral("progress")).toInt(-1);
    if (object.contains(QStringLiteral("bytesDone")))
        m_bytesDone = object.value(QStringLiteral("bytesDone")).toVariant().toULongLong();
    if (object.contains(QStringLiteral("bytesTotal")))
        m_bytesTotal = object.value(QStringLiteral("bytesTotal")).toVariant().toULongLong();
    if (object.contains(QStringLiteral("speed")))
        m_bytesPerSecond = object.value(QStringLiteral("speed")).toDouble();
    if (object.contains(QStringLiteral("eta")))
        m_etaSeconds = object.value(QStringLiteral("eta")).toVariant().toLongLong();
    if (object.contains(QStringLiteral("logPath")))
        m_logPath = object.value(QStringLiteral("logPath")).toString(m_logPath);
    m_writeStarted = m_writeStarted || m_stage == QStringLiteral("writing") ||
            m_stage == QStringLiteral("synchronizing") || m_stage == QStringLiteral("customizing") ||
            m_stage == QStringLiteral("verifying") || m_stage == QStringLiteral("finalizing");
    m_canCancel = m_busy && !m_writeStarted && m_stage != QStringLiteral("complete") && m_stage != QStringLiteral("failed");
    if (m_stage == QStringLiteral("failed"))
        m_lastError = m_status;
    if (m_stage == QStringLiteral("complete"))
        m_succeeded = true;
    emit operationChanged();
}

void StorageImageFlasher::finish(bool success, const QString &message)
{
    m_busy = false;
    m_canCancel = false;
    m_succeeded = success;
    m_stage = success ? QStringLiteral("complete") : QStringLiteral("failed");
    m_status = message;
    if (!success)
        m_lastError = message;
    if (success)
        m_progress = 100;
    if (!m_configPath.isEmpty())
        QFile::remove(m_configPath);
    emit operationChanged();
    emit operationFinished(success, message);
}
