import QtQuick 2.15

Rectangle {
    id: root
    property var contextData: ({})
    property var modalContext: ({})
    property var controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
    property var settingsBackend: (typeof settingsManager !== "undefined") ? settingsManager : null
    property bool setupPresentation: false

    property int focusIndex: 0
    property int inactivityMinutes: 15
    readonly property var inactivityOptions: [0, 5, 15, 30, 60]
    property string detectedTransport: "unknown"
    property bool bridgeAvailable: false
    property bool bridgeRequestPending: false
    property bool registrationRequestPending: false
    property bool registrationPollPending: false
    property var registration: ({})
    property string pairingStage: "idle"
    property string statusMessage: "Connect the controller over USB and press Register to begin guided Bluetooth pairing."

    readonly property color panel: "#071426"
    readonly property color raised: "#0B1A30"
    readonly property color inset: "#06101F"
    readonly property color cobalt: "#0047AB"
    readonly property color neonGreen: "#39FF88"
    readonly property color cyan: "#7DF9FF"
    readonly property color red: "#FF3048"
    readonly property color amber: "#FFD45A"
    readonly property color textPrimary: "#F4FBFF"
    readonly property color textMuted: "#8AA6C8"

    readonly property bool controllerConnected: backendBool("controllerConnected", false)
    readonly property bool controllerCharging: backendBool("controllerCharging", false)
    readonly property bool bluetoothConnected: controllerConnected && detectedTransport === "bluetooth"
    readonly property bool usbConnected: controllerConnected && detectedTransport === "usb"
    readonly property int batteryPercent: backendNumber("controllerBatteryPercent", -1)

    signal closed()
    signal actionRequested(string action, var payload)

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    Keys.enabled: visible
    color: setupPresentation ? "#00000000" : "#D5000207"
    z: 999

    function backendBool(name, fallbackValue) {
        try { return controllerBackend && controllerBackend[name] !== undefined ? controllerBackend[name] === true : fallbackValue }
        catch (error) { return fallbackValue }
    }
    function backendString(name, fallbackValue) {
        try {
            if (controllerBackend && controllerBackend[name] !== undefined) {
                var value = String(controllerBackend[name] || "").trim()
                return value.length ? value : fallbackValue
            }
        } catch (error) {}
        return fallbackValue
    }
    function backendNumber(name, fallbackValue) {
        try {
            if (controllerBackend && controllerBackend[name] !== undefined) {
                var value = Number(controllerBackend[name])
                if (!isNaN(value)) return value
            }
        } catch (error) {}
        return fallbackValue
    }
    function controllerName() {
        return backendString("controllerDisplayName", backendString("controllerName", "Controller"))
    }
    function inputEventName() {
        var match = /(?:^|\/)event([0-9]{1,5})$/.exec(backendString("controllerDevicePath", ""))
        return match ? "event" + match[1] : ""
    }
    function transportLabel() {
        if (!controllerConnected) return "OFFLINE"
        if (usbConnected) return "USB / WIRED"
        if (bluetoothConnected) return "BLUETOOTH"
        return "CONNECTED • TRANSPORT UNVERIFIED"
    }
    function transportColor() {
        return bluetoothConnected ? neonGreen : controllerConnected ? cobalt : red
    }
    function applyRegistration(state) {
        if (!state) return
        registration = state
        pairingStage = String(state.phase || "idle")
        if (!registrationRequestPending || pairingStage === "connected")
            statusMessage = String(state.message || "Controller registration is unavailable.")
    }
    function requestControllerStatus() {
        if (!visible || bridgeRequestPending) return
        bridgeRequestPending = true
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return
            root.bridgeRequestPending = false
            if (!root.visible) return
            if (xhr.status !== 200) {
                root.bridgeAvailable = false
                root.detectedTransport = "unknown"
                root.statusMessage = "Controller registration service unavailable."
                return
            }
            try {
                var state = JSON.parse(String(xhr.responseText || "{}"))
                root.bridgeAvailable = true
                root.detectedTransport = state.transport === "usb" ? "usb" :
                                         state.transport === "bluetooth" ? "bluetooth" : "unknown"
            } catch (error) { root.bridgeAvailable = false; root.detectedTransport = "unknown" }
        }
        xhr.open("GET", "http://127.0.0.1:48173/status?device=" + encodeURIComponent(inputEventName()), true)
        xhr.send()
        requestRegistrationStatus()
    }
    function requestRegistrationStatus() {
        // A periodic poll cannot overwrite the result of an active registration.
        if (!visible || registrationPollPending || registrationRequestPending) return
        registrationPollPending = true
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return
            root.registrationPollPending = false
            if (!root.visible) return
            if (xhr.status === 200) {
                try { root.applyRegistration(JSON.parse(String(xhr.responseText || "{}"))) }
                catch (error) {}
            }
        }
        xhr.open("GET", "http://127.0.0.1:48173/registration", true)
        xhr.send()
    }
    function registerCurrentUsbController() {
        if (registrationRequestPending) return false
        if (["waiting_disconnect", "scanning", "bonding", "trusting", "connecting"].indexOf(pairingStage) !== -1) return true
        if (!bridgeAvailable || !usbConnected || !inputEventName().length) {
            pairingStage = "error"
            statusMessage = "Connect a supported PlayStation controller with a USB data cable first."
            return false
        }
        registrationRequestPending = true
        statusMessage = "Reading the connected controller's hardware address…"
        var xhr = new XMLHttpRequest()
        xhr.timeout = 23000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return
            root.registrationRequestPending = false
            if (!root.visible) return
            var response = ({})
            try { response = JSON.parse(String(xhr.responseText || "{}")) }
            catch (error) {}
            if (xhr.status === 200 && response.address) {
                root.applyRegistration(response)
            } else {
                root.pairingStage = "error"
                root.statusMessage = response.error ? String(response.error) :
                    xhr.status === 0 ? "Registration request could not reach the local bridge. Check bridge status; USB data was not saved." :
                    "Registration failed (HTTP " + String(xhr.status) + "). Reopen the modal and retry."
            }
        }
        xhr.open("POST", "http://127.0.0.1:48173/register", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("X-Neutron-Controller", "register-usb-v1")
        xhr.send(JSON.stringify({ event: inputEventName() }))
        return true
    }
    function loadInactivityMinutes() {
        var current = 15
        try {
            if (settingsBackend && typeof settingsBackend.value === "function")
                current = Number(settingsBackend.value("controller.bluetoothInactivityMinutes", 15))
        } catch (error) {}
        if (isNaN(current)) current = 15
        var best = inactivityOptions[0]
        for (var i = 1; i < inactivityOptions.length; ++i)
            if (Math.abs(inactivityOptions[i] - current) < Math.abs(best - current)) best = inactivityOptions[i]
        inactivityMinutes = best
    }
    function adjustInactivity(delta) {
        var currentIndex = inactivityOptions.indexOf(inactivityMinutes)
        inactivityMinutes = inactivityOptions[Math.max(0, Math.min(inactivityOptions.length - 1, currentIndex + delta))]
        try {
            if (settingsBackend && typeof settingsBackend.queueChange === "function") {
                settingsBackend.queueChange("controller.bluetoothInactivityMinutes", inactivityMinutes, "immediate")
                if (typeof settingsBackend.applyPending === "function") settingsBackend.applyPending()
            }
        } catch (error) {}
    }
    function inactivityLabel() { return inactivityMinutes <= 0 ? "OFF" : String(inactivityMinutes) + " MIN" }
    function powerDownController() {
        if (!bluetoothConnected) {
            statusMessage = "Power Down is available only over Bluetooth."
            return false
        }
        try {
            if (controllerBackend && typeof controllerBackend.powerOffController === "function") {
                controllerBackend.powerOffController()
                statusMessage = "Powering down controller…"
                powerDownCloseDelay.restart()
                return true
            }
        } catch (error) {}
        statusMessage = "Controller power down failed."
        return false
    }
    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        focusIndex = 0
        bridgeAvailable = false
        registrationRequestPending = false
        detectedTransport = "unknown"
        pairingStage = "idle"
        statusMessage = "Checking USB controller and saved Bluetooth registration…"
        loadInactivityMinutes()
        visible = true
        forceActiveFocus()
        requestControllerStatus()
    }
    function openModal(context) { open(context) }
    function close() { powerDownCloseDelay.stop(); visible = false; closed() }
    function closeModal() { close() }
    function cancelSetupRegistration() {
        if (!setupPresentation || ["waiting_disconnect", "scanning", "bonding", "trusting", "connecting"].indexOf(pairingStage) === -1) {
            close()
            return true
        }
        if (registrationRequestPending)
            return true
        registrationRequestPending = true
        statusMessage = "Cancelling this registration attempt…"
        var xhr = new XMLHttpRequest()
        xhr.timeout = 6000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return
            root.registrationRequestPending = false
            if (xhr.status === 200) {
                try { root.applyRegistration(JSON.parse(String(xhr.responseText || "{}"))) }
                catch (error) {}
                root.close()
            } else {
                root.pairingStage = "error"
                root.statusMessage = "Cancellation could not reach the local controller service. Retry or wait for the active attempt to finish."
            }
        }
        xhr.open("POST", "http://127.0.0.1:48173/cancel", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("X-Neutron-Controller", "register-usb-v1")
        xhr.send("{}")
        return true
    }
    function activateFocused() {
        if (focusIndex === 0) return registerCurrentUsbController()
        if (setupPresentation && focusIndex === 2) return cancelSetupRegistration()
        if (focusIndex === 1) return powerDownController()
        if (focusIndex === 3) { adjustInactivity(1); return true }
        close()
        return true
    }
    function handleControllerPressed(button) {
        if (!visible) return false
        var action = String(button || "").trim().toLowerCase()
        if (action === "cancel" || action === "circle" || action === "o" || action === "b") {
            if (setupPresentation)
                return cancelSetupRegistration()
            close()
            return true
        }
        if (setupPresentation && (action === "left" || action === "up" ||
                                  action === "right" || action === "down")) {
            focusIndex = focusIndex === 0 ? 2 : 0
            return true
        }
        if (focusIndex === 3 && (action === "left" || action === "right")) {
            adjustInactivity(action === "left" ? -1 : 1); return true
        }
        if (action === "left" || action === "up") { focusIndex = Math.max(0, focusIndex - 1); return true }
        if (action === "right" || action === "down") { focusIndex = Math.min(3, focusIndex + 1); return true }
        if (action === "primary" || action === "x" || action === "a" || action === "cross") return activateFocused()
        if (action === "context" || action === "triangle" || action === "y") return registerCurrentUsbController()
        return true
    }
    function handleControllerReleased(button) { return visible }

    Timer { id: statusRefreshTimer; interval: 1500; running: root.visible; repeat: true; onTriggered: root.requestControllerStatus() }
    Timer { id: powerDownCloseDelay; interval: 250; repeat: false; onTriggered: root.close() }

    Rectangle {
        id: modalPanel
        anchors.top: parent.top
        anchors.topMargin: root.setupPresentation ? 122 : 96
        anchors.right: parent.right
        anchors.rightMargin: root.setupPresentation ? 46 : 28
        width: root.setupPresentation ? parent.width - 92 : Math.min(parent.width * 0.50, 920)
        height: root.setupPresentation ? parent.height - 212 : Math.min(parent.height - 118, 690)
        radius: root.setupPresentation ? 24 : 30
        color: "#F4071426"
        border.width: 2
        border.color: root.pairingStage === "error" ? root.red : root.cobalt
        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 13
            Row {
                width: parent.width; height: 66; spacing: 16
                Rectangle {
                    width: 58; height: 58; radius: 18
                    color: root.bluetoothConnected ? "#103524" : root.inset
                    border.width: 2; border.color: root.transportColor()
                    Text {
                        anchors.centerIn: parent
                        text: root.bluetoothConnected ? "ᛒ" : root.usbConnected ? "USB" : "?"
                        color: root.bluetoothConnected ? root.neonGreen : root.usbConnected ? root.cyan : root.amber
                        font.pixelSize: root.usbConnected ? 14 : 23; font.bold: true
                    }
                }
                Column {
                    width: parent.width - 76; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    Text { text: "CONTROLLER CONNECTION"; color: root.textPrimary; font.pixelSize: 24; font.bold: true }
                    Text { text: "USB → unplug → exact MAC scan → pair → trust → connect"; color: root.textMuted; font.pixelSize: 12; font.bold: true }
                }
            }
            Rectangle { width: parent.width; height: 1; color: "#294866" }
            Rectangle {
                width: parent.width; height: 90; radius: 18; color: root.inset
                border.width: 1; border.color: "#284767"
                Row {
                    anchors.fill: parent; anchors.margins: 16; spacing: 22
                    Column {
                        width: parent.width * 0.48; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { width: parent.width; text: root.controllerName(); color: root.textPrimary; font.pixelSize: 20; font.bold: true; elide: Text.ElideRight }
                        Text { text: root.transportLabel(); color: root.transportColor(); font.pixelSize: 13; font.bold: true }
                    }
                    Rectangle { width: 1; height: 50; anchors.verticalCenter: parent.verticalCenter; color: "#294866" }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { text: "BATTERY"; color: root.textMuted; font.pixelSize: 10; font.bold: true }
                        Text { text: root.batteryPercent >= 0 ? String(Math.round(root.batteryPercent)) + "%" : "--%"; color: root.controllerCharging ? root.neonGreen : root.cyan; font.pixelSize: 21; font.bold: true }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 166; radius: 18; color: root.pairingStage === "connected" ? "#102E25" : root.raised
                border.width: 1; border.color: root.pairingStage === "error" ? root.red : root.pairingStage === "connected" ? root.neonGreen : "#315D86"
                Column {
                    anchors.fill: parent; anchors.margins: 16; spacing: 8
                    Text {
                        text: root.pairingStage === "connected" ? "CONTROLLER BONDED + TRUSTED" :
                              root.pairingStage === "error" ? "REGISTRATION NEEDS ATTENTION" :
                              root.pairingStage === "waiting_disconnect" ? "UNPLUG CONTROLLER • ENTER PAIRING MODE" :
                              root.pairingStage === "scanning" ? "SCANNING FOR SAVED MAC" :
                              root.pairingStage === "bonding" ? "CREATING BLUETOOTH BOND" :
                              root.pairingStage === "trusting" ? "TRUSTING CONTROLLER" :
                              root.pairingStage === "connecting" ? "CONNECTING CONTROLLER" :
                              root.pairingStage === "registered" ? "CONTROLLER MAC SAVED" : "CONTROLLER REGISTRATION"
                        color: root.pairingStage === "error" ? root.red : root.pairingStage === "connected" ? root.neonGreen : root.cyan
                        font.pixelSize: 14; font.bold: true
                    }
                    Text { width: parent.width; text: root.statusMessage; color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap }
                    Text {
                        width: parent.width
                        text: root.registration.address ? "SAVED CONTROLLER: " + String(root.registration.name || "PlayStation Controller") + "  •  " + root.registration.address : "NO SAVED BLUETOOTH CONTROLLER"
                        color: root.registration.address ? root.cyan : root.textMuted
                        font.pixelSize: 11; font.bold: true; elide: Text.ElideRight
                    }
                    Text {
                        text: "PAIRED " + (root.registration.paired ? "YES" : "NO") + "  •  TRUSTED " + (root.registration.trusted ? "YES" : "NO") + "  •  CONNECTED " + (root.registration.connected ? "YES" : "NO")
                        color: root.registration.connected && root.registration.trusted && root.registration.paired ? root.neonGreen : root.textMuted
                        font.pixelSize: 10; font.bold: true
                    }
                }
            }
            Row {
                width: parent.width; height: 54; spacing: 9
                Rectangle {
                    width: root.setupPresentation ? (parent.width - 9) / 2 : (parent.width - 18) / 3; height: 52; radius: 15
                    color: root.focusIndex === 0 ? "#17365D" : root.inset
                    border.width: root.focusIndex === 0 ? 2 : 1
                    border.color: root.focusIndex === 0 ? root.neonGreen : "#294866"
                    Text { anchors.centerIn: parent; text: root.registrationRequestPending ? "READING USB…" :
                          (root.pairingStage === "waiting_disconnect" || root.pairingStage === "scanning" || root.pairingStage === "bonding" || root.pairingStage === "trusting" || root.pairingStage === "connecting") ? "REGISTRATION RUNNING" : "REGISTER CONTROLLER"; color: root.textPrimary; font.pixelSize: 11; font.bold: true }
                    MouseArea { anchors.fill: parent; enabled: !root.registrationRequestPending; onClicked: { root.focusIndex = 0; root.activateFocused() } }
                }
                Rectangle {
                    visible: !root.setupPresentation
                    width: (parent.width - 18) / 3; height: 52; radius: 15
                    color: root.focusIndex === 1 ? "#35131A" : root.inset
                    opacity: root.bluetoothConnected ? 1 : 0.38
                    border.width: root.focusIndex === 1 ? 2 : 1
                    border.color: root.focusIndex === 1 ? root.red : "#294866"
                    Text { anchors.centerIn: parent; text: "POWER DOWN"; color: root.textPrimary; font.pixelSize: 11; font.bold: true }
                    MouseArea { anchors.fill: parent; enabled: root.bluetoothConnected; onClicked: { root.focusIndex = 1; root.activateFocused() } }
                }
                Rectangle {
                    width: root.setupPresentation ? (parent.width - 9) / 2 : (parent.width - 18) / 3; height: 52; radius: 15
                    color: root.focusIndex === 2 ? "#35131A" : root.inset
                    border.width: root.focusIndex === 2 ? 2 : 1
                    border.color: root.focusIndex === 2 ? root.red : "#294866"
                    Text { anchors.centerIn: parent; text: root.setupPresentation
                                  ? (root.pairingStage === "connected" ? "CONTINUE" : "CANCEL / RETURN")
                                  : "CLOSE"; color: root.textPrimary; font.pixelSize: 11; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: { root.focusIndex = 2; root.activateFocused() } }
                }
            }
            Rectangle {
                visible: !root.setupPresentation
                width: parent.width; height: 54; radius: 15
                color: root.focusIndex === 3 ? "#102C36" : root.inset
                border.width: root.focusIndex === 3 ? 2 : 1
                border.color: root.focusIndex === 3 ? root.neonGreen : "#294866"
                Row {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; width: parent.width - 145; spacing: 2
                        Text { text: "BLUETOOTH INACTIVITY POWER DOWN"; color: root.textPrimary; font.pixelSize: 11; font.bold: true }
                        Text { text: "Turns off a Bluetooth controller after no input."; color: root.textMuted; font.pixelSize: 10 }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "‹  " + root.inactivityLabel() + "  ›"; color: root.neonGreen; font.pixelSize: 13; font.bold: true }
                }
                MouseArea { anchors.fill: parent; onClicked: root.focusIndex = 3 }
            }
            Text {
                width: parent.width
                text: "1. USB + REGISTER  •  2. UNPLUG + SHARE/CREATE + PS  •  3. AUTO PAIR + TRUST + CONNECT"
                color: root.textMuted; font.pixelSize: 10; font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
