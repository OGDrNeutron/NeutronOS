import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
Item {
    id:root
    objectName:"GeminiLockPresentation"
    property var host
    property var clockBackend:typeof clockSettingsManager!=="undefined"?clockSettingsManager:null
    readonly property bool clockVisible:!clockBackend||clockBackend.lockscreenClockVisible!==false
    function handleClockAction(action){
        if(!clockVisible||root.host.cardArmed)return false
        if(action==="primary")worldClock.nextRegion()
        else if(action==="secondary")worldClock.returnToLocal()
        else if(action==="context")worldClock.requestLocalTimezone()
        return true
    }
    property real errorStrength:0
    property int observedInputCount:0
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
        function onInputTokensChanged(){
            var count=root.host.inputTokens.length
            if(count>root.observedInputCount && root.host.cardArmed && !root.host.loginSuccess && !root.host.isLockedOut())
                outerRing.acceptedInput()
            root.observedInputCount=count
        }
    }
    GeminiRenderQuality{id:renderQuality;active:root.visible&&root.host.animationsEnabled}
    Item {
        id:layout;width:1672;height:941;anchors.centerIn:parent
        scale:Math.min(root.width/width,root.height/height)
        GeminiFrame {
            objectName:"GeminiLockWelcome";visible:!root.clockBackend||root.clockBackend.lockscreenWelcomeVisible!==false;x:43;y:67;width:417;height:106;accent:root.feedback==="success"?"#00ff8b":"#02caff"
            Rectangle{x:15;y:15;width:2;height:77;radius:1;color:"#00caff"}
            Column {
                x:32;y:11;width:370;spacing:1
                Text{text:root.host.greetingPrefix();color:"#ace7ff";font.pixelSize:12;font.letterSpacing:2}
                Text{text:root.host.currentDisplayName();width:365;elide:Text.ElideRight;color:"white";font.bold:true;font.pixelSize:28}
                Text{text:root.host.errorText.length?root.host.errorText:root.host.isLockedOut()?"Access suspended · "+root.host.formatTime(root.host.lockoutSecondsRemaining()):root.host.statusText;width:365;elide:Text.ElideRight;color:root.feedback==="error"?"#ff4960":"#dceaff";font.pixelSize:16}
                Text{text:root.host.cardArmed?"Enter controller passcode":root.host.loginSuccess?"Access granted":"Press X to unlock";color:"#e6f8ff";font.pixelSize:16}
            }

        }
        Item {
            x:625;y:15;width:450;height:130
            EnergyAtom{x:-20;y:-10;width:135;height:135;animated:root.host.animationsEnabled;quality:renderQuality}
            Column{x:125;y:14;spacing:0
                Text{text:"Neutron<font color='#ff1735'>OS</font>";textFormat:Text.RichText;color:"#f6faff";font.bold:true;font.pixelSize:54}
                Text{text:"G E M I N I";color:"#00ffdb";font.bold:true;font.pixelSize:37}
            }
        }
        GeminiFrame {
            id:securityBadge;objectName:"GeminiLockSecurityBadge"
            x:43;y:189;width:417;height:75
            readonly property var backend:root.host && "loginSecurityBackend" in root.host ? root.host.loginSecurityBackend : null
            readonly property bool known:!!backend && backend.daemonOnline===true
            readonly property bool secure:known && root.host.loginSecurityIsSecure()
            accent:!known?"#ffd45a":secure?"#00ff87":"#ff1735"
            RecoveryGlyph{x:22;y:16;width:42;height:42;kind:securityBadge.secure?"secure":"unsecure";color:securityBadge.accent}
            Column{x:82;y:14;spacing:3
                Text{text:!securityBadge.known?"Security Unavailable":securityBadge.secure?"System Secure":"System Unsecure";color:securityBadge.accent;font.bold:true;font.pixelSize:22}
                Text{text:!securityBadge.known?"Waiting for Security service":securityBadge.secure?"All Systems Operational":"Attention Required";color:"#e7efff";font.pixelSize:16}
            }
        }
        LockClock055 {
            id:worldClock;x:1135;y:57;width:495;height:166;animated:root.host.animationsEnabled;quality:renderQuality
            settings:root.clockBackend;visible:root.clockVisible
            focused:root.host.lockscreenFocus==="clock"&&!root.host.cardArmed
            interactionBlocked:root.host.cardArmed||root.host.loginSuccess||root.host.isLockedOut()
            onFocusRequested:root.host.setLockscreenFocus("clock")
            onAuthenticationRequested:root.host.beginClockTimezoneAuthentication()
        }
        Item {
            id:center;objectName:"GeminiLockCenter"
            x:506;y:151;width:660;height:660
            LockRing055 {
                id:outerRing;quality:renderQuality;anchors.fill:parent
                animated:root.host.animationsEnabled;feedback:root.feedback
                opacity:root.host.cardArmed&&!root.host.loginSuccess&&!root.host.isLockedOut()?.75+root.errorStrength*.25:0
                visible:opacity>.001
                Behavior on opacity{NumberAnimation{duration:240;easing.type:Easing.InOutCubic}}
            }
            EnergyAtom{x:45;y:45;width:570;height:570;nucleusVisible:false;animated:root.host.animationsEnabled;feedback:root.feedback;quality:renderQuality}
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
        ControllerRegistrationSession{id:connection;active:root.visible;registrationEnabled:false;controller:root.host.controllerBackend}
        Text{objectName:"GeminiLockControllerConnection";x:535;y:819;width:600;text:"Controller · "+connection.connectionLabel;color:"#A7DEFF";font.pixelSize:21;horizontalAlignment:Text.AlignHCenter}
        Text{objectName:"GeminiLockPasscodeCount";x:535;y:852;width:600;text:root.host.isLockedOut()?"SECURITY TIMER · "+root.host.formatTime(root.host.lockoutSecondsRemaining()):root.host.cardArmed?"Controller passcode · "+root.host.inputTokens.length+" inputs":"";horizontalAlignment:Text.AlignHCenter;font.pixelSize:19;color:root.feedback==="error"?"#ff4055":"#a7deff"}
    }
}
