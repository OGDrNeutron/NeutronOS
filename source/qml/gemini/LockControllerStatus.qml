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
    readonly property bool dualSense:/dualsense|ps5|playstation 5/i.test(controllerName)
    Image {
        objectName:"GeminiLockControllerArtwork"
        x:10;y:16;width:84;height:52
        source:Qt.resolvedUrl("assets/Controller.png")
        fillMode:Image.PreserveAspectFit
        smooth:true;mipmap:true
    }
    Rectangle{x:100;y:22;width:1;height:40;color:"#284155"}
    Text{objectName:"GeminiLockControllerName";x:106;y:22;width:136;height:40;text:root.controllerName;elide:Text.ElideRight;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;color:"#f5f8ff";font.pixelSize:18;font.weight:Font.DemiBold}
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
