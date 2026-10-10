#pragma once

#include <QFile>
#include <QFileInfo>
#include <QString>

#include <pwd.h>

namespace HumanAccountPolicy
{
struct UidRange
{
    quint64 minimum = 1000;
    quint64 maximum = 60000;
};

inline UidRange uidRange()
{
    UidRange range;
    QFile file(QStringLiteral("/etc/login.defs"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return range;
    while (!file.atEnd()) {
        const QByteArray line = file.readLine().split('#').constFirst().trimmed();
        const QList<QByteArray> fields = line.simplified().split(' ');
        if (fields.size() != 2)
            continue;
        bool ok = false;
        const quint64 value = fields.at(1).toULongLong(&ok);
        if (!ok)
            continue;
        if (fields.at(0) == QByteArrayLiteral("UID_MIN"))
            range.minimum = value;
        else if (fields.at(0) == QByteArrayLiteral("UID_MAX"))
            range.maximum = value;
    }
    return range;
}

inline bool interactiveShell(const QString &shellValue)
{
    const QString shell = shellValue.trimmed().toLower();
    return shell.startsWith(QLatin1Char('/')) &&
           !shell.endsWith(QStringLiteral("/nologin")) &&
           !shell.endsWith(QStringLiteral("/false")) &&
           shell != QStringLiteral("/bin/sync") &&
           shell != QStringLiteral("/sbin/halt") &&
           shell != QStringLiteral("/sbin/shutdown");
}

inline bool isHuman(const QString &username,
                    quint64 uid,
                    const QString &homeDirectory,
                    const QString &shell)
{
    const UidRange range = uidRange();
    const QString home = homeDirectory.trimmed();
    return username.trimmed() != QStringLiteral("root") &&
           username.trimmed() != QStringLiteral("neutronos") &&
           home == QStringLiteral("/NeutronOS/") + username.trimmed() &&
           uid >= range.minimum && uid <= range.maximum &&
           interactiveShell(shell) &&
           home.startsWith(QLatin1Char('/')) &&
           home != QStringLiteral("/") &&
           home != QStringLiteral("/nonexistent") &&
           QFileInfo(home).isDir();
}

inline bool isHuman(const struct passwd &entry)
{
    return isHuman(QString::fromLocal8Bit(entry.pw_name ? entry.pw_name : ""),
                   static_cast<quint64>(entry.pw_uid),
                   QString::fromLocal8Bit(entry.pw_dir ? entry.pw_dir : ""),
                   QString::fromLocal8Bit(entry.pw_shell ? entry.pw_shell : ""));
}

inline bool namedUserIsHuman(const QString &username)
{
    const QByteArray encoded = username.toLocal8Bit();
    const struct passwd *entry = getpwnam(encoded.constData());
    return entry && isHuman(*entry);
}
}


#include <QPointer>
inline QString activeGamesHome(QObject *identity) {
    if (!identity) return {};
    const QString user=identity->property("activeUsername").toString();
    const auto encoded=user.toLocal8Bit();
    const passwd *entry=getpwnam(encoded.constData());
    return entry && HumanAccountPolicy::isHuman(*entry) ? QString::fromLocal8Bit(entry->pw_dir) : QString();
}
