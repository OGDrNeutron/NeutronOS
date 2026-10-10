import QtQuick 2.15

import "../components"

Item {
    id: root

    anchors.fill: parent
    visible: false
    focus: visible
    z: 1000

    property var commands: []
    property int selectedIndex: 0
    property string armedQuickActionId: ""

    signal closeRequested()
    signal commandRequested(string commandId, bool requiresArmed)
    signal armRequested(string commandId)

    function open() {
        visible = true
        forceActiveFocus()
    }

    function close() {
        visible = false
        closeRequested()
    }

    function moveLeft() { quickGrid.moveLeft(); selectedIndex = quickGrid.selectedIndex }
    function moveRight() { quickGrid.moveRight(); selectedIndex = quickGrid.selectedIndex }
    function moveUp() { quickGrid.moveUp(); selectedIndex = quickGrid.selectedIndex }
    function moveDown() { quickGrid.moveDown(); selectedIndex = quickGrid.selectedIndex }
    function activateSelected() { quickGrid.activateSelected() }

    function normalizeControllerAction(button) {
        var b = String(button || "").toLowerCase()
        if (b === "primary" || b === "x" || b === "cross" || b === "a") return "primary"
        if (b === "cancel" || b === "o" || b === "circle" || b === "b") return "cancel"
        if (b === "up" || b === "dpad_up") return "up"
        if (b === "down" || b === "dpad_down") return "down"
        if (b === "left" || b === "dpad_left") return "left"
        if (b === "right" || b === "dpad_right") return "right"
        if (b === "system" || b === "start" || b === "options" || b === "menu") return "system"
        return b
    }

    function handleControllerPressed(button) {
        if (!visible) return false
        var action = normalizeControllerAction(button)
        if (action === "up") { moveUp(); return true }
        if (action === "down") { moveDown(); return true }
        if (action === "left") { moveLeft(); return true }
        if (action === "right") { moveRight(); return true }
        if (action === "primary") { activateSelected(); return true }
        if (action === "cancel" || action === "system") { close(); return true }
        return true
    }

    function handleControllerReleased(button) { return visible }

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.58 }

    TerminalGlassPanel {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 42
        anchors.rightMargin: 42
        anchors.bottomMargin: 116
        height: 420
        radius: 32
        padding: 24
        strong: true
        focused: true

        Column {
            anchors.fill: parent
            spacing: 16

            Row {
                width: parent.width
                height: 44

                Text {
                    width: parent.width * 0.55
                    text: "QUICK COMMANDS"
                    color: "#F3FCFF"
                    font.pixelSize: 28
                    font.bold: true
                    font.letterSpacing: 2
                }

                Text {
                    width: parent.width * 0.45
                    text: "X RUN  •  O CLOSE  •  RED NEEDS ARM"
                    color: "#77A9C8"
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1
                }
            }

            QuickCommandGrid {
                id: quickGrid
                width: parent.width
                height: parent.height - 60
                commands: root.commands
                selectedIndex: root.selectedIndex
                armedQuickActionId: root.armedQuickActionId
                gridFocused: root.visible

                onSelectedIndexChanged: root.selectedIndex = selectedIndex
                onActionRequested: function(commandId, requiresArmed) { root.commandRequested(commandId, requiresArmed) }
                onArmRequested: function(commandId) { root.armRequested(commandId) }
            }
        }
    }

    Keys.onPressed: function(event) {
        if (!visible) return
        if (event.key === Qt.Key_Up) { moveUp(); event.accepted = true; return }
        if (event.key === Qt.Key_Down) { moveDown(); event.accepted = true; return }
        if (event.key === Qt.Key_Left) { moveLeft(); event.accepted = true; return }
        if (event.key === Qt.Key_Right) { moveRight(); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activateSelected(); event.accepted = true; return }
        if (event.key === Qt.Key_Escape) { close(); event.accepted = true; return }
    }
}
