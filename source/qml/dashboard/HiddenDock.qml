import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components"

Item {
    id: root

    /*
        ============================================================
                            HIDDEN DOCK
        ============================================================

        Secure hidden dashboard/console dock.

        Preserved from original:
            - opened / armed compatibility.
            - unlocked gate.
            - selectedIndex / selectedDock compatibility.
            - HiddenDockSecurityModal protection.
            - X select.
            - O close.
            - Square lock.
            - Secure right-side glass panel.
            - Built-in secure action list.
            - closed().
            - actionRequested(action).

        Next-gen updates:
            - Safe controllerManager access.
            - Safe appManager/appLauncher access.
            - Can optionally show hidden/non-favorite apps.
            - Keeps original secure system actions.
            - Adds appRequested(appData, index) for app-launching parents.
            - Adds itemRequested(itemData, index) for newer Console wiring.
            - Controller aliases expanded.
            - Animations pause when hidden.
            - Security modal remains separate.
            - No MouseArea.
            - No Button.
            - No placeholder data.
    */

    signal closed()
    signal actionRequested(string action)
    signal itemRequested(var itemData, int index)
    signal appRequested(var appData, int index)

    property bool opened: false
    property bool externallyControlled: false

    /*
        Backward compatibility for older ConsoleScene/Console wiring.
        Internally this dock uses opened.
    */
    property bool armed: opened

    onArmedChanged: {
        if (opened !== armed)
            opened = armed
    }

    onOpenedChanged: {
        if (armed !== opened)
            armed = opened

        if (opened) {
            syncPowerModeState()
            clampSelected()
            forceActiveFocus()
        }
    }

    property bool unlocked: false
    property bool sectionFocused: opened
    property int selectedIndex: 0

    /*
        Backward compatibility for older ConsoleScene/Console wiring.
        Internally this dock uses selectedIndex.
    */
    property int selectedDock: selectedIndex

    onSelectedDockChanged: {
        if (selectedIndex !== selectedDock)
            selectedIndex = selectedDock
    }

    onSelectedIndexChanged: {
        if (selectedDock !== selectedIndex)
            selectedDock = selectedIndex

        clampSelected()
    }

    /*
        If hidden apps exist, they can appear above the built-in secure actions.
        The original secure actions are still kept.
    */
    property bool includeHiddenApps: true
    property bool includeSystemActions: true
    property int visibleItemCount: 6

    property bool animationsEnabled: visible && enabled && opened

    property color neutronBlue: "#7df9ff"
    property color focusBlue: "#4da6ff"
    property color neutronRed: "#ff3040"
    property color neutronPurple: "#a855f7"
    property color secureGreen: "#22ff88"
    property color warning: "#F5B942"
    property color mutedBlue: "#8aa6c8"

    property real glowPulse: 0.45
    property real sweepPulse: -1.0

    property bool developerModeEnabled: false
    property bool performanceModeEnabled: false
    property bool performanceProfileModalVisible: false
    property int performanceProfileIndex: 0
    property int performanceProfilePhase: 0 // 0 list, 1 review
    property bool performanceProfileArmed: false
    property bool performanceProfileError: false
    property string performanceProfileMessage: ""
    property var performanceSelectedConfiguration: ({})
    property var performanceAssessment: ({})
    property string statusMessage: ""
    property bool statusMessageIsError: false

    function developerBackend() {
        try {
            if (typeof developerModeManager !== "undefined" &&
                    developerModeManager) {
                return developerModeManager
            }
        } catch (error) {
        }

        return null
    }

    function powerBackend() {
        try {
            if (typeof powerModeManager !== "undefined" &&
                    powerModeManager) {
                return powerModeManager
            }
        } catch (error) {
        }

        return null
    }

    function performanceBackend() {
        try {
            if (typeof performanceManager !== "undefined" && performanceManager)
                return performanceManager
        } catch (error) {
        }
        return null
    }

    function performanceProfiles() {
        var backend = performanceBackend()
        if (!backend)
            return []
        try {
            return backend.availableProfiles || []
        } catch (error) {
            return []
        }
    }

    function selectedPerformanceProfile() {
        var list = performanceProfiles()
        if (!list || list.length <= 0)
            return null
        performanceProfileIndex = Math.max(0, Math.min(list.length - 1, performanceProfileIndex))
        return list[performanceProfileIndex]
    }

    function openPerformanceProfiles() {
        var backend = performanceBackend()
        if (!backend) {
            showStatusMessage("Performance backend is unavailable.", true)
            return false
        }
        try { backend.refresh() } catch (error) {}
        performanceProfileIndex = 0
        var currentId = ""
        try { currentId = String(backend.currentConfiguration.profile || "") } catch (currentError) {}
        var list = performanceProfiles()
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].profile || "") === currentId) {
                performanceProfileIndex = i
                break
            }
        }
        performanceProfilePhase = 0
        performanceProfileArmed = false
        performanceProfileError = false
        performanceProfileMessage = ""
        performanceSelectedConfiguration = ({})
        performanceAssessment = ({})
        performanceProfileModalVisible = true
        forceActiveFocus()
        return true
    }

    function closePerformanceProfiles() {
        performanceProfileModalVisible = false
        performanceProfilePhase = 0
        performanceProfileArmed = false
        performanceProfileError = false
        performanceProfileMessage = ""
        forceActiveFocus()
    }

    function movePerformanceProfile(delta) {
        var list = performanceProfiles()
        if (!list || list.length <= 0)
            return
        performanceProfileIndex = (performanceProfileIndex + delta + list.length) % list.length
    }

    function reviewPerformanceProfile() {
        var backend = performanceBackend()
        var profile = selectedPerformanceProfile()
        if (!backend || !profile)
            return
        performanceSelectedConfiguration = profile
        try { performanceAssessment = backend.evaluateConfiguration(profile) }
        catch (error) { performanceAssessment = ({"ok": false, "errors": [String(error)]}) }
        performanceProfileError = !Boolean(performanceAssessment.ok)
        performanceProfileMessage = performanceProfileError
                ? String(performanceAssessment.errors || "The selected profile is invalid.")
                : ""
        performanceProfileArmed = false
        performanceProfilePhase = 1
    }

    function confirmPerformanceProfile() {
        if (performanceProfileError) {
            performanceProfilePhase = 0
            performanceProfileError = false
            performanceProfileMessage = ""
            return
        }
        if (!performanceProfileArmed) {
            performanceProfileArmed = true
            return
        }
        var backend = performanceBackend()
        if (!backend) {
            performanceProfileError = true
            performanceProfileMessage = "Performance backend is unavailable."
            performanceProfileArmed = false
            return
        }
        var unhealthyOverride = !Boolean(performanceAssessment.healthOk)
        var result = null
        try { result = backend.applyConfiguration(performanceSelectedConfiguration, unhealthyOverride) }
        catch (error) { result = ({"ok": false, "message": String(error)}) }
        if (!result || !result.ok) {
            performanceProfileError = true
            performanceProfileMessage = String(result && result.message ? result.message : "The profile could not be applied.")
            performanceProfileArmed = false
            return
        }
        performanceProfileMessage = String(result.message || "Profile applied. Rebooting.")
    }

    function handlePerformanceProfileController(action) {
        if (!performanceProfileModalVisible)
            return false
        if (action === "cancel") {
            if (performanceProfilePhase === 1) {
                performanceProfilePhase = 0
                performanceProfileArmed = false
                performanceProfileError = false
                performanceProfileMessage = ""
            } else {
                closePerformanceProfiles()
            }
            return true
        }
        if (performanceProfilePhase === 0) {
            if (action === "up" || action === "left") movePerformanceProfile(-1)
            else if (action === "down" || action === "right") movePerformanceProfile(1)
            else if (action === "primary") reviewPerformanceProfile()
            return true
        }
        if (action === "primary")
            confirmPerformanceProfile()
        return true
    }

    function syncPowerModeState() {
        var developer = developerBackend()
        var performance = performanceBackend()

        try {
            developerModeEnabled = developer
                                   ? !!developer.developerModeEnabled
                                   : false
        } catch (developerError) {
            developerModeEnabled = false
        }

        try {
            performanceModeEnabled = performance && performance.currentConfiguration
                                     ? !Boolean(performance.currentConfiguration.stock)
                                     : false
        } catch (performanceError) {
            performanceModeEnabled = false
        }
    }

    function showStatusMessage(message, isError) {
        statusMessage = String(message || "").trim()
        statusMessageIsError = !!isError

        statusMessageTimer.stop()

        if (statusMessage.length > 0)
            statusMessageTimer.restart()
    }

    Timer {
        id: statusMessageTimer
        interval: 3200
        repeat: false

        onTriggered: {
            root.statusMessage = ""
            root.statusMessageIsError = false
        }
    }

    Connections {
        target: root.developerBackend()
        ignoreUnknownSignals: true

        function onDeveloperModeChanged() {
            root.syncPowerModeState()
        }
    }

    Connections {
        target: root.performanceBackend()
        ignoreUnknownSignals: true

        function onConfigurationChanged() { root.syncPowerModeState() }
        function onProfilesChanged() { root.syncPowerModeState() }
    }

    Component.onCompleted: {
        root.syncPowerModeState()
        root.clampSelected()
    }

    anchors.fill: parent
    visible: opened || securityGate.visible || performanceProfileModalVisible || opacity > 0.0
    opacity: opened ? 1.0 : 0.0
    z: 900
    focus: opened || performanceProfileModalVisible

    Behavior on opacity {
        enabled: root.visible || root.opened

        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            ORIGINAL ACTIONS
        ============================================================
    */

    ListModel {
        id: dockActions

        ListElement {
            title: "Performance Profiles"
            subtitle: "Saved and model-specific profiles"
            action: "performance_mode"
            danger: false
            performanceAction: true
            requiresDeveloper: true
        }

        ListElement {
            title: "System Overview"
            subtitle: "Open live hardware status"
            action: "system_overview"
            danger: false
            performanceAction: false
            requiresDeveloper: false
        }

        ListElement {
            title: "Controller Status"
            subtitle: "Input, haptics, and pairing"
            action: "controller_status"
            danger: false
            performanceAction: false
            requiresDeveloper: false
        }

        ListElement {
            title: "Logs"
            subtitle: "View NeutronOS service logs"
            action: "logs"
            danger: false
            performanceAction: false
            requiresDeveloper: false
        }

        ListElement {
            title: "Settings"
            subtitle: "Open console settings"
            action: "settings"
            danger: false
            performanceAction: false
            requiresDeveloper: false
        }

        ListElement {
            title: "Restart Shell"
            subtitle: "Restart NeutronOS shell"
            action: "restart_shell"
            danger: true
            performanceAction: false
            requiresDeveloper: false
        }

        ListElement {
            title: "Power Options"
            subtitle: "Shutdown / reboot menu"
            action: "power_options"
            danger: true
            performanceAction: false
            requiresDeveloper: false
        }
    }

    /*
        ============================================================
                                API
        ============================================================
    */

    function open() {
        if (unlocked) {
            opened = true
            clampSelected()
            forceActiveFocus()
            return
        }

        securityGate.open()
    }

    function close() {
        /*
            Console owns the opened binding in production. Writing opened
            here would destroy that binding and leave the dock/Console in
            mismatched states after the first close.
        */
        if (!externallyControlled)
            opened = false

        closed()
    }

    function lockDock() {
        unlocked = false
        close()
    }

    function toggle() {
        if (opened)
            close()
        else
            open()
    }

    function moveSelection(delta) {
        if (!opened)
            return false

        var count = itemCount()

        if (count <= 0)
            return false

        selectedIndex += delta

        while (selectedIndex < 0)
            selectedIndex += count

        selectedIndex = selectedIndex % count

        return true
    }

    function activateSelected() {
        if (!opened)
            return false

        var item = itemAt(selectedIndex)

        if (!item)
            return false

        itemRequested(item, selectedIndex)

        if (item.__kind === "app") {
            appRequested(item.appData, selectedIndex)

            var appId = appValue(item.appData, [
                                      "id",
                                      "appId",
                                      "desktopId"
                                  ], "")

            if (appId.length > 0)
                actionRequested("app:" + appId)

            return true
        }

        actionRequested(String(item.action || ""))

        return true
    }

    function handleController(button) {
        var action = normalizeControllerAction(button)

        if (performanceProfileModalVisible)
            return handlePerformanceProfileController(action)

        if (securityGate.visible) {
            securityGate.handleController(button)
            return true
        }

        if (!opened)
            return false

        if (action === "up") {
            return moveSelection(-1)
        }

        if (action === "down") {
            return moveSelection(1)
        }

        if (action === "left") {
            return moveSelection(-1)
        }

        if (action === "right") {
            return moveSelection(1)
        }

        if (action === "primary") {
            return activateSelected()
        }

        if (action === "cancel" || action === "system") {
            close()
            return true
        }

        if (action === "secondary") {
            lockDock()
            return true
        }

        return true
    }

    function handleControllerPressed(button) {
        return handleController(button)
    }

    function handleControllerReleased(button) {
        return opened || securityGate.visible || performanceProfileModalVisible
    }

    /*
        ============================================================
                            DATA HELPERS
        ============================================================
    */

    function appBackend() {
        try {
            if (typeof appLauncher !== "undefined" && appLauncher)
                return appLauncher
        } catch (e) {
        }

        try {
            if (typeof appManager !== "undefined" && appManager)
                return appManager
        } catch (e2) {
        }

        return null
    }

    function controllerBackend() {
        try {
            if (typeof controllerManager !== "undefined" && controllerManager)
                return controllerManager
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

    function appValue(app, keys, fallbackValue) {
        if (!app)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = app[keys[i]]

                if (value !== undefined &&
                        value !== null &&
                        String(value).length > 0) {
                    return String(value)
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function appBool(app, keys, fallbackValue) {
        if (!app)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var raw = app[keys[i]]

                if (raw === undefined || raw === null)
                    continue

                if (raw === true)
                    return true

                if (raw === false)
                    return false

                if (typeof raw === "number")
                    return raw !== 0

                var text = String(raw).trim().toLowerCase()

                if (text === "true" ||
                        text === "1" ||
                        text === "yes" ||
                        text === "hidden" ||
                        text === "inactive") {
                    return true
                }

                if (text === "false" ||
                        text === "0" ||
                        text === "no" ||
                        text === "favorite" ||
                        text === "active") {
                    return false
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function rawAppList() {
        var backend = appBackend()

        if (!backend)
            return []

        try {
            if (backend.hiddenApps)
                return backend.hiddenApps
        } catch (e) {
        }

        try {
            if (backend.nonFavoriteApps)
                return backend.nonFavoriteApps
        } catch (e2) {
        }

        try {
            if (backend.apps)
                return backend.apps
        } catch (e3) {
        }

        return []
    }

    function hiddenAppItems() {
        if (!includeHiddenApps)
            return []

        var list = rawAppList()
        var result = []

        if (!list || list.length === undefined)
            return result

        for (var i = 0; i < list.length; i++) {
            var app = list[i]

            var fromExplicitHiddenList = false

            try {
                fromExplicitHiddenList = appBackend() &&
                                         appBackend().hiddenApps &&
                                         appBackend().hiddenApps === list
            } catch (e) {
                fromExplicitHiddenList = false
            }

            var favorite = appBool(app, [
                                  "favorite",
                                  "isFavorite",
                                  "pinned"
                              ], false)

            var hidden = appBool(app, [
                               "hidden",
                               "isHidden",
                               "developerOnly"
                           ], false)

            if (fromExplicitHiddenList || hidden || !favorite) {
                result.push({
                    "__kind": "app",
                    "title": appValue(app, [
                                          "name",
                                          "title",
                                          "displayName",
                                          "id",
                                          "appId"
                                      ], "App"),
                    "subtitle": appValue(app, [
                                             "subtitle",
                                             "description",
                                             "category",
                                             "type"
                                         ], "Hidden app"),
                    "action": "app:" + appValue(app, [
                                                   "id",
                                                   "appId",
                                                   "desktopId"
                                               ], ""),
                    "danger": false,
                    "performanceAction": false,
                    "requiresDeveloper": false,
                    "appData": app
                })
            }
        }

        return result
    }

    function systemActionItems() {
        var result = []

        if (!includeSystemActions)
            return result

        for (var i = 0; i < dockActions.count; i++) {
            var item = dockActions.get(i)

            result.push({
                "__kind": "action",
                "title": item.title,
                "subtitle": item.subtitle,
                "action": item.action,
                "danger": item.danger,
                "performanceAction": item.performanceAction,
                "requiresDeveloper": item.requiresDeveloper,
                "appData": null
            })
        }

        return result
    }

    function allItems() {
        var result = []

        var apps = hiddenAppItems()
        var actions = systemActionItems()

        /* Keep Performance Mode as the first stable Hidden Dock anchor. */
        if (actions.length > 0 && itemPerformanceAction(actions[0]))
            result.push(actions[0])

        for (var i = 0; i < apps.length; i++)
            result.push(apps[i])

        for (var j = 0; j < actions.length; j++) {
            if (j === 0 && itemPerformanceAction(actions[j]))
                continue

            result.push(actions[j])
        }

        return result
    }

    function itemCount() {
        return allItems().length
    }

    function itemAt(index) {
        var list = allItems()

        if (!list || list.length <= 0)
            return null

        while (index < 0)
            index += list.length

        index = index % list.length

        return list[index]
    }

    function visibleStartIndex() {
        var count = itemCount()
        var limit = Math.max(1, visibleItemCount)

        if (count <= limit)
            return 0

        var start = selectedIndex - Math.floor(limit / 2)

        while (start < 0)
            start += count

        return start % count
    }

    function visibleItems() {
        var list = allItems()
        var count = list.length
        var limit = Math.min(visibleItemCount, count)
        var start = visibleStartIndex()
        var result = []

        if (count <= 0)
            return result

        for (var i = 0; i < limit; i++) {
            var realIndex = (start + i) % count

            result.push({
                "data": list[realIndex],
                "realIndex": realIndex
            })
        }

        return result
    }

    function visibleCount() {
        return visibleItems().length
    }

    function clampSelected() {
        var count = itemCount()

        if (count <= 0) {
            selectedIndex = 0
            return
        }

        if (selectedIndex < 0)
            selectedIndex = count - 1

        if (selectedIndex >= count)
            selectedIndex = 0
    }

    function itemTitle(item) {
        if (!item)
            return "Item"

        return cleanText(item.title).length > 0 ? item.title : "Item"
    }

    function itemSubtitle(item) {
        if (!item)
            return ""

        if (itemPerformanceAction(item)) {
            if (!developerModeEnabled)
                return "Enable Developer Mode first"

            var backend = performanceBackend()
            if (backend && backend.currentConfiguration) {
                var current = backend.currentConfiguration
                return "Current: " + String(current.profileName || "Normal") +
                       " • " + Number(current.cpuMinMhz || 0) + "–" + Number(current.cpuMaxMhz || 0) + " MHz"
            }

            return "Open saved and model-specific profiles"
        }

        return cleanText(item.subtitle)
    }

    function itemPerformanceAction(item) {
        if (!item)
            return false

        try {
            return !!item.performanceAction ||
                   String(item.action || "").toLowerCase() === "performance_mode"
        } catch (error) {
            return false
        }
    }

    function itemRequiresDeveloper(item) {
        if (!item)
            return false

        try {
            return !!item.requiresDeveloper
        } catch (error) {
            return false
        }
    }

    function itemDeveloperLocked(item) {
        return itemRequiresDeveloper(item) && !developerModeEnabled
    }

    function itemDanger(item) {
        if (!item)
            return false

        try {
            return !!item.danger
        } catch (e) {
            return false
        }
    }

    function itemGlyph(item) {
        if (!item)
            return "✦"

        if (item.__kind === "app")
            return "◈"

        var action = String(item.action || "").toLowerCase()
        var title = String(item.title || "").toLowerCase()
        var combined = action + " " + title

        if (root.itemPerformanceAction(item))
            return "◴"

        if (combined.indexOf("power") >= 0 ||
                combined.indexOf("shutdown") >= 0) {
            return "⏻"
        }

        if (combined.indexOf("restart") >= 0 ||
                combined.indexOf("reboot") >= 0) {
            return "↻"
        }

        if (combined.indexOf("logs") >= 0)
            return "≡"

        if (combined.indexOf("settings") >= 0)
            return "⚙"

        if (combined.indexOf("controller") >= 0)
            return "⌁"

        if (combined.indexOf("system") >= 0)
            return "SYS"

        return "✦"
    }

    function normalizeControllerAction(button) {
        var b = String(button || "").trim().toLowerCase()

        if (b === "primary" ||
                b === "cross" ||
                b === "x" ||
                b === "a" ||
                b === "ps_cross") {
            return "primary"
        }

        if (b === "cancel" ||
                b === "circle" ||
                b === "o" ||
                b === "b" ||
                b === "ps_circle") {
            return "cancel"
        }

        if (b === "secondary" ||
                b === "square" ||
                b === "xbox_x" ||
                b === "ps_square") {
            return "secondary"
        }

        if (b === "context" ||
                b === "triangle" ||
                b === "y" ||
                b === "ps_triangle") {
            return "context"
        }

        if (b === "system" ||
                b === "options" ||
                b === "option" ||
                b === "start" ||
                b === "settings" ||
                b === "menu" ||
                b === "guide" ||
                b === "home" ||
                b === "ps" ||
                b === "playstation") {
            return "system"
        }

        if (b === "dpad_up")
            return "up"

        if (b === "dpad_down")
            return "down"

        if (b === "dpad_left")
            return "left"

        if (b === "dpad_right")
            return "right"

        if (b === "up" ||
                b === "down" ||
                b === "left" ||
                b === "right") {
            return b
        }

        if (b === "l1" ||
                b === "r1" ||
                b === "l2" ||
                b === "r2") {
            return b
        }

        return b
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on glowPulse {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.35
            to: 1.0
            duration: 1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.35
            duration: 1800
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweepPulse {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 3600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 3600
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            OVERLAY
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        visible: root.opened
        color: "#01040A"
        opacity: 0.72
    }

    Rectangle {
        id: dockPanel

        visible: root.opened

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 42
        anchors.topMargin: 96
        anchors.bottomMargin: 96

        width: Math.min(560, parent.width * 0.34)
        radius: 38

        color: "#050914"

        border.width: 2
        border.color: root.neutronBlue

        clip: true

        scale: root.opened ? 1.0 : 0.96

        Behavior on scale {
            enabled: root.visible || root.opened

            NumberAnimation {
                duration: 190
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.035
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -190

            width: parent.width * 1.15
            height: 330
            radius: height / 2

            color: root.neutronBlue
            opacity: 0.055 + root.glowPulse * 0.045
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            width: 7
            radius: 4

            color: root.neutronBlue
            opacity: 0.72 + root.glowPulse * 0.22
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 34
            anchors.rightMargin: 34
            anchors.topMargin: 20

            height: 1

            color: root.neutronBlue
            opacity: 0.55 + root.glowPulse * 0.28
        }

        Column {
            anchors.fill: parent
            anchors.margins: 34

            spacing: 22

            Column {
                width: parent.width
                spacing: 5

                Text {
                    width: parent.width

                    text: "Hidden Dock"

                    color: "white"

                    font.pixelSize: 38
                    font.bold: true

                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    width: parent.width

                    text: root.itemCount() > dockActions.count
                          ? "Hidden apps and secure controls"
                          : "Secure dashboard controls"

                    color: "#9fd8ff"

                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1.4

                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Rectangle {
                width: parent.width
                height: 1

                color: root.neutronBlue
                opacity: 0.22
            }

            Item {
                width: parent.width
                height: parent.height - 174

                Item {
                    visible: root.itemCount() <= 0

                    anchors.fill: parent

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter

                            text: "NO HIDDEN ITEMS"

                            color: "#8aa6c8"

                            font.pixelSize: 22
                            font.bold: true
                            font.letterSpacing: 1.4
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter

                            text: "App registry has not published hidden apps"

                            color: "#5f7f9e"

                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                }

                Repeater {
                    model: root.visibleItems()

                    Rectangle {
                        id: actionRow

                        property var wrapperData: modelData
                        property var itemData: wrapperData && wrapperData.data ? wrapperData.data : null
                        property int realIndex: wrapperData && wrapperData.realIndex !== undefined
                                                ? wrapperData.realIndex
                                                : index

                        property bool selected: root.selectedIndex === realIndex
                        property bool danger: root.itemDanger(itemData)
                        property bool performanceAction: root.itemPerformanceAction(itemData)
                        property bool developerLocked: root.itemDeveloperLocked(itemData)
                        property bool performanceActive: performanceAction && root.performanceModeEnabled

                        width: parent.width
                        height: 76
                        radius: 22

                        y: index * 88

                        color: performanceAction
                               ? developerLocked
                                 ? selected ? "#20242b" : "#171b21"
                                 : performanceActive
                                   ? selected ? "#4a0710" : "#31070d"
                                   : selected ? "#35080e" : "#22070b"
                               : selected
                                 ? danger
                                   ? "#2a070c"
                                   : "#071d33"
                                 : "#071426"

                        border.width: selected ? 2 : 1
                        border.color: performanceAction
                                      ? developerLocked
                                        ? selected ? "#8a9099" : "#454b55"
                                        : root.neutronRed
                                      : selected
                                        ? danger
                                          ? root.neutronRed
                                          : root.neutronBlue
                                        : "#223d5f"

                        scale: selected ? 1.025 : 1.0
                        opacity: developerLocked
                                 ? selected ? 0.76 : 0.50
                                 : selected ? 1.0 : 0.72

                        Behavior on y {
                            enabled: root.animationsEnabled

                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on scale {
                            enabled: root.animationsEnabled

                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on opacity {
                            enabled: root.animationsEnabled

                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on border.color {
                            enabled: root.animationsEnabled

                            ColorAnimation {
                                duration: 140
                                easing.type: Easing.OutCubic
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1

                            radius: parent.radius - 1
                            color: "#FFFFFF"
                            opacity: selected ? 0.045 : 0.020
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom

                            width: selected ? 6 : 3
                            radius: 3

                            color: performanceAction
                                   ? developerLocked ? "#737983" : root.neutronRed
                                   : danger ? root.neutronRed
                                   : itemData && itemData.__kind === "app" ? root.neutronPurple
                                   : root.neutronBlue

                            opacity: selected ? 0.95 : 0.42
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 18

                            width: 42
                            height: 42
                            radius: 14

                            color: performanceAction
                                   ? developerLocked ? "#242830" : "#3a0710cc"
                                   : danger ? "#3a0710cc"
                                   : itemData && itemData.__kind === "app" ? "#20103acc"
                                   : "#0b2746cc"

                            border.width: selected ? 2 : 1
                            border.color: performanceAction
                                          ? developerLocked ? "#737983" : root.neutronRed
                                          : danger ? root.neutronRed
                                          : itemData && itemData.__kind === "app" ? root.neutronPurple
                                          : root.neutronBlue

                            Text {
                                anchors.centerIn: parent

                                text: root.itemGlyph(actionRow.itemData)

                                color: performanceAction
                                       ? developerLocked ? "#a7adb6" : "#ffd1d1"
                                       : danger ? "#ffd1d1"
                                       : itemData && itemData.__kind === "app" ? "#ead7ff"
                                       : "#d9f8ff"

                                font.pixelSize: root.itemGlyph(actionRow.itemData).length > 2 ? 11 : 20
                                font.bold: true
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 74
                            anchors.rightMargin: 18

                            spacing: 3

                            Text {
                                width: parent.width

                                text: root.itemTitle(actionRow.itemData)

                                color: performanceAction
                                       ? developerLocked ? "#a7adb6" : "#ffd1d1"
                                       : danger && actionRow.selected
                                         ? "#ffd1d1"
                                         : "white"

                                font.pixelSize: 20
                                font.bold: true

                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Text {
                                width: parent.width

                                text: root.itemSubtitle(actionRow.itemData)

                                color: performanceAction
                                       ? developerLocked ? "#858b94" : "#ff9a9a"
                                       : danger ? "#ff9a9a"
                                       : itemData && itemData.__kind === "app" ? "#d8c7ff"
                                       : "#8aa6c8"

                                font.pixelSize: 13
                                font.bold: actionRow.selected

                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        Rectangle {
                            visible: actionRow.selected

                            anchors.fill: parent
                            anchors.margins: -4

                            radius: parent.radius + 4
                            color: "transparent"

                            border.width: 1
                            border.color: actionRow.performanceAction
                                          ? actionRow.developerLocked ? "#8a9099" : root.neutronRed
                                          : actionRow.danger ? root.neutronRed : root.neutronBlue

                            opacity: 0.26 + root.glowPulse * 0.20
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 48
                radius: 24

                color: "#071426"
                border.width: 1
                border.color: "#335577"

                Text {
                    anchors.centerIn: parent

                    text: root.itemDeveloperLocked(root.itemAt(root.selectedIndex))
                          ? "X info  •  Developer Mode required  •  O close"
                          : "X select  •  O close  •  Square lock"

                    color: "#9fd8ff"

                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.3
                }
            }
        }

        Rectangle {
            id: statusPopup

            visible: root.statusMessage.length > 0

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 82

            width: Math.min(parent.width - 52, statusLabel.implicitWidth + 50)
            height: 58
            radius: 22
            z: 40

            color: root.statusMessageIsError ? "#30070d" : "#062d20"
            border.width: 2
            border.color: root.statusMessageIsError
                          ? root.neutronRed
                          : root.secureGreen

            opacity: visible ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: statusLabel

                anchors.centerIn: parent
                width: parent.width - 28

                text: root.statusMessage
                color: root.statusMessageIsError ? "#ffd1d1" : "#c8ffe5"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap

                font.pixelSize: 15
                font.bold: true
            }
        }

        /*
            Scroll/page indicator.
        */
        Rectangle {
            visible: root.itemCount() > root.visibleItemCount

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.rightMargin: 12
            anchors.topMargin: 120
            anchors.bottomMargin: 92

            width: 4
            radius: 2

            color: "#1b3658"

            Rectangle {
                width: parent.width
                height: Math.max(28, parent.height / Math.max(1, root.itemCount()) * root.visibleItemCount)
                radius: 2

                y: root.itemCount() <= 1
                   ? 0
                   : (parent.height - height) *
                     (root.selectedIndex / Math.max(1, root.itemCount() - 1))

                color: root.neutronBlue
                opacity: 0.72 + root.glowPulse * 0.20

                Behavior on y {
                    enabled: root.animationsEnabled

                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Rectangle {
        id: performanceProfileModal
        anchors.fill: parent
        visible: root.performanceProfileModalVisible
        color: "#E0000000"
        z: 1200

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(980, parent.width - 80)
            height: Math.min(680, parent.height - 60)
            radius: 32
            color: "#08182B"
            border.width: 3
            border.color: root.performanceProfileError ? root.neutronRed : root.neutronBlue

            Column {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 16

                Text {
                    width: parent.width
                    text: root.performanceProfilePhase === 0 ? "PERFORMANCE PROFILES" : "REVIEW PERFORMANCE PROFILE"
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: {
                        var backend = root.performanceBackend()
                        if (!backend) return "Backend unavailable"
                        var current = backend.currentConfiguration || ({})
                        return "Current: " + String(current.profileName || "Normal") +
                               "  •  " + Number(current.cpuMinMhz || 0) + "–" + Number(current.cpuMaxMhz || 0) + " MHz" +
                               "  •  GPU " + Number(current.gpuMhz || 0) + " MHz" +
                               "  •  Turbo " + (current.turbo ? "ON" : "OFF")
                    }
                    color: "#9FD8FF"
                    font.pixelSize: 14
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle { width: parent.width; height: 1; color: "#244668" }

                ListView {
                    id: profileList
                    visible: root.performanceProfilePhase === 0
                    width: parent.width
                    height: parent.height - 150
                    clip: true
                    model: root.performanceProfiles()
                    currentIndex: root.performanceProfileIndex
                    spacing: 10
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: profileList.width
                        height: 84
                        radius: 20
                        color: index === root.performanceProfileIndex ? "#0D3152" : "#071426"
                        border.width: index === root.performanceProfileIndex ? 3 : 1
                        border.color: index === root.performanceProfileIndex ? root.neutronBlue : "#244668"
                        Row {
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 18
                            Column {
                                width: parent.width - 330
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: String(modelData.profileName || "Profile"); color: "white"; font.pixelSize: 19; font.bold: true }
                                Text { text: modelData.saved ? "Saved custom profile" : (modelData.stock ? "Stock / no overclock" : "Built-in model profile"); color: modelData.stock ? root.secureGreen : root.mutedBlue; font.pixelSize: 12 }
                            }
                            Text {
                                width: 300
                                anchors.verticalCenter: parent.verticalCenter
                                text: Number(modelData.cpuMinMhz || 0) + "–" + Number(modelData.cpuMaxMhz || 0) + " MHz  •  GPU " + Number(modelData.gpuMhz || 0) + "  •  " + (modelData.turbo ? "TURBO" : "Dynamic")
                                color: modelData.turbo ? root.neutronRed : "#D9F8FF"
                                font.pixelSize: 13
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                Column {
                    visible: root.performanceProfilePhase === 1
                    width: parent.width
                    height: parent.height - 150
                    spacing: 14
                    property var profile: root.performanceSelectedConfiguration || ({})
                    property var check: root.performanceAssessment || ({})

                    Text { width: parent.width; text: String(parent.profile.profileName || "Profile"); color: "white"; font.pixelSize: 26; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    Text { width: parent.width; text: "CPU IDLE  " + Number(parent.profile.cpuMinMhz || 0) + " MHz\nCPU MAX   " + Number(parent.profile.cpuMaxMhz || 0) + " MHz\nGPU / V3D " + Number(parent.profile.gpuMhz || 0) + " MHz\nTURBO      " + (parent.profile.turbo ? "ON" : "OFF"); color: "#D9F8FF"; font.pixelSize: 18; font.bold: true; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.35 }
                    Rectangle { width: parent.width; height: 1; color: "#244668" }
                    Text {
                        width: parent.width
                        text: parent.profile.stock
                              ? "Normal removes the NeutronOS-managed overclock block and returns to stock clocks."
                              : "Cooling and proper voltage/power delivery are required.\n" + String(parent.check.warningText || "")
                        color: parent.profile.stock ? root.secureGreen : root.warning
                        font.pixelSize: 15
                        font.bold: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        visible: !Boolean(parent.check.healthOk)
                        width: parent.width
                        text: String(parent.check.healthMessage || "Current hardware health is not recommended for overclocking.")
                        color: root.neutronRed
                        font.pixelSize: 14
                        font.bold: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        visible: root.performanceProfileMessage.length > 0
                        width: parent.width
                        text: root.performanceProfileMessage
                        color: root.performanceProfileError ? root.neutronRed : root.secureGreen
                        font.pixelSize: 14
                        font.bold: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Item { width: 1; height: 8 }
                    Rectangle {
                        width: parent.width
                        height: 62
                        radius: 20
                        color: root.performanceProfileError ? "#301018" : (root.performanceProfileArmed ? root.neutronRed : root.warning)
                        border.width: 2
                        border.color: root.performanceProfileError ? root.neutronRed : "#FFE6A6"
                        Text {
                            anchors.centerIn: parent
                            text: root.performanceProfileError ? "X  RETURN" : (root.performanceProfileArmed ? "X  CONFIRM APPLY & REBOOT" : "X  ARM PROFILE")
                            color: root.performanceProfileError ? "#FFD5DA" : "#160A00"
                            font.pixelSize: 15
                            font.bold: true
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: root.performanceProfilePhase === 0 ? "D-PAD select  •  X review  •  O close" : "X arm / confirm  •  O back"
                    color: "#8AA6C8"
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    /*
        ============================================================
                            SECURITY GATE
        ============================================================
    */

    HiddenDockSecurityModal {
        id: securityGate

        anchors.fill: parent

        onUnlocked: {
            root.unlocked = true
            root.opened = true
            root.selectedIndex = 0
            root.forceActiveFocus()
        }

        onCancelled: {
            root.opened = false
            root.forceActiveFocus()
        }
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================
    */

    Keys.onUpPressed: handleController("up")
    Keys.onDownPressed: handleController("down")
    Keys.onLeftPressed: handleController("left")
    Keys.onRightPressed: handleController("right")
    Keys.onReturnPressed: handleController("primary")
    Keys.onEnterPressed: handleController("primary")
    Keys.onSpacePressed: handleController("primary")
    Keys.onEscapePressed: handleController("cancel")
    Keys.onBackPressed: handleController("cancel")

    Keys.onPressed: function(event) {
        if (!root.opened && !securityGate.visible)
            return

        if (event.key === Qt.Key_Backspace) {
            handleController("secondary")
            event.accepted = true
            return
        }
    }

    /*
        ============================================================
                        OPTIONAL CONTROLLER CONNECTION
        ============================================================

        Safe target. If Main.qml/Console.qml already routes controller input
        directly into handleController(), this connection is harmless but can
        be disabled by not exposing controllerManager.
    */

    Connections {
        target: root.controllerBackend()
        enabled: root.visible
        ignoreUnknownSignals: true

        function onButtonPressed(button) {
            root.handleController(button)
        }

        function onStickMoved(stick, x, y) {
            return
        }
    }

    Connections {
        target: root.appBackend()
        ignoreUnknownSignals: true

        function onAppsChanged() {
            root.clampSelected()
        }

        function onHiddenAppsChanged() {
            root.clampSelected()
        }

        function onFavoritesChanged() {
            root.clampSelected()
        }
    }

    onVisibleChanged: {
        if (!visible && !opened) {
            clampSelected()
        }
    }

}