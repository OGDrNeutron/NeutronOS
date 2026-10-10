#include "GeminiGamesBackend.h"
#include "AccountIdentity.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QQmlEngine>
#include <QSaveFile>
#include <QUrl>
#include <QStandardPaths>
#include <signal.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>
namespace GeminiGames {
OwnedProcess::OwnedProcess(QObject *parent):QObject(parent){
    m_process.setChildProcessModifier([]{if(setsid()<0)_exit(127);prctl(PR_SET_PDEATHSIG,SIGKILL);});
    m_timeout.setSingleShot(true);
    connect(&m_process,&QProcess::started,this,&OwnedProcess::started);
    connect(&m_process,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus status){m_timeout.stop();emit exited(code,status==QProcess::NormalExit);});
    connect(&m_process,&QProcess::errorOccurred,this,[this](QProcess::ProcessError e){if(e==QProcess::FailedToStart)emit failed(m_process.errorString());});
    connect(&m_timeout,&QTimer::timeout,this,[this]{if(running())emit stopTimedOut();});
}
bool OwnedProcess::start(const QString &program,const QStringList &args,const QProcessEnvironment &env,const QString &dir,const QString &log){if(running())return false;m_process.setProcessEnvironment(env);m_process.setWorkingDirectory(dir);m_process.setStandardOutputFile(log,QIODevice::Append);m_process.setStandardErrorFile(log,QIODevice::Append);m_process.start(program,args);return true;}
bool OwnedProcess::signal(int number){qint64 id=m_process.processId();return id>1&&getpgid(pid_t(id))==pid_t(id)&&kill(-pid_t(id),number)==0;}
void OwnedProcess::gracefulStop(int ms){if(!running())return;signal(SIGCONT);signal(SIGTERM);m_timeout.start(ms);}
void OwnedProcess::forceStop(){if(running()){signal(SIGCONT);signal(SIGKILL);}m_timeout.stop();}
GeminiGamesBackend::GeminiGamesBackend(QObject *parent):QObject(parent),m_process(this){
    m_hardware=RuntimeAdapters::hardware();
    connect(&m_manager,&QProcess::readyReadStandardOutput,this,&GeminiGamesBackend::consumeManager);
    connect(&m_manager,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int,QProcess::ExitStatus){consumeManager();if(m_managerResult)emit managerFinished(m_managerAction,m_managerState.value("success").toBool(),m_managerState);if(!m_managerResult){m_managerState={{"success",false},{"message","Games manager stopped before reporting completion. Review installation logs; files and saves are retained."}};emit managerFinished(m_managerAction,false,m_managerState);}emit managerChanged();emit changed();if(!ownsAccount())initialize();});
    connect(&m_manager,&QProcess::errorOccurred,this,[this](QProcess::ProcessError error){if(error==QProcess::FailedToStart){m_managerState={{"success",false},{"message",m_manager.errorString()}};emit managerChanged();emit managerFinished(m_managerAction,false,m_managerState);}});

    m_footerTimer.setSingleShot(true);m_footerTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_footerTimer,&QTimer::timeout,this,&GeminiGamesBackend::footerTimeout);
    m_launchTimeout.setSingleShot(true);m_launchTimeout.setInterval(5000);
    connect(&m_launchTimeout,&QTimer::timeout,this,[this]{notify("Game input service did not become ready. Launch cancelled.",true);restore();});
    connect(&m_input,&QLocalSocket::connected,this,[this]{auto profile=m_current.value("controllerProfile").toMap();inputCommand("begin",{{"profile",profile}});});
    connect(&m_input,&QLocalSocket::readyRead,this,&GeminiGamesBackend::consumeInput);
    connect(&m_input,&QLocalSocket::disconnected,this,[this]{if(gameActive()){notify("Controller ownership service disconnected. Closing the owned game safely.",true);m_closing=true;m_process.gracefulStop();}});
    connect(&m_input,&QLocalSocket::errorOccurred,this,[this](QLocalSocket::LocalSocketError){if(m_launchPending){notify("Gemini game input service unavailable: "+m_input.errorString(),true);restore();}});
    connect(&m_process,&OwnedProcess::started,this,[this]{m_launchPending=false;m_launchTimeout.stop();m_gamingMode=m_preferences.value("lowResource",true).toBool();recordSample("launch");if(m_gamingMode&&m_window){m_window->setPersistentSceneGraph(false);m_window->setPersistentGraphics(false);m_window->hide();m_window->releaseResources();}if(m_library)m_library->setQuiescent(true);if(m_artwork)m_artwork->setQuiescent(true);m_sampleTimer.start();emit sessionChanged();});
    connect(&m_process,&OwnedProcess::failed,this,[this](const QString &error){notify("Game launch failed: "+error,true);restore();});
    connect(&m_process,&OwnedProcess::exited,this,[this](int code,bool normal){notify(m_closing|| (normal&&code==0)?"Game session ended.":"Game exited with code "+QString::number(code)+". Review the runtime log.",!m_closing&&(!normal||code!=0));restore();});
    connect(&m_process,&OwnedProcess::stopTimedOut,this,[this]{m_stopTimedOut=true;openMenu();notify("Game refused graceful termination. Force Close is now available.",true);emit sessionChanged();});
    m_sampleTimer.setInterval(5000);connect(&m_sampleTimer,&QTimer::timeout,this,[this]{recordSample(m_menuOpen?"menu":"gaming");});
    m_homeTimer.setSingleShot(true);m_homeTimer.setTimerType(Qt::PreciseTimer);m_homeTimer.setInterval(3000);connect(&m_homeTimer,&QTimer::timeout,this,[this]{if(m_homeHold.isValid()&&m_homeHold.elapsed()>=3000)openMenu();});
}
GeminiGamesBackend::~GeminiGamesBackend(){if(managerBusy()){m_manager.terminate();if(!m_manager.waitForFinished(15000)){m_manager.kill();m_manager.waitForFinished(2000);}}m_process.forceStop();inputCommand("end");}
bool GeminiGamesBackend::ownsAccount()const{return !m_home.isEmpty()&&activeGamesHome(m_identity)==m_home;}
void GeminiGamesBackend::accountChanged(){if(!ownsAccount()){if(managerBusy())cancelManager();setSystemAccess(false);}m_footerTimer.stop();initialize();emit changed();emit sessionChanged();}
void GeminiGamesBackend::setSystemAccess(bool available){available=available&&ownsAccount();if(m_systemAccess==available)return;m_systemAccess=available;/* System keyboard temporarily owns input; keep the approved installer running. Account loss cancels in accountChanged(). */if(!available&&gameActive()){m_homeTimer.stop();m_homeHold.invalidate();m_menuOpen=false;m_backgrounded=true;inputCommand("background");if(m_window){m_window->show();m_window->raise();m_window->requestActivate();}emit sessionChanged();}}
bool GeminiGamesBackend::initialize(){
    QString home=activeGamesHome(m_identity);if(home.isEmpty()){notify("No validated Gemini human account is active. Personal Games storage cannot be resolved.",true);return false;}
    for(const auto &path:QStringList{home,home+"/apps",home+"/apps/gemini-games"}){QFileInfo info(path);if(info.exists()&&(info.isSymLink()||info.canonicalFilePath()!=path)){notify("Personal Games storage is redirected; access denied.",true);return false;}}
    if(home==m_home&&m_library)return true;
    if(gameActive()||managerBusy()){notify("Finish the current game or installer before changing accounts.",true);return false;}
    if(m_library) delete m_library;
    if(m_artwork) delete m_artwork;
    m_preferences.clear();m_uiState.clear();m_messages.clear();m_current.clear();m_managerState.clear();m_runtimeChoices.clear();
    m_home=home;m_artwork=new GameArtwork(home,this);m_library=new GameLibrary(home,this);
    connect(m_artwork,&GameArtwork::changed,this,&GeminiGamesBackend::changed);connect(m_artwork,&GameArtwork::error,this,[this](const QString &e){notify(e);});
    if(!m_artwork->valid())notify("Personal artwork directory is unavailable or redirected.",true);
    connect(m_library,&GameLibrary::changed,this,[this]{if(m_artwork)m_artwork->refresh();emit changed();});connect(m_library,&GameLibrary::error,this,[this](const QString &e){notify(e,true);});
    QFile prefs(m_library->stateDirectory()+"/preferences.json");if(prefs.open(QIODevice::ReadOnly))m_preferences=QJsonDocument::fromJson(prefs.readAll()).object().toVariantMap();
    m_uiState=m_preferences.value("uiState").toMap();if(m_library->automatic())m_library->rescan();emit changed();return true;
}
void GeminiGamesBackend::refreshArtwork(){if(ownsAccount()&&m_artwork)m_artwork->refresh();}
bool GeminiGamesBackend::setArtworkAssignment(const QString &id,const QString &path){if(!ownsAccount()||!m_artwork||!m_library)return false;QString local=path.startsWith("file:")?QUrl(path).toLocalFile():path;if(!local.isEmpty()&&!m_artwork->contains(local)){notify("Select an available image from your Games artwork directory.",true);return false;}return m_library->update(id,{{"artworkOverride",local.isEmpty()?QString():QUrl::fromLocalFile(local).toString()}});}
QVariantMap GeminiGamesBackend::browseFolders(const QString &path) const {return ownsAccount()&&m_library?m_library->browseFolders(path):QVariantMap{{"ok",false},{"error","Sign in to browse your Games folders."}};}
bool GeminiGamesBackend::addFolder(const QString &p){return ownsAccount()&&m_library&&m_library->addRoot(p);}
bool GeminiGamesBackend::editFolder(int i,const QString &p){return ownsAccount()&&m_library&&m_library->editRoot(i,p);}
bool GeminiGamesBackend::removeFolder(int i){return ownsAccount()&&m_library&&m_library->removeRoot(i);}
void GeminiGamesBackend::rescan(){if(ownsAccount()&&m_library)m_library->rescan();}
bool GeminiGamesBackend::favorite(const QString &id,bool v){return ownsAccount()&&m_library&&m_library->update(id,{{"favorite",v}});}
bool GeminiGamesBackend::updateMetadata(const QString &id,const QString &field,const QString &value){if(!ownsAccount()||!m_library)return false;if(field=="title"&&!value.trimmed().isEmpty()&&value.size()<=256)return m_library->update(id,{{"titleOverride",value.trimmed()}});if(field=="artwork")return setArtworkAssignment(id,value);return false;}
bool GeminiGamesBackend::choosePlatform(const QString &id,const QString &kind){if(!ownsAccount()||!m_library)return false;auto g=m_library->find(id);auto allowed=g.value("candidates").toStringList();if(!allowed.contains(kind))return false;return m_library->update(id,{{"chosenKind",kind},{"configuration",QVariantMap()}});}
QVariantList GeminiGamesBackend::recommendations(const QString &id)const{return ownsAccount()&&m_library?RuntimeAdapters::recommendations(m_library->find(id),m_hardware,installedRuntimes()):QVariantList();}
bool GeminiGamesBackend::configure(const QString &id,const QVariantMap &configuration,bool approved){
    if(!ownsAccount()||!approved||!m_library)return false;
    auto g=m_library->find(id);if(g.isEmpty())return false;
    QString requested=configuration.value("runtime").toString();bool allowed=false;for(const auto &v:recommendations(id)){auto r=v.toMap();if(r.value("id")==requested&&r.value("capabilities").toMap().value("launch").toBool()&&r.value("status")!="unsupported")allowed=true;}
    if(!allowed){notify("No validated candidate runtime is installed for this game. Review compatibility or configure remote streaming.",true);return false;}
    QVariantMap c=configuration;c["signature"]=g.value("signature");if(c.value("arguments").toStringList().size()>64)return false;
    auto plan=RuntimeAdapters::plan(g,c,m_library->stateDirectory());if(RuntimeAdapters::runtimeAvailable(c)&&!plan.error.isEmpty()){notify(plan.error,true);return false;}
    for(const auto &arg:configuration.value("arguments").toList())if(arg.metaType().id()!=QMetaType::QString){notify("Launch arguments must be strings.",true);return false;}
    c["configuredAt"]=QDateTime::currentDateTimeUtc().toString(Qt::ISODate);return m_library->update(id,{{"configuration",c}});
}
bool GeminiGamesBackend::play(const QString &id){
    if(!ownsAccount()||!m_library||gameActive()||managerBusy())return false;
    if(!m_systemAccess){notify("Game launch requires an active authenticated Gemini application session.",true);return false;}
    if(!m_sessionIntegrationAvailable){notify("Game launch requires the Gemini package-session capability. Library browsing remains available.",true);return false;}
    if(geteuid()==0){notify("Games cannot launch with root privileges.",true);return false;}
    m_controllers.clear();m_current=m_library->find(id);auto c=m_current.value("configuration").toMap();if(c.isEmpty()){notify("Configure a compatible runtime and controller profile first.");return false;}
    if(!RuntimeAdapters::runtimeAvailable(c)){emit runtimeMissing(id,c.value("runtime").toString());return false;}
    if(m_current.value("installationPending").toBool()){notify("Installation needs attention. Open Install / Compatibility to select its launch executable or repair it.",true);return false;}
    m_plan=RuntimeAdapters::plan(m_current,c,m_library->stateDirectory());if(!m_plan.error.isEmpty()){notify(m_plan.error,true);return false;}
    if(QStandardPaths::findExecutable("bwrap").isEmpty()){notify("Game launch denied: the required bubblewrap sandbox is unavailable.",true);return false;}
    m_launchPending=true;m_stopTimedOut=false;m_closing=false;recordSample("before");m_launchTimeout.start();m_input.connectToServer("/run/neutronos-controller-proxy/control.sock");emit sessionChanged();return true;
}
void GeminiGamesBackend::inputCommand(const QString &command,const QVariantMap &extra){if(m_input.state()!=QLocalSocket::ConnectedState)return;auto message=extra;message["command"]=command;m_input.write(QJsonDocument::fromVariant(message).toJson(QJsonDocument::Compact)+"\n");m_input.flush();}
void GeminiGamesBackend::consumeInput(){
    m_inputBytes+=m_input.readAll();if(m_inputBytes.size()>65536){m_input.abort();return;}
    int end;while((end=m_inputBytes.indexOf('\n'))>=0){auto raw=m_inputBytes.left(end);m_inputBytes.remove(0,end+1);auto msg=QJsonDocument::fromJson(raw).object();QString event=msg.value("event").toString();
        if(event=="ready"&&m_launchPending){m_controllerCount=msg.value("controllers").toInt();if(m_controllerCount<1){notify("No supported physical gamepad is available. Launch cancelled.",true);restore();}else if(!launchPrepared())restore();}
        else if(event=="inputReset"){m_homeTimer.stop();m_homeHold.invalidate();emit inputReset();}
        else if(event=="homeHold"&&m_process.running())openMenu();
        else if(event=="action"&&ownsAccount()&&m_systemAccess){if(m_menuOpen&&msg.value("pressed").toBool(true))emit modalAction(msg.value("action").toString());else if(m_backgrounded)emit backgroundAction(msg.value("action").toString(),msg.value("pressed").toBool(true));}
        else if(event=="connected"){m_controllers.append(msg.toVariantMap());m_controllerCount=m_controllers.size();emit sessionChanged();}
        else if(event=="disconnected"){for(int i=m_controllers.size()-1;i>=0;--i)if(m_controllers[i].toMap().value("slot").toInt()==msg.value("slot").toInt())m_controllers.removeAt(i);m_controllerCount=m_controllers.size();notify("Controller disconnected; reconnect to continue.");emit sessionChanged();}
    }
}
bool GeminiGamesBackend::launchPrepared(){
    if(!ownsAccount()||!m_systemAccess||!m_sessionIntegrationAvailable){notify("Session ownership changed during setup. Launch cancelled.",true);return false;}
    m_plan.environment.insert("SDL_VIDEODRIVER","wayland");
    const auto configEnvironment=m_current.value("configuration").toMap().value("environment").toMap();
    QString state=m_library->stateDirectory()+"/runtime/"+m_current.value("id").toString();QDir().mkpath(state);QStringList args={"--clearenv","--setenv","PATH","/usr/local/bin:/usr/bin:/bin","--setenv","LANG","C.UTF-8","--die-with-parent","--unshare-all","--cap-drop","ALL","--ro-bind","/usr","/usr","--proc","/proc","--dev","/dev","--tmpfs","/tmp","--ro-bind","/etc","/etc","--ro-bind","/sys","/sys","--dir","/run","--bind",state,state,"--setenv","HOME",state,"--setenv","XDG_CONFIG_HOME",state+"/config","--setenv","XDG_CACHE_HOME",state+"/cache","--setenv","XDG_DATA_HOME",state+"/data"};
    for(const auto &p:{QString("/bin"),QString("/lib"),QString("/lib64")})if(QFileInfo(p).exists())args<<"--ro-bind"<<p<<p;
    for(const auto &v:m_library->roots()){QString p=v.toMap().value("path").toString();if(QFileInfo(p).isDir())args<<"--ro-bind"<<p<<p;}
    QString input="/dev/neutronos-controller-proxy";args<<"--dev-bind"<<input<<"/dev/input";
    for(const auto &p:{QString("/dev/dri"),QString("/dev/snd")})if(QFileInfo(p).exists())args<<"--dev-bind"<<p<<p;
    for(const auto &p:{qEnvironmentVariable("XDG_RUNTIME_DIR"),qEnvironmentVariable("PIPEWIRE_RUNTIME_DIR")})if(!p.isEmpty()&&QFileInfo(p).isDir())args<<"--bind"<<p<<p;
    if(m_plan.runtime=="wine"||m_plan.runtime=="proton") {QString prefix=m_plan.environment.value("WINEPREFIX");QDir().mkpath(prefix);args<<"--bind"<<prefix<<prefix;if(m_plan.runtime=="proton"){QString data=m_plan.environment.value("STEAM_COMPAT_DATA_PATH");args<<"--bind"<<data<<data;QString steam=m_plan.environment.value("STEAM_COMPAT_CLIENT_INSTALL_PATH");args<<"--ro-bind"<<steam<<steam;}}
    if(m_current.value("installation").isValid()){QString root=m_current.value("root").toString();if(QFileInfo(root).isDir()&&m_plan.runtime!="wine"&&m_plan.runtime!="proton")args<<"--ro-bind"<<root<<root;else if(QFileInfo(root).isDir()&&m_current.value("installation").toMap().value("mode")=="import")args<<"--ro-bind"<<root<<root;}
    if(!m_plan.program.startsWith("/usr/")&&m_plan.runtime!="native"){QString runtimeRoot=QFileInfo(m_plan.program).dir().absolutePath();if(m_plan.runtime=="wine"&&QFileInfo(runtimeRoot).fileName()=="bin")runtimeRoot=QFileInfo(runtimeRoot).dir().absolutePath();args<<"--ro-bind"<<runtimeRoot<<runtimeRoot;}
    bool network=m_current.value("configuration").toMap().value("network",false).toBool()||m_plan.runtime=="moonlight";if(network)args<<"--share-net";
    for(const auto &name:QStringList{"XDG_RUNTIME_DIR","WAYLAND_DISPLAY","PIPEWIRE_RUNTIME_DIR","PULSE_SERVER","SDL_VIDEODRIVER","WINEPREFIX","STEAM_COMPAT_DATA_PATH","STEAM_COMPAT_CLIENT_INSTALL_PATH"}){QString value=m_plan.environment.value(name);if(!value.isEmpty())args<<"--setenv"<<name<<value;}
    for(auto it=configEnvironment.constBegin();it!=configEnvironment.constEnd();++it)args<<"--setenv"<<it.key()<<it.value().toString();
    // The private input directory is the sole gamepad interface. Filesystem
    // hotplug works across its isolated network namespace; HIDAPI must not
    // claim the physical controller instead of the owned evdev proxy.
    args<<"--setenv"<<"SDL_JOYSTICK_DISABLE_UDEV"<<"1"<<"--setenv"<<"SDL_JOYSTICK_HIDAPI"<<"0";
    auto profile=m_current.value("controllerProfile").toMap();QString mapping=profile.value("sdlMapping").toString();if(!mapping.isEmpty())args<<"--setenv"<<"SDL_GAMECONTROLLERCONFIG"<<mapping;
    auto config=m_current.value("configuration").toMap();for(const auto &name:QStringList{"launcher","core","dosboxConfig"}){QString file=config.value(name).toString();if(!file.isEmpty()&&QFileInfo(file).isFile()&&!file.startsWith("/usr/")){args<<"--ro-bind"<<file<<file;}}
    args<<"--"<<m_plan.program;args.append(m_plan.arguments);
    m_plan.environment.insert("SDL_VIDEODRIVER","wayland");m_plan.environment.remove("SDL_GAMECONTROLLERCONFIG");

    QString launchProgram=QStandardPaths::findExecutable("bwrap");
    if(m_plan.runtime=="wine"||m_plan.runtime=="proton"){
        if(m_managerProgram.isEmpty()||!QFileInfo(m_managerProgram).isFile()){notify("The signed Games runtime helper is unavailable. Reinstall Games through the App Store.",true);return false;}
        QString prefix=m_plan.runtime=="proton"?m_plan.environment.value("STEAM_COMPAT_DATA_PATH"):m_plan.environment.value("WINEPREFIX");
        QStringList wrapped={m_managerProgram,"--prefix-run",m_home,prefix,"--",launchProgram};wrapped.append(args);args=wrapped;launchProgram="/usr/bin/python3";
    }
    bool launched=m_process.start(launchProgram,args,m_plan.environment,m_plan.workingDirectory,logPath());
    if(launched){auto count=m_current.value("playCount").toInt();m_library->update(m_current.value("id").toString(),{{"lastPlayed",QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},{"playCount",count+1}});}return launched;
}
void GeminiGamesBackend::openMenu(){if(!ownsAccount()||!m_systemAccess||!m_process.running())return;m_menuOpen=true;m_backgrounded=false;inputCommand("modal");auto c=m_current.value("configuration").toMap();if(m_plan.capabilities.value("pause").toBool()&&c.value("offlineSuspend",false).toBool())m_paused=m_process.signal(SIGSTOP);if(m_window){m_window->show();m_window->raise();m_window->requestActivate();}emit sessionChanged();}
bool GeminiGamesBackend::resumeGame(){if(!ownsAccount()||!m_systemAccess||!m_process.running()||m_stopTimedOut)return false;if(m_paused&&!m_process.signal(SIGCONT)){notify("Unable to resume the owned process.",true);return false;}m_paused=false;m_menuOpen=false;m_backgrounded=false;inputCommand("resume");if(m_window)m_window->hide();emit sessionChanged();return true;}
void GeminiGamesBackend::closeGame(){if(!ownsAccount())return;if(m_launchPending&&!m_process.running()){restore();return;}if(!m_process.running())return;m_menuOpen=true;m_closing=true;m_process.gracefulStop();emit sessionChanged();}
void GeminiGamesBackend::forceCloseGame(){if(!ownsAccount()||!m_stopTimedOut)return;m_process.forceStop();}
bool GeminiGamesBackend::prepareSwitch(){if(!ownsAccount())return false;if(!gameActive())return true;auto c=m_current.value("configuration").toMap();if(!m_plan.capabilities.value("supportsBackground").toBool()||!c.value("offlineSuspend").toBool()){notify("This runtime has no validated safe background capability. Resume or close the game before switching.",true);return false;}openMenu();m_menuOpen=false;m_backgrounded=true;m_gamingMode=false;inputCommand("background");emit sessionChanged();return true;}
void GeminiGamesBackend::restore(){if(m_library)m_library->setQuiescent(false);if(m_artwork)m_artwork->setQuiescent(false);m_launchTimeout.stop();m_launchPending=false;m_homeTimer.stop();m_homeHold.invalidate();m_sampleTimer.stop();m_menuOpen=false;m_stopTimedOut=false;m_paused=false;m_backgrounded=false;m_gamingMode=false;m_closing=false;inputCommand("end");m_input.disconnectFromServer();m_inputBytes.clear();m_controllerCount=0;m_controllers.clear();if(m_window){m_window->show();m_window->raise();m_window->requestActivate();}recordSample("restored");if(!ownsAccount())initialize();emit sessionChanged();emit restoreRequested();}
bool GeminiGamesBackend::controllerPress(const QString &action){if(!ownsAccount()||!m_systemAccess||!gameActive())return false;if(action=="home"){if(!m_homeHold.isValid()){m_homeHold.start();m_homeTimer.start();}return true;}if(m_menuOpen)emit modalAction(action);return !m_backgrounded||action=="home";}
bool GeminiGamesBackend::controllerRelease(const QString &action){if(!ownsAccount()||!m_systemAccess||!gameActive())return false;if(action=="home"){m_homeTimer.stop();m_homeHold.invalidate();return true;}return !m_backgrounded;}
void GeminiGamesBackend::attachWindow(QObject *window){m_window=qobject_cast<QQuickWindow*>(window);}
void GeminiGamesBackend::notify(const QString &message,bool critical){if(message.isEmpty()||!ownsAccount())return;m_messages.append(QVariantMap{{"text",message},{"critical",critical},{"acknowledged",false},{"time",QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}});while(m_messages.size()>100){int i=-1;for(int j=0;j<m_messages.size();j++)if(!m_messages[j].toMap().value("critical").toBool()||m_messages[j].toMap().value("acknowledged").toBool()){i=j;break;}if(i<0)break;m_messages.removeAt(i);}emit changed();emit messagePublished(message,critical);}
void GeminiGamesBackend::acknowledge(int i){if(!ownsAccount()||i<0||i>=m_messages.size())return;auto m=m_messages[i].toMap();m["acknowledged"]=true;m_messages[i]=m;emit changed();}
bool GeminiGamesBackend::setPreference(const QString &name,const QVariant &value){if(!ownsAccount())return false;if(!QStringList{"lowResource","animations","artwork","automaticScan"}.contains(name))return false;m_preferences[name]=value;if(name=="automaticScan"&&m_library)m_library->setAutomatic(value.toBool());savePreferences();emit changed();return true;}
bool GeminiGamesBackend::setControllerProfile(const QString &id,const QVariantMap &profile){if(!ownsAccount()||!m_library||gameActive())return false;QString mapping=profile.value("sdlMapping").toString();if(mapping.size()>8192||mapping.contains('\n'))return false;return m_library->update(id,{{"controllerProfile",profile}});}
void GeminiGamesBackend::setUiState(const QVariantMap &state){if(!ownsAccount())return;m_uiState=state;m_preferences["uiState"]=state;savePreferences();}
void GeminiGamesBackend::savePreferences(){if(!ownsAccount()||!m_library)return;QSaveFile f(m_library->stateDirectory()+"/preferences.json");if(!f.open(QIODevice::WriteOnly)){notify("Preferences could not be saved.",true);return;}f.write(QJsonDocument::fromVariant(m_preferences).toJson());if(!f.commit())notify("Preferences could not be committed.",true);}
QString GeminiGamesBackend::logPath()const{return ownsAccount()&&m_library?m_library->stateDirectory()+"/runtime/"+m_current.value("id").toString()+"/game.log":QString();}
QVariantMap GeminiGamesBackend::resourceSample()const{timespec ts{};clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&ts);QVariantMap out{{"time",QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},{"cpuSeconds",double(ts.tv_sec)+double(ts.tv_nsec)/1e9},{"processId",QCoreApplication::applicationPid()},{"gameProcessId",m_process.pid()},{"gamingMode",m_gamingMode}};QFile f("/proc/self/status");if(f.open(QIODevice::ReadOnly)){for(const auto &line:f.readAll().split('\n'))if(line.startsWith("VmRSS:")||line.startsWith("VmHWM:"))out[QString::fromLatin1(line.left(line.indexOf(':')))]=QString::fromLatin1(line.mid(line.indexOf(':')+1)).trimmed();}out["controllers"]=controllers();out["gpu"]=RuntimeAdapters::hardware().value("gpus");return out;}
void GeminiGamesBackend::recordSample(const QString &phase){if(!m_library)return;QFile f(m_library->stateDirectory()+"/performance.jsonl");if(!f.open(QIODevice::WriteOnly|QIODevice::Append))return;auto sample=resourceSample();sample["phase"]=phase;f.write(QJsonDocument::fromVariant(sample).toJson(QJsonDocument::Compact)+"\n");}
bool GeminiGamesBackend::managerOperation(const QVariantMap &request){
    auto reject=[this](const QString &message){if(!managerBusy()){m_managerState={{"success",false},{"message",message}};emit managerChanged();}notify(message,true);return false;};
    if(!ownsAccount()||!m_library)return reject("Sign in to a validated human account before managing games.");
    if(managerBusy()||gameActive())return reject("Finish the active game or installation before starting another operation.");
    if(m_managerProgram.isEmpty()||!QFileInfo(m_managerProgram).isFile())return reject("The signed Games installation helper is unavailable. Reinstall Games through the App Store.");
    QString action=request.value("action").toString();
    if(action!="status"&&action!="browse"&&action!="inspect"&&(!m_systemAccess||geteuid()==0))return reject("Game changes require the active authenticated Gemini application session. Close any system input dialog and try again.");
    m_managerAction=action;m_managerResult=false;m_managerBytes.clear();m_managerState={{"event","progress"},{"stage","Preparing"},{"detail","Validating the selected local files."}};
    auto environment=QProcessEnvironment::systemEnvironment();environment.insert("PYTHONDONTWRITEBYTECODE","1");m_manager.setProcessEnvironment(environment);
    m_manager.start("/usr/bin/python3",{m_managerProgram,"--home",m_home});
    m_manager.write(QJsonDocument::fromVariant(request).toJson(QJsonDocument::Compact)+"\n");emit managerChanged();return true;
}
void GeminiGamesBackend::cancelManager(){if(managerBusy())m_manager.write("{\"action\":\"cancel\"}\n");}
void GeminiGamesBackend::installerControl(const QString &action,const QString &text){if(!ownsAccount()||!m_systemAccess||!managerBusy()||m_managerAction!="install")return;const QStringList allowed={"primary","up","down","left","right","l1","r1","text"};if(!allowed.contains(action)||text.size()>4096)return;m_manager.write(QJsonDocument::fromVariant(QVariantMap{{"action","controller"},{"control",action},{"text",text}}).toJson(QJsonDocument::Compact)+"\n");}
void GeminiGamesBackend::consumeManager(){
    m_managerBytes+=m_manager.readAllStandardOutput();if(m_managerBytes.size()>4*1024*1024){m_manager.terminate();return;}
    int end;while((end=m_managerBytes.indexOf('\n'))>=0){auto raw=m_managerBytes.left(end);m_managerBytes.remove(0,end+1);auto result=QJsonDocument::fromJson(raw).object().toVariantMap();if(result.isEmpty())continue;
        m_managerState=result;
        if(result.value("event")=="result"){
            m_managerResult=true;bool success=result.value("success").toBool();
            if(result.contains("runtimes"))m_runtimeChoices=result.value("runtimes").toList();
            if(m_library){if(result.contains("game"))m_library->registerInstallation(result.value("game").toMap());for(const auto &game:result.value("games").toList())m_library->registerInstallation(game.toMap());if(result.contains("removedId"))m_library->retireInstallation(result.value("removedId").toString());}
            if(!result.value("message").toString().isEmpty())notify(result.value("message").toString(),!success);

        }emit managerChanged();emit changed();
    }
}

}
