#include "PowerModeManager.h"

#if defined(NEUTRONOS_PLATFORM_GEMINI)
#include "../platform/gemini/GeminiHardware.h"
#endif

#include "DeveloperModeManager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSaveFile>
#include <QSet>

#include <algorithm>

PowerModeManager::PowerModeManager(DeveloperModeManager *developerModeManager,
                                   QObject *parent)
    : QObject(parent)
    , m_developerModeManager(developerModeManager)
{
    if (m_developerModeManager) {
        connect(
            m_developerModeManager,
            &DeveloperModeManager::developerModeChanged,
            this,
            &PowerModeManager::handleDeveloperModeChanged
        );
    }

    const QStringList policies = policyDirectories();
    setAvailable(!policies.isEmpty());

    const QString persistedMode = loadPersistedMode();

    if (persistedMode == QStringLiteral("performance") &&
            developerModeEnabled()) {
        QString error;

        if (applyPerformance(&error)) {
            setMode(QStringLiteral("performance"));
            setStatus(QStringLiteral("Performance mode active"));
            return;
        }

        setStatus(
            QStringLiteral("Performance mode could not be restored"),
            error
        );
    }

    QString error;

    if (applyNormal(&error)) {
        setMode(QStringLiteral("normal"));
        savePersistedMode(QStringLiteral("normal"));
        setStatus(QStringLiteral("Normal mode active"));
    } else {
        setStatus(QStringLiteral("Normal mode could not be applied"), error);
    }
}

QString PowerModeManager::mode() const
{
    return m_mode;
}

QString PowerModeManager::displayName() const
{
    return performanceModeEnabled()
           ? QStringLiteral("Performance")
           : QStringLiteral("Normal");
}

QString PowerModeManager::iconName() const
{
    return performanceModeEnabled()
           ? QStringLiteral("speedometer")
           : QStringLiteral("balanced");
}

bool PowerModeManager::performanceModeEnabled() const
{
    return m_mode == QStringLiteral("performance");
}

bool PowerModeManager::normalModeEnabled() const
{
    return !performanceModeEnabled();
}

bool PowerModeManager::available() const
{
    return m_available;
}

QString PowerModeManager::lastError() const
{
    return m_lastError;
}

QString PowerModeManager::statusMessage() const
{
    return m_statusMessage;
}

int PowerModeManager::normalFrequencyCapMhz() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    quint64 maximum = 0;
    for (const QString &policy : policyDirectories()) {
        const quint64 value = hardwareMaximumKhz(policy);
        if (value) maximum = maximum ? qMin(maximum, value) : value;
    }
    return static_cast<int>(maximum / 1000ULL);
#else
    return static_cast<int>(kNormalMaxFrequencyKhz / 1000ULL);
#endif
}

QString PowerModeManager::stateFilePath() const
{
    return QStringLiteral(NEUTRONOS_STATE_DIR "/power_mode.json");
}

QStringList PowerModeManager::policyDirectories() const
{
    QStringList result;
    QSet<QString> seen;

    const QDir policyRoot(
        QStringLiteral("/sys/devices/system/cpu/cpufreq")
    );

    const QStringList policyNames = policyRoot.entryList(
        QStringList() << QStringLiteral("policy*"),
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::Name
    );

    for (const QString &name : policyNames) {
        const QString path = QFileInfo(
            policyRoot.filePath(name)
        ).canonicalFilePath();

        if (!path.isEmpty() && !seen.contains(path)) {
            seen.insert(path);
            result.append(path);
        }
    }

    if (!result.isEmpty())
        return result;

    const QDir cpuRoot(QStringLiteral("/sys/devices/system/cpu"));
    const QStringList cpuNames = cpuRoot.entryList(
        QStringList() << QStringLiteral("cpu[0-9]*"),
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::Name
    );

    for (const QString &name : cpuNames) {
        const QString candidate = cpuRoot.filePath(
            name + QStringLiteral("/cpufreq")
        );

        if (!QFileInfo::exists(candidate))
            continue;

        const QString path = QFileInfo(candidate).canonicalFilePath();

        if (!path.isEmpty() && !seen.contains(path)) {
            seen.insert(path);
            result.append(path);
        }
    }

    return result;
}

bool PowerModeManager::developerModeEnabled() const
{
    return m_developerModeManager &&
           m_developerModeManager->developerModeEnabled();
}

QString PowerModeManager::readTextFile(const QString &path) const
{
    QFile file(path);

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();

    return QString::fromUtf8(file.readAll()).trimmed();
}

quint64 PowerModeManager::readUnsignedFile(const QString &path) const
{
    bool ok = false;
    const quint64 value = readTextFile(path).toULongLong(&ok);
    return ok ? value : 0ULL;
}

bool PowerModeManager::writeTextFile(const QString &path,
                                     const QString &value,
                                     QString *errorMessage) const
{
    QFile file(path);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        if (path.startsWith(QStringLiteral("/sys/devices/system/cpu/cpufreq/policy"))) {
            QProcess helper;
            helper.start(QStringLiteral("sudo"),
                         {QStringLiteral("-n"),
                          QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                          QStringLiteral("write-cpufreq"), path, value});
            if (helper.waitForFinished(5000) && helper.exitCode() == 0)
                return true;
            if (errorMessage)
                *errorMessage = QString::fromUtf8(helper.readAllStandardError()).trimmed();
            return false;
        }
        if (errorMessage) {
            *errorMessage = QStringLiteral("Cannot open %1 for writing: %2")
                                .arg(path, file.errorString());
        }
        return false;
    }

    const QByteArray bytes = value.toUtf8();

    if (file.write(bytes) != bytes.size()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Could not write %1: %2")
                                .arg(path, file.errorString());
        }
        return false;
    }

    if (!file.flush()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Could not flush %1: %2")
                                .arg(path, file.errorString());
        }
        return false;
    }

    return true;
}

QStringList PowerModeManager::availableGovernors(
    const QString &policyDirectory
) const
{
    return readTextFile(
        QDir(policyDirectory).filePath(
            QStringLiteral("scaling_available_governors")
        )
    ).split(QChar(' '), Qt::SkipEmptyParts);
}

QString PowerModeManager::preferredNormalGovernor(
    const QString &policyDirectory
) const
{
    const QStringList governors = availableGovernors(policyDirectory);

#if defined(NEUTRONOS_PLATFORM_GEMINI)
    if (governors.contains(QStringLiteral("schedutil")))
        return QStringLiteral("schedutil");
    if (governors.contains(QStringLiteral("powersave")))
        return QStringLiteral("powersave");
#endif
    if (governors.contains(QStringLiteral("ondemand")))
        return QStringLiteral("ondemand");

    if (governors.contains(QStringLiteral("schedutil")))
        return QStringLiteral("schedutil");

    if (governors.contains(QStringLiteral("conservative")))
        return QStringLiteral("conservative");

    if (governors.contains(QStringLiteral("powersave")))
        return QStringLiteral("powersave");

    return readTextFile(
        QDir(policyDirectory).filePath(
            QStringLiteral("scaling_governor")
        )
    );
}

quint64 PowerModeManager::hardwareMaximumKhz(
    const QString &policyDirectory
) const
{
    const QDir dir(policyDirectory);

    quint64 value = readUnsignedFile(
        dir.filePath(QStringLiteral("cpuinfo_max_freq"))
    );

    if (value > 0ULL)
        return value;

    const QStringList available = readTextFile(
        dir.filePath(QStringLiteral("scaling_available_frequencies"))
    ).split(QChar(' '), Qt::SkipEmptyParts);

    for (const QString &entry : available) {
        bool ok = false;
        const quint64 frequency = entry.toULongLong(&ok);

        if (ok)
            value = std::max(value, frequency);
    }

    if (value > 0ULL)
        return value;

    return readUnsignedFile(
        dir.filePath(QStringLiteral("scaling_max_freq"))
    );
}

quint64 PowerModeManager::hardwareMinimumKhz(
    const QString &policyDirectory
) const
{
    const QDir dir(policyDirectory);

    quint64 value = readUnsignedFile(
        dir.filePath(QStringLiteral("cpuinfo_min_freq"))
    );

    if (value > 0ULL)
        return value;

    return readUnsignedFile(
        dir.filePath(QStringLiteral("scaling_min_freq"))
    );
}


bool PowerModeManager::managedPerformanceProfileActive() const
{
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    return false;
#else
    const QStringList candidates = {
        QStringLiteral("/boot/firmware/config.txt"),
        QStringLiteral("/boot/config.txt")
    };

    for (const QString &path : candidates) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;

        const QString text = QString::fromUtf8(file.readAll());
        const int begin = text.indexOf(QStringLiteral("# BEGIN NEUTRONOS PERFORMANCE PROFILE"));
        const int end = text.indexOf(QStringLiteral("# END NEUTRONOS PERFORMANCE PROFILE"));
        if (begin >= 0 && end > begin &&
                text.mid(begin, end - begin).contains(QStringLiteral("arm_freq=")))
            return true;
    }

    return false;
#endif
}

bool PowerModeManager::applyPerformance(QString *errorMessage)
{
    const QStringList policies = policyDirectories();

    if (policies.isEmpty()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("CPU frequency policies were not found.");
        return false;
    }

    for (const QString &policy : policies) {
        const QDir dir(policy);
        const QStringList governors = availableGovernors(policy);

        if (!governors.contains(QStringLiteral("performance"))) {
            if (errorMessage) {
                *errorMessage = QStringLiteral(
                    "The performance governor is unavailable for %1."
                ).arg(policy);
            }
            return false;
        }

        const quint64 maximumKhz = hardwareMaximumKhz(policy);

        if (maximumKhz == 0ULL) {
            if (errorMessage) {
                *errorMessage = QStringLiteral(
                    "The hardware maximum frequency is unavailable for %1."
                ).arg(policy);
            }
            return false;
        }

        QString writeError;

        if (!writeTextFile(
                dir.filePath(QStringLiteral("scaling_max_freq")),
                QString::number(maximumKhz),
                &writeError)) {
            if (errorMessage)
                *errorMessage = writeError;
            return false;
        }

        if (!writeTextFile(
                dir.filePath(QStringLiteral("scaling_governor")),
                QStringLiteral("performance"),
                &writeError)) {
            if (errorMessage)
                *errorMessage = writeError;
            return false;
        }
    }

    return true;
}

bool PowerModeManager::applyNormal(QString *errorMessage)
{
    const QStringList policies = policyDirectories();

    if (policies.isEmpty()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("CPU frequency policies were not found.");
        return false;
    }

    for (const QString &policy : policies) {
        const QDir dir(policy);
        const quint64 hardwareMaximum = hardwareMaximumKhz(policy);

        if (hardwareMaximum == 0ULL) {
            if (errorMessage) {
                *errorMessage = QStringLiteral(
                    "The hardware maximum frequency is unavailable for %1."
                ).arg(policy);
            }
            return false;
        }

        /* A saved NeutronOS Performance profile changes the firmware
           hardware maximum after reboot. Do not immediately force it back to
           1.5 GHz when NeutronShell starts. Stock systems retain the original
           Normal-mode 1.5 GHz ceiling. */
#if defined(NEUTRONOS_PLATFORM_GEMINI)
        const quint64 normalMaximum = hardwareMaximum;
#else
        const quint64 normalMaximum = managedPerformanceProfileActive()
            ? hardwareMaximum
            : std::min(hardwareMaximum, kNormalMaxFrequencyKhz);
#endif

        const quint64 currentMinimum = readUnsignedFile(
            dir.filePath(QStringLiteral("scaling_min_freq"))
        );

        QString writeError;

        if (currentMinimum > normalMaximum) {
            quint64 safeMinimum = hardwareMinimumKhz(policy);

            if (safeMinimum == 0ULL || safeMinimum > normalMaximum)
                safeMinimum = normalMaximum;

            if (!writeTextFile(
                    dir.filePath(QStringLiteral("scaling_min_freq")),
                    QString::number(safeMinimum),
                    &writeError)) {
                if (errorMessage)
                    *errorMessage = writeError;
                return false;
            }
        }

        if (!writeTextFile(
                dir.filePath(QStringLiteral("scaling_max_freq")),
                QString::number(normalMaximum),
                &writeError)) {
            if (errorMessage)
                *errorMessage = writeError;
            return false;
        }

        const QString governor = preferredNormalGovernor(policy);

        if (governor.isEmpty()) {
            if (errorMessage) {
                *errorMessage = QStringLiteral(
                    "No normal CPU governor is available for %1."
                ).arg(policy);
            }
            return false;
        }

        if (!writeTextFile(
                dir.filePath(QStringLiteral("scaling_governor")),
                governor,
                &writeError)) {
            if (errorMessage)
                *errorMessage = writeError;
            return false;
        }
    }

    return true;
}

bool PowerModeManager::savePersistedMode(const QString &mode,
                                         QString *errorMessage) const
{
    QDir stateDirectory(QStringLiteral(NEUTRONOS_STATE_DIR));

    if (!stateDirectory.exists() &&
            !QDir().mkpath(stateDirectory.absolutePath())) {
        if (errorMessage) {
            *errorMessage = QStringLiteral(
                "Could not create the NeutronOS state directory."
            );
        }
        return false;
    }

    QJsonObject object;
    object.insert(QStringLiteral("version"), 1);
    object.insert(QStringLiteral("mode"), mode);
    object.insert(
        QStringLiteral("updatedAtUtc"),
        QDateTime::currentDateTimeUtc().toString(Qt::ISODate)
    );

    QSaveFile file(stateFilePath());

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Could not open %1: %2")
                                .arg(stateFilePath(), file.errorString());
        }
        return false;
    }

    const QByteArray data = QJsonDocument(object).toJson(
        QJsonDocument::Indented
    );

    if (file.write(data) != data.size()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Could not write %1: %2")
                                .arg(stateFilePath(), file.errorString());
        }
        file.cancelWriting();
        return false;
    }

    if (!file.commit()) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Could not commit %1: %2")
                                .arg(stateFilePath(), file.errorString());
        }
        return false;
    }

    QFile::setPermissions(
        stateFilePath(),
        QFileDevice::ReadOwner | QFileDevice::WriteOwner
    );

    return true;
}

QString PowerModeManager::loadPersistedMode() const
{
    QFile file(stateFilePath());

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QStringLiteral("normal");

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());

    if (!document.isObject())
        return QStringLiteral("normal");

    const QString value = document.object()
                              .value(QStringLiteral("mode"))
                              .toString()
                              .trimmed()
                              .toLower();

    return value == QStringLiteral("performance")
           ? QStringLiteral("performance")
           : QStringLiteral("normal");
}

void PowerModeManager::setMode(const QString &mode)
{
    const QString normalized = mode == QStringLiteral("performance")
                               ? QStringLiteral("performance")
                               : QStringLiteral("normal");

    if (m_mode == normalized)
        return;

    m_mode = normalized;
    emit modeChanged();
}

void PowerModeManager::setAvailable(bool available)
{
    if (m_available == available)
        return;

    m_available = available;
    emit statusChanged();
}

void PowerModeManager::setStatus(const QString &statusMessage,
                                 const QString &errorMessage)
{
    const QString cleanStatus = statusMessage.trimmed();
    const QString cleanError = errorMessage.trimmed();

    if (m_statusMessage == cleanStatus && m_lastError == cleanError)
        return;

    m_statusMessage = cleanStatus;
    m_lastError = cleanError;
    emit statusChanged();
}

QVariantMap PowerModeManager::result(bool ok, const QString &message) const
{
    QVariantMap map;
    map.insert(QStringLiteral("ok"), ok);
    map.insert(QStringLiteral("message"), message);
    map.insert(QStringLiteral("mode"), m_mode);
    map.insert(QStringLiteral("performanceModeEnabled"), performanceModeEnabled());
    map.insert(QStringLiteral("developerModeRequired"), !developerModeEnabled());
    map.insert(QStringLiteral("error"), m_lastError);
    return map;
}

void PowerModeManager::refresh()
{
    setAvailable(!policyDirectories().isEmpty());

    if (!developerModeEnabled() && performanceModeEnabled()) {
        setNormalMode();
        return;
    }

    emit modeChanged();
    emit statusChanged();
}

QVariantMap PowerModeManager::togglePerformanceMode()
{
    return setPerformanceMode(!performanceModeEnabled());
}

QVariantMap PowerModeManager::setPerformanceMode(bool enabled)
{
    if (!enabled)
        return setNormalMode();

    if (!developerModeEnabled()) {
        const QString message = QStringLiteral(
            "Enable Developer Mode first to use Performance Mode."
        );
        setStatus(message, message);
        emit operationCompleted(false, message);
        return result(false, message);
    }

    if (!available()) {
        const QString message = QStringLiteral(
            "CPU frequency control is unavailable on this system."
        );
        setStatus(message, message);
        emit operationCompleted(false, message);
        return result(false, message);
    }

    QString error;

    if (!applyPerformance(&error)) {
        const QString message = error.isEmpty()
                                ? QStringLiteral("Performance Mode could not be enabled.")
                                : error;
        setStatus(QStringLiteral("Performance Mode failed"), message);
        emit operationCompleted(false, message);
        return result(false, message);
    }

    setMode(QStringLiteral("performance"));

    QString persistenceError;
    savePersistedMode(QStringLiteral("performance"), &persistenceError);

    const QString message = QStringLiteral(
        "Performance Mode enabled: hardware CPU maximum and performance governor active."
    );

    setStatus(message, persistenceError);
    emit operationCompleted(true, message);
    return result(true, message);
}

QVariantMap PowerModeManager::setNormalMode()
{
    if (!available()) {
        const QString message = QStringLiteral(
            "CPU frequency control is unavailable on this system."
        );
        setStatus(message, message);
        emit operationCompleted(false, message);
        return result(false, message);
    }

    QString error;

    if (!applyNormal(&error)) {
        const QString message = error.isEmpty()
                                ? QStringLiteral("Normal Mode could not be restored.")
                                : error;
        setStatus(QStringLiteral("Normal Mode failed"), message);
        emit operationCompleted(false, message);
        return result(false, message);
    }

    setMode(QStringLiteral("normal"));

    QString persistenceError;
    savePersistedMode(QStringLiteral("normal"), &persistenceError);

#if defined(NEUTRONOS_PLATFORM_GEMINI)
    const QString message = QStringLiteral("Normal Mode restored: supported hardware maximum and normal CPU governor active.");
#else
    const QString message = managedPerformanceProfileActive()
        ? QStringLiteral("Normal governor restored while preserving the applied NeutronOS Performance profile maximum.")
        : QStringLiteral("Normal Mode restored: CPU capped at 1.5 GHz with the normal governor.");
#endif

    setStatus(message, persistenceError);
    emit operationCompleted(true, message);
    return result(true, message);
}

void PowerModeManager::handleDeveloperModeChanged()
{
    if (!developerModeEnabled() && performanceModeEnabled())
        setNormalMode();

    emit statusChanged();
}
