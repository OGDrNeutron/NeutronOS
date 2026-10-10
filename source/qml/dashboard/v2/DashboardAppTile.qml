import QtQuick

Item {
    id: root

    property var backend: null
    property var appData: ({})
    property var cardInfo: ({})

    property bool selected: false
    property color accent: "#49DFFF"
    property real uiScale: 1.0

    signal activated()
    signal focused()
    signal detailsRequested()
    signal actionsRequested()

    readonly property color white: "#F8FBFF"
    readonly property color muted: "#9FB3C9"
    readonly property color infoBlue: "#72B9FF"
    readonly property color green: "#72EE78"

    readonly property real infoHeight:
        94 * uiScale

    function safeText(value) {
        return String(
            value === undefined || value === null
            ? ""
            : value
        ).trim()
    }

    function asset(value, kind) {
        var text = safeText(value)

        if (!text)
            return ""

        if (
            text.indexOf(":") >= 0 ||
            text.indexOf("/") >= 0
        )
            return text

        return Qt.resolvedUrl(
            "../../../themes/Default/apps/" +
            kind +
            "/" +
            text +
            ".png"
        )
    }

    function posterSource() {
        return asset(
            appData.posterSource ||
            appData.posterPath ||
            appData.poster,
            "posters"
        )
    }

    function iconSource() {
        return asset(
            appData.iconSource ||
            appData.icon,
            "icons"
        )
    }

    function appName() {
        return safeText(
            appData.name ||
            appData.displayName ||
            appData.title ||
            appData.id
        ) || "Application"
    }

    function typeText() {
        var value = safeText(cardInfo.typeText)
        return value.length > 0 ? value : "Unknown"
    }

    function sizeText() {
        var value = safeText(cardInfo.sizeText)

        return value.length > 0
            ? value
            : "Unknown"
    }

    function formatLastOpenedFallback() {
        var raw = safeText(appData.lastUsedUtc)

        if (raw.length <= 0)
            return "Never opened"

        var stamp = new Date(raw)

        if (isNaN(stamp.getTime()))
            return "Never opened"

        return Qt.formatDateTime(
            stamp,
            "MMM d, h:mm AP"
        )
    }

    function lastOpenedText() {
        var value = safeText(cardInfo.lastOpenedText)

        return value.length > 0
            ? value
            : formatLastOpenedFallback()
    }

    function appRunning() {
        if (appData.appRunning === true)
            return true

        return (
            appData.uiRunning === true ||
            appData.backgroundRunning === true
        )
    }

    function serviceRunning() {
        return appData.serviceRunning === true
    }

    function refreshCardInfo() {
        if (
            backend &&
            typeof backend.appCardInfo === "function"
        ) {
            var info = backend.appCardInfo(appData)

            if (info)
                cardInfo = info

            return
        }

        cardInfo = ({})
    }

    onAppDataChanged:
        Qt.callLater(refreshCardInfo)

    onBackendChanged:
        Qt.callLater(refreshCardInfo)

    Component.onCompleted:
        Qt.callLater(refreshCardInfo)

    scale: selected ? 1.020 : 1.0
    z: selected ? 20 : 1

    Behavior on scale {
        NumberAnimation {
            duration: 175
            easing.type: Easing.InOutCubic
        }
    }

    Rectangle {
        id: glowOuter

        anchors.fill: card
        anchors.margins: -6 * root.uiScale

        radius: 22 * root.uiScale
        visible: root.selected

        color: "#1418DFFF"
        border.width: 3.0 * root.uiScale
        border.color: root.accent
        opacity: 0.94
    }

    Rectangle {
        id: glowAccent

        anchors.fill: card
        anchors.margins: -2 * root.uiScale

        radius: 20 * root.uiScale
        visible: root.selected

        color: "transparent"
        border.width: 1.4 * root.uiScale
        border.color: "#C9A84DFF"
        opacity: 0.88
    }

    Rectangle {
        id: card

        anchors.fill: parent

        radius: 18 * root.uiScale
        clip: true

        color: "#F1091321"

        border.width:
            root.selected
            ? 2.3 * root.uiScale
            : 1.15 * root.uiScale

        border.color:
            root.selected
            ? root.accent
            : "#526B879E"

        // Full 1:1 poster region. The information panel starts after this item,
        // so no name/icon/status UI obscures any part of the artwork.
        Rectangle {
            id: posterArea

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: width

            color: "#08111D"

            Image {
                id: poster

                anchors.fill: parent

                source: root.posterSource()
                fillMode: Image.PreserveAspectFit

                sourceSize.width: 768
                sourceSize.height: 768

                asynchronous: true
                cache: true
                smooth: true
            }

            Rectangle {
                anchors.fill: parent

                visible:
                    poster.status !== Image.Ready

                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: "#14243A"
                    }

                    GradientStop {
                        position: 1.0
                        color: "#08101D"
                    }
                }

                Image {
                    anchors.centerIn: parent

                    width: parent.width * 0.52
                    height: width

                    source: root.iconSource()
                    fillMode: Image.PreserveAspectFit

                    asynchronous: true
                    cache: true
                    smooth: true
                }
            }

            Rectangle {
                visible: root.selected

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top

                height: 3 * root.uiScale

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0.0
                        color: "#35DFFF"
                    }

                    GradientStop {
                        position: 0.5
                        color: root.accent
                    }

                    GradientStop {
                        position: 1.0
                        color: "#EC46FF"
                    }
                }
            }
        }

        Rectangle {
            id: infoPlate

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: posterArea.bottom
            anchors.bottom: parent.bottom

            color: "#F40A1726"

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#F70A1726" }
                GradientStop { position: 0.52; color: "#F20B1828" }
                GradientStop { position: 1.0; color: "#EB10162B" }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.selected ? 2.6 * root.uiScale : 1.0 * root.uiScale
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.selected ? "#35E2FF" : "#3B58728B" }
                    GradientStop { position: 0.48; color: root.selected ? root.accent : "#3B58728B" }
                    GradientStop { position: 1.0; color: root.selected ? "#E04DFF" : "#3B58728B" }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3 * root.uiScale
                color: root.selected ? root.accent : "#274760"
                opacity: root.selected ? 1.0 : 0.65
            }

            Image {
                id: appIcon
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 5 * root.uiScale
                anchors.topMargin: 5 * root.uiScale
                anchors.bottomMargin: 5 * root.uiScale
                width: height
                source: root.iconSource()
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
            }

            Rectangle {
                anchors.left: appIcon.right
                anchors.leftMargin: 6 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height * 0.62
                color: "#31546D84"
            }

            Item {
                id: statusStack
                anchors.right: parent.right
                anchors.rightMargin: 9 * root.uiScale
                anchors.verticalCenter: parent.verticalCenter
                width: root.serviceRunning() || root.appRunning() ? 112 * root.uiScale : 0
                height: statusColumn.height

                Column {
                    id: statusColumn
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 5 * root.uiScale

                    Rectangle {
                        visible: root.serviceRunning()
                        width: statusColumn.width
                        height: 24 * root.uiScale
                        radius: 9 * root.uiScale
                        color: "#D3154629"
                        border.width: 1.05 * root.uiScale
                        border.color: root.green
                        Text {
                            anchors.centerIn: parent
                            text: "SERVICE RUNNING"
                            color: root.green
                            font.pixelSize: 8.7 * root.uiScale
                            font.bold: true
                            font.letterSpacing: 0.25 * root.uiScale
                        }
                    }

                    Rectangle {
                        visible: root.appRunning()
                        width: statusColumn.width
                        height: 24 * root.uiScale
                        radius: 9 * root.uiScale
                        color: "#D3154629"
                        border.width: 1.05 * root.uiScale
                        border.color: root.green
                        Text {
                            anchors.centerIn: parent
                            text: "APP RUNNING"
                            color: root.green
                            font.pixelSize: 9.0 * root.uiScale
                            font.bold: true
                            font.letterSpacing: 0.28 * root.uiScale
                        }
                    }
                }
            }

            Column {
                anchors.left: appIcon.right
                anchors.right: statusStack.width > 0 ? statusStack.left : parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 14 * root.uiScale
                anchors.rightMargin: 9 * root.uiScale
                anchors.topMargin: 10 * root.uiScale
                spacing: 4 * root.uiScale

                Text {
                    width: parent.width
                    text: root.appName()
                    color: root.white
                    font.pixelSize: 18.2 * root.uiScale
                    font.bold: true
                    font.letterSpacing: 0.15 * root.uiScale
                    elide: Text.ElideRight
                }

                Row {
                    width: parent.width
                    height: 20 * root.uiScale
                    spacing: 6 * root.uiScale

                    Rectangle {
                        height: 20 * root.uiScale
                        width: ownershipText.implicitWidth + 14 * root.uiScale
                        radius: 7 * root.uiScale
                        color: "#261A4260"
                        border.width: 1
                        border.color: root.typeText() === "App Store" ? "#B14DFF" : root.typeText() === "System" ? "#35DFFF" : "#FF5B8A"
                        Text {
                            id: ownershipText
                            anchors.centerIn: parent
                            text: root.typeText().toUpperCase()
                            color: root.typeText() === "App Store" ? "#D9A7FF" : root.typeText() === "System" ? "#80EAFF" : "#FF8BAC"
                            font.pixelSize: 8.6 * root.uiScale
                            font.bold: true
                            font.letterSpacing: 0.35 * root.uiScale
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "•  " + root.sizeText()
                        color: root.infoBlue
                        font.pixelSize: 9.7 * root.uiScale
                        font.bold: true
                    }
                }

                Text {
                    width: parent.width
                    text: "Last opened  " + root.lastOpenedText()
                    color: root.muted
                    font.pixelSize: 9.3 * root.uiScale
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            anchors.fill: parent

            hoverEnabled: true

            acceptedButtons:
                Qt.LeftButton |
                Qt.RightButton

            onEntered: root.focused()

            onClicked: function(mouse) {
                root.focused()

                if (mouse.button === Qt.RightButton)
                    root.actionsRequested()
                else
                    root.activated()
            }
        }
    }
}
