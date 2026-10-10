import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                        DELETE CONFIRM MODAL
        ============================================================

        Destructive action confirmation.

        Controller:
        - LEFT / RIGHT = choose CANCEL or DELETE
        - X / ENTER = activate selected option
        - O / ESC = cancel
        - No mouse assumptions

        Safety:
        - Delete defaults to CANCEL.
        - DELETE is red/destructive.
    */

    anchors.fill: parent

    visible: false
    focus: visible
    z: 920

    property string fileName: "Selected Item"
    property string filePath: ""
    property int selectedAction: 0

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color dangerRed: "#FF3040"
    property color warningYellow: "#FFD166"

    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real dangerPulse: 0.35
    property real sweep: -1.0

    signal deleteConfirmed(string path)
    signal closed()

    function openModal(name, path) {
        fileName = String(name || "Selected Item")
        filePath = String(path || "")
        selectedAction = 0
        visible = true
        forceActiveFocus()
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

    function activateSelected() {
        if (selectedAction === 0) {
            close()
            return
        }

        deleteConfirmed(filePath)
        close()
    }

    /*
        ============================================================
                            ANIMATION
        ============================================================
    */

    SequentialAnimation on dangerPulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 820
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 820
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation on sweep {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 2600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 2600
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
        opacity: 0.68
    }

    Rectangle {
        anchors.fill: parent
        color: "#2A0A10"
        opacity: 0.22
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
        height: 430
        radius: 38

        color: "#12070BF6"

        border.width: 3
        border.color: root.dangerRed

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

            height: 3

            color: root.dangerRed
            opacity: 0.62 + root.dangerPulse * 0.24
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -180

            width: 620
            height: 320
            radius: 160

            color: root.dangerRed
            opacity: 0.046 + root.dangerPulse * 0.046
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -110
            anchors.bottomMargin: -130

            width: 300
            height: 300
            radius: 150

            color: root.purpleGlow
            opacity: 0.018
        }

        Rectangle {
            width: 170
            height: 3
            radius: 2

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.bottom: parent.bottom

            color: root.dangerRed
            opacity: 0.38 + root.dangerPulse * 0.24
        }

        /*
            ========================================================
                                CONTENT
            ========================================================
        */

        Column {
            anchors.fill: parent
            anchors.margins: 34

            spacing: 20

            Rectangle {
                width: 82
                height: 82
                radius: 28

                anchors.horizontalCenter: parent.horizontalCenter

                color: "#3A1116"

                border.width: 2
                border.color: root.dangerRed

                Rectangle {
                    anchors.centerIn: parent

                    width: 58
                    height: 58
                    radius: 22

                    color: root.dangerRed
                    opacity: 0.090 + root.dangerPulse * 0.080
                }

                Text {
                    anchors.centerIn: parent

                    text: "!"

                    color: "#FFD1D1"

                    font.pixelSize: 46
                    font.bold: true

                    style: Text.Raised
                    styleColor: "#66000000"
                }
            }

            Text {
                width: parent.width

                text: "DELETE ITEM?"

                color: "#FFD1D1"

                font.pixelSize: 34
                font.bold: true
                font.letterSpacing: 1.2

                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width

                text: root.fileName

                color: root.textPrimary

                font.pixelSize: 24
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }

            Text {
                width: parent.width

                text: root.filePath

                color: root.textMuted

                font.pixelSize: 12
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }

            Rectangle {
                width: parent.width
                height: 48
                radius: 18

                color: "#2A0A10D8"

                border.width: 1
                border.color: root.dangerRed

                Text {
                    anchors.centerIn: parent

                    width: parent.width - 32

                    text: "This action is destructive. Confirm only if you are sure."

                    color: "#FFB8B8"

                    font.pixelSize: 14
                    font.bold: true

                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18

                ConfirmButton {
                    label: "CANCEL"
                    selected: root.selectedAction === 0
                    danger: false
                }

                ConfirmButton {
                    label: "DELETE"
                    selected: root.selectedAction === 1
                    danger: true
                }
            }

            Text {
                width: parent.width

                text: "X CONFIRM  •  O CANCEL"

                color: root.textMuted

                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.2

                horizontalAlignment: Text.AlignHCenter

                opacity: 0.80
            }
        }
    }

    /*
        ============================================================
                            COMPONENTS
        ============================================================
    */

    component ConfirmButton: Rectangle {
        property string label: ""
        property bool selected: false
        property bool danger: false

        width: 220
        height: 68
        radius: 22

        color: selected
               ? danger ? "#3A1116" : "#104D86EE"
               : "#071426DD"

        border.width: selected ? 3 : 1
        border.color: danger
                      ? root.dangerRed
                      : selected
                        ? root.focusBlue
                        : "#2A8DCC"

        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: selected ? 0.052 : 0.026
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -42

            width: parent.width * 0.62
            height: 76
            radius: 38

            color: danger ? root.dangerRed : root.focusBlue
            opacity: selected ? 0.070 + root.dangerPulse * 0.060 : 0.018
        }

        Text {
            anchors.centerIn: parent

            text: label

            color: danger && selected ? "#FFD1D1" : root.textPrimary

            font.pixelSize: 19
            font.bold: true
            font.letterSpacing: 1.4
        }

        Rectangle {
            visible: selected

            anchors.fill: parent
            anchors.margins: -5

            radius: parent.radius + 5

            color: "transparent"

            border.width: 1
            border.color: danger ? root.dangerRed : root.focusBlue

            opacity: 0.40 + root.dangerPulse * 0.28
        }
    }

    /*
        ============================================================
                            KEYS
        ============================================================
    */

    Keys.onLeftPressed: moveLeft()
    Keys.onRightPressed: moveRight()

    Keys.onReturnPressed: activateSelected()
    Keys.onEnterPressed: activateSelected()
    Keys.onSpacePressed: activateSelected()

    Keys.onEscapePressed: close()
    Keys.onBackPressed: close()
}