import QtQuick 2.15

import "../components"

Item {
    id: root

    anchors.fill: parent
    visible: false
    focus: visible
    z: 1000

    property bool developerMode: false
    property string modeLabel: "REGULAR"
    property string statusText: ""
    property int selectedIndex: 0

    readonly property var actions: [
        { "id": "restart", "label": "RESTART PTY", "hint": "Apply current mode" },
        { "id": "close", "label": "CLOSE", "hint": "Back to terminal" }
    ]

    signal closeRequested()
    signal restartRequested()

    function open() { visible = true; selectedIndex = 0; forceActiveFocus() }
    function close() { visible = false; closeRequested() }
    function moveLeft() { selectedIndex = Math.max(0, selectedIndex - 1) }
    function moveRight() { selectedIndex = Math.min(actions.length - 1, selectedIndex + 1) }

    function activateSelected() {
        var action = actions[selectedIndex]
        if (!action) return
        if (action.id === "restart") restartRequested()
        else close()
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

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.60 }

    TerminalGlassPanel {
        anchors.centerIn: parent
        width: Math.min(parent.width - 260, 860)
        height: 380
        radius: 34
        padding: 28
        strong: true
        focused: true
        danger: root.developerMode
        success: !root.developerMode

        Column {
            anchors.fill: parent
            spacing: 18

            Text { width: parent.width; text: "DEVELOPER MODE STATUS"; color: "#F3FCFF"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 29; font.bold: true; font.letterSpacing: 2 }

            TerminalGlassPanel {
                width: parent.width
                height: 96
                radius: 24
                padding: 16
                focused: false
                danger: root.developerMode
                success: !root.developerMode

                Column {
                    width: parent.width - 24
                    anchors.centerIn: parent
                    spacing: 8
                    Text { width: parent.width; text: root.modeLabel; color: root.developerMode ? "#FFD166" : "#27FF9A"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 26; font.bold: true; font.letterSpacing: 2 }
                    Text { width: parent.width; text: root.developerMode ? "Root/developer shell is active because Console enabled Developer Mode." : "Regular user shell is active. Sudo still requires a password."; color: "#B9EEFF"; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; font.pixelSize: 15 }
                }
            }

            Text {
                width: parent.width
                text: "Terminal can only read Developer Mode state. It cannot enable Developer Mode. To change mode, exit to Console and use the Console Developer Mode flow."
                color: "#B9EEFF"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 16
                lineHeight: 1.12
            }

            Row {
                width: parent.width
                height: 84
                spacing: 14
                Repeater {
                    model: root.actions
                    delegate: TerminalGlassPanel {
                        width: (parent.width - 14) / 2
                        height: 78
                        radius: 22
                        padding: 10
                        focused: index === root.selectedIndex
                        strong: index === root.selectedIndex
                        Column { width: parent.width - 20; anchors.centerIn: parent; spacing: 4; Text { width: parent.width; text: modelData.label; color: "#F3FCFF"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 15; font.bold: true; font.letterSpacing: 1 } Text { width: parent.width; text: modelData.hint; color: "#77A9C8"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11; font.bold: true } }
                    }
                }
            }
        }
    }
}
