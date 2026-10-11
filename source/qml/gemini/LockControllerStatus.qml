import QtQuick
import QtQuick.Shapes
GeminiFrame {
    id:root
    property var controller:null
    property bool active:false
    readonly property bool connected:!!controller&&controller.controllerConnected===true
    readonly property string controllerName:connected?String(controller.controllerName||"Connected controller"):"Controller disconnected"
    readonly property int battery:connected&&controller.controllerBatteryAvailable===true&&isFinite(Number(controller.controllerBatteryPercent))&&Number(controller.controllerBatteryPercent)>=0&&Number(controller.controllerBatteryPercent)<=100?Math.round(Number(controller.controllerBatteryPercent)):-1
    readonly property color batteryColor:battery<0?"#91a7bd":battery<=15?"#FF3157":battery<=35?"#F7D85B":"#20F58B"
    readonly property string connectionLabel:connection.connectionLabel
    corner:17;fill:"#e0030b19";accent:connected?"#118eb6":"#304257";glow:.25
    ControllerRegistrationSession{id:connection;active:root.active;registrationEnabled:false;controller:root.controller}
    Rectangle{x:16;y:19;width:70;height:48;radius:10;color:"#112033";border.color:root.connected?"#19E9FF":"#647588"
        Shape{anchors.centerIn:parent;width:55;height:40;scale:1.2;preferredRendererType:Shape.CurveRenderer
            ShapePath{strokeColor:root.connected?"#a7eaff":"#91a7bd";strokeWidth:1.8;fillColor:"transparent";capStyle:ShapePath.RoundCap;joinStyle:ShapePath.RoundJoin
                PathSvg{path:"M 12 5 L 26 5 C 33 5 34 13 36 23 C 36 27 31 27 28 21 L 10 21 C 7 27 2 27 2 23 C 4 13 5 5 12 5 Z M 10 10 L 10 17 M 6.5 13.5 L 13.5 13.5 M 27 10 L 27 12 M 31 14 L 31 16"}
            }
        }
    }
    Rectangle{x:100;y:22;width:1;height:40;color:"#284155"}
    Column{x:112;y:22;width:132;spacing:4
        Text{objectName:"GeminiLockControllerName";width:parent.width;text:root.controllerName;elide:Text.ElideRight;color:"#f5f8ff";font.pixelSize:18;font.weight:Font.DemiBold}
        Row{spacing:7
            Rectangle{width:5;height:5;radius:2.5;anchors.verticalCenter:parent.verticalCenter;color:root.connected?"#19E9FF":"#91a7bd"}
            Text{objectName:"GeminiLockControllerTransport";text:root.connectionLabel;color:root.connected?"#a7deff":"#91a7bd";font.pixelSize:13}
        }
    }
    Rectangle{x:248;y:22;width:1;height:40;color:"#284155"}
    Rectangle{objectName:"GeminiLockControllerBatteryGraphic";x:264;y:31;width:40;height:22;radius:4;color:"transparent";border.width:1.5;border.color:root.batteryColor
        Rectangle{x:40;y:7;width:3;height:8;radius:1;color:root.batteryColor}
        Rectangle{x:4;y:4;width:root.battery<0?0:32*root.battery/100;height:14;radius:2;color:root.batteryColor}
        Text{anchors.centerIn:parent;text:"—";visible:root.battery<0;color:root.batteryColor;font.pixelSize:13}
    }
    Column{x:322;y:28;width:58;spacing:3
        Text{objectName:"GeminiLockControllerBattery";text:root.battery<0?"Unavailable":root.battery+"%";color:root.batteryColor;font.pixelSize:root.battery<0?9:18;font.weight:Font.DemiBold}
        Text{text:root.connected&&root.controller.controllerCharging===true?"Charging":"";color:"#91a7bd";font.pixelSize:11}
    }
    Shape {
        objectName:"GeminiLockControllerTransportIcon"
        x:382;y:22;width:28;height:40
        visible:root.connected&&(root.connectionLabel==="Wired"||root.connectionLabel==="Bluetooth")
        preferredRendererType:Shape.CurveRenderer
        ShapePath {
            fillColor:"transparent";strokeWidth:2.6;capStyle:ShapePath.RoundCap;joinStyle:ShapePath.RoundJoin
            strokeColor:root.connectionLabel==="Wired"?"#ff1645":"#00ddff"
            PathSvg {path:root.connectionLabel==="Bluetooth"?"M 11 3 L 11 37 L 22 27 L 3 10 M 3 30 L 22 13 L 11 3":"M 13 34 L 13 4 M 9 9 L 13 3 L 17 9 M 13 28 C 3 28 4 23 4 15 M 1 15 L 7 15 M 13 23 C 23 23 23 19 23 12 M 20 10 L 26 10 L 26 15 L 20 15 Z"}
        }
    }
}
