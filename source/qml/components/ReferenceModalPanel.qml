import QtQuick 2.15

Rectangle {
    id: root
    property color accentColor: "#49C8FF"
    radius: 30
    color: "#F20A1725"
    border.width: 2
    border.color: accentColor

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Math.max(0, parent.radius - 2)
        color: "transparent"
        border.width: 1
        border.color: "#16FFFFFF"
    }
}
