#include <QCoreApplication>
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
 const bool began=start();if(began&&!finished){QTimer::singleShot(45000,&loop,&QEventLoop::quit);loop.exec();}
 QObject::disconnect(c);return began&&finished&&passed;
}
int main(int argc,char **argv){
 QCoreApplication app(argc,argv);if(argc!=2)return 2;QDir fixtures(QString::fromLocal8Bit(argv[1]));
 HumanHome::setSessionUser(QStringLiteral("geminiflow"));if(HumanHome::path().isEmpty())return 3;
 AppStoreManager store(QStringLiteral("/opt/neutronos"),nullptr,nullptr,nullptr);
 QEventLoop warm;QTimer::singleShot(2300,&warm,&QEventLoop::quit);warm.exec();
 const QString repoPath=store.repositoriesPath();const QByteArray originalRepos=bytes(repoPath);
 const QString registryPath=store.installedRegistryPath();const QByteArray originalRegistry=bytes(registryPath);
 QJsonObject checks;
 checks["runtimeGeminiDetected"]=store.currentPlatform()==QStringLiteral("gemini")&&store.currentArchitecture()==QStringLiteral("amd64");
 store.loadRepositories();bool geminiUrl=false,noApollo=true;
 for(const auto &v:store.repositories()){const auto r=v.toMap();if(r.value("id").toString()=="neutronos-official"){geminiUrl=r.value("url").toString().endsWith("/Apps/Gemini/index.json");noApollo=!r.value("url").toString().endsWith("/Apps/index.json");}}
 checks["GeminiOfficialCatalogSelected"]=geminiUrl&&noApollo;
 checks["signedBundledEmptyGeminiCatalogAccepted"]=store.loadBundledGeminiCatalog(QVariantMap{{"id","neutronos-official"}});
 auto catalog=[&](const QString &name){store.writeJsonObject(repoPath,{{"schema",1},{"repositories",QVariantList{QVariantMap{{"id","gemini-validation"},{"name","Gemini disposable validation"},{"url",fixtures.filePath(name)},{"enabled",true},{"trusted",true}}}}});store.refreshCatalog();return store.catalog();};
 store.m_installedRegistry.clear();
 const auto valid=catalog("index.json");
 checks["signedGeminiCatalogLoads"]=store.repositoryConnected()&&valid.size()==1;
 QVariantMap package=store.packageById("gemini-trust-test");
 checks["ApolloSameIdHigherVersionFiltered"]=package.value("version").toString()=="1.0.0";
 checks["authenticatedCompatibleInstallOffered"]=package.value("storeEligible").toBool()&&package.value("signatureReady").toBool();
 QString error;checks["validSignedGeminiNappAccepted"]=store.verifyPackageBytes(bytes(fixtures.filePath("valid-gemini.napp")),package,&error);
 for(const QString &name:{"unsigned.napp","modified-payload.napp","modified-manifest.napp","bad-signature.napp","unknown-signer.napp","apollo-only.napp","arm64-only.napp","metadata-tampering.napp","embedded-attacker-key.napp","signed-hash-mismatch.napp","signed-app-identity-mismatch.napp","missing-platform.napp","missing-architecture.napp"}){
  const QByteArray data=bytes(fixtures.filePath(name));auto probe=package;probe["sha256"]=QString::fromLatin1(QCryptographicHash::hash(data,QCryptographicHash::Sha256).toHex());error.clear();checks[name+"Rejected"]=!store.verifyPackageBytes(data,probe,&error)&&!error.isEmpty();
 }
 checks["unsignedCatalogRejected"]=catalog("index-unsigned.json").isEmpty();
 checks["modifiedCatalogRejected"]=catalog("index-modified.json").isEmpty();catalog("index.json");
 store.m_installedRegistry["gemini-trust-test"]=QVariantMap{{"platforms",QStringList{"apollo"}},{"architectures",QStringList{"aarch64"}},{"version","99.0.0"}};store.rebuildCatalog();
 const auto foreign=store.packageById("gemini-trust-test");checks["foreignInstalledVersionNotConfused"]=foreign.value("installedVersion").toString().isEmpty()&&!foreign.value("updateEligible").toBool()&&!foreign.value("storeEligible").toBool();
 store.m_installedRegistry.clear();store.rebuildCatalog();
 checks["unsignedManualInstallDenied"]=!store.installLocalPackage(fixtures.filePath("unsigned.napp"));
 checks["validSignedPackageInstalls"]=operation(store,[&]{return store.installPackage("gemini-trust-test");});
 checks["installedGeminiVersionRecognized"]=store.installedVersion("gemini-trust-test")=="1.0.0";
 catalog("index-update.json");checks["authenticatedCompatibleNewerUpdateOffered"]=store.packageById("gemini-trust-test").value("updateEligible").toBool();
 checks["signedGeminiUpdateInstalls"]=operation(store,[&]{return store.updatePackage("gemini-trust-test");});
 checks["updatedGeminiVersionRecognized"]=store.installedVersion("gemini-trust-test")=="1.1.0";
 checks["signedApplicationRollbackCompletes"]=operation(store,[&]{return store.rollbackPackage("gemini-trust-test");});
 checks["rollbackRestoresPriorVersion"]=store.installedVersion("gemini-trust-test")=="1.0.0";
 // The fixture owns only this synthetic ID in the disposable VM.
 checks["applicationUninstallCompletes"]=operation(store,[&]{return store.uninstallPackage("gemini-trust-test");});
 checks["applicationRegistryRemoved"]=!store.isInstalled("gemini-trust-test");
 bool passed=true;for(auto it=checks.begin();it!=checks.end();++it)passed=passed&&it.value().toBool();
 QFile repos(repoPath);if(repos.open(QIODevice::WriteOnly)){repos.write(originalRepos);repos.close();}
 QFile registry(registryPath);if(registry.open(QIODevice::WriteOnly)){registry.write(originalRegistry);registry.close();}
 QJsonObject report{{"passed",passed},{"checks",checks},{"productionAppStoreManager",true},{"usesInstalledSharedTrustRoot",true},{"privateKeyUsedByProbe",false},{"lastStatus",store.statusMessage()},{"lastError",store.lastError()}};
 fprintf(stdout,"%s\n",QJsonDocument(report).toJson(QJsonDocument::Compact).constData());return passed?0:1;
}
