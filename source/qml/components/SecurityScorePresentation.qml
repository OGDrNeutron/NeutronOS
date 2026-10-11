import QtQuick 2.15
import "SecurityIndicator.js" as SecurityIndicator

Item {
    id: root

    property var backend: null
    property real uiScale: 1.0
    property real labelPixelSize: 24
    property real barHeight: 10

    readonly property int score: SecurityIndicator.score(backend)
    readonly property string strength: SecurityIndicator.label(backend)
    readonly property color statusColor: score < 0 ? "#FF3048"
                                                    : score >= 80 ? "#22FF88"
                                                    : score >= 55 ? "#F7D85B"
                                                    : "#FF3048"
    readonly property string presentationText: score < 0 ? strength
                                                          : strength + " " + String(score) + "%"

    Text {
        id: scoreLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        text: root.presentationText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.statusColor
        font.pixelSize: root.labelPixelSize * root.uiScale
        font.bold: true
    }

    Rectangle {
        id: scoreTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.barHeight * root.uiScale
        radius: height / 2
        color: "#26384A"
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.score < 0 ? 0 : parent.width * root.score / 100
            radius: parent.radius
            color: root.statusColor
        }
    }
}
