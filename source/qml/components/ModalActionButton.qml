import QtQuick

Rectangle {
    id: root
    property string glyph: "X"
    property string label: "Action"
    property color accent: "#35DFFF"
    property bool destructive: false
    property bool selected: false
    signal activated()
    implicitHeight: 64
    radius: 16
    color: selected ? Qt.rgba(accent.r,accent.g,accent.b,.20) : "#0A1828"
    border.width: selected ? 3 : 1
    border.color: destructive ? "#FF4963" : selected ? accent : "#304A62"
    scale: selected ? 1.025 : 1
    Behavior on scale { NumberAnimation { duration:130; easing.type:Easing.OutCubic } }
    Row { anchors.centerIn:parent; spacing:12
        Rectangle { width:34;height:34;radius:17;color:"#10243A";border.width:2;border.color:root.destructive?"#FF4963":root.accent
            Text { anchors.centerIn:parent;text:root.glyph;color:root.destructive?"#FF7184":root.accent;font.pixelSize:15;font.bold:true }
        }
        Text { anchors.verticalCenter:parent.verticalCenter;text:root.label;color:root.destructive?"#FF7184":"white";font.pixelSize:17;font.bold:true }
    }
    MouseArea { anchors.fill:parent;onClicked:root.activated() }
}
