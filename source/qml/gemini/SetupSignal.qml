import QtQuick
Item {
    property int strength:0
    width:50;height:32
    Repeater{model:5
        Rectangle{required property int index;x:index*11;y:30-height;width:8;height:8+index*5;radius:1;color:parent.strength>index*20?"#08F764":"#12382A"}
    }
}
