import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible

    property var coreBackend: null
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
    property int deviceIndex: 0
    property int focusPane: 0 // 0 devices, 1 actions
    property int actionIndex: 0
    property string statusText: ""
    property bool statusError: false

    signal statusChanged(string message, bool error)
    signal closed()

    readonly property var devices: coreBackend && coreBackend.bluetoothDevices ? coreBackend.bluetoothDevices : []
    readonly property var selectedDevice: devices.length > 0 ? devices[Math.max(0, Math.min(devices.length - 1, deviceIndex))] : ({})
    readonly property var actions: {
        if (!devices.length) return ["REFRESH"]
        var values = []
        values.push(selectedDevice.connected === true ? "DISCONNECT" : "CONNECT")
        if (selectedDevice.paired !== true) values.push("PAIR")
        values.push(selectedDevice.trusted === true ? "REMOVE TRUST" : "TRUST")
        if (selectedDevice.paired === true) values.push("REMOVE DEVICE")
        values.push("REFRESH")
        return values
    }

    function openModal(address) {
        visibleMode = true
        deviceIndex = 0
        focusPane = 0
        actionIndex = 0
        refreshDevices(false)
        var wanted = String(address || "").toLowerCase()
        if (wanted.length > 0) {
            for (var i = 0; i < devices.length; ++i) {
                if (String(devices[i].address || "").toLowerCase() === wanted) {
                    deviceIndex = i
                    break
                }
            }
        }
        forceActiveFocus()
    }

    function closeModal() {
        visibleMode = false
        closed()
    }

    function setStatus(message, error) {
        statusText = String(message || "")
        statusError = error === true
        statusChanged(statusText, statusError)
    }

    function refreshDevices(showStatus) {
        if (!coreBackend || typeof coreBackend.refresh !== "function") {
            if (showStatus !== false) setStatus("Bluetooth backend is unavailable.", true)
            return false
        }
        coreBackend.refresh()
        deviceIndex = Math.min(deviceIndex, Math.max(0, devices.length - 1))
        if (showStatus !== false) setStatus(String(coreBackend.lastMessage || "Bluetooth device list refreshed."), false)
        return true
    }

    function normalizedAction(label) {
        if (label === "REMOVE TRUST") return "untrust"
        if (label === "REMOVE DEVICE") return "remove"
        return String(label || "").toLowerCase()
    }

    function runAction(label) {
        if (label === "REFRESH") { refreshDevices(true); return }
        var address = String(selectedDevice.address || "")
        if (!address.length) { setStatus("The selected Bluetooth device has no usable address.", true); return }
        if (!coreBackend || typeof coreBackend.requestBluetoothAction !== "function") {
            setStatus("Bluetooth management is unavailable.", true)
            return
        }
        var action = normalizedAction(label)
        var ok = coreBackend.requestBluetoothAction(action, address)
        setStatus(ok === false ? (String(coreBackend.lastMessage || label + " was rejected.")) : String(coreBackend.lastMessage || label + " requested."), ok === false)
        Qt.callLater(function() { if (coreBackend && typeof coreBackend.refresh === "function") coreBackend.refresh() })
    }

    function handleControllerPressed(action) {
        if (!visibleMode) return false
        if (action === "cancel") { closeModal(); return true }
        if (action === "left") { focusPane = 0; return true }
        if (action === "right") { if (devices.length) focusPane = 1; return true }
        if (action === "up") {
            if (focusPane === 0) deviceIndex = Math.max(0, deviceIndex - 1)
            else actionIndex = Math.max(0, actionIndex - 1)
            return true
        }
        if (action === "down") {
            if (focusPane === 0) deviceIndex = Math.min(Math.max(0, devices.length - 1), deviceIndex + 1)
            else actionIndex = Math.min(Math.max(0, actions.length - 1), actionIndex + 1)
            return true
        }
        if (action === "primary") {
            if (focusPane === 0) { if (devices.length) { focusPane = 1; actionIndex = 0 } else refreshDevices(true) }
            else runAction(actions[actionIndex])
            return true
        }
        return true
    }

    onDeviceIndexChanged: actionIndex = 0

    Rectangle { anchors.fill: parent; color: "#D902060D" }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 110, 1460)
        height: Math.min(parent.height - 96, 860)
        radius: 30
        color: root.panelColor
        border.width: 2
        border.color: root.focusBlue
        clip: true

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 112; color: root.panelInset
            Item {
                anchors.left: parent.left; anchors.leftMargin: 34; anchors.verticalCenter: parent.verticalCenter
                width: 58; height: 70
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var c=getContext("2d"); c.clearRect(0,0,width,height); c.strokeStyle=String(root.cyan); c.lineWidth=5; c.lineCap="round"; c.lineJoin="round";
                        c.beginPath(); c.moveTo(width*.5,4); c.lineTo(width*.5,height-4); c.moveTo(width*.5,4); c.lineTo(width*.82,height*.28); c.lineTo(width*.24,height*.72); c.moveTo(width*.5,height-4); c.lineTo(width*.82,height*.72); c.lineTo(width*.24,height*.28); c.stroke();
                    }
                }
            }
            Column {
                anchors.left: parent.left; anchors.leftMargin: 110; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Text { text: "BLUETOOTH"; color: root.textPrimary; font.pixelSize: 30; font.bold: true; font.letterSpacing: 1.6 }
                Text { text: "CONNECTED DEVICES • PAIRING • TRUST"; color: root.cyan; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.2 }
            }
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 34; anchors.verticalCenter: parent.verticalCenter
                width: 206; height: 54; radius: 17; color: root.devices.length ? "#0B3326" : root.panelRaised; border.width: 1; border.color: root.devices.length ? root.success : root.divider
                Text { anchors.centerIn: parent; text: String(root.devices.length) + (root.devices.length===1?" DEVICE":" DEVICES"); color: root.devices.length ? root.success : root.textMuted; font.pixelSize: 14; font.bold: true }
            }
        }

        Row {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 134; anchors.bottom: footer.top; anchors.bottomMargin: 20; anchors.leftMargin: 28; anchors.rightMargin: 28
            spacing: 20

            Rectangle {
                width: parent.width * .43; height: parent.height; radius: 24; color: root.panelInset; border.width: 1; border.color: root.focusPane===0 ? root.focusBlue : root.divider
                Column {
                    anchors.fill: parent; anchors.margins: 18; spacing: 10
                    Text { width: parent.width; text: "DEVICES"; color: root.textMuted; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.5 }
                    ListView {
                        id: deviceList
                        width: parent.width; height: parent.height - 36; model: root.devices; spacing: 8; clip: true; currentIndex: root.deviceIndex; boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            required property var modelData; required property int index
                            width: deviceList.width; height: 82; radius: 18
                            color: root.deviceIndex===index ? "#12335A" : root.panelRaised
                            border.width: root.deviceIndex===index ? 2 : 1
                            border.color: root.deviceIndex===index ? root.focusBlue : root.divider
                            Rectangle { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; width: 48; height: 48; radius: 16; color: root.panelInset; border.width: 1; border.color: modelData.connected===true ? root.success : root.focusBlue
                                Text { anchors.centerIn: parent; text: modelData.type && String(modelData.type).toLowerCase().indexOf("audio")>=0 ? "♪" : "B"; color: modelData.connected===true ? root.success : root.cyan; font.pixelSize: 20; font.bold: true }
                            }
                            Column { anchors.left: parent.left; anchors.leftMargin: 76; anchors.right: trustLabel.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                Text { width: parent.width; text: String(modelData.name || "Unknown device"); color: root.textPrimary; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: String(modelData.address || "Address unavailable"); color: root.textMuted; font.pixelSize: 11; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.connected===true ? "CONNECTED" : modelData.paired===true ? "PAIRED" : "AVAILABLE"; color: modelData.connected===true ? root.success : root.focusBlue; font.pixelSize: 10; font.bold: true }
                            }
                            Text { id: trustLabel; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData.trusted===true ? "TRUSTED" : "UNTRUSTED"; color: modelData.trusted===true ? root.success : root.warning; font.pixelSize: 10; font.bold: true }
                        }
                        Text { anchors.centerIn: parent; visible: root.devices.length===0; text: "NO BLUETOOTH DEVICES\nPress X to refresh."; color: root.textMuted; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    }
                }
            }

            Rectangle {
                width: parent.width * .57 - 20; height: parent.height; radius: 24; color: root.panelInset; border.width: 1; border.color: root.focusPane===1 ? root.focusBlue : root.divider
                Column {
                    anchors.fill: parent; anchors.margins: 24; spacing: 14
                    Text { width: parent.width; text: root.devices.length ? String(root.selectedDevice.name || "Bluetooth Device") : "DEVICE DETAILS"; color: root.textPrimary; font.pixelSize: 24; font.bold: true; elide: Text.ElideRight }
                    Text { width: parent.width; text: root.devices.length ? String(root.selectedDevice.type || "Bluetooth") + " • " + String(root.selectedDevice.address || "Unavailable") : "Select a device to inspect and manage it."; color: root.textMuted; font.pixelSize: 13; elide: Text.ElideRight }
                    Rectangle { width: parent.width; height: 1; color: root.divider }
                    Grid {
                        columns: 2; columnSpacing: 10; rowSpacing: 10; width: parent.width
                        Repeater {
                            model: root.devices.length ? [
                                {l:"CONNECTION",v:root.selectedDevice.connected===true?"CONNECTED":"DISCONNECTED",tone:root.selectedDevice.connected===true?root.success:root.textMuted},
                                {l:"PAIRING",v:root.selectedDevice.paired===true?"PAIRED":"NOT PAIRED",tone:root.selectedDevice.paired===true?root.focusBlue:root.textMuted},
                                {l:"TRUST",v:root.selectedDevice.trusted===true?"TRUSTED":"UNTRUSTED",tone:root.selectedDevice.trusted===true?root.success:root.warning},
                                {l:"SIGNAL",v:root.selectedDevice.signal!==undefined?String(root.selectedDevice.signal):root.selectedDevice.rssi!==undefined?String(root.selectedDevice.rssi):"N/A",tone:root.cyan},
                                {l:"BATTERY",v:root.selectedDevice.battery!==undefined?String(root.selectedDevice.battery):root.selectedDevice.batteryPercent!==undefined?String(root.selectedDevice.batteryPercent)+"%":"N/A",tone:root.cyan},
                                {l:"ADDRESS",v:String(root.selectedDevice.address||"N/A"),tone:root.textSecondary}
                            ] : []
                            delegate: Rectangle {
                                required property var modelData
                                width: (parent.width - 10) / 2; height: 70; radius: 16; color: root.panelRaised; border.width: 1; border.color: root.divider
                                Column { anchors.fill: parent; anchors.margins: 12; spacing: 4
                                    Text { width: parent.width; text: modelData.l; color: root.textMuted; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.0 }
                                    Text { width: parent.width; text: modelData.v; color: modelData.tone; font.pixelSize: 14; font.bold: true; elide: Text.ElideMiddle }
                                }
                            }
                        }
                    }
                    Text { width: parent.width; text: "ACTIONS"; color: root.textMuted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                    Repeater {
                        model: root.actions
                        delegate: Rectangle {
                            required property string modelData; required property int index
                            width: parent.width; height: 58; radius: 16
                            color: root.focusPane===1 && root.actionIndex===index ? "#12335A" : root.panelRaised
                            border.width: root.focusPane===1 && root.actionIndex===index ? 2 : 1
                            border.color: root.focusPane===1 && root.actionIndex===index ? root.focusBlue : root.divider
                            Text { anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: modelData==="REMOVE DEVICE" ? root.danger : modelData==="TRUST" ? root.success : modelData==="REMOVE TRUST" ? root.warning : root.textPrimary; font.pixelSize: 14; font.bold: true }
                            Text { anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: "X"; color: root.cyan; font.pixelSize: 12; font.bold: true }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 58; color: root.panelInset
            Text { anchors.centerIn: parent; width: parent.width - 40; text: root.statusText.length ? root.statusText : "LEFT / RIGHT  PANE     UP / DOWN  SELECT     X  ACTION     O  CLOSE"; color: root.statusText.length ? (root.statusError ? root.danger : root.success) : root.textMuted; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
        }
    }
}
