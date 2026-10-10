#pragma once

#include <QObject>
#include <QVariantList>
#include <QFileSystemWatcher>

class ScreensaverManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList assets
               READ assets
               NOTIFY assetsChanged)

    Q_PROPERTY(int assetCount
               READ assetCount
               NOTIFY assetsChanged)

    Q_PROPERTY(int timeoutMinutes
               READ timeoutMinutes
               WRITE setTimeoutMinutes
               NOTIFY timeoutMinutesChanged)

    Q_PROPERTY(bool enabled
               READ enabled
               NOTIFY timeoutMinutesChanged)

    Q_PROPERTY(bool active
               READ active
               NOTIFY activeChanged)

    Q_PROPERTY(QString directoryPath
               READ directoryPath
               CONSTANT)

    Q_PROPERTY(int revision
               READ revision
               NOTIFY assetsChanged)

    Q_PROPERTY(QString contentMode
               READ contentMode
               NOTIFY settingsChanged)

    Q_PROPERTY(QString animationId
               READ animationId
               NOTIFY settingsChanged)

    Q_PROPERTY(int animationSpeed
               READ animationSpeed
               NOTIFY settingsChanged)

    Q_PROPERTY(int animationIntensity
               READ animationIntensity
               NOTIFY settingsChanged)

    Q_PROPERTY(bool randomRotation
               READ randomRotation
               NOTIFY settingsChanged)

    Q_PROPERTY(QVariantList availableAnimations
               READ availableAnimations
               CONSTANT)

public:
    explicit ScreensaverManager(
        const QString &directoryPath,
        const QString &stateDirectory,
        QObject *parent = nullptr
    );

    QVariantList assets() const;
    int assetCount() const;

    int timeoutMinutes() const;
    void setTimeoutMinutes(int minutes);
    bool enabled() const;

    bool active() const;
    QString directoryPath() const;
    int revision() const;
    QString contentMode() const;
    QString animationId() const;
    int animationSpeed() const;
    int animationIntensity() const;
    bool randomRotation() const;
    QVariantList availableAnimations() const;

    Q_INVOKABLE bool applyTimeoutMinutes(int minutes);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void rescan();
    Q_INVOKABLE void activate();
    Q_INVOKABLE void deactivate();
    Q_INVOKABLE bool isSupportedTimeout(int minutes) const;
    Q_INVOKABLE bool applyPresentation(const QString &contentMode,
                                       const QString &animationId,
                                       int speed,
                                       int intensity,
                                       bool randomRotation);

signals:
    void assetsChanged();
    void timeoutMinutesChanged();
    void activeChanged();
    void settingsSaveFailed(const QString &message);
    void settingsChanged();

private:
    void ensureDirectories();
    void loadSettings();
    bool saveSettings();
    QVariantList scanAssets() const;
    static QString normalizedAssetName(const QString &fileName);

    QString m_directoryPath;
    QString m_stateDirectory;
    QString m_settingsPath;

    QVariantList m_assets;
    int m_timeoutMinutes = 5;
    bool m_active = false;
    int m_revision = 0;
    QString m_contentMode = QStringLiteral("pictures");
    QString m_animationId = QStringLiteral("starfield");
    int m_animationSpeed = 100;
    int m_animationIntensity = 100;
    bool m_randomRotation = false;

    QFileSystemWatcher m_watcher;
};
