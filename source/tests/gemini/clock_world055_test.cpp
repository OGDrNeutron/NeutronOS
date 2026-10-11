#include <QtTest>
#include <QTemporaryDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QTimeZone>
#include <QProcess>
#include <QUuid>
#include <QJsonObject>
#include <cmath>
#include "ClockSettingsManager.h"
class ClockWorldTest: public QObject {
 Q_OBJECT
 QTemporaryDir directory;
 QString originalRoot;
private slots:
 void initTestCase(){QVERIFY(directory.isValid());originalRoot=qEnvironmentVariable("NEUTRONOS_ROOT");}
 void init(){qputenv("NEUTRONOS_ROOT",(directory.path()+"/case-"+QUuid::createUuid().toString(QUuid::WithoutBraces)).toUtf8());}
 void cleanupTestCase(){qputenv("NEUTRONOS_ROOT",originalRoot.toUtf8());}
 void ianaRegionsAndCoordinates(){
  ClockSettingsManager manager;const auto regions=manager.worldClockRegions();QVERIFY(regions.size()>=13);
  for(const auto &row:regions){const auto region=row.toMap();QVERIFY(QTimeZone(region["timezone"].toString().toUtf8()).isValid());QVERIFY(region["coordinatesAvailable"].toBool());QVERIFY(std::abs(region["latitude"].toDouble())<=90);QVERIFY(std::abs(region["longitude"].toDouble())<=180);}
  auto newYork=manager.worldClockRegion("America/New_York");QVERIFY(std::abs(newYork["latitude"].toDouble()-40.714)<.1);QVERIFY(std::abs(newYork["longitude"].toDouble()+74.006)<.1);
 }
 void regionalTimeDSTFractionalOffsetsAndDates(){
  ClockSettingsManager manager;auto summer=QDateTime::fromString("2026-07-01T02:30:00Z",Qt::ISODate);auto winter=QDateTime::fromString("2026-01-01T02:30:00Z",Qt::ISODate);
  QCOMPARE(manager.worldClockDisplay("America/New_York",summer)["offsetSeconds"].toInt(),-14400);
  QCOMPARE(manager.worldClockDisplay("America/New_York",winter)["offsetSeconds"].toInt(),-18000);
  QCOMPARE(manager.worldClockDisplay("Asia/Kathmandu",summer)["offsetSeconds"].toInt(),20700);
  QCOMPARE(manager.worldClockDisplay("Asia/Kolkata",summer)["offsetSeconds"].toInt(),19800);
  QCOMPARE(manager.worldClockDisplay("Australia/Adelaide",summer)["offsetSeconds"].toInt(),34200);
  QCOMPARE(manager.worldClockDisplay("Australia/Adelaide",winter)["offsetSeconds"].toInt(),37800);
  QVERIFY(manager.worldClockDisplay("America/New_York",summer)["date"].toString().contains("Jun 30"));
  auto midday=QDateTime::fromString("2026-07-01T16:59:00Z",Qt::ISODate);auto display=manager.worldClockDisplay("America/New_York",midday);QCOMPARE(display["time"].toString(),QString("12:59"));QCOMPARE(display["period"].toString(),QString("PM"));
  auto evening=manager.worldClockDisplay("Asia/Tokyo",QDateTime::fromString("2026-03-20T12:00:00Z",Qt::ISODate));QCOMPARE(evening["time"].toString(),QString("9:00"));QCOMPARE(evening["period"].toString(),QString("PM"));
  QVERIFY(manager.setUse24Hour(true));display=manager.worldClockDisplay("Asia/Kathmandu",midday);QCOMPARE(display["time"].toString(),QString("22:44"));QVERIFY(display["period"].toString().isEmpty());
  QCOMPARE(display["utcMs"].toLongLong(),midday.toMSecsSinceEpoch());
 }
 void solarUTCSeasonsAndContinuity(){
  ClockSettingsManager manager;auto noon=QDateTime::fromString("2026-03-20T12:00:00Z",Qt::ISODate);auto equinox=manager.solarPosition(noon);QVERIFY(std::abs(equinox["subsolarLatitude"].toDouble())<1);QVERIFY(std::abs(equinox["subsolarLongitude"].toDouble())<5);
  auto june=manager.solarPosition(QDateTime::fromString("2026-06-21T12:00:00Z",Qt::ISODate));QVERIFY(std::abs(june["subsolarLatitude"].toDouble()-23.44)<.5);
  auto december=manager.solarPosition(QDateTime::fromString("2026-12-21T12:00:00Z",Qt::ISODate));QVERIFY(std::abs(december["subsolarLatitude"].toDouble()+23.44)<.5);
  double length=0;for(const auto key:{"x","y","z"})length+=std::pow(equinox[key].toDouble(),2);QVERIFY(std::abs(length-1)<1e-10);
  QCOMPARE(manager.solarPosition(noon.toTimeZone(QTimeZone("Asia/Kathmandu"))),equinox);
  auto later=manager.solarPosition(noon.addSecs(60));QVERIFY(std::abs(later["subsolarLongitude"].toDouble()-equinox["subsolarLongitude"].toDouble()+.25)<.003);
  QVERIFY(manager.solarPosition(QDateTime()).isEmpty());
 }
 void visibilityAtomicPersistenceAndPermissions(){
  ClockSettingsManager manager;QVERIFY(manager.lockscreenClockVisible());QVERIFY(manager.lockscreenWelcomeVisible());QSignalSpy clock(&manager,&ClockSettingsManager::lockscreenClockVisibleChanged),welcome(&manager,&ClockSettingsManager::lockscreenWelcomeVisibleChanged);
  QVERIFY(manager.setLockscreenClockVisible(false));QVERIFY(manager.setLockscreenWelcomeVisible(false));QCOMPARE(clock.size(),1);QCOMPARE(welcome.size(),1);
  ClockSettingsManager reloaded;QVERIFY(!reloaded.lockscreenClockVisible());QVERIFY(!reloaded.lockscreenWelcomeVisible());
  QFileInfo file(qEnvironmentVariable("NEUTRONOS_ROOT")+"/state/settings/clock.json");QVERIFY(file.exists());QVERIFY(!(file.permissions()&(QFileDevice::WriteGroup|QFileDevice::WriteOther|QFileDevice::ReadGroup|QFileDevice::ReadOther)));
  const QString bad=directory.path()+"/not-a-directory";QFile blocker(bad);QVERIFY(blocker.open(QIODevice::WriteOnly));blocker.close();qputenv("NEUTRONOS_ROOT",bad.toUtf8());ClockSettingsManager blocked;QVERIFY(!blocked.setLockscreenClockVisible(false));QVERIFY(blocked.lockscreenClockVisible());
 }
 void detailsVisibilityPersistenceAndFailure(){
  { ClockSettingsManager manager; QVERIFY(manager.lockscreenDetailsVisible());
    QSignalSpy changed(&manager,&ClockSettingsManager::lockscreenDetailsVisibleChanged);
    QVERIFY(manager.setLockscreenDetailsVisible(false)); QCOMPARE(changed.size(),1);
    QVERIFY(manager.setLockscreenDetailsVisible(false)); QCOMPARE(changed.size(),1);
    QVERIFY(manager.setLockscreenWelcomeVisible(false)); }
  { ClockSettingsManager reloaded; QVERIFY(!reloaded.lockscreenDetailsVisible());
    QVERIFY(reloaded.setLockscreenDetailsVisible(true)); }
  ClockSettingsManager visibleAgain; QVERIFY(visibleAgain.lockscreenDetailsVisible());
  const QString bad=directory.path()+"/details-blocker"; QFile blocker(bad);
  QVERIFY(blocker.open(QIODevice::WriteOnly)); blocker.close(); qputenv("NEUTRONOS_ROOT",bad.toUtf8());
  ClockSettingsManager blocked; QSignalSpy changed(&blocked,&ClockSettingsManager::lockscreenDetailsVisibleChanged);
  QVERIFY(!blocked.setLockscreenDetailsVisible(false)); QVERIFY(blocked.lockscreenDetailsVisible()); QCOMPARE(changed.size(),0);
 }
 void untrustedVisibilityFileIgnored(){
  ClockSettingsManager manager;QVERIFY(manager.setLockscreenClockVisible(false));QString path=qEnvironmentVariable("NEUTRONOS_ROOT")+"/state/settings/clock.json";QVERIFY(QFile::setPermissions(path,QFileDevice::ReadOwner|QFileDevice::WriteOwner|QFileDevice::WriteOther));ClockSettingsManager reloaded;QVERIFY(reloaded.lockscreenClockVisible());
 }
 void unauthenticatedRequestsCannotMutateTimezone(){
  ClockSettingsManager manager;const QString before=manager.timezone();const QString target=before=="Asia/Kathmandu"?"Europe/London":"Asia/Kathmandu";
  QSignalSpy operations(&manager,&ClockSettingsManager::operationStarted);QVERIFY(!manager.requestLockscreenTimezone(target));QCOMPARE(manager.timezone(),before);
  QVERIFY(manager.metaObject()->indexOfMethod("completeLockscreenTimezoneAuthorization(QString)")<0);
  QVariantMap identity{{"username","gemini-test"},{"busy",false},{"lockedOut",false}};manager.setLockscreenAuthenticationProvider([&](){return identity;});
  QVERIFY(!manager.requestLockscreenTimezone("../etc/passwd"));QVERIFY(!manager.requestLockscreenTimezone(before));
  identity["busy"]=true;QVERIFY(!manager.requestLockscreenTimezone(target));identity["busy"]=false;identity["lockedOut"]=true;QVERIFY(!manager.requestLockscreenTimezone(target));identity["lockedOut"]=false;
  QVERIFY(manager.requestLockscreenTimezone(target));QVERIFY(manager.timezoneAuthorizationPending());QCOMPARE(manager.timezone(),before);QVERIFY(!manager.operationBusy());
  manager.completeLockscreenTimezoneAuthorization("wrong-user");QVERIFY(!manager.timezoneAuthorizationPending());QCOMPARE(operations.size(),0);QCOMPARE(manager.timezone(),before);
  QVERIFY(manager.requestLockscreenTimezone(target));manager.cancelLockscreenTimezoneRequest();manager.completeLockscreenTimezoneAuthorization("gemini-test");QCOMPARE(operations.size(),0);QCOMPARE(manager.timezone(),before);
  QVERIFY(manager.requestLockscreenTimezone(target));QVERIFY(manager.setLockscreenClockVisible(false));QVERIFY(!manager.timezoneAuthorizationPending());
 }
 void authorizedTimezoneApplyDisposableVMOnly(){
  if(!qEnvironmentVariableIsSet("GEMINI_DISPOSABLE_VM")||!QFile::exists("/etc/systemd/system/gemini-private-console.service"))QSKIP("System mutation is restricted to the disposable Gemini VM");
  ClockSettingsManager manager;const QString target=manager.timezone()=="Asia/Kathmandu"?"Europe/London":"Asia/Kathmandu";
  QProcess ntpBefore;ntpBefore.start("/usr/bin/timedatectl",{"show","-p","NTP","--value"});QVERIFY(ntpBefore.waitForFinished());const auto ntp=ntpBefore.readAllStandardOutput();
  manager.setLockscreenAuthenticationProvider([](){return QVariantMap{{"username","gemini-test"},{"busy",false},{"lockedOut",false}};});
  QSignalSpy finished(&manager,&ClockSettingsManager::operationFinished);QVERIFY(manager.requestLockscreenTimezone(target));QElapsedTimer elapsed;elapsed.start();const auto utc=QDateTime::currentDateTimeUtc();manager.completeLockscreenTimezoneAuthorization("gemini-test");QVERIFY(finished.wait(20000));QVERIFY2(finished.last()[1].toBool(),qPrintable(manager.worldClockStatus()));QCOMPARE(manager.timezone(),target);
  QProcess verify;verify.start("/usr/bin/timedatectl",{"show","-p","Timezone","--value"});QVERIFY(verify.waitForFinished());QCOMPARE(QString::fromUtf8(verify.readAllStandardOutput()).trimmed(),target);
  QProcess ntpAfter;ntpAfter.start("/usr/bin/timedatectl",{"show","-p","NTP","--value"});QVERIFY(ntpAfter.waitForFinished());QCOMPARE(ntpAfter.readAllStandardOutput(),ntp);QVERIFY(std::abs(utc.msecsTo(QDateTime::currentDateTimeUtc())-elapsed.elapsed())<2000);
  QFile report("/tmp/gemini-world-timezone-applied.json");QVERIFY(report.open(QIODevice::WriteOnly));report.write(QJsonDocument(QJsonObject{{"passed",true},{"timezone",target},{"NTPUnchanged",true},{"UTCClockUnchanged",true},{"helperVerifiedAsDisplayUser",true}}).toJson());
 }
};
QTEST_GUILESS_MAIN(ClockWorldTest)
#include "clock_world055_test.moc"
