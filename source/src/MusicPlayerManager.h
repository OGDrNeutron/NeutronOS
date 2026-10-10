#pragma once

#include <QObject>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QLocalSocket>
#include <QProcess>
#include <QQueue>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class MusicPlayerManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool initialized READ initialized NOTIFY initializedChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool playerAvailable READ playerAvailable NOTIFY playerAvailableChanged)
    Q_PROPERTY(bool playerConnected READ playerConnected NOTIFY playerConnectedChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

    Q_PROPERTY(QVariantList tracks READ tracks NOTIFY tracksChanged)
    Q_PROPERTY(QVariantList albums READ albums NOTIFY albumsChanged)
    Q_PROPERTY(QVariantList artists READ artists NOTIFY artistsChanged)
    Q_PROPERTY(QVariantList folders READ folders NOTIFY foldersChanged)
    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY playlistsChanged)
    Q_PROPERTY(QVariantList queue READ queue NOTIFY queueChanged)
    Q_PROPERTY(QStringList libraryRoots READ libraryRoots NOTIFY libraryRootsChanged)

    Q_PROPERTY(QVariantMap currentTrack READ currentTrack NOTIFY currentTrackChanged)
    Q_PROPERTY(int currentQueueIndex READ currentQueueIndex NOTIFY currentQueueIndexChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playbackStateChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY playbackStateChanged)
    Q_PROPERTY(qint64 positionMs READ positionMs NOTIFY positionChanged)
    Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY durationChanged)
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(QString repeatMode READ repeatMode WRITE setRepeatMode NOTIFY repeatModeChanged)

    Q_PROPERTY(QVariantList equalizerPresets READ equalizerPresets CONSTANT)
    Q_PROPERTY(QString equalizerPreset READ equalizerPreset WRITE setEqualizerPreset NOTIFY equalizerPresetChanged)
    Q_PROPERTY(QVariantList audioOutputs READ audioOutputs NOTIFY audioOutputsChanged)
    Q_PROPERTY(QString selectedAudioOutput READ selectedAudioOutput WRITE setSelectedAudioOutput NOTIFY selectedAudioOutputChanged)

    Q_PROPERTY(QString visualizationMode READ visualizationMode WRITE setVisualizationMode NOTIFY visualizationModeChanged)
    Q_PROPERTY(QStringList visualizationModes READ visualizationModes CONSTANT)
    Q_PROPERTY(QVariantList spectrum READ spectrum NOTIFY spectrumChanged)
    Q_PROPERTY(bool visualizationConsumerActive READ visualizationConsumerActive WRITE setVisualizationConsumerActive NOTIFY visualizationConsumerActiveChanged)

    Q_PROPERTY(bool discoveryBusy READ discoveryBusy NOTIFY discoveryStateChanged)
    Q_PROPERTY(QString discoveryStatus READ discoveryStatus NOTIFY discoveryStateChanged)
    Q_PROPERTY(QVariantList discoveredAudio READ discoveredAudio NOTIFY discoveredAudioChanged)
    Q_PROPERTY(QVariantList metadataRepairPreview READ metadataRepairPreview NOTIFY metadataRepairChanged)
    Q_PROPERTY(bool metadataRepairBusy READ metadataRepairBusy NOTIFY metadataRepairStateChanged)
    Q_PROPERTY(QString metadataRepairStatus READ metadataRepairStatus NOTIFY metadataRepairStateChanged)
    Q_PROPERTY(int metadataRepairCurrent READ metadataRepairCurrent NOTIFY metadataRepairStateChanged)
    Q_PROPERTY(int metadataRepairTotal READ metadataRepairTotal NOTIFY metadataRepairStateChanged)
    Q_PROPERTY(qreal metadataRepairProgress READ metadataRepairProgress NOTIFY metadataRepairStateChanged)

public:
    explicit MusicPlayerManager(const QString &neutronRoot, QObject *parent = nullptr);
    ~MusicPlayerManager() override;

    bool initialized() const;
    bool busy() const;
    bool playerAvailable() const;
    bool playerConnected() const;
    QString status() const;
    QString error() const;

    QVariantList tracks() const;
    QVariantList albums() const;
    QVariantList artists() const;
    QVariantList folders() const;
    QVariantList playlists() const;
    QVariantList queue() const;
    QStringList libraryRoots() const;

    QVariantMap currentTrack() const;
    int currentQueueIndex() const;
    bool playing() const;
    bool paused() const;
    qint64 positionMs() const;
    qint64 durationMs() const;
    int volume() const;
    bool shuffle() const;
    QString repeatMode() const;

    QVariantList equalizerPresets() const;
    QString equalizerPreset() const;
    QVariantList audioOutputs() const;
    QString selectedAudioOutput() const;

    QString visualizationMode() const;
    QStringList visualizationModes() const;
    QVariantList spectrum() const;
    bool visualizationConsumerActive() const;

    bool discoveryBusy() const;
    QString discoveryStatus() const;
    QVariantList discoveredAudio() const;
    QVariantList metadataRepairPreview() const;
    bool metadataRepairBusy() const;
    QString metadataRepairStatus() const;
    int metadataRepairCurrent() const;
    int metadataRepairTotal() const;
    qreal metadataRepairProgress() const;

    Q_INVOKABLE void initialize();
    Q_INVOKABLE void refreshLibrary();
    Q_INVOKABLE void scanLibrary(const QStringList &roots);
    Q_INVOKABLE QString canonicalUserHome() const;
    Q_INVOKABLE QString defaultMusicPath() const;
    Q_INVOKABLE QString parentDirectory(const QString &path) const;
    Q_INVOKABLE QVariantList directoryEntries(const QString &path) const;
    Q_INVOKABLE QStringList suggestedLibraryRoots() const;
    Q_INVOKABLE QStringList supportedExtensions() const;
    Q_INVOKABLE bool addLibraryRoot(const QString &path);
    Q_INVOKABLE bool removeLibraryRoot(const QString &path);

    Q_INVOKABLE bool playTrack(int libraryIndex);
    Q_INVOKABLE bool playPath(const QString &path);
    Q_INVOKABLE bool playAlbum(const QString &albumKey);
    Q_INVOKABLE bool playArtist(const QString &artistName);
    Q_INVOKABLE bool playFolder(const QString &folderPath);
    Q_INVOKABLE bool playPlaylist(const QString &playlistName);
    Q_INVOKABLE bool enqueuePath(const QString &path);
    Q_INVOKABLE bool removeQueueItem(int index);
    Q_INVOKABLE void clearQueue();

    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seekMs(qint64 positionMs);
    Q_INVOKABLE void seekRelativeMs(qint64 deltaMs);
    Q_INVOKABLE void setVolume(int volume);
    Q_INVOKABLE void setShuffle(bool enabled);
    Q_INVOKABLE void toggleShuffle();
    Q_INVOKABLE void setRepeatMode(const QString &mode);
    Q_INVOKABLE void cycleRepeatMode();

    Q_INVOKABLE bool createPlaylist(const QString &name);
    Q_INVOKABLE bool deletePlaylist(const QString &name);
    Q_INVOKABLE bool addToPlaylist(const QString &name, const QString &path);
    Q_INVOKABLE bool removeFromPlaylist(const QString &name, const QString &path);
    Q_INVOKABLE QVariantList playlistTracks(const QString &name) const;

    Q_INVOKABLE void setEqualizerPreset(const QString &preset);
    Q_INVOKABLE void refreshAudioOutputs();
    Q_INVOKABLE void setSelectedAudioOutput(const QString &outputId);

    Q_INVOKABLE void setVisualizationMode(const QString &mode);
    Q_INVOKABLE void setVisualizationConsumerActive(bool active);
    Q_INVOKABLE void scanAllMedia();
    Q_INVOKABLE void clearDiscoveredAudio();
    Q_INVOKABLE bool moveDiscoveredAudio(const QStringList &paths);
    Q_INVOKABLE QString formatDuration(qint64 milliseconds) const;
    Q_INVOKABLE int trackIndexForPath(const QString &path) const;
    Q_INVOKABLE QVariantMap trackForPath(const QString &path) const;
    Q_INVOKABLE QVariantList buildMetadataRepairPreview(const QStringList &paths);
    Q_INVOKABLE bool applyMetadataRepair(const QStringList &paths);
    Q_INVOKABLE void clearMetadataRepairPreview();

signals:
    void initializedChanged();
    void busyChanged();
    void playerAvailableChanged();
    void playerConnectedChanged();
    void statusChanged();
    void errorChanged();

    void tracksChanged();
    void albumsChanged();
    void artistsChanged();
    void foldersChanged();
    void playlistsChanged();
    void queueChanged();
    void libraryRootsChanged();

    void currentTrackChanged();
    void currentQueueIndexChanged();
    void playbackStateChanged();
    void positionChanged();
    void durationChanged();
    void volumeChanged();
    void shuffleChanged();
    void repeatModeChanged();

    void equalizerPresetChanged();
    void audioOutputsChanged();
    void selectedAudioOutputChanged();
    void visualizationModeChanged();
    void spectrumChanged();
    void visualizationConsumerActiveChanged();
    void discoveryStateChanged();
    void discoveredAudioChanged();
    void metadataRepairChanged();
    void metadataRepairStateChanged();

    void scanFinished(bool success, const QString &message);
    void playbackError(const QString &message);
    void operationFinished(const QString &operation, bool success, const QString &message);

private:
    struct ScanPayload {
        QVariantList tracks;
        QVariantMap cache;
        QString error;
    };

    struct DiscoveryPayload {
        QVariantList files;
        QString status;
        QString error;
    };

    struct MetadataRepairPayload {
        QVariantList changes;
        QStringList failures;
        int completed = 0;
        int failed = 0;
        QString error;
    };

    static ScanPayload scanRoots(const QStringList &roots,
                                 const QVariantMap &existingCache,
                                 const QString &artworkDirectory);
    static QVariantMap probeTrack(const QString &path,
                                  const QVariantMap &cached,
                                  const QString &artworkDirectory);
    static DiscoveryPayload discoverAudioOutsideLibrary(const QString &canonicalHome,
                                                        const QStringList &libraryRoots);
    static QString normalizedPath(const QString &path);
    static QString stableId(const QString &text);
    static QString cleanTag(const QString &value, const QString &fallback = QString());
    static int parseTrackNumber(const QString &value);

    void setInitialized(bool value);
    void setBusy(bool value);
    void setPlayerAvailable(bool value);
    void setPlayerConnected(bool value);
    void setStatus(const QString &value);
    void setError(const QString &value);

    void ensureStateDirectories();
    void loadSettings();
    bool saveSettings() const;
    void loadLibraryCache();
    bool saveLibraryCache() const;
    void loadPlaylists();
    bool savePlaylists() const;
    void rebuildCatalogs();
    void pruneQueue();

    QString stateDirectory() const;
    QString settingsPath() const;
    QString cachePath() const;
    QString playlistsPath() const;
    QString artworkDirectory() const;
    QString socketPath() const;

    bool ensurePlayer();
    void startPlayer();
    void connectPlayerSocket();
    void disconnectPlayerSocket();
    void queueCommand(const QJsonArray &command, int requestId = 0);
    void flushCommands();
    void sendObserveCommands();
    void processSocketData();
    void processPlayerMessage(const QJsonObject &object);
    void handlePropertyChange(const QString &name, const QJsonValue &value);
    void handleTrackEnded(const QString &reason);
    void setQueuePaths(const QStringList &paths, int startIndex);
    bool loadQueueIndex(int index, bool force = false);
    int nextQueueIndex() const;
    int previousQueueIndex() const;
    QStringList pathsForAlbum(const QString &albumKey) const;
    QStringList pathsForArtist(const QString &artistName) const;
    QStringList pathsForFolder(const QString &folderPath) const;
    QStringList pathsForPlaylist(const QString &playlistName) const;
    void applyEqualizer();
    void applyAudioOutput();
    void updateSpectrum();
    void updateVisualizationTimer();

    QVariantMap playlistObject(const QString &name) const;
    int playlistObjectIndex(const QString &name) const;

    QString m_neutronRoot;
    bool m_initialized = false;
    bool m_busy = false;
    bool m_playerAvailable = false;
    bool m_playerConnected = false;
    QString m_status;
    QString m_error;

    QVariantList m_tracks;
    QVariantList m_albums;
    QVariantList m_artists;
    QVariantList m_folders;
    QVariantList m_playlists;
    QVariantMap m_libraryCache;
    QStringList m_libraryRoots;

    QStringList m_queuePaths;
    int m_currentQueueIndex = -1;
    QVariantMap m_currentTrack;
    bool m_playing = false;
    bool m_paused = false;
    qint64 m_positionMs = 0;
    qint64 m_durationMs = 0;
    int m_volume = 78;
    bool m_shuffle = false;
    QString m_repeatMode = QStringLiteral("off");

    QString m_equalizerPreset = QStringLiteral("Flat");
    QVariantList m_audioOutputs;
    QString m_selectedAudioOutput = QStringLiteral("auto");
    QString m_visualizationMode = QStringLiteral("Atom");
    QVariantList m_spectrum;
    bool m_visualizationConsumerActive = false;

    bool m_discoveryBusy = false;
    QString m_discoveryStatus;
    QVariantList m_discoveredAudio;
    QVariantList m_metadataRepairPreview;
    bool m_metadataRepairBusy = false;
    QString m_metadataRepairStatus;
    int m_metadataRepairCurrent = 0;
    int m_metadataRepairTotal = 0;

    QFutureWatcher<ScanPayload> m_scanWatcher;
    QFutureWatcher<DiscoveryPayload> m_discoveryWatcher;
    QFutureWatcher<MetadataRepairPayload> m_metadataRepairWatcher;
    QProcess m_playerProcess;
    QLocalSocket m_playerSocket;
    QByteArray m_socketBuffer;
    QQueue<QByteArray> m_pendingCommands;
    QTimer m_socketRetryTimer;
    QTimer m_positionPollTimer;
    QTimer m_spectrumTimer;
    int m_socketAttempts = 0;
    bool m_stoppingForLoad = false;
};
