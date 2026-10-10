import QtQuick
import QtQuick.Shapes
Item {
    id:icon
    property string kind:"folder"
    property color tint:"#79d6ff"
    implicitWidth:36;implicitHeight:32
    Shape {anchors.fill:parent;visible:icon.kind==="folder"
        ShapePath{strokeColor:icon.tint;strokeWidth:2;fillColor:"#15354b";startX:3;startY:7
            PathLine{x:13;y:7} PathLine{x:17;y:11} PathLine{x:33;y:11} PathLine{x:33;y:28} PathLine{x:3;y:28} PathLine{x:3;y:7}
        }
    }
    Shape {anchors.fill:parent;visible:icon.kind==="home"
        ShapePath{strokeColor:icon.tint;strokeWidth:2;fillColor:"#15354b";startX:3;startY:15
            PathLine{x:18;y:3} PathLine{x:33;y:15} PathMove{x:8;y:11} PathLine{x:8;y:29} PathLine{x:28;y:29} PathLine{x:28;y:11}
        }
    }
    Rectangle{x:3;y:5;width:30;height:24;radius:4;visible:icon.kind==="drive";color:"#15354b";border.color:icon.tint;border.width:2
        Rectangle{x:5;y:6;width:20;height:3;radius:1;color:icon.tint}
        Rectangle{x:22;y:17;width:3;height:3;radius:1.5;color:icon.tint}
    }
}
