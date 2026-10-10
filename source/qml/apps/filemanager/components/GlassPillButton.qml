import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            GLASS PILL BUTTON
        ============================================================

        Controller-first pill button.

        Used by:
        - View toolbar
        - Sort button
        - Quick actions
        - Modal actions

        No MouseArea.
        Parent components call activate().
    */

    width: 150
    height: 48

    property string text: "BUTTON"
    property string subtitle: ""
    property string iconText: ""

    property bool focused: false
    property bool selected: false
    property bool active: false
    property bool armed: false
    property bool danger: false
    property bool enabledButton: true

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color greenAccent: "#22FF88"
    property color dangerRed: "#FF3040"
    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#6F8FB8"

    property real pulse: 0.35

    signal activated()

    function activate() {
        if (!enabledButton)
            return

        activated()
    }

    SequentialAnimation on pulse {
        running: root.visible && root.enabledButton && (root.focused || root.selected || root.active || root.armed)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 1200
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1200
            easing.type: Easing.InOutQuad
        }
    }

    Rectangle {
        id: shell

        anchors.fill: parent

        radius: height / 2

        color: !root.enabledButton
               ? "#06101AAA"
               : root.armed || root.danger
                 ? "#2A0A10EE"
                 : root.active
                   ? "#0E3D66EE"
                   : root.focused || root.selected
                     ? "#104D86EE"
                     : "#071426DD"

        border.width: root.focused || root.selected || root.active || root.armed ? 2 : 1

        border.color: !root.enabledButton
                      ? "#264053"
                      : root.armed || root.danger
                        ? root.dangerRed
                        : root.active
                          ? root.greenAccent
                          : root.focused || root.selected
                            ? root.focusBlue
                            : "#2A8DCC"

        opacity: root.enabledButton ? 1.0 : 0.42

        clip: true

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 150
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: root.enabledButton ? 0.044 : 0.018
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 1

            color: "#FFFFFF"
            opacity: root.enabledButton ? 0.18 : 0.06
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -parent.height * 0.65

            width: parent.width * 0.82
            height: parent.height * 1.05
            radius: height / 2

            color: root.armed || root.danger
                   ? root.dangerRed
                   : root.active
                     ? root.greenAccent
                     : root.focusBlue

            opacity: root.enabledButton
                     ? ((root.focused || root.selected || root.active || root.armed)
                        ? 0.060 + root.pulse * 0.070
                        : 0.028)
                     : 0.0
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4

            width: parent.width * 0.46
            height: 2
            radius: 1

            color: root.armed || root.danger
                   ? root.dangerRed
                   : root.active
                     ? root.greenAccent
                     : root.focusBlue

            opacity: root.enabledButton
                     ? ((root.focused || root.selected || root.active || root.armed)
                        ? 0.38 + root.pulse * 0.32
                        : 0.16)
                     : 0.0
        }
    }

    Row {
        anchors.centerIn: parent

        spacing: root.iconText.length > 0 ? 8 : 0

        Text {
            visible: root.iconText.length > 0

            anchors.verticalCenter: parent.verticalCenter

            text: root.iconText

            color: !root.enabledButton
                   ? root.textMuted
                   : root.armed || root.danger
                     ? "#FFD1D1"
                     : root.active
                       ? "#D5FFE8"
                       : root.focused || root.selected
                         ? "#FFFFFF"
                         : root.textSecondary

            font.pixelSize: 17
            font.bold: true

            opacity: root.enabledButton ? 1.0 : 0.48
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            spacing: -1

            Text {
                text: root.text

                color: !root.enabledButton
                       ? root.textMuted
                       : root.armed || root.danger
                         ? "#FFD1D1"
                         : root.focused || root.selected || root.active
                           ? "#FFFFFF"
                           : root.textPrimary

                font.pixelSize: root.subtitle.length > 0 ? 14 : 15
                font.bold: true
                font.letterSpacing: 1.0

                horizontalAlignment: Text.AlignHCenter

                opacity: root.enabledButton ? 1.0 : 0.48
            }

            Text {
                visible: root.subtitle.length > 0

                text: root.subtitle

                color: root.enabledButton ? root.textMuted : "#4A5D72"

                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.7

                horizontalAlignment: Text.AlignHCenter

                opacity: root.enabledButton ? 0.82 : 0.42
            }
        }
    }

    Rectangle {
        visible: root.focused && root.enabledButton

        anchors.fill: parent
        anchors.margins: -4

        radius: height / 2

        color: "transparent"

        border.width: 1
        border.color: root.focusBlue

        opacity: 0.36 + root.pulse * 0.26
    }
}