#pragma once

#include <QObject>
#include <QFutureWatcher>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>

class QNetworkReply;
class QFile;
class DeveloperModeManager;

class UpdateRecoveryManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString currentVersion READ currentVersion NOTIFY stateChanged)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY stateChanged)
    Q_PROPERTY(QString channel READ channel WRITE setChannel NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY stateChanged)
    Q_PROPERTY(QString lastChecked READ lastChecked NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotes READ releaseNotes NOTIFY stateChanged)
    Q_PROPERTY(QString updateSizeText READ updateSizeText NOTIFY stateChanged)
    Q_PROPERTY(QString manifestUrl READ manifestUrl WRITE setManifestUrl NOTIFY stateChanged)
    Q_PROPERTY(QString downloadedPackage READ downloadedPackage NOTIFY stateChanged)
    Q_PROPERTY(QString integritySummary READ integritySummary NOTIFY integrityChanged)
    Q_PROPERTY(QString latestRecoveryPoint READ latestRecoveryPoint NOTIFY recoveryChanged)
    Q_PROPERTY(QString recoveryDirectory READ recoveryDirectory CONSTANT)
    Q_PROPERTY(QString lastCheckedText READ lastCheckedText NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool packageDownloaded READ packageDownloaded NOTIFY stateChanged)
    Q_PROPERTY(bool packageVerified READ packageVerified NOTIFY stateChanged)
    Q_PROPERTY(bool manifestVerified READ manifestVerified NOTIFY stateChanged)
    Q_PROPERTY(bool rollbackAvailable READ rollbackAvailable NOTIFY recoveryChanged)
    Q_PROPERTY(bool safeModePrepared READ safeModePrepared NOTIFY recoveryChanged)
    Q_PROPERTY(bool recoveryModePrepared READ recoveryModePrepared NOTIFY recoveryChanged)
    Q_PROPERTY(bool repositoryConfigured READ repositoryConfigured NOTIFY stateChanged)
    Q_PROPERTY(bool trustedKeyAvailable READ trustedKeyAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool releaseManifestAvailable READ releaseManifestAvailable NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(int debianUpdatesAvailable READ debianUpdatesAvailable NOTIFY stateChanged)
    Q_PROPERTY(int recoveryPointCount READ recoveryPointCount NOTIFY recoveryChanged)
    Q_PROPERTY(QVariantList recoveryPoints READ recoveryPoints NOTIFY recoveryChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(QVariantMap integrityReport READ integrityReport NOTIFY integrityChanged)

public:
    explicit UpdateRecoveryManager(const QString &neutronRoot,
                                   DeveloperModeManager *developerModeManager,
                                   QObject *parent = nullptr,
                                   const QString &trustedPublicKeyPath = QString());
    ~UpdateRecoveryManager() override;

    QString currentVersion() const;
    QString availableVersion() const;
    QString channel() const;
    QString status() const;
    QString lastMessage() const;
    QString lastChecked() const;
    QString releaseNotes() const;
    QString updateSizeText() const;
    QString manifestUrl() const;
    QString downloadedPackage() const;
    QString integritySummary() const;
    QString latestRecoveryPoint() const;
    QString recoveryDirectory() const;
    QString lastCheckedText() const;
    bool busy() const;
    bool updateAvailable() const;
    bool packageDownloaded() const;
    bool packageVerified() const;
    bool manifestVerified() const;
    bool rollbackAvailable() const;
    bool safeModePrepared() const;
    bool recoveryModePrepared() const;
    bool repositoryConfigured() const;
    bool trustedKeyAvailable() const;
    bool releaseManifestAvailable() const;
    int progress() const;
    int debianUpdatesAvailable() const;
    int recoveryPointCount() const;
    QVariantList recoveryPoints() const;
    QVariantList history() const;
    QVariantMap integrityReport() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setChannel(const QString &channel);
    Q_INVOKABLE void setManifestUrl(const QString &url);
    Q_INVOKABLE bool checkForUpdates(const QString &channel = QString());
    Q_INVOKABLE bool downloadAvailableUpdate();
    Q_INVOKABLE bool cancelCurrentOperation();
    Q_INVOKABLE bool checkDebianUpdates();
    Q_INVOKABLE bool installDebianUpdates();
    Q_INVOKABLE bool verifyInstallation();
    Q_INVOKABLE bool createRecoveryPoint(const QString &label = QString());
    Q_INVOKABLE bool prepareAvailableUpdateForInstall();
    Q_INVOKABLE bool installDownloadedUpdate();
    Q_INVOKABLE bool rollbackLastUpdate();
    Q_INVOKABLE bool repairInstallation();
    Q_INVOKABLE bool prepareSafeMode();
    Q_INVOKABLE bool cancelSafeMode();
    Q_INVOKABLE bool prepareRecoveryMode();
    Q_INVOKABLE bool cancelRecoveryMode();
    Q_INVOKABLE bool clearUpdateCache();
    Q_INVOKABLE QString historyText() const;
    Q_INVOKABLE QString integrityReportText() const;

signals:
    void stateChanged();
    void historyChanged();
    void integrityChanged();
    void recoveryChanged();
    void operationFinished(const QString &operation, bool success, const QString &message);
    void restartScheduled(const QString &reason);
    void installCandidateReady(const QString &version, const QString &size,
                               const QString &releaseNotes);

private slots:
    void onManifestFinished();
    void onDownloadReadyRead();
    void onDownloadProgress(qint64 received, qint64 total);
    void onDownloadFinished();
    void onProcessReadyRead();
    void onProcessFinished(int exitCode, QProcess::ExitStatus status);
    void onIntegrityFinished();

private:
    enum class Operation {
        None,
        CheckManifest,
        SyncMainline,
        Download,
        CheckDebian,
        VerifyIntegrity,
        CreateRecovery,
        StageUpdate
    };

    QString m_neutronRoot;
    QString m_trustedPublicKeyPath;
    DeveloperModeManager *m_developerModeManager = nullptr;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QFile *m_downloadFile = nullptr;
    QProcess *m_process = nullptr;
    QFutureWatcher<QVariantMap> *m_integrityWatcher = nullptr;
    Operation m_operation = Operation::None;

    QString m_currentVersion;
    QString m_availableVersion;
    QString m_channel = QStringLiteral("stable");
    QString m_status = QStringLiteral("Ready");
    QString m_lastMessage;
    QString m_lastChecked;
    QString m_releaseNotes;
    QString m_manifestUrl;
    QString m_mainlineSyncCommand;
    QString m_packageUrl;
    QString m_expectedSha256;
    QString m_signatureBase64;
    QString m_downloadedPackage;
    QString m_manifestEnvelopePath;
    QString m_manifestSourceUrl;
    QString m_integritySummary = QStringLiteral("Not verified");
    QString m_latestRecoveryPoint;
    bool m_busy = false;
    bool m_updateAvailable = false;
    bool m_packageDownloaded = false;
    bool m_packageVerified = false;
    bool m_manifestVerified = false;
    bool m_mainlineManaged = false;
    bool m_safeModePrepared = false;
    bool m_recoveryModePrepared = false;
    bool m_prepareInstallAfterDownload = false;
    int m_progress = -1;
    int m_debianUpdatesAvailable = 0;
    qulonglong m_updateSize = 0;
    QByteArray m_processOutput;
    QVariantList m_history;
    QVariantMap m_integrityReport;
    QVariantList m_recoveryPoints;
    QJsonObject m_manifest;

    QString configPath() const;
    QString statePath() const;
    QString historyPath() const;
    QString downloadsPath() const;
    QString inboxManifestPath() const;
    QString releaseManifestPath() const;
    QString publicKeyPath() const;
    QString recoveryRoot() const;
    QString safeModeFlagPath() const;
    QString recoveryModeFlagPath() const;
    QString recoveryControlPath() const;
    QString helperPath() const;

    void loadConfig();
    void saveConfig() const;
    void loadState();
    void saveState() const;
    void loadHistory();
    void appendHistory(const QString &type, bool success, const QString &message,
                       const QVariantMap &extra = QVariantMap());
    void refreshRecoveryState();
    void setBusy(Operation operation, const QString &status, int progress = -1);
    void finish(Operation operation, bool success, const QString &message);
    bool beginProcess(Operation operation, const QString &program,
                      const QStringList &arguments, const QString &status);
    bool fetchConfiguredManifest();
    bool startDetachedRecoveryAction(const QString &action, const QStringList &arguments,
                                     const QString &description);
    bool parseManifest(const QByteArray &payload, QString *errorMessage);
    bool parseMainlineIndex(const QJsonObject &index, QString *errorMessage);
    bool parseMainlineMetadataEnvelope(const QJsonObject &envelope, QString *errorMessage);
    bool reconcileAuthenticatedDownloadPath(QString *errorMessage);
    bool verifyArtifactContent(const QString &path, QString *errorMessage) const;
    bool verifyDownloadedPackage(QString *errorMessage);
    bool reloadPersistedCandidate(QString *errorMessage);
    QByteArray readPublicKey(QString *errorMessage) const;
    bool verifyReleaseSignature(const QByteArray &metadata, const QByteArray &signature, QString *errorMessage) const;
    static QVariantMap verifyManifestFiles(const QString &root, const QString &manifestPath);
    static QString humanBytes(qulonglong bytes);
    static bool isNewerVersion(const QString &candidate, const QString &current);
    static QString cleanChannel(const QString &channel);
    static QString operationName(Operation operation);
};
