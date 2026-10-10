import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                              PROCESS CIRCLE
        ============================================================

        Preserved from original:
            - name property.
            - label property.
            - percent property.
            - diameter property.
            - thickness property.
            - lowColor / midColor / highColor threshold colors.
            - accent color based on percent.
            - Circular Canvas usage ring.
            - Center percent text.
            - Process/app name below.
            - Optional label below name.
            - No MouseArea.
            - No Button.

        Next-gen updates:
            - Explicit QtQuick 2.15 import.
            - Canvas uses clearRect instead of ctx.reset().
            - Safe clamping for percent, diameter, and thickness.
            - Smooth animated percent changes.
            - Animations pause when hidden/disabled.
            - Canvas repaints on size/color/percent changes.
            - Better text fallback.
            - Optional compact mode.
            - Still very lightweight for Raspberry Pi.
            - No placeholder data.
    */

    property string name: "--"
    property string label: ""
    property int percent: 0

    property int diameter: 64
    property int thickness: 6

    property bool animationsEnabled: visible && enabled
    property bool showPercentText: true
    property bool showName: true
    property bool showLabel: true
    property bool compact: false

    property color lowColor: "#22ff88"
    property color midColor: "#facc15"
    property color highColor: "#ff3040"

    property color trackColor: "#22324a"
    property color textColor: "white"
    property color nameColor: "#cfeaff"
    property color labelColor: "#8aa6c8"

    property color accent: clampedPercent() < 56
                           ? lowColor
                           : clampedPercent() < 80
                             ? midColor
                             : highColor

    property real paintedPercent: clampedPercent()

    width: Math.max(safeDiameter(), safeDiameter() + 24)
    height: safeDiameter() + (compact ? 22 : 32)

    Behavior on paintedPercent {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    Behavior on accent {
        enabled: root.animationsEnabled

        ColorAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                                RING
        ============================================================
    */

    Canvas {
        id: ring

        width: root.safeDiameter()
        height: root.safeDiameter()

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        antialiasing: true
        renderTarget: Canvas.Image

        onPaint: {
            var ctx = getContext("2d")

            ctx.clearRect(0, 0, width, height)

            if (width <= 2 || height <= 2)
                return

            var lineWidth = root.safeThickness()
            var cx = width / 2
            var cy = height / 2
            var r = Math.max(1, (Math.min(width, height) / 2) - (lineWidth / 2) - 1)

            var pct = Math.max(0, Math.min(100, root.paintedPercent))
            var start = -Math.PI / 2
            var end = start + (Math.PI * 2 * (pct / 100.0))

            ctx.lineCap = "round"
            ctx.lineWidth = lineWidth

            /*
                Track.
            */
            ctx.strokeStyle = root.trackColor
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2, false)
            ctx.stroke()

            /*
                Usage arc.
            */
            if (pct > 0) {
                ctx.strokeStyle = root.accent
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, end, false)
                ctx.stroke()
            }

            /*
                Subtle inner glass guide.
            */
            ctx.lineWidth = 1
            ctx.strokeStyle = "rgba(255,255,255,0.10)"
            ctx.beginPath()
            ctx.arc(cx, cy, Math.max(1, r - lineWidth - 3), 0, Math.PI * 2, false)
            ctx.stroke()
        }

        Connections {
            target: root

            function onPercentChanged() {
                root.paintedPercent = root.clampedPercent()
            }

            function onPaintedPercentChanged() {
                ring.requestPaint()
            }

            function onAccentChanged() {
                ring.requestPaint()
            }

            function onTrackColorChanged() {
                ring.requestPaint()
            }

            function onDiameterChanged() {
                ring.requestPaint()
            }

            function onThicknessChanged() {
                ring.requestPaint()
            }

            function onVisibleChanged() {
                if (root.visible)
                    ring.requestPaint()
            }

            function onEnabledChanged() {
                if (root.enabled)
                    ring.requestPaint()
            }
        }

        Component.onCompleted: {
            ring.requestPaint()
        }
    }

    /*
        ============================================================
                            CENTER TEXT
        ============================================================
    */

    Text {
        anchors.centerIn: ring

        visible: root.showPercentText

        text: root.clampedPercent() + "%"

        color: root.textColor

        font.pixelSize: root.compact ? 11 : 14
        font.bold: true

        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    /*
        ============================================================
                            LABELS
        ============================================================
    */

    Text {
        id: nameText

        visible: root.showName

        anchors.top: ring.bottom
        anchors.topMargin: root.compact ? 3 : 5
        anchors.horizontalCenter: parent.horizontalCenter

        width: root.safeDiameter() + 24

        horizontalAlignment: Text.AlignHCenter

        text: root.displayName()

        color: root.nameColor

        font.pixelSize: root.compact ? 9 : 10
        font.bold: true

        elide: Text.ElideRight
        maximumLineCount: 1
    }

    Text {
        visible: root.showLabel && root.displayLabel().length > 0

        anchors.top: nameText.bottom
        anchors.topMargin: root.compact ? 1 : 2
        anchors.horizontalCenter: parent.horizontalCenter

        width: root.safeDiameter() + 24

        horizontalAlignment: Text.AlignHCenter

        text: root.displayLabel()

        color: root.labelColor

        font.pixelSize: root.compact ? 7 : 8
        font.bold: true

        elide: Text.ElideRight
        maximumLineCount: 1
    }

    /*
        ============================================================
                            HELPERS
        ============================================================
    */

    function cleanText(value) {
        if (value === undefined || value === null)
            return ""

        var text = String(value).trim()

        if (text === "undefined" || text === "null")
            return ""

        return text
    }

    function clampedPercent() {
        var value = Number(percent)

        if (isNaN(value))
            value = 0

        return Math.max(0, Math.min(100, Math.round(value)))
    }

    function safeDiameter() {
        var value = Number(diameter)

        if (isNaN(value))
            value = 64

        return Math.max(32, Math.round(value))
    }

    function safeThickness() {
        var value = Number(thickness)

        if (isNaN(value))
            value = 6

        value = Math.max(2, Math.round(value))

        return Math.min(value, Math.max(2, safeDiameter() / 4))
    }

    function displayName() {
        var text = cleanText(name)

        if (text.length <= 0)
            return "--"

        return text
    }

    function displayLabel() {
        return cleanText(label)
    }

    onVisibleChanged: {
        if (visible)
            ring.requestPaint()
    }

    Component.onCompleted: {
        paintedPercent = clampedPercent()
        ring.requestPaint()
    }
}