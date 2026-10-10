#pragma once

#include <QByteArray>
#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QVariantMap>
#include <QUrl>
#include <functional>

class QNetworkAccessManager;
class QNetworkReply;
class QJsonDocument;

class JellyfinManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool hasSavedConnection READ hasSavedConnection NOTIFY connectionChanged)
    Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY connectionChanged)
    Q_PROPERTY(QString serverName READ serverName NOTIFY serverInfoChanged)
    Q_PROPERTY(QString serverVersion READ serverVersion NOTIFY serverInfoChanged)
    Q_PROPERTY(QString operatingSystem READ operatingSystem NOTIFY serverInfoChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY messageChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY messageChanged)
    Q_PROPERTY(QVariantList users READ users NOTIFY usersChanged)
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList sessions READ sessions NOTIFY sessionsChanged)
    Q_PROPERTY(QVariantList libraries READ libraries NOTIFY librariesChanged)
    Q_PROPERTY(QVariantList tasks READ tasks NOTIFY tasksChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchResultsChanged)
    Q_PROPERTY(QVariantMap selectedItem READ selectedItem NOTIFY selectedItemChanged)
    Q_PROPERTY(QVariantMap serverConfiguration READ serverConfiguration NOTIFY serverConfigurationChanged)

public:
    explicit JellyfinManager(const QString &neutronRoot, QObject *parent = nullptr);
    ~JellyfinManager() override;

    bool connected() const;
    bool busy() const;
    bool hasSavedConnection() const;
    QString serverUrl() const;
    QString serverName() const;
    QString serverVersion() const;
    QString operatingSystem() const;
    QString lastError() const;
    QString lastMessage() const;
    QVariantList users() const;
    QVariantList devices() const;
    QVariantList sessions() const;
    QVariantList libraries() const;
    QVariantList tasks() const;
    QVariantList searchResults() const;
    QVariantMap selectedItem() const;
    QVariantMap serverConfiguration() const;

    Q_INVOKABLE void connectToServer(const QString &url, const QString &apiKey,
                                     bool allowSelfSigned = false);
    Q_INVOKABLE void connectSaved();
    Q_INVOKABLE void disconnectServer();
    Q_INVOKABLE void forgetConnection();
    Q_INVOKABLE void refreshDashboard();

    Q_INVOKABLE void loadUsers();
    Q_INVOKABLE void createUser(const QString &name, const QString &password,
                                bool administrator, bool disabled, bool hidden);
    Q_INVOKABLE void updateUser(const QString &userId, const QString &name,
                                const QString &password, bool administrator,
                                bool disabled, bool hidden);
    Q_INVOKABLE void deleteUser(const QString &userId);

    Q_INVOKABLE void loadDevices();
    Q_INVOKABLE void deleteDevice(const QString &deviceId);
    Q_INVOKABLE void logoutSession(const QString &sessionId);

    Q_INVOKABLE void loadLibraries();
    Q_INVOKABLE void scanAllLibraries();
    Q_INVOKABLE void scanLibrary(const QString &itemId);

    Q_INVOKABLE void loadTasks();
    Q_INVOKABLE void startTask(const QString &taskId);

    Q_INVOKABLE void searchMedia(const QString &term);
    Q_INVOKABLE void loadItem(const QString &itemId);
    Q_INVOKABLE void saveItemMetadata(const QString &itemId, const QVariantMap &changes);
    Q_INVOKABLE void refreshItemMetadata(const QString &itemId, bool recursive = true);

    Q_INVOKABLE void loadServerConfiguration();
    Q_INVOKABLE void saveServerConfiguration(const QVariantMap &changes);

signals:
    void connectionChanged();
    void busyChanged();
    void serverInfoChanged();
    void messageChanged();
    void usersChanged();
    void devicesChanged();
    void sessionsChanged();
    void librariesChanged();
    void tasksChanged();
    void searchResultsChanged();
    void selectedItemChanged();
    void serverConfigurationChanged();
    void operationFinished(const QString &operation, bool success, const QString &message);

private:
    using ReplyHandler = std::function<void(bool, int, const QJsonDocument &, const QString &)>;

    void setBusyDelta(int delta);
    void setMessage(const QString &message, bool error = false);
    void clearMessages();
    void setConnected(bool value);
    bool validateBaseUrl(const QString &value, QUrl *normalized, QString *error) const;
    QNetworkReply *request(const QByteArray &method, const QString &path,
                           const QVariantMap &query, const QVariant &body,
                           const ReplyHandler &handler);
    void finishOperation(const QString &operation, bool success, const QString &message);
    void testCurrentConnection(bool saveOnSuccess);
    void loadServerInfo();
    QVariantMap userById(const QString &userId) const;
    QVariantMap mergeMaps(const QVariantMap &base, const QVariantMap &changes) const;

    bool saveConnectionSecret();
    bool loadConnectionSecret(QString *error = nullptr);
    bool ensureSecretKey(QByteArray *key, QString *error) const;
    QString connectionPath() const;
    QString keyPath() const;
    static bool writePrivateFile(const QString &path, const QByteArray &data);

    QString m_neutronRoot;
    QString m_stateRoot;
    QNetworkAccessManager *m_network = nullptr;
    QUrl m_baseUrl;
    QString m_apiKey;
    bool m_allowSelfSigned = false;
    bool m_connected = false;
    bool m_hasSavedConnection = false;
    int m_pendingRequests = 0;

    QString m_serverName;
    QString m_serverVersion;
    QString m_operatingSystem;
    QString m_lastError;
    QString m_lastMessage;
    QVariantList m_users;
    QVariantList m_devices;
    QVariantList m_sessions;
    QVariantList m_libraries;
    QVariantList m_tasks;
    QVariantList m_searchResults;
    QVariantMap m_selectedItem;
    QVariantMap m_serverConfiguration;
};
