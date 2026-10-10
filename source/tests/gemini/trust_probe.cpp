#include "UpdateRecoveryManager.h"
#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>
#include <functional>
static bool operation(UpdateRecoveryManager &manager,const QString &name,const std::function<bool()> &start){
 QEventLoop loop;bool ok=false,finished=false;
 auto connection=QObject::connect(&manager,&UpdateRecoveryManager::operationFinished,&loop,[&](const QString &op,bool success,const QString &){if(op==name){ok=success;finished=true;loop.quit();}});
 bool began=start();if(began&&!finished){QTimer::singleShot(45000,&loop,&QEventLoop::quit);loop.exec();}
 QObject::disconnect(connection);return began&&finished&&ok;
}
int main(int argc,char **argv){
 QCoreApplication app(argc,argv);if(argc!=2)return 2;QDir fixtures(QString::fromLocal8Bit(argv[1]));QTemporaryDir root;if(!root.isValid())return 3;
 qputenv("NEUTRONOS_STATE_DIR",(root.path()+"/state").toUtf8());QDir().mkpath(root.path()+"/config");QFile version(root.path()+"/config/version.json");if(!version.open(QIODevice::WriteOnly))return 4;version.write("{\"version\":\"0.5.4\"}");version.close();
 UpdateRecoveryManager manager(root.path(),nullptr);QJsonObject results;
 auto check=[&](const QString &name){manager.setManifestUrl(QUrl::fromLocalFile(fixtures.filePath(name)).toString());return operation(manager,"check-update",[&]{return manager.checkForUpdates("mainline");});};
 results["validSignedManifestAccepted"]=check("valid-envelope.json")&&manager.manifestVerified()&&manager.updateAvailable();
 results["payloadHashVerifiedBeforeReady"]=operation(manager,"download-update",[&]{return manager.downloadAvailableUpdate();})&&manager.packageVerified();
 for(const QString &name:{"unsigned-envelope.json","bad-signature-envelope.json","unknown-envelope.json","manifest-disagreement-envelope.json"})results[name+"Rejected"]=!check(name)&&!manager.manifestVerified();
 results["signedHashMismatchRejected"]=check("hash-mismatch-envelope.json")&&!operation(manager,"download-update",[&]{return manager.downloadAvailableUpdate();})&&!manager.packageVerified();
 bool passed=true;for(auto it=results.begin();it!=results.end();++it)passed=passed&&it.value().toBool();
 QJsonObject report{{"passed",passed},{"checks",results},{"productionUpdateManager",true},{"usesInstalledTrustRoot",true},{"privateKeyUsedByProbe",false}};
 fprintf(stdout,"%s\n",QJsonDocument(report).toJson(QJsonDocument::Compact).constData());return passed?0:1;
}
