import QtQuick 2.15
import QtQuick.Layouts 1.15
import "../../components"

Rectangle {
    id: root

    property var contextData: ({})
    property var modalContext: ({})
    property var storageBackend: (typeof storageManager !== "undefined") ? storageManager : null
    property var monitorBackend: (typeof systemMonitor !== "undefined") ? systemMonitor : null
    property var assetBackend: (typeof assetManager !== "undefined") ? assetManager : null
    property var fileBackend: (typeof fileManager !== "undefined") ? fileManager : ((typeof fileManagerBackend !== "undefined") ? fileManagerBackend : null)
    property var settingsBackend: (typeof settingsManager !== "undefined") ? settingsManager : null
    property var controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null

    property int categoryIndex: 0
    property int focusPane: 0
    property int controlIndex: 0
    property int selectedDeviceIndex: 0
    property string selectedDevicePath: ""
    property var flatDevices: []
    property string formatFilesystem: "ext4"
    property string volumeLabel: "NEUTRON"
    property bool formatArmed: false
    property bool cloneArmed: false
    property bool flashArmed: false
    property string flashImagePath: ""
    property int imageFlashTab: 0
    property bool imagerModeVisible: false
    property int imagerModeIndex: 0
    property bool imagerCatalogVisible: false
    property int imagerCatalogIndex: 0
    property var selectedImagerOs: ({})
    property bool imagerSetupVisible: false
    property int imagerSetupIndex: 0
    property bool imagerSetupArmed: false
    property bool imagerManualSource: false
    property bool imagerOperationActive: false
    property bool imagerResultVisible: false
    property bool imagerResultSuccess: false
    property string imagerResultMessage: ""
    property bool manualPickerVisible: false
    property string manualPickerPath: "/home/echo/Downloads"
    property var manualPickerItems: []
    property int manualPickerIndex: 0
    property string manualPickerPurpose: "imager"
    property string setupHostname: "neutron"
    property string setupUsername: "neutronos"
    property string setupPassword: ""
    property bool setupSsh: true
    property bool setupWifi: false
    property string setupSsid: ""
    property string setupWifiPassword: ""
    property string setupWifiCountry: "US"
    property string setupTimezone: "America/New_York"
    property string setupLocale: "en_US.UTF-8"
    property string setupKeyboard: "us"
    property bool optimizationDeleteArmed: false
    property var optimizationSelectedPaths: []
    property int optimizationAgeDays: 30
    property string optimizationRootPath: ""
    property string securitySourcePath: ""
    property string securityDestinationPath: ""
    property string securityPassword: ""
    property string securityMethod: "xchacha20-poly1305"
    property string securityArmedAction: ""
    property string securityRequestedMode: ""
    property string keyboardTarget: "label"
    property bool keyboardOpen: false
    property string mountName: "Media"
    property bool deviceActionVisible: false
    property int deviceActionIndex: 0
    property string deviceActionArmed: ""
    property string statusMessage: ""
    property bool statusIsError: false
    property bool securityTaskActive: false
    property string securityTaskName: ""
    property bool taskResultVisible: false
    property bool taskResultSuccess: false
    property string taskResultTitle: ""
    property string taskResultMessage: ""
    property bool headerFocused: false
    readonly property bool fullScreenApp: contextData && contextData.fullManager === true
    readonly property var selectedUsageBreakdown: {
        var selected = selectedDevice()
        var mount = clean(selected.mountText || selected.mount || selected.mountPoint)
        var usage = settingsBackend && settingsBackend.storageUsage ? settingsBackend.storageUsage : []
        for (var i=0;i<usage.length;i++) if (clean(usage[i].mount) === mount) return usage[i]
        return ({categories:[]})
    }

    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color panelInset: "#06101F"
    property color focusBlue: "#4DA6FF"
    property color neutronCyan: "#7DF9FF"
    property color successGreen: "#22FF88"
    property color warningGold: "#F5C542"
    property color dangerRed: "#FF3040"
    property color purple: "#B75CFF"
    property color textWhite: "#F4FBFF"
    property color mutedText: "#8AA6C8"

    Timer {
        id: statusToastTimer
        interval: 2800
        repeat: false
        onTriggered: {
            root.statusMessage = ""
            root.statusIsError = false
        }
    }

    readonly property var categories: [
        { "title": "OVERVIEW", "icon": "◫", "detail": "CAPACITY & STATUS" },
        { "title": "DEVICES", "icon": "▣", "detail": "ALL CONNECTED DRIVES" },
        { "title": "HEALTH", "icon": "♥", "detail": "SMART DIAGNOSTICS" },
        { "title": "FORMAT", "icon": "⌫", "detail": "ERASE & PREPARE" },
        { "title": "SECURITY", "icon": "◆", "detail": "ENCRYPT & DECRYPT" },
        { "title": "OPTIMIZE", "icon": "✦", "detail": "REVIEW OLD FILES" },
        { "title": "IMAGE FLASH", "icon": "⇩", "detail": "WRITE IMAGE OR CLONE" },
        { "title": "DETAILS", "icon": "i", "detail": "DEVICE INFORMATION" }
    ]

    readonly property var encryptionMethods: {
        try {
            if (fileBackend && fileBackend.supportedEncryptionMethods && fileBackend.supportedEncryptionMethods.length > 0)
                return fileBackend.supportedEncryptionMethods
        } catch (error) {}
        return ["xchacha20-poly1305", "aes-256-gcm", "gpg-aes256"]
    }

    readonly property var optimizationCandidates: {
        try { return storageBackend && storageBackend.optimizationCandidates ? storageBackend.optimizationCandidates : [] }
        catch (error) { return [] }
    }

    readonly property bool optimizationScanning: {
        try { return storageBackend && storageBackend.optimizationScanning === true }
        catch (error) { return false }
    }

    readonly property var filesystems: {
        try {
            if (storageBackend && storageBackend.supportedFilesystems && storageBackend.supportedFilesystems.length > 0)
                return storageBackend.supportedFilesystems
        } catch (error) {}
        return ["ext4", "exfat", "vfat", "btrfs"]
    }

    readonly property bool operationBusy: {
        try { return storageBackend && storageBackend.busy === true } catch (error) { return false }
    }

    readonly property var imagerCatalog: {
        try { return storageBackend && storageBackend.imagerCatalog ? storageBackend.imagerCatalog : [] }
        catch (error) { return [] }
    }

    readonly property bool imagerCatalogLoading: {
        try { return storageBackend && storageBackend.imagerCatalogLoading === true }
        catch (error) { return false }
    }

    signal closed()
    signal actionRequested(string action, var payload)

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    Keys.enabled: visible
    color: fullScreenApp ? "#02060D" : "#D4020710"
    z: 999

    component RailItem: Rectangle {
        property string titleText: ""
        property string detailText: ""
        property string iconText: ""
        property bool selected: false
        property bool activePage: false
        width: parent ? parent.width : 280
        height: 64
        radius: 8
        color: selected ? "#102A42" : (activePage ? "#0B1F31" : "transparent")
        border.width: selected ? 1 : 0
        border.color: selected ? root.focusBlue : "transparent"

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: 2
            color: selected || activePage ? root.focusBlue : "transparent"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 9
            color: selected ? "#17365D" : "#0B1A29"
            border.width: 1
            border.color: selected ? root.neutronCyan : "#243746"
            Text {
                anchors.centerIn: parent
                text: iconText
                color: selected ? root.neutronCyan : "#91AEC5"
                font.pixelSize: 18
                font.bold: true
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 62
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                width: parent.width
                text: titleText
                color: selected || activePage ? root.textWhite : "#C8D5DF"
                font.pixelSize: 16
                font.bold: true
                font.letterSpacing: 0.6
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: detailText
                color: selected ? "#9FDFFF" : root.mutedText
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.7
                elide: Text.ElideRight
            }
        }
    }

    component SettingRow: Rectangle {
        property string titleText: ""
        property string detailText: ""
        property string valueText: ""
        property color valueColor: root.neutronCyan
        property bool selected: false
        property bool disabled: false
        property bool danger: false
        width: parent ? parent.width : 760
        height: 80
        radius: 8
        color: selected ? (danger ? "#34151B" : "#0D263A") : "#081522"
        border.width: 1
        border.color: selected ? (danger ? root.dangerRed : root.focusBlue) : "#203847"
        opacity: disabled ? 0.42 : 1.0

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: 2
            color: selected ? (danger ? root.dangerRed : root.focusBlue) : "#263B48"
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.right: valueLabel.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text {
                width: parent.width
                text: titleText
                color: root.textWhite
                font.pixelSize: 17
                font.bold: true
                font.letterSpacing: 0.45
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: detailText
                color: root.mutedText
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        Text {
            id: valueLabel
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(330, implicitWidth)
            text: valueText
            color: valueColor
            font.pixelSize: 16
            font.bold: true
            font.letterSpacing: 0.6
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    component DeviceRow: Rectangle {
        property var deviceData: ({})
        property bool selected: false
        width: parent ? parent.width : 760
        height: 94
        radius: 8
        color: selected ? "#0D263A" : "#081522"
        border.width: 1
        border.color: selected ? root.focusBlue : "#203847"

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: 2
            color: selected ? root.manufacturerColor(deviceData) : "#263B48"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 58
            height: 58
            radius: 12
            color: root.manufacturerKey(deviceData) === "neutronos" ? "#351018" : "#0A1A29"
            border.width: 1
            border.color: root.manufacturerColor(deviceData)

            Text {
                anchors.centerIn: parent
                width: parent.width - 8
                text: root.manufacturerMark(deviceData)
                color: root.manufacturerColor(deviceData)
                font.pixelSize: text.length > 4 ? 10 : (text.length > 2 ? 14 : 23)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 88
            anchors.right: statePill.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                width: parent.width
                text: root.isSystemStorage(deviceData) ? "NeutronOS Boot Storage" : root.deviceTitle(deviceData)
                color: root.textWhite
                font.pixelSize: 18
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.manufacturerName(deviceData) + (root.clean(root.physicalDevice(deviceData).model).length > 0 ? "  •  " + root.clean(root.physicalDevice(deviceData).model) : "")
                color: root.manufacturerColor(deviceData)
                font.pixelSize: 12
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.deviceSubtitle(deviceData) + "  •  " + root.deviceMountText(deviceData)
                color: root.mutedText
                font.pixelSize: 11
                elide: Text.ElideMiddle
            }
        }

        Rectangle {
            id: statePill
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: root.isSystemStorage(deviceData) ? 132 : 104
            height: 32
            radius: 16
            color: root.isSystemStorage(deviceData) ? "#2A1015" : (deviceData.readOnly ? "#2A2410" : "#0A241A")
            border.width: 1
            border.color: root.isSystemStorage(deviceData) ? root.dangerRed : (deviceData.readOnly ? root.warningGold : root.successGreen)
            Text {
                anchors.centerIn: parent
                text: root.isSystemStorage(deviceData) ? "BOOT / PROTECTED" : (deviceData.readOnly ? "READ ONLY" : "READY")
                color: root.isSystemStorage(deviceData) ? "#FF8B94" : (deviceData.readOnly ? root.warningGold : root.successGreen)
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.5
            }
        }
    }

    component OptimizationRow: Rectangle {
        property var candidateData: ({})
        property bool selected: false
        property bool marked: false
        width: parent ? parent.width : 760
        height: 148
        radius: 8
        color: selected ? "#17365D" : (marked ? "#102B2A" : "#09182B")
        border.width: selected ? 2 : 1
        border.color: selected ? root.focusBlue : (marked ? root.successGreen : "#1D3958")

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48
            radius: 14
            color: marked ? "#164C3A" : "#102943"
            border.width: 2
            border.color: marked ? root.successGreen : "#315A80"
            Text { anchors.centerIn: parent; text: marked ? "✓" : "○"; color: marked ? root.successGreen : root.mutedText; font.pixelSize: 26; font.bold: true }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 84
            anchors.right: sizePill.left
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text { width: parent.width; text: root.clean(candidateData.name, "Unnamed file"); color: root.textWhite; font.pixelSize: 19; font.bold: true; elide: Text.ElideMiddle }
            Text { width: parent.width; text: root.clean(candidateData.category, "Review item") + "  •  " + root.clean(candidateData.path); color: root.neutronCyan; font.pixelSize: 12; font.bold: true; elide: Text.ElideMiddle }
            Text { width: parent.width; text: root.clean(candidateData.purpose, "Review before deletion."); color: root.mutedText; font.pixelSize: 13; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
            Text { width: parent.width; text: "LAST USED  " + root.clean(candidateData.lastUsed, "UNKNOWN") + "   •   MODIFIED  " + root.clean(candidateData.lastModified, "UNKNOWN"); color: "#B4C9DF"; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight }
        }

        Rectangle {
            id: sizePill
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 132
            height: 60
            radius: 18
            color: candidateData.recommended ? "#143B31" : "#3D3218"
            border.width: 1
            border.color: candidateData.recommended ? root.successGreen : root.warningGold
            Column { anchors.centerIn: parent; spacing: 3
                Text { text: root.clean(candidateData.size, "0 B"); color: root.textWhite; font.pixelSize: 15; font.bold: true; horizontalAlignment: Text.AlignHCenter; width: 112 }
                Text { text: candidateData.recommended ? "RECOMMENDED" : "REVIEW"; color: candidateData.recommended ? root.successGreen : root.warningGold; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; width: 112 }
            }
        }
    }

    function themeFile(path) {
        try {
            if (assetBackend && typeof assetBackend.themeFile === "function")
                return String(assetBackend.themeFile(path) || "")
        } catch (error) {}
        return ""
    }

    function clean(value, fallbackValue) {
        if (value === undefined || value === null || String(value).trim().length === 0)
            return fallbackValue || ""
        return String(value).trim()
    }

    function boolValue(value) { return value === true || Number(value) !== 0 }

    function flattenDevices(list, level) {
        var output = []
        var rows = list || []
        for (var i = 0; i < rows.length; i++) {
            var item = rows[i]
            if (!item) continue
            var copy = {}
            for (var key in item) copy[key] = item[key]
            copy.depth = level || 0
            output.push(copy)
            var children = item.children || []
            var nested = flattenDevices(children, (level || 0) + 1)
            for (var n = 0; n < nested.length; n++) output.push(nested[n])
        }
        return output
    }

    function syncDevices() {
        var previous = selectedDevicePath
        try { flatDevices = flattenDevices(storageBackend ? storageBackend.devices : [], 0) }
        catch (error) { flatDevices = [] }

        selectedDeviceIndex = 0
        if (previous.length > 0) {
            for (var i = 0; i < flatDevices.length; i++) {
                if (clean(flatDevices[i].path) === previous) {
                    selectedDeviceIndex = i
                    break
                }
            }
        }
        if (flatDevices.length > 0)
            selectedDevicePath = clean(flatDevices[selectedDeviceIndex].path)
        else
            selectedDevicePath = ""
        clampControl()
    }

    function applyDashboardContext() {
        var requested = contextData && contextData.device ? clean(contextData.device.path) : ""
        if (requested.length > 0) {
            for (var i = 0; i < flatDevices.length; ++i) {
                if (clean(flatDevices[i].path) === requested) {
                    selectedDeviceIndex = i
                    selectedDevicePath = requested
                    break
                }
            }
        }

        var tool = contextData ? clean(contextData.storageTool).toLowerCase() : ""
        if (!tool.length || tool === "overview")
            return

        focusPane = 1
        controlIndex = 0

        if (tool === "health" || tool === "smart" || tool === "smart-health") {
            categoryIndex = 2
        } else if (tool === "format") {
            categoryIndex = 3
        } else if (tool === "encrypt" || tool === "decrypt") {
            categoryIndex = 4
            securityRequestedMode = tool
        } else if (tool === "optimize") {
            categoryIndex = 5
            var selectedMount = contextData ? clean(contextData.selectedMount) : ""
            if (selectedMount.length > 0)
                optimizationRootPath = selectedMount
        } else if (tool === "imageflash" || tool === "image-flash") {
            categoryIndex = 6
        } else if (tool === "details") {
            categoryIndex = 7
        }

        clampControl()
        ensureControlVisible()
    }

    function selectedDevice() {
        if (selectedDeviceIndex < 0 || selectedDeviceIndex >= flatDevices.length)
            return ({})
        return flatDevices[selectedDeviceIndex] || ({})
    }

    function selectedTopDisk() {
        var item = selectedDevice()
        if (!item) return ({})
        if (item.type === "disk") return item
        var parent = clean(item.parentPath)
        for (var i = 0; i < flatDevices.length; i++)
            if (clean(flatDevices[i].path) === parent) return flatDevices[i]
        return item
    }

    function physicalDevice(item) {
        var value = item || ({})
        if (clean(value.type).toLowerCase() === "disk") return value
        var parent = clean(value.parentPath)
        for (var i = 0; i < flatDevices.length; i++) {
            if (clean(flatDevices[i].path) === parent) return flatDevices[i]
        }
        return value
    }

    function isSystemStorage(item) {
        var value = item || ({})
        var disk = physicalDevice(value)
        return value.system === true || value.containsRoot === true || disk.system === true || disk.containsRoot === true ||
               (storageBackend && clean(storageBackend.systemDisk).length > 0 && clean(disk.path) === clean(storageBackend.systemDisk))
    }

    function manufacturerKey(item) {
        if (isSystemStorage(item)) return "neutronos"
        var disk = physicalDevice(item)
        var text = (clean(disk.vendor) + " " + clean(disk.model)).toLowerCase()
        if (text.indexOf("seagate") >= 0 || text.indexOf("st8000") >= 0 || text.indexOf("st4000") >= 0 || text.indexOf("st2000") >= 0) return "seagate"
        if (text.indexOf("samsung") >= 0) return "samsung"
        if (text.indexOf("sk hynix") >= 0 || text.indexOf("skhynix") >= 0 || text.indexOf("solidigm") >= 0) return "hynix"
        if (text.indexOf("micron") >= 0 || text.indexOf("crucial") >= 0) return "micron"
        if (text.indexOf("kioxia") >= 0 || text.indexOf("toshiba") >= 0) return "kioxia"
        if (text.indexOf("western digital") >= 0 || text.indexOf("wd ") >= 0 || text.indexOf(" wdc") >= 0 || text.indexOf("sandisk") >= 0 || text.indexOf("san disk") >= 0) return "wd"
        if (text.indexOf("kingston") >= 0) return "kingston"
        if (text.indexOf("pny") >= 0) return "pny"
        return "generic"
    }

    function manufacturerName(item) {
        var key = manufacturerKey(item)
        if (key === "neutronos") return "NeutronOS"
        if (key === "seagate") return "Seagate"
        if (key === "samsung") return "Samsung Electronics"
        if (key === "hynix") return "SK hynix / Solidigm"
        if (key === "micron") return "Micron / Crucial"
        if (key === "kioxia") return "Kioxia"
        if (key === "wd") return "Western Digital / SanDisk"
        if (key === "kingston") return "Kingston"
        if (key === "pny") return "PNY"
        var disk = physicalDevice(item)
        return clean(disk.vendor, "Storage Device")
    }

    function manufacturerMark(item) {
        var key = manufacturerKey(item)
        if (key === "neutronos") return "nOS"
        if (key === "seagate") return "S"
        if (key === "samsung") return "SAMSUNG"
        if (key === "hynix") return "SK"
        if (key === "micron") return "M"
        if (key === "kioxia") return "K"
        if (key === "wd") return "WD"
        if (key === "kingston") return "K"
        if (key === "pny") return "PNY"
        return clean(physicalDevice(item).type).toLowerCase() === "part" ? "VOL" : "DRV"
    }

    function manufacturerColor(item) {
        var key = manufacturerKey(item)
        if (key === "neutronos") return "#FF3E4D"
        if (key === "seagate") return "#66D13F"
        if (key === "samsung") return "#4D8CFF"
        if (key === "hynix") return "#FF7A45"
        if (key === "micron") return "#66C2FF"
        if (key === "kioxia") return "#FF405F"
        if (key === "wd") return "#33A7FF"
        if (key === "kingston") return "#FF5C67"
        if (key === "pny") return "#8E7CFF"
        return neutronCyan
    }

    function displayUsageDevice(item) {
        var value = item || ({})
        if (Number(value.filesystemBytes || 0) > 0 || Number(value.usedBytes || 0) > 0 || clean(value.mountText).length > 0)
            return value
        var disk = physicalDevice(value)
        var children = disk && disk.children ? disk.children : []
        for (var i = 0; i < children.length; i++) {
            var child = children[i] || ({})
            if (Number(child.filesystemBytes || 0) > 0 || clean(child.mountText).length > 0)
                return child
        }
        return value
    }

    function selectedFriendlyTitle() {
        var item = selectedDevice()
        if (!item || clean(item.path).length === 0) return "No storage selected"
        if (isSystemStorage(item)) return "NeutronOS Boot Storage"
        var label = clean(item.label)
        var disk = physicalDevice(item)
        var model = clean(disk.model)
        if (label.length > 0) return label
        if (model.length > 0) return model
        return clean(item.path, "Storage Device")
    }

    function selectedFriendlySubtitle() {
        var item = selectedDevice()
        var disk = physicalDevice(item)
        if (!item || clean(item.path).length === 0) return "Connect a drive or refresh the inventory"
        var values = []
        values.push(manufacturerName(item))
        if (clean(disk.model).length > 0 && clean(disk.model).toLowerCase() !== manufacturerName(item).toLowerCase()) values.push(clean(disk.model))
        if (clean(item.size).length > 0) values.push(clean(item.size))
        if (clean(item.transport).length > 0) values.push(clean(item.transport).toUpperCase())
        else if (clean(disk.transport).length > 0) values.push(clean(disk.transport).toUpperCase())
        return values.join("  •  ")
    }

    function workActive() {
        return operationBusy || optimizationScanning || securityTaskActive
    }

    function workTitle() {
        if (operationBusy) return clean(storageBackend ? storageBackend.operationName : "", "STORAGE OPERATION")
        if (optimizationScanning) return "STORAGE OPTIMIZATION SCAN"
        if (securityTaskActive) return securityTaskName.length > 0 ? securityTaskName : "STORAGE SECURITY"
        return "STORAGE OPERATION"
    }

    function workProgress() {
        if (operationBusy) {
            var value = Number(storageBackend ? storageBackend.operationProgress : -1)
            return value >= 0 ? Math.max(0, Math.min(100, Math.round(value))) : 0
        }
        // These backends expose a real busy/completion boundary but no incremental
        // percentage. Keeping this at zero until completion is truthful rather than
        // animating a fake percentage.
        if (optimizationScanning || securityTaskActive) return 0
        return 100
    }

    function workStage() {
        if (operationBusy) return clean(storageBackend ? storageBackend.operationStatus : "", "Working")
        if (optimizationScanning) return "Scanning approved locations and building the review list"
        if (securityTaskActive) return securityTaskName.indexOf("DECRYPT") >= 0 ? "Decrypting and authenticating the selected data" : "Encrypting and authenticating the selected data"
        return "Complete"
    }

    function showTaskResult(title, success, message) {
        taskResultTitle = clean(title, "STORAGE TASK")
        taskResultSuccess = success === true
        taskResultMessage = clean(message, success ? "Task completed successfully." : "Task failed.")
        taskResultVisible = true
    }

    function deviceTitle(item) {
        var label = clean(item.label)
        var model = clean(item.model)
        var base = label.length > 0 ? label : (model.length > 0 ? model : clean(item.path, "STORAGE DEVICE"))
        var mounts = item && item.mountPoints ? item.mountPoints : []
        var isBoot = item && (item.containsRoot === true || mounts.indexOf("/") >= 0)
        if (isBoot) base = "BOOT · " + base
        return (item.depth > 0 ? "↳  " : "") + base
    }

    function deviceSubtitle(item) {
        var pieces = [clean(item.path), clean(item.size)]
        if (clean(item.filesystem).length > 0) pieces.push(clean(item.filesystem).toUpperCase())
        if (clean(item.transport).length > 0) pieces.push(clean(item.transport).toUpperCase())
        return pieces.filter(function(v) { return v.length > 0 }).join("  •  ")
    }

    function deviceMountText(item) {
        return clean(item.mountText, "NOT MOUNTED")
    }

    function displayIds() {
        try {
            var values = monitorBackend && monitorBackend.displayedMountIds ? monitorBackend.displayedMountIds : []
            return [values.length > 0 ? clean(values[0]) : "", values.length > 1 ? clean(values[1]) : ""]
        } catch (error) { return ["", ""] }
    }

    function stableDisplayId(item) {
        return clean(item.uuid, clean(item.partUuid, clean(item.path)))
    }

    function assignDisplaySlot(slotIndex) {
        var item = selectedDevice()
        if (!item || clean(item.path).length === 0) return
        if (clean(item.mountText).length === 0) {
            setStatus("Select a mounted volume for the System Overview display.", true)
            return
        }
        var ids = displayIds()
        ids[slotIndex] = stableDisplayId(item)
        if (ids[0] === ids[1]) ids[slotIndex === 0 ? 1 : 0] = ""
        try {
            if (monitorBackend && typeof monitorBackend.setDisplayedMounts === "function") {
                if (monitorBackend.setDisplayedMounts(ids))
                    setStatus("Display slot " + (slotIndex + 1) + " updated.", false)
                else
                    setStatus("The System Overview rejected that storage selection.", true)
            }
        } catch (error) { setStatus(String(error), true) }
    }

    function setStatus(message, isError) {
        statusToastTimer.stop()
        statusMessage = clean(message)
        statusIsError = isError === true
        if (statusMessage.length > 0) {
            statusToastTimer.interval = statusIsError ? 6000 : 2800
            statusToastTimer.restart()
        }
    }

    function containsPath(list, path) {
        var target = clean(path)
        for (var i = 0; i < list.length; i++) if (clean(list[i]) === target) return true
        return false
    }

    function toggleOptimizationPath(path) {
        var target = clean(path)
        if (target.length === 0) return
        var next = []
        var removed = false
        for (var i = 0; i < optimizationSelectedPaths.length; i++) {
            if (clean(optimizationSelectedPaths[i]) === target) removed = true
            else next.push(optimizationSelectedPaths[i])
        }
        if (!removed) next.push(target)
        optimizationSelectedPaths = next
        optimizationDeleteArmed = false
    }

    function selectRecommendedOptimizationPaths() {
        var next = []
        for (var i = 0; i < optimizationCandidates.length; i++) {
            var candidate = optimizationCandidates[i] || ({})
            if (candidate.recommended === true && candidate.writable === true) next.push(clean(candidate.path))
        }
        optimizationSelectedPaths = next
        optimizationDeleteArmed = false
    }

    function selectedOptimizationBytes() {
        var total = 0
        for (var i = 0; i < optimizationCandidates.length; i++) {
            var candidate = optimizationCandidates[i] || ({})
            if (containsPath(optimizationSelectedPaths, candidate.path)) total += Number(candidate.sizeBytes || 0)
        }
        return total
    }

    function humanBytes(bytes) {
        var value = Math.max(0, Number(bytes || 0))
        var units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var index = 0
        while (value >= 1024 && index < units.length - 1) { value /= 1024; index++ }
        return (index === 0 ? Math.round(value) : value.toFixed(1)) + " " + units[index]
    }

    function cycleEncryptionMethod(delta) {
        var list = encryptionMethods || []
        if (list.length === 0) return
        var index = 0
        for (var i = 0; i < list.length; i++) if (String(list[i]) === securityMethod) index = i
        securityMethod = String(list[(index + delta + list.length) % list.length])
        securityArmedAction = ""
    }

    function suggestedSecurityDestination(decrypting) {
        var source = clean(securitySourcePath)
        if (source.length === 0) return ""
        if (decrypting) {
            var suffixes = [".nenc", ".aesgcm", ".gpg"]
            for (var i = 0; i < suffixes.length; i++)
                if (source.toLowerCase().endsWith(suffixes[i])) return source.slice(0, -suffixes[i].length)
            return source + ".decrypted"
        }
        try {
            if (fileBackend && typeof fileBackend.suggestedEncryptedName === "function")
                return String(fileBackend.suggestedEncryptedName(source))
        } catch (error) {}
        return source + ".nenc"
    }

    function openTextKeyboard(targetName, titleText) {
        keyboardTarget = targetName
        keyboardOpen = true
        volumeKeyboard.title = titleText
        volumeKeyboard.visibleMode = true
        volumeKeyboard.openKeyboard(targetName === "password" ? "large" : "large")
        volumeKeyboard.forceActiveFocus()
    }

    function currentKeyboardText() {
        if (keyboardTarget === "label") return volumeLabel
        if (keyboardTarget === "optimizationRoot") return optimizationRootPath
        if (keyboardTarget === "source") return securitySourcePath
        if (keyboardTarget === "destination") return securityDestinationPath
        if (keyboardTarget === "password") return securityPassword
        if (keyboardTarget === "mountName") return mountName
        if (keyboardTarget === "flashImage") return flashImagePath
        if (keyboardTarget === "setupHostname") return setupHostname
        if (keyboardTarget === "setupUsername") return setupUsername
        if (keyboardTarget === "setupPassword") return setupPassword
        if (keyboardTarget === "setupSsid") return setupSsid
        if (keyboardTarget === "setupWifiPassword") return setupWifiPassword
        if (keyboardTarget === "setupWifiCountry") return setupWifiCountry
        if (keyboardTarget === "setupTimezone") return setupTimezone
        if (keyboardTarget === "setupLocale") return setupLocale
        if (keyboardTarget === "setupKeyboard") return setupKeyboard
        return ""
    }

    function setKeyboardText(value) {
        var text = String(value || "")
        if (keyboardTarget === "label") volumeLabel = text.slice(0, 32)
        else if (keyboardTarget === "optimizationRoot") optimizationRootPath = text.slice(0, 1024)
        else if (keyboardTarget === "source") securitySourcePath = text.slice(0, 1024)
        else if (keyboardTarget === "destination") securityDestinationPath = text.slice(0, 1024)
        else if (keyboardTarget === "password") securityPassword = text.slice(0, 256)
        else if (keyboardTarget === "mountName") mountName = text.slice(0, 48)
        else if (keyboardTarget === "flashImage") flashImagePath = text.slice(0, 2048)
        else if (keyboardTarget === "setupHostname") setupHostname = text.slice(0, 63)
        else if (keyboardTarget === "setupUsername") setupUsername = text.toLowerCase().slice(0, 32)
        else if (keyboardTarget === "setupPassword") setupPassword = text.slice(0, 256)
        else if (keyboardTarget === "setupSsid") setupSsid = text.slice(0, 64)
        else if (keyboardTarget === "setupWifiPassword") setupWifiPassword = text.slice(0, 256)
        else if (keyboardTarget === "setupWifiCountry") setupWifiCountry = text.toUpperCase().slice(0, 2)
        else if (keyboardTarget === "setupTimezone") setupTimezone = text.slice(0, 80)
        else if (keyboardTarget === "setupLocale") setupLocale = text.slice(0, 40)
        else if (keyboardTarget === "setupKeyboard") setupKeyboard = text.slice(0, 24)
    }

    function refreshAll() {
        try { if (storageBackend && typeof storageBackend.refreshDevices === "function") storageBackend.refreshDevices() }
        catch (error) { setStatus(String(error), true) }
        try { if (monitorBackend && typeof monitorBackend.refreshStorage === "function") monitorBackend.refreshStorage() }
        catch (error2) {}
        syncDevices()
    }

    function setupPayload() {
        return {
            hostname: setupHostname,
            username: setupUsername,
            password: setupPassword,
            ssh: setupSsh,
            wifi: setupWifi,
            ssid: setupSsid,
            wifiPassword: setupWifiPassword,
            wifiCountry: setupWifiCountry,
            timezone: setupTimezone,
            locale: setupLocale,
            keyboard: setupKeyboard
        }
    }

    function openImagerMode() {
        imagerModeIndex = 0
        imagerModeVisible = true
        imagerCatalogVisible = false
        imagerSetupVisible = false
        manualPickerVisible = false
        imagerSetupArmed = false
    }

    function openRecommendedCatalog() {
        imagerModeVisible = false
        imagerCatalogVisible = true
        imagerCatalogIndex = 0
        try {
            if (storageBackend && imagerCatalog.length === 0 && !imagerCatalogLoading)
                storageBackend.refreshImagerCatalog()
        } catch (error) { setStatus(String(error), true) }
    }

    function openManualPicker(purpose) {
        manualPickerPurpose = clean(purpose, "imager")
        imagerModeVisible = false
        manualPickerVisible = true
        manualPickerIndex = 0
        if (manualPickerPath.length === 0) manualPickerPath = "/home/echo/Downloads"
        try {
            if (fileBackend && typeof fileBackend.loadDirectory === "function")
                fileBackend.loadDirectory(manualPickerPath)
            else setStatus("File Manager backend is unavailable.", true)
        } catch (error) { setStatus(String(error), true) }
    }

    function selectedManualItem() {
        if (!manualPickerItems || manualPickerItems.length === 0) return ({})
        return manualPickerItems[Math.max(0, Math.min(manualPickerItems.length - 1, manualPickerIndex))] || ({})
    }

    function manualImageSupported(path) {
        var lower = String(path || "").toLowerCase()
        return lower.endsWith(".img") || lower.endsWith(".iso") || lower.endsWith(".xz") || lower.endsWith(".gz") || lower.endsWith(".zip")
    }

    function openSetupFor(osEntry, manualSource) {
        selectedImagerOs = osEntry || ({})
        imagerManualSource = manualSource === true
        imagerCatalogVisible = false
        manualPickerVisible = false
        imagerSetupIndex = 0
        imagerSetupArmed = false
        imagerSetupVisible = true
    }

    function beginImagerInstall() {
        var targetPath = clean(selectedTopDisk().path)
        if (targetPath.length === 0) {
            setStatus("Select a whole non-system target disk first.", true)
            return false
        }
        if (setupHostname.trim().length === 0 || setupUsername.trim().length === 0 || setupPassword.length < 8) {
            setStatus("Hostname and username are required, and the password must contain at least eight characters.", true)
            return false
        }
        if (setupWifi && (setupSsid.trim().length === 0 || setupWifiPassword.length < 8)) {
            setStatus("Wi-Fi setup requires an SSID and a password of at least eight characters.", true)
            return false
        }
        if (!imagerSetupArmed) {
            imagerSetupArmed = true
            setStatus("IMAGE INSTALL ARMED — press X again to download/write and completely overwrite " + targetPath + ".", true)
            return false
        }
        imagerSetupArmed = false
        var started = false
        try {
            if (!storageBackend) {
                setStatus("Storage backend is unavailable.", true)
                return false
            }
            if (imagerManualSource)
                started = storageBackend.installManualImage(clean(flashImagePath), targetPath, setupPayload())
            else
                started = storageBackend.installRecommendedImage(selectedImagerOs, targetPath, setupPayload())
        } catch (error) {
            setStatus(String(error), true)
            return false
        }
        if (!started) {
            setStatus(storageBackend ? clean(storageBackend.lastMessage, "Image installation could not start.") : "Storage backend unavailable.", true)
            return false
        }
        imagerSetupVisible = false
        imagerOperationActive = true
        setStatus("Raspberry Pi Imager started. Keep the target connected through verification and setup.", false)
        return true
    }

    function currentControlCount() {
        if (categoryIndex === 0) return 4
        if (categoryIndex === 1) return Math.max(1, flatDevices.length)
        if (categoryIndex === 2) return 2
        if (categoryIndex === 3) return 4
        if (categoryIndex === 4) return 7
        if (categoryIndex === 5) return optimizationCandidates.length + 5
        if (categoryIndex === 6) return imageFlashTab === 0 ? 5 : 3
        return 1
    }

    function clampControl() {
        controlIndex = Math.max(0, Math.min(currentControlCount() - 1, controlIndex))
        ensureVisible()
    }

    function selectCategory(index) {
        categoryIndex = (index + categories.length) % categories.length
        controlIndex = 0
        formatArmed = false
        cloneArmed = false
        flashArmed = false
        optimizationDeleteArmed = false
        securityArmedAction = ""
        ensureVisible()
    }

    function moveControl(delta) {
        var count = currentControlCount()
        if (count <= 0) return
        controlIndex = (controlIndex + delta + count) % count
        if (categoryIndex === 1 && flatDevices.length > 0) {
            selectedDeviceIndex = controlIndex
            selectedDevicePath = clean(flatDevices[selectedDeviceIndex].path)
            try { if (storageBackend && typeof storageBackend.suggestedMountName === "function") mountName = String(storageBackend.suggestedMountName(selectedDevicePath)) } catch (error) {}
        }
        formatArmed = false
        cloneArmed = false
        flashArmed = false
        optimizationDeleteArmed = false
        securityArmedAction = ""
        ensureVisible()
    }

    function ensureVisible() {
        Qt.callLater(function() {
            var flick = currentFlick()
            if (!flick) return
            var rowHeight = categoryIndex === 1 ? 122 : (categoryIndex === 5 ? 150 : 102)
            var top = Math.max(0, controlIndex * rowHeight - 24)
            var bottom = top + rowHeight + 48
            if (top < flick.contentY) flick.contentY = top
            else if (bottom > flick.contentY + flick.height) flick.contentY = Math.max(0, bottom - flick.height)
        })
    }

    function currentFlick() {
        if (categoryIndex === 0) return overviewFlick
        if (categoryIndex === 1) return devicesFlick
        if (categoryIndex === 2) return healthFlick
        if (categoryIndex === 3) return formatFlick
        if (categoryIndex === 4) return securityFlick
        if (categoryIndex === 5) return optimizeFlick
        if (categoryIndex === 6) return backupFlick
        return detailsFlick
    }

    function cycleFilesystem(delta) {
        var list = filesystems
        if (!list || list.length === 0) return
        var index = 0
        for (var i = 0; i < list.length; i++) if (String(list[i]) === formatFilesystem) index = i
        index = (index + delta + list.length) % list.length
        formatFilesystem = String(list[index])
    }

    function openLabelKeyboard() { openTextKeyboard("label", "VOLUME LABEL") }

    function activateCurrent() {
        if (workActive()) {
            setStatus("Wait for the current storage operation to finish.", true)
            return
        }

        if (categoryIndex === 0) {
            if (controlIndex === 0) refreshAll()
            else if (controlIndex === 1) assignDisplaySlot(0)
            else if (controlIndex === 2) assignDisplaySlot(1)
            else selectCategory(5)
            return
        }

        if (categoryIndex === 1) {
            if (flatDevices.length > 0) {
                selectedDeviceIndex = controlIndex
                selectedDevicePath = clean(flatDevices[selectedDeviceIndex].path)
                try { if (storageBackend && typeof storageBackend.suggestedMountName === "function") mountName = String(storageBackend.suggestedMountName(selectedDevicePath)) } catch (error) {}
                deviceActionIndex = 0
                deviceActionArmed = ""
                deviceActionVisible = true
                setStatus(deviceTitle(selectedDevice()) + " selected.", false)
            }
            return
        }

        if (categoryIndex === 2) {
            if (controlIndex === 0) {
                try {
                    var started = false
                    if (storageBackend && typeof storageBackend.runHealthCheck === "function")
                        started = storageBackend.runHealthCheck(selectedDevicePath)
                    else if (storageBackend && typeof storageBackend.runSmartCheck === "function")
                        started = storageBackend.runSmartCheck(selectedDevicePath)
                    if (!started)
                        setStatus(storageBackend ? clean(storageBackend.lastMessage, "Health check could not start.") : "Storage backend unavailable.", true)
                    else if (!(storageBackend && storageBackend.busy === true))
                        setStatus(storageBackend ? clean(storageBackend.lastMessage, "Health check complete.") : "Health check complete.", false)
                } catch (error) { setStatus(String(error), true) }
            } else refreshAll()
            return
        }

        if (categoryIndex === 3) {
            if (controlIndex === 0) cycleFilesystem(1)
            else if (controlIndex === 1) openLabelKeyboard()
            else if (controlIndex === 2) {
                var formatValidation = ({ok:false, message:"Storage backend unavailable."})
                try {
                    if (storageBackend && typeof storageBackend.validateFormat === "function")
                        formatValidation = storageBackend.validateFormat(selectedDevicePath, formatFilesystem)
                } catch (formatValidationError) {
                    formatArmed = false
                    setStatus(String(formatValidationError), true)
                    return
                }
                if (!formatValidation.ok) {
                    formatArmed = false
                    setStatus(clean(formatValidation.message, "Format validation failed."), true)
                    return
                }
                if (!formatArmed) {
                    formatArmed = true
                    setStatus(clean(formatValidation.message, "FORMAT ARMED — press X again to erase the selected device.") + " Press X again to continue.", true)
                    return
                }
                // Revalidate immediately before the destructive call in case the
                // selected disk, mount state, or privilege state changed while armed.
                try {
                    formatValidation = storageBackend.validateFormat(selectedDevicePath, formatFilesystem)
                    if (!formatValidation.ok) {
                        formatArmed = false
                        setStatus(clean(formatValidation.message, "Format validation failed."), true)
                        return
                    }
                    formatArmed = false
                    if (!storageBackend.formatDevice(selectedDevicePath, formatFilesystem, volumeLabel))
                        setStatus(clean(storageBackend.lastMessage, "Format could not start."), true)
                } catch (error2) {
                    formatArmed = false
                    setStatus(String(error2), true)
                }
            } else formatArmed = false
            return
        }

        if (categoryIndex === 4) {
            if (controlIndex === 0) openTextKeyboard("source", "SOURCE FILE OR ENCRYPTED ARCHIVE")
            else if (controlIndex === 1) openTextKeyboard("destination", "DESTINATION PATH")
            else if (controlIndex === 2) cycleEncryptionMethod(1)
            else if (controlIndex === 3) openTextKeyboard("password", "ENCRYPTION PASSWORD")
            else if (controlIndex === 4 || controlIndex === 5) {
                var action = controlIndex === 4 ? "encrypt" : "decrypt"
                if (clean(securitySourcePath).length === 0 || clean(securityPassword).length < 8) {
                    setStatus("Enter a source path and a password of at least eight characters.", true)
                    return
                }
                if (clean(securityDestinationPath).length === 0)
                    securityDestinationPath = suggestedSecurityDestination(action === "decrypt")
                if (securityArmedAction !== action) {
                    securityArmedAction = action
                    setStatus(action.toUpperCase() + " ARMED — press X again to begin.", true)
                    return
                }
                securityArmedAction = ""
                try {
                    if (!fileBackend) { setStatus("File encryption backend is unavailable.", true); return }
                    securityTaskName = action === "encrypt" ? "ENCRYPT STORAGE DATA" : "DECRYPT STORAGE DATA"
                    securityTaskActive = true
                    if (action === "encrypt")
                        fileBackend.encryptPath(securitySourcePath, securityDestinationPath, securityPassword, securityMethod)
                    else
                        fileBackend.decryptPath(securitySourcePath, securityDestinationPath, securityPassword, securityMethod)
                    setStatus(action.toUpperCase() + " started. The source is never deleted automatically.", false)
                } catch (securityError) {
                    securityTaskActive = false
                    setStatus(String(securityError), true)
                }
            } else {
                securitySourcePath = ""
                securityDestinationPath = ""
                securityPassword = ""
                securityArmedAction = ""
                setStatus("Security fields cleared.", false)
            }
            return
        }

        if (categoryIndex === 5) {
            var count = optimizationCandidates.length
            if (controlIndex === 0) openTextKeyboard("optimizationRoot", "OPTIMIZATION SCAN LOCATION")
            else if (controlIndex === 1) adjustCurrent(1)
            else if (controlIndex === 2) {
                try {
                    if (!storageBackend || !storageBackend.scanOptimization(optimizationRootPath, optimizationAgeDays))
                        setStatus(storageBackend ? clean(storageBackend.lastMessage, "Optimization scan could not start.") : "Storage backend unavailable.", true)
                    else setStatus("Scanning for review candidates. Nothing is deleted automatically.", false)
                } catch (scanError) { setStatus(String(scanError), true) }
            } else if (controlIndex >= 3 && controlIndex < 3 + count) {
                toggleOptimizationPath(clean(optimizationCandidates[controlIndex - 3].path))
            } else if (controlIndex === 3 + count) {
                if (optimizationSelectedPaths.length === 0) {
                    setStatus("Select at least one reviewed file before deleting.", true)
                    return
                }
                var deleteValidation = ({ok:false, message:"Storage backend unavailable."})
                try {
                    if (storageBackend && typeof storageBackend.validateOptimizationDelete === "function")
                        deleteValidation = storageBackend.validateOptimizationDelete(optimizationSelectedPaths)
                } catch (deleteValidationError) {
                    optimizationDeleteArmed = false
                    setStatus(String(deleteValidationError), true)
                    return
                }
                if (!deleteValidation.ok) {
                    optimizationDeleteArmed = false
                    setStatus(clean(deleteValidation.message, "No reviewed files are currently safe to delete."), true)
                    return
                }
                if (!optimizationDeleteArmed) {
                    optimizationDeleteArmed = true
                    setStatus(clean(deleteValidation.message, "Delete reviewed files?") + " Press X again to permanently delete them.", true)
                    return
                }
                optimizationDeleteArmed = false
                try {
                    deleteValidation = storageBackend.validateOptimizationDelete(optimizationSelectedPaths)
                    if (!deleteValidation.ok) {
                        setStatus(clean(deleteValidation.message, "Delete validation failed."), true)
                        return
                    }
                    if (!storageBackend.deleteOptimizationCandidates(optimizationSelectedPaths, "DELETE"))
                        setStatus(clean(storageBackend.lastMessage, "Delete operation failed."), true)
                    else optimizationSelectedPaths = []
                } catch (deleteError) { setStatus(String(deleteError), true) }
            } else selectRecommendedOptimizationPaths()
            return
        }

        if (categoryIndex === 6) {
            if (controlIndex === 0) {
                imageFlashTab = (imageFlashTab + 1) % 2
                flashArmed = false
                cloneArmed = false
                return
            }

            if (imageFlashTab === 1) {
                if (controlIndex === 1) openImagerMode()
                else {
                    try {
                        if (storageBackend && !imagerCatalogLoading) storageBackend.refreshImagerCatalog()
                    } catch (catalogError) { setStatus(String(catalogError), true) }
                }
                return
            }

            if (controlIndex === 1) {
                flashArmed = false
                cloneArmed = false
                openManualPicker("rawflash")
                return
            }

            if (controlIndex === 2) {
                cloneArmed = false
                var targetPath = clean(selectedTopDisk().path)
                var validation = ({ok:false, message:"Storage backend unavailable."})
                try {
                    if (storageBackend && typeof storageBackend.validateImageFlash === "function")
                        validation = storageBackend.validateImageFlash(clean(flashImagePath), targetPath)
                } catch (validationError) {
                    setStatus(String(validationError), true)
                    return
                }
                if (!validation.ok) {
                    flashArmed = false
                    setStatus(clean(validation.message, "Image flash validation failed."), true)
                    return
                }
                if (!flashArmed) {
                    flashArmed = true
                    setStatus("IMAGE FLASH ARMED — press X again to overwrite " + targetPath + ".", true)
                    return
                }
                flashArmed = false
                try {
                    if (!storageBackend || !storageBackend.flashImage(clean(flashImagePath), targetPath))
                        setStatus(storageBackend ? clean(storageBackend.lastMessage, "Image flash could not start.") : "Storage backend unavailable.", true)
                    else
                        setStatus("Image flash started. Keep the target connected until verification completes.", false)
                } catch (flashError) { setStatus(String(flashError), true) }
                return
            }

            if (controlIndex === 3) {
                flashArmed = false
                var cloneTarget = clean(selectedTopDisk().path)
                var cloneValidation = ({ok:false, message:"Storage backend unavailable."})
                try {
                    if (storageBackend && typeof storageBackend.validateBootClone === "function")
                        cloneValidation = storageBackend.validateBootClone(cloneTarget)
                } catch (cloneValidationError) {
                    cloneArmed = false
                    setStatus(String(cloneValidationError), true)
                    return
                }
                if (!cloneValidation.ok) {
                    cloneArmed = false
                    setStatus(clean(cloneValidation.message, "Boot backup validation failed."), true)
                    return
                }
                if (!cloneArmed) {
                    cloneArmed = true
                    setStatus(clean(cloneValidation.message, "The target will be overwritten.") + " Press X again to begin the boot backup.", true)
                    return
                }
                try {
                    cloneValidation = storageBackend.validateBootClone(cloneTarget)
                    if (!cloneValidation.ok) {
                        cloneArmed = false
                        setStatus(clean(cloneValidation.message, "Boot backup validation failed."), true)
                        return
                    }
                    cloneArmed = false
                    if (!storageBackend.cloneBootDevice(cloneTarget))
                        setStatus(clean(storageBackend.lastMessage, "Boot backup could not start."), true)
                } catch (error3) {
                    cloneArmed = false
                    setStatus(String(error3), true)
                }
                return
            }

            flashArmed = false
            cloneArmed = false
            setStatus("Pending image-flash or boot-backup action disarmed.", false)
            return
        }

        refreshAll()
    }

    function currentSupportsHorizontalAdjustment() {
        return (categoryIndex === 3 && controlIndex === 0) ||
               (categoryIndex === 4 && controlIndex === 2) ||
               (categoryIndex === 5 && controlIndex === 1) ||
               (categoryIndex === 6 && controlIndex === 0)
    }

    function adjustCurrent(delta) {
        if (categoryIndex === 3 && controlIndex === 0) cycleFilesystem(delta)
        else if (categoryIndex === 4 && controlIndex === 2) cycleEncryptionMethod(delta)
        else if (categoryIndex === 5 && controlIndex === 1) {
            var values = [7, 14, 30, 60, 90, 180, 365]
            var index = values.indexOf(optimizationAgeDays)
            if (index < 0) index = 2
            optimizationAgeDays = values[(index + delta + values.length) % values.length]
            optimizationDeleteArmed = false
        } else if (categoryIndex === 6 && controlIndex === 0) {
            imageFlashTab = (imageFlashTab + delta + 2) % 2
            controlIndex = 0
            flashArmed = false
            cloneArmed = false
        }
    }

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        categoryIndex = 0
        focusPane = 0
        controlIndex = 0
        formatArmed = false
        cloneArmed = false
        flashArmed = false
        optimizationDeleteArmed = false
        securityArmedAction = ""
        securityRequestedMode = ""
        optimizationSelectedPaths = []
        if (optimizationRootPath.length === 0) {
            try { optimizationRootPath = storageBackend ? String(storageBackend.defaultOptimizationRoot()) : "" } catch (error) {}
        }
        keyboardOpen = false
        deviceActionVisible = false
        deviceActionArmed = ""
        imagerModeVisible = false
        imagerCatalogVisible = false
        imagerSetupVisible = false
        manualPickerVisible = false
        imagerResultVisible = false
        taskResultVisible = false
        taskResultSuccess = false
        taskResultTitle = ""
        taskResultMessage = ""
        securityTaskActive = false
        securityTaskName = ""
        headerFocused = false
        imagerSetupArmed = false
        visible = true
        refreshAll()
        applyDashboardContext()
        forceActiveFocus()
    }

    function openModal(context) { open(context) }

    function close() {
        if (workActive()) {
            setStatus("A storage operation is running. Keep Storage open until the task finishes.", true)
            return
        }
        keyboardOpen = false
        volumeKeyboard.visibleMode = false
        visible = false
        closed()
    }

    function closeModal() { close() }

    function normalizeAction(action) {
        var value = String(action || "").trim().toLowerCase()
        if (value === "x" || value === "cross" || value === "primary" || value === "confirm") return "primary"
        if (value === "o" || value === "circle" || value === "cancel" || value === "back") return "cancel"
        if (value === "triangle" || value === "context") return "context"
        if (value === "square" || value === "secondary") return "secondary"
        if (value === "options" || value === "system" || value === "start") return "start"
        if (value === "l1" || value === "left_shoulder") return "previous"
        if (value === "r1" || value === "right_shoulder") return "next"
        if (value === "dpad_left") return "left"
        if (value === "dpad_right") return "right"
        if (value === "dpad_up") return "up"
        if (value === "dpad_down") return "down"
        return value
    }

    function handleControllerPressed(action) {
        if (!visible) return false
        var value = normalizeAction(action)

        if (keyboardOpen) {
            if (typeof volumeKeyboard.handleControllerPressed === "function")
                return volumeKeyboard.handleControllerPressed(value)
            return true
        }

        if (taskResultVisible) {
            if (value === "primary" || value === "cancel") {
                taskResultVisible = false
                forceActiveFocus()
            }
            return true
        }

        if (imagerResultVisible) {
            if (value === "primary" || value === "cancel") {
                imagerResultVisible = false
                forceActiveFocus()
            }
            return true
        }

        if (workActive()) {
            if (value === "secondary" && operationBusy) {
                try {
                    if (storageBackend && typeof storageBackend.cancelOperation === "function") {
                        storageBackend.cancelOperation()
                        setStatus("Cancellation requested. Waiting for the storage backend to stop safely.", false)
                    }
                } catch (cancelError) { setStatus(String(cancelError), true) }
            } else if (value === "cancel") {
                setStatus(operationBusy ? "Task is still running. Press Square to request a safe cancel." : "Task is still running and this backend does not expose a safe cancel action.", false)
            }
            return true
        }

        if (imagerModeVisible) {
            if (value === "cancel") { imagerModeVisible = false; return true }
            if (value === "left" || value === "up") { imagerModeIndex = Math.max(0, imagerModeIndex - 1); return true }
            if (value === "right" || value === "down") { imagerModeIndex = Math.min(1, imagerModeIndex + 1); return true }
            if (value === "primary") {
                if (imagerModeIndex === 0) openRecommendedCatalog()
                else openManualPicker("imager")
            }
            return true
        }

        if (imagerCatalogVisible) {
            if (value === "cancel") { imagerCatalogVisible = false; openImagerMode(); return true }
            if (value === "context") {
                try { if (storageBackend && !imagerCatalogLoading) storageBackend.refreshImagerCatalog() } catch (error) { setStatus(String(error), true) }
                return true
            }
            if (value === "up") { imagerCatalogIndex = Math.max(0, imagerCatalogIndex - 1); return true }
            if (value === "down") { imagerCatalogIndex = Math.min(Math.max(0, imagerCatalog.length - 1), imagerCatalogIndex + 1); return true }
            if (value === "primary" && imagerCatalog.length > 0) {
                var osEntry = imagerCatalog[Math.max(0, Math.min(imagerCatalog.length - 1, imagerCatalogIndex))]
                if (!osEntry.available || clean(osEntry.url).length === 0) {
                    setStatus("NeutronOS is pinned first, but no flashable release image is published in the GitHub Releases repository yet.", true)
                    return true
                }
                openSetupFor(osEntry, false)
            }
            return true
        }

        if (manualPickerVisible) {
            if (value === "cancel") {
                manualPickerVisible = false
                if (manualPickerPurpose === "imager") openImagerMode()
                else forceActiveFocus()
                return true
            }
            if (value === "secondary") {
                var parentPath = manualPickerPath.substring(0, manualPickerPath.lastIndexOf("/"))
                if (parentPath.length === 0) parentPath = "/"
                try { if (fileBackend) fileBackend.loadDirectory(parentPath) } catch (error) { setStatus(String(error), true) }
                return true
            }
            if (value === "up") { manualPickerIndex = Math.max(0, manualPickerIndex - 1); return true }
            if (value === "down") { manualPickerIndex = Math.min(Math.max(0, manualPickerItems.length - 1), manualPickerIndex + 1); return true }
            if (value === "primary") {
                var fileItem = selectedManualItem()
                if (fileItem.isDirectory === true || fileItem.isDir === true) {
                    try { if (fileBackend) fileBackend.loadDirectory(String(fileItem.path || "")) } catch (folderError) { setStatus(String(folderError), true) }
                    return true
                }
                if (!manualImageSupported(fileItem.path)) {
                    setStatus("Select an .img, .iso, .xz, .gz, or .zip image.", true)
                    return true
                }
                flashImagePath = String(fileItem.path || "")
                if (manualPickerPurpose === "rawflash") {
                    manualPickerVisible = false
                    setStatus("Image selected: " + String(fileItem.name || flashImagePath), false)
                    forceActiveFocus()
                } else {
                    openSetupFor({name:String(fileItem.name || "Manual image"), description:"Manually selected image", available:true, initFormat:"systemd"}, true)
                }
            }
            return true
        }

        if (imagerSetupVisible) {
            if (value === "cancel") {
                if (imagerSetupArmed) { imagerSetupArmed = false; setStatus("Image installation disarmed.", false) }
                else { imagerSetupVisible = false; if (imagerManualSource) openManualPicker("imager"); else openRecommendedCatalog() }
                return true
            }
            if (value === "up") { imagerSetupIndex = Math.max(0, imagerSetupIndex - 1); imagerSetupArmed = false; return true }
            if (value === "down") { imagerSetupIndex = Math.min(11, imagerSetupIndex + 1); imagerSetupArmed = false; return true }
            if (value === "left" || value === "right") {
                if (imagerSetupIndex === 3) setupSsh = !setupSsh
                else if (imagerSetupIndex === 4) setupWifi = !setupWifi
                imagerSetupArmed = false
                return true
            }
            if (value === "primary") {
                if (imagerSetupIndex === 0) openTextKeyboard("setupHostname", "HOSTNAME")
                else if (imagerSetupIndex === 1) openTextKeyboard("setupUsername", "USERNAME")
                else if (imagerSetupIndex === 2) openTextKeyboard("setupPassword", "USER PASSWORD")
                else if (imagerSetupIndex === 3) setupSsh = !setupSsh
                else if (imagerSetupIndex === 4) setupWifi = !setupWifi
                else if (imagerSetupIndex === 5) openTextKeyboard("setupSsid", "WI-FI NETWORK NAME")
                else if (imagerSetupIndex === 6) openTextKeyboard("setupWifiPassword", "WI-FI PASSWORD")
                else if (imagerSetupIndex === 7) openTextKeyboard("setupWifiCountry", "WI-FI COUNTRY CODE")
                else if (imagerSetupIndex === 8) openTextKeyboard("setupTimezone", "TIME ZONE")
                else if (imagerSetupIndex === 9) openTextKeyboard("setupLocale", "LOCALE")
                else if (imagerSetupIndex === 10) openTextKeyboard("setupKeyboard", "KEYBOARD LAYOUT")
                else beginImagerInstall()
                return true
            }
            return true
        }

        if (deviceActionVisible) {
            if (value === "cancel") { deviceActionVisible = false; deviceActionArmed = ""; return true }
            if (value === "left" || value === "up") { deviceActionIndex = Math.max(0, deviceActionIndex - 1); deviceActionArmed = ""; return true }
            if (value === "right" || value === "down") { deviceActionIndex = Math.min(3, deviceActionIndex + 1); deviceActionArmed = ""; return true }
            if (value === "primary") {
                var item = selectedDevice()
                var mounted = clean(item.mountText).length > 0
                if (deviceActionIndex === 0) { deviceActionVisible = false; selectCategory(7); return true }
                if (deviceActionIndex === 2) { openTextKeyboard("mountName", "MOUNT NAME"); return true }
                if (deviceActionIndex === 1) {
                    if (!mounted) {
                        var validation = storageBackend ? storageBackend.validateMount(selectedDevicePath, mountName) : ({ok:false,message:"Storage backend unavailable."})
                        if (!validation.ok) { setStatus(String(validation.message || "Mount validation failed."), true); return true }
                        if (storageBackend.mountDevice(selectedDevicePath, mountName)) { deviceActionVisible = false; setStatus(String(validation.message), false) }
                        return true
                    }
                    var unmountValidation = ({ok:false, message:"Storage backend unavailable."})
                    try {
                        if (storageBackend && typeof storageBackend.validateUnmount === "function")
                            unmountValidation = storageBackend.validateUnmount(selectedDevicePath)
                    } catch (unmountValidationError) {
                        deviceActionArmed = ""
                        setStatus(String(unmountValidationError), true)
                        return true
                    }
                    if (!unmountValidation.ok) {
                        deviceActionArmed = ""
                        setStatus(clean(unmountValidation.message, "Unmount validation failed."), true)
                        return true
                    }
                    if (deviceActionArmed !== "unmount") {
                        deviceActionArmed = "unmount"
                        setStatus(clean(unmountValidation.message, "Ready to unmount.") + " Press X again after closing files that use this device.", true)
                        return true
                    }
                    deviceActionArmed = ""
                    try {
                        unmountValidation = storageBackend.validateUnmount(selectedDevicePath)
                        if (!unmountValidation.ok) { setStatus(clean(unmountValidation.message, "Unmount validation failed."), true); return true }
                        if (storageBackend.unmountDevice(selectedDevicePath)) deviceActionVisible = false
                    } catch (unmountError) { setStatus(String(unmountError), true) }
                    return true
                }
                if (deviceActionIndex === 3) {
                    if (deviceActionArmed !== "eject") { deviceActionArmed = "eject"; setStatus("SAFE EJECT ARMED — press X again to unmount and power off the device.", true); return true }
                    deviceActionArmed = ""
                    if (storageBackend && storageBackend.ejectDevice(selectedDevicePath)) deviceActionVisible = false
                    return true
                }
            }
            return true
        }

        if (focusPane === 2) {
            if (value === "primary") { close(); return true }
            if (value === "cancel" || value === "left" || value === "down") {
                headerFocused = false
                focusPane = 0
                return true
            }
            return true
        }

        if (value === "start") {
            headerFocused = true
            focusPane = 2
            return true
        }

        if (value === "cancel") {
            if (formatArmed || cloneArmed || flashArmed || optimizationDeleteArmed || securityArmedAction.length > 0) {
                formatArmed = false
                cloneArmed = false
                flashArmed = false
                optimizationDeleteArmed = false
                securityArmedAction = ""
                setStatus("Pending action disarmed.", false)
            } else close()
            return true
        }
        if (value === "context") { refreshAll(); return true }
        if (value === "previous") { selectCategory(categoryIndex - 1); return true }
        if (value === "next") { selectCategory(categoryIndex + 1); return true }
        if (value === "left") {
            if (focusPane === 1 && currentSupportsHorizontalAdjustment()) adjustCurrent(-1)
            else if (focusPane === 1) focusPane = 0
            else adjustCurrent(-1)
            return true
        }
        if (value === "right") {
            if (focusPane === 0) focusPane = 1
            else adjustCurrent(1)
            return true
        }
        if (value === "up") {
            if (focusPane === 0 && categoryIndex === 0) { headerFocused = true; focusPane = 2 }
            else if (focusPane === 1 && controlIndex === 0) { headerFocused = true; focusPane = 2 }
            else if (focusPane === 0) selectCategory(categoryIndex - 1)
            else moveControl(-1)
            return true
        }
        if (value === "down") {
            if (focusPane === 0) selectCategory(categoryIndex + 1)
            else moveControl(1)
            return true
        }
        if (value === "primary") {
            if (focusPane === 0) focusPane = 1
            else activateCurrent()
            return true
        }
        return true
    }

    Keys.onPressed: function(event) {
        if (!visible) return
        var action = ""
        if (event.key === Qt.Key_Left) action = "left"
        else if (event.key === Qt.Key_Right) action = "right"
        else if (event.key === Qt.Key_Up) action = "up"
        else if (event.key === Qt.Key_Down) action = "down"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) action = "cancel"
        else if (event.key === Qt.Key_F5) action = "context"
        if (action.length > 0) {
            event.accepted = true
            handleControllerPressed(action)
        }
    }

    Connections {
        target: storageBackend
        enabled: target !== null
        ignoreUnknownSignals: true
        function onDevicesChanged() { root.syncDevices() }
        function onOperationChanged() {
            if (storageBackend && storageBackend.lastMessage)
                root.setStatus(String(storageBackend.lastMessage), String(storageBackend.operationStatus) === "FAILED")
        }
        function onOperationFinished(success, message) {
            var finishedTitle = root.clean(storageBackend ? storageBackend.operationName : "", root.imagerOperationActive ? "IMAGE INSTALL" : "STORAGE TASK")
            root.setStatus(message, !success)
            root.showTaskResult(finishedTitle, success, String(message || (success ? "Task completed successfully." : "Task failed.")))
            if (root.imagerOperationActive) {
                root.imagerOperationActive = false
                root.setupPassword = ""
                root.setupWifiPassword = ""
            }
            if (success) root.syncDevices()
        }
        function onOptimizationChanged() { root.clampControl() }
        function onOptimizationFinished(success, message) {
            root.setStatus(message, !success)
            root.showTaskResult("STORAGE OPTIMIZATION SCAN", success, String(message || (success ? "Optimization scan completed." : "Optimization scan failed.")))
            if (success) root.selectRecommendedOptimizationPaths()
        }
    }

    Connections {
        target: fileBackend
        enabled: target !== null
        ignoreUnknownSignals: true
        function onDirectoryLoaded(path, items) {
            if (!root.manualPickerVisible) return
            root.manualPickerPath = String(path || "/")
            root.manualPickerItems = items || []
            root.manualPickerIndex = 0
        }
        function onOperationCompleted(actionId, path) {
            var wasSecurityTask = root.securityTaskActive
            var title = root.securityTaskName.length > 0 ? root.securityTaskName : String(actionId || "SECURITY TASK").toUpperCase()
            root.securityTaskActive = false
            root.setStatus(String(actionId).toUpperCase() + " completed: " + String(path), false)
            if (wasSecurityTask) {
                root.showTaskResult(title, true, "Completed successfully: " + String(path))
                root.securityPassword = ""
            }
        }
        function onOperationFailed(message) {
            var wasSecurityTask = root.securityTaskActive
            var title = root.securityTaskName.length > 0 ? root.securityTaskName : "STORAGE SECURITY"
            root.securityTaskActive = false
            root.setStatus(String(message), true)
            if (wasSecurityTask) {
                root.showTaskResult(title, false, String(message))
                root.securityPassword = ""
            }
        }
    }

    Rectangle {
        id: mainStorageSurface
        anchors.centerIn: parent
        width: root.fullScreenApp ? parent.width : Math.min(parent.width - 80, 1600)
        height: root.fullScreenApp ? parent.height : Math.min(parent.height - 60, 990)
        radius: root.fullScreenApp ? 0 : 12
        color: "#02060D"
        border.width: root.fullScreenApp ? 0 : 1
        border.color: "#25313C"
        clip: true

        ReferenceAppHeader {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 54
            appTitle: "Storage"
            primaryStatus: root.workActive() ? "Working" : "Ready"
            primaryTone: root.workActive() ? "warning" : "success"
            attention: root.statusIsError
            menuFocused: root.headerFocused || root.focusPane === 2
            onMenuRequested: root.close()
        }

        Rectangle {
            id: railPanel
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.top: header.bottom
            anchors.topMargin: 16
            anchors.bottom: footer.top
            anchors.bottomMargin: 16
            width: Math.max(235, Math.min(290, parent.width * 0.15))
            radius: 8
            color: "#06101AEE"
            border.width: 1
            border.color: "#25313C"

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                Text {
                    width: parent.width
                    text: "STORAGE TOOLS"
                    color: root.textWhite
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.0
                }
                Text {
                    width: parent.width
                    text: root.selectedFriendlyTitle()
                    color: root.manufacturerColor(root.selectedDevice())
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                }
                Rectangle { width: parent.width; height: 1; color: "#25313C" }

                Repeater {
                    model: root.categories
                    delegate: RailItem {
                        width: parent.width
                        titleText: modelData.title
                        detailText: modelData.detail
                        iconText: modelData.icon
                        activePage: root.categoryIndex === index
                        selected: root.focusPane === 0 && root.categoryIndex === index
                    }
                }
            }
        }

        Rectangle {
            id: contentPanel
            anchors.left: railPanel.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.top: header.bottom
            anchors.topMargin: 16
            anchors.bottom: footer.top
            anchors.bottomMargin: 16
            radius: 8
            color: "#06101AEE"
            border.width: 1
            border.color: root.focusPane === 1 ? root.focusBlue : "#25313C"
            clip: true

            Rectangle {
                id: selectedDeviceHero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                height: 122
                radius: 8
                color: "#081522"
                border.width: 1
                border.color: root.manufacturerColor(root.selectedDevice())

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 86
                    height: 86
                    radius: 18
                    color: root.manufacturerKey(root.selectedDevice()) === "neutronos" ? "#351018" : "#0A1A29"
                    border.width: 2
                    border.color: root.manufacturerColor(root.selectedDevice())

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 10
                        text: root.manufacturerMark(root.selectedDevice())
                        color: root.manufacturerColor(root.selectedDevice())
                        font.pixelSize: text.length > 4 ? 14 : (text.length > 2 ? 21 : 34)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 120
                    anchors.right: usageCard.left
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        width: parent.width
                        text: root.isSystemStorage(root.selectedDevice()) ? "SELECTED STORAGE  •  NEUTRONOS SYSTEM" : "SELECTED STORAGE"
                        color: root.manufacturerColor(root.selectedDevice())
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.0
                    }
                    Text {
                        width: parent.width
                        text: root.selectedFriendlyTitle()
                        color: root.textWhite
                        font.pixelSize: 24
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.selectedFriendlySubtitle()
                        color: root.mutedText
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.clean(root.selectedDevice().path, "NO DEVICE") + "  •  " + root.deviceMountText(root.displayUsageDevice(root.selectedDevice()))
                        color: "#B8C9D5"
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                }

                Rectangle {
                    id: usageCard
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(245, parent.width * 0.25)
                    height: 92
                    radius: 8
                    color: "#06101A"
                    border.width: 1
                    border.color: "#25313C"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 7
                        Row {
                            width: parent.width
                            spacing: 8
                            Text {
                                width: parent.width * 0.62
                                text: root.clean(root.displayUsageDevice(root.selectedDevice()).size, root.clean(root.selectedDevice().size, "—"))
                                color: root.textWhite
                                font.pixelSize: 18
                                font.bold: true
                            }
                            Text {
                                width: parent.width * 0.34
                                text: Number(root.displayUsageDevice(root.selectedDevice()).usagePercent || 0) + "% USED"
                                color: Number(root.displayUsageDevice(root.selectedDevice()).usagePercent || 0) >= 90 ? root.dangerRed : (Number(root.displayUsageDevice(root.selectedDevice()).usagePercent || 0) >= 75 ? root.warningGold : root.successGreen)
                                font.pixelSize: 12
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 12
                            radius: 6
                            color: "#02070D"
                            border.width: 1
                            border.color: "#25313C"
                            Rectangle {
                                height: parent.height
                                radius: 6
                                width: parent.width * Math.max(0, Math.min(100, Number(root.displayUsageDevice(root.selectedDevice()).usagePercent || 0))) / 100
                                color: Number(root.displayUsageDevice(root.selectedDevice()).usagePercent || 0) >= 90 ? root.dangerRed : (Number(root.displayUsageDevice(root.selectedDevice()).usagePercent || 0) >= 75 ? root.warningGold : root.manufacturerColor(root.selectedDevice()))
                            }
                        }
                        Text {
                            width: parent.width
                            text: root.clean(root.displayUsageDevice(root.selectedDevice()).available, "—") + " available  •  " + root.clean(root.displayUsageDevice(root.selectedDevice()).filesystem, "unformatted").toUpperCase()
                            color: root.mutedText
                            font.pixelSize: 11
                            font.bold: true
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Flickable {
                id: overviewFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: selectedDeviceHero.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                anchors.topMargin: 12
                visible: root.categoryIndex === 0
                clip: true
                contentWidth: width
                contentHeight: overviewColumn.height
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: overviewColumn
                    width: overviewFlick.width
                    spacing: 10
                    Rectangle {
                        width: parent.width; height: 170; radius: 10; color: "#0A1A2F"; border.width: 1; border.color: "#1D3958"
                        Row {
                            anchors.fill: parent; anchors.margins: 22; spacing: 18
                            Repeater {
                                model: [
                                    {"title":"CONNECTED", "value": String(root.flatDevices.length), "color":root.neutronCyan},
                                    {"title":"SYSTEM DISK", "value":root.clean(root.storageBackend ? root.storageBackend.systemDisk : "", "UNKNOWN"), "color":root.warningGold},
                                    {"title":"SMART", "value":root.storageBackend && root.storageBackend.smartctlAvailable ? "AVAILABLE" : "NOT INSTALLED", "color":root.storageBackend && root.storageBackend.smartctlAvailable ? root.successGreen : root.warningGold}
                                ]
                                delegate: Rectangle {
                                    width: (parent.width - 36) / 3; height: parent.height; radius: 18; color: "#071426"; border.width: 1; border.color: "#244A70"
                                    Column { anchors.centerIn: parent; width: parent.width - 24; spacing: 9
                                        Text { width: parent.width; text: modelData.title; color: root.mutedText; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                        Text { width: parent.width; text: modelData.value; color: modelData.color; font.pixelSize: 19; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle }
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        width:parent.width
                        height:Math.max(92, 54 + usageCategories.count * 42)
                        radius:22; color:"#0A1A2F"; border.width:1; border.color:"#1D3958"
                        Column {
                            anchors.fill:parent; anchors.margins:18; spacing:8
                            Text { text:"STORAGE BREAKDOWN  •  "+root.deviceTitle(root.selectedDevice()); color:root.textWhite; font.pixelSize:15; font.bold:true }
                            Repeater {
                                id:usageCategories
                                model:root.selectedUsageBreakdown.categories||[]
                                delegate:Row {
                                    required property var modelData
                                    width:parent.width; height:34; spacing:10
                                    Rectangle{width:10;height:10;radius:5;color:String(modelData.color||root.neutronCyan);anchors.verticalCenter:parent.verticalCenter}
                                    Text{width:parent.width*.5;text:String(modelData.name||"Other");color:root.textWhite;font.pixelSize:13}
                                    Text{width:parent.width*.22;text:String(modelData.formatted||"--");color:root.neutronCyan;font.pixelSize:13;horizontalAlignment:Text.AlignRight}
                                    Text{width:parent.width*.16;text:String(modelData.percent||0)+"%";color:root.mutedText;font.pixelSize:13;horizontalAlignment:Text.AlignRight}
                                }
                            }
                            Text { visible:usageCategories.count===0; text:"Run Refresh Inventory to calculate Movies, Music, Apps, Documents and other usage."; color:root.mutedText; font.pixelSize:13 }
                        }
                    }
                    SettingRow { width: parent.width; titleText: "REFRESH INVENTORY"; detailText: "Rescan all connected disks, partitions and mounts"; valueText: "X  REFRESH"; selected: root.focusPane === 1 && root.controlIndex === 0 }
                    SettingRow { width: parent.width; titleText: "SYSTEM OVERVIEW SLOT 1"; detailText: "Assign the selected mounted volume to the first storage card"; valueText: root.deviceTitle(root.selectedDevice()); selected: root.focusPane === 1 && root.controlIndex === 1 }
                    SettingRow { width: parent.width; titleText: "SYSTEM OVERVIEW SLOT 2"; detailText: "Assign the selected mounted volume to the second storage card"; valueText: root.deviceTitle(root.selectedDevice()); selected: root.focusPane === 1 && root.controlIndex === 2 }
                    SettingRow { width: parent.width; titleText: "OPTIMIZE STORAGE"; detailText: "Review old caches, temporary files, logs and large user files before deletion"; valueText: "X  OPEN"; selected: root.focusPane === 1 && root.controlIndex === 3 }
                }
            }

            Flickable {
                id: devicesFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: selectedDeviceHero.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                anchors.topMargin: 12
                visible: root.categoryIndex === 1
                clip: true; contentWidth: width; contentHeight: devicesColumn.height; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: devicesColumn
                    width: devicesFlick.width
                    spacing: 10
                    Text { width: parent.width; text: root.flatDevices.length > 0 ? "SELECT A DEVICE FOR DETAILS, MOUNT, UNMOUNT, OR SAFE EJECT" : "NO STORAGE DEVICES DETECTED"; color: root.neutronCyan; font.pixelSize: 15; font.bold: true; font.letterSpacing: 1.0 }
                    Repeater {
                        model: root.flatDevices
                        delegate: DeviceRow { width: parent.width; deviceData: modelData; selected: root.focusPane === 1 && root.controlIndex === index }
                    }
                }
            }

            Flickable {
                id: healthFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: selectedDeviceHero.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                anchors.topMargin: 12
                visible: root.categoryIndex === 2
                clip: true; contentWidth: width; contentHeight: healthColumn.height; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: healthColumn
                    width: healthFlick.width; spacing: 10
                    Rectangle {
                        width: parent.width; height: 235; radius: 10; color: "#0A1A2F"; border.width: 1; border.color: "#1D3958"
                        Column { anchors.fill: parent; anchors.margins: 24; spacing: 14
                            Text { width: parent.width; text: root.deviceTitle(root.selectedTopDisk()); color: root.textWhite; font.pixelSize: 24; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: (root.storageBackend && root.storageBackend.smartctlAvailable ? "SMART STATUS  " : "HEALTH STATUS  ") + root.clean(root.selectedTopDisk().smartStatus, "NOT CHECKED"); color: root.selectedTopDisk().smartStatus === "PASSED" ? root.successGreen : root.selectedTopDisk().smartStatus === "ATTENTION" ? root.dangerRed : root.warningGold; font.pixelSize: 19; font.bold: true }
                            Text { width: parent.width; text: "TEMPERATURE  " + (Number(root.selectedTopDisk().smartTemperature) >= 0 ? root.selectedTopDisk().smartTemperature + "°C" : "—") + "     POWER ON  " + root.clean(root.selectedTopDisk().smartPowerOnHours, "—") + " h"; color: Number(root.selectedTopDisk().smartTemperature) >= 0 ? root.successGreen : root.mutedText; font.pixelSize: 15; font.bold: true }
                            Text { width: parent.width; text: root.storageBackend && root.storageBackend.smartctlAvailable ? "NeutronOS reads available temperature telemetry automatically. Run the full SMART health check for status and lifetime data." : "SMART is unavailable for this system, so NeutronOS will run a basic device and mounted-filesystem readiness check instead."; color: root.mutedText; font.pixelSize: 14; wrapMode: Text.WordWrap }
                        }
                    }
                    SettingRow { width: parent.width; titleText: root.storageBackend && root.storageBackend.smartctlAvailable ? "RUN SMART HEALTH CHECK" : "RUN HEALTH CHECK"; detailText: root.storageBackend && root.storageBackend.smartctlAvailable ? "Read drive health, temperature and lifetime data from the physical disk" : "Check device availability and mounted-filesystem readiness"; valueText: "X  CHECK"; selected: root.focusPane === 1 && root.controlIndex === 0 }
                    SettingRow { width: parent.width; titleText: "REFRESH DEVICES"; detailText: "Rescan after connecting or removing a storage device"; valueText: "X  REFRESH"; selected: root.focusPane === 1 && root.controlIndex === 1 }
                }
            }

            Flickable {
                id: formatFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: selectedDeviceHero.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                anchors.topMargin: 12
                visible: root.categoryIndex === 3
                clip: true; contentWidth: width; contentHeight: formatColumn.height; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: formatColumn
                    width: formatFlick.width; spacing: 10
                    Rectangle {
                        width: parent.width; height: 170; radius: 10; color: "#3A1720"; border.width: 2; border.color: root.dangerRed
                        Column { anchors.fill: parent; anchors.margins: 24; spacing: 10
                            Text { width: parent.width; text: "DESTRUCTIVE OPERATION"; color: root.dangerRed; font.pixelSize: 21; font.bold: true; font.letterSpacing: 1.1 }
                            Text { width: parent.width; text: "Formatting permanently erases the selected device. NeutronOS blocks the active system disk and requires a second X press before execution."; color: "#FFD5D9"; font.pixelSize: 14; wrapMode: Text.WordWrap }
                            Text { width: parent.width; text: "TARGET  " + root.clean(root.selectedDevice().path, "NONE"); color: root.textWhite; font.pixelSize: 16; font.bold: true; elide: Text.ElideMiddle }
                        }
                    }
                    SettingRow { width: parent.width; titleText: "FILESYSTEM"; detailText: "Left/Right selects the filesystem format"; valueText: root.formatFilesystem.toUpperCase(); selected: root.focusPane === 1 && root.controlIndex === 0 }
                    SettingRow { width: parent.width; titleText: "VOLUME LABEL"; detailText: "Open the virtual keyboard to name the new volume"; valueText: root.volumeLabel; selected: root.focusPane === 1 && root.controlIndex === 1 }
                    SettingRow { width: parent.width; titleText: root.formatArmed ? "PRESS X AGAIN TO FORMAT" : "FORMAT SELECTED DEVICE"; detailText: root.formatArmed ? "This is the final confirmation" : "Unmount, erase and create the selected filesystem"; valueText: root.formatArmed ? "ARMED" : "X  ARM"; valueColor: root.dangerRed; danger: true; selected: root.focusPane === 1 && root.controlIndex === 2 }
                    SettingRow { width: parent.width; titleText: "DISARM"; detailText: "Cancel the pending format confirmation"; valueText: "X  CANCEL"; selected: root.focusPane === 1 && root.controlIndex === 3 }
                }
            }

            Flickable {
                id: securityFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: selectedDeviceHero.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                anchors.topMargin: 12
                visible: root.categoryIndex === 4
                clip: true; contentWidth: width; contentHeight: securityColumn.height; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: securityColumn
                    width: securityFlick.width; spacing: 10
                    Rectangle {
                        width: parent.width; height: 190; radius: 10; color: "#0A1A2F"; border.width: 2; border.color: root.purple
                        Column { anchors.fill: parent; anchors.margins: 24; spacing: 10
                            Text { width: parent.width; text: root.securityRequestedMode === "encrypt" ? "ENCRYPT STORAGE DATA" : root.securityRequestedMode === "decrypt" ? "DECRYPT STORAGE DATA" : "STORAGE ENCRYPTION"; color: root.purple; font.pixelSize: 22; font.bold: true; font.letterSpacing: 1.1 }
                            Text { width: parent.width; text: root.securityRequestedMode === "encrypt" ? "Create an authenticated encrypted copy using the existing File Manager security backend. The source is preserved and passwords are never stored." : root.securityRequestedMode === "decrypt" ? "Restore protected storage data using the existing File Manager security backend. The encrypted source remains untouched unless you remove it later." : "Encrypt or decrypt a file or archive using the File Manager security backend. The source is never removed automatically, passwords are never stored, and every operation must be armed twice."; color: root.textWhite; font.pixelSize: 14; wrapMode: Text.WordWrap }
                            Text { width: parent.width; text: "Folders are packed into an authenticated container automatically and restored during decryption."; color: root.warningGold; font.pixelSize: 13; font.bold: true; wrapMode: Text.WordWrap }
                        }
                    }
                    SettingRow { width: parent.width; titleText: "SOURCE PATH"; detailText: "File or encrypted archive to process"; valueText: root.clean(root.securitySourcePath, "X  ENTER PATH"); selected: root.focusPane === 1 && root.controlIndex === 0 }
                    SettingRow { width: parent.width; titleText: "DESTINATION PATH"; detailText: "Leave empty to use the recommended output name"; valueText: root.clean(root.securityDestinationPath, "AUTO"); selected: root.focusPane === 1 && root.controlIndex === 1 }
                    SettingRow { width: parent.width; titleText: "ENCRYPTION METHOD"; detailText: "Left/Right changes the authenticated encryption format"; valueText: root.securityMethod.toUpperCase(); selected: root.focusPane === 1 && root.controlIndex === 2 }
                    SettingRow { width: parent.width; titleText: "PASSWORD"; detailText: "Minimum eight characters; never written to disk"; valueText: root.securityPassword.length > 0 ? "••••••••••" : "X  ENTER"; selected: root.focusPane === 1 && root.controlIndex === 3 }
                    SettingRow { width: parent.width; titleText: root.securityArmedAction === "encrypt" ? "PRESS X AGAIN TO ENCRYPT" : "ENCRYPT"; detailText: "Creates an encrypted copy and preserves the original"; valueText: root.securityArmedAction === "encrypt" ? "ARMED" : "X  ARM"; valueColor: root.warningGold; danger: root.securityArmedAction === "encrypt"; selected: root.focusPane === 1 && root.controlIndex === 4 }
                    SettingRow { width: parent.width; titleText: root.securityArmedAction === "decrypt" ? "PRESS X AGAIN TO DECRYPT" : "DECRYPT"; detailText: "Restores an encrypted file to the selected destination"; valueText: root.securityArmedAction === "decrypt" ? "ARMED" : "X  ARM"; valueColor: root.warningGold; danger: root.securityArmedAction === "decrypt"; selected: root.focusPane === 1 && root.controlIndex === 5 }
                    SettingRow { width: parent.width; titleText: "CLEAR SECURITY FIELDS"; detailText: "Forget the entered paths and password immediately"; valueText: "X  CLEAR"; selected: root.focusPane === 1 && root.controlIndex === 6 }
                }
            }

            Flickable {
                id: optimizeFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: selectedDeviceHero.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                anchors.topMargin: 12
                visible: root.categoryIndex === 5
                clip: true; contentWidth: width; contentHeight: optimizeColumn.height; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: optimizeColumn
                    width: optimizeFlick.width; spacing: 10
                    Rectangle {
                        width: parent.width; height: 208; radius: 10; color: "#0A1A2F"; border.width: 2; border.color: root.successGreen
                        Column { anchors.fill: parent; anchors.margins: 24; spacing: 10
                            Text { width: parent.width; text: "REVIEW BEFORE DELETE"; color: root.successGreen; font.pixelSize: 22; font.bold: true; font.letterSpacing: 1.1 }
                            Text { width: parent.width; text: "Storage Optimize scans approved locations for old caches, temporary files, logs, crash data, unfinished downloads, backups and large old user files. It never deletes during a scan."; color: root.textWhite; font.pixelSize: 14; wrapMode: Text.WordWrap }
                            Text { width: parent.width; text: root.optimizationScanning ? "SCANNING…" : root.clean(root.storageBackend ? root.storageBackend.optimizationSummary : "", "Run a scan to build a review list."); color: root.optimizationScanning ? root.warningGold : root.neutronCyan; font.pixelSize: 14; font.bold: true; wrapMode: Text.WordWrap }
                            Text { width: parent.width; text: root.optimizationSelectedPaths.length + " SELECTED  •  " + root.humanBytes(root.selectedOptimizationBytes()); color: root.mutedText; font.pixelSize: 13; font.bold: true }
                        }
                    }
                    SettingRow { width: parent.width; titleText: "SCAN LOCATION"; detailText: "Home, mounted media, /mnt, /tmp and approved cache locations only"; valueText: root.clean(root.optimizationRootPath, "X  ENTER"); selected: root.focusPane === 1 && root.controlIndex === 0 }
                    SettingRow { width: parent.width; titleText: "OLDER THAN"; detailText: "Left/Right changes the minimum last-used age"; valueText: root.optimizationAgeDays + " DAYS"; selected: root.focusPane === 1 && root.controlIndex === 1 }
                    SettingRow { width: parent.width; titleText: root.optimizationScanning ? "SCANNING STORAGE" : "SCAN WITHOUT DELETING"; detailText: "Build a detailed review list with purpose, size and last-used information"; valueText: root.optimizationScanning ? "WORKING" : "X  SCAN"; disabled: root.optimizationScanning; selected: root.focusPane === 1 && root.controlIndex === 2 }
                    Repeater {
                        model: root.optimizationCandidates
                        delegate: OptimizationRow {
                            width: parent.width
                            candidateData: modelData
                            marked: root.containsPath(root.optimizationSelectedPaths, modelData.path)
                            selected: root.focusPane === 1 && root.controlIndex === index + 3
                        }
                    }
                    SettingRow {
                        width: parent.width
                        titleText: root.optimizationDeleteArmed ? "PRESS X AGAIN TO PERMANENTLY DELETE" : "DELETE SELECTED REVIEW ITEMS"
                        detailText: root.optimizationDeleteArmed ? "Final confirmation — only the currently reviewed writable files are allowed" : "Requires two presses and exact backend confirmation; protected paths are refused"
                        valueText: root.optimizationDeleteArmed ? "ARMED" : (root.optimizationSelectedPaths.length + " FILES")
                        valueColor: root.dangerRed
                        danger: true
                        disabled: root.optimizationSelectedPaths.length === 0
                        selected: root.focusPane === 1 && root.controlIndex === root.optimizationCandidates.length + 3
                    }
                    SettingRow {
                        width: parent.width
                        titleText: "SELECT RECOMMENDED"
                        detailText: "Select only old writable cache, temporary and diagnostic items; user media remains unselected"
                        valueText: "X  SELECT"
                        selected: root.focusPane === 1 && root.controlIndex === root.optimizationCandidates.length + 4
                    }
                }
            }

            Flickable {
                id: backupFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: selectedDeviceHero.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                anchors.topMargin: 12
                visible: root.categoryIndex === 6
                clip: true; contentWidth: width; contentHeight: backupColumn.height; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: backupColumn
                    width: backupFlick.width; spacing: 10
                    Rectangle {
                        width: parent.width; height: 220; radius: 10; color: "#0A1A2F"; border.width: 2; border.color: root.warningGold
                        Column { anchors.fill: parent; anchors.margins: 24; spacing: 12
                            Text { width: parent.width; text: root.imageFlashTab === 0 ? "STORAGE IMAGE FLASHER" : "RASPBERRY PI IMAGER"; color: root.imageFlashTab === 0 ? root.warningGold : root.successGreen; font.pixelSize: 24; font.bold: true; font.letterSpacing: 1.1 }
                            Text { width: parent.width; text: "TARGET  " + (root.clean(root.selectedTopDisk().path).length > 0 ? (root.selectedFriendlyTitle() + "  •  " + root.clean(root.selectedTopDisk().path)) : "SELECT A WHOLE NON-SYSTEM DISK"); color: root.textWhite; font.pixelSize: 16; font.bold: true; elide: Text.ElideMiddle }
                            Text { width: parent.width; text: root.imageFlashTab === 0 ? ("IMAGE  " + root.clean(root.flashImagePath, "SELECT AN .IMG, .ISO, .XZ, .GZ, OR .ZIP IMAGE")) : "Recommended Install downloads an operating system, verifies it, writes its original partition table/filesystems, verifies the written image, then applies supported first-boot settings."; color: root.imageFlashTab === 0 ? root.textWhite : root.mutedText; font.pixelSize: 14; font.bold: root.imageFlashTab === 0; wrapMode: Text.WordWrap; elide: root.imageFlashTab === 0 ? Text.ElideMiddle : Text.ElideNone }
                            Text { width: parent.width; text: "The active boot/root disk is always blocked. Image flashing does not pre-format the target because the image supplies its own partition table and filesystems."; color: root.mutedText; font.pixelSize: 13; wrapMode: Text.WordWrap }
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 72; radius: 8; color: "#071426"; border.width: root.focusPane === 1 && root.controlIndex === 0 ? 3 : 1; border.color: root.focusPane === 1 && root.controlIndex === 0 ? root.focusBlue : "#315A80"
                        Row {
                            anchors.fill: parent; anchors.margins: 8; spacing: 8
                            Repeater {
                                model: ["LOCAL IMAGE", "RASPBERRY PI IMAGER"]
                                Rectangle {
                                    required property string modelData
                                    required property int index
                                    width: (parent.width - 8) / 2; height: parent.height; radius: 7
                                    color: root.imageFlashTab === index ? (index === 1 ? "#17482E" : "#17365D") : "#0A1A2F"
                                    border.width: root.imageFlashTab === index ? 2 : 1
                                    border.color: root.imageFlashTab === index ? (index === 1 ? root.successGreen : root.focusBlue) : "#1D3958"
                                    Text { anchors.centerIn: parent; text: modelData; color: root.imageFlashTab === index ? root.textWhite : root.mutedText; font.pixelSize: 16; font.bold: true }
                                }
                            }
                        }
                    }
                    SettingRow { visible: root.imageFlashTab === 0; width: parent.width; titleText: "IMAGE FILE"; detailText: "Browse a local .img, .iso, .xz, .gz, or .zip image"; valueText: root.clean(root.flashImagePath, "X  SELECT"); selected: root.focusPane === 1 && root.controlIndex === 1 }
                    SettingRow { visible: root.imageFlashTab === 0; width: parent.width; titleText: root.flashArmed ? "PRESS X AGAIN TO START FLASH" : "FLASH IMAGE"; detailText: root.flashArmed ? "Final confirmation — the target disk will be completely overwritten" : "Write and verify the selected image on the target disk"; valueText: root.flashArmed ? "ARMED" : "X  ARM"; valueColor: root.dangerRed; danger: true; selected: root.focusPane === 1 && root.controlIndex === 2 }
                    SettingRow { visible: root.imageFlashTab === 0; width: parent.width; titleText: root.cloneArmed ? "PRESS X AGAIN TO START CLONE" : "CREATE BOOT BACKUP"; detailText: root.cloneArmed ? "Final confirmation — target will be completely overwritten" : "Clone the active system disk to the selected target"; valueText: root.cloneArmed ? "ARMED" : "X  ARM"; valueColor: root.dangerRed; danger: true; selected: root.focusPane === 1 && root.controlIndex === 3 }
                    SettingRow { visible: root.imageFlashTab === 0; width: parent.width; titleText: "DISARM"; detailText: "Cancel the pending image-flash or boot-backup confirmation"; valueText: "X  CANCEL"; selected: root.focusPane === 1 && root.controlIndex === 4 }
                    SettingRow { visible: root.imageFlashTab === 1; width: parent.width; titleText: "OPEN RASPBERRY PI IMAGER"; detailText: "Choose Recommended Install or Manual Install"; valueText: "X  OPEN"; valueColor: root.successGreen; selected: root.focusPane === 1 && root.controlIndex === 1 }
                    SettingRow { visible: root.imageFlashTab === 1; width: parent.width; titleText: "REFRESH OPERATING SYSTEMS"; detailText: root.clean(root.storageBackend ? root.storageBackend.imagerCatalogStatus : "", "Load the official Raspberry Pi Imager catalog"); valueText: root.imagerCatalogLoading ? "LOADING…" : (root.imagerCatalog.length + " READY"); valueColor: root.neutronCyan; selected: root.focusPane === 1 && root.controlIndex === 2 }
                }
            }

            Flickable {
                id: detailsFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: selectedDeviceHero.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 16
                anchors.topMargin: 12
                visible: root.categoryIndex === 7
                clip: true; contentWidth: width; contentHeight: detailsColumn.height; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: detailsColumn
                    width: detailsFlick.width; spacing: 10
                    Text { width: parent.width; text: root.deviceTitle(root.selectedDevice()); color: root.textWhite; font.pixelSize: 27; font.bold: true; elide: Text.ElideRight }
                    Rectangle {
                        width: parent.width; height: 88; radius: 8; color: "#0A1A2F"; border.width: 1; border.color: "#1D3958"
                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 18; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; height: 22; radius: 11; color: "#06101F"; border.width: 1; border.color: "#315A80"
                            Rectangle { height: parent.height; radius: parent.radius; width: parent.width * Math.max(0, Math.min(100, Number(root.selectedDevice().usagePercent || 0))) / 100; color: Number(root.selectedDevice().usagePercent || 0) >= 90 ? root.dangerRed : (Number(root.selectedDevice().usagePercent || 0) >= 75 ? root.warningGold : root.neutronCyan) }
                        }
                        Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -27; text: Number(root.selectedDevice().usagePercent || 0) + "% USED  •  " + root.clean(root.selectedDevice().used, "—") + " USED  •  " + root.clean(root.selectedDevice().available, "—") + " AVAILABLE"; color: root.textWhite; font.pixelSize: 14; font.bold: true }
                    }
                    Repeater {
                        model: [
                            {"title":"DEVICE PATH", "value":root.clean(root.selectedDevice().path, "—")},
                            {"title":"MODEL", "value":root.clean(root.selectedDevice().model, "—")},
                            {"title":"VENDOR", "value":root.clean(root.selectedDevice().vendor, "—")},
                            {"title":"SERIAL", "value":root.clean(root.selectedDevice().serial, "—")},
                            {"title":"TYPE / TRANSPORT", "value":root.clean(root.selectedDevice().type, "—").toUpperCase() + "  /  " + root.clean(root.selectedDevice().transport, "—").toUpperCase()},
                            {"title":"CAPACITY", "value":root.clean(root.selectedDevice().size, "—")},
                            {"title":"USED / AVAILABLE", "value":root.clean(root.selectedDevice().used, "—") + "  /  " + root.clean(root.selectedDevice().available, "—")},
                            {"title":"FILESYSTEM", "value":root.clean(root.selectedDevice().filesystem, "—").toUpperCase()},
                            {"title":"LABEL", "value":root.clean(root.selectedDevice().label, "—")},
                            {"title":"UUID", "value":root.clean(root.selectedDevice().uuid, "—")},
                            {"title":"MOUNT POINTS", "value":root.deviceMountText(root.selectedDevice())},
                            {"title":"STATUS", "value":root.selectedDevice().system ? "PROTECTED SYSTEM DEVICE" : (root.selectedDevice().readOnly ? "READ ONLY" : "AVAILABLE")}
                        ]
                        delegate: SettingRow { width: parent.width; titleText: modelData.title; detailText: ""; valueText: modelData.value; selected: false }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 7
                anchors.top: parent.top
                anchors.topMargin: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                width: 7
                radius: 4
                visible: root.currentFlick() && root.currentFlick().contentHeight > root.currentFlick().height
                color: "#102943"
                Rectangle {
                    width: parent.width
                    radius: 4
                    color: root.focusBlue
                    height: root.currentFlick() ? Math.max(45, parent.height * root.currentFlick().height / Math.max(root.currentFlick().height, root.currentFlick().contentHeight)) : parent.height
                    y: root.currentFlick() ? (parent.height - height) * root.currentFlick().visibleArea.yPosition / Math.max(0.001, 1.0 - root.currentFlick().visibleArea.heightRatio) : 0
                }
            }
        }

        ReferenceAppFooter {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 72
            controllerBackend: root.controllerBackend
            hintText: ""
        }

        Rectangle {
            id: statusToast
            visible: root.statusMessage.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: footer.top
            anchors.bottomMargin: 8
            width: Math.min(parent.width - 80, Math.max(520, statusToastText.implicitWidth + 48))
            height: 36
            radius: 18
            color: root.statusIsError ? "#2A1015" : "#081522"
            border.width: 1
            border.color: root.statusIsError ? root.dangerRed : "#315A80"
            z: 40

            Text {
                id: statusToastText
                anchors.centerIn: parent
                width: parent.width - 28
                text: root.statusMessage
                color: root.statusIsError ? "#FF8790" : "#C8D5DF"
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.deviceActionVisible
        color: "#E602060D"
        z: 1250
        Rectangle {
            anchors.centerIn: parent
            width: 1100
            height: 520
            radius: 34
            color: "#071426"
            border.width: 3
            border.color: root.deviceActionArmed.length > 0 ? root.dangerRed : root.neutronCyan
            Column {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 20
                Text { width: parent.width; text: "DEVICE ACTIONS"; color: root.textWhite; font.pixelSize: 31; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: root.deviceTitle(root.selectedDevice()) + "  •  " + root.clean(root.selectedDevice().path, ""); color: root.mutedText; font.pixelSize: 15; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle }
                Row {
                    width: parent.width
                    height: 190
                    spacing: 12
                    Repeater {
                        model: [
                            {title:"DETAILS", detail:"Inspect device information"},
                            {title:root.clean(root.selectedDevice().mountText).length > 0 ? (root.deviceActionArmed === "unmount" ? "PRESS X AGAIN" : "UNMOUNT") : "MOUNT", detail:root.clean(root.selectedDevice().mountText).length > 0 ? "Flush writes and remove the volume safely" : "Mount at /mnt/" + root.mountName},
                            {title:"MOUNT NAME", detail:root.mountName},
                            {title:root.deviceActionArmed === "eject" ? "PRESS X AGAIN" : "SAFE EJECT", detail:"Unmount and power off removable hardware"}
                        ]
                        Rectangle {
                            required property int index
                            required property var modelData
                            width: (parent.width - 36) / 4
                            height: parent.height
                            radius: 22
                            color: index === root.deviceActionIndex ? (root.deviceActionArmed.length > 0 ? "#4A1721" : "#17365D") : "#0A1A2F"
                            border.width: index === root.deviceActionIndex ? 3 : 1
                            border.color: index === root.deviceActionIndex ? (root.deviceActionArmed.length > 0 ? root.dangerRed : root.focusBlue) : "#1D3958"
                            Column { anchors.fill: parent; anchors.margins: 16; spacing: 12
                                Text { width: parent.width; text: modelData.title; color: index === root.deviceActionIndex ? root.neutronCyan : root.textWhite; font.pixelSize: 17; font.bold: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                                Text { width: parent.width; text: modelData.detail; color: root.mutedText; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                            }
                        }
                    }
                }
                Text { width: parent.width; text: "←/→ CHOOSE   X SELECT   O CANCEL"; color: root.mutedText; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.imagerModeVisible
        color: "#E802060D"
        z: 1260
        Rectangle {
            anchors.centerIn: parent
            width: 980
            height: 430
            radius: 34
            color: root.panelColor
            border.width: 3
            border.color: root.successGreen
            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 24
                Text { width: parent.width; text: "RASPBERRY PI IMAGER"; color: root.successGreen; font.pixelSize: 31; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: "Choose a recommended online image or select a local image manually."; color: root.mutedText; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                Row {
                    width: parent.width
                    height: 190
                    spacing: 18
                    Repeater {
                        model: [
                            {title:"RECOMMENDED INSTALL", detail:"Browse NeutronOS, Raspberry Pi OS Lite 64-bit, and compatible operating systems"},
                            {title:"MANUAL INSTALL", detail:"Open a controller-first file browser and select a local image"}
                        ]
                        Rectangle {
                            required property int index
                            required property var modelData
                            width: (parent.width - 18) / 2
                            height: parent.height
                            radius: 24
                            color: root.imagerModeIndex === index ? "#17482E" : "#0A1A2F"
                            border.width: root.imagerModeIndex === index ? 3 : 1
                            border.color: root.imagerModeIndex === index ? root.successGreen : "#1D3958"
                            Column { anchors.fill: parent; anchors.margins: 20; spacing: 14
                                Text { width: parent.width; text: modelData.title; color: root.imagerModeIndex === index ? root.successGreen : root.textWhite; font.pixelSize: 20; font.bold: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                                Text { width: parent.width; text: modelData.detail; color: root.mutedText; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                            }
                        }
                    }
                }
                Text { width: parent.width; text: "←/→ CHOOSE   X CONTINUE   O CANCEL"; color: root.mutedText; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.imagerCatalogVisible
        color: "#F002060D"
        z: 1261
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 1380)
            height: Math.min(parent.height - 70, 940)
            radius: 34
            color: root.panelColor
            border.width: 3
            border.color: root.successGreen
            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14
                Text { width: parent.width; text: "RECOMMENDED OPERATING SYSTEMS"; color: root.successGreen; font.pixelSize: 29; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: root.imagerCatalogLoading ? "Loading the official Raspberry Pi Imager catalog…" : root.clean(root.storageBackend ? root.storageBackend.imagerCatalogStatus : "", root.imagerCatalog.length + " operating systems ready"); color: root.imagerCatalogLoading ? root.warningGold : root.mutedText; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                ListView {
                    id: imagerCatalogList
                    width: parent.width
                    height: parent.height - 120
                    model: root.imagerCatalog
                    currentIndex: root.imagerCatalogIndex
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: 92
                        radius: 20
                        color: index === root.imagerCatalogIndex ? (index === 0 ? "#17482E" : "#17365D") : "#0A1A2F"
                        border.width: index === root.imagerCatalogIndex ? 3 : 1
                        border.color: index === 0 ? root.successGreen : (index === root.imagerCatalogIndex ? root.focusBlue : "#1D3958")
                        Row {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 18
                            Rectangle {
                                width: 58; height: 58; radius: 18
                                color: index === 0 ? "#103D27" : "#102943"
                                border.width: 1
                                border.color: index === 0 ? root.successGreen : root.neutronCyan
                                Text { anchors.centerIn: parent; text: index === 0 ? "N" : "OS"; color: index === 0 ? root.successGreen : root.neutronCyan; font.pixelSize: 19; font.bold: true }
                            }
                            Column {
                                width: parent.width - 300
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5
                                Text { width: parent.width; text: String(modelData.name || "Operating System"); color: index === 0 ? root.successGreen : root.textWhite; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: String(modelData.description || ""); color: root.mutedText; font.pixelSize: 13; elide: Text.ElideRight }
                                Text { width: parent.width; text: index === 0 ? String(modelData.website || "https://github.com/OGDrNeutron/NeutronOS") : String(modelData.group || modelData.source || ""); color: root.neutronCyan; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight }
                            }
                            Column {
                                width: 190
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5
                                Text { width: parent.width; text: modelData.available ? (Number(modelData.downloadBytes || 0) > 0 ? root.humanBytes(modelData.downloadBytes) : "READY") : "NO IMAGE RELEASE"; color: modelData.available ? root.successGreen : root.dangerRed; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight }
                                Text { width: parent.width; text: String(modelData.releaseDate || ""); color: root.mutedText; font.pixelSize: 12; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                }
                Text { width: parent.width; text: "↑/↓ SELECT   X CONTINUE   TRIANGLE REFRESH   O BACK"; color: root.mutedText; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.manualPickerVisible
        color: "#F002060D"
        z: 1262
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 180, 1120)
            height: Math.min(parent.height - 150, 760)
            radius: 32
            color: root.panelColor
            border.width: 3
            border.color: root.neutronCyan
            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14
                Text { width: parent.width; text: root.manualPickerPurpose === "rawflash" ? "SELECT IMAGE TO FLASH" : "SELECT LOCAL IMAGE"; color: root.neutronCyan; font.pixelSize: 28; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: root.manualPickerPath; color: root.mutedText; font.pixelSize: 14; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter }
                ListView {
                    id: manualImageList
                    width: parent.width
                    height: parent.height - 105
                    model: root.manualPickerItems
                    currentIndex: root.manualPickerIndex
                    clip: true
                    spacing: 7
                    boundsBehavior: Flickable.StopAtBounds
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: 70
                        radius: 17
                        color: index === root.manualPickerIndex ? "#17365D" : "#0A1A2F"
                        border.width: index === root.manualPickerIndex ? 3 : 1
                        border.color: index === root.manualPickerIndex ? root.focusBlue : "#1D3958"
                        Row { anchors.fill: parent; anchors.margins: 14; spacing: 14
                            Text { width: 45; text: modelData.isDirectory === true || modelData.isDir === true ? "▣" : "IMG"; color: modelData.isDirectory === true || modelData.isDir === true ? root.warningGold : (root.manualImageSupported(modelData.path) ? root.successGreen : root.mutedText); font.pixelSize: 17; font.bold: true; verticalAlignment: Text.AlignVCenter }
                            Column { width: parent.width - 170; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                Text { width: parent.width; text: String(modelData.name || ""); color: root.textWhite; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: String(modelData.sizeText || modelData.path || ""); color: root.mutedText; font.pixelSize: 12; elide: Text.ElideRight }
                            }
                        }
                    }
                }
                Text { width: parent.width; text: "↑/↓ SELECT   X OPEN/CHOOSE   SQUARE PARENT   O BACK"; color: root.mutedText; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.imagerSetupVisible
        color: "#F202060D"
        z: 1263
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 1320)
            height: Math.min(parent.height - 60, 980)
            radius: 34
            color: root.panelColor
            border.width: 3
            border.color: root.imagerSetupArmed ? root.dangerRed : root.successGreen
            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12
                Text { width: parent.width; text: "IMAGE SETUP"; color: root.successGreen; font.pixelSize: 29; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: String(root.selectedImagerOs.name || "Manual image") + "  →  " + root.clean(root.selectedTopDisk().path, "NO TARGET SELECTED"); color: root.textWhite; font.pixelSize: 15; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle }
                Flickable {
                    width: parent.width
                    height: parent.height - 105
                    contentWidth: width
                    contentHeight: imagerSetupColumn.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: imagerSetupColumn
                        width: parent.width
                        spacing: 8
                        SettingRow { width: parent.width; titleText: "HOSTNAME"; detailText: "Network name for the installed Pi"; valueText: root.setupHostname; selected: root.imagerSetupIndex === 0 }
                        SettingRow { width: parent.width; titleText: "USERNAME"; detailText: "First local user account"; valueText: root.setupUsername; selected: root.imagerSetupIndex === 1 }
                        SettingRow { width: parent.width; titleText: "PASSWORD"; detailText: "Stored only as a salted SHA-512 password hash in the image"; valueText: root.setupPassword.length > 0 ? "••••••••" : "X  ENTER"; selected: root.imagerSetupIndex === 2 }
                        SettingRow { width: parent.width; titleText: "SSH"; detailText: "Enable remote shell access on first boot"; valueText: root.setupSsh ? "ON" : "OFF"; valueColor: root.setupSsh ? root.successGreen : root.mutedText; selected: root.imagerSetupIndex === 3 }
                        SettingRow { width: parent.width; titleText: "WI-FI"; detailText: "Create a NetworkManager connection in the flashed image"; valueText: root.setupWifi ? "ON" : "OFF"; valueColor: root.setupWifi ? root.successGreen : root.mutedText; selected: root.imagerSetupIndex === 4 }
                        SettingRow { width: parent.width; titleText: "WI-FI SSID"; detailText: "Wireless network name"; valueText: root.clean(root.setupSsid, "X  ENTER"); disabled: !root.setupWifi; selected: root.imagerSetupIndex === 5 }
                        SettingRow { width: parent.width; titleText: "WI-FI PASSWORD"; detailText: "Minimum eight characters"; valueText: root.setupWifiPassword.length > 0 ? "••••••••" : "X  ENTER"; disabled: !root.setupWifi; selected: root.imagerSetupIndex === 6 }
                        SettingRow { width: parent.width; titleText: "WI-FI COUNTRY"; detailText: "Two-letter regulatory code"; valueText: root.setupWifiCountry; disabled: !root.setupWifi; selected: root.imagerSetupIndex === 7 }
                        SettingRow { width: parent.width; titleText: "TIME ZONE"; detailText: "Example: America/New_York"; valueText: root.setupTimezone; selected: root.imagerSetupIndex === 8 }
                        SettingRow { width: parent.width; titleText: "LOCALE"; detailText: "System language and character encoding"; valueText: root.setupLocale; selected: root.imagerSetupIndex === 9 }
                        SettingRow { width: parent.width; titleText: "KEYBOARD"; detailText: "Keyboard layout code"; valueText: root.setupKeyboard; selected: root.imagerSetupIndex === 10 }
                        SettingRow { width: parent.width; titleText: root.imagerSetupArmed ? "PRESS X AGAIN TO INSTALL" : "CONFIRM AND INSTALL"; detailText: root.imagerSetupArmed ? "Final confirmation — the selected target will be completely overwritten" : "Download, verify, write, verify again, and apply supported setup options"; valueText: root.imagerSetupArmed ? "ARMED" : "X  CONFIRM"; valueColor: root.imagerSetupArmed ? root.dangerRed : root.successGreen; danger: root.imagerSetupArmed; selected: root.imagerSetupIndex === 11 }
                    }
                }
                Text { width: parent.width; text: "↑/↓ NAVIGATE   X EDIT/TOGGLE/CONFIRM   O BACK"; color: root.mutedText; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.imagerResultVisible
        color: "#F202060D"
        z: 1270
        Rectangle {
            anchors.centerIn: parent
            width: 960
            height: 430
            radius: 34
            color: root.panelColor
            border.width: 4
            border.color: root.imagerResultSuccess ? root.successGreen : root.dangerRed
            Column {
                anchors.fill: parent
                anchors.margins: 38
                spacing: 24
                Text { width: parent.width; text: root.imagerResultSuccess ? "IMAGE INSTALL COMPLETE" : "IMAGE INSTALL ERROR"; color: root.imagerResultSuccess ? root.successGreen : root.dangerRed; font.pixelSize: 31; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; height: 220; text: root.imagerResultMessage; color: root.textWhite; font.pixelSize: 17; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                Text { width: parent.width; text: "X OR O TO CLOSE"; color: root.mutedText; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.workActive()
        color: "#D902060D"
        z: 1200

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 120, 980)
            height: operationBusy ? 600 : 430
            radius: 12
            color: "#07111A"
            border.width: 1
            border.color: root.warningGold

            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 16

                Text {
                    width: parent.width
                    text: root.workTitle()
                    color: root.textWhite
                    font.pixelSize: 30
                    font.bold: true
                    font.letterSpacing: 1.0
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.isSystemStorage(root.selectedDevice()) ? "NeutronOS Boot Storage" : root.selectedFriendlyTitle()
                    color: root.manufacturerColor(root.selectedDevice())
                    font.pixelSize: 15
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                Rectangle {
                    width: parent.width
                    height: 28
                    radius: 14
                    color: "#030810"
                    border.width: 1
                    border.color: "#315A80"
                    clip: true
                    Rectangle {
                        height: parent.height
                        width: parent.width * root.workProgress() / 100
                        radius: 14
                        color: root.workProgress() >= 100 ? root.successGreen : root.warningGold
                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    width: parent.width
                    text: root.workProgress() + "%"
                    color: root.workProgress() >= 100 ? root.successGreen : root.neutronCyan
                    font.pixelSize: 24
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                // The current backend stage sits directly below the progress bar/percent,
                // so the user can see exactly what the task is doing rather than stare at
                // a decorative animation and wonder whether civilization has stalled.
                Text {
                    width: parent.width
                    text: root.workStage()
                    color: root.textWhite
                    font.pixelSize: 16
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Text {
                    visible: !operationBusy
                    width: parent.width
                    text: "This backend reports a start/completion boundary but no intermediate percentage. NeutronOS keeps the displayed percentage truthful and changes to 100% only when the backend confirms completion."
                    color: root.mutedText
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Grid {
                    visible: operationBusy
                    width: parent.width
                    columns: 2
                    columnSpacing: 14
                    rowSpacing: 9
                    Repeater {
                        model: [
                            {label:"SOURCE", value:root.clean(storageBackend ? storageBackend.operationSource : "", "SYSTEM / INTERNAL")},
                            {label:"TARGET", value:root.clean(storageBackend ? storageBackend.operationTarget : "", "—")},
                            {label:"WRITTEN", value:root.clean(storageBackend ? storageBackend.operationBytesText : "", "—")},
                            {label:"SPEED", value:root.clean(storageBackend ? storageBackend.operationSpeed : "", "—")},
                            {label:"ELAPSED", value:root.clean(storageBackend ? storageBackend.operationElapsed : "", "0s")},
                            {label:"ETA", value:root.clean(storageBackend ? storageBackend.operationEta : "", "—")},
                            {label:"VERIFICATION", value:root.clean(storageBackend ? storageBackend.operationVerification : "", "NOT REQUIRED")},
                            {label:"STAGE", value:root.clean(storageBackend ? storageBackend.operationStatus : "", "WORKING")}
                        ]
                        Rectangle {
                            required property var modelData
                            width: (parent.width - 14) / 2
                            height: 58
                            radius: 8
                            color: "#0A1A2F"
                            border.width: 1
                            border.color: "#1D3958"
                            Column {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 3
                                Text { width: parent.width; text: modelData.label; color: root.mutedText; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.0 }
                                Text { width: parent.width; text: modelData.value; color: modelData.label === "VERIFICATION" && String(modelData.value).toUpperCase().indexOf("FAIL") >= 0 ? root.dangerRed : root.textWhite; font.pixelSize: 13; font.bold: true; elide: Text.ElideMiddle }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: operationBusy ? "O  KEEP RUNNING     SQUARE  REQUEST SAFE CANCEL" : "O  KEEP RUNNING"
                    color: root.mutedText
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.taskResultVisible
        color: "#E602060D"
        z: 1280

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 160, 820)
            height: 410
            radius: 12
            color: "#07111A"
            border.width: 1
            border.color: root.taskResultSuccess ? root.successGreen : root.dangerRed

            Column {
                anchors.fill: parent
                anchors.margins: 36
                spacing: 20

                Text {
                    width: parent.width
                    text: root.taskResultTitle
                    color: root.textWhite
                    font.pixelSize: 28
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.taskResultSuccess ? "100%" : "TASK FAILED"
                    color: root.taskResultSuccess ? root.successGreen : root.dangerRed
                    font.pixelSize: 34
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    width: parent.width
                    height: 24
                    radius: 12
                    color: "#030810"
                    border.width: 1
                    border.color: root.taskResultSuccess ? root.successGreen : root.dangerRed
                    Rectangle {
                        height: parent.height
                        width: root.taskResultSuccess ? parent.width : 0
                        radius: 12
                        color: root.successGreen
                    }
                }
                Text {
                    width: parent.width
                    height: 120
                    text: root.taskResultMessage
                    color: root.textWhite
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: "X OR O  CLOSE"
                    color: root.mutedText
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.keyboardOpen
        color: "transparent"
        z: 1300
        VirtualKeyboard {
            id: volumeKeyboard
            anchors.centerIn: parent
            visibleMode: false
            title: "TEXT ENTRY"
            cancelBehavior: "close"
            onKeyPressed: function(value) {
                var keyText = String(value)
                if (keyText === "SPACE") keyText = " "
                if (keyText === "CLEAR") root.setKeyboardText("")
                else if (keyText !== "CAPS" && keyText !== "SHIFT" && keyText !== "SPEC" && keyText !== "ABC")
                    root.setKeyboardText(root.currentKeyboardText() + keyText)
            }
            onBackspacePressed: {
                var value = root.currentKeyboardText()
                root.setKeyboardText(value.slice(0, -1))
            }
            onEnterPressed: {
                root.keyboardOpen = false
                volumeKeyboard.visibleMode = false
                root.forceActiveFocus()
            }
            onClosePressed: {
                root.keyboardOpen = false
                volumeKeyboard.visibleMode = false
                root.forceActiveFocus()
            }
        }
    }
}
