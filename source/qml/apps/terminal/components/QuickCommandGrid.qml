import QtQuick 2.15

Item {
    id: root

    property var commands: []
    property int selectedIndex: 0
    property string armedQuickActionId: ""
    property bool gridFocused: false

    property int columns: 3
    property real cellHeight: 84
    property real cellSpacing: 12

    signal actionRequested(string commandId, bool requiresArmed)
    signal armRequested(string commandId)

    function commandCount() {
        return commands ? commands.length : 0
    }

    function clampIndex() {
        if (commandCount() <= 0) {
            selectedIndex = 0
            return
        }
        selectedIndex = Math.max(0, Math.min(commandCount() - 1, selectedIndex))
    }

    function selectedCommand() {
        clampIndex()
        if (commandCount() <= 0)
            return null
        return commands[selectedIndex]
    }

    function moveLeft() {
        clampIndex()
        selectedIndex = Math.max(0, selectedIndex - 1)
    }

    function moveRight() {
        clampIndex()
        selectedIndex = Math.min(commandCount() - 1, selectedIndex + 1)
    }

    function moveUp() {
        clampIndex()
        selectedIndex = Math.max(0, selectedIndex - columns)
    }

    function moveDown() {
        clampIndex()
        selectedIndex = Math.min(commandCount() - 1, selectedIndex + columns)
    }

    function activateSelected() {
        var command = selectedCommand()
        if (!command || command.enabled === false)
            return

        var id = String(command.id || "")
        var needsArmed = command.requiresArmed === true

        if (needsArmed && armedQuickActionId !== id) {
            armRequested(id)
            return
        }

        actionRequested(id, needsArmed)
    }

    Grid {
        id: grid
        anchors.fill: parent
        columns: root.columns
        spacing: root.cellSpacing

        Repeater {
            model: root.commands || []

            delegate: TerminalGlassPanel {
                width: (grid.width - (root.cellSpacing * (root.columns - 1))) / root.columns
                height: root.cellHeight
                radius: 20
                padding: 12
                focused: root.gridFocused && index === root.selectedIndex
                danger: modelData.requiresArmed === true && root.armedQuickActionId === modelData.id
                success: modelData.enabled !== false && modelData.requiresArmed !== true
                strong: index === root.selectedIndex

                Column {
                    anchors.fill: parent
                    spacing: 5

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.enabled === false ? "#606A78" : modelData.requiresArmed ? "#FF3048" : "#27FF9A"
                        }

                        Text {
                            width: parent.width - 18
                            text: modelData.label || modelData.id || "Command"
                            color: modelData.enabled === false ? "#7F8898" : "#F3FCFF"
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            font.bold: true
                        }
                    }

                    Text {
                        width: parent.width
                        text: modelData.developerOnly ? "Developer Mode" : modelData.requiresArmed ? "Armed confirmation" : modelData.group || "General"
                        color: modelData.requiresArmed ? "#FFD166" : "#77A9C8"
                        elide: Text.ElideRight
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: modelData.command || ""
                        color: "#77A9C8"
                        elide: Text.ElideRight
                        font.family: "monospace"
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.commandCount() <= 0
        text: "No quick commands available"
        color: "#77A9C8"
        font.pixelSize: 18
        font.bold: true
    }
}
