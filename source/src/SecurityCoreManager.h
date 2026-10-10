#pragma once

#include "SecureIpcClient.h"
#include "SecurityIndicatorSnapshot.h"

#include <QObject>
#include <QFutureWatcher>
#include <QJsonObject>
#include <QQueue>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class SecurityManager;

// Presentation-only adapter for the authoritative neutron-securityd service.
// This class owns no privileged policy, state files, audit stream, command
// execution, cryptography, firewall, recovery, or hardening implementation.
class SecurityCoreManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool indicatorOnline READ indicatorOnline NOTIFY indicatorChanged)
    Q_PROPERTY(int indicatorScore READ indicatorScore NOTIFY indicatorChanged)
    Q_PROPERTY(bool daemonOnline READ daemonOnline NOTIFY stateChanged)
    Q_PROPERTY(QString daemonStatus READ daemonStatus NOTIFY stateChanged)
    Q_PROPERTY(QString lastErrorCode READ lastErrorCode NOTIFY stateChanged)
    Q_PROPERTY(int securityScore READ securityScore NOTIFY stateChanged)
    Q_PROPERTY(int threatLevel READ threatLevel NOTIFY stateChanged)
    Q_PROPERTY(QString threatLabel READ threatLabel NOTIFY stateChanged)
    Q_PROPERTY(QString suggestedThreatReason READ suggestedThreatReason NOTIFY stateChanged)
    Q_PROPERTY(bool learningMode READ learningMode NOTIFY stateChanged)
    Q_PROPERTY(bool enforcementEnabled READ enforcementEnabled NOTIFY stateChanged)
    Q_PROPERTY(bool responseEngineEnabled READ responseEngineEnabled NOTIFY stateChanged)
    Q_PROPERTY(QVariantList events READ events NOTIFY stateChanged)
    Q_PROPERTY(QVariantList listeningPorts READ listeningPorts NOTIFY stateChanged)
    Q_PROPERTY(QVariantList bannedSources READ bannedSources NOTIFY stateChanged)
    Q_PROPERTY(QVariantList rejectedActivity READ rejectedActivity NOTIFY stateChanged)
    Q_PROPERTY(QVariantList auditEntries READ auditEntries NOTIFY stateChanged)
    Q_PROPERTY(QVariantList installedApps READ installedApps NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap sshStatus READ sshStatus NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap tailscaleStatus READ tailscaleStatus NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap vaultCombo READ vaultCombo NOTIFY stateChanged)
    Q_PROPERTY(QVariantList peripherals READ peripherals NOTIFY stateChanged)
    Q_PROPERTY(QVariantList malwareFindings READ malwareFindings NOTIFY stateChanged)
    Q_PROPERTY(QVariantList quarantinedItems READ quarantinedItems NOTIFY stateChanged)
    Q_PROPERTY(QVariantList quarantinedApps READ quarantinedApps NOTIFY stateChanged)
    Q_PROPERTY(QVariantList integrityChanges READ integrityChanges NOTIFY stateChanged)
    Q_PROPERTY(QString integrityStatus READ integrityStatus NOTIFY stateChanged)
    Q_PROPERTY(QVariantList hardeningProfiles READ hardeningProfiles NOTIFY stateChanged)
    Q_PROPERTY(QString activeHardeningProfile READ activeHardeningProfile NOTIFY stateChanged)
    Q_PROPERTY(bool hardeningRollbackAvailable READ hardeningRollbackAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool vaultUnlocked READ vaultUnlocked NOTIFY stateChanged)
    Q_PROPERTY(QVariantList vaultEntries READ vaultEntries NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap revealedVaultSecret READ revealedVaultSecret NOTIFY stateChanged)
    Q_PROPERTY(bool recoveryConfigured READ recoveryConfigured NOTIFY stateChanged)
    Q_PROPERTY(bool recoveryDeferred READ recoveryDeferred NOTIFY stateChanged)
    Q_PROPERTY(bool recoveryMinimumLocked READ recoveryMinimumLocked NOTIFY stateChanged)
    Q_PROPERTY(QString recoveryMethod READ recoveryMethod NOTIFY stateChanged)
    Q_PROPERTY(QString generatedRecoveryCode READ generatedRecoveryCode NOTIFY stateChanged)
    Q_PROPERTY(QVariantList recoveryUsbCandidates READ recoveryUsbCandidates NOTIFY stateChanged)
    Q_PROPERTY(bool auditValid READ auditValid NOTIFY stateChanged)
    Q_PROPERTY(QString auditHead READ auditHead NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap stats READ stats NOTIFY stateChanged)

public:
    explicit SecurityCoreManager(const QString &neutronRoot, SecurityManager *authManager,
                                 QObject *parent = nullptr);
    ~SecurityCoreManager() override;

    bool indicatorOnline() const { return m_indicator.online; }
    int indicatorScore() const { return m_indicator.score; }
    Q_INVOKABLE void refreshIndicator();
    bool daemonOnline() const { return m_daemonOnline; }
    QString daemonStatus() const { return m_daemonStatus; }
    QString lastErrorCode() const { return m_lastErrorCode; }
    int securityScore() const { return m_securityScore; }
    int threatLevel() const { return m_threatLevel; }
    QString threatLabel() const { return m_threatLabel; }
    QString suggestedThreatReason() const { return m_suggestedThreatReason; }
    bool learningMode() const { return m_learningMode; }
    bool enforcementEnabled() const { return m_enforcementEnabled; }
    bool responseEngineEnabled() const { return m_responseEngineEnabled; }
    QVariantList events() const { return m_events; }
    QVariantList listeningPorts() const { return m_listeningPorts; }
    QVariantList bannedSources() const { return m_bannedSources; }
    QVariantList rejectedActivity() const { return m_rejectedActivity; }
    QVariantList auditEntries() const { return m_auditEntries; }
    QVariantList installedApps() const { return m_installedApps; }
    QVariantMap sshStatus() const { return m_sshStatus; }
    QVariantMap tailscaleStatus() const { return m_tailscaleStatus; }
    QVariantMap vaultCombo() const { return m_vaultCombo; }
    QVariantList peripherals() const { return m_peripherals; }
    QVariantList malwareFindings() const { return m_malwareFindings; }
    QVariantList quarantinedItems() const { return m_quarantinedItems; }
    QVariantList quarantinedApps() const { return m_quarantinedApps; }
    QVariantList integrityChanges() const { return m_integrityChanges; }
    QString integrityStatus() const { return m_integrityStatus; }
    QVariantList hardeningProfiles() const { return m_hardeningProfiles; }
    QString activeHardeningProfile() const { return m_activeHardeningProfile; }
    bool hardeningRollbackAvailable() const { return m_hardeningRollbackAvailable; }
    bool vaultUnlocked() const { return m_vaultUnlocked; }
    QVariantList vaultEntries() const { return m_vaultEntries; }
    QVariantMap revealedVaultSecret() const { return m_revealedVaultSecret; }
    bool recoveryConfigured() const { return m_recoveryConfigured; }
    bool recoveryDeferred() const { return false; }
    bool recoveryMinimumLocked() const { return false; }
    QString recoveryMethod() const { return m_recoveryMethod; }
    QString generatedRecoveryCode() const { return m_generatedRecoveryCode; }
    QVariantList recoveryUsbCandidates() const { return m_recoveryUsbCandidates; }
    bool auditValid() const { return m_auditValid; }
    QString auditHead() const { return m_auditHead; }
    QVariantMap stats() const { return m_stats; }

    // Internal App Store restart authorization. This is deliberately not
    // Q_INVOKABLE: package QML cannot use it to create a login-bypass token.
    QVariantMap authenticatedSessionIdentity() const;

    Q_INVOKABLE void refresh();
    // Presentation lifecycle hint only. The daemon remains the authorization
    // boundary and independently verifies session, executable, UID and cgroup.
    Q_INVOKABLE void setShellSessionAuthenticated(bool authenticated);
    Q_INVOKABLE void setLearningMode(bool enabled);
    Q_INVOKABLE void setEnforcementEnabled(bool enabled);
    Q_INVOKABLE void setResponseEngineEnabled(bool enabled);
    Q_INVOKABLE void acknowledgeEvent(const QString &eventId);
    Q_INVOKABLE void acknowledgeAllEvents();
    Q_INVOKABLE void setEventFlagged(const QString &eventId, bool flagged);
    Q_INVOKABLE void neutralizeEvent(const QString &eventId);
    Q_INVOKABLE void setSshEnabled(bool enabled);
    Q_INVOKABLE void setTailscaleEnabled(bool enabled);
    Q_INVOKABLE void setVaultComboMode(const QString &mode);
    Q_INVOKABLE void setVaultCombo(const QString &combo);
    Q_INVOKABLE void verifyVaultCombo(const QString &combo);
    Q_INVOKABLE void previewHardening(const QString &actionId);
    Q_INVOKABLE void toggleHardeningAction(const QString &actionId);
    Q_INVOKABLE void selectAllHardening(bool selected);
    Q_INVOKABLE void applyHardening(const QString &actionId);
    Q_INVOKABLE void rollbackHardening();
    Q_INVOKABLE bool blockSource(const QString &address, int minutes = 1440);
    Q_INVOKABLE bool unblockSource(const QString &address);
    Q_INVOKABLE bool trustPeripheral(const QString &deviceId);
    Q_INVOKABLE bool allowPeripheralOnce(const QString &deviceId);
    Q_INVOKABLE bool blockPeripheral(const QString &deviceId);
    Q_INVOKABLE bool unlockVault(const QString &password);
    Q_INVOKABLE bool unlockVaultWithLoginCombo(const QString &combo);
    Q_INVOKABLE bool saveVaultEntry(const QString &entryId, const QString &name,
                                    const QString &username, const QString &password);
    Q_INVOKABLE bool revealVaultEntry(const QString &entryId);
    Q_INVOKABLE bool deleteVaultEntry(const QString &entryId);
    Q_INVOKABLE void clearRevealedVaultSecret();
    Q_INVOKABLE void lockVault();
    Q_INVOKABLE void generateRecoveryCode();
    Q_INVOKABLE bool confirmGeneratedRecoveryCode();
    Q_INVOKABLE bool deferRecoverySetup();
    Q_INVOKABLE bool enrollUsbRecovery(const QString &mountPath);
    Q_INVOKABLE bool verifyUsbRecovery();
    Q_INVOKABLE bool verifyRecoveryCode(const QString &code);
    Q_INVOKABLE void requestSnapshot();
    Q_INVOKABLE void scanDownloads();
    Q_INVOKABLE void scanNeutronOS();
    Q_INVOKABLE bool cancelMalwareScan();
    Q_INVOKABLE bool quarantineFinding(const QString &findingId);
    Q_INVOKABLE bool quarantineAppPackage(const QString &path);
    Q_INVOKABLE bool restoreQuarantinedApp(const QString &itemId);
    Q_INVOKABLE bool deleteQuarantinedApp(const QString &itemId);
    Q_INVOKABLE bool runQuarantinedApp(const QString &itemId, const QString &entrypoint, bool network = false);
    Q_INVOKABLE void refreshQuarantinedApps();
    Q_INVOKABLE void verifyIntegrity();
    Q_INVOKABLE void createIntegrityBaseline();
    // Shared presentation review flag. Authoritative approval still goes
    // through security.create-integrity-baseline in securityd.
    Q_INVOKABLE bool setIntegrityChangeFlagged(const QString &changeKey, bool flagged);
    Q_INVOKABLE bool setManualThreatLevel(int level);
    Q_INVOKABLE void deescalateToNormal();

signals:
    void indicatorChanged();
    void stateChanged();
    void operationFinished(bool success, const QString &message);
    void securityEventRaised(const QVariantMap &event);

private:
    struct Request { QString operation; QJsonObject arguments; bool snapshot = false; };
    struct Completion { Request request; SecureIpcClient::Result result; };

    bool enqueue(const QString &operation, const QJsonObject &arguments = {}, bool snapshot = false);
    void startNext();
    SecureIpcClient::Identity identity() const;
    QString activeSessionId(const QString &username) const;
    void applySnapshot(const QJsonObject &state);
    void markUnavailable(const QString &code, const QString &message);
    static QVariantList list(const QJsonObject &state, const char *name);
    static QString integrityChangeKey(const QVariantMap &change);

    QString m_neutronRoot;
    SecurityManager *m_authManager = nullptr;
    const QString m_socketPath = QStringLiteral("/run/neutronos/security/control.sock");
    QQueue<Request> m_requests;
    QFutureWatcher<Completion> m_watcher;
    SecurityIndicatorSnapshot m_indicator;
    QFutureWatcher<SecurityIndicatorSnapshot> m_indicatorWatcher;
    QTimer m_indicatorTimer;
    QTimer m_healthTimer;
    QTimer m_secretTimer;
    bool m_refreshQueued = false;
    bool m_shellSessionAuthenticated = false;
    int m_consecutiveIpcFailures = 0;
    bool m_eventBaselineReady = false;
    QSet<QString> m_seenEventIds;
    QSet<QString> m_flaggedIntegrityChangeKeys;

    bool m_daemonOnline = false;
    QString m_daemonStatus = QStringLiteral("Security service unavailable");
    QString m_lastErrorCode = QStringLiteral("service_unavailable");
    int m_securityScore = 0;
    int m_threatLevel = 5;
    QString m_threatLabel = QStringLiteral("DEFCON 5");
    QString m_suggestedThreatReason = QStringLiteral("Security service unavailable");
    bool m_learningMode = false;
    bool m_enforcementEnabled = false;
    bool m_responseEngineEnabled = false;
    QVariantList m_events, m_listeningPorts, m_bannedSources, m_peripherals;
    QVariantList m_rejectedActivity, m_auditEntries, m_installedApps;
    QVariantMap m_sshStatus, m_tailscaleStatus, m_vaultCombo;
    QVariantList m_malwareFindings, m_quarantinedItems, m_quarantinedApps, m_integrityChanges;
    QString m_integrityStatus = QStringLiteral("UNAVAILABLE");
    QVariantList m_hardeningProfiles;
    QString m_activeHardeningProfile = QStringLiteral("none");
    bool m_hardeningRollbackAvailable = false;
    bool m_vaultUnlocked = false;
    QVariantList m_vaultEntries;
    QVariantMap m_revealedVaultSecret;
    bool m_recoveryConfigured = false;
    QString m_recoveryMethod = QStringLiteral("none");
    QString m_generatedRecoveryCode;
    QVariantList m_recoveryUsbCandidates;
    bool m_auditValid = false;
    QString m_auditHead = QStringLiteral("Unavailable");
    QVariantMap m_stats;
};
