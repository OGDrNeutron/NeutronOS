import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root

    property var monitor: null
    property var processSummary: ({})
    property var details: ({})
    property var detailRows: []
    property string sourceLabel: "PROCESS MONITOR"

    property color focusBlue: "#4da6ff"
    property color neutronBlue: "#7df9ff"
    property color successGreen: "#22ff88"
    property color warningGold: "#f5c542"
    property color dangerRed: "#ff3040"
    property color mutedText: "#8aa6c8"

    signal closed()

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    activeFocusOnTab: true
    color: "#b8000000"
    opacity: 1.0
    z: 4000

    function value(object, keys, fallbackValue) {
        if (!object)
            return fallbackValue

        for (var i = 0; i < keys.length; ++i) {
            try {
                var candidate = object[keys[i]]
                if (candidate !== undefined && candidate !== null &&
                        String(candidate).length > 0) {
                    return candidate
                }
            } catch (error) {
            }
        }

        return fallbackValue
    }

    function processPid() {
        return Number(value(processSummary, ["pid", "processId"], 0))
    }

    function processName() {
        return String(value(details, ["name", "processName"],
                            value(processSummary,
                                  ["name", "processName", "command"],
                                  "Unknown process")))
    }

    function percentText(rawValue) {
        var number = Number(rawValue)
        if (isNaN(number))
            number = 0
        return number.toFixed(1) + "%"
    }

    function open(process, label) {
        processSummary = process || ({})
        sourceLabel = String(label || "PROCESS MONITOR")
        visible = true
        refreshDetails()
        Qt.callLater(function() {
            if (root.visible)
                root.forceActiveFocus()
        })
    }

    function openModal(process, label) {
        open(process, label)
    }

    function close() {
        if (!visible)
            return

        visible = false
        details = ({})
        detailRows = []
        processSummary = ({})
        closed()
    }

    function closeModal() {
        close()
    }

    function refreshDetails() {
        var pid = processPid()
        var snapshot = ({})

        if (monitor && pid > 0) {
            try {
                if (typeof monitor.processDetails === "function")
                    snapshot = monitor.processDetails(pid)
            } catch (error) {
                snapshot = ({
                    "available": false,
                    "error": String(error)
                })
            }
        }

        details = snapshot || ({})
        rebuildRows()
        detailFlick.contentY = 0
    }

    function displayValue(keys, fallbackValue) {
        return String(value(details, keys,
                            value(processSummary, keys, fallbackValue)))
    }

    function rebuildRows() {
        var available = Boolean(value(details, ["available"], false))

        detailRows = [
            { "section": "IDENTITY" },
            { "label": "PROCESS NAME", "value": processName() },
            { "label": "PID", "value": String(processPid()) },
            { "label": "PARENT PID", "value": displayValue(["parentPid"], "--") },
            { "label": "USER", "value": displayValue(["user", "username", "owner"], "--") },
            { "label": "STATE", "value": displayValue(["state", "status"], "--") },
            { "label": "SERVICE / SCOPE", "value": displayValue(["serviceUnit"], "None detected") },

            { "section": "EXECUTION" },
            { "label": "EXECUTABLE", "value": displayValue(["executable"], "Unavailable"), "long": true },
            { "label": "WORKING DIRECTORY", "value": displayValue(["workingDirectory"], "Unavailable"), "long": true },
            { "label": "COMMAND LINE", "value": displayValue(["commandLine"], processName()), "long": true },
            { "label": "CGROUP", "value": displayValue(["cgroup"], "Unavailable"), "long": true },

            { "section": "LIVE USAGE" },
            { "label": "CPU USAGE", "value": percentText(value(details, ["cpuPercent"], value(processSummary, ["cpu", "cpuPercent"], 0))) },
            { "label": "RAM USAGE", "value": percentText(value(details, ["memoryPercent"], value(processSummary, ["memory", "memoryPercent"], 0))) },
            { "label": "RESIDENT MEMORY", "value": displayValue(["residentMemory"], "--") },
            { "label": "VIRTUAL MEMORY", "value": displayValue(["virtualMemory"], "--") },
            { "label": "CPU TIME", "value": displayValue(["cpuTime"], "--") },

            { "section": "LIFETIME" },
            { "label": "START TIME", "value": displayValue(["startTime"], "Unavailable") },
            { "label": "ELAPSED RUNTIME", "value": displayValue(["elapsedRuntime", "runtime", "elapsed"], "--") },
            { "label": "THREADS", "value": displayValue(["threads"], "--") },
            { "label": "PRIORITY", "value": displayValue(["priority"], "--") },
            { "label": "NICE VALUE", "value": displayValue(["nice"], "--") },

            { "section": "I/O AND DIAGNOSTICS" },
            { "label": "OPEN FILES", "value": displayValue(["openFiles"], "Unavailable") },
            { "label": "DISK READ", "value": displayValue(["diskRead"], "--") },
            { "label": "DISK WRITE", "value": displayValue(["diskWrite"], "--") },
            { "label": "CHARACTERS READ", "value": displayValue(["charactersRead"], "--") },
            { "label": "CHARACTERS WRITTEN", "value": displayValue(["charactersWritten"], "--") },
            { "label": "VOLUNTARY CONTEXT SWITCHES", "value": displayValue(["voluntaryContextSwitches"], "--") },
            { "label": "INVOLUNTARY CONTEXT SWITCHES", "value": displayValue(["nonvoluntaryContextSwitches"], "--") }
        ]

        if (!available) {
            detailRows.unshift({
                "label": "STATUS",
                "value": displayValue(["error"], "Live process details are unavailable"),
                "warning": true,
                "long": true
            })
        }
    }

    function normalizeAction(action) {
        var valueText = String(action || "").trim().toLowerCase()

        if (valueText === "x" || valueText === "cross" ||
                valueText === "primary" || valueText === "confirm")
            return "primary"
        if (valueText === "o" || valueText === "circle" ||
                valueText === "cancel" || valueText === "back")
            return "cancel"
        if (valueText === "triangle" || valueText === "context")
            return "context"
        if (valueText === "dpad_up")
            return "up"
        if (valueText === "dpad_down")
            return "down"
        if (valueText === "dpad_left")
            return "left"
        if (valueText === "dpad_right")
            return "right"
        return valueText
    }

    function handleControllerPressed(action) {
        if (!visible)
            return false

        var normalized = normalizeAction(action)

        if (normalized === "cancel") {
            close()
            return true
        }

        if (normalized === "primary" || normalized === "context") {
            refreshDetails()
            return true
        }

        if (normalized === "up") {
            detailFlick.contentY = Math.max(0, detailFlick.contentY - 72)
            return true
        }

        if (normalized === "down") {
            detailFlick.contentY = Math.min(
                        Math.max(0, detailFlick.contentHeight - detailFlick.height),
                        detailFlick.contentY + 72)
            return true
        }

        if (normalized === "left" || normalized === "l1") {
            detailFlick.contentY = Math.max(0, detailFlick.contentY - detailFlick.height * 0.72)
            return true
        }

        if (normalized === "right" || normalized === "r1") {
            detailFlick.contentY = Math.min(
                        Math.max(0, detailFlick.contentHeight - detailFlick.height),
                        detailFlick.contentY + detailFlick.height * 0.72)
            return true
        }

        return true
    }

    function handleController(action) {
        return handleControllerPressed(action)
    }

    function handleControllerReleased(action) {
        return visible
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace)
            action = "cancel"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            action = "primary"
        else if (event.key === Qt.Key_Up)
            action = "up"
        else if (event.key === Qt.Key_Down)
            action = "down"
        else if (event.key === Qt.Key_Left)
            action = "left"
        else if (event.key === Qt.Key_Right)
            action = "right"
        else if (event.key === Qt.Key_R)
            action = "context"

        if (action.length > 0) {
            event.accepted = handleControllerPressed(action)
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.86, 1280)
        height: Math.min(parent.height * 0.88, 860)
        radius: 28
        color: "#050d18"
        border.width: 2
        border.color: root.focusBlue

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                spacing: 16

                Rectangle {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    radius: 26
                    color: "#102847"
                    border.width: 2
                    border.color: root.neutronBlue

                    Text {
                        anchors.centerIn: parent
                        text: "i"
                        color: root.neutronBlue
                        font.pixelSize: 28
                        font.bold: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: root.processName()
                        color: "white"
                        font.pixelSize: 26
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.sourceLabel + "  •  PID " + root.processPid() + "  •  LIVE PROCESS BREAKDOWN"
                        color: root.mutedText
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 0.8
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 176
                    Layout.preferredHeight: 42
                    radius: 14
                    color: "#10213a"
                    border.width: 1
                    border.color: root.neutronBlue

                    Text {
                        anchors.centerIn: parent
                        text: "X  REFRESH"
                        color: root.neutronBlue
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                spacing: 10

                Repeater {
                    model: [
                        { "label": "CPU", "value": root.percentText(root.value(root.details, ["cpuPercent"], root.value(root.processSummary, ["cpu", "cpuPercent"], 0))), "accent": root.successGreen },
                        { "label": "RAM", "value": root.percentText(root.value(root.details, ["memoryPercent"], root.value(root.processSummary, ["memory", "memoryPercent"], 0))), "accent": root.neutronBlue },
                        { "label": "STATE", "value": root.displayValue(["state", "status"], "--"), "accent": root.warningGold },
                        { "label": "RUNTIME", "value": root.displayValue(["elapsedRuntime", "runtime"], "--"), "accent": "#c78cff" }
                    ]

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: "#0a1830"
                        border.width: 1
                        border.color: modelData.accent

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            spacing: 5

                            Text {
                                width: parent.width
                                text: modelData.label
                                color: root.mutedText
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                width: parent.width
                                text: modelData.value
                                color: modelData.accent
                                font.pixelSize: 18
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 20
                color: "#071426"
                border.width: 1
                border.color: "#294d72"
                clip: true

                Flickable {
                    id: detailFlick
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true
                    interactive: false
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: detailColumn.height

                    Column {
                        id: detailColumn
                        width: detailFlick.width
                        spacing: 7

                        Repeater {
                            model: root.detailRows

                            Loader {
                                required property var modelData
                                property var rowData: modelData
                                width: detailColumn.width
                                height: rowData.section !== undefined
                                        ? 38
                                        : (item ? item.implicitHeight : (rowData.long ? 82 : 48))

                                sourceComponent: rowData.section !== undefined ? sectionDelegate : valueDelegate
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    width: 4
                    height: Math.max(32, parent.height * Math.min(1, detailFlick.height / Math.max(1, detailFlick.contentHeight)))
                    radius: 2
                    color: root.focusBlue
                    opacity: detailFlick.contentHeight > detailFlick.height ? 0.8 : 0
                    y: 12 + (parent.height - height - 24) *
                       (detailFlick.contentY / Math.max(1, detailFlick.contentHeight - detailFlick.height))
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                text: "UP/DOWN SCROLL  •  L1/R1 PAGE  •  X REFRESH  •  O BACK"
                color: root.mutedText
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.8
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Component {
        id: sectionDelegate

        Rectangle {
            readonly property var rowData: parent ? parent.rowData : ({})
            implicitHeight: 38
            radius: 10
            color: "#10213a"

            Text {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                text: parent.parent.rowData.section
                color: root.neutronBlue
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.2
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Component {
        id: valueDelegate

        Rectangle {
            readonly property var rowData: parent ? parent.rowData : ({})
            implicitHeight: rowData.long
                            ? Math.max(82, valueText.paintedHeight + 22)
                            : 48
            radius: 10
            color: rowData.warning ? "#35131b" : "#09182c"
            border.width: rowData.warning ? 1 : 0
            border.color: root.dangerRed

            RowLayout {
                id: contentRow
                anchors.fill: parent
                anchors.margins: 10
                spacing: 16

                Text {
                    Layout.preferredWidth: Math.min(260, parent.width * 0.30)
                    Layout.alignment: Qt.AlignTop
                    text: contentRow.parent.rowData.label
                    color: root.mutedText
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 0.7
                    wrapMode: Text.Wrap
                }

                Text {
                    id: valueText
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    text: contentRow.parent.rowData.value
                    color: contentRow.parent.rowData.warning ? root.dangerRed : "white"
                    font.pixelSize: contentRow.parent.rowData.long ? 12 : 13
                    font.bold: true
                    wrapMode: contentRow.parent.rowData.long ? Text.WrapAnywhere : Text.NoWrap
                    elide: contentRow.parent.rowData.long ? Text.ElideNone : Text.ElideRight
                }
            }
        }
    }
}
