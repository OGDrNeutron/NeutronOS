import QtQuick

/*
    NeutronOS Modern Dashboard thermal energy ring.

    Code-driven renderer tuned for the Pi:
      - no PNG ring assets
      - one threaded dynamic Canvas at ~30 FPS while visible
      - one static Canvas for ticks/boundaries
      - clockwise plasma-flow modulation
      - smooth blue -> violet -> red thermal color field
      - randomized clockwise purple tracer with a short reactive wake
*/
Item {
    id: root
    clip: true

    property real temperatureFahrenheit: 0
    property var history: []
    property bool valid: false
    property bool throttled: false
    property real learnedBaseline: 0
    property string adaptiveStatus: "Stable"
    property real criticalThreshold: 160
    property bool animationEnabled: visible

    // Dynamic ring state. Positive angular motion is clockwise in screen space.
    property real flowPhase: 0
    property real tracerStartAngle: 0
    property real tracerTravel: 0
    property int tracerDuration: 720
    property bool tracerActive: false

    readonly property real temperatureCelsius:
        valid ? (temperatureFahrenheit - 32.0) * 5.0 / 9.0 : 0
    readonly property real baselineDifference:
        learnedBaseline > 0 && valid ? temperatureFahrenheit - learnedBaseline : 0
    readonly property bool critical:
        throttled ||
        (valid && temperatureFahrenheit >=
         Math.min(160, criticalThreshold > 0 ? criticalThreshold : 160))

    readonly property string statusLabel: {
        if (!valid)
            return "Unavailable"
        if (learnedBaseline <= 0)
            return critical ? "Hot" : "Stable"
        if (baselineDifference < -10)
            return "Cool"
        if (baselineDifference >= 30)
            return "Hot"
        if (baselineDifference > 10)
            return "Warm"
        return "Stable"
    }

    readonly property color statusColor:
        statusLabel === "Cool" ? "#36D9FF" :
        statusLabel === "Warm" ? "#FFB14A" :
        statusLabel === "Hot" ? "#FF365B" :
        statusLabel === "Unavailable" ? "#8D9DB1" : "#24F0D4"

    readonly property real motionMultiplier:
        statusLabel === "Hot" ? 1.35 :
        statusLabel === "Warm" ? 1.15 : 1.0

    readonly property real tracerAngle:
        normalizeDegrees(tracerStartAngle + tracerTravel)

    function normalizeDegrees(value) {
        var result = value % 360
        return result < 0 ? result + 360 : result
    }

    function angularDistance(a, b) {
        var d = Math.abs(normalizeDegrees(a) - normalizeDegrees(b))
        return Math.min(d, 360 - d)
    }

    // Returns how far a ring segment is behind the clockwise-moving tracer.
    function clockwiseTrailDistance(segmentAngle, headAngle) {
        return normalizeDegrees(headAngle - segmentAngle)
    }

    function clamp01(v) {
        return Math.max(0, Math.min(1, v))
    }

    function mix(a, b, amount) {
        return a + (b - a) * clamp01(amount)
    }

    function rgba(r, g, b, a) {
        return "rgba(" + Math.round(clamp01(r) * 255) + "," +
               Math.round(clamp01(g) * 255) + "," +
               Math.round(clamp01(b) * 255) + "," + clamp01(a) + ")"
    }

    /*
        The color field is anchored like the reference image: blue dominates
        the left side and red dominates the right. At the top/bottom they
        blend smoothly through an electric violet-white transition.
    */
    function thermalColor(angleDegrees, brightness, alpha) {
        var radians = angleDegrees * Math.PI / 180.0
        var redWeight = 0.5 + 0.5 * Math.cos(radians)
        redWeight = clamp01(redWeight)

        var blueR = 0.02
        var blueG = 0.50
        var blueB = 1.00
        var redR = 1.00
        var redG = 0.10
        var redB = 0.08

        var r = mix(blueR, redR, redWeight)
        var g = mix(blueG, redG, redWeight)
        var b = mix(blueB, redB, redWeight)

        // Lift the crossover toward the bright violet-white seen in the target.
        var crossover = 1.0 - Math.abs(redWeight - 0.5) * 2.0
        crossover = Math.pow(clamp01(crossover), 3.2)
        r = mix(r, 0.94, crossover * 0.30)
        g = mix(g, 0.48, crossover * 0.22)
        b = mix(b, 1.00, crossover * 0.28)

        // The tracer temporarily turns its current location and wake purple.
        if (root.tracerActive) {
            var behind = clockwiseTrailDistance(angleDegrees, root.tracerAngle)
            var trailLength = 34.0
            var trailWeight = behind <= trailLength
                            ? Math.pow(1.0 - behind / trailLength, 1.6)
                            : 0.0
            var headWeight = Math.max(0.0,
                                      1.0 - angularDistance(angleDegrees,
                                                            root.tracerAngle) / 7.0)
            var purpleWeight = Math.max(trailWeight * 0.88, headWeight)
            r = mix(r, 0.74, purpleWeight)
            g = mix(g, 0.16, purpleWeight)
            b = mix(b, 1.00, purpleWeight)
        }

        var light = Math.max(0.38, brightness)
        return rgba(Math.min(1, r * light),
                    Math.min(1, g * light),
                    Math.min(1, b * light),
                    alpha)
    }

    function scheduleTracer() {
        tracerDelay.interval = 1250 + Math.floor(Math.random() * 3600)
        if (animationEnabled && visible && !tracerActive)
            tracerDelay.restart()
    }

    function launchTracer() {
        tracerStartAngle = Math.floor(Math.random() * 360)
        tracerTravel = 0
        tracerDuration = 480 + Math.floor(Math.random() * 720)
        tracerActive = true
        tracerRun.restart()
    }

    onAnimationEnabledChanged: {
        if (animationEnabled && visible && !tracerActive)
            scheduleTracer()
        else if (!animationEnabled)
            tracerDelay.stop()
    }

    onVisibleChanged: {
        if (visible && animationEnabled && !tracerActive)
            scheduleTracer()
        else if (!visible)
            tracerDelay.stop()
    }

    Component.onCompleted: scheduleTracer()

    Timer {
        id: frameClock
        interval: 33
        repeat: true
        running: root.animationEnabled && root.visible
        onTriggered: {
            root.flowPhase = root.normalizeDegrees(
                        root.flowPhase + 2.15 * root.motionMultiplier)
            plasmaCanvas.requestPaint()
        }
    }

    Timer {
        id: tracerDelay
        repeat: false
        interval: 2200
        onTriggered: {
            if (root.animationEnabled && root.visible && !root.tracerActive)
                root.launchTracer()
        }
    }

    NumberAnimation {
        id: tracerRun
        target: root
        property: "tracerTravel"
        from: 0
        to: 360
        duration: root.tracerDuration
        easing.type: Easing.InOutSine
        onFinished: {
            root.tracerActive = false
            root.tracerTravel = 0
            plasmaCanvas.requestPaint()
            root.scheduleTracer()
        }
    }

    Item {
        id: reactor
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusPill.top
        anchors.bottomMargin: Math.max(5, parent.height * 0.014)

        readonly property real diameter:
            Math.min(width, height) * 0.94
        readonly property real centerX: width / 2
        readonly property real centerY: height / 2
        readonly property real ringRadius: diameter * 0.405
        readonly property real ringWidth:
            Math.max(9, Math.min(19, diameter * 0.055))

        // Static geometry makes the circle unmistakable without repainting it.
        Canvas {
            id: staticCanvas
            anchors.fill: parent
            antialiasing: true
            renderStrategy: Canvas.Threaded

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var cx = reactor.centerX
                var cy = reactor.centerY
                var radius = reactor.ringRadius

                // Outer and inner precision rings.
                ctx.beginPath()
                ctx.arc(cx, cy, radius + reactor.ringWidth * 0.88,
                        0, Math.PI * 2, false)
                ctx.lineWidth = Math.max(1, reactor.ringWidth * 0.10)
                ctx.strokeStyle = "rgba(69,135,255,0.28)"
                ctx.stroke()

                ctx.beginPath()
                ctx.arc(cx, cy, radius - reactor.ringWidth * 0.95,
                        0, Math.PI * 2, false)
                ctx.lineWidth = Math.max(1, reactor.ringWidth * 0.08)
                ctx.strokeStyle = "rgba(80,154,255,0.34)"
                ctx.stroke()

                // Inner gauge ticks, with stronger quarter markers.
                var tickRadiusOuter = radius - reactor.ringWidth * 1.35
                for (var i = 0; i < 48; ++i) {
                    var a = (i * 7.5 - 90) * Math.PI / 180.0
                    var major = (i % 12) === 0
                    var medium = (i % 4) === 0
                    var tickLength = major ? reactor.ringWidth * 0.92
                                           : medium ? reactor.ringWidth * 0.58
                                                    : reactor.ringWidth * 0.34
                    var r1 = tickRadiusOuter - tickLength
                    var r2 = tickRadiusOuter

                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(a) * r1,
                               cy + Math.sin(a) * r1)
                    ctx.lineTo(cx + Math.cos(a) * r2,
                               cy + Math.sin(a) * r2)
                    ctx.lineWidth = major ? Math.max(2, reactor.ringWidth * 0.16)
                                          : Math.max(1, reactor.ringWidth * 0.075)

                    var deg = root.normalizeDegrees(i * 7.5 - 90)
                    ctx.strokeStyle = root.thermalColor(deg,
                                                        major ? 1.20 : 0.82,
                                                        major ? 0.92 : 0.54)
                    ctx.stroke()
                }
            }
        }

        Canvas {
            id: plasmaCanvas
            anchors.fill: parent
            antialiasing: true
            renderStrategy: Canvas.Threaded

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var cx = reactor.centerX
                var cy = reactor.centerY
                var radius = reactor.ringRadius
                var ringWidth = reactor.ringWidth
                var segments = 84
                var step = 360.0 / segments

                // Base luminous ring. Each segment has a traveling intensity wave,
                // making the energy visibly move clockwise without rotating the
                // entire blue/red color geography.
                for (var i = 0; i < segments; ++i) {
                    var a0 = i * step - 90
                    var a1 = a0 + step + 1.1
                    var centerAngle = a0 + step * 0.5
                    var pulse = 0.70 + 0.30 *
                                (0.5 + 0.5 * Math.sin(
                                     centerAngle * 0.26 - root.flowPhase * 0.55))
                    var pulse2 = 0.86 + 0.14 *
                                 (0.5 + 0.5 * Math.sin(
                                      centerAngle * 0.57 - root.flowPhase * 1.12))
                    var brightness = pulse * pulse2 + 0.22

                    var start = a0 * Math.PI / 180.0
                    var end = a1 * Math.PI / 180.0

                    // Broad translucent energy glow.
                    ctx.beginPath()
                    ctx.arc(cx, cy, radius, start, end, false)
                    ctx.lineCap = "round"
                    ctx.lineWidth = ringWidth * 1.85
                    ctx.strokeStyle = root.thermalColor(centerAngle,
                                                        brightness * 0.82,
                                                        0.15 + pulse * 0.12)
                    ctx.stroke()

                    // Saturated body.
                    ctx.beginPath()
                    ctx.arc(cx, cy, radius, start, end, false)
                    ctx.lineWidth = ringWidth * 0.72
                    ctx.strokeStyle = root.thermalColor(centerAngle,
                                                        brightness * 1.04,
                                                        0.82)
                    ctx.stroke()

                    // Hot center filament.
                    ctx.beginPath()
                    ctx.arc(cx, cy, radius, start, end, false)
                    ctx.lineWidth = Math.max(1.5, ringWidth * 0.18)
                    ctx.strokeStyle = root.thermalColor(centerAngle,
                                                        brightness * 1.48,
                                                        0.96)
                    ctx.stroke()
                }

                // Two electrical strands weave inside the primary ring. They are
                // intentionally sparse to keep the Pi render cost bounded.
                for (var strand = 0; strand < 2; ++strand) {
                    var points = 60
                    var previousX = 0
                    var previousY = 0
                    var previousAngle = 0

                    for (var p = 0; p <= points; ++p) {
                        var angle = p * 360.0 / points - 90
                        var rad = angle * Math.PI / 180.0
                        var wobble = Math.sin(rad * (5.0 + strand * 1.7) -
                                              root.flowPhase * Math.PI / 92.0 -
                                              strand * 1.4)
                        var fine = Math.sin(rad * 13.0 -
                                            root.flowPhase * Math.PI / 47.0 +
                                            strand * 2.1)
                        var strandRadius = radius +
                                           wobble * ringWidth * 0.27 +
                                           fine * ringWidth * 0.08 +
                                           (strand === 0 ? -ringWidth * 0.18
                                                         : ringWidth * 0.14)
                        var x = cx + Math.cos(rad) * strandRadius
                        var y = cy + Math.sin(rad) * strandRadius

                        if (p > 0) {
                            ctx.beginPath()
                            ctx.moveTo(previousX, previousY)
                            ctx.lineTo(x, y)
                            ctx.lineCap = "round"
                            ctx.lineWidth = Math.max(1.0, ringWidth * 0.095)
                            ctx.strokeStyle = root.thermalColor(previousAngle,
                                                                1.52,
                                                                0.72)
                            ctx.stroke()
                        }

                        previousX = x
                        previousY = y
                        previousAngle = angle
                    }
                }

                // Purple tracer. It shares the exact ring radius so the wake and
                // segment recoloring line up with its physical location.
                if (root.tracerActive) {
                    var tracerRad = root.tracerAngle * Math.PI / 180.0
                    var tx = cx + Math.cos(tracerRad) * radius
                    var ty = cy + Math.sin(tracerRad) * radius

                    ctx.beginPath()
                    ctx.arc(tx, ty, ringWidth * 1.05, 0, Math.PI * 2, false)
                    ctx.fillStyle = "rgba(168,52,255,0.14)"
                    ctx.fill()

                    ctx.beginPath()
                    ctx.arc(tx, ty, ringWidth * 0.58, 0, Math.PI * 2, false)
                    ctx.fillStyle = "rgba(190,72,255,0.38)"
                    ctx.fill()

                    ctx.beginPath()
                    ctx.arc(tx, ty, Math.max(2.4, ringWidth * 0.23),
                            0, Math.PI * 2, false)
                    ctx.fillStyle = "rgba(235,205,255,1.0)"
                    ctx.fill()
                }
            }
        }

        // Dark central face, kept separate so the animated Canvas never repaints text.
        Rectangle {
            anchors.centerIn: parent
            width: reactor.diameter * 0.53
            height: width
            radius: width / 2
            color: "#E5070C18"
            border.width: Math.max(1, width * 0.006)
            border.color: root.critical ? "#68FF365B" : "#553E82D8"

            Rectangle {
                anchors.fill: parent
                anchors.margins: Math.max(4, parent.width * 0.038)
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: "#304692E6"
            }

            Column {
                anchors.centerIn: parent
                width: parent.width * 0.92
                spacing: Math.max(1, parent.height * 0.018)

                Text {
                    width: parent.width
                    text: "CORE AVG"
                    color: "#DDE9FF"
                    font.pixelSize: Math.max(9, parent.parent.width * 0.082)
                    font.bold: true
                    font.letterSpacing: 1.25
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: root.valid
                          ? Math.round(root.temperatureFahrenheit) + "°F"
                          : "--"
                    color: "#FFFFFF"
                    font.pixelSize: Math.max(24, parent.parent.width * 0.285)
                    font.bold: true
                    font.letterSpacing: 0.6
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: root.valid
                          ? Math.round(root.temperatureCelsius) + "°C"
                          : ""
                    color: "#D3E4FF"
                    font.pixelSize: Math.max(11, parent.parent.width * 0.120)
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        id: statusPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(8, parent.height * 0.026)
        width: Math.max(82, Math.min(parent.width * 0.36, 142))
        height: Math.max(25, Math.min(parent.height * 0.072, 33))
        radius: height / 2
        color: "#D9081220"
        border.width: 1.2
        border.color: root.statusColor

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(root.statusColor.r,
                                  root.statusColor.g,
                                  root.statusColor.b,
                                  0.15)
        }

        Text {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            text: root.statusLabel
            color: root.statusColor
            font.pixelSize: Math.max(11, parent.height * 0.45)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
}
