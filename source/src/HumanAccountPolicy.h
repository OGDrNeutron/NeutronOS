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

#include <QRegularExpression>
#include <QString>
#include <QReadWriteLock>
#include <pwd.h>
#include <unistd.h>
#include <vector>

// Session identity is supplied by UserManager after passwd validation. The
// internal shell service identity never supplies personal storage paths.
namespace HumanHome {
inline QString sessionUsername;
inline QReadWriteLock sessionLock;
inline void setSessionUser(const QString &username) { QWriteLocker guard(&sessionLock); sessionUsername = username; }
inline QString sessionUser() { QReadLocker guard(&sessionLock); return sessionUsername; }
inline QString forUser(const QString &username)
{
    static const QRegularExpression valid(QStringLiteral("^[a-z_][a-z0-9_-]{0,31}$"));
    if (!valid.match(username).hasMatch()) return QString();
    const QByteArray name = username.toLocal8Bit();
    std::vector<char> buffer(65536);
    passwd account{}; passwd *entry = nullptr;
    if (getpwnam_r(name.constData(), &account, buffer.data(), buffer.size(), &entry) != 0) return QString();
    const QString expected = QStringLiteral("/NeutronOS/") + username;
    if (!entry || !HumanAccountPolicy::isHuman(*entry) ||
        QString::fromLocal8Bit(entry->pw_dir) != expected) return QString();
    return expected;
}
inline QString path()
{
    const QString username = sessionUser();
    if (!username.isEmpty()) return forUser(username);
    // The guarded browser supervisor carries its authenticated session identity.
    const QString supervisedUser = qEnvironmentVariable("NEUTRONOS_HUMAN_USER");
    if (!supervisedUser.isEmpty()) return forUser(supervisedUser);
    // Developer/direct human launches may use their own validated passwd entry.
    std::vector<char> buffer(65536);
    passwd account{}; passwd *entry = nullptr;
    if (getpwuid_r(getuid(), &account, buffer.data(), buffer.size(), &entry) != 0) return QString();
    return entry ? forUser(QString::fromLocal8Bit(entry->pw_name)) : QString();
}
inline QString appStateRoot() { const QString home = path(); return home.isEmpty() ? QStringLiteral("/var/lib/neutronos") : home; }
inline QString browsePath() { const QString home = path(); return home.isEmpty() ? QStringLiteral("/NeutronOS") : home; }
}
