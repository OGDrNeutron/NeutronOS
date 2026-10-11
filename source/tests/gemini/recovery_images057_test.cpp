#include <QtTest>
#include <QTemporaryDir>
#include <QFile>
#include "RecoveryModeManager.h"
class RecoveryImages057Test: public QObject {
 Q_OBJECT
private slots:
 void imageSelectionKeepsOverlaySeparateAndConfirmsExactTarget(){
  QTemporaryDir temp;QVERIFY(temp.isValid());auto write=[&](QString name,QByteArray data){QFile f(temp.filePath(name));QVERIFY(f.open(QIODevice::WriteOnly));f.write(data);f.close();f.setPermissions(QFile::ReadOwner|QFile::WriteOwner|QFile::ExeOwner);};
  write("sudo","#!/bin/sh\nshift\nexec \"$@\"\n");
  write("helper",R"SH(#!/bin/sh
case "$1" in
recovery-status) printf '%s\n' '{"active":true,"mode":"RECOVERY","images":[{"path":"recovery-images/Gemini/0.5.7/r2/metadata.json","name":"Gemini 0.5.7","version":"0.5.7","verified":true,"kind":"image","size":900000000}],"recoveryPoints":[{"path":"/safe/backup","name":"Unchanged backup","verified":true}]}' ;;
image-download) printf 'PROGRESS:70:Downloading image\n'; sleep .1; printf 'PROGRESS:100:Verified image\n' ;;
image-targets) printf '%s\n' '{"targets":[{"path":"/dev/vdc","name":"Blank Test Disk RECOVERYTARGET057","size":25769803776,"fingerprint":"exact-target-identity","verified":true,"kind":"image-target"}]}' ;;
image-install) test "$2" = 'recovery-images/Gemini/0.5.7/r2/metadata.json' && test "$3" = '/dev/vdc' && test "$4" = 'exact-target-identity' || exit 2; printf 'PROGRESS:100:Image verified on offline target\n' ;;
*) exit 1 ;;
esac
)SH");
  qputenv("NEUTRONOS_RECOVERY_SUDO",temp.filePath("sudo").toUtf8());qputenv("NEUTRONOS_RECOVERY_HELPER",temp.filePath("helper").toUtf8());
  RecoveryModeManager manager;QTRY_COMPARE(manager.view(),QString("landing"));QCOMPARE(manager.recoveryPoints().size(),1);
  manager.handleAction("primary");manager.selectIndex(0);manager.handleAction("primary");QCOMPARE(manager.recoveryPoints().first().toMap().value("kind").toString(),QString("backup"));
  manager.handleAction("cancel");manager.selectIndex(2);manager.handleAction("primary");QCOMPARE(manager.recoveryPoints().first().toMap().value("kind").toString(),QString("image"));
  manager.handleAction("primary");QVERIFY(manager.armed());manager.handleAction("primary");QTRY_COMPARE(manager.recoveryPoints().first().toMap().value("kind").toString(),QString("image-target"));QTRY_VERIFY(!manager.busy());
  manager.handleAction("primary");QVERIFY(manager.armed());QVERIFY(manager.message().contains("RECOVERYTARGET057"));QVERIFY(manager.message().contains("25769803776"));
  manager.handleAction("cancel");QVERIFY(!manager.armed());manager.handleAction("primary");manager.handleAction("primary");QTRY_COMPARE(manager.view(),QString("success"));QCOMPARE(manager.progress(),100);
  qunsetenv("NEUTRONOS_RECOVERY_SUDO");qunsetenv("NEUTRONOS_RECOVERY_HELPER");
 }
};
QTEST_GUILESS_MAIN(RecoveryImages057Test)
#include "recovery_images057_test.moc"
