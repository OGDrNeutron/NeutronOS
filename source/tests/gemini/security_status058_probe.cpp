#include <QCoreApplication>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include "SecurityCoreManager.h"
int main(int argc,char**argv){QCoreApplication app(argc,argv);SecurityCoreManager manager("/opt/neutronos",nullptr);QTimer::singleShot(2500,&app,[&]{QJsonObject result{{"online",manager.indicatorOnline()},{"indicatorScore",manager.indicatorScore()},{"securityScore",manager.securityScore()},{"authenticatedSessionOnline",manager.daemonOnline()}};fprintf(stdout,"%s\n",QJsonDocument(result).toJson(QJsonDocument::Compact).constData());app.quit();});return app.exec();}
