#include "HumanAccountPolicy.h"
#include "PackageAppBridgeManager.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSet>

#include <sys/resource.h>
#include <sys/stat.h>

namespace {
constexpr qsizetype kMaximumMessage = 4 * 1024 * 1024;

QJsonObject readObject(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object() : QJsonObject{};
}


QSet<QString> declaredPermissions(const QJsonObject &package)
{
    QSet<QString> result;
    for (const QJsonValue &value : package.value(QStringLiteral("permissions")).toArray()) {
        const QString permission = value.toString().trimmed().toLower();
        if (!permission.isEmpty()) result.insert(permission);
    }
    return result;
}

bool explicitPermissionDenied(const QString &neutronRoot, const QString &appId,
                              const QString &permissionName)
{
    const QJsonObject all = readObject(QDir(neutronRoot).filePath(
        QStringLiteral("state/core-capabilities/app-permissions.json")));
    const QJsonObject app = all.value(appId).toObject();
    if (!app.contains(permissionName)) return false;
    const QString state = app.value(permissionName).toString().trimmed().toLower();
    return state.startsWith(QStringLiteral("denied")) ||
           state.startsWith(QStringLiteral("ask")) ||
           state.startsWith(QStringLiteral("conditional"));
}

bool declaredAndApproved(const QSet<QString> &declared, const QString &neutronRoot,
                         const QString &appId, const QStringList &declarations,
                         const QString &permissionName)
{
    bool hasDeclaration = false;
    for (const QString &name : declarations) {
        if (declared.contains(name)) { hasDeclaration = true; break; }
    }
    return hasDeclaration && !explicitPermissionDenied(neutronRoot, appId, permissionName);
}

void addExistingBind(QStringList &arguments, const QString &flag, const QString &path)
{
    if (QFileInfo::exists(path)) arguments << flag << path << path;
}

QJsonObject builtInRemoteSystemsManifest(const QString &neutronRoot)
{
    const QJsonObject manifest = readObject(QDir(neutronRoot).filePath(
        QStringLiteral("qml/apps/neutronremotesystems/app.json")));
    if (!manifest.value(QStringLiteral("systemApp")).toBool()) return {};
    if (manifest.value(QStringLiteral("id")).toString().trimmed().toLower() !=
        QStringLiteral("neutronremotesystems")) return {};
    if (manifest.value(QStringLiteral("systemHelper")).toString().trimmed() !=
        QStringLiteral("/usr/local/lib/neutronos/remote-systems-bridge.py")) return {};
    return manifest;
}

QString builtInRemoteSystemsHelper(const QString &neutronRoot, const QString &id,
                                   const QString &helperName)
{
    if (id != QStringLiteral("neutronremotesystems") ||
        helperName != QStringLiteral("remote-systems-bridge.py") ||
        builtInRemoteSystemsManifest(neutronRoot).isEmpty()) return {};

    const QString expected = QStringLiteral("/usr/local/lib/neutronos/remote-systems-bridge.py");
    QFileInfo info(expected);
    const QString canonical = info.canonicalFilePath();
    if (canonical != expected || !info.isFile() || !info.isExecutable() || info.ownerId() != 0)
        return {};
    const QFileDevice::Permissions perms = info.permissions();
    if (perms.testFlag(QFileDevice::WriteGroup) || perms.testFlag(QFileDevice::WriteOther))
        return {};
    return canonical;
}
}

PackageAppBridgeManager::PackageAppBridgeManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent), m_root(QDir::cleanPath(neutronRoot))
{
}

PackageAppBridgeManager::~PackageAppBridgeManager()
{
    const QStringList ids = m_bridges.keys();
    for (const QString &id : ids) stop(id);
}

QString PackageAppBridgeManager::validatedHelper(const QString &appId,
                                                  const QString &helperName,
                                                  QString *error) const
{
    static const QRegularExpression idPattern(QStringLiteral("^[a-z0-9][a-z0-9._-]{0,95}$"));
    static const QRegularExpression namePattern(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"));
    const QString id = appId.trimmed().toLower();
    if (!idPattern.match(id).hasMatch() || !namePattern.match(helperName).hasMatch()) {
        if (error) *error = QStringLiteral("Invalid package bridge identity");
        return {};
    }

    const QString relative = QStringLiteral("scripts/apps/%1/%2").arg(id, helperName);
    const QString stateRoot = HumanHome::appStateRoot();
    const QJsonObject registry = readObject(
        QDir(stateRoot).filePath(QStringLiteral("apps/installed.json")));
    const QJsonObject package = registry.value(QStringLiteral("packages")).toObject().value(id).toObject();
    const QJsonArray files = package.value(QStringLiteral("files")).toArray();
    bool owned = false;
    for (const QJsonValue &file : files) {
        if (file.toString() == relative) { owned = true; break; }
    }
    if (!owned) {
        const QString systemHelper = builtInRemoteSystemsHelper(m_root, id, helperName);
        if (!systemHelper.isEmpty()) return systemHelper;
        if (error) *error = QStringLiteral("Helper is neither App Store-owned nor an approved built-in system helper");
        return {};
    }
    const QString payloadRoot = QDir(stateRoot).filePath(QStringLiteral("apps/payload"));
    const QString root = QFileInfo(payloadRoot).canonicalFilePath();
    const QString path = QFileInfo(QDir(payloadRoot).filePath(relative)).canonicalFilePath();
    if (root.isEmpty() || path.isEmpty() || !path.startsWith(root + QLatin1Char('/')) ||
        !QFileInfo(path).isFile()) {
        if (error) *error = QStringLiteral("Installed helper failed path or mode validation");
        return {};
    }

    QFileInfo helperInfo(path);
    if (!helperInfo.isExecutable()) {
        /*
            The registry already proved this exact path belongs to the signed
            installed package, and the canonical-path check above keeps it
            inside the App Store payload. If only the executable bit was lost,
            repair that bit in place instead of dead-ending the application.
            No arbitrary path is ever chmod'd here.
        */
        const QFileDevice::Permissions repairedPermissions =
            QFile::permissions(path) | QFileDevice::ExeOwner;
        if (QFile::setPermissions(path, repairedPermissions))
            helperInfo.refresh();
    }

    if (!helperInfo.isExecutable()) {
        if (error) *error = QStringLiteral("Installed helper failed path or mode validation");
        return {};
    }
    return path;
}

bool PackageAppBridgeManager::start(const QString &appId, const QString &helperName)
{
    const QString id = appId.trimmed().toLower();
    if (m_bridges.contains(id) && m_bridges[id].process &&
        m_bridges[id].process->state() != QProcess::NotRunning) return true;
    QString error;
    const QString helper = validatedHelper(id, helperName, &error);
    if (helper.isEmpty()) {
        m_bridges[id].error = error;
        emit stateChanged(id, false, error);
        return false;
    }

    const QString bwrap = QStandardPaths::findExecutable(QStringLiteral("bwrap"));
    if (bwrap.isEmpty()) {
        error = QStringLiteral("Package helper denied: bubblewrap sandbox is unavailable");
        m_bridges[id].error = error;
        emit stateChanged(id, false, error);
        return false;
    }

    const QString stateRoot = HumanHome::appStateRoot();
    const QJsonObject registry = readObject(
        QDir(stateRoot).filePath(QStringLiteral("apps/installed.json")));
    QJsonObject package = registry.value(QStringLiteral("packages")).toObject().value(id).toObject();
    if (package.isEmpty() && id == QStringLiteral("neutronremotesystems") &&
        helper == QStringLiteral("/usr/local/lib/neutronos/remote-systems-bridge.py")) {
        package = builtInRemoteSystemsManifest(m_root);
    }
    const QSet<QString> declared = declaredPermissions(package);
    const QString payloadRoot = QDir(stateRoot).filePath(QStringLiteral("apps/payload"));
    const QString appState = QDir(stateRoot).filePath(QStringLiteral("apps/%1").arg(id));
    QDir().mkpath(appState);

    const bool networkAllowed = declaredAndApproved(
        declared, m_root, id, {QStringLiteral("network")}, QStringLiteral("Network"));
    const bool documentsAllowed = declaredAndApproved(
        declared, m_root, id,
        {QStringLiteral("filesystem"), QStringLiteral("documents"), QStringLiteral("file-management")},
        QStringLiteral("Documents"));
    const bool removableAllowed = declaredAndApproved(
        declared, m_root, id,
        {QStringLiteral("storage"), QStringLiteral("removable-storage"), QStringLiteral("removable-media")},
        QStringLiteral("Removable Storage"));
    const bool remoteAdminAllowed = declaredAndApproved(
        declared, m_root, id, {QStringLiteral("remote-service-management")},
        QStringLiteral("Local Network"));
    const bool hasRemoteProvider = !package.value(QStringLiteral("remoteCapabilities")).toArray().isEmpty();

    QStringList sandbox{
        QStringLiteral("--die-with-parent"), QStringLiteral("--new-session"),
        QStringLiteral("--unshare-all"), QStringLiteral("--cap-drop"), QStringLiteral("ALL"),
        QStringLiteral("--clearenv"),
        QStringLiteral("--ro-bind"), QStringLiteral("/usr"), QStringLiteral("/usr"),
        QStringLiteral("--proc"), QStringLiteral("/proc"),
        QStringLiteral("--dev"), QStringLiteral("/dev"),
        QStringLiteral("--tmpfs"), QStringLiteral("/tmp"),
        QStringLiteral("--dir"), QStringLiteral("/var"),
        QStringLiteral("--dir"), QStringLiteral("/var/lib"),
        QStringLiteral("--dir"), QStringLiteral("/var/lib/neutronos"),
        QStringLiteral("--dir"), QStringLiteral("/var/lib/neutronos/app-store"),
        QStringLiteral("--dir"), QStringLiteral("/var/lib/neutronos/apps"),
        QStringLiteral("--ro-bind"), payloadRoot, payloadRoot,
        QStringLiteral("--bind"), appState, appState,
        QStringLiteral("--dir"), QStringLiteral("/run"),
        QStringLiteral("--dir"), QStringLiteral("/run/neutronos"),
        QStringLiteral("--setenv"), QStringLiteral("PATH"), QStringLiteral("/usr/local/bin:/usr/bin:/bin"),
        QStringLiteral("--setenv"), QStringLiteral("HOME"), appState,
        QStringLiteral("--setenv"), QStringLiteral("TMPDIR"), QStringLiteral("/tmp"),
        QStringLiteral("--setenv"), QStringLiteral("LANG"), QStringLiteral("C.UTF-8"),
        QStringLiteral("--setenv"), QStringLiteral("PYTHONUNBUFFERED"), QStringLiteral("1"),
        QStringLiteral("--setenv"), QStringLiteral("NEUTRONOS_APP_ID"), id,
        QStringLiteral("--setenv"), QStringLiteral("NEUTRONOS_STATE_DIR"), stateRoot
    };

    addExistingBind(sandbox, QStringLiteral("--ro-bind"), QStringLiteral("/bin"));
    addExistingBind(sandbox, QStringLiteral("--ro-bind"), QStringLiteral("/lib"));
    addExistingBind(sandbox, QStringLiteral("--ro-bind"), QStringLiteral("/lib64"));

    if (networkAllowed) {
        sandbox << QStringLiteral("--share-net");
        addExistingBind(sandbox, QStringLiteral("--ro-bind"), QStringLiteral("/etc/resolv.conf"));
        addExistingBind(sandbox, QStringLiteral("--ro-bind"), QStringLiteral("/etc/hosts"));
        addExistingBind(sandbox, QStringLiteral("--ro-bind"), QStringLiteral("/etc/nsswitch.conf"));
        addExistingBind(sandbox, QStringLiteral("--ro-bind"), QStringLiteral("/etc/ssl"));
    }
    // Only the approved Tailscale app may inspect the host tailscaled LocalAPI.
    // The CLI needs this UNIX socket to observe externally configured tailnets;
    // --share-net alone does not expose it because --unshare-all hides host /run.
    // Bind exactly the socket, never the daemon's state or the whole host /run.
    if (id == QStringLiteral("tailscale-manager") && networkAllowed &&
        declaredAndApproved(declared, m_root, id,
                            {QStringLiteral("scoped-privileged-operations")},
                            QStringLiteral("Network"))) {
        const QString socket = QStringLiteral("/run/tailscale/tailscaled.sock");
        struct stat socketStat{};
        const QByteArray socketPath = socket.toLocal8Bit();
        if (::lstat(socketPath.constData(), &socketStat) == 0 &&
            S_ISSOCK(socketStat.st_mode)) {
            sandbox << QStringLiteral("--dir") << QStringLiteral("/run/tailscale")
                    << QStringLiteral("--ro-bind") << socket << socket
                    << QStringLiteral("--dir") << QStringLiteral("/var/run")
                    << QStringLiteral("--symlink") << QStringLiteral("/run/tailscale")
                    << QStringLiteral("/var/run/tailscale");
        }
    }
    if (documentsAllowed) {
        addExistingBind(sandbox, QStringLiteral("--bind"), QDir(HumanHome::browsePath()).filePath(QStringLiteral("Documents")));
    }
    if (removableAllowed) {
        addExistingBind(sandbox, QStringLiteral("--bind"), QStringLiteral("/media"));
        addExistingBind(sandbox, QStringLiteral("--bind"), QStringLiteral("/mnt"));
        addExistingBind(sandbox, QStringLiteral("--bind"), QStringLiteral("/run/media"));
    }
    if (remoteAdminAllowed) {
        const QString socket = QStringLiteral("/run/neutronos/remote-service-admin.sock");
        addExistingBind(sandbox, QStringLiteral("--bind"), socket);
        sandbox << QStringLiteral("--setenv") << QStringLiteral("NEUTRONOS_REMOTE_ADMIN_SOCKET") << socket;
    }
    if (hasRemoteProvider) {
        const QString socket = QStringLiteral("/run/neutronos/remote-service-provider.sock");
        addExistingBind(sandbox, QStringLiteral("--bind"), socket);
        sandbox << QStringLiteral("--setenv") << QStringLiteral("NEUTRONOS_REMOTE_PROVIDER_SOCKET") << socket;
    }

    sandbox << QStringLiteral("--chdir") << appState << helper;

    Bridge bridge;
    bridge.process = new QProcess(this);
    bridge.process->setProgram(bwrap);
    bridge.process->setArguments(sandbox);
    QProcessEnvironment environment;
    environment.insert(QStringLiteral("PATH"), QStringLiteral("/usr/bin:/bin"));
    bridge.process->setProcessEnvironment(environment);
    bridge.process->setProcessChannelMode(QProcess::SeparateChannels);
    bridge.process->setChildProcessModifier([]() {
        struct rlimit nofile{256, 256};
        // Do not set RLIMIT_NPROC here: Linux counts ALL threads owned by the
        // real UID, not just this app. A fixed limit of 64 blocks Bubblewrap
        // namespace creation once the NeutronOS desktop/user exceeds it.
        // Keep the Bubblewrap namespace and capability isolation unchanged.
        struct rlimit fsize{128ULL * 1024ULL * 1024ULL, 128ULL * 1024ULL * 1024ULL};
        struct rlimit core{0, 0};
        ::setrlimit(RLIMIT_NOFILE, &nofile);
        ::setrlimit(RLIMIT_FSIZE, &fsize);
        ::setrlimit(RLIMIT_CORE, &core);
    });

    m_bridges.insert(id, bridge);
    QProcess *process = m_bridges[id].process;
    connect(process, &QProcess::readyReadStandardOutput, this, [this, id]() { consume(id); });
    connect(process, &QProcess::readyReadStandardError, this, [this, id]() {
        if (!m_bridges.contains(id)) return;
        QByteArray text = m_bridges[id].process->readAllStandardError().trimmed();
        if (text.size() > 2048) text = text.right(2048);
        if (!text.isEmpty()) m_bridges[id].error = QString::fromUtf8(text);
    });
    connect(process, &QProcess::started, this, [this, id]() { emit stateChanged(id, true, {}); });
    connect(process, &QProcess::errorOccurred, this, [this, id](QProcess::ProcessError) {
        if (!m_bridges.contains(id)) return;
        m_bridges[id].error = m_bridges[id].process->errorString();
        emit stateChanged(id, false, m_bridges[id].error);
    });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [this, id](int code, QProcess::ExitStatus) {
        if (!m_bridges.contains(id)) return;
        if (code != 0 && m_bridges[id].error.isEmpty())
            m_bridges[id].error = QStringLiteral("Package helper exited with code %1").arg(code);
        emit stateChanged(id, false, m_bridges[id].error);
    });
    process->start();
    return process->waitForStarted(2000);
}

bool PackageAppBridgeManager::send(const QString &appId, const QVariantMap &message)
{
    const QString id = appId.trimmed().toLower();
    if (!running(id)) return false;
    QByteArray line = QJsonDocument(QJsonObject::fromVariantMap(message)).toJson(QJsonDocument::Compact);
    if (line.size() > kMaximumMessage) return false;
    line.append('\n');
    return m_bridges[id].process->write(line) == line.size();
}

void PackageAppBridgeManager::consume(const QString &appId)
{
    Bridge &bridge = m_bridges[appId];
    bridge.output += bridge.process->readAllStandardOutput();
    if (bridge.output.size() > kMaximumMessage * 2) {
        bridge.error = QStringLiteral("Package helper exceeded the bounded message buffer");
        bridge.process->kill();
        return;
    }
    while (true) {
        const qsizetype newline = bridge.output.indexOf('\n');
        if (newline < 0) break;
        const QByteArray line = bridge.output.left(newline).trimmed();
        bridge.output.remove(0, newline + 1);
        if (line.isEmpty() || line.size() > kMaximumMessage) continue;
        const QJsonDocument document = QJsonDocument::fromJson(line);
        if (!document.isObject()) continue;
        QVariantMap message = document.object().toVariantMap();
        if (message.value(QStringLiteral("type")).toString() == QStringLiteral("approval") &&
            protectedAction(message.value(QStringLiteral("command")).toString())) {
            send(appId, {{QStringLiteral("action"), QStringLiteral("approval")},
                         {QStringLiteral("requestId"), message.value(QStringLiteral("requestId"))},
                         {QStringLiteral("decision"), QStringLiteral("decline")}});
            message.insert(QStringLiteral("type"), QStringLiteral("policy-denial"));
            message.insert(QStringLiteral("detail"), QStringLiteral("NeutronOS protected-action policy denied this request"));
        }
        emit messageReceived(appId, message);
    }
}

bool PackageAppBridgeManager::protectedAction(const QString &command)
{
    const QString value = command.toLower();
    static const QStringList denied = {
        QStringLiteral("reboot"), QStringLiteral("shutdown"), QStringLiteral("poweroff"),
        QStringLiteral("/boot/firmware"), QStringLiteral("cmdline.txt"), QStringLiteral("config.txt"),
        QStringLiteral("initramfs"), QStringLiteral("eeprom"), QStringLiteral("mkfs"),
        QStringLiteral("wipefs"), QStringLiteral(" fdisk"), QStringLiteral(" parted"),
        QStringLiteral("nmcli"), QStringLiteral("tailscale"), QStringLiteral("iptables"),
        QStringLiteral("nft "), QStringLiteral("ip route"),
        QStringLiteral("systemctl restart neutronos"), QStringLiteral("systemctl stop ssh")
    };
    for (const QString &needle : denied) if (value.contains(needle)) return true;
    return false;
}

void PackageAppBridgeManager::stop(const QString &appId)
{
    const QString id = appId.trimmed().toLower();
    if (!m_bridges.contains(id)) return;
    Bridge bridge = m_bridges.take(id);
    if (bridge.process) {
        if (bridge.process->state() != QProcess::NotRunning) {
            bridge.process->terminate();
            if (!bridge.process->waitForFinished(1000)) bridge.process->kill();
        }
        bridge.process->deleteLater();
    }
    emit stateChanged(id, false, {});
}

void PackageAppBridgeManager::stopAll()
{
    const QStringList ids = m_bridges.keys();
    for (const QString &id : ids)
        stop(id);
}

bool PackageAppBridgeManager::running(const QString &appId) const
{
    const QString id = appId.trimmed().toLower();
    return m_bridges.contains(id) && m_bridges.value(id).process &&
           m_bridges.value(id).process->state() == QProcess::Running;
}

QString PackageAppBridgeManager::lastError(const QString &appId) const
{
    return m_bridges.value(appId.trimmed().toLower()).error;
}
