import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent
    visible: visibleMode
    enabled: visibleMode
    focus: visibleMode
    z: 130

    property bool visibleMode: false
    property int choice: 0
    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color textPrimary: "#F4FBFF"
    property color textSecondary: "#C8D5DF"
    property color textMuted: "#8AA6C8"
    property color divider: "#25313C"
    property color focusBlue: "#4DA6FF"
    property color warning: "#F5C542"
    property color danger: "#FF3040"
    property color neutronCyan: "#7DF9FF"

    signal enableConfirmed()
    signal cancelled()

    function open() {
        choice = 0
        visibleMode = true
        forceActiveFocus()
    }

    function closeCancel() {
        visibleMode = false
        cancelled()
    }

    function handleControllerPressed(button) {
        var action = String(button || "").toLowerCase()
        if (action === "cross" || action === "x" || action === "ps_cross") action = "primary"
        else if (action === "circle" || action === "o" || action === "ps_circle") action = "cancel"
        else if (action === "dpad_left") action = "left"
        else if (action === "dpad_right") action = "right"

        if (action === "left" || action === "right") {
            choice = choice === 0 ? 1 : 0
            return true
        }
        if (action === "cancel") {
            closeCancel()
            return true
        }
        if (action === "primary") {
            if (choice === 0) {
                closeCancel()
                return true
            }
            visibleMode = false
            enableConfirmed()
            return true
        }
        return true
    }

    Rectangle {
        anchors.fill: parent
        color: "#E602060D"
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 100, 1120)
        height: Math.min(parent.height - 100, 650)
        radius: 30
        color: root.panelColor
        border.width: 2
        border.color: root.warning
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 116
            color: "#06101F"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.divider
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                height: 64
                radius: 18
                color: "#2A2210"
                border.width: 1
                border.color: root.warning
                Text {
                    anchors.centerIn: parent
                    text: "!"
                    color: root.warning
                    font.pixelSize: 31
                    font.bold: true
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 116
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    text: "AUTOMATIC LOGIN"
                    color: root.textPrimary
                    font.pixelSize: 27
                    font.bold: true
                    font.letterSpacing: 1.1
                }
                Text {
                    text: "Physical-access security changes when LoginScreen is skipped"
                    color: root.textMuted
                    font.pixelSize: 14
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 146
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 96
            anchors.leftMargin: 34
            anchors.rightMargin: 34
            spacing: 16

            Rectangle {
                width: parent.width
                height: 188
                radius: 16
                color: "#081522"
                border.width: 1
                border.color: "#315A80"

                Column {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 11

                    Text {
                        text: "LOGINSCREEN WILL BE BYPASSED AT STARTUP"
                        color: root.warning
                        font.pixelSize: 16
                        font.bold: true
                        font.letterSpacing: 0.8
                    }

                    Text {
                        width: parent.width
                        text: "Anyone with physical access can reach the selected local account without entering its normal LoginScreen credential. High-priority Settings actions still require the active Linux account password before completion."
                        color: root.textSecondary
                        font.pixelSize: 15
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        text: "That authorization window is temporary and is cleared when Settings closes."
                        color: root.textMuted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Repeater {
                    model: [
                        { label: "KEEP LOGIN REQUIRED", tone: root.focusBlue, width: 360 },
                        { label: "ENABLE AUTOMATIC LOGIN", tone: root.danger, width: 400 }
                    ]

                    Rectangle {
                        required property int index
                        required property var modelData
                        width: modelData.width
                        height: 76
                        radius: 16
                        color: root.choice === index
                               ? (index === 0 ? "#0D263A" : "#2A1015")
                               : root.panelRaised
                        border.width: root.choice === index ? 2 : 1
                        border.color: root.choice === index ? modelData.tone : "#203847"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.choice === index ? modelData.tone : root.textPrimary
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 0.5
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 76
            color: "#06101F"

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: root.divider
            }

            Text {
                anchors.centerIn: parent
                text: "LEFT / RIGHT  CHOOSE     X  CONFIRM     O  CANCEL"
                color: root.neutronCyan
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 0.7
            }
        }
    }
}
