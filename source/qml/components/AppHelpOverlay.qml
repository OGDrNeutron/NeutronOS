import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 50000

    property string appId: ""
    property string appName: "Application"
    property string description: ""
    property int introductionNumber: 0
    property bool automaticIntroduction: false
    property int selectedControl: 0
    property var appData: ({})

    signal closed()

    readonly property var controls: controlsForApp(appId)

    function controlsForApp(idValue) {
        var id = String(idValue || "").toLowerCase()
        var common = [
            { button: "D-PAD / LEFT STICK", action: "Navigate" },
            { button: "O", action: "Back, cancel or close" },
            { button: "OPTIONS", action: "App menu or options" },
            { button: "SHARE / QUICK", action: "Open this Help panel" }
        ]
        var specific = ({
            "musicplayer": [
                { button: "X", action: "Play or pause the selected/current track" },
                { button: "SQUARE", action: "Stop playback" },
                { button: "TRIANGLE", action: "Toggle shuffle" },
                { button: "L1 / R1", action: "Change library sections" }
            ],
            "mediaoptimizer": [
                { button: "TRIANGLE", action: "Open the media library" },
                { button: "SQUARE", action: "Confirm the optimizer modal" },
                { button: "X", action: "Select, arm or confirm" },
                { button: "O", action: "Close the topmost modal" }
            ],
            "storage": [
                { button: "X", action: "Open the selected device or action" },
                { button: "SQUARE", action: "Secondary storage action" },
                { button: "TRIANGLE", action: "Device details or context" },
                { button: "O", action: "Back without writing" }
            ],
            "security": [
                { button: "L1 / R1", action: "Change Security tabs" },
                { button: "X", action: "Open or select" },
                { button: "SQUARE", action: "Apply an armed action" },
                { button: "O", action: "Cancel or return" }
            ],
            "settings": [
                { button: "L1 / R1", action: "Change Settings tabs" },
                { button: "X", action: "Open or change a setting" },
                { button: "SQUARE", action: "Apply pending settings" },
                { button: "O", action: "Back or discard the active modal" }
            ],
            "filemanager": [
                { button: "X", action: "Arm/open a file" },
                { button: "TRIANGLE", action: "Arm/open a folder or context" },
                { button: "SQUARE", action: "Paste into the destination" },
                { button: "O", action: "Back or exit" }
            ],
            "gallery": [
                { button: "X", action: "Open or select media" },
                { button: "TRIANGLE", action: "Cycle view/context" },
                { button: "SQUARE", action: "Secondary media action" },
                { button: "RIGHT STICK", action: "Pan while zoomed" }
            ],
            "terminal": [
                { button: "X", action: "Select or type" },
                { button: "TRIANGLE", action: "Quick commands" },
                { button: "OPTIONS", action: "Terminal options" },
                { button: "O", action: "Exit options / leave running" }
            ],
            "browser": [
                { button: "X", action: "Activate links and controls" },
                { button: "TRIANGLE", action: "Browser context action" },
                { button: "L1 / R1", action: "Change tabs or page section" },
                { button: "O", action: "Back or close" }
            ],
            "docker": [
                { button: "X", action: "Arm start/stop" },
                { button: "X + TRIANGLE", action: "Edit the selected container" },
                { button: "TRIANGLE", action: "Create a container" },
                { button: "O", action: "Exit" }
            ],
            "qbittorrent": [
                { button: "X", action: "Open or pause/resume a torrent" },
                { button: "TRIANGLE", action: "Torrent details/context" },
                { button: "SQUARE", action: "Secondary torrent action" },
                { button: "O", action: "Back or exit" }
            ],
            "games": [
                { button: "X", action: "Launch the selected game" },
                { button: "TRIANGLE", action: "Game details" },
                { button: "SQUARE", action: "Reorder the library" },
                { button: "HOLD OPTIONS", action: "Exit an active game session" }
            ],
            "logs": [
                { button: "X", action: "Open live logs" },
                { button: "TRIANGLE", action: "Open recent logs" },
                { button: "R3", action: "Filters" },
                { button: "SQUARE", action: "Toggle appearance" }
            ],
            "texteditor": [
                { button: "X", action: "Edit or activate" },
                { button: "TRIANGLE", action: "Editor context actions" },
                { button: "SQUARE", action: "Save/apply where shown" },
                { button: "O", action: "Back with unsaved-change protection" }
            ],
            "appstore": [
                { button: "X", action: "Open or install" },
                { button: "TRIANGLE", action: "App details" },
                { button: "L1 / R1", action: "Change store sections" },
                { button: "O", action: "Back or exit" }
            ]
        })
        return (specific[id] || [
            { button: "X", action: "Primary action" },
            { button: "TRIANGLE", action: "Context action" },
            { button: "SQUARE", action: "Secondary action" },
            { button: "O", action: "Back or close" }
        ]).concat(common)
    }

    function openAutomatic(data, count) {
        appData = data || ({})
        appId = String(appData.id || appData.appId || "")
        appName = String(appData.name || appData.title || appId || "Application")
        description = String(appData.description || "Controller-first NeutronOS application.")
        introductionNumber = Math.max(1, Math.min(3, Number(count) || 1))
        automaticIntroduction = true
        selectedControl = 0
        visible = true
        forceActiveFocus()
    }

    function openManual(data) {
        appData = data || ({})
        appId = String(appData.id || appData.appId || "")
        appName = String(appData.name || appData.title || appId || "Application")
        description = String(appData.description || "Controller-first NeutronOS application.")
        introductionNumber = 0
        automaticIntroduction = false
        selectedControl = 0
        visible = true
        forceActiveFocus()
    }

    function close() {
        visible = false
        automaticIntroduction = false
        closed()
    }

    function normalize(value) {
        var action = String(value || "").toLowerCase()
        if (action === "x" || action === "cross" || action === "primary") return "primary"
        if (action === "o" || action === "circle" || action === "cancel") return "cancel"
        if (action === "up" || action === "dpad_up") return "up"
        if (action === "down" || action === "dpad_down") return "down"
        if (action === "l1") return "l1"
        if (action === "r1") return "r1"
        return action
    }

    function handleControllerPressed(value) {
        if (!visible)
            return false
        var action = normalize(value)
        if (action === "cancel" || action === "primary") {
            close()
            return true
        }
        if (action === "up" || action === "l1") {
            selectedControl = Math.max(0, selectedControl - 1)
            controlsList.positionViewAtIndex(selectedControl, ListView.Contain)
            return true
        }
        if (action === "down" || action === "r1") {
            selectedControl = Math.min(controls.length - 1, selectedControl + 1)
            controlsList.positionViewAtIndex(selectedControl, ListView.Contain)
            return true
        }
        return true
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Up) action = "up"
        else if (event.key === Qt.Key_Down) action = "down"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) action = "cancel"
        if (action.length > 0) {
            event.accepted = true
            handleControllerPressed(action)
        }
    }

    Rectangle { anchors.fill: parent; color: "#E8050811" }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1320)
        height: Math.min(parent.height - 100, 860)
        radius: 36
        color: "#071321"
        border.width: 2
        border.color: "#56D9FF"
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 116
            color: "#0A2136"

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 38
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    text: root.appName.toUpperCase() + " HELP"
                    color: "white"
                    font.pixelSize: 31
                    font.bold: true
                }
                Text {
                    text: root.automaticIntroduction
                          ? "FIRST-USE GUIDE  " + root.introductionNumber + " OF 3"
                          : "CONTROLLER GUIDE"
                    color: root.automaticIntroduction ? "#79FFAE" : "#7DF9FF"
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1.8
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 142
            anchors.bottom: footer.top
            anchors.leftMargin: 38
            anchors.rightMargin: 38
            spacing: 22

            Text {
                width: parent.width
                text: root.description
                color: "#CFE9FF"
                font.pixelSize: 20
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Text {
                text: "CONTROLS"
                color: "#7DF9FF"
                font.pixelSize: 16
                font.bold: true
                font.letterSpacing: 2
            }

            ListView {
                id: controlsList
                width: parent.width
                height: parent.height - 130
                clip: true
                spacing: 10
                model: root.controls
                currentIndex: root.selectedControl

                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width: controlsList.width
                    height: 66
                    radius: 18
                    color: index === root.selectedControl ? "#123D5B" : "#0B2135"
                    border.width: index === root.selectedControl ? 2 : 1
                    border.color: index === root.selectedControl ? "#66E4FF" : "#24455F"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 24
                        Rectangle {
                            width: 215
                            height: 34
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 12
                            color: "#07111D"
                            border.width: 1
                            border.color: "#4CBEE8"
                            Text {
                                anchors.centerIn: parent
                                text: String(modelData.button || "")
                                color: "#FFFFFF"
                                font.pixelSize: 15
                                font.bold: true
                            }
                        }
                        Text {
                            width: parent.width - 255
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(modelData.action || "")
                            color: "#D7EEFF"
                            font.pixelSize: 18
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 76
            color: "#081A2B"
            border.width: 1
            border.color: "#27455F"
            Text {
                anchors.centerIn: parent
                text: "X / O  CLOSE     •     UP / DOWN  REVIEW     •     SHARE / QUICK  OPEN HELP LATER"
                color: "#A9DFFF"
                font.pixelSize: 16
                font.bold: true
            }
        }
    }
}
