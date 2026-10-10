import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                               FOCUS RING
        ============================================================

        Purpose:
            Reusable blue focus overlay for controller navigation.

        Used for:
            - AppTile selected state.
            - QuickActionTile selected state.
            - SystemCard selected state.
            - User cards.
            - Modal buttons.
            - Hidden dock items.
            - Any controller-focusable surface.

        Design rules:
            - Blue means navigation focus.
            - Red armed state belongs in ArmedRing.qml.
            - No MouseArea.
            - No Button.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles only.
            - Animations stop when hidden/inactive.
            - Safe for Raspberry Pi 60 FPS UI.
    */

    property bool focused: false
    property bool active: focused
    property bool animationsEnabled: visible && enabled && active

    property bool showPulse: true
    property bool showCorners: true
    property bool showSweep: true
    property bool showInnerLine: true
    property bool showOuterGlow: true
    property bool showBottomBar: false

    property real radius: 24
    property real margin: 5
    property real lineWidth: 3

    property color focusColor: "#4da6ff"
    property color focusBright: "#7df9ff"
    property color focusSoft: "#9fd8ff"
    property color focusDeep: "#06162d"

    property real pulse: 0.45
    property real sweep: -1.0
    property real breathe: 0.5

    implicitWidth: 220
    implicitHeight: 140

    visible: active || opacity > 0.0
    opacity: active ? 1.0 : 0.0

    Behavior on opacity {
        enabled: true

        NumberAnimation {
            duration: 110
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled && root.showPulse
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.32
            to: 1.0
            duration: 1250
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.32
            duration: 1250
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on breathe {
        running: root.animationsEnabled && root.showPulse
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.45
            to: 1.0
            duration: 1850
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.45
            duration: 1850
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && root.showSweep
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
                            OUTER BLUE GLOW
        ============================================================
    */

    Rectangle {
        visible: root.showOuterGlow

        anchors.fill: parent
        anchors.margins: -root.margin - 7

        radius: root.radius + root.margin + 9

        color: root.focusColor
        opacity: root.active ? 0.040 + root.pulse * 0.050 : 0.0
    }

    Rectangle {
        visible: root.showOuterGlow

        anchors.fill: parent
        anchors.margins: -root.margin - 2

        radius: root.radius + root.margin + 4

        color: root.focusBright
        opacity: root.active ? 0.020 + root.breathe * 0.030 : 0.0
    }

    /*
        ============================================================
                            MAIN FOCUS RING
        ============================================================
    */

    Rectangle {
        anchors.fill: parent
        anchors.margins: -root.margin

        radius: root.radius + root.margin

        color: "transparent"

        border.width: root.lineWidth
        border.color: root.focusColor

        opacity: root.active ? 0.70 + root.pulse * 0.20 : 0.0
    }

    Rectangle {
        visible: root.showInnerLine

        anchors.fill: parent
        anchors.margins: 1

        radius: Math.max(0, root.radius - 1)

        color: "transparent"

        border.width: 1
        border.color: root.focusBright

        opacity: root.active ? 0.20 + root.pulse * 0.12 : 0.0
    }

    Rectangle {
        visible: root.showInnerLine

        anchors.fill: parent
        anchors.margins: -Math.max(1, root.margin * 0.35)

        radius: root.radius + Math.max(1, root.margin * 0.35)

        color: root.focusColor
        opacity: root.active ? 0.025 + root.pulse * 0.025 : 0.0
    }

    /*
        ============================================================
                            MOVING ENERGY SWEEP
        ============================================================
    */

    Rectangle {
        visible: root.showSweep && root.width > 40

        width: Math.max(42, root.width * 0.18)
        height: Math.max(2, root.lineWidth - 1)
        radius: height / 2

        x: (root.width - width) * ((root.sweep + 1.0) / 2.0)
        y: -root.margin - 1

        color: root.focusBright
        opacity: root.active ? 0.22 + root.pulse * 0.20 : 0.0
    }

    Rectangle {
        visible: root.showSweep && root.width > 40

        width: Math.max(42, root.width * 0.18)
        height: Math.max(2, root.lineWidth - 1)
        radius: height / 2

        x: (root.width - width) * ((1.0 - root.sweep) / 2.0)
        y: root.height + root.margin - height + 1

        color: root.focusSoft
        opacity: root.active ? 0.18 + root.pulse * 0.16 : 0.0
    }

    /*
        ============================================================
                            CORNER BRACKETS
        ============================================================
    */

    component CornerBracket: Item {
        id: corner

        property bool mirrorX: false
        property bool mirrorY: false
        property color bracketColor: root.focusBright

        width: 25
        height: 25

        transform: [
            Scale {
                origin.x: corner.width / 2
                origin.y: corner.height / 2
                xScale: corner.mirrorX ? -1 : 1
                yScale: corner.mirrorY ? -1 : 1
            }
        ]

        Rectangle {
            x: 0
            y: 0
            width: 25
            height: Math.max(2, root.lineWidth - 1)
            radius: height / 2
            color: corner.bracketColor
        }

        Rectangle {
            x: 0
            y: 0
            width: Math.max(2, root.lineWidth - 1)
            height: 25
            radius: width / 2
            color: corner.bracketColor
        }
    }

    Item {
        visible: root.showCorners

        anchors.fill: parent
        anchors.margins: -root.margin - 3

        opacity: root.active ? 0.48 + root.pulse * 0.22 : 0.0

        CornerBracket {
            anchors.left: parent.left
            anchors.top: parent.top
        }

        CornerBracket {
            anchors.right: parent.right
            anchors.top: parent.top
            mirrorX: true
        }

        CornerBracket {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            mirrorY: true
        }

        CornerBracket {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            mirrorX: true
            mirrorY: true
        }
    }

    /*
        ============================================================
                            OPTIONAL BOTTOM BAR
        ============================================================
    */

    Rectangle {
        visible: root.showBottomBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: -root.margin - 2

        height: Math.max(3, root.lineWidth + 1)
        radius: height / 2

        color: root.focusBright
        opacity: root.active ? 0.40 + root.pulse * 0.20 : 0.0
    }

    /*
        ============================================================
                            PUBLIC HELPERS
        ============================================================
    */

    function setFocused(value) {
        root.focused = !!value
        root.active = root.focused
    }

    function show() {
        root.focused = true
        root.active = true
    }

    function hide() {
        root.focused = false
        root.active = false
    }

    onFocusedChanged: {
        active = focused
    }

    onVisibleChanged: {
        if (!visible) {
            pulse = 0.45
            breathe = 0.5
            sweep = -1.0
        }
    }
}