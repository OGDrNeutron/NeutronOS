import QtQuick

Rectangle {
    id: root
    // NEUTRONOS_HEADER_STATUS_SELECTION_COLOR_V2
    property string icon: "●"
    property string iconKind: ""
    property string imageSource: ""
    property string primary: ""
    property string secondary: ""
    property color statusColor: "#19E9FF"
    property color selectionColor: "#00A8FF"
    property bool attention: false
    property bool selected: false
    signal activated()
    onAttentionChanged: if (!attention) opacity = 1
    radius: 12
    color: attention ? "#DD3A0710" : (selected ? "#B00A1C32" : "#A0070D19")
    border.width: attention ? 3 : (selected ? 2 : 1)
    border.color: attention ? "#FF263F" : (selected ? root.selectionColor : "#30415D72")
    Rectangle { anchors.fill:parent;anchors.margins:-7;radius:parent.radius+7;color:"transparent";border.width:root.attention?4:(root.selected?2:0);border.color:root.attention?"#AFFF2344":root.selectionColor;opacity:root.attention?1.0:0.40;visible:root.attention||root.selected;z:-1 }
    SequentialAnimation on opacity {
        running: root.attention
        loops: Animation.Infinite
        NumberAnimation { from:1;to:.62;duration:720;easing.type:Easing.InOutSine }
        NumberAnimation { from:.62;to:1;duration:720;easing.type:Easing.InOutSine }
    }
    Row { anchors.fill: parent; anchors.margins: 9; spacing: 9
        Rectangle { width: 36; height: 36; radius: 9; clip: true; color: root.attention?"#A8180710":"#080C17"; border.width: 1; border.color: root.attention?"#FF3850":"#263C5D"
            Text { anchors.centerIn: parent; visible:root.imageSource.length===0 && root.iconKind.length===0; text: root.icon; color: root.attention?"#FF6577":"white"; font.pixelSize: 18 }
            SemanticStatusIcon { anchors.centerIn:parent; width:25; height:25; visible:root.imageSource.length===0 && root.iconKind.length>0; kind:root.iconKind; accent:root.statusColor }
            Image { anchors.fill:parent; anchors.margins:2; visible:root.imageSource.length>0; source:root.imageSource; fillMode:Image.PreserveAspectCrop; smooth:true; mipmap:true; cache:true }
        }
        Column { anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Text { text: root.primary; color: root.attention?"#FFDFE4":"white"; font.pixelSize: 14 }
            Text { visible: text.length>0; text: root.secondary; color: root.statusColor; font.pixelSize: 11 }
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activated() }
}
