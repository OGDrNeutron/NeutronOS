import QtQuick
import QtTest
import "../../qml" as Shell
TestCase {
    id: test
    name: "GeminiVisualStates"
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
        function ensureRecoveryCode() {return true}
        function refreshRecoveryTargets() {}
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
        property bool available: true
        property bool scanning: false
        property var availableNetworks: [{ssid:"NeutronHome",signalPercent:96,security:"WPA2 / WPA3",frequency:5200},{ssid:"Orbi_5G",signalPercent:86,security:"WPA2",frequency:5200},{ssid:"NETGEAR",signalPercent:74,security:"WPA2",frequency:2437},{ssid:"TP-Link_2.4G",signalPercent:69,security:"WPA2",frequency:2412},{ssid:"XfinityWiFi",signalPercent:58,security:"WPA2",frequency:2437},{ssid:"SpectrumSetup-3F",signalPercent:49,security:"WPA2",frequency:2437}]
        property string connectionState: "DISCONNECTED"
        property string connectedSsid: ""
        property string lastError: ""
        signal operationFinished(string operation, bool success, string message)
        function setWifiEnabled(value) { return true }
        function requestScan() { return true }
        function connectToNetwork(payload) { return true }
    }
    QtObject {
        id:securityCoreManager
        property bool daemonOnline:true
        property int securityScore:100
        property int threatLevel:5
        property string threatLabel:"DEFCON 5"
        property bool recoveryConfigured:false
        property var stats:({firewallProtectionState:"ACTIVE",failedServices:0,events24h:0})
    }
    Shell.SetupWizard { id: wizard; anchors.fill: parent }
    function modal() {
        for (var i=0; i<wizard.children.length; i++)
            if (wizard.children[i].setupPresentation === true) return wizard.children[i]
        fail("Controller registration modal missing")
    }
    function test_capture_all_reference_states() {
        var captureQuality=findChild(wizard,"GeminiRenderQuality");verify(captureQuality!==null);captureQuality.active=false;captureQuality.level=2
        wizard.username="echo";wizard.displayName="Echo";wizard.hostname="neutronos"
        wizard.accountPassword="Gemini-visual-fixture-only-053";wizard.confirmPassword=wizard.accountPassword;wizard.comboConfigured=true;wizard.comboStatus="Passcode ready"
        setupWizardManager.recoveryCode="NEUTRON-7K9F-3D2M-V8HG-4P1Q-Z6TR"
        setupWizardManager.recoveryTargets=[{label:"SanDisk Ultra",mountPath:"/tmp/gemini-visual-usb-1"},{label:"Samsung USB Drive",mountPath:"/tmp/gemini-visual-usb-2"},{label:"Generic Flash Disk",mountPath:"/tmp/gemini-visual-usb-3"},{label:"External SSD",mountPath:"/tmp/gemini-visual-usb-4"}]
        setupWizardManager.storagePlan={disk:"/dev/vda",diskBytes:25769803776,systemBytes:16640800768,availableBytes:8589934592,status:"new",boot:{sectors:1048576}}
        var states=[{name:"01-welcome",step:0},{name:"02-timezone-1",step:1},{name:"03-timezone-2",step:1,region:true},{name:"04-network",step:2},{name:"05-controller-unpaired",step:3},{name:"06-controller-paired",step:3,paired:true},{name:"07-account",step:4},{name:"08-storage",step:5},{name:"09-recovery",step:6},{name:"10-security",step:7},{name:"11-initial-experience",step:8},{name:"12-ready",step:9}]
        for(var i=0;i<states.length;i++) {
            var state=states[i]
            wizard.setStep(state.step)
            wizard.selectedIndex=0
            if(state.name==="02-timezone-1")wizard.timezone="America/New_York"
            if(state.region)wizard.timezone="Europe/Berlin"
            if(state.step===3){wizard.bluetoothStage=state.paired?3:0;wizard.bluetoothCandidate={name:"DualSense Wireless Controller",manufacturer:"Sony Interactive Entertainment",address:"F8:5E:3C:9A:7B:21",paired:!!state.paired,trusted:!!state.paired,connected:!!state.paired}}
            if(state.step===6)wizard.recoveryKeyVisible=true
            waitForRendering(wizard)
            var surface=findChild(wizard,"setupPageSurface")
            tryCompare(surface,"opacity",1,10000)
            wait(state.step===1?1800:600)
            var capture=grabImage(wizard)
            compare(capture.width,wizard.width);compare(capture.height,wizard.height);verify(capture.pixel(20,100).a>0.99,"Setup background must stay opaque through lighting/3D captures");console.info("VM_CAPTURE",state.name,capture.width,capture.height,"quality",captureQuality.level,"staticCaptureQualityHeld",true)
            capture.save("/tmp/gemini-visual-"+state.name+".png")
        }
    }
}
