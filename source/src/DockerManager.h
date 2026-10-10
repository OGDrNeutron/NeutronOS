#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>
#include <QQueue>

class DockerManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList containers READ containers NOTIFY containersChanged)
    Q_PROPERTY(bool dockerAvailable READ dockerAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool daemonActive READ daemonActive NOTIFY availabilityChanged)
    Q_PROPERTY(bool daemonEnabled READ daemonEnabled NOTIFY availabilityChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY operationChanged)
    Q_PROPERTY(QString operationName READ operationName NOTIFY operationChanged)
    Q_PROPERTY(QString operationStatus READ operationStatus NOTIFY operationChanged)
    Q_PROPERTY(int operationProgress READ operationProgress NOTIFY operationChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY operationChanged)

public:
    explicit DockerManager(QObject *parent = nullptr);
    ~DockerManager() override;

    QVariantList containers() const;
    bool dockerAvailable() const;
    bool daemonActive() const;
    bool daemonEnabled() const;
    bool busy() const;
    QString operationName() const;
    QString operationStatus() const;
    int operationProgress() const;
    QString lastMessage() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap containerDetails(const QString &containerId) const;
    Q_INVOKABLE bool toggleContainer(const QString &containerId);
    Q_INVOKABLE bool createContainer(const QVariantMap &configuration);
    Q_INVOKABLE bool updateContainer(const QString &containerId,
                                     const QVariantMap &configuration);
    Q_INVOKABLE bool removeContainer(const QString &containerId,
                                     const QString &confirmation);
    Q_INVOKABLE bool cancelOperation();
    Q_INVOKABLE QString formatBytes(qulonglong bytes) const;

signals:
    void containersChanged();
    void availabilityChanged();
    void operationChanged();
    void operationFinished(bool success, const QString &message);

private:
    struct CommandStep
    {
        QString program;
        QStringList arguments;
        QString description;
        bool tolerateNonZero = false;
    };

    QVariantList m_containers;
    bool m_dockerAvailable = false;
    bool m_daemonActive = false;
    bool m_daemonEnabled = false;
    bool m_busy = false;
    QString m_operationName;
    QString m_operationStatus;
    int m_operationProgress = -1;
    QString m_lastMessage;
    QProcess *m_process = nullptr;
    QList<CommandStep> m_steps;
    int m_stepIndex = -1;
    QByteArray m_output;

    static QString dockerExecutable();
    static QString humanBytes(qulonglong bytes);
    static QString sanitizedName(const QString &name);
    static QString sanitizedImage(const QString &image);
    static QStringList splitLines(const QVariant &value);
    static bool safeArgumentLine(const QString &value);
    static QVariantMap result(bool ok, const QString &message);

    QVariantMap findContainer(const QString &containerId) const;
    bool knownContainer(const QString &containerId) const;
    static int runSync(const QString &program,
                       const QStringList &arguments,
                       QByteArray *standardOutput = nullptr,
                       QByteArray *standardError = nullptr,
                       int timeoutMs = 15000);
    bool startSteps(const QString &operationName,
                    const QList<CommandStep> &steps);
    void startNextStep();
    void finishOperation(bool success, const QString &message);
    void setOperation(const QString &name,
                      const QString &status,
                      int progress,
                      const QString &message = QString());

private slots:
    void onReadyRead();
    void onFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessError(QProcess::ProcessError error);
};
