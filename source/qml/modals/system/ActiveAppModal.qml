import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root

    property var contextData: ({})
    property var modalContext: ({})
    property var appData: null
    property int selectedAction: 0
    property int armedAction: -1
    property bool actionPending: false
    property string statusMessage: ""
    property bool statusIsError: false

    property color focusBlue: "#7DF9FF"
    property color successGreen: "#22FF88"
    property color warningGold: "#F5C542"
    property color dangerRed: "#FF3040"
    property color mutedText: "#8AA6C8"

    readonly property var actionModel: [
        { "key": "start", "title": "START", "subtitle": "Start the service, container, or app session", "color": successGreen },
        { "key": "stop", "title": "STOP", "subtitle": "Stop the app gracefully", "color": warningGold },
        { "key": "restart", "title": "RESTART", "subtitle": "Stop and start the app cleanly", "color": focusBlue },
        { "key": "kill", "title": "KILL", "subtitle": "Force terminate the backend", "color": dangerRed }
    ]

    signal closed()
    signal actionRequested(string action, var payload)

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 999
    color: "#D802050B"
    Keys.enabled: visible

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        appData = extractApp(contextData)
        selectedAction = appIsRunning() ? 1 : 0
        armedAction = -1
        actionPending = false
        statusMessage = ""
        statusIsError = false
        visible = true
        forceActiveFocus()
    }

    function openModal(context) { open(context) }

    function close() {
        if (!visible)
            return
        visible = false
        armedAction = -1
        actionPending = false
        statusMessage = ""
        appData = null
        closed()
    }

    function closeModal() { close() }

    function extractApp(context) {
        if (!context)
            return null
        try { if (context.app) return context.app } catch (e1) {}
        try { if (context.appData) return context.appData } catch (e2) {}
        return context
    }

    function clean(value) {
        if (value === undefined || value === null)
            return ""
        var text = String(value).trim()
        return text === "undefined" || text === "null" ? "" : text
    }

    function valueFor(keys, fallbackValue) {
        if (!appData)
            return fallbackValue
        for (var i = 0; i < keys.length; ++i) {
            try {
                var value = appData[keys[i]]
                if (clean(value).length > 0)
                    return value
            } catch (error) {}
        }
        return fallbackValue
    }

    function appName() { return clean(valueFor(["displayName", "name", "title", "id"], "Application")) }
    function appId() { return clean(valueFor(["id", "appId", "desktopId"], "")) }
    function appType() { return clean(valueFor(["type", "appType", "kind"], "unknown")) }
    function appService() { return clean(valueFor(["docker", "container", "service", "serviceName"], "")) }
    function appPid() { return clean(valueFor(["pid", "processId", "mainPid"], "")) }

    function appIsRunning() {
        var raw = valueFor(["running", "isRunning", "active", "serviceRunning", "uiRunning"], false)
        if (raw === true)
            return true
        var text = String(raw).toLowerCase()
        if (text === "true" || text === "1" || text === "running" || text === "active" || text === "online")
            return true
        var state = clean(valueFor(["status", "state", "statusText"], "")).toLowerCase()
        return state === "running" || state === "active" || state === "online"
    }

    function actionAt(index) {
        if (index < 0 || index >= actionModel.length)
            return actionModel[0]
        return actionModel[index]
    }

    function actionDisabled(index) {
        var key = actionAt(index).key
        if (key === "start")
            return appIsRunning()
        if (key === "stop")
            return !appIsRunning()
        return false
    }

    function actionNeedsConfirmation(index) {
        var key = actionAt(index).key
        return key === "stop" || key === "restart" || key === "kill"
    }

    function payload(key) {
        return {
            "app": appData,
            "appId": appId(),
            "service": appService(),
            "pid": appPid(),
            "force": key === "kill",
            "requestedAction": key
        }
    }

    function moveSelection(delta) {
        if (actionPending)
            return true
        selectedAction = (selectedAction + delta + actionModel.length) % actionModel.length
        armedAction = -1
        statusMessage = ""
        statusIsError = false
        return true
    }

    function activateSelected() {
        if (actionPending)
            return true
        if (!appData) {
            statusMessage = "APPLICATION DATA IS NOT AVAILABLE"
            statusIsError = true
            return true
        }
        if (actionDisabled(selectedAction)) {
            statusMessage = actionAt(selectedAction).key === "start"
                            ? "THE APP IS ALREADY ACTIVE"
                            : "THE APP IS ALREADY INACTIVE"
            statusIsError = false
            return true
        }

        var action = actionAt(selectedAction)
        if (actionNeedsConfirmation(selectedAction) && armedAction !== selectedAction) {
            armedAction = selectedAction
            statusMessage = action.key === "kill"
                            ? "KILL ARMED — PRESS X AGAIN TO FORCE TERMINATE"
                            : action.title + " ARMED — PRESS X AGAIN TO CONFIRM"
            statusIsError = action.key === "kill"
            return true
        }

        actionPending = true
        statusMessage = "REQUESTING " + action.title + " FOR " + appName().toUpperCase()
        statusIsError = false
        actionRequested(action.key, payload(action.key))
        armedAction = -1
        return true
    }

    function cancelOrClose() {
        if (armedAction >= 0) {
            armedAction = -1
            statusMessage = "ACTION DISARMED"
            statusIsError = false
            return true
        }
        actionRequested("cancel", payload("cancel"))
        close()
        return true
    }

    function normalize(value) {
        var action = String(value || "").trim().toLowerCase()
        if (action === "x" || action === "cross" || action === "primary" || action === "confirm") return "primary"
        if (action === "o" || action === "circle" || action === "cancel" || action === "back") return "cancel"
        if (action === "dpad_left") return "left"
        if (action === "dpad_right") return "right"
        if (action === "dpad_up") return "up"
        if (action === "dpad_down") return "down"
        return action
    }

    function handleControllerPressed(value) {
        if (!visible)
            return false
        var action = normalize(value)
        if (action === "cancel") return cancelOrClose()
        if (action === "left" || action === "up") return moveSelection(-1)
        if (action === "right" || action === "down") return moveSelection(1)
        if (action === "primary" || action === "system") return activateSelected()
        return true
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) action = "left"
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) action = "right"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) action = "cancel"
        if (action.length > 0) {
            event.accepted = true
            handleControllerPressed(action)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#B0000000"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 140, 1420)
        height: Math.min(parent.height - 120, 760)
        radius: 34
        color: "#071426"
        border.width: 2
        border.color: root.armedAction >= 0 ? root.actionAt(root.armedAction).color : "#7DF9FF"
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 116
            color: "#0A1A2D"
            border.width: 1
            border.color: "#2F4E6A"

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 34
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Text {
                    text: root.appName().toUpperCase()
                    color: "#FFFFFF"
                    font.pixelSize: 30
                    font.bold: true
                    font.letterSpacing: 1.4
                }

                Text {
                    text: root.appType().toUpperCase() + "  •  " + (root.appIsRunning() ? "ACTIVE" : "INACTIVE")
                    color: root.appIsRunning() ? "#79FFB1" : "#FF9EAA"
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.3
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                width: 180
                height: 42
                radius: 21
                color: root.appIsRunning() ? "#102D21" : "#311018"
                border.width: 1
                border.color: root.appIsRunning() ? root.successGreen : root.dangerRed

                Text {
                    anchors.centerIn: parent
                    text: root.appIsRunning() ? "RUNNING" : "STOPPED"
                    color: root.appIsRunning() ? "#A9FFD1" : "#FFB2BC"
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.8
                }
            }
        }

        Grid {
            id: actionGrid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 150
            anchors.leftMargin: 34
            anchors.rightMargin: 34
            columns: 4
            columnSpacing: 18

            Repeater {
                model: root.actionModel

                Rectangle {
                    width: (actionGrid.width - actionGrid.columnSpacing * 3) / 4
                    height: 290
                    radius: 26
                    color: root.armedAction === index
                           ? "#321019"
                           : root.selectedAction === index
                             ? "#102B45"
                             : "#0A1727"
                    opacity: root.actionDisabled(index) ? 0.48 : 1.0
                    border.width: root.selectedAction === index ? 3 : 1
                    border.color: root.armedAction === index
                                  ? modelData.color
                                  : root.selectedAction === index
                                    ? modelData.color
                                    : "#36516F"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 18

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 88
                            height: 88
                            radius: 26
                            color: Qt.rgba(modelData.color.r, modelData.color.g, modelData.color.b, 0.12)
                            border.width: 2
                            border.color: modelData.color

                            Text {
                                anchors.centerIn: parent
                                text: modelData.title.substring(0, 1)
                                color: modelData.color
                                font.pixelSize: 34
                                font.bold: true
                            }
                        }

                        Text {
                            width: parent.width
                            text: modelData.title
                            color: "#FFFFFF"
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 22
                            font.bold: true
                            font.letterSpacing: 1.3
                        }

                        Text {
                            width: parent.width
                            text: root.armedAction === index
                                  ? (modelData.key === "kill" ? "PRESS X AGAIN TO FORCE" : "PRESS X AGAIN TO CONFIRM")
                                  : modelData.subtitle
                            color: root.armedAction === index ? "#FFB2BC" : "#8FA9C2"
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            font.pixelSize: 14
                            font.bold: root.armedAction === index
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selectedAction = index
                            root.activateSelected()
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 86
            color: "#08182A"
            border.width: 1
            border.color: "#2F4E6A"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.64
                text: root.statusMessage.length > 0
                      ? root.statusMessage
                      : "Choose a backend action. Stop, Restart, and Kill require confirmation."
                color: root.statusIsError ? "#FF9EAA" : "#9FD8FF"
                font.pixelSize: 14
                font.bold: root.statusMessage.length > 0
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                text: "◀▶ SELECT   X ACTION   O BACK"
                color: "#7895B1"
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 0.9
            }
        }
    }
}
