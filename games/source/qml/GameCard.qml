import QtQuick
NeonPanel {
    id: card
    property var game: ({})
    property bool showArtwork: true
    radius: 11
    Image { id: artworkImage; anchors.fill: parent; anchors.margins: 2; source: card.showArtwork ? String(card.game.artworkDisplay || card.game.artwork || "") : ""; sourceSize: Qt.size(512,768); fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: status === Image.Ready }
    Rectangle { anchors.fill: parent; anchors.margins: 2; color: "transparent"; gradient: Gradient { GradientStop { position: 0; color: "#05031223" } GradientStop { position: 0.48; color: "#08020b17" } GradientStop { position: 1; color: "#fa010408" } } }
    Text { anchors.centerIn: parent; visible: !card.showArtwork || artworkImage.status!==Image.Ready; text: "◇"; color: "#2c9bc4"; font.pixelSize: parent.height*0.33 }
    Column {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
        spacing: 8
        Text { width: parent.width; text: card.game.titleOverride || card.game.title || ""; color: "white"; font.pixelSize: Math.max(14,card.width*0.084); font.weight: Font.DemiBold; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
        Row { spacing: 10
            Rectangle { color: "#bc00070e"; radius: 7; border.color: "#81909b"; width: label.width+16; height: 23
                Text { id: label; anchors.centerIn: parent; text: String(card.game.chosenKind || card.game.kind || "Unknown").toUpperCase(); color: "white"; font.pixelSize: 12 }
            }
            Text { text: card.game.online ? "●" : "○"; color: card.game.online ? "#02f09f" : "#94afc3"; font.pixelSize: 17 }
            Text { text: card.game.favorite ? "★" : ""; color: "#5aceff"; font.pixelSize: 16 }
        }
    }
}
