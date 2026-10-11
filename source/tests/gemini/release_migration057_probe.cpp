#include <QCoreApplication>
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QEventLoop>
#include <QTimer>
#include <QUrl>
#include <QCryptographicHash>
#include "HumanAccountPolicy.h"
#define private public
#include "AppStoreManager.h"
#undef private
#include "UpdateRecoveryManager.h"
#include <functional>
static QByteArray read(const QString &p){QFile f(p);return f.open(QIODevice::ReadOnly)?f.readAll():QByteArray();}
static bool run(AppStoreManager &m,const std::function<bool()> &start){QEventLoop loop;bool done=false,ok=false;auto c=QObject::connect(&m,&AppStoreManager::operationFinished,&loop,[&](const QString &,const QString &,bool success,const QString &message){qInfo().noquote()<<message;done=true;ok=success;loop.quit();});bool began=start();if(began&&!done){QTimer::singleShot(180000,&loop,&QEventLoop::quit);loop.exec();}QObject::disconnect(c);return began&&done&&ok;}
static bool check(UpdateRecoveryManager &m,const QString &name,const std::function<bool()> &start){QEventLoop loop;bool done=false,ok=false;auto c=QObject::connect(&m,&UpdateRecoveryManager::operationFinished,&loop,[&](const QString &op,bool success,const QString &message){qInfo().noquote()<<op<<message;if(op==name){done=true;ok=success;loop.quit();}});bool began=start();if(began&&!done){QTimer::singleShot(180000,&loop,&QEventLoop::quit);loop.exec();}QObject::disconnect(c);return began&&done&&ok;}
int main(int argc,char **argv){QCoreApplication app(argc,argv);if(argc!=3)return 2;QString phase=argv[1],fixture=argv[2];QJsonObject checks;
if(phase=="prerequisite"){
 HumanHome::setSessionUser("geminiupgradefixture");if(HumanHome::path().isEmpty())return 3;
 AppStoreManager store("/opt/neutronos",nullptr,nullptr,nullptr);QEventLoop warm;QTimer::singleShot(2300,&warm,&QEventLoop::quit);warm.exec();
 store.writeJsonObject(store.repositoriesPath(),{{"schema",1},{"repositories",QVariantList{QVariantMap{{"id","gemini-validation"},{"name","Isolated signed prerequisite"},{"url",fixture+"/index.json"},{"enabled",true},{"trusted",true}}}}});store.refreshCatalog();
 auto package=store.packageById("gemini-update-recovery");checks["catalogSignatureAndCompatibility"]=package.value("signatureReady").toBool()&&package.value("storeEligible").toBool();
 const QByteArray before=QCryptographicHash::hash(read("/opt/neutronos/build/NeutronShell"),QCryptographicHash::Sha256);
 checks["normalAppStoreInstallsPrerequisite"]=run(store,[&]{return store.installPackage("gemini-update-recovery");});
 checks["installedVersion"]=store.installedVersion("gemini-update-recovery")=="0.5.7";
 checks["shellUnchanged"]=before==QCryptographicHash::hash(read("/opt/neutronos/build/NeutronShell"),QCryptographicHash::Sha256);
 checks["OSRemains056UntilCompleteUpdate"]=QJsonDocument::fromJson(read("/etc/neutronos/version.json")).object().value("version").toString()=="0.5.6";
 checks["backendActivationComplete"]=QFile::exists("/var/lib/neutronos/update-recovery/backend-migrations/protocol2/complete.json");
 checks["R2BackendPreserved"]=QFile::exists("/var/lib/neutronos/update-recovery/backend-migrations/protocol2/originals/neutronos-update-recovery");
}else if(phase=="update"){
 // The network/authentication boundary is the existing local Mainline mirror.
 // The isolated fixture changes only the configured mirror path and omits sync.
 UpdateRecoveryManager manager("/opt/neutronos",nullptr);
 checks["baseline056"]=manager.currentVersion()=="0.5.6";
 manager.setManifestUrl(QUrl::fromLocalFile(fixture+"/mainline.json").toString());
 checks["signed057Discovered"]=check(manager,"check-update",[&]{return manager.checkForUpdates("mainline");})&&manager.manifestVerified()&&manager.updateAvailable()&&manager.availableVersion()=="0.5.7";
 checks["packageDownloadAndHash"]=check(manager,"download-update",[&]{return manager.downloadAvailableUpdate();})&&manager.packageVerified();
 QFile out(fixture+"/downloaded-envelope-path.txt");
 // Cache paths are reported for the isolated root/reboot controller; this probe does not reboot.
 qInfo().noquote()<<"DOWNLOADED_PACKAGE"<<manager.downloadedPackage();
}else return 2;
bool pass=true;for(auto it=checks.begin();it!=checks.end();++it)pass=pass&&it.value().toBool();fprintf(stdout,"%s\n",QJsonDocument(QJsonObject{{"passed",pass},{"checks",checks}}).toJson(QJsonDocument::Compact).constData());return pass?0:1;}
