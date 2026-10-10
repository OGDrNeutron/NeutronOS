import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                               ARMED RING
        ============================================================

        Purpose:
            Reusable red armed-state overlay for destructive actions.

        Used for:
            - Quick action destructive confirmation.
            - Shutdown / reboot / stop / delete states.
            - AppTile armed state.
            - QuickActionTile armed state.
            - ModalTabButton danger confirmation.
            - SystemCard / SystemBox destructive actions.
            - HiddenDock dangerous rows.

        Design rules:
            - Red ring means armed/destructive confirmation.
            - Blue focus stays separate in FocusRing.qml.
            - No MouseArea.
            - No Button.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles only.
            - Animations stop when hidden/inactive.
            - Controller-first visual language.

        API:
            armed: true/false
            label: "ARMED"
            subtitle: optional small text
            dangerColor: main red
            radius: corner radius
            margin: outside margin
            lineWidth: ring width
            showLabel/showCorners/showSweep/showPulse
    */

    property bool armed: false
    property bool active: armed
    property bool animationsEnabled: visible && enabled && active

    property string label: "ARMED"
    property string subtitle: ""

    property bool showLabel: true
    property bool showSubtitle: subtitle.length > 0
    property bool showCorners: true
    property bool showSweep: true
    property bool showPulse: true
    property bool showInnerGlow: true
    property bool showBottomWarningBar: true

    property real radius: 24
    property real margin: 6
    property real lineWidth: 3

    property color dangerColor: "#ff3040"
    property color dangerSoft: "#ff6b7a"
    property color dangerDeep: "#3a0710"
    property color textColor: "#ffd1d1"

    property real pulse: 0.45
    property real sweep: -1.0
    property real labelPulse: 0.45

    /*
        If parent does not size it explicitly, it still has a useful footprint.
    */
    implicitWidth: 220
    implicitHeight: 140

    visible: active || opacity > 0.0
    opacity: active ? 1.0 : 0.0

    Behavior on opacity {
        enabled: true

        NumberAnimation {
            duration: 120
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
            duration: 520
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.32
            duration: 520
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on labelPulse {
        running: root.animationsEnabled && root.showLabel
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.42
            to: 1.0
            duration: 720
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.42
            duration: 720
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && root.showSweep
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 1350
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 1350
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            OUTER WARNING GLOW
        ============================================================
    */

    Rectangle {
        visible: root.showPulse

        anchors.fill: parent
        anchors.margins: -root.margin - 6

        radius: root.radius + root.margin + 8

        color: root.dangerColor
        opacity: root.active ? 0.055 + root.pulse * 0.055 : 0.0
    }

    /*
        ============================================================
                            MAIN RING
        ============================================================
    */

    Rectangle {
        anchors.fill: parent
        anchors.margins: -root.margin

        radius: root.radius + root.margin

        color: "transparent"

        border.width: root.lineWidth
        border.color: root.dangerColor

        opacity: root.active ? 0.78 + root.pulse * 0.20 : 0.0
    }

    Rectangle {
        visible: root.showInnerGlow

        anchors.fill: parent
        anchors.margins: -Math.max(1, root.margin * 0.35)

        radius: root.radius + Math.max(1, root.margin * 0.35)

        color: root.dangerColor
        opacity: root.active ? 0.050 + root.pulse * 0.040 : 0.0
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1

        radius: Math.max(0, root.radius - 1)

        color: "transparent"

        border.width: 1
        border.color: "#ffffff"

        opacity: root.active ? 0.10 + root.pulse * 0.06 : 0.0
    }

    /*
        ============================================================
                            MOVING SWEEP
        ============================================================
    */

    Rectangle {
        visible: root.showSweep && root.width > 40

        width: Math.max(42, root.width * 0.20)
        height: Math.max(2, root.lineWidth - 1)
        radius: height / 2

        x: (root.width - width) * ((root.sweep + 1.0) / 2.0)
        y: -root.margin - 1

        color: root.dangerSoft
        opacity: root.active ? 0.32 + root.pulse * 0.25 : 0.0
    }

    Rectangle {
        visible: root.showSweep && root.width > 40

        width: Math.max(42, root.width * 0.20)
        height: Math.max(2, root.lineWidth - 1)
        radius: height / 2

        x: (root.width - width) * ((1.0 - root.sweep) / 2.0)
        y: root.height + root.margin - height + 1

        color: root.dangerColor
        opacity: root.active ? 0.28 + root.pulse * 0.22 : 0.0
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
        property color bracketColor: root.dangerColor

        width: 28
        height: 28

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
            width: 28
            height: Math.max(2, root.lineWidth)
            radius: height / 2
            color: corner.bracketColor
        }

        Rectangle {
            x: 0
            y: 0
            width: Math.max(2, root.lineWidth)
            height: 28
            radius: width / 2
            color: corner.bracketColor
        }
    }

    Item {
        visible: root.showCorners

        anchors.fill: parent
        anchors.margins: -root.margin - 4

        opacity: root.active ? 0.72 + root.pulse * 0.24 : 0.0

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
                            LABEL BADGE
        ============================================================
    */

    Rectangle {
        id: labelBadge

        visible: root.showLabel

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -root.margin - height / 2

        width: Math.max(84, labelText.implicitWidth + 34)
        height: root.showSubtitle ? 44 : 28
        radius: height / 2

        color: root.dangerDeep

        border.width: 1
        border.color: root.dangerColor

        opacity: root.active ? 0.92 + root.labelPulse * 0.06 : 0.0

        Column {
            anchors.centerIn: parent
            spacing: -1

            Text {
                id: labelText

                anchors.horizontalCenter: parent.horizontalCenter

                text: root.label

                color: root.textColor

                font.pixelSize: root.showSubtitle ? 11 : 12
                font.bold: true
                font.letterSpacing: 2.2

                horizontalAlignment: Text.AlignHCenter
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Text {
                visible: root.showSubtitle

                anchors.horizontalCenter: parent.horizontalCenter

                text: root.subtitle

                color: "#ff9a9a"

                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.1

                horizontalAlignment: Text.AlignHCenter
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }
    }

    /*
        ============================================================
                            BOTTOM WARNING BAR
        ============================================================
    */

    Rectangle {
        visible: root.showBottomWarningBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: -root.margin - 2

        height: Math.max(4, root.lineWidth + 2)
        radius: height / 2

        color: root.dangerColor
        opacity: root.active ? 0.62 + root.pulse * 0.26 : 0.0
    }

    /*
        ============================================================
                            PUBLIC HELPERS
        ============================================================
    */

    function arm() {
        root.armed = true
        root.active = true
    }

    function disarm() {
        root.armed = false
        root.active = false
    }

    function setArmed(value) {
        root.armed = !!value
        root.active = root.armed
    }

    onArmedChanged: {
        active = armed
    }

    onVisibleChanged: {
        if (!visible) {
            pulse = 0.45
            labelPulse = 0.45
            sweep = -1.0
        }
    }
}