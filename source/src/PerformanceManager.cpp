#include "PerformanceManager.h"

#if defined(NEUTRONOS_PLATFORM_GEMINI)
#include "../platform/gemini/GeminiHardware.h"
#endif

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTextStream>

#include <algorithm>
#include <cmath>

namespace {
constexpr auto kBeginMarker = "# BEGIN NEUTRONOS PERFORMANCE PROFILE";
constexpr auto kEndMarker = "# END NEUTRONOS PERFORMANCE PROFILE";

int mapInt(const QVariantMap &map, const QString &key, int fallback)
{
    bool ok = false;
    const int value = map.value(key).toInt(&ok);
    return ok ? value : fallback;
}

bool mapBool(const QVariantMap &map, const QString &key, bool fallback)
{
    if (!map.contains(key))
        return fallback;
    return map.value(key).toBool();
}

QString titleCaseProfile(const QString &value)
{
    const QString normalized = value.trimmed().toLower();
    if (normalized == QStringLiteral("stage1")) return QStringLiteral("Stage 1");
    if (normalized == QStringLiteral("stage2")) return QStringLiteral("Stage 2");
    if (normalized == QStringLiteral("stage3")) return QStringLiteral("Stage 3");
    if (normalized == QStringLiteral("max")) return QStringLiteral("Max");
    if (normalized == QStringLiteral("balanced")) return QStringLiteral("Balanced");
    if (normalized == QStringLiteral("performance")) return QStringLiteral("Performance");
    if (normalized == QStringLiteral("custom")) return QStringLiteral("Custom");
    return QStringLiteral("Normal");
}
}

PerformanceManager::PerformanceManager(QObject *parent)
    : QObject(parent)
{
    m_piModel = detectPiModel();
    m_spec = determineModelSpec(m_piModel);
    m_available = !m_piModel.isEmpty() && !configPath().isEmpty();
    m_profiles = buildDefaultProfiles();
    loadSavedProfiles();
    m_currentConfiguration = parseManagedConfiguration();

    m_refreshTimer.setInterval(2500);
    m_refreshTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_refreshTimer, &QTimer::timeout, this, &PerformanceManager::refresh);
    m_refreshTimer.start();
    refresh();

    /* The legacy PowerMode manager used to cap every boot at 1.5 GHz.
       Re-apply the explicitly selected managed profile to cpufreq after the
       firmware has exposed its new hardware maximum. */
    QTimer::singleShot(700, this, [this]() {
        if (m_runtimePolicySynchronized || m_runtimePolicyAttempts >= 4)
            return;
        QString ignored;
        m_runtimePolicySynchronized = applyRuntimePolicy(m_currentConfiguration, &ignored);
        ++m_runtimePolicyAttempts;
    });
}

bool PerformanceManager::available() const { return m_available; }
QString PerformanceManager::piModel() const { return m_piModel; }
QString PerformanceManager::modelKey() const { return m_spec.key; }
QVariantMap PerformanceManager::telemetry() const { return m_telemetry; }
QVariantMap PerformanceManager::currentConfiguration() const { return m_currentConfiguration; }
QVariantList PerformanceManager::defaultProfiles() const { return m_profiles; }
QVariantList PerformanceManager::savedProfiles() const { return m_savedProfiles; }
QVariantList PerformanceManager::availableProfiles() const
{
    QVariantList profiles = m_profiles;
    profiles.append(m_savedProfiles);
    return profiles;
}
QVariantList PerformanceManager::autoRecommendations() const { return m_recommendations; }
bool PerformanceManager::autoConfigAllowed() const { return m_autoConfigAllowed; }
QString PerformanceManager::healthMessage() const { return m_healthMessage; }
bool PerformanceManager::busy() const { return m_busy; }
QString PerformanceManager::lastMessage() const { return m_lastMessage; }

QVariantMap PerformanceManager::modelLimits() const
{
    return {
        {QStringLiteral("model"), m_piModel},
        {QStringLiteral("modelKey"), m_spec.key},
        {QStringLiteral("stockCpuMinMhz"), m_spec.stockMin},
        {QStringLiteral("stockCpuMaxMhz"), m_spec.stockMax},
        {QStringLiteral("stockGpuMhz"), m_spec.stockGpu},
        {QStringLiteral("manualCpuMaxMhz"), m_spec.manualMax},
        {QStringLiteral("manualGpuMaxMhz"), m_spec.gpuMax},
        {QStringLiteral("temperatureCautionC"), m_spec.cautionC},
        {QStringLiteral("temperatureHotC"), m_spec.hotC}
    };
}

QString PerformanceManager::readTextFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromUtf8(file.readAll()).trimmed();
}

bool PerformanceManager::writeTextFileAtomically(const QString &path,
                                                 const QByteArray &data,
                                                 QString *errorMessage)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        if (errorMessage) *errorMessage = file.errorString();
        return false;
    }
    if (file.write(data) != data.size()) {
        if (errorMessage) *errorMessage = file.errorString();
        file.cancelWriting();
        return false;
    }
    if (!file.commit()) {
        if (errorMessage) *errorMessage = file.errorString();
        return false;
    }
    return true;
}

QString PerformanceManager::runCommand(const QString &program,
                                       const QStringList &arguments,
                                       int timeoutMs)
{
    QProcess process;
    process.start(program, arguments);
    if (!process.waitForStarted(300))
        return {};
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(200);
        return {};
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
        return {};
    return QString::fromUtf8(process.readAllStandardOutput()).trimmed();
}

QString PerformanceManager::detectPiModel() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    const QString model = GeminiHardware::model();
    return model.isEmpty() ? QStringLiteral("x86_64 PC") : model;
#else
    QString model = readTextFile(QStringLiteral("/proc/device-tree/model"));
    model.remove(QChar('\0'));
    if (!model.isEmpty())
        return model;
    model = readTextFile(QStringLiteral("/sys/firmware/devicetree/base/model"));
    model.remove(QChar('\0'));
    return model;
#endif
}

PerformanceManager::ModelSpec PerformanceManager::determineModelSpec(const QString &model) const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    Q_UNUSED(model)
    ModelSpec spec;
    spec.key = QStringLiteral("gemini");
    spec.filter = QString();
    quint64 minimum = 0, maximum = 0;
    for (const QString &policy : GeminiHardware::cpuPolicies()) {
        const quint64 low = GeminiHardware::frequencyKhz(policy, QStringLiteral("cpuinfo_min_freq"));
        const quint64 high = GeminiHardware::frequencyKhz(policy, QStringLiteral("cpuinfo_max_freq"));
        if (!low || !high) continue;
        minimum = qMax(minimum, low);
        maximum = maximum ? qMin(maximum, high) : high;
    }
    spec.stockMin = static_cast<int>((minimum + 999ULL) / 1000ULL);
    spec.stockMax = spec.manualMax = spec.balancedMax = spec.performanceMax = static_cast<int>(maximum / 1000ULL);
    spec.stockGpu = spec.gpuMax = spec.balancedGpu = spec.performanceGpu = 0;
    const auto temperature = GeminiHardware::cpuTemperature();
    spec.cautionC = temperature.warning;
    spec.hotC = temperature.critical;
    return spec;
#else
    const QString m = model.toLower();
    ModelSpec s;

    if (m.contains(QStringLiteral("raspberry pi 5")) || m.contains(QStringLiteral("compute module 5")) ||
        m.contains(QStringLiteral("raspberry pi 500"))) {
        s = {QStringLiteral("pi5"), QStringLiteral("[pi5]"), 1500, 2400, 960, 3000, 1200,
             2700, 1000, 2900, 1100, 78, 68};
    } else if (m.contains(QStringLiteral("raspberry pi 400"))) {
        s = {QStringLiteral("pi400"), QStringLiteral("[pi400]"), 600, 1800, 500, 2300, 700,
             2000, 550, 2200, 600, 75, 65};
    } else if (m.contains(QStringLiteral("raspberry pi 4")) || m.contains(QStringLiteral("compute module 4"))) {
        s = {QStringLiteral("pi4"), QStringLiteral("[pi4]"), 600, 1500, 500, 2200, 700,
             1800, 525, 2000, 550, 75, 65};
    } else if (m.contains(QStringLiteral("3 model b+")) || m.contains(QStringLiteral("3 model a+")) ||
               m.contains(QStringLiteral("compute module 3+"))) {
        s = {QStringLiteral("pi3plus"), QStringLiteral("[pi3+]"), 600, 1400, 400, 1600, 500,
             1450, 425, 1500, 450, 72, 62};
    } else if (m.contains(QStringLiteral("raspberry pi 3")) || m.contains(QStringLiteral("compute module 3"))) {
        s = {QStringLiteral("pi3"), QStringLiteral("[pi3]"), 600, 1200, 400, 1450, 500,
             1300, 425, 1400, 450, 72, 62};
    } else if (m.contains(QStringLiteral("zero 2"))) {
        s = {QStringLiteral("pi02"), QStringLiteral("[pi02]"), 600, 1000, 400, 1300, 500,
             1100, 425, 1200, 450, 72, 62};
    } else if (m.contains(QStringLiteral("raspberry pi 2"))) {
        s = {QStringLiteral("pi2"), QStringLiteral("[pi2]"), 600, 900, 250, 1200, 400,
             1000, 275, 1100, 300, 72, 62};
    } else {
        s.key = QStringLiteral("unknown");
        s.filter = QStringLiteral("[all]");
    }
    return s;
#endif
}

QString PerformanceManager::configPath() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    return QString();
#else
    const QStringList candidates = {
        QStringLiteral("/boot/firmware/config.txt"),
        QStringLiteral("/boot/config.txt")
    };
    for (const QString &candidate : candidates) {
        if (QFileInfo::exists(candidate))
            return candidate;
    }
    return {};
#endif
}

QString PerformanceManager::profileStorePath() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    return QStringLiteral("/opt/neutronos/state/performance/profiles.json");
#else
    QDir project(QCoreApplication::applicationDirPath());
    if (project.dirName() == QStringLiteral("build"))
        project.cdUp();
    if (!QFileInfo::exists(project.filePath(QStringLiteral("qml"))))
        project = QDir(QDir::home().filePath(QStringLiteral("NeutronOS")));
    return project.filePath(QStringLiteral("state/performance/profiles.json"));
#endif
}

void PerformanceManager::loadSavedProfiles()
{
    m_savedProfiles.clear();
    QFile file(profileStorePath());
    if (!file.open(QIODevice::ReadOnly))
        return;
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isArray())
        return;
    int fallbackIndex = 1;
    for (const QJsonValue &value : document.array()) {
        if (!value.isObject())
            continue;
        QVariantMap map = normalizeConfiguration(value.toObject().toVariantMap());
        if (map.value(QStringLiteral("stock")).toBool())
            continue;
        QString id = value.toObject().value(QStringLiteral("profile")).toString().trimmed();
        if (!id.startsWith(QStringLiteral("custom-")))
            id = QStringLiteral("custom-%1").arg(fallbackIndex++);
        QString name = value.toObject().value(QStringLiteral("profileName")).toString().trimmed();
        if (name.isEmpty())
            name = QStringLiteral("Custom %1").arg(fallbackIndex);
        map.insert(QStringLiteral("profile"), id);
        map.insert(QStringLiteral("profileName"), name);
        map.insert(QStringLiteral("saved"), true);
        map.insert(QStringLiteral("createdUtc"), value.toObject().value(QStringLiteral("createdUtc")).toString());
        m_savedProfiles.append(map);
    }
}

bool PerformanceManager::persistSavedProfiles(QString *errorMessage) const
{
    const QString path = profileStorePath();
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        if (errorMessage)
            *errorMessage = QStringLiteral("Could not create the performance profile folder.");
        return false;
    }
    const QByteArray data = QJsonDocument::fromVariant(m_savedProfiles).toJson(QJsonDocument::Indented);
    return writeTextFileAtomically(path, data, errorMessage);
}

QVariantMap PerformanceManager::stockConfiguration() const
{
    return {
        {QStringLiteral("profile"), QStringLiteral("normal")},
        {QStringLiteral("profileName"), QStringLiteral("Normal")},
        {QStringLiteral("cpuMinMhz"), m_spec.stockMin},
        {QStringLiteral("cpuMaxMhz"), m_spec.stockMax},
        {QStringLiteral("gpuMhz"), m_spec.stockGpu},
        {QStringLiteral("turbo"), false},
        {QStringLiteral("stock"), true}
    };
}

QVariantMap PerformanceManager::normalizeConfiguration(const QVariantMap &configuration) const
{
    QVariantMap out = stockConfiguration();
    QString profile = configuration.value(QStringLiteral("profile"), QStringLiteral("custom"))
                          .toString().trimmed().toLower();
    if (profile.isEmpty()) profile = QStringLiteral("custom");
    out.insert(QStringLiteral("profile"), profile);
    out.insert(QStringLiteral("profileName"),
               configuration.value(QStringLiteral("profileName"), titleCaseProfile(profile)).toString());
    out.insert(QStringLiteral("cpuMinMhz"), mapInt(configuration, QStringLiteral("cpuMinMhz"), m_spec.stockMin));
    out.insert(QStringLiteral("cpuMaxMhz"), mapInt(configuration, QStringLiteral("cpuMaxMhz"), m_spec.stockMax));
    out.insert(QStringLiteral("gpuMhz"), mapInt(configuration, QStringLiteral("gpuMhz"), m_spec.stockGpu));
    out.insert(QStringLiteral("turbo"), mapBool(configuration, QStringLiteral("turbo"), false));
    const bool stock = out.value(QStringLiteral("cpuMinMhz")).toInt() == m_spec.stockMin &&
                       out.value(QStringLiteral("cpuMaxMhz")).toInt() == m_spec.stockMax &&
                       out.value(QStringLiteral("gpuMhz")).toInt() == m_spec.stockGpu &&
                       !out.value(QStringLiteral("turbo")).toBool();
    out.insert(QStringLiteral("stock"), stock);
    if (stock) {
        out.insert(QStringLiteral("profile"), QStringLiteral("normal"));
        out.insert(QStringLiteral("profileName"), QStringLiteral("Normal"));
    }
    return out;
}

QVariantMap PerformanceManager::parseManagedConfiguration() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    QVariantMap map = stockConfiguration();
    const QStringList policies = GeminiHardware::cpuPolicies();
    if (!policies.isEmpty()) {
        const quint64 low = GeminiHardware::frequencyKhz(policies.first(), QStringLiteral("scaling_min_freq"));
        const quint64 high = GeminiHardware::frequencyKhz(policies.first(), QStringLiteral("scaling_max_freq"));
        map.insert(QStringLiteral("cpuMinMhz"), low / 1000ULL);
        map.insert(QStringLiteral("cpuMaxMhz"), high / 1000ULL);
    }
    return map;
#else
    const QString path = configPath();
    if (path.isEmpty())
        return stockConfiguration();
    const QString text = readTextFile(path);
    const int begin = text.indexOf(QString::fromLatin1(kBeginMarker));
    const int end = text.indexOf(QString::fromLatin1(kEndMarker));
    if (begin < 0 || end <= begin)
        return stockConfiguration();
    const QString block = text.mid(begin, end - begin);
    QVariantMap map;
    auto captureInt = [&block](const QString &key, int fallback) {
        QRegularExpression re(QStringLiteral("^\\s*%1\\s*=\\s*(\\d+)\\s*$")
                              .arg(QRegularExpression::escape(key)),
                              QRegularExpression::MultilineOption);
        const auto match = re.match(block);
        return match.hasMatch() ? match.captured(1).toInt() : fallback;
    };
    QRegularExpression profileRe(QStringLiteral("^# PROFILE: (.+)$"),
                                 QRegularExpression::MultilineOption);
    const auto profileMatch = profileRe.match(block);
    const QString profileName = profileMatch.hasMatch() ? profileMatch.captured(1).trimmed() : QStringLiteral("Custom");
    map.insert(QStringLiteral("profileName"), profileName);
    map.insert(QStringLiteral("profile"), profileName.toLower().remove(QChar(' ')));
    map.insert(QStringLiteral("cpuMinMhz"), captureInt(QStringLiteral("arm_freq_min"), m_spec.stockMin));
    map.insert(QStringLiteral("cpuMaxMhz"), captureInt(QStringLiteral("arm_freq"), m_spec.stockMax));
    map.insert(QStringLiteral("gpuMhz"), captureInt(QStringLiteral("v3d_freq"), m_spec.stockGpu));
    map.insert(QStringLiteral("turbo"), captureInt(QStringLiteral("force_turbo"), 0) == 1);
    return normalizeConfiguration(map);
#endif
}

QVariantList PerformanceManager::buildDefaultProfiles() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    return {stockConfiguration()};
#else
    const int cpuSpan = std::max(100, m_spec.performanceMax - m_spec.stockMax);
    const int gpuSpan = std::max(25, m_spec.performanceGpu - m_spec.stockGpu);
    auto profile = [this](const QString &id, const QString &name, int min, int max, int gpu, bool turbo) {
        QVariantMap map{{QStringLiteral("profile"), id}, {QStringLiteral("profileName"), name},
                        {QStringLiteral("cpuMinMhz"), min}, {QStringLiteral("cpuMaxMhz"), max},
                        {QStringLiteral("gpuMhz"), gpu}, {QStringLiteral("turbo"), turbo}};
        return normalizeConfiguration(map);
    };
    return {
        profile(QStringLiteral("normal"), QStringLiteral("Normal"), m_spec.stockMin, m_spec.stockMax, m_spec.stockGpu, false),
        profile(QStringLiteral("stage1"), QStringLiteral("Stage 1"), m_spec.stockMin,
                m_spec.stockMax + cpuSpan / 3, m_spec.stockGpu + gpuSpan / 3, false),
        profile(QStringLiteral("stage2"), QStringLiteral("Stage 2"), m_spec.stockMin,
                m_spec.stockMax + (cpuSpan * 2) / 3, m_spec.stockGpu + (gpuSpan * 2) / 3, false),
        profile(QStringLiteral("stage3"), QStringLiteral("Stage 3"), m_spec.stockMin,
                m_spec.performanceMax, m_spec.performanceGpu, false),
        profile(QStringLiteral("max"), QStringLiteral("Max"), m_spec.performanceMax,
                m_spec.manualMax, m_spec.gpuMax, true)
    };
#endif
}

QVariantMap PerformanceManager::profileConfiguration(const QString &profileName) const
{
    const QString target = profileName.trimmed().toLower().remove(QChar(' '));
    const QVariantList profiles = availableProfiles();
    for (const QVariant &entry : profiles) {
        const QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("profile")).toString().toLower().remove(QChar(' ')) == target ||
            map.value(QStringLiteral("profileName")).toString().toLower().remove(QChar(' ')) == target)
            return map;
    }
    return stockConfiguration();
}

QVariantMap PerformanceManager::saveCustomProfile(const QVariantMap &configuration)
{
    const QVariantMap assessment = evaluateConfiguration(configuration);
    if (!assessment.value(QStringLiteral("ok")).toBool())
        return result(false, assessment.value(QStringLiteral("errors")).toStringList().join(QStringLiteral(" ")));
    QVariantMap normalized = normalizeConfiguration(configuration);
    if (normalized.value(QStringLiteral("stock")).toBool())
        return result(false, QStringLiteral("Normal is already available as the stock profile."));

    for (const QVariant &entry : m_savedProfiles) {
        const QVariantMap existing = entry.toMap();
        if (existing.value(QStringLiteral("cpuMinMhz")) == normalized.value(QStringLiteral("cpuMinMhz")) &&
            existing.value(QStringLiteral("cpuMaxMhz")) == normalized.value(QStringLiteral("cpuMaxMhz")) &&
            existing.value(QStringLiteral("gpuMhz")) == normalized.value(QStringLiteral("gpuMhz")) &&
            existing.value(QStringLiteral("turbo")) == normalized.value(QStringLiteral("turbo"))) {
            return result(true, QStringLiteral("That custom profile is already saved."),
                          {{QStringLiteral("profile"), existing}});
        }
    }

    const int number = m_savedProfiles.size() + 1;
    normalized.insert(QStringLiteral("profile"), QStringLiteral("custom-%1").arg(QDateTime::currentMSecsSinceEpoch()));
    normalized.insert(QStringLiteral("profileName"), QStringLiteral("Custom %1").arg(number));
    normalized.insert(QStringLiteral("saved"), true);
    normalized.insert(QStringLiteral("createdUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    m_savedProfiles.append(normalized);
    QString error;
    if (!persistSavedProfiles(&error)) {
        m_savedProfiles.removeLast();
        return result(false, error);
    }
    emit profilesChanged();
    return result(true, QStringLiteral("Saved %1. It is now available in Hidden Dock.")
                         .arg(normalized.value(QStringLiteral("profileName")).toString()),
                  {{QStringLiteral("profile"), normalized}});
}


double PerformanceManager::sampleCpuLoadPercent()
{
    QFile file(QStringLiteral("/proc/stat"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return 0.0;
    const QString line = QString::fromUtf8(file.readLine()).trimmed();
    const QStringList values = line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    if (values.size() < 5 || values.first() != QStringLiteral("cpu"))
        return 0.0;
    quint64 total = 0;
    for (int i = 1; i < values.size(); ++i)
        total += values.at(i).toULongLong();
    const quint64 idle = values.value(4).toULongLong() + values.value(5).toULongLong();
    double load = 0.0;
    if (m_previousTotalJiffies > 0 && total > m_previousTotalJiffies) {
        const quint64 totalDelta = total - m_previousTotalJiffies;
        const quint64 idleDelta = idle >= m_previousIdleJiffies ? idle - m_previousIdleJiffies : 0;
        if (totalDelta > 0)
            load = 100.0 * double(totalDelta - std::min(totalDelta, idleDelta)) / double(totalDelta);
    }
    m_previousTotalJiffies = total;
    m_previousIdleJiffies = idle;
    return std::clamp(load, 0.0, 100.0);
}

quint32 PerformanceManager::throttledFlags() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    return 0U; // Pi firmware throttle flags have no PC equivalent.
#else
    const QString output = runCommand(QStringLiteral("vcgencmd"), {QStringLiteral("get_throttled")}, 700);
    QRegularExpression re(QStringLiteral("0x([0-9a-fA-F]+)"));
    const auto match = re.match(output);
    bool ok = false;
    return match.hasMatch() ? match.captured(1).toUInt(&ok, 16) : 0U;
#endif
}

bool PerformanceManager::coolingDetected() const
{
    QDir root(QStringLiteral("/sys/class/thermal"));
    const QStringList devices = root.entryList({QStringLiteral("cooling_device*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &device : devices) {
        const QString type = readTextFile(root.filePath(device + QStringLiteral("/type"))).toLower();
        if (type.contains(QStringLiteral("fan")) || type.contains(QStringLiteral("pwm")))
            return true;
    }
    return false;
}

bool PerformanceManager::recentKernelPowerOrThermalWarning()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (m_lastJournalCheckMs > 0 && now - m_lastJournalCheckMs < 60000)
        return m_recentKernelWarning;
    m_lastJournalCheckMs = now;
    const QString output = runCommand(QStringLiteral("journalctl"),
                                      {QStringLiteral("-b"), QStringLiteral("-k"),
                                       QStringLiteral("--since"), QStringLiteral("-30 minutes"),
                                       QStringLiteral("--no-pager"), QStringLiteral("-o"), QStringLiteral("cat")},
                                      1200).toLower();
    m_recentKernelWarning = output.contains(QStringLiteral("undervoltage")) ||
                            output.contains(QStringLiteral("under-voltage")) ||
                            output.contains(QStringLiteral("throttl")) ||
                            output.contains(QStringLiteral("soft temperature limit"));
    return m_recentKernelWarning;
}

QVariantMap PerformanceManager::sampleTelemetry()
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    const auto temperature = GeminiHardware::cpuTemperature();
    quint64 currentKhz = 0;
    for (const QString &policy : GeminiHardware::cpuPolicies())
        currentKhz = qMax(currentKhz, GeminiHardware::frequencyKhz(policy, QStringLiteral("scaling_cur_freq")));
    const double load = sampleCpuLoadPercent();
    const bool recentWarning = recentKernelPowerOrThermalWarning();
    const bool hot = temperature.available && temperature.celsius >= temperature.critical;
    m_autoConfigAllowed = false;
    m_healthMessage = QStringLiteral("Pi firmware overclock profiles are unavailable on Gemini. Use Normal/Performance mode for supported Linux CPU governors.");
    return {{QStringLiteral("temperatureC"), temperature.available ? temperature.celsius : -1.0},
            {QStringLiteral("temperatureAvailable"), temperature.available},
            {QStringLiteral("temperatureSource"), temperature.source},
            {QStringLiteral("currentCpuMhz"), static_cast<double>(currentKhz) / 1000.0},
            {QStringLiteral("currentGpuMhz"), 0.0},
            {QStringLiteral("gpuClockAvailable"), false},
            {QStringLiteral("cpuLoadPercent"), load},
            {QStringLiteral("throttledHex"), QStringLiteral("Unavailable")},
            {QStringLiteral("throttleStatusAvailable"), false},
            {QStringLiteral("recentKernelWarning"), recentWarning},
            {QStringLiteral("coolingDetected"), coolingDetected()},
            {QStringLiteral("healthy"), temperature.available && !hot && !recentWarning && load < 92.0},
            {QStringLiteral("caution"), temperature.available && temperature.celsius >= temperature.warning},
            {QStringLiteral("healthMessage"), m_healthMessage},
            {QStringLiteral("sampledUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}};
#else
    QVariantMap t;
    bool ok = false;
    const double temperatureC = readTextFile(QStringLiteral("/sys/class/thermal/thermal_zone0/temp")).toDouble(&ok) / 1000.0;
    const QString armClock = runCommand(QStringLiteral("vcgencmd"), {QStringLiteral("measure_clock"), QStringLiteral("arm")}, 700);
    const QString gpuClock = runCommand(QStringLiteral("vcgencmd"), {QStringLiteral("measure_clock"), QStringLiteral("v3d")}, 700);
    auto parseHz = [](const QString &text) {
        const int eq = text.indexOf(QChar('='));
        bool parsed = false;
        const double hz = (eq >= 0 ? text.mid(eq + 1) : text).trimmed().toDouble(&parsed);
        return parsed ? hz / 1000000.0 : 0.0;
    };
    const quint32 flags = throttledFlags();
    const bool underVoltageNow = flags & 0x1U;
    const bool cappedNow = flags & 0x2U;
    const bool throttledNow = flags & 0x4U;
    const bool softTempNow = flags & 0x8U;
    const bool historyUnderVoltage = flags & 0x10000U;
    const bool historyCapped = flags & 0x20000U;
    const bool historyThrottled = flags & 0x40000U;
    const bool historySoftTemp = flags & 0x80000U;
    const bool recentWarning = recentKernelPowerOrThermalWarning();
    const double load = sampleCpuLoadPercent();
    const bool currentFault = underVoltageNow || cappedNow || throttledNow || softTempNow;
    const bool hot = ok && temperatureC >= m_spec.hotC;
    const bool caution = ok && temperatureC >= m_spec.cautionC;
    const bool overloaded = load >= 92.0;
    const bool healthy = !currentFault && !hot && !recentWarning && !overloaded;

    QStringList reasons;
    if (underVoltageNow) reasons << QStringLiteral("undervoltage is currently detected");
    if (cappedNow) reasons << QStringLiteral("the CPU frequency is currently capped");
    if (throttledNow) reasons << QStringLiteral("the Pi is currently throttled");
    if (softTempNow) reasons << QStringLiteral("the soft temperature limit is active");
    if (hot) reasons << QStringLiteral("CPU temperature is too high");
    else if (caution) reasons << QStringLiteral("CPU temperature is elevated");
    if (recentWarning) reasons << QStringLiteral("a power or thermal warning occurred in the last 30 minutes");
    if (overloaded) reasons << QStringLiteral("current CPU load is too high for a health assessment");

    m_autoConfigAllowed = healthy;
    m_healthMessage = healthy
        ? QStringLiteral("Healthy for model-aware overclock recommendations. Cooling and proper voltage are still required.")
        : QStringLiteral("Overclocking is not currently recommended: %1.").arg(reasons.join(QStringLiteral(", ")));

    t.insert(QStringLiteral("temperatureC"), ok ? temperatureC : -1.0);
    t.insert(QStringLiteral("currentCpuMhz"), parseHz(armClock));
    t.insert(QStringLiteral("currentGpuMhz"), parseHz(gpuClock));
    t.insert(QStringLiteral("cpuLoadPercent"), load);
    t.insert(QStringLiteral("throttledHex"), QStringLiteral("0x%1").arg(flags, 0, 16));
    t.insert(QStringLiteral("underVoltageNow"), underVoltageNow);
    t.insert(QStringLiteral("frequencyCappedNow"), cappedNow);
    t.insert(QStringLiteral("throttledNow"), throttledNow);
    t.insert(QStringLiteral("softTemperatureNow"), softTempNow);
    t.insert(QStringLiteral("underVoltageOccurred"), historyUnderVoltage);
    t.insert(QStringLiteral("frequencyCappedOccurred"), historyCapped);
    t.insert(QStringLiteral("throttlingOccurred"), historyThrottled);
    t.insert(QStringLiteral("softTemperatureOccurred"), historySoftTemp);
    t.insert(QStringLiteral("recentKernelWarning"), recentWarning);
    t.insert(QStringLiteral("coolingDetected"), coolingDetected());
    t.insert(QStringLiteral("healthy"), healthy);
    t.insert(QStringLiteral("caution"), caution || historyUnderVoltage || historyCapped || historyThrottled || historySoftTemp);
    t.insert(QStringLiteral("healthMessage"), m_healthMessage);
    t.insert(QStringLiteral("sampledUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    return t;
#endif
}

QVariantMap PerformanceManager::evaluateConfiguration(const QVariantMap &configuration) const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    const QString message = QStringLiteral("Pi firmware overclock configuration is unavailable on Gemini.");
    return {{QStringLiteral("ok"), false}, {QStringLiteral("errors"), QStringList{message}},
            {QStringLiteral("warningLevel"), QStringLiteral("unavailable")},
            {QStringLiteral("warningText"), message}, {QStringLiteral("healthOk"), false},
            {QStringLiteral("configuration"), configuration}};
#else
    const QVariantMap c = normalizeConfiguration(configuration);
    const int min = c.value(QStringLiteral("cpuMinMhz")).toInt();
    const int max = c.value(QStringLiteral("cpuMaxMhz")).toInt();
    const int gpu = c.value(QStringLiteral("gpuMhz")).toInt();
    const bool turbo = c.value(QStringLiteral("turbo")).toBool();
    QStringList errors;
    if (min < m_spec.stockMin || min > m_spec.manualMax) errors << QStringLiteral("Idle CPU speed is outside the supported range.");
    if (max < m_spec.stockMax || max > m_spec.manualMax) errors << QStringLiteral("Maximum CPU speed is outside the model range.");
    if (min > max) errors << QStringLiteral("Idle CPU speed cannot exceed maximum CPU speed.");
    if (gpu < m_spec.stockGpu || gpu > m_spec.gpuMax) errors << QStringLiteral("GPU speed is outside the model range.");

    int level = 0;
    QString label = QStringLiteral("NORMAL");
    QStringList reasons;
    const bool stock = c.value(QStringLiteral("stock")).toBool();
    if (!stock) {
        level = 1;
        label = QStringLiteral("LOW");
        reasons << QStringLiteral("Cooling and proper voltage/power delivery are required.");
        if (max > m_spec.balancedMax || gpu > m_spec.balancedGpu || min > m_spec.stockMin) {
            level = 2;
            label = QStringLiteral("MODERATE");
        }
        if (m_spec.key == QStringLiteral("pi4") && max >= 1800 && max <= 2000 &&
            gpu <= 550 && !turbo) {
            reasons << QStringLiteral("For Raspberry Pi 4, 1.8–2.0 GHz is inside the model-appropriate range when adequate cooling and proper voltage are present.");
        }
        if (max > m_spec.performanceMax || gpu > m_spec.performanceGpu || min >= m_spec.stockMax) {
            level = 3;
            label = QStringLiteral("HIGH");
            reasons << QStringLiteral("The selected clocks are beyond the model's normal recommendation.");
        }
        if (turbo) {
            level = std::max(level, 3);
            label = QStringLiteral("HIGH");
            reasons << QStringLiteral("Turbo holds maximum frequencies even while idle.");
        }
        if (max >= m_spec.manualMax && turbo) {
            level = 4;
            label = QStringLiteral("EXTREME");
        }
    }
    const bool healthOk = m_telemetry.value(QStringLiteral("healthy"), false).toBool();
    return {
        {QStringLiteral("ok"), errors.isEmpty()},
        {QStringLiteral("errors"), errors},
        {QStringLiteral("warningLevel"), level},
        {QStringLiteral("warningLabel"), label},
        {QStringLiteral("warningText"), reasons.join(QStringLiteral(" "))},
        {QStringLiteral("requiresWarning"), !stock},
        {QStringLiteral("healthOk"), healthOk},
        {QStringLiteral("healthMessage"), m_healthMessage},
        {QStringLiteral("configuration"), c}
    };
#endif
}

QVariantList PerformanceManager::buildRecommendations() const
{
    if (!m_autoConfigAllowed)
        return {};
    QVariantMap balanced{{QStringLiteral("profile"), QStringLiteral("balanced")},
                         {QStringLiteral("profileName"), QStringLiteral("Balanced")},
                         {QStringLiteral("cpuMinMhz"), m_spec.stockMin},
                         {QStringLiteral("cpuMaxMhz"), m_spec.balancedMax},
                         {QStringLiteral("gpuMhz"), m_spec.balancedGpu},
                         {QStringLiteral("turbo"), false},
                         {QStringLiteral("reason"), QStringLiteral("Moderate clocks with dynamic idle scaling and turbo off.")}};
    QVariantMap performance{{QStringLiteral("profile"), QStringLiteral("performance")},
                            {QStringLiteral("profileName"), QStringLiteral("Performance")},
                            {QStringLiteral("cpuMinMhz"), m_spec.stockMin},
                            {QStringLiteral("cpuMaxMhz"), m_spec.performanceMax},
                            {QStringLiteral("gpuMhz"), m_spec.performanceGpu},
                            {QStringLiteral("turbo"), false},
                            {QStringLiteral("reason"), QStringLiteral("Higher model-appropriate clocks while retaining dynamic scaling.")}};
    balanced = normalizeConfiguration(balanced);
    performance = normalizeConfiguration(performance);
    balanced.insert(QStringLiteral("reason"), QStringLiteral("Moderate clocks with dynamic idle scaling and turbo off."));
    performance.insert(QStringLiteral("reason"), QStringLiteral("Higher model-appropriate clocks while retaining dynamic scaling."));
    balanced.insert(QStringLiteral("assessment"), evaluateConfiguration(balanced));
    performance.insert(QStringLiteral("assessment"), evaluateConfiguration(performance));
    return {balanced, performance};
}

void PerformanceManager::refresh()
{
    const QVariantMap oldTelemetry = m_telemetry;
    const QVariantMap oldConfig = m_currentConfiguration;
    m_telemetry = sampleTelemetry();
    m_recommendations = buildRecommendations();
    m_currentConfiguration = parseManagedConfiguration();
    if (oldTelemetry != m_telemetry)
        emit telemetryChanged();
    if (oldConfig != m_currentConfiguration) {
        m_runtimePolicySynchronized = false;
        m_runtimePolicyAttempts = 0;
        emit configurationChanged();
    }

    if (!m_runtimePolicySynchronized && m_runtimePolicyAttempts < 4) {
        QString ignored;
        m_runtimePolicySynchronized = applyRuntimePolicy(m_currentConfiguration, &ignored);
        ++m_runtimePolicyAttempts;
    }
}

bool PerformanceManager::applyRuntimePolicy(const QVariantMap &configuration,
                                            QString *errorMessage)
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    Q_UNUSED(configuration)
    if (errorMessage) *errorMessage = QStringLiteral("Pi firmware profiles do not control Gemini CPU policies. Use Normal/Performance mode.");
    return false;
#else
    const QVariantMap c = normalizeConfiguration(configuration);
    const quint64 requestedMaxKhz = static_cast<quint64>(c.value(QStringLiteral("cpuMaxMhz")).toInt()) * 1000ULL;
    const quint64 requestedMinKhz = static_cast<quint64>(c.value(QStringLiteral("cpuMinMhz")).toInt()) * 1000ULL;

    QDir policyRoot(QStringLiteral("/sys/devices/system/cpu/cpufreq"));
    const QStringList policies = policyRoot.entryList(
        QStringList() << QStringLiteral("policy*"),
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::Name);

    if (policies.isEmpty()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("CPU frequency policies are unavailable.");
        return false;
    }

    for (const QString &name : policies) {
        const QDir policy(policyRoot.filePath(name));
        bool maxOk = false;
        const quint64 hardwareMaxKhz = readTextFile(
            policy.filePath(QStringLiteral("cpuinfo_max_freq"))).toULongLong(&maxOk);
        if (!maxOk || hardwareMaxKhz == 0ULL) {
            if (errorMessage)
                *errorMessage = QStringLiteral("Hardware CPU maximum is unavailable for %1.").arg(name);
            return false;
        }

        const quint64 targetMaxKhz = std::min(requestedMaxKhz, hardwareMaxKhz);
        const quint64 targetMinKhz = std::min(requestedMinKhz, targetMaxKhz);

        auto writeSysfs = [&](const QString &fileName, quint64 value) -> bool {
            QFile file(policy.filePath(fileName));
            if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
                if (errorMessage)
                    *errorMessage = QStringLiteral("Cannot update %1: %2").arg(file.fileName(), file.errorString());
                return false;
            }
            const QByteArray data = QByteArray::number(value);
            if (file.write(data) != data.size()) {
                if (errorMessage)
                    *errorMessage = QStringLiteral("Could not write %1.").arg(file.fileName());
                return false;
            }
            return true;
        };

        const quint64 currentMinKhz = readTextFile(
            policy.filePath(QStringLiteral("scaling_min_freq"))).toULongLong();
        if (currentMinKhz > targetMaxKhz &&
                !writeSysfs(QStringLiteral("scaling_min_freq"), targetMinKhz))
            return false;
        if (!writeSysfs(QStringLiteral("scaling_max_freq"), targetMaxKhz))
            return false;
        if (!writeSysfs(QStringLiteral("scaling_min_freq"), targetMinKhz))
            return false;

        const QStringList governors = readTextFile(
            policy.filePath(QStringLiteral("scaling_available_governors")))
            .split(QChar(' '), Qt::SkipEmptyParts);
        QString governor;
        if (governors.contains(QStringLiteral("ondemand")))
            governor = QStringLiteral("ondemand");
        else if (governors.contains(QStringLiteral("schedutil")))
            governor = QStringLiteral("schedutil");
        if (!governor.isEmpty()) {
            QFile governorFile(policy.filePath(QStringLiteral("scaling_governor")));
            if (governorFile.open(QIODevice::WriteOnly | QIODevice::Text))
                governorFile.write(governor.toUtf8());
        }
    }

    return true;
#endif
}

bool PerformanceManager::writeManagedBlock(const QVariantMap &configuration,
                                           QString *errorMessage)
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    Q_UNUSED(configuration)
    if (errorMessage) *errorMessage = QStringLiteral("Pi firmware overclock profiles are unavailable on Gemini.");
    return false;
#else
    const QString path = configPath();
    if (path.isEmpty()) {
        if (errorMessage) *errorMessage = QStringLiteral("Raspberry Pi config.txt was not found.");
        return false;
    }
    QFile input(path);
    if (!input.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (errorMessage) *errorMessage = input.errorString();
        return false;
    }
    QString text = QString::fromUtf8(input.readAll());
    input.close();

    const QRegularExpression blockRe(
        QStringLiteral("(?:^|\\n)%1[\\s\\S]*?%2(?:\\n|$)")
            .arg(QRegularExpression::escape(QString::fromLatin1(kBeginMarker)),
                 QRegularExpression::escape(QString::fromLatin1(kEndMarker))));
    text.remove(blockRe);
    while (text.endsWith(QStringLiteral("\n\n\n"))) text.chop(1);

    const QVariantMap c = normalizeConfiguration(configuration);
    if (!c.value(QStringLiteral("stock")).toBool()) {
        QStringList lines;
        lines << QString::fromLatin1(kBeginMarker)
              << QStringLiteral("# Managed only by NeutronOS Settings > Performance after explicit Apply.")
              << QStringLiteral("# PROFILE: %1").arg(c.value(QStringLiteral("profileName")).toString())
              << m_spec.filter
              << QStringLiteral("arm_boost=0")
              << QStringLiteral("arm_freq=%1").arg(c.value(QStringLiteral("cpuMaxMhz")).toInt())
              << QStringLiteral("arm_freq_min=%1").arg(c.value(QStringLiteral("cpuMinMhz")).toInt())
              << QStringLiteral("v3d_freq=%1").arg(c.value(QStringLiteral("gpuMhz")).toInt())
              << QStringLiteral("force_turbo=%1").arg(c.value(QStringLiteral("turbo")).toBool() ? 1 : 0)
              << QStringLiteral("initial_turbo=0")
              << QStringLiteral("[all]")
              << QString::fromLatin1(kEndMarker);
        if (!text.endsWith(QChar('\n'))) text += QChar('\n');
        text += QChar('\n') + lines.join(QChar('\n')) + QChar('\n');
    }

    if (!writeTextFileAtomically(path, text.toUtf8(), errorMessage))
        return false;
    const QString verify = readTextFile(path);
    if (!c.value(QStringLiteral("stock")).toBool() &&
        (!verify.contains(QString::fromLatin1(kBeginMarker)) ||
         !verify.contains(QStringLiteral("arm_freq=%1").arg(c.value(QStringLiteral("cpuMaxMhz")).toInt())))) {
        if (errorMessage) *errorMessage = QStringLiteral("The written performance block could not be verified.");
        return false;
    }
    return true;
#endif
}

QVariantMap PerformanceManager::result(bool ok, const QString &message,
                                       const QVariantMap &extra) const
{
    QVariantMap out = extra;
    out.insert(QStringLiteral("ok"), ok);
    out.insert(QStringLiteral("message"), message);
    return out;
}

QVariantMap PerformanceManager::applyConfiguration(const QVariantMap &configuration,
                                                   bool allowUnhealthyOverride)
{
    if (m_busy)
        return result(false, QStringLiteral("A performance operation is already running."));
    if (!m_available)
        return result(false, QStringLiteral("Performance configuration is unavailable on this device."));

    const QVariantMap assessment = evaluateConfiguration(configuration);
    if (!assessment.value(QStringLiteral("ok")).toBool())
        return result(false, assessment.value(QStringLiteral("errors")).toStringList().join(QStringLiteral(" ")), assessment);
    if (!assessment.value(QStringLiteral("healthOk")).toBool() && !allowUnhealthyOverride)
        return result(false, m_healthMessage, assessment);

    m_busy = true;
    m_lastMessage = QStringLiteral("Writing selected performance profile…");
    emit operationChanged();

    QString error;
    const QVariantMap normalized = normalizeConfiguration(configuration);
    const bool written = writeManagedBlock(normalized, &error);
    if (!written) {
        m_busy = false;
        m_lastMessage = error;
        emit operationChanged();
        return result(false, error, assessment);
    }

    m_currentConfiguration = normalized;
    m_busy = false;
    m_lastMessage = QStringLiteral("Performance profile applied. Rebooting to activate it.");
    emit configurationChanged();
    emit operationChanged();
    emit configurationApplied(normalized);

    QTimer::singleShot(900, qApp, []() {
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
    });

    QVariantMap extra = assessment;
    extra.insert(QStringLiteral("rebooting"), true);
    extra.insert(QStringLiteral("configuration"), normalized);
    return result(true, m_lastMessage, extra);
}
