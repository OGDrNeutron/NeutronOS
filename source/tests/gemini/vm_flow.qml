import QtQuick
QtObject {
    id:flow
    property var wizard:null
    property var main:null
    property var login:null
    property int phase:0
    onPhaseChanged:console.info("GEMINI_FLOW_PHASE",phase)
    property double started:Date.now()
    property var steps:[]
    property var assertions:[]
    property real hiddenLoginPulse:0
    property bool resumedLogin:false
    property var fracturePerformance:({})
    property var unlockPerformance:({})
    property var unlockPreparationPerformance:({})
    property bool transitionPerfStarted:false
    property var unlockStages:[]
    property bool wrongTested:false
    property double wrongFeedbackWaitStarted:0
    property real fractureTriggerMs:0
    property var idlePerformance:({})
    property var lockIdlePerformance:({})
    property var networkModal:null
    property int fractureFrame:0
    property double phaseStarted:Date.now()
    function find(item,name){
        if(!item)return null
        if(item.objectName===name)return item
        var children=item.children||[]
        for(var i=0;i<children.length;i++){var hit=find(children[i],name);if(hit)return hit}
        return null
    }
    function check(value,label){
        if(!value)throw Error(label)
        assertions.push(label)
        console.info("GEMINI_FLOW_ASSERT",label)
    }
    function press(target,action){target.handleControllerPressed(action);target.handleControllerReleased(action)}
    function down(count){for(var i=0;i<count;i++)press(wizard,"down")}
    function mandatory(){var old=wizard.stepIndex;press(wizard,"square");check(wizard.stepIndex===old,"Square rejected on mandatory step "+(old+1))}
    function recordCombo(){press(wizard,"primary");for(var i=0;i<4;i++)press(wizard,["up","down","left","right"][i]);press(wizard,"system")}
    function complete(success,reason){
        ticker.stop()
        vmBridge.result({passed:success,reason:reason||"",securityOnline:securityCoreManager.daemonOnline,securityScore:securityCoreManager.securityScore,securityError:securityCoreManager.lastErrorCode,steps:steps,assertions:assertions,sshEnabled:vmBridge.sshEnabled,seconds:(Date.now()-started)/1000,productionManagers:true,liveLogin:true,runMode:resumedLogin?"login-after-completed-setup":"full-setup",consoleIdlePerformance:idlePerformance,lockIdlePerformance:lockIdlePerformance,unlockPerformance:unlockPerformance,unlockPreparationPerformance:unlockPreparationPerformance,unlockStages:unlockStages,wrongPasswordTested:wrongTested,fracturePerformance:fracturePerformance,fractureTriggerMs:fractureTriggerMs})
        vmBridge.finish(success)
    }
    property Timer ticker:Timer {
        interval:250;repeat:true;running:true
        onTriggered:{
            try{
                if(Date.now()-flow.started>420000)throw Error("Full controller setup timed out in phase "+flow.phase)
                if(flow.phase===0){
                    flow.wizard=flow.find(vmWindow.contentItem,"GeminiSetupWizard")
                    flow.main=flow.find(vmWindow.contentItem,"GeminiMainRoot")
                    if(!flow.wizard&&flow.main&&setupWizardManager.setupComplete){
                        flow.login=flow.find(vmWindow.contentItem,"GeminiLoginScreen")
                        if(!flow.login||!flow.login.active)return
                        flow.resumedLogin=true;flow.press(flow.login,"x");flow.phase=8;return
                    }
                    if(!flow.wizard||!flow.main)return
                    flow.mandatory();flow.press(flow.wizard,"x");flow.check(flow.wizard.stepIndex===1,"Welcome X reaches Timezone")
                    flow.steps.push(1,2);flow.phase=1
                }else if(flow.phase===1){
                    flow.mandatory();flow.press(flow.wizard,"circle");flow.check(flow.wizard.stepIndex===0,"Timezone back reaches Welcome")
                    flow.press(flow.wizard,"x");flow.check(flow.wizard.stepIndex===1,"Forward after back still reaches Timezone")
                    flow.wizard.timezone="America/New_York"
                    flow.down(3);flow.press(flow.wizard,"x");flow.check(flow.wizard.stepIndex===2,"Timezone applies through the actual backend")
                    flow.steps.push(3);flow.phase=2
                }else if(flow.phase===2){
                    // Dedicated kernel/NM regression tests exercise actual Wi-Fi.
                    // This flow proves setup and SSH work when network is skipped.
                    if(vmBridge.wifiEnabled){networkManager.requestScan();flow.phase=21;return}
                    flow.press(flow.wizard,"square");flow.check(flow.wizard.stepIndex===3,"Network Square advances")
                    flow.steps.push(4);vmBridge.capture("055-controller-unpaired");flow.phase=3
                }else if(flow.phase===21){
                    var available=networkManager.availableNetworks
                    var found=-1;for(var n=0;n<available.length;n++)if(available[n].ssid==="GeminiRegression")found=n
                    if(found<0||networkManager.operationBusy)return
                    flow.wizard.selectedIndex=found;flow.press(flow.wizard,"x")
                    flow.wizard.wifiPassword="gemini-test-only-052";flow.wizard.connectSelectedWifi();flow.check(flow.wizard.wifiConnecting,"Wizard starts the selected Wi-Fi operation after scan settles");flow.phase=22
                }else if(flow.phase===22){
                    if(networkManager.connectionState!=="CONNECTED"||networkManager.connectedSsid!=="GeminiRegression"){if(!flow.wizard.wifiConnecting&&networkManager.lastError.length)throw Error("Wi-Fi operation failed: "+networkManager.lastError);return}
                    flow.check(networkManager.connectedSsid==="GeminiRegression","Setup uses actual NetworkManager Wi-Fi connection")
                    var frequency=flow.find(flow.wizard,"setupWifiFrequency");flow.check(frequency!==null&&frequency.text==="2.4 GHz","Setup frequency displays the actual NetworkManager band without NaN")
                    flow.wizard.wifiModalOpen=false;flow.wizard.selectedIndex=networkManager.availableNetworks.length+1;flow.press(flow.wizard,"x")
                    flow.check(flow.wizard.stepIndex===3,"Connected Wi-Fi X advances to Controller")
                    flow.steps.push(4);vmBridge.capture("055-controller-unpaired");flow.phase=3
                }else if(flow.phase===3){
                    flow.press(flow.wizard,"square");flow.check(flow.wizard.stepIndex===4,"Controller Square advances")
                    flow.steps.push(5);flow.mandatory();vmBridge.capture("055-account")
                    flow.down(7);flow.press(flow.wizard,"x");flow.check(flow.wizard.stepIndex===4,"Invalid account cannot advance")
                    flow.wizard.hostname="gemini-vm-053";flow.wizard.username="geminiflow";flow.wizard.displayName="Gemini VM"
                    // Synthetic VM fixture only. Never log credential properties.
                    flow.wizard.accountPassword="Gemini-VM-test-only-053";flow.wizard.confirmPassword=flow.wizard.accountPassword
                    flow.press(flow.wizard,"up");flow.recordCombo();flow.recordCombo()
                    flow.check(flow.wizard.comboFirst.join("|")===flow.wizard.comboSecond.join("|"),"Controller passcode confirmation matches")
                    flow.press(flow.wizard,"down");flow.press(flow.wizard,"x");flow.phase=4
                }else if(flow.phase===4){
                    if(flow.wizard.stepIndex!==5)return
                    flow.check(flow.wizard.accountApplied&&flow.wizard.comboConfigured,"Actual Linux identity and controller passcode persisted")
                    flow.steps.push(6);flow.mandatory();flow.press(flow.wizard,"down");flow.press(flow.wizard,"x")
                    flow.check(flow.wizard.stepIndex===6,"Storage continues with existing storage preserved")
                    flow.steps.push(7);flow.phase=5
                }else if(flow.phase===5){
                    flow.press(flow.wizard,"square");flow.check(flow.wizard.stepIndex===7,"Recovery Square advances")
                    flow.steps.push(8);vmBridge.capture("055-security-simulation");flow.mandatory();flow.press(flow.wizard,"left");flow.down(8);flow.press(flow.wizard,"x")
                    flow.check(flow.wizard.stepIndex===8,"Security advances using supported preference state")
                    flow.steps.push(9);vmBridge.capture("055-initial-experience");flow.phase=6
                }else if(flow.phase===6){
                    flow.mandatory();flow.down(3)
                    if(flow.wizard.sshEnabledOnFinish!==vmBridge.sshEnabled)flow.press(flow.wizard,"x")
                    flow.down(4);flow.press(flow.wizard,"x")
                    flow.check(flow.wizard.stepIndex===9,"Preferences applied successfully with selected SSH path")
                    flow.steps.push(10);flow.mandatory();flow.phaseStarted=Date.now();flow.phase=61
                }else if(flow.phase===61){
                    if(Date.now()-flow.phaseStarted<1200)return
                    flow.wizard.notice="";vmBridge.capture("ready");vmBridge.beginPerformance()
                    var triggerStarted=Date.now();flow.press(flow.wizard,"x");flow.fractureTriggerMs=Date.now()-triggerStarted
                    flow.check(flow.main.setupFractureRetained,"Setup retained during fracture")
                    flow.check(setupWizardManager.setupComplete,"Actual setup completion persisted")
                    flow.login=flow.find(vmWindow.contentItem,"GeminiLoginScreen")
                    flow.check(flow.login!==null&&flow.login.visible&&flow.login.active,"Live Login rendered beneath Setup")
                    flow.phaseStarted=Date.now();flow.phase=7
                }else if(flow.phase===7){
                    if(flow.main.setupFractureRetained){if(vmBridge.captureFractureFrames)vmBridge.capture("fracture-"+flow.fractureFrame);flow.fractureFrame++;return}
                    flow.fracturePerformance=vmBridge.performance();flow.fracturePerformance.capturesDuringAnimation=vmBridge.captureFractureFrames
                    flow.check(flow.find(vmWindow.contentItem,"GeminiSetupWizard")===null,"Setup unloaded after fracture")
                    console.info("GEMINI_FOCUS_ITEM",vmWindow.activeFocusItem?vmWindow.activeFocusItem.objectName:"none")
                    if(!flow.main.itemContainsFocus(flow.login,vmWindow.activeFocusItem)){if(Date.now()-flow.phaseStarted>2500)throw Error("Live Login did not receive focus after Setup handoff");return}
                    flow.check(flow.main.itemContainsFocus(flow.login,vmWindow.activeFocusItem),"Live Login receives focus")
                    vmBridge.capture("login")
                    // Acknowledge first-login instructions through the controller.
                    flow.press(flow.login,"x");flow.phase=8
                }else if(flow.phase===8){
                    flow.press(flow.login,"x");flow.phase=81
                }else if(flow.phase===81){
                    vmBridge.capture("lock-idle")
                    if(flow.resumedLogin&&!vmBridge.captureFractureFrames){vmBridge.beginPerformance();flow.phaseStarted=Date.now();flow.phase=811;return}
                    // The authoritative login rejects an entire 15-input rolling window.
                    for(var j=0;j<flow.login.maxInputWindow;j++)flow.press(flow.login,"up")
                    flow.phaseStarted=Date.now();flow.phase=82
                }else if(flow.phase===811){
                    if(Date.now()-flow.phaseStarted<12000)return
                    flow.lockIdlePerformance=vmBridge.performance();flow.lockIdlePerformance.state="lock-atom-idle"
                    vmBridge.beginPerformance();flow.phase=9
                }else if(flow.phase===82){
                    if(!flow.login.errorText.length){if(Date.now()-flow.phaseStarted>60000)throw Error("Wrong passcode did not report rejection");return}
                    flow.check(!flow.main.authenticated,"Wrong controller passcode stays locked")
                    var presentation=flow.find(vmWindow.contentItem,"GeminiLockPresentation")
                    if(presentation.feedback!=="error"){
                        if(flow.wrongFeedbackWaitStarted===0)flow.wrongFeedbackWaitStarted=Date.now()
                        if(Date.now()-flow.wrongFeedbackWaitStarted>1200)throw Error("Wrong passcode did not turn energy red")
                        return
                    }
                    flow.check(presentation.feedback==="error","Wrong passcode gives immediate red energy feedback")
                    vmBridge.capture("lock-error");flow.wrongTested=true;flow.phaseStarted=Date.now();flow.phase=83
                }else if(flow.phase===83){
                    if(Date.now()-flow.phaseStarted<1700)return
                    var presentation=flow.find(vmWindow.contentItem,"GeminiLockPresentation")
                    flow.check(presentation.feedback==="neutral","Error energy returns cleanly to neutral")
                    vmBridge.beginPerformance();flow.phase=9
                }else if(flow.phase===9){
                    for(var i=0;i<4;i++)flow.press(flow.login,["up","down","left","right"][i])
                    flow.phase=10
                }else if(flow.phase===10){
                    if(!flow.main.authenticated)return
                    if(flow.main.shellMode!=="console"){
                        var transition=flow.find(vmWindow.contentItem,"GeminiUnlockTransition")
                        var stage=transition?transition.stage:"green"
                        if(transition&&transition.started&&!flow.transitionPerfStarted){flow.unlockPreparationPerformance=vmBridge.performance();vmBridge.beginPerformance();flow.transitionPerfStarted=true}
                        if(flow.unlockStages.indexOf(stage)<0){flow.unlockStages.push(stage);if(vmBridge.captureFractureFrames)vmBridge.capture("unlock-"+stage)}
                        return
                    }
                    flow.unlockPerformance=vmBridge.performance();flow.unlockPerformance.capturesDuringAnimation=vmBridge.captureFractureFrames
                    flow.check(flow.main.authenticated,"Controller passcode authenticates real Login")
                    flow.check(flow.main.shellMode==="console","Console launches after login")
                    vmBridge.capture("console");flow.phaseStarted=Date.now();flow.phase=105
                }else if(flow.phase===105){
                    if(Date.now()-flow.phaseStarted<4000)return
                    vmBridge.beginPerformance();flow.phaseStarted=Date.now();flow.phase=11
                }else if(flow.phase===11){
                    if(Date.now()-flow.phaseStarted<12000)return
                    flow.check(flow.find(vmWindow.contentItem,"GeminiLoginScreen")===null,"Login unloaded after Console handoff")
                    flow.check(securityCoreManager.daemonOnline,"Authoritative Security IPC becomes online after human login")
                    flow.check(securityCoreManager.securityScore>=0&&securityCoreManager.securityScore<=100,"Authoritative live Security score is available")
                    flow.idlePerformance=vmBridge.performance();flow.idlePerformance.state="console-idle-after-login"
                    flow.check(flow.idlePerformance.runningAnimations.length===0,"Covered legacy views and settled onboarding do not animate in Desktop")
                    if(vmBridge.wifiEnabled){
                        var header=flow.find(vmWindow.contentItem,"desktopWifiHeader")
                        flow.check(header!==null&&header.primary===networkManager.connectedSsid,"Desktop header equals actual active Wi-Fi SSID after setup/login")
                        var component=Qt.createComponent("/opt/neutronos/qml/modals/system/NetworkManagerModal.qml")
                        var modal=component.createObject(vmWindow.contentItem)
                        flow.check(modal!==null&&modal.connectedSsid()===header.primary,"Network modal and Desktop share actual NetworkManager SSID")
                        flow.networkModal=modal
                        var saved=false;for(var profile=0;profile<networkManager.savedNetworks.length;profile++)if(networkManager.savedNetworks[profile].ssid==="GeminiRegression")saved=true
                        flow.check(saved,"Actual Wi-Fi profile persisted")
                        if(networkManager.operationBusy)return
                        flow.check(networkManager.disconnectCurrent(),"Actual Wi-Fi disconnect starts")
                        flow.phase=12;return
                    }
                    flow.complete(true,"")
                }else if(flow.phase===12){
                    if(networkManager.connectedSsid.length||networkManager.operationBusy)return
                    var disconnectedHeader=flow.find(vmWindow.contentItem,"desktopWifiHeader")
                    flow.check(disconnectedHeader.primary==="Offline"&&flow.networkModal.connectedSsid()==="","Desktop and Network modal clear SSID after actual disconnect")
                    flow.check(networkManager.connectToNetwork({ssid:"GeminiRegression",security:"WPA2",remember:true}),"Reconnect uses saved profile without resubmitting credentials")
                    flow.phase=13
                }else if(flow.phase===13){
                    if(networkManager.connectionState!=="CONNECTED"||networkManager.connectedSsid!=="GeminiRegression")return
                    var reconnectedHeader=flow.find(vmWindow.contentItem,"desktopWifiHeader")
                    flow.check(reconnectedHeader.primary===networkManager.connectedSsid&&flow.networkModal.connectedSsid()===networkManager.connectedSsid,"Desktop and Network modal update after actual saved-profile reconnect")
                    flow.networkModal.destroy();flow.complete(true,"")
                }
            }catch(error){console.error("GEMINI_FLOW_FAILURE",String(error));flow.complete(false,String(error))}
        }
    }
}
