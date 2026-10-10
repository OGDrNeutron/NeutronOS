import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root

    property var backend: null
    property bool developerModeEnabled: false
    property bool activeFocusMode: false
    property bool lightMode: false
    property color panelColor: lightMode ? "#FFFFFF" : "#071426"
    property color raisedColor: lightMode ? "#F7F9FB" : "#0B1A30"
    property color insetColor: lightMode ? "#E9EEF4" : "#06101F"
    property color textPrimary: lightMode ? "#080B10" : "#F4FBFF"
    property color textSecondary: lightMode ? "#2F3945" : "#A8C2DE"
    property color textMuted: lightMode ? "#65717E" : "#7895B5"
    property color divider: lightMode ? "#CFD6DE" : "#1D3958"
    property color focusBlue: "#4DA6FF"
    property color success: "#16C784"
    property color warning: "#F5B942"
    property color danger: "#FF4055"
    property color purple: "#A855F7"

    signal statusChanged(string message, bool error)

    property int tabIndex: 0            // 0 profiles, 1 manual
    property int focusIndex: 0
    property var pendingConfiguration: ({})
    property bool dirty: false
    property bool modalVisible: false
    property bool modalArmed: false
    property bool modalError: false
    property bool modalNeedsHealthOverride: false
    property string modalTitle: ""
    property string modalBody: ""
    property var modalConfiguration: ({})

    property var telemetry: backend ? backend.telemetry : ({})
    property var limits: backend ? backend.modelLimits : ({})
    property var profiles: backend ? backend.availableProfiles : []
    property var assessment: backend ? backend.evaluateConfiguration(pendingConfiguration) : ({})

    readonly property bool profilePreviewActive: tabIndex === 0 && focusIndex >= 2 && focusIndex < profilesApplyIndex
    readonly property var previewConfiguration: profilePreviewActive && profiles && profiles.length > (focusIndex - 2)
                                                    ? profiles[focusIndex - 2]
                                                    : pendingConfiguration
    readonly property var previewAssessment: backend ? backend.evaluateConfiguration(previewConfiguration) : ({})

    readonly property int profilesApplyIndex: (profiles ? profiles.length : 0) + 2
    readonly property int profilesFocusCount: (profiles ? profiles.length : 0) + 3
    readonly property int manualFocusCount: 8
    readonly property int focusCount: tabIndex === 0 ? profilesFocusCount : manualFocusCount

    function normalizeAction(action) {
        var a = String(action || "").toLowerCase().replace(/-/g, "_")
        if (a === "x" || a === "cross" || a === "primary" || a === "confirm") return "primary"
        if (a === "o" || a === "circle" || a === "cancel" || a === "back") return "cancel"
        if (a === "square" || a === "secondary") return "secondary"
        if (a === "triangle" || a === "context") return "context"
        if (a === "start" || a === "system" || a === "options") return "system"
        return a
    }

    function cloneMap(value) {
        var copy = ({})
        if (!value)
            return copy
        for (var key in value)
            copy[key] = value[key]
        return copy
    }

    function configurationsEqual(a, b) {
        if (!a || !b)
            return false
        return Number(a.cpuMinMhz || 0) === Number(b.cpuMinMhz || 0) &&
               Number(a.cpuMaxMhz || 0) === Number(b.cpuMaxMhz || 0) &&
               Number(a.gpuMhz || 0) === Number(b.gpuMhz || 0) &&
               Boolean(a.turbo) === Boolean(b.turbo)
    }

    function currentConfiguration() {
        return backend && backend.currentConfiguration ? backend.currentConfiguration : ({})
    }

    function currentProfileName() {
        var current = currentConfiguration()
        return profileDisplayName(current)
    }

    function profileDisplayName(profile) {
        if (!profile)
            return "Normal"
        var supplied = String(profile.profileName || "").trim()
        if (supplied.length > 0)
            return supplied
        var id = String(profile.profile || "normal").toLowerCase()
        if (id === "stage1") return "Stage 1"
        if (id === "stage2") return "Stage 2"
        if (id === "stage3") return "Stage 3"
        if (id === "max") return "Max"
        if (id.indexOf("custom") === 0) return "Custom"
        return "Normal"
    }

    function profileDescription(profile) {
        if (!profile)
            return "Profile information is unavailable."
        var id = String(profile.profile || "").toLowerCase()
        var minCpu = Number(profile.cpuMinMhz || 0)
        var maxCpu = Number(profile.cpuMaxMhz || 0)
        var gpu = Number(profile.gpuMhz || 0)
        var clocks = maxCpu + " MHz CPU / " + gpu + " MHz GPU"
        if (id === "normal")
            return "Everyday stock profile • " + clocks + " • dynamic idle scaling • turbo off."
        if (id === "stage1")
            return "Light performance uplift • " + clocks + " • dynamic idle scaling stays enabled • turbo off."
        if (id === "stage2")
            return "Balanced performance uplift • " + clocks + " • active cooling recommended • turbo off."
        if (id === "stage3")
            return "High-performance preset • " + clocks + " • strong cooling required • turbo off."
        if (id === "max")
            return "Maximum manual preset • " + minCpu + "–" + maxCpu + " MHz CPU / " + gpu + " MHz GPU • turbo on • strong cooling and power required."
        if (id.indexOf("custom") === 0 || profile.saved === true)
            return "Saved custom profile • " + minCpu + "–" + maxCpu + " MHz CPU / " + gpu + " MHz GPU • turbo " + (profile.turbo ? "on" : "off") + "."
        return profileDisplayName(profile) + " • " + minCpu + "–" + maxCpu + " MHz CPU / " + gpu + " MHz GPU • turbo " + (profile.turbo ? "on" : "off") + "."
    }

    function profileDetailedDescription(profile) {
        if (!profile)
            return "Profile information is unavailable."

        var id = String(profile.profile || "").toLowerCase()
        var name = profileDisplayName(profile)
        var minCpu = Number(profile.cpuMinMhz || 0)
        var maxCpu = Number(profile.cpuMaxMhz || 0)
        var gpu = Number(profile.gpuMhz || 0)
        var turbo = Boolean(profile.turbo)
        var clocks = minCpu + "–" + maxCpu + " MHz CPU and " + gpu + " MHz GPU"

        if (id === "normal")
            return "Normal is the everyday NeutronOS profile. It keeps the processor inside stock limits, allows the CPU to scale down while idle, and keeps turbo disabled. Use it for normal desktop work, media, background services, and the lowest practical heat and power draw. Current targets: " + clocks + "."
        if (id === "stage1")
            return "Stage 1 is a light performance increase above stock. It keeps dynamic idle scaling and turbo disabled while raising the available CPU and GPU headroom. It is intended for a little more responsiveness, lighter games, and emulation without committing to the heat and power demands of the higher stages. Current targets: " + clocks + "."
        if (id === "stage2")
            return "Stage 2 is the balanced performance preset. It raises CPU and GPU limits further for heavier games, emulation, and sustained workloads while still allowing the CPU to clock down at idle. Active cooling is recommended for long sessions. Current targets: " + clocks + "."
        if (id === "stage3")
            return "Stage 3 uses the highest standard NeutronOS performance targets before Max. It is intended for demanding games and sustained compute workloads where performance matters more than acoustics or power draw. Strong active cooling and a stable power supply are expected. Current targets: " + clocks + "."
        if (id === "max")
            return "Max is the most aggressive built-in preset. It raises the minimum CPU clock, allows the manual CPU ceiling, uses the maximum configured GPU target, and forces turbo on. Use it only when cooling and power are known to be stable; it produces the most heat and leaves the least thermal margin. Current targets: " + clocks + "."
        if (id.indexOf("custom") === 0 || profile.saved === true)
            return name + " is a saved custom profile. NeutronOS will use the exact clock and turbo values stored with this profile rather than one of the built-in stages. Review its thermal risk before applying it. Current targets: " + clocks + "; turbo " + (turbo ? "on" : "off") + "."

        return name + " uses " + clocks + " with turbo " + (turbo ? "on" : "off") + ". Review the risk indicator and current thermal health before applying this configuration."
    }

    function riskLabel(profile) {
        if (!backend || !profile)
            return "UNKNOWN"
        var result = backend.evaluateConfiguration(profile)
        return String(result.warningLabel || "NORMAL")
    }

    function riskColor(profile) {
        var label = riskLabel(profile)
        if (label === "EXTREME" || label === "HIGH") return danger
        if (label === "MODERATE") return warning
        if (label === "LOW") return purple
        return success
    }

    function syncFromBackend(force) {
        if (!backend)
            return
        if (!dirty || force) {
            pendingConfiguration = cloneMap(backend.currentConfiguration)
            dirty = false
            assessment = backend.evaluateConfiguration(pendingConfiguration)
        }
    }

    function setPending(configuration) {
        if (!configuration)
            return
        pendingConfiguration = cloneMap(configuration)
        dirty = backend ? !configurationsEqual(pendingConfiguration, backend.currentConfiguration) : true
        assessment = backend ? backend.evaluateConfiguration(pendingConfiguration) : ({})
    }

    function selectProfile(index) {
        if (!profiles || index < 0 || index >= profiles.length)
            return
        if (!developerModeEnabled) {
            statusChanged("Enable Developer Mode to change the active performance profile.", true)
            return
        }
        setPending(profiles[index])
        statusChanged(String(profiles[index].profileName || "Profile") + " selected. Review it before applying.", false)
    }

    function manualProfileName() {
        return String(pendingConfiguration.profileName || "Custom")
    }

    function adjustManualRow(direction) {
        if (!backend || !developerModeEnabled) {
            statusChanged("Enable Developer Mode to change performance values.", true)
            return
        }

        var c = cloneMap(pendingConfiguration)
        var stockMin = Number(limits.stockCpuMinMhz || 600)
        var stockMax = Number(limits.stockCpuMaxMhz || 1500)
        var maxLimit = Number(limits.manualCpuMaxMhz || stockMax)
        var stockGpu = Number(limits.stockGpuMhz || 500)
        var gpuLimit = Number(limits.manualGpuMaxMhz || stockGpu)

        if (focusIndex === 1) {
            var list = profiles || []
            if (list.length <= 0)
                return
            var current = 0
            var currentId = String(pendingConfiguration.profile || "")
            for (var i = 0; i < list.length; ++i) {
                if (String(list[i].profile || "") === currentId ||
                        String(list[i].profileName || "") === manualProfileName()) {
                    current = i
                    break
                }
            }
            current = (current + direction + list.length) % list.length
            setPending(list[current])
            return
        }

        if (focusIndex === 2) {
            c.cpuMinMhz = Math.max(stockMin,
                                   Math.min(Number(c.cpuMaxMhz || stockMax),
                                            Number(c.cpuMinMhz || stockMin) + direction * 100))
        } else if (focusIndex === 3) {
            c.cpuMaxMhz = Math.max(Math.max(stockMax, Number(c.cpuMinMhz || stockMin)),
                                   Math.min(maxLimit, Number(c.cpuMaxMhz || stockMax) + direction * 100))
        } else if (focusIndex === 4) {
            c.gpuMhz = Math.max(stockGpu,
                                Math.min(gpuLimit, Number(c.gpuMhz || stockGpu) + direction * 25))
        } else if (focusIndex === 5) {
            c.turbo = !Boolean(c.turbo)
        } else {
            return
        }

        c.profile = "custom"
        c.profileName = "Custom"
        setPending(c)
    }

    function saveCurrentProfile() {
        if (!backend || !developerModeEnabled) {
            statusChanged("Enable Developer Mode before saving a custom performance profile.", true)
            return
        }
        var result = backend.saveCustomProfile(pendingConfiguration)
        statusChanged(String(result.message || (result.ok ? "Profile saved." : "Profile could not be saved.")), !result.ok)
        if (result.ok && result.profile)
            setPending(result.profile)
    }

    function openApplyModal() {
        if (!backend)
            return
        if (!developerModeEnabled) {
            statusChanged("Enable Developer Mode before applying a performance profile.", true)
            return
        }
        if (!dirty) {
            statusChanged("The selected profile is already applied.", false)
            return
        }

        var check = backend.evaluateConfiguration(pendingConfiguration)
        assessment = check
        if (!check.ok) {
            modalTitle = "INVALID CONFIGURATION"
            modalBody = Array.isArray(check.errors) ? check.errors.join("\n") : String(check.errors || "The selected values are invalid.")
            modalError = true
            modalNeedsHealthOverride = false
            modalConfiguration = ({})
            modalArmed = false
            modalVisible = true
            return
        }

        modalConfiguration = cloneMap(pendingConfiguration)
        modalError = false
        modalNeedsHealthOverride = !Boolean(check.healthOk)
        modalArmed = false
        modalTitle = modalNeedsHealthOverride ? "HARDWARE HEALTH WARNING" : "APPLY PERFORMANCE PROFILE"

        var body = "Current profile: " + currentProfileName() +
                   "\nSelected profile: " + String(modalConfiguration.profileName || "Custom") +
                   "\n\nCPU range: " + Number(modalConfiguration.cpuMinMhz || 0) + "–" + Number(modalConfiguration.cpuMaxMhz || 0) + " MHz" +
                   "\nGPU / V3D: " + Number(modalConfiguration.gpuMhz || 0) + " MHz" +
                   "\nTurbo: " + (modalConfiguration.turbo ? "ON" : "OFF") +
                   "\nRisk: " + String(check.warningLabel || "NORMAL")

        if (String(check.warningText || "").length > 0)
            body += "\n\n" + String(check.warningText)
        if (modalNeedsHealthOverride)
            body += "\n\n" + String(check.healthMessage || backend.healthMessage || "Current hardware health is not suitable for this profile.")

        body += "\n\nNeutronOS will update only its managed performance block in config.txt, verify the write, and reboot."
        modalBody = body
        modalVisible = true
    }

    function confirmModal() {
        if (modalError) {
            modalVisible = false
            modalArmed = false
            return
        }
        if (!modalArmed) {
            modalArmed = true
            return
        }

        var result = backend.applyConfiguration(modalConfiguration, modalNeedsHealthOverride)
        if (!result.ok) {
            modalTitle = "APPLY FAILED"
            modalBody = String(result.message || "The performance configuration could not be applied.")
            modalError = true
            modalArmed = false
            return
        }

        modalTitle = "PROFILE APPLIED"
        modalBody = String(result.message || "Rebooting to activate the selected profile.")
        modalError = false
        modalArmed = true
        dirty = false
    }

    function handleControllerPressed(action) {
        action = normalizeAction(action)

        if (modalVisible) {
            if (action === "cancel") {
                modalVisible = false
                modalArmed = false
            } else if (action === "primary") {
                confirmModal()
            }
            return true
        }

        if (action === "up") {
            focusIndex = (focusIndex - 1 + focusCount) % focusCount
            return true
        }
        if (action === "down") {
            focusIndex = (focusIndex + 1) % focusCount
            return true
        }
        if (action === "left") {
            if (focusIndex === 0) {
                tabIndex = Math.max(0, tabIndex - 1)
                focusIndex = 0
            } else if (tabIndex === 1) {
                adjustManualRow(-1)
            }
            return true
        }
        if (action === "right") {
            if (focusIndex === 0) {
                tabIndex = Math.min(1, tabIndex + 1)
                focusIndex = 0
            } else if (tabIndex === 1) {
                adjustManualRow(1)
            }
            return true
        }
        if (action === "primary") {
            if (focusIndex === 0) {
                tabIndex = tabIndex === 0 ? 1 : 0
                focusIndex = 0
                return true
            }

            if (tabIndex === 0) {
                if (focusIndex === 1) {
                    if (backend) {
                        backend.refresh()
                        syncFromBackend(false)
                        statusChanged(String(backend.healthMessage || "Performance telemetry refreshed."), false)
                    }
                } else if (focusIndex >= 2 && focusIndex < profilesApplyIndex) {
                    selectProfile(focusIndex - 2)
                } else if (focusIndex === profilesApplyIndex) {
                    openApplyModal()
                }
            } else {
                if (focusIndex >= 1 && focusIndex <= 5)
                    adjustManualRow(1)
                else if (focusIndex === 6)
                    saveCurrentProfile()
                else if (focusIndex === 7)
                    openApplyModal()
            }
            return true
        }
        if (action === "secondary") {
            openApplyModal()
            return true
        }
        return false
    }

    Component.onCompleted: syncFromBackend(true)

    onVisibleChanged: {
        if (visible && backend) {
            backend.refresh()
            syncFromBackend(false)
        }
    }

    Connections {
        target: root.backend
        function onConfigurationChanged() { root.syncFromBackend(false) }
        function onProfilesChanged() {
            if (root.focusIndex >= root.focusCount)
                root.focusIndex = Math.max(0, root.focusCount - 1)
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.visible && root.backend !== null
        onTriggered: root.backend.refresh()
    }

    Column {
        anchors.fill: parent
        spacing: 12

        Row {
            width: parent.width
            height: 176
            spacing: 12

            Rectangle {
                width: Math.round((parent.width - 12) * 0.46)
                height: parent.height
                radius: 22
                color: root.raisedColor
                border.width: 1
                border.color: root.divider

                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 7

                    Row {
                        width: parent.width
                        height: 24
                        Text {
                            width: parent.width - 120
                            text: "CURRENT PROFILE"
                            color: root.focusBlue
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.6
                        }
                        Rectangle {
                            width: 112
                            height: 24
                            radius: 12
                            color: root.developerModeEnabled ? (root.lightMode ? "#DDFCEB" : "#0B3A28") : root.insetColor
                            border.width: 1
                            border.color: root.developerModeEnabled ? root.success : root.divider
                            Text {
                                anchors.centerIn: parent
                                text: root.developerModeEnabled ? "UNLOCKED" : "READ ONLY"
                                color: root.developerModeEnabled ? root.success : root.textMuted
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.currentProfileName()
                        color: root.textPrimary
                        font.pixelSize: 34
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        height: 43
                        text: root.profileDescription(root.currentConfiguration())
                        color: root.textSecondary
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }
                    Row {
                        width: parent.width
                        spacing: 14
                        Text {
                            text: Number(root.currentConfiguration().cpuMinMhz || 0) + "–" + Number(root.currentConfiguration().cpuMaxMhz || 0) + " MHz CPU"
                            color: root.focusBlue
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Text {
                            text: Number(root.currentConfiguration().gpuMhz || 0) + " MHz GPU"
                            color: root.purple
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Text {
                            text: root.currentConfiguration().turbo ? "TURBO ON" : "TURBO OFF"
                            color: root.currentConfiguration().turbo ? root.danger : root.success
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                }
            }

            Grid {
                width: parent.width - Math.round((parent.width - 12) * 0.46) - 12
                height: parent.height
                columns: 3
                rows: 2
                spacing: 8

                Repeater {
                    model: [
                        { label: "MODEL", value: root.backend ? String(root.backend.piModel || "Unavailable") : "Unavailable" },
                        { label: "TEMP", value: Number(root.telemetry.temperatureC || -1) >= 0 ? Number(root.telemetry.temperatureC).toFixed(1) + " °C" : "Unavailable" },
                        { label: "CPU NOW", value: Number(root.telemetry.currentCpuMhz || 0).toFixed(0) + " MHz" },
                        { label: "LOAD", value: Number(root.telemetry.cpuLoadPercent || 0).toFixed(0) + "%" },
                        { label: "THROTTLE", value: String(root.telemetry.throttledHex || "0x0") },
                        { label: "HEALTH", value: root.backend && root.backend.autoConfigAllowed ? "HEALTHY" : "CHECK" }
                    ]
                    Rectangle {
                        width: (parent.width - 16) / 3
                        height: (parent.height - 8) / 2
                        radius: 16
                        color: root.raisedColor
                        border.width: 1
                        border.color: root.divider
                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 7
                            Text {
                                text: String(modelData.label || "")
                                color: root.textMuted
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1.0
                            }
                            Text {
                                width: parent.width
                                text: String(modelData.value || "Unavailable")
                                color: modelData.label === "HEALTH"
                                       ? (String(modelData.value) === "HEALTHY" ? root.success : root.warning)
                                       : root.textPrimary
                                font.pixelSize: modelData.label === "MODEL" ? 11 : 16
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 48
            radius: 15
            color: root.backend && root.backend.autoConfigAllowed
                   ? (root.lightMode ? "#DDFCEB" : "#0B3A28")
                   : (root.lightMode ? "#FFF0E1" : "#3A1E12")
            border.width: 1
            border.color: root.backend && root.backend.autoConfigAllowed ? root.success : root.warning
            Text {
                anchors.fill: parent
                anchors.margins: 11
                text: root.backend ? String(root.backend.healthMessage || "Performance health data unavailable.") : "Performance backend unavailable."
                color: root.backend && root.backend.autoConfigAllowed ? root.success : root.warning
                font.pixelSize: 12
                font.bold: true
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }
        }

        Row {
            width: parent.width
            height: 48
            spacing: 10
            Repeater {
                model: ["PROFILES", "MANUAL"]
                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 48
                    radius: 15
                    color: root.tabIndex === index ? root.focusBlue : root.insetColor
                    border.width: root.activeFocusMode && root.focusIndex === 0 && root.tabIndex === index ? 3 : 1
                    border.color: root.activeFocusMode && root.focusIndex === 0 && root.tabIndex === index ? "#D9F4FF" : root.divider
                    Text {
                        anchors.centerIn: parent
                        text: String(modelData)
                        color: root.tabIndex === index ? "#04111F" : root.textSecondary
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 1.0
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.tabIndex = index
                            root.focusIndex = 0
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: parent.height - 292

            Row {
                anchors.fill: parent
                spacing: 12
                visible: root.tabIndex === 0

                Rectangle {
                    width: Math.round((parent.width - 12) * 0.62)
                    height: parent.height
                    radius: 20
                    color: root.insetColor
                    border.width: 1
                    border.color: root.divider

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Row {
                            width: parent.width
                            height: 44
                            Text {
                                width: parent.width - 170
                                anchors.verticalCenter: parent.verticalCenter
                                text: "AVAILABLE PROFILES  •  " + String(root.profiles ? root.profiles.length : 0)
                                color: root.textPrimary
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Rectangle {
                                width: 160
                                height: 40
                                radius: 13
                                color: root.focusIndex === 1 && root.activeFocusMode ? root.focusBlue : root.raisedColor
                                border.width: root.focusIndex === 1 && root.activeFocusMode ? 2 : 1
                                border.color: root.focusIndex === 1 && root.activeFocusMode ? "#D9F4FF" : root.divider
                                Text {
                                    anchors.centerIn: parent
                                    text: "REFRESH HEALTH"
                                    color: root.focusIndex === 1 && root.activeFocusMode ? "#04111F" : root.textPrimary
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.focusIndex = 1
                                        if (root.backend) {
                                            root.backend.refresh()
                                            root.syncFromBackend(false)
                                            root.statusChanged(String(root.backend.healthMessage || "Performance telemetry refreshed."), false)
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: profileList
                            width: parent.width
                            height: parent.height - 52
                            model: root.profiles || []
                            spacing: 8
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            currentIndex: Math.max(0, root.focusIndex - 2)
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            delegate: Rectangle {
                                id: profileDelegate
                                width: profileList.width
                                height: 82
                                radius: 16
                                property var profileData: modelData || ({})
                                property bool applied: root.configurationsEqual(profileData, root.currentConfiguration())
                                property bool selectedPending: root.configurationsEqual(profileData, root.pendingConfiguration)
                                property bool focused: root.activeFocusMode && root.focusIndex === index + 2
                                color: focused ? (root.lightMode ? "#DFEFFF" : "#17365D") : root.raisedColor
                                border.width: focused ? 3 : selectedPending ? 2 : 1
                                border.color: focused ? root.focusBlue : selectedPending ? root.success : root.divider

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    Rectangle {
                                        width: 8
                                        height: parent.height
                                        radius: 4
                                        color: root.riskColor(profileDelegate.profileData)
                                    }

                                    Column {
                                        width: parent.width - 300
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Row {
                                            spacing: 8
                                            Text {
                                                text: root.profileDisplayName(profileDelegate.profileData)
                                                color: root.textPrimary
                                                font.pixelSize: 17
                                                font.bold: true
                                            }
                                            Text {
                                                visible: profileDelegate.applied
                                                text: "APPLIED"
                                                color: root.success
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                            Text {
                                                visible: profileDelegate.selectedPending && !profileDelegate.applied
                                                text: "SELECTED"
                                                color: root.focusBlue
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }
                                        Text {
                                            width: parent.width
                                            text: root.profileDescription(profileDelegate.profileData)
                                            color: root.textMuted
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Column {
                                        width: 260
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3
                                        Text {
                                            width: parent.width
                                            text: Number(profileDelegate.profileData.cpuMaxMhz || 0) + " MHz CPU  •  " + Number(profileDelegate.profileData.gpuMhz || 0) + " MHz GPU"
                                            color: root.textPrimary
                                            font.pixelSize: 12
                                            font.bold: true
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            width: parent.width
                                            text: root.riskLabel(profileDelegate.profileData) + (profileDelegate.profileData.turbo ? "  •  TURBO" : "")
                                            color: root.riskColor(profileDelegate.profileData)
                                            font.pixelSize: 11
                                            font.bold: true
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: root.focusIndex = index + 2
                                    onClicked: {
                                        root.focusIndex = index + 2
                                        root.selectProfile(index)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width - Math.round((parent.width - 12) * 0.62) - 12
                    height: parent.height
                    radius: 20
                    color: root.raisedColor
                    border.width: 1
                    border.color: root.divider

                    Column {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10

                        Text {
                            text: root.profilePreviewActive ? "PROFILE PREVIEW" : (root.dirty ? "SELECTED PROFILE" : "ACTIVE PROFILE")
                            color: root.profilePreviewActive ? root.focusBlue : (root.dirty ? root.focusBlue : root.success)
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.3
                        }
                        Text {
                            width: parent.width
                            text: root.profileDisplayName(root.previewConfiguration)
                            color: root.textPrimary
                            font.pixelSize: 25
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            height: 126
                            text: root.profileDetailedDescription(root.previewConfiguration)
                            color: root.textSecondary
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }
                        Rectangle { width: parent.width; height: 1; color: root.divider }
                        Text { text: "CPU IDLE    " + Number(root.previewConfiguration.cpuMinMhz || 0) + " MHz"; color: root.textPrimary; font.pixelSize: 13; font.bold: true }
                        Text { text: "CPU MAX     " + Number(root.previewConfiguration.cpuMaxMhz || 0) + " MHz"; color: root.textPrimary; font.pixelSize: 13; font.bold: true }
                        Text { text: "GPU / V3D   " + Number(root.previewConfiguration.gpuMhz || 0) + " MHz"; color: root.textPrimary; font.pixelSize: 13; font.bold: true }
                        Text { text: "TURBO       " + (root.previewConfiguration.turbo ? "ON" : "OFF"); color: root.previewConfiguration.turbo ? root.danger : root.success; font.pixelSize: 13; font.bold: true }
                        Text { text: "RISK        " + String(root.previewAssessment.warningLabel || "NORMAL"); color: root.riskColor(root.previewConfiguration); font.pixelSize: 13; font.bold: true }
                        Item { width: 1; height: Math.max(0, parent.height - 386) }
                        Rectangle {
                            width: parent.width
                            height: 54
                            radius: 16
                            color: root.dirty && root.developerModeEnabled ? root.success : root.insetColor
                            border.width: root.activeFocusMode && root.focusIndex === root.profilesApplyIndex ? 3 : 1
                            border.color: root.activeFocusMode && root.focusIndex === root.profilesApplyIndex ? "#D9FFE9" : root.divider
                            opacity: root.dirty && root.developerModeEnabled ? 1.0 : 0.65
                            Text {
                                anchors.centerIn: parent
                                text: root.developerModeEnabled ? (root.dirty ? "APPLY & REBOOT" : "ALREADY APPLIED") : "DEVELOPER MODE REQUIRED"
                                color: root.dirty && root.developerModeEnabled ? "#03150D" : root.textMuted
                                font.pixelSize: 12
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.focusIndex = root.profilesApplyIndex
                                    root.openApplyModal()
                                }
                            }
                        }
                    }
                }
            }

            Column {
                anchors.fill: parent
                spacing: 8
                visible: root.tabIndex === 1

                Repeater {
                    model: [
                        { label: "PROFILE", value: root.manualProfileName(), detail: "Cycle through Normal, Stage 1, Stage 2, Stage 3, Max and saved custom profiles" },
                        { label: "IDLE CPU", value: Number(root.pendingConfiguration.cpuMinMhz || 0) + " MHz", detail: "Minimum dynamic CPU frequency" },
                        { label: "MAX CPU", value: Number(root.pendingConfiguration.cpuMaxMhz || 0) + " MHz", detail: "Maximum CPU frequency" },
                        { label: "GPU / V3D", value: Number(root.pendingConfiguration.gpuMhz || 0) + " MHz", detail: "3D graphics clock" },
                        { label: "TURBO", value: root.pendingConfiguration.turbo ? "ON" : "OFF", detail: "Turbo holds maximum clocks while enabled" }
                    ]
                    Rectangle {
                        width: parent.width
                        height: 62
                        radius: 15
                        color: root.raisedColor
                        border.width: root.activeFocusMode && root.focusIndex === index + 1 ? 3 : 1
                        border.color: root.activeFocusMode && root.focusIndex === index + 1 ? root.focusBlue : root.divider
                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12
                            Column {
                                width: parent.width - 280
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Text { text: String(modelData.label || ""); color: root.textPrimary; font.pixelSize: 14; font.bold: true }
                                Text { width: parent.width; text: String(modelData.detail || ""); color: root.textMuted; font.pixelSize: 11; elide: Text.ElideRight }
                            }
                            Text {
                                width: 240
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.value || "")
                                color: index === 4 && root.pendingConfiguration.turbo ? root.danger : root.success
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.focusIndex = index + 1
                                root.adjustManualRow(1)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 52
                    radius: 15
                    color: root.assessment && Number(root.assessment.warningLevel || 0) >= 3
                           ? (root.lightMode ? "#FFE4E8" : "#3A121B")
                           : root.insetColor
                    border.width: 1
                    border.color: root.assessment && Number(root.assessment.warningLevel || 0) >= 3 ? root.danger : root.warning
                    Text {
                        anchors.fill: parent
                        anchors.margins: 11
                        text: root.assessment && root.assessment.requiresWarning
                              ? String(root.assessment.warningLabel || "WARNING") + "  •  " + String(root.assessment.warningText || "Cooling and proper voltage are required.")
                              : "NORMAL  •  Stock clocks, dynamic scaling and turbo off."
                        color: root.assessment && Number(root.assessment.warningLevel || 0) >= 3 ? root.danger : root.warning
                        font.pixelSize: 11
                        font.bold: true
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Row {
                    width: parent.width
                    height: 54
                    spacing: 10
                    Rectangle {
                        width: (parent.width - 10) / 2
                        height: 54
                        radius: 16
                        color: root.insetColor
                        border.width: root.activeFocusMode && root.focusIndex === 6 ? 3 : 1
                        border.color: root.activeFocusMode && root.focusIndex === 6 ? root.focusBlue : root.divider
                        Text { anchors.centerIn: parent; text: "SAVE CUSTOM PROFILE"; color: root.textPrimary; font.pixelSize: 12; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: { root.focusIndex = 6; root.saveCurrentProfile() } }
                    }
                    Rectangle {
                        width: (parent.width - 10) / 2
                        height: 54
                        radius: 16
                        color: root.dirty && root.developerModeEnabled ? root.success : root.insetColor
                        border.width: root.activeFocusMode && root.focusIndex === 7 ? 3 : 1
                        border.color: root.activeFocusMode && root.focusIndex === 7 ? "#D9FFE9" : root.divider
                        opacity: root.dirty && root.developerModeEnabled ? 1.0 : 0.65
                        Text {
                            anchors.centerIn: parent
                            text: root.developerModeEnabled ? (root.dirty ? "APPLY & REBOOT" : "ALREADY APPLIED") : "DEVELOPER MODE REQUIRED"
                            color: root.dirty && root.developerModeEnabled ? "#03150D" : root.textMuted
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: { root.focusIndex = 7; root.openApplyModal() } }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.modalVisible
        color: "#C0000000"
        z: 40

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(820, parent.width - 80)
            height: Math.min(520, parent.height - 60)
            radius: 30
            color: root.panelColor
            border.width: 3
            border.color: root.modalError || root.modalNeedsHealthOverride ? root.danger : root.warning

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 18

                Text {
                    width: parent.width
                    text: root.modalTitle
                    color: root.modalError || root.modalNeedsHealthOverride ? root.danger : root.warning
                    font.pixelSize: 26
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    height: parent.height - 150
                    text: root.modalBody
                    color: root.textPrimary
                    font.pixelSize: 15
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignTop
                }
                Rectangle {
                    width: parent.width
                    height: 58
                    radius: 17
                    color: root.modalError ? root.insetColor : (root.modalArmed ? root.danger : root.warning)
                    Text {
                        anchors.centerIn: parent
                        text: root.modalError ? "X  CLOSE" : (root.modalArmed ? "X  CONFIRM APPLY & REBOOT" : "X  ARM")
                        color: root.modalError ? root.textPrimary : "#1A0800"
                        font.pixelSize: 14
                        font.bold: true
                    }
                }
                Text {
                    width: parent.width
                    text: "O  CANCEL"
                    color: root.textMuted
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
