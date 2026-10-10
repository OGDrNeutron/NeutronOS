import QtQuick

/*
    NeutronOS Modern Dashboard CPU / RAM gauge.

    Visual goals:
      - premium near-complete circular gauge with the gap centered at the bottom
      - blue/cyan energy at the ends, green low range, yellow mid range,
        orange/red high range
      - fine white gauge ticks
      - subtle static electric/circuit halo
      - centered label, percentage and Load/Usage text
      - no continuous animation or shader load; Canvas repaints only when the
        metric value or geometry changes
*/
Item {
    id: root

    property real value: 0
    property bool valid: true
    property string label: "CPU"
    property string subtitle: label === "RAM" ? "Usage" : "Load"

    // Retained for compatibility with existing callers. The new gauge uses
    // its own fixed NeutronOS risk spectrum instead of per-widget colors.
    property color startColor: "#18D98C"
    property color endColor: "#FF4967"

    property real animatedValue: 0

    function clamp01(v) {
        return Math.max(0, Math.min(1, Number(v || 0)))
    }

    function spectrumRgb(t) {
        var stops = [
            [0.00,  27, 174, 255],  // cyan / blue at lower gap edge
            [0.10,  43, 226, 143],  // green
            [0.35, 110, 242,  78],  // lime
            [0.52, 246, 236,  58],  // yellow
            [0.68, 255, 161,  48],  // orange
            [0.84, 255,  67,  78],  // red
            [0.94, 255,  60, 133],  // magenta
            [1.00,  49, 169, 255]   // blue at upper gap edge
        ]

        var x = clamp01(t)
        for (var i = 0; i < stops.length - 1; ++i) {
            var a = stops[i]
            var b = stops[i + 1]
            if (x >= a[0] && x <= b[0]) {
                var span = Math.max(0.0001, b[0] - a[0])
                var f = (x - a[0]) / span
                return [
                    Math.round(a[1] + (b[1] - a[1]) * f),
                    Math.round(a[2] + (b[2] - a[2]) * f),
                    Math.round(a[3] + (b[3] - a[3]) * f)
                ]
            }
        }
        return [49, 169, 255]
    }

    function rgba(rgb, alpha) {
        return "rgba(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + "," + alpha + ")"
    }

    function valueColor() {
        var v = clamp01(animatedValue / 100.0)
        // Status color intentionally follows risk rather than the decorative
        // blue energy at each end of the ring.
        if (v < 0.50) return "#48E283"
        if (v < 0.75) return "#F4DD42"
        if (v < 0.90) return "#FF9F38"
        return "#FF4967"
    }

    onValueChanged: {
        valueAnimation.stop()
        valueAnimation.from = animatedValue
        valueAnimation.to = Math.max(0, Math.min(100, Number(value || 0)))
        valueAnimation.start()
    }

    Component.onCompleted: {
        animatedValue = Math.max(0, Math.min(100, Number(value || 0)))
        gaugeCanvas.requestPaint()
    }

    NumberAnimation {
        id: valueAnimation
        target: root
        property: "animatedValue"
        duration: 420
        easing.type: Easing.OutCubic
    }

    Canvas {
        id: gaugeCanvas
        anchors.fill: parent
        antialiasing: true

        function drawArc(ctx, cx, cy, radius, width, color, start, end) {
            ctx.beginPath()
            ctx.lineWidth = width
            ctx.lineCap = "round"
            ctx.strokeStyle = color
            ctx.arc(cx, cy, radius, start, end, false)
            ctx.stroke()
        }

        function drawSpectralArc(ctx, cx, cy, radius, width, start, sweep, alpha, fraction) {
            var segments = 112
            var visibleFraction = Math.max(0, Math.min(1, fraction))
            var count = Math.max(0, Math.round(segments * visibleFraction))

            for (var i = 0; i < count; ++i) {
                var f0 = i / segments
                var f1 = (i + 1.28) / segments
                var rgb = root.spectrumRgb((f0 + f1) * 0.5)
                var a0 = start + sweep * f0
                var a1 = start + sweep * Math.min(1, f1)

                ctx.beginPath()
                ctx.lineWidth = width
                ctx.lineCap = "butt"
                ctx.strokeStyle = root.rgba(rgb, alpha)
                ctx.arc(cx, cy, radius, a0, a1, false)
                ctx.stroke()
            }
        }

        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            if (w <= 2 || h <= 2)
                return

            ctx.reset()

            var cx = w * 0.5
            var cy = h * 0.50
            var outer = Math.min(w, h) * 0.455
            var ringRadius = outer * 0.78
            var ringWidth = Math.max(8, outer * 0.105)

            // Gap centered at the bottom. Canvas angles are clockwise in screen
            // coordinates, so this starts just left of the bottom gap and wraps
            // around the top to the right edge of that gap.
            var start = Math.PI * 0.62
            var sweep = Math.PI * 1.76
            var end = start + sweep

            // Static "electric" halo. It is intentionally deterministic and
            // never animated, so it contributes visual depth without runtime load.
            for (var halo = 0; halo < 4; ++halo) {
                var hr = outer * (0.91 + halo * 0.035)
                var alpha = 0.11 - halo * 0.018
                drawArc(ctx, cx, cy, hr, Math.max(1, outer * 0.010),
                        halo % 2 === 0
                            ? "rgba(39,153,255," + alpha + ")"
                            : "rgba(215,62,255," + alpha + ")",
                        start - halo * 0.016, end + halo * 0.012)
            }

            // Fine geometric halo fragments around the upper two-thirds.
            ctx.lineWidth = Math.max(0.8, outer * 0.006)
            for (var n = 0; n < 58; ++n) {
                var f = n / 57.0
                var angle = start + sweep * f
                // Skip the lower opening region to preserve the clean gap.
                var rr = outer * (1.01 + 0.035 * Math.sin(n * 2.47))
                var span = 0.030 + 0.018 * (0.5 + 0.5 * Math.sin(n * 1.93))
                var rgbHalo = f < 0.48 ? [34, 157, 255] : [218, 56, 255]
                ctx.strokeStyle = root.rgba(rgbHalo, 0.14 + 0.08 * (0.5 + 0.5 * Math.sin(n)))
                ctx.beginPath()
                ctx.arc(cx, cy, rr, angle, angle + span, false)
                ctx.stroke()
            }

            // Dark background track.
            drawArc(ctx, cx, cy, ringRadius, ringWidth * 1.28,
                    "rgba(8,18,38,0.92)", start, end)

            // Dim full spectrum gives the reference its complete rainbow ring.
            drawSpectralArc(ctx, cx, cy, ringRadius, ringWidth,
                            start, sweep, root.valid ? 0.34 : 0.10, 1.0)

            // Glow under the active range, built from two broad low-alpha strokes.
            var active = root.valid ? root.clamp01(root.animatedValue / 100.0) : 0
            drawSpectralArc(ctx, cx, cy, ringRadius, ringWidth * 1.55,
                            start, sweep, 0.10, active)
            drawSpectralArc(ctx, cx, cy, ringRadius, ringWidth * 1.26,
                            start, sweep, 0.17, active)

            // Bright active range.
            drawSpectralArc(ctx, cx, cy, ringRadius, ringWidth * 0.82,
                            start, sweep, root.valid ? 0.98 : 0.15, active)

            // Inner cyan/red guide arcs.
            drawArc(ctx, cx, cy, ringRadius - ringWidth * 1.16,
                    Math.max(1, outer * 0.010), "rgba(23,218,255,0.54)",
                    start + 0.01, start + sweep * 0.48)
            drawArc(ctx, cx, cy, ringRadius - ringWidth * 1.16,
                    Math.max(1, outer * 0.010), "rgba(255,64,99,0.48)",
                    start + sweep * 0.52, end - 0.01)

            // Gauge tick marks.
            var ticks = 92
            for (var t = 0; t <= ticks; ++t) {
                var tf = t / ticks
                var a = start + sweep * tf
                var major = (t % 5 === 0)
                var r1 = ringRadius - ringWidth * (major ? 0.58 : 0.46)
                var r2 = ringRadius + ringWidth * (major ? 0.49 : 0.37)
                var activeTick = tf <= active
                var tickAlpha = root.valid
                    ? (activeTick ? (major ? 0.93 : 0.70) : (major ? 0.30 : 0.18))
                    : 0.14

                ctx.beginPath()
                ctx.lineWidth = major ? Math.max(1.1, outer * 0.008) : Math.max(0.8, outer * 0.005)
                ctx.strokeStyle = "rgba(247,250,255," + tickAlpha + ")"
                ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1)
                ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2)
                ctx.stroke()
            }

            // Bright end caps at the two sides of the bottom gap.
            var capWidth = ringWidth * 0.94
            drawArc(ctx, cx, cy, ringRadius, capWidth,
                    "rgba(35,183,255,0.92)", start - 0.018, start + 0.055)
            drawArc(ctx, cx, cy, ringRadius, capWidth,
                    "rgba(60,173,255,0.92)", end - 0.055, end + 0.018)

            // Active-value marker.
            if (root.valid && active > 0.005) {
                var markerAngle = start + sweep * active
                var markerRgb = root.spectrumRgb(active)
                var mx = cx + Math.cos(markerAngle) * ringRadius
                var my = cy + Math.sin(markerAngle) * ringRadius

                ctx.fillStyle = root.rgba(markerRgb, 0.20)
                ctx.beginPath()
                ctx.arc(mx, my, ringWidth * 0.56, 0, Math.PI * 2)
                ctx.fill()

                ctx.fillStyle = "rgba(255,255,255,0.96)"
                ctx.beginPath()
                ctx.arc(mx, my, Math.max(1.8, ringWidth * 0.12), 0, Math.PI * 2)
                ctx.fill()
            }

            // Dark center disk.
            ctx.fillStyle = "rgba(4,13,28,0.84)"
            ctx.beginPath()
            ctx.arc(cx, cy, ringRadius - ringWidth * 1.50, 0, Math.PI * 2)
            ctx.fill()

            ctx.lineWidth = Math.max(1, outer * 0.008)
            ctx.strokeStyle = "rgba(39,161,255,0.26)"
            ctx.stroke()
        }

        Connections {
            target: root
            function onAnimatedValueChanged() { gaugeCanvas.requestPaint() }
            function onValidChanged() { gaugeCanvas.requestPaint() }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -root.height * 0.006
        width: parent.width * 0.60
        spacing: Math.max(1, root.height * 0.010)

        Text {
            width: parent.width
            text: root.label
            color: "#F7F8FC"
            font.pixelSize: Math.max(13, root.width * 0.100)
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: root.valid ? Math.round(root.animatedValue) + "%" : "--"
            color: root.valid ? "#FFFFFF" : "#718096"
            font.pixelSize: Math.max(30, root.width * 0.205)
            font.weight: Font.Light
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: root.valid ? root.subtitle : "Unavailable"
            color: root.valid ? "#A9B6DC" : "#718096"
            font.pixelSize: Math.max(10, root.width * 0.072)
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
