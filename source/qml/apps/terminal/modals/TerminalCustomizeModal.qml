import QtQuick 2.15

import "../components"

Item {
    id: root

    anchors.fill: parent
    visible: false
    focus: visible
    z: 1000

    property string tintColor: "#68D8FF"
    property string textColor: "#F3FCFF"
    property string startupMessage: "Welcome to NeutronOS Gemini."
    property int viewportFontSize: 16
    property int typebarFontSize: 18
    property int panelOpacityPercent: 100
    property bool timestampsVisible: true
    property int themePresetIndex: -1
    property string statusText: "Adjust the terminal workspace, then save to keep the changes."
    property int selectedIndex: 0

    readonly property var themePresets: [
        { "name": "GEMINI", "tint": "#68D8FF", "text": "#F3FCFF" },
        { "name": "EMERALD", "tint": "#27FF9A", "text": "#EFFFF7" },
        { "name": "VIOLET", "tint": "#B794FF", "text": "#F7F1FF" },
        { "name": "AMBER", "tint": "#FFD166", "text": "#FFF8E7" },
        { "name": "CARBON", "tint": "#9DB1C5", "text": "#F4F7FA" }
    ]

    readonly property var rows: [
        { "id": "preset", "label": "THEME PRESET", "value": root.presetName(), "hint": "LEFT/RIGHT CYCLE" },
        { "id": "tint", "label": "INTERFACE TINT", "value": root.tintColor, "hint": "X EDIT #RRGGBB" },
        { "id": "text", "label": "TERMINAL TEXT", "value": root.textColor, "hint": "X EDIT #RRGGBB" },
        { "id": "viewportFont", "label": "VIEWPORT TEXT SIZE", "value": String(root.viewportFontSize) + " px", "hint": "LEFT/RIGHT" },
        { "id": "typebarFont", "label": "TYPE BAR TEXT SIZE", "value": String(root.typebarFontSize) + " px", "hint": "LEFT/RIGHT" },
        { "id": "panelOpacity", "label": "WORKSPACE PANEL OPACITY", "value": String(root.panelOpacityPercent) + "%", "hint": "LEFT/RIGHT" },
        { "id": "timestamps", "label": "PROMPT TIMESTAMPS", "value": root.timestampsVisible ? "ON  •  12-HOUR AM/PM" : "OFF", "hint": "LEFT/RIGHT OR X" },
        { "id": "startup", "label": "SHELL STARTUP MESSAGE", "value": root.startupMessage, "hint": "X EDIT" },
        { "id": "save", "label": "SAVE", "value": "Apply and persist customization", "hint": "X APPLY" },
        { "id": "reset", "label": "RESET", "value": "Restore NeutronOS Terminal defaults", "hint": "X RESET" },
        { "id": "close", "label": "CLOSE", "value": "Return to Terminal", "hint": "O / X CLOSE" }
    ]

    signal closeRequested()
    signal keyboardRequested(string fieldId, string value, string title)
    signal saveRequested(string tintColor, string textColor, string startupMessage,
                         int viewportFontSize, int typebarFontSize,
                         int panelOpacityPercent, bool timestampsVisible)
    signal resetRequested()

    function clampValue(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, Number(value || 0)))
    }

    function presetName() {
        return themePresetIndex >= 0 && themePresetIndex < themePresets.length
               ? String(themePresets[themePresetIndex].name)
               : "CUSTOM"
    }

    function syncPresetFromColors() {
        var tint = String(tintColor || "").toUpperCase()
        var text = String(textColor || "").toUpperCase()
        themePresetIndex = -1
        for (var i = 0; i < themePresets.length; ++i) {
            if (String(themePresets[i].tint).toUpperCase() === tint &&
                    String(themePresets[i].text).toUpperCase() === text) {
                themePresetIndex = i
                break
            }
        }
    }

    function applyPreset(indexValue) {
        if (themePresets.length <= 0)
            return
        var index = Number(indexValue || 0) % themePresets.length
        if (index < 0)
            index += themePresets.length
        themePresetIndex = index
        tintColor = String(themePresets[index].tint)
        textColor = String(themePresets[index].text)
        statusText = String(themePresets[index].name) + " preset selected. Save to persist it."
    }

    function cyclePreset(delta) {
        var start = themePresetIndex >= 0 ? themePresetIndex : 0
        applyPreset(start + Number(delta || 0))
    }

    function open() {
        viewportFontSize = Math.round(clampValue(viewportFontSize, 13, 22))
        typebarFontSize = Math.round(clampValue(typebarFontSize, 14, 22))
        panelOpacityPercent = Math.round(clampValue(panelOpacityPercent, 65, 100) / 5) * 5
        syncPresetFromColors()
        visible = true
        selectedIndex = 0
        statusText = "Adjust the terminal workspace, then save to keep the changes."
        forceActiveFocus()
    }

    function close() {
        visible = false
        closeRequested()
    }

    function setField(fieldId, value) {
        if (fieldId === "tint") {
            tintColor = String(value || "").trim()
            themePresetIndex = -1
        } else if (fieldId === "text") {
            textColor = String(value || "").trim()
            themePresetIndex = -1
        } else if (fieldId === "startup") {
            startupMessage = String(value || "")
        }
    }

    function moveUp() { selectedIndex = Math.max(0, selectedIndex - 1) }
    function moveDown() { selectedIndex = Math.min(rows.length - 1, selectedIndex + 1) }

    function adjustSelected(delta) {
        var row = rows[selectedIndex]
        if (!row)
            return
        var step = Number(delta || 0)
        if (row.id === "preset") {
            cyclePreset(step)
        } else if (row.id === "viewportFont") {
            viewportFontSize = Math.round(clampValue(viewportFontSize + step, 13, 22))
        } else if (row.id === "typebarFont") {
            typebarFontSize = Math.round(clampValue(typebarFontSize + step, 14, 22))
        } else if (row.id === "panelOpacity") {
            panelOpacityPercent = Math.round(clampValue(panelOpacityPercent + step * 5, 65, 100) / 5) * 5
        } else if (row.id === "timestamps") {
            timestampsVisible = !timestampsVisible
        }
    }

    function activateSelected() {
        var row = rows[selectedIndex]
        if (!row) return
        if (row.id === "preset") cyclePreset(1)
        else if (row.id === "tint") keyboardRequested("tint", tintColor, "Interface Tint — #RRGGBB")
        else if (row.id === "text") keyboardRequested("text", textColor, "Terminal Text — #RRGGBB")
        else if (row.id === "viewportFont" || row.id === "typebarFont" || row.id === "panelOpacity") adjustSelected(1)
        else if (row.id === "timestamps") timestampsVisible = !timestampsVisible
        else if (row.id === "startup") keyboardRequested("startup", startupMessage, "Shell Startup Message")
        else if (row.id === "save") saveRequested(tintColor, textColor, startupMessage,
                                                   viewportFontSize, typebarFontSize,
                                                   panelOpacityPercent, timestampsVisible)
        else if (row.id === "reset") resetRequested()
        else close()
    }

    function normalizeControllerAction(button) {
        var b = String(button || "").toLowerCase().replace(/\s+/g, "_").replace(/-/g, "_")
        if (b === "primary" || b === "x" || b === "cross" || b === "a") return "primary"
        if (b === "cancel" || b === "o" || b === "circle" || b === "b") return "cancel"
        if (b === "dpad_up" || b === "leftstick_up" || b === "rightstick_up" || b === "up") return "up"
        if (b === "dpad_down" || b === "leftstick_down" || b === "rightstick_down" || b === "down") return "down"
        if (b === "dpad_left" || b === "leftstick_left" || b === "rightstick_left" || b === "left") return "left"
        if (b === "dpad_right" || b === "leftstick_right" || b === "rightstick_right" || b === "right") return "right"
        return b
    }

    function handleControllerPressed(button) {
        if (!visible) return false
        var action = normalizeControllerAction(button)
        if (action === "up") { moveUp(); return true }
        if (action === "down") { moveDown(); return true }
        if (action === "left") { adjustSelected(-1); return true }
        if (action === "right") { adjustSelected(1); return true }
        if (action === "primary") { activateSelected(); return true }
        if (action === "cancel") { close(); return true }
        return true
    }

    function handleControllerReleased(button) { return visible }

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.62 }

    TerminalGlassPanel {
        anchors.centerIn: parent
        width: Math.min(parent.width - 220, 1040)
        height: Math.min(parent.height - 110, 860)
        radius: 34
        padding: 24
        strong: true
        focused: true
        accentColor: root.tintColor

        Column {
            anchors.fill: parent
            spacing: 10

            Text {
                width: parent.width
                text: "CUSTOMIZE TERMINAL"
                color: root.textColor
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 29
                font.bold: true
                font.letterSpacing: 2
            }

            Text {
                width: parent.width
                text: "Theme, terminal typography, workspace glass and prompt timing. Color and banner settings remain compatible with the existing Terminal appearance profile."
                color: "#B9EEFF"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 14
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Rectangle {
                    width: 156
                    height: 34
                    radius: 17
                    color: "#0B1728"
                    border.width: 1
                    border.color: root.tintColor
                    Text {
                        anchors.centerIn: parent
                        text: root.presetName()
                        color: root.tintColor
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.0
                    }
                }

                Rectangle {
                    width: 156
                    height: 34
                    radius: 17
                    color: "#0B1728"
                    border.width: 1
                    border.color: "#31536A"
                    Text {
                        anchors.centerIn: parent
                        text: root.timestampsVisible ? "TIMESTAMPS ON" : "TIMESTAMPS OFF"
                        color: root.timestampsVisible ? "#7DFFB6" : "#9AAAB9"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }

                Rectangle {
                    width: 210
                    height: 34
                    radius: 17
                    color: "#0B1728"
                    border.width: 1
                    border.color: "#31536A"
                    Text {
                        anchors.centerIn: parent
                        text: "VIEW " + root.viewportFontSize + "  •  TYPE " + root.typebarFontSize
                        color: root.textColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 5

                Repeater {
                    model: root.rows
                    delegate: Rectangle {
                        width: parent.width
                        height: (modelData.id === "startup") ? 54 : 48
                        radius: 14
                        color: index === root.selectedIndex ? "#18324BEF" : "#081522D8"
                        border.width: index === root.selectedIndex ? 2 : 1
                        border.color: index === root.selectedIndex ? root.tintColor : "#28485E"

                        Rectangle {
                            visible: modelData.id === "tint" || modelData.id === "text"
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 8
                            color: modelData.id === "tint" ? root.tintColor : root.textColor
                            border.width: 1
                            border.color: "#FFFFFF"
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: (modelData.id === "tint" || modelData.id === "text") ? 54 : 15
                            anchors.right: hintText.left
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: modelData.label
                                color: root.textColor
                                font.pixelSize: 13
                                font.bold: true
                                font.letterSpacing: 0.9
                            }

                            Text {
                                width: parent.width
                                text: modelData.value
                                color: modelData.id === "save" ? "#7DFFB6"
                                     : modelData.id === "reset" ? "#FFD166"
                                     : modelData.id === "timestamps" && root.timestampsVisible ? "#7DFFB6"
                                     : "#B9EEFF"
                                elide: Text.ElideMiddle
                                font.pixelSize: 12
                                font.family: modelData.id === "startup" ? "monospace" : "sans-serif"
                            }
                        }

                        Text {
                            id: hintText
                            anchors.right: parent.right
                            anchors.rightMargin: 15
                            anchors.verticalCenter: parent.verticalCenter
                            width: 180
                            text: modelData.hint
                            color: index === root.selectedIndex ? root.tintColor : "#6F91A9"
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 0.6
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.statusText
                color: root.tintColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                font.bold: true
            }

            Text {
                width: parent.width
                text: "UP/DOWN SELECT  •  LEFT/RIGHT ADJUST  •  X EDIT/ACTIVATE  •  O CLOSE"
                color: "#77A9C8"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.0
            }
        }
    }
}
