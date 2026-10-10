import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            RENAME MODAL
        ============================================================

        Rename armed/selected file.

        Controller:
        - Type new name with keyboard for now.
        - Enter / X-style fallback = rename.
        - O / ESC = cancel.
        - No mouse assumptions.

        Backend-ready:
        - Emits renameConfirmed(newName).
        - Main.qml sends the armed file path + new name to backend.
    */

    anchors.fill: parent

    visible: false
    focus: visible
    z: 930

    property string originalName: "Selected Item"
    property string newName: ""
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

    signal renameConfirmed(string newName)
    signal closed()

    function openModal(name) {
        originalName = String(name || "Selected Item")
        newName = originalName
        selectedAction = 1
        visible = true
        forceActiveFocus()
        nameInput.forceActiveFocus()
        nameInput.selectAll()
    }

    function close() {
        visible = false
        closed()
    }

    function moveLeft() {
        selectedAction = Math.max(0, selectedAction - 1)
    }

    function moveRight() {
        selectedAction = Math.min(1, selectedAction + 1)
    }

    function cleanName() {
        return String(nameInput.text || newName || "").trim()
    }

    function canRename() {
        var name = cleanName()

        return name.length > 0 &&
               name !== originalName &&
               name.indexOf("/") < 0 &&
               name.indexOf("\\") < 0
    }

    function activateSelected() {
        if (selectedAction === 0) {
            close()
            return
        }

        commitRename()
    }

    function commitRename() {
        if (!canRename())
            return

        newName = cleanName()
        renameConfirmed(newName)
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

        width: 720
        height: 440
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

            y: -170

            width: 600
            height: 300
            radius: 150

            color: root.focusBlue
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
            width: 150
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

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 34
            anchors.rightMargin: 34
            anchors.topMargin: 30

            spacing: 10

            Text {
                width: parent.width

                text: "RENAME ITEM"

                color: root.focusBlue

                font.pixelSize: 16
                font.bold: true
                font.letterSpacing: 2.4

                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width

                text: "Choose a new name"

                color: root.textPrimary

                font.pixelSize: 34
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width

                text: root.originalName

                color: root.textMuted

                font.pixelSize: 13
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
            }
        }

        /*
            ========================================================
                                INPUT
            ========================================================
        */

        Rectangle {
            id: inputShell

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 62
            anchors.rightMargin: 62
            anchors.topMargin: 180

            height: 74
            radius: 26

            color: "#071426E8"

            border.width: 2
            border.color: nameInput.activeFocus ? root.focusBlue : "#2A8DCC"

            clip: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1

                radius: parent.radius - 1
                color: "#FFFFFF"
                opacity: 0.040
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top

                height: 1

                color: "#FFFFFF"
                opacity: 0.18
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter

                text: "✎"

                color: root.focusBlue

                font.pixelSize: 24
                font.bold: true
            }

            TextInput {
                id: nameInput

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                anchors.leftMargin: 62
                anchors.rightMargin: 24

                height: parent.height - 12

                text: root.newName

                color: root.textPrimary
                selectionColor: root.focusBlue
                selectedTextColor: "#02101C"

                font.pixelSize: 24
                font.bold: true

                verticalAlignment: TextInput.AlignVCenter

                clip: true
                focus: false
                activeFocusOnTab: false

                onTextEdited: {
                    root.newName = text
                }

                onAccepted: {
                    root.commitRename()
                }

                Keys.onEscapePressed: {
                    root.close()
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                anchors.leftMargin: 62
                anchors.rightMargin: 24
                anchors.bottomMargin: 8

                height: 2
                radius: 1

                color: root.focusBlue
                opacity: nameInput.activeFocus ? 0.34 + root.glowPulse * 0.26 : 0.12
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
            anchors.top: inputShell.bottom
            anchors.topMargin: 12

            anchors.leftMargin: 64
            anchors.rightMargin: 64

            text: root.cleanName().length <= 0
                  ? "Name cannot be empty."
                  : root.cleanName().indexOf("/") >= 0 || root.cleanName().indexOf("\\") >= 0
                    ? "Names cannot contain slashes."
                    : root.cleanName() === root.originalName
                      ? "Enter a new name different from the original."
                      : "Ready to rename."

            color: !root.canRename()
                   ? root.warningYellow
                   : root.greenAccent

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
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 46

            spacing: 18

            ModalActionButton {
                label: "CANCEL"
                selected: root.selectedAction === 0
                danger: false
                enabledButton: true
            }

            ModalActionButton {
                label: "RENAME"
                selected: root.selectedAction === 1
                danger: false
                enabledButton: root.canRename()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20

            text: "X RENAME  •  O CANCEL"

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
        if (nameInput.activeFocus && root.canRename()) {
            root.commitRename()
            return
        }

        root.activateSelected()
    }

    Keys.onEnterPressed: {
        if (nameInput.activeFocus && root.canRename()) {
            root.commitRename()
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

    component ModalActionButton: Rectangle {
        property string label: ""
        property bool selected: false
        property bool danger: false
        property bool enabledButton: true

        width: 220
        height: 68
        radius: 22

        color: !enabledButton
               ? "#06101AAA"
               : selected
                 ? danger ? "#3A1116" : "#104D86EE"
                 : "#071426DD"

        border.width: selected ? 3 : 1
        border.color: !enabledButton
                      ? "#264053"
                      : danger
                        ? root.dangerRed
                        : selected
                          ? root.focusBlue
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

            color: !enabledButton
                   ? root.textMuted
                   : danger && selected
                     ? "#FFD1D1"
                     : root.textPrimary

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
            border.color: danger ? root.dangerRed : root.focusBlue

            opacity: 0.36 + root.glowPulse * 0.28
        }
    }
}