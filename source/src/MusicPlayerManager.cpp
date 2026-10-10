#include "MusicPlayerManager.h"

#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>
#include <cmath>
#include <limits>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QMap>
#include <QMetaObject>
#include <QPointer>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>

namespace {
const QStringList kAudioExtensions = {
    QStringLiteral("aac"), QStringLiteral("aiff"), QStringLiteral("alac"),
    QStringLiteral("ape"), QStringLiteral("flac"), QStringLiteral("m4a"),
    QStringLiteral("mp3"), QStringLiteral("mp4"), QStringLiteral("oga"),
    QStringLiteral("ogg"), QStringLiteral("opus"), QStringLiteral("wav"),
    QStringLiteral("wma")
};

QString firstNonEmpty(const QJsonObject &object,
                      const QStringList &keys,
                      const QString &fallback = QString())
{
    for (const QString &key : keys) {
        const QString value = object.value(key).toVariant().toString().trimmed();
        if (!value.isEmpty())
            return value;
    }
    return fallback;
}

QString durationText(qint64 milliseconds)
{
    const qint64 totalSeconds = std::max<qint64>(0, milliseconds / 1000);
    const qint64 hours = totalSeconds / 3600;
    const qint64 minutes = (totalSeconds % 3600) / 60;
    const qint64 seconds = totalSeconds % 60;
    if (hours > 0)
        return QStringLiteral("%1:%2:%3")
            .arg(hours)
            .arg(minutes, 2, 10, QLatin1Char('0'))
            .arg(seconds, 2, 10, QLatin1Char('0'));
    return QStringLiteral("%1:%2")
        .arg(minutes)
        .arg(seconds, 2, 10, QLatin1Char('0'));
}

bool writeJsonFile(const QString &path, const QJsonDocument &document)
{
    QSaveFile output(path);
    if (!output.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    if (output.write(document.toJson(QJsonDocument::Indented)) < 0)
        return false;
    return output.commit();
}

QJsonDocument readJsonFile(const QString &path)
{
    QFile input(path);
    if (!input.open(QIODevice::ReadOnly))
        return {};
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(input.readAll(), &error);
    return error.error == QJsonParseError::NoError ? document : QJsonDocument();
}

QString extractArtwork(const QString &ffmpeg,
                       const QString &source,
                       const QString &target)
{
    const QString missingMarker = target + QStringLiteral(".none");
    if (QFileInfo::exists(target))
        return target;
    if (ffmpeg.isEmpty() || QFileInfo::exists(missingMarker))
        return {};

    QProcess process;
    process.setProgram(ffmpeg);
    process.setArguments({
        QStringLiteral("-v"), QStringLiteral("error"),
        QStringLiteral("-y"),
        QStringLiteral("-i"), source,
        QStringLiteral("-an"),
        QStringLiteral("-map"), QStringLiteral("0:v:0?"),
        QStringLiteral("-frames:v"), QStringLiteral("1"),
        QStringLiteral("-vf"), QStringLiteral("scale='min(640,iw)':-2"),
        QStringLiteral("-q:v"), QStringLiteral("3"),
        target
    });
    process.start();
    if (!process.waitForStarted(2500))
        return {};
    if (!process.waitForFinished(12000)) {
        process.kill();
        process.waitForFinished(1000);
        return {};
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 ||
        !QFileInfo(target).isFile() || QFileInfo(target).size() <= 0) {
        QFile::remove(target);
        QFile marker(missingMarker);
        if (marker.open(QIODevice::WriteOnly | QIODevice::Truncate))
            marker.write("no-embedded-art\n");
        return {};
    }
    QFile::remove(missingMarker);
    return target;
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

    const QString home = QDir::homePath();
    return QDir::cleanPath(home);
}

bool directoryContainsAudio(const QString &path)
{
    QDir directory(path);
    if (!directory.exists() || !directory.isReadable())
        return false;
    QDirIterator iterator(path, QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                          QDirIterator::Subdirectories);
    int checked = 0;
    while (iterator.hasNext() && checked < 5000) {
        const QFileInfo info(iterator.next());
        ++checked;
        if (kAudioExtensions.contains(info.suffix().toLower()))
            return true;
    }
    return false;
}

bool pathIsInside(const QString &candidate, const QString &root)
{
    const QString cleanCandidate = QDir::cleanPath(candidate);
    QString cleanRoot = QDir::cleanPath(root);
    if (!cleanRoot.endsWith(QLatin1Char('/')))
        cleanRoot.append(QLatin1Char('/'));
    return cleanCandidate == QDir::cleanPath(root) || cleanCandidate.startsWith(cleanRoot);
}

QString friendlyAudioOutputName(const QString &id, const QString &description, int &hdmiIndex)
{
    const QString combined = (id + QLatin1Char(' ') + description).toLower();
    if (combined.contains(QStringLiteral("hdmi")))
        return QStringLiteral("HDMI%1").arg(hdmiIndex++);
    if (combined.contains(QStringLiteral("headphone")) ||
        combined.contains(QStringLiteral("analog-stereo")) ||
        combined.contains(QStringLiteral("bcm2835 headphones")))
        return QStringLiteral("Headphones");
    if (combined.contains(QStringLiteral("dualsense")) ||
        combined.contains(QStringLiteral("dualshock")) ||
        combined.contains(QStringLiteral("wireless controller")) ||
        combined.contains(QStringLiteral("gamepad")))
        return QStringLiteral("Controller");
    if (combined.contains(QStringLiteral("bluez")) || combined.contains(QStringLiteral("bluetooth")))
        return QStringLiteral("Bluetooth");
    if (combined.contains(QStringLiteral("usb")))
        return QStringLiteral("USB Audio");
    QString clean = description.trimmed();
    clean.remove(QRegularExpression(QStringLiteral("\\s*\\([^)]{20,}\\)\\s*$")));
    if (clean.size() > 28)
        clean = clean.left(25).trimmed() + QStringLiteral("…");
    return clean.isEmpty() ? QStringLiteral("Audio Device") : clean;
}


QString safeSongFileName(QString value)
{
    value = value.trimmed();
    value.replace(QRegularExpression(QStringLiteral("[\\\\/:*?\"<>|]+")), QStringLiteral(" "));
    value.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));
    value = value.trimmed();
    while (value.endsWith(QLatin1Char('.')) || value.endsWith(QLatin1Char(' ')))
        value.chop(1);
    return value.isEmpty() ? QStringLiteral("Unknown Song") : value.left(180);
}

QVariantMap inferSongIdentity(const QString &path, const QVariantMap &existing)
{
    QFileInfo info(path);
    QString stem = info.completeBaseName();
    stem.replace(QLatin1Char('_'), QLatin1Char(' '));
    stem.replace(QRegularExpression(QStringLiteral("^\\s*\\d{1,3}[ ._-]+")), QString());
    stem.replace(QRegularExpression(QStringLiteral("\\s*\\[(official|lyrics?|audio|video|explicit|clean)[^]]*\\]\\s*$"), QRegularExpression::CaseInsensitiveOption), QString());
    stem.replace(QRegularExpression(QStringLiteral("\\s*\\((official|lyrics?|audio|video)\\)\\s*$"), QRegularExpression::CaseInsensitiveOption), QString());
    stem = stem.simplified();

    QString artist = existing.value(QStringLiteral("artist")).toString().trimmed();
    QString title = existing.value(QStringLiteral("title")).toString().trimmed();
    QString featured;
    int inferredTrack = existing.value(QStringLiteral("trackNumber")).toInt();

    const QRegularExpression trackPrefix(QStringLiteral("^\\s*(\\d{1,3})[ ._-]+"));
    const QRegularExpressionMatch trackMatch = trackPrefix.match(info.completeBaseName());
    if (inferredTrack <= 0 && trackMatch.hasMatch())
        inferredTrack = trackMatch.captured(1).toInt();

    const QStringList pieces = stem.split(QRegularExpression(QStringLiteral("\\s+-\\s+")), Qt::SkipEmptyParts);
    if (pieces.size() >= 2) {
        artist = pieces.first().trimmed();
        title = pieces.mid(1).join(QStringLiteral(" - ")).trimmed();
    } else if (title.isEmpty() || title.compare(info.completeBaseName(), Qt::CaseInsensitive) == 0) {
        title = stem;
    }

    QRegularExpression featuring(QStringLiteral("(?:\\(|\\[)?\\s*(?:feat\\.?|ft\\.?|featuring)\\s+([^\\)\\]]+)(?:\\)|\\])?"), QRegularExpression::CaseInsensitiveOption);
    QRegularExpressionMatch match = featuring.match(title);
    if (match.hasMatch()) {
        featured = match.captured(1).trimmed();
        title.remove(match.capturedStart(), match.capturedLength());
        title = title.simplified();
    }
    if (featured.isEmpty()) {
        match = featuring.match(artist);
        if (match.hasMatch()) {
            featured = match.captured(1).trimmed();
            artist.remove(match.capturedStart(), match.capturedLength());
            artist = artist.simplified();
        }
    }

    title = safeSongFileName(title);
    if (artist.isEmpty()) artist = QStringLiteral("Unknown Artist");
    QString metadataArtist = artist;
    if (!featured.isEmpty()) metadataArtist += QStringLiteral(" feat. ") + featured;

    QVariantMap result;
    result.insert(QStringLiteral("path"), QDir::cleanPath(info.absoluteFilePath()));
    result.insert(QStringLiteral("currentName"), info.fileName());
    result.insert(QStringLiteral("title"), title);
    result.insert(QStringLiteral("artist"), artist);
    result.insert(QStringLiteral("featuredArtist"), featured);
    result.insert(QStringLiteral("metadataArtist"), metadataArtist);
    result.insert(QStringLiteral("album"), existing.value(QStringLiteral("album")).toString());
    result.insert(QStringLiteral("albumArtist"), existing.value(QStringLiteral("albumArtist")).toString());
    result.insert(QStringLiteral("genre"), existing.value(QStringLiteral("genre")).toString());
    result.insert(QStringLiteral("year"), existing.value(QStringLiteral("year")).toString());
    result.insert(QStringLiteral("trackNumber"), inferredTrack);
    result.insert(QStringLiteral("extension"), info.suffix().toLower());
    result.insert(QStringLiteral("proposedName"), title + (info.suffix().isEmpty() ? QString() : QStringLiteral(".") + info.suffix()));
    result.insert(QStringLiteral("changed"),
                  info.fileName().compare(result.value(QStringLiteral("proposedName")).toString(), Qt::CaseSensitive) != 0 ||
                  existing.value(QStringLiteral("title")).toString().trimmed() != title ||
                  existing.value(QStringLiteral("artist")).toString().trimmed() != metadataArtist ||
                  (inferredTrack > 0 && existing.value(QStringLiteral("trackNumber")).toInt() != inferredTrack));
    return result;
}

QString nonConflictingSongPath(const QString &directory, const QString &fileName, const QString &sourcePath)
{
    QFileInfo proposed(QDir(directory).filePath(fileName));
    if (QDir::cleanPath(proposed.absoluteFilePath()) == QDir::cleanPath(sourcePath) || !proposed.exists())
        return proposed.absoluteFilePath();
    const QString stem = proposed.completeBaseName();
    const QString suffix = proposed.suffix();
    for (int index = 2; index < 1000; ++index) {
        const QString candidateName = stem + QStringLiteral(" (%1)").arg(index) +
            (suffix.isEmpty() ? QString() : QStringLiteral(".") + suffix);
        const QString candidate = QDir(directory).filePath(candidateName);
        if (!QFileInfo::exists(candidate)) return candidate;
    }
    return QDir(directory).filePath(stem + QStringLiteral("-") + QUuid::createUuid().toString(QUuid::WithoutBraces) +
        (suffix.isEmpty() ? QString() : QStringLiteral(".") + suffix));
}

bool verifyAudioContainer(const QString &ffprobe, const QString &path)
{
    const QFileInfo info(path);
    if (!info.isFile() || info.size() <= 0)
        return false;
    if (ffprobe.isEmpty())
        return true;

    QProcess process;
    process.setProgram(ffprobe);
    process.setArguments({QStringLiteral("-v"), QStringLiteral("error"),
                          QStringLiteral("-show_entries"), QStringLiteral("format=duration"),
                          QStringLiteral("-of"), QStringLiteral("default=noprint_wrappers=1:nokey=1"),
                          path});
    process.start();
    if (!process.waitForStarted(2000) || !process.waitForFinished(15000)) {
        process.kill();
        process.waitForFinished(500);
        return false;
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
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

}

MusicPlayerManager::MusicPlayerManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot))
{
    m_spectrum.reserve(64);
    for (int i = 0; i < 64; ++i)
        m_spectrum.append(0.04);

    connect(&m_scanWatcher, &QFutureWatcher<ScanPayload>::finished, this, [this]() {
        const ScanPayload payload = m_scanWatcher.result();
        if (!payload.error.isEmpty()) {
            setError(payload.error);
            setBusy(false);
            emit scanFinished(false, payload.error);
            emit operationFinished(QStringLiteral("scan"), false, payload.error);
            return;
        }

        m_tracks = payload.tracks;
        m_libraryCache = payload.cache;
        rebuildCatalogs();
        pruneQueue();
        saveLibraryCache();
        setBusy(false);
        setStatus(QStringLiteral("Library ready — %1 tracks").arg(m_tracks.size()));
        emit tracksChanged();
        emit queueChanged();
        emit scanFinished(true, QStringLiteral("Music library contains %1 tracks.").arg(m_tracks.size()));
        emit operationFinished(QStringLiteral("scan"), true,
                               QStringLiteral("Music library contains %1 tracks.").arg(m_tracks.size()));
    });


    connect(&m_discoveryWatcher, &QFutureWatcher<DiscoveryPayload>::finished, this, [this]() {
        const DiscoveryPayload payload = m_discoveryWatcher.result();
        m_discoveryBusy = false;
        m_discoveryStatus = payload.error.isEmpty() ? payload.status : payload.error;
        if (!payload.error.isEmpty()) {
            setError(payload.error);
            emit operationFinished(QStringLiteral("discover-audio"), false, payload.error);
        } else {
            m_discoveredAudio = payload.files;
            emit discoveredAudioChanged();
            emit operationFinished(QStringLiteral("discover-audio"), true, payload.status);
        }
        emit discoveryStateChanged();
    });

    connect(&m_metadataRepairWatcher, &QFutureWatcher<MetadataRepairPayload>::finished, this, [this]() {
        const MetadataRepairPayload payload = m_metadataRepairWatcher.result();

        QMap<QString, QString> replacements;
        for (const QVariant &value : payload.changes) {
            const QVariantMap change = value.toMap();
            const QString oldPath = QDir::cleanPath(change.value(QStringLiteral("oldPath")).toString());
            const QString newPath = QDir::cleanPath(change.value(QStringLiteral("newPath")).toString());
            if (!oldPath.isEmpty() && !newPath.isEmpty())
                replacements.insert(oldPath, newPath);
        }

        if (!replacements.isEmpty()) {
            for (QString &path : m_queuePaths) {
                const QString normalized = QDir::cleanPath(path);
                if (replacements.contains(normalized))
                    path = replacements.value(normalized);
            }
            for (int i = 0; i < m_playlists.size(); ++i) {
                QVariantMap playlist = m_playlists.at(i).toMap();
                QStringList paths = playlist.value(QStringLiteral("paths")).toStringList();
                bool changed = false;
                for (QString &path : paths) {
                    const QString normalized = QDir::cleanPath(path);
                    if (replacements.contains(normalized)) {
                        path = replacements.value(normalized);
                        changed = true;
                    }
                }
                if (changed) {
                    paths.removeDuplicates();
                    playlist.insert(QStringLiteral("paths"), paths);
                    playlist.insert(QStringLiteral("trackCount"), paths.size());
                    m_playlists[i] = playlist;
                }
            }
            savePlaylists();
            emit playlistsChanged();
            emit queueChanged();
        }

        m_metadataRepairBusy = false;
        m_metadataRepairCurrent = m_metadataRepairTotal;
        const QString message = payload.failures.isEmpty()
            ? QStringLiteral("Updated filenames and embedded metadata for %1 song(s).").arg(payload.completed)
            : QStringLiteral("Updated %1 song(s); %2 item(s) could not be changed.")
                  .arg(payload.completed).arg(payload.failed);
        m_metadataRepairStatus = payload.error.isEmpty() ? message : payload.error;
        clearMetadataRepairPreview();
        setBusy(false);
        setStatus(m_metadataRepairStatus);
        if (!payload.error.isEmpty() || payload.failed > 0)
            setError(m_metadataRepairStatus);
        emit metadataRepairStateChanged();
        emit operationFinished(QStringLiteral("metadata-repair"),
                               payload.completed > 0 && payload.failed == 0 && payload.error.isEmpty(),
                               m_metadataRepairStatus);
        if (payload.completed > 0)
            refreshLibrary();
    });


    m_socketRetryTimer.setInterval(120);
    m_socketRetryTimer.setSingleShot(false);
    connect(&m_socketRetryTimer, &QTimer::timeout, this, &MusicPlayerManager::connectPlayerSocket);

    m_positionPollTimer.setInterval(500);
    connect(&m_positionPollTimer, &QTimer::timeout, this, [this]() {
        if (!m_playerConnected)
            return;
        queueCommand(QJsonArray{QStringLiteral("get_property"), QStringLiteral("time-pos")}, 9001);
        queueCommand(QJsonArray{QStringLiteral("get_property"), QStringLiteral("duration")}, 9002);
    });

    m_spectrumTimer.setInterval(33);
    connect(&m_spectrumTimer, &QTimer::timeout, this, &MusicPlayerManager::updateSpectrum);

    connect(&m_playerProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        setPlayerConnected(false);
        if (m_playerProcess.error() == QProcess::FailedToStart) {
            setPlayerAvailable(false);
            const QString message = QStringLiteral("mpv could not start. Install the mpv package to enable playback.");
            setError(message);
            emit playbackError(message);
        }
    });

    connect(&m_playerProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
        disconnectPlayerSocket();
        if (exitStatus == QProcess::CrashExit || (exitCode != 0 && m_playing)) {
            const QString message = QStringLiteral("The music playback process stopped unexpectedly.");
            setError(message);
            emit playbackError(message);
        }
        m_playing = false;
        m_paused = false;
        emit playbackStateChanged();
        updateVisualizationTimer();
    });

    connect(&m_playerSocket, &QLocalSocket::connected, this, [this]() {
        m_socketRetryTimer.stop();
        m_socketAttempts = 0;
        setPlayerConnected(true);
        sendObserveCommands();
        applyAudioOutput();
        applyEqualizer();
        setVolume(m_volume);
        flushCommands();
        m_positionPollTimer.start();
        setStatus(QStringLiteral("Player ready"));
    });

    connect(&m_playerSocket, &QLocalSocket::readyRead,
            this, &MusicPlayerManager::processSocketData);

    connect(&m_playerSocket, &QLocalSocket::disconnected, this, [this]() {
        setPlayerConnected(false);
        m_positionPollTimer.stop();
    });

    connect(&m_playerSocket, &QLocalSocket::errorOccurred, this,
            [this](QLocalSocket::LocalSocketError error) {
        if (error == QLocalSocket::ServerNotFoundError ||
            error == QLocalSocket::ConnectionRefusedError) {
            if (m_playerProcess.state() != QProcess::NotRunning && m_socketAttempts < 80)
                m_socketRetryTimer.start();
            return;
        }
        setPlayerConnected(false);
    });
}

MusicPlayerManager::~MusicPlayerManager()
{
    m_spectrumTimer.stop();
    if (m_metadataRepairWatcher.isRunning())
        m_metadataRepairWatcher.waitForFinished();
    saveSettings();
    savePlaylists();
    if (m_playerSocket.state() == QLocalSocket::ConnectedState) {
        QJsonObject quitObject;
        quitObject.insert(QStringLiteral("command"), QJsonArray{QStringLiteral("quit")});
        m_playerSocket.write(QJsonDocument(quitObject).toJson(QJsonDocument::Compact) + '\n');
        m_playerSocket.flush();
    }
    m_playerSocket.abort();
    if (m_playerProcess.state() != QProcess::NotRunning) {
        m_playerProcess.terminate();
        if (!m_playerProcess.waitForFinished(800)) {
            m_playerProcess.kill();
            m_playerProcess.waitForFinished(500);
        }
    }
    QFile::remove(socketPath());
}

bool MusicPlayerManager::initialized() const { return m_initialized; }
bool MusicPlayerManager::busy() const { return m_busy; }
bool MusicPlayerManager::playerAvailable() const { return m_playerAvailable; }
bool MusicPlayerManager::playerConnected() const { return m_playerConnected; }
QString MusicPlayerManager::status() const { return m_status; }
QString MusicPlayerManager::error() const { return m_error; }
QVariantList MusicPlayerManager::tracks() const { return m_tracks; }
QVariantList MusicPlayerManager::albums() const { return m_albums; }
QVariantList MusicPlayerManager::artists() const { return m_artists; }
QVariantList MusicPlayerManager::folders() const { return m_folders; }
QVariantList MusicPlayerManager::playlists() const { return m_playlists; }
QStringList MusicPlayerManager::libraryRoots() const { return m_libraryRoots; }
QVariantMap MusicPlayerManager::currentTrack() const { return m_currentTrack; }
int MusicPlayerManager::currentQueueIndex() const { return m_currentQueueIndex; }
bool MusicPlayerManager::playing() const { return m_playing; }
bool MusicPlayerManager::paused() const { return m_paused; }
qint64 MusicPlayerManager::positionMs() const { return m_positionMs; }
qint64 MusicPlayerManager::durationMs() const { return m_durationMs; }
int MusicPlayerManager::volume() const { return m_volume; }
bool MusicPlayerManager::shuffle() const { return m_shuffle; }
QString MusicPlayerManager::repeatMode() const { return m_repeatMode; }
QString MusicPlayerManager::equalizerPreset() const { return m_equalizerPreset; }
QVariantList MusicPlayerManager::audioOutputs() const { return m_audioOutputs; }
QString MusicPlayerManager::selectedAudioOutput() const { return m_selectedAudioOutput; }
QString MusicPlayerManager::visualizationMode() const { return m_visualizationMode; }
QVariantList MusicPlayerManager::spectrum() const { return m_spectrum; }
bool MusicPlayerManager::visualizationConsumerActive() const { return m_visualizationConsumerActive; }
bool MusicPlayerManager::discoveryBusy() const { return m_discoveryBusy; }
QString MusicPlayerManager::discoveryStatus() const { return m_discoveryStatus; }
QVariantList MusicPlayerManager::discoveredAudio() const { return m_discoveredAudio; }
QVariantList MusicPlayerManager::metadataRepairPreview() const { return m_metadataRepairPreview; }
bool MusicPlayerManager::metadataRepairBusy() const { return m_metadataRepairBusy; }
QString MusicPlayerManager::metadataRepairStatus() const { return m_metadataRepairStatus; }
int MusicPlayerManager::metadataRepairCurrent() const { return m_metadataRepairCurrent; }
int MusicPlayerManager::metadataRepairTotal() const { return m_metadataRepairTotal; }
qreal MusicPlayerManager::metadataRepairProgress() const
{
    return m_metadataRepairTotal > 0
        ? static_cast<qreal>(m_metadataRepairCurrent) / static_cast<qreal>(m_metadataRepairTotal)
        : 0.0;
}

QVariantList MusicPlayerManager::queue() const
{
    QVariantList result;
    result.reserve(m_queuePaths.size());
    for (const QString &path : m_queuePaths) {
        QVariantMap track = trackForPath(path);
        if (!track.isEmpty())
            result.append(track);
    }
    return result;
}

QStringList MusicPlayerManager::visualizationModes() const
{
    return {QStringLiteral("Pipes"), QStringLiteral("Spectrum"),
            QStringLiteral("Oscilloscope"), QStringLiteral("Particle Tunnel"),
            QStringLiteral("Plasma"), QStringLiteral("Starfield"), QStringLiteral("Cover Art"),
            QStringLiteral("Atom")};
}

QVariantList MusicPlayerManager::equalizerPresets() const
{
    return {
        QVariantMap{{QStringLiteral("name"), QStringLiteral("Flat")},
                    {QStringLiteral("description"), QStringLiteral("Unmodified output")}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("Bass Boost")},
                    {QStringLiteral("description"), QStringLiteral("Stronger low frequencies")}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("Warm")},
                    {QStringLiteral("description"), QStringLiteral("Smooth lows and restrained highs")}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("Vocal")},
                    {QStringLiteral("description"), QStringLiteral("Clearer speech and lead vocals")}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("Treble")},
                    {QStringLiteral("description"), QStringLiteral("Brighter high-frequency detail")}},
        QVariantMap{{QStringLiteral("name"), QStringLiteral("Night")},
                    {QStringLiteral("description"), QStringLiteral("Reduced extremes for quiet listening")}}
    };
}

void MusicPlayerManager::initialize()
{
    if (m_initialized)
        return;

    ensureStateDirectories();
    loadSettings();
    loadPlaylists();
    loadLibraryCache();
    refreshAudioOutputs();
    ensurePlayer();

    setInitialized(true);
    if (m_tracks.isEmpty())
        refreshLibrary();
    else {
        rebuildCatalogs();
        setStatus(QStringLiteral("Library ready — %1 tracks").arg(m_tracks.size()));
        emit tracksChanged();
    }
}

QString MusicPlayerManager::canonicalUserHome() const
{
    return canonicalHomeForRoot(m_neutronRoot);
}

QString MusicPlayerManager::defaultMusicPath() const
{
    return QDir(canonicalUserHome()).filePath(QStringLiteral("Music"));
}

QString MusicPlayerManager::parentDirectory(const QString &path) const
{
    QDir directory(QDir::cleanPath(QFileInfo(path).absoluteFilePath()));
    if (!directory.exists())
        directory.setPath(canonicalUserHome());
    if (!directory.cdUp())
        return directory.absolutePath();
    return directory.absolutePath();
}

QVariantList MusicPlayerManager::directoryEntries(const QString &path) const
{
    return browsableDirectories(path, canonicalUserHome());
}

QStringList MusicPlayerManager::suggestedLibraryRoots() const
{
    QStringList candidates{defaultMusicPath()};
    const QString processMusic = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (!processMusic.isEmpty())
        candidates.append(QDir::cleanPath(processMusic));
    candidates.append(QDir(m_neutronRoot).filePath(QStringLiteral("Music")));
    candidates.append(QStringLiteral("/root/Music"));

    QStringList result;
    for (const QString &candidate : candidates) {
        const QString cleaned = QDir::cleanPath(QFileInfo(candidate).absoluteFilePath());
        if (!result.contains(cleaned) && (cleaned == defaultMusicPath() || directoryContainsAudio(cleaned)))
            result.append(cleaned);
    }
    return result;
}

QStringList MusicPlayerManager::supportedExtensions() const
{
    return kAudioExtensions;
}

void MusicPlayerManager::refreshLibrary()
{
    scanLibrary(m_libraryRoots.isEmpty() ? QStringList{defaultMusicPath()} : m_libraryRoots);
}

void MusicPlayerManager::scanLibrary(const QStringList &roots)
{
    if (m_busy)
        return;

    QStringList cleaned;
    for (const QString &root : roots) {
        const QString path = QDir::cleanPath(QFileInfo(root).absoluteFilePath());
        if (QDir(path).exists() && !cleaned.contains(path))
            cleaned.append(path);
    }
    if (cleaned.isEmpty()) {
        QDir().mkpath(defaultMusicPath());
        cleaned.append(defaultMusicPath());
    }

    m_libraryRoots = cleaned;
    saveSettings();
    emit libraryRootsChanged();
    setError(QString());
    setBusy(true);
    setStatus(QStringLiteral("Scanning music library…"));

    const QVariantMap cache = m_libraryCache;
    const QString artDir = artworkDirectory();
    m_scanWatcher.setFuture(QtConcurrent::run([cleaned, cache, artDir]() {
        return MusicPlayerManager::scanRoots(cleaned, cache, artDir);
    }));
}

bool MusicPlayerManager::addLibraryRoot(const QString &path)
{
    const QString normalized = normalizedPath(path);
    if (!QDir(normalized).exists()) {
        const QString message = QStringLiteral("Music folder does not exist: %1").arg(path);
        setError(message);
        emit operationFinished(QStringLiteral("add-root"), false, message);
        return false;
    }
    if (!m_libraryRoots.contains(normalized)) {
        m_libraryRoots.append(normalized);
        saveSettings();
        emit libraryRootsChanged();
    }
    refreshLibrary();
    return true;
}

bool MusicPlayerManager::removeLibraryRoot(const QString &path)
{
    const QString normalized = normalizedPath(path);
    if (m_libraryRoots.size() <= 1 || !m_libraryRoots.removeOne(normalized))
        return false;
    saveSettings();
    emit libraryRootsChanged();
    refreshLibrary();
    return true;
}

void MusicPlayerManager::scanAllMedia()
{
    if (m_discoveryBusy || m_discoveryWatcher.isRunning())
        return;
    m_discoveryBusy = true;
    m_discoveryStatus = QStringLiteral("Searching for audio outside the configured music library…");
    m_discoveredAudio.clear();
    emit discoveredAudioChanged();
    emit discoveryStateChanged();

    const QString home = canonicalUserHome();
    const QStringList roots = m_libraryRoots;
    m_discoveryWatcher.setFuture(QtConcurrent::run([home, roots]() {
        return MusicPlayerManager::discoverAudioOutsideLibrary(home, roots);
    }));
}

void MusicPlayerManager::clearDiscoveredAudio()
{
    if (m_discoveredAudio.isEmpty())
        return;
    m_discoveredAudio.clear();
    m_discoveryStatus.clear();
    emit discoveredAudioChanged();
    emit discoveryStateChanged();
}

bool MusicPlayerManager::moveDiscoveredAudio(const QStringList &paths)
{
    if (paths.isEmpty())
        return false;

    const QString destinationRoot = defaultMusicPath();
    if (!QDir().mkpath(destinationRoot)) {
        const QString message = QStringLiteral("Could not create the Music folder: %1").arg(destinationRoot);
        setError(message);
        emit operationFinished(QStringLiteral("move-discovered-audio"), false, message);
        return false;
    }

    int moved = 0;
    QStringList failed;
    QSet<QString> movedPaths;
    for (const QString &requested : paths) {
        const QString source = normalizedPath(requested);
        const QFileInfo sourceInfo(source);
        if (!sourceInfo.isFile() || !kAudioExtensions.contains(sourceInfo.suffix().toLower())) {
            failed.append(requested);
            continue;
        }
        if (pathIsInside(source, destinationRoot)) {
            movedPaths.insert(source);
            continue;
        }

        QString target = QDir(destinationRoot).filePath(sourceInfo.fileName());
        const QString base = sourceInfo.completeBaseName();
        const QString suffix = sourceInfo.completeSuffix();
        int counter = 2;
        while (QFileInfo::exists(target)) {
            const QString numbered = suffix.isEmpty()
                ? QStringLiteral("%1 (%2)").arg(base).arg(counter)
                : QStringLiteral("%1 (%2).%3").arg(base).arg(counter).arg(suffix);
            target = QDir(destinationRoot).filePath(numbered);
            ++counter;
        }

        bool success = QFile::rename(source, target);
        if (!success && QFile::copy(source, target)) {
            success = QFile::remove(source);
            if (!success)
                QFile::remove(target);
        }
        if (success) {
            ++moved;
            movedPaths.insert(source);
        } else {
            failed.append(sourceInfo.fileName());
        }
    }

    if (!movedPaths.isEmpty()) {
        QVariantList remaining;
        for (const QVariant &value : m_discoveredAudio) {
            const QVariantMap entry = value.toMap();
            if (!movedPaths.contains(normalizedPath(entry.value(QStringLiteral("path")).toString())))
                remaining.append(entry);
        }
        m_discoveredAudio = remaining;
        emit discoveredAudioChanged();
    }

    const QString message = failed.isEmpty()
        ? QStringLiteral("Moved %1 audio file(s) into %2.").arg(moved).arg(destinationRoot)
        : QStringLiteral("Moved %1 file(s); %2 could not be moved.").arg(moved).arg(failed.size());
    m_discoveryStatus = message;
    emit discoveryStateChanged();
    emit operationFinished(QStringLiteral("move-discovered-audio"), moved > 0, message);
    if (moved > 0)
        refreshLibrary();
    return moved > 0;
}

MusicPlayerManager::ScanPayload MusicPlayerManager::scanRoots(
    const QStringList &roots,
    const QVariantMap &existingCache,
    const QString &artworkDirectory)
{
    ScanPayload payload;
    QVariantMap nextCache;
    QSet<QString> seen;

    for (const QString &root : roots) {
        QDirIterator iterator(root,
                              QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                              QDirIterator::Subdirectories);
        while (iterator.hasNext()) {
            const QString path = normalizedPath(iterator.next());
            if (path.isEmpty() || seen.contains(path))
                continue;
            const QFileInfo info(path);
            if (!kAudioExtensions.contains(info.suffix().toLower()))
                continue;
            seen.insert(path);

            const QVariantMap cached = existingCache.value(path).toMap();
            const bool cacheValid = cached.value(QStringLiteral("size")).toLongLong() == info.size() &&
                                    cached.value(QStringLiteral("modifiedMs")).toLongLong() ==
                                        info.lastModified().toMSecsSinceEpoch() &&
                                    !cached.value(QStringLiteral("track")).toMap().isEmpty();
            QVariantMap entry;
            if (cacheValid) {
                entry = cached;
            } else {
                QVariantMap track = probeTrack(path, cached, artworkDirectory);
                if (track.isEmpty())
                    continue;
                entry.insert(QStringLiteral("size"), info.size());
                entry.insert(QStringLiteral("modifiedMs"), info.lastModified().toMSecsSinceEpoch());
                entry.insert(QStringLiteral("track"), track);
            }
            nextCache.insert(path, entry);
            payload.tracks.append(entry.value(QStringLiteral("track")));
        }
    }

    std::sort(payload.tracks.begin(), payload.tracks.end(), [](const QVariant &left, const QVariant &right) {
        const QVariantMap a = left.toMap();
        const QVariantMap b = right.toMap();
        const int artist = QString::localeAwareCompare(a.value(QStringLiteral("artist")).toString(),
                                                       b.value(QStringLiteral("artist")).toString());
        if (artist != 0)
            return artist < 0;
        const int album = QString::localeAwareCompare(a.value(QStringLiteral("album")).toString(),
                                                      b.value(QStringLiteral("album")).toString());
        if (album != 0)
            return album < 0;
        const int aTrack = a.value(QStringLiteral("trackNumber")).toInt();
        const int bTrack = b.value(QStringLiteral("trackNumber")).toInt();
        if (aTrack != bTrack)
            return aTrack < bTrack;
        return QString::localeAwareCompare(a.value(QStringLiteral("title")).toString(),
                                           b.value(QStringLiteral("title")).toString()) < 0;
    });

    payload.cache = nextCache;
    return payload;
}

MusicPlayerManager::DiscoveryPayload MusicPlayerManager::discoverAudioOutsideLibrary(
    const QString &canonicalHome, const QStringList &libraryRoots)
{
    DiscoveryPayload payload;
    QStringList searchRoots{canonicalHome};
    const QString userName = QFileInfo(canonicalHome).fileName();
    const QStringList removableRoots{
        QDir(QStringLiteral("/media")).filePath(userName),
        QDir(QStringLiteral("/run/media")).filePath(userName),
        QStringLiteral("/mnt")
    };
    for (const QString &candidate : removableRoots) {
        if (QDir(candidate).exists() && !searchRoots.contains(candidate))
            searchRoots.append(candidate);
    }

    QStringList normalizedLibraries;
    for (const QString &root : libraryRoots)
        normalizedLibraries.append(normalizedPath(root));

    const QString neutronState = QDir(canonicalHome).filePath(QStringLiteral("NeutronOS/state"));
    const QStringList excludedNames{QStringLiteral(".cache"), QStringLiteral(".local/share/Trash")};
    QSet<QString> seen;
    const int maximumResults = 15000;

    for (const QString &searchRoot : searchRoots) {
        QDirIterator iterator(searchRoot, QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                              QDirIterator::Subdirectories);
        while (iterator.hasNext() && payload.files.size() < maximumResults) {
            const QString path = normalizedPath(iterator.next());
            if (path.isEmpty() || seen.contains(path))
                continue;
            seen.insert(path);

            bool excluded = pathIsInside(path, neutronState);
            for (const QString &relative : excludedNames) {
                if (pathIsInside(path, QDir(canonicalHome).filePath(relative))) {
                    excluded = true;
                    break;
                }
            }
            if (excluded)
                continue;

            bool alreadyInLibrary = false;
            for (const QString &libraryRoot : normalizedLibraries) {
                if (pathIsInside(path, libraryRoot)) {
                    alreadyInLibrary = true;
                    break;
                }
            }
            if (alreadyInLibrary)
                continue;

            const QFileInfo info(path);
            if (!kAudioExtensions.contains(info.suffix().toLower()))
                continue;

            QVariantMap entry;
            entry.insert(QStringLiteral("path"), path);
            entry.insert(QStringLiteral("name"), info.completeBaseName());
            entry.insert(QStringLiteral("fileName"), info.fileName());
            entry.insert(QStringLiteral("folder"), info.absolutePath());
            entry.insert(QStringLiteral("bytes"), info.size());
            entry.insert(QStringLiteral("modifiedMs"), info.lastModified().toMSecsSinceEpoch());
            payload.files.append(entry);
        }
    }

    std::sort(payload.files.begin(), payload.files.end(), [](const QVariant &left, const QVariant &right) {
        return QString::localeAwareCompare(left.toMap().value(QStringLiteral("fileName")).toString(),
                                           right.toMap().value(QStringLiteral("fileName")).toString()) < 0;
    });
    payload.status = payload.files.size() >= maximumResults
        ? QStringLiteral("Found at least %1 audio files outside the library. Refine the selection before moving.").arg(maximumResults)
        : QStringLiteral("Found %1 audio file(s) outside the configured library.").arg(payload.files.size());
    return payload;
}

QVariantMap MusicPlayerManager::probeTrack(const QString &path,
                                           const QVariantMap &cached,
                                           const QString &artworkDirectory)
{
    Q_UNUSED(cached)
    const QFileInfo info(path);
    if (!info.isFile())
        return {};

    QString title = info.completeBaseName();
    const QDir albumDirectory = info.dir();
    QDir artistDirectory = albumDirectory;
    artistDirectory.cdUp();
    QString artist = artistDirectory.dirName();
    QString album = albumDirectory.dirName();
    QString albumArtist;
    QString genre;
    QString year;
    int trackNumber = 0;
    qint64 durationMs = 0;

    const QString ffprobe = QStandardPaths::findExecutable(QStringLiteral("ffprobe"));
    if (!ffprobe.isEmpty()) {
        QProcess process;
        process.setProgram(ffprobe);
        process.setArguments({
            QStringLiteral("-v"), QStringLiteral("error"),
            QStringLiteral("-print_format"), QStringLiteral("json"),
            QStringLiteral("-show_entries"),
            QStringLiteral("format=duration:format_tags=title,artist,album,album_artist,track,genre,date,year"),
            path
        });
        process.start();
        if (process.waitForStarted(2000) && process.waitForFinished(6000) &&
            process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0) {
            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(process.readAllStandardOutput(), &parseError);
            if (parseError.error == QJsonParseError::NoError && document.isObject()) {
                const QJsonObject format = document.object().value(QStringLiteral("format")).toObject();
                const QJsonObject tags = format.value(QStringLiteral("tags")).toObject();
                title = firstNonEmpty(tags, {QStringLiteral("title"), QStringLiteral("TITLE")}, title);
                artist = firstNonEmpty(tags, {QStringLiteral("artist"), QStringLiteral("ARTIST")}, artist);
                album = firstNonEmpty(tags, {QStringLiteral("album"), QStringLiteral("ALBUM")}, album);
                albumArtist = firstNonEmpty(tags,
                    {QStringLiteral("album_artist"), QStringLiteral("ALBUM_ARTIST")}, artist);
                genre = firstNonEmpty(tags, {QStringLiteral("genre"), QStringLiteral("GENRE")});
                year = firstNonEmpty(tags,
                    {QStringLiteral("date"), QStringLiteral("DATE"),
                     QStringLiteral("year"), QStringLiteral("YEAR")});
                trackNumber = parseTrackNumber(firstNonEmpty(tags,
                    {QStringLiteral("track"), QStringLiteral("TRACK")}));
                bool durationOk = false;
                const double duration = format.value(QStringLiteral("duration")).toVariant().toDouble(&durationOk);
                if (durationOk && duration > 0.0)
                    durationMs = static_cast<qint64>(duration * 1000.0);
            }
        } else if (process.state() != QProcess::NotRunning) {
            process.kill();
            process.waitForFinished(500);
        }
    }

    title = cleanTag(title, info.completeBaseName());
    artist = cleanTag(artist, QStringLiteral("Unknown Artist"));
    album = cleanTag(album, QStringLiteral("Unknown Album"));
    albumArtist = cleanTag(albumArtist, artist);
    genre = cleanTag(genre);
    year = cleanTag(year);
    if (year.size() > 4)
        year = year.left(4);

    const QString artworkId = stableId(albumArtist.toCaseFolded() + QLatin1Char('\n') + album.toCaseFolded());
    const QString ffmpeg = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    const QString artwork = extractArtwork(ffmpeg, path,
        QDir(artworkDirectory).filePath(artworkId + QStringLiteral(".jpg")));

    const QString albumKey = artist.toCaseFolded() + QLatin1Char('\n') + album.toCaseFolded();
    QVariantMap track;
    track.insert(QStringLiteral("id"), stableId(path));
    track.insert(QStringLiteral("path"), info.absoluteFilePath());
    track.insert(QStringLiteral("url"), QUrl::fromLocalFile(info.absoluteFilePath()).toString());
    track.insert(QStringLiteral("fileName"), info.fileName());
    track.insert(QStringLiteral("title"), title);
    track.insert(QStringLiteral("artist"), artist);
    track.insert(QStringLiteral("album"), album);
    track.insert(QStringLiteral("albumArtist"), albumArtist);
    track.insert(QStringLiteral("albumKey"), albumKey);
    track.insert(QStringLiteral("genre"), genre);
    track.insert(QStringLiteral("year"), year);
    track.insert(QStringLiteral("trackNumber"), trackNumber);
    track.insert(QStringLiteral("durationMs"), durationMs);
    track.insert(QStringLiteral("durationText"), durationText(durationMs));
    track.insert(QStringLiteral("bytes"), info.size());
    track.insert(QStringLiteral("modifiedMs"), info.lastModified().toMSecsSinceEpoch());
    track.insert(QStringLiteral("artworkPath"), artwork);
    track.insert(QStringLiteral("artworkUrl"), artwork.isEmpty() ? QString() : QUrl::fromLocalFile(artwork).toString());
    return track;
}

QString MusicPlayerManager::normalizedPath(const QString &path)
{
    QFileInfo info(path);
    const QString canonical = info.canonicalFilePath();
    return QDir::cleanPath(canonical.isEmpty() ? info.absoluteFilePath() : canonical);
}

QString MusicPlayerManager::stableId(const QString &text)
{
    return QString::fromLatin1(QCryptographicHash::hash(text.toUtf8(), QCryptographicHash::Sha256).toHex().left(24));
}

QString MusicPlayerManager::cleanTag(const QString &value, const QString &fallback)
{
    QString result = value;
    result.replace(QChar::Null, QLatin1Char(' '));
    result = result.simplified();
    return result.isEmpty() ? fallback : result;
}

int MusicPlayerManager::parseTrackNumber(const QString &value)
{
    const QString first = value.section(QLatin1Char('/'), 0, 0).trimmed();
    bool ok = false;
    const int number = first.toInt(&ok);
    return ok && number >= 0 ? number : 0;
}

void MusicPlayerManager::rebuildCatalogs()
{
    QMap<QString, QVariantMap> albums;
    QMap<QString, QVariantMap> artists;
    QMap<QString, QVariantMap> folders;

    for (const QVariant &value : m_tracks) {
        const QVariantMap track = value.toMap();
        const QString albumKey = track.value(QStringLiteral("albumKey")).toString();
        QVariantMap album = albums.value(albumKey);
        if (album.isEmpty()) {
            album.insert(QStringLiteral("key"), albumKey);
            album.insert(QStringLiteral("name"), track.value(QStringLiteral("album")));
            album.insert(QStringLiteral("artist"), track.value(QStringLiteral("albumArtist")));
            album.insert(QStringLiteral("artworkUrl"), track.value(QStringLiteral("artworkUrl")));
            album.insert(QStringLiteral("trackCount"), 0);
            album.insert(QStringLiteral("durationMs"), 0);
            album.insert(QStringLiteral("year"), track.value(QStringLiteral("year")));
        }
        if (album.value(QStringLiteral("artworkUrl")).toString().isEmpty() &&
            !track.value(QStringLiteral("artworkUrl")).toString().isEmpty())
            album.insert(QStringLiteral("artworkUrl"), track.value(QStringLiteral("artworkUrl")));
        album.insert(QStringLiteral("trackCount"), album.value(QStringLiteral("trackCount")).toInt() + 1);
        album.insert(QStringLiteral("durationMs"), album.value(QStringLiteral("durationMs")).toLongLong() +
                                                track.value(QStringLiteral("durationMs")).toLongLong());
        album.insert(QStringLiteral("durationText"), durationText(album.value(QStringLiteral("durationMs")).toLongLong()));
        albums.insert(albumKey, album);

        const QString artistName = track.value(QStringLiteral("artist")).toString();
        QVariantMap artist = artists.value(artistName.toCaseFolded());
        if (artist.isEmpty()) {
            artist.insert(QStringLiteral("name"), artistName);
            artist.insert(QStringLiteral("trackCount"), 0);
            artist.insert(QStringLiteral("albumCount"), 0);
            artist.insert(QStringLiteral("artworkUrl"), track.value(QStringLiteral("artworkUrl")));
            artist.insert(QStringLiteral("albumKeys"), QStringList());
        }
        QStringList albumKeys = artist.value(QStringLiteral("albumKeys")).toStringList();
        if (!albumKeys.contains(albumKey))
            albumKeys.append(albumKey);
        artist.insert(QStringLiteral("albumKeys"), albumKeys);
        artist.insert(QStringLiteral("albumCount"), albumKeys.size());
        artist.insert(QStringLiteral("trackCount"), artist.value(QStringLiteral("trackCount")).toInt() + 1);
        if (artist.value(QStringLiteral("artworkUrl")).toString().isEmpty() &&
            !track.value(QStringLiteral("artworkUrl")).toString().isEmpty())
            artist.insert(QStringLiteral("artworkUrl"), track.value(QStringLiteral("artworkUrl")));
        artists.insert(artistName.toCaseFolded(), artist);

        const QString folderPath = QFileInfo(track.value(QStringLiteral("path")).toString()).absolutePath();
        QVariantMap folder = folders.value(folderPath);
        if (folder.isEmpty()) {
            folder.insert(QStringLiteral("path"), folderPath);
            folder.insert(QStringLiteral("name"), QFileInfo(folderPath).fileName());
            folder.insert(QStringLiteral("trackCount"), 0);
            folder.insert(QStringLiteral("artworkUrl"), track.value(QStringLiteral("artworkUrl")));
        }
        folder.insert(QStringLiteral("trackCount"), folder.value(QStringLiteral("trackCount")).toInt() + 1);
        if (folder.value(QStringLiteral("artworkUrl")).toString().isEmpty() &&
            !track.value(QStringLiteral("artworkUrl")).toString().isEmpty())
            folder.insert(QStringLiteral("artworkUrl"), track.value(QStringLiteral("artworkUrl")));
        folders.insert(folderPath, folder);
    }

    m_albums.clear();
    for (const QVariantMap &album : albums)
        m_albums.append(album);
    std::sort(m_albums.begin(), m_albums.end(), [](const QVariant &a, const QVariant &b) {
        return QString::localeAwareCompare(a.toMap().value(QStringLiteral("name")).toString(),
                                           b.toMap().value(QStringLiteral("name")).toString()) < 0;
    });

    m_artists.clear();
    for (QVariantMap artist : artists) {
        artist.remove(QStringLiteral("albumKeys"));
        m_artists.append(artist);
    }
    std::sort(m_artists.begin(), m_artists.end(), [](const QVariant &a, const QVariant &b) {
        return QString::localeAwareCompare(a.toMap().value(QStringLiteral("name")).toString(),
                                           b.toMap().value(QStringLiteral("name")).toString()) < 0;
    });

    m_folders.clear();
    for (const QVariantMap &folder : folders)
        m_folders.append(folder);
    std::sort(m_folders.begin(), m_folders.end(), [](const QVariant &a, const QVariant &b) {
        return QString::localeAwareCompare(a.toMap().value(QStringLiteral("path")).toString(),
                                           b.toMap().value(QStringLiteral("path")).toString()) < 0;
    });

    emit albumsChanged();
    emit artistsChanged();
    emit foldersChanged();
}

int MusicPlayerManager::trackIndexForPath(const QString &path) const
{
    const QString normalized = normalizedPath(path);
    for (int i = 0; i < m_tracks.size(); ++i) {
        if (normalizedPath(m_tracks.at(i).toMap().value(QStringLiteral("path")).toString()) == normalized)
            return i;
    }
    return -1;
}

QVariantMap MusicPlayerManager::trackForPath(const QString &path) const
{
    const int index = trackIndexForPath(path);
    return index >= 0 ? m_tracks.at(index).toMap() : QVariantMap();
}

bool MusicPlayerManager::playTrack(int libraryIndex)
{
    if (libraryIndex < 0 || libraryIndex >= m_tracks.size())
        return false;
    QStringList paths;
    paths.reserve(m_tracks.size());
    for (const QVariant &value : m_tracks)
        paths.append(value.toMap().value(QStringLiteral("path")).toString());
    setQueuePaths(paths, libraryIndex);
    return loadQueueIndex(libraryIndex, true);
}

bool MusicPlayerManager::playPath(const QString &path)
{
    const int libraryIndex = trackIndexForPath(path);
    if (libraryIndex < 0) {
        const QString message = QStringLiteral("Track is no longer in the music library.");
        setError(message);
        emit playbackError(message);
        return false;
    }
    return playTrack(libraryIndex);
}

QStringList MusicPlayerManager::pathsForAlbum(const QString &albumKey) const
{
    QStringList paths;
    for (const QVariant &value : m_tracks) {
        const QVariantMap track = value.toMap();
        if (track.value(QStringLiteral("albumKey")).toString() == albumKey)
            paths.append(track.value(QStringLiteral("path")).toString());
    }
    return paths;
}

QStringList MusicPlayerManager::pathsForArtist(const QString &artistName) const
{
    QStringList paths;
    for (const QVariant &value : m_tracks) {
        const QVariantMap track = value.toMap();
        if (track.value(QStringLiteral("artist")).toString().compare(artistName, Qt::CaseInsensitive) == 0)
            paths.append(track.value(QStringLiteral("path")).toString());
    }
    return paths;
}

QStringList MusicPlayerManager::pathsForFolder(const QString &folderPath) const
{
    QStringList paths;
    const QString normalizedFolder = normalizedPath(folderPath);
    for (const QVariant &value : m_tracks) {
        const QVariantMap track = value.toMap();
        if (normalizedPath(QFileInfo(track.value(QStringLiteral("path")).toString()).absolutePath()) == normalizedFolder)
            paths.append(track.value(QStringLiteral("path")).toString());
    }
    return paths;
}

QStringList MusicPlayerManager::pathsForPlaylist(const QString &playlistName) const
{
    return playlistObject(playlistName).value(QStringLiteral("paths")).toStringList();
}

bool MusicPlayerManager::playAlbum(const QString &albumKey)
{
    const QStringList paths = pathsForAlbum(albumKey);
    if (paths.isEmpty())
        return false;
    setQueuePaths(paths, 0);
    return loadQueueIndex(0, true);
}

bool MusicPlayerManager::playArtist(const QString &artistName)
{
    const QStringList paths = pathsForArtist(artistName);
    if (paths.isEmpty())
        return false;
    setQueuePaths(paths, 0);
    return loadQueueIndex(0, true);
}

bool MusicPlayerManager::playFolder(const QString &folderPath)
{
    const QStringList paths = pathsForFolder(folderPath);
    if (paths.isEmpty())
        return false;
    setQueuePaths(paths, 0);
    return loadQueueIndex(0, true);
}

bool MusicPlayerManager::playPlaylist(const QString &playlistName)
{
    const QStringList paths = pathsForPlaylist(playlistName);
    if (paths.isEmpty())
        return false;
    setQueuePaths(paths, 0);
    return loadQueueIndex(0, true);
}

void MusicPlayerManager::setQueuePaths(const QStringList &paths, int startIndex)
{
    m_queuePaths.clear();
    for (const QString &path : paths) {
        if (trackIndexForPath(path) >= 0 && !m_queuePaths.contains(path))
            m_queuePaths.append(path);
    }
    m_currentQueueIndex = m_queuePaths.isEmpty()
        ? -1 : std::clamp(startIndex, 0, static_cast<int>(m_queuePaths.size()) - 1);
    emit queueChanged();
    emit currentQueueIndexChanged();
}

bool MusicPlayerManager::enqueuePath(const QString &path)
{
    const QString normalized = normalizedPath(path);
    if (trackIndexForPath(normalized) < 0)
        return false;
    m_queuePaths.append(normalized);
    emit queueChanged();
    return true;
}

bool MusicPlayerManager::removeQueueItem(int index)
{
    if (index < 0 || index >= m_queuePaths.size())
        return false;
    m_queuePaths.removeAt(index);
    if (m_queuePaths.isEmpty()) {
        m_currentQueueIndex = -1;
        m_currentTrack.clear();
        emit currentTrackChanged();
    } else if (index < m_currentQueueIndex) {
        --m_currentQueueIndex;
    } else if (m_currentQueueIndex >= m_queuePaths.size()) {
        m_currentQueueIndex = m_queuePaths.size() - 1;
    }
    emit queueChanged();
    emit currentQueueIndexChanged();
    return true;
}

void MusicPlayerManager::clearQueue()
{
    stop();
    m_queuePaths.clear();
    m_currentQueueIndex = -1;
    m_currentTrack.clear();
    emit queueChanged();
    emit currentQueueIndexChanged();
    emit currentTrackChanged();
}

bool MusicPlayerManager::ensurePlayer()
{
    const QString mpv = QStandardPaths::findExecutable(QStringLiteral("mpv"));
    const bool available = !mpv.isEmpty();
    setPlayerAvailable(available);
    if (!available) {
        setStatus(QStringLiteral("Playback dependency missing"));
        setError(QStringLiteral("Install mpv to enable the Music Player playback engine."));
        return false;
    }
    if (m_playerProcess.state() == QProcess::NotRunning)
        startPlayer();
    return true;
}

void MusicPlayerManager::startPlayer()
{
    const QString mpv = QStandardPaths::findExecutable(QStringLiteral("mpv"));
    if (mpv.isEmpty()) {
        setPlayerAvailable(false);
        return;
    }

    disconnectPlayerSocket();
    QFile::remove(socketPath());
    m_playerProcess.setProgram(mpv);
    m_playerProcess.setProcessChannelMode(QProcess::MergedChannels);
    QStringList playerArguments{
        QStringLiteral("--no-config"),
        QStringLiteral("--idle=yes"),
        QStringLiteral("--no-terminal"),
        QStringLiteral("--really-quiet"),
        QStringLiteral("--no-video"),
        QStringLiteral("--audio-display=no"),
        QStringLiteral("--force-window=no"),
        QStringLiteral("--keep-open=no"),
        QStringLiteral("--gapless-audio=weak"),
        QStringLiteral("--audio-client-name=NeutronOS Music Player"),
        QStringLiteral("--input-ipc-server=%1").arg(socketPath()),
        QStringLiteral("--volume=%1").arg(m_volume)
    };
    // Omitting --audio-device for Automatic lets PipeWire/Pulse select the
    // active HDMI sink. Explicit devices retain their real mpv identifier.
    if (!m_selectedAudioOutput.isEmpty() && m_selectedAudioOutput != QStringLiteral("auto"))
        playerArguments.append(QStringLiteral("--audio-device=%1").arg(m_selectedAudioOutput));
    m_playerProcess.setArguments(playerArguments);
    m_playerProcess.start();
    if (!m_playerProcess.waitForStarted(2200)) {
        setPlayerAvailable(false);
        const QString message = QStringLiteral("mpv failed to start: %1").arg(m_playerProcess.errorString());
        setError(message);
        emit playbackError(message);
        return;
    }
    setPlayerAvailable(true);
    m_socketAttempts = 0;
    m_socketRetryTimer.start();
}

void MusicPlayerManager::connectPlayerSocket()
{
    if (m_playerSocket.state() == QLocalSocket::ConnectedState ||
        m_playerSocket.state() == QLocalSocket::ConnectingState)
        return;
    if (m_playerProcess.state() == QProcess::NotRunning) {
        m_socketRetryTimer.stop();
        return;
    }
    if (++m_socketAttempts > 80) {
        m_socketRetryTimer.stop();
        const QString message = QStringLiteral("Could not connect to the music playback engine.");
        setError(message);
        emit playbackError(message);
        return;
    }
    m_playerSocket.abort();
    m_playerSocket.connectToServer(socketPath(), QIODevice::ReadWrite);
}

void MusicPlayerManager::disconnectPlayerSocket()
{
    m_socketRetryTimer.stop();
    m_positionPollTimer.stop();
    m_playerSocket.abort();
    m_socketBuffer.clear();
    setPlayerConnected(false);
}

void MusicPlayerManager::queueCommand(const QJsonArray &command, int requestId)
{
    QJsonObject object;
    object.insert(QStringLiteral("command"), command);
    if (requestId > 0)
        object.insert(QStringLiteral("request_id"), requestId);
    const QByteArray data = QJsonDocument(object).toJson(QJsonDocument::Compact) + '\n';
    if (m_playerSocket.state() == QLocalSocket::ConnectedState) {
        m_playerSocket.write(data);
        m_playerSocket.flush();
    } else {
        if (m_pendingCommands.size() > 128)
            m_pendingCommands.dequeue();
        m_pendingCommands.enqueue(data);
        ensurePlayer();
    }
}

void MusicPlayerManager::flushCommands()
{
    if (m_playerSocket.state() != QLocalSocket::ConnectedState)
        return;
    while (!m_pendingCommands.isEmpty())
        m_playerSocket.write(m_pendingCommands.dequeue());
    m_playerSocket.flush();
}

void MusicPlayerManager::sendObserveCommands()
{
    int id = 1;
    const QStringList properties = {
        QStringLiteral("pause"), QStringLiteral("time-pos"),
        QStringLiteral("duration"), QStringLiteral("volume"),
        QStringLiteral("path"), QStringLiteral("idle-active")
    };
    for (const QString &property : properties)
        queueCommand(QJsonArray{QStringLiteral("observe_property"), id++, property});
}

void MusicPlayerManager::processSocketData()
{
    m_socketBuffer.append(m_playerSocket.readAll());
    for (;;) {
        const qsizetype newline = m_socketBuffer.indexOf('\n');
        if (newline < 0)
            break;
        const QByteArray line = m_socketBuffer.left(newline).trimmed();
        m_socketBuffer.remove(0, newline + 1);
        if (line.isEmpty())
            continue;
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error == QJsonParseError::NoError && document.isObject())
            processPlayerMessage(document.object());
    }
}

void MusicPlayerManager::processPlayerMessage(const QJsonObject &object)
{
    const int requestId = object.value(QStringLiteral("request_id")).toInt();
    if (requestId == 9001 && object.value(QStringLiteral("error")).toString() == QStringLiteral("success")) {
        handlePropertyChange(QStringLiteral("time-pos"), object.value(QStringLiteral("data")));
        return;
    }
    if (requestId == 9002 && object.value(QStringLiteral("error")).toString() == QStringLiteral("success")) {
        handlePropertyChange(QStringLiteral("duration"), object.value(QStringLiteral("data")));
        return;
    }

    const QString event = object.value(QStringLiteral("event")).toString();
    if (event == QStringLiteral("property-change")) {
        handlePropertyChange(object.value(QStringLiteral("name")).toString(),
                             object.value(QStringLiteral("data")));
        return;
    }
    if (event == QStringLiteral("file-loaded")) {
        m_stoppingForLoad = false;
        m_playing = true;
        m_paused = false;
        emit playbackStateChanged();
        updateVisualizationTimer();
        setStatus(QStringLiteral("Playing %1").arg(m_currentTrack.value(QStringLiteral("title")).toString()));
        return;
    }
    if (event == QStringLiteral("end-file")) {
        handleTrackEnded(object.value(QStringLiteral("reason")).toString());
        return;
    }
    if (object.contains(QStringLiteral("error")) &&
        object.value(QStringLiteral("error")).toString() != QStringLiteral("success")) {
        const QString commandError = object.value(QStringLiteral("error")).toString();
        if (!commandError.isEmpty() && commandError != QStringLiteral("property unavailable"))
            setError(QStringLiteral("Playback command failed: %1").arg(commandError));
    }
}

void MusicPlayerManager::handlePropertyChange(const QString &name, const QJsonValue &value)
{
    if (name == QStringLiteral("pause")) {
        const bool paused = value.toBool();
        if (m_paused != paused) {
            m_paused = paused;
            m_playing = !paused && !m_currentTrack.isEmpty();
            emit playbackStateChanged();
            updateVisualizationTimer();
        }
    } else if (name == QStringLiteral("time-pos")) {
        const qint64 position = value.isDouble()
            ? static_cast<qint64>(value.toDouble() * 1000.0) : 0;
        if (m_positionMs != position) {
            m_positionMs = position;
            emit positionChanged();
        }
    } else if (name == QStringLiteral("duration")) {
        const qint64 duration = value.isDouble()
            ? static_cast<qint64>(value.toDouble() * 1000.0) : 0;
        if (m_durationMs != duration) {
            m_durationMs = duration;
            emit durationChanged();
        }
    } else if (name == QStringLiteral("volume")) {
        const int volume = std::clamp(qRound(value.toDouble()), 0, 100);
        if (m_volume != volume) {
            m_volume = volume;
            emit volumeChanged();
        }
    } else if (name == QStringLiteral("idle-active") && value.toBool()) {
        if (m_stoppingForLoad)
            return;
        if (!m_playing && !m_paused)
            updateVisualizationTimer();
    }
}

bool MusicPlayerManager::loadQueueIndex(int index, bool force)
{
    if (index < 0 || index >= m_queuePaths.size())
        return false;
    if (!ensurePlayer())
        return false;

    const QVariantMap track = trackForPath(m_queuePaths.at(index));
    if (track.isEmpty())
        return false;
    if (!force && index == m_currentQueueIndex && m_playing)
        return true;

    m_currentQueueIndex = index;
    m_currentTrack = track;
    m_positionMs = 0;
    m_durationMs = track.value(QStringLiteral("durationMs")).toLongLong();
    m_playing = true;
    m_paused = false;
    m_stoppingForLoad = true;
    emit currentQueueIndexChanged();
    emit currentTrackChanged();
    emit positionChanged();
    emit durationChanged();
    emit playbackStateChanged();

    queueCommand(QJsonArray{QStringLiteral("loadfile"),
                            track.value(QStringLiteral("path")).toString(),
                            QStringLiteral("replace")});
    applyAudioOutput();
    applyEqualizer();
    updateVisualizationTimer();
    return true;
}

int MusicPlayerManager::nextQueueIndex() const
{
    if (m_queuePaths.isEmpty())
        return -1;
    if (m_repeatMode == QStringLiteral("one"))
        return m_currentQueueIndex;
    if (m_shuffle && m_queuePaths.size() > 1) {
        int candidate = m_currentQueueIndex;
        while (candidate == m_currentQueueIndex)
            candidate = QRandomGenerator::global()->bounded(static_cast<int>(m_queuePaths.size()));
        return candidate;
    }
    const int next = m_currentQueueIndex + 1;
    if (next < m_queuePaths.size())
        return next;
    return m_repeatMode == QStringLiteral("all") ? 0 : -1;
}

int MusicPlayerManager::previousQueueIndex() const
{
    if (m_queuePaths.isEmpty())
        return -1;
    const int previous = m_currentQueueIndex - 1;
    if (previous >= 0)
        return previous;
    return m_repeatMode == QStringLiteral("all") ? m_queuePaths.size() - 1 : 0;
}

void MusicPlayerManager::handleTrackEnded(const QString &reason)
{
    if (m_stoppingForLoad || reason == QStringLiteral("stop") || reason == QStringLiteral("redirect")) {
        m_stoppingForLoad = false;
        return;
    }
    if (reason == QStringLiteral("error")) {
        const QString message = QStringLiteral("The selected track could not be played.");
        setError(message);
        emit playbackError(message);
    }
    const int nextIndex = nextQueueIndex();
    if (nextIndex >= 0) {
        loadQueueIndex(nextIndex, true);
        return;
    }
    m_playing = false;
    m_paused = false;
    m_positionMs = 0;
    emit playbackStateChanged();
    emit positionChanged();
    updateVisualizationTimer();
    setStatus(QStringLiteral("Queue finished"));
}

void MusicPlayerManager::togglePause()
{
    if (m_currentTrack.isEmpty()) {
        if (!m_tracks.isEmpty())
            playTrack(0);
        return;
    }
    queueCommand(QJsonArray{QStringLiteral("cycle"), QStringLiteral("pause")});
}

void MusicPlayerManager::pause()
{
    if (!m_currentTrack.isEmpty())
        queueCommand(QJsonArray{QStringLiteral("set_property"), QStringLiteral("pause"), true});
}

void MusicPlayerManager::resume()
{
    if (m_currentTrack.isEmpty()) {
        if (!m_tracks.isEmpty())
            playTrack(0);
        return;
    }
    queueCommand(QJsonArray{QStringLiteral("set_property"), QStringLiteral("pause"), false});
}

void MusicPlayerManager::stop()
{
    if (m_playerConnected)
        queueCommand(QJsonArray{QStringLiteral("stop")});
    m_stoppingForLoad = false;
    m_playing = false;
    m_paused = false;
    m_positionMs = 0;
    emit playbackStateChanged();
    emit positionChanged();
    updateVisualizationTimer();
    updateSpectrum();
}

void MusicPlayerManager::next()
{
    const int index = nextQueueIndex();
    if (index >= 0)
        loadQueueIndex(index, true);
}

void MusicPlayerManager::previous()
{
    if (m_positionMs > 5000) {
        seekMs(0);
        return;
    }
    const int index = previousQueueIndex();
    if (index >= 0)
        loadQueueIndex(index, true);
}

void MusicPlayerManager::seekMs(qint64 positionMs)
{
    const qint64 maximum = m_durationMs > 0 ? m_durationMs : std::numeric_limits<qint64>::max();
    const qint64 target = std::clamp<qint64>(positionMs, 0, maximum);
    queueCommand(QJsonArray{QStringLiteral("set_property"), QStringLiteral("time-pos"),
                            static_cast<double>(target) / 1000.0});
    m_positionMs = target;
    emit positionChanged();
}

void MusicPlayerManager::seekRelativeMs(qint64 deltaMs)
{
    seekMs(m_positionMs + deltaMs);
}

void MusicPlayerManager::setVolume(int volume)
{
    const int clamped = std::clamp(volume, 0, 100);
    if (m_volume == clamped && m_playerConnected)
        return;
    m_volume = clamped;
    queueCommand(QJsonArray{QStringLiteral("set_property"), QStringLiteral("volume"), m_volume});
    saveSettings();
    emit volumeChanged();
}

void MusicPlayerManager::setShuffle(bool enabled)
{
    if (m_shuffle == enabled)
        return;
    m_shuffle = enabled;
    saveSettings();
    emit shuffleChanged();
}

void MusicPlayerManager::toggleShuffle()
{
    setShuffle(!m_shuffle);
}

void MusicPlayerManager::setRepeatMode(const QString &mode)
{
    QString normalized = mode.toLower();
    if (normalized != QStringLiteral("off") && normalized != QStringLiteral("all") &&
        normalized != QStringLiteral("one"))
        normalized = QStringLiteral("off");
    if (m_repeatMode == normalized)
        return;
    m_repeatMode = normalized;
    saveSettings();
    emit repeatModeChanged();
}

void MusicPlayerManager::cycleRepeatMode()
{
    if (m_repeatMode == QStringLiteral("off"))
        setRepeatMode(QStringLiteral("all"));
    else if (m_repeatMode == QStringLiteral("all"))
        setRepeatMode(QStringLiteral("one"));
    else
        setRepeatMode(QStringLiteral("off"));
}

QVariantMap MusicPlayerManager::playlistObject(const QString &name) const
{
    const int index = playlistObjectIndex(name);
    return index >= 0 ? m_playlists.at(index).toMap() : QVariantMap();
}

int MusicPlayerManager::playlistObjectIndex(const QString &name) const
{
    for (int i = 0; i < m_playlists.size(); ++i) {
        if (m_playlists.at(i).toMap().value(QStringLiteral("name")).toString()
                .compare(name, Qt::CaseInsensitive) == 0)
            return i;
    }
    return -1;
}

bool MusicPlayerManager::createPlaylist(const QString &name)
{
    const QString cleanName = name.simplified().left(80);
    if (cleanName.isEmpty() || playlistObjectIndex(cleanName) >= 0) {
        const QString message = cleanName.isEmpty()
            ? QStringLiteral("Playlist name cannot be empty.")
            : QStringLiteral("A playlist with that name already exists.");
        setError(message);
        emit operationFinished(QStringLiteral("create-playlist"), false, message);
        return false;
    }
    m_playlists.append(QVariantMap{
        {QStringLiteral("name"), cleanName},
        {QStringLiteral("paths"), QStringList()},
        {QStringLiteral("trackCount"), 0},
        {QStringLiteral("created"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}
    });
    savePlaylists();
    emit playlistsChanged();
    emit operationFinished(QStringLiteral("create-playlist"), true,
                           QStringLiteral("Created playlist %1.").arg(cleanName));
    return true;
}

bool MusicPlayerManager::deletePlaylist(const QString &name)
{
    const int index = playlistObjectIndex(name);
    if (index < 0)
        return false;
    m_playlists.removeAt(index);
    savePlaylists();
    emit playlistsChanged();
    emit operationFinished(QStringLiteral("delete-playlist"), true,
                           QStringLiteral("Deleted playlist %1.").arg(name));
    return true;
}

bool MusicPlayerManager::addToPlaylist(const QString &name, const QString &path)
{
    const int index = playlistObjectIndex(name);
    const QString normalized = normalizedPath(path);
    if (index < 0 || trackIndexForPath(normalized) < 0)
        return false;
    QVariantMap playlist = m_playlists.at(index).toMap();
    QStringList paths = playlist.value(QStringLiteral("paths")).toStringList();
    if (!paths.contains(normalized))
        paths.append(normalized);
    playlist.insert(QStringLiteral("paths"), paths);
    playlist.insert(QStringLiteral("trackCount"), paths.size());
    m_playlists[index] = playlist;
    savePlaylists();
    emit playlistsChanged();
    return true;
}

bool MusicPlayerManager::removeFromPlaylist(const QString &name, const QString &path)
{
    const int index = playlistObjectIndex(name);
    if (index < 0)
        return false;
    QVariantMap playlist = m_playlists.at(index).toMap();
    QStringList paths = playlist.value(QStringLiteral("paths")).toStringList();
    if (!paths.removeOne(normalizedPath(path)))
        return false;
    playlist.insert(QStringLiteral("paths"), paths);
    playlist.insert(QStringLiteral("trackCount"), paths.size());
    m_playlists[index] = playlist;
    savePlaylists();
    emit playlistsChanged();
    return true;
}

QVariantList MusicPlayerManager::playlistTracks(const QString &name) const
{
    QVariantList result;
    for (const QString &path : pathsForPlaylist(name)) {
        const QVariantMap track = trackForPath(path);
        if (!track.isEmpty())
            result.append(track);
    }
    return result;
}

void MusicPlayerManager::setEqualizerPreset(const QString &preset)
{
    QString selected = QStringLiteral("Flat");
    for (const QVariant &value : equalizerPresets()) {
        const QString name = value.toMap().value(QStringLiteral("name")).toString();
        if (name.compare(preset, Qt::CaseInsensitive) == 0) {
            selected = name;
            break;
        }
    }
    if (m_equalizerPreset == selected)
        return;
    m_equalizerPreset = selected;
    applyEqualizer();
    saveSettings();
    emit equalizerPresetChanged();
}

void MusicPlayerManager::applyEqualizer()
{
    QString filter;
    if (m_equalizerPreset == QStringLiteral("Bass Boost"))
        filter = QStringLiteral("lavfi=[equalizer=f=70:t=q:w=1:g=5,equalizer=f=150:t=q:w=1:g=3]");
    else if (m_equalizerPreset == QStringLiteral("Warm"))
        filter = QStringLiteral("lavfi=[equalizer=f=120:t=q:w=1:g=3,equalizer=f=7000:t=q:w=1:g=-2]");
    else if (m_equalizerPreset == QStringLiteral("Vocal"))
        filter = QStringLiteral("lavfi=[equalizer=f=250:t=q:w=1:g=-2,equalizer=f=2000:t=q:w=1:g=4,equalizer=f=4200:t=q:w=1:g=2]");
    else if (m_equalizerPreset == QStringLiteral("Treble"))
        filter = QStringLiteral("lavfi=[equalizer=f=5000:t=q:w=1:g=3,equalizer=f=10000:t=q:w=1:g=4]");
    else if (m_equalizerPreset == QStringLiteral("Night"))
        filter = QStringLiteral("lavfi=[equalizer=f=80:t=q:w=1:g=-4,equalizer=f=2500:t=q:w=1:g=2,equalizer=f=9000:t=q:w=1:g=-3]");
    queueCommand(QJsonArray{QStringLiteral("set_property"), QStringLiteral("af"), filter});
}

void MusicPlayerManager::refreshAudioOutputs()
{
    QVariantList outputs;
    outputs.append(QVariantMap{{QStringLiteral("id"), QStringLiteral("auto")},
                               {QStringLiteral("name"), QStringLiteral("Automatic")}});

    int hdmiIndex = 0;
    const QString mpv = QStandardPaths::findExecutable(QStringLiteral("mpv"));
    if (!mpv.isEmpty()) {
        QProcess process;
        process.setProgram(mpv);
        process.setArguments({QStringLiteral("--no-config"), QStringLiteral("--audio-device=help")});
        process.setProcessChannelMode(QProcess::MergedChannels);
        process.start();
        if (process.waitForStarted(1500) && process.waitForFinished(5000)) {
            const QString text = QString::fromLocal8Bit(process.readAll());
            const QStringList lines = text.split(QLatin1Char('\n'));
            const QRegularExpression expression(QStringLiteral("^\\s*'([^']+)'\\s*\\((.+)\\)\\s*$"));
            for (const QString &line : lines) {
                const QRegularExpressionMatch match = expression.match(line);
                if (!match.hasMatch())
                    continue;
                const QString id = match.captured(1).trimmed();
                const QString description = match.captured(2).trimmed();
                if (!id.isEmpty() && id != QStringLiteral("auto")) {
                    const QString friendlyName = friendlyAudioOutputName(id, description, hdmiIndex);
                    outputs.append(QVariantMap{{QStringLiteral("id"), id},
                                               {QStringLiteral("name"), friendlyName},
                                               {QStringLiteral("description"), description}});
                }
            }
        }
    }
    bool hasHdmi = false;
    for (const QVariant &entry : outputs) {
        if (entry.toMap().value(QStringLiteral("name")).toString().startsWith(QStringLiteral("HDMI"), Qt::CaseInsensitive)) {
            hasHdmi = true;
            break;
        }
    }
    if (!hasHdmi) {
        const QString aplay = QStandardPaths::findExecutable(QStringLiteral("aplay"));
        if (!aplay.isEmpty()) {
            QProcess process;
            process.setProgram(aplay);
            process.setArguments({QStringLiteral("-L")});
            process.start();
            if (process.waitForStarted(1200) && process.waitForFinished(3500)) {
                int fallbackHdmi = 0;
                const QStringList lines = QString::fromLocal8Bit(process.readAllStandardOutput()).split(QLatin1Char('\n'));
                for (const QString &raw : lines) {
                    const QString line = raw.trimmed();
                    if (!line.startsWith(QStringLiteral("hdmi:"), Qt::CaseInsensitive)) continue;
                    const QString id = QStringLiteral("alsa/") + line;
                    bool duplicate = false;
                    for (const QVariant &entry : outputs)
                        if (entry.toMap().value(QStringLiteral("id")).toString() == id) duplicate = true;
                    if (!duplicate)
                        outputs.append(QVariantMap{{QStringLiteral("id"), id},
                                                   {QStringLiteral("name"), QStringLiteral("HDMI %1").arg(fallbackHdmi++)},
                                                   {QStringLiteral("description"), line}});
                }
            }
        }
    }

    m_audioOutputs = outputs;
    bool selectedExists = false;
    for (const QVariant &value : m_audioOutputs) {
        if (value.toMap().value(QStringLiteral("id")).toString() == m_selectedAudioOutput) {
            selectedExists = true;
            break;
        }
    }
    if (!selectedExists) {
        m_selectedAudioOutput = QStringLiteral("auto");
        saveSettings();
        setStatus(QStringLiteral("Saved audio output was unavailable; using Automatic."));
    }
    emit audioOutputsChanged();
    emit selectedAudioOutputChanged();
}

void MusicPlayerManager::setSelectedAudioOutput(const QString &outputId)
{
    QString selected = QStringLiteral("auto");
    for (const QVariant &value : m_audioOutputs) {
        const QString id = value.toMap().value(QStringLiteral("id")).toString();
        if (id == outputId) {
            selected = id;
            break;
        }
    }
    if (m_selectedAudioOutput == selected)
        return;
    m_selectedAudioOutput = selected;
    applyAudioOutput();
    saveSettings();
    emit selectedAudioOutputChanged();
}

void MusicPlayerManager::applyAudioOutput()
{
    const QString output = m_selectedAudioOutput.isEmpty() ? QStringLiteral("auto") : m_selectedAudioOutput;
    queueCommand(QJsonArray{QStringLiteral("set_property"), QStringLiteral("audio-device"), output});
}


QVariantList MusicPlayerManager::buildMetadataRepairPreview(const QStringList &paths)
{
    QVariantList preview;
    QSet<QString> seen;
    for (const QString &rawPath : paths) {
        const QString path = normalizedPath(rawPath);
        if (path.isEmpty() || seen.contains(path) || !QFileInfo(path).isFile()) continue;
        seen.insert(path);
        const QVariantMap proposal = inferSongIdentity(path, trackForPath(path));
        if (proposal.value(QStringLiteral("changed")).toBool())
            preview.append(proposal);
    }
    m_metadataRepairPreview = preview;
    m_metadataRepairStatus = preview.isEmpty()
        ? QStringLiteral("Selected songs already have matching filenames and metadata.")
        : QStringLiteral("%1 proposed metadata repair(s) are ready for review.").arg(preview.size());
    emit metadataRepairChanged();
    emit metadataRepairStateChanged();
    return preview;
}

void MusicPlayerManager::clearMetadataRepairPreview()
{
    if (m_metadataRepairPreview.isEmpty()) return;
    m_metadataRepairPreview.clear();
    emit metadataRepairChanged();
}

bool MusicPlayerManager::applyMetadataRepair(const QStringList &paths)
{
    if (m_metadataRepairBusy || m_busy) {
        setError(QStringLiteral("Music Player is already processing another operation."));
        return false;
    }

    const QVariantList preview = buildMetadataRepairPreview(paths);
    if (preview.isEmpty()) {
        setError(QStringLiteral("No filename or metadata changes are needed for the selected songs."));
        emit operationFinished(QStringLiteral("metadata-repair"), false, error());
        return false;
    }

    const QString ffmpeg = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    if (ffmpeg.isEmpty()) {
        setError(QStringLiteral("ffmpeg is required to update embedded music metadata."));
        emit operationFinished(QStringLiteral("metadata-repair"), false, error());
        return false;
    }
    const QString ffprobe = QStandardPaths::findExecutable(QStringLiteral("ffprobe"));

    const QString currentPath = QDir::cleanPath(m_currentTrack.value(QStringLiteral("path")).toString());
    for (const QVariant &value : preview) {
        if (QDir::cleanPath(value.toMap().value(QStringLiteral("path")).toString()) == currentPath) {
            stop();
            break;
        }
    }

    m_metadataRepairBusy = true;
    m_metadataRepairCurrent = 0;
    m_metadataRepairTotal = preview.size();
    m_metadataRepairStatus = QStringLiteral("Preparing %1 song(s)…").arg(preview.size());
    setError(QString());
    setBusy(true);
    setStatus(m_metadataRepairStatus);
    emit metadataRepairStateChanged();

    QPointer<MusicPlayerManager> self(this);
    m_metadataRepairWatcher.setFuture(QtConcurrent::run([self, preview, ffmpeg, ffprobe]() {
        MetadataRepairPayload payload;
        const int total = preview.size();

        for (int index = 0; index < total; ++index) {
            const QVariantMap entry = preview.at(index).toMap();
            const QString source = QDir::cleanPath(entry.value(QStringLiteral("path")).toString());
            const QFileInfo info(source);
            const QString displayName = info.fileName();

            if (self) {
                QMetaObject::invokeMethod(self, [self, index, total, displayName]() {
                    if (!self) return;
                    self->m_metadataRepairCurrent = index;
                    self->m_metadataRepairStatus = QStringLiteral("Updating %1 of %2 — %3")
                        .arg(index + 1).arg(total).arg(displayName);
                    emit self->metadataRepairStateChanged();
                }, Qt::QueuedConnection);
            }

            if (!info.isFile() || !info.isWritable()) {
                payload.failures.append(displayName.isEmpty() ? source : displayName);
                ++payload.failed;
                continue;
            }

            const QString target = nonConflictingSongPath(
                info.absolutePath(), entry.value(QStringLiteral("proposedName")).toString(), source);
            const QString extension = info.suffix();
            const QString token = QUuid::createUuid().toString(QUuid::WithoutBraces);
            const QString temporary = QDir(info.absolutePath()).filePath(
                QStringLiteral(".neutron-meta-") + token +
                (extension.isEmpty() ? QString() : QStringLiteral(".") + extension));
            const QString originalHold = QDir(info.absolutePath()).filePath(
                QStringLiteral(".neutron-original-") + token +
                (extension.isEmpty() ? QString() : QStringLiteral(".") + extension));

            QStringList arguments{QStringLiteral("-v"), QStringLiteral("error"), QStringLiteral("-y"),
                                  QStringLiteral("-i"), source,
                                  QStringLiteral("-map"), QStringLiteral("0"),
                                  QStringLiteral("-map_metadata"), QStringLiteral("0"),
                                  QStringLiteral("-c"), QStringLiteral("copy"),
                                  QStringLiteral("-metadata"), QStringLiteral("title=%1").arg(entry.value(QStringLiteral("title")).toString()),
                                  QStringLiteral("-metadata"), QStringLiteral("artist=%1").arg(entry.value(QStringLiteral("metadataArtist")).toString())};
            const QString album = entry.value(QStringLiteral("album")).toString().trimmed();
            const QString albumArtist = entry.value(QStringLiteral("albumArtist")).toString().trimmed();
            const QString genre = entry.value(QStringLiteral("genre")).toString().trimmed();
            const QString year = entry.value(QStringLiteral("year")).toString().trimmed();
            const int trackNumber = entry.value(QStringLiteral("trackNumber")).toInt();
            if (!album.isEmpty()) arguments << QStringLiteral("-metadata") << QStringLiteral("album=%1").arg(album);
            if (!albumArtist.isEmpty()) arguments << QStringLiteral("-metadata") << QStringLiteral("album_artist=%1").arg(albumArtist);
            if (!genre.isEmpty()) arguments << QStringLiteral("-metadata") << QStringLiteral("genre=%1").arg(genre);
            if (!year.isEmpty()) arguments << QStringLiteral("-metadata") << QStringLiteral("date=%1").arg(year);
            if (trackNumber > 0) arguments << QStringLiteral("-metadata") << QStringLiteral("track=%1").arg(trackNumber);
            arguments << temporary;

            QProcess process;
            process.setProgram(ffmpeg);
            process.setArguments(arguments);
            process.start();
            bool written = process.waitForStarted(2500) && process.waitForFinished(120000) &&
                           process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0 &&
                           verifyAudioContainer(ffprobe, temporary);
            if (!written) {
                if (process.state() != QProcess::NotRunning) {
                    process.kill();
                    process.waitForFinished(500);
                }
                QFile::remove(temporary);
                payload.failures.append(displayName);
                ++payload.failed;
                continue;
            }

            QFile::setPermissions(temporary, QFile::permissions(source));
            if (!QFile::rename(source, originalHold)) {
                QFile::remove(temporary);
                payload.failures.append(displayName);
                ++payload.failed;
                continue;
            }
            if (!QFile::rename(temporary, target)) {
                QFile::rename(originalHold, source);
                QFile::remove(temporary);
                payload.failures.append(displayName);
                ++payload.failed;
                continue;
            }
            QFile::remove(originalHold);

            payload.changes.append(QVariantMap{
                {QStringLiteral("oldPath"), source},
                {QStringLiteral("newPath"), QDir::cleanPath(target)},
                {QStringLiteral("title"), entry.value(QStringLiteral("title"))},
                {QStringLiteral("artist"), entry.value(QStringLiteral("metadataArtist"))}
            });
            ++payload.completed;
        }

        if (self) {
            QMetaObject::invokeMethod(self, [self, total]() {
                if (!self) return;
                self->m_metadataRepairCurrent = total;
                self->m_metadataRepairStatus = QStringLiteral("Finalizing music library…");
                emit self->metadataRepairStateChanged();
            }, Qt::QueuedConnection);
        }
        return payload;
    }));
    return true;
}

void MusicPlayerManager::setVisualizationMode(const QString &mode)
{
    QString selected = QStringLiteral("Atom");
    for (const QString &candidate : visualizationModes()) {
        if (candidate.compare(mode, Qt::CaseInsensitive) == 0) {
            selected = candidate;
            break;
        }
    }
    if (m_visualizationMode == selected)
        return;
    m_visualizationMode = selected;
    saveSettings();
    emit visualizationModeChanged();
}

void MusicPlayerManager::setVisualizationConsumerActive(bool active)
{
    if (m_visualizationConsumerActive == active)
        return;
    m_visualizationConsumerActive = active;
    emit visualizationConsumerActiveChanged();
    updateVisualizationTimer();
}

void MusicPlayerManager::updateVisualizationTimer()
{
    const bool shouldRun = m_visualizationConsumerActive && m_playing && !m_paused;
    if (shouldRun) {
        if (!m_spectrumTimer.isActive())
            m_spectrumTimer.start();
    } else {
        m_spectrumTimer.stop();
        if (!m_visualizationConsumerActive) {
            QVariantList values;
            values.reserve(64);
            for (int i = 0; i < 64; ++i)
                values.append(0.0);
            if (m_spectrum != values) {
                m_spectrum = values;
                emit spectrumChanged();
            }
        }
    }
}

void MusicPlayerManager::updateSpectrum()
{
    if (!m_visualizationConsumerActive)
        return;
    QVariantList values;
    values.reserve(64);
    if (!m_playing || m_paused) {
        for (int i = 0; i < 64; ++i)
            values.append(0.035);
    } else {
        const double seconds = static_cast<double>(m_positionMs) / 1000.0;
        const uint seed = qHash(m_currentTrack.value(QStringLiteral("id")).toString());
        for (int i = 0; i < 64; ++i) {
            const double lowRollOff = std::exp(-static_cast<double>(i) / 20.0);
            const double wave1 = 0.5 + 0.5 * std::sin(seconds * (3.0 + (seed % 7) * 0.13) + i * 0.47);
            const double wave2 = 0.5 + 0.5 * std::sin(seconds * 7.1 + i * 1.21 + (seed % 31));
            const double pulse = std::pow(0.5 + 0.5 * std::sin(seconds * 2.2 + (seed % 17)), 4.0);
            const double value = std::clamp(0.05 + lowRollOff * (0.37 * wave1 + 0.22 * wave2 + 0.28 * pulse),
                                            0.03, 1.0);
            values.append(value);
        }
    }
    m_spectrum = values;
    emit spectrumChanged();
}

QString MusicPlayerManager::formatDuration(qint64 milliseconds) const
{
    return durationText(milliseconds);
}

void MusicPlayerManager::pruneQueue()
{
    QStringList cleaned;
    for (const QString &path : m_queuePaths) {
        if (trackIndexForPath(path) >= 0)
            cleaned.append(path);
    }
    m_queuePaths = cleaned;
    if (m_queuePaths.isEmpty())
        m_currentQueueIndex = -1;
    else if (m_currentQueueIndex >= m_queuePaths.size())
        m_currentQueueIndex = m_queuePaths.size() - 1;
}

QString MusicPlayerManager::stateDirectory() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/musicplayer"));
}
QString MusicPlayerManager::settingsPath() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("settings.json"));
}
QString MusicPlayerManager::cachePath() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("library-cache.json"));
}
QString MusicPlayerManager::playlistsPath() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("playlists.json"));
}
QString MusicPlayerManager::artworkDirectory() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("artwork"));
}
QString MusicPlayerManager::socketPath() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("mpv.sock"));
}

void MusicPlayerManager::ensureStateDirectories()
{
    QDir().mkpath(defaultMusicPath());
    QDir().mkpath(stateDirectory());
    QDir().mkpath(artworkDirectory());
}

void MusicPlayerManager::loadSettings()
{
    const QJsonDocument document = readJsonFile(settingsPath());
    if (document.isObject()) {
        const QJsonObject object = document.object();
        m_volume = std::clamp(object.value(QStringLiteral("volume")).toInt(78), 0, 100);
        m_shuffle = object.value(QStringLiteral("shuffle")).toBool(false);
        m_repeatMode = object.value(QStringLiteral("repeatMode")).toString(QStringLiteral("off"));
        m_equalizerPreset = object.value(QStringLiteral("equalizerPreset")).toString(QStringLiteral("Flat"));
        m_selectedAudioOutput = object.value(QStringLiteral("audioOutput")).toString(QStringLiteral("auto"));
        m_visualizationMode = object.value(QStringLiteral("visualizationMode")).toString(QStringLiteral("Atom"));
        const QJsonArray roots = object.value(QStringLiteral("libraryRoots")).toArray();
        for (const QJsonValue &value : roots) {
            const QString path = normalizedPath(value.toString());
            if (QDir(path).exists() && !m_libraryRoots.contains(path))
                m_libraryRoots.append(path);
        }
    }
    const QString canonicalMusic = defaultMusicPath();
    if (!m_libraryRoots.contains(canonicalMusic))
        m_libraryRoots.prepend(canonicalMusic);

    // Recognize previous roots created when the system service resolved QStandardPaths
    // against root instead of the real NeutronOS user. They remain readable until the
    // user chooses to move their files into the canonical Music folder.
    const QStringList suggested = suggestedLibraryRoots();
    for (const QString &path : suggested) {
        if (QDir(path).exists() && !m_libraryRoots.contains(path))
            m_libraryRoots.append(path);
    }

    m_libraryRoots.removeDuplicates();
    saveSettings();
    emit libraryRootsChanged();
}

bool MusicPlayerManager::saveSettings() const
{
    QJsonArray roots;
    for (const QString &root : m_libraryRoots)
        roots.append(root);
    QJsonObject object;
    object.insert(QStringLiteral("volume"), m_volume);
    object.insert(QStringLiteral("shuffle"), m_shuffle);
    object.insert(QStringLiteral("repeatMode"), m_repeatMode);
    object.insert(QStringLiteral("equalizerPreset"), m_equalizerPreset);
    object.insert(QStringLiteral("audioOutput"), m_selectedAudioOutput);
    object.insert(QStringLiteral("visualizationMode"), m_visualizationMode);
    object.insert(QStringLiteral("libraryRoots"), roots);
    return writeJsonFile(settingsPath(), QJsonDocument(object));
}

void MusicPlayerManager::loadLibraryCache()
{
    const QJsonDocument document = readJsonFile(cachePath());
    if (!document.isObject())
        return;
    const QJsonObject root = document.object();
    m_libraryCache = root.value(QStringLiteral("entries")).toObject().toVariantMap();
    m_tracks.clear();
    for (auto iterator = m_libraryCache.cbegin(); iterator != m_libraryCache.cend(); ++iterator) {
        const QVariantMap track = iterator.value().toMap().value(QStringLiteral("track")).toMap();
        if (!track.isEmpty() && QFileInfo::exists(track.value(QStringLiteral("path")).toString()))
            m_tracks.append(track);
    }
    std::sort(m_tracks.begin(), m_tracks.end(), [](const QVariant &a, const QVariant &b) {
        return QString::localeAwareCompare(a.toMap().value(QStringLiteral("title")).toString(),
                                           b.toMap().value(QStringLiteral("title")).toString()) < 0;
    });
}

bool MusicPlayerManager::saveLibraryCache() const
{
    QJsonObject root;
    root.insert(QStringLiteral("version"), 1);
    root.insert(QStringLiteral("generated"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    root.insert(QStringLiteral("entries"), QJsonObject::fromVariantMap(m_libraryCache));
    return writeJsonFile(cachePath(), QJsonDocument(root));
}

void MusicPlayerManager::loadPlaylists()
{
    const QJsonDocument document = readJsonFile(playlistsPath());
    m_playlists.clear();
    if (document.isArray()) {
        for (const QJsonValue &value : document.array()) {
            QVariantMap playlist = value.toObject().toVariantMap();
            QStringList paths = playlist.value(QStringLiteral("paths")).toStringList();
            paths.removeDuplicates();
            playlist.insert(QStringLiteral("paths"), paths);
            playlist.insert(QStringLiteral("trackCount"), paths.size());
            if (!playlist.value(QStringLiteral("name")).toString().trimmed().isEmpty())
                m_playlists.append(playlist);
        }
    }
    emit playlistsChanged();
}

bool MusicPlayerManager::savePlaylists() const
{
    return writeJsonFile(playlistsPath(), QJsonDocument(QJsonArray::fromVariantList(m_playlists)));
}

void MusicPlayerManager::setInitialized(bool value)
{
    if (m_initialized == value)
        return;
    m_initialized = value;
    emit initializedChanged();
}
void MusicPlayerManager::setBusy(bool value)
{
    if (m_busy == value)
        return;
    m_busy = value;
    emit busyChanged();
}
void MusicPlayerManager::setPlayerAvailable(bool value)
{
    if (m_playerAvailable == value)
        return;
    m_playerAvailable = value;
    emit playerAvailableChanged();
}
void MusicPlayerManager::setPlayerConnected(bool value)
{
    if (m_playerConnected == value)
        return;
    m_playerConnected = value;
    emit playerConnectedChanged();
}
void MusicPlayerManager::setStatus(const QString &value)
{
    if (m_status == value)
        return;
    m_status = value;
    emit statusChanged();
}
void MusicPlayerManager::setError(const QString &value)
{
    if (m_error == value)
        return;
    m_error = value;
    emit errorChanged();
}
