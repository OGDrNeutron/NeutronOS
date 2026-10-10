import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            GLASS ICON BUTTON
        ============================================================

        Controller-first visual button.

        Used by:
        - Header back / forward arrows
        - Search icon button
        - Future quick action icons

        No MouseArea.
        Parent components call activate().
    */

    width: 58
    height: 58

    property string iconText: "•"
    property string label: ""

    property bool focused: false
    property bool selected: false
    property bool armed: false
    property bool danger: false
    property bool enabledButton: true
    property bool compact: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color dangerRed: "#FF3040"
    property color textPrimary: "#F3FCFF"
    property color textMuted: "#6F8FB8"

    property real pulse: 0.35

    signal activated()

    function activate() {
        if (!enabledButton)
            return

        activated()
    }

    SequentialAnimation on pulse {
        running: root.visible && root.enabledButton && (root.focused || root.selected || root.armed)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 1050
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1050
            easing.type: Easing.InOutQuad
        }
    }

    Rectangle {
        id: shell

        anchors.fill: parent

        radius: root.compact ? 16 : 20

        color: !root.enabledButton
               ? "#06101AAA"
               : root.armed
                 ? "#300A10EE"
                 : root.focused || root.selected
                   ? "#104D86EE"
                   : "#071426DD"

        border.width: root.focused || root.selected || root.armed ? 2 : 1
        border.color: !root.enabledButton
                      ? "#264053"
                      : root.armed || root.danger
                        ? root.dangerRed
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
            opacity: root.enabledButton ? 0.045 : 0.018
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

            y: -parent.height * 0.54

            width: parent.width * 1.22
            height: parent.height * 0.90
            radius: height / 2

            color: root.armed || root.danger ? root.dangerRed : root.focusBlue
            opacity: root.enabledButton
                     ? ((root.focused || root.selected || root.armed)
                        ? 0.070 + root.pulse * 0.075
                        : 0.030)
                     : 0.0
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4

            width: parent.width * 0.42
            height: 2
            radius: 1

            color: root.armed || root.danger ? root.dangerRed : root.focusBlue
            opacity: root.enabledButton
                     ? ((root.focused || root.selected || root.armed)
                        ? 0.40 + root.pulse * 0.30
                        : 0.18)
                     : 0.0
        }
    }

    Text {
        id: icon

        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.label.length > 0 ? -7 : 0

        text: root.iconText

        color: !root.enabledButton
               ? root.textMuted
               : root.armed || root.danger
                 ? "#FFD1D1"
                 : root.focused || root.selected
                   ? "#FFFFFF"
                   : root.textPrimary

        font.pixelSize: root.compact ? 24 : 30
        font.bold: true

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        opacity: root.enabledButton ? 1.0 : 0.48

        style: Text.Raised
        styleColor: "#66000000"
    }

    Text {
        visible: root.label.length > 0

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: icon.bottom
        anchors.topMargin: -2

        width: parent.width - 8

        text: root.label

        color: root.enabledButton ? "#B9EEFF" : root.textMuted

        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 0.8

        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight

        opacity: root.enabledButton ? 0.86 : 0.40
    }

    Rectangle {
        visible: root.focused && root.enabledButton

        anchors.fill: parent
        anchors.margins: -4

        radius: shell.radius + 4

        color: "transparent"

        border.width: 1
        border.color: root.focusBlue

        opacity: 0.38 + root.pulse * 0.28
    }
}