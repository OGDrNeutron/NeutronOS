import QtQuick 2.15

import "../components"

Item {
    id: root

    anchors.fill: parent
    visible: false
    focus: visible
    z: 1000

    property string clipboardText: ""
    property string selectionText: ""
    property int selectedIndex: 0

    readonly property var actions: [
        { "id": "copy-selection", "label": "COPY SELECTION", "hint": "Selection to clipboard" },
        { "id": "paste-draft", "label": "PASTE DRAFT", "hint": "Into type bar" },
        { "id": "paste-pty", "label": "PASTE PTY", "hint": "Direct shell paste" },
        { "id": "clear", "label": "CLEAR", "hint": "Clear selection" }
    ]

    signal closeRequested()
    signal copySelectionRequested()
    signal pasteToDraftRequested()
    signal pasteToPtyRequested()
    signal clearSelectionRequested()

    function open() { visible = true; selectedIndex = 0; forceActiveFocus() }
    function close() { visible = false; closeRequested() }
    function moveLeft() { selectedIndex = Math.max(0, selectedIndex - 1) }
    function moveRight() { selectedIndex = Math.min(actions.length - 1, selectedIndex + 1) }

    function activateSelected() {
        var action = actions[selectedIndex]
        if (!action) return
        if (action.id === "copy-selection") copySelectionRequested()
        else if (action.id === "paste-draft") pasteToDraftRequested()
        else if (action.id === "paste-pty") pasteToPtyRequested()
        else if (action.id === "clear") clearSelectionRequested()
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

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.58 }

    TerminalGlassPanel {
        anchors.centerIn: parent
        width: Math.min(parent.width - 220, 920)
        height: 430
        radius: 32
        padding: 24
        strong: true
        focused: true

        Column {
            anchors.fill: parent
            spacing: 14

            Text {
                width: parent.width
                text: "CLIPBOARD BRIDGE"
                color: "#F3FCFF"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 28
                font.bold: true
                font.letterSpacing: 2
            }

            Row {
                width: parent.width
                height: 168
                spacing: 14

                TerminalGlassPanel {
                    width: (parent.width - 14) / 2
                    height: parent.height
                    radius: 22
                    padding: 14
                    focused: false

                    Column {
                        anchors.fill: parent
                        spacing: 8

                        Text { text: "SELECTION"; color: "#68D8FF"; font.pixelSize: 13; font.bold: true; font.letterSpacing: 1.5 }
                        Text {
                            width: parent.width
                            height: parent.height - 28
                            text: root.selectionText.length > 0 ? root.selectionText : "No selected text"
                            color: root.selectionText.length > 0 ? "#D9E8FF" : "#77A9C8"
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            font.family: "monospace"
                            font.pixelSize: 13
                        }
                    }
                }

                TerminalGlassPanel {
                    width: (parent.width - 14) / 2
                    height: parent.height
                    radius: 22
                    padding: 14
                    focused: false

                    Column {
                        anchors.fill: parent
                        spacing: 8

                        Text { text: "SHARED CLIPBOARD"; color: "#68D8FF"; font.pixelSize: 13; font.bold: true; font.letterSpacing: 1.5 }
                        Text {
                            width: parent.width
                            height: parent.height - 28
                            text: root.clipboardText.length > 0 ? root.clipboardText : "Clipboard empty"
                            color: root.clipboardText.length > 0 ? "#D9E8FF" : "#77A9C8"
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            font.family: "monospace"
                            font.pixelSize: 13
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: 88
                spacing: 12

                Repeater {
                    model: root.actions

                    delegate: TerminalGlassPanel {
                        width: (parent.width - 36) / 4
                        height: 82
                        radius: 20
                        padding: 8
                        focused: index === root.selectedIndex
                        danger: modelData.id === "paste-pty"
                        strong: index === root.selectedIndex

                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Text { width: parent.width; text: modelData.label; color: modelData.id === "paste-pty" ? "#FFD166" : "#F3FCFF"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 13; font.bold: true; font.letterSpacing: 1 }
                            Text { width: parent.width; text: modelData.hint; color: "#77A9C8"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 10; font.bold: true }
                        }
                    }
                }
            }

            Text { width: parent.width; text: "X ACTIVATE  •  O CLOSE"; color: "#77A9C8"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.4 }
        }
    }
}
