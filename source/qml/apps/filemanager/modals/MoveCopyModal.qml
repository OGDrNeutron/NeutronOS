import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            MOVE / COPY MODAL
        ============================================================

        Destination picker for Move and Copy.

        Controller:
        - Type destination path with keyboard for now.
        - LEFT / RIGHT = choose CANCEL or CONFIRM.
        - X / ENTER = activate selected option.
        - O / ESC = cancel.
        - No mouse assumptions.

        Backend:
        - Emits moveConfirmed(sourcePath, destinationPath)
        - Emits copyConfirmed(sourcePath, destinationPath)
    */

    anchors.fill: parent

    visible: false
    focus: visible
    z: 925

    property string mode: "move"
    property string fileName: "Selected Item"
    property string sourcePath: ""
    property string destinationPath: "/home/echo"
    property string currentPath: "/home/echo"

    property int selectedAction: 1

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

    signal moveConfirmed(string sourcePath, string destinationPath)
    signal copyConfirmed(string sourcePath, string destinationPath)
    signal closed()

    function openMove(name, path, startPath) {
        openModal("move", name, path, startPath)
    }

    function openCopy(name, path, startPath) {
        openModal("copy", name, path, startPath)
    }

    function openModal(actionMode, name, path, startPath) {
        mode = String(actionMode || "move").toLowerCase()
        fileName = String(name || "Selected Item")
        sourcePath = String(path || "")
        currentPath = String(startPath || "/home/echo")
        destinationPath = currentPath

        selectedAction = 1
        visible = true

        forceActiveFocus()
        destinationInput.forceActiveFocus()
        destinationInput.selectAll()
    }

    function close() {
        visible = false
        closed()
    }

    function modeTitle() {
        return mode === "copy" ? "COPY ITEM" : "MOVE ITEM"
    }

    function modeVerb() {
        return mode === "copy" ? "COPY" : "MOVE"
    }

    function cleanDestination() {
        return String(destinationInput.text || destinationPath || "").trim()
    }

    function canConfirm() {
        var destination = cleanDestination()

        return sourcePath.length > 0 &&
               destination.length > 0 &&
               destination !== sourcePath
    }

    function moveLeft() {
        selectedAction = Math.max(0, selectedAction - 1)
    }

    function moveRight() {
        selectedAction = Math.min(1, selectedAction + 1)
    }

    function activateSelected() {
        if (selectedAction === 0) {
            close()
            return
        }

        commit()
    }

    function commit() {
        if (!canConfirm())
            return

        destinationPath = cleanDestination()

        if (mode === "copy")
            copyConfirmed(sourcePath, destinationPath)
        else
            moveConfirmed(sourcePath, destinationPath)

        close()
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
            duration: 1400
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1400
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

        width: 780
        height: 500
        radius: 38

        color: "#061A2EF6"

        border.width: 2
        border.color: root.mode === "copy" ? root.greenAccent : root.focusBlue

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

            width: 660
            height: 320
            radius: 160

            color: root.mode === "copy" ? root.greenAccent : root.focusBlue
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

            color: root.mode === "copy" ? root.greenAccent : root.focusBlue
            opacity: 0.28 + root.glowPulse * 0.16
        }

        /*
            ========================================================
                                HEADER
            ========================================================
        */

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 38
            anchors.rightMargin: 38
            anchors.topMargin: 30

            spacing: 10

            Text {
                width: parent.width

                text: root.modeTitle()

                color: root.mode === "copy" ? root.greenAccent : root.focusBlue

                font.pixelSize: 16
                font.bold: true
                font.letterSpacing: 2.4

                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width

                text: root.fileName

                color: root.textPrimary

                font.pixelSize: 32
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }

            Text {
                width: parent.width

                text: root.sourcePath

                color: root.textMuted

                font.pixelSize: 12
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }

        /*
            ========================================================
                            DESTINATION FIELD
            ========================================================
        */

        Rectangle {
            id: inputShell

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 62
            anchors.rightMargin: 62
            anchors.topMargin: 176

            height: 76
            radius: 26

            color: "#071426E8"

            border.width: 2
            border.color: destinationInput.activeFocus
                          ? root.mode === "copy" ? root.greenAccent : root.focusBlue
                          : "#2A8DCC"

            clip: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1

                radius: parent.radius - 1
                color: "#FFFFFF"
                opacity: 0.040
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter

                text: root.mode === "copy" ? "⧉" : "⇢"

                color: root.mode === "copy" ? root.greenAccent : root.focusBlue

                font.pixelSize: 26
                font.bold: true
            }

            TextInput {
                id: destinationInput

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                anchors.leftMargin: 64
                anchors.rightMargin: 24

                height: parent.height - 12

                text: root.destinationPath

                color: root.textPrimary
                selectionColor: root.mode === "copy" ? root.greenAccent : root.focusBlue
                selectedTextColor: "#02101C"

                font.pixelSize: 22
                font.bold: true

                verticalAlignment: TextInput.AlignVCenter

                clip: true
                focus: false
                activeFocusOnTab: false

                onTextEdited: {
                    root.destinationPath = text
                }

                onAccepted: {
                    root.commit()
                }

                Keys.onEscapePressed: {
                    root.close()
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                anchors.leftMargin: 64
                anchors.rightMargin: 24
                anchors.bottomMargin: 8

                height: 2
                radius: 1

                color: root.mode === "copy" ? root.greenAccent : root.focusBlue
                opacity: destinationInput.activeFocus ? 0.34 + root.glowPulse * 0.26 : 0.12
            }
        }

        /*
            ========================================================
                            QUICK DESTINATIONS
            ========================================================
        */

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: inputShell.bottom
            anchors.topMargin: 20

            spacing: 12

            QuickDestination {
                label: "HOME"
                path: "/home/echo"
            }

            QuickDestination {
                label: "MEDIA"
                path: "/mnt/NeutronMedia"
            }

            QuickDestination {
                label: "CURRENT"
                path: root.currentPath
            }
        }

        /*
            ========================================================
                                STATUS
            ========================================================
        */

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: actionRow.top
            anchors.bottomMargin: 18

            anchors.leftMargin: 64
            anchors.rightMargin: 64

            text: root.cleanDestination().length <= 0
                  ? "Destination path cannot be empty."
                  : root.cleanDestination() === root.sourcePath
                    ? "Destination cannot be the same as the source."
                    : "Ready to " + root.modeVerb().toLowerCase() + "."

            color: root.canConfirm() ? root.greenAccent : root.warningYellow

            font.pixelSize: 12
            font.bold: true
            font.letterSpacing: 0.7

            horizontalAlignment: Text.AlignHCenter
        }

        /*
            ========================================================
                                ACTIONS
            ========================================================
        */

        Row {
            id: actionRow

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 52

            spacing: 18

            ModalActionButton {
                label: "CANCEL"
                selected: root.selectedAction === 0
                enabledButton: true
                accent: root.focusBlue
            }

            ModalActionButton {
                label: root.modeVerb()
                selected: root.selectedAction === 1
                enabledButton: root.canConfirm()
                accent: root.mode === "copy" ? root.greenAccent : root.focusBlue
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22

            text: "X " + root.modeVerb() + "  •  O CANCEL"

            color: root.textMuted

            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1.2

            opacity: 0.78
        }
    }

    /*
        ============================================================
                            KEYS
        ============================================================
    */

    Keys.onLeftPressed: moveLeft()
    Keys.onRightPressed: moveRight()

    Keys.onReturnPressed: {
        if (destinationInput.activeFocus && root.canConfirm()) {
            root.commit()
            return
        }

        root.activateSelected()
    }

    Keys.onEnterPressed: {
        if (destinationInput.activeFocus && root.canConfirm()) {
            root.commit()
            return
        }

        root.activateSelected()
    }

    Keys.onSpacePressed: activateSelected()
    Keys.onEscapePressed: close()
    Keys.onBackPressed: close()

    /*
        ============================================================
                            COMPONENTS
        ============================================================
    */

    component QuickDestination: Rectangle {
        property string label: ""
        property string path: ""

        width: 150
        height: 38
        radius: 19

        color: "#071426DD"

        border.width: 1
        border.color: "#2A8DCC"

        opacity: 0.88

        Text {
            anchors.centerIn: parent

            text: label

            color: root.textSecondary

            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.1
        }
    }

    component ModalActionButton: Rectangle {
        property string label: ""
        property bool selected: false
        property bool enabledButton: true
        property color accent: "#7DF9FF"

        width: 220
        height: 68
        radius: 22

        color: !enabledButton
               ? "#06101AAA"
               : selected
                 ? "#104D86EE"
                 : "#071426DD"

        border.width: selected ? 3 : 1
        border.color: !enabledButton
                      ? "#264053"
                      : selected
                        ? accent
                        : "#2A8DCC"

        opacity: enabledButton ? 1.0 : 0.42

        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: selected ? 0.050 : 0.026
        }

        Text {
            anchors.centerIn: parent

            text: label

            color: !enabledButton ? root.textMuted : root.textPrimary

            font.pixelSize: 19
            font.bold: true
            font.letterSpacing: 1.4
        }

        Rectangle {
            visible: selected && enabledButton

            anchors.fill: parent
            anchors.margins: -5

            radius: parent.radius + 5

            color: "transparent"

            border.width: 1
            border.color: accent

            opacity: 0.36 + root.glowPulse * 0.28
        }
    }
}
