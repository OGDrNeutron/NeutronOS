#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>

class DeveloperModeManager;

class PrivilegeManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool pending READ pending NOTIFY changed)
    Q_PROPERTY(bool running READ running NOTIFY changed)
    Q_PROPERTY(bool developerMode READ developerMode NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString description READ description NOTIFY changed)
    Q_PROPERTY(QString command READ command NOTIFY changed)
    Q_PROPERTY(QString lastError READ lastError NOTIFY changed)

public:
    explicit PrivilegeManager(DeveloperModeManager *developerModeManager,
                              QObject *parent = nullptr);

    bool pending() const;
    bool running() const;
    bool developerMode() const;
    QString title() const;
    QString description() const;
    QString command() const;
    QString lastError() const;

    Q_INVOKABLE bool request(const QString &title,
                             const QString &description,
                             const QString &command,
                             const QStringList &arguments = {});
    Q_INVOKABLE void proceed(const QString &password = QString());
    Q_INVOKABLE void cancel();

signals:
    void changed();
    void completed(bool success, const QString &message,
                   const QString &output, int exitCode);

private:
    static bool requestLooksAllowed(const QString &command,
                                    const QStringList &arguments,
                                    QString *reason);
    void finishStartFailure(const QString &message);

    DeveloperModeManager *m_developerModeManager = nullptr;
    QProcess m_process;
    bool m_pending = false;
    bool m_running = false;
    QString m_title;
    QString m_description;
    QString m_command;
    QString m_error;
    QString m_output;
    QStringList m_arguments;
};
