import QtQuick 2.15

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var terminalBackend: null

    property string navigationArea: "typebar"
    property int toolbarIndex: 0
    property int quickIndex: 0
    property string activeModal: ""

    readonly property bool backendAvailable: terminalBackend !== null && terminalBackend !== undefined
    readonly property bool backendRunning: backendAvailable ? terminalBackend.running : false
    readonly property bool ptyAlive: backendAvailable ? terminalBackend.ptyAlive : false
    readonly property bool developerMode: backendAvailable ? terminalBackend.developerMode : false
    readonly property string modeLabel: backendAvailable ? terminalBackend.modeLabel : "OFFLINE"
    readonly property string statusText: backendAvailable ? terminalBackend.statusText : "Terminal backend unavailable"
    readonly property string errorText: backendAvailable ? terminalBackend.error : "terminalManager is not exposed to QML"
    readonly property string promptLabel: backendAvailable ? terminalBackend.promptLabel : "terminal unavailable"
    readonly property string outputText: backendAvailable ? terminalBackend.outputText : "[NeutronOS Terminal] terminalManager unavailable\n"
    readonly property string inputDraft: backendAvailable ? terminalBackend.inputDraft : ""
    readonly property string clipboardText: backendAvailable ? terminalBackend.clipboardText : ""
    readonly property string selectionText: backendAvailable ? terminalBackend.selectionText : ""
    readonly property string webUrl: backendAvailable ? terminalBackend.webUrl : ""
    readonly property string webToken: backendAvailable ? terminalBackend.webToken : ""
    readonly property string webPairingCode: backendAvailable && terminalBackend.webPairingCode !== undefined ? terminalBackend.webPairingCode : webToken
    readonly property int webPairingCodeSecondsRemaining: backendAvailable && terminalBackend.webPairingCodeSecondsRemaining !== undefined ? terminalBackend.webPairingCodeSecondsRemaining : 0
    readonly property bool webPairingCodeActive: backendAvailable && terminalBackend.webPairingCodeActive !== undefined ? terminalBackend.webPairingCodeActive : false
    readonly property bool webMirrorRunning: backendAvailable ? terminalBackend.webMirrorRunning : false
    readonly property bool webMirrorEnabled: backendAvailable ? terminalBackend.webMirrorEnabled : false
    readonly property int webClientCount: backendAvailable ? terminalBackend.webClientCount : 0
    readonly property int authenticatedWebClientCount: backendAvailable && terminalBackend.authenticatedWebClientCount !== undefined
                                                      ? terminalBackend.authenticatedWebClientCount
                                                      : webClientCount

    readonly property bool modalOpen: activeModal.length > 0

    readonly property var toolbarActions: [
        { "id": "send", "label": "SEND", "hint": "Run type bar", "danger": false },
        { "id": "keyboard", "label": "KEYBOARD", "hint": "Virtual keyboard", "danger": false },
        { "id": "snippets", "label": "SNIPPETS", "hint": "Saved commands", "danger": false },
        { "id": "quick", "label": "QUICK", "hint": "Quick commands", "danger": false },
        { "id": "copy", "label": root.clipboardText.length > 0 ? "PASTE" : "COPY", "hint": root.clipboardText.length > 0 ? "Paste to type bar" : "Clipboard", "danger": false },
        { "id": "web", "label": "REMOTE", "hint": "Terminal mirror", "danger": false },
        { "id": "customize", "label": "CUSTOMIZE", "hint": "Theme, type & layout", "danger": false },
        { "id": "dev", "label": "DEV", "hint": "Mode status", "danger": false },
        { "id": "clear", "label": "CLEAR", "hint": "Clear screen", "danger": false },
        { "id": "ctrlc", "label": "CTRL+C", "hint": "Cancel command", "danger": true },
        { "id": "exit", "label": "EXIT", "hint": "Return console", "danger": true }
    ]

    signal toolbarActionRequested(string actionId)
    signal modalRequested(string modalId)
    signal exitRequested()

    function clampToolbarIndex() {
        toolbarIndex = Math.max(0, Math.min(toolbarActions.length - 1, toolbarIndex))
    }

    function selectedToolbarAction() {
        clampToolbarIndex()
        return toolbarActions[toolbarIndex]
    }

    function normalizeControllerAction(button) {
        var b = String(button || "").toLowerCase()
        b = b.replace(/\s+/g, "_").replace(/-/g, "_")

        if (b === "primary" || b === "x" || b === "cross" || b === "a")
            return "primary"
        if (b === "cancel" || b === "o" || b === "circle" || b === "b")
            return "cancel"
        if (b === "secondary" || b === "square" || b === "y")
            return "secondary"
        if (b === "context" || b === "triangle")
            return "context"
        if (b === "system" || b === "start" || b === "options" || b === "menu")
            return "system"
        if (b === "quick" || b === "select" || b === "share" || b === "create")
            return "quick"
        if (b === "home" || b === "ps" || b === "playstation" || b === "guide")
            return "home"
        if (b === "dpad_up" || b === "leftstick_up" || b === "rightstick_up")
            return "up"
        if (b === "dpad_down" || b === "leftstick_down" || b === "rightstick_down")
            return "down"
        if (b === "dpad_left" || b === "leftstick_left" || b === "rightstick_left")
            return "left"
        if (b === "dpad_right" || b === "leftstick_right" || b === "rightstick_right")
            return "right"

        return b
    }

    function moveToolbarLeft() {
        toolbarIndex = Math.max(0, toolbarIndex - 1)
    }

    function moveToolbarRight() {
        toolbarIndex = Math.min(toolbarActions.length - 1, toolbarIndex + 1)
    }

    function activateToolbar() {
        var action = selectedToolbarAction()
        if (!action)
            return
        toolbarActionRequested(String(action.id || ""))
    }

    function setModal(modalId) {
        activeModal = modalId || ""
    }

    function clearModal() {
        activeModal = ""
    }

    function commitDraft() {
        if (backendAvailable)
            terminalBackend.commitDraft("qml")
    }

    function clearDraft() {
        if (backendAvailable)
            terminalBackend.clearDraft("qml")
    }

    function backspaceDraft() {
        if (backendAvailable)
            terminalBackend.backspaceDraft("qml")
    }

    function clearScreen() {
        if (backendAvailable)
            terminalBackend.clearScreen()
    }

    function sendCtrlC() {
        if (backendAvailable)
            terminalBackend.sendKey("ctrl-c", "qml")
    }

    function startBackend() {
        if (backendAvailable)
            terminalBackend.start()
    }

    function stopBackend() {
        if (backendAvailable)
            terminalBackend.stop()
    }
}
