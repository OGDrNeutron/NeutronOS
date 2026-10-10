#include "CaptureManager.h"

#include "NotificationManager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <QSaveFile>
#include <QStandardPaths>
#include <QVariantMap>

#include <algorithm>

namespace {
constexpr qint64 MinimumRecordingBytes = 4096;
}

CaptureManager::CaptureManager(const QString &neutronRoot,
                               NotificationManager *notificationManager,
                               QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_userHome(canonicalUserHome(neutronRoot)),
      m_stateDirectory(QDir(m_neutronRoot).filePath(QStringLiteral("state/capture"))),
      m_settingsPath(QDir(m_stateDirectory).filePath(QStringLiteral("settings.json"))),
      m_screenshotsPath(QDir(m_userHome).filePath(QStringLiteral("Pictures/NeutronOS/Screenshots"))),
      m_recordingsPath(QDir(m_userHome).filePath(QStringLiteral("Videos/NeutronOS/Recordings"))),
      m_notificationManager(notificationManager)
{
    m_frameTimer.setTimerType(Qt::PreciseTimer);
    m_frameTimer.setSingleShot(false);
    connect(&m_frameTimer, &QTimer::timeout,
            this, &CaptureManager::captureNextFrame);

    m_elapsedTimer.setInterval(1000);
    m_elapsedTimer.setTimerType(Qt::CoarseTimer);
    m_elapsedTimer.setSingleShot(false);
    connect(&m_elapsedTimer, &QTimer::timeout,
            this, &CaptureManager::updateElapsedTime);

    connect(&m_encoder, &QProcess::errorOccurred,
            this, &CaptureManager::handleEncoderError);
    connect(&m_encoder,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &CaptureManager::handleEncoderFinished);

    ensureDirectories();
    loadSettings();
}

CaptureManager::~CaptureManager()
{
    if (m_recording)
        stopRecording();
}

bool CaptureManager::recording() const
{
    return m_recording;
}

int CaptureManager::elapsedSeconds() const
{
    return m_elapsedSeconds;
}

QString CaptureManager::lastScreenshotPath() const
{
    return m_lastScreenshotPath;
}

QString CaptureManager::lastRecordingPath() const
{
    return m_lastRecordingPath;
}

QString CaptureManager::screenshotsPath() const
{
    return m_screenshotsPath;
}

QString CaptureManager::recordingsPath() const
{
    return m_recordingsPath;
}

QString CaptureManager::statusMessage() const
{
    return m_statusMessage;
}

bool CaptureManager::showIndicator() const
{
    return m_showIndicator;
}

int CaptureManager::frameRate() const
{
    return m_frameRate;
}

QString CaptureManager::resolution() const
{
    return m_resolution;
}

void CaptureManager::setShowIndicator(bool show)
{
    if (m_showIndicator == show)
        return;
    m_showIndicator = show;
    saveSettings();
    emit showIndicatorChanged();
}

void CaptureManager::setFrameRate(int framesPerSecond)
{
    const int normalized = framesPerSecond >= 60 ? 60 : 30;
    if (m_frameRate == normalized)
        return;
    m_frameRate = normalized;
    saveSettings();
    emit frameRateChanged();
}

void CaptureManager::setResolution(const QString &resolution)
{
    const QString clean = resolution.trimmed().toLower();
    const QString normalized = clean == QStringLiteral("1080p")
                               ? QStringLiteral("1080p")
                               : QStringLiteral("720p");
    if (m_resolution == normalized)
        return;
    m_resolution = normalized;
    saveSettings();
    emit resolutionChanged();
}

bool CaptureManager::captureScreenshot(QObject *windowObject)
{
    QQuickWindow *window = resolveWindow(windowObject);
    if (!window) {
        const QString message = QStringLiteral("The NeutronOS window was unavailable for capture.");
        setStatusMessage(message);
        emit captureError(message);
        return false;
    }

    if (!ensureDirectories()) {
        const QString message = QStringLiteral("The screenshot directory could not be created.");
        setStatusMessage(message);
        emit captureError(message);
        return false;
    }

    const QImage image = window->grabWindow();
    if (image.isNull()) {
        const QString message = QStringLiteral("NeutronOS could not read the current screen.");
        setStatusMessage(message);
        emit captureError(message);
        return false;
    }

    const QString path = QDir(m_screenshotsPath).filePath(
        QStringLiteral("NeutronOS_Screenshot_%1.png").arg(timestampToken())
    );

    if (!image.save(path, "PNG")) {
        const QString message = QStringLiteral("The screenshot could not be saved.");
        setStatusMessage(message);
        emit captureError(message);
        return false;
    }

    m_lastScreenshotPath = path;
    setStatusMessage(QStringLiteral("Screenshot saved"));
    emit lastScreenshotPathChanged();
    emit screenshotSaved(path);

    publishNotification(
        QStringLiteral("Screenshot Saved"),
        QFileInfo(path).fileName(),
        QStringLiteral("success"),
        QStringLiteral("open-gallery"),
        path,
        QStringLiteral("screenshot")
    );
    return true;
}

bool CaptureManager::startRecording(QObject *windowObject)
{
    if (m_recording)
        return true;

    QQuickWindow *window = resolveWindow(windowObject);
    if (!window) {
        const QString message = QStringLiteral("The NeutronOS window was unavailable for recording.");
        setStatusMessage(message);
        emit captureError(message);
        return false;
    }

    const QString ffmpeg = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    if (ffmpeg.isEmpty()) {
        const QString message = QStringLiteral("Screen recording requires ffmpeg.");
        setStatusMessage(message);
        emit captureError(message);
        publishNotification(
            QStringLiteral("Recording Could Not Start"), message,
            QStringLiteral("warning"), QString(), QString(), QStringLiteral("recording")
        );
        return false;
    }

    if (!ensureDirectories()) {
        const QString message = QStringLiteral("The recording directory could not be created.");
        setStatusMessage(message);
        emit captureError(message);
        return false;
    }

    const QSize sourceSize = window->size();
    m_targetSize = sizeForResolution(m_resolution, sourceSize);
    if (!m_targetSize.isValid()) {
        const QString message = QStringLiteral("The current display size is invalid for recording.");
        setStatusMessage(message);
        emit captureError(message);
        return false;
    }

    m_pendingRecordingPath = QDir(m_recordingsPath).filePath(
        QStringLiteral("NeutronOS_Recording_%1.mp4").arg(timestampToken())
    );

    QStringList arguments;
    arguments
        << QStringLiteral("-hide_banner")
        << QStringLiteral("-loglevel") << QStringLiteral("warning")
        << QStringLiteral("-y")
        << QStringLiteral("-f") << QStringLiteral("rawvideo")
        << QStringLiteral("-pixel_format") << QStringLiteral("bgra")
        << QStringLiteral("-video_size")
        << QStringLiteral("%1x%2").arg(m_targetSize.width()).arg(m_targetSize.height())
        << QStringLiteral("-framerate") << QString::number(m_frameRate)
        << QStringLiteral("-i") << QStringLiteral("pipe:0")
        << QStringLiteral("-an")
        << QStringLiteral("-c:v") << QStringLiteral("libx264")
        << QStringLiteral("-preset") << QStringLiteral("ultrafast")
        << QStringLiteral("-tune") << QStringLiteral("zerolatency")
        << QStringLiteral("-crf") << QStringLiteral("23")
        << QStringLiteral("-pix_fmt") << QStringLiteral("yuv420p")
        << QStringLiteral("-movflags") << QStringLiteral("+faststart")
        << m_pendingRecordingPath;

    m_encoder.setProgram(ffmpeg);
    m_encoder.setArguments(arguments);
    m_encoder.setProcessChannelMode(QProcess::SeparateChannels);
    m_encoder.start(QIODevice::WriteOnly);

    if (!m_encoder.waitForStarted(3000)) {
        const QString message = QStringLiteral("ffmpeg did not start: %1").arg(m_encoder.errorString());
        m_pendingRecordingPath.clear();
        setStatusMessage(message);
        emit captureError(message);
        publishNotification(
            QStringLiteral("Recording Could Not Start"), message,
            QStringLiteral("warning"), QString(), QString(), QStringLiteral("recording")
        );
        return false;
    }

    m_window = window;
    m_recording = true;
    m_stopping = false;
    m_elapsedSeconds = 0;
    setStatusMessage(QStringLiteral("Recording"));

    const int interval = std::max(1, 1000 / std::max(1, m_frameRate));
    m_frameTimer.setInterval(interval);
    m_frameTimer.start();
    m_elapsedTimer.start();

    emit recordingChanged();
    emit elapsedSecondsChanged();
    emit recordingStarted(m_pendingRecordingPath);

    publishNotification(
        QStringLiteral("Screen Recording Started"),
        QStringLiteral("Press R1 to stop recording."),
        QStringLiteral("info"),
        QStringLiteral("stop-recording"),
        m_pendingRecordingPath,
        QStringLiteral("recording")
    );

    captureNextFrame();
    return true;
}

bool CaptureManager::stopRecording()
{
    if (!m_recording)
        return false;

    m_stopping = true;
    m_frameTimer.stop();
    m_elapsedTimer.stop();

    if (m_encoder.state() != QProcess::NotRunning) {
        m_encoder.closeWriteChannel();
        if (!m_encoder.waitForFinished(15000)) {
            m_encoder.terminate();
            if (!m_encoder.waitForFinished(3000)) {
                m_encoder.kill();
                m_encoder.waitForFinished(2000);
            }
        }
    }

    const QFileInfo output(m_pendingRecordingPath);
    const bool success = output.isFile() && output.size() >= MinimumRecordingBytes;
    const QString errorMessage = success
        ? QString()
        : QStringLiteral("The screen recording did not produce a valid video file.");
    finishRecording(success, errorMessage);
    return success;
}

bool CaptureManager::toggleRecording(QObject *windowObject)
{
    return m_recording ? stopRecording() : startRecording(windowObject);
}

void CaptureManager::reloadSettings()
{
    loadSettings();
    emit showIndicatorChanged();
    emit frameRateChanged();
    emit resolutionChanged();
}

void CaptureManager::captureNextFrame()
{
    if (!m_recording || m_stopping || !m_window)
        return;

    if (m_encoder.state() != QProcess::Running) {
        finishRecording(false, QStringLiteral("The recording encoder stopped unexpectedly."));
        return;
    }

    const qint64 frameBytes = qint64(m_targetSize.width()) *
                              qint64(m_targetSize.height()) * 4;
    if (m_encoder.bytesToWrite() > frameBytes * 2)
        return;

    QImage image = m_window->grabWindow();
    if (image.isNull())
        return;

    if (image.size() != m_targetSize) {
        image = image.scaled(
            m_targetSize,
            Qt::IgnoreAspectRatio,
            Qt::SmoothTransformation
        );
    }

    if (image.format() != QImage::Format_ARGB32)
        image = image.convertToFormat(QImage::Format_ARGB32);

    const qint64 bytes = image.sizeInBytes();
    if (bytes != frameBytes)
        return;

    if (m_encoder.write(
            reinterpret_cast<const char *>(image.constBits()),
            bytes) < 0) {
        finishRecording(false, QStringLiteral("The recording frame could not be written."));
    }
}

void CaptureManager::updateElapsedTime()
{
    if (!m_recording)
        return;
    ++m_elapsedSeconds;
    emit elapsedSecondsChanged();
}

void CaptureManager::handleEncoderError(QProcess::ProcessError)
{
    if (!m_recording || m_stopping)
        return;
    finishRecording(
        false,
        QStringLiteral("Screen recording failed: %1").arg(m_encoder.errorString())
    );
}

void CaptureManager::handleEncoderFinished(int exitCode,
                                           QProcess::ExitStatus exitStatus)
{
    if (!m_recording || m_stopping)
        return;

    QString diagnostic = QString::fromLocal8Bit(m_encoder.readAllStandardError()).trimmed();
    if (diagnostic.size() > 320)
        diagnostic = diagnostic.right(320);

    QString message = QStringLiteral("The recording encoder exited unexpectedly (%1).").arg(exitCode);
    if (exitStatus == QProcess::CrashExit)
        message = QStringLiteral("The recording encoder crashed.");
    if (!diagnostic.isEmpty())
        message += QStringLiteral(" ") + diagnostic;
    finishRecording(false, message);
}

QString CaptureManager::canonicalUserHome(const QString &neutronRoot)
{
    const QFileInfo rootInfo(QDir::cleanPath(neutronRoot));
    const QString parent = rootInfo.dir().absolutePath();
    if (!parent.isEmpty() && parent != QStringLiteral("/"))
        return parent;
    return QDir::homePath();
}

QString CaptureManager::timestampToken()
{
    return QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd_HH-mm-ss-zzz"));
}

QSize CaptureManager::sizeForResolution(const QString &resolution,
                                        const QSize &windowSize)
{
    QSize result;
    if (resolution == QStringLiteral("1080p"))
        result = QSize(1920, 1080);
    else
        result = QSize(1280, 720);

    if (windowSize.width() > 0 && windowSize.height() > 0 &&
            windowSize.width() < result.width()) {
        result = windowSize;
    }

    result.setWidth(std::max(2, result.width() - (result.width() % 2)));
    result.setHeight(std::max(2, result.height() - (result.height() % 2)));
    return result;
}

QQuickWindow *CaptureManager::resolveWindow(QObject *windowObject) const
{
    return qobject_cast<QQuickWindow *>(windowObject);
}

bool CaptureManager::ensureDirectories()
{
    return QDir().mkpath(m_stateDirectory) &&
           QDir().mkpath(m_screenshotsPath) &&
           QDir().mkpath(m_recordingsPath);
}

bool CaptureManager::loadSettings()
{
    QFile file(m_settingsPath);
    if (!file.open(QIODevice::ReadOnly))
        return saveSettings();

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return false;

    const QJsonObject object = document.object();
    m_showIndicator = object.value(QStringLiteral("showIndicator")).toBool(true);
    m_frameRate = object.value(QStringLiteral("frameRate")).toInt(30) >= 60 ? 60 : 30;
    m_resolution = object.value(QStringLiteral("resolution")).toString(QStringLiteral("720p"));
    if (m_resolution != QStringLiteral("1080p"))
        m_resolution = QStringLiteral("720p");
    return true;
}

bool CaptureManager::saveSettings() const
{
    QDir().mkpath(m_stateDirectory);
    QSaveFile file(m_settingsPath);
    if (!file.open(QIODevice::WriteOnly))
        return false;

    QJsonObject object;
    object.insert(QStringLiteral("showIndicator"), m_showIndicator);
    object.insert(QStringLiteral("frameRate"), m_frameRate);
    object.insert(QStringLiteral("resolution"), m_resolution);
    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    return file.commit();
}

void CaptureManager::setStatusMessage(const QString &message)
{
    if (m_statusMessage == message)
        return;
    m_statusMessage = message;
    emit statusMessageChanged();
}

void CaptureManager::publishNotification(const QString &title,
                                         const QString &message,
                                         const QString &priority,
                                         const QString &action,
                                         const QString &path,
                                         const QString &mediaType)
{
    if (!m_notificationManager)
        return;

    QVariantMap payload;
    if (!path.isEmpty())
        payload.insert(QStringLiteral("path"), path);
    if (!mediaType.isEmpty())
        payload.insert(QStringLiteral("mediaType"), mediaType);

    m_notificationManager->publish(
        QStringLiteral("media"),
        title,
        message,
        priority,
        QStringLiteral("Capture"),
        action,
        payload
    );
}

void CaptureManager::finishRecording(bool success,
                                     const QString &errorMessage)
{
    if (!m_recording && m_pendingRecordingPath.isEmpty())
        return;

    m_frameTimer.stop();
    m_elapsedTimer.stop();

    if (!m_stopping && m_encoder.state() != QProcess::NotRunning) {
        m_stopping = true;
        m_encoder.closeWriteChannel();
        m_encoder.terminate();
        m_encoder.waitForFinished(1000);
    }

    const QString path = m_pendingRecordingPath;
    m_window.clear();
    m_recording = false;
    m_stopping = false;
    m_elapsedSeconds = 0;
    m_pendingRecordingPath.clear();

    emit recordingChanged();
    emit elapsedSecondsChanged();

    if (success) {
        m_lastRecordingPath = path;
        setStatusMessage(QStringLiteral("Recording saved"));
        emit lastRecordingPathChanged();
        emit recordingStopped(path);
        publishNotification(
            QStringLiteral("Screen Recording Saved"),
            QFileInfo(path).fileName(),
            QStringLiteral("success"),
            QStringLiteral("open-gallery"),
            path,
            QStringLiteral("recording")
        );
        return;
    }

    if (!path.isEmpty())
        QFile::remove(path);
    const QString message = errorMessage.isEmpty()
        ? QStringLiteral("Screen recording failed.")
        : errorMessage;
    setStatusMessage(message);
    emit captureError(message);
    publishNotification(
        QStringLiteral("Screen Recording Failed"),
        message,
        QStringLiteral("warning"),
        QString(),
        QString(),
        QStringLiteral("recording")
    );
}
