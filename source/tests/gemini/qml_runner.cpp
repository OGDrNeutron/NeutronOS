#include <QtQuickTest/quicktest.h>
#include <QtQml/qqml.h>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlNetworkAccessManagerFactory>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
class TestNetwork final:public QNetworkAccessManager {
protected:
 QNetworkReply *createRequest(Operation operation,const QNetworkRequest &input,QIODevice *data=nullptr) override {
  QNetworkRequest request(input);auto url=request.url();
  if(qEnvironmentVariableIsSet("GEMINI_CONTROLLER_FIXTURE")&&url.host()=="127.0.0.1"&&url.port()==48173){url.setPort(48174);request.setUrl(url);}
  return QNetworkAccessManager::createRequest(operation,request,data);
 }
};
class TestNetworkFactory final:public QQmlNetworkAccessManagerFactory {public:QNetworkAccessManager *create(QObject *parent) override {auto *manager=new TestNetwork;manager->setParent(parent);return manager;}};
#include "GeminiGeometry.h"
#include "ClockSettingsManager.h"
#include "ControllerReplay.h"
class GeminiTestSetup : public QObject {
    Q_OBJECT
public:
    GeminiTestSetup() { if (qEnvironmentVariableIsEmpty("QSG_RENDER_LOOP")) qputenv("QSG_RENDER_LOOP", "basic"); }
public slots:
    void qmlEngineAvailable(QQmlEngine *engine) {
        static TestNetworkFactory factory;engine->setNetworkAccessManagerFactory(&factory);
        auto *identity=new QObject(engine);identity->setProperty("activeUsername",qEnvironmentVariable("GEMINI_TEST_USERNAME"));engine->rootContext()->setContextProperty("securityManager",identity);
        engine->rootContext()->setContextProperty("worldClockTestBackend",new ClockSettingsManager(engine));
        engine->rootContext()->setContextProperty("controllerReplay",new ControllerReplay(engine));
    }
    void applicationAvailable() {
        qmlRegisterType<GeminiRingGeometry>("NeutronGemini",1,0,"GeminiRingGeometry");
        qmlRegisterType<GeminiFractureGeometry>("NeutronGemini",1,0,"GeminiFractureGeometry");
    }
};
QUICK_TEST_MAIN_WITH_SETUP(GeminiQmlRegression, GeminiTestSetup)
#include "qml_runner.moc"
