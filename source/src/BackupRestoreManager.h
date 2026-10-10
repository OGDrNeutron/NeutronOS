#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QVariantList>

class UpdateRecoveryManager;

class BackupRestoreManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY stateChanged)
    Q_PROPERTY(QString currentItem READ currentItem NOTIFY stateChanged)
    Q_PROPERTY(QString backupRoot READ backupRoot CONSTANT)
    Q_PROPERTY(QString destinationPath READ destinationPath WRITE setDestinationPath NOTIFY stateChanged)
    Q_PROPERTY(QString latestBackup READ latestBackup NOTIFY backupsChanged)
    Q_PROPERTY(QString latestBackupName READ latestBackupName NOTIFY backupsChanged)
    Q_PROPERTY(QString latestBackupProfile READ latestBackupProfile NOTIFY backupsChanged)
    Q_PROPERTY(QString totalBackupSizeText READ totalBackupSizeText NOTIFY backupsChanged)
    Q_PROPERTY(QString profile READ profile WRITE setProfile NOTIFY stateChanged)
    Q_PROPERTY(QString reinstallPackage READ reinstallPackage NOTIFY stateChanged)
    Q_PROPERTY(bool includeRoms READ includeRoms WRITE setIncludeRoms NOTIFY stateChanged)
    Q_PROPERTY(bool preserveUserData READ preserveUserData WRITE setPreserveUserData NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(bool cleanReinstallReady READ cleanReinstallReady NOTIFY stateChanged)
    Q_PROPERTY(bool recoveryEnvironmentReady READ recoveryEnvironmentReady NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(int backupCount READ backupCount NOTIFY backupsChanged)
    Q_PROPERTY(QVariantList backups READ backups NOTIFY backupsChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)

public:
    explicit BackupRestoreManager(const QString &neutronRoot,
                                  UpdateRecoveryManager *updateRecoveryManager,
                                  QObject *parent = nullptr);
    ~BackupRestoreManager() override;

    QString status() const;
    QString lastMessage() const;
    QString currentItem() const;
    QString backupRoot() const;
    QString destinationPath() const;
    QString latestBackup() const;
    QString latestBackupName() const;
    QString latestBackupProfile() const;
    QString totalBackupSizeText() const;
    QString profile() const;
    QString reinstallPackage() const;
    bool includeRoms() const;
    bool preserveUserData() const;
    bool busy() const;
    bool cleanReinstallReady() const;
    bool recoveryEnvironmentReady() const;
    int progress() const;
    int backupCount() const;
    QVariantList backups() const;
    QVariantList history() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setDestinationPath(const QString &path);
    Q_INVOKABLE void setProfile(const QString &profile);
    Q_INVOKABLE void setIncludeRoms(bool enabled);
    Q_INVOKABLE void setPreserveUserData(bool enabled);
    Q_INVOKABLE bool createBackup(const QString &label = QString());
    Q_INVOKABLE bool verifyLatestBackup();
    Q_INVOKABLE bool restoreLatestBackup();
    Q_INVOKABLE bool restoreBackup(const QString &path);
    Q_INVOKABLE bool deleteLatestBackup();
    Q_INVOKABLE bool secureWipeUserData(const QString &confirmation);
    Q_INVOKABLE bool cleanReinstall(const QString &confirmation);
    Q_INVOKABLE bool cancelCurrentOperation();
    Q_INVOKABLE QString backupDetailsText() const;
    Q_INVOKABLE QString historyText() const;

signals:
    void stateChanged();
    void backupsChanged();
    void historyChanged();
    void operationFinished(const QString &operation, bool success, const QString &message);
    void restartScheduled(const QString &reason);

private slots:
    void onProcessReadyRead();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onBackupListFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    enum class Operation {
        None,
        CreateBackup,
        VerifyBackup,
        RestoreBackup,
        DeleteBackup
    };

    QString m_neutronRoot;
    UpdateRecoveryManager *m_updateRecoveryManager = nullptr;
    QProcess *m_process = nullptr;
    QProcess *m_listProcess = nullptr;
    bool m_scanAgain = false;
    Operation m_operation = Operation::None;
    QString m_status = QStringLiteral("Ready");
    QString m_lastMessage;
    QString m_currentItem;
    QString m_destinationPath;
    QString m_latestBackup;
    QString m_latestBackupProfile;
    QString m_profile = QStringLiteral("full");
    bool m_includeRoms = false;
    bool m_preserveUserData = true;
    bool m_busy = false;
    int m_progress = -1;
    qulonglong m_totalBackupBytes = 0;
    QByteArray m_processOutput;
    QVariantList m_backups;
    QVariantList m_history;

    QString configPath() const;
    QString historyPath() const;
    QString detachedStatusPath() const;
    QString helperPath() const;
    void loadConfig();
    void saveConfig() const;
    void loadHistory();
    void appendHistory(const QString &operation, bool success, const QString &message);
    void importDetachedStatus();
    void scanBackups();
    bool beginProcess(Operation operation, const QStringList &arguments, const QString &message);
    bool startDetached(const QString &action, const QStringList &arguments, const QString &message);
    void setBusy(Operation operation, const QString &message);
    void finish(Operation operation, bool success, const QString &message);
    static QString operationName(Operation operation);
    static QString cleanProfile(const QString &profile);
    static QString humanBytes(qulonglong bytes);
    static QString fileSha256(const QString &path);
    static bool pathInside(const QString &child, const QString &parent);
};
