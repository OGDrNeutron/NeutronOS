import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: visibleMode
    enabled: visibleMode
    focus: visibleMode
    z: 121

    property bool visibleMode: false
    property var backend: null
    property int selectedIndex: -1
    property int armedIndex: -1
    property string statusMessage: ""
    property bool statusError: false
    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color textPrimary: "#F4FBFF"
    property color textSecondary: "#A8C2DE"
    property color textMuted: "#7895B5"
    property color divider: "#1D3958"
    property color focusBlue: "#4DA6FF"
    property color success: "#22FF88"
    property color warning: "#F5C542"
    property color danger: "#FF3040"
    signal closeRequested()

    ListModel { id: restoreModel; dynamicRoles: true }

    function rebuild() {
        var previous = selectedIndex >= 0 && selectedIndex < restoreModel.count
                     ? String(restoreModel.get(selectedIndex).path || "") : ""
        restoreModel.clear()
        var rows = backend ? backend.backups : []
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].verified === true) restoreModel.append(rows[i])
        }
        selectedIndex = restoreModel.count > 0 ? 0 : -1
        for (var j = 0; j < restoreModel.count; ++j) {
            if (String(restoreModel.get(j).path) === previous) selectedIndex = j
        }
        restoreList.currentIndex = selectedIndex
        armedIndex = -1
    }

    function openModal() {
        visibleMode = true
        statusMessage = "Loading protected restore-point catalog…"
        statusError = false
        armedIndex = -1
        if (backend) backend.refresh()
        rebuild()
        forceActiveFocus()
    }

    function closeModal() {
        armedIndex = -1
        visibleMode = false
        closeRequested()
    }

    function move(delta) {
        if (restoreModel.count <= 0) return
        selectedIndex = (selectedIndex + delta + restoreModel.count) % restoreModel.count
        restoreList.currentIndex = selectedIndex
        restoreList.positionViewAtIndex(selectedIndex, ListView.Contain)
        armedIndex = -1
        statusMessage = "Selection changed. Restoration is not armed."
        statusError = false
    }

    function activate() {
        if (!backend || backend.busy || selectedIndex < 0 || selectedIndex >= restoreModel.count) return
        var point = restoreModel.get(selectedIndex)
        if (point.verified !== true) {
            statusMessage = "This restore point is not verified and cannot be selected."
            statusError = true
            armedIndex = -1
            return
        }
        if (armedIndex !== selectedIndex) {
            armedIndex = selectedIndex
            statusMessage = "RESTORE ARMED — Press X again to stage " + String(point.name) + " for one-shot Recovery."
            statusError = false
            return
        }
        armedIndex = -1
        var started = backend.restoreBackup(String(point.path))
        statusMessage = String(backend.lastMessage || (started ? "Staging restore point…" : "Restore staging could not start."))
        statusError = !started
    }

    function normalizeAction(value) {
        var action = String(value || "").toLowerCase()
        if (action === "x" || action === "cross" || action === "ps_cross") return "primary"
        if (action === "o" || action === "circle" || action === "ps_circle") return "cancel"
        if (action === "dpad_up") return "up"
        if (action === "dpad_down") return "down"
        return action
    }

    function handleControllerPressed(value) {
        var action = normalizeAction(value)
        if (!visibleMode) return false
        if (action === "cancel") { closeModal(); return true }
        if (action === "up") { move(-1); return true }
        if (action === "down") { move(1); return true }
        if (action === "primary") { activate(); return true }
        return true
    }
    function handleController(value) { return handleControllerPressed(value) }
    function handleControllerReleased(value) { return visibleMode }

    Connections {
        target: backend
        ignoreUnknownSignals: true
        function onBackupsChanged() {
            root.rebuild()
            root.statusMessage = restoreModel.count > 0 ? "Choose a verified restore point." : "No valid restore points are available."
            root.statusError = restoreModel.count <= 0
        }
        function onStateChanged() {
            if (backend && backend.busy) root.statusMessage = String(backend.currentItem || backend.status || "Working…")
        }
        function onOperationFinished(operation, ok, message) {
            if (operation !== "restore-backup") return
            root.statusMessage = String(message)
            root.statusError = !ok
            root.armedIndex = -1
        }
    }

    Rectangle { anchors.fill: parent; color: "#B0000000" }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1180)
        height: Math.min(parent.height - 100, 820)
        radius: 34; color: root.panelColor; border.width: 2; border.color: root.focusBlue
        Column {
            anchors.fill: parent; anchors.margins: 30; spacing: 14
            Text { width: parent.width; text: "RESTORE POINTS"; color: root.textPrimary; font.pixelSize: 30; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            Text { width: parent.width; text: "VERIFIED PROTECTED BACKUPS • USER FILES PRESERVED"; color: root.focusBlue; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            Rectangle { width: parent.width; height: 1; color: root.divider }
            ListView {
                id: restoreList; width: parent.width; height: parent.height - 240; clip: true; model: restoreModel; spacing: 10; currentIndex: root.selectedIndex
                delegate: Rectangle {
                    required property int index
                    required property string name
                    required property string profile
                    required property string sizeText
                    required property string modified
                    width: restoreList.width; height: 106; radius: 16
                    color: index === root.selectedIndex ? root.panelRaised : "transparent"
                    border.width: index === root.selectedIndex ? 2 : 1
                    border.color: root.armedIndex === index ? root.warning : (index === root.selectedIndex ? root.focusBlue : root.divider)
                    Column { anchors.fill: parent; anchors.margins: 13; spacing: 5
                        Text { width: parent.width; text: name; color: root.textPrimary; font.pixelSize: 17; font.bold: true; elide: Text.ElideMiddle }
                        Text { width: parent.width; text: profile + " • " + sizeText + " • " + modified; color: root.textSecondary; font.pixelSize: 14; elide: Text.ElideRight }
                        Text { width: parent.width; text: root.armedIndex === index ? "ARMED — X CONFIRM" : "CHECKSUM VERIFIED"; color: root.armedIndex === index ? root.warning : root.success; font.pixelSize: 13; font.bold: true }
                    }
                }
            }
            Rectangle { width: parent.width; height: 62; radius: 14; color: root.panelRaised; border.width: 1; border.color: root.statusError ? root.danger : root.divider
                Text { anchors.fill: parent; anchors.margins: 10; text: backend && backend.busy && backend.progress >= 0 ? String(backend.progress) + "%  " + root.statusMessage : root.statusMessage; color: root.statusError ? root.danger : root.textSecondary; font.pixelSize: 14; wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
            }
            Text { width: parent.width; text: "UP / DOWN  SELECT     X  ARM / CONFIRM     O  BACK"; color: root.textMuted; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter }
        }
    }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up) { handleControllerPressed("up"); event.accepted = true }
        else if (event.key === Qt.Key_Down) { handleControllerPressed("down"); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { handleControllerPressed("primary"); event.accepted = true }
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) { handleControllerPressed("cancel"); event.accepted = true }
    }
}
