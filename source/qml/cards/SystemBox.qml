import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    /*
        ============================================================
                            SYSTEM BOX
        ============================================================

        Reusable metric card for SystemOverview.

        Preserved from original:
            - title
            - value
            - subvalue
            - percent
            - optional circular gauge
            - GlassCard focused/armed styling
            - Canvas circular ring

        Next-gen updates:
            - Title is pinned to the top.
            - Main value is centered.
            - Optional subvalue stays below value.
            - Linear usage bar appears for non-circular cards.
            - Circular gauge safely clamps percent.
            - Warning/critical colors.
            - Safe systemMonitor connection.
            - Ring repaints when percent/focus/armed/visible changes.
            - Animations pause when hidden.
            - No placeholder behavior.
    */

    property string title: ""
    property string value: ""
    property string subvalue: ""

    /*
        Expected 0..100 from backend.
        Bad values are clamped instead of breaking the Canvas.
    */
    property int percent: 0

    property bool circular: false
    property bool showPercentText: false
    property bool showLinearBar: !circular
    property bool animationsEnabled: visible && enabled

    property int warningPercent: 78
    property int criticalPercent: 90

    property color normalColor: root.accent
    property color focusedColor: "#4da6ff"
    property color armedColor: "#ff3040"
    property color warningColor: "#f5c542"
    property color criticalColor: "#ff3040"
    property color trackColor: "#223355"

    property real pulse: 0.55

    /*
        Safe backend reference.
        This avoids a ReferenceError when SystemBox is previewed or loaded
        before systemMonitor is exposed.
    */
    property var systemBackend: {
        try {
            if (typeof systemMonitor !== "undefined" && systemMonitor)
                return systemMonitor
        } catch (e) {
        }

        return null
    }

    implicitWidth: 172
    implicitHeight: 118

    function clampedPercent() {
        var p = Number(percent)

        if (isNaN(p))
            return 0

        return Math.max(0, Math.min(100, p))
    }

    function metricColor() {
        var p = clampedPercent()

        if (root.armed)
            return armedColor

        if (p >= criticalPercent)
            return criticalColor

        if (p >= warningPercent)
            return warningColor

        if (root.focused)
            return focusedColor

        return normalColor
    }

    function percentLabel() {
        return Math.round(clampedPercent()) + "%"
    }

    SequentialAnimation on pulse {
        running: root.animationsEnabled &&
                 (root.focused ||
                  root.armed ||
                  root.clampedPercent() >= root.warningPercent)

        loops: Animation.Infinite

        NumberAnimation {
            from: 0.42
            to: 1.0
            duration: root.armed || root.clampedPercent() >= root.criticalPercent ? 620 : 1650
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.42
            duration: root.armed || root.clampedPercent() >= root.criticalPercent ? 620 : 1650
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            TITLE
        ============================================================
    */

    Text {
        id: titleText

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 8

        width: parent.width - 14

        text: root.title

        color: root.metricColor()

        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 0.6

        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1

        opacity: root.focused || root.armed ? 1.0 : 0.88
    }

    /*
        ============================================================
                            CIRCULAR RING
        ============================================================
    */

    Canvas {
        id: ring

        visible: root.circular

        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.subvalue.length > 0 ? -5 : 3

        width: 64
        height: 64

        antialiasing: true

        onPaint: {
            var ctx = getContext("2d")
            var p = root.clampedPercent() / 100.0
            var center = width / 2
            var radius = 24
            var line = 6

            ctx.clearRect(0, 0, width, height)

            ctx.lineWidth = line
            ctx.lineCap = "round"

            ctx.strokeStyle = root.trackColor
            ctx.globalAlpha = 0.90
            ctx.beginPath()
            ctx.arc(center, center, radius, 0, Math.PI * 2)
            ctx.stroke()

            ctx.strokeStyle = root.metricColor()
            ctx.globalAlpha =
                    root.armed ||
                    root.focused ||
                    root.clampedPercent() >= root.warningPercent
                    ? 0.72 + root.pulse * 0.28
                    : 0.92

            ctx.beginPath()
            ctx.arc(center,
                    center,
                    radius,
                    -Math.PI / 2,
                    -Math.PI / 2 + Math.PI * 2 * p)
            ctx.stroke()

            if (root.focused || root.armed) {
                ctx.lineWidth = 1
                ctx.strokeStyle = root.metricColor()
                ctx.globalAlpha = root.armed ? 0.42 + root.pulse * 0.25
                                             : 0.30 + root.pulse * 0.18
                ctx.beginPath()
                ctx.arc(center, center, radius + 8, 0, Math.PI * 2)
                ctx.stroke()
            }

            ctx.globalAlpha = 1.0
        }

        Connections {
            target: root.systemBackend
            ignoreUnknownSignals: true

            function onSystemChanged() {
                ring.requestPaint()
            }
        }

        Connections {
            target: root

            function onFocusedChanged() {
                ring.requestPaint()
            }

            function onArmedChanged() {
                ring.requestPaint()
            }

            function onPercentChanged() {
                ring.requestPaint()
            }

            function onCircularChanged() {
                ring.requestPaint()
            }

            function onVisibleChanged() {
                if (root.visible)
                    ring.requestPaint()
            }
        }

        Connections {
            target: root

            function onPulseChanged() {
                if (root.circular &&
                        (root.focused ||
                         root.armed ||
                         root.clampedPercent() >= root.warningPercent)) {
                    ring.requestPaint()
                }
            }
        }
    }

    /*
        ============================================================
                            CENTER VALUE
        ============================================================
    */

    Column {
        id: valueColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.circular ? 2 : -3
        anchors.leftMargin: 10
        anchors.rightMargin: 10

        spacing: 4

        Text {
            id: valueText

            width: parent.width

            text: root.value.length > 0 ? root.value : "--"

            color: "white"

            font.pixelSize: root.circular ? 17 : 20
            font.bold: true
            font.letterSpacing: 0.2

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            style: Text.Outline
            styleColor: "#99000000"
        }

        Text {
            visible: root.subvalue.length > 0 && !root.circular

            width: parent.width

            text: root.subvalue

            color: "#8aa6c8"

            font.pixelSize: 10
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: 0.94
        }
    }

    /*
        Circular cards use the subvalue at the bottom so it does not collide
        with the ring/value.
    */
    Text {
        visible: root.subvalue.length > 0 && root.circular

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10

        width: parent.width - 14

        text: root.subvalue

        color: "#8aa6c8"

        font.pixelSize: 10
        font.bold: true

        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1

        opacity: 0.94
    }

    /*
        ============================================================
                            LINEAR BAR
        ============================================================
    */

    Item {
        id: linearBar

        visible: root.showLinearBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 10

        height: 16

        Rectangle {
            id: barTrack

            anchors.left: parent.left
            anchors.right: root.showPercentText ? percentText.left : parent.right
            anchors.rightMargin: root.showPercentText ? 8 : 0
            anchors.verticalCenter: parent.verticalCenter

            height: 6
            radius: 3

            color: root.trackColor
            opacity: 0.86

            Rectangle {
                id: barFill

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                width: parent.width * root.clampedPercent() / 100.0
                radius: parent.radius

                color: root.metricColor()

                opacity: root.armed ||
                         root.focused ||
                         root.clampedPercent() >= root.warningPercent
                         ? 0.72 + root.pulse * 0.28
                         : 0.92

                Behavior on width {
                    enabled: root.animationsEnabled

                    NumberAnimation {
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on color {
                    enabled: root.animationsEnabled

                    ColorAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            id: percentText

            visible: root.showPercentText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: root.percentLabel()

            color: root.metricColor()

            font.pixelSize: 10
            font.bold: true

            opacity: root.focused ||
                     root.armed ||
                     root.clampedPercent() >= root.warningPercent
                     ? 1.0
                     : 0.82
        }
    }

    /*
        ============================================================
                            WARNING OUTLINE
        ============================================================
    */

    Rectangle {
        visible: root.armed || root.clampedPercent() >= root.warningPercent

        anchors.fill: parent
        anchors.margins: root.armed ? -2 : 0

        radius: root.radius + 2
        color: "transparent"

        border.width: root.armed || root.clampedPercent() >= root.criticalPercent ? 2 : 1
        border.color: root.metricColor()

        opacity: root.armed ||
                 root.clampedPercent() >= root.criticalPercent
                 ? 0.22 + root.pulse * 0.28
                 : 0.14 + root.pulse * 0.18
    }

    Component.onCompleted: {
        if (root.circular)
            ring.requestPaint()
    }
}