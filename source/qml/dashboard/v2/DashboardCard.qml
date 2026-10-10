import QtQuick

Rectangle {
    id: root
    property string title: ""
    property string menuText: "•••"
    property bool showHeading: true
    property bool selected: false
    property color accent: theme.cyan
    property alias contentItem: body
    property bool transparentShell: false
    signal clicked()

    DashboardTheme { id: theme }
    radius: theme.radius
    color: transparentShell ? "transparent" : (selected ? "#F00A1C34" : theme.card)
    border.width: transparentShell ? 0 : (selected ? 5 : 1)
    border.color: selected ? accent : theme.border
    scale: selected ? 1.035 : 1.0
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 140 } }

    Rectangle {
        id: focusGlow
        anchors.fill: parent
        anchors.margins: -13
        radius: root.radius + 13
        visible: root.selected && !root.transparentShell
        color: "transparent"
        border.width: 4
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .44)
        opacity: .95
        z: -1
    }
    Rectangle {
        id: focusCornerAccent
        width: 18; height: 18; radius: 5
        anchors.left: parent.left; anchors.top: parent.top
        anchors.leftMargin: 10; anchors.topMargin: 10
        visible: root.selected && !root.transparentShell
        color: root.accent
        opacity: .9
    }

    Rectangle {
        anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1
        color: "transparent"; border.width: root.transparentShell ? 0 : (root.selected ? 1 : 0)
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .28)
    }
    Text {
        id: heading; anchors.left: parent.left; anchors.top: parent.top
        anchors.leftMargin: 18; anchors.topMargin: 14
        visible: root.showHeading
        text: root.title; color: theme.text; font.pixelSize: 18; font.weight: Font.Medium
    }
    Text {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.rightMargin: 16; anchors.topMargin: 9
        text: root.menuText; color: theme.muted; font.pixelSize: 17; font.letterSpacing: 2
    }
    Item {
        id: body; anchors.left: parent.left; anchors.right: parent.right
        anchors.top: root.showHeading ? heading.bottom : parent.top; anchors.bottom: parent.bottom
        anchors.margins: 15; anchors.topMargin: root.showHeading ? 8 : 15
        clip: true
    }
    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
