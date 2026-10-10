import QtQuick 2.15

Item {
    id: root

    /*
        PATCH 16B-R2: CONSOLE ARC GAUGE

        Console-only CPU/RAM gauge inspired by the supplied speedometer.
        The resource-monitor modals are intentionally outside this patch.

        Rendering characteristics:
          - One cached Canvas image.
          - Repaints only when telemetry, size, or visibility changes.
          - A short transition is allowed when the sampled percentage changes.
          - No timer, rotation loop, shader, or continuous animation.
    */

    property string title: ""
    property string value: "--"
    property string subtitle: ""
    property int percent: 0

    property int diameter: 180
    property int thickness: 14
    property bool animationsEnabled: visible && enabled

    property color greenColor: "#25e88a"
    property color greenYellowColor: "#a9ed35"
    property color yellowColor: "#ffd43b"
    property color yellowRedColor: "#ff8a32"
    property color redColor: "#ff3045"
    property color trackColor: "#203149"

    readonly property color accent: colorForPercent(clampedPercent())
    property real paintedPercent: clampedPercent()

    width: safeDiameter()
    height: safeDiameter()

    Behavior on paintedPercent {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: outerFrame

        anchors.fill: parent
        radius: width / 2

        color: "#07111dcc"
        border.width: Math.max(2, root.safeDiameter() * 0.012)
        border.color: "#52657d"

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#152536" }
            GradientStop { position: 0.38; color: "#08131f" }
            GradientStop { position: 1.0; color: "#03080f" }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.max(8, root.safeDiameter() * 0.047)
        radius: width / 2

        color: "#02070dcc"
        border.width: 1
        border.color: "#7df9ff2e"
    }

    Canvas {
        id: gaugeCanvas

        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            if (width <= 4 || height <= 4)
                return

            var cx = width / 2
            var cy = height / 2
            var lineWidth = root.safeThickness()
            var radius = Math.max(2, Math.min(width, height) / 2 - lineWidth - 10)
            var startAngle = root.degreesToRadians(122)
            var totalSweep = root.degreesToRadians(296)
            var pct = Math.max(0, Math.min(100, root.paintedPercent))

            function angleForPercent(value) {
                return startAngle + totalSweep * (value / 100.0)
            }

            function strokeArc(fromPercent, toPercent, colorValue, widthValue, alphaValue) {
                if (toPercent <= fromPercent)
                    return

                ctx.save()
                ctx.globalAlpha = alphaValue
                ctx.lineCap = "butt"
                ctx.lineWidth = widthValue
                ctx.strokeStyle = colorValue
                ctx.beginPath()
                ctx.arc(
                    cx,
                    cy,
                    radius,
                    angleForPercent(fromPercent),
                    angleForPercent(toPercent),
                    false
                )
                ctx.stroke()
                ctx.restore()
            }

            /* Inactive arc track with rounded cutout ends. */
            ctx.save()
            ctx.lineCap = "round"
            ctx.lineWidth = lineWidth
            ctx.strokeStyle = root.trackColor
            ctx.beginPath()
            ctx.arc(cx, cy, radius, startAngle, startAngle + totalSweep, false)
            ctx.stroke()
            ctx.restore()

            /*
                Smooth cumulative health gradient. There are no threshold
                separator lines: the active arc blends continuously from
                green through yellow and orange into red. Rendering remains
                cached and happens only when telemetry changes.
            */
            var segmentCount = 120
            var activeSegments = Math.ceil((pct / 100.0) * segmentCount)

            for (var glowSegment = 0; glowSegment < activeSegments; ++glowSegment) {
                var glowFrom = (glowSegment / segmentCount) * 100
                var glowTo = Math.min(pct, ((glowSegment + 1) / segmentCount) * 100)
                var glowMid = (glowFrom + glowTo) * 0.5
                strokeArc(glowFrom, glowTo + 0.08, root.colorForPercent(glowMid), lineWidth + 7, 0.16)
            }

            for (var activeSegment = 0; activeSegment < activeSegments; ++activeSegment) {
                var activeFrom = (activeSegment / segmentCount) * 100
                var activeTo = Math.min(pct, ((activeSegment + 1) / segmentCount) * 100)
                var activeMid = (activeFrom + activeTo) * 0.5
                strokeArc(activeFrom, activeTo + 0.08, root.colorForPercent(activeMid), lineWidth, 1.0)
            }

            /* Colored cap at zero and at the live endpoint. */
            if (pct > 0) {
                var startX = cx + Math.cos(startAngle) * radius
                var startY = cy + Math.sin(startAngle) * radius
                var endAngle = angleForPercent(pct)
                var endX = cx + Math.cos(endAngle) * radius
                var endY = cy + Math.sin(endAngle) * radius

                ctx.fillStyle = root.colorForPercent(0)
                ctx.beginPath()
                ctx.arc(startX, startY, lineWidth * 0.49, 0, Math.PI * 2, false)
                ctx.fill()

                ctx.fillStyle = root.colorForPercent(pct)
                ctx.beginPath()
                ctx.arc(endX, endY, lineWidth * 0.49, 0, Math.PI * 2, false)
                ctx.fill()
            }

            /* Speedometer-style ticks follow the same smooth gradient. */
            var tickOuter = radius - lineWidth * 0.88
            var tickCount = 40

            for (var tick = 0; tick <= tickCount; ++tick) {
                var tickPercent = (tick / tickCount) * 100
                var tickAngle = angleForPercent(tickPercent)
                var majorTick = tick % 5 === 0
                var tickLength = majorTick ? lineWidth * 0.82 : lineWidth * 0.43
                var tickInner = tickOuter - tickLength

                ctx.save()
                ctx.lineCap = "round"
                ctx.lineWidth = majorTick ? 2.2 : 1.2
                ctx.globalAlpha = tickPercent <= pct ? 0.95 : 0.23
                ctx.strokeStyle = tickPercent <= pct
                                  ? root.colorForPercent(tickPercent)
                                  : "#c8dcf2"
                ctx.beginPath()
                ctx.moveTo(
                    cx + Math.cos(tickAngle) * tickInner,
                    cy + Math.sin(tickAngle) * tickInner
                )
                ctx.lineTo(
                    cx + Math.cos(tickAngle) * tickOuter,
                    cy + Math.sin(tickAngle) * tickOuter
                )
                ctx.stroke()
                ctx.restore()
            }

            /* Inner guide rings reinforce the instrument appearance. */
            ctx.save()
            ctx.lineWidth = 1
            ctx.globalAlpha = 0.18
            ctx.strokeStyle = "#dceeff"
            ctx.beginPath()
            ctx.arc(cx, cy, Math.max(2, radius - lineWidth - 9), 0, Math.PI * 2, false)
            ctx.stroke()
            ctx.globalAlpha = 0.09
            ctx.beginPath()
            ctx.arc(cx, cy, Math.max(2, radius - lineWidth - 18), 0, Math.PI * 2, false)
            ctx.stroke()
            ctx.restore()

            /*
                Digital health face centered in the open middle of the CPU/RAM gauge.
                0–55 is green/smiling, 56–79 is yellow/neutral, and 80–100
                is red/frowning. The face shares this cached Canvas and adds
                no timer or continuous scene-graph work.
            */
            var faceMode = pct <= 55 ? "smile" : (pct < 80 ? "neutral" : "frown")
            var faceColor = faceMode === "smile"
                            ? root.greenColor
                            : (faceMode === "neutral"
                               ? root.yellowColor
                               : root.redColor)
            var facePatterns = {
                smile: [
                    "0100010",
                    "0100010",
                    "0000000",
                    "0000000",
                    "1000001",
                    "0100010",
                    "0011100"
                ],
                neutral: [
                    "0100010",
                    "0100010",
                    "0000000",
                    "0000000",
                    "0000000",
                    "0111110",
                    "0000000"
                ],
                frown: [
                    "0100010",
                    "0100010",
                    "0000000",
                    "0000000",
                    "0011100",
                    "0100010",
                    "1000001"
                ]
            }
            var pattern = facePatterns[faceMode]
            var pixelSize = Math.max(2.4, root.safeDiameter() * 0.019)
            var pixelGap = Math.max(1.0, pixelSize * 0.34)
            var faceStep = pixelSize + pixelGap
            var faceWidth = faceStep * 7 - pixelGap
            var faceHeight = faceStep * 7 - pixelGap
            var faceLeft = cx - faceWidth / 2
            var faceTop = cy - faceHeight / 2

            ctx.save()
            ctx.fillStyle = faceColor
            ctx.shadowColor = faceColor
            ctx.shadowBlur = Math.max(4, pixelSize * 1.8)
            for (var faceRow = 0; faceRow < 7; ++faceRow) {
                for (var faceColumn = 0; faceColumn < 7; ++faceColumn) {
                    if (pattern[faceRow].charAt(faceColumn) !== "1")
                        continue
                    var px = faceLeft + faceColumn * faceStep
                    var py = faceTop + faceRow * faceStep
                    ctx.fillRect(px, py, pixelSize, pixelSize)
                }
            }
            ctx.restore()
        }

        Connections {
            target: root

            function onPercentChanged() {
                root.paintedPercent = root.clampedPercent()
            }

            function onPaintedPercentChanged() {
                gaugeCanvas.requestPaint()
            }

            function onDiameterChanged() {
                gaugeCanvas.requestPaint()
            }

            function onThicknessChanged() {
                gaugeCanvas.requestPaint()
            }

            function onVisibleChanged() {
                if (root.visible)
                    gaugeCanvas.requestPaint()
            }

            function onEnabledChanged() {
                if (root.enabled)
                    gaugeCanvas.requestPaint()
            }
        }

        Component.onCompleted: requestPaint()
    }

    /* Bottom cutout readout: label above the live percentage. */
    Column {
        id: readout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(5, root.safeDiameter() * 0.025)

        spacing: -2
        z: 5

        Text {
            width: Math.max(72, root.safeDiameter() * 0.46)

            text: root.cleanText(root.title).length > 0
                  ? root.cleanText(root.title).toUpperCase()
                  : "SYSTEM"

            color: "#f2f8ff"
            font.pixelSize: Math.max(13, root.safeDiameter() * 0.076)
            font.bold: true
            font.letterSpacing: 1.5

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            width: Math.max(82, root.safeDiameter() * 0.54)

            text: Math.round(root.paintedPercent) + "%"
            color: "white"

            font.pixelSize: Math.max(25, root.safeDiameter() * 0.17)
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(56, root.safeDiameter() * 0.34)
            height: 2
            radius: 1
            color: root.accent
            opacity: 0.9
        }
    }

    function cleanText(input) {
        if (input === undefined || input === null)
            return ""

        var text = String(input).trim()

        if (text === "undefined" || text === "null")
            return ""

        return text
    }

    function clampedPercent() {
        var number = Number(percent)

        if (isNaN(number))
            number = 0

        return Math.max(0, Math.min(100, number))
    }

    function safeDiameter() {
        var number = Number(diameter)

        if (isNaN(number))
            number = 180

        return Math.max(96, Math.round(number))
    }

    function safeThickness() {
        var number = Number(thickness)

        if (isNaN(number))
            number = 14

        number = Math.max(8, Math.round(number))
        return Math.min(number, Math.max(8, safeDiameter() / 7))
    }

    function degreesToRadians(degrees) {
        return Number(degrees) * Math.PI / 180.0
    }

    function colorForPercent(value) {
        var number = Number(value)

        if (isNaN(number))
            number = 0

        number = Math.max(0, Math.min(100, number))

        /*
            Health-face thresholds remain 0–55, 56–79, and 80–100,
            while the arc itself blends smoothly with no hard color seam.
        */
        if (number <= 45)
            return greenColor

        if (number <= 60)
            return blendColor(greenColor, greenYellowColor, (number - 45) / 15.0)

        if (number <= 72)
            return blendColor(greenYellowColor, yellowColor, (number - 60) / 12.0)

        if (number <= 84)
            return blendColor(yellowColor, yellowRedColor, (number - 72) / 12.0)

        return blendColor(yellowRedColor, redColor, (number - 84) / 16.0)
    }

    function blendColor(fromColor, toColor, amount) {
        var a = Math.max(0, Math.min(1, Number(amount)))
        return Qt.rgba(
            fromColor.r + (toColor.r - fromColor.r) * a,
            fromColor.g + (toColor.g - fromColor.g) * a,
            fromColor.b + (toColor.b - fromColor.b) * a,
            fromColor.a + (toColor.a - fromColor.a) * a
        )
    }

    onVisibleChanged: {
        if (visible)
            gaugeCanvas.requestPaint()
    }

    Component.onCompleted: {
        paintedPercent = clampedPercent()
        gaugeCanvas.requestPaint()
    }
}
