#include "BackupRestoreManager.h"
#include <QTimer>
#include "UpdateRecoveryManager.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>

#include <utility>

namespace {
constexpr int kMaximumHistoryEntries = 100;

QString nowIso()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

QString displayTime(const QDateTime &time)
{
    return time.isValid() ? time.toLocalTime().toString(QStringLiteral("MMM d, yyyy  h:mm AP"))
                          : QStringLiteral("Unknown");
}
}

BackupRestoreManager::BackupRestoreManager(const QString &neutronRoot,
                                           UpdateRecoveryManager *updateRecoveryManager,
                                           QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_updateRecoveryManager(updateRecoveryManager)
{
    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_process, &QProcess::readyReadStandardOutput,
            this, &BackupRestoreManager::onProcessReadyRead);
    connect(m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &BackupRestoreManager::onProcessFinished);
    m_listProcess = new QProcess(this);
    m_listProcess->setProcessChannelMode(QProcess::SeparateChannels);
    connect(m_listProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &BackupRestoreManager::onBackupListFinished);
    loadConfig();
    loadHistory();
    QTimer::singleShot(3000, this, &BackupRestoreManager::refresh);
}

BackupRestoreManager::~BackupRestoreManager()
{
    cancelCurrentOperation();
    if (m_listProcess && m_listProcess->state() != QProcess::NotRunning) {
        m_listProcess->terminate();
        if (!m_listProcess->waitForFinished(1000))
            m_listProcess->kill();
    }
}

QString BackupRestoreManager::status() const { return m_status; }
QString BackupRestoreManager::lastMessage() const { return m_lastMessage; }
QString BackupRestoreManager::currentItem() const { return m_currentItem; }
QString BackupRestoreManager::backupRoot() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("backups/system"));
}
QString BackupRestoreManager::destinationPath() const { return m_destinationPath; }
QString BackupRestoreManager::latestBackup() const { return m_latestBackup; }
QString BackupRestoreManager::latestBackupName() const
{
    return m_latestBackup.isEmpty() ? QStringLiteral("None") : QFileInfo(m_latestBackup).fileName();
}
QString BackupRestoreManager::latestBackupProfile() const
{
    return m_latestBackupProfile.isEmpty() ? QStringLiteral("Unknown") : m_latestBackupProfile;
}
QString BackupRestoreManager::totalBackupSizeText() const { return humanBytes(m_totalBackupBytes); }
QString BackupRestoreManager::profile() const { return m_profile; }
QString BackupRestoreManager::reinstallPackage() const
{
    return m_updateRecoveryManager ? m_updateRecoveryManager->downloadedPackage() : QString();
}
bool BackupRestoreManager::includeRoms() const { return m_includeRoms; }
bool BackupRestoreManager::preserveUserData() const { return m_preserveUserData; }
bool BackupRestoreManager::busy() const { return m_busy; }
bool BackupRestoreManager::cleanReinstallReady() const
{
    return m_updateRecoveryManager && m_updateRecoveryManager->packageDownloaded() &&
           m_updateRecoveryManager->packageVerified() &&
           QFileInfo::exists(m_updateRecoveryManager->downloadedPackage());
}
bool BackupRestoreManager::recoveryEnvironmentReady() const
{
    return QFileInfo::exists(QStringLiteral("/boot/firmware/neutronos-recovery/reimage.sh")) ||
           QFileInfo::exists(QStringLiteral("/boot/neutronos-recovery/reimage.sh"));
}
int BackupRestoreManager::progress() const { return m_progress; }
int BackupRestoreManager::backupCount() const { return m_backups.size(); }
QVariantList BackupRestoreManager::backups() const { return m_backups; }
QVariantList BackupRestoreManager::history() const { return m_history; }

QString BackupRestoreManager::configPath() const
{
    const QString stateRoot = qEnvironmentVariable(
        "NEUTRONOS_STATE_DIR", QStringLiteral("/var/lib/neutronos"));
    return QDir(stateRoot).filePath(QStringLiteral("settings/backup-restore.json"));
}

QString BackupRestoreManager::historyPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/backup-restore/history.json"));
}

QString BackupRestoreManager::detachedStatusPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/backup-restore/last-system-operation.json"));
}

QString BackupRestoreManager::helperPath() const
{
    return QStringLiteral("/usr/local/sbin/neutronos-privileged-helper");
}

void BackupRestoreManager::loadConfig()
{
    m_destinationPath = backupRoot();
    QFile file(configPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        file.setFileName(QDir(m_neutronRoot).filePath(
            QStringLiteral("config/backup-restore.json")));
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
            return;
    }
    const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
    m_profile = cleanProfile(object.value(QStringLiteral("profile")).toString(m_profile));
    m_includeRoms = object.value(QStringLiteral("includeRoms")).toBool(false);
    m_preserveUserData = object.value(QStringLiteral("preserveUserData")).toBool(true);
    const QString candidate = QDir::cleanPath(object.value(QStringLiteral("destinationPath")).toString());
    if (!candidate.isEmpty() && QDir::isAbsolutePath(candidate) && candidate != QStringLiteral("/"))
        m_destinationPath = candidate;
}

void BackupRestoreManager::saveConfig() const
{
    QDir().mkpath(QFileInfo(configPath()).absolutePath());
    QSaveFile file(configPath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    const QJsonObject object{
        {QStringLiteral("profile"), m_profile},
        {QStringLiteral("includeRoms"), m_includeRoms},
        {QStringLiteral("preserveUserData"), m_preserveUserData},
        {QStringLiteral("destinationPath"), m_destinationPath}
    };
    const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(payload) == payload.size())
        file.commit();
}

void BackupRestoreManager::loadHistory()
{
    m_history.clear();
    QFile file(historyPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QJsonArray array = QJsonDocument::fromJson(file.readAll()).array();
    for (const QJsonValue &value : array)
        m_history.append(value.toObject().toVariantMap());
}

void BackupRestoreManager::appendHistory(const QString &operation, bool success, const QString &message)
{
    QVariantMap entry{{QStringLiteral("timestamp"), nowIso()},
                      {QStringLiteral("operation"), operation},
                      {QStringLiteral("success"), success},
                      {QStringLiteral("message"), message}};
    m_history.prepend(entry);
    while (m_history.size() > kMaximumHistoryEntries)
        m_history.removeLast();
    QJsonArray array;
    for (const QVariant &value : std::as_const(m_history))
        array.append(QJsonObject::fromVariantMap(value.toMap()));
    QDir().mkpath(QFileInfo(historyPath()).absolutePath());
    QSaveFile file(historyPath());
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        const QByteArray payload = QJsonDocument(array).toJson(QJsonDocument::Indented);
        if (file.write(payload) == payload.size())
            file.commit();
    }
    emit historyChanged();
}

void BackupRestoreManager::importDetachedStatus()
{
    QFile file(detachedStatusPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
    const QString timestamp = object.value(QStringLiteral("timestamp")).toString();
    if (timestamp.isEmpty())
        return;
    m_status = object.value(QStringLiteral("state")).toString(QStringLiteral("Ready"));
    m_lastMessage = object.value(QStringLiteral("message")).toString();
}

void BackupRestoreManager::scanBackups()
{
    if (m_listProcess->state() != QProcess::NotRunning) {
        m_scanAgain = true;
        return;
    }
    const QString sudo = QStringLiteral("/usr/bin/sudo");
    if (!QFileInfo(helperPath()).isExecutable() || !QFileInfo(sudo).isExecutable()) {
        m_lastMessage = QStringLiteral("The authenticated backup listing service is unavailable.");
        emit stateChanged();
        return;
    }
    m_scanAgain = false;
    m_listProcess->start(sudo, {QStringLiteral("-n"), helperPath(),
                                QStringLiteral("backup-list"), m_destinationPath});
    if (!m_listProcess->waitForStarted(3000)) {
        m_lastMessage = QStringLiteral("Could not start the authenticated backup listing service.");
        emit stateChanged();
    }
}

void BackupRestoreManager::refresh()
{
    importDetachedStatus();
    scanBackups();
    emit stateChanged();
}

void BackupRestoreManager::setDestinationPath(const QString &path)
{
    const QString clean = QDir::cleanPath(path.trimmed());
    if (clean.isEmpty() || !QDir::isAbsolutePath(clean) || clean == QStringLiteral("/")) {
        m_lastMessage = QStringLiteral("Backup destination must be an absolute directory and cannot be the filesystem root.");
        emit stateChanged();
        return;
    }
    m_destinationPath = clean;
    QDir().mkpath(m_destinationPath);
    saveConfig();
    scanBackups();
    m_lastMessage = QStringLiteral("Backup destination updated.");
    emit stateChanged();
}

void BackupRestoreManager::setProfile(const QString &profile)
{
    m_profile = cleanProfile(profile);
    saveConfig();
    emit stateChanged();
}

void BackupRestoreManager::setIncludeRoms(bool enabled)
{
    m_includeRoms = enabled;
    saveConfig();
    emit stateChanged();
}

void BackupRestoreManager::setPreserveUserData(bool enabled)
{
    m_preserveUserData = enabled;
    saveConfig();
    emit stateChanged();
}

bool BackupRestoreManager::beginProcess(Operation operation, const QStringList &arguments,
                                        const QString &message)
{
    if (m_busy || m_process->state() != QProcess::NotRunning)
        return false;
    const QString sudo = QStringLiteral("/usr/bin/sudo");
    if (!QFileInfo(helperPath()).isExecutable() || !QFileInfo(sudo).isExecutable()) {
        m_lastMessage = QStringLiteral("The authenticated backup service is unavailable.");
        emit stateChanged();
        return false;
    }
    m_processOutput.clear();
    setBusy(operation, message);
    QStringList privilegedArguments{QStringLiteral("-n"), helperPath()};
    privilegedArguments.append(arguments);
    m_process->start(sudo, privilegedArguments);
    if (!m_process->waitForStarted(3000)) {
        finish(operation, false, QStringLiteral("Could not start the authenticated backup service."));
        return false;
    }
    return true;
}

bool BackupRestoreManager::startDetached(const QString &action, const QStringList &arguments,
                                         const QString &message)
{
    if (m_busy)
        return false;
    const QString systemdRun = QStandardPaths::findExecutable(QStringLiteral("systemd-run"));
    if (systemdRun.isEmpty() || !QFileInfo::exists(helperPath())) {
        m_lastMessage = QStringLiteral("The systemd backup/reinstall helper is unavailable.");
        emit stateChanged();
        return false;
    }
    const QString unit = QStringLiteral("neutronos-backup-%1-%2")
                             .arg(action, QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMddhhmmss")));
    QStringList command{QStringLiteral("--unit=") + unit,
                        QStringLiteral("--collect"),
                        QStringLiteral("--property=Type=exec"),
                        helperPath(), action};
    command.append(arguments);
    qint64 pid = 0;
    if (!QProcess::startDetached(systemdRun, command, QString(), &pid)) {
        m_lastMessage = QStringLiteral("Could not hand the operation to systemd.");
        emit stateChanged();
        return false;
    }
    m_status = QStringLiteral("System operation scheduled");
    m_lastMessage = message + QStringLiteral(" NeutronOS may restart automatically.");
    appendHistory(action, true, m_lastMessage);
    emit stateChanged();
    emit restartScheduled(message);
    return true;
}

void BackupRestoreManager::setBusy(Operation operation, const QString &message)
{
    m_operation = operation;
    m_busy = true;
    m_status = message;
    m_lastMessage = message;
    m_currentItem.clear();
    m_progress = 0;
    emit stateChanged();
}

void BackupRestoreManager::finish(Operation operation, bool success, const QString &message)
{
    if (m_operation != operation)
        return;
    m_operation = Operation::None;
    m_busy = false;
    m_progress = success ? 100 : -1;
    m_currentItem.clear();
    m_status = success ? QStringLiteral("Ready") : QStringLiteral("Failed");
    m_lastMessage = message;
    appendHistory(operationName(operation), success, message);
    scanBackups();
    emit stateChanged();
    emit operationFinished(operationName(operation), success, message);
}

QString BackupRestoreManager::operationName(Operation operation)
{
    switch (operation) {
    case Operation::CreateBackup: return QStringLiteral("create-backup");
    case Operation::VerifyBackup: return QStringLiteral("verify-backup");
    case Operation::RestoreBackup: return QStringLiteral("restore-backup");
    case Operation::DeleteBackup: return QStringLiteral("delete-backup");
    case Operation::None: break;
    }
    return QStringLiteral("backup-operation");
}

bool BackupRestoreManager::createBackup(const QString &label)
{
    return beginProcess(Operation::CreateBackup,
                        {QStringLiteral("backup-create"), m_profile,
                         m_includeRoms ? QStringLiteral("1") : QStringLiteral("0"),
                         label.trimmed(), m_destinationPath},
                        QStringLiteral("Creating %1 backup…").arg(m_profile));
}

bool BackupRestoreManager::verifyLatestBackup()
{
    scanBackups();
    if (m_latestBackup.isEmpty()) {
        m_lastMessage = QStringLiteral("No backup is available to verify.");
        emit stateChanged();
        return false;
    }
    return beginProcess(Operation::VerifyBackup,
                        {QStringLiteral("backup-verify"), m_latestBackup},
                        QStringLiteral("Verifying latest backup…"));
}

bool BackupRestoreManager::restoreLatestBackup()
{
    return restoreBackup(m_latestBackup);
}

bool BackupRestoreManager::restoreBackup(const QString &path)
{
    const QString clean = QDir::cleanPath(path.trimmed());
    bool listedAndVerified = false;
    for (const QVariant &value : std::as_const(m_backups)) {
        const QVariantMap row = value.toMap();
        if (QDir::cleanPath(row.value(QStringLiteral("path")).toString()) == clean &&
            row.value(QStringLiteral("verified")).toBool()) {
            listedAndVerified = true;
            break;
        }
    }
    if (!listedAndVerified || !pathInside(clean, m_destinationPath)) {
        m_lastMessage = QStringLiteral("The selected restore point is not in the verified backup catalog.");
        emit stateChanged();
        return false;
    }
    return beginProcess(Operation::RestoreBackup,
                        {QStringLiteral("backup-restore-stage"), clean},
                        QStringLiteral("Revalidating and staging restore point…"));
}

bool BackupRestoreManager::deleteLatestBackup()
{
    scanBackups();
    if (m_latestBackup.isEmpty() || !pathInside(m_latestBackup, m_destinationPath)) {
        m_lastMessage = QStringLiteral("No safe backup is available to delete.");
        emit stateChanged();
        return false;
    }
    return beginProcess(Operation::DeleteBackup,
                        {QStringLiteral("backup-delete"), m_latestBackup},
                        QStringLiteral("Deleting latest backup…"));
}

bool BackupRestoreManager::secureWipeUserData(const QString &confirmation)
{
    if (confirmation.trimmed() != QStringLiteral("WIPE MY NEUTRONOS DATA")) {
        m_lastMessage = QStringLiteral("Confirmation phrase did not match. Nothing was changed.");
        emit stateChanged();
        return false;
    }
    return startDetached(QStringLiteral("wipe-user-data"),
                         {QStringLiteral("WIPE MY NEUTRONOS DATA"),
                          m_includeRoms ? QStringLiteral("1") : QStringLiteral("0")},
                         QStringLiteral("Secure NeutronOS data reset scheduled."));
}

bool BackupRestoreManager::cleanReinstall(const QString &confirmation)
{
    if (confirmation.trimmed() != QStringLiteral("REINSTALL NEUTRONOS GEMINI")) {
        m_lastMessage = QStringLiteral("Confirmation phrase did not match. Nothing was changed.");
        emit stateChanged();
        return false;
    }
    if (!cleanReinstallReady()) {
        m_lastMessage = QStringLiteral("A downloaded and signature-verified full-install package is required in Update & Recovery.");
        emit stateChanged();
        return false;
    }
    const QString package = m_updateRecoveryManager->downloadedPackage();
    const QString digest = fileSha256(package);
    if (digest.isEmpty()) {
        m_lastMessage = QStringLiteral("Could not hash the verified reinstall package.");
        emit stateChanged();
        return false;
    }
    return startDetached(QStringLiteral("clean-reinstall"),
                         {package, digest,
                          m_preserveUserData ? QStringLiteral("1") : QStringLiteral("0"),
                          QStringLiteral("REINSTALL NEUTRONOS GEMINI")},
                         QStringLiteral("Clean NeutronOS Gemini reinstall scheduled."));
}

bool BackupRestoreManager::cancelCurrentOperation()
{
    if (!m_busy || m_process->state() == QProcess::NotRunning)
        return false;
    m_process->terminate();
    if (!m_process->waitForFinished(2000))
        m_process->kill();
    return true;
}

void BackupRestoreManager::onProcessReadyRead()
{
    if (!m_process)
        return;
    const QByteArray bytes = m_process->readAllStandardOutput();
    m_processOutput.append(bytes);
    const QString text = QString::fromLocal8Bit(bytes);
    const QStringList lines = text.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    const QRegularExpression progressExpression(QStringLiteral("^PROGRESS:([0-9]{1,3}):(.*)$"));
    for (const QString &line : lines) {
        const QRegularExpressionMatch match = progressExpression.match(line.trimmed());
        if (match.hasMatch()) {
            m_progress = qBound(0, match.captured(1).toInt(), 100);
            m_currentItem = match.captured(2).trimmed();
        }
    }
    emit stateChanged();
}

void BackupRestoreManager::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (m_operation == Operation::None)
        return;
    m_processOutput.append(m_process->readAllStandardOutput());
    const Operation operation = m_operation;
    const bool success = exitStatus == QProcess::NormalExit && exitCode == 0;
    QString detail = QString::fromLocal8Bit(m_processOutput).trimmed();
    const QStringList lines = detail.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    if (!lines.isEmpty())
        detail = lines.constLast();
    const QString message = success
        ? (operation == Operation::CreateBackup
               ? (detail.startsWith(QStringLiteral("Backup created:"))
                      ? detail : QStringLiteral("Backup created and checksummed successfully."))
               : operation == Operation::VerifyBackup
                   ? QStringLiteral("Backup verification completed successfully.")
                   : operation == Operation::RestoreBackup
                       ? QStringLiteral("Restore point verified and staged. Restart to apply it in one-shot Recovery.")
                       : QStringLiteral("Latest backup and checksum deleted successfully."))
        : QStringLiteral("Backup operation failed: %1").arg(detail.isEmpty() ? QStringLiteral("unknown error") : detail);
    finish(operation, success, message);
}

void BackupRestoreManager::onBackupListFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    const QByteArray output = m_listProcess->readAllStandardOutput();
    const QString diagnostic = QString::fromLocal8Bit(m_listProcess->readAllStandardError()).trimmed();
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(output, &parseError);
    const QJsonObject object = document.object();
    const bool success = exitStatus == QProcess::NormalExit && exitCode == 0 &&
                         parseError.error == QJsonParseError::NoError &&
                         object.value(QStringLiteral("success")).toBool(false) &&
                         object.value(QStringLiteral("backups")).isArray();

    if (success) {
        QVariantList backups;
        qulonglong totalBytes = 0;
        QString latestBackup;
        QString latestProfile;
        const QJsonArray rows = object.value(QStringLiteral("backups")).toArray();
        for (const QJsonValue &value : rows) {
            const QJsonObject row = value.toObject();
            const QString path = QDir::cleanPath(row.value(QStringLiteral("path")).toString());
            const QString name = row.value(QStringLiteral("name")).toString();
            const QString profile = row.value(QStringLiteral("profile")).toString();
            const qulonglong size = static_cast<qulonglong>(row.value(QStringLiteral("size")).toDouble());
            const QDateTime modified = QDateTime::fromString(
                row.value(QStringLiteral("modified")).toString(), Qt::ISODate);
            if (path.isEmpty() || name.isEmpty() || !pathInside(path, m_destinationPath) ||
                QFileInfo(path).fileName() != name || !row.value(QStringLiteral("verified")).toBool())
                continue;
            backups.append(QVariantMap{{QStringLiteral("path"), path},
                                       {QStringLiteral("name"), name},
                                       {QStringLiteral("profile"), profile},
                                       {QStringLiteral("size"), size},
                                       {QStringLiteral("sizeText"), humanBytes(size)},
                                       {QStringLiteral("modified"), displayTime(modified)},
                                       {QStringLiteral("verified"), true}});
            totalBytes += size;
            if (latestBackup.isEmpty()) {
                latestBackup = path;
                latestProfile = profile;
            }
        }
        m_backups = backups;
        m_latestBackup = latestBackup;
        m_latestBackupProfile = latestProfile;
        m_totalBackupBytes = totalBytes;
        emit backupsChanged();
    } else {
        m_backups.clear();
        m_latestBackup.clear();
        m_latestBackupProfile.clear();
        m_totalBackupBytes = 0;
        const QString helperMessage = object.value(QStringLiteral("message")).toString().trimmed();
        const QString failureDetail = !helperMessage.isEmpty() ? helperMessage
            : (!diagnostic.isEmpty() ? diagnostic.left(600)
                                     : QStringLiteral("invalid authenticated response"));
        m_lastMessage = QStringLiteral("Backup enumeration failed: %1").arg(failureDetail);
        emit backupsChanged();
        emit stateChanged();
    }

    if (m_scanAgain)
        QTimer::singleShot(0, this, &BackupRestoreManager::scanBackups);
}

QString BackupRestoreManager::backupDetailsText() const
{
    if (m_backups.isEmpty())
        return QStringLiteral("No backups were found in %1.").arg(m_destinationPath);
    QStringList lines;
    for (const QVariant &value : m_backups) {
        const QVariantMap item = value.toMap();
        lines.append(QStringLiteral("%1\n  Profile: %2\n  Size: %3\n  Created: %4\n  Checksum: %5")
                         .arg(item.value(QStringLiteral("name")).toString(),
                              item.value(QStringLiteral("profile")).toString(),
                              item.value(QStringLiteral("sizeText")).toString(),
                              item.value(QStringLiteral("modified")).toString(),
                              item.value(QStringLiteral("verified")).toBool() ? QStringLiteral("Available") : QStringLiteral("Missing")));
    }
    return lines.join(QStringLiteral("\n\n"));
}

QString BackupRestoreManager::historyText() const
{
    if (m_history.isEmpty())
        return QStringLiteral("No backup or restore operations have been recorded.");
    QStringList lines;
    for (const QVariant &value : m_history) {
        const QVariantMap item = value.toMap();
        const QDateTime timestamp = QDateTime::fromString(item.value(QStringLiteral("timestamp")).toString(), Qt::ISODateWithMs);
        lines.append(QStringLiteral("%1  •  %2\n%3")
                         .arg(displayTime(timestamp),
                              item.value(QStringLiteral("success")).toBool() ? QStringLiteral("SUCCESS") : QStringLiteral("FAILED"),
                              item.value(QStringLiteral("message")).toString()));
    }
    return lines.join(QStringLiteral("\n\n"));
}

QString BackupRestoreManager::cleanProfile(const QString &profile)
{
    const QString value = profile.trimmed().toLower();
    if (value == QStringLiteral("settings") || value == QStringLiteral("apps") ||
        value == QStringLiteral("personal"))
        return value;
    return QStringLiteral("full");
}

QString BackupRestoreManager::humanBytes(qulonglong bytes)
{
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < 4) {
        value /= 1024.0;
        ++unit;
    }
    return QStringLiteral("%1 %2").arg(value, 0, value >= 100.0 || unit == 0 ? 'f' : 'f', unit == 0 ? 0 : 1)
                                 .arg(QString::fromLatin1(units[unit]));
}

QString BackupRestoreManager::fileSha256(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&file))
        return QString();
    return QString::fromLatin1(hash.result().toHex());
}

bool BackupRestoreManager::pathInside(const QString &child, const QString &parent)
{
    const QString cleanChild = QFileInfo(child).absoluteFilePath();
    QString cleanParent = QFileInfo(parent).absoluteFilePath();
    if (!cleanParent.endsWith(QLatin1Char('/')))
        cleanParent.append(QLatin1Char('/'));
    return cleanChild.startsWith(cleanParent) && cleanChild != cleanParent;
}
