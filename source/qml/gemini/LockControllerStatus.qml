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
    Item {
        x:14;y:17;width:74;height:52
        Shape {
            anchors.fill:parent;preferredRendererType:Shape.CurveRenderer
            ShapePath {
                strokeColor:root.connected?"#6bd8f1":"#667c88";strokeWidth:1.3
                fillGradient:LinearGradient{x1:0;y1:8;x2:0;y2:52
                    GradientStop{position:0;color:root.dualSense?"#e2edf2":"#36586c"}
                    GradientStop{position:.5;color:root.dualSense?"#9db5c3":"#1d3547"}
                    GradientStop{position:1;color:"#152332"}
                }
                PathSvg{path:"M 17 8 C 24 5 48 5 55 8 C 61 11 68 36 66 46 C 64 54 57 52 49 40 L 23 40 C 15 52 8 54 6 46 C 4 36 11 11 17 8 Z"}
            }
            ShapePath{strokeColor:"#54798e";strokeWidth:1;fillColor:"#08121c"
                PathSvg{path:"M 21 11 C 28 8 44 8 51 11 L 49 28 L 54 40 L 47 40 L 41 36 L 31 36 L 25 40 L 18 40 L 23 28 Z"}
            }
        }
        Rectangle{x:25;y:10;width:23;height:15;radius:4;color:"#162c3a";border.width:.7;border.color:"#7a9ba8"}
        Rectangle{x:14;y:18;width:5;height:15;radius:1;color:"#0b1924"}
        Rectangle{x:9;y:23;width:15;height:5;radius:1;color:"#0b1924"}
        Repeater{model:2;delegate:Rectangle{required property int index;x:index===0?24:41;y:31;width:11;height:11;radius:5.5;color:"#040b12";border.width:1.1;border.color:"#46677b"
            Rectangle{anchors.centerIn:parent;width:6;height:6;radius:3;color:"#182d3e"}
        }}
        Repeater{model:4;delegate:Rectangle{required property int index;x:54+(index===1?5:index===3?-5:0);y:21+(index===2?5:index===0?-5:0);width:4;height:4;radius:2;color:["#58d3dc","#ef8299","#8aa4ed","#aebae0"][index]}}
        Rectangle{x:33;y:29;width:7;height:2;radius:1;color:"#5bcde6"}
    }
    Rectangle{x:100;y:22;width:1;height:40;color:"#284155"}
    Column{x:112;y:22;width:132;spacing:4
        Text{objectName:"GeminiLockControllerName";width:parent.width;text:root.controllerName;elide:Text.ElideRight;color:"#f5f8ff";font.pixelSize:18;font.weight:Font.DemiBold}

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
