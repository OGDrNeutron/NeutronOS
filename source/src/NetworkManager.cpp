#include "NetworkManager.h"

#include <QAbstractSocket>
#include <QByteArray>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QHostAddress>
#include <QNetworkAddressEntry>
#include <QNetworkAccessManager>
#include <QNetworkInterface>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QUuid>
#include <QVariantList>
#include <QtEndian>
#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>
#include <utility>

namespace
{
const QString ServiceName =
    QStringLiteral(
        "org.freedesktop.NetworkManager"
    );

const QString RootPath =
    QStringLiteral(
        "/org/freedesktop/NetworkManager"
    );

const QString RootInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager"
    );

const QString PropertiesInterface =
    QStringLiteral(
        "org.freedesktop.DBus.Properties"
    );

const QString DeviceInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager.Device"
    );

const QString WirelessInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager.Device.Wireless"
    );

const QString AccessPointInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager.AccessPoint"
    );

const QString SettingsPath =
    QStringLiteral(
        "/org/freedesktop/NetworkManager/Settings"
    );

const QString SettingsInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager.Settings"
    );

const QString SettingsConnectionInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager.Settings.Connection"
    );

const QString ActiveConnectionInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager.Connection.Active"
    );

const QString Ip4ConfigInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager.IP4Config"
    );

const QString Dhcp4ConfigInterface =
    QStringLiteral(
        "org.freedesktop.NetworkManager.DHCP4Config"
    );

constexpr uint DeviceTypeWifi = 2;

constexpr uint AccessPointPrivacyFlag = 0x00000001;
constexpr uint SecurityKeyManagementPsk = 0x00000100;
constexpr uint SecurityKeyManagement8021x = 0x00000200;
constexpr uint SecurityKeyManagementSae = 0x00000400;
constexpr uint SecurityKeyManagementOwe = 0x00000800;
constexpr uint SecurityKeyManagementOweTransition = 0x00001000;

constexpr int ScanMinimumIntervalMs = 8000;
constexpr int ScanSettleDelayMs = 2200;
constexpr int ScanTimeoutMs = 60000;
constexpr int PassiveRefreshIntervalMs = 12000;
constexpr int DbusOperationTimeoutMs = 30000;

constexpr int AutoSpeedTestIntervalMs = 10 * 60 * 1000;
constexpr int InitialSpeedTestDelayMs = 45 * 1000;
constexpr int SpeedPhaseTimeoutMs = 25 * 1000;
constexpr qint64 SpeedDownloadBytes = 2 * 1000 * 1000;
constexpr qint64 SpeedUploadBytes = 512 * 1024;
// Dashboard background estimate: intentionally tiny. At one probe every
// 20 seconds this is roughly 338 MiB/day if the dashboard remains visible
// continuously, and no probe is allowed to overlap a precise manual test.
constexpr qint64 QuickSpeedUploadBytes = 16 * 1024;
constexpr int QuickSpeedTimeoutMs = 6000;
constexpr int DiagnosticStepTimeoutMs = 7000;
constexpr int MaintenanceTimeoutMs = 25000;
const QString OfflineNetworkSocket = QStringLiteral("/run/neutronos/offline-network/control.sock");

QString sessionFileValue(const QByteArray &contents, const QByteArray &key)
{
    for (const QByteArray &line : contents.split('\n')) {
        if (line.startsWith(key + '='))
            return QString::fromUtf8(line.mid(key.size() + 1)).trimmed();
    }
    return {};
}

const QUrl SpeedLatencyUrl(
    QStringLiteral(
        "https://speed.cloudflare.com/__down?bytes=1024"
    )
);

const QUrl SpeedDownloadUrl(
    QStringLiteral(
        "https://speed.cloudflare.com/__down?bytes=2000000"
    )
);

const QUrl SpeedUploadUrl(
    QStringLiteral(
        "https://speed.cloudflare.com/__up"
    )
);

const QUrl QuickSpeedDownloadUrl(
    QStringLiteral(
        "https://speed.cloudflare.com/__down?bytes=65536"
    )
);

const QUrl QuickSpeedUploadUrl(
    QStringLiteral(
        "https://speed.cloudflare.com/__up"
    )
);

QString normalizedActionName(const QString &action)
{
    QString result =
        action.trimmed().toLower();

    result.remove(
        QRegularExpression(
            QStringLiteral("[\\s_\\-]")
        )
    );

    return result;
}

QString uppercaseSecurity(const QString &value)
{
    QString security =
        value.trimmed().toUpper();

    if (security.isEmpty() ||
            security == QStringLiteral("NONE") ||
            security ==
            QStringLiteral("UNSECURED")) {
        return QStringLiteral("OPEN");
    }

    if (security.contains(
            QStringLiteral("WPA3")) &&
            security.contains(
                QStringLiteral("WPA2"))) {
        return QStringLiteral("WPA2/WPA3");
    }

    if (security.contains(
            QStringLiteral("WPA3"))) {
        return QStringLiteral("WPA3");
    }

    if (security.contains(
            QStringLiteral("WPA2"))) {
        return QStringLiteral("WPA2");
    }

    if (security.contains(
            QStringLiteral("WPA")) &&
            !security.contains(
                QStringLiteral("ENTERPRISE"))) {
        return QStringLiteral("WPA");
    }

    if (security.contains(
            QStringLiteral("802.1X")) ||
            security.contains(
                QStringLiteral("ENTERPRISE"))) {
        return QStringLiteral("WPA2-ENTERPRISE");
    }

    if (security.contains(
            QStringLiteral("OWE"))) {
        return QStringLiteral("OWE");
    }

    if (security.contains(
            QStringLiteral("WEP"))) {
        return QStringLiteral("WEP");
    }

    if (security.contains(
            QStringLiteral("OPEN"))) {
        return QStringLiteral("OPEN");
    }

    return security;
}

bool securityRequiresPassword(
    const QString &security)
{
    const QString normalized =
        uppercaseSecurity(security);

    return normalized != QStringLiteral("OPEN") &&
           normalized != QStringLiteral("OWE");
}

bool securityUnsupported(
    const QString &security)
{
    const QString normalized =
        uppercaseSecurity(security);

    return normalized.contains(
               QStringLiteral("ENTERPRISE")) ||
           normalized.contains(
               QStringLiteral("802.1X"));
}

QString activeConnectionStateText(uint state)
{
    switch (state) {
    case 1:
        return QStringLiteral("CONNECTING");

    case 2:
        return QStringLiteral("CONNECTED");

    case 3:
        return QStringLiteral("DISCONNECTING");

    case 4:
        return QStringLiteral("DISCONNECTED");

    default:
        return QStringLiteral("UNKNOWN");
    }
}

QString deviceStateText(uint state,
                        bool wifiEnabled)
{
    if (!wifiEnabled)
        return QStringLiteral("WI-FI DISABLED");

    switch (state) {
    case 20:
        return QStringLiteral("UNAVAILABLE");

    case 30:
        return QStringLiteral("DISCONNECTED");

    case 40:
    case 50:
    case 60:
    case 70:
    case 80:
    case 90:
        return QStringLiteral("CONNECTING");

    case 100:
        return QStringLiteral("CONNECTED");

    case 110:
        return QStringLiteral("DISCONNECTING");

    case 120:
        return QStringLiteral("FAILED");

    default:
        return QStringLiteral("DISCONNECTED");
    }
}

QList<QVariantMap> variantMapArray(
    const QVariant &value)
{
    QList<QVariantMap> result;

    const QVariantList direct =
        value.toList();

    for (const QVariant &entry : direct) {
        const QVariantMap map =
            entry.toMap();

        if (!map.isEmpty())
            result.append(map);
    }

    if (!result.isEmpty())
        return result;

    if (value.userType() ==
            qMetaTypeId<QDBusArgument>()) {
        const QDBusArgument argument =
            qvariant_cast<QDBusArgument>(
                value
            );

        argument.beginArray();

        while (!argument.atEnd()) {
            QVariantMap map;
            argument >> map;

            if (!map.isEmpty())
                result.append(map);
        }

        argument.endArray();
    }

    return result;
}

QString stringFromVariant(
    const QVariant &value)
{
    if (!value.isValid() ||
            value.isNull()) {
        return QString();
    }

    if (value.canConvert<QString>()) {
        const QString text =
            value.toString().trimmed();

        if (!text.isEmpty())
            return text;
    }

    return QString();
}

QVariant nestedPayloadValue(
    const QVariantMap &payload,
    const QStringList &keys)
{
    for (const QString &key : keys) {
        if (payload.contains(key) &&
                payload.value(key).isValid()) {
            return payload.value(key);
        }
    }

    const QVariantMap network =
        payload.value(
            QStringLiteral("network")
        ).toMap();

    for (const QString &key : keys) {
        if (network.contains(key) &&
                network.value(key).isValid()) {
            return network.value(key);
        }
    }

    return QVariant();
}

bool mapListDifferent(const QVariantList &left,
                      const QVariantList &right)
{
    return left != right;
}

bool mapDifferent(const QVariantMap &left,
                  const QVariantMap &right)
{
    return left != right;
}
}

/*
    ========================================================================
                         CUSTOM D-BUS TYPE SUPPORT
    ========================================================================
*/

QDBusArgument &operator<<(
    QDBusArgument &argument,
    const NeutronNetworkSettings &settings)
{
    argument.beginMap(
        QMetaType::QString,
        QMetaType::QVariantMap
    );

    for (auto iterator =
             settings.constBegin();
         iterator != settings.constEnd();
         ++iterator) {
        argument.beginMapEntry();
        argument << iterator.key();
        argument << iterator.value();
        argument.endMapEntry();
    }

    argument.endMap();
    return argument;
}

const QDBusArgument &operator>>(
    const QDBusArgument &argument,
    NeutronNetworkSettings &settings)
{
    settings.clear();

    argument.beginMap();

    while (!argument.atEnd()) {
        QString key;
        QVariantMap value;

        argument.beginMapEntry();
        argument >> key;
        argument >> value;
        argument.endMapEntry();

        settings.insert(key, value);
    }

    argument.endMap();
    return argument;
}

/*
    ========================================================================
                              CONSTRUCTION
    ========================================================================
*/

NetworkManager::NetworkManager(
    QObject *parent)
    : QObject(parent)
{
    initializeDbusTypes();

    m_passiveRefreshTimer.setInterval(
        PassiveRefreshIntervalMs
    );

    m_passiveRefreshTimer.setSingleShot(
        false
    );

    m_refreshCoalesceTimer.setSingleShot(
        true
    );

    m_scanSettleTimer.setSingleShot(
        true
    );

    m_scanTimeoutTimer.setSingleShot(
        true
    );

    m_speedTestTimer.setInterval(
        AutoSpeedTestIntervalMs
    );

    m_speedTestTimer.setSingleShot(
        false
    );

    m_speedPhaseTimeoutTimer.setSingleShot(
        true
    );

    m_networkAccessManager =
        new QNetworkAccessManager(this);

    connect(
        &m_speedTestTimer,
        &QTimer::timeout,
        this,
        [this]() {
            runQuickSpeedProbe();
        }
    );

    connect(
        &m_speedPhaseTimeoutTimer,
        &QTimer::timeout,
        this,
        [this]() {
            abortSpeedReply();
            finishSpeedTest(
                false,
                QStringLiteral(
                    "Speed test timed out"
                )
            );
        }
    );

    connect(
        &m_passiveRefreshTimer,
        &QTimer::timeout,
        this,
        &NetworkManager::passiveStatusRefresh
    );

    connect(
        &m_refreshCoalesceTimer,
        &QTimer::timeout,
        this,
        &NetworkManager::coalescedRefresh
    );

    connect(
        &m_scanSettleTimer,
        &QTimer::timeout,
        this,
        &NetworkManager::finishScanRefresh
    );

    connect(
        &m_scanTimeoutTimer,
        &QTimer::timeout,
        this,
        &NetworkManager::handleScanTimeout
    );

    connect(&m_offlineNetworkWatcher, &QFutureWatcher<SecureIpcClient::Result>::finished,
            this, [this]() {
        const auto result = m_offlineNetworkWatcher.result();
        m_offlineNetworkBusy = false;
        emit offlineNetworkBusyChanged();
        bool success = result.transportOk && result.serviceOk;
        QString message;
        if (success) {
            const QJsonObject payload = result.response.value(QStringLiteral("result")).toObject();
            m_offlineNetworkState = payload.toVariantMap();
            m_offlineNetworkError = payload.value(QStringLiteral("error")).toString();
            success = payload.value(QStringLiteral("success")).toBool(true);
            message = payload.value(QStringLiteral("message")).toString(
                success ? QStringLiteral("Offline network updated") : m_offlineNetworkError);
        } else {
            m_offlineNetworkError = result.errorMessage.isEmpty()
                ? QStringLiteral("Offline Network service unavailable") : result.errorMessage;
            message = m_offlineNetworkError;
        }
        emit offlineNetworkStateChanged();
        emit offlineNetworkOperationFinished(success, message);
    });

    initializeServiceWatch();
    m_passiveRefreshTimer.start();
    m_speedTestTimer.start();

    QTimer::singleShot(
        InitialSpeedTestDelayMs,
        this,
        [this]() {
            runQuickSpeedProbe();
        }
    );
}

NetworkManager::~NetworkManager()
{
    if (m_offlineNetworkWatcher.isRunning())
        m_offlineNetworkWatcher.waitForFinished();
    abortSpeedReply();
    abortQuickSpeedProbe();

    if (m_diagnosticProcess)
        m_diagnosticProcess->kill();

    if (m_maintenanceProcess)
        m_maintenanceProcess->kill();

    disconnectDynamicSignals();

    QDBusConnection::systemBus()
        .disconnect(
            ServiceName,
            RootPath,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onRootPropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );
}

/*
    ========================================================================
                                  GETTERS
    ========================================================================
*/

QVariantList NetworkManager::availableNetworks() const
{
    return m_availableNetworks;
}

QVariantList NetworkManager::savedNetworks() const
{
    return m_savedNetworks;
}

QVariantMap NetworkManager::connectedNetwork() const
{
    return m_connectedNetwork;
}

QString NetworkManager::connectedSsid() const
{
    return m_connectedSsid;
}

QString NetworkManager::connectionState() const
{
    return m_connectionState;
}

QString NetworkManager::activeConnectionId() const
{
    return m_activeConnectionId;
}

QString NetworkManager::activeConnectionUuid() const
{
    return m_activeConnectionUuid;
}

bool NetworkManager::available() const
{
    return m_available;
}

bool NetworkManager::networkingEnabled() const
{
    return m_networkingEnabled;
}

bool NetworkManager::wifiEnabled() const
{
    return m_wifiEnabled;
}

bool NetworkManager::wirelessHardwareEnabled() const
{
    return m_wirelessHardwareEnabled;
}

bool NetworkManager::scanning() const
{
    return m_scanning;
}

bool NetworkManager::operationBusy() const
{
    return m_operationBusy;
}

QString NetworkManager::interfaceName() const
{
    return m_interfaceName;
}

QString NetworkManager::localIp() const
{
    return m_localIp;
}

QString NetworkManager::gateway() const
{
    return m_gateway;
}

QVariantList NetworkManager::dnsServers() const
{
    return m_dnsServers;
}

QString NetworkManager::tailscaleIp() const
{
    return m_tailscaleIp;
}

int NetworkManager::signalPercent() const
{
    return m_signalPercent;
}

QString NetworkManager::currentSecurity() const
{
    return m_currentSecurity;
}

QString NetworkManager::frequency() const
{
    return m_frequency;
}

bool NetworkManager::speedTestRunning() const
{
    return m_speedTestRunning;
}

double NetworkManager::downloadMbps() const
{
    return m_downloadMbps;
}

double NetworkManager::uploadMbps() const
{
    return m_uploadMbps;
}

int NetworkManager::latencyMs() const
{
    return m_latencyMs;
}

QString NetworkManager::speedTestStatus() const
{
    return m_speedTestStatus;
}

QString NetworkManager::speedTestLastRun() const
{
    if (!m_lastSpeedTest.isValid())
        return QStringLiteral("Never");

    return m_lastSpeedTest
        .toLocalTime()
        .toString(
            QStringLiteral("MMM d, h:mm AP")
        );
}

int NetworkManager::speedTestIntervalMinutes() const
{
    return 10;
}

bool NetworkManager::diagnosticsRunning() const
{
    return m_diagnosticsRunning;
}

QVariantList NetworkManager::diagnosticResults() const
{
    return m_diagnosticResults;
}

QString NetworkManager::diagnosticsSummary() const
{
    return m_diagnosticsSummary;
}

QString NetworkManager::lastError() const
{
    return m_lastError;
}

QString NetworkManager::lastOperation() const
{
    return m_lastOperation;
}

int NetworkManager::networkRevision() const
{
    return m_networkRevision;
}

/*
    ========================================================================
                            PUBLIC REFRESH API
    ========================================================================
*/

void NetworkManager::refresh()
{
    coalescedRefresh();
}

void NetworkManager::refreshStatus()
{
    coalescedRefresh();
}

void NetworkManager::refreshNetworks()
{
    coalescedRefresh();
}

void NetworkManager::refreshSavedNetworks()
{
    coalescedRefresh();
}

bool NetworkManager::scan()
{
    return requestScan();
}

/*
    ========================================================================
                              ACTION ROUTER
    ========================================================================
*/

bool NetworkManager::executeAction(
    const QString &action,
    const QVariantMap &payload)
{
    const QString normalized =
        normalizedActionName(action);

    if (normalized ==
            QStringLiteral("scan")) {
        return requestScan();
    }

    if (normalized ==
            QStringLiteral("connect")) {
        return connectToNetwork(payload);
    }

    if (normalized ==
            QStringLiteral("disconnect")) {
        return disconnectCurrent();
    }

    if (normalized ==
            QStringLiteral("forget")) {
        return forgetNetwork(payload);
    }

    if (normalized ==
            QStringLiteral("addhidden") ||
            normalized ==
            QStringLiteral("addnetwork")) {
        return addHiddenNetwork(payload);
    }

    if (normalized ==
            QStringLiteral("refresh") ||
            normalized ==
            QStringLiteral("refreshnetworks")) {
        if (m_operationBusy)
            return false;

        beginOperation(
            QStringLiteral("refresh"),
            payload
        );

        coalescedRefresh();

        finishOperation(
            QStringLiteral("refresh"),
            true,
            QStringLiteral(
                "Network information refreshed"
            ),
            payload
        );

        return true;
    }

    if (normalized ==
            QStringLiteral("enablewifi")) {
        return setWifiEnabled(true);
    }

    if (normalized ==
            QStringLiteral("disablewifi")) {
        return setWifiEnabled(false);
    }

    if (normalized ==
            QStringLiteral("setwifienabled")) {
        return setWifiEnabled(
            payload.value(
                QStringLiteral("enabled")
            ).toBool()
        );
    }

    if (normalized ==
            QStringLiteral("speedtest") ||
            normalized ==
            QStringLiteral("runspeedtest")) {
        return runSpeedTest();
    }

    if (normalized ==
            QStringLiteral("diagnostics") ||
            normalized ==
            QStringLiteral("rundiagnostics")) {
        return runDiagnostics();
    }

    if (normalized ==
            QStringLiteral("repair") ||
            normalized ==
            QStringLiteral("repairconnection")) {
        return repairConnection();
    }

    if (normalized ==
            QStringLiteral("restartwifimanager") ||
            normalized ==
            QStringLiteral("restartnetworkmanager")) {
        return restartWifiManager();
    }

    if (normalized ==
            QStringLiteral("cancel")) {
        cancelPendingOperation();
        return true;
    }

    setLastError(
        QStringLiteral(
            "Unsupported network action: %1"
        ).arg(action)
    );

    return false;
}

SecureIpcClient::Identity NetworkManager::offlineNetworkIdentity() const
{
    SecureIpcClient::Identity identity;
    identity.user = QProcessEnvironment::systemEnvironment().value(QStringLiteral("USER"), QStringLiteral("neutronos"));
    const QDir sessions(QStringLiteral("/run/systemd/sessions"));
    for (const QString &name : sessions.entryList(QDir::Files | QDir::NoDotAndDotDot)) {
        QFile file(sessions.filePath(name));
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QByteArray data = file.readAll();
        if (sessionFileValue(data, QByteArrayLiteral("USER")) == identity.user &&
            sessionFileValue(data, QByteArrayLiteral("ACTIVE")) == QStringLiteral("1")) {
            identity.sessionId = name;
            if (sessionFileValue(data, QByteArrayLiteral("REMOTE")) != QStringLiteral("1"))
                break;
        }
    }
    if (identity.sessionId.isEmpty())
        identity.sessionId = QProcessEnvironment::systemEnvironment().value(QStringLiteral("XDG_SESSION_ID"));
    identity.applicationId = QStringLiteral("network");
    identity.applicationInstance = QStringLiteral("neutronshell-network-manager");
    return identity;
}

bool NetworkManager::requestOfflineNetwork(const QString &operation, const QJsonObject &arguments)
{
    if (m_offlineNetworkBusy)
        return false;
    m_offlineNetworkBusy = true;
    m_offlineNetworkError.clear();
    emit offlineNetworkBusyChanged();
    const auto identity = offlineNetworkIdentity();
    m_offlineNetworkWatcher.setFuture(QtConcurrent::run([operation, arguments, identity]() {
        return SecureIpcClient::request(OfflineNetworkSocket, QStringLiteral("network"),
                                        operation, arguments, identity, 5000);
    }));
    return true;
}

bool NetworkManager::refreshOfflineNetwork()
{
    return requestOfflineNetwork(QStringLiteral("network.status"));
}

bool NetworkManager::setOfflineNetworkMode(const QString &mode)
{
    static const QSet<QString> modes{QStringLiteral("normal-wifi"), QStringLiteral("ethernet"),
        QStringLiteral("wifi-hotspot"), QStringLiteral("lan-hotspot"), QStringLiteral("offline-roku")};
    if (!modes.contains(mode))
        return false;
    return requestOfflineNetwork(QStringLiteral("network.set-mode"),
                                 QJsonObject{{QStringLiteral("mode"), mode}});
}

bool NetworkManager::setOfflineNetworkDns(const QString &target, bool enabled, bool wildcard)
{
    if (target != QStringLiteral("wifi") && target != QStringLiteral("lan"))
        return false;
    return requestOfflineNetwork(QStringLiteral("network.set-dns"), QJsonObject{
        {QStringLiteral("target"), target}, {QStringLiteral("enabled"), enabled},
        {QStringLiteral("wildcard"), wildcard}});
}

bool NetworkManager::setOfflineWifiPassword(const QString &password, const QString &confirmation)
{
    if (password.size() < 8 || password.size() > 63 || password != confirmation)
        return false;
    return requestOfflineNetwork(QStringLiteral("network.set-wifi-credential"), QJsonObject{
        {QStringLiteral("password"), password}, {QStringLiteral("confirmation"), confirmation}});
}

/*
    ========================================================================
                   PATCH 14 SPEED TEST / NETWORK TOOLS
    ========================================================================
*/

bool NetworkManager::runSpeedTest()
{
    if (m_speedTestRunning)
        return false;

    // Manual Speed Check is authoritative and takes priority over the tiny
    // dashboard estimate if one happens to be in flight.
    if (m_quickSpeedProbeRunning) {
        abortQuickSpeedProbe();
        m_quickSpeedProbeRunning = false;
    }

    if (!m_available ||
            !m_networkingEnabled ||
            m_localIp == QStringLiteral("--")) {
        const QString status =
            QStringLiteral(
                "Waiting for an active Internet connection"
            );

        if (m_speedTestStatus != status) {
            m_speedTestStatus = status;
            emit speedTestStatusChanged();
        }

        return false;
    }

    // A manual or delayed startup test becomes the new cadence anchor.
    // This prevents a second automatic test from firing moments later.
    m_speedTestTimer.start(AutoSpeedTestIntervalMs);

    m_speedTestRunning = true;
    m_speedPhase = SpeedPhase::Latency;
    m_downloadMbps = 0.0;
    m_uploadMbps = 0.0;
    m_latencyMs = -1;
    m_speedTestStatus =
        QStringLiteral(
            "Measuring latency"
        );

    emit speedTestRunningChanged();
    emit speedTestResultsChanged();
    emit speedTestStatusChanged();

    startLatencyProbe();
    return true;
}

bool NetworkManager::runQuickSpeedProbe()
{
    if (m_speedTestRunning || m_quickSpeedProbeRunning)
        return false;

    if (!m_available ||
            !m_networkingEnabled ||
            m_localIp == QStringLiteral("--")) {
        return false;
    }

    m_quickSpeedProbeRunning = true;
    startQuickDownloadProbe();
    return true;
}

void NetworkManager::startQuickDownloadProbe()
{
    abortQuickSpeedProbe();
    m_quickSpeedProbeRunning = true;

    QNetworkRequest request(QuickSpeedDownloadUrl);
    request.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy
    );
    request.setRawHeader(
        QByteArrayLiteral("Accept-Encoding"),
        QByteArrayLiteral("identity")
    );
    request.setHeader(
        QNetworkRequest::UserAgentHeader,
        QStringLiteral("NeutronOS-Gemini-QuickProbe/0.1")
    );

    m_quickSpeedElapsed.restart();
    QNetworkReply *reply = m_networkAccessManager->get(request);
    m_quickSpeedReply = reply;

    QTimer::singleShot(
        QuickSpeedTimeoutMs,
        this,
        [this, reply]() {
            if (m_quickSpeedReply != reply)
                return;
            abortQuickSpeedProbe();
            finishQuickSpeedProbe(false);
        }
    );

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {
            if (m_quickSpeedReply != reply)
                return;

            const auto error = reply->error();
            const QByteArray data = reply->readAll();
            const qint64 elapsed = qMax<qint64>(1, m_quickSpeedElapsed.elapsed());

            m_quickSpeedReply.clear();
            reply->deleteLater();

            if (error != QNetworkReply::NoError || data.isEmpty()) {
                finishQuickSpeedProbe(false);
                return;
            }

            const double seconds = static_cast<double>(elapsed) / 1000.0;
            const double measuredMbps =
                (static_cast<double>(data.size()) * 8.0) /
                1000000.0 /
                seconds;
            m_downloadMbps = m_downloadMbps > 0.0
                ? (m_downloadMbps * 0.55) + (measuredMbps * 0.45)
                : measuredMbps;
            emit speedTestResultsChanged();
            startQuickUploadProbe();
        }
    );
}

void NetworkManager::startQuickUploadProbe()
{
    abortQuickSpeedProbe();
    m_quickSpeedProbeRunning = true;

    if (m_quickUploadPayload.size() != QuickSpeedUploadBytes) {
        m_quickUploadPayload = QByteArray(
            QuickSpeedUploadBytes,
            'Q'
        );
    }

    QNetworkRequest request(QuickSpeedUploadUrl);
    request.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy
    );
    request.setRawHeader(
        QByteArrayLiteral("Content-Type"),
        QByteArrayLiteral("application/octet-stream")
    );
    request.setHeader(
        QNetworkRequest::UserAgentHeader,
        QStringLiteral("NeutronOS-Gemini-QuickProbe/0.1")
    );

    m_quickSpeedElapsed.restart();
    QNetworkReply *reply = m_networkAccessManager->post(
        request,
        m_quickUploadPayload
    );
    m_quickSpeedReply = reply;

    QTimer::singleShot(
        QuickSpeedTimeoutMs,
        this,
        [this, reply]() {
            if (m_quickSpeedReply != reply)
                return;
            abortQuickSpeedProbe();
            finishQuickSpeedProbe(false);
        }
    );

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {
            if (m_quickSpeedReply != reply)
                return;

            const auto error = reply->error();
            reply->readAll();
            const qint64 elapsed = qMax<qint64>(1, m_quickSpeedElapsed.elapsed());

            m_quickSpeedReply.clear();
            reply->deleteLater();

            if (error != QNetworkReply::NoError) {
                finishQuickSpeedProbe(false);
                return;
            }

            const double seconds = static_cast<double>(elapsed) / 1000.0;
            const double measuredMbps =
                (static_cast<double>(QuickSpeedUploadBytes) * 8.0) /
                1000000.0 /
                seconds;
            m_uploadMbps = m_uploadMbps > 0.0
                ? (m_uploadMbps * 0.55) + (measuredMbps * 0.45)
                : measuredMbps;
            emit speedTestResultsChanged();
            finishQuickSpeedProbe(true);
        }
    );
}

void NetworkManager::finishQuickSpeedProbe(bool success)
{
    abortQuickSpeedProbe();
    m_quickSpeedProbeRunning = false;

    if (!success)
        return;

    m_lastSpeedTest = QDateTime::currentDateTime();
    m_speedTestStatus = QStringLiteral("Background estimate updated");
    emit speedTestResultsChanged();
    emit speedTestStatusChanged();
}

void NetworkManager::abortQuickSpeedProbe()
{
    if (!m_quickSpeedReply)
        return;

    QNetworkReply *reply = m_quickSpeedReply.data();
    m_quickSpeedReply.clear();
    QObject::disconnect(reply, nullptr, this, nullptr);
    reply->abort();
    reply->deleteLater();
}

void NetworkManager::startLatencyProbe()
{
    abortSpeedReply();

    m_speedPhase = SpeedPhase::Latency;
    m_speedTestStatus =
        QStringLiteral(
            "Measuring latency"
        );

    emit speedTestStatusChanged();

    QNetworkRequest request(SpeedLatencyUrl);
    request.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy
    );
    request.setRawHeader(
        QByteArrayLiteral("Accept-Encoding"),
        QByteArrayLiteral("identity")
    );
    request.setHeader(
        QNetworkRequest::UserAgentHeader,
        QStringLiteral("NeutronOS-Gemini/0.1")
    );

    m_speedElapsed.restart();
    QNetworkReply *reply =
        m_networkAccessManager->get(request);
    m_speedReply = reply;
    m_speedPhaseTimeoutTimer.start(
        SpeedPhaseTimeoutMs
    );

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {
            if (m_speedReply != reply)
                return;

            m_speedPhaseTimeoutTimer.stop();
            const auto error = reply->error();
            const QString errorText =
                reply->errorString();
            reply->readAll();
            const qint64 elapsed =
                qMax<qint64>(1, m_speedElapsed.elapsed());

            m_speedReply.clear();
            reply->deleteLater();

            if (error != QNetworkReply::NoError) {
                finishSpeedTest(
                    false,
                    QStringLiteral(
                        "Latency test failed: %1"
                    ).arg(errorText)
                );
                return;
            }

            m_latencyMs =
                static_cast<int>(elapsed);
            emit speedTestResultsChanged();
            startDownloadProbe();
        }
    );
}

void NetworkManager::startDownloadProbe()
{
    abortSpeedReply();

    m_speedPhase = SpeedPhase::Download;
    m_speedTestStatus =
        QStringLiteral(
            "Measuring download speed"
        );

    emit speedTestStatusChanged();

    QNetworkRequest request(SpeedDownloadUrl);
    request.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy
    );
    request.setRawHeader(
        QByteArrayLiteral("Accept-Encoding"),
        QByteArrayLiteral("identity")
    );
    request.setHeader(
        QNetworkRequest::UserAgentHeader,
        QStringLiteral("NeutronOS-Gemini/0.1")
    );

    m_speedElapsed.restart();
    QNetworkReply *reply =
        m_networkAccessManager->get(request);
    m_speedReply = reply;
    m_speedPhaseTimeoutTimer.start(
        SpeedPhaseTimeoutMs
    );

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {
            if (m_speedReply != reply)
                return;

            m_speedPhaseTimeoutTimer.stop();
            const auto error = reply->error();
            const QString errorText =
                reply->errorString();
            const QByteArray data = reply->readAll();
            const qint64 elapsed =
                qMax<qint64>(1, m_speedElapsed.elapsed());

            m_speedReply.clear();
            reply->deleteLater();

            if (error != QNetworkReply::NoError ||
                    data.isEmpty()) {
                finishSpeedTest(
                    false,
                    QStringLiteral(
                        "Download test failed: %1"
                    ).arg(errorText)
                );
                return;
            }

            const double seconds =
                static_cast<double>(elapsed) /
                1000.0;

            m_downloadMbps =
                (static_cast<double>(data.size()) * 8.0) /
                1000000.0 /
                seconds;

            emit speedTestResultsChanged();
            startUploadProbe();
        }
    );
}

void NetworkManager::startUploadProbe()
{
    abortSpeedReply();

    m_speedPhase = SpeedPhase::Upload;
    m_speedTestStatus =
        QStringLiteral(
            "Measuring upload speed"
        );

    emit speedTestStatusChanged();

    if (m_uploadPayload.size() != SpeedUploadBytes) {
        m_uploadPayload = QByteArray(
            SpeedUploadBytes,
            'N'
        );
    }

    QNetworkRequest request(SpeedUploadUrl);
    request.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy
    );
    request.setRawHeader(
        QByteArrayLiteral("Content-Type"),
        QByteArrayLiteral("application/octet-stream")
    );
    request.setHeader(
        QNetworkRequest::UserAgentHeader,
        QStringLiteral("NeutronOS-Gemini/0.1")
    );

    m_speedElapsed.restart();
    QNetworkReply *reply =
        m_networkAccessManager->post(
            request,
            m_uploadPayload
        );
    m_speedReply = reply;
    m_speedPhaseTimeoutTimer.start(
        SpeedPhaseTimeoutMs
    );

    connect(
        reply,
        &QNetworkReply::finished,
        this,
        [this, reply]() {
            if (m_speedReply != reply)
                return;

            m_speedPhaseTimeoutTimer.stop();
            const auto error = reply->error();
            const QString errorText =
                reply->errorString();
            reply->readAll();
            const qint64 elapsed =
                qMax<qint64>(1, m_speedElapsed.elapsed());

            m_speedReply.clear();
            reply->deleteLater();

            if (error != QNetworkReply::NoError) {
                finishSpeedTest(
                    false,
                    QStringLiteral(
                        "Upload test failed: %1"
                    ).arg(errorText)
                );
                return;
            }

            const double seconds =
                static_cast<double>(elapsed) /
                1000.0;

            m_uploadMbps =
                (static_cast<double>(SpeedUploadBytes) * 8.0) /
                1000000.0 /
                seconds;

            emit speedTestResultsChanged();

            finishSpeedTest(
                true,
                QStringLiteral(
                    "Automatic test complete"
                )
            );
        }
    );
}

void NetworkManager::finishSpeedTest(
    bool success,
    const QString &message)
{
    abortSpeedReply();
    m_speedPhaseTimeoutTimer.stop();
    m_speedPhase = SpeedPhase::Idle;
    m_speedTestRunning = false;
    m_lastSpeedTest =
        QDateTime::currentDateTime();
    m_speedTestStatus = message;

    if (!success) {
        setLastError(message);
    }

    emit speedTestRunningChanged();
    emit speedTestResultsChanged();
    emit speedTestStatusChanged();
}

void NetworkManager::abortSpeedReply()
{
    if (!m_speedReply)
        return;

    QNetworkReply *reply =
        m_speedReply.data();
    m_speedReply.clear();

    QObject::disconnect(reply, nullptr, this, nullptr);
    reply->abort();
    reply->deleteLater();
}

bool NetworkManager::runDiagnostics()
{
    if (m_diagnosticsRunning ||
            m_operationBusy) {
        return false;
    }

    beginOperation(
        QStringLiteral("diagnostics"),
        QVariantMap()
    );

    m_diagnosticsRunning = true;
    m_diagnosticResults.clear();
    m_diagnosticsSummary =
        QStringLiteral(
            "Running network checks"
        );
    m_diagnosticIndex = 0;

    emit diagnosticsRunningChanged();
    emit diagnosticResultsChanged();
    emit diagnosticsSummaryChanged();

    buildDiagnosticQueue();
    startNextDiagnosticStep();
    return true;
}

void NetworkManager::buildDiagnosticQueue()
{
    m_diagnosticQueue.clear();

    const QString systemctl =
        findExecutable({
            QStringLiteral("systemctl")
        });

    const QString ip =
        findExecutable({
            QStringLiteral("ip")
        });

    const QString ping =
        findExecutable({
            QStringLiteral("ping")
        });

    const QString getent =
        findExecutable({
            QStringLiteral("getent")
        });

    m_diagnosticQueue.append({
        QStringLiteral("manager"),
        QStringLiteral("NetworkManager service"),
        systemctl,
        {
            QStringLiteral("is-active"),
            QStringLiteral("NetworkManager.service")
        }
    });

    m_diagnosticQueue.append({
        QStringLiteral("interface"),
        QStringLiteral("Wi-Fi interface"),
        ip,
        {
            QStringLiteral("-brief"),
            QStringLiteral("address"),
            QStringLiteral("show"),
            QStringLiteral("dev"),
            m_interfaceName
        }
    });

    m_diagnosticQueue.append({
        QStringLiteral("route"),
        QStringLiteral("Default route"),
        ip,
        {
            QStringLiteral("route"),
            QStringLiteral("show"),
            QStringLiteral("default")
        }
    });

    if (!m_gateway.trimmed().isEmpty() &&
            m_gateway != QStringLiteral("--")) {
        m_diagnosticQueue.append({
            QStringLiteral("gateway"),
            QStringLiteral("Gateway reachability"),
            ping,
            {
                QStringLiteral("-c"),
                QStringLiteral("1"),
                QStringLiteral("-W"),
                QStringLiteral("2"),
                m_gateway
            }
        });
    }

    m_diagnosticQueue.append({
        QStringLiteral("internet"),
        QStringLiteral("Internet reachability"),
        ping,
        {
            QStringLiteral("-c"),
            QStringLiteral("1"),
            QStringLiteral("-W"),
            QStringLiteral("2"),
            QStringLiteral("1.1.1.1")
        }
    });

    m_diagnosticQueue.append({
        QStringLiteral("dns"),
        QStringLiteral("DNS resolution"),
        getent,
        {
            QStringLiteral("ahostsv4"),
            QStringLiteral("cloudflare.com")
        }
    });
}

void NetworkManager::startNextDiagnosticStep()
{
    if (!m_diagnosticsRunning)
        return;

    if (m_diagnosticIndex >=
            m_diagnosticQueue.size()) {
        finishDiagnostics();
        return;
    }

    const DiagnosticStep step =
        m_diagnosticQueue.at(
            m_diagnosticIndex
        );

    if (step.program.trimmed().isEmpty()) {
        appendDiagnosticResult(
            step,
            false,
            QStringLiteral(
                "Required system command is unavailable"
            )
        );
        ++m_diagnosticIndex;
        QTimer::singleShot(
            0,
            this,
            [this]() {
                startNextDiagnosticStep();
            }
        );
        return;
    }

    if (step.id == QStringLiteral("interface") &&
            m_interfaceName.trimmed().isEmpty()) {
        appendDiagnosticResult(
            step,
            false,
            QStringLiteral(
                "No wireless interface detected"
            )
        );
        ++m_diagnosticIndex;
        QTimer::singleShot(
            0,
            this,
            [this]() {
                startNextDiagnosticStep();
            }
        );
        return;
    }

    QProcess *process =
        new QProcess(this);
    m_diagnosticProcess = process;

    connect(
        process,
        qOverload<int, QProcess::ExitStatus>(
            &QProcess::finished
        ),
        this,
        [this, process, step](
            int exitCode,
            QProcess::ExitStatus exitStatus) {
            if (m_diagnosticProcess != process)
                return;

            QByteArray output =
                process->readAllStandardOutput();
            output +=
                process->readAllStandardError();

            QString detail =
                QString::fromLocal8Bit(output)
                .simplified()
                .left(220);

            const bool success =
                exitStatus == QProcess::NormalExit &&
                exitCode == 0;

            if (detail.isEmpty()) {
                detail = success
                    ? QStringLiteral("Check passed")
                    : QStringLiteral("Check failed");
            }

            m_diagnosticProcess.clear();
            process->deleteLater();

            appendDiagnosticResult(
                step,
                success,
                detail
            );

            ++m_diagnosticIndex;
            startNextDiagnosticStep();
        }
    );

    connect(
        process,
        &QProcess::errorOccurred,
        this,
        [this, process, step](
            QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart ||
                    m_diagnosticProcess != process) {
                return;
            }

            m_diagnosticProcess.clear();
            process->deleteLater();

            appendDiagnosticResult(
                step,
                false,
                QStringLiteral(
                    "System command failed to start"
                )
            );

            ++m_diagnosticIndex;
            startNextDiagnosticStep();
        }
    );

    process->start(
        step.program,
        step.arguments
    );

    QTimer::singleShot(
        DiagnosticStepTimeoutMs,
        this,
        [this, process]() {
            if (m_diagnosticProcess == process &&
                    process->state() !=
                    QProcess::NotRunning) {
                process->kill();
            }
        }
    );
}

void NetworkManager::appendDiagnosticResult(
    const DiagnosticStep &step,
    bool success,
    const QString &detail)
{
    QVariantMap result;
    result.insert(
        QStringLiteral("id"),
        step.id
    );
    result.insert(
        QStringLiteral("label"),
        step.label
    );
    result.insert(
        QStringLiteral("success"),
        success
    );
    result.insert(
        QStringLiteral("status"),
        success
            ? QStringLiteral("PASS")
            : QStringLiteral("FAIL")
    );
    result.insert(
        QStringLiteral("detail"),
        detail
    );

    m_diagnosticResults.append(result);
    emit diagnosticResultsChanged();
}

void NetworkManager::finishDiagnostics()
{
    int passed = 0;

    for (const QVariant &entry :
            std::as_const(m_diagnosticResults)) {
        if (entry.toMap()
                .value(QStringLiteral("success"))
                .toBool()) {
            ++passed;
        }
    }

    const int total =
        m_diagnosticResults.size();

    m_diagnosticsRunning = false;
    m_diagnosticsSummary =
        QStringLiteral(
            "%1 of %2 checks passed"
        ).arg(passed)
         .arg(total);

    emit diagnosticsRunningChanged();
    emit diagnosticsSummaryChanged();

    finishOperation(
        QStringLiteral("diagnostics"),
        passed == total && total > 0,
        m_diagnosticsSummary,
        QVariantMap()
    );
}

bool NetworkManager::repairConnection()
{
    if (m_operationBusy ||
            m_maintenanceProcess) {
        return false;
    }

    if (m_interfaceName.trimmed().isEmpty()) {
        setLastError(
            QStringLiteral(
                "No Wi-Fi interface is available to repair"
            )
        );
        return false;
    }

    const QString nmcli =
        findExecutable({
            QStringLiteral("nmcli")
        });

    if (nmcli.isEmpty()) {
        setLastError(
            QStringLiteral(
                "nmcli is unavailable; connection repair cannot run"
            )
        );
        return false;
    }

    m_repairStage = 0;

    return startMaintenanceProcess(
        QStringLiteral("repairConnection"),
        nmcli,
        {
            QStringLiteral("device"),
            QStringLiteral("reapply"),
            m_interfaceName
        }
    );
}

bool NetworkManager::restartWifiManager()
{
    if (m_operationBusy ||
            m_maintenanceProcess) {
        return false;
    }

    const QString systemctl =
        findExecutable({
            QStringLiteral("systemctl")
        });

    if (systemctl.isEmpty()) {
        setLastError(
            QStringLiteral(
                "systemctl is unavailable; NetworkManager cannot restart"
            )
        );
        return false;
    }

    return startMaintenanceProcess(
        QStringLiteral("restartWifiManager"),
        systemctl,
        {
            QStringLiteral("restart"),
            QStringLiteral("NetworkManager.service")
        }
    );
}

QString NetworkManager::findExecutable(
    const QStringList &names) const
{
    for (const QString &name : names) {
        const QString path =
            QStandardPaths::findExecutable(name);

        if (!path.isEmpty())
            return path;
    }

    return QString();
}

bool NetworkManager::startMaintenanceProcess(
    const QString &action,
    const QString &program,
    const QStringList &arguments)
{
    if (m_maintenanceProcess ||
            program.trimmed().isEmpty()) {
        return false;
    }

    if (!m_operationBusy) {
        beginOperation(
            action,
            QVariantMap()
        );
    }

    m_maintenanceAction = action;

    QProcess *process =
        new QProcess(this);
    m_maintenanceProcess = process;

    connect(
        process,
        qOverload<int, QProcess::ExitStatus>(
            &QProcess::finished
        ),
        this,
        [this, process](
            int exitCode,
            QProcess::ExitStatus exitStatus) {
            if (m_maintenanceProcess != process)
                return;

            handleMaintenanceFinished(
                exitCode,
                static_cast<int>(exitStatus)
            );
        }
    );

    connect(
        process,
        &QProcess::errorOccurred,
        this,
        [this, process](
            QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart ||
                    m_maintenanceProcess != process) {
                return;
            }

            handleMaintenanceFinished(
                -1,
                static_cast<int>(
                    QProcess::CrashExit
                )
            );
        }
    );

    process->start(program, arguments);

    QTimer::singleShot(
        MaintenanceTimeoutMs,
        this,
        [this, process]() {
            if (m_maintenanceProcess == process &&
                    process->state() !=
                    QProcess::NotRunning) {
                process->kill();
            }
        }
    );

    return true;
}

void NetworkManager::handleMaintenanceFinished(
    int exitCode,
    int exitStatus)
{
    if (!m_maintenanceProcess)
        return;

    QProcess *process =
        m_maintenanceProcess.data();

    QByteArray output =
        process->readAllStandardOutput();
    output += process->readAllStandardError();

    const QString detail =
        QString::fromLocal8Bit(output)
        .simplified()
        .left(240);

    const bool success =
        exitStatus ==
            static_cast<int>(QProcess::NormalExit) &&
        exitCode == 0;

    const QString action =
        m_maintenanceAction;

    m_maintenanceProcess.clear();
    process->deleteLater();

    if (action ==
            QStringLiteral("repairConnection") &&
            !success &&
            m_repairStage == 0) {
        const QString nmcli =
            findExecutable({
                QStringLiteral("nmcli")
            });

        if (!nmcli.isEmpty()) {
            m_repairStage = 1;
            startMaintenanceProcess(
                action,
                nmcli,
                {
                    QStringLiteral("device"),
                    QStringLiteral("connect"),
                    m_interfaceName
                }
            );
            return;
        }
    }

    QString message;

    if (action ==
            QStringLiteral("restartWifiManager")) {
        message = success
            ? QStringLiteral(
                  "NetworkManager restarted successfully"
              )
            : QStringLiteral(
                  "NetworkManager restart failed%1"
              ).arg(
                  detail.isEmpty()
                      ? QString()
                      : QStringLiteral(": %1").arg(detail)
              );
    } else {
        message = success
            ? QStringLiteral(
                  "Wi-Fi connection repair completed"
              )
            : QStringLiteral(
                  "Wi-Fi connection repair failed%1"
              ).arg(
                  detail.isEmpty()
                      ? QString()
                      : QStringLiteral(": %1").arg(detail)
              );
    }

    finishOperation(
        action,
        success,
        message,
        QVariantMap()
    );

    scheduleRefresh(2200);

    if (success) {
        QTimer::singleShot(
            3600,
            this,
            [this]() {
                coalescedRefresh();

                if (m_wifiEnabled &&
                        !m_scanning &&
                        !m_operationBusy) {
                    requestScan();
                }
            }
        );
    }
}

/*
    ========================================================================
                              SERVICE SETUP
    ========================================================================
*/

void NetworkManager::initializeDbusTypes()
{
    qRegisterMetaType<
        NeutronNetworkSettings
    >(
        "NeutronNetworkSettings"
    );

    qDBusRegisterMetaType<
        NeutronNetworkSettings
    >();
}

void NetworkManager::initializeServiceWatch()
{
    QDBusServiceWatcher *watcher =
        new QDBusServiceWatcher(
            ServiceName,
            QDBusConnection::systemBus(),
            QDBusServiceWatcher::WatchForRegistration |
            QDBusServiceWatcher::WatchForUnregistration,
            this
        );

    connect(
        watcher,
        &QDBusServiceWatcher::serviceRegistered,
        this,
        &NetworkManager::onServiceRegistered
    );

    connect(
        watcher,
        &QDBusServiceWatcher::serviceUnregistered,
        this,
        &NetworkManager::onServiceUnregistered
    );

    QDBusConnectionInterface *interface =
        QDBusConnection::systemBus()
            .interface();

    if (!interface) {
        resetUnavailableState();
        return;
    }

    const QDBusReply<bool> registered =
        interface->isServiceRegistered(
            ServiceName
        );

    if (registered.isValid() &&
            registered.value()) {
        onServiceRegistered(ServiceName);
    } else {
        resetUnavailableState();
    }
}

void NetworkManager::connectRootSignals()
{
    QDBusConnection bus =
        QDBusConnection::systemBus();

    bus.disconnect(
        ServiceName,
        RootPath,
        PropertiesInterface,
        QStringLiteral(
            "PropertiesChanged"
        ),
        this,
        SLOT(
            onRootPropertiesChanged(
                QString,
                QVariantMap,
                QStringList
            )
        )
    );

    bus.connect(
        ServiceName,
        RootPath,
        PropertiesInterface,
        QStringLiteral(
            "PropertiesChanged"
        ),
        this,
        SLOT(
            onRootPropertiesChanged(
                QString,
                QVariantMap,
                QStringList
            )
        )
    );
}

void NetworkManager::disconnectDynamicSignals()
{
    QDBusConnection bus =
        QDBusConnection::systemBus();

    for (const QString &path :
            std::as_const(
                m_connectedSignalPaths
            )) {
        bus.disconnect(
            ServiceName,
            path,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onDevicePropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );

        bus.disconnect(
            ServiceName,
            path,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onAccessPointPropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );

        bus.disconnect(
            ServiceName,
            path,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onActiveConnectionPropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );

        bus.disconnect(
            ServiceName,
            path,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onIpConfigurationPropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );

        bus.disconnect(
            ServiceName,
            path,
            SettingsConnectionInterface,
            QStringLiteral("Updated"),
            this,
            SLOT(
                onSettingsConnectionUpdated()
            )
        );

        bus.disconnect(
            ServiceName,
            path,
            SettingsConnectionInterface,
            QStringLiteral("Removed"),
            this,
            SLOT(
                onSettingsConnectionRemoved()
            )
        );
    }

    m_connectedSignalPaths.clear();
}

void NetworkManager::resetUnavailableState()
{
    disconnectDynamicSignals();

    m_refreshCoalesceTimer.stop();
    m_scanSettleTimer.stop();
    m_scanTimeoutTimer.stop();

    const bool wasAvailable =
        m_available;

    const bool oldNetworking =
        m_networkingEnabled;

    const bool oldWifi =
        m_wifiEnabled;

    const bool oldHardware =
        m_wirelessHardwareEnabled;

    const bool oldScanning =
        m_scanning;

    const bool oldBusy =
        m_operationBusy;

    const bool hadAvailableNetworks =
        !m_availableNetworks.isEmpty();

    const bool hadSavedNetworks =
        !m_savedNetworks.isEmpty();

    const bool hadConnectedNetwork =
        !m_connectedNetwork.isEmpty();

    const QString oldSsid =
        m_connectedSsid;

    const QString oldState =
        m_connectionState;

    m_available = false;
    if(m_connectivity!=0){m_connectivity=0;emit connectivityChanged();}
    m_networkingEnabled = false;
    m_wifiEnabled = false;
    m_wirelessHardwareEnabled = false;
    m_scanning = false;
    m_operationBusy = false;

    m_availableNetworks.clear();
    m_savedNetworks.clear();
    m_connectedNetwork.clear();

    m_accessPoints.clear();
    m_savedConnections.clear();
    m_savedConnectionBySsid.clear();

    m_connectedSsid.clear();
    m_connectionState =
        QStringLiteral("UNAVAILABLE");

    m_activeConnectionId.clear();
    m_activeConnectionUuid.clear();

    m_interfaceName.clear();
    m_localIp =
        QStringLiteral("--");

    m_gateway =
        QStringLiteral("--");

    m_dnsServers.clear();

    m_tailscaleIp =
        detectTailscaleIp();

    m_signalPercent = 0;
    m_currentSecurity =
        QStringLiteral("--");

    m_frequency =
        QStringLiteral("--");

    m_wirelessDevicePath.clear();
    m_activeAccessPointPath.clear();
    m_activeConnectionPath.clear();
    m_activeIp4ConfigPath.clear();
    m_activeDhcp4ConfigPath.clear();

    clearPendingSensitiveData();
    m_pendingAction.clear();

    if (wasAvailable)
        emit availabilityChanged();

    if (oldNetworking)
        emit networkingEnabledChanged();

    if (oldWifi)
        emit wifiEnabledChanged();

    if (oldHardware)
        emit wirelessHardwareEnabledChanged();

    if (oldScanning)
        emit scanningChanged();

    if (oldBusy)
        emit operationBusyChanged();

    if (hadAvailableNetworks)
        emit availableNetworksChanged();

    if (hadSavedNetworks)
        emit savedNetworksChanged();

    if (hadConnectedNetwork)
        emit connectedNetworkChanged();

    if (!oldSsid.isEmpty())
        emit connectedSsidChanged();

    if (oldState != m_connectionState)
        emit connectionStateChanged();

    const bool detailsChanged =
        !m_interfaceName.isEmpty() ||
        m_localIp != QStringLiteral("--") ||
        m_gateway != QStringLiteral("--") ||
        !m_dnsServers.isEmpty() ||
        m_tailscaleIp != QStringLiteral("--") ||
        m_signalPercent != 0 ||
        m_currentSecurity != QStringLiteral("--") ||
        m_frequency != QStringLiteral("--");

    const bool stateChanged =
        wasAvailable ||
        oldNetworking ||
        oldWifi ||
        oldHardware ||
        oldScanning ||
        oldBusy ||
        hadAvailableNetworks ||
        hadSavedNetworks ||
        hadConnectedNetwork ||
        !oldSsid.isEmpty() ||
        oldState != m_connectionState ||
        detailsChanged;

    if (stateChanged) {
        emit networkDetailsChanged();
        incrementRevision();
    }
}

void NetworkManager::onServiceRegistered(
    const QString &serviceName)
{
    if (serviceName != ServiceName)
        return;

    if (!m_available) {
        m_available = true;
        emit availabilityChanged();
    }

    connectRootSignals();
    scheduleRefresh(0);
}

void NetworkManager::onServiceUnregistered(
    const QString &serviceName)
{
    if (serviceName != ServiceName)
        return;

    resetUnavailableState();
}

/*
    ========================================================================
                         REFRESH ORCHESTRATION
    ========================================================================
*/

void NetworkManager::scheduleRefresh(
    int delayMs)
{
    const int boundedDelay =
        qBound(
            0,
            delayMs,
            5000
        );

    if (m_refreshCoalesceTimer.isActive()) {
        if (boundedDelay >=
                m_refreshCoalesceTimer
                    .remainingTime()) {
            return;
        }
    }

    m_refreshCoalesceTimer.start(
        boundedDelay
    );
}

void NetworkManager::coalescedRefresh()
{
    QDBusConnectionInterface *interface =
        QDBusConnection::systemBus()
            .interface();

    if (!interface) {
        resetUnavailableState();
        return;
    }

    const QDBusReply<bool> registered =
        interface->isServiceRegistered(
            ServiceName
        );

    if (!registered.isValid() ||
            !registered.value()) {
        resetUnavailableState();
        return;
    }

    const QVariantList oldAvailableNetworks =
        m_availableNetworks;

    const QVariantList oldSavedNetworks =
        m_savedNetworks;

    const QVariantMap oldConnectedNetwork =
        m_connectedNetwork;

    const QString oldSsid =
        m_connectedSsid;

    const QString oldConnectionState =
        m_connectionState;

    const QString oldActiveId =
        m_activeConnectionId;

    const QString oldActiveUuid =
        m_activeConnectionUuid;

    const bool oldAvailable =
        m_available;

    const bool oldNetworking =
        m_networkingEnabled;

    const bool oldWifi =
        m_wifiEnabled;

    const bool oldHardware =
        m_wirelessHardwareEnabled;

    const QString oldInterface =
        m_interfaceName;

    const QString oldLocalIp =
        m_localIp;

    const QString oldGateway =
        m_gateway;

    const QVariantList oldDns =
        m_dnsServers;

    const QString oldTailscale =
        m_tailscaleIp;

    const int oldSignal =
        m_signalPercent;

    const QString oldSecurity =
        m_currentSecurity;

    const QString oldFrequency =
        m_frequency;

    disconnectDynamicSignals();

    m_available = true;

    refreshRootState();
    discoverWirelessDevice();
    refreshWirelessDevice();
    refreshActiveConnection();
    refreshSavedConnectionsInternal();
    refreshAccessPoints();
    refreshIpConfiguration();
    refreshTailscaleAddress();
    rebuildPublicModels();
    rebuildConnectedNetwork();

    bool changed = false;

    if (oldAvailable != m_available) {
        emit availabilityChanged();
        changed = true;
    }

    if (oldNetworking !=
            m_networkingEnabled) {
        emit networkingEnabledChanged();
        changed = true;
    }

    if (oldWifi != m_wifiEnabled) {
        emit wifiEnabledChanged();
        changed = true;
    }

    if (oldHardware !=
            m_wirelessHardwareEnabled) {
        emit wirelessHardwareEnabledChanged();
        changed = true;
    }

    if (mapListDifferent(
            oldAvailableNetworks,
            m_availableNetworks)) {
        emit availableNetworksChanged();
        changed = true;
    }

    if (mapListDifferent(
            oldSavedNetworks,
            m_savedNetworks)) {
        emit savedNetworksChanged();
        changed = true;
    }

    if (mapDifferent(
            oldConnectedNetwork,
            m_connectedNetwork) ||
            oldActiveId !=
            m_activeConnectionId ||
            oldActiveUuid !=
            m_activeConnectionUuid) {
        emit connectedNetworkChanged();
        changed = true;
    }

    if (oldSsid != m_connectedSsid) {
        emit connectedSsidChanged();
        changed = true;
    }

    if (oldConnectionState !=
            m_connectionState) {
        emit connectionStateChanged();
        changed = true;
    }

    const bool detailsChanged =
        oldInterface != m_interfaceName ||
        oldLocalIp != m_localIp ||
        oldGateway != m_gateway ||
        oldDns != m_dnsServers ||
        oldTailscale != m_tailscaleIp ||
        oldSignal != m_signalPercent ||
        oldSecurity != m_currentSecurity ||
        oldFrequency != m_frequency;

    if (detailsChanged) {
        emit networkDetailsChanged();
        changed = true;
    }

    if (changed)
        incrementRevision();
}

void NetworkManager::passiveStatusRefresh()
{
    scheduleRefresh(0);
}

void NetworkManager::refreshRootState()
{
    bool ok = false;

    const QVariantMap properties =
        readAllProperties(
            RootPath,
            RootInterface,
            &ok
        );

    if (!ok) {
        if(m_connectivity!=0){m_connectivity=0;emit connectivityChanged();}
        m_available = false;
        return;
    }

    const int connectivity=properties.value(QStringLiteral("Connectivity"),0).toInt();
    if(m_connectivity!=connectivity){m_connectivity=connectivity;emit connectivityChanged();}
    m_available = true;

    m_networkingEnabled =
        properties.value(
            QStringLiteral(
                "NetworkingEnabled"
            ),
            true
        ).toBool();

    m_wifiEnabled =
        properties.value(
            QStringLiteral(
                "WirelessEnabled"
            ),
            false
        ).toBool();

    m_wirelessHardwareEnabled =
        properties.value(
            QStringLiteral(
                "WirelessHardwareEnabled"
            ),
            false
        ).toBool();
}

void NetworkManager::discoverWirelessDevice()
{
    m_wirelessDevicePath.clear();

    QDBusInterface root(
        ServiceName,
        RootPath,
        RootInterface,
        QDBusConnection::systemBus()
    );

    if (!root.isValid())
        return;

    const QDBusMessage reply =
        root.call(
            QStringLiteral("GetDevices")
        );

    if (reply.type() ==
            QDBusMessage::ErrorMessage ||
            reply.arguments().isEmpty()) {
        return;
    }

    const QStringList paths =
        objectPathList(
            reply.arguments().first()
        );

    for (const QString &path : paths) {
        const uint deviceType =
            readProperty(
                path,
                DeviceInterface,
                QStringLiteral("DeviceType")
            ).toUInt();

        if (deviceType != DeviceTypeWifi)
            continue;

        m_wirelessDevicePath = path;
        break;
    }

    if (m_wirelessDevicePath.isEmpty())
        return;

    QDBusConnection::systemBus()
        .connect(
            ServiceName,
            m_wirelessDevicePath,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onDevicePropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );

    m_connectedSignalPaths.insert(
        m_wirelessDevicePath
    );
}

void NetworkManager::refreshWirelessDevice()
{
    m_interfaceName.clear();
    m_activeAccessPointPath.clear();

    if (m_wirelessDevicePath.isEmpty())
        return;

    bool deviceOk = false;

    const QVariantMap deviceProperties =
        readAllProperties(
            m_wirelessDevicePath,
            DeviceInterface,
            &deviceOk
        );

    if (deviceOk) {
        m_interfaceName =
            deviceProperties.value(
                QStringLiteral("Interface")
            ).toString();
    }

    bool wirelessOk = false;

    const QVariantMap wirelessProperties =
        readAllProperties(
            m_wirelessDevicePath,
            WirelessInterface,
            &wirelessOk
        );

    if (wirelessOk) {
        m_activeAccessPointPath =
            objectPathString(
                wirelessProperties.value(
                    QStringLiteral(
                        "ActiveAccessPoint"
                    )
                )
            );

        if (m_activeAccessPointPath ==
                QStringLiteral("/")) {
            m_activeAccessPointPath.clear();
        }
    }
}

void NetworkManager::refreshActiveConnection()
{
    m_activeConnectionPath.clear();
    m_activeConnectionId.clear();
    m_activeConnectionUuid.clear();
    m_activeIp4ConfigPath.clear();
    m_activeDhcp4ConfigPath.clear();

    m_connectedSsid.clear();
    m_signalPercent = 0;
    m_currentSecurity =
        QStringLiteral("--");

    m_frequency =
        QStringLiteral("--");

    const QStringList activePaths =
        objectPathList(
            readProperty(
                RootPath,
                RootInterface,
                QStringLiteral(
                    "ActiveConnections"
                )
            )
        );

    for (const QString &path :
            activePaths) {
        bool ok = false;

        const QVariantMap properties =
            readAllProperties(
                path,
                ActiveConnectionInterface,
                &ok
            );

        if (!ok)
            continue;

        const QString type =
            properties.value(
                QStringLiteral("Type")
            ).toString();

        if (type !=
                QStringLiteral(
                    "802-11-wireless"
                ) &&
                type !=
                QStringLiteral("wifi")) {
            continue;
        }

        const QStringList devices =
            objectPathList(
                properties.value(
                    QStringLiteral("Devices")
                )
            );

        if (!m_wirelessDevicePath.isEmpty() &&
                !devices.contains(
                    m_wirelessDevicePath
                )) {
            continue;
        }

        m_activeConnectionPath = path;

        m_activeConnectionId =
            properties.value(
                QStringLiteral("Id")
            ).toString();

        m_activeConnectionUuid =
            properties.value(
                QStringLiteral("Uuid")
            ).toString();

        const QString specificObject =
            objectPathString(
                properties.value(
                    QStringLiteral(
                        "SpecificObject"
                    )
                )
            );

        if (!specificObject.isEmpty() &&
                specificObject !=
                QStringLiteral("/")) {
            m_activeAccessPointPath =
                specificObject;
        }

        m_activeIp4ConfigPath =
            objectPathString(
                properties.value(
                    QStringLiteral("Ip4Config")
                )
            );

        if (m_activeIp4ConfigPath ==
                QStringLiteral("/")) {
            m_activeIp4ConfigPath.clear();
        }

        m_activeDhcp4ConfigPath =
            objectPathString(
                properties.value(
                    QStringLiteral(
                        "Dhcp4Config"
                    )
                )
            );

        if (m_activeDhcp4ConfigPath ==
                QStringLiteral("/")) {
            m_activeDhcp4ConfigPath.clear();
        }

        const uint state =
            properties.value(
                QStringLiteral("State")
            ).toUInt();

        m_connectionState =
            activeConnectionStateText(
                state
            );

        QDBusConnection::systemBus()
            .connect(
                ServiceName,
                path,
                PropertiesInterface,
                QStringLiteral(
                    "PropertiesChanged"
                ),
                this,
                SLOT(
                    onActiveConnectionPropertiesChanged(
                        QString,
                        QVariantMap,
                        QStringList
                    )
                )
            );

        m_connectedSignalPaths.insert(path);
        break;
    }

    if (m_activeConnectionPath.isEmpty()) {
        const uint deviceState =
            readProperty(
                m_wirelessDevicePath,
                DeviceInterface,
                QStringLiteral("State")
            ).toUInt();

        m_connectionState =
            m_available
            ? deviceStateText(
                  deviceState,
                  m_wifiEnabled
              )
            : QStringLiteral(
                  "UNAVAILABLE"
              );

        return;
    }

    if (!m_activeAccessPointPath.isEmpty()) {
        const AccessPointRecord accessPoint =
            readAccessPoint(
                m_activeAccessPointPath
            );

        m_connectedSsid =
            accessPoint.ssid;

        m_signalPercent =
            accessPoint.signalPercent;

        m_currentSecurity =
            accessPoint.security;

        m_frequency =
            accessPoint.frequencyText;
    }

    if (m_connectedSsid.isEmpty())
        m_connectedSsid =
            m_activeConnectionId;
}

void NetworkManager::refreshSavedConnectionsInternal()
{
    m_savedConnections.clear();
    m_savedConnectionBySsid.clear();

    QDBusInterface settings(
        ServiceName,
        SettingsPath,
        SettingsInterface,
        QDBusConnection::systemBus()
    );

    if (!settings.isValid())
        return;

    const QDBusMessage reply =
        settings.call(
            QStringLiteral(
                "ListConnections"
            )
        );

    if (reply.type() ==
            QDBusMessage::ErrorMessage ||
            reply.arguments().isEmpty()) {
        return;
    }

    const QStringList paths =
        objectPathList(
            reply.arguments().first()
        );

    for (const QString &path : paths) {
        const SavedConnectionRecord record =
            readSavedConnection(path);

        if (record.path.isEmpty() ||
                record.ssid.isEmpty()) {
            continue;
        }

        m_savedConnections.insert(
            path,
            record
        );

        if (!m_savedConnectionBySsid.contains(
                record.ssid)) {
            m_savedConnectionBySsid.insert(
                record.ssid,
                path
            );
        }

        QDBusConnection::systemBus()
            .connect(
                ServiceName,
                path,
                SettingsConnectionInterface,
                QStringLiteral("Updated"),
                this,
                SLOT(
                    onSettingsConnectionUpdated()
                )
            );

        QDBusConnection::systemBus()
            .connect(
                ServiceName,
                path,
                SettingsConnectionInterface,
                QStringLiteral("Removed"),
                this,
                SLOT(
                    onSettingsConnectionRemoved()
                )
            );

        m_connectedSignalPaths.insert(path);
    }
}

void NetworkManager::refreshAccessPoints()
{
    m_accessPoints.clear();

    if (m_wirelessDevicePath.isEmpty())
        return;

    QDBusInterface wireless(
        ServiceName,
        m_wirelessDevicePath,
        WirelessInterface,
        QDBusConnection::systemBus()
    );

    if (!wireless.isValid())
        return;

    QDBusMessage reply =
        wireless.call(
            QStringLiteral(
                "GetAllAccessPoints"
            )
        );

    if (reply.type() ==
            QDBusMessage::ErrorMessage) {
        reply =
            wireless.call(
                QStringLiteral(
                    "GetAccessPoints"
                )
            );
    }

    if (reply.type() ==
            QDBusMessage::ErrorMessage ||
            reply.arguments().isEmpty()) {
        return;
    }

    const QStringList paths =
        objectPathList(
            reply.arguments().first()
        );

    for (const QString &path : paths) {
        AccessPointRecord record =
            readAccessPoint(path);

        if (record.path.isEmpty())
            continue;

        record.saved =
            m_savedConnectionBySsid.contains(
                record.ssid
            );

        record.connected =
            path ==
            m_activeAccessPointPath;

        m_accessPoints.insert(
            path,
            record
        );

        QDBusConnection::systemBus()
            .connect(
                ServiceName,
                path,
                PropertiesInterface,
                QStringLiteral(
                    "PropertiesChanged"
                ),
                this,
                SLOT(
                    onAccessPointPropertiesChanged(
                        QString,
                        QVariantMap,
                        QStringList
                    )
                )
            );

        m_connectedSignalPaths.insert(path);
    }
}

void NetworkManager::refreshIpConfiguration()
{
    m_localIp =
        QStringLiteral("--");

    m_gateway =
        QStringLiteral("--");

    m_dnsServers.clear();

    if (m_activeIp4ConfigPath.isEmpty())
        return;

    bool ok = false;

    const QVariantMap properties =
        readAllProperties(
            m_activeIp4ConfigPath,
            Ip4ConfigInterface,
            &ok
        );

    if (!ok)
        return;

    const QList<QVariantMap> addressData =
        variantMapArray(
            properties.value(
                QStringLiteral(
                    "AddressData"
                )
            )
        );

    for (const QVariantMap &entry :
            addressData) {
        const QString address =
            entry.value(
                QStringLiteral("address")
            ).toString();

        if (!address.isEmpty()) {
            m_localIp = address;
            break;
        }
    }

    if (m_localIp ==
            QStringLiteral("--")) {
        const QVariant addresses =
            properties.value(
                QStringLiteral("Addresses")
            );

        if (addresses.userType() ==
                qMetaTypeId<QDBusArgument>()) {
            const QDBusArgument argument =
                qvariant_cast<QDBusArgument>(
                    addresses
                );

            argument.beginArray();

            if (!argument.atEnd()) {
                argument.beginArray();

                uint address = 0;
                uint prefix = 0;
                uint gatewayValue = 0;

                if (!argument.atEnd())
                    argument >> address;

                if (!argument.atEnd())
                    argument >> prefix;

                if (!argument.atEnd())
                    argument >> gatewayValue;

                Q_UNUSED(prefix)

                argument.endArray();

                m_localIp =
                    ipv4FromUInt(address);

                if (m_gateway ==
                        QStringLiteral("--") &&
                        gatewayValue != 0) {
                    m_gateway =
                        ipv4FromUInt(
                            gatewayValue
                        );
                }
            }

            argument.endArray();
        }
    }

    const QString gatewayValue =
        properties.value(
            QStringLiteral("Gateway")
        ).toString();

    if (!gatewayValue.isEmpty())
        m_gateway = gatewayValue;

    const QList<QVariantMap> nameserverData =
        variantMapArray(
            properties.value(
                QStringLiteral(
                    "NameserverData"
                )
            )
        );

    for (const QVariantMap &entry :
            nameserverData) {
        const QString address =
            entry.value(
                QStringLiteral("address")
            ).toString();

        if (!address.isEmpty() &&
                !m_dnsServers.contains(
                    address
                )) {
            m_dnsServers.append(address);
        }
    }

    if (m_dnsServers.isEmpty()) {
        m_dnsServers =
            dnsFromUIntList(
                properties.value(
                    QStringLiteral(
                        "Nameservers"
                    )
                )
            );
    }

    QDBusConnection::systemBus()
        .connect(
            ServiceName,
            m_activeIp4ConfigPath,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onIpConfigurationPropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );

    m_connectedSignalPaths.insert(
        m_activeIp4ConfigPath
    );

    if (!m_activeDhcp4ConfigPath.isEmpty()) {
        QDBusConnection::systemBus()
            .connect(
                ServiceName,
                m_activeDhcp4ConfigPath,
                PropertiesInterface,
                QStringLiteral(
                    "PropertiesChanged"
                ),
                this,
                SLOT(
                    onIpConfigurationPropertiesChanged(
                        QString,
                        QVariantMap,
                        QStringList
                    )
                )
            );

        m_connectedSignalPaths.insert(
            m_activeDhcp4ConfigPath
        );
    }
}

void NetworkManager::refreshTailscaleAddress()
{
    m_tailscaleIp =
        detectTailscaleIp();
}

void NetworkManager::rebuildPublicModels()
{
    QHash<QString, AccessPointRecord> strongest;

    for (auto iterator =
             m_accessPoints.constBegin();
         iterator !=
         m_accessPoints.constEnd();
         ++iterator) {
        AccessPointRecord record =
            iterator.value();

        record.saved =
            m_savedConnectionBySsid.contains(
                record.ssid
            );

        record.connected =
            record.path ==
            m_activeAccessPointPath;

        const QString key =
            record.hidden ||
            record.ssid.isEmpty()
            ? record.path
            : record.ssid;

        if (!strongest.contains(key) ||
                strongest.value(key)
                    .signalPercent <
                record.signalPercent ||
                record.connected) {
            strongest.insert(
                key,
                record
            );
        }
    }

    QList<AccessPointRecord> accessPointList =
        strongest.values();

    std::sort(
        accessPointList.begin(),
        accessPointList.end(),
        [](const AccessPointRecord &left,
           const AccessPointRecord &right) {
            if (left.connected !=
                    right.connected) {
                return left.connected;
            }

            if (left.saved != right.saved)
                return left.saved;

            if (left.signalPercent !=
                    right.signalPercent) {
                return left.signalPercent >
                       right.signalPercent;
            }

            return QString::localeAwareCompare(
                       left.ssid,
                       right.ssid
                   ) < 0;
        }
    );

    QVariantList available;

    for (const AccessPointRecord &record :
            accessPointList) {
        available.append(
            accessPointToMap(record)
        );
    }

    QList<SavedConnectionRecord> savedList =
        m_savedConnections.values();

    std::sort(
        savedList.begin(),
        savedList.end(),
        [](const SavedConnectionRecord &left,
           const SavedConnectionRecord &right) {
            if (left.connected !=
                    right.connected) {
                return left.connected;
            }

            if (left.timestamp !=
                    right.timestamp) {
                return left.timestamp >
                       right.timestamp;
            }

            return QString::localeAwareCompare(
                       left.ssid,
                       right.ssid
                   ) < 0;
        }
    );

    QVariantList saved;

    for (const SavedConnectionRecord &record :
            savedList) {
        saved.append(
            savedConnectionToMap(record)
        );
    }

    m_availableNetworks = available;
    m_savedNetworks = saved;
}

void NetworkManager::rebuildConnectedNetwork()
{
    if (m_activeConnectionPath.isEmpty()) {
        m_connectedNetwork.clear();
        return;
    }

    QVariantMap result;

    if (!m_activeAccessPointPath.isEmpty() &&
            m_accessPoints.contains(
                m_activeAccessPointPath)) {
        result =
            accessPointToMap(
                m_accessPoints.value(
                    m_activeAccessPointPath
                )
            );
    }

    if (result.isEmpty()) {
        result[
            QStringLiteral("id")
        ] = !m_activeConnectionUuid.isEmpty()
            ? m_activeConnectionUuid
            : m_activeConnectionPath;

        result[
            QStringLiteral("ssid")
        ] = m_connectedSsid;

        result[
            QStringLiteral("name")
        ] = m_connectedSsid;

        result[
            QStringLiteral("connected")
        ] = true;

        result[
            QStringLiteral("saved")
        ] = !m_activeConnectionUuid.isEmpty();

        result[
            QStringLiteral("signal")
        ] = m_signalPercent;

        result[
            QStringLiteral("security")
        ] = m_currentSecurity;

        result[
            QStringLiteral("frequency")
        ] = m_frequency;
    }

    result[
        QStringLiteral("activeConnectionPath")
    ] = m_activeConnectionPath;

    result[
        QStringLiteral("activeConnectionId")
    ] = m_activeConnectionId;

    result[
        QStringLiteral("activeConnectionUuid")
    ] = m_activeConnectionUuid;

    result[
        QStringLiteral("interface")
    ] = m_interfaceName;

    result[
        QStringLiteral("localIp")
    ] = m_localIp;

    result[
        QStringLiteral("gateway")
    ] = m_gateway;

    result[
        QStringLiteral("dnsServers")
    ] = m_dnsServers;

    result[
        QStringLiteral("tailscaleIp")
    ] = m_tailscaleIp;

    result[
        QStringLiteral("state")
    ] = m_connectionState;

    result[
        QStringLiteral("status")
    ] = m_connectionState;

    m_connectedNetwork = result;
}

void NetworkManager::incrementRevision()
{
    ++m_networkRevision;

    if (m_networkRevision >
            1000000000) {
        m_networkRevision = 1;
    }

    emit networkRevisionChanged();
    emit networkChanged();
}

/*
    ========================================================================
                         D-BUS PROPERTY HELPERS
    ========================================================================
*/

QVariant NetworkManager::readProperty(
    const QString &path,
    const QString &interfaceName,
    const QString &propertyName,
    bool *ok) const
{
    if (ok)
        *ok = false;

    if (path.isEmpty() ||
            path == QStringLiteral("/")) {
        return QVariant();
    }

    QDBusInterface properties(
        ServiceName,
        path,
        PropertiesInterface,
        QDBusConnection::systemBus()
    );

    if (!properties.isValid())
        return QVariant();

    const QDBusReply<QDBusVariant> reply =
        properties.call(
            QStringLiteral("Get"),
            interfaceName,
            propertyName
        );

    if (!reply.isValid())
        return QVariant();

    if (ok)
        *ok = true;

    return reply.value().variant();
}

QVariantMap NetworkManager::readAllProperties(
    const QString &path,
    const QString &interfaceName,
    bool *ok) const
{
    if (ok)
        *ok = false;

    if (path.isEmpty() ||
            path == QStringLiteral("/")) {
        return QVariantMap();
    }

    QDBusInterface properties(
        ServiceName,
        path,
        PropertiesInterface,
        QDBusConnection::systemBus()
    );

    if (!properties.isValid())
        return QVariantMap();

    const QDBusReply<QVariantMap> reply =
        properties.call(
            QStringLiteral("GetAll"),
            interfaceName
        );

    if (!reply.isValid())
        return QVariantMap();

    if (ok)
        *ok = true;

    return reply.value();
}

QStringList NetworkManager::objectPathList(
    const QVariant &value) const
{
    QStringList result;

    const QList<QDBusObjectPath> paths =
        qdbus_cast<
            QList<QDBusObjectPath>
        >(value);

    for (const QDBusObjectPath &path :
            paths) {
        if (!path.path().isEmpty() &&
                path.path() !=
                QStringLiteral("/")) {
            result.append(path.path());
        }
    }

    if (!result.isEmpty())
        return result;

    const QVariantList variants =
        value.toList();

    for (const QVariant &entry :
            variants) {
        const QString path =
            objectPathString(entry);

        if (!path.isEmpty() &&
                !result.contains(path)) {
            result.append(path);
        }
    }

    return result;
}

QString NetworkManager::objectPathString(
    const QVariant &value) const
{
    if (!value.isValid() ||
            value.isNull()) {
        return QString();
    }

    if (value.canConvert<QDBusObjectPath>()) {
        const QDBusObjectPath path =
            qvariant_cast<QDBusObjectPath>(
                value
            );

        if (path.path() !=
                QStringLiteral("/")) {
            return path.path();
        }

        return QString();
    }

    const QString text =
        value.toString().trimmed();

    if (text.startsWith(
            QStringLiteral("/")) &&
            text != QStringLiteral("/")) {
        return text;
    }

    return QString();
}

/*
    ========================================================================
                          MODEL CONVERSION
    ========================================================================
*/

NetworkManager::AccessPointRecord
NetworkManager::readAccessPoint(
    const QString &path) const
{
    AccessPointRecord record;

    bool ok = false;

    const QVariantMap properties =
        readAllProperties(
            path,
            AccessPointInterface,
            &ok
        );

    if (!ok)
        return record;

    record.path = path;
    record.ssid =
        decodeSsid(
            properties.value(
                QStringLiteral("Ssid")
            )
        );

    record.bssid =
        properties.value(
            QStringLiteral("HwAddress")
        ).toString();

    record.signalPercent =
        normalizedSignal(
            properties.value(
                QStringLiteral("Strength")
            )
        );

    record.frequencyMhz =
        properties.value(
            QStringLiteral("Frequency")
        ).toUInt();

    record.frequencyText =
        frequencyLabel(
            record.frequencyMhz
        );

    const uint flags =
        properties.value(
            QStringLiteral("Flags")
        ).toUInt();

    const uint wpaFlags =
        properties.value(
            QStringLiteral("WpaFlags")
        ).toUInt();

    const uint rsnFlags =
        properties.value(
            QStringLiteral("RsnFlags")
        ).toUInt();

    record.security =
        securityFromAccessPointFlags(
            flags,
            wpaFlags,
            rsnFlags
        );

    record.hidden =
        record.ssid.isEmpty();

    if (record.hidden)
        record.ssid =
            QStringLiteral("Hidden Network");

    record.id =
        !record.bssid.isEmpty()
        ? record.bssid
        : path;

    record.saved =
        m_savedConnectionBySsid.contains(
            record.ssid
        );

    record.connected =
        path ==
        m_activeAccessPointPath;

    record.lastSeen =
        QDateTime::currentDateTime();

    return record;
}

NetworkManager::SavedConnectionRecord
NetworkManager::readSavedConnection(
    const QString &path) const
{
    SavedConnectionRecord record;

    QDBusInterface connection(
        ServiceName,
        path,
        SettingsConnectionInterface,
        QDBusConnection::systemBus()
    );

    if (!connection.isValid())
        return record;

    const QDBusReply<
        NeutronNetworkSettings
    > reply =
        connection.call(
            QStringLiteral("GetSettings")
        );

    if (!reply.isValid())
        return record;

    const NeutronNetworkSettings settings =
        reply.value();

    const QVariantMap connectionSection =
        settings.value(
            QStringLiteral("connection")
        );

    const QString type =
        connectionSection.value(
            QStringLiteral("type")
        ).toString();

    if (type !=
            QStringLiteral(
                "802-11-wireless"
            ) &&
            type !=
            QStringLiteral("wifi")) {
        return record;
    }

    const QVariantMap wirelessSection =
        settings.value(
            QStringLiteral(
                "802-11-wireless"
            )
        );

    const QString mode = wirelessSection.value(QStringLiteral("mode"),
                                               QStringLiteral("infrastructure")).toString();
    if (!mode.isEmpty() && mode != QStringLiteral("infrastructure"))
        return record;

    record.path = path;

    record.id =
        connectionSection.value(
            QStringLiteral("id")
        ).toString();

    record.uuid =
        connectionSection.value(
            QStringLiteral("uuid")
        ).toString();

    record.ssid =
        decodeSsid(
            wirelessSection.value(
                QStringLiteral("ssid")
            )
        );

    if (record.ssid.isEmpty())
        record.ssid = record.id;

    record.security =
        securityFromSettings(
            settings
        );

    record.autoConnect =
        connectionSection.value(
            QStringLiteral(
                "autoconnect"
            ),
            true
        ).toBool();

    record.hidden =
        wirelessSection.value(
            QStringLiteral("hidden"),
            false
        ).toBool();

    record.timestamp =
        connectionSection.value(
            QStringLiteral("timestamp")
        ).toLongLong();

    record.connected =
        (
            !record.uuid.isEmpty() &&
            record.uuid ==
            m_activeConnectionUuid
        ) ||
        (
            !record.id.isEmpty() &&
            record.id ==
            m_activeConnectionId
        );

    return record;
}

QVariantMap NetworkManager::accessPointToMap(
    const AccessPointRecord &record) const
{
    QVariantMap result;

    result[
        QStringLiteral("id")
    ] = record.id;

    result[
        QStringLiteral("path")
    ] = record.path;

    result[
        QStringLiteral("accessPointPath")
    ] = record.path;

    result[
        QStringLiteral("ssid")
    ] = record.ssid;

    result[
        QStringLiteral("name")
    ] = record.ssid;

    result[
        QStringLiteral("displayName")
    ] = record.ssid;

    result[
        QStringLiteral("bssid")
    ] = record.bssid;

    result[
        QStringLiteral("signal")
    ] = record.signalPercent;

    result[
        QStringLiteral("signalPercent")
    ] = record.signalPercent;

    result[
        QStringLiteral("strength")
    ] = record.signalPercent;

    result[
        QStringLiteral("quality")
    ] = record.signalPercent;

    result[
        QStringLiteral("security")
    ] = record.security;

    result[
        QStringLiteral("securityType")
    ] = record.security;

    result[
        QStringLiteral("frequency")
    ] = record.frequencyText;

    result[
        QStringLiteral("frequencyText")
    ] = record.frequencyText;

    result[
        QStringLiteral("frequencyMhz")
    ] = record.frequencyMhz;

    result[
        QStringLiteral("band")
    ] = record.frequencyText;

    result[
        QStringLiteral("saved")
    ] = record.saved;

    result[
        QStringLiteral("known")
    ] = record.saved;

    result[
        QStringLiteral("hasProfile")
    ] = record.saved;

    result[
        QStringLiteral("connected")
    ] = record.connected;

    result[
        QStringLiteral("active")
    ] = record.connected;

    result[
        QStringLiteral("current")
    ] = record.connected;

    result[
        QStringLiteral("hidden")
    ] = record.hidden;

    result[
        QStringLiteral("lastSeen")
    ] = record.lastSeen;

    return result;
}

QVariantMap NetworkManager::savedConnectionToMap(
    const SavedConnectionRecord &record) const
{
    QVariantMap result;

    result[
        QStringLiteral("id")
    ] = !record.uuid.isEmpty()
        ? record.uuid
        : record.id;

    result[
        QStringLiteral("profileId")
    ] = record.uuid;

    result[
        QStringLiteral("uuid")
    ] = record.uuid;

    result[
        QStringLiteral("connectionId")
    ] = record.id;

    result[
        QStringLiteral("path")
    ] = record.path;

    result[
        QStringLiteral("connectionPath")
    ] = record.path;

    result[
        QStringLiteral("ssid")
    ] = record.ssid;

    result[
        QStringLiteral("name")
    ] = record.ssid;

    result[
        QStringLiteral("displayName")
    ] = record.ssid;

    result[
        QStringLiteral("security")
    ] = record.security;

    result[
        QStringLiteral("securityType")
    ] = record.security;

    result[
        QStringLiteral("saved")
    ] = true;

    result[
        QStringLiteral("known")
    ] = true;

    result[
        QStringLiteral("hasProfile")
    ] = true;

    result[
        QStringLiteral("connected")
    ] = record.connected;

    result[
        QStringLiteral("active")
    ] = record.connected;

    result[
        QStringLiteral("current")
    ] = record.connected;

    result[
        QStringLiteral("autoConnect")
    ] = record.autoConnect;

    result[
        QStringLiteral("hidden")
    ] = record.hidden;

    result[
        QStringLiteral("timestamp")
    ] = record.timestamp;

    int strongestSignal = 0;
    QString bssid;
    QString frequencyText =
        QStringLiteral("--");

    for (const AccessPointRecord &accessPoint :
            m_accessPoints) {
        if (accessPoint.ssid !=
                record.ssid) {
            continue;
        }

        if (accessPoint.signalPercent <
                strongestSignal &&
                !accessPoint.connected) {
            continue;
        }

        strongestSignal =
            accessPoint.signalPercent;

        bssid =
            accessPoint.bssid;

        frequencyText =
            accessPoint.frequencyText;
    }

    result[
        QStringLiteral("signal")
    ] = strongestSignal;

    result[
        QStringLiteral("signalPercent")
    ] = strongestSignal;

    result[
        QStringLiteral("bssid")
    ] = bssid;

    result[
        QStringLiteral("frequency")
    ] = frequencyText;

    result[
        QStringLiteral("frequencyText")
    ] = frequencyText;

    return result;
}

QString NetworkManager::decodeSsid(
    const QVariant &value) const
{
    QByteArray bytes;

    if (value.userType() ==
            QMetaType::QByteArray) {
        bytes = value.toByteArray();
    } else {
        bytes =
            qdbus_cast<QByteArray>(
                value
            );
    }

    if (!bytes.isEmpty()) {
        QString text =
            QString::fromUtf8(bytes)
                .trimmed();

        if (!text.isEmpty())
            return text;
    }

    return value.toString().trimmed();
}

QString NetworkManager::securityFromAccessPointFlags(
    uint flags,
    uint wpaFlags,
    uint rsnFlags) const
{
    const bool privacy =
        (flags &
         AccessPointPrivacyFlag) != 0;

    const bool hasPsk =
        (
            wpaFlags &
            SecurityKeyManagementPsk
        ) != 0 ||
        (
            rsnFlags &
            SecurityKeyManagementPsk
        ) != 0;

    const bool hasSae =
        (
            rsnFlags &
            SecurityKeyManagementSae
        ) != 0;

    const bool hasEnterprise =
        (
            wpaFlags &
            SecurityKeyManagement8021x
        ) != 0 ||
        (
            rsnFlags &
            SecurityKeyManagement8021x
        ) != 0;

    const bool hasOwe =
        (
            rsnFlags &
            SecurityKeyManagementOwe
        ) != 0 ||
        (
            rsnFlags &
            SecurityKeyManagementOweTransition
        ) != 0;

    if (hasEnterprise)
        return QStringLiteral(
            "WPA2-ENTERPRISE"
        );

    if (hasSae && hasPsk)
        return QStringLiteral(
            "WPA2/WPA3"
        );

    if (hasSae)
        return QStringLiteral("WPA3");

    if (hasOwe)
        return QStringLiteral("OWE");

    if ((rsnFlags != 0) && hasPsk)
        return QStringLiteral("WPA2");

    if ((wpaFlags != 0) && hasPsk)
        return QStringLiteral("WPA");

    if (privacy)
        return QStringLiteral("WEP");

    return QStringLiteral("OPEN");
}

QString NetworkManager::securityFromSettings(
    const NeutronNetworkSettings &settings) const
{
    const QVariantMap securitySection =
        settings.value(
            QStringLiteral(
                "802-11-wireless-security"
            )
        );

    const QString keyManagement =
        securitySection.value(
            QStringLiteral("key-mgmt")
        ).toString()
         .toLower();

    if (keyManagement ==
            QStringLiteral("sae")) {
        return QStringLiteral("WPA3");
    }

    if (keyManagement ==
            QStringLiteral("wpa-psk")) {
        return QStringLiteral("WPA2");
    }

    if (keyManagement ==
            QStringLiteral("wpa-eap") ||
            keyManagement ==
            QStringLiteral(
                "ieee8021x"
            )) {
        return QStringLiteral(
            "WPA2-ENTERPRISE"
        );
    }

    if (keyManagement ==
            QStringLiteral("owe")) {
        return QStringLiteral("OWE");
    }

    if (keyManagement ==
            QStringLiteral("none")) {
        if (securitySection.contains(
                QStringLiteral("wep-key0"))) {
            return QStringLiteral("WEP");
        }

        return QStringLiteral("OPEN");
    }

    const QVariantMap wirelessSection =
        settings.value(
            QStringLiteral(
                "802-11-wireless"
            )
        );

    if (wirelessSection.contains(
            QStringLiteral("security"))) {
        return QStringLiteral("WPA2");
    }

    return QStringLiteral("OPEN");
}

QString NetworkManager::frequencyLabel(
    uint frequencyMhz) const
{
    if (frequencyMhz == 0)
        return QStringLiteral("--");

    if (frequencyMhz < 3000)
        return QStringLiteral("2.4 GHz");

    if (frequencyMhz < 5925)
        return QStringLiteral("5 GHz");

    return QStringLiteral("6 GHz");
}

int NetworkManager::normalizedSignal(
    const QVariant &value) const
{
    return qBound(
        0,
        value.toInt(),
        100
    );
}

/*
    ========================================================================
                          CONNECTION LOOKUP
    ========================================================================
*/

QString NetworkManager::findSavedConnectionPath(
    const QVariantMap &payload) const
{
    const QString explicitPath =
        nestedPayloadValue(
            payload,
            QStringList()
                << QStringLiteral(
                    "connectionPath"
                )
                << QStringLiteral(
                    "profilePath"
                )
        ).toString()
         .trimmed();

    if (!explicitPath.isEmpty() &&
            m_savedConnections.contains(
                explicitPath)) {
        return explicitPath;
    }

    const QString profileId =
        nestedPayloadValue(
            payload,
            QStringList()
                << QStringLiteral(
                    "profileId"
                )
                << QStringLiteral("uuid")
                << QStringLiteral(
                    "connectionUuid"
                )
        ).toString()
         .trimmed();

    if (!profileId.isEmpty()) {
        for (auto iterator =
                 m_savedConnections.constBegin();
             iterator !=
             m_savedConnections.constEnd();
             ++iterator) {
            const SavedConnectionRecord &record =
                iterator.value();

            if (record.uuid == profileId ||
                    record.id == profileId) {
                return record.path;
            }
        }
    }

    const QString ssid =
        payloadSsid(payload);

    if (!ssid.isEmpty())
        return m_savedConnectionBySsid
            .value(ssid);

    return QString();
}

QString NetworkManager::findAccessPointPath(
    const QVariantMap &payload) const
{
    const QString explicitPath =
        nestedPayloadValue(
            payload,
            QStringList()
                << QStringLiteral(
                    "accessPointPath"
                )
                << QStringLiteral("apPath")
                << QStringLiteral("path")
        ).toString()
         .trimmed();

    if (!explicitPath.isEmpty() &&
            m_accessPoints.contains(
                explicitPath)) {
        return explicitPath;
    }

    const QString bssid =
        nestedPayloadValue(
            payload,
            QStringList()
                << QStringLiteral("bssid")
                << QStringLiteral(
                    "accessPoint"
                )
        ).toString()
         .trimmed();

    const QString id =
        nestedPayloadValue(
            payload,
            QStringList()
                << QStringLiteral("id")
        ).toString()
         .trimmed();

    const QString ssid =
        payloadSsid(payload);

    QString strongestPath;
    int strongestSignal = -1;

    for (auto iterator =
             m_accessPoints.constBegin();
         iterator !=
         m_accessPoints.constEnd();
         ++iterator) {
        const AccessPointRecord &record =
            iterator.value();

        if (!bssid.isEmpty() &&
                record.bssid.compare(
                    bssid,
                    Qt::CaseInsensitive
                ) == 0) {
            return record.path;
        }

        if (!id.isEmpty() &&
                (
                    record.id == id ||
                    record.path == id
                )) {
            return record.path;
        }

        if (!ssid.isEmpty() &&
                record.ssid == ssid &&
                record.signalPercent >
                strongestSignal) {
            strongestSignal =
                record.signalPercent;

            strongestPath =
                record.path;
        }
    }

    return strongestPath;
}

QString NetworkManager::payloadSsid(
    const QVariantMap &payload) const
{
    return nestedPayloadValue(
        payload,
        QStringList()
            << QStringLiteral("ssid")
            << QStringLiteral("name")
            << QStringLiteral(
                "displayName"
            )
    ).toString()
     .trimmed();
}

QString NetworkManager::payloadSecurity(
    const QVariantMap &payload) const
{
    return uppercaseSecurity(
        nestedPayloadValue(
            payload,
            QStringList()
                << QStringLiteral(
                    "security"
                )
                << QStringLiteral(
                    "securityType"
                )
                << QStringLiteral(
                    "authentication"
                )
        ).toString()
    );
}

bool NetworkManager::validateConnectPayload(
    const QVariantMap &payload,
    QString *errorMessage) const
{
    const QString ssid =
        payloadSsid(payload);

    if (ssid.isEmpty()) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Network name is required"
                );
        }

        return false;
    }

    if (ssid.toUtf8().size() > 32) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Network names cannot exceed 32 bytes"
                );
        }

        return false;
    }

    const QString security =
        payloadSecurity(payload);

    if (securityUnsupported(security)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Enterprise Wi-Fi requires an identity and certificate flow"
                );
        }

        return false;
    }

    if (!findSavedConnectionPath(
            payload
        ).isEmpty()) {
        return true;
    }

    if (!securityRequiresPassword(
            security)) {
        return true;
    }

    const QString password =
        nestedPayloadValue(
            payload,
            QStringList()
                << QStringLiteral(
                    "password"
                )
                << QStringLiteral("psk")
                << QStringLiteral(
                    "passphrase"
                )
        ).toString();

    if (password.isEmpty()) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "A password is required for this network"
                );
        }

        return false;
    }

    if (security != QStringLiteral("WEP")) {
        const bool isRawHex =
            password.size() == 64 &&
            QRegularExpression(
                QStringLiteral(
                    "^[0-9a-fA-F]{64}$"
                )
            ).match(password)
             .hasMatch();

        if (!isRawHex &&
                (
                    password.size() < 8 ||
                    password.size() > 63
                )) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "WPA passwords must contain 8 to 63 characters"
                    );
            }

            return false;
        }
    }

    return true;
}

bool NetworkManager::validateHiddenPayload(
    const QVariantMap &payload,
    QString *errorMessage) const
{
    if (!validateConnectPayload(
            payload,
            errorMessage)) {
        return false;
    }

    const QString security =
        payloadSecurity(payload);

    if (security ==
            QStringLiteral("OWE")) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Hidden OWE networks are not supported by this setup flow"
                );
        }

        return false;
    }

    return true;
}

/*
    ========================================================================
                       CONNECTION SETTINGS GENERATION
    ========================================================================
*/

NeutronNetworkSettings
NetworkManager::buildConnectionSettings(
    const QVariantMap &payload,
    bool hidden) const
{
    NeutronNetworkSettings settings;

    const QString ssid =
        payloadSsid(payload);

    QString security =
        payloadSecurity(payload);

    const QString password =
        nestedPayloadValue(
            payload,
            QStringList()
                << QStringLiteral(
                    "password"
                )
                << QStringLiteral("psk")
                << QStringLiteral(
                    "passphrase"
                )
        ).toString();

    // Some access-point payloads omit a normalized security label even
    // though the password field is present. Treat that as WPA-PSK instead
    // of creating an incomplete profile with no key-mgmt property.
    if (!password.isEmpty() &&
            (security.isEmpty() ||
             security == QStringLiteral("OPEN") ||
             security == QStringLiteral("NONE") ||
             security == QStringLiteral("UNKNOWN"))) {
        security = QStringLiteral("WPA2");
    }

    const bool remember =
        payload.value(
            QStringLiteral("remember"),
            true
        ).toBool();

    QVariantMap connection;

    connection[
        QStringLiteral("id")
    ] = ssid;

    connection[
        QStringLiteral("uuid")
    ] = QUuid::createUuid()
            .toString(
                QUuid::WithoutBraces
            );

    connection[
        QStringLiteral("type")
    ] = QStringLiteral(
        "802-11-wireless"
    );

    connection[
        QStringLiteral("autoconnect")
    ] = remember;

    settings.insert(
        QStringLiteral("connection"),
        connection
    );

    QVariantMap wireless;

    wireless[
        QStringLiteral("ssid")
    ] = ssid.toUtf8();

    wireless[
        QStringLiteral("mode")
    ] = QStringLiteral(
        "infrastructure"
    );

    wireless[
        QStringLiteral("hidden")
    ] = hidden;

    if (!password.isEmpty() ||
            securityRequiresPassword(security) ||
            security == QStringLiteral("OWE")) {
        wireless[
            QStringLiteral("security")
        ] = QStringLiteral(
            "802-11-wireless-security"
        );
    }

    settings.insert(
        QStringLiteral(
            "802-11-wireless"
        ),
        wireless
    );

    const QVariantMap securitySection =
        buildWirelessSecuritySection(
            security,
            password
        );

    if (!securitySection.isEmpty()) {
        settings.insert(
            QStringLiteral(
                "802-11-wireless-security"
            ),
            securitySection
        );
    }

    QVariantMap ipv4;

    ipv4[
        QStringLiteral("method")
    ] = QStringLiteral("auto");

    settings.insert(
        QStringLiteral("ipv4"),
        ipv4
    );

    QVariantMap ipv6;

    ipv6[
        QStringLiteral("method")
    ] = QStringLiteral("auto");

    settings.insert(
        QStringLiteral("ipv6"),
        ipv6
    );

    return settings;
}

QVariantMap
NetworkManager::buildWirelessSecuritySection(
    const QString &security,
    const QString &password) const
{
    const QString normalized =
        uppercaseSecurity(security);

    QVariantMap section;

    if (normalized ==
            QStringLiteral("OPEN")) {
        return section;
    }

    if (normalized ==
            QStringLiteral("OWE")) {
        section[
            QStringLiteral("key-mgmt")
        ] = QStringLiteral("owe");

        return section;
    }

    if (normalized ==
            QStringLiteral("WPA3")) {
        section[
            QStringLiteral("key-mgmt")
        ] = QStringLiteral("sae");

        section[
            QStringLiteral("psk")
        ] = password;

        return section;
    }

    if (normalized ==
            QStringLiteral("WEP")) {
        section[
            QStringLiteral("key-mgmt")
        ] = QStringLiteral("none");

        section[
            QStringLiteral("wep-key0")
        ] = password;

        section[
            QStringLiteral(
                "wep-key-type"
            )
        ] = 1;

        return section;
    }

    section[
        QStringLiteral("key-mgmt")
    ] = QStringLiteral("wpa-psk");

    section[
        QStringLiteral("psk")
    ] = password;

    return section;
}

/*
    ========================================================================
                             NETWORK OPERATIONS
    ========================================================================
*/

bool NetworkManager::requestScan()
{
    if (!m_available) {
        setLastError(
            QStringLiteral(
                "NetworkManager is unavailable"
            )
        );

        return false;
    }

    if (!m_wifiEnabled ||
            !m_wirelessHardwareEnabled) {
        setLastError(
            QStringLiteral(
                "Wi-Fi is disabled"
            )
        );

        return false;
    }

    if (m_wirelessDevicePath.isEmpty()) {
        setLastError(
            QStringLiteral(
                "No wireless device is available"
            )
        );

        return false;
    }

    if (m_scanning)
        return true;

    if (m_operationBusy)
        return false;

    if (m_lastScanRequest.isValid() &&
            m_lastScanRequest.msecsTo(
                QDateTime::currentDateTime()
            ) <
            ScanMinimumIntervalMs) {
        const int remaining =
            ScanMinimumIntervalMs -
            static_cast<int>(
                m_lastScanRequest.msecsTo(
                    QDateTime::currentDateTime()
                )
            );

        setLastError(
            QStringLiteral(
                "Please wait %1 second%2 before scanning again"
            )
                .arg(
                    qMax(
                        1,
                        qCeil(
                            remaining /
                            1000.0
                        )
                    )
                )
                .arg(
                    remaining > 1000
                    ? QStringLiteral("s")
                    : QString()
                )
        );

        return false;
    }

    const QVariantMap payload = {
        {
            QStringLiteral("source"),
            QStringLiteral("networkModal")
        }
    };

    beginOperation(
        QStringLiteral("scan"),
        payload
    );

    // LastScan is NetworkManager's completed-scan timestamp. A method reply
    // only acknowledges the request; it does not mean results are ready.
    m_scanStartTimestamp = readProperty(m_wirelessDevicePath, WirelessInterface,
                                       QStringLiteral("LastScan")).toLongLong();
    setScanning(true);

    m_lastScanRequest =
        QDateTime::currentDateTime();

    QDBusMessage message =
        QDBusMessage::createMethodCall(
            ServiceName,
            m_wirelessDevicePath,
            WirelessInterface,
            QStringLiteral("RequestScan")
        );

    message << QVariantMap();

    QDBusPendingCallWatcher *watcher =
        new QDBusPendingCallWatcher(
            QDBusConnection::systemBus()
                .asyncCall(
                    message,
                    DbusOperationTimeoutMs
                ),
            this
        );

    watcher->setProperty(
        "action",
        QStringLiteral("scan")
    );

    watcher->setProperty(
        "payload",
        sanitizedPayload(payload)
    );

    watcher->setProperty(
        "serial",
        QVariant::fromValue<
            qulonglong
        >(m_operationSerial)
    );

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        &NetworkManager::onScanRequestFinished
    );

    m_scanTimeoutTimer.start(
        ScanTimeoutMs
    );

    return true;
}

bool NetworkManager::connectToNetwork(
    const QVariantMap &payload)
{
    if (m_operationBusy)
        return false;

    if (!m_available ||
            !m_wifiEnabled ||
            m_wirelessDevicePath.isEmpty()) {
        setLastError(
            QStringLiteral(
                "Wi-Fi is not available"
            )
        );

        return false;
    }

    QString error;

    if (!validateConnectPayload(
            payload,
            &error)) {
        setLastError(error);
        return false;
    }

    const QString connectionPath =
        findSavedConnectionPath(payload);

    const QString accessPointPath =
        findAccessPointPath(payload);

    if (!connectionPath.isEmpty()) {
        return activateSavedConnection(
            connectionPath,
            accessPointPath,
            payload
        );
    }

    const bool hidden =
        payload.value(
            QStringLiteral("hidden"),
            false
        ).toBool();

    if (!hidden &&
            accessPointPath.isEmpty()) {
        setLastError(
            QStringLiteral(
                "The selected network is no longer available"
            )
        );

        return false;
    }

    return addAndActivateConnection(
        payload,
        hidden
    );
}

bool NetworkManager::disconnectCurrent()
{
    if (m_operationBusy)
        return false;

    if (m_activeConnectionPath.isEmpty()) {
        setLastError(
            QStringLiteral(
                "No active Wi-Fi connection exists"
            )
        );

        return false;
    }

    QVariantMap payload;

    payload[
        QStringLiteral("ssid")
    ] = m_connectedSsid;

    payload[
        QStringLiteral(
            "activeConnectionPath"
        )
    ] = m_activeConnectionPath;

    return deactivateConnection(
        m_activeConnectionPath,
        payload
    );
}

bool NetworkManager::forgetNetwork(
    const QVariantMap &payload)
{
    if (m_operationBusy)
        return false;

    const QString connectionPath =
        findSavedConnectionPath(payload);

    if (connectionPath.isEmpty()) {
        setLastError(
            QStringLiteral(
                "No saved profile was found for this network"
            )
        );

        return false;
    }

    return deleteSavedConnection(
        connectionPath,
        payload
    );
}

bool NetworkManager::addHiddenNetwork(
    const QVariantMap &payload)
{
    if (m_operationBusy)
        return false;

    if (!m_available ||
            !m_wifiEnabled ||
            m_wirelessDevicePath.isEmpty()) {
        setLastError(
            QStringLiteral(
                "Wi-Fi is not available"
            )
        );

        return false;
    }

    QString error;

    if (!validateHiddenPayload(
            payload,
            &error)) {
        setLastError(error);
        return false;
    }

    QVariantMap hiddenPayload =
        payload;

    hiddenPayload[
        QStringLiteral("hidden")
    ] = true;

    return addAndActivateConnection(
        hiddenPayload,
        true
    );
}

bool NetworkManager::setWifiEnabled(
    bool enabled)
{
    if (m_operationBusy)
        return false;

    if (!m_available) {
        setLastError(
            QStringLiteral(
                "NetworkManager is unavailable"
            )
        );

        return false;
    }

    if (m_wifiEnabled == enabled) {
        setLastOperation(
            enabled
            ? QStringLiteral(
                  "Wi-Fi is already enabled"
              )
            : QStringLiteral(
                  "Wi-Fi is already disabled"
              )
        );

        return true;
    }

    QVariantMap payload;

    payload[
        QStringLiteral("enabled")
    ] = enabled;

    beginOperation(
        QStringLiteral(
            "setWifiEnabled"
        ),
        payload
    );

    QDBusMessage message =
        QDBusMessage::createMethodCall(
            ServiceName,
            RootPath,
            PropertiesInterface,
            QStringLiteral("Set")
        );

    message
        << RootInterface
        << QStringLiteral(
               "WirelessEnabled"
           )
        << QVariant::fromValue(
               QDBusVariant(enabled)
           );

    QDBusPendingCallWatcher *watcher =
        new QDBusPendingCallWatcher(
            QDBusConnection::systemBus()
                .asyncCall(
                    message,
                    DbusOperationTimeoutMs
                ),
            this
        );

    watcher->setProperty(
        "action",
        QStringLiteral(
            "setWifiEnabled"
        )
    );

    watcher->setProperty(
        "payload",
        sanitizedPayload(payload)
    );

    watcher->setProperty(
        "serial",
        QVariant::fromValue<
            qulonglong
        >(m_operationSerial)
    );

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        &NetworkManager::onWifiToggleFinished
    );

    return true;
}

void NetworkManager::cancelPendingOperation()
{
    ++m_operationSerial;

    m_scanSettleTimer.stop();
    m_scanTimeoutTimer.stop();

    if (m_diagnosticProcess) {
        QProcess *process =
            m_diagnosticProcess.data();
        m_diagnosticProcess.clear();
        process->kill();
        process->deleteLater();
    }

    if (m_maintenanceProcess) {
        QProcess *process =
            m_maintenanceProcess.data();
        m_maintenanceProcess.clear();
        process->kill();
        process->deleteLater();
    }

    if (m_diagnosticsRunning) {
        m_diagnosticsRunning = false;
        m_diagnosticsSummary =
            QStringLiteral(
                "Diagnostics cancelled"
            );
        emit diagnosticsRunningChanged();
        emit diagnosticsSummaryChanged();
    }

    const QString cancelledAction =
        m_pendingAction;

    const QVariantMap cancelledPayload =
        m_pendingPayload;

    clearPendingSensitiveData();
    m_pendingAction.clear();

    setScanning(false);
    setOperationBusy(false);

    setLastOperation(
        QStringLiteral(
            "Network operation cancelled locally"
        )
    );

    if (!cancelledAction.isEmpty()) {
        emit operationFinished(
            cancelledAction,
            false,
            QStringLiteral(
                "Operation cancelled locally"
            ),
            cancelledPayload
        );
    }
}

bool NetworkManager::activateSavedConnection(
    const QString &connectionPath,
    const QString &accessPointPath,
    const QVariantMap &payload)
{
    if (connectionPath.isEmpty() ||
            m_wirelessDevicePath.isEmpty()) {
        return false;
    }

    beginOperation(
        QStringLiteral("connect"),
        payload
    );

    QDBusMessage message =
        QDBusMessage::createMethodCall(
            ServiceName,
            RootPath,
            RootInterface,
            QStringLiteral(
                "ActivateConnection"
            )
        );

    message
        << QVariant::fromValue(
               QDBusObjectPath(
                   connectionPath
               )
           )
        << QVariant::fromValue(
               QDBusObjectPath(
                   m_wirelessDevicePath
               )
           )
        << QVariant::fromValue(
               QDBusObjectPath(
                   accessPointPath.isEmpty()
                   ? QStringLiteral("/")
                   : accessPointPath
               )
           );

    QDBusPendingCallWatcher *watcher =
        new QDBusPendingCallWatcher(
            QDBusConnection::systemBus()
                .asyncCall(
                    message,
                    DbusOperationTimeoutMs
                ),
            this
        );

    watcher->setProperty(
        "action",
        QStringLiteral("connect")
    );

    watcher->setProperty(
        "payload",
        sanitizedPayload(payload)
    );

    watcher->setProperty(
        "serial",
        QVariant::fromValue<
            qulonglong
        >(m_operationSerial)
    );

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        &NetworkManager::onActivateConnectionFinished
    );

    return true;
}

bool NetworkManager::addAndActivateConnection(
    const QVariantMap &payload,
    bool hidden)
{
    if (m_wirelessDevicePath.isEmpty())
        return false;

    const QString accessPointPath =
        hidden
        ? QStringLiteral("/")
        : findAccessPointPath(payload);

    const NeutronNetworkSettings settings =
        buildConnectionSettings(
            payload,
            hidden
        );

    const bool remember =
        payload.value(
            QStringLiteral("remember"),
            true
        ).toBool();

    beginOperation(
        hidden
        ? QStringLiteral("addHidden")
        : QStringLiteral("connect"),
        payload
    );

    QDBusMessage message;

    if (remember) {
        message =
            QDBusMessage::createMethodCall(
                ServiceName,
                RootPath,
                RootInterface,
                QStringLiteral(
                    "AddAndActivateConnection"
                )
            );

        message
            << QVariant::fromValue(
                   settings
               )
            << QVariant::fromValue(
                   QDBusObjectPath(
                       m_wirelessDevicePath
                   )
               )
            << QVariant::fromValue(
                   QDBusObjectPath(
                       accessPointPath.isEmpty()
                       ? QStringLiteral("/")
                       : accessPointPath
                   )
               );
    } else {
        message =
            QDBusMessage::createMethodCall(
                ServiceName,
                RootPath,
                RootInterface,
                QStringLiteral(
                    "AddAndActivateConnection2"
                )
            );

        QVariantMap options;

        options[
            QStringLiteral("persist")
        ] = QStringLiteral("memory");

        message
            << QVariant::fromValue(
                   settings
               )
            << QVariant::fromValue(
                   QDBusObjectPath(
                       m_wirelessDevicePath
                   )
               )
            << QVariant::fromValue(
                   QDBusObjectPath(
                       accessPointPath.isEmpty()
                       ? QStringLiteral("/")
                       : accessPointPath
                   )
               )
            << options;
    }

    QDBusPendingCallWatcher *watcher =
        new QDBusPendingCallWatcher(
            QDBusConnection::systemBus()
                .asyncCall(
                    message,
                    DbusOperationTimeoutMs
                ),
            this
        );

    watcher->setProperty(
        "action",
        hidden
        ? QStringLiteral("addHidden")
        : QStringLiteral("connect")
    );

    watcher->setProperty(
        "payload",
        sanitizedPayload(payload)
    );

    watcher->setProperty(
        "serial",
        QVariant::fromValue<
            qulonglong
        >(m_operationSerial)
    );

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        &NetworkManager::onAddAndActivateConnectionFinished
    );

    return true;
}

bool NetworkManager::deactivateConnection(
    const QString &activeConnectionPath,
    const QVariantMap &payload)
{
    if (activeConnectionPath.isEmpty())
        return false;

    beginOperation(
        QStringLiteral("disconnect"),
        payload
    );

    QDBusMessage message =
        QDBusMessage::createMethodCall(
            ServiceName,
            RootPath,
            RootInterface,
            QStringLiteral(
                "DeactivateConnection"
            )
        );

    message
        << QVariant::fromValue(
               QDBusObjectPath(
                   activeConnectionPath
               )
           );

    QDBusPendingCallWatcher *watcher =
        new QDBusPendingCallWatcher(
            QDBusConnection::systemBus()
                .asyncCall(
                    message,
                    DbusOperationTimeoutMs
                ),
            this
        );

    watcher->setProperty(
        "action",
        QStringLiteral("disconnect")
    );

    watcher->setProperty(
        "payload",
        sanitizedPayload(payload)
    );

    watcher->setProperty(
        "serial",
        QVariant::fromValue<
            qulonglong
        >(m_operationSerial)
    );

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        &NetworkManager::onDisconnectFinished
    );

    return true;
}

bool NetworkManager::deleteSavedConnection(
    const QString &connectionPath,
    const QVariantMap &payload)
{
    if (connectionPath.isEmpty())
        return false;

    beginOperation(
        QStringLiteral("forget"),
        payload
    );

    QDBusMessage message =
        QDBusMessage::createMethodCall(
            ServiceName,
            connectionPath,
            SettingsConnectionInterface,
            QStringLiteral("Delete")
        );

    QDBusPendingCallWatcher *watcher =
        new QDBusPendingCallWatcher(
            QDBusConnection::systemBus()
                .asyncCall(
                    message,
                    DbusOperationTimeoutMs
                ),
            this
        );

    watcher->setProperty(
        "action",
        QStringLiteral("forget")
    );

    watcher->setProperty(
        "payload",
        sanitizedPayload(payload)
    );

    watcher->setProperty(
        "serial",
        QVariant::fromValue<
            qulonglong
        >(m_operationSerial)
    );

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        &NetworkManager::onForgetFinished
    );

    return true;
}

/*
    ========================================================================
                         ASYNC OPERATION REPLIES
    ========================================================================
*/

void NetworkManager::onScanRequestFinished(
    QDBusPendingCallWatcher *watcher)
{
    const quint64 serial =
        watcher->property(
            "serial"
        ).toULongLong();

    const QVariantMap payload =
        watcher->property(
            "payload"
        ).toMap();

    if (serial != m_operationSerial) {
        watcher->deleteLater();
        return;
    }

    if (watcher->isError()) {
        const QString error =
            watcher->error().message();

        m_scanSettleTimer.stop();
        m_scanTimeoutTimer.stop();

        setScanning(false);

        finishOperation(
            QStringLiteral("scan"),
            false,
            error.isEmpty()
            ? QStringLiteral(
                  "Wi-Fi scan request failed"
              )
            : error,
            payload
        );

        emit scanFinished(
            false,
            error
        );

        watcher->deleteLater();
        return;
    }

    setLastOperation(
        QStringLiteral(
            "Wi-Fi scan request accepted"
        )
    );

    m_scanSettleTimer.start(
        ScanSettleDelayMs
    );

    watcher->deleteLater();
}

void NetworkManager::onActivateConnectionFinished(
    QDBusPendingCallWatcher *watcher)
{
    const quint64 serial =
        watcher->property(
            "serial"
        ).toULongLong();

    const QVariantMap payload =
        watcher->property(
            "payload"
        ).toMap();

    const QString action =
        watcher->property(
            "action"
        ).toString();

    if (serial != m_operationSerial) {
        watcher->deleteLater();
        return;
    }

    if (watcher->isError()) {
        finishOperation(
            action,
            false,
            watcher->error().message(),
            payload
        );
    } else {
        finishOperation(
            action,
            true,
            QStringLiteral(
                "Connection request accepted"
            ),
            payload
        );

        scheduleRefresh(500);
    }

    watcher->deleteLater();
}

void NetworkManager::onAddAndActivateConnectionFinished(
    QDBusPendingCallWatcher *watcher)
{
    const quint64 serial =
        watcher->property(
            "serial"
        ).toULongLong();

    const QVariantMap payload =
        watcher->property(
            "payload"
        ).toMap();

    const QString action =
        watcher->property(
            "action"
        ).toString();

    if (serial != m_operationSerial) {
        watcher->deleteLater();
        return;
    }

    if (watcher->isError()) {
        finishOperation(
            action,
            false,
            watcher->error().message(),
            payload
        );
    } else {
        finishOperation(
            action,
            true,
            action ==
            QStringLiteral("addHidden")
            ? QStringLiteral(
                  "Hidden network request accepted"
              )
            : QStringLiteral(
                  "Connection request accepted"
              ),
            payload
        );

        scheduleRefresh(650);
    }

    watcher->deleteLater();
}

void NetworkManager::onDisconnectFinished(
    QDBusPendingCallWatcher *watcher)
{
    const quint64 serial =
        watcher->property(
            "serial"
        ).toULongLong();

    const QVariantMap payload =
        watcher->property(
            "payload"
        ).toMap();

    if (serial != m_operationSerial) {
        watcher->deleteLater();
        return;
    }

    if (watcher->isError()) {
        finishOperation(
            QStringLiteral("disconnect"),
            false,
            watcher->error().message(),
            payload
        );
    } else {
        finishOperation(
            QStringLiteral("disconnect"),
            true,
            QStringLiteral(
                "Wi-Fi disconnected"
            ),
            payload
        );

        scheduleRefresh(350);
    }

    watcher->deleteLater();
}

void NetworkManager::onForgetFinished(
    QDBusPendingCallWatcher *watcher)
{
    const quint64 serial =
        watcher->property(
            "serial"
        ).toULongLong();

    const QVariantMap payload =
        watcher->property(
            "payload"
        ).toMap();

    if (serial != m_operationSerial) {
        watcher->deleteLater();
        return;
    }

    if (watcher->isError()) {
        finishOperation(
            QStringLiteral("forget"),
            false,
            watcher->error().message(),
            payload
        );
    } else {
        finishOperation(
            QStringLiteral("forget"),
            true,
            QStringLiteral(
                "Saved network profile removed"
            ),
            payload
        );

        scheduleRefresh(300);
    }

    watcher->deleteLater();
}

void NetworkManager::onWifiToggleFinished(
    QDBusPendingCallWatcher *watcher)
{
    const quint64 serial =
        watcher->property(
            "serial"
        ).toULongLong();

    const QVariantMap payload =
        watcher->property(
            "payload"
        ).toMap();

    if (serial != m_operationSerial) {
        watcher->deleteLater();
        return;
    }

    if (watcher->isError()) {
        finishOperation(
            QStringLiteral(
                "setWifiEnabled"
            ),
            false,
            watcher->error().message(),
            payload
        );
    } else {
        const bool enabled =
            payload.value(
                QStringLiteral("enabled")
            ).toBool();

        finishOperation(
            QStringLiteral(
                "setWifiEnabled"
            ),
            true,
            enabled
            ? QStringLiteral(
                  "Wi-Fi enabled"
              )
            : QStringLiteral(
                  "Wi-Fi disabled"
              ),
            payload
        );

        scheduleRefresh(350);
    }

    watcher->deleteLater();
}

/*
    ========================================================================
                            SCAN COMPLETION
    ========================================================================
*/

void NetworkManager::finishScanRefresh()
{
    if (!m_scanning)
        return;

    const QVariant completed = readProperty(m_wirelessDevicePath, WirelessInterface,
                                           QStringLiteral("LastScan"));
    if (!completed.isValid() || completed.toLongLong() <= m_scanStartTimestamp) {
        m_scanSettleTimer.start(ScanSettleDelayMs);
        return;
    }
    m_scanTimeoutTimer.stop();

    coalescedRefresh();
    setScanning(false);

    const QVariantMap payload =
        m_pendingPayload;

    finishOperation(
        QStringLiteral("scan"),
        true,
        QStringLiteral(
            "Wi-Fi scan completed"
        ),
        payload
    );

    emit scanFinished(
        true,
        QStringLiteral(
            "Wi-Fi scan completed"
        )
    );
}

void NetworkManager::handleScanTimeout()
{
    if (!m_scanning)
        return;

    m_scanSettleTimer.stop();
    setScanning(false);

    const QVariantMap payload =
        m_pendingPayload;

    coalescedRefresh();

    finishOperation(
        QStringLiteral("scan"),
        false,
        QStringLiteral(
            "Wi-Fi scan timed out"
        ),
        payload
    );

    emit scanFinished(
        false,
        QStringLiteral(
            "Wi-Fi scan timed out"
        )
    );
}

/*
    ========================================================================
                          D-BUS CHANGE HANDLERS
    ========================================================================
*/

void NetworkManager::onRootPropertiesChanged(
    const QString &interfaceName,
    const QVariantMap &changedProperties,
    const QStringList &invalidatedProperties)
{
    Q_UNUSED(changedProperties)
    Q_UNUSED(invalidatedProperties)

    if (interfaceName != RootInterface)
        return;

    scheduleRefresh(100);
}

void NetworkManager::onDevicePropertiesChanged(
    const QString &interfaceName,
    const QVariantMap &changedProperties,
    const QStringList &invalidatedProperties)
{
    Q_UNUSED(changedProperties)
    Q_UNUSED(invalidatedProperties)

    if (interfaceName != DeviceInterface &&
            interfaceName !=
            WirelessInterface) {
        return;
    }

    scheduleRefresh(120);
}

void NetworkManager::onAccessPointPropertiesChanged(
    const QString &interfaceName,
    const QVariantMap &changedProperties,
    const QStringList &invalidatedProperties)
{
    Q_UNUSED(changedProperties)
    Q_UNUSED(invalidatedProperties)

    if (interfaceName !=
            AccessPointInterface) {
        return;
    }

    scheduleRefresh(160);
}

void NetworkManager::onActiveConnectionPropertiesChanged(
    const QString &interfaceName,
    const QVariantMap &changedProperties,
    const QStringList &invalidatedProperties)
{
    Q_UNUSED(changedProperties)
    Q_UNUSED(invalidatedProperties)

    if (interfaceName !=
            ActiveConnectionInterface) {
        return;
    }

    scheduleRefresh(100);
}

void NetworkManager::onIpConfigurationPropertiesChanged(
    const QString &interfaceName,
    const QVariantMap &changedProperties,
    const QStringList &invalidatedProperties)
{
    Q_UNUSED(changedProperties)
    Q_UNUSED(invalidatedProperties)

    if (interfaceName != Ip4ConfigInterface &&
            interfaceName !=
            Dhcp4ConfigInterface) {
        return;
    }

    scheduleRefresh(100);
}

void NetworkManager::onSettingsConnectionUpdated()
{
    scheduleRefresh(120);
}

void NetworkManager::onSettingsConnectionRemoved()
{
    scheduleRefresh(120);
}

/*
    ========================================================================
                         OPERATION LIFECYCLE
    ========================================================================
*/

void NetworkManager::beginOperation(
    const QString &action,
    const QVariantMap &payload)
{
    ++m_operationSerial;

    m_pendingAction = action;
    m_pendingPayload =
        sanitizedPayload(payload);

    setLastError(QString());

    setLastOperation(
        QStringLiteral(
            "%1 started"
        ).arg(action)
    );

    setOperationBusy(true);

    emit operationStarted(
        action,
        m_pendingPayload
    );
}

void NetworkManager::finishOperation(
    const QString &action,
    bool success,
    const QString &message,
    const QVariantMap &payload)
{
    const QVariantMap safePayload =
        payload.isEmpty()
        ? m_pendingPayload
        : sanitizedPayload(payload);

    if (success)
        setLastError(QString());
    else
        setLastError(message);

    setLastOperation(message);

    if (action ==
            QStringLiteral("scan")) {
        setScanning(false);
    }

    setOperationBusy(false);

    m_pendingAction.clear();
    clearPendingSensitiveData();

    emit operationFinished(
        action,
        success,
        message,
        safePayload
    );
}

void NetworkManager::setOperationBusy(
    bool busy)
{
    if (m_operationBusy == busy)
        return;

    m_operationBusy = busy;
    emit operationBusyChanged();
}

void NetworkManager::setScanning(
    bool scanning)
{
    if (m_scanning == scanning)
        return;

    m_scanning = scanning;
    emit scanningChanged();
}

void NetworkManager::setLastError(
    const QString &message)
{
    if (m_lastError == message)
        return;

    m_lastError = message;
    emit lastErrorChanged();
}

void NetworkManager::setLastOperation(
    const QString &message)
{
    if (m_lastOperation == message)
        return;

    m_lastOperation = message;
    emit lastOperationChanged();
}

/*
    ========================================================================
                         SENSITIVE DATA HANDLING
    ========================================================================
*/

QVariantMap NetworkManager::sanitizedPayload(
    const QVariantMap &payload) const
{
    QVariantMap result;

    for (auto iterator =
             payload.constBegin();
         iterator != payload.constEnd();
         ++iterator) {
        const QString normalizedKey =
            iterator.key()
                .trimmed()
                .toLower();

        if (normalizedKey.contains(
                QStringLiteral("password")) ||
                normalizedKey.contains(
                    QStringLiteral("passphrase")) ||
                normalizedKey ==
                QStringLiteral("psk") ||
                normalizedKey.contains(
                    QStringLiteral("secret")) ||
                normalizedKey.startsWith(
                    QStringLiteral("wep-key"))) {
            continue;
        }

        const QVariant value =
            iterator.value();

        if (value.type() ==
                QVariant::Map) {
            result.insert(
                iterator.key(),
                sanitizedPayload(
                    value.toMap()
                )
            );

            continue;
        }

        if (value.type() ==
                QVariant::List) {
            QVariantList sanitizedList;

            for (const QVariant &entry :
                    value.toList()) {
                if (entry.type() ==
                        QVariant::Map) {
                    sanitizedList.append(
                        sanitizedPayload(
                            entry.toMap()
                        )
                    );
                } else {
                    sanitizedList.append(entry);
                }
            }

            result.insert(
                iterator.key(),
                sanitizedList
            );

            continue;
        }

        result.insert(
            iterator.key(),
            value
        );
    }

    return result;
}

void NetworkManager::clearPendingSensitiveData()
{
    m_pendingPayload.clear();
}

/*
    ========================================================================
                         ADDRESS CONVERSION
    ========================================================================
*/

QString NetworkManager::ipv4FromUInt(
    uint value) const
{
    if (value == 0)
        return QStringLiteral("--");

    const quint32 hostOrder =
        qFromBigEndian<quint32>(
            value
        );

    const QHostAddress address(
        hostOrder
    );

    const QString text =
        address.toString();

    return text.isEmpty()
           ? QStringLiteral("--")
           : text;
}

QVariantList NetworkManager::dnsFromUIntList(
    const QVariant &value) const
{
    QVariantList result;

    const QList<uint> addresses =
        qdbus_cast<QList<uint>>(
            value
        );

    for (uint address : addresses) {
        const QString text =
            ipv4FromUInt(address);

        if (text !=
                QStringLiteral("--") &&
                !result.contains(text)) {
            result.append(text);
        }
    }

    if (!result.isEmpty())
        return result;

    for (const QVariant &entry :
            value.toList()) {
        const QString text =
            ipv4FromUInt(
                entry.toUInt()
            );

        if (text !=
                QStringLiteral("--") &&
                !result.contains(text)) {
            result.append(text);
        }
    }

    return result;
}

QString NetworkManager::detectTailscaleIp() const
{
    const QList<QNetworkInterface> interfaces =
        QNetworkInterface::allInterfaces();

    for (const QNetworkInterface &interface :
            interfaces) {
        const QString name =
            interface.name().toLower();

        if (!name.startsWith(
                QStringLiteral("tailscale"))) {
            continue;
        }

        if (!(interface.flags() &
                QNetworkInterface::IsUp)) {
            continue;
        }

        for (const QNetworkAddressEntry &entry :
                interface.addressEntries()) {
            if (entry.ip().protocol() ==
                    QAbstractSocket::IPv4Protocol) {
                return entry.ip()
                    .toString();
            }
        }
    }

    return QStringLiteral("--");
}
