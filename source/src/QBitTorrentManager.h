#pragma once

#include <QObject>
#include <QByteArray>
#include <QList>
#include <QPair>
#include <QString>
#include <QVariantList>
#include <QUrl>

class QNetworkAccessManager;
class QTimer;

class QBitTorrentManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY authenticatedChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QVariantList torrents READ torrents NOTIFY torrentsChanged)
    Q_PROPERTY(QVariantList torrentFiles READ torrentFiles NOTIFY torrentFilesChanged)
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY configurationChanged)
    Q_PROPERTY(QString configuredUsername READ configuredUsername NOTIFY configurationChanged)

public:
    explicit QBitTorrentManager(const QString &neutronRoot, QObject *parent = nullptr);

    bool authenticated() const;
    bool loading() const;
    QString error() const;
    QVariantList torrents() const;
    QVariantList torrentFiles() const;
    QString baseUrl() const;
    QString configuredUsername() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void startTorrent(const QString &hash);
    Q_INVOKABLE void resumeTorrent(const QString &hash);
    Q_INVOKABLE void pauseTorrent(const QString &hash);
    Q_INVOKABLE void restartTorrent(const QString &hash);
    Q_INVOKABLE void reannounceTorrent(const QString &hash);
    Q_INVOKABLE void recheckTorrent(const QString &hash);
    Q_INVOKABLE void forceStartTorrent(const QString &hash, bool enabled);
    Q_INVOKABLE void deleteTorrent(const QString &hash, bool deleteFiles);
    Q_INVOKABLE void loadTorrentFiles(const QString &hash);
    Q_INVOKABLE void setTorrentFileWanted(const QString &hash, int fileIndex, bool wanted);
    Q_INVOKABLE void retryConnection();
    Q_INVOKABLE bool saveConfiguration(const QString &url, const QString &username, const QString &password);
    Q_INVOKABLE bool saveAndTestConfiguration(const QString &url, const QString &username, const QString &password);

signals:
    void authenticatedChanged();
    void loadingChanged();
    void errorChanged();
    void torrentsChanged();
    void torrentFilesChanged();
    void configurationChanged();

private:
    struct HttpResult {
        int status = 0;
        QByteArray body;
        QString error;
    };

    void loadConfiguration();
    void startLocalBackend();
    bool ensureAuthenticated();
    bool probeApi();
    bool login(const QString &username, const QString &password);
    HttpResult request(const QByteArray &method,
                       const QString &path,
                       const QByteArray &body = {},
                       const QByteArray &contentType = {});
    bool postTorrentCommand(const QString &endpoint,
                            const QString &hash,
                            const QList<QPair<QString, QString>> &extra = {});
    void setAuthenticated(bool value);
    void setLoading(bool value);
    void setError(const QString &value);
    QString statePath() const;
    QString logPath() const;
    void writeLog(const QString &message) const;

    QString m_neutronRoot;
    QUrl m_baseUrl;
    QString m_username;
    QString m_password;
    QNetworkAccessManager *m_network = nullptr;
    QTimer *m_refreshTimer = nullptr;
    bool m_authenticated = false;
    bool m_loading = false;
    QString m_error;
    QVariantList m_torrents;
    QVariantList m_torrentFiles;
};
