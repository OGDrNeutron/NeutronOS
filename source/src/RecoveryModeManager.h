#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>

class RecoveryModeManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int menuIndex READ menuIndex NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap context READ context NOTIFY stateChanged)
    Q_PROPERTY(QVariantList recoveryPoints READ recoveryPoints NOTIFY stateChanged)
    Q_PROPERTY(int selectedIndex READ selectedIndex NOTIFY stateChanged)
    Q_PROPERTY(int failureOption READ failureOption NOTIFY stateChanged)
    Q_PROPERTY(QString view READ view NOTIFY stateChanged)
    Q_PROPERTY(QString title READ title NOTIFY stateChanged)
    Q_PROPERTY(QString message READ message NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(bool armed READ armed NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)

public:
    explicit RecoveryModeManager(QObject *parent = nullptr);

    int menuIndex() const { return m_menuIndex; }
    QVariantMap context() const { return m_context; }
    Q_INVOKABLE void selectIndex(int index);
    QVariantList recoveryPoints() const;
    int selectedIndex() const;
    int failureOption() const;
    QString view() const;
    QString title() const;
    QString message() const;
    int progress() const;
    bool armed() const;
    bool busy() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool handleAction(const QString &action);

signals:
    void stateChanged();

private slots:
    void onReadyRead();
    void onFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    enum class Operation { None, Status, Apply, Verify, Delete, Cancel, Reboot, ImageDownload, ImageTargets, ImageInstall };
    QProcess m_process;
    Operation m_operation = Operation::None;
    QVariantList m_recoveryPoints;
    QVariantList m_imageReleases;
    QVariantList m_savedRecoveryPoints;
    QString m_selectedImage;
    QByteArray m_output;
    int m_selectedIndex = 0;
    int m_menuIndex = 0;
    QVariantMap m_context;
    QByteArray m_pendingProgress;
    QString m_catalogReturn = QStringLiteral("landing");
    int m_failureOption = 0;
    int m_progress = -1;
    bool m_armed = false;
    bool m_busy = false;
    QString m_view = QStringLiteral("loading");
    QString m_title = QStringLiteral("Preparing Recovery");
    QString m_message = QStringLiteral("Loading the verified recovery catalog…");

    bool start(Operation operation, const QStringList &arguments);
    void beginApply();
    void cancelRecovery();
    void requestReboot();
    void fail(const QString &message);
    QString selectedPath() const;
    static QString sanitizedMessage(const QByteArray &output);
};
