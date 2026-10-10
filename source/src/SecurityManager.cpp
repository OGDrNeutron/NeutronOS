#include "SecurityManager.h"
#include "NotificationManager.h"
#include "HumanAccountPolicy.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QMessageAuthenticationCode>
#include <QMetaObject>
#include <QPointer>
#include <QRegularExpression>
#include <QSaveFile>
#include <QtConcurrent/QtConcurrentRun>
#include <QtGlobal>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <utility>
#include <vector>

#include <sodium.h>

#ifdef Q_OS_LINUX
#include <pwd.h>
#include <security/pam_appl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#endif

namespace {
constexpr int LockoutTickMs = 1000;
constexpr int AuthorizationTickMs = 1000;
constexpr int RefreshDelayMs = 120;

QString envValue(const char *name)
{
    return QString::fromLocal8Bit(qgetenv(name)).trimmed();
}

bool safeUserName(const QString &name)
{
    static const QRegularExpression pattern(
        QStringLiteral("^[A-Za-z_][A-Za-z0-9_.-]{0,63}$"));
    return pattern.match(name).hasMatch();
}

QString passwdString(const char *value)
{
    return value ? QString::fromLocal8Bit(value).trimmed() : QString();
}

QString mapText(const QVariantMap &map, const QStringList &keys)
{
    for (const QString &key : keys) {
        const QString value = map.value(key).toString().trimmed();
        if (!value.isEmpty())
            return value;
    }

    const QVariantMap nested = map.value(QStringLiteral("user")).toMap();
    for (const QString &key : keys) {
        const QString value = nested.value(key).toString().trimmed();
        if (!value.isEmpty())
            return value;
    }

    return {};
}

QString currentSessionUser()
{
#ifdef Q_OS_LINUX
    const QStringList candidates = {
        envValue("NEUTRONOS_USER"),
        envValue("SUDO_USER"),
        envValue("LOGNAME"),
        envValue("USER")
    };

    for (const QString &candidate : candidates) {
        if (safeUserName(candidate) && HumanAccountPolicy::namedUserIsHuman(candidate))
            return candidate;
    }

    long size = sysconf(_SC_GETPW_R_SIZE_MAX);
    if (size < 1024)
        size = 16384;

    std::vector<char> buffer(static_cast<std::size_t>(size));
    struct passwd entry;
    struct passwd *result = nullptr;

    if (getpwuid_r(getuid(), &entry, buffer.data(), buffer.size(), &result) == 0 &&
            result) {
        const QString user = passwdString(result->pw_name);
        if (safeUserName(user) && HumanAccountPolicy::isHuman(entry))
            return user;
    }

    QDir homeRoot(QStringLiteral("/home"));
    const QFileInfoList homes = homeRoot.entryInfoList(
        QDir::Dirs | QDir::Readable | QDir::NoDotAndDotDot,
        QDir::Name);

    QString onlyUser;
    for (const QFileInfo &home : homes) {
        const QString candidate = home.fileName();
        if (!safeUserName(candidate))
            continue;

        const QByteArray encoded = candidate.toLocal8Bit();
        if (getpwnam_r(encoded.constData(), &entry, buffer.data(), buffer.size(), &result) != 0 ||
                !result || !HumanAccountPolicy::isHuman(*result)) {
            continue;
        }

        if (!onlyUser.isEmpty())
            return {};
        onlyUser = candidate;
    }

    return onlyUser;
#else
    const QString candidate = envValue("USER");
    return safeUserName(candidate) ? candidate : QString();
#endif
}

QString isoUtc(const QDateTime &value)
{
    return value.isValid() ? value.toUTC().toString(Qt::ISODateWithMs) : QString();
}

QDateTime parseUtc(const QJsonValue &value)
{
    QDateTime parsed = QDateTime::fromString(value.toString(), Qt::ISODateWithMs);
    if (!parsed.isValid())
        parsed = QDateTime::fromString(value.toString(), Qt::ISODate);
    return parsed.isValid() ? parsed.toUTC() : QDateTime();
}

bool sodiumAvailable()
{
    static const bool ready = sodium_init() >= 0;
    return ready;
}

void wipeBytes(QByteArray &value)
{
    if (!value.isEmpty() && sodiumAvailable())
        sodium_memzero(value.data(), static_cast<std::size_t>(value.size()));
    else if (!value.isEmpty())
        value.fill('\0');
    value.clear();
    value.squeeze();
}

QByteArray argonHash(const QByteArray &secret,
                     unsigned long long operations,
                     std::size_t memory)
{
    if (!sodiumAvailable() || secret.isEmpty())
        return {};

    char encoded[crypto_pwhash_STRBYTES];
    sodium_memzero(encoded, sizeof(encoded));

    const int rc = crypto_pwhash_str(
        encoded,
        secret.constData(),
        static_cast<unsigned long long>(secret.size()),
        operations,
        memory);

    const QByteArray result = rc == 0 ? QByteArray(encoded) : QByteArray();
    sodium_memzero(encoded, sizeof(encoded));
    return result;
}

bool argonVerify(const QByteArray &secret, const QByteArray &encoded)
{
    return sodiumAvailable() && !secret.isEmpty() && !encoded.isEmpty() &&
           crypto_pwhash_str_verify(
               encoded.constData(),
               secret.constData(),
               static_cast<unsigned long long>(secret.size())) == 0;
}

QByteArray pbkdf2(const QByteArray &password,
                  const QByteArray &salt,
                  int iterations,
                  int length)
{
    if (password.isEmpty() || salt.isEmpty() || iterations <= 0 || length <= 0)
        return {};

    constexpr int hashLength = 32;
    const int blocks = (length + hashLength - 1) / hashLength;
    QByteArray derived;
    derived.reserve(blocks * hashLength);

    for (int block = 1; block <= blocks; ++block) {
        QByteArray blockSalt = salt;
        blockSalt.append(static_cast<char>((block >> 24) & 0xff));
        blockSalt.append(static_cast<char>((block >> 16) & 0xff));
        blockSalt.append(static_cast<char>((block >> 8) & 0xff));
        blockSalt.append(static_cast<char>(block & 0xff));

        QByteArray u = QMessageAuthenticationCode::hash(
            blockSalt, password, QCryptographicHash::Sha256);
        QByteArray accumulator = u;

        for (int iteration = 1; iteration < iterations; ++iteration) {
            u = QMessageAuthenticationCode::hash(
                u, password, QCryptographicHash::Sha256);
            for (int i = 0; i < accumulator.size(); ++i) {
                accumulator[i] = static_cast<char>(
                    static_cast<unsigned char>(accumulator[i]) ^
                    static_cast<unsigned char>(u[i]));
            }
        }

        derived.append(accumulator);
        wipeBytes(blockSalt);
        wipeBytes(u);
        wipeBytes(accumulator);
    }

    derived.truncate(length);
    return derived;
}

bool constantEquals(const QByteArray &left, const QByteArray &right)
{
    const int maxLength = qMax(left.size(), right.size());
    unsigned int difference =
        static_cast<unsigned int>(left.size() ^ right.size());

    for (int i = 0; i < maxLength; ++i) {
        const unsigned char l =
            i < left.size() ? static_cast<unsigned char>(left.at(i)) : 0U;
        const unsigned char r =
            i < right.size() ? static_cast<unsigned char>(right.at(i)) : 0U;
        difference |= static_cast<unsigned int>(l ^ r);
    }

    return difference == 0U;
}

QByteArray legacyDirectionCanonical(const QByteArray &canonical)
{
    const QList<QByteArray> tokens = canonical.split('|');
    QList<QByteArray> converted;
    converted.reserve(tokens.size());

    for (QByteArray token : tokens) {
        if (token == QByteArrayLiteral("UP"))
            token = QByteArrayLiteral("U");
        else if (token == QByteArrayLiteral("DOWN"))
            token = QByteArrayLiteral("D");
        else if (token == QByteArrayLiteral("LEFT"))
            token = QByteArrayLiteral("L");
        else if (token == QByteArrayLiteral("RIGHT"))
            token = QByteArrayLiteral("R");
        converted.append(token);
    }

    QByteArray result;
    for (int i = 0; i < converted.size(); ++i) {
        if (i > 0)
            result.append('|');
        result.append(converted.at(i));
    }
    return result;
}

bool verifyLegacyObject(const QJsonObject &record,
                        const QByteArray &canonicalCombo)
{
    const int iterations = record.value(QStringLiteral("iterations")).toInt();
    const QByteArray salt = QByteArray::fromBase64(
        record.value(QStringLiteral("salt")).toString().toLatin1());

    QByteArray expected = QByteArray::fromBase64(
        record.value(QStringLiteral("hash")).toString().toLatin1());
    if (expected.isEmpty()) {
        expected = QByteArray::fromBase64(
            record.value(QStringLiteral("digest")).toString().toLatin1());
    }

    if (iterations < 100000 || iterations > 5000000 ||
            salt.size() < 16 || expected.isEmpty()) {
        return false;
    }

    QByteArray candidate = pbkdf2(
        canonicalCombo, salt, iterations, expected.size());
    const bool matched = constantEquals(candidate, expected);
    wipeBytes(candidate);
    return matched;
}

QString oldFlatPath(const QString &directory, const QString &username)
{
    if (!safeUserName(username))
        return {};

    if (username == QStringLiteral("neutronos"))
        return directory + QStringLiteral("/login_combo.hash");

    const QByteArray digest = QCryptographicHash::hash(
        username.toUtf8(), QCryptographicHash::Sha256).toHex();

    return directory + QStringLiteral("/login_combo_") +
           QString::fromLatin1(digest.left(16)) + QStringLiteral(".hash");
}

#ifdef Q_OS_LINUX
struct PamConversationData
{
    QByteArray username;
    QByteArray password;
};

struct PamSessionBundle
{
    pam_handle_t *handle = nullptr;
    PamConversationData *conversation = nullptr;
    bool sessionOpen = false;
};

bool trustedLockoutStateFile(const QString &path,
                             uid_t accountUid,
                             gid_t accountGid)
{
#ifdef Q_OS_LINUX
    const QByteArray encoded = QFile::encodeName(path);
    struct stat state {};
    if (::lstat(encoded.constData(), &state) != 0 || !S_ISREG(state.st_mode))
        return false;

    const uid_t effectiveUid = ::geteuid();
    const bool trustedOwner = state.st_uid == static_cast<uid_t>(0) ||
                              state.st_uid == effectiveUid ||
                              (state.st_uid == accountUid && state.st_gid == accountGid);
    const bool writableByAnotherAccount =
        (state.st_mode & (S_IWGRP | S_IWOTH)) != 0;
    return trustedOwner && !writableByAnotherAccount;
#else
    const QFileInfo info(path);
    return info.isFile() && !info.isSymLink();
#endif
}

void destroyPamSessionBundle(void *opaque)
{
    auto *bundle = static_cast<PamSessionBundle *>(opaque);
    if (!bundle)
        return;

    int rc = PAM_SUCCESS;
    if (bundle->handle) {
        if (bundle->sessionOpen)
            rc = pam_close_session(bundle->handle, PAM_SILENT);

        const int credRc = pam_setcred(bundle->handle, PAM_DELETE_CRED);
        if (rc == PAM_SUCCESS && credRc != PAM_SUCCESS)
            rc = credRc;

        pam_end(bundle->handle, rc);
    }

    if (bundle->conversation) {
        wipeBytes(bundle->conversation->password);
        wipeBytes(bundle->conversation->username);
        delete bundle->conversation;
    }

    delete bundle;
}
#endif
}

SecurityManager::SecurityManager(QObject *parent)
    : QObject(parent)
{
    m_monotonicClock.start();

    m_lockoutRefreshTimer.setInterval(LockoutTickMs);
    m_lockoutRefreshTimer.setSingleShot(false);

    m_setupAuthorizationTimer.setInterval(AuthorizationTickMs);
    m_setupAuthorizationTimer.setSingleShot(false);

    m_highPriorityAuthorizationTimer.setInterval(AuthorizationTickMs);
    m_highPriorityAuthorizationTimer.setSingleShot(false);

    m_refreshCoalesceTimer.setInterval(RefreshDelayMs);
    m_refreshCoalesceTimer.setSingleShot(true);

    connect(&m_lockoutRefreshTimer, &QTimer::timeout,
            this, &SecurityManager::updateLockoutState);
    connect(&m_setupAuthorizationTimer, &QTimer::timeout,
            this, &SecurityManager::updateSetupAuthorizationState);
    connect(&m_highPriorityAuthorizationTimer, &QTimer::timeout,
            this, &SecurityManager::updateHighPriorityAuthorizationState);
    connect(&m_refreshCoalesceTimer, &QTimer::timeout,
            this, &SecurityManager::coalescedRefresh);
    connect(&m_fileWatcher, &QFileSystemWatcher::fileChanged,
            this, &SecurityManager::onWatchedPathChanged);
    connect(&m_fileWatcher, &QFileSystemWatcher::directoryChanged,
            this, &SecurityManager::onWatchedPathChanged);

    ensureSodiumReady();
    ensureSecurityDir();

    const QString initialUser = currentSessionUser();
    if (!initialUser.isEmpty())
        setActiveUsername(initialUser);
    else {
        rebuildPublicState();
        rebuildWatchers();
    }

    migrateLegacyUserState();
    if (!m_activeUsername.isEmpty())
        loadActiveUserState();
}

SecurityManager::~SecurityManager()
{
    ++m_operationSerial;
    m_lockoutRefreshTimer.stop();
    m_setupAuthorizationTimer.stop();
    m_highPriorityAuthorizationTimer.stop();
    m_refreshCoalesceTimer.stop();

    if (!m_fileWatcher.files().isEmpty())
        m_fileWatcher.removePaths(m_fileWatcher.files());
    if (!m_fileWatcher.directories().isEmpty())
        m_fileWatcher.removePaths(m_fileWatcher.directories());

    clearTransientSecrets();
    closePamSession();
}

QString SecurityManager::activeUsername() const { return m_activeUsername; }
QVariantMap SecurityManager::activeUser() const { return m_activeUser; }
QString SecurityManager::loginConfigurationState() const
{
    return LoginConfiguration::name(m_loginConfigurationState);
}
bool SecurityManager::lockedOut() const { return m_lockedOut; }
int SecurityManager::failedAttempts() const { return m_failedAttempts; }
int SecurityManager::secondsRemaining() const { return m_secondsRemaining; }
int SecurityManager::lockoutDelaySeconds() const { return m_lockoutDelaySeconds; }
int SecurityManager::lockoutLevel() const { return m_lockoutLevel; }
QString SecurityManager::lastFailureReason() const { return m_lastFailureReason; }
bool SecurityManager::loginComboConfigured() const { return m_loginComboConfigured; }
bool SecurityManager::requiresComboSetup() const
{
    return !m_activeUsername.isEmpty() &&
           LoginConfiguration::allowsFirstRunSetup(m_loginConfigurationState);
}
int SecurityManager::comboLength() const { return m_comboLength; }
int SecurityManager::minimumComboLength() const { return MinimumComboLength; }
int SecurityManager::maximumComboLength() const { return MaximumComboLength; }
int SecurityManager::maximumRollingInputs() const { return MaximumRollingInputs; }

QVariantList SecurityManager::allowedComboTokens() const
{
    const QStringList tokens = {
        QStringLiteral("UP"), QStringLiteral("DOWN"),
        QStringLiteral("LEFT"), QStringLiteral("RIGHT"),
        QStringLiteral("X"), QStringLiteral("O"),
        QStringLiteral("SQUARE"), QStringLiteral("TRIANGLE"),
        QStringLiteral("L1"), QStringLiteral("R1"),
        QStringLiteral("L2"), QStringLiteral("R2"),
        QStringLiteral("L3"), QStringLiteral("R3")
    };

    QVariantList result;
    for (const QString &token : tokens)
        result.append(token);
    return result;
}

bool SecurityManager::setupAuthorized() const
{
    return setupAuthorizationValid();
}

int SecurityManager::setupAuthorizationRemaining() const
{
    if (!setupAuthorizationValid())
        return 0;

    return static_cast<int>(qMax<qint64>(
        1,
        QDateTime::currentDateTimeUtc().secsTo(
            m_setupAuthorization.expiresAtUtc)));
}

bool SecurityManager::highPriorityAuthorized() const
{
    return highPriorityAuthorizationValidFor(m_highPriorityAuthorizedApp);
}

int SecurityManager::highPriorityAuthorizationRemaining() const
{
    if (!highPriorityAuthorized())
        return 0;
    return static_cast<int>(qMax<qint64>(1,
        QDateTime::currentDateTimeUtc().secsTo(m_highPriorityAuthorizationExpiresAtUtc)));
}

QString SecurityManager::highPriorityAuthorizedApp() const
{
    return highPriorityAuthorized() ? m_highPriorityAuthorizedApp : QString();
}

bool SecurityManager::operationBusy() const { return m_operationBusy; }
bool SecurityManager::authenticationPending() const
{
    return m_operationBusy &&
           m_operationKind == OperationKind::VerifyLocalPassword;
}
bool SecurityManager::comboOperationPending() const
{
    return m_operationBusy &&
           (m_operationKind == OperationKind::CreateCombo ||
            m_operationKind == OperationKind::VerifyCombo ||
            m_operationKind == OperationKind::ChangeCombo);
}
QString SecurityManager::activeOperation() const { return m_activeOperation; }
QString SecurityManager::lastOperation() const { return m_lastOperation; }
QString SecurityManager::lastError() const { return m_lastError; }
QString SecurityManager::securityDirPath() const
{
    return QStringLiteral(NEUTRONOS_SECURITY_STATE_DIR);
}
QString SecurityManager::kdfScheme() const
{
    return QStringLiteral("argon2id/libsodium");
}
int SecurityManager::securityRevision() const { return m_securityRevision; }
bool SecurityManager::pamSessionOpen() const { return m_pamSessionOpen; }
QString SecurityManager::pamSessionUser() const { return m_pamSessionUser; }
QString SecurityManager::pamLastError() const { return m_pamLastError; }

bool SecurityManager::setActiveUser(const QVariantMap &userContext)
{
    if (m_operationBusy) {
        setLastError(QStringLiteral("A security operation is already running"));
        return false;
    }

    QVariantMap validated;
    QString error;
    if (!validateActiveUserContext(userContext, &validated, &error)) {
        setLastError(error);
        return false;
    }

    const QString username =
        validated.value(QStringLiteral("username")).toString();
    const bool changed =
        username != m_activeUsername || validated != m_activeUser;

    if (username != m_activeUsername) {
        ++m_operationSerial;
        clearPendingOperation();
        setOperationBusy(false);
        clearSetupAuthorization();

        if (m_pamSessionOpen && m_pamSessionUser != username)
            closePamSession();
    }

    m_activeUsername = username;
    m_activeUser = validated;

    migrateLegacyComboForUser(username);
    loadActiveUserState();
    rebuildWatchers();

    setLastError(QString());
    setLastOperation(QStringLiteral("Security profile loaded"));

    if (changed) {
        emit activeUserChanged();
        emit stateChanged();
        incrementSecurityRevision();
    }

    return true;
}

bool SecurityManager::setActiveUsername(const QString &username)
{
    QVariantMap context;
    context.insert(QStringLiteral("username"), username);
    return setActiveUser(context);
}

void SecurityManager::clearActiveUser()
{
    ++m_operationSerial;
    const bool hadUser = !m_activeUsername.isEmpty() || !m_activeUser.isEmpty();

    clearPendingOperation();
    setOperationBusy(false);
    m_setupAuthorization = SetupAuthorization();
    m_setupAuthorizationTimer.stop();
    clearHighPriorityAuthorization();
    closePamSession();

    m_activeUsername.clear();
    m_activeUser.clear();
    m_comboRecord = ComboRecord();
    m_persistentState = PersistentState();

    m_failedAttempts = 0;
    m_highThreatAttempts = 0;
    m_secondsRemaining = 0;
    m_lockoutDelaySeconds = 0;
    m_lockoutLevel = 0;
    m_lockedOut = false;
    m_loginComboConfigured = false;
    setLoginConfigurationState(LoginConfiguration::State::LoadingUnknown);
    m_comboLength = 0;
    m_lastFailureReason.clear();
    m_lastHighThreatReason.clear();
    m_lockoutUntilMonotonicMs = 0;
    m_lockoutRefreshTimer.stop();

    rebuildWatchers();

    if (hadUser) {
        emit activeUserChanged();
        emit setupAuthorizationChanged();
        emit stateChanged();
        incrementSecurityRevision();
    }
}

bool SecurityManager::authorizeFreshSetupIdentity(const QString &username)
{
    if (m_operationBusy) {
        setLastError(QStringLiteral("A security operation is already running"));
        return false;
    }

    const QString cleanUsername = username.trimmed();
    if (!safeUserName(cleanUsername) ||
            !HumanAccountPolicy::namedUserIsHuman(cleanUsername)) {
        setLastError(QStringLiteral(
            "Fresh setup authorization requires a valid local human account"));
        return false;
    }

    if (m_activeUsername.isEmpty() && !setActiveUsername(cleanUsername))
        return false;

    if (!usernameMatchesActiveUser(cleanUsername)) {
        setLastError(QStringLiteral(
            "Fresh setup authorization must target the active local user"));
        return false;
    }

    if (m_loginComboConfigured) {
        setLastError(QStringLiteral(
            "Fresh setup authorization is unavailable after passcode enrollment"));
        return false;
    }

    /*
        setup-identity is guarded by a root-owned one-shot wrapper. Require its
        success marker before granting the narrow in-memory authorization used
        to create the first controller combo.
    */
    const QString identityMarkerPath = QStringLiteral(
        "/var/lib/neutronos/security-core/identity-provisioned");
    QFile identityMarker(identityMarkerPath);
    if (!identityMarker.exists() || !identityMarker.open(QIODevice::ReadOnly)) {
        setLastError(QStringLiteral(
            "Fresh setup identity provisioning could not be verified"));
        return false;
    }

    QJsonParseError markerParseError;
    const QJsonDocument markerDocument =
        QJsonDocument::fromJson(identityMarker.readAll(), &markerParseError);
    if (markerParseError.error != QJsonParseError::NoError ||
            !markerDocument.isObject() ||
            !markerDocument.object()
                 .value(QStringLiteral("provisioned"))
                 .toBool(false)) {
        setLastError(QStringLiteral(
            "Fresh setup identity provisioning marker is invalid"));
        return false;
    }

    const QString setupPath =
        QStringLiteral("/var/lib/neutronos/setup/setup.json");
    QFile setupFile(setupPath);
    if (setupFile.exists()) {
        if (!setupFile.open(QIODevice::ReadOnly)) {
            setLastError(QStringLiteral(
                "First-boot setup state could not be verified"));
            return false;
        }

        QJsonParseError parseError;
        const QJsonDocument setupDocument =
            QJsonDocument::fromJson(setupFile.readAll(), &parseError);
        if (parseError.error != QJsonParseError::NoError ||
                !setupDocument.isObject()) {
            setLastError(QStringLiteral(
                "First-boot setup state is invalid"));
            return false;
        }

        if (setupDocument.object()
                .value(QStringLiteral("completed"))
                .toBool(false)) {
            setLastError(QStringLiteral(
                "First-boot setup has already been completed"));
            return false;
        }
    }

    /*
        This gate is deliberately narrower than password authentication:
        - the target must already be a real human Unix account;
        - onboarding must still be incomplete; and
        - no controller login combo may exist yet.

        setup-identity is the root-owned one-shot operation that created the
        account and installed the password immediately before this call. A
        second PAM round-trip from the unprivileged display account is both
        redundant and invalid for a different Unix user on pam_unix.
    */
    grantSetupAuthorization(cleanUsername, QStringLiteral("setup"));
    setLastError(QString());
    setLastOperation(QStringLiteral("Fresh setup identity authorized"));
    return true;
}

bool SecurityManager::beginLocalPasswordVerification(
    const QString &username,
    const QString &password,
    const QString &purpose)
{
    if (m_operationBusy)
        return false;

    if (m_activeUsername.isEmpty() && !setActiveUsername(username))
        return false;

    if (!usernameMatchesActiveUser(username)) {
        setLastError(QStringLiteral(
            "Password verification must target the active local user"));
        return false;
    }

    updateLockoutState();
    if (m_lockedOut) {
        setLastError(QStringLiteral("Authentication is temporarily locked"));
        return false;
    }

    if (password.isEmpty()) {
        setLastError(QStringLiteral("Local account password is required"));
        return false;
    }

    const QString normalized = normalizedPurpose(purpose);
    QVariantMap payload;
    payload.insert(QStringLiteral("username"), m_activeUsername);
    payload.insert(QStringLiteral("purpose"), normalized);

    if (!beginOperation(OperationKind::VerifyLocalPassword,
                        QStringLiteral("verifyLocalPassword"), payload)) {
        return false;
    }

    QByteArray passwordBytes = password.toUtf8();
    dispatchLocalPasswordVerification(
        m_activeUsername, passwordBytes, normalized, m_operationSerial);
    secureClear(passwordBytes);
    return true;
}

bool SecurityManager::verifyLocalPassword(
    const QString &username,
    const QString &password)
{
    return authenticateLocalUser(username, password);
}

bool SecurityManager::authenticateLocalUser(
    const QString &username,
    const QString &password)
{
    if (m_activeUsername.isEmpty() && !setActiveUsername(username))
        return false;

    if (!usernameMatchesActiveUser(username)) {
        setLastError(QStringLiteral(
            "Authentication must target the active local user"));
        return false;
    }

    updateLockoutState();
    if (m_lockedOut)
        return false;

    if (password.isEmpty()) {
        setLastError(QStringLiteral("Local account password is required"));
        return false;
    }

    const bool success =
        verifyPamPasswordAndOpenSession(m_activeUsername, password);

    if (!success) {
        registerFailedAttemptWithReason(
            QStringLiteral("PAM authentication failed"));
        return false;
    }

    resetFailuresAfterVerifiedAuthentication();
    grantSetupAuthorization(
        m_activeUsername,
        m_loginComboConfigured
            ? QStringLiteral("change")
            : QStringLiteral("setup"));

    setLastOperation(QStringLiteral("Local account verified"));
    return true;
}

bool SecurityManager::authorizeHighPriorityAction(
    const QString &username,
    const QString &password,
    const QString &appId)
{
    const QString cleanAppId = appId.trimmed().toLower();
    if (cleanAppId.isEmpty()) {
        setLastError(QStringLiteral("An application scope is required"));
        return false;
    }

    if (!authenticateLocalUser(username, password)) {
        clearHighPriorityAuthorization();
        return false;
    }

    m_highPriorityAuthorizedApp = cleanAppId;
    m_highPriorityAuthorizationExpiresAtUtc =
        QDateTime::currentDateTimeUtc().addSecs(HighPriorityAuthorizationSeconds);
    m_highPriorityAuthorizationTimer.start();

    if (qApp) {
        qApp->setProperty("neutronHighPriorityAppId", m_highPriorityAuthorizedApp);
        qApp->setProperty("neutronHighPriorityExpiresUtcMs",
                          m_highPriorityAuthorizationExpiresAtUtc.toMSecsSinceEpoch());
    }

    setLastOperation(QStringLiteral("High-priority actions authorized for 15 minutes"));
    emit highPriorityAuthorizationChanged();
    return true;
}

bool SecurityManager::highPriorityAuthorizationValidFor(const QString &appId) const
{
    const QString cleanAppId = appId.trimmed().toLower();
    return !cleanAppId.isEmpty() &&
           cleanAppId == m_highPriorityAuthorizedApp &&
           m_highPriorityAuthorizationExpiresAtUtc.isValid() &&
           QDateTime::currentDateTimeUtc() < m_highPriorityAuthorizationExpiresAtUtc;
}

void SecurityManager::clearHighPriorityAuthorization()
{
    const bool changed = !m_highPriorityAuthorizedApp.isEmpty() ||
                         m_highPriorityAuthorizationExpiresAtUtc.isValid();
    m_highPriorityAuthorizationTimer.stop();
    m_highPriorityAuthorizedApp.clear();
    m_highPriorityAuthorizationExpiresAtUtc = QDateTime();
    if (qApp) {
        qApp->setProperty("neutronHighPriorityAppId", QString());
        qApp->setProperty("neutronHighPriorityExpiresUtcMs", 0);
    }
    if (changed)
        emit highPriorityAuthorizationChanged();
}

void SecurityManager::updateHighPriorityAuthorizationState()
{
    if (!highPriorityAuthorized()) {
        clearHighPriorityAuthorization();
        return;
    }
    emit highPriorityAuthorizationChanged();
}

bool SecurityManager::closePamSession()
{
#ifdef Q_OS_LINUX
    if (!m_pamHandle) {
        const bool changed =
            m_pamSessionOpen || !m_pamSessionUser.isEmpty() ||
            !m_pamEnvironment.isEmpty();
        resetPamState();
        if (changed)
            emit pamSessionChanged();
        return true;
    }

    auto *bundle = static_cast<PamSessionBundle *>(m_pamHandle);
    int rc = PAM_SUCCESS;

    if (bundle->handle && bundle->sessionOpen)
        rc = pam_close_session(bundle->handle, PAM_SILENT);

    if (bundle->handle) {
        const int credRc = pam_setcred(bundle->handle, PAM_DELETE_CRED);
        if (rc == PAM_SUCCESS && credRc != PAM_SUCCESS)
            rc = credRc;
        const int endRc = pam_end(bundle->handle, rc);
        if (rc == PAM_SUCCESS && endRc != PAM_SUCCESS)
            rc = endRc;
        bundle->handle = nullptr;
    }

    if (bundle->conversation) {
        wipeBytes(bundle->conversation->password);
        wipeBytes(bundle->conversation->username);
        delete bundle->conversation;
        bundle->conversation = nullptr;
    }

    delete bundle;
    m_pamHandle = nullptr;
    resetPamState();

    if (rc != PAM_SUCCESS) {
        setPamLastError(QStringLiteral("PAM session cleanup failed"));
        return false;
    }

    setPamLastError(QString());
    emit pamSessionChanged();
    return true;
#else
    resetPamState();
    emit pamSessionChanged();
    return true;
#endif
}

bool SecurityManager::logoutPamSession()
{
    return closePamSession();
}

QStringList SecurityManager::pamEnvironment() const
{
    return m_pamEnvironment;
}


bool SecurityManager::beginLoginComboCreation(
    const QString &username,
    const QString &normalizedCombo,
    const QString &confirmation)
{
    if (m_operationBusy)
        return false;

    if (!usernameMatchesActiveUser(username)) {
        setLastError(QStringLiteral(
            "Combo creation must target the active local user"));
        return false;
    }

    if (!setupAuthorizationValid()) {
        setLastError(QStringLiteral(
            "Local account verification is required before creating a login combo"));
        return false;
    }

    bool comboValid = false;
    bool confirmationValid = false;
    const QString canonical =
        canonicalComboString(normalizedCombo, &comboValid);
    const QString canonicalConfirmation =
        canonicalComboString(confirmation, &confirmationValid);

    const int tokenCount =
        canonical.split(QLatin1Char('|'), Qt::SkipEmptyParts).size();

    if (!comboValid ||
            tokenCount < MinimumComboLength ||
            tokenCount > MaximumComboLength) {
        setLastError(QStringLiteral(
            "Controller combo must contain %1 to %2 supported inputs")
            .arg(MinimumComboLength)
            .arg(MaximumComboLength));
        return false;
    }

    QByteArray comboBytes = canonical.toUtf8();
    QByteArray confirmationBytes = canonicalConfirmation.toUtf8();

    if (!confirmationValid ||
            !constantTimeEquals(comboBytes, confirmationBytes)) {
        secureClear(comboBytes);
        secureClear(confirmationBytes);
        setLastError(QStringLiteral(
            "Controller combo confirmation does not match"));
        return false;
    }

    QVariantMap payload;
    payload.insert(QStringLiteral("username"), m_activeUsername);
    payload.insert(QStringLiteral("comboLength"), tokenCount);

    if (!beginOperation(OperationKind::CreateCombo,
                        QStringLiteral("createLoginCombo"),
                        payload)) {
        secureClear(comboBytes);
        secureClear(confirmationBytes);
        return false;
    }

    dispatchComboCreation(
        m_activeUsername,
        comboBytes,
        confirmationBytes,
        m_operationSerial);

    secureClear(comboBytes);
    secureClear(confirmationBytes);
    return true;
}

bool SecurityManager::beginLoginComboChange(
    const QString &username,
    const QString &currentRollingBuffer,
    const QString &newCombo,
    const QString &confirmation)
{
    if (m_operationBusy)
        return false;

    if (!usernameMatchesActiveUser(username)) {
        setLastError(QStringLiteral(
            "Combo change must target the active local user"));
        return false;
    }

    if (!setupAuthorizationValid()) {
        setLastError(QStringLiteral(
            "Local account verification is required before changing the login combo"));
        return false;
    }

    if (!m_comboRecord.valid)
        loadActiveUserState();

    if (!m_comboRecord.valid) {
        setLastError(QStringLiteral("No existing login combo is configured"));
        return false;
    }

    bool newValid = false;
    bool confirmationValid = false;
    const QString canonicalNew =
        canonicalComboString(newCombo, &newValid);
    const QString canonicalConfirmation =
        canonicalComboString(confirmation, &confirmationValid);

    const int newTokenCount =
        canonicalNew.split(QLatin1Char('|'), Qt::SkipEmptyParts).size();

    if (!newValid ||
            newTokenCount < MinimumComboLength ||
            newTokenCount > MaximumComboLength) {
        setLastError(QStringLiteral(
            "New controller combo must contain %1 to %2 supported inputs")
            .arg(MinimumComboLength)
            .arg(MaximumComboLength));
        return false;
    }

    QByteArray newBytes = canonicalNew.toUtf8();
    QByteArray confirmationBytes = canonicalConfirmation.toUtf8();

    if (!confirmationValid ||
            !constantTimeEquals(newBytes, confirmationBytes)) {
        secureClear(newBytes);
        secureClear(confirmationBytes);
        setLastError(QStringLiteral(
            "New controller combo confirmation does not match"));
        return false;
    }

    const bool recoveryAuthorized =
        currentRollingBuffer.trimmed().isEmpty() &&
        setupAuthorizationValid();

    QByteArray currentWindowBytes;
    if (!recoveryAuthorized) {
        bool currentValid = false;
        const QStringList currentWindow =
            finalVerificationWindow(
                currentRollingBuffer,
                m_comboRecord.tokenCount,
                &currentValid);

        if (!currentValid) {
            secureClear(newBytes);
            secureClear(confirmationBytes);
            setLastError(QStringLiteral("Current controller combo is invalid"));
            return false;
        }

        currentWindowBytes = canonicalCombo(currentWindow).toUtf8();
    }

    QVariantMap payload;
    payload.insert(QStringLiteral("username"), m_activeUsername);
    payload.insert(QStringLiteral("comboLength"), newTokenCount);
    payload.insert(QStringLiteral("recoveryAuthorized"), recoveryAuthorized);

    if (!beginOperation(OperationKind::ChangeCombo,
                        QStringLiteral("changeLoginCombo"),
                        payload)) {
        secureClear(currentWindowBytes);
        secureClear(newBytes);
        secureClear(confirmationBytes);
        return false;
    }

    dispatchComboChange(
        m_activeUsername,
        currentWindowBytes,
        newBytes,
        confirmationBytes,
        m_comboRecord,
        recoveryAuthorized,
        m_operationSerial);

    secureClear(currentWindowBytes);
    secureClear(newBytes);
    secureClear(confirmationBytes);
    return true;
}

bool SecurityManager::beginLoginComboVerification(
    const QString &username,
    const QString &rollingBuffer)
{
    if (m_operationBusy)
        return false;

    if (!usernameMatchesActiveUser(username)) {
        setLastError(QStringLiteral(
            "Combo verification must target the active local user"));
        return false;
    }

    updateLockoutState();

    if (m_lockedOut) {
        const QString message = QStringLiteral("Login is temporarily locked");
        setLastError(message);
        emit loginComboVerificationFinished(
            false, message, m_failedAttempts, m_secondsRemaining);
        emit unlockDenied(message, m_failedAttempts, m_secondsRemaining);
        return false;
    }

    if (!m_comboRecord.valid)
        loadActiveUserState();

    if (!m_comboRecord.valid) {
        const QString message =
            QStringLiteral("A login combo has not been configured");
        setLastError(message);
        emit loginComboVerificationFinished(
            false, message, m_failedAttempts, m_secondsRemaining);
        return false;
    }

    bool bufferValid = false;
    const QStringList bufferTokens =
        tokenizeCombo(rollingBuffer, &bufferValid, true);

    if (!bufferValid) {
        setLastError(QStringLiteral(
            "Controller input contains an unsupported or reserved input"));
        return false;
    }

    if (bufferTokens.size() < m_comboRecord.tokenCount) {
        setLastError(QStringLiteral("Controller input sequence is incomplete"));
        return false;
    }

    bool windowValid = false;
    const QStringList window =
        finalVerificationWindow(
            rollingBuffer,
            m_comboRecord.tokenCount,
            &windowValid);

    if (!windowValid)
        return false;

    QByteArray canonicalWindow = canonicalCombo(window).toUtf8();

    QVariantMap payload;
    payload.insert(QStringLiteral("username"), m_activeUsername);
    payload.insert(QStringLiteral("rollingTokenCount"), bufferTokens.size());
    payload.insert(QStringLiteral("comboLength"), m_comboRecord.tokenCount);

    if (!beginOperation(OperationKind::VerifyCombo,
                        QStringLiteral("verifyLoginCombo"),
                        payload)) {
        secureClear(canonicalWindow);
        return false;
    }

    dispatchComboVerification(
        m_activeUsername,
        canonicalWindow,
        m_comboRecord,
        m_operationSerial);

    secureClear(canonicalWindow);
    return true;
}

void SecurityManager::setNotificationManager(NotificationManager *manager)
{
    m_notificationManager = manager;
}

bool SecurityManager::beginAuthenticatedNotificationClear(
    const QString &username,
    const QString &rollingBuffer)
{
    // This method is the only QML-visible entry point to the protected clear.
    // Active-user binding and the existing Argon2/lockout verifier are mandatory.
    if (!m_notificationManager || !usernameMatchesActiveUser(username) ||
            m_activeUser.value(QStringLiteral("username")).toString() != m_activeUsername)
        return false;
    if (!beginLoginComboVerification(username, rollingBuffer))
        return false;
    m_notificationClearPending = true;
    m_notificationClearSerial = m_operationSerial;
    m_notificationClearUser = m_activeUsername;
    return true;
}

bool SecurityManager::hasLoginCombo(const QString &username)
{
    const QString clean = cleanUsername(username);
    if (clean.isEmpty())
        return false;

    migrateLegacyComboForUser(clean);
    const ComboRecord record = readComboRecord(clean);

    if (clean == m_activeUsername) {
        applyComboRecord(record);
        const QString recordPath = comboFilePath(clean);
        const bool recordExists = QFileInfo::exists(recordPath);
        setLoginConfigurationState(LoginConfiguration::fromLocalEvidence(
            true,
            recordExists,
            !recordExists || pathIsRootOwnedOwnerOnly(recordPath, false),
            record.valid,
            authoritativeSetupCompleted()));
        rebuildPublicState();
    }

    return record.valid;
}

bool SecurityManager::createLoginCombo(
    const QString &username,
    const QString &normalizedCombo)
{
    if (m_activeUsername.isEmpty() && !setActiveUsername(username))
        return false;

    if (!usernameMatchesActiveUser(username) ||
            !setupAuthorizationValid()) {
        setLastError(QStringLiteral(
            "Local account verification is required before creating a login combo"));
        return false;
    }

    bool valid = false;
    const QString canonical =
        canonicalComboString(normalizedCombo, &valid);
    const int tokenCount =
        canonical.split(QLatin1Char('|'), Qt::SkipEmptyParts).size();

    if (!valid ||
            tokenCount < MinimumComboLength ||
            tokenCount > MaximumComboLength) {
        return false;
    }

    QByteArray canonicalBytes = canonical.toUtf8();

    ComboRecord record;
    record.version = 3;
    record.username = m_activeUsername;
    record.kdf = QStringLiteral("argon2id");
    record.scheme = QStringLiteral("libsodium-crypto-pwhash-str");
    record.encodedHash = argon2idHashCombo(canonicalBytes);
    record.tokenCount = tokenCount;
    record.createdAtUtc = QDateTime::currentDateTimeUtc();
    record.updatedAtUtc = record.createdAtUtc;
    record.valid = !record.encodedHash.isEmpty();

    secureClear(canonicalBytes);

    if (!record.valid || !saveComboRecord(record)) {
        setLastError(QStringLiteral(
            "Login combo could not be stored securely"));
        return false;
    }

    applyComboRecord(record);
    clearSetupAuthorization();
    resetFailuresAfterVerifiedAuthentication();
    rebuildPublicState();
    rebuildWatchers();
    return true;
}

bool SecurityManager::verifyLoginCombo(
    const QString &username,
    const QString &rollingBuffer)
{
    if (m_activeUsername.isEmpty() && !setActiveUsername(username))
        return false;

    if (!usernameMatchesActiveUser(username))
        return false;

    updateLockoutState();
    if (m_lockedOut)
        return false;

    if (!m_comboRecord.valid)
        loadActiveUserState();
    if (!m_comboRecord.valid)
        return false;

    bool bufferValid = false;
    const QStringList bufferTokens =
        tokenizeCombo(rollingBuffer, &bufferValid, true);

    if (!bufferValid ||
            bufferTokens.size() < m_comboRecord.tokenCount) {
        return false;
    }

    bool windowValid = false;
    const QStringList window =
        finalVerificationWindow(
            rollingBuffer,
            m_comboRecord.tokenCount,
            &windowValid);

    if (!windowValid)
        return false;

    QByteArray canonicalBytes = canonicalCombo(window).toUtf8();

    bool success = false;
    bool legacySuccess = false;

    if (m_comboRecord.kdf.contains(
            QStringLiteral("argon"), Qt::CaseInsensitive)) {
        success = verifyArgon2idCombo(
            canonicalBytes, m_comboRecord.encodedHash);

        if (!success && m_comboRecord.version < 3) {
            QByteArray legacyCanonical =
                legacyDirectionCanonical(canonicalBytes);
            success = verifyArgon2idCombo(
                legacyCanonical, m_comboRecord.encodedHash);
            legacySuccess = success;
            secureClear(legacyCanonical);
        }
    } else if (m_comboRecord.kdf.contains(
                   QStringLiteral("pbkdf2"), Qt::CaseInsensitive)) {
        const QJsonDocument document =
            QJsonDocument::fromJson(m_comboRecord.encodedHash);
        if (document.isObject()) {
            legacySuccess =
                verifyLegacyPbkdf2Record(document.object(), canonicalBytes);
            success = legacySuccess;
        }
    }

    if (success && legacySuccess) {
        ComboRecord migrated;
        migrated.version = 3;
        migrated.username = m_activeUsername;
        migrated.kdf = QStringLiteral("argon2id");
        migrated.scheme = QStringLiteral("libsodium-crypto-pwhash-str");
        migrated.encodedHash = argon2idHashCombo(canonicalBytes);
        migrated.tokenCount = m_comboRecord.tokenCount;
        migrated.createdAtUtc =
            m_comboRecord.createdAtUtc.isValid()
                ? m_comboRecord.createdAtUtc
                : QDateTime::currentDateTimeUtc();
        migrated.updatedAtUtc = QDateTime::currentDateTimeUtc();
        migrated.valid = !migrated.encodedHash.isEmpty();

        if (migrated.valid && saveComboRecord(migrated))
            applyComboRecord(migrated);
    }

    secureClear(canonicalBytes);

    if (success) {
        resetFailuresAfterVerifiedAuthentication();
        return true;
    }

    if (bufferTokens.size() >= MaximumRollingInputs) {
        registerFailedAttemptWithReason(
            QStringLiteral("incorrect controller combo"));
    }

    return false;
}

bool SecurityManager::loginComboConfiguredForUser(const QString &username)
{
    return hasLoginCombo(username);
}

bool SecurityManager::comboConfigured(const QString &username)
{
    return hasLoginCombo(username);
}

bool SecurityManager::verifyCombo(
    const QString &username,
    const QString &rollingBuffer)
{
    return verifyLoginCombo(username, rollingBuffer);
}

bool SecurityManager::setLoginCombo(
    const QString &username,
    const QString &normalizedCombo)
{
    return createLoginCombo(username, normalizedCombo);
}

bool SecurityManager::isValidComboFormat(const QString &combo) const
{
    bool valid = false;
    const QStringList tokens = tokenizeCombo(combo, &valid, false);
    return valid &&
           tokens.size() >= MinimumComboLength &&
           tokens.size() <= MaximumComboLength;
}

int SecurityManager::normalizedComboTokenCount(const QString &combo) const
{
    bool valid = false;
    const QStringList tokens = tokenizeCombo(combo, &valid, false);
    return valid ? tokens.size() : 0;
}

bool SecurityManager::registerFailedAttempt()
{
    return registerFailedAttemptWithReason(QStringLiteral("unspecified"));
}

bool SecurityManager::registerFailedAttemptWithReason(const QString &reason)
{
    if (m_activeUsername.isEmpty())
        return false;

    updateLockoutState();

    if (m_lockedOut)
        return true;

    const QString cleanReason = reason.trimmed().toLower();
    if (shouldIgnoreFailureReason(cleanReason) || failureCooldownActive())
        return false;

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    m_lastFailedAttemptMonotonicMs = m_monotonicClock.elapsed();
    m_lastFailureReason =
        cleanReason.isEmpty() ? QStringLiteral("unspecified") : cleanReason;
    ++m_failedAttempts;

    startLockoutForCurrentFailureCount(m_lastFailureReason);
    return m_lockedOut;
}

void SecurityManager::registerHighThreat()
{
    registerHighThreatWithReason(QStringLiteral("unspecified"));
}

void SecurityManager::registerHighThreatWithReason(const QString &reason)
{
    if (m_activeUsername.isEmpty())
        return;

    updateLockoutState();

    if (m_lockedOut)
        return;

    const QString cleanReason = reason.trimmed().toLower();
    if (shouldIgnoreFailureReason(cleanReason) || highThreatCooldownActive())
        return;

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    m_lastHighThreatMonotonicMs = m_monotonicClock.elapsed();
    m_lastHighThreatReason =
        cleanReason.isEmpty() ? QStringLiteral("unspecified") : cleanReason;
    ++m_highThreatAttempts;
    m_failedAttempts += 2;

    const int deterministicDelay =
        delayForFailedAttempts(m_failedAttempts);

    startLockout(
        qMin(qMax(5 * 60, deterministicDelay), m_maxLockoutSeconds),
        m_lastHighThreatReason);
}

void SecurityManager::registerSuccess()
{
    /*
        Existing QML may call registerSuccess() after verifyLoginCombo().
        The verified path has already reset the counters, so that redundant
        compatibility call is an allowed no-op.
    */
    if (!m_lockedOut &&
            m_failedAttempts == 0 &&
            m_highThreatAttempts == 0) {
        return;
    }

    if (!m_pamSessionOpen && !setupAuthorizationValid()) {
        setLastError(QStringLiteral(
            "A verified authentication context is required to clear failures"));
        return;
    }

    resetFailuresAfterVerifiedAuthentication();
}

void SecurityManager::refresh()
{
    refreshSecurityState();
}

void SecurityManager::refreshSecurityState()
{
    if (m_operationBusy) {
        scheduleRefresh();
        return;
    }

    loadActiveUserState();
}

void SecurityManager::clearLockout()
{
    if (!setupAuthorizationValid(QStringLiteral("recovery"))) {
        setLastError(QStringLiteral(
            "Recovery authorization is required to clear the lockout"));
        return;
    }

    resetFailuresAfterVerifiedAuthentication();
    clearSetupAuthorization();
}

void SecurityManager::cancelPendingOperation()
{
    ++m_operationSerial;

    const QString action = m_activeOperation;
    const QVariantMap payload = m_pendingSafePayload;

    clearPendingOperation();
    setOperationBusy(false);
    clearSetupAuthorization();
    setLastOperation(QStringLiteral("Security operation cancelled locally"));

    if (!action.isEmpty()) {
        emit operationFinished(
            action,
            false,
            QStringLiteral("Operation cancelled locally"),
            payload);
    }

    rebuildPublicState();
}

void SecurityManager::clearSetupAuthorization()
{
    const bool hadAuthorization = m_setupAuthorization.valid;
    m_setupAuthorization = SetupAuthorization();
    m_setupAuthorizationTimer.stop();

    if (hadAuthorization) {
        emit setupAuthorizationChanged();
        emit stateChanged();
        incrementSecurityRevision();
    }
}

void SecurityManager::clearTransientSecrets()
{
    clearSetupAuthorization();
    m_pendingSafePayload.clear();
}

bool SecurityManager::migrateLegacyUserState()
{
    ensureSecurityDir();

    const QStringList sourceDirectories = {
        legacySecurityDirPath(),
        securityDirPath()
    };

    bool migrated = false;

    for (const QString &directoryPath : sourceDirectories) {
        QDir directory(directoryPath);
        if (!directory.exists())
            continue;

        const QStringList files = directory.entryList(
            QStringList() << QStringLiteral("login_combo*.hash"),
            QDir::Files | QDir::NoDotAndDotDot);

        for (const QString &fileName : files) {
            const QByteArray data =
                readFile(directory.absoluteFilePath(fileName));
            if (data.isEmpty())
                continue;

            const QJsonDocument document = QJsonDocument::fromJson(data);
            if (!document.isObject())
                continue;

            QJsonObject object = document.object();
            QString username = cleanUsername(
                object.value(QStringLiteral("username")).toString());

            if (username.isEmpty() &&
                    fileName == QStringLiteral("login_combo.hash")) {
                username = QStringLiteral("neutronos");
            }

            if (username.isEmpty() || !localAccountExists(username))
                continue;

            const QString target = comboFilePath(username);
            if (QFileInfo::exists(target))
                continue;

            object.insert(QStringLiteral("username"), username);
            if (writeSecureJsonFile(
                    target,
                    QJsonDocument(object).toJson(QJsonDocument::Indented))) {
                migrated = true;
            }
        }
    }

    if (!m_activeUsername.isEmpty() &&
            migrateLegacyComboForUser(m_activeUsername)) {
        migrated = true;
    }

    rebuildWatchers();
    return migrated;
}


QString SecurityManager::neutronRootPath() const
{
    const QString configured = envValue("NEUTRONOS_ROOT");
    if (!configured.isEmpty())
        return QDir::cleanPath(configured);

    const QString home = m_activeUser.value(
        QStringLiteral("homeDirectory")).toString().trimmed();

    if (!home.isEmpty())
        return QDir::cleanPath(home + QStringLiteral("/NeutronOS"));

    return QDir::cleanPath(
        QDir::homePath() + QStringLiteral("/NeutronOS"));
}

QString SecurityManager::legacySecurityDirPath() const
{
    return neutronRootPath() + QStringLiteral("/state/security");
}

QString SecurityManager::usersSecurityDirPath() const
{
    return securityDirPath() + QStringLiteral("/users");
}

QString SecurityManager::activeUserSecurityDirPath() const
{
    return m_activeUsername.isEmpty()
        ? QString()
        : usersSecurityDirPath() + QLatin1Char('/') + m_activeUsername;
}

QString SecurityManager::lockoutStateFilePath() const
{
    const QString directory = activeUserSecurityDirPath();
    return directory.isEmpty()
        ? QString()
        : directory + QStringLiteral("/state.json");
}

QString SecurityManager::comboFilePath(const QString &username) const
{
    const QString clean = cleanUsername(username);
    return clean.isEmpty()
        ? QString()
        : usersSecurityDirPath() + QLatin1Char('/') + clean +
          QStringLiteral("/combo.json");
}

QString SecurityManager::legacyComboFilePath(const QString &username) const
{
    const QString clean = cleanUsername(username);
    return clean.isEmpty()
        ? QString()
        : oldFlatPath(legacySecurityDirPath(), clean);
}

bool SecurityManager::authoritativeSetupCompleted() const
{
    QFile file(QStringLiteral("/var/lib/neutronos/setup/setup.json"));
    if (!file.open(QIODevice::ReadOnly))
        return false;

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    return error.error == QJsonParseError::NoError &&
           document.isObject() &&
           document.object().value(QStringLiteral("completed")).toBool(false);
}

void SecurityManager::ensureSecurityDir() const
{
    const QString stateRoot = QStringLiteral(NEUTRONOS_STATE_DIR);
    if (!QDir().mkpath(stateRoot))
        return;


    ensureSecureDirectory(securityDirPath());
    ensureSecureDirectory(usersSecurityDirPath());

    if (!m_activeUsername.isEmpty())
        ensureSecureDirectory(activeUserSecurityDirPath());
}

bool SecurityManager::ensureSecureDirectory(const QString &path) const
{
    if (path.isEmpty())
        return false;

    /*
        Security state may be provisioned by the root-owned setup service while
        NeutronShell itself runs as the desktop account.  Existing root-owned,
        owner-only directories are already trusted and must not be chmod/chown'd
        by the unprivileged shell.  Treating that intentional ownership split as
        unsafe caused readPersistentState() to synthesize a maximum lockout on
        every service restart.
    */
    if (QFileInfo::exists(path))
        return pathIsRootOwnedOwnerOnly(path, true);

    if (!QDir().mkpath(path))
        return false;

    return setOwnerOnlyPermissions(path, true) &&
           setOwnerRootOnly(path) &&
           pathIsRootOwnedOwnerOnly(path, true);
}

bool SecurityManager::setOwnerRootOnly(const QString &path) const
{
#ifdef Q_OS_LINUX
    const QByteArray bytes = path.toLocal8Bit();
    struct stat state;
    if (::lstat(bytes.constData(), &state) != 0 || S_ISLNK(state.st_mode))
        return false;
    return state.st_uid == ::geteuid() && state.st_gid == ::getegid();
#else
    Q_UNUSED(path)
    return true;
#endif
}

bool SecurityManager::setOwnerOnlyPermissions(
    const QString &path,
    bool executable) const
{
    QFileDevice::Permissions permissions =
        QFileDevice::ReadOwner | QFileDevice::WriteOwner;
    if (executable)
        permissions |= QFileDevice::ExeOwner;

    const bool qtOk = QFile::setPermissions(path, permissions);

#ifdef Q_OS_LINUX
    const QByteArray bytes = path.toLocal8Bit();
    const mode_t mode = executable
        ? static_cast<mode_t>(0700)
        : static_cast<mode_t>(0600);
    return qtOk && ::chmod(bytes.constData(), mode) == 0;
#else
    return qtOk;
#endif
}

bool SecurityManager::pathIsRootOwnedOwnerOnly(
    const QString &path,
    bool directory) const
{
#ifdef Q_OS_LINUX
    const QByteArray bytes = path.toLocal8Bit();
    struct stat state;

    if (::lstat(bytes.constData(), &state) != 0 || S_ISLNK(state.st_mode))
        return false;

    if (directory && !S_ISDIR(state.st_mode))
        return false;
    if (!directory && !S_ISREG(state.st_mode))
        return false;

    const uid_t effectiveUid = ::geteuid();
    const gid_t effectiveGid = ::getegid();

    const bool ownedByRoot =
        state.st_uid == static_cast<uid_t>(0) &&
        state.st_gid == static_cast<gid_t>(0);
    const bool ownedByServiceAccount =
        state.st_uid == effectiveUid &&
        state.st_gid == effectiveGid;
    const uid_t accountUid = static_cast<uid_t>(
        m_activeUser.value(QStringLiteral("uid"), qulonglong(-1)).toULongLong());
    const gid_t accountGid = static_cast<gid_t>(
        m_activeUser.value(QStringLiteral("gid"), qulonglong(-1)).toULongLong());
    const bool ownedByActiveAccount =
        !m_activeUsername.isEmpty() &&
        state.st_uid == accountUid && state.st_gid == accountGid;

    return (ownedByRoot || ownedByServiceAccount || ownedByActiveAccount) &&
           (state.st_mode & (S_IRWXG | S_IRWXO)) == 0;
#else
    Q_UNUSED(path)
    Q_UNUSED(directory)
    return true;
#endif
}

bool SecurityManager::securityDirectoryLooksSafe() const
{
    if (!pathIsRootOwnedOwnerOnly(securityDirPath(), true) ||
            !pathIsRootOwnedOwnerOnly(usersSecurityDirPath(), true)) {
        return false;
    }

    if (!m_activeUsername.isEmpty() &&
            QFileInfo::exists(activeUserSecurityDirPath()) &&
            !pathIsRootOwnedOwnerOnly(activeUserSecurityDirPath(), true)) {
        return false;
    }

    return true;
}

QString SecurityManager::cleanUsername(const QString &username) const
{
    const QString clean = username.trimmed();
    return safeUserName(clean) ? clean : QString();
}

bool SecurityManager::localAccountExists(
    const QString &username,
    QVariantMap *validatedUser) const
{
    const QString clean = cleanUsername(username);
    if (clean.isEmpty())
        return false;

#ifdef Q_OS_LINUX
    long size = sysconf(_SC_GETPW_R_SIZE_MAX);
    if (size < 1024)
        size = 16384;

    std::vector<char> buffer(static_cast<std::size_t>(size));
    struct passwd entry;
    struct passwd *result = nullptr;
    const QByteArray encoded = clean.toLocal8Bit();

    if (getpwnam_r(
            encoded.constData(),
            &entry,
            buffer.data(),
            buffer.size(),
            &result) != 0 ||
            !result) {
        return false;
    }

    if (validatedUser) {
        QVariantMap user;
        QString displayName =
            passwdString(result->pw_gecos)
                .section(QLatin1Char(','), 0, 0)
                .trimmed();

        if (displayName.isEmpty())
            displayName = clean;

        user.insert(QStringLiteral("id"), clean);
        user.insert(QStringLiteral("userId"), clean);
        user.insert(QStringLiteral("username"), clean);
        user.insert(QStringLiteral("accountName"), clean);
        user.insert(QStringLiteral("displayName"), displayName);
        user.insert(QStringLiteral("name"), displayName);
        user.insert(QStringLiteral("uid"),
                    static_cast<qulonglong>(result->pw_uid));
        user.insert(QStringLiteral("gid"),
                    static_cast<qulonglong>(result->pw_gid));
        user.insert(QStringLiteral("homeDirectory"),
                    passwdString(result->pw_dir));
        user.insert(QStringLiteral("home"),
                    user.value(QStringLiteral("homeDirectory")));
        user.insert(QStringLiteral("shell"),
                    passwdString(result->pw_shell));
        user.insert(QStringLiteral("local"), true);
        user.insert(QStringLiteral("valid"), true);
        *validatedUser = user;
    }

    return true;
#else
    if (validatedUser) {
        QVariantMap user;
        user.insert(QStringLiteral("id"), clean);
        user.insert(QStringLiteral("userId"), clean);
        user.insert(QStringLiteral("username"), clean);
        user.insert(QStringLiteral("displayName"), clean);
        user.insert(QStringLiteral("name"), clean);
        user.insert(QStringLiteral("homeDirectory"), QDir::homePath());
        user.insert(QStringLiteral("local"), true);
        user.insert(QStringLiteral("valid"), true);
        *validatedUser = user;
    }
    return true;
#endif
}

bool SecurityManager::validateActiveUserContext(
    const QVariantMap &userContext,
    QVariantMap *validatedUser,
    QString *errorMessage) const
{
    const QString username = cleanUsername(mapText(
        userContext,
        QStringList()
            << QStringLiteral("username")
            << QStringLiteral("accountName")
            << QStringLiteral("userId")
            << QStringLiteral("id")));

    if (username.isEmpty()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("A valid local username is required");
        return false;
    }

    QVariantMap user;
    if (!localAccountExists(username, &user)) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("Local account '%1' was not found")
                .arg(username);
        }
        return false;
    }

    const QString displayName = mapText(
        userContext,
        QStringList()
            << QStringLiteral("displayName")
            << QStringLiteral("name"));

    if (!displayName.isEmpty()) {
        user.insert(QStringLiteral("displayName"), displayName);
        user.insert(QStringLiteral("name"), displayName);
    }

    const QString avatar = mapText(
        userContext,
        QStringList()
            << QStringLiteral("icon")
            << QStringLiteral("avatar")
            << QStringLiteral("avatarSource"));

    if (!avatar.isEmpty()) {
        user.insert(QStringLiteral("icon"), avatar);
        user.insert(QStringLiteral("avatar"), avatar);
        user.insert(QStringLiteral("avatarSource"), avatar);
    }

    if (validatedUser)
        *validatedUser = user;
    if (errorMessage)
        errorMessage->clear();

    return true;
}

bool SecurityManager::usernameMatchesActiveUser(const QString &username) const
{
    const QString clean = cleanUsername(username);
    return !clean.isEmpty() && clean == m_activeUsername;
}

void SecurityManager::loadState()
{
    loadActiveUserState();
}

void SecurityManager::loadActiveUserState()
{
    if (m_activeUsername.isEmpty()) {
        applyPersistentState(PersistentState());
        applyComboRecord(ComboRecord());
        rebuildPublicState();
        setLoginConfigurationState(LoginConfiguration::State::LoadingUnknown);
        return;
    }

    ensureSecurityDir();
    migrateLegacyComboForUser(m_activeUsername);
    applyPersistentState(readPersistentState());
    const QString recordPath = comboFilePath(m_activeUsername);
    const bool recordExists = QFileInfo::exists(recordPath);
    const bool ownerTrusted = !recordExists || pathIsRootOwnedOwnerOnly(recordPath, false);
    const ComboRecord record = readComboRecord(m_activeUsername);
    applyComboRecord(record);
    setLoginConfigurationState(LoginConfiguration::fromLocalEvidence(
        true, recordExists, ownerTrusted, record.valid,
        authoritativeSetupCompleted()));
    rebuildPublicState();
    rebuildWatchers();
}

SecurityManager::PersistentState SecurityManager::readPersistentState() const
{
    PersistentState state;
    state.username = m_activeUsername;
    state.valid = !m_activeUsername.isEmpty();

    const QString statePath = lockoutStateFilePath();
    const uid_t accountUid = static_cast<uid_t>(
        m_activeUser.value(QStringLiteral("uid"), qulonglong(-1)).toULongLong());
    const gid_t accountGid = static_cast<gid_t>(
        m_activeUser.value(QStringLiteral("gid"), qulonglong(-1)).toULongLong());
    if (QFileInfo::exists(statePath) &&
            !trustedLockoutStateFile(statePath, accountUid, accountGid)) {
        /*
            Never manufacture a one-hour lockout from a metadata mismatch.
            A lockout state file is trusted only when it is a regular file,
            owned by root or the running service account, and not writable by
            another account.  An untrusted file is ignored and logged instead
            of denying the local owner access to the machine.
        */
        qWarning() << "Ignoring unsafe lockout state file instead of synthesizing a lockout:"
                   << statePath;
        state.lastFailureReason = QStringLiteral("ignored unsafe persistent security state");
        return state;
    }

    const QByteArray data = readFile(statePath);
    if (data.isEmpty())
        return state;

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(data, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return state;

    const QJsonObject object = document.object();
    const QString storedUser = cleanUsername(
        object.value(QStringLiteral("username")).toString());

    if (!storedUser.isEmpty() && storedUser != m_activeUsername)
        return state;

    state.version = object.value(QStringLiteral("version")).toInt(3);
    state.failedAttempts = qBound(
        0,
        object.value(QStringLiteral("failedAttempts")).toInt(),
        1000000);
    state.highThreatAttempts = qBound(
        0,
        object.value(QStringLiteral("highThreatAttempts")).toInt(),
        1000000);
    state.lockedOut =
        object.value(QStringLiteral("lockedOut")).toBool(false);
    state.lockoutDelaySeconds = qBound(
        0,
        object.value(QStringLiteral("lockoutDelaySeconds")).toInt(),
        m_maxLockoutSeconds);
    state.lockoutLevel = qBound(
        0,
        object.value(QStringLiteral("lockoutLevel")).toInt(),
        5);
    state.lastFailureReason =
        object.value(QStringLiteral("lastFailureReason")).toString();
    state.lastHighThreatReason =
        object.value(QStringLiteral("lastHighThreatReason")).toString();
    state.lastSuccessfulLoginUtc = parseUtc(
        object.value(QStringLiteral("lastSuccessfulLoginUtc")));
    state.valid = true;
    return state;
}

SecurityManager::ComboRecord SecurityManager::readComboRecord(
    const QString &username) const
{
    ComboRecord record;
    const QString clean = cleanUsername(username);
    if (clean.isEmpty())
        return record;

    const QString recordPath = comboFilePath(clean);
    if (QFileInfo::exists(recordPath) &&
            !pathIsRootOwnedOwnerOnly(recordPath, false)) {
        return record;
    }

    const QByteArray data = readFile(recordPath);
    if (data.isEmpty())
        return record;

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(data, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return record;

    const QJsonObject object = document.object();
    record.version = object.value(QStringLiteral("version")).toInt(2);
    record.username = cleanUsername(
        object.value(QStringLiteral("username")).toString());
    if (record.username.isEmpty())
        record.username = clean;

    record.kdf =
        object.value(QStringLiteral("kdf")).toString().trimmed().toLower();
    record.scheme =
        object.value(QStringLiteral("scheme")).toString().trimmed();
    record.tokenCount =
        object.value(QStringLiteral("tokenCount")).toInt(
            object.value(QStringLiteral("comboLength")).toInt());

    record.createdAtUtc =
        parseUtc(object.value(QStringLiteral("createdAtUtc")));
    if (!record.createdAtUtc.isValid())
        record.createdAtUtc =
            parseUtc(object.value(QStringLiteral("createdAt")));

    record.updatedAtUtc =
        parseUtc(object.value(QStringLiteral("updatedAtUtc")));
    if (!record.updatedAtUtc.isValid())
        record.updatedAtUtc =
            parseUtc(object.value(QStringLiteral("updatedAt")));

    const bool lengthValid =
        record.tokenCount >= MinimumComboLength &&
        record.tokenCount <= MaximumRollingInputs;

    if (record.kdf.contains(QStringLiteral("argon"))) {
        record.encodedHash =
            object.value(QStringLiteral("hash")).toString().toLatin1();
        record.valid =
            record.username == clean &&
            lengthValid &&
            record.encodedHash.startsWith(QByteArrayLiteral("$argon2"));
    } else if (record.kdf.contains(QStringLiteral("pbkdf2"))) {
        record.encodedHash = document.toJson(QJsonDocument::Compact);

        const int iterations =
            object.value(QStringLiteral("iterations")).toInt();
        const QByteArray salt = QByteArray::fromBase64(
            object.value(QStringLiteral("salt")).toString().toLatin1());

        QByteArray digest = QByteArray::fromBase64(
            object.value(QStringLiteral("hash")).toString().toLatin1());
        if (digest.isEmpty()) {
            digest = QByteArray::fromBase64(
                object.value(QStringLiteral("digest")).toString().toLatin1());
        }

        record.valid =
            record.username == clean &&
            lengthValid &&
            iterations >= 100000 &&
            iterations <= 5000000 &&
            salt.size() >= 16 &&
            !digest.isEmpty();
    }

    return record;
}

bool SecurityManager::saveState()
{
    if (m_activeUsername.isEmpty())
        return false;

    PersistentState state;
    state.version = 3;
    state.username = m_activeUsername;
    state.failedAttempts = m_failedAttempts;
    state.highThreatAttempts = m_highThreatAttempts;
    state.lockedOut = m_lockedOut;
    state.lockoutDelaySeconds = m_lockoutDelaySeconds;
    state.lockoutLevel = m_lockoutLevel;
    state.lastFailureReason = m_lastFailureReason;
    state.lastHighThreatReason = m_lastHighThreatReason;
    state.lastSuccessfulLoginUtc =
        m_persistentState.lastSuccessfulLoginUtc;
    state.valid = true;

    const bool saved = savePersistentState(state);
    if (saved)
        m_persistentState = state;
    return saved;
}

bool SecurityManager::savePersistentState(const PersistentState &state)
{
    if (!state.valid || state.username != m_activeUsername)
        return false;

    QJsonObject object;
    object.insert(QStringLiteral("version"), state.version);
    object.insert(QStringLiteral("username"), state.username);
    object.insert(QStringLiteral("failedAttempts"), state.failedAttempts);
    object.insert(QStringLiteral("highThreatAttempts"), state.highThreatAttempts);
    object.insert(QStringLiteral("lockedOut"), state.lockedOut);
    object.insert(QStringLiteral("lockoutDelaySeconds"),
                  state.lockoutDelaySeconds);
    object.insert(QStringLiteral("lockoutLevel"), state.lockoutLevel);
    object.insert(QStringLiteral("lastFailureReason"),
                  state.lastFailureReason);
    object.insert(QStringLiteral("lastHighThreatReason"),
                  state.lastHighThreatReason);
    object.insert(QStringLiteral("lastSuccessfulLoginUtc"),
                  isoUtc(state.lastSuccessfulLoginUtc));
    object.insert(QStringLiteral("lastStateWriteUtc"),
                  QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));

    return writeSecureJsonFile(
        lockoutStateFilePath(),
        QJsonDocument(object).toJson(QJsonDocument::Indented));
}

bool SecurityManager::saveComboRecord(const ComboRecord &record)
{
    if (!record.valid ||
            record.username != m_activeUsername ||
            !record.kdf.contains(QStringLiteral("argon")) ||
            record.encodedHash.isEmpty()) {
        return false;
    }

    QJsonObject object;
    object.insert(QStringLiteral("version"), 3);
    object.insert(QStringLiteral("username"), record.username);
    object.insert(QStringLiteral("kdf"), QStringLiteral("argon2id"));
    object.insert(QStringLiteral("scheme"),
                  QStringLiteral("libsodium-crypto-pwhash-str"));
    object.insert(QStringLiteral("tokenCount"), record.tokenCount);
    object.insert(QStringLiteral("hash"),
                  QString::fromLatin1(record.encodedHash));
    object.insert(QStringLiteral("createdAtUtc"),
                  isoUtc(record.createdAtUtc));
    object.insert(QStringLiteral("updatedAtUtc"),
                  isoUtc(record.updatedAtUtc));

    return writeSecureJsonFile(
        comboFilePath(record.username),
        QJsonDocument(object).toJson(QJsonDocument::Indented));
}

void SecurityManager::applyPersistentState(const PersistentState &state)
{
    m_persistentState = state;
    m_failedAttempts = state.valid ? state.failedAttempts : 0;
    m_highThreatAttempts = state.valid ? state.highThreatAttempts : 0;
    m_lastFailureReason = state.lastFailureReason;
    m_lastHighThreatReason = state.lastHighThreatReason;
    m_lockoutLevel = levelForFailedAttempts(m_failedAttempts);
    m_lockoutDelaySeconds = delayForFailedAttempts(m_failedAttempts);
    m_lockedOut = false;
    m_secondsRemaining = 0;
    m_lockoutUntilMonotonicMs = 0;

    if (state.valid && state.lockedOut && m_failedAttempts > 0) {
        const int delay = qMax(1, m_lockoutDelaySeconds);
        if (!m_monotonicClock.isValid())
            m_monotonicClock.start();

        m_lockedOut = true;
        m_secondsRemaining = delay;
        m_lockoutUntilMonotonicMs =
            m_monotonicClock.elapsed() +
            static_cast<qint64>(delay) * 1000;

        if (!m_lockoutRefreshTimer.isActive())
            m_lockoutRefreshTimer.start();
    } else {
        m_lockoutRefreshTimer.stop();
    }
}

void SecurityManager::applyComboRecord(const ComboRecord &record)
{
    m_comboRecord = record;
    setLoginComboConfigured(
        record.valid,
        record.valid ? record.tokenCount : 0);
}

void SecurityManager::rebuildPublicState()
{
    const bool configured =
        m_comboRecord.valid &&
        m_comboRecord.username == m_activeUsername;

    const int length = configured ? m_comboRecord.tokenCount : 0;

    if (m_loginComboConfigured != configured || m_comboLength != length) {
        m_loginComboConfigured = configured;
        m_comboLength = length;
        emit stateChanged();
    }

    emit securityDirectoryStateChanged();
    incrementSecurityRevision();
}

void SecurityManager::setLoginConfigurationState(LoginConfiguration::State state)
{
    if (m_loginConfigurationState == state)
        return;
    m_loginConfigurationState = state;
    emit loginConfigurationStateChanged();
}

void SecurityManager::incrementSecurityRevision()
{
    ++m_securityRevision;
    if (m_securityRevision > 1000000000)
        m_securityRevision = 1;
    emit securityRevisionChanged();
}

void SecurityManager::startLockoutForCurrentFailureCount(
    const QString &reason)
{
    const int delay = delayForFailedAttempts(m_failedAttempts);
    if (delay > 0)
        startLockout(delay, reason);
}

void SecurityManager::startLockout(int seconds, const QString &reason)
{
    const int safeSeconds = qBound(1, seconds, m_maxLockoutSeconds);

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    m_lockoutDelaySeconds = safeSeconds;
    m_lockoutLevel = levelForFailedAttempts(m_failedAttempts);
    m_secondsRemaining = safeSeconds;
    m_lockedOut = true;
    m_lockoutUntilMonotonicMs =
        m_monotonicClock.elapsed() +
        static_cast<qint64>(safeSeconds) * 1000;

    if (!reason.trimmed().isEmpty())
        m_lastFailureReason = reason.trimmed().toLower();

    saveState();

    if (!m_lockoutRefreshTimer.isActive())
        m_lockoutRefreshTimer.start();

    emit lockoutStarted();
    emit stateChanged();
    incrementSecurityRevision();
}

void SecurityManager::resetFailuresAfterVerifiedAuthentication()
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
    m_persistentState.lastSuccessfulLoginUtc =
        QDateTime::currentDateTimeUtc();

    m_lockoutRefreshTimer.stop();
    saveState();

    if (wasLockedOut)
        emit lockoutCleared();

    emit stateChanged();
    incrementSecurityRevision();
}

void SecurityManager::updateLockoutState()
{
    if (!m_lockedOut) {
        m_secondsRemaining = 0;
        m_lockoutDelaySeconds =
            delayForFailedAttempts(m_failedAttempts);
        m_lockoutLevel =
            levelForFailedAttempts(m_failedAttempts);
        m_lockoutRefreshTimer.stop();
        return;
    }

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    const qint64 remainingMs =
        m_lockoutUntilMonotonicMs - m_monotonicClock.elapsed();

    if (remainingMs > 0) {
        const int seconds =
            static_cast<int>((remainingMs + 999) / 1000);
        if (seconds != m_secondsRemaining) {
            m_secondsRemaining = seconds;
            emit stateChanged();
        }
        return;
    }

    m_lockedOut = false;
    m_secondsRemaining = 0;
    m_lockoutUntilMonotonicMs = 0;
    m_lockoutDelaySeconds =
        delayForFailedAttempts(m_failedAttempts);
    m_lockoutLevel =
        levelForFailedAttempts(m_failedAttempts);
    m_lockoutRefreshTimer.stop();
    saveState();

    emit lockoutCleared();
    emit stateChanged();
    incrementSecurityRevision();
}

int SecurityManager::delayForFailedAttempts(int attempts) const
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

int SecurityManager::levelForFailedAttempts(int attempts) const
{
    return attempts <= 0 ? 0 : qMin(5, attempts);
}

bool SecurityManager::failureCooldownActive() const
{
    return m_monotonicClock.isValid() &&
           m_lastFailedAttemptMonotonicMs >= 0 &&
           m_monotonicClock.elapsed() -
               m_lastFailedAttemptMonotonicMs <
               m_failedAttemptCooldownMs;
}

bool SecurityManager::highThreatCooldownActive() const
{
    return m_monotonicClock.isValid() &&
           m_lastHighThreatMonotonicMs >= 0 &&
           m_monotonicClock.elapsed() -
               m_lastHighThreatMonotonicMs <
               m_highThreatCooldownMs;
}

bool SecurityManager::shouldIgnoreFailureReason(const QString &reason) const
{
    const QString lower = reason.trimmed().toLower();
    return lower.isEmpty() ||
           lower.contains(QStringLiteral("motion")) ||
           lower.contains(QStringLiteral("tilt")) ||
           lower.contains(QStringLiteral("gyro")) ||
           lower.contains(QStringLiteral("sensor")) ||
           lower.contains(QStringLiteral("visual")) ||
           lower.contains(QStringLiteral("empty")) ||
           lower.contains(QStringLiteral("incomplete"));
}

void SecurityManager::setLoginComboConfigured(
    bool configured,
    int tokenCount)
{
    const int normalizedLength = configured
        ? qBound(MinimumComboLength, tokenCount, MaximumRollingInputs)
        : 0;

    if (m_loginComboConfigured == configured &&
            m_comboLength == normalizedLength) {
        return;
    }

    m_loginComboConfigured = configured;
    m_comboLength = normalizedLength;
    emit stateChanged();
    incrementSecurityRevision();
}

bool SecurityManager::setupAuthorizationValid(const QString &purpose) const
{
    if (!m_setupAuthorization.valid ||
            m_setupAuthorization.username != m_activeUsername ||
            !m_setupAuthorization.expiresAtUtc.isValid() ||
            QDateTime::currentDateTimeUtc() >=
                m_setupAuthorization.expiresAtUtc) {
        return false;
    }

    if (purpose.trimmed().isEmpty())
        return true;

    const QString requested = normalizedPurpose(purpose);

    return m_setupAuthorization.purpose == requested ||
           m_setupAuthorization.purpose == QStringLiteral("recovery") ||
           (m_setupAuthorization.purpose == QStringLiteral("change") &&
            requested == QStringLiteral("setup"));
}

void SecurityManager::grantSetupAuthorization(
    const QString &username,
    const QString &purpose)
{
    m_setupAuthorization.username = username;
    m_setupAuthorization.purpose = normalizedPurpose(purpose);
    m_setupAuthorization.expiresAtUtc =
        QDateTime::currentDateTimeUtc().addSecs(
            SetupAuthorizationSeconds);
    m_setupAuthorization.valid = true;

    if (!m_setupAuthorizationTimer.isActive())
        m_setupAuthorizationTimer.start();

    emit setupAuthorizationChanged();
    emit stateChanged();
    incrementSecurityRevision();
}

QString SecurityManager::normalizedPurpose(const QString &purpose) const
{
    const QString normalized = purpose.trimmed().toLower();

    if (normalized == QStringLiteral("setup") ||
            normalized == QStringLiteral("change") ||
            normalized == QStringLiteral("recovery")) {
        return normalized;
    }

    return QStringLiteral("login");
}

void SecurityManager::updateSetupAuthorizationState()
{
    if (setupAuthorizationValid()) {
        emit setupAuthorizationChanged();
        return;
    }

    const bool hadAuthorization = m_setupAuthorization.valid;
    m_setupAuthorization = SetupAuthorization();
    m_setupAuthorizationTimer.stop();

    if (hadAuthorization) {
        emit setupAuthorizationChanged();
        emit stateChanged();
        incrementSecurityRevision();
    }
}

QStringList SecurityManager::tokenizeCombo(
    const QString &combo,
    bool *valid,
    bool allowRollingBuffer) const
{
    if (valid)
        *valid = false;

    QString text = combo.trimmed().toUpper();
    if (text.isEmpty())
        return {};

    text.replace(
        QRegularExpression(QStringLiteral("[\\[\\]\\(\\)\\{\\}]")),
        QStringLiteral(" "));

    QStringList rawTokens;
    const bool separated = text.contains(
        QRegularExpression(QStringLiteral("[\\s,;|>:/]")));

    if (separated) {
        rawTokens = text.split(
            QRegularExpression(QStringLiteral("[\\s,;|>:/]+")),
            Qt::SkipEmptyParts);
    } else {
        const QStringList aliases = {
            QStringLiteral("LEFTSTICKCLICK"),
            QStringLiteral("RIGHTSTICKCLICK"),
            QStringLiteral("BUTTONTRIANGLE"),
            QStringLiteral("BUTTONSQUARE"),
            QStringLiteral("LEFTTRIGGER"),
            QStringLiteral("RIGHTTRIGGER"),
            QStringLiteral("LEFTBUMPER"),
            QStringLiteral("RIGHTBUMPER"),
            QStringLiteral("DPADDOWN"),
            QStringLiteral("DPADRIGHT"),
            QStringLiteral("DPADLEFT"),
            QStringLiteral("DPADUP"),
            QStringLiteral("TRIANGLE"),
            QStringLiteral("SECONDARY"),
            QStringLiteral("CONTEXT"),
            QStringLiteral("PRIMARY"),
            QStringLiteral("CANCEL"),
            QStringLiteral("CIRCLE"),
            QStringLiteral("SQUARE"),
            QStringLiteral("CROSS"),
            QStringLiteral("LEFTSTICK"),
            QStringLiteral("RIGHTSTICK"),
            QStringLiteral("BUTTONY"),
            QStringLiteral("BUTTONX"),
            QStringLiteral("BUTTONO"),
            QStringLiteral("DOWN"),
            QStringLiteral("RIGHT"),
            QStringLiteral("LEFT"),
            QStringLiteral("UP"),
            QStringLiteral("L1"), QStringLiteral("R1"),
            QStringLiteral("L2"), QStringLiteral("R2"),
            QStringLiteral("L3"), QStringLiteral("R3"),
            QStringLiteral("X"), QStringLiteral("O"),
            QStringLiteral("U"), QStringLiteral("D"),
            QStringLiteral("L"), QStringLiteral("R"),
            QStringLiteral("A"), QStringLiteral("B"),
            QStringLiteral("Y")
        };

        while (!text.isEmpty()) {
            bool matched = false;
            for (const QString &alias : aliases) {
                if (!text.startsWith(alias))
                    continue;

                rawTokens.append(alias);
                text.remove(0, alias.size());
                matched = true;
                break;
            }

            if (!matched)
                return {};
        }
    }

    const int maxTokens =
        allowRollingBuffer ? MaximumRollingInputs : MaximumComboLength;

    if (rawTokens.isEmpty() || rawTokens.size() > maxTokens)
        return {};

    QStringList result;
    result.reserve(rawTokens.size());

    for (const QString &raw : rawTokens) {
        const QString canonical = canonicalToken(raw);
        if (canonical.isEmpty() || !comboTokenAllowed(canonical))
            return {};
        result.append(canonical);
    }

    if (valid)
        *valid = true;
    return result;
}

QString SecurityManager::canonicalToken(const QString &token) const
{
    QString value = token.trimmed().toUpper();
    value.remove(QRegularExpression(QStringLiteral("[\\s_\\-]")));

    if (value == QStringLiteral("U"))
        return QStringLiteral("UP");
    if (value == QStringLiteral("D"))
        return QStringLiteral("DOWN");
    if (value == QStringLiteral("L"))
        return QStringLiteral("LEFT");
    if (value == QStringLiteral("R"))
        return QStringLiteral("RIGHT");

    if (value == QStringLiteral("UP") || value == QStringLiteral("DPADUP"))
        return QStringLiteral("UP");
    if (value == QStringLiteral("DOWN") || value == QStringLiteral("DPADDOWN"))
        return QStringLiteral("DOWN");
    if (value == QStringLiteral("LEFT") || value == QStringLiteral("DPADLEFT"))
        return QStringLiteral("LEFT");
    if (value == QStringLiteral("RIGHT") || value == QStringLiteral("DPADRIGHT"))
        return QStringLiteral("RIGHT");

    if (value == QStringLiteral("X") ||
            value == QStringLiteral("A") ||
            value == QStringLiteral("CROSS") ||
            value == QStringLiteral("PRIMARY") ||
            value == QStringLiteral("BUTTONX")) {
        return QStringLiteral("X");
    }

    if (value == QStringLiteral("O") ||
            value == QStringLiteral("B") ||
            value == QStringLiteral("CIRCLE") ||
            value == QStringLiteral("CANCEL") ||
            value == QStringLiteral("BUTTONO")) {
        return QStringLiteral("O");
    }

    if (value == QStringLiteral("SQUARE") ||
            value == QStringLiteral("SECONDARY") ||
            value == QStringLiteral("BUTTONSQUARE")) {
        return QStringLiteral("SQUARE");
    }

    if (value == QStringLiteral("TRIANGLE") ||
            value == QStringLiteral("Y") ||
            value == QStringLiteral("CONTEXT") ||
            value == QStringLiteral("BUTTONY") ||
            value == QStringLiteral("BUTTONTRIANGLE")) {
        return QStringLiteral("TRIANGLE");
    }

    if (value == QStringLiteral("L1") || value == QStringLiteral("LEFTBUMPER"))
        return QStringLiteral("L1");
    if (value == QStringLiteral("R1") || value == QStringLiteral("RIGHTBUMPER"))
        return QStringLiteral("R1");
    if (value == QStringLiteral("L2") || value == QStringLiteral("LEFTTRIGGER"))
        return QStringLiteral("L2");
    if (value == QStringLiteral("R2") || value == QStringLiteral("RIGHTTRIGGER"))
        return QStringLiteral("R2");
    if (value == QStringLiteral("L3") ||
            value == QStringLiteral("LEFTSTICK") ||
            value == QStringLiteral("LEFTSTICKCLICK")) {
        return QStringLiteral("L3");
    }
    if (value == QStringLiteral("R3") ||
            value == QStringLiteral("RIGHTSTICK") ||
            value == QStringLiteral("RIGHTSTICKCLICK")) {
        return QStringLiteral("R3");
    }

    return {};
}

bool SecurityManager::comboTokenAllowed(const QString &token) const
{
    static const QSet<QString> allowed = {
        QStringLiteral("UP"), QStringLiteral("DOWN"),
        QStringLiteral("LEFT"), QStringLiteral("RIGHT"),
        QStringLiteral("X"), QStringLiteral("O"),
        QStringLiteral("SQUARE"), QStringLiteral("TRIANGLE"),
        QStringLiteral("L1"), QStringLiteral("R1"),
        QStringLiteral("L2"), QStringLiteral("R2"),
        QStringLiteral("L3"), QStringLiteral("R3")
    };

    return allowed.contains(token);
}

QString SecurityManager::canonicalCombo(const QStringList &tokens) const
{
    return tokens.join(QLatin1Char('|'));
}

QString SecurityManager::canonicalComboString(
    const QString &combo,
    bool *valid) const
{
    bool tokensValid = false;
    const QStringList tokens =
        tokenizeCombo(combo, &tokensValid, false);

    if (valid)
        *valid = tokensValid;
    return tokensValid ? canonicalCombo(tokens) : QString();
}

QStringList SecurityManager::finalVerificationWindow(
    const QString &rollingBuffer,
    int requiredTokenCount,
    bool *valid) const
{
    if (valid)
        *valid = false;

    bool bufferValid = false;
    const QStringList tokens =
        tokenizeCombo(rollingBuffer, &bufferValid, true);

    if (!bufferValid ||
            requiredTokenCount < MinimumComboLength ||
            requiredTokenCount > MaximumRollingInputs ||
            tokens.size() < requiredTokenCount) {
        return {};
    }

    if (valid)
        *valid = true;
    return tokens.mid(tokens.size() - requiredTokenCount);
}

bool SecurityManager::ensureSodiumReady() const
{
    return sodiumAvailable();
}

QByteArray SecurityManager::argon2idHashCombo(
    const QByteArray &canonicalCombo) const
{
    return argonHash(
        canonicalCombo,
        m_argonOpsLimit,
        m_argonMemLimit);
}

bool SecurityManager::verifyArgon2idCombo(
    const QByteArray &canonicalCombo,
    const QByteArray &encodedHash) const
{
    return argonVerify(canonicalCombo, encodedHash);
}

QByteArray SecurityManager::randomBytes(int count) const
{
    if (!ensureSodiumReady() || count <= 0)
        return {};

    QByteArray bytes(count, '\0');
    randombytes_buf(
        bytes.data(),
        static_cast<std::size_t>(bytes.size()));
    return bytes;
}

QByteArray SecurityManager::legacyPbkdf2Sha256(
    const QByteArray &password,
    const QByteArray &salt,
    int iterations,
    int derivedKeyLength) const
{
    return pbkdf2(password, salt, iterations, derivedKeyLength);
}

bool SecurityManager::verifyLegacyPbkdf2Record(
    const QJsonObject &record,
    const QByteArray &canonicalCombo) const
{
    return verifyLegacyObject(record, canonicalCombo);
}

bool SecurityManager::constantTimeEquals(
    const QByteArray &left,
    const QByteArray &right) const
{
    return constantEquals(left, right);
}

void SecurityManager::secureClear(QByteArray &buffer)
{
    wipeBytes(buffer);
}

void SecurityManager::secureClear(QString &text)
{
    if (!text.isEmpty() && sodiumAvailable()) {
        sodium_memzero(
            text.data(),
            static_cast<std::size_t>(text.size()) * sizeof(QChar));
    } else if (!text.isEmpty()) {
        text.fill(QChar(0));
    }

    text.clear();
    text.squeeze();
}

QByteArray SecurityManager::readFile(const QString &path) const
{
    if (path.isEmpty())
        return {};

    const QFileInfo info(path);
    if (info.isSymLink())
        return {};

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};

    const QByteArray data = file.readAll();
    file.close();
    return data;
}

bool SecurityManager::writeSecureJsonFile(
    const QString &path,
    const QByteArray &json) const
{
    return writeSecureBytesFile(path, json);
}

bool SecurityManager::writeSecureBytesFile(
    const QString &path,
    const QByteArray &data) const
{
    if (path.isEmpty())
        return false;

    ensureSecurityDir();

    const QFileInfo info(path);
    if (info.exists() && info.isSymLink())
        return false;

    if (!ensureSecureDirectory(info.absolutePath()))
        return false;

    QSaveFile file(path);
    file.setDirectWriteFallback(false);

    if (!file.open(QIODevice::WriteOnly))
        return false;

    if (file.write(data) != data.size()) {
        file.cancelWriting();
        return false;
    }

    if (!file.commit())
        return false;

    const bool secure =
        setOwnerOnlyPermissions(path, false) &&
        setOwnerRootOnly(path) &&
        pathIsRootOwnedOwnerOnly(path, false);

    return secure;
}

bool SecurityManager::migrateLegacyComboForUser(const QString &username)
{
    const QString clean = cleanUsername(username);
    if (clean.isEmpty())
        return false;

    const QString target = comboFilePath(clean);
    if (QFileInfo::exists(target))
        return true;

    const QStringList candidates = {
        oldFlatPath(securityDirPath(), clean),
        legacyComboFilePath(clean)
    };

    for (const QString &candidate : candidates) {
        if (candidate.isEmpty() ||
                candidate == target ||
                !QFileInfo::exists(candidate)) {
            continue;
        }

        const QByteArray data = readFile(candidate);
        const QJsonDocument document = QJsonDocument::fromJson(data);

        if (data.isEmpty() || !document.isObject())
            continue;

        QJsonObject object = document.object();
        QString storedUser = cleanUsername(
            object.value(QStringLiteral("username")).toString());
        if (storedUser.isEmpty())
            storedUser = clean;

        if (storedUser != clean)
            continue;

        object.insert(QStringLiteral("username"), clean);

        if (writeSecureJsonFile(
                target,
                QJsonDocument(object).toJson(QJsonDocument::Indented))) {
            return true;
        }
    }

    return false;
}


bool SecurityManager::openPamLoginSession(
    const QString &username,
    const QString &password)
{
    AsyncResult result;
    QByteArray passwordBytes = password.toUtf8();

    const bool success = authenticatePamInWorker(
        username,
        passwordBytes,
        true,
        &result);

    secureClear(passwordBytes);

    if (!success) {
        releasePamResultSession(result);
        setPamLastError(result.message);
        return false;
    }

    return adoptPamSessionFromResult(result);
}

bool SecurityManager::verifyPamPasswordAndOpenSession(
    const QString &username,
    const QString &password)
{
    return openPamLoginSession(username, password);
}

bool SecurityManager::authenticatePamInWorker(
    const QString &username,
    QByteArray password,
    bool openSession,
    AsyncResult *result)
{
    if (!result) {
        secureClear(password);
        return false;
    }

    result->success = false;
    result->pamSessionEstablished = false;
    result->pamHandle = nullptr;
    result->pamEnvironment.clear();

#ifdef Q_OS_LINUX
    if (!safeUserName(username) || password.isEmpty()) {
        result->message = QStringLiteral("Username and password are required");
        secureClear(password);
        return false;
    }

    auto *conversationData = new PamConversationData;
    conversationData->username = username.toLocal8Bit();
    conversationData->password = password;

    struct pam_conv conversation = {
        &SecurityManager::pamConversationCallback,
        conversationData
    };

    pam_handle_t *handle = nullptr;
    QByteArray service = envValue("NEUTRONOS_PAM_SERVICE").toLocal8Bit();

    if (service.isEmpty())
        service = QByteArrayLiteral("neutronos");

    const QByteArray encodedUsername = username.toLocal8Bit();

    int rc = pam_start(
        service.constData(),
        encodedUsername.constData(),
        &conversation,
        &handle);

    if ((rc != PAM_SUCCESS || !handle) &&
            service != QByteArrayLiteral("login")) {
        if (handle) {
            pam_end(handle, rc);
            handle = nullptr;
        }

        rc = pam_start(
            "login",
            encodedUsername.constData(),
            &conversation,
            &handle);
    }

    if (rc == PAM_SUCCESS && handle) {
        pam_set_item(handle, PAM_TTY, "neutronos");
        pam_set_item(handle, PAM_RHOST, "local");
        rc = pam_authenticate(handle, PAM_SILENT);
    }

    if (rc == PAM_SUCCESS)
        rc = pam_acct_mgmt(handle, PAM_SILENT);

    bool credentialsEstablished = false;
    bool sessionOpened = false;

    if (rc == PAM_SUCCESS && openSession) {
        rc = pam_setcred(handle, PAM_ESTABLISH_CRED);
        credentialsEstablished = rc == PAM_SUCCESS;
    }

    if (rc == PAM_SUCCESS && openSession) {
        rc = pam_open_session(handle, PAM_SILENT);
        sessionOpened = rc == PAM_SUCCESS;
    }

    if (rc != PAM_SUCCESS) {
        const char *message = handle ? pam_strerror(handle, rc) : nullptr;
        result->message = message
            ? QString::fromLocal8Bit(message).trimmed()
            : QStringLiteral("Local account authentication failed");

        if (sessionOpened)
            pam_close_session(handle, PAM_SILENT);
        if (credentialsEstablished)
            pam_setcred(handle, PAM_DELETE_CRED);
        if (handle)
            pam_end(handle, rc);

        wipeBytes(conversationData->password);
        wipeBytes(conversationData->username);
        delete conversationData;
        secureClear(password);
        return false;
    }

    result->success = true;
    result->message = QStringLiteral("Local account verified");

    if (openSession) {
        auto *bundle = new PamSessionBundle;
        bundle->handle = handle;
        bundle->conversation = conversationData;
        bundle->sessionOpen = sessionOpened;

        wipeBytes(conversationData->password);

        char **environment = pam_getenvlist(handle);
        if (environment) {
            for (int i = 0; environment[i] != nullptr; ++i) {
                result->pamEnvironment.append(
                    QString::fromLocal8Bit(environment[i]));
                std::free(environment[i]);
            }
            std::free(environment);
        }

        result->pamHandle = bundle;
        result->pamSessionEstablished = true;
    } else {
        pam_end(handle, PAM_SUCCESS);
        wipeBytes(conversationData->password);
        wipeBytes(conversationData->username);
        delete conversationData;
    }

    secureClear(password);
    return true;
#else
    Q_UNUSED(username)
    Q_UNUSED(openSession)
    result->message = QStringLiteral("PAM is unavailable on this platform");
    secureClear(password);
    return false;
#endif
}

bool SecurityManager::adoptPamSessionFromResult(const AsyncResult &result)
{
    if (!result.success ||
            !result.pamSessionEstablished ||
            !result.pamHandle) {
        return result.success;
    }

    closePamSession();

    m_pamHandle = result.pamHandle;
    m_pamSessionOpen = true;
    m_pamSessionUser = m_activeUsername;
    m_pamEnvironment = result.pamEnvironment;
    m_pamLastError.clear();

    emit pamSessionChanged();
    return true;
}

void SecurityManager::releasePamResultSession(const AsyncResult &result) const
{
#ifdef Q_OS_LINUX
    if (result.pamHandle)
        destroyPamSessionBundle(result.pamHandle);
#else
    Q_UNUSED(result)
#endif
}

void SecurityManager::resetPamState()
{
    m_pamHandle = nullptr;
    m_pamSessionOpen = false;
    m_pamSessionUser.clear();
    m_pamEnvironment.clear();
}

void SecurityManager::setPamLastError(const QString &errorText)
{
    if (m_pamLastError == errorText)
        return;

    m_pamLastError = errorText;
    emit pamSessionChanged();
}

int SecurityManager::pamConversationCallback(
    int messageCount,
    const struct pam_message **messages,
    struct pam_response **responses,
    void *applicationData)
{
#ifdef Q_OS_LINUX
    if (messageCount <= 0 ||
            !messages ||
            !responses ||
            !applicationData) {
        return PAM_CONV_ERR;
    }

    auto *data = static_cast<PamConversationData *>(applicationData);

    auto *reply = static_cast<struct pam_response *>(
        std::calloc(
            static_cast<std::size_t>(messageCount),
            sizeof(struct pam_response)));

    if (!reply)
        return PAM_BUF_ERR;

    for (int i = 0; i < messageCount; ++i) {
        if (!messages[i]) {
            for (int j = 0; j < i; ++j)
                std::free(reply[j].resp);
            std::free(reply);
            return PAM_CONV_ERR;
        }

        const int style = messages[i]->msg_style;

        if (style == PAM_PROMPT_ECHO_OFF ||
                style == PAM_PROMPT_ECHO_ON) {
            const QByteArray response =
                style == PAM_PROMPT_ECHO_ON
                    ? data->username
                    : data->password;

            reply[i].resp = ::strdup(response.constData());
            if (!reply[i].resp) {
                for (int j = 0; j <= i; ++j)
                    std::free(reply[j].resp);
                std::free(reply);
                return PAM_BUF_ERR;
            }
        } else if (style == PAM_ERROR_MSG ||
                   style == PAM_TEXT_INFO) {
            reply[i].resp = nullptr;
        } else {
            for (int j = 0; j <= i; ++j)
                std::free(reply[j].resp);
            std::free(reply);
            return PAM_CONV_ERR;
        }
    }

    *responses = reply;
    return PAM_SUCCESS;
#else
    Q_UNUSED(messageCount)
    Q_UNUSED(messages)
    Q_UNUSED(responses)
    Q_UNUSED(applicationData)
    return -1;
#endif
}

void SecurityManager::dispatchLocalPasswordVerification(
    const QString &username,
    QByteArray password,
    const QString &purpose,
    quint64 serial)
{
    const bool openSession =
        purpose == QStringLiteral("login") ||
        (purpose == QStringLiteral("setup") && !m_loginComboConfigured);
    QPointer<SecurityManager> guard(this);

    QtConcurrent::run(
        [guard,
         username,
         purpose,
         openSession,
         serial,
         password = std::move(password)]() mutable {
            AsyncResult result;
            result.serial = serial;
            result.operation = OperationKind::VerifyLocalPassword;
            result.purpose = purpose;
            result.success = authenticatePamInWorker(
                username,
                password,
                openSession,
                &result);

            secureClear(password);

            if (!guard) {
#ifdef Q_OS_LINUX
                if (result.pamHandle)
                    destroyPamSessionBundle(result.pamHandle);
#endif
                return;
            }

            QObject *dispatchContext = QCoreApplication::instance();
            if (!dispatchContext) {
#ifdef Q_OS_LINUX
                if (result.pamHandle)
                    destroyPamSessionBundle(result.pamHandle);
#endif
                return;
            }

            const bool queued = QMetaObject::invokeMethod(
                dispatchContext,
                [guard, result]() {
                    if (guard) {
                        guard->applyAsyncResult(result);
                    } else {
#ifdef Q_OS_LINUX
                        if (result.pamHandle)
                            destroyPamSessionBundle(result.pamHandle);
#endif
                    }
                },
                Qt::QueuedConnection);

            if (!queued) {
#ifdef Q_OS_LINUX
                if (result.pamHandle)
                    destroyPamSessionBundle(result.pamHandle);
#endif
            }
        });
}

void SecurityManager::dispatchComboCreation(
    const QString &username,
    QByteArray canonicalComboBytes,
    QByteArray confirmation,
    quint64 serial)
{
    const unsigned long long operations = m_argonOpsLimit;
    const std::size_t memory = m_argonMemLimit;
    QPointer<SecurityManager> guard(this);

    QtConcurrent::run(
        [guard,
         username,
         operations,
         memory,
         serial,
         canonicalComboBytes = std::move(canonicalComboBytes),
         confirmation = std::move(confirmation)]() mutable {
            AsyncResult result;
            result.serial = serial;
            result.operation = OperationKind::CreateCombo;

            if (!constantEquals(canonicalComboBytes, confirmation)) {
                result.message = QStringLiteral(
                    "Controller combo confirmation does not match");
            } else {
                ComboRecord record;
                record.version = 3;
                record.username = username;
                record.kdf = QStringLiteral("argon2id");
                record.scheme = QStringLiteral(
                    "libsodium-crypto-pwhash-str");
                record.encodedHash = argonHash(
                    canonicalComboBytes, operations, memory);
                record.tokenCount =
                    canonicalComboBytes.split('|').size();
                record.createdAtUtc = QDateTime::currentDateTimeUtc();
                record.updatedAtUtc = record.createdAtUtc;
                record.valid =
                    !record.encodedHash.isEmpty() &&
                    record.tokenCount >= MinimumComboLength &&
                    record.tokenCount <= MaximumComboLength;

                result.comboRecord = record;
                result.success = record.valid;
                result.message = result.success
                    ? QStringLiteral("Controller login combo created")
                    : QStringLiteral("Controller combo hashing failed");
            }

            secureClear(canonicalComboBytes);
            secureClear(confirmation);

            if (!guard)
                return;

            QMetaObject::invokeMethod(
                guard.data(),
                [guard, result]() {
                    if (guard)
                        guard->applyAsyncResult(result);
                },
                Qt::QueuedConnection);
        });
}

void SecurityManager::dispatchComboVerification(
    const QString &username,
    QByteArray canonicalWindow,
    ComboRecord record,
    quint64 serial)
{
    const unsigned long long operations = m_argonOpsLimit;
    const std::size_t memory = m_argonMemLimit;
    QPointer<SecurityManager> guard(this);

    QtConcurrent::run(
        [guard,
         username,
         operations,
         memory,
         serial,
         record = std::move(record),
         canonicalWindow = std::move(canonicalWindow)]() mutable {
            AsyncResult result;
            result.serial = serial;
            result.operation = OperationKind::VerifyCombo;
            result.tokenCount = canonicalWindow.split('|').size();

            bool legacySuccess = false;

            if (record.kdf.contains(
                    QStringLiteral("argon"), Qt::CaseInsensitive)) {
                result.success = argonVerify(
                    canonicalWindow, record.encodedHash);

                if (!result.success && record.version < 3) {
                    QByteArray legacyCanonical =
                        legacyDirectionCanonical(canonicalWindow);
                    result.success = argonVerify(
                        legacyCanonical, record.encodedHash);

                    if (result.success) {
                        ComboRecord migrated;
                        migrated.version = 3;
                        migrated.username = username;
                        migrated.kdf = QStringLiteral("argon2id");
                        migrated.scheme = QStringLiteral(
                            "libsodium-crypto-pwhash-str");
                        migrated.encodedHash = argonHash(
                            canonicalWindow, operations, memory);
                        migrated.tokenCount = record.tokenCount;
                        migrated.createdAtUtc = record.createdAtUtc.isValid()
                            ? record.createdAtUtc
                            : QDateTime::currentDateTimeUtc();
                        migrated.updatedAtUtc =
                            QDateTime::currentDateTimeUtc();
                        migrated.valid = !migrated.encodedHash.isEmpty();
                        result.comboRecord = migrated;
                    }

                    wipeBytes(legacyCanonical);
                }
            } else if (record.kdf.contains(
                           QStringLiteral("pbkdf2"), Qt::CaseInsensitive)) {
                const QJsonDocument document =
                    QJsonDocument::fromJson(record.encodedHash);
                if (document.isObject()) {
                    legacySuccess = verifyLegacyObject(
                        document.object(), canonicalWindow);
                    result.success = legacySuccess;
                }
            }

            if (legacySuccess) {
                ComboRecord migrated;
                migrated.version = 3;
                migrated.username = username;
                migrated.kdf = QStringLiteral("argon2id");
                migrated.scheme = QStringLiteral(
                    "libsodium-crypto-pwhash-str");
                migrated.encodedHash = argonHash(
                    canonicalWindow, operations, memory);
                migrated.tokenCount = record.tokenCount;
                migrated.createdAtUtc = record.createdAtUtc.isValid()
                    ? record.createdAtUtc
                    : QDateTime::currentDateTimeUtc();
                migrated.updatedAtUtc = QDateTime::currentDateTimeUtc();
                migrated.valid = !migrated.encodedHash.isEmpty();
                result.comboRecord = migrated;
            }

            result.message = result.success
                ? QStringLiteral("Login combo accepted")
                : QStringLiteral("Incorrect controller combo");

            secureClear(canonicalWindow);

            if (!guard)
                return;

            QMetaObject::invokeMethod(
                guard.data(),
                [guard, result]() {
                    if (guard)
                        guard->applyAsyncResult(result);
                },
                Qt::QueuedConnection);
        });
}

void SecurityManager::dispatchComboChange(
    const QString &username,
    QByteArray currentWindow,
    QByteArray newCombo,
    QByteArray confirmation,
    ComboRecord currentRecord,
    bool recoveryAuthorized,
    quint64 serial)
{
    const unsigned long long operations = m_argonOpsLimit;
    const std::size_t memory = m_argonMemLimit;
    QPointer<SecurityManager> guard(this);

    QtConcurrent::run(
        [guard,
         username,
         operations,
         memory,
         recoveryAuthorized,
         serial,
         currentRecord = std::move(currentRecord),
         currentWindow = std::move(currentWindow),
         newCombo = std::move(newCombo),
         confirmation = std::move(confirmation)]() mutable {
            AsyncResult result;
            result.serial = serial;
            result.operation = OperationKind::ChangeCombo;

            bool currentAccepted = recoveryAuthorized;

            if (!currentAccepted) {
                if (currentRecord.kdf.contains(
                        QStringLiteral("argon"), Qt::CaseInsensitive)) {
                    currentAccepted = argonVerify(
                        currentWindow, currentRecord.encodedHash);

                    if (!currentAccepted && currentRecord.version < 3) {
                        QByteArray legacyCanonical =
                            legacyDirectionCanonical(currentWindow);
                        currentAccepted = argonVerify(
                            legacyCanonical, currentRecord.encodedHash);
                        wipeBytes(legacyCanonical);
                    }
                } else if (currentRecord.kdf.contains(
                               QStringLiteral("pbkdf2"),
                               Qt::CaseInsensitive)) {
                    const QJsonDocument document =
                        QJsonDocument::fromJson(
                            currentRecord.encodedHash);
                    if (document.isObject()) {
                        currentAccepted = verifyLegacyObject(
                            document.object(), currentWindow);
                    }
                }
            }

            const bool confirmationMatches =
                constantEquals(newCombo, confirmation);

            if (!currentAccepted) {
                result.message = QStringLiteral(
                    "Current controller combo is incorrect");
            } else if (!confirmationMatches) {
                result.message = QStringLiteral(
                    "New controller combo confirmation does not match");
            } else {
                ComboRecord replacement;
                replacement.version = 3;
                replacement.username = username;
                replacement.kdf = QStringLiteral("argon2id");
                replacement.scheme = QStringLiteral(
                    "libsodium-crypto-pwhash-str");
                replacement.encodedHash = argonHash(
                    newCombo, operations, memory);
                replacement.tokenCount = newCombo.split('|').size();
                replacement.createdAtUtc =
                    currentRecord.createdAtUtc.isValid()
                        ? currentRecord.createdAtUtc
                        : QDateTime::currentDateTimeUtc();
                replacement.updatedAtUtc =
                    QDateTime::currentDateTimeUtc();
                replacement.valid =
                    !replacement.encodedHash.isEmpty() &&
                    replacement.tokenCount >= MinimumComboLength &&
                    replacement.tokenCount <= MaximumComboLength;

                result.comboRecord = replacement;
                result.success = replacement.valid;
                result.message = result.success
                    ? QStringLiteral("Controller login combo changed")
                    : QStringLiteral("Replacement combo hashing failed");
            }

            secureClear(currentWindow);
            secureClear(newCombo);
            secureClear(confirmation);

            if (!guard)
                return;

            QMetaObject::invokeMethod(
                guard.data(),
                [guard, result]() {
                    if (guard)
                        guard->applyAsyncResult(result);
                },
                Qt::QueuedConnection);
        });
}


void SecurityManager::applyAsyncResult(const AsyncResult &result)
{
    if (result.serial != m_operationSerial ||
            result.operation != m_operationKind) {
        releasePamResultSession(result);
        return;
    }

    const QString action = operationName(result.operation);
    const QVariantMap payload = m_pendingSafePayload;

    if (result.operation == OperationKind::VerifyLocalPassword) {
        bool success = result.success;
        QString message = result.message;

        if (success && result.pamSessionEstablished) {
            success = adoptPamSessionFromResult(result);
            if (!success) {
                message = QStringLiteral(
                    "PAM session could not be adopted");
            }
        }

        if (success) {
            resetFailuresAfterVerifiedAuthentication();

            if (result.purpose != QStringLiteral("login") ||
                    !m_loginComboConfigured) {
                grantSetupAuthorization(
                    m_activeUsername,
                    result.purpose == QStringLiteral("login")
                        ? QStringLiteral("setup")
                        : result.purpose);
            }
        } else {
            releasePamResultSession(result);
            registerFailedAttemptWithReason(
                QStringLiteral("PAM authentication failed"));
        }

        emit localPasswordVerificationFinished(
            success, message, result.purpose);

        finishOperation(action, success, message, payload);

        /*
            After a combo exists, the local Linux password authorizes recovery
            and settings changes but is not the normal console unlock key.
        */
        return;
    }

    if (result.operation == OperationKind::CreateCombo) {
        bool success = result.success;
        QString message = result.message;

        if (success) {
            ComboRecord record = result.comboRecord;
            record.username = m_activeUsername;
            success = saveComboRecord(record);

            if (success) {
                applyComboRecord(record);
                clearSetupAuthorization();
                resetFailuresAfterVerifiedAuthentication();
                rebuildWatchers();
            } else {
                message = QStringLiteral(
                    "Controller combo could not be persisted securely");
            }
        }

        emit loginComboCreationFinished(success, message);
        finishOperation(action, success, message, payload);

        if (success)
            emit unlockGranted(m_activeUser);

        return;
    }

    if (result.operation == OperationKind::VerifyCombo) {
        const bool notificationClear = m_notificationClearPending &&
            result.serial == m_notificationClearSerial &&
            m_notificationClearUser == m_activeUsername &&
            payload.value(QStringLiteral("username")).toString() == m_activeUsername &&
            m_notificationManager;
        if (result.success) {
            if (result.comboRecord.valid) {
                ComboRecord migrated = result.comboRecord;
                migrated.username = m_activeUsername;

                if (saveComboRecord(migrated))
                    applyComboRecord(migrated);
            }

            resetFailuresAfterVerifiedAuthentication();

            if (notificationClear) {
                const QVariantMap clear =
                    m_notificationManager->clearAllSecurityAuthenticated();
                const bool cleared = clear.value(QStringLiteral("success")).toBool() &&
                    clear.value(QStringLiteral("remainingSecurity")).toInt() == 0;
                finishOperation(action, cleared,
                    cleared ? QStringLiteral("Authenticated Security notifications cleared")
                            : QStringLiteral("Authenticated Security notification clear failed"),
                    payload);
                emit authenticatedNotificationClearFinished(clear);
                return;
            }

            emit loginComboVerificationFinished(
                true,
                result.message,
                m_failedAttempts,
                m_secondsRemaining);

            finishOperation(
                action,
                true,
                result.message,
                payload);

            emit unlockGranted(m_activeUser);
            return;
        }

        const int rollingCount = payload.value(
            QStringLiteral("rollingTokenCount")).toInt();

        if (rollingCount >= MaximumRollingInputs) {
            registerFailedAttemptWithReason(
                QStringLiteral("incorrect controller combo"));
        }

        if (!notificationClear)
            emit loginComboVerificationFinished(
                false, result.message, m_failedAttempts, m_secondsRemaining);

        finishOperation(
            action,
            false,
            result.message,
            payload);
        if (notificationClear) {
            QVariantMap clear;
            clear.insert(QStringLiteral("success"), false);
            clear.insert(QStringLiteral("removed"), 0);
            clear.insert(QStringLiteral("total"), m_notificationManager->totalCount());
            clear.insert(QStringLiteral("message"), result.message);
            clear.insert(QStringLiteral("secondsRemaining"), m_secondsRemaining);
            emit authenticatedNotificationClearFinished(clear);
        }

        if (rollingCount >= MaximumRollingInputs) {
            emit unlockDenied(
                result.message,
                m_failedAttempts,
                m_secondsRemaining);
        }

        return;
    }

    if (result.operation == OperationKind::ChangeCombo) {
        bool success = result.success;
        QString message = result.message;

        if (success) {
            ComboRecord record = result.comboRecord;
            record.username = m_activeUsername;
            success = saveComboRecord(record);

            if (success) {
                applyComboRecord(record);
                clearSetupAuthorization();
                resetFailuresAfterVerifiedAuthentication();
                rebuildWatchers();
            } else {
                message = QStringLiteral(
                    "Replacement combo could not be persisted securely");
            }
        } else if (message.contains(
                       QStringLiteral("Current controller combo"))) {
            registerFailedAttemptWithReason(
                QStringLiteral("incorrect current controller combo"));
        }

        emit loginComboChangeFinished(success, message);
        finishOperation(action, success, message, payload);
    }
}

bool SecurityManager::beginOperation(
    OperationKind operation,
    const QString &action,
    const QVariantMap &payload)
{
    if (m_operationBusy || operation == OperationKind::None)
        return false;

    ++m_operationSerial;
    m_operationKind = operation;
    m_activeOperation = action;
    m_pendingSafePayload = sanitizedPayload(payload);

    setLastError(QString());
    setLastOperation(QStringLiteral("%1 started").arg(action));
    setOperationBusy(true);

    emit operationStarted(action, m_pendingSafePayload);
    return true;
}

void SecurityManager::finishOperation(
    const QString &action,
    bool success,
    const QString &message,
    const QVariantMap &payload)
{
    const QVariantMap safePayload = payload.isEmpty()
        ? m_pendingSafePayload
        : sanitizedPayload(payload);

    if (success)
        setLastError(QString());
    else
        setLastError(message);

    setLastOperation(message);
    clearPendingOperation();
    setOperationBusy(false);

    emit operationFinished(
        action,
        success,
        message,
        safePayload);
}

void SecurityManager::setOperationBusy(bool busy)
{
    if (m_operationBusy == busy)
        return;

    m_operationBusy = busy;
    emit operationBusyChanged();
}

void SecurityManager::setLastOperation(const QString &message)
{
    if (m_lastOperation == message)
        return;

    m_lastOperation = message;
    emit operationStateChanged();
}

void SecurityManager::setLastError(const QString &message)
{
    if (m_lastError == message)
        return;

    m_lastError = message;
    emit operationStateChanged();
}

void SecurityManager::clearPendingOperation()
{
    m_operationKind = OperationKind::None;
    m_activeOperation.clear();
    m_pendingSafePayload.clear();
    m_notificationClearPending = false;
    m_notificationClearSerial = 0;
    m_notificationClearUser.clear();
}

QString SecurityManager::operationName(OperationKind operation) const
{
    switch (operation) {
    case OperationKind::VerifyLocalPassword:
        return QStringLiteral("verifyLocalPassword");
    case OperationKind::CreateCombo:
        return QStringLiteral("createLoginCombo");
    case OperationKind::VerifyCombo:
        return QStringLiteral("verifyLoginCombo");
    case OperationKind::ChangeCombo:
        return QStringLiteral("changeLoginCombo");
    case OperationKind::None:
    default:
        return {};
    }
}

QVariantMap SecurityManager::sanitizedPayload(
    const QVariantMap &payload) const
{
    QVariantMap result;

    for (auto it = payload.constBegin(); it != payload.constEnd(); ++it) {
        const QString key = it.key().trimmed().toLower();

        const bool sensitive =
            key.contains(QStringLiteral("password")) ||
            key.contains(QStringLiteral("passphrase")) ||
            key.contains(QStringLiteral("secret")) ||
            key.contains(QStringLiteral("token")) ||
            key.contains(QStringLiteral("hash")) ||
            key.contains(QStringLiteral("digest")) ||
            key.contains(QStringLiteral("salt")) ||
            key.contains(QStringLiteral("confirmation")) ||
            key.contains(QStringLiteral("sequence")) ||
            key.contains(QStringLiteral("rollingbuffer")) ||
            key == QStringLiteral("combo") ||
            key.contains(QStringLiteral("currentcombo")) ||
            key.contains(QStringLiteral("newcombo")) ||
            key.contains(QStringLiteral("oldcombo"));

        if (sensitive)
            continue;

        const QVariant value = it.value();

        if (value.userType() == QMetaType::QVariantMap) {
            result.insert(
                it.key(),
                sanitizedPayload(value.toMap()));
            continue;
        }

        if (value.userType() == QMetaType::QVariantList) {
            QVariantList list;
            for (const QVariant &entry : value.toList()) {
                list.append(
                    entry.userType() == QMetaType::QVariantMap
                        ? QVariant(sanitizedPayload(entry.toMap()))
                        : entry);
            }
            result.insert(it.key(), list);
            continue;
        }

        result.insert(it.key(), value);
    }

    return result;
}

QVariantMap SecurityManager::publicSecurityContext() const
{
    QVariantMap result;
    result.insert(QStringLiteral("username"), m_activeUsername);
    result.insert(QStringLiteral("loginComboConfigured"),
                  m_loginComboConfigured);
    result.insert(QStringLiteral("comboLength"), m_comboLength);
    result.insert(QStringLiteral("failedAttempts"), m_failedAttempts);
    result.insert(QStringLiteral("lockedOut"), m_lockedOut);
    result.insert(QStringLiteral("secondsRemaining"), m_secondsRemaining);
    result.insert(QStringLiteral("lockoutLevel"), m_lockoutLevel);
    result.insert(QStringLiteral("setupAuthorized"),
                  setupAuthorizationValid());
    result.insert(QStringLiteral("setupAuthorizationRemaining"),
                  setupAuthorizationRemaining());
    result.insert(QStringLiteral("pamSessionOpen"), m_pamSessionOpen);
    return result;
}

void SecurityManager::rebuildWatchers()
{
    const QStringList existingFiles = m_fileWatcher.files();
    if (!existingFiles.isEmpty())
        m_fileWatcher.removePaths(existingFiles);

    const QStringList existingDirectories = m_fileWatcher.directories();
    if (!existingDirectories.isEmpty())
        m_fileWatcher.removePaths(existingDirectories);

    m_watchedPaths.clear();

    auto addPath = [this](const QString &path) {
        if (path.isEmpty() || !QFileInfo::exists(path))
            return;

        const QString clean = QDir::cleanPath(path);
        if (m_watchedPaths.contains(clean))
            return;

        if (m_fileWatcher.addPath(clean))
            m_watchedPaths.insert(clean);
    };

    addPath(securityDirPath());
    addPath(usersSecurityDirPath());
    addPath(QStringLiteral("/var/lib/neutronos/setup"));
    addPath(QStringLiteral("/var/lib/neutronos/setup/setup.json"));

    if (!m_activeUsername.isEmpty()) {
        addPath(activeUserSecurityDirPath());
        addPath(lockoutStateFilePath());
        addPath(comboFilePath(m_activeUsername));
    }

    addPath(legacySecurityDirPath());
}

void SecurityManager::scheduleRefresh(int delayMs)
{
    const int boundedDelay = qBound(0, delayMs, 5000);

    if (m_refreshCoalesceTimer.isActive() &&
            m_refreshCoalesceTimer.remainingTime() <= boundedDelay) {
        return;
    }

    m_refreshCoalesceTimer.start(boundedDelay);
}

void SecurityManager::onWatchedPathChanged(const QString &path)
{
    Q_UNUSED(path)
    scheduleRefresh();
}

void SecurityManager::coalescedRefresh()
{
    if (m_operationBusy) {
        scheduleRefresh(250);
        return;
    }

    loadActiveUserState();
}
