#include "QBitTorrentManager.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkCookieJar>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSaveFile>
#include <QTimer>
#include <QUrlQuery>

namespace {
QString cleanBaseUrl(QString value)
{
    value = value.trimmed();
    if (value.isEmpty())
        value = QStringLiteral("http://127.0.0.1:8080");
    if (!value.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive) &&
        !value.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive))
        value.prepend(QStringLiteral("http://"));
    while (value.endsWith(QLatin1Char('/')))
        value.chop(1);
    return value;
}

QByteArray formData(const QList<QPair<QString, QString>> &values)
{
    QUrlQuery query;
    for (const auto &pair : values)
        query.addQueryItem(pair.first, pair.second);
    return query.query(QUrl::FullyEncoded).toUtf8();
}

bool runCommand(const QString &program, const QStringList &arguments, int timeoutMs = 8000)
{
    QProcess process;
    process.setProgram(program);
    process.setArguments(arguments);
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start();
    if (!process.waitForStarted(1200))
        return false;
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(500);
        return false;
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}
}

QBitTorrentManager::QBitTorrentManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_network(new QNetworkAccessManager(this)),
      m_refreshTimer(new QTimer(this))
{
    m_network->setCookieJar(new QNetworkCookieJar(m_network));
    loadConfiguration();
    m_refreshTimer->setInterval(5000);
    connect(m_refreshTimer, &QTimer::timeout, this, &QBitTorrentManager::refresh);
    // Discover an already-running API without mutating service state merely
    // because NeutronShell started.  Explicit Retry/Setup actions may start a
    // local backend; ordinary shell construction remains side-effect free.
    QTimer::singleShot(350, this, &QBitTorrentManager::refresh);
}

bool QBitTorrentManager::authenticated() const { return m_authenticated; }
bool QBitTorrentManager::loading() const { return m_loading; }
QString QBitTorrentManager::error() const { return m_error; }
QVariantList QBitTorrentManager::torrents() const { return m_torrents; }
QVariantList QBitTorrentManager::torrentFiles() const { return m_torrentFiles; }
QString QBitTorrentManager::baseUrl() const { return m_baseUrl.toString(); }
QString QBitTorrentManager::configuredUsername() const { return m_username; }

QString QBitTorrentManager::statePath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/qbittorrent/settings.json"));
}

QString QBitTorrentManager::logPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/qbittorrent/last-backend.log"));
}

void QBitTorrentManager::writeLog(const QString &message) const
{
    QDir().mkpath(QFileInfo(logPath()).absolutePath());
    QFile file(logPath());
    if (file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        file.write(QDateTime::currentDateTime().toString(Qt::ISODateWithMs).toUtf8());
        file.write("  ");
        file.write(message.toUtf8());
        file.write("\n");
    }
}

void QBitTorrentManager::loadConfiguration()
{
    QString url = qEnvironmentVariable("NEUTRONOS_QBIT_URL");
    m_username = qEnvironmentVariable("NEUTRONOS_QBIT_USERNAME");
    m_password = qEnvironmentVariable("NEUTRONOS_QBIT_PASSWORD");

    QFile file(statePath());
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
        if (document.isObject()) {
            const QJsonObject object = document.object();
            if (url.trimmed().isEmpty())
                url = object.value(QStringLiteral("url")).toString();
            if (m_username.isEmpty())
                m_username = object.value(QStringLiteral("username")).toString();
            if (m_password.isEmpty())
                m_password = object.value(QStringLiteral("password")).toString();
        }
    }

    m_baseUrl = QUrl(cleanBaseUrl(url));
    emit configurationChanged();
}

void QBitTorrentManager::startLocalBackend()
{
    if (probeApi())
        return;

    const QList<QPair<QString, QStringList>> commands = {
        {QStringLiteral("systemctl"), {QStringLiteral("start"), QStringLiteral("qbittorrent-nox.service")}},
        {QStringLiteral("systemctl"), {QStringLiteral("start"), QStringLiteral("qbittorrent.service")}},
        {QStringLiteral("docker"), {QStringLiteral("start"), QStringLiteral("qbittorrent")}}
    };
    for (const auto &command : commands) {
        if (runCommand(command.first, command.second)) {
            writeLog(QStringLiteral("Started qBittorrent with %1 %2")
                         .arg(command.first).arg(command.second.join(QLatin1Char(' '))));
            break;
        }
    }
}

QBitTorrentManager::HttpResult QBitTorrentManager::request(const QByteArray &method,
                                                           const QString &path,
                                                           const QByteArray &body,
                                                           const QByteArray &contentType)
{
    HttpResult result;
    QUrl url(m_baseUrl.toString() + path);
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "NeutronOS-qBittorrent/1.0");
    request.setRawHeader("Referer", m_baseUrl.toString().toUtf8() + "/");
    if (!contentType.isEmpty())
        request.setHeader(QNetworkRequest::ContentTypeHeader, QString::fromLatin1(contentType));

    QNetworkReply *reply = nullptr;
    if (method == "POST")
        reply = m_network->post(request, body);
    else
        reply = m_network->get(request);

    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    connect(&timeout, &QTimer::timeout, &loop, [&]() {
        result.error = QStringLiteral("qBittorrent Web API timed out.");
        if (reply)
            reply->abort();
        loop.quit();
    });
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    timeout.start(6000);
    loop.exec();
    timeout.stop();

    result.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    result.body = reply->readAll();
    if (result.error.isEmpty() && reply->error() != QNetworkReply::NoError && result.status == 0)
        result.error = reply->errorString();
    reply->deleteLater();
    return result;
}

bool QBitTorrentManager::probeApi()
{
    const HttpResult result = request("GET", QStringLiteral("/api/v2/app/version"));
    return result.status == 200 && !result.body.trimmed().isEmpty();
}

bool QBitTorrentManager::login(const QString &username, const QString &password)
{
    if (username.isEmpty() || password.isEmpty())
        return false;
    const HttpResult result = request(
        "POST", QStringLiteral("/api/v2/auth/login"),
        formData({{QStringLiteral("username"), username},
                  {QStringLiteral("password"), password}}),
        "application/x-www-form-urlencoded");
    const QByteArray response = result.body.trimmed();
    return (result.status == 200 && response.startsWith("Ok")) ||
           (result.status == 204 && response.isEmpty());
}

bool QBitTorrentManager::ensureAuthenticated()
{
    if (probeApi()) {
        setAuthenticated(true);
        return true;
    }

    QList<QPair<QString, QString>> credentials;
    if (!m_username.isEmpty() && !m_password.isEmpty())
        credentials.append({m_username, m_password});
    credentials.append({QStringLiteral("admin"), QStringLiteral("adminadmin")});

    for (const auto &credential : credentials) {
        if (login(credential.first, credential.second) && probeApi()) {
            setAuthenticated(true);
            return true;
        }
    }

    setAuthenticated(false);
    return false;
}

void QBitTorrentManager::retryConnection()
{
    setLoading(true);
    setError(QString());
    startLocalBackend();
    if (!ensureAuthenticated()) {
        setLoading(false);
        setError(QStringLiteral("Could not authenticate with qBittorrent Web API at %1. Enable localhost authentication bypass or save WebUI credentials in state/qbittorrent/settings.json. Log: %2")
                     .arg(m_baseUrl.toString()).arg(logPath()));
        writeLog(m_error);
        return;
    }
    m_refreshTimer->start();
    setLoading(false);
    refresh();
}

void QBitTorrentManager::refresh()
{
    if (m_loading)
        return;
    setLoading(true);
    if (!ensureAuthenticated()) {
        setLoading(false);
        setError(QStringLiteral("qBittorrent Web API is unavailable or authentication failed. Retry after checking the service. Log: %1").arg(logPath()));
        return;
    }

    const HttpResult result = request("GET", QStringLiteral("/api/v2/torrents/info?filter=all"));
    if (result.status != 200) {
        setLoading(false);
        setError(QStringLiteral("qBittorrent returned HTTP %1 while loading torrents. Log: %2")
                     .arg(result.status).arg(logPath()));
        writeLog(QStringLiteral("Torrent refresh failed: HTTP %1 %2")
                     .arg(result.status).arg(QString::fromUtf8(result.body.left(400))));
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(result.body);
    if (!document.isArray()) {
        setLoading(false);
        setError(QStringLiteral("qBittorrent returned invalid torrent data. Log: %1").arg(logPath()));
        return;
    }

    QVariantList next;
    const QJsonArray array = document.array();
    next.reserve(array.size());
    for (const QJsonValue &value : array)
        next.append(value.toObject().toVariantMap());
    m_torrents = next;
    emit torrentsChanged();
    setError(QString());
    setLoading(false);
}

bool QBitTorrentManager::postTorrentCommand(const QString &endpoint,
                                            const QString &hash,
                                            const QList<QPair<QString, QString>> &extra)
{
    if (hash.trimmed().isEmpty())
        return false;
    QList<QPair<QString, QString>> values{{QStringLiteral("hashes"), hash}};
    values += extra;
    const HttpResult result = request("POST", endpoint, formData(values),
                                      "application/x-www-form-urlencoded");
    if (result.status == 200) {
        QTimer::singleShot(250, this, &QBitTorrentManager::refresh);
        return true;
    }
    setError(QStringLiteral("qBittorrent command failed with HTTP %1.").arg(result.status));
    writeLog(QStringLiteral("Command %1 failed: HTTP %2 %3")
                 .arg(endpoint).arg(result.status).arg(QString::fromUtf8(result.body.left(300))));
    return false;
}


bool QBitTorrentManager::saveConfiguration(const QString &url, const QString &username, const QString &password)
{
    const QString cleanedUrl = cleanBaseUrl(url);
    const QString cleanedUsername = username.trimmed();
    if (cleanedUrl.isEmpty() || cleanedUsername.isEmpty() || password.isEmpty()) {
        setError(QStringLiteral("URL, username, and password are required."));
        return false;
    }

    QDir().mkpath(QFileInfo(statePath()).absolutePath());
    QSaveFile file(statePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        setError(QStringLiteral("Could not save qBittorrent API settings."));
        return false;
    }

    QJsonObject object;
    object.insert(QStringLiteral("url"), cleanedUrl);
    object.insert(QStringLiteral("username"), cleanedUsername);
    object.insert(QStringLiteral("password"), password);
    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setError(QStringLiteral("Could not commit qBittorrent API settings."));
        return false;
    }
    QFile::setPermissions(statePath(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    m_baseUrl = QUrl(cleanedUrl);
    m_username = cleanedUsername;
    m_password = password;
    m_network->setCookieJar(new QNetworkCookieJar(m_network));
    setAuthenticated(false);
    setError(QString());
    emit configurationChanged();
    writeLog(QStringLiteral("Saved qBittorrent Web API configuration for %1").arg(cleanedUrl));
    return true;
}

bool QBitTorrentManager::saveAndTestConfiguration(const QString &url, const QString &username, const QString &password)
{
    if (!saveConfiguration(url, username, password))
        return false;
    retryConnection();
    return m_authenticated;
}

void QBitTorrentManager::startTorrent(const QString &hash)
{
    if (!postTorrentCommand(QStringLiteral("/api/v2/torrents/start"), hash))
        postTorrentCommand(QStringLiteral("/api/v2/torrents/resume"), hash);
}
void QBitTorrentManager::resumeTorrent(const QString &hash) { startTorrent(hash); }
void QBitTorrentManager::pauseTorrent(const QString &hash)
{
    if (!postTorrentCommand(QStringLiteral("/api/v2/torrents/stop"), hash))
        postTorrentCommand(QStringLiteral("/api/v2/torrents/pause"), hash);
}
void QBitTorrentManager::restartTorrent(const QString &hash)
{
    pauseTorrent(hash);
    QTimer::singleShot(500, this, [this, hash]() { startTorrent(hash); });
}
void QBitTorrentManager::reannounceTorrent(const QString &hash)
{
    postTorrentCommand(QStringLiteral("/api/v2/torrents/reannounce"), hash);
}
void QBitTorrentManager::recheckTorrent(const QString &hash)
{
    postTorrentCommand(QStringLiteral("/api/v2/torrents/recheck"), hash);
}
void QBitTorrentManager::forceStartTorrent(const QString &hash, bool enabled)
{
    postTorrentCommand(QStringLiteral("/api/v2/torrents/setForceStart"), hash,
                       {{QStringLiteral("value"), enabled ? QStringLiteral("true") : QStringLiteral("false")}});
}
void QBitTorrentManager::deleteTorrent(const QString &hash, bool deleteFiles)
{
    postTorrentCommand(QStringLiteral("/api/v2/torrents/delete"), hash,
                       {{QStringLiteral("deleteFiles"), deleteFiles ? QStringLiteral("true") : QStringLiteral("false")}});
}

void QBitTorrentManager::loadTorrentFiles(const QString &hash)
{
    const HttpResult result = request("GET", QStringLiteral("/api/v2/torrents/files?hash=%1")
                                              .arg(QString::fromLatin1(QUrl::toPercentEncoding(hash))));
    if (result.status != 200) {
        setError(QStringLiteral("Could not load torrent files (HTTP %1).").arg(result.status));
        return;
    }
    const QJsonDocument document = QJsonDocument::fromJson(result.body);
    if (!document.isArray())
        return;
    QVariantList next;
    for (const QJsonValue &value : document.array())
        next.append(value.toObject().toVariantMap());
    m_torrentFiles = next;
    emit torrentFilesChanged();
}

void QBitTorrentManager::setTorrentFileWanted(const QString &hash, int fileIndex, bool wanted)
{
    postTorrentCommand(QStringLiteral("/api/v2/torrents/filePrio"), hash,
                       {{QStringLiteral("id"), QString::number(fileIndex)},
                        {QStringLiteral("priority"), wanted ? QStringLiteral("1") : QStringLiteral("0")}});
    QTimer::singleShot(300, this, [this, hash]() { loadTorrentFiles(hash); });
}

void QBitTorrentManager::setAuthenticated(bool value)
{
    if (m_authenticated == value)
        return;
    m_authenticated = value;
    emit authenticatedChanged();
}
void QBitTorrentManager::setLoading(bool value)
{
    if (m_loading == value)
        return;
    m_loading = value;
    emit loadingChanged();
}
void QBitTorrentManager::setError(const QString &value)
{
    if (m_error == value)
        return;
    m_error = value;
    emit errorChanged();
}
