import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    /*
        ============================================================
                                CLOCK CARD
        ============================================================

        Production card for Console header/user/time area.

        Preserved from original:
            - Controller status line
            - Controller battery shell/fill
            - Charging indicator
            - Time text
            - Date text
            - Controller type detection
            - Battery color thresholds

        Next-gen updates:
            - Safe controllerManager access
            - Optional self-updating clock when timeText/dateText are not supplied
            - No hard crash if controllerManager is missing
            - Works with aliases from newer ControllerManager properties
            - Animations/timer pause when hidden
            - Cleaner scaling for 720p/1080p/4K
            - No mouse assumptions
    */

    property string timeText: ""
    property string dateText: ""

    /*
        If Console provides timeText/dateText, this card uses those.
        If not, ClockCard can update itself.
    */
    property bool useInternalClockWhenEmpty: true
    property bool showControllerStatus: true
    property bool showBatteryStatus: true
    property bool animationsEnabled: visible && enabled

    property string fallbackOfflineText: "Controller Offline"
    property string fallbackUnknownBatteryText: "--% · Unknown"
    property string fallbackOfflineBatteryText: "--% · Offline"

    property color controllerOnlineColor: "#22ff88"
    property color controllerOfflineColor: "#8aa6c8"
    property color chargingColor: "#7df9ff"
    property color lowBatteryColor: "#ff3040"
    property color mediumBatteryColor: "#f5c542"
    property color highBatteryColor: "#22ff88"
    property color unknownBatteryColor: "#8aa6c8"

    property real pulse: 0.55

    accent: "#c084fc"

    implicitWidth: 270
    implicitHeight: showControllerStatus ? 168 : 110

    /*
        ============================================================
                            INTERNAL CLOCK
        ============================================================
    */

    property string internalTimeText: ""
    property string internalDateText: ""

    readonly property string shownTimeText: {
        if (String(timeText).length > 0)
            return timeText

        if (useInternalClockWhenEmpty)
            return internalTimeText

        return ""
    }

    readonly property string shownDateText: {
        if (String(dateText).length > 0)
            return dateText

        if (useInternalClockWhenEmpty)
            return internalDateText

        return ""
    }

    Timer {
        id: clockTimer

        interval: 1000
        repeat: true
        running: root.visible && root.useInternalClockWhenEmpty

        triggeredOnStart: true

        onTriggered: root.refreshInternalClock()
    }

    function refreshInternalClock() {
        var now = new Date()

        var hours = now.getHours()
        var minutes = now.getMinutes()
        var suffix = hours >= 12 ? "PM" : "AM"

        var displayHour = hours % 12

        if (displayHour === 0)
            displayHour = 12

        var minuteText = minutes < 10 ? "0" + minutes : String(minutes)

        internalTimeText = displayHour + ":" + minuteText + " " + suffix

        var days = [
                    "Sunday",
                    "Monday",
                    "Tuesday",
                    "Wednesday",
                    "Thursday",
                    "Friday",
                    "Saturday"
                ]

        var months = [
                    "January",
                    "February",
                    "March",
                    "April",
                    "May",
                    "June",
                    "July",
                    "August",
                    "September",
                    "October",
                    "November",
                    "December"
                ]

        internalDateText =
                days[now.getDay()] + ", " +
                months[now.getMonth()] + " " +
                now.getDate()
    }

    /*
        ============================================================
                            ANIMATION
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled && root.controllerConnected()
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.42
            to: 1.0
            duration: 1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.42
            duration: 1800
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            LAYOUT
        ============================================================
    */

    Column {
        id: contentColumn

        anchors.centerIn: parent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        spacing: Math.max(5, root.height * 0.032)

        Column {
            id: controllerCluster

            visible: root.showControllerStatus

            anchors.horizontalCenter: parent.horizontalCenter

            width: parent.width

            spacing: 3

            Row {
                id: controllerRow

                anchors.horizontalCenter: parent.horizontalCenter

                width: parent.width
                height: 20

                spacing: 7

                Item {
                    id: controllerGlyph

                    width: 25
                    height: 16

                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.centerIn: parent

                        width: 19
                        height: 11
                        radius: 6

                        color: "#02060D"

                        border.width: 1
                        border.color: root.controllerConnected()
                                      ? root.controllerOnlineColor
                                      : "#66758a"

                        opacity: root.controllerConnected()
                                 ? 0.75 + root.pulse * 0.25
                                 : 0.62
                    }

                    Rectangle {
                        x: 1
                        y: 8

                        width: 8
                        height: 7
                        radius: 4

                        color: "#02060D"

                        border.width: 1
                        border.color: root.controllerConnected()
                                      ? root.controllerOnlineColor
                                      : "#66758a"

                        opacity: root.controllerConnected()
                                 ? 0.75 + root.pulse * 0.25
                                 : 0.62
                    }

                    Rectangle {
                        x: 16
                        y: 8

                        width: 8
                        height: 7
                        radius: 4

                        color: "#02060D"

                        border.width: 1
                        border.color: root.controllerConnected()
                                      ? root.controllerOnlineColor
                                      : "#66758a"

                        opacity: root.controllerConnected()
                                 ? 0.75 + root.pulse * 0.25
                                 : 0.62
                    }

                    Rectangle {
                        visible: root.controllerConnected()

                        anchors.centerIn: parent

                        width: parent.width + 10
                        height: parent.height + 8
                        radius: 12

                        color: "transparent"

                        border.width: 1
                        border.color: root.controllerOnlineColor

                        opacity: root.pulse * 0.26
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter

                    width: Math.max(0, controllerRow.width - controllerGlyph.width - controllerRow.spacing)

                    text: root.controllerConnected()
                          ? root.controllerType() + " Controller Connected"
                          : root.fallbackOfflineText

                    color: root.controllerConnected()
                           ? root.controllerOnlineColor
                           : root.controllerOfflineColor

                    font.pixelSize: Math.max(10, Math.min(13, root.height * 0.072))
                    font.bold: true
                    font.letterSpacing: 0.8

                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            Row {
                id: batteryRow

                visible: root.showBatteryStatus

                anchors.horizontalCenter: parent.horizontalCenter

                height: 20

                spacing: 7

                Item {
                    id: batteryGlyph

                    width: 47
                    height: 17

                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        id: batteryShell

                        x: 0
                        y: 2

                        width: 41
                        height: 13
                        radius: 4

                        color: "#02060D"

                        border.width: 1
                        border.color: root.batteryFillColor()

                        opacity: root.controllerConnected() ? 1.0 : 0.45
                    }

                    Rectangle {
                        x: 42
                        y: 6

                        width: 4
                        height: 5
                        radius: 2

                        color: root.batteryFillColor()

                        opacity: root.controllerConnected() ? 0.9 : 0.35
                    }

                    Rectangle {
                        anchors.left: batteryShell.left
                        anchors.verticalCenter: batteryShell.verticalCenter
                        anchors.leftMargin: 3

                        width: root.batteryFillWidth()
                        height: 7
                        radius: 3

                        color: root.batteryFillColor()

                        opacity: root.controllerConnected() && root.batteryPercent() >= 0
                                 ? 0.92
                                 : 0.18

                        Behavior on width {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: batteryShell

                        visible: root.controllerCharging()

                        text: "⚡"
                        color: "white"

                        font.pixelSize: 9
                        font.bold: true
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.batteryStatusText()

                    color: root.controllerConnected()
                           ? root.batteryFillColor()
                           : root.controllerOfflineColor

                    font.pixelSize: Math.max(10, Math.min(13, root.height * 0.072))
                    font.bold: true
                    font.letterSpacing: 0.6

                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Text {
            id: timeLabel

            anchors.horizontalCenter: parent.horizontalCenter

            width: parent.width

            text: root.shownTimeText

            color: "white"

            font.pixelSize: Math.max(28, Math.min(44, root.height * 0.19))
            font.bold: true
            font.letterSpacing: 0.4

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            style: Text.Outline
            styleColor: "#AA000000"
        }

        Text {
            id: dateLabel

            anchors.horizontalCenter: parent.horizontalCenter

            width: parent.width - 18

            text: root.shownDateText

            color: "#9fd8ff"

            font.pixelSize: Math.max(11, Math.min(17, root.height * 0.078))
            font.bold: true
            font.letterSpacing: 0.5

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: 0.92
        }
    }

    /*
        ============================================================
                            CONTROLLER HELPERS
        ============================================================
    */

    function controllerBackend() {
        try {
            if (typeof controllerManager !== "undefined" && controllerManager)
                return controllerManager
        } catch (e) {
        }

        return null
    }

    function controllerConnected() {
        var backend = controllerBackend()

        if (!backend)
            return false

        try {
            return !!backend.controllerConnected
        } catch (e) {
            return false
        }
    }

    function controllerName() {
        var backend = controllerBackend()

        if (!backend)
            return ""

        try {
            return String(backend.controllerName || "")
        } catch (e) {
            return ""
        }
    }

    function controllerType() {
        var name = controllerName().toLowerCase()

        if (name.indexOf("dualsense") >= 0 ||
                name.indexOf("ps5") >= 0) {
            return "PS5"
        }

        if (name.indexOf("dualshock") >= 0 ||
                name.indexOf("ps4") >= 0 ||
                name.indexOf("wireless controller") >= 0 ||
                name.indexOf("playstation") >= 0 ||
                name.indexOf("sony") >= 0) {
            return "PS4"
        }

        if (name.indexOf("xbox") >= 0)
            return "Xbox"

        if (name.indexOf("8bitdo") >= 0)
            return "8BitDo"

        if (name.length > 0)
            return "Gamepad"

        return "Controller"
    }

    function batteryPercent() {
        var backend = controllerBackend()

        if (!backend)
            return -1

        try {
            if (backend.controllerBatteryAvailable === false)
                return -1

            var pct = Number(backend.controllerBatteryPercent)

            if (isNaN(pct) || pct < 0)
                return -1

            return Math.max(0, Math.min(100, pct))
        } catch (e) {
            return -1
        }
    }

    function controllerCharging() {
        var backend = controllerBackend()

        if (!backend)
            return false

        try {
            if (backend.controllerCharging === true)
                return true

            var state = String(backend.controllerBatteryState || "").toLowerCase()

            return state === "charging"
        } catch (e) {
            return false
        }
    }

    function batteryState() {
        var backend = controllerBackend()

        if (!backend)
            return "Unknown"

        try {
            var state = String(backend.controllerBatteryState || "Unknown")

            if (state.length <= 0)
                return "Unknown"

            return state
        } catch (e) {
            return "Unknown"
        }
    }

    function batteryStatusText() {
        if (!controllerConnected())
            return fallbackOfflineBatteryText

        var pct = batteryPercent()

        if (pct < 0)
            return fallbackUnknownBatteryText

        if (controllerCharging())
            return pct + "% · Charging"

        return pct + "% · " + batteryState()
    }

    function batteryFillWidth() {
        var pct = batteryPercent()

        if (pct < 0)
            return 0

        return Math.max(3, Math.min(35, 35 * (pct / 100.0)))
    }

    function batteryFillColor() {
        var pct = batteryPercent()

        if (!controllerConnected())
            return "#66758a"

        if (controllerCharging())
            return chargingColor

        if (pct < 0)
            return unknownBatteryColor

        if (pct <= 20)
            return lowBatteryColor

        if (pct <= 45)
            return mediumBatteryColor

        return highBatteryColor
    }

    Component.onCompleted: {
        if (useInternalClockWhenEmpty)
            refreshInternalClock()
    }
}