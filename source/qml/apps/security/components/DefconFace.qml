import QtQuick 2.15

Item {
    id: root
    property int level: 5
    property color accent: "#42FF70"

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            ctx.clearRect(0, 0, w, h)
            var cx = w / 2
            var cy = h / 2
            var r = Math.min(w, h) * 0.39
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.strokeStyle = root.accent.toString()
            ctx.fillStyle = root.accent.toString()

            // outer polished face ring
            ctx.lineWidth = Math.max(4, r * 0.085)
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.stroke()

            // subtle inner ring
            ctx.globalAlpha = 0.24
            ctx.lineWidth = Math.max(1, r * 0.025)
            ctx.beginPath()
            ctx.arc(cx, cy, r * 0.82, 0, Math.PI * 2)
            ctx.stroke()
            ctx.globalAlpha = 1.0

            // eyes
            var eyeY = cy - r * 0.23
            var eyeDX = r * 0.34
            if (root.level === 1) {
                ctx.lineWidth = Math.max(4, r * 0.07)
                ctx.beginPath()
                ctx.moveTo(cx-eyeDX-r*0.10, eyeY-r*0.07)
                ctx.lineTo(cx-eyeDX+r*0.10, eyeY+r*0.05)
                ctx.moveTo(cx+eyeDX-r*0.10, eyeY+r*0.05)
                ctx.lineTo(cx+eyeDX+r*0.10, eyeY-r*0.07)
                ctx.stroke()
            } else {
                ctx.beginPath()
                ctx.arc(cx-eyeDX, eyeY, Math.max(4, r*0.065), 0, Math.PI*2)
                ctx.arc(cx+eyeDX, eyeY, Math.max(4, r*0.065), 0, Math.PI*2)
                ctx.fill()
            }

            // mouth: 5 full smile, 4 mild smile, 3 neutral, 2 frown, 1 angry frown
            ctx.lineWidth = Math.max(5, r * 0.075)
            ctx.beginPath()
            if (root.level >= 5) {
                ctx.arc(cx, cy + r*0.02, r*0.45, 0.18*Math.PI, 0.82*Math.PI, false)
            } else if (root.level === 4) {
                ctx.arc(cx, cy + r*0.12, r*0.38, 0.20*Math.PI, 0.80*Math.PI, false)
            } else if (root.level === 3) {
                ctx.moveTo(cx-r*0.34, cy+r*0.30)
                ctx.lineTo(cx+r*0.34, cy+r*0.30)
            } else if (root.level === 2) {
                ctx.arc(cx, cy + r*0.58, r*0.39, 1.18*Math.PI, 1.82*Math.PI, false)
            } else {
                ctx.arc(cx, cy + r*0.62, r*0.43, 1.16*Math.PI, 1.84*Math.PI, false)
            }
            ctx.stroke()
        }
        Connections {
            target: root
            function onLevelChanged() { canvas.requestPaint() }
            function onAccentChanged() { canvas.requestPaint() }
        }
        Component.onCompleted: requestPaint()
    }
}
