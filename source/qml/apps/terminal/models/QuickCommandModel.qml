import QtQuick 2.15

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var terminalBackend: null
    property var commands: []
    property int selectedIndex: 0
    property string armedQuickActionId: ""

    readonly property bool backendAvailable: terminalBackend !== null && terminalBackend !== undefined

    signal commandRunRequested(string commandId, bool requiresArmed)
    signal commandArmRequested(string commandId)

    function refresh() {
        commands = backendAvailable ? terminalBackend.quickCommands : []
        armedQuickActionId = backendAvailable ? terminalBackend.armedQuickActionId : ""
        clampIndex()
    }

    function commandCount() {
        return commands ? commands.length : 0
    }

    function clampIndex() {
        var count = commandCount()
        if (count <= 0) {
            selectedIndex = 0
            return
        }
        selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex))
    }

    function selectedCommand() {
        clampIndex()
        if (commandCount() <= 0)
            return null
        return commands[selectedIndex]
    }

    function moveLeft(columns) {
        clampIndex()
        selectedIndex = Math.max(0, selectedIndex - 1)
    }

    function moveRight(columns) {
        clampIndex()
        selectedIndex = Math.min(commandCount() - 1, selectedIndex + 1)
    }

    function moveUp(columns) {
        clampIndex()
        selectedIndex = Math.max(0, selectedIndex - Math.max(1, columns || 3))
    }

    function moveDown(columns) {
        clampIndex()
        selectedIndex = Math.min(commandCount() - 1, selectedIndex + Math.max(1, columns || 3))
    }

    function activateSelected() {
        var command = selectedCommand()
        if (!command)
            return

        if (command.enabled === false)
            return

        var id = String(command.id || "")
        var requiresArmed = command.requiresArmed === true

        if (requiresArmed && armedQuickActionId !== id) {
            commandArmRequested(id)
            return
        }

        commandRunRequested(id, requiresArmed)
    }

    function arm(commandId) {
        if (!backendAvailable)
            return
        terminalBackend.armQuickAction(commandId)
        refresh()
    }

    function clearArmed() {
        if (!backendAvailable)
            return
        terminalBackend.clearArmedQuickAction()
        refresh()
    }

    function run(commandId, requiresArmed, source) {
        if (!backendAvailable)
            return null
        var result = terminalBackend.runQuickCommand(commandId, requiresArmed, source || "qml")
        refresh()
        return result
    }

    Connections {
        target: root.backendAvailable ? root.terminalBackend : null
        ignoreUnknownSignals: true

        function onQuickCommandsChanged() {
            root.refresh()
        }

        function onArmedQuickActionChanged() {
            root.refresh()
        }

        function onModeChanged() {
            root.refresh()
        }
    }

    Component.onCompleted: refresh()
}
