#include "JellyfinManager.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QHostInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QSslError>
#include <QSysInfo>
#include <QTimer>
#include <QUrlQuery>
#include <QUuid>

#include <sodium.h>

#include <algorithm>
#include <functional>
#include <utility>

#ifdef Q_OS_UNIX
#include <sys/stat.h>
#endif

namespace {
constexpr auto kClientName = "NeutronOS Jellyfin";
constexpr auto kClientVersion = "68J2A";
constexpr auto kSecretMagic = "NJF1";
constexpr int kRequestTimeoutMs = 30000;

QString cleanServerUrl(const QUrl &url)
{
    QString value = url.adjusted(QUrl::RemoveQuery | QUrl::RemoveFragment |
                                 QUrl::StripTrailingSlash).toString();
    while (value.endsWith(QLatin1Char('/')))
        value.chop(1);
    return value;
}

QString errorFromDocument(const QJsonDocument &document, const QByteArray &fallback)
{
    if (document.isObject()) {
        const QJsonObject object = document.object();
        const QStringList keys = {QStringLiteral("Message"), QStringLiteral("message"),
                                  QStringLiteral("Error"), QStringLiteral("error")};
        for (const QString &key : keys) {
            const QString text = object.value(key).toString().trimmed();
            if (!text.isEmpty())
                return text;
        }
    }
    const QString text = QString::fromUtf8(fallback).trimmed();
    return text.left(600);
}

QVariantList documentList(const QJsonDocument &document)
{
    if (document.isArray())
        return document.array().toVariantList();
    if (document.isObject()) {
        const QJsonObject object = document.object();
        const QStringList keys = {QStringLiteral("Items"), QStringLiteral("items"),
                                  QStringLiteral("Results"), QStringLiteral("results")};
        for (const QString &key : keys) {
            if (object.value(key).isArray())
                return object.value(key).toArray().toVariantList();
        }
    }
    return {};
}

QString deviceIdentifier()
{
    const QByteArray machineId = QSysInfo::machineUniqueId();
    if (!machineId.isEmpty())
        return QString::fromLatin1(QCryptographicHash::hash(machineId, QCryptographicHash::Sha256).toHex().left(32));
    return QString::fromLatin1(QCryptographicHash::hash(
        (QHostInfo::localHostName() + QStringLiteral("-neutronos-jellyfin")).toUtf8(),
        QCryptographicHash::Sha256).toHex().left(32));
}
}

JellyfinManager::JellyfinManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_stateRoot(QStringLiteral("/var/lib/neutronos/apps/jellyfin")),
      m_network(new QNetworkAccessManager(this))
{
    if (sodium_init() < 0)
        setMessage(QStringLiteral("Secure credential storage could not initialize."), true);

    QDir().mkpath(m_stateRoot);
#ifdef Q_OS_UNIX
    ::chmod(QFile::encodeName(m_stateRoot).constData(), 0700);
#endif
    m_hasSavedConnection = QFileInfo::exists(connectionPath()) && QFileInfo::exists(keyPath());
}

JellyfinManager::~JellyfinManager() = default;

bool JellyfinManager::connected() const { return m_connected; }
bool JellyfinManager::busy() const { return m_pendingRequests > 0; }
bool JellyfinManager::hasSavedConnection() const { return m_hasSavedConnection; }
QString JellyfinManager::serverUrl() const { return cleanServerUrl(m_baseUrl); }
QString JellyfinManager::serverName() const { return m_serverName; }
QString JellyfinManager::serverVersion() const { return m_serverVersion; }
QString JellyfinManager::operatingSystem() const { return m_operatingSystem; }
QString JellyfinManager::lastError() const { return m_lastError; }
QString JellyfinManager::lastMessage() const { return m_lastMessage; }
QVariantList JellyfinManager::users() const { return m_users; }
QVariantList JellyfinManager::devices() const { return m_devices; }
QVariantList JellyfinManager::sessions() const { return m_sessions; }
QVariantList JellyfinManager::libraries() const { return m_libraries; }
QVariantList JellyfinManager::tasks() const { return m_tasks; }
QVariantList JellyfinManager::searchResults() const { return m_searchResults; }
QVariantMap JellyfinManager::selectedItem() const { return m_selectedItem; }
QVariantMap JellyfinManager::serverConfiguration() const { return m_serverConfiguration; }

void JellyfinManager::setBusyDelta(int delta)
{
    const bool wasBusy = busy();
    m_pendingRequests = std::max(0, m_pendingRequests + delta);
    if (wasBusy != busy())
        emit busyChanged();
}

void JellyfinManager::setMessage(const QString &message, bool error)
{
    if (error) {
        m_lastError = message;
        m_lastMessage.clear();
    } else {
        m_lastMessage = message;
        m_lastError.clear();
    }
    emit messageChanged();
}

void JellyfinManager::clearMessages()
{
    if (m_lastError.isEmpty() && m_lastMessage.isEmpty())
        return;
    m_lastError.clear();
    m_lastMessage.clear();
    emit messageChanged();
}

void JellyfinManager::setConnected(bool value)
{
    if (m_connected == value)
        return;
    m_connected = value;
    emit connectionChanged();
}

bool JellyfinManager::validateBaseUrl(const QString &value, QUrl *normalized, QString *error) const
{
    QString clean = value.trimmed();
    if (!clean.contains(QStringLiteral("://")))
        clean.prepend(QStringLiteral("http://"));
    QUrl url(clean, QUrl::StrictMode);
    if (!url.isValid() || url.host().isEmpty()) {
        if (error) *error = QStringLiteral("Enter a valid Jellyfin server address.");
        return false;
    }
    const QString scheme = url.scheme().toLower();
    if (scheme != QStringLiteral("http") && scheme != QStringLiteral("https")) {
        if (error) *error = QStringLiteral("Only HTTP and HTTPS Jellyfin addresses are allowed.");
        return false;
    }
    if (!url.userInfo().isEmpty()) {
        if (error) *error = QStringLiteral("Do not place credentials inside the server URL.");
        return false;
    }
    url.setQuery(QString());
    url.setFragment(QString());
    QString path = url.path();
    while (path.endsWith(QLatin1Char('/')))
        path.chop(1);
    url.setPath(path);
    if (normalized) *normalized = url;
    return true;
}

QNetworkReply *JellyfinManager::request(const QByteArray &method, const QString &path,
                                        const QVariantMap &query, const QVariant &body,
                                        const ReplyHandler &handler)
{
    if (!m_baseUrl.isValid() || m_baseUrl.host().isEmpty()) {
        handler(false, 0, QJsonDocument(), QStringLiteral("Jellyfin is not connected."));
        return nullptr;
    }

    QUrl url = m_baseUrl;
    QString joined = url.path();
    if (!joined.endsWith(QLatin1Char('/')))
        joined.append(QLatin1Char('/'));
    QString relative = path;
    while (relative.startsWith(QLatin1Char('/')))
        relative.remove(0, 1);
    joined.append(relative);
    url.setPath(joined);
    QUrlQuery urlQuery;
    for (auto it = query.cbegin(); it != query.cend(); ++it)
        urlQuery.addQueryItem(it.key(), it.value().toString());
    url.setQuery(urlQuery);

    QNetworkRequest networkRequest(url);
    networkRequest.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    networkRequest.setRawHeader("Accept", "application/json");
    networkRequest.setRawHeader("X-Emby-Token", m_apiKey.toUtf8());
    const QString authorization = QStringLiteral(
        "MediaBrowser Client=\"%1\", Device=\"NeutronOS Gemini\", DeviceId=\"%2\", Version=\"%3\", Token=\"%4\"")
        .arg(QString::fromLatin1(kClientName), deviceIdentifier(),
             QString::fromLatin1(kClientVersion), m_apiKey);
    networkRequest.setRawHeader("Authorization", authorization.toUtf8());

    QByteArray payload;
    if (body.isValid() && !body.isNull())
        payload = QJsonDocument::fromVariant(body).toJson(QJsonDocument::Compact);

    QNetworkReply *reply = nullptr;
    if (method == "GET")
        reply = m_network->get(networkRequest);
    else if (method == "POST")
        reply = m_network->post(networkRequest, payload);
    else if (method == "DELETE")
        reply = m_network->deleteResource(networkRequest);
    else
        reply = m_network->sendCustomRequest(networkRequest, method, payload);

    if (!reply) {
        handler(false, 0, QJsonDocument(), QStringLiteral("Jellyfin request could not be started."));
        return nullptr;
    }

    if (m_allowSelfSigned) {
        connect(reply, &QNetworkReply::sslErrors, reply,
                [reply](const QList<QSslError> &) { reply->ignoreSslErrors(); });
    }

    setBusyDelta(1);
    QTimer::singleShot(kRequestTimeoutMs, reply, [reply]() {
        if (reply->isRunning())
            reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, handler]() {
        const QByteArray raw = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        const bool httpOk = status >= 200 && status < 300;
        const bool networkOk = reply->error() == QNetworkReply::NoError;
        QString error;
        if (!networkOk || !httpOk) {
            error = errorFromDocument(document, raw);
            if (error.isEmpty())
                error = reply->errorString();
            if (status == 401 || status == 403)
                error = QStringLiteral("The Jellyfin API key was rejected or lacks administrator access.");
            else if (status > 0)
                error = QStringLiteral("Jellyfin returned HTTP %1: %2").arg(status).arg(error);
        }
        reply->deleteLater();
        setBusyDelta(-1);
        handler(networkOk && httpOk, status, document, error);
    });
    return reply;
}

void JellyfinManager::finishOperation(const QString &operation, bool success, const QString &message)
{
    setMessage(message, !success);
    emit operationFinished(operation, success, message);
}

void JellyfinManager::connectToServer(const QString &url, const QString &apiKey, bool allowSelfSigned)
{
    clearMessages();
    QUrl normalized;
    QString validationError;
    if (!validateBaseUrl(url, &normalized, &validationError)) {
        finishOperation(QStringLiteral("connect"), false, validationError);
        return;
    }
    if (apiKey.trimmed().isEmpty()) {
        finishOperation(QStringLiteral("connect"), false, QStringLiteral("Enter a Jellyfin administrator API key."));
        return;
    }
    m_baseUrl = normalized;
    m_apiKey = apiKey.trimmed();
    m_allowSelfSigned = allowSelfSigned;
    setConnected(false);
    testCurrentConnection(true);
}

void JellyfinManager::connectSaved()
{
    QString error;
    if (!loadConnectionSecret(&error)) {
        finishOperation(QStringLiteral("connect"), false,
                        error.isEmpty() ? QStringLiteral("No saved Jellyfin connection was found.") : error);
        return;
    }
    testCurrentConnection(false);
}

void JellyfinManager::disconnectServer()
{
    setConnected(false);
    m_apiKey.clear();
    m_users.clear(); m_devices.clear(); m_sessions.clear(); m_libraries.clear();
    m_tasks.clear(); m_searchResults.clear(); m_selectedItem.clear(); m_serverConfiguration.clear();
    emit usersChanged(); emit devicesChanged(); emit sessionsChanged(); emit librariesChanged();
    emit tasksChanged(); emit searchResultsChanged(); emit selectedItemChanged(); emit serverConfigurationChanged();
    setMessage(QStringLiteral("Disconnected from Jellyfin."));
}

void JellyfinManager::forgetConnection()
{
    disconnectServer();
    QFile::remove(connectionPath());
    QFile::remove(keyPath());
    m_baseUrl = QUrl();
    m_hasSavedConnection = false;
    emit connectionChanged();
    setMessage(QStringLiteral("Saved Jellyfin connection removed."));
}

void JellyfinManager::testCurrentConnection(bool saveOnSuccess)
{
    request("GET", QStringLiteral("System/Info"), {}, {},
            [this, saveOnSuccess](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok || !document.isObject()) {
            setConnected(false);
            finishOperation(QStringLiteral("connect"), false,
                            error.isEmpty() ? QStringLiteral("Jellyfin did not return valid server information.") : error);
            return;
        }
        const QVariantMap info = document.object().toVariantMap();
        m_serverName = info.value(QStringLiteral("ServerName")).toString();
        m_serverVersion = info.value(QStringLiteral("Version")).toString();
        m_operatingSystem = info.value(QStringLiteral("OperatingSystem")).toString();
        emit serverInfoChanged();
        setConnected(true);
        if (saveOnSuccess && !saveConnectionSecret()) {
            finishOperation(QStringLiteral("connect"), false,
                            QStringLiteral("Connected, but the API key could not be stored securely."));
            return;
        }
        finishOperation(QStringLiteral("connect"), true,
                        QStringLiteral("Connected to %1.").arg(m_serverName.isEmpty() ? QStringLiteral("Jellyfin") : m_serverName));
        refreshDashboard();
    });
}

void JellyfinManager::refreshDashboard()
{
    if (!m_connected) {
        finishOperation(QStringLiteral("refresh"), false, QStringLiteral("Connect to Jellyfin first."));
        return;
    }
    loadServerInfo();
    loadUsers();
    loadDevices();
    loadLibraries();
    loadTasks();
    loadServerConfiguration();
}

void JellyfinManager::loadServerInfo()
{
    request("GET", QStringLiteral("System/Info"), {}, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok || !document.isObject()) {
            setMessage(error, true);
            return;
        }
        const QVariantMap info = document.object().toVariantMap();
        m_serverName = info.value(QStringLiteral("ServerName")).toString();
        m_serverVersion = info.value(QStringLiteral("Version")).toString();
        m_operatingSystem = info.value(QStringLiteral("OperatingSystem")).toString();
        emit serverInfoChanged();
    });
}

void JellyfinManager::loadUsers()
{
    request("GET", QStringLiteral("Users"), {}, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok) { setMessage(error, true); return; }
        m_users = documentList(document);
        emit usersChanged();
    });
}

QVariantMap JellyfinManager::userById(const QString &userId) const
{
    for (const QVariant &entry : m_users) {
        const QVariantMap user = entry.toMap();
        if (user.value(QStringLiteral("Id")).toString() == userId)
            return user;
    }
    return {};
}

QVariantMap JellyfinManager::mergeMaps(const QVariantMap &base, const QVariantMap &changes) const
{
    QVariantMap merged = base;
    for (auto it = changes.cbegin(); it != changes.cend(); ++it)
        merged.insert(it.key(), it.value());
    return merged;
}

void JellyfinManager::createUser(const QString &name, const QString &password,
                                  bool administrator, bool disabled, bool hidden)
{
    const QString cleanName = name.trimmed();
    if (cleanName.isEmpty()) {
        finishOperation(QStringLiteral("create-user"), false, QStringLiteral("User name cannot be empty."));
        return;
    }
    const QVariantMap body{{QStringLiteral("Name"), cleanName},
                           {QStringLiteral("Password"), password}};
    request("POST", QStringLiteral("Users/New"), {}, body,
            [this, cleanName, administrator, disabled, hidden]
            (bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok) {
            finishOperation(QStringLiteral("create-user"), false, error);
            return;
        }

        const QVariantMap created = document.isObject()
            ? document.object().toVariantMap() : QVariantMap();
        const QString userId = created.value(QStringLiteral("Id")).toString();
        if (userId.isEmpty()) {
            finishOperation(QStringLiteral("create-user"), true,
                            QStringLiteral("Created Jellyfin user %1. Reloading users to verify policy settings.").arg(cleanName));
            loadUsers();
            return;
        }

        QVariantMap policy = created.value(QStringLiteral("Policy")).toMap();
        policy.insert(QStringLiteral("IsAdministrator"), administrator);
        policy.insert(QStringLiteral("IsDisabled"), disabled);
        policy.insert(QStringLiteral("IsHidden"), hidden);
        request("POST", QStringLiteral("Users/%1/Policy").arg(userId), {}, policy,
                [this, cleanName](bool policyOk, int, const QJsonDocument &, const QString &policyError) {
            finishOperation(QStringLiteral("create-user"), policyOk,
                            policyOk ? QStringLiteral("Created and configured Jellyfin user %1.").arg(cleanName)
                                     : QStringLiteral("The user was created, but its policy could not be applied: %1").arg(policyError));
            loadUsers();
        });
    });
}

void JellyfinManager::updateUser(const QString &userId, const QString &name,
                                 const QString &password, bool administrator,
                                 bool disabled, bool hidden)
{
    QVariantMap user = userById(userId);
    if (user.isEmpty()) {
        finishOperation(QStringLiteral("update-user"), false, QStringLiteral("The selected user is no longer available."));
        return;
    }
    user.insert(QStringLiteral("Name"), name.trimmed());
    QVariantMap policy = user.value(QStringLiteral("Policy")).toMap();
    policy.insert(QStringLiteral("IsAdministrator"), administrator);
    policy.insert(QStringLiteral("IsDisabled"), disabled);
    policy.insert(QStringLiteral("IsHidden"), hidden);

    request("POST", QStringLiteral("Users/%1").arg(userId), {}, user,
            [this, userId, password, policy](bool ok, int, const QJsonDocument &, const QString &error) {
        if (!ok) { finishOperation(QStringLiteral("update-user"), false, error); return; }
        request("POST", QStringLiteral("Users/%1/Policy").arg(userId), {}, policy,
                [this, userId, password](bool policyOk, int, const QJsonDocument &, const QString &policyError) {
            if (!policyOk) { finishOperation(QStringLiteral("update-user"), false, policyError); return; }
            if (password.isEmpty()) {
                finishOperation(QStringLiteral("update-user"), true, QStringLiteral("Jellyfin user updated."));
                loadUsers();
                return;
            }
            const QVariantMap passwordBody{{QStringLiteral("CurrentPw"), QString()},
                                           {QStringLiteral("NewPw"), password},
                                           {QStringLiteral("ResetPassword"), false}};
            request("POST", QStringLiteral("Users/%1/Password").arg(userId), {}, passwordBody,
                    [this](bool passwordOk, int, const QJsonDocument &, const QString &passwordError) {
                finishOperation(QStringLiteral("update-user"), passwordOk,
                                passwordOk ? QStringLiteral("Jellyfin user and password updated.") : passwordError);
                if (passwordOk) loadUsers();
            });
        });
    });
}

void JellyfinManager::deleteUser(const QString &userId)
{
    request("DELETE", QStringLiteral("Users/%1").arg(userId), {}, {},
            [this](bool ok, int, const QJsonDocument &, const QString &error) {
        finishOperation(QStringLiteral("delete-user"), ok,
                        ok ? QStringLiteral("Jellyfin user deleted.") : error);
        if (ok) loadUsers();
    });
}

void JellyfinManager::loadDevices()
{
    request("GET", QStringLiteral("Devices"), {{QStringLiteral("Limit"), 200}}, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok) { setMessage(error, true); return; }
        m_devices = documentList(document);
        emit devicesChanged();
    });
    request("GET", QStringLiteral("Sessions"), {}, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok) { setMessage(error, true); return; }
        m_sessions = documentList(document);
        emit sessionsChanged();
    });
}

void JellyfinManager::deleteDevice(const QString &deviceId)
{
    request("DELETE", QStringLiteral("Devices"), {{QStringLiteral("Id"), deviceId}}, {},
            [this](bool ok, int, const QJsonDocument &, const QString &error) {
        finishOperation(QStringLiteral("delete-device"), ok,
                        ok ? QStringLiteral("Device access record removed.") : error);
        if (ok) loadDevices();
    });
}

void JellyfinManager::logoutSession(const QString &sessionId)
{
    request("POST", QStringLiteral("Sessions/Logout"), {{QStringLiteral("Id"), sessionId}}, {},
            [this](bool ok, int, const QJsonDocument &, const QString &error) {
        finishOperation(QStringLiteral("logout-session"), ok,
                        ok ? QStringLiteral("The Jellyfin session was logged out.") : error);
        if (ok) loadDevices();
    });
}

void JellyfinManager::loadLibraries()
{
    request("GET", QStringLiteral("Library/VirtualFolders"), {}, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok) { setMessage(error, true); return; }
        m_libraries = documentList(document);
        emit librariesChanged();
    });
}

void JellyfinManager::scanAllLibraries()
{
    request("POST", QStringLiteral("Library/Refresh"), {}, {},
            [this](bool ok, int, const QJsonDocument &, const QString &error) {
        finishOperation(QStringLiteral("scan-library"), ok,
                        ok ? QStringLiteral("Jellyfin library scan started.") : error);
        if (ok) loadTasks();
    });
}

void JellyfinManager::scanLibrary(const QString &itemId)
{
    if (itemId.trimmed().isEmpty()) { scanAllLibraries(); return; }
    const QVariantMap query{{QStringLiteral("Recursive"), QStringLiteral("true")},
                            {QStringLiteral("MetadataRefreshMode"), QStringLiteral("Default")},
                            {QStringLiteral("ImageRefreshMode"), QStringLiteral("Default")},
                            {QStringLiteral("ReplaceAllMetadata"), QStringLiteral("false")},
                            {QStringLiteral("ReplaceAllImages"), QStringLiteral("false")}};
    request("POST", QStringLiteral("Items/%1/Refresh").arg(itemId), query, {},
            [this](bool ok, int, const QJsonDocument &, const QString &error) {
        finishOperation(QStringLiteral("scan-library"), ok,
                        ok ? QStringLiteral("Selected library scan started.") : error);
        if (ok) loadTasks();
    });
}

void JellyfinManager::loadTasks()
{
    request("GET", QStringLiteral("ScheduledTasks"), {}, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok) { setMessage(error, true); return; }
        m_tasks = documentList(document);
        emit tasksChanged();
    });
}

void JellyfinManager::startTask(const QString &taskId)
{
    request("POST", QStringLiteral("ScheduledTasks/Running/%1").arg(taskId), {}, {},
            [this](bool ok, int, const QJsonDocument &, const QString &error) {
        finishOperation(QStringLiteral("start-task"), ok,
                        ok ? QStringLiteral("Jellyfin task started.") : error);
        if (ok) loadTasks();
    });
}

void JellyfinManager::searchMedia(const QString &term)
{
    if (term.trimmed().isEmpty()) {
        m_searchResults.clear();
        emit searchResultsChanged();
        return;
    }
    const QVariantMap query{{QStringLiteral("SearchTerm"), term.trimmed()},
                            {QStringLiteral("Recursive"), QStringLiteral("true")},
                            {QStringLiteral("IncludeItemTypes"), QStringLiteral("Movie,Series,Season,Episode,Audio,MusicAlbum,MusicArtist,BoxSet")},
                            {QStringLiteral("Fields"), QStringLiteral("Overview,Genres,Tags,ProviderIds,Path,PremiereDate,ProductionYear,OfficialRating,CommunityRating")},
                            {QStringLiteral("Limit"), 100},
                            {QStringLiteral("SortBy"), QStringLiteral("SortName")}};
    request("GET", QStringLiteral("Items"), query, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok) { finishOperation(QStringLiteral("search-media"), false, error); return; }
        m_searchResults = documentList(document);
        emit searchResultsChanged();
        finishOperation(QStringLiteral("search-media"), true,
                        QStringLiteral("Found %1 matching media items.").arg(m_searchResults.size()));
    });
}

void JellyfinManager::loadItem(const QString &itemId)
{
    request("GET", QStringLiteral("Items/%1").arg(itemId), {}, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok || !document.isObject()) {
            finishOperation(QStringLiteral("load-item"), false,
                            error.isEmpty() ? QStringLiteral("The media item could not be loaded.") : error);
            return;
        }
        m_selectedItem = document.object().toVariantMap();
        emit selectedItemChanged();
        finishOperation(QStringLiteral("load-item"), true, QStringLiteral("Metadata loaded."));
    });
}

void JellyfinManager::saveItemMetadata(const QString &itemId, const QVariantMap &changes)
{
    if (itemId.isEmpty() || m_selectedItem.value(QStringLiteral("Id")).toString() != itemId) {
        finishOperation(QStringLiteral("save-metadata"), false, QStringLiteral("Load the item before saving metadata."));
        return;
    }
    QVariantMap body = mergeMaps(m_selectedItem, changes);
    request("POST", QStringLiteral("Items/%1").arg(itemId), {}, body,
            [this, itemId, body](bool ok, int, const QJsonDocument &, const QString &error) {
        if (ok) {
            m_selectedItem = body;
            emit selectedItemChanged();
        }
        finishOperation(QStringLiteral("save-metadata"), ok,
                        ok ? QStringLiteral("Jellyfin metadata saved.") : error);
        if (ok) loadItem(itemId);
    });
}

void JellyfinManager::refreshItemMetadata(const QString &itemId, bool recursive)
{
    const QVariantMap query{{QStringLiteral("Recursive"), recursive ? QStringLiteral("true") : QStringLiteral("false")},
                            {QStringLiteral("MetadataRefreshMode"), QStringLiteral("FullRefresh")},
                            {QStringLiteral("ImageRefreshMode"), QStringLiteral("FullRefresh")},
                            {QStringLiteral("ReplaceAllMetadata"), QStringLiteral("false")},
                            {QStringLiteral("ReplaceAllImages"), QStringLiteral("false")}};
    request("POST", QStringLiteral("Items/%1/Refresh").arg(itemId), query, {},
            [this](bool ok, int, const QJsonDocument &, const QString &error) {
        finishOperation(QStringLiteral("refresh-metadata"), ok,
                        ok ? QStringLiteral("Jellyfin metadata refresh started.") : error);
    });
}

void JellyfinManager::loadServerConfiguration()
{
    request("GET", QStringLiteral("System/Configuration"), {}, {},
            [this](bool ok, int, const QJsonDocument &document, const QString &error) {
        if (!ok || !document.isObject()) { setMessage(error, true); return; }
        m_serverConfiguration = document.object().toVariantMap();
        emit serverConfigurationChanged();
    });
}

void JellyfinManager::saveServerConfiguration(const QVariantMap &changes)
{
    if (m_serverConfiguration.isEmpty()) {
        finishOperation(QStringLiteral("save-settings"), false, QStringLiteral("Load server settings before saving."));
        return;
    }
    const QVariantMap body = mergeMaps(m_serverConfiguration, changes);
    request("POST", QStringLiteral("System/Configuration"), {}, body,
            [this, body](bool ok, int, const QJsonDocument &, const QString &error) {
        if (ok) {
            m_serverConfiguration = body;
            emit serverConfigurationChanged();
            loadServerInfo();
        }
        finishOperation(QStringLiteral("save-settings"), ok,
                        ok ? QStringLiteral("Jellyfin server settings saved.") : error);
    });
}

QString JellyfinManager::connectionPath() const
{
    return QDir(m_stateRoot).filePath(QStringLiteral("connection.secret"));
}

QString JellyfinManager::keyPath() const
{
    return QDir(m_stateRoot).filePath(QStringLiteral("credential.key"));
}

bool JellyfinManager::writePrivateFile(const QString &path, const QByteArray &data)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    if (file.write(data) != data.size() || !file.commit())
        return false;
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
#ifdef Q_OS_UNIX
    ::chmod(QFile::encodeName(path).constData(), 0600);
#endif
    return true;
}

bool JellyfinManager::ensureSecretKey(QByteArray *key, QString *error) const
{
    QFile existing(keyPath());
    if (existing.exists()) {
        if (!existing.open(QIODevice::ReadOnly)) {
            if (error) *error = QStringLiteral("Saved Jellyfin credential key could not be read.");
            return false;
        }
        const QByteArray data = existing.readAll();
        if (data.size() != crypto_secretbox_KEYBYTES) {
            if (error) *error = QStringLiteral("Saved Jellyfin credential key is invalid.");
            return false;
        }
        *key = data;
        return true;
    }
    QByteArray data(crypto_secretbox_KEYBYTES, Qt::Uninitialized);
    randombytes_buf(data.data(), static_cast<size_t>(data.size()));
    if (!writePrivateFile(keyPath(), data)) {
        if (error) *error = QStringLiteral("Jellyfin credential key could not be created.");
        return false;
    }
    *key = data;
    return true;
}

bool JellyfinManager::saveConnectionSecret()
{
    QByteArray key;
    QString error;
    if (!ensureSecretKey(&key, &error)) {
        setMessage(error, true);
        return false;
    }
    const QVariantMap connection{{QStringLiteral("serverUrl"), cleanServerUrl(m_baseUrl)},
                                 {QStringLiteral("apiKey"), m_apiKey},
                                 {QStringLiteral("allowSelfSigned"), m_allowSelfSigned}};
    const QByteArray plain = QJsonDocument::fromVariant(connection).toJson(QJsonDocument::Compact);
    QByteArray nonce(crypto_secretbox_NONCEBYTES, Qt::Uninitialized);
    randombytes_buf(nonce.data(), static_cast<size_t>(nonce.size()));
    QByteArray cipher(plain.size() + crypto_secretbox_MACBYTES, Qt::Uninitialized);
    if (crypto_secretbox_easy(reinterpret_cast<unsigned char *>(cipher.data()),
                              reinterpret_cast<const unsigned char *>(plain.constData()),
                              static_cast<unsigned long long>(plain.size()),
                              reinterpret_cast<const unsigned char *>(nonce.constData()),
                              reinterpret_cast<const unsigned char *>(key.constData())) != 0)
        return false;
    QByteArray output(kSecretMagic);
    output.append(nonce);
    output.append(cipher);
    if (!writePrivateFile(connectionPath(), output))
        return false;
    m_hasSavedConnection = true;
    emit connectionChanged();
    return true;
}

bool JellyfinManager::loadConnectionSecret(QString *error)
{
    QFile file(connectionPath());
    if (!file.open(QIODevice::ReadOnly)) {
        if (error) *error = QStringLiteral("No saved Jellyfin connection was found.");
        return false;
    }
    const QByteArray input = file.readAll();
    const QByteArray magic(kSecretMagic);
    if (!input.startsWith(magic) || input.size() <= magic.size() + crypto_secretbox_NONCEBYTES + crypto_secretbox_MACBYTES) {
        if (error) *error = QStringLiteral("Saved Jellyfin connection data is invalid.");
        return false;
    }
    QByteArray key;
    if (!ensureSecretKey(&key, error))
        return false;
    const QByteArray nonce = input.mid(magic.size(), crypto_secretbox_NONCEBYTES);
    const QByteArray cipher = input.mid(magic.size() + crypto_secretbox_NONCEBYTES);
    QByteArray plain(cipher.size() - crypto_secretbox_MACBYTES, Qt::Uninitialized);
    if (crypto_secretbox_open_easy(reinterpret_cast<unsigned char *>(plain.data()),
                                   reinterpret_cast<const unsigned char *>(cipher.constData()),
                                   static_cast<unsigned long long>(cipher.size()),
                                   reinterpret_cast<const unsigned char *>(nonce.constData()),
                                   reinterpret_cast<const unsigned char *>(key.constData())) != 0) {
        if (error) *error = QStringLiteral("Saved Jellyfin connection data could not be decrypted.");
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(plain, &parseError);
    if (!document.isObject()) {
        if (error) *error = QStringLiteral("Saved Jellyfin connection data is malformed.");
        return false;
    }
    const QVariantMap connection = document.object().toVariantMap();
    QUrl normalized;
    QString validationError;
    if (!validateBaseUrl(connection.value(QStringLiteral("serverUrl")).toString(), &normalized, &validationError)) {
        if (error) *error = validationError;
        return false;
    }
    const QString apiKey = connection.value(QStringLiteral("apiKey")).toString();
    if (apiKey.isEmpty()) {
        if (error) *error = QStringLiteral("Saved Jellyfin API key is empty.");
        return false;
    }
    m_baseUrl = normalized;
    m_apiKey = apiKey;
    m_allowSelfSigned = connection.value(QStringLiteral("allowSelfSigned")).toBool();
    return true;
}
