import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            SCROLL RAIL
        ============================================================

        Visual-only scroll indicator.

        Important:
        - Not focusable.
        - Not selectable.
        - No mouse assumptions.
        - Controller never lands here.
        - Right stick scrolls the page through FileGrid.qml.
        - D-pad/left stick selection auto-scrolls through FileGrid.qml.
    */

    width: 8

    property real scrollPercent: 0.0
    property real handlePercent: 1.0
    property bool focused: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color dangerRed: "#FF3040"

    property real glowPulse: 0.35

    SequentialAnimation on glowPulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1800
            easing.type: Easing.InOutSine
        }
    }

    function clampedScroll() {
        return Math.max(0.0, Math.min(1.0, Number(scrollPercent || 0.0)))
    }

    function clampedHandle() {
        return Math.max(0.08, Math.min(1.0, Number(handlePercent || 1.0)))
    }

    Rectangle {
        id: rail

        anchors.fill: parent

        radius: width / 2

        color: "#071426AA"

        border.width: 1
        border.color: "#244B66"

        opacity: 0.82

        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1

            color: "#FFFFFF"
            opacity: 0.030
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            width: 2
            height: parent.height

            radius: 1

            color: root.focusBlue
            opacity: 0.10
        }
    }

    Rectangle {
        id: handleGlow

        anchors.horizontalCenter: parent.horizontalCenter

        width: parent.width + 10
        height: handle.height + 18
        radius: width / 2

        y: handle.y - 9

        color: root.focusBlue
        opacity: 0.035 + root.glowPulse * 0.030
    }

    Rectangle {
        id: handle

        anchors.horizontalCenter: parent.horizontalCenter

        width: parent.width
        height: Math.max(36, parent.height * root.clampedHandle())
        radius: width / 2

        y: Math.max(0, Math.min(parent.height - height,
                                (parent.height - height) * root.clampedScroll()))

        color: root.focusBlue

        opacity: 0.66 + root.glowPulse * 0.22

        Behavior on y {
            NumberAnimation {
                duration: 130
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 130
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1

            color: "#FFFFFF"
            opacity: 0.18
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 5

            width: parent.width * 0.42
            height: Math.max(10, parent.height - 10)
            radius: width / 2

            color: "#FFFFFF"
            opacity: 0.26
        }
    }
}