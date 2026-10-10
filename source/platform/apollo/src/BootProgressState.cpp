#include "BootProgressState.h"

#include <QDir>
#include <QFile>

#ifdef Q_OS_LINUX
#include <fcntl.h>
#include <grp.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#endif

namespace {
constexpr auto kDefaultStateDirectory = "/run/neutronos/boot";
constexpr auto kStateGroup = "neutronos-shell";

void setError(QString *destination, const QString &message)
{
    if (destination)
        *destination = message;
}

#ifdef Q_OS_LINUX
gid_t stateGroup()
{
    const QByteArray configured = qEnvironmentVariable("NEUTRONOS_BOOT_STATE_GROUP",
                                                        kStateGroup).toLocal8Bit();
    const group *entry = ::getgrnam(configured.constData());
    return entry ? entry->gr_gid : static_cast<gid_t>(-1);
}

bool writeAll(int fd, const QByteArray &content)
{
    qsizetype written = 0;
    while (written < content.size()) {
        const ssize_t result = ::write(fd, content.constData() + written,
                                       static_cast<size_t>(content.size() - written));
        if (result <= 0)
            return false;
        written += result;
    }
    return true;
}
#endif
}

BootProgressState::BootProgressState(QString stateDirectory)
    : m_stateDirectory(stateDirectory.trimmed().isEmpty()
                           ? defaultStateDirectory()
                           : std::move(stateDirectory))
{
}

QString BootProgressState::defaultStateDirectory()
{
    const QString configured = qEnvironmentVariable("NEUTRONOS_BOOT_STATE_DIR").trimmed();
    return configured.isEmpty() ? QString::fromLatin1(kDefaultStateDirectory) : configured;
}

bool BootProgressState::ensureDirectory(QString *error) const
{
    if (!QDir().mkpath(m_stateDirectory)) {
        setError(error, QStringLiteral("cannot create boot state directory"));
        return false;
    }
#ifdef Q_OS_LINUX
    const QByteArray path = QFile::encodeName(m_stateDirectory);
    struct stat metadata{};
    if (::lstat(path.constData(), &metadata) != 0 || !S_ISDIR(metadata.st_mode)) {
        setError(error, QStringLiteral("boot state path is not a directory"));
        return false;
    }

    const gid_t group = stateGroup();
    const uid_t effectiveUser = ::geteuid();
    if (effectiveUser == 0 || metadata.st_uid == effectiveUser) {
        // Root creates the production directory; an unprivileged owner is
        // used only by isolated self-tests. Set the group before the mode
        // because chown may clear the setgid bit.
        if (group != static_cast<gid_t>(-1) &&
            ::chown(path.constData(), static_cast<uid_t>(-1), group) != 0) {
            setError(error, QStringLiteral("cannot set boot state directory group"));
            return false;
        }
        if (::chmod(path.constData(), 02770) != 0) {
            setError(error, QStringLiteral("cannot set boot state directory mode"));
            return false;
        }
    } else {
        // NeutronShell is deliberately not the owner. Accept the directory
        // created by the root renderer/state-setup service only when its
        // group and group-writable setgid contract are already intact.
        constexpr mode_t requiredMode = S_ISGID | S_IRWXG;
        if (group == static_cast<gid_t>(-1) || metadata.st_gid != group ||
            (metadata.st_mode & requiredMode) != requiredMode) {
            setError(error, QStringLiteral("boot state directory is not group-writable"));
            return false;
        }
    }
#endif
    return true;
}

bool BootProgressState::writeMarker(const QString &name, const QByteArray &content,
                                    QString *error) const
{
    if (name.isEmpty() || name.contains(QLatin1Char('/'))) {
        setError(error, QStringLiteral("invalid boot marker name"));
        return false;
    }
    if (!ensureDirectory(error))
        return false;

#ifdef Q_OS_LINUX
    const QString path = markerPath(name);
    const QString temporary = path + QStringLiteral(".tmp.%1").arg(::getpid());
    const QByteArray temporaryBytes = QFile::encodeName(temporary);
    const QByteArray pathBytes = QFile::encodeName(path);
    const int fd = ::open(temporaryBytes.constData(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC,
                          0660);
    if (fd < 0) {
        setError(error, QStringLiteral("cannot create boot marker %1").arg(name));
        return false;
    }
    const gid_t group = stateGroup();
    const bool metadataOk = ::fchmod(fd, 0660) == 0 &&
        (group == static_cast<gid_t>(-1) ||
         ::fchown(fd, static_cast<uid_t>(-1), group) == 0);
    const bool contentOk = metadataOk && writeAll(fd, content) && ::fsync(fd) == 0;
    ::close(fd);
    if (!contentOk || ::rename(temporaryBytes.constData(), pathBytes.constData()) != 0) {
        ::unlink(temporaryBytes.constData());
        setError(error, QStringLiteral("cannot publish boot marker %1").arg(name));
        return false;
    }
    return true;
#else
    Q_UNUSED(content)
    setError(error, QStringLiteral("boot state is supported only on Linux"));
    return false;
#endif
}

bool BootProgressState::appendEvent(int percent, const QString &milestone,
                                    QString *error) const
{
#ifdef Q_OS_LINUX
    const QByteArray path = QFile::encodeName(markerPath(QStringLiteral("events.tsv")));
    const int fd = ::open(path.constData(), O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0660);
    if (fd < 0) {
        setError(error, QStringLiteral("cannot open boot event log"));
        return false;
    }
    ::fchmod(fd, 0660);
    const gid_t group = stateGroup();
    if (group != static_cast<gid_t>(-1))
        ::fchown(fd, static_cast<uid_t>(-1), group);
    timespec now{};
    ::clock_gettime(CLOCK_BOOTTIME, &now);
    const qint64 milliseconds = static_cast<qint64>(now.tv_sec) * 1000 +
                                static_cast<qint64>(now.tv_nsec / 1000000);
    const QByteArray line = QByteArray::number(milliseconds) + '\t' +
                            QByteArray::number(percent) + '\t' +
                            milestone.toUtf8().replace('\n', ' ') + '\n';
    const bool ok = writeAll(fd, line);
    ::close(fd);
    if (!ok)
        setError(error, QStringLiteral("cannot append boot event"));
    return ok;
#else
    Q_UNUSED(percent)
    Q_UNUSED(milestone)
    setError(error, QStringLiteral("boot state is supported only on Linux"));
    return false;
#endif
}

bool BootProgressState::begin(QString *error) const
{
    if (!ensureDirectory(error))
        return false;
    if (!writeMarker(QStringLiteral("active"), QByteArrayLiteral("active\n"), error))
        return false;
    return advance(0, QStringLiteral("approved-visual-source-verified"), error);
}

bool BootProgressState::advance(int percent, const QString &milestone,
                                QString *error) const
{
    if (percent < 0 || percent > 100 || percent % 5 != 0 || milestone.trimmed().isEmpty()) {
        setError(error, QStringLiteral("invalid boot progress transition"));
        return false;
    }
    if (!ensureDirectory(error))
        return false;

#ifdef Q_OS_LINUX
    const QByteArray lockPath = QFile::encodeName(markerPath(QStringLiteral("progress.lock")));
    const int lockFd = ::open(lockPath.constData(), O_RDWR | O_CREAT | O_CLOEXEC, 0660);
    if (lockFd < 0 || ::flock(lockFd, LOCK_EX) != 0) {
        if (lockFd >= 0)
            ::close(lockFd);
        setError(error, QStringLiteral("cannot lock boot progress"));
        return false;
    }
    ::fchmod(lockFd, 0660);
    const gid_t group = stateGroup();
    if (group != static_cast<gid_t>(-1))
        ::fchown(lockFd, static_cast<uid_t>(-1), group);

    const int previous = progress();
    bool ok = true;
    if (percent > previous) {
        ok = writeMarker(QStringLiteral("progress"),
                         QByteArray::number(percent) + '\n', error) &&
             writeMarker(QStringLiteral("milestone"),
                         milestone.toUtf8() + '\n', error) &&
             appendEvent(percent, milestone, error);
    } else if (previous < 0 && percent == 0) {
        ok = writeMarker(QStringLiteral("progress"), QByteArrayLiteral("0\n"), error) &&
             writeMarker(QStringLiteral("milestone"), milestone.toUtf8() + '\n', error) &&
             appendEvent(percent, milestone, error);
    }
    ::flock(lockFd, LOCK_UN);
    ::close(lockFd);
    return ok;
#else
    Q_UNUSED(percent)
    Q_UNUSED(milestone)
    setError(error, QStringLiteral("boot state is supported only on Linux"));
    return false;
#endif
}

int BootProgressState::progress() const
{
    QFile file(markerPath(QStringLiteral("progress")));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return -1;
    bool valid = false;
    const int value = QString::fromLatin1(file.readAll()).trimmed().toInt(&valid);
    return valid ? value : -1;
}

bool BootProgressState::hasMarker(const QString &name) const
{
    return QFile::exists(markerPath(name));
}

bool BootProgressState::removeMarker(const QString &name) const
{
    return !hasMarker(name) || QFile::remove(markerPath(name));
}

QString BootProgressState::stateDirectory() const
{
    return m_stateDirectory;
}

QString BootProgressState::markerPath(const QString &name) const
{
    return QDir(m_stateDirectory).filePath(name);
}
