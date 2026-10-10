#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QSize>
#include <QString>
#include <QTimer>

class NotificationManager;
class QQuickWindow;

class CaptureManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    Q_PROPERTY(int elapsedSeconds READ elapsedSeconds NOTIFY elapsedSecondsChanged)
    Q_PROPERTY(QString lastScreenshotPath READ lastScreenshotPath NOTIFY lastScreenshotPathChanged)
    Q_PROPERTY(QString lastRecordingPath READ lastRecordingPath NOTIFY lastRecordingPathChanged)
    Q_PROPERTY(QString screenshotsPath READ screenshotsPath CONSTANT)
    Q_PROPERTY(QString recordingsPath READ recordingsPath CONSTANT)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(bool showIndicator READ showIndicator WRITE setShowIndicator NOTIFY showIndicatorChanged)
    Q_PROPERTY(int frameRate READ frameRate WRITE setFrameRate NOTIFY frameRateChanged)
    Q_PROPERTY(QString resolution READ resolution WRITE setResolution NOTIFY resolutionChanged)

public:
    explicit CaptureManager(const QString &neutronRoot,
                            NotificationManager *notificationManager,
                            QObject *parent = nullptr);
    ~CaptureManager() override;

    bool recording() const;
    int elapsedSeconds() const;
    QString lastScreenshotPath() const;
    QString lastRecordingPath() const;
    QString screenshotsPath() const;
    QString recordingsPath() const;
    QString statusMessage() const;
    bool showIndicator() const;
    int frameRate() const;
    QString resolution() const;

    void setShowIndicator(bool show);
    void setFrameRate(int framesPerSecond);
    void setResolution(const QString &resolution);

    Q_INVOKABLE bool captureScreenshot(QObject *windowObject);
    Q_INVOKABLE bool startRecording(QObject *windowObject);
    Q_INVOKABLE bool stopRecording();
    Q_INVOKABLE bool toggleRecording(QObject *windowObject);
    Q_INVOKABLE void reloadSettings();

signals:
    void recordingChanged();
    void elapsedSecondsChanged();
    void lastScreenshotPathChanged();
    void lastRecordingPathChanged();
    void statusMessageChanged();
    void showIndicatorChanged();
    void frameRateChanged();
    void resolutionChanged();

    void screenshotSaved(const QString &path);
    void recordingStarted(const QString &path);
    void recordingStopped(const QString &path);
    void captureError(const QString &message);

private slots:
    void captureNextFrame();
    void updateElapsedTime();
    void handleEncoderError(QProcess::ProcessError error);
    void handleEncoderFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    QString m_neutronRoot;
    QString m_userHome;
    QString m_stateDirectory;
    QString m_settingsPath;
    QString m_screenshotsPath;
    QString m_recordingsPath;
    NotificationManager *m_notificationManager = nullptr;

    QPointer<QQuickWindow> m_window;
    QProcess m_encoder;
    QTimer m_frameTimer;
    QTimer m_elapsedTimer;
    QSize m_targetSize;

    bool m_recording = false;
    bool m_stopping = false;
    int m_elapsedSeconds = 0;
    int m_frameRate = 30;
    QString m_resolution = QStringLiteral("720p");
    bool m_showIndicator = true;
    QString m_lastScreenshotPath;
    QString m_lastRecordingPath;
    QString m_pendingRecordingPath;
    QString m_statusMessage;

    static QString canonicalUserHome(const QString &neutronRoot);
    static QString timestampToken();
    static QSize sizeForResolution(const QString &resolution,
                                   const QSize &windowSize);

    QQuickWindow *resolveWindow(QObject *windowObject) const;
    bool ensureDirectories();
    bool loadSettings();
    bool saveSettings() const;
    void setStatusMessage(const QString &message);
    void publishNotification(const QString &title,
                             const QString &message,
                             const QString &priority,
                             const QString &action,
                             const QString &path,
                             const QString &mediaType);
    void finishRecording(bool success, const QString &errorMessage = QString());
};
