import QtQuick
Item {
    id: panel
    property bool illuminated: false
    property color fill: "#e808111e"
    property real radius: 14
    Rectangle { anchors.fill: parent; radius: panel.radius; color: panel.fill; border.color: panel.illuminated ? "#87e4ff" : "#234259"; border.width: panel.illuminated ? 2 : 1 }
}
