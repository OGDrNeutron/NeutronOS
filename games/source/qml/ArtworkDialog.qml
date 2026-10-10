import QtQuick
Rectangle {
    id: dialog
    objectName: "GamesArtworkDialog"
    property var backend
    property var game: ({})
    property int selected: 0
    readonly property var files: backend ? backend.artworkFiles : []
    signal closeRequested()
    color: "#e701050e"
    function handleControllerPressed(action) {
        if(action==="cancel")closeRequested()
        else if(action==="up")selected=Math.max(0,selected-1)
        else if(action==="down")selected=Math.min(files.length+1,selected+1)
        else if(action==="primary") {
            if(selected===1)backend.refreshArtwork()
            else if(backend.setArtworkAssignment(game.id,selected===0?"":files[selected-2].path))closeRequested()
        }
    }
    onVisibleChanged: if(visible)selected=0
    onFilesChanged: selected=Math.max(0,Math.min(selected,files.length+1))
    NeonPanel {
        anchors.centerIn: parent; width: Math.min(parent.width*0.85,1250); height: Math.min(parent.height*0.85,770); illuminated: true
        Text { x: 30; y: 24; text: "Game Artwork"; color: "white"; font.pixelSize: 29; font.bold: true }
        Text { x: 30; y: 70; width: parent.width-60; text: (dialog.game.titleOverride || dialog.game.title || "")+"\n"+(backend?backend.artworkDirectory:""); color: "#93c9e7"; font.pixelSize: 17; wrapMode: Text.Wrap }
        Image { x: 30; y: 135; width: parent.width*0.32; height: parent.height-240; source: dialog.game.artworkDisplay || dialog.game.artwork || ""; sourceSize: Qt.size(512,768); fillMode: Image.PreserveAspectFit; asynchronous: true }
        Text { x: 30; y: parent.height-95; width: parent.width-60; text: (dialog.game.artworkAutomatic?"Automatic matching":"Manual assignment")+"\n"+(dialog.game.artworkFile || "No custom image assigned")+(dialog.game.artworkSelectionRequired?"\nMultiple equally valid matches: choose an image.":""); color: "#adc8da"; font.pixelSize: 15; wrapMode: Text.Wrap }
        ListView {
            id: choices
            x: parent.width*0.38; y: 135; width: parent.width*0.58; height: parent.height-245; clip: true; spacing: 9
            model: 2+dialog.files.length; currentIndex: dialog.selected
            onCurrentIndexChanged: positionViewAtIndex(currentIndex,ListView.Contain)
            delegate: NeonPanel {
                width: choices.width; height: 65; illuminated: dialog.selected===index
                Image { x: 8; y: 5; width: 45; height: 55; source: index>=2?dialog.files[index-2].thumbnail:""; sourceSize: Qt.size(90,110); fillMode: Image.PreserveAspectFit; asynchronous: true }
                Text { x: index>=2?66:16; anchors.verticalCenter: parent.verticalCenter; width: parent.width-x-15; text: index===0?"Restore Automatic Matching":index===1?"Refresh Artwork":dialog.files[index-2].fileName; color: "white"; font.pixelSize: 17; elide: Text.ElideRight }
                MouseArea { anchors.fill: parent; onClicked: {dialog.selected=index;dialog.handleControllerPressed("primary")} }
            }
        }
        Text { x: parent.width*0.38; y: parent.height-120; width: parent.width*0.58; text: "↑ ↓ Select   X Assign / Refresh   Circle Return\nOriginal images are preserved. Supported formats: "+(backend?backend.artworkFormats.join(", "):""); color: "#4ac9ff"; font.pixelSize: 16; wrapMode: Text.Wrap }
    }
}
