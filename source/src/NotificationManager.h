#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>

class NotificationManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList notifications READ notifications NOTIFY notificationsChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY notificationsChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY notificationsChanged)
    Q_PROPERTY(QString statePath READ statePath CONSTANT)
    Q_PROPERTY(QString dndMode READ dndMode WRITE setDndMode NOTIFY notificationsChanged)

public:
    explicit NotificationManager(const QString &neutronRoot,
                                 QObject *parent = nullptr);

    QVariantList notifications() const;
    int unreadCount() const;
    int totalCount() const;
    QString statePath() const;
    QString dndMode() const { return m_dndMode; }

    Q_INVOKABLE QString publish(const QString &category,
                                const QString &title,
                                const QString &message,
                                const QString &priority,
                                const QString &source,
                                const QString &action,
                                const QVariantMap &payload);

    Q_INVOKABLE bool markRead(const QString &notificationId,
                              bool read = true);
    Q_INVOKABLE bool markAllRead();
    Q_INVOKABLE bool dismiss(const QString &notificationId);
    Q_INVOKABLE int clearOrdinary();
    Q_INVOKABLE int clearSecurity();
    Q_INVOKABLE bool clearAll();
    Q_INVOKABLE QVariantMap notification(const QString &notificationId) const;
    Q_INVOKABLE void reload();
    Q_INVOKABLE bool setDndMode(const QString &mode);
    Q_INVOKABLE bool shouldPresent(const QString &notificationId) const;

signals:
    void notificationsChanged();
    void notificationPublished(const QVariantMap &notification);
    void notificationRemoved(const QString &notificationId);

private:
    friend class SecurityManager;
    QVariantMap clearAllSecurityAuthenticated();
    bool saveList(const QVariantList &entries) const;

    QString m_neutronRoot;
    QString m_stateDirectory;
    QString m_statePath;
    QVariantList m_notifications;
    QString m_dndMode = QStringLiteral("off");

    static QString normalizedCategory(const QString &category);
    static QString normalizedPriority(const QString &priority);
    static QString cleanedText(const QString &text, int maximumLength);
    static qint64 timestampFor(const QVariantMap &entry);
    static bool protectedNotification(const QVariantMap &entry);

    int indexForId(const QString &notificationId) const;
    bool load();
    bool save() const;
    void trim();
};
