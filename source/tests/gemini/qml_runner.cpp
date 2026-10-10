#include <QtQuickTest/quicktest.h>
#include <QtQml/qqml.h>
#include <QQmlEngine>
#include <QQmlContext>
#include "GeminiGeometry.h"
#include "ClockSettingsManager.h"
#include "ControllerReplay.h"
class GeminiTestSetup : public QObject {
    Q_OBJECT
public:
    GeminiTestSetup() { if (qEnvironmentVariableIsEmpty("QSG_RENDER_LOOP")) qputenv("QSG_RENDER_LOOP", "basic"); }
public slots:
    void qmlEngineAvailable(QQmlEngine *engine) {
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
