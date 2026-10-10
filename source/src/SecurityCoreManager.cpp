#include "SecurityCoreManager.h"
#include "SecurityManager.h"

#include <QDir>
#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonValue>
#include <QProcessEnvironment>
#include <QtConcurrent/QtConcurrentRun>

namespace {
QString valueFromSessionFile(const QByteArray &contents, const QByteArray &key)
{
    for (const QByteArray &line : contents.split('\n')) {
        if (line.startsWith(key + '='))
            return QString::fromUtf8(line.mid(key.size() + 1)).trimmed();
    }
    return {};
}
}

SecurityCoreManager::SecurityCoreManager(const QString &neutronRoot,
                                         SecurityManager *authManager, QObject *parent)
    : QObject(parent), m_neutronRoot(QDir(neutronRoot).absolutePath()), m_authManager(authManager)
{
    m_healthTimer.setInterval(5000);
    m_healthTimer.setSingleShot(false);
    connect(&m_healthTimer, &QTimer::timeout, this, &SecurityCoreManager::refresh);
    m_healthTimer.start();

    m_secretTimer.setSingleShot(true);
    m_secretTimer.setInterval(30000);
    connect(&m_secretTimer, &QTimer::timeout, this, &SecurityCoreManager::clearRevealedVaultSecret);

    if (m_authManager) {
        connect(m_authManager, &SecurityManager::activeUserChanged, this, &SecurityCoreManager::refresh);
        connect(m_authManager, &SecurityManager::pamSessionChanged, this, &SecurityCoreManager::refresh);
    }
    connect(&m_watcher, &QFutureWatcher<Completion>::finished, this, [this]() {
        const Completion completion = m_watcher.result();
        const SecureIpcClient::Result &result = completion.result;
        if (completion.request.snapshot)
            m_refreshQueued = false;
        if (!result.transportOk || !result.serviceOk) {
            const QString code = !result.transportOk
                ? (result.errorCode == QStringLiteral("invalid_identity")
                   ? QStringLiteral("invalid_session") : QStringLiteral("service_unavailable"))
                : (result.errorCode.isEmpty() ? QStringLiteral("internal_error") : result.errorCode);
            const QString message = result.errorMessage.isEmpty() ? QStringLiteral("Security service unavailable") : result.errorMessage;

            // Only a failed status snapshot is evidence that the Security Core
            // itself may be unavailable. A slow/rejected mutation must not make
            // the entire app, firewall and score appear offline.
            if (completion.request.snapshot) {
                markUnavailable(code, message);
            } else {
                m_lastErrorCode = code;
                emit operationFinished(false, message);
                // Reconcile with authoritative state after a mutation failure.
                enqueue(QStringLiteral("security.snapshot"), {}, true);
            }
        } else {
            m_daemonOnline = true;
            m_lastErrorCode.clear();
            const QJsonObject payload = result.response.value(QStringLiteral("result")).toObject();
            if (completion.request.snapshot) {
                applySnapshot(payload.value(QStringLiteral("state")).toObject());
            } else {
                const bool success = payload.value(QStringLiteral("success")).toBool(true);
                const QString message = payload.value(QStringLiteral("message")).toString(
                    success ? QStringLiteral("Security operation completed") : QStringLiteral("Security operation was rejected"));
                if (payload.contains(QStringLiteral("recoveryCode")))
                    m_generatedRecoveryCode = payload.value(QStringLiteral("recoveryCode")).toString();
                if (payload.contains(QStringLiteral("secret"))) {
                    m_revealedVaultSecret = payload.value(QStringLiteral("secret")).toObject().toVariantMap();
                    m_secretTimer.start();
                }
                emit stateChanged();
                emit operationFinished(success, message);
                // Vault factor verification and unlock are now one daemon-side
                // authorization decision.  Never turn a successful client-side
                // verification into an argument-free privileged unlock.
                enqueue(QStringLiteral("security.snapshot"), {}, true);
            }
        }
        startNext();
    });
    QTimer::singleShot(0, this, &SecurityCoreManager::refresh);
}

SecurityCoreManager::~SecurityCoreManager()
{
    if (m_watcher.isRunning())
        m_watcher.waitForFinished();
    m_revealedVaultSecret.clear();
    m_generatedRecoveryCode.clear();
    m_requests.clear();
}

QString SecurityCoreManager::activeSessionId(const QString &username) const
{
    const QDir sessions(QStringLiteral("/run/systemd/sessions"));
    QString localSession;
    QString displaySession;
    const QString shellUser = QProcessEnvironment::systemEnvironment().value(QStringLiteral("USER"));
    for (const QString &name : sessions.entryList(QDir::Files | QDir::NoDotAndDotDot)) {
        QFile file(sessions.filePath(name));
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QByteArray data = file.readAll();
        const QString sessionUser = valueFromSessionFile(data, QByteArrayLiteral("USER"));
        const QString active = valueFromSessionFile(data, QByteArrayLiteral("ACTIVE"));
        const QString state = valueFromSessionFile(data, QByteArrayLiteral("STATE"));
        if (active != QStringLiteral("1") ||
            (state != QStringLiteral("active") && state != QStringLiteral("online")))
            continue;
        if (sessionUser != username) {
            // A verified controller combo authenticates in the display shell,
            // without a human PAM session. The daemon independently verifies
            // the exact shell process and this local logind display session.
            if (sessionUser == shellUser &&
                valueFromSessionFile(data, QByteArrayLiteral("IS_DISPLAY")) == QStringLiteral("1") &&
                valueFromSessionFile(data, QByteArrayLiteral("REMOTE")) == QStringLiteral("0") &&
                !valueFromSessionFile(data, QByteArrayLiteral("SEAT")).isEmpty())
                displaySession = name;
            continue;
        }

        const QString remote = valueFromSessionFile(data, QByteArrayLiteral("REMOTE"));
        if (remote == QStringLiteral("1"))
            continue; // An SSH session must never replace local shell identity.
        const QString leader = valueFromSessionFile(data, QByteArrayLiteral("LEADER"));
        if (leader.toLongLong() == QCoreApplication::applicationPid())
            return name;
        if (localSession.isEmpty())
            localSession = name;
    }
    if (!localSession.isEmpty())
        return localSession;
    if (!displaySession.isEmpty())
        return displaySession;
    return {};
}

SecureIpcClient::Identity SecurityCoreManager::identity() const
{
    SecureIpcClient::Identity value;
    value.user = m_authManager ? m_authManager->activeUsername().trimmed() : QString();
    if (value.user.isEmpty())
        value.user = QProcessEnvironment::systemEnvironment().value(QStringLiteral("USER"));
    value.sessionId = activeSessionId(value.user);
    value.applicationId = QStringLiteral("security");
    value.applicationInstance = QStringLiteral("neutronshell-security-core");
    return value;
}

QVariantMap SecurityCoreManager::authenticatedSessionIdentity() const
{
    if (!m_shellSessionAuthenticated)
        return {};

    const SecureIpcClient::Identity value = identity();
    if (value.user.trimmed().isEmpty())
        return {};

    return QVariantMap{
        {QStringLiteral("userName"), value.user.trimmed()},
        {QStringLiteral("sessionId"), value.sessionId.trimmed()}
    };
}

bool SecurityCoreManager::enqueue(const QString &operation, const QJsonObject &arguments, bool snapshot)
{
    if (snapshot && m_refreshQueued)
        return true;
    if (snapshot)
        m_refreshQueued = true;
    m_requests.enqueue({operation, arguments, snapshot});
    startNext();
    return true;
}

void SecurityCoreManager::startNext()
{
    if (m_watcher.isRunning() || m_requests.isEmpty())
        return;
    const Request request = m_requests.dequeue();
    const SecureIpcClient::Identity requestIdentity = identity();
    const QString socketPath = m_socketPath;
    m_watcher.setFuture(QtConcurrent::run([request, requestIdentity, socketPath]() {
        Completion completion;
        completion.request = request;

        // Snapshots should fail fast. Normal mutations get enough time for
        // service/firewall changes on the Raspberry Pi, while integrity and
        // hardening operations get a wider window because they legitimately
        // hash or rewrite many files. Malware scans are asynchronous server-side.
        int timeoutMs = request.snapshot ? 4000 : 15000;
        if (request.operation == QStringLiteral("security.verify-integrity") ||
            request.operation == QStringLiteral("security.create-integrity-baseline") ||
            request.operation == QStringLiteral("security.apply-hardening") ||
            request.operation == QStringLiteral("security.rollback-hardening"))
            timeoutMs = 60000;

        completion.result = SecureIpcClient::request(socketPath, QStringLiteral("security"),
                                                     request.operation, request.arguments,
                                                     requestIdentity, timeoutMs);
        completion.request.arguments = {};
        return completion;
    }));
}

QVariantList SecurityCoreManager::list(const QJsonObject &state, const char *name)
{
    return state.value(QLatin1String(name)).toArray().toVariantList();
}

QString SecurityCoreManager::integrityChangeKey(const QVariantMap &change)
{
    static constexpr const char *keys[] = {
        "id", "eventId", "path", "file", "target", "name", "component"
    };

    for (const char *key : keys) {
        const QString value =
            change.value(QLatin1String(key)).toString().trimmed();

        if (!value.isEmpty())
            return value;
    }

    return {};
}

void SecurityCoreManager::applySnapshot(const QJsonObject &state)
{
    if (state.isEmpty()) {
        markUnavailable(QStringLiteral("invalid_response"), QStringLiteral("Security service returned no state"));
        return;
    }
    m_daemonOnline = true;
    m_consecutiveIpcFailures = 0;
    m_daemonStatus = state.value(QStringLiteral("daemonStatus")).toString(QStringLiteral("Security core online"));
    m_lastErrorCode.clear();
    m_securityScore = state.value(QStringLiteral("securityScore")).toInt();
    m_threatLevel = state.value(QStringLiteral("threatLevel")).toInt(5);
    m_threatLabel = state.value(QStringLiteral("threatLabel")).toString(QStringLiteral("DEFCON %1").arg(m_threatLevel));
    m_suggestedThreatReason = state.value(QStringLiteral("suggestedThreatReason")).toString();
    m_learningMode = state.value(QStringLiteral("learningMode")).toBool();
    m_enforcementEnabled = state.value(QStringLiteral("enforcementEnabled")).toBool();
    m_responseEngineEnabled = state.value(QStringLiteral("responseEngineEnabled")).toBool();
    const QVariantList nextEvents = list(state, "events");
    QSet<QString> nextIds;
    for (const QVariant &value : nextEvents) {
        const QVariantMap event = value.toMap();
        const QString id = event.value(QStringLiteral("id")).toString();
        if (!id.isEmpty()) {
            nextIds.insert(id);
            if (m_eventBaselineReady && !m_seenEventIds.contains(id))
                emit securityEventRaised(event);
        }
    }
    m_events = nextEvents;
    m_seenEventIds = nextIds;
    m_eventBaselineReady = true;
    m_listeningPorts = list(state, "listeningPorts");
    m_bannedSources = list(state, "bannedSources");
    m_rejectedActivity = list(state, "rejectedActivity");
    m_auditEntries = list(state, "auditEntries");
    m_installedApps = list(state, "installedApps");
    m_sshStatus = state.value(QStringLiteral("sshStatus")).toObject().toVariantMap();
    m_tailscaleStatus = state.value(QStringLiteral("tailscaleStatus")).toObject().toVariantMap();
    m_vaultCombo = state.value(QStringLiteral("vaultCombo")).toObject().toVariantMap();
    m_peripherals = list(state, "peripherals");
    m_malwareFindings = list(state, "malwareFindings");
    m_quarantinedItems = list(state, "quarantinedItems");
    m_quarantinedApps = list(state, "quarantinedApps");
    m_integrityChanges = list(state, "integrityChanges");
    for (QVariant &value : m_integrityChanges) {
        QVariantMap change = value.toMap();
        const QString key = integrityChangeKey(change);

        if (!key.isEmpty() &&
                m_flaggedIntegrityChangeKeys.contains(key)) {
            change[QStringLiteral("flagged")] = true;
        }

        value = change;
    }
    m_integrityStatus = state.value(QStringLiteral("integrityStatus")).toString(QStringLiteral("UNAVAILABLE"));
    m_hardeningProfiles = list(state, "hardeningProfiles");
    m_activeHardeningProfile = state.value(QStringLiteral("activeHardeningProfile")).toString(QStringLiteral("none"));
    m_hardeningRollbackAvailable = state.value(QStringLiteral("hardeningRollbackAvailable")).toBool();
    m_vaultUnlocked = state.value(QStringLiteral("vaultUnlocked")).toBool();
    m_vaultEntries = list(state, "vaultEntries");
    m_recoveryConfigured = state.value(QStringLiteral("recoveryConfigured")).toBool();
    const QJsonObject recovery = state.value(QStringLiteral("recovery")).toObject();
    m_recoveryMethod = recovery.value(QStringLiteral("primaryMethod")).toString(QStringLiteral("none"));
    m_recoveryUsbCandidates = list(state, "recoveryUsbCandidates");
    m_auditValid = state.value(QStringLiteral("auditValid")).toBool();
    m_auditHead = state.value(QStringLiteral("auditHead")).toString(QStringLiteral("Unavailable"));
    m_stats = state.value(QStringLiteral("stats")).toObject().toVariantMap();
    const bool scanRunning = m_stats.value(QStringLiteral("scanRunning")).toBool();
    m_healthTimer.setInterval(scanRunning ? 1000 : 5000);
    emit stateChanged();
}

void SecurityCoreManager::markUnavailable(const QString &code, const QString &message)
{
    m_lastErrorCode = code;

    // Authentication loss is authoritative. Do not retain privileged session
    // state after logout or an invalid authenticated session.
    if (code == QStringLiteral("invalid_session")) {
        m_consecutiveIpcFailures = 0;
        m_daemonOnline = false;
        m_daemonStatus = message;
        m_securityScore = 0;
        m_events.clear();
        m_listeningPorts.clear();
        m_bannedSources.clear();
        m_rejectedActivity.clear();
        m_auditEntries.clear();
        m_installedApps.clear();
        m_sshStatus.clear();
        m_tailscaleStatus.clear();
        m_vaultCombo.clear();
        m_peripherals.clear();
        m_malwareFindings.clear();
        m_quarantinedItems.clear();
        m_quarantinedApps.clear();
        m_integrityChanges.clear();
        m_integrityStatus = QStringLiteral("UNAVAILABLE");
        m_vaultUnlocked = false;
        m_vaultEntries.clear();
        m_revealedVaultSecret.clear();
        m_auditValid = false;
        m_auditHead = QStringLiteral("Unavailable");
        m_stats.clear();
        emit stateChanged();
        return;
    }

    ++m_consecutiveIpcFailures;

    // A single slow operation or transient IPC hiccup must not erase the
    // last-known-good Security state. Preserve score, DEFCON, firewall,
    // integrity, events and telemetry while the client retries.
    if (m_consecutiveIpcFailures < 3) {
        m_daemonStatus = QStringLiteral("STALE - Retrying security service");
        emit stateChanged();

        QTimer::singleShot(750, this, [this]() {
            if (m_shellSessionAuthenticated ||
                !m_authManager ||
                m_authManager->pamSessionOpen()) {
                refresh();
            }
        });
        return;
    }

    // Three consecutive failures indicate a meaningful service outage.
    // Mark connectivity offline, but still preserve the last-known-good
    // protection data instead of replacing real values with fake zeroes.
    m_daemonOnline = false;
    m_daemonStatus = QStringLiteral("Security service unavailable - last known state retained");
    emit stateChanged();

    QTimer::singleShot(2000, this, [this]() {
        if (m_shellSessionAuthenticated ||
            !m_authManager ||
            m_authManager->pamSessionOpen()) {
            refresh();
        }
    });
}

void SecurityCoreManager::refresh()
{
    if (!m_shellSessionAuthenticated &&
            m_authManager && !m_authManager->pamSessionOpen()) {
        if (m_daemonOnline || m_lastErrorCode != QStringLiteral("invalid_session"))
            markUnavailable(QStringLiteral("invalid_session"), QStringLiteral("Sign in to access Security status"));
        return;
    }
    enqueue(QStringLiteral("security.snapshot"), {}, true);
}

void SecurityCoreManager::setShellSessionAuthenticated(bool authenticated)
{
    if (m_shellSessionAuthenticated == authenticated)
        return;
    m_shellSessionAuthenticated = authenticated;
    if (authenticated)
        refresh();
    else
        markUnavailable(QStringLiteral("invalid_session"),
                        QStringLiteral("Sign in to access Security status"));
}
void SecurityCoreManager::setLearningMode(bool v) { enqueue(QStringLiteral("security.set-learning-mode"), {{QStringLiteral("enabled"), v}}); }
void SecurityCoreManager::setEnforcementEnabled(bool v) { enqueue(QStringLiteral("security.set-enforcement-enabled"), {{QStringLiteral("enabled"), v}}); }
void SecurityCoreManager::setResponseEngineEnabled(bool v) { enqueue(QStringLiteral("security.set-response-engine-enabled"), {{QStringLiteral("enabled"), v}}); }
void SecurityCoreManager::acknowledgeEvent(const QString &v) { enqueue(QStringLiteral("security.acknowledge-event"), {{QStringLiteral("eventId"), v}}); }
void SecurityCoreManager::acknowledgeAllEvents() { enqueue(QStringLiteral("security.acknowledge-all-events")); }
void SecurityCoreManager::setEventFlagged(const QString &v, bool flagged) { enqueue(QStringLiteral("security.set-event-flagged"), {{QStringLiteral("eventId"), v}, {QStringLiteral("flagged"), flagged}}); }
void SecurityCoreManager::neutralizeEvent(const QString &v) { enqueue(QStringLiteral("security.neutralize-event"), {{QStringLiteral("eventId"), v}}); }
void SecurityCoreManager::setSshEnabled(bool v) { enqueue(QStringLiteral("security.set-ssh-enabled"), {{QStringLiteral("enabled"), v}}); }
void SecurityCoreManager::setTailscaleEnabled(bool v) { enqueue(QStringLiteral("security.set-tailscale-enabled"), {{QStringLiteral("enabled"), v}}); }
void SecurityCoreManager::setVaultComboMode(const QString &v) { enqueue(QStringLiteral("security.set-vault-combo-mode"), {{QStringLiteral("mode"), v}}); }
void SecurityCoreManager::setVaultCombo(const QString &v) { enqueue(QStringLiteral("security.set-vault-combo"), {{QStringLiteral("combo"), v}}); }
void SecurityCoreManager::verifyVaultCombo(const QString &v)
{
    const QString user = m_authManager ? m_authManager->activeUsername().trimmed() : QString();
    enqueue(QStringLiteral("security.unlock-vault-controller"),
            {{QStringLiteral("combo"), v}, {QStringLiteral("username"), user}});
}
void SecurityCoreManager::previewHardening(const QString &v) { enqueue(QStringLiteral("security.preview-hardening"), {{QStringLiteral("profile"), v}}); }
void SecurityCoreManager::toggleHardeningAction(const QString &id) { for (QVariant &v : m_hardeningProfiles) { QVariantMap m=v.toMap(); if (m.value(QStringLiteral("id")).toString()==id) { m[QStringLiteral("selected")]=!m.value(QStringLiteral("selected")).toBool(); v=m; } } emit stateChanged(); }
void SecurityCoreManager::selectAllHardening(bool selected) { for (QVariant &v : m_hardeningProfiles) { QVariantMap m=v.toMap(); m[QStringLiteral("selected")]=selected; v=m; } emit stateChanged(); }
void SecurityCoreManager::applyHardening(const QString &id) { QString profile=id; if (profile==QStringLiteral("selected")) for (const QVariant &v:m_hardeningProfiles) if (v.toMap().value(QStringLiteral("selected")).toBool()) { profile=v.toMap().value(QStringLiteral("id")).toString(); break; } if (profile==QStringLiteral("selected")) profile=QStringLiteral("balanced"); enqueue(QStringLiteral("security.apply-hardening"), {{QStringLiteral("profile"), profile}}); }
void SecurityCoreManager::rollbackHardening() { enqueue(QStringLiteral("security.rollback-hardening")); }
bool SecurityCoreManager::blockSource(const QString &v,int m) { return enqueue(QStringLiteral("security.block-source"),{{QStringLiteral("address"),v},{QStringLiteral("durationMinutes"),m}}); }
bool SecurityCoreManager::unblockSource(const QString &v) { return enqueue(QStringLiteral("security.unblock-source"),{{QStringLiteral("address"),v}}); }
bool SecurityCoreManager::trustPeripheral(const QString &v) { return enqueue(QStringLiteral("security.trust-peripheral"),{{QStringLiteral("deviceId"),v}}); }
bool SecurityCoreManager::allowPeripheralOnce(const QString &v) { return enqueue(QStringLiteral("security.allow-peripheral-once"),{{QStringLiteral("deviceId"),v}}); }
bool SecurityCoreManager::blockPeripheral(const QString &v) { return enqueue(QStringLiteral("security.block-peripheral"),{{QStringLiteral("deviceId"),v}}); }
bool SecurityCoreManager::unlockVault(const QString &v) { return enqueue(QStringLiteral("security.unlock-vault"),{{QStringLiteral("password"),v}}); }
bool SecurityCoreManager::unlockVaultWithLoginCombo(const QString &combo)
{
    if (!m_authManager) {
        emit operationFinished(false, QStringLiteral("Controller authentication is unavailable"));
        return false;
    }
    const QString user = m_authManager->activeUsername().trimmed();
    if (user.isEmpty() || !m_authManager->verifyLoginCombo(user, combo)) {
        emit operationFinished(false, QStringLiteral("Controller combo rejected"));
        return false;
    }
    return enqueue(QStringLiteral("security.unlock-vault-controller"),
                   {{QStringLiteral("combo"), combo},
                    {QStringLiteral("username"), user}});
}
bool SecurityCoreManager::saveVaultEntry(const QString &i,const QString &n,const QString &u,const QString &p) { return enqueue(QStringLiteral("security.save-vault-entry"),{{QStringLiteral("entryId"),i},{QStringLiteral("name"),n},{QStringLiteral("username"),u},{QStringLiteral("password"),p}}); }
bool SecurityCoreManager::revealVaultEntry(const QString &v) { return enqueue(QStringLiteral("security.reveal-vault-entry"),{{QStringLiteral("entryId"),v}}); }
bool SecurityCoreManager::deleteVaultEntry(const QString &v) { return enqueue(QStringLiteral("security.delete-vault-entry"),{{QStringLiteral("entryId"),v}}); }
void SecurityCoreManager::clearRevealedVaultSecret() { if (!m_revealedVaultSecret.isEmpty()) { m_revealedVaultSecret.clear(); emit stateChanged(); } }
void SecurityCoreManager::lockVault() { enqueue(QStringLiteral("security.lock-vault")); clearRevealedVaultSecret(); }
void SecurityCoreManager::generateRecoveryCode() { enqueue(QStringLiteral("security.enroll-recovery-code")); }
bool SecurityCoreManager::confirmGeneratedRecoveryCode() { m_generatedRecoveryCode.clear(); emit stateChanged(); return true; }
bool SecurityCoreManager::deferRecoverySetup() { emit operationFinished(false, QStringLiteral("Recovery setup cannot be deferred by the unified Security Core")); return false; }
bool SecurityCoreManager::enrollUsbRecovery(const QString &v) { return enqueue(QStringLiteral("security.enroll-usb-recovery"),{{QStringLiteral("device"),v}}); }
bool SecurityCoreManager::verifyUsbRecovery() { return enqueue(QStringLiteral("security.verify-usb-recovery")); }
bool SecurityCoreManager::verifyRecoveryCode(const QString &v) { return enqueue(QStringLiteral("security.verify-recovery-code"),{{QStringLiteral("code"),v}}); }
void SecurityCoreManager::requestSnapshot() { enqueue(QStringLiteral("security.request-snapshot")); }
void SecurityCoreManager::scanDownloads() { enqueue(QStringLiteral("security.scan-downloads")); }
void SecurityCoreManager::scanNeutronOS() { enqueue(QStringLiteral("security.scan-neutronos")); }
bool SecurityCoreManager::cancelMalwareScan() { return enqueue(QStringLiteral("security.cancel-scan")); }
bool SecurityCoreManager::quarantineFinding(const QString &v) { return enqueue(QStringLiteral("security.quarantine-finding"),{{QStringLiteral("findingId"),v}}); }
bool SecurityCoreManager::quarantineAppPackage(const QString &v) { return enqueue(QStringLiteral("security.quarantine-app-package"),{{QStringLiteral("path"),v}}); }
bool SecurityCoreManager::restoreQuarantinedApp(const QString &v) { return enqueue(QStringLiteral("security.restore-quarantined-app"),{{QStringLiteral("itemId"),v}}); }
bool SecurityCoreManager::deleteQuarantinedApp(const QString &v) { return enqueue(QStringLiteral("security.delete-quarantined-app"),{{QStringLiteral("itemId"),v}}); }
bool SecurityCoreManager::runQuarantinedApp(const QString &v,const QString &entrypoint,bool network) { return enqueue(QStringLiteral("security.run-quarantined-app"),{{QStringLiteral("itemId"),v},{QStringLiteral("entrypoint"),entrypoint},{QStringLiteral("network"),network}}); }
void SecurityCoreManager::refreshQuarantinedApps() { enqueue(QStringLiteral("security.list-quarantined-apps")); }
void SecurityCoreManager::verifyIntegrity() { enqueue(QStringLiteral("security.verify-integrity")); }
void SecurityCoreManager::createIntegrityBaseline() { enqueue(QStringLiteral("security.create-integrity-baseline")); }

bool SecurityCoreManager::setIntegrityChangeFlagged(
    const QString &changeKey, bool flagged)
{
    const QString key = changeKey.trimmed();

    if (key.isEmpty())
        return false;

    if (flagged)
        m_flaggedIntegrityChangeKeys.insert(key);
    else
        m_flaggedIntegrityChangeKeys.remove(key);

    for (QVariant &value : m_integrityChanges) {
        QVariantMap change = value.toMap();

        if (integrityChangeKey(change) != key)
            continue;

        change[QStringLiteral("flagged")] = flagged;
        value = change;
    }

    emit stateChanged();
    return true;
}
bool SecurityCoreManager::setManualThreatLevel(int v) { return enqueue(QStringLiteral("security.set-manual-defcon"),{{QStringLiteral("level"),v}}); }
void SecurityCoreManager::deescalateToNormal() { enqueue(QStringLiteral("security.deescalate-normal")); }
