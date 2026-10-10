import QtQuick

Rectangle {
    id: root
    property string symbol: "●"
    property bool selected: false
    property int badge: 0
    signal activated()
    width: 52; height: 52; radius: 26; color: selected ? "#17152D" : "transparent"
    border.width: 1; border.color: selected ? "#E42BFF" : "#314D6C"
    Text { anchors.centerIn: parent; text: root.symbol; color: root.selected ? "#F14AFF" : "#23CFFF"; font.pixelSize: 25 }
    Rectangle { visible: root.badge>0; width: 12; height: 12; radius: 6; color: "#FF294B"; anchors.right: parent.right; anchors.top: parent.top; border.width: 2; border.color: "#030611" }
    MouseArea { anchors.fill: parent; onClicked: root.activated() }
}
