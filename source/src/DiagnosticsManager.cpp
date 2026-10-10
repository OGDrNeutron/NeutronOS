#include "DiagnosticsManager.h"

#if defined(NEUTRONOS_PLATFORM_GEMINI)
#include "../platform/gemini/GeminiHardware.h"
#endif

#include <QtConcurrent>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>
#include <QAbstractSocket>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSysInfo>
#include <QThread>
#include <QUuid>

namespace {
QVariantMap check(const QString &id, const QString &title, const QString &status,
                  const QString &value, const QString &detail,
                  const QString &evidence = QString(), const QString &suggestedAction = QString())
{
    return {{QStringLiteral("id"), id}, {QStringLiteral("title"), title},
            {QStringLiteral("status"), status}, {QStringLiteral("value"), value},
            {QStringLiteral("detail"), detail},
            {QStringLiteral("evidence"), evidence.isEmpty() ? detail : evidence},
            {QStringLiteral("suggestedAction"), suggestedAction},
            {QStringLiteral("hasSuggestedAction"), !suggestedAction.isEmpty()}};
}

QString prettyBytes(qulonglong bytes)
{
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < 4) { value /= 1024.0; ++unit; }
    return QString::number(value, 'f', unit == 0 ? 0 : 1) + QLatin1Char(' ') + QString::fromLatin1(units[unit]);
}
}

DiagnosticsManager::DiagnosticsManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent), m_neutronRoot(QDir(neutronRoot).absolutePath())
{
    connect(&m_diagnosticsWatcher, &QFutureWatcher<QVariantMap>::finished, this, [this]() {
        const QVariantMap result = m_diagnosticsWatcher.result();
        m_checks = result.value(QStringLiteral("checks")).toList();
        m_passedCount = result.value(QStringLiteral("passed")).toInt();
        m_warningCount = result.value(QStringLiteral("warnings")).toInt();
        m_failedCount = result.value(QStringLiteral("failed")).toInt();
        m_systemSummary = result.value(QStringLiteral("summary")).toString();
        m_lastRun = QDateTime::currentDateTime().toString(QStringLiteral("MMM d, yyyy • h:mm AP"));
        emit diagnosticsChanged();
        setProgress(100);
        setStage(QStringLiteral("Complete"));
        setLastMessage(QStringLiteral("Diagnostics complete: %1 passed, %2 warnings, %3 failed.")
                       .arg(m_passedCount).arg(m_warningCount).arg(m_failedCount));
        setBusy(false);
    });

    connect(&m_bundleWatcher, &QFutureWatcher<QVariantMap>::finished, this, [this]() {
        const QVariantMap result = m_bundleWatcher.result();
        const bool ok = result.value(QStringLiteral("ok")).toBool();
        if (ok) {
            m_lastBundlePath = result.value(QStringLiteral("path")).toString();
            emit bundleChanged();
        }
        setProgress(ok ? 100 : 0);
        setStage(ok ? QStringLiteral("Bundle ready") : QStringLiteral("Bundle failed"));
        setLastMessage(result.value(QStringLiteral("message")).toString());
        setBusy(false);
    });
}

bool DiagnosticsManager::refresh() { return runFullDiagnostics(); }

bool DiagnosticsManager::rerunCheck(const QString &checkId)
{
    if (checkId.trimmed().isEmpty())
        return false;
    m_requestedCheckId = checkId.trimmed();
    return runFullDiagnostics();
}

bool DiagnosticsManager::runFullDiagnostics()
{
    if (m_busy) return false;
    setBusy(true); setProgress(8); setStage(QStringLiteral("Checking system"));
    setLastMessage(QStringLiteral("Running hardware, service, storage and network checks…"));
    m_diagnosticsWatcher.setFuture(QtConcurrent::run([this]() { return collectDiagnostics(); }));
    return true;
}

bool DiagnosticsManager::exportSupportBundle()
{
    if (m_busy) return false;
    setBusy(true); setProgress(10); setStage(QStringLiteral("Collecting support data"));
    setLastMessage(QStringLiteral("Creating a redacted NeutronOS support bundle…"));
    m_bundleWatcher.setFuture(QtConcurrent::run([this]() { return buildSupportBundle(); }));
    return true;
}

QString DiagnosticsManager::reportText() const
{
    QStringList lines;
    lines << QStringLiteral("NeutronOS Diagnostics") << m_systemSummary
          << QStringLiteral("Last run: %1").arg(m_lastRun) << QString();
    for (const QVariant &entry : m_checks) {
        const QVariantMap item = entry.toMap();
        lines << QStringLiteral("[%1] %2 — %3")
                     .arg(item.value(QStringLiteral("status")).toString().toUpper(),
                          item.value(QStringLiteral("title")).toString(),
                          item.value(QStringLiteral("value")).toString())
              << item.value(QStringLiteral("detail")).toString() << QString();
    }
    return lines.join(QLatin1Char('\n'));
}

QVariantMap DiagnosticsManager::collectDiagnostics() const
{
    QVariantList results;
    int passed = 0, warnings = 0, failed = 0;
    auto add = [&](const QVariantMap &item) {
        results.append(item);
        const QString status = item.value(QStringLiteral("status")).toString();
        if (status == QStringLiteral("pass")) ++passed;
        else if (status == QStringLiteral("fail")) ++failed;
        else ++warnings;
    };

#if defined(NEUTRONOS_PLATFORM_GEMINI)
    QString model = GeminiHardware::model();
    if (model.isEmpty()) model = QStringLiteral("x86_64 PC");
#else
    QString model = readText(QStringLiteral("/proc/device-tree/model")).remove(QChar('\0')).trimmed();
    if (model.isEmpty()) model = QSysInfo::prettyProductName();
#endif
    QString version = QStringLiteral("Unknown");
    QFile versionFile(QDir(m_neutronRoot).filePath(QStringLiteral("config/version.json")));
    if (versionFile.open(QIODevice::ReadOnly))
        version = QJsonDocument::fromJson(versionFile.readAll()).object().value(QStringLiteral("displayName")).toString(QStringLiteral("Unknown"));
    const QString summary = QStringLiteral("%1 • %2 • %3 cores • %4")
        .arg(model, QSysInfo::kernelVersion()).arg(QThread::idealThreadCount()).arg(version);

    const QString load = readText(QStringLiteral("/proc/loadavg")).section(QLatin1Char(' '), 0, 2);
    const int cores = qMax(1, QThread::idealThreadCount());
    bool loadOk = false;
    const double loadOne = load.section(QLatin1Char(' '), 0, 0).toDouble(&loadOk);
    const QString frequency = readText(QStringLiteral("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")).trimmed();
    add(check(QStringLiteral("cpu"), QStringLiteral("CPU"), !loadOk ? QStringLiteral("warn") :
              loadOne > cores * 2.0 ? QStringLiteral("fail") : loadOne > cores ? QStringLiteral("warn") : QStringLiteral("pass"),
              loadOk ? QStringLiteral("%1 cores • load %2").arg(cores).arg(load) : QStringLiteral("Unavailable"),
              QStringLiteral("Core availability, 1/5/15 minute load, and current frequency were sampled."),
              QStringLiteral("loadavg=%1; scaling_cur_freq=%2 kHz").arg(load, frequency.isEmpty() ? QStringLiteral("Unavailable") : frequency),
              loadOk && loadOne > cores ? QStringLiteral("Inspect System > Services and Logs for sustained CPU consumers.") : QString()));

    const QString memText = readText(QStringLiteral("/proc/meminfo"));
    auto memValue = [&memText](const QString &name) -> qulonglong {
        const auto match = QRegularExpression(QStringLiteral("^%1:\\s+(\\d+)").arg(name), QRegularExpression::MultilineOption).match(memText);
        return match.hasMatch() ? match.captured(1).toULongLong() : 0;
    };
    const qulonglong totalKb = memValue(QStringLiteral("MemTotal"));
    const qulonglong availableKb = memValue(QStringLiteral("MemAvailable"));
    const qulonglong swapKb = memValue(QStringLiteral("SwapTotal"));
    const int availablePercent = totalKb ? static_cast<int>((availableKb * 100) / totalKb) : 0;
    add(check(QStringLiteral("ram"), QStringLiteral("RAM"), !totalKb ? QStringLiteral("warn") :
              availablePercent < 5 ? QStringLiteral("fail") : availablePercent < 15 ? QStringLiteral("warn") : QStringLiteral("pass"),
              totalKb ? QStringLiteral("%1% available").arg(availablePercent) : QStringLiteral("Unavailable"),
              QStringLiteral("Physical memory pressure and swap/zram capacity."),
              totalKb ? QStringLiteral("%1 available / %2 total • %3 swap")
                  .arg(prettyBytes(availableKb * 1024), prettyBytes(totalKb * 1024), prettyBytes(swapKb * 1024)) : QStringLiteral("/proc/meminfo unavailable"),
              availablePercent < 15 ? QStringLiteral("Close unused apps or choose the Eco profile to reduce background work.") : QString()));

#if defined(NEUTRONOS_PLATFORM_GEMINI)
    const auto temperature = GeminiHardware::cpuTemperature();
    const QString thermalStatus = !temperature.available ? QStringLiteral("warn") :
        temperature.celsius >= temperature.critical ? QStringLiteral("fail") :
        temperature.celsius >= temperature.warning ? QStringLiteral("warn") : QStringLiteral("pass");
    add(check(QStringLiteral("temperature"), QStringLiteral("Temperature"), thermalStatus,
              temperature.available ? QStringLiteral("%1°C").arg(temperature.celsius, 0, 'f', 1) : QStringLiteral("Unavailable"),
              QStringLiteral("CPU temperature from Linux hwmon or a CPU-labelled thermal zone."),
              temperature.available ? QStringLiteral("source=%1; warning=%2°C; critical=%3°C; active throttle status unavailable")
                  .arg(temperature.source).arg(temperature.warning).arg(temperature.critical) : QStringLiteral("No supported CPU temperature sensor is readable."),
              thermalStatus == QStringLiteral("pass") ? QString() : QStringLiteral("Check CPU cooling and sensor-driver availability.")));
#else
    bool tempOk = false;
    const double tempC = readText(QStringLiteral("/sys/class/thermal/thermal_zone0/temp")).trimmed().toDouble(&tempOk) / 1000.0;
    QString throttled = commandOutput(QStringLiteral("vcgencmd"), {QStringLiteral("get_throttled")}, 2500).trimmed();
    if (throttled.isEmpty()) throttled = QStringLiteral("Unavailable");
    const bool throttleClear = throttled.endsWith(QStringLiteral("0x0"));
    const QString thermalStatus = !tempOk ? QStringLiteral("warn") : tempC >= 82.0 || (!throttleClear && throttled != QStringLiteral("Unavailable"))
        ? QStringLiteral("fail") : tempC >= 75.0 ? QStringLiteral("warn") : QStringLiteral("pass");
    add(check(QStringLiteral("temperature"), QStringLiteral("Temperature"), thermalStatus,
              tempOk ? QStringLiteral("%1°C").arg(tempC, 0, 'f', 1) : QStringLiteral("Unavailable"),
              QStringLiteral("Current CPU thermal state and firmware throttle history."),
              QStringLiteral("thresholds=75°C warning/82°C fail; throttle=%1").arg(throttled),
              thermalStatus == QStringLiteral("pass") ? QString() : QStringLiteral("Check ventilation and Raspberry Pi power delivery.")));

#endif

    QStorageInfo rootStorage(QStringLiteral("/")); rootStorage.refresh();
    const qulonglong available = rootStorage.bytesAvailable();
    const int freePercent = rootStorage.bytesTotal() ? static_cast<int>((available * 100) / rootStorage.bytesTotal()) : 0;
    const QString storageStatus = !rootStorage.isValid() || !rootStorage.isReady() || freePercent < 3 ? QStringLiteral("fail") :
                                  freePercent < 10 ? QStringLiteral("warn") : QStringLiteral("pass");
    const QString ioErrors = commandOutput(QStringLiteral("journalctl"), {QStringLiteral("-b"), QStringLiteral("-k"),
        QStringLiteral("-p"), QStringLiteral("err"), QStringLiteral("-n"), QStringLiteral("80"), QStringLiteral("--no-pager")}, 4500);
    add(check(QStringLiteral("storage"), QStringLiteral("Storage"), storageStatus,
              rootStorage.isValid() ? QStringLiteral("%1 free").arg(prettyBytes(available)) : QStringLiteral("Unavailable"),
              QStringLiteral("Root mount readiness, capacity, low-space state, and observable kernel I/O errors."),
              QStringLiteral("filesystem=%1; free=%2%; kernel-errors=%3")
                  .arg(QString::fromUtf8(rootStorage.fileSystemType())).arg(freePercent).arg(ioErrors.isEmpty() ? QStringLiteral("none observed") : ioErrors.left(600)),
              storageStatus == QStringLiteral("pass") ? QString() : QStringLiteral("Open Storage Manager and free space; inspect kernel logs before repair.")));

    const bool rootReadOnly = rootStorage.isReadOnly();
    const QString mountEvidence = commandOutput(QStringLiteral("findmnt"), {QStringLiteral("-no"), QStringLiteral("SOURCE,FSTYPE,OPTIONS"), QStringLiteral("/")}, 2500);
    add(check(QStringLiteral("filesystem"), QStringLiteral("Filesystem"), !rootStorage.isValid() ? QStringLiteral("fail") :
              rootReadOnly ? QStringLiteral("warn") : QStringLiteral("pass"),
              rootStorage.isValid() ? (rootReadOnly ? QStringLiteral("Read-only") : QStringLiteral("Mounted")) : QStringLiteral("Unavailable"),
              QStringLiteral("Read-only mount inspection only; no repair was attempted."), mountEvidence,
              rootReadOnly ? QStringLiteral("Review filesystem errors and schedule offline fsck if evidence supports it.") : QString()));

    bool networkActive = false; QStringList addresses;
    for (const QNetworkInterface &iface : QNetworkInterface::allInterfaces()) {
        if (!(iface.flags() & QNetworkInterface::IsUp) || !(iface.flags() & QNetworkInterface::IsRunning) || (iface.flags() & QNetworkInterface::IsLoopBack)) continue;
        for (const QNetworkAddressEntry &address : iface.addressEntries()) {
            if (address.ip().protocol() == QAbstractSocket::IPv4Protocol && !address.ip().isLoopback()) {
                networkActive = true; addresses << iface.humanReadableName() + QStringLiteral(": ") + address.ip().toString();
            }
        }
    }
    const QString routes = commandOutput(QStringLiteral("ip"), {QStringLiteral("route"), QStringLiteral("show")}, 2500);
    const QString resolv = readText(QStringLiteral("/etc/resolv.conf"));
    const bool dnsConfigured = resolv.contains(QRegularExpression(QStringLiteral("^\\s*nameserver\\s+"), QRegularExpression::MultilineOption));
    add(check(QStringLiteral("network"), QStringLiteral("Networking"), networkActive && dnsConfigured ? QStringLiteral("pass") :
              networkActive ? QStringLiteral("warn") : QStringLiteral("fail"),
              networkActive ? addresses.join(QStringLiteral(" • ")) : QStringLiteral("No active interface"),
              QStringLiteral("Authoritative interface state, gateway route, and resolver configuration; no network state was changed."),
              QStringLiteral("routes=%1\nresolver=%2").arg(routes.isEmpty() ? QStringLiteral("Unavailable") : routes, resolv.left(600)),
              !networkActive ? QStringLiteral("Open Network Center and inspect the physical link or saved connection.") :
              !dnsConfigured ? QStringLiteral("Check the configured DNS server in Network Center.") : QString()));

    const QString failedUnits = commandOutput(QStringLiteral("systemctl"),
        {QStringLiteral("--failed"), QStringLiteral("--type=service"),
         QStringLiteral("--no-legend"), QStringLiteral("--plain")}, 4000).trimmed();
    auto unitState = [](const QString &unit) {
        return DiagnosticsManager::commandOutput(QStringLiteral("systemctl"),
            {QStringLiteral("is-active"), unit}, 2500).section(QLatin1Char('\n'), 0, 0).trimmed();
    };
    const QString shellState = unitState(QStringLiteral("neutronos.service"));
    const QString securityState = unitState(QStringLiteral("neutron-securityd.service"));
    const QString networkManagerState = unitState(QStringLiteral("NetworkManager.service"));
    const QString bluetoothState = unitState(QStringLiteral("bluetooth.service"));
    QStringList actionableFailures;
    for (const QString &line : failedUnits.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QString unit = line.simplified().section(QLatin1Char(' '), 0, 0);
        // wait-online is allowed to time out when First Boot deliberately skips
        // networking. The actual NetworkManager daemon state below is decisive.
        if (unit == QStringLiteral("NetworkManager-wait-online.service") &&
                networkManagerState == QStringLiteral("active"))
            continue;
        actionableFailures.append(unit.isEmpty() ? line.simplified() : unit);
    }
    const bool criticalInactive = shellState != QStringLiteral("active") ||
                                  securityState != QStringLiteral("active") ||
                                  networkManagerState != QStringLiteral("active") ||
                                  bluetoothState != QStringLiteral("active");
    const QString serviceStatus = criticalInactive ? QStringLiteral("fail") :
                                  actionableFailures.isEmpty() ? QStringLiteral("pass") : QStringLiteral("warn");
    const QString serviceEvidence = QStringLiteral(
        "neutronos=%1; security=%2; NetworkManager=%3; bluetooth=%4; actionable-failed=%5")
        .arg(shellState, securityState, networkManagerState, bluetoothState,
             actionableFailures.isEmpty() ? QStringLiteral("none") : actionableFailures.join(QStringLiteral(", ")));
    add(check(QStringLiteral("services"), QStringLiteral("Services"), serviceStatus,
              serviceStatus == QStringLiteral("pass") ? QStringLiteral("Critical services active") :
              criticalInactive ? QStringLiteral("Critical service unavailable") : QStringLiteral("Failed service detected"),
              QStringLiteral("NeutronOS, Security Core, NetworkManager and Bluetooth service state plus actionable failed units."),
              serviceEvidence,
              serviceStatus == QStringLiteral("pass") ? QString() :
              QStringLiteral("Open Services Manager for the named unit and inspect Logs before restarting it.")));

    const QString controllers = commandOutput(QStringLiteral("sh"), {QStringLiteral("-c"),
        QStringLiteral("for d in /dev/input/event*; do [ -e \"$d\" ] && echo \"$d\"; done")}, 2000);
    const QString power = commandOutput(QStringLiteral("sh"), {QStringLiteral("-c"),
        QStringLiteral("for d in /sys/class/power_supply/*; do [ -r \"$d/type\" ] && printf '%s:%s ' \"$d\" \"$(cat \"$d/type\")\"; done")}, 2000);
    add(check(QStringLiteral("controller"), QStringLiteral("Controller"), controllers.isEmpty() ? QStringLiteral("warn") : QStringLiteral("pass"),
              controllers.isEmpty() ? QStringLiteral("No event device detected") : controllers.section(QLatin1Char('\n'), 0, 0),
              QStringLiteral("Input event paths and optional battery providers."),
              QStringLiteral("events=%1; power=%2").arg(controllers.isEmpty() ? QStringLiteral("none") : controllers, power.isEmpty() ? QStringLiteral("Unavailable") : power),
              controllers.isEmpty() ? QStringLiteral("Reconnect or pair a controller in Settings > Bluetooth.") : QString()));

    const QString drm = commandOutput(QStringLiteral("sh"), {QStringLiteral("-c"),
        QStringLiteral("for s in /sys/class/drm/card*-*/status; do [ -r \"$s\" ] && printf '%s=' \"$s\" && cat \"$s\"; done")}, 2500);
    const bool displayConnected = drm.contains(QStringLiteral("connected"));
    add(check(QStringLiteral("display"), QStringLiteral("Display"), displayConnected ? QStringLiteral("pass") : QStringLiteral("warn"),
              displayConnected ? QStringLiteral("Active connector detected") : QStringLiteral("HDMI state unavailable"),
              QStringLiteral("DRM connector presence; resolution/refresh remain driver-owned."), drm.isEmpty() ? QStringLiteral("Unavailable") : drm,
              displayConnected ? QString() : QStringLiteral("Verify HDMI cabling; Safe Resolution Fallback remains available.")));

    const QString securityPath = QStringLiteral("/var/lib/neutronos/security-core/state.json");
    const QString security = readText(securityPath);
    QJsonParseError securityParseError;
    const QJsonDocument securityDocument = QJsonDocument::fromJson(security.toUtf8(), &securityParseError);
    const bool securityAvailable = securityParseError.error == QJsonParseError::NoError && securityDocument.isObject();
    const QJsonObject securityObject = securityAvailable ? securityDocument.object() : QJsonObject();
    const bool auditProblem = securityAvailable && securityObject.value(QStringLiteral("auditValid")).isBool() &&
                              !securityObject.value(QStringLiteral("auditValid")).toBool();
    add(check(QStringLiteral("security"), QStringLiteral("Security"), !securityAvailable ? QStringLiteral("warn") :
              auditProblem ? QStringLiteral("fail") : QStringLiteral("pass"),
              !securityAvailable ? QStringLiteral("Unavailable") : auditProblem ? QStringLiteral("Audit invalid") : QStringLiteral("Security Core state available"),
              QStringLiteral("Unified Security Core state and audit-integrity signal."),
              securityAvailable ? QStringLiteral("path=%1; security-score=%2; audit-invalid=%3")
                  .arg(securityPath)
                  .arg(securityObject.value(QStringLiteral("securityScore")).toInt(-1))
                  .arg(auditProblem ? QStringLiteral("yes") : QStringLiteral("no"))
                                : QStringLiteral("%1 unavailable or invalid JSON").arg(securityPath),
              auditProblem ? QStringLiteral("Open Security Overview and run the authoritative integrity audit.") : QString()));

    const QString appsRoot = QDir(m_neutronRoot).filePath(QStringLiteral("qml/apps"));
    const QStringList appDirs = QDir(appsRoot).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    int appTargets = 0;
    int missingEntries = 0;
    for (const QString &app : appDirs) {
        const QDir directory(QDir(appsRoot).filePath(app));
        const bool hasMain = directory.exists(QStringLiteral("Main.qml"));
        const QString manifestPath = directory.filePath(QStringLiteral("app.json"));
        const bool hasManifest = QFileInfo::exists(manifestPath);
        // Runtime content directories such as qml/apps/games/roms are not app
        // targets. AppManager only treats a directory as an application when it
        // has an entry QML file or an app manifest.
        if (!hasMain && !hasManifest)
            continue;
        ++appTargets;
        bool validTarget = hasMain;
        if (hasManifest) {
            QFile manifestFile(manifestPath);
            if (manifestFile.open(QIODevice::ReadOnly)) {
                QJsonParseError parseError;
                const QJsonDocument manifestDocument = QJsonDocument::fromJson(manifestFile.readAll(), &parseError);
                validTarget = parseError.error == QJsonParseError::NoError && manifestDocument.isObject() && hasMain;
            } else {
                validTarget = false;
            }
        }
        if (!validTarget)
            ++missingEntries;
    }
    add(check(QStringLiteral("app-runtime"), QStringLiteral("App Runtime"), missingEntries > 0 ? QStringLiteral("warn") : QStringLiteral("pass"),
              QStringLiteral("%1 apps • %2 unavailable targets").arg(appTargets).arg(missingEntries),
              QStringLiteral("Filesystem-first AppManager launch targets and required QML entry points."),
              QStringLiteral("appsRoot=%1; app-targets=%2; content-directories=%3; missing=%4")
                  .arg(appsRoot).arg(appTargets).arg(appDirs.size() - appTargets).arg(missingEntries),
              missingEntries > 0 ? QStringLiteral("Open Applications and inspect unavailable launch targets.") : QString()));

    return {{QStringLiteral("checks"), results}, {QStringLiteral("passed"), passed},
            {QStringLiteral("warnings"), warnings}, {QStringLiteral("failed"), failed},
            {QStringLiteral("summary"), summary}};
}

QVariantMap DiagnosticsManager::buildSupportBundle() const
{
    const QString supportRoot = QDir(m_neutronRoot).filePath(QStringLiteral("state/support"));
    QDir().mkpath(supportRoot);
    const QString stamp = QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-HHmmss"));
    const QString staging = QDir(supportRoot).filePath(QStringLiteral(".bundle-") + QUuid::createUuid().toString(QUuid::WithoutBraces));
    if (!QDir().mkpath(staging)) return {{QStringLiteral("ok"), false}, {QStringLiteral("message"), QStringLiteral("Could not create support staging directory.")}};

    const QVariantMap report = collectDiagnostics();
    QSaveFile reportFile(QDir(staging).filePath(QStringLiteral("diagnostics.json")));
    if (reportFile.open(QIODevice::WriteOnly)) { reportFile.write(QJsonDocument::fromVariant(report).toJson(QJsonDocument::Indented)); reportFile.commit(); }

    const QList<QPair<QString, QString>> commands = {
        {QStringLiteral("neutronos-journal.txt"), redact(commandOutput(QStringLiteral("journalctl"), {QStringLiteral("-b"), QStringLiteral("-u"), QStringLiteral("neutronos.service"), QStringLiteral("-n"), QStringLiteral("1200"), QStringLiteral("--no-pager")}, 15000))},
        {QStringLiteral("kernel-warnings.txt"), redact(commandOutput(QStringLiteral("journalctl"), {QStringLiteral("-b"), QStringLiteral("-k"), QStringLiteral("-p"), QStringLiteral("warning..alert"), QStringLiteral("-n"), QStringLiteral("600"), QStringLiteral("--no-pager")}, 15000))},
        {QStringLiteral("failed-services.txt"), redact(commandOutput(QStringLiteral("systemctl"), {QStringLiteral("--failed"), QStringLiteral("--no-pager")}, 6000))},
        {QStringLiteral("storage.txt"), redact(commandOutput(QStringLiteral("lsblk"), {QStringLiteral("-o"), QStringLiteral("NAME,MODEL,SERIAL,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,ROTA,RO,TYPE")}, 6000))},
        {QStringLiteral("network.txt"), redact(commandOutput(QStringLiteral("ip"), {QStringLiteral("address"), QStringLiteral("show")}, 6000))},
        {QStringLiteral("routes.txt"), redact(commandOutput(QStringLiteral("ip"), {QStringLiteral("route"), QStringLiteral("show")}, 6000))}
    };
    for (const auto &entry : commands) {
        QSaveFile file(QDir(staging).filePath(entry.first));
        if (file.open(QIODevice::WriteOnly)) { file.write(entry.second.toUtf8()); file.commit(); }
    }

    const QString archive = QDir(supportRoot).filePath(QStringLiteral("NeutronOS-support-") + stamp + QStringLiteral(".tar.gz"));
    QProcess tar; tar.setProgram(QStandardPaths::findExecutable(QStringLiteral("tar")));
    tar.setArguments({QStringLiteral("-czf"), archive, QStringLiteral("-C"), staging, QStringLiteral(".")});
    tar.start(); const bool completed = tar.waitForStarted(3000) && tar.waitForFinished(30000) && tar.exitStatus() == QProcess::NormalExit && tar.exitCode() == 0;
    QDir(staging).removeRecursively();
    if (!completed || !QFileInfo::exists(archive)) return {{QStringLiteral("ok"), false}, {QStringLiteral("message"), QStringLiteral("Support bundle creation failed: ") + QString::fromUtf8(tar.readAllStandardError()).trimmed()}};
    return {{QStringLiteral("ok"), true}, {QStringLiteral("path"), archive}, {QStringLiteral("message"), QStringLiteral("Support bundle created at ") + archive}};
}

QString DiagnosticsManager::commandOutput(const QString &program, const QStringList &arguments, int timeoutMs)
{
    QString executable = QStandardPaths::findExecutable(program);
    if (executable.isEmpty()) return QString();
    QProcess process; process.setProgram(executable); process.setArguments(arguments); process.start();
    if (!process.waitForStarted(1500)) return QString();
    if (!process.waitForFinished(timeoutMs)) { process.kill(); process.waitForFinished(1000); }
    QString output = QString::fromUtf8(process.readAllStandardOutput());
    const QString error = QString::fromUtf8(process.readAllStandardError());
    if (!error.trimmed().isEmpty()) output += (output.endsWith(QLatin1Char('\n')) ? QString() : QStringLiteral("\n")) + error;
    return output.trimmed();
}

QString DiagnosticsManager::readText(const QString &path)
{
    QFile file(path); if (!file.open(QIODevice::ReadOnly)) return QString();
    return QString::fromUtf8(file.readAll());
}

QString DiagnosticsManager::redact(const QString &text)
{
    QStringList output;
    const QRegularExpression sensitive(QStringLiteral("(?i)(password|passwd|token|secret|api[_-]?key|authorization)\\s*[:=]"));
    for (const QString &line : text.split(QLatin1Char('\n'))) output << (sensitive.match(line).hasMatch() ? QStringLiteral("[REDACTED SENSITIVE LINE]") : line);
    return output.join(QLatin1Char('\n'));
}

void DiagnosticsManager::setBusy(bool value) { if (m_busy == value) return; m_busy = value; emit busyChanged(); }
void DiagnosticsManager::setProgress(int value) { value = qBound(0, value, 100); if (m_progress == value) return; m_progress = value; emit progressChanged(); }
void DiagnosticsManager::setStage(const QString &value) { if (m_stage == value) return; m_stage = value; emit stageChanged(); }
void DiagnosticsManager::setLastMessage(const QString &value) { if (m_lastMessage == value) return; m_lastMessage = value; emit lastMessageChanged(); }
