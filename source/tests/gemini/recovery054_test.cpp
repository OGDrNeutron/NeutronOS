#include <QtTest>
#include <QTemporaryDir>
#include <QFile>
#include "RecoveryModeManager.h"
class Recovery054Test:public QObject {
 Q_OBJECT
private slots:
 void realProcessNavigationAndSplitProgress(){
  QTemporaryDir temp;QVERIFY(temp.isValid());
  auto write=[&](QString name,QByteArray content){QFile file(temp.filePath(name));QVERIFY(file.open(QIODevice::WriteOnly));file.write(content);file.close();file.setPermissions(QFile::ReadOwner|QFile::WriteOwner|QFile::ExeOwner);};
  write("sudo", "#!/bin/sh\nshift\nexec \"$@\"\n");
  write("helper",R"SH(#!/bin/sh
case "$1" in
recovery-status) printf '%s\n' '{"active":true,"mode":"BACKUP_RESTORE","reason":"Test transaction","recoveryPoints":[{"path":"/safe/backup","name":"Verified fixture","verified":true,"size":4096,"profile":"CONFIG"}]}' ;;
recovery-apply-backup) printf 'PROG'; sleep .1; printf 'RESS:55:Restoring configu'; sleep .1; printf 'ration\n'; sleep 2; printf 'PROGRESS:94:Finalizing\n'; sleep .1; printf 'PROGRESS:100:Restored\n' ;;
backup-verify) printf 'Verified\n' ;;
backup-delete) printf 'Deleted\n' ;;
*) exit 1 ;;
esac
)SH");
  qputenv("NEUTRONOS_RECOVERY_SUDO",temp.filePath("sudo").toUtf8());qputenv("NEUTRONOS_RECOVERY_HELPER",temp.filePath("helper").toUtf8());
  RecoveryModeManager manager;
  QTRY_COMPARE(manager.view(),QString("landing"));QCOMPARE(manager.recoveryPoints().size(),1);
  manager.handleAction("primary");QCOMPARE(manager.view(),QString("menu"));
  manager.handleAction("down");QCOMPARE(manager.menuIndex(),1);manager.handleAction("primary");QCOMPARE(manager.view(),QString("unavailable"));QVERIFY(!manager.busy());
  manager.handleAction("cancel");manager.selectIndex(3);manager.handleAction("primary");QCOMPARE(manager.view(),QString("manage"));
  manager.handleAction("secondary");QVERIFY(manager.armed());manager.handleAction("cancel");QVERIFY(!manager.armed());QCOMPARE(manager.view(),QString("manage"));
  manager.handleAction("primary");QTRY_VERIFY(!manager.busy());QVERIFY(manager.message().contains("verified"));
  manager.handleAction("cancel");manager.selectIndex(0);manager.handleAction("primary");QCOMPARE(manager.view(),QString("selection"));
  manager.handleAction("primary");QVERIFY(manager.armed());manager.handleAction("cancel");QVERIFY(!manager.armed());QCOMPARE(manager.view(),QString("selection"));
  manager.handleAction("primary");manager.handleAction("primary");QVERIFY(manager.busy());
  QTRY_COMPARE_WITH_TIMEOUT(manager.progress(),55,1500);QCOMPARE(manager.message(),QString("Restoring configuration"));
  manager.handleAction("cancel");QCOMPARE(manager.view(),QString("progress"));QVERIFY(manager.busy());
  QTRY_COMPARE(manager.view(),QString("success"));QCOMPARE(manager.progress(),100);
  qunsetenv("NEUTRONOS_RECOVERY_SUDO");qunsetenv("NEUTRONOS_RECOVERY_HELPER");
 }
};
QTEST_GUILESS_MAIN(Recovery054Test)
#include "recovery054_test.moc"
