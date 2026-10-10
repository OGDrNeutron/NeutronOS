#include "SettingsManager.h"
#if defined(NEUTRONOS_PLATFORM_GEMINI)
#include "../platform/gemini/GeminiHardware.h"
#endif

#include <QTimer>

#include "ControllerManager.h"
#include "DeveloperModeManager.h"
#include "NetworkManager.h"
#include "PowerModeManager.h"
#include "ScreensaverManager.h"
#include "StorageManager.h"
#include "UserManager.h"

#include <QtConcurrent/QtConcurrentRun>

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QOperatingSystemVersion>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSet>
#include <QSysInfo>
#include <QTextStream>
#include <QUrl>

#include <algorithm>

#ifdef Q_OS_LINUX
#include <sys/utsname.h>
#include <unistd.h>
#endif

namespace {
QString mapString(const QVariantMap &map, const QString &key, const QString &fallback = QString())
{
    const QString value = map.value(key).toString().trimmed();
    return value.isEmpty() ? fallback : value;
}

bool mapBool(const QVariantMap &map, const QString &key, bool fallback = false)
{
    if (!map.contains(key))
        return fallback;
    const QVariant value = map.value(key);
    if (value.typeId() == QMetaType::Bool)
        return value.toBool();
    const QString text = value.toString().trimmed().toLower();
    return text == QStringLiteral("true") || text == QStringLiteral("1") ||
           text == QStringLiteral("yes") || text == QStringLiteral("on") ||
           text == QStringLiteral("enabled") || text == QStringLiteral("active");
}

bool settingsHighPriorityAuthorizationValid()
{
    if (!qApp)
        return false;
    const QString appId = qApp->property("neutronHighPriorityAppId").toString();
    const qint64 expires = qApp->property("neutronHighPriorityExpiresUtcMs").toLongLong();
    return appId == QStringLiteral("settings") &&
           expires > QDateTime::currentDateTimeUtc().toMSecsSinceEpoch();
}

bool highPrioritySettingsKey(const QString &key)
{
    return key.startsWith(QStringLiteral("performance.")) ||
           key.startsWith(QStringLiteral("advanced.")) ||
           key == QStringLiteral("display.gpuMemory") ||
           key == QStringLiteral("system.bootTarget") ||
           key == QStringLiteral("interfaces.ssh") ||
           key == QStringLiteral("interfaces.vnc") ||
           key == QStringLiteral("interfaces.spi") ||
           key == QStringLiteral("interfaces.i2c") ||
           key == QStringLiteral("interfaces.serial");
}

bool highPrioritySettingsAction(const QString &action)
{
    static const QSet<QString> actions{
        QStringLiteral("restart-shell"), QStringLiteral("reboot"),
        QStringLiteral("shutdown"), QStringLiteral("install-updates"),
        QStringLiteral("expand-filesystem"), QStringLiteral("clear-cache"),
        QStringLiteral("clear-history"), QStringLiteral("validate-boot"),
        QStringLiteral("safe-mode")
    };
    return actions.contains(action);
}

QStringList variantStringList(const QVariant &value)
{
    QStringList result;
    if (value.canConvert<QStringList>())
        result = value.toStringList();
    if (result.isEmpty()) {
        const QVariantList list = value.toList();
        for (const QVariant &entry : list) {
            const QString text = entry.toString().trimmed();
            if (!text.isEmpty())
                result.append(text);
        }
    }
    if (result.isEmpty()) {
        const QString text = value.toString().trimmed();
        if (!text.isEmpty())
            result.append(text);
    }
    result.removeAll(QString());
    result.removeDuplicates();
    return result;
}

QString firstMount(const QVariantMap &device)
{
    const QStringList values = variantStringList(device.value(QStringLiteral("mountPoints")));
    for (const QString &value : values) {
        if (!value.trimmed().isEmpty())
            return QDir::cleanPath(value.trimmed());
    }
    const QString text = device.value(QStringLiteral("mountText")).toString().trimmed();
    if (!text.isEmpty())
        return QDir::cleanPath(text.section(QLatin1Char(','), 0, 0).trimmed());
    return {};
}

void flattenDevices(const QVariantList &source,
                    QVariantList *destination,
                    const QVariantMap &inherited = QVariantMap())
{
    if (!destination)
        return;
    for (const QVariant &entry : source) {
        QVariantMap device = entry.toMap();
        if (device.isEmpty())
            continue;
        for (const QString &key : {QStringLiteral("model"), QStringLiteral("vendor"),
                                   QStringLiteral("serial"), QStringLiteral("transport")}) {
            if (device.value(key).toString().trimmed().isEmpty() &&
                    !inherited.value(key).toString().trimmed().isEmpty())
                device.insert(key, inherited.value(key));
        }
        destination->append(device);
        flattenDevices(device.value(QStringLiteral("children")).toList(), destination, device);
    }
}

QString cpuInfoValue(const QString &key)
{
    QFile file(QStringLiteral("/proc/cpuinfo"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    const QString prefix = key.trimmed().toLower();
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        const int colon = line.indexOf(QLatin1Char(':'));
        if (colon <= 0)
            continue;
        if (line.left(colon).trimmed().toLower() == prefix)
            return line.mid(colon + 1).trimmed();
    }
    return {};
}

quint64 memInfoKiB(const QString &key)
{
    QFile file(QStringLiteral("/proc/meminfo"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return 0;
    const QString prefix = key + QLatin1Char(':');
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (!line.startsWith(prefix))
            continue;
        const QString number = line.mid(prefix.size()).trimmed().section(QLatin1Char(' '), 0, 0);
        return number.toULongLong();
    }
    return 0;
}

QString categoryForFile(const QString &absolutePath, const QFileInfo &info, const QString &mountPath)
{
    const QString lowerPath = absolutePath.toLower();
    const QString suffix = info.suffix().toLower();
    QString relative = lowerPath;
    if (relative.startsWith(mountPath.toLower()))
        relative = relative.mid(mountPath.size());

    static const QSet<QString> video = {
        QStringLiteral("mkv"), QStringLiteral("mp4"), QStringLiteral("m4v"),
        QStringLiteral("avi"), QStringLiteral("mov"), QStringLiteral("webm"),
        QStringLiteral("wmv"), QStringLiteral("flv"), QStringLiteral("ts"),
        QStringLiteral("m2ts"), QStringLiteral("mpg"), QStringLiteral("mpeg"),
        QStringLiteral("vob")
    };
    static const QSet<QString> audio = {
        QStringLiteral("mp3"), QStringLiteral("flac"), QStringLiteral("wav"),
        QStringLiteral("m4a"), QStringLiteral("aac"), QStringLiteral("ogg"),
        QStringLiteral("opus"), QStringLiteral("wma")
    };
    static const QSet<QString> images = {
        QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("png"),
        QStringLiteral("gif"), QStringLiteral("webp"), QStringLiteral("heic"),
        QStringLiteral("bmp"), QStringLiteral("tiff"), QStringLiteral("raw")
    };
    static const QSet<QString> documents = {
        QStringLiteral("pdf"), QStringLiteral("doc"), QStringLiteral("docx"),
        QStringLiteral("odt"), QStringLiteral("txt"), QStringLiteral("rtf"),
        QStringLiteral("xls"), QStringLiteral("xlsx"), QStringLiteral("ods"),
        QStringLiteral("ppt"), QStringLiteral("pptx"), QStringLiteral("csv"),
        QStringLiteral("md"), QStringLiteral("epub")
    };
    static const QSet<QString> archives = {
        QStringLiteral("zip"), QStringLiteral("7z"), QStringLiteral("rar"),
        QStringLiteral("tar"), QStringLiteral("gz"), QStringLiteral("bz2"),
        QStringLiteral("xz"), QStringLiteral("zst"), QStringLiteral("img"),
        QStringLiteral("iso")
    };

    if (video.contains(suffix) || audio.contains(suffix) ||
        relative.contains(QStringLiteral("/movies/")) ||
        relative.contains(QStringLiteral("/tv/")) ||
        relative.contains(QStringLiteral("/media/")) ||
        relative.contains(QStringLiteral("/music/")))
        return QStringLiteral("Media & Video");

    if (images.contains(suffix) || relative.contains(QStringLiteral("/photos/")) ||
        relative.contains(QStringLiteral("/pictures/")))
        return QStringLiteral("Photos");

    if (documents.contains(suffix) || relative.contains(QStringLiteral("/documents/")))
        return QStringLiteral("Documents");

    if (relative.contains(QStringLiteral("/downloads/")))
        return QStringLiteral("Downloads");

    if (relative.contains(QStringLiteral("backup")) ||
        relative.contains(QStringLiteral("snapshot")) ||
        relative.contains(QStringLiteral("timeshift")) || archives.contains(suffix))
        return QStringLiteral("Backups");

    if (relative.startsWith(QStringLiteral("/usr/")) ||
        relative.startsWith(QStringLiteral("/lib/")) ||
        relative.startsWith(QStringLiteral("/lib64/")) ||
        relative.startsWith(QStringLiteral("/boot/")) ||
        relative.startsWith(QStringLiteral("/var/")) ||
        relative.startsWith(QStringLiteral("/etc/")) ||
        relative.startsWith(QStringLiteral("/bin/")) ||
        relative.startsWith(QStringLiteral("/sbin/")))
        return QStringLiteral("System");

    if (relative.contains(QStringLiteral("/apps/")) ||
        relative.contains(QStringLiteral("/docker/")) ||
        relative.contains(QStringLiteral("/containers/")) ||
        relative.contains(QStringLiteral("/opt/")) ||
        suffix == QStringLiteral("appimage"))
        return QStringLiteral("Apps");

    return QStringLiteral("Other");
}

QVariantList categoryListFromMap(const QMap<QString, quint64> &bytes, quint64 usedBytes)
{
    static const QStringList order = {
        QStringLiteral("Media & Video"), QStringLiteral("Photos"),
        QStringLiteral("Apps"), QStringLiteral("System"),
        QStringLiteral("Documents"), QStringLiteral("Downloads"),
        QStringLiteral("Backups"), QStringLiteral("Other")
    };
    static const QMap<QString, QString> colors = {
        {QStringLiteral("Media & Video"), QStringLiteral("#A855F7")},
        {QStringLiteral("Photos"), QStringLiteral("#EC4899")},
        {QStringLiteral("Apps"), QStringLiteral("#4DA6FF")},
        {QStringLiteral("System"), QStringLiteral("#F59E0B")},
        {QStringLiteral("Documents"), QStringLiteral("#22C55E")},
        {QStringLiteral("Downloads"), QStringLiteral("#06B6D4")},
        {QStringLiteral("Backups"), QStringLiteral("#F97316")},
        {QStringLiteral("Other"), QStringLiteral("#64748B")}
    };

    QVariantList result;
    for (const QString &name : order) {
        const quint64 value = bytes.value(name, 0);
        if (value == 0 && name != QStringLiteral("Other"))
            continue;
        QVariantMap item;
        item.insert(QStringLiteral("name"), name);
        item.insert(QStringLiteral("bytes"), QVariant::fromValue(value));
        item.insert(QStringLiteral("formatted"), SettingsManager::humanBytes(value));
        item.insert(QStringLiteral("percent"), usedBytes > 0 ? qRound((double(value) / double(usedBytes)) * 100.0) : 0);
        item.insert(QStringLiteral("color"), colors.value(name, QStringLiteral("#64748B")));
        result.append(item);
    }
    return result;
}
}

SettingsManager::SettingsManager(const QString &neutronRoot,
                                 UserManager *userManager,
                                 StorageManager *storageManager,
                                 DeveloperModeManager *developerModeManager,
                                 ScreensaverManager *screensaverManager,
                                 NetworkManager *networkManager,
                                 ControllerManager *controllerManager,
                                 PowerModeManager *powerModeManager,
                                 QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_userManager(userManager),
      m_storageManager(storageManager),
      m_developerModeManager(developerModeManager),
      m_screensaverManager(screensaverManager),
      m_networkManager(networkManager),
      m_controllerManager(controllerManager),
      m_powerModeManager(powerModeManager)
{
    connect(&m_storageWatcher, &QFutureWatcher<QVariantList>::finished,
            this, &SettingsManager::handleStorageScanFinished);
    connect(&m_integrityWatcher, &QFutureWatcher<QVariantMap>::finished,
            this, &SettingsManager::handleIntegrityCheckFinished);
    connect(&m_operationProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &SettingsManager::handleOperationFinished);

    if (m_developerModeManager) {
        connect(m_developerModeManager, &DeveloperModeManager::developerModeChanged,
                this, [this]() {
                    rebuildValues();
                    emit developerModeChanged();
                    emit valuesChanged();
                });
    }
    if (m_storageManager) {
        connect(m_storageManager, &StorageManager::devicesChanged,
                this, [this]() {
                    rebuildValues();
                    emit valuesChanged();
                });
    }
    if (m_userManager) {
        connect(m_userManager, &UserManager::activeUserChanged,
                this, [this]() { rebuildValues(); emit valuesChanged(); });
        connect(m_userManager, &UserManager::profileRevisionChanged,
                this, [this]() { rebuildValues(); emit valuesChanged(); });
    }

    QDir().mkpath(settingsDirectory());
    loadSettings();
    loadStorageCache();
    rebuildValues();
    QTimer::singleShot(1700, this, &SettingsManager::refresh);
}

SettingsManager::~SettingsManager()
{
    m_cancelStorageScan.store(true);
    if (m_storageWatcher.isRunning())
        m_storageWatcher.waitForFinished();
    if (m_integrityWatcher.isRunning())
        m_integrityWatcher.waitForFinished();
}

QString SettingsManager::themeMode() const { return m_themeMode; }
bool SettingsManager::darkMode() const { return m_themeMode != QStringLiteral("light"); }
QString SettingsManager::dashboardMode() const
{
    const QString mode = m_values.value(QStringLiteral("display.dashboardMode"),
                                        QStringLiteral("modern")).toString().toLower();
    return mode == QStringLiteral("legacy") ? QStringLiteral("legacy") : QStringLiteral("modern");
}
QVariantMap SettingsManager::values() const { return m_values; }
QVariantMap SettingsManager::systemInfo() const { return m_systemInfo; }
QVariantMap SettingsManager::pendingChanges() const { return pendingVariantMap(); }
int SettingsManager::pendingCount() const { return m_pending.size(); }
bool SettingsManager::busy() const { return m_busy; }
QString SettingsManager::operationName() const { return m_operationName; }
QString SettingsManager::operationStatus() const { return m_operationStatus; }
QString SettingsManager::lastMessage() const { return m_lastMessage; }
QVariantList SettingsManager::storageUsage() const { return m_storageUsage; }
bool SettingsManager::storageScanBusy() const { return m_storageScanBusy; }
int SettingsManager::storageScanProgress() const { return m_storageScanProgress; }
bool SettingsManager::developerModeEnabled() const
{
    return m_developerModeManager && m_developerModeManager->developerModeEnabled();
}

QVariantMap SettingsManager::integrityReport() const { return m_integrityReport; }
bool SettingsManager::integrityCheckBusy() const { return m_integrityCheckBusy; }

QString SettingsManager::settingsDirectory() const
{
    return QStringLiteral("/var/lib/neutronos/settings");
}

QString SettingsManager::settingsPath() const
{
    return settingsDirectory() + QStringLiteral("/control-centre.json");
}

QString SettingsManager::storageCachePath() const
{
    return settingsDirectory() + QStringLiteral("/storage-usage.json");
}

QString SettingsManager::readTextFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromUtf8(file.readAll()).trimmed();
}

QString SettingsManager::executable(const QString &name)
{
    return QStandardPaths::findExecutable(name);
}

QString SettingsManager::humanBytes(quint64 bytes)
{
    static const char *units[] = {"B", "KB", "MB", "GB", "TB", "PB"};
    double value = double(bytes);
    int unit = 0;
    while (value >= 1000.0 && unit < 5) {
        value /= 1000.0;
        ++unit;
    }
    return QString::number(value, unit == 0 ? 'f' : 'f', unit == 0 ? 0 : 1) +
           QLatin1Char(' ') + QString::fromLatin1(units[unit]);
}

QString SettingsManager::formatBytes(quint64 bytes) const { return humanBytes(bytes); }

bool SettingsManager::writeTextFileAtomically(const QString &path,
                                              const QByteArray &data,
                                              QString *message)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        if (message)
            *message = file.errorString();
        return false;
    }
    if (file.write(data) != data.size()) {
        if (message)
            *message = file.errorString();
        return false;
    }
    if (!file.commit()) {
        if (message)
            *message = file.errorString();
        return false;
    }
    return true;
}

void SettingsManager::loadSettings()
{
    QFile file(settingsPath());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return;
    const QVariantMap map = document.object().toVariantMap();
    const QString requestedTheme = mapString(map, QStringLiteral("themeMode"), QStringLiteral("dark")).toLower();
    m_themeMode = requestedTheme == QStringLiteral("light") ? QStringLiteral("light") : QStringLiteral("dark");
    const QVariantMap savedValues = map.value(QStringLiteral("values")).toMap();
    for (auto it = savedValues.cbegin(); it != savedValues.cend(); ++it)
        m_values.insert(it.key(), it.value());
}

bool SettingsManager::saveSettings() const
{
    QJsonObject object;
    object.insert(QStringLiteral("version"), 1);
    object.insert(QStringLiteral("themeMode"), m_themeMode);
    object.insert(QStringLiteral("values"), QJsonObject::fromVariantMap(m_values));
    object.insert(QStringLiteral("savedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    QString message;
    return writeTextFileAtomically(settingsPath(), QJsonDocument(object).toJson(QJsonDocument::Indented), &message);
}

bool SettingsManager::setDashboardMode(const QString &mode)
{
    const QString normalized = mode.trimmed().toLower();
    if (normalized != QStringLiteral("modern") && normalized != QStringLiteral("legacy"))
        return false;
    if (dashboardMode() == normalized)
        return true;
    m_values.insert(QStringLiteral("display.dashboardMode"), normalized);
    if (!saveSettings())
        return false;
    emit dashboardModeChanged();
    emit valuesChanged();
    return true;
}

bool SettingsManager::setUiPreference(const QString &key, const QVariant &value)
{
    // UI-only preferences are deliberately separated from privileged settings
    // application.  They may never name a system, network, boot, or service key.
    static const QRegularExpression allowed(QStringLiteral("^ui\\.[A-Za-z0-9_.-]{1,80}$"));
    if (!allowed.match(key).hasMatch())
        return false;
    if (m_values.value(key) == value)
        return true;
    m_values.insert(key, value);
    if (!saveSettings())
        return false;
    emit valuesChanged();
    return true;
}

void SettingsManager::loadStorageCache()
{
    QFile file(storageCachePath());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return;
    m_storageUsage = document.object().value(QStringLiteral("devices")).toArray().toVariantList();
}

bool SettingsManager::saveStorageCache() const
{
    QJsonObject object;
    object.insert(QStringLiteral("version"), 1);
    object.insert(QStringLiteral("scannedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    object.insert(QStringLiteral("devices"), QJsonArray::fromVariantList(m_storageUsage));
    QString message;
    return writeTextFileAtomically(storageCachePath(), QJsonDocument(object).toJson(QJsonDocument::Indented), &message);
}

QString SettingsManager::bootConfigText() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    return QString();
#else
    QStringList sections;
    for (const QString &candidate : {QStringLiteral("/boot/firmware/config.txt"),
                                     QStringLiteral("/boot/config.txt")}) {
        QFile file(candidate);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        sections.append(QString::fromUtf8(file.readAll()));
    }
    return sections.join(QLatin1Char('\n'));
#endif
}

bool SettingsManager::bootConfigEnabled(const QString &key, bool fallback) const
{
    const QString text = bootConfigText();
    if (text.isEmpty())
        return fallback;

    QString pattern;
    if (key == QStringLiteral("spi") || key == QStringLiteral("i2c_arm")) {
        pattern = QStringLiteral("^\\s*dtparam\\s*=\\s*%1\\s*=\\s*([^#\\s]+)")
                      .arg(QRegularExpression::escape(key));
    } else {
        pattern = QStringLiteral("^\\s*%1\\s*=\\s*([^#\\s]+)")
                      .arg(QRegularExpression::escape(key));
    }

    QRegularExpression expression(pattern,
                                  QRegularExpression::MultilineOption |
                                  QRegularExpression::CaseInsensitiveOption);
    QRegularExpressionMatchIterator matches = expression.globalMatch(text);
    QString value;
    while (matches.hasNext())
        value = matches.next().captured(1).trimmed().toLower();
    if (value.isEmpty())
        return fallback;
    return value == QStringLiteral("1") || value == QStringLiteral("on") ||
           value == QStringLiteral("true") || value == QStringLiteral("yes") ||
           value == QStringLiteral("enabled");
}

bool SettingsManager::bootOverlayEnabled(const QString &overlayPrefix) const
{
    const QString text = bootConfigText();
    if (text.isEmpty())
        return false;
    const QRegularExpression expression(
        QStringLiteral("^\\s*dtoverlay\\s*=\\s*%1(?:[,\\s]|$)")
            .arg(QRegularExpression::escape(overlayPrefix)),
        QRegularExpression::MultilineOption |
        QRegularExpression::CaseInsensitiveOption);
    return expression.match(text).hasMatch();
}

bool SettingsManager::serviceInstalled(const QStringList &units) const
{
    const QString systemctl = executable(QStringLiteral("systemctl"));
    if (systemctl.isEmpty())
        return false;
    for (const QString &unit : units) {
        QProcess process;
        process.start(systemctl, {QStringLiteral("show"), QStringLiteral("--property=LoadState"),
                                  QStringLiteral("--value"), unit});
        if (!process.waitForStarted(1000) || !process.waitForFinished(2200))
            continue;
        const QString state = QString::fromUtf8(process.readAllStandardOutput()).trimmed().toLower();
        if (!state.isEmpty() && state != QStringLiteral("not-found"))
            return true;
    }
    return false;
}

bool SettingsManager::serviceActive(const QStringList &units) const
{
    const QString systemctl = executable(QStringLiteral("systemctl"));
    if (systemctl.isEmpty())
        return false;
    for (const QString &unit : units) {
        for (const QString &verb : {QStringLiteral("is-active"), QStringLiteral("is-enabled")}) {
            QProcess process;
            process.start(systemctl, {verb, QStringLiteral("--quiet"), unit});
            if (process.waitForStarted(1000) && process.waitForFinished(2200) &&
                    process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0)
                return true;
        }
    }
    return false;
}

QString SettingsManager::serviceDisplayState(const QStringList &units) const
{
    if (!serviceInstalled(units))
        return QStringLiteral("UNAVAILABLE");
    return serviceActive(units) ? QStringLiteral("ON") : QStringLiteral("OFF");
}

void SettingsManager::rebuildSystemInfo()
{
    QVariantMap info;
    info.insert(QStringLiteral("hostname"), readTextFile(QStringLiteral("/etc/hostname")));
    info.insert(QStringLiteral("kernel"), QSysInfo::kernelVersion());
    info.insert(QStringLiteral("architecture"), QSysInfo::currentCpuArchitecture());
    info.insert(QStringLiteral("productType"), QSysInfo::productType());
    info.insert(QStringLiteral("productVersion"), QSysInfo::productVersion());
    info.insert(QStringLiteral("prettyProductName"), QSysInfo::prettyProductName());
    info.insert(QStringLiteral("machineId"), QString::fromLatin1(QSysInfo::machineUniqueId().toHex().left(16)));

#if defined(NEUTRONOS_PLATFORM_GEMINI)
    QString model = GeminiHardware::model();
    if (model.isEmpty()) model = QStringLiteral("x86_64 PC");
    info.insert(QStringLiteral("model"), model);
    info.insert(QStringLiteral("isRaspberryPi"), false);
    info.insert(QStringLiteral("boardRevision"), GeminiHardware::dmiValue(QStringLiteral("board_version")));
    info.insert(QStringLiteral("serial"), GeminiHardware::dmiValue(QStringLiteral("product_serial")));
#else
    QString model = readTextFile(QStringLiteral("/proc/device-tree/model"));
    model.remove(QChar('\0'));
    if (model.isEmpty())
        model = cpuInfoValue(QStringLiteral("model name"));
    if (model.isEmpty())
        model = QStringLiteral("Linux device");
    const bool raspberryPi = model.contains(QStringLiteral("Raspberry Pi"), Qt::CaseInsensitive) ||
                             QFileInfo::exists(QStringLiteral("/proc/device-tree/hat"));
    info.insert(QStringLiteral("model"), model);
    info.insert(QStringLiteral("isRaspberryPi"), raspberryPi);
    info.insert(QStringLiteral("boardRevision"), cpuInfoValue(QStringLiteral("revision")));
    info.insert(QStringLiteral("serial"), cpuInfoValue(QStringLiteral("serial")));
#endif
    info.insert(QStringLiteral("cpuModel"), cpuInfoValue(QStringLiteral("model name")));

    QString output;
    QString message;
    QString bootTarget = QStringLiteral("unknown");
    if (runCommandBlocking(QStringLiteral("systemctl"), {QStringLiteral("get-default")}, 2500, &output, &message))
        bootTarget = output.trimmed();
    info.insert(QStringLiteral("bootTarget"), bootTarget);

#if defined(NEUTRONOS_PLATFORM_GEMINI)
    const QString firmware = GeminiHardware::firmware();
#else
    QString firmware;
    if (raspberryPi && runCommandBlocking(QStringLiteral("vcgencmd"), {QStringLiteral("version")}, 2500, &output, &message))
        firmware = output.section(QLatin1Char('\n'), 0, 0).trimmed();
#endif
    info.insert(QStringLiteral("firmware"), firmware.isEmpty() ? QStringLiteral("Unavailable") : firmware);

    QStorageInfo root(QStringLiteral("/"));
    info.insert(QStringLiteral("rootTotalBytes"), QVariant::fromValue(root.bytesTotal()));
    info.insert(QStringLiteral("rootFreeBytes"), QVariant::fromValue(root.bytesAvailable()));
    info.insert(QStringLiteral("rootTotal"), humanBytes(root.bytesTotal()));
    info.insert(QStringLiteral("rootFree"), humanBytes(root.bytesAvailable()));
    const quint64 memoryKiB = memInfoKiB(QStringLiteral("MemTotal"));
    info.insert(QStringLiteral("memoryBytes"), QVariant::fromValue(memoryKiB * 1024ULL));
    info.insert(QStringLiteral("memory"), humanBytes(memoryKiB * 1024ULL));
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    info.insert(QStringLiteral("neutronVersion"), QStringLiteral("0.5 candidate"));
    info.insert(QStringLiteral("edition"), QStringLiteral("Gemini"));
    info.insert(QStringLiteral("codename"), QStringLiteral("Gemini"));
#else
    info.insert(QStringLiteral("neutronVersion"), QStringLiteral("1.0.0-alpha.1"));
    info.insert(QStringLiteral("edition"), QStringLiteral("Apollo"));
    info.insert(QStringLiteral("codename"), QStringLiteral("Apollo"));
#endif
    info.insert(QStringLiteral("qtVersion"), QString::fromLatin1(qVersion()));
    m_systemInfo = info;
}

void SettingsManager::rebuildValues()
{
    if (!m_values.contains(QStringLiteral("display.dashboardMode")))
        m_values.insert(QStringLiteral("display.dashboardMode"), QStringLiteral("modern"));
    m_values.insert(QStringLiteral("theme.mode"), m_themeMode);
    m_values.insert(QStringLiteral("system.hostname"), m_systemInfo.value(QStringLiteral("hostname")));

    const QString bootTarget = m_systemInfo.value(QStringLiteral("bootTarget")).toString();
    m_values.insert(QStringLiteral("system.bootTarget"),
                    bootTarget == QStringLiteral("graphical.target") ? QStringLiteral("desktop") :
                    bootTarget == QStringLiteral("multi-user.target") ? QStringLiteral("cli") :
                    QStringLiteral("neutronos"));
    m_values.insert(QStringLiteral("developer.enabled"), developerModeEnabled());

    const QStringList sshUnits{QStringLiteral("ssh.service"), QStringLiteral("ssh.socket"),
                               QStringLiteral("sshd.service")};
    const QStringList vncUnits{QStringLiteral("vncserver-x11-serviced.service"),
                               QStringLiteral("wayvnc.service"), QStringLiteral("tigervncserver.service")};
    const QStringList bluetoothUnits{QStringLiteral("bluetooth.service")};
    m_values.insert(QStringLiteral("interfaces.ssh"), serviceActive(sshUnits));
    m_values.insert(QStringLiteral("interfaces.sshState"), serviceDisplayState(sshUnits));
    m_values.insert(QStringLiteral("interfaces.vnc"), serviceActive(vncUnits));
    m_values.insert(QStringLiteral("interfaces.vncState"), serviceDisplayState(vncUnits));
    m_values.insert(QStringLiteral("interfaces.bluetooth"), serviceActive(bluetoothUnits));
    m_values.insert(QStringLiteral("interfaces.bluetoothState"), serviceDisplayState(bluetoothUnits));
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    for (const QString &key : {QStringLiteral("spi"), QStringLiteral("i2c"), QStringLiteral("serial"),
                              QStringLiteral("onewire"), QStringLiteral("infrared"), QStringLiteral("gpio")}) {
        m_values.insert(QStringLiteral("interfaces.") + key, false);
        m_values.insert(QStringLiteral("interfaces.") + key + QStringLiteral("State"), QStringLiteral("UNAVAILABLE"));
    }
    const bool camera = !QDir(QStringLiteral("/sys/class/video4linux")).entryList(QDir::Dirs | QDir::NoDotAndDotDot).isEmpty();
    m_values.insert(QStringLiteral("interfaces.camera"), camera);
    m_values.insert(QStringLiteral("interfaces.cameraState"), camera ? QStringLiteral("ON") : QStringLiteral("UNAVAILABLE"));
    m_values.insert(QStringLiteral("display.gpuMemory"), 0);
    m_values.insert(QStringLiteral("display.overscan"), false);
    m_values.insert(QStringLiteral("display.forceHdmi"), false);
    m_values.insert(QStringLiteral("display.cec"), false);
    quint64 minimum = 0, maximum = 0, currentMaximum = 0;
    QString governor;
    for (const QString &policy : GeminiHardware::cpuPolicies()) {
        const quint64 low = GeminiHardware::frequencyKhz(policy, QStringLiteral("cpuinfo_min_freq"));
        const quint64 high = GeminiHardware::frequencyKhz(policy, QStringLiteral("cpuinfo_max_freq"));
        if (!low || !high) continue;
        minimum = qMax(minimum, low);
        maximum = maximum ? qMin(maximum, high) : high;
        const quint64 current = GeminiHardware::frequencyKhz(policy, QStringLiteral("scaling_max_freq"));
        currentMaximum = currentMaximum ? qMin(currentMaximum, current) : current;
        if (governor.isEmpty()) governor = GeminiHardware::readText(QDir(policy).filePath(QStringLiteral("scaling_governor")));
    }
    m_values.insert(QStringLiteral("performance.minSupportedFrequency"), (minimum + 999ULL) / 1000ULL);
    m_values.insert(QStringLiteral("performance.maxSupportedFrequency"), maximum / 1000ULL);
    m_values.insert(QStringLiteral("performance.maxFrequency"), currentMaximum / 1000ULL);
    m_values.insert(QStringLiteral("performance.governor"), governor);
#else
    m_values.insert(QStringLiteral("interfaces.camera"), bootConfigEnabled(QStringLiteral("camera_auto_detect"), true));
    m_values.insert(QStringLiteral("interfaces.spi"), bootConfigEnabled(QStringLiteral("spi"), false));
    m_values.insert(QStringLiteral("interfaces.i2c"), bootConfigEnabled(QStringLiteral("i2c_arm"), false));
    m_values.insert(QStringLiteral("interfaces.serial"), bootConfigEnabled(QStringLiteral("enable_uart"), false));
    m_values.insert(QStringLiteral("interfaces.onewire"), bootOverlayEnabled(QStringLiteral("w1-gpio")));
    m_values.insert(QStringLiteral("interfaces.infrared"),
                    bootOverlayEnabled(QStringLiteral("gpio-ir")) ||
                    bootOverlayEnabled(QStringLiteral("gpio-ir-tx")));

    QString groupOutput;
    QString groupMessage;
    const bool gpioAccess = runCommandBlocking(QStringLiteral("id"),
                                                {QStringLiteral("-nG"), activeUsername()},
                                                2500, &groupOutput, &groupMessage) &&
                            groupOutput.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts)
                                .contains(QStringLiteral("gpio"));
    m_values.insert(QStringLiteral("interfaces.gpio"), gpioAccess);

    m_values.insert(QStringLiteral("display.gpuMemory"), 128);
    const QString config = bootConfigText();
    QRegularExpression gpuExpression(QStringLiteral("^\\s*gpu_mem\\s*=\\s*(\\d+)") , QRegularExpression::MultilineOption);
    const QRegularExpressionMatch gpuMatch = gpuExpression.match(config);
    if (gpuMatch.hasMatch())
        m_values.insert(QStringLiteral("display.gpuMemory"), gpuMatch.captured(1).toInt());
    m_values.insert(QStringLiteral("display.overscan"), !bootConfigEnabled(QStringLiteral("disable_overscan"), true));
    m_values.insert(QStringLiteral("display.forceHdmi"), bootConfigEnabled(QStringLiteral("hdmi_force_hotplug"), false));
    m_values.insert(QStringLiteral("display.cec"), !bootConfigEnabled(QStringLiteral("hdmi_ignore_cec"), false));

#endif

    QString timezone = readTextFile(QStringLiteral("/etc/timezone"));
    if (timezone.isEmpty()) {
        QString output;
        QString message;
        if (runCommandBlocking(QStringLiteral("timedatectl"),
                               {QStringLiteral("show"), QStringLiteral("--property=Timezone"),
                                QStringLiteral("--value")}, 2500, &output, &message))
            timezone = output.trimmed();
    }
    if (!timezone.isEmpty())
        m_values.insert(QStringLiteral("localization.timezone"), timezone);

    if (m_userManager) {
        m_values.insert(QStringLiteral("user.name"), m_userManager->displayName());
        m_values.insert(QStringLiteral("user.username"), m_userManager->username());
        m_values.insert(QStringLiteral("user.avatar"), m_userManager->avatarSource());
        m_values.insert(QStringLiteral("user.role"), m_userManager->role());
        m_values.insert(QStringLiteral("user.tagline"), m_userManager->profileTagline());
    }
    if (m_screensaverManager) {
        m_values.insert(QStringLiteral("appearance.screensaverEnabled"), m_screensaverManager->enabled());
        m_values.insert(QStringLiteral("appearance.screensaverMinutes"), m_screensaverManager->timeoutMinutes());
    }
    if (m_networkManager) {
        m_values.insert(QStringLiteral("network.ssid"), m_networkManager->connectedSsid());
        m_values.insert(QStringLiteral("network.connected"), m_networkManager->connectionState().compare(QStringLiteral("connected"), Qt::CaseInsensitive) == 0);
        m_values.insert(QStringLiteral("network.wifiEnabled"), m_networkManager->wifiEnabled());
        m_values.insert(QStringLiteral("network.ip"), m_networkManager->localIp());
    }
    if (m_controllerManager) {
        m_values.insert(QStringLiteral("controller.connected"), m_controllerManager->controllerConnected());
        m_values.insert(QStringLiteral("controller.name"), m_controllerManager->controllerName());
        m_values.insert(QStringLiteral("controller.type"), m_controllerManager->controllerType());
        m_values.insert(QStringLiteral("controller.battery"), m_controllerManager->controllerBatteryPercent());
        m_values.insert(QStringLiteral("controller.charging"), m_controllerManager->controllerCharging());
    }
    if (m_powerModeManager)
        m_values.insert(QStringLiteral("power.mode"), m_powerModeManager->mode());
}

void SettingsManager::refresh()
{
    if (m_developerModeManager)
        m_developerModeManager->refresh();
    if (m_powerModeManager)
        m_powerModeManager->refresh();
    if (m_storageManager)
        m_storageManager->refreshDevices();
    if (m_networkManager)
        m_networkManager->refresh();
    if (m_controllerManager) {
        m_controllerManager->refreshControllerIdentity();
        m_controllerManager->refreshBattery();
    }
    rebuildSystemInfo();
    rebuildValues();
    emit valuesChanged();
    emit developerModeChanged();
}

QVariant SettingsManager::value(const QString &key, const QVariant &fallback) const
{
    if (m_pending.contains(key))
        return m_pending.value(key).value;
    return m_values.value(key, fallback);
}

bool SettingsManager::queueChange(const QString &key, const QVariant &newValue, const QString &applyMode)
{
    const QString cleanKey = key.trimmed();
    if (cleanKey.isEmpty())
        return false;
    PendingEntry entry;
    entry.value = newValue;
    entry.applyMode = applyMode.trimmed().isEmpty() ? QStringLiteral("apply") : applyMode.trimmed().toLower();
    m_pending.insert(cleanKey, entry);
    emit pendingChangesChanged();
    return true;
}

bool SettingsManager::setThemeMode(const QString &mode)
{
    const QString normalized = mode.trimmed().toLower();
    const QString next = normalized == QStringLiteral("light") ? QStringLiteral("light") : QStringLiteral("dark");
    if (m_themeMode == next)
        return true;
    m_themeMode = next;
    m_values.insert(QStringLiteral("theme.mode"), m_themeMode);
    saveSettings();
    emit themeChanged();
    emit valuesChanged();
    return true;
}

void SettingsManager::discardPending()
{
    if (m_pending.isEmpty())
        return;
    m_pending.clear();
    emit pendingChangesChanged();
}

QVariantMap SettingsManager::pendingVariantMap() const
{
    QVariantMap result;
    for (auto it = m_pending.cbegin(); it != m_pending.cend(); ++it) {
        QVariantMap entry;
        entry.insert(QStringLiteral("value"), it.value().value);
        entry.insert(QStringLiteral("applyMode"), it.value().applyMode);
        result.insert(it.key(), entry);
    }
    return result;
}

QVariantMap SettingsManager::validatePending() const
{
    QVariantMap result;
    QStringList errors;
    bool reboot = false;
    bool logout = false;
    for (auto it = m_pending.cbegin(); it != m_pending.cend(); ++it) {
        if (it.key() == QStringLiteral("system.hostname") && !validHostname(it.value().value.toString()))
            errors << QStringLiteral("Hostname is invalid.");
        reboot = reboot || it.value().applyMode == QStringLiteral("reboot");
        logout = logout || it.value().applyMode == QStringLiteral("logout");
    }
    result.insert(QStringLiteral("ok"), errors.isEmpty());
    result.insert(QStringLiteral("errors"), errors);
    result.insert(QStringLiteral("rebootRequired"), reboot);
    result.insert(QStringLiteral("logoutRequired"), logout);
    result.insert(QStringLiteral("count"), m_pending.size());
    return result;
}

bool SettingsManager::applyPending()
{
    const QVariantMap validation = validatePending();
    if (!validation.value(QStringLiteral("ok")).toBool()) {
        m_lastMessage = validation.value(QStringLiteral("errors")).toStringList().join(QStringLiteral(" "));
        emit operationChanged();
        return false;
    }

    bool containsHighPriorityChange = false;
    for (auto it = m_pending.cbegin(); it != m_pending.cend(); ++it)
        containsHighPriorityChange = containsHighPriorityChange || highPrioritySettingsKey(it.key());

    if (m_values.value(QStringLiteral("user.autoLogin"), false).toBool() &&
            containsHighPriorityChange && !settingsHighPriorityAuthorizationValid()) {
        m_lastMessage = QStringLiteral(
            "Login password authorization is required while Automatic Login is enabled.");
        emit operationChanged();
        return false;
    }

    bool reboot = false;
    bool logout = false;
    QStringList applied;
    QStringList failed;
    const auto copy = m_pending;
    for (auto it = copy.cbegin(); it != copy.cend(); ++it) {
        QString message;
        if (applyOne(it.key(), it.value().value, &message)) {
            m_values.insert(it.key(), it.value().value);
            applied << it.key();
            reboot = reboot || it.value().applyMode == QStringLiteral("reboot");
            logout = logout || it.value().applyMode == QStringLiteral("logout");
            m_pending.remove(it.key());
        } else {
            failed << (it.key() + QStringLiteral(": ") + message);
        }
    }
    saveSettings();
    rebuildSystemInfo();
    rebuildValues();
    emit pendingChangesChanged();
    emit valuesChanged();

    if (!failed.isEmpty()) {
        m_lastMessage = QStringLiteral("Some settings could not be applied: ") + failed.join(QStringLiteral(" | "));
        emit operationChanged();
        return false;
    }

    m_lastMessage = QStringLiteral("Applied %1 setting%2.").arg(applied.size()).arg(applied.size() == 1 ? QString() : QStringLiteral("s"));
    emit operationChanged();
    if (reboot)
        emit rebootRequired(QStringLiteral("One or more settings affect boot-time configuration."));
    if (logout)
        emit logoutRequired(QStringLiteral("One or more settings require a new login session."));
    return true;
}

bool SettingsManager::validHostname(const QString &hostname) const
{
    const QString value = hostname.trimmed();
    if (value.isEmpty() || value.size() > 63)
        return false;
    static const QRegularExpression pattern(QStringLiteral("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"));
    return pattern.match(value).hasMatch();
}

bool SettingsManager::validUsername(const QString &username) const
{
    static const QRegularExpression pattern(QStringLiteral("^[a-z_][a-z0-9_-]{0,30}$"));
    return pattern.match(username.trimmed()).hasMatch();
}

bool SettingsManager::runCommandBlocking(const QString &program,
                                         const QStringList &arguments,
                                         int timeoutMs,
                                         QString *output,
                                         QString *message) const
{
    const QString path = program.contains(QLatin1Char('/')) ? program : executable(program);
    if (path.isEmpty()) {
        if (message)
            *message = QStringLiteral("Required command is not installed: ") + program;
        return false;
    }
    QProcess process;
    process.start(path, arguments);
    if (!process.waitForStarted(2500)) {
        if (message)
            *message = process.errorString();
        return false;
    }
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(1000);
        if (message)
            *message = QStringLiteral("Operation timed out.");
        return false;
    }
    const QString standard = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    const QString error = QString::fromUtf8(process.readAllStandardError()).trimmed();
    if (output)
        *output = standard;
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        if (message)
            *message = error.isEmpty() ? standard : error;
        return false;
    }
    if (message)
        *message = standard;
    return true;
}

bool SettingsManager::writeBootConfigValue(const QString &key, const QString &value, QString *message)
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    Q_UNUSED(key)
    Q_UNUSED(value)
    if (message) *message = QStringLiteral("Raspberry Pi firmware settings are unavailable on Gemini.");
    return false;
#else
    QString path;
    for (const QString &candidate : {QStringLiteral("/boot/firmware/config.txt"), QStringLiteral("/boot/config.txt")}) {
        if (QFileInfo::exists(candidate)) {
            path = candidate;
            break;
        }
    }
    if (path.isEmpty()) {
        if (message)
            *message = QStringLiteral("Raspberry Pi boot configuration was not found.");
        return false;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (message)
            *message = file.errorString();
        return false;
    }
    QStringList lines = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
    file.close();
    const QString prefix = key + QLatin1Char('=');
    bool replaced = false;
    for (QString &line : lines) {
        const QString trimmed = line.trimmed();
        if (trimmed.startsWith(prefix) || trimmed.startsWith(QStringLiteral("#") + prefix)) {
            line = prefix + value;
            replaced = true;
            break;
        }
    }
    if (!replaced)
        lines.append(prefix + value);
    return writeTextFileAtomically(path, lines.join(QLatin1Char('\n')).toUtf8(), message);
#endif
}

bool SettingsManager::setServiceEnabled(const QStringList &units, bool enabled, QString *message)
{
    for (const QString &unit : units) {
        QString output;
        QString localMessage;
        const bool exists = runCommandBlocking(QStringLiteral("systemctl"),
                                               {QStringLiteral("status"), unit, QStringLiteral("--no-pager")},
                                               3500, &output, &localMessage) ||
                            localMessage.contains(QStringLiteral("inactive"), Qt::CaseInsensitive) ||
                            localMessage.contains(QStringLiteral("disabled"), Qt::CaseInsensitive);
        if (!exists && localMessage.contains(QStringLiteral("could not be found"), Qt::CaseInsensitive))
            continue;
        const QStringList arguments = enabled
            ? QStringList{QStringLiteral("enable"), QStringLiteral("--now"), unit}
            : QStringList{QStringLiteral("disable"), QStringLiteral("--now"), unit};
        if (runCommandBlocking(QStringLiteral("systemctl"), arguments, 15000, &output, &localMessage)) {
            if (message)
                *message = enabled ? QStringLiteral("Service enabled.") : QStringLiteral("Service disabled.");
            return true;
        }
        if (message)
            *message = localMessage;
    }
    if (message && message->isEmpty())
        *message = QStringLiteral("No supported service unit was found.");
    return false;
}

bool SettingsManager::applyOne(const QString &key, const QVariant &newValue, QString *message)
{
    if (key == QStringLiteral("theme.mode"))
        return setThemeMode(newValue.toString());
    if (key == QStringLiteral("display.dashboardMode")) {
        const bool saved = setDashboardMode(newValue.toString());
        if (message)
            *message = saved ? QStringLiteral("Dashboard changed.")
                             : QStringLiteral("Dashboard must be Modern or Legacy.");
        return saved;
    }
    if (key == QStringLiteral("display.userClockBackground")) {
        QString path = newValue.toString().trimmed();
        if (path.startsWith(QStringLiteral("file://")))
            path = QUrl(path).toLocalFile();
        if (path.isEmpty()) {
            if (message) *message = QStringLiteral("Default User / Clock artwork restored.");
            return true;
        }
        const QFileInfo info(path);
        const QString canonical = info.canonicalFilePath();
        const QString suffix = info.suffix().toLower();
        const bool approvedRoot = canonical.startsWith(QStringLiteral("/home/echo/")) ||
                                  canonical.startsWith(QStringLiteral("/mnt/"));
        if (!info.isFile() || info.isSymLink() || !approvedRoot ||
                !QStringList{QStringLiteral("png"), QStringLiteral("jpg"),
                             QStringLiteral("jpeg"), QStringLiteral("webp")}.contains(suffix)) {
            if (message) *message = QStringLiteral("Choose a PNG, JPEG or WebP image from your home or mounted media.");
            return false;
        }
        if (message) *message = QStringLiteral("User / Clock artwork saved.");
        return true;
    }

    if (key == QStringLiteral("system.hostname")) {
        const QString hostname = newValue.toString().trimmed();
        if (!validHostname(hostname)) {
            if (message) *message = QStringLiteral("Invalid hostname.");
            return false;
        }
        QString output;
        return runCommandBlocking(QStringLiteral("hostnamectl"), {QStringLiteral("set-hostname"), hostname}, 8000, &output, message);
    }

    if (key == QStringLiteral("system.bootTarget")) {
        const QString mode = newValue.toString().toLower();
        QString target;
        if (mode == QStringLiteral("desktop")) target = QStringLiteral("graphical.target");
        else if (mode == QStringLiteral("cli")) target = QStringLiteral("multi-user.target");
        else target = QStringLiteral("neutronos.target");
        QString output;
        return runCommandBlocking(QStringLiteral("systemctl"), {QStringLiteral("set-default"), target}, 8000, &output, message);
    }

    if (key == QStringLiteral("interfaces.ssh"))
        return setServiceEnabled({QStringLiteral("ssh.service"), QStringLiteral("sshd.service")}, newValue.toBool(), message);
    if (key == QStringLiteral("interfaces.vnc"))
        return setServiceEnabled({QStringLiteral("vncserver-x11-serviced.service"), QStringLiteral("wayvnc.service")}, newValue.toBool(), message);
    if (key == QStringLiteral("interfaces.bluetooth"))
        return setServiceEnabled({QStringLiteral("bluetooth.service")}, newValue.toBool(), message);
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    const QSet<QString> firmwareSettings{
        QStringLiteral("interfaces.spi"), QStringLiteral("interfaces.i2c"), QStringLiteral("interfaces.serial"),
        QStringLiteral("interfaces.onewire"), QStringLiteral("interfaces.camera"), QStringLiteral("interfaces.gpio"),
        QStringLiteral("interfaces.infrared"), QStringLiteral("display.gpuMemory"), QStringLiteral("display.overscan"),
        QStringLiteral("display.forceHdmi"), QStringLiteral("display.cec"), QStringLiteral("display.rotation"),
        QStringLiteral("display.colorRange"), QStringLiteral("display.resolution")};
    if (firmwareSettings.contains(key)) {
        if (message) *message = QStringLiteral("This Raspberry Pi firmware control is unavailable on Gemini. PC devices use standard Linux drivers.");
        return false;
    }
#else
    if (key == QStringLiteral("interfaces.spi"))
        return writeBootConfigValue(QStringLiteral("dtparam=spi"), newValue.toBool() ? QStringLiteral("on") : QStringLiteral("off"), message);
    if (key == QStringLiteral("interfaces.i2c"))
        return writeBootConfigValue(QStringLiteral("dtparam=i2c_arm"), newValue.toBool() ? QStringLiteral("on") : QStringLiteral("off"), message);
    if (key == QStringLiteral("interfaces.serial"))
        return writeBootConfigValue(QStringLiteral("enable_uart"), newValue.toBool() ? QStringLiteral("1") : QStringLiteral("0"), message);
    if (key == QStringLiteral("interfaces.onewire"))
        return writeBootConfigValue(QStringLiteral("dtoverlay"), newValue.toBool() ? QStringLiteral("w1-gpio") : QStringLiteral("disable-w1"), message);
    if (key == QStringLiteral("interfaces.camera"))
        return writeBootConfigValue(QStringLiteral("camera_auto_detect"), newValue.toBool() ? QStringLiteral("1") : QStringLiteral("0"), message);
    if (key == QStringLiteral("interfaces.gpio")) {
        QString output;
        if (newValue.toBool())
            return runCommandBlocking(QStringLiteral("usermod"),
                                      {QStringLiteral("-aG"), QStringLiteral("gpio"), activeUsername()},
                                      8000, &output, message);
        return runCommandBlocking(QStringLiteral("gpasswd"),
                                  {QStringLiteral("-d"), activeUsername(), QStringLiteral("gpio")},
                                  8000, &output, message);
    }
    if (key == QStringLiteral("interfaces.infrared")) {
        const QString configPath = QFileInfo::exists(QStringLiteral("/boot/firmware/config.txt"))
            ? QStringLiteral("/boot/firmware/config.txt") : QStringLiteral("/boot/config.txt");
        QFile file(configPath);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            if (message) *message = file.errorString();
            return false;
        }
        QStringList lines = QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
        file.close();
        bool found = false;
        for (QString &line : lines) {
            const QString trimmed = line.trimmed();
            if (trimmed.startsWith(QStringLiteral("dtoverlay=gpio-ir"), Qt::CaseInsensitive)) {
                line = newValue.toBool() ? QStringLiteral("dtoverlay=gpio-ir")
                                         : QStringLiteral("#dtoverlay=gpio-ir");
                found = true;
            }
        }
        if (newValue.toBool() && !found)
            lines.append(QStringLiteral("dtoverlay=gpio-ir"));
        return writeTextFileAtomically(configPath, lines.join(QLatin1Char('\n')).toUtf8(), message);
    }
    if (key == QStringLiteral("display.gpuMemory"))
        return writeBootConfigValue(QStringLiteral("gpu_mem"), QString::number(qBound(64, newValue.toInt(), 512)), message);
    if (key == QStringLiteral("display.overscan"))
        return writeBootConfigValue(QStringLiteral("disable_overscan"), newValue.toBool() ? QStringLiteral("0") : QStringLiteral("1"), message);
    if (key == QStringLiteral("display.forceHdmi"))
        return writeBootConfigValue(QStringLiteral("hdmi_force_hotplug"), newValue.toBool() ? QStringLiteral("1") : QStringLiteral("0"), message);
    if (key == QStringLiteral("display.cec"))
        return writeBootConfigValue(QStringLiteral("hdmi_ignore_cec"), newValue.toBool() ? QStringLiteral("0") : QStringLiteral("1"), message);
    if (key == QStringLiteral("display.rotation")) {
        const QString rotation = newValue.toString();
        const QString code = rotation == QStringLiteral("90") ? QStringLiteral("1")
                           : rotation == QStringLiteral("180") ? QStringLiteral("2")
                           : rotation == QStringLiteral("270") ? QStringLiteral("3")
                           : QStringLiteral("0");
        return writeBootConfigValue(QStringLiteral("display_hdmi_rotate"), code, message);
    }
    if (key == QStringLiteral("display.colorRange")) {
        const QString range = newValue.toString().toLower();
        const QString code = range == QStringLiteral("limited") ? QStringLiteral("1")
                           : range == QStringLiteral("full") ? QStringLiteral("2")
                           : QStringLiteral("0");
        return writeBootConfigValue(QStringLiteral("hdmi_pixel_encoding"), code, message);
    }
    if (key == QStringLiteral("display.resolution")) {
        const QString resolution = newValue.toString().toLower();
        if (resolution == QStringLiteral("1920x1080")) {
            if (!writeBootConfigValue(QStringLiteral("hdmi_group"), QStringLiteral("2"), message)) return false;
            return writeBootConfigValue(QStringLiteral("hdmi_mode"), QStringLiteral("82"), message);
        }
        if (resolution == QStringLiteral("3840x2160")) {
            if (!writeBootConfigValue(QStringLiteral("hdmi_group"), QStringLiteral("1"), message)) return false;
            return writeBootConfigValue(QStringLiteral("hdmi_mode"), QStringLiteral("97"), message);
        }
        if (message) *message = QStringLiteral("Automatic or custom resolution preference saved.");
        return true;
    }

#endif

    if (key == QStringLiteral("localization.timezone")) {
        QString output;
        return runCommandBlocking(QStringLiteral("timedatectl"), {QStringLiteral("set-timezone"), newValue.toString()}, 8000, &output, message);
    }
    if (key == QStringLiteral("localization.locale")) {
        QString output;
        return runCommandBlocking(QStringLiteral("localectl"), {QStringLiteral("set-locale"), newValue.toString()}, 10000, &output, message);
    }
    if (key == QStringLiteral("localization.keyboard")) {
        QString output;
        return runCommandBlocking(QStringLiteral("localectl"), {QStringLiteral("set-keymap"), newValue.toString()}, 10000, &output, message);
    }
    if (key == QStringLiteral("audio.volume")) {
        const int volume = qBound(0, newValue.toInt(), 100);
        QString output;
        if (!executable(QStringLiteral("wpctl")).isEmpty())
            return runCommandBlocking(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QString::number(volume) + QStringLiteral("%")}, 5000, &output, message);
        return runCommandBlocking(QStringLiteral("amixer"), {QStringLiteral("sset"), QStringLiteral("Master"), QString::number(volume) + QStringLiteral("%")}, 5000, &output, message);
    }
    if (key == QStringLiteral("audio.muted")) {
        QString output;
        if (!executable(QStringLiteral("wpctl")).isEmpty())
            return runCommandBlocking(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), newValue.toBool() ? QStringLiteral("1") : QStringLiteral("0")}, 5000, &output, message);
        return runCommandBlocking(QStringLiteral("amixer"), {QStringLiteral("sset"), QStringLiteral("Master"), newValue.toBool() ? QStringLiteral("mute") : QStringLiteral("unmute")}, 5000, &output, message);
    }
    if (key == QStringLiteral("audio.output")) {
        const QString outputMode = newValue.toString().toLower();
#if !defined(NEUTRONOS_PLATFORM_GEMINI)
        if (!executable(QStringLiteral("raspi-config")).isEmpty() &&
            (outputMode == QStringLiteral("hdmi") || outputMode == QStringLiteral("analog") || outputMode == QStringLiteral("automatic"))) {
            const QString code = outputMode == QStringLiteral("hdmi") ? QStringLiteral("2")
                               : outputMode == QStringLiteral("analog") ? QStringLiteral("1")
                               : QStringLiteral("0");
            QString output;
            return runCommandBlocking(QStringLiteral("raspi-config"), {QStringLiteral("nonint"), QStringLiteral("do_audio"), code}, 8000, &output, message);
        }
#endif
        if (message) *message = QStringLiteral("Audio output preference saved. Select USB/Bluetooth devices through their device manager.");
        return true;
    }
    if (key == QStringLiteral("appearance.screensaverMinutes")) {
        if (!m_screensaverManager) {
            if (message) *message = QStringLiteral("Screensaver backend unavailable.");
            return false;
        }
        return m_screensaverManager->applyTimeoutMinutes(newValue.toInt());
    }
    if (key == QStringLiteral("network.wifiEnabled")) {
        if (!m_networkManager) {
            if (message) *message = QStringLiteral("Network backend unavailable.");
            return false;
        }
        return m_networkManager->setWifiEnabled(newValue.toBool());
    }
    if (key == QStringLiteral("performance.mode")) {
        if (!m_powerModeManager) {
            if (message) *message = QStringLiteral("Power mode backend unavailable.");
            return false;
        }
        const QString mode = newValue.toString().toLower();
        const QVariantMap result = mode == QStringLiteral("performance")
            ? m_powerModeManager->setPerformanceMode(true)
            : m_powerModeManager->setNormalMode();
        if (message) *message = result.value(QStringLiteral("message")).toString();
        return result.value(QStringLiteral("ok")).toBool();
    }
    if (key == QStringLiteral("performance.governor") ||
        key == QStringLiteral("performance.maxFrequency")) {
        const QDir policies(QStringLiteral("/sys/devices/system/cpu/cpufreq"));
        const QStringList entries = policies.entryList({QStringLiteral("policy*")}, QDir::Dirs | QDir::NoDotAndDotDot);
        if (entries.isEmpty()) {
            if (message) *message = QStringLiteral("CPU frequency policy files are unavailable.");
            return false;
        }
#if defined(NEUTRONOS_PLATFORM_GEMINI)
        const bool setGovernor = key.endsWith(QStringLiteral("governor"));
        const QString governor = newValue.toString().trimmed();
        bool numberOk = false;
        const quint64 requestedMhz = newValue.toULongLong(&numberOk);
        if (!setGovernor && (!numberOk || !requestedMhz || requestedMhz > 100000ULL)) {
            if (message) *message = QStringLiteral("A supported CPU frequency in MHz is required.");
            return false;
        }
        const quint64 requestedKhz = requestedMhz * 1000ULL;
        // Validate every policy before changing any of them.
        for (const QString &entry : entries) {
            const QDir policy(policies.absoluteFilePath(entry));
            if (setGovernor) {
                const QStringList supported = GeminiHardware::readText(policy.filePath(QStringLiteral("scaling_available_governors")))
                    .split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
                if (!supported.contains(governor)) {
                    if (message) *message = QStringLiteral("The selected governor is unavailable for %1.").arg(entry);
                    return false;
                }
            } else {
                const quint64 minimum = GeminiHardware::frequencyKhz(policy.path(), QStringLiteral("cpuinfo_min_freq"));
                const quint64 maximum = GeminiHardware::frequencyKhz(policy.path(), QStringLiteral("cpuinfo_max_freq"));
                const quint64 activeMinimum = GeminiHardware::frequencyKhz(policy.path(), QStringLiteral("scaling_min_freq"));
                if (!minimum || !maximum || requestedKhz < qMax(minimum, activeMinimum) || requestedKhz > maximum) {
                    if (message) *message = QStringLiteral("Frequency is outside the supported bounds for %1.").arg(entry);
                    return false;
                }
            }
        }
        const QByteArray value = setGovernor ? governor.toUtf8() : QByteArray::number(requestedKhz);
        const QString fileName = setGovernor ? QStringLiteral("scaling_governor") : QStringLiteral("scaling_max_freq");
        for (const QString &entry : entries) {
            QFile file(policies.absoluteFilePath(entry + QLatin1Char('/') + fileName));
            if (!file.open(QIODevice::WriteOnly) || file.write(value) != value.size()) {
                if (message) *message = file.errorString();
                return false;
            }
        }
#else
        const QByteArray value = key.endsWith(QStringLiteral("governor"))
            ? newValue.toString().trimmed().toUtf8()
            : QByteArray::number(qBound(600, newValue.toInt(), 2400) * 1000);
        const QString fileName = key.endsWith(QStringLiteral("governor"))
            ? QStringLiteral("scaling_governor") : QStringLiteral("scaling_max_freq");
        for (const QString &entry : entries) {
            QFile file(policies.absoluteFilePath(entry + QLatin1Char('/') + fileName));
            if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                if (message) *message = file.errorString();
                return false;
            }
            if (file.write(value) != value.size()) {
                if (message) *message = file.errorString();
                return false;
            }
        }
#endif
        if (message) *message = QStringLiteral("CPU policy applied.");
        return true;
    }

    // Preferences that are consumed by QML or companion services are persisted now.
    if (message)
        *message = QStringLiteral("Preference saved.");
    return true;
}

bool SettingsManager::startOperation(const QString &action,
                                     const QString &program,
                                     const QStringList &arguments,
                                     const QString &statusText)
{
    if (m_busy)
        return false;
    const QString path = program.contains(QLatin1Char('/')) ? program : executable(program);
    if (path.isEmpty()) {
        m_lastMessage = QStringLiteral("Required command is not installed: ") + program;
        emit operationChanged();
        return false;
    }
    m_busy = true;
    m_operationName = action;
    m_operationStatus = statusText;
    m_pendingOperationAction = action;
    m_operationProcess.setProgram(path);
    m_operationProcess.setArguments(arguments);
    m_operationProcess.start();
    emit operationChanged();
    return true;
}

void SettingsManager::handleOperationFinished(int exitCode, QProcess::ExitStatus status)
{
    const QString output = QString::fromUtf8(m_operationProcess.readAllStandardOutput()).trimmed();
    const QString error = QString::fromUtf8(m_operationProcess.readAllStandardError()).trimmed();
    const bool ok = status == QProcess::NormalExit && exitCode == 0;
    m_lastMessage = ok ? (output.isEmpty() ? QStringLiteral("Operation completed.") : output)
                       : (error.isEmpty() ? QStringLiteral("Operation failed.") : error);
    const QString action = m_pendingOperationAction;
    m_busy = false;
    m_operationName.clear();
    m_operationStatus.clear();
    m_pendingOperationAction.clear();
    emit operationChanged();
    emit operationFinished(action, ok, m_lastMessage);
    refresh();
}

bool SettingsManager::runAction(const QString &action, const QVariantMap &payload)
{
    const QString key = action.trimmed().toLower();
    if (m_values.value(QStringLiteral("user.autoLogin"), false).toBool() &&
            highPrioritySettingsAction(key) && !settingsHighPriorityAuthorizationValid()) {
        m_lastMessage = QStringLiteral(
            "Login password authorization is required while Automatic Login is enabled.");
        emit operationChanged();
        return false;
    }
    if (key == QStringLiteral("refresh")) { refresh(); return true; }
    if (key == QStringLiteral("scan-storage")) { scanStorageUsage(); return true; }
    if (key == QStringLiteral("restart-shell"))
        return startOperation(key, QStringLiteral("sudo"),
                              {QStringLiteral("-n"),
                               QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                               QStringLiteral("power-action"),
                               QStringLiteral("restart")},
                              QStringLiteral("Restarting NeutronOS shell…"));
    if (key == QStringLiteral("reboot"))
        return startOperation(key, QStringLiteral("sudo"),
                              {QStringLiteral("-n"),
                               QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                               QStringLiteral("power-action"),
                               QStringLiteral("reboot")},
                              QStringLiteral("Rebooting the Pi…"));
    if (key == QStringLiteral("shutdown"))
        return startOperation(key, QStringLiteral("sudo"),
                              {QStringLiteral("-n"),
                               QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                               QStringLiteral("power-action"),
                               QStringLiteral("shutdown")},
                              QStringLiteral("Powering off the Pi…"));
    if (key == QStringLiteral("check-updates"))
        return startOperation(key, QStringLiteral("apt-get"), {QStringLiteral("update")}, QStringLiteral("Checking package sources…"));
    if (key == QStringLiteral("install-updates")) {
        if (!developerModeEnabled()) {
            m_lastMessage = QStringLiteral("Developer Mode is required to install system updates.");
            emit operationChanged();
            return false;
        }
        return startOperation(key, QStringLiteral("apt-get"), {QStringLiteral("-y"), QStringLiteral("upgrade")}, QStringLiteral("Installing system updates…"));
    }
    if (key == QStringLiteral("expand-filesystem")) {
        if (!developerModeEnabled()) {
            m_lastMessage = QStringLiteral("Developer Mode is required.");
            emit operationChanged();
            return false;
        }
#if defined(NEUTRONOS_PLATFORM_GEMINI)
        m_lastMessage = QStringLiteral("Filesystem expansion is managed by Gemini storage provisioning. Use the Storage Utility for manual changes.");
#else
        const QString raspiConfig = executable(QStringLiteral("raspi-config"));
        if (!raspiConfig.isEmpty())
            return startOperation(key, raspiConfig, {QStringLiteral("--expand-rootfs")}, QStringLiteral("Expanding root filesystem…"));
        m_lastMessage = QStringLiteral("raspi-config is not installed. Use the Storage Utility or terminal.");
#endif
        emit operationChanged();
        return false;
    }
    if (key == QStringLiteral("clear-cache")) {
        QDir cache(m_neutronRoot + QStringLiteral("/state/cache"));
        const bool ok = !cache.exists() || cache.removeRecursively();
        m_lastMessage = ok ? QStringLiteral("NeutronOS cache cleared.") : QStringLiteral("Could not clear the cache.");
        emit operationChanged();
        return ok;
    }
    if (key == QStringLiteral("network-repair")) {
        if (m_networkManager)
            return m_networkManager->repairConnection();
        return false;
    }
    if (key == QStringLiteral("network-speed-test")) {
        if (m_networkManager)
            return m_networkManager->runSpeedTest();
        return false;
    }
    if (key == QStringLiteral("controller-off")) {
        if (m_controllerManager) {
            m_controllerManager->powerOffController();
            return true;
        }
        return false;
    }
    if (key == QStringLiteral("diagnostics")) {
        const QString script = m_neutronRoot + QStringLiteral("/scripts/neutronos-health-check.sh");
        return startOperation(key, script, QStringList(), QStringLiteral("Running NeutronOS diagnostics…"));
    }
    if (key == QStringLiteral("validate-boot")) {
        if (!developerModeEnabled()) {
            m_lastMessage = QStringLiteral("Developer Mode is required.");
            emit operationChanged();
            return false;
        }
#if defined(NEUTRONOS_PLATFORM_GEMINI)
        m_lastMessage = QStringLiteral("Pi config.txt validation is unavailable on Gemini. UEFI boot uses Debian GRUB and initramfs.");
        emit operationChanged();
        emit operationFinished(key, false, m_lastMessage);
        return false;
#else
        const QString config = bootConfigText();
        if (config.isEmpty()) {
            m_lastMessage = QStringLiteral("No Raspberry Pi boot configuration was found.");
            emit operationChanged();
            return false;
        }
        QStringList errors;
        const QStringList lines = config.split(QLatin1Char('\n'));
        for (int index = 0; index < lines.size(); ++index) {
            const QString line = lines.at(index).trimmed();
            if (line.isEmpty() || line.startsWith(QLatin1Char('#')) ||
                (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']'))))
                continue;
            if (!line.contains(QLatin1Char('=')) && !line.startsWith(QStringLiteral("include ")))
                errors.append(QStringLiteral("Line %1 has no key/value separator.").arg(index + 1));
        }
        m_lastMessage = errors.isEmpty()
            ? QStringLiteral("Boot configuration syntax is valid.")
            : QStringLiteral("Boot configuration errors: ") + errors.join(QStringLiteral(" "));
        emit operationChanged();
        emit operationFinished(key, errors.isEmpty(), m_lastMessage);
        return errors.isEmpty();
#endif
    }
    if (key == QStringLiteral("safe-mode")) {
        if (!developerModeEnabled()) {
            m_lastMessage = QStringLiteral("Developer Mode is required.");
            emit operationChanged();
            return false;
        }
        QJsonObject object;
        object.insert(QStringLiteral("enabled"), true);
        object.insert(QStringLiteral("requestedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
        object.insert(QStringLiteral("reason"), QStringLiteral("Settings Control Centre"));
        QString message;
        const bool ok = writeTextFileAtomically(settingsDirectory() + QStringLiteral("/safe-mode.json"),
                                                QJsonDocument(object).toJson(QJsonDocument::Indented),
                                                &message);
        m_lastMessage = ok ? QStringLiteral("Safe Mode is prepared for the next NeutronOS start.") : message;
        emit operationChanged();
        emit operationFinished(key, ok, m_lastMessage);
        return ok;
    }
    if (key == QStringLiteral("controller-pair")) {
        if (!serviceActive({QStringLiteral("bluetooth.service")})) {
            m_lastMessage = QStringLiteral("Bluetooth is not active.");
            emit operationChanged();
            return false;
        }
        return startOperation(key, QStringLiteral("bluetoothctl"),
                              {QStringLiteral("--timeout"), QStringLiteral("20"), QStringLiteral("scan"), QStringLiteral("on")},
                              QStringLiteral("Scanning for Bluetooth controllers…"));
    }
    if (key == QStringLiteral("clear-history")) {
        QStringList paths{
            QStringLiteral("/var/lib/neutronos/terminal/history.json"),
            QStringLiteral("/var/lib/neutronos/terminal/history.txt"),
            settingsDirectory() + QStringLiteral("/recent-activity.json")
        };
        bool ok = true;
        for (const QString &path : paths) {
            if (QFileInfo::exists(path) && !QFile::remove(path))
                ok = false;
        }
        m_lastMessage = ok ? QStringLiteral("Approved local activity history was cleared.")
                           : QStringLiteral("Some local history files could not be cleared.");
        emit operationChanged();
        emit operationFinished(key, ok, m_lastMessage);
        return ok;
    }
    if (key == QStringLiteral("set-proxy")) {
        m_values.insert(QStringLiteral("network.proxy"), payload);
        saveSettings();
        emit valuesChanged();
        return true;
    }
    m_lastMessage = QStringLiteral("Unsupported settings action: ") + action;
    emit operationChanged();
    return false;
}

QString SettingsManager::activeUsername() const
{
    if (m_userManager && !m_userManager->username().trimmed().isEmpty())
        return m_userManager->username().trimmed();
    return QStringLiteral("neutronos");
}

bool SettingsManager::changePassword(const QString &newPassword)
{
    if (newPassword.size() < 8) {
        m_lastMessage = QStringLiteral("Password must contain at least 8 characters.");
        emit operationChanged();
        return false;
    }
    QProcess process;
    process.start(executable(QStringLiteral("chpasswd")), QStringList());
    if (!process.waitForStarted(2500)) {
        m_lastMessage = QStringLiteral("Could not start password service.");
        emit operationChanged();
        return false;
    }
    process.write((activeUsername() + QLatin1Char(':') + newPassword + QLatin1Char('\n')).toUtf8());
    process.closeWriteChannel();
    if (!process.waitForFinished(10000) || process.exitCode() != 0) {
        m_lastMessage = QString::fromUtf8(process.readAllStandardError()).trimmed();
        if (m_lastMessage.isEmpty())
            m_lastMessage = QStringLiteral("Password change failed.");
        emit operationChanged();
        return false;
    }
    m_lastMessage = QStringLiteral("Password changed successfully.");
    emit operationChanged();
    return true;
}

bool SettingsManager::createUser(const QString &username,
                                 const QString &displayName,
                                 const QString &password,
                                 bool administrator)
{
    const QString clean = username.trimmed();
    if (!validUsername(clean) || password.size() < 8) {
        m_lastMessage = QStringLiteral("Use a valid lowercase username and an 8-character password.");
        emit operationChanged();
        return false;
    }
    QString output;
    QString message;
    QStringList arguments{QStringLiteral("-m"), QStringLiteral("-s"), QStringLiteral("/bin/bash")};
    if (!displayName.trimmed().isEmpty())
        arguments << QStringLiteral("-c") << displayName.trimmed();
    arguments << clean;
    if (!runCommandBlocking(QStringLiteral("useradd"), arguments, 15000, &output, &message)) {
        m_lastMessage = message;
        emit operationChanged();
        return false;
    }
    QProcess pass;
    pass.start(executable(QStringLiteral("chpasswd")), QStringList());
    if (pass.waitForStarted(2500)) {
        pass.write((clean + QLatin1Char(':') + password + QLatin1Char('\n')).toUtf8());
        pass.closeWriteChannel();
        pass.waitForFinished(10000);
    }
    if (administrator)
        runCommandBlocking(QStringLiteral("usermod"), {QStringLiteral("-aG"), QStringLiteral("sudo"), clean}, 8000, &output, &message);
    if (m_userManager)
        m_userManager->refreshUsers();
    m_lastMessage = QStringLiteral("User account created.");
    emit operationChanged();
    return true;
}

bool SettingsManager::removeUser(const QString &username)
{
    const QString clean = username.trimmed();
    if (!validUsername(clean) || clean == activeUsername() || clean == QStringLiteral("root")) {
        m_lastMessage = QStringLiteral("The active user and root account cannot be removed.");
        emit operationChanged();
        return false;
    }
    QString output;
    QString message;
    const bool ok = runCommandBlocking(QStringLiteral("userdel"), {QStringLiteral("-r"), clean}, 20000, &output, &message);
    m_lastMessage = ok ? QStringLiteral("User account removed.") : message;
    emit operationChanged();
    if (ok && m_userManager)
        m_userManager->refreshUsers();
    return ok;
}

bool SettingsManager::connectWifi(const QString &ssid,
                                  const QString &password,
                                  const QString &country)
{
    if (ssid.trimmed().isEmpty()) {
        m_lastMessage = QStringLiteral("Enter a Wi-Fi network name.");
        emit operationChanged();
        return false;
    }
    if (!country.trimmed().isEmpty()) {
        QString output;
        QString message;
        runCommandBlocking(QStringLiteral("iw"), {QStringLiteral("reg"), QStringLiteral("set"), country.trimmed().toUpper()}, 5000, &output, &message);
    }
    if (m_networkManager) {
        QVariantMap payload;
        payload.insert(QStringLiteral("ssid"), ssid.trimmed());
        payload.insert(QStringLiteral("password"), password);
        const bool ok = m_networkManager->connectToNetwork(payload);
        m_lastMessage = ok ? QStringLiteral("Wi-Fi connection requested.")
                           : QStringLiteral("Wi-Fi connection request failed.");
        emit operationChanged();
        return ok;
    }
    QString output;
    QString message;
    QStringList arguments{QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("connect"), ssid.trimmed()};
    if (!password.isEmpty())
        arguments << QStringLiteral("password") << password;
    const bool ok = runCommandBlocking(QStringLiteral("nmcli"), arguments, 30000, &output, &message);
    m_lastMessage = ok ? output : message;
    emit operationChanged();
    return ok;
}

QVariantMap SettingsManager::buildIntegrityReport() const
{
    QVariantList checks;
    QStringList errors;
    auto appendCheck = [&checks, &errors](const QString &name,
                                          bool ok,
                                          const QString &detail) {
        QVariantMap check;
        check.insert(QStringLiteral("name"), name);
        check.insert(QStringLiteral("ok"), ok);
        check.insert(QStringLiteral("status"), ok ? QStringLiteral("OK") : QStringLiteral("ERROR"));
        check.insert(QStringLiteral("detail"), detail);
        checks.append(check);
        if (!ok)
            errors.append(name + QStringLiteral(": ") + detail);
    };

    bool cpuOk = QFileInfo::exists(QStringLiteral("/proc/stat"));
    QString cpuDetail = cpuOk ? QStringLiteral("CPU telemetry is readable.")
                              : QStringLiteral("/proc/stat is unavailable.");
#if !defined(NEUTRONOS_PLATFORM_GEMINI)
    const QString vcgencmd = executable(QStringLiteral("vcgencmd"));
    if (!vcgencmd.isEmpty()) {
        QString output;
        QString message;
        if (runCommandBlocking(vcgencmd, {QStringLiteral("get_throttled")}, 2500, &output, &message)) {
            const QString value = output.section(QLatin1Char('='), 1).trimmed();
            bool converted = false;
            const quint32 flags = value.toUInt(&converted, 16);
            if (converted && (flags & 0x0000FFFFU) != 0U) {
                cpuOk = false;
                cpuDetail = QStringLiteral("Active Raspberry Pi throttling flags: 0x") +
                            QString::number(flags, 16).toUpper();
            } else if (converted) {
                cpuDetail = QStringLiteral("CPU telemetry readable; no active throttling.");
            }
        }
    }
#endif
    appendCheck(QStringLiteral("CPU"), cpuOk, cpuDetail);

    const quint64 totalKiB = memInfoKiB(QStringLiteral("MemTotal"));
    const quint64 availableKiB = memInfoKiB(QStringLiteral("MemAvailable"));
    const bool ramOk = totalKiB > 0 && availableKiB >= 128ULL * 1024ULL;
    appendCheck(QStringLiteral("RAM"), ramOk,
                totalKiB == 0
                    ? QStringLiteral("/proc/meminfo could not be read.")
                    : QStringLiteral("%1 available of %2.")
                          .arg(humanBytes(availableKiB * 1024ULL),
                               humanBytes(totalKiB * 1024ULL)));

    QStorageInfo root(QStringLiteral("/"));
    const bool storageOk = root.isValid() && root.isReady() &&
                           root.bytesAvailable() >= 256ULL * 1024ULL * 1024ULL;
    appendCheck(QStringLiteral("Storage"), storageOk,
                root.isValid() && root.isReady()
                    ? QStringLiteral("%1 available on the boot filesystem.")
                          .arg(humanBytes(root.bytesAvailable()))
                    : QStringLiteral("The boot filesystem is not ready."));

    const bool inputOk = QFileInfo(QStringLiteral("/dev/input")).isDir();
    const bool bluetoothOk = !serviceInstalled({QStringLiteral("bluetooth.service")}) ||
                             serviceActive({QStringLiteral("bluetooth.service")});
    const bool peripheralOk = inputOk && bluetoothOk;
    appendCheck(QStringLiteral("Peripherals"), peripheralOk,
                !inputOk ? QStringLiteral("Linux input devices are unavailable.")
                         : !bluetoothOk ? QStringLiteral("Bluetooth is installed but inactive.")
                                        : QStringLiteral("Input and peripheral services are available."));

    const QFileInfo securityDirectory(QStringLiteral("/var/lib/neutronos/security"));
    const bool securityPermissionsOk = securityDirectory.exists() && securityDirectory.isDir() &&
        !(securityDirectory.permissions() & QFileDevice::WriteOther);
    const bool shellServiceOk = serviceActive({QStringLiteral("neutronos.service")});
    const bool securityOk = securityPermissionsOk && shellServiceOk;
    appendCheck(QStringLiteral("Security"), securityOk,
                !securityPermissionsOk
                    ? QStringLiteral("The NeutronOS security directory is missing or world-writable.")
                    : !shellServiceOk ? QStringLiteral("neutronos.service is not active or enabled.")
                                      : QStringLiteral("Security state permissions and shell service are valid."));

    const bool valid = errors.isEmpty();
    QVariantMap report;
    report.insert(QStringLiteral("valid"), valid);
    report.insert(QStringLiteral("title"), valid ? QStringLiteral("System Integrity Valid")
                                                  : QStringLiteral("System Integrity Errors Found"));
    report.insert(QStringLiteral("summary"), valid
                  ? QStringLiteral("Core NeutronOS telemetry, storage, peripherals and security checks passed.")
                  : errors.join(QStringLiteral("\n")));
    report.insert(QStringLiteral("checks"), checks);
    report.insert(QStringLiteral("errors"), errors);
    report.insert(QStringLiteral("checkedAt"), QDateTime::currentDateTime().toString(Qt::ISODate));
    return report;
}

void SettingsManager::runSystemIntegrityCheck()
{
    if (m_integrityCheckBusy)
        return;
    m_integrityCheckBusy = true;
    m_integrityReport.clear();
    m_lastMessage = QStringLiteral("Verifying NeutronOS system integrity…");
    emit integrityReportChanged();
    emit operationChanged();
    m_integrityWatcher.setFuture(QtConcurrent::run([this]() {
        return buildIntegrityReport();
    }));
}

void SettingsManager::handleIntegrityCheckFinished()
{
    m_integrityReport = m_integrityWatcher.result();
    m_integrityCheckBusy = false;
    m_lastMessage = m_integrityReport.value(QStringLiteral("title")).toString();
    emit integrityReportChanged();
    emit operationChanged();
}

void SettingsManager::scanStorageUsage()
{
    if (m_storageScanBusy || !m_storageManager)
        return;
    m_storageManager->refreshDevices();
    const QVariantList devices = m_storageManager->devices();
    m_cancelStorageScan.store(false);
    m_storageScanBusy = true;
    m_storageScanProgress = 1;
    m_lastMessage = QStringLiteral("Scanning storage usage in the background…");
    emit storageUsageChanged();
    emit operationChanged();
    m_storageWatcher.setFuture(QtConcurrent::run([devices, this]() {
        return buildStorageUsage(devices, &m_cancelStorageScan);
    }));
}

void SettingsManager::cancelStorageScan()
{
    m_cancelStorageScan.store(true);
    m_lastMessage = QStringLiteral("Storage scan cancellation requested.");
    emit operationChanged();
}

void SettingsManager::handleStorageScanFinished()
{
    m_storageUsage = m_storageWatcher.result();
    m_storageScanBusy = false;
    m_storageScanProgress = 100;
    m_lastMessage = m_cancelStorageScan.load()
        ? QStringLiteral("Storage scan stopped. Partial results are shown.")
        : QStringLiteral("Storage usage scan complete.");
    saveStorageCache();
    emit storageUsageChanged();
    emit operationChanged();
}

QVariantList SettingsManager::buildStorageUsage(const QVariantList &devices, std::atomic_bool *cancelFlag)
{
    QVariantList flat;
    flattenDevices(devices, &flat);

    QMap<QString, QVariantMap> candidates;
    for (const QVariant &entry : flat) {
        const QVariantMap device = entry.toMap();
        const QStringList mounts = variantStringList(device.value(QStringLiteral("mountPoints")));
        for (const QString &rawMount : mounts) {
            const QString mount = QDir::cleanPath(rawMount.trimmed());
            if (mount.isEmpty() || !QFileInfo(mount).isDir())
                continue;
            QVariantMap merged = candidates.value(mount);
            for (auto it = device.cbegin(); it != device.cend(); ++it) {
                if (!it.value().toString().trimmed().isEmpty() || !merged.contains(it.key()))
                    merged.insert(it.key(), it.value());
            }
            merged.insert(QStringLiteral("mount"), mount);
            candidates.insert(mount, merged);
        }
    }

    for (const QStorageInfo &storage : QStorageInfo::mountedVolumes()) {
        if (!storage.isValid() || !storage.isReady())
            continue;
        const QString mount = QDir::cleanPath(storage.rootPath());
        if (mount.isEmpty() || mount.startsWith(QStringLiteral("/proc")) ||
            mount.startsWith(QStringLiteral("/sys")) || mount.startsWith(QStringLiteral("/dev")) ||
            mount.startsWith(QStringLiteral("/run")))
            continue;
        QVariantMap merged = candidates.value(mount);
        merged.insert(QStringLiteral("mount"), mount);
        if (merged.value(QStringLiteral("path")).toString().trimmed().isEmpty())
            merged.insert(QStringLiteral("path"), QString::fromUtf8(storage.device()));
        if (merged.value(QStringLiteral("label")).toString().trimmed().isEmpty())
            merged.insert(QStringLiteral("label"), storage.displayName());
        if (merged.value(QStringLiteral("filesystem")).toString().trimmed().isEmpty())
            merged.insert(QStringLiteral("filesystem"), QString::fromUtf8(storage.fileSystemType()));
        if (!merged.contains(QStringLiteral("system")))
            merged.insert(QStringLiteral("system"), mount == QStringLiteral("/"));
        candidates.insert(mount, merged);
    }

    QVariantList result;
    for (auto candidate = candidates.cbegin(); candidate != candidates.cend(); ++candidate) {
        if (cancelFlag && cancelFlag->load())
            break;

        const QString mount = candidate.key();
        const QVariantMap device = candidate.value();
        if (!QFileInfo(mount).isDir())
            continue;

        QStorageInfo storage(mount);
        if (!storage.isValid() || !storage.isReady())
            continue;

        QMap<QString, quint64> categoryBytes;
        quint64 scannedBytes = 0;
        quint64 fileCount = 0;
        bool complete = true;
        QElapsedTimer timer;
        timer.start();

        QStringList scanRoots;
        if (mount == QStringLiteral("/")) {
            scanRoots << QStringLiteral("/home") << QStringLiteral("/usr")
                      << QStringLiteral("/var") << QStringLiteral("/opt")
                      << QStringLiteral("/boot") << QStringLiteral("/etc");
        } else {
            scanRoots << mount;
        }

        for (const QString &scanRoot : scanRoots) {
            if (!QFileInfo(scanRoot).isDir())
                continue;
            QDirIterator iterator(scanRoot,
                                  QDir::Files | QDir::NoSymLinks | QDir::Hidden,
                                  QDirIterator::Subdirectories);
            while (iterator.hasNext()) {
                if (cancelFlag && cancelFlag->load()) {
                    complete = false;
                    break;
                }
                iterator.next();
                const QFileInfo info = iterator.fileInfo();
                if (!info.isFile())
                    continue;
                const QString absolute = info.absoluteFilePath();
                if (absolute.startsWith(QStringLiteral("/var/lib/neutronos/security/")) ||
                    absolute.startsWith(QStringLiteral("/var/cache/apt/archives/partial/")))
                    continue;
                const quint64 size = quint64(std::max<qint64>(0, info.size()));
                categoryBytes[categoryForFile(absolute, info, mount)] += size;
                scannedBytes += size;
                ++fileCount;
                if (fileCount >= 500000 || timer.elapsed() > 60000) {
                    complete = false;
                    break;
                }
            }
            if (!complete)
                break;
        }

        const quint64 total = storage.bytesTotal();
        const quint64 free = storage.bytesAvailable();
        const quint64 used = total > free ? total - free : scannedBytes;
        if (used > scannedBytes)
            categoryBytes[QStringLiteral("Other")] += used - scannedBytes;

        QString name = mapString(device, QStringLiteral("label"));
        const QString model = mapString(device, QStringLiteral("model"));
        const QString vendor = mapString(device, QStringLiteral("vendor"));
        if (name.isEmpty() && !model.isEmpty())
            name = model;
        if (name.isEmpty() && !storage.displayName().trimmed().isEmpty())
            name = storage.displayName().trimmed();
        if (name.isEmpty() && mount == QStringLiteral("/"))
            name = QStringLiteral("Boot");
        if (name.isEmpty())
            name = QFileInfo(mount).fileName();
        if (name.isEmpty())
            name = QFileInfo(device.value(QStringLiteral("path")).toString()).fileName();
        if (name.isEmpty())
            name = QStringLiteral("Storage Device");
        if (!vendor.isEmpty() && !name.contains(vendor, Qt::CaseInsensitive))
            name = vendor + QLatin1Char(' ') + name;

        QString filesystem = mapString(device, QStringLiteral("filesystem"));
        if (filesystem.isEmpty())
            filesystem = QString::fromUtf8(storage.fileSystemType()).trimmed();
        if (filesystem.isEmpty())
            filesystem = QStringLiteral("Unknown");

        QVariantMap item;
        item.insert(QStringLiteral("path"), mapString(device, QStringLiteral("path"), QString::fromUtf8(storage.device())));
        item.insert(QStringLiteral("name"), name.simplified());
        item.insert(QStringLiteral("model"), model);
        item.insert(QStringLiteral("vendor"), vendor);
        item.insert(QStringLiteral("serial"), device.value(QStringLiteral("serial")));
        item.insert(QStringLiteral("transport"), device.value(QStringLiteral("transport")));
        item.insert(QStringLiteral("mount"), mount);
        item.insert(QStringLiteral("filesystem"), filesystem);
        item.insert(QStringLiteral("totalBytes"), QVariant::fromValue(total));
        item.insert(QStringLiteral("usedBytes"), QVariant::fromValue(used));
        item.insert(QStringLiteral("freeBytes"), QVariant::fromValue(free));
        item.insert(QStringLiteral("total"), humanBytes(total));
        item.insert(QStringLiteral("used"), humanBytes(used));
        item.insert(QStringLiteral("free"), humanBytes(free));
        item.insert(QStringLiteral("usedPercent"), total > 0 ? qRound((double(used) / double(total)) * 100.0) : 0);
        item.insert(QStringLiteral("categories"), categoryListFromMap(categoryBytes, used));
        item.insert(QStringLiteral("fileCount"), QVariant::fromValue(fileCount));
        item.insert(QStringLiteral("scanComplete"), complete);
        item.insert(QStringLiteral("system"), mapBool(device, QStringLiteral("system"), mount == QStringLiteral("/")));
        item.insert(QStringLiteral("removable"), mapBool(device, QStringLiteral("removable")));
        item.insert(QStringLiteral("status"), complete ? QStringLiteral("Analyzed") : QStringLiteral("Partial analysis"));
        result.append(item);
    }

    std::sort(result.begin(), result.end(), [](const QVariant &left, const QVariant &right) {
        const QVariantMap a = left.toMap();
        const QVariantMap b = right.toMap();
        if (a.value(QStringLiteral("system")).toBool() != b.value(QStringLiteral("system")).toBool())
            return a.value(QStringLiteral("system")).toBool();
        return a.value(QStringLiteral("name")).toString().localeAwareCompare(
                   b.value(QStringLiteral("name")).toString()) < 0;
    });
    return result;
}
