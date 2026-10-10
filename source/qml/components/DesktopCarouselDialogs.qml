import QtQuick

Item {
    id: shared
    required property var host
    Rectangle {
        visible: host.desktopCarouselRemoveModalOpen && !host.selectorOnly && host.activeMode === "desktop"
        anchors.horizontalCenter: shared.horizontalCenter
        anchors.bottom: shared.bottom
        anchors.bottomMargin: 10*host.uiScale
        width: 300*host.uiScale
        height: 74*host.uiScale
        radius: 18*host.uiScale
        color: "#F41A0710"
        border.width: 2
        border.color: "#FF4057"
        z: 96
        Column {
            anchors.centerIn: parent
            spacing: 4*host.uiScale
            Text { text: "Remove app icon?"; color: "#FFFFFF"; font.pixelSize: 13*host.uiScale; font.bold: true; horizontalAlignment: Text.AlignHCenter; width: 270*host.uiScale }
            Text { text: "PRESS CIRCLE AGAIN"; color: "#FF6577"; font.pixelSize: 9*host.uiScale; font.bold: true; font.letterSpacing: 1.5*host.uiScale; horizontalAlignment: Text.AlignHCenter; width: 270*host.uiScale }
        }
    }

    Rectangle {
        visible: host.desktopCarouselSettingsOpen && !host.selectorOnly && host.activeMode === "desktop"
        anchors.horizontalCenter: shared.horizontalCenter
        anchors.bottom: shared.bottom
        anchors.bottomMargin: 10*host.uiScale
        width: Math.min(parent.width*0.56, 760*host.uiScale)
        height: 270*host.uiScale
        radius: 22*host.uiScale
        color: "#F4071426"
        border.width: 2
        border.color: "#FF4057"
        z: 98

        Column {
            anchors.fill: parent
            anchors.margins: 18*host.uiScale
            spacing: 12*host.uiScale

            Text { width: parent.width; text: "APP CAROUSEL SETTINGS"; color: "#FFFFFF"; font.pixelSize: 15*host.uiScale; font.bold: true; horizontalAlignment: Text.AlignHCenter; font.letterSpacing: 1.4*host.uiScale }

            Rectangle {
                width: parent.width
                height: 54*host.uiScale
                radius: 15*host.uiScale
                color: host.desktopCarouselSettingsRow===0 ? "#3A111A" : "#081522"
                border.width: host.desktopCarouselSettingsRow===0 ? 2 : 1
                border.color: host.desktopCarouselSettingsRow===0 ? "#FF4057" : "#294866"
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 16*host.uiScale
                    anchors.rightMargin: 16*host.uiScale
                    spacing: 12*host.uiScale
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "ICON SLOTS"; color: "#F4FBFF"; font.pixelSize: 10*host.uiScale; font.bold: true }
                    Item { width: Math.max(1, parent.width - 230*host.uiScale); height: 1 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "‹"; color: "#8AA6C8"; font.pixelSize: 16*host.uiScale; font.bold: true }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: String(host.desktopCarouselCapacity); color: "#7DF9FF"; font.pixelSize: 15*host.uiScale; font.bold: true }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "›"; color: "#8AA6C8"; font.pixelSize: 16*host.uiScale; font.bold: true }
                }
            }

            Rectangle {
                width: parent.width
                height: 118*host.uiScale
                radius: 15*host.uiScale
                color: host.desktopCarouselSettingsRow===1 ? "#3A111A" : "#081522"
                border.width: host.desktopCarouselSettingsRow===1 ? 2 : 1
                border.color: host.desktopCarouselSettingsRow===1 ? "#FF4057" : "#294866"
                Column {
                    anchors.fill: parent
                    anchors.margins: 10*host.uiScale
                    spacing: 8*host.uiScale
                    Text { text: "AVAILABLE APPS  •  X ADD / REMOVE"; color: "#AFC5DB"; font.pixelSize: 8*host.uiScale; font.bold: true }
                    ListView {
                        id: desktopCarouselSettingsApps
                        width: parent.width
                        height: 76*host.uiScale
                        orientation: ListView.Horizontal
                        spacing: 8*host.uiScale
                        interactive: false
                        model: host.baseAppList
                        currentIndex: host.desktopCarouselPickerIndex
                        delegate: Item {
                            required property int index
                            required property var modelData
                            width: 58*host.uiScale
                            height: 72*host.uiScale
                            Rectangle {
                                anchors.fill: parent
                                radius: 12*host.uiScale
                                color: index===host.desktopCarouselPickerIndex&&host.desktopCarouselSettingsRow===1 ? "#152B42" : "transparent"
                                border.width: index===host.desktopCarouselPickerIndex&&host.desktopCarouselSettingsRow===1 ? 2 : 0
                                border.color: "#4DA6FF"
                            }
                            Image { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: 4*host.uiScale; width: 42*host.uiScale; height: 42*host.uiScale; source: host.appIconSource(modelData); fillMode: Image.PreserveAspectFit; smooth: true; mipmap: false }
                            Rectangle { visible: host.desktopCarouselIds.indexOf(String(modelData.id||""))>=0; anchors.right: parent.right; anchors.top: parent.top; width: 13*host.uiScale; height: 13*host.uiScale; radius: 7*host.uiScale; color: "#22FF88"; border.width: 1; border.color: "#D8FFEA"; Text { anchors.centerIn: parent; text: "✓"; color: "#03120A"; font.pixelSize: 8*host.uiScale; font.bold: true } }
                            Text { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; text: String(modelData.name||modelData.displayName||modelData.id||""); color: "#F4FBFF"; font.pixelSize: 7*host.uiScale; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                        }
                    }
                }
            }

            Text { width: parent.width; text: "UP/DOWN SECTION   •   LEFT/RIGHT ADJUST   •   X TOGGLE APP   •   CIRCLE CLOSE"; color: "#8AA6C8"; font.pixelSize: 7.5*host.uiScale; font.bold: true; horizontalAlignment: Text.AlignHCenter }
        }
    }

}
