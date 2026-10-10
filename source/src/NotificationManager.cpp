#include "NotificationManager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QUuid>
#include <QStringList>

#include <algorithm>

namespace {
constexpr int MaximumNotifications = 250;
constexpr qint64 DuplicateWindowMs = 5000;
}

NotificationManager::NotificationManager(const QString &neutronRoot,
                                         QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_stateDirectory(QDir::cleanPath(neutronRoot + QStringLiteral("/state/notifications"))),
      m_statePath(QDir::cleanPath(m_stateDirectory + QStringLiteral("/notifications.json")))
{
    QDir().mkpath(m_stateDirectory);
    load();
    QFile preference(QDir(m_neutronRoot).filePath(QStringLiteral("state/core-capabilities/preferences.json")));
    if (preference.open(QIODevice::ReadOnly))
        m_dndMode = QJsonDocument::fromJson(preference.readAll()).object()
                        .value(QStringLiteral("dndMode")).toString(QStringLiteral("off"));
}

QVariantList NotificationManager::notifications() const
{
    return m_notifications;
}

int NotificationManager::unreadCount() const
{
    int count = 0;
    for (const QVariant &value : m_notifications) {
        if (!value.toMap().value(QStringLiteral("read")).toBool())
            ++count;
    }
    return count;
}

int NotificationManager::totalCount() const
{
    return m_notifications.size();
}

QString NotificationManager::statePath() const
{
    return m_statePath;
}

QString NotificationManager::publish(const QString &category,
                                     const QString &title,
                                     const QString &message,
                                     const QString &priority,
                                     const QString &source,
                                     const QString &action,
                                     const QVariantMap &payload)
{
    const QString cleanCategory = normalizedCategory(category);
    const QString cleanTitle = cleanedText(title, 160);
    const QString cleanMessage = cleanedText(message, 1200);
    const QString cleanSource = cleanedText(source, 120);
    const QString cleanAction = cleanedText(action, 120);
    const QString cleanPriority = normalizedPriority(priority);

    if (cleanTitle.isEmpty() && cleanMessage.isEmpty())
        return QString();

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();

    // Collapse bursts of identical backend signals into one fresh unread item.
    for (int index = 0; index < m_notifications.size(); ++index) {
        QVariantMap existing = m_notifications.at(index).toMap();
        if (existing.value(QStringLiteral("category")).toString() != cleanCategory ||
                existing.value(QStringLiteral("title")).toString() != cleanTitle ||
                existing.value(QStringLiteral("message")).toString() != cleanMessage ||
                existing.value(QStringLiteral("source")).toString() != cleanSource) {
            continue;
        }

        if (nowMs - timestampFor(existing) > DuplicateWindowMs)
            break;

        existing[QStringLiteral("timestampMs")] = nowMs;
        existing[QStringLiteral("timestamp")] = QDateTime::fromMSecsSinceEpoch(nowMs, Qt::UTC).toString(Qt::ISODateWithMs);
        existing[QStringLiteral("read")] = false;
        existing[QStringLiteral("priority")] = cleanPriority;
        existing[QStringLiteral("action")] = cleanAction;
        existing[QStringLiteral("payload")] = payload;
        existing[QStringLiteral("repeatCount")] = existing.value(QStringLiteral("repeatCount"), 1).toInt() + 1;

        m_notifications.removeAt(index);
        m_notifications.prepend(existing);
        trim();
        save();
        emit notificationsChanged();
        emit notificationPublished(existing);
        return existing.value(QStringLiteral("id")).toString();
    }

    QVariantMap entry;
    const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    entry[QStringLiteral("id")] = id;
    entry[QStringLiteral("category")] = cleanCategory;
    entry[QStringLiteral("title")] = cleanTitle.isEmpty() ? QStringLiteral("NeutronOS Notification") : cleanTitle;
    entry[QStringLiteral("message")] = cleanMessage;
    entry[QStringLiteral("priority")] = cleanPriority;
    entry[QStringLiteral("source")] = cleanSource;
    entry[QStringLiteral("action")] = cleanAction;
    entry[QStringLiteral("payload")] = payload;
    entry[QStringLiteral("timestampMs")] = nowMs;
    entry[QStringLiteral("timestamp")] = QDateTime::fromMSecsSinceEpoch(nowMs, Qt::UTC).toString(Qt::ISODateWithMs);
    entry[QStringLiteral("read")] = false;
    entry[QStringLiteral("repeatCount")] = 1;

    m_notifications.prepend(entry);
    trim();
    save();
    emit notificationsChanged();
    emit notificationPublished(entry);
    return id;
}

bool NotificationManager::markRead(const QString &notificationId, bool read)
{
    const int index = indexForId(notificationId);
    if (index < 0)
        return false;

    QVariantMap entry = m_notifications.at(index).toMap();
    if (entry.value(QStringLiteral("read")).toBool() == read)
        return true;

    entry[QStringLiteral("read")] = read;
    m_notifications[index] = entry;
    if (!save())
        return false;
    emit notificationsChanged();
    return true;
}

bool NotificationManager::markAllRead()
{
    bool changed = false;
    for (int index = 0; index < m_notifications.size(); ++index) {
        QVariantMap entry = m_notifications.at(index).toMap();
        if (entry.value(QStringLiteral("read")).toBool())
            continue;
        entry[QStringLiteral("read")] = true;
        m_notifications[index] = entry;
        changed = true;
    }

    if (!changed)
        return true;
    if (!save())
        return false;
    emit notificationsChanged();
    return true;
}

bool NotificationManager::dismiss(const QString &notificationId)
{
    const int index = indexForId(notificationId);
    if (index < 0)
        return false;

    const QVariantMap dismissed = m_notifications.at(index).toMap();
    if (protectedNotification(dismissed))
        return false;
    m_notifications.removeAt(index);
    if (!save())
        return false;
    emit notificationsChanged();
    emit notificationRemoved(notificationId);
    return true;
}

int NotificationManager::clearOrdinary()
{
    QVariantList retained;
    QVariantList dismissed;
    for (const QVariant &value : std::as_const(m_notifications)) {
        const QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("category")).toString() == QStringLiteral("security") ||
            protectedNotification(entry))
            retained.append(entry);
        else
            dismissed.append(entry);
    }
    if (dismissed.isEmpty())
        return 0;
    if (!saveList(retained))
        return 0;
    m_notifications = retained;
    emit notificationsChanged();
    for (const QVariant &value : std::as_const(dismissed)) {
        const QVariantMap entry = value.toMap();
        emit notificationRemoved(entry.value(QStringLiteral("id")).toString());
    }
    return dismissed.size();
}

int NotificationManager::clearSecurity()
{
    QVariantList retained;
    QVariantList dismissed;
    for (const QVariant &value : std::as_const(m_notifications)) {
        const QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("category")).toString() != QStringLiteral("security") ||
            protectedNotification(entry))
            retained.append(entry);
        else
            dismissed.append(entry);
    }
    if (dismissed.isEmpty())
        return 0;
    m_notifications = retained;
    if (!save())
        return 0;
    emit notificationsChanged();
    for (const QVariant &value : std::as_const(dismissed)) {
        const QVariantMap entry = value.toMap();
        emit notificationRemoved(entry.value(QStringLiteral("id")).toString());
    }
    return dismissed.size();
}

bool NotificationManager::clearAll()
{
    if (m_notifications.isEmpty())
        return true;

    QVariantList retained;
    for (const QVariant &value : std::as_const(m_notifications))
        if (protectedNotification(value.toMap())) retained.append(value);
    if (retained.size() == m_notifications.size())
        return true;
    if (!saveList(retained))
        return false;
    m_notifications = retained;
    emit notificationsChanged();
    return true;
}

QVariantMap NotificationManager::clearAllSecurityAuthenticated()
{
    QVariantList retained;
    QVariantList removed;
    for (const QVariant &value : std::as_const(m_notifications)) {
        const QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("category")).toString() == QStringLiteral("security"))
            removed.append(entry);
        else
            retained.append(entry);
    }
    QVariantMap result;
    result.insert(QStringLiteral("success"), false);
    result.insert(QStringLiteral("removed"), 0);
    result.insert(QStringLiteral("remainingSecurity"), removed.size());
    result.insert(QStringLiteral("total"), m_notifications.size());
    if (removed.isEmpty()) {
        result[QStringLiteral("success")] = true;
        return result;
    }
    // Only notification presentation state is persisted. Security audit, threat,
    // integrity and quarantine stores are deliberately never opened here.
    if (!saveList(retained)) {
        result[QStringLiteral("error")] = QStringLiteral("Notification storage could not be saved");
        return result;
    }
    m_notifications = retained;
    emit notificationsChanged();
    for (const QVariant &value : std::as_const(removed))
        emit notificationRemoved(value.toMap().value(QStringLiteral("id")).toString());
    result[QStringLiteral("success")] = true;
    result[QStringLiteral("removed")] = removed.size();
    result[QStringLiteral("remainingSecurity")] = 0;
    result[QStringLiteral("total")] = retained.size();
    return result;
}

QVariantMap NotificationManager::notification(const QString &notificationId) const
{
    const int index = indexForId(notificationId);
    return index < 0 ? QVariantMap() : m_notifications.at(index).toMap();
}

void NotificationManager::reload()
{
    load();
    emit notificationsChanged();
}

bool NotificationManager::setDndMode(const QString &mode)
{
    const QString value = mode.trimmed().toLower();
    if (value != QStringLiteral("off") && value != QStringLiteral("on") &&
        value != QStringLiteral("schedule"))
        return false;
    m_dndMode = value;
    emit notificationsChanged();
    return true;
}

bool NotificationManager::shouldPresent(const QString &notificationId) const
{
    const QVariantMap item = notification(notificationId);
    if (item.isEmpty())
        return false;
    const QString priority = item.value(QStringLiteral("priority")).toString().toLower();
    const QString category = item.value(QStringLiteral("category")).toString().toLower();
    if (priority == QStringLiteral("critical") || category == QStringLiteral("security"))
        return true;
    return m_dndMode == QStringLiteral("off");
}

QString NotificationManager::normalizedCategory(const QString &category)
{
    const QString clean = category.trimmed().toLower();
    static const QStringList supported = {
        QStringLiteral("system"), QStringLiteral("security"), QStringLiteral("storage"),
        QStringLiteral("network"), QStringLiteral("apps"), QStringLiteral("updates"),
        QStringLiteral("backup"), QStringLiteral("games"), QStringLiteral("docker"),
        QStringLiteral("media")
    };
    return supported.contains(clean) ? clean : QStringLiteral("system");
}

QString NotificationManager::normalizedPriority(const QString &priority)
{
    const QString clean = priority.trimmed().toLower();
    if (clean == QStringLiteral("critical") || clean == QStringLiteral("warning") ||
            clean == QStringLiteral("success") || clean == QStringLiteral("info")) {
        return clean;
    }
    return QStringLiteral("info");
}

QString NotificationManager::cleanedText(const QString &text, int maximumLength)
{
    QString cleaned = text;
    cleaned.replace(QChar('\r'), QChar(' '));
    cleaned = cleaned.trimmed();
    if (cleaned.size() > maximumLength)
        cleaned = cleaned.left(maximumLength - 1) + QChar(0x2026);
    return cleaned;
}

qint64 NotificationManager::timestampFor(const QVariantMap &entry)
{
    return entry.value(QStringLiteral("timestampMs")).toLongLong();
}

bool NotificationManager::protectedNotification(const QVariantMap &entry)
{
    if (entry.value(QStringLiteral("category")).toString() != QStringLiteral("security"))
        return false;
    const QVariantMap payload = entry.value(QStringLiteral("payload")).toMap();
    // The producer may explicitly make a Security notification presentation
    // non-dismissible without changing the lifecycle of its underlying event.
    // Critical Security notifications remain protected by default.
    return entry.value(QStringLiteral("priority")).toString() == QStringLiteral("critical") ||
           entry.value(QStringLiteral("dismissible"), true).toBool() == false ||
           payload.value(QStringLiteral("dismissible"), true).toBool() == false ||
           payload.value(QStringLiteral("nonDismissible"), false).toBool() ||
           payload.value(QStringLiteral("protectedNotification"), false).toBool();
}

int NotificationManager::indexForId(const QString &notificationId) const
{
    for (int index = 0; index < m_notifications.size(); ++index) {
        if (m_notifications.at(index).toMap().value(QStringLiteral("id")).toString() == notificationId)
            return index;
    }
    return -1;
}

bool NotificationManager::load()
{
    m_notifications.clear();

    QFile file(m_statePath);
    if (!file.exists())
        return true;
    if (!file.open(QIODevice::ReadOnly))
        return false;

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isArray())
        return false;

    for (const QJsonValue &value : document.array()) {
        if (!value.isObject())
            continue;
        QVariantMap entry = value.toObject().toVariantMap();
        if (entry.value(QStringLiteral("id")).toString().isEmpty())
            continue;
        entry[QStringLiteral("category")] = normalizedCategory(entry.value(QStringLiteral("category")).toString());
        entry[QStringLiteral("priority")] = normalizedPriority(entry.value(QStringLiteral("priority")).toString());
        m_notifications.append(entry);
    }

    std::sort(m_notifications.begin(), m_notifications.end(), [](const QVariant &left, const QVariant &right) {
        return NotificationManager::timestampFor(left.toMap()) > NotificationManager::timestampFor(right.toMap());
    });
    trim();
    return true;
}

bool NotificationManager::save() const
{
    return saveList(m_notifications);
}

bool NotificationManager::saveList(const QVariantList &entries) const
{
    QDir().mkpath(m_stateDirectory);
    QSaveFile file(m_statePath);
    if (!file.open(QIODevice::WriteOnly))
        return false;

    QJsonArray array;
    for (const QVariant &value : entries)
        array.append(QJsonObject::fromVariantMap(value.toMap()));

    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    return file.commit();
}

void NotificationManager::trim()
{
    while (m_notifications.size() > MaximumNotifications)
        m_notifications.removeLast();
}
