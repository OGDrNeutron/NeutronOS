import QtQuick 2.15

FocusScope {
    id: root
    anchors.fill: parent
    visible: false
    enabled: visible
    z: 10000

    property string appName: "Application"

    // Compatibility retained for app-side safety checks. There is no selectable
    // action state anymore; the controller button itself chooses the action.
    property int selectedIndex: 0
    property int displayIndex: 0
    property Item returnFocusItem: null
    property string descriptionText: ""
    property string exitLabel: "Exit"
    property string leaveRunningLabel: "Leave Running"
    property string resumeLabel: "Resume"

    readonly property color panelColor: "#071426"
    readonly property color raisedColor: "#0B1A30"
    readonly property color textMain: "#F4FBFF"
    readonly property color textMuted: "#8AA6C8"
    readonly property color green: "#22FF88"
    readonly property color purple: "#B75CFF"
    readonly property color red: "#FF3040"

    signal exitRequested()
    signal leaveRunningRequested()
    signal dismissed()

    function openModal(focusItem) {
        returnFocusItem = focusItem || null
        selectedIndex = 0
        displayIndex = 0
        visible = true
        forceActiveFocus()
    }

    function closeModal() {
        visible = false
        dismissed()
        if (returnFocusItem && returnFocusItem.forceActiveFocus)
            returnFocusItem.forceActiveFocus()
    }

    function activate() { requestExit() }
    function move(delta) { return }

    function requestExit() {
        selectedIndex = 0
        visible = false
        exitRequested()
    }

    function requestBackground() {
        selectedIndex = 1
        visible = false
        leaveRunningRequested()
    }

    function requestResume() {
        selectedIndex = 2
        closeModal()
    }

    function handleController(action) {
        if (!visible) return false
        var a = String(action || "").toLowerCase().replace(/-/g, "_")
        if (a === "primary" || a === "x" || a === "cross" || a === "ps_cross" || a === "enter" || a === "accept")
            requestExit()
        else if (a === "secondary" || a === "square" || a === "ps_square" || a === "xbox_x")
            requestBackground()
        else if (a === "cancel" || a === "circle" || a === "o" || a === "ps_circle" || a === "back" || a === "escape")
            requestResume()
        return true
    }

    Rectangle {
        anchors.fill: parent
        color: "#D9000000"
    }

    Item {
        id: orbitFrame
        width: Math.min(parent.width - 160, 920)
        height: 320
        anchors.centerIn: parent

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, 912)
            height: 312
            radius: 24
            color: "transparent"
            border.width: 2
            border.color: root.red
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: Math.min(parent.width - 20, 900)
            height: 300
            radius: 18
            color: root.panelColor
            border.width: 0

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 24

                Text {
                    width: parent.width
                    text: root.appName
                    color: root.textMain
                    font.pixelSize: 30
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14

                    Rectangle {
                        width: 245; height: 112; radius: 16
                        color: root.raisedColor
                        border.width: 1
                        border.color: Qt.rgba(root.green.r, root.green.g, root.green.b, 0.75)
                        Column {
                            anchors.centerIn: parent; spacing: 6
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "○"; color: root.green; font.pixelSize: 30; font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.resumeLabel; color: root.textMain; font.pixelSize: 17; font.bold: true }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.requestResume() }
                    }

                    Rectangle {
                        width: 245; height: 112; radius: 16
                        color: root.raisedColor
                        border.width: 1
                        border.color: Qt.rgba(root.purple.r, root.purple.g, root.purple.b, 0.75)
                        Column {
                            anchors.centerIn: parent; spacing: 6
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "□"; color: root.purple; font.pixelSize: 30; font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.leaveRunningLabel; color: root.textMain; font.pixelSize: 17; font.bold: true }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.requestBackground() }
                    }

                    Rectangle {
                        width: 245; height: 112; radius: 16
                        color: root.raisedColor
                        border.width: 1
                        border.color: Qt.rgba(root.red.r, root.red.g, root.red.b, 0.80)
                        Column {
                            anchors.centerIn: parent; spacing: 6
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "✕"; color: root.red; font.pixelSize: 28; font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.exitLabel; color: root.textMain; font.pixelSize: 17; font.bold: true }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.requestExit() }
                    }
                }

                Text {
                    width: parent.width
                    text: "○  RESUME        □  LEAVE RUNNING        ✕  EXIT"
                    color: root.textMuted
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Item {
            id: orbitDot
            width: 14
            height: 14
            z: 5
            Rectangle { anchors.centerIn: parent; width: 18; height: 18; radius: 9; color: "#44FF3040" }
            Rectangle { anchors.centerIn: parent; width: 9; height: 9; radius: 4.5; color: root.red; border.width: 1; border.color: "#FFFF9AA4" }
        }

        PathAnimation {
            target: orbitDot
            duration: 4300
            loops: Animation.Infinite
            running: root.visible
            path: Path {
                startX: 28; startY: 0
                PathLine { x: orbitFrame.width - 28; y: 0 }
                PathQuad { x: orbitFrame.width; y: 28; controlX: orbitFrame.width; controlY: 0 }
                PathLine { x: orbitFrame.width; y: orbitFrame.height - 28 }
                PathQuad { x: orbitFrame.width - 28; y: orbitFrame.height; controlX: orbitFrame.width; controlY: orbitFrame.height }
                PathLine { x: 28; y: orbitFrame.height }
                PathQuad { x: 0; y: orbitFrame.height - 28; controlX: 0; controlY: orbitFrame.height }
                PathLine { x: 0; y: 28 }
                PathQuad { x: 28; y: 0; controlX: 0; controlY: 0 }
            }
        }
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) action = "cancel"
        if (action.length) {
            event.accepted = true
            root.handleController(action)
        }
    }
}
