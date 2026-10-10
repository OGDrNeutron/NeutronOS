import QtQuick 2.15
import QtQuick.Layouts 1.15
import "../../systemwidgets" as SystemWidgets

Rectangle {
    id: root

    property string mode: "cpu"
    property var contextData: ({})
    property var modalContext: ({})
    property bool pointerEnabled: true
    property bool animationsEnabled: visible && enabled

    readonly property bool cpuMode: mode.toLowerCase() === "cpu"
    readonly property var monitor:
        (typeof systemMonitor !== "undefined" && systemMonitor)
        ? systemMonitor
        : null

    property int selectedAction: 0
    property int selectedTopProcess: 0
    property int selectedProcess: 0
    property int focusZone: 0
    property string processSort: cpuMode ? "cpu" : "memory"

    property var summarySnapshot: []
    property var topProcessSnapshot: []
    property var processSnapshot: []
    property var coreSnapshot: []

    property string lastNavigationAction: ""
    property double lastNavigationAt: 0
    property int navigationDebounceMs: 105

    property color neutronBlue: "#7df9ff"
    property color focusBlue: "#4da6ff"
    property color successGreen: "#22ff88"
    property color warningGold: "#f5c542"
    property color dangerRed: "#ff3040"
    property color purple: "#c78cff"
    property color pink: "#ff67c7"
    property color mutedText: "#8aa6c8"

    readonly property int actionCount: 4
    readonly property int actionAnchorBase: cpuMode ? 16000 : 26000
    readonly property int topProcessAnchorBase: cpuMode ? 16100 : 26100
    readonly property int processAnchorBase: cpuMode ? 16500 : 26500

    signal closed()
    signal actionRequested(string action, var payload)

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    activeFocusOnTab: true
    color: "#70000000"
    opacity: 1.0
    z: 999

    function cleanText(value) {
        if (value === undefined || value === null)
            return ""
        var text = String(value).trim()
        return text === "undefined" || text === "null" ? "" : text
    }

    function objectValue(object, keys, fallbackValue) {
        if (!object)
            return fallbackValue

        for (var i = 0; i < keys.length; ++i) {
            try {
                var value = object[keys[i]]
                if (value !== undefined && value !== null && String(value).length > 0)
                    return value
            } catch (error) {
            }
        }
        return fallbackValue
    }

    function numberValue(value, fallbackValue) {
        var number = Number(value)
        return isNaN(number) ? fallbackValue : number
    }

    function clampPercent(value) {
        return Math.max(0, Math.min(100, numberValue(value, 0)))
    }

    function normalizedArray(value) {
        if (value === undefined || value === null)
            return []

        try {
            if (Array.isArray(value))
                return value.slice(0)
        } catch (arrayError) {
        }

        var count = 0
        try {
            count = value.length !== undefined ? Number(value.length) : Number(value.count)
        } catch (countError) {
            count = 0
        }

        if (isNaN(count) || count <= 0)
            return []

        var result = []
        for (var i = 0; i < count; ++i) {
            try {
                result.push(value[i])
            } catch (entryError) {
            }
        }
        return result
    }

    function processPid(process) {
        return String(objectValue(process, ["pid", "processId"], "--"))
    }

    function processName(process) {
        return String(objectValue(process,
                                  ["name", "processName", "command", "comm"],
                                  "Unknown"))
    }

    function processUser(process) {
        return String(objectValue(process, ["user", "username", "owner"], "--"))
    }

    function processCpu(process) {
        return numberValue(objectValue(process, ["cpu", "cpuPercent", "usage"], 0), 0)
    }

    function processMemory(process) {
        return numberValue(objectValue(process,
                                       ["memory", "memoryPercent", "ram", "mem"],
                                       0), 0)
    }

    function processMemoryBytes(process) {
        return numberValue(objectValue(process,
                                       ["memoryBytes", "residentBytes", "rssBytes", "rss"],
                                       0), 0)
    }

    function processState(process) {
        return String(objectValue(process, ["state", "status"], "--"))
    }

    function processRuntime(process) {
        return String(objectValue(process, ["runtime", "elapsed", "time"], "--"))
    }

    function formatBytes(bytes) {
        var value = Math.max(0, numberValue(bytes, 0))
        var units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var unit = 0
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024
            ++unit
        }
        var decimals = unit === 0 ? 0 : (unit >= 3 ? 2 : 1)
        return value.toFixed(decimals) + " " + units[unit]
    }

    function percentText(value) {
        return numberValue(value, 0).toFixed(1) + "%"
    }

    function usageColor(value) {
        var percent = clampPercent(value)
        if (percent >= 90)
            return dangerRed
        if (percent >= 70)
            return warningGold
        return successGreen
    }

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        selectedAction = 0
        selectedTopProcess = 0
        selectedProcess = 0
        focusZone = 0
        processSort = cpuMode ? "cpu" : "memory"
        visible = true
        requestBackendRefresh(true)
        refreshData()
        Qt.callLater(function() {
            if (root.visible)
                root.forceActiveFocus()
        })
    }

    function openModal(context) {
        open(context)
    }

    function close() {
        if (!visible)
            return
        if (processDetails.visible) {
            processDetails.close()
            return
        }

        visible = false
        summarySnapshot = []
        topProcessSnapshot = []
        processSnapshot = []
        coreSnapshot = []
        lastNavigationAction = ""
        lastNavigationAt = 0
        closed()
    }

    function closeModal() {
        close()
    }

    function requestBackendRefresh(includeProcesses) {
        if (!monitor)
            return

        try {
            if (cpuMode && typeof monitor.refreshCpuMonitor === "function")
                monitor.refreshCpuMonitor()
            else if (!cpuMode && typeof monitor.refreshMemoryMonitor === "function")
                monitor.refreshMemoryMonitor()
        } catch (monitorError) {
        }

        if (includeProcesses) {
            try {
                if (typeof monitor.refreshProcesses === "function")
                    monitor.refreshProcesses()
            } catch (processError) {
            }
        }
    }

    function sourceArray(keys) {
        if (!monitor)
            return []

        for (var i = 0; i < keys.length; ++i) {
            try {
                var rows = normalizedArray(monitor[keys[i]])
                if (rows.length > 0)
                    return rows
            } catch (error) {
            }
        }
        return []
    }

    function buildProcessSnapshot() {
        var rows = cpuMode
                ? sourceArray(["cpuProcesses", "processesByCpu", "processList"])
                : sourceArray(["memoryProcesses", "processesByMemory", "processList"])

        if (rows.length <= 0) {
            rows = normalizedArray(objectValue(contextData,
                                               ["processes", cpuMode ? "cpuProcesses" : "memoryProcesses"],
                                               []))
        }

        rows.sort(function(a, b) {
            if (processSort === "name")
                return processName(a).localeCompare(processName(b))
            if (processSort === "pid")
                return Number(processPid(a)) - Number(processPid(b))
            if (processSort === "memory") {
                var byteDifference = processMemoryBytes(b) - processMemoryBytes(a)
                return byteDifference !== 0 ? byteDifference : processMemory(b) - processMemory(a)
            }
            return processCpu(b) - processCpu(a)
        })

        return rows.slice(0, Math.min(128, rows.length))
    }

    function buildTopSnapshot(allRows) {
        var rows = cpuMode
                ? sourceArray(["topCpuProcesses", "cpuProcesses", "processList"])
                : sourceArray(["topRamProcesses", "memoryProcesses", "processList"])

        if (rows.length <= 0)
            rows = allRows.slice(0)

        rows.sort(function(a, b) {
            if (cpuMode)
                return processCpu(b) - processCpu(a)
            var byteDifference = processMemoryBytes(b) - processMemoryBytes(a)
            return byteDifference !== 0 ? byteDifference : processMemory(b) - processMemory(a)
        })

        return rows.slice(0, Math.min(3, rows.length))
    }

    function monitorValue(keys, fallbackValue) {
        return objectValue(monitor, keys, fallbackValue)
    }

    function rebuildSummarySnapshot() {
        if (cpuMode) {
            summarySnapshot = [
                { "label": "TOTAL CPU", "value": Math.round(clampPercent(monitorValue(["cpuPercent", "cpuUsagePercent", "cpuUsage"], 0))) + "%", "accent": usageColor(monitorValue(["cpuPercent", "cpuUsagePercent"], 0)) },
                { "label": "TEMPERATURE", "value": cleanText(monitorValue(["temperature", "cpuTemp"], "--")), "accent": warningGold },
                { "label": "FREQUENCY", "value": cleanText(monitorValue(["cpuFrequency", "cpuFrequencyText"], "--")), "accent": neutronBlue },
                { "label": "GOVERNOR", "value": cleanText(monitorValue(["cpuGovernor", "governor"], "--")), "accent": purple },
                { "label": "LOAD 1 / 5 / 15", "value": cleanText(monitorValue(["loadAverage", "loadAverageText"], "--")), "accent": pink },
                { "label": "PROCESSES", "value": String(monitorValue(["processCount"], processSnapshot.length)), "accent": focusBlue }
            ]
            coreSnapshot = sourceArray(["cpuCores", "perCoreUsage", "cpuCoreUsage"])
        } else {
            summarySnapshot = [
                { "label": "RAM USED", "value": Math.round(clampPercent(monitorValue(["ramPercent", "memoryPercent"], 0))) + "%", "accent": usageColor(monitorValue(["ramPercent", "memoryPercent"], 0)) },
                { "label": "USED / TOTAL", "value": cleanText(monitorValue(["ramUsed", "memoryUsed"], "--")) + " / " + cleanText(monitorValue(["ramTotal", "memoryTotal"], "--")), "accent": neutronBlue },
                { "label": "AVAILABLE", "value": cleanText(monitorValue(["ramAvailable", "memoryAvailable"], "--")), "accent": successGreen },
                { "label": "CACHE", "value": cleanText(monitorValue(["memoryCached", "cachedMemory"], "--")), "accent": purple },
                { "label": "SWAP", "value": cleanText(monitorValue(["swapUsed"], "--")) + " / " + cleanText(monitorValue(["swapTotal"], "--")), "accent": warningGold },
                { "label": "PRESSURE", "value": Math.round(clampPercent(monitorValue(["memoryPressurePercent", "memoryPressure"], 0))) + "%", "accent": pink }
            ]
            coreSnapshot = []
        }
    }

    function refreshData() {
        if (!visible)
            return

        var rows = buildProcessSnapshot()
        processSnapshot = rows
        topProcessSnapshot = buildTopSnapshot(rows)
        rebuildSummarySnapshot()
        clampSelections()
    }

    function clampSelections() {
        selectedAction = Math.max(0, Math.min(actionCount - 1, selectedAction))
        selectedTopProcess = Math.max(0, Math.min(Math.max(0, topProcessSnapshot.length - 1), selectedTopProcess))
        selectedProcess = Math.max(0, Math.min(Math.max(0, processSnapshot.length - 1), selectedProcess))

        if (focusZone === 1 && topProcessSnapshot.length <= 0)
            focusZone = processSnapshot.length > 0 ? 2 : 0
        if (focusZone === 2 && processSnapshot.length <= 0)
            focusZone = topProcessSnapshot.length > 0 ? 1 : 0
    }

    function actionAnchor(index) {
        return actionAnchorBase + index
    }

    function topProcessAnchor(index) {
        return topProcessAnchorBase + index
    }

    function processAnchor(index) {
        return processAnchorBase + index
    }

    function actionTitle(index) {
        if (index === 0)
            return "REFRESH"
        if (index === 1)
            return cpuMode ? "SORT CPU" : "SORT RAM"
        if (index === 2)
            return cpuMode ? "SORT RAM" : "SORT CPU"
        return "CLOSE"
    }

    function selectAction(index) {
        selectedAction = (index % actionCount + actionCount) % actionCount
        focusZone = 0
        forceActiveFocus()
    }

    function selectTop(index) {
        if (topProcessSnapshot.length <= 0)
            return
        selectedTopProcess = Math.max(0, Math.min(topProcessSnapshot.length - 1, index))
        focusZone = 1
        forceActiveFocus()
    }

    function selectProcess(index) {
        if (processSnapshot.length <= 0)
            return
        selectedProcess = Math.max(0, Math.min(processSnapshot.length - 1, index))
        focusZone = 2
        processList.positionViewAtIndex(selectedProcess, ListView.Contain)
        forceActiveFocus()
    }

    function setProcessSort(sortKey) {
        processSort = sortKey
        try {
            if (monitor) {
                if (cpuMode && typeof monitor.setProcessSort === "function")
                    monitor.setProcessSort(sortKey)
                else if (!cpuMode && typeof monitor.setMemoryProcessSort === "function")
                    monitor.setMemoryProcessSort(sortKey)
            }
        } catch (sortError) {
        }
        processSnapshot = buildProcessSnapshot()
        selectedProcess = 0
        processList.positionViewAtBeginning()
        actionRequested("sort", { "sort": sortKey, "source": mode })
    }

    function cycleSort(direction) {
        var sorts = ["cpu", "memory", "name", "pid"]
        var current = sorts.indexOf(processSort)
        if (current < 0)
            current = 0
        setProcessSort(sorts[(current + direction + sorts.length) % sorts.length])
    }

    function activateAction() {
        if (selectedAction === 0) {
            requestBackendRefresh(true)
            refreshData()
            actionRequested("refresh", { "source": mode })
            return true
        }
        if (selectedAction === 1) {
            setProcessSort(cpuMode ? "cpu" : "memory")
            return true
        }
        if (selectedAction === 2) {
            setProcessSort(cpuMode ? "memory" : "cpu")
            return true
        }
        close()
        return true
    }

    function openProcessDetails(process, origin) {
        if (!process)
            return false
        processDetails.open(process,
                            (cpuMode ? "CPU MONITOR" : "RAM MONITOR") +
                            "  •  " + String(origin || "PROCESS"))
        actionRequested("processDetails", {
                            "process": process,
                            "source": mode,
                            "origin": origin
                        })
        return true
    }

    function acceptNavigationPulse(action) {
        if (action !== "left" && action !== "right" &&
                action !== "up" && action !== "down")
            return true

        var now = Date.now()
        if (lastNavigationAction === action &&
                now - lastNavigationAt < navigationDebounceMs)
            return false

        lastNavigationAction = action
        lastNavigationAt = now
        return true
    }

    function normalizeAction(action) {
        var value = String(action || "").trim().toLowerCase()
        if (value === "x" || value === "cross" || value === "primary" || value === "confirm")
            return "primary"
        if (value === "o" || value === "circle" || value === "cancel" || value === "back")
            return "cancel"
        if (value === "triangle" || value === "context")
            return "context"
        if (value === "options" || value === "start" || value === "system")
            return "system"
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

        if (processDetails.visible)
            return processDetails.handleControllerPressed(action)

        var normalized = normalizeAction(action)
        if (!acceptNavigationPulse(normalized))
            return true

        if (!activeFocus)
            forceActiveFocus()

        if (normalized === "cancel") {
            close()
            return true
        }

        if (normalized === "context") {
            requestBackendRefresh(true)
            refreshData()
            return true
        }

        if (normalized === "l1") {
            cycleSort(-1)
            return true
        }
        if (normalized === "r1") {
            cycleSort(1)
            return true
        }

        if (focusZone === 0) {
            if (normalized === "left")
                selectAction(selectedAction - 1)
            else if (normalized === "right")
                selectAction(selectedAction + 1)
            else if (normalized === "down") {
                if (topProcessSnapshot.length > 0)
                    selectTop(0)
                else if (processSnapshot.length > 0)
                    selectProcess(0)
            } else if (normalized === "primary" || normalized === "system")
                return activateAction()
            return true
        }

        if (focusZone === 1) {
            if (normalized === "left")
                selectTop(selectedTopProcess - 1)
            else if (normalized === "right")
                selectTop(selectedTopProcess + 1)
            else if (normalized === "up")
                selectAction(selectedAction)
            else if (normalized === "down" && processSnapshot.length > 0)
                selectProcess(0)
            else if (normalized === "primary")
                return openProcessDetails(topProcessSnapshot[selectedTopProcess], "TOP 3")
            return true
        }

        if (normalized === "up") {
            if (selectedProcess <= 0 && topProcessSnapshot.length > 0)
                selectTop(selectedTopProcess)
            else
                selectProcess(selectedProcess - 1)
            return true
        }
        if (normalized === "down") {
            selectProcess(selectedProcess + 1)
            return true
        }
        if (normalized === "left") {
            cycleSort(-1)
            return true
        }
        if (normalized === "right") {
            cycleSort(1)
            return true
        }
        if (normalized === "primary")
            return openProcessDetails(processSnapshot[selectedProcess], "PROCESS TABLE")

        return true
    }

    function handleController(action) {
        return handleControllerPressed(action)
    }

    function handleControllerReleased(action) {
        if (processDetails.visible)
            return processDetails.handleControllerReleased(action)

        var normalized = normalizeAction(action)
        if (normalized === lastNavigationAction) {
            lastNavigationAction = ""
            lastNavigationAt = 0
        }
        return visible
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Left)
            action = "left"
        else if (event.key === Qt.Key_Right)
            action = "right"
        else if (event.key === Qt.Key_Up)
            action = "up"
        else if (event.key === Qt.Key_Down)
            action = "down"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace)
            action = "cancel"
        else if (event.key === Qt.Key_R)
            action = "context"

        if (action.length > 0)
            event.accepted = handleControllerPressed(action)
    }

    Connections {
        target: root.monitor
        enabled: target !== null
        ignoreUnknownSignals: true

        function onCpuMonitorChanged() {
            if (root.cpuMode)
                root.refreshData()
        }
        function onMemoryMonitorChanged() {
            if (!root.cpuMode)
                root.refreshData()
        }
        function onProcessDataChanged() {
            root.refreshData()
        }
        function onTemperatureChanged() {
            if (root.cpuMode)
                root.rebuildSummarySnapshot()
        }
        function onSystemChanged() {
            root.rebuildSummarySnapshot()
        }
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.visible && !processDetails.visible
        onTriggered: root.refreshData()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.94, 1540)
        height: Math.min(parent.height * 0.92, 960)
        radius: 30
        color: "#050d18"
        border.width: 2
        border.color: root.cpuMode ? root.neutronBlue : root.purple

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 11

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 62
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 50
                    Layout.preferredHeight: 50
                    radius: 25
                    color: root.cpuMode ? "#103049" : "#27163f"
                    border.width: 2
                    border.color: root.cpuMode ? root.neutronBlue : root.purple

                    Text {
                        anchors.centerIn: parent
                        text: root.cpuMode ? "CPU" : "RAM"
                        color: root.cpuMode ? root.neutronBlue : root.purple
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: root.cpuMode ? "CPU MONITOR" : "MEMORY MONITOR"
                        color: "white"
                        font.pixelSize: 27
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.cpuMode
                              ? "LIVE PROCESSOR TELEMETRY  •  SELECT A PROCESS WITH X FOR FULL DIAGNOSTICS"
                              : "LIVE RAM, SWAP, PRESSURE, AND RESIDENT PROCESS TELEMETRY  •  X OPENS DETAILS"
                        color: root.mutedText
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.65
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 38
                    radius: 13
                    color: "#10213a"
                    border.width: 1
                    border.color: root.successGreen

                    Text {
                        anchors.centerIn: parent
                        text: "LIVE  •  " + root.processSnapshot.length
                        color: root.successGreen
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                spacing: 9

                Repeater {
                    model: root.actionCount

                    Rectangle {
                        required property int index
                        readonly property int controllerAnchor: root.actionAnchor(index)
                        objectName: (root.cpuMode ? "cpu" : "memory") + "ActionAnchor_" + controllerAnchor
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        color: root.focusZone === 0 && root.selectedAction === index ? "#14365a" : "#0a1830"
                        border.width: root.focusZone === 0 && root.selectedAction === index ? 3 : 1
                        border.color: root.focusZone === 0 && root.selectedAction === index ? root.focusBlue : "#294d72"

                        Text {
                            anchors.centerIn: parent
                            text: root.actionTitle(index)
                            color: root.focusZone === 0 && root.selectedAction === index ? "white" : root.mutedText
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 0.9
                        }
                    }
                }
            }

            /* PATCH 16B: CIRCULAR RESOURCE GAUGE */
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                radius: 20
                color: "#071426"
                border.width: 1
                border.color: root.cpuMode ? "#2b5a82" : "#5f447d"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    Item {
                        Layout.preferredWidth: 190
                        Layout.fillHeight: true

                        SystemWidgets.CircularUsageGauge {
                            anchors.centerIn: parent
                            width: 178
                            height: 178
                            value: root.cpuMode
                                   ? root.clampPercent(root.monitorValue(
                                         ["cpuPercent", "cpuUsagePercent", "cpuUsage"], 0))
                                   : root.clampPercent(root.monitorValue(
                                         ["ramPercent", "memoryPercent", "memoryUsagePercent"], 0))
                            label: root.cpuMode ? "TOTAL CPU" : "RAM USED"
                            detail: root.cpuMode
                                    ? String(root.monitorValue(
                                          ["cpuGovernor", "governor"], "LIVE"))
                                    : String(root.monitorValue(
                                          ["ramAvailable", "memoryAvailable"], "--")) + " AVAILABLE"
                            primaryColor: root.cpuMode ? root.neutronBlue : root.purple
                            secondaryColor: root.cpuMode ? root.focusBlue : root.pink
                            warningColor: root.warningGold
                            dangerColor: root.dangerRed
                            mutedTextColor: root.mutedText
                            animationsEnabled: root.animationsEnabled
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 3
                        rowSpacing: 8
                        columnSpacing: 8

                        Repeater {
                            model: root.summarySnapshot.length > 1
                                   ? root.summarySnapshot.slice(1)
                                   : []

                            Rectangle {
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 72
                                radius: 14
                                color: "#08172a"
                                border.width: 1
                                border.color: modelData.accent

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    spacing: 5

                                    Text {
                                        width: parent.width
                                        text: modelData.label
                                        color: root.mutedText
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.letterSpacing: 0.75
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.value
                                        color: modelData.accent
                                        font.pixelSize: 15
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.cpuMode ? 58 : 0
                visible: root.cpuMode
                radius: 16
                color: "#071426"
                border.width: 1
                border.color: "#2b5a82"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Repeater {
                        model: root.coreSnapshot

                        Rectangle {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 10
                            color: "#0a1830"
                            border.width: 1
                            border.color: root.usageColor(root.objectValue(modelData, ["usage", "percent", "cpu", "load"], 0))

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: String(root.objectValue(modelData, ["name", "label"], "CPU " + index))
                                    color: "white"
                                    font.pixelSize: 11
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: root.percentText(root.objectValue(modelData, ["usage", "percent", "cpu", "load"], 0))
                                    color: root.usageColor(root.objectValue(modelData, ["usage", "percent", "cpu", "load"], 0))
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                Text {
                                    text: String(root.objectValue(modelData, ["frequency", "frequencyText", "clock"], ""))
                                    color: root.mutedText
                                    font.pixelSize: 9
                                    font.bold: true
                                    visible: text.length > 0
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.coreSnapshot.length <= 0
                        text: "PER-CORE TELEMETRY IS INITIALIZING"
                        color: root.mutedText
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 152
                radius: 20
                color: "#071426"
                border.width: root.focusZone === 1 ? 3 : 1
                border.color: root.focusZone === 1 ? root.focusBlue : (root.cpuMode ? "#2b5a82" : "#5f447d")

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22

                        Text {
                            Layout.fillWidth: true
                            text: root.cpuMode ? "TOP THREE CPU CONSUMERS" : "TOP THREE RESIDENT RAM CONSUMERS"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 1
                        }

                        Text {
                            text: "CONTROLLER ANCHORS  •  X DETAILS"
                            color: root.neutronBlue
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 0.7
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        Repeater {
                            model: root.topProcessSnapshot

                            Rectangle {
                                required property int index
                                required property var modelData
                                readonly property int controllerAnchor: root.topProcessAnchor(index)
                                objectName: (root.cpuMode ? "cpuTopProcessAnchor_" : "ramTopProcessAnchor_") + controllerAnchor
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 15
                                color: root.focusZone === 1 && root.selectedTopProcess === index ? "#14365a" : "#09182c"
                                border.width: root.focusZone === 1 && root.selectedTopProcess === index ? 3 : 1
                                border.color: root.focusZone === 1 && root.selectedTopProcess === index
                                              ? root.focusBlue
                                              : root.usageColor(root.cpuMode ? root.processCpu(modelData) : root.processMemory(modelData))

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 11
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 42
                                        Layout.preferredHeight: 42
                                        radius: 21
                                        color: "#132b49"
                                        border.width: 1
                                        border.color: root.focusBlue

                                        Text {
                                            anchors.centerIn: parent
                                            text: String(index + 1)
                                            color: "white"
                                            font.pixelSize: 17
                                            font.bold: true
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.processName(modelData)
                                            color: "white"
                                            font.pixelSize: 17
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "PID " + root.processPid(modelData) + "  •  " + root.processUser(modelData)
                                            color: root.mutedText
                                            font.pixelSize: 11
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.cpuMode
                                                  ? ("RAM " + root.percentText(root.processMemory(modelData)))
                                                  : ("RESIDENT " + root.formatBytes(root.processMemoryBytes(modelData)))
                                            color: root.mutedText
                                            font.pixelSize: 10
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.preferredWidth: 88
                                        spacing: 3

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.cpuMode
                                                  ? root.percentText(root.processCpu(modelData))
                                                  : root.percentText(root.processMemory(modelData))
                                            color: root.usageColor(root.cpuMode ? root.processCpu(modelData) : root.processMemory(modelData))
                                            font.pixelSize: 18
                                            font.bold: true
                                            horizontalAlignment: Text.AlignRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.processState(modelData)
                                            color: root.mutedText
                                            font.pixelSize: 10
                                            font.bold: true
                                            horizontalAlignment: Text.AlignRight
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.topProcessSnapshot.length <= 0
                            text: "WAITING FOR PROCESS SAMPLE"
                            color: root.mutedText
                            font.pixelSize: 13
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                color: "#050e1b"
                border.width: root.focusZone === 2 ? 3 : 1
                border.color: root.focusZone === 2 ? root.focusBlue : (root.cpuMode ? "#2b5a82" : "#5f447d")

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 7

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24

                        Text {
                            Layout.fillWidth: true
                            text: root.cpuMode ? "ALL CPU PROCESSES" : "PROCESSES BY RESIDENT MEMORY"
                            color: "white"
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 0.9
                        }

                        Text {
                            text: "SORT: " + root.processSort.toUpperCase() + "  •  L1/R1 CHANGE"
                            color: root.neutronBlue
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 0.6
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 8
                        color: "#10213a"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10

                            Repeater {
                                model: [
                                    { "width": 0.09, "text": "PID", "align": Text.AlignLeft },
                                    { "width": 0.31, "text": "PROCESS", "align": Text.AlignLeft },
                                    { "width": 0.14, "text": "USER", "align": Text.AlignLeft },
                                    { "width": 0.11, "text": "CPU", "align": Text.AlignRight },
                                    { "width": 0.11, "text": "RAM", "align": Text.AlignRight },
                                    { "width": 0.10, "text": "STATE", "align": Text.AlignHCenter },
                                    { "width": 0.14, "text": "RUNTIME", "align": Text.AlignRight }
                                ]

                                Text {
                                    required property var modelData
                                    width: parent.width * modelData.width
                                    height: parent.height
                                    text: modelData.text
                                    color: root.mutedText
                                    font.pixelSize: 10
                                    font.bold: true
                                    horizontalAlignment: modelData.align
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    ListView {
                        id: processList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        interactive: false
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.processSnapshot
                        currentIndex: root.selectedProcess
                        preferredHighlightBegin: 0
                        preferredHighlightEnd: Math.max(0, height - 38)
                        highlightRangeMode: ListView.ApplyRange

                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            readonly property int controllerAnchor: root.processAnchor(index)
                            objectName: (root.cpuMode ? "cpuProcessAnchor_" : "ramProcessAnchor_") + controllerAnchor
                            width: ListView.view.width
                            height: 38
                            radius: 8
                            color: root.focusZone === 2 && root.selectedProcess === index
                                   ? "#14365a"
                                   : (index % 2 === 0 ? "#091628" : "#07111f")
                            border.width: root.focusZone === 2 && root.selectedProcess === index ? 2 : 0
                            border.color: root.focusBlue

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10

                                Text { width: parent.width * 0.09; height: parent.height; text: root.processPid(modelData); color: "#b9d8ee"; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: parent.width * 0.31; height: parent.height; text: root.processName(modelData); color: "white"; font.pixelSize: 13; font.bold: true; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: parent.width * 0.14; height: parent.height; text: root.processUser(modelData); color: "#a6c7dc"; font.pixelSize: 11; font.bold: true; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: parent.width * 0.11; height: parent.height; text: root.percentText(root.processCpu(modelData)); color: root.usageColor(root.processCpu(modelData)); font.pixelSize: 11; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                                Text { width: parent.width * 0.11; height: parent.height; text: root.processMemoryBytes(modelData) > 0 ? root.formatBytes(root.processMemoryBytes(modelData)) : root.percentText(root.processMemory(modelData)); color: root.neutronBlue; font.pixelSize: 11; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: parent.width * 0.10; height: parent.height; text: root.processState(modelData); color: root.warningGold; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: parent.width * 0.14; height: parent.height; text: root.processRuntime(modelData); color: root.mutedText; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.processSnapshot.length <= 0
                            text: "PROCESS DATA IS INITIALIZING"
                            color: root.mutedText
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                text: root.focusZone === 0
                      ? "LEFT/RIGHT ACTION  •  DOWN TOP 3  •  TRIANGLE REFRESH  •  O CLOSE"
                      : (root.focusZone === 1
                         ? "LEFT/RIGHT TOP PROCESS  •  X FULL DETAILS  •  UP ACTIONS  •  DOWN PROCESS TABLE"
                         : "UP/DOWN PROCESS  •  X FULL DETAILS  •  L1/R1 SORT  •  O CLOSE")
                color: root.mutedText
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.7
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    ProcessDetailsModal {
        id: processDetails
        monitor: root.monitor

        onClosed: {
            if (root.visible)
                root.forceActiveFocus()
        }
    }
}
