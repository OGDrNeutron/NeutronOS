#pragma once

#include <QObject>
#include <QByteArray>
#include <QFutureWatcher>
#include <QJsonObject>
#include <QJsonValue>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>
#include <QFileDevice>
#include <QElapsedTimer>
#include <QDateTime>

#include <atomic>
#include <functional>

class DeveloperModeManager;

class MediaOptimizerManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList locations READ locations NOTIFY locationsChanged)
    Q_PROPERTY(QVariantList media READ media NOTIFY mediaChanged)
    Q_PROPERTY(QString selectedRoot READ selectedRoot NOTIFY stateChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(QString operationStatus READ operationStatus NOTIFY stateChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY stateChanged)
    Q_PROPERTY(QString currentInput READ currentInput NOTIFY stateChanged)
    Q_PROPERTY(QString currentOutput READ currentOutput NOTIFY stateChanged)
    Q_PROPERTY(QString scanCurrentFile READ scanCurrentFile NOTIFY stateChanged)
    Q_PROPERTY(int scanCurrentIndex READ scanCurrentIndex NOTIFY stateChanged)
    Q_PROPERTY(int scanTotalFiles READ scanTotalFiles NOTIFY stateChanged)
    Q_PROPERTY(int scanRemainingFiles READ scanRemainingFiles NOTIFY stateChanged)
    Q_PROPERTY(int scanCachedFiles READ scanCachedFiles NOTIFY stateChanged)
    Q_PROPERTY(int scanNewFiles READ scanNewFiles NOTIFY stateChanged)
    Q_PROPERTY(int scanBatchSize READ scanBatchSize WRITE setScanBatchSize NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList scanBatchOptions READ scanBatchOptions CONSTANT)
    Q_PROPERTY(int scanProcessedThisBatch READ scanProcessedThisBatch NOTIFY stateChanged)
    Q_PROPERTY(int scanPendingFiles READ scanPendingFiles NOTIFY stateChanged)
    Q_PROPERTY(bool scanComplete READ scanComplete NOTIFY stateChanged)
    Q_PROPERTY(bool ffmpegAvailable READ ffmpegAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool ffprobeAvailable READ ffprobeAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool allow4K READ allow4K WRITE setAllow4K NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList presets READ presets NOTIFY presetsChanged)
    Q_PROPERTY(QVariantMap encoderCapabilities READ encoderCapabilities NOTIFY availabilityChanged)
    Q_PROPERTY(bool queueActive READ queueActive NOTIFY queueChanged)
    Q_PROPERTY(int queueCompleted READ queueCompleted NOTIFY queueChanged)
    Q_PROPERTY(int queueTotal READ queueTotal NOTIFY queueChanged)
    Q_PROPERTY(int queueRemaining READ queueRemaining NOTIFY queueChanged)
    Q_PROPERTY(QString queueStage READ queueStage NOTIFY queueChanged)
    Q_PROPERTY(qint64 queueEstimatedMs READ queueEstimatedMs NOTIFY queueChanged)
    Q_PROPERTY(qint64 queueStorageDelta READ queueStorageDelta NOTIFY queueChanged)
    Q_PROPERTY(QVariantList queueErrors READ queueErrors NOTIFY queueChanged)
    Q_PROPERTY(bool renameActive READ renameActive NOTIFY renameChanged)
    Q_PROPERTY(int renameCompleted READ renameCompleted NOTIFY renameChanged)
    Q_PROPERTY(int renameTotal READ renameTotal NOTIFY renameChanged)
    Q_PROPERTY(int renameRemaining READ renameRemaining NOTIFY renameChanged)
    Q_PROPERTY(QString renameCurrentFile READ renameCurrentFile NOTIFY renameChanged)
    Q_PROPERTY(QString renameStatus READ renameStatus NOTIFY renameChanged)
    Q_PROPERTY(QVariantList renameErrors READ renameErrors NOTIFY renameChanged)
    Q_PROPERTY(bool renameUndoAvailable READ renameUndoAvailable NOTIFY renameChanged)

public:
    explicit MediaOptimizerManager(const QString &neutronRoot,
                                   DeveloperModeManager *developerModeManager,
                                   QObject *parent = nullptr);
    ~MediaOptimizerManager() override;

    QVariantList locations() const;
    QVariantList media() const;
    QString selectedRoot() const;
    bool scanning() const;
    bool busy() const;
    int progress() const;
    QString operationStatus() const;
    QString lastMessage() const;
    QString currentInput() const;
    QString currentOutput() const;
    QString scanCurrentFile() const;
    int scanCurrentIndex() const;
    int scanTotalFiles() const;
    int scanRemainingFiles() const;
    int scanCachedFiles() const;
    int scanNewFiles() const;
    int scanBatchSize() const;
    QVariantList scanBatchOptions() const;
    int scanProcessedThisBatch() const;
    int scanPendingFiles() const;
    bool scanComplete() const;
    bool ffmpegAvailable() const;
    bool ffprobeAvailable() const;
    bool allow4K() const;
    QVariantList presets() const;
    QVariantMap encoderCapabilities() const;
    bool queueActive() const;
    int queueCompleted() const;
    int queueTotal() const;
    int queueRemaining() const;
    QString queueStage() const;
    qint64 queueEstimatedMs() const;
    qint64 queueStorageDelta() const;
    QVariantList queueErrors() const;
    bool renameActive() const;
    int renameCompleted() const;
    int renameTotal() const;
    int renameRemaining() const;
    QString renameCurrentFile() const;
    QString renameStatus() const;
    QVariantList renameErrors() const;
    bool renameUndoAvailable() const;

    Q_INVOKABLE void setAllow4K(bool enabled);
    Q_INVOKABLE void setScanBatchSize(int size);
    Q_INVOKABLE void refreshLocations();
    Q_INVOKABLE bool scanLocation(const QString &rootPath);
    Q_INVOKABLE bool continueScan();
    Q_INVOKABLE QVariantMap mediaDetails(const QString &path) const;
    Q_INVOKABLE QVariantMap recommendedSettings(const QString &path) const;
    Q_INVOKABLE QVariantMap defaultSafeConfiguration() const;
    Q_INVOKABLE QVariantMap defaultRokuConfiguration() const;
    Q_INVOKABLE bool configurationHasChanges(const QVariantMap &configuration) const;
    Q_INVOKABLE void completeAnalysisOnly();
    Q_INVOKABLE void resetSessionSafety();
    Q_INVOKABLE QVariantMap prepare4KConversionWarning(const QVariantList &paths,
                                                        const QVariantMap &settings);
    Q_INVOKABLE bool arm4KConversion(const QString &token);
    Q_INVOKABLE QVariantList incompatibleForConfiguration(const QVariantMap &configuration) const;
    Q_INVOKABLE bool savePreset(const QString &name, const QVariantMap &configuration);
    Q_INVOKABLE bool deletePreset(const QString &id);
    Q_INVOKABLE bool startOptimization(const QString &path, const QVariantMap &settings);
    Q_INVOKABLE bool startOptimizationQueue(const QVariantList &paths,
                                            const QVariantMap &settings,
                                            bool replaceOriginals);
    Q_INVOKABLE bool cancelOperation();
    Q_INVOKABLE QString formatBytes(qulonglong bytes) const;
    Q_INVOKABLE QString formatSignedBytes(qint64 bytes) const;
    Q_INVOKABLE QString formatDuration(qint64 milliseconds) const;
    Q_INVOKABLE QString canonicalUserHome() const;
    Q_INVOKABLE QVariantList mediaPickerEntries(const QString &path,
                                                 const QStringList &extensions) const;
    Q_INVOKABLE QString parentDirectory(const QString &path) const;
    Q_INVOKABLE QVariantList buildBatchRenamePreview(const QVariantList &paths,
                                                      const QString &mode) const;
    Q_INVOKABLE bool startBatchRename(const QVariantList &entries);
    Q_INVOKABLE bool undoLastRenameBatch();

signals:
    void locationsChanged();
    void mediaChanged();
    void stateChanged();
    void availabilityChanged();
    void settingsChanged();
    void presetsChanged();
    void queueChanged();
    void scanFinished(bool success, const QString &message);
    void optimizationFinished(bool success, const QString &message, const QString &outputPath);
    void optimizationQueueFinished(bool success, const QString &message);
    void renameChanged();
    void batchRenameFinished(bool success, const QString &message);

private:
    QString m_neutronRoot;
    DeveloperModeManager *m_developerModeManager = nullptr;
    QVariantList m_locations;
    QVariantList m_media;
    QVariantList m_customPresets;
    QString m_selectedRoot;
    bool m_scanning = false;
    bool m_busy = false;
    int m_progress = -1;
    QString m_operationStatus;
    QString m_lastMessage;
    QString m_currentInput;
    QString m_currentOutput;
    QString m_temporaryOutput;
    QString m_replacementBackup;
    qint64 m_currentDurationMs = 0;
    qint64 m_currentSourceSize = 0;
    QFileDevice::Permissions m_currentPermissions{};
    QDateTime m_currentModified;
    QByteArray m_ffmpegErrors;
    QFutureWatcher<QVariantMap> *m_scanWatcher = nullptr;
    QProcess *m_ffmpegProcess = nullptr;
    bool m_ffmpegAvailable = false;
    bool m_ffprobeAvailable = false;
    bool m_allow4K = false;
    QString m_scanCurrentFile;
    int m_scanCurrentIndex = 0;
    int m_scanTotalFiles = 0;
    int m_scanRemainingFiles = 0;
    int m_scanCachedFiles = 0;
    int m_scanNewFiles = 0;
    int m_scanBatchSize = 500;
    int m_scanProcessedThisBatch = 0;
    int m_scanPendingFiles = 0;
    bool m_scanComplete = true;
    std::atomic_bool m_scanCancelRequested{false};

    bool m_replaceOriginal = false;
    bool m_queueActive = false;
    QVariantList m_queuePaths;
    QVariantMap m_queueSettings;
    int m_queueIndex = 0;
    int m_queueCompleted = 0;
    int m_queueTotal = 0;
    QString m_queueStage;
    qint64 m_queueEstimatedMs = 0;
    qint64 m_queueStorageDelta = 0;
    QVariantList m_queueErrors;
    QElapsedTimer m_queueTimer;
    bool m_queue4KAuthorized = false;
    QString m_pending4KToken;
    QByteArray m_pending4KFingerprint;
    QByteArray m_authorized4KFingerprint;

    bool m_renameActive = false;
    QVariantList m_renameQueue;
    QVariantList m_renameErrors;
    QVariantList m_lastRenameUndo;
    int m_renameIndex = 0;
    int m_renameCompleted = 0;
    QString m_renameCurrentFile;
    QString m_renameStatus;

    static QString executable(const QString &name);
    static QString canonicalDirectory(const QString &path);
    static QString humanBytes(qulonglong bytes);
    static QString durationText(qint64 milliseconds);
    static QString normalizedCodec(const QString &codec);
    static bool isVideoCodecCompatible(const QString &codec);
    static bool isAudioTrackCompatible(const QVariantMap &track);
    static bool isEnglish(const QString &language);
    static bool isImageSubtitleCodec(const QString &codec);
    static QVariantMap probeFile(const QString &ffprobe, const QString &path);
    static QVariantMap scanMediaRoot(const QString &ffprobe,
                                     const QString &rootPath,
                                     const QString &cachePath,
                                     int batchSize,
                                     std::atomic_bool *cancelRequested,
                                     const std::function<void(int, int, int, const QString &, int, int, int)> &progressCallback);
    static QVariantMap buildMediaItem(const QString &path, const QJsonObject &probe);
    static QVariantMap applyCompatibilityPolicy(QVariantMap item, bool allow4K);
    static qint64 jsonInteger(const QJsonValue &value);
    static double jsonDouble(const QJsonValue &value);
    static QString cleanedReleaseTitle(const QString &baseName);
    static QString smartTitleCase(const QString &value);
    static QString safeRenameStem(const QString &value);
    static QVariantMap renameProposal(const QString &path, const QString &mode);

    QVariantMap findMedia(const QString &path) const;
    QString outputPathFor(const QString &inputPath, const QVariantMap &settings) const;
    QString effectiveContainerFor(const QVariantMap &item, const QVariantMap &settings) const;
    bool configurationHasActualChanges(const QVariantMap &configuration) const;
    bool videoConversionSelected(const QVariantMap &settings) const;
    QString normalized4KPolicy(const QVariantMap &settings) const;
    QByteArray fourKAuthorizationFingerprint(const QVariantList &paths,
                                              const QVariantMap &settings) const;
    void clear4KAuthorization();
    QString selectVideoEncoder(const QString &mode, const QString &preference = QString()) const;
    QString selectAudioEncoder(const QString &mode) const;
    QString containerFormat(const QString &container) const;
    bool ffmpegHasEncoder(const QString &encoder) const;
    bool verifyOutputFile(const QString &path) const;
    QStringList selectedAudioIndexes(const QVariantMap &item, const QString &trackMode) const;
    QStringList selectedSubtitleIndexes(const QVariantMap &item, const QString &subtitleMode) const;
    QString cachePathForRoot(const QString &rootPath) const;
    QString settingsPath() const;
    QString presetsPath() const;
    void loadSettings();
    void saveSettings() const;
    void loadPresets();
    void savePresets() const;
    void applyPolicyToMedia();
    QVariantList cachedMediaForRoot(const QString &rootPath) const;
    void applyScanProgress(int currentBatch,
                           int batchTarget,
                           int totalFiles,
                           const QString &path,
                           int cachedCount,
                           int newCount,
                           int pendingCount);
    void setState(const QString &status, int progress, const QString &message = QString());
    void finishOptimization(bool success, const QString &message);
    void startNextQueuedItem();
    void finishQueue(bool success, const QString &message);
    void updateQueueEstimate();
    void processNextRename();
    void finishBatchRename(bool success, const QString &message);
    bool updateCacheAfterRename(const QString &oldPath, const QString &newPath);
    void saveRenameHistory() const;
    void loadRenameHistory();

private slots:
    void onScanFinished();
    void onFfmpegStandardOutput();
    void onFfmpegStandardError();
    void onFfmpegFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onFfmpegError(QProcess::ProcessError error);
};
