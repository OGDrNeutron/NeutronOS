import QtQuick 2.15

Item {
    id: root

    property string text: ""
    property bool active: false
    property bool danger: false
    property bool warning: false

    property color activeColor: "#27FF9A"
    property color inactiveColor: "#77A9C8"
    property color dangerColor: "#FF3048"
    property color warningColor: "#FFD166"

    implicitWidth: label.implicitWidth + 34
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.danger ? "#2A0710" : root.warning ? "#251C05" : root.active ? "#06291C" : "#091626"
        border.width: 1
        border.color: root.danger ? root.dangerColor : root.warning ? root.warningColor : root.active ? root.activeColor : "#3A6D8A"
        opacity: 0.95
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.danger ? root.dangerColor : root.warning ? root.warningColor : root.active ? root.activeColor : root.inactiveColor
        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 1.2
    }
}
