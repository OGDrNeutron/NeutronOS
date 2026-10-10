import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE ACTION MODAL
        ============================================================

        Opens after a file has been armed/selected.

        Actions:
        - OPEN
        - MOVE
        - COPY
        - RENAME
        - DUPLICATE
        - DETAILS
        - DELETE

        Controller:
        - LEFT / RIGHT = move between actions
        - UP / DOWN = move by row
        - X / ENTER = activate selected action
        - O / ESC = close
        - No mouse assumptions

        Backend-ready:
        - Move / Copy / Duplicate signals are exposed now.
        - Main/backend can wire them directly when the C++ backend lands.
    */

    anchors.fill: parent

    visible: false
    focus: visible
    z: 900

    property var fileData: null
    property int selectedAction: 0

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color greenAccent: "#22FF88"
    property color dangerRed: "#FF3040"
    property color warningYellow: "#FFD166"

    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real glowPulse: 0.35
    property real sweep: -1.0

    property int columns: 4

    property var actions: [
        {
            "id": "open",
            "text": "OPEN",
            "icon": "↗",
            "subtitle": "Launch item",
            "danger": false
        },
        {
            "id": "move",
            "text": "MOVE",
            "icon": "⇢",
            "subtitle": "Relocate",
            "danger": false
        },
        {
            "id": "copy",
            "text": "COPY",
            "icon": "⧉",
            "subtitle": "Copy to",
            "danger": false
        },
        {
            "id": "rename",
            "text": "RENAME",
            "icon": "✎",
            "subtitle": "New name",
            "danger": false
        },
        {
            "id": "duplicate",
            "text": "DUPLICATE",
            "icon": "⧉",
            "subtitle": "Same folder",
            "danger": false
        },
        {
            "id": "details",
            "text": "DETAILS",
            "icon": "i",
            "subtitle": "Metadata",
            "danger": false
        },
        {
            "id": "delete",
            "text": "DELETE",
            "icon": "−",
            "subtitle": "Trash item",
            "danger": true
        }
    ]

    signal openRequested()
    signal moveRequested()
    signal copyRequested()
    signal renameRequested()
    signal duplicateRequested()
    signal detailsRequested()
    signal deleteRequested()
    signal closed()

    function openModal(data) {
        fileData = data
        selectedAction = 0
        visible = true
        forceActiveFocus()
    }

    function close() {
        visible = false
        closed()
    }

    function actionCount() {
        return actions.length
    }

    function normalizeIndex(index) {
        var count = actionCount()

        if (count <= 0)
            return 0

        var value = index % count

        if (value < 0)
            value += count

        return value
    }

    function moveLeft() {
        selectedAction = normalizeIndex(selectedAction - 1)
    }

    function moveRight() {
        selectedAction = normalizeIndex(selectedAction + 1)
    }

    function moveUp() {
        selectedAction = normalizeIndex(selectedAction - columns)
    }

    function moveDown() {
        selectedAction = normalizeIndex(selectedAction + columns)
    }

    function activateSelected() {
        var action = actions[normalizeIndex(selectedAction)]

        if (!action)
            return

        if (action.id === "open") {
            close()
            openRequested()
            return
        }

        if (action.id === "move") {
            close()
            moveRequested()
            return
        }

        if (action.id === "copy") {
            close()
            copyRequested()
            return
        }

        if (action.id === "rename") {
            close()
            renameRequested()
            return
        }

        if (action.id === "duplicate") {
            close()
            duplicateRequested()
            return
        }

        if (action.id === "details") {
            close()
            detailsRequested()
            return
        }

        if (action.id === "delete") {
            close()
            deleteRequested()
            return
        }
    }

    function fileName() {
        if (!fileData)
            return "Selected Item"

        return String(fileData.name || fileData.fileName || "Selected Item")
    }

    function filePath() {
        if (!fileData)
            return ""

        return String(fileData.path || fileData.filePath || "")
    }

    function fileKind() {
        if (!fileData)
            return "file"

        return String(fileData.kind || fileData.type || "file").toLowerCase()
    }

    function isDirectory() {
        if (!fileData)
            return false

        return fileData.isDirectory === true ||
               fileKind() === "folder"
    }

    function iconTextForKind() {
        var k = fileKind()

        if (isDirectory() || k === "folder")
            return "▰"

        if (k === "video")
            return "▶"

        if (k === "image")
            return "◫"

        if (k === "audio")
            return "♫"

        if (k === "archive")
            return "ZIP"

        if (k === "disk")
            return "ISO"

        if (k === "code")
            return "{ }"

        if (k === "document")
            return "≡"

        return "•"
    }

    function kindLabel() {
        if (isDirectory())
            return "FOLDER"

        var k = fileKind()

        if (k.length <= 0)
            return "FILE"

        return k.toUpperCase()
    }

    function accentForKind() {
        var k = fileKind()

        if (isDirectory() || k === "folder")
            return focusBlue

        if (k === "video")
            return purpleGlow

        if (k === "image")
            return "#38BDF8"

        if (k === "audio")
            return greenAccent

        if (k === "archive")
            return warningYellow

        if (k === "disk")
            return "#C084FC"

        if (k === "code")
            return "#4DA6FF"

        if (k === "document")
            return "#A7EEFF"

        return textSecondary
    }

    /*
        ============================================================
                            ANIMATION
        ============================================================
    */

    SequentialAnimation on glowPulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 1350
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1350
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 3100
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 3100
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            OVERLAY
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        color: "#000000"
        opacity: 0.62
    }

    Rectangle {
        anchors.fill: parent

        color: "#061A2E"
        opacity: 0.18
    }

    /*
        ============================================================
                            MODAL SHELL
        ============================================================
    */

    Rectangle {
        id: modalShell

        anchors.centerIn: parent

        width: 860
        height: 510
        radius: 38

        color: "#061A2EF6"

        border.width: 2
        border.color: root.focusBlue

        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.044
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 2

            color: "#FFFFFF"
            opacity: 0.24
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -180

            width: 700
            height: 320
            radius: 160

            color: root.accentForKind()
            opacity: 0.030 + root.glowPulse * 0.030
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -120
            anchors.bottomMargin: -140

            width: 320
            height: 320
            radius: 160

            color: root.purpleGlow
            opacity: 0.024
        }

        Rectangle {
            width: 170
            height: 3
            radius: 2

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.bottom: parent.bottom

            color: root.focusBlue
            opacity: 0.28 + root.glowPulse * 0.16
        }

        /*
            ========================================================
                                HEADER
            ========================================================
        */

        Row {
            id: headerRow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 34
            anchors.rightMargin: 34
            anchors.topMargin: 28

            height: 86

            spacing: 18

            Rectangle {
                width: 76
                height: 76
                radius: 24

                anchors.verticalCenter: parent.verticalCenter

                color: "#071426E8"

                border.width: 2
                border.color: root.accentForKind()

                clip: true

                Rectangle {
                    anchors.centerIn: parent

                    width: 54
                    height: 54
                    radius: 20

                    color: root.accentForKind()
                    opacity: 0.055 + root.glowPulse * 0.050
                }

                Text {
                    anchors.centerIn: parent

                    text: root.iconTextForKind()

                    color: "#FFFFFF"

                    font.pixelSize: text.length > 3 ? 22 : 34
                    font.bold: true

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    style: Text.Raised
                    styleColor: "#66000000"
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 100
                spacing: 6

                Text {
                    width: parent.width

                    text: "FILE ACTIONS"

                    color: root.focusBlue

                    font.pixelSize: 16
                    font.bold: true
                    font.letterSpacing: 2.2
                }

                Text {
                    width: parent.width

                    text: root.fileName()

                    color: root.textPrimary

                    font.pixelSize: 30
                    font.bold: true

                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                }

                Row {
                    spacing: 10

                    Rectangle {
                        width: kindText.implicitWidth + 24
                        height: 24
                        radius: 12

                        color: "#071426DD"

                        border.width: 1
                        border.color: root.accentForKind()

                        Text {
                            id: kindText

                            anchors.centerIn: parent

                            text: root.kindLabel()

                            color: root.accentForKind()

                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 1.1
                        }
                    }

                    Text {
                        width: headerRow.width - 220

                        text: root.filePath()

                        color: root.textMuted

                        font.pixelSize: 12
                        font.bold: true

                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        /*
            ========================================================
                            ACTION BUTTON GRID
            ========================================================
        */

        Grid {
            id: actionGrid

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom

            anchors.leftMargin: 34
            anchors.rightMargin: 34
            anchors.topMargin: 26

            columns: root.columns
            rows: 2

            rowSpacing: 16
            columnSpacing: 14

            Repeater {
                model: root.actions.length

                Rectangle {
                    id: actionButton

                    width: (actionGrid.width - actionGrid.columnSpacing * (root.columns - 1)) / root.columns
                    height: 116
                    radius: 26

                    property var actionData: root.actions[index]
                    property bool actionFocused: index === root.selectedAction
                    property bool actionDanger: actionData.danger === true

                    color: actionDanger && actionFocused
                           ? "#3A1116"
                           : actionFocused
                             ? "#104D86EE"
                             : "#071426D8"

                    border.width: actionFocused ? 3 : 1
                    border.color: actionDanger
                                  ? root.dangerRed
                                  : actionFocused
                                    ? root.focusBlue
                                    : "#2A8DCC"

                    clip: true

                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 140
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1

                        radius: parent.radius - 1
                        color: "#FFFFFF"
                        opacity: actionFocused ? 0.056 : 0.030
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top

                        height: 1

                        color: "#FFFFFF"
                        opacity: actionFocused ? 0.22 : 0.12
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top

                        y: -52

                        width: parent.width * 0.78
                        height: 96
                        radius: 48

                        color: actionDanger ? root.dangerRed : root.focusBlue
                        opacity: actionFocused ? 0.070 + root.glowPulse * 0.070 : 0.018
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom

                        visible: actionFocused

                        width: actionDanger ? 6 : 4
                        radius: width / 2

                        color: actionDanger ? root.dangerRed : root.focusBlue
                        opacity: 0.82
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter

                            text: actionData.icon

                            color: actionDanger && actionFocused
                                   ? "#FFD1D1"
                                   : actionDanger
                                     ? "#FF9A9A"
                                     : actionFocused
                                       ? "#FFFFFF"
                                       : root.textSecondary

                            font.pixelSize: actionData.text === "DUPLICATE" ? 26 : 30
                            font.bold: true

                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            width: parent.width

                            text: actionData.text

                            color: actionDanger && actionFocused
                                   ? "#FFD1D1"
                                   : actionFocused
                                     ? "#FFFFFF"
                                     : root.textPrimary

                            font.pixelSize: actionData.text.length > 8 ? 14 : 16
                            font.bold: true
                            font.letterSpacing: 1.1

                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width

                            text: actionData.subtitle

                            color: actionDanger ? "#FFB8B8" : root.textMuted

                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 0.6

                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight

                            opacity: 0.82
                        }
                    }

                    Rectangle {
                        visible: actionFocused

                        anchors.fill: parent
                        anchors.margins: -5

                        radius: parent.radius + 5

                        color: "transparent"

                        border.width: 1
                        border.color: actionDanger ? root.dangerRed : root.focusBlue

                        opacity: 0.36 + root.glowPulse * 0.28
                    }
                }
            }
        }

        /*
            ========================================================
                                FOOTER
            ========================================================
        */

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            anchors.leftMargin: 34
            anchors.rightMargin: 34
            anchors.bottomMargin: 22

            height: 34

            Text {
                anchors.verticalCenter: parent.verticalCenter

                width: parent.width / 3

                text: "X SELECT ACTION"

                color: root.textSecondary

                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.4
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                width: parent.width / 3

                text: "O CANCEL"

                color: root.textMuted

                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.4

                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                width: parent.width / 3

                text: "MOVE  COPY  DUPLICATE READY"

                color: root.textMuted

                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.1

                horizontalAlignment: Text.AlignRight
            }
        }
    }

    /*
        ============================================================
                            KEYS
        ============================================================
    */

    Keys.onLeftPressed: moveLeft()
    Keys.onRightPressed: moveRight()
    Keys.onUpPressed: moveUp()
    Keys.onDownPressed: moveDown()

    Keys.onReturnPressed: activateSelected()
    Keys.onEnterPressed: activateSelected()
    Keys.onSpacePressed: activateSelected()

    Keys.onEscapePressed: close()
    Keys.onBackPressed: close()
}