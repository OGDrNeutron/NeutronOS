#include "ScreensaverManager.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QUrl>

namespace {
constexpr int DefaultTimeoutMinutes = 5;
const QStringList kAnimations = {
    QStringLiteral("pipes"),
    QStringLiteral("dvd"),
    QStringLiteral("atom"),
    QStringLiteral("starfield"),
    QStringLiteral("plasma"),
    QStringLiteral("tunnel")
};

bool supportedTimeout(int minutes)
{
    return minutes == 0 ||
           minutes == 3 ||
           minutes == 5 ||
           minutes == 10 ||
           minutes == 15 ||
           minutes == 30;
}
}

ScreensaverManager::ScreensaverManager(
    const QString &directoryPath,
    const QString &stateDirectory,
    QObject *parent
)
    : QObject(parent)
    , m_directoryPath(QDir::cleanPath(directoryPath))
    , m_stateDirectory(QDir::cleanPath(stateDirectory))
    , m_settingsPath(
          QDir(m_stateDirectory).filePath(
              QStringLiteral("screensaver.json")
          )
      )
{
    ensureDirectories();
    loadSettings();
    rescan();

    if (QFileInfo::exists(m_directoryPath))
        m_watcher.addPath(m_directoryPath);

    connect(
        &m_watcher,
        &QFileSystemWatcher::directoryChanged,
        this,
        [this](const QString &) {
            rescan();

            if (!m_watcher.directories().contains(m_directoryPath) &&
                    QFileInfo::exists(m_directoryPath)) {
                m_watcher.addPath(m_directoryPath);
            }
        }
    );
}

QVariantList ScreensaverManager::assets() const
{
    return m_assets;
}

int ScreensaverManager::assetCount() const
{
    return m_assets.size();
}

int ScreensaverManager::timeoutMinutes() const
{
    return m_timeoutMinutes;
}

void ScreensaverManager::setTimeoutMinutes(int minutes)
{
    applyTimeoutMinutes(minutes);
}

bool ScreensaverManager::applyTimeoutMinutes(int minutes)
{
    if (!supportedTimeout(minutes))
        return false;

    if (m_timeoutMinutes == minutes)
        return true;

    const int previous = m_timeoutMinutes;
    m_timeoutMinutes = minutes;

    if (!saveSettings()) {
        m_timeoutMinutes = previous;
        emit settingsSaveFailed(
            QStringLiteral("Unable to save screensaver timeout")
        );
        return false;
    }

    emit timeoutMinutesChanged();
    return true;
}

bool ScreensaverManager::enabled() const
{
    return m_timeoutMinutes > 0;
}

bool ScreensaverManager::active() const
{
    return m_active;
}

QString ScreensaverManager::directoryPath() const
{
    return m_directoryPath;
}

int ScreensaverManager::revision() const
{
    return m_revision;
}

QString ScreensaverManager::contentMode() const { return m_contentMode; }
QString ScreensaverManager::animationId() const { return m_animationId; }
int ScreensaverManager::animationSpeed() const { return m_animationSpeed; }
int ScreensaverManager::animationIntensity() const { return m_animationIntensity; }
bool ScreensaverManager::randomRotation() const { return m_randomRotation; }

QVariantList ScreensaverManager::availableAnimations() const
{
    QVariantList result;
    const QVariantList labels = {
        QVariantMap{{QStringLiteral("id"), QStringLiteral("pipes")}, {QStringLiteral("name"), QStringLiteral("Classic Pipes")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("dvd")}, {QStringLiteral("name"), QStringLiteral("NeutronOS DVD Bounce")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("atom")}, {QStringLiteral("name"), QStringLiteral("Atom Field")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("starfield")}, {QStringLiteral("name"), QStringLiteral("Starfield")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("plasma")}, {QStringLiteral("name"), QStringLiteral("Plasma")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("tunnel")}, {QStringLiteral("name"), QStringLiteral("Particle Tunnel")}}
    };
    return labels;
}

bool ScreensaverManager::applyPresentation(const QString &contentMode,
                                             const QString &animationId,
                                             int speed,
                                             int intensity,
                                             bool randomRotation)
{
    const QString cleanMode = contentMode.trimmed().toLower() == QStringLiteral("animations")
        ? QStringLiteral("animations") : QStringLiteral("pictures");
    QString cleanAnimation = animationId.trimmed().toLower();
    if (!kAnimations.contains(cleanAnimation))
        cleanAnimation = QStringLiteral("starfield");
    const int cleanSpeed = qBound(40, speed, 180);
    const int cleanIntensity = qBound(30, intensity, 160);
    if (cleanMode == m_contentMode && cleanAnimation == m_animationId &&
            cleanSpeed == m_animationSpeed && cleanIntensity == m_animationIntensity &&
            randomRotation == m_randomRotation)
        return true;
    const QString oldMode = m_contentMode;
    const QString oldAnimation = m_animationId;
    const int oldSpeed = m_animationSpeed;
    const int oldIntensity = m_animationIntensity;
    const bool oldRandom = m_randomRotation;
    m_contentMode = cleanMode;
    m_animationId = cleanAnimation;
    m_animationSpeed = cleanSpeed;
    m_animationIntensity = cleanIntensity;
    m_randomRotation = randomRotation;
    if (!saveSettings()) {
        m_contentMode = oldMode;
        m_animationId = oldAnimation;
        m_animationSpeed = oldSpeed;
        m_animationIntensity = oldIntensity;
        m_randomRotation = oldRandom;
        emit settingsSaveFailed(QStringLiteral("Unable to save screensaver presentation."));
        return false;
    }
    emit settingsChanged();
    return true;
}

void ScreensaverManager::refresh()
{
    const int previousTimeout = m_timeoutMinutes;
    const QString previousMode = m_contentMode;
    const QString previousAnimation = m_animationId;
    const int previousSpeed = m_animationSpeed;
    const int previousIntensity = m_animationIntensity;
    const bool previousRandom = m_randomRotation;
    loadSettings();

    if (m_timeoutMinutes != previousTimeout)
        emit timeoutMinutesChanged();
    if (m_contentMode != previousMode || m_animationId != previousAnimation ||
            m_animationSpeed != previousSpeed || m_animationIntensity != previousIntensity ||
            m_randomRotation != previousRandom)
        emit settingsChanged();

    rescan();
}

void ScreensaverManager::rescan()
{
    const QVariantList updated = scanAssets();

    if (updated == m_assets)
        return;

    m_assets = updated;
    ++m_revision;
    emit assetsChanged();
}

void ScreensaverManager::activate()
{
    if (m_active)
        return;

    rescan();
    m_active = true;
    emit activeChanged();
}

void ScreensaverManager::deactivate()
{
    if (!m_active)
        return;

    m_active = false;
    emit activeChanged();
}

bool ScreensaverManager::isSupportedTimeout(int minutes) const
{
    return supportedTimeout(minutes);
}

void ScreensaverManager::ensureDirectories()
{
    QDir().mkpath(m_directoryPath);
    QDir().mkpath(m_stateDirectory);
}

void ScreensaverManager::loadSettings()
{
    QFile file(m_settingsPath);

    if (!file.open(QIODevice::ReadOnly)) {
        m_timeoutMinutes = DefaultTimeoutMinutes;
        m_contentMode = QStringLiteral("pictures");
        m_animationId = QStringLiteral("starfield");
        m_animationSpeed = 100;
        m_animationIntensity = 100;
        m_randomRotation = false;
        return;
    }

    const QJsonDocument document =
        QJsonDocument::fromJson(file.readAll());

    file.close();

    if (!document.isObject()) {
        m_timeoutMinutes = DefaultTimeoutMinutes;
        m_contentMode = QStringLiteral("pictures");
        m_animationId = QStringLiteral("starfield");
        m_animationSpeed = 100;
        m_animationIntensity = 100;
        m_randomRotation = false;
        return;
    }

    const QJsonObject object = document.object();
    const int loaded = object.value(QStringLiteral("timeoutMinutes")).toInt(DefaultTimeoutMinutes);
    m_timeoutMinutes = supportedTimeout(loaded) ? loaded : DefaultTimeoutMinutes;
    m_contentMode = object.value(QStringLiteral("contentMode")).toString(QStringLiteral("pictures"));
    if (m_contentMode != QStringLiteral("animations"))
        m_contentMode = QStringLiteral("pictures");
    m_animationId = object.value(QStringLiteral("animationId")).toString(QStringLiteral("starfield"));
    if (!kAnimations.contains(m_animationId))
        m_animationId = QStringLiteral("starfield");
    m_animationSpeed = qBound(40, object.value(QStringLiteral("animationSpeed")).toInt(100), 180);
    m_animationIntensity = qBound(30, object.value(QStringLiteral("animationIntensity")).toInt(100), 160);
    m_randomRotation = object.value(QStringLiteral("randomRotation")).toBool(false);
}

bool ScreensaverManager::saveSettings()
{
    QJsonObject object;
    object.insert(QStringLiteral("timeoutMinutes"), m_timeoutMinutes);
    object.insert(QStringLiteral("contentMode"), m_contentMode);
    object.insert(QStringLiteral("animationId"), m_animationId);
    object.insert(QStringLiteral("animationSpeed"), m_animationSpeed);
    object.insert(QStringLiteral("animationIntensity"), m_animationIntensity);
    object.insert(QStringLiteral("randomRotation"), m_randomRotation);

    QSaveFile file(m_settingsPath);

    if (!file.open(QIODevice::WriteOnly))
        return false;

    const QByteArray encoded =
        QJsonDocument(object).toJson(QJsonDocument::Indented);

    if (file.write(encoded) != encoded.size()) {
        file.cancelWriting();
        return false;
    }

    return file.commit();
}

QVariantList ScreensaverManager::scanAssets() const
{
    QDir directory(m_directoryPath);

    const QStringList filters = {
        QStringLiteral("*.png"),
        QStringLiteral("*.jpg"),
        QStringLiteral("*.jpeg"),
        QStringLiteral("*.webp")
    };

    const QFileInfoList files = directory.entryInfoList(
        filters,
        QDir::Files | QDir::Readable | QDir::NoSymLinks,
        QDir::Name | QDir::IgnoreCase
    );

    QVariantList result;
    result.reserve(files.size());

    for (const QFileInfo &file : files) {
        QVariantMap item;
        item.insert(
            QStringLiteral("id"),
            file.completeBaseName().toLower()
        );
        item.insert(
            QStringLiteral("name"),
            normalizedAssetName(file.completeBaseName())
        );
        item.insert(
            QStringLiteral("path"),
            file.absoluteFilePath()
        );
        item.insert(
            QStringLiteral("url"),
            QUrl::fromLocalFile(file.absoluteFilePath())
        );
        result.append(item);
    }

    return result;
}

QString ScreensaverManager::normalizedAssetName(const QString &fileName)
{
    QString value = fileName;
    value.replace(QLatin1Char('_'), QLatin1Char(' '));
    value.replace(QLatin1Char('-'), QLatin1Char(' '));

    const QStringList words =
        value.split(QLatin1Char(' '), Qt::SkipEmptyParts);

    QStringList normalized;
    normalized.reserve(words.size());

    for (QString word : words) {
        if (!word.isEmpty())
            word[0] = word.at(0).toUpper();

        normalized.append(word);
    }

    return normalized.join(QLatin1Char(' '));
}
