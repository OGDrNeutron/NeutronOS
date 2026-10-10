import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
Item {
    id:root
    property var quality:null
    layer.enabled:!quality||quality.bloom
    layer.effect:MultiEffect {shadowEnabled:true;shadowColor:"#009CFF";shadowOpacity:.9;shadowBlur:.8;shadowHorizontalOffset:0;shadowVerticalOffset:0}
    Repeater {
        model:7
        Shape {
            required property int index
            anchors.fill:parent
            ShapePath {
                strokeColor:index%3===0?"#44FF1248":index%2?"#90239AFF":"#48136DCF"
                strokeWidth:index%3===0?2:3
                fillColor:"transparent"
                capStyle:ShapePath.RoundCap
                PathAngleArc {centerX:root.width/2;centerY:root.height/2;radiusX:root.width/2-8-index*12;radiusY:root.height/2-8-index*10;startAngle:index*47-115;sweepAngle:150+index*18}
            }
        }
    }
    Repeater {
        model:root.quality&&root.quality.level===0?20:56
        Rectangle {
            required property int index
            readonly property real angle:index*2.399963
            readonly property real distance:.38+.12*Math.sin(index*7.31)
            x:root.width*(.5+Math.cos(angle)*distance)
            y:root.height*(.5+Math.sin(angle)*distance)
            width:index%7===0?4:2;height:width;radius:width/2
            color:index%4===0?"#BCFF164D":"#AE168CFF"
        }
    }
}
