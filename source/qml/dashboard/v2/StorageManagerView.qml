import QtQuick

Item {
    id: root

    property var backend: null
    property int selectedIndex: 0
    property int focusZone: 0      // 0 devices, 1 tools
    property int toolIndex: 0

    signal detailsRequested(string kind, var context)
    signal actionsRequested(string kind, var context)

    readonly property var drives: backend && backend.devices ? backend.devices : []
    readonly property var selectedDrive: drives.length > 0 && selectedIndex >= 0 && selectedIndex < drives.length ? drives[selectedIndex] : ({})
    readonly property var activity: backend && backend.recentActivity ? backend.recentActivity : []
    readonly property real uiScale: Math.max(0.94, Math.min(width / 1560.0, height / 860.0))

    readonly property color panel: "#F0081425"
    readonly property color panelRaised: "#F20B1A2E"
    readonly property color inset: "#F406101D"
    readonly property color border: "#42527899"
    readonly property color borderSoft: "#2D45627E"
    readonly property color blue: "#4C9DFF"
    readonly property color cyan: "#4CE6FF"
    readonly property color purple: "#B45CFF"
    readonly property color orange: "#FF993D"
    readonly property color green: "#4DEB91"
    readonly property color yellow: "#FFD44D"
    readonly property color red: "#FF455E"
    readonly property color white: "#F7FBFF"
    readonly property color secondary: "#BCD0E4"
    readonly property color muted: "#7E98B3"

    readonly property real gap: 14 * uiScale
    readonly property real overviewHeight: 124 * uiScale
    readonly property real devicesHeight: 300 * uiScale

    readonly property var storageTools: [
        { id: "health", title: backend && backend.smartctlAvailable ? "SMART HEALTH CHECK" : "HEALTH CHECK", detail: backend && backend.smartctlAvailable ? "Drive diagnostics, temperature and lifetime data" : "Basic availability and filesystem readiness check", icon: "health", tone: green },
        { id: "format", title: "FORMAT", detail: "Erase and prepare the selected storage device", icon: "format", tone: red },
        { id: "encrypt", title: "ENCRYPT", detail: "Open authenticated storage-data encryption tools", icon: "lock", tone: purple },
        { id: "decrypt", title: "DECRYPT", detail: "Restore protected storage data", icon: "unlock", tone: cyan },
        { id: "optimize", title: "OPTIMIZE", detail: "Review reclaimable data before cleanup", icon: "optimize", tone: orange },
        { id: "imageflash", title: "IMAGE FLASH", detail: "Write an image or prepare a bootable target", icon: "flash", tone: blue }
    ]

    function clean(value) {
        return String(value === undefined || value === null ? "" : value).trim()
    }

    function clampSelection() {
        if (drives.length <= 0) {
            selectedIndex = 0
            return
        }
        selectedIndex = Math.max(0, Math.min(drives.length - 1, selectedIndex))
    }

    function childrenOf(device) {
        return device && device.children ? device.children : []
    }

    function walkFirst(device, predicate) {
        if (!device) return null
        if (predicate(device)) return device
        var children = childrenOf(device)
        for (var i = 0; i < children.length; ++i) {
            var found = walkFirst(children[i], predicate)
            if (found) return found
        }
        return null
    }

    function sumTree(device, key) {
        if (!device) return 0
        var total = Number(device[key] || 0)
        var children = childrenOf(device)
        for (var i = 0; i < children.length; ++i)
            total += sumTree(children[i], key)
        return total
    }

    function firstTreeValue(device, key) {
        if (!device) return ""
        var own = clean(device[key])
        if (own.length) return own
        var children = childrenOf(device)
        for (var i = 0; i < children.length; ++i) {
            var value = firstTreeValue(children[i], key)
            if (value.length) return value
        }
        return ""
    }

    function mountedVolume(device) {
        return walkFirst(device, function(node) {
            var points = node && node.mountPoints ? node.mountPoints : []
            return points.length > 0
        })
    }

    function mountPoint(device) {
        var volume = mountedVolume(device)
        if (!volume) return ""
        var points = volume.mountPoints || []
        if (!points.length) return ""
        for (var i = 0; i < points.length; ++i) {
            var candidate = clean(points[i])
            if (candidate === "/") return candidate
            if (candidate !== "/boot" && candidate !== "/boot/firmware") return candidate
        }
        return clean(points[0])
    }

    function mountLeaf(path) {
        var value = clean(path)
        if (!value.length) return ""
        if (value === "/" || value === "/boot" || value === "/boot/firmware") return "NeutronOS"
        while (value.length > 1 && value.endsWith("/")) value = value.slice(0, -1)
        var parts = value.split("/")
        return parts.length ? parts[parts.length - 1] : value
    }

    function driveDisplayName(device, index) {
        if (device && device.containsRoot === true) return "NeutronOS"
        var mount = mountLeaf(mountPoint(device))
        if (mount.length) return mount
        var label = firstTreeValue(device, "label")
        if (label.length) return label
        var model = clean(device && device.model)
        if (model.length) return model
        var path = clean(device && device.path)
        return path.length ? path : "Storage Device " + (index + 1)
    }

    function driveModel(device) {
        var vendor = clean(device && device.vendor)
        var model = clean(device && device.model)
        if (vendor.length && model.length && model.toLowerCase().indexOf(vendor.toLowerCase()) !== 0)
            return vendor + " " + model
        return model.length ? model : (vendor.length ? vendor : "Generic block device")
    }

    function driveRole(device) {
        if (device && device.containsRoot === true) return "SYSTEM STORAGE"
        if (device && (device.removable === true || device.hotplug === true)) return "REMOVABLE STORAGE"
        return "INTERNAL STORAGE"
    }

    function driveType(device) {
        var transport = clean(device && device.transport).toUpperCase()
        var rotational = device && device.rotational === true
        var kind = rotational ? "HDD" : "SSD / FLASH"
        return transport.length ? transport + "  •  " + kind : kind
    }

    function formatBytes(bytes) {
        var value = Math.max(0, Number(bytes || 0))
        var units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var index = 0
        while (value >= 1024 && index < units.length - 1) {
            value /= 1024
            ++index
        }
        if (index === 0) return Math.round(value) + " " + units[index]
        if (value >= 100) return value.toFixed(0) + " " + units[index]
        if (value >= 10) return value.toFixed(1) + " " + units[index]
        return value.toFixed(2) + " " + units[index]
    }

    function driveCapacityBytes(device) {
        return Number(device && device.sizeBytes || 0)
    }

    function driveFilesystemBytes(device) {
        var value = sumTree(device, "filesystemBytes")
        return value > 0 ? value : driveCapacityBytes(device)
    }

    function driveUsedBytes(device) {
        return sumTree(device, "usedBytes")
    }

    function driveAvailableBytes(device) {
        return sumTree(device, "availableBytes")
    }

    function driveUsagePercent(device) {
        var total = driveFilesystemBytes(device)
        var used = driveUsedBytes(device)
        return total > 0 ? Math.max(0, Math.min(100, used * 100 / total)) : 0
    }

    function driveFilesystem(device) {
        var value = firstTreeValue(device, "filesystem")
        return value.length ? value.toUpperCase() : "UNFORMATTED"
    }

    function driveTemperatureValue(device) {
        var value = Number(device && device.smartTemperature !== undefined ? device.smartTemperature : -1)
        if (value >= 0) return value
        var children = childrenOf(device)
        for (var i = 0; i < children.length; ++i) {
            var child = driveTemperatureValue(children[i])
            if (child >= 0) return child
        }
        return -1
    }

    function driveTemperature(device) {
        var value = driveTemperatureValue(device)
        return value >= 0 ? Math.round(value) + "°C" : "NOT REPORTED"
    }

    function driveHealth(device) {
        var status = clean(device && device.smartStatus).toUpperCase()
        if (status === "PASSED") return "HEALTHY"
        if (status === "ATTENTION") return "ATTENTION"
        if (status === "UNSUPPORTED") return "BASIC CHECK"
        return backend && backend.smartctlAvailable ? "NOT CHECKED" : "CHECK AVAILABLE"
    }

    function driveHealthColor(device) {
        var status = clean(device && device.smartStatus).toUpperCase()
        if (status === "PASSED") return green
        if (status === "ATTENTION") return red
        if (status === "UNSUPPORTED") return yellow
        return cyan
    }

    function selectedBreakdown() {
        if (!backend || !backend.usageBreakdowns) return ({})
        var point = mountPoint(selectedDrive)
        return point.length ? (backend.usageBreakdowns[point] || ({})) : ({})
    }

    function usageRows() {
        var breakdown = selectedBreakdown()
        var entries = breakdown && breakdown.entries ? breakdown.entries : []
        var out = []
        for (var i = 0; i < entries.length; ++i) {
            if (entries[i].free === true) continue
            if (Number(entries[i].bytes || 0) <= 0) continue
            out.push(entries[i])
            if (out.length >= 5) break
        }
        return out
    }

    function requestSelectedUsage(force) {
        var point = mountPoint(selectedDrive)
        if (point.length && backend && typeof backend.requestUsageBreakdown === "function")
            backend.requestUsageBreakdown(point, force === true)
    }

    function recentRows() {
        var rows = []
        for (var i = 0; i < activity.length && i < 3; ++i) rows.push(activity[i])
        return rows
    }

    function selectDrive(index) {
        if (!drives.length) return
        selectedIndex = Math.max(0, Math.min(drives.length - 1, index))
        focusZone = 0
        requestSelectedUsage(false)
    }

    function openTool(index) {
        if (!drives.length || index < 0 || index >= storageTools.length) return
        toolIndex = index
        var tool = storageTools[index]
        actionsRequested("storage", {
            device: selectedDrive,
            storageTool: tool.id,
            storageToolTitle: tool.title,
            selectedMount: mountPoint(selectedDrive)
        })
    }

    function handleControllerPressed(action) {
        if (focusZone === 0) {
            if (action === "left") selectDrive(selectedIndex - 1)
            else if (action === "right") selectDrive(selectedIndex + 1)
            else if (action === "down") { focusZone = 1; toolIndex = 0 }
            else if ((action === "primary" || action === "context") && drives.length)
                detailsRequested("storage", { device: selectedDrive })
            else if (action === "secondary" && drives.length)
                actionsRequested("storage", { device: selectedDrive, storageTool: "overview" })
            return true
        }

        if (focusZone === 1) {
            if (action === "left") toolIndex = Math.max(0, toolIndex - 1)
            else if (action === "right") toolIndex = Math.min(storageTools.length - 1, toolIndex + 1)
            else if (action === "up") {
                if (toolIndex >= 3) toolIndex -= 3
                else focusZone = 0
            } else if (action === "down") {
                if (toolIndex < 3) toolIndex = Math.min(storageTools.length - 1, toolIndex + 3)
            } else if (action === "primary") openTool(toolIndex)
            else if (action === "cancel") focusZone = 0
            return true
        }
        return true
    }

    onSelectedIndexChanged: requestSelectedUsage(false)

    Component.onCompleted: {
        clampSelection()
        requestSelectedUsage(false)
    }

    Connections {
        target: root.backend
        function onDevicesChanged() {
            root.clampSelection()
            root.requestSelectedUsage(false)
        }
    }

    Timer {
        interval: 900000
        repeat: true
        running: root.visible
        onTriggered: root.requestSelectedUsage(false)
    }

    component MetricCell: Item {
        property string labelText: ""
        property string valueText: ""
        property string detailText: ""
        property color accent: root.white

        Rectangle {
            visible: parent.x > 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height * 0.62
            color: root.borderSoft
        }
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 18 * root.uiScale
            anchors.rightMargin: 12 * root.uiScale
            spacing: 4 * root.uiScale
            Text { width: parent.width; text: labelText; color: root.muted; font.pixelSize: 12 * root.uiScale; font.bold: true; font.letterSpacing: 0.8; elide: Text.ElideRight }
            Text { width: parent.width; text: valueText; color: accent; font.pixelSize: 24 * root.uiScale; font.bold: true; elide: Text.ElideRight }
            Text { width: parent.width; text: detailText; color: root.secondary; font.pixelSize: 11 * root.uiScale; elide: Text.ElideRight }
        }
    }

    component ToolGlyph: Canvas {
        property string kind: "health"
        property color accent: root.cyan
        onKindChanged: requestPaint()
        onAccentChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height, cx = w / 2, cy = h / 2
            ctx.strokeStyle = accent
            ctx.fillStyle = accent
            ctx.lineWidth = Math.max(2, 2.2 * root.uiScale)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            if (kind === "health") {
                ctx.beginPath(); ctx.moveTo(cx, h * 0.14); ctx.lineTo(w * 0.78, h * 0.25); ctx.lineTo(w * 0.73, h * 0.58); ctx.quadraticCurveTo(cx, h * 0.86, w * 0.27, h * 0.58); ctx.lineTo(w * 0.22, h * 0.25); ctx.closePath(); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(w * 0.34, cy); ctx.lineTo(w * 0.44, cy); ctx.lineTo(w * 0.49, h * 0.39); ctx.lineTo(w * 0.56, h * 0.62); ctx.lineTo(w * 0.63, cy); ctx.lineTo(w * 0.70, cy); ctx.stroke()
            } else if (kind === "format") {
                ctx.strokeRect(w * 0.20, h * 0.22, w * 0.60, h * 0.56)
                ctx.beginPath(); ctx.moveTo(w * 0.28, h * 0.60); ctx.lineTo(w * 0.72, h * 0.60); ctx.stroke()
                ctx.beginPath(); ctx.arc(w * 0.66, h * 0.38, w * 0.07, 0, Math.PI * 2); ctx.fill()
            } else if (kind === "lock" || kind === "unlock") {
                ctx.strokeRect(w * 0.25, h * 0.43, w * 0.50, h * 0.36)
                ctx.beginPath()
                if (kind === "lock") {
                    ctx.arc(cx, h * 0.43, w * 0.18, Math.PI, Math.PI * 2)
                } else {
                    ctx.arc(w * 0.56, h * 0.43, w * 0.18, Math.PI, Math.PI * 1.88)
                }
                ctx.stroke()
                ctx.beginPath(); ctx.arc(cx, h * 0.60, w * 0.035, 0, Math.PI * 2); ctx.fill()
            } else if (kind === "optimize") {
                ctx.beginPath(); ctx.moveTo(cx, h * 0.13); ctx.lineTo(w * 0.58, h * 0.40); ctx.lineTo(w * 0.85, cy); ctx.lineTo(w * 0.58, h * 0.60); ctx.lineTo(cx, h * 0.87); ctx.lineTo(w * 0.42, h * 0.60); ctx.lineTo(w * 0.15, cy); ctx.lineTo(w * 0.42, h * 0.40); ctx.closePath(); ctx.stroke()
                ctx.beginPath(); ctx.arc(cx, cy, w * 0.075, 0, Math.PI * 2); ctx.fill()
            } else if (kind === "flash") {
                ctx.beginPath(); ctx.moveTo(w * 0.56, h * 0.10); ctx.lineTo(w * 0.28, h * 0.53); ctx.lineTo(w * 0.47, h * 0.53); ctx.lineTo(w * 0.40, h * 0.90); ctx.lineTo(w * 0.74, h * 0.43); ctx.lineTo(w * 0.54, h * 0.43); ctx.closePath(); ctx.stroke()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"

        Column {
            anchors.fill: parent
            anchors.margins: 2 * root.uiScale
            spacing: root.gap

            Rectangle {
                width: parent.width
                height: root.overviewHeight
                radius: 18 * root.uiScale
                color: root.panel
                border.width: 1
                border.color: root.border

                Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 4 * root.uiScale; radius: 2 * root.uiScale; color: root.blue }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 18 * root.uiScale
                    anchors.rightMargin: 14 * root.uiScale

                    Item {
                        width: parent.width * 0.28
                        height: parent.height
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 18 * root.uiScale
                            spacing: 5 * root.uiScale
                            Text { width: parent.width; text: "STORAGE OVERVIEW"; color: root.blue; font.pixelSize: 15 * root.uiScale; font.bold: true; font.letterSpacing: 1.0 }
                            Text { width: parent.width; text: root.drives.length ? root.driveDisplayName(root.selectedDrive, root.selectedIndex) : "NO STORAGE DETECTED"; color: root.white; font.pixelSize: 27 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: root.drives.length ? root.driveModel(root.selectedDrive) : "Connect a storage device"; color: root.secondary; font.pixelSize: 13 * root.uiScale; elide: Text.ElideRight }
                        }
                    }

                    MetricCell { width: parent.width * 0.18; height: parent.height; labelText: "CAPACITY"; valueText: root.drives.length ? root.formatBytes(root.driveCapacityBytes(root.selectedDrive)) : "--"; detailText: root.driveType(root.selectedDrive); accent: root.white }
                    MetricCell { width: parent.width * 0.18; height: parent.height; labelText: "USED"; valueText: root.drives.length ? root.formatBytes(root.driveUsedBytes(root.selectedDrive)) : "--"; detailText: Math.round(root.driveUsagePercent(root.selectedDrive)) + "% utilized"; accent: root.cyan }
                    MetricCell { width: parent.width * 0.18; height: parent.height; labelText: "AVAILABLE"; valueText: root.drives.length ? root.formatBytes(root.driveAvailableBytes(root.selectedDrive)) : "--"; detailText: root.driveFilesystem(root.selectedDrive); accent: root.green }
                    MetricCell { width: parent.width * 0.18; height: parent.height; labelText: "TEMPERATURE"; valueText: root.drives.length ? root.driveTemperature(root.selectedDrive) : "--"; detailText: root.driveHealth(root.selectedDrive); accent: root.driveTemperatureValue(root.selectedDrive) >= 60 ? root.red : (root.driveTemperatureValue(root.selectedDrive) >= 50 ? root.yellow : root.green) }
                }
            }

            Rectangle {
                width: parent.width
                height: root.devicesHeight
                radius: 18 * root.uiScale
                color: root.panel
                border.width: root.focusZone === 0 ? 2 : 1
                border.color: root.focusZone === 0 ? root.cyan : root.border
                clip: true

                Row {
                    x: 18 * root.uiScale
                    y: 13 * root.uiScale
                    spacing: 10 * root.uiScale
                    Text { text: "STORAGE DEVICES"; color: root.blue; font.pixelSize: 17 * root.uiScale; font.bold: true; font.letterSpacing: 0.8 }
                    Text { text: "•  " + root.drives.length + " CONNECTED"; color: root.muted; font.pixelSize: 12 * root.uiScale; font.bold: true; anchors.baseline: parent.children[0].baseline }
                }

                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 18 * root.uiScale
                    anchors.topMargin: 15 * root.uiScale
                    text: "◀  ▶  SELECT     X  DETAILS     ▼  TOOLS"
                    color: root.muted
                    font.pixelSize: 11 * root.uiScale
                    font.bold: true
                }

                ListView {
                    id: driveList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14 * root.uiScale
                    anchors.rightMargin: 14 * root.uiScale
                    anchors.topMargin: 52 * root.uiScale
                    anchors.bottomMargin: 14 * root.uiScale
                    orientation: ListView.Horizontal
                    spacing: 12 * root.uiScale
                    clip: true
                    model: root.drives
                    currentIndex: root.selectedIndex
                    interactive: true

                    delegate: Rectangle {
                        id: deviceCard
                        required property int index
                        required property var modelData
                        width: Math.max(300 * root.uiScale, (driveList.width - 24 * root.uiScale) / Math.min(3, Math.max(1, root.drives.length)))
                        height: driveList.height
                        radius: 15 * root.uiScale
                        color: root.selectedIndex === index ? "#F3122941" : root.panelRaised
                        border.width: root.selectedIndex === index ? 2 : 1
                        border.color: root.selectedIndex === index ? root.cyan : root.borderSoft

                        property real usage: root.driveUsagePercent(modelData)
                        property color accent: modelData.containsRoot === true ? root.cyan : (index % 3 === 1 ? root.purple : root.blue)

                        MouseArea { anchors.fill: parent; onClicked: root.selectDrive(index) }

                        Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 4 * root.uiScale; radius: 2 * root.uiScale; color: deviceCard.accent; opacity: root.selectedIndex === index ? 1.0 : 0.55 }

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16 * root.uiScale
                            spacing: 6 * root.uiScale

                            Text { width: parent.width; text: root.driveRole(modelData); color: deviceCard.accent; font.pixelSize: 11 * root.uiScale; font.bold: true; font.letterSpacing: 0.8 }
                            Text { width: parent.width; text: root.driveDisplayName(modelData, index); color: root.white; font.pixelSize: 22 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: root.driveModel(modelData); color: root.secondary; font.pixelSize: 12.5 * root.uiScale; elide: Text.ElideRight }

                            Item { width: 1; height: 5 * root.uiScale }

                            Row {
                                width: parent.width
                                height: 72 * root.uiScale
                                spacing: 14 * root.uiScale

                                Canvas {
                                    width: 72 * root.uiScale
                                    height: width
                                    property real value: deviceCard.usage
                                    property color accent: deviceCard.accent
                                    onValueChanged: requestPaint()
                                    onAccentChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d"); ctx.reset()
                                        var cx = width / 2, cy = height / 2, r = width * 0.37
                                        ctx.lineWidth = Math.max(5, 6 * root.uiScale)
                                        ctx.strokeStyle = "#22364B"; ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
                                        ctx.strokeStyle = accent; ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0, Math.min(100, value)) / 100); ctx.stroke()
                                    }
                                    Text { anchors.centerIn: parent; text: Math.round(deviceCard.usage) + "%"; color: root.white; font.pixelSize: 14 * root.uiScale; font.bold: true }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 86 * root.uiScale
                                    spacing: 5 * root.uiScale
                                    Text { width: parent.width; text: "USED  " + root.formatBytes(root.driveUsedBytes(modelData)); color: root.secondary; font.pixelSize: 12 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                                    Text { width: parent.width; text: "FREE  " + root.formatBytes(root.driveAvailableBytes(modelData)); color: root.green; font.pixelSize: 12 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                                    Text { width: parent.width; text: root.driveFilesystem(modelData) + "  •  " + root.driveTemperature(modelData); color: root.muted; font.pixelSize: 11.5 * root.uiScale; elide: Text.ElideRight }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 9 * root.uiScale
                                radius: height / 2
                                color: "#17283A"
                                Rectangle { width: parent.width * deviceCard.usage / 100; height: parent.height; radius: parent.radius; color: deviceCard.usage >= 90 ? root.red : (deviceCard.usage >= 75 ? root.yellow : deviceCard.accent) }
                            }

                            Text { width: parent.width; text: "MOUNT  " + (root.mountPoint(modelData).length ? root.mountPoint(modelData) : "NOT MOUNTED"); color: root.secondary; font.pixelSize: 11.5 * root.uiScale; font.bold: true; elide: Text.ElideMiddle }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: parent.height - root.overviewHeight - root.devicesHeight - root.gap * 2
                spacing: root.gap

                Rectangle {
                    width: parent.width * 0.54
                    height: parent.height
                    radius: 18 * root.uiScale
                    color: root.panel
                    border.width: 1
                    border.color: root.border

                    Text { x: 18 * root.uiScale; y: 14 * root.uiScale; text: "SELECTED DEVICE"; color: root.blue; font.pixelSize: 17 * root.uiScale; font.bold: true; font.letterSpacing: 0.8 }
                    Text { anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: 18 * root.uiScale; anchors.topMargin: 14 * root.uiScale; text: root.driveHealth(root.selectedDrive); color: root.driveHealthColor(root.selectedDrive); font.pixelSize: 13 * root.uiScale; font.bold: true }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 18 * root.uiScale
                        anchors.topMargin: 50 * root.uiScale
                        spacing: 18 * root.uiScale

                        Item {
                            width: parent.width * 0.44
                            height: parent.height

                            Item {
                                id: selectedGaugeShell
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: -8 * root.uiScale
                                width: Math.min(parent.width * 0.92, 218 * root.uiScale)
                                height: width

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 8 * root.uiScale
                                    radius: width / 2
                                    color: "#091725"
                                    border.width: 1
                                    border.color: "#315C7D"
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.68
                                    height: width
                                    radius: width / 2
                                    color: "#0B1B2B"
                                    border.width: 1
                                    border.color: "#284760"
                                }

                                Canvas {
                                    id: selectedRing
                                    anchors.fill: parent
                                    property real value: root.driveUsagePercent(root.selectedDrive)
                                    onValueChanged: requestPaint()
                                    Component.onCompleted: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()

                                        var cx = width / 2
                                        var cy = height / 2
                                        var outerR = width * 0.455
                                        var ringR = width * 0.385
                                        var innerR = width * 0.315
                                        var start = -Math.PI * 0.75
                                        var sweep = Math.PI * 1.5
                                        var progress = Math.max(0, Math.min(100, value)) / 100.0
                                        var end = start + sweep * progress

                                        // Subtle outer halo.
                                        ctx.lineWidth = Math.max(2, 2.2 * root.uiScale)
                                        ctx.strokeStyle = "#285270"
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, outerR, 0, Math.PI * 2)
                                        ctx.stroke()

                                        // Precision ticks around the gauge.
                                        for (var i = 0; i <= 30; ++i) {
                                            var t = i / 30.0
                                            var a = start + sweep * t
                                            var lit = t <= progress
                                            var r1 = outerR - 11 * root.uiScale
                                            var r2 = outerR - (i % 5 === 0 ? 2 : 5) * root.uiScale
                                            ctx.lineWidth = i % 5 === 0 ? 2.2 * root.uiScale : 1.1 * root.uiScale
                                            ctx.strokeStyle = lit
                                                ? (t < 0.70 ? root.cyan : (t < 0.90 ? root.yellow : root.red))
                                                : "#20384C"
                                            ctx.beginPath()
                                            ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1)
                                            ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2)
                                            ctx.stroke()
                                        }

                                        // Track.
                                        ctx.lineWidth = Math.max(15, 17 * root.uiScale)
                                        ctx.lineCap = "round"
                                        ctx.strokeStyle = "#182F43"
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, ringR, start, start + sweep)
                                        ctx.stroke()

                                        // Soft luminous underlay.
                                        ctx.lineWidth = Math.max(20, 22 * root.uiScale)
                                        ctx.strokeStyle = Qt.rgba(0.30, 0.83, 1.0, 0.10)
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, ringR, start, end)
                                        ctx.stroke()

                                        // Main premium gradient.
                                        var grad = ctx.createLinearGradient(
                                            width * 0.15, height * 0.12,
                                            width * 0.88, height * 0.88
                                        )
                                        grad.addColorStop(0.00, root.cyan)
                                        grad.addColorStop(0.58, root.blue)
                                        grad.addColorStop(0.82, root.purple)
                                        grad.addColorStop(1.00, root.red)

                                        ctx.lineWidth = Math.max(13, 15 * root.uiScale)
                                        ctx.strokeStyle = grad
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, ringR, start, end)
                                        ctx.stroke()

                                        // Inner technical ring.
                                        ctx.lineWidth = Math.max(1, 1.5 * root.uiScale)
                                        ctx.strokeStyle = "#3B6A89"
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, innerR, 0, Math.PI * 2)
                                        ctx.stroke()
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.58
                                    spacing: 1 * root.uiScale

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Math.round(selectedRing.value) + "%"
                                        color: root.white
                                        font.pixelSize: 39 * root.uiScale
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "USED"
                                        color: root.cyan
                                        font.pixelSize: 12.5 * root.uiScale
                                        font.bold: true
                                        font.letterSpacing: 1.4
                                    }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 54 * root.uiScale
                                        height: 1
                                        color: root.border
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: root.formatBytes(root.driveTotalBytes(root.selectedDrive))
                                        color: root.secondary
                                        font.pixelSize: 12 * root.uiScale
                                        font.bold: true
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "CAPACITY"
                                        color: root.muted
                                        font.pixelSize: 9.5 * root.uiScale
                                        font.bold: true
                                        font.letterSpacing: 0.8
                                    }
                                }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                spacing: 5 * root.uiScale
                                Text { width: parent.width; text: "MOUNT  " + (root.mountPoint(root.selectedDrive).length ? root.mountPoint(root.selectedDrive) : "Not mounted"); color: root.secondary; font.pixelSize: 12 * root.uiScale; font.bold: true; elide: Text.ElideMiddle }
                                Text { width: parent.width; text: "FILESYSTEM  " + root.driveFilesystem(root.selectedDrive); color: root.secondary; font.pixelSize: 12 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: "TEMPERATURE  " + root.driveTemperature(root.selectedDrive); color: root.driveTemperatureValue(root.selectedDrive) >= 0 ? root.green : root.muted; font.pixelSize: 12 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: "DEVICE  " + root.clean(root.selectedDrive.path); color: root.muted; font.pixelSize: 11 * root.uiScale; elide: Text.ElideMiddle }
                            }
                        }

                        Rectangle { width: 1; height: parent.height * 0.88; anchors.verticalCenter: parent.verticalCenter; color: root.borderSoft }

                        Item {
                            width: parent.width * 0.56 - 19 * root.uiScale
                            height: parent.height

                            Text { x: 0; y: 0; text: "USAGE BREAKDOWN"; color: root.secondary; font.pixelSize: 13 * root.uiScale; font.bold: true; font.letterSpacing: 0.7 }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 28 * root.uiScale
                                spacing: 9 * root.uiScale
                                Repeater {
                                    model: root.usageRows()
                                    delegate: Item {
                                        required property int index
                                        required property var modelData
                                        width: parent.width
                                        height: 28 * root.uiScale
                                        Rectangle { x: 0; anchors.verticalCenter: parent.verticalCenter; width: 8 * root.uiScale; height: 8 * root.uiScale; radius: 4 * root.uiScale; color: root.clean(modelData.color).length ? modelData.color : root.blue }
                                        Text { x: 18 * root.uiScale; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.55; text: root.clean(modelData.name).toUpperCase(); color: root.secondary; font.pixelSize: 11.5 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.formatBytes(Number(modelData.bytes || 0)); color: root.white; font.pixelSize: 11.5 * root.uiScale; font.bold: true }
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.usageRows().length === 0
                                width: parent.width * 0.90
                                text: root.mountPoint(root.selectedDrive).length ? "Usage categories are being prepared for this volume." : "Mount this device to calculate a live usage breakdown."
                                color: root.muted
                                font.pixelSize: 12 * root.uiScale
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width * 0.46 - root.gap
                    height: parent.height
                    radius: 18 * root.uiScale
                    color: root.panel
                    border.width: root.focusZone === 1 ? 2 : 1
                    border.color: root.focusZone === 1 ? root.cyan : root.border

                    Row {
                        x: 18 * root.uiScale
                        y: 13 * root.uiScale
                        spacing: 10 * root.uiScale
                        Text { text: "STORAGE TOOLS"; color: root.blue; font.pixelSize: 17 * root.uiScale; font.bold: true; font.letterSpacing: 0.8 }
                        Text { text: "•  " + root.driveDisplayName(root.selectedDrive, root.selectedIndex); color: root.muted; font.pixelSize: 11.5 * root.uiScale; font.bold: true; anchors.baseline: parent.children[0].baseline; elide: Text.ElideRight }
                    }

                    Grid {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 14 * root.uiScale
                        anchors.rightMargin: 14 * root.uiScale
                        anchors.topMargin: 48 * root.uiScale
                        anchors.bottomMargin: 14 * root.uiScale
                        columns: 3
                        rows: 2
                        spacing: 9 * root.uiScale

                        Repeater {
                            model: root.storageTools
                            delegate: Rectangle {
                                id: toolCard
                                required property int index
                                required property var modelData
                                width: (parent.width - 18 * root.uiScale) / 3
                                height: (parent.height - 9 * root.uiScale) / 2
                                radius: 13 * root.uiScale
                                color: root.focusZone === 1 && root.toolIndex === index ? "#173452" : root.panelRaised
                                border.width: root.focusZone === 1 && root.toolIndex === index ? 2 : 1
                                border.color: root.focusZone === 1 && root.toolIndex === index ? modelData.tone : root.borderSoft

                                MouseArea { anchors.fill: parent; onClicked: { root.focusZone = 1; root.toolIndex = index; root.openTool(index) } }

                                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 3 * root.uiScale; radius: 2 * root.uiScale; color: modelData.tone; opacity: 0.95 }

                                Rectangle {
                                    x: 12 * root.uiScale
                                    y: 14 * root.uiScale
                                    width: 44 * root.uiScale
                                    height: 44 * root.uiScale
                                    radius: 11 * root.uiScale
                                    color: Qt.rgba(modelData.tone.r, modelData.tone.g, modelData.tone.b, 0.10)
                                    border.width: 1
                                    border.color: Qt.rgba(modelData.tone.r, modelData.tone.g, modelData.tone.b, 0.40)
                                    ToolGlyph { anchors.centerIn: parent; width: 31 * root.uiScale; height: width; kind: modelData.icon; accent: modelData.tone }
                                }

                                Text { x: 66 * root.uiScale; y: 14 * root.uiScale; width: parent.width - 76 * root.uiScale; text: modelData.title; color: root.white; font.pixelSize: 13.5 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                                Text { x: 66 * root.uiScale; y: 38 * root.uiScale; width: parent.width - 76 * root.uiScale; height: parent.height - 48 * root.uiScale; text: modelData.detail; color: root.secondary; font.pixelSize: 10.5 * root.uiScale; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }

                                Text { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: 10 * root.uiScale; anchors.bottomMargin: 7 * root.uiScale; text: "X  OPEN"; color: modelData.tone; font.pixelSize: 9.5 * root.uiScale; font.bold: true }
                            }
                        }
                    }
                }
            }
        }
    }
}
