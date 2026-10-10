#pragma once

#include <QObject>
#include <QByteArray>
#include <QDateTime>
#include <QElapsedTimer>
#include <QList>
#include <QPointer>
#include <QHash>
#include <QJsonObject>
#include <QMap>
#include <QMetaType>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QFutureWatcher>

#include "SecureIpcClient.h"

#include <QtDBus/QDBusArgument>

class QDBusInterface;
class QDBusMessage;
class QDBusPendingCallWatcher;
class QNetworkAccessManager;
class QNetworkReply;
class QProcess;

/*
    NetworkManager's connection-settings payload uses the D-Bus signature:

        a{sa{sv}}

    Qt does not provide a named public alias for that exact shape, so
    NeutronOS registers this type once in NetworkManager.cpp.
*/
using NeutronNetworkSettings = QMap<QString, QVariantMap>;

Q_DECLARE_METATYPE(NeutronNetworkSettings)

QDBusArgument &operator<<(QDBusArgument &argument,
                          const NeutronNetworkSettings &settings);

const QDBusArgument &operator>>(const QDBusArgument &argument,
                                NeutronNetworkSettings &settings);

/*
    ========================================================================
                            NETWORK MANAGER BACKEND
    ========================================================================

    NetworkManager is the production Wi-Fi backend for NeutronOS.

    It talks to the system NetworkManager service over D-Bus:

        org.freedesktop.NetworkManager

    It does not parse command-line output and does not invoke sudo.

    Responsibilities:

        - Discover the active wireless device.
        - Expose the current SSID, signal, security, IP, gateway, and DNS.
        - Expose available access points.
        - Expose saved Wi-Fi profiles.
        - Request scans only when explicitly asked.
        - Connect to saved and unsaved networks.
        - Add hidden networks.
        - Disconnect the active Wi-Fi connection.
        - Forget saved profiles.
        - Toggle Wi-Fi through NetworkManager.
        - Return structured operation results to QML.
        - Avoid storing or logging plaintext passwords.

    The NetworkManagerModal.qml action contract is:

        scan
        connect
        disconnect
        forget
        addHidden
        refresh
        speedTest
        diagnostics
        repairConnection
        restartWifiManager
        cancel

    "requestKeyboard" remains a Console/UI action and must not be passed to
    this backend.
*/

class NetworkManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int connectivity READ connectivity NOTIFY connectivityChanged)

    /*
        --------------------------------------------------------------------
                          AVAILABLE NETWORK MODELS
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QVariantList availableNetworks
               READ availableNetworks
               NOTIFY availableNetworksChanged)

    Q_PROPERTY(QVariantList networks
               READ availableNetworks
               NOTIFY availableNetworksChanged)

    Q_PROPERTY(QVariantList wifiNetworks
               READ availableNetworks
               NOTIFY availableNetworksChanged)

    Q_PROPERTY(QVariantList savedNetworks
               READ savedNetworks
               NOTIFY savedNetworksChanged)

    Q_PROPERTY(QVariantList knownNetworks
               READ savedNetworks
               NOTIFY savedNetworksChanged)

    Q_PROPERTY(QVariantList wifiProfiles
               READ savedNetworks
               NOTIFY savedNetworksChanged)

    /*
        --------------------------------------------------------------------
                         CURRENT CONNECTION STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QVariantMap connectedNetwork
               READ connectedNetwork
               NOTIFY connectedNetworkChanged)

    Q_PROPERTY(QVariantMap currentNetwork
               READ connectedNetwork
               NOTIFY connectedNetworkChanged)

    Q_PROPERTY(QString connectedSsid
               READ connectedSsid
               NOTIFY connectedSsidChanged)

    Q_PROPERTY(QString ssid
               READ connectedSsid
               NOTIFY connectedSsidChanged)

    Q_PROPERTY(QString currentSsid
               READ connectedSsid
               NOTIFY connectedSsidChanged)

    Q_PROPERTY(QString connectionState
               READ connectionState
               NOTIFY connectionStateChanged)

    Q_PROPERTY(QString networkState
               READ connectionState
               NOTIFY connectionStateChanged)

    Q_PROPERTY(QString wifiState
               READ connectionState
               NOTIFY connectionStateChanged)

    Q_PROPERTY(QString activeConnectionId
               READ activeConnectionId
               NOTIFY connectedNetworkChanged)

    Q_PROPERTY(QString activeConnectionUuid
               READ activeConnectionUuid
               NOTIFY connectedNetworkChanged)

    /*
        --------------------------------------------------------------------
                             RADIO / SERVICE STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool available
               READ available
               NOTIFY availabilityChanged)

    Q_PROPERTY(bool networkingEnabled
               READ networkingEnabled
               NOTIFY networkingEnabledChanged)

    Q_PROPERTY(bool wifiEnabled
               READ wifiEnabled
               NOTIFY wifiEnabledChanged)

    Q_PROPERTY(bool wirelessEnabled
               READ wifiEnabled
               NOTIFY wifiEnabledChanged)

    Q_PROPERTY(bool wirelessHardwareEnabled
               READ wirelessHardwareEnabled
               NOTIFY wirelessHardwareEnabledChanged)

    Q_PROPERTY(bool scanning
               READ scanning
               NOTIFY scanningChanged)

    Q_PROPERTY(bool scanInProgress
               READ scanning
               NOTIFY scanningChanged)

    Q_PROPERTY(bool operationBusy
               READ operationBusy
               NOTIFY operationBusyChanged)

    /*
        --------------------------------------------------------------------
                         ADDRESS / LINK INFORMATION
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString interfaceName
               READ interfaceName
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString wifiInterface
               READ interfaceName
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString localIp
               READ localIp
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString ipv4
               READ localIp
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString ipAddress
               READ localIp
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString gateway
               READ gateway
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString defaultGateway
               READ gateway
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QVariantList dnsServers
               READ dnsServers
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QVariantList dns
               READ dnsServers
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QVariantList nameServers
               READ dnsServers
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString tailscaleIp
               READ tailscaleIp
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString tailnetIp
               READ tailscaleIp
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(int signalPercent
               READ signalPercent
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(int wifiSignalPercent
               READ signalPercent
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(int connectedSignal
               READ signalPercent
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString currentSecurity
               READ currentSecurity
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString securityType
               READ currentSecurity
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString wifiSecurity
               READ currentSecurity
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString frequency
               READ frequency
               NOTIFY networkDetailsChanged)

    Q_PROPERTY(QString band
               READ frequency
               NOTIFY networkDetailsChanged)

    /*
        --------------------------------------------------------------------
                      SPEED TEST / DIAGNOSTIC STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool speedTestRunning
               READ speedTestRunning
               NOTIFY speedTestRunningChanged)

    Q_PROPERTY(double downloadMbps
               READ downloadMbps
               NOTIFY speedTestResultsChanged)

    Q_PROPERTY(double uploadMbps
               READ uploadMbps
               NOTIFY speedTestResultsChanged)

    Q_PROPERTY(int latencyMs
               READ latencyMs
               NOTIFY speedTestResultsChanged)

    Q_PROPERTY(QString speedTestStatus
               READ speedTestStatus
               NOTIFY speedTestStatusChanged)

    Q_PROPERTY(QString speedTestLastRun
               READ speedTestLastRun
               NOTIFY speedTestResultsChanged)

    Q_PROPERTY(int speedTestIntervalMinutes
               READ speedTestIntervalMinutes
               CONSTANT)

    Q_PROPERTY(bool diagnosticsRunning
               READ diagnosticsRunning
               NOTIFY diagnosticsRunningChanged)

    Q_PROPERTY(QVariantList diagnosticResults
               READ diagnosticResults
               NOTIFY diagnosticResultsChanged)

    Q_PROPERTY(QString diagnosticsSummary
               READ diagnosticsSummary
               NOTIFY diagnosticsSummaryChanged)

    /*
        --------------------------------------------------------------------
                              STATUS / REVISION
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString lastError
               READ lastError
               NOTIFY lastErrorChanged)

    Q_PROPERTY(QString lastOperation
               READ lastOperation
               NOTIFY lastOperationChanged)

    Q_PROPERTY(int networkRevision
               READ networkRevision
               NOTIFY networkRevisionChanged)

    Q_PROPERTY(QVariantMap offlineNetworkState READ offlineNetworkState NOTIFY offlineNetworkStateChanged)
    Q_PROPERTY(bool offlineNetworkBusy READ offlineNetworkBusy NOTIFY offlineNetworkBusyChanged)
    Q_PROPERTY(QString offlineNetworkError READ offlineNetworkError NOTIFY offlineNetworkStateChanged)

public:
    explicit NetworkManager(QObject *parent = nullptr);
    ~NetworkManager() override;

    /*
        Available and saved networks.
    */
    QVariantList availableNetworks() const;
    QVariantList savedNetworks() const;

    /*
        Current connection.
    */
    QVariantMap connectedNetwork() const;
    QString connectedSsid() const;
    QString connectionState() const;
    int connectivity() const { return m_connectivity; }
    QString activeConnectionId() const;
    QString activeConnectionUuid() const;

    /*
        Service/radio state.
    */
    bool available() const;
    bool networkingEnabled() const;
    bool wifiEnabled() const;
    bool wirelessHardwareEnabled() const;
    bool scanning() const;
    bool operationBusy() const;

    /*
        Link details.
    */
    QString interfaceName() const;
    QString localIp() const;
    QString gateway() const;
    QVariantList dnsServers() const;
    QString tailscaleIp() const;
    int signalPercent() const;
    QString currentSecurity() const;
    QString frequency() const;

    /*
        Lightweight automatic network benchmark and diagnostics.
    */
    bool speedTestRunning() const;
    double downloadMbps() const;
    double uploadMbps() const;
    int latencyMs() const;
    QString speedTestStatus() const;
    QString speedTestLastRun() const;
    int speedTestIntervalMinutes() const;

    bool diagnosticsRunning() const;
    QVariantList diagnosticResults() const;
    QString diagnosticsSummary() const;

    /*
        Status.
    */
    QString lastError() const;
    QString lastOperation() const;
    int networkRevision() const;
    QVariantMap offlineNetworkState() const { return m_offlineNetworkState; }
    bool offlineNetworkBusy() const { return m_offlineNetworkBusy; }
    QString offlineNetworkError() const { return m_offlineNetworkError; }

    /*
        Full refresh does not automatically request a Wi-Fi scan.
        It only reloads current NetworkManager state and cached AP data.
    */
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshStatus();
    Q_INVOKABLE void refreshNetworks();
    Q_INVOKABLE void refreshSavedNetworks();

    /*
        Scanning is always explicit. Repeated requests are coalesced and rate
        limited so NetworkManager is not spammed by controller input.
    */
    Q_INVOKABLE bool requestScan();
    Q_INVOKABLE bool scan();

    /*
        Generic action entry point used by Console.qml.
    */
    Q_INVOKABLE bool executeAction(const QString &action,
                                   const QVariantMap &payload = QVariantMap());

    /*
        Direct methods are also exposed for backend tests and other apps.
    */
    Q_INVOKABLE bool connectToNetwork(const QVariantMap &payload);
    Q_INVOKABLE bool disconnectCurrent();
    Q_INVOKABLE bool forgetNetwork(const QVariantMap &payload);
    Q_INVOKABLE bool addHiddenNetwork(const QVariantMap &payload);
    Q_INVOKABLE bool setWifiEnabled(bool enabled);

    /*
        Patch 14 network tools. The automatic speed test repeats every
        ten minutes while an Internet connection is available.
    */
    Q_INVOKABLE bool runSpeedTest();
    Q_INVOKABLE bool runQuickSpeedProbe();
    Q_INVOKABLE bool runDiagnostics();
    Q_INVOKABLE bool repairConnection();
    Q_INVOKABLE bool restartWifiManager();
    Q_INVOKABLE bool refreshOfflineNetwork();
    Q_INVOKABLE bool setOfflineNetworkMode(const QString &mode);
    Q_INVOKABLE bool setOfflineNetworkDns(const QString &target, bool enabled, bool wildcard);
    Q_INVOKABLE bool setOfflineWifiPassword(const QString &password, const QString &confirmation);

    /*
        Cancels only local pending UI/backend bookkeeping. NetworkManager
        operations already submitted over D-Bus may still finish.
    */
    Q_INVOKABLE void cancelPendingOperation();

signals:
    /*
        Compatibility aggregate signal.
    */
    void networkChanged();

    /*
        Domain-specific model and state signals.
    */
    void availableNetworksChanged();
    void savedNetworksChanged();
    void connectedNetworkChanged();
    void connectedSsidChanged();
    void connectionStateChanged();
    void connectivityChanged();

    void availabilityChanged();
    void networkingEnabledChanged();
    void wifiEnabledChanged();
    void wirelessHardwareEnabledChanged();
    void scanningChanged();
    void operationBusyChanged();

    void networkDetailsChanged();

    void speedTestRunningChanged();
    void speedTestResultsChanged();
    void speedTestStatusChanged();

    void diagnosticsRunningChanged();
    void diagnosticResultsChanged();
    void diagnosticsSummaryChanged();

    void lastErrorChanged();
    void lastOperationChanged();
    void networkRevisionChanged();
    void offlineNetworkStateChanged();
    void offlineNetworkBusyChanged();
    void offlineNetworkOperationFinished(bool success, const QString &message);

    /*
        Operation lifecycle signals consumed by Console.qml.
    */
    void operationStarted(const QString &action,
                          const QVariantMap &payload);

    void operationFinished(const QString &action,
                           bool success,
                           const QString &message,
                           const QVariantMap &payload);

    void scanFinished(bool success,
                      const QString &message);

private slots:
    /*
        D-Bus service and property change handlers.
    */
    void onServiceRegistered(const QString &serviceName);
    void onServiceUnregistered(const QString &serviceName);

    void onRootPropertiesChanged(const QString &interfaceName,
                                 const QVariantMap &changedProperties,
                                 const QStringList &invalidatedProperties);

    void onDevicePropertiesChanged(const QString &interfaceName,
                                   const QVariantMap &changedProperties,
                                   const QStringList &invalidatedProperties);

    void onAccessPointPropertiesChanged(const QString &interfaceName,
                                        const QVariantMap &changedProperties,
                                        const QStringList &invalidatedProperties);

    void onActiveConnectionPropertiesChanged(const QString &interfaceName,
                                             const QVariantMap &changedProperties,
                                             const QStringList &invalidatedProperties);

    void onIpConfigurationPropertiesChanged(const QString &interfaceName,
                                            const QVariantMap &changedProperties,
                                            const QStringList &invalidatedProperties);

    void onSettingsConnectionUpdated();
    void onSettingsConnectionRemoved();

    /*
        Asynchronous D-Bus replies.
    */
    void onScanRequestFinished(QDBusPendingCallWatcher *watcher);
    void onActivateConnectionFinished(QDBusPendingCallWatcher *watcher);
    void onAddAndActivateConnectionFinished(QDBusPendingCallWatcher *watcher);
    void onDisconnectFinished(QDBusPendingCallWatcher *watcher);
    void onForgetFinished(QDBusPendingCallWatcher *watcher);
    void onWifiToggleFinished(QDBusPendingCallWatcher *watcher);

    /*
        Timers.
    */
    void finishScanRefresh();
    void handleScanTimeout();
    void coalescedRefresh();
    void passiveStatusRefresh();

private:
    struct AccessPointRecord
    {
        QString path;
        QString id;
        QString ssid;
        QString bssid;
        QString security;
        QString frequencyText;
        uint frequencyMhz = 0;
        int signalPercent = 0;
        bool hidden = false;
        bool saved = false;
        bool connected = false;
        QDateTime lastSeen;
    };

    struct SavedConnectionRecord
    {
        QString path;
        QString id;
        QString uuid;
        QString ssid;
        QString security;
        bool autoConnect = true;
        bool connected = false;
        bool hidden = false;
        qlonglong timestamp = 0;
    };

    struct DiagnosticStep
    {
        QString id;
        QString label;
        QString program;
        QStringList arguments;
    };

    enum class SpeedPhase
    {
        Idle,
        Latency,
        Download,
        Upload
    };

    /*
        Timers never trigger wireless scans. They only refresh already-known
        NetworkManager state and coalesce signal bursts.
    */
    QTimer m_passiveRefreshTimer;
    QTimer m_refreshCoalesceTimer;
    QTimer m_scanSettleTimer;
    QTimer m_scanTimeoutTimer;
    QTimer m_speedTestTimer;
    QTimer m_speedPhaseTimeoutTimer;

    /*
        Public models.
    */
    QVariantList m_availableNetworks;
    QVariantList m_savedNetworks;
    QVariantMap m_connectedNetwork;

    /*
        Service and radio state.
    */
    bool m_available = false;
    bool m_networkingEnabled = false;
    bool m_wifiEnabled = false;
    bool m_wirelessHardwareEnabled = false;
    bool m_scanning = false;
    bool m_operationBusy = false;

    /*
        Current connection details.
    */
    QString m_connectedSsid;
    int m_connectivity = 0; // NetworkManager: unknown=0, none=1, portal=2, limited=3, full=4
    QString m_connectionState = QStringLiteral("DISCONNECTED");
    QString m_activeConnectionId;
    QString m_activeConnectionUuid;

    QString m_interfaceName;
    QString m_localIp = QStringLiteral("--");
    QString m_gateway = QStringLiteral("--");
    QVariantList m_dnsServers;
    QString m_tailscaleIp = QStringLiteral("--");
    int m_signalPercent = 0;
    QString m_currentSecurity = QStringLiteral("--");
    QString m_frequency = QStringLiteral("--");

    /*
        Patch 14 benchmark and diagnostics state.
    */
    QNetworkAccessManager *m_networkAccessManager = nullptr;
    QPointer<QNetworkReply> m_speedReply;
    QElapsedTimer m_speedElapsed;
    QPointer<QNetworkReply> m_quickSpeedReply;
    QElapsedTimer m_quickSpeedElapsed;
    bool m_quickSpeedProbeRunning = false;
    QByteArray m_quickUploadPayload;
    SpeedPhase m_speedPhase = SpeedPhase::Idle;
    bool m_speedTestRunning = false;
    double m_downloadMbps = 0.0;
    double m_uploadMbps = 0.0;
    int m_latencyMs = -1;
    QString m_speedTestStatus = QStringLiteral("Waiting for first automatic test");
    QDateTime m_lastSpeedTest;
    QByteArray m_uploadPayload;

    bool m_diagnosticsRunning = false;
    QVariantList m_diagnosticResults;
    QString m_diagnosticsSummary = QStringLiteral("Not run yet");
    QList<DiagnosticStep> m_diagnosticQueue;
    int m_diagnosticIndex = 0;
    QPointer<QProcess> m_diagnosticProcess;

    QPointer<QProcess> m_maintenanceProcess;
    QString m_maintenanceAction;
    int m_repairStage = 0;

    /*
        Object paths discovered from NetworkManager.
    */
    QString m_wirelessDevicePath;
    QString m_activeAccessPointPath;
    QString m_activeConnectionPath;
    QString m_activeIp4ConfigPath;
    QString m_activeDhcp4ConfigPath;

    /*
        Internal caches keyed by D-Bus object path or stable profile UUID.
    */
    QHash<QString, AccessPointRecord> m_accessPoints;
    QHash<QString, SavedConnectionRecord> m_savedConnections;
    QHash<QString, QString> m_savedConnectionBySsid;
    QSet<QString> m_connectedSignalPaths;

    /*
        Operation state.
    */
    QString m_lastError;
    QString m_lastOperation;
    QString m_pendingAction;
    QVariantMap m_pendingPayload;
    QDateTime m_lastScanRequest;
    qlonglong m_scanStartTimestamp = -1;
    int m_networkRevision = 0;
    QVariantMap m_offlineNetworkState;
    QString m_offlineNetworkError;
    bool m_offlineNetworkBusy = false;
    QFutureWatcher<SecureIpcClient::Result> m_offlineNetworkWatcher;
    quint64 m_operationSerial = 0;

    /*
        Service setup.
    */
    void initializeServiceWatch();
    void initializeDbusTypes();
    void connectRootSignals();
    void disconnectDynamicSignals();
    void resetUnavailableState();

    /*
        Refresh orchestration.
    */
    void scheduleRefresh(int delayMs = 0);
    void refreshRootState();
    void discoverWirelessDevice();
    void refreshWirelessDevice();
    void refreshAccessPoints();
    void refreshSavedConnectionsInternal();
    void refreshActiveConnection();
    void refreshIpConfiguration();
    void refreshTailscaleAddress();
    void rebuildPublicModels();
    void rebuildConnectedNetwork();
    void incrementRevision();

    /*
        Patch 14 speed test, diagnostics, and repair helpers.
    */
    void startLatencyProbe();
    void startDownloadProbe();
    void startUploadProbe();
    void finishSpeedTest(bool success, const QString &message);
    void abortSpeedReply();
    void startQuickDownloadProbe();
    void startQuickUploadProbe();
    void finishQuickSpeedProbe(bool success);
    void abortQuickSpeedProbe();

    void buildDiagnosticQueue();
    void startNextDiagnosticStep();
    void appendDiagnosticResult(const DiagnosticStep &step,
                                bool success,
                                const QString &detail);
    void finishDiagnostics();

    QString findExecutable(const QStringList &names) const;
    bool startMaintenanceProcess(const QString &action,
                                 const QString &program,
                                 const QStringList &arguments);
    void handleMaintenanceFinished(int exitCode,
                                   int exitStatus);
    bool requestOfflineNetwork(const QString &operation, const QJsonObject &arguments = {});
    SecureIpcClient::Identity offlineNetworkIdentity() const;

    /*
        D-Bus property helpers.
    */
    QVariant readProperty(const QString &path,
                          const QString &interfaceName,
                          const QString &propertyName,
                          bool *ok = nullptr) const;

    QVariantMap readAllProperties(const QString &path,
                                  const QString &interfaceName,
                                  bool *ok = nullptr) const;

    QStringList objectPathList(const QVariant &value) const;
    QString objectPathString(const QVariant &value) const;

    /*
        Model conversion helpers.
    */
    AccessPointRecord readAccessPoint(const QString &path) const;
    SavedConnectionRecord readSavedConnection(const QString &path) const;

    QVariantMap accessPointToMap(const AccessPointRecord &record) const;
    QVariantMap savedConnectionToMap(const SavedConnectionRecord &record) const;

    QString decodeSsid(const QVariant &value) const;
    QString securityFromAccessPointFlags(uint flags,
                                         uint wpaFlags,
                                         uint rsnFlags) const;

    QString securityFromSettings(const NeutronNetworkSettings &settings) const;
    QString frequencyLabel(uint frequencyMhz) const;
    int normalizedSignal(const QVariant &value) const;

    /*
        Connection lookup and validation.
    */
    QString findSavedConnectionPath(const QVariantMap &payload) const;
    QString findAccessPointPath(const QVariantMap &payload) const;
    QString payloadSsid(const QVariantMap &payload) const;
    QString payloadSecurity(const QVariantMap &payload) const;

    bool validateConnectPayload(const QVariantMap &payload,
                                QString *errorMessage) const;

    bool validateHiddenPayload(const QVariantMap &payload,
                               QString *errorMessage) const;

    /*
        D-Bus connection-settings generation.
    */
    NeutronNetworkSettings buildConnectionSettings(
        const QVariantMap &payload,
        bool hidden) const;

    QVariantMap buildWirelessSecuritySection(
        const QString &security,
        const QString &password) const;

    /*
        Operations.
    */
    bool activateSavedConnection(const QString &connectionPath,
                                 const QString &accessPointPath,
                                 const QVariantMap &payload);

    bool addAndActivateConnection(const QVariantMap &payload,
                                  bool hidden);

    bool deactivateConnection(const QString &activeConnectionPath,
                              const QVariantMap &payload);

    bool deleteSavedConnection(const QString &connectionPath,
                               const QVariantMap &payload);

    /*
        Operation lifecycle.
    */
    void beginOperation(const QString &action,
                        const QVariantMap &payload);

    void finishOperation(const QString &action,
                         bool success,
                         const QString &message,
                         const QVariantMap &payload = QVariantMap());

    void setOperationBusy(bool busy);
    void setScanning(bool scanning);
    void setLastError(const QString &message);
    void setLastOperation(const QString &message);

    /*
        Sensitive data must not be retained after a D-Bus request is built.
    */
    QVariantMap sanitizedPayload(const QVariantMap &payload) const;
    void clearPendingSensitiveData();

    /*
        Address conversion helpers.
    */
    QString ipv4FromUInt(uint value) const;
    QVariantList dnsFromUIntList(const QVariant &value) const;
    QString detectTailscaleIp() const;
};
