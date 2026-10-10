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
    QtObject{id:userManager;property var availableAvatars:[{id:"fixture-icon",label:"Fixture",source:""}];function resolveAvatarSource(id){return ""}}
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
    function test_forward_reaches_region_then_wifi() {
        wizard.handleControllerPressed("x")
        compare(wizard.stepIndex, 1)
        wizard.selectedIndex = 3
        wizard.handleControllerPressed("x")
        compare(wizard.stepIndex, 2)
        verify(setupWizardManager.regionConfirmed)
    }
    function test_circle_returns_to_region_and_welcome() {
        wizard.setStep(2)
        wizard.handleControllerPressed("circle")
        compare(wizard.stepIndex, 1)
        wizard.handleControllerPressed("circle")
        compare(wizard.stepIndex, 0)
        wizard.handleControllerPressed("x")
        compare(wizard.stepIndex, 1)
    }
    function test_paired_controller_continue_advances() {
        wizard.setStep(3)
        modal().applyRegistration({address:"02:00:00:00:00:01",paired:true,trusted:true,connected:true,usb_present:false,phase:"error"})
        compare(wizard.bluetoothStage,3)
        verify(!setupWizardManager.controllerPaired)
        wizard.handleControllerPressed("x")
        compare(wizard.stepIndex,4)
    }
    function test_incomplete_or_stale_pairing_stays_on_step() {
        wizard.setStep(3)
        modal().applyRegistration({address:"02:00:00:00:00:01",paired:true,trusted:true,connected:false})
        compare(wizard.bluetoothStage,0)
        setupWizardManager.livePairingVerified=false
        modal().applyRegistration({address:"02:00:00:00:00:01",paired:true,trusted:true,connected:true,usb_present:false})
        wizard.handleControllerPressed("x")
        compare(wizard.stepIndex,3)
        verify(!setupWizardManager.controllerPaired)
    }
    Connections {target:controllerReplay;function onPressed(action){wizard.handleControllerPressed(action)}function onReleased(action){wizard.handleControllerReleased(action)}}
    function test_evdev_pairing_cross_and_square() {
        wizard.setStep(3)
        controllerReplay.tap(304) // BTN_SOUTH: real production evdev reader and mapping
        compare(wizard.stepIndex,3)
        controllerReplay.tap(308) // BTN_WEST must not skip pairing
        compare(wizard.stepIndex,3)
        modal().applyRegistration({address:"02:00:00:00:00:01",paired:true,trusted:true,connected:true,usb_present:false})
        controllerReplay.tap(308);compare(wizard.stepIndex,3)
        controllerReplay.event(304,1);compare(wizard.stepIndex,4)
        controllerReplay.event(304,2);compare(wizard.stepIndex,4) // repeat does not reconfirm
        controllerReplay.event(304,0)
    }
    function test_wifi_show_password_is_controller_selectable() {
        wizard.setStep(2);wizard.openWifiConnection({ssid:"Fixture",security:"WPA2"})
        wizard.handleControllerPressed("down");compare(wizard.wifiModalIndex,1)
        wizard.handleControllerPressed("x");verify(wizard.wifiPasswordVisible)
        wizard.handleControllerPressed("x");verify(!wizard.wifiPasswordVisible)
        compare(wizard.stepIndex,2);verify(!wizard.wifiConnecting)
    }
    function test_account_icon_and_password_navigation() {
        wizard.setStep(4);wizard.selectedIndex=3
        wizard.handleControllerPressed("square");verify(wizard.passwordVisible)
        wizard.handleControllerPressed("down");compare(wizard.selectedIndex,4)
        wizard.handleControllerPressed("square");verify(!wizard.passwordVisible)
        wizard.handleControllerPressed("down");compare(wizard.selectedIndex,5)
        wizard.handleControllerPressed("left");verify(wizard.accountIconFocused)
        wizard.handleControllerPressed("x");verify(wizard.avatarPickerOpen)
        wizard.handleControllerPressed("x");compare(wizard.selectedAvatar,"fixture-icon")
        wizard.handleControllerPressed("right");verify(!wizard.accountIconFocused)
        compare(wizard.selectedIndex,5)
        wizard.handleControllerPressed("triangle");verify(wizard.avatarPickerOpen)
        wizard.handleControllerPressed("circle");verify(!wizard.avatarPickerOpen)
        wizard.handleControllerPressed("down");compare(wizard.selectedIndex,6)
    }
    function test_recovery_copy_save_and_confirmation_cancel() {
        wizard.setStep(6);verify(wizard.recoveryKeyVisible)
        wizard.handleControllerPressed("x");compare(fileManager.copies,1)
        wizard.handleControllerPressed("down");wizard.handleControllerPressed("down")
        wizard.handleControllerPressed("x");verify(!wizard.recoveryConfirmOpen)
        setupWizardManager.recoveryTargets=[{mountPath:"/media/fixture"}]
        wizard.handleControllerPressed("x");verify(wizard.recoveryConfirmOpen)
        wizard.handleControllerPressed("circle");verify(!wizard.recoveryConfirmOpen)
        compare(wizard.stepIndex,6);compare(setupWizardManager.recoveryWrites,0)
        wizard.handleControllerPressed("x");wizard.handleControllerPressed("x")
        compare(setupWizardManager.recoveryWrites,1)
        compare(wizard.stepIndex,6)
        wizard.handleControllerPressed("down");wizard.handleControllerPressed("x")
        compare(wizard.stepIndex,7)
    }
    function test_security_panels_use_up_down_and_live_preview_selection() {
        wizard.setStep(7);compare(wizard.securityPanel,"right")
        wizard.handleControllerPressed("down");compare(wizard.securityChoiceIndex,1)
        wizard.handleControllerPressed("x");compare(wizard.securityProfileIndex,1)
        compare(wizard.simulatedSecurity.profile,"Strict")
        compare(wizard.simulatedSecurity.score,100)
        wizard.handleControllerPressed("left");compare(wizard.securityPanel,"left")
        compare(wizard.selectedIndex,0)
        wizard.handleControllerPressed("down");compare(wizard.selectedIndex,1)
        wizard.handleControllerPressed("right");compare(wizard.securityPanel,"right")
        compare(wizard.selectedIndex,1)
        wizard.handleControllerPressed("left");wizard.selectedIndex=8
        wizard.handleControllerPressed("x");compare(wizard.stepIndex,8)
    }
    function test_wifi_ui_waits_for_selected_link_before_completion() {
        wizard.setStep(2)
        wizard.openWifiConnection({ssid:"GeminiRegression", security:"WPA2"})
        wizard.wifiPassword = "fixture-password"
        wizard.connectSelectedWifi()
        verify(wizard.wifiConnecting)
        networkManager.operationFinished("connect", true, "accepted")
        wait(600)
        verify(wizard.wifiConnecting)
        verify(!wizard.wifiStepVisited)
        networkManager.connectionState = "CONNECTED"
        networkManager.connectedSsid = "DifferentNetwork"
        wait(600)
        verify(!wizard.wifiStepVisited)
        networkManager.connectedSsid = "GeminiRegression"
        tryCompare(wizard, "wifiConnecting", false, 2000)
        verify(wizard.wifiStepVisited)
        compare(wizard.wifiPassword, "")
    }
    function test_scan_busy_does_not_start_or_clear_wifi_credentials() {
        wizard.setStep(2)
        wizard.openWifiConnection({ssid:"BusyRegression",security:"WPA2"})
        wizard.wifiPassword="fixture-password"
        networkManager.operationBusy=true
        wizard.connectSelectedWifi()
        verify(!wizard.wifiConnecting)
        compare(wizard.wifiPassword,"fixture-password")
        verify(wizard.wifiConnectionState.indexOf("scanning")>=0)
    }
    function test_hidden_ssid_preserves_generic_backend_payload() {
        wizard.setStep(2)
        wizard.openHiddenWifi()
        compare(wizard.keyboardField,"hiddenSsid")
        wizard.setFieldValue("hiddenSsid","HiddenRegression")
        wizard.closeKeyboard()
        wizard.wifiPassword="fixture-password"
        wizard.connectSelectedWifi()
        verify(networkManager.lastConnectPayload.hidden)
        compare(networkManager.lastConnectPayload.ssid,"HiddenRegression")
        verify(networkManager.lastConnectPayload.remember)
        wizard.wifiConnecting=false
        wizard.wifiModalOpen=false
        wizard.wifiPassword=""
    }
    function test_wifi_failure_is_visible_and_does_not_complete_step() {
        wizard.setStep(2)
        wizard.openWifiConnection({ssid:"GeminiRegression", security:"WPA2"})
        wizard.wifiPassword = "fixture-password"
        wizard.connectSelectedWifi()
        networkManager.operationFinished("connect", false, "Wi-Fi adapter unavailable")
        verify(!wizard.wifiConnecting)
        verify(!wizard.wifiStepVisited)
        compare(wizard.wifiConnectionState, "Wi-Fi adapter unavailable")
        compare(wizard.wifiPassword, "")
    }
    function test_square_skips_only_optional_steps() {
        for(var i=0;i<2;i++) {
            var step=[2,6][i]
            wizard.stepIndex=step
            wizard.handleControllerPressed("square")
            compare(wizard.stepIndex,step+1)
        }
    }
    function test_square_rejects_every_mandatory_page() {
        var steps=[0,1,3,4,5,7,8,9]
        for(var i=0;i<steps.length;i++) {
            wizard.stepIndex=steps[i]
            wizard.handleControllerPressed("square")
            compare(wizard.stepIndex,steps[i])
        }
    }
    function test_confirmed_timezone_still_appears_after_back_to_welcome() {
        setupWizardManager.regionConfirmed=true
        wizard.setStep(0)
        wizard.handleControllerPressed("x")
        compare(wizard.stepIndex,1)
    }
    function test_back_preserves_account_and_network_entries() {
        wizard.username="fixtureuser"
        wizard.wifiPassword="fixture-password"
        wizard.stepIndex=4
        wizard.handleControllerPressed("circle")
        compare(wizard.username,"fixtureuser")
        wizard.handleControllerPressed("circle")
        compare(wizard.wifiPassword,"fixture-password")
    }
}
