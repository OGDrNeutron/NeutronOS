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
#include <sodium.h>

#include <cstdlib>

namespace {
void require(bool condition, const char *message) { if (!condition) { qCritical("%s", message); std::exit(1); } }

QByteArray envelope(const QByteArray &signedPayload, const QByteArray &secretKey, bool corrupt)
{
    QByteArray signature(crypto_sign_BYTES, Qt::Uninitialized);
    crypto_sign_detached(reinterpret_cast<unsigned char *>(signature.data()), nullptr,
                         reinterpret_cast<const unsigned char *>(signedPayload.constData()), signedPayload.size(),
                         reinterpret_cast<const unsigned char *>(secretKey.constData()));
    if (corrupt) signature[0] = static_cast<char>(signature[0] ^ 0x7f);
    return QJsonDocument(QJsonObject{{"format","neutronos.update-manifest.v2"},
        {"signedPayload",QString::fromLatin1(signedPayload.toBase64())},
        {"signature",QString::fromLatin1(signature.toBase64())}}).toJson(QJsonDocument::Compact);
}

bool check(UpdateRecoveryManager &manager, const QString &path)
{
    manager.setManifestUrl(QUrl::fromLocalFile(path).toString());
    QEventLoop loop; bool success=false;
    QObject::connect(&manager,&UpdateRecoveryManager::operationFinished,&loop,
                     [&](const QString &name,bool ok,const QString &message){
        if(name=="check-update"){
            if (!ok) qWarning("check-update failed: %s", qPrintable(message));
            success=ok;
            loop.quit();
        }
    });
    require(manager.checkForUpdates("beta"), "manifest check should start");
    QTimer::singleShot(5000,&loop,&QEventLoop::quit);loop.exec();return success;
}
}

int main(int argc,char **argv)
{
    QCoreApplication app(argc,argv);require(sodium_init()>=0,"libsodium init");QTemporaryDir root;require(root.isValid(),"temporary root");
    qputenv("NEUTRONOS_STATE_DIR", (root.path() + "/state").toUtf8());
    QDir().mkpath(root.path()+"/config");
    QFile version(root.path()+"/config/version.json");require(version.open(QIODevice::WriteOnly),"version open");version.write("{\"version\":\"1.0.0-beta.1\"}\n");version.close();
    QByteArray publicKey(crypto_sign_PUBLICKEYBYTES,Qt::Uninitialized),secretKey(crypto_sign_SECRETKEYBYTES,Qt::Uninitialized);crypto_sign_keypair(reinterpret_cast<unsigned char *>(publicKey.data()),reinterpret_cast<unsigned char *>(secretKey.data()));
    QFile key(root.path()+"/config/update-public-key");require(key.open(QIODevice::WriteOnly),"key open");key.write(publicKey.toBase64());key.close();
    const QJsonObject signedObject{{"product","NeutronOS"},{"codename","Apollo"},{"version","1.0.0-beta.2"},{"channel","beta"},{"architecture","arm64"},{"artifact",QJsonObject{{"url","file:///tmp/test.nosupdate"},{"sha256",QString(64,'a')},{"size",128}}},{"releaseNotes","Test"},{"releaseTimestamp","2026-08-10T00:00:00Z"},{"minimumCompatibleVersion","1.0.0-beta.1"},{"minimumUpdaterVersion","1.0.0"},{"updateFormatVersion",2},{"rollbackCompatible",true}};
    const QByteArray payload=QJsonDocument(signedObject).toJson(QJsonDocument::Compact);
    QFile good(root.path()+"/good.json");require(good.open(QIODevice::WriteOnly),"good open");good.write(envelope(payload,secretKey,false));good.close();
    UpdateRecoveryManager manager(root.path(),nullptr,nullptr,key.fileName());require(check(manager,good.fileName()),"valid signed manifest should pass");require(manager.manifestVerified(),"manifest verified state");require(manager.updateAvailable(),"semantic prerelease ordering");
    QFile bad(root.path()+"/bad.json");require(bad.open(QIODevice::WriteOnly),"bad open");bad.write(envelope(payload,secretKey,true));bad.close();require(!check(manager,bad.fileName()),"invalid signature must fail");require(!manager.manifestVerified(),"invalid signature must clear verified state");
    QJsonObject wrong=signedObject;wrong["architecture"]="x86_64";QFile arch(root.path()+"/arch.json");require(arch.open(QIODevice::WriteOnly),"arch open");arch.write(envelope(QJsonDocument(wrong).toJson(QJsonDocument::Compact),secretKey,false));arch.close();require(!check(manager,arch.fileName()),"wrong architecture must fail");
    return 0;
}
