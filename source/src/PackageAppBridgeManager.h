#pragma once

#include <QHash>
#include <QObject>
#include <QProcess>
#include <QVariantMap>

// App-neutral transport for package-owned helpers. It never starts a process
// during shell construction and only executes a helper recorded as owned by a
// transactionally installed package.
class PackageAppBridgeManager final : public QObject
{
    Q_OBJECT
public:
    explicit PackageAppBridgeManager(const QString &neutronRoot, QObject *parent = nullptr);
    ~PackageAppBridgeManager() override;

    Q_INVOKABLE bool start(const QString &appId, const QString &helperName);
    Q_INVOKABLE bool send(const QString &appId, const QVariantMap &message);
    Q_INVOKABLE void stop(const QString &appId);
    Q_INVOKABLE void stopAll();
    Q_INVOKABLE bool running(const QString &appId) const;
    Q_INVOKABLE QString lastError(const QString &appId) const;

signals:
    void messageReceived(QString appId, QVariantMap message);
    void stateChanged(QString appId, bool running, QString error);

private:
    struct Bridge {
        QProcess *process = nullptr;
        QByteArray output;
        QString error;
    };
    QString m_root;
    QHash<QString, Bridge> m_bridges;

    QString validatedHelper(const QString &appId, const QString &helperName,
                            QString *error) const;
    void consume(const QString &appId);
    static bool protectedAction(const QString &command);
};
