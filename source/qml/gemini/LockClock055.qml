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
    Rectangle {
        id:housing;objectName:"GeminiClockHousing";x:0;y:57;width:279;height:94.5;z:1
        radius:46;color:"#e4010812";border.width:2;border.color:root.focused?"#adf6ff":"#13799d"
        Rectangle{anchors.fill:parent;anchors.margins:5;radius:42;color:"transparent";border.width:1;border.color:"#28547c"}
        Rectangle{anchors.fill:parent;anchors.margins:9;radius:37;color:"transparent";border.width:1;border.color:"#142f4f"}
        Text{id:timeText;objectName:"GeminiLockLocalTime";x:36;y:10;text:root.localTime;color:"#f7fbff";font.pixelSize:43;font.weight:Font.DemiBold}
        Text{objectName:"GeminiLockMeridiem";x:timeText.x+timeText.width+7;y:34;text:root.localPeriod;color:"#00eaff";font.pixelSize:20;visible:!root.use24Hour}
        Text{objectName:"GeminiLockLocalDate";x:37;y:63;text:root.localDate;color:"#e8f0f7";font.pixelSize:14}
    }
    Item {
        id:planet;objectName:"GeminiClockPlanetInstrument";x:205;y:0;width:184;height:206;z:2
        TimezoneEarth{id:clockEarth;objectName:"GeminiLockClockEarth";anchors.centerIn:parent;width:180;height:180;quality:root.quality;animated:false;region:"Worldwide";latitude:root.selectedRegion.latitude;longitude:root.globeLongitudeTarget;spinAngle:root.earthAngle;astronomicalLighting:root.worldBackendAvailable;solarDirection:Qt.vector3d(root.solarData.x,root.solarData.y,root.solarData.z)}
    }
    Text {
        x:30;y:160;width:215;elide:Text.ElideRight;font.pixelSize:10;color:"#96cddd"
        text:root.settings&&root.settings.worldClockStatus?root.settings.worldClockStatus:root.focused?"X Explore · □ Local"+(root.isLocal?"":" · △ Set Local"):""
    }
    MouseArea{anchors.fill:parent;enabled:!root.interactionBlocked;onClicked:{root.focusRequested();root.nextRegion()}}
}
