#include <QCoreApplication>
#include <QCursor>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

#include "BrowserManager.h"
#include "CaptureManager.h"
#include "ControllerManager.h"
#include "NotificationManager.h"

#ifndef NEUTRONOS_PROJECT_ROOT
#define NEUTRONOS_PROJECT_ROOT "/opt/neutronos"
#endif

int main(int argc, char *argv[])
{
    // Qt requires this before QGuiApplication for WebEngine Quick context sharing.
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);

    QCoreApplication::setApplicationName(QStringLiteral("NeutronBrowser"));
    QCoreApplication::setApplicationVersion(QStringLiteral("1.0.0-alpha"));
    QCoreApplication::setOrganizationName(QStringLiteral("DrNeutron"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("neutronos.local"));
    app.setOverrideCursor(Qt::BlankCursor);

    QString neutronRoot = qEnvironmentVariable("NEUTRONOS_ROOT").trimmed();
    if (neutronRoot.isEmpty())
        neutronRoot = QStringLiteral(NEUTRONOS_PROJECT_ROOT);
    neutronRoot = QDir::cleanPath(neutronRoot);

    BrowserManager browserManager(neutronRoot);
    NotificationManager notificationManager(neutronRoot);
    CaptureManager captureManager(neutronRoot, &notificationManager);
    ControllerManager controllerManager;
    controllerManager.setStickNavigationActionsEnabled(false);

    QQmlApplicationEngine engine;
    const QString qmlRoot = QDir(neutronRoot).filePath(QStringLiteral("qml"));
    engine.addImportPath(qmlRoot);
    engine.addImportPath(QDir(qmlRoot).filePath(QStringLiteral("components")));
    engine.addImportPath(QDir(qmlRoot).filePath(QStringLiteral("apps")));

    engine.rootContext()->setContextProperty(QStringLiteral("neutronRoot"), neutronRoot);
    engine.rootContext()->setContextProperty(QStringLiteral("neutronThemeRoot"),
        QDir(neutronRoot).filePath(QStringLiteral("themes/Default")));
    engine.rootContext()->setContextProperty(QStringLiteral("browserManager"), &browserManager);
    engine.rootContext()->setContextProperty(QStringLiteral("captureManager"), &captureManager);
    engine.rootContext()->setContextProperty(QStringLiteral("controllerManager"), &controllerManager);
    engine.rootContext()->setContextProperty(QStringLiteral("standaloneBrowser"), true);

    const QUrl source = QUrl::fromLocalFile(
        QDir(qmlRoot).filePath(QStringLiteral("apps/browser/Standalone.qml")));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [source](QObject *object, const QUrl &objectUrl) {
        if (!object && objectUrl == source)
            QCoreApplication::exit(2);
    }, Qt::QueuedConnection);
    engine.load(source);
    if (engine.rootObjects().isEmpty())
        return 2;
    return app.exec();
}
