#include "FileManager.h"

#include <QClipboard>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QGuiApplication>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSet>
#include <QTemporaryDir>
#include <QTemporaryFile>
#include <QTextStream>
#include <QUrl>
#include <QtConcurrent/QtConcurrentRun>

#include <sodium.h>
#include <algorithm>
#include <cstring>

#ifdef Q_OS_LINUX
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace {
constexpr qint64 kPreviewBytes = 1024 * 1024;
constexpr qint64 kTextLimitBytes = 8 * 1024 * 1024;
constexpr qint64 kCryptoChunkBytes = 1024 * 1024;
const QByteArray kVaultMagic("NEUTRONVAULT1", 13);
const QByteArray kAesMagic("NEUTRONAESG1", 12);

QString cleanUserPath(const QString &path)
{
    QString value = path.trimmed();
    if (value.startsWith(QStringLiteral("file://")))
        value = QUrl(value).toLocalFile();
    if (value == QStringLiteral("~"))
        value = QDir::homePath();
    else if (value.startsWith(QStringLiteral("~/")))
        value = QDir::homePath() + value.mid(1);
    return QDir::cleanPath(value);
}

QString fileExtension(const QString &path)
{
    const QString lower = QFileInfo(path).fileName().toLower();
    if (lower.endsWith(QStringLiteral(".tar.gz"))) return QStringLiteral("tar.gz");
    if (lower.endsWith(QStringLiteral(".tar.xz"))) return QStringLiteral("tar.xz");
    if (lower.endsWith(QStringLiteral(".tar.bz2"))) return QStringLiteral("tar.bz2");
    return QFileInfo(lower).suffix().toLower();
}

bool textLikeExtension(const QString &path)
{
    static const QSet<QString> extensions = {
        QStringLiteral("txt"), QStringLiteral("md"), QStringLiteral("log"),
        QStringLiteral("py"), QStringLiteral("pyw"), QStringLiteral("cpp"),
        QStringLiteral("cc"), QStringLiteral("cxx"), QStringLiteral("c"),
        QStringLiteral("h"), QStringLiteral("hpp"), QStringLiteral("hh"),
        QStringLiteral("qml"), QStringLiteral("js"), QStringLiteral("mjs"),
        QStringLiteral("json"), QStringLiteral("jsonc"), QStringLiteral("xml"),
        QStringLiteral("yaml"), QStringLiteral("yml"), QStringLiteral("toml"),
        QStringLiteral("ini"), QStringLiteral("conf"), QStringLiteral("cfg"),
        QStringLiteral("sh"), QStringLiteral("bash"), QStringLiteral("zsh"),
        QStringLiteral("fish"), QStringLiteral("service"), QStringLiteral("socket"),
        QStringLiteral("timer"), QStringLiteral("target"), QStringLiteral("desktop"),
        QStringLiteral("html"), QStringLiteral("htm"), QStringLiteral("css"),
        QStringLiteral("scss"), QStringLiteral("sql"), QStringLiteral("csv"),
        QStringLiteral("tsv"), QStringLiteral("svg"), QStringLiteral("diff"),
        QStringLiteral("patch"), QStringLiteral("cmake"), QStringLiteral("pro"),
        QStringLiteral("pri"), QStringLiteral("gitignore"), QStringLiteral("env")
    };
    const QFileInfo info(path);
    const QString suffix = info.suffix().toLower();
    if (extensions.contains(suffix))
        return true;
    const QString name = info.fileName().toLower();
    return name == QStringLiteral("makefile") ||
           name == QStringLiteral("cmakelists.txt") ||
           name.startsWith(QStringLiteral("readme")) ||
           name.startsWith(QStringLiteral("license"));
}

QByteArray littleEndian32(quint32 value)
{
    QByteArray out(4, '\0');
    out[0] = char(value & 0xff);
    out[1] = char((value >> 8) & 0xff);
    out[2] = char((value >> 16) & 0xff);
    out[3] = char((value >> 24) & 0xff);
    return out;
}

bool readLittleEndian32(QFile &file, quint32 *value)
{
    const QByteArray bytes = file.read(4);
    if (bytes.size() != 4)
        return false;
    *value = quint32(quint8(bytes[0])) |
             (quint32(quint8(bytes[1])) << 8) |
             (quint32(quint8(bytes[2])) << 16) |
             (quint32(quint8(bytes[3])) << 24);
    return true;
}

QString shellSafeLabel(const QString &label)
{
    QString result = label.trimmed();
    result.remove(QChar::Null);
    return result.left(16);
}
}

FileManager::FileManager(QObject *parent)
    : QObject(parent),
      m_currentPath(QDir::homePath())
{
    if (sodium_init() < 0)
        setError(QStringLiteral("libsodium could not initialize."));

    loadQuickPlaces();
    loadTags();
    loadSftpConnections();

    if (QGuiApplication::clipboard()) {
        connect(QGuiApplication::clipboard(), &QClipboard::dataChanged,
                this, &FileManager::clipboardTextChanged);
    }
}

bool FileManager::ready() const { return m_ready; }
bool FileManager::busy() const { return m_busy; }
QString FileManager::error() const { return m_error; }
QString FileManager::currentPath() const { return m_currentPath; }
QString FileManager::homePath() const { return QDir::homePath(); }
QString FileManager::clipboardText() const
{
    return QGuiApplication::clipboard() ? QGuiApplication::clipboard()->text() : QString();
}
QString FileManager::clipboardPath() const { return m_clipboardPath; }
QString FileManager::clipboardMode() const { return m_clipboardMode; }
QStringList FileManager::supportedArchiveFormats() const
{
    QStringList formats{QStringLiteral("zip"), QStringLiteral("tar")};
    if (commandExists(QStringLiteral("gzip"))) formats << QStringLiteral("tar.gz");
    if (commandExists(QStringLiteral("xz"))) formats << QStringLiteral("tar.xz");
    if (commandExists(QStringLiteral("bzip2"))) formats << QStringLiteral("tar.bz2");
    if (commandExists(QStringLiteral("7z")) || commandExists(QStringLiteral("7zz")))
        formats << QStringLiteral("7z");
    return formats;
}
QVariantList FileManager::quickPlaces() const { return m_quickPlaces; }
QVariantList FileManager::tagDefinitions() const { return m_tagDefinitions; }
bool FileManager::sftpAvailable() const { return commandExists(QStringLiteral("sshfs")); }

QVariantList FileManager::sftpConnections() const
{
    QVariantList rows;
    for (const QVariant &value : m_sftpConnections) {
        QVariantMap row = value.toMap();
        const QString mountPath = row.value(QStringLiteral("mountPath")).toString();
        row.insert(QStringLiteral("connected"), isMountedPath(mountPath));
        rows.append(row);
    }
    return rows;
}

QStringList FileManager::supportedEncryptionMethods() const
{
    QStringList methods{QStringLiteral("xchacha20-poly1305")};
    if (crypto_aead_aes256gcm_is_available() != 0)
        methods << QStringLiteral("aes-256-gcm");
    if (commandExists(QStringLiteral("gpg")))
        methods << QStringLiteral("gpg-aes256");
    return methods;
}

void FileManager::initialize()
{
    setReady(true);
    loadDirectory(m_currentPath);
    emit capabilitiesChanged();
}

void FileManager::setReady(bool value)
{
    if (m_ready == value) return;
    m_ready = value;
    emit readyChanged();
}
void FileManager::setBusy(bool value)
{
    if (m_busy == value) return;
    m_busy = value;
    emit busyChanged();
}
void FileManager::setError(const QString &value)
{
    if (m_error == value) return;
    m_error = value;
    emit errorChanged();
}
void FileManager::setCurrentPath(const QString &value)
{
    const QString cleaned = QDir::cleanPath(value);
    if (m_currentPath == cleaned) return;
    m_currentPath = cleaned;
    emit currentPathChanged();
}

void FileManager::runTask(const QString &action,
                          const QString &path,
                          const std::function<TaskResult()> &task,
                          const std::function<void(const TaskResult &)> &finished)
{
    if (m_busy) {
        const QString message = QStringLiteral("Another file operation is still running.");
        setError(message);
        emit operationFailed(message);
        return;
    }

    setError(QString());
    setBusy(true);

    auto *watcher = new QFutureWatcher<TaskResult>(this);
    connect(watcher, &QFutureWatcher<TaskResult>::finished, this,
            [this, watcher, action, path, finished]() {
        const TaskResult result = watcher->result();
        watcher->deleteLater();
        setBusy(false);
        if (!result.ok) {
            const QString message = result.error.isEmpty()
                    ? QStringLiteral("%1 failed.").arg(action)
                    : result.error;
            setError(message);
            emit operationFailed(message);
            return;
        }
        setError(QString());
        if (finished)
            finished(result);
        else
            emit operationCompleted(result.action.isEmpty() ? action : result.action,
                                    result.path.isEmpty() ? path : result.path);
    });
    watcher->setFuture(QtConcurrent::run(task));
}

QString FileManager::normalizedExistingPath(const QString &path)
{
    const QString cleaned = cleanUserPath(path);
    const QFileInfo info(cleaned);
    if (!info.exists() && !info.isSymLink())
        return QString();
    return info.absoluteFilePath();
}

void FileManager::loadDirectory(const QString &path)
{
    const QString requested = cleanUserPath(path.isEmpty() ? QDir::homePath() : path);
    runTask(QStringLiteral("load-directory"), requested, [requested]() {
        TaskResult result;
        result.action = QStringLiteral("load-directory");
        result.path = requested;
        const QFileInfo rootInfo(requested);
        if (!rootInfo.exists() || !rootInfo.isDir()) {
            result.error = QStringLiteral("Directory does not exist: %1").arg(requested);
            return result;
        }
        QDir dir(requested);
        const QFileInfoList entries = dir.entryInfoList(
            QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
            QDir::DirsFirst | QDir::IgnoreCase | QDir::Name);
        QVariantList items;
        QMimeDatabase mimeDatabase;
        for (const QFileInfo &info : entries) {
            QVariantMap item;
            const QString mime = info.isDir()
                    ? QStringLiteral("inode/directory")
                    : mimeDatabase.mimeTypeForFile(info, QMimeDatabase::MatchExtension).name();
            item.insert(QStringLiteral("name"), info.fileName());
            item.insert(QStringLiteral("path"), info.absoluteFilePath());
            item.insert(QStringLiteral("type"), info.isDir() ? QStringLiteral("folder") : QStringLiteral("file"));
            item.insert(QStringLiteral("isDir"), info.isDir());
            item.insert(QStringLiteral("isDirectory"), info.isDir());
            item.insert(QStringLiteral("isSymlink"), info.isSymLink());
            item.insert(QStringLiteral("hidden"), info.isHidden());
            item.insert(QStringLiteral("size"), QVariant::fromValue<qulonglong>(info.size()));
            item.insert(QStringLiteral("sizeText"), info.isDir() ? QStringLiteral("Folder") : humanSize(info.size()));
            item.insert(QStringLiteral("modified"), info.lastModified());
            item.insert(QStringLiteral("modifiedText"), info.lastModified().toString(QStringLiteral("MMM d, yyyy  h:mm AP")));
            item.insert(QStringLiteral("extension"), fileExtension(info.fileName()));
            item.insert(QStringLiteral("mimeType"), mime);
            item.insert(QStringLiteral("readable"), info.isReadable());
            item.insert(QStringLiteral("writable"), info.isWritable());
            item.insert(QStringLiteral("executable"), info.isExecutable());
            item.insert(QStringLiteral("permissions"), permissionString(info));
            item.insert(QStringLiteral("icon"), iconForPath(info, mime));
            items.append(item);
        }
        result.ok = true;
        result.payload = items;
        return result;
    }, [this](const TaskResult &result) {
        setCurrentPath(result.path);
        emit directoryLoaded(result.path, result.payload.toList());
    });
}

void FileManager::refresh() { loadDirectory(m_currentPath); }

void FileManager::openPath(const QString &path)
{
    const QString existing = normalizedExistingPath(path);
    if (existing.isEmpty()) {
        const QString message = QStringLiteral("Path does not exist: %1").arg(path);
        setError(message);
        emit operationFailed(message);
        return;
    }
    const QFileInfo info(existing);
    if (info.isDir()) {
        loadDirectory(existing);
        return;
    }
    if (isEditable(existing)) {
        readTextFile(existing);
        return;
    }
    requestQuickLook(existing);
}

void FileManager::requestQuickLook(const QString &path)
{
    const QString existing = normalizedExistingPath(path);
    runTask(QStringLiteral("quick-look"), existing, [existing]() {
        TaskResult result;
        result.action = QStringLiteral("quick-look");
        result.path = existing;
        if (existing.isEmpty()) {
            result.error = QStringLiteral("The selected path no longer exists.");
            return result;
        }
        QString error;
        const QVariantMap preview = quickLookForPath(existing, &error);
        if (!error.isEmpty()) {
            result.error = error;
            return result;
        }
        result.ok = true;
        result.payload = preview;
        return result;
    }, [this](const TaskResult &result) {
        emit quickLookReady(result.path, result.payload.toMap());
    });
}

void FileManager::requestMetadata(const QString &path)
{
    const QString existing = normalizedExistingPath(path);
    runTask(QStringLiteral("metadata"), existing, [existing]() {
        TaskResult result;
        result.action = QStringLiteral("metadata");
        result.path = existing;
        if (existing.isEmpty()) {
            result.error = QStringLiteral("The selected path no longer exists.");
            return result;
        }
        result.ok = true;
        result.payload = metadataForPath(existing);
        return result;
    }, [this](const TaskResult &result) {
        emit metadataReady(result.path, result.payload.toMap());
    });
}

void FileManager::readTextFile(const QString &path, qint64 maximumBytes)
{
    const QString existing = normalizedExistingPath(path);
    const qint64 limit = qBound<qint64>(qint64{1}, maximumBytes, qint64{32} * 1024 * 1024);
    runTask(QStringLiteral("read-text"), existing, [existing, limit]() {
        TaskResult result;
        result.action = QStringLiteral("read-text");
        result.path = existing;
        QFile file(existing);
        if (!file.open(QIODevice::ReadOnly)) {
            result.error = QStringLiteral("Unable to read %1: %2").arg(existing, file.errorString());
            return result;
        }
        const bool truncated = file.size() > limit;
        QByteArray bytes = file.read(limit);
        if (bytes.startsWith("\xEF\xBB\xBF"))
            bytes.remove(0, 3);
        QVariantMap payload;
        payload.insert(QStringLiteral("text"), QString::fromUtf8(bytes));
        payload.insert(QStringLiteral("encoding"), QStringLiteral("UTF-8"));
        payload.insert(QStringLiteral("truncated"), truncated);
        result.ok = true;
        result.payload = payload;
        return result;
    }, [this](const TaskResult &result) {
        const QVariantMap payload = result.payload.toMap();
        emit textFileLoaded(result.path,
                            payload.value(QStringLiteral("text")).toString(),
                            payload.value(QStringLiteral("encoding")).toString(),
                            payload.value(QStringLiteral("truncated")).toBool());
    });
}

void FileManager::saveTextFile(const QString &path, const QString &text)
{
    const QString destination = cleanUserPath(path);
    runTask(QStringLiteral("save-text"), destination, [destination, text]() {
        TaskResult result;
        result.action = QStringLiteral("save-text");
        result.path = destination;
        const QFileInfo info(destination);
        if (!QDir().mkpath(info.absolutePath())) {
            result.error = QStringLiteral("Unable to create the destination directory.");
            return result;
        }
        QSaveFile file(destination);
        if (!file.open(QIODevice::WriteOnly)) {
            result.error = QStringLiteral("Unable to save %1: %2").arg(destination, file.errorString());
            return result;
        }
        const QByteArray bytes = text.toUtf8();
        if (file.write(bytes) != bytes.size() || !file.commit()) {
            result.error = QStringLiteral("Unable to commit %1: %2").arg(destination, file.errorString());
            return result;
        }
        result.ok = true;
        return result;
    });
}

void FileManager::createFolder(const QString &parentPath, const QString &folderName)
{
    const QString parent = cleanUserPath(parentPath);
    const QString name = QFileInfo(folderName.trimmed()).fileName();
    const QString destination = QDir(parent).filePath(name);
    runTask(QStringLiteral("create-folder"), destination, [destination, name]() {
        TaskResult result;
        result.action = QStringLiteral("create-folder");
        result.path = destination;
        if (name.isEmpty() || name == QStringLiteral(".") || name == QStringLiteral("..")) {
            result.error = QStringLiteral("Enter a valid folder name.");
            return result;
        }
        if (QFileInfo::exists(destination)) {
            result.error = QStringLiteral("An item with that name already exists.");
            return result;
        }
        if (!QDir().mkpath(destination)) {
            result.error = QStringLiteral("Unable to create folder: %1").arg(destination);
            return result;
        }
        result.ok = true;
        return result;
    });
}

void FileManager::createFile(const QString &parentPath,
                             const QString &fileName,
                             const QString &templateId)
{
    const QString parent = cleanUserPath(parentPath);
    const QString name = QFileInfo(fileName.trimmed()).fileName();
    const QString destination = QDir(parent).filePath(name);
    runTask(QStringLiteral("create-file"), destination, [destination, name, templateId]() {
        TaskResult result;
        result.action = QStringLiteral("create-file");
        result.path = destination;
        if (name.isEmpty() || name == QStringLiteral(".") || name == QStringLiteral("..")) {
            result.error = QStringLiteral("Enter a valid file name.");
            return result;
        }
        if (QFileInfo::exists(destination)) {
            result.error = QStringLiteral("An item with that name already exists.");
            return result;
        }
        QSaveFile file(destination);
        if (!file.open(QIODevice::WriteOnly)) {
            result.error = QStringLiteral("Unable to create %1: %2").arg(destination, file.errorString());
            return result;
        }
        QByteArray bytes;
        const QString extension = fileExtension(destination);
        if (extension == QStringLiteral("zip")) {
            bytes = QByteArray::fromHex("504b0506000000000000000000000000000000000000");
        } else if (extension == QStringLiteral("tar")) {
            bytes = QByteArray(1024, '\0');
        } else {
            bytes = templateContents(destination, templateId).toUtf8();
        }
        if (file.write(bytes) != bytes.size() || !file.commit()) {
            result.error = QStringLiteral("Unable to commit %1: %2").arg(destination, file.errorString());
            return result;
        }
        result.ok = true;
        return result;
    });
}

QString FileManager::destinationPathFor(const QString &sourcePath,
                                        const QString &destinationDirectory)
{
    const QFileInfo source(sourcePath);
    return QDir(cleanUserPath(destinationDirectory)).filePath(source.fileName());
}

QString FileManager::uniquePath(const QString &desiredPath)
{
    if (!QFileInfo::exists(desiredPath))
        return desiredPath;
    const QFileInfo info(desiredPath);
    const QString directory = info.absolutePath();
    const QString completeSuffix = info.completeSuffix();
    const QString base = completeSuffix.isEmpty()
            ? info.fileName()
            : info.fileName().left(info.fileName().size() - completeSuffix.size() - 1);
    for (int index = 2; index < 10000; ++index) {
        const QString candidateName = completeSuffix.isEmpty()
                ? QStringLiteral("%1 copy %2").arg(base).arg(index)
                : QStringLiteral("%1 copy %2.%3").arg(base).arg(index).arg(completeSuffix);
        const QString candidate = QDir(directory).filePath(candidateName);
        if (!QFileInfo::exists(candidate))
            return candidate;
    }
    return desiredPath + QStringLiteral(".") + QString::number(QDateTime::currentMSecsSinceEpoch());
}

bool FileManager::copyRecursively(const QString &sourcePath,
                                  const QString &destinationPath,
                                  QString *error)
{
    const QFileInfo sourceInfo(sourcePath);
    if (!sourceInfo.exists() && !sourceInfo.isSymLink()) {
        *error = QStringLiteral("Source does not exist: %1").arg(sourcePath);
        return false;
    }
    if (sourceInfo.isSymLink()) {
        const QString target = sourceInfo.symLinkTarget();
        if (!QFile::link(target, destinationPath)) {
            *error = QStringLiteral("Unable to copy symbolic link %1").arg(sourcePath);
            return false;
        }
        return true;
    }
    if (sourceInfo.isFile()) {
        if (!QDir().mkpath(QFileInfo(destinationPath).absolutePath()) ||
                !QFile::copy(sourcePath, destinationPath)) {
            *error = QStringLiteral("Unable to copy %1 to %2").arg(sourcePath, destinationPath);
            return false;
        }
        QFile::setPermissions(destinationPath, sourceInfo.permissions());
        return true;
    }
    if (!QDir().mkpath(destinationPath)) {
        *error = QStringLiteral("Unable to create %1").arg(destinationPath);
        return false;
    }
    QDir sourceDir(sourcePath);
    const QFileInfoList children = sourceDir.entryInfoList(
        QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
        QDir::DirsFirst | QDir::Name);
    for (const QFileInfo &child : children) {
        const QString destinationChild = QDir(destinationPath).filePath(child.fileName());
        if (!copyRecursively(child.absoluteFilePath(), destinationChild, error))
            return false;
    }
    QFile::setPermissions(destinationPath, sourceInfo.permissions());
    return true;
}

bool FileManager::removeSafely(const QString &path, QString *error)
{
    const QFileInfo info(path);
    if (!info.exists() && !info.isSymLink()) {
        *error = QStringLiteral("Path does not exist: %1").arg(path);
        return false;
    }
    if (info.isDir() && !info.isSymLink()) {
        QDir dir(path);
        if (!dir.removeRecursively()) {
            *error = QStringLiteral("Unable to remove directory: %1").arg(path);
            return false;
        }
        return true;
    }
    if (!QFile::remove(path)) {
        *error = QStringLiteral("Unable to remove file: %1").arg(path);
        return false;
    }
    return true;
}

bool FileManager::moveSafely(const QString &sourcePath,
                             const QString &destinationPath,
                             QString *error)
{
    if (QFile::rename(sourcePath, destinationPath))
        return true;
    if (!copyRecursively(sourcePath, destinationPath, error))
        return false;
    if (!removeSafely(sourcePath, error)) {
        QString cleanupError;
        removeSafely(destinationPath, &cleanupError);
        return false;
    }
    return true;
}

void FileManager::copyPath(const QString &sourcePath, const QString &destinationDirectory)
{
    const QString source = normalizedExistingPath(sourcePath);
    const QString directory = cleanUserPath(destinationDirectory);
    const QString destination = destinationPathFor(source, directory);
    runTask(QStringLiteral("copy"), destination, [source, directory, destination]() {
        TaskResult result;
        result.action = QStringLiteral("copy");
        result.path = destination;
        if (source.isEmpty()) {
            result.error = QStringLiteral("The source item no longer exists.");
            return result;
        }
        if (!QFileInfo(directory).isDir()) {
            result.error = QStringLiteral("Destination is not a directory: %1").arg(directory);
            return result;
        }
        if (QFileInfo::exists(destination)) {
            result.error = QStringLiteral("An item named %1 already exists in the destination.")
                    .arg(QFileInfo(destination).fileName());
            return result;
        }
        const QString canonicalSource = QFileInfo(source).canonicalFilePath();
        const QString canonicalDestination = QFileInfo(directory).canonicalFilePath();
        if (QFileInfo(source).isDir() &&
                (canonicalDestination == canonicalSource ||
                 canonicalDestination.startsWith(canonicalSource + QLatin1Char('/')))) {
            result.error = QStringLiteral("A folder cannot be copied inside itself.");
            return result;
        }
        QString error;
        if (!copyRecursively(source, destination, &error)) {
            result.error = error;
            return result;
        }
        result.ok = true;
        return result;
    });
}

void FileManager::movePath(const QString &sourcePath, const QString &destinationDirectory)
{
    const QString source = normalizedExistingPath(sourcePath);
    const QString directory = cleanUserPath(destinationDirectory);
    const QString destination = destinationPathFor(source, directory);
    runTask(QStringLiteral("move"), destination, [source, directory, destination]() {
        TaskResult result;
        result.action = QStringLiteral("move");
        result.path = destination;
        if (source.isEmpty()) {
            result.error = QStringLiteral("The source item no longer exists.");
            return result;
        }
        if (!QFileInfo(directory).isDir()) {
            result.error = QStringLiteral("Destination is not a directory: %1").arg(directory);
            return result;
        }
        if (QFileInfo::exists(destination)) {
            result.error = QStringLiteral("An item named %1 already exists in the destination.")
                    .arg(QFileInfo(destination).fileName());
            return result;
        }
        const QString canonicalSource = QFileInfo(source).canonicalFilePath();
        const QString canonicalDestination = QFileInfo(directory).canonicalFilePath();
        if (QFileInfo(source).isDir() &&
                (canonicalDestination == canonicalSource ||
                 canonicalDestination.startsWith(canonicalSource + QLatin1Char('/')))) {
            result.error = QStringLiteral("A folder cannot be moved inside itself.");
            return result;
        }
        QString error;
        if (!moveSafely(source, destination, &error)) {
            result.error = error;
            return result;
        }
        result.ok = true;
        return result;
    });
}

void FileManager::renamePath(const QString &path, const QString &newName)
{
    const QString source = normalizedExistingPath(path);
    const QString safeName = QFileInfo(newName.trimmed()).fileName();
    const QString destination = QDir(QFileInfo(source).absolutePath()).filePath(safeName);
    runTask(QStringLiteral("rename"), destination, [source, safeName, destination]() {
        TaskResult result;
        result.action = QStringLiteral("rename");
        result.path = destination;
        if (source.isEmpty() || safeName.isEmpty() || safeName == QStringLiteral(".") || safeName == QStringLiteral("..")) {
            result.error = QStringLiteral("Enter a valid new name.");
            return result;
        }
        if (QFileInfo::exists(destination)) {
            result.error = QStringLiteral("An item with that name already exists.");
            return result;
        }
        if (!QFile::rename(source, destination)) {
            result.error = QStringLiteral("Unable to rename %1").arg(source);
            return result;
        }
        result.ok = true;
        return result;
    });
}

void FileManager::duplicatePath(const QString &path)
{
    const QString source = normalizedExistingPath(path);
    const QString destination = uniquePath(source);
    runTask(QStringLiteral("duplicate"), destination, [source, destination]() {
        TaskResult result;
        result.action = QStringLiteral("duplicate");
        result.path = destination;
        QString error;
        if (source.isEmpty() || !copyRecursively(source, destination, &error)) {
            result.error = source.isEmpty() ? QStringLiteral("The item no longer exists.") : error;
            return result;
        }
        result.ok = true;
        return result;
    });
}

void FileManager::deletePath(const QString &path)
{
    const QString source = normalizedExistingPath(path);
    runTask(QStringLiteral("trash"), source, [source]() {
        TaskResult result;
        result.action = QStringLiteral("trash");
        result.path = source;
        if (source.isEmpty()) {
            result.error = QStringLiteral("The item no longer exists.");
            return result;
        }
        const QString trashRoot = QDir::homePath() + QStringLiteral("/.local/share/Trash");
        const QString filesRoot = trashRoot + QStringLiteral("/files");
        const QString infoRoot = trashRoot + QStringLiteral("/info");
        if (!QDir().mkpath(filesRoot) || !QDir().mkpath(infoRoot)) {
            result.error = QStringLiteral("Unable to create the desktop Trash folders.");
            return result;
        }
        const QString trashPath = uniquePath(QDir(filesRoot).filePath(QFileInfo(source).fileName()));
        QString error;
        if (!moveSafely(source, trashPath, &error)) {
            result.error = error;
            return result;
        }
        const QString infoName = QFileInfo(trashPath).fileName() + QStringLiteral(".trashinfo");
        QSaveFile infoFile(QDir(infoRoot).filePath(infoName));
        if (infoFile.open(QIODevice::WriteOnly)) {
            const QString encoded = QString::fromUtf8(QUrl::toPercentEncoding(source, QByteArray("/")));
            const QString contents = QStringLiteral("[Trash Info]\nPath=%1\nDeletionDate=%2\n")
                    .arg(encoded, QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss")));
            infoFile.write(contents.toUtf8());
            infoFile.commit();
        }
        result.path = trashPath;
        result.ok = true;
        return result;
    });
}

void FileManager::setClipboardPath(const QString &path, const QString &mode)
{
    const QString existing = normalizedExistingPath(path);
    if (existing.isEmpty()) {
        const QString message = QStringLiteral("The selected item no longer exists.");
        setError(message);
        emit operationFailed(message);
        return;
    }
    m_clipboardPath = existing;
    m_clipboardMode = mode.toLower() == QStringLiteral("move")
            ? QStringLiteral("move") : QStringLiteral("copy");
    emit clipboardPathChanged();
    emit operationCompleted(QStringLiteral("clipboard-%1").arg(m_clipboardMode), existing);
}

void FileManager::clearClipboardPath()
{
    if (m_clipboardPath.isEmpty() && m_clipboardMode.isEmpty()) return;
    m_clipboardPath.clear();
    m_clipboardMode.clear();
    emit clipboardPathChanged();
}

void FileManager::pasteClipboardPath(const QString &destinationDirectory)
{
    if (m_clipboardPath.isEmpty()) {
        const QString message = QStringLiteral("No file or folder is on the File Manager clipboard.");
        setError(message);
        emit operationFailed(message);
        return;
    }
    if (m_clipboardMode == QStringLiteral("move"))
        movePath(m_clipboardPath, destinationDirectory);
    else
        copyPath(m_clipboardPath, destinationDirectory);
}

void FileManager::copyText(const QString &text)
{
    if (QGuiApplication::clipboard())
        QGuiApplication::clipboard()->setText(text);
}
QString FileManager::pasteText() const { return clipboardText(); }

QString FileManager::archiveFormatForPath(const QString &path)
{
    return fileExtension(path);
}

bool FileManager::runProcess(const QString &program,
                             const QStringList &arguments,
                             const QString &workingDirectory,
                             const QByteArray &stdinData,
                             QByteArray *stdoutData,
                             QByteArray *stderrData,
                             int timeoutMs)
{
    QProcess process;
    if (!workingDirectory.isEmpty())
        process.setWorkingDirectory(workingDirectory);
    process.start(program, arguments, QIODevice::ReadWrite);
    if (!process.waitForStarted(5000)) {
        if (stderrData) *stderrData = process.errorString().toUtf8();
        return false;
    }
    if (!stdinData.isEmpty()) {
        process.write(stdinData);
        process.closeWriteChannel();
    }
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(3000);
        if (stderrData) *stderrData = QByteArray("Operation timed out.");
        return false;
    }
    if (stdoutData) *stdoutData = process.readAllStandardOutput();
    if (stderrData) *stderrData = process.readAllStandardError();
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}

bool FileManager::commandExists(const QString &program)
{
    return !QStandardPaths::findExecutable(program).isEmpty();
}

bool FileManager::createArchive(const QStringList &sourcePaths,
                                const QString &destinationArchive,
                                const QString &format,
                                QString *error)
{
    if (sourcePaths.isEmpty()) {
        *error = QStringLiteral("Select at least one item to compress.");
        return false;
    }
    const QString normalizedFormat = format.toLower();
    QString program;
    QStringList arguments;
    QString workingDirectory;
    const QString firstParent = QFileInfo(sourcePaths.first()).absolutePath();
    bool commonParent = true;
    for (const QString &source : sourcePaths) {
        if (QFileInfo(source).absolutePath() != firstParent) {
            commonParent = false;
            break;
        }
    }
    if (commonParent)
        workingDirectory = firstParent;

    if (normalizedFormat == QStringLiteral("zip")) {
        if (commandExists(QStringLiteral("zip"))) {
            program = QStringLiteral("zip");
            arguments << QStringLiteral("-r") << destinationArchive;
            for (const QString &source : sourcePaths)
                arguments << (commonParent ? QFileInfo(source).fileName() : QFileInfo(source).absoluteFilePath());
        } else if (commandExists(QStringLiteral("python3"))) {
            program = QStringLiteral("python3");
            arguments << QStringLiteral("-c")
                      << QStringLiteral(
                             "import os,sys,zipfile\n"
                             "dest=sys.argv[1]\n"
                             "sources=sys.argv[2:]\n"
                             "with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,allowZip64=True) as z:\n"
                             "  for src in sources:\n"
                             "    src=os.path.normpath(src); parent=os.path.dirname(src) or '.'\n"
                             "    if os.path.isdir(src):\n"
                             "      wrote=False\n"
                             "      for base,dirs,files in os.walk(src):\n"
                             "        rel=os.path.relpath(base,parent)\n"
                             "        if not files and not dirs: z.writestr(rel.rstrip('/')+'/',b'')\n"
                             "        for name in files:\n"
                             "          full=os.path.join(base,name); z.write(full,os.path.relpath(full,parent)); wrote=True\n"
                             "    else: z.write(src,os.path.basename(src))\n")
                      << destinationArchive;
            for (const QString &source : sourcePaths)
                arguments << (commonParent ? QFileInfo(source).fileName() : QFileInfo(source).absoluteFilePath());
        } else {
            *error = QStringLiteral("ZIP support requires either zip or python3.");
            return false;
        }
    } else if (normalizedFormat == QStringLiteral("7z")) {
        program = commandExists(QStringLiteral("7zz")) ? QStringLiteral("7zz") : QStringLiteral("7z");
        if (!commandExists(program)) {
            *error = QStringLiteral("The 7-Zip package is not installed.");
            return false;
        }
        arguments << QStringLiteral("a") << QStringLiteral("-t7z") << destinationArchive;
        for (const QString &source : sourcePaths)
            arguments << (commonParent ? QFileInfo(source).fileName() : QFileInfo(source).absoluteFilePath());
    } else {
        program = QStringLiteral("tar");
        workingDirectory.clear();
        if (!commandExists(program)) {
            *error = QStringLiteral("The tar package is not installed.");
            return false;
        }
        if (normalizedFormat == QStringLiteral("tar.gz"))
            arguments << QStringLiteral("-czf");
        else if (normalizedFormat == QStringLiteral("tar.xz"))
            arguments << QStringLiteral("-cJf");
        else if (normalizedFormat == QStringLiteral("tar.bz2"))
            arguments << QStringLiteral("-cjf");
        else
            arguments << QStringLiteral("-cf");
        arguments << destinationArchive;
        for (const QString &source : sourcePaths) {
            const QFileInfo info(source);
            arguments << QStringLiteral("-C") << info.absolutePath() << info.fileName();
        }
    }
    QByteArray out;
    QByteArray err;
    if (!runProcess(program, arguments, workingDirectory, QByteArray(), &out, &err, 30 * 60 * 1000)) {
        *error = QStringLiteral("Compression failed: %1").arg(QString::fromUtf8(err).trimmed());
        return false;
    }
    return true;
}

bool FileManager::unpackArchive(const QString &archivePath,
                                const QString &destinationDirectory,
                                QString *error)
{
    if (!QDir().mkpath(destinationDirectory)) {
        *error = QStringLiteral("Unable to create extraction directory.");
        return false;
    }

    QString listError;
    const QVariantList listedEntries = archiveEntries(archivePath, &listError);
    if (!listError.isEmpty()) {
        *error = listError;
        return false;
    }
    for (const QVariant &value : listedEntries) {
        QString name = value.toMap().value(QStringLiteral("name")).toString();
        name.replace(QLatin1Char('\\'), QLatin1Char('/'));
        const QString cleaned = QDir::cleanPath(name);
        if (name.startsWith(QLatin1Char('/')) ||
                QRegularExpression(QStringLiteral("^[A-Za-z]:")).match(name).hasMatch() ||
                cleaned == QStringLiteral("..") || cleaned.startsWith(QStringLiteral("../")) ||
                cleaned.contains(QStringLiteral("/../"))) {
            *error = QStringLiteral("Archive contains an unsafe path and was not extracted: %1").arg(name);
            return false;
        }
    }

    const QString format = archiveFormatForPath(archivePath);
    QString program;
    QStringList arguments;
    if (format == QStringLiteral("zip")) {
        if (commandExists(QStringLiteral("unzip"))) {
            program = QStringLiteral("unzip");
            arguments << QStringLiteral("-o") << archivePath << QStringLiteral("-d") << destinationDirectory;
        } else if (commandExists(QStringLiteral("python3"))) {
            program = QStringLiteral("python3");
            arguments << QStringLiteral("-c")
                      << QStringLiteral("import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])")
                      << archivePath << destinationDirectory;
        } else {
            *error = QStringLiteral("ZIP extraction requires either unzip or python3.");
            return false;
        }
    } else if (format == QStringLiteral("7z")) {
        program = commandExists(QStringLiteral("7zz")) ? QStringLiteral("7zz") : QStringLiteral("7z");
        arguments << QStringLiteral("x") << QStringLiteral("-y")
                  << QStringLiteral("-o%1").arg(destinationDirectory) << archivePath;
    } else {
        program = QStringLiteral("tar");
        arguments << QStringLiteral("-xf") << archivePath << QStringLiteral("-C") << destinationDirectory;
    }
    if (!commandExists(program)) {
        *error = QStringLiteral("Required extraction tool is not installed: %1").arg(program);
        return false;
    }
    QByteArray out;
    QByteArray err;
    if (!runProcess(program, arguments, QString(), QByteArray(), &out, &err, 30 * 60 * 1000)) {
        *error = QStringLiteral("Extraction failed: %1").arg(QString::fromUtf8(err).trimmed());
        return false;
    }
    return true;
}

QVariantList FileManager::archiveEntries(const QString &archivePath, QString *error)
{
    const QString format = archiveFormatForPath(archivePath);
    QString program;
    QStringList arguments;
    const bool sevenZip = format == QStringLiteral("7z");
    if (format == QStringLiteral("zip")) {
        if (commandExists(QStringLiteral("unzip"))) {
            program = QStringLiteral("unzip");
            arguments << QStringLiteral("-Z1") << archivePath;
        } else if (commandExists(QStringLiteral("python3"))) {
            program = QStringLiteral("python3");
            arguments << QStringLiteral("-c")
                      << QStringLiteral("import sys,zipfile; print('\\n'.join(zipfile.ZipFile(sys.argv[1]).namelist()))")
                      << archivePath;
        } else {
            *error = QStringLiteral("ZIP listing requires either unzip or python3.");
            return {};
        }
    } else if (sevenZip) {
        program = commandExists(QStringLiteral("7zz")) ? QStringLiteral("7zz") : QStringLiteral("7z");
        arguments << QStringLiteral("l") << QStringLiteral("-slt") << archivePath;
    } else {
        program = QStringLiteral("tar");
        arguments << QStringLiteral("-tf") << archivePath;
    }
    QByteArray out;
    QByteArray err;
    if (!commandExists(program) ||
            !runProcess(program, arguments, QString(), QByteArray(), &out, &err, 120000)) {
        *error = QStringLiteral("Unable to list archive: %1").arg(QString::fromUtf8(err).trimmed());
        return {};
    }
    QVariantList entries;
    const QStringList lines = QString::fromUtf8(out).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &rawLine : lines) {
        QString name;
        if (sevenZip) {
            if (!rawLine.startsWith(QStringLiteral("Path = ")))
                continue;
            name = rawLine.mid(7).trimmed();
            if (QFileInfo(name).absoluteFilePath() == QFileInfo(archivePath).absoluteFilePath())
                continue;
        } else {
            name = rawLine.trimmed();
        }
        if (name.isEmpty())
            continue;
        QVariantMap entry;
        entry.insert(QStringLiteral("name"), name);
        entries.append(entry);
        if (entries.size() >= 500)
            break;
    }
    return entries;
}

void FileManager::compressPaths(const QStringList &sourcePaths,
                                const QString &destinationArchive,
                                const QString &format)
{
    QStringList sources;
    for (const QString &source : sourcePaths) {
        const QString existing = normalizedExistingPath(source);
        if (!existing.isEmpty()) sources << existing;
    }
    const QString destination = cleanUserPath(destinationArchive);
    const QString archiveFormat = format.toLower();
    runTask(QStringLiteral("compress"), destination, [sources, destination, archiveFormat]() {
        TaskResult result;
        result.action = QStringLiteral("compress");
        result.path = destination;
        if (QFileInfo::exists(destination)) {
            result.error = QStringLiteral("The destination archive already exists.");
            return result;
        }
        const QString destinationParent = QFileInfo(destination).absolutePath();
        for (const QString &source : sources) {
            if (!QFileInfo(source).isDir())
                continue;
            const QString canonicalSource = QFileInfo(source).canonicalFilePath();
            const QString canonicalParent = QFileInfo(destinationParent).canonicalFilePath();
            if (!canonicalSource.isEmpty() &&
                    (canonicalParent == canonicalSource ||
                     canonicalParent.startsWith(canonicalSource + QLatin1Char('/')))) {
                result.error = QStringLiteral("An archive cannot be created inside the folder being compressed.");
                return result;
            }
        }
        QString error;
        if (!createArchive(sources, destination, archiveFormat, &error)) {
            result.error = error;
            return result;
        }
        result.ok = true;
        return result;
    });
}

void FileManager::extractArchive(const QString &archivePath,
                                 const QString &destinationDirectory)
{
    const QString source = normalizedExistingPath(archivePath);
    const QString destination = cleanUserPath(destinationDirectory);
    runTask(QStringLiteral("extract"), destination, [source, destination]() {
        TaskResult result;
        result.action = QStringLiteral("extract");
        result.path = destination;
        if (source.isEmpty()) {
            result.error = QStringLiteral("Archive does not exist.");
            return result;
        }
        QString error;
        if (!unpackArchive(source, destination, &error)) {
            result.error = error;
            return result;
        }
        result.ok = true;
        return result;
    });
}

void FileManager::listArchive(const QString &archivePath)
{
    const QString source = normalizedExistingPath(archivePath);
    runTask(QStringLiteral("list-archive"), source, [source]() {
        TaskResult result;
        result.action = QStringLiteral("list-archive");
        result.path = source;
        QString error;
        const QVariantList entries = archiveEntries(source, &error);
        if (!error.isEmpty()) {
            result.error = error;
            return result;
        }
        result.ok = true;
        result.payload = entries;
        return result;
    }, [this](const TaskResult &result) {
        emit archiveListed(result.path, result.payload.toList());
    });
}

bool FileManager::encryptXChaCha(const QString &sourcePath,
                                 const QString &destinationPath,
                                 const QString &password,
                                 QString *finalPath,
                                 QString *error)
{
    if (password.size() < 8) {
        *error = QStringLiteral("Encryption passwords must contain at least 8 characters.");
        return false;
    }
    const QFileInfo sourceInfo(sourcePath);
    QTemporaryDir temporary;
    QString inputPath = sourcePath;
    bool archivedDirectory = false;
    if (sourceInfo.isDir()) {
        if (!temporary.isValid()) {
            *error = QStringLiteral("Unable to create temporary encryption workspace.");
            return false;
        }
        inputPath = temporary.filePath(QStringLiteral("payload.tar"));
        if (!createArchive(QStringList{sourcePath}, inputPath, QStringLiteral("tar"), error))
            return false;
        archivedDirectory = true;
    }
    QString outputPath = cleanUserPath(destinationPath);
    if (QFileInfo(outputPath).isDir())
        outputPath = QDir(outputPath).filePath(sourceInfo.fileName() + QStringLiteral(".nenc"));
    if (QFileInfo::exists(outputPath)) {
        *error = QStringLiteral("Encrypted destination already exists.");
        return false;
    }
    QFile input(inputPath);
    QSaveFile output(outputPath);
    if (!input.open(QIODevice::ReadOnly) || !output.open(QIODevice::WriteOnly)) {
        *error = QStringLiteral("Unable to open encryption input or destination.");
        return false;
    }
    unsigned char salt[crypto_pwhash_SALTBYTES];
    randombytes_buf(salt, sizeof salt);
    unsigned char key[crypto_secretstream_xchacha20poly1305_KEYBYTES];
    const QByteArray passwordBytes = password.toUtf8();
    if (crypto_pwhash(key, sizeof key,
                      passwordBytes.constData(), static_cast<unsigned long long>(passwordBytes.size()),
                      salt, crypto_pwhash_OPSLIMIT_MODERATE, crypto_pwhash_MEMLIMIT_MODERATE,
                      crypto_pwhash_ALG_DEFAULT) != 0) {
        sodium_memzero(key, sizeof key);
        *error = QStringLiteral("Not enough memory to derive the encryption key.");
        return false;
    }
    crypto_secretstream_xchacha20poly1305_state state;
    unsigned char streamHeader[crypto_secretstream_xchacha20poly1305_HEADERBYTES];
    crypto_secretstream_xchacha20poly1305_init_push(&state, streamHeader, key);
    sodium_memzero(key, sizeof key);

    QJsonObject metadata;
    metadata.insert(QStringLiteral("name"), sourceInfo.fileName());
    metadata.insert(QStringLiteral("directory"), sourceInfo.isDir());
    metadata.insert(QStringLiteral("archivedDirectory"), archivedDirectory);
    metadata.insert(QStringLiteral("created"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    const QByteArray metadataBytes = QJsonDocument(metadata).toJson(QJsonDocument::Compact);

    output.write(kVaultMagic);
    output.write(reinterpret_cast<const char *>(salt), sizeof salt);
    output.write(reinterpret_cast<const char *>(streamHeader), sizeof streamHeader);
    output.write(littleEndian32(static_cast<quint32>(metadataBytes.size())));
    output.write(metadataBytes);

    QByteArray plain(kCryptoChunkBytes, '\0');
    QByteArray cipher(kCryptoChunkBytes + crypto_secretstream_xchacha20poly1305_ABYTES, '\0');
    while (true) {
        const qint64 count = input.read(plain.data(), plain.size());
        if (count < 0) {
            *error = input.errorString();
            return false;
        }
        const bool finalChunk = input.atEnd();
        unsigned long long cipherSize = 0;
        crypto_secretstream_xchacha20poly1305_push(
            &state,
            reinterpret_cast<unsigned char *>(cipher.data()), &cipherSize,
            reinterpret_cast<const unsigned char *>(plain.constData()),
            static_cast<unsigned long long>(count),
            nullptr, 0,
            finalChunk ? crypto_secretstream_xchacha20poly1305_TAG_FINAL : 0);
        output.write(littleEndian32(static_cast<quint32>(cipherSize)));
        if (output.write(cipher.constData(), static_cast<qint64>(cipherSize)) != static_cast<qint64>(cipherSize)) {
            *error = output.errorString();
            return false;
        }
        if (finalChunk) break;
    }
    if (!output.commit()) {
        *error = output.errorString();
        return false;
    }
    *finalPath = outputPath;
    return true;
}

bool FileManager::decryptXChaCha(const QString &sourcePath,
                                 const QString &destinationPath,
                                 const QString &password,
                                 QString *finalPath,
                                 QString *error)
{
    QFile input(sourcePath);
    if (!input.open(QIODevice::ReadOnly)) {
        *error = input.errorString();
        return false;
    }
    if (input.read(kVaultMagic.size()) != kVaultMagic) {
        *error = QStringLiteral("This is not a NeutronOS encrypted container.");
        return false;
    }
    QByteArray salt = input.read(crypto_pwhash_SALTBYTES);
    QByteArray streamHeader = input.read(crypto_secretstream_xchacha20poly1305_HEADERBYTES);
    quint32 metadataSize = 0;
    if (salt.size() != crypto_pwhash_SALTBYTES ||
            streamHeader.size() != crypto_secretstream_xchacha20poly1305_HEADERBYTES ||
            !readLittleEndian32(input, &metadataSize) || metadataSize > 1024 * 1024) {
        *error = QStringLiteral("Encrypted container header is damaged.");
        return false;
    }
    const QByteArray metadataBytes = input.read(metadataSize);
    const QJsonObject metadata = QJsonDocument::fromJson(metadataBytes).object();
    const QString originalName = metadata.value(QStringLiteral("name")).toString(QStringLiteral("decrypted-file"));
    const bool archivedDirectory = metadata.value(QStringLiteral("archivedDirectory")).toBool();

    unsigned char key[crypto_secretstream_xchacha20poly1305_KEYBYTES];
    const QByteArray passwordBytes = password.toUtf8();
    if (crypto_pwhash(key, sizeof key,
                      passwordBytes.constData(), static_cast<unsigned long long>(passwordBytes.size()),
                      reinterpret_cast<const unsigned char *>(salt.constData()),
                      crypto_pwhash_OPSLIMIT_MODERATE, crypto_pwhash_MEMLIMIT_MODERATE,
                      crypto_pwhash_ALG_DEFAULT) != 0) {
        sodium_memzero(key, sizeof key);
        *error = QStringLiteral("Not enough memory to derive the decryption key.");
        return false;
    }
    crypto_secretstream_xchacha20poly1305_state state;
    if (crypto_secretstream_xchacha20poly1305_init_pull(
            &state,
            reinterpret_cast<const unsigned char *>(streamHeader.constData()), key) != 0) {
        sodium_memzero(key, sizeof key);
        *error = QStringLiteral("Encrypted container header authentication failed.");
        return false;
    }
    sodium_memzero(key, sizeof key);

    QTemporaryDir temporary;
    QString requestedDestination = cleanUserPath(destinationPath);
    QString outputPath;
    if (archivedDirectory) {
        if (!temporary.isValid()) {
            *error = QStringLiteral("Unable to create decryption workspace.");
            return false;
        }
        outputPath = temporary.filePath(QStringLiteral("payload.tar"));
    } else if (QFileInfo(requestedDestination).isDir()) {
        outputPath = QDir(requestedDestination).filePath(originalName);
    } else {
        outputPath = requestedDestination;
    }
    if (outputPath.isEmpty())
        outputPath = QDir(QFileInfo(sourcePath).absolutePath()).filePath(originalName);
    if (!archivedDirectory && QFileInfo::exists(outputPath)) {
        *error = QStringLiteral("Decrypted destination already exists.");
        return false;
    }
    QSaveFile output(outputPath);
    if (!output.open(QIODevice::WriteOnly)) {
        *error = output.errorString();
        return false;
    }
    bool sawFinal = false;
    while (!input.atEnd()) {
        quint32 cipherSize = 0;
        if (!readLittleEndian32(input, &cipherSize) ||
                cipherSize < crypto_secretstream_xchacha20poly1305_ABYTES ||
                cipherSize > kCryptoChunkBytes + crypto_secretstream_xchacha20poly1305_ABYTES) {
            *error = QStringLiteral("Encrypted data stream is damaged.");
            return false;
        }
        const QByteArray cipher = input.read(cipherSize);
        if (cipher.size() != static_cast<int>(cipherSize)) {
            *error = QStringLiteral("Encrypted data stream ended unexpectedly.");
            return false;
        }
        QByteArray plain(cipherSize, '\0');
        unsigned long long plainSize = 0;
        unsigned char tag = 0;
        if (crypto_secretstream_xchacha20poly1305_pull(
                &state,
                reinterpret_cast<unsigned char *>(plain.data()), &plainSize, &tag,
                reinterpret_cast<const unsigned char *>(cipher.constData()), cipherSize,
                nullptr, 0) != 0) {
            *error = QStringLiteral("Password is incorrect or the encrypted data was modified.");
            return false;
        }
        if (output.write(plain.constData(), static_cast<qint64>(plainSize)) != static_cast<qint64>(plainSize)) {
            *error = output.errorString();
            return false;
        }
        if (tag == crypto_secretstream_xchacha20poly1305_TAG_FINAL) {
            sawFinal = true;
            if (!input.atEnd()) {
                *error = QStringLiteral("Unexpected data follows the authenticated stream.");
                return false;
            }
        }
    }
    if (!sawFinal) {
        *error = QStringLiteral("Encrypted stream is incomplete.");
        return false;
    }
    if (!output.commit()) {
        *error = output.errorString();
        return false;
    }
    if (archivedDirectory) {
        QString extractionRoot = requestedDestination;
        if (extractionRoot.isEmpty()) extractionRoot = QFileInfo(sourcePath).absolutePath();
        if (!QFileInfo(extractionRoot).isDir())
            extractionRoot = QFileInfo(extractionRoot).absolutePath();
        if (!unpackArchive(outputPath, extractionRoot, error))
            return false;
        *finalPath = QDir(extractionRoot).filePath(originalName);
    } else {
        *finalPath = outputPath;
    }
    return true;
}


bool FileManager::encryptAesGcm(const QString &sourcePath,
                                const QString &destinationPath,
                                const QString &password,
                                QString *finalPath,
                                QString *error)
{
    if (crypto_aead_aes256gcm_is_available() == 0) {
        *error = QStringLiteral("AES-256-GCM is unavailable on this processor. Use XChaCha20-Poly1305 instead.");
        return false;
    }
    if (password.size() < 8) {
        *error = QStringLiteral("Encryption passwords must contain at least 8 characters.");
        return false;
    }
    const QFileInfo sourceInfo(sourcePath);
    QTemporaryDir temporary;
    QString inputPath = sourcePath;
    bool archivedDirectory = false;
    if (sourceInfo.isDir()) {
        if (!temporary.isValid()) {
            *error = QStringLiteral("Unable to create temporary encryption workspace.");
            return false;
        }
        inputPath = temporary.filePath(QStringLiteral("payload.tar"));
        if (!createArchive(QStringList{sourcePath}, inputPath, QStringLiteral("tar"), error))
            return false;
        archivedDirectory = true;
    }
    QString outputPath = cleanUserPath(destinationPath);
    if (QFileInfo(outputPath).isDir())
        outputPath = QDir(outputPath).filePath(sourceInfo.fileName() + QStringLiteral(".nenc"));
    if (QFileInfo::exists(outputPath)) {
        *error = QStringLiteral("Encrypted destination already exists.");
        return false;
    }
    QFile input(inputPath);
    QSaveFile output(outputPath);
    if (!input.open(QIODevice::ReadOnly) || !output.open(QIODevice::WriteOnly)) {
        *error = QStringLiteral("Unable to open encryption input or destination.");
        return false;
    }
    unsigned char salt[crypto_pwhash_SALTBYTES];
    unsigned char noncePrefix[4];
    unsigned char key[crypto_aead_aes256gcm_KEYBYTES];
    randombytes_buf(salt, sizeof salt);
    randombytes_buf(noncePrefix, sizeof noncePrefix);
    const QByteArray passwordBytes = password.toUtf8();
    if (crypto_pwhash(key, sizeof key,
                      passwordBytes.constData(), static_cast<unsigned long long>(passwordBytes.size()),
                      salt, crypto_pwhash_OPSLIMIT_MODERATE, crypto_pwhash_MEMLIMIT_MODERATE,
                      crypto_pwhash_ALG_DEFAULT) != 0) {
        sodium_memzero(key, sizeof key);
        *error = QStringLiteral("Not enough memory to derive the encryption key.");
        return false;
    }
    QJsonObject metadata;
    metadata.insert(QStringLiteral("name"), sourceInfo.fileName());
    metadata.insert(QStringLiteral("directory"), sourceInfo.isDir());
    metadata.insert(QStringLiteral("archivedDirectory"), archivedDirectory);
    metadata.insert(QStringLiteral("plainSize"), QString::number(QFileInfo(inputPath).size()));
    metadata.insert(QStringLiteral("created"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    const QByteArray metadataBytes = QJsonDocument(metadata).toJson(QJsonDocument::Compact);
    output.write(kAesMagic);
    output.write(reinterpret_cast<const char *>(salt), sizeof salt);
    output.write(reinterpret_cast<const char *>(noncePrefix), sizeof noncePrefix);
    output.write(littleEndian32(static_cast<quint32>(metadataBytes.size())));
    output.write(metadataBytes);

    quint64 counter = 0;
    QByteArray plain(kCryptoChunkBytes, '\0');
    QByteArray cipher(kCryptoChunkBytes + crypto_aead_aes256gcm_ABYTES, '\0');
    while (true) {
        const qint64 count = input.read(plain.data(), plain.size());
        if (count < 0) {
            sodium_memzero(key, sizeof key);
            *error = input.errorString();
            return false;
        }
        unsigned char nonce[crypto_aead_aes256gcm_NPUBBYTES] = {};
        std::memcpy(nonce, noncePrefix, sizeof noncePrefix);
        for (int i = 0; i < 8; ++i)
            nonce[4 + i] = static_cast<unsigned char>((counter >> (8 * i)) & 0xff);
        unsigned long long cipherSize = 0;
        if (crypto_aead_aes256gcm_encrypt(
                reinterpret_cast<unsigned char *>(cipher.data()), &cipherSize,
                reinterpret_cast<const unsigned char *>(plain.constData()),
                static_cast<unsigned long long>(count),
                reinterpret_cast<const unsigned char *>(metadataBytes.constData()),
                static_cast<unsigned long long>(metadataBytes.size()),
                nullptr, nonce, key) != 0) {
            sodium_memzero(key, sizeof key);
            *error = QStringLiteral("AES-GCM encryption failed.");
            return false;
        }
        output.write(littleEndian32(static_cast<quint32>(cipherSize)));
        if (output.write(cipher.constData(), static_cast<qint64>(cipherSize)) != static_cast<qint64>(cipherSize)) {
            sodium_memzero(key, sizeof key);
            *error = output.errorString();
            return false;
        }
        ++counter;
        if (input.atEnd())
            break;
    }
    sodium_memzero(key, sizeof key);
    if (!output.commit()) {
        *error = output.errorString();
        return false;
    }
    *finalPath = outputPath;
    return true;
}

bool FileManager::decryptAesGcm(const QString &sourcePath,
                                const QString &destinationPath,
                                const QString &password,
                                QString *finalPath,
                                QString *error)
{
    if (crypto_aead_aes256gcm_is_available() == 0) {
        *error = QStringLiteral("AES-256-GCM is unavailable on this processor.");
        return false;
    }
    QFile input(sourcePath);
    if (!input.open(QIODevice::ReadOnly)) {
        *error = input.errorString();
        return false;
    }
    if (input.read(kAesMagic.size()) != kAesMagic) {
        *error = QStringLiteral("This is not an AES-GCM NeutronOS encrypted container.");
        return false;
    }
    const QByteArray salt = input.read(crypto_pwhash_SALTBYTES);
    const QByteArray noncePrefix = input.read(4);
    quint32 metadataSize = 0;
    if (salt.size() != crypto_pwhash_SALTBYTES || noncePrefix.size() != 4 ||
            !readLittleEndian32(input, &metadataSize) || metadataSize > 1024 * 1024) {
        *error = QStringLiteral("Encrypted container header is damaged.");
        return false;
    }
    const QByteArray metadataBytes = input.read(metadataSize);
    const QJsonObject metadata = QJsonDocument::fromJson(metadataBytes).object();
    const QString originalName = metadata.value(QStringLiteral("name")).toString(QStringLiteral("decrypted-file"));
    const bool archivedDirectory = metadata.value(QStringLiteral("archivedDirectory")).toBool();
    const qint64 expectedSize = metadata.value(QStringLiteral("plainSize")).toString().toLongLong();

    unsigned char key[crypto_aead_aes256gcm_KEYBYTES];
    const QByteArray passwordBytes = password.toUtf8();
    if (crypto_pwhash(key, sizeof key,
                      passwordBytes.constData(), static_cast<unsigned long long>(passwordBytes.size()),
                      reinterpret_cast<const unsigned char *>(salt.constData()),
                      crypto_pwhash_OPSLIMIT_MODERATE, crypto_pwhash_MEMLIMIT_MODERATE,
                      crypto_pwhash_ALG_DEFAULT) != 0) {
        sodium_memzero(key, sizeof key);
        *error = QStringLiteral("Not enough memory to derive the decryption key.");
        return false;
    }
    QTemporaryDir temporary;
    const QString requestedDestination = cleanUserPath(destinationPath);
    QString outputPath;
    if (archivedDirectory) {
        if (!temporary.isValid()) {
            sodium_memzero(key, sizeof key);
            *error = QStringLiteral("Unable to create decryption workspace.");
            return false;
        }
        outputPath = temporary.filePath(QStringLiteral("payload.tar"));
    } else if (QFileInfo(requestedDestination).isDir()) {
        outputPath = QDir(requestedDestination).filePath(originalName);
    } else {
        outputPath = requestedDestination;
    }
    if (outputPath.isEmpty())
        outputPath = QDir(QFileInfo(sourcePath).absolutePath()).filePath(originalName);
    if (!archivedDirectory && QFileInfo::exists(outputPath)) {
        sodium_memzero(key, sizeof key);
        *error = QStringLiteral("Decrypted destination already exists.");
        return false;
    }
    QSaveFile output(outputPath);
    if (!output.open(QIODevice::WriteOnly)) {
        sodium_memzero(key, sizeof key);
        *error = output.errorString();
        return false;
    }
    quint64 counter = 0;
    qint64 totalPlain = 0;
    while (!input.atEnd()) {
        quint32 cipherSize = 0;
        if (!readLittleEndian32(input, &cipherSize) ||
                cipherSize < crypto_aead_aes256gcm_ABYTES ||
                cipherSize > kCryptoChunkBytes + crypto_aead_aes256gcm_ABYTES) {
            sodium_memzero(key, sizeof key);
            *error = QStringLiteral("Encrypted AES-GCM stream is damaged.");
            return false;
        }
        const QByteArray cipher = input.read(cipherSize);
        if (cipher.size() != static_cast<int>(cipherSize)) {
            sodium_memzero(key, sizeof key);
            *error = QStringLiteral("Encrypted AES-GCM stream ended unexpectedly.");
            return false;
        }
        unsigned char nonce[crypto_aead_aes256gcm_NPUBBYTES] = {};
        std::memcpy(nonce, noncePrefix.constData(), 4);
        for (int i = 0; i < 8; ++i)
            nonce[4 + i] = static_cast<unsigned char>((counter >> (8 * i)) & 0xff);
        QByteArray plain(cipherSize, '\0');
        unsigned long long plainSize = 0;
        if (crypto_aead_aes256gcm_decrypt(
                reinterpret_cast<unsigned char *>(plain.data()), &plainSize,
                nullptr,
                reinterpret_cast<const unsigned char *>(cipher.constData()), cipherSize,
                reinterpret_cast<const unsigned char *>(metadataBytes.constData()),
                static_cast<unsigned long long>(metadataBytes.size()),
                nonce, key) != 0) {
            sodium_memzero(key, sizeof key);
            *error = QStringLiteral("Password is incorrect or the AES-GCM data was modified.");
            return false;
        }
        if (output.write(plain.constData(), static_cast<qint64>(plainSize)) != static_cast<qint64>(plainSize)) {
            sodium_memzero(key, sizeof key);
            *error = output.errorString();
            return false;
        }
        totalPlain += static_cast<qint64>(plainSize);
        ++counter;
    }
    sodium_memzero(key, sizeof key);
    if (totalPlain != expectedSize) {
        *error = QStringLiteral("Encrypted stream is incomplete or has extra chunks.");
        return false;
    }
    if (!output.commit()) {
        *error = output.errorString();
        return false;
    }
    if (archivedDirectory) {
        QString extractionRoot = requestedDestination;
        if (extractionRoot.isEmpty()) extractionRoot = QFileInfo(sourcePath).absolutePath();
        if (!QFileInfo(extractionRoot).isDir())
            extractionRoot = QFileInfo(extractionRoot).absolutePath();
        if (!unpackArchive(outputPath, extractionRoot, error))
            return false;
        *finalPath = QDir(extractionRoot).filePath(originalName);
    } else {
        *finalPath = outputPath;
    }
    return true;
}

bool FileManager::encryptGpg(const QString &sourcePath,
                             const QString &destinationPath,
                             const QString &password,
                             QString *finalPath,
                             QString *error)
{
    if (!commandExists(QStringLiteral("gpg"))) {
        *error = QStringLiteral("GnuPG is not installed.");
        return false;
    }
    if (password.size() < 8) {
        *error = QStringLiteral("Encryption passwords must contain at least 8 characters.");
        return false;
    }
    QTemporaryDir temporary;
    QString inputPath = sourcePath;
    if (QFileInfo(sourcePath).isDir()) {
        inputPath = temporary.filePath(QFileInfo(sourcePath).fileName() + QStringLiteral(".tar"));
        if (!createArchive(QStringList{sourcePath}, inputPath, QStringLiteral("tar"), error))
            return false;
    }
    QString outputPath = cleanUserPath(destinationPath);
    if (QFileInfo(outputPath).isDir())
        outputPath = QDir(outputPath).filePath(QFileInfo(sourcePath).fileName() + QStringLiteral(".gpg"));
    QByteArray out;
    QByteArray err;
    const QStringList args{
        QStringLiteral("--batch"), QStringLiteral("--yes"),
        QStringLiteral("--pinentry-mode"), QStringLiteral("loopback"),
        QStringLiteral("--passphrase-fd"), QStringLiteral("0"),
        QStringLiteral("--symmetric"), QStringLiteral("--cipher-algo"), QStringLiteral("AES256"),
        QStringLiteral("--output"), outputPath, inputPath
    };
    if (!runProcess(QStringLiteral("gpg"), args, QString(), password.toUtf8() + '\n', &out, &err, 30 * 60 * 1000)) {
        *error = QStringLiteral("GPG encryption failed: %1").arg(QString::fromUtf8(err).trimmed());
        return false;
    }
    *finalPath = outputPath;
    return true;
}

bool FileManager::decryptGpg(const QString &sourcePath,
                             const QString &destinationPath,
                             const QString &password,
                             QString *finalPath,
                             QString *error)
{
    if (!commandExists(QStringLiteral("gpg"))) {
        *error = QStringLiteral("GnuPG is not installed.");
        return false;
    }
    QString outputPath = cleanUserPath(destinationPath);
    if (QFileInfo(outputPath).isDir()) {
        QString name = QFileInfo(sourcePath).completeBaseName();
        outputPath = QDir(outputPath).filePath(name);
    }
    QByteArray out;
    QByteArray err;
    const QStringList args{
        QStringLiteral("--batch"), QStringLiteral("--yes"),
        QStringLiteral("--pinentry-mode"), QStringLiteral("loopback"),
        QStringLiteral("--passphrase-fd"), QStringLiteral("0"),
        QStringLiteral("--decrypt"), QStringLiteral("--output"), outputPath, sourcePath
    };
    if (!runProcess(QStringLiteral("gpg"), args, QString(), password.toUtf8() + '\n', &out, &err, 30 * 60 * 1000)) {
        *error = QStringLiteral("GPG decryption failed: %1").arg(QString::fromUtf8(err).trimmed());
        return false;
    }
    *finalPath = outputPath;
    return true;
}

void FileManager::encryptPath(const QString &sourcePath,
                              const QString &destinationPath,
                              const QString &password,
                              const QString &method)
{
    const QString source = normalizedExistingPath(sourcePath);
    const QString destination = cleanUserPath(destinationPath);
    const QString normalizedMethod = method.toLower();
    runTask(QStringLiteral("encrypt"), destination, [source, destination, password, normalizedMethod]() {
        TaskResult result;
        result.action = QStringLiteral("encrypt");
        QString finalPath;
        QString error;
        bool ok = false;
        if (source.isEmpty()) {
            result.error = QStringLiteral("The source item no longer exists.");
            return result;
        }
        if (normalizedMethod == QStringLiteral("gpg-aes256"))
            ok = encryptGpg(source, destination, password, &finalPath, &error);
        else if (normalizedMethod == QStringLiteral("aes-256-gcm"))
            ok = encryptAesGcm(source, destination, password, &finalPath, &error);
        else
            ok = encryptXChaCha(source, destination, password, &finalPath, &error);
        result.ok = ok;
        result.path = finalPath;
        result.error = error;
        return result;
    });
}

void FileManager::decryptPath(const QString &sourcePath,
                              const QString &destinationPath,
                              const QString &password,
                              const QString &method)
{
    const QString source = normalizedExistingPath(sourcePath);
    const QString destination = cleanUserPath(destinationPath);
    QString normalizedMethod = method.toLower();
    if (normalizedMethod == QStringLiteral("auto")) {
        if (source.toLower().endsWith(QStringLiteral(".gpg"))) {
            normalizedMethod = QStringLiteral("gpg-aes256");
        } else {
            QFile probe(source);
            if (probe.open(QIODevice::ReadOnly)) {
                const QByteArray magic = probe.read(qMax(kVaultMagic.size(), kAesMagic.size()));
                normalizedMethod = magic.startsWith(kAesMagic)
                        ? QStringLiteral("aes-256-gcm")
                        : QStringLiteral("xchacha20-poly1305");
            } else {
                normalizedMethod = QStringLiteral("xchacha20-poly1305");
            }
        }
    }
    runTask(QStringLiteral("decrypt"), destination, [source, destination, password, normalizedMethod]() {
        TaskResult result;
        result.action = QStringLiteral("decrypt");
        QString finalPath;
        QString error;
        bool ok = false;
        if (source.isEmpty()) {
            result.error = QStringLiteral("Encrypted source no longer exists.");
            return result;
        }
        if (normalizedMethod == QStringLiteral("gpg-aes256"))
            ok = decryptGpg(source, destination, password, &finalPath, &error);
        else if (normalizedMethod == QStringLiteral("aes-256-gcm"))
            ok = decryptAesGcm(source, destination, password, &finalPath, &error);
        else
            ok = decryptXChaCha(source, destination, password, &finalPath, &error);
        result.ok = ok;
        result.path = finalPath;
        result.error = error;
        return result;
    });
}


QString FileManager::tagsPath() const
{
    return QDir::homePath() + QStringLiteral("/NeutronOS/state/filemanager/tags.json");
}

void FileManager::loadTags()
{
    m_tagDefinitions.clear();
    m_tagAssignments.clear();

    auto preset = [](const QString &id, const QString &name, const QString &color, const QString &icon) {
        QVariantMap tag;
        tag.insert(QStringLiteral("id"), id);
        tag.insert(QStringLiteral("name"), name);
        tag.insert(QStringLiteral("color"), color);
        tag.insert(QStringLiteral("icon"), icon);
        tag.insert(QStringLiteral("preset"), true);
        return tag;
    };

    m_tagDefinitions << preset(QStringLiteral("work"), QStringLiteral("Work"), QStringLiteral("#24C8FF"), QStringLiteral("💼"))
                     << preset(QStringLiteral("personal"), QStringLiteral("Personal"), QStringLiteral("#A45BFF"), QStringLiteral("👤"))
                     << preset(QStringLiteral("important"), QStringLiteral("Important"), QStringLiteral("#FF4055"), QStringLiteral("▲"));

    QFile file(tagsPath());
    if (!file.open(QIODevice::ReadOnly))
        return;

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return;

    const QJsonObject root = document.object();
    for (const QJsonValue &value : root.value(QStringLiteral("customTags")).toArray()) {
        if (!value.isObject()) continue;
        QVariantMap tag = value.toObject().toVariantMap();
        if (tag.value(QStringLiteral("id")).toString().isEmpty()) continue;
        tag.insert(QStringLiteral("preset"), false);
        m_tagDefinitions.append(tag);
    }

    const QJsonObject assignments = root.value(QStringLiteral("assignments")).toObject();
    for (auto it = assignments.constBegin(); it != assignments.constEnd(); ++it) {
        QStringList ids;
        for (const QJsonValue &id : it.value().toArray())
            ids << id.toString();
        ids.removeAll(QString());
        ids.removeDuplicates();
        if (!ids.isEmpty())
            m_tagAssignments.insert(it.key(), ids);
    }
}

bool FileManager::saveTags() const
{
    const QString path = tagsPath();
    QDir().mkpath(QFileInfo(path).absolutePath());

    QJsonArray custom;
    for (const QVariant &value : m_tagDefinitions) {
        const QVariantMap tag = value.toMap();
        if (!tag.value(QStringLiteral("preset")).toBool())
            custom.append(QJsonObject::fromVariantMap(tag));
    }

    QJsonObject assignments;
    for (auto it = m_tagAssignments.constBegin(); it != m_tagAssignments.constEnd(); ++it) {
        QJsonArray ids;
        for (const QString &id : it.value().toStringList()) ids.append(id);
        assignments.insert(it.key(), ids);
    }

    QJsonObject root;
    root.insert(QStringLiteral("customTags"), custom);
    root.insert(QStringLiteral("assignments"), assignments);

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return file.commit();
}

QVariantList FileManager::tagsForPath(const QString &path) const
{
    QVariantList rows;
    const QString key = cleanUserPath(path);
    const QStringList ids = m_tagAssignments.value(key).toStringList();
    for (const QString &id : ids) {
        for (const QVariant &value : m_tagDefinitions) {
            const QVariantMap tag = value.toMap();
            if (tag.value(QStringLiteral("id")).toString() == id) {
                rows.append(tag);
                break;
            }
        }
    }
    return rows;
}

bool FileManager::assignTag(const QString &path, const QString &tagId)
{
    const QString key = cleanUserPath(path);
    if (!QFileInfo::exists(key)) {
        setError(QStringLiteral("The selected item no longer exists."));
        emit operationFailed(m_error);
        return false;
    }
    bool found = false;
    for (const QVariant &value : m_tagDefinitions) {
        if (value.toMap().value(QStringLiteral("id")).toString() == tagId) { found = true; break; }
    }
    if (!found) {
        setError(QStringLiteral("Unknown File Manager tag."));
        emit operationFailed(m_error);
        return false;
    }
    QStringList ids = m_tagAssignments.value(key).toStringList();
    if (!ids.contains(tagId)) ids << tagId;
    m_tagAssignments.insert(key, ids);
    if (!saveTags()) {
        setError(QStringLiteral("Could not save file tags."));
        emit operationFailed(m_error);
        return false;
    }
    setError(QString());
    emit tagsChanged();
    emit operationCompleted(QStringLiteral("tag-assigned"), key);
    return true;
}

bool FileManager::removeTag(const QString &path, const QString &tagId)
{
    const QString key = cleanUserPath(path);
    QStringList ids = m_tagAssignments.value(key).toStringList();
    ids.removeAll(tagId);
    if (ids.isEmpty()) m_tagAssignments.remove(key);
    else m_tagAssignments.insert(key, ids);
    if (!saveTags()) {
        setError(QStringLiteral("Could not save file tags."));
        emit operationFailed(m_error);
        return false;
    }
    setError(QString());
    emit tagsChanged();
    emit operationCompleted(QStringLiteral("tag-removed"), key);
    return true;
}

QString FileManager::createCustomTag(const QString &name, const QString &color, const QString &icon)
{
    const QString cleanName = name.trimmed().left(32);
    if (cleanName.isEmpty()) {
        setError(QStringLiteral("Enter a tag name."));
        emit operationFailed(m_error);
        return QString();
    }
    const QByteArray seed = (cleanName + QString::number(QDateTime::currentMSecsSinceEpoch())).toUtf8();
    const QString id = QStringLiteral("custom-") + QString::fromLatin1(QCryptographicHash::hash(seed, QCryptographicHash::Sha1).toHex().left(10));
    QVariantMap tag;
    tag.insert(QStringLiteral("id"), id);
    tag.insert(QStringLiteral("name"), cleanName);
    tag.insert(QStringLiteral("color"), color.trimmed().isEmpty() ? QStringLiteral("#21C8FF") : color.trimmed());
    tag.insert(QStringLiteral("icon"), icon.trimmed().isEmpty() ? QStringLiteral("★") : icon.trimmed().left(4));
    tag.insert(QStringLiteral("preset"), false);
    m_tagDefinitions.append(tag);
    if (!saveTags()) {
        m_tagDefinitions.removeLast();
        setError(QStringLiteral("Could not save the custom tag."));
        emit operationFailed(m_error);
        return QString();
    }
    setError(QString());
    emit tagsChanged();
    return id;
}

QString FileManager::sftpConnectionsPath() const
{
    return QDir::homePath() + QStringLiteral("/NeutronOS/state/filemanager/sftp-connections.json");
}

QString FileManager::sftpMountRoot() const
{
    return QDir::homePath() + QStringLiteral("/NeutronOS/state/filemanager/sftp");
}

bool FileManager::isMountedPath(const QString &path)
{
    const QString clean = QDir::cleanPath(path);
    if (clean.isEmpty()) return false;
    for (const QStorageInfo &storage : QStorageInfo::mountedVolumes()) {
        if (QDir::cleanPath(storage.rootPath()) == clean) return true;
    }
    return false;
}

void FileManager::loadSftpConnections()
{
    m_sftpConnections.clear();
    QFile file(sftpConnectionsPath());
    if (!file.open(QIODevice::ReadOnly)) return;
    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isArray()) return;
    for (const QJsonValue &value : doc.array()) {
        if (!value.isObject()) continue;
        QVariantMap profile = value.toObject().toVariantMap();
        const QString id = profile.value(QStringLiteral("id")).toString();
        const QString host = profile.value(QStringLiteral("host")).toString();
        const QString user = profile.value(QStringLiteral("user")).toString();
        if (id.isEmpty() || host.isEmpty() || user.isEmpty()) continue;
        profile.insert(QStringLiteral("mountPath"), QDir(sftpMountRoot()).filePath(id));
        m_sftpConnections.append(profile);
    }
}

bool FileManager::saveSftpConnections() const
{
    const QString path = sftpConnectionsPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QJsonArray rows;
    for (const QVariant &value : m_sftpConnections) {
        QVariantMap profile = value.toMap();
        profile.remove(QStringLiteral("connected"));
        profile.remove(QStringLiteral("password"));
        rows.append(QJsonObject::fromVariantMap(profile));
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) return false;
    file.write(QJsonDocument(rows).toJson(QJsonDocument::Indented));
    return file.commit();
}

QVariantMap FileManager::sftpProfileById(const QString &id) const
{
    for (const QVariant &value : m_sftpConnections) {
        const QVariantMap profile = value.toMap();
        if (profile.value(QStringLiteral("id")).toString() == id) return profile;
    }
    return {};
}

QString FileManager::saveSftpConnection(const QString &id,
                                        const QString &name,
                                        const QString &host,
                                        int port,
                                        const QString &user,
                                        const QString &remotePath,
                                        const QString &auth)
{
    const QString cleanHost = host.trimmed();
    const QString cleanUser = user.trimmed();
    if (cleanHost.isEmpty() || cleanUser.isEmpty()) {
        setError(QStringLiteral("SFTP requires a host and username."));
        emit operationFailed(m_error);
        return QString();
    }
    QString profileId = id.trimmed();
    if (profileId.isEmpty()) {
        const QByteArray seed = (cleanUser + QLatin1Char('@') + cleanHost + QString::number(QDateTime::currentMSecsSinceEpoch())).toUtf8();
        profileId = QStringLiteral("sftp-") + QString::fromLatin1(QCryptographicHash::hash(seed, QCryptographicHash::Sha1).toHex().left(10));
    }
    QVariantMap profile;
    profile.insert(QStringLiteral("id"), profileId);
    profile.insert(QStringLiteral("name"), name.trimmed().isEmpty() ? cleanHost : name.trimmed().left(48));
    profile.insert(QStringLiteral("host"), cleanHost);
    profile.insert(QStringLiteral("port"), qBound(1, port <= 0 ? 22 : port, 65535));
    profile.insert(QStringLiteral("user"), cleanUser);
    profile.insert(QStringLiteral("remotePath"), remotePath.trimmed().isEmpty() ? QStringLiteral("/") : remotePath.trimmed());
    profile.insert(QStringLiteral("auth"), auth == QStringLiteral("password") ? QStringLiteral("password") : QStringLiteral("key"));
    profile.insert(QStringLiteral("mountPath"), QDir(sftpMountRoot()).filePath(profileId));

    bool replaced = false;
    for (int i = 0; i < m_sftpConnections.size(); ++i) {
        if (m_sftpConnections.at(i).toMap().value(QStringLiteral("id")).toString() == profileId) {
            m_sftpConnections[i] = profile;
            replaced = true;
            break;
        }
    }
    if (!replaced) m_sftpConnections.append(profile);
    if (!saveSftpConnections()) {
        setError(QStringLiteral("Could not save the SFTP profile."));
        emit operationFailed(m_error);
        return QString();
    }
    setError(QString());
    emit sftpConnectionsChanged();
    return profileId;
}

void FileManager::connectSftp(const QString &id, const QString &password)
{
    const QVariantMap profile = sftpProfileById(id);
    if (profile.isEmpty()) {
        setError(QStringLiteral("SFTP profile not found."));
        emit operationFailed(m_error);
        return;
    }
    if (!sftpAvailable()) {
        setError(QStringLiteral("SFTP requires sshfs. Install it with: sudo apt install sshfs"));
        emit operationFailed(m_error);
        return;
    }

    const QString mountPath = profile.value(QStringLiteral("mountPath")).toString();
    if (isMountedPath(mountPath)) {
        emit operationCompleted(QStringLiteral("sftp-connected"), mountPath);
        return;
    }

    runTask(QStringLiteral("sftp-connect"), mountPath, [profile, mountPath, password]() {
        TaskResult result;
        result.action = QStringLiteral("sftp-connected");
        result.path = mountPath;
        if (!QDir().mkpath(mountPath)) {
            result.error = QStringLiteral("Unable to create the SFTP mount folder.");
            return result;
        }
        const QString host = profile.value(QStringLiteral("host")).toString();
        const QString user = profile.value(QStringLiteral("user")).toString();
        const QString remote = profile.value(QStringLiteral("remotePath"), QStringLiteral("/")).toString();
        const int port = profile.value(QStringLiteral("port"), 22).toInt();
        const QString auth = profile.value(QStringLiteral("auth"), QStringLiteral("key")).toString();

        QStringList args;
        args << QStringLiteral("%1@%2:%3").arg(user, host, remote) << mountPath
             << QStringLiteral("-p") << QString::number(port)
             << QStringLiteral("-o") << QStringLiteral("reconnect")
             << QStringLiteral("-o") << QStringLiteral("ServerAliveInterval=15")
             << QStringLiteral("-o") << QStringLiteral("ServerAliveCountMax=3")
             << QStringLiteral("-o") << QStringLiteral("ConnectTimeout=10")
             << QStringLiteral("-o") << QStringLiteral("StrictHostKeyChecking=accept-new");

        QByteArray input;
        if (auth == QStringLiteral("password")) {
            if (password.isEmpty()) {
                result.error = QStringLiteral("Enter the SFTP password.");
                return result;
            }
            args << QStringLiteral("-o") << QStringLiteral("password_stdin");
            input = password.toUtf8() + '\n';
        } else {
            args << QStringLiteral("-o") << QStringLiteral("BatchMode=yes");
        }

        QByteArray out;
        QByteArray err;
        if (!runProcess(QStringLiteral("sshfs"), args, QString(), input, &out, &err, 30000)) {
            result.error = QStringLiteral("SFTP connection failed: %1").arg(QString::fromUtf8(err).trimmed());
            return result;
        }
        result.ok = isMountedPath(mountPath);
        if (!result.ok) result.error = QStringLiteral("SSHFS exited without mounting the remote server.");
        return result;
    }, [this](const TaskResult &result) {
        emit sftpConnectionsChanged();
        emit operationCompleted(result.action, result.path);
    });
}

void FileManager::disconnectSftp(const QString &id)
{
    const QVariantMap profile = sftpProfileById(id);
    if (profile.isEmpty()) return;
    const QString mountPath = profile.value(QStringLiteral("mountPath")).toString();
    if (!isMountedPath(mountPath)) {
        emit sftpConnectionsChanged();
        return;
    }
    runTask(QStringLiteral("sftp-disconnect"), mountPath, [mountPath]() {
        TaskResult result;
        result.action = QStringLiteral("sftp-disconnected");
        result.path = mountPath;
        QByteArray out;
        QByteArray err;
        QString program;
        QStringList args;
        if (commandExists(QStringLiteral("fusermount3"))) { program = QStringLiteral("fusermount3"); args << QStringLiteral("-u") << mountPath; }
        else if (commandExists(QStringLiteral("fusermount"))) { program = QStringLiteral("fusermount"); args << QStringLiteral("-u") << mountPath; }
        else { program = QStringLiteral("umount"); args << mountPath; }
        if (!runProcess(program, args, QString(), QByteArray(), &out, &err, 30000)) {
            result.error = QStringLiteral("Could not disconnect SFTP: %1").arg(QString::fromUtf8(err).trimmed());
            return result;
        }
        result.ok = true;
        return result;
    }, [this](const TaskResult &result) {
        emit sftpConnectionsChanged();
        emit operationCompleted(result.action, result.path);
    });
}

bool FileManager::removeSftpConnection(const QString &id)
{
    const QVariantMap profile = sftpProfileById(id);
    if (profile.isEmpty()) return true;
    if (isMountedPath(profile.value(QStringLiteral("mountPath")).toString())) {
        setError(QStringLiteral("Disconnect the SFTP server before removing it."));
        emit operationFailed(m_error);
        return false;
    }
    for (int i = m_sftpConnections.size() - 1; i >= 0; --i) {
        if (m_sftpConnections.at(i).toMap().value(QStringLiteral("id")).toString() == id)
            m_sftpConnections.removeAt(i);
    }
    if (!saveSftpConnections()) {
        setError(QStringLiteral("Could not remove the SFTP profile."));
        emit operationFailed(m_error);
        return false;
    }
    setError(QString());
    emit sftpConnectionsChanged();
    return true;
}

QString FileManager::quickPlacesPath() const
{
    return QDir::homePath() + QStringLiteral("/NeutronOS/state/filemanager/quick-places.json");
}

void FileManager::loadQuickPlaces()
{
    m_quickPlaces.clear();
    QFile file(quickPlacesPath());
    if (!file.open(QIODevice::ReadOnly))
        return;

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isArray())
        return;

    const QJsonArray array = document.array();
    for (const QJsonValue &value : array) {
        if (!value.isObject())
            continue;
        const QJsonObject object = value.toObject();
        const int slot = object.value(QStringLiteral("slot")).toInt(-1);
        const QString path = cleanUserPath(object.value(QStringLiteral("path")).toString());
        const QFileInfo info(path);
        if (slot < 0 || slot > 7 || !info.exists() || !info.isDir())
            continue;
        QVariantMap place;
        place.insert(QStringLiteral("slot"), slot);
        place.insert(QStringLiteral("name"), object.value(QStringLiteral("name")).toString(info.fileName().isEmpty() ? path : info.fileName()));
        place.insert(QStringLiteral("path"), info.absoluteFilePath());
        place.insert(QStringLiteral("icon"), QStringLiteral("★"));
        place.insert(QStringLiteral("quick"), true);
        m_quickPlaces.append(place);
    }

    std::sort(m_quickPlaces.begin(), m_quickPlaces.end(), [](const QVariant &left, const QVariant &right) {
        return left.toMap().value(QStringLiteral("slot")).toInt() < right.toMap().value(QStringLiteral("slot")).toInt();
    });
}

bool FileManager::saveQuickPlaces() const
{
    const QString path = quickPlacesPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QJsonArray array;
    for (const QVariant &value : m_quickPlaces)
        array.append(QJsonObject::fromVariantMap(value.toMap()));

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    return file.commit();
}

bool FileManager::assignQuickPlace(int slot, const QString &path, const QString &label)
{
    if (slot < 0 || slot > 7) {
        setError(QStringLiteral("Quick-place slot must be between 1 and 8."));
        emit operationFailed(m_error);
        return false;
    }

    const QString cleaned = cleanUserPath(path);
    const QFileInfo info(cleaned);
    if (!info.exists() || !info.isDir()) {
        setError(QStringLiteral("Quick place must point to an existing folder."));
        emit operationFailed(m_error);
        return false;
    }

    for (int index = m_quickPlaces.size() - 1; index >= 0; --index) {
        const QVariantMap existing = m_quickPlaces.at(index).toMap();
        if (existing.value(QStringLiteral("slot")).toInt() == slot ||
                existing.value(QStringLiteral("path")).toString() == info.absoluteFilePath())
            m_quickPlaces.removeAt(index);
    }

    QVariantMap place;
    place.insert(QStringLiteral("slot"), slot);
    place.insert(QStringLiteral("name"), label.trimmed().isEmpty()
                 ? (info.fileName().isEmpty() ? info.absoluteFilePath() : info.fileName())
                 : label.trimmed());
    place.insert(QStringLiteral("path"), info.absoluteFilePath());
    place.insert(QStringLiteral("icon"), QStringLiteral("★"));
    place.insert(QStringLiteral("quick"), true);
    m_quickPlaces.append(place);
    std::sort(m_quickPlaces.begin(), m_quickPlaces.end(), [](const QVariant &left, const QVariant &right) {
        return left.toMap().value(QStringLiteral("slot")).toInt() < right.toMap().value(QStringLiteral("slot")).toInt();
    });

    if (!saveQuickPlaces()) {
        setError(QStringLiteral("Could not save File Manager quick places."));
        emit operationFailed(m_error);
        return false;
    }
    setError(QString());
    emit quickPlacesChanged();
    emit operationCompleted(QStringLiteral("quick-place-assigned"), info.absoluteFilePath());
    return true;
}

bool FileManager::removeQuickPlace(int slot)
{
    bool removed = false;
    for (int index = m_quickPlaces.size() - 1; index >= 0; --index) {
        if (m_quickPlaces.at(index).toMap().value(QStringLiteral("slot")).toInt() == slot) {
            m_quickPlaces.removeAt(index);
            removed = true;
        }
    }
    if (!removed)
        return true;
    if (!saveQuickPlaces()) {
        setError(QStringLiteral("Could not save File Manager quick places."));
        emit operationFailed(m_error);
        return false;
    }
    setError(QString());
    emit quickPlacesChanged();
    emit operationCompleted(QStringLiteral("quick-place-removed"), QString::number(slot));
    return true;
}

void FileManager::searchFiles(const QString &query,
                              const QString &rootPath,
                              bool recursive,
                              int maximumResults)
{
    const QString needle = query.trimmed();
    const QString root = cleanUserPath(rootPath.isEmpty() ? m_currentPath : rootPath);
    const int limit = qBound(1, maximumResults, 5000);
    if (needle.isEmpty()) {
        emit searchCompleted(needle, root, QVariantList());
        return;
    }

    runTask(QStringLiteral("search-files"), root, [needle, root, recursive, limit]() {
        TaskResult result;
        result.action = QStringLiteral("search-files");
        result.path = root;
        const QFileInfo rootInfo(root);
        if (!rootInfo.exists() || !rootInfo.isDir()) {
            result.error = QStringLiteral("Search location does not exist: %1").arg(root);
            return result;
        }

        QVariantList items;
        QMimeDatabase mimeDatabase;
        const QDirIterator::IteratorFlags flags = recursive ? QDirIterator::Subdirectories : QDirIterator::NoIteratorFlags;
        QDirIterator iterator(root, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System, flags);
        while (iterator.hasNext() && items.size() < limit) {
            iterator.next();
            const QFileInfo info = iterator.fileInfo();
            if (!info.fileName().contains(needle, Qt::CaseInsensitive))
                continue;
            const QString mime = info.isDir()
                    ? QStringLiteral("inode/directory")
                    : mimeDatabase.mimeTypeForFile(info, QMimeDatabase::MatchExtension).name();
            QVariantMap item;
            item.insert(QStringLiteral("name"), info.fileName());
            item.insert(QStringLiteral("path"), info.absoluteFilePath());
            item.insert(QStringLiteral("parentPath"), info.absolutePath());
            item.insert(QStringLiteral("type"), info.isDir() ? QStringLiteral("folder") : QStringLiteral("file"));
            item.insert(QStringLiteral("isDir"), info.isDir());
            item.insert(QStringLiteral("sizeText"), info.isDir() ? QStringLiteral("Folder") : humanSize(info.size()));
            item.insert(QStringLiteral("modifiedText"), info.lastModified().toString(QStringLiteral("MMM d, yyyy  h:mm AP")));
            item.insert(QStringLiteral("mimeType"), mime);
            item.insert(QStringLiteral("extension"), fileExtension(info.fileName()));
            item.insert(QStringLiteral("icon"), iconForPath(info, mime));
            item.insert(QStringLiteral("hidden"), info.isHidden());
            item.insert(QStringLiteral("writable"), info.isWritable());
            item.insert(QStringLiteral("searchResult"), true);
            items.append(item);
        }
        result.ok = true;
        result.payload = items;
        return result;
    }, [this, needle, root](const TaskResult &result) {
        emit searchCompleted(needle, root, result.payload.toList());
    });
}

QVariantList FileManager::standardPlaces() const
{
    QVariantList places;
    const auto add = [&places](const QString &name, const QString &path, const QString &icon) {
        if (!QFileInfo(path).exists()) return;
        QVariantMap place;
        place.insert(QStringLiteral("name"), name);
        place.insert(QStringLiteral("path"), path);
        place.insert(QStringLiteral("icon"), icon);
        places.append(place);
    };
    add(QStringLiteral("Home"), QDir::homePath(), QStringLiteral("⌂"));
    add(QStringLiteral("NeutronOS"), QDir::homePath() + QStringLiteral("/NeutronOS"), QStringLiteral("⚛"));
    add(QStringLiteral("Desktop"), QStandardPaths::writableLocation(QStandardPaths::DesktopLocation), QStringLiteral("▰"));
    add(QStringLiteral("Documents"), QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation), QStringLiteral("▤"));
    add(QStringLiteral("Downloads"), QStandardPaths::writableLocation(QStandardPaths::DownloadLocation), QStringLiteral("⇩"));
    add(QStringLiteral("Media"), QStringLiteral("/mnt/NeutronMedia"), QStringLiteral("▣"));
    add(QStringLiteral("Root"), QStringLiteral("/"), QStringLiteral("/"));
    return places;
}

QString FileManager::rootDevicePath()
{
    QByteArray out;
    QByteArray err;
    if (runProcess(QStringLiteral("findmnt"),
                   QStringList{QStringLiteral("-n"), QStringLiteral("-o"), QStringLiteral("SOURCE"), QStringLiteral("/")},
                   QString(), QByteArray(), &out, &err, 5000))
        return QString::fromUtf8(out).trimmed();
    return QString();
}

QString FileManager::baseBlockDevice(const QString &devicePath)
{
    QString device = devicePath;
    if (device.contains(QStringLiteral("mmcblk")) || device.contains(QStringLiteral("nvme")))
        device.remove(QRegularExpression(QStringLiteral("p\\d+$")));
    else
        device.remove(QRegularExpression(QStringLiteral("\\d+$")));
    return device;
}

QVariantList FileManager::listVolumes() const
{
    QVariantList volumes;
    QString rootDevice = rootDevicePath();
    if (rootDevice.isEmpty()) {
        const QStorageInfo rootStorage(QStringLiteral("/"));
        if (rootStorage.isValid())
            rootDevice = QString::fromLocal8Bit(rootStorage.device());
    }
    const QString rootBase = baseBlockDevice(rootDevice);

    for (const QStorageInfo &storage : QStorageInfo::mountedVolumes()) {
        if (!storage.isValid() || !storage.isReady() || storage.bytesTotal() <= 0)
            continue;

        const QString device = QString::fromLocal8Bit(storage.device());
        const QString mountPath = QDir::cleanPath(storage.rootPath());
        const QString base = baseBlockDevice(device);
        const bool systemDevice = !rootBase.isEmpty() && !base.isEmpty() && base == rootBase;
        const bool systemRoot = mountPath == QStringLiteral("/");
        const bool externalBlockDevice = device.startsWith(QStringLiteral("/dev/")) &&
                                         !base.isEmpty() && !systemDevice && mountPath != QStringLiteral("/");

        // File Manager's Storage rail intentionally shows only the NeutronOS
        // root filesystem and real external block-device peripherals. This
        // excludes tmpfs, overlay, boot helper mounts, container mounts, etc.
        if (!systemRoot && !externalBlockDevice)
            continue;

        QVariantMap volume;
        QString name = systemRoot ? QStringLiteral("NeutronOS") : storage.displayName().trimmed();
        if (name.isEmpty() || name == mountPath) {
            name = QFileInfo(mountPath).fileName();
            if (name.isEmpty()) name = QFileInfo(device).fileName();
        }
        volume.insert(QStringLiteral("name"), name);
        volume.insert(QStringLiteral("device"), device);
        volume.insert(QStringLiteral("mountPath"), mountPath);
        volume.insert(QStringLiteral("filesystem"), QString::fromLatin1(storage.fileSystemType()));
        volume.insert(QStringLiteral("total"), QVariant::fromValue<qulonglong>(storage.bytesTotal()));
        volume.insert(QStringLiteral("free"), QVariant::fromValue<qulonglong>(storage.bytesAvailable()));
        volume.insert(QStringLiteral("totalText"), humanSize(storage.bytesTotal()));
        volume.insert(QStringLiteral("freeText"), humanSize(storage.bytesAvailable()));
        volume.insert(QStringLiteral("readOnly"), storage.isReadOnly());
        volume.insert(QStringLiteral("system"), systemRoot);
        volume.insert(QStringLiteral("external"), externalBlockDevice);
        volumes.append(volume);
    }
    return volumes;
}

void FileManager::formatVolume(const QString &devicePath,
                               const QString &filesystem,
                               const QString &label,
                               const QString &confirmation)
{
    const QString device = cleanUserPath(devicePath);
    const QString fs = filesystem.toLower();
    const QString safeLabel = shellSafeLabel(label);
    runTask(QStringLiteral("format-volume"), device, [device, fs, safeLabel, confirmation]() {
        TaskResult result;
        result.action = QStringLiteral("format-volume");
        result.path = device;
        if (confirmation != QStringLiteral("FORMAT")) {
            result.error = QStringLiteral("Formatting requires the exact confirmation word FORMAT.");
            return result;
        }
        if (!device.startsWith(QStringLiteral("/dev/")) || !QFileInfo::exists(device)) {
            result.error = QStringLiteral("Select a valid block-device partition.");
            return result;
        }
        const QString rootDevice = rootDevicePath();
        if (!rootDevice.isEmpty() &&
                (device == rootDevice || baseBlockDevice(device) == baseBlockDevice(rootDevice))) {
            result.error = QStringLiteral("NeutronOS refuses to format its boot/system device.");
            return result;
        }
        QString mkfs;
        QStringList mkfsArgs;
        if (fs == QStringLiteral("ext4")) {
            mkfs = QStringLiteral("mkfs.ext4");
            mkfsArgs << QStringLiteral("-F");
            if (!safeLabel.isEmpty()) mkfsArgs << QStringLiteral("-L") << safeLabel;
        } else if (fs == QStringLiteral("exfat")) {
            mkfs = QStringLiteral("mkfs.exfat");
            if (!safeLabel.isEmpty()) mkfsArgs << QStringLiteral("-n") << safeLabel;
        } else if (fs == QStringLiteral("vfat") || fs == QStringLiteral("fat32")) {
            mkfs = QStringLiteral("mkfs.vfat");
            mkfsArgs << QStringLiteral("-F") << QStringLiteral("32");
            if (!safeLabel.isEmpty()) mkfsArgs << QStringLiteral("-n") << safeLabel;
        } else if (fs == QStringLiteral("ntfs")) {
            mkfs = QStringLiteral("mkfs.ntfs");
            mkfsArgs << QStringLiteral("-F");
            if (!safeLabel.isEmpty()) mkfsArgs << QStringLiteral("-L") << safeLabel;
        } else {
            result.error = QStringLiteral("Supported filesystems: ext4, exfat, fat32, ntfs.");
            return result;
        }
        if (!commandExists(mkfs)) {
            result.error = QStringLiteral("Formatting tool is not installed: %1").arg(mkfs);
            return result;
        }
        QByteArray out;
        QByteArray err;
        if (commandExists(QStringLiteral("udisksctl")))
            runProcess(QStringLiteral("udisksctl"),
                       QStringList{QStringLiteral("unmount"), QStringLiteral("-b"), device},
                       QString(), QByteArray(), &out, &err, 30000);
        else
            runProcess(QStringLiteral("umount"), QStringList{device}, QString(), QByteArray(), &out, &err, 30000);
        if (commandExists(QStringLiteral("wipefs")) &&
                !runProcess(QStringLiteral("wipefs"), QStringList{QStringLiteral("-a"), device},
                            QString(), QByteArray(), &out, &err, 30000)) {
            result.error = QStringLiteral("Unable to clear the old filesystem: %1").arg(QString::fromUtf8(err).trimmed());
            return result;
        }
        mkfsArgs << device;
        if (!runProcess(mkfs, mkfsArgs, QString(), QByteArray(), &out, &err, 10 * 60 * 1000)) {
            result.error = QStringLiteral("Formatting failed: %1").arg(QString::fromUtf8(err).trimmed());
            return result;
        }
        result.ok = true;
        return result;
    });
}

bool FileManager::isEditable(const QString &path) const
{
    const QFileInfo info(cleanUserPath(path));
    if (!info.isFile() || info.size() > kTextLimitBytes)
        return false;
    if (textLikeExtension(path)) return true;
    QMimeDatabase database;
    const QString mime = database.mimeTypeForFile(info, QMimeDatabase::MatchContent).name();
    return mime.startsWith(QStringLiteral("text/")) ||
           mime == QStringLiteral("application/json") ||
           mime == QStringLiteral("application/xml") ||
           mime == QStringLiteral("application/javascript");
}

bool FileManager::isArchive(const QString &path) const
{
    static const QSet<QString> formats{
        QStringLiteral("zip"), QStringLiteral("tar"), QStringLiteral("tar.gz"),
        QStringLiteral("tar.xz"), QStringLiteral("tar.bz2"), QStringLiteral("7z")
    };
    return formats.contains(archiveFormatForPath(path));
}

QString FileManager::suggestedArchiveName(const QString &sourcePath, const QString &format) const
{
    return QDir(QFileInfo(sourcePath).absolutePath()).filePath(
        QFileInfo(sourcePath).fileName() + QLatin1Char('.') + format.toLower());
}

QString FileManager::suggestedEncryptedName(const QString &sourcePath) const
{
    return sourcePath + QStringLiteral(".nenc");
}

QString FileManager::humanSize(quint64 bytes)
{
    static const QStringList units{QStringLiteral("B"), QStringLiteral("KB"), QStringLiteral("MB"),
                                   QStringLiteral("GB"), QStringLiteral("TB"), QStringLiteral("PB")};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < units.size() - 1) {
        value /= 1024.0;
        ++unit;
    }
    return unit == 0
            ? QStringLiteral("%1 %2").arg(bytes).arg(units.at(unit))
            : QStringLiteral("%1 %2").arg(value, 0, 'f', value >= 10.0 ? 1 : 2).arg(units.at(unit));
}

QString FileManager::permissionString(const QFileInfo &info)
{
    const QFile::Permissions p = info.permissions();
    QString value;
    value += info.isDir() ? QLatin1Char('d') : QLatin1Char('-');
    value += p.testFlag(QFile::ReadOwner) ? QLatin1Char('r') : QLatin1Char('-');
    value += p.testFlag(QFile::WriteOwner) ? QLatin1Char('w') : QLatin1Char('-');
    value += p.testFlag(QFile::ExeOwner) ? QLatin1Char('x') : QLatin1Char('-');
    value += p.testFlag(QFile::ReadGroup) ? QLatin1Char('r') : QLatin1Char('-');
    value += p.testFlag(QFile::WriteGroup) ? QLatin1Char('w') : QLatin1Char('-');
    value += p.testFlag(QFile::ExeGroup) ? QLatin1Char('x') : QLatin1Char('-');
    value += p.testFlag(QFile::ReadOther) ? QLatin1Char('r') : QLatin1Char('-');
    value += p.testFlag(QFile::WriteOther) ? QLatin1Char('w') : QLatin1Char('-');
    value += p.testFlag(QFile::ExeOther) ? QLatin1Char('x') : QLatin1Char('-');
    return value;
}

QString FileManager::humanPermissionString(const QFileInfo &info)
{
    const QFile::Permissions p = info.permissions();
    auto describe = [p](QFileDevice::Permission read, QFileDevice::Permission write, QFileDevice::Permission execute) {
        QStringList actions;
        if (p.testFlag(read)) actions << QStringLiteral("Read");
        if (p.testFlag(write)) actions << QStringLiteral("Write");
        if (p.testFlag(execute)) actions << QStringLiteral("Execute");
        return actions.isEmpty() ? QStringLiteral("No access") : actions.join(QStringLiteral(" & "));
    };

    return QStringLiteral("Owner: %1  •  Group: %2  •  Others: %3")
            .arg(describe(QFileDevice::ReadOwner, QFileDevice::WriteOwner, QFileDevice::ExeOwner),
                 describe(QFileDevice::ReadGroup, QFileDevice::WriteGroup, QFileDevice::ExeGroup),
                 describe(QFileDevice::ReadOther, QFileDevice::WriteOther, QFileDevice::ExeOther));
}

QString FileManager::iconForPath(const QFileInfo &info, const QString &mimeType)
{
    if (info.isDir()) return QStringLiteral("folder");
    if (mimeType.startsWith(QStringLiteral("image/"))) return QStringLiteral("image");
    if (mimeType.startsWith(QStringLiteral("video/"))) return QStringLiteral("video");
    if (mimeType.startsWith(QStringLiteral("audio/"))) return QStringLiteral("audio");
    if (textLikeExtension(info.fileName())) return QStringLiteral("code");
    const QString ext = archiveFormatForPath(info.fileName());
    if (ext == QStringLiteral("zip") || ext.startsWith(QStringLiteral("tar")) || ext == QStringLiteral("7z"))
        return QStringLiteral("archive");
    if (info.fileName().endsWith(QStringLiteral(".nenc")) || info.fileName().endsWith(QStringLiteral(".gpg")))
        return QStringLiteral("encrypted");
    return QStringLiteral("file");
}

QVariantMap FileManager::metadataForPath(const QString &path)
{
    const QFileInfo info(path);
    QMimeDatabase database;
    const QString mime = info.isDir() ? QStringLiteral("inode/directory")
                                      : database.mimeTypeForFile(info, QMimeDatabase::MatchContent).name();
    QVariantMap metadata;
    metadata.insert(QStringLiteral("name"), info.fileName());
    metadata.insert(QStringLiteral("path"), info.absoluteFilePath());
    metadata.insert(QStringLiteral("parent"), info.absolutePath());
    metadata.insert(QStringLiteral("type"), info.isDir() ? QStringLiteral("Folder") : mime);
    metadata.insert(QStringLiteral("mimeType"), mime);
    metadata.insert(QStringLiteral("extension"), fileExtension(path));
    metadata.insert(QStringLiteral("size"), QVariant::fromValue<qulonglong>(info.size()));
    metadata.insert(QStringLiteral("sizeText"), humanSize(info.size()));
    metadata.insert(QStringLiteral("owner"), info.owner());
    metadata.insert(QStringLiteral("group"), info.group());
    metadata.insert(QStringLiteral("permissions"), permissionString(info));
    metadata.insert(QStringLiteral("permissionsText"), humanPermissionString(info));
    metadata.insert(QStringLiteral("readable"), info.isReadable());
    metadata.insert(QStringLiteral("writable"), info.isWritable());
    metadata.insert(QStringLiteral("executable"), info.isExecutable());
    metadata.insert(QStringLiteral("hidden"), info.isHidden());
    metadata.insert(QStringLiteral("symlink"), info.isSymLink());
    metadata.insert(QStringLiteral("symlinkTarget"), info.symLinkTarget());
    metadata.insert(QStringLiteral("created"), info.birthTime().isValid() ? info.birthTime() : info.metadataChangeTime());
    metadata.insert(QStringLiteral("modified"), info.lastModified());
    metadata.insert(QStringLiteral("accessed"), info.lastRead());
    metadata.insert(QStringLiteral("canonicalPath"), info.canonicalFilePath());
    if (info.isFile() && info.size() <= 64 * 1024 * 1024) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly)) {
            QCryptographicHash hash(QCryptographicHash::Sha256);
            hash.addData(&file);
            metadata.insert(QStringLiteral("sha256"), QString::fromLatin1(hash.result().toHex()));
        }
    } else {
        metadata.insert(QStringLiteral("sha256"), QStringLiteral("Available for files up to 64 MB"));
    }
    return metadata;
}

QVariantMap FileManager::quickLookForPath(const QString &path, QString *error)
{
    const QFileInfo info(path);
    if (!info.exists()) {
        *error = QStringLiteral("The selected item no longer exists.");
        return {};
    }
    QVariantMap preview = metadataForPath(path);
    QMimeDatabase database;
    const QString mime = info.isDir() ? QStringLiteral("inode/directory")
                                      : database.mimeTypeForFile(info, QMimeDatabase::MatchContent).name();
    if (info.isDir()) {
        QDir dir(path);
        const QFileInfoList children = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden);
        preview.insert(QStringLiteral("previewType"), QStringLiteral("folder"));
        preview.insert(QStringLiteral("summary"), QStringLiteral("%1 items").arg(children.size()));
        return preview;
    }
    if (mime.startsWith(QStringLiteral("image/"))) {
        QImageReader reader(path);
        const QSize size = reader.size();
        preview.insert(QStringLiteral("previewType"), QStringLiteral("image"));
        preview.insert(QStringLiteral("url"), QUrl::fromLocalFile(path));
        preview.insert(QStringLiteral("dimensions"), size.isValid()
                       ? QStringLiteral("%1 × %2").arg(size.width()).arg(size.height()) : QString());
        return preview;
    }
    if (textLikeExtension(path) || mime.startsWith(QStringLiteral("text/")) ||
            mime == QStringLiteral("application/json") || mime == QStringLiteral("application/xml")) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            *error = file.errorString();
            return {};
        }
        QByteArray bytes = file.read(kPreviewBytes);
        QString text = QString::fromUtf8(bytes);
        if (mime == QStringLiteral("application/json")) {
            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(bytes, &parseError);
            if (parseError.error == QJsonParseError::NoError)
                text = QString::fromUtf8(document.toJson(QJsonDocument::Indented));
        }
        preview.insert(QStringLiteral("previewType"), QStringLiteral("text"));
        preview.insert(QStringLiteral("text"), text);
        preview.insert(QStringLiteral("truncated"), info.size() > kPreviewBytes);
        return preview;
    }
    const QString archiveFormat = archiveFormatForPath(path);
    if (archiveFormat == QStringLiteral("zip") || archiveFormat.startsWith(QStringLiteral("tar")) ||
            archiveFormat == QStringLiteral("7z")) {
        QString archiveError;
        const QVariantList entries = archiveEntries(path, &archiveError);
        preview.insert(QStringLiteral("previewType"), QStringLiteral("archive"));
        preview.insert(QStringLiteral("entries"), entries);
        preview.insert(QStringLiteral("summary"), archiveError.isEmpty()
                       ? QStringLiteral("%1 listed entries").arg(entries.size()) : archiveError);
        return preview;
    }
    if (mime.startsWith(QStringLiteral("video/")) || mime.startsWith(QStringLiteral("audio/"))) {
        preview.insert(QStringLiteral("previewType"), QStringLiteral("media"));
        preview.insert(QStringLiteral("url"), QUrl::fromLocalFile(path));
        preview.insert(QStringLiteral("summary"), QStringLiteral("Media preview metadata"));
        return preview;
    }
    QFile file(path);
    if (file.open(QIODevice::ReadOnly)) {
        const QByteArray bytes = file.read(256);
        QStringList rows;
        for (int offset = 0; offset < bytes.size(); offset += 16) {
            const QByteArray chunk = bytes.mid(offset, 16);
            rows << QStringLiteral("%1  %2")
                    .arg(offset, 8, 16, QLatin1Char('0'))
                    .arg(QString::fromLatin1(chunk.toHex(' ')));
        }
        preview.insert(QStringLiteral("previewType"), QStringLiteral("hex"));
        preview.insert(QStringLiteral("text"), rows.join(QLatin1Char('\n')));
    } else {
        preview.insert(QStringLiteral("previewType"), QStringLiteral("metadata"));
    }
    return preview;
}

QString FileManager::templateContents(const QString &fileName, const QString &templateId)
{
    const QString extension = QFileInfo(fileName).suffix().toLower();
    const QString selected = templateId.isEmpty() ? extension : templateId.toLower();
    const QString baseName = QFileInfo(fileName).completeBaseName();
    if (selected == QStringLiteral("py") || selected == QStringLiteral("python"))
        return QStringLiteral("#!/usr/bin/env python3\n\n\ndef main() -> None:\n    pass\n\n\nif __name__ == \"__main__\":\n    main()\n");
    if (selected == QStringLiteral("cpp") || selected == QStringLiteral("c++"))
        return QStringLiteral("#include <iostream>\n\nint main()\n{\n    std::cout << \"Hello from NeutronOS\\n\";\n    return 0;\n}\n");
    if (selected == QStringLiteral("h") || selected == QStringLiteral("hpp")) {
        QString guard = baseName.toUpper();
        guard.replace(QRegularExpression(QStringLiteral("[^A-Z0-9]+")), QStringLiteral("_"));
        return QStringLiteral("#pragma once\n\n// %1\n").arg(guard);
    }
    if (selected == QStringLiteral("json"))
        return QStringLiteral("{\n  \"name\": \"%1\"\n}\n").arg(baseName);
    if (selected == QStringLiteral("qml"))
        return QStringLiteral("import QtQuick 2.15\n\nItem {\n    id: root\n}\n");
    if (selected == QStringLiteral("js"))
        return QStringLiteral("function main() {\n    \"use strict\";\n}\n");
    if (selected == QStringLiteral("sh") || selected == QStringLiteral("bash"))
        return QStringLiteral("#!/usr/bin/env bash\nset -Eeuo pipefail\n\n");
    if (selected == QStringLiteral("md") || selected == QStringLiteral("markdown"))
        return QStringLiteral("# %1\n\n").arg(baseName);
    if (selected == QStringLiteral("html"))
        return QStringLiteral("<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <title>%1</title>\n</head>\n<body>\n</body>\n</html>\n").arg(baseName);
    if (selected == QStringLiteral("service"))
        return QStringLiteral("[Unit]\nDescription=%1\n\n[Service]\nType=simple\nExecStart=/usr/bin/true\n\n[Install]\nWantedBy=multi-user.target\n").arg(baseName);
    if (selected == QStringLiteral("yaml") || selected == QStringLiteral("yml"))
        return QStringLiteral("name: %1\n").arg(baseName);
    if (selected == QStringLiteral("xml"))
        return QStringLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>\n");
    return QString();
}
