import QtQuick 2.15

Item {
    id: root

    /*
        Shared NeutronOS controller identity + battery presentation.

        Reuse this component unchanged on LoginScreen and later above the
        Console uptime card. The backend supplies the verified controller type,
        Bluetooth address and live battery percentage.
    */

    property var controllerBackend: null

    property color neutronRed: "#ff3040"
    property color chargingGreen: "#22ff88"
    property color textWhite: "#f4fbff"
    property color mutedWhite: "#a9bfd0"
    property color panelDark: "#08111f"

    /*
        Presentation controls. Login uses the full controller silhouette.
        System Overview reuses the same battery logic in compact platform mode.
    */
    property bool compact: false
    property bool platformSymbolMode: false
    property bool showControllerType: true
    property bool showSeparators: true

    readonly property int statusFontSize: compact ? 17 : 24
    readonly property int segmentWidth: compact ? 15 : 24
    readonly property int segmentHeight: compact ? 30 : 42
    readonly property int segmentSpacing: compact ? 4 : 7

    readonly property bool controllerConnected: {
        try {
            return controllerBackend &&
                   controllerBackend.controllerConnected === true
        } catch (error) {
            return false
        }
    }

    readonly property int batteryPercent: {
        try {
            if (!controllerBackend)
                return -1

            if (controllerBackend.controllerBatteryAvailable !== undefined &&
                    !controllerBackend.controllerBatteryAvailable)
                return -1

            var value = Number(controllerBackend.controllerBatteryPercent)

            if (isNaN(value))
                return -1

            return Math.max(0, Math.min(100, Math.round(value)))
        } catch (error) {
            return -1
        }
    }

    readonly property string controllerType: {
        try {
            if (controllerBackend &&
                    controllerBackend.controllerType !== undefined) {
                var verifiedType = String(controllerBackend.controllerType || "").trim()

                if (verifiedType.length > 0 &&
                        verifiedType.toLowerCase() !== "controller")
                    return verifiedType
            }

            if (controllerBackend &&
                    controllerBackend.controllerName !== undefined) {
                var rawName = String(controllerBackend.controllerName || "").trim()

                if (rawName.length > 0 &&
                        rawName.toLowerCase() !== "none")
                    return rawName
            }
        } catch (error) {
        }

        return "Controller"
    }

    readonly property string controllerModelLabel: {
        var model = String(controllerType || "").trim()
        model = model.replace(/DualShock\s*4/i, "DualShock4")
        model = model.replace(/DualShock\s*3/i, "DualShock3")
        model = model.replace(/Wireless Controller/i, "Controller")
        return model.length > 0 ? model : "Controller"
    }

    readonly property string controllerFamily: {
        var type = controllerType.toLowerCase()

        if (type.indexOf("dualshock") >= 0 ||
                type.indexOf("dualsense") >= 0 ||
                type.indexOf("playstation") >= 0 ||
                type.indexOf("sony") >= 0)
            return "playstation"

        if (type.indexOf("xbox") >= 0)
            return "xbox"

        if (type.indexOf("switch") >= 0 ||
                type.indexOf("nintendo") >= 0 ||
                type.indexOf("joy-con") >= 0)
            return "nintendo"

        if (type.indexOf("8bitdo") >= 0)
            return "8bitdo"

        return "generic"
    }

    readonly property string controllerBadge: {
        if (controllerFamily === "playstation")
            return "PS"

        if (controllerFamily === "xbox")
            return "XB"

        if (controllerFamily === "nintendo")
            return "NS"

        if (controllerFamily === "8bitdo")
            return "8B"

        return ""
    }

    readonly property int litSegments: {
        if (batteryPercent < 0)
            return 0

        if (batteryPercent >= 80)
            return 5

        if (batteryPercent >= 60)
            return 4

        if (batteryPercent >= 40)
            return 3

        if (batteryPercent > 20)
            return 2

        return 1
    }

    readonly property bool lowBattery:
        batteryPercent >= 0 && batteryPercent <= 20

    readonly property bool charging: {
        try {
            return controllerBackend &&
                   controllerBackend.controllerCharging === true
        } catch (error) {
            return false
        }
    }

    property real energyPulse: 0.0
    property real lowBlink: 0.0

    visible: controllerConnected
    implicitWidth: statusRow.implicitWidth
    implicitHeight: compact ? 52 : 68

    SequentialAnimation on energyPulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.0
            to: 1.0
            duration: root.charging ? 620 : 1150
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.0
            duration: root.charging ? 620 : 1150
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on lowBlink {
        running: root.visible && root.lowBattery && !root.charging
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.0
            to: 1.0
            duration: 420
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.0
            duration: 420
            easing.type: Easing.InOutQuad
        }
    }

    Row {
        id: statusRow

        anchors.verticalCenter: parent.verticalCenter
        spacing: root.compact ? 8 : 14

        /* Controller icon. The badge adapts to the verified controller family. */
        Item {
            id: controllerIcon

            width: root.platformSymbolMode ? 0 : (root.compact ? 50 : 72)
            height: root.compact ? 38 : 48
            visible: !root.platformSymbolMode

            Rectangle {
                anchors.centerIn: parent
                width: 62
                height: 28
                radius: 13
                color: root.panelDark
                border.width: 2
                border.color: root.textWhite
            }

            Rectangle {
                x: 4
                y: 22
                width: 22
                height: 24
                radius: 10
                rotation: 19
                color: root.panelDark
                border.width: 2
                border.color: root.textWhite
            }

            Rectangle {
                x: 46
                y: 22
                width: 22
                height: 24
                radius: 10
                rotation: -19
                color: root.panelDark
                border.width: 2
                border.color: root.textWhite
            }

            Rectangle {
                x: 17
                y: 20
                width: 14
                height: 4
                radius: 2
                color: root.charging ? root.chargingGreen : root.neutronRed
            }

            Rectangle {
                x: 22
                y: 15
                width: 4
                height: 14
                radius: 2
                color: root.charging ? root.chargingGreen : root.neutronRed
            }

            Rectangle {
                x: 49
                y: 16
                width: 5
                height: 5
                radius: 2.5
                color: root.neutronRed
            }

            Rectangle {
                x: 56
                y: 23
                width: 5
                height: 5
                radius: 2.5
                color: root.textWhite
            }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                text: root.controllerBadge
                visible: text.length > 0
                color: root.textWhite
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.8
            }

            Rectangle {
                anchors.centerIn: parent
                width: 76 + root.energyPulse * 8
                height: 52 + root.energyPulse * 6
                radius: height / 2
                color: root.charging ? root.chargingGreen : root.neutronRed
                opacity: 0.025 + root.energyPulse * (root.charging ? 0.095 : 0.045)
                z: -1
            }
        }

        Item {
            id: platformSymbol

            width: root.platformSymbolMode ? (root.compact ? 48 : 62) : 0
            height: root.compact ? 40 : 48
            visible: root.platformSymbolMode

            Rectangle {
                anchors.centerIn: parent
                width: root.compact ? 40 : 52
                height: width
                radius: 13
                color: root.panelDark
                border.width: 2
                border.color: root.charging ? root.chargingGreen : root.neutronRed

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 8 + root.energyPulse * 6
                    height: width
                    radius: 16
                    color: root.charging ? root.chargingGreen : root.neutronRed
                    opacity: 0.035 + root.energyPulse * 0.070
                    z: -1
                }

                Text {
                    anchors.centerIn: parent
                    text: root.controllerBadge.length > 0
                          ? root.controllerBadge
                          : "OS"
                    color: root.textWhite
                    font.pixelSize: root.compact ? 15 : 18
                    font.bold: true
                    font.letterSpacing: 0.8
                }
            }
        }

        Text {
            visible: root.showSeparators
            anchors.verticalCenter: parent.verticalCenter
            text: ":"
            color: root.mutedWhite
            font.pixelSize: root.statusFontSize
            font.bold: true
        }

        Text {
            id: typeLabel

            anchors.verticalCenter: parent.verticalCenter
            visible: root.showControllerType
            text: root.controllerModelLabel
            color: root.textWhite
            font.pixelSize: root.statusFontSize
            font.bold: true
            font.letterSpacing: 1.0
        }

        Text {
            visible: root.showSeparators && root.showControllerType
            anchors.verticalCenter: parent.verticalCenter
            text: ":"
            color: root.mutedWhite
            font.pixelSize: root.statusFontSize
            font.bold: true
        }

        Row {
            id: segmentRow

            anchors.verticalCenter: parent.verticalCenter
            spacing: root.segmentSpacing

            Repeater {
                model: 5

                Item {
                    id: segmentHost

                    property int segmentIndex: index

                    width: root.segmentWidth
                    height: root.segmentHeight

                    readonly property bool activeSegment:
                        root.batteryPercent >= 0 && segmentIndex < root.litSegments

                    readonly property bool blinkingLowSegment:
                        root.lowBattery && segmentIndex === 0

                    readonly property color segmentColor: {
                        if (root.charging && activeSegment)
                            return root.chargingGreen

                        if (blinkingLowSegment)
                            return root.lowBlink < 0.5
                                   ? root.neutronRed
                                   : root.textWhite

                        return activeSegment
                               ? root.neutronRed
                               : root.textWhite
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + (root.compact ? 8 : 8) + root.energyPulse * 5
                        height: parent.height + (root.compact ? 8 : 8) + root.energyPulse * 6
                        radius: root.compact ? 6 : 9
                        color: segmentHost.segmentColor
                        opacity: segmentHost.activeSegment ||
                                 segmentHost.blinkingLowSegment
                                 ? 0.08 + root.energyPulse * (root.charging ? 0.20 : 0.12)
                                 : 0.035
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: root.compact ? 5 : 7
                        color: segmentHost.segmentColor
                        opacity: segmentHost.activeSegment ||
                                 segmentHost.blinkingLowSegment
                                 ? 0.94
                                 : 0.82
                        border.width: 1
                        border.color: segmentHost.activeSegment ||
                                      segmentHost.blinkingLowSegment
                                      ? "#ffffd7dc"
                                      : "#ffccd8e2"

                        scale: segmentHost.activeSegment && (root.charging || root.lowBattery)
                               ? 1.0 + root.energyPulse * 0.055
                               : 1.0

                        Behavior on color {
                            ColorAnimation {
                                duration: 110
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: root.showSeparators
            anchors.verticalCenter: parent.verticalCenter
            text: ":"
            color: root.mutedWhite
            font.pixelSize: root.statusFontSize
            font.bold: true
        }

        Text {
            id: percentLabel

            anchors.verticalCenter: parent.verticalCenter
            text: root.batteryPercent >= 0
                  ? root.batteryPercent + "%" + (root.charging ? " ⚡" : "")
                  : "--%"
            color: root.charging
                   ? root.chargingGreen
                   : (root.lowBattery && root.lowBlink < 0.5
                      ? root.neutronRed
                      : root.textWhite)
            font.pixelSize: root.statusFontSize
            font.bold: true
            font.letterSpacing: root.compact ? 0.4 : 1.0

            scale: root.charging || root.lowBattery
                   ? 1.0 + root.energyPulse * 0.045
                   : 1.0

            opacity: root.charging
                     ? 0.66 + root.energyPulse * 0.34
                     : 1.0

            Behavior on color {
                ColorAnimation {
                    duration: 110
                }
            }
        }
    }
}
