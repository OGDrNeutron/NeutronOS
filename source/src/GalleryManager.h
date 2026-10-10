#pragma once

#include <QObject>
#include <QFutureWatcher>
#include <QFileInfo>
#include <QHash>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class GalleryManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(QVariantList albums READ albums NOTIFY albumsChanged)
    Q_PROPERTY(QStringList roots READ roots NOTIFY rootsChanged)
    Q_PROPERTY(int mediaCount READ mediaCount NOTIFY itemsChanged)
    Q_PROPERTY(int imageCount READ imageCount NOTIFY itemsChanged)
    Q_PROPERTY(int videoCount READ videoCount NOTIFY itemsChanged)
    Q_PROPERTY(int screenshotCount READ screenshotCount NOTIFY itemsChanged)
    Q_PROPERTY(int recordingCount READ recordingCount NOTIFY itemsChanged)

public:
    explicit GalleryManager(const QString &neutronRoot, QObject *parent = nullptr);

    bool busy() const;
    QString error() const;
    QVariantList items() const;
    QVariantList albums() const;
    QStringList roots() const;
    int mediaCount() const;
    int imageCount() const;
    int videoCount() const;
    int screenshotCount() const;
    int recordingCount() const;

    Q_INVOKABLE void initialize();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void scan(const QStringList &roots);
    Q_INVOKABLE QVariantMap metadata(const QString &path) const;
    Q_INVOKABLE bool toggleFavorite(const QString &path);
    Q_INVOKABLE bool isFavorite(const QString &path) const;
    Q_INVOKABLE bool rotateImage(const QString &path, int degrees);
    Q_INVOKABLE bool copyMedia(const QString &path, const QString &destinationDirectory);
    Q_INVOKABLE bool moveMedia(const QString &path, const QString &destinationDirectory);
    Q_INVOKABLE bool copyImage(const QString &path, const QString &destinationDirectory);
    Q_INVOKABLE bool moveImage(const QString &path, const QString &destinationDirectory);
    Q_INVOKABLE bool moveToTrash(const QString &path);
    Q_INVOKABLE QString canonicalUserHome() const;
    Q_INVOKABLE QString defaultPicturesPath() const;
    Q_INVOKABLE QString defaultVideosPath() const;
    Q_INVOKABLE QString screenshotsPath() const;
    Q_INVOKABLE QString recordingsPath() const;
    Q_INVOKABLE QString parentDirectory(const QString &path) const;
    Q_INVOKABLE QVariantList directoryEntries(const QString &path) const;
    Q_INVOKABLE QStringList suggestedLibraryRoots() const;
    Q_INVOKABLE bool addLibraryRoot(const QString &path);
    Q_INVOKABLE bool removeLibraryRoot(const QString &path);
    Q_INVOKABLE QStringList supportedExtensions() const;
    Q_INVOKABLE QStringList supportedImageExtensions() const;
    Q_INVOKABLE QStringList supportedVideoExtensions() const;

signals:
    void busyChanged();
    void errorChanged();
    void itemsChanged();
    void albumsChanged();
    void rootsChanged();
    void operationCompleted(const QString &action, const QString &path);
    void operationFailed(const QString &message);

private:
    static QVariantList scanRoots(const QStringList &roots,
                                  const QSet<QString> &favorites,
                                  const QVariantMap &cachedMetadata,
                                  const QString &screenshotsPath,
                                  const QString &recordingsPath,
                                  const QString &thumbnailDirectory);
    static QVariantMap imageMetadata(const QString &path,
                                     const QSet<QString> &favorites,
                                     const QString &screenshotsPath,
                                     const QVariantMap &cached = {});
    static QVariantMap videoMetadata(const QString &path,
                                     const QSet<QString> &favorites,
                                     const QString &recordingsPath,
                                     const QString &thumbnailDirectory,
                                     const QVariantMap &cached = {});
    static QString uniqueDestination(const QString &desiredPath);
    static bool copyFileAtomic(const QString &source, const QString &destination, QString *error);
    static bool cacheEntryMatches(const QVariantMap &cached, const QFileInfo &info);
    static QString mediaCategory(const QString &path,
                                 const QString &mediaType,
                                 const QString &screenshotsPath,
                                 const QString &recordingsPath);
    void setBusy(bool busy);
    void setError(const QString &error);
    void rebuildAlbums();
    void loadFavorites();
    void loadRoots();
    void loadMediaCache();
    bool saveRoots() const;
    bool saveFavorites() const;
    bool saveMediaCache() const;
    QString favoritesFile() const;
    QString rootsFile() const;
    QString mediaCacheFile() const;
    QString thumbnailsDirectory() const;

    QString m_neutronRoot;
    bool m_busy = false;
    QString m_error;
    QVariantList m_items;
    QVariantList m_albums;
    QStringList m_roots;
    QSet<QString> m_favorites;
    QVariantMap m_cachedMetadata;
    QFutureWatcher<QVariantList> m_scanWatcher;
};
