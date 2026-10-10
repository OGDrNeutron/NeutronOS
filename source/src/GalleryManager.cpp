#include "GalleryManager.h"

#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>
#include <utility>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTransform>
#include <QUrl>

namespace {
QString normalizedPath(const QString &path)
{
    QFileInfo info(path);
    const QString canonical = info.canonicalFilePath();
    return QDir::cleanPath(canonical.isEmpty() ? info.absoluteFilePath() : canonical);
}

QString humanSize(quint64 bytes)
{
    static const QStringList units = {QStringLiteral("B"), QStringLiteral("KB"),
                                      QStringLiteral("MB"), QStringLiteral("GB"),
                                      QStringLiteral("TB")};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < units.size() - 1) {
        value /= 1024.0;
        ++unit;
    }
    return unit == 0
        ? QStringLiteral("%1 %2").arg(static_cast<qulonglong>(bytes)).arg(units.at(unit))
        : QStringLiteral("%1 %2").arg(value, 0, 'f', 1).arg(units.at(unit));
}

QString humanDuration(qint64 milliseconds)
{
    if (milliseconds <= 0)
        return QStringLiteral("0:00");
    const qint64 totalSeconds = milliseconds / 1000;
    const qint64 hours = totalSeconds / 3600;
    const qint64 minutes = (totalSeconds % 3600) / 60;
    const qint64 seconds = totalSeconds % 60;
    if (hours > 0)
        return QStringLiteral("%1:%2:%3").arg(hours).arg(minutes, 2, 10, QLatin1Char('0')).arg(seconds, 2, 10, QLatin1Char('0'));
    return QStringLiteral("%1:%2").arg(minutes).arg(seconds, 2, 10, QLatin1Char('0'));
}

QString canonicalHomeForRoot(const QString &neutronRoot)
{
    const QString overrideHome = qEnvironmentVariable("NEUTRONOS_USER_HOME").trimmed();
    if (!overrideHome.isEmpty() && QDir(overrideHome).exists())
        return QDir::cleanPath(QFileInfo(overrideHome).absoluteFilePath());

    QFileInfo rootInfo(neutronRoot);
    QString resolved = rootInfo.canonicalFilePath();
    if (resolved.isEmpty())
        resolved = rootInfo.absoluteFilePath();
    QDir rootDir(QDir::cleanPath(resolved));
    if (rootDir.dirName().compare(QStringLiteral("NeutronOS"), Qt::CaseInsensitive) == 0 && rootDir.cdUp())
        return rootDir.absolutePath();
    return QDir::cleanPath(QDir::homePath());
}

QVariantList browsableDirectories(const QString &requestedPath, const QString &fallbackPath)
{
    QString path = QDir::cleanPath(QFileInfo(requestedPath).absoluteFilePath());
    if (!QDir(path).exists())
        path = fallbackPath;
    QVariantList entries;
    QDir directory(path);
    const QFileInfoList directories = directory.entryInfoList(
        QDir::Dirs | QDir::Readable | QDir::NoDotAndDotDot,
        QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &info : directories) {
        QVariantMap entry;
        entry.insert(QStringLiteral("name"), info.fileName());
        entry.insert(QStringLiteral("path"), QDir::cleanPath(info.absoluteFilePath()));
        entry.insert(QStringLiteral("writable"), info.isWritable());
        entry.insert(QStringLiteral("mediaCount"), 0);
        entries.append(entry);
    }
    return entries;
}

QSet<QString> imageExtensions()
{
    QSet<QString> result;
    for (const QByteArray &format : QImageReader::supportedImageFormats())
        result.insert(QString::fromLatin1(format).toLower());
    return result;
}

QSet<QString> videoExtensions()
{
    return {QStringLiteral("mp4"), QStringLiteral("m4v"), QStringLiteral("mkv"),
            QStringLiteral("mov"), QStringLiteral("avi"), QStringLiteral("webm"),
            QStringLiteral("mpeg"), QStringLiteral("mpg"), QStringLiteral("ts"),
            QStringLiteral("mts"), QStringLiteral("m2ts"), QStringLiteral("wmv"),
            QStringLiteral("flv"), QStringLiteral("ogv"), QStringLiteral("3gp")};
}

bool pathWithin(const QString &path, const QString &root)
{
    const QString cleanPath = QDir::cleanPath(QFileInfo(path).absoluteFilePath());
    const QString cleanRoot = QDir::cleanPath(QFileInfo(root).absoluteFilePath());
    return cleanPath == cleanRoot || cleanPath.startsWith(cleanRoot + QLatin1Char('/'));
}
}

GalleryManager::GalleryManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot))
{
    connect(&m_scanWatcher, &QFutureWatcher<QVariantList>::finished, this, [this]() {
        m_items = m_scanWatcher.result();
        m_cachedMetadata.clear();
        for (const QVariant &value : std::as_const(m_items)) {
            const QVariantMap item = value.toMap();
            const QString path = normalizedPath(item.value(QStringLiteral("path")).toString());
            if (!path.isEmpty())
                m_cachedMetadata.insert(path, item);
        }
        saveMediaCache();
        rebuildAlbums();
        setBusy(false);
        emit itemsChanged();
        emit albumsChanged();
    });
}

bool GalleryManager::busy() const { return m_busy; }
QString GalleryManager::error() const { return m_error; }
QVariantList GalleryManager::items() const { return m_items; }
QVariantList GalleryManager::albums() const { return m_albums; }
QStringList GalleryManager::roots() const { return m_roots; }
int GalleryManager::mediaCount() const { return m_items.size(); }

int GalleryManager::imageCount() const
{
    int count = 0;
    for (const QVariant &value : m_items)
        count += value.toMap().value(QStringLiteral("mediaType")).toString() == QStringLiteral("image") ? 1 : 0;
    return count;
}

int GalleryManager::videoCount() const
{
    int count = 0;
    for (const QVariant &value : m_items)
        count += value.toMap().value(QStringLiteral("mediaType")).toString() == QStringLiteral("video") ? 1 : 0;
    return count;
}

int GalleryManager::screenshotCount() const
{
    int count = 0;
    for (const QVariant &value : m_items)
        count += value.toMap().value(QStringLiteral("category")).toString() == QStringLiteral("screenshot") ? 1 : 0;
    return count;
}

int GalleryManager::recordingCount() const
{
    int count = 0;
    for (const QVariant &value : m_items)
        count += value.toMap().value(QStringLiteral("category")).toString() == QStringLiteral("recording") ? 1 : 0;
    return count;
}

QString GalleryManager::canonicalUserHome() const
{
    return canonicalHomeForRoot(m_neutronRoot);
}

QString GalleryManager::defaultPicturesPath() const
{
    return QDir(canonicalUserHome()).filePath(QStringLiteral("Pictures"));
}

QString GalleryManager::defaultVideosPath() const
{
    return QDir(canonicalUserHome()).filePath(QStringLiteral("Videos"));
}

QString GalleryManager::screenshotsPath() const
{
    return QDir(defaultPicturesPath()).filePath(QStringLiteral("NeutronOS/Screenshots"));
}

QString GalleryManager::recordingsPath() const
{
    return QDir(defaultVideosPath()).filePath(QStringLiteral("NeutronOS/Recordings"));
}

QString GalleryManager::parentDirectory(const QString &path) const
{
    QDir directory(QDir::cleanPath(QFileInfo(path).absoluteFilePath()));
    if (!directory.exists())
        directory.setPath(canonicalUserHome());
    if (!directory.cdUp())
        return directory.absolutePath();
    return directory.absolutePath();
}

QVariantList GalleryManager::directoryEntries(const QString &path) const
{
    return browsableDirectories(path, canonicalUserHome());
}

QStringList GalleryManager::suggestedLibraryRoots() const
{
    QStringList candidates{defaultPicturesPath(), defaultVideosPath(), screenshotsPath(), recordingsPath()};
    const QString processPictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    const QString processVideos = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    if (!processPictures.isEmpty())
        candidates.append(QDir::cleanPath(processPictures));
    if (!processVideos.isEmpty())
        candidates.append(QDir::cleanPath(processVideos));
    candidates.append(QDir(m_neutronRoot).filePath(QStringLiteral("Pictures")));
    candidates.append(QDir(m_neutronRoot).filePath(QStringLiteral("Videos")));
    candidates.append(QStringLiteral("/root/Pictures"));
    candidates.append(QStringLiteral("/root/Videos"));

    QStringList result;
    for (const QString &candidate : candidates) {
        const QString cleaned = QDir::cleanPath(QFileInfo(candidate).absoluteFilePath());
        if (QDir(cleaned).exists() && QDir(cleaned).isReadable() && !result.contains(cleaned))
            result.append(cleaned);
    }
    return result;
}

bool GalleryManager::addLibraryRoot(const QString &path)
{
    const QString cleaned = normalizedPath(path);
    if (!QDir(cleaned).exists()) {
        setError(QStringLiteral("Media folder does not exist: %1").arg(path));
        return false;
    }
    if (!m_roots.contains(cleaned)) {
        m_roots.append(cleaned);
        m_roots.removeDuplicates();
        saveRoots();
        emit rootsChanged();
    }
    refresh();
    return true;
}

bool GalleryManager::removeLibraryRoot(const QString &path)
{
    const QString cleaned = normalizedPath(path);
    const QStringList protectedRoots{normalizedPath(defaultPicturesPath()), normalizedPath(defaultVideosPath()),
                                     normalizedPath(screenshotsPath()), normalizedPath(recordingsPath())};
    if (protectedRoots.contains(cleaned))
        return false;
    if (!m_roots.removeOne(cleaned))
        return false;
    saveRoots();
    emit rootsChanged();
    refresh();
    return true;
}

QStringList GalleryManager::supportedImageExtensions() const
{
    QStringList result = imageExtensions().values();
    result.sort(Qt::CaseInsensitive);
    return result;
}

QStringList GalleryManager::supportedVideoExtensions() const
{
    QStringList result = videoExtensions().values();
    result.sort(Qt::CaseInsensitive);
    return result;
}

QStringList GalleryManager::supportedExtensions() const
{
    QStringList result = supportedImageExtensions();
    result.append(supportedVideoExtensions());
    result.removeDuplicates();
    result.sort(Qt::CaseInsensitive);
    return result;
}

void GalleryManager::initialize()
{
    QDir().mkpath(defaultPicturesPath());
    QDir().mkpath(defaultVideosPath());
    QDir().mkpath(screenshotsPath());
    QDir().mkpath(recordingsPath());
    QDir().mkpath(thumbnailsDirectory());
    QDir().mkpath(QDir(m_neutronRoot).filePath(QStringLiteral("state/gallery")));
    loadFavorites();
    loadMediaCache();
    loadRoots();
    const QStringList suggested = suggestedLibraryRoots();
    for (const QString &path : suggested) {
        const QString cleaned = normalizedPath(path);
        if (QDir(cleaned).exists() && !m_roots.contains(cleaned))
            m_roots.append(cleaned);
    }
    const QStringList required{normalizedPath(defaultPicturesPath()), normalizedPath(defaultVideosPath()),
                               normalizedPath(screenshotsPath()), normalizedPath(recordingsPath())};
    for (const QString &path : required) {
        if (!m_roots.contains(path))
            m_roots.append(path);
    }
    m_roots.removeDuplicates();
    saveRoots();
    emit rootsChanged();
    refresh();
}

void GalleryManager::refresh()
{
    scan(m_roots.isEmpty()
             ? QStringList{defaultPicturesPath(), defaultVideosPath(), screenshotsPath(), recordingsPath()}
             : m_roots);
}

void GalleryManager::scan(const QStringList &roots)
{
    if (m_busy)
        return;

    QStringList cleaned;
    for (const QString &root : roots) {
        const QString path = QDir::cleanPath(QFileInfo(root).absoluteFilePath());
        if (!path.isEmpty() && QDir(path).exists() && !cleaned.contains(path))
            cleaned.append(path);
    }
    if (cleaned.isEmpty())
        cleaned = {defaultPicturesPath(), defaultVideosPath()};

    m_roots = cleaned;
    emit rootsChanged();
    setError(QString());
    setBusy(true);

    const QSet<QString> favorites = m_favorites;
    const QVariantMap cached = m_cachedMetadata;
    const QString screenshots = screenshotsPath();
    const QString recordings = recordingsPath();
    const QString thumbnails = thumbnailsDirectory();
    m_scanWatcher.setFuture(QtConcurrent::run([cleaned, favorites, cached, screenshots, recordings, thumbnails]() {
        return GalleryManager::scanRoots(cleaned, favorites, cached, screenshots, recordings, thumbnails);
    }));
}

QVariantList GalleryManager::scanRoots(const QStringList &roots,
                                       const QSet<QString> &favorites,
                                       const QVariantMap &cachedMetadata,
                                       const QString &screenshotsPath,
                                       const QString &recordingsPath,
                                       const QString &thumbnailDirectory)
{
    QVariantList result;
    QSet<QString> seen;
    const QSet<QString> images = imageExtensions();
    const QSet<QString> videos = videoExtensions();

    for (const QString &root : roots) {
        QDirIterator iterator(root, QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                              QDirIterator::Subdirectories);
        while (iterator.hasNext()) {
            const QString path = normalizedPath(iterator.next());
            if (seen.contains(path))
                continue;
            const QFileInfo info(path);
            const QString extension = info.suffix().toLower();
            const QVariantMap cached = cachedMetadata.value(path).toMap();
            QVariantMap metadata;
            if (images.contains(extension))
                metadata = imageMetadata(path, favorites, screenshotsPath, cached);
            else if (videos.contains(extension))
                metadata = videoMetadata(path, favorites, recordingsPath, thumbnailDirectory, cached);
            if (!metadata.isEmpty()) {
                result.append(metadata);
                seen.insert(path);
            }
        }
    }

    std::sort(result.begin(), result.end(), [](const QVariant &left, const QVariant &right) {
        return left.toMap().value(QStringLiteral("modifiedMs")).toLongLong()
             > right.toMap().value(QStringLiteral("modifiedMs")).toLongLong();
    });
    return result;
}

bool GalleryManager::cacheEntryMatches(const QVariantMap &cached, const QFileInfo &info)
{
    return !cached.isEmpty()
        && cached.value(QStringLiteral("bytes")).toLongLong() == info.size()
        && cached.value(QStringLiteral("modifiedMs")).toLongLong() == info.lastModified().toMSecsSinceEpoch();
}

QString GalleryManager::mediaCategory(const QString &path,
                                      const QString &mediaType,
                                      const QString &screenshotsPath,
                                      const QString &recordingsPath)
{
    if (mediaType == QStringLiteral("image") && pathWithin(path, screenshotsPath))
        return QStringLiteral("screenshot");
    if (mediaType == QStringLiteral("video") && pathWithin(path, recordingsPath))
        return QStringLiteral("recording");
    return mediaType == QStringLiteral("video") ? QStringLiteral("video") : QStringLiteral("photo");
}

QVariantMap GalleryManager::imageMetadata(const QString &path,
                                          const QSet<QString> &favorites,
                                          const QString &screenshotsPath,
                                          const QVariantMap &cached)
{
    QFileInfo info(path);
    if (!info.exists() || !info.isFile())
        return {};

    QVariantMap item = cached;
    if (!cacheEntryMatches(cached, info) || cached.value(QStringLiteral("mediaType")).toString() != QStringLiteral("image")) {
        QImageReader reader(path);
        reader.setAutoTransform(true);
        const QSize size = reader.size();
        if (!size.isValid())
            return {};
        item.clear();
        item.insert(QStringLiteral("width"), size.width());
        item.insert(QStringLiteral("height"), size.height());
        item.insert(QStringLiteral("format"), QString::fromLatin1(reader.format()).toUpper());
        item.insert(QStringLiteral("portrait"), size.height() > size.width());
    }

    const QString normalized = normalizedPath(path);
    item.insert(QStringLiteral("path"), info.absoluteFilePath());
    item.insert(QStringLiteral("url"), QUrl::fromLocalFile(info.absoluteFilePath()).toString());
    item.insert(QStringLiteral("previewUrl"), QUrl::fromLocalFile(info.absoluteFilePath()).toString());
    item.insert(QStringLiteral("thumbnailUrl"), QUrl::fromLocalFile(info.absoluteFilePath()).toString());
    item.insert(QStringLiteral("name"), info.fileName());
    item.insert(QStringLiteral("baseName"), info.completeBaseName());
    item.insert(QStringLiteral("album"), info.dir().dirName().isEmpty() ? QStringLiteral("Pictures") : info.dir().dirName());
    item.insert(QStringLiteral("albumPath"), info.dir().absolutePath());
    item.insert(QStringLiteral("mediaType"), QStringLiteral("image"));
    item.insert(QStringLiteral("category"), mediaCategory(path, QStringLiteral("image"), screenshotsPath, QString()));
    item.insert(QStringLiteral("bytes"), static_cast<qlonglong>(info.size()));
    item.insert(QStringLiteral("sizeText"), humanSize(static_cast<quint64>(info.size())));
    item.insert(QStringLiteral("modified"), info.lastModified().toString(Qt::ISODateWithMs));
    item.insert(QStringLiteral("modifiedMs"), info.lastModified().toMSecsSinceEpoch());
    item.insert(QStringLiteral("favorite"), favorites.contains(normalized));
    item.insert(QStringLiteral("durationMs"), 0);
    item.insert(QStringLiteral("durationText"), QString());
    return item;
}

QVariantMap GalleryManager::videoMetadata(const QString &path,
                                          const QSet<QString> &favorites,
                                          const QString &recordingsPath,
                                          const QString &thumbnailDirectory,
                                          const QVariantMap &cached)
{
    QFileInfo info(path);
    if (!info.exists() || !info.isFile())
        return {};

    QVariantMap item = cached;
    const bool reusable = cacheEntryMatches(cached, info)
        && cached.value(QStringLiteral("mediaType")).toString() == QStringLiteral("video")
        && (cached.value(QStringLiteral("thumbnailPath")).toString().isEmpty()
            || QFileInfo::exists(cached.value(QStringLiteral("thumbnailPath")).toString()));

    if (!reusable) {
        item.clear();
        qint64 durationMs = 0;
        int width = 0;
        int height = 0;
        QString codec;

        QProcess probe;
        probe.start(QStringLiteral("ffprobe"),
                    {QStringLiteral("-v"), QStringLiteral("error"),
                     QStringLiteral("-print_format"), QStringLiteral("json"),
                     QStringLiteral("-show_streams"), QStringLiteral("-show_format"),
                     info.absoluteFilePath()});
        if (probe.waitForStarted(1500) && probe.waitForFinished(10000)) {
            const QJsonDocument document = QJsonDocument::fromJson(probe.readAllStandardOutput());
            const QJsonObject root = document.object();
            for (const QJsonValue &value : root.value(QStringLiteral("streams")).toArray()) {
                const QJsonObject stream = value.toObject();
                if (stream.value(QStringLiteral("codec_type")).toString() != QStringLiteral("video"))
                    continue;
                width = stream.value(QStringLiteral("width")).toInt();
                height = stream.value(QStringLiteral("height")).toInt();
                codec = stream.value(QStringLiteral("codec_name")).toString().toUpper();
                const double streamDuration = stream.value(QStringLiteral("duration")).toString().toDouble();
                if (streamDuration > 0.0)
                    durationMs = qRound64(streamDuration * 1000.0);
                break;
            }
            if (durationMs <= 0) {
                const double formatDuration = root.value(QStringLiteral("format")).toObject()
                                                  .value(QStringLiteral("duration")).toString().toDouble();
                if (formatDuration > 0.0)
                    durationMs = qRound64(formatDuration * 1000.0);
            }
        }

        const QByteArray digest = QCryptographicHash::hash(info.absoluteFilePath().toUtf8(), QCryptographicHash::Sha256).toHex();
        const QString thumbnailPath = QDir(thumbnailDirectory).filePath(QString::fromLatin1(digest.left(32)) + QStringLiteral(".jpg"));
        const QFileInfo thumbnailInfo(thumbnailPath);
        if (!thumbnailInfo.exists() || thumbnailInfo.lastModified() < info.lastModified()) {
            QDir().mkpath(thumbnailDirectory);
            QProcess thumbnailer;
            thumbnailer.start(QStringLiteral("ffmpeg"),
                              {QStringLiteral("-nostdin"), QStringLiteral("-loglevel"), QStringLiteral("error"),
                               QStringLiteral("-ss"), QStringLiteral("00:00:01.000"),
                               QStringLiteral("-i"), info.absoluteFilePath(),
                               QStringLiteral("-frames:v"), QStringLiteral("1"),
                               QStringLiteral("-vf"), QStringLiteral("scale=640:-2"),
                               QStringLiteral("-q:v"), QStringLiteral("3"),
                               QStringLiteral("-y"), thumbnailPath});
            if (!thumbnailer.waitForStarted(1500) || !thumbnailer.waitForFinished(15000) || thumbnailer.exitCode() != 0)
                QFile::remove(thumbnailPath);
        }

        item.insert(QStringLiteral("width"), width);
        item.insert(QStringLiteral("height"), height);
        item.insert(QStringLiteral("format"), codec.isEmpty() ? info.suffix().toUpper() : codec);
        item.insert(QStringLiteral("portrait"), height > width && width > 0);
        item.insert(QStringLiteral("durationMs"), durationMs);
        item.insert(QStringLiteral("durationText"), humanDuration(durationMs));
        item.insert(QStringLiteral("thumbnailPath"), QFileInfo::exists(thumbnailPath) ? thumbnailPath : QString());
    }

    const QString normalized = normalizedPath(path);
    const QString thumbnailPath = item.value(QStringLiteral("thumbnailPath")).toString();
    item.insert(QStringLiteral("path"), info.absoluteFilePath());
    item.insert(QStringLiteral("url"), QUrl::fromLocalFile(info.absoluteFilePath()).toString());
    item.insert(QStringLiteral("previewUrl"), thumbnailPath.isEmpty() ? QString() : QUrl::fromLocalFile(thumbnailPath).toString());
    item.insert(QStringLiteral("thumbnailUrl"), thumbnailPath.isEmpty() ? QString() : QUrl::fromLocalFile(thumbnailPath).toString());
    item.insert(QStringLiteral("name"), info.fileName());
    item.insert(QStringLiteral("baseName"), info.completeBaseName());
    item.insert(QStringLiteral("album"), info.dir().dirName().isEmpty() ? QStringLiteral("Videos") : info.dir().dirName());
    item.insert(QStringLiteral("albumPath"), info.dir().absolutePath());
    item.insert(QStringLiteral("mediaType"), QStringLiteral("video"));
    item.insert(QStringLiteral("category"), mediaCategory(path, QStringLiteral("video"), QString(), recordingsPath));
    item.insert(QStringLiteral("bytes"), static_cast<qlonglong>(info.size()));
    item.insert(QStringLiteral("sizeText"), humanSize(static_cast<quint64>(info.size())));
    item.insert(QStringLiteral("modified"), info.lastModified().toString(Qt::ISODateWithMs));
    item.insert(QStringLiteral("modifiedMs"), info.lastModified().toMSecsSinceEpoch());
    item.insert(QStringLiteral("favorite"), favorites.contains(normalized));
    return item;
}

QVariantMap GalleryManager::metadata(const QString &path) const
{
    const QString normalized = normalizedPath(path);
    for (const QVariant &value : m_items) {
        const QVariantMap item = value.toMap();
        if (normalizedPath(item.value(QStringLiteral("path")).toString()) == normalized)
            return item;
    }
    return {};
}

bool GalleryManager::toggleFavorite(const QString &path)
{
    const QString normalized = normalizedPath(path);
    if (normalized.isEmpty() || !QFileInfo::exists(normalized)) {
        setError(QStringLiteral("Media file does not exist."));
        return false;
    }
    if (m_favorites.contains(normalized))
        m_favorites.remove(normalized);
    else
        m_favorites.insert(normalized);
    if (!saveFavorites())
        return false;

    for (QVariant &value : m_items) {
        QVariantMap map = value.toMap();
        if (normalizedPath(map.value(QStringLiteral("path")).toString()) == normalized) {
            map.insert(QStringLiteral("favorite"), m_favorites.contains(normalized));
            value = map;
            m_cachedMetadata.insert(normalized, map);
            break;
        }
    }
    saveMediaCache();
    emit itemsChanged();
    emit operationCompleted(QStringLiteral("favorite"), normalized);
    return true;
}

bool GalleryManager::isFavorite(const QString &path) const
{
    return m_favorites.contains(normalizedPath(path));
}

bool GalleryManager::rotateImage(const QString &path, int degrees)
{
    const QString normalized = normalizedPath(path);
    const QVariantMap item = metadata(normalized);
    if (item.value(QStringLiteral("mediaType")).toString() != QStringLiteral("image")) {
        setError(QStringLiteral("Only images can be rotated."));
        emit operationFailed(m_error);
        return false;
    }
    QImageReader reader(normalized);
    reader.setAutoTransform(true);
    QImage image = reader.read();
    if (image.isNull()) {
        setError(reader.errorString().isEmpty() ? QStringLiteral("Image could not be decoded.")
                                                : reader.errorString());
        emit operationFailed(m_error);
        return false;
    }

    const int rotation = ((degrees % 360) + 360) % 360;
    if (rotation == 0)
        return true;
    image = image.transformed(QTransform().rotate(rotation), Qt::SmoothTransformation);

    QSaveFile output(normalized);
    if (!output.open(QIODevice::WriteOnly)) {
        setError(output.errorString());
        emit operationFailed(m_error);
        return false;
    }
    QByteArray format = reader.format();
    if (format.isEmpty())
        format = QFileInfo(normalized).suffix().toLatin1();
    QImageWriter writer(&output, format);
    writer.setQuality(94);
    if (!writer.write(image) || !output.commit()) {
        setError(writer.errorString().isEmpty() ? output.errorString() : writer.errorString());
        emit operationFailed(m_error);
        return false;
    }
    m_cachedMetadata.remove(normalized);
    emit operationCompleted(QStringLiteral("rotate"), normalized);
    refresh();
    return true;
}

QString GalleryManager::uniqueDestination(const QString &desiredPath)
{
    QFileInfo info(desiredPath);
    if (!info.exists())
        return desiredPath;
    const QString directory = info.dir().absolutePath();
    const QString base = info.completeBaseName();
    const QString suffix = info.suffix();
    for (int index = 2; index < 10000; ++index) {
        const QString name = suffix.isEmpty()
            ? QStringLiteral("%1 (%2)").arg(base).arg(index)
            : QStringLiteral("%1 (%2).%3").arg(base).arg(index).arg(suffix);
        const QString candidate = QDir(directory).filePath(name);
        if (!QFileInfo::exists(candidate))
            return candidate;
    }
    return QDir(directory).filePath(QStringLiteral("%1-%2.%3")
        .arg(base, QString::number(QDateTime::currentMSecsSinceEpoch()), suffix));
}

bool GalleryManager::copyFileAtomic(const QString &source, const QString &destination, QString *error)
{
    QFile input(source);
    if (!input.open(QIODevice::ReadOnly)) {
        if (error) *error = input.errorString();
        return false;
    }
    QSaveFile output(destination);
    if (!output.open(QIODevice::WriteOnly)) {
        if (error) *error = output.errorString();
        return false;
    }
    while (!input.atEnd()) {
        const QByteArray block = input.read(1024 * 1024);
        if (block.isEmpty() && input.error() != QFileDevice::NoError) {
            if (error) *error = input.errorString();
            return false;
        }
        if (output.write(block) != block.size()) {
            if (error) *error = output.errorString();
            return false;
        }
    }
    if (!output.commit()) {
        if (error) *error = output.errorString();
        return false;
    }
    return true;
}

bool GalleryManager::copyMedia(const QString &path, const QString &destinationDirectory)
{
    const QString source = normalizedPath(path);
    QDir destination(destinationDirectory);
    if (!QFileInfo(source).isFile() || !destination.exists()) {
        setError(QStringLiteral("Source media or destination folder is unavailable."));
        emit operationFailed(m_error);
        return false;
    }
    const QString target = uniqueDestination(destination.filePath(QFileInfo(source).fileName()));
    QString message;
    if (!copyFileAtomic(source, target, &message)) {
        setError(message);
        emit operationFailed(m_error);
        return false;
    }
    emit operationCompleted(QStringLiteral("copy"), target);
    refresh();
    return true;
}

bool GalleryManager::moveMedia(const QString &path, const QString &destinationDirectory)
{
    const QString source = normalizedPath(path);
    QDir destination(destinationDirectory);
    if (!QFileInfo(source).isFile() || !destination.exists()) {
        setError(QStringLiteral("Source media or destination folder is unavailable."));
        emit operationFailed(m_error);
        return false;
    }
    const QString target = uniqueDestination(destination.filePath(QFileInfo(source).fileName()));
    if (!QFile::rename(source, target)) {
        QString message;
        if (!copyFileAtomic(source, target, &message) || !QFile::remove(source)) {
            setError(message.isEmpty() ? QStringLiteral("Media could not be moved.") : message);
            emit operationFailed(m_error);
            return false;
        }
    }
    if (m_favorites.remove(source) > 0) {
        m_favorites.insert(normalizedPath(target));
        saveFavorites();
    }
    m_cachedMetadata.remove(source);
    emit operationCompleted(QStringLiteral("move"), target);
    refresh();
    return true;
}

bool GalleryManager::copyImage(const QString &path, const QString &destinationDirectory)
{
    return copyMedia(path, destinationDirectory);
}

bool GalleryManager::moveImage(const QString &path, const QString &destinationDirectory)
{
    return moveMedia(path, destinationDirectory);
}

bool GalleryManager::moveToTrash(const QString &path)
{
    const QString source = normalizedPath(path);
    if (!QFileInfo(source).isFile()) {
        setError(QStringLiteral("Media file does not exist."));
        emit operationFailed(m_error);
        return false;
    }
    const QString trash = QDir(canonicalUserHome()).filePath(QStringLiteral(".local/share/Trash/files"));
    QDir().mkpath(trash);
    const QString target = uniqueDestination(QDir(trash).filePath(QFileInfo(source).fileName()));
    if (!QFile::rename(source, target)) {
        QString message;
        if (!copyFileAtomic(source, target, &message) || !QFile::remove(source)) {
            setError(message.isEmpty() ? QStringLiteral("Media could not be moved to Trash.") : message);
            emit operationFailed(m_error);
            return false;
        }
    }
    m_favorites.remove(source);
    m_cachedMetadata.remove(source);
    saveFavorites();
    saveMediaCache();
    emit operationCompleted(QStringLiteral("trash"), target);
    refresh();
    return true;
}

void GalleryManager::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void GalleryManager::setError(const QString &error)
{
    if (m_error == error)
        return;
    m_error = error;
    emit errorChanged();
}

void GalleryManager::rebuildAlbums()
{
    QMap<QString, QVariantMap> grouped;
    for (const QVariant &value : std::as_const(m_items)) {
        const QVariantMap media = value.toMap();
        const QString path = media.value(QStringLiteral("albumPath")).toString();
        QVariantMap album = grouped.value(path);
        if (album.isEmpty()) {
            album.insert(QStringLiteral("path"), path);
            album.insert(QStringLiteral("name"), media.value(QStringLiteral("album")));
            album.insert(QStringLiteral("count"), 0);
            album.insert(QStringLiteral("coverUrl"), media.value(QStringLiteral("previewUrl")));
        }
        album.insert(QStringLiteral("count"), album.value(QStringLiteral("count")).toInt() + 1);
        grouped.insert(path, album);
    }
    m_albums.clear();
    for (auto iterator = grouped.cbegin(); iterator != grouped.cend(); ++iterator)
        m_albums.append(iterator.value());
}

void GalleryManager::loadRoots()
{
    m_roots.clear();
    QFile input(rootsFile());
    if (!input.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(input.readAll());
    const QJsonArray values = document.object().value(QStringLiteral("roots")).toArray();
    for (const QJsonValue &value : values) {
        const QString path = normalizedPath(value.toString());
        if (QDir(path).exists() && !m_roots.contains(path))
            m_roots.append(path);
    }
}

bool GalleryManager::saveRoots() const
{
    QJsonArray values;
    for (const QString &path : m_roots)
        values.append(path);
    QJsonObject object;
    object.insert(QStringLiteral("schema"), 2);
    object.insert(QStringLiteral("roots"), values);
    QSaveFile output(rootsFile());
    if (!output.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    output.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    return output.commit();
}

QString GalleryManager::rootsFile() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/gallery/roots.json"));
}

QString GalleryManager::favoritesFile() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/gallery/favorites.json"));
}

QString GalleryManager::mediaCacheFile() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/gallery/media-cache.json"));
}

QString GalleryManager::thumbnailsDirectory() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/gallery/thumbnails"));
}

void GalleryManager::loadFavorites()
{
    m_favorites.clear();
    QFile file(favoritesFile());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    for (const QJsonValue &value : document.object().value(QStringLiteral("favorites")).toArray())
        m_favorites.insert(normalizedPath(value.toString()));
}

bool GalleryManager::saveFavorites() const
{
    QJsonArray array;
    QStringList paths = m_favorites.values();
    paths.sort(Qt::CaseInsensitive);
    for (const QString &path : paths)
        array.append(path);
    QJsonObject object;
    object.insert(QStringLiteral("schema"), 2);
    object.insert(QStringLiteral("favorites"), array);
    QDir().mkpath(QFileInfo(favoritesFile()).dir().absolutePath());
    QSaveFile file(favoritesFile());
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    return file.commit();
}

void GalleryManager::loadMediaCache()
{
    m_cachedMetadata.clear();
    QFile file(mediaCacheFile());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonObject entries = QJsonDocument::fromJson(file.readAll()).object().value(QStringLiteral("entries")).toObject();
    for (auto iterator = entries.begin(); iterator != entries.end(); ++iterator) {
        const QString path = normalizedPath(iterator.key());
        if (QFileInfo::exists(path))
            m_cachedMetadata.insert(path, iterator.value().toObject().toVariantMap());
    }
}

bool GalleryManager::saveMediaCache() const
{
    QJsonObject entries;
    for (auto iterator = m_cachedMetadata.cbegin(); iterator != m_cachedMetadata.cend(); ++iterator)
        entries.insert(iterator.key(), QJsonObject::fromVariantMap(iterator.value().toMap()));
    QJsonObject root;
    root.insert(QStringLiteral("schema"), 2);
    root.insert(QStringLiteral("savedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    root.insert(QStringLiteral("entries"), entries);
    QDir().mkpath(QFileInfo(mediaCacheFile()).dir().absolutePath());
    QSaveFile file(mediaCacheFile());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return file.commit();
}
