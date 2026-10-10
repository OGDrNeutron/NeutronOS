import QtQuick
import QtTest
import "../../qml" as Shell
TestCase {
    id: test
    name: "GeminiSetupFlow"
    when: windowShown
    visible: true
    width: 1280; height: 720
    QtObject {
        id: setupWizardManager
        property bool setupRequired: true
        property bool busy: false
        property string status: ""
        property string lastError: "Controller not verified"
        property bool controllerPaired: false
        property bool regionConfirmed: false
        property bool livePairingVerified: true
        property string rememberedUsbController: ""
        property bool bluetoothAvailable: true
        property bool bluetoothScanning: false
        property var bluetoothDevices: []
        property var recoveryTargets: []
        property string recoveryCode: ""
        property bool recoveryWritten: false
        property string remoteControllerToken: ""
        property var storagePlan: ({})
        property bool storageBusy: false
        property string storageStage: ""
        signal identityApplied(bool success, string user, string message)
        signal regionApplied(bool success, string message)
        signal bluetoothOperationFinished(bool success, string message)
        signal storageProvisioningFinished(bool success, var result, string message)
        signal storageProgress(string stage, string message)
        function refresh() {}
        function refreshStoragePlan() {}
        property int recoveryWrites:0
        function writeRecoveryDrive(path){recoveryWrites++;return path==="/media/fixture"}
        function ensureRecoveryCode(){return true}
        function refreshRecoveryTargets(){}
        function recordOptionalStep(step,skipped){return true}
        function domainStatus(id) {
            if (["timezone", "locale", "keyboard"].indexOf(id) >= 0)
                return regionConfirmed ? "configured" : "not-configured"
            if (id === "controller") return controllerPaired ? "configured" : "not-configured"
            return "not-configured"
        }
        function applyRegion(tz, locale, keyboard) { regionConfirmed = true; return true }
        function rememberUsbController(name, path) {}
        function confirmControllerRegistration() { controllerPaired = livePairingVerified; return controllerPaired }
    }
    QtObject {
        id: networkManager
        property var availableNetworks: []
        property string connectionState: "DISCONNECTED"
        property string connectedSsid: ""
        property string lastError: ""
        property bool operationBusy:false
        property var lastConnectPayload: ({})
        signal operationFinished(string operation, bool success, string message)
        function setWifiEnabled(value) { return true }
        function requestScan() { return true }
        function connectToNetwork(payload) {lastConnectPayload=payload;return true}
    }
    Shell.SetupWizard { id: wizard; anchors.fill: parent }
    QtObject{id:userManager;property var availableAvatars:[{id:"fixture-icon",label:"Fixture",source:""}];function resolveAvatarSource(id){return "file:///opt/neutronos/themes/Default/users/user_icon.png"}}
    QtObject{id:fileManager;property int copies:0;function copyText(value){if(value.length)copies++}}
    function modal(){return wizard.controllerRegistration}
    function initTestCase() { verify(wizard.backend() === setupWizardManager); verify(wizard.visible) }
    function init() {
        modal().state = ({})
        wizard.accountApplied=false
        wizard.comboConfigured=false
        wizard.comboRecording=false
        wizard.passwordVisible=false
        wizard.wifiPasswordVisible=false
        setupWizardManager.recoveryCode="FIXTURE-ONLY-NOT-A-REAL-KEY"
        setupWizardManager.recoveryTargets=[]
        setupWizardManager.recoveryWrites=0
        fileManager.copies=0
        setupWizardManager.regionConfirmed = false
        setupWizardManager.controllerPaired = false
        setupWizardManager.livePairingVerified = true
        networkManager.operationBusy=false
        networkManager.connectionState = "DISCONNECTED"
        networkManager.connectedSsid = ""
        wizard.bluetoothStage=0
        wizard.pickerOpen=false
        wizard.localePanelOpen=false
        wizard.experienceExtraPanel=false
        wizard.storageProgressOpen=false
        wizard.wifiStepVisited = false
        wizard.setStep(0)
    }
    function test_visual_states055() {
        function capture(name){wait(2500);var image=grabImage(wizard);verify(image.width>0&&image.height>0);image.save("/tmp/gemini-055-"+name+".png")}
        wizard.setStep(2);wizard.openWifiConnection({ssid:"GeminiRegression",security:"WPA2"});wizard.wifiModalIndex=1;capture("wifi-show-password-focus");wizard.wifiModalOpen=false
        wizard.setStep(3);wizard.controllerRegistration.active=false;wizard.controllerRegistration.transport="usb";wizard.controllerRegistration.state=({usb_present:true,phase:"waiting_disconnect"});capture("controller-wait-disconnect")
        wizard.controllerRegistration.state=({address:"02:00:00:00:00:01",paired:true,trusted:true,connected:true,usb_present:false,registration:{phase:"complete"}});capture("controller-verified-fixture")
        wizard.setStep(4);wizard.selectedAvatar="fixture-icon";wizard.accountIconFocused=true;capture("account-icon-focus");wizard.accountIconFocused=false;wizard.selectedIndex=3;capture("account-password-instruction")
        wizard.setStep(6);setupWizardManager.recoveryTargets=[{label:"Synthetic VM target",mountPath:"/media/fixture"}];wizard.recoveryActionIndex=0;capture("recovery-copy-focus");wizard.recoveryActionIndex=2;capture("recovery-save-focus")
        wizard.setStep(7);wizard.securityPanel="right";wizard.securityChoiceIndex=2;wizard.securityProfileIndex=2;capture("security-simulation-profile");wizard.securityPanel="left";wizard.selectedIndex=1;capture("security-left-focus")
        wizard.setStep(8);capture("initial-experience")
    }
}
