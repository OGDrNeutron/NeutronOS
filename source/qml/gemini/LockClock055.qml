import QtQuick
import QtQuick.Shapes
Item {
    id:root
    objectName:"GeminiLockClock"
    property bool animated:true
    property bool focused:false
    property bool interactionBlocked:false
    signal focusRequested()
    signal authenticationRequested()
    property string selectedTimezone:""
    readonly property bool worldBackendAvailable:settings&&typeof settings.worldClockDisplay==="function"
    readonly property string systemTimezone:settings&&settings.timezone?settings.timezone:"UTC"
    readonly property string displayedTimezone:selectedTimezone.length?selectedTimezone:systemTimezone
    readonly property bool isLocal:displayedTimezone===systemTimezone
    readonly property var selectedRegion:worldBackendAvailable?settings.worldClockRegion(displayedTimezone):({latitude:18,longitude:90,label:"Local"})
    readonly property var regionalDisplay:{var format=use24Hour;return worldBackendAvailable?settings.worldClockDisplay(displayedTimezone,now):({})}
    readonly property var solarData:worldBackendAvailable?settings.solarPosition(now):({x:1,y:0,z:0})
    function nextRegion(){
        if(interactionBlocked||!worldBackendAvailable)return
        var regions=settings.worldClockRegions;if(!regions.length)return
        var index=-1;for(var i=0;i<regions.length;i++)if(regions[i].timezone===displayedTimezone){index=i;break}
        selectedTimezone=regions[(index+1)%regions.length].timezone
    }
    function returnToLocal(){
        if(interactionBlocked)return
        if(settings&&typeof settings.cancelLockscreenTimezoneRequest==="function")settings.cancelLockscreenTimezoneRequest()
        selectedTimezone=""
    }
    function requestLocalTimezone(){
        if(interactionBlocked||isLocal||!worldBackendAvailable)return false
        if(settings.requestLockscreenTimezone(displayedTimezone)){authenticationRequested();return true}
        return false
    }
    property var quality:null
    property var settings:typeof clockSettingsManager!=="undefined"?clockSettingsManager:null
    property date now:new Date()
    property real earthAngle:0
    property real orientationPhase:0
    property real globeLongitudeTarget:0
    function orientToRegion(){
        orientationPhase=earthAngle
        var desired=Number(selectedRegion.longitude)+orientationPhase
        while(desired-clockEarth.longitude>180)desired-=360
        while(desired-clockEarth.longitude< -180)desired+=360
        globeLongitudeTarget=desired
    }
    onSelectedRegionChanged:Qt.callLater(orientToRegion)
    Component.onCompleted:orientToRegion()
    readonly property bool use24Hour:settings?settings.use24Hour:false
    readonly property int earthRotationPeriodMs:60000
    readonly property string localPeriod:worldBackendAvailable?String(regionalDisplay.period||""):use24Hour?"":Qt.formatDateTime(now,"AP")
    readonly property string localTime:worldBackendAvailable?String(regionalDisplay.time||"--:--"):use24Hour?Qt.formatDateTime(now,"HH:mm"):Qt.formatDateTime(now,"h:mm AP").slice(0,-localPeriod.length-1)
    readonly property string localDate:worldBackendAvailable?String(regionalDisplay.date||""):Qt.formatDateTime(now,"ddd, MMM d, yyyy")
    Timer{interval:1000;repeat:true;running:root.visible;onTriggered:root.now=new Date()}
    NumberAnimation on earthAngle{from:0;to:360;duration:root.earthRotationPeriodMs;loops:Animation.Infinite;running:root.visible&&root.animated;easing.type:Easing.Linear}
    Item {
        id:housing;objectName:"GeminiClockHousing";x:12;y:20;width:279;height:94.5;z:1
        Item{width:372;height:126;scale:0.75;transformOrigin:Item.TopLeft
        Shape {
            anchors.fill:parent;preferredRendererType:Shape.CurveRenderer
            ShapePath {
                strokeColor:"#02050b";strokeWidth:9;fillColor:"#be01030a";startX:34;startY:8
                PathLine{x:340;y:8} PathLine{x:372;y:36} PathLine{x:372;y:101} PathLine{x:341;y:132}
                PathLine{x:34;y:132} PathLine{x:2;y:103} PathLine{x:2;y:37} PathLine{x:34;y:8}
            }
            ShapePath {
                strokeColor:"#536b80";strokeWidth:1;startX:31;startY:0
                fillGradient:LinearGradient{x1:0;y1:0;x2:0;y2:126
                    GradientStop{position:0;color:"#a3b4c4"} GradientStop{position:.07;color:"#2c3b4c"}
                    GradientStop{position:.38;color:"#536577"} GradientStop{position:.51;color:"#111b28"}
                    GradientStop{position:.89;color:"#253849"} GradientStop{position:1;color:"#a1afbd"}
                }
                PathLine{x:338;y:0} PathLine{x:369;y:28} PathLine{x:369;y:97} PathLine{x:338;y:126}
                PathLine{x:31;y:126} PathLine{x:0;y:97} PathLine{x:0;y:28} PathLine{x:31;y:0}
            }
            ShapePath {
                strokeColor:"#030810";strokeWidth:3;startX:35;startY:9
                fillGradient:LinearGradient{x1:0;y1:0;x2:0;y2:116
                    GradientStop{position:0;color:"#0b1320"} GradientStop{position:.5;color:"#263443"} GradientStop{position:1;color:"#060b13"}
                }
                PathLine{x:333;y:9} PathLine{x:358;y:32} PathLine{x:358;y:93} PathLine{x:333;y:116}
                PathLine{x:35;y:116} PathLine{x:11;y:93} PathLine{x:11;y:32} PathLine{x:35;y:9}
            }
            ShapePath {
                strokeColor:"#617386";strokeWidth:1;startX:41;startY:17
                fillGradient:LinearGradient{x1:0;y1:17;x2:0;y2:108
                    GradientStop{position:0;color:"#101b2b"} GradientStop{position:.35;color:"#030812"} GradientStop{position:1;color:"#050911"}
                }
                PathLine{x:328;y:17} PathLine{x:347;y:36} PathLine{x:347;y:89} PathLine{x:328;y:108}
                PathLine{x:41;y:108} PathLine{x:22;y:89} PathLine{x:22;y:36} PathLine{x:41;y:17}
            }
            ShapePath{strokeColor:"#0b5278";strokeWidth:5;fillColor:"transparent";startX:40;startY:6;PathLine{x:327;y:6} PathLine{x:349;y:26}}
            ShapePath{strokeColor:"#5fe6ff";strokeWidth:1.5;fillColor:"transparent";startX:40;startY:6;PathLine{x:327;y:6} PathLine{x:349;y:26}}
            ShapePath{strokeColor:"#146b9c";strokeWidth:4;fillColor:"transparent";startX:82;startY:121;PathLine{x:327;y:121} PathLine{x:348;y:101}}
            ShapePath{strokeColor:"#50baff";strokeWidth:1.2;fillColor:"transparent";startX:82;startY:121;PathLine{x:327;y:121} PathLine{x:348;y:101}}
            ShapePath{strokeColor:"#650d24";strokeWidth:6;fillColor:"transparent";startX:8;startY:92;PathLine{x:33;y:119} PathLine{x:75;y:119}}
            ShapePath{strokeColor:"#ff3357";strokeWidth:2;fillColor:"transparent";startX:8;startY:92;PathLine{x:33;y:119} PathLine{x:75;y:119}}
            ShapePath{strokeColor:"#ff3758";strokeWidth:2;fillColor:"transparent";startX:303;startY:3;PathLine{x:348;y:3}}
        }
        Shape {
            anchors.fill:parent;visible:root.focused;preferredRendererType:Shape.CurveRenderer
            ShapePath{strokeColor:"#a0edff";strokeWidth:1.2;fillColor:"transparent";startX:35;startY:13;PathLine{x:16;y:32} PathLine{x:16;y:92} PathLine{x:35;y:112}}
        }
        Repeater{model:13;Rectangle{required property int index;x:56+index*20;y:index%2?111:12;width:13;height:1;color:index%3?"#607286":"#213348";opacity:.5}}
        Repeater {
            model:4
            Rectangle{required property int index;x:index%2?339:29;y:index<2?22:98;width:5;height:5;radius:2.5
                gradient:Gradient{GradientStop{position:0;color:"#99aab9"} GradientStop{position:.6;color:"#172537"} GradientStop{position:1;color:"#788da0"}}
                Rectangle{x:1;y:2;width:3;height:1;color:"#02050c"}
            }
        }
        Text{x:32;y:20;width:205;elide:Text.ElideRight;text:(root.isLocal?"LOCAL · ":"WORLD · ")+String(root.selectedRegion.label).toUpperCase();font.pixelSize:7;font.letterSpacing:2;color:"#7fa0b5"}
        Row{x:244;y:24;spacing:4;Repeater{model:4;Rectangle{required property int index;width:3;height:3;radius:1;color:index===2?"#ff3056":index===0?"#f2fcff":"#27658a"}}}
        Text{id:timeText;objectName:"GeminiLockLocalTime";x:30;y:27;text:root.localTime;color:"#f7fbff";font.pixelSize:57;font.weight:Font.DemiBold;style:Text.Raised;styleColor:"#607c99"}
        Text{objectName:"GeminiLockMeridiem";x:timeText.x+timeText.width+10;y:51;text:root.localPeriod;color:"#00caff";font.pixelSize:28;visible:!root.use24Hour}
        Text{objectName:"GeminiLockLocalDate";x:32;y:91;text:root.localDate;color:"#dce8f5";font.pixelSize:18}
    }
    }
    Item {
        id:planet;objectName:"GeminiClockPlanetInstrument";x:244;y:0;width:170;height:170;z:2
        TimezoneEarth{id:clockEarth;objectName:"GeminiLockClockEarth";anchors.centerIn:parent;width:180;height:180;quality:root.quality;animated:false;region:"Worldwide";latitude:root.selectedRegion.latitude;longitude:root.globeLongitudeTarget;spinAngle:root.earthAngle;astronomicalLighting:root.worldBackendAvailable;solarDirection:Qt.vector3d(root.solarData.x,root.solarData.y,root.solarData.z)}
    }
    Text {
        x:30;y:128;width:215;elide:Text.ElideRight;font.pixelSize:10;color:"#96cddd"
        text:root.settings&&root.settings.worldClockStatus?root.settings.worldClockStatus:root.focused?"X Explore · □ Local"+(root.isLocal?"":" · △ Set Local"):""
    }
    MouseArea{anchors.fill:parent;enabled:!root.interactionBlocked;onClicked:{root.focusRequested();root.nextRegion()}}
}
