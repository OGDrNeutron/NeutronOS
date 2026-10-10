import QtQuick

Item {
    id: shared
    required property var host
    property bool focused: false
    property real uiScale: host ? host.uiScale : 1
    signal appRequested(var app)
            Row {
                anchors.centerIn:parent
                spacing:6*shared.uiScale
                visible:true
                Repeater {
                    model:host.desktopCarouselResolvedApps
                    delegate:Item {
                        id:carouselIconSlot
                        required property int index
                        required property var modelData
                        width:38*shared.uiScale;height:38*shared.uiScale
                        readonly property bool selected:shared.focused&&host.desktopCarouselIndex===index
                        transformOrigin:Item.Center
                        SequentialAnimation on rotation {
                            running:host.desktopCarouselMoveMode&&carouselIconSlot.selected
                            loops:Animation.Infinite
                            NumberAnimation{from:-2.0;to:2.0;duration:90;easing.type:Easing.InOutSine}
                            NumberAnimation{from:2.0;to:-2.0;duration:90;easing.type:Easing.InOutSine}
                            onStopped:carouselIconSlot.rotation=0
                        }
                        Rectangle {
                            anchors.fill:parent
                            radius:10*shared.uiScale
                            color:"transparent"
                            border.width:carouselIconSlot.selected?2:0
                            border.color:host.desktopCarouselMoveMode?"#FF4057":"#4DA6FF"
                        }
                        Image {
                            id:carouselAppImage
                            anchors.centerIn:parent
                            width:32*shared.uiScale;height:32*shared.uiScale
                            source:host.appIconSource(modelData)
                            // The footer shows these at 32-64px. Decoding nine 500x500
                            // images on the Pi's GUI thread stalls every selection redraw.
                            sourceSize.width:Math.ceil(48*shared.uiScale)
                            sourceSize.height:Math.ceil(48*shared.uiScale)
                            asynchronous:true
                            fillMode:Image.PreserveAspectFit
                            smooth:true;mipmap:false;cache:true
                        }
                        Text {
                            anchors.centerIn:parent
                            visible:carouselAppImage.status===Image.Error||String(carouselAppImage.source).length===0
                            text:String(modelData.name||modelData.displayName||modelData.id||"A").slice(0,1).toUpperCase()
                            color:"#7DF9FF";font.pixelSize:11*shared.uiScale;font.bold:true
                        }
                        MouseArea {
                            anchors.fill:parent
                            cursorShape:Qt.PointingHandCursor
                            onClicked:{host.desktopCarouselIndex=index;shared.appRequested(modelData)}
                        }
                    }
                }
            }

}
