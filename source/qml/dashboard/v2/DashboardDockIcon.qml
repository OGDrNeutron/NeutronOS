import QtQuick

Item {
    id:root
    property var appData:({})
    property bool selected:false
    property bool moving:false
    property bool sectionActive:true
    readonly property bool hovered:pointerHover.hovered
    signal activated()
    function iconSource() {
        var value=String(root.appData.iconSource||root.appData.icon||root.appData.poster||"")
        if(!value)return ""
        if(value.indexOf(":")>=0||value.indexOf("/")>=0)return value
        return Qt.resolvedUrl("../../../themes/Default/apps/icons/"+value+".png")
    }
    width:108;height:108
    scale:selected||hovered?1.11:1
    opacity:sectionActive||hovered?1.0:0.58
    Behavior on scale { NumberAnimation{duration:140;easing.type:Easing.OutCubic} }
    Behavior on opacity { NumberAnimation{duration:150;easing.type:Easing.OutCubic} }
    Rectangle { anchors.centerIn:parent;width:92;height:92;radius:46;color:selected?"#2514BDEB":"transparent"; border.width:selected?3:0;border.color:root.moving?"#FF52D2":"#55E9FF" }
    Image { anchors.centerIn:parent;width:84;height:84;source:root.iconSource();fillMode:Image.PreserveAspectFit;asynchronous:true;cache:true }
    Rectangle { visible:selected;anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;width:root.moving?48:22;height:4;radius:2;color:root.moving?"#FF52D2":"#18E6FF" }
    Text { visible:root.moving; anchors.horizontalCenter:parent.horizontalCenter; anchors.bottom:parent.bottom; anchors.bottomMargin:7; text:"MOVE"; color:"white"; font.pixelSize:10; font.bold:true }
    HoverHandler{id:pointerHover}
    TapHandler{onTapped:root.activated()}
}
