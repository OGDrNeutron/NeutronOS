import QtQuick
import QtQuick.Effects
Rectangle {
    id:root
    property string text:""
    property bool selected:false
    property bool chevron:true
    property string iconKind:""
    property int textSize:25
    property bool strongText:true
    property color focusColor:"#26FF64"
    property color selectedFill:"#010D05"
    property color idleFill:"#071023"
    property bool idleBorder:true
    property string chevronText:"⌄"
    signal activated()
    radius:13
    color:selected?root.selectedFill:root.idleFill
    border.color:selected?root.focusColor:"#305C86";border.width:selected?2:root.idleBorder?1:0
    layer.enabled:selected
    layer.effect:MultiEffect {shadowEnabled:true;shadowColor:root.focusColor;shadowOpacity:0.65;shadowBlur:0.55;shadowHorizontalOffset:0;shadowVerticalOffset:0}
    SetupGlyph{x:25;anchors.verticalCenter:parent.verticalCenter;width:34;height:34;visible:root.iconKind.length>0;kind:root.iconKind;color:root.selected?"#77D8FF":"#C9DFFD"}
    Text {x:root.iconKind.length?94:22;anchors.verticalCenter:parent.verticalCenter;width:parent.width-x-52;text:root.text;color:"white";font.family:"Montserrat";font.pixelSize:root.textSize;font.weight:root.strongText?Font.Bold:Font.Normal;elide:Text.ElideRight}
    Text {visible:root.chevron;anchors.right:parent.right;anchors.rightMargin:22;anchors.verticalCenter:parent.verticalCenter;text:root.chevronText;color:root.selected?"#25FF65":"#9BBFE0";font.family:"Montserrat";font.pixelSize:25}
    Rectangle {anchors.fill:parent;anchors.margins:-4;z:-1;visible:root.selected;color:"transparent";radius:parent.radius+4;border.width:5;border.color:root.focusColor;opacity:.17}
    Rectangle {anchors.fill:parent;anchors.margins:-10;z:-2;visible:root.selected;color:"transparent";radius:parent.radius+10;border.width:9;border.color:root.focusColor;opacity:.055}
    MouseArea {anchors.fill:parent;onClicked:root.activated()}
}
