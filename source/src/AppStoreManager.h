#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>
#include <QHash>
#include <QPointer>
#include <QProcess>

class AppManager;
class DeveloperModeManager;
class SecurityCoreManager;
class QNetworkAccessManager;
class QNetworkReply;

class AppStoreManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString platform READ currentPlatform CONSTANT)
    Q_PROPERTY(QString architecture READ currentArchitecture CONSTANT)
    Q_PROPERTY(QVariantList catalog READ catalog NOTIFY catalogChanged)
    Q_PROPERTY(QVariantList repositories READ repositories NOTIFY repositoriesChanged)
    Q_PROPERTY(QStringList categories READ categories NOTIFY catalogChanged)
    Q_PROPERTY(int availableCount READ availableCount NOTIFY catalogChanged)
    Q_PROPERTY(int updateCount READ updateCount NOTIFY catalogChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool repositoryConnected READ repositoryConnected NOTIFY repositoryConnectedChanged)
    Q_PROPERTY(QString activeOperation READ activeOperation NOTIFY operationStateChanged)
    Q_PROPERTY(QString activePackageId READ activePackageId NOTIFY operationStateChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(QString operationStage READ operationStage NOTIFY operationDetailChanged)
    Q_PROPERTY(QString operationDetail READ operationDetail NOTIFY operationDetailChanged)
    Q_PROPERTY(QStringList operationItems READ operationItems NOTIFY operationDetailChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY statusMessageChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(bool rebuilding READ rebuilding NOTIFY rebuildStateChanged)
    Q_PROPERTY(double rebuildProgress READ rebuildProgress NOTIFY rebuildStateChanged)
    Q_PROPERTY(QString rebuildMessage READ rebuildMessage NOTIFY rebuildStateChanged)
    Q_PROPERTY(QVariantMap startupResume READ startupResume NOTIFY startupResumeChanged)
    Q_PROPERTY(bool developerModeEnabled READ developerModeEnabled NOTIFY developerModeChanged)
    Q_PROPERTY(QVariantMap lastSecurityAnalysis READ lastSecurityAnalysis NOTIFY securityAnalysisChanged)

public:
    explicit AppStoreManager(
        const QString &neutronRoot,
        AppManager *appManager,
        DeveloperModeManager *developerModeManager,
        SecurityCoreManager *securityCoreManager,
        QObject *parent = nullptr
    );
    ~AppStoreManager() override;

    QVariantList catalog() const;
    QVariantList repositories() const;
    QStringList categories() const;
    int availableCount() const;
    int updateCount() const;
    bool busy() const;
    bool repositoryConnected() const;
    QString activeOperation() const;
    QString activePackageId() const;
    QString statusMessage() const;
    QString operationStage() const { return m_operationStage; }
    QString operationDetail() const { return m_operationDetail; }
    QStringList operationItems() const { return m_operationItems; }
    QString lastError() const;
    double progress() const;
    bool rebuilding() const { return m_rebuilding; }
    double rebuildProgress() const { return m_rebuildProgress; }
    QString rebuildMessage() const { return m_rebuildMessage; }
    QVariantMap startupResume() const { return m_startupResume; }
    bool developerModeEnabled() const;
    QVariantMap lastSecurityAnalysis() const { return m_lastSecurityAnalysis; }

    Q_INVOKABLE void refreshCatalog();
    Q_INVOKABLE void reload();
    Q_INVOKABLE QVariantMap packageById(const QString &packageId) const;
    Q_INVOKABLE QVariantList searchPackages(
        const QString &query,
        const QString &category,
        const QString &filter = QStringLiteral("all")
    ) const;
    Q_INVOKABLE QVariantMap compatibilityFor(const QString &packageId) const;
    Q_INVOKABLE bool isInstalled(const QString &packageId) const;
    Q_INVOKABLE QString installedVersion(const QString &packageId) const;
    Q_INVOKABLE bool updateAvailable(const QString &packageId) const;

    Q_INVOKABLE void setApplicationSessionState(const QString &id, bool busy) { m_applicationSessionId=busy?id:QString(); }
    Q_INVOKABLE bool installPackage(const QString &packageId);
    Q_INVOKABLE bool updatePackage(const QString &packageId);
    Q_INVOKABLE bool uninstallPackage(const QString &packageId);
    Q_INVOKABLE bool rollbackPackage(const QString &packageId);
    Q_INVOKABLE bool installLocalPackage(const QString &packagePath);
    Q_INVOKABLE QVariantMap analyzeLocalPackage(const QString &packagePath);
    Q_INVOKABLE bool removeAnalyzedPackage(const QString &packagePath);

    Q_INVOKABLE bool addRepository(
        const QString &name,
        const QString &url,
        const QString &keyId
    );
    Q_INVOKABLE bool removeRepository(const QString &repositoryId);
    Q_INVOKABLE bool setRepositoryEnabled(const QString &repositoryId, bool enabled);
    Q_INVOKABLE bool setRepositoryTrusted(const QString &repositoryId, bool trusted);

    Q_INVOKABLE QString formatBytes(qulonglong bytes) const;
    Q_INVOKABLE QVariantMap installFootprint(const QString &packageId) const;
    Q_INVOKABLE QVariantMap uninstallPlan(const QString &packageId) const;
    Q_INVOKABLE QString appStoreRootPath() const;
    Q_INVOKABLE QString manualPackageDirectory() const;
    Q_INVOKABLE void clearStartupResume();

signals:
    void catalogChanged();
    void repositoriesChanged();
    void busyChanged();
    void repositoryConnectedChanged();
    void operationStateChanged();
    void statusMessageChanged();
    void progressChanged();
    void operationDetailChanged();
    void rebuildStateChanged();
    void rebuildStarted();
    void startupResumeChanged();
    void developerModeChanged();
    void operationFinished(QString packageId, QString operation, bool success, QString message);
    void securityAnalysisChanged();

private:
    QString m_applicationSessionId;
    QString m_neutronRoot;
    AppManager *m_appManager = nullptr;
    DeveloperModeManager *m_developerModeManager = nullptr;
    SecurityCoreManager *m_securityCoreManager = nullptr;
    QNetworkAccessManager *m_network = nullptr;
    QProcess *m_operationProcess = nullptr;
    QProcess *m_rebuildProcess = nullptr;

    QVariantList m_catalog;
    QVariantList m_remoteCatalog;
    QVariantList m_repositories;
    QVariantMap m_installedRegistry;
    QStringList m_categories;

    bool m_busy = false;
    bool m_usedBundledCatalog = false;
    bool m_repositoryConnected = false;
    QString m_activeOperation;
    QString m_activePackageId;
    QString m_statusMessage;
    QString m_lastError;
    double m_progress = 0.0;
    QString m_operationStage;
    QString m_operationDetail;
    QStringList m_operationItems;
    QByteArray m_operationLineBuffer;
    bool m_rebuilding = false;
    double m_rebuildProgress = 0.0;
    QString m_rebuildMessage;
    QByteArray m_rebuildOutput;
    QString m_rebuildStage;
    QString m_rebuildWorkspace;
    QString m_rebuildBuildDirectory;
    QString m_rebuildStagedShell;
    QString m_rebuildOriginalShellBackup;
    quint32 m_rebuildOriginalPermissions = 0;
    bool m_rebuildShellInstalled = false;
    QVariantMap m_pendingRebuildResult;
    QVariantMap m_startupResume;
    QVariantMap m_lastSecurityAnalysis;

    int m_pendingCatalogReplies = 0;
    int m_successfulCatalogSources = 0;
    QHash<QNetworkReply *, QVariantMap> m_replyRepositories;
    QPointer<QNetworkReply> m_packageReply;
    QVariantMap m_pendingPackage;
    QByteArray m_operationOutput;

    QString configDirectory() const;
    QString stateDirectory() const;
    QString repositoriesPath() const;
    QString catalogCachePath() const;
    QString installedRegistryPath() const;
    QString downloadDirectory() const;
    QString helperScriptPath() const;
    QString versionPath() const;

    void ensureDirectories();
    void ensureDefaultConfiguration();
    void loadRepositories();
    void loadInstalledRegistry();
    void loadCatalogCache();
    void saveCatalogCache() const;
    void rebuildCatalog();
    QVariantList scanLocalApplications() const;
    QVariantMap readJsonObject(const QString &path) const;
    bool writeJsonObject(const QString &path, const QVariantMap &object) const;

    void fetchRepository(const QVariantMap &repository);
    bool loadBundledGeminiCatalog(const QVariantMap &repository);
    void consumeRepositoryDocument(const QByteArray &bytes, const QVariantMap &repository);
    void finishCatalogRefresh();
    QVariantMap normalizedPackage(QVariantMap package, const QVariantMap &repository) const;
    QVariantMap decoratedPackage(QVariantMap package) const;
    QVariantMap storefrontStatusForPackage(const QVariantMap &package) const;

    bool beginRemoteInstall(const QVariantMap &package, const QString &operation);
    bool consumeDownloadedPackage(const QByteArray &bytes, const QVariantMap &package, const QString &operation);
    bool verifyPackageBytes(const QByteArray &bytes, const QVariantMap &package, QString *error) const;
    void startHelperOperation(
        const QString &operation,
        const QString &packageId,
        const QStringList &arguments
    );
    void finishOperation(bool success, const QString &message);
    void consumeOperationBytes(const QByteArray &bytes);
    void applyOperationEvent(const QVariantMap &event);
    void setOperationDetail(const QString &stage, const QString &detail = QString(), const QStringList &items = {});
    QVariantMap parseLastJsonObject(const QByteArray &bytes) const;
    void consumeStartupResume();
    void beginRebuild(const QVariantMap &operationResult);
    void consumeRebuildOutput();
    void handleRebuildFinished(int exitCode, QProcess::ExitStatus exitStatus);
    bool restoreOriginalShell(QString *error);
    void cleanupRebuildWorkspace();
    void failRebuild(const QString &message);
    bool rollbackPackageSynchronously(QString *error);
    void armAuthenticatedRestart();
    void setRebuildState(bool rebuilding, double progress, const QString &message);
    QVariantMap inspectLocalPackage(const QString &path, QString *error) const;

    QVariantMap compatibilityForPackage(const QVariantMap &package) const;
    QString currentPlatform() const;
    QString currentArchitecture() const;
    QString currentNeutronVersion() const;
    static int compareVersions(const QString &left, const QString &right);
    static QString normalizeId(const QString &value);
    static QStringList variantStringList(const QVariant &value);
    static QByteArray decodeBinary(const QString &value);

    void setBusy(bool busy);
    void setRepositoryConnected(bool connected);
    void setProgress(double progress);
    void setStatus(const QString &message, const QString &error = QString());
};
