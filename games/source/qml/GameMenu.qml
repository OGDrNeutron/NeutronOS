import QtQuick
Item {
    id: modal
    property var session: null
    property int selected: 0
    visible: session !== null && session.menuOpen
    property var actions: session && session.stopTimedOut ? ["Wait for game", "Force Close Game"] : ["Resume Game", "Close Game"]
    function handleControllerPressed(action) {
        if(action==="left" || action==="up") selected=Math.max(0,selected-1)
        else if(action==="right" || action==="down") selected=Math.min(actions.length-1,selected+1)
        else if(action==="cancel" && session && !session.stopTimedOut) session.resumeGame()
        else if(action==="primary" && session) {
            if(session.stopTimedOut) { if(selected===1)session.forceCloseGame() }
            else if(selected===0)session.resumeGame()
            else session.closeGame()
        }
    }
    onVisibleChanged: if(visible) {selected=0;forceActiveFocus()}
    Rectangle { anchors.fill: parent; color: "#db01050e" }
    NeonPanel {
        anchors.centerIn: parent; width: Math.min(parent.width*0.68,820); height: 350; illuminated: true
        Column {
            anchors.fill: parent; anchors.margins: 34; spacing: 23
            Text { text: "NEUTRONOS GEMINI  /  GAME SESSION"; color: "#36c9ff"; font.pixelSize: 17; font.letterSpacing: 2 }
            Text { width: parent.width; text: session ? session.gameTitle : ""; color: "white"; font.pixelSize: 31; font.bold: true; elide: Text.ElideRight }
            Text { width: parent.width; text: session && session.stopTimedOut ? "Graceful close timed out. Force Close may lose unsaved progress." : "Gameplay input is reserved while this menu is open."; color: "#aac3d6"; font.pixelSize: 18; wrapMode: Text.Wrap }
            Row {
                spacing: 20
                Repeater {
                    model: modal.actions
                    NeonPanel { width: 310; height: 65; illuminated: modal.selected===index
                        Text { anchors.centerIn: parent; text: modelData; color: "white"; font.pixelSize: 21 }
                        MouseArea { anchors.fill: parent; onClicked: {modal.selected=index;modal.handleControllerPressed("primary")} }
                    }
                }
            }
        }
    }
    Connections { target: modal.session; function onModalAction(action) { if(modal.visible)modal.handleControllerPressed(action) } }
    Keys.onPressed: function(event) { var action=event.key===Qt.Key_Up?"up":event.key===Qt.Key_Down?"down":event.key===Qt.Key_Left?"left":event.key===Qt.Key_Right?"right":event.key===Qt.Key_Return?"primary":event.key===Qt.Key_Escape?"cancel":"";if(action){handleControllerPressed(action);event.accepted=true} }
}
