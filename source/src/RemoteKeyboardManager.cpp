#include "RemoteKeyboardManager.h"

#include <QAbstractSocket>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QProcess>
#include <QStandardPaths>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslSocket>
#include <QStringList>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QUrl>
#include <QtGlobal>

namespace {
constexpr quint16 kFirstPort = 38761;
constexpr quint16 kLastPort = 38780;
constexpr qsizetype kMaximumRequestBytes = 128 * 1024;
constexpr qsizetype kMaximumRemoteText = 65536;
constexpr int kPairingLifetimeSeconds = 60;
constexpr int kClosedKeyboardGraceMs = 20000;
constexpr int kLanPairingAttemptLimit = 5;
constexpr int kTailscalePairingAttemptLimit = 10;
constexpr qint64 kPairingLockoutMs = 30LL * 60LL * 1000LL;


bool isTailscaleAddress(const QHostAddress &address)
{
    // Qt can represent an IPv4 peer as either native IPv4 or IPv4-mapped
    // IPv6. Ask QHostAddress for a convertible IPv4 value first so a
    // Tailscale 100.64.0.0/10 client always receives the intended 10-try
    // policy instead of accidentally falling back to the LAN limit.
    bool ipv4Ok = false;
    const quint32 ipv4 = address.toIPv4Address(&ipv4Ok);
    if (ipv4Ok)
        return (ipv4 & 0xFFC00000U) == 0x64400000U; // 100.64.0.0/10

    if (address.protocol() == QAbstractSocket::IPv6Protocol) {
        const Q_IPV6ADDR value = address.toIPv6Address();
        return value[0] == 0xfd && value[1] == 0x7a &&
               value[2] == 0x11 && value[3] == 0x5c &&
               value[4] == 0xa1 && value[5] == 0xe0; // fd7a:115c:a1e0::/48
    }

    return false;
}

int addressScore(const QHostAddress &address)
{
    if (address.protocol() != QAbstractSocket::IPv4Protocol || address.isLoopback())
        return -1;
    const quint32 value = address.toIPv4Address();
    if ((value & 0xFF000000U) == 0x0A000000U) return 500;       // 10/8
    if ((value & 0xFFF00000U) == 0xAC100000U) return 500;       // 172.16/12
    if ((value & 0xFFFF0000U) == 0xC0A80000U) return 500;       // 192.168/16
    if ((value & 0xFFC00000U) == 0x64400000U) return 350;       // Tailscale/CGNAT 100.64/10
    if ((value & 0xFFFF0000U) == 0xA9FE0000U) return 20;        // Link-local
    return 200;
}

QByteArray jsonError(const QString &message)
{
    QJsonObject object;
    object.insert(QStringLiteral("ok"), false);
    object.insert(QStringLiteral("error"), message);
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

QByteArray jsonOk(const QJsonObject &extra = {})
{
    QJsonObject object = extra;
    object.insert(QStringLiteral("ok"), true);
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

class TlsTcpServer final : public QTcpServer
{
public:
    explicit TlsTcpServer(QObject *parent = nullptr) : QTcpServer(parent) {}

    void setTlsConfiguration(const QSslConfiguration &configuration)
    {
        m_configuration = configuration;
    }

protected:
    void incomingConnection(qintptr socketDescriptor) override
    {
        auto *socket = new QSslSocket(this);
        if (!socket->setSocketDescriptor(socketDescriptor)) {
            socket->deleteLater();
            return;
        }
        socket->setSslConfiguration(m_configuration);
        auto *timer = new QTimer(socket);
        timer->setSingleShot(true);
        timer->setInterval(5000);
        QObject::connect(timer, &QTimer::timeout, socket, [socket]() {
            if (!socket->isEncrypted())
                socket->abort();
        });
        QObject::connect(socket, &QSslSocket::encrypted, this, [this, socket, timer]() {
            timer->stop();
            addPendingConnection(socket);
            emit newConnection();
        });
        QObject::connect(socket, &QSslSocket::errorOccurred, socket, [socket](QAbstractSocket::SocketError) {
            if (!socket->isEncrypted())
                socket->deleteLater();
        });
        timer->start();
        socket->startServerEncryption();
    }

private:
    QSslConfiguration m_configuration;
};

bool loadRemoteKeyboardTls(const QString &stateDirectory, QSslConfiguration *configuration, QString *error)
{
    if (!configuration)
        return false;
    QDir().mkpath(stateDirectory);
    const QString certPath = QDir(stateDirectory).filePath(QStringLiteral("tls.crt"));
    const QString keyPath = QDir(stateDirectory).filePath(QStringLiteral("tls.key"));
    if (!QFileInfo::exists(certPath) || !QFileInfo::exists(keyPath)) {
        const QString openssl = QStandardPaths::findExecutable(QStringLiteral("openssl"));
        if (openssl.isEmpty()) {
            if (error) *error = QStringLiteral("OpenSSL is required for Remote Keyboard TLS.");
            return false;
        }
        QProcess process;
        process.start(openssl, {QStringLiteral("req"), QStringLiteral("-x509"),
                                QStringLiteral("-newkey"), QStringLiteral("rsa:2048"),
                                QStringLiteral("-nodes"), QStringLiteral("-keyout"), keyPath,
                                QStringLiteral("-out"), certPath, QStringLiteral("-days"),
                                QStringLiteral("825"), QStringLiteral("-subj"),
                                QStringLiteral("/CN=neutron-keyboard.local"), QStringLiteral("-addext"),
                                QStringLiteral("subjectAltName=DNS:neutronos.local,DNS:neutron-keyboard.local,IP:127.0.0.1")});
        if (!process.waitForStarted(3000) || !process.waitForFinished(30000) || process.exitCode() != 0) {
            if (error) *error = QStringLiteral("Could not create the Remote Keyboard TLS certificate.");
            return false;
        }
    }
    QFile::setPermissions(keyPath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    const QList<QSslCertificate> certificates = QSslCertificate::fromPath(certPath);
    QFile keyFile(keyPath);
    if (certificates.isEmpty() || !keyFile.open(QIODevice::ReadOnly)) {
        if (error) *error = QStringLiteral("Remote Keyboard TLS certificate files are invalid.");
        return false;
    }
    QSslKey key(keyFile.readAll(), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
    if (key.isNull()) {
        if (error) *error = QStringLiteral("Remote Keyboard TLS private key is invalid.");
        return false;
    }
    QSslConfiguration value = QSslConfiguration::defaultConfiguration();
    value.setLocalCertificate(certificates.first());
    value.setPrivateKey(key);
    value.setProtocol(QSsl::TlsV1_2OrLater);
    value.setPeerVerifyMode(QSslSocket::VerifyNone);
    *configuration = value;
    return true;
}
}

RemoteKeyboardManager::RemoteKeyboardManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_server(new TlsTcpServer(this)),
      m_pairingTimer(new QTimer(this)),
      m_graceTimer(new QTimer(this)),
      m_status(QStringLiteral("Remote keyboard is stopped."))
{
    connect(m_server, &QTcpServer::newConnection,
            this, &RemoteKeyboardManager::handleNewConnection);

    m_pairingTimer->setInterval(250);
    connect(m_pairingTimer, &QTimer::timeout, this, [this]() {
        if (!pairingCodeActive()) {
            clearPairingCode();
            return;
        }
        emit stateChanged();
    });

    m_graceTimer->setSingleShot(true);
    m_graceTimer->setInterval(kClosedKeyboardGraceMs);
    connect(m_graceTimer, &QTimer::timeout,
            this, &RemoteKeyboardManager::expireGraceSession);
}

RemoteKeyboardManager::~RemoteKeyboardManager()
{
    stop();
}

bool RemoteKeyboardManager::running() const { return m_server && m_server->isListening(); }
QString RemoteKeyboardManager::url() const { return m_url; }
QString RemoteKeyboardManager::qrImage() const { return m_qrImage; }
QString RemoteKeyboardManager::status() const { return m_status; }
quint16 RemoteKeyboardManager::port() const { return m_port; }
bool RemoteKeyboardManager::keyboardActive() const { return m_keyboardActive; }
bool RemoteKeyboardManager::pairingPanelVisible() const { return m_pairingPanelVisible; }
QString RemoteKeyboardManager::pairingCode() const { return pairingCodeActive() ? m_pairingCode : QString(); }
int RemoteKeyboardManager::authenticatedClientCount() const { return m_authenticatedSessions.size(); }

int RemoteKeyboardManager::pairingSecondsRemaining() const
{
    if (m_pairingCode.isEmpty() || m_pairingExpiresAtMs <= 0)
        return 0;
    const qint64 remaining = m_pairingExpiresAtMs - QDateTime::currentMSecsSinceEpoch();
    if (remaining <= 0)
        return 0;
    return qMax(1, int((remaining + 999) / 1000));
}

bool RemoteKeyboardManager::pairingCodeActive() const
{
    return !m_pairingCode.isEmpty() &&
           m_pairingExpiresAtMs > QDateTime::currentMSecsSinceEpoch();
}

QString RemoteKeyboardManager::stateDirectory() const
{
    return QStringLiteral("/var/lib/neutronos/apps/remote-keyboard");
}

QString RemoteKeyboardManager::settingsPath() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("keyboard-settings.json"));
}

QString RemoteKeyboardManager::makeSessionToken() const
{
    QByteArray bytes;
    bytes.reserve(32);
    for (int i = 0; i < 4; ++i) {
        const quint64 value = QRandomGenerator::system()->generate64();
        bytes.append(reinterpret_cast<const char *>(&value), sizeof(value));
    }
    return QString::fromLatin1(bytes.toBase64(QByteArray::Base64UrlEncoding |
                                               QByteArray::OmitTrailingEquals));
}

QString RemoteKeyboardManager::makePairingCode() const
{
    QString digits;
    digits.reserve(8);
    for (int i = 0; i < 8; ++i)
        digits.append(QString::number(QRandomGenerator::system()->bounded(10)));
    return digits.left(4) + QLatin1Char('-') + digits.mid(4);
}

QString RemoteKeyboardManager::preferredAddress() const
{
    QString best;
    int bestScore = -1;
    const auto interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &interface : interfaces) {
        if (!(interface.flags() & QNetworkInterface::IsUp) ||
            !(interface.flags() & QNetworkInterface::IsRunning) ||
            (interface.flags() & QNetworkInterface::IsLoopBack)) {
            continue;
        }
        for (const QNetworkAddressEntry &entry : interface.addressEntries()) {
            const QHostAddress address = entry.ip();
            const int score = addressScore(address);
            if (score > bestScore) {
                bestScore = score;
                best = address.toString();
            }
        }
    }
    return best;
}

void RemoteKeyboardManager::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit stateChanged();
}

bool RemoteKeyboardManager::authLocked() const
{
    return m_authLockedUntilMs > QDateTime::currentMSecsSinceEpoch();
}

int RemoteKeyboardManager::authLockSecondsRemaining() const
{
    const qint64 remaining = m_authLockedUntilMs - QDateTime::currentMSecsSinceEpoch();
    return remaining > 0 ? qMax(1, int((remaining + 999) / 1000)) : 0;
}

void RemoteKeyboardManager::refreshAuthLockout()
{
    if (m_authLockedUntilMs <= 0 || authLocked())
        return;
    m_authLockedUntilMs = 0;
    m_lanFailedPairingAttempts = 0;
    m_tailscaleFailedPairingAttempts = 0;
    emit stateChanged();
}

bool RemoteKeyboardManager::peerIsTailscale(QTcpSocket *socket) const
{
    return socket && isTailscaleAddress(socket->peerAddress());
}

int RemoteKeyboardManager::authAttemptLimit(QTcpSocket *socket) const
{
    return peerIsTailscale(socket) ? kTailscalePairingAttemptLimit : kLanPairingAttemptLimit;
}

int RemoteKeyboardManager::authFailedAttempts(QTcpSocket *socket) const
{
    return peerIsTailscale(socket) ? m_tailscaleFailedPairingAttempts : m_lanFailedPairingAttempts;
}

void RemoteKeyboardManager::recordAuthFailure(QTcpSocket *socket)
{
    refreshAuthLockout();
    if (authLocked())
        return;

    int *counter = peerIsTailscale(socket)
        ? &m_tailscaleFailedPairingAttempts
        : &m_lanFailedPairingAttempts;
    ++(*counter);

    if (*counter >= authAttemptLimit(socket)) {
        m_authLockedUntilMs = QDateTime::currentMSecsSinceEpoch() + kPairingLockoutMs;
        setStatus(QStringLiteral("Remote Keyboard pairing locked for 30 minutes after too many failed codes."));
    }
    emit stateChanged();
}

void RemoteKeyboardManager::resetAuthFailures()
{
    const bool changed = m_lanFailedPairingAttempts != 0 ||
                         m_tailscaleFailedPairingAttempts != 0 ||
                         m_authLockedUntilMs != 0;
    m_lanFailedPairingAttempts = 0;
    m_tailscaleFailedPairingAttempts = 0;
    m_authLockedUntilMs = 0;
    if (changed)
        emit stateChanged();
}

bool RemoteKeyboardManager::ensureServerRunning()
{
    if (running())
        return true;

    const QString address = preferredAddress();
    if (address.isEmpty()) {
        setStatus(QStringLiteral("No active IPv4 network address is available."));
        return false;
    }

    QSslConfiguration tlsConfiguration;
    QString tlsError;
    if (!loadRemoteKeyboardTls(stateDirectory(), &tlsConfiguration, &tlsError)) {
        setStatus(tlsError);
        return false;
    }
    static_cast<TlsTcpServer *>(m_server)->setTlsConfiguration(tlsConfiguration);

    m_port = 0;
    for (quint16 candidate = kFirstPort; candidate <= kLastPort; ++candidate) {
        if (m_server->listen(QHostAddress::AnyIPv4, candidate)) {
            m_port = candidate;
            break;
        }
    }
    if (!running()) {
        setStatus(QStringLiteral("Could not open a NeutronOS Remote Keyboard port."));
        return false;
    }

    m_url = QStringLiteral("https://%1:%2/").arg(address).arg(m_port);
    m_qrImage.clear();
    setStatus(QStringLiteral("Remote Keyboard is ready for a temporary pairing code."));
    emit stateChanged();
    return true;
}

bool RemoteKeyboardManager::start(const QString &initialText)
{
    m_initialText = initialText.left(kMaximumRemoteText);
    return ensureServerRunning();
}

void RemoteKeyboardManager::clearPairingCode()
{
    const bool changed = !m_pairingCode.isEmpty() || m_pairingExpiresAtMs != 0;
    m_pairingCode.clear();
    m_pairingExpiresAtMs = 0;
    m_pairingTimer->stop();
    if (changed)
        emit stateChanged();
}

void RemoteKeyboardManager::stop()
{
    m_pairingTimer->stop();
    m_graceTimer->stop();
    if (m_server)
        m_server->close();

    const auto sockets = m_buffers.keys();
    for (QTcpSocket *socket : sockets) {
        if (socket) {
            socket->disconnectFromHost();
            socket->deleteLater();
        }
    }
    m_buffers.clear();
    m_authenticatedSessions.clear();
    m_pairingCode.clear();
    m_pairingExpiresAtMs = 0;
    m_url.clear();
    m_qrImage.clear();
    m_port = 0;
    m_pairingPanelVisible = false;
    setStatus(QStringLiteral("Remote keyboard is stopped."));
    emit stateChanged();
}

bool RemoteKeyboardManager::regenerate(const QString &initialText)
{
    m_initialText = initialText.left(kMaximumRemoteText);
    if (!m_authenticatedSessions.isEmpty()) {
        setStatus(QStringLiteral("Remote Keyboard Connected. One-device security guard active."));
        return false;
    }
    if (!ensureServerRunning())
        return false;
    generatePairingCode();
    return pairingCodeActive();
}

void RemoteKeyboardManager::setInitialText(const QString &text)
{
    m_initialText = text.left(kMaximumRemoteText);
}

void RemoteKeyboardManager::setKeyboardActive(bool active)
{
    if (m_keyboardActive == active) {
        if (active && m_graceTimer->isActive())
            m_graceTimer->stop();
        return;
    }

    m_keyboardActive = active;
    if (active) {
        m_graceTimer->stop();
        if (!m_authenticatedSessions.isEmpty())
            setStatus(QStringLiteral("Remote Keyboard Connected. One-device security guard active."));
        else if (running())
            setStatus(QStringLiteral("Remote Keyboard input is active."));
    } else {
        m_pairingPanelVisible = false;
        if (running()) {
            m_graceTimer->start();
            setStatus(QStringLiteral("Remote Keyboard input is paused for 20 seconds."));
        }
    }
    emit stateChanged();
}

bool RemoteKeyboardManager::showPairingPanel()
{
    if (!m_keyboardActive) {
        setStatus(QStringLiteral("Open the NeutronOS keyboard before pairing a remote device."));
        return false;
    }
    if (!ensureServerRunning())
        return false;
    m_pairingPanelVisible = true;
    emit stateChanged();
    return true;
}

void RemoteKeyboardManager::hidePairingPanel()
{
    if (!m_pairingPanelVisible)
        return;
    m_pairingPanelVisible = false;
    emit stateChanged();
}

QString RemoteKeyboardManager::generatePairingCode()
{
    if (!m_keyboardActive) {
        setStatus(QStringLiteral("Open the NeutronOS keyboard before generating a code."));
        return QString();
    }

    if (!m_authenticatedSessions.isEmpty()) {
        clearPairingCode();
        setStatus(QStringLiteral("Remote Keyboard Connected. One-device security guard active."));
        return QString();
    }

    refreshAuthLockout();
    if (authLocked()) {
        const int seconds = authLockSecondsRemaining();
        setStatus(QStringLiteral("Remote Keyboard pairing is locked. Try again in %1 minute(s).")
                      .arg(qMax(1, (seconds + 59) / 60)));
        return QString();
    }

    if (!ensureServerRunning())
        return QString();

    m_pairingPanelVisible = true;
    m_pairingCode = makePairingCode();
    m_pairingExpiresAtMs = QDateTime::currentMSecsSinceEpoch() +
                           qint64(kPairingLifetimeSeconds) * 1000;
    m_pairingTimer->start();
    setStatus(QStringLiteral("Pairing code active for 60 seconds."));
    emit stateChanged();
    return m_pairingCode;
}

void RemoteKeyboardManager::expireGraceSession()
{
    if (m_keyboardActive)
        return;
    stop();
}

QVariant RemoteKeyboardManager::keyboardSetting(const QString &key, const QVariant &fallback) const
{
    QFile file(settingsPath());
    if (!file.open(QIODevice::ReadOnly))
        return fallback;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return fallback;
    return document.object().value(key).toVariant().isValid()
               ? document.object().value(key).toVariant()
               : fallback;
}

bool RemoteKeyboardManager::saveKeyboardSetting(const QString &key, const QVariant &value)
{
    if (!key.startsWith(QStringLiteral("keyboard.")) || key.size() > 80)
        return false;
    QDir directory(stateDirectory());
    if (!directory.mkpath(QStringLiteral(".")) && !directory.exists())
        return false;
    QFile::setPermissions(stateDirectory(),
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

    QJsonObject object;
    QFile current(settingsPath());
    if (current.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(current.readAll());
        if (document.isObject())
            object = document.object();
    }
    object.insert(key, QJsonValue::fromVariant(value));
    QSaveFile output(settingsPath());
    if (!output.open(QIODevice::WriteOnly))
        return false;
    if (output.write(QJsonDocument(object).toJson(QJsonDocument::Indented)) < 0)
        return false;
    if (!output.commit())
        return false;
    QFile::setPermissions(settingsPath(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    emit stateChanged();
    return true;
}

QByteArray RemoteKeyboardManager::pairingPageHtml() const
{
    return R"HTML(<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>NeutronOS Remote Keyboard</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(circle at 50% -10%,#102b4b 0,#07111f 38%,#02050a 80%);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#f5faff;display:grid;place-items:center;padding:24px}.panel{width:min(520px,100%);background:#07111fee;border:1px solid #304f69;border-radius:28px;padding:32px;box-shadow:0 28px 80px #000b,0 0 40px #ff354a12;text-align:center}.brand{font-size:13px;letter-spacing:.22em;color:#ff5365;font-weight:900}.panel h1{margin:10px 0 8px;font-size:clamp(28px,7vw,42px)}.panel p{margin:0 auto 26px;color:#9cb2c9;line-height:1.5;max-width:390px}.code{width:100%;font:800 30px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.14em;text-align:center;background:#020812;color:#fff;border:2px solid #355976;border-radius:18px;padding:18px 10px;outline:0}.code:focus{border-color:#ff354a;box-shadow:0 0 0 4px #ff354a20}.button{width:100%;margin-top:14px;border:1px solid #ff5365;background:#3a121a;color:#fff;border-radius:16px;padding:15px;font-size:16px;font-weight:900}.error{min-height:22px;margin-top:15px;color:#ff7482;font-weight:700}.hint{margin-top:20px;color:#647f98;font-size:12px}
</style></head><body><section class="panel"><div class="brand">NEUTRONOS</div><h1>Remote Keyboard</h1><p>Enter the temporary code shown on the NeutronOS keyboard.</p><input id="code" class="code" inputmode="numeric" autocomplete="one-time-code" maxlength="9" placeholder="0000-0000"><button id="connect" class="button">CONNECT</button><div id="error" class="error"></div><div class="hint">The code expires after 60 seconds and is never placed in the URL.<br>Security lockout: 5 failed LAN codes, or 10 over Tailscale, locks pairing for 30 minutes.</div></section>
<script>
const code=document.getElementById('code'),error=document.getElementById('error');function fmt(){let v=code.value.replace(/\D/g,'').slice(0,8);code.value=v.slice(0,4)+(v.length>4?'-'+v.slice(4):'')}code.addEventListener('input',fmt);async function pair(){error.textContent='';try{const r=await fetch('/pair',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:code.value})});const j=await r.json();if(!r.ok||!j.ok)throw new Error(j.error||'Code rejected');location.reload()}catch(e){error.textContent=e.message||'Unable to connect'}}document.getElementById('connect').onclick=pair;code.addEventListener('keydown',e=>{if(e.key==='Enter')pair()});code.focus();
</script></body></html>)HTML";
}

QByteArray RemoteKeyboardManager::keyboardPageHtml() const
{
    return R"HTML(<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>NeutronOS Remote Keyboard</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(circle at 50% -10%,#102b4b 0,#07111f 38%,#02050a 80%);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#f5faff;padding:calc(24px + env(safe-area-inset-top)) 18px calc(24px + env(safe-area-inset-bottom))}.shell{width:min(760px,100%);margin:0 auto}.head{text-align:center;margin:4vh 0 24px}.eyebrow{color:#ff5365;font-size:12px;letter-spacing:.22em;font-weight:900}.head h1{margin:7px 0 5px;font-size:clamp(28px,7vw,42px)}.state{color:#9cb2c9}.panel{background:#07111fee;border:1px solid #304f69;border-radius:26px;padding:20px;box-shadow:0 26px 70px #000a}.text{width:100%;min-height:210px;resize:vertical;border:2px solid #355976;border-radius:18px;background:#020812;color:#fff;padding:17px;font:17px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;outline:0}.text:focus{border-color:#4bb8ff;box-shadow:0 0 0 4px #4bb8ff1c}.text:disabled{opacity:.42}.status{margin-top:14px;color:#94abc0;font-size:14px}.live{color:#29e68b;font-weight:900}.paused{color:#ffb447;font-weight:900}.secure{margin-top:16px;color:#647f98;font-size:12px;text-align:center}
</style></head><body><main class="shell"><header class="head"><div class="eyebrow">NEUTRONOS</div><h1>Remote Keyboard</h1><div class="state">Authenticated keyboard session</div></header><section class="panel"><textarea id="text" class="text" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Type or paste here"></textarea><div id="status" class="status"></div><div class="secure">Input works only while the NeutronOS virtual keyboard is visibly open. Closing it pauses remote typing immediately.</div></section></main>
<script>
const box=document.getElementById('text'),status=document.getElementById('status');let previous='',stateTimer=0,sendChain=Promise.resolve();async function state(){try{const r=await fetch('/state',{cache:'no-store'});if(r.status===401){location.reload();return}const j=await r.json();box.disabled=!j.keyboardActive;status.innerHTML=j.keyboardActive?'<span class="live">● LIVE</span> Linked to the active NeutronOS keyboard':'<span class="paused">● PAUSED</span> Reopen the NeutronOS keyboard within 20 seconds to continue';}catch(e){status.textContent='Connection unavailable'}stateTimer=setTimeout(state,700)}function post(payload){sendChain=sendChain.then(async()=>{const r=await fetch('/input',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});if(r.status===401){location.reload();throw new Error('expired')}if(r.status===409)throw new Error('paused');if(!r.ok)throw new Error('send failed')}).catch(()=>{});return sendChain}box.addEventListener('input',()=>{const now=box.value;let p=0;while(p<previous.length&&p<now.length&&previous[p]===now[p])p++;let oldEnd=previous.length-1,newEnd=now.length-1;while(oldEnd>=p&&newEnd>=p&&previous[oldEnd]===now[newEnd]){oldEnd--;newEnd--}const removed=Math.max(0,oldEnd-p+1);const added=now.slice(p,newEnd+1);if(removed)post({op:'backspace',count:removed});if(added){const pieces=added.replace(/\r\n/g,'\n').replace(/\r/g,'\n').split('\n');pieces.forEach((piece,i)=>{if(piece)post({op:'text',text:piece});if(i<pieces.length-1)post({op:'enter'})})}previous=now});box.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();post({op:'enter'});previous=box.value}});state();box.focus();
</script></body></html>)HTML";
}

QByteArray RemoteKeyboardManager::lockedPageHtml() const
{
    return R"HTML(<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>NeutronOS Remote Keyboard</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(circle at 50% -10%,#123927 0,#07111f 42%,#02050a 82%);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#f5faff;display:grid;place-items:center;padding:24px}.panel{width:min(520px,100%);background:#07111ff2;border:1px solid #29e68b;border-radius:28px;padding:34px;box-shadow:0 28px 80px #000b,0 0 46px #29e68b18;text-align:center}.guard{width:76px;height:76px;margin:0 auto 18px;border-radius:50%;display:grid;place-items:center;background:#0a2a1d;border:2px solid #29e68b;color:#29e68b;font-size:38px;font-weight:900}.brand{font-size:12px;letter-spacing:.22em;color:#29e68b;font-weight:900}.panel h1{margin:10px 0 12px;font-size:clamp(27px,7vw,40px);color:#29e68b}.panel p{margin:0 auto;color:#9cb2c9;line-height:1.55;max-width:400px}.pill{display:inline-block;margin-top:24px;padding:10px 16px;border:1px solid #29e68b;border-radius:999px;background:#0a2a1d;color:#29e68b;font-size:12px;font-weight:900;letter-spacing:.08em}
</style></head><body><section class="panel"><div class="guard">✓</div><div class="brand">NEUTRONOS SECURITY GUARD</div><h1>Remote Keyboard In Use</h1><p>One remote device is already authenticated. Additional connections are rejected until the active session closes.</p><div class="pill">ONE DEVICE ONLY</div></section></body></html>)HTML";
}

void RemoteKeyboardManager::handleNewConnection()
{
    while (m_server->hasPendingConnections()) {
        QTcpSocket *socket = m_server->nextPendingConnection();
        m_buffers.insert(socket, QByteArray());
        connect(socket, &QTcpSocket::readyRead, this, [this, socket]() { handleReadyRead(socket); });
        connect(socket, &QTcpSocket::disconnected, this, [this, socket]() {
            m_buffers.remove(socket);
            socket->deleteLater();
        });
    }
}

void RemoteKeyboardManager::handleReadyRead(QTcpSocket *socket)
{
    if (!socket || !m_buffers.contains(socket))
        return;
    QByteArray &buffer = m_buffers[socket];
    buffer.append(socket->readAll());
    if (buffer.size() > kMaximumRequestBytes) {
        sendResponse(socket, 413, "Payload Too Large", "text/plain; charset=utf-8", "Request is too large.");
        return;
    }
    const qsizetype headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd < 0)
        return;

    qsizetype contentLength = 0;
    const QList<QByteArray> headerLines = buffer.left(headerEnd).split('\n');
    for (QByteArray line : headerLines) {
        line = line.trimmed();
        if (line.toLower().startsWith("content-length:")) {
            bool ok = false;
            contentLength = line.mid(line.indexOf(':') + 1).trimmed().toLongLong(&ok);
            if (!ok || contentLength < 0 || contentLength > kMaximumRequestBytes) {
                sendResponse(socket, 400, "Bad Request", "text/plain; charset=utf-8", "Invalid content length.");
                return;
            }
        }
    }
    const qsizetype total = headerEnd + 4 + contentLength;
    if (buffer.size() < total)
        return;

    const QByteArray request = buffer.left(total);
    m_buffers.remove(socket);
    processRequest(socket, request);
}

QString RemoteKeyboardManager::headerValue(const QByteArray &request, const QByteArray &headerName) const
{
    const qsizetype firstLineEnd = request.indexOf("\r\n");
    const qsizetype headerEnd = request.indexOf("\r\n\r\n");
    if (firstLineEnd < 0 || headerEnd < 0)
        return QString();

    const QByteArray wanted = headerName.toLower() + ':';
    const QList<QByteArray> lines = request.mid(firstLineEnd + 2, headerEnd - firstLineEnd - 2).split('\n');
    for (QByteArray line : lines) {
        line = line.trimmed();
        if (line.toLower().startsWith(wanted))
            return QString::fromUtf8(line.mid(line.indexOf(':') + 1).trimmed());
    }
    return QString();
}

QString RemoteKeyboardManager::sessionFromRequest(const QByteArray &request) const
{
    const QString cookie = headerValue(request, QByteArrayLiteral("Cookie"));
    const QStringList parts = cookie.split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        const QString trimmed = part.trimmed();
        if (trimmed.startsWith(QStringLiteral("neutron_keyboard_session=")))
            return trimmed.mid(QStringLiteral("neutron_keyboard_session=").size());
    }
    return QString();
}

bool RemoteKeyboardManager::sessionValid(const QByteArray &request) const
{
    const QString session = sessionFromRequest(request);
    return !session.isEmpty() && m_authenticatedSessions.contains(session);
}

void RemoteKeyboardManager::processRequest(QTcpSocket *socket, const QByteArray &request)
{
    const qsizetype firstLineEnd = request.indexOf("\r\n");
    if (firstLineEnd < 0) {
        sendResponse(socket, 400, "Bad Request", "text/plain; charset=utf-8", "Bad request.");
        return;
    }
    const QList<QByteArray> parts = request.left(firstLineEnd).split(' ');
    if (parts.size() < 2) {
        sendResponse(socket, 400, "Bad Request", "text/plain; charset=utf-8", "Bad request.");
        return;
    }

    const QByteArray method = parts.at(0).toUpper();
    const QUrl parsed = QUrl::fromEncoded(QByteArray("https://neutronos.local") + parts.at(1));
    const QString path = parsed.path();
    const qsizetype bodyStart = request.indexOf("\r\n\r\n") + 4;
    const bool authenticated = sessionValid(request);

    const QList<QByteArray> commonHeaders = {
        "Cache-Control: no-store, max-age=0",
        "Pragma: no-cache",
        "Content-Security-Policy: default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'",
        "X-Frame-Options: DENY",
        "X-Content-Type-Options: nosniff"
    };

    if (method == "GET" && path == QStringLiteral("/")) {
        if (authenticated) {
            sendResponse(socket, 200, "OK", "text/html; charset=utf-8",
                         keyboardPageHtml(), commonHeaders);
        } else if (!m_authenticatedSessions.isEmpty()) {
            sendResponse(socket, 423, "Locked", "text/html; charset=utf-8",
                         lockedPageHtml(), commonHeaders);
        } else {
            sendResponse(socket, 200, "OK", "text/html; charset=utf-8",
                         pairingPageHtml(), commonHeaders);
        }
        return;
    }

    if (method == "POST" && path == QStringLiteral("/pair")) {
        if (!m_authenticatedSessions.isEmpty()) {
            sendResponse(socket, 423, "Locked", "application/json; charset=utf-8",
                         jsonError(QStringLiteral("One remote keyboard is already connected. Additional connections are blocked.")),
                         {"Cache-Control: no-store"});
            return;
        }
        if (!m_keyboardActive) {
            sendResponse(socket, 409, "Conflict", "application/json; charset=utf-8",
                         jsonError(QStringLiteral("The NeutronOS keyboard is closed.")), {"Cache-Control: no-store"});
            return;
        }
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(request.mid(bodyStart), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            sendResponse(socket, 400, "Bad Request", "application/json; charset=utf-8",
                         jsonError(QStringLiteral("Invalid request.")), {"Cache-Control: no-store"});
            return;
        }
        refreshAuthLockout();
        if (authLocked()) {
            const int seconds = authLockSecondsRemaining();
            sendResponse(socket, 429, "Too Many Requests", "application/json; charset=utf-8",
                         jsonError(QStringLiteral("Remote Keyboard pairing is locked. Try again in %1 minute(s).")
                                   .arg(qMax(1, (seconds + 59) / 60))),
                         {"Cache-Control: no-store", QByteArray("Retry-After: ") + QByteArray::number(seconds)});
            return;
        }

        const QString supplied = document.object().value(QStringLiteral("code")).toString().trimmed();
        if (!pairingCodeActive() || supplied != m_pairingCode) {
            recordAuthFailure(socket);
            if (authLocked()) {
                const int seconds = authLockSecondsRemaining();
                sendResponse(socket, 429, "Too Many Requests", "application/json; charset=utf-8",
                             jsonError(QStringLiteral("Too many incorrect codes. Remote Keyboard pairing is locked for 30 minutes.")),
                             {"Cache-Control: no-store", QByteArray("Retry-After: ") + QByteArray::number(seconds)});
            } else {
                const int remaining = qMax(0, authAttemptLimit(socket) - authFailedAttempts(socket));
                sendResponse(socket, 403, "Forbidden", "application/json; charset=utf-8",
                             jsonError(QStringLiteral("Code is incorrect or expired. %1 attempt(s) remain before a 30-minute lockout.")
                                       .arg(remaining)), {"Cache-Control: no-store"});
            }
            return;
        }
        resetAuthFailures();
        const QString session = makeSessionToken();
        m_authenticatedSessions.insert(session);
        clearPairingCode();
        setStatus(QStringLiteral("Remote Keyboard Connected. One-device security guard active."));
        sendResponse(socket, 200, "OK", "application/json; charset=utf-8", jsonOk(), {
            "Cache-Control: no-store",
            QByteArray("Set-Cookie: neutron_keyboard_session=") + session.toUtf8() +
                "; Path=/; Secure; HttpOnly; SameSite=Strict"
        });
        emit stateChanged();
        return;
    }

    if (!authenticated) {
        sendResponse(socket, 401, "Unauthorized", "application/json; charset=utf-8",
                     jsonError(QStringLiteral("Session expired.")), {"Cache-Control: no-store"});
        return;
    }

    if (method == "GET" && path == QStringLiteral("/state")) {
        QJsonObject state;
        state.insert(QStringLiteral("keyboardActive"), m_keyboardActive);
        state.insert(QStringLiteral("graceRemainingMs"),
                     m_graceTimer->isActive() ? m_graceTimer->remainingTime() : 0);
        sendResponse(socket, 200, "OK", "application/json; charset=utf-8",
                     jsonOk(state), {"Cache-Control: no-store"});
        return;
    }

    if (method == "POST" && path == QStringLiteral("/input")) {
        if (!m_keyboardActive) {
            sendResponse(socket, 409, "Conflict", "application/json; charset=utf-8",
                         jsonError(QStringLiteral("NeutronOS keyboard is closed.")), {"Cache-Control: no-store"});
            return;
        }

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(request.mid(bodyStart), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            sendResponse(socket, 400, "Bad Request", "application/json; charset=utf-8",
                         jsonError(QStringLiteral("Invalid input.")), {"Cache-Control: no-store"});
            return;
        }

        const QJsonObject object = document.object();
        const QString op = object.value(QStringLiteral("op")).toString();
        if (op == QStringLiteral("text")) {
            QString text = object.value(QStringLiteral("text")).toString();
            if (text.size() > kMaximumRemoteText)
                text.truncate(kMaximumRemoteText);
            text.remove(QChar::Null);
            if (!text.isEmpty())
                emit textSubmitted(text);
        } else if (op == QStringLiteral("backspace")) {
            const int count = qBound(1, object.value(QStringLiteral("count")).toInt(1), 128);
            emit backspaceRequested(count);
        } else if (op == QStringLiteral("enter")) {
            emit enterRequested();
        } else {
            sendResponse(socket, 400, "Bad Request", "application/json; charset=utf-8",
                         jsonError(QStringLiteral("Unknown input operation.")), {"Cache-Control: no-store"});
            return;
        }

        sendResponse(socket, 200, "OK", "application/json; charset=utf-8",
                     jsonOk(), {"Cache-Control: no-store"});
        return;
    }

    sendResponse(socket, 404, "Not Found", "text/plain; charset=utf-8", "Not found.");
}

void RemoteKeyboardManager::sendResponse(QTcpSocket *socket,
                                         int statusCode,
                                         const QByteArray &statusText,
                                         const QByteArray &contentType,
                                         const QByteArray &body,
                                         const QList<QByteArray> &extraHeaders)
{
    if (!socket)
        return;
    QByteArray response = "HTTP/1.1 " + QByteArray::number(statusCode) + " " + statusText + "\r\n";
    response += "Content-Type: " + contentType + "\r\n";
    response += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
    response += "Connection: close\r\n";
    response += "Strict-Transport-Security: max-age=31536000\r\n";
    for (const QByteArray &header : extraHeaders)
        response += header + "\r\n";
    response += "\r\n";
    response += body;
    socket->write(response);
    socket->disconnectFromHost();
}
