import QtQuick

Rectangle {
    id: editor
    objectName: "GamesControllerProfile"
    property var backend
    property var game: ({})
    property var mapping: ({})
    property var inverted: []
    property int selected: 0
    readonly property var controls: [
        {code: 304, name: "Cross / A"}, {code: 305, name: "Circle / B"},
        {code: 307, name: "Triangle / Y"}, {code: 308, name: "Square / X"},
        {code: 310, name: "L1 / Left Shoulder"}, {code: 311, name: "R1 / Right Shoulder"},
        {code: 314, name: "Select / Share"}, {code: 315, name: "Start / Options"},
        {code: 317, name: "L3 / Left Stick Click"}, {code: 318, name: "R3 / Right Stick Click"}
    ]
    signal closeRequested()
    color: "#e701050e"

    function target(code) { return mapping[String(code)] === undefined ? code : Number(mapping[String(code)]) }
    function name(code) {
        for(var i=0;i<controls.length;i++)if(controls[i].code===code)return controls[i].name
        return "Other saved button"
    }
    function changeButton(index, direction) {
        var source=controls[index].code, previous=target(source), targetIndex=0
        for(var i=0;i<controls.length;i++)if(controls[i].code===previous)targetIndex=i
        var next=controls[(targetIndex+direction+controls.length)%controls.length].code
        var updated=JSON.parse(JSON.stringify(mapping))
        // Swap the button already assigned to the new action, avoiding duplicate input.
        for(i=0;i<controls.length;i++)if(controls[i].code!==source && target(controls[i].code)===next)updated[String(controls[i].code)]=previous
        updated[String(source)]=next
        for(var key in updated)if(Number(key)===Number(updated[key]))delete updated[key]
        mapping=updated
    }
    function toggleAxis(code) {
        var next=inverted.slice(), index=next.indexOf(code)
        if(index<0)next.push(code);else next.splice(index,1)
        inverted=next
    }
    function rowName(index) {
        if(index<controls.length)return controls[index].name+"  →  "+name(target(controls[index].code))
        if(index===10)return "Invert Left Stick Vertical  ·  "+(inverted.indexOf(1)>=0?"On":"Off")
        if(index===11)return "Invert Right Stick Vertical  ·  "+(inverted.indexOf(4)>=0?"On":"Off")
        if(index===12)return "Save Controller Profile"
        return "Restore Default Buttons and Sticks"
    }
    function handleControllerPressed(action) {
        if(action==="cancel")closeRequested()
        else if(action==="up")selected=Math.max(0,selected-1)
        else if(action==="down")selected=Math.min(13,selected+1)
        else if(action==="primary" || action==="left" || action==="right") {
            if(selected<controls.length)changeButton(selected,action==="left"?-1:1)
            else if(selected===10)toggleAxis(1)
            else if(selected===11)toggleAxis(4)
            else if(action==="primary"&&selected===13){mapping=({});inverted=[]}
            else if(action==="primary"&&selected===12){
                var profile=JSON.parse(JSON.stringify(game.controllerProfile || {}))
                profile.buttons=mapping;profile.invertAxes=inverted
                if(backend.setControllerProfile(game.id,profile))closeRequested()
            }
        }
    }
    onVisibleChanged: if(visible){
        var profile=game.controllerProfile || {}
        mapping=JSON.parse(JSON.stringify(profile.buttons || {}))
        inverted=(profile.invertAxes || []).slice();selected=0
    }
    NeonPanel {
        anchors.centerIn: parent
        width: Math.min(parent.width*0.8,1050);height: Math.min(parent.height*0.86,780)
        illuminated: true
        Text { x: 30;y: 24;text: "Controller Profile";color: "white";font.pixelSize: 29;font.bold: true }
        Text { x: 30;y: 70;width: parent.width-60;text: (editor.game.titleOverride || editor.game.title || "")+"\nChange gameplay buttons with Left / Right or X. PS/Home stays reserved for Gemini.";color: "#93c9e7";font.pixelSize: 17;wrapMode: Text.Wrap }
        ListView {
            id: rows
            x: 30;y: 145;width: parent.width-60;height: parent.height-245
            clip: true;spacing: 10;model: 14;currentIndex: editor.selected
            onCurrentIndexChanged: positionViewAtIndex(currentIndex,ListView.Contain)
            delegate: NeonPanel {
                width: rows.width;height: 46;illuminated: editor.selected===index
                Text { anchors { left: parent.left;right: parent.right;verticalCenter: parent.verticalCenter;margins: 18 }text: editor.rowName(index);color: "white";font.pixelSize: 17;elide: Text.ElideRight }
                MouseArea { anchors.fill: parent;onClicked: {editor.selected=index;editor.handleControllerPressed("primary")} }
            }
        }
        Text { x: 30;y: parent.height-80;width: parent.width-60;text: "↑ ↓ Select    ← → Change    X Apply    Circle Cancel\nStick and trigger ranges stay analog. Games may also provide their own controller settings.";color: "#4ac9ff";font.pixelSize: 16;wrapMode: Text.Wrap }
    }
}
