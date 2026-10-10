import QtQuick
Item {
    id: root
    property url referenceUrl
    property int percent: 0
    property real phase: 0
    property bool recovery: false
    readonly property bool loaded: background.status === Image.Ready
    readonly property real artworkScale: Math.min(width / 3840, height / 2160)
    readonly property real artworkX: (width - 3840 * artworkScale) / 2
    readonly property real artworkY: (height - 2160 * artworkScale) / 2
    // Measured bottom of the reference tagline is y=1338 of 2160.
    readonly property real progressCenter: (artworkY + 1338 * artworkScale + height) / 2
    Rectangle { anchors.fill: parent; color: "black" }
    Image {
        id: background
        anchors.fill: parent
        source: root.referenceUrl
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        cache: false
        smooth: true
    }
    Repeater {
        model: 3
        delegate: Item {
            required property int index
            readonly property real angle: root.phase * Math.PI * 2 + index * Math.PI * 2 / 3
            readonly property real tilt: (index === 0 ? -20 : index === 1 ? 62 : 105) * Math.PI / 180
            readonly property real a: (index === 0 ? 375 : 345) * Math.cos(angle)
            readonly property real b: 103 * Math.sin(angle)
            x: root.artworkX + (1934 + a * Math.cos(tilt) - b * Math.sin(tilt)) * root.artworkScale
            y: root.artworkY + (670 + a * Math.sin(tilt) + b * Math.cos(tilt)) * root.artworkScale
            // Tiny additive glow layers only; all reference pixels remain static.
            Repeater {
                model: 4
                delegate: Rectangle {
                    required property int index
                    width: (28 - index * 6) * root.artworkScale
                    height: width
                    x: -width / 2; y: -height / 2
                    radius: width / 2
                    color: index === 3 ? "#e8fbff" : "#56d9ff"
                    opacity: index === 3 ? 1 : 0.16
                }
            }
        }
    }
    Rectangle {
        x: (root.width - width) / 2
        y: root.progressCenter - 36 * root.artworkScale
        width: 860 * root.artworkScale
        height: 10 * root.artworkScale
        radius: height / 2
        color: "#40232b"
        Rectangle {
            width: parent.width * root.percent / 100
            height: parent.height
            radius: height / 2
            color: "#e91d32"
        }
    }
    Text {
        x: 0; y: root.progressCenter - 10 * root.artworkScale
        width: root.width; height: 46 * root.artworkScale
        text: root.recovery ? "RECOVERY MODE ENABLED" : root.percent + "%"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: "DejaVu Sans"
        font.pixelSize: Math.max(1, Math.round(34 * root.artworkScale))
        color: "#f4f6ff"
    }
}
