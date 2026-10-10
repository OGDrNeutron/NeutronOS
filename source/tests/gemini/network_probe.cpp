#include "NetworkManager.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QElapsedTimer>
#include <QThread>
#include <QHostAddress>
#include <QTextStream>
#include <functional>
static bool waitFor(std::function<bool()> condition, int ms=45000) {
    QElapsedTimer t; t.start();
    while(t.elapsed()<ms) { QCoreApplication::processEvents(); if(condition()) return true; QThread::msleep(50); }
    return false;
}
int main(int argc, char **argv) {
    QCoreApplication app(argc,argv); NetworkManager nm;
    const QString mode=app.arguments().value(1,"status");
    if(!waitFor([&]{ nm.refreshStatus(); return nm.available() && !nm.interfaceName().isEmpty(); },15000)) return 2;
    if(mode=="scan") {
        bool finished=false, succeeded=false;
        QObject::connect(&nm,&NetworkManager::scanFinished,[&](bool ok){ finished=true; succeeded=ok; });
        if(!nm.requestScan() || !waitFor([&]{return finished && !nm.operationBusy();},90000)
            || !succeeded || !nm.lastError().isEmpty()) {
            QTextStream(stderr)<<"Scan failed: "<<nm.lastError()<<Qt::endl; return 3;
        }
    }
    if(mode=="connect") {
        if(!nm.connectToNetwork({{"ssid","GeminiRegression"},{"password","gemini-test-only-052"},{"security","WPA2"},{"remember",true}})) return 4;
        if(!waitFor([&]{return nm.connectionState()=="CONNECTED" && nm.connectedSsid()=="GeminiRegression" && !QHostAddress(nm.localIp()).isNull();},90000)) { QTextStream(stderr)<<nm.interfaceName()<<" "<<nm.connectionState()<<" "<<nm.lastError()<<Qt::endl; return 5; }
    }
    if(mode=="disconnect" && (!nm.disconnectCurrent() || !waitFor([&]{return nm.connectedSsid().isEmpty() && !nm.operationBusy();}))) return 6;
    QJsonObject out{{"interface",nm.interfaceName()},{"ssid",nm.connectedSsid()},{"state",nm.connectionState()},
        {"ip",nm.localIp()},{"error",nm.lastError()},{"wifi",nm.wifiEnabled()},
        {"hardware",nm.wirelessHardwareEnabled()},{"networks",QJsonArray::fromVariantList(nm.availableNetworks())},
        {"profiles",QJsonArray::fromVariantList(nm.savedNetworks())}};
    QTextStream(stdout)<<QJsonDocument(out).toJson(QJsonDocument::Compact)<<Qt::endl;
    return 0;
}
