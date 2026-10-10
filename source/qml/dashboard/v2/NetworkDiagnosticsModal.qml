import QtQuick 2.15

Rectangle {
    id: root
    property var networkBackend: null
    property bool opened: false
    property int selectedIndex: 0

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

    function resultList() {
        return networkBackend && networkBackend.diagnosticResults ? networkBackend.diagnosticResults : []
    }
    function openModal() {
        opened = true
        selectedIndex = 0
        if (networkBackend && typeof networkBackend.runDiagnostics === "function")
            networkBackend.runDiagnostics()
        forceActiveFocus()
    }
    function closeModal() {
        opened = false
        if (parent && typeof parent.forceActiveFocus === "function")
            parent.forceActiveFocus()
    }
    function handleControllerPressed(action) {
        if (!opened) return false
        if (action === "cancel" || action === "back" || action === "circle" || action === "o") closeModal()
        else if (action === "up") selectedIndex = Math.max(0, selectedIndex - 1)
        else if (action === "down") selectedIndex = Math.min(Math.max(0, resultList().length - 1), selectedIndex + 1)
        else if (action === "primary") {
            if (networkBackend && !networkBackend.diagnosticsRunning && typeof networkBackend.runDiagnostics === "function")
                networkBackend.runDiagnostics()
        }
        return true
    }

    Column {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 14
        Row {
            width: parent.width; height: 58
            Column {
                width: parent.width - 220; spacing: 2
                Text { text: "NETWORK DIAGNOSTICS"; color: "#FFFFFF"; font.pixelSize: 28; font.bold: true }
                Text {
                    text: root.networkBackend ? String(root.networkBackend.diagnosticsSummary || "Not run yet") : "Unavailable"
                    color: root.networkBackend && root.networkBackend.diagnosticsRunning ? "#F2C85A" : "#8FCBFF"
                    font.pixelSize: 12; font.bold: true
                }
            }
            Text {
                width: 220; anchors.verticalCenter: parent.verticalCenter
                text: root.networkBackend && root.networkBackend.diagnosticsRunning ? "RUNNING…" : "X RUN AGAIN"
                color: root.networkBackend && root.networkBackend.diagnosticsRunning ? "#F2C85A" : "#7DF9FF"
                font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignRight
            }
        }
        ListView {
            id: resultsList
            width: parent.width
            height: parent.height - 58 - 44 - parent.spacing * 2
            clip: true; spacing: 8
            model: root.networkBackend && root.networkBackend.diagnosticResults ? root.networkBackend.diagnosticResults : []
            currentIndex: root.selectedIndex
            delegate: Rectangle {
                required property int index
                required property var modelData
                width: resultsList.width; height: 82; radius: 14
                color: index === root.selectedIndex ? "#183D68" : "#0B1830"
                border.width: index === root.selectedIndex ? 2 : 1
                border.color: index === root.selectedIndex ? "#58B9FF" : "#274267"
                Row {
                    anchors.fill: parent; anchors.margins: 13; spacing: 12
                    Rectangle {
                        width: 58; height: 28; radius: 14; anchors.verticalCenter: parent.verticalCenter
                        color: Boolean(modelData.success) ? "#153B31" : "#481B29"
                        border.width: 1; border.color: Boolean(modelData.success) ? "#54E9A4" : "#FF5875"
                        Text {
                            anchors.centerIn: parent
                            text: Boolean(modelData.success) ? "PASS" : "FAIL"
                            color: Boolean(modelData.success) ? "#68F7B6" : "#FF6A84"
                            font.pixelSize: 10; font.bold: true
                        }
                    }
                    Column {
                        width: parent.width - 70; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                        Text {
                            width: parent.width; text: String(modelData.label || modelData.name || "Network Check")
                            color: "#FFFFFF"; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width; text: String(modelData.detail || modelData.message || "")
                            color: "#96A8CA"; font.pixelSize: 11; wrapMode: Text.Wrap
                            maximumLineCount: 2; elide: Text.ElideRight
                        }
                    }
                }
            }
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        }
        Text {
            width: parent.width; height: 34
            text: "D-PAD REVIEW RESULTS  •  X RUN AGAIN  •  O CLOSE"
            color: "#7C95C0"; font.pixelSize: 11; font.bold: true
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
    }
}
