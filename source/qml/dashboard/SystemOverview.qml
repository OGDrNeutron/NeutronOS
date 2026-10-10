import QtQuick 2.15
import QtQuick.Layouts 1.15
import "../systemwidgets"
import "../components"

Rectangle {
    id: root

    property var activeUser
    property var controllerBackend:
        (typeof controllerManager !== "undefined")
        ? controllerManager
        : null
    property string currentTime: ""
    property string currentDate: ""

    property string currentTimezoneLabel: ""
    property color clockTextTint: "#FFFFFF"
    property color clockDateTint: "#9FD8FF"
    property color clockTimezoneTint: "#7DF9FF"
    property int clockScale: 100
    property bool showClockDate: true
    property bool showClockTimezone: false

    property bool sectionFocused: false
    property int selectedSystem: 0
    property int armedIndex: -1

    property bool activeAppSelectionMode: false
    property int selectedActiveApp: 0

    /*
        Console.qml disables SystemOverview while the lock screen or AppHost
        owns the display. TempGauge and NetworkPulseCore are the only
        continuous animations in this component.
    */
    readonly property bool consoleActive: visible && enabled
    property bool animationsEnabled: consoleActive

    /*
        Live CPU and memory snapshots.

        SystemMonitor performs the actual /proc sampling every two seconds.
        This component only copies the already-cached values into ordinary
        QML properties when the backend emits its change signals. A low-cost
        2.5-second fallback read keeps the display current on Qt builds where
        context-property dependency tracking is conservative.

        The fallback does not launch a command, parse /proc, or request a new
        backend sample, so it adds negligible CPU overhead.
    */
    readonly property var liveSystemMonitor:
        (typeof systemMonitor !== "undefined" && systemMonitor)
        ? systemMonitor
        : null

    property int liveCpuPercent: 0
    property string liveCpuText: ""

    property int liveRamPercent: 0
    property real liveRamUsedBytes: 0
    property real liveRamTotalBytes: 0
    property real liveRamAvailableBytes: 0
    property string liveRamText: ""
    property string liveRamUsed: ""
    property string liveRamTotal: ""

    readonly property var liveNetworkManager:
        (typeof networkManager !== "undefined" && networkManager)
        ? networkManager
        : null

    property string liveNetworkDownload: "0 B/s"
    property string liveNetworkUpload: "0 B/s"
    property string liveNetworkTestDownload: "--"
    property string liveNetworkTestUpload: "--"
    property string liveNetworkTestLatency: "--"
    property string liveNetworkTestAge: "WAITING FOR TEST"
    property bool liveNetworkTestRunning: false

    function normalizedPercent(value) {
        var number = Number(value)

        if (isNaN(number))
            return 0

        return Math.max(
            0,
            Math.min(
                100,
                Math.round(number)
            )
        )
    }

    function refreshLiveCpu() {
        var monitor = root.liveSystemMonitor

        if (!monitor)
            return

        try {
            var candidate = monitor.cpuPercent

            if (candidate === undefined || candidate === null)
                candidate = monitor.cpuUsagePercent

            if (candidate === undefined || candidate === null)
                candidate = monitor.cpuUsage

            var percent = root.normalizedPercent(candidate)
            var text = root.cleanText(monitor.cpu)

            /*
                Keep compatibility with an older backend that only exposed the
                formatted CPU string. Prefer the exact integer property when it
                is valid, but never leave a nonzero text sample displayed as 0.
            */
            var parsedText = parseFloat(
                String(text).replace("%", "")
            )

            if (percent === 0 &&
                    !isNaN(parsedText) &&
                    parsedText > 0) {
                percent = root.normalizedPercent(parsedText)
            }

            root.liveCpuPercent = percent
            root.liveCpuText =
                text.length > 0 && text !== "--"
                ? text
                : percent + "%"
        } catch (error) {
            /*
                Keep the last good cached value if the backend is temporarily
                unavailable during shell startup or shutdown.
            */
        }
    }

    function requestCpuSample() {
        var monitor = root.liveSystemMonitor

        if (!monitor)
            return

        try {
            if (typeof monitor.refreshCpuMonitor === "function") {
                monitor.refreshCpuMonitor()
            } else if (typeof monitor.refresh === "function") {
                monitor.refresh()
            }
        } catch (error) {
            /* Backend may be disappearing during shell shutdown. */
        }
    }

    function refreshLiveMemory() {
        var monitor = root.liveSystemMonitor

        if (!monitor)
            return

        try {
            var totalBytes = Number(monitor.ramTotalBytes)
            var availableBytes = Number(monitor.ramAvailableBytes)

            if (isNaN(totalBytes) || totalBytes <= 0)
                totalBytes = Number(monitor.memoryTotalBytes)

            if (isNaN(availableBytes) || availableBytes < 0)
                availableBytes = Number(monitor.memoryAvailableBytes)

            if (!isNaN(totalBytes) &&
                    totalBytes > 0 &&
                    !isNaN(availableBytes)) {
                availableBytes = Math.max(
                    0,
                    Math.min(totalBytes, availableBytes)
                )

                root.liveRamTotalBytes = totalBytes
                root.liveRamAvailableBytes = availableBytes
                root.liveRamUsedBytes = totalBytes - availableBytes
                root.liveRamPercent = root.normalizedPercent(
                    100 * root.liveRamUsedBytes / totalBytes
                )
            } else {
                root.liveRamPercent = root.normalizedPercent(
                    monitor.ramPercent
                )
            }

            root.liveRamText = root.cleanText(monitor.ram)
            root.liveRamUsed = root.cleanText(monitor.ramUsed)
            root.liveRamTotal = root.cleanText(monitor.ramTotal)
        } catch (error) {
            /*
                Preserve the last valid values until SystemMonitor becomes
                available again.
            */
        }
    }

    function refreshLiveNetwork() {
        var monitor = root.liveSystemMonitor
        var manager = root.liveNetworkManager

        try {
            if (monitor) {
                root.liveNetworkDownload = root.cleanText(monitor.download || monitor.downloadSpeed) || "0 B/s"
                root.liveNetworkUpload = root.cleanText(monitor.upload || monitor.uploadSpeed) || "0 B/s"
            }
        } catch (monitorError) {}

        try {
            if (manager) {
                var down = Number(manager.downloadMbps)
                var up = Number(manager.uploadMbps)
                var latency = Number(manager.latencyMs)
                root.liveNetworkTestDownload = !isNaN(down) && down > 0 ? root.formatMbpsValue(down) : "--"
                root.liveNetworkTestUpload = !isNaN(up) && up > 0 ? root.formatMbpsValue(up) : "--"
                root.liveNetworkTestLatency = !isNaN(latency) && latency >= 0 ? Math.round(latency) + " ms" : "--"
                root.liveNetworkTestAge = root.cleanText(manager.speedTestLastRun) || "WAITING FOR TEST"
                root.liveNetworkTestRunning = Boolean(manager.speedTestRunning)
            }
        } catch (managerError) {}
    }

    function formatMbpsValue(value) {
        var number = Number(value)
        if (isNaN(number) || number <= 0)
            return "--"
        if (number >= 100)
            return number.toFixed(0) + " Mbps"
        if (number >= 10)
            return number.toFixed(1) + " Mbps"
        return number.toFixed(2) + " Mbps"
    }

    function refreshLiveMetrics() {
        root.refreshLiveCpu()
        root.refreshLiveMemory()
        root.refreshLiveNetwork()
    }

    Connections {
        target: root.liveSystemMonitor
        enabled: target !== null
        ignoreUnknownSignals: true

        function onCpuMonitorChanged() {
            root.refreshLiveCpu()
        }

        function onMemoryMonitorChanged() {
            root.refreshLiveMemory()
        }

        function onSystemChanged() {
            root.refreshLiveMetrics()
        }

        function onNetworkMonitorChanged() {
            root.refreshLiveNetwork()
        }
    }

    Connections {
        target: root.liveNetworkManager
        enabled: target !== null
        ignoreUnknownSignals: true

        function onSpeedTestRunningChanged() { root.refreshLiveNetwork() }
        function onSpeedTestResultsChanged() { root.refreshLiveNetwork() }
        function onSpeedTestStatusChanged() { root.refreshLiveNetwork() }
        function onNetworkDetailsChanged() { root.refreshLiveNetwork() }
        function onNetworkRevisionChanged() { root.refreshLiveNetwork() }
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.consoleActive

        onTriggered: {
            root.requestCpuSample()
            root.refreshLiveMetrics()
        }
    }

    onConsoleActiveChanged: {
        if (consoleActive) {
            requestCpuSample()
            refreshLiveMetrics()
        }
    }

    Component.onCompleted: {
        requestCpuSample()
        refreshLiveMetrics()
    }

    property int systemCardCount: 9

    property color neutronBlue: "#7df9ff"
    property color focusBlue: "#4da6ff"
    property color darkGlass: "#071426"
    property color dangerRed: "#ff3040"
    property color successGreen: "#22ff88"
    property color warningYellow: "#facc15"

    /*
        cardClicked is retained for compatibility with the current Console.
        The production Console modal router should use modalRequested.
    */
    signal cardClicked(string cardType, int index)
    signal modalRequested(string modalId, var context)

    height: parent ? parent.height * 0.235 : 254
    radius: 36
    color: "transparent"
    border.width: 0
    border.color: "transparent"
    clip: false

    /*
        ============================================================
                            TITLE
        ============================================================
    */

    Row {
        id: title

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 5

        spacing: 0
        z: 20

        /*
            Match the LoginScreen NeutronOS spectrum: hot red through
            magenta and violet into the cold neutron cyan endpoint.
        */
        Repeater {
            model: [
                ["S", "#ff3040"],
                ["Y", "#ff4ea8"],
                ["S", "#d946ef"],
                ["T", "#a855f7"],
                ["E", "#6366f1"],
                ["M", "#7df9ff"]
            ]

            Text {
                text: modelData[0]
                color: modelData[1]
                font.pixelSize: 27
                font.bold: true
            }
        }
    }

    Text {
        id: statusLine

        anchors.top: title.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: -3

        text: shownSystemMode() + "  •  " + shownThermalStatus()

        color: shownThermalStatus() === "No Throttle" ||
               shownThermalStatus() === "--"
               ? neutronBlue
               : dangerRed

        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 1
        z: 20
    }

    Text {
        id: selectionHint

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 34
        anchors.topMargin: 14

        visible: root.sectionFocused &&
                 (root.selectedSystem !== 3 || root.armedIndex >= 0)

        text: root.selectionHintText()
        color: root.armedIndex >= 0 ? "#ff9a9a" : neutronBlue

        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 1.5
        z: 30
    }

    /*
        ============================================================
                        SHARED FOCUS SHELL
        ============================================================
    */

    component FocusShell: Item {
        id: focusShell

        property int itemIndex: -1
        property string label: ""

        property bool selected: root.sectionFocused &&
                                root.selectedSystem === itemIndex

        property bool armed: root.armedIndex === itemIndex
        property real pulse: 0.5

        anchors.fill: parent
        z: 50
        visible: selected || armed

        SequentialAnimation on pulse {
            running: root.animationsEnabled && focusShell.armed
            loops: Animation.Infinite

            NumberAnimation {
                from: 0.35
                to: 1.0
                duration: 600
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                from: 1.0
                to: 0.35
                duration: 600
                easing.type: Easing.InOutSine
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -7

            radius: 28
            color: "transparent"

            border.width: armed ? 4 : 3
            border.color: armed ? root.dangerRed : root.focusBlue

            opacity: armed
                     ? 0.82 + focusShell.pulse * 0.18
                     : 0.92
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2

            radius: 23
            color: armed ? root.dangerRed : root.focusBlue

            opacity: armed
                     ? 0.08 + focusShell.pulse * 0.06
                     : 0.11
        }

        /*
            Selection is already communicated by the blue focus ring. The
            previous SELECT CPU / SELECT STORAGE banner duplicated that state
            and obscured the card edge. Keep a banner only for armed actions.
        */
        Rectangle {
            visible: armed && focusShell.itemIndex !== 3

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: -7

            height: 28
            radius: 14

            color: "#3A1116EE"

            border.width: 1
            border.color: root.dangerRed

            Text {
                anchors.centerIn: parent

                text: "ARMED  " + label
                color: "#FFD1D1"

                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.4
            }
        }
    }

    /*
        ============================================================
                    NETWORK PACKET / RADAR CORE
        ============================================================
    */

    component NetworkPulseCore: Item {
        id: netCore

        property int activity: Math.max(downloadActivity, uploadActivity)
        property int downloadActivity: 0
        property int uploadActivity: 0
        property int signalPercent: 0
        property bool connected: true
        property bool motionActive: false

        property real receivePhase: 0.0
        property real transmitPhase: 0.0
        property real reactorPulse: 0.35
        property real orbitRotation: 0.0

        readonly property color receiveColor: "#35E9FF"
        readonly property color transmitColor: "#9C7CFF"

        SequentialAnimation on reactorPulse {
            running: root.consoleActive && netCore.visible && netCore.connected
            loops: Animation.Infinite

            NumberAnimation {
                from: 0.22
                to: 1.0
                duration: netCore.motionActive ? 720 : 1450
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                from: 1.0
                to: 0.22
                duration: netCore.motionActive ? 720 : 1450
                easing.type: Easing.InOutSine
            }
        }

        NumberAnimation on receivePhase {
            running: root.consoleActive &&
                     netCore.visible &&
                     netCore.connected &&
                     netCore.downloadActivity > 0
            from: 0.0
            to: 1.0
            duration: Math.max(470, 1100 - netCore.downloadActivity * 52)
            loops: Animation.Infinite
            easing.type: Easing.Linear
        }

        NumberAnimation on transmitPhase {
            running: root.consoleActive &&
                     netCore.visible &&
                     netCore.connected &&
                     netCore.uploadActivity > 0
            from: 0.0
            to: 1.0
            duration: Math.max(500, 1180 - netCore.uploadActivity * 48)
            loops: Animation.Infinite
            easing.type: Easing.Linear
        }

        NumberAnimation on orbitRotation {
            running: root.consoleActive && netCore.visible && netCore.connected
            from: 0
            to: 360
            duration: netCore.motionActive ? 2600 : 5200
            loops: Animation.Infinite
            easing.type: Easing.Linear
        }

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: "#050E1AF2"
            border.width: 1
            border.color: netCore.connected ? "#3F8CCF99" : "#FF304088"

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - 2
                color: "#FFFFFF"
                opacity: 0.025
            }
        }

        /* Receive conduit: packets converge on the neutron reactor. */
        Item {
            id: receiveLane
            anchors.left: parent.left
            anchors.leftMargin: 86
            anchors.right: reactor.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            height: 24

            Repeater {
                model: 6

                Rectangle {
                    property real phase: (netCore.receivePhase + index * 0.18) % 1.0
                    visible: netCore.connected &&
                             index < Math.max(1, Math.ceil(netCore.downloadActivity / 2))
                    width: 7 + (index % 2) * 2
                    height: width
                    radius: width / 2
                    x: phase * Math.max(1, receiveLane.width - width)
                    y: receiveLane.height / 2 - height / 2 +
                       Math.sin((phase + index) * 6.283) * 5
                    color: netCore.receiveColor
                    opacity: 0.25 + 0.75 * phase
                }
            }
        }

        /* Transmit conduit: packets accelerate away from the reactor. */
        Item {
            id: transmitLane
            anchors.left: reactor.right
            anchors.leftMargin: 18
            anchors.right: parent.right
            anchors.rightMargin: 86
            anchors.verticalCenter: parent.verticalCenter
            height: 24

            Repeater {
                model: 6

                Rectangle {
                    property real phase: (netCore.transmitPhase + index * 0.18) % 1.0
                    visible: netCore.connected &&
                             index < Math.max(1, Math.ceil(netCore.uploadActivity / 2))
                    width: 7 + (index % 2) * 2
                    height: width
                    radius: width / 2
                    x: phase * Math.max(1, transmitLane.width - width)
                    y: transmitLane.height / 2 - height / 2 +
                       Math.cos((phase + index) * 6.283) * 5
                    color: netCore.transmitColor
                    opacity: 0.95 - 0.60 * phase
                }
            }
        }

        Rectangle {
            id: reactor
            anchors.centerIn: parent
            width: 58
            height: 58
            radius: 29
            color: "#071426"
            border.width: 2
            border.color: netCore.connected ? neutronBlue : dangerRed

            Rectangle {
                anchors.centerIn: parent
                width: 45
                height: 45
                radius: 23
                color: netCore.connected ? netCore.receiveColor : dangerRed
                opacity: 0.07 + netCore.reactorPulse * 0.10
            }

            Rectangle {
                anchors.centerIn: parent
                width: 23
                height: 23
                radius: 12
                color: netCore.connected ? "#17CFFF" : dangerRed
                border.width: 1
                border.color: netCore.connected ? "#D8FFFF" : "#FFD1D1"
                opacity: 0.88 + netCore.reactorPulse * 0.12
            }

            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: "white"
                visible: netCore.connected
            }

            Item {
                anchors.centerIn: parent
                width: 51
                height: 51
                rotation: netCore.orbitRotation
                visible: netCore.connected

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: 7
                    height: 7
                    radius: 4
                    color: netCore.transmitColor
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 70
            height: 34
            radius: 14
            color: "#072132E8"
            border.width: 1
            border.color: "#35E9FF88"

            Column {
                anchors.centerIn: parent
                spacing: -2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "↓ RX"
                    color: netCore.receiveColor
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.9
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2
                    Repeater {
                        model: 6
                        Rectangle {
                            width: 5
                            height: 3 + index * 1.6
                            radius: 2
                            color: netCore.receiveColor
                            opacity: index < Math.ceil(netCore.downloadActivity / 2)
                                     ? 0.95 : 0.16
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 70
            height: 34
            radius: 14
            color: "#16112FE8"
            border.width: 1
            border.color: "#9C7CFF88"

            Column {
                anchors.centerIn: parent
                spacing: -2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "TX ↑"
                    color: netCore.transmitColor
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.9
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2
                    Repeater {
                        model: 6
                        Rectangle {
                            width: 5
                            height: 3 + index * 1.6
                            radius: 2
                            color: netCore.transmitColor
                            opacity: index < Math.ceil(netCore.uploadActivity / 2)
                                     ? 0.95 : 0.16
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            width: 58
            height: 15
            radius: 8
            color: netCore.connected ? "#09263DEE" : "#2A0A10EE"
            border.width: 1
            border.color: netCore.connected ? "#7DF9FF66" : "#FF304066"

            Text {
                anchors.centerIn: parent
                text: netCore.connected
                      ? Math.max(0, netCore.signalPercent) + "%"
                      : "OFF"
                color: netCore.connected ? neutronBlue : "#FF9A9A"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.7
            }
        }
    }

    /*
        ============================================================
                            CONTENT
        ============================================================
    */

    Item {
        id: contentDock

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: statusLine.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 8
        anchors.bottomMargin: 10

        /*
            ========================================================
                            TEMPERATURE
            ========================================================
        */

        Item {
            id: temperatureTile

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom

            width: 285
            height: parent.height

            FocusShell {
                itemIndex: 4
                label: "TEMPERATURE"
            }

            TempGauge {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -2

                enabled: root.consoleActive
                temperature: root.currentTemperatureValue()

                scale: 1.08
            }
        }

        /*
            ========================================================
                            LEFT SIDE
            ========================================================
        */

        RowLayout {
            id: leftRow

            anchors.left: parent.left
            anchors.right: temperatureTile.left
            anchors.bottom: parent.bottom
            anchors.rightMargin: 22

            height: parent.height
            spacing: 18

            /*
                CPU
            */

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 255
                Layout.fillHeight: true

                FocusShell {
                    itemIndex: 0
                    label: "CPU"
                }

                SystemCircle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom

                    title: "CPU"
                    value: cpuDisplayText()
                    subtitle: "Load"
                    percent: cpuPercentValue()
                    animationsEnabled: root.consoleActive

                    diameter: Math.min(206, parent.height + 28)
                    thickness: 17
                }
            }

            /*
                RAM
                PATCH 16B-R2: CONSOLE RAM ARC GAUGE
            */

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 255
                Layout.fillHeight: true

                FocusShell {
                    itemIndex: 1
                    label: "RAM"
                }

                SystemCircle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom

                    title: "RAM"
                    value: ramPercentValue() + "%"
                    subtitle: ""
                    percent: ramPercentValue()
                    animationsEnabled: root.consoleActive

                    diameter: Math.min(206, parent.height + 28)
                    thickness: 17
                }
            }

            /*
                STORAGE
            */

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 330
                Layout.fillHeight: true

                FocusShell {
                    itemIndex: 2
                    label: "STORAGE"
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 2
                    anchors.bottomMargin: 4

                    spacing: 10

                    Text {
                        width: parent.width

                        text: "STORAGE"
                        color: neutronBlue

                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 1.6

                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Repeater {
                        model: Math.min(2, mountCount())

                        Item {
                            width: parent.width
                            height: 78

                            Text {
                                id: storageTitle

                                anchors.left: parent.left
                                anchors.top: parent.top

                                width: parent.width * 0.66

                                text: mountName(index)

                                color: mountPercent(index) >= 86
                                       ? dangerRed
                                       : mountPercent(index) >= 70
                                         ? warningYellow
                                         : neutronBlue

                                font.pixelSize: 30
                                font.bold: true
                                font.letterSpacing: 1

                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.top: parent.top

                                text: mountPercent(index) + "%"
                                color: "white"

                                font.pixelSize: 30
                                font.bold: true
                            }

                            Rectangle {
                                id: track

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: storageTitle.bottom
                                anchors.topMargin: 9

                                height: 13
                                radius: 7
                                color: "#203149"

                                Rectangle {
                                    width: parent.width *
                                           (mountPercent(index) / 100)

                                    height: parent.height
                                    radius: parent.radius

                                    color: percentColor(mountPercent(index))

                                    Behavior on width {
                                        enabled: root.consoleActive

                                        NumberAnimation {
                                            duration: 260
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: track.bottom
                                anchors.topMargin: 7

                                text: mountUsed(index) +
                                      " / " +
                                      mountTotal(index)

                                color: "#cfeaff"

                                font.pixelSize: 25
                                font.bold: true

                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }

                    Item {
                        visible: mountCount() <= 0

                        width: parent.width
                        height: Math.max(84, parent.height - 28)

                        Text {
                            anchors.centerIn: parent

                            width: parent.width

                            text: "No mounted storage"
                            color: "#8aa6c8"

                            font.pixelSize: 38
                            font.bold: true

                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            /*
                ACTIVE APPS
            */

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 250
                Layout.fillHeight: true

                FocusShell {
                    itemIndex: 3
                    label: "ACTIVE"
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 2
                    anchors.bottomMargin: 7

                    spacing: 7

                    Text {
                        width: parent.width

                        text: "ACTIVE"
                        color: successGreen

                        font.pixelSize: 20
                        font.bold: true
                        font.letterSpacing: 2

                        horizontalAlignment: Text.AlignHCenter
                    }

                    Item {
                        width: parent.width
                        height: Math.max(112, parent.height - 61)
                        clip: true

                        ListView {
                            id: activeAppsList

                            anchors.fill: parent
                            anchors.leftMargin: parent.width * 0.03
                            anchors.rightMargin: parent.width * 0.03

                            visible: root.activeAppCount() > 0
                            clip: true
                            interactive: false
                            spacing: 4
                            cacheBuffer: 96

                            model: root.runningApps()

                            currentIndex: root.activeAppSelectionMode
                                          ? root.selectedActiveApp
                                          : -1

                            preferredHighlightBegin: 0
                            preferredHighlightEnd: height
                            highlightRangeMode: ListView.ApplyRange

                            delegate: Rectangle {
                                readonly property bool appSelected:
                                    root.activeAppSelectionMode &&
                                    root.selectedActiveApp === index

                                width: activeAppsList.width
                                height: 31
                                radius: height / 2

                                color: appSelected
                                       ? "#4A1119EE"
                                       : "#0a2a22cc"

                                border.width: appSelected ? 2 : 1

                                border.color: appSelected
                                              ? root.dangerRed
                                              : root.successGreen

                                scale: appSelected ? 1.02 : 1.0

                                Behavior on scale {
                                    enabled: root.consoleActive

                                    NumberAnimation {
                                        duration: 110
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10

                                    spacing: 7

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter

                                        width: 7
                                        height: 7
                                        radius: width / 2

                                        color: root.successGreen
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter

                                        width: Math.max(
                                            1,
                                            parent.width - 72
                                        )

                                        text: root.appDisplayName(modelData)
                                        color: "white"

                                        font.pixelSize: 17
                                        font.bold: true

                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter

                                        text: "ACTIVE"
                                        color: root.successGreen

                                        font.pixelSize: 11
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: root.activeAppCount() <= 0

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: parent.width * 0.03
                            anchors.rightMargin: parent.width * 0.03

                            height: 36
                            radius: height / 2

                            color: "#07142699"

                            border.width: 1
                            border.color: "#44608080"

                            Text {
                                anchors.centerIn: parent

                                text: "NO ACTIVE APPS"
                                color: "#8aa6c8"

                                font.pixelSize: 14
                                font.bold: true
                                font.letterSpacing: 0.8
                            }
                        }
                    }

                    Text {
                        width: parent.width

                        text: root.activeAppCount() === 1
                              ? "1 APP"
                              : root.activeAppCount() + " APPS"

                        color: root.successGreen

                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 1

                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        /*
            ========================================================
                            RIGHT SIDE
            ========================================================
        */

        RowLayout {
            id: rightRow

            anchors.left: temperatureTile.right
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 22

            height: parent.height
            spacing: 18

            /*
                NETWORK
            */

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 430
                Layout.fillHeight: true

                FocusShell {
                    itemIndex: 5
                    label: "NETWORK"
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 2
                    anchors.bottomMargin: 4

                    spacing: 6

                    Text {
                        width: parent.width

                        text: "NETWORK"
                        color: networkConnected()
                               ? neutronBlue
                               : dangerRed

                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 1.6

                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width

                        text: networkTitle()

                        color: networkConnected()
                               ? "white"
                               : "#ffd1d1"

                        font.pixelSize: 23
                        font.bold: true

                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width

                        text: networkSubline()

                        color: networkConnected()
                               ? "white"
                               : "#ff9a9a"

                        opacity: 0.78

                        font.pixelSize: 14
                        font.bold: true

                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width

                        text: networkAddressLine()
                        color: "#9fd8ff"

                        font.pixelSize: 13
                        font.bold: true

                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Rectangle {
                        width: parent.width * 0.92
                        height: 42
                        radius: 18
                        anchors.horizontalCenter: parent.horizontalCenter

                        color: "#081426cc"

                        border.width: 1

                        border.color: networkConnected()
                                      ? "#4da6ff66"
                                      : "#ff304066"

                        Row {
                            anchors.centerIn: parent
                            spacing: 30

                            Text {
                                text: "↓ " + cachedDownloadSpeed()
                                color: neutronBlue

                                font.pixelSize: 17
                                font.bold: true
                            }

                            Text {
                                text: "↑ " + cachedUploadSpeed()
                                color: "#9fd8ff"

                                font.pixelSize: 17
                                font.bold: true
                            }
                        }
                    }

                    NetworkPulseCore {
                        width: parent.width * 0.92
                        height: 50
                        anchors.horizontalCenter: parent.horizontalCenter

                        motionActive: root.consoleActive &&
                                      networkConnected() &&
                                      networkActivityLevel() > 0
                        connected: networkConnected()
                        activity: networkActivityLevel()
                        downloadActivity: speedRank(root.liveNetworkDownload)
                        uploadActivity: speedRank(root.liveNetworkUpload)
                        signalPercent: wifiSignalPercent()
                    }

                    Text {
                        width: parent.width

                        text: "10 MIN CACHE  •  " +
                              speedTestAge()

                        color: "#8aa6c8"

                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.2

                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            /*
                CONTROLLER + COMPACT UPTIME

                The controller status row is the selectable anchor. Uptime is
                intentionally display-only and no longer owns a focus target.
            */

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 360
                Layout.fillHeight: true

                FocusShell {
                    itemIndex: 6
                    label: "CONTROLLER"
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    height: implicitHeight
                    spacing: 8

                    Rectangle {
                        width: Math.min(parent.width, 250)
                        height: 64
                        anchors.horizontalCenter: parent.horizontalCenter
                        radius: 18
                        color: "#071426F2"
                        border.width: 1
                        border.color: overviewControllerStatus.visible ? "#3A7DF9FF" : "#31506A80"

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.radius - 2
                            color: "#FFFFFF"
                            opacity: 0.035
                        }

                        ControllerBatteryStatus {
                            id: overviewControllerStatus
                            anchors.centerIn: parent
                            controllerBackend: root.controllerBackend
                            compact: true
                            platformSymbolMode: true
                            showControllerType: true
                            showSeparators: false
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !overviewControllerStatus.visible
                            text: "CONTROLLER OFFLINE"
                            color: "#8aa6c8"
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                    }

                    Row {
                        width: parent.width
                        height: 40
                        spacing: 10

                        Text {
                            width: parent.width * 0.30
                            anchors.verticalCenter: parent.verticalCenter
                            text: "UPTIME"
                            color: neutronBlue
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 1.1
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            width: parent.width * 0.64
                            anchors.verticalCenter: parent.verticalCenter
                            text: firstProp(
                                ["uptime", "systemUptime"],
                                "--"
                            )
                            color: "white"
                            font.pixelSize: 25
                            font.bold: true
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    Row {
                        width: parent.width
                        height: 28
                        spacing: 10

                        Text {
                            width: parent.width * 0.30
                            anchors.verticalCenter: parent.verticalCenter
                            text: "APT"
                            color: "#8aa6c8"
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            width: parent.width * 0.64
                            anchors.verticalCenter: parent.verticalCenter
                            text: firstProp(
                                [
                                    "lastAptUpdate",
                                    "aptLastUpdate",
                                    "lastUpdate"
                                ],
                                "--"
                            )
                            color: "#cfeaff"
                            font.pixelSize: 13
                            font.bold: true
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }
            }

            /*
                CLOCK
            */

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 280
                Layout.fillHeight: true

                FocusShell {
                    itemIndex: 7
                    label: "CLOCK"
                }

                Item {
                    anchors.fill: parent

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5

                        height: implicitHeight
                        spacing: 0

                        Text {
                            text: shownTime()
                            color: clockTextColor()

                            font.pixelSize: Math.round(64 * Math.max(80, Math.min(140, root.clockScale)) / 100)
                            font.bold: true

                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            visible: root.showClockDate
                            text: shownDate()
                            color: clockDateColor()

                            font.pixelSize: 28
                            font.bold: true

                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            visible: root.showClockTimezone &&
                                     cleanText(root.currentTimezoneLabel).length > 0
                            text: root.currentTimezoneLabel
                            color: root.clockTimezoneTint
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 1.8
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                    }
                }
            }

            /*
                USER
            */

            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 230
                Layout.fillHeight: true

                FocusShell {
                    itemIndex: 8
                    label: "USER"
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4

                    height: implicitHeight
                    spacing: 7

                    Rectangle {
                        id: avatar

                        width: 172
                        height: 172
                        radius: activeUserAvatarRadius(width)

                        anchors.horizontalCenter: parent.horizontalCenter

                        clip: false
                        color: "#101d42dd"

                        border.width: root.armedIndex === 8
                                      ? 5
                                      : root.sectionFocused &&
                                        root.selectedSystem === 8
                                        ? 4
                                        : 3

                        border.color: root.armedIndex === 8
                                      ? dangerRed
                                      : root.sectionFocused &&
                                        root.selectedSystem === 8
                                        ? focusBlue
                                        : activeUserAccent()

                        /* PATCH 15: PROFILE AVATAR GLOW */
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + 22
                            height: parent.height + 22
                            radius: activeUserAvatarRadius(width)
                            color: "transparent"
                            border.width: 8
                            border.color: activeUserAccent()
                            opacity: 0.06 + activeUserGlowStrength() * 0.22
                            z: 0
                        }


                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5

                            radius: activeUserAvatarRadius(width)
                            color: "transparent"

                            border.width: 1
                            border.color: "#66ffffff"
                        }

                        Image {
                            id: userImage

                            anchors.fill: parent

                            source: activeUserIcon()
                            fillMode: Image.PreserveAspectCrop

                            smooth: true
                            cache: true
                            asynchronous: true
                            mipmap: true

                            opacity: status === Image.Ready ? 1.0 : 0.0
                        }

                        Text {
                            visible: userImage.status !== Image.Ready

                            anchors.centerIn: parent

                            text: activeUserInitial()
                            color: "white"

                            font.pixelSize: 42
                            font.bold: true
                        }
                    }

                    Text {
                        text: activeUserName()
                        color: activeUserNameTint()

                        font.pixelSize: 21
                        font.bold: true

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        visible: activeUserTagline().length > 0
                        text: activeUserTagline()
                        color: activeUserAccent()

                        font.pixelSize: 13
                        font.bold: true

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
        }
    }

    /*
        ============================================================
                        CONTROLLER AND ROUTING
        ============================================================
    */

    function activateSelected() {
        if (root.selectedSystem === 3) {
            var count = root.activeAppCount()

            if (count <= 0)
                return false

            if (!root.activeAppSelectionMode) {
                root.activeAppSelectionMode = true

                root.selectedActiveApp = Math.max(
                    0,
                    Math.min(
                        root.selectedActiveApp,
                        count - 1
                    )
                )

                return true
            }

            var selectedApp = root.activeAppAt(
                root.selectedActiveApp
            )

            if (!selectedApp)
                return false

            root.modalRequested(
                "activeApp",
                {
                    "app": selectedApp,
                    "index": root.selectedActiveApp
                }
            )

            return true
        }

        var modalId = root.modalIdForIndex(
            root.selectedSystem
        )

        if (modalId.length <= 0)
            return false

        var context = root.modalContextForIndex(
            root.selectedSystem
        )

        root.modalRequested(modalId, context)

        /*
            Compatibility with the current Console until its modal router
            is replaced. The production Console can remove this connection.
        */
        root.cardClicked(
            root.cardTypeForIndex(root.selectedSystem),
            root.selectedSystem
        )

        return true
    }

    function moveSelection(delta) {
        if (root.activeAppSelectionMode)
            return root.moveActiveAppSelection(delta)

        var next =
            Number(root.selectedSystem) +
            Number(delta)

        while (next < 0)
            next += root.systemCardCount

        next = next % root.systemCardCount

        if (next !== 3)
            root.activeAppSelectionMode = false

        root.selectedSystem = next
        return true
    }

    function moveActiveAppSelection(delta) {
        var count = root.activeAppCount()

        if (count <= 0) {
            root.selectedActiveApp = 0
            root.activeAppSelectionMode = false
            return false
        }

        var next =
            Number(root.selectedActiveApp) +
            Number(delta)

        while (next < 0)
            next += count

        root.selectedActiveApp = next % count
        return true
    }

    function disarmSelected() {
        if (root.activeAppSelectionMode) {
            root.activeAppSelectionMode = false
            return true
        }

        if (root.armedIndex >= 0) {
            root.armedIndex = -1
            return true
        }

        return false
    }

    function handleController(action) {
        if (!root.sectionFocused)
            return false

        if (action === "left" ||
                action === "L" ||
                action === "LEFT") {
            return moveSelection(-1)
        }

        if (action === "right" ||
                action === "R" ||
                action === "RIGHT") {
            return moveSelection(1)
        }

        if (action === "primary" ||
                action === "x" ||
                action === "X" ||
                action === "confirm") {
            return activateSelected()
        }

        if (action === "cancel" ||
                action === "o" ||
                action === "O" ||
                action === "back") {
            return disarmSelected()
        }

        return false
    }

    function selectionHintText() {
        if (root.armedIndex >= 0) {
            return "ARMED  " +
                   root.cardLabel(root.armedIndex) +
                   "  •  O CANCEL"
        }

        if (root.selectedSystem === 3) {
            if (root.activeAppCount() <= 0)
                return "NO ACTIVE APPS"

            if (root.activeAppSelectionMode) {
                var app = root.activeAppAt(
                    root.selectedActiveApp
                )

                return "X OPTIONS  •  " +
                       root.appDisplayName(app) +
                       "  •  O BACK"
            }

            return ""
        }

        return "X OPEN  " +
               root.cardLabel(root.selectedSystem)
    }

    function modalIdForIndex(index) {
        if (index === 0)
            return "cpu"

        if (index === 1)
            return "memory"

        if (index === 2)
            return "storage"

        if (index === 4)
            return "temperature"

        if (index === 5)
            return "network"

        if (index === 6)
            return "controllerSettings"

        if (index === 7)
            return "clock"

        if (index === 8)
            return "user"

        return ""
    }

    function modalContextForIndex(index) {
        if (index === 0) {
            return {
                "cpuPercent": root.cpuPercentValue(),
                "temperature": root.currentTemperatureValue()
            }
        }

        if (index === 1) {
            return {
                "percent": root.ramPercentValue(),
                "summary": root.ramText()
            }
        }

        if (index === 2) {
            return {
                "mounts": root.mountList()
            }
        }

        if (index === 4) {
            return {
                "temperature": root.currentTemperatureValue()
            }
        }

        if (index === 5) {
            return {
                "ssid": root.networkTitle(),
                "connected": root.networkConnected(),
                "localIp": root.localIp(),
                "tailscaleIp": root.tailscaleIp(),
                "signalPercent": root.wifiSignalPercent()
            }
        }

        if (index === 6) {
            return {
                "connected": root.controllerConnected(),
                "controllerType": root.controllerTypeName(),
                "batteryPercent": root.controllerBatteryValue(),
                "uptime": root.firstProp(
                    ["uptime", "systemUptime"],
                    "--"
                )
            }
        }

        if (index === 7) {
            return {
                "time": root.shownTime(),
                "date": root.shownDate()
            }
        }

        if (index === 8) {
            return {
                "user": root.activeUser,
                "displayName": root.activeUserName(),
                "role": root.activeUserRole(),
                "icon": root.activeUserIcon()
            }
        }

        return {}
    }

    function cardTypeForIndex(index) {
        if (index === 0)
            return "cpu"

        if (index === 1)
            return "ram"

        if (index === 2)
            return "storage"

        if (index === 3)
            return "active"

        if (index === 4)
            return "temperature"

        if (index === 5)
            return "network"

        if (index === 6)
            return "controller"

        if (index === 7)
            return "clock"

        if (index === 8)
            return "user"

        return "system"
    }

    function cardLabel(index) {
        if (index === 0)
            return "CPU"

        if (index === 1)
            return "MEMORY"

        if (index === 2)
            return "STORAGE"

        if (index === 3)
            return "ACTIVE APPS"

        if (index === 4)
            return "TEMPERATURE"

        if (index === 5)
            return "NETWORK"

        if (index === 6)
            return "CONTROLLER"

        if (index === 7)
            return "CLOCK"

        if (index === 8)
            return "USER"

        return "SYSTEM"
    }

    function controllerConnected() {
        try {
            return root.controllerBackend &&
                   root.controllerBackend.controllerConnected === true
        } catch (error) {
            return false
        }
    }

    function controllerTypeName() {
        try {
            if (root.controllerBackend &&
                    root.controllerBackend.controllerType !== undefined) {
                var verified = root.cleanText(
                    root.controllerBackend.controllerType
                )

                if (verified.length > 0)
                    return verified
            }

            if (root.controllerBackend &&
                    root.controllerBackend.controllerName !== undefined) {
                var raw = root.cleanText(
                    root.controllerBackend.controllerName
                )

                if (raw.length > 0)
                    return raw
            }
        } catch (error) {
        }

        return "Controller"
    }

    function controllerBatteryValue() {
        try {
            if (!root.controllerBackend)
                return -1

            var value = Number(
                root.controllerBackend.controllerBatteryPercent
            )

            if (isNaN(value))
                return -1

            return Math.max(0, Math.min(100, Math.round(value)))
        } catch (error) {
            return -1
        }
    }

    /*
        ============================================================
                        SAFE BACKEND HELPERS
        ============================================================
    */

    function systemBackend() {
        try {
            if (typeof systemMonitor !== "undefined" &&
                    systemMonitor) {
                return systemMonitor
            }
        } catch (e) {
        }

        return null
    }

    function appBackend() {
        try {
            if (typeof appManager !== "undefined" &&
                    appManager) {
                return appManager
            }
        } catch (e) {
        }

        return null
    }

    function assetBackend() {
        try {
            if (typeof assetManager !== "undefined" &&
                    assetManager) {
                return assetManager
            }
        } catch (e) {
        }

        return null
    }

    function cleanText(value) {
        if (value === undefined ||
                value === null) {
            return ""
        }

        var text = String(value).trim()

        if (text === "undefined" ||
                text === "null") {
            return ""
        }

        return text
    }

    function prop(name, fallbackValue) {
        var backend = systemBackend()

        if (!backend)
            return fallbackValue

        try {
            var value = backend[name]

            if (value !== undefined &&
                    value !== null &&
                    String(value).length > 0) {
                return value
            }
        } catch (e) {
        }

        return fallbackValue
    }

    function firstProp(names, fallbackValue) {
        for (var i = 0; i < names.length; i++) {
            var value = prop(names[i], "")

            if (value !== undefined &&
                    value !== null) {
                var text = cleanText(value)

                if (text.length > 0 &&
                        text !== "--") {
                    return value
                }
            }
        }

        return fallbackValue
    }

    function hasValue(value) {
        var text = cleanText(value)

        return text.length > 0 &&
               text !== "--" &&
               text !== "0.0.0.0"
    }

    function isAbsoluteSource(value) {
        var text = String(value || "")
                   .trim()
                   .toLowerCase()

        return text.indexOf("file:") === 0 ||
               text.indexOf("qrc:") === 0 ||
               text.indexOf("http://") === 0 ||
               text.indexOf("https://") === 0 ||
               text.indexOf("image://") === 0
    }

    function themeFile(path) {
        var cleanPath = cleanText(path)

        if (cleanPath.length <= 0)
            return ""

        if (isAbsoluteSource(cleanPath))
            return cleanPath

        var assets = assetBackend()

        if (assets &&
                typeof assets.themeFile === "function") {
            try {
                return assets.themeFile(cleanPath)
            } catch (e) {
            }
        }

        // SystemOverview.qml is under qml/dashboard; the theme root is two
        // levels up. This fallback is used by offscreen tests and early load.
        return "../../themes/Default/" + cleanPath
    }

    function percentColor(value) {
        var p = Number(value)

        if (isNaN(p))
            p = 0

        if (p >= 86)
            return dangerRed

        if (p >= 70)
            return warningYellow

        return successGreen
    }

    /*
        ============================================================
                        SYSTEM STATUS
        ============================================================
    */

    function shownSystemMode() {
        return String(
            firstProp(
                ["systemMode", "mode", "profile"],
                "NORMAL"
            )
        )
    }

    function shownThermalStatus() {
        return String(
            firstProp(
                [
                    "thermalStatus",
                    "throttleStatus",
                    "throttled",
                    "cpuThrottle"
                ],
                "No Throttle"
            )
        )
    }

    /*
        ============================================================
                        CPU / RAM / TEMP
        ============================================================
    */

    function parseTemp(value) {
        if (!value || value === "--")
            return 0

        var clean = String(value)

        clean = clean.replace("°F", "")
        clean = clean.replace("°C", "")
        clean = clean.replace("°", "")
        clean = clean.replace("F", "")
        clean = clean.replace("C", "")

        var parsed = parseFloat(clean)

        if (isNaN(parsed))
            return 0

        return parsed
    }

    function currentTemperatureValue() {
        return parseTemp(
            firstProp(
                [
                    "temperature",
                    "temp",
                    "cpuTemp",
                    "cpuTemperature"
                ],
                "--"
            )
        )
    }

    function tempColor() {
        var temp = currentTemperatureValue()

        if (temp >= 176)
            return dangerRed

        if (temp >= 150)
            return warningYellow

        return neutronBlue
    }

    function cpuPercentValue() {
        return root.liveCpuPercent
    }

    function cpuDisplayText() {
        var direct = cleanText(root.liveCpuText)

        if (direct.length > 0 &&
                direct !== "--") {
            return direct
        }

        return cpuPercentValue() + "%"
    }

    function ramPercentValue() {
        return root.liveRamPercent
    }

    function ramText() {
        var summary = cleanText(root.liveRamText)

        if (summary.length > 0 &&
                summary !== "--") {
            return summary
        }

        var used = cleanText(root.liveRamUsed)
        var total = cleanText(root.liveRamTotal)

        if (used.length > 0 &&
                used !== "--" &&
                total.length > 0 &&
                total !== "--") {
            return used + " / " + total
        }

        return "RAM DATA WAITING"
    }

    function memoryBlockCount() {
        var value = ramPercentValue()

        if (value <= 0)
            return 1

        return Math.max(
            1,
            Math.min(8, Math.ceil(value / 12.5))
        )
    }

    /*
        ============================================================
                            STORAGE
        ============================================================
    */

    function rawMountList() {
        var backend = systemBackend()

        if (!backend)
            return []

        try {
            if (backend.mounts)
                return backend.mounts
        } catch (e) {
        }

        return []
    }

    function isIgnoredMount(item) {
        if (!item)
            return true

        var name = cleanText(item.name).toLowerCase()
        var type = cleanText(item.type).toLowerCase()
        var fs = cleanText(item.fs).toLowerCase()
        var filesystem = cleanText(item.filesystem).toLowerCase()
        var mount = cleanText(item.mount).toLowerCase()
        var mountPoint = cleanText(item.mountPoint).toLowerCase()
        var path = cleanText(item.path).toLowerCase()

        var combined =
            name + " " +
            type + " " +
            fs + " " +
            filesystem + " " +
            mount + " " +
            mountPoint + " " +
            path

        if (combined.indexOf("tmpfs") >= 0)
            return true

        if (combined.indexOf("tempfs") >= 0)
            return true

        if (combined.indexOf("devtmpfs") >= 0)
            return true

        if (combined.indexOf("proc") >= 0 ||
                combined.indexOf("sysfs") >= 0 ||
                combined.indexOf("cgroup") >= 0) {
            return true
        }

        if (mountPoint.indexOf("/run") === 0 ||
                mountPoint.indexOf("/proc") === 0 ||
                mountPoint.indexOf("/sys") === 0 ||
                mountPoint.indexOf("/dev") === 0) {
            return true
        }

        return false
    }

    function cloneMount(item) {
        var result = {}

        if (!item)
            return result

        try {
            for (var key in item)
                result[key] = item[key]
        } catch (e) {
        }

        result.name = mountLabelForItem(item)

        return result
    }

    function mountLabelForItem(item) {
        var name = cleanText(item.name)
        var mountPoint = cleanText(item.mountPoint)
        var mount = cleanText(item.mount)
        var path = cleanText(item.path)

        var combined =
            (
                name + " " +
                mountPoint + " " +
                mount + " " +
                path
            ).toLowerCase()

        if (name.toLowerCase() === "rootfs" ||
                mountPoint === "/" ||
                mount === "/" ||
                path === "/" ||
                combined.indexOf("rootfs") >= 0) {
            return "Boot"
        }

        if (combined.indexOf("media") >= 0 ||
                combined.indexOf("usb") >= 0 ||
                combined.indexOf("hdd") >= 0 ||
                combined.indexOf("drive") >= 0 ||
                combined.indexOf("external") >= 0) {
            return name.length > 0 &&
                   name.toLowerCase() !== "storage"
                   ? name
                   : "Media"
        }

        if (name.length > 0)
            return name

        if (mountPoint.length > 0)
            return mountPoint

        if (mount.length > 0)
            return mount

        if (path.length > 0)
            return path

        return "Storage"
    }

    function mountPriority(item) {
        var name = cleanText(item.name).toLowerCase()
        var mountPoint = cleanText(item.mountPoint).toLowerCase()
        var mount = cleanText(item.mount).toLowerCase()
        var path = cleanText(item.path).toLowerCase()

        var combined =
            name + " " +
            mountPoint + " " +
            mount + " " +
            path

        if (name === "boot" ||
                name === "rootfs" ||
                mountPoint === "/" ||
                mount === "/" ||
                path === "/") {
            return 0
        }

        if (combined.indexOf("media") >= 0 ||
                combined.indexOf("usb") >= 0 ||
                combined.indexOf("hdd") >= 0 ||
                combined.indexOf("drive") >= 0 ||
                combined.indexOf("external") >= 0) {
            return 1
        }

        return 2
    }

    function mountList() {
        var raw = rawMountList()
        var result = []

        if (!raw ||
                raw.length === undefined) {
            return result
        }

        for (var i = 0; i < raw.length; i++) {
            var item = raw[i]

            if (!isIgnoredMount(item))
                result.push(cloneMount(item))
        }

        result.sort(function(a, b) {
            return mountPriority(a) -
                   mountPriority(b)
        })

        return result
    }

    function mountCount() {
        return mountList().length
    }

    function mountItem(index) {
        var list = mountList()

        if (!list ||
                index < 0 ||
                index >= list.length) {
            return null
        }

        return list[index]
    }

    function mountValue(index, key, fallbackValue) {
        var item = mountItem(index)

        if (!item)
            return fallbackValue

        try {
            if (item[key] !== undefined &&
                    item[key] !== null) {
                return item[key]
            }
        } catch (e) {
        }

        return fallbackValue
    }

    function mountName(index) {
        return String(
            mountValue(index, "name", "Storage")
        )
    }

    function mountPercent(index) {
        var value = Number(
            firstMountValue(
                index,
                [
                    "percent",
                    "usedPercent",
                    "usagePercent",
                    "usage"
                ],
                0
            )
        )

        if (isNaN(value))
            return 0

        return Math.max(
            0,
            Math.min(100, Math.round(value))
        )
    }

    function firstMountValue(index, keys, fallbackValue) {
        var item = mountItem(index)

        if (!item)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = item[keys[i]]

                if (value !== undefined &&
                        value !== null &&
                        String(value).length > 0) {
                    return value
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function mountUsed(index) {
        return String(
            firstMountValue(
                index,
                ["used", "usedText", "usedHuman"],
                "--"
            )
        )
    }

    function mountTotal(index) {
        return String(
            firstMountValue(
                index,
                ["total", "totalText", "size", "sizeHuman"],
                "--"
            )
        )
    }

    /*
        ============================================================
                            NETWORK
        ============================================================
    */

    function networkConnected() {
        return hasValue(localIp()) ||
               hasValue(tailscaleIp())
    }

    function localIp() {
        return String(
            firstProp(
                ["localIp", "ip", "ipv4", "networkIp"],
                "--"
            )
        )
    }

    function tailscaleIp() {
        return String(
            firstProp(
                ["tailscaleIp", "tailnetIp", "tsIp"],
                "--"
            )
        )
    }

    function networkTitle() {
        var ssid = firstProp(
            [
                "ssid",
                "networkSsid",
                "wifiSsid",
                "networkName"
            ],
            ""
        )

        if (hasValue(ssid) &&
                String(ssid) !== "wlan0") {
            return String(ssid)
        }

        if (networkConnected())
            return "Wi-Fi Connected"

        return "Offline"
    }

    function networkSubline() {
        var signal = firstProp(
            [
                "wifiSignal",
                "signal",
                "signalStrength"
            ],
            "--"
        )

        var iface = firstProp(
            [
                "wifiInterface",
                "interface",
                "networkInterface"
            ],
            ""
        )

        if (hasValue(iface) &&
                hasValue(signal)) {
            return iface + "  •  " + signal
        }

        if (hasValue(signal))
            return String(signal)

        if (hasValue(iface))
            return String(iface)

        return networkConnected()
               ? "Network link active"
               : "No network link"
    }

    function networkAddressLine() {
        var local = localIp()
        var ts = tailscaleIp()
        var parts = []

        if (hasValue(local))
            parts.push(local)

        if (hasValue(ts))
            parts.push("TS " + ts)

        if (parts.length <= 0)
            return "--"

        return parts.join("  •  ")
    }

    function cachedDownloadSpeed() {
        return root.liveNetworkTestDownload
    }

    function cachedUploadSpeed() {
        return root.liveNetworkTestUpload
    }

    function speedTestAge() {
        if (root.liveNetworkTestRunning)
            return "TEST RUNNING"
        return root.liveNetworkTestAge
    }

    function networkActivityLevel() {
        if (!networkConnected())
            return 0

        var value = Math.max(
            speedRank(root.liveNetworkDownload),
            speedRank(root.liveNetworkUpload)
        )

        return Math.max(0, Math.min(12, value))
    }

    function wifiSignalPercent() {
        var percentDirect = Number(
            firstProp(
                [
                    "wifiSignalPercent",
                    "signalPercent",
                    "networkSignalPercent"
                ],
                -1
            )
        )

        if (!isNaN(percentDirect) &&
                percentDirect >= 0) {
            return Math.max(
                0,
                Math.min(
                    100,
                    Math.round(percentDirect)
                )
            )
        }

        var signal = String(
            firstProp(
                [
                    "wifiSignal",
                    "signal",
                    "signalStrength"
                ],
                "--"
            )
        )

        var match = signal.match(/-?\d+/)

        if (!match)
            return networkConnected() ? 65 : 0

        var dbm = Number(match[0])

        if (isNaN(dbm))
            return networkConnected() ? 65 : 0

        var percent =
            Math.round(
                ((dbm + 100) / 55) * 100
            )

        return Math.max(
            0,
            Math.min(100, percent)
        )
    }

    function speedRank(value) {
        var text = String(value || "--")
                   .toUpperCase()

        if (text === "--")
            return 0

        if (text.indexOf("GB") >= 0 ||
                text.indexOf("GIB") >= 0) {
            return 12
        }

        if (text.indexOf("MB") >= 0 ||
                text.indexOf("MIB") >= 0) {
            return 9
        }

        if (text.indexOf("KB") >= 0 ||
                text.indexOf("KIB") >= 0) {
            return 5
        }

        if (text.indexOf("B/S") >= 0)
            return 3

        return 2
    }

    /*
        ============================================================
                        ACTIVE APPS
        ============================================================
    */

    function appList() {
        var backend = appBackend()

        if (!backend)
            return []

        try {
            if (backend.favoriteApps)
                return backend.favoriteApps
        } catch (e) {
        }

        try {
            if (backend.apps)
                return backend.apps
        } catch (e2) {
        }

        return []
    }

    function appValue(app, keys, fallbackValue) {
        if (!app)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = app[keys[i]]

                if (value !== undefined &&
                        value !== null &&
                        String(value).length > 0) {
                    return value
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function appIsRunning(app) {
        var raw = appValue(
            app,
            [
                "running",
                "isRunning",
                "active",
                "serviceRunning"
            ],
            false
        )

        if (raw === true)
            return true

        if (raw === false)
            return false

        var text = String(raw).toLowerCase()

        return text === "true" ||
               text === "1" ||
               text === "running" ||
               text === "active" ||
               text === "online"
    }

    function runningApps() {
        var list = appList()
        var result = []

        if (!list ||
                list.length === undefined) {
            return result
        }

        for (var i = 0; i < list.length; i++) {
            if (appIsRunning(list[i]))
                result.push(list[i])

            if (result.length >= 3)
                break
        }

        return result
    }

    function activeAppCount() {
        return runningApps().length
    }

    function activeAppAt(index) {
        var apps = runningApps()

        if (!apps ||
                index < 0 ||
                index >= apps.length) {
            return null
        }

        return apps[index]
    }

    function appDisplayName(app) {
        return String(
            appValue(
                app,
                [
                    "name",
                    "title",
                    "displayName",
                    "id"
                ],
                "Application"
            )
        )
    }

    /*
        ============================================================
                        USER / CLOCK
        ============================================================
    */

    function activeUserName() {
        if (root.activeUser) {
            try {
                if (hasValue(root.activeUser.displayName))
                    return String(root.activeUser.displayName)
            } catch (e) {
            }

            try {
                if (hasValue(root.activeUser.username))
                    return String(root.activeUser.username)
            } catch (e2) {
            }
        }

        return "User"
    }

    /* PATCH 15: USER PROFILE APPEARANCE HELPERS */
    function activeUserProfileValue(keys, fallbackValue) {
        if (!root.activeUser)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = root.activeUser[keys[i]]

                if (value !== undefined &&
                        value !== null &&
                        String(value).trim().length > 0) {
                    return value
                }
            } catch (error) {
            }
        }

        return fallbackValue
    }

    function activeUserNameTint() {
        return String(activeUserProfileValue(
            ["nameTint", "displayNameTint"],
            "#FFFFFF"
        ))
    }

    function activeUserAccent() {
        return String(activeUserProfileValue(
            ["accentColor", "profileAccent"],
            neutronBlue
        ))
    }

    function activeUserTagline() {
        return cleanText(activeUserProfileValue(
            ["profileTagline", "tagline", "statusMessage"],
            ""
        ))
    }

    function activeUserAvatarFrame() {
        var frame = cleanText(activeUserProfileValue(
            ["avatarFrame", "avatarShape"],
            "circle"
        )).toLowerCase()

        return frame === "square" || frame === "rounded"
               ? frame
               : "circle"
    }

    function activeUserAvatarRadius(size) {
        var frame = activeUserAvatarFrame()

        if (frame === "square")
            return 12

        if (frame === "rounded")
            return Math.max(20, size * 0.22)

        return size / 2
    }

    function activeUserGlowStrength() {
        var value = Number(activeUserProfileValue(["glowStrength"], 0.65))

        if (isNaN(value))
            value = 0.65

        return Math.max(0.0, Math.min(1.0, value))
    }

    function activeUserRole() {
        if (root.activeUser) {
            try {
                if (hasValue(root.activeUser.role))
                    return String(root.activeUser.role)
            } catch (e) {
            }

            try {
                if (hasValue(root.activeUser.accountRole))
                    return String(root.activeUser.accountRole)
            } catch (e2) {
            }

            try {
                if (root.activeUser.isAdmin === true)
                    return "Admin"
            } catch (e3) {
            }
        }

        return "Admin"
    }

    function activeUserIcon() {
        if (root.activeUser) {
            try {
                var icon = cleanText(root.activeUser.icon)

                if (icon.length > 0) {
                    if (isAbsoluteSource(icon))
                        return icon

                    if (icon.indexOf("/") >= 0)
                        return themeFile(icon)

                    return themeFile("users/" + icon)
                }
            } catch (e) {
            }
        }

        return themeFile("users/user_icon.png")
    }

    function activeUserInitial() {
        var name = activeUserName()

        if (name.length <= 0)
            return "U"

        return name.charAt(0).toUpperCase()
    }

    function shownTime() {
        if (cleanText(root.currentTime).length > 0)
            return root.currentTime

        var now = new Date()
        var hours = now.getHours()
        var minutes = now.getMinutes()
        var suffix = hours >= 12 ? "PM" : "AM"
        var displayHour = hours % 12

        if (displayHour === 0)
            displayHour = 12

        return displayHour +
               ":" +
               (minutes < 10 ? "0" + minutes : minutes) +
               " " +
               suffix
    }

    function shownDate() {
        if (cleanText(root.currentDate).length > 0)
            return root.currentDate

        var now = new Date()

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

        return days[now.getDay()] +
               ", " +
               months[now.getMonth()] +
               " " +
               now.getDate()
    }

    function clockTextColor() {
        return String(root.clockTextTint || "#FFFFFF")
    }

    function clockDateColor() {
        return String(root.clockDateTint || "#9FD8FF")
    }

    /*
        ============================================================
                        STATE CLEANUP
        ============================================================
    */

    onSelectedSystemChanged: {
        if (selectedSystem < 0)
            selectedSystem = systemCardCount - 1

        if (selectedSystem >= systemCardCount)
            selectedSystem = 0

        if (selectedSystem !== 3)
            activeAppSelectionMode = false
    }

    onSelectedActiveAppChanged: {
        var count = activeAppCount()

        if (count <= 0) {
            selectedActiveApp = 0
            activeAppSelectionMode = false
            return
        }

        if (selectedActiveApp < 0)
            selectedActiveApp = count - 1

        if (selectedActiveApp >= count)
            selectedActiveApp = 0
    }

    onVisibleChanged: {
        if (!visible) {
            armedIndex = -1
            activeAppSelectionMode = false
            selectedActiveApp = 0
        }
    }

    onEnabledChanged: {
        if (!enabled) {
            armedIndex = -1
            activeAppSelectionMode = false
        }
    }
}
