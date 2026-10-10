import QtQuick
import QtQuick.Shapes
Rectangle {
    id:root
    property var controller:null
    property bool active:false
    readonly property bool connected:!!controller&&controller.controllerConnected===true
    readonly property string controllerName:connected?String(controller.controllerName||"Connected controller"):"Controller disconnected"
    readonly property int battery:connected&&controller.controllerBatteryAvailable===true&&isFinite(Number(controller.controllerBatteryPercent))&&Number(controller.controllerBatteryPercent)>=0&&Number(controller.controllerBatteryPercent)<=100?Math.round(Number(controller.controllerBatteryPercent)):-1
    readonly property color batteryColor:battery<0?"#91a7bd":battery<=15?"#FF3157":battery<=35?"#F7D85B":"#20F58B"
    readonly property string connectionLabel:connection.connectionLabel
    radius:18;color:"#e0030b19";border.width:1;border.color:connected?"#397a91":"#304257"
    ControllerRegistrationSession{id:connection;active:root.active;registrationEnabled:false;controller:root.controller}
    Rectangle{x:20;y:18;width:48;height:40;radius:10;color:"#112033";border.color:root.connected?"#19E9FF":"#647588"
        Shape{anchors.centerIn:parent;width:38;height:28;preferredRendererType:Shape.CurveRenderer
            ShapePath{strokeColor:root.connected?"#a7eaff":"#91a7bd";strokeWidth:1.8;fillColor:"transparent";capStyle:ShapePath.RoundCap;joinStyle:ShapePath.RoundJoin
                PathSvg{path:"M 12 5 L 26 5 C 33 5 34 13 36 23 C 36 27 31 27 28 21 L 10 21 C 7 27 2 27 2 23 C 4 13 5 5 12 5 Z M 10 10 L 10 17 M 6.5 13.5 L 13.5 13.5 M 27 10 L 27 12 M 31 14 L 31 16"}
            }
        }
    }
    Column{x:84;y:17;width:338;spacing:5
        Text{objectName:"GeminiLockControllerName";width:parent.width;text:root.controllerName;elide:Text.ElideRight;color:"#f5f8ff";font.pixelSize:19;font.weight:Font.DemiBold}
        Row{spacing:7
            Rectangle{width:5;height:5;radius:2.5;anchors.verticalCenter:parent.verticalCenter;color:root.connected?"#19E9FF":"#91a7bd"}
            Text{objectName:"GeminiLockControllerTransport";text:root.connectionLabel;color:root.connected?"#a7deff":"#91a7bd";font.pixelSize:13}
        }
    }
    Rectangle{x:440;y:19;width:1;height:38;color:"#284155"}
    Rectangle{objectName:"GeminiLockControllerBatteryGraphic";x:463;y:28;width:40;height:22;radius:4;color:"transparent";border.width:1.5;border.color:root.batteryColor
        Rectangle{x:40;y:7;width:3;height:8;radius:1;color:root.batteryColor}
        Rectangle{x:4;y:4;width:root.battery<0?0:32*root.battery/100;height:14;radius:2;color:root.batteryColor}
        Text{anchors.centerIn:parent;text:"—";visible:root.battery<0;color:root.batteryColor;font.pixelSize:13}
    }
    Column{x:516;y:18;width:90;spacing:3
        Text{objectName:"GeminiLockControllerBattery";text:root.battery<0?"Unavailable":root.battery+"%";color:root.batteryColor;font.pixelSize:root.battery<0?12:18;font.weight:Font.DemiBold}
        Text{text:root.connected&&root.controller.controllerCharging===true?"Charging":"Battery";color:"#91a7bd";font.pixelSize:11}
    }
}
