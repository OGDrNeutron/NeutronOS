import QtQuick 2.15

import "../components"

Item {
    id: root

    anchors.fill: parent
    visible: false
    focus: visible
    z: 1250

    property string snippetId: ""
    property string labelText: ""
    property string categoryText: "Custom"
    property string commandText: ""
    property int selectedRow: 0
    property string errorText: ""

    signal closeRequested()
    signal keyboardRequested(string fieldId, string value, string title)
    signal saveRequested(string snippetId, string label, string command, string category)

    function openForAdd() {
        snippetId = ""
        labelText = "New Snippet"
        categoryText = "Custom"
        commandText = ""
        selectedRow = 0
        errorText = ""
        visible = true
        forceActiveFocus()
    }

    function openForEdit(item) {
        snippetId = item ? String(item.id || "") : ""
        labelText = item ? String(item.label || "") : ""
        categoryText = item ? String(item.category || "Custom") : "Custom"
        commandText = item ? String(item.command || "") : ""
        selectedRow = 0
        errorText = ""
        visible = true
        forceActiveFocus()
    }

    function close() {
        visible = false
        errorText = ""
        closeRequested()
    }

    function setField(fieldId, value) {
        if (fieldId === "label") labelText = value
        else if (fieldId === "category") categoryText = value
        else if (fieldId === "command") commandText = value
        forceActiveFocus()
    }

    function activate() {
        if (selectedRow === 0)
            keyboardRequested("label", labelText, "Snippet Name")
        else if (selectedRow === 1)
            keyboardRequested("category", categoryText, "Snippet Category")
        else if (selectedRow === 2)
            keyboardRequested("command", commandText, "Command or Code")
        else if (selectedRow === 3) {
            if (labelText.trim().length === 0 || commandText.trim().length === 0) {
                errorText = "A name and command are required."
                return
            }
            saveRequested(snippetId, labelText.trim(), commandText, categoryText.trim().length > 0 ? categoryText.trim() : "Custom")
        } else {
            close()
        }
    }

    function normalizeAction(button) {
        var b = String(button || "").toLowerCase().replace(/\s+/g, "_").replace(/-/g, "_")
        if (b === "primary" || b === "x" || b === "cross" || b === "a") return "primary"
        if (b === "cancel" || b === "o" || b === "circle" || b === "b") return "cancel"
        if (b === "dpad_up") return "up"
        if (b === "dpad_down") return "down"
        return b
    }

    function handleControllerPressed(button) {
        if (!visible) return false
        var action = normalizeAction(button)
        if (action === "up") { selectedRow = Math.max(0, selectedRow - 1); return true }
        if (action === "down") { selectedRow = Math.min(4, selectedRow + 1); return true }
        if (action === "primary") { activate(); return true }
        if (action === "cancel") { close(); return true }
        return true
    }

    function handleControllerReleased(button) { return visible }

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.76 }

    TerminalGlassPanel {
        anchors.centerIn: parent
        width: Math.min(parent.width - 260, 1120)
        height: 720
        radius: 38
        padding: 28
        strong: true
        focused: true

        Column {
            anchors.fill: parent
            spacing: 16

            Text { width: parent.width; text: root.snippetId.length > 0 ? "EDIT SNIPPET" : "ADD SNIPPET"; color: "#F3FCFF"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 32; font.bold: true; font.letterSpacing: 2.2 }
            Text { width: parent.width; text: "Select a field with X. The NeutronOS virtual keyboard handles all text entry."; color: "#77A9C8"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 15 }

            Repeater {
                model: [
                    { id: "label", title: "NAME", value: root.labelText, hint: "Short label shown in the snippets menu" },
                    { id: "category", title: "CATEGORY", value: root.categoryText, hint: "Used by the left-side category rail" },
                    { id: "command", title: "COMMAND / CODE", value: root.commandText, hint: "Single command or multiline snippet" }
                ]

                delegate: Rectangle {
                    width: parent.width
                    height: modelData.id === "command" ? 210 : 108
                    radius: 22
                    color: index === root.selectedRow ? "#123A60" : "#071727DD"
                    border.width: index === root.selectedRow ? 3 : 1
                    border.color: index === root.selectedRow ? "#68D8FF" : "#2B4E6B"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 7
                        Text { text: modelData.title; color: index === root.selectedRow ? "#7DF9FF" : "#77A9C8"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.5 }
                        Text { width: parent.width; height: modelData.id === "command" ? 116 : 28; text: String(modelData.value || ""); color: "#F3FCFF"; font.family: modelData.id === "command" ? "monospace" : "sans-serif"; font.pixelSize: modelData.id === "command" ? 15 : 20; wrapMode: modelData.id === "command" ? Text.WrapAnywhere : Text.NoWrap; elide: modelData.id === "command" ? Text.ElideNone : Text.ElideRight }
                        Text { width: parent.width; text: modelData.hint; color: "#77A9C8"; font.pixelSize: 12; elide: Text.ElideRight }
                    }
                }
            }

            Row {
                width: parent.width
                height: 80
                spacing: 16

                Rectangle {
                    width: (parent.width - 16) / 2
                    height: parent.height
                    radius: 22
                    color: root.selectedRow === 3 ? "#14593E" : "#0A2A22"
                    border.width: root.selectedRow === 3 ? 3 : 1
                    border.color: root.selectedRow === 3 ? "#27FF9A" : "#23654E"
                    Text { anchors.centerIn: parent; text: "SAVE"; color: "#F3FCFF"; font.pixelSize: 20; font.bold: true; font.letterSpacing: 1.5 }
                }

                Rectangle {
                    width: (parent.width - 16) / 2
                    height: parent.height
                    radius: 22
                    color: root.selectedRow === 4 ? "#4D1720" : "#271016"
                    border.width: root.selectedRow === 4 ? 3 : 1
                    border.color: root.selectedRow === 4 ? "#FF5067" : "#6D2733"
                    Text { anchors.centerIn: parent; text: "CANCEL"; color: "#F3FCFF"; font.pixelSize: 20; font.bold: true; font.letterSpacing: 1.5 }
                }
            }

            Text { width: parent.width; height: 24; text: root.errorText; visible: text.length > 0; color: "#FF7185"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 14; font.bold: true }
        }
    }
}
