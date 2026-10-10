import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components" as Shared
import "RemoteSettingsCatalog.js" as RemoteCatalog

Item {
    id: root
    anchors.fill: parent
    focus: true

    signal appExited()
    signal exitRequested()
    signal backgroundRequested()

    property string appId: "neutronremotesystems"
    property string appName: "Neutron Remote Systems"
    property string version: "1.0.3"
    property var transport: (typeof packageAppBridgeManager !== "undefined") ? packageAppBridgeManager : null

    property bool brokerOnline: false
    property string brokerMessage: "Connecting to remote service broker"
    property bool webControllerAvailable: true
    property bool webControllerEnabled: true
    property bool webControllerActive: false
    property string webControllerMode: "CHECKING"
    property string webControllerUrl: "https://remote.neutronos"
    property string webControllerMessage: ""
    property var providers: []
    property int selectedAppIndex: 0
    property int selectedServiceIndex: 0
    property int focusPane: 0                 // 0 apps, 1 right-side categories, 2 header
    property int categoryIndex: 0
    property var settingCategories: ["STATUS", "SERVICES", "ACCESS", "NETWORK", "SECURITY", "ADVANCED"]
    property var systemServices: []
    property int systemServiceIndex: 0
    property int settingIndex: 0
    property var settingRows: categorySettings(categoryIndex)
    property var durationOptions: RemoteCatalog.durationOptions()
    property bool durationOpen: false
    property int durationIndex: 0
    property bool exitOpen: false

    property var providerDescription: ({})
    property var providerSupportedSettings: ({})
    property var providerValues: ({})
    property var providerConstraints: ({})
    property string providerError: ""
    property bool providerLoading: false
    property var startedProviderIds: ({})

    property bool keyboardOpen: false
    property string keyboardText: ""
    property string keyboardSettingKey: ""

    readonly property color bg: "#02050B"
    readonly property color panel: "#07101CEB"
    readonly property color panelRaised: "#0B1726F4"
    readonly property color panelSoft: "#09131FDD"
    readonly property color border: "#20364A"
    readonly property color blue: "#33A7FF"
    readonly property color blueBright: "#64D8FF"
    readonly property color violet: "#8E65FF"
    readonly property color magenta: "#E432FF"
    readonly property color red: "#FF4D63"
    readonly property color green: "#42E69C"
    readonly property color amber: "#FFD166"
    readonly property color textPrimary: "#F2F8FF"
    readonly property color textSecondary: "#AFC2D3"
    readonly property color textMuted: "#6E8497"

    function normalize(action) {
        var a = String(action || "").toLowerCase()
        if (a === "x" || a === "cross" || a === "confirm" || a === "select") return "primary"
        if (a === "o" || a === "circle" || a === "back") return "cancel"
        if (a === "options") return "start"
        return a
    }

    function sharedComponentUrl(name) {
        if (typeof neutronosQmlPath !== "undefined" && String(neutronosQmlPath).length)
            return "file://" + String(neutronosQmlPath) + "/components/" + name
        if (typeof assetManager !== "undefined" && assetManager && assetManager.qmlPath !== undefined)
            return "file://" + String(assetManager.qmlPath) + "/components/" + name
        return ""
    }

    function syncChrome() {
        if (headerLoader.item) {
            headerLoader.item.appTitle = "Neutron Remote Systems"
            headerLoader.item.primaryStatus = brokerOnline ? "Protected" : "Broker Offline"
            headerLoader.item.primaryTone = brokerOnline ? "success" : "danger"
            headerLoader.item.secondaryStatus = providers.length ? String(providers.length) + " REMOTE APPS" : "NO PROVIDERS"
            headerLoader.item.secondaryTone = providers.length ? "info" : "warning"
            headerLoader.item.attention = !brokerOnline
            headerLoader.item.menuFocused = focusPane === 2 && !exitOpen && !durationOpen
        }
        if (footerLoader.item)
            footerLoader.item.hintText = "D-PAD  NAVIGATE   X  SELECT   △  REFRESH   O  BACK"
    }

    function sendGatekeeper(action, values) {
        if (!transport) return false
        var message = values || {}
        message.action = action
        return transport.send(appId, message)
    }

    function openBridge() {
        if (!transport) {
            brokerOnline = false
            brokerMessage = "NeutronOS package bridge is unavailable"
            syncChrome()
            return
        }
        if (!transport.start(appId, "remote-systems-bridge.py")) {
            brokerOnline = false
            brokerMessage = transport.lastError(appId)
            syncChrome()
            return
        }
        sendGatekeeper("open")
    }

    function refreshAll() {
        providerError = ""
        sendGatekeeper("refresh")
    }

    function currentApp() {
        if (!providers || providers.length === 0) return null
        selectedAppIndex = Math.max(0, Math.min(selectedAppIndex, providers.length - 1))
        return providers[selectedAppIndex]
    }

    function currentServices() {
        var app = currentApp()
        return app && app.services ? app.services : []
    }

    function currentService() {
        var services = currentServices()
        if (!services.length) return null
        selectedServiceIndex = Math.max(0, Math.min(selectedServiceIndex, services.length - 1))
        return services[selectedServiceIndex]
    }

    function categorySettings(index) {
        if (index < 2) return []
        var prefixes = index === 2 ? ["remote.", "access."]
                     : index === 3 ? ["network.", "sessions."]
                     : index === 4 ? ["security.", "devices.", "privacy.", "restrictions."]
                     : ["performance.", "logging.", "alerts.", "advanced."]
        var all = RemoteCatalog.rows()
        var result = []
        for (var i = 0; i < all.length; ++i) {
            var row = all[i]
            if (!row || row.kind !== "setting") continue
            var key = String(row.key || "")
            for (var p = 0; p < prefixes.length; ++p) {
                if (key.indexOf(prefixes[p]) === 0) {
                    result.push(row)
                    break
                }
            }
        }
        return result
    }

    function selectCategory(index) {
        categoryIndex = Math.max(0, Math.min(index, settingCategories.length - 1))
        settingIndex = 0
        if (settingsList) {
            settingsList.currentIndex = 0
            if (settingRows.length) settingsList.positionViewAtIndex(0, ListView.Beginning)
        }
    }

    function currentSystemService() {
        if (!systemServices || !systemServices.length) return null
        systemServiceIndex = Math.max(0, Math.min(systemServiceIndex, systemServices.length - 1))
        return systemServices[systemServiceIndex]
    }

    function servicePortText(service) {
        if (!service) return "—"
        var ports = service.ports || []
        var portText = ports.length ? ports.join(", ") : String(service.port || "—")
        return String(service.portMode || "system-default") === "system-default" ? "SYSTEM DEFAULT  •  " + portText : "CUSTOM  •  " + portText
    }

    function activeForText(secondsValue) {
        var seconds = Math.max(0, Number(secondsValue || 0))
        var days = Math.floor(seconds / 86400)
        var hours = Math.floor((seconds % 86400) / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        if (days > 0) return days + "d " + hours + "h"
        if (hours > 0) return hours + "h " + minutes + "m"
        return minutes + "m"
    }

    function openWebControllerPortEditor() {
        var service = currentSystemService()
        if (!service || String(service.id || "") !== "web-controller" || service.portWritable !== true) return
        keyboardSettingKey = "system.web-controller.port"
        keyboardText = String(service.port || 443)
        keyboardOpen = true
        syncKeyboard()
    }

    function resetWebControllerPort() {
        var service = currentSystemService()
        if (!service || String(service.id || "") !== "web-controller") return
        sendGatekeeper("web-controller-port-set", { systemDefault: true })
    }

    function selectedGrant() {
        var app = currentApp()
        return app && app.grant ? app.grant : ({ active: false, enabled: false, durationCode: "", expiresAt: "", remainingSeconds: 0 })
    }

    function providerIcon(appIdValue) {
        if (typeof assetManager !== "undefined" && assetManager && typeof assetManager.appIcon === "function") {
            var found = assetManager.appIcon(String(appIdValue || ""))
            if (found && String(found).length) return found
        }
        return ""
    }

    function updateProviderDescription(message) {
        providerDescription = message || ({})
        providerSupportedSettings = message.supportedSettings || ({})
        providerValues = message.values || ({})
        providerConstraints = message.constraints || ({})
        providerError = ""
        providerLoading = false
    }

    function requestProviderDescription() {
        providerDescription = ({})
        providerSupportedSettings = ({})
        providerValues = ({})
        providerConstraints = ({})
        providerError = ""
        var app = currentApp()
        var service = currentService()
        if (!app || !service) return
        if (!service.bridgeCompatible || !service.helperName) {
            providerError = String(service.bridgeReason || "Remote provider is not compatible with the package bridge")
            return
        }
        if (!transport) {
            providerError = "Package bridge is unavailable"
            return
        }
        var wasRunning = transport.running(app.appId)
        if (!transport.start(app.appId, service.helperName)) {
            providerError = transport.lastError(app.appId)
            return
        }
        if (!wasRunning) {
            var nextStarted = Object.assign({}, startedProviderIds)
            nextStarted[app.appId] = true
            startedProviderIds = nextStarted
        }
        providerLoading = true
        transport.send(app.appId, {
            action: "remote.describe",
            protocol: "neutronos-remote-service",
            protocolVersion: 1,
            capabilityId: service.id
        })
    }

    function refreshProvider() {
        var app = currentApp()
        var service = currentService()
        if (!app || !service || !transport || !transport.running(app.appId)) {
            requestProviderDescription()
            return
        }
        providerLoading = true
        transport.send(app.appId, {
            action: "remote.refresh",
            protocol: "neutronos-remote-service",
            protocolVersion: 1,
            capabilityId: service.id
        })
    }

    function grantFor(durationCode) {
        var app = currentApp()
        if (!app) return
        sendGatekeeper("grant", { appId: app.appId, durationCode: durationCode })
        durationOpen = false
    }

    function revokeSelected(reason) {
        var app = currentApp()
        if (!app) return
        sendGatekeeper("revoke", { appId: app.appId, reason: reason || "manual" })
    }

    function openDuration() {
        if (!currentApp()) return
        var code = String(selectedGrant().durationCode || "")
        durationIndex = 0
        for (var i = 0; i < durationOptions.length; ++i)
            if (durationOptions[i].code === code) durationIndex = i
        durationOpen = true
    }

    function supportMeta(key) {
        var raw = providerSupportedSettings ? providerSupportedSettings[key] : undefined
        if (raw === undefined || raw === null || raw === false) return ({ supported: false, writable: false })
        if (raw === true) return ({ supported: true, writable: true })
        if (typeof raw === "object") {
            var copy = Object.assign({}, raw)
            if (copy.supported === undefined) copy.supported = true
            if (copy.writable === undefined) copy.writable = true
            return copy
        }
        return ({ supported: Boolean(raw), writable: Boolean(raw) })
    }

    function settingSupported(row) {
        if (!row || row.kind !== "setting") return true
        if (row.key === "web.controller.enabled" || row.key === "web.controller.status") return webControllerAvailable
        if (row.central === true) return currentApp() !== null
        return supportMeta(row.key).supported === true
    }

    function settingWritable(row) {
        if (!settingSupported(row)) return false
        if (row.key === "web.controller.enabled") return true
        if (row.key === "web.controller.status") return false
        if (row.central === true) {
            return row.key === "remote.service.enabled" || row.key === "access.activeGrant" ||
                   row.key === "access.duration" || row.key === "access.extend" || row.key === "access.revoke"
        }
        return supportMeta(row.key).writable !== false
    }

    function durationLabel(code) {
        var c = String(code || "")
        for (var i = 0; i < durationOptions.length; ++i)
            if (durationOptions[i].code === c) return durationOptions[i].label
        return "NOT SET"
    }

    function remainingText() {
        var heartbeat = tick.text
        var grant = selectedGrant()
        if (!grant.active) return "INACTIVE"
        if (grant.durationCode === "indefinite") return "INDEFINITE"
        var end = Date.parse(String(grant.expiresAt || ""))
        if (isNaN(end)) return "--"
        var seconds = Math.max(0, Math.floor((end - Date.now()) / 1000))
        var hours = Math.floor(seconds / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        var secs = seconds % 60
        return (hours > 0 ? String(hours) + "h " : "") + String(minutes) + "m " + String(secs) + "s"
    }

    function centralValue(key) {
        var grant = selectedGrant()
        if (key === "web.controller.enabled") return webControllerEnabled ? "ON" : "OFF"
        if (key === "web.controller.status") {
            if (!webControllerAvailable) return "UNAVAILABLE"
            if (!webControllerEnabled) return "OFF"
            if (!webControllerActive) return "STARTING"
            return String(webControllerMode || "ONLINE").toUpperCase() + "  •  " + webControllerUrl
        }
        if (key === "remote.service.enabled") return grant.active === true
        if (key === "remote.service.status") {
            if (!providerDescription || providerDescription.serviceAvailable === false) return "UNAVAILABLE"
            if (providerDescription.serviceRunning === true) return "RUNNING"
            return grant.active ? "AUTHORIZED / STOPPED" : "STOPPED"
        }
        if (key === "remote.service.appSideEnabled") {
            if (!providerDescription || providerDescription.appRemoteEnabled === undefined) return "UNKNOWN"
            return providerDescription.appRemoteEnabled === true ? "ON" : "OFF"
        }
        if (key === "access.activeGrant" || key === "access.duration") return durationLabel(grant.durationCode)
        if (key === "access.timeRemaining") return remainingText()
        if (key === "access.expiration") return grant.durationCode === "indefinite" ? "INDEFINITE" : String(grant.expiresAt || "NOT SET")
        if (key === "access.extend") return "PRESS X"
        if (key === "access.revoke") return grant.active ? "PRESS X" : "INACTIVE"
        return ""
    }

    function settingValue(row) {
        if (!row || row.kind !== "setting") return ""
        if (row.central === true) return centralValue(row.key)
        var value = providerValues ? providerValues[row.key] : undefined
        if (value === undefined || value === null) return "--"
        if (typeof value === "boolean") return value ? "ON" : "OFF"
        if (Array.isArray(value)) return value.join(", ")
        if (typeof value === "object") return JSON.stringify(value)
        return String(value)
    }

    function sendProviderSet(key, value) {
        var app = currentApp()
        var service = currentService()
        if (!app || !service || !transport) return
        if (!transport.running(app.appId) && !transport.start(app.appId, service.helperName)) {
            providerError = transport.lastError(app.appId)
            return
        }
        transport.send(app.appId, {
            action: "remote.set",
            protocol: "neutronos-remote-service",
            protocolVersion: 1,
            capabilityId: service.id,
            key: key,
            value: value
        })
    }

    function sendProviderInvoke(key) {
        var app = currentApp()
        var service = currentService()
        if (!app || !service || !transport) return
        transport.send(app.appId, {
            action: "remote.invoke",
            protocol: "neutronos-remote-service",
            protocolVersion: 1,
            capabilityId: service.id,
            key: key
        })
    }

    function openTextEditor(key) {
        keyboardSettingKey = key
        var value = providerValues ? providerValues[key] : ""
        keyboardText = value === undefined || value === null ? "" : String(value)
        keyboardOpen = true
        syncKeyboard()
    }

    function syncKeyboard() {
        if (!keyboardLoader.item) return
        keyboardLoader.item.title = keyboardSettingKey === "system.web-controller.port" ? "WEB CONTROLLER PORT" : "REMOTE SETTING"
        keyboardLoader.item.visibleMode = keyboardOpen
        keyboardLoader.item.active = keyboardOpen
        keyboardLoader.item.selectedIndex = 0
    }

    function activateSetting(row, delta) {
        if (!row || row.kind !== "setting" || !settingWritable(row)) return
        if (row.central === true) {
            if (row.key === "web.controller.enabled") {
                sendGatekeeper("web-controller-set", { enabled: !webControllerEnabled })
            } else if (row.key === "remote.service.enabled") {
                if (selectedGrant().active) revokeSelected("manual")
                else openDuration()
            } else if (row.key === "access.activeGrant" || row.key === "access.duration" || row.key === "access.extend") {
                openDuration()
            } else if (row.key === "access.revoke") {
                if (selectedGrant().active) revokeSelected("manual")
            }
            return
        }
        var meta = supportMeta(row.key)
        var editor = String(meta.type || row.editor || "value").toLowerCase()
        var current = providerValues ? providerValues[row.key] : undefined
        if (editor === "boolean" || editor === "toggle") {
            sendProviderSet(row.key, !(current === true))
        } else if (editor === "enum" || editor === "choice") {
            var options = meta.options || []
            if (!options.length) return
            var index = options.indexOf(current)
            if (index < 0) index = 0
            index = (index + (delta < 0 ? -1 : 1) + options.length) % options.length
            sendProviderSet(row.key, options[index])
        } else if (editor === "number") {
            var step = Number(meta.step === undefined ? 1 : meta.step)
            var value = Number(current === undefined ? (meta.minimum === undefined ? 0 : meta.minimum) : current)
            value += (delta < 0 ? -step : step)
            if (meta.minimum !== undefined) value = Math.max(Number(meta.minimum), value)
            if (meta.maximum !== undefined) value = Math.min(Number(meta.maximum), value)
            sendProviderSet(row.key, value)
        } else if (editor === "text" || editor === "string") {
            openTextEditor(row.key)
        } else if (editor === "action") {
            sendProviderInvoke(row.key)
        }
    }

    function clampSettingIndex(direction) {
        if (!settingRows.length) { settingIndex = 0; return }
        var i = Math.max(0, Math.min(settingIndex, settingRows.length - 1))
        while (i >= 0 && i < settingRows.length && settingRows[i].kind === "section") i += direction
        if (i < 0 || i >= settingRows.length) {
            i = Math.max(0, Math.min(settingIndex, settingRows.length - 1))
            while (i >= 0 && i < settingRows.length && settingRows[i].kind === "section") i -= direction
        }
        settingIndex = Math.max(0, Math.min(i, settingRows.length - 1))
        settingsList.currentIndex = settingIndex
        settingsList.positionViewAtIndex(settingIndex, ListView.Contain)
    }

    function selectApp(index) {
        selectedAppIndex = Math.max(0, Math.min(index, Math.max(0, providers.length - 1)))
        selectedServiceIndex = 0
        appList.currentIndex = selectedAppIndex
        if (providers.length) appList.positionViewAtIndex(selectedAppIndex, ListView.Contain)
        requestProviderDescription()
    }

    function openExitModal() {
        exitOpen = true
        syncChrome()
        referenceExitModal.openModal(root)
    }

    function handleControllerPressed(action) {
        var a = normalize(action)
        if (keyboardOpen) {
            if (keyboardLoader.item && typeof keyboardLoader.item.handleControllerPressed === "function")
                keyboardLoader.item.handleControllerPressed(a)
            return true
        }
        if (durationOpen) {
            if (a === "cancel") durationOpen = false
            else if (a === "up") durationIndex = Math.max(0, durationIndex - 1)
            else if (a === "down") durationIndex = Math.min(durationOptions.length - 1, durationIndex + 1)
            else if (a === "primary") grantFor(durationOptions[durationIndex].code)
            return true
        }
        if (exitOpen) {
            return referenceExitModal.handleController(a)
        }
        if (a === "triangle" || a === "context") { refreshAll(); return true }
        if (a === "cancel") { openExitModal(); return true }
        if (focusPane === 2) {
            if (a === "down" || a === "cancel") focusPane = 0
            else if (a === "primary") openExitModal()
            syncChrome()
            return true
        }
        if (a === "up" && focusPane === 0 && selectedAppIndex === 0) {
            focusPane = 2; syncChrome(); return true
        }
        if (a === "left") {
            if (focusPane === 1 && categoryIndex > 0) selectCategory(categoryIndex - 1)
            else if (focusPane === 1) focusPane = 0
            else if (focusPane === 0 && currentServices().length > 1) {
                selectedServiceIndex = (selectedServiceIndex + currentServices().length - 1) % currentServices().length
                requestProviderDescription()
            }
            return true
        }
        if (a === "right") {
            if (focusPane === 0) focusPane = 1
            else if (focusPane === 1 && categoryIndex < settingCategories.length - 1) selectCategory(categoryIndex + 1)
            return true
        }
        if (focusPane === 0) {
            if (a === "up" && providers.length) selectApp(selectedAppIndex - 1)
            else if (a === "down" && providers.length) selectApp(selectedAppIndex + 1)
            else if (a === "primary" && currentApp()) {
                if (selectedGrant().active) revokeSelected("manual")
                else openDuration()
            }
            return true
        }
        if (focusPane === 1) {
            if (a === "l1") { selectCategory(categoryIndex - 1); return true }
            if (a === "r1") { selectCategory(categoryIndex + 1); return true }
            if (categoryIndex === 0) {
                if (a === "primary") openWebControllerPortEditor()
                else if (a === "square") resetWebControllerPort()
                return true
            }
            if (categoryIndex === 1) {
                if (a === "up") systemServiceIndex = Math.max(0, systemServiceIndex - 1)
                else if (a === "down") systemServiceIndex = Math.min(systemServices.length - 1, systemServiceIndex + 1)
                else if (a === "primary" && systemServices.length) selectCategory(0)
                if (systemServiceList && systemServices.length) systemServiceList.positionViewAtIndex(systemServiceIndex, ListView.Contain)
                return true
            }
            if (a === "up" && settingRows.length) { settingIndex = Math.max(0, settingIndex - 1); clampSettingIndex(-1) }
            else if (a === "down" && settingRows.length) { settingIndex = Math.min(settingRows.length - 1, settingIndex + 1); clampSettingIndex(1) }
            else if (a === "primary" && settingRows.length) activateSetting(settingRows[settingIndex], 1)
            else if (a === "square" && categoryIndex === 0) resetWebControllerPort()
            return true
        }
        return true
    }

    function handleControllerReleased(action) { return true }

    onBrokerOnlineChanged: syncChrome()
    onProvidersChanged: syncChrome()
    onFocusPaneChanged: syncChrome()
    onExitOpenChanged: syncChrome()

    Component.onCompleted: {
        categoryIndex = 0
        settingIndex = 0
        syncChrome()
        openBridge()
    }

    Component.onDestruction: {
        if (transport) transport.stop(appId)
    }

    Connections {
        target: root.transport
        ignoreUnknownSignals: true
        function onStateChanged(id, running, error) {
            if (id === root.appId && !running && String(error || "").length) {
                root.brokerOnline = false
                root.brokerMessage = String(error)
            }
        }
        function onMessageReceived(id, message) {
            if (id === root.appId) {
                var type = String(message.type || "")
                if (type === "broker-state") {
                    root.brokerOnline = message.online === true
                    root.brokerMessage = String(message.message || "")
                } else if (type === "providers") {
                    root.providers = message.providers || []
                    if (root.providers.length === 0) {
                        root.selectedAppIndex = 0
                        root.providerDescription = ({})
                        root.providerSupportedSettings = ({})
                        root.providerValues = ({})
                    } else {
                        root.selectedAppIndex = Math.min(root.selectedAppIndex, root.providers.length - 1)
                        root.requestProviderDescription()
                    }
                } else if (type === "system-services") {
                    root.systemServices = message.services || []
                    root.systemServiceIndex = Math.max(0, Math.min(root.systemServiceIndex, Math.max(0, root.systemServices.length - 1)))
                } else if (type === "grant-updated") {
                    root.refreshAll()
                } else if (type === "web-controller") {
                    root.webControllerAvailable = message.available !== false
                    root.webControllerEnabled = message.enabled === true
                    root.webControllerActive = message.active === true
                    root.webControllerMode = String(message.mode || (root.webControllerActive ? "ONLINE" : "OFFLINE"))
                    root.webControllerUrl = String(message.url || "https://remote.neutronos")
                    root.webControllerMessage = String(message.message || "")
                } else if (type === "error") {
                    root.brokerMessage = String(message.message || "Remote Systems error")
                }
                root.syncChrome()
                return
            }
            var app = root.currentApp()
            if (!app || id !== app.appId) return
            var providerType = String(message.type || "")
            if (providerType === "remote-description") {
                var service = root.currentService()
                if (!service || String(message.capabilityId || service.id) !== String(service.id)) return
                if (Number(message.protocolVersion || 0) !== 1) {
                    root.providerError = "Provider protocol version is not supported"
                    root.providerLoading = false
                    return
                }
                root.updateProviderDescription(message)
            } else if (providerType === "remote-setting-updated") {
                var values = Object.assign({}, root.providerValues)
                values[String(message.key || "")] = message.value
                root.providerValues = values
            } else if (providerType === "error") {
                root.providerError = String(message.message || "Provider error")
                root.providerLoading = false
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        onTriggered: tick.text = String(Date.now())
    }
    Timer {
        interval: 10000
        repeat: true
        running: root.visible && root.brokerOnline
        onTriggered: root.sendGatekeeper("refresh")
    }
    Text { id: tick; visible: false; text: "0" }

    Rectangle { anchors.fill: parent; color: root.bg }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B1020" }
            GradientStop { position: 0.47; color: "#030812" }
            GradientStop { position: 1.0; color: "#120516" }
        }
        opacity: 0.94
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#112F6B55" }
            GradientStop { position: 0.52; color: "#00000000" }
            GradientStop { position: 1.0; color: "#69113855" }
        }
    }

    Loader {
        id: headerLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 54
        z: 100
        source: root.sharedComponentUrl("ReferenceAppHeader.qml")
        onLoaded: root.syncChrome()
    }
    Connections {
        target: headerLoader.item
        ignoreUnknownSignals: true
        function onMenuRequested() { root.focusPane = 2; root.openExitModal() }
    }

    Loader {
        id: footerLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 72
        z: 100
        source: root.sharedComponentUrl("ReferenceAppFooter.qml")
        onLoaded: root.syncChrome()
    }

    Row {
        id: mainRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerLoader.bottom
        anchors.bottom: footerLoader.top
        anchors.margins: 20
        spacing: 18

        Rectangle {
            id: leftPanel
            width: Math.max(470, Math.min(620, mainRow.width * 0.34))
            height: mainRow.height
            radius: 24
            color: root.panel
            border.width: root.focusPane === 0 ? 2 : 1
            border.color: root.focusPane === 0 ? root.blueBright : root.border
            clip: true

            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 92; color: "#0A1625"
                border.width: 0
                Text {
                    anchors.centerIn: parent
                    text: "REMOTE SERVICES AVAILABLE"
                    color: root.textPrimary
                    font.pixelSize: 21
                    font.bold: true
                    font.letterSpacing: 1.5
                }
            }

            ListView {
                id: appList
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.topMargin: 104
                anchors.bottom: leftFooter.top; anchors.bottomMargin: 10
                anchors.leftMargin: 12; anchors.rightMargin: 12
                model: root.providers
                currentIndex: root.selectedAppIndex
                spacing: 10
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: appList.width
                    height: 92
                    radius: 18
                    color: index === root.selectedAppIndex ? "#102741" : "#07131F"
                    border.width: index === root.selectedAppIndex ? 2 : 1
                    border.color: index === root.selectedAppIndex ? root.blueBright : "#1B3245"

                    Image {
                        id: appIcon
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 62; height: 62
                        source: root.providerIcon(modelData.appId)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Rectangle {
                        visible: !appIcon.source || String(appIcon.source).length === 0
                        anchors.fill: appIcon
                        radius: 15
                        color: "#13263A"
                        Text { anchors.centerIn: parent; text: "N"; color: root.blueBright; font.pixelSize: 28; font.bold: true }
                    }

                    Column {
                        anchors.left: appIcon.right; anchors.leftMargin: 14
                        anchors.right: gateToggle.left; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Text {
                            width: parent.width
                            text: String(modelData.name || modelData.appId)
                            color: root.textPrimary
                            font.pixelSize: 19
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: (modelData.services ? modelData.services.length : 0) + " REMOTE SERVICE" + ((modelData.services && modelData.services.length === 1) ? "" : "S")
                            color: root.textMuted
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                    }

                    Rectangle {
                        id: gateToggle
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 74; height: 36; radius: 18
                        property bool active: modelData.grant && modelData.grant.active === true
                        color: active ? "#0B3427" : "#32131A"
                        border.width: 1
                        border.color: active ? root.green : root.red
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            anchors.verticalCenter: parent.verticalCenter
                            x: gateToggle.active ? gateToggle.width - width - 4 : 4
                            color: gateToggle.active ? root.green : root.red
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom; anchors.topMargin: 4
                            text: gateToggle.active ? "ON" : "OFF"
                            color: gateToggle.active ? root.green : root.red
                            font.pixelSize: 11; font.bold: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.selectApp(index); root.focusPane = 0 }
                        onDoubleClicked: {
                            root.selectApp(index)
                            if (modelData.grant && modelData.grant.active) root.revokeSelected("manual")
                            else root.openDuration()
                        }
                    }
                }

                Text {
                    visible: root.providers.length === 0
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.brokerOnline
                          ? "No installed app currently advertises a signed neutronos-remote-service capability.\n\nRemote-capable apps will appear here automatically."
                          : "Remote service broker is offline.\n\n" + root.brokerMessage
                    color: root.brokerOnline ? root.textSecondary : root.red
                    font.pixelSize: 18
                    lineHeight: 1.35
                }
            }

            Rectangle {
                id: leftFooter
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 76
                color: "#07111D"
                border.width: 0
                Row {
                    anchors.centerIn: parent
                    spacing: 12
                    Rectangle { width: 9; height: 9; radius: 5; color: root.brokerOnline ? root.green : root.red }
                    Text {
                        text: root.brokerOnline ? "SECURITY BROKER ONLINE" : "SECURITY BROKER OFFLINE"
                        color: root.brokerOnline ? root.green : root.red
                        font.pixelSize: 13; font.bold: true; font.letterSpacing: 1.1
                    }
                }
            }
        }

        Rectangle {
            id: rightPanel
            width: mainRow.width - leftPanel.width - mainRow.spacing
            height: mainRow.height
            radius: 24
            color: root.panel
            border.width: root.focusPane === 1 ? 2 : 1
            border.color: root.focusPane === 1 ? root.magenta : root.border
            clip: true

            Rectangle {
                id: categoryHeader
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 88
                color: "#081522"
                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Repeater {
                        model: root.settingCategories
                        Rectangle {
                            required property string modelData
                            required property int index
                            width: Math.max(104, categoryLabel.implicitWidth + 30)
                            height: 44
                            radius: 18
                            color: root.categoryIndex === index ? "#183453" : "#0A1723"
                            border.width: root.categoryIndex === index ? 2 : 1
                            border.color: root.categoryIndex === index ? root.blueBright : "#23384A"
                            Text {
                                id: categoryLabel
                                anchors.centerIn: parent
                                text: modelData
                                color: root.categoryIndex === index ? root.blueBright : root.textSecondary
                                font.pixelSize: 13
                                font.bold: true
                                font.letterSpacing: 0.8
                            }
                            MouseArea { anchors.fill: parent; onClicked: { root.focusPane = 1; root.selectCategory(index) } }
                        }
                    }
                }
            }

            Item {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: categoryHeader.bottom; anchors.bottom: parent.bottom

                Item {
                    id: statusView
                    visible: root.categoryIndex === 0
                    anchors.fill: parent
                    property var service: root.currentSystemService()

                    Rectangle {
                        visible: !parent.service || parent.service.online !== true
                        anchors.fill: parent
                        anchors.margins: 24
                        radius: 24
                        color: "#45101820"
                        border.width: 2; border.color: root.red
                        Column {
                            anchors.centerIn: parent
                            spacing: 18
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "OFFLINE"; color: root.red; font.pixelSize: 58; font.bold: true; font.letterSpacing: 5 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: statusView.service ? String(statusView.service.name || "SERVICE") : "NO SERVICE SELECTED"; color: root.textPrimary; font.pixelSize: 24; font.bold: true }
                            Text { width: 620; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: statusView.service && statusView.service.enabled === false ? "This service is disabled." : "No active external listener is currently available for this service."; color: root.textSecondary; font.pixelSize: 16 }
                        }
                    }

                    Column {
                        visible: parent.service && parent.service.online === true
                        anchors.fill: parent
                        anchors.margins: 28
                        spacing: 22
                        Text {
                            width: parent.width
                            text: statusView.service ? String(statusView.service.name || "SYSTEM SERVICE") : "SYSTEM SERVICE"
                            color: root.textPrimary; font.pixelSize: 30; font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            width: parent.width
                            text: statusView.service ? String(statusView.service.source || "NeutronOS") : "NeutronOS"
                            color: root.textMuted; font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Row {
                            width: parent.width
                            spacing: 16
                            Repeater {
                                model: [
                                    { label: "STATUS", value: "ONLINE", tone: root.green },
                                    { label: "ACTIVE FOR", value: root.activeForText(statusView.service ? statusView.service.activeSeconds : 0), tone: root.blueBright },
                                    { label: "PORT", value: root.servicePortText(statusView.service), tone: root.magenta }
                                ]
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: (parent.width - 32) / 3
                                    height: 150; radius: 22
                                    color: "#0A1725"
                                    border.width: index === 2 && statusView.service && statusView.service.portWritable === true ? 2 : 1
                                    border.color: index === 2 && statusView.service && statusView.service.portWritable === true ? root.magenta : "#23384A"
                                    Column {
                                        anchors.centerIn: parent; spacing: 12
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.textMuted; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.1 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; width: parent.parent.width - 24; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: modelData.value; color: modelData.tone; font.pixelSize: index === 2 ? 18 : 26; font.bold: true }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: index === 2 && root.currentSystemService() && root.currentSystemService().portWritable === true
                                        onClicked: root.openWebControllerPortEditor()
                                    }
                                }
                            }
                        }
                        Rectangle {
                            width: parent.width; height: 96; radius: 18
                            color: "#08131F"; border.width: 1; border.color: "#20364A"
                            Column {
                                anchors.centerIn: parent; spacing: 7
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: statusView.service && statusView.service.portWritable === true ? "X  CHANGE PORT    •    □  SYSTEM DEFAULT" : "PORT CONTROLLED BY SYSTEM DEFAULT"; color: statusView.service && statusView.service.portWritable === true ? root.blueBright : root.textMuted; font.pixelSize: 14; font.bold: true }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: statusView.service && statusView.service.portWritable === true ? "Web Controller Service is managed through Neutron Remote Systems." : "This service is displayed here but its port remains owned by its native service configuration."; color: root.textSecondary; font.pixelSize: 13 }
                            }
                        }
                    }
                }

                Item {
                    visible: root.categoryIndex === 1
                    anchors.fill: parent
                    Column {
                        anchors.fill: parent; anchors.margins: 22; spacing: 12
                        Text { width: parent.width; text: "EXTERNALLY LISTENING SYSTEM SERVICES"; color: root.blueBright; font.pixelSize: 15; font.bold: true; font.letterSpacing: 1.2; horizontalAlignment: Text.AlignHCenter }
                        Text { width: parent.width; text: "Web Controller is managed here. Other services are discovered from the live system and remain SYSTEM DEFAULT unless their provider exposes safe port control."; color: root.textSecondary; font.pixelSize: 14; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                        ListView {
                            id: systemServiceList
                            width: parent.width; height: parent.height - 78
                            model: root.systemServices
                            currentIndex: root.systemServiceIndex
                            spacing: 8; clip: true
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: systemServiceList.width; height: 76; radius: 17
                                color: index === root.systemServiceIndex ? "#172B43" : "#08131F"
                                border.width: index === root.systemServiceIndex ? 2 : 1
                                border.color: index === root.systemServiceIndex ? root.blueBright : "#20364A"
                                Row {
                                    anchors.fill: parent; anchors.margins: 14; spacing: 14
                                    Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: modelData.online === true ? root.green : root.red }
                                    Column {
                                        width: parent.width - 260; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                        Text { width: parent.width; text: String(modelData.name || modelData.id || "Service"); color: root.textPrimary; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight }
                                        Text { width: parent.width; text: String(modelData.source || "System") + "  •  " + String(modelData.detail || ""); color: root.textMuted; font.pixelSize: 13; elide: Text.ElideRight }
                                    }
                                    Column {
                                        width: 210; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                        Text { anchors.right: parent.right; text: modelData.online === true ? "ONLINE" : "OFFLINE"; color: modelData.online === true ? root.green : root.red; font.pixelSize: 13; font.bold: true }
                                        Text { anchors.right: parent.right; text: root.servicePortText(modelData); color: root.blueBright; font.pixelSize: 13; font.bold: true }
                                    }
                                }
                                MouseArea { anchors.fill: parent; onClicked: { root.focusPane = 1; root.systemServiceIndex = index }
onDoubleClicked: { root.systemServiceIndex = index; root.selectCategory(0) } }
                            }
                        }
                    }
                }

                ListView {
                    id: settingsList
                    visible: root.categoryIndex >= 2
                    anchors.fill: parent
                    anchors.margins: 16
                    model: root.settingRows
                    currentIndex: root.settingIndex
                    spacing: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: settingsList.width; height: 62; radius: 14
                        property bool selected: root.focusPane === 1 && root.settingIndex === index
                        property bool supported: root.settingSupported(modelData)
                        property bool writable: root.settingWritable(modelData)
                        color: selected ? "#172239" : (supported ? "#08131F" : "#070B11")
                        border.width: selected ? 2 : 1
                        border.color: selected ? root.magenta : (supported ? "#1B3042" : "#111A22")
                        opacity: supported ? 1.0 : 0.34
                        Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.56; text: String(modelData.label || ""); color: parent.supported ? root.textPrimary : root.textMuted; font.pixelSize: 16; font.bold: parent.selected; elide: Text.ElideRight }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(300, Math.max(120, settingValueText.implicitWidth + 32)); height: 36; radius: 18
                            color: parent.supported ? (parent.writable ? "#0D2233" : "#0B151F") : "#0B0D11"
                            border.width: 1; border.color: parent.supported ? (parent.writable ? root.blue : "#27333C") : "#20252A"
                            Text { id: settingValueText; anchors.centerIn: parent; width: Math.min(270, implicitWidth); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: parent.parent.supported ? root.settingValue(modelData) : "UNAVAILABLE"; color: parent.parent.supported ? (parent.parent.writable ? root.blueBright : root.textSecondary) : root.textMuted; font.pixelSize: 12; font.bold: true }
                        }
                        MouseArea { anchors.fill: parent; enabled: parent.supported; onClicked: { root.focusPane = 1; root.settingIndex = index; settingsList.currentIndex = index }
onDoubleClicked: root.activateSetting(modelData, 1) }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.durationOpen
        anchors.fill: parent
        z: 300
        color: "#B8000000"
        Rectangle {
            anchors.centerIn: parent
            width: 600; height: 650
            radius: 28
            color: "#07111DF7"
            border.width: 2; border.color: root.blueBright
            Column {
                anchors.fill: parent; anchors.margins: 26; spacing: 12
                Text { width: parent.width; text: "REMOTE ACCESS DURATION"; color: root.textPrimary; font.pixelSize: 26; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: root.currentApp() ? String(root.currentApp().name || root.currentApp().appId) : ""; color: root.textSecondary; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter }
                Item { width: 1; height: 10 }
                Repeater {
                    model: root.durationOptions
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: parent.width; height: 68; radius: 16
                        color: index === root.durationIndex ? "#163753" : "#0A1723"
                        border.width: index === root.durationIndex ? 2 : 1
                        border.color: index === root.durationIndex ? root.blueBright : "#23384A"
                        Text { anchors.centerIn: parent; text: modelData.label; color: index === root.durationIndex ? root.blueBright : root.textPrimary; font.pixelSize: 18; font.bold: true; font.letterSpacing: 1.0 }
                        MouseArea { anchors.fill: parent; onClicked: { root.durationIndex = index; root.grantFor(modelData.code) } }
                    }
                }
                Text { width: parent.width; text: "The provider still needs its own app-side Remote setting enabled. This grant cannot override the app."; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; color: root.amber; font.pixelSize: 13 }
            }
        }
    }

    Shared.ReferenceExitModal {
        id: referenceExitModal
        appName: root.appName
        onExitRequested: { root.exitOpen = false; root.exitRequested() }
        onLeaveRunningRequested: { root.exitOpen = false; root.backgroundRequested() }
        onDismissed: { root.exitOpen = false; root.syncChrome(); root.forceActiveFocus() }
    }

Loader {
        id: keyboardLoader
        visible: root.keyboardOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footerLoader.top
        height: Math.min(460, parent.height * 0.43)
        z: 400
        source: root.keyboardOpen ? root.sharedComponentUrl("VirtualKeyboard.qml") : ""
        onLoaded: root.syncKeyboard()
    }
    Connections {
        target: keyboardLoader.item
        ignoreUnknownSignals: true
        function onKeyPressed(value) { root.keyboardText += String(value) }
        function onBackspacePressed() { if (root.keyboardText.length) root.keyboardText = root.keyboardText.slice(0, -1) }
        function onClearAllRequested() { root.keyboardText = "" }
        function onEnterPressed() {
            if (root.keyboardSettingKey === "system.web-controller.port") {
                var port = Number(root.keyboardText)
                if (isNaN(port) || port < 1 || port > 65535 || Math.floor(port) !== port) {
                    root.brokerMessage = "Port must be a whole number from 1 to 65535"
                    return
                }
                root.sendGatekeeper("web-controller-port-set", { port: port, systemDefault: false })
            } else {
                root.sendProviderSet(root.keyboardSettingKey, root.keyboardText)
            }
            root.keyboardOpen = false
            root.syncKeyboard()
        }
        function onClosePressed() { root.keyboardOpen = false; root.syncKeyboard() }
    }

    Rectangle {
        visible: root.keyboardOpen
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: keyboardLoader.top
        height: 58; z: 401
        color: "#07111DF8"
        border.width: 1; border.color: root.blue
        Text { anchors.fill: parent; anchors.margins: 12; text: root.keyboardText.length ? root.keyboardText : "Enter value"; color: root.textPrimary; font.pixelSize: 18; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    }
}
