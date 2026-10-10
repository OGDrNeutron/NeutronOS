import QtQuick
import QtQuick.Effects
Rectangle {
    id:root
    property string text:"CONTINUE"
    property string hint:"PRESS"
    property bool selected:true
    property bool chevron:true
    signal activated()
    width:450;height:88;radius:24
    color:"#010C03";border.width:2;border.color:selected?"#9BFFAD":"#286737"
    layer.enabled:selected
    layer.effect:MultiEffect {shadowEnabled:true;shadowColor:"#27FF37";shadowOpacity:1;shadowBlur:0.85;shadowHorizontalOffset:0;shadowVerticalOffset:0}
    gradient:Gradient {GradientStop{position:0;color:"#061D03"}GradientStop{position:0.5;color:"#020B02"}GradientStop{position:1;color:"#001900"}}
    Text {anchors.horizontalCenter:parent.horizontalCenter;y:root.hint.length?Math.max(5,(root.height-64)/2):(root.height-height)/2;text:root.text;color:"#9AFFA5";font.family:"Montserrat";font.pixelSize:29;font.weight:Font.Bold}
    Row {visible:root.hint.length>0;anchors.horizontalCenter:parent.horizontalCenter;y:root.height-32;spacing:7
        Text{text:root.hint+" X";color:"#18FF59";font.family:"Montserrat";font.pixelSize:19;font.weight:Font.Bold}
    }
    Text {visible:root.chevron;x:parent.width-56;y:13;text:"›";color:"#B4FFAE";font.family:"Montserrat";font.pixelSize:51}
    Rectangle {anchors.fill:parent;anchors.margins:-4;z:-1;visible:root.selected;color:"transparent";radius:parent.radius+4;border.width:5;border.color:root.selected?"#13FF30":"transparent";opacity:.17}
    Rectangle {anchors.fill:parent;anchors.margins:-10;z:-2;visible:root.selected;color:"transparent";radius:parent.radius+10;border.width:9;border.color:root.selected?"#13FF30":"transparent";opacity:.055}
    MouseArea {anchors.fill:parent;onClicked:root.activated()}
}
