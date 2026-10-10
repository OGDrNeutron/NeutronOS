import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    // NEUTRONOS_CONTROLLER_PROMO_PLAYSTATION_LABEL_V3

    // NEUTRONOS_CONTROLLER_PROMOTION_MODAL_V2
    // Deliberately has no AppStore-manager dependency at component-load time.
    // The modal only emits a deep-link request when the user selects View.

    anchors.fill: parent
    visible: true
    enabled: visible
    focus: visible
    z: 30000

    property var contextData: ({})
    property var modalContext: ({})
    property int selectedAction: 0

    readonly property color panelColor: "#071426"
    readonly property color panelRaised: "#0B1A30"
    readonly property color electricBlue: "#00A8FF"
    readonly property color cobaltBlue: "#0047AB"
    readonly property color neutronCyan: "#7DF9FF"
    readonly property color textWhite: "#F4FBFF"
    readonly property color mutedText: "#8AA6C8"
    readonly property color successGreen: "#22FF88"

    readonly property string appId: "customcontrollers"
    readonly property string appName: "Custom Controllers"
    readonly property string iconUrl: "https://raw.githubusercontent.com/OGDrNeutron/NeutronOS/main/Apps/icons/customcontrollers.png"
    readonly property string posterUrl: "https://raw.githubusercontent.com/OGDrNeutron/NeutronOS/main/Apps/posters/customcontrollers.png"

    signal closed()
    signal actionRequested(string action, var payload)

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        selectedAction = 0
        visible = true
        forceActiveFocus()
    }

    function openModal(context) { open(context) }

    function close() {
        if (!visible)
            return
        visible = false
        closed()
    }

    function closeModal() { close() }

    function activate() {
        if (selectedAction === 0)
            actionRequested("openAppStore", { "packageId": appId })
        else
            close()
    }

    function handleControllerPressed(action) {
        var a = String(action || "").trim().toLowerCase()
        if (a === "left") selectedAction = 0
        else if (a === "right") selectedAction = 1
        else if (a === "primary" || a === "x" || a === "confirm") activate()
        else if (a === "cancel" || a === "o" || a === "back") close()
        return true
    }

    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return visible }

    Keys.onPressed: function(event) {
        var a = ""
        if (event.key === Qt.Key_Left) a = "left"
        else if (event.key === Qt.Key_Right) a = "right"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) a = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) a = "cancel"
        if (a.length > 0) {
            handleControllerPressed(a)
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#D4020710"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1360)
        height: Math.min(parent.height - 100, 820)
        radius: 34
        color: root.panelColor
        border.width: 2
        border.color: root.electricBlue
        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 32
            color: "transparent"
            border.width: 1
            border.color: "#173C60"
        }

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 126
            color: "#091A30"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18

                Rectangle {
                    width: 66
                    height: 66
                    radius: 20
                    color: "#0D2948"
                    border.width: 2
                    border.color: root.electricBlue

                    Image {
                        id: headerIcon
                        anchors.fill: parent
                        anchors.margins: 8
                        source: root.iconUrl
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        cache: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: headerIcon.status === Image.Error
                        text: "CC"
                        color: root.electricBlue
                        font.pixelSize: 20
                        font.bold: true
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: "CONTROLLER CUSTOMIZATION"
                        color: root.textWhite
                        font.pixelSize: 28
                        font.bold: true
                        font.letterSpacing: 1.1
                    }

                    Text {
                        text: "CUSTOM CONTROLLERS  •  NEUTRONOS APP STORE"
                        color: root.electricBlue
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: actions.top
            anchors.margins: 30
            spacing: 30

            Rectangle {
                width: 360
                height: parent.height
                radius: 26
                color: "#07111F"
                border.width: 1
                border.color: "#274E73"
                clip: true

                Image {
                    id: posterImage
                    anchors.fill: parent
                    source: root.posterUrl
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    cache: true
                }

                Rectangle {
                    anchors.fill: parent
                    visible: posterImage.status === Image.Error
                    color: "#091A30"
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 50
                        text: "CUSTOM\nCONTROLLERS"
                        color: root.electricBlue
                        font.pixelSize: 34
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 118
                    color: "#D006101E"

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 20
                        spacing: 5
                        Text { text: root.appName; color: root.textWhite; font.pixelSize: 23; font.bold: true }
                        Text { text: "CONTROLLER-FIRST CUSTOMIZATION"; color: root.neutronCyan; font.pixelSize: 11; font.bold: true }
                    }
                }
            }

            Column {
                width: parent.width - 390
                anchors.verticalCenter: parent.verticalCenter
                spacing: 22

                Row {
                    spacing: 18

                    Rectangle {
                        width: 92
                        height: 92
                        radius: 24
                        color: "#0B2137"
                        border.width: 2
                        border.color: root.electricBlue

                        Image {
                            id: appIcon
                            anchors.fill: parent
                            anchors.margins: 10
                            source: root.iconUrl
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            cache: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appIcon.status === Image.Error
                            text: "CC"
                            color: root.electricBlue
                            font.pixelSize: 24
                            font.bold: true
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Text { text: root.appName; color: root.textWhite; font.pixelSize: 31; font.bold: true }
                        Text {
                            text: "PLAYSTATION"
                            color: root.electricBlue
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 0.55
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "Download Custom Controllers for advanced controller customization. Keep System Overview focused on connection and battery status while the app owns remapping, profiles, diagnostics, lighting and supported controller-specific tuning."
                    color: "#D8E8F5"
                    font.pixelSize: 18
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    width: parent.width
                    height: 166
                    radius: 22
                    color: root.panelRaised
                    border.width: 1
                    border.color: "#264C70"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 10
                        Text { text: "APP FEATURES"; color: root.neutronCyan; font.pixelSize: 14; font.bold: true; font.letterSpacing: 0.8 }
                        Text {
                            width: parent.width
                            text: "• Controller profiles and remapping\n• Supported lighting and haptic controls\n• Controller diagnostics and identification\n• Per-controller customization without bloating the system shell"
                            color: root.mutedText
                            font.pixelSize: 15
                            lineHeight: 1.25
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        Row {
            id: actions
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 28
            spacing: 18

            Rectangle {
                width: 430
                height: 68
                radius: 18
                color: root.selectedAction === 0 ? "#123E68" : "#0B2137"
                border.width: root.selectedAction === 0 ? 2 : 1
                border.color: root.selectedAction === 0 ? root.electricBlue : "#315A80"
                Text { anchors.centerIn: parent; text: "VIEW IN APP STORE"; color: root.textWhite; font.pixelSize: 16; font.bold: true; font.letterSpacing: 0.7 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.selectedAction = 0; root.activate() } }
            }

            Rectangle {
                width: 210
                height: 68
                radius: 18
                color: root.selectedAction === 1 ? "#123E68" : "#0B2137"
                border.width: root.selectedAction === 1 ? 2 : 1
                border.color: root.selectedAction === 1 ? root.electricBlue : "#315A80"
                Text { anchors.centerIn: parent; text: "CLOSE"; color: root.textWhite; font.pixelSize: 16; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.selectedAction = 1; root.activate() } }
            }
        }
    }
}
