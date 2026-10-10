#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlComponent>
#include <QDebug>
int main(int argc,char**argv){
 QGuiApplication app(argc,argv);QQmlEngine engine;QObject session;session.setProperty("activeUsername",QString("root"));engine.rootContext()->setContextProperty("securityManager",&session);
 const QString path=QString::fromLocal8Bit(argv[1]);QQmlComponent component(&engine);
 component.setData(("import QtQuick\nimport \""+QUrl::fromLocalFile(path).toString()+"\" as Native\nItem { property var backend: Native.GamesBackend }").toUtf8(),QUrl::fromLocalFile(path+"/../../Probe.qml"));
 auto*root=component.create();if(!root){qCritical()<<component.errors();return 1;}
 QObject*backend=root->property("backend").value<QObject*>();bool result=true;
 if(!backend||!QMetaObject::invokeMethod(backend,"initialize",Q_RETURN_ARG(bool,result))||result){qCritical()<<"Unvalidated account was not rejected";return 2;}
 qInfo()<<"Package-local precompiled Games plugin loads and refuses root personal storage";
 delete root;return 0;
}
