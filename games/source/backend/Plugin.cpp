#include "GeminiGamesBackend.h"
#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include <QQmlContext>
#include <QFileInfo>
#include <QDir>
#include <dlfcn.h>
static QString packageManagerPath(){
    Dl_info info{};
    if(!dladdr(reinterpret_cast<const void*>(&packageManagerPath),&info)||!info.dli_fname)return {};
    QDir module(QFileInfo(QString::fromLocal8Bit(info.dli_fname)).absolutePath());
    return QFileInfo(module.filePath("../../management/games_manager.py")).canonicalFilePath();
}
class GeminiGamesPlugin final:public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        const QString manager=packageManagerPath();
        qmlRegisterSingletonType<GeminiGames::GeminiGamesBackend>(uri,1,0,"GamesBackend",[manager](QQmlEngine *engine,QJSEngine*)->QObject*{
            auto *backend=new GeminiGames::GeminiGamesBackend;
            backend->setSessionIdentity(engine->rootContext()->contextProperty("securityManager").value<QObject*>());
            backend->setManagerProgram(manager);
            return backend;
        });
    }
};
#include "Plugin.moc"
