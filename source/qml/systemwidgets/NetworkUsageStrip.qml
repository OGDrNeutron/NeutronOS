import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                          NETWORK USAGE STRIP
        ============================================================

        Preserved from original:
            - apps property.
            - maxItems property.
            - Compact row layout.
            - Uses ProcessCircle.
            - Shows app/process name.
            - Shows rate label.
            - Shows percent ring.
            - No MouseArea.
            - No Button.

        Next-gen updates:
            - Explicit QtQuick 2.15 import.
            - Safe apps access.
            - Supports app fields:
                name/title/displayName/process/service
                rate/label/speed/download/upload
                percent/usage/usagePercent/networkPercent
            - Optional systemMonitor fallback if apps is empty.
            - Empty state when no network app usage is available.
            - Clamps percent to 0-100.
            - Prevents ReferenceError if systemMonitor is missing.
            - Animations can be disabled when parent is hidden.
            - Keeps lightweight Row + Repeater structure.
            - No placeholder data.
    */

    property var apps: []
    property int maxItems: 4

    property bool animationsEnabled: visible && enabled
    property bool showEmptyState: true

    property string emptyText: "No network activity"

    property color neutronBlue: "#7df9ff"
    property color mutedBlue: "#8aa6c8"

    width: 360
    height: 98

    /*
        ============================================================
                            MAIN ROW
        ============================================================
    */

    Row {
        id: usageRow

        anchors.centerIn: parent

        spacing: 14
        visible: root.itemCount() > 0

        Repeater {
            model: root.visibleItems()

            ProcessCircle {
                diameter: root.circleDiameter()
                thickness: root.circleThickness()

                name: root.itemName(modelData)
                label: root.itemRate(modelData)
                percent: root.itemPercent(modelData)

                /*
                    Safe optional property assignment for newer ProcessCircle.
                    Older ProcessCircle versions ignore this because the
                    property is checked before assignment.
                */
                Component.onCompleted: {
                    if ("animationsEnabled" in this)
                        this.animationsEnabled = Qt.binding(function() {
                            return root.animationsEnabled
                        })
                }
            }
        }
    }

    /*
        ============================================================
                            EMPTY STATE
        ============================================================
    */

    Item {
        anchors.fill: parent

        visible: root.showEmptyState && root.itemCount() <= 0

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter

                text: "NETWORK"
                color: root.neutronBlue

                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.6
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter

                text: root.emptyText
                color: root.mutedBlue

                font.pixelSize: 13
                font.bold: true

                opacity: 0.82
            }
        }
    }

    /*
        ============================================================
                            DATA HELPERS
        ============================================================
    */

    function systemBackend() {
        try {
            if (typeof systemMonitor !== "undefined" && systemMonitor)
                return systemMonitor
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

    function rawApps() {
        if (root.apps && root.apps.length !== undefined && root.apps.length > 0)
            return root.apps

        var backend = systemBackend()

        if (!backend)
            return []

        try {
            if (backend.networkApps)
                return backend.networkApps
        } catch (e) {
        }

        try {
            if (backend.networkUsageApps)
                return backend.networkUsageApps
        } catch (e2) {
        }

        try {
            if (backend.processNetworkUsage)
                return backend.processNetworkUsage
        } catch (e3) {
        }

        return []
    }

    function itemList() {
        var raw = rawApps()
        var result = []

        if (!raw || raw.length === undefined)
            return result

        for (var i = 0; i < raw.length; i++) {
            var item = raw[i]

            if (!item)
                continue

            /*
                Do not invent data. Only include real supplied records.
            */
            result.push(item)
        }

        return result
    }

    function visibleItems() {
        var list = itemList()
        var result = []

        var count = Math.min(Math.max(0, root.maxItems), list.length)

        for (var i = 0; i < count; i++)
            result.push(list[i])

        return result
    }

    function itemCount() {
        return visibleItems().length
    }

    function valueFor(item, keys, fallbackValue) {
        if (!item)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = item[keys[i]]

                if (value !== undefined &&
                        value !== null &&
                        String(value).trim().length > 0) {
                    return value
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function itemName(item) {
        var value = valueFor(item, [
                                 "name",
                                 "title",
                                 "displayName",
                                 "process",
                                 "processName",
                                 "service",
                                 "app"
                             ], "")

        var text = cleanText(value)

        if (text.length > 0)
            return text

        return "Process"
    }

    function itemRate(item) {
        var value = valueFor(item, [
                                 "rate",
                                 "label",
                                 "speed",
                                 "networkRate",
                                 "download",
                                 "upload",
                                 "downloadRate",
                                 "uploadRate"
                             ], "")

        var text = cleanText(value)

        if (text.length > 0)
            return text

        var down = cleanText(valueFor(item, [
                                      "down",
                                      "rx",
                                      "rxRate",
                                      "downloadSpeed"
                                  ], ""))

        var up = cleanText(valueFor(item, [
                                    "up",
                                    "tx",
                                    "txRate",
                                    "uploadSpeed"
                                ], ""))

        if (down.length > 0 && up.length > 0)
            return "↓ " + down + " ↑ " + up

        if (down.length > 0)
            return "↓ " + down

        if (up.length > 0)
            return "↑ " + up

        return "--"
    }

    function itemPercent(item) {
        var value = Number(valueFor(item, [
                                    "percent",
                                    "usage",
                                    "usagePercent",
                                    "networkPercent",
                                    "activity",
                                    "load"
                                ], 0))

        if (isNaN(value))
            value = 0

        return Math.max(0, Math.min(100, Math.round(value)))
    }

    /*
        ============================================================
                            SIZE HELPERS
        ============================================================
    */

    function circleDiameter() {
        if (root.height <= 70)
            return Math.max(42, root.height - 14)

        return 58
    }

    function circleThickness() {
        if (circleDiameter() <= 46)
            return 5

        return 6
    }

    onMaxItemsChanged: {
        if (maxItems < 0)
            maxItems = 0
    }
}