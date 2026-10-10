import QtQuick 2.15

Item {
    id: root

    property var actions: []
    property int selectedIndex: 0
    property bool toolbarFocused: false

    property color textPrimary: "#F3FCFF"
    property color textMuted: "#77A9C8"
    property color neutronBlue: "#68D8FF"
    property color dangerRed: "#FF3048"

    height: 86

    signal actionRequested(string actionId)

    function actionCount() {
        return actions ? actions.length : 0
    }

    function clampIndex() {
        if (actionCount() <= 0) {
            selectedIndex = 0
            return
        }
        selectedIndex = Math.max(0, Math.min(actionCount() - 1, selectedIndex))
    }

    function moveLeft() {
        clampIndex()
        selectedIndex = Math.max(0, selectedIndex - 1)
    }

    function moveRight() {
        clampIndex()
        selectedIndex = Math.min(actionCount() - 1, selectedIndex + 1)
    }

    function activateSelected() {
        clampIndex()
        if (actionCount() <= 0)
            return
        actionRequested(String(actions[selectedIndex].id || ""))
    }

    Rectangle {
        anchors.fill: parent
        color: "#02050AF2"
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12

        Repeater {
            model: root.actions || []

            delegate: TerminalGlassPanel {
                width: String(modelData.label || "").length >= 9 ? 150 : 128
                height: 58
                radius: 18
                padding: 0
                focused: root.toolbarFocused && index === root.selectedIndex
                danger: modelData.danger === true
                strong: index === root.selectedIndex
                accentColor: root.neutronBlue

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 14
                    text: modelData.label || "--"
                    color: modelData.danger ? root.dangerRed : root.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.pixelSize: String(modelData.label || "").length >= 9 ? 14 : 16
                    font.bold: true
                    font.letterSpacing: 1.15
                }
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 42
        anchors.verticalCenter: parent.verticalCenter
        text: root.toolbarFocused ? "TOOLBAR" : ""
        color: root.neutronBlue
        font.pixelSize: 12
        font.bold: true
        font.letterSpacing: 2
    }
}
