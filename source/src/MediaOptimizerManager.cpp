#include "MediaOptimizerManager.h"
#include "DeveloperModeManager.h"

#include <QtConcurrent>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaType>
#include <QPointer>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSet>
#include <QTextStream>
#include <QTimer>
#include <QUuid>
#include <QFileDevice>

#include <algorithm>

namespace {
const QStringList kMediaExtensions = {
    QStringLiteral("*.mkv"), QStringLiteral("*.mp4"), QStringLiteral("*.m4v"),
    QStringLiteral("*.mov"), QStringLiteral("*.avi"), QStringLiteral("*.webm"),
    QStringLiteral("*.ts"), QStringLiteral("*.m2ts"), QStringLiteral("*.mts"),
    QStringLiteral("*.mpg"), QStringLiteral("*.mpeg"), QStringLiteral("*.wmv")
};

QString tagValue(const QJsonObject &stream, const QString &key)
{
    return stream.value(QStringLiteral("tags")).toObject().value(key).toString();
}

QString streamLanguage(const QJsonObject &stream)
{
    QString language = tagValue(stream, QStringLiteral("language")).trimmed().toLower();
    return language.isEmpty() ? QStringLiteral("und") : language;
}

bool streamDefault(const QJsonObject &stream)
{
    return stream.value(QStringLiteral("disposition")).toObject()
                 .value(QStringLiteral("default")).toInt() == 1;
}

QString normalizedChoice(const QVariant &value)
{
    QString text = value.toString().trimmed().toUpper();
    text.replace(QRegularExpression(QStringLiteral("[^A-Z0-9]+")), QStringLiteral("_"));
    while (text.startsWith(QLatin1Char('_')))
        text.remove(0, 1);
    while (text.endsWith(QLatin1Char('_')))
        text.chop(1);
    return text;
}

bool isUnchangedChoice(const QVariant &value)
{
    const QString choice = normalizedChoice(value);
    return choice.isEmpty() || choice == QStringLiteral("UNCHANGED") ||
           choice == QStringLiteral("ORIGINAL") || choice == QStringLiteral("KEEP") ||
           choice == QStringLiteral("CURRENT");
}

bool hasExplicitPositiveNumber(const QVariantMap &settings, const QString &key)
{
    if (!settings.contains(key) || isUnchangedChoice(settings.value(key)))
        return false;
    bool ok = false;
    const qlonglong value = settings.value(key).toLongLong(&ok);
    return ok && value > 0;
}

QString sourceVideoEncoderMode(const QVariantMap &item)
{
    const QString codec = normalizedChoice(item.value(QStringLiteral("videoCodec")));
    if (codec == QStringLiteral("HEVC") || codec == QStringLiteral("H265"))
        return QStringLiteral("H265");
    if (codec == QStringLiteral("H264") || codec == QStringLiteral("AVC"))
        return QStringLiteral("H264");
    if (codec == QStringLiteral("AV1"))
        return QStringLiteral("AV1");
    if (codec == QStringLiteral("VP9"))
        return QStringLiteral("VP9");
    return QStringLiteral("H264");
}

QString sourceAudioEncoderMode(const QVariantMap &item)
{
    const QVariantList tracks = item.value(QStringLiteral("audioTracks")).toList();
    if (tracks.isEmpty())
        return QStringLiteral("AAC");
    const QString codec = normalizedChoice(tracks.constFirst().toMap().value(QStringLiteral("codec")));
    if (codec == QStringLiteral("AAC")) return QStringLiteral("AAC");
    if (codec == QStringLiteral("AC3")) return QStringLiteral("AC3");
    if (codec == QStringLiteral("EAC3")) return QStringLiteral("EAC3");
    if (codec == QStringLiteral("OPUS")) return QStringLiteral("OPUS");
    if (codec == QStringLiteral("MP3")) return QStringLiteral("MP3");
    if (codec == QStringLiteral("FLAC")) return QStringLiteral("FLAC");
    return QStringLiteral("AAC");
}
}

MediaOptimizerManager::MediaOptimizerManager(const QString &neutronRoot,
                                             DeveloperModeManager *developerModeManager,
                                             QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_developerModeManager(developerModeManager)
{
    m_scanWatcher = new QFutureWatcher<QVariantMap>(this);
    connect(m_scanWatcher, &QFutureWatcher<QVariantMap>::finished,
            this, &MediaOptimizerManager::onScanFinished);
    loadSettings();
    loadPresets();
    loadRenameHistory();
    refreshLocations();
}

MediaOptimizerManager::~MediaOptimizerManager()
{
    cancelOperation();
    if (m_scanWatcher && m_scanWatcher->isRunning()) {
        m_scanWatcher->cancel();
        m_scanWatcher->waitForFinished();
    }
}

QVariantList MediaOptimizerManager::locations() const { return m_locations; }
QVariantList MediaOptimizerManager::media() const { return m_media; }
QString MediaOptimizerManager::selectedRoot() const { return m_selectedRoot; }
bool MediaOptimizerManager::scanning() const { return m_scanning; }
bool MediaOptimizerManager::busy() const { return m_busy; }
int MediaOptimizerManager::progress() const { return m_progress; }
QString MediaOptimizerManager::operationStatus() const { return m_operationStatus; }
QString MediaOptimizerManager::lastMessage() const { return m_lastMessage; }
QString MediaOptimizerManager::currentInput() const { return m_currentInput; }
QString MediaOptimizerManager::currentOutput() const { return m_currentOutput; }
QString MediaOptimizerManager::scanCurrentFile() const { return m_scanCurrentFile; }
int MediaOptimizerManager::scanCurrentIndex() const { return m_scanCurrentIndex; }
int MediaOptimizerManager::scanTotalFiles() const { return m_scanTotalFiles; }
int MediaOptimizerManager::scanRemainingFiles() const { return m_scanRemainingFiles; }
int MediaOptimizerManager::scanCachedFiles() const { return m_scanCachedFiles; }
int MediaOptimizerManager::scanNewFiles() const { return m_scanNewFiles; }
int MediaOptimizerManager::scanBatchSize() const { return m_scanBatchSize; }
int MediaOptimizerManager::scanProcessedThisBatch() const { return m_scanProcessedThisBatch; }
int MediaOptimizerManager::scanPendingFiles() const { return m_scanPendingFiles; }
bool MediaOptimizerManager::scanComplete() const { return m_scanComplete; }
bool MediaOptimizerManager::ffmpegAvailable() const { return m_ffmpegAvailable; }
bool MediaOptimizerManager::ffprobeAvailable() const { return m_ffprobeAvailable; }
bool MediaOptimizerManager::allow4K() const { return m_allow4K; }
bool MediaOptimizerManager::queueActive() const { return m_queueActive; }
int MediaOptimizerManager::queueCompleted() const { return m_queueCompleted; }
int MediaOptimizerManager::queueTotal() const { return m_queueTotal; }
int MediaOptimizerManager::queueRemaining() const { return qMax(0, m_queueTotal - m_queueCompleted); }
QString MediaOptimizerManager::queueStage() const { return m_queueStage; }
qint64 MediaOptimizerManager::queueEstimatedMs() const { return m_queueEstimatedMs; }
qint64 MediaOptimizerManager::queueStorageDelta() const { return m_queueStorageDelta; }
QVariantList MediaOptimizerManager::queueErrors() const { return m_queueErrors; }
bool MediaOptimizerManager::renameActive() const { return m_renameActive; }
int MediaOptimizerManager::renameCompleted() const { return m_renameCompleted; }
int MediaOptimizerManager::renameTotal() const { return m_renameQueue.size(); }
int MediaOptimizerManager::renameRemaining() const { return qMax(0, m_renameQueue.size() - m_renameCompleted); }
QString MediaOptimizerManager::renameCurrentFile() const { return m_renameCurrentFile; }
QString MediaOptimizerManager::renameStatus() const { return m_renameStatus; }
QVariantList MediaOptimizerManager::renameErrors() const { return m_renameErrors; }
bool MediaOptimizerManager::renameUndoAvailable() const { return !m_lastRenameUndo.isEmpty(); }

QString MediaOptimizerManager::settingsPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/apps/mediaoptimizer/settings.json"));
}

void MediaOptimizerManager::loadSettings()
{
    // Patch 61G: 4K conversion permission is deliberately session-only.
    // A previous session can never leave the next Media Optimizer launch armed.
    m_allow4K = false;

    QFile file(settingsPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return;
    const QJsonObject object = document.object();
    const int storedBatchSize = object.value(QStringLiteral("scanBatchSize")).toInt(500);
    const QSet<int> allowedBatchSizes{100, 250, 500, 1000, 2500, 0};
    m_scanBatchSize = allowedBatchSizes.contains(storedBatchSize) ? storedBatchSize : 500;
}

void MediaOptimizerManager::saveSettings() const
{
    const QString path = settingsPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    const QJsonObject object{
        {QStringLiteral("scanBatchSize"), m_scanBatchSize}
    };
    const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(payload) == payload.size())
        file.commit();
}

QString MediaOptimizerManager::presetsPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/apps/mediaoptimizer/presets.json"));
}

void MediaOptimizerManager::loadPresets()
{
    m_customPresets.clear();
    QFile file(presetsPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isArray())
        return;
    for (const QJsonValue &value : document.array()) {
        if (value.isObject())
            m_customPresets.append(value.toObject().toVariantMap());
    }
}

void MediaOptimizerManager::savePresets() const
{
    const QString path = presetsPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QJsonArray array;
    for (const QVariant &value : m_customPresets)
        array.append(QJsonObject::fromVariantMap(value.toMap()));
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    const QByteArray payload = QJsonDocument(array).toJson(QJsonDocument::Indented);
    if (file.write(payload) == payload.size())
        file.commit();
}

void MediaOptimizerManager::setAllow4K(bool enabled)
{
    if (m_allow4K == enabled)
        return;
    m_allow4K = enabled;
    applyPolicyToMedia();
    emit settingsChanged();
    emit mediaChanged();
}

void MediaOptimizerManager::setScanBatchSize(int size)
{
    const QSet<int> allowedBatchSizes{100, 250, 500, 1000, 2500, 0};
    if (!allowedBatchSizes.contains(size) || m_scanBatchSize == size)
        return;
    m_scanBatchSize = size;
    saveSettings();
    emit settingsChanged();
}

QVariantList MediaOptimizerManager::scanBatchOptions() const
{
    return {
        QVariantMap{{QStringLiteral("value"), 100}, {QStringLiteral("label"), QStringLiteral("100")}, {QStringLiteral("description"), QStringLiteral("Probe up to 100 new or changed files")}},
        QVariantMap{{QStringLiteral("value"), 250}, {QStringLiteral("label"), QStringLiteral("250")}, {QStringLiteral("description"), QStringLiteral("Probe up to 250 new or changed files")}},
        QVariantMap{{QStringLiteral("value"), 500}, {QStringLiteral("label"), QStringLiteral("500")}, {QStringLiteral("description"), QStringLiteral("Balanced default for large libraries")}},
        QVariantMap{{QStringLiteral("value"), 1000}, {QStringLiteral("label"), QStringLiteral("1000")}, {QStringLiteral("description"), QStringLiteral("Probe up to 1000 new or changed files")}},
        QVariantMap{{QStringLiteral("value"), 2500}, {QStringLiteral("label"), QStringLiteral("2500")}, {QStringLiteral("description"), QStringLiteral("Large foreground scan batch")}},
        QVariantMap{{QStringLiteral("value"), 0}, {QStringLiteral("label"), QStringLiteral("ALL")}, {QStringLiteral("description"), QStringLiteral("Finish every remaining new or changed file")}}
    };
}

void MediaOptimizerManager::applyPolicyToMedia()
{
    QVariantList updated;
    updated.reserve(m_media.size());
    for (const QVariant &value : m_media)
        updated.append(applyCompatibilityPolicy(value.toMap(), m_allow4K));
    m_media = updated;
}

QVariantMap MediaOptimizerManager::defaultSafeConfiguration() const
{
    return {
        {QStringLiteral("id"), QStringLiteral("safe-unchanged")},
        {QStringLiteral("name"), QStringLiteral("Unchanged")},
        {QStringLiteral("videoCodec"), QStringLiteral("Unchanged")},
        {QStringLiteral("container"), QStringLiteral("Unchanged")},
        {QStringLiteral("videoBitrateKbps"), QStringLiteral("Unchanged")},
        {QStringLiteral("resolution"), QStringLiteral("Unchanged")},
        {QStringLiteral("frameRate"), QStringLiteral("Unchanged")},
        {QStringLiteral("profile"), QStringLiteral("Unchanged")},
        {QStringLiteral("pixelFormat"), QStringLiteral("Unchanged")},
        {QStringLiteral("encoderPreference"), QStringLiteral("Unchanged")},
        {QStringLiteral("audioCodec"), QStringLiteral("Unchanged")},
        {QStringLiteral("audioChannels"), QStringLiteral("Unchanged")},
        {QStringLiteral("audioBitrateKbps"), QStringLiteral("Unchanged")},
        {QStringLiteral("sampleRate"), QStringLiteral("Unchanged")},
        {QStringLiteral("trackMode"), QStringLiteral("Unchanged")},
        {QStringLiteral("subtitleMode"), QStringLiteral("Unchanged")},
        {QStringLiteral("subtitleInjectionPath"), QString()},
        {QStringLiteral("metadataMode"), QStringLiteral("Unchanged")},
        {QStringLiteral("fourKPolicy"), QStringLiteral("Keep 4K Unchanged")}
    };
}

QVariantMap MediaOptimizerManager::defaultRokuConfiguration() const
{
    return {
        {QStringLiteral("id"), QStringLiteral("roku-tv")},
        {QStringLiteral("name"), QStringLiteral("Roku TV")},
        {QStringLiteral("videoCodec"), QStringLiteral("H265")},
        {QStringLiteral("container"), QStringLiteral("MKV")},
        {QStringLiteral("videoBitrateKbps"), 8000},
        {QStringLiteral("resolution"), QStringLiteral("Original")},
        {QStringLiteral("frameRate"), QStringLiteral("Original")},
        {QStringLiteral("profile"), QStringLiteral("Main")},
        {QStringLiteral("pixelFormat"), QStringLiteral("yuv420p")},
        {QStringLiteral("encoderPreference"), QStringLiteral("Auto")},
        {QStringLiteral("audioCodec"), QStringLiteral("AAC")},
        {QStringLiteral("audioChannels"), QStringLiteral("5.1")},
        {QStringLiteral("audioBitrateKbps"), 640},
        {QStringLiteral("sampleRate"), 48000},
        {QStringLiteral("trackMode"), QStringLiteral("BEST_ENGLISH")},
        {QStringLiteral("subtitleMode"), QStringLiteral("KEEP_ENGLISH_TEXT")},
        {QStringLiteral("subtitleInjectionPath"), QString()},
        {QStringLiteral("metadataMode"), QStringLiteral("Preserve")},
        {QStringLiteral("fourKPolicy"), QStringLiteral("Keep 4K Unchanged")},
        {QStringLiteral("copyMetadata"), true}
    };
}

bool MediaOptimizerManager::videoConversionSelected(const QVariantMap &settings) const
{
    return !isUnchangedChoice(settings.value(QStringLiteral("videoCodec"))) ||
           hasExplicitPositiveNumber(settings, QStringLiteral("videoBitrateKbps")) ||
           !isUnchangedChoice(settings.value(QStringLiteral("resolution"))) ||
           !isUnchangedChoice(settings.value(QStringLiteral("frameRate"))) ||
           !isUnchangedChoice(settings.value(QStringLiteral("profile"))) ||
           !isUnchangedChoice(settings.value(QStringLiteral("pixelFormat")));
}

bool MediaOptimizerManager::configurationHasActualChanges(const QVariantMap &configuration) const
{
    if (videoConversionSelected(configuration))
        return true;
    if (!isUnchangedChoice(configuration.value(QStringLiteral("container"))) ||
        !isUnchangedChoice(configuration.value(QStringLiteral("audioCodec"))) ||
        !isUnchangedChoice(configuration.value(QStringLiteral("audioChannels"))) ||
        hasExplicitPositiveNumber(configuration, QStringLiteral("audioBitrateKbps")) ||
        hasExplicitPositiveNumber(configuration, QStringLiteral("sampleRate")) ||
        !isUnchangedChoice(configuration.value(QStringLiteral("trackMode"))) ||
        !isUnchangedChoice(configuration.value(QStringLiteral("subtitleMode"))) ||
        !configuration.value(QStringLiteral("subtitleInjectionPath")).toString().trimmed().isEmpty() ||
        !isUnchangedChoice(configuration.value(QStringLiteral("metadataMode"))))
        return true;

    // Compatibility with older saved presets. The safe Patch 61G baseline does
    // not write copyMetadata, but a legacy preset still counts as an explicit
    // metadata operation.
    return configuration.contains(QStringLiteral("copyMetadata"));
}

bool MediaOptimizerManager::configurationHasChanges(const QVariantMap &configuration) const
{
    return configurationHasActualChanges(configuration);
}

void MediaOptimizerManager::completeAnalysisOnly()
{
    clear4KAuthorization();
    m_operationStatus = QStringLiteral("Scan/cache analysis complete");
    m_progress = 100;
    m_lastMessage = QStringLiteral("No changes selected. NeutronOS completed scan/cache analysis only; no media file was rewritten.");
    emit stateChanged();
}

void MediaOptimizerManager::resetSessionSafety()
{
    clear4KAuthorization();
    if (!m_queueActive && !m_busy)
        m_queue4KAuthorized = false;
    if (m_allow4K) {
        m_allow4K = false;
        applyPolicyToMedia();
        emit settingsChanged();
        emit mediaChanged();
    }
}

QString MediaOptimizerManager::normalized4KPolicy(const QVariantMap &settings) const
{
    const QString policy = normalizedChoice(settings.value(QStringLiteral("fourKPolicy"),
                                                            QStringLiteral("Keep 4K Unchanged")));
    if (policy == QStringLiteral("ALLOW_4K_CONVERSION") || policy == QStringLiteral("ALLOW_4K"))
        return QStringLiteral("ALLOW_4K_CONVERSION");
    if (policy == QStringLiteral("SKIP_4K_FILES") || policy == QStringLiteral("SKIP_4K"))
        return QStringLiteral("SKIP_4K_FILES");
    return QStringLiteral("KEEP_4K_UNCHANGED");
}

QByteArray MediaOptimizerManager::fourKAuthorizationFingerprint(const QVariantList &paths,
                                                                 const QVariantMap &settings) const
{
    QStringList canonicalPaths;
    for (const QVariant &value : paths) {
        const QString path = QFileInfo(value.toString()).absoluteFilePath();
        if (!path.isEmpty() && !canonicalPaths.contains(path))
            canonicalPaths.append(path);
    }
    canonicalPaths.sort(Qt::CaseSensitive);

    QJsonObject payload;
    payload.insert(QStringLiteral("paths"), QJsonArray::fromStringList(canonicalPaths));
    payload.insert(QStringLiteral("settings"), QJsonObject::fromVariantMap(settings));
    return QCryptographicHash::hash(QJsonDocument(payload).toJson(QJsonDocument::Compact),
                                    QCryptographicHash::Sha256);
}

void MediaOptimizerManager::clear4KAuthorization()
{
    m_pending4KToken.clear();
    m_pending4KFingerprint.clear();
    m_authorized4KFingerprint.clear();
}

QVariantMap MediaOptimizerManager::prepare4KConversionWarning(const QVariantList &paths,
                                                               const QVariantMap &settings)
{
    clear4KAuthorization();
    QVariantMap warning{{QStringLiteral("required"), false}};
    if (normalized4KPolicy(settings) != QStringLiteral("ALLOW_4K_CONVERSION") ||
        !videoConversionSelected(settings))
        return warning;

    QVariantList files;
    for (const QVariant &value : paths) {
        const QVariantMap item = findMedia(value.toString());
        if (item.isEmpty() || !item.value(QStringLiteral("is4K")).toBool())
            continue;

        const QString sourceResolution = item.value(QStringLiteral("resolution")).toString();
        const QString sourceCodec = item.value(QStringLiteral("videoCodec")).toString().toUpper();
        const QVariant resolutionSetting = settings.value(QStringLiteral("resolution"));
        const QVariant codecSetting = settings.value(QStringLiteral("videoCodec"));
        const QString targetResolution = isUnchangedChoice(resolutionSetting)
            ? sourceResolution : resolutionSetting.toString();
        const QString targetCodec = isUnchangedChoice(codecSetting)
            ? sourceCodec : codecSetting.toString().toUpper();
        files.append(QVariantMap{
            {QStringLiteral("path"), item.value(QStringLiteral("path"))},
            {QStringLiteral("fileName"), item.value(QStringLiteral("name"))},
            {QStringLiteral("sourceResolution"), sourceResolution},
            {QStringLiteral("sourceCodec"), sourceCodec},
            {QStringLiteral("targetResolution"), targetResolution},
            {QStringLiteral("targetCodec"), targetCodec}
        });
    }

    if (files.isEmpty())
        return warning;

    m_pending4KToken = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_pending4KFingerprint = fourKAuthorizationFingerprint(paths, settings);
    warning.insert(QStringLiteral("required"), true);
    warning.insert(QStringLiteral("token"), m_pending4KToken);
    warning.insert(QStringLiteral("count"), files.size());
    warning.insert(QStringLiteral("files"), files);
    warning.insert(QStringLiteral("message"),
                   QStringLiteral("4K video conversion is blocked until this separate danger confirmation is armed."));
    return warning;
}

bool MediaOptimizerManager::arm4KConversion(const QString &token)
{
    if (token.isEmpty() || token != m_pending4KToken || m_pending4KFingerprint.isEmpty()) {
        m_lastMessage = QStringLiteral("The 4K conversion authorization expired. Review the danger warning again.");
        emit stateChanged();
        return false;
    }
    m_authorized4KFingerprint = m_pending4KFingerprint;
    m_pending4KToken.clear();
    m_pending4KFingerprint.clear();
    m_lastMessage = QStringLiteral("4K conversion armed for this exact queue and configuration only.");
    emit stateChanged();
    return true;
}

QVariantList MediaOptimizerManager::presets() const
{
    QVariantList result;
    QVariantMap roku = defaultRokuConfiguration();
    roku.insert(QStringLiteral("builtIn"), true);
    roku.insert(QStringLiteral("description"), QStringLiteral("Roku TV direct-play profile with editable HEVC, AAC 5.1 and English text subtitles."));
    result.append(roku);
    for (const QVariant &value : m_customPresets)
        result.append(value);
    return result;
}

bool MediaOptimizerManager::savePreset(const QString &name, const QVariantMap &configuration)
{
    const QString cleanName = name.trimmed();
    if (cleanName.isEmpty()) {
        m_lastMessage = QStringLiteral("Enter a preset name.");
        emit stateChanged();
        return false;
    }
    const QString id = QStringLiteral("custom-") + QString::fromLatin1(
        QCryptographicHash::hash(cleanName.toLower().toUtf8(), QCryptographicHash::Sha256).toHex().left(12));
    QVariantMap entry = configuration;
    entry.insert(QStringLiteral("id"), id);
    entry.insert(QStringLiteral("name"), cleanName);
    entry.insert(QStringLiteral("builtIn"), false);
    entry.insert(QStringLiteral("description"), QStringLiteral("Custom Media Optimizer compatibility profile."));
    bool replaced = false;
    for (int i = 0; i < m_customPresets.size(); ++i) {
        if (m_customPresets.at(i).toMap().value(QStringLiteral("id")).toString() == id) {
            m_customPresets[i] = entry;
            replaced = true;
            break;
        }
    }
    if (!replaced)
        m_customPresets.append(entry);
    savePresets();
    m_lastMessage = QStringLiteral("Preset saved: %1").arg(cleanName);
    emit presetsChanged();
    emit stateChanged();
    return true;
}

bool MediaOptimizerManager::deletePreset(const QString &id)
{
    if (id == QStringLiteral("roku-tv"))
        return false;
    for (int i = 0; i < m_customPresets.size(); ++i) {
        if (m_customPresets.at(i).toMap().value(QStringLiteral("id")).toString() == id) {
            m_customPresets.removeAt(i);
            savePresets();
            emit presetsChanged();
            return true;
        }
    }
    return false;
}

QVariantMap MediaOptimizerManager::encoderCapabilities() const
{
    return {
        {QStringLiteral("H264"), !selectVideoEncoder(QStringLiteral("H264")).isEmpty()},
        {QStringLiteral("H265"), !selectVideoEncoder(QStringLiteral("H265")).isEmpty()},
        {QStringLiteral("AV1"), !selectVideoEncoder(QStringLiteral("AV1")).isEmpty()},
        {QStringLiteral("VP9"), !selectVideoEncoder(QStringLiteral("VP9")).isEmpty()},
        {QStringLiteral("VVC"), !selectVideoEncoder(QStringLiteral("VVC")).isEmpty()},
        {QStringLiteral("WAV"), !selectAudioEncoder(QStringLiteral("WAV")).isEmpty()},
        {QStringLiteral("FLAC"), !selectAudioEncoder(QStringLiteral("FLAC")).isEmpty()},
        {QStringLiteral("AAC"), !selectAudioEncoder(QStringLiteral("AAC")).isEmpty()},
        {QStringLiteral("AC3"), !selectAudioEncoder(QStringLiteral("AC3")).isEmpty()},
        {QStringLiteral("OPUS"), !selectAudioEncoder(QStringLiteral("OPUS")).isEmpty()},
        {QStringLiteral("MP3"), !selectAudioEncoder(QStringLiteral("MP3")).isEmpty()}
    };
}

QString MediaOptimizerManager::executable(const QString &name)
{
    return QStandardPaths::findExecutable(name);
}

QString MediaOptimizerManager::canonicalDirectory(const QString &path)
{
    const QFileInfo info(path.trimmed());
    if (!info.exists() || !info.isDir())
        return QString();
    const QString canonical = info.canonicalFilePath();
    return QDir::cleanPath(canonical.isEmpty() ? info.absoluteFilePath() : canonical);
}

QString MediaOptimizerManager::humanBytes(qulonglong bytes)
{
    static const QStringList units = {QStringLiteral("B"), QStringLiteral("KiB"),
                                      QStringLiteral("MiB"), QStringLiteral("GiB"),
                                      QStringLiteral("TiB")};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < units.size() - 1) {
        value /= 1024.0;
        ++unit;
    }
    return QStringLiteral("%1 %2").arg(value, 0, 'f', unit == 0 ? 0 : 1).arg(units.at(unit));
}

QString MediaOptimizerManager::durationText(qint64 milliseconds)
{
    if (milliseconds <= 0)
        return QStringLiteral("Unknown");
    qint64 totalSeconds = milliseconds / 1000;
    const qint64 hours = totalSeconds / 3600;
    totalSeconds %= 3600;
    const qint64 minutes = totalSeconds / 60;
    const qint64 seconds = totalSeconds % 60;
    if (hours > 0)
        return QStringLiteral("%1:%2:%3").arg(hours).arg(minutes, 2, 10, QLatin1Char('0')).arg(seconds, 2, 10, QLatin1Char('0'));
    return QStringLiteral("%1:%2").arg(minutes).arg(seconds, 2, 10, QLatin1Char('0'));
}

QString MediaOptimizerManager::formatBytes(qulonglong bytes) const { return humanBytes(bytes); }
QString MediaOptimizerManager::formatSignedBytes(qint64 bytes) const
{
    return (bytes < 0 ? QStringLiteral("-") : QStringLiteral("+")) +
           humanBytes(static_cast<qulonglong>(qAbs(bytes)));
}
QString MediaOptimizerManager::formatDuration(qint64 milliseconds) const { return durationText(milliseconds); }

QString MediaOptimizerManager::canonicalUserHome() const
{
    const QFileInfo rootInfo(m_neutronRoot);
    const QString parent = rootInfo.absoluteDir().absolutePath();
    return canonicalDirectory(parent).isEmpty() ? parent : canonicalDirectory(parent);
}

QString MediaOptimizerManager::parentDirectory(const QString &path) const
{
    QDir directory(path);
    if (!directory.cdUp())
        return QDir::cleanPath(path);
    return directory.absolutePath();
}

QVariantList MediaOptimizerManager::mediaPickerEntries(const QString &path,
                                                        const QStringList &extensions) const
{
    QVariantList result;
    QDir directory(path);
    if (!directory.exists())
        return result;
    const QFileInfoList folders = directory.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot,
                                                           QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &info : folders) {
        result.append(QVariantMap{{QStringLiteral("name"), info.fileName()},
                                  {QStringLiteral("path"), info.absoluteFilePath()},
                                  {QStringLiteral("directory"), true}});
    }
    QStringList filters;
    for (QString extension : extensions) {
        extension = extension.trimmed();
        if (extension.startsWith(QLatin1Char('.')))
            extension.remove(0, 1);
        if (!extension.isEmpty())
            filters << QStringLiteral("*.%1").arg(extension);
    }
    if (!filters.isEmpty()) {
        const QFileInfoList files = directory.entryInfoList(filters, QDir::Files, QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo &info : files) {
            result.append(QVariantMap{{QStringLiteral("name"), info.fileName()},
                                      {QStringLiteral("path"), info.absoluteFilePath()},
                                      {QStringLiteral("directory"), false}});
        }
    }
    return result;
}

QString MediaOptimizerManager::normalizedCodec(const QString &codec)
{
    const QString value = codec.trimmed().toLower();
    if (value == QStringLiteral("h265") || value == QStringLiteral("hevc"))
        return QStringLiteral("hevc");
    if (value == QStringLiteral("avc") || value == QStringLiteral("avc1"))
        return QStringLiteral("h264");
    if (value == QStringLiteral("e-ac-3") || value == QStringLiteral("ec-3"))
        return QStringLiteral("eac3");
    return value;
}

bool MediaOptimizerManager::isVideoCodecCompatible(const QString &codec)
{
    const QString normalized = normalizedCodec(codec);
    return normalized == QStringLiteral("h264") ||
           normalized == QStringLiteral("hevc") ||
           normalized == QStringLiteral("av1");
}

bool MediaOptimizerManager::isEnglish(const QString &language)
{
    const QString value = language.trimmed().toLower();
    return value == QStringLiteral("eng") || value == QStringLiteral("en") ||
           value == QStringLiteral("english");
}

bool MediaOptimizerManager::isAudioTrackCompatible(const QVariantMap &track)
{
    const QString codec = normalizedCodec(track.value(QStringLiteral("codec")).toString());
    const int channels = track.value(QStringLiteral("channels")).toInt();
    return channels >= 1 && channels <= 6 &&
           (codec == QStringLiteral("aac") || codec == QStringLiteral("ac3") ||
            codec == QStringLiteral("eac3"));
}

bool MediaOptimizerManager::isImageSubtitleCodec(const QString &codec)
{
    const QString value = normalizedCodec(codec);
    return value == QStringLiteral("hdmv_pgs_subtitle") ||
           value == QStringLiteral("dvd_subtitle") ||
           value == QStringLiteral("dvb_subtitle") ||
           value == QStringLiteral("xsub") ||
           value == QStringLiteral("pgssub");
}

qint64 MediaOptimizerManager::jsonInteger(const QJsonValue &value)
{
    if (value.isDouble())
        return static_cast<qint64>(value.toDouble());
    bool ok = false;
    const qint64 result = value.toString().toLongLong(&ok);
    return ok ? result : 0;
}

double MediaOptimizerManager::jsonDouble(const QJsonValue &value)
{
    if (value.isDouble())
        return value.toDouble();
    bool ok = false;
    const double result = value.toString().toDouble(&ok);
    return ok ? result : 0.0;
}

QVariantMap MediaOptimizerManager::probeFile(const QString &ffprobe, const QString &path)
{
    QProcess process;
    process.setProgram(ffprobe);
    process.setArguments({QStringLiteral("-v"), QStringLiteral("error"),
                          QStringLiteral("-print_format"), QStringLiteral("json"),
                          QStringLiteral("-show_format"), QStringLiteral("-show_streams"), path});
    process.start();
    if (!process.waitForStarted(3000) || !process.waitForFinished(30000)) {
        process.kill();
        process.waitForFinished(1000);
        return {};
    }
    if (process.exitCode() != 0)
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(process.readAllStandardOutput());
    if (!document.isObject())
        return {};
    return document.object().toVariantMap();
}

QVariantMap MediaOptimizerManager::buildMediaItem(const QString &path, const QJsonObject &probe)
{
    const QFileInfo info(path);
    const QJsonArray streams = probe.value(QStringLiteral("streams")).toArray();
    const QJsonObject format = probe.value(QStringLiteral("format")).toObject();

    QVariantMap item;
    item[QStringLiteral("id")] = QString::fromLatin1(
        QCryptographicHash::hash(info.absoluteFilePath().toUtf8(), QCryptographicHash::Sha256)
            .toHex().left(20));
    item[QStringLiteral("path")] = info.absoluteFilePath();
    item[QStringLiteral("name")] = info.fileName();
    item[QStringLiteral("baseName")] = info.completeBaseName();
    item[QStringLiteral("directory")] = info.absolutePath();
    item[QStringLiteral("extension")] = info.suffix().toLower();
    item[QStringLiteral("sizeBytes")] = static_cast<qulonglong>(info.size());
    item[QStringLiteral("sizeText")] = humanBytes(static_cast<qulonglong>(qMax<qint64>(0, info.size())));
    item[QStringLiteral("modified")] = info.lastModified().toString(Qt::ISODate);
    item[QStringLiteral("accessed")] = info.lastRead().toString(Qt::ISODate);
    item[QStringLiteral("containerFormat")] = format.value(QStringLiteral("format_long_name")).toString();

    const double durationSeconds = jsonDouble(format.value(QStringLiteral("duration")));
    const qint64 durationMs = static_cast<qint64>(durationSeconds * 1000.0);
    item[QStringLiteral("durationMs")] = durationMs;
    item[QStringLiteral("durationText")] = durationText(durationMs);

    QVariantList audioTracks;
    QVariantList subtitleTracks;
    QString videoCodec;
    int width = 0;
    int height = 0;
    qint64 videoBitRate = 0;

    for (const QJsonValue &streamValue : streams) {
        const QJsonObject stream = streamValue.toObject();
        const QString type = stream.value(QStringLiteral("codec_type")).toString();
        const int streamIndex = stream.value(QStringLiteral("index")).toInt();
        if (type == QStringLiteral("video") && videoCodec.isEmpty()) {
            videoCodec = normalizedCodec(stream.value(QStringLiteral("codec_name")).toString());
            width = stream.value(QStringLiteral("width")).toInt();
            height = stream.value(QStringLiteral("height")).toInt();
            videoBitRate = jsonInteger(stream.value(QStringLiteral("bit_rate")));
        } else if (type == QStringLiteral("audio")) {
            const QString codec = normalizedCodec(stream.value(QStringLiteral("codec_name")).toString());
            const int channels = stream.value(QStringLiteral("channels")).toInt();
            const QString profile = stream.value(QStringLiteral("profile")).toString();
            const QString title = tagValue(stream, QStringLiteral("title"));
            const bool atmos = codec == QStringLiteral("eac3") &&
                (profile.contains(QStringLiteral("joc"), Qt::CaseInsensitive) ||
                 title.contains(QStringLiteral("atmos"), Qt::CaseInsensitive));
            QVariantMap track;
            track[QStringLiteral("index")] = streamIndex;
            track[QStringLiteral("codec")] = codec;
            track[QStringLiteral("codecLong")] = stream.value(QStringLiteral("codec_long_name")).toString();
            track[QStringLiteral("channels")] = channels;
            track[QStringLiteral("layout")] = stream.value(QStringLiteral("channel_layout")).toString();
            track[QStringLiteral("language")] = streamLanguage(stream);
            track[QStringLiteral("title")] = title;
            track[QStringLiteral("default")] = streamDefault(stream);
            track[QStringLiteral("atmos")] = atmos;
            track[QStringLiteral("bitRate")] = jsonInteger(stream.value(QStringLiteral("bit_rate")));
            track[QStringLiteral("compatible")] = isAudioTrackCompatible(track);
            audioTracks.append(track);
        } else if (type == QStringLiteral("subtitle")) {
            const QString codec = normalizedCodec(stream.value(QStringLiteral("codec_name")).toString());
            QVariantMap track;
            track[QStringLiteral("index")] = streamIndex;
            track[QStringLiteral("codec")] = codec;
            track[QStringLiteral("language")] = streamLanguage(stream);
            track[QStringLiteral("title")] = tagValue(stream, QStringLiteral("title"));
            track[QStringLiteral("default")] = streamDefault(stream);
            track[QStringLiteral("imageBased")] = isImageSubtitleCodec(codec);
            subtitleTracks.append(track);
        }
    }

    const bool resolutionKnown = width > 0 && height > 0;
    const bool is4K = width > 1920 || height > 1080;
    const bool codecCompatible = isVideoCodecCompatible(videoCodec);
    const bool resolutionCompatible = resolutionKnown && width <= 1920 && height <= 1080;
    const bool videoCompatible = codecCompatible && resolutionCompatible;
    bool audioCompatible = !audioTracks.isEmpty();
    bool hasEnglishAudio = false;
    for (const QVariant &trackValue : audioTracks) {
        const QVariantMap track = trackValue.toMap();
        audioCompatible = audioCompatible && track.value(QStringLiteral("compatible")).toBool();
        hasEnglishAudio = hasEnglishAudio || isEnglish(track.value(QStringLiteral("language")).toString());
    }
    bool hasImageSubtitles = false;
    bool hasEnglishSubtitles = false;
    for (const QVariant &trackValue : subtitleTracks) {
        const QVariantMap track = trackValue.toMap();
        hasImageSubtitles = hasImageSubtitles || track.value(QStringLiteral("imageBased")).toBool();
        hasEnglishSubtitles = hasEnglishSubtitles || isEnglish(track.value(QStringLiteral("language")).toString());
    }

    const bool needsVideo = !videoCompatible;
    const bool needsAudio = !audioCompatible;
    const bool needsSubtitles = hasImageSubtitles;
    const bool needsOptimization = needsVideo || needsAudio || needsSubtitles;
    QStringList reasons;
    if (!isVideoCodecCompatible(videoCodec))
        reasons.append(QStringLiteral("Video codec is outside the Roku compatibility set."));
    if (!resolutionCompatible)
        reasons.append(width > 1920 || height > 1080
                           ? QStringLiteral("Resolution exceeds the Pi 4 1080p conversion limit.")
                           : QStringLiteral("Video resolution could not be identified."));
    if (needsAudio)
        reasons.append(QStringLiteral("One or more audio tracks are not AAC/AC-3/E-AC-3 at 5.1 channels or below."));
    if (needsSubtitles)
        reasons.append(QStringLiteral("Image-based subtitles can force transcoding; removing them is preferred."));
    if (!needsOptimization)
        reasons.append(QStringLiteral("Direct-play compatible with the Roku preset."));

    qulonglong estimatedSavings = 0;
    if (needsOptimization && durationSeconds > 0.0 && info.size() > 0) {
        double targetBitsPerSecond = 0.0;
        if (needsVideo && resolutionCompatible)
            targetBitsPerSecond += height > 720 ? 5000000.0 : 3000000.0;
        else
            targetBitsPerSecond += videoBitRate > 0 ? static_cast<double>(videoBitRate) : 5000000.0;
        targetBitsPerSecond += 640000.0;
        const double estimatedBytes = targetBitsPerSecond * durationSeconds / 8.0;
        if (estimatedBytes < static_cast<double>(info.size()))
            estimatedSavings = static_cast<qulonglong>(static_cast<double>(info.size()) - estimatedBytes);
        else if (needsAudio || needsSubtitles)
            estimatedSavings = static_cast<qulonglong>(static_cast<double>(info.size()) * 0.03);
    }

    QStringList audioSummaryParts;
    for (const QVariant &trackValue : audioTracks) {
        const QVariantMap track = trackValue.toMap();
        const QString codecText = track.value(QStringLiteral("codec")).toString().toUpper();
        const int channels = track.value(QStringLiteral("channels")).toInt();
        const QString part = QStringLiteral("%1 %2ch").arg(codecText.isEmpty() ? QStringLiteral("UNKNOWN") : codecText)
                                                      .arg(channels > 0 ? channels : 0);
        if (!audioSummaryParts.contains(part))
            audioSummaryParts.append(part);
    }
    QStringList subtitleSummaryParts;
    int imageSubtitleCount = 0;
    for (const QVariant &trackValue : subtitleTracks) {
        const QVariantMap track = trackValue.toMap();
        if (track.value(QStringLiteral("imageBased")).toBool())
            ++imageSubtitleCount;
        const QString codecText = track.value(QStringLiteral("codec")).toString().toUpper();
        if (!codecText.isEmpty() && !subtitleSummaryParts.contains(codecText))
            subtitleSummaryParts.append(codecText);
    }

    item[QStringLiteral("videoCodecCompatible")] = codecCompatible;
    item[QStringLiteral("resolutionKnown")] = resolutionKnown;
    item[QStringLiteral("is4K")] = is4K;
    item[QStringLiteral("currentVideoText")] = QStringLiteral("%1 · %2")
        .arg(videoCodec.isEmpty() ? QStringLiteral("UNKNOWN") : videoCodec.toUpper())
        .arg(width > 0 && height > 0 ? QStringLiteral("%1×%2").arg(width).arg(height)
                                     : QStringLiteral("UNKNOWN RESOLUTION"));
    item[QStringLiteral("currentAudioText")] = audioSummaryParts.isEmpty()
        ? QStringLiteral("NO AUDIO TRACKS")
        : audioSummaryParts.mid(0, 3).join(QStringLiteral(" + "));
    item[QStringLiteral("currentSubtitleText")] = subtitleTracks.isEmpty()
        ? QStringLiteral("NO SUBTITLES")
        : QStringLiteral("%1 TRACK%2 · %3 IMAGE-BASED · %4")
              .arg(subtitleTracks.size())
              .arg(subtitleTracks.size() == 1 ? QString() : QStringLiteral("S"))
              .arg(imageSubtitleCount)
              .arg(subtitleSummaryParts.mid(0, 3).join(QStringLiteral(" / ")));

    item[QStringLiteral("videoCodec")] = videoCodec.isEmpty() ? QStringLiteral("unknown") : videoCodec;
    item[QStringLiteral("width")] = width;
    item[QStringLiteral("height")] = height;
    item[QStringLiteral("resolution")] = width > 0 && height > 0
        ? QStringLiteral("%1×%2").arg(width).arg(height)
        : QStringLiteral("Unknown");
    item[QStringLiteral("videoCompatible")] = videoCompatible;
    item[QStringLiteral("resolutionCompatible")] = resolutionCompatible;
    item[QStringLiteral("audioCompatible")] = audioCompatible;
    item[QStringLiteral("hasEnglishAudio")] = hasEnglishAudio;
    item[QStringLiteral("hasImageSubtitles")] = hasImageSubtitles;
    item[QStringLiteral("hasEnglishSubtitles")] = hasEnglishSubtitles;
    item[QStringLiteral("needsVideo")] = needsVideo;
    item[QStringLiteral("needsAudio")] = needsAudio;
    item[QStringLiteral("needsSubtitles")] = needsSubtitles;
    item[QStringLiteral("needsOptimization")] = needsOptimization;
    item[QStringLiteral("audioTracks")] = audioTracks;
    item[QStringLiteral("subtitleTracks")] = subtitleTracks;
    item[QStringLiteral("audioTrackCount")] = audioTracks.size();
    item[QStringLiteral("subtitleTrackCount")] = subtitleTracks.size();
    item[QStringLiteral("reasons")] = reasons;
    item[QStringLiteral("estimatedSavingsBytes")] = estimatedSavings;
    item[QStringLiteral("estimatedSavings")] = humanBytes(estimatedSavings);
    item[QStringLiteral("purpose")] = QStringLiteral("Video media container used for movie or episode playback.");
    return applyCompatibilityPolicy(item, false);
}

QVariantMap MediaOptimizerManager::applyCompatibilityPolicy(QVariantMap item, bool allow4K)
{
    const QString videoCodec = normalizedCodec(item.value(QStringLiteral("videoCodec")).toString());
    const int width = item.value(QStringLiteral("width")).toInt();
    const int height = item.value(QStringLiteral("height")).toInt();
    const bool codecCompatible = item.contains(QStringLiteral("videoCodecCompatible"))
        ? item.value(QStringLiteral("videoCodecCompatible")).toBool()
        : isVideoCodecCompatible(videoCodec);
    const bool is4K = item.contains(QStringLiteral("is4K"))
        ? item.value(QStringLiteral("is4K")).toBool()
        : (width > 1920 || height > 1080);
    const bool resolutionCompatible = item.contains(QStringLiteral("resolutionCompatible"))
        ? item.value(QStringLiteral("resolutionCompatible")).toBool()
        : (width > 0 && height > 0 && width <= 1920 && height <= 1080);
    item[QStringLiteral("videoCodecCompatible")] = codecCompatible;
    item[QStringLiteral("is4K")] = is4K;
    item[QStringLiteral("resolutionKnown")] = width > 0 && height > 0;
    if (!item.contains(QStringLiteral("currentVideoText"))) {
        item[QStringLiteral("currentVideoText")] = QStringLiteral("%1 · %2")
            .arg(videoCodec.isEmpty() ? QStringLiteral("UNKNOWN") : videoCodec.toUpper())
            .arg(width > 0 && height > 0 ? QStringLiteral("%1×%2").arg(width).arg(height)
                                         : QStringLiteral("UNKNOWN RESOLUTION"));
    }
    const bool videoCompatible = codecCompatible && (resolutionCompatible || (allow4K && is4K));
    const bool audioCompatible = item.value(QStringLiteral("audioCompatible")).toBool();
    const bool needsSubtitles = item.value(QStringLiteral("hasImageSubtitles")).toBool();
    const bool needsVideo = !videoCompatible;
    const bool needsAudio = !audioCompatible;

    item[QStringLiteral("allow4KApplied")] = allow4K;
    item[QStringLiteral("videoCompatible")] = videoCompatible;
    item[QStringLiteral("directPlayResolutionCompatible")] = resolutionCompatible || (allow4K && is4K);
    item[QStringLiteral("needsVideo")] = needsVideo;
    item[QStringLiteral("needsAudio")] = needsAudio;
    item[QStringLiteral("needsSubtitles")] = needsSubtitles;
    item[QStringLiteral("needsOptimization")] = needsVideo || needsAudio || needsSubtitles;

    QString recommendedVideo;
    if (videoCompatible)
        recommendedVideo = is4K && allow4K ? QStringLiteral("KEEP · 4K DIRECT PLAY") : QStringLiteral("KEEP CURRENT");
    else if (is4K)
        recommendedVideo = QStringLiteral("H.265/H.264 · CONVERT OFF-DEVICE");
    else
        recommendedVideo = QStringLiteral("H.265/HEVC · 1080P OR LOWER");
    item[QStringLiteral("recommendedVideoText")] = recommendedVideo;
    item[QStringLiteral("recommendedAudioText")] = audioCompatible
        ? QStringLiteral("KEEP CURRENT")
        : QStringLiteral("AAC 5.1 OR AC-3 5.1");
    item[QStringLiteral("recommendedSubtitleText")] = needsSubtitles
        ? QStringLiteral("REMOVE IMAGE-BASED · KEEP TEXT ENGLISH")
        : QStringLiteral("KEEP CURRENT / ENGLISH");

    QStringList reasons;
    if (!codecCompatible)
        reasons.append(QStringLiteral("Video codec should be H.264, H.265/HEVC, or AV1."));
    if (is4K && !allow4K)
        reasons.append(QStringLiteral("4K is marked for review. Enable Allow 4K to accept compatible direct-play video."));
    else if (!resolutionCompatible && !is4K)
        reasons.append(QStringLiteral("Video resolution could not be identified."));
    if (needsAudio)
        reasons.append(QStringLiteral("One or more audio tracks should be AAC, AC-3, or E-AC-3 at 5.1 channels or below."));
    if (needsSubtitles)
        reasons.append(QStringLiteral("Image-based subtitles can force transcoding and should normally be removed."));
    if (!(needsVideo || needsAudio || needsSubtitles))
        reasons.append(is4K && allow4K
                           ? QStringLiteral("Compatible 4K direct-play media; NeutronOS will not transcode the video.")
                           : QStringLiteral("Direct-play compatible with the Roku preset."));
    item[QStringLiteral("reasons")] = reasons;
    if (!(needsVideo || needsAudio || needsSubtitles)) {
        item[QStringLiteral("estimatedSavingsBytes")] = 0;
        item[QStringLiteral("estimatedSavings")] = humanBytes(0);
    }
    return item;
}


QString MediaOptimizerManager::smartTitleCase(const QString &value)
{
    const QSet<QString> smallWords{
        QStringLiteral("a"), QStringLiteral("an"), QStringLiteral("and"),
        QStringLiteral("as"), QStringLiteral("at"), QStringLiteral("but"),
        QStringLiteral("by"), QStringLiteral("for"), QStringLiteral("in"),
        QStringLiteral("of"), QStringLiteral("on"), QStringLiteral("or"),
        QStringLiteral("the"), QStringLiteral("to"), QStringLiteral("vs")
    };
    QStringList words = value.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (int i = 0; i < words.size(); ++i) {
        QString word = words.at(i);
        const QString lower = word.toLower();
        if (i > 0 && i + 1 < words.size() && smallWords.contains(lower)) {
            words[i] = lower;
            continue;
        }
        if (word.size() <= 4 && word == word.toUpper() && word.contains(QRegularExpression(QStringLiteral("[A-Z]"))))
            continue;
        if (!word.isEmpty())
            words[i] = word.left(1).toUpper() + word.mid(1).toLower();
    }
    return words.join(QLatin1Char(' '));
}

QString MediaOptimizerManager::cleanedReleaseTitle(const QString &baseName)
{
    QString value = baseName;
    value.replace(QRegularExpression(QStringLiteral("[._]+")), QStringLiteral(" "));
    value.replace(QRegularExpression(QStringLiteral("\\[[^\\]]*(?:2160p|1080p|720p|480p|bluray|web[- .]?dl|webrip|hdtv|x26[45]|h\\.?26[45]|hevc|av1|vp9|aac|ac3|eac3|dts|truehd|atmos)[^\\]]*\\]"), QRegularExpression::CaseInsensitiveOption), QStringLiteral(" "));
    value.replace(QRegularExpression(QStringLiteral("\\([^\\)]*(?:2160p|1080p|720p|480p|bluray|web[- .]?dl|webrip|hdtv|x26[45]|h\\.?26[45]|hevc|av1|vp9|aac|ac3|eac3|dts|truehd|atmos)[^\\)]*\\)"), QRegularExpression::CaseInsensitiveOption), QStringLiteral(" "));
    value.replace(QRegularExpression(QStringLiteral("\\b(?:2160p|1080p|720p|576p|480p|4k|uhd|hdr10\\+?|dolby[ .]?vision|dv|bluray|bdrip|brrip|web[- .]?dl|webrip|hdtv|remux|xvid|divx|x26[45]|h\\.?26[45]|hevc|avc|av1|vp9|vvc|10bit|8bit|aac(?:2\\.?0|5\\.?1)?|ac3|eac3|ddp(?:2\\.?0|5\\.?1)?|dts(?:hd)?|truehd|atmos|flac|opus|mp3|proper|repack|extended|unrated|limited|internal|multi|dubbed|subbed)\\b"), QRegularExpression::CaseInsensitiveOption), QStringLiteral(" "));
    value.replace(QRegularExpression(QStringLiteral("\\s+-\\s+[A-Za-z0-9]{2,20}$")), QStringLiteral(" "));
    value.replace(QRegularExpression(QStringLiteral("[\\[\\]{}]+")), QStringLiteral(" "));
    value.replace(QRegularExpression(QStringLiteral("\\s{2,}")), QStringLiteral(" "));
    return value.trimmed();
}

QString MediaOptimizerManager::safeRenameStem(const QString &value)
{
    QString clean = value;
    clean.replace(QRegularExpression(QStringLiteral("[<>:\"/\\\\|?*\\x00-\\x1F]")), QStringLiteral(" "));
    clean.replace(QRegularExpression(QStringLiteral("\\s{2,}")), QStringLiteral(" "));
    clean = clean.trimmed();
    while (clean.endsWith(QLatin1Char('.')) || clean.endsWith(QLatin1Char(' ')))
        clean.chop(1);
    return clean.left(220).trimmed();
}

QVariantMap MediaOptimizerManager::renameProposal(const QString &path, const QString &mode)
{
    const QFileInfo info(path);
    QVariantMap result{
        {QStringLiteral("oldPath"), info.absoluteFilePath()},
        {QStringLiteral("oldName"), info.fileName()},
        {QStringLiteral("mode"), mode},
        {QStringLiteral("valid"), false}
    };
    if (!info.exists() || !info.isFile()) {
        result.insert(QStringLiteral("reason"), QStringLiteral("Source file no longer exists"));
        return result;
    }

    const QString originalBase = info.completeBaseName();
    QString normalized = originalBase;
    normalized.replace(QRegularExpression(QStringLiteral("[._]+")), QStringLiteral(" "));
    const QRegularExpression episodeRx(QStringLiteral("(?i)(?:\\bS(\\d{1,2})E(\\d{1,3})\\b|\\b(\\d{1,2})x(\\d{1,3})\\b)"));
    const QRegularExpressionMatch episodeMatch = episodeRx.match(normalized);
    const bool showMode = mode.startsWith(QStringLiteral("SHOW_"));
    QString stem;

    if (showMode) {
        if (!episodeMatch.hasMatch()) {
            result.insert(QStringLiteral("reason"), QStringLiteral("No season/episode number was detected"));
            return result;
        }
        const int season = !episodeMatch.captured(1).isEmpty() ? episodeMatch.captured(1).toInt() : episodeMatch.captured(3).toInt();
        const int episode = !episodeMatch.captured(2).isEmpty() ? episodeMatch.captured(2).toInt() : episodeMatch.captured(4).toInt();
        QString showName = cleanedReleaseTitle(normalized.left(episodeMatch.capturedStart()));
        QString episodeName = cleanedReleaseTitle(normalized.mid(episodeMatch.capturedEnd()));
        showName = smartTitleCase(showName);
        episodeName = smartTitleCase(episodeName);
        if (showName.isEmpty()) {
            result.insert(QStringLiteral("reason"), QStringLiteral("Show name could not be detected"));
            return result;
        }
        stem = QStringLiteral("%1 S%2E%3")
            .arg(showName)
            .arg(season, 2, 10, QLatin1Char('0'))
            .arg(episode, 2, 10, QLatin1Char('0'));
        if (mode == QStringLiteral("SHOW_NUMBER_TITLE") && !episodeName.isEmpty())
            stem += QStringLiteral(" %1").arg(episodeName);
        result.insert(QStringLiteral("kind"), QStringLiteral("show"));
        result.insert(QStringLiteral("showName"), showName);
        result.insert(QStringLiteral("season"), season);
        result.insert(QStringLiteral("episode"), episode);
        result.insert(QStringLiteral("episodeName"), episodeName);
    } else {
        if (episodeMatch.hasMatch()) {
            result.insert(QStringLiteral("reason"), QStringLiteral("Episode pattern detected; choose a TV-show naming preset"));
            return result;
        }
        const QRegularExpression yearRx(QStringLiteral("\\b((?:19|20)\\d{2})\\b"));
        const QRegularExpressionMatch yearMatch = yearRx.match(normalized);
        QString movieName = cleanedReleaseTitle(yearMatch.hasMatch() ? normalized.left(yearMatch.capturedStart()) : normalized);
        movieName = smartTitleCase(movieName);
        if (movieName.isEmpty()) {
            result.insert(QStringLiteral("reason"), QStringLiteral("Movie name could not be detected"));
            return result;
        }
        stem = movieName;
        if (mode == QStringLiteral("MOVIE_TITLE_YEAR") && yearMatch.hasMatch())
            stem += QStringLiteral(" (%1)").arg(yearMatch.captured(1));
        result.insert(QStringLiteral("kind"), QStringLiteral("movie"));
        result.insert(QStringLiteral("movieName"), movieName);
        result.insert(QStringLiteral("year"), yearMatch.hasMatch() ? yearMatch.captured(1) : QString());
        if (mode == QStringLiteral("MOVIE_TITLE_YEAR") && !yearMatch.hasMatch())
            result.insert(QStringLiteral("warning"), QStringLiteral("No year detected; the clean movie title will be used"));
    }

    stem = safeRenameStem(stem);
    if (stem.isEmpty()) {
        result.insert(QStringLiteral("reason"), QStringLiteral("Proposed filename is empty"));
        return result;
    }
    const QString suffix = info.suffix();
    const QString newName = suffix.isEmpty() ? stem : stem + QLatin1Char('.') + suffix;
    const QString newPath = info.dir().absoluteFilePath(newName);
    result.insert(QStringLiteral("newName"), newName);
    result.insert(QStringLiteral("newPath"), newPath);
    result.insert(QStringLiteral("unchanged"), QFileInfo(newPath).absoluteFilePath() == info.absoluteFilePath());
    result.insert(QStringLiteral("collision"), QFileInfo::exists(newPath) && QFileInfo(newPath).absoluteFilePath() != info.absoluteFilePath());
    if (result.value(QStringLiteral("collision")).toBool()) {
        result.insert(QStringLiteral("reason"), QStringLiteral("A file with the proposed name already exists"));
        return result;
    }
    result.insert(QStringLiteral("valid"), true);
    return result;
}

QVariantList MediaOptimizerManager::buildBatchRenamePreview(const QVariantList &paths, const QString &mode) const
{
    static const QSet<QString> allowed{
        QStringLiteral("MOVIE_TITLE"), QStringLiteral("MOVIE_TITLE_YEAR"),
        QStringLiteral("SHOW_NUMBER"), QStringLiteral("SHOW_NUMBER_TITLE")
    };
    const QString normalizedMode = mode.trimmed().toUpper();
    if (!allowed.contains(normalizedMode))
        return {};
    QVariantList preview;
    QSet<QString> destinations;
    for (const QVariant &value : paths) {
        const QString path = value.typeId() == QMetaType::QVariantMap
            ? value.toMap().value(QStringLiteral("path")).toString()
            : value.toString();
        if (path.isEmpty())
            continue;
        QVariantMap proposal = renameProposal(path, normalizedMode);
        const QString destination = proposal.value(QStringLiteral("newPath")).toString();
        if (!destination.isEmpty()) {
            if (destinations.contains(destination)) {
                proposal.insert(QStringLiteral("valid"), false);
                proposal.insert(QStringLiteral("collision"), true);
                proposal.insert(QStringLiteral("reason"), QStringLiteral("Two selected files resolve to the same name"));
            }
            destinations.insert(destination);
        }
        preview.append(proposal);
    }
    return preview;
}

bool MediaOptimizerManager::updateCacheAfterRename(const QString &oldPath, const QString &newPath)
{
    if (m_selectedRoot.isEmpty())
        return false;
    const QString cachePath = cachePathForRoot(m_selectedRoot);
    QFile file(cachePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    QJsonParseError error;
    QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    file.close();
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return false;
    QJsonObject object = document.object();
    QJsonArray entries = object.value(QStringLiteral("entries")).toArray();
    bool changed = false;
    const QFileInfo newInfo(newPath);
    for (int i = 0; i < entries.size(); ++i) {
        QJsonObject entry = entries.at(i).toObject();
        if (QFileInfo(entry.value(QStringLiteral("path")).toString()).absoluteFilePath() != QFileInfo(oldPath).absoluteFilePath())
            continue;
        entry.insert(QStringLiteral("path"), newInfo.absoluteFilePath());
        entry.insert(QStringLiteral("size"), static_cast<double>(newInfo.size()));
        entry.insert(QStringLiteral("modifiedMs"), static_cast<double>(newInfo.lastModified().toMSecsSinceEpoch()));
        QJsonObject media = entry.value(QStringLiteral("media")).toObject();
        if (!media.isEmpty()) {
            media.insert(QStringLiteral("path"), newInfo.absoluteFilePath());
            media.insert(QStringLiteral("fileName"), newInfo.fileName());
            media.insert(QStringLiteral("name"), newInfo.fileName());
            entry.insert(QStringLiteral("media"), media);
        }
        entries[i] = entry;
        changed = true;
        break;
    }
    if (!changed)
        return false;
    object.insert(QStringLiteral("entries"), entries);
    object.insert(QStringLiteral("updatedUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    QSaveFile save(cachePath);
    if (!save.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    save.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    return save.commit();
}

void MediaOptimizerManager::saveRenameHistory() const
{
    const QString stateDir = QDir(m_neutronRoot).filePath(QStringLiteral("state/apps/mediaoptimizer"));
    QDir().mkpath(stateDir);
    QJsonObject object;
    object.insert(QStringLiteral("version"), 1);
    object.insert(QStringLiteral("createdUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    object.insert(QStringLiteral("entries"), QJsonArray::fromVariantList(m_lastRenameUndo));
    QSaveFile latest(QDir(stateDir).filePath(QStringLiteral("last-rename.json")));
    if (latest.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        latest.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
        latest.commit();
    }
    const QString logName = QStringLiteral("rename-%1.json").arg(QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMdd-HHmmss")));
    QSaveFile log(QDir(stateDir).filePath(logName));
    if (log.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        log.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
        log.commit();
    }
}

void MediaOptimizerManager::loadRenameHistory()
{
    QFile file(QDir(m_neutronRoot).filePath(QStringLiteral("state/apps/mediaoptimizer/last-rename.json")));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (document.isObject())
        m_lastRenameUndo = document.object().value(QStringLiteral("entries")).toArray().toVariantList();
}

bool MediaOptimizerManager::startBatchRename(const QVariantList &entries)
{
    if (m_busy || m_scanning || m_queueActive || m_renameActive || entries.isEmpty()) {
        m_lastMessage = QStringLiteral("Batch rename cannot start while another media operation is active.");
        emit stateChanged();
        return false;
    }
    m_renameQueue.clear();
    for (const QVariant &value : entries) {
        const QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("valid")).toBool() && !entry.value(QStringLiteral("unchanged")).toBool())
            m_renameQueue.append(entry);
    }
    if (m_renameQueue.isEmpty()) {
        m_lastMessage = QStringLiteral("No valid filename changes were selected.");
        emit stateChanged();
        return false;
    }
    m_renameActive = true;
    m_renameErrors.clear();
    m_lastRenameUndo.clear();
    m_renameIndex = 0;
    m_renameCompleted = 0;
    m_renameCurrentFile.clear();
    m_renameStatus = QStringLiteral("Preparing batch rename");
    emit renameChanged();
    QTimer::singleShot(0, this, &MediaOptimizerManager::processNextRename);
    return true;
}

void MediaOptimizerManager::processNextRename()
{
    if (!m_renameActive)
        return;
    if (m_renameIndex >= m_renameQueue.size()) {
        const bool success = m_renameErrors.isEmpty();
        finishBatchRename(success, success
            ? QStringLiteral("Batch rename completed successfully.")
            : QStringLiteral("Batch rename completed with %1 error%2.")
                .arg(m_renameErrors.size()).arg(m_renameErrors.size() == 1 ? QString() : QStringLiteral("s")));
        return;
    }
    const QVariantMap entry = m_renameQueue.at(m_renameIndex).toMap();
    const QString oldPath = QFileInfo(entry.value(QStringLiteral("oldPath")).toString()).absoluteFilePath();
    const QString newPath = QFileInfo(entry.value(QStringLiteral("newPath")).toString()).absoluteFilePath();
    m_renameCurrentFile = QFileInfo(oldPath).fileName();
    m_renameStatus = QStringLiteral("Renaming %1").arg(m_renameCurrentFile);
    emit renameChanged();

    QString error;
    if (oldPath.isEmpty() || newPath.isEmpty() || QFileInfo(oldPath).absolutePath() != QFileInfo(newPath).absolutePath())
        error = QStringLiteral("Unsafe rename destination");
    else if (!QFileInfo::exists(oldPath))
        error = QStringLiteral("Source file no longer exists");
    else if (QFileInfo::exists(newPath))
        error = QStringLiteral("Destination already exists");
    else if (!QFile::rename(oldPath, newPath))
        error = QStringLiteral("Filesystem rename failed");

    if (!error.isEmpty()) {
        m_renameErrors.append(QVariantMap{{QStringLiteral("path"), oldPath}, {QStringLiteral("message"), error}});
    } else {
        m_lastRenameUndo.prepend(QVariantMap{{QStringLiteral("oldPath"), oldPath}, {QStringLiteral("newPath"), newPath}});
        for (int i = 0; i < m_media.size(); ++i) {
            QVariantMap item = m_media.at(i).toMap();
            if (QFileInfo(item.value(QStringLiteral("path")).toString()).absoluteFilePath() == oldPath) {
                item.insert(QStringLiteral("path"), newPath);
                item.insert(QStringLiteral("fileName"), QFileInfo(newPath).fileName());
                item.insert(QStringLiteral("name"), QFileInfo(newPath).fileName());
                m_media[i] = item;
                break;
            }
        }
        updateCacheAfterRename(oldPath, newPath);
    }
    ++m_renameIndex;
    ++m_renameCompleted;
    emit mediaChanged();
    emit renameChanged();
    QTimer::singleShot(20, this, &MediaOptimizerManager::processNextRename);
}

void MediaOptimizerManager::finishBatchRename(bool success, const QString &message)
{
    m_renameActive = false;
    m_renameCurrentFile.clear();
    m_renameStatus = message;
    m_lastMessage = message;
    if (!m_lastRenameUndo.isEmpty())
        saveRenameHistory();
    emit renameChanged();
    emit stateChanged();
    emit batchRenameFinished(success, message);
}

bool MediaOptimizerManager::undoLastRenameBatch()
{
    if (m_busy || m_scanning || m_queueActive || m_renameActive)
        return false;
    if (m_lastRenameUndo.isEmpty())
        loadRenameHistory();
    if (m_lastRenameUndo.isEmpty()) {
        m_lastMessage = QStringLiteral("There is no batch rename to undo.");
        emit stateChanged();
        return false;
    }
    QVariantList failures;
    QVariantList restored;
    for (const QVariant &value : m_lastRenameUndo) {
        const QVariantMap entry = value.toMap();
        const QString oldPath = entry.value(QStringLiteral("oldPath")).toString();
        const QString newPath = entry.value(QStringLiteral("newPath")).toString();
        if (!QFileInfo::exists(newPath) || QFileInfo::exists(oldPath) || !QFile::rename(newPath, oldPath)) {
            failures.append(QVariantMap{{QStringLiteral("path"), newPath}, {QStringLiteral("message"), QStringLiteral("Unable to restore original name")}});
            continue;
        }
        restored.append(entry);
        for (int i = 0; i < m_media.size(); ++i) {
            QVariantMap item = m_media.at(i).toMap();
            if (QFileInfo(item.value(QStringLiteral("path")).toString()).absoluteFilePath() == QFileInfo(newPath).absoluteFilePath()) {
                item.insert(QStringLiteral("path"), oldPath);
                item.insert(QStringLiteral("fileName"), QFileInfo(oldPath).fileName());
                item.insert(QStringLiteral("name"), QFileInfo(oldPath).fileName());
                m_media[i] = item;
                break;
            }
        }
        updateCacheAfterRename(newPath, oldPath);
    }
    m_renameErrors = failures;
    if (failures.isEmpty())
        m_lastRenameUndo.clear();
    else {
        QVariantList remaining;
        for (const QVariant &value : m_lastRenameUndo) {
            if (!restored.contains(value))
                remaining.append(value);
        }
        m_lastRenameUndo = remaining;
    }
    saveRenameHistory();
    m_lastMessage = failures.isEmpty()
        ? QStringLiteral("The most recent batch rename was undone.")
        : QStringLiteral("Undo completed with %1 file%2 that could not be restored.")
            .arg(failures.size()).arg(failures.size() == 1 ? QString() : QStringLiteral("s"));
    emit mediaChanged();
    emit renameChanged();
    emit stateChanged();
    return failures.isEmpty();
}

QString MediaOptimizerManager::cachePathForRoot(const QString &rootPath) const
{
    const QByteArray digest = QCryptographicHash::hash(
        QDir::cleanPath(rootPath).toUtf8(), QCryptographicHash::Sha256).toHex();
    return QDir(m_neutronRoot)
        .filePath(QStringLiteral("state/apps/mediaoptimizer/cache/%1.json")
                      .arg(QString::fromLatin1(digest.left(24))));
}

QVariantList MediaOptimizerManager::cachedMediaForRoot(const QString &rootPath) const
{
    const QString cachePath = cachePathForRoot(rootPath);
    QFile file(cachePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return {};
    const QJsonObject object = document.object();
    const int cacheVersion = object.value(QStringLiteral("version")).toInt();
    if ((cacheVersion != 2 && cacheVersion != 3) ||
        QDir::cleanPath(object.value(QStringLiteral("root")).toString()) != QDir::cleanPath(rootPath))
        return {};

    QVariantList items;
    const QJsonArray entries = object.value(QStringLiteral("entries")).toArray();
    for (const QJsonValue &value : entries) {
        const QJsonObject entry = value.toObject();
        const QString path = entry.value(QStringLiteral("path")).toString();
        const QFileInfo info(path);
        if (!info.exists() || !info.isFile())
            continue;
        const qint64 cachedSize = jsonInteger(entry.value(QStringLiteral("size")));
        const qint64 cachedModified = jsonInteger(entry.value(QStringLiteral("modifiedMs")));
        if (cachedSize != info.size() || cachedModified != info.lastModified().toMSecsSinceEpoch())
            continue;
        if (entry.value(QStringLiteral("failed")).toBool(false))
            continue;
        const QVariantMap mediaItem = entry.value(QStringLiteral("media")).toObject().toVariantMap();
        if (!mediaItem.isEmpty())
            items.append(mediaItem);
    }
    return items;
}

QVariantMap MediaOptimizerManager::scanMediaRoot(
    const QString &ffprobe,
    const QString &rootPath,
    const QString &cachePath,
    int batchSize,
    std::atomic_bool *cancelRequested,
    const std::function<void(int, int, int, const QString &, int, int, int)> &progressCallback)
{
    QHash<QString, QJsonObject> cachedEntries;
    QFile cacheFile(cachePath);
    if (cacheFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(cacheFile.readAll(), &error);
        if (error.error == QJsonParseError::NoError && document.isObject()) {
            const QJsonObject object = document.object();
            const int cacheVersion = object.value(QStringLiteral("version")).toInt();
            if ((cacheVersion == 2 || cacheVersion == 3) &&
                QDir::cleanPath(object.value(QStringLiteral("root")).toString()) == QDir::cleanPath(rootPath)) {
                for (const QJsonValue &value : object.value(QStringLiteral("entries")).toArray()) {
                    const QJsonObject entry = value.toObject();
                    const QString path = entry.value(QStringLiteral("path")).toString();
                    if (!path.isEmpty())
                        cachedEntries.insert(path, entry);
                }
            }
        }
    }

    QStringList paths;
    QDirIterator iterator(rootPath, kMediaExtensions, QDir::Files,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext() && paths.size() < 250000) {
        const QString path = iterator.next();
        const QFileInfo info(path);
        if (info.isReadable() && !info.isSymLink())
            paths.append(info.absoluteFilePath());
    }
    std::sort(paths.begin(), paths.end(), [](const QString &left, const QString &right) {
        return QString::localeAwareCompare(left, right) < 0;
    });

    QVariantList items;
    QHash<QString, QJsonObject> nextEntries;
    QStringList candidates;
    int cachedCount = 0;
    int failedCount = 0;

    for (const QString &path : paths) {
        const QFileInfo info(path);
        const QJsonObject cached = cachedEntries.value(path);
        const bool signatureHit = !cached.isEmpty() &&
            jsonInteger(cached.value(QStringLiteral("size"))) == info.size() &&
            jsonInteger(cached.value(QStringLiteral("modifiedMs"))) == info.lastModified().toMSecsSinceEpoch();
        if (!signatureHit) {
            candidates.append(path);
            if (!cached.isEmpty())
                nextEntries.insert(path, cached); // Keep stale metadata only until this file is processed.
            continue;
        }

        nextEntries.insert(path, cached);
        if (cached.value(QStringLiteral("failed")).toBool(false)) {
            ++failedCount;
            continue;
        }
        const QVariantMap mediaItem = cached.value(QStringLiteral("media")).toObject().toVariantMap();
        if (!mediaItem.isEmpty()) {
            items.append(mediaItem);
            ++cachedCount;
        } else {
            candidates.append(path);
        }
    }

    const int availableCandidates = candidates.size();
    const int batchTarget = batchSize <= 0
        ? availableCandidates
        : qMin(batchSize, availableCandidates);
    int processedCount = 0;
    int newCount = 0;

    for (int index = 0; index < batchTarget; ++index) {
        if (cancelRequested && cancelRequested->load())
            break;

        const QString path = candidates.at(index);
        const QFileInfo info(path);
        const QVariantMap probeMap = probeFile(ffprobe, path);
        QJsonObject entry;
        entry.insert(QStringLiteral("path"), path);
        entry.insert(QStringLiteral("size"), static_cast<double>(info.size()));
        entry.insert(QStringLiteral("modifiedMs"), static_cast<double>(info.lastModified().toMSecsSinceEpoch()));

        if (!probeMap.isEmpty()) {
            const QVariantMap mediaItem = buildMediaItem(path, QJsonObject::fromVariantMap(probeMap));
            if (!mediaItem.isEmpty()) {
                items.append(mediaItem);
                entry.insert(QStringLiteral("media"), QJsonObject::fromVariantMap(mediaItem));
                ++newCount;
            } else {
                entry.insert(QStringLiteral("failed"), true);
                entry.insert(QStringLiteral("error"), QStringLiteral("Metadata could not be converted"));
                ++failedCount;
            }
        } else {
            entry.insert(QStringLiteral("failed"), true);
            entry.insert(QStringLiteral("error"), QStringLiteral("ffprobe failed"));
            ++failedCount;
        }
        nextEntries.insert(path, entry);
        ++processedCount;

        const int pendingCount = qMax(0, availableCandidates - processedCount);
        if (progressCallback)
            progressCallback(processedCount, batchTarget, paths.size(), path,
                             cachedCount, newCount, pendingCount);
    }

    const bool cancelled = cancelRequested && cancelRequested->load();
    const int pendingCount = qMax(0, availableCandidates - processedCount);

    // Persist every completed or cancelled batch. This is the Patch 60D resume point.
    QDir().mkpath(QFileInfo(cachePath).absolutePath());
    QJsonArray nextCacheEntries;
    for (const QString &path : paths) {
        const QJsonObject entry = nextEntries.value(path);
        if (!entry.isEmpty())
            nextCacheEntries.append(entry);
    }
    QJsonObject cacheObject;
    cacheObject.insert(QStringLiteral("version"), 3);
    cacheObject.insert(QStringLiteral("root"), QDir::cleanPath(rootPath));
    cacheObject.insert(QStringLiteral("updated"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    cacheObject.insert(QStringLiteral("batchSize"), batchSize);
    cacheObject.insert(QStringLiteral("pending"), pendingCount);
    cacheObject.insert(QStringLiteral("entries"), nextCacheEntries);
    QSaveFile saveFile(cachePath);
    bool cacheSaved = false;
    if (saveFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        const QByteArray data = QJsonDocument(cacheObject).toJson(QJsonDocument::Compact);
        if (saveFile.write(data) == data.size())
            cacheSaved = saveFile.commit();
        else
            saveFile.cancelWriting();
    }

    QVariantMap result;
    result.insert(QStringLiteral("items"), items);
    result.insert(QStringLiteral("total"), paths.size());
    result.insert(QStringLiteral("cached"), cachedCount);
    result.insert(QStringLiteral("new"), newCount);
    result.insert(QStringLiteral("failed"), failedCount);
    result.insert(QStringLiteral("processed"), processedCount);
    result.insert(QStringLiteral("pending"), pendingCount);
    result.insert(QStringLiteral("complete"), pendingCount == 0);
    result.insert(QStringLiteral("cacheSaved"), cacheSaved);
    result.insert(QStringLiteral("cancelled"), cancelled);
    return result;
}

void MediaOptimizerManager::applyScanProgress(int currentBatch,
                                               int batchTarget,
                                               int totalFiles,
                                               const QString &path,
                                               int cachedCount,
                                               int newCount,
                                               int pendingCount)
{
    if (!m_scanning)
        return;
    m_scanCurrentIndex = currentBatch;
    m_scanTotalFiles = totalFiles;
    m_scanRemainingFiles = pendingCount;
    m_scanCachedFiles = cachedCount;
    m_scanNewFiles = newCount;
    m_scanProcessedThisBatch = currentBatch;
    m_scanPendingFiles = pendingCount;
    m_scanComplete = pendingCount == 0;
    m_scanCurrentFile = path;
    m_currentInput = path;
    m_progress = batchTarget > 0
        ? qBound(0, qRound(100.0 * currentBatch / batchTarget), 100)
        : 100;
    m_operationStatus = QStringLiteral("Scanning batch %1 / %2")
                            .arg(currentBatch)
                            .arg(batchTarget);
    m_lastMessage = QStringLiteral("%1 · %2 still pending · %3 reused from cache · %4 added or refreshed")
                        .arg(QFileInfo(path).fileName())
                        .arg(pendingCount)
                        .arg(cachedCount)
                        .arg(newCount);
    emit stateChanged();
}

void MediaOptimizerManager::refreshLocations()
{
    const bool ffmpegNow = !executable(QStringLiteral("ffmpeg")).isEmpty();
    const bool ffprobeNow = !executable(QStringLiteral("ffprobe")).isEmpty();
    if (ffmpegNow != m_ffmpegAvailable || ffprobeNow != m_ffprobeAvailable) {
        m_ffmpegAvailable = ffmpegNow;
        m_ffprobeAvailable = ffprobeNow;
        emit availabilityChanged();
    }

    QVariantList next;
    QSet<QString> seen;
    auto appendLocation = [&next, &seen](const QString &name, const QString &root,
                                         const QByteArray &device, const QByteArray &fs,
                                         qint64 total, qint64 free) {
        const QString clean = QDir::cleanPath(root);
        if (clean.isEmpty() || seen.contains(clean))
            return;
        seen.insert(clean);
        next.append(QVariantMap{
            {QStringLiteral("id"), QString::fromLatin1(QCryptographicHash::hash(clean.toUtf8(), QCryptographicHash::Sha256).toHex().left(12))},
            {QStringLiteral("name"), name},
            {QStringLiteral("root"), clean},
            {QStringLiteral("device"), QString::fromLocal8Bit(device)},
            {QStringLiteral("filesystem"), QString::fromLocal8Bit(fs)},
            {QStringLiteral("totalBytes"), static_cast<qlonglong>(total)},
            {QStringLiteral("freeBytes"), static_cast<qlonglong>(free)},
            {QStringLiteral("total"), humanBytes(static_cast<qulonglong>(qMax<qint64>(0, total)))},
            {QStringLiteral("free"), humanBytes(static_cast<qulonglong>(qMax<qint64>(0, free)))}
        });
    };

    const QString mediaDefault = QDir::homePath() + QStringLiteral("/Media");
    if (QFileInfo::exists(mediaDefault))
        appendLocation(QStringLiteral("Home Media"), mediaDefault, {}, {}, 0, 0);
    appendLocation(QStringLiteral("Home"), QDir::homePath(), {}, {}, 0, 0);

    const QList<QStorageInfo> volumes = QStorageInfo::mountedVolumes();
    for (const QStorageInfo &storage : volumes) {
        if (!storage.isValid() || !storage.isReady() || storage.rootPath().isEmpty() ||
            QDir::cleanPath(storage.rootPath()) == QStringLiteral("/"))
            continue;
        QString name = storage.displayName();
        if (name.isEmpty())
            name = storage.name();
        if (name.isEmpty())
            name = storage.rootPath();
        appendLocation(name, storage.rootPath(), storage.device(), storage.fileSystemType(),
                       storage.bytesTotal(), storage.bytesAvailable());
    }
    m_locations = next;
    emit locationsChanged();
}

void MediaOptimizerManager::setState(const QString &status,
                                     int progressValue,
                                     const QString &message)
{
    m_operationStatus = status;
    m_progress = progressValue;
    if (!message.isEmpty())
        m_lastMessage = message;
    emit stateChanged();
}

bool MediaOptimizerManager::scanLocation(const QString &rootPath)
{
    if (m_busy || m_scanning)
        return false;
    const QString root = canonicalDirectory(rootPath);
    if (root.isEmpty() || root == QStringLiteral("/") ||
        root.startsWith(QStringLiteral("/proc")) || root.startsWith(QStringLiteral("/sys")) ||
        root.startsWith(QStringLiteral("/dev")) || root.startsWith(QStringLiteral("/run"))) {
        m_lastMessage = QStringLiteral("Choose a media directory or mounted storage area, not the operating-system root.");
        emit stateChanged();
        return false;
    }
    const QString ffprobe = executable(QStringLiteral("ffprobe"));
    if (ffprobe.isEmpty()) {
        m_lastMessage = QStringLiteral("ffprobe is required to inspect media.");
        emit stateChanged();
        return false;
    }

    m_selectedRoot = root;
    m_scanCancelRequested.store(false);
    m_scanning = true;
    m_scanCurrentFile.clear();
    m_scanCurrentIndex = 0;
    m_scanTotalFiles = 0;
    m_scanRemainingFiles = 0;
    m_scanCachedFiles = 0;
    m_scanNewFiles = 0;
    m_scanProcessedThisBatch = 0;
    m_scanPendingFiles = 0;
    m_scanComplete = false;

    const QVariantList cachedItems = cachedMediaForRoot(root);
    m_media = cachedItems;
    emit mediaChanged();
    const QString batchLabel = m_scanBatchSize <= 0
        ? QStringLiteral("ALL")
        : QString::number(m_scanBatchSize);
    const QString initialMessage = cachedItems.isEmpty()
        ? (m_scanBatchSize <= 0
               ? QStringLiteral("Starting a full scan. The cache is saved when the scan finishes or is paused.")
               : QStringLiteral("Starting a %1-file scan batch. The cache is saved after this batch.").arg(batchLabel))
        : QStringLiteral("Loaded %1 cached media files. Batch %2 will probe only new or changed files.")
              .arg(cachedItems.size())
              .arg(batchLabel);
    setState(QStringLiteral("Checking for new or changed media"), 0, initialMessage);

    const QString cachePath = cachePathForRoot(root);
    const int batchSize = m_scanBatchSize;
    QPointer<MediaOptimizerManager> guard(this);
    m_scanWatcher->setFuture(QtConcurrent::run([ffprobe, root, cachePath, batchSize, guard, this]() {
        auto reportProgress = [guard](int currentBatch, int batchTarget, int totalFiles,
                                      const QString &path, int cachedCount, int newCount,
                                      int pendingCount) {
            if (!guard)
                return;
            QMetaObject::invokeMethod(guard,
                                      [guard, currentBatch, batchTarget, totalFiles, path,
                                       cachedCount, newCount, pendingCount]() {
                if (guard)
                    guard->applyScanProgress(currentBatch, batchTarget, totalFiles, path,
                                             cachedCount, newCount, pendingCount);
            }, Qt::QueuedConnection);
        };
        return MediaOptimizerManager::scanMediaRoot(
            ffprobe, root, cachePath, batchSize, &m_scanCancelRequested, reportProgress);
    }));
    return true;
}

bool MediaOptimizerManager::continueScan()
{
    if (m_selectedRoot.isEmpty()) {
        m_lastMessage = QStringLiteral("Choose a media location before continuing the scan.");
        emit stateChanged();
        return false;
    }
    return scanLocation(m_selectedRoot);
}

void MediaOptimizerManager::onScanFinished()
{
    const QVariantMap result = m_scanWatcher->result();
    const bool cancelled = result.value(QStringLiteral("cancelled")).toBool();
    const bool cacheSaved = result.value(QStringLiteral("cacheSaved")).toBool();
    m_media = result.value(QStringLiteral("items")).toList();
    applyPolicyToMedia();
    m_scanning = false;
    m_progress = cancelled ? -1 : 100;
    m_scanTotalFiles = result.value(QStringLiteral("total")).toInt();
    m_scanCachedFiles = result.value(QStringLiteral("cached")).toInt();
    m_scanNewFiles = result.value(QStringLiteral("new")).toInt();
    m_scanProcessedThisBatch = result.value(QStringLiteral("processed")).toInt();
    m_scanPendingFiles = result.value(QStringLiteral("pending")).toInt();
    m_scanRemainingFiles = m_scanPendingFiles;
    m_scanComplete = result.value(QStringLiteral("complete")).toBool();

    if (cancelled) {
        m_operationStatus = QStringLiteral("Scan batch paused");
        m_lastMessage = cacheSaved
            ? QStringLiteral("Scan paused after %1 file%2. Progress was cached; %3 new or changed file%4 remain.")
                  .arg(m_scanProcessedThisBatch)
                  .arg(m_scanProcessedThisBatch == 1 ? QString() : QStringLiteral("s"))
                  .arg(m_scanPendingFiles)
                  .arg(m_scanPendingFiles == 1 ? QString() : QStringLiteral("s"))
            : QStringLiteral("Scan paused, but the cache could not be saved.");
    } else if (m_scanComplete) {
        m_operationStatus = QStringLiteral("Library scan complete");
        const int failed = result.value(QStringLiteral("failed")).toInt();
        m_lastMessage = QStringLiteral("%1 media file%2 available · %3 reused from cache · %4 added or refreshed%5 · cache saved.")
                            .arg(m_media.size())
                            .arg(m_media.size() == 1 ? QString() : QStringLiteral("s"))
                            .arg(m_scanCachedFiles)
                            .arg(m_scanNewFiles)
                            .arg(failed > 0 ? QStringLiteral(" · %1 unreadable cached").arg(failed) : QString());
    } else {
        m_operationStatus = QStringLiteral("Scan batch complete");
        m_lastMessage = QStringLiteral("Batch cached after %1 file%2 · %3 new or changed file%4 remain. Start the scan again to continue.")
                            .arg(m_scanProcessedThisBatch)
                            .arg(m_scanProcessedThisBatch == 1 ? QString() : QStringLiteral("s"))
                            .arg(m_scanPendingFiles)
                            .arg(m_scanPendingFiles == 1 ? QString() : QStringLiteral("s"));
    }
    emit mediaChanged();
    emit stateChanged();
    emit scanFinished(!cancelled, m_lastMessage);
}

QVariantMap MediaOptimizerManager::findMedia(const QString &path) const
{
    const QString clean = QFileInfo(path).absoluteFilePath();
    for (const QVariant &entry : m_media) {
        const QVariantMap item = entry.toMap();
        if (QFileInfo(item.value(QStringLiteral("path")).toString()).absoluteFilePath() == clean)
            return item;
    }
    return {};
}

QVariantMap MediaOptimizerManager::mediaDetails(const QString &path) const
{
    return findMedia(path);
}

QVariantMap MediaOptimizerManager::recommendedSettings(const QString &path) const
{
    const QVariantMap item = findMedia(path);
    if (item.isEmpty())
        return {};
    QString videoMode = QStringLiteral("KEEP");
    if (!item.value(QStringLiteral("videoCompatible")).toBool() &&
        item.value(QStringLiteral("resolutionCompatible")).toBool())
        videoMode = QStringLiteral("H265");
    if (item.value(QStringLiteral("is4K")).toBool())
        videoMode = QStringLiteral("KEEP");
    return {
        {QStringLiteral("preset"), QStringLiteral("ROKU")},
        {QStringLiteral("videoMode"), videoMode},
        {QStringLiteral("audioMode"), item.value(QStringLiteral("audioCompatible")).toBool()
                                               ? QStringLiteral("KEEP")
                                               : QStringLiteral("AAC_5_1")},
        {QStringLiteral("trackMode"), QStringLiteral("BEST_ENGLISH")},
        {QStringLiteral("subtitleMode"), item.value(QStringLiteral("hasImageSubtitles")).toBool()
                                                  ? QStringLiteral("REMOVE_IMAGE")
                                                  : QStringLiteral("KEEP_ENGLISH")},
        {QStringLiteral("keepSource"), true},
        {QStringLiteral("fourKBlocked"), item.value(QStringLiteral("is4K")).toBool() && !m_allow4K}
    };
}

QString MediaOptimizerManager::containerFormat(const QString &container) const
{
    const QString value = normalizedChoice(container);
    if (value == QStringLiteral("MP4") || value == QStringLiteral("M4V"))
        return QStringLiteral("mp4");
    if (value == QStringLiteral("MOV"))
        return QStringLiteral("mov");
    if (value == QStringLiteral("WEBM"))
        return QStringLiteral("webm");
    if (value == QStringLiteral("AVI"))
        return QStringLiteral("avi");
    if (value == QStringLiteral("TS") || value == QStringLiteral("M2TS") || value == QStringLiteral("MTS"))
        return QStringLiteral("mpegts");
    if (value == QStringLiteral("MPG") || value == QStringLiteral("MPEG"))
        return QStringLiteral("mpeg");
    if (value == QStringLiteral("WMV") || value == QStringLiteral("ASF"))
        return QStringLiteral("asf");
    return QStringLiteral("matroska");
}

QString MediaOptimizerManager::effectiveContainerFor(const QVariantMap &item,
                                                       const QVariantMap &settings) const
{
    const QVariant selected = settings.value(QStringLiteral("container"), QStringLiteral("Unchanged"));
    if (!isUnchangedChoice(selected))
        return normalizedChoice(selected);

    QString extension = item.value(QStringLiteral("extension")).toString().trimmed().toUpper();
    if (extension.isEmpty())
        extension = QFileInfo(item.value(QStringLiteral("path")).toString()).suffix().toUpper();
    if (extension == QStringLiteral("MKV")) return QStringLiteral("MKV");
    if (extension == QStringLiteral("MP4") || extension == QStringLiteral("M4V")) return QStringLiteral("MP4");
    if (extension == QStringLiteral("MOV")) return QStringLiteral("MOV");
    if (extension == QStringLiteral("WEBM")) return QStringLiteral("WEBM");
    if (extension == QStringLiteral("AVI")) return QStringLiteral("AVI");
    if (extension == QStringLiteral("TS") || extension == QStringLiteral("M2TS") || extension == QStringLiteral("MTS")) return QStringLiteral("TS");
    if (extension == QStringLiteral("MPG") || extension == QStringLiteral("MPEG")) return QStringLiteral("MPEG");
    if (extension == QStringLiteral("WMV")) return QStringLiteral("WMV");
    return QStringLiteral("MKV");
}

QString MediaOptimizerManager::outputPathFor(const QString &inputPath,
                                              const QVariantMap &settings) const
{
    const QFileInfo info(inputPath);
    QVariantMap item = findMedia(inputPath);
    if (item.isEmpty()) {
        item.insert(QStringLiteral("path"), inputPath);
        item.insert(QStringLiteral("extension"), info.suffix().toLower());
    }
    const QString container = effectiveContainerFor(item, settings);
    const QString audioCodec = normalizedChoice(settings.value(QStringLiteral("audioCodec"), QStringLiteral("Unchanged")));
    QString extension = container.toLower();
    if (container == QStringLiteral("TS")) extension = QStringLiteral("ts");
    else if (container == QStringLiteral("MPEG")) extension = QStringLiteral("mpeg");
    else if (container == QStringLiteral("WMV")) extension = QStringLiteral("wmv");
    if (settings.value(QStringLiteral("audioOnly")).toBool()) {
        if (audioCodec == QStringLiteral("WAV")) extension = QStringLiteral("wav");
        else if (audioCodec == QStringLiteral("FLAC")) extension = QStringLiteral("flac");
        else if (audioCodec == QStringLiteral("MP3")) extension = QStringLiteral("mp3");
        else if (audioCodec == QStringLiteral("OPUS")) extension = QStringLiteral("opus");
        else extension = QStringLiteral("m4a");
    }
    if (extension.isEmpty() || extension == QStringLiteral("unchanged"))
        extension = info.suffix().isEmpty() ? QStringLiteral("mkv") : info.suffix().toLower();

    QString path = info.absolutePath() + QLatin1Char('/') + info.completeBaseName() +
                   QStringLiteral(".optimized.") + extension;
    int suffix = 2;
    while (QFileInfo::exists(path)) {
        path = info.absolutePath() + QLatin1Char('/') + info.completeBaseName() +
               QStringLiteral(".optimized-%1.").arg(suffix++) + extension;
    }
    return path;
}

bool MediaOptimizerManager::ffmpegHasEncoder(const QString &encoder) const
{
    const QString ffmpeg = executable(QStringLiteral("ffmpeg"));
    if (ffmpeg.isEmpty())
        return false;
    QProcess process;
    process.setProgram(ffmpeg);
    process.setArguments({QStringLiteral("-hide_banner"), QStringLiteral("-encoders")});
    process.start();
    if (!process.waitForStarted(2000) || !process.waitForFinished(8000)) {
        process.kill();
        return false;
    }
    const QString output = QString::fromUtf8(process.readAllStandardOutput() + process.readAllStandardError());
    return output.contains(QRegularExpression(QStringLiteral("\b") + QRegularExpression::escape(encoder) + QStringLiteral("\b")));
}

QString MediaOptimizerManager::selectVideoEncoder(const QString &mode, const QString &preference) const
{
    const QString normalized = mode.trimmed().toUpper();
    const bool preferHardware = preference.trimmed().compare(QStringLiteral("Software"), Qt::CaseInsensitive) != 0;
    if (normalized == QStringLiteral("H264") || normalized == QStringLiteral("AVC")) {
        if (preferHardware && ffmpegHasEncoder(QStringLiteral("h264_v4l2m2m"))) return QStringLiteral("h264_v4l2m2m");
        if (ffmpegHasEncoder(QStringLiteral("libx264"))) return QStringLiteral("libx264");
    }
    if (normalized == QStringLiteral("H265") || normalized == QStringLiteral("HEVC")) {
        if (preferHardware && ffmpegHasEncoder(QStringLiteral("hevc_v4l2m2m"))) return QStringLiteral("hevc_v4l2m2m");
        if (ffmpegHasEncoder(QStringLiteral("libx265"))) return QStringLiteral("libx265");
    }
    if (normalized == QStringLiteral("AV1")) {
        for (const QString &encoder : {QStringLiteral("libsvtav1"), QStringLiteral("librav1e"), QStringLiteral("libaom-av1")})
            if (ffmpegHasEncoder(encoder)) return encoder;
    }
    if (normalized == QStringLiteral("VP9") && ffmpegHasEncoder(QStringLiteral("libvpx-vp9")))
        return QStringLiteral("libvpx-vp9");
    if (normalized == QStringLiteral("VVC") || normalized == QStringLiteral("H266")) {
        for (const QString &encoder : {QStringLiteral("libvvenc"), QStringLiteral("libx266")})
            if (ffmpegHasEncoder(encoder)) return encoder;
    }
    return QString();
}

QString MediaOptimizerManager::selectAudioEncoder(const QString &mode) const
{
    const QString normalized = mode.trimmed().toUpper();
    if (normalized == QStringLiteral("ORIGINAL") || normalized == QStringLiteral("KEEP")) return QStringLiteral("copy");
    if (normalized == QStringLiteral("WAV")) return QStringLiteral("pcm_s24le");
    if (normalized == QStringLiteral("FLAC")) return QStringLiteral("flac");
    if (normalized == QStringLiteral("AAC")) return QStringLiteral("aac");
    if (normalized == QStringLiteral("AC3")) return QStringLiteral("ac3");
    if (normalized == QStringLiteral("EAC3")) return QStringLiteral("eac3");
    if (normalized == QStringLiteral("OPUS")) return ffmpegHasEncoder(QStringLiteral("libopus")) ? QStringLiteral("libopus") : QStringLiteral("opus");
    if (normalized == QStringLiteral("MP3")) return ffmpegHasEncoder(QStringLiteral("libmp3lame")) ? QStringLiteral("libmp3lame") : QStringLiteral("mp3");
    return QString();
}

bool MediaOptimizerManager::verifyOutputFile(const QString &path) const
{
    const QString ffprobe = executable(QStringLiteral("ffprobe"));
    if (ffprobe.isEmpty() || !QFileInfo(path).exists() || QFileInfo(path).size() <= 0)
        return false;
    QProcess process;
    process.setProgram(ffprobe);
    process.setArguments({QStringLiteral("-v"), QStringLiteral("error"),
                          QStringLiteral("-show_entries"), QStringLiteral("format=duration"),
                          QStringLiteral("-of"), QStringLiteral("default=noprint_wrappers=1:nokey=1"), path});
    process.start();
    if (!process.waitForStarted(2000) || !process.waitForFinished(12000)) {
        process.kill();
        return false;
    }
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0 &&
           !QString::fromUtf8(process.readAllStandardOutput()).trimmed().isEmpty();
}

QStringList MediaOptimizerManager::selectedAudioIndexes(const QVariantMap &item,
                                                        const QString &trackMode) const
{
    const QVariantList tracks = item.value(QStringLiteral("audioTracks")).toList();
    const QString mode = trackMode.trimmed().toUpper();
    QStringList indexes;
    if (mode.isEmpty() || mode == QStringLiteral("UNCHANGED") ||
        mode == QStringLiteral("ORIGINAL") || mode == QStringLiteral("KEEP") ||
        mode == QStringLiteral("ALL")) {
        for (const QVariant &value : tracks)
            indexes.append(QString::number(value.toMap().value(QStringLiteral("index")).toInt()));
        return indexes;
    }
    QVariantList english;
    for (const QVariant &value : tracks) {
        if (isEnglish(value.toMap().value(QStringLiteral("language")).toString()))
            english.append(value);
    }
    if (mode == QStringLiteral("ENGLISH")) {
        for (const QVariant &value : english)
            indexes.append(QString::number(value.toMap().value(QStringLiteral("index")).toInt()));
        return indexes;
    }
    const QVariantList candidates = english.isEmpty() ? tracks : english;
    QVariantMap best;
    int bestScore = -1;
    for (const QVariant &value : candidates) {
        const QVariantMap track = value.toMap();
        int score = track.value(QStringLiteral("channels")).toInt() * 10;
        if (track.value(QStringLiteral("default")).toBool())
            score += 100;
        if (track.value(QStringLiteral("compatible")).toBool())
            score += 20;
        if (track.value(QStringLiteral("atmos")).toBool())
            score += 5;
        if (score > bestScore) {
            bestScore = score;
            best = track;
        }
    }
    if (!best.isEmpty())
        indexes.append(QString::number(best.value(QStringLiteral("index")).toInt()));
    return indexes;
}

QStringList MediaOptimizerManager::selectedSubtitleIndexes(const QVariantMap &item,
                                                           const QString &subtitleMode) const
{
    const QVariantList tracks = item.value(QStringLiteral("subtitleTracks")).toList();
    const QString mode = subtitleMode.trimmed().toUpper();
    QStringList indexes;
    if (mode.isEmpty() || mode == QStringLiteral("UNCHANGED") ||
        mode == QStringLiteral("ORIGINAL") || mode == QStringLiteral("KEEP")) {
        for (const QVariant &value : tracks)
            indexes.append(QString::number(value.toMap().value(QStringLiteral("index")).toInt()));
        return indexes;
    }
    if (mode == QStringLiteral("REMOVE_ALL"))
        return indexes;
    for (const QVariant &value : tracks) {
        const QVariantMap track = value.toMap();
        const bool image = track.value(QStringLiteral("imageBased")).toBool();
        const bool english = isEnglish(track.value(QStringLiteral("language")).toString());
        bool include = false;
        if (mode == QStringLiteral("KEEP_ALL"))
            include = true;
        else if (mode == QStringLiteral("REMOVE_IMAGE"))
            include = !image;
        else if (mode == QStringLiteral("KEEP_ENGLISH"))
            include = english;
        else if (mode == QStringLiteral("KEEP_ENGLISH_TEXT"))
            include = english && !image;
        else if (mode == QStringLiteral("KEEP_TEXT"))
            include = !image;
        else if (mode == QStringLiteral("KEEP_IMAGE"))
            include = image;
        if (include)
            indexes.append(QString::number(track.value(QStringLiteral("index")).toInt()));
    }
    return indexes;
}

QVariantList MediaOptimizerManager::incompatibleForConfiguration(const QVariantMap &configuration) const
{
    QVariantList result;
    if (!configurationHasActualChanges(configuration))
        return result;

    const QString video = normalizedChoice(configuration.value(QStringLiteral("videoCodec")));
    const QString audio = normalizedChoice(configuration.value(QStringLiteral("audioCodec")));
    const QString subtitles = normalizedChoice(configuration.value(QStringLiteral("subtitleMode")));
    const QString container = normalizedChoice(configuration.value(QStringLiteral("container")));
    const QString policy = normalized4KPolicy(configuration);
    const bool anyVideoConversion = videoConversionSelected(configuration);
    const bool explicitVideoCodec = !isUnchangedChoice(configuration.value(QStringLiteral("videoCodec")));
    const bool explicitContainer = !isUnchangedChoice(configuration.value(QStringLiteral("container")));
    const bool explicitAudioCodec = !isUnchangedChoice(configuration.value(QStringLiteral("audioCodec")));
    const bool explicitAudioShape = !isUnchangedChoice(configuration.value(QStringLiteral("audioChannels"))) ||
                                    hasExplicitPositiveNumber(configuration, QStringLiteral("audioBitrateKbps")) ||
                                    hasExplicitPositiveNumber(configuration, QStringLiteral("sampleRate")) ||
                                    !isUnchangedChoice(configuration.value(QStringLiteral("trackMode")));
    const bool explicitSubtitles = !isUnchangedChoice(configuration.value(QStringLiteral("subtitleMode"))) ||
                                   !configuration.value(QStringLiteral("subtitleInjectionPath")).toString().trimmed().isEmpty();
    const bool explicitMetadata = !isUnchangedChoice(configuration.value(QStringLiteral("metadataMode"))) ||
                                  configuration.contains(QStringLiteral("copyMetadata"));

    for (const QVariant &value : m_media) {
        QVariantMap item = value.toMap();
        if (item.value(QStringLiteral("is4K")).toBool() &&
            policy != QStringLiteral("ALLOW_4K_CONVERSION"))
            continue;

        bool incompatible = false;
        if (anyVideoConversion) {
            if (explicitVideoCodec) {
                const QString currentVideo = normalizedChoice(item.value(QStringLiteral("videoCodec")));
                const QString wanted = video == QStringLiteral("H265") ? QStringLiteral("HEVC") : video;
                incompatible = incompatible || (currentVideo != wanted &&
                                                 !(video == QStringLiteral("H265") && currentVideo == QStringLiteral("H265")));
            } else {
                incompatible = true;
            }
            incompatible = incompatible ||
                hasExplicitPositiveNumber(configuration, QStringLiteral("videoBitrateKbps")) ||
                !isUnchangedChoice(configuration.value(QStringLiteral("resolution"))) ||
                !isUnchangedChoice(configuration.value(QStringLiteral("frameRate"))) ||
                !isUnchangedChoice(configuration.value(QStringLiteral("profile"))) ||
                !isUnchangedChoice(configuration.value(QStringLiteral("pixelFormat")));
        }

        if (explicitContainer) {
            const QString currentExtension = normalizedChoice(item.value(QStringLiteral("extension")));
            const QString wanted = container == QStringLiteral("M4V") ? QStringLiteral("MP4") : container;
            incompatible = incompatible || currentExtension != wanted;
        }

        if (explicitAudioCodec) {
            const QVariantList tracks = item.value(QStringLiteral("audioTracks")).toList();
            bool allMatch = !tracks.isEmpty();
            for (const QVariant &trackValue : tracks)
                allMatch = allMatch && normalizedChoice(trackValue.toMap().value(QStringLiteral("codec"))) == audio;
            incompatible = incompatible || !allMatch;
        }
        incompatible = incompatible || explicitAudioShape;

        if (explicitSubtitles) {
            if (subtitles == QStringLiteral("REMOVE_ALL"))
                incompatible = incompatible || item.value(QStringLiteral("subtitleTrackCount")).toInt() > 0;
            else if (subtitles == QStringLiteral("KEEP_ENGLISH_TEXT") || subtitles == QStringLiteral("KEEP_TEXT") ||
                     subtitles == QStringLiteral("REMOVE_IMAGE"))
                incompatible = incompatible || item.value(QStringLiteral("hasImageSubtitles")).toBool();
            else
                incompatible = true;
        }

        incompatible = incompatible || explicitMetadata;
        if (incompatible)
            result.append(item);
    }
    return result;
}

bool MediaOptimizerManager::startOptimization(const QString &path,
                                              const QVariantMap &settings)
{
    if (m_busy || m_scanning)
        return false;
    const QVariantMap item = findMedia(path);
    if (item.isEmpty()) {
        m_lastMessage = QStringLiteral("The selected media file is not part of the current scan.");
        emit stateChanged();
        return false;
    }
    if (!configurationHasActualChanges(settings)) {
        completeAnalysisOnly();
        return false;
    }

    const QString policy = normalized4KPolicy(settings);
    const bool is4K = item.value(QStringLiteral("is4K")).toBool();
    const bool videoConversion = videoConversionSelected(settings);
    if (is4K && policy != QStringLiteral("ALLOW_4K_CONVERSION")) {
        m_lastMessage = policy == QStringLiteral("SKIP_4K_FILES")
            ? QStringLiteral("This 4K file was skipped by the active 4K policy.")
            : QStringLiteral("This 4K file is protected by Keep 4K Unchanged.");
        emit stateChanged();
        return false;
    }
    if (is4K && videoConversion && !m_queue4KAuthorized) {
        m_lastMessage = QStringLiteral("4K conversion is blocked. Review and arm the separate 4K danger confirmation first.");
        emit stateChanged();
        return false;
    }

    const QString ffmpeg = executable(QStringLiteral("ffmpeg"));
    if (ffmpeg.isEmpty()) {
        m_lastMessage = QStringLiteral("FFmpeg is not installed.");
        emit stateChanged();
        return false;
    }

    const QVariant videoCodecSetting = settings.value(QStringLiteral("videoCodec"), QStringLiteral("Unchanged"));
    const QVariant audioCodecSetting = settings.value(QStringLiteral("audioCodec"), QStringLiteral("Unchanged"));
    const QString targetVideoMode = isUnchangedChoice(videoCodecSetting)
        ? sourceVideoEncoderMode(item) : normalizedChoice(videoCodecSetting);
    const QString targetAudioMode = isUnchangedChoice(audioCodecSetting)
        ? sourceAudioEncoderMode(item) : normalizedChoice(audioCodecSetting);
    const QString container = effectiveContainerFor(item, settings);
    const bool explicitContainer = !isUnchangedChoice(settings.value(QStringLiteral("container")));
    const bool audioConversion = !isUnchangedChoice(audioCodecSetting) ||
                                 !isUnchangedChoice(settings.value(QStringLiteral("audioChannels"))) ||
                                 hasExplicitPositiveNumber(settings, QStringLiteral("audioBitrateKbps")) ||
                                 hasExplicitPositiveNumber(settings, QStringLiteral("sampleRate"));

    const bool replaceOriginals = settings.value(QStringLiteral("replaceOriginals"), false).toBool();
    if (replaceOriginals && explicitContainer) {
        QVariantMap unchangedSettings = defaultSafeConfiguration();
        const QString sourceContainer = effectiveContainerFor(item, unchangedSettings);
        if (containerFormat(sourceContainer) != containerFormat(container)) {
            m_lastMessage = QStringLiteral("Replace Originals cannot change the container because the original filename extension would become misleading. Choose Create New Files.");
            emit stateChanged();
            return false;
        }
    }

    QStringList arguments{QStringLiteral("-hide_banner"), QStringLiteral("-y"),
                          QStringLiteral("-i"), item.value(QStringLiteral("path")).toString()};
    const QString injectedSubtitle = settings.value(QStringLiteral("subtitleInjectionPath")).toString().trimmed();
    const QString requestedSubtitleMode = normalizedChoice(
        settings.value(QStringLiteral("subtitleMode"), QStringLiteral("Unchanged")));
    const bool injectSubtitle = !injectedSubtitle.isEmpty() && QFileInfo::exists(injectedSubtitle);
    if (requestedSubtitleMode == QStringLiteral("INJECT") && !injectSubtitle) {
        m_lastMessage = QStringLiteral("Subtitle injection was selected, but the chosen .srt file is missing or invalid. No media file was rewritten.");
        emit stateChanged();
        return false;
    }
    if (injectSubtitle)
        arguments << QStringLiteral("-i") << injectedSubtitle;

    const QString metadataMode = normalizedChoice(settings.value(QStringLiteral("metadataMode"), QStringLiteral("Unchanged")));
    if (metadataMode == QStringLiteral("PRESERVE") ||
        (!settings.contains(QStringLiteral("metadataMode")) &&
         settings.value(QStringLiteral("copyMetadata"), false).toBool())) {
        arguments << QStringLiteral("-map_metadata") << QStringLiteral("0")
                  << QStringLiteral("-map_chapters") << QStringLiteral("0");
    } else if (metadataMode == QStringLiteral("STRIP") || metadataMode == QStringLiteral("REMOVE") ||
               (!settings.contains(QStringLiteral("metadataMode")) &&
                settings.contains(QStringLiteral("copyMetadata")) &&
                !settings.value(QStringLiteral("copyMetadata")).toBool())) {
        arguments << QStringLiteral("-map_metadata") << QStringLiteral("-1")
                  << QStringLiteral("-map_chapters") << QStringLiteral("-1");
    }

    arguments << QStringLiteral("-map") << QStringLiteral("0:v?");
    if (!videoConversion) {
        arguments << QStringLiteral("-c:v") << QStringLiteral("copy");
    } else {
        const QString preference = isUnchangedChoice(settings.value(QStringLiteral("encoderPreference")))
            ? QString() : settings.value(QStringLiteral("encoderPreference")).toString();
        const QString encoder = selectVideoEncoder(targetVideoMode, preference);
        if (encoder.isEmpty()) {
            m_lastMessage = QStringLiteral("The selected video encoder is not available in this FFmpeg build: %1").arg(targetVideoMode);
            emit stateChanged();
            return false;
        }
        arguments << QStringLiteral("-c:v") << encoder;
        const int videoBitrate = hasExplicitPositiveNumber(settings, QStringLiteral("videoBitrateKbps"))
            ? settings.value(QStringLiteral("videoBitrateKbps")).toInt() : 0;
        if (videoBitrate > 0)
            arguments << QStringLiteral("-b:v") << QStringLiteral("%1k").arg(videoBitrate);
        else if (encoder.contains(QStringLiteral("264")))
            arguments << QStringLiteral("-crf") << QStringLiteral("20");
        else if (encoder.contains(QStringLiteral("265")))
            arguments << QStringLiteral("-crf") << QStringLiteral("22");
        else
            arguments << QStringLiteral("-crf") << QStringLiteral("31") << QStringLiteral("-b:v") << QStringLiteral("0");
        if (encoder.startsWith(QStringLiteral("libx")))
            arguments << QStringLiteral("-preset") << QStringLiteral("medium");
        else if (encoder == QStringLiteral("libsvtav1"))
            arguments << QStringLiteral("-preset") << QStringLiteral("8");

        const QVariant resolutionValue = settings.value(QStringLiteral("resolution"));
        if (!isUnchangedChoice(resolutionValue) && resolutionValue.toString().contains(QLatin1Char('x'), Qt::CaseInsensitive))
            arguments << QStringLiteral("-s") << resolutionValue.toString();
        const QVariant frameRateValue = settings.value(QStringLiteral("frameRate"));
        if (!isUnchangedChoice(frameRateValue))
            arguments << QStringLiteral("-r") << frameRateValue.toString();
        const QVariant pixelFormatValue = settings.value(QStringLiteral("pixelFormat"));
        if (!isUnchangedChoice(pixelFormatValue))
            arguments << QStringLiteral("-pix_fmt") << pixelFormatValue.toString();
        const QVariant profileValue = settings.value(QStringLiteral("profile"));
        if (!isUnchangedChoice(profileValue) && normalizedChoice(profileValue) != QStringLiteral("AUTO"))
            arguments << QStringLiteral("-profile:v") << profileValue.toString().toLower();
    }

    const QStringList audioIndexes = selectedAudioIndexes(item,
        settings.value(QStringLiteral("trackMode"), QStringLiteral("Unchanged")).toString());
    for (const QString &index : audioIndexes)
        arguments << QStringLiteral("-map") << QStringLiteral("0:%1?").arg(index);
    if (!audioIndexes.isEmpty()) {
        const QString audioEncoder = audioConversion ? selectAudioEncoder(targetAudioMode) : QStringLiteral("copy");
        if (audioEncoder.isEmpty()) {
            m_lastMessage = QStringLiteral("The selected audio encoder is unavailable: %1").arg(targetAudioMode);
            emit stateChanged();
            return false;
        }
        arguments << QStringLiteral("-c:a") << audioEncoder;
        if (audioEncoder != QStringLiteral("copy") && !audioEncoder.startsWith(QStringLiteral("pcm")) &&
            audioEncoder != QStringLiteral("flac") &&
            hasExplicitPositiveNumber(settings, QStringLiteral("audioBitrateKbps"))) {
            const int bitrate = settings.value(QStringLiteral("audioBitrateKbps")).toInt();
            arguments << QStringLiteral("-b:a") << QStringLiteral("%1k").arg(qMax(64, bitrate));
        }
        const QVariant channelsValue = settings.value(QStringLiteral("audioChannels"));
        if (!isUnchangedChoice(channelsValue) && audioEncoder != QStringLiteral("copy")) {
            const QString channels = channelsValue.toString();
            if (channels == QStringLiteral("2.1")) arguments << QStringLiteral("-ac") << QStringLiteral("3");
            else if (channels == QStringLiteral("5.1")) arguments << QStringLiteral("-ac") << QStringLiteral("6");
            else if (channels == QStringLiteral("7.1")) arguments << QStringLiteral("-ac") << QStringLiteral("8");
            else if (channels == QStringLiteral("2.0") || channels == QStringLiteral("Stereo")) arguments << QStringLiteral("-ac") << QStringLiteral("2");
        }
        if (hasExplicitPositiveNumber(settings, QStringLiteral("sampleRate")) && audioEncoder != QStringLiteral("copy"))
            arguments << QStringLiteral("-ar") << QString::number(settings.value(QStringLiteral("sampleRate")).toInt());
    }

    const QVariant subtitleModeValue = settings.value(QStringLiteral("subtitleMode"), QStringLiteral("Unchanged"));
    const QString subtitleMode = normalizedChoice(subtitleModeValue);
    const QStringList subtitleIndexes = selectedSubtitleIndexes(item, subtitleMode);
    for (const QString &index : subtitleIndexes)
        arguments << QStringLiteral("-map") << QStringLiteral("0:%1?").arg(index);
    if (injectSubtitle)
        arguments << QStringLiteral("-map") << QStringLiteral("1:0?");
    if (!subtitleIndexes.isEmpty() || injectSubtitle) {
        const bool subtitleChanged = !isUnchangedChoice(subtitleModeValue) || injectSubtitle;
        if (!subtitleChanged) {
            arguments << QStringLiteral("-c:s") << QStringLiteral("copy");
        } else {
            const bool mp4 = container == QStringLiteral("MP4");
            arguments << QStringLiteral("-c:s") << (mp4 ? QStringLiteral("mov_text") : QStringLiteral("srt"));
        }
    }

    m_currentInput = item.value(QStringLiteral("path")).toString();
    m_replaceOriginal = replaceOriginals;
    m_currentOutput = m_replaceOriginal ? m_currentInput : outputPathFor(m_currentInput, settings);
    const QFileInfo inputInfo(m_currentInput);
    QString temporaryExtension = container.toLower();
    if (container == QStringLiteral("TS")) temporaryExtension = QStringLiteral("ts");
    else if (container == QStringLiteral("MPEG")) temporaryExtension = QStringLiteral("mpeg");
    else if (container == QStringLiteral("WMV")) temporaryExtension = QStringLiteral("wmv");
    if (temporaryExtension.isEmpty())
        temporaryExtension = inputInfo.suffix().isEmpty() ? QStringLiteral("mkv") : inputInfo.suffix();
    const QString partialName = QStringLiteral(".%1.neutronos-partial-%2.%3")
        .arg(inputInfo.completeBaseName())
        .arg(QUuid::createUuid().toString(QUuid::WithoutBraces))
        .arg(temporaryExtension);
    m_temporaryOutput = inputInfo.absoluteDir().filePath(partialName);
    m_replacementBackup = inputInfo.absoluteDir().filePath(QStringLiteral(".%1.neutronos-safe-original-%2.%3")
        .arg(inputInfo.completeBaseName())
        .arg(QUuid::createUuid().toString(QUuid::WithoutBraces))
        .arg(inputInfo.suffix()));
    QFile::remove(m_temporaryOutput);
    QFile::remove(m_replacementBackup);
    m_currentDurationMs = item.value(QStringLiteral("durationMs")).toLongLong();
    m_currentSourceSize = inputInfo.size();
    m_currentPermissions = inputInfo.permissions();
    m_currentModified = inputInfo.lastModified();
    m_ffmpegErrors.clear();

    arguments << QStringLiteral("-max_muxing_queue_size") << QStringLiteral("4096")
              << QStringLiteral("-progress") << QStringLiteral("pipe:1")
              << QStringLiteral("-nostats")
              << QStringLiteral("-f") << containerFormat(container)
              << m_temporaryOutput;

    if (!m_ffmpegProcess) {
        m_ffmpegProcess = new QProcess(this);
        connect(m_ffmpegProcess, &QProcess::readyReadStandardOutput, this, &MediaOptimizerManager::onFfmpegStandardOutput);
        connect(m_ffmpegProcess, &QProcess::readyReadStandardError, this, &MediaOptimizerManager::onFfmpegStandardError);
        connect(m_ffmpegProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, &MediaOptimizerManager::onFfmpegFinished);
        connect(m_ffmpegProcess, &QProcess::errorOccurred, this, &MediaOptimizerManager::onFfmpegError);
    }

    m_busy = true;
    m_queueStage = QStringLiteral("Encoding %1").arg(inputInfo.fileName());
    setState(QStringLiteral("Optimizing media"), 0,
             m_replaceOriginal ? QStringLiteral("Creating and verifying a safe replacement before touching the original.")
                               : QStringLiteral("Creating a new optimized media file beside the original."));
    emit queueChanged();
    m_ffmpegProcess->setProgram(ffmpeg);
    m_ffmpegProcess->setArguments(arguments);
    m_ffmpegProcess->setProcessChannelMode(QProcess::SeparateChannels);
    m_ffmpegProcess->start();
    return true;
}

bool MediaOptimizerManager::startOptimizationQueue(const QVariantList &paths,
                                                    const QVariantMap &settings,
                                                    bool replaceOriginals)
{
    if (m_busy || m_scanning || paths.isEmpty())
        return false;
    if (!configurationHasActualChanges(settings)) {
        completeAnalysisOnly();
        return false;
    }

    const QString policy = normalized4KPolicy(settings);
    m_queuePaths.clear();
    QSet<QString> seen;
    int protected4KCount = 0;
    bool requires4KAuthorization = false;
    for (const QVariant &value : paths) {
        const QString path = QFileInfo(value.toString()).absoluteFilePath();
        const QVariantMap item = findMedia(path);
        if (path.isEmpty() || seen.contains(path) || item.isEmpty())
            continue;
        seen.insert(path);

        if (item.value(QStringLiteral("is4K")).toBool()) {
            if (policy != QStringLiteral("ALLOW_4K_CONVERSION")) {
                ++protected4KCount;
                continue;
            }
            requires4KAuthorization = requires4KAuthorization || videoConversionSelected(settings);
        }
        m_queuePaths.append(path);
    }

    if (m_queuePaths.isEmpty()) {
        m_lastMessage = protected4KCount > 0
            ? (policy == QStringLiteral("SKIP_4K_FILES")
                ? QStringLiteral("All selected files were 4K and were skipped. No media file was rewritten.")
                : QStringLiteral("All selected files were protected by Keep 4K Unchanged. No media file was rewritten."))
            : QStringLiteral("No valid scanned media files were selected.");
        emit stateChanged();
        return false;
    }

    const QByteArray fingerprint = fourKAuthorizationFingerprint(paths, settings);
    if (requires4KAuthorization && m_authorized4KFingerprint != fingerprint) {
        m_queuePaths.clear();
        m_lastMessage = QStringLiteral("4K conversion is blocked. The separate danger warning must be armed for this exact queue and configuration.");
        emit stateChanged();
        return false;
    }
    m_queue4KAuthorized = requires4KAuthorization;
    clear4KAuthorization();

    m_queueSettings = settings;
    m_queueSettings.insert(QStringLiteral("replaceOriginals"), replaceOriginals);
    m_queueIndex = 0;
    m_queueCompleted = 0;
    m_queueTotal = m_queuePaths.size();
    m_queueStorageDelta = 0;
    m_queueEstimatedMs = 0;
    m_queueErrors.clear();
    m_queueActive = true;
    m_queueStage = protected4KCount > 0
        ? QStringLiteral("Preparing queue · %1 protected 4K file%2 left unchanged")
              .arg(protected4KCount).arg(protected4KCount == 1 ? QString() : QStringLiteral("s"))
        : QStringLiteral("Preparing optimization queue");
    m_queueTimer.restart();
    emit queueChanged();
    QTimer::singleShot(0, this, &MediaOptimizerManager::startNextQueuedItem);
    return true;
}

void MediaOptimizerManager::startNextQueuedItem()
{
    if (!m_queueActive)
        return;
    if (m_queueIndex >= m_queuePaths.size()) {
        finishQueue(m_queueErrors.isEmpty(), m_queueErrors.isEmpty()
            ? QStringLiteral("Optimization queue completed successfully.")
            : QStringLiteral("Optimization queue completed with %1 error%2.")
                .arg(m_queueErrors.size()).arg(m_queueErrors.size() == 1 ? QString() : QStringLiteral("s")));
        return;
    }
    const QString path = m_queuePaths.at(m_queueIndex).toString();
    m_queueStage = QStringLiteral("Starting %1 of %2 · %3")
        .arg(m_queueIndex + 1).arg(m_queueTotal).arg(QFileInfo(path).fileName());
    emit queueChanged();
    if (!startOptimization(path, m_queueSettings)) {
        m_queueErrors.append(QVariantMap{{QStringLiteral("path"), path},
                                         {QStringLiteral("message"), m_lastMessage}});
        ++m_queueIndex;
        updateQueueEstimate();
        QTimer::singleShot(0, this, &MediaOptimizerManager::startNextQueuedItem);
    }
}

void MediaOptimizerManager::updateQueueEstimate()
{
    if (!m_queueTimer.isValid() || m_queueCompleted <= 0) {
        m_queueEstimatedMs = 0;
    } else {
        const qint64 average = m_queueTimer.elapsed() / qMax(1, m_queueCompleted);
        m_queueEstimatedMs = average * qMax(0, m_queueTotal - m_queueCompleted);
    }
    emit queueChanged();
}

void MediaOptimizerManager::finishQueue(bool success, const QString &message)
{
    m_queueActive = false;
    m_queue4KAuthorized = false;
    clear4KAuthorization();
    m_queueStage = success ? QStringLiteral("Complete") : QStringLiteral("Complete with errors");
    m_queueEstimatedMs = 0;
    m_lastMessage = message;
    emit queueChanged();
    emit stateChanged();
    emit optimizationQueueFinished(success, message);
    if (!m_selectedRoot.isEmpty())
        QTimer::singleShot(150, this, [this]() { if (!m_scanning && !m_busy) scanLocation(m_selectedRoot); });
}

void MediaOptimizerManager::onFfmpegStandardOutput()
{
    if (!m_ffmpegProcess)
        return;
    const QString text = QString::fromUtf8(m_ffmpegProcess->readAllStandardOutput());
    const QStringList lines = text.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        if (line.startsWith(QStringLiteral("out_time_ms="))) {
            bool ok = false;
            const qint64 microseconds = line.mid(QStringLiteral("out_time_ms=").size()).toLongLong(&ok);
            if (ok && m_currentDurationMs > 0) {
                const qint64 currentMs = microseconds / 1000;
                m_progress = qBound(0, static_cast<int>((100.0 * currentMs) / m_currentDurationMs), 99);
                emit stateChanged();
            }
        }
    }
}

void MediaOptimizerManager::onFfmpegStandardError()
{
    if (!m_ffmpegProcess)
        return;
    m_ffmpegErrors += m_ffmpegProcess->readAllStandardError();
    if (m_ffmpegErrors.size() > 512 * 1024)
        m_ffmpegErrors = m_ffmpegErrors.right(512 * 1024);
}

void MediaOptimizerManager::finishOptimization(bool success, const QString &message)
{
    QString output = m_currentOutput;
    if (!success) {
        QFile::remove(m_temporaryOutput);
    } else if (!verifyOutputFile(m_temporaryOutput)) {
        success = false;
        QFile::remove(m_temporaryOutput);
        output.clear();
    } else if (m_replaceOriginal) {
        if (!QFile::rename(m_currentInput, m_replacementBackup)) {
            success = false;
            QFile::remove(m_temporaryOutput);
            output.clear();
        } else if (!QFile::rename(m_temporaryOutput, m_currentInput)) {
            QFile::rename(m_replacementBackup, m_currentInput);
            success = false;
            QFile::remove(m_temporaryOutput);
            output.clear();
        } else {
            QFile replacement(m_currentInput);
            replacement.setPermissions(m_currentPermissions);
            if (m_currentModified.isValid())
                replacement.setFileTime(m_currentModified, QFileDevice::FileModificationTime);
            QFile::remove(m_replacementBackup);
            output = m_currentInput;
        }
    } else {
        QFile::remove(output);
        if (!QFile::rename(m_temporaryOutput, output)) {
            success = false;
            QFile::remove(m_temporaryOutput);
            output.clear();
        }
    }
    m_busy = false;
    m_progress = success ? 100 : -1;
    m_operationStatus = success ? QStringLiteral("Optimization complete") : QStringLiteral("Optimization failed");
    m_lastMessage = message;
    emit stateChanged();
    emit optimizationFinished(success, m_lastMessage, output);
}

void MediaOptimizerManager::onFfmpegFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    onFfmpegStandardOutput();
    onFfmpegStandardError();
    if (!m_busy)
        return;
    const QString completedInput = m_currentInput;
    const qint64 sourceSize = m_currentSourceSize;
    const bool encoded = exitStatus == QProcess::NormalExit && exitCode == 0 &&
                         QFileInfo(m_temporaryOutput).exists() && QFileInfo(m_temporaryOutput).size() > 0;
    bool success = encoded && verifyOutputFile(m_temporaryOutput);
    const qint64 outputSize = success ? QFileInfo(m_temporaryOutput).size() : 0;
    QString message;
    if (success) {
        const qint64 delta = outputSize - sourceSize;
        message = QStringLiteral("%1 · storage %2")
            .arg(m_replaceOriginal ? QStringLiteral("Original safely replaced") : QStringLiteral("Optimized copy created"),
                 formatSignedBytes(delta));
        m_queueStorageDelta += delta;
    } else {
        const QString error = QString::fromUtf8(m_ffmpegErrors).trimmed();
        message = error.isEmpty() ? QStringLiteral("FFmpeg exited with code %1 or output verification failed.").arg(exitCode)
                                  : error.right(3000);
    }
    finishOptimization(success, message);

    if (m_queueActive) {
        if (!success)
            m_queueErrors.append(QVariantMap{{QStringLiteral("path"), completedInput},
                                             {QStringLiteral("message"), message}});
        ++m_queueIndex;
        ++m_queueCompleted;
        updateQueueEstimate();
        QTimer::singleShot(80, this, &MediaOptimizerManager::startNextQueuedItem);
    }
}

void MediaOptimizerManager::onFfmpegError(QProcess::ProcessError error)
{
    Q_UNUSED(error)
    if (!m_busy)
        return;
    const QString path = m_currentInput;
    const QString message = m_ffmpegProcess ? m_ffmpegProcess->errorString()
                                             : QStringLiteral("FFmpeg process failed.");
    finishOptimization(false, message);
    if (m_queueActive) {
        m_queueErrors.append(QVariantMap{{QStringLiteral("path"), path},
                                         {QStringLiteral("message"), message}});
        ++m_queueIndex;
        ++m_queueCompleted;
        updateQueueEstimate();
        QTimer::singleShot(80, this, &MediaOptimizerManager::startNextQueuedItem);
    }
}

bool MediaOptimizerManager::cancelOperation()
{
    if (m_renameActive) {
        m_renameActive = false;
        m_renameStatus = QStringLiteral("Batch rename cancelled after %1 file%2.")
            .arg(m_renameCompleted)
            .arg(m_renameCompleted == 1 ? QString() : QStringLiteral("s"));
        m_lastMessage = m_renameStatus;
        if (!m_lastRenameUndo.isEmpty())
            saveRenameHistory();
        emit renameChanged();
        emit stateChanged();
        emit batchRenameFinished(false, m_renameStatus);
        return true;
    }
    if (m_scanning && m_scanWatcher && m_scanWatcher->isRunning()) {
        m_scanCancelRequested.store(true);
        m_lastMessage = QStringLiteral("Media scan cancellation requested. Completed probes will remain cached.");
        emit stateChanged();
        return true;
    }
    if (!m_busy && !m_queueActive)
        return false;
    m_queueActive = false;
    m_queue4KAuthorized = false;
    clear4KAuthorization();
    if (m_ffmpegProcess && m_ffmpegProcess->state() != QProcess::NotRunning) {
        m_ffmpegProcess->terminate();
        if (!m_ffmpegProcess->waitForFinished(1500))
            m_ffmpegProcess->kill();
    }
    if (m_busy)
        finishOptimization(false, QStringLiteral("Media optimization cancelled."));
    m_queueStage = QStringLiteral("Cancelled");
    emit queueChanged();
    return true;
}
