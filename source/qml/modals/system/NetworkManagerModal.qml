// NEUTRONOS_WIFI_STORAGE_CHROME_V1
import QtQuick 2.15
import QtQuick.Layouts 1.15
import "../../components"

Rectangle {
    id: root

    /*
        ============================================================
             PATCH 14 — FULL SCROLLABLE NETWORK CONTROL PANEL
        ============================================================

        Controller contract:
            D-pad / sticks  move the single stable selection
            X               activate / connect / confirm armed action
            Triangle        arm Forget for a saved network
            O               cancel armed state, close keyboard/editor/modal
            Options/Start   activate the selected control

        The panel is intentionally opaque and avoids continuous decorative
        animation. Only the selected item is scrolled into view.
    */

    property var contextData: ({})
    property var modalContext: ({})
    property bool pointerEnabled: true

    property var availableSnapshot: []
    property var savedSnapshot: []
    property var diagnosticsSnapshot: []

    property int selectedNavIndex: 0
    property string armedKey: ""
    property string statusMessage: ""
    property bool statusIsError: false

    // Patch 19: explicit reactive speed-test snapshots. Dynamic helper lookups
    // do not reliably establish QML dependencies for context properties.
    property bool speedTestRunningSnapshot: false
    property real downloadMbpsSnapshot: 0.0
    property real uploadMbpsSnapshot: 0.0
    property int latencyMsSnapshot: -1
    property string speedTestStatusSnapshot: "Waiting for first automatic test"
    property string speedTestLastRunSnapshot: "Never"

    property bool editorVisible: false
    property string editorMode: ""
    property var editorNetwork: null
    property int selectedEditorControl: 0
    property string editorSsid: ""
    property string editorPassword: ""
    property int editorSecurityIndex: 0
    property bool editorRemember: true

    property bool keyboardVisible: false
    property string keyboardField: ""
    property bool hotspotPasswordVisible: false
    property string hotspotPassword: ""
    property string hotspotPasswordConfirmation: ""
    property int hotspotPasswordFocus: 0
    property bool enableHotspotAfterPassword: false

    readonly property var securityOptions: [
        "WPA2/WPA3",
        "WPA2",
        "WPA3",
        "OPEN"
    ]

    readonly property int quickActionCount: 4
    readonly property int availableStart: quickActionCount
    readonly property int savedStart: availableStart + availableSnapshot.length
    readonly property int hotspotStart: savedStart + savedSnapshot.length
    readonly property int hotspotCount: 10
    readonly property int toolStart: hotspotStart + hotspotCount
    readonly property int toolCount: 4
    readonly property int navCount: toolStart + toolCount

    readonly property var hotspotActionBackend: backend()

    property color neutronBlue: "#4DA6FF"
    property color focusBlue: "#4DA6FF"
    property color successGreen: "#22ff88"
    property color warningGold: "#f5c542"
    property color dangerRed: "#ff3040"
    property color purple: "#c084fc"
    property color mutedText: "#8aa6c8"
    property color panelColor: "#02060D"
    property color panelInner: "#02060D"
    property color cardColor: "#0B1A30"

    signal closed()
    signal actionRequested(string action, var payload)

    anchors.fill: parent
    visible: false
    enabled: visible
    color: "#D4020710"
    z: 999
    focus: visible
    Keys.enabled: visible

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        selectedNavIndex = 0
        armedKey = ""
        statusMessage = ""
        statusIsError = false
        editorVisible = false
        keyboardVisible = false
        visible = true
        reloadFromBackend()
        refreshSpeedTestSnapshot()

        var manager = backend()
        if (manager && typeof manager.refresh === "function")
            manager.refresh()

        root.forceActiveFocus()
        scrollSelectionTimer.restart()
    }

    function openModal(context) {
        open(context)
    }

    function close() {
        if (!visible)
            return

        if (keyboardVisible) {
            closeKeyboard()
            return
        }

        if (editorVisible) {
            closeEditor()
            return
        }

        visible = false
        armedKey = ""
        availableSnapshot = []
        savedSnapshot = []
        diagnosticsSnapshot = []
        closed()
    }

    function closeModal() {
        close()
    }

    function backend() {
        try {
            if (typeof networkManager !== "undefined" && networkManager)
                return networkManager
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

        for (var i = 0; i < keys.length; ++i) {
            try {
                var value = object[keys[i]]
                if (value !== undefined && value !== null)
                    return value
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function backendValue(keys, fallbackValue) {
        return objectValue(backend(), keys, fallbackValue)
    }

    function contextValue(keys, fallbackValue) {
        return objectValue(contextData, keys, fallbackValue)
    }

    function normalizedArray(value) {
        if (!value)
            return []

        try {
            if (Array.isArray(value))
                return value.slice(0)

            if (value.length !== undefined) {
                var result = []
                for (var i = 0; i < value.length; ++i)
                    result.push(value[i])
                return result
            }
        } catch (e) {
        }

        return []
    }

    function numberValue(value, fallbackValue) {
        var result = Number(value)
        return isNaN(result) ? fallbackValue : result
    }

    function clampPercent(value) {
        return Math.max(0, Math.min(100, numberValue(value, 0)))
    }

    function reloadFromBackend() {
        var availableRaw = backendValue(
            ["availableNetworks", "networks", "wifiNetworks"],
            contextValue(["availableNetworks", "networks"], [])
        )

        var savedRaw = backendValue(
            ["savedNetworks", "knownNetworks", "wifiProfiles"],
            contextValue(["savedNetworks", "knownNetworks"], [])
        )

        availableSnapshot = normalizeAndSortNetworks(
            normalizedArray(availableRaw),
            false
        )

        savedSnapshot = normalizeAndSortNetworks(
            normalizedArray(savedRaw),
            true
        )

        diagnosticsSnapshot = normalizedArray(
            backendValue(["diagnosticResults"], [])
        )

        selectedNavIndex = Math.max(
            0,
            Math.min(Math.max(0, navCount - 1), selectedNavIndex)
        )
        scrollSelectionTimer.restart()
    }

    function normalizeAndSortNetworks(list, savedDefault) {
        var result = []
        var seen = ({})

        for (var i = 0; i < list.length; ++i) {
            var item = list[i]
            var ssid = networkSsid(item)
            if (ssid.length <= 0)
                continue

            var key = networkId(item)
            if (key.length <= 0)
                key = ssid + "|" + networkBssid(item)

            if (seen[key])
                continue

            seen[key] = true
            result.push(item)
        }

        result.sort(function(a, b) {
            var ac = networkConnected(a) ? 1 : 0
            var bc = networkConnected(b) ? 1 : 0
            if (ac !== bc)
                return bc - ac

            var as = networkSaved(a, savedDefault) ? 1 : 0
            var bs = networkSaved(b, savedDefault) ? 1 : 0
            if (as !== bs)
                return bs - as

            var signalDelta = networkSignal(b) - networkSignal(a)
            if (signalDelta !== 0)
                return signalDelta

            return networkSsid(a).localeCompare(networkSsid(b))
        })

        return result
    }

    function networkValue(network, keys, fallbackValue) {
        return objectValue(network, keys, fallbackValue)
    }

    function networkId(network) {
        return cleanText(networkValue(
            network,
            ["id", "uuid", "path", "bssid", "ssid"],
            ""
        ))
    }

    function networkSsid(network) {
        return cleanText(networkValue(
            network,
            ["ssid", "name", "connectionName", "id"],
            ""
        ))
    }

    function networkBssid(network) {
        return cleanText(networkValue(network, ["bssid", "mac"], ""))
    }

    function networkSignal(network) {
        return clampPercent(networkValue(
            network,
            ["signalPercent", "signal", "strength", "quality"],
            0
        ))
    }

    function networkSecurity(network) {
        var value = cleanText(networkValue(
            network,
            ["security", "securityType", "auth"],
            "OPEN"
        )).toUpperCase()

        return value.length > 0 ? value : "OPEN"
    }

    function networkFrequency(network) {
        return cleanText(networkValue(
            network,
            ["frequency", "band", "frequencyText"],
            "--"
        ))
    }

    function networkSaved(network, fallbackValue) {
        var value = networkValue(
            network,
            ["saved", "known", "remembered"],
            fallbackValue
        )
        return Boolean(value)
    }

    function networkConnected(network) {
        var explicit = networkValue(
            network,
            ["connected", "active", "current"],
            false
        )

        if (Boolean(explicit))
            return true

        return connectedSsid().length > 0 &&
               networkSsid(network) === connectedSsid()
    }

    function networkHidden(network) {
        return Boolean(networkValue(network, ["hidden"], false))
    }

    function networkRequiresPassword(network) {
        var security = networkSecurity(network)
        return security !== "OPEN" &&
               security !== "NONE" &&
               security.indexOf("OWE") < 0
    }

    function networkPayload(network, savedDefault) {
        return {
            "network": network,
            "id": networkId(network),
            "ssid": networkSsid(network),
            "bssid": networkBssid(network),
            "security": networkSecurity(network),
            "saved": networkSaved(network, savedDefault),
            "hidden": networkHidden(network)
        }
    }

    function connectedSsid() {
        return cleanText(backendValue(
            ["connectedSsid", "ssid", "currentSsid"],
            contextValue(["ssid", "networkName"], "")
        ))
    }

    function connectionState() {
        return cleanText(backendValue(
            ["connectionState", "networkState", "wifiState"],
            connectedSsid().length > 0 ? "CONNECTED" : "DISCONNECTED"
        )).toUpperCase()
    }

    function wifiEnabled() {
        return Boolean(backendValue(
            ["wifiEnabled", "wirelessEnabled"],
            true
        ))
    }

    function scanning() {
        return Boolean(backendValue(
            ["scanning", "scanInProgress"],
            false
        ))
    }

    function operationBusy() {
        return Boolean(backendValue(["operationBusy"], false))
    }

    function currentSignalPercent() {
        return clampPercent(backendValue(
            ["signalPercent", "wifiSignalPercent", "connectedSignal"],
            0
        ))
    }

    function currentSecurity() {
        return cleanText(backendValue(
            ["currentSecurity", "securityType", "wifiSecurity"],
            "--"
        )).toUpperCase()
    }

    function localIp() {
        return cleanText(backendValue(
            ["localIp", "ipv4", "ipAddress"],
            "--"
        )) || "--"
    }

    function gateway() {
        return cleanText(backendValue(
            ["gateway", "defaultGateway"],
            "--"
        )) || "--"
    }

    function dnsText() {
        var servers = normalizedArray(backendValue(
            ["dnsServers", "dns", "nameServers"],
            []
        ))

        if (servers.length <= 0)
            return "--"

        var output = []
        for (var i = 0; i < servers.length; ++i) {
            var value = cleanText(servers[i])
            if (value.length > 0)
                output.push(value)
        }

        return output.length > 0 ? output.join("  •  ") : "--"
    }

    function tailscaleIp() {
        return cleanText(backendValue(
            ["tailscaleIp", "tailnetIp"],
            "--"
        )) || "--"
    }

    function interfaceName() {
        return cleanText(backendValue(
            ["interfaceName", "wifiInterface"],
            "--"
        )) || "--"
    }

    function currentFrequency() {
        return cleanText(backendValue(
            ["frequency", "band"],
            "--"
        )) || "--"
    }

    function refreshSpeedTestSnapshot() {
        var manager = backend()
        if (!manager)
            return

        try { speedTestRunningSnapshot = Boolean(manager.speedTestRunning) } catch (error1) {}
        try { downloadMbpsSnapshot = numberValue(manager.downloadMbps, downloadMbpsSnapshot) } catch (error2) {}
        try { uploadMbpsSnapshot = numberValue(manager.uploadMbps, uploadMbpsSnapshot) } catch (error3) {}
        try { latencyMsSnapshot = Math.round(numberValue(manager.latencyMs, latencyMsSnapshot)) } catch (error4) {}
        try { speedTestStatusSnapshot = cleanText(manager.speedTestStatus) || speedTestStatusSnapshot } catch (error5) {}
        try { speedTestLastRunSnapshot = cleanText(manager.speedTestLastRun) || speedTestLastRunSnapshot } catch (error6) {}
    }

    function speedTestRunning() {
        return speedTestRunningSnapshot
    }

    function downloadMbps() {
        return downloadMbpsSnapshot
    }

    function uploadMbps() {
        return uploadMbpsSnapshot
    }

    function latencyMs() {
        return latencyMsSnapshot
    }

    function speedTestStatus() {
        return speedTestStatusSnapshot
    }

    function speedTestLastRun() {
        return speedTestLastRunSnapshot
    }

    function diagnosticsRunning() {
        return Boolean(backendValue(["diagnosticsRunning"], false))
    }

    function diagnosticsSummary() {
        return cleanText(backendValue(
            ["diagnosticsSummary"],
            "Not run yet"
        ))
    }

    function formatMbps(value) {
        var number = numberValue(value, 0)
        if (number <= 0)
            return "--"
        if (number >= 100)
            return number.toFixed(0)
        if (number >= 10)
            return number.toFixed(1)
        return number.toFixed(2)
    }

    function maskedText(length) {
        var count = Math.max(0, Number(length) || 0)
        var text = ""
        for (var i = 0; i < count; ++i)
            text += "•"
        return text
    }

    function quickActionTitle(index) {
        if (index === 0)
            return scanning() ? "SCANNING" : "SCAN NETWORKS"
        if (index === 1)
            return "ADD HIDDEN"
        if (index === 2)
            return speedTestRunning() ? "TESTING" : "SPEED TEST"
        return wifiEnabled() ? "WI-FI ON" : "WI-FI OFF"
    }

    function quickActionSubtitle(index) {
        if (index === 0)
            return "Refresh nearby access points"
        if (index === 1)
            return "Enter SSID and password"
        if (index === 2)
            return "Also runs automatically every 10 minutes"
        return wifiEnabled() ? "Press X twice to disable" : "Press X to enable"
    }

    function hotspotTitle(index) {
        var titles = [
            "ENABLE LOCAL WI-FI HOTSPOT",
            "DISABLE LOCAL WI-FI HOTSPOT",
            "ENABLE WI-FI DNSMASQ",
            "DISABLE WI-FI DNSMASQ",
            "ENABLE OFFLINE ROKU MODE",
            "DISABLE OFFLINE ROKU MODE",
            "ENABLE LAN HOTSPOT",
            "DISABLE LAN HOTSPOT",
            "ENABLE LAN DNSMASQ",
            "DISABLE LAN DNSMASQ"
        ]
        return titles[Math.max(0, Math.min(titles.length - 1, index))]
    }

    function hotspotSubtitle(index) {
        var subtitles = [
            "Manual mode: broadcast NeutronOS until you disable it yourself",
            "Stop only the manually enabled NeutronOS Wi-Fi hotspot",
            "Provide Wi-Fi DHCP and local DNS addresses for offline Roku clients",
            "Keep the Wi-Fi hotspot active without providing DHCP or DNS",
            "Explicit isolated Roku/Jellyfin mode; never starts automatically",
            "Return to normal Wi-Fi without deleting saved profiles",
            "Configure the wired interface as an offline Roku network",
            "Return the wired interface from the NeutronOS LAN hotspot profile",
            "Provide LAN DHCP and local DNS addresses for a directly connected Roku",
            "Keep the LAN interface active without providing DHCP or DNS"
        ]
        return subtitles[Math.max(0, Math.min(subtitles.length - 1, index))]
    }

    function hotspotScriptPath(index) {
        var scripts = [
            "/opt/neutronos/scripts/neutron-hotspot-enable.sh",
            "/opt/neutronos/scripts/neutron-hotspot-disable.sh",
            "/opt/neutronos/scripts/neutron-wifi-dnsmasq-enable.sh",
            "/opt/neutronos/scripts/neutron-wifi-dnsmasq-disable.sh",
            "/opt/neutronos/scripts/neutron-hotspot-auto-enable.sh",
            "/opt/neutronos/scripts/neutron-hotspot-auto-disable.sh",
            "/opt/neutronos/scripts/neutron-lan-hotspot-enable.sh",
            "/opt/neutronos/scripts/neutron-lan-hotspot-disable.sh",
            "/opt/neutronos/scripts/neutron-lan-dnsmasq-enable.sh",
            "/opt/neutronos/scripts/neutron-lan-dnsmasq-disable.sh"
        ]
        return scripts[Math.max(0, Math.min(scripts.length - 1, index))]
    }

    function activateHotspot(index) {
        armedKey = ""

        if (!hotspotActionBackend ||
                typeof hotspotActionBackend.executeAction !== "function") {
            statusMessage = "HOTSPOT CONTROL BACKEND IS UNAVAILABLE"
            statusIsError = true
            return false
        }

        var state = hotspotActionBackend.offlineNetworkState || ({})
        if (index === 0 && !Boolean(state.passwordConfigured)) {
            hotspotPassword = ""
            hotspotPasswordConfirmation = ""
            hotspotPasswordFocus = 0
            hotspotPasswordVisible = true
            return true
        }
        var success = false
        if (index === 0) success = hotspotActionBackend.setOfflineNetworkMode("wifi-hotspot")
        else if (index === 1) success = hotspotActionBackend.setOfflineNetworkMode("normal-wifi")
        else if (index === 2) success = hotspotActionBackend.setOfflineNetworkDns("wifi", true, Boolean(state.wildcardDnsEnabled))
        else if (index === 3) success = hotspotActionBackend.setOfflineNetworkDns("wifi", false, Boolean(state.wildcardDnsEnabled))
        else if (index === 4) success = hotspotActionBackend.setOfflineNetworkMode("offline-roku")
        else if (index === 5) success = hotspotActionBackend.setOfflineNetworkMode("normal-wifi")
        else if (index === 6) success = hotspotActionBackend.setOfflineNetworkMode("lan-hotspot")
        else if (index === 7) success = hotspotActionBackend.setOfflineNetworkMode("normal-wifi")
        else if (index === 8) success = hotspotActionBackend.setOfflineNetworkDns("lan", true, Boolean(state.wildcardDnsEnabled))
        else if (index === 9) success = hotspotActionBackend.setOfflineNetworkDns("lan", false, Boolean(state.wildcardDnsEnabled))

        statusMessage = success
            ? hotspotTitle(index) + " REQUEST SENT"
            : "HOTSPOT REQUEST FAILED — CHECK NETWORK DIAGNOSTICS OR JOURNAL"
        statusIsError = !success

        if (success) {
            var manager = backend()
            if (manager && typeof manager.refresh === "function")
                manager.refresh()
            reloadFromBackend()
        }

        return success
    }

    function toolTitle(index) {
        if (index === 0)
            return diagnosticsRunning() ? "DIAGNOSTICS RUNNING" : "RUN DIAGNOSTICS"
        if (index === 1)
            return "REPAIR CONNECTION"
        if (index === 2)
            return "RESTART WI-FI MANAGER"
        return "CLOSE NETWORK PANEL"
    }

    function toolSubtitle(index) {
        if (index === 0)
            return "Service, interface, route, gateway, Internet, and DNS checks"
        if (index === 1)
            return "Reapply the Pi wireless interface and reconnect if required"
        if (index === 2)
            return "Restart NetworkManager — requires armed confirmation"
        return "Return to the NeutronOS Console"
    }

    function selectedKind() {
        if (selectedNavIndex < quickActionCount)
            return "quick"
        if (selectedNavIndex < savedStart)
            return "available"
        if (selectedNavIndex < hotspotStart)
            return "saved"
        if (selectedNavIndex < toolStart)
            return "hotspot"
        return "tool"
    }

    function selectedNetworkData() {
        if (selectedKind() === "available")
            return availableSnapshot[selectedNavIndex - availableStart]
        if (selectedKind() === "saved")
            return savedSnapshot[selectedNavIndex - savedStart]
        return null
    }

    function selectedNetworkSavedDefault() {
        return selectedKind() === "saved"
    }

    function moveSelection(delta) {
        if (navCount <= 0)
            return false

        armedKey = ""
        selectedNavIndex = Math.max(
            0,
            Math.min(navCount - 1, selectedNavIndex + delta)
        )
        scrollSelectionTimer.restart()
        return true
    }

    function activateSelected() {
        var kind = selectedKind()

        if (kind === "quick")
            return activateQuickAction(selectedNavIndex)

        if (kind === "available" || kind === "saved")
            return activateNetwork(
                selectedNetworkData(),
                selectedNetworkSavedDefault()
            )

        if (kind === "hotspot")
            return activateHotspot(selectedNavIndex - hotspotStart)

        return activateTool(selectedNavIndex - toolStart)
    }

    function activateQuickAction(index) {
        if (operationBusy() && index !== 3) {
            statusMessage = "A NETWORK OPERATION IS ALREADY RUNNING"
            statusIsError = true
            return false
        }

        if (index === 0) {
            armedKey = ""
            statusMessage = "SCANNING FOR AVAILABLE NETWORKS"
            statusIsError = false
            actionRequested("scan", { "source": "networkModal" })
            return true
        }

        if (index === 1) {
            armedKey = ""
            openEditor("hidden", null)
            return true
        }

        if (index === 2) {
            armedKey = ""
            statusMessage = "NETWORK SPEED TEST STARTED"
            statusIsError = false
            actionRequested("speedTest", { "source": "networkModal" })
            return true
        }

        if (wifiEnabled()) {
            if (armedKey !== "wifiOff") {
                armedKey = "wifiOff"
                statusMessage = "WI-FI OFF IS ARMED — PRESS X AGAIN TO CONFIRM"
                statusIsError = true
                return true
            }
        }

        armedKey = ""
        actionRequested("setWifiEnabled", {
            "enabled": !wifiEnabled(),
            "source": "networkModal"
        })
        statusMessage = wifiEnabled()
            ? "DISABLING WI-FI"
            : "ENABLING WI-FI"
        statusIsError = false
        return true
    }

    function activateNetwork(network, savedDefault) {
        if (!network)
            return false

        var forgetKey = "forget:" + networkId(network)
        if (armedKey === forgetKey) {
            actionRequested("forget", networkPayload(network, savedDefault))
            armedKey = ""
            statusMessage = "FORGET REQUEST SENT FOR " + networkSsid(network).toUpperCase()
            statusIsError = false
            return true
        }

        if (operationBusy()) {
            statusMessage = "A NETWORK OPERATION IS ALREADY RUNNING"
            statusIsError = true
            return false
        }

        if (networkConnected(network)) {
            actionRequested("disconnect", networkPayload(network, savedDefault))
            statusMessage = "DISCONNECTING FROM " + networkSsid(network).toUpperCase()
            statusIsError = false
            return true
        }

        if (networkRequiresPassword(network) &&
                !networkSaved(network, savedDefault)) {
            openEditor("connect", network)
            return true
        }

        actionRequested("connect", networkPayload(network, savedDefault))
        statusMessage = "CONNECTING TO " + networkSsid(network).toUpperCase()
        statusIsError = false
        return true
    }

    function activateTool(index) {
        if (index === 3) {
            close()
            return true
        }

        if (operationBusy()) {
            statusMessage = "A NETWORK OPERATION IS ALREADY RUNNING"
            statusIsError = true
            return false
        }

        if (index === 0) {
            armedKey = ""
            statusMessage = "RUNNING NETWORK DIAGNOSTICS"
            statusIsError = false
            actionRequested("diagnostics", { "source": "networkModal" })
            return true
        }

        if (index === 1) {
            armedKey = ""
            statusMessage = "REPAIRING THE WI-FI CONNECTION"
            statusIsError = false
            actionRequested("repairConnection", { "source": "networkModal" })
            return true
        }

        if (armedKey !== "restartWifiManager") {
            armedKey = "restartWifiManager"
            statusMessage = "WI-FI MANAGER RESTART IS ARMED — PRESS X AGAIN TO CONFIRM"
            statusIsError = true
            return true
        }

        armedKey = ""
        statusMessage = "RESTARTING NETWORKMANAGER"
        statusIsError = false
        actionRequested("restartWifiManager", { "source": "networkModal" })
        return true
    }

    function contextSelected() {
        var kind = selectedKind()
        if (kind !== "available" && kind !== "saved") {
            statusMessage = "TRIANGLE IS USED TO FORGET A SAVED NETWORK PROFILE"
            statusIsError = false
            return true
        }

        var network = selectedNetworkData()
        var savedDefault = selectedNetworkSavedDefault()
        if (!networkSaved(network, savedDefault)) {
            statusMessage = "THIS NETWORK DOES NOT HAVE A SAVED PROFILE"
            statusIsError = true
            return true
        }

        armedKey = "forget:" + networkId(network)
        statusMessage = "FORGET IS ARMED FOR " +
                        networkSsid(network).toUpperCase() +
                        " — PRESS X TO CONFIRM"
        statusIsError = true
        return true
    }

    function navItem(index) {
        if (index < quickActionCount)
            return quickActionRepeater.itemAt(index)

        if (index < savedStart)
            return availableRepeater.itemAt(index - availableStart)

        if (index < hotspotStart)
            return savedRepeater.itemAt(index - savedStart)

        if (index < toolStart)
            return hotspotRepeater.itemAt(index - hotspotStart)

        return toolRepeater.itemAt(index - toolStart)
    }

    function ensureSelectedVisible() {
        var item = navItem(selectedNavIndex)
        if (!item || !contentFlick.visible)
            return

        var point = item.mapToItem(contentColumn, 0, 0)
        var top = point.y - 18
        var bottom = point.y + item.height + 18

        if (top < contentFlick.contentY) {
            contentFlick.contentY = Math.max(0, top)
        } else if (bottom > contentFlick.contentY + contentFlick.height) {
            contentFlick.contentY = Math.min(
                Math.max(0, contentFlick.contentHeight - contentFlick.height),
                bottom - contentFlick.height
            )
        }
    }

    function securityIndexFor(value) {
        var normalized = cleanText(value).toUpperCase()
        for (var i = 0; i < securityOptions.length; ++i) {
            if (securityOptions[i] === normalized)
                return i
        }

        if (normalized.indexOf("WPA3") >= 0 && normalized.indexOf("WPA2") >= 0)
            return 0
        if (normalized.indexOf("WPA3") >= 0)
            return 2
        if (normalized.indexOf("WPA") >= 0)
            return 1
        return 3
    }

    function openEditor(mode, network) {
        editorMode = mode
        editorNetwork = network
        editorPassword = ""
        editorRemember = true

        if (mode === "connect") {
            editorSsid = networkSsid(network)
            editorSecurityIndex = securityIndexFor(networkSecurity(network))
            selectedEditorControl = editorSecurityIndex === 3 ? 3 : 2
        } else {
            editorSsid = ""
            editorSecurityIndex = 0
            selectedEditorControl = 0
        }

        editorVisible = true
        keyboardVisible = false
        armedKey = ""
        root.forceActiveFocus()
    }

    function closeEditor() {
        if (keyboardVisible) {
            closeKeyboard()
            return
        }

        editorVisible = false
        editorMode = ""
        editorNetwork = null
        editorSsid = ""
        editorPassword = ""
        selectedEditorControl = 0
        root.forceActiveFocus()
    }

    function editorControlEnabled(index) {
        if (editorMode === "connect" && index === 0)
            return false
        if (editorSecurityIndex === 3 && index === 2)
            return false
        return true
    }

    function moveEditorSelection(delta) {
        var next = selectedEditorControl
        for (var i = 0; i < 6; ++i) {
            next = (next + delta + 6) % 6
            if (editorControlEnabled(next)) {
                selectedEditorControl = next
                return true
            }
        }
        return false
    }

    function openKeyboard(fieldName) {
        keyboardField = fieldName
        keyboardVisible = true
        networkKeyboard.title = fieldName === "password"
            ? "Wi-Fi Password"
            : "Network Name / SSID"
        networkKeyboard.openKeyboard("large")
    }

    function closeKeyboard() {
        keyboardVisible = false
        keyboardField = ""
        networkKeyboard.visibleMode = false
        root.forceActiveFocus()
    }

    function appendKeyboardValue(value) {
        if (keyboardField === "hotspotPassword") { hotspotPassword += value; return }
        if (keyboardField === "hotspotConfirmation") { hotspotPasswordConfirmation += value; return }
        if (keyboardField === "password")
            editorPassword += value
        else
            editorSsid += value
    }

    function keyboardBackspace() {
        if (keyboardField === "hotspotPassword") { hotspotPassword = hotspotPassword.slice(0, -1); return }
        if (keyboardField === "hotspotConfirmation") { hotspotPasswordConfirmation = hotspotPasswordConfirmation.slice(0, -1); return }
        if (keyboardField === "password") {
            if (editorPassword.length > 0)
                editorPassword = editorPassword.slice(0, editorPassword.length - 1)
        } else if (editorSsid.length > 0) {
            editorSsid = editorSsid.slice(0, editorSsid.length - 1)
        }
    }

    function activateEditorControl() {
        if (selectedEditorControl === 0) {
            openKeyboard("ssid")
            return true
        }

        if (selectedEditorControl === 1) {
            editorSecurityIndex = (editorSecurityIndex + 1) % securityOptions.length
            if (editorSecurityIndex === 3)
                editorPassword = ""
            return true
        }

        if (selectedEditorControl === 2) {
            openKeyboard("password")
            return true
        }

        if (selectedEditorControl === 3) {
            editorRemember = !editorRemember
            return true
        }

        if (selectedEditorControl === 4)
            return submitEditor()

        closeEditor()
        return true
    }

    function submitEditor() {
        var ssid = cleanText(editorSsid)
        if (ssid.length <= 0) {
            statusMessage = "NETWORK NAME IS REQUIRED"
            statusIsError = true
            selectedEditorControl = 0
            return false
        }

        var security = securityOptions[editorSecurityIndex]
        if (security !== "OPEN" && cleanText(editorPassword).length <= 0) {
            statusMessage = "A PASSWORD IS REQUIRED FOR THIS NETWORK"
            statusIsError = true
            selectedEditorControl = 2
            return false
        }

        var payload = {
            "network": editorNetwork,
            "id": networkId(editorNetwork),
            "ssid": ssid,
            "bssid": networkBssid(editorNetwork),
            "security": security,
            "password": editorPassword,
            "remember": editorRemember,
            "hidden": editorMode === "hidden"
        }

        actionRequested(editorMode === "hidden" ? "addHidden" : "connect", payload)
        statusMessage = "CONNECT REQUEST SENT FOR " + ssid.toUpperCase()
        statusIsError = false
        editorVisible = false
        keyboardVisible = false
        editorPassword = ""
        root.forceActiveFocus()
        return true
    }

    function applyKeyboardText(fieldName, text, accepted) {
        if (accepted === false)
            return false
        if (fieldName === "password")
            editorPassword = String(text || "")
        else if (fieldName === "ssid")
            editorSsid = String(text || "")
        else
            return false
        return true
    }

    function completeVirtualKeyboard(fieldName, text, accepted) {
        return applyKeyboardText(fieldName, text, accepted)
    }

    function submitHotspotPassword() {
        if (hotspotPassword.length < 8) {
            statusMessage = "HOTSPOT PASSWORD MUST CONTAIN AT LEAST 8 CHARACTERS"
            statusIsError = true
            return false
        }
        if (hotspotPassword !== hotspotPasswordConfirmation) {
            statusMessage = "HOTSPOT PASSWORDS DO NOT MATCH"
            statusIsError = true
            return false
        }
        var accepted = hotspotActionBackend && hotspotActionBackend.setOfflineWifiPassword(
            hotspotPassword, hotspotPasswordConfirmation)
        enableHotspotAfterPassword = accepted
        hotspotPassword = ""
        hotspotPasswordConfirmation = ""
        hotspotPasswordVisible = false
        statusMessage = accepted ? "SECURE HOTSPOT CREDENTIAL REQUEST SENT" : "CREDENTIAL REQUEST FAILED"
        statusIsError = !accepted
        return accepted
    }

    function normalizeAction(action) {
        var value = String(action || "").trim().toLowerCase()
        if (value === "x" || value === "cross" || value === "confirm")
            return "primary"
        if (value === "o" || value === "circle" || value === "back")
            return "cancel"
        if (value === "triangle")
            return "context"
        if (value === "options" || value === "start")
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

        var normalized = normalizeAction(action)

        if (keyboardVisible)
            return networkKeyboard.handleController(normalized)

        if (hotspotPasswordVisible) {
            if (normalized === "cancel") { hotspotPasswordVisible = false; hotspotPassword = ""; hotspotPasswordConfirmation = ""; return true }
            if (normalized === "up") { hotspotPasswordFocus = Math.max(0, hotspotPasswordFocus - 1); return true }
            if (normalized === "down") { hotspotPasswordFocus = Math.min(3, hotspotPasswordFocus + 1); return true }
            if (normalized === "primary") {
                if (hotspotPasswordFocus === 0) openKeyboard("hotspotPassword")
                else if (hotspotPasswordFocus === 1) openKeyboard("hotspotConfirmation")
                else if (hotspotPasswordFocus === 2) submitHotspotPassword()
                else { hotspotPasswordVisible = false; hotspotPassword = ""; hotspotPasswordConfirmation = "" }
                return true
            }
            return true
        }

        if (editorVisible) {
            if (normalized === "cancel") {
                closeEditor()
                return true
            }
            if (normalized === "up")
                return moveEditorSelection(-1)
            if (normalized === "down")
                return moveEditorSelection(1)
            if (normalized === "left" && selectedEditorControl === 1) {
                editorSecurityIndex = (editorSecurityIndex - 1 + securityOptions.length) % securityOptions.length
                return true
            }
            if (normalized === "right" && selectedEditorControl === 1) {
                editorSecurityIndex = (editorSecurityIndex + 1) % securityOptions.length
                return true
            }
            if ((normalized === "left" || normalized === "right") && selectedEditorControl === 3) {
                editorRemember = normalized === "right"
                return true
            }
            if (normalized === "primary" || normalized === "system")
                return activateEditorControl()
            return true
        }

        if (normalized === "cancel") {
            if (armedKey.length > 0) {
                armedKey = ""
                statusMessage = "ARMED ACTION CANCELLED"
                statusIsError = false
            } else {
                close()
            }
            return true
        }

        if (normalized === "context")
            return contextSelected()

        if (normalized === "up")
            return moveSelection(-1)

        if (normalized === "down")
            return moveSelection(1)

        if (normalized === "left") {
            if (selectedNavIndex < quickActionCount)
                return moveSelection(-1)
            return moveSelection(-1)
        }

        if (normalized === "right") {
            if (selectedNavIndex < quickActionCount)
                return moveSelection(1)
            return moveSelection(1)
        }

        if (normalized === "primary" || normalized === "system")
            return activateSelected()

        return true
    }

    function handleController(action) {
        return handleControllerPressed(action)
    }

    function handleControllerReleased(action) {
        return visible
    }

    Timer {
        id: scrollSelectionTimer
        interval: 1
        repeat: false
        onTriggered: root.ensureSelectedVisible()
    }

    Connections {
        target: root.backend()
        ignoreUnknownSignals: true

        function onAvailableNetworksChanged() {
            root.reloadFromBackend()
        }

        function onSavedNetworksChanged() {
            root.reloadFromBackend()
        }

        function onConnectedNetworkChanged() {
            root.reloadFromBackend()
        }

        function onConnectedSsidChanged() {
            root.reloadFromBackend()
        }

        function onNetworkDetailsChanged() {
            root.reloadFromBackend()
        }

        function onNetworkRevisionChanged() {
            root.reloadFromBackend()
        }

        function onDiagnosticResultsChanged() {
            root.diagnosticsSnapshot = root.normalizedArray(
                root.backendValue(["diagnosticResults"], [])
            )
        }

        function onOperationFinished(action, success, message, payload) {
            root.statusMessage = String(message || "")
            root.statusIsError = !success
            root.armedKey = ""
            root.reloadFromBackend()
        }

        function onOfflineNetworkOperationFinished(success, message) {
            root.statusMessage = String(message || "")
            root.statusIsError = !success
            if (success && root.enableHotspotAfterPassword) {
                root.enableHotspotAfterPassword = false
                root.hotspotActionBackend.setOfflineNetworkMode("wifi-hotspot")
            } else if (!success) {
                root.enableHotspotAfterPassword = false
            }
        }

        function onScanFinished(success, message) {
            root.statusMessage = String(message || "")
            root.statusIsError = !success
            root.reloadFromBackend()
        }

        function onSpeedTestRunningChanged() {
            root.refreshSpeedTestSnapshot()
        }

        function onSpeedTestResultsChanged() {
            root.refreshSpeedTestSnapshot()
        }

        function onSpeedTestStatusChanged() {
            root.refreshSpeedTestSnapshot()
            var text = root.speedTestStatus()
            root.statusMessage = text.toUpperCase()
            root.statusIsError =
                text.toLowerCase().indexOf("failed") >= 0 ||
                text.toLowerCase().indexOf("timed out") >= 0
        }

        function onLastErrorChanged() {
            var errorText = root.cleanText(
                root.backendValue(["lastError"], "")
            )
            if (errorText.length > 0) {
                root.statusMessage = errorText.toUpperCase()
                root.statusIsError = true
            }
        }
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Up)
            action = "up"
        else if (event.key === Qt.Key_Down)
            action = "down"
        else if (event.key === Qt.Key_Left)
            action = "left"
        else if (event.key === Qt.Key_Right)
            action = "right"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace)
            action = "cancel"
        else if (event.key === Qt.Key_F3)
            action = "context"
        else if (event.key === Qt.Key_Menu)
            action = "system"

        if (action.length > 0) {
            handleControllerPressed(action)
            event.accepted = true
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.pointerEnabled
        acceptedButtons: Qt.LeftButton
        onClicked: root.close()
    }

    Rectangle {
        anchors.fill: parent
        visible: root.hotspotPasswordVisible
        enabled: visible
        z: 2900
        color: "#02040cf2"

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.58, 760)
            spacing: 14
            Text { width: parent.width; text: "WI-FI HOTSPOT PASSWORD"; color: root.neutronBlue; font.pixelSize: 24; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            Text { width: parent.width; text: "Create or change the hotspot credential. It is sent only through authenticated local IPC and is never displayed after saving."; color: root.mutedText; font.pixelSize: 13; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
            Repeater {
                model: [
                    { label: "PASSWORD", value: root.hotspotPassword.length ? root.maskedText(root.hotspotPassword.length) : "At least 8 characters" },
                    { label: "CONFIRM PASSWORD", value: root.hotspotPasswordConfirmation.length ? root.maskedText(root.hotspotPasswordConfirmation.length) : "Re-enter password" },
                    { label: "SAVE", value: "" }, { label: "CANCEL", value: "" }
                ]
                Rectangle {
                    required property int index
                    required property var modelData
                    width: parent.width; height: 64; radius: 18
                    color: root.hotspotPasswordFocus === index ? "#12335a" : root.cardColor
                    border.width: root.hotspotPasswordFocus === index ? 3 : 1
                    border.color: root.hotspotPasswordFocus === index ? root.focusBlue : "#1D3958"
                    RowLayout { anchors.fill: parent; anchors.margins: 16
                        Text { Layout.fillWidth: true; text: modelData.label; color: "white"; font.bold: true }
                        Text { text: modelData.value; color: root.mutedText }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { root.hotspotPasswordFocus = index; if (index === 0) root.openKeyboard("hotspotPassword"); else if (index === 1) root.openKeyboard("hotspotConfirmation"); else if (index === 2) root.submitHotspotPassword(); else root.hotspotPasswordVisible = false } }
                }
            }
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1600)
        height: Math.min(parent.height - 60, 990)
        radius: 12
        color: root.panelColor
        border.width: 1
        border.color: "#25313C"

        MouseArea {
            anchors.fill: parent
            enabled: root.pointerEnabled
            acceptedButtons: Qt.LeftButton
            onClicked: function(mouse) { mouse.accepted = true }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 10
            color: root.panelInner
            border.width: 0
            border.color: "transparent"
        }

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 22
            height: 70
            radius: 8
            color: "#081522"
            border.width: 1
            border.color: "#25313C"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "NETWORK CONTROL"
                        color: "white"
                        font.pixelSize: 31
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Text {
                        text: "SCROLLABLE WI-FI, SPEED, DIAGNOSTICS, AND REPAIR"
                        color: root.mutedText
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.9
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 180
                    Layout.preferredHeight: 38
                    radius: 16
                    color: wifiEnabled() ? "#0b3025" : "#3a1118"
                    border.width: 1
                    border.color: wifiEnabled() ? root.successGreen : root.dangerRed

                    Text {
                        anchors.centerIn: parent
                        text: wifiEnabled() ? "WI-FI ENABLED" : "WI-FI DISABLED"
                        color: wifiEnabled() ? root.successGreen : "#ff9aa5"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 180
                    Layout.preferredHeight: 38
                    radius: 16
                    color: connectedSsid().length > 0 ? "#0b3025" : "#34151b"
                    border.width: 1
                    border.color: connectedSsid().length > 0 ? root.neutronBlue : root.dangerRed

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 18
                        text: connectionState()
                        color: connectedSsid().length > 0 ? root.neutronBlue : "#ff9aa5"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.8
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Flickable {
            id: contentFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 14
            anchors.bottomMargin: 12
            clip: true
            contentWidth: width
            contentHeight: contentColumn.height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: contentColumn
                width: contentFlick.width
                spacing: 14

                Rectangle {
                    width: parent.width
                    height: 170
                    radius: 24
                    color: connectedSsid().length > 0 ? "#0a2b24" : "#30151b"
                    border.width: 1
                    border.color: connectedSsid().length > 0 ? root.successGreen : root.dangerRed

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 18

                        Rectangle {
                            Layout.preferredWidth: 122
                            Layout.fillHeight: true
                            radius: 20
                            color: "#081629"
                            border.width: 1
                            border.color: connectedSsid().length > 0 ? root.neutronBlue : root.dangerRed

                            Column {
                                anchors.centerIn: parent
                                spacing: 10

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 5

                                    Repeater {
                                        model: 4

                                        Rectangle {
                                            required property int index
                                            width: 11
                                            height: 15 + index * 9
                                            radius: 3
                                            anchors.bottom: parent.bottom
                                            color: index < Math.ceil(root.currentSignalPercent() / 25)
                                                ? root.neutronBlue
                                                : "#29445f"
                                        }
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.currentSignalPercent() + "%"
                                    color: connectedSsid().length > 0 ? root.neutronBlue : root.dangerRed
                                    font.pixelSize: 22
                                    font.bold: true
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 5

                            Text {
                                Layout.fillWidth: true
                                text: connectedSsid().length > 0 ? connectedSsid() : "No Wi-Fi Connection"
                                color: "white"
                                font.pixelSize: 27
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: connectionState() + "  •  " + currentSecurity() + "  •  " + currentFrequency()
                                color: connectedSsid().length > 0 ? root.successGreen : "#ff9aa5"
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.8
                                elide: Text.ElideRight
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: 3
                                columnSpacing: 12
                                rowSpacing: 7

                                Repeater {
                                    model: [
                                        { "label": "LOCAL IP", "value": root.localIp() },
                                        { "label": "GATEWAY", "value": root.gateway() },
                                        { "label": "TAILSCALE", "value": root.tailscaleIp() },
                                        { "label": "INTERFACE", "value": root.interfaceName() },
                                        { "label": "DNS", "value": root.dnsText() },
                                        { "label": "RADIO", "value": root.wifiEnabled() ? "ON" : "OFF" }
                                    ]

                                    Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        radius: 13
                                        color: "#071526"
                                        border.width: 1
                                        border.color: "#284764"

                                        Column {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 5
                                            spacing: 1

                                            Text {
                                                width: parent.width
                                                text: modelData.label
                                                color: root.mutedText
                                                font.pixelSize: 8
                                                font.bold: true
                                                font.letterSpacing: 0.8
                                            }

                                            Text {
                                                width: parent.width
                                                text: modelData.value
                                                color: "white"
                                                font.pixelSize: 12
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "QUICK NETWORK ACTIONS"
                    color: root.neutronBlue
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.1
                }

                Row {
                    id: quickActionRow
                    width: parent.width
                    height: 96
                    spacing: 12

                    Repeater {
                        id: quickActionRepeater
                        model: root.quickActionCount

                        Rectangle {
                            required property int index
                            width: (quickActionRow.width - quickActionRow.spacing * 3) / 4
                            height: quickActionRow.height
                            radius: 20
                            color: root.armedKey === "wifiOff" && index === 3
                                ? "#46131b"
                                : root.selectedNavIndex === index
                                  ? "#12335a"
                                  : root.cardColor
                            border.width: root.armedKey === "wifiOff" && index === 3
                                ? 4
                                : root.selectedNavIndex === index ? 3 : 1
                            border.color: root.armedKey === "wifiOff" && index === 3
                                ? root.dangerRed
                                : root.selectedNavIndex === index
                                  ? root.focusBlue
                                  : "#1D3958"

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 18
                                spacing: 5

                                Text {
                                    width: parent.width
                                    text: root.quickActionTitle(index)
                                    color: "white"
                                    font.pixelSize: 13
                                    font.bold: true
                                    font.letterSpacing: 0.7
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: root.quickActionSubtitle(index)
                                    color: root.mutedText
                                    font.pixelSize: 9
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.pointerEnabled
                                onClicked: {
                                    root.selectedNavIndex = index
                                    root.activateSelected()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 172
                    radius: 24
                    color: "#0c1b30"
                    border.width: 1
                    border.color: speedTestRunning() ? root.warningGold : root.purple

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "AUTOMATIC SPEED TEST"
                                    color: "white"
                                    font.pixelSize: 20
                                    font.bold: true
                                    font.letterSpacing: 0.9
                                }

                                Text {
                                    text: speedTestStatus()
                                    color: speedTestRunning() ? root.warningGold : root.mutedText
                                    font.pixelSize: 11
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                text: "EVERY 10 MINUTES  •  LAST: " + speedTestLastRun().toUpperCase()
                                color: root.neutronBlue
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 0.7
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            Repeater {
                                model: [
                                    { "label": "DOWNLOAD", "value": root.formatMbps(root.downloadMbps()), "unit": "Mbps" },
                                    { "label": "UPLOAD", "value": root.formatMbps(root.uploadMbps()), "unit": "Mbps" },
                                    { "label": "LATENCY", "value": root.latencyMs() >= 0 ? String(root.latencyMs()) : "--", "unit": "ms" }
                                ]

                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 18
                                    color: "#071526"
                                    border.width: 1
                                    border.color: "#2b5479"

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.label
                                            color: root.mutedText
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.letterSpacing: 0.9
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.value
                                            color: root.neutronBlue
                                            font.pixelSize: 27
                                            font.bold: true
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.unit
                                            color: "#b9d8ee"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "AVAILABLE NETWORKS  •  " + availableSnapshot.length
                    color: root.neutronBlue
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.1
                }

                Column {
                    id: availableColumn
                    width: parent.width
                    spacing: 9

                    Text {
                        width: parent.width
                        height: availableSnapshot.length === 0 ? 54 : 0
                        visible: availableSnapshot.length === 0
                        text: scanning() ? "Scanning for nearby networks…" : "No access points are currently cached. Select SCAN NETWORKS."
                        color: root.mutedText
                        font.pixelSize: 12
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        id: availableRepeater
                        model: root.availableSnapshot

                        Rectangle {
                            required property int index
                            required property var modelData
                            readonly property int navIndex: root.availableStart + index
                            width: availableColumn.width
                            height: 82
                            radius: 19
                            color: root.armedKey === "forget:" + root.networkId(modelData)
                                ? "#46131b"
                                : root.selectedNavIndex === navIndex
                                  ? "#12335a"
                                  : root.cardColor
                            border.width: root.armedKey === "forget:" + root.networkId(modelData)
                                ? 4
                                : root.selectedNavIndex === navIndex ? 3 : 1
                            border.color: root.armedKey === "forget:" + root.networkId(modelData)
                                ? root.dangerRed
                                : root.selectedNavIndex === navIndex
                                  ? root.focusBlue
                                  : root.networkConnected(modelData)
                                    ? root.successGreen
                                    : "#1D3958"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 13
                                spacing: 14

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.networkSsid(modelData)
                                        color: "white"
                                        font.pixelSize: 18
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.networkSecurity(modelData) +
                                              "  •  " + root.networkFrequency(modelData) +
                                              (root.networkSaved(modelData, false) ? "  •  SAVED" : "")
                                        color: root.networkSaved(modelData, false) ? root.purple : root.mutedText
                                        font.pixelSize: 10
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 150
                                    Layout.preferredHeight: 42
                                    radius: 15
                                    color: root.networkConnected(modelData) ? "#0b3025" : "#081629"
                                    border.width: 1
                                    border.color: root.networkConnected(modelData) ? root.successGreen : root.neutronBlue

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.networkConnected(modelData)
                                            ? "X  DISCONNECT"
                                            : "X  CONNECT"
                                        color: root.networkConnected(modelData) ? root.successGreen : root.neutronBlue
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                    }
                                }

                                Column {
                                    Layout.preferredWidth: 82
                                    spacing: 3

                                    Text {
                                        width: parent.width
                                        text: Math.round(root.networkSignal(modelData)) + "%"
                                        color: root.networkSignal(modelData) >= 45 ? root.successGreen : root.warningGold
                                        font.pixelSize: 16
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 7
                                        radius: 4
                                        color: "#243b55"

                                        Rectangle {
                                            width: parent.width * root.networkSignal(modelData) / 100
                                            height: parent.height
                                            radius: parent.radius
                                            color: root.networkSignal(modelData) >= 45 ? root.successGreen : root.warningGold
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.pointerEnabled
                                onClicked: {
                                    root.selectedNavIndex = navIndex
                                    root.activateSelected()
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "SAVED NETWORKS  •  " + savedSnapshot.length
                    color: root.purple
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.1
                }

                Column {
                    id: savedColumn
                    width: parent.width
                    spacing: 9

                    Text {
                        width: parent.width
                        height: savedSnapshot.length === 0 ? 54 : 0
                        visible: savedSnapshot.length === 0
                        text: "No saved Wi-Fi profiles were returned by NetworkManager."
                        color: root.mutedText
                        font.pixelSize: 12
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Repeater {
                        id: savedRepeater
                        model: root.savedSnapshot

                        Rectangle {
                            required property int index
                            required property var modelData
                            readonly property int navIndex: root.savedStart + index
                            width: savedColumn.width
                            height: 80
                            radius: 19
                            color: root.armedKey === "forget:" + root.networkId(modelData)
                                ? "#46131b"
                                : root.selectedNavIndex === navIndex
                                  ? "#12335a"
                                  : root.cardColor
                            border.width: root.armedKey === "forget:" + root.networkId(modelData)
                                ? 4
                                : root.selectedNavIndex === navIndex ? 3 : 1
                            border.color: root.armedKey === "forget:" + root.networkId(modelData)
                                ? root.dangerRed
                                : root.selectedNavIndex === navIndex
                                  ? root.focusBlue
                                  : root.networkConnected(modelData)
                                    ? root.successGreen
                                    : root.purple

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 13
                                spacing: 14

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.networkSsid(modelData)
                                        color: "white"
                                        font.pixelSize: 18
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.networkSecurity(modelData) +
                                              (root.networkHidden(modelData) ? "  •  HIDDEN" : "") +
                                              "  •  TRIANGLE TO ARM FORGET"
                                        color: root.mutedText
                                        font.pixelSize: 10
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 160
                                    Layout.preferredHeight: 42
                                    radius: 15
                                    color: root.networkConnected(modelData) ? "#0b3025" : "#081629"
                                    border.width: 1
                                    border.color: root.networkConnected(modelData) ? root.successGreen : root.neutronBlue

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.networkConnected(modelData)
                                            ? "X  DISCONNECT"
                                            : "X  CONNECT"
                                        color: root.networkConnected(modelData) ? root.successGreen : root.neutronBlue
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.pointerEnabled
                                onClicked: {
                                    root.selectedNavIndex = navIndex
                                    root.activateSelected()
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "OFFLINE WI-FI & LAN HOTSPOTS"
                    color: root.neutronBlue
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.1
                }

                Text {
                    width: parent.width
                    text: "Wi-Fi and LAN offline networks are independent. dnsmasq is optional for each and supplies DHCP plus local DNS addresses to Roku clients. Manual Wi-Fi never scans or switches away until you disable it. Automatic fallback never restarts or reconfigures Tailscale."
                    color: root.mutedText
                    font.pixelSize: 10
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                Column {
                    id: hotspotColumn
                    width: parent.width
                    spacing: 9

                    Repeater {
                        id: hotspotRepeater
                        model: root.hotspotCount

                        Rectangle {
                            required property int index
                            readonly property int navIndex: root.hotspotStart + index
                            width: hotspotColumn.width
                            height: 82
                            radius: 19
                            color: root.selectedNavIndex === navIndex
                                ? "#12335a"
                                : root.cardColor
                            border.width: root.selectedNavIndex === navIndex ? 3 : 1
                            border.color: root.selectedNavIndex === navIndex
                                ? root.focusBlue
                                : index === 0
                                  ? root.successGreen
                                  : index === 1
                                    ? root.warningGold
                                    : index === 2
                                      ? root.neutronBlue
                                      : root.purple

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                spacing: 14

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.hotspotTitle(index)
                                        color: "white"
                                        font.pixelSize: 16
                                        font.bold: true
                                        font.letterSpacing: 0.6
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.hotspotSubtitle(index)
                                        color: root.mutedText
                                        font.pixelSize: 9
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 122
                                    Layout.preferredHeight: 42
                                    radius: 15
                                    color: "#081629"
                                    border.width: 1
                                    border.color: root.selectedNavIndex === navIndex
                                        ? root.focusBlue
                                        : root.neutronBlue

                                    Text {
                                        anchors.centerIn: parent
                                        text: "X  APPLY"
                                        color: root.neutronBlue
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.pointerEnabled
                                onClicked: {
                                    root.selectedNavIndex = navIndex
                                    root.activateSelected()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(150, diagnosticsColumn.height + 36)
                    radius: 24
                    color: "#0c1b30"
                    border.width: 1
                    border.color: diagnosticsRunning() ? root.warningGold : "#1D3958"

                    Column {
                        id: diagnosticsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 18
                        spacing: 8

                        Row {
                            width: parent.width
                            height: 30

                            Text {
                                width: parent.width * 0.55
                                text: "NETWORK DIAGNOSTICS"
                                color: "white"
                                font.pixelSize: 20
                                font.bold: true
                                font.letterSpacing: 0.9
                            }

                            Text {
                                width: parent.width * 0.45
                                text: diagnosticsSummary().toUpperCase()
                                color: diagnosticsRunning() ? root.warningGold : root.neutronBlue
                                font.pixelSize: 10
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            width: parent.width
                            visible: diagnosticsSnapshot.length === 0
                            height: visible ? 44 : 0
                            text: "Run diagnostics to verify NetworkManager, the Wi-Fi interface, route, gateway, Internet reachability, and DNS."
                            color: root.mutedText
                            font.pixelSize: 11
                            font.bold: true
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                        }

                        Repeater {
                            model: root.diagnosticsSnapshot

                            Rectangle {
                                required property var modelData
                                width: diagnosticsColumn.width
                                height: 52
                                radius: 15
                                color: "#071526"
                                border.width: 1
                                border.color: Boolean(modelData.success) ? root.successGreen : root.dangerRed

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 13
                                    anchors.rightMargin: 13
                                    spacing: 12

                                    Text {
                                        Layout.preferredWidth: 190
                                        text: cleanText(modelData.label)
                                        color: "white"
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.preferredWidth: 48
                                        text: Boolean(modelData.success) ? "PASS" : "FAIL"
                                        color: Boolean(modelData.success) ? root.successGreen : root.dangerRed
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: cleanText(modelData.detail)
                                        color: root.mutedText
                                        font.pixelSize: 9
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "DIAGNOSTICS AND REPAIR"
                    color: root.warningGold
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.1
                }

                Column {
                    id: toolColumn
                    width: parent.width
                    spacing: 9

                    Repeater {
                        id: toolRepeater
                        model: root.toolCount

                        Rectangle {
                            required property int index
                            readonly property int navIndex: root.toolStart + index
                            width: toolColumn.width
                            height: 76
                            radius: 19
                            color: root.armedKey === "restartWifiManager" && index === 2
                                ? "#46131b"
                                : root.selectedNavIndex === navIndex
                                  ? "#12335a"
                                  : root.cardColor
                            border.width: root.armedKey === "restartWifiManager" && index === 2
                                ? 4
                                : root.selectedNavIndex === navIndex ? 3 : 1
                            border.color: root.armedKey === "restartWifiManager" && index === 2
                                ? root.dangerRed
                                : root.selectedNavIndex === navIndex
                                  ? root.focusBlue
                                  : index === 2
                                    ? root.dangerRed
                                    : index === 1
                                      ? root.warningGold
                                      : root.neutronBlue

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                spacing: 14

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.toolTitle(index)
                                        color: "white"
                                        font.pixelSize: 16
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.armedKey === "restartWifiManager" && index === 2
                                            ? "PRESS X AGAIN TO RESTART NETWORKMANAGER"
                                            : root.toolSubtitle(index)
                                        color: root.armedKey === "restartWifiManager" && index === 2
                                            ? "#ffb4bc"
                                            : root.mutedText
                                        font.pixelSize: 9
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    text: index === 2 ? "ARMED ACTION" : "X  SELECT"
                                    color: index === 2 ? root.dangerRed : root.neutronBlue
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 0.8
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.pointerEnabled
                                onClicked: {
                                    root.selectedNavIndex = navIndex
                                    root.activateSelected()
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 6
                }
            }

        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 22
            height: 50
            radius: 18
            color: "#09172a"
            border.width: 1
            border.color: "#294b70"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 16

                Text {
                    Layout.fillWidth: true
                    text: root.statusMessage.length > 0
                        ? root.statusMessage
                        : "AUTO SPEED TEST ACTIVE  •  NEXT TEST RUNS ON THE 10-MINUTE BACKEND TIMER"
                    color: root.statusIsError ? "#ff9aa5" : root.successGreen
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.7
                    elide: Text.ElideRight
                }

                Text {
                    text: "D-PAD/STICKS MOVE  •  X SELECT  •  TRIANGLE FORGET  •  O BACK"
                    color: "#9fd8ff"
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 0.6
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.editorVisible
        enabled: visible
        z: 2000
        color: "#02040cf5"

        MouseArea {
            anchors.fill: parent
            enabled: root.pointerEnabled
            onClicked: function(mouse) { mouse.accepted = true }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.60, 940)
            height: Math.min(parent.height * 0.72, 720)
            radius: 32
            color: root.panelColor
            border.width: 2
            border.color: root.neutronBlue

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 13

                Text {
                    Layout.fillWidth: true
                    text: editorMode === "hidden" ? "ADD HIDDEN NETWORK" : "CONNECT TO " + editorSsid.toUpperCase()
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: "Select a field with X. The NeutronOS controller keyboard opens for SSID and password entry."
                    color: root.mutedText
                    font.pixelSize: 11
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: [
                        { "title": "NETWORK NAME / SSID", "value": root.editorSsid.length > 0 ? root.editorSsid : "Select to enter SSID" },
                        { "title": "SECURITY", "value": root.securityOptions[root.editorSecurityIndex] },
                        { "title": "PASSWORD", "value": root.editorPassword.length > 0 ? root.maskedText(root.editorPassword.length) : (root.editorSecurityIndex === 3 ? "Not required" : "Select to enter password") },
                        { "title": "REMEMBER PROFILE", "value": root.editorRemember ? "YES" : "NO" }
                    ]

                    Rectangle {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 72
                        radius: 18
                        color: root.selectedEditorControl === index ? "#12335a" : root.cardColor
                        opacity: root.editorControlEnabled(index) ? 1 : 0.45
                        border.width: root.selectedEditorControl === index ? 3 : 1
                        border.color: root.selectedEditorControl === index ? root.focusBlue : "#1D3958"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18

                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: root.mutedText
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.8
                            }

                            Text {
                                Layout.preferredWidth: parent.width * 0.52
                                text: modelData.value
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.pointerEnabled && root.editorControlEnabled(index)
                            onClicked: {
                                root.selectedEditorControl = index
                                root.activateEditorControl()
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    spacing: 14

                    Repeater {
                        model: [
                            { "index": 4, "title": editorMode === "hidden" ? "ADD AND CONNECT" : "CONNECT" },
                            { "index": 5, "title": "CANCEL" }
                        ]

                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 20
                            color: root.selectedEditorControl === modelData.index ? "#12335a" : root.cardColor
                            border.width: root.selectedEditorControl === modelData.index ? 3 : 1
                            border.color: root.selectedEditorControl === modelData.index ? root.focusBlue : root.neutronBlue

                            Text {
                                anchors.centerIn: parent
                                text: modelData.title
                                color: "white"
                                font.pixelSize: 15
                                font.bold: true
                                font.letterSpacing: 0.8
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.pointerEnabled
                                onClicked: {
                                    root.selectedEditorControl = modelData.index
                                    root.activateEditorControl()
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "UP/DOWN MOVE  •  LEFT/RIGHT CHANGE SECURITY  •  X SELECT  •  O CANCEL"
                    color: "#9fd8ff"
                    font.pixelSize: 9
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.keyboardVisible
        enabled: visible
        z: 3000
        color: "#02040cf7"

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.90, 1320)
            spacing: 12

            Rectangle {
                width: parent.width
                height: 64
                radius: 20
                color: root.panelColor
                border.width: 1
                border.color: root.neutronBlue

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18

                    Text {
                        Layout.fillWidth: true
                        text: root.keyboardField === "hotspotPassword"
                            ? (root.hotspotPassword.length > 0 ? root.maskedText(root.hotspotPassword.length) : "Enter hotspot password")
                            : root.keyboardField === "hotspotConfirmation"
                            ? (root.hotspotPasswordConfirmation.length > 0 ? root.maskedText(root.hotspotPasswordConfirmation.length) : "Confirm hotspot password")
                            : root.keyboardField === "password"
                            ? (root.editorPassword.length > 0 ? root.maskedText(root.editorPassword.length) : "Enter Wi-Fi password")
                            : (root.editorSsid.length > 0 ? root.editorSsid : "Enter network name / SSID")
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "ENTER CLOSES KEYBOARD"
                        color: root.neutronBlue
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            VirtualKeyboard {
                id: networkKeyboard
                width: parent.width
                height: 550
                active: root.keyboardVisible
                cancelBehavior: "close"
                resetOnOpen: false

                onKeyPressed: function(value) {
                    root.appendKeyboardValue(value)
                }

                onBackspacePressed: root.keyboardBackspace()
                onEnterPressed: root.closeKeyboard()
                onClosePressed: root.closeKeyboard()
            }
        }
    }
}
