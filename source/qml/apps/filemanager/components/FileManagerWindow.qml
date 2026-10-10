import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                        FILE MANAGER WINDOW SHELL
        ============================================================

        Floating Liquid Glass desktop-style window.

        This is the hero shell:
        - large centered glass panel
        - cyan/purple edge glow
        - subtle animated sweep
        - red armed state
        - blue focus state
        - no mouse assumptions
    */

    property bool focused: true
    property bool armed: false
    property bool busy: false
    property bool connected: true

    property color shellColor: "#061A2EF0"
    property color innerColor: "#071426D8"
    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color greenAccent: "#22FF88"
    property color dangerRed: "#FF3040"

    property real glowPulse: 0.35
    property real busyPulse: 0.0
    property real sweep: -1.0

    SequentialAnimation on glowPulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 2600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 2600
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on busyPulse {
        running: root.busy
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.0
            to: 1.0
            duration: 700
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.0
            duration: 700
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation on sweep {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 4400
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 4400
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            OUTER GLOW
        ============================================================
    */

    Rectangle {
        anchors.centerIn: parent

        width: parent.width + 42
        height: parent.height + 42
        radius: 44

        color: root.armed ? root.dangerRed : root.focusBlue
        opacity: root.focused
                 ? (root.armed ? 0.060 + root.glowPulse * 0.050
                                : 0.040 + root.glowPulse * 0.040)
                 : 0.022
    }

    Rectangle {
        anchors.centerIn: parent

        width: parent.width + 80
        height: parent.height + 72
        radius: 58

        color: root.purpleGlow
        opacity: root.focused ? 0.018 + root.glowPulse * 0.020 : 0.010
    }

    /*
        ============================================================
                            MAIN GLASS
        ============================================================
    */

    Rectangle {
        id: shell

        anchors.fill: parent

        radius: 36

        color: root.armed ? "#230910F0" : root.shellColor

        border.width: root.armed ? 3 : 2
        border.color: root.armed
                      ? root.dangerRed
                      : root.focused
                        ? root.focusBlue
                        : "#2A8DCC"

        clip: true

        Behavior on color {
            ColorAnimation {
                duration: 170
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 170
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.038
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
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            width: root.armed ? 8 : 5
            radius: width / 2

            color: root.armed
                   ? root.dangerRed
                   : root.connected
                     ? root.focusBlue
                     : root.dangerRed

            opacity: root.armed ? 0.86 : 0.62
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -190

            width: parent.width * 0.72
            height: 380
            radius: 190

            color: root.armed ? root.dangerRed : root.focusBlue
            opacity: root.armed
                     ? 0.038 + root.glowPulse * 0.030
                     : 0.032 + root.glowPulse * 0.024
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: -190
            anchors.bottomMargin: -230

            width: 520
            height: 520
            radius: 260

            color: root.electricBlue
            opacity: 0.020
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -170
            anchors.topMargin: -210

            width: 500
            height: 500
            radius: 250

            color: root.purpleGlow
            opacity: 0.018
        }

        /*
            Bottom sweep line.
        */

        Rectangle {
            width: 260
            height: 3
            radius: 2

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.bottom: parent.bottom

            color: root.armed ? root.dangerRed : root.focusBlue
            opacity: root.busy ? 0.34 + root.busyPulse * 0.28
                               : 0.22 + root.glowPulse * 0.10
        }

        /*
            Busy shimmer.
        */

        Rectangle {
            visible: root.busy

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 3

            color: root.focusBlue
            opacity: 0.24 + root.busyPulse * 0.34
        }
    }
}