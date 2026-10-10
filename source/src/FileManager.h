#pragma once

#include <QObject>
#include <QFileInfo>
#include <QHash>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>
#include <functional>

class FileManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString homePath READ homePath CONSTANT)
    Q_PROPERTY(QString clipboardText READ clipboardText NOTIFY clipboardTextChanged)
    Q_PROPERTY(QString clipboardPath READ clipboardPath NOTIFY clipboardPathChanged)
    Q_PROPERTY(QString clipboardMode READ clipboardMode NOTIFY clipboardPathChanged)
    Q_PROPERTY(QStringList supportedArchiveFormats READ supportedArchiveFormats CONSTANT)
    Q_PROPERTY(QStringList supportedEncryptionMethods READ supportedEncryptionMethods NOTIFY capabilitiesChanged)
    Q_PROPERTY(QVariantList quickPlaces READ quickPlaces NOTIFY quickPlacesChanged)
    Q_PROPERTY(QVariantList tagDefinitions READ tagDefinitions NOTIFY tagsChanged)
    Q_PROPERTY(QVariantList sftpConnections READ sftpConnections NOTIFY sftpConnectionsChanged)
    Q_PROPERTY(bool sftpAvailable READ sftpAvailable CONSTANT)

public:
    explicit FileManager(QObject *parent = nullptr);

    bool ready() const;
    bool busy() const;
    QString error() const;
    QString currentPath() const;
    QString homePath() const;
    QString clipboardText() const;
    QString clipboardPath() const;
    QString clipboardMode() const;
    QStringList supportedArchiveFormats() const;
    QStringList supportedEncryptionMethods() const;
    QVariantList quickPlaces() const;
    QVariantList tagDefinitions() const;
    QVariantList sftpConnections() const;
    bool sftpAvailable() const;

    Q_INVOKABLE void initialize();
    Q_INVOKABLE void loadDirectory(const QString &path);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void openPath(const QString &path);
    Q_INVOKABLE void requestQuickLook(const QString &path);
    Q_INVOKABLE void requestMetadata(const QString &path);
    Q_INVOKABLE void readTextFile(const QString &path, qint64 maximumBytes = 8 * 1024 * 1024);
    Q_INVOKABLE void saveTextFile(const QString &path, const QString &text);

    Q_INVOKABLE void createFolder(const QString &parentPath, const QString &folderName);
    Q_INVOKABLE void createFile(const QString &parentPath,
                                const QString &fileName,
                                const QString &templateId = QString());
    Q_INVOKABLE void deletePath(const QString &path);
    Q_INVOKABLE void renamePath(const QString &path, const QString &newName);
    Q_INVOKABLE void copyPath(const QString &sourcePath, const QString &destinationDirectory);
    Q_INVOKABLE void movePath(const QString &sourcePath, const QString &destinationDirectory);
    Q_INVOKABLE void duplicatePath(const QString &path);

    Q_INVOKABLE void setClipboardPath(const QString &path, const QString &mode);
    Q_INVOKABLE void clearClipboardPath();
    Q_INVOKABLE void pasteClipboardPath(const QString &destinationDirectory);
    Q_INVOKABLE void copyText(const QString &text);
    Q_INVOKABLE QString pasteText() const;

    Q_INVOKABLE void compressPaths(const QStringList &sourcePaths,
                                   const QString &destinationArchive,
                                   const QString &format);
    Q_INVOKABLE void extractArchive(const QString &archivePath,
                                    const QString &destinationDirectory);
    Q_INVOKABLE void listArchive(const QString &archivePath);

    Q_INVOKABLE void encryptPath(const QString &sourcePath,
                                 const QString &destinationPath,
                                 const QString &password,
                                 const QString &method = QStringLiteral("xchacha20-poly1305"));
    Q_INVOKABLE void decryptPath(const QString &sourcePath,
                                 const QString &destinationPath,
                                 const QString &password,
                                 const QString &method = QStringLiteral("auto"));

    Q_INVOKABLE QVariantList standardPlaces() const;
    Q_INVOKABLE bool assignQuickPlace(int slot, const QString &path, const QString &label = QString());
    Q_INVOKABLE bool removeQuickPlace(int slot);

    Q_INVOKABLE QVariantList tagsForPath(const QString &path) const;
    Q_INVOKABLE bool assignTag(const QString &path, const QString &tagId);
    Q_INVOKABLE bool removeTag(const QString &path, const QString &tagId);
    Q_INVOKABLE QString createCustomTag(const QString &name, const QString &color, const QString &icon);

    Q_INVOKABLE QString saveSftpConnection(const QString &id,
                                           const QString &name,
                                           const QString &host,
                                           int port,
                                           const QString &user,
                                           const QString &remotePath,
                                           const QString &auth);
    Q_INVOKABLE void connectSftp(const QString &id, const QString &password = QString());
    Q_INVOKABLE void disconnectSftp(const QString &id);
    Q_INVOKABLE bool removeSftpConnection(const QString &id);
    Q_INVOKABLE void searchFiles(const QString &query,
                                 const QString &rootPath,
                                 bool recursive = true,
                                 int maximumResults = 500);
    Q_INVOKABLE QVariantList listVolumes() const;
    Q_INVOKABLE void formatVolume(const QString &devicePath,
                                  const QString &filesystem,
                                  const QString &label,
                                  const QString &confirmation);

    Q_INVOKABLE bool isEditable(const QString &path) const;
    Q_INVOKABLE bool isArchive(const QString &path) const;
    Q_INVOKABLE QString suggestedArchiveName(const QString &sourcePath,
                                             const QString &format) const;
    Q_INVOKABLE QString suggestedEncryptedName(const QString &sourcePath) const;

signals:
    void readyChanged();
    void busyChanged();
    void errorChanged();
    void currentPathChanged();
    void clipboardTextChanged();
    void clipboardPathChanged();
    void capabilitiesChanged();
    void quickPlacesChanged();
    void tagsChanged();
    void sftpConnectionsChanged();

    void directoryLoaded(const QString &path, const QVariantList &items);
    void operationCompleted(const QString &actionId, const QString &path);
    void operationFailed(const QString &message);
    void quickLookReady(const QString &path, const QVariantMap &preview);
    void metadataReady(const QString &path, const QVariantMap &metadata);
    void textFileLoaded(const QString &path,
                        const QString &text,
                        const QString &encoding,
                        bool truncated);
    void archiveListed(const QString &path, const QVariantList &entries);
    void searchCompleted(const QString &query,
                         const QString &rootPath,
                         const QVariantList &items);

private:
    struct TaskResult {
        bool ok = false;
        QString action;
        QString path;
        QString error;
        QVariant payload;
    };

    void setReady(bool ready);
    void setBusy(bool busy);
    void setError(const QString &error);
    void setCurrentPath(const QString &path);
    void runTask(const QString &action,
                 const QString &path,
                 const std::function<TaskResult()> &task,
                 const std::function<void(const TaskResult &)> &finished = {});

    static QString normalizedExistingPath(const QString &path);
    static QString destinationPathFor(const QString &sourcePath,
                                      const QString &destinationDirectory);
    static bool copyRecursively(const QString &sourcePath,
                                const QString &destinationPath,
                                QString *error);
    static bool moveSafely(const QString &sourcePath,
                           const QString &destinationPath,
                           QString *error);
    static bool removeSafely(const QString &path, QString *error);
    static QString uniquePath(const QString &desiredPath);
    static QString humanSize(quint64 bytes);
    static QString permissionString(const QFileInfo &info);
    static QString humanPermissionString(const QFileInfo &info);
    static QString iconForPath(const QFileInfo &info, const QString &mimeType);
    static QVariantMap metadataForPath(const QString &path);
    static QVariantMap quickLookForPath(const QString &path, QString *error);
    static QString templateContents(const QString &fileName, const QString &templateId);
    static bool commandExists(const QString &program);
    static bool runProcess(const QString &program,
                           const QStringList &arguments,
                           const QString &workingDirectory,
                           const QByteArray &stdinData,
                           QByteArray *stdoutData,
                           QByteArray *stderrData,
                           int timeoutMs = 120000);
    static QString archiveFormatForPath(const QString &path);
    static bool createArchive(const QStringList &sourcePaths,
                              const QString &destinationArchive,
                              const QString &format,
                              QString *error);
    static bool unpackArchive(const QString &archivePath,
                              const QString &destinationDirectory,
                              QString *error);
    static QVariantList archiveEntries(const QString &archivePath, QString *error);
    static bool encryptXChaCha(const QString &sourcePath,
                               const QString &destinationPath,
                               const QString &password,
                               QString *finalPath,
                               QString *error);
    static bool decryptXChaCha(const QString &sourcePath,
                               const QString &destinationPath,
                               const QString &password,
                               QString *finalPath,
                               QString *error);
    static bool encryptAesGcm(const QString &sourcePath,
                              const QString &destinationPath,
                              const QString &password,
                              QString *finalPath,
                              QString *error);
    static bool decryptAesGcm(const QString &sourcePath,
                              const QString &destinationPath,
                              const QString &password,
                              QString *finalPath,
                              QString *error);
    static bool encryptGpg(const QString &sourcePath,
                           const QString &destinationPath,
                           const QString &password,
                           QString *finalPath,
                           QString *error);
    static bool decryptGpg(const QString &sourcePath,
                           const QString &destinationPath,
                           const QString &password,
                           QString *finalPath,
                           QString *error);
    static QString rootDevicePath();
    static QString baseBlockDevice(const QString &devicePath);
    QString quickPlacesPath() const;
    void loadQuickPlaces();
    bool saveQuickPlaces() const;
    QString tagsPath() const;
    void loadTags();
    bool saveTags() const;
    QString sftpConnectionsPath() const;
    QString sftpMountRoot() const;
    void loadSftpConnections();
    bool saveSftpConnections() const;
    QVariantMap sftpProfileById(const QString &id) const;
    static bool isMountedPath(const QString &path);

    bool m_ready = false;
    bool m_busy = false;
    QString m_error;
    QString m_currentPath;
    QString m_clipboardPath;
    QString m_clipboardMode;
    QVariantList m_quickPlaces;
    QVariantList m_tagDefinitions;
    QVariantMap m_tagAssignments;
    QVariantList m_sftpConnections;
};
