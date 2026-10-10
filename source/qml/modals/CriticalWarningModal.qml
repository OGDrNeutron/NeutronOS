import QtQuick 2.15

Item {
    id: root

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 32000

    property string warningTitle: "CRITICAL SYSTEM WARNING"
    property string warningMessage: ""
    property string warningSource: "SYSTEM"
    property string warningTime: ""

    signal dismissed()

    function openWarning(title, message, source) {
        warningTitle = String(title || "CRITICAL SYSTEM WARNING")
        warningMessage = String(message || "NeutronOS detected a condition that needs attention.")
        warningSource = String(source || "SYSTEM").toUpperCase()
        warningTime = Qt.formatDateTime(new Date(), "MMM d • h:mm:ss AP")
        visible = true
        forceActiveFocus()
    }

    function close() {
        if (!visible)
            return
        visible = false
        dismissed()
    }

    function handleControllerPressed(button) {
        var action = String(button || "").toLowerCase()
        if (action === "primary" || action === "x" || action === "cross" ||
                action === "cancel" || action === "o" || action === "circle" ||
                action === "system" || action === "start" || action === "options") {
            close()
        }
        return true
    }

    function handleControllerReleased(button) { return visible }

    Rectangle {
        anchors.fill: parent
        color: "#E006080D"
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 180, 1000)
        height: 520
        radius: 38
        color: "#F20A111E"
        border.width: 4
        border.color: "#FF3048"

        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            radius: 30
            color: "transparent"
            border.width: 1
            border.color: "#6AFF3048"
        }

        SequentialAnimation on scale {
            running: root.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0.995; to: 1.012; duration: 850; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.012; to: 0.995; duration: 850; easing.type: Easing.InOutSine }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 44
            spacing: 20

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 88
                height: 88
                radius: 44
                color: "#4AFF3048"
                border.width: 3
                border.color: "#FF3048"

                Text {
                    anchors.centerIn: parent
                    text: "!"
                    color: "#FFFFFF"
                    font.pixelSize: 54
                    font.bold: true
                }
            }

            Text {
                width: parent.width
                text: root.warningTitle
                color: "#FF4055"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 34
                font.bold: true
                font.letterSpacing: 1.7
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                height: 130
                text: root.warningMessage
                color: "#FFFFFF"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 21
                font.bold: true
                lineHeight: 1.16
                wrapMode: Text.WordWrap
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, 610)
                height: 48
                radius: 24
                color: "#201B2638"
                border.width: 1
                border.color: "#754C6585"

                Text {
                    anchors.centerIn: parent
                    text: root.warningSource + "  •  " + root.warningTime
                    color: "#AFC8E5"
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.1
                }
            }

            Text {
                width: parent.width
                text: "X  ACKNOWLEDGE  •  O  DISMISS\nLogs integration will be added to this warning panel in a later patch."
                color: "#7DF9FF"
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 13
                font.bold: true
                lineHeight: 1.3
            }
        }
    }

    Keys.onPressed: function(event) {
        if (!visible)
            return
        event.accepted = true
        close()
    }
}
