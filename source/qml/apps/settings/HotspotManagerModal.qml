import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible

    property var networkBackend: null
    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color panelInset: "#06101F"
    property color textPrimary: "#F4FBFF"
    property color textSecondary: "#C8D5DF"
    property color textMuted: "#8AA6C8"
    property color divider: "#1D3958"
    property color focusBlue: "#4DA6FF"
    property color cyan: "#7DF9FF"
    property color success: "#22FF88"
    property color warning: "#F5C542"
    property color danger: "#FF3040"

    property bool visibleMode: false
    property int focusIndex: 0
    property int outputIndex: 0 // 0 Wi-Fi, 1 Ethernet
    property string ssidDraft: "NeutronOS"
    property string securityDraft: "wpa2"
    property int maxConnectionsDraft: 8
    property string passwordDraft: ""
    property string statusText: ""
    property bool statusError: false

    signal keyboardRequested(string target, string initialValue, string title)
    signal statusChanged(string message, bool error)
    signal closed()

    readonly property var state: networkBackend && networkBackend.offlineNetworkState
                                 ? networkBackend.offlineNetworkState : ({})
    readonly property string outputKind: outputIndex === 0 ? "wifi" : "lan"
    readonly property var outputState: outputKind === "wifi"
                                       ? (state.wifi || ({})) : (state.lan || ({}))
    readonly property bool hotspotActive: String(state.mode || "normal-wifi") ===
                                          (outputIndex === 0 ? "wifi-hotspot" : "lan-hotspot")
    readonly property var clients: outputState && outputState.leases ? outputState.leases : []
    readonly property int maxFocus: outputIndex === 0 ? 7 : 4

    function openModal() {
        visibleMode = true
        focusIndex = 0
        var currentMode = String(state.mode || "normal-wifi")
        outputIndex = currentMode === "lan-hotspot" ? 1 : 0
        syncFromState()
        if (networkBackend && typeof networkBackend.refreshOfflineNetwork === "function")
            networkBackend.refreshOfflineNetwork()
        forceActiveFocus()
    }

    function closeModal() {
        visibleMode = false
        statusText = ""
        statusError = false
        closed()
    }

    function syncFromState() {
        var s = state || ({})
        var wifi = s.wifi || ({})
        if (String(wifi.ssid || "").length > 0) ssidDraft = String(wifi.ssid)
        securityDraft = String(wifi.security || "wpa2").toLowerCase() === "wpa3" ? "wpa3" : "wpa2"
        var targetState = outputIndex === 0 ? wifi : (s.lan || ({}))
        var maxValue = Number(targetState.maxConnections || 8)
        maxConnectionsDraft = isNaN(maxValue) ? 8 : Math.max(1, Math.min(64, Math.round(maxValue)))
    }

    function setStatus(message, error) {
        statusText = String(message || "")
        statusError = error === true
        statusChanged(statusText, statusError)
    }

    function requestRefresh() {
        if (!networkBackend || typeof networkBackend.refreshOfflineNetwork !== "function") {
            setStatus("Hotspot backend is unavailable.", true)
            return false
        }
        var ok = networkBackend.refreshOfflineNetwork()
        setStatus(ok === false ? "Hotspot state refresh could not be started." : "Hotspot state refreshed.", ok === false)
        return ok !== false
    }

    function configureCurrent(enableValue) {
        if (!networkBackend || typeof networkBackend.requestOfflineNetwork !== "function") {
            setStatus("This NeutronOS build does not expose hotspot configuration.", true)
            return false
        }
        var payload = {
            target: outputKind,
            maxConnections: maxConnectionsDraft
        }
        if (outputKind === "wifi") {
            payload.ssid = ssidDraft
            payload.security = securityDraft
        }
        if (enableValue !== undefined && enableValue !== null)
            payload.enable = enableValue === true
        var ok = networkBackend.requestOfflineNetwork("network.configure-hotspot", payload)
        var changingMode = enableValue !== undefined && enableValue !== null
        var message = changingMode ? (enableValue === true ? "Hotspot enable requested." : "Hotspot disable requested.") : "Hotspot configuration request sent."
        setStatus(ok === false ? "Hotspot request was rejected." : message, ok === false)
        return ok !== false
    }

    function toggleHotspot() {
        if (!networkBackend || typeof networkBackend.requestOfflineNetwork !== "function") {
            setStatus("Hotspot mode control is unavailable.", true)
            return
        }
        if (!hotspotActive && outputIndex === 0 && state.passwordConfigured !== true) {
            passwordDraft = ""
            keyboardRequested("hotspotPassword", "", "Hotspot Password")
            return
        }
        configureCurrent(!hotspotActive)
    }

    function acceptKeyboard(target, value) {
        var clean = String(value || "")
        if (target === "hotspotSsid") {
            if (clean.trim().length < 1) {
                setStatus("SSID cannot be empty.", true)
                return
            }
            ssidDraft = clean.trim()
            configureCurrent()
            return
        }
        if (target === "hotspotPassword") {
            passwordDraft = clean
            if (passwordDraft.length < 8) {
                setStatus("Hotspot password must contain at least 8 characters.", true)
                passwordDraft = ""
                return
            }
            keyboardRequested("hotspotPasswordConfirm", "", "Confirm Hotspot Password")
            return
        }
        if (target === "hotspotPasswordConfirm") {
            if (clean !== passwordDraft) {
                setStatus("Hotspot passwords do not match.", true)
                passwordDraft = ""
                return
            }
            if (!networkBackend || typeof networkBackend.setOfflineWifiPassword !== "function") {
                setStatus("Hotspot credential control is unavailable.", true)
                passwordDraft = ""
                return
            }
            var ok = networkBackend.setOfflineWifiPassword(passwordDraft, clean)
            passwordDraft = ""
            setStatus(ok === false ? "Hotspot password was rejected." : "Hotspot password update requested.", ok === false)
        }
    }

    function cycleOutput(delta) {
        outputIndex = (outputIndex + (delta > 0 ? 1 : -1) + 2) % 2
        syncFromState()
        focusIndex = 0
    }

    function handleControllerPressed(action) {
        if (!visibleMode) return false
        if (action === "cancel") { closeModal(); return true }
        if (action === "up") { focusIndex = Math.max(0, focusIndex - 1); return true }
        if (action === "down") { focusIndex = Math.min(maxFocus, focusIndex + 1); return true }
        if (action === "left" || action === "right") {
            var delta = action === "right" ? 1 : -1
            if (focusIndex === 0) cycleOutput(delta)
            else if (outputIndex === 0 && focusIndex === 4) {
                securityDraft = securityDraft === "wpa2" ? "wpa3" : "wpa2"
                configureCurrent()
            } else if ((outputIndex === 0 && focusIndex === 5) || (outputIndex === 1 && focusIndex === 2)) {
                maxConnectionsDraft = Math.max(1, Math.min(64, maxConnectionsDraft + delta))
                configureCurrent()
            }
            return true
        }
        if (action === "primary") {
            if (focusIndex === 0) { cycleOutput(1); return true }
            if (focusIndex === 1) { toggleHotspot(); return true }
            if (outputIndex === 0) {
                if (focusIndex === 2) { keyboardRequested("hotspotSsid", ssidDraft, "Hotspot SSID"); return true }
                if (focusIndex === 3) { passwordDraft = ""; keyboardRequested("hotspotPassword", "", "Hotspot Password"); return true }
                if (focusIndex === 4) { securityDraft = securityDraft === "wpa2" ? "wpa3" : "wpa2"; configureCurrent(); return true }
                if (focusIndex === 5) { maxConnectionsDraft = maxConnectionsDraft >= 64 ? 1 : maxConnectionsDraft + 1; configureCurrent(); return true }
                if (focusIndex === 6) { requestRefresh(); return true }
                if (focusIndex === 7) { closeModal(); return true }
            } else {
                if (focusIndex === 2) { maxConnectionsDraft = maxConnectionsDraft >= 64 ? 1 : maxConnectionsDraft + 1; configureCurrent(); return true }
                if (focusIndex === 3) { requestRefresh(); return true }
                if (focusIndex === 4) { closeModal(); return true }
            }
        }
        return true
    }

    onVisibleChanged: if (visible) syncFromState()

    Rectangle {
        anchors.fill: parent
        color: "#D902060D"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 110, 1420)
        height: Math.min(parent.height - 96, 860)
        radius: 30
        color: root.panelColor
        border.width: 2
        border.color: root.focusBlue
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 112
            color: root.panelInset
            Text {
                anchors.left: parent.left; anchors.leftMargin: 34; anchors.top: parent.top; anchors.topMargin: 24
                text: "HOTSPOT"; color: root.textPrimary; font.pixelSize: 30; font.bold: true; font.letterSpacing: 1.8
            }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 34; anchors.top: parent.top; anchors.topMargin: 64
                text: root.outputIndex === 0 ? "WI-FI ACCESS POINT" : "ETHERNET INTERNET SHARING"
                color: root.cyan; font.pixelSize: 13; font.bold: true; font.letterSpacing: 1.2
            }
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 34; anchors.verticalCenter: parent.verticalCenter
                width: 220; height: 54; radius: 17
                color: root.hotspotActive ? "#0B3326" : "#31151A"
                border.width: 1; border.color: root.hotspotActive ? root.success : root.danger
                Text { anchors.centerIn: parent; text: root.hotspotActive ? "ACTIVE" : "INACTIVE"; color: root.hotspotActive ? root.success : root.danger; font.pixelSize: 15; font.bold: true; font.letterSpacing: 1.2 }
            }
        }

        Row {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.topMargin: 134; anchors.leftMargin: 28; anchors.rightMargin: 28; anchors.bottom: footer.top; anchors.bottomMargin: 20
            spacing: 20

            Rectangle {
                width: parent.width * 0.47
                height: parent.height
                radius: 24
                color: root.panelInset
                border.width: 1
                border.color: root.divider

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 10

                    Text { width: parent.width; text: "CONFIGURATION"; color: root.textMuted; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.5 }

                    Repeater {
                        model: root.outputIndex === 0 ? [
                            {title:"OUTPUT", value:"WI-FI", sub:"Broadcast from the NeutronOS wireless adapter"},
                            {title:"HOTSPOT", value:root.hotspotActive?"ENABLED":"DISABLED", sub:"Enable or disable this hotspot"},
                            {title:"SSID", value:root.ssidDraft, sub:"Wireless network name"},
                            {title:"PASSWORD", value:root.state.passwordConfigured===true?"CONFIGURED":"NOT SET", sub:"WPA credential • never displayed"},
                            {title:"SECURITY", value:root.securityDraft.toUpperCase(), sub:"WPA2 Personal or WPA3 Personal"},
                            {title:"MAX CONNECTIONS", value:String(root.maxConnectionsDraft), sub:"Maximum DHCP clients"},
                            {title:"REFRESH", value:"X  REFRESH", sub:"Refresh state and connected devices"},
                            {title:"CLOSE", value:"O  CLOSE", sub:"Return to Network settings"}
                        ] : [
                            {title:"OUTPUT", value:"ETHERNET", sub:"Share upstream Wi-Fi through the wired port"},
                            {title:"HOTSPOT", value:root.hotspotActive?"ENABLED":"DISABLED", sub:"Keep Wi-Fi internet active while Ethernet is shared"},
                            {title:"MAX CONNECTIONS", value:String(root.maxConnectionsDraft), sub:"Maximum Ethernet DHCP clients"},
                            {title:"REFRESH", value:"X  REFRESH", sub:"Refresh state and connected devices"},
                            {title:"CLOSE", value:"O  CLOSE", sub:"Return to Network settings"}
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 66
                            radius: 16
                            color: root.focusIndex === index ? "#12335A" : root.panelRaised
                            border.width: root.focusIndex === index ? 2 : 1
                            border.color: root.focusIndex === index ? root.focusBlue : root.divider
                            Rectangle { width: 5; height: parent.height - 18; radius: 3; anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; color: root.focusIndex === index ? root.cyan : root.focusBlue; opacity: .9 }
                            Column {
                                anchors.left: parent.left; anchors.leftMargin: 28; anchors.right: valueText.left; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Text { width: parent.width; text: modelData.title; color: root.textPrimary; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.sub; color: root.textMuted; font.pixelSize: 11; elide: Text.ElideRight }
                            }
                            Text {
                                id: valueText
                                anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                                width: 178
                                text: modelData.value
                                color: modelData.title === "HOTSPOT" ? (root.hotspotActive ? root.success : root.danger) : root.cyan
                                font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width * 0.53 - 20
                height: parent.height
                radius: 24
                color: root.panelInset
                border.width: 1
                border.color: root.divider

                Column {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12
                    Row {
                        width: parent.width
                        Text { width: parent.width - 180; text: "CONNECTED DEVICES"; color: root.textPrimary; font.pixelSize: 19; font.bold: true }
                        Text { width: 180; text: String(root.clients.length) + " / " + String(root.maxConnectionsDraft); color: root.cyan; font.pixelSize: 15; font.bold: true; horizontalAlignment: Text.AlignRight }
                    }
                    Text {
                        width: parent.width
                        text: root.outputIndex === 0 ? "Clients associated with the Wi-Fi hotspot." : "Clients receiving network access through Ethernet. Wi-Fi remains available as the upstream internet connection."
                        color: root.textMuted; font.pixelSize: 12; wrapMode: Text.WordWrap
                    }
                    Rectangle { width: parent.width; height: 1; color: root.divider }

                    ListView {
                        id: clientsView
                        width: parent.width
                        height: parent.height - 112
                        model: root.clients
                        spacing: 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            required property var modelData
                            width: clientsView.width
                            height: 106
                            radius: 18
                            color: root.panelRaised
                            border.width: 1
                            border.color: root.divider
                            Rectangle { width: 48; height: 48; radius: 15; anchors.left: parent.left; anchors.leftMargin: 16; anchors.top: parent.top; anchors.topMargin: 15; color: "#102943"; border.width: 1; border.color: root.focusBlue
                                Text { anchors.centerIn: parent; text: "◆"; color: modelData.active === false ? root.textMuted : root.success; font.pixelSize: 19; font.bold: true }
                            }
                            Column {
                                anchors.left: parent.left; anchors.leftMargin: 78; anchors.right: parent.right; anchors.rightMargin: 16; anchors.top: parent.top; anchors.topMargin: 12; spacing: 4
                                Text { width: parent.width; text: String(modelData.name || "Unnamed device"); color: root.textPrimary; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: "IP  " + String(modelData.ip || "Unavailable") + "     MAC  " + String(modelData.mac || "Unavailable"); color: root.textSecondary; font.pixelSize: 12; elide: Text.ElideRight }
                                Text { width: parent.width; text: "INTERFACE  " + String(modelData.interface || root.outputState.interface || "Unavailable") + "     LINK  " + String(modelData.neighborState || (modelData.active === false ? "EXPIRED" : "ACTIVE")); color: root.cyan; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: String(modelData.expires || "Lease expiration unavailable"); color: root.textMuted; font.pixelSize: 10; elide: Text.ElideRight }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.clients.length === 0
                            text: "NO CONNECTED DEVICES\nClients will appear here when they receive an address."
                            color: root.textMuted; font.pixelSize: 15; font.bold: true; horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 58
            color: root.panelInset
            Text {
                anchors.centerIn: parent
                text: root.statusText.length > 0 ? root.statusText : "D-PAD  NAVIGATE     LEFT / RIGHT  CHANGE     X  SELECT     O  CLOSE"
                color: root.statusText.length > 0 ? (root.statusError ? root.danger : root.success) : root.textMuted
                font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width - 40
            }
        }
    }
}
