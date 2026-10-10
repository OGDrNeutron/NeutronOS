import QtQuick
import QtQuick.Shapes

Item {
    id:signalIcon
    property color tint:"#ff4057"
    implicitWidth:28;implicitHeight:26
    Shape {
        anchors.fill:parent
        ShapePath {
            strokeColor:signalIcon.tint;strokeWidth:2.3;fillColor:"transparent";capStyle:ShapePath.RoundCap
            startX:2;startY:8
            PathQuad{x:26;y:8;controlX:14;controlY:-3}
            PathMove{x:6;y:12}
            PathQuad{x:22;y:12;controlX:14;controlY:4}
            PathMove{x:10;y:16}
            PathQuad{x:18;y:16;controlX:14;controlY:12}
        }
    }
    Rectangle{x:12;y:20;width:4;height:4;radius:2;color:signalIcon.tint}
}
