import QtQuick 2.15

Rectangle {
    id: root
    property bool secure: true
    // NEUTRONOS_FILEMANAGER_HEADER_SECURITY_SCORE_V1
    property int securityScore: -1
    readonly property string protectionState: securityScore < 0 ? (secure ? "secure" : "attention") : securityScore >= 80 ? "secure" : securityScore >= 55 ? "weak" : "attention"
    readonly property color protectionColor: protectionState === "secure" ? "#42E69C" : protectionState === "weak" ? "#F7D85B" : "#FF4D63"
    readonly property color protectionFill: protectionState === "secure" ? "#0A241A" : protectionState === "weak" ? "#2A2410" : "#2A1015"
    readonly property string protectionText: protectionState === "secure" ? "SECURE" : protectionState === "weak" ? "WEAK" : "ATTENTION"
    property bool menuFocused: false
    signal menuRequested()

    color: "#030810F2"
    border.width: 0
    radius: 5

    // Edge treatment deliberately omits the top stroke so the header visually
    // grows out of the top edge, matching the footer's connection to the bottom.
    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: "#21303A" }
    Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: "#21303A" }
    Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: "#21303A" }

    Rectangle {
        id: statusPill
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: statusText.implicitWidth + 28
        height: 34
        radius: 17
        color: root.protectionFill
        border.width: 1
        border.color: root.protectionColor

        Text {
            id: statusText
            anchors.centerIn: parent
            text: root.protectionText
            color: root.protectionColor
            font.pixelSize: 18
            font.bold: true
            font.letterSpacing: 0.8
        }
    }

    Text {
        anchors.centerIn: parent
        text: "FILE MANAGER"
        color: "#33A7FF"
        font.pixelSize: 28
        font.bold: true
        font.letterSpacing: 1.6
    }

    Rectangle {
        id: menuAnchor
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 72
        height: 38
        radius: 19
        color: root.menuFocused ? "#0A241A" : "transparent"
        border.width: root.menuFocused ? 2 : 0
        border.color: "#42E69C"

        Row {
            anchors.centerIn: parent
            spacing: 10
            Repeater {
                model: ["#1AA7FF", "#6E63FF", "#E432FF"]
                Rectangle { width: 11; height: 11; radius: 6; color: modelData }
            }
        }
        MouseArea { anchors.fill: parent; onClicked: root.menuRequested() }
    }
}
