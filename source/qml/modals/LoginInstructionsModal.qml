import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 62000

    property bool automatic: false
    signal acknowledged()
    signal closed()

    readonly property color cyan: "#68E7FF"
    readonly property color green: "#22FF88"
    readonly property color textPrimary: "#F4F8FF"
    readonly property color textMuted: "#A9C7DC"

    function openAutomatic() {
        automatic = true
        visible = true
        forceActiveFocus()
    }
    function openManual() {
        automatic = false
        visible = true
        forceActiveFocus()
    }
    function close() {
        automatic = false
        visible = false
        closed()
    }
    function accept() {
        if (automatic)
            acknowledged()
        visible = false
        closed()
    }
    function handleControllerPressed(value) {
        if (!visible) return false
        var action = String(value || "").trim().toLowerCase()
        if (action === "primary" || action === "x" || action === "cross" ||
                action === "a" || action === "confirm" || action === "cancel" ||
                action === "o" || action === "circle" || action === "b" || action === "back") {
            accept()
        }
        return true
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter ||
                event.key === Qt.Key_Space || event.key === Qt.Key_Escape ||
                event.key === Qt.Key_Backspace) {
            event.accepted = true
            accept()
        }
    }

    Rectangle { anchors.fill: parent; color: "#E5000208" }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 110, 1180)
        height: Math.min(parent.height - 100, 780)
        radius: 34
        color: "#F4071426"
        border.width: 2
        border.color: root.cyan
        Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 31; color: "transparent"; border.width: 1; border.color: "#245A7B" }

        Column {
            anchors.fill: parent
            anchors.margins: 42
            spacing: 19
            Text { width: parent.width; text: "CONTROLLER LOGIN"; color: root.textPrimary; font.pixelSize: 34; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            Text { width: parent.width; text: "YOUR COMBINATION UNLOCKS NEUTRONOS"; color: root.cyan; font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.2; horizontalAlignment: Text.AlignHCenter }
            Rectangle { width: parent.width; height: 1; color: "#31556F" }
            Text {
                width: parent.width
                text: "1. Press X to arm the login card.\n2. Enter the controller combination you created during Setup.\n3. NeutronOS unlocks automatically as soon as the complete correct combination is received. No final button press is required.\n4. An incorrect attempt is rejected and clears the input window."
                color: root.textPrimary; font.pixelSize: 21; lineHeight: 1.25; wrapMode: Text.WordWrap
            }
            Rectangle {
                width: parent.width; height: 176; radius: 22; color: "#0B1B2D"; border.width: 1; border.color: "#385A78"
                Text {
                    anchors.fill: parent; anchors.margins: 20
                    text: "FAILED ATTEMPTS & INPUT WINDOW\nThe rolling input window holds at most 15 controller inputs. Verification begins after 220 ms without another input. There is no separate entry timeout. Failed attempts lock login for 5 seconds, then 30 seconds, 5 minutes, 15 minutes, and one hour for the fifth and later failures. The authentication backend also enforces a 900 ms failed-attempt cooldown."
                    color: root.textMuted; font.pixelSize: 17; lineHeight: 1.18; wrapMode: Text.WordWrap
                }
            }
            Text { width: parent.width; text: "Your combination is verified as a salted Argon2id hash. This guide never displays or logs it."; color: root.green; font.pixelSize: 16; font.bold: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
            Item { width: 1; height: 2 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 310; height: 62; radius: 20; color: "#153B54"; border.width: 2; border.color: root.cyan
                Text { anchors.centerIn: parent; text: "X  GOT IT"; color: "white"; font.pixelSize: 19; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.accept() }
            }
        }
    }
}
