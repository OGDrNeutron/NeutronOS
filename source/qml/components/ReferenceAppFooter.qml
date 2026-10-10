import QtQuick 2.15

Rectangle {
    id: root

    property string hintText: ""
    // Use the global backend by default so every app using the shared footer
    // receives the same live controller state. Explicit app bindings remain
    // supported for compatibility.
    property var controllerBackend: (typeof controllerManager !== "undefined")
                                    ? controllerManager : null
    property var clockBackend: (typeof clockExperienceManager !== "undefined")
                               ? clockExperienceManager : null
    property date fallbackClockNow: new Date()
    property real uiScale: 1.0

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
    readonly property string batteryState: {
        try {
            return controllerBackend && controllerBackend.controllerBatteryState !== undefined
                   ? String(controllerBackend.controllerBatteryState || "").trim().toLowerCase()
                   : ""
        } catch (error) { return "" }
    }
    // Some controller drivers report Full or Not Charging while external power
    // is still attached. Treat those as powered so the footer does not show a
    // red discharging icon while the controller is physically on charge.
    readonly property bool charging: {
        try {
            if (controllerBackend && controllerBackend.controllerCharging === true)
                return true
            return batteryState === "charging" ||
                   batteryState === "full" ||
                   batteryState === "not charging"
        } catch (error) { return false }
    }
    readonly property bool discharging: batteryState === "discharging"
    // The footer is intentionally binary for the controller icon: explicit
    // Discharging is red; every powered/charging/indeterminate state is green.
    // This avoids a false red icon when hid-playstation reports Full,
    // Not Charging, or temporarily Unknown while external power is attached.
    readonly property bool chargeVisualActive: !discharging
    readonly property color batteryTone: chargeVisualActive ? "#42E69C" : "#FF4D63"
    height: 72
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
                source: Qt.resolvedUrl("../../themes/Default/atom.svg")
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
                running: root.visible && footerAtom.status === Image.Ready
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
        spacing: 12

        Row {
            visible: root.controllerConnected
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Item {
                width: 82
                height: 52
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    id: premiumControllerIcon
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.width
                    source: root.chargeVisualActive
                            ? Qt.resolvedUrl("controller-premium-green.png")
                            : Qt.resolvedUrl("controller-premium-red.png")
                    sourceSize.width: 192
                    sourceSize.height: 192
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    cache: true
                    asynchronous: false
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: 5
                    Rectangle {
                        width: 8
                        height: 27
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
                font.pixelSize: 19
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
