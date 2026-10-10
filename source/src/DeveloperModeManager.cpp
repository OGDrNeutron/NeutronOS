#include "DeveloperModeManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QCryptographicHash>
#include <QMessageAuthenticationCode>
#include <QRegularExpression>
#include <QDateTime>
#include <QDebug>

#include <sodium.h>

#ifdef Q_OS_LINUX
#include <sys/stat.h>
#include <unistd.h>
#endif

/*
    ============================================================
                            CONSTRUCTION
    ============================================================
*/

DeveloperModeManager::DeveloperModeManager(QObject *parent)
    : QObject(parent)
{
    m_monotonicClock.start();

    ensureStateDirectories();
    ensureSodiumReady();
    migrateLegacyDeveloperState();

    loadState();
    updateLockoutState();

    m_lockoutRefreshTimer.setInterval(1000);
    m_lockoutRefreshTimer.setSingleShot(false);

    connect(
        &m_lockoutRefreshTimer,
        &QTimer::timeout,
        this,
        &DeveloperModeManager::updateLockoutState
    );

    m_lockoutRefreshTimer.start();
}

/*
    ============================================================
                            PROPERTIES
    ============================================================
*/

bool DeveloperModeManager::developerModeEnabled() const
{
    return m_developerModeEnabled;
}

bool DeveloperModeManager::developerModeConfigured() const
{
    return m_developerModeConfigured;
}

bool DeveloperModeManager::setupRequired() const
{
    return !m_developerModeConfigured;
}

bool DeveloperModeManager::lockedOut() const
{
    return m_lockedOut;
}

int DeveloperModeManager::failedAttempts() const
{
    return m_failedAttempts;
}

int DeveloperModeManager::secondsRemaining() const
{
    return m_secondsRemaining;
}

int DeveloperModeManager::lockoutDelaySeconds() const
{
    return m_lockoutDelaySeconds;
}

int DeveloperModeManager::lockoutLevel() const
{
    return m_lockoutLevel;
}

QString DeveloperModeManager::securityDirPath() const
{
    return QStringLiteral(NEUTRONOS_SECURITY_STATE_DIR);
}

QString DeveloperModeManager::stateDirPath() const
{
    return QStringLiteral(NEUTRONOS_STATE_DIR);
}

QString DeveloperModeManager::kdfScheme() const
{
    return QStringLiteral("argon2id/libsodium");
}

QString DeveloperModeManager::lastError() const
{
    return m_lastError;
}

QString DeveloperModeManager::lastFailureReason() const
{
    return m_lastFailureReason;
}

QString DeveloperModeManager::buttonState() const
{
    if (m_lockedOut || !m_lastError.isEmpty())
        return QStringLiteral("red");

    if (m_developerModeEnabled)
        return QStringLiteral("green");

    return QString();
}


QString DeveloperModeManager::status() const
{
    if (m_lockedOut) {
        if (m_secondsRemaining > 0) {
            return QStringLiteral("locked:%1").arg(m_secondsRemaining);
        }

        return QStringLiteral("locked");
    }

    if (!m_developerModeConfigured)
        return QStringLiteral("setup-required");

    if (m_developerModeEnabled)
        return QStringLiteral("enabled");

    return QStringLiteral("disabled");
}

/*
    ============================================================
                            COMPATIBILITY API
    ============================================================
*/

bool DeveloperModeManager::isEnabled() const
{
    return developerModeEnabled();
}

bool DeveloperModeManager::isConfigured() const
{
    return developerModeConfigured();
}

bool DeveloperModeManager::isSetupRequired() const
{
    return setupRequired();
}

void DeveloperModeManager::refresh()
{
    loadState();
    updateLockoutState();

    emit developerModeChanged();
    emit enabledChanged();
    emit configuredChanged();
    emit lockoutChanged();
}

/*
    ============================================================
                                PATHS
    ============================================================
*/

QString DeveloperModeManager::neutronRootPath() const
{
    const QByteArray envRoot = qgetenv("NEUTRONOS_ROOT");

    if (!envRoot.isEmpty()) {
        const QString envPath = QDir::cleanPath(QString::fromLocal8Bit(envRoot));

        if (QFileInfo::exists(envPath + QStringLiteral("/qml/Main.qml")))
            return envPath;
    }

    const QString homeRoot = QDir::cleanPath(QDir::homePath() + QStringLiteral("/NeutronOS"));

    if (QFileInfo::exists(homeRoot + QStringLiteral("/qml/Main.qml")))
        return homeRoot;

    const QString currentRoot = QDir::cleanPath(QDir::currentPath());

    if (QFileInfo::exists(currentRoot + QStringLiteral("/qml/Main.qml")))
        return currentRoot;

    const QString appDir = QDir::cleanPath(QCoreApplication::applicationDirPath());
    const QString appParent = QDir::cleanPath(QDir(appDir).absoluteFilePath(QStringLiteral("..")));

    if (QFileInfo::exists(appParent + QStringLiteral("/qml/Main.qml")))
        return appParent;

    return homeRoot;
}

QString DeveloperModeManager::legacySecurityDirPath() const
{
    return neutronRootPath() + QStringLiteral("/state/security");
}

QString DeveloperModeManager::legacyStateDirPath() const
{
    return neutronRootPath() + QStringLiteral("/state");
}

QString DeveloperModeManager::hashFilePath() const
{
    return securityDirPath() + QStringLiteral("/developer_mode.hash");
}

QString DeveloperModeManager::enabledMarkerPath() const
{
    return stateDirPath() + QStringLiteral("/developer_mode.enabled");
}

QString DeveloperModeManager::lockoutStateFilePath() const
{
    return securityDirPath() + QStringLiteral("/developer_mode_lockout.json");
}

QString DeveloperModeManager::legacyHashFilePath() const
{
    return legacySecurityDirPath() + QStringLiteral("/developer_mode.hash");
}

QString DeveloperModeManager::legacyEnabledMarkerPath() const
{
    return legacyStateDirPath() + QStringLiteral("/developer_mode.enabled");
}

void DeveloperModeManager::ensureStateDirectories() const
{
    ensureSecureDirectory(stateDirPath());
    ensureSecureDirectory(securityDirPath());

    securityDirectoryLooksSafe();
}

void DeveloperModeManager::ensureSecureDirectory(const QString &path) const
{
    if (path.trimmed().isEmpty())
        return;

    /*
       Authoritative state ownership is prepared by neutronos-state-setup.
       The unprivileged shell must never chown/chmod these directories.
    */
    const QFileInfo info(path);
    if (!info.exists() || !info.isDir())
        qWarning() << "DeveloperModeManager required state directory is missing:" << path;
}

bool DeveloperModeManager::securityDirectoryLooksSafe() const
{
#ifdef Q_OS_LINUX
    struct stat st;

    const QByteArray pathBytes = securityDirPath().toLocal8Bit();

    if (::stat(pathBytes.constData(), &st) != 0) {
        qWarning() << "DeveloperModeManager could not stat security directory:"
                   << securityDirPath();
        return false;
    }

    const bool ownerExpected = st.st_uid == ::geteuid();
    const bool groupAccess = (st.st_mode & S_IRWXG) != 0;
    const bool worldAccess = (st.st_mode & S_IRWXO) != 0;

    if (!ownerExpected) {
        qWarning() << "DeveloperModeManager security directory owner does not match runtime user:"
                   << securityDirPath();
    }

    if (groupAccess || worldAccess) {
        qWarning() << "DeveloperModeManager security directory permissions are too open:"
                   << securityDirPath();
    }

    return ownerExpected && !groupAccess && !worldAccess;
#else
    return true;
#endif
}

/*
    ============================================================
                                FILE I/O
    ============================================================
*/

QByteArray DeveloperModeManager::readFile(const QString &path) const
{
    QFile file(path);

    if (!file.open(QIODevice::ReadOnly))
        return {};

    const QByteArray data = file.readAll();

    file.close();

    return data;
}

bool DeveloperModeManager::writeSecureBytesFile(const QString &path,
                                                const QByteArray &data) const
{
    ensureStateDirectories();

    const QFileInfo targetInfo(path);
    const QString parentPath = targetInfo.absolutePath();

    if (!QDir(parentPath).exists() && !QDir().mkpath(parentPath)) {
        qWarning() << "DeveloperModeManager could not create parent directory:"
                   << parentPath;
        return false;
    }

    /*
        QSaveFile replaces the older hand-rolled .tmp + remove + rename flow.
        The old flow could leave a stale temporary file or fail between remove
        and rename, which surfaced in QML as "code cannot be saved".

        Direct-write fallback is enabled for filesystems that do not support an
        atomic rename, while normal filesystems still receive an atomic commit.
    */
    QSaveFile file(path);
    file.setDirectWriteFallback(true);

    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "DeveloperModeManager failed to open secure file:"
                   << path
                   << file.errorString();
        return false;
    }

    const qint64 written = file.write(data);

    if (written != data.size()) {
        qWarning() << "DeveloperModeManager failed to fully write secure file:"
                   << path
                   << "written=" << written
                   << "expected=" << data.size()
                   << file.errorString();
        file.cancelWriting();
        return false;
    }

    if (!file.commit()) {
        qWarning() << "DeveloperModeManager failed to commit secure file:"
                   << path
                   << file.errorString();
        return false;
    }

    const bool permissionsOk = setOwnerOnlyPermissions(path, false);
    const bool ownershipOk = setOwnerRootOnly(path);

    if (!permissionsOk || !ownershipOk) {
        qWarning() << "DeveloperModeManager could not secure credential file:"
                   << path;
        QFile::remove(path);
        return false;
    }

    /* Verify the bytes that will be read back by the enable step. */
    QFile verificationFile(path);

    if (!verificationFile.open(QIODevice::ReadOnly)) {
        qWarning() << "DeveloperModeManager could not reopen secure file:"
                   << path
                   << verificationFile.errorString();
        return false;
    }

    const QByteArray stored = verificationFile.readAll();
    verificationFile.close();

    if (stored != data) {
        qWarning() << "DeveloperModeManager secure-file verification failed:"
                   << path;
        QFile::remove(path);
        return false;
    }

    return true;
}

bool DeveloperModeManager::writeSecureJsonFile(const QString &path,
                                               const QByteArray &json) const
{
    return writeSecureBytesFile(path, json);
}

bool DeveloperModeManager::removeSecureFile(const QString &path) const
{
    if (!QFileInfo::exists(path))
        return true;

    if (!QFile::remove(path)) {
        qWarning() << "DeveloperModeManager failed to remove secure file:" << path;
        return false;
    }

    return true;
}

bool DeveloperModeManager::setOwnerRootOnly(const QString &path) const
{
#ifdef Q_OS_LINUX
    /* Ownership is assigned by neutronos-state-setup before the shell starts. */
    struct stat st;
    const QByteArray bytes = path.toLocal8Bit();
    if (::stat(bytes.constData(), &st) != 0)
        return false;
    return st.st_uid == ::geteuid();
#else
    Q_UNUSED(path)
    return true;
#endif
}

bool DeveloperModeManager::setOwnerOnlyPermissions(const QString &path,
                                                   bool executable) const
{
    QFile::Permissions permissions =
            QFileDevice::ReadOwner |
            QFileDevice::WriteOwner;

    if (executable)
        permissions |= QFileDevice::ExeOwner;

    const bool qtOk = QFile::setPermissions(path, permissions);

#ifdef Q_OS_LINUX
    const QByteArray bytes = path.toLocal8Bit();
    const mode_t mode = executable ? static_cast<mode_t>(0700) : static_cast<mode_t>(0600);

    if (::chmod(bytes.constData(), mode) != 0) {
        qWarning() << "DeveloperModeManager failed to chmod path:" << path;
        return false;
    }
#endif

    return qtOk;
}

/*
    ============================================================
                            LOAD / SAVE
    ============================================================
*/

void DeveloperModeManager::loadState()
{
    ensureStateDirectories();
    loadConfiguredState();
    loadEnabledState();

    const QByteArray data = readFile(lockoutStateFilePath());

    if (data.isEmpty()) {
        m_failedAttempts = 0;
        m_highThreatAttempts = 0;
        m_lockedOut = false;
        m_secondsRemaining = 0;
        m_lockoutDelaySeconds = 0;
        m_lockoutLevel = 0;
        m_lastFailureReason.clear();
        m_lastHighThreatReason.clear();

        emit lockoutChanged();
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(data);

    if (!doc.isObject()) {
        qWarning() << "DeveloperModeManager lockout state file is invalid JSON.";
        emit lockoutChanged();
        return;
    }

    const QJsonObject obj = doc.object();

    m_stateVersion = obj.value(QStringLiteral("version")).toInt(2);
    m_failedAttempts = qMax(0, obj.value(QStringLiteral("failedAttempts")).toInt(0));
    m_highThreatAttempts = qMax(0, obj.value(QStringLiteral("highThreatAttempts")).toInt(0));
    m_lastFailureReason = obj.value(QStringLiteral("lastFailureReason")).toString();
    m_lastHighThreatReason = obj.value(QStringLiteral("lastHighThreatReason")).toString();

    m_lockoutLevel = levelForFailedAttempts(m_failedAttempts);
    m_lockoutDelaySeconds = delayForFailedAttempts(m_failedAttempts);

    const bool persistedLockedOut = obj.value(QStringLiteral("lockedOut")).toBool(false);

    /*
        No wall-clock timestamp is trusted as unlock authority.

        If Developer Mode was locked out when the process stopped, the
        deterministic delay is re-applied from the persistent failed-attempt
        counter.
    */
    if (persistedLockedOut && m_failedAttempts > 0) {
        startLockout(qMax(1, m_lockoutDelaySeconds),
                     QStringLiteral("restored persistent developer lockout"));
        return;
    }

    m_lockedOut = false;
    m_secondsRemaining = 0;
    m_lockoutUntilMonotonicMs = 0;

    emit lockoutChanged();
}

void DeveloperModeManager::saveLockoutState()
{
    QJsonObject obj;

    obj[QStringLiteral("version")] = 2;
    obj[QStringLiteral("securityDir")] = securityDirPath();
    obj[QStringLiteral("stateDir")] = stateDirPath();
    obj[QStringLiteral("kdf")] = QStringLiteral("argon2id/libsodium");

    obj[QStringLiteral("failedAttempts")] = m_failedAttempts;
    obj[QStringLiteral("highThreatAttempts")] = m_highThreatAttempts;
    obj[QStringLiteral("lockedOut")] = m_lockedOut;
    obj[QStringLiteral("secondsRemaining")] = m_secondsRemaining;
    obj[QStringLiteral("lockoutDelaySeconds")] = m_lockoutDelaySeconds;
    obj[QStringLiteral("lockoutLevel")] = m_lockoutLevel;

    /*
        Diagnostic only. Never used as the unlock condition.
    */
    obj[QStringLiteral("lastStateWriteUtc")] =
            QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    obj[QStringLiteral("lastFailureReason")] = m_lastFailureReason;
    obj[QStringLiteral("lastHighThreatReason")] = m_lastHighThreatReason;

    writeSecureJsonFile(
        lockoutStateFilePath(),
        QJsonDocument(obj).toJson(QJsonDocument::Indented)
    );
}

void DeveloperModeManager::loadEnabledState()
{
    const bool enabled = QFileInfo::exists(enabledMarkerPath());

    setDeveloperModeEnabled(enabled);
}

void DeveloperModeManager::saveEnabledState(bool enabled)
{
    if (enabled) {
        const QByteArray marker =
                QByteArray("enabled\n") +
                QByteArray("stateDir=") +
                stateDirPath().toUtf8() +
                QByteArray("\n");

        if (!writeSecureBytesFile(enabledMarkerPath(), marker)) {
            setLastError(QStringLiteral("Failed to write Developer Mode enabled marker."));
            setDeveloperModeEnabled(false);
            return;
        }

        setDeveloperModeEnabled(true);
        return;
    }

    removeSecureFile(enabledMarkerPath());
    setDeveloperModeEnabled(false);
}

void DeveloperModeManager::loadConfiguredState()
{
    setDeveloperModeConfigured(QFileInfo::exists(hashFilePath()));
}

/*
    ============================================================
                            SETTERS
    ============================================================
*/

void DeveloperModeManager::setDeveloperModeEnabled(bool enabled)
{
    if (m_developerModeEnabled == enabled)
        return;

    m_developerModeEnabled = enabled;

    emit developerModeChanged();
    emit enabledChanged();
    emit buttonStateChanged();

    if (enabled)
        emit developerModeEnabledChanged();
    else
        emit developerModeDisabledChanged();
}

void DeveloperModeManager::setDeveloperModeConfigured(bool configured)
{
    if (m_developerModeConfigured == configured)
        return;

    m_developerModeConfigured = configured;

    emit developerModeChanged();
    emit configuredChanged();
}

void DeveloperModeManager::setLastError(const QString &errorText)
{
    const QString clean = errorText.trimmed();

    if (m_lastError == clean)
        return;

    m_lastError = clean;
    emit developerModeChanged();
    emit errorChanged();
    emit buttonStateChanged();
}

/*
    ============================================================
                            LOCKOUTS
    ============================================================
*/

int DeveloperModeManager::delayForFailedAttempts(int attempts) const
{
    if (attempts <= 0)
        return 0;

    if (attempts == 1)
        return 5;

    if (attempts == 2)
        return 30;

    if (attempts == 3)
        return 5 * 60;

    if (attempts == 4)
        return 15 * 60;

    return m_maxLockoutSeconds;
}

int DeveloperModeManager::levelForFailedAttempts(int attempts) const
{
    if (attempts <= 0)
        return 0;

    return qMin(5, attempts);
}

void DeveloperModeManager::updateLockoutState()
{
    const bool wasLockedOut = m_lockedOut;

    if (!m_lockedOut) {
        m_secondsRemaining = 0;
        m_lockoutDelaySeconds = delayForFailedAttempts(m_failedAttempts);
        m_lockoutLevel = levelForFailedAttempts(m_failedAttempts);
        return;
    }

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    const qint64 nowMs = m_monotonicClock.elapsed();
    const qint64 remainingMs = m_lockoutUntilMonotonicMs - nowMs;

    if (remainingMs > 0) {
        m_secondsRemaining = static_cast<int>((remainingMs + 999) / 1000);
        emit lockoutChanged();
        return;
    }

    /*
        Lockout window ended.

        The persistent failed-attempt counter remains. Only a successful
        Developer Mode verification or admin reset clears it.
    */
    m_lockedOut = false;
    m_secondsRemaining = 0;
    m_lockoutUntilMonotonicMs = 0;
    m_lockoutDelaySeconds = delayForFailedAttempts(m_failedAttempts);
    m_lockoutLevel = levelForFailedAttempts(m_failedAttempts);

    saveLockoutState();

    if (wasLockedOut)
        emit lockoutCleared();

    emit lockoutChanged();
}

void DeveloperModeManager::startLockoutForCurrentFailureCount(const QString &reason)
{
    const int delay = delayForFailedAttempts(m_failedAttempts);

    if (delay <= 0)
        return;

    startLockout(delay, reason);
}

void DeveloperModeManager::startLockout(int seconds, const QString &reason)
{
    const int safeSeconds = qBound(1, seconds, m_maxLockoutSeconds);

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    m_lockoutDelaySeconds = safeSeconds;
    m_lockoutLevel = levelForFailedAttempts(m_failedAttempts);
    m_secondsRemaining = safeSeconds;
    m_lockedOut = true;

    m_lockoutUntilMonotonicMs =
            m_monotonicClock.elapsed() + static_cast<qint64>(safeSeconds) * 1000;

    if (!reason.trimmed().isEmpty())
        m_lastFailureReason = reason.trimmed().toLower();

    saveLockoutState();

    emit lockoutStarted();
    emit lockoutChanged();
}

bool DeveloperModeManager::failureCooldownActive() const
{
    if (!m_monotonicClock.isValid() || m_lastFailedAttemptMonotonicMs < 0)
        return false;

    return m_monotonicClock.elapsed() - m_lastFailedAttemptMonotonicMs <
            m_failedAttemptCooldownMs;
}

bool DeveloperModeManager::highThreatCooldownActive() const
{
    if (!m_monotonicClock.isValid() || m_lastHighThreatMonotonicMs < 0)
        return false;

    return m_monotonicClock.elapsed() - m_lastHighThreatMonotonicMs <
            m_highThreatCooldownMs;
}

bool DeveloperModeManager::registerFailedAttempt()
{
    return registerFailedAttemptWithReason(QStringLiteral("developer credential failed"));
}

bool DeveloperModeManager::registerFailedAttemptWithReason(const QString &reason)
{
    updateLockoutState();

    if (m_lockedOut)
        return true;

    const QString cleanReason = reason.trimmed().toLower();

    /*
        UI-only events must never count as security failures.
    */
    if (cleanReason.contains(QStringLiteral("motion")) ||
            cleanReason.contains(QStringLiteral("tilt")) ||
            cleanReason.contains(QStringLiteral("gyro")) ||
            cleanReason.contains(QStringLiteral("sensor")) ||
            cleanReason.contains(QStringLiteral("empty")) ||
            cleanReason.contains(QStringLiteral("visual"))) {
        return false;
    }

    if (failureCooldownActive())
        return false;

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    m_lastFailedAttemptMonotonicMs = m_monotonicClock.elapsed();
    m_lastFailureReason = cleanReason.isEmpty()
                          ? QStringLiteral("developer credential failed")
                          : cleanReason;

    m_failedAttempts += 1;

    startLockoutForCurrentFailureCount(m_lastFailureReason);

    return m_lockedOut;
}

void DeveloperModeManager::registerHighThreat()
{
    registerHighThreatWithReason(QStringLiteral("developer high threat"));
}

void DeveloperModeManager::registerHighThreatWithReason(const QString &reason)
{
    updateLockoutState();

    if (m_lockedOut)
        return;

    const QString cleanReason = reason.trimmed().toLower();

    if (cleanReason.contains(QStringLiteral("motion")) ||
            cleanReason.contains(QStringLiteral("tilt")) ||
            cleanReason.contains(QStringLiteral("gyro")) ||
            cleanReason.contains(QStringLiteral("sensor")) ||
            cleanReason.contains(QStringLiteral("empty")) ||
            cleanReason.contains(QStringLiteral("visual"))) {
        return;
    }

    if (highThreatCooldownActive())
        return;

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    m_lastHighThreatMonotonicMs = m_monotonicClock.elapsed();
    m_lastHighThreatReason = cleanReason.isEmpty()
                             ? QStringLiteral("developer high threat")
                             : cleanReason;

    m_highThreatAttempts += 1;
    m_failedAttempts += 2;

    const int deterministicDelay = delayForFailedAttempts(m_failedAttempts);
    const int threatDelay = qMax(5 * 60, deterministicDelay);

    startLockout(qMin(threatDelay, m_maxLockoutSeconds), m_lastHighThreatReason);
}

void DeveloperModeManager::registerSuccess()
{
    const bool wasLockedOut = m_lockedOut;

    m_failedAttempts = 0;
    m_highThreatAttempts = 0;

    m_lockedOut = false;
    m_secondsRemaining = 0;
    m_lockoutDelaySeconds = 0;
    m_lockoutLevel = 0;
    m_lockoutUntilMonotonicMs = 0;

    m_lastFailedAttemptMonotonicMs = -1;
    m_lastHighThreatMonotonicMs = -1;

    m_lastFailureReason.clear();
    m_lastHighThreatReason.clear();

    saveLockoutState();

    if (wasLockedOut)
        emit lockoutCleared();

    emit lockoutChanged();
}

void DeveloperModeManager::clearLockout()
{
    registerSuccess();
}

/*
    ============================================================
                        CREDENTIAL NORMALIZATION
    ============================================================
*/

QStringList DeveloperModeManager::tokenizeCredential(const QString &credential) const
{
    QString text = credential.trimmed().toUpper();

    text.replace(QStringLiteral(" "), QStringLiteral(""));
    text.replace(QStringLiteral("-"), QStringLiteral(""));
    text.replace(QStringLiteral("_"), QStringLiteral(""));
    text.replace(QStringLiteral(","), QStringLiteral(""));
    text.replace(QStringLiteral("|"), QStringLiteral(""));
    text.replace(QStringLiteral(">"), QStringLiteral(""));

    QStringList tokens;

    const QStringList knownTokens = {
        QStringLiteral("TRIANGLE"),
        QStringLiteral("SQUARE"),
        QStringLiteral("SELECT"),
        QStringLiteral("SYSTEM"),
        QStringLiteral("START"),
        QStringLiteral("OPTIONS"),
        QStringLiteral("MENU"),
        QStringLiteral("HOME"),
        QStringLiteral("PS"),
        QStringLiteral("L1"),
        QStringLiteral("R1"),
        QStringLiteral("L2"),
        QStringLiteral("R2"),
        QStringLiteral("L3"),
        QStringLiteral("R3"),
        QStringLiteral("UP"),
        QStringLiteral("DOWN"),
        QStringLiteral("LEFT"),
        QStringLiteral("RIGHT"),
        QStringLiteral("CROSS"),
        QStringLiteral("CIRCLE"),
        QStringLiteral("PRIMARY"),
        QStringLiteral("CANCEL"),
        QStringLiteral("CONTEXT"),
        QStringLiteral("SECONDARY"),
        QStringLiteral("X"),
        QStringLiteral("O"),
        QStringLiteral("U"),
        QStringLiteral("D"),
        QStringLiteral("L"),
        QStringLiteral("R")
    };

    while (!text.isEmpty()) {
        bool matched = false;

        for (const QString &token : knownTokens) {
            if (!text.startsWith(token))
                continue;

            QString canonical = token;

            if (canonical == QStringLiteral("UP"))
                canonical = QStringLiteral("U");
            else if (canonical == QStringLiteral("DOWN"))
                canonical = QStringLiteral("D");
            else if (canonical == QStringLiteral("LEFT"))
                canonical = QStringLiteral("L");
            else if (canonical == QStringLiteral("RIGHT"))
                canonical = QStringLiteral("R");
            else if (canonical == QStringLiteral("CROSS") ||
                     canonical == QStringLiteral("PRIMARY"))
                canonical = QStringLiteral("X");
            else if (canonical == QStringLiteral("CIRCLE") ||
                     canonical == QStringLiteral("CANCEL"))
                canonical = QStringLiteral("O");
            else if (canonical == QStringLiteral("OPTIONS") ||
                     canonical == QStringLiteral("MENU"))
                canonical = QStringLiteral("START");
            else if (canonical == QStringLiteral("CONTEXT"))
                canonical = QStringLiteral("TRIANGLE");
            else if (canonical == QStringLiteral("SECONDARY"))
                canonical = QStringLiteral("SQUARE");

            tokens.append(canonical);
            text.remove(0, token.length());
            matched = true;
            break;
        }

        if (!matched)
            text.remove(0, 1);
    }

    return tokens;
}

QString DeveloperModeManager::canonicalCredential(const QStringList &tokens) const
{
    return QStringLiteral("CTRL:") + tokens.join(QStringLiteral("|"));
}

QString DeveloperModeManager::canonicalCredential(const QString &credential) const
{
    const QString raw = credential.trimmed();

    if (raw.isEmpty())
        return QString();

    const QStringList tokens = tokenizeCredential(raw);

    /*
        Controller combo path.
        Three tokens minimum keeps Developer Mode harder than a single button
        accident, while still controller-friendly.
    */
    if (tokens.length() >= 3)
        return canonicalCredential(tokens);

    /*
        Keyboard fallback path.
        Normalize but do not lowercase symbols away completely.
    */
    QString code = raw.normalized(QString::NormalizationForm_KC).trimmed();

    code.replace(QRegularExpression(QStringLiteral("[\\r\\n\\t]+")), QStringLiteral(""));
    code.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));

    if (code.length() < 6)
        return QString();

    return QStringLiteral("KEY:") + code;
}

bool DeveloperModeManager::credentialLooksValidForSetup(const QString &credential) const
{
    return !canonicalCredential(credential).isEmpty();
}

/*
    ============================================================
                            ARGON2ID
    ============================================================
*/

bool DeveloperModeManager::ensureSodiumReady() const
{
    static bool initialized = false;
    static bool failed = false;

    if (initialized)
        return true;

    if (failed)
        return false;

    if (sodium_init() < 0) {
        failed = true;
        qWarning() << "DeveloperModeManager failed to initialize libsodium.";
        return false;
    }

    initialized = true;
    return true;
}

QByteArray DeveloperModeManager::argon2idHashCredential(
    const QByteArray &canonicalCredential
) const
{
    if (!ensureSodiumReady())
        return {};

    char encoded[crypto_pwhash_STRBYTES];

    const int rc = crypto_pwhash_str(
        encoded,
        canonicalCredential.constData(),
        static_cast<unsigned long long>(canonicalCredential.size()),
        m_argonOpsLimit,
        m_argonMemLimit
    );

    if (rc != 0) {
        qWarning() << "DeveloperModeManager Argon2id hashing failed.";
        return {};
    }

    return QByteArray(encoded);
}

bool DeveloperModeManager::verifyArgon2idCredential(
    const QByteArray &canonicalCredential,
    const QByteArray &encodedHash
) const
{
    if (!ensureSodiumReady())
        return false;

    if (encodedHash.isEmpty())
        return false;

    const int rc = crypto_pwhash_str_verify(
        encodedHash.constData(),
        canonicalCredential.constData(),
        static_cast<unsigned long long>(canonicalCredential.size())
    );

    return rc == 0;
}

/*
    ============================================================
                            LEGACY PBKDF2
    ============================================================
*/

QByteArray DeveloperModeManager::legacyPbkdf2Sha256(const QByteArray &password,
                                                    const QByteArray &salt,
                                                    int iterations,
                                                    int dkLen) const
{
    const int hashLen = 32;
    const int blockCount = (dkLen + hashLen - 1) / hashLen;

    QByteArray derived;
    derived.reserve(blockCount * hashLen);

    for (int block = 1; block <= blockCount; ++block) {
        QByteArray saltBlock = salt;

        saltBlock.append(static_cast<char>((block >> 24) & 0xFF));
        saltBlock.append(static_cast<char>((block >> 16) & 0xFF));
        saltBlock.append(static_cast<char>((block >> 8) & 0xFF));
        saltBlock.append(static_cast<char>(block & 0xFF));

        QByteArray u = QMessageAuthenticationCode::hash(
            saltBlock,
            password,
            QCryptographicHash::Sha256
        );

        QByteArray t = u;

        for (int i = 1; i < iterations; ++i) {
            u = QMessageAuthenticationCode::hash(
                u,
                password,
                QCryptographicHash::Sha256
            );

            for (int j = 0; j < t.size(); ++j)
                t[j] = static_cast<char>(t[j] ^ u[j]);
        }

        derived.append(t);
    }

    derived.truncate(dkLen);

    return derived;
}

bool DeveloperModeManager::constantTimeEquals(const QByteArray &a,
                                              const QByteArray &b) const
{
    if (a.size() != b.size())
        return false;

    unsigned char diff = 0;

    for (int i = 0; i < a.size(); ++i)
        diff |= static_cast<unsigned char>(a[i] ^ b[i]);

    return diff == 0;
}

/*
    ============================================================
                            SETUP API
    ============================================================
*/

bool DeveloperModeManager::configureDeveloperMode(const QString &codeOrCombo)
{
    return createDeveloperModeCredential(codeOrCombo);
}

bool DeveloperModeManager::createDeveloperModeCredential(const QString &codeOrCombo)
{
    updateLockoutState();

    if (m_lockedOut) {
        setLastError(QStringLiteral("Developer Mode is locked out."));
        return false;
    }

    if (!credentialLooksValidForSetup(codeOrCombo)) {
        setLastError(QStringLiteral("Developer Mode credential is too short."));
        return false;
    }

    const QString canonical = canonicalCredential(codeOrCombo);
    const QByteArray encodedHash = argon2idHashCredential(canonical.toUtf8());

    if (encodedHash.isEmpty()) {
        setLastError(QStringLiteral("Developer Mode hash creation failed."));
        return false;
    }

    QJsonObject obj;

    obj[QStringLiteral("version")] = 2;
    obj[QStringLiteral("kdf")] = QStringLiteral("argon2id");
    obj[QStringLiteral("scheme")] = QStringLiteral("libsodium-crypto-pwhash-str");
    obj[QStringLiteral("hash")] = QString::fromLatin1(encodedHash);
    obj[QStringLiteral("createdAtUtc")] =
            QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    if (canonical.startsWith(QStringLiteral("CTRL:")))
        obj[QStringLiteral("credentialType")] = QStringLiteral("controller-combo");
    else
        obj[QStringLiteral("credentialType")] = QStringLiteral("keyboard-code");

    const bool ok = writeSecureJsonFile(
        hashFilePath(),
        QJsonDocument(obj).toJson(QJsonDocument::Indented)
    );

    if (!ok) {
        setLastError(QStringLiteral("Developer Mode credential could not be saved to the secure state directory."));
        return false;
    }

    setDeveloperModeConfigured(true);
    setLastError(QString());

    registerSuccess();

    return true;
}

bool DeveloperModeManager::createDeveloperModeCombo(const QString &combo)
{
    return createDeveloperModeCredential(combo);
}

bool DeveloperModeManager::setDeveloperModeCombo(const QString &combo)
{
    return createDeveloperModeCredential(combo);
}

bool DeveloperModeManager::setDeveloperModePassword(const QString &code)
{
    return createDeveloperModeCredential(code);
}

bool DeveloperModeManager::setDeveloperModeCode(const QString &code)
{
    return createDeveloperModeCredential(code);
}

QString DeveloperModeManager::normalizeCode(const QString &codeOrCombo) const
{
    const QString raw = codeOrCombo.trimmed();

    if (raw.isEmpty())
        return QString();

    const QStringList tokens = tokenizeCredential(raw);

    if (tokens.length() >= 3)
        return tokens.join(QStringLiteral(","));

    QString code = raw.normalized(QString::NormalizationForm_KC).trimmed();
    code.replace(QRegularExpression(QStringLiteral("[\r\n\t]+")), QString());
    code.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));
    return code;
}

QVariantMap DeveloperModeManager::validateCodeConfirmation(
    const QString &firstCode,
    const QString &confirmationCode
)
{
    QVariantMap result;

    const QString firstCanonical = canonicalCredential(firstCode);
    const QString confirmationCanonical = canonicalCredential(confirmationCode);

    const bool ok = !firstCanonical.isEmpty() &&
                    firstCanonical == confirmationCanonical;

    result.insert(QStringLiteral("ok"), ok);
    result.insert(
        QStringLiteral("normalizedCode"),
        ok ? normalizeCode(firstCode) : QString()
    );
    const QString errorMessage = ok
                                 ? QString()
                                 : QStringLiteral(
                                       "The two Developer Mode credentials do not match."
                                   );

    result.insert(QStringLiteral("error"), errorMessage);
    setLastError(errorMessage);

    return result;
}

QVariantMap DeveloperModeManager::enableWithCode(const QString &codeOrCombo)
{
    QVariantMap result;

    bool ok = false;

    if (!developerModeConfigured()) {
        if (configureDeveloperMode(codeOrCombo))
            ok = enableDeveloperMode(codeOrCombo);
    } else {
        ok = enableDeveloperMode(codeOrCombo);
    }

    result.insert(QStringLiteral("ok"), ok);
    result.insert(QStringLiteral("enabled"), developerModeEnabled());
    result.insert(QStringLiteral("configured"), developerModeConfigured());
    result.insert(QStringLiteral("error"), lastError());

    return result;
}

/*
    ============================================================
                            VERIFY API
    ============================================================
*/

bool DeveloperModeManager::verifyDeveloperModeCredential(const QString &codeOrCombo)
{
    updateLockoutState();

    if (m_lockedOut) {
        setLastError(QStringLiteral("Developer Mode is locked out."));
        return false;
    }

    loadConfiguredState();

    if (!m_developerModeConfigured) {
        setLastError(QStringLiteral("Developer Mode is not configured."));
        return false;
    }

    const QString canonical = canonicalCredential(codeOrCombo);

    if (canonical.isEmpty()) {
        setLastError(QStringLiteral("Invalid Developer Mode credential."));
        return false;
    }

    const QByteArray data = readFile(hashFilePath());

    if (data.isEmpty()) {
        setDeveloperModeConfigured(false);
        setLastError(QStringLiteral("Developer Mode credential file is missing."));
        return false;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(data);

    if (!doc.isObject()) {
        setLastError(QStringLiteral("Developer Mode credential file is invalid."));
        registerFailedAttemptWithReason(QStringLiteral("invalid developer credential file"));
        return false;
    }

    const QJsonObject obj = doc.object();

    const QString kdf = obj.value(QStringLiteral("kdf")).toString().trimmed().toLower();
    const QByteArray canonicalBytes = canonical.toUtf8();

    bool ok = false;
    bool legacyOk = false;

    if (kdf == QStringLiteral("argon2id") ||
            kdf.contains(QStringLiteral("argon2"))) {
        const QByteArray encodedHash =
                obj.value(QStringLiteral("hash")).toString().toLatin1();

        ok = verifyArgon2idCredential(canonicalBytes, encodedHash);
    } else if (kdf == QStringLiteral("pbkdf2-sha256")) {
        const int iterations =
                obj.value(QStringLiteral("iterations")).toInt(m_legacyPbkdf2Iterations);

        const QByteArray salt =
                QByteArray::fromBase64(
                    obj.value(QStringLiteral("salt")).toString().toLatin1()
                );

        const QByteArray expectedHash =
                QByteArray::fromBase64(
                    obj.value(QStringLiteral("hash")).toString().toLatin1()
                );

        if (iterations > 0 && !salt.isEmpty() && !expectedHash.isEmpty()) {
            const QByteArray candidateHash = legacyPbkdf2Sha256(
                canonicalBytes,
                salt,
                iterations,
                expectedHash.size()
            );

            legacyOk = constantTimeEquals(candidateHash, expectedHash);
            ok = legacyOk;
        }
    } else {
        /*
            Some early developer-mode files were raw hash-string files rather
            than JSON. Treat known libsodium strings as Argon2id.
        */
        const QByteArray raw = data.trimmed();

        if (raw.startsWith("$argon2id$"))
            ok = verifyArgon2idCredential(canonicalBytes, raw);
    }

    if (!ok) {
        setLastError(QStringLiteral("Developer Mode credential rejected."));
        registerFailedAttemptWithReason(QStringLiteral("developer credential rejected"));
        return false;
    }

    if (legacyOk) {
        /*
            Verified legacy credential; immediately rewrite as Argon2id.
        */
        createDeveloperModeCredential(codeOrCombo);
    }

    setLastError(QString());
    registerSuccess();

    return true;
}

bool DeveloperModeManager::verifyDeveloperModeCombo(const QString &combo)
{
    return verifyDeveloperModeCredential(combo);
}

bool DeveloperModeManager::verifyDeveloperModePassword(const QString &code)
{
    return verifyDeveloperModeCredential(code);
}

bool DeveloperModeManager::verifyCode(const QString &codeOrCombo)
{
    return verifyDeveloperModeCredential(codeOrCombo);
}

bool DeveloperModeManager::verifyCombo(const QString &combo)
{
    return verifyDeveloperModeCredential(combo);
}

bool DeveloperModeManager::enableDeveloperMode(const QString &codeOrCombo)
{
    if (!verifyDeveloperModeCredential(codeOrCombo))
        return false;

    saveEnabledState(true);

    return m_developerModeEnabled;
}

bool DeveloperModeManager::verifyAndEnable(const QString &codeOrCombo)
{
    return enableDeveloperMode(codeOrCombo);
}

bool DeveloperModeManager::enable(const QString &codeOrCombo)
{
    return enableDeveloperMode(codeOrCombo);
}

bool DeveloperModeManager::toggleDeveloperMode(const QString &codeOrCombo)
{
    if (m_developerModeEnabled)
        return disableDeveloperMode();

    return enableDeveloperMode(codeOrCombo);
}

/*
    ============================================================
                            DISABLE / RESET
    ============================================================
*/

bool DeveloperModeManager::disableDeveloperMode()
{
    saveEnabledState(false);
    return !m_developerModeEnabled;
}

bool DeveloperModeManager::disable()
{
    return disableDeveloperMode();
}

bool DeveloperModeManager::turnOff()
{
    return disableDeveloperMode();
}

bool DeveloperModeManager::resetDeveloperMode()
{
    bool ok = true;

    ok = removeSecureFile(hashFilePath()) && ok;
    ok = removeSecureFile(enabledMarkerPath()) && ok;
    ok = removeSecureFile(lockoutStateFilePath()) && ok;

    m_developerModeEnabled = false;
    m_developerModeConfigured = false;

    m_failedAttempts = 0;
    m_highThreatAttempts = 0;

    m_lockedOut = false;
    m_secondsRemaining = 0;
    m_lockoutDelaySeconds = 0;
    m_lockoutLevel = 0;
    m_lockoutUntilMonotonicMs = 0;

    m_lastFailedAttemptMonotonicMs = -1;
    m_lastHighThreatMonotonicMs = -1;

    m_lastError.clear();
    m_lastFailureReason.clear();
    m_lastHighThreatReason.clear();

    emit developerModeChanged();
    emit enabledChanged();
    emit configuredChanged();
    emit developerModeDisabledChanged();
    emit lockoutCleared();
    emit lockoutChanged();

    return ok;
}

/*
    ============================================================
                            MIGRATION
    ============================================================
*/

bool DeveloperModeManager::migrateLegacyDeveloperState()
{
    ensureStateDirectories();

    bool migratedAny = false;

    const QString legacyHash = legacyHashFilePath();
    const QString targetHash = hashFilePath();

    if (QFileInfo::exists(legacyHash) && !QFileInfo::exists(targetHash)) {
        if (QFile::copy(legacyHash, targetHash)) {
            setOwnerOnlyPermissions(targetHash, false);
            setOwnerRootOnly(targetHash);
            migratedAny = true;
        } else {
            qWarning() << "DeveloperModeManager failed to migrate legacy hash:"
                       << legacyHash
                       << "->"
                       << targetHash;
        }
    }

    const QString legacyMarker = legacyEnabledMarkerPath();
    const QString targetMarker = enabledMarkerPath();

    if (QFileInfo::exists(legacyMarker) && !QFileInfo::exists(targetMarker)) {
        if (QFile::copy(legacyMarker, targetMarker)) {
            setOwnerOnlyPermissions(targetMarker, false);
            setOwnerRootOnly(targetMarker);
            migratedAny = true;
        } else {
            qWarning() << "DeveloperModeManager failed to migrate legacy enabled marker:"
                       << legacyMarker
                       << "->"
                       << targetMarker;
        }
    }

    /*
        Old wall-clock lockout data is intentionally not migrated.
        Hardened lockout state starts from persistent counter data in the new
        location only.
    */

    if (migratedAny)
        qInfo() << "DeveloperModeManager migrated legacy state to /var/lib/neutronos.";

    return migratedAny;
}