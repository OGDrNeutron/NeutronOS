import QtQuick 2.15

Rectangle {
    id: root

    property string hintText: ""
    property var controllerBackend: null
    property var clockBackend: (typeof clockExperienceManager !== "undefined")
                               ? clockExperienceManager : null
    property date fallbackClockNow: new Date()

    readonly property bool controllerConnected: {
        try { return controllerBackend && controllerBackend.controllerConnected === true }
        catch (error) { return false }
    }
    readonly property int batteryPercent: {
        try {
            if (!controllerBackend || controllerBackend.controllerBatteryAvailable === false)
                return -1
            var value = Number(controllerBackend.controllerBatteryPercent)
            return isNaN(value) ? -1 : Math.max(0, Math.min(100, Math.round(value)))
        } catch (error) { return -1 }
    }
    readonly property int litBars: {
        if (batteryPercent < 0) return 0
        if (batteryPercent >= 100) return 5
        if (batteryPercent >= 80) return 4
        if (batteryPercent >= 60) return 3
        if (batteryPercent >= 40) return 2
        if (batteryPercent > 0) return 1
        return 0
    }
    readonly property bool charging: {
        try { return controllerBackend && controllerBackend.controllerCharging === true }
        catch (error) { return false }
    }
    readonly property color batteryTone: charging ? "#42E69C" :
                                                 (batteryPercent < 0 ? "#71808B" :
                                                  batteryPercent >= 60 ? "#42E69C" :
                                                  batteryPercent >= 30 ? "#FFD166" : "#FF4D63")

    color: "#030810F2"
    border.width: 1
    border.color: "#21303A"
    radius: 5

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Item {
            id: footerAtomSpinner
            width: 31
            height: 31
            anchors.verticalCenter: parent.verticalCenter
            transformOrigin: Item.Center

            Image {
                id: footerAtom
                anchors.fill: parent
                source: Qt.resolvedUrl("../../../../themes/Default/atom.svg")
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                smooth: true
                cache: true
            }

            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: 10000
                loops: Animation.Infinite
                running: footerAtom.status === Image.Ready
                easing.type: Easing.Linear
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text { text: "Neutron"; color: "#F4FBFF"; font.pixelSize: 22; font.bold: true }
            Text { text: "OS"; color: "#FF3E4D"; font.pixelSize: 22; font.bold: true }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 8
        Text { text: "Secure"; color: "#D6DADF"; font.pixelSize: 17; font.bold: true }
        Text { text: "|"; color: "#6F7A82"; font.pixelSize: 17; font.bold: true }
        Text { text: "Intelligent"; color: "#D6DADF"; font.pixelSize: 17; font.bold: true }
        Text { text: "|"; color: "#6F7A82"; font.pixelSize: 17; font.bold: true }
        Text { text: "Unstoppable"; color: "#FF3E4D"; font.pixelSize: 17; font.bold: true }
    }

    Row {
        id: rightStatus
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Row {
            visible: root.controllerConnected
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Item {
                width: 34
                height: 24
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 4
                    width: 31
                    height: 16
                    radius: 7
                    color: "#07111A"
                    border.width: 1
                    border.color: "#AFC0CB"
                }
                Rectangle { x: 2; y: 13; width: 9; height: 8; radius: 4; color: "#07111A"; border.width: 1; border.color: "#AFC0CB"; rotation: 18 }
                Rectangle { x: 23; y: 13; width: 9; height: 8; radius: 4; color: "#07111A"; border.width: 1; border.color: "#AFC0CB"; rotation: -18 }
                Text { x: 7; y: 5; text: "+"; color: "#AFC0CB"; font.pixelSize: 10; font.bold: true }
                Text { x: 23; y: 7; text: "•"; color: "#AFC0CB"; font.pixelSize: 10; font.bold: true }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Repeater {
                    model: 5
                    Rectangle {
                        width: 5
                        height: 17
                        radius: 2
                        color: index < root.litBars ? root.batteryTone : "#26323A"
                        border.width: 1
                        border.color: index < root.litBars ? root.batteryTone : "#3A4852"
                        opacity: index < root.litBars ? 1.0 : 0.65
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.batteryPercent >= 0 ? String(root.batteryPercent) + "%" : "--%"
                color: root.batteryTone
                font.pixelSize: 16
                font.bold: true
            }
        }

        Rectangle {
            visible: root.controllerConnected
            width: 1
            height: 25
            anchors.verticalCenter: parent.verticalCenter
            color: "#28343C"
        }

        Text {
            id: clockText
            anchors.verticalCenter: parent.verticalCenter
            text: root.clockBackend
                  ? String(root.clockBackend.currentTimeText || "--:--")
                  : Qt.formatTime(root.fallbackClockNow, "h:mm AP")
            color: "#D6DADF"
            font.pixelSize: 20
        }
    }

    Timer {
        interval: 1000
        running: root.visible && !root.clockBackend
        repeat: true
        onTriggered: root.fallbackClockNow = new Date()
    }
}
