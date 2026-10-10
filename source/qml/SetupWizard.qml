import QtQuick 2.15
import QtQuick.Controls 2.15
import "gemini"
import "modals/system/TimezoneCatalog.js" as TimezoneCatalog
import "components"
import "gemini/SecurityScoreSimulation.js" as ScoreSimulation
import "modals/system"

Item {
    id: root
    objectName: "GeminiSetupWizard"

    anchors.fill: parent
    visible: typeof setupWizardManager !== "undefined" && setupWizardManager && (setupWizardManager.setupRequired || fractureActive)
    enabled: visible
    focus: visible
    z: 60000

    signal completed()
    signal completionStarting()
    signal completionAborted()
    property bool fractureActive: false
    property bool pickerOpen: false
    property int pickerStage: 0
    property int pickerIndex: 0
    property bool localePanelOpen: false
    property int localePanelIndex: 0
    property bool wifiPasswordVisible: false
    property bool recoveryKeyVisible: true
    property bool accountIconFocused: false
    property string securityPanel: "right"
    property int securityChoiceIndex: 0
    property int recoveryActionIndex: 0
    property alias controllerRegistration: registrationSession
    property bool recoveryConfirmOpen: false
    property bool experienceExtraPanel: false
    property int experienceExtraIndex: 0
    property string selectedAvatar: ""
    property bool avatarPickerOpen: false
    property int avatarPickerIndex: 0
    readonly property var timezonePath: TimezoneCatalog.findPath(timezone)
    readonly property string regionLabel: timezone === "UTC" ? "Worldwide" : TimezoneCatalog.continentAt(timezonePath.continent).name
    readonly property string countryLabel: timezone === "UTC" ? "All countries" : TimezoneCatalog.countriesFor(timezonePath.continent)[timezonePath.country].name
    readonly property string timezoneLabel: timezone === "UTC" ? "Coordinated Universal Time (UTC)" : TimezoneCatalog.zonesFor(timezonePath.continent,timezonePath.country)[timezonePath.zone].label
    readonly property var pickerEntries: pickerStage === 0 ? TimezoneCatalog.catalog.concat([{name:"Worldwide",utc:true}]) : pickerStage === 1 ? TimezoneCatalog.countriesFor(timezonePath.continent) : TimezoneCatalog.zonesFor(timezonePath.continent,timezonePath.country)
    GeminiRenderQuality { id: renderQuality; active: root.visible && !root.fractureActive && !root.accountBusy && !(root.backend() && root.backend().busy) }

    property int stepIndex: 0
    property int selectedIndex: 0
    property bool keyboardOpen: false
    property string keyboardField: ""
    property bool keyboardSecret: false
    property bool optionsHeld: false
    property string notice: ""
    property string noticeDetail: ""
    property bool noticeError: false
    property bool stepTransitionRunning: false

    property string timezone: "UTC"
    property string localeName: "en_US.UTF-8"
    property string keyboardLayout: "us"

    property string wifiPassword: ""
    property var selectedWifi: ({})
    property bool wifiModalOpen: false
    property bool wifiConnecting: false
    property int wifiModalIndex: 0
    property string wifiConnectionState: ""
    property int wifiVerificationTicks: 0

    property int bluetoothStage: 0 // 0 intro, 1 scanned, 2 candidate chosen, 3 paired
    property int bluetoothIndex: 0
    property var bluetoothCandidate: ({})

    property string hostname: "neutronos"
    property string username: ""
    property string displayName: ""
    property string accountPassword: ""
    property string confirmPassword: ""
    property bool passwordVisible: false
    property bool accountApplied: false
    property bool accountBusy: false

    property bool comboRecording: false
    property bool comboConfirming: false
    property var comboFirst: []
    property var comboSecond: []
    property string comboStatus: "Not configured"
    property bool comboConfigured: false

    property int recoveryIndex: 0
    property bool recoverySkipped: false

    property int audioIndex: 0
    property int screensaverIndex: 1
    property int performanceIndex: 0
    property int launcherIndex: 0
    property int securityProfileIndex: 0
    property bool securityLearningMode: false
    property bool securityEnforcementEnabled: true
    property bool securityResponseEngineEnabled: true
    property bool securityBackgroundScanEnabled: true
    property int securityHardeningIndex: 1
    property int securitySeverityIndex: 1
    property int securityBanIndex: 1
    property int privacyIndex: 0
    property int dashboardTabIndex: 0
    property bool wifiStepVisited: false
    property bool storageStepVisited: false
    property bool storageConfirmOpen: false
    property bool storageProgressOpen: false
    property bool storageProgressSuccess: false
    property string storageProgressMessage: ""
    property var storageProgressResult: ({})
    readonly property var storagePlan: backend() ? backend().storagePlan : ({})
    property bool sshEnabledOnFinish: false
    property bool remoteControllerEnabled: false
    property bool displayConfirmed: true
    property bool preferencesApplied: false

    readonly property var stepTitles: [
        "WELCOME",
        "REGION",
        "WI-FI",
        "BLUETOOTH CONTROLLER",
        "ACCOUNT & PASSCODE",
        "USER STORAGE",
        "RECOVERY DRIVE",
        "SECURITY CONFIGURATION",
        "PREFERENCES",
        "READY"
    ]

    readonly property var screensaverOptions: [5, 10, 15, 30]
    readonly property var performanceOptions: ["Normal", "Eco"]
    readonly property var launcherOptions: ["Carousel", "Desktop / Card Grid"]
    readonly property var securityHardeningOptions: ["Balanced", "Strict", "Fortified"]
    readonly property var securitySeverityOptions: ["High only", "Medium and above", "Low and above"]
    readonly property var securitySeverityValues: [4, 3, 2]
    readonly property var securityBanOptions: [8, 5, 3]
    readonly property var privacyOptions: ["Local only", "Share diagnostics"]
    readonly property var dashboardTabOptions: ["Desktop", "System Overview", "Security", "Storage", "Apps"]
    readonly property var dashboardTabIds: ["desktop", "system", "security", "storage", "apps"]
    readonly property string welcomeTitle: "Welcome To NeutronOS"
    readonly property color primaryText: "#F4F8FF"
    readonly property color secondaryText: "#A9C7DC"
    readonly property color neutronRed: "#FF3040"
    readonly property color focusCyan: "#68E7FF"

    function backend() {
        return (typeof setupWizardManager !== "undefined") ? setupWizardManager : null
    }

    function normalize(value) {
        var action = String(value || "").trim().toLowerCase()
        if (action === "x" || action === "cross" || action === "primary" || action === "a") return "primary"
        if (action === "o" || action === "circle" || action === "cancel" || action === "b") return "cancel"
        if (action === "triangle" || action === "context" || action === "y") return "context"
        if (action === "square" || action === "secondary") return "secondary"
        if (action === "options" || action === "system" || action === "start") return "system"
        if (action === "dpad_up") return "up"
        if (action === "dpad_down") return "down"
        if (action === "dpad_left") return "left"
        if (action === "dpad_right") return "right"
        return action
    }

    function showNotice(message, errorState, detail) {
        notice = String(message || "")
        noticeDetail = String(detail || "")
        noticeError = errorState === true
        noticeTimer.restart()
    }

    function openAvatarPicker() {
        if(typeof userManager==="undefined" || !userManager.availableAvatars.length) {showNotice("No account icons available",false);return}
        avatarPickerOpen=true
    }
    function selectAvatar() {
        var choices=userManager.availableAvatars
        if(avatarPickerIndex>=0 && avatarPickerIndex<choices.length)selectedAvatar=String(choices[avatarPickerIndex].id||choices[avatarPickerIndex].source)
        avatarPickerOpen=false
    }
    function setStep(index) {
        var previousStep = stepIndex
        stepIndex = Math.max(0, Math.min(stepTitles.length - 1, index))
        selectedIndex = 0
        accountIconFocused = false
        securityPanel = "right"
        securityChoiceIndex = securityProfileIndex
        recoveryActionIndex = 0
        keyboardOpen = false
        optionsHeld = false
        keyboard.closeKeyboard()
        wifiModalOpen = false
        pickerOpen = false
        localePanelOpen = false
        avatarPickerOpen = false
        experienceExtraPanel = false
        if (stepIndex === 4 && previousStep !== 4)
            passwordVisible = false
        if (stepIndex === 2 && typeof networkManager !== "undefined" && networkManager) {
            if (typeof networkManager.setWifiEnabled === "function") networkManager.setWifiEnabled(true)
            if (typeof networkManager.requestScan === "function") networkManager.requestScan()
        }
        if (stepIndex === 3) {
            var name = (typeof controllerManager !== "undefined" && controllerManager)
                    ? String(controllerManager.controllerName || "") : ""
            var path = (typeof controllerManager !== "undefined" && controllerManager)
                    ? String(controllerManager.controllerDevicePath || "") : ""
            if (backend()) backend().rememberUsbController(name, path)
        }
        if (stepIndex === 5 && backend()) {
            storageConfirmOpen = false
            backend().refreshStoragePlan()
        }
        if (stepIndex === 6 && backend()) {
            backend().ensureRecoveryCode()
            backend().refreshRecoveryTargets()
        }
        if (stepIndex === 8 && typeof musicPlayerManager !== "undefined" && musicPlayerManager) {
            if (typeof musicPlayerManager.refreshAudioOutputs === "function")
                musicPlayerManager.refreshAudioOutputs()
        }
    }

    function domainConfigured(id) {
        return backend() && typeof backend().domainStatus === "function" && backend().domainStatus(id) === "configured"
    }

    function firstIncompleteStep() { return 1 }

    function recordOptional(step, skipped) {
        if (backend() && typeof backend().recordOptionalStep === "function" &&
                !backend().recordOptionalStep(step,skipped)) {
            showNotice(backend().lastError,true)
            return false
        }
        return true
    }
    function skipOptionalStep() {
        var id = stepIndex === 2 ? "network" : stepIndex === 3 ? "controller" : stepIndex === 6 ? "recovery" : ""
        if (!id.length) {showNotice("This page is required",false);return}
        if (!recordOptional(id,true))return
        if (stepIndex === 2) {
            wifiVerifyTimer.stop();wifiPassword="";wifiConnecting=false;wifiStepVisited=true;wifiModalOpen=false
        }
        // Registration is reconciled by the bridge; leaving this optional page does not erase a bond.
        if (stepIndex === 6) {recoverySkipped=true;recoveryConfirmOpen=false}
        setStep(stepIndex+1)
    }
    function openRegionPicker(stage) {
        if (timezone === "UTC" && stage > 0) {showNotice("Select a geographic region first",false);return}
        pickerStage=stage
        pickerIndex=stage===0?(timezone==="UTC"?TimezoneCatalog.continentCount():timezonePath.continent):stage===1?timezonePath.country:timezonePath.zone
        pickerOpen=true
    }
    function selectRegionEntry() {
        var entry=pickerEntries[pickerIndex]
        if(!entry)return
        if(pickerStage===0) timezone=entry.utc?"UTC":entry.countries[0].zones[0].id
        else if(pickerStage===1) timezone=entry.zones[0].id
        else timezone=entry.id
        pickerOpen=false
    }
    function continueRegion() {
        if(backend() && backend().applyRegion(timezone,localeName,keyboardLayout))setStep(2)
        else showNotice(backend()?backend().lastError:"Region backend unavailable",true)
    }
    function activateAccountField(row) {selectedIndex=row;handleControllerPressed("primary")}
    function continueAccount() {accountIconFocused=false;selectedIndex=6;handleControllerPressed("primary")}
    function continuePreferences() {selectedIndex=7;handleControllerPressed("primary")}
    function copyRecoveryKey() {
        if(typeof fileManager!=="undefined" && fileManager && backend()) {
            fileManager.copyText(backend().recoveryCode)
            showNotice("Recovery key copied",false)
        }
    }

    function storageSize(value) {
        var bytes = Number(value || 0)
        return bytes > 0 ? (bytes / 1073741824).toFixed(2) + " GiB" : "Unavailable"
    }
    function storageLayoutLine(label, entry) {
        if (!entry || !entry.device) return label + ": unavailable"
        var start = Number(entry.start || 0), sectors = Number(entry.sectors || 0)
        return label + "  " + String(entry.device) + "  sectors " + start + "–" +
               (start + sectors - 1) + "  (" + storageSize(sectors * 512) + ")"
    }

    function fieldValue(name) {
        if (name === "timezone") return timezone
        if (name === "locale") return localeName
        if (name === "keyboard") return keyboardLayout
        if (name === "wifiPassword") return wifiPassword
        if (name === "hiddenSsid") return String(selectedWifi.ssid||"")
        if (name === "hostname") return hostname
        if (name === "username") return username
        if (name === "displayName") return displayName
        if (name === "accountPassword") return accountPassword
        if (name === "confirmPassword") return confirmPassword
        return ""
    }

    function setFieldValue(name, value) {
        var text = String(value || "")
        if (name === "timezone") timezone = text
        else if (name === "locale") localeName = text
        else if (name === "keyboard") keyboardLayout = text
        else if (name === "wifiPassword") wifiPassword = text
        else if (name === "hiddenSsid") selectedWifi=({ssid:text,security:"WPA2",hidden:true})
        else if (name === "hostname") hostname = text
        else if (name === "username") username = text.toLowerCase()
        else if (name === "displayName") displayName = text
        else if (name === "accountPassword") accountPassword = text
        else if (name === "confirmPassword") confirmPassword = text
    }

    function openKeyboard(field, secret) {
        keyboardField = field
        keyboardSecret = secret === true
        keyboardOpen = true
        keyboard.openKeyboard()
    }

    function closeKeyboard() {
        keyboardOpen = false
        optionsHeld = false
        keyboard.closeKeyboard()
        forceActiveFocus()
    }

    function appendKeyboard(value) {
        var current = fieldValue(keyboardField)
        if (value === "CLEAR") current = ""
        else if (value === "SPACE") current += " "
        else current += value
        setFieldValue(keyboardField, current)
    }

    function connectSelectedWifi() {
        if (typeof networkManager!=="undefined" && networkManager && networkManager.operationBusy) {
            wifiConnectionState="Wi-Fi is still scanning or completing an operation. Try Connect when it finishes."
            showNotice(wifiConnectionState,false)
            return
        }
        if (!selectedWifi || String(selectedWifi.ssid || "").length === 0)
            return
        var security = String(selectedWifi.security || selectedWifi.securityType || "Open")
        var secure = security.toLowerCase().indexOf("open") < 0 && security.toLowerCase() !== "none"
        if (secure && wifiPassword.length === 0) {
            wifiConnectionState = "Enter the network password, then choose Connect."
            return
        }
        if (wifiConnecting)
            return
        if (typeof networkManager !== "undefined" && networkManager &&
                typeof networkManager.connectToNetwork === "function") {
            var accepted = networkManager.connectToNetwork({
                ssid: String(selectedWifi.ssid || ""),
                security: security,
                password: wifiPassword,
                remember: true,
                hidden: selectedWifi.hidden===true,
                accessPointPath: selectedWifi.accessPointPath || selectedWifi.path || ""
            })
            if (!accepted) {
                wifiConnectionState = String(networkManager.lastError || "Unable to start Wi-Fi connection")
                wifiPassword = ""
            } else {
                wifiConnecting = true
                wifiVerificationTicks = 0
                wifiConnectionState = "Connecting to " + String(selectedWifi.ssid || "") + "…"
            }
        }
    }

    function openHiddenWifi() {
        openWifiConnection({ssid:"",security:"WPA2",hidden:true})
        openKeyboard("hiddenSsid",false)
    }

    function openWifiConnection(network) {
        selectedWifi = network || ({})
        wifiPassword = ""
        wifiConnecting = false
        wifiVerificationTicks = 0
        wifiModalIndex = 0
        wifiConnectionState = "Enter the password and choose Connect."
        var security = String(selectedWifi.security || selectedWifi.securityType || "Open").toLowerCase()
        if (security.indexOf("open") >= 0 || security === "none") {
            wifiModalIndex = 2
            wifiConnectionState = "This network does not require a password."
        }
        wifiModalOpen = true
    }

    function finishWifiVerification(success, message) {
        wifiVerifyTimer.stop()
        wifiConnecting = false
        wifiPassword = ""
        wifiConnectionState = message
        if (success) {
            recordOptional("network",false)
            wifiStepVisited = true
            wifiModalIndex = 3
        }
    }

    function beginComboRecording(confirming) {
        comboRecording = true
        comboConfirming = confirming === true
        if (comboConfirming) comboSecond = []
        else comboFirst = []
        comboStatus = comboConfirming
                ? "Repeat the passcode, then press OPTIONS"
                : "Enter 4–10 controller inputs, then press OPTIONS"
    }

    function comboToken(action) {
        var allowed = ["primary", "secondary", "context", "up", "down", "left", "right", "l1", "r1", "l2", "r2"]
        return allowed.indexOf(action) >= 0 ? action : ""
    }

    function finishComboRecording() {
        var values = comboConfirming ? comboSecond : comboFirst
        if (values.length < 4 || values.length > 10) {
            comboStatus = "Passcode must contain 4–10 inputs"
            showNotice(comboStatus, true)
            comboRecording = false
            return
        }
        comboRecording = false
        if (!comboConfirming) {
            comboStatus = "First pass captured. Press X to repeat it."
            return
        }
        if (comboFirst.join("|") !== comboSecond.join("|")) {
            comboStatus = "Passcodes did not match. Record again."
            comboFirst = []
            comboSecond = []
            showNotice(comboStatus, true)
            return
        }
        comboStatus = "Passcode ready"
        showNotice("Controller passcode captured", false)
    }

    function applyAccountAndCombo() {
        if (accountPassword.length < 8) {
            showNotice("Account password must contain at least 8 characters", true)
            return
        }
        if (accountPassword !== confirmPassword) {
            showNotice("Passwords do not match", true)
            return
        }
        if (comboFirst.length < 4 || comboFirst.join("|") !== comboSecond.join("|")) {
            showNotice("Create and confirm the controller passcode first", true)
            return
        }
        if (!backend()) return
        accountBusy = true
        if (!backend().applyIdentity(hostname, username, displayName, accountPassword)) {
            accountBusy = false
            showNotice("Unable to create your account.", true,
                       String(backend().lastError || "The account service could not complete the request."))
        }
    }

    function audioOutputLabel() {
        var outputs = (typeof musicPlayerManager !== "undefined" && musicPlayerManager)
                ? musicPlayerManager.audioOutputs : []
        if (!outputs || outputs.length === 0)
            return "Automatic"
        var index = Math.max(0, Math.min(outputs.length - 1, audioIndex))
        var output = outputs[index] || ({})
        return String(output.name || output.label || output.description || output.id || "Automatic")
    }

    function applyPreferences() {
        var outputs = (typeof musicPlayerManager !== "undefined" && musicPlayerManager)
                ? musicPlayerManager.audioOutputs : []
        if (outputs && outputs.length > 0) {
            var output = outputs[Math.max(0, Math.min(outputs.length - 1, audioIndex))]
            if (output && typeof musicPlayerManager.setSelectedAudioOutput === "function")
                musicPlayerManager.setSelectedAudioOutput(String(output.id || "auto"))
        }
        if (typeof screensaverManager !== "undefined" && screensaverManager &&
                typeof screensaverManager.applyTimeoutMinutes === "function")
            screensaverManager.applyTimeoutMinutes(screensaverOptions[screensaverIndex])

        if (typeof personalizationManager !== "undefined" && personalizationManager) {
            if (typeof personalizationManager.setActiveUser === "function")
                personalizationManager.setActiveUser(username)
            if (typeof personalizationManager.applyLauncher === "function")
                personalizationManager.applyLauncher(
                    launcherOptions[launcherIndex].toLowerCase().indexOf("grid") >= 0 ? "grid" : "carousel",
                    100, 100)
        }
        if (typeof dashboardLayoutManager !== "undefined" && dashboardLayoutManager) {
            dashboardLayoutManager.setActiveUser(username)
            dashboardLayoutManager.setDefaultTab(dashboardTabIds[dashboardTabIndex])
        }

        if (backend()) {
            return backend().savePreferences({
                audioOutput: outputs && outputs.length > 0
                             ? String(outputs[audioIndex].id || "auto") : "auto",
                screensaverMinutes: screensaverOptions[screensaverIndex],
                performancePreference: performanceOptions[performanceIndex],
                launcherMode: launcherOptions[launcherIndex].toLowerCase().indexOf("grid") >= 0
                              ? "grid" : "carousel",
                securityProfile: "custom",
                securityLearningMode: securityProfileIndex !== 2 ? false : securityLearningMode,
                securityEnforcementEnabled: securityProfileIndex !== 2 ? true : securityEnforcementEnabled,
                securityResponseEngineEnabled: securityProfileIndex !== 2 ? true : securityResponseEngineEnabled,
                securityBackgroundScanEnabled: securityProfileIndex !== 2 ? true : securityBackgroundScanEnabled,
                securityHardeningProfile: securityProfileIndex === 0 ? "balanced" : securityProfileIndex === 1 ? "strict" : securityHardeningOptions[securityHardeningIndex].toLowerCase(),
                securityNotificationMinimumSeverity: securityProfileIndex !== 2 ? 3 : securitySeverityValues[securitySeverityIndex],
                securityAutomaticBanThreshold: securityProfileIndex !== 2 ? 5 : securityBanOptions[securityBanIndex],
                diagnosticsSharing: privacyIndex === 1,
                sshEnabled: sshEnabledOnFinish,
                remoteControllerEnabled: remoteControllerEnabled,
                displayConfirmed: displayConfirmed,
                defaultDashboardTab: dashboardTabIds[dashboardTabIndex]
            })
        }
        return false
    }

    function finishWizard() {
        if(fractureActive)return
        if(!preferencesApplied) {
            if(!applyPreferences()) {showNotice(backend()?backend().lastError:"Unable to apply preferences",true);return}
            preferencesApplied=true
        }
        fractureActive=true
        completionStarting()
        if(!backend() || !backend().completeSetup()) {
            fractureActive=false;completionAborted()
            showNotice(backend()?backend().lastError:"Setup backend unavailable",true)
            return
        }
        accountPassword="";confirmPassword="";passwordVisible=false;wifiPassword=""
        fractureLoader.active=true
        Qt.callLater(function(){if(fractureLoader.item)fractureLoader.item.begin(setupPages)})
    }

    property bool controllerContinueBusy: false

    function handleControllerPressed(value) {
        if (!visible)
            return false
        var action = normalize(value)
        if(fractureActive)return true
        if(avatarPickerOpen) {
            if(action==="cancel")avatarPickerOpen=false
            else if(action==="primary")selectAvatar()
            else if(["up","down","left","right"].indexOf(action)>=0)avatarPickerIndex=Math.max(0,Math.min(userManager.availableAvatars.length-1,avatarPickerIndex+(action==="up"?-5:action==="down"?5:action==="left"?-1:1)))
            return true
        }
        if(pickerOpen) {
            if(action==="cancel")pickerOpen=false
            else if(action==="up")pickerIndex=Math.max(0,pickerIndex-1)
            else if(action==="down")pickerIndex=Math.min(pickerEntries.length-1,pickerIndex+1)
            else if(action==="primary")selectRegionEntry()
            return true
        }
        if(localePanelOpen && !keyboardOpen) {
            if(action==="cancel")localePanelOpen=false
            else if(action==="up" || action==="down")localePanelIndex=1-localePanelIndex
            else if(action==="primary")openKeyboard(localePanelIndex===0?"locale":"keyboard",false)
            return true
        }
        if(action==="secondary" && stepIndex!==3 && !keyboardOpen && !comboRecording && !storageProgressOpen && !(stepIndex===4&&!accountIconFocused&&(selectedIndex===3||selectedIndex===4))) {skipOptionalStep();return true}
        if (timezonePicker.item && timezonePicker.item.visible)
            return timezonePicker.item.handleControllerPressed(action)

        if (storageProgressOpen) {
            if (!backend() || backend().storageBusy)
                return true
            if (action === "primary" && storageProgressSuccess) {
                storageProgressOpen = false
                storageStepVisited = true
                setStep(6)
            } else if ((action === "primary" || action === "cancel") && !storageProgressSuccess) {
                storageProgressOpen = false
                forceActiveFocus()
            }
            return true
        }

        if (wifiModalOpen && !keyboardOpen) {
            if (wifiConnecting)
                return true
            if (action === "cancel") {
                wifiPassword = ""
                wifiModalOpen = false
                forceActiveFocus()
                return true
            }
            if (action === "up") wifiModalIndex = Math.max(0, wifiModalIndex - 1)
            else if (action === "down") wifiModalIndex = Math.min(wifiStepVisited?3:2, wifiModalIndex + 1)
            else if (action === "primary") {
                if (wifiModalIndex === 0) openKeyboard("wifiPassword", true)
                else if (wifiModalIndex === 1) wifiPasswordVisible = !wifiPasswordVisible
                else if (wifiModalIndex === 2) connectSelectedWifi()
                else {
                    wifiModalOpen = false
                    if (wifiConnectionState.indexOf("Connected") === 0) setStep(3)
                    else forceActiveFocus()
                }
            }
            return true
        }

        if (keyboardOpen) {
            if (action === "system") {
                if (!optionsHeld) {
                    optionsHeld = true
                    keyboard.pressEnter()
                }
                return true
            }
            keyboard.handleController(action)
            return true
        }

        if (stepTransitionRunning)
            return true

        if (comboRecording) {
            if (action === "cancel") {
                comboRecording = false
                comboStatus = "Recording cancelled"
                return true
            }
            if (action === "system") {
                finishComboRecording()
                return true
            }
            var token = comboToken(action)
            if (token.length > 0) {
                var target = comboConfirming ? comboSecond : comboFirst
                if (target.length < 10) target.push(token)
                comboStatus = target.join("  •  ")
                if (typeof controllerManager !== "undefined" && controllerManager &&
                        typeof controllerManager.hapticNavigation === "function")
                    controllerManager.hapticNavigation()
            }
            return true
        }

        if(experienceExtraPanel) {
            if(action==="cancel")experienceExtraPanel=false
            else if(action==="up")experienceExtraIndex=Math.max(0,experienceExtraIndex-1)
            else if(action==="down")experienceExtraIndex=Math.min(2,experienceExtraIndex+1)
            else if(action==="left"||action==="right"||action==="primary") {
                var extraDelta=action==="left"?-1:1
                if(experienceExtraIndex===0)screensaverIndex=(screensaverIndex+extraDelta+screensaverOptions.length)%screensaverOptions.length
                else if(experienceExtraIndex===1)launcherIndex=(launcherIndex+extraDelta+launcherOptions.length)%launcherOptions.length
                else privacyIndex=1-privacyIndex
                preferencesApplied=false
            }
            return true
        }
        if (action === "cancel") {
            if (stepIndex === 6 && recoveryConfirmOpen) recoveryConfirmOpen = false
            else if (stepIndex === 5 && storageConfirmOpen) storageConfirmOpen = false
            else if (stepIndex > 0) setStep(stepIndex - 1)
            return true
        }

        if (stepIndex === 0) {
            if (action === "primary" || action === "right") setStep(firstIncompleteStep())
            return true
        }

        if (stepIndex === 1) {
            if(action==="up")selectedIndex=Math.max(0,selectedIndex-1)
            else if(action==="down")selectedIndex=Math.min(3,selectedIndex+1)
            else if(action==="context")localePanelOpen=true
            else if(action==="primary") {
                if(selectedIndex===3)continueRegion()
                else openRegionPicker(selectedIndex)
            }
            return true
        }

        if (stepIndex === 2) {
            var wifi = (typeof networkManager !== "undefined" && networkManager)
                    ? networkManager.availableNetworks : []
            var wifiCount = wifi ? wifi.length : 0
            if (action === "up") selectedIndex = Math.max(0, selectedIndex - 1)
            else if (action === "down") selectedIndex = Math.min(wifiCount+1, selectedIndex + 1)
            else if (action === "context" && typeof networkManager !== "undefined" && networkManager)
                networkManager.requestScan()
            else if (action === "primary") {
                if (selectedIndex === wifiCount) {openHiddenWifi()}
                else if (selectedIndex > wifiCount) {
                    if(networkManager && String(networkManager.connectionState).toUpperCase()==="CONNECTED") {wifiStepVisited=true;if(recordOptional("network",false))setStep(3)}
                    else showNotice("Connect to Wi-Fi or press Square to skip",false)
                }
                else {
                    openWifiConnection(wifi[selectedIndex])
                }
            }
            return true
        }

        if (stepIndex === 3) {
            if (controllerContinueBusy) return true
            if (action === "primary" && registrationSession.verified) {
                controllerContinueBusy = true
                try {
                    if (backend() && backend().confirmControllerRegistration() && recordOptional("controller",false))
                        setStep(4)
                    else showNotice(backend() ? backend().lastError : "Setup service unavailable",true)
                } finally { controllerContinueBusy = false }
            } else if (action === "primary" || action === "context") registrationSession.begin()
            return true
        }

        if (stepIndex === 4) {
            if(action==="context"){openAvatarPicker();return true}
            if(action==="left"){accountIconFocused=true;return true}
            if(action==="right"){accountIconFocused=false;return true}
            if(accountIconFocused){if(action==="primary")openAvatarPicker();return true}
            var accountFields = ["hostname", "username", "displayName", "accountPassword",
                                 "confirmPassword", "combo", "continue"]
            if (action === "up") selectedIndex = Math.max(0, selectedIndex - 1)
            else if (action === "down") selectedIndex = Math.min(accountFields.length - 1, selectedIndex + 1)
            else if(action==="secondary" && (selectedIndex===3||selectedIndex===4))passwordVisible=!passwordVisible
            else if (action === "primary") {
                var accountField = accountFields[selectedIndex]
                if (accountField === "combo") beginComboRecording(comboFirst.length > 0)
                else if (accountField === "continue") {
                    if (accountApplied && comboConfigured) setStep(5)
                    else applyAccountAndCombo()
                } else openKeyboard(accountField,
                                    (accountField === "accountPassword" || accountField === "confirmPassword") && !passwordVisible)
            }
            return true
        }

        if (stepIndex === 5) {
            if (storageConfirmOpen) {
                if (action === "cancel") { storageConfirmOpen = false; return true }
                if (action === "up" || action === "down") selectedIndex = 1 - selectedIndex
                if (action === "primary") {
                    if (selectedIndex === 1) { storageConfirmOpen = false; return true }
                    var started = backend() && backend().provisionStorage(
                                String(storagePlan.fingerprint || ""))
                    storageConfirmOpen = false
                    if (started) {
                        storageProgressOpen = true
                        storageProgressSuccess = false
                        storageProgressMessage = "Validating installation drive"
                        storageProgressResult = ({})
                    } else showNotice(backend() ? backend().lastError : "Storage setup unavailable", true)
                }
                return true
            }
            if (action === "up" || action === "down") selectedIndex = 1 - selectedIndex
            else if (action === "context" && backend()) backend().refreshStoragePlan()
            else if (action === "primary") {
                if (selectedIndex === 1 || String(storagePlan.status || "") === "existing") {
                    storageStepVisited = true; setStep(6)
                } else if (String(storagePlan.status || "") === "available" ||
                           String(storagePlan.status || "") === "interrupted") {
                    storageConfirmOpen = true; selectedIndex = 0
                } else showNotice(backend() ? backend().lastError || "Storage layout is unsupported or too small" : "Storage setup unavailable", true)
            }
            return true
        }

        if (stepIndex === 6) {
            var targets = backend() ? backend().recoveryTargets : []
            if(recoveryConfirmOpen) {
                if(action!=="primary")return true
                recoveryConfirmOpen=false
                if(backend()&&targets.length&&backend().writeRecoveryDrive(String(targets[recoveryIndex].mountPath||""))) {
                    recoverySkipped=false;recordOptional("recovery",false);showNotice("Recovery bundle saved",false)
                } else showNotice(backend()?backend().lastError:"No removable drive is mounted",true)
                return true
            }
            if(action==="up")recoveryActionIndex=Math.max(0,recoveryActionIndex-1)
            else if(action==="down")recoveryActionIndex=Math.min(3,recoveryActionIndex+1)
            else if(action==="context"&&backend())backend().refreshRecoveryTargets()
            else if(action==="primary") {
                if(recoveryActionIndex===0)copyRecoveryKey()
                else if(recoveryActionIndex===1&&targets.length)recoveryIndex=(recoveryIndex+1)%targets.length
                else if(recoveryActionIndex===2) {
                    if(targets.length)recoveryConfirmOpen=true
                    else showNotice("Mount a removable drive before saving a recovery bundle",false)
                } else if(recoveryActionIndex===3) {
                    if(!backend()||!backend().recoveryCode.length)showNotice("Recovery key generation is not ready",true)
                    else {recoverySkipped=false;if(recordOptional("recovery",false))setStep(7)}
                }
            }
            return true
        }

        if (stepIndex === 7) {
            if(action==="left"){securityPanel="left";return true}
            if(action==="right"){securityPanel="right";return true}
            if(securityPanel==="left") {
                if(action==="up")selectedIndex=Math.max(0,selectedIndex-1)
                else if(action==="down")selectedIndex=Math.min(8,selectedIndex+1)
                else if(action==="primary"){if(selectedIndex===8)setStep(8);else {securityPanel="right";securityChoiceIndex=securityProfileIndex}}
                return true
            }
            if(selectedIndex===0) {
                if(action==="up")securityChoiceIndex=Math.max(0,securityChoiceIndex-1)
                else if(action==="down")securityChoiceIndex=Math.min(2,securityChoiceIndex+1)
                else if(action==="primary")securityProfileIndex=securityChoiceIndex
            } else if(selectedIndex===8) {if(action==="primary")setStep(8)}
            else if(action==="primary"&&securityProfileIndex===2) {
                if(selectedIndex===1){securityLearningMode=!securityLearningMode;if(securityLearningMode)securityEnforcementEnabled=false}
                else if(selectedIndex===2){securityEnforcementEnabled=!securityEnforcementEnabled;if(securityEnforcementEnabled)securityLearningMode=false}
                else if(selectedIndex===3)securityResponseEngineEnabled=!securityResponseEngineEnabled
                else if(selectedIndex===4)securityBackgroundScanEnabled=!securityBackgroundScanEnabled
                else if(selectedIndex===5)securityHardeningIndex=(securityHardeningIndex+1)%securityHardeningOptions.length
                else if(selectedIndex===6)securitySeverityIndex=(securitySeverityIndex+1)%securitySeverityOptions.length
                else if(selectedIndex===7)securityBanIndex=(securityBanIndex+1)%securityBanOptions.length
            }
            return true
        }

        if(stepIndex===8) {
            if(action==="up")selectedIndex=Math.max(0,selectedIndex-1)
            else if(action==="down")selectedIndex=Math.min(7,selectedIndex+1)
            else if(action==="context")experienceExtraPanel=true
            else if(action==="left"||action==="right"||action==="primary") {
                var delta=action==="left"?-1:1
                var outputs=typeof musicPlayerManager!=="undefined"&&musicPlayerManager?musicPlayerManager.audioOutputs:[]
                if(selectedIndex===0&&outputs&&outputs.length)audioIndex=(audioIndex+delta+outputs.length)%outputs.length
                else if(selectedIndex===1)showNotice("Video uses the active compositor display mode",false)
                else if(selectedIndex===2)performanceIndex=(performanceIndex+delta+performanceOptions.length)%performanceOptions.length
                else if(selectedIndex===3)sshEnabledOnFinish=!sshEnabledOnFinish
                else if(selectedIndex===4)remoteControllerEnabled=!remoteControllerEnabled
                else if(selectedIndex===5)displayConfirmed=!displayConfirmed
                else if(selectedIndex===6)dashboardTabIndex=(dashboardTabIndex+delta+dashboardTabOptions.length)%dashboardTabOptions.length
                else if(selectedIndex===7&&action==="primary") {
                    if(applyPreferences()){preferencesApplied=true;setStep(9)}
                    else showNotice(backend()?backend().lastError:"Unable to apply preferences",true)
                    return true
                }
                preferencesApplied=false
            }
            return true
        }

        if (stepIndex === 9) {
            if (action === "primary") finishWizard()
            return true
        }
        return true
    }

    function handleControllerReleased(value) {
        if (normalize(value) === "system")
            optionsHeld = false
        if (keyboard && typeof keyboard.handleControllerReleased === "function")
            keyboard.handleControllerReleased(value)
        return visible
    }

    Component.onCompleted: {
        if (backend()) backend().refresh()
        if (typeof clockSettingsManager !== "undefined" && clockSettingsManager)
            timezone = String(clockSettingsManager.timezone || "UTC")
        forceActiveFocus()
    }

    Connections {
        target: (typeof setupWizardManager !== "undefined") ? setupWizardManager : null
        function onIdentityApplied(success, resolvedUsername, message) {
            accountBusy = false
            if (!success) {
                showNotice("Unable to create your account.", true, message)
                return
            }
            username = resolvedUsername
            accountApplied = true
            if (typeof userManager !== "undefined" && userManager) {
                userManager.refreshUsers()
                userManager.setActiveUserByName(username)
                if(root.selectedAvatar.length && typeof userManager.setAvatar==="function")userManager.setAvatar(root.selectedAvatar)
            }
            if (typeof securityManager !== "undefined" && securityManager) {
                securityManager.setActiveUsername(username)
                if (!securityManager.authorizeFreshSetupIdentity(username)) {
                    showNotice(String(securityManager.lastError || "Unable to authorize passcode setup"), true)
                    return
                }
                var combo = comboFirst.join("|")
                if (!securityManager.beginLoginComboCreation(username, combo, combo))
                    showNotice(String(securityManager.lastError || "Unable to create controller passcode"), true)
            }
        }
        function onBluetoothOperationFinished(success, message) {
            showNotice(message, !success)
            if (success && backend().controllerPaired) bluetoothStage = 3
        }
    }

    Connections {
        target: (typeof securityManager !== "undefined") ? securityManager : null
        function onLocalPasswordVerificationFinished(success, message, purpose) {
            if (purpose !== "setup") return
            if (!success) {
                showNotice(message, true)
                return
            }
            var combo = comboFirst.join("|")
            if (!securityManager.beginLoginComboCreation(username, combo, combo))
                showNotice(String(securityManager.lastError || "Unable to create controller passcode"), true)
        }
        function onLoginComboCreationFinished(success, message) {
            comboConfigured = success
            comboStatus = success ? "Controller passcode configured" : message
            if (success) {
                accountPassword = ""
                confirmPassword = ""
                passwordVisible = false
            }
            showNotice(message, !success)
            if (success) setStep(5)
        }
    }

    Connections {
        target: (typeof networkManager !== "undefined") ? networkManager : null
        function onOperationFinished(operation, success, message) {
            if (root.stepIndex !== 2) return
            if (String(operation).toLowerCase().indexOf("connect") < 0) return
            if (!success) {
                root.finishWifiVerification(false, String(message || "Wi-Fi connection failed"))
                return
            }
            root.wifiConnectionState = "Connection accepted. Verifying network access…"
            root.wifiVerificationTicks = 0
            wifiVerifyTimer.restart()
            if (success)
                root.wifiPassword = ""
        }
    }

    Timer {
        id: wifiVerifyTimer
        interval: 500
        repeat: true
        onTriggered: {
            if (!root.wifiConnecting || !root.wifiModalOpen) { stop(); return }
            root.wifiVerificationTicks += 1
            var backend = (typeof networkManager !== "undefined") ? networkManager : null
            var state = backend ? String(backend.connectionState || "").toUpperCase() : ""
            var activeSsid = backend ? String(backend.connectedSsid || "") : ""
            var wantedSsid = String(root.selectedWifi.ssid || "")
            if (state === "CONNECTED" && activeSsid === wantedSsid) {
                root.finishWifiVerification(true, "Connected and verified: " + wantedSsid)
            } else if (state === "FAILED") {
                root.finishWifiVerification(false, "Authentication failed or NetworkManager rejected the credentials. Re-enter the password and try again.")
            } else if (root.wifiVerificationTicks >= 60) {
                root.finishWifiVerification(false, "Connection timed out before NetworkManager verified the selected network.")
            }
        }
    }

    ControllerRegistrationSession {
        id: registrationSession
        active: root.visible && root.stepIndex===3
        controller: typeof controllerManager!=="undefined"?controllerManager:null
        function reconcile() {
            root.bluetoothCandidate=state
            root.bluetoothStage = verified ? 3 : 0
        }
        onStateChanged: Qt.callLater(reconcile)
        onVerifiedChanged: reconcile()
    }
    ControllerRegistrationSession {
        id: connectionSession
        active: root.visible && root.stepIndex===8
        registrationEnabled: false
        controller: typeof controllerManager!=="undefined"?controllerManager:null
    }
    readonly property string controllerConnectionLabel: connectionSession.connectionLabel
    readonly property var simulatedSecurity: ScoreSimulation.preview(["Balanced","Strict","Custom"][securityProfileIndex],[],0,"SECURE")

    Connections {
        target: root.backend()
        ignoreUnknownSignals: true
        function onStorageProgress(stage, message) {
            root.storageProgressMessage = String(message || stage || "Working…")
        }
        function onStorageProvisioningFinished(success, result, message) {
            root.storageProgressSuccess = success === true
            root.storageProgressResult = result || ({})
            root.storageProgressMessage = success
                    ? "Complete"
                    : String(message || "Storage provisioning failed")
        }
    }

    Loader {
        id: timezonePicker
        anchors.fill: parent
        z: 61000
        active: false
        source: "modals/system/TimezonePickerModal.qml"
    }
    Connections {
        target: timezonePicker.item
        function onTimezoneSelected(zoneId) { root.timezone = String(zoneId) }
    }

    Timer {
        id: noticeTimer
        interval: 5000
        onTriggered: { root.notice = ""; root.noticeDetail = "" }
    }

    GeminiSetupPages {id:setupPages;anchors.fill:parent;wizard:root;quality:renderQuality}
    Item {id:controllerGuide;anchors.bottom:parent.bottom;height:38;width:parent.width}
    Loader {
        id:fractureLoader;anchors.fill:parent;z:65000;active:false
        sourceComponent:Component {
            GeminiFracture {
                quality:renderQuality
                onFinished:{root.fractureActive=false;root.completed()}
            }
        }
    }

    Rectangle {
        visible: root.notice.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: controllerGuide.top
        anchors.bottomMargin: 12
        width: Math.min(parent.width - 160, root.noticeDetail.length ? 900 : 460)
        height: root.noticeDetail.length > 0 ? 90 : 44
        radius: 20
        color: root.noticeError ? "#5B1720" : "#0E4B35"
        border.width: 2
        border.color: root.noticeError ? "#FF6472" : "#63F0A1"
        z: 1000
        Column {
            anchors.centerIn: parent
            width: parent.width - 40
            spacing: 5
            Text { width: parent.width; text: root.notice; color: "white"; font.pixelSize: 18; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
            Text { visible: root.noticeDetail.length > 0; width: parent.width; text: root.noticeDetail; color: "#FFD6DA"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
        }
    }

    Rectangle {
        visible: root.storageProgressOpen
        anchors.fill: parent
        color: "#E8000208"
        z: 1900
    }
    Rectangle {
        visible: root.storageProgressOpen
        anchors.centerIn: parent
        width: Math.min(parent.width - 130, 1040)
        height: 520
        radius: 34
        color: "#F4071426"
        border.width: 2
        border.color: root.storageProgressSuccess ? "#22FF88" : ((root.backend() && root.backend().storageBusy) ? root.focusCyan : "#FF6472")
        z: 1901
        Column {
            anchors.fill: parent; anchors.margins: 42; spacing: 24
            Text { width:parent.width; text:"USER DATA STORAGE"; color:"white"; font.pixelSize:32; font.bold:true; horizontalAlignment:Text.AlignHCenter }
            Item {
                anchors.horizontalCenter:parent.horizontalCenter; width:96; height:96
                Rectangle { anchors.centerIn:parent; width:82; height:82; radius:41; color:"transparent"; border.width:7; border.color:"#24445E" }
                Rectangle { anchors.top:parent.top; anchors.horizontalCenter:parent.horizontalCenter; width:18; height:18; radius:9; color:root.storageProgressSuccess?"#22FF88":root.focusCyan
                    RotationAnimation on rotation { from:0; to:360; duration:1100; loops:Animation.Infinite; running:root.storageProgressOpen&&root.backend()&&root.backend().storageBusy }
                    transformOrigin:Item.Bottom
                }
            }
            Text { width:parent.width; text:root.storageProgressMessage; color:root.storageProgressSuccess?"#22FF88":"#CBE9FF"; font.pixelSize:22; font.bold:true; wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter }
            Text {
                width:parent.width; visible:root.storageProgressSuccess
                text:"Verified capacity: "+root.storageSize(root.storageProgressResult.availableBytes)+"\nMount location: "+String(root.storageProgressResult.mountpoint||"/srv/neutronos/user-data")
                color:"#DCEEFF"; font.pixelSize:18; wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter
            }
            Text { width:parent.width; visible:root.backend()&&root.backend().storageBusy; text:"Do not remove power or the installation drive. This window cannot be dismissed while storage is being modified."; color:"#FFDCA1"; font.pixelSize:15; wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter }
            Rectangle {
                visible:root.backend()&&!root.backend().storageBusy
                anchors.horizontalCenter:parent.horizontalCenter; width:330; height:64; radius:20
                color:root.storageProgressSuccess?"#155D3A":"#4B1820"; border.width:2; border.color:root.storageProgressSuccess?"#22FF88":"#FF6472"
                Text { anchors.centerIn:parent; text:root.storageProgressSuccess?"X  CONTINUE":"X  RETURN TO STORAGE"; color:"white"; font.pixelSize:18; font.bold:true }
            }
        }
    }

    Rectangle {
        visible: root.keyboardOpen
        anchors.fill: parent
        color: "#D9000000"
        z: 2000
    }

    Rectangle {
        visible: root.keyboardOpen
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        width: Math.min(parent.width - 70, 1740)
        height: Math.min(parent.height - 80, 760)
        radius: 30
        color: "#071321"
        border.width: 2
        border.color: root.neutronRed
        z: 2001

        Column {
            anchors.fill: parent; anchors.margins: 20; spacing: 12
            Text {
                width: parent.width
                text: (root.keyboardField === "wifiPassword" ? "PASSWORD: " : "VALUE: ") +
                      (root.keyboardSecret ? (root.fieldValue(root.keyboardField).length > 0 ? "••••••••" : "")
                                           : root.fieldValue(root.keyboardField))
                color: "white"; font.pixelSize: 20; font.bold: true; elide: Text.ElideRight
            }
            VirtualKeyboard {
                id: keyboard
                width: parent.width
                height: parent.height - 48
                visibleMode: root.keyboardOpen
                active: root.keyboardOpen
                largeMode: true
                cancelBehavior: "close"
                title: "Setup Keyboard"
                onKeyPressed: function(value) { root.appendKeyboard(value) }
                onBackspacePressed: {
                    var current = root.fieldValue(root.keyboardField)
                    root.setFieldValue(root.keyboardField, current.substring(0, Math.max(0, current.length - 1)))
                }
                onEnterPressed: root.closeKeyboard()
                onClosePressed: root.closeKeyboard()
            }
        }
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Up) action = "up"
        else if (event.key === Qt.Key_Down) action = "down"
        else if (event.key === Qt.Key_Left) action = "left"
        else if (event.key === Qt.Key_Right) action = "right"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) action = "cancel"
        else if (event.key === Qt.Key_F5) action = "context"
        else if (event.key === Qt.Key_F6) action = "secondary"
        else if (event.key === Qt.Key_Menu) action = "system"
        if (action.length > 0) {
            event.accepted = true
            root.handleControllerPressed(action)
        }
    }
}
