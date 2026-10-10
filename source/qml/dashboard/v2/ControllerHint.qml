import QtQuick

Row {
    id: root
    property string family: "generic"
    property string action: "primary"
    property string glyph: "A"
    property string label: "Select"
    property color accent: "#19E9FF"
    readonly property bool playStationSymbol: family === "playstation" && (glyph === "△" || glyph === "□" || glyph === "○" || glyph === "×")
    spacing: 9

    Rectangle {
        id: badge
        width: 42
        height: 42
        radius: root.family === "nintendo" ? 13 : 21
        color: "#07101F"
        border.width: 1.5
        border.color: root.accent

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: root.family === "nintendo" ? 9 : width / 2
            color: "transparent"
            border.width: root.family === "xbox" || root.family === "nintendo" ? 1 : 0
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.38)
        }

        Text {
            anchors.centerIn: parent
            visible: !root.playStationSymbol
            text: root.glyph
            color: root.accent
            font.pixelSize: 19
            font.bold: true
            font.letterSpacing: 0.4
        }

        Canvas {
            id: symbolCanvas
            anchors.centerIn: parent
            width: 22
            height: 22
            visible: root.playStationSymbol
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = root.accent
                ctx.lineWidth = 2.2
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                var pad = 2.3
                if (root.glyph === "△") {
                    ctx.beginPath()
                    ctx.moveTo(width / 2, pad)
                    ctx.lineTo(width - pad, height - pad)
                    ctx.lineTo(pad, height - pad)
                    ctx.closePath()
                    ctx.stroke()
                } else if (root.glyph === "□") {
                    ctx.strokeRect(pad + 0.8, pad + 0.8, width - (pad + 0.8) * 2, height - (pad + 0.8) * 2)
                } else if (root.glyph === "○") {
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, width / 2 - pad, 0, Math.PI * 2)
                    ctx.stroke()
                } else if (root.glyph === "×") {
                    ctx.beginPath()
                    ctx.moveTo(pad + 0.8, pad + 0.8)
                    ctx.lineTo(width - pad - 0.8, height - pad - 0.8)
                    ctx.moveTo(width - pad - 0.8, pad + 0.8)
                    ctx.lineTo(pad + 0.8, height - pad - 0.8)
                    ctx.stroke()
                }
            }

            Connections {
                target: root
                function onAccentChanged() { symbolCanvas.requestPaint() }
                function onGlyphChanged() { symbolCanvas.requestPaint() }
                function onFamilyChanged() { symbolCanvas.requestPaint() }
            }
            Component.onCompleted: requestPaint()
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: "#F5F8FF"
        font.pixelSize: 15
        font.weight: Font.DemiBold
    }
}
