#include <QGuiApplication>
#include <QStandardPaths>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlComponent>
#include <QUrl>
#include "AppManager.h"
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>
#include <QHash>
#include <QPointer>
#include <QProcess>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QEventLoop>
#include <QTimer>
#include <QDir>
#include <QCryptographicHash>
#include <functional>
#include "HumanAccountPolicy.h"
#define private public
#include "AppStoreManager.h"
#undef private
static QByteArray bytes(const QString &path){QFile f(path);return f.open(QIODevice::ReadOnly)?f.readAll():QByteArray();}
static bool operation(AppStoreManager &store,const std::function<bool()> &start){
 QEventLoop loop;bool finished=false,passed=false;
 auto c=QObject::connect(&store,&AppStoreManager::operationFinished,&loop,[&](const QString &,const QString &,bool ok,const QString &){finished=true;passed=ok;loop.quit();});
 const bool began=start();if(began&&!finished){QTimer::singleShot(900000,&loop,&QEventLoop::quit);loop.exec();}
 QObject::disconnect(c);return began&&finished&&passed;
}
int main(int argc,char **argv){
 QGuiApplication app(argc,argv);if(argc!=2)return 2;QDir fixtures(QString::fromLocal8Bit(argv[1]));
 HumanHome::setSessionUser(QStringLiteral("geminivalfixture"));if(HumanHome::path().isEmpty())return 3;
 AppManager apps;apps.setActiveUser("geminivalfixture");AppStoreManager store("/opt/neutronos",&apps,nullptr,nullptr);
 QEventLoop warm;QTimer::singleShot(2300,&warm,&QEventLoop::quit);warm.exec();
 const bool runtimePreviouslyInstalled=!QStandardPaths::findExecutable("wine").isEmpty();
 bool rebuilt=false;QObject::connect(&store,&AppStoreManager::rebuildStateChanged,&app,[&](){rebuilt=rebuilt||store.rebuilding();});
 const auto shellModified=QFileInfo("/opt/neutronos/build/NeutronShell").lastModified();
 const QString repoPath=store.repositoriesPath();const QByteArray originalRepos=bytes(repoPath);
 QJsonObject checks;const QByteArray shell=QCryptographicHash::hash(bytes("/opt/neutronos/build/NeutronShell"),QCryptographicHash::Sha256);
 auto catalog=[&](const QString &name){store.writeJsonObject(repoPath,{{"schema",1},{"repositories",QVariantList{QVariantMap{{"id","gemini-validation"},{"name","Gemini disposable validation"},{"url",fixtures.filePath(name)},{"enabled",true},{"trusted",true}}}}});store.refreshCatalog();};
 auto unchanged=[&](){return !rebuilt&&QFileInfo("/opt/neutronos/build/NeutronShell").lastModified()==shellModified&&QCryptographicHash::hash(bytes("/opt/neutronos/build/NeutronShell"),QCryptographicHash::Sha256)==shell;};
 catalog("index.json");auto package=store.packageById("gemini-games");
 checks["signedCompatibleReview4Catalog"]=package.value("version").toString()=="0.1.0-review.4"&&package.value("signatureReady").toBool()&&package.value("storeEligible").toBool();
 checks["installThroughProductionAppStore"]=operation(store,[&]{return store.installPackage("gemini-games");});
 checks["installedVersion"]=store.installedVersion("gemini-games")=="0.1.0-review.4";checks["installNoOSRebuild"]=unchanged();
 apps.reloadApps();auto installed=apps.appById("gemini-games");
 auto displayed=[&](){for(const auto &entry:apps.dashboardApps()){auto row=entry.toMap();if(row.value("id").toString()=="gemini-games")return row;}return QVariantMap();};
 const QString icon=QUrl(displayed().value("iconSource").toString()).toLocalFile();
 checks["officialInstalledIcon"]=QCryptographicHash::hash(bytes(icon),QCryptographicHash::Sha256).toHex()=="2a1d19829eb53419edc46be939bd2addf558bc1d4c7aaaa9ef7cd2c3aa2668fc";
 const QString entry=apps.resolveQmlEntry(installed);checks["installedQmlEntryExists"]=QFile::exists(entry);
 QString native=QFileInfo(entry).absolutePath()+"/native/review4";
 for(int restart=0;restart<2;restart++){
  QQmlEngine engine;QObject identity;identity.setProperty("activeUsername",QString("geminivalfixture"));engine.rootContext()->setContextProperty("securityManager",&identity);
  QQmlComponent component(&engine);component.setData(("import QtQml\nimport \""+QUrl::fromLocalFile(native).toString()+"\" as Native\nQtObject{property var backend:Native.GamesBackend}").toUtf8(),QUrl::fromLocalFile(QFileInfo(entry).absolutePath()+"/Probe.qml"));
  QObject *root=component.create();QObject *backend=root?root->property("backend").value<QObject*>():nullptr;bool initialized=false;
  checks[QString("installedNativeLaunch%1").arg(restart)]=backend&&QMetaObject::invokeMethod(backend,"initialize",Q_RETURN_ARG(bool,initialized))&&initialized;
  bool managerStarted=false,managerSucceeded=false;
  if(backend){QEventLoop managerLoop;auto timer=new QTimer(&managerLoop);timer->setInterval(100);QObject::connect(timer,&QTimer::timeout,&managerLoop,[&]{if(!backend->property("managerBusy").toBool()){managerSucceeded=backend->property("managerState").toMap().value("success").toBool();managerLoop.quit();}});QVariantMap status{{"action","status"}};QMetaObject::invokeMethod(backend,"managerOperation",Q_RETURN_ARG(bool,managerStarted),Q_ARG(QVariantMap,status));if(managerStarted){timer->start();QTimer::singleShot(30000,&managerLoop,&QEventLoop::quit);managerLoop.exec();}}
  checks[QString("packagedHelperStatus%1").arg(restart)]=managerStarted&&managerSucceeded;
  delete root;
 }
 for(const QString &name:{"missing-capability.napp","wrong-qt-abi.napp"}){QString error;QByteArray data=bytes(fixtures.filePath(name));auto probe=package;probe["sha256"]=QString::fromLatin1(QCryptographicHash::hash(data,QCryptographicHash::Sha256).toHex());checks[name+"Rejected"]=!store.verifyPackageBytes(data,probe,&error)&&!error.isEmpty();}
 checks["freshUninstall"]=operation(store,[&]{return store.uninstallPackage("gemini-games");});
 catalog("index-previous.json");checks["installPreviousReview3"]=operation(store,[&]{return store.installPackage("gemini-games");});
 checks["previousVersionRecognized"]=store.installedVersion("gemini-games")=="0.1.0-review.3";
 catalog("index.json");checks["review4UpgradeOffered"]=store.packageById("gemini-games").value("updateEligible").toBool();
 checks["upgradePreviousReview3"]=operation(store,[&]{return store.updatePackage("gemini-games");});
 apps.reloadApps();checks["upgradeOfficialIcon"]=QCryptographicHash::hash(bytes(QUrl(displayed().value("iconSource").toString()).toLocalFile()),QCryptographicHash::Sha256).toHex()=="2a1d19829eb53419edc46be939bd2addf558bc1d4c7aaaa9ef7cd2c3aa2668fc";
 checks["upgradeNoOSRebuild"]=unchanged();
 catalog("index-update.json");checks["updateOffered"]=store.packageById("gemini-games").value("updateEligible").toBool();
 checks["updateThroughAppStore"]=operation(store,[&]{return store.updatePackage("gemini-games");});checks["updatedVersion"]=store.installedVersion("gemini-games")=="0.1.1-vm-only";checks["updateNoOSRebuild"]=unchanged();
 checks["rollbackThroughAppStore"]=operation(store,[&]{return store.rollbackPackage("gemini-games");});checks["rollbackVersion"]=store.installedVersion("gemini-games")=="0.1.0-review.4";
 checks["uninstallThroughAppStore"]=operation(store,[&]{return store.uninstallPackage("gemini-games");});checks["registryRemoved"]=!store.isInstalled("gemini-games");checks["ownedIconRemoved"]=!QFile::exists(icon);checks["uninstallNoOSRebuild"]=unchanged();
 catalog("index.json");
 auto eligible=[&](){QJsonObject last;for(const auto &line:store.m_operationOutput.split('\n')){auto row=QJsonDocument::fromJson(line).object();if(row.contains("dependencyEligibility"))last=row.value("dependencyEligibility").toObject();}return last;};
 checks["sharedAInstalled"]=operation(store,[&]{return store.installPackage("shared-a-vm-only");});
 checks["sharedBInstalled"]=operation(store,[&]{return store.installPackage("shared-b-vm-only");});
 checks["sharedFirstOwnerRemoved"]=operation(store,[&]{return store.uninstallPackage("shared-a-vm-only");});
 const auto firstEligibility=eligible();checks["sharedDependencyProtectedWhileOtherAppRequiresIt"]=firstEligibility.value("known").toBool()&&!firstEligibility.value("eligible").toArray().contains("hello");
 checks["sharedFinalOwnerRemoved"]=operation(store,[&]{return store.uninstallPackage("shared-b-vm-only");});
 const auto lastEligibility=eligible();checks["lastOwnerRemovalMakesOnlyOrphanEligible"]=lastEligibility.value("known").toBool()&&lastEligibility.value("eligible").toArray().contains("hello")&&!lastEligibility.value("eligible").toArray().contains("sed");
 QProcess installedDependency;installedDependency.start("/usr/bin/dpkg-query",{"-W","-f=${Status}","hello"});installedDependency.waitForFinished(15000);checks["eligibleDependencyRetainedForSeparateReview"]=installedDependency.exitCode()==0&&installedDependency.readAllStandardOutput().contains("install ok installed");
 checks["optionalRuntimeStateUnchangedByGamesLifecycle"]=runtimePreviouslyInstalled==!QStandardPaths::findExecutable("wine").isEmpty();
 bool passed=true;for(auto it=checks.begin();it!=checks.end();++it)passed=passed&&it.value().toBool();
 QFile repos(repoPath);if(repos.open(QIODevice::WriteOnly))repos.write(originalRepos);
 QJsonObject report{{"testedPackageSHA256",QString::fromLatin1(QCryptographicHash::hash(bytes(fixtures.filePath("Gemini-Games-0.1.0-review.4.napp")),QCryptographicHash::Sha256).toHex())},{"passed",passed},{"checks",checks},{"productionAppStoreManager",true},{"installedIconPath",icon},{"installedQmlEntry",entry},{"lastStatus",store.statusMessage()},{"lastError",store.lastError()},{"frontendControllerRendering","Separate rendered production-event replay evidence"}};
 fprintf(stdout,"%s\n",QJsonDocument(report).toJson(QJsonDocument::Compact).constData());return passed?0:1;
}
