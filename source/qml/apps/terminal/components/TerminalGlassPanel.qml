import QtQuick 2.15

Item {
    id: root

    property real radius: 28
    property real padding: 18
    property bool focused: false
    property bool danger: false
    property bool success: false
    property bool strong: false
    property real surfaceOpacity: 1.0
    property color accentColor: "#68D8FF"

    property color panelColor: strong ? "#152237DD" : "#0A1424C8"
    property color borderColor: danger ? "#FF3048" : success ? "#27FF9A" : focused ? root.accentColor : "#3A6D8AAA"
    property color glowColor: danger ? "#FF3048" : success ? "#27FF9A" : root.accentColor

    default property alias content: contentItem.data

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.panelColor
        border.width: root.focused ? 2 : 1
        border.color: root.borderColor
        opacity: 0.98 * Math.max(0.55, Math.min(1.0, root.surfaceOpacity))
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: root.focused ? 2 : 0
        border.color: root.glowColor
        opacity: root.focused ? 0.42 : 0.0
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.radius * 0.72
        anchors.rightMargin: root.radius * 0.72
        height: 1
        color: "#FFFFFF"
        opacity: root.strong ? 0.20 : 0.12
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
