import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                               GLASS PANEL
        ============================================================

        Purpose:
            Reusable NeutronOS liquid-glass surface.

        Used for:
            - Login panels.
            - Console sections.
            - Modal backgrounds.
            - App containers.
            - Toolbars.
            - Status strips.
            - Header panels.
            - Info panels.

        Design rules:
            - Dark cosmic glass.
            - Subtle cyan/purple edge energy.
            - No MouseArea.
            - No Button.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles/text-safe container only.
            - Animations stop when hidden/inactive.
            - Controller-first UI surface.

        Notes:
            - FocusRing.qml handles blue controller focus.
            - ArmedRing.qml handles red destructive confirmation.
            - This panel can still tint itself for focused/armed state when needed.
    */

    default property alias content: contentLayer.data

    property bool focused: false
    property bool armed: false
    property bool active: true
    property bool highlighted: false
    property bool disabled: false

    property bool animationsEnabled: visible && enabled && active
    property bool sweepEnabled: true
    property bool pulseEnabled: true
    property bool showTopLine: true
    property bool showInnerLine: true
    property bool showOuterGlow: true
    property bool showBottomLine: false
    property bool clipContent: false

    property real radius: 28
    property real borderWidth: 1
    property real padding: 0

    property color panelColor: "#071426d8"
    property color panelColorFocused: "#0a1b34e8"
    property color panelColorArmed: "#23070bdd"
    property color borderColor: "#2b5d8f77"
    property color focusColor: "#4da6ff"
    property color accentColor: "#7df9ff"
    property color purpleColor: "#a855f7"
    property color dangerColor: "#ff3040"
    property color disabledColor: "#05080faa"

    property real pulse: 0.42
    property real sweep: -1.0
    property real breathe: 0.52

    implicitWidth: 320
    implicitHeight: 180

    opacity: disabled ? 0.54 : 1.0

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    scale: highlighted ? 1.012 : 1.0

    Behavior on scale {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled && root.pulseEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.32
            to: 1.0
            duration: root.armed ? 620 : 1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.32
            duration: root.armed ? 620 : 1800
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on breathe {
        running: root.animationsEnabled && root.pulseEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.42
            to: 1.0
            duration: 2600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.42
            duration: 2600
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && root.sweepEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.armed ? 1450 : 4200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.armed ? 1450 : 4200
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            OUTER GLOW
        ============================================================
    */

    Rectangle {
        visible: root.showOuterGlow

        anchors.fill: parent
        anchors.margins: -10

        radius: root.radius + 12

        color: root.edgeColor()
        opacity: root.disabled ? 0.0 :
                 root.armed ? 0.050 + root.pulse * 0.055 :
                 root.focused ? 0.038 + root.pulse * 0.045 :
                 root.highlighted ? 0.028 + root.breathe * 0.035 :
                                    0.018 + root.breathe * 0.018
    }

    Rectangle {
        visible: root.showOuterGlow && !root.armed

        anchors.fill: parent
        anchors.margins: -4

        radius: root.radius + 6

        color: root.purpleColor
        opacity: root.disabled ? 0.0 :
                 root.focused || root.highlighted ? 0.014 + root.breathe * 0.020 :
                                                     0.008 + root.breathe * 0.010
    }

    /*
        ============================================================
                            MAIN PANEL
        ============================================================
    */

    Rectangle {
        id: panel

        anchors.fill: parent

        radius: root.radius

        color: root.currentPanelColor()

        border.width: root.borderWidth
        border.color: root.currentBorderColor()

        clip: root.clipContent

        Behavior on color {
            enabled: root.animationsEnabled

            ColorAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on border.color {
            enabled: root.animationsEnabled

            ColorAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        /*
            Subtle liquid-glass body depth.
        */
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2

            radius: Math.max(0, root.radius - 2)

            color: "#ffffff"
            opacity: root.disabled ? 0.018 : 0.030
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 8

            height: 1
            radius: 1

            color: "#ffffff"
            opacity: root.disabled ? 0.030 : 0.105
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.bottomMargin: 8

            height: 1
            radius: 1

            color: root.edgeColor()
            opacity: root.showBottomLine ? 0.18 + root.pulse * 0.10 : 0.0
        }
    }

    /*
        ============================================================
                            EDGE LINES
        ============================================================
    */

    Rectangle {
        visible: root.showTopLine

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18

        height: Math.max(1, root.borderWidth)
        radius: height / 2

        color: root.edgeColor()
        opacity: root.disabled ? 0.08 :
                 root.armed ? 0.42 + root.pulse * 0.22 :
                 root.focused ? 0.34 + root.pulse * 0.16 :
                                0.18 + root.breathe * 0.08
    }

    Rectangle {
        visible: root.showInnerLine

        anchors.fill: parent
        anchors.margins: 1

        radius: Math.max(0, root.radius - 1)

        color: "transparent"

        border.width: 1
        border.color: "#ffffff"

        opacity: root.disabled ? 0.030 :
                 root.armed ? 0.075 + root.pulse * 0.040 :
                 root.focused ? 0.080 + root.pulse * 0.050 :
                                0.050
    }

    /*
        ============================================================
                            MOVING SWEEP
        ============================================================
    */

    Rectangle {
        visible: root.sweepEnabled && root.width > 50

        width: Math.max(70, root.width * 0.18)
        height: 1
        radius: 1

        x: (root.width - width) * ((root.sweep + 1.0) / 2.0)
        y: 0

        color: root.edgeBrightColor()
        opacity: root.disabled ? 0.0 :
                 root.armed ? 0.26 + root.pulse * 0.24 :
                 root.focused ? 0.22 + root.pulse * 0.18 :
                                0.12 + root.breathe * 0.10
    }

    Rectangle {
        visible: root.sweepEnabled && root.width > 50 && root.highlighted

        width: Math.max(60, root.width * 0.14)
        height: 1
        radius: 1

        x: (root.width - width) * ((1.0 - root.sweep) / 2.0)
        y: root.height - 1

        color: root.purpleColor
        opacity: root.disabled ? 0.0 : 0.10 + root.breathe * 0.10
    }

    /*
        ============================================================
                            CONTENT LAYER
        ============================================================
    */

    Item {
        id: contentLayer

        anchors.fill: parent
        anchors.margins: root.padding

        clip: root.clipContent
    }

    /*
        ============================================================
                            HELPERS
        ============================================================
    */

    function currentPanelColor() {
        if (root.disabled)
            return root.disabledColor

        if (root.armed)
            return root.panelColorArmed

        if (root.focused || root.highlighted)
            return root.panelColorFocused

        return root.panelColor
    }

    function currentBorderColor() {
        if (root.disabled)
            return "#1f2a4488"

        if (root.armed)
            return root.dangerColor

        if (root.focused)
            return root.focusColor

        if (root.highlighted)
            return root.accentColor

        return root.borderColor
    }

    function edgeColor() {
        if (root.armed)
            return root.dangerColor

        if (root.focused)
            return root.focusColor

        if (root.highlighted)
            return root.accentColor

        return root.accentColor
    }

    function edgeBrightColor() {
        if (root.armed)
            return "#ff8a96"

        if (root.focused)
            return root.accentColor

        if (root.highlighted)
            return "#d8b4fe"

        return root.accentColor
    }

    function setFocused(value) {
        root.focused = !!value
    }

    function setArmed(value) {
        root.armed = !!value
    }

    function setHighlighted(value) {
        root.highlighted = !!value
    }

    onVisibleChanged: {
        if (!visible) {
            pulse = 0.42
            sweep = -1.0
            breathe = 0.52
        }
    }
}