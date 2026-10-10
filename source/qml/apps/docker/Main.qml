import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components" as Shared

Item {
    id: app
    anchors.fill: parent
    focus: true

    property string appId: "docker"
    property string appName: "Docker"
    property var appData: ({})
    property var activeUser: null
    property bool developerModeEnabled: false
    property bool hostActive: true
    property var backend: (typeof dockerManager !== "undefined") ? dockerManager : null
    property var controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
    property var privilegeBackend: (typeof privilegeManager !== "undefined") ? privilegeManager : null
    property var securityBackend: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null
    property var appBackend: (typeof appManager !== "undefined") ? appManager : null

    signal exitRequested()
    signal backgroundRequested()

    property bool lightMode: false
    // 0 container list, 1 action rail, 2 header menu.
    property int focusZone: 0
    property int selectedIndex: 0
    property bool engineCardSelected: true
    property int actionIndex: 0
    property var selectedDetails: ({})
    property bool engineVisible: false
    property int engineFocus: 0
    property bool adminAwaitingPassword: false
    property string adminAction: ""
    property string adminPassword: ""
    property string adminMessage: ""
    property string armedId: ""
    property bool exitVisible: false
    property int exitChoice: 0
    property bool formVisible: false
    property string formMode: "create"
    property int formFocus: 0
    property bool presetVisible: false
    property int presetFocus: 0
    property int selectedPresetIndex: 0
    property string keyboardTarget: ""
    property string fieldName: ""
    property string fieldImage: ""
    property string fieldRestart: "no"
    property string fieldPorts: ""
    property string fieldVolumes: ""
    property string fieldEnvironment: ""
    property string fieldCommand: ""
    property string fieldCpus: "1.00"
    property string fieldMemory: "512m"
    property string editingId: ""
    property bool removeArmed: false
    property string localMessage: ""
    readonly property var dockerPresets: [
        {
            id: "custom", name: "Custom", description: "Start with an empty container form.",
            containerName: "", image: "", restart: "no", ports: "", volumes: "", environment: "", command: ""
        },
        {
            id: "portainer", name: "Portainer CE", description: "Web-based Docker administration with persistent configuration.",
            containerName: "portainer", image: "portainer/portainer-ce:latest", restart: "no",
            ports: "9000:9000\n9443:9443", volumes: "/var/run/docker.sock:/var/run/docker.sock\nneutronos_portainer_data:/data", environment: "", command: ""
        },
        {
            id: "jellyfin", name: "Jellyfin", description: "Media server preset. Edit the media volume before creation.",
            containerName: "jellyfin", image: "jellyfin/jellyfin:latest", restart: "no",
            ports: "8096:8096", volumes: "neutronos_jellyfin_config:/config\nneutronos_jellyfin_cache:/cache\nneutronos_media:/media", environment: "", command: ""
        },
        {
            id: "qbittorrent", name: "qBittorrent", description: "LinuxServer qBittorrent with Web UI and persistent downloads.",
            containerName: "qbittorrent", image: "lscr.io/linuxserver/qbittorrent:latest", restart: "no",
            ports: "8080:8080\n6881:6881\n6881:6881/udp", volumes: "neutronos_qbittorrent_config:/config\nneutronos_downloads:/downloads",
            environment: "PUID=1000\nPGID=1000\nWEBUI_PORT=8080", command: ""
        },
        {
            id: "nginx", name: "NGINX", description: "Lightweight web server with a persistent content volume.",
            containerName: "nginx", image: "nginx:alpine", restart: "no",
            ports: "8080:80", volumes: "neutronos_nginx_html:/usr/share/nginx/html:ro", environment: "", command: ""
        },
        {
            id: "watchtower", name: "Watchtower", description: "Checks for newer container images once per day and removes old layers.",
            containerName: "watchtower", image: "containrrr/watchtower:latest", restart: "no",
            ports: "", volumes: "/var/run/docker.sock:/var/run/docker.sock", environment: "", command: "--cleanup --interval 86400"
        },
        {
            id: "redis", name: "Redis", description: "Persistent Redis data store with append-only durability enabled.",
            containerName: "redis", image: "redis:alpine", restart: "no",
            ports: "6379:6379", volumes: "neutronos_redis_data:/data", environment: "", command: "redis-server --appendonly yes"
        }
    ]
    readonly property int formRowCount: formMode === "create" ? 9 : 7

    readonly property var containers: backend && backend.containers ? backend.containers : []
    readonly property color bg: lightMode ? "#F4F6F8" : "#020712"
    readonly property color panel: lightMode ? "#FFFFFF" : "#071426"
    readonly property color panelRaised: lightMode ? "#F8FAFC" : "#0B1D33"
    readonly property color raised: panelRaised
    readonly property color inset: lightMode ? "#EEF3F8" : "#030A11"
    readonly property bool securityProtected: securityBackend &&
                                                securityBackend.daemonOnline &&
                                                securityBackend.auditValid &&
                                                Number(securityBackend.threatLevel || 5) > 2
    readonly property color textPrimary: lightMode ? "#071018" : "#F4FBFF"
    readonly property color textSecondary: lightMode ? "#344253" : "#A9C6E3"
    readonly property color divider: lightMode ? "#CCD5DF" : "#1A3C5D"
    readonly property color cyan: "#7DF9FF"
    readonly property color blue: "#47C8FF"
    readonly property color green: "#22E887"
    readonly property color yellow: "#FFD166"
    readonly property color red: "#FF4055"
    readonly property color purple: "#B56AFF"

    function themeFile(name) {
        try {
            if (typeof assetManager !== "undefined" && assetManager)
                return assetManager.themeFile(name)
        } catch (e) {}
        return Qt.resolvedUrl("../../../themes/Default/" + name)
    }

    function normalizedContainerCandidate(value) {
        var v = String(value || "").trim().toLowerCase()
        if (!v.length) return ""
        var at = v.indexOf("@")
        if (at >= 0) v = v.substring(0, at)
        var slash = v.lastIndexOf("/")
        if (slash >= 0) v = v.substring(slash + 1)
        var colon = v.indexOf(":")
        if (colon >= 0) v = v.substring(0, colon)
        return v.replace(/[^a-z0-9._-]/g, "")
    }

    function containerAppRecord(item) {
        if (!appBackend || !appBackend.appById || !item) return ({})
        var candidates = []
        var nameCandidate = normalizedContainerCandidate(item.name)
        var imageCandidate = normalizedContainerCandidate(item.image)
        if (nameCandidate.length) candidates.push(nameCandidate)
        if (imageCandidate.length && imageCandidate !== nameCandidate) candidates.push(imageCandidate)
        for (var i = 0; i < candidates.length; ++i) {
            var record = appBackend.appById(candidates[i])
            if (record && String(record.id || "").length) return record
        }
        return ({})
    }

    function containerIconSource(item) {
        var record = containerAppRecord(item)
        var value = String(record.iconSource || record.icon || "").trim()
        if (!value.length) return ""
        if (value.indexOf(":") >= 0 || value.indexOf("/") >= 0) return value
        return themeFile("apps/icons/" + value + ".png")
    }

    function networkAccessText() {
        var endpoints = selectedDetails.publishedEndpoints || []
        if (endpoints.length) return endpoints.join("\n")
        var existing = String(selectedDetails.ipAddress || "").trim()
        return existing.length ? existing : "No published ports"
    }

    function savedFilesText() {
        var locations = selectedDetails.savedLocations || []
        if (locations.length) return locations.join("\n")
        var workdir = String(selectedDetails.workingDir || "").trim()
        return workdir.length ? workdir : "No persistent storage configured"
    }

    function startCommandText() {
        var explicit = String(selectedDetails.startCommand || "").trim()
        if (explicit.length) return explicit
        var name = String(currentContainer().name || "").trim()
        return name.length ? ("sudo docker start " + name) : "Select a container"
    }

    function normalizeAction(action) {
        var v = String(action || "").toLowerCase().replace(/-/g, "_")
        if (v === "x" || v === "cross" || v === "primary") return "primary"
        if (v === "o" || v === "circle" || v === "cancel") return "cancel"
        if (v === "triangle" || v === "context") return "context"
        if (v === "square" || v === "secondary") return "secondary"
        if (v === "start" || v === "settings" || v === "options" || v === "system") return "system"
        if (v === "dpad_up") return "up"
        if (v === "dpad_down") return "down"
        if (v === "dpad_left") return "left"
        if (v === "dpad_right") return "right"
        return v
    }

    function currentContainer() {
        if (!containers || containers.length === 0)
            return ({})
        selectedIndex = Math.max(0, Math.min(selectedIndex, containers.length - 1))
        return containers[selectedIndex] || ({})
    }

    function moveSelection(delta) {
        if (!containers || containers.length === 0) return
        engineCardSelected = false
        selectedIndex = Math.max(0, Math.min(containers.length - 1, selectedIndex + delta))
        containerList.currentIndex = selectedIndex
        containerList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function refreshSelectedDetails() {
        var item = currentContainer()
        if (!backend || !item.id) {
            selectedDetails = ({})
            return
        }
        var details = backend.containerDetails(String(item.id))
        selectedDetails = details && details.ok ? details : item
    }

    function runningCount() {
        var count = 0
        for (var i = 0; i < containers.length; ++i)
            if (containers[i] && containers[i].running === true) count++
        return count
    }

    function engineStatusText() {
        if (!backend || !backend.dockerAvailable) return "NOT INSTALLED"
        return backend.daemonActive ? "ENGINE ON" : "ENGINE OFF"
    }

    function engineStatusTone() {
        if (!backend || !backend.dockerAvailable) return red
        return backend.daemonActive ? green : yellow
    }

    function engineActionLabel(index) {
        if (index === 0) return backend && backend.daemonActive ? "STOP ENGINE" : "START ENGINE"
        if (index === 1) return backend && backend.daemonEnabled ? "DISABLE AT BOOT" : "ENABLE AT BOOT"
        return "REFRESH STATUS"
    }

    function engineActionDescription(index) {
        if (index === 0)
            return backend && backend.daemonActive
                ? "Stop Docker now. Running containers will stop with the engine."
                : "Start Docker now so containers can run."
        if (index === 1)
            return backend && backend.daemonEnabled
                ? "Keep Docker available for manual start after reboot."
                : "Start Docker automatically during system boot."
        return "Re-read Docker service and container state."
    }

    function requestEngineAction(index) {
        if (!backend) return
        if (index === 2) {
            backend.refresh()
            adminMessage = String(backend.lastMessage || "Docker status refreshed.")
            return
        }
        if (!privilegeBackend) {
            adminMessage = "NeutronOS administrative backend is unavailable."
            return
        }
        var action = index === 0
            ? (backend.daemonActive ? "stop" : "start")
            : (backend.daemonEnabled ? "disable" : "enable")
        var title = action === "start" ? "Start Docker Engine" :
                    action === "stop" ? "Stop Docker Engine" :
                    action === "enable" ? "Enable Docker at Boot" :
                    "Disable Docker at Boot"
        var description = action === "start"
            ? "Start docker.service now."
            : action === "stop"
              ? "Stop docker.service now. Active containers will stop."
              : action === "enable"
                ? "Enable docker.service for automatic startup."
                : "Disable automatic Docker startup. This does not stop the currently running engine."
        var accepted = privilegeBackend.request(title, description,
                                                "/usr/bin/systemctl",
                                                [action, "docker.service"])
        if (!accepted) {
            adminMessage = String(privilegeBackend.lastError || "Administrative request was rejected.")
            return
        }
        adminAction = action
        adminPassword = ""
        adminAwaitingPassword = true
        keyboardTarget = "__admin__"
        keyboardBuffer.text = ""
        keyboardBuffer.cursorPosition = 0
        keyboard.title = title + " · Password"
        keyboard.openKeyboard("large")
    }

    function activateActionRail() {
        var item = currentContainer()
        if (actionIndex === 0) {
            if (item.id && backend) backend.toggleContainer(String(item.id))
        } else if (actionIndex === 1) {
            if (item.id) openEdit()
        } else if (actionIndex === 2) {
            openCreate()
        } else if (actionIndex === 3) {
            engineVisible = true
            engineFocus = 0
            adminMessage = ""
        }
    }

    function clearForm() {
        fieldName = ""
        fieldImage = ""
        fieldRestart = "no"
        fieldPorts = ""
        fieldVolumes = ""
        fieldEnvironment = ""
        fieldCommand = ""
        fieldCpus = "1.00"
        fieldMemory = "512m"
        editingId = ""
        removeArmed = false
        presetVisible = false
        presetFocus = 0
        selectedPresetIndex = 0
        formFocus = 0
    }

    function applyPreset(index) {
        var safeIndex = Math.max(0, Math.min(dockerPresets.length - 1, Number(index || 0)))
        var preset = dockerPresets[safeIndex]
        selectedPresetIndex = safeIndex
        fieldName = String(preset.containerName || "")
        fieldImage = String(preset.image || "")
        fieldRestart = String(preset.restart || "no")
        fieldPorts = String(preset.ports || "")
        fieldVolumes = String(preset.volumes || "")
        fieldEnvironment = String(preset.environment || "")
        fieldCommand = String(preset.command || "")
        localMessage = preset.id === "custom"
            ? "Custom container form ready."
            : String(preset.name) + " preset loaded. Review ports, volumes, and environment before creating."
    }

    function openPresetPicker() {
        presetFocus = selectedPresetIndex
        presetVisible = true
        Qt.callLater(function() {
            presetList.currentIndex = presetFocus
            presetList.positionViewAtIndex(presetFocus, ListView.Contain)
        })
    }

    function openCreate() {
        clearForm()
        formMode = "create"
        applyPreset(0)
        formVisible = true
    }

    function openEdit() {
        var item = currentContainer()
        if (!item.id || !backend) return
        var details = backend.containerDetails(String(item.id))
        clearForm()
        formMode = "edit"
        editingId = String(item.id)
        fieldName = String(details.name || item.name || "")
        fieldImage = String(details.image || item.image || "")
        fieldRestart = String(details.restartPolicy || "no")
        fieldPorts = (details.portBindings || []).join("\n")
        fieldVolumes = (details.binds || []).join("\n")
        fieldEnvironment = (details.environment || []).join("\n")
        fieldCommand = (details.commandList || []).join(" ")
        var nano = Number(details.cpuNano || 0)
        fieldCpus = nano > 0 ? (nano / 1000000000.0).toFixed(2) : "1.00"
        var memoryBytes = Number(details.memoryBytes || 0)
        fieldMemory = memoryBytes > 0 ? Math.max(1, Math.round(memoryBytes / 1048576)) + "m" : "512m"
        formVisible = true
    }

    function restartValues() { return ["no", "unless-stopped", "always", "on-failure"] }
    function cycleRestart(delta) {
        var values = restartValues()
        var index = values.indexOf(fieldRestart)
        if (index < 0) index = 0
        fieldRestart = values[(index + delta + values.length) % values.length]
    }

    function formRowLabel(index) {
        if (formMode === "create")
            return ["PRESET", "NAME", "IMAGE", "RESTART", "PORTS", "VOLUMES", "ENVIRONMENT", "COMMAND", "CREATE CONTAINER"][index]
        return ["NAME", "IMAGE", "RESTART", "CPU LIMIT", "MEMORY LIMIT", "SAVE SETTINGS", "REMOVE CONTAINER"][index]
    }

    function formRowValue(index) {
        if (formMode === "create") {
            var preset = dockerPresets[Math.max(0, Math.min(dockerPresets.length - 1, selectedPresetIndex))]
            return [String(preset.name) + " · " + String(preset.description), fieldName, fieldImage, fieldRestart,
                    fieldPorts, fieldVolumes, fieldEnvironment, fieldCommand,
                    "Pull image, create, then manage it here"][index]
        }
        return [fieldName, fieldImage + " · recreation required to change", fieldRestart, fieldCpus, fieldMemory,
                "Rename and apply Docker update settings",
                removeArmed ? "X again permanently removes this container" : "X arms permanent removal"][index]
    }

    function formRowType(index) {
        if (formMode === "create")
            return ["preset", "name", "image", "restart", "ports", "volumes", "environment", "command", "submit"][index]
        return ["name", "readonly", "restart", "cpus", "memory", "submit", "remove"][index]
    }

    function valueForTarget(target) {
        if (target === "name") return fieldName
        if (target === "image") return fieldImage
        if (target === "ports") return fieldPorts
        if (target === "volumes") return fieldVolumes
        if (target === "environment") return fieldEnvironment
        if (target === "command") return fieldCommand
        if (target === "cpus") return fieldCpus
        if (target === "memory") return fieldMemory
        return ""
    }

    function setTargetValue(target, value) {
        if (target === "name") fieldName = value
        else if (target === "image") fieldImage = value
        else if (target === "ports") fieldPorts = value
        else if (target === "volumes") fieldVolumes = value
        else if (target === "environment") fieldEnvironment = value
        else if (target === "command") fieldCommand = value
        else if (target === "cpus") fieldCpus = value
        else if (target === "memory") fieldMemory = value
    }

    function openKeyboard(target) {
        keyboardTarget = target
        keyboardBuffer.text = valueForTarget(target)
        keyboardBuffer.cursorPosition = keyboardBuffer.text.length
        keyboard.title = "Docker Settings"
        keyboard.openKeyboard("large")
    }

    function closeKeyboard() {
        keyboard.visibleMode = false
        keyboardTarget = ""
        keyboardBuffer.text = ""
        forceActiveFocus()
    }

    function submitForm() {
        if (!backend) return
        var ok = false
        if (formMode === "create") {
            ok = backend.createContainer({
                name: fieldName, image: fieldImage, restartPolicy: fieldRestart,
                ports: fieldPorts, volumes: fieldVolumes, environment: fieldEnvironment,
                command: fieldCommand
            })
        } else {
            ok = backend.updateContainer(editingId, {
                name: fieldName, restartPolicy: fieldRestart, cpus: fieldCpus, memory: fieldMemory
            })
        }
        if (ok) {
            formVisible = false
            armedId = ""
        }
        localMessage = backend ? String(backend.lastMessage || "") : ""
    }

    function activateFormRow() {
        var type = formRowType(Math.max(0, Math.min(formFocus, formRowCount - 1)))
        if (type === "preset") openPresetPicker()
        else if (type === "restart") cycleRestart(1)
        else if (type === "submit") submitForm()
        else if (type === "remove") {
            if (!removeArmed) removeArmed = true
            else if (backend) {
                var item = currentContainer()
                backend.removeContainer(editingId, "REMOVE " + String(item.name || fieldName))
                formVisible = false
                armedId = ""
            }
        } else if (type !== "readonly") openKeyboard(type)
    }

    function handleControllerPressed(action) {
        var value = normalizeAction(action)
        if (keyboard.visibleMode) {
            keyboard.handleControllerPressed(value)
            return true
        }
        if (backend && backend.busy) {
            if (value === "cancel") backend.cancelOperation()
            return true
        }
        if (exitVisible) {
            referenceExitModal.handleController(value)
            return true
        }
        if (presetVisible) {
            if (value === "cancel") presetVisible = false
            else if (value === "up" || value === "left") {
                presetFocus = Math.max(0, presetFocus - 1)
                presetList.currentIndex = presetFocus
                presetList.positionViewAtIndex(presetFocus, ListView.Contain)
            } else if (value === "down" || value === "right") {
                presetFocus = Math.min(dockerPresets.length - 1, presetFocus + 1)
                presetList.currentIndex = presetFocus
                presetList.positionViewAtIndex(presetFocus, ListView.Contain)
            } else if (value === "primary") {
                applyPreset(presetFocus)
                presetVisible = false
                formFocus = 1
            }
            return true
        }
        if (formVisible) {
            if (value === "cancel") { formVisible = false; removeArmed = false }
            else if (value === "up") { formFocus = Math.max(0, formFocus - 1); removeArmed = false }
            else if (value === "down") { formFocus = Math.min(formRowCount - 1, formFocus + 1); removeArmed = false }
            else if (value === "left" && formRowType(formFocus) === "restart") cycleRestart(-1)
            else if (value === "right" && formRowType(formFocus) === "restart") cycleRestart(1)
            else if (value === "primary") activateFormRow()
            return true
        }
        if (engineVisible) {
            if (value === "cancel") {
                if (privilegeBackend && privilegeBackend.pending) privilegeBackend.cancel()
                engineVisible = false
                adminAwaitingPassword = false
                adminPassword = ""
            } else if (!adminAwaitingPassword && (!privilegeBackend || !privilegeBackend.running)) {
                if (value === "up" || value === "left") engineFocus = Math.max(0, engineFocus - 1)
                else if (value === "down" || value === "right") engineFocus = Math.min(2, engineFocus + 1)
                else if (value === "primary") requestEngineAction(engineFocus)
            }
            return true
        }

        if (focusZone === 2) {
            if (value === "primary") { exitVisible = true; referenceExitModal.openModal(app) }
            else if (value === "down" || value === "cancel") { focusZone = 0; engineCardSelected = true }
            return true
        }

        if (value === "cancel") { exitVisible = true; referenceExitModal.openModal(app) }
        else if (value === "system") { if (backend) { backend.refresh(); refreshSelectedDetails() } }
        else if (value === "context") openCreate()
        else if (focusZone === 0) {
            if (value === "up") {
                if (engineCardSelected) focusZone = 2
                else if (selectedIndex <= 0) engineCardSelected = true
                else moveSelection(-1)
            } else if (value === "down") {
                if (engineCardSelected) {
                    if (containers && containers.length > 0) {
                        engineCardSelected = false
                        selectedIndex = 0
                        containerList.currentIndex = 0
                        containerList.positionViewAtIndex(0, ListView.Contain)
                        refreshSelectedDetails()
                    }
                } else moveSelection(1)
            } else if (value === "right") { focusZone = 1; actionIndex = 0 }
            else if (value === "primary") {
                if (engineCardSelected) {
                    engineFocus = 1
                    adminMessage = ""
                    engineVisible = true
                } else {
                    var quickItem = currentContainer()
                    if (quickItem.id && backend) backend.toggleContainer(String(quickItem.id))
                }
            }
        } else if (focusZone === 1) {
            if (value === "left") focusZone = 0
            else if (value === "up") actionIndex = Math.max(0, actionIndex - 1)
            else if (value === "down") actionIndex = Math.min(3, actionIndex + 1)
            else if (value === "primary") activateActionRail()
        }
        return true
    }
    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return true }

    Connections {
        target: backend
        ignoreUnknownSignals: true
        function onContainersChanged() {
            if (containers.length === 0) selectedIndex = 0
            else selectedIndex = Math.max(0, Math.min(selectedIndex, containers.length - 1))
            Qt.callLater(function() {
                containerList.currentIndex = selectedIndex
                rootRefreshDetailsTimer.restart()
            })
        }
        function onAvailabilityChanged() {
            Qt.callLater(function() { refreshSelectedDetails() })
        }
        function onOperationFinished(success, message) {
            localMessage = message
            Qt.callLater(function() { refreshSelectedDetails() })
        }
    }

    Connections {
        target: privilegeBackend
        ignoreUnknownSignals: true
        function onCompleted(success, message, output, exitCode) {
            adminAwaitingPassword = false
            adminPassword = ""
            adminMessage = String(message || (success ? "Docker administrative action completed." : "Docker administrative action failed."))
            if (backend) {
                backend.refresh()
                Qt.callLater(function() { refreshSelectedDetails() })
            }
        }
    }

    Timer {
        id: rootRefreshDetailsTimer
        interval: 80
        repeat: false
        onTriggered: refreshSelectedDetails()
    }

    onSelectedIndexChanged: rootRefreshDetailsTimer.restart()

    Rectangle { anchors.fill: parent; color: bg }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#030812" }
            GradientStop { position: 0.55; color: "#02070D" }
            GradientStop { position: 1.0; color: "#04120E" }
        }
    }

    Shared.ReferenceAppHeader {
        id: header
        x: 18
        width: parent.width - 36
        anchors.top: parent.top
        z: 50
        appTitle: "Docker"
        primaryStatus: app.securityProtected ? "Secure" : "Attention"
        primaryTone: app.securityProtected ? "success" : "danger"
        secondaryStatus: backend && backend.dockerAvailable
                         ? (backend.daemonActive ? "Engine On" : "Engine Off")
                         : "Docker Unavailable"
        secondaryTone: backend && backend.daemonActive ? "success" : "warning"
        attention: !app.securityProtected
        menuFocused: app.focusZone === 2 && !app.exitVisible
        onMenuRequested: { app.exitVisible = true; referenceExitModal.openModal(app) }
    }

    Shared.ReferenceAppFooter {
        id: footer
        x: 18
        width: parent.width - 36
        anchors.bottom: parent.bottom
        z: 50
        hintText: ""
        controllerBackend: app.controllerBackend
    }

    Row {
        id: workspace
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 14

        Rectangle {
            id: listPanel
            width: Math.max(430, Math.min(620, parent.width * 0.37))
            height: parent.height
            radius: 9
            color: panel
            border.width: app.focusZone === 0 ? 2 : 1
            border.color: app.focusZone === 0 ? blue : divider

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 92
                    radius: 8
                    color: app.engineCardSelected && app.focusZone === 0 ? "#0D2A43" : panelRaised
                    border.width: app.engineCardSelected && app.focusZone === 0 ? 2 : 1
                    border.color: app.engineCardSelected && app.focusZone === 0 ? blue : divider

                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            width: 58
                            height: 58
                            radius: 16
                            anchors.verticalCenter: parent.verticalCenter
                            color: backend && backend.daemonActive ? "#0A2B1E" : "#2A2110"
                            border.width: 1
                            border.color: app.engineStatusTone()
                            Text {
                                anchors.centerIn: parent
                                text: "▣"
                                color: app.engineStatusTone()
                                font.pixelSize: 30
                                font.bold: true
                            }
                        }

                        Column {
                            width: parent.width - 220
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Text {
                                width: parent.width
                                text: app.engineStatusText()
                                color: app.engineStatusTone()
                                font.pixelSize: 20
                                font.bold: true
                            }
                            Text {
                                width: parent.width
                                text: backend && backend.dockerAvailable
                                      ? (backend.daemonEnabled ? "Starts automatically with NeutronOS" : "Manual start after reboot")
                                      : "Docker executable was not found"
                                color: textSecondary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }

                        Column {
                            width: 120
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                anchors.right: parent.right
                                text: containers.length + " TOTAL"
                                color: cyan
                                font.pixelSize: 13
                                font.bold: true
                            }
                            Text {
                                anchors.right: parent.right
                                text: app.runningCount() + " RUNNING"
                                color: green
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            app.focusZone = 0
                            app.engineCardSelected = true
                            app.engineFocus = 1
                            app.adminMessage = ""
                            app.engineVisible = true
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 34
                    Text {
                        text: "CONTAINERS"
                        color: textPrimary
                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 1.6
                    }
                    Item { width: Math.max(0, parent.width - 285); height: 1 }
                    Text {
                        text: "△ CREATE"
                        color: purple
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                ListView {
                    id: containerList
                    width: parent.width
                    height: parent.height - 156
                    model: containers
                    spacing: 8
                    clip: true
                    currentIndex: selectedIndex
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: containerList.width
                        height: 108
                        radius: 8
                        property bool selected: !app.engineCardSelected && index === app.selectedIndex
                        color: selected ? "#0D2A43" : panelRaised
                        border.width: selected ? 2 : 1
                        border.color: selected ? blue : divider

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Rectangle {
                                width: 5
                                height: 70
                                radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.running ? green : yellow
                            }

                            Item {
                                width: 64
                                height: 64
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: listAppIcon
                                    anchors.fill: parent
                                    source: app.containerIconSource(modelData)
                                    sourceSize.width: 500
                                    sourceSize.height: 500
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    mipmap: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: String(listAppIcon.source || "").length === 0 || listAppIcon.status === Image.Error
                                    text: String(modelData.name || "D").slice(0, 1).toUpperCase()
                                    color: cyan
                                    font.pixelSize: 25
                                    font.bold: true
                                }
                            }

                            Column {
                                width: parent.width - 264
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5
                                Text {
                                    width: parent.width
                                    text: String(modelData.name || "Unnamed container")
                                    color: textPrimary
                                    font.pixelSize: 19
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: String(modelData.image || "Unknown image")
                                    color: cyan
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: String(modelData.ports || "No published ports")
                                    color: textSecondary
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: 116
                                height: 34
                                radius: 17
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.running ? "#0A2B1E" : "#2B2110"
                                border.width: 1
                                border.color: modelData.running ? green : yellow
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.running ? "RUNNING" : "STOPPED"
                                    color: modelData.running ? green : yellow
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                app.selectedIndex = index
                                app.engineCardSelected = false
                                app.focusZone = 0
                                app.refreshSelectedDetails()
                            }
                            onDoubleClicked: {
                                if (backend) backend.toggleContainer(String(modelData.id || ""))
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: containers.length === 0
                        width: parent.width - 60
                        text: !backend || !backend.dockerAvailable
                              ? "DOCKER IS NOT INSTALLED"
                              : !backend.daemonActive
                                ? "DOCKER ENGINE IS OFF\n\n→ OPEN ENGINE CONTROLS TO START IT"
                                : "NO CONTAINERS\n\n△ CREATE THE FIRST CONTAINER"
                        color: textSecondary
                        font.pixelSize: 18
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        Rectangle {
            id: detailPanel
            width: parent.width - listPanel.width - parent.spacing
            height: parent.height
            radius: 9
            color: panel
            border.width: app.focusZone === 1 ? 2 : 1
            border.color: app.focusZone === 1 ? blue : divider

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Rectangle {
                    width: parent.width
                    height: 132
                    radius: 9
                    color: panelRaised
                    border.width: 1
                    border.color: divider

                    Row {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 18

                        Item {
                            width: 88
                            height: 88
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: detailAppIcon
                                anchors.fill: parent
                                source: app.containerIconSource(app.currentContainer())
                                sourceSize.width: 500
                                sourceSize.height: 500
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: String(detailAppIcon.source || "").length === 0 || detailAppIcon.status === Image.Error
                                text: app.currentContainer().id
                                      ? String(app.currentContainer().name || "D").slice(0, 1).toUpperCase()
                                      : "D"
                                color: currentContainer().running ? green : yellow
                                font.pixelSize: 34
                                font.bold: true
                            }
                        }

                        Column {
                            width: parent.width - 310
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Text {
                                width: parent.width
                                text: currentContainer().id ? String(currentContainer().name || "Container") : "DOCKER WORKSPACE"
                                color: textPrimary
                                font.pixelSize: 28
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: currentContainer().id
                                      ? String(currentContainer().image || "Unknown image")
                                      : "Select a container to inspect it, or create a new container from a preset."
                                color: cyan
                                font.pixelSize: 15
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: currentContainer().id
                                      ? String(currentContainer().status || currentContainer().state || "")
                                      : String(localMessage || (backend ? backend.lastMessage : "Docker backend unavailable"))
                                color: textSecondary
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            width: 180
                            height: 44
                            radius: 22
                            anchors.verticalCenter: parent.verticalCenter
                            color: currentContainer().running ? "#0A2B1E" : "#2A2110"
                            border.width: 1
                            border.color: currentContainer().running ? green : yellow
                            Text {
                                anchors.centerIn: parent
                                text: currentContainer().id
                                      ? (currentContainer().running ? "● RUNNING" : "● STOPPED")
                                      : app.engineStatusText()
                                color: currentContainer().id
                                       ? (currentContainer().running ? green : yellow)
                                       : app.engineStatusTone()
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: parent.height - 220
                    spacing: 12

                    Rectangle {
                        width: parent.width - 260
                        height: parent.height
                        radius: 8
                        color: inset
                        border.width: 1
                        border.color: divider

                        Flickable {
                            id: detailFlick
                            anchors.fill: parent
                            anchors.margins: 14
                            contentWidth: width
                            contentHeight: detailColumn.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            Column {
                                id: detailColumn
                                width: detailFlick.width
                                spacing: 12

                                Text {
                                    text: "CONTAINER DETAILS"
                                    color: textPrimary
                                    font.pixelSize: 16
                                    font.bold: true
                                    font.letterSpacing: 1.4
                                }

                                Grid {
                                    width: parent.width
                                    columns: 2
                                    columnSpacing: 12
                                    rowSpacing: 10

                                    Repeater {
                                        model: [
                                            {k:"IMAGE", v:String(app.selectedDetails.image || app.currentContainer().image || "—")},
                                            {k:"PLATFORM", v:String(app.selectedDetails.platform || "—")},
                                            {k:"RESTART POLICY", v:String(app.selectedDetails.restartPolicy || "—")},
                                            {k:"NETWORK ACCESS", v:app.networkAccessText()},
                                            {k:"HOSTNAME", v:String(app.selectedDetails.hostname || "—")},
                                            {k:"SAVED FILES", v:app.savedFilesText()},
                                            {k:"CPU LIMIT", v:Number(app.selectedDetails.cpuNano || 0) > 0 ? (Number(app.selectedDetails.cpuNano) / 1000000000.0).toFixed(2) + " CPU" : "UNLIMITED"},
                                            {k:"MEMORY LIMIT", v:Number(app.selectedDetails.memoryBytes || 0) > 0 && backend ? backend.formatBytes(Number(app.selectedDetails.memoryBytes)) : "UNLIMITED"}
                                        ]

                                        Rectangle {
                                            required property var modelData
                                            width: (detailColumn.width - 12) / 2
                                            height: 94
                                            radius: 7
                                            color: raised
                                            border.width: 1
                                            border.color: divider
                                            Column {
                                                anchors.fill: parent
                                                anchors.margins: 11
                                                spacing: 5
                                                Text { text: modelData.k; color: textSecondary; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.0 }
                                                Text {
                                                    width: parent.width
                                                    text: modelData.v
                                                    color: textPrimary
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    wrapMode: Text.WrapAnywhere
                                                    maximumLineCount: 3
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }

                                Text { text: "PORTS"; color: cyan; font.pixelSize: 13; font.bold: true }
                                Text {
                                    width: parent.width
                                    text: (app.selectedDetails.portBindings || []).length
                                          ? (app.selectedDetails.portBindings || []).join("\n")
                                          : String(app.currentContainer().ports || "No published ports")
                                    color: textSecondary
                                    font.family: "monospace"
                                    font.pixelSize: 13
                                    wrapMode: Text.WrapAnywhere
                                }

                                Text { text: "MOUNTS"; color: purple; font.pixelSize: 13; font.bold: true }
                                Text {
                                    width: parent.width
                                    text: (app.selectedDetails.mountDetails || []).length
                                          ? (app.selectedDetails.mountDetails || []).join("\n")
                                          : ((app.selectedDetails.binds || []).length
                                             ? (app.selectedDetails.binds || []).join("\n")
                                             : String(app.currentContainer().mounts || "No persistent mounts"))
                                    color: textSecondary
                                    font.family: "monospace"
                                    font.pixelSize: 13
                                    wrapMode: Text.WrapAnywhere
                                }

                                Text { text: "START COMMAND"; color: cyan; font.pixelSize: 13; font.bold: true }
                                Text {
                                    width: parent.width
                                    text: app.startCommandText()
                                    color: textSecondary
                                    font.family: "monospace"
                                    font.pixelSize: 13
                                    wrapMode: Text.WrapAnywhere
                                }

                                Item { width: 1; height: 10 }
                            }
                        }
                    }

                    Column {
                        width: 248
                        height: parent.height
                        spacing: 10

                        Text {
                            width: parent.width
                            text: "ACTIONS"
                            color: textPrimary
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 1.5
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Repeater {
                            model: [
                                {label: app.currentContainer().running ? "STOP CONTAINER" : "START CONTAINER",
                                 detail: app.currentContainer().id ? "Change runtime state" : "Select a container",
                                 tone: app.currentContainer().running ? app.yellow : app.green},
                                {label:"EDIT CONTAINER", detail:"Name, restart, CPU, memory", tone:app.purple},
                                {label:"CREATE CONTAINER", detail:"Preset or custom configuration", tone:app.cyan},
                                {label:"ENGINE CONTROLS", detail:"Runtime and boot service state", tone:app.blue}
                            ]

                            Rectangle {
                                required property var modelData
                                required property int index
                                width: parent.width
                                height: 78
                                radius: 8
                                property bool selected: app.focusZone === 1 && app.actionIndex === index
                                color: selected ? Qt.rgba(modelData.tone.r, modelData.tone.g, modelData.tone.b, 0.16) : raised
                                border.width: selected ? 2 : 1
                                border.color: selected ? modelData.tone : divider

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label
                                        color: modelData.tone
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.parent.width - 20
                                        text: modelData.detail
                                        color: textSecondary
                                        font.pixelSize: 10
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        app.focusZone = 1
                                        app.actionIndex = index
                                        app.activateActionRail()
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    height: 28
                    text: app.focusZone === 0
                          ? "↑ / ↓ CONTAINER     X START / STOP     → ACTIONS     △ CREATE     OPTIONS REFRESH"
                          : "↑ / ↓ ACTION     X CONFIRM     ← CONTAINERS"
                    color: app.focusZone === 1 ? cyan : textSecondary
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Rectangle {
        visible: backend && backend.busy
        anchors.fill: parent
        color: "#D8000000"
        z: 90

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 220, 880)
            height: 300
            radius: 20
            color: "#07101A"
            border.width: 2
            border.color: cyan

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 18

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String(backend.operationName || "DOCKER OPERATION").toUpperCase()
                    color: textPrimary
                    font.pixelSize: 28
                    font.bold: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: backend.operationProgress >= 0 ? String(backend.operationProgress) + "%" : "WORKING"
                    color: cyan
                    font.pixelSize: 42
                    font.bold: true
                }

                Rectangle {
                    width: parent.width
                    height: 18
                    radius: 9
                    color: "#142330"
                    clip: true
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(100, Number(backend.operationProgress || 0))) / 100
                        height: parent.height
                        radius: 9
                        color: cyan
                    }
                }

                Text {
                    width: parent.width
                    text: String(backend.operationStatus || "Working…")
                    color: textSecondary
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "O  CANCEL OPERATION"
                    color: yellow
                    font.pixelSize: 13
                    font.bold: true
                }
            }
        }
    }

    Rectangle {
        visible: engineVisible
        anchors.fill: parent
        color: "#DF000000"
        z: 95

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 180, 960)
            height: 510
            radius: 20
            color: "#07101A"
            border.width: 2
            border.color: blue

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 16

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "DOCKER ENGINE"
                    color: textPrimary
                    font.pixelSize: 30
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: "Control the Docker daemon separately from individual containers. Administrative changes require the local account password."
                    color: textSecondary
                    font.pixelSize: 15
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14

                    Rectangle {
                        width: 210
                        height: 44
                        radius: 22
                        color: backend && backend.daemonActive ? "#0A2B1E" : "#2A2110"
                        border.width: 1
                        border.color: backend && backend.daemonActive ? green : yellow
                        Text {
                            anchors.centerIn: parent
                            text: backend && backend.daemonActive ? "● ENGINE ACTIVE" : "● ENGINE STOPPED"
                            color: backend && backend.daemonActive ? green : yellow
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    Rectangle {
                        width: 210
                        height: 44
                        radius: 22
                        color: backend && backend.daemonEnabled ? "#0A2B1E" : "#101B28"
                        border.width: 1
                        border.color: backend && backend.daemonEnabled ? green : blue
                        Text {
                            anchors.centerIn: parent
                            text: backend && backend.daemonEnabled ? "BOOT ENABLED" : "MANUAL START"
                            color: backend && backend.daemonEnabled ? green : blue
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }

                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: parent.width
                        height: 78
                        radius: 9
                        property bool selected: engineFocus === index
                        color: selected ? "#0D2A43" : panelRaised
                        border.width: selected ? 2 : 1
                        border.color: selected ? blue : divider

                        Row {
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 16

                            Text {
                                width: 240
                                anchors.verticalCenter: parent.verticalCenter
                                text: app.engineActionLabel(index)
                                color: index === 0 ? app.engineStatusTone() : (index === 1 ? purple : cyan)
                                font.pixelSize: 16
                                font.bold: true
                            }

                            Text {
                                width: parent.width - 280
                                anchors.verticalCenter: parent.verticalCenter
                                text: app.engineActionDescription(index)
                                color: textSecondary
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: adminMessage
                    visible: adminMessage.length > 0
                    color: adminMessage.toLowerCase().indexOf("fail") >= 0 ||
                           adminMessage.toLowerCase().indexOf("reject") >= 0 ||
                           adminMessage.toLowerCase().indexOf("required") >= 0 ? red : green
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "↑ / ↓ CHOOSE     X CONFIRM     O CLOSE"
                    color: textSecondary
                    font.pixelSize: 13
                    font.bold: true
                }
            }
        }
    }

    Rectangle {
        visible: formVisible; anchors.centerIn: parent; width: Math.min(parent.width - 180, 1180); height: Math.min(parent.height - 90, 900)
        radius: 34; color: panel; border.width: 3; border.color: formMode === "create" ? cyan : purple; z: 20
        Column {
            anchors.fill: parent; anchors.margins: 28; spacing: 14
            Text { text: formMode === "create" ? "CREATE DOCKER CONTAINER" : "EDIT DOCKER CONTAINER"; color: textPrimary; font.pixelSize: 28; font.bold: true; font.letterSpacing: 2 }
            Text { text: formMode === "create" ? "Choose a preset, then review every field. Images, ports, volumes and environment are passed as separate Docker arguments." : "Docker can update name, restart policy, CPU and memory without recreating the container."; color: textSecondary; font.pixelSize: 14; wrapMode: Text.WordWrap; width: parent.width }
            ListView {
                id: formList; width: parent.width; height: parent.height - 130; spacing: 9; clip: true; model: formRowCount; currentIndex: formFocus
                delegate: Rectangle {
                    required property int index
                    width: formList.width; height: 72; radius: 18
                    color: index === app.formFocus ? (lightMode ? "#EAF5FF" : "#0D2C4B") : panelRaised
                    border.width: index === app.formFocus ? 3 : 1
                    border.color: index === app.formFocus ? (app.formRowType(index) === "remove" ? red : blue) : divider
                    Row { anchors.fill: parent; anchors.margins: 16; spacing: 20
                        Text { width: 240; anchors.verticalCenter: parent.verticalCenter; text: app.formRowLabel(index); color: app.formRowType(index) === "remove" ? red : textPrimary; font.pixelSize: 15; font.bold: true; font.letterSpacing: 1.5 }
                        Text { width: parent.width - 280; anchors.verticalCenter: parent.verticalCenter; text: String(app.formRowValue(index) || "Not set").replace(/\n/g, "  ·  "); color: app.formRowType(index) === "remove" && removeArmed ? red : textSecondary; font.pixelSize: 14; elide: Text.ElideRight }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: presetVisible
        anchors.centerIn: parent
        width: Math.min(parent.width - 280, 980)
        height: Math.min(parent.height - 170, 700)
        radius: 34
        color: panel
        border.width: 3
        border.color: cyan
        z: 40

        Column {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            Text { text: "CHOOSE A DOCKER PRESET"; color: textPrimary; font.pixelSize: 29; font.bold: true; font.letterSpacing: 2 }
            Text {
                width: parent.width
                text: "Presets fill the create form only. Review storage paths, ports, credentials, and image settings before installation."
                color: textSecondary; font.pixelSize: 15; wrapMode: Text.WordWrap
            }

            ListView {
                id: presetList
                width: parent.width
                height: parent.height - 120
                model: dockerPresets
                spacing: 10
                clip: true
                currentIndex: presetFocus

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: presetList.width
                    height: 86
                    radius: 19
                    color: index === presetFocus ? (lightMode ? "#EAF5FF" : "#0D2C4B") : panelRaised
                    border.width: index === presetFocus ? 3 : 1
                    border.color: index === presetFocus ? blue : divider
                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 20
                        Rectangle {
                            width: 54; height: 54; radius: 14
                            color: index === selectedPresetIndex ? "#0C3B2A" : (lightMode ? "#E3EAF1" : "#0A1828")
                            border.width: 2; border.color: index === selectedPresetIndex ? green : divider
                            Text { anchors.centerIn: parent; text: index === selectedPresetIndex ? "✓" : String(index + 1); color: index === selectedPresetIndex ? green : textSecondary; font.pixelSize: 20; font.bold: true }
                        }
                        Column {
                            width: parent.width - 90
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Text { width: parent.width; text: String(modelData.name); color: textPrimary; font.pixelSize: 20; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: String(modelData.description); color: textSecondary; font.pixelSize: 14; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }
    }

    Shared.ReferenceExitModal {
        id: referenceExitModal
        appName: "Docker"
        descriptionText: "Leave the Docker manager running in the background, or close the manager before returning to NeutronOS. Containers keep their own Docker runtime state."
        exitLabel: "EXIT APP"
        onExitRequested: {
            app.exitVisible = false
            app.exitRequested()
        }
        onLeaveRunningRequested: {
            app.exitVisible = false
            app.backgroundRequested()
        }
        onDismissed: {
            app.exitVisible = false
            app.forceActiveFocus()
        }
    }

    TextEdit { id: keyboardBuffer; visible: false }
    Shared.VirtualKeyboard {
        id: keyboard
        z: 120
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.bottomMargin: 24
        height: Math.max(0, Math.min(416, parent.height - 80))
        visibleMode: false
        resetOnOpen: true
        title: "Docker Settings"

        onKeyPressed: function(value) {
            keyboardBuffer.insert(keyboardBuffer.cursorPosition, value)
            if (keyboardTarget === "__admin__") {
                adminPassword = keyboardBuffer.text
            } else {
                setTargetValue(keyboardTarget, keyboardBuffer.text)
            }
        }

        onBackspacePressed: {
            if (keyboardBuffer.cursorPosition > 0)
                keyboardBuffer.remove(keyboardBuffer.cursorPosition - 1, keyboardBuffer.cursorPosition)
            if (keyboardTarget === "__admin__") {
                adminPassword = keyboardBuffer.text
            } else {
                setTargetValue(keyboardTarget, keyboardBuffer.text)
            }
        }

        onEnterPressed: {
            if (keyboardTarget === "__admin__") {
                adminPassword = keyboardBuffer.text
                keyboard.visibleMode = false
                if (privilegeBackend && privilegeBackend.pending) {
                    var secret = adminPassword
                    adminPassword = ""
                    keyboardBuffer.text = ""
                    adminAwaitingPassword = false
                    privilegeBackend.proceed(secret)
                    secret = ""
                    adminMessage = "Applying Docker service change…"
                } else {
                    adminAwaitingPassword = false
                    adminMessage = "Administrative request is no longer pending."
                }
                keyboardTarget = ""
                app.forceActiveFocus()
            } else {
                setTargetValue(keyboardTarget, keyboardBuffer.text)
                closeKeyboard()
            }
        }

        onClosePressed: {
            if (keyboardTarget === "__admin__") {
                if (privilegeBackend && privilegeBackend.pending) privilegeBackend.cancel()
                adminPassword = ""
                keyboardBuffer.text = ""
                adminAwaitingPassword = false
                adminMessage = "Administrative action cancelled."
                keyboardTarget = ""
            } else {
                setTargetValue(keyboardTarget, keyboardBuffer.text)
            }
            app.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        if (backend) backend.refresh()
        Qt.callLater(function() { refreshSelectedDetails() })
        forceActiveFocus()
    }
}
