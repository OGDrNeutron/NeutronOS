import "../components/SecurityIndicator.js" as SecurityIndicator
import "../dashboard/v2" as Dashboard
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
Item {
    id:root
    objectName:"GeminiLockPresentation"
    property var host
    property var clockBackend:typeof clockSettingsManager!=="undefined"?clockSettingsManager:null
    readonly property bool detailsVisible:!clockBackend||clockBackend.lockscreenDetailsVisible!==false
    readonly property bool clockVisible:detailsVisible&&(!clockBackend||clockBackend.lockscreenClockVisible!==false)
    readonly property var securityBackend:root.host && "loginSecurityBackend" in root.host ? root.host.loginSecurityBackend : null
    readonly property color securityColor:SecurityIndicator.color(securityBackend)
    function handleClockAction(action){
        if(!clockVisible||root.host.cardArmed)return false
        if(action==="primary")worldClock.nextRegion()
        else if(action==="secondary")worldClock.returnToLocal()
        else if(action==="context")worldClock.requestLocalTimezone()
        return true
    }
    property real errorStrength:0
    readonly property string feedback:host.loginSuccess?"success":errorStrength>0||host.isLockedOut()?"error":"neutral"
    function errorFeedback(){errorPulse.restart()}
    SequentialAnimation {
        id:errorPulse
        NumberAnimation{target:root;property:"errorStrength";to:1;duration:70}
        NumberAnimation{target:root;property:"errorStrength";to:.2;duration:140}
        NumberAnimation{target:root;property:"errorStrength";to:1;duration:120}
        PauseAnimation{duration:650}
        NumberAnimation{target:root;property:"errorStrength";to:0;duration:320}
    }
    Connections {
        target:root.host
        function onErrorTextChanged(){if(root.host.errorText.length>0)root.errorFeedback()}
        function onAuthenticationInputAccepted(){outerRing.acceptedInput()}
    }
    GeminiRenderQuality{id:renderQuality;active:root.visible&&root.host.animationsEnabled}
    Item {
        id:layout;width:1672;height:941;anchors.centerIn:parent
        scale:Math.min(root.width/width,root.height/height)
        GeminiFrame {
            objectName:"GeminiLockWelcome";x:-22;y:47;width:435;height:114
            accent:root.securityColor;glow:.55;fill:"#db02090b";corner:22
            Column {
                x:50;y:19;width:275;spacing:2
                Text{text:root.host.greetingPrefix();color:root.securityColor;font.pixelSize:19}
                Text{text:root.host.currentDisplayName();width:275;elide:Text.ElideRight;color:"white";font.bold:true;font.pixelSize:27;fontSizeMode:Text.Fit;minimumPixelSize:20}
                Text{text:root.host.errorText.length?root.host.errorText:root.host.isLockedOut()?"Access suspended · "+root.host.formatTime(root.host.lockoutSecondsRemaining()):root.host.cardArmed?"Enter controller passcode":root.host.loginSuccess?"Access granted":"Profile ready · Press X to unlock";width:275;elide:Text.ElideRight;color:"#edf6f9";font.pixelSize:16}
            }
            Dashboard.SemanticStatusIcon{visible:SecurityIndicator.score(root.securityBackend)>=55;x:346;y:24;width:41;height:43;kind:SecurityIndicator.icon(root.securityBackend);accent:root.securityColor}
            Shape {
                x:344;y:22;width:54;height:50;visible:SecurityIndicator.score(root.securityBackend)<55
                preferredRendererType:Shape.CurveRenderer
                ShapePath{strokeColor:root.securityColor;strokeWidth:4;fillColor:"transparent";joinStyle:ShapePath.RoundJoin;capStyle:ShapePath.RoundCap
                    PathSvg{path:"M 27 2 L 51 46 L 3 46 Z M 27 17 L 27 29 M 27 36 L 27 37"}
                }
            }
            Text{objectName:"GeminiLockSecurityLabel";x:314;y:79;width:92;horizontalAlignment:Text.AlignHCenter;text:SecurityIndicator.label(root.securityBackend);color:root.securityColor;font.bold:true;font.pixelSize:text.length>9?12:17}
        }
        Item {
            x:625;y:15;width:450;height:130
            EnergyAtom{x:-20;y:-10;width:135;height:135;animated:root.host.animationsEnabled;quality:renderQuality}
            Column{x:125;y:14;spacing:0
                Text{text:"Neutron<font color='#ff1735'>OS</font>";textFormat:Text.RichText;color:"#f6faff";font.bold:true;font.pixelSize:54}
                Text{text:"G E M I N I";color:"#00ffdb";font.bold:true;font.pixelSize:37}
            }
        }
        LockClock055 {
            id:worldClock;x:1255;y:28;width:389;height:206;animated:root.host.animationsEnabled;quality:renderQuality
            settings:root.clockBackend;visible:root.clockVisible
            focused:root.host.lockscreenFocus==="clock"&&!root.host.cardArmed
            interactionBlocked:root.host.cardArmed||root.host.loginSuccess||root.host.isLockedOut()
            onFocusRequested:root.host.setLockscreenFocus("clock")
            onAuthenticationRequested:root.host.beginClockTimezoneAuthentication()
        }
        Item {
            id:center;objectName:"GeminiLockCenter"
            x:506;y:151;width:660;height:660
            LockHelix057 {
                id:outerRing;quality:renderQuality;anchors.fill:parent
                armed:root.host.cardArmed&&!root.host.loginSuccess&&!root.host.isLockedOut()
                animated:root.visible&&root.host.animationsEnabled
            }
            EnergyAtom{x:45;y:45;width:570;height:570;nucleusVisible:false;visible:!root.host.cardArmed;animated:root.visible&&visible&&root.host.animationsEnabled;feedback:root.feedback;quality:renderQuality}
            Rectangle {
                id:userCard;objectName:"GeminiLockUserIcon"
                anchors.centerIn:parent;width:170;height:170;radius:85;color:"#ef020817"
                // The avatar surface and circular mask share the exact outline bounds.
                Item {
                    id:avatarSurface;objectName:"GeminiLockAvatarSurface";anchors.fill:parent
                    layer.enabled:true
                    layer.effect:MultiEffect{maskEnabled:true;maskSource:avatarMask}
                    Image {
                        id:avatarImage;objectName:"GeminiLockAvatarImage";anchors.fill:parent
                        source:String(root.host.currentAvatarSource()).length?root.host.currentAvatarSource():Qt.resolvedUrl("../../themes/Default/users/user_icon.png")
                        fillMode:Image.PreserveAspectCrop;smooth:true;mipmap:true
                        // Only the measured Default artwork's transparent outer margin is cropped.
                        sourceClipRect:String(source).indexOf("/themes/Default/users/user_icon.png")>=0?Qt.rect(32,24,960,960):Qt.rect(0,0,0,0)
                    }
                    Image {
                        anchors.fill:parent;visible:avatarImage.status!==Image.Ready
                        source:"../../themes/Default/users/user_icon.png";sourceClipRect:Qt.rect(32,24,960,960)
                        fillMode:Image.PreserveAspectCrop;smooth:true;mipmap:true
                    }
                }
                Rectangle{id:avatarMask;objectName:"GeminiLockAvatarMask";anchors.fill:parent;radius:width/2;color:"white";visible:false;layer.enabled:true}
                Rectangle {
                    objectName:"GeminiLockAvatarOutline";anchors.fill:parent;radius:width/2;color:"transparent";z:2
                    border.width:4;border.color:root.feedback==="error"?"#ff2035":root.feedback==="success"?"#00ff8b":"#00d9ff"
                }
                MouseArea{anchors.fill:parent;onClicked:{root.host.setLockscreenFocus("user");root.host.selectFocused()}}
            }
            Rectangle {
                anchors.centerIn:parent;width:660;height:660;radius:330;color:"transparent";border.color:"#00ff8b";border.width:4
                visible:root.host.loginSuccess
                scale:root.host.unlockRippleScale;opacity:root.host.unlockRippleOpacity
            }
        }
        LockControllerStatus {
            objectName:"GeminiLockControllerPanel";x:(layout.width-width)/2;y:824;width:426;height:84
            controller:root.host.controllerBackend;visible:root.detailsVisible;active:root.visible&&visible
        }
        Text{objectName:"GeminiLockPasscodeCount";x:535;y:905;width:600;text:root.host.isLockedOut()?"SECURITY TIMER · "+root.host.formatTime(root.host.lockoutSecondsRemaining()):root.host.cardArmed?"Controller passcode · "+root.host.inputTokens.length+" inputs":"";horizontalAlignment:Text.AlignHCenter;font.pixelSize:19;color:root.feedback==="error"?"#ff4055":"#a7deff"}
    }
}
