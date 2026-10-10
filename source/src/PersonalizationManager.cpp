#include "PersonalizationManager.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>

namespace {
const QStringList kCards = {
    QStringLiteral("cpu"),
    QStringLiteral("memory"),
    QStringLiteral("storage"),
    QStringLiteral("active"),
    QStringLiteral("temperature"),
    QStringLiteral("network"),
    QStringLiteral("uptime"),
    QStringLiteral("clock"),
    QStringLiteral("user")
};
}

PersonalizationManager::PersonalizationManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent)
    , m_stateRoot(QDir(neutronRoot).filePath(QStringLiteral("state/personalization")))
    , m_systemOverviewLayout(defaultLayout())
{
    QDir().mkpath(m_stateRoot);
    load();
}

QString PersonalizationManager::activeUser() const { return m_activeUser; }
bool PersonalizationManager::systemOverviewEnabled() const { return m_systemOverviewEnabled; }
QVariantList PersonalizationManager::systemOverviewLayout() const { return m_systemOverviewLayout; }
bool PersonalizationManager::systemOverviewCustomized() const { return !m_systemOverviewEnabled || m_systemOverviewLayout != defaultLayout(); }
QString PersonalizationManager::launcherMode() const { return m_launcherMode; }
int PersonalizationManager::gridCardSize() const { return m_gridCardSize; }
int PersonalizationManager::gridSpacing() const { return m_gridSpacing; }

QVariantList PersonalizationManager::availableSystemCards() const
{
    QVariantList result;
    for (const QString &id : kCards) {
        QVariantMap item;
        item.insert(QStringLiteral("id"), id);
        QString title = id;
        if (title == QStringLiteral("active"))
            title = QStringLiteral("Active Apps");
        else {
            title[0] = title.at(0).toUpper();
        }
        item.insert(QStringLiteral("title"), title);
        result.append(item);
    }
    return result;
}

QString PersonalizationManager::normalizedUser(const QString &username) const
{
    QString value = username.trimmed().toLower();
    value.replace(QRegularExpression(QStringLiteral("[^a-z0-9._-]+")), QStringLiteral("_"));
    while (value.startsWith(QLatin1Char('.')))
        value.remove(0, 1);
    return value.isEmpty() ? QStringLiteral("default") : value.left(64);
}

QString PersonalizationManager::statePath() const
{
    return QDir(m_stateRoot).filePath(m_activeUser + QStringLiteral(".json"));
}

QVariantList PersonalizationManager::defaultLayout()
{
    QVariantList result;
    for (const QString &id : kCards)
        result.append(id);
    return result;
}

QVariantList PersonalizationManager::normalizedLayout(const QVariantList &layout) const
{
    QVariantList result;
    QSet<QString> seen;
    for (const QVariant &entry : layout) {
        const QString id = entry.toString().trimmed().toLower();
        if (!kCards.contains(id) || seen.contains(id))
            continue;
        seen.insert(id);
        result.append(id);
    }
    return result;
}

void PersonalizationManager::setActiveUser(const QString &username)
{
    const QString clean = normalizedUser(username);
    if (clean == m_activeUser)
        return;
    m_activeUser = clean;
    load();
    emit settingsChanged();
}

bool PersonalizationManager::applySystemOverview(const QVariantList &layout, bool enabled)
{
    const QVariantList clean = normalizedLayout(layout);
    const bool changed = clean != m_systemOverviewLayout || enabled != m_systemOverviewEnabled;
    if (!changed)
        return true;
    m_systemOverviewLayout = clean;
    m_systemOverviewEnabled = enabled;
    if (!save()) {
        emit saveFailed(QStringLiteral("Unable to save System Overview layout."));
        load();
        return false;
    }
    emit settingsChanged();
    return true;
}

bool PersonalizationManager::resetSystemOverview()
{
    return applySystemOverview(defaultLayout(), true);
}

bool PersonalizationManager::applyLauncher(const QString &mode, int cardSize, int spacing)
{
    const QString cleanMode = mode.trimmed().toLower() == QStringLiteral("grid")
        ? QStringLiteral("grid") : QStringLiteral("carousel");
    const int cleanSize = qBound(70, cardSize, 140);
    const int cleanSpacing = qBound(70, spacing, 140);
    if (cleanMode == m_launcherMode && cleanSize == m_gridCardSize && cleanSpacing == m_gridSpacing)
        return true;
    m_launcherMode = cleanMode;
    m_gridCardSize = cleanSize;
    m_gridSpacing = cleanSpacing;
    if (!save()) {
        emit saveFailed(QStringLiteral("Unable to save launcher preference."));
        load();
        return false;
    }
    emit settingsChanged();
    return true;
}

bool PersonalizationManager::resetLauncher()
{
    return applyLauncher(QStringLiteral("carousel"), 100, 100);
}

QVariantMap PersonalizationManager::snapshot() const
{
    QVariantMap result;
    result.insert(QStringLiteral("user"), m_activeUser);
    result.insert(QStringLiteral("systemOverviewEnabled"), m_systemOverviewEnabled);
    result.insert(QStringLiteral("systemOverviewLayout"), m_systemOverviewLayout);
    result.insert(QStringLiteral("launcherMode"), m_launcherMode);
    result.insert(QStringLiteral("gridCardSize"), m_gridCardSize);
    result.insert(QStringLiteral("gridSpacing"), m_gridSpacing);
    return result;
}

void PersonalizationManager::load()
{
    m_systemOverviewEnabled = true;
    m_systemOverviewLayout = defaultLayout();
    m_launcherMode = QStringLiteral("carousel");
    m_gridCardSize = 100;
    m_gridSpacing = 100;

    QFile file(statePath());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return;
    const QJsonObject object = document.object();
    m_systemOverviewEnabled = object.value(QStringLiteral("systemOverviewEnabled")).toBool(true);
    m_launcherMode = object.value(QStringLiteral("launcherMode")).toString(QStringLiteral("carousel"));
    if (m_launcherMode != QStringLiteral("grid"))
        m_launcherMode = QStringLiteral("carousel");
    m_gridCardSize = qBound(70, object.value(QStringLiteral("gridCardSize")).toInt(100), 140);
    m_gridSpacing = qBound(70, object.value(QStringLiteral("gridSpacing")).toInt(100), 140);
    if (object.contains(QStringLiteral("systemOverviewLayout"))) {
        QVariantList loaded;
        for (const QJsonValue &value : object.value(QStringLiteral("systemOverviewLayout")).toArray())
            loaded.append(value.toString());
        m_systemOverviewLayout = normalizedLayout(loaded);
    } else {
        m_systemOverviewLayout = defaultLayout();
    }
}

bool PersonalizationManager::save()
{
    QJsonObject object;
    object.insert(QStringLiteral("version"), 1);
    object.insert(QStringLiteral("systemOverviewEnabled"), m_systemOverviewEnabled);
    object.insert(QStringLiteral("launcherMode"), m_launcherMode);
    object.insert(QStringLiteral("gridCardSize"), m_gridCardSize);
    object.insert(QStringLiteral("gridSpacing"), m_gridSpacing);
    QJsonArray layout;
    for (const QVariant &value : m_systemOverviewLayout)
        layout.append(value.toString());
    object.insert(QStringLiteral("systemOverviewLayout"), layout);

    QDir().mkpath(m_stateRoot);
    QSaveFile file(statePath());
    if (!file.open(QIODevice::WriteOnly))
        return false;
    const QByteArray data = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(data) != data.size()) {
        file.cancelWriting();
        return false;
    }
    return file.commit();
}
