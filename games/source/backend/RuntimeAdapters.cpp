#include "RuntimeAdapters.h"
#include "GameLibrary.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>
#include <unistd.h>
namespace GeminiGames {
namespace {
QString executable(const QStringList &names){for(const auto &n:names){QString p=QStandardPaths::findExecutable(n);if(!p.isEmpty())return p;}return {};}
QString read(const QString &p){QFile f(p);return f.open(QIODevice::ReadOnly)?QString::fromUtf8(f.read(1024*1024)).trimmed():QString();}
QString programFor(const QVariantList &list,const QString &id){for(const auto &v:list){auto r=v.toMap();if(r.value("id")==id)return r.value("program").toString();}return {};}
}
QVariantMap RuntimeAdapters::capabilities(const QString &id){
    // SIGSTOP is opt-in for an offline native process; it is not an emulator pause API.
    bool native=id=="native";
    bool supported=QStringList{"native","wine","proton","dosbox","scummvm","cemu","dolphin","retroarch","ppsspp","duckstation","pcsx2","rpcs3","ruffle","moonlight"}.contains(id);
    return {{"launch",supported},{"pause",native},{"resume",native},{"gracefulStop",supported},{"forceStop",supported},{"supportsBackground",native},{"supportsDisplayDetach",false},{"supportsControllerInterception",supported},{"supportsSuspend",native},{"supportsResume",native},{"ownsGameProcess",supported}};
}
QVariantList RuntimeAdapters::runtimes(){
    const QList<QPair<QString,QStringList>> specs={{"native",{}},{"wine",{"wine64","wine"}},{"proton",{"proton"}},{"dosbox",{"dosbox","dosbox-x"}},{"scummvm",{"scummvm"}},{"steam",{"steam"}},{"cemu",{"Cemu","cemu"}},{"dolphin",{"dolphin-emu"}},{"retroarch",{"retroarch"}},{"ppsspp",{"PPSSPPSDL","ppsspp"}},{"duckstation",{"duckstation"}},{"pcsx2",{"pcsx2"}},{"rpcs3",{"rpcs3"}},{"ruffle",{"ruffle"}},{"moonlight",{"moonlight"}}};
    QVariantList out;for(const auto &spec:specs){QString p=spec.first=="native"?"native":executable(spec.second);out.append(QVariantMap{{"id",spec.first},{"program",p},{"installed",!p.isEmpty()},{"capabilities",capabilities(spec.first)}});}return out;
}
bool RuntimeAdapters::runtimeAvailable(const QVariantMap &configuration){QString id=configuration.value("runtime").toString(),custom=configuration.value("runtimeProgram").toString();if(!custom.isEmpty()){QString name=QFileInfo(custom).fileName();QStringList names=id=="wine"?QStringList{"wine","wine64"}:id=="proton"?QStringList{"proton"}:id=="dosbox"?QStringList{"dosbox","dosbox-x"}:id=="scummvm"?QStringList{"scummvm"}:QStringList{name};if(!names.contains(name))return false;}return id=="native"||(!custom.isEmpty()?QFileInfo(custom).isFile()&&QFileInfo(custom).isExecutable():!programFor(runtimes(),id).isEmpty());}
bool RuntimeAdapters::validEnvironment(const QVariantMap &environment){const QStringList allowed={"WINEDEBUG","WINEDLLOVERRIDES","DXVK_LOG_LEVEL","DXVK_HUD","VKD3D_CONFIG","PROTON_USE_WINED3D","PROTON_NO_ESYNC","PROTON_NO_FSYNC","MESA_GL_VERSION_OVERRIDE","MESA_GLSL_VERSION_OVERRIDE"};for(auto it=environment.constBegin();it!=environment.constEnd();++it)if(!allowed.contains(it.key())||it.value().metaType().id()!=QMetaType::QString||it.value().toString().size()>4096||it.value().toString().contains(QChar(0)))return false;return environment.size()<=32;}
QVariantMap RuntimeAdapters::hardware(){
    QVariantMap h{{"architecture",QSysInfo::currentCpuArchitecture()},{"logicalCpus",int(sysconf(_SC_NPROCESSORS_ONLN))},{"ramBytes",qlonglong(sysconf(_SC_PHYS_PAGES))*sysconf(_SC_PAGESIZE)},{"cpuFlags",read("/proc/cpuinfo")},{"graphicsVerified",false},{"performanceVerified",false}};
    QVariantList gpus;QDir drm("/sys/class/drm");for(const auto &name:drm.entryList({"card[0-9]","card[0-9][0-9]"},QDir::Dirs)){QString d=drm.filePath(name+"/device/");gpus.append(QVariantMap{{"name",name},{"vendor",read(d+"vendor")},{"device",read(d+"device")},{"busyPercent",read(d+"gpu_busy_percent")},{"clocks",read(d+"pp_dpm_sclk")}});}h["gpus"]=gpus;h["graphicsNote"]="GPU API and driver capability must be validated on the target session.";return h;
}
QVariantList RuntimeAdapters::recommendations(const QVariantMap &game,const QVariantMap &h,const QVariantList &list){
    QString kind=game.value("chosenKind",game.value("kind")).toString();QString runtime,reason;bool experimental=false,blocked=false;
    if(kind=="archive"||game.contains("archiveFormat")){runtime="archive";blocked=true;reason="Archive found. Game format is unverified. User-authorized extraction and a compatible installed runtime are required; the archive cannot launch directly.";}
    else if(kind=="linux"){runtime="native";reason="Native ELF launch; inspect requirements and configure once.";QString a=game.value("architecture").toString();if(a!="amd64"&&a!="i386"){blocked=true;reason="Executable architecture is incompatible with Gemini AMD64.";}if(a=="i386"){experimental=true;reason="32-bit native game requires compatible installed Linux libraries.";}}
    else if(kind=="windows"||kind=="plutonium"){runtime="wine";experimental=true;reason=kind=="plutonium"?"T6 structure found. Select a valid Plutonium launcher; Linux support is unofficial and must be tested.":"Windows PE found. Wine availability alone does not prove game compatibility; configure and test.";}
    else if(kind=="dos"){runtime="dosbox";reason="DOSBox candidate; CPU, memory, sound and per-title configuration require validation.";experimental=true;}
    else if(kind=="scummvm"){runtime="scummvm";reason="ScummVM requires supported game data and a user-selected game ID.";experimental=true;}
    else if(kind=="ubisoft"){runtime="wine";experimental=true;blocked=true;reason="Ubisoft launcher/DRM compatibility is unverified. Recommend configured remote streaming; local execution is not advertised as playable.";}
    else if(kind=="steam"){runtime="steam";blocked=true;reason="Steam manifest recognized. Delegated Steam game lifecycle and Steam Input require a validated session adapter; direct supervision is unavailable.";}
    else if(kind=="wiiu"){runtime="cemu";reason="Cemu candidate for Wii U RPX. Validate GPU API, title and update/DLC configuration first.";if(h.value("ramBytes").toLongLong()<4LL*1024*1024*1024||!h.value("cpuFlags").toString().contains("sse4_1")){blocked=true;reason="Cemu candidate lacks minimum memory/CPU evidence.";}if(!h.value("graphicsVerified").toBool())experimental=true;}
    else if(kind=="wii"||kind=="gamecube"){runtime="dolphin";reason="Dolphin candidate from a verified disc system header; title performance must be tested.";experimental=!h.value("graphicsVerified").toBool();}
    else if(kind=="psp"){runtime="ppsspp";reason="PPSSPP candidate from PSP disc structure.";}
    else if(kind=="ps1"){runtime="duckstation";reason="DuckStation needs an authorized BIOS and user-confirmed disc identity.";experimental=true;}
    else if(kind=="ps2"){runtime="pcsx2";reason="PCSX2 needs an authorized BIOS and validated GPU/CPU and title compatibility.";experimental=true;}
    else if(kind=="ps3"){runtime="rpcs3";reason="RPCS3 requires firmware and per-title compatibility validation.";experimental=true;}
    else if(QStringList{"n64","nes","gameboy","snes","gba","retroarch"}.contains(kind)){runtime="retroarch";reason="RetroArch candidate; choose an installed compatible libretro core.";}
    else if(kind=="flash"){runtime="ruffle";reason="Ruffle candidate; ActionScript feature support varies by title.";experimental=true;}
    else if(kind=="remote"){runtime="moonlight";reason="Moonlight candidate; pairing and an available host/application are required.";}
    else if(kind=="cloud"){runtime="cloud";blocked=true;reason="HTTPS cloud descriptor recognized. Provider authentication/controller/browser session supervision is not yet supported.";}
    else if(kind=="android"){runtime="android";blocked=true;reason="APK identified. No supported Gemini Android execution adapter; choose remote streaming.";}
    else {blocked=true;reason="Identification is ambiguous; choose a likely platform before setup.";}
    if(QStringList{"windows","plutonium","ubisoft"}.contains(kind)&&!QStringList{"amd64","i386"}.contains(game.value("architecture").toString())){blocked=true;reason="Windows executable architecture is incompatible with Gemini AMD64/Wine.";}
    QString p=programFor(list,runtime);bool installed=runtime=="native"||!p.isEmpty();
    if(h.value("architecture").toString()!="x86_64"&&h.value("architecture").toString()!="amd64"){blocked=true;reason="This application requires Gemini x86_64/AMD64.";}
    QVariantMap local{{"id",runtime},{"installed",installed},{"launchable",installed&&!blocked},{"status",blocked?"unsupported":!installed?"runtime missing":experimental?"requires validation":"configuration required"},{"reason",reason},{"experimental",experimental},{"performance","Unmeasured; no frame-rate guarantee"},{"controller","Real evdev gamepad proxy; runtime mapping requires session validation"},{"capabilities",capabilities(runtime)}};
    QVariantList out{local};if(kind=="ubisoft"||kind=="windows"||kind=="plutonium"||kind=="android")out.append(QVariantMap{{"id","moonlight"},{"installed",!programFor(list,"moonlight").isEmpty()},{"launchable",false},{"status","configure a remote-stream descriptor"},{"reason","Use a compatible host with the game legitimately installed; network latency and controller support must be tested."}});return out;
}
LaunchPlan RuntimeAdapters::plan(const QVariantMap &game,const QVariantMap &c,const QString &state){
    LaunchPlan p;p.runtime=c.value("runtime").toString();p.capabilities=capabilities(p.runtime);p.environment=QProcessEnvironment::systemEnvironment();p.workingDirectory=QFileInfo(game.value("path").toString()).absolutePath();
    if(game.value("kind")=="archive"||game.contains("archiveFormat")){p.error="Archive launch denied. Use user-authorized extracted game data with a verified compatible runtime.";return p;}
    if(!game.value("online").toBool()){p.error="Game storage is disconnected or files are unavailable.";return p;}
    if(c.value("signature")!=game.value("signature")||c.value("signature").toString()!=GameLibrary::materialSignature(game.value("path").toString())){p.error="Game files changed; setup must be reviewed again.";return p;}
    QString path=game.value("path").toString();p.program=c.value("runtimeProgram").toString();if(p.program.isEmpty())p.program=programFor(runtimes(),p.runtime);
    if(!validEnvironment(c.value("environment").toMap())){p.error="Unsupported compatibility environment override.";return p;}
    const auto env=c.value("environment").toMap();for(auto it=env.constBegin();it!=env.constEnd();++it)p.environment.insert(it.key(),it.value().toString());
    if(!c.value("workingDirectory").toString().isEmpty()){QString directory=QFileInfo(c.value("workingDirectory").toString()).canonicalFilePath(),root=QFileInfo(game.value("root").toString()).canonicalFilePath();if(directory.isEmpty()||root.isEmpty()||!(directory==root||directory.startsWith(root+"/"))){p.error="Working directory must remain inside this game folder.";return p;}p.workingDirectory=directory;}
    if(p.runtime=="native"){p.program=path;p.arguments=c.value("arguments").toStringList();if(!QFileInfo(path).isExecutable())p.error="Native game is not executable.";}
    else if(p.runtime=="wine"||p.runtime=="proton"){QString target=c.value("launcher").toString();if(target.isEmpty())target=path;QFileInfo launcher(target);if(!launcher.isFile()||!target.endsWith(".exe",Qt::CaseInsensitive)){p.error="Select the installed Windows/Plutonium .exe launcher.";return p;}p.arguments={target};p.arguments.append(c.value("arguments").toStringList());QString prefix=c.value("prefix").toString();if(prefix.isEmpty())prefix=state+"/prefixes/"+game.value("id").toString();QString expected=state+"/prefixes/"+game.value("id").toString();if(prefix!=expected&&prefix!=expected+"/pfx"){p.error="Wine prefix must belong to this game.";return p;}p.environment.insert("WINEPREFIX",prefix);if(p.runtime=="proton"){p.environment.insert("STEAM_COMPAT_DATA_PATH",expected);QString steam=c.value("steamClientPath").toString();if(!QFileInfo(steam).isDir()){p.error="Select the installed Steam client path for Proton.";return p;}p.environment.insert("STEAM_COMPAT_CLIENT_INSTALL_PATH",steam);p.arguments.prepend("waitforexitandrun");}}
    else if(p.runtime=="dosbox"){p.arguments={path,"-exit"};QString conf=c.value("dosboxConfig").toString();if(!conf.isEmpty()){if(!QFileInfo(conf).isFile()){p.error="DOSBox configuration file is unavailable.";return p;}p.arguments<<"-conf"<<conf;}}
    else if(p.runtime=="scummvm"){QString id=c.value("scummvmGameId").toString();if(!QRegularExpression("^[A-Za-z0-9_:-]+$").match(id).hasMatch()){p.error="Select a supported ScummVM game ID.";return p;}p.arguments={"--path="+game.value("root").toString(),id};}
    else if(p.runtime=="cemu")p.arguments={"-f","-g",path};
    else if(p.runtime=="dolphin")p.arguments={"-b","-e",path};
    else if(p.runtime=="ppsspp")p.arguments={path};
    else if(p.runtime=="duckstation")p.arguments={"-fullscreen",path};
    else if(p.runtime=="pcsx2")p.arguments={"-fullscreen","--",path};
    else if(p.runtime=="rpcs3")p.arguments={"--no-gui",path};
    else if(p.runtime=="ruffle")p.arguments={path};
    else if(p.runtime=="retroarch"){
        QString core=c.value("core").toString();if(!QFileInfo(core).isFile()||!core.endsWith("_libretro.so")){p.error="Choose an installed compatible libretro core.";return p;}p.arguments={"-f","-L",core,path};
    } else if(p.runtime=="moonlight"){
        QString host=game.value("host").toString(),app=game.value("remoteApp").toString();if(host.isEmpty()||host.startsWith('-')||app.isEmpty()){p.error="Remote descriptor requires a paired host and application.";return p;}p.arguments={"stream",host,app};
    } else p.error="Runtime does not have a supported process lifecycle adapter.";
    if(!p.program.isEmpty()&&p.runtime!="native"&&(!QFileInfo(p.program).isAbsolute()||!QFileInfo(p.program).isExecutable()))p.error="Selected runtime is not an executable installed file.";
    if(p.program.isEmpty())p.error="Configured runtime disappeared; setup must be reviewed.";
    // No system GPU/clocks or runtime-specific unsupported switches are injected.
    return p;
}
}
