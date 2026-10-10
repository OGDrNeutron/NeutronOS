#pragma once

#include <QObject>
#include <QFutureWatcher>
#include <QHash>
#include <QElapsedTimer>
#include <QList>
#include <QProcess>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class StorageManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(QVariantMap usageBreakdowns READ usageBreakdowns NOTIFY devicesChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY operationChanged)
    Q_PROPERTY(QString operationName READ operationName NOTIFY operationChanged)
    Q_PROPERTY(QString operationStatus READ operationStatus NOTIFY operationChanged)
    Q_PROPERTY(int operationProgress READ operationProgress NOTIFY operationChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY operationChanged)
    Q_PROPERTY(QString operationSource READ operationSource NOTIFY operationChanged)
    Q_PROPERTY(QString operationTarget READ operationTarget NOTIFY operationChanged)
    Q_PROPERTY(quint64 operationBytesProcessed READ operationBytesProcessed NOTIFY operationChanged)
    Q_PROPERTY(quint64 operationTotalBytes READ operationTotalBytes NOTIFY operationChanged)
    Q_PROPERTY(QString operationBytesText READ operationBytesText NOTIFY operationChanged)
    Q_PROPERTY(QString operationSpeed READ operationSpeed NOTIFY operationChanged)
    Q_PROPERTY(QString operationEta READ operationEta NOTIFY operationChanged)
    Q_PROPERTY(QString operationElapsed READ operationElapsed NOTIFY operationChanged)
    Q_PROPERTY(QString operationVerification READ operationVerification NOTIFY operationChanged)
    Q_PROPERTY(QVariantList imagerCatalog READ imagerCatalog NOTIFY imagerCatalogChanged)
    Q_PROPERTY(bool imagerCatalogLoading READ imagerCatalogLoading NOTIFY imagerCatalogChanged)
    Q_PROPERTY(QString imagerCatalogStatus READ imagerCatalogStatus NOTIFY imagerCatalogChanged)
    Q_PROPERTY(QString systemDisk READ systemDisk NOTIFY devicesChanged)
    Q_PROPERTY(bool smartctlAvailable READ smartctlAvailable CONSTANT)
    Q_PROPERTY(QStringList supportedFilesystems READ supportedFilesystems CONSTANT)
    Q_PROPERTY(QVariantList optimizationCandidates READ optimizationCandidates NOTIFY optimizationChanged)
    Q_PROPERTY(bool optimizationScanning READ optimizationScanning NOTIFY optimizationChanged)
    Q_PROPERTY(QString optimizationRoot READ optimizationRoot NOTIFY optimizationChanged)
    Q_PROPERTY(quint64 optimizationReclaimableBytes READ optimizationReclaimableBytes NOTIFY optimizationChanged)
    Q_PROPERTY(QString optimizationReclaimable READ optimizationReclaimable NOTIFY optimizationChanged)
    Q_PROPERTY(QString optimizationSummary READ optimizationSummary NOTIFY optimizationChanged)
    Q_PROPERTY(QVariantMap performanceTelemetry READ performanceTelemetry NOTIFY performanceTelemetryChanged)
    Q_PROPERTY(QVariantList recentActivity READ recentActivity NOTIFY activityChanged)

public:
    explicit StorageManager(QObject *parent = nullptr);
    ~StorageManager() override;

    QVariantList devices() const;
    QVariantMap usageBreakdowns() const;
    bool busy() const;
    QString operationName() const;
    QString operationStatus() const;
    int operationProgress() const;
    QString lastMessage() const;
    QString operationSource() const;
    QString operationTarget() const;
    quint64 operationBytesProcessed() const;
    quint64 operationTotalBytes() const;
    QString operationBytesText() const;
    QString operationSpeed() const;
    QString operationEta() const;
    QString operationElapsed() const;
    QString operationVerification() const;
    QVariantList imagerCatalog() const;
    bool imagerCatalogLoading() const;
    QString imagerCatalogStatus() const;
    QString systemDisk() const;
    bool smartctlAvailable() const;
    QStringList supportedFilesystems() const;
    QVariantList optimizationCandidates() const;
    bool optimizationScanning() const;
    QString optimizationRoot() const;
    quint64 optimizationReclaimableBytes() const;
    QString optimizationReclaimable() const;
    QString optimizationSummary() const;
    QVariantMap performanceTelemetry() const;
    QVariantList recentActivity() const;

    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void requestUsageBreakdown(const QString &mountPoint, bool force = false);
    Q_INVOKABLE QVariantMap deviceDetails(const QString &devicePath) const;
    Q_INVOKABLE QVariantMap validateFormat(const QString &devicePath,
                                            const QString &filesystem) const;
    Q_INVOKABLE QVariantMap validateBootClone(const QString &targetDevice) const;
    Q_INVOKABLE QVariantMap validateImageFlash(const QString &imagePath,
                                               const QString &targetDevice) const;
    Q_INVOKABLE bool runSmartCheck(const QString &devicePath);
    Q_INVOKABLE bool runHealthCheck(const QString &devicePath);
    Q_INVOKABLE bool formatDevice(const QString &devicePath,
                                  const QString &filesystem,
                                  const QString &label = QString());
    Q_INVOKABLE bool cloneBootDevice(const QString &targetDevice);
    Q_INVOKABLE bool flashImage(const QString &imagePath,
                                const QString &targetDevice);
    Q_INVOKABLE void refreshImagerCatalog();
    Q_INVOKABLE bool installRecommendedImage(const QVariantMap &osEntry,
                                              const QString &targetDevice,
                                              const QVariantMap &setup);
    Q_INVOKABLE bool installManualImage(const QString &imagePath,
                                        const QString &targetDevice,
                                        const QVariantMap &setup);
    Q_INVOKABLE bool cancelOperation();
    Q_INVOKABLE QString suggestedMountName(const QString &devicePath) const;
    Q_INVOKABLE QVariantMap validateMount(const QString &devicePath,
                                           const QString &mountName) const;
    Q_INVOKABLE bool mountDevice(const QString &devicePath,
                                 const QString &mountName);
    Q_INVOKABLE QVariantMap validateUnmount(const QString &devicePath) const;
    Q_INVOKABLE bool unmountDevice(const QString &devicePath);
    Q_INVOKABLE bool ejectDevice(const QString &devicePath);

    Q_INVOKABLE QString defaultOptimizationRoot() const;
    Q_INVOKABLE bool scanOptimization(const QString &rootPath = QString(),
                                      int olderThanDays = 30);
    Q_INVOKABLE QVariantMap optimizationCandidateDetails(const QString &path) const;
    Q_INVOKABLE QVariantMap validateOptimizationDelete(const QStringList &paths) const;
    Q_INVOKABLE bool deleteOptimizationCandidates(const QStringList &paths,
                                                   const QString &confirmation);
    Q_INVOKABLE QString describePath(const QString &path) const;

signals:
    void devicesChanged();
    void operationChanged();
    void operationFinished(bool success, const QString &message);
    void optimizationChanged();
    void imagerCatalogChanged();
    void optimizationFinished(bool success, const QString &message);
    void performanceTelemetryChanged();
    void activityChanged();

private:
    struct CommandStep
    {
        QString program;
        QStringList arguments;
        QString description;
        bool tolerateNonZero = false;
    };

    QVariantList m_devices;
    QVariantMap m_usageBreakdowns;
    QSet<QString> m_usageBreakdownScanning;
    QHash<QString, qint64> m_usageBreakdownLastScanMs;
    QHash<QString, QVariantMap> m_flatDevices;
    QHash<QString, QVariantMap> m_smartResults;
    QString m_systemDisk;

    QProcess *m_process = nullptr;
    QProcess *m_catalogProcess = nullptr;
    QList<CommandStep> m_steps;
    int m_stepIndex = -1;
    bool m_busy = false;
    QString m_operationName;
    QString m_operationStatus;
    int m_operationProgress = -1;
    QString m_lastMessage;
    QString m_operationTarget;
    QString m_smartTarget;
    quint64 m_cloneSourceBytes = 0;
    QString m_operationSource;
    quint64 m_operationBytesProcessed = 0;
    QString m_operationSpeed;
    QString m_operationEta;
    QString m_operationElapsed;
    QString m_operationVerification = QStringLiteral("NOT REQUIRED");
    QElapsedTimer m_operationTimer;
    QByteArray m_processOutput;
    QByteArray m_progressBuffer;
    QByteArray m_catalogOutput;
    QVariantList m_imagerCatalog;
    bool m_imagerCatalogLoading = false;
    QString m_imagerCatalogStatus = QStringLiteral("NOT LOADED");
    QString m_imagerJobPath;

    QVariantList m_optimizationCandidates;
    bool m_optimizationScanning = false;
    QString m_optimizationRoot;
    quint64 m_optimizationReclaimableBytes = 0;
    int m_optimizationAgeDays = 30;
    QString m_optimizationSummary;
    QFutureWatcher<QVariantMap> *m_optimizationWatcher = nullptr;

    QTimer m_performanceTimer;
    QVariantMap m_performanceTelemetry;
    QVariantMap m_previousDiskStats;
    qint64 m_previousDiskStatsMs = 0;
    QVariantList m_recentActivity;

    static QString executable(const QString &name);
    static QString humanBytes(quint64 bytes);
    static QString humanDuration(qint64 seconds);
    static QString shellQuoted(const QString &value);
    static QString imagerScriptPath();
    static quint64 imageExpandedSize(const QString &imagePath, QString *archiveMember = nullptr);
    static QString normalizedFilesystem(const QString &filesystem);
    static QString sanitizedLabel(const QString &label, const QString &filesystem);
    static QString firstPartitionPath(const QString &diskPath);
    static QStringList stringListFromJson(const QVariant &value);
    static QVariantMap scanOptimizationRoot(const QString &rootPath, int olderThanDays);
    static QString purposeForPath(const QString &path);
    static QString categoryForPath(const QString &path);
    static bool isOptimizationRootAllowed(const QString &path);
    static bool isProtectedOptimizationPath(const QString &path);
    static QString canonicalOrAbsolute(const QString &path);
    static QString sanitizedMountName(const QString &name);
    static QVariantMap scanUsageBreakdown(const QString &mountPoint);
    static int parseTemperatureFromSmartJson(const QByteArray &jsonData);

    int probeSysfsTemperature(const QVariantMap &device) const;
    int probeTemperature(const QVariantMap &device) const;
    void refreshTemperatureReadings(const QVariantList &devices);
    void samplePerformanceTelemetry();
    void appendActivity(const QString &kind,
                        const QString &title,
                        const QString &detail,
                        const QString &tone = QStringLiteral("info"));

    QVariantMap parseLsblkNode(const QVariantMap &node,
                               const QString &parentPath,
                               bool *containsRoot);
    void rebuildFlatDeviceIndex();
    void indexDevice(const QVariantMap &device);
    QVariantMap findDevice(const QString &path) const;
    QVariantMap findTopLevelDevice(const QString &path) const;
    QStringList mountedPaths(const QVariantMap &device) const;
    QStringList mountedPathsRecursive(const QVariantMap &device) const;
    QVariantMap mountableVolume(const QString &path) const;
    bool isKnownBlockDevice(const QString &path) const;
    bool isProtectedDevice(const QVariantMap &device) const;
    quint64 deviceSize(const QVariantMap &device) const;
    QString deviceType(const QVariantMap &device) const;
    QVariantMap result(bool ok, const QString &message) const;

    void setOperationState(const QString &name,
                           const QString &status,
                           int progress,
                           const QString &message = QString());
    bool startImagerJob(const QVariantMap &osEntry,
                        const QString &targetDevice,
                        const QVariantMap &setup,
                        const QString &localPath = QString());
    bool startSteps(const QString &operationName,
                    const QString &target,
                    const QList<CommandStep> &steps,
                    quint64 cloneSourceBytes = 0,
                    const QString &source = QString());
    void startNextStep();
    void finishOperation(bool success, const QString &message);
    void parseSmartResult(const QByteArray &jsonData);
    void updateSmartFields(QVariantMap &device) const;
    void updateSmartFieldsRecursive(QVariantList &devices) const;
    void handleProcessOutput(const QByteArray &data);

private slots:
    void onProcessReadyRead();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onOptimizationScanFinished();
    void onCatalogReadyRead();
    void onCatalogFinished(int exitCode, QProcess::ExitStatus exitStatus);
};
