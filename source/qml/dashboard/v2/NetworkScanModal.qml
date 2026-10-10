import QtQuick 2.15
import "../../components"

Rectangle {
    id: root
    property var networkBackend: null
    property bool opened: false
    property int selectedIndex: 0
    property string statusMessage: ""
    property bool statusError: false
    property bool passwordEntry: false
    property var pendingNetwork: ({})
    property string pendingPassword: ""

    anchors.fill: parent
    visible: opened
    enabled: visible
    color: "#F0020814"
    radius: 22
    border.width: 1
    border.color: "#5B7DF3"
    focus: opened
    Keys.onPressed: function(event) {
        if (!root.opened) return
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            root.closeModal()
            event.accepted = true
        }
    }

    function isCancelAction(action) {
        var value = String(action === undefined || action === null ? "" : action).toLowerCase()
        return value === "cancel" || value === "back" ||
               value === "circle" || value === "o"
    }

    function networkList() {
        return networkBackend && networkBackend.availableNetworks ? networkBackend.availableNetworks : []
    }
    function clean(v) {
        if (v === undefined || v === null) return ""
        var s = String(v).trim()
        return s === "undefined" || s === "null" ? "" : s
    }
    function ssid(n) { return clean(n && (n.ssid || n.name || n.displayName || n.id)) }
    function security(n) { return clean(n && (n.security || n.securityType || "OPEN")).toUpperCase() }
    function strength(n) {
        var raw = n && n.signalPercent !== undefined ? n.signalPercent : (n ? n.signal : 0)
        return Math.max(0, Math.min(100, Number(raw || 0)))
    }
    function saved(n) { return Boolean(n && (n.saved === true || n.known === true || n.hasProfile === true)) }
    function connected(n) { return Boolean(n && (n.connected === true || n.active === true || n.current === true)) }
    function requiresPassword(n) {
        var s = security(n)
        return s.length > 0 && s !== "OPEN" && s !== "NONE" && s !== "--"
    }
    function connectionPayload(n, password) {
        return {
            "network": n || ({}),
            "id": clean(n && n.id),
            "ssid": ssid(n),
            "bssid": clean(n && n.bssid),
            "security": security(n),
            "password": password || "",
            "remember": true,
            "hidden": false
        }
    }
    function openModal() {
        opened = true
        selectedIndex = 0
        statusMessage = "SCANNING FOR NETWORKS"
        statusError = false
        passwordEntry = false
        pendingNetwork = ({})
        pendingPassword = ""
        if (networkBackend && typeof networkBackend.requestScan === "function")
            networkBackend.requestScan()
        forceActiveFocus()
    }
    function dismissModal() {
        passwordEntry = false
        pendingPassword = ""
        pendingNetwork = ({})
        wifiKeyboard.visibleMode = false
        opened = false

        if (parent && typeof parent.forceActiveFocus === "function")
            parent.forceActiveFocus()
    }

    function closeModal() {
        dismissModal()
    }
    function selectedNetwork() {
        var list = networkList()
        if (!list.length) return null
        return list[Math.max(0, Math.min(selectedIndex, list.length - 1))]
    }
    function connectSelected() {
        var n = selectedNetwork()
        if (!n || !networkBackend) return false
        if (connected(n)) {
            statusMessage = ssid(n) + " IS ALREADY CONNECTED"
            statusError = false
            return true
        }
        if (requiresPassword(n) && !saved(n)) {
            pendingNetwork = n
            pendingPassword = ""
            passwordEntry = true
            wifiKeyboard.openKeyboard("small")
            return true
        }
        var ok = typeof networkBackend.connectToNetwork === "function"
               ? networkBackend.connectToNetwork(connectionPayload(n, "")) : false
        statusMessage = ok ? "CONNECTING TO " + ssid(n).toUpperCase()
                           : clean(networkBackend.lastError || "CONNECTION REQUEST FAILED")
        statusError = !ok
        return true
    }
    function submitPassword() {
        if (!passwordEntry || !networkBackend) return false
        if (pendingPassword.length < 8) {
            statusMessage = "PASSWORD MUST CONTAIN AT LEAST 8 CHARACTERS"
            statusError = true
            return false
        }
        var name = ssid(pendingNetwork)
        var ok = typeof networkBackend.connectToNetwork === "function"
               ? networkBackend.connectToNetwork(connectionPayload(pendingNetwork, pendingPassword)) : false
        statusMessage = ok ? "CONNECTING TO " + name.toUpperCase()
                           : clean(networkBackend.lastError || "CONNECTION REQUEST FAILED")
        statusError = !ok
        passwordEntry = false
        pendingPassword = ""
        wifiKeyboard.visibleMode = false
        forceActiveFocus()
        return ok
    }
    function handleControllerPressed(action) {
        if (!opened) return false

        if (passwordEntry) {
            // NEUTRONOS_WIFI_SCAN_KEYBOARD_ROUTING_V1
            if (isCancelAction(action)) {
                dismissModal()
                return true
            }
            if (wifiKeyboard && typeof wifiKeyboard.handleController === "function")
                return wifiKeyboard.handleController(action)
            if (wifiKeyboard && typeof wifiKeyboard.handleControllerPressed === "function")
                return wifiKeyboard.handleControllerPressed(action)
            return true
        }

        if (isCancelAction(action)) {
            dismissModal()
            return true
        }

        if (action === "up") selectedIndex = Math.max(0, selectedIndex - 1)
        else if (action === "down") selectedIndex = Math.min(Math.max(0, networkList().length - 1), selectedIndex + 1)
        else if (action === "primary") connectSelected()
        else if (action === "context") {
            statusMessage = "REFRESHING NETWORK LIST"
            statusError = false
            if (networkBackend && typeof networkBackend.requestScan === "function") networkBackend.requestScan()
        }
        return true
    }

    Connections {
        target: root.networkBackend
        enabled: target !== null
        ignoreUnknownSignals: true
        function onAvailableNetworksChanged() {
            selectedIndex = Math.max(0, Math.min(Math.max(0, root.networkList().length - 1), selectedIndex))
        }
        function onScanningChanged() {
            if (!root.networkBackend) return
            statusMessage = root.networkBackend.scanning ? "SCANNING FOR NETWORKS" :
                            (root.networkList().length + " NETWORKS FOUND")
            statusError = false
        }
        function onOperationFinished(action, success, message, payload) {
            if (!root.opened) return
            var a = String(action || "").toLowerCase()
            if (a.indexOf("connect") < 0 && a.indexOf("activate") < 0) return
            statusMessage = String(message || (success ? "NETWORK CONNECTION UPDATED" : "NETWORK CONNECTION FAILED"))
            statusError = !success
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 14
        Row {
            width: parent.width; height: 56
            Text { width: parent.width - 180; text: "AVAILABLE NETWORKS"; color: "#F8FAFF"; font.pixelSize: 28; font.bold: true }
            Text {
                width: 180
                text: root.networkBackend && root.networkBackend.scanning ? "SCANNING…" : "△ RESCAN"
                color: root.networkBackend && root.networkBackend.scanning ? "#F3C85A" : "#7DF9FF"
                font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight
            }
        }
        Rectangle {
            width: parent.width; height: 42; radius: 12
            color: root.statusError ? "#3A1520" : "#112845"
            border.width: 1; border.color: root.statusError ? "#FF5572" : "#365F95"
            Text {
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                text: root.statusMessage; color: root.statusError ? "#FF738B" : "#9FD9FF"
                font.pixelSize: 12; font.bold: true; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            }
        }
        ListView {
            id: list
            width: parent.width
            height: parent.height - 56 - 42 - 56 - parent.spacing * 3
            clip: true; spacing: 7
            model: root.networkBackend && root.networkBackend.availableNetworks ? root.networkBackend.availableNetworks : []
            currentIndex: root.selectedIndex
            delegate: Rectangle {
                required property int index
                required property var modelData
                width: list.width; height: 68; radius: 14
                color: index === root.selectedIndex ? "#183D68" : "#0B1830"
                border.width: index === root.selectedIndex ? 2 : 1
                border.color: index === root.selectedIndex ? "#58B9FF" : "#274267"
                Row {
                    anchors.fill: parent; anchors.margins: 12; spacing: 12
                    Column {
                        width: parent.width * .58; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { width: parent.width; text: root.ssid(modelData); color: "#FFFFFF"; font.pixelSize: 17; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: root.security(modelData) + (root.saved(modelData) ? "  •  SAVED" : ""); color: "#8FA6CF"; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight }
                    }
                    Column {
                        width: parent.width * .18; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text {
                            width: parent.width; text: root.strength(modelData) + "%"
                            color: root.strength(modelData) >= 70 ? "#56EDA5" : root.strength(modelData) >= 40 ? "#F2C85A" : "#FF738B"
                            font.pixelSize: 16; font.bold: true; horizontalAlignment: Text.AlignRight
                        }
                        Text { width: parent.width; text: "SIGNAL"; color: "#7287B3"; font.pixelSize: 9; horizontalAlignment: Text.AlignRight }
                    }
                    Text {
                        width: parent.width * .20 - parent.spacing * 2; anchors.verticalCenter: parent.verticalCenter
                        text: root.connected(modelData) ? "CONNECTED" : (root.saved(modelData) ? "X CONNECT" : (root.requiresPassword(modelData) ? "X PASSWORD" : "X CONNECT"))
                        color: root.connected(modelData) ? "#60F1AE" : "#7DF9FF"
                        font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignRight
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: { root.selectedIndex = index; root.connectSelected() } }
            }
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        }
        Text {
            width: parent.width; height: 36
            text: "D-PAD SELECT  •  X CONNECT  •  △ RESCAN  •  O CLOSE"
            color: "#7C95C0"; font.pixelSize: 11; font.bold: true
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.passwordEntry
        enabled: visible
        z: 20
        color: "#F4020814"
        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width * .72, 820)
            spacing: 12
            Text {
                width: parent.width
                text: "CONNECT TO " + root.ssid(root.pendingNetwork).toUpperCase()
                color: "#FFFFFF"; font.pixelSize: 20; font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Rectangle {
                width: parent.width; height: 52; radius: 14
                color: "#0E1A2D"; border.width: 1; border.color: "#54B9FF"
                Text {
                    anchors.fill: parent; anchors.margins: 12
                    text: root.pendingPassword.length ? "•".repeat(root.pendingPassword.length) : "Enter Wi-Fi password"
                    color: root.pendingPassword.length ? "#FFFFFF" : "#7F91B3"
                    font.pixelSize: 15; verticalAlignment: Text.AlignVCenter
                }
            }
            VirtualKeyboard {
                id: wifiKeyboard
                width: parent.width; height: 360
                active: root.passwordEntry
                cancelBehavior: "close"
                resetOnOpen: true
                onKeyPressed: function(value) { root.pendingPassword += value }
                onBackspacePressed: root.pendingPassword = root.pendingPassword.slice(0, -1)
                onEnterPressed: root.submitPassword()
                onClosePressed: root.dismissModal()
            }
        }
    }
}
