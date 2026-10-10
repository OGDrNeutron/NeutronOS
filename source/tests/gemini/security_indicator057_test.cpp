#include "SecurityIndicatorSnapshot.h"
#include <QTest>
#include <QTemporaryDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <sys/stat.h>
class IndicatorTest:public QObject {
 Q_OBJECT
private slots:
 void authoritativeScoreAndFreshness(){
  const auto now=QDateTime::currentDateTimeUtc();
  auto state=[&](int score,qint64 offset){return QJsonDocument(QJsonObject{{"securityScore",score},{"heartbeat",now.addMSecs(offset).toString(Qt::ISODateWithMs)}}).toJson();};
  for(int score:{0,54,55,79,80,100}){auto v=SecurityIndicatorSnapshot::parse(state(score,-5000),now);QVERIFY(v.online);QCOMPARE(v.score,score);}
  for(auto data:{state(100,-20001),state(100,1000),state(-1,0),state(101,0),QByteArray("{}"),QByteArray("broken")}){auto v=SecurityIndicatorSnapshot::parse(data,now);QVERIFY(!v.online);QCOMPARE(v.score,-1);}
 }
 void protectedFileFailures(){
  QTemporaryDir d;auto now=QDateTime::currentDateTimeUtc();auto path=d.path()+"/state.json";
  QFile f(path);QVERIFY(f.open(QIODevice::WriteOnly));f.write(QJsonDocument(QJsonObject{{"securityScore",90},{"heartbeat",now.toString(Qt::ISODateWithMs)}}).toJson());f.close();
  QVERIFY(!SecurityIndicatorSnapshot::read(d.path()+"/missing",now).online);
  QVERIFY(QFile::link(path,d.path()+"/linked"));QVERIFY(!SecurityIndicatorSnapshot::read(d.path()+"/linked",now).online);
  const auto fifo=QFile::encodeName(d.path()+"/fifo");QCOMPARE(mkfifo(fifo.constData(),0600),0);QVERIFY(!SecurityIndicatorSnapshot::read(QString::fromUtf8(fifo),now).online);
  QVERIFY(f.setPermissions(QFileDevice::ReadOwner|QFileDevice::WriteOwner|QFileDevice::WriteOther));QVERIFY(!SecurityIndicatorSnapshot::read(path,now).online);
  if(geteuid()==0){QVERIFY(f.setPermissions(QFileDevice::ReadOwner|QFileDevice::WriteOwner|QFileDevice::ReadGroup|QFileDevice::ReadOther));QVERIFY(SecurityIndicatorSnapshot::read(path,now).online);}
 }
};
QTEST_GUILESS_MAIN(IndicatorTest)
#include "security_indicator057_test.moc"
