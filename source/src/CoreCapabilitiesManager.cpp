#include "HumanAccountPolicy.h"
#include "CoreCapabilitiesManager.h"
#include "SecurityCoreManager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSet>

namespace {
const QStringList kPermissions = {"Network","Media","Documents","Removable Storage","Microphone","Bluetooth","Local Network","System Telemetry","Notifications","Background Execution","Privileged Operations"};
const QStringList kProtectedUnits = {"neutronos.service","neutron-securityd.service","neutron-security-watchdog.service","ssh.service","sshd.service","NetworkManager.service","bluetooth.service","tailscaled.service"};
QString normalizedAddress(const QString &value) {
    const QString address=value.trimmed().toUpper();
    return QRegularExpression("^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$").match(address).hasMatch()?address:QString();
}
}

CoreCapabilitiesManager::CoreCapabilitiesManager(const QString &root, SecurityCoreManager *security, QObject *parent)
    : QObject(parent), m_root(QDir(root).absolutePath()), m_security(security)
{
    loadPreferences(); refresh();
}

QString CoreCapabilitiesManager::preferencesPath() const { return QDir(m_root).filePath("state/core-capabilities/preferences.json"); }
QString CoreCapabilitiesManager::permissionsPath() const { return QDir(m_root).filePath("state/core-capabilities/app-permissions.json"); }
bool CoreCapabilitiesManager::allowed(const QString &v,const QStringList &values){return values.contains(v.trimmed().toLower());}

QString CoreCapabilitiesManager::output(const QString &program,const QStringList &arguments,int timeout)
{
    const QString executable=QStandardPaths::findExecutable(program); if(executable.isEmpty())return {};
    QProcess process;process.start(executable,arguments);if(!process.waitForStarted(1000))return {};
    if(!process.waitForFinished(timeout)){process.kill();process.waitForFinished(500);}
    return QString::fromUtf8(process.readAllStandardOutput()+process.readAllStandardError()).trimmed();
}

QVariantMap CoreCapabilitiesManager::result(const QString &name,const QString &status,const QString &summary,const QString &evidence,const QString &suggestion)
{return {{"name",name},{"status",status},{"summary",summary},{"evidence",evidence},{"suggestedAction",suggestion}};}

void CoreCapabilitiesManager::loadPreferences()
{
    QFile f(preferencesPath());if(!f.open(QIODevice::ReadOnly))return;const auto o=QJsonDocument::fromJson(f.readAll()).object();
    m_uiScale=o.value("uiScale").toString(m_uiScale);m_dndMode=o.value("dndMode").toString(m_dndMode);
    m_adaptiveDashboard=o.value("adaptiveDashboard").toString(m_adaptiveDashboard);
    m_activeSecurityProfile=o.value("securityProfile").toString(m_activeSecurityProfile);
}
bool CoreCapabilitiesManager::savePreferences() const
{
    QDir().mkpath(QFileInfo(preferencesPath()).absolutePath());QSaveFile f(preferencesPath());if(!f.open(QIODevice::WriteOnly))return false;
    const QJsonObject o{{"schemaVersion",1},{"uiScale",m_uiScale},{"dndMode",m_dndMode},{"adaptiveDashboard",m_adaptiveDashboard},{"securityProfile",m_activeSecurityProfile}};
    const QByteArray b=QJsonDocument(o).toJson(QJsonDocument::Indented);return f.write(b)==b.size()&&f.commit();
}

void CoreCapabilitiesManager::loadRelease(){QFile f(QDir(m_root).filePath("config/version.json"));m_releaseInfo=f.open(QIODevice::ReadOnly)?QJsonDocument::fromJson(f.readAll()).object().toVariantMap():QVariantMap{{"version","Unknown"}};}

void CoreCapabilitiesManager::loadPermissions()
{
    QVariantMap persisted;
    QFile p(permissionsPath());
    if (p.open(QIODevice::ReadOnly))
        persisted = QJsonDocument::fromJson(p.readAll()).object().toVariantMap();

    QHash<QString, QSet<QString>> declaredByApp;
    QHash<QString, QString> displayNames;
    QSet<QString> appIds;
    const QDir sourceApps(QDir(m_root).filePath(QStringLiteral("qml/apps")));
    for (const QString &id : sourceApps.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        appIds.insert(id);
        displayNames.insert(id, id);
    }

    const QString stateRoot = HumanHome::appStateRoot();
    QFile installed(QDir(stateRoot).filePath(QStringLiteral("apps/installed.json")));
    if (installed.open(QIODevice::ReadOnly)) {
        const QJsonObject packages = QJsonDocument::fromJson(installed.readAll())
                                         .object().value(QStringLiteral("packages")).toObject();
        for (auto it = packages.constBegin(); it != packages.constEnd(); ++it) {
            const QString id = it.key().trimmed().toLower();
            const QJsonObject package = it.value().toObject();
            if (id.isEmpty()) continue;
            appIds.insert(id);
            displayNames.insert(id, package.value(QStringLiteral("name")).toString(id));
            QSet<QString> declared;
            for (const QJsonValue &entry : package.value(QStringLiteral("permissions")).toArray())
                declared.insert(entry.toString().trimmed().toLower());
            declaredByApp.insert(id, declared);
        }
    }

    auto declaredFor = [](const QSet<QString> &declared, const QString &permission) {
        if (permission == QStringLiteral("Network")) return declared.contains(QStringLiteral("network"));
        if (permission == QStringLiteral("Documents")) return declared.contains(QStringLiteral("filesystem")) ||
            declared.contains(QStringLiteral("documents")) || declared.contains(QStringLiteral("file-management"));
        if (permission == QStringLiteral("Removable Storage")) return declared.contains(QStringLiteral("storage")) ||
            declared.contains(QStringLiteral("removable-storage")) || declared.contains(QStringLiteral("removable-media"));
        if (permission == QStringLiteral("Microphone")) return declared.contains(QStringLiteral("microphone"));
        if (permission == QStringLiteral("Bluetooth")) return declared.contains(QStringLiteral("bluetooth"));
        if (permission == QStringLiteral("Local Network")) return declared.contains(QStringLiteral("remote-service-management")) ||
            declared.contains(QStringLiteral("local-network"));
        if (permission == QStringLiteral("System Telemetry")) return declared.contains(QStringLiteral("system-telemetry")) ||
            declared.contains(QStringLiteral("package-discovery")) || declared.contains(QStringLiteral("security-audit"));
        if (permission == QStringLiteral("Notifications")) return declared.contains(QStringLiteral("notifications"));
        if (permission == QStringLiteral("Background Execution")) return declared.contains(QStringLiteral("background-execution"));
        if (permission == QStringLiteral("Privileged Operations")) return declared.contains(QStringLiteral("privileged-operations"));
        if (permission == QStringLiteral("Media")) return declared.contains(QStringLiteral("media"));
        return false;
    };

    m_appPermissions.clear();
    QStringList ordered = appIds.values();
    ordered.sort(Qt::CaseInsensitive);
    for (const QString &id : ordered) {
        QVariantList permissions;
        const QVariantMap states = persisted.value(id).toMap();
        const QSet<QString> declared = declaredByApp.value(id);
        for (const QString &name : kPermissions) {
            QString defaultState = declaredFor(declared, name)
                ? QStringLiteral("Allowed") : QStringLiteral("Denied");
            QString state = states.value(name, defaultState).toString();
            if (name == QStringLiteral("Privileged Operations") && state == QStringLiteral("Denied"))
                state = QStringLiteral("Denied • no approved scopes");
            permissions.append(QVariantMap{{"name",name},{"state",state},
                {"reason", declaredFor(declared, name) ? "Signed package declaration" : "Declared capability policy"},
                {"lastUse","Unknown"},{"restartRequired",name=="Network"||name=="Background Execution"}});
        }
        m_appPermissions.append(QVariantMap{{"appId",id},{"name",displayNames.value(id,id)},{"permissions",permissions}});
    }
}

void CoreCapabilitiesManager::loadBluetooth()
{
    m_bluetoothDevices.clear();const QString devices=output("bluetoothctl",{"devices"});
    for(const QString &line:devices.split('\n',Qt::SkipEmptyParts)){auto match=QRegularExpression("^Device\\s+([0-9A-Fa-f:]{17})\\s+(.+)$").match(line);if(!match.hasMatch())continue;
        const QString a=match.captured(1),info=output("bluetoothctl",{"info",a});
        auto has=[&](const QString &key){return info.contains(key+": yes",Qt::CaseInsensitive);};
        auto field=[&](const QString &key){auto m=QRegularExpression("^\\s*"+QRegularExpression::escape(key)+":\\s*(.+)$",QRegularExpression::MultilineOption).match(info);return m.hasMatch()?m.captured(1).trimmed():QString("Unavailable");};
        m_bluetoothDevices.append(QVariantMap{{"address",a},{"name",match.captured(2)},{"connected",has("Connected")},{"paired",has("Paired")},{"trusted",has("Trusted")},{"battery",field("Battery Percentage")},{"signal",field("RSSI")},{"type",field("Icon")}});}
}

void CoreCapabilitiesManager::loadAudio()
{
    m_audioOutputs.clear();const QString text=output("wpctl",{"status"},5000);bool sinks=false;
    for(QString line:text.split('\n')){if(line.contains("Sinks:")){sinks=true;continue;}if(sinks&&line.contains("Sources:"))break;if(!sinks)continue;
        auto m=QRegularExpression("([*]?)\\s*([0-9]+)\\.\\s+(.+?)\\s+\\[").match(line);if(m.hasMatch())m_audioOutputs.append(QVariantMap{{"id",m.captured(2)},{"name",m.captured(3).trimmed()},{"default",!m.captured(1).isEmpty()},{"available",true}});}
    if(m_audioOutputs.isEmpty())m_audioOutputs.append(QVariantMap{{"id","unknown"},{"name","Unavailable"},{"default",false},{"available",false}});
}

void CoreCapabilitiesManager::loadDisplay()
{
    m_displayModes.clear();QDir drm("/sys/class/drm");for(const QString &entry:drm.entryList(QStringList{"card*-*"},QDir::Dirs|QDir::NoDotAndDotDot)){
        QFile status(drm.filePath(entry+"/status"));if(!status.open(QIODevice::ReadOnly)||status.readAll().trimmed()!="connected")continue;
        QFile modes(drm.filePath(entry+"/modes"));if(modes.open(QIODevice::ReadOnly))for(const QString &mode:QString::fromUtf8(modes.readAll()).split('\n',Qt::SkipEmptyParts))m_displayModes.append(QVariantMap{{"connector",entry},{"mode",mode},{"refresh","Unknown"},{"safe",mode=="1920x1080"}});}
    if(m_displayModes.isEmpty())m_displayModes.append(QVariantMap{{"connector","Unavailable"},{"mode","Unavailable"},{"refresh","Unavailable"},{"safe",false}});
}

void CoreCapabilitiesManager::loadServices()
{
    m_services.clear();

    const QStringList supportedKinds = {
        QStringLiteral("service"),
        QStringLiteral("timer"),
        QStringLiteral("socket"),
        QStringLiteral("path"),
        QStringLiteral("target")
    };

    auto unitKind = [&supportedKinds](const QString &unit) -> QString {
        const int dot = unit.lastIndexOf(QLatin1Char('.'));
        if (dot < 0)
            return QString();
        const QString kind = unit.mid(dot + 1).trimmed().toLower();
        return supportedKinds.contains(kind) ? kind : QString();
    };

    auto protectedUnit = [](const QString &unit) -> bool {
        return kProtectedUnits.contains(unit) ||
               unit.startsWith(QStringLiteral("neutronos-")) ||
               unit.startsWith(QStringLiteral("neutron-"));
    };

    // Build one runtime-state map from systemctl instead of spawning a
    // process for every individual unit. Settings can therefore enumerate the
    // complete local systemd inventory without turning refresh into a small
    // benchmark of process creation.
    QHash<QString, QVariantMap> runtimeByUnit;
    const QString loadedUnits = output(
        QStringLiteral("systemctl"),
        {QStringLiteral("list-units"), QStringLiteral("--all"),
         QStringLiteral("--no-legend"), QStringLiteral("--no-pager"),
         QStringLiteral("--plain")},
        6000);

    for (QString line : loadedUnits.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        line = line.trimmed();
        if (line.startsWith(QChar(0x25CF))) // systemctl failure bullet
            line = line.mid(1).trimmed();
        const QStringList fields = line.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (fields.size() < 4)
            continue;

        const QString unit = fields.at(0);
        if (unitKind(unit).isEmpty())
            continue;

        const QString active = fields.value(2, QStringLiteral("unknown"));
        const QString sub = fields.value(3, QStringLiteral("unknown"));
        QString description;
        if (fields.size() > 4)
            description = fields.mid(4).join(QLatin1Char(' '));

        runtimeByUnit.insert(unit, QVariantMap{
            {QStringLiteral("active"), active},
            {QStringLiteral("sub"), sub},
            {QStringLiteral("description"), description}
        });
    }

    QSet<QString> seenUnits;
    const QString unitFiles = output(
        QStringLiteral("systemctl"),
        {QStringLiteral("list-unit-files"), QStringLiteral("--no-legend"),
         QStringLiteral("--no-pager"), QStringLiteral("--plain")},
        6000);

    for (const QString &rawLine : unitFiles.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList fields = rawLine.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (fields.size() < 2)
            continue;

        const QString unit = fields.at(0).trimmed();
        const QString kind = unitKind(unit);
        if (kind.isEmpty())
            continue;

        const QString startup = fields.at(1).trimmed();
        const QVariantMap runtime = runtimeByUnit.value(unit);
        const QString active = runtime.value(QStringLiteral("active"), QStringLiteral("inactive")).toString();
        const QString sub = runtime.value(QStringLiteral("sub"), QStringLiteral("dead")).toString();
        const QString description = runtime.value(QStringLiteral("description")).toString().trimmed();
        const QString runtimeState = sub.isEmpty() || sub == active
            ? active
            : active + QStringLiteral(" • ") + sub;

        m_services.append(QVariantMap{
            {QStringLiteral("name"), description.isEmpty() ? unit : description},
            {QStringLiteral("unit"), unit},
            {QStringLiteral("path"), QString()},
            {QStringLiteral("kind"), kind},
            {QStringLiteral("state"), runtimeState.isEmpty() ? QStringLiteral("unavailable") : runtimeState},
            {QStringLiteral("startup"), startup.isEmpty() ? QStringLiteral("unavailable") : startup},
            {QStringLiteral("protected"), protectedUnit(unit)},
            {QStringLiteral("description"), description},
            {QStringLiteral("source"), QStringLiteral("systemd")},
            {QStringLiteral("lastTransition"), QStringLiteral("Unknown")}
        });
        seenUnits.insert(unit);
    }

    // Include loaded/transient units which do not have a normal unit-file
    // entry, so the Services page reflects what is actually running as well
    // as what can start at boot.
    for (auto it = runtimeByUnit.constBegin(); it != runtimeByUnit.constEnd(); ++it) {
        const QString unit = it.key();
        if (seenUnits.contains(unit))
            continue;
        const QString kind = unitKind(unit);
        if (kind.isEmpty())
            continue;
        const QVariantMap runtime = it.value();
        const QString active = runtime.value(QStringLiteral("active"), QStringLiteral("unknown")).toString();
        const QString sub = runtime.value(QStringLiteral("sub"), QStringLiteral("unknown")).toString();
        const QString description = runtime.value(QStringLiteral("description")).toString().trimmed();
        const QString runtimeState = sub.isEmpty() || sub == active
            ? active
            : active + QStringLiteral(" • ") + sub;

        m_services.append(QVariantMap{
            {QStringLiteral("name"), description.isEmpty() ? unit : description},
            {QStringLiteral("unit"), unit},
            {QStringLiteral("path"), QString()},
            {QStringLiteral("kind"), kind},
            {QStringLiteral("state"), runtimeState},
            {QStringLiteral("startup"), QStringLiteral("transient")},
            {QStringLiteral("protected"), protectedUnit(unit)},
            {QStringLiteral("description"), description},
            {QStringLiteral("source"), QStringLiteral("systemd runtime")},
            {QStringLiteral("lastTransition"), QStringLiteral("Unknown")}
        });
    }

    // NeutronOS also owns helpers which are intentionally on-demand rather
    // than systemd units. Surface those alongside startup services so the
    // Settings inventory represents the complete OS-owned support layer.
    struct HelperLocation {
        QString path;
        bool neutronNamesOnly;
    };
    const QList<HelperLocation> helperLocations = {
        {QStringLiteral("/usr/local/lib/neutronos"), false},
        {QStringLiteral("/usr/local/sbin"), true},
        {QStringLiteral("/usr/local/bin"), true}
    };
    QSet<QString> seenHelperPaths;

    for (const HelperLocation &location : helperLocations) {
        const QDir directory(location.path);
        if (!directory.exists())
            continue;

        const QFileInfoList entries = directory.entryInfoList(
            QDir::Files | QDir::NoDotAndDotDot,
            QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo &entry : entries) {
            const QString name = entry.fileName();
            if (location.neutronNamesOnly &&
                !name.startsWith(QStringLiteral("neutron"), Qt::CaseInsensitive))
                continue;

            const QString path = entry.absoluteFilePath();
            if (seenHelperPaths.contains(path))
                continue;
            seenHelperPaths.insert(path);

            m_services.append(QVariantMap{
                {QStringLiteral("name"), name},
                {QStringLiteral("unit"), QString()},
                {QStringLiteral("path"), path},
                {QStringLiteral("kind"), QStringLiteral("helper")},
                {QStringLiteral("state"), entry.isExecutable() ? QStringLiteral("available") : QStringLiteral("installed")},
                {QStringLiteral("startup"), QStringLiteral("on demand")},
                {QStringLiteral("protected"), true},
                {QStringLiteral("description"), QStringLiteral("NeutronOS-owned local helper")},
                {QStringLiteral("source"), location.path},
                {QStringLiteral("lastTransition"), QStringLiteral("Not applicable")}
            });
        }
    }
}

void CoreCapabilitiesManager::loadHelp()
{
    QFile f(QDir(m_root).filePath("config/help-center.json"));m_helpSections.clear();if(f.open(QIODevice::ReadOnly))for(const auto &v:QJsonDocument::fromJson(f.readAll()).array())m_helpSections.append(v.toObject().toVariantMap());
}

void CoreCapabilitiesManager::loadSecurity()
{
    m_securityProfiles={QVariantMap{{"name","NORMAL"},{"defcon",5},{"impact","Balanced local protection"}},QVariantMap{{"name","TRAVEL"},{"defcon",4},{"impact","Untrusted-network hardening"}},QVariantMap{{"name","OFFLINE"},{"defcon",4},{"impact","Network access restricted"}},QVariantMap{{"name","RESTRICTED"},{"defcon",3},{"impact","App and network access constrained"}},QVariantMap{{"name","LOCKDOWN"},{"defcon",2},{"impact","Only essential services"}},QVariantMap{{"name","MAXIMUM"},{"defcon",1},{"impact","Existing DEFCON double-arm policy"}}};
    m_securityTimeline.clear();if(!m_security)return;for(const QVariant &v:m_security->events()){const QVariantMap e=v.toMap();m_securityTimeline.append(QVariantMap{{"timestamp",e.value("timestamp","Unknown")},{"category",e.value("category","System")},{"severity",e.value("severity",1)},{"title",e.value("title","Security event")},{"evidence",e}});}
}

void CoreCapabilitiesManager::refresh(){loadRelease();loadPermissions();loadBluetooth();loadAudio();loadDisplay();loadServices();loadHelp();loadSecurity();runNetworkDiagnostics();m_lastMessage="Core capabilities refreshed from authoritative local sources.";emit changed();}
bool CoreCapabilitiesManager::setUiScale(const QString &v){const QString n=v.trimmed().toLower();if(!allowed(n,{"automatic","small","normal","large","extra large"}))return false;m_uiScale=n;if(!savePreferences())return false;emit preferencesChanged();return true;}
bool CoreCapabilitiesManager::setDndMode(const QString &v){const QString n=v.trimmed().toLower();if(!allowed(n,{"off","on","schedule"}))return false;m_dndMode=n;if(!savePreferences())return false;emit preferencesChanged();return true;}
bool CoreCapabilitiesManager::setAdaptiveDashboard(const QString &v){const QString n=v.trimmed().toLower();if(!allowed(n,{"off","subtle","full"}))return false;m_adaptiveDashboard=n;if(!savePreferences())return false;emit preferencesChanged();return true;}

bool CoreCapabilitiesManager::setAppPermission(const QString &appId,const QString &permission,const QString &state)
{
    if(appId.contains('/')||!kPermissions.contains(permission)||!QStringList{"Allowed","Denied","Ask / Conditional"}.contains(state)||permission=="Privileged Operations") {m_lastMessage="Permission elevation denied by policy.";emit changed();return false;}
    QVariantMap all;QFile in(permissionsPath());if(in.open(QIODevice::ReadOnly))all=QJsonDocument::fromJson(in.readAll()).object().toVariantMap();QVariantMap app=all.value(appId).toMap();app.insert(permission,state);all.insert(appId,app);
    QDir().mkpath(QFileInfo(permissionsPath()).absolutePath());QSaveFile out(permissionsPath());if(!out.open(QIODevice::WriteOnly))return false;const QByteArray b=QJsonDocument(QJsonObject::fromVariantMap(all)).toJson(QJsonDocument::Indented);if(out.write(b)!=b.size()||!out.commit())return false;loadPermissions();emit changed();return true;
}

bool CoreCapabilitiesManager::applySecurityProfile(const QString &profile,bool confirmed)
{
    const QString p=profile.trimmed().toUpper();QVariantMap selected;for(const QVariant &v:m_securityProfiles)if(v.toMap().value("name")==p)selected=v.toMap();if(selected.isEmpty()||!m_security)return false;
    if((p=="RESTRICTED"||p=="LOCKDOWN"||p=="MAXIMUM")&&!confirmed){m_lastMessage="Confirmation required for restrictive profile.";emit changed();return false;}
    if(p=="MAXIMUM"){m_lastMessage="MAXIMUM must be armed through the existing DEFCON double-arm flow.";emit changed();return false;}
    m_security->setManualThreatLevel(selected.value("defcon").toInt());m_activeSecurityProfile=p;savePreferences();emit preferencesChanged();return true;
}

bool CoreCapabilitiesManager::requestServiceAction(const QString &unit,const QString &action)
{
    if(kProtectedUnits.contains(unit)||!allowed(action,{"start","stop","restart","enable","disable"})||!QRegularExpression("^[a-zA-Z0-9@_.-]+\\.service$").match(unit).hasMatch()){m_lastMessage="Service action denied by protected-service policy.";emit changed();return false;}
    // Mutating systemd is privileged.  This manager deliberately remains a
    // presentation/model layer until the secure IPC broker grants a concrete
    // service scope; never let QML become the authorization boundary.
    m_lastMessage="Service action requires an approved secure-IPC operation scope.";
    emit changed();
    return false;
}

bool CoreCapabilitiesManager::requestBluetoothAction(const QString &address,const QString &action)
{const QString a=normalizedAddress(address);if(a.isEmpty()||!allowed(action,{"pair","connect","disconnect","remove","trust","untrust"}))return false;const int code=QProcess::execute("bluetoothctl",{action,a});loadBluetooth();emit changed();return code==0;}
bool CoreCapabilitiesManager::setAudioVolume(int percent){if(percent<0||percent>100)return false;return QProcess::execute("wpctl",{"set-volume","@DEFAULT_AUDIO_SINK@",QString::number(percent)+"%"})==0;}
bool CoreCapabilitiesManager::setAudioMute(bool muted){return QProcess::execute("wpctl",{"set-mute","@DEFAULT_AUDIO_SINK@",muted?"1":"0"})==0;}
bool CoreCapabilitiesManager::testAudio(const QString &channel){const QString value=channel.trimmed().toLower();if(!allowed(value,{"left","right","stereo"}))return false;QStringList args{"-t","sine","-f","440","-l","1"};if(value=="left")args<<"-s"<<"1";else if(value=="right")args<<"-s"<<"2";return QProcess::execute("speaker-test",args)==0;}
bool CoreCapabilitiesManager::requestDisplayMode(const QString &mode){bool exists=false;for(const QVariant &v:m_displayModes)exists=exists||v.toMap().value("mode")==mode;if(!exists)return false;m_lastMessage="Display change prepared; live HDMI changes are disabled during development.";emit displayConfirmationRequired(mode,15);emit changed();return true;}

void CoreCapabilitiesManager::runNetworkDiagnostics()
{
    m_networkDiagnostics.clear();const QString links=output("ip",{"-brief","link"});const QString addresses=output("ip",{"-brief","address"});const QString routes=output("ip",{"route"});const QString resolver=output("resolvectl",{"status"},5000);const QString tailscale=output("tailscale",{"status"},5000);
    m_networkDiagnostics.append(result("Interface",links.isEmpty()?"WARNING":"PASS",links.isEmpty()?"Unavailable":"Interfaces enumerated",links));
    m_networkDiagnostics.append(result("Physical Link",links.contains(" UP ")?"PASS":"WARNING","Carrier state inspected",links,"Check cable/radio state."));
    m_networkDiagnostics.append(result("DHCP",addresses.contains(QRegularExpression("\\b(?:dhcp|dynamic)\\b"))?"PASS":"WARNING","Address lease state",addresses));
    m_networkDiagnostics.append(result("Gateway",routes.contains("default via")?"PASS":"FAIL","Default gateway",routes,"Check DHCP or static gateway configuration."));
    m_networkDiagnostics.append(result("DNS",resolver.contains("DNS Servers")?"PASS":"WARNING","Resolver configuration",resolver,"Check configured DNS server."));
    m_networkDiagnostics.append(result("Internet","WARNING","Not probed automatically","External traffic is intentionally not generated by the local health pass."));
    m_networkDiagnostics.append(result("Tailscale",tailscale.isEmpty()?"WARNING":"PASS",tailscale.isEmpty()?"Unavailable":"State available",tailscale));
    m_networkDiagnostics.append(result("Local Services","PASS","Local-only checks complete","No service state was changed."));
    m_networkDiagnostics.append(result("Latency","WARNING","Unavailable","No remote target was contacted."));
    m_networkDiagnostics.append(result("Packet Loss","WARNING","Unavailable","No remote target was contacted."));
}

void CoreCapabilitiesManager::search(const QString &query)
{
    const QString q=query.trimmed();m_searchResults.clear();if(q.isEmpty()){emit searchChanged();return;}auto add=[this,&q](const QString &category,const QString &title,const QString &description,const QString &action){if((title+' '+description).contains(q,Qt::CaseInsensitive))m_searchResults.append(QVariantMap{{"category",category},{"title",title},{"description",description},{"action",action}});};
    QDir apps(QDir(m_root).filePath("qml/apps"));for(const QString &id:apps.entryList(QDir::Dirs|QDir::NoDotAndDotDot))add("Apps",id,"Open application","open-app:"+id);
    for(const QVariant &v:m_helpSections){const auto h=v.toMap();add("Help",h.value("title").toString(),h.value("summary").toString(),"help:"+h.value("id").toString());}
    for(const QVariant &v:m_services){const auto s=v.toMap();add("System Actions",s.value("name").toString(),s.value("unit").toString(),"service:"+s.value("unit").toString());}
    add("Settings","Updates","Signed NeutronOS system updates","settings:updates");add("Settings","Bluetooth","Pair and connect devices","settings:bluetooth");add("Settings","Audio","Output, volume and audio test","settings:audio");
    for(const QStorageInfo &s:QStorageInfo::mountedVolumes())
        add("Storage",s.displayName(),s.rootPath(),"storage:"+s.rootPath());
    QFile notifications(QDir(m_root).filePath("state/notifications/notifications.json"));
    if(notifications.open(QIODevice::ReadOnly)) {
        const QJsonDocument document=QJsonDocument::fromJson(notifications.readAll());
        const QJsonArray entries=document.isArray()?document.array():document.object().value("notifications").toArray();
        for(const QJsonValue &value:entries) {
            const QJsonObject item=value.toObject();
            add("Notifications",item.value("title").toString("Unknown"),
                item.value("message").toString("Unavailable"),
                "notification:"+item.value("id").toVariant().toString());
        }
    }
    QFile fileIndex(QDir(m_root).filePath("state/search/file-index.json"));
    if(fileIndex.open(QIODevice::ReadOnly)) {
        const QJsonArray entries=QJsonDocument::fromJson(fileIndex.readAll()).array();
        for(const QJsonValue &value:entries) {
            const QJsonObject item=value.toObject();
            add("Files",item.value("name").toString("Unknown"),
                item.value("path").toString("Unavailable"),
                "file:"+item.value("path").toString());
        }
    }
    emit searchChanged();
}
