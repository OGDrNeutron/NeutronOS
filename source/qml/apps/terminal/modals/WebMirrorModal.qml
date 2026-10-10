import QtQuick 2.15

import "../components"

Item {
    id: root

    anchors.fill: parent
    visible: false
    focus: visible
    z: 1000

    property string webUrl: ""
    property string pairingCode: ""
    property int pairingSecondsRemaining: 0
    property int webClientCount: 0
    property bool webMirrorRunning: false
    property bool webMirrorEnabled: false
    property int selectedIndex: 0
    property string actionMessage: ""
    property bool actionError: false

    readonly property var actions: [
        { "id": "toggle", "label": webMirrorRunning ? "DISABLE REMOTE MIRROR" : "ENABLE REMOTE MIRROR" },
        { "id": "generate", "label": "GENERATE CODE" }
    ]

    signal closeRequested()
    signal toggleWebMirrorRequested()
    signal generateCodeRequested()

    function open() { visible = true; selectedIndex = 0; actionMessage = ""; actionError = false; forceActiveFocus() }
    function showActionResult(ok, message) {
        actionError = !ok
        actionMessage = String(message || "")
        actionMessageTimer.restart()
    }
    function close() { visible = false; closeRequested() }
    function moveLeft() { selectedIndex = Math.max(0, selectedIndex - 1) }
    function moveRight() { selectedIndex = Math.min(actions.length - 1, selectedIndex + 1) }

    function activateSelected() {
        var action = actions[selectedIndex]
        if (!action) return
        if (action.id === "toggle") toggleWebMirrorRequested()
        else if (action.id === "generate") generateCodeRequested()
    }

    function normalizeControllerAction(button) {
        var b = String(button || "").toLowerCase()
        if (b === "primary" || b === "x" || b === "cross" || b === "a") return "primary"
        if (b === "cancel" || b === "o" || b === "circle" || b === "b") return "cancel"
        if (b === "left" || b === "dpad_left") return "left"
        if (b === "right" || b === "dpad_right") return "right"
        if (b === "system" || b === "start" || b === "options" || b === "menu") return "system"
        return b
    }

    function handleControllerPressed(button) {
        if (!visible) return false
        var action = normalizeControllerAction(button)
        if (action === "left") { moveLeft(); return true }
        if (action === "right") { moveRight(); return true }
        if (action === "primary") { activateSelected(); return true }
        if (action === "cancel" || action === "system") { close(); return true }
        return true
    }

    function handleControllerReleased(button) { return visible }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Left) { moveLeft(); event.accepted = true; return }
        if (event.key === Qt.Key_Right) { moveRight(); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { activateSelected(); event.accepted = true; return }
        if (event.key === Qt.Key_Escape) { close(); event.accepted = true; return }
    }

    Timer {
        id: actionMessageTimer
        interval: root.actionError ? 6000 : 3200
        repeat: false
        onTriggered: { root.actionMessage = ""; root.actionError = false }
    }

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.66 }

    TerminalGlassPanel {
        anchors.centerIn: parent
        width: Math.min(parent.width - 240, 980)
        height: 520
        radius: 34
        padding: 30
        strong: true
        focused: true
        success: root.webMirrorRunning

        Column {
            anchors.fill: parent
            spacing: 16

            Text {
                width: parent.width
                text: "Remote Terminal Mirror"
                color: "#F3FCFF"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 34
                font.bold: true
                font.letterSpacing: 1.2
            }

            Text {
                width: parent.width
                text: "The Remote Terminal Mirror attaches to this live terminal. Connecting to the address below lets that device use its own keyboard while viewing the same terminal session. Designed for mobile devices."
                color: "#B9EEFF"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 16
                lineHeight: 1.18
            }

            TerminalGlassPanel {
                width: parent.width
                height: 68
                radius: 20
                padding: 0
                focused: false
                success: root.webMirrorRunning

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 36
                    spacing: 4
                    Text { width: parent.width; text: "ADDRESS"; color: "#77A9C8"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.6 }
                    Text { width: parent.width; text: root.webMirrorRunning && root.webUrl.length > 0 ? root.webUrl : "Remote mirror is disabled"; color: root.webMirrorRunning ? "#68D8FF" : "#71808B"; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle; font.family: "monospace"; font.pixelSize: 19; font.bold: true }
                }
            }

            TerminalGlassPanel {
                width: parent.width
                height: 116
                radius: 22
                padding: 12
                focused: false
                success: root.pairingSecondsRemaining > 0

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 36
                    spacing: 5
                    Text { width: parent.width; text: "60-SECOND CONNECTION CODE"; color: "#77A9C8"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.6 }
                    Text {
                        width: parent.width
                        text: root.pairingSecondsRemaining > 0 && root.pairingCode.length > 0 ? root.pairingCode : "XXXX-XXXX"
                        color: root.pairingSecondsRemaining > 0 ? "#F3FCFF" : "#71808B"
                        horizontalAlignment: Text.AlignHCenter
                        font.family: "monospace"
                        font.pixelSize: 34
                        font.bold: true
                        font.letterSpacing: 5
                    }
                    Text {
                        width: parent.width
                        text: root.pairingSecondsRemaining > 0
                              ? "Valid for " + root.pairingSecondsRemaining + " seconds"
                              : "Generate a new code when you are ready to connect"
                        color: root.pairingSecondsRemaining > 0 ? "#27FF9A" : "#77A9C8"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }

            Row {
                width: parent.width
                height: 78
                spacing: 14

                Repeater {
                    model: root.actions

                    delegate: TerminalGlassPanel {
                        width: (parent.width - 14) / 2
                        height: 74
                        radius: 20
                        padding: 6
                        focused: index === root.selectedIndex
                        success: modelData.id === "toggle" && root.webMirrorRunning
                        strong: index === root.selectedIndex

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 18
                            text: modelData.label
                            color: "#F3FCFF"
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 1.0
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedIndex = index
                                root.activateSelected()
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.actionMessage.length > 0
                      ? root.actionMessage
                      : (root.webMirrorRunning ? "REMOTE ON" : "REMOTE OFF") + "  •  VALIDATED CONNECTIONS " + root.webClientCount + "  •  X SELECT  •  O CLOSE"
                color: root.actionMessage.length > 0
                       ? (root.actionError ? "#FF6B78" : "#27FF9A")
                       : "#77A9C8"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.0
            }
        }
    }
}
