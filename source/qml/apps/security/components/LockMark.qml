import QtQuick 2.15

Item {
    id: root
    property color accent: "#42E69C"
    property bool filled: true

    Rectangle {
        id: shackle
        width: parent.width * 0.58
        height: parent.height * 0.48
        radius: width * 0.5
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.06
        color: "transparent"
        border.width: Math.max(2, Math.round(parent.width * 0.10))
        border.color: root.accent
    }

    Rectangle {
        width: parent.width * 0.78
        height: parent.height * 0.55
        radius: Math.max(3, parent.width * 0.12)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        color: root.filled ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : "transparent"
        border.width: Math.max(2, Math.round(parent.width * 0.08))
        border.color: root.accent

        Rectangle {
            width: Math.max(3, parent.width * 0.10)
            height: parent.height * 0.34
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent
        }
    }
}
