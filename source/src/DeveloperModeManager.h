#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QByteArray>
#include <QElapsedTimer>
#include <QTimer>
#include <QVariantMap>

/*
    ============================================================
                        DEVELOPER MODE MANAGER
    ============================================================

    Hardened global Developer Mode backend for NeutronOS.

    Ownership:
        - Developer Mode is Console-owned/global.
        - Terminal reads Developer Mode state only.
        - Terminal must not enable Developer Mode itself.

    Hardened state paths:
        /var/lib/neutronos/security/developer_mode.hash
        /var/lib/neutronos/developer_mode.enabled
        /var/lib/neutronos/security/developer_mode_lockout.json

    Fixes included:
        - Root-owned security state.
        - No plaintext developer combo/code storage.
        - Argon2id/libsodium KDF for new hashes.
        - Legacy PBKDF2 migration support.
        - Persistent failed-attempt counter.
        - Deterministic exponential lockout backoff.
        - Monotonic active lockout timer.
        - No wall-clock trust for unlock expiration.
*/

#ifndef NEUTRONOS_STATE_DIR
#define NEUTRONOS_STATE_DIR "/var/lib/neutronos"
#endif

#ifndef NEUTRONOS_SECURITY_STATE_DIR
#define NEUTRONOS_SECURITY_STATE_DIR "/var/lib/neutronos/security"
#endif

class DeveloperModeManager : public QObject
{
    Q_OBJECT

    /*
        Preferred QML properties.
    */
    Q_PROPERTY(bool developerModeEnabled READ developerModeEnabled NOTIFY developerModeChanged)
    Q_PROPERTY(bool developerModeConfigured READ developerModeConfigured NOTIFY developerModeChanged)
    Q_PROPERTY(bool setupRequired READ setupRequired NOTIFY developerModeChanged)

    /*
        Compatibility aliases for older QML.
    */
    Q_PROPERTY(bool enabled READ developerModeEnabled NOTIFY developerModeChanged)
    Q_PROPERTY(bool configured READ developerModeConfigured NOTIFY developerModeChanged)

    /* Compatibility properties used by the controller-first QML modal. */
    Q_PROPERTY(bool codeCreated READ developerModeConfigured NOTIFY configuredChanged)
    Q_PROPERTY(QString buttonState READ buttonState NOTIFY buttonStateChanged)
    Q_PROPERTY(QString error READ lastError NOTIFY errorChanged)

    /*
        Hardened lockout state.
    */
    Q_PROPERTY(bool lockedOut READ lockedOut NOTIFY lockoutChanged)
    Q_PROPERTY(int failedAttempts READ failedAttempts NOTIFY lockoutChanged)
    Q_PROPERTY(int secondsRemaining READ secondsRemaining NOTIFY lockoutChanged)
    Q_PROPERTY(int lockoutDelaySeconds READ lockoutDelaySeconds NOTIFY lockoutChanged)
    Q_PROPERTY(int lockoutLevel READ lockoutLevel NOTIFY lockoutChanged)

    /*
        Diagnostics.
    */
    Q_PROPERTY(QString securityDir READ securityDirPath CONSTANT)
    Q_PROPERTY(QString stateDir READ stateDirPath CONSTANT)
    Q_PROPERTY(QString kdfScheme READ kdfScheme CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY developerModeChanged)
    Q_PROPERTY(QString lastFailureReason READ lastFailureReason NOTIFY lockoutChanged)

public:
    explicit DeveloperModeManager(QObject *parent = nullptr);
    ~DeveloperModeManager() override = default;

    bool developerModeEnabled() const;
    bool developerModeConfigured() const;
    bool setupRequired() const;

    bool lockedOut() const;
    int failedAttempts() const;
    int secondsRemaining() const;
    int lockoutDelaySeconds() const;
    int lockoutLevel() const;

    QString securityDirPath() const;
    QString stateDirPath() const;
    QString kdfScheme() const;
    QString lastError() const;
    QString lastFailureReason() const;
    QString buttonState() const;

    /*
        ============================================================
                            STATE API
        ============================================================
    */

    Q_INVOKABLE bool isEnabled() const;
    Q_INVOKABLE bool isConfigured() const;
    Q_INVOKABLE bool isSetupRequired() const;

    Q_INVOKABLE void refresh();

    /*
        Disable Developer Mode immediately.

        This removes the enabled marker only. It does not erase the
        configured developer credential.
    */
    Q_INVOKABLE bool disableDeveloperMode();
    Q_INVOKABLE bool disable();
    Q_INVOKABLE bool turnOff();

    /*
        Clear all runtime Developer Mode state and credential.

        This is an admin/recovery function. Because the state path is now
        /var/lib/neutronos, it only succeeds when the process has permission.
    */
    Q_INVOKABLE bool resetDeveloperMode();

    /*
        ============================================================
                        SETUP / CREDENTIAL API
        ============================================================

        These accept controller combo strings or keyboard fallback codes.
        The caller should normalize visually, but this backend canonicalizes
        again before hashing.

        No plaintext credential is stored.
    */

    Q_INVOKABLE bool configureDeveloperMode(const QString &codeOrCombo);
    Q_INVOKABLE bool createDeveloperModeCredential(const QString &codeOrCombo);
    Q_INVOKABLE bool createDeveloperModeCombo(const QString &combo);
    Q_INVOKABLE bool setDeveloperModeCombo(const QString &combo);
    Q_INVOKABLE bool setDeveloperModePassword(const QString &code);
    Q_INVOKABLE bool setDeveloperModeCode(const QString &code);

    /*
        Compatibility helpers for DeveloperModeModal.qml. These keep all
        credential comparison and setup decisions in the hardened backend.
    */
    Q_INVOKABLE QString normalizeCode(const QString &codeOrCombo) const;
    Q_INVOKABLE QVariantMap validateCodeConfirmation(
        const QString &firstCode,
        const QString &confirmationCode
    );
    Q_INVOKABLE QVariantMap enableWithCode(const QString &codeOrCombo);

    /*
        ============================================================
                            ENABLE / VERIFY API
        ============================================================

        verifyDeveloperModeCredential():
            Verifies only.

        enableDeveloperMode():
            Verifies, then writes the enabled marker.

        verifyAndEnable():
            Compatibility alias.

        enable():
            Compatibility alias.
    */

    Q_INVOKABLE bool verifyDeveloperModeCredential(const QString &codeOrCombo);
    Q_INVOKABLE bool verifyDeveloperModeCombo(const QString &combo);
    Q_INVOKABLE bool verifyDeveloperModePassword(const QString &code);
    Q_INVOKABLE bool verifyCode(const QString &codeOrCombo);
    Q_INVOKABLE bool verifyCombo(const QString &combo);

    Q_INVOKABLE bool enableDeveloperMode(const QString &codeOrCombo);
    Q_INVOKABLE bool verifyAndEnable(const QString &codeOrCombo);
    Q_INVOKABLE bool enable(const QString &codeOrCombo);

    Q_INVOKABLE bool toggleDeveloperMode(const QString &codeOrCombo);

    /*
        ============================================================
                        FAILED ATTEMPTS / LOCKOUTS
        ============================================================
    */

    Q_INVOKABLE bool registerFailedAttempt();
    Q_INVOKABLE bool registerFailedAttemptWithReason(const QString &reason);

    Q_INVOKABLE void registerHighThreat();
    Q_INVOKABLE void registerHighThreatWithReason(const QString &reason);

    Q_INVOKABLE void registerSuccess();
    Q_INVOKABLE void clearLockout();

    /*
        Migration helper.

        Imports older files from:
            ~/NeutronOS/state/security/developer_mode.hash
            ~/NeutronOS/state/developer_mode.enabled

        Into:
            /var/lib/neutronos/security/developer_mode.hash
            /var/lib/neutronos/developer_mode.enabled
    */
    Q_INVOKABLE bool migrateLegacyDeveloperState();


    Q_INVOKABLE QString status() const;

signals:
    void developerModeChanged();
    void enabledChanged();
    void configuredChanged();
    void buttonStateChanged();
    void errorChanged();

    void developerModeEnabledChanged();
    void developerModeDisabledChanged();

    void lockoutChanged();
    void lockoutStarted();
    void lockoutCleared();

private:
    /*
        ============================================================
                            STATE
        ============================================================
    */

    bool m_developerModeEnabled = false;
    bool m_developerModeConfigured = false;

    QString m_lastError;
    QString m_lastFailureReason;
    QString m_lastHighThreatReason;

    /*
        Persistent failed-attempt counters.
    */
    int m_failedAttempts = 0;
    int m_highThreatAttempts = 0;

    bool m_lockedOut = false;
    int m_secondsRemaining = 0;
    int m_lockoutDelaySeconds = 0;
    int m_lockoutLevel = 0;

    /*
        Monotonic active lockout timer.
        Wall-clock time is diagnostic only and never trusted as the unlock
        authority.
    */
    QElapsedTimer m_monotonicClock;
    qint64 m_lockoutUntilMonotonicMs = 0;

    qint64 m_lastFailedAttemptMonotonicMs = -1;
    qint64 m_lastHighThreatMonotonicMs = -1;

    /*
        Rate-limit repeated UI calls.
    */
    int m_failedAttemptCooldownMs = 900;
    int m_highThreatCooldownMs = 1500;

    /*
        Deterministic lockout cap.
    */
    int m_maxLockoutSeconds = 3600;

    /*
        State file version.
    */
    int m_stateVersion = 2;

    /*
        Argon2id settings.

        Conservative for Raspberry Pi, memory-hard enough to avoid the old
        cheap GPU-only brute-force profile.
    */
    unsigned long long m_argonOpsLimit = 3;
    size_t m_argonMemLimit = 64 * 1024 * 1024;

    /*
        Legacy PBKDF2 verification/migration only.
        New hashes are Argon2id.
    */
    int m_legacyPbkdf2Iterations = 210000;

    QTimer m_lockoutRefreshTimer;

    /*
        ============================================================
                                PATHS
        ============================================================
    */

    QString neutronRootPath() const;
    QString legacySecurityDirPath() const;
    QString legacyStateDirPath() const;

    QString hashFilePath() const;
    QString enabledMarkerPath() const;
    QString lockoutStateFilePath() const;

    QString legacyHashFilePath() const;
    QString legacyEnabledMarkerPath() const;

    void ensureStateDirectories() const;
    void ensureSecureDirectory(const QString &path) const;

    bool securityDirectoryLooksSafe() const;

    /*
        ============================================================
                            LOAD / SAVE
        ============================================================
    */

    void loadState();
    void saveLockoutState();

    void loadEnabledState();
    void saveEnabledState(bool enabled);

    void loadConfiguredState();

    void setDeveloperModeEnabled(bool enabled);
    void setDeveloperModeConfigured(bool configured);
    void setLastError(const QString &errorText);

    /*
        ============================================================
                            LOCKOUTS
        ============================================================
    */

    void updateLockoutState();
    void startLockoutForCurrentFailureCount(const QString &reason);
    void startLockout(int seconds, const QString &reason);

    int delayForFailedAttempts(int attempts) const;
    int levelForFailedAttempts(int attempts) const;

    bool failureCooldownActive() const;
    bool highThreatCooldownActive() const;

    /*
        ============================================================
                        CREDENTIAL NORMALIZATION
        ============================================================
    */

    QStringList tokenizeCredential(const QString &credential) const;
    QString canonicalCredential(const QString &credential) const;
    QString canonicalCredential(const QStringList &tokens) const;

    bool credentialLooksValidForSetup(const QString &credential) const;

    /*
        ============================================================
                            ARGON2ID HASHING
        ============================================================
    */

    bool ensureSodiumReady() const;

    QByteArray argon2idHashCredential(const QByteArray &canonicalCredential) const;
    bool verifyArgon2idCredential(const QByteArray &canonicalCredential,
                                  const QByteArray &encodedHash) const;

    /*
        Legacy PBKDF2 support.
    */
    QByteArray legacyPbkdf2Sha256(const QByteArray &password,
                                  const QByteArray &salt,
                                  int iterations,
                                  int dkLen) const;

    bool constantTimeEquals(const QByteArray &a, const QByteArray &b) const;

    /*
        ============================================================
                                FILE I/O
        ============================================================
    */

    QByteArray readFile(const QString &path) const;

    bool writeSecureBytesFile(const QString &path, const QByteArray &data) const;
    bool writeSecureJsonFile(const QString &path, const QByteArray &json) const;

    bool removeSecureFile(const QString &path) const;

    bool setOwnerRootOnly(const QString &path) const;
    bool setOwnerOnlyPermissions(const QString &path, bool executable) const;
};