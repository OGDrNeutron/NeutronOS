import QtQuick
import QtQuick.Shapes
Item {
    id:root
    property color accent:"#00baff"
    property color fill:"#df030b19"
    property real glow:.35
    property real corner:22
    default property alias content:body.data
    Shape {
        anchors.fill:parent
        preferredRendererType:Shape.CurveRenderer
        ShapePath {
            strokeColor:Qt.rgba(root.accent.r,root.accent.g,root.accent.b,root.glow);strokeWidth:6;fillColor:"transparent"
            startX:root.corner;startY:3
            PathLine{x:root.width-root.corner;y:3} PathLine{x:root.width-3;y:root.corner}
            PathLine{x:root.width-3;y:root.height-root.corner} PathLine{x:root.width-root.corner;y:root.height-3}
            PathLine{x:root.corner;y:root.height-3} PathLine{x:3;y:root.height-root.corner}
            PathLine{x:3;y:root.corner} PathLine{x:root.corner;y:3}
        }
        ShapePath {
            strokeColor:root.accent;strokeWidth:1.2;fillColor:root.fill
            startX:root.corner;startY:6
            PathLine{x:root.width-root.corner;y:6} PathLine{x:root.width-6;y:root.corner}
            PathLine{x:root.width-6;y:root.height-root.corner} PathLine{x:root.width-root.corner;y:root.height-6}
            PathLine{x:root.corner;y:root.height-6} PathLine{x:6;y:root.height-root.corner}
            PathLine{x:6;y:root.corner} PathLine{x:root.corner;y:6}
        }
    }
    Repeater {
        model:4
        Rectangle{required property int index;width:root.width*.09;height:3;x:index%2?root.width-width-root.corner:root.corner;y:index<2?3:root.height-6;color:root.accent}
    }
    Item{id:body;anchors.fill:parent}
}
