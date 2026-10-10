#pragma once

#include <QObject>
#include <QByteArray>
#include <QDateTime>
#include <QElapsedTimer>
#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include "LoginConfigurationState.h"

class NotificationManager;

#include <cstddef>

/*
    ========================================================================
                            SECURITY MANAGER
    ========================================================================

    Canonical NeutronOS login-security backend.

    This class remains the single owner of:

        - Local Linux authentication through PAM.
        - PAM credential/session establishment and teardown.
        - Controller login-combo creation and verification.
        - Argon2id hashing through libsodium.
        - Legacy PBKDF2 verification and migration.
        - Persistent failed-attempt counters and deterministic lockouts.
        - Temporary local-password authorization for combo setup/change.
        - Root-owned security state under /var/lib/neutronos/security.

    The previously generated LoginSecurityManager is not used. SecurityManager
    preserves the existing QML API while adding explicit asynchronous methods
    for production LoginScreen and UserSettingsModal integration.

    ------------------------------------------------------------------------
                               SECURITY RULES
    ------------------------------------------------------------------------

        1. No plaintext password or controller combo is persisted.

        2. New combo records use libsodium crypto_pwhash_str(), which currently
           produces an Argon2id encoded hash.

        3. Combo creation/change requires a valid temporary PAM authorization
           for the active local account.

        4. HOME, PS, SYSTEM, START, OPTIONS, MENU, and SELECT are reserved for
           shell-level actions and cannot be used as login-combo tokens.

        5. The backend accepts at most 15 rolling input tokens and verifies only
           the final configured combo-length window. QML cannot bypass this.

        6. Invalid submitted combos are registered as failed attempts inside
           this backend. LoginScreen must not increment the counter separately.

        7. Empty, malformed, unknown, or mismatched usernames are rejected.
           There is no shared "default" security record.

        8. Authentication and password hashing have asynchronous entry points
           so the Qt Quick render thread does not perform PAM or Argon2 work.

        9. Security state is root-owned and owner-only:

               /var/lib/neutronos/security                 0700
               /var/lib/neutronos/security/users           0700
               /var/lib/neutronos/security/users/<user>    0700
               combo.json                                  0600
               state.json                                  0600

       10. Persistent failure counters survive service restarts. Active lockout
           countdowns use monotonic time and are deterministically re-applied
           after a restart instead of trusting wall-clock expiry.

    ------------------------------------------------------------------------
                         COMPATIBILITY API PRESERVED
    ------------------------------------------------------------------------

        verifyLocalPassword()
        authenticateLocalUser()
        hasLoginCombo()
        createLoginCombo()
        verifyLoginCombo()
        loginComboConfiguredForUser()
        comboConfigured()
        verifyCombo()
        setLoginCombo()
        registerFailedAttempt()
        registerFailedAttemptWithReason()
        registerHighThreat()
        registerHighThreatWithReason()
        registerSuccess()
        refresh()
        clearLockout()
        closePamSession()
        logoutPamSession()
        pamEnvironment()
        migrateLegacyUserState()

    New production QML should prefer:

        setActiveUser()
        beginLocalPasswordVerification()
        beginLoginComboCreation()
        beginLoginComboVerification()
        beginLoginComboChange()
*/

#ifndef NEUTRONOS_STATE_DIR
#define NEUTRONOS_STATE_DIR "/var/lib/neutronos"
#endif

#ifndef NEUTRONOS_SECURITY_STATE_DIR
#define NEUTRONOS_SECURITY_STATE_DIR "/var/lib/neutronos/security"
#endif

class SecurityManager final : public QObject
{
    Q_OBJECT

    /*
        --------------------------------------------------------------------
                              ACTIVE ACCOUNT
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString activeUsername
               READ activeUsername
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString username
               READ activeUsername
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString userId
               READ activeUsername
               NOTIFY activeUserChanged)

    Q_PROPERTY(QVariantMap activeUser
               READ activeUser
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString loginConfigurationState
               READ loginConfigurationState
               NOTIFY loginConfigurationStateChanged)

    /*
        --------------------------------------------------------------------
                           LOCKOUT / FAILURE STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool lockedOut
               READ lockedOut
               NOTIFY stateChanged)

    Q_PROPERTY(int failedAttempts
               READ failedAttempts
               NOTIFY stateChanged)

    Q_PROPERTY(int secondsRemaining
               READ secondsRemaining
               NOTIFY stateChanged)

    Q_PROPERTY(int lockoutRemaining
               READ secondsRemaining
               NOTIFY stateChanged)

    Q_PROPERTY(int lockoutRemainingSeconds
               READ secondsRemaining
               NOTIFY stateChanged)

    Q_PROPERTY(int lockoutDelaySeconds
               READ lockoutDelaySeconds
               NOTIFY stateChanged)

    Q_PROPERTY(int lockoutLevel
               READ lockoutLevel
               NOTIFY stateChanged)

    Q_PROPERTY(QString lastFailureReason
               READ lastFailureReason
               NOTIFY stateChanged)

    /*
        --------------------------------------------------------------------
                            LOGIN COMBO STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool loginComboConfigured
               READ loginComboConfigured
               NOTIFY stateChanged)

    Q_PROPERTY(bool comboConfiguredForActiveUser
               READ loginComboConfigured
               NOTIFY stateChanged)

    Q_PROPERTY(bool requiresComboSetup
               READ requiresComboSetup
               NOTIFY stateChanged)

    Q_PROPERTY(int comboLength
               READ comboLength
               NOTIFY stateChanged)

    Q_PROPERTY(int minimumComboLength
               READ minimumComboLength
               CONSTANT)

    Q_PROPERTY(int maximumComboLength
               READ maximumComboLength
               CONSTANT)

    Q_PROPERTY(int maximumRollingInputs
               READ maximumRollingInputs
               CONSTANT)

    Q_PROPERTY(QVariantList allowedComboTokens
               READ allowedComboTokens
               CONSTANT)

    /*
        --------------------------------------------------------------------
                        SETUP AUTHORIZATION STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool setupAuthorized
               READ setupAuthorized
               NOTIFY setupAuthorizationChanged)

    Q_PROPERTY(bool localPasswordVerified
               READ setupAuthorized
               NOTIFY setupAuthorizationChanged)

    Q_PROPERTY(int setupAuthorizationRemaining
               READ setupAuthorizationRemaining
               NOTIFY setupAuthorizationChanged)

    Q_PROPERTY(bool highPriorityAuthorized
               READ highPriorityAuthorized
               NOTIFY highPriorityAuthorizationChanged)

    Q_PROPERTY(int highPriorityAuthorizationRemaining
               READ highPriorityAuthorizationRemaining
               NOTIFY highPriorityAuthorizationChanged)

    Q_PROPERTY(QString highPriorityAuthorizedApp
               READ highPriorityAuthorizedApp
               NOTIFY highPriorityAuthorizationChanged)

    /*
        --------------------------------------------------------------------
                           ASYNC OPERATION STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool operationBusy
               READ operationBusy
               NOTIFY operationBusyChanged)

    Q_PROPERTY(bool authenticationPending
               READ authenticationPending
               NOTIFY operationBusyChanged)

    Q_PROPERTY(bool comboOperationPending
               READ comboOperationPending
               NOTIFY operationBusyChanged)

    Q_PROPERTY(QString activeOperation
               READ activeOperation
               NOTIFY operationBusyChanged)

    Q_PROPERTY(QString lastOperation
               READ lastOperation
               NOTIFY operationStateChanged)

    Q_PROPERTY(QString lastError
               READ lastError
               NOTIFY operationStateChanged)

    /*
        --------------------------------------------------------------------
                         SECURITY BACKEND DIAGNOSTICS
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString securityDir
               READ securityDirPath
               CONSTANT)

    Q_PROPERTY(QString kdfScheme
               READ kdfScheme
               CONSTANT)

    Q_PROPERTY(bool securityDirectorySafe
               READ securityDirectoryLooksSafe
               NOTIFY securityDirectoryStateChanged)

    Q_PROPERTY(int securityRevision
               READ securityRevision
               NOTIFY securityRevisionChanged)

    /*
        --------------------------------------------------------------------
                              PAM SESSION STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool pamSessionOpen
               READ pamSessionOpen
               NOTIFY pamSessionChanged)

    Q_PROPERTY(QString pamSessionUser
               READ pamSessionUser
               NOTIFY pamSessionChanged)

    Q_PROPERTY(QString pamLastError
               READ pamLastError
               NOTIFY pamSessionChanged)

public:
    explicit SecurityManager(QObject *parent = nullptr);
    ~SecurityManager() override;

    /*
        Active account.
    */
    QString activeUsername() const;
    QVariantMap activeUser() const;
    QString loginConfigurationState() const;

    /*
        Lockout state.
    */
    bool lockedOut() const;
    int failedAttempts() const;
    int secondsRemaining() const;
    int lockoutDelaySeconds() const;
    int lockoutLevel() const;
    QString lastFailureReason() const;

    /*
        Combo state.
    */
    bool loginComboConfigured() const;
    bool requiresComboSetup() const;
    int comboLength() const;
    int minimumComboLength() const;
    int maximumComboLength() const;
    int maximumRollingInputs() const;
    QVariantList allowedComboTokens() const;

    /*
        Setup authorization.
    */
    bool setupAuthorized() const;
    int setupAuthorizationRemaining() const;
    bool highPriorityAuthorized() const;
    int highPriorityAuthorizationRemaining() const;
    QString highPriorityAuthorizedApp() const;

    /*
        Operation state.
    */
    bool operationBusy() const;
    bool authenticationPending() const;
    bool comboOperationPending() const;
    QString activeOperation() const;
    QString lastOperation() const;
    QString lastError() const;

    /*
        Diagnostics.
    */
    QString securityDirPath() const;
    QString kdfScheme() const;
    bool securityDirectoryLooksSafe() const;
    int securityRevision() const;

    /*
        PAM session.
    */
    bool pamSessionOpen() const;
    QString pamSessionUser() const;
    QString pamLastError() const;

    /*
        --------------------------------------------------------------------
                            ACTIVE USER ROUTING
        --------------------------------------------------------------------

        The active account must be selected before combo setup/verification.

        Immutable identity fields are revalidated against the local account
        database. QML-provided username, UID, home, or role values are not
        trusted as security authority.
    */

    Q_INVOKABLE bool setActiveUser(const QVariantMap &userContext);
    Q_INVOKABLE bool setActiveUsername(const QString &username);
    Q_INVOKABLE void clearActiveUser();

    /*
        --------------------------------------------------------------------
                       ASYNCHRONOUS PAM AUTHENTICATION
        --------------------------------------------------------------------

        Returns true when the request was accepted.

        completion:
            localPasswordVerificationFinished(success, message, purpose)

        purpose:
            login       open/retain a PAM session
            setup       authorize first-time combo creation
            change      authorize combo replacement
            recovery    authorize combo recovery/replacement
    */

    Q_INVOKABLE bool beginLocalPasswordVerification(
        const QString &username,
        const QString &password,
        const QString &purpose = QStringLiteral("login"));

    /*
        First-boot identity provisioning has already crossed the audited root
        helper boundary and successfully installed the submitted password.
        During that narrow pre-combo window, authorize controller-passcode
        enrollment without attempting cross-user PAM from the display account.
    */
    Q_INVOKABLE bool authorizeFreshSetupIdentity(const QString &username);

    /*
        --------------------------------------------------------------------
                     SYNCHRONOUS PAM COMPATIBILITY API
        --------------------------------------------------------------------

        Preserved for existing QML while LoginScreen is migrated. These calls
        perform real PAM work synchronously and therefore should not be used
        from animation-critical new QML.
    */

    Q_INVOKABLE bool verifyLocalPassword(const QString &username,
                                         const QString &password);

    Q_INVOKABLE bool authenticateLocalUser(const QString &username,
                                           const QString &password);

    Q_INVOKABLE bool authorizeHighPriorityAction(
        const QString &username,
        const QString &password,
        const QString &appId = QStringLiteral("settings"));
    Q_INVOKABLE bool highPriorityAuthorizationValidFor(const QString &appId) const;
    Q_INVOKABLE void clearHighPriorityAuthorization();

    /*
        Close the active PAM session when NeutronOS logs out. Locking may keep
        the authenticated Linux session open depending on Main.qml policy.
    */
    Q_INVOKABLE bool closePamSession();
    Q_INVOKABLE bool logoutPamSession();

    /*
        PAM environment exported for AppLauncher/Terminal session setup.
    */
    Q_INVOKABLE QStringList pamEnvironment() const;

    /*
        --------------------------------------------------------------------
                         ASYNCHRONOUS COMBO SETUP
        --------------------------------------------------------------------

        All three values are transient. They are removed from retained
        operation payloads and overwritten in worker-local mutable buffers.

        Combo creation/change requires setupAuthorized == true.
    */

    Q_INVOKABLE bool beginLoginComboCreation(
        const QString &username,
        const QString &normalizedCombo,
        const QString &confirmation);

    Q_INVOKABLE bool beginLoginComboChange(
        const QString &username,
        const QString &currentRollingBuffer,
        const QString &newCombo,
        const QString &confirmation);

    /*
        --------------------------------------------------------------------
                       ASYNCHRONOUS COMBO VERIFICATION
        --------------------------------------------------------------------

        Returns true when verification work was accepted.

        The backend:
            - rejects more than maximumRollingInputs tokens,
            - rejects reserved/unknown tokens,
            - selects only the final configured comboLength tokens,
            - registers a failed attempt on mismatch,
            - emits unlockGranted only on success.
    */

    Q_INVOKABLE bool beginLoginComboVerification(
        const QString &username,
        const QString &rollingBuffer);

    // Authenticates the active local user with the existing combo verifier.
    // The protected clear is native-only and cannot be called from QML.
    Q_INVOKABLE bool beginAuthenticatedNotificationClear(
        const QString &username,
        const QString &rollingBuffer);
    void setNotificationManager(NotificationManager *manager);

    /*
        --------------------------------------------------------------------
                         COMBO COMPATIBILITY API
        --------------------------------------------------------------------

        These names remain available for current QML and tests.

        createLoginCombo()/setLoginCombo() require a valid setup authorization
        window. They no longer permit unrestricted hash replacement.

        verifyLoginCombo()/verifyCombo() register failure internally.
    */

    Q_INVOKABLE bool hasLoginCombo(const QString &username);

    Q_INVOKABLE bool createLoginCombo(const QString &username,
                                      const QString &normalizedCombo);

    Q_INVOKABLE bool verifyLoginCombo(const QString &username,
                                      const QString &rollingBuffer);

    Q_INVOKABLE bool loginComboConfiguredForUser(const QString &username);
    Q_INVOKABLE bool comboConfigured(const QString &username);

    Q_INVOKABLE bool verifyCombo(const QString &username,
                                 const QString &rollingBuffer);

    Q_INVOKABLE bool setLoginCombo(const QString &username,
                                   const QString &normalizedCombo);

    /*
        Non-mutating format checks used by setup UI.
    */
    Q_INVOKABLE bool isValidComboFormat(const QString &combo) const;
    Q_INVOKABLE int normalizedComboTokenCount(const QString &combo) const;

    /*
        --------------------------------------------------------------------
                       FAILED ATTEMPTS / LOCKOUTS
        --------------------------------------------------------------------
    */

    Q_INVOKABLE bool registerFailedAttempt();
    Q_INVOKABLE bool registerFailedAttemptWithReason(const QString &reason);

    Q_INVOKABLE void registerHighThreat();
    Q_INVOKABLE void registerHighThreatWithReason(const QString &reason);

    Q_INVOKABLE void registerSuccess();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshSecurityState();

    /*
        Recovery/admin API. This succeeds only when the process can write the
        root-owned state directory. Normal QML must not expose it as a casual
        user action.
    */
    Q_INVOKABLE void clearLockout();

    /*
        --------------------------------------------------------------------
                       TRANSIENT OPERATION CONTROL
        --------------------------------------------------------------------
    */

    Q_INVOKABLE void cancelPendingOperation();
    Q_INVOKABLE void clearSetupAuthorization();
    Q_INVOKABLE void clearTransientSecrets();

    /*
        --------------------------------------------------------------------
                              LEGACY MIGRATION
        --------------------------------------------------------------------

        Imports supported combo records from:

            ~/NeutronOS/state/security

        Into the root-owned authoritative location. Old wall-clock lockout
        deadlines are intentionally not trusted or imported.
    */

    Q_INVOKABLE bool migrateLegacyUserState();

signals:
    /*
        Existing compatibility signals.
    */
    void stateChanged();
    void lockoutStarted();
    void lockoutCleared();
    void pamSessionChanged();
    void loginConfigurationStateChanged();

    /*
        Active account.
    */
    void activeUserChanged();

    /*
        Setup authorization.
    */
    void setupAuthorizationChanged();
    void highPriorityAuthorizationChanged();

    /*
        Async operation state.
    */
    void operationBusyChanged();
    void operationStateChanged();

    void operationStarted(const QString &action,
                          const QVariantMap &safePayload);

    void operationFinished(const QString &action,
                           bool success,
                           const QString &message,
                           const QVariantMap &safePayload);

    /*
        Specific result signals.
    */
    void localPasswordVerificationFinished(bool success,
                                           const QString &message,
                                           const QString &purpose);

    void loginComboCreationFinished(bool success,
                                    const QString &message);

    void loginComboVerificationFinished(bool success,
                                        const QString &message,
                                        int failedAttempts,
                                        int secondsRemaining);

    void loginComboChangeFinished(bool success,
                                  const QString &message);
    void authenticatedNotificationClearFinished(const QVariantMap &result);

    /*
        Main.qml consumes these session-gate signals.
    */
    void unlockGranted(const QVariantMap &userContext);

    void unlockDenied(const QString &message,
                      int failedAttempts,
                      int secondsRemaining);

    /*
        Diagnostics/revision.
    */
    void securityDirectoryStateChanged();
    void securityRevisionChanged();

private slots:
    void updateLockoutState();
    void updateSetupAuthorizationState();
    void updateHighPriorityAuthorizationState();

    void onWatchedPathChanged(const QString &path);
    void coalescedRefresh();

private:
    enum class OperationKind
    {
        None,
        VerifyLocalPassword,
        CreateCombo,
        VerifyCombo,
        ChangeCombo
    };

    struct ComboRecord
    {
        int version = 3;
        QString username;
        QString kdf = QStringLiteral("argon2id");
        QString scheme =
            QStringLiteral("libsodium-crypto-pwhash-str");
        QByteArray encodedHash;
        int tokenCount = 0;
        QDateTime createdAtUtc;
        QDateTime updatedAtUtc;
        bool valid = false;
    };

    struct PersistentState
    {
        int version = 3;
        QString username;
        int failedAttempts = 0;
        int highThreatAttempts = 0;
        bool lockedOut = false;
        int lockoutDelaySeconds = 0;
        int lockoutLevel = 0;
        QString lastFailureReason;
        QString lastHighThreatReason;
        QDateTime lastSuccessfulLoginUtc;
        bool valid = false;
    };

    struct SetupAuthorization
    {
        QString username;
        QString purpose;
        QDateTime expiresAtUtc;
        bool valid = false;
    };

    struct AsyncResult
    {
        quint64 serial = 0;
        OperationKind operation = OperationKind::None;
        bool success = false;
        QString message;
        QString purpose;
        ComboRecord comboRecord;
        QByteArray candidateDigest;
        int tokenCount = 0;
        bool pamSessionEstablished = false;
        QStringList pamEnvironment;
        void *pamHandle = nullptr;
    };

    /*
        --------------------------------------------------------------------
                              SECURITY CONSTANTS
        --------------------------------------------------------------------
    */

    static constexpr int MinimumComboLength = 4;
    static constexpr int MaximumComboLength = 12;
    static constexpr int MaximumRollingInputs = 15;
    static constexpr int SetupAuthorizationSeconds = 300;
    static constexpr int HighPriorityAuthorizationSeconds = 900;

    /*
        Persistent deterministic lockout policy:

            1st failure  -> 5 seconds
            2nd failure  -> 30 seconds
            3rd failure  -> 5 minutes
            4th failure  -> 15 minutes
            5th+ failure -> 1 hour cap
    */

    int m_maxLockoutSeconds = 3600;
    int m_failedAttemptCooldownMs = 900;
    int m_highThreatCooldownMs = 1500;

    /*
        Legacy PBKDF2 values for verification/migration only.
    */

    int m_legacyPbkdf2Iterations = 210000;
    int m_legacySaltBytes = 32;
    int m_legacyHashBytes = 32;

    /*
        Argon2id settings for Raspberry Pi 4.

        64 MiB memory use is deliberate. Hashing must run through the async API
        for production QML.
    */

    unsigned long long m_argonOpsLimit = 3;
    std::size_t m_argonMemLimit =
        static_cast<std::size_t>(
            64ULL * 1024ULL * 1024ULL
        );

    /*
        --------------------------------------------------------------------
                              ACTIVE USER
        --------------------------------------------------------------------
    */

    QString m_activeUsername;
    QVariantMap m_activeUser;

    /*
        --------------------------------------------------------------------
                             PERSISTED STATE
        --------------------------------------------------------------------
    */

    ComboRecord m_comboRecord;
    PersistentState m_persistentState;

    int m_failedAttempts = 0;
    int m_highThreatAttempts = 0;

    int m_secondsRemaining = 0;
    int m_lockoutDelaySeconds = 0;
    int m_lockoutLevel = 0;

    bool m_lockedOut = false;
    bool m_loginComboConfigured = false;
    int m_comboLength = 0;

    QString m_lastFailureReason;
    QString m_lastHighThreatReason;

    /*
        Monotonic active lockout. The deadline is never persisted as authority.
    */

    QElapsedTimer m_monotonicClock;
    qint64 m_lockoutUntilMonotonicMs = 0;

    qint64 m_lastFailedAttemptMonotonicMs = -1;
    qint64 m_lastHighThreatMonotonicMs = -1;

    /*
        --------------------------------------------------------------------
                         SETUP AUTHORIZATION
        --------------------------------------------------------------------
    */

    SetupAuthorization m_setupAuthorization;
    QString m_highPriorityAuthorizedApp;
    QDateTime m_highPriorityAuthorizationExpiresAtUtc;

    /*
        --------------------------------------------------------------------
                              PAM STATE
        --------------------------------------------------------------------
    */

    void *m_pamHandle = nullptr;
    bool m_pamSessionOpen = false;
    QString m_pamSessionUser;
    QString m_pamLastError;
    QStringList m_pamEnvironment;

    /*
        --------------------------------------------------------------------
                            ASYNC OPERATION STATE
        --------------------------------------------------------------------
    */

    OperationKind m_operationKind = OperationKind::None;
    bool m_operationBusy = false;
    QString m_activeOperation;
    QString m_lastOperation;
    QString m_lastError;
    QVariantMap m_pendingSafePayload;
    quint64 m_operationSerial = 0;
    QPointer<NotificationManager> m_notificationManager;
    quint64 m_notificationClearSerial = 0;
    QString m_notificationClearUser;
    bool m_notificationClearPending = false;

    /*
        --------------------------------------------------------------------
                           TIMERS / FILE WATCHING
        --------------------------------------------------------------------
    */

    QTimer m_lockoutRefreshTimer;
    QTimer m_setupAuthorizationTimer;
    QTimer m_highPriorityAuthorizationTimer;
    QTimer m_refreshCoalesceTimer;

    QFileSystemWatcher m_fileWatcher;
    QSet<QString> m_watchedPaths;

    int m_securityRevision = 0;
    LoginConfiguration::State m_loginConfigurationState =
        LoginConfiguration::State::LoadingUnknown;

    /*
        --------------------------------------------------------------------
                                PATHS
        --------------------------------------------------------------------
    */

    QString neutronRootPath() const;
    QString legacySecurityDirPath() const;

    QString usersSecurityDirPath() const;
    QString activeUserSecurityDirPath() const;

    QString lockoutStateFilePath() const;
    QString comboFilePath(const QString &username) const;
    QString legacyComboFilePath(const QString &username) const;
    bool authoritativeSetupCompleted() const;

    void ensureSecurityDir() const;
    bool ensureSecureDirectory(const QString &path) const;

    bool setOwnerRootOnly(const QString &path) const;
    bool setOwnerOnlyPermissions(const QString &path,
                                 bool executable) const;

    bool pathIsRootOwnedOwnerOnly(const QString &path,
                                  bool directory) const;
    void setLoginConfigurationState(LoginConfiguration::State state);

    /*
        --------------------------------------------------------------------
                         ACTIVE USER VALIDATION
        --------------------------------------------------------------------
    */

    QString cleanUsername(const QString &username) const;

    bool localAccountExists(const QString &username,
                            QVariantMap *validatedUser = nullptr) const;

    bool validateActiveUserContext(const QVariantMap &userContext,
                                   QVariantMap *validatedUser,
                                   QString *errorMessage) const;

    bool usernameMatchesActiveUser(const QString &username) const;

    /*
        --------------------------------------------------------------------
                          STATE LOAD / SAVE
        --------------------------------------------------------------------
    */

    void loadState();
    void loadActiveUserState();

    PersistentState readPersistentState() const;
    ComboRecord readComboRecord(const QString &username) const;

    bool saveState();
    bool savePersistentState(const PersistentState &state);
    bool saveComboRecord(const ComboRecord &record);

    void applyPersistentState(const PersistentState &state);
    void applyComboRecord(const ComboRecord &record);

    void rebuildPublicState();
    void incrementSecurityRevision();

    /*
        --------------------------------------------------------------------
                           LOCKOUT INTERNALS
        --------------------------------------------------------------------
    */

    void startLockoutForCurrentFailureCount(const QString &reason);
    void startLockout(int seconds,
                      const QString &reason);

    int delayForFailedAttempts(int attempts) const;
    int levelForFailedAttempts(int attempts) const;

    bool failureCooldownActive() const;
    bool highThreatCooldownActive() const;

    bool shouldIgnoreFailureReason(const QString &reason) const;

    void setLoginComboConfigured(bool configured,
                                 int tokenCount = 0);

    /*
        --------------------------------------------------------------------
                        SETUP AUTHORIZATION INTERNALS
        --------------------------------------------------------------------
    */

    bool setupAuthorizationValid(const QString &purpose = QString()) const;

    void grantSetupAuthorization(const QString &username,
                                 const QString &purpose);

    QString normalizedPurpose(const QString &purpose) const;

    /*
        --------------------------------------------------------------------
                    USERNAME / COMBO NORMALIZATION
        --------------------------------------------------------------------
    */

    QStringList tokenizeCombo(const QString &combo,
                              bool *valid = nullptr,
                              bool allowRollingBuffer = false) const;

    QString canonicalToken(const QString &token) const;
    bool comboTokenAllowed(const QString &token) const;

    QString canonicalCombo(const QStringList &tokens) const;
    QString canonicalComboString(const QString &combo,
                                 bool *valid = nullptr) const;

    QStringList finalVerificationWindow(const QString &rollingBuffer,
                                        int requiredTokenCount,
                                        bool *valid = nullptr) const;

    /*
        --------------------------------------------------------------------
                             ARGON2ID HASHING
        --------------------------------------------------------------------
    */

    bool ensureSodiumReady() const;

    QByteArray argon2idHashCombo(const QByteArray &canonicalCombo) const;

    bool verifyArgon2idCombo(const QByteArray &canonicalCombo,
                             const QByteArray &encodedHash) const;

    /*
        Legacy PBKDF2 migration/verification.
    */

    QByteArray randomBytes(int count) const;

    QByteArray legacyPbkdf2Sha256(const QByteArray &password,
                                  const QByteArray &salt,
                                  int iterations,
                                  int derivedKeyLength) const;

    void resetFailuresAfterVerifiedAuthentication();

    bool verifyLegacyPbkdf2Record(const QJsonObject &record,
                                  const QByteArray &canonicalCombo) const;

    bool constantTimeEquals(const QByteArray &left,
                            const QByteArray &right) const;

    static void secureClear(QByteArray &buffer);
    static void secureClear(QString &text);

    /*
        --------------------------------------------------------------------
                                FILE I/O
        --------------------------------------------------------------------
    */

    QByteArray readFile(const QString &path) const;

    bool writeSecureJsonFile(const QString &path,
                             const QByteArray &json) const;

    bool writeSecureBytesFile(const QString &path,
                              const QByteArray &data) const;

    bool migrateLegacyComboForUser(const QString &username);

    /*
        --------------------------------------------------------------------
                              PAM HELPERS
        --------------------------------------------------------------------
    */

    bool openPamLoginSession(const QString &username,
                             const QString &password);

    bool verifyPamPasswordAndOpenSession(const QString &username,
                                         const QString &password);

    static bool authenticatePamInWorker(const QString &username,
                                        QByteArray password,
                                        bool openSession,
                                        AsyncResult *result);

    bool adoptPamSessionFromResult(const AsyncResult &result);
    void releasePamResultSession(const AsyncResult &result) const;

    void resetPamState();
    void setPamLastError(const QString &errorText);

    static int pamConversationCallback(int messageCount,
                                       const struct pam_message **messages,
                                       struct pam_response **responses,
                                       void *applicationData);

    /*
        --------------------------------------------------------------------
                         ASYNCHRONOUS DISPATCH
        --------------------------------------------------------------------
    */

    void dispatchLocalPasswordVerification(const QString &username,
                                           QByteArray password,
                                           const QString &purpose,
                                           quint64 serial);

    void dispatchComboCreation(const QString &username,
                               QByteArray canonicalCombo,
                               QByteArray confirmation,
                               quint64 serial);

    void dispatchComboVerification(const QString &username,
                                   QByteArray canonicalWindow,
                                   ComboRecord record,
                                   quint64 serial);

    void dispatchComboChange(const QString &username,
                             QByteArray currentWindow,
                             QByteArray newCombo,
                             QByteArray confirmation,
                             ComboRecord currentRecord,
                             bool recoveryAuthorized,
                             quint64 serial);

    void applyAsyncResult(const AsyncResult &result);

    /*
        --------------------------------------------------------------------
                         OPERATION LIFECYCLE
        --------------------------------------------------------------------
    */

    bool beginOperation(OperationKind operation,
                        const QString &action,
                        const QVariantMap &payload = QVariantMap());

    void finishOperation(const QString &action,
                         bool success,
                         const QString &message,
                         const QVariantMap &payload = QVariantMap());

    void setOperationBusy(bool busy);
    void setLastOperation(const QString &message);
    void setLastError(const QString &message);
    void clearPendingOperation();

    QString operationName(OperationKind operation) const;

    /*
        --------------------------------------------------------------------
                         PAYLOAD SANITIZATION
        --------------------------------------------------------------------
    */

    QVariantMap sanitizedPayload(const QVariantMap &payload) const;
    QVariantMap publicSecurityContext() const;

    /*
        --------------------------------------------------------------------
                          FILE WATCHER INTERNALS
        --------------------------------------------------------------------
    */

    void rebuildWatchers();
    void scheduleRefresh(int delayMs = 120);
};
