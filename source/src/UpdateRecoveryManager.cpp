#include "UpdateRecoveryManager.h"
#include <QTimer>
#include "DeveloperModeManager.h"

#include <QtConcurrent>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSignalBlocker>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTextStream>
#include <QTemporaryDir>
#include <QUrl>
#include <QVersionNumber>

#include <algorithm>

#include <sodium.h>

namespace {
constexpr int kMaximumManifestBytes = 1024 * 1024;
constexpr int kMaximumHistoryEntries = 100;

QString nowIso()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

QString displayTimestamp(const QString &iso)
{
    const QDateTime time = QDateTime::fromString(iso, Qt::ISODateWithMs);
    return time.isValid() ? time.toLocalTime().toString(QStringLiteral("MMM d, yyyy  h:mm AP")) : iso;
}

bool safeRelativePath(const QString &path)
{
    const QString clean = QDir::cleanPath(path.trimmed());
    return !clean.isEmpty() && !QDir::isAbsolutePath(clean) && clean != QStringLiteral("..") &&
           !clean.startsWith(QStringLiteral("../")) && !clean.contains(QStringLiteral("/../"));
}

bool safeArtifactBasename(const QString &name)
{
    const QString candidate = name.trimmed();
    return !candidate.isEmpty() && candidate != QStringLiteral(".") &&
           candidate != QStringLiteral("..") && !candidate.contains(QStringLiteral("..")) &&
           !candidate.contains(QLatin1Char('/')) && !candidate.contains(QLatin1Char('\\')) &&
           !QDir::isAbsolutePath(candidate) && QFileInfo(candidate).fileName() == candidate &&
           QDir::cleanPath(candidate) == candidate;
}

bool semanticTriplet(const QString &value, int *major = nullptr, int *minor = nullptr, int *patch = nullptr)
{
    const QRegularExpression expression(QStringLiteral("^(\\d+)\\.(\\d+)\\.(\\d+)$"));
    const QRegularExpressionMatch match = expression.match(value.trimmed());
    if (!match.hasMatch())
        return false;
    if (major) *major = match.captured(1).toInt();
    if (minor) *minor = match.captured(2).toInt();
    if (patch) *patch = match.captured(3).toInt();
    return true;
}

int compareSemantic(const QString &left, const QString &right)
{
    return QVersionNumber::compare(QVersionNumber::fromString(left), QVersionNumber::fromString(right));
}

bool permitsTransition(const QJsonObject &metadata, const QString &current, QString *errorMessage)
{
    const QString target = metadata.value(QStringLiteral("version")).toString().trimmed();
    const QString updateClass = metadata.value(QStringLiteral("updateClass")).toString().trimmed().toLower();
    const QString minimum = metadata.value(QStringLiteral("minimumSupportedVersion")).toString().trimmed();
    const QString maximum = metadata.value(QStringLiteral("maximumSupportedVersion")).toString().trimmed();
    const QString requiredBaseline = metadata.value(QStringLiteral("requiredBaseline")).toString().trimmed();
    const QJsonValue supersedesValue = metadata.value(QStringLiteral("supersedes"));
    int targetMajor = 0, targetMinor = 0, targetPatch = 0;
    int currentMajor = 0, currentMinor = 0, currentPatch = 0;
    int baselineMajor = 0, baselineMinor = 0, baselinePatch = 0;
    if (!semanticTriplet(target, &targetMajor, &targetMinor, &targetPatch) ||
        !semanticTriplet(current, &currentMajor, &currentMinor, &currentPatch) ||
        !semanticTriplet(minimum) || !semanticTriplet(requiredBaseline, &baselineMajor, &baselineMinor, &baselinePatch) ||
        (!maximum.isEmpty() && !semanticTriplet(maximum)) || !supersedesValue.isArray() ||
        (updateClass != QStringLiteral("patch") && updateClass != QStringLiteral("baseline") &&
         updateClass != QStringLiteral("major"))) {
        if (errorMessage) *errorMessage = QStringLiteral("Authenticated update compatibility metadata is incomplete.");
        return false;
    }
    for (const QJsonValue &superseded : supersedesValue.toArray()) {
        if (!superseded.isString() || !semanticTriplet(superseded.toString())) {
            if (errorMessage) *errorMessage = QStringLiteral("Authenticated supersedence metadata is invalid.");
            return false;
        }
    }
    if (compareSemantic(target, current) <= 0 || compareSemantic(current, minimum) < 0 ||
        (!maximum.isEmpty() && compareSemantic(current, maximum) > 0)) {
        if (errorMessage) *errorMessage = QStringLiteral("This signed release does not permit an update from %1.").arg(current);
        return false;
    }
    if (updateClass == QStringLiteral("patch")) {
        if (targetPatch == 0 || baselinePatch != 0 || targetMajor != baselineMajor ||
            targetMinor != baselineMinor || currentMajor != baselineMajor || currentMinor != baselineMinor ||
            compareSemantic(current, requiredBaseline) < 0) {
            if (errorMessage) *errorMessage = QStringLiteral("Patch %1 requires its declared %2 baseline series.")
                .arg(target, requiredBaseline);
            return false;
        }
    } else if (updateClass == QStringLiteral("baseline")) {
        if (targetMinor == 0 || targetPatch != 0 || baselinePatch != 0 || targetMajor != baselineMajor ||
            baselineMinor >= targetMinor || currentMajor != baselineMajor || currentMinor != baselineMinor ||
            compareSemantic(current, requiredBaseline) < 0) {
            if (errorMessage) *errorMessage = QStringLiteral("Cumulative baseline %1 requires the declared preceding baseline series %2.")
                .arg(target, requiredBaseline);
            return false;
        }
    } else if (targetMinor != 0 || targetPatch != 0 || baselineMinor != 0 || baselinePatch != 0 ||
               baselineMajor >= targetMajor || currentMajor != baselineMajor ||
               compareSemantic(current, requiredBaseline) < 0) {
        if (errorMessage) *errorMessage = QStringLiteral("Major release %1 does not authorize this baseline transition from %2.")
            .arg(target, current);
        return false;
    }
    return true;
}
}

UpdateRecoveryManager::UpdateRecoveryManager(const QString &neutronRoot,
                                             DeveloperModeManager *developerModeManager,
                                             QObject *parent,
                                             const QString &trustedPublicKeyPath)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_trustedPublicKeyPath(trustedPublicKeyPath.trimmed().isEmpty()
                                 ? QString()
                                 : QDir::cleanPath(trustedPublicKeyPath)),
      m_developerModeManager(developerModeManager)
{
    const int sodiumResult = sodium_init();
    Q_UNUSED(sodiumResult)
    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_process, &QProcess::readyReadStandardOutput,
            this, &UpdateRecoveryManager::onProcessReadyRead);
    connect(m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &UpdateRecoveryManager::onProcessFinished);

    m_integrityWatcher = new QFutureWatcher<QVariantMap>(this);
    connect(m_integrityWatcher, &QFutureWatcher<QVariantMap>::finished,
            this, &UpdateRecoveryManager::onIntegrityFinished);

    loadConfig();
    loadState();
    loadHistory();
    QTimer::singleShot(2800, this, &UpdateRecoveryManager::refresh);
}

UpdateRecoveryManager::~UpdateRecoveryManager()
{
    cancelCurrentOperation();
    if (m_integrityWatcher && m_integrityWatcher->isRunning()) {
        m_integrityWatcher->cancel();
        m_integrityWatcher->waitForFinished();
    }
}

QString UpdateRecoveryManager::currentVersion() const { return m_currentVersion; }
QString UpdateRecoveryManager::availableVersion() const { return m_availableVersion; }
QString UpdateRecoveryManager::channel() const { return m_channel; }
QString UpdateRecoveryManager::status() const { return m_status; }
QString UpdateRecoveryManager::lastMessage() const { return m_lastMessage; }
QString UpdateRecoveryManager::lastChecked() const { return m_lastChecked; }
QString UpdateRecoveryManager::releaseNotes() const { return m_releaseNotes; }
QString UpdateRecoveryManager::manifestUrl() const { return m_manifestUrl; }
QString UpdateRecoveryManager::downloadedPackage() const { return m_downloadedPackage; }
QString UpdateRecoveryManager::integritySummary() const { return m_integritySummary; }
QString UpdateRecoveryManager::latestRecoveryPoint() const { return m_latestRecoveryPoint; }
QString UpdateRecoveryManager::recoveryDirectory() const { return recoveryRoot(); }
QString UpdateRecoveryManager::lastCheckedText() const
{
    return m_lastChecked.isEmpty() ? QStringLiteral("Never") : displayTimestamp(m_lastChecked);
}
bool UpdateRecoveryManager::busy() const { return m_busy; }
bool UpdateRecoveryManager::updateAvailable() const { return m_updateAvailable; }
bool UpdateRecoveryManager::packageDownloaded() const { return m_packageDownloaded; }
bool UpdateRecoveryManager::packageVerified() const { return m_packageVerified; }
bool UpdateRecoveryManager::manifestVerified() const { return m_manifestVerified; }
bool UpdateRecoveryManager::rollbackAvailable() const { return !m_latestRecoveryPoint.isEmpty(); }
bool UpdateRecoveryManager::safeModePrepared() const { return m_safeModePrepared; }
bool UpdateRecoveryManager::recoveryModePrepared() const { return m_recoveryModePrepared; }
bool UpdateRecoveryManager::repositoryConfigured() const { return !m_manifestUrl.isEmpty(); }
bool UpdateRecoveryManager::trustedKeyAvailable() const { return QFileInfo::exists(publicKeyPath()); }
bool UpdateRecoveryManager::releaseManifestAvailable() const { return QFileInfo::exists(releaseManifestPath()); }
int UpdateRecoveryManager::progress() const { return m_progress; }
int UpdateRecoveryManager::debianUpdatesAvailable() const { return m_debianUpdatesAvailable; }
int UpdateRecoveryManager::recoveryPointCount() const { return m_recoveryPoints.size(); }
QVariantList UpdateRecoveryManager::recoveryPoints() const { return m_recoveryPoints; }
QVariantList UpdateRecoveryManager::history() const { return m_history; }
QVariantMap UpdateRecoveryManager::integrityReport() const { return m_integrityReport; }

QString UpdateRecoveryManager::updateSizeText() const
{
    return m_updateSize > 0 ? humanBytes(m_updateSize) : QStringLiteral("Unknown");
}

QString UpdateRecoveryManager::configPath() const
{
    const QString stateRoot = qEnvironmentVariable(
        "NEUTRONOS_STATE_DIR", QStringLiteral("/var/lib/neutronos"));
    return QDir(stateRoot).filePath(QStringLiteral("settings/update-recovery.json"));
}

QString UpdateRecoveryManager::statePath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/update-recovery/state.json"));
}

QString UpdateRecoveryManager::historyPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/update-recovery/history.json"));
}

QString UpdateRecoveryManager::downloadsPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/update-recovery/downloads"));
}

QString UpdateRecoveryManager::inboxManifestPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("updates/inbox/manifest.json"));
}

QString UpdateRecoveryManager::releaseManifestPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("config/release-manifest.sha256"));
}

QString UpdateRecoveryManager::publicKeyPath() const
{
    if (!m_trustedPublicKeyPath.isEmpty())
        return m_trustedPublicKeyPath;
    return QStringLiteral("/etc/neutronos/keys/neutronos-release.gpg");
}

QString UpdateRecoveryManager::recoveryRoot() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("backups/recovery"));
}

QString UpdateRecoveryManager::safeModeFlagPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/update-recovery/safe-mode-next-boot"));
}

QString UpdateRecoveryManager::recoveryModeFlagPath() const
{
    return QStringLiteral("/var/lib/neutronos/recovery/next-boot.json");
}

QString UpdateRecoveryManager::recoveryControlPath() const
{
    const QString installed = QStringLiteral("/usr/local/sbin/neutronos-recovery-control");
    return QFileInfo::exists(installed)
        ? installed
        : QDir(m_neutronRoot).filePath(QStringLiteral("scripts/neutronos-recovery-control"));
}

QString UpdateRecoveryManager::helperPath() const
{
    if (qEnvironmentVariableIsSet("NEUTRONOS_UPDATE_TEST_ROOT")) {
        const QString testHelper = qEnvironmentVariable("NEUTRONOS_UPDATE_TEST_HELPER").trimmed();
        if (!testHelper.isEmpty())
            return testHelper;
    }
    // Privileged update actions must execute root-owned code, never a helper
    // located in the user-writable NeutronOS source tree.
    return QStringLiteral("/usr/local/lib/neutronos/neutronos-update-recovery");
}

void UpdateRecoveryManager::loadConfig()
{
    m_currentVersion = QStringLiteral("0.5 candidate");
    QFile versionFile(QDir(m_neutronRoot).filePath(QStringLiteral("config/version.json")));
    if (versionFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QJsonObject versionObject = QJsonDocument::fromJson(versionFile.readAll()).object();
        const QString version = versionObject.value(QStringLiteral("version")).toString().trimmed();
        if (!version.isEmpty())
            m_currentVersion = version;
    }

    const QString systemConfigPath = QDir(m_neutronRoot).filePath(
        QStringLiteral("config/update-recovery.json"));
    QJsonObject systemObject;
    QFile systemFile(systemConfigPath);
    if (systemFile.open(QIODevice::ReadOnly | QIODevice::Text))
        systemObject = QJsonDocument::fromJson(systemFile.readAll()).object();

    QJsonObject runtimeObject;
    QFile runtimeFile(configPath());
    if (runtimeFile.open(QIODevice::ReadOnly | QIODevice::Text))
        runtimeObject = QJsonDocument::fromJson(runtimeFile.readAll()).object();

    const QString systemChannel = cleanChannel(
        systemObject.value(QStringLiteral("channel")).toString());
    const QString systemManifest = systemObject.value(QStringLiteral("manifestUrl")).toString().trimmed();
    const QString systemSync = systemObject.value(QStringLiteral("mainlineSyncCommand")).toString().trimmed();
    m_mainlineManaged = systemChannel == QStringLiteral("mainline") &&
                        !systemManifest.isEmpty() && !systemSync.isEmpty();
    const QJsonObject object = m_mainlineManaged ? systemObject
                                                 : (runtimeObject.isEmpty() ? systemObject : runtimeObject);
    m_channel = cleanChannel(object.value(QStringLiteral("channel")).toString(m_channel));
    m_manifestUrl = object.value(QStringLiteral("manifestUrl")).toString().trimmed();
    m_mainlineSyncCommand = object.value(QStringLiteral("mainlineSyncCommand")).toString().trimmed();
    if (m_mainlineManaged && (runtimeObject.value(QStringLiteral("channel")).toString() != m_channel ||
                              runtimeObject.value(QStringLiteral("manifestUrl")).toString() != m_manifestUrl ||
                              runtimeObject.value(QStringLiteral("mainlineSyncCommand")).toString() != m_mainlineSyncCommand))
        saveConfig();
}

void UpdateRecoveryManager::saveConfig() const
{
    QDir().mkpath(QFileInfo(configPath()).absolutePath());
    QSaveFile file(configPath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    const QJsonObject object{
        {QStringLiteral("channel"), m_channel},
        {QStringLiteral("manifestUrl"), m_manifestUrl},
        {QStringLiteral("mainlineSyncCommand"), m_mainlineSyncCommand}
    };
    const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(payload) == payload.size())
        file.commit();
}

void UpdateRecoveryManager::loadState()
{
    QFile file(statePath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
    m_lastChecked = object.value(QStringLiteral("lastChecked")).toString();
    m_availableVersion = object.value(QStringLiteral("availableVersion")).toString();
    m_releaseNotes = object.value(QStringLiteral("releaseNotes")).toString();
    m_downloadedPackage = object.value(QStringLiteral("downloadedPackage")).toString();
    m_expectedSha256 = object.value(QStringLiteral("sha256")).toString();
    m_signatureBase64 = object.value(QStringLiteral("signature")).toString();
    m_manifestEnvelopePath = object.value(QStringLiteral("manifestEnvelopePath")).toString();
    m_manifestSourceUrl = object.value(QStringLiteral("manifestSourceUrl")).toString();
    m_packageUrl = object.value(QStringLiteral("packageUrl")).toString();
    m_updateSize = static_cast<qulonglong>(object.value(QStringLiteral("packageBytes")).toDouble(0));
    m_packageDownloaded = !m_downloadedPackage.isEmpty() && QFileInfo::exists(m_downloadedPackage);
    // Never restore a persisted trust decision. Every process lifetime and every
    // privileged staging request must re-authenticate the signed release data.
    m_packageVerified = false;
    m_manifestVerified = false;
    m_updateAvailable = !m_availableVersion.isEmpty() && isNewerVersion(m_availableVersion, m_currentVersion);
}

void UpdateRecoveryManager::saveState() const
{
    QDir().mkpath(QFileInfo(statePath()).absolutePath());
    QSaveFile file(statePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    const QJsonObject object{
        {QStringLiteral("lastChecked"), m_lastChecked},
        {QStringLiteral("availableVersion"), m_availableVersion},
        {QStringLiteral("releaseNotes"), m_releaseNotes},
        {QStringLiteral("downloadedPackage"), m_downloadedPackage},
        {QStringLiteral("sha256"), m_expectedSha256},
        {QStringLiteral("signature"), m_signatureBase64},
        {QStringLiteral("manifestEnvelopePath"), m_manifestEnvelopePath},
        {QStringLiteral("manifestSourceUrl"), m_manifestSourceUrl},
        {QStringLiteral("packageUrl"), m_packageUrl},
        {QStringLiteral("packageBytes"), static_cast<double>(m_updateSize)}
    };
    const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(payload) == payload.size())
        file.commit();
}

void UpdateRecoveryManager::loadHistory()
{
    m_history.clear();
    QFile file(historyPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    const QJsonArray array = QJsonDocument::fromJson(file.readAll()).array();
    for (const QJsonValue &value : array)
        m_history.append(value.toObject().toVariantMap());
}

void UpdateRecoveryManager::appendHistory(const QString &type, bool success,
                                          const QString &message, const QVariantMap &extra)
{
    QVariantMap entry = extra;
    entry.insert(QStringLiteral("type"), type);
    entry.insert(QStringLiteral("success"), success);
    entry.insert(QStringLiteral("message"), message);
    entry.insert(QStringLiteral("timestamp"), nowIso());
    m_history.prepend(entry);
    while (m_history.size() > kMaximumHistoryEntries)
        m_history.removeLast();

    QJsonArray array;
    for (const QVariant &value : m_history)
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

void UpdateRecoveryManager::refreshRecoveryState()
{
    QVariantList points;
    const QString helper = helperPath();
    if (QFileInfo(helper).isExecutable()) {
        QProcess listing;
        listing.start(helper, {QStringLiteral("list-recovery-points")});
        if (listing.waitForStarted(2000) && listing.waitForFinished(10000) && listing.exitCode() == 0) {
            const QJsonArray values = QJsonDocument::fromJson(listing.readAllStandardOutput())
                                          .object().value(QStringLiteral("recoveryPoints")).toArray();
            for (const QJsonValue &value : values) {
                const QJsonObject point = value.toObject();
                if (point.value(QStringLiteral("valid")).toBool(false))
                    points.append(point.toVariantMap());
            }
        }
    }
    const QString nextRecovery = points.isEmpty()
        ? QString() : points.first().toMap().value(QStringLiteral("path")).toString();
    const bool nextSafeMode = QFileInfo::exists(safeModeFlagPath());
    const bool nextRecoveryMode = QFileInfo::exists(recoveryModeFlagPath());
    const bool changed = nextRecovery != m_latestRecoveryPoint || points != m_recoveryPoints || nextSafeMode != m_safeModePrepared ||
                         nextRecoveryMode != m_recoveryModePrepared;
    m_latestRecoveryPoint = nextRecovery;
    m_recoveryPoints = points;
    m_safeModePrepared = nextSafeMode;
    m_recoveryModePrepared = nextRecoveryMode;
    if (changed)
        emit recoveryChanged();
}

void UpdateRecoveryManager::refresh()
{
    loadConfig();
    m_packageDownloaded = !m_downloadedPackage.isEmpty() && QFileInfo::exists(m_downloadedPackage);
    refreshRecoveryState();
    emit stateChanged();
}

QString UpdateRecoveryManager::cleanChannel(const QString &channel)
{
    const QString value = channel.trimmed().toLower();
    if (value == QStringLiteral("preview"))
        return QStringLiteral("beta");
    if (value == QStringLiteral("stable") || value == QStringLiteral("alpha") || value == QStringLiteral("beta") ||
        value == QStringLiteral("mainline") ||
        value == QStringLiteral("developer"))
        return value;
    return QStringLiteral("stable");
}

void UpdateRecoveryManager::setChannel(const QString &channel)
{
    const QString cleaned = m_mainlineManaged ? QStringLiteral("mainline") : cleanChannel(channel);
    if (m_channel == cleaned)
        return;
    m_channel = cleaned;
    saveConfig();
    emit stateChanged();
}

void UpdateRecoveryManager::setManifestUrl(const QString &url)
{
    const QString cleaned = url.trimmed();
    if (m_manifestUrl == cleaned)
        return;
    m_manifestUrl = cleaned;
    saveConfig();
    emit stateChanged();
}

void UpdateRecoveryManager::setBusy(Operation operation, const QString &status, int progress)
{
    m_operation = operation;
    m_busy = operation != Operation::None;
    m_status = status;
    m_progress = progress;
    m_lastMessage.clear();
    emit stateChanged();
}

QString UpdateRecoveryManager::operationName(Operation operation)
{
    switch (operation) {
    case Operation::CheckManifest: return QStringLiteral("check-update");
    case Operation::SyncMainline: return QStringLiteral("sync-mainline");
    case Operation::Download: return QStringLiteral("download-update");
    case Operation::CheckDebian: return QStringLiteral("check-debian");
    case Operation::VerifyIntegrity: return QStringLiteral("verify-installation");
    case Operation::CreateRecovery: return QStringLiteral("create-recovery");
    case Operation::StageUpdate: return QStringLiteral("install-update");
    default: return QStringLiteral("operation");
    }
}

void UpdateRecoveryManager::finish(Operation operation, bool success, const QString &message)
{
    const QString name = operationName(operation);
    m_operation = Operation::None;
    m_busy = false;
    m_progress = success ? 100 : -1;
    m_status = success ? QStringLiteral("Ready") : QStringLiteral("Attention required");
    m_lastMessage = message;
    appendHistory(name, success, message);
    saveState();
    emit stateChanged();
    emit operationFinished(name, success, message);
}

bool UpdateRecoveryManager::checkForUpdates(const QString &channel)
{
    if (m_busy)
        return false;
    if (!channel.trimmed().isEmpty())
        setChannel(channel);

    if (!m_mainlineSyncCommand.isEmpty()) {
        if (!QFileInfo(m_mainlineSyncCommand).isExecutable()) {
            m_lastMessage = QStringLiteral("The private Mainline sync helper is unavailable.");
            m_status = QStringLiteral("Repository not configured");
            emit stateChanged();
            emit operationFinished(QStringLiteral("check-update"), false, m_lastMessage);
            return false;
        }
        return beginProcess(Operation::SyncMainline, m_mainlineSyncCommand, {},
                            QStringLiteral("Refreshing private NeutronOS Mainline…"));
    }
    return fetchConfiguredManifest();
}

bool UpdateRecoveryManager::fetchConfiguredManifest()
{
    if (m_busy)
        return false;

    QUrl url;
    if (!m_manifestUrl.isEmpty()) {
        QString resolved = m_manifestUrl;
        resolved.replace(QStringLiteral("{channel}"), m_channel);
        url = QUrl::fromUserInput(resolved);
    } else if (QFileInfo::exists(inboxManifestPath())) {
        url = QUrl::fromLocalFile(inboxManifestPath());
    } else {
        m_lastMessage = QStringLiteral("No update repository is configured and updates/inbox/manifest.json was not found.");
        m_status = QStringLiteral("Repository not configured");
        emit stateChanged();
        emit operationFinished(QStringLiteral("check-update"), false, m_lastMessage);
        return false;
    }

    if (!url.isValid() || (url.scheme() != QStringLiteral("https") && url.scheme() != QStringLiteral("file"))) {
        m_lastMessage = QStringLiteral("The update manifest must use HTTPS or a local file path.");
        emit stateChanged();
        return false;
    }

    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("NeutronOS-Gemini-UpdateManager/1"));
    m_reply = m_network.get(request);
    connect(m_reply, &QNetworkReply::finished, this, &UpdateRecoveryManager::onManifestFinished);
    setBusy(Operation::CheckManifest, QStringLiteral("Checking %1 channel…").arg(m_channel), -1);
    return true;
}

void UpdateRecoveryManager::onManifestFinished()
{
    QNetworkReply *reply = m_reply.data();
    if (!reply)
        return;
    const QUrl manifestSourceUrl = reply->url();
    m_reply = nullptr;
    if (reply->error() != QNetworkReply::NoError) {
        const QString message = QStringLiteral("Update check failed: %1").arg(reply->errorString());
        reply->deleteLater();
        finish(Operation::CheckManifest, false, message);
        return;
    }
    const QByteArray payload = reply->read(kMaximumManifestBytes + 1);
    if (payload.size() > kMaximumManifestBytes) {
        reply->deleteLater();
        finish(Operation::CheckManifest, false, QStringLiteral("Update manifest exceeded the 1 MiB safety limit."));
        return;
    }
    setProperty("manifestSourceUrl", manifestSourceUrl);
    m_manifestSourceUrl = manifestSourceUrl.toString();
    QString error;
    if (!parseManifest(payload, &error)) {
        reply->deleteLater();
        finish(Operation::CheckManifest, false, error);
        return;
    }
    reply->deleteLater();
    m_lastChecked = nowIso();
    const bool available = m_updateAvailable;
    finish(Operation::CheckManifest, true,
           available ? QStringLiteral("NeutronOS %1 is available.").arg(m_availableVersion)
                     : QStringLiteral("NeutronOS is up to date on the %1 channel.").arg(m_channel));
}

bool UpdateRecoveryManager::parseManifest(const QByteArray &payload, QString *errorMessage)
{
    m_manifestVerified = false;
    m_packageVerified = false;
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (!document.isObject()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("Invalid update manifest: %1").arg(parseError.errorString());
        return false;
    }
    const QJsonObject envelope = document.object();
    if (envelope.value(QStringLiteral("schema")).toInt() == 1 &&
        envelope.value(QStringLiteral("channel")).toString() == QStringLiteral("mainline") &&
        envelope.value(QStringLiteral("releases")).isArray())
        return parseMainlineIndex(envelope, errorMessage);
    if (envelope.value(QStringLiteral("format")).toString() ==
        QStringLiteral("neutronos.mainline-metadata.v1"))
        return parseMainlineMetadataEnvelope(envelope, errorMessage);
    if (envelope.value(QStringLiteral("format")).toString() !=
            QStringLiteral("neutronos.update-manifest.v2")) {
        if (errorMessage) *errorMessage = QStringLiteral("Unsupported or unsigned update manifest format.");
        return false;
    }
    const QByteArray signedPayload = QByteArray::fromBase64(
        envelope.value(QStringLiteral("signedPayload")).toString().toLatin1());
    const QByteArray manifestSignature = QByteArray::fromBase64(
        envelope.value(QStringLiteral("signature")).toString().toLatin1());
    if (!verifyReleaseSignature(signedPayload, manifestSignature, errorMessage)) return false;
    const QJsonDocument signedDocument = QJsonDocument::fromJson(signedPayload, &parseError);
    if (!signedDocument.isObject()) {
        if (errorMessage) *errorMessage = QStringLiteral("The signed release payload is invalid.");
        return false;
    }
    const QJsonObject object = signedDocument.object();
    if (object.value(QStringLiteral("product")).toString() != QStringLiteral("NeutronOS")) {
        if (errorMessage) *errorMessage = QStringLiteral("The manifest is not a NeutronOS update.");
        return false;
    }
    const QString codename = object.value(QStringLiteral("codename")).toString(QStringLiteral("Gemini"));
    const QString manifestChannel = cleanChannel(object.value(QStringLiteral("channel")).toString(m_channel));
    const QString version = object.value(QStringLiteral("version")).toString().trimmed();
    const QString architecture = object.value(QStringLiteral("architecture")).toString().trimmed().toLower();
    const QJsonObject artifact = object.value(QStringLiteral("artifact")).toObject();
    const QString packageUrl = artifact.value(QStringLiteral("url")).toString().trimmed();
    const QString sha = artifact.value(QStringLiteral("sha256")).toString().trimmed().toLower();
    const int updateFormat = object.value(QStringLiteral("updateFormatVersion")).toInt();
    const QString minimumCompatible = object.value(QStringLiteral("minimumCompatibleVersion")).toString();
    const QString minimumUpdater = object.value(QStringLiteral("minimumUpdaterVersion")).toString();
    const QString currentArchitecture = QSysInfo::currentCpuArchitecture().toLower() == QStringLiteral("x86_64")
        ? QStringLiteral("amd64") : QSysInfo::currentCpuArchitecture().toLower();
    if (codename != QStringLiteral("Gemini") || manifestChannel != m_channel || version.isEmpty() ||
        packageUrl.isEmpty() || !QRegularExpression(QStringLiteral("^[0-9a-f]{64}$")).match(sha).hasMatch()) {
        if (errorMessage) *errorMessage = QStringLiteral("The update manifest is incomplete or does not match Gemini/%1.").arg(m_channel);
        return false;
    }
    if (architecture != currentArchitecture) {
        if (errorMessage) *errorMessage = QStringLiteral("The update architecture %1 does not match this %2 system.")
            .arg(architecture, currentArchitecture);
        return false;
    }
    if (updateFormat != 2) {
        if (errorMessage) *errorMessage = QStringLiteral("This updater does not support update format %1.").arg(updateFormat);
        return false;
    }
    if ((!minimumCompatible.isEmpty() && isNewerVersion(minimumCompatible, m_currentVersion)) ||
        (!minimumUpdater.isEmpty() && isNewerVersion(minimumUpdater, QStringLiteral("1.0.0")))) {
        if (errorMessage) *errorMessage = QStringLiteral("The release requires a newer compatible system or updater.");
        return false;
    }

    QUrl package(packageUrl);
    if (package.isRelative()) {
        const QUrl sourceUrl = property("manifestSourceUrl").toUrl();
        package = sourceUrl.resolved(package);
    }
    if (!package.isValid() || (package.scheme() != QStringLiteral("https") && package.scheme() != QStringLiteral("file"))) {
        if (errorMessage) *errorMessage = QStringLiteral("The update package URL is invalid or insecure.");
        return false;
    }

    m_manifest = object;
    m_manifestVerified = true;
    m_availableVersion = version;
    m_releaseNotes = object.value(QStringLiteral("notes")).toString();
    m_packageUrl = package.toString();
    m_expectedSha256 = sha;
    m_signatureBase64 = envelope.value(QStringLiteral("signature")).toString();
    m_updateSize = static_cast<qulonglong>(artifact.value(QStringLiteral("size")).toDouble(0));
    m_updateAvailable = isNewerVersion(version, m_currentVersion);
    m_packageDownloaded = false;
    m_packageVerified = false;

    // Cache the exact signed envelope, not merely the derived checksum. The
    // privileged helper independently verifies this envelope again before it
    // accepts any package bytes.
    QDir().mkpath(downloadsPath());
    const QString safeVersion = QString(version).replace(
        QRegularExpression(QStringLiteral("[^A-Za-z0-9._-]")), QStringLiteral("_"));
    m_manifestEnvelopePath = QDir(downloadsPath()).filePath(
        QStringLiteral("NeutronOS-%1.manifest.json").arg(safeVersion));
    QSaveFile envelopeFile(m_manifestEnvelopePath);
    if (!envelopeFile.open(QIODevice::WriteOnly) ||
        envelopeFile.write(payload) != payload.size() || !envelopeFile.commit()) {
        m_manifestVerified = false;
        if (errorMessage) *errorMessage = QStringLiteral("Could not persist the signed release manifest safely.");
        return false;
    }
    saveState();
    emit stateChanged();
    return true;
}

bool UpdateRecoveryManager::parseMainlineIndex(const QJsonObject &index, QString *errorMessage)
{
    m_manifestVerified = false;
    m_packageVerified = false;
    if (m_channel != QStringLiteral("mainline")) {
        if (errorMessage) *errorMessage = QStringLiteral("The Mainline index requires the mainline update channel.");
        return false;
    }
    const QUrl sourceUrl = property("manifestSourceUrl").toUrl();
    if (!sourceUrl.isLocalFile()) {
        if (errorMessage) *errorMessage = QStringLiteral("Private Mainline must be read from the authenticated local mirror.");
        return false;
    }
    const QFileInfo sourceInfo(sourceUrl.toLocalFile());
    const QDir repositoryRoot = sourceInfo.dir();
    QList<QJsonObject> candidates;
    const QJsonArray releases = index.value(QStringLiteral("releases")).toArray();
    for (const QJsonValue &value : releases) {
        const QJsonObject release = value.toObject();
        if (!release.value(QStringLiteral("live")).toBool(false))
            continue;
        const QString version = release.value(QStringLiteral("version")).toString().trimmed();
        if (semanticTriplet(version) && isNewerVersion(version, m_currentVersion))
            candidates.append(release);
    }
    std::sort(candidates.begin(), candidates.end(), [](const QJsonObject &left, const QJsonObject &right) {
        return compareSemantic(left.value(QStringLiteral("version")).toString(),
                               right.value(QStringLiteral("version")).toString()) > 0;
    });
    if (candidates.isEmpty()) {
        m_availableVersion.clear();
        m_packageUrl.clear();
        m_expectedSha256.clear();
        m_updateSize = 0;
        m_updateAvailable = false;
        m_packageDownloaded = false;
        m_packageVerified = false;
        emit stateChanged();
        return true;
    }

    QString lastFailure;
    for (const QJsonObject &selected : candidates) {
        const QString selectedVersion = selected.value(QStringLiteral("version")).toString().trimmed();
        const QString metadataRelative = selected.value(QStringLiteral("metadata")).toString();
        const QString signatureRelative = selected.value(QStringLiteral("signature")).toString();
        const QString artifactRelative = selected.value(QStringLiteral("artifact")).toString();
        if (!safeRelativePath(metadataRelative) || !safeRelativePath(signatureRelative) ||
            !safeRelativePath(artifactRelative)) {
            lastFailure = QStringLiteral("Mainline contains an unsafe release path for %1.").arg(selectedVersion);
            continue;
        }
        const QString metadataPath = repositoryRoot.filePath(metadataRelative);
        const QString signaturePath = repositoryRoot.filePath(signatureRelative);
        const QString artifactPath = repositoryRoot.filePath(artifactRelative);
        QFile metadataFile(metadataPath);
        QFile signatureFile(signaturePath);
        if (!metadataFile.open(QIODevice::ReadOnly) || !signatureFile.open(QIODevice::ReadOnly)) {
            lastFailure = QStringLiteral("LIVE Mainline release %1 is incomplete.").arg(selectedVersion);
            continue;
        }
        const QByteArray metadata = metadataFile.read(kMaximumManifestBytes + 1);
        const QByteArray signatureText = signatureFile.read(4097).trimmed();
        if (metadata.size() > kMaximumManifestBytes || signatureText.size() > 4096) {
            lastFailure = QStringLiteral("Mainline signed metadata for %1 exceeded its safety limit.").arg(selectedVersion);
            continue;
        }
        const QJsonObject signedEnvelope{
            {QStringLiteral("format"), QStringLiteral("neutronos.mainline-metadata.v1")},
            {QStringLiteral("metadata"), QString::fromLatin1(metadata.toBase64())},
            {QStringLiteral("signature"), QString::fromLatin1(signatureText)},
            {QStringLiteral("artifactUrl"), QUrl::fromLocalFile(artifactPath).toString()}
        };
        QString candidateError;
        if (!parseMainlineMetadataEnvelope(signedEnvelope, &candidateError)) {
            lastFailure = candidateError;
            continue;
        }
        const QString indexName = selected.value(QStringLiteral("name")).toString();
        const QString indexSha = selected.value(QStringLiteral("sha256")).toString().trimmed().toLower();
        if (m_availableVersion != selectedVersion || QFileInfo(artifactPath).fileName() != indexName ||
            m_expectedSha256 != indexSha || QFileInfo(metadataPath).fileName() != QStringLiteral("metadata.json") ||
            QFileInfo(signaturePath).fileName() != QStringLiteral("metadata.sig")) {
            m_manifestVerified = false;
            lastFailure = QStringLiteral("Mainline index and signed metadata disagree for %1.").arg(selectedVersion);
            continue;
        }
        return true;
    }
    if (errorMessage) *errorMessage = lastFailure.isEmpty()
        ? QStringLiteral("No LIVE Mainline package authorizes an update from %1.").arg(m_currentVersion)
        : lastFailure;
    return false;
}

bool UpdateRecoveryManager::parseMainlineMetadataEnvelope(const QJsonObject &envelope,
                                                          QString *errorMessage)
{
    const QByteArray metadata = QByteArray::fromBase64(
        envelope.value(QStringLiteral("metadata")).toString().toLatin1());
    const QByteArray signature = QByteArray::fromBase64(
        envelope.value(QStringLiteral("signature")).toString().toLatin1());
    if (!verifyReleaseSignature(metadata, signature, errorMessage)) return false;
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(metadata, &parseError);
    const QJsonObject object = document.object();
    const QString name = object.value(QStringLiteral("name")).toString().trimmed();
    const QString version = object.value(QStringLiteral("version")).toString().trimmed();
    const QString sha = object.value(QStringLiteral("sha256")).toString().trimmed().toLower();
    const qint64 bytes = static_cast<qint64>(object.value(QStringLiteral("bytes")).toDouble(-1));
    if (!document.isObject() || object.value(QStringLiteral("schema")).toInt() != 1 ||
        object.value(QStringLiteral("algorithm")).toString() != (m_trustedPublicKeyPath.isEmpty() ? QStringLiteral("OpenPGP") : QStringLiteral("Ed25519")) ||
        object.value(QStringLiteral("channel")).toString() != QStringLiteral("mainline") ||
        (object.value(QStringLiteral("packageScope")).toString() != QStringLiteral("os-overlay") &&
         object.value(QStringLiteral("packageScope")).toString() != QStringLiteral("full-system")) ||
        !object.value(QStringLiteral("recoveryCapable")).isBool() ||
        (object.value(QStringLiteral("recoveryCapable")).toBool() &&
         object.value(QStringLiteral("packageScope")).toString() != QStringLiteral("full-system")) ||
        !safeArtifactBasename(name) || version.isEmpty() || bytes < 0 ||
        !QRegularExpression(QStringLiteral("^[0-9a-f]{64}$")).match(sha).hasMatch()) {
        if (errorMessage) *errorMessage = QStringLiteral("Authenticated Mainline metadata is incomplete or invalid.");
        return false;
    }
    const QUrl packageUrl(envelope.value(QStringLiteral("artifactUrl")).toString());
    if (!packageUrl.isValid() || !packageUrl.isLocalFile() ||
        QFileInfo(packageUrl.toLocalFile()).fileName() != name) {
        if (errorMessage) *errorMessage = QStringLiteral("Authenticated Mainline package identity does not match its artifact path.");
        return false;
    }
    if (!permitsTransition(object, m_currentVersion, errorMessage)) {
        return false;
    }

    m_manifest = object;
    m_manifestVerified = true;
    m_availableVersion = version;
    m_releaseNotes = QStringLiteral("Signed NeutronOS Mainline release %1.").arg(version);
    m_packageUrl = packageUrl.toString();
    m_expectedSha256 = sha;
    m_signatureBase64 = envelope.value(QStringLiteral("signature")).toString();
    m_updateSize = static_cast<qulonglong>(bytes);
    m_updateAvailable = true;
    m_packageDownloaded = false;
    m_packageVerified = false;

    QDir().mkpath(downloadsPath());
    if (!reconcileAuthenticatedDownloadPath(errorMessage)) {
        m_manifestVerified = false;
        return false;
    }
    const QString safeVersion = QString(version).replace(
        QRegularExpression(QStringLiteral("[^A-Za-z0-9._-]")), QStringLiteral("_"));
    m_manifestEnvelopePath = QDir(downloadsPath()).filePath(
        QStringLiteral("NeutronOS-%1.mainline-metadata.json").arg(safeVersion));
    const QByteArray exactEnvelope = QJsonDocument(envelope).toJson(QJsonDocument::Compact);
    QSaveFile file(m_manifestEnvelopePath);
    if (!file.open(QIODevice::WriteOnly) || file.write(exactEnvelope) != exactEnvelope.size() || !file.commit()) {
        m_manifestVerified = false;
        if (errorMessage) *errorMessage = QStringLiteral("Could not persist authenticated Mainline metadata safely.");
        return false;
    }
    saveState();
    emit stateChanged();
    return true;
}

bool UpdateRecoveryManager::downloadAvailableUpdate()
{
    if (m_busy || !m_updateAvailable || m_packageUrl.isEmpty())
        return false;
    QUrl url(m_packageUrl);
    if (!url.isValid())
        return false;

    QDir().mkpath(downloadsPath());
    const QString authenticatedName = m_manifest.value(QStringLiteral("name")).toString().trimmed();
    if (!safeArtifactBasename(authenticatedName)) {
        m_lastMessage = QStringLiteral("The authenticated update package name is unsafe.");
        emit stateChanged();
        return false;
    }
    const QString finalPath = QDir(downloadsPath()).filePath(authenticatedName);
    const QString partialPath = finalPath + QStringLiteral(".part");
    QFile::remove(partialPath);
    delete m_downloadFile;
    m_downloadFile = new QFile(partialPath, this);
    if (!m_downloadFile->open(QIODevice::WriteOnly)) {
        m_lastMessage = QStringLiteral("Could not create the update download file.");
        emit stateChanged();
        return false;
    }

    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("NeutronOS-Gemini-UpdateManager/1"));
    m_reply = m_network.get(request);
    connect(m_reply, &QNetworkReply::readyRead, this, &UpdateRecoveryManager::onDownloadReadyRead);
    connect(m_reply, &QNetworkReply::downloadProgress, this, &UpdateRecoveryManager::onDownloadProgress);
    connect(m_reply, &QNetworkReply::finished, this, &UpdateRecoveryManager::onDownloadFinished);
    m_downloadedPackage = finalPath;
    setBusy(Operation::Download, QStringLiteral("Downloading NeutronOS %1…").arg(m_availableVersion), 0);
    return true;
}

void UpdateRecoveryManager::onDownloadReadyRead()
{
    if (m_reply && m_downloadFile)
        m_downloadFile->write(m_reply->readAll());
}

void UpdateRecoveryManager::onDownloadProgress(qint64 received, qint64 total)
{
    if (total > 0)
        m_progress = static_cast<int>((received * 100) / total);
    m_status = QStringLiteral("Downloading %1 of %2").arg(humanBytes(received), humanBytes(total > 0 ? total : received));
    emit stateChanged();
}

void UpdateRecoveryManager::onDownloadFinished()
{
    QPointer<QNetworkReply> reply = m_reply;
    m_reply = nullptr;
    if (m_downloadFile) {
        if (reply)
            m_downloadFile->write(reply->readAll());
        m_downloadFile->flush();
        m_downloadFile->close();
    }
    const QString partialPath = m_downloadFile ? m_downloadFile->fileName() : QString();
    if (reply && reply->error() != QNetworkReply::NoError) {
        m_prepareInstallAfterDownload = false;
        QFile::remove(partialPath);
        const QString error = reply->errorString();
        reply->deleteLater();
        delete m_downloadFile;
        m_downloadFile = nullptr;
        finish(Operation::Download, false, QStringLiteral("Update download failed: %1").arg(error));
        return;
    }
    if (reply)
        reply->deleteLater();
    delete m_downloadFile;
    m_downloadFile = nullptr;

    QFile::remove(m_downloadedPackage);
    if (!QFile::rename(partialPath, m_downloadedPackage)) {
        m_prepareInstallAfterDownload = false;
        QFile::remove(partialPath);
        finish(Operation::Download, false, QStringLiteral("Could not finalize the downloaded update package."));
        return;
    }
    QString error;
    m_packageDownloaded = true;
    m_packageVerified = verifyDownloadedPackage(&error);
    if (!m_packageVerified) {
        m_prepareInstallAfterDownload = false;
        QFile::remove(m_downloadedPackage);
        m_packageDownloaded = false;
        finish(Operation::Download, false, error);
        return;
    }
    const bool readyForInstall = m_prepareInstallAfterDownload;
    m_prepareInstallAfterDownload = false;
    finish(Operation::Download, true, QStringLiteral("Update downloaded and signature verified."));
    if (readyForInstall)
        emit installCandidateReady(m_availableVersion, updateSizeText(), m_releaseNotes);
}

bool UpdateRecoveryManager::reloadPersistedCandidate(QString *errorMessage)
{
    loadState();
    if (m_availableVersion.isEmpty() || m_manifestEnvelopePath.isEmpty() ||
        m_packageUrl.isEmpty() || !isNewerVersion(m_availableVersion, m_currentVersion)) {
        if (errorMessage)
            *errorMessage = QStringLiteral("No compatible persisted NeutronOS update is available.");
        return false;
    }
    const QString persistedVersion = m_availableVersion;
    QFile envelopeFile(m_manifestEnvelopePath);
    if (!envelopeFile.open(QIODevice::ReadOnly)) {
        if (errorMessage)
            *errorMessage = QStringLiteral("The authenticated update metadata is no longer available. Check for updates again.");
        return false;
    }
    const QByteArray envelope = envelopeFile.readAll();
    if (!m_manifestSourceUrl.isEmpty())
        setProperty("manifestSourceUrl", QUrl(m_manifestSourceUrl));
    if (!parseManifest(envelope, errorMessage))
        return false;
    if (m_availableVersion != persistedVersion || !m_updateAvailable || !m_manifestVerified) {
        if (errorMessage)
            *errorMessage = QStringLiteral("The persisted update no longer authorizes this installed version.");
        return false;
    }
    return true;
}

bool UpdateRecoveryManager::prepareAvailableUpdateForInstall()
{
    if (m_busy)
        return false;
    QString error;
    if (!reloadPersistedCandidate(&error)) {
        m_lastMessage = error;
        emit stateChanged();
        return false;
    }
    if (m_packageDownloaded && QFileInfo::exists(m_downloadedPackage)) {
        m_packageVerified = verifyDownloadedPackage(&error);
        if (!m_packageVerified) {
            m_lastMessage = error;
            emit stateChanged();
            return false;
        }
        emit stateChanged();
        emit installCandidateReady(m_availableVersion, updateSizeText(), m_releaseNotes);
        return true;
    }
    m_prepareInstallAfterDownload = true;
    if (!downloadAvailableUpdate()) {
        m_prepareInstallAfterDownload = false;
        m_lastMessage = QStringLiteral("The persisted update package could not be downloaded.");
        emit stateChanged();
        return false;
    }
    return true;
}

bool UpdateRecoveryManager::verifyReleaseSignature(const QByteArray &metadata, const QByteArray &signature, QString *errorMessage) const
{
    if (metadata.isEmpty() || metadata.size() > kMaximumManifestBytes || signature.isEmpty() || signature.size() > 16384) {
        if (errorMessage) *errorMessage = QStringLiteral("Missing or oversized signed release metadata/signature.");
        return false;
    }
    // Explicit constructor injection preserves the existing isolated unit-test
    // collaborator. Production never reads keys from downloaded packages.
    if (!m_trustedPublicKeyPath.isEmpty()) {
        const QByteArray key = readPublicKey(errorMessage);
        const bool ok = key.size() == crypto_sign_PUBLICKEYBYTES && signature.size() == crypto_sign_BYTES &&
            crypto_sign_verify_detached(reinterpret_cast<const unsigned char *>(signature.constData()),
                reinterpret_cast<const unsigned char *>(metadata.constData()), metadata.size(),
                reinterpret_cast<const unsigned char *>(key.constData())) == 0;
        if (!ok && errorMessage && errorMessage->isEmpty()) *errorMessage = QStringLiteral("The release signature is not trusted.");
        return ok;
    }
    QTemporaryDir folder;
    QFile manifest(folder.filePath(QStringLiteral("manifest"))), sig(folder.filePath(QStringLiteral("signature")));
    if (!folder.isValid() || !manifest.open(QIODevice::WriteOnly) || manifest.write(metadata) != metadata.size() ||
        !sig.open(QIODevice::WriteOnly) || sig.write(signature) != signature.size()) {
        if (errorMessage) *errorMessage = QStringLiteral("Could not prepare release verification.");
        return false;
    }
    manifest.close();sig.close();QProcess verifier;
    verifier.start(QStringLiteral("/usr/local/libexec/neutronos-release-verify"),
        {QStringLiteral("verify"),manifest.fileName(),sig.fileName()});
    const bool done = verifier.waitForFinished(35000);
    if (!done) { verifier.kill();verifier.waitForFinished(1000); }
    const bool ok = done && verifier.exitStatus() == QProcess::NormalExit && verifier.exitCode() == 0;
    if (!ok && errorMessage) *errorMessage = QStringLiteral("The release signature is not trusted. %1").arg(QString::fromUtf8(verifier.readAllStandardError()).trimmed().left(600));
    return ok;
}

QByteArray UpdateRecoveryManager::readPublicKey(QString *errorMessage) const
{
    QFile file(publicKeyPath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (errorMessage) *errorMessage = QStringLiteral("No trusted NeutronOS update public key is installed.");
        return {};
    }
    QByteArray data = file.readAll().trimmed();
    if (data.startsWith("-----BEGIN PUBLIC KEY-----")) {
        QByteArray body = data;
        body.replace("-----BEGIN PUBLIC KEY-----", "");
        body.replace("-----END PUBLIC KEY-----", "");
        body.replace("\r", "");
        body.replace("\n", "");
        body.replace(" ", "");
        const QByteArray der = QByteArray::fromBase64(body);
        const QByteArray ed25519SpkiPrefix = QByteArray::fromHex("302a300506032b6570032100");
        if (der.size() == ed25519SpkiPrefix.size() + crypto_sign_PUBLICKEYBYTES &&
            der.startsWith(ed25519SpkiPrefix))
            return der.mid(ed25519SpkiPrefix.size());
        if (errorMessage) *errorMessage = QStringLiteral("The pinned PEM key is not an Ed25519 public key.");
        return {};
    }
    if (data.startsWith("NEUTRONOS-ED25519:"))
        data = data.mid(QByteArray("NEUTRONOS-ED25519:").size()).trimmed();
    QByteArray key = QByteArray::fromHex(data);
    if (key.size() != crypto_sign_PUBLICKEYBYTES)
        key = QByteArray::fromBase64(data);
    if (key.size() != crypto_sign_PUBLICKEYBYTES) {
        if (errorMessage) *errorMessage = QStringLiteral("The installed update public key is invalid.");
        return {};
    }
    return key;
}

bool UpdateRecoveryManager::verifyArtifactContent(const QString &path, QString *errorMessage) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (errorMessage) *errorMessage = QStringLiteral("The downloaded update package cannot be opened.");
        return false;
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&file)) {
        if (errorMessage) *errorMessage = QStringLiteral("The update package could not be hashed.");
        return false;
    }
    if (QString::fromLatin1(hash.result().toHex()) != m_expectedSha256) {
        if (errorMessage) *errorMessage = QStringLiteral("Update checksum verification failed. The package was discarded.");
        return false;
    }
    if (m_updateSize > 0 && static_cast<qulonglong>(file.size()) != m_updateSize) {
        if (errorMessage) *errorMessage = QStringLiteral("Update size verification failed against signed metadata.");
        return false;
    }
    return true;
}

bool UpdateRecoveryManager::reconcileAuthenticatedDownloadPath(QString *errorMessage)
{
    const QString authenticatedName = m_manifest.value(QStringLiteral("name")).toString().trimmed();
    if (!safeArtifactBasename(authenticatedName)) {
        if (errorMessage) *errorMessage = QStringLiteral("The authenticated update package name is unsafe.");
        return false;
    }
    const QString canonicalPath = QDir(downloadsPath()).filePath(authenticatedName);
    const QString previousPath = m_downloadedPackage;
    QString contentError;
    if (QFileInfo::exists(canonicalPath)) {
        m_downloadedPackage = canonicalPath;
        m_packageDownloaded = verifyArtifactContent(canonicalPath, &contentError);
        m_packageVerified = false;
        return true;
    }
    const QFileInfo previous(previousPath);
    const QFileInfo canonical(canonicalPath);
    if (!previousPath.isEmpty() && previous.isFile() &&
        previous.absolutePath() == canonical.absolutePath() &&
        previous.fileName() != authenticatedName &&
        verifyArtifactContent(previousPath, &contentError) &&
        QFile::rename(previousPath, canonicalPath)) {
        m_downloadedPackage = canonicalPath;
        m_packageDownloaded = true;
        m_packageVerified = false;
        return true;
    }
    m_downloadedPackage = canonicalPath;
    m_packageDownloaded = false;
    m_packageVerified = false;
    return true;
}

bool UpdateRecoveryManager::verifyDownloadedPackage(QString *errorMessage)
{
    if (!m_manifestVerified) {
        QFile envelopeFile(m_manifestEnvelopePath);
        if (m_manifestEnvelopePath.isEmpty() || !envelopeFile.open(QIODevice::ReadOnly)) {
            if (errorMessage) *errorMessage = QStringLiteral("The artifact is denied because its signed release manifest is unavailable.");
            return false;
        }
        const QByteArray envelope = envelopeFile.read(kMaximumManifestBytes + 1);
        if (envelope.size() > kMaximumManifestBytes) {
            if (errorMessage) *errorMessage = QStringLiteral("The cached signed release manifest exceeded the safety limit.");
            return false;
        }
        if (!m_manifestSourceUrl.isEmpty())
            setProperty("manifestSourceUrl", QUrl(m_manifestSourceUrl));
        if (!parseManifest(envelope, errorMessage))
            return false;
        m_packageDownloaded = !m_downloadedPackage.isEmpty() && QFileInfo::exists(m_downloadedPackage);
    }
    const QString authenticatedName = m_manifest.value(QStringLiteral("name")).toString().trimmed();
    if (!safeArtifactBasename(authenticatedName) ||
        QFileInfo(m_downloadedPackage).fileName() != authenticatedName) {
        if (errorMessage) *errorMessage = QStringLiteral("Authenticated package name does not match the downloaded artifact.");
        return false;
    }
    if (!verifyArtifactContent(m_downloadedPackage, errorMessage))
        return false;
    // The SHA-256 value is inside the exact payload authenticated above. A
    // second artifact signature is intentionally unnecessary and is not used
    // as a substitute for signed release metadata.
    return true;
}

bool UpdateRecoveryManager::beginProcess(Operation operation, const QString &program,
                                         const QStringList &arguments, const QString &status)
{
    if (m_busy || !m_process || m_process->state() != QProcess::NotRunning)
        return false;
    m_processOutput.clear();
    setBusy(operation, status, -1);
    m_process->start(program, arguments);
    if (!m_process->waitForStarted(3000)) {
        finish(operation, false, QStringLiteral("Could not start %1: %2").arg(program, m_process->errorString()));
        return false;
    }
    return true;
}

bool UpdateRecoveryManager::checkDebianUpdates()
{
    const QString apt = QStandardPaths::findExecutable(QStringLiteral("apt-get"));
    if (apt.isEmpty()) {
        m_lastMessage = QStringLiteral("apt-get is not installed.");
        emit stateChanged();
        return false;
    }
    return beginProcess(Operation::CheckDebian, apt,
                        {QStringLiteral("-s"), QStringLiteral("upgrade")},
                        QStringLiteral("Checking Debian package updates…"));
}

void UpdateRecoveryManager::onProcessReadyRead()
{
    if (m_process)
        m_processOutput.append(m_process->readAllStandardOutput());
}

void UpdateRecoveryManager::onProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    if (m_operation == Operation::None)
        return;
    if (m_process)
        m_processOutput.append(m_process->readAllStandardOutput());
    const Operation operation = m_operation;
    if (operation == Operation::SyncMainline) {
        const bool success = exitCode == 0 && status == QProcess::NormalExit;
        if (!success) {
            const QString detail = QString::fromLocal8Bit(m_processOutput).trimmed();
            finish(operation, false, detail.isEmpty()
                       ? QStringLiteral("Private Mainline synchronization failed.")
                       : QStringLiteral("Private Mainline synchronization failed: %1").arg(detail));
            return;
        }
        m_operation = Operation::None;
        m_busy = false;
        m_progress = -1;
        if (!fetchConfiguredManifest())
            finish(Operation::CheckManifest, false, QStringLiteral("Could not read the synchronized Mainline index."));
        return;
    }
    if (operation == Operation::CheckDebian) {
        const QString output = QString::fromLocal8Bit(m_processOutput);
        int count = 0;
        const QStringList lines = output.split(QLatin1Char('\n'));
        for (const QString &line : lines)
            if (line.startsWith(QStringLiteral("Inst "))) ++count;
        m_debianUpdatesAvailable = count;
        finish(operation, exitCode == 0 && status == QProcess::NormalExit,
               exitCode == 0 ? QStringLiteral("%1 Debian package update(s) available.").arg(count)
                             : QStringLiteral("Debian update check failed."));
        return;
    }
    if (operation == Operation::CreateRecovery) {
        refreshRecoveryState();
        finish(operation, exitCode == 0 && status == QProcess::NormalExit,
               exitCode == 0 ? QStringLiteral("Recovery point created successfully.")
                             : QStringLiteral("Recovery point creation failed: %1").arg(QString::fromLocal8Bit(m_processOutput).trimmed()));
        return;
    }
    if (operation == Operation::StageUpdate) {
        const bool success = exitCode == 0 && status == QProcess::NormalExit;
        const QString detail = QString::fromLocal8Bit(m_processOutput).trimmed();
        finish(operation, success,
               success ? QStringLiteral("Verified update staged. Rebooting into Recovery to apply it.")
                       : QStringLiteral("Update staging failed: %1").arg(detail.isEmpty()
                             ? QStringLiteral("privileged helper failed") : detail));
        return;
    }
    finish(operation, exitCode == 0 && status == QProcess::NormalExit,
           exitCode == 0 ? QStringLiteral("Operation completed.") : QStringLiteral("Operation failed."));
}

bool UpdateRecoveryManager::installDebianUpdates()
{
    return startDetachedRecoveryAction(QStringLiteral("debian-upgrade"), {},
                                       QStringLiteral("Installing Debian package updates"));
}

QVariantMap UpdateRecoveryManager::verifyManifestFiles(const QString &root, const QString &manifestPath)
{
    QVariantList failures;
    int checked = 0;
    QFile manifest(manifestPath);
    if (!manifest.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QVariantMap failure;
        failure.insert(QStringLiteral("path"), manifestPath);
        failure.insert(QStringLiteral("reason"), QStringLiteral("Missing manifest"));
        QVariantMap result;
        result.insert(QStringLiteral("success"), false);
        result.insert(QStringLiteral("checked"), 0);
        result.insert(QStringLiteral("failed"), 1);
        result.insert(QStringLiteral("summary"), QStringLiteral("Release manifest is missing."));
        result.insert(QStringLiteral("failures"), QVariantList{failure});
        return result;
    }
    QTextStream stream(&manifest);
    while (!stream.atEnd()) {
        const QString line = stream.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        const int separator = line.indexOf(QRegularExpression(QStringLiteral("\\s+")));
        if (separator <= 0)
            continue;
        const QString expected = line.left(separator).trimmed().toLower();
        QString relative = line.mid(separator).trimmed();
        while (relative.startsWith(QLatin1Char('*')) || relative.startsWith(QLatin1Char(' ')))
            relative.remove(0, 1);
        if (!safeRelativePath(relative))
            continue;
        ++checked;
        const QString absolute = QDir(root).filePath(relative);
        QFile file(absolute);
        if (!file.open(QIODevice::ReadOnly)) {
            failures.append(QVariantMap{{QStringLiteral("path"), relative}, {QStringLiteral("reason"), QStringLiteral("Missing or unreadable")}});
            continue;
        }
        QCryptographicHash hash(QCryptographicHash::Sha256);
        hash.addData(&file);
        const QString actual = QString::fromLatin1(hash.result().toHex());
        if (actual != expected)
            failures.append(QVariantMap{{QStringLiteral("path"), relative}, {QStringLiteral("reason"), QStringLiteral("Checksum mismatch")}});
    }
    const bool success = failures.isEmpty();
    return {{QStringLiteral("success"), success},
            {QStringLiteral("checked"), checked},
            {QStringLiteral("failed"), failures.size()},
            {QStringLiteral("summary"), success ? QStringLiteral("%1 release files verified.").arg(checked)
                                                 : QStringLiteral("%1 of %2 release files failed verification.").arg(failures.size()).arg(checked)},
            {QStringLiteral("failures"), failures}};
}

bool UpdateRecoveryManager::verifyInstallation()
{
    if (m_busy || m_integrityWatcher->isRunning())
        return false;
    setBusy(Operation::VerifyIntegrity, QStringLiteral("Verifying NeutronOS release files…"), -1);
    const QString root = m_neutronRoot;
    const QString manifest = releaseManifestPath();
    m_integrityWatcher->setFuture(QtConcurrent::run([root, manifest]() {
        return verifyManifestFiles(root, manifest);
    }));
    return true;
}

void UpdateRecoveryManager::onIntegrityFinished()
{
    if (m_operation != Operation::VerifyIntegrity)
        return;
    m_integrityReport = m_integrityWatcher->result();
    m_integritySummary = m_integrityReport.value(QStringLiteral("summary")).toString();
    emit integrityChanged();
    finish(Operation::VerifyIntegrity, m_integrityReport.value(QStringLiteral("success")).toBool(), m_integritySummary);
}

bool UpdateRecoveryManager::createRecoveryPoint(const QString &label)
{
    if (m_busy)
        return false;
    const QString helper = helperPath();
    if (!QFileInfo::exists(helper)) {
        m_lastMessage = QStringLiteral("Update/recovery helper is missing.");
        emit stateChanged();
        return false;
    }
    const QString sudo = qEnvironmentVariableIsSet("NEUTRONOS_UPDATE_TEST_ROOT")
        ? qEnvironmentVariable("NEUTRONOS_UPDATE_TEST_SUDO").trimmed()
        : QStandardPaths::findExecutable(QStringLiteral("sudo"));
    if (sudo.isEmpty()) {
        m_lastMessage = QStringLiteral("Privileged recovery-point creation is unavailable.");
        emit stateChanged();
        return false;
    }
    return beginProcess(Operation::CreateRecovery, sudo,
                        {QStringLiteral("-n"), helper, QStringLiteral("create-recovery"), label.trimmed()},
                        QStringLiteral("Creating a verified recovery point…"));
}

bool UpdateRecoveryManager::startDetachedRecoveryAction(const QString &action,
                                                        const QStringList &arguments,
                                                        const QString &description)
{
    if (m_busy)
        return false;
    const QString systemdRun = QStandardPaths::findExecutable(QStringLiteral("systemd-run"));
    const QString helper = helperPath();
    if (systemdRun.isEmpty() || !QFileInfo::exists(helper)) {
        m_lastMessage = QStringLiteral("The systemd update/recovery helper is unavailable.");
        emit stateChanged();
        return false;
    }
    const QString unit = QStringLiteral("neutronos-update-%1-%2")
                             .arg(action, QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyyMMddhhmmss")));
    QStringList command{QStringLiteral("--unit=") + unit, QStringLiteral("--collect"),
                        QStringLiteral("--property=Type=exec"), helper, action};
    command.append(arguments);
    qint64 pid = 0;
    const bool started = QProcess::startDetached(systemdRun, command, QString(), &pid);
    if (!started) {
        m_lastMessage = QStringLiteral("Could not hand the operation to systemd.");
        emit stateChanged();
        return false;
    }
    const QString message = description + QStringLiteral(". NeutronOS may restart automatically.");
    appendHistory(action, true, message, {{QStringLiteral("unit"), unit}});
    m_status = QStringLiteral("System operation scheduled");
    m_lastMessage = message;
    emit stateChanged();
    emit restartScheduled(description);
    return true;
}

bool UpdateRecoveryManager::installDownloadedUpdate()
{
    QString error;
    if (!m_packageDownloaded || !QFileInfo::exists(m_downloadedPackage)) {
        m_lastMessage = QStringLiteral("No downloaded NeutronOS update is ready.");
        emit stateChanged();
        return false;
    }
    // Re-verify every time, even if this process verified the download earlier.
    // The privileged helper repeats signature + digest validation yet again.
    m_packageVerified = verifyDownloadedPackage(&error);
    if (!m_packageVerified) {
        m_lastMessage = error;
        emit stateChanged();
        return false;
    }
    const QString sudo = QStandardPaths::findExecutable(QStringLiteral("sudo"));
    const QString helper = helperPath();
    if (sudo.isEmpty() || !QFileInfo(sudo).isExecutable() || !QFileInfo(helper).isExecutable()) {
        m_lastMessage = QStringLiteral("The privileged Update/Recovery staging helper is unavailable.");
        emit stateChanged();
        return false;
    }
    return beginProcess(Operation::StageUpdate, sudo,
                        {QStringLiteral("-n"), helper, QStringLiteral("stage-update"),
                         m_downloadedPackage, m_manifestEnvelopePath, m_availableVersion},
                        QStringLiteral("Re-verifying and staging NeutronOS %1 for Recovery…").arg(m_availableVersion));
}

bool UpdateRecoveryManager::rollbackLastUpdate()
{
    refreshRecoveryState();
    if (m_latestRecoveryPoint.isEmpty()) {
        m_lastMessage = QStringLiteral("No recovery point is available to roll back.");
        emit stateChanged();
        return false;
    }
    return startDetachedRecoveryAction(QStringLiteral("prepare-rollback"), {m_latestRecoveryPoint},
                                       QStringLiteral("Preparing rollback request without replacing the running OS"));
}

bool UpdateRecoveryManager::repairInstallation()
{
    return startDetachedRecoveryAction(QStringLiteral("repair"), {},
                                       QStringLiteral("Rebuilding and repairing the current NeutronOS installation"));
}

bool UpdateRecoveryManager::prepareSafeMode()
{
    QDir().mkpath(QFileInfo(safeModeFlagPath()).absolutePath());
    QSaveFile file(safeModeFlagPath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        m_lastMessage = QStringLiteral("Could not prepare Safe Mode.");
        emit stateChanged();
        return false;
    }
    const QByteArray payload = nowIso().toUtf8() + '\n';
    if (file.write(payload) != payload.size() || !file.commit()) {
        m_lastMessage = QStringLiteral("Could not commit the Safe Mode flag.");
        emit stateChanged();
        return false;
    }
    refreshRecoveryState();
    m_lastMessage = QStringLiteral("Safe Mode is prepared for the next NeutronOS start.");
    appendHistory(QStringLiteral("safe-mode"), true, m_lastMessage);
    emit stateChanged();
    return true;
}

bool UpdateRecoveryManager::cancelSafeMode()
{
    const bool removed = !QFileInfo::exists(safeModeFlagPath()) || QFile::remove(safeModeFlagPath());
    refreshRecoveryState();
    m_lastMessage = removed ? QStringLiteral("Safe Mode preparation cancelled.")
                            : QStringLiteral("Could not remove the Safe Mode flag.");
    emit stateChanged();
    return removed;
}

bool UpdateRecoveryManager::prepareRecoveryMode()
{
    if (!m_developerModeManager || !m_developerModeManager->developerModeEnabled()) {
        m_lastMessage = QStringLiteral("Recovery Mode is available only while Developer Mode is enabled.");
        emit stateChanged();
        return false;
    }
    QProcess process;
    process.setProgram(recoveryControlPath());
    process.setArguments({QStringLiteral("prepare"),
                          QStringLiteral("Developer requested a one-shot local recovery terminal.")});
    process.start();
    const bool ok = process.waitForStarted(3000) && process.waitForFinished(5000) &&
                    process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
    refreshRecoveryState();
    m_lastMessage = ok
        ? QStringLiteral("Recovery Mode is prepared for one boot. Reboot was not performed.")
        : QStringLiteral("Recovery Mode could not be prepared: %1")
              .arg(QString::fromUtf8(process.readAllStandardError()).trimmed());
    appendHistory(QStringLiteral("recovery-mode"), ok, m_lastMessage);
    emit stateChanged();
    return ok;
}

bool UpdateRecoveryManager::cancelRecoveryMode()
{
    QProcess process;
    process.setProgram(recoveryControlPath());
    process.setArguments({QStringLiteral("cancel")});
    process.start();
    const bool ok = process.waitForStarted(3000) && process.waitForFinished(5000) &&
                    process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
    refreshRecoveryState();
    m_lastMessage = ok ? QStringLiteral("One-shot Recovery Mode cancelled.")
                       : QStringLiteral("Recovery Mode cancellation failed.");
    emit stateChanged();
    return ok;
}

bool UpdateRecoveryManager::clearUpdateCache()
{
    if (m_busy)
        return false;
    QDir directory(downloadsPath());
    bool success = true;
    if (directory.exists()) {
        const QFileInfoList entries = directory.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
        for (const QFileInfo &entry : entries)
            success = QFile::remove(entry.absoluteFilePath()) && success;
    }
    if (!m_manifestEnvelopePath.isEmpty()) QFile::remove(m_manifestEnvelopePath);
    m_downloadedPackage.clear();
    m_manifestEnvelopePath.clear();
    m_manifestSourceUrl.clear();
    m_packageDownloaded = false;
    m_packageVerified = false;
    m_manifestVerified = false;
    saveState();
    m_lastMessage = success ? QStringLiteral("Downloaded update files were cleared.")
                            : QStringLiteral("Some update files could not be removed.");
    appendHistory(QStringLiteral("clear-update-cache"), success, m_lastMessage);
    emit stateChanged();
    return success;
}

bool UpdateRecoveryManager::cancelCurrentOperation()
{
    if (!m_busy)
        return false;
    const Operation operation = m_operation;

    if (m_reply) {
        QNetworkReply *reply = m_reply.data();
        m_reply = nullptr;
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    if (m_process && m_process->state() != QProcess::NotRunning) {
        const QSignalBlocker blocker(m_process);
        m_process->kill();
        m_process->waitForFinished(1500);
    }
    if (operation == Operation::VerifyIntegrity && m_integrityWatcher->isRunning())
        m_integrityWatcher->cancel();
    if (m_downloadFile) {
        const QString path = m_downloadFile->fileName();
        m_downloadFile->close();
        QFile::remove(path);
        delete m_downloadFile;
        m_downloadFile = nullptr;
    }
    finish(operation, false, QStringLiteral("Operation cancelled."));
    return true;
}

QString UpdateRecoveryManager::historyText() const
{
    if (m_history.isEmpty())
        return QStringLiteral("No update or recovery operations have been recorded yet.");
    QStringList lines;
    const int count = qMin(30, static_cast<int>(m_history.size()));
    for (int i = 0; i < count; ++i) {
        const QVariantMap entry = m_history.at(i).toMap();
        lines.append(QStringLiteral("%1  •  %2  •  %3\n%4")
                         .arg(displayTimestamp(entry.value(QStringLiteral("timestamp")).toString()),
                              entry.value(QStringLiteral("success")).toBool() ? QStringLiteral("SUCCESS") : QStringLiteral("FAILED"),
                              entry.value(QStringLiteral("type")).toString().toUpper(),
                              entry.value(QStringLiteral("message")).toString()));
    }
    return lines.join(QStringLiteral("\n\n"));
}

QString UpdateRecoveryManager::integrityReportText() const
{
    if (m_integrityReport.isEmpty())
        return QStringLiteral("Run Verify Installation to compare the live NeutronOS files with the signed release manifest.");
    QStringList lines{m_integritySummary};
    const QVariantList failures = m_integrityReport.value(QStringLiteral("failures")).toList();
    const int limit = qMin(50, static_cast<int>(failures.size()));
    for (int i = 0; i < limit; ++i) {
        const QVariantMap failure = failures.at(i).toMap();
        lines.append(QStringLiteral("• %1 — %2")
                         .arg(failure.value(QStringLiteral("path")).toString(),
                              failure.value(QStringLiteral("reason")).toString()));
    }
    if (failures.size() > limit)
        lines.append(QStringLiteral("…and %1 additional failure(s).").arg(failures.size() - limit));
    return lines.join(QLatin1Char('\n'));
}

QString UpdateRecoveryManager::humanBytes(qulonglong bytes)
{
    static const QStringList units{QStringLiteral("B"), QStringLiteral("KiB"),
                                   QStringLiteral("MiB"), QStringLiteral("GiB"),
                                   QStringLiteral("TiB")};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < units.size() - 1) {
        value /= 1024.0;
        ++unit;
    }
    return QStringLiteral("%1 %2").arg(value, 0, 'f', unit == 0 ? 0 : 1).arg(units.at(unit));
}

bool UpdateRecoveryManager::isNewerVersion(const QString &candidate, const QString &current)
{
    struct SemVer { QVersionNumber core; QStringList pre; bool valid = false; };
    auto parse = [](const QString &value) {
        SemVer result;
        const auto match = QRegularExpression(
            QStringLiteral("(?:^|\\s)(\\d+)\\.(\\d+)\\.(\\d+)(?:-([0-9A-Za-z.-]+))?(?:\\+[0-9A-Za-z.-]+)?(?:$|\\s)"))
                               .match(value.trimmed());
        if (!match.hasMatch())
            return result;
        result.core = QVersionNumber({match.captured(1).toInt(), match.captured(2).toInt(), match.captured(3).toInt()});
        result.pre = match.captured(4).split(QLatin1Char('.'), Qt::SkipEmptyParts);
        result.valid = true;
        return result;
    };
    const SemVer left = parse(candidate), right = parse(current);
    if (!left.valid || !right.valid)
        return false;
    const int coreComparison = QVersionNumber::compare(left.core, right.core);
    if (coreComparison != 0)
        return coreComparison > 0;
    if (left.pre.isEmpty() != right.pre.isEmpty())
        return left.pre.isEmpty(); // A stable release sorts after prereleases.
    for (int index = 0; index < qMax(left.pre.size(), right.pre.size()); ++index) {
        if (index >= left.pre.size()) return false;
        if (index >= right.pre.size()) return true;
        const QString a = left.pre.at(index), b = right.pre.at(index);
        if (a == b) continue;
        bool aNumber = false, bNumber = false;
        const qulonglong an = a.toULongLong(&aNumber), bn = b.toULongLong(&bNumber);
        if (aNumber && bNumber) return an > bn;
        if (aNumber != bNumber) return !aNumber; // Non-numeric identifiers sort after numeric.
        return QString::compare(a, b, Qt::CaseSensitive) > 0;
    }
    return false;
}
