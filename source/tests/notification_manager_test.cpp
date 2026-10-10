#include "NotificationManager.h"

#include <QCoreApplication>
#include <QTemporaryDir>

#include <cstdlib>

namespace {
void require(bool condition, const char *message)
{
    if (!condition) {
        qCritical("%s", message);
        std::exit(1);
    }
}
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir root;
    require(root.isValid(), "temporary notification root must be available");

    NotificationManager notifications(root.path());
    const QString ordinary = notifications.publish(
        QStringLiteral("system"), QStringLiteral("Completed"),
        QStringLiteral("Routine task finished"), QStringLiteral("info"),
        QStringLiteral("test"), QString(), {});
    const QString critical = notifications.publish(
        QStringLiteral("security"), QStringLiteral("Active incident"),
        QStringLiteral("Evidence requires review"), QStringLiteral("critical"),
        QStringLiteral("Security Core"), QStringLiteral("security-review"), {});

    require(!ordinary.isEmpty() && !critical.isEmpty(), "notifications should publish");
    require(notifications.setDndMode(QStringLiteral("on")), "DND should accept on");
    require(!notifications.shouldPresent(ordinary), "DND should suppress ordinary presentation");
    require(notifications.shouldPresent(critical), "critical security events must bypass DND");
    require(!notifications.setDndMode(QStringLiteral("invalid")), "unknown DND mode must be denied");
    require(notifications.dismiss(ordinary), "ordinary notification should clear");
    require(!notifications.dismiss(critical), "critical security notification must be protected");

    notifications.publish(QStringLiteral("storage"), QStringLiteral("Mounted"),
                          QStringLiteral("Media mounted"), QStringLiteral("success"),
                          QStringLiteral("Storage Manager"), QString(), {});
    const QString securityWarning = notifications.publish(
        QStringLiteral("security"), QStringLiteral("Review recommended"),
        QStringLiteral("Dismissible presentation"), QStringLiteral("warning"),
        QStringLiteral("Security Core"), QString(), {{QStringLiteral("eventId"), QStringLiteral("event-1")}});
    const QString protectedWarning = notifications.publish(
        QStringLiteral("security"), QStringLiteral("Policy hold"),
        QStringLiteral("This warning is explicitly non-dismissible"), QStringLiteral("warning"),
        QStringLiteral("Security Core"), QString(),
        {{QStringLiteral("eventId"), QStringLiteral("event-2")},
         {QStringLiteral("dismissible"), false}});
    require(notifications.clearAll(), "one R3 press must clear normal and dismissible Security notifications");
    require(notifications.notification(securityWarning).isEmpty(),
            "one R3 press must clear dismissible Security notifications");
    require(notifications.notification(protectedWarning).value(QStringLiteral("category")).toString() ==
                QStringLiteral("security"), "R3 must retain protected Security notifications");
    require(notifications.notification(critical).value(QStringLiteral("priority")).toString() ==
                QStringLiteral("critical"), "R3 must retain critical Security notifications");
    require(notifications.totalCount() == 2, "R3 must leave only protected Security notifications");
    return 0;
}
