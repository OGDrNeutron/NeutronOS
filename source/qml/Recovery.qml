import QtQuick
import QtQuick.Controls
import "gemini"
ApplicationWindow {
    id:root
    visible:true;visibility:Window.FullScreen;color:"#030814";title:"NeutronOS Gemini Recovery"
    RecoveryExperience{id:experience;anchors.fill:parent;backend:recoveryModeManager}
    FocusScope {
        id:input;anchors.fill:parent;focus:true
        Keys.onPressed:function(event){
            if(event.key===Qt.Key_Up)experience.handle("up")
            else if(event.key===Qt.Key_Down)experience.handle("down")
            else if(event.key===Qt.Key_Return||event.key===Qt.Key_Enter)experience.handle("primary")
            else if(event.key===Qt.Key_Escape||event.key===Qt.Key_Backspace)experience.handle("cancel")
            else if(event.key===Qt.Key_Space)experience.handle("secondary")
            else return
            event.accepted=true
        }
    }
    Connections{target:controllerManager;function onActionPressed(action){experience.handle(action)}}
    Component.onCompleted:input.forceActiveFocus()
}
