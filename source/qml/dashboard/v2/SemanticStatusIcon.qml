import QtQuick

/*
    NEUTRONOS_SEMANTIC_HEADER_ICONS_V2
    Vector-only status glyphs. No emoji/font dependency is required for the
    System Overview header, so Clock/Wi-Fi/User/Security stay visually stable.
*/
Item {
    id: root
    property string kind: "locked"
    property color accent: kind === "unlocked" ? "#FF4059" : "#42E995"

    Canvas {
        id: glyphCanvas
        anchors.fill: parent
        antialiasing: true

        function circle(ctx, x, y, radius, fill) {
            ctx.beginPath()
            ctx.arc(x, y, radius, 0, Math.PI * 2)
            if (fill) ctx.fill(); else ctx.stroke()
        }

        function drawClock(ctx, variant) {
            var cx = width * .5
            var cy = height * .5
            var r = width * .36
            ctx.lineWidth = Math.max(2.2, width * .075)
            ctx.strokeStyle = root.accent
            ctx.fillStyle = root.accent

            if (variant === "clockDigital") {
                ctx.beginPath()
                ctx.roundedRect(width * .12, height * .25, width * .76, height * .5,
                               width * .12, width * .12)
                ctx.stroke()
                ctx.lineWidth = Math.max(1.8, width * .055)
                ctx.beginPath()
                ctx.moveTo(width * .27, height * .51); ctx.lineTo(width * .39, height * .51)
                ctx.moveTo(width * .61, height * .51); ctx.lineTo(width * .73, height * .51)
                ctx.stroke()
                circle(ctx, width * .5, height * .43, width * .025, true)
                circle(ctx, width * .5, height * .59, width * .025, true)
                return
            }

            if (variant === "clockRing") {
                circle(ctx, cx, cy, r, false)
                ctx.lineWidth = Math.max(1.6, width * .05)
                circle(ctx, cx, cy, r * .7, false)
                circle(ctx, cx, cy, width * .05, true)
                return
            }

            if (variant === "clockDot") {
                circle(ctx, cx, cy, r, false)
                for (var i = 0; i < 12; ++i) {
                    var a = (Math.PI * 2 * i / 12) - Math.PI / 2
                    circle(ctx,
                           cx + Math.cos(a) * r * .76,
                           cy + Math.sin(a) * r * .76,
                           width * .018,
                           true)
                }
                ctx.beginPath()
                ctx.moveTo(cx, cy)
                ctx.lineTo(cx, cy - r * .48)
                ctx.moveTo(cx, cy)
                ctx.lineTo(cx + r * .42, cy + r * .18)
                ctx.stroke()
                return
            }

            circle(ctx, cx, cy, r, false)
            if (variant !== "clockMinimal") {
                ctx.lineWidth = Math.max(1.4, width * .042)
                for (var j = 0; j < 4; ++j) {
                    var b = (Math.PI / 2 * j) - Math.PI / 2
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(b) * r * .72, cy + Math.sin(b) * r * .72)
                    ctx.lineTo(cx + Math.cos(b) * r * .9, cy + Math.sin(b) * r * .9)
                    ctx.stroke()
                }
            }
            ctx.lineWidth = Math.max(2.3, width * .075)
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(cx, cy - r * .48)
            ctx.moveTo(cx, cy)
            ctx.lineTo(cx + r * (variant === "clockMinimal" ? .48 : .38),
                       cy + r * (variant === "clockMinimal" ? .06 : .22))
            ctx.stroke()
            circle(ctx, cx, cy, width * .045, true)
        }

        function drawWifi(ctx) {
            var cx = width * .5
            var baseY = height * .72
            ctx.strokeStyle = root.accent
            ctx.fillStyle = root.accent
            ctx.lineCap = "round"
            ctx.lineWidth = Math.max(2.4, width * .08)
            var radii = [width * .34, width * .24, width * .14]
            for (var i = 0; i < radii.length; ++i) {
                var r = radii[i]
                ctx.beginPath()
                ctx.arc(cx, baseY, r, Math.PI * 1.22, Math.PI * 1.78)
                ctx.stroke()
            }
            circle(ctx, cx, baseY, width * .055, true)
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = root.accent
            ctx.fillStyle = root.accent
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.lineWidth = Math.max(2.4, width * .085)

            if (root.kind.indexOf("clock") === 0) {
                drawClock(ctx, root.kind)
                return
            }

            if (root.kind === "wifi") {
                drawWifi(ctx)
                return
            }

            if (root.kind === "user") {
                circle(ctx, width * .5, height * .31, width * .18, true)
                ctx.beginPath()
                ctx.moveTo(width * .18, height * .82)
                ctx.quadraticCurveTo(width * .22, height * .54, width * .5, height * .54)
                ctx.quadraticCurveTo(width * .78, height * .54, width * .82, height * .82)
                ctx.closePath()
                ctx.fill()
                return
            }

            // Compact shackle first, then draw the solid body over its lower legs.
            // "locked" is used for both green Secure and yellow Weak Protection;
            // "unlocked" is reserved for red Unsecure/Unavailable.
            ctx.beginPath()
            ctx.lineWidth = Math.max(1.35, width * .075)
            if (root.kind === "unlocked") {
                ctx.moveTo(width * .245, height * .385)
                ctx.lineTo(width * .245, height * .325)
                ctx.bezierCurveTo(width * .245, height * .16, width * .685, height * .16,
                                  width * .685, height * .33)
                ctx.lineTo(width * .685, height * .49)
            } else {
                ctx.moveTo(width * .34, height * .49)
                ctx.lineTo(width * .34, height * .345)
                ctx.bezierCurveTo(width * .34, height * .16, width * .66, height * .16,
                                  width * .66, height * .345)
                ctx.lineTo(width * .66, height * .49)
            }
            ctx.stroke()
            ctx.fillStyle = root.accent
            var bx = width * .18, by = height * .46, bw = width * .64, bh = height * .42
            ctx.beginPath()
            ctx.roundedRect(bx, by, bw, bh, Math.max(2, width * .075), Math.max(2, width * .075))
            ctx.fill()
            ctx.fillStyle = "#07101B"
            circle(ctx, width * .5, height * .65, width * .055, true)
            ctx.fillRect(width * .475, height * .65, width * .05, height * .12)
        }

        Connections {
            target: root
            function onKindChanged() { glyphCanvas.requestPaint() }
            function onAccentChanged() { glyphCanvas.requestPaint() }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
}
