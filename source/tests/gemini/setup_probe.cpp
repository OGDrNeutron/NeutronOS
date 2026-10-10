#include "SetupWizardManager.h"
#include <QCoreApplication>
#include <QTextStream>
int main(int argc,char **argv) {
    QCoreApplication app(argc,argv); SetupWizardManager manager("/opt/neutronos"); manager.refresh();
    const QString mode=app.arguments().value(1);
    if(mode=="help") {
        for(int i=1;i<=4;i++) {
            SetupWizardManager restored("/opt/neutronos");
            const auto result=restored.registerAppOpen("fixture","gemini-games");
            if(result.value("count").toInt()!=qMin(i,3) || result.value("show").toBool()!=(i<=3)) return 20+i;
            SetupWizardManager reread("/opt/neutronos");
            if(reread.appHelpCount("fixture","gemini-games")!=qMin(i,3)) return 30+i;
        }
    } else if(mode=="factory") {
        if(manager.domainStatus("timezone")=="configured") return 2;
        if(!manager.applyRegion("America/New_York","en_US.UTF-8","us")) return 3;
        if(manager.domainStatus("timezone")!="configured") return 4;
        SetupWizardManager restored("/opt/neutronos"); restored.refresh();
        if(restored.domainStatus("timezone")!="configured") return 5;
    } else if(mode=="controller") {
        if(!manager.confirmControllerRegistration()) return 6;
        manager.rememberUsbController("Test","/dev/input/event0");
        if(!manager.controllerPaired() || manager.domainStatus("controller")!="configured") return 7;
        SetupWizardManager restored("/opt/neutronos"); restored.refresh(); if(!restored.controllerPaired()) return 8;
    } else if(mode=="controller-reject") {
        if(manager.confirmControllerRegistration()) return 9;
    } else if(mode=="finalize-ssh-on" || mode=="finalize-ssh-off") {
        // The disposable guest already has a real human account and its
        // synthetic, valid controller-combo credential. Exercise the actual
        // backend preference call, domain checks and completion persistence.
        if(!manager.resetSetupForNextBoot() || !manager.setupRequired()) return 11;
        if(!manager.applyRegion("America/New_York","en_US.UTF-8","us")) return 12;
        QVariantMap prefs{{"securityProfile","default"},{"performancePreference","Normal"},
                          {"sshEnabled",mode=="finalize-ssh-on"},{"remoteControllerEnabled",true}};
        if(!manager.savePreferences(prefs) || !manager.completeSetup()) {
            QTextStream(stderr)<<manager.lastError()<<Qt::endl; return 13;
        }
        if(!manager.acknowledgeLoginInstructions()) return 14;
        SetupWizardManager restored("/opt/neutronos"); restored.refresh();
        if(restored.setupRequired() || !restored.setupComplete()) return 15;
    } else return 10;
    QTextStream(stdout)<<"GEMINI_SETUP_PROBE_PASS "<<mode<<Qt::endl; return 0;
}
