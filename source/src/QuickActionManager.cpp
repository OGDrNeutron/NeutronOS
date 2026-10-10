#include "QuickActionManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>
#include <QDebug>

#include <algorithm>

namespace {
QString canonicalRoot(const QString &value)
{
    return QDir::cleanPath(value);
}

bool rootLooksValid(const QString &root)
{
    return QFileInfo::exists(QDir(root).filePath(QStringLiteral("qml/Main.qml")));
}
}

QuickActionManager::QuickActionManager(QObject *parent)
    : QObject(parent)
{
    resolveRuntimePaths();
    reloadActions();
}

QVariantList QuickActionManager::actions() const { return m_actions; }
QVariantList QuickActionManager::dockActions() const { return m_dockActions; }
int QuickActionManager::actionCount() const { return m_actions.size(); }
int QuickActionManager::dockSlotCount() const { return m_dockActionIds.size(); }
bool QuickActionManager::busy() const { return m_busy; }
QString QuickActionManager::lastMessage() const { return m_lastMessage; }
QString QuickActionManager::neutronRootPath() const { return m_neutronRootPath; }
QString QuickActionManager::appsRootPath() const { return m_appsRootPath; }
QString QuickActionManager::configRootPath() const { return m_configRootPath; }

void QuickActionManager::reloadActions()
{
    resolveRuntimePaths();
    m_actions.clear();
    m_seenActionIds.clear();

    discoverActions();

    std::sort(m_actions.begin(), m_actions.end(), [](const QVariant &left, const QVariant &right) {
        const QVariantMap a = left.toMap();
        const QVariantMap b = right.toMap();
        const int pa = a.value(QStringLiteral("priority"), 9999).toInt();
        const int pb = b.value(QStringLiteral("priority"), 9999).toInt();
        if (pa != pb)
            return pa < pb;
        return a.value(QStringLiteral("name")).toString().compare(
                   b.value(QStringLiteral("name")).toString(), Qt::CaseInsensitive) < 0;
    });

    loadDockState();
    normalizeDockAssignments();
    if (m_dockStateNeedsSave) {
        if (saveDockState())
            m_dockStateNeedsSave = false;
    }
    rebuildDockActions();

    emit actionsChanged();
    emit dockActionsChanged();
}

void QuickActionManager::refreshActions() { reloadActions(); }
void QuickActionManager::rediscoverActions() { reloadActions(); }

QVariantMap QuickActionManager::actionById(const QString &actionId) const
{
    const QString id = safeId(actionId);
    for (const QVariant &value : m_actions) {
        const QVariantMap action = value.toMap();
        if (action.value(QStringLiteral("id")).toString() == id)
            return action;
    }
    return {};
}

QVariantMap QuickActionManager::actionAt(int index) const
{
    if (index < 0 || index >= m_actions.size())
        return {};
    return m_actions.at(index).toMap();
}

QVariantMap QuickActionManager::dockActionAt(int slot) const
{
    if (slot < 0 || slot >= m_dockActions.size())
        return {};
    return m_dockActions.at(slot).toMap();
}

bool QuickActionManager::hasAction(const QString &actionId) const
{
    return !actionById(actionId).isEmpty();
}

QStringList QuickActionManager::dockActionIds() const
{
    return m_dockActionIds;
}

bool QuickActionManager::setDockAction(int slot, const QString &actionId)
{
    if (slot < 0 || slot >= m_dockActionIds.size())
        return false;

    const QString id = safeId(actionId);
    if (actionById(id).isEmpty())
        return false;

    const int existing = m_dockActionIds.indexOf(id);
    if (existing >= 0 && existing != slot)
        m_dockActionIds[existing] = m_dockActionIds.at(slot);

    m_dockActionIds[slot] = id;
    normalizeDockAssignments();

    if (!saveDockState()) {
        setLastMessage(QStringLiteral("Unable to save Quick Actions layout"));
        return false;
    }

    rebuildDockActions();
    emit dockActionsChanged();
    setLastMessage(QStringLiteral("Quick Action slot updated"));
    return true;
}

bool QuickActionManager::appendDockAction(const QString &actionId)
{
    const QString id = safeId(actionId);
    if (actionById(id).isEmpty() || m_dockActionIds.contains(id))
        return false;

    m_dockActionIds.append(id);
    normalizeDockAssignments();

    if (!saveDockState()) {
        m_dockActionIds.removeAll(id);
        setLastMessage(QStringLiteral("Unable to add Quick Action"));
        return false;
    }

    rebuildDockActions();
    emit dockActionsChanged();
    setLastMessage(QStringLiteral("Quick Action added"));
    return true;
}

bool QuickActionManager::removeDockAction(int slot)
{
    if (m_dockActionIds.size() <= 1 || slot < 0 || slot >= m_dockActionIds.size())
        return false;

    const QString removed = m_dockActionIds.takeAt(slot);
    if (!saveDockState()) {
        m_dockActionIds.insert(slot, removed);
        setLastMessage(QStringLiteral("Unable to remove Quick Action"));
        return false;
    }

    rebuildDockActions();
    emit dockActionsChanged();
    setLastMessage(QStringLiteral("Quick Action removed"));
    return true;
}

bool QuickActionManager::moveDockAction(int fromSlot, int toSlot)
{
    if (fromSlot < 0 || fromSlot >= m_dockActionIds.size() ||
            toSlot < 0 || toSlot >= m_dockActionIds.size()) {
        return false;
    }

    if (fromSlot == toSlot)
        return true;

    m_dockActionIds.move(fromSlot, toSlot);
    if (!saveDockState()) {
        m_dockActionIds.move(toSlot, fromSlot);
        setLastMessage(QStringLiteral("Unable to reorder Quick Actions"));
        return false;
    }

    rebuildDockActions();
    emit dockActionsChanged();
    setLastMessage(QStringLiteral("Quick Actions reordered"));
    return true;
}

bool QuickActionManager::resetDockActions()
{
    m_dockActionIds = defaultDockActionIds();
    normalizeDockAssignments();

    if (!saveDockState()) {
        setLastMessage(QStringLiteral("Unable to reset Quick Actions layout"));
        return false;
    }

    rebuildDockActions();
    emit dockActionsChanged();
    setLastMessage(QStringLiteral("Quick Actions restored"));
    return true;
}

bool QuickActionManager::executeAction(const QVariantMap &actionData)
{
    const QVariantMap action = normalizeAction(actionData);
    const QString id = action.value(QStringLiteral("id")).toString();

    if (id.isEmpty()) {
        setLastMessage(QStringLiteral("Quick action blocked: missing id"));
        emit actionFinished(id, false, m_lastMessage);
        return false;
    }

    if (isLaunchAction(action)) {
        emit actionLaunchRequested(action);
        setLastMessage(QStringLiteral("Opening ") + action.value(QStringLiteral("name"), id).toString());
        emit actionFinished(id, true, m_lastMessage);
        return true;
    }

    const QString type = normalizedType(action.value(QStringLiteral("type")).toString());
    if (type == QStringLiteral("service") || type == QStringLiteral("service-action"))
        return executeServiceAction(action);
    if (type == QStringLiteral("script"))
        return executeScriptAction(action);
    return executeSystemAction(action);
}

bool QuickActionManager::runAction(const QVariantMap &actionData) { return executeAction(actionData); }
bool QuickActionManager::triggerAction(const QVariantMap &actionData) { return executeAction(actionData); }

bool QuickActionManager::executeActionById(const QString &actionId)
{
    const QVariantMap action = actionById(actionId);
    if (action.isEmpty()) {
        const QString id = safeId(actionId);
        setLastMessage(QStringLiteral("Quick action not found: ") + id);
        emit actionFinished(id, false, m_lastMessage);
        return false;
    }
    return executeAction(action);
}

bool QuickActionManager::isLaunchAction(const QVariantMap &actionData) const
{
    const QVariantMap action = normalizeAction(actionData);
    if (action.value(QStringLiteral("launchApp"), false).toBool())
        return true;

    const QString type = normalizedType(action.value(QStringLiteral("type")).toString());
    return type == QStringLiteral("qml") ||
           type == QStringLiteral("web") ||
           type == QStringLiteral("service-web") ||
           type == QStringLiteral("command") ||
           type == QStringLiteral("external") ||
           type == QStringLiteral("app");
}

bool QuickActionManager::isDangerAction(const QVariantMap &actionData) const
{
    const QVariantMap action = normalizeAction(actionData);
    if (action.value(QStringLiteral("danger"), false).toBool() ||
            action.value(QStringLiteral("destructive"), false).toBool())
        return true;

    const QString combined = (
        action.value(QStringLiteral("id")).toString() + QLatin1Char(' ') +
        action.value(QStringLiteral("backendAction")).toString() + QLatin1Char(' ') +
        action.value(QStringLiteral("name")).toString()
    ).toLower();

    return combined.contains(QStringLiteral("shutdown")) ||
           combined.contains(QStringLiteral("poweroff")) ||
           combined.contains(QStringLiteral("reboot")) ||
           combined.contains(QStringLiteral("kill"));
}

bool QuickActionManager::requiresConfirmation(const QVariantMap &actionData) const
{
    const QVariantMap action = normalizeAction(actionData);
    return action.value(QStringLiteral("confirmRequired"), false).toBool() ||
           isDangerAction(action);
}

void QuickActionManager::discoverActions()
{
    discoverBuiltInActions();
    discoverDropInAppActions();
    discoverServiceActions();
    discoverScriptActions();
    discoverConfigActions();
}

void QuickActionManager::discoverBuiltInActions()
{
    addAction({
        {QStringLiteral("id"), QStringLiteral("shutdown")},
        {QStringLiteral("name"), QStringLiteral("Shutdown")},
        {QStringLiteral("subtitle"), QStringLiteral("Power off the Pi")},
        {QStringLiteral("icon"), QStringLiteral("shutdown")},
        {QStringLiteral("type"), QStringLiteral("system-action")},
        {QStringLiteral("backendAction"), QStringLiteral("shutdown")},
        {QStringLiteral("danger"), true},
        {QStringLiteral("confirmRequired"), true},
        {QStringLiteral("priority"), 10}
    });

    addAction({
        {QStringLiteral("id"), QStringLiteral("restart")},
        {QStringLiteral("name"), QStringLiteral("Restart")},
        {QStringLiteral("subtitle"), QStringLiteral("Restart NeutronOS shell")},
        {QStringLiteral("icon"), QStringLiteral("restart")},
        {QStringLiteral("type"), QStringLiteral("system-action")},
        {QStringLiteral("backendAction"), QStringLiteral("restart-shell")},
        {QStringLiteral("confirmRequired"), true},
        {QStringLiteral("priority"), 20}
    });

    addAction({
        {QStringLiteral("id"), QStringLiteral("reboot")},
        {QStringLiteral("name"), QStringLiteral("Reboot")},
        {QStringLiteral("subtitle"), QStringLiteral("Reboot the Pi")},
        {QStringLiteral("icon"), QStringLiteral("reboot")},
        {QStringLiteral("type"), QStringLiteral("system-action")},
        {QStringLiteral("backendAction"), QStringLiteral("reboot")},
        {QStringLiteral("danger"), true},
        {QStringLiteral("confirmRequired"), true},
        {QStringLiteral("priority"), 30}
    });

    addAction({
        {QStringLiteral("id"), QStringLiteral("controller-off")},
        {QStringLiteral("name"), QStringLiteral("Controller Off")},
        {QStringLiteral("subtitle"), QStringLiteral("Disconnect the active controller")},
        {QStringLiteral("icon"), QStringLiteral("controller-off")},
        {QStringLiteral("type"), QStringLiteral("system-action")},
        {QStringLiteral("backendAction"), QStringLiteral("controller-off")},
        {QStringLiteral("confirmRequired"), true},
        {QStringLiteral("priority"), 40}
    });

    addAction({
        {QStringLiteral("id"), QStringLiteral("screensaver")},
        {QStringLiteral("name"), QStringLiteral("Screensaver")},
        {QStringLiteral("subtitle"), QStringLiteral("Start the screensaver")},
        {QStringLiteral("icon"), QStringLiteral("screensaver")},
        {QStringLiteral("type"), QStringLiteral("system-action")},
        {QStringLiteral("backendAction"), QStringLiteral("screensaver")},
        {QStringLiteral("priority"), 50}
    });

    addAction({
        {QStringLiteral("id"), QStringLiteral("help")},
        {QStringLiteral("name"), QStringLiteral("Help")},
        {QStringLiteral("subtitle"), QStringLiteral("Open the NeutronOS Help Center")},
        {QStringLiteral("icon"), QStringLiteral("help.png")},
        {QStringLiteral("type"), QStringLiteral("system-action")},
        {QStringLiteral("backendAction"), QStringLiteral("help")},
        {QStringLiteral("priority"), 55}
    });

    const QList<QVariantMap> appDefaults = {
        {
            {QStringLiteral("id"), QStringLiteral("terminal")},
            {QStringLiteral("name"), QStringLiteral("Terminal")},
            {QStringLiteral("icon"), QStringLiteral("terminal")},
            {QStringLiteral("type"), QStringLiteral("qml")},
            {QStringLiteral("appId"), QStringLiteral("terminal")},
            {QStringLiteral("qmlSource"), appMainQmlSource(QStringLiteral("terminal"))},
            {QStringLiteral("launchApp"), true},
            {QStringLiteral("priority"), 60}
        },
        {
            {QStringLiteral("id"), QStringLiteral("settings")},
            {QStringLiteral("name"), QStringLiteral("Settings")},
            {QStringLiteral("icon"), QStringLiteral("settings")},
            {QStringLiteral("type"), QStringLiteral("qml")},
            {QStringLiteral("appId"), QStringLiteral("settings")},
            {QStringLiteral("qmlSource"), appMainQmlSource(QStringLiteral("settings"))},
            {QStringLiteral("launchApp"), true},
            {QStringLiteral("priority"), 70}
        },
        {
            {QStringLiteral("id"), QStringLiteral("filemanager")},
            {QStringLiteral("name"), QStringLiteral("Files")},
            {QStringLiteral("icon"), QStringLiteral("filemanager")},
            {QStringLiteral("type"), QStringLiteral("qml")},
            {QStringLiteral("appId"), QStringLiteral("filemanager")},
            {QStringLiteral("qmlSource"), appMainQmlSource(QStringLiteral("filemanager"))},
            {QStringLiteral("launchApp"), true},
            {QStringLiteral("priority"), 80}
        }
    };

    for (const QVariantMap &action : appDefaults)
        addAction(action);
}

void QuickActionManager::discoverDropInAppActions()
{
    QDir directory(m_appsRootPath);
    if (!directory.exists())
        return;

    int priority = 200;
    const QFileInfoList entries = directory.entryInfoList(
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::Name | QDir::IgnoreCase
    );

    for (const QFileInfo &entry : entries)
        discoverAppDirectory(entry.absoluteFilePath(), priority++);
}

void QuickActionManager::discoverAppDirectory(const QString &directoryPath, int priority)
{
    const QDir directory(directoryPath);
    const QString id = safeId(directory.dirName());
    const QString mainPath = directory.filePath(QStringLiteral("Main.qml"));
    if (id.isEmpty() || !QFileInfo::exists(mainPath))
        return;

    QVariantMap manifest = readJsonObject(directory.filePath(QStringLiteral("app.json")));
    QVariantMap action;
    action.insert(QStringLiteral("id"), id);
    action.insert(QStringLiteral("appId"), id);
    action.insert(QStringLiteral("name"), manifest.value(QStringLiteral("name"), displayNameFromId(id)));
    action.insert(QStringLiteral("subtitle"), manifest.value(QStringLiteral("subtitle"), QStringLiteral("Open application")));
    action.insert(QStringLiteral("icon"), manifest.value(QStringLiteral("icon"), id));
    action.insert(QStringLiteral("poster"), manifest.value(QStringLiteral("poster"), id));
    action.insert(QStringLiteral("type"), manifest.value(QStringLiteral("type"), QStringLiteral("qml")));
    action.insert(QStringLiteral("qmlSource"), appMainQmlSource(id));
    action.insert(QStringLiteral("entry"), mainPath);
    action.insert(QStringLiteral("source"), QStringLiteral("app"));
    action.insert(QStringLiteral("launchApp"), true);
    action.insert(QStringLiteral("priority"), manifest.value(QStringLiteral("quickActionPriority"), priority));

    for (const QString &key : {QStringLiteral("service"), QStringLiteral("docker"), QStringLiteral("url"), QStringLiteral("command")}) {
        if (manifest.contains(key))
            action.insert(key, manifest.value(key));
    }

    addAction(action);
}

void QuickActionManager::discoverServiceActions()
{
    const QStringList knownUnits = {
        QStringLiteral("docker.service"),
        QStringLiteral("jellyfin.service"),
        QStringLiteral("qbittorrent.service"),
        QStringLiteral("tailscaled.service")
    };

    int priority = 500;
    for (const QString &unit : knownUnits) {
        if (!systemdUnitExists(unit))
            continue;

        const QString base = unit.section(QLatin1Char('.'), 0, 0);
        addAction({
            {QStringLiteral("id"), QStringLiteral("service-") + safeId(base)},
            {QStringLiteral("name"), displayNameFromId(base)},
            {QStringLiteral("subtitle"), QStringLiteral("Start service")},
            {QStringLiteral("icon"), QStringLiteral("service")},
            {QStringLiteral("type"), QStringLiteral("service-action")},
            {QStringLiteral("service"), unit},
            {QStringLiteral("serviceAction"), QStringLiteral("start")},
            {QStringLiteral("priority"), priority++}
        });
    }

    const QStringList containers = {QStringLiteral("jellyfin"), QStringLiteral("qbittorrent"), QStringLiteral("portainer")};
    for (const QString &container : containers) {
        if (!dockerContainerExists(container))
            continue;

        addAction({
            {QStringLiteral("id"), QStringLiteral("service-docker-") + safeId(container)},
            {QStringLiteral("name"), displayNameFromId(container)},
            {QStringLiteral("subtitle"), QStringLiteral("Start container")},
            {QStringLiteral("icon"), QStringLiteral("service")},
            {QStringLiteral("type"), QStringLiteral("service-action")},
            {QStringLiteral("docker"), container},
            {QStringLiteral("serviceAction"), QStringLiteral("start")},
            {QStringLiteral("priority"), priority++}
        });
    }
}

void QuickActionManager::discoverScriptActions()
{
    const QStringList roots = {
        QDir(m_neutronRootPath).filePath(QStringLiteral("scripts")),
        QDir(m_configRootPath).filePath(QStringLiteral("scripts"))
    };

    int priority = 700;
    for (const QString &root : roots) {
        QDir directory(root);
        if (!directory.exists())
            continue;

        const QFileInfoList files = directory.entryInfoList(
            QStringList() << QStringLiteral("*.sh") << QStringLiteral("*.py"),
            QDir::Files | QDir::Readable | QDir::NoSymLinks,
            QDir::Name | QDir::IgnoreCase
        );

        for (const QFileInfo &file : files) {
            const QString id = safeId(file.completeBaseName());
            QVariantMap action;
            action.insert(QStringLiteral("id"), QStringLiteral("script-") + id);
            action.insert(QStringLiteral("name"), displayNameFromId(file.completeBaseName()));
            action.insert(QStringLiteral("subtitle"), QStringLiteral("Run approved script"));
            action.insert(QStringLiteral("icon"), QStringLiteral("script"));
            action.insert(QStringLiteral("type"), QStringLiteral("script"));
            action.insert(QStringLiteral("scriptPath"), file.absoluteFilePath());
            action.insert(QStringLiteral("confirmRequired"), true);
            action.insert(QStringLiteral("priority"), priority++);
            addAction(action);
        }
    }
}

void QuickActionManager::discoverConfigActions()
{
    const QString combined = QDir(m_configRootPath).filePath(QStringLiteral("quickactions.json"));
    discoverConfigFile(combined);

    QDir directory(QDir(m_configRootPath).filePath(QStringLiteral("quickactions")));
    if (!directory.exists())
        return;

    const QFileInfoList files = directory.entryInfoList(
        QStringList() << QStringLiteral("*.json"),
        QDir::Files | QDir::Readable | QDir::NoSymLinks,
        QDir::Name | QDir::IgnoreCase
    );

    for (const QFileInfo &file : files)
        discoverConfigFile(file.absoluteFilePath());
}

void QuickActionManager::discoverConfigFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (document.isObject()) {
        const QJsonObject object = document.object();
        if (object.value(QStringLiteral("actions")).isArray()) {
            for (const QJsonValue &value : object.value(QStringLiteral("actions")).toArray())
                if (value.isObject()) addAction(value.toObject().toVariantMap());
        } else {
            addAction(object.toVariantMap());
        }
    } else if (document.isArray()) {
        for (const QJsonValue &value : document.array())
            if (value.isObject()) addAction(value.toObject().toVariantMap());
    }
}

void QuickActionManager::addAction(const QVariantMap &raw)
{
    QVariantMap action = normalizeAction(raw);
    const QString id = action.value(QStringLiteral("id")).toString();
    if (id.isEmpty() || m_seenActionIds.contains(id))
        return;
    m_seenActionIds.insert(id);
    m_actions.append(action);
}

QVariantMap QuickActionManager::normalizeAction(QVariantMap action) const
{
    QString id = safeId(action.value(QStringLiteral("id"), action.value(QStringLiteral("actionId"))).toString());
    if (id.isEmpty())
        id = safeId(action.value(QStringLiteral("name"), action.value(QStringLiteral("title"))).toString());
    action.insert(QStringLiteral("id"), id);

    if (!action.contains(QStringLiteral("name")))
        action.insert(QStringLiteral("name"), displayNameFromId(id));
    if (!action.contains(QStringLiteral("subtitle")))
        action.insert(QStringLiteral("subtitle"), QStringLiteral("Quick action"));

    const QString type = normalizedType(action.value(QStringLiteral("type"), QStringLiteral("system-action")).toString());
    action.insert(QStringLiteral("type"), type);
    action.insert(QStringLiteral("icon"), sharedIconFor(action));

    if (!action.contains(QStringLiteral("confirmRequired")))
        action.insert(QStringLiteral("confirmRequired"), false);
    if (!action.contains(QStringLiteral("danger")))
        action.insert(QStringLiteral("danger"), false);
    if (!action.contains(QStringLiteral("priority")))
        action.insert(QStringLiteral("priority"), 9999);

    const bool launchAction =
        action.value(QStringLiteral("launchApp"), false).toBool() ||
        type == QStringLiteral("qml") ||
        type == QStringLiteral("web") ||
        type == QStringLiteral("service-web") ||
        type == QStringLiteral("command") ||
        type == QStringLiteral("external") ||
        type == QStringLiteral("app");

    if (launchAction) {
        const QString appId = safeId(action.value(QStringLiteral("appId"), id).toString());
        action.insert(QStringLiteral("appId"), appId);
        action.insert(QStringLiteral("launchApp"), true);
        if (!action.contains(QStringLiteral("qmlSource")) && type == QStringLiteral("qml"))
            action.insert(QStringLiteral("qmlSource"), appMainQmlSource(appId));
    }

    return action;
}

QVariantMap QuickActionManager::readJsonObject(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object().toVariantMap() : QVariantMap();
}

QVariantList QuickActionManager::readJsonArray(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isArray() ? document.array().toVariantList() : QVariantList();
}

QString QuickActionManager::safeId(const QString &value) const
{
    QString id = value.trimmed().toLower();
    id.replace(QRegularExpression(QStringLiteral("[^a-z0-9._-]+")), QStringLiteral("-"));
    id.replace(QRegularExpression(QStringLiteral("-+")), QStringLiteral("-"));
    return id.remove(QRegularExpression(QStringLiteral("^-|-$")));
}

QString QuickActionManager::displayNameFromId(const QString &id) const
{
    QString value = id;
    value.replace(QLatin1Char('_'), QLatin1Char(' '));
    value.replace(QLatin1Char('-'), QLatin1Char(' '));
    QStringList words = value.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (QString &word : words) {
        if (!word.isEmpty())
            word[0] = word.at(0).toUpper();
    }
    return words.join(QLatin1Char(' '));
}

QString QuickActionManager::normalizedType(const QString &type) const
{
    const QString value = type.trimmed().toLower();
    if (value == QStringLiteral("native") || value == QStringLiteral("neutron"))
        return QStringLiteral("qml");
    if (value == QStringLiteral("systemd") || value == QStringLiteral("docker") || value == QStringLiteral("service"))
        return QStringLiteral("service-action");
    if (value.isEmpty())
        return QStringLiteral("system-action");
    return value;
}

QString QuickActionManager::cleanPath(const QString &path) const { return QDir::cleanPath(path); }
QString QuickActionManager::appMainQmlSource(const QString &appId) const
{
    return QStringLiteral("apps/") + safeId(appId) + QStringLiteral("/Main.qml");
}

QString QuickActionManager::sharedIconFor(const QVariantMap &action) const
{
    const QString type = normalizedType(action.value(QStringLiteral("type")).toString());
    if (type == QStringLiteral("service") || type == QStringLiteral("service-action"))
        return QStringLiteral("service");
    if (type == QStringLiteral("script"))
        return QStringLiteral("script");

    const QString icon = action.value(QStringLiteral("icon")).toString().trimmed();
    return icon.isEmpty() ? QStringLiteral("atom") : icon;
}

QStringList QuickActionManager::defaultDockActionIds() const
{
    return {
        QStringLiteral("shutdown"),
        QStringLiteral("restart"),
        QStringLiteral("reboot"),
        QStringLiteral("controller-off"),
        QStringLiteral("screensaver"),
        QStringLiteral("help"),
        QStringLiteral("terminal"),
        QStringLiteral("settings")
    };
}

void QuickActionManager::loadDockState()
{
    m_dockActionIds.clear();
    m_dockStateNeedsSave = false;

    QFile file(m_statePath);
    if (!file.open(QIODevice::ReadOnly)) {
        m_dockActionIds = defaultDockActionIds();
        m_dockStateNeedsSave = true;
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        m_dockActionIds = defaultDockActionIds();
        m_dockStateNeedsSave = true;
        return;
    }

    const QJsonObject object = document.object();
    for (const QJsonValue &value : object.value(QStringLiteral("slots")).toArray())
        m_dockActionIds.append(safeId(value.toString()));

    /*
        Patch 24B dock-state migration. Existing users receive Help once.
        Once version 3 is saved, they remain free to remove it permanently.
    */
    const int version = object.value(QStringLiteral("version")).toInt(1);
    if (version < 3 && !m_dockActionIds.contains(QStringLiteral("help"))) {
        m_dockActionIds.append(QStringLiteral("help"));
        m_dockStateNeedsSave = true;
    }
}

bool QuickActionManager::saveDockState() const
{
    if (!QDir().mkpath(QFileInfo(m_statePath).absolutePath()))
        return false;

    QJsonArray slotArray;
    for (const QString &id : m_dockActionIds)
        slotArray.append(id);

    QJsonObject object;
    object.insert(QStringLiteral("version"), 3);
    object.insert(QStringLiteral("slots"), slotArray);

    QSaveFile file(m_statePath);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(payload) != payload.size())
        return false;
    return file.commit();
}

void QuickActionManager::normalizeDockAssignments()
{
    QStringList result;
    QSet<QString> used;

    for (const QString &candidate : m_dockActionIds) {
        const QString id = safeId(candidate);
        if (id.isEmpty() || used.contains(id) || actionById(id).isEmpty())
            continue;
        result.append(id);
        used.insert(id);
    }

    /* The dock is never allowed to become empty. */
    if (result.isEmpty()) {
        const QStringList defaults = defaultDockActionIds();
        for (const QString &candidate : defaults) {
            if (!actionById(candidate).isEmpty()) {
                result.append(candidate);
                break;
            }
        }
    }

    if (result.isEmpty() && !m_actions.isEmpty()) {
        const QString id = m_actions.first().toMap().value(QStringLiteral("id")).toString();
        if (!id.isEmpty())
            result.append(id);
    }

    m_dockActionIds = result;
}

void QuickActionManager::rebuildDockActions()
{
    m_dockActions.clear();
    for (int slot = 0; slot < m_dockActionIds.size(); ++slot) {
        QVariantMap action = actionById(m_dockActionIds.at(slot));
        if (action.isEmpty())
            continue;
        action.insert(QStringLiteral("slot"), slot);
        m_dockActions.append(action);
    }
}

void QuickActionManager::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void QuickActionManager::setLastMessage(const QString &message)
{
    if (m_lastMessage == message)
        return;
    m_lastMessage = message;
    emit lastMessageChanged();
}

bool QuickActionManager::executeSystemAction(const QVariantMap &actionData)
{
    const QString id = actionData.value(QStringLiteral("id")).toString();
    const QString backend = actionData.value(QStringLiteral("backendAction"), id).toString().trimmed().toLower();

    if (backend == QStringLiteral("controller-off")) {
        emit controllerOffRequested();
        setLastMessage(QStringLiteral("Controller disconnect requested"));
        emit actionFinished(id, true, m_lastMessage);
        return true;
    }

    if (backend == QStringLiteral("screensaver")) {
        emit screensaverRequested();
        setLastMessage(QStringLiteral("Screensaver requested"));
        emit actionFinished(id, true, m_lastMessage);
        return true;
    }

    if (backend == QStringLiteral("help")) {
        emit helpRequested();
        setLastMessage(QStringLiteral("Help Center opened"));
        emit actionFinished(id, true, m_lastMessage);
        return true;
    }

    setBusy(true);
    bool success = false;

    if (backend == QStringLiteral("restart") || backend == QStringLiteral("restart-os") || backend == QStringLiteral("restart-shell")) {
        success = runSystemdAction(id, QStringLiteral("neutronos.service"), QStringLiteral("restart"));
    } else if (backend == QStringLiteral("reboot")) {
        success = runCommandAction(id, QStringLiteral("systemctl"), {QStringLiteral("reboot")}, 3000);
    } else if (backend == QStringLiteral("shutdown") || backend == QStringLiteral("poweroff")) {
        success = runCommandAction(id, QStringLiteral("systemctl"), {QStringLiteral("poweroff")}, 3000);
    } else if (backend == QStringLiteral("update") || backend == QStringLiteral("system-update")) {
        success = runCommandAction(id, QStringLiteral("bash"), {QStringLiteral("-lc"), QStringLiteral("apt update && apt upgrade -y")}, 120000);
    } else if (actionData.contains(QStringLiteral("program"))) {
        success = runCommandAction(
            id,
            actionData.value(QStringLiteral("program")).toString(),
            variantToStringList(actionData.value(QStringLiteral("arguments"))),
            actionData.value(QStringLiteral("timeoutMs"), 15000).toInt()
        );
    } else {
        setLastMessage(QStringLiteral("Unsupported quick action: ") + backend);
        emit actionFinished(id, false, m_lastMessage);
    }

    setBusy(false);
    return success;
}

bool QuickActionManager::executeServiceAction(const QVariantMap &actionData)
{
    const QString id = actionData.value(QStringLiteral("id")).toString();
    const QString action = actionData.value(QStringLiteral("serviceAction"), QStringLiteral("start")).toString().trimmed().toLower();
    const QString docker = actionData.value(QStringLiteral("docker")).toString().trimmed();
    const QString service = actionData.value(QStringLiteral("service")).toString().trimmed();

    setBusy(true);
    bool success = false;
    if (!docker.isEmpty() && dockerContainerExists(docker))
        success = runDockerAction(id, docker, action);
    else if (!service.isEmpty() && systemdUnitExists(service))
        success = runSystemdAction(id, service, action);
    else {
        setLastMessage(QStringLiteral("Service backend is unavailable"));
        emit actionFinished(id, false, m_lastMessage);
    }
    setBusy(false);
    return success;
}

bool QuickActionManager::executeScriptAction(const QVariantMap &actionData)
{
    const QString id = actionData.value(QStringLiteral("id")).toString();
    const QString path = cleanPath(actionData.value(QStringLiteral("scriptPath")).toString());
    const QFileInfo file(path);

    const QStringList approvedRoots = {
        cleanPath(QDir(m_neutronRootPath).filePath(QStringLiteral("scripts"))),
        cleanPath(QDir(m_configRootPath).filePath(QStringLiteral("scripts")))
    };

    bool approved = false;
    for (const QString &root : approvedRoots) {
        if (path == root || path.startsWith(root + QDir::separator())) {
            approved = true;
            break;
        }
    }

    if (!approved || !file.exists() || !file.isFile()) {
        setLastMessage(QStringLiteral("Script is outside approved NeutronOS directories"));
        emit actionFinished(id, false, m_lastMessage);
        return false;
    }

    const QString suffix = file.suffix().toLower();
    if (suffix == QStringLiteral("py"))
        return runCommandAction(id, QStringLiteral("python3"), {file.absoluteFilePath()}, 120000);
    return runCommandAction(id, QStringLiteral("bash"), {file.absoluteFilePath()}, 120000);
}

bool QuickActionManager::runCommandAction(const QString &actionId,
                                          const QString &program,
                                          const QStringList &arguments,
                                          int timeoutMs)
{
    QString output;
    QString error;
    const int code = runProcess(program, arguments, timeoutMs, &output, &error);
    QString message = code == 0 ? output.trimmed() : error.trimmed();
    if (message.isEmpty())
        message = code == 0 ? QStringLiteral("Action completed") : QStringLiteral("Action failed");
    setLastMessage(message);
    emit actionFinished(actionId, code == 0, message);
    return code == 0;
}

bool QuickActionManager::runSystemdAction(const QString &actionId,
                                          const QString &unit,
                                          const QString &actionName)
{
    if (!commandExists(QStringLiteral("systemctl"))) {
        setLastMessage(QStringLiteral("systemctl is unavailable"));
        emit actionFinished(actionId, false, m_lastMessage);
        return false;
    }
    return runCommandAction(actionId, QStringLiteral("systemctl"), {actionName, unit}, 15000);
}

bool QuickActionManager::runDockerAction(const QString &actionId,
                                         const QString &container,
                                         const QString &actionName)
{
    if (!commandExists(QStringLiteral("docker"))) {
        setLastMessage(QStringLiteral("docker is unavailable"));
        emit actionFinished(actionId, false, m_lastMessage);
        return false;
    }
    return runCommandAction(actionId, QStringLiteral("docker"), {actionName, container}, 15000);
}

int QuickActionManager::runProcess(const QString &program,
                                   const QStringList &arguments,
                                   int timeoutMs,
                                   QString *standardOutput,
                                   QString *standardError) const
{
    if (program.trimmed().isEmpty())
        return -127;

    QProcess process;
    process.setProcessChannelMode(QProcess::SeparateChannels);
    process.start(program, arguments);
    if (!process.waitForStarted(900)) {
        if (standardError) *standardError = QStringLiteral("Failed to start: ") + program;
        return -127;
    }
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(700);
        if (standardOutput) *standardOutput = QString::fromUtf8(process.readAllStandardOutput());
        if (standardError) *standardError = QString::fromUtf8(process.readAllStandardError());
        return -124;
    }
    if (standardOutput) *standardOutput = QString::fromUtf8(process.readAllStandardOutput());
    if (standardError) *standardError = QString::fromUtf8(process.readAllStandardError());
    return process.exitStatus() == QProcess::NormalExit ? process.exitCode() : -125;
}

bool QuickActionManager::commandExists(const QString &command) const
{
    const QFileInfo info(command);
    if (info.isAbsolute())
        return info.exists() && info.isExecutable();
    return runProcess(QStringLiteral("which"), {command}, 900) == 0;
}

bool QuickActionManager::systemdUnitExists(const QString &unit) const
{
    if (unit.isEmpty() || !commandExists(QStringLiteral("systemctl")))
        return false;
    QString output;
    const int code = runProcess(
        QStringLiteral("systemctl"),
        {QStringLiteral("list-unit-files"), unit, QStringLiteral("--no-legend")},
        1800,
        &output
    );
    return code == 0 && output.contains(unit);
}

bool QuickActionManager::dockerContainerExists(const QString &name) const
{
    if (name.isEmpty() || !commandExists(QStringLiteral("docker")))
        return false;
    QString output;
    const int code = runProcess(
        QStringLiteral("docker"),
        {QStringLiteral("ps"), QStringLiteral("-a"), QStringLiteral("--format"), QStringLiteral("{{.Names}}")},
        2500,
        &output
    );
    if (code != 0)
        return false;
    for (const QString &line : output.split(QLatin1Char('\n'))) {
        if (line.trimmed().compare(name, Qt::CaseInsensitive) == 0)
            return true;
    }
    return false;
}

QStringList QuickActionManager::variantToStringList(const QVariant &value) const
{
    QStringList result;
    const QVariantList list = value.toList();
    for (const QVariant &entry : list) {
        const QString text = entry.toString().trimmed();
        if (!text.isEmpty()) result.append(text);
    }
    if (result.isEmpty()) {
        const QString text = value.toString().trimmed();
        if (!text.isEmpty()) result.append(text);
    }
    return result;
}

void QuickActionManager::resolveRuntimePaths()
{
    m_neutronRootPath = resolveNeutronRootPath();
    m_appsRootPath = cleanPath(QDir(m_neutronRootPath).filePath(QStringLiteral("qml/apps")));
    m_configRootPath = cleanPath(QDir(m_neutronRootPath).filePath(QStringLiteral("config")));
    m_statePath = cleanPath(QDir(m_neutronRootPath).filePath(QStringLiteral("state/apps/quick-actions.json")));
}

QString QuickActionManager::resolveNeutronRootPath() const
{
    const QByteArray env = qgetenv("NEUTRONOS_ROOT");
    if (!env.isEmpty()) {
        const QString root = canonicalRoot(QString::fromLocal8Bit(env));
        if (rootLooksValid(root)) return root;
    }

    const QString home = canonicalRoot(QDir::homePath() + QStringLiteral("/NeutronOS"));
    if (rootLooksValid(home)) return home;

    const QString current = canonicalRoot(QDir::currentPath());
    if (rootLooksValid(current)) return current;

    const QString appParent = canonicalRoot(QDir(QCoreApplication::applicationDirPath()).absoluteFilePath(QStringLiteral("..")));
    if (rootLooksValid(appParent)) return appParent;
    return home;
}
