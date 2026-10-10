import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root

    /*
        ============================================================
                    TEMPERATURE HISTORY MODAL
        ============================================================

        Production role:
            - Displays real CPU-temperature history.
            - Supports 1-hour, 6-hour, 12-hour, and 24-hour ranges.
            - Reads history from a backend ring buffer.
            - Redraws only when history, range, thresholds, or size changes.
            - Contains no continuously running decorative animation.
            - Loads only while open through Console.qml.

        Backend-ready systemMonitor properties:
            temperature / cpuTemperature / cpuTemp
            temperatureUnit
            temperatureWarningThreshold
            temperatureCriticalThreshold
            temperatureHistory
            thermalHistory
            temperatureHistoryRevision
            thermalThrottled
            throttlingEvents

        Preferred history entry:
            {
                "timestamp": 1783713600000,
                "temperature": 128.4,
                "throttled": false
            }

        Timestamps may be milliseconds, seconds, ISO-8601 strings, or Date
        values. Numeric history entries are also accepted and are distributed
        evenly across the selected range.

        Optional backend methods:
            getTemperatureHistory(int rangeSeconds)
            requestTemperatureHistory(int rangeSeconds)
            setTemperatureHistoryRange(int rangeSeconds)
            refreshTemperatureHistory()
            refreshThermalHistory()
            refresh()
    */

    property var contextData: ({})
    property var modalContext: ({})

    property bool pointerEnabled: true

    property int focusZone: 1
    property int selectedAction: 0
    property int selectedRange: 0

    readonly property var rangeOptions: [
        {
            "label": "1 HR",
            "hours": 1,
            "seconds": 3600
        },
        {
            "label": "6 HR",
            "hours": 6,
            "seconds": 21600
        },
        {
            "label": "12 HR",
            "hours": 12,
            "seconds": 43200
        },
        {
            "label": "24 HR",
            "hours": 24,
            "seconds": 86400
        }
    ]

    property var temperatureSnapshot: []
    property int historyRevision: 0

    property real currentTemperatureValue: 0
    property real minimumTemperatureValue: 0
    property real maximumTemperatureValue: 0
    property real averageTemperatureValue: 0

    property real warningThreshold: 150
    property real criticalThreshold: 176

    property string temperatureUnitValue: "F"
    property string thermalStatusValue: "NORMAL"
    property int throttlingEventCount: 0

    property string statusMessage: ""
    property bool statusIsError: false

    property color neutronBlue: "#7df9ff"
    property color focusBlue: "#4da6ff"
    property color successGreen: "#22ff88"
    property color warningGold: "#f5c542"
    property color dangerRed: "#ff3040"
    property color purple: "#c084fc"
    property color pink: "#f472b6"
    property color mutedText: "#8aa6c8"
    property color panelColor: "#071426"
    property color panelInner: "#10172a"

    readonly property int actionCount: 2
    readonly property int rangeCount: rangeOptions.length

    signal closed()
    signal actionRequested(string action, var payload)

    anchors.fill: parent
    visible: false
    enabled: visible
    color: "#70000000"
    opacity: 1.0
    z: 999
    focus: visible
    Keys.enabled: visible

    /*
        ============================================================
                                API
        ============================================================
    */

    function open(context) {
        contextData = context || ({})
        modalContext = contextData

        focusZone = 1
        selectedAction = 0
        selectedRange = 0

        statusMessage = ""
        statusIsError = false

        visible = true

        loadThresholds()
        requestHistory()
        refreshCurrentTemperature()

        root.forceActiveFocus()
    }

    function openModal(context) {
        open(context)
    }

    function close() {
        if (!visible)
            return

        visible = false
        temperatureSnapshot = []
        statusMessage = ""
        statusIsError = false
        closed()
    }

    function closeModal() {
        close()
    }

    /*
        ============================================================
                        BACKEND AND DATA HELPERS
        ============================================================
    */

    function backend() {
        try {
            if (typeof systemMonitor !== "undefined" &&
                    systemMonitor) {
                return systemMonitor
            }
        } catch (e) {
        }

        return null
    }

    function cleanText(value) {
        if (value === undefined || value === null)
            return ""

        var text = String(value).trim()

        if (text === "undefined" || text === "null")
            return ""

        return text
    }

    function objectValue(object, keys, fallbackValue) {
        if (!object)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = object[keys[i]]

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

    function backendValue(keys, fallbackValue) {
        var monitor = backend()

        if (!monitor)
            return fallbackValue

        return objectValue(
            monitor,
            keys,
            fallbackValue
        )
    }

    function contextValue(keys, fallbackValue) {
        return objectValue(
            contextData,
            keys,
            fallbackValue
        )
    }

    function normalizedArray(value) {
        if (!value)
            return []

        try {
            if (Array.isArray(value))
                return value.slice(0)

            if (value.length !== undefined) {
                var result = []

                for (var i = 0; i < value.length; i++)
                    result.push(value[i])

                return result
            }
        } catch (e) {
        }

        return []
    }

    function numberValue(value, fallbackValue) {
        var number = Number(value)

        if (isNaN(number))
            return fallbackValue

        return number
    }

    function selectedRangeSeconds() {
        var option = rangeOptions[selectedRange]

        if (!option)
            return 3600

        return Number(option.seconds)
    }

    function selectedRangeHours() {
        var option = rangeOptions[selectedRange]

        if (!option)
            return 1

        return Number(option.hours)
    }

    function selectedRangeLabel() {
        var option = rangeOptions[selectedRange]

        if (!option)
            return "1 HR"

        return String(option.label)
    }

    function loadThresholds() {
        temperatureUnitValue = normalizedTemperatureUnit(
            backendValue(
                ["temperatureUnit", "thermalUnit"],
                contextValue(
                    ["temperatureUnit", "unit"],
                    "F"
                )
            )
        )

        var defaultWarning =
            temperatureUnitValue === "C"
            ? 65
            : 150

        var defaultCritical =
            temperatureUnitValue === "C"
            ? 80
            : 176

        warningThreshold = numberValue(
            backendValue(
                [
                    "temperatureWarningThreshold",
                    "thermalWarningThreshold",
                    "warningTemperature"
                ],
                defaultWarning
            ),
            defaultWarning
        )

        criticalThreshold = numberValue(
            backendValue(
                [
                    "temperatureCriticalThreshold",
                    "thermalCriticalThreshold",
                    "criticalTemperature"
                ],
                defaultCritical
            ),
            defaultCritical
        )
    }

    function normalizedTemperatureUnit(value) {
        var text =
            cleanText(value)
            .replace("°", "")
            .toUpperCase()

        if (text === "C" ||
                text === "CELSIUS") {
            return "C"
        }

        return "F"
    }

    function parseTemperature(value) {
        if (value === undefined || value === null)
            return NaN

        if (typeof value === "number")
            return value

        var text =
            cleanText(value)
            .replace("°F", "")
            .replace("°C", "")
            .replace("°", "")
            .replace("F", "")
            .replace("C", "")

        return Number(text)
    }

    function formatTemperature(value) {
        var number = Number(value)

        if (isNaN(number))
            return "--"

        return number.toFixed(1) +
               "°" +
               temperatureUnitValue
    }

    function refreshCurrentTemperature() {
        var value = backendValue(
            [
                "temperature",
                "cpuTemperature",
                "cpuTemp",
                "temp"
            ],
            contextValue(
                [
                    "temperature",
                    "cpuTemperature"
                ],
                NaN
            )
        )

        var parsed = parseTemperature(value)

        if (!isNaN(parsed))
            currentTemperatureValue = parsed

        thermalStatusValue = String(
            backendValue(
                [
                    "thermalStatus",
                    "throttleStatus",
                    "thermalState"
                ],
                currentTemperatureValue >= criticalThreshold
                ? "CRITICAL"
                : currentTemperatureValue >= warningThreshold
                  ? "WARNING"
                  : "NORMAL"
            )
        ).toUpperCase()

        throttlingEventCount = calculateThrottleCount()
    }

    function refreshBackend() {
        var monitor = backend()

        if (!monitor)
            return

        try {
            if (typeof monitor.refreshTemperatureHistory === "function") {
                monitor.refreshTemperatureHistory()
            } else if (typeof monitor.refreshThermalHistory === "function") {
                monitor.refreshThermalHistory()
            } else if (typeof monitor.refresh === "function") {
                monitor.refresh()
            }
        } catch (e) {
        }
    }

    function requestHistory() {
        loadThresholds()
        refreshBackend()

        var monitor = backend()
        var result = null

        if (monitor) {
            try {
                if (typeof monitor.setTemperatureHistoryRange === "function") {
                    monitor.setTemperatureHistoryRange(
                        selectedRangeSeconds()
                    )
                }
            } catch (e1) {
            }

            try {
                if (typeof monitor.getTemperatureHistory === "function") {
                    result = monitor.getTemperatureHistory(
                        selectedRangeSeconds()
                    )
                }
            } catch (e2) {
                result = null
            }

            if (!result) {
                try {
                    if (typeof monitor.requestTemperatureHistory === "function") {
                        monitor.requestTemperatureHistory(
                            selectedRangeSeconds()
                        )
                    }
                } catch (e3) {
                }
            }
        }

        if (result)
            loadHistory(result)
        else
            reloadHistoryFromBackend()

        refreshCurrentTemperature()

        actionRequested(
            "rangeChanged",
            {
                "hours": selectedRangeHours(),
                "seconds": selectedRangeSeconds(),
                "label": selectedRangeLabel()
            }
        )
    }

    function reloadHistoryFromBackend() {
        var history = backendValue(
            [
                "temperatureHistory",
                "thermalHistory",
                "cpuTemperatureHistory"
            ],
            contextValue(
                [
                    "temperatureHistory",
                    "thermalHistory",
                    "history"
                ],
                []
            )
        )

        loadHistory(history)
    }

    function loadHistory(history) {
        var raw = normalizedArray(history)
        var normalized = []
        var rangeMilliseconds =
            selectedRangeSeconds() * 1000

        var now = Date.now()
        var minimumTime =
            now - rangeMilliseconds

        for (var i = 0; i < raw.length; i++) {
            var entry = raw[i]
            var sample = normalizeSample(
                entry,
                i,
                raw.length,
                minimumTime,
                now
            )

            if (!sample)
                continue

            /*
                Retain a small boundary sample immediately before the range
                only when the backend already provided it. This allows the
                graph line to enter the visible range cleanly.
            */
            if (sample.timestamp >= minimumTime ||
                    i === 0) {
                normalized.push(sample)
            }
        }

        normalized.sort(function(a, b) {
            return a.timestamp - b.timestamp
        })

        temperatureSnapshot = normalized
        calculateStatistics()
        historyRevision++

        if (temperatureSnapshot.length <= 0) {
            statusMessage =
                "NO TEMPERATURE HISTORY IS AVAILABLE FOR " +
                selectedRangeLabel()

            statusIsError = true
        } else {
            statusMessage =
                temperatureSnapshot.length +
                (
                    temperatureSnapshot.length === 1
                    ? " SAMPLE"
                    : " SAMPLES"
                ) +
                " LOADED FOR " +
                selectedRangeLabel()

            statusIsError = false
        }
    }

    function normalizeSample(
        entry,
        index,
        total,
        rangeStart,
        rangeEnd
    ) {
        var temperature = NaN
        var timestamp = NaN
        var throttled = false

        if (typeof entry === "number") {
            temperature = Number(entry)
        } else if (entry) {
            temperature = parseTemperature(
                objectValue(
                    entry,
                    [
                        "temperature",
                        "temp",
                        "value",
                        "cpuTemperature"
                    ],
                    NaN
                )
            )

            timestamp = parseTimestamp(
                objectValue(
                    entry,
                    [
                        "timestamp",
                        "time",
                        "date",
                        "epoch",
                        "recordedAt"
                    ],
                    NaN
                )
            )

            var rawThrottled = objectValue(
                entry,
                [
                    "throttled",
                    "isThrottled",
                    "thermalThrottle"
                ],
                false
            )

            throttled =
                rawThrottled === true ||
                String(rawThrottled).toLowerCase() === "true" ||
                String(rawThrottled) === "1"
        }

        if (isNaN(temperature))
            return null

        if (isNaN(timestamp)) {
            if (total <= 1) {
                timestamp = rangeEnd
            } else {
                timestamp =
                    rangeStart +
                    (
                        (rangeEnd - rangeStart) *
                        index /
                        (total - 1)
                    )
            }
        }

        return {
            "timestamp": timestamp,
            "temperature": temperature,
            "throttled": throttled
        }
    }

    function parseTimestamp(value) {
        if (value === undefined || value === null)
            return NaN

        if (value instanceof Date)
            return value.getTime()

        if (typeof value === "number") {
            if (value < 100000000000)
                return value * 1000

            return value
        }

        var text = cleanText(value)

        if (text.length <= 0)
            return NaN

        var numeric = Number(text)

        if (!isNaN(numeric)) {
            if (numeric < 100000000000)
                return numeric * 1000

            return numeric
        }

        var parsed = Date.parse(text)

        if (isNaN(parsed))
            return NaN

        return parsed
    }

    function calculateStatistics() {
        if (temperatureSnapshot.length <= 0) {
            minimumTemperatureValue = 0
            maximumTemperatureValue = 0
            averageTemperatureValue = 0
            throttlingEventCount = 0
            return
        }

        var minimum =
            temperatureSnapshot[0].temperature

        var maximum =
            temperatureSnapshot[0].temperature

        var sum = 0
        var throttleCount = 0

        for (var i = 0;
                i < temperatureSnapshot.length;
                i++) {
            var sample = temperatureSnapshot[i]
            var value = Number(sample.temperature)

            minimum = Math.min(minimum, value)
            maximum = Math.max(maximum, value)
            sum += value

            if (sample.throttled === true)
                throttleCount++
        }

        minimumTemperatureValue = minimum
        maximumTemperatureValue = maximum

        averageTemperatureValue =
            sum / temperatureSnapshot.length

        throttlingEventCount = Math.max(
            throttleCount,
            calculateThrottleCount()
        )
    }

    function calculateThrottleCount() {
        var direct = Number(
            backendValue(
                [
                    "throttlingEvents",
                    "thermalThrottleCount"
                ],
                0
            )
        )

        if (!isNaN(direct) && direct >= 0)
            return Math.round(direct)

        var current = backendValue(
            [
                "thermalThrottled",
                "throttled"
            ],
            false
        )

        return current === true ? 1 : 0
    }

    function temperatureColor(value) {
        var number = Number(value)

        if (number >= criticalThreshold)
            return dangerRed

        if (number >= warningThreshold)
            return warningGold

        return neutronBlue
    }

    function thermalStatusColor() {
        var status = thermalStatusValue.toLowerCase()

        if (status.indexOf("critical") >= 0 ||
                status.indexOf("thrott") >= 0) {
            return dangerRed
        }

        if (status.indexOf("warn") >= 0 ||
                status.indexOf("hot") >= 0) {
            return warningGold
        }

        return successGreen
    }

    /*
        ============================================================
                            ACTIONS
        ============================================================
    */

    function actionTitle(index) {
        return index === 0
               ? "REFRESH"
               : "CLOSE"
    }

    function activateAction() {
        if (selectedAction === 0) {
            requestHistory()

            actionRequested(
                "refresh",
                {
                    "hours": selectedRangeHours(),
                    "seconds": selectedRangeSeconds()
                }
            )

            return true
        }

        close()
        return true
    }

    function setRange(index) {
        if (index < 0 ||
                index >= rangeCount) {
            return false
        }

        selectedRange = index
        requestHistory()
        return true
    }

    function moveRange(delta) {
        selectedRange =
            (selectedRange + delta + rangeCount) %
            rangeCount

        requestHistory()
        return true
    }

    /*
        ============================================================
                        CONTROLLER HANDLING
        ============================================================
    */

    function normalizeAction(action) {
        var value =
            String(action || "")
            .trim()
            .toLowerCase()

        if (value === "x" ||
                value === "cross" ||
                value === "primary" ||
                value === "confirm") {
            return "primary"
        }

        if (value === "o" ||
                value === "circle" ||
                value === "cancel" ||
                value === "back") {
            return "cancel"
        }

        if (value === "triangle" ||
                value === "context") {
            return "context"
        }

        if (value === "options" ||
                value === "start" ||
                value === "system") {
            return "system"
        }

        if (value === "dpad_left")
            return "left"

        if (value === "dpad_right")
            return "right"

        if (value === "dpad_up")
            return "up"

        if (value === "dpad_down")
            return "down"

        return value
    }

    function handleControllerPressed(action) {
        if (!visible)
            return false

        var normalized =
            normalizeAction(action)

        if (normalized === "cancel") {
            close()
            return true
        }

        if (normalized === "context") {
            requestHistory()
            return true
        }

        if (focusZone === 0) {
            if (normalized === "left") {
                selectedAction =
                    (selectedAction - 1 + actionCount) %
                    actionCount

                return true
            }

            if (normalized === "right") {
                selectedAction =
                    (selectedAction + 1) %
                    actionCount

                return true
            }

            if (normalized === "down") {
                focusZone = 1
                return true
            }

            if (normalized === "primary" ||
                    normalized === "system") {
                return activateAction()
            }

            return true
        }

        if (normalized === "left")
            return moveRange(-1)

        if (normalized === "right")
            return moveRange(1)

        if (normalized === "up") {
            focusZone = 0
            return true
        }

        if (normalized === "primary" ||
                normalized === "system") {
            return setRange(selectedRange)
        }

        return true
    }

    function handleController(action) {
        return handleControllerPressed(action)
    }

    function handleControllerReleased(action) {
        return visible
    }

    /*
        ============================================================
                        BACKEND CHANGE CONNECTIONS
        ============================================================
    */

    Connections {
        target: root.backend()
        enabled: root.visible
        ignoreUnknownSignals: true

        function onTemperatureHistoryChanged() {
            root.reloadHistoryFromBackend()
        }

        function onThermalHistoryChanged() {
            root.reloadHistoryFromBackend()
        }

        function onCpuTemperatureHistoryChanged() {
            root.reloadHistoryFromBackend()
        }

        function onTemperatureHistoryRevisionChanged() {
            root.reloadHistoryFromBackend()
        }

        function onTemperatureChanged() {
            root.refreshCurrentTemperature()
        }

        function onCpuTemperatureChanged() {
            root.refreshCurrentTemperature()
        }

        function onThermalStatusChanged() {
            root.refreshCurrentTemperature()
        }

        function onThrottlingEventsChanged() {
            root.refreshCurrentTemperature()
        }
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================
    */

    Keys.onPressed: function(event) {
        if (event.isAutoRepeat)
            return

        if (event.key === Qt.Key_Left ||
                event.key === Qt.Key_A) {
            handleControllerPressed("left")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Right ||
                event.key === Qt.Key_D) {
            handleControllerPressed("right")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Up ||
                event.key === Qt.Key_W) {
            handleControllerPressed("up")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Down ||
                event.key === Qt.Key_S) {
            handleControllerPressed("down")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Return ||
                event.key === Qt.Key_Enter ||
                event.key === Qt.Key_Space) {
            handleControllerPressed("primary")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Escape ||
                event.key === Qt.Key_Backspace) {
            handleControllerPressed("cancel")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_F5) {
            handleControllerPressed("context")
            event.accepted = true
        }
    }

    /*
        ============================================================
                            POINTER FALLBACK
        ============================================================
    */

    MouseArea {
        anchors.fill: parent
        enabled: root.pointerEnabled
        acceptedButtons: Qt.LeftButton

        onClicked:
            root.close()
    }

    /*
        ============================================================
                                PANEL
        ============================================================
    */

    Rectangle {
        id: panel

        anchors.centerIn: parent

        width:
            Math.min(
                parent.width * 0.86,
                1420
            )

        height:
            Math.min(
                parent.height * 0.82,
                830
            )

        radius: 34
        color: root.panelColor
        opacity: 1.0

        border.width: 2
        border.color: root.neutronBlue

        MouseArea {
            anchors.fill: parent
            enabled: root.pointerEnabled
            acceptedButtons: Qt.LeftButton

            onClicked: function(mouse) {
                mouse.accepted = true
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2

            radius: parent.radius - 2
            color: root.panelInner

            border.width: 1
            border.color: "#2a4d78"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 16

            /*
                HEADER
            */

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "TEMPERATURE HISTORY"
                        color: "white"

                        font.pixelSize: 34
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Text {
                        text:
                            "CPU THERMAL TREND  •  BACKEND RING BUFFER"

                        color: root.mutedText

                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }

                Repeater {
                    model: root.actionCount

                    Rectangle {
                        required property int index

                        Layout.preferredWidth: 128
                        Layout.preferredHeight: 42

                        radius: 17

                        color:
                            root.focusZone === 0 &&
                            root.selectedAction === index
                            ? "#12335a"
                            : "#081426"

                        border.width:
                            root.focusZone === 0 &&
                            root.selectedAction === index
                            ? 3
                            : 1

                        border.color:
                            root.focusZone === 0 &&
                            root.selectedAction === index
                            ? root.focusBlue
                            : "#3b678f"

                        Text {
                            anchors.centerIn: parent

                            text: root.actionTitle(index)

                            color:
                                root.focusZone === 0 &&
                                root.selectedAction === index
                                ? "white"
                                : "#b9d8ee"

                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.8
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.pointerEnabled

                            onClicked: {
                                root.focusZone = 0
                                root.selectedAction = index
                                root.activateAction()
                            }
                        }
                    }
                }
            }

            /*
                SUMMARY METRICS
            */

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
                spacing: 12

                Repeater {
                    model: [
                        {
                            "label": "CURRENT",
                            "value": root.formatTemperature(
                                root.currentTemperatureValue
                            ),
                            "accent": root.temperatureColor(
                                root.currentTemperatureValue
                            )
                        },
                        {
                            "label": "MINIMUM",
                            "value": root.temperatureSnapshot.length > 0
                                     ? root.formatTemperature(
                                         root.minimumTemperatureValue
                                       )
                                     : "--",
                            "accent": root.neutronBlue
                        },
                        {
                            "label": "AVERAGE",
                            "value": root.temperatureSnapshot.length > 0
                                     ? root.formatTemperature(
                                         root.averageTemperatureValue
                                       )
                                     : "--",
                            "accent": root.purple
                        },
                        {
                            "label": "MAXIMUM",
                            "value": root.temperatureSnapshot.length > 0
                                     ? root.formatTemperature(
                                         root.maximumTemperatureValue
                                       )
                                     : "--",
                            "accent": root.temperatureColor(
                                root.maximumTemperatureValue
                            )
                        },
                        {
                            "label": "THERMAL STATE",
                            "value": root.thermalStatusValue,
                            "accent": root.thermalStatusColor()
                        },
                        {
                            "label": "THROTTLE EVENTS",
                            "value": String(root.throttlingEventCount),
                            "accent": root.throttlingEventCount > 0
                                      ? root.dangerRed
                                      : root.successGreen
                        }
                    ]

                    Rectangle {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        radius: 18
                        color: "#081426"

                        border.width: 1
                        border.color: modelData.accent

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 18
                            spacing: 5

                            Text {
                                width: parent.width

                                text: modelData.label
                                color: root.mutedText

                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1

                                horizontalAlignment:
                                    Text.AlignHCenter

                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width

                                text: modelData.value
                                color: modelData.accent

                                font.pixelSize: 20
                                font.bold: true

                                horizontalAlignment:
                                    Text.AlignHCenter

                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            /*
                RANGE SELECTOR
            */

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                spacing: 12

                Text {
                    Layout.preferredWidth: 170

                    text: "TIME RANGE"
                    color: "white"

                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1
                }

                Repeater {
                    model: root.rangeOptions

                    Rectangle {
                        required property int index
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        radius: 18

                        color:
                            root.selectedRange === index
                            ? "#12335a"
                            : "#081426"

                        border.width:
                            root.focusZone === 1 &&
                            root.selectedRange === index
                            ? 3
                            : root.selectedRange === index
                              ? 2
                              : 1

                        border.color:
                            root.focusZone === 1 &&
                            root.selectedRange === index
                            ? root.focusBlue
                            : root.selectedRange === index
                              ? root.neutronBlue
                              : "#3b678f"

                        Text {
                            anchors.centerIn: parent

                            text: modelData.label

                            color:
                                root.selectedRange === index
                                ? "white"
                                : root.mutedText

                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.pointerEnabled

                            onClicked: {
                                root.focusZone = 1
                                root.setRange(index)
                            }
                        }
                    }
                }
            }

            /*
                STATIC-REDRAW GRAPH
            */

            Rectangle {
                id: graphPanel

                Layout.fillWidth: true
                Layout.fillHeight: true

                radius: 22
                color: "#050e1b"

                border.width: 1
                border.color: "#2b5a82"

                clip: true

                Canvas {
                    id: graphCanvas

                    anchors.fill: parent
                    anchors.margins: 10

                    antialiasing: true
                    renderStrategy: Canvas.Cooperative

                    onPaint: {
                        var context =
                            getContext("2d")

                        root.paintGraph(
                            context,
                            width,
                            height
                        )
                    }

                    onWidthChanged:
                        requestPaint()

                    onHeightChanged:
                        requestPaint()
                }

                Text {
                    anchors.centerIn: parent

                    visible:
                        root.temperatureSnapshot.length <= 0

                    text:
                        "TEMPERATURE HISTORY IS NOT AVAILABLE"

                    color: root.mutedText

                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1
                }
            }

            /*
                STATUS / FOOTER
            */

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 16

                Text {
                    Layout.fillWidth: true

                    text: root.statusMessage

                    color:
                        root.statusIsError
                        ? "#ff9a9a"
                        : root.successGreen

                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 0.8

                    elide: Text.ElideRight
                }

                Text {
                    text:
                        root.focusZone === 0
                        ? "LEFT/RIGHT ACTION  •  DOWN RANGE  •  O CLOSE"
                        : "LEFT/RIGHT RANGE  •  UP ACTIONS  •  TRIANGLE REFRESH  •  O CLOSE"

                    color: "#9fd8ff"

                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.8

                    horizontalAlignment:
                        Text.AlignRight
                }
            }
        }
    }

    /*
        ============================================================
                        CANVAS GRAPH RENDERING
        ============================================================
    */

    function paintGraph(context, width, height) {
        context.reset()
        context.clearRect(0, 0, width, height)

        var left = 62
        var right = 20
        var top = 22
        var bottom = 42

        var graphWidth =
            Math.max(1, width - left - right)

        var graphHeight =
            Math.max(1, height - top - bottom)

        context.fillStyle = "#06101d"
        context.fillRect(
            left,
            top,
            graphWidth,
            graphHeight
        )

        var yRange = graphTemperatureRange()
        var yMinimum = yRange.minimum
        var yMaximum = yRange.maximum

        drawGraphGrid(
            context,
            left,
            top,
            graphWidth,
            graphHeight,
            yMinimum,
            yMaximum
        )

        drawThresholdLine(
            context,
            left,
            top,
            graphWidth,
            graphHeight,
            yMinimum,
            yMaximum,
            warningThreshold,
            "#f5c542",
            "WARNING"
        )

        drawThresholdLine(
            context,
            left,
            top,
            graphWidth,
            graphHeight,
            yMinimum,
            yMaximum,
            criticalThreshold,
            "#ff3040",
            "CRITICAL"
        )

        if (temperatureSnapshot.length > 0) {
            drawTemperatureArea(
                context,
                left,
                top,
                graphWidth,
                graphHeight,
                yMinimum,
                yMaximum
            )

            drawThrottleMarkers(
                context,
                left,
                top,
                graphWidth,
                graphHeight,
                yMinimum,
                yMaximum
            )
        }

        drawTimeLabels(
            context,
            left,
            top,
            graphWidth,
            graphHeight
        )
    }

    function graphTemperatureRange() {
        var defaultMinimum =
            temperatureUnitValue === "C"
            ? 25
            : 77

        var defaultMaximum =
            temperatureUnitValue === "C"
            ? 90
            : 194

        if (temperatureSnapshot.length <= 0) {
            return {
                "minimum": defaultMinimum,
                "maximum": defaultMaximum
            }
        }

        var minimum = Math.min(
            minimumTemperatureValue,
            warningThreshold
        )

        var maximum = Math.max(
            maximumTemperatureValue,
            criticalThreshold
        )

        var padding =
            temperatureUnitValue === "C"
            ? 5
            : 9

        minimum = Math.floor(minimum - padding)
        maximum = Math.ceil(maximum + padding)

        if (maximum - minimum < padding * 4)
            maximum = minimum + padding * 4

        return {
            "minimum": minimum,
            "maximum": maximum
        }
    }

    function drawGraphGrid(
        context,
        left,
        top,
        width,
        height,
        yMinimum,
        yMaximum
    ) {
        context.lineWidth = 1
        context.strokeStyle = "#29445f88"
        context.fillStyle = "#8aa6c8"
        context.font = "bold 11px sans-serif"
        context.textAlign = "right"
        context.textBaseline = "middle"

        var horizontalLines = 5

        for (var i = 0;
                i <= horizontalLines;
                i++) {
            var ratio =
                i / horizontalLines

            var y =
                top + height * ratio

            context.beginPath()
            context.moveTo(left, y)
            context.lineTo(left + width, y)
            context.stroke()

            var value =
                yMaximum -
                (
                    (yMaximum - yMinimum) *
                    ratio
                )

            context.fillText(
                Math.round(value) +
                "°" +
                temperatureUnitValue,
                left - 10,
                y
            )
        }

        context.strokeStyle = "#1b334c66"

        var verticalLines = 6

        for (var column = 0;
                column <= verticalLines;
                column++) {
            var x =
                left +
                width *
                column /
                verticalLines

            context.beginPath()
            context.moveTo(x, top)
            context.lineTo(x, top + height)
            context.stroke()
        }
    }

    function drawThresholdLine(
        context,
        left,
        top,
        width,
        height,
        yMinimum,
        yMaximum,
        threshold,
        color,
        label
    ) {
        if (threshold < yMinimum ||
                threshold > yMaximum) {
            return
        }

        var y = graphY(
            threshold,
            top,
            height,
            yMinimum,
            yMaximum
        )

        context.lineWidth = 1.5
        context.strokeStyle = color
        context.globalAlpha = 0.72

        context.beginPath()
        context.moveTo(left, y)
        context.lineTo(left + width, y)
        context.stroke()

        context.globalAlpha = 1.0
        context.fillStyle = color
        context.font = "bold 10px sans-serif"
        context.textAlign = "left"
        context.textBaseline = "bottom"

        context.fillText(
            label + " " +
            formatTemperature(threshold),
            left + 8,
            y - 3
        )
    }

    function drawTemperatureArea(
        context,
        left,
        top,
        width,
        height,
        yMinimum,
        yMaximum
    ) {
        var bounds = graphTimeBounds()
        var startTime = bounds.start
        var endTime = bounds.end

        var gradient =
            context.createLinearGradient(
                0,
                top,
                0,
                top + height
            )

        gradient.addColorStop(
            0,
            "rgba(125,249,255,0.35)"
        )

        gradient.addColorStop(
            1,
            "rgba(77,166,255,0.02)"
        )

        context.beginPath()

        for (var i = 0;
                i < temperatureSnapshot.length;
                i++) {
            var sample =
                temperatureSnapshot[i]

            var x = graphX(
                sample.timestamp,
                left,
                width,
                startTime,
                endTime
            )

            var y = graphY(
                sample.temperature,
                top,
                height,
                yMinimum,
                yMaximum
            )

            if (i === 0)
                context.moveTo(x, y)
            else
                context.lineTo(x, y)
        }

        var last =
            temperatureSnapshot[
                temperatureSnapshot.length - 1
            ]

        var first =
            temperatureSnapshot[0]

        context.lineTo(
            graphX(
                last.timestamp,
                left,
                width,
                startTime,
                endTime
            ),
            top + height
        )

        context.lineTo(
            graphX(
                first.timestamp,
                left,
                width,
                startTime,
                endTime
            ),
            top + height
        )

        context.closePath()
        context.fillStyle = gradient
        context.fill()

        context.beginPath()

        for (var lineIndex = 0;
                lineIndex < temperatureSnapshot.length;
                lineIndex++) {
            var lineSample =
                temperatureSnapshot[lineIndex]

            var lineX = graphX(
                lineSample.timestamp,
                left,
                width,
                startTime,
                endTime
            )

            var lineY = graphY(
                lineSample.temperature,
                top,
                height,
                yMinimum,
                yMaximum
            )

            if (lineIndex === 0)
                context.moveTo(lineX, lineY)
            else
                context.lineTo(lineX, lineY)
        }

        context.lineWidth = 3
        context.strokeStyle = "#7df9ff"
        context.shadowColor = "#4da6ff"
        context.shadowBlur = 8
        context.stroke()
        context.shadowBlur = 0

        /*
            Draw only a limited number of point markers. This preserves
            readability without turning a long 24-hour series into hundreds
            of expensive circles.
        */
        var markerStep =
            Math.max(
                1,
                Math.ceil(
                    temperatureSnapshot.length / 32
                )
            )

        for (var markerIndex = 0;
                markerIndex < temperatureSnapshot.length;
                markerIndex += markerStep) {
            var marker =
                temperatureSnapshot[markerIndex]

            var markerX = graphX(
                marker.timestamp,
                left,
                width,
                startTime,
                endTime
            )

            var markerY = graphY(
                marker.temperature,
                top,
                height,
                yMinimum,
                yMaximum
            )

            context.beginPath()
            context.arc(
                markerX,
                markerY,
                3,
                0,
                Math.PI * 2
            )

            context.fillStyle =
                marker.temperature >= criticalThreshold
                ? "#ff3040"
                : marker.temperature >= warningThreshold
                  ? "#f5c542"
                  : "#7df9ff"

            context.fill()
        }
    }

    function drawThrottleMarkers(
        context,
        left,
        top,
        width,
        height,
        yMinimum,
        yMaximum
    ) {
        var bounds = graphTimeBounds()

        for (var i = 0;
                i < temperatureSnapshot.length;
                i++) {
            var sample =
                temperatureSnapshot[i]

            if (sample.throttled !== true)
                continue

            var x = graphX(
                sample.timestamp,
                left,
                width,
                bounds.start,
                bounds.end
            )

            var y = graphY(
                sample.temperature,
                top,
                height,
                yMinimum,
                yMaximum
            )

            context.beginPath()
            context.arc(
                x,
                y,
                7,
                0,
                Math.PI * 2
            )

            context.lineWidth = 2
            context.strokeStyle = "#ff3040"
            context.fillStyle = "#5c1018"
            context.fill()
            context.stroke()
        }
    }

    function drawTimeLabels(
        context,
        left,
        top,
        width,
        height
    ) {
        var bounds = graphTimeBounds()
        var divisions = 6

        context.fillStyle = "#8aa6c8"
        context.font = "bold 10px sans-serif"
        context.textAlign = "center"
        context.textBaseline = "top"

        for (var i = 0; i <= divisions; i++) {
            var ratio = i / divisions
            var timestamp =
                bounds.start +
                (
                    (bounds.end - bounds.start) *
                    ratio
                )

            context.fillText(
                formatGraphTime(timestamp),
                left + width * ratio,
                top + height + 10
            )
        }
    }

    function graphTimeBounds() {
        var end = Date.now()
        var start =
            end -
            selectedRangeSeconds() *
            1000

        if (temperatureSnapshot.length > 0) {
            var newest =
                temperatureSnapshot[
                    temperatureSnapshot.length - 1
                ].timestamp

            if (newest > end)
                end = newest

            start =
                end -
                selectedRangeSeconds() *
                1000
        }

        return {
            "start": start,
            "end": end
        }
    }

    function graphX(
        timestamp,
        left,
        width,
        startTime,
        endTime
    ) {
        if (endTime <= startTime)
            return left

        var ratio =
            (timestamp - startTime) /
            (endTime - startTime)

        ratio =
            Math.max(
                0,
                Math.min(1, ratio)
            )

        return left + width * ratio
    }

    function graphY(
        temperature,
        top,
        height,
        minimum,
        maximum
    ) {
        if (maximum <= minimum)
            return top + height

        var ratio =
            (temperature - minimum) /
            (maximum - minimum)

        ratio =
            Math.max(
                0,
                Math.min(1, ratio)
            )

        return top + height * (1 - ratio)
    }

    function formatGraphTime(timestamp) {
        var date = new Date(timestamp)

        if (selectedRangeHours() <= 12)
            return Qt.formatTime(date, "h:mm AP")

        return Qt.formatDateTime(
            date,
            "MMM d\nh AP"
        )
    }

    onHistoryRevisionChanged:
        graphCanvas.requestPaint()

    onWarningThresholdChanged:
        graphCanvas.requestPaint()

    onCriticalThresholdChanged:
        graphCanvas.requestPaint()

    onTemperatureUnitValueChanged:
        graphCanvas.requestPaint()

    onVisibleChanged: {
        if (!visible) {
            focusZone = 1
            selectedAction = 0
            selectedRange = 0
        } else {
            Qt.callLater(
                graphCanvas.requestPaint
            )
        }
    }
}