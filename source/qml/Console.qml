import QtQuick 2.15
import QtQuick.Controls 2.15

/*
    Transitional imports.

    These match the current NeutronOS project folders.
    The final shell keeps Console as the owner of navigation, global
    modals, Developer Mode, and app-launch requests.
*/
import "dashboard"
import "dashboard/v2"
import "modals"
import "components"
import "modals/system"

Item {
    id: consoleRoot

    /*
        ============================================================
                            PUBLIC API FOR MAIN.QML
        ============================================================
    */

    property var activeUser
    readonly property var desktopCarouselController: modernDashboardView
    property bool shellActive: false
    property bool globalSearchActive: false
    readonly property bool suppressDirectionalRepeat: consoleRoot.modernDashboard && modernDashboardView && modernDashboardView.suppressDirectionalRepeat
    readonly property bool controllerPairHomeCaptureActive:
        consoleRoot.systemDetailModalId === "controllerSettings" &&
        systemDetailLoader.item &&
        ("awaitingHomeConfirmation" in systemDetailLoader.item) &&
        systemDetailLoader.item.awaitingHomeConfirmation === true
    property int lifecycleGeneration: 0

    signal logoutRequested()
    signal sessionMenuRequested()
    signal appLaunchRequested(var appData)
    signal notificationCenterRequested()
    signal globalSearchRequested()
    signal screensaverRequested()
    signal controllerOffRequested()
    signal restartShellRequested()
    signal rebootRequested()
    signal shutdownRequested()

    /*
        ============================================================
                            BACKEND BRIDGES
        ============================================================
    */

    property var appBackend:
        (typeof appLauncher !== "undefined")
        ? appLauncher
        : (
            (typeof appManager !== "undefined")
            ? appManager
            : null
        )

    property var quickBackend:
        (typeof quickActionManager !== "undefined")
        ? quickActionManager
        : null

    property var dockSecurity:
        (typeof dockSecurityManager !== "undefined")
        ? dockSecurityManager
        : null

    property var networkBackend:
        (typeof networkManager !== "undefined")
        ? networkManager
        : null

    property var userBackend:
        (typeof userManager !== "undefined")
        ? userManager
        : null

    property var clockBackend:
        (typeof clockSettingsManager !== "undefined")
        ? clockSettingsManager
        : null


    property var clockExperienceBackend:
        (typeof clockExperienceManager !== "undefined")
        ? clockExperienceManager
        : null


    property var securityBackend:
        (typeof securityCoreManager !== "undefined") ? securityCoreManager : null

    property var monitorBackend:
        (typeof systemMonitor !== "undefined") ? systemMonitor : null

    property var settingsBackend:
        (typeof settingsManager !== "undefined") ? settingsManager : null

    property var dashboardLayoutBackend:
        (typeof dashboardLayoutManager !== "undefined") ? dashboardLayoutManager : null

    property bool legacyDashboardActive:
        dashboardLayoutBackend && dashboardLayoutBackend.legacyAvailable &&
        String(dashboardLayoutBackend.defaultTab || "system") === "legacy"

    readonly property bool modernDashboard: !legacyDashboardActive

    property var personalizationBackend:
        (typeof personalizationManager !== "undefined") ? personalizationManager : null

    readonly property bool systemOverviewAllowed:
        personalizationBackend ? personalizationBackend.systemOverviewEnabled !== false : true
    readonly property bool customSystemOverview:
        personalizationBackend ? personalizationBackend.systemOverviewCustomized === true : false
    readonly property string launcherMode:
        personalizationBackend ? String(personalizationBackend.launcherMode || "carousel") : "carousel"

    property var criticalWarningQueue: []
    property int lastObservedThrottleEvents: 0

    /*
        ============================================================
                            CONSOLE SECTIONS
        ============================================================

        0 = System Overview
        1 = Apps Carousel
        2 = Quick Actions
        3 = Hidden App Dock
    */

    property int selectedSection: 1
    property int selectedSystemCard: 0
    property int selectedApp: 0
    property int selectedAction: 0
    property int selectedDock: 0

    property int visibleAppCount: 7
    property int appStartIndex: 0

    /*
        Must match the nine production cards in SystemOverview.qml.
    */
    readonly property var systemCardTypes: [
        "cpu",
        "memory",
        "storage",
        "active",
        "temperature",
        "network",
        "uptime",
        "clock",
        "user"
    ]

    property bool hiddenDockVisible: false
    property int hiddenDockReturnSection: 2
    property int settingsTapCount: 0

    property string currentTime: "--:--"
    property string currentDate: ""
    property string currentTimezoneLabel: ""
    property color currentClockTint: "#FFFFFF"
    property color currentDateTint: "#9FD8FF"
    property color currentTimezoneTint: "#7DF9FF"
    property int currentClockScale: 100
    property bool currentShowDate: true
    property bool currentShowTimezone: false

    property real cameraZoom: 1.0

    /*
        Quick Actions dock motion is event-driven. These values animate
        briefly when the dock receives focus or its selection changes.
    */
    property real dockGlowPulse: 0.30
    property real dockSweep: -1.0

    property bool sectionMoveLocked: false
    property bool carouselMoveLocked: false
    property bool launchLocked: false
    property int queuedCarouselMove: 0


    readonly property real systemOverviewHeightRatio: 0.135
    readonly property real quickDockHeightRatio: 0.105

    /*
        ============================================================
                    LAZY SYSTEM-DETAIL MODAL ROUTER
        ============================================================

        Only one System Overview detail modal is loaded at a time.
        Closed detail modals are unloaded after their close animation.
    */

    property string systemDetailModalId: ""
    property var systemDetailModalContext: ({})
    property string systemDetailLoadError: ""
    property string systemDetailLoadSource: ""
    // Explicit Loader source. Keeping this separate from systemDetailModalId
    // avoids mutating a dependency of Loader.source from onStatusChanged.
    property string systemDetailModalQmlSource: ""

    readonly property bool systemDetailModalOpen:
        systemDetailModalId.length > 0

    readonly property bool modalOpen:
        criticalWarningModal.visible ||
        appModal.visible ||
        appCarouselModal.visible ||
        quickActionModal.visible ||
        quickActionCustomizeModal.visible ||
        helpModal.visible ||
        hiddenDockSecurityModal.visible ||
        hiddenDock.performanceProfileModalVisible ||
        systemDetailModalOpen ||
        systemDetailLoadError.length > 0

    focus: true
    enabled: shellActive

    /*
        ============================================================
                                HELPERS
        ============================================================
    */

    function criticalMessage(text) {
        var value = String(text || "").toLowerCase()
        return value.indexOf("critical") >= 0 ||
               value.indexOf("fatal") >= 0 ||
               value.indexOf("corrupt") >= 0 ||
               value.indexOf("integrity") >= 0 ||
               value.indexOf("security") >= 0 ||
               value.indexOf("throttl") >= 0 ||
               value.indexOf("thermal") >= 0 ||
               value.indexOf("overheat") >= 0
    }

    function showCriticalWarning(title, message, source) {
        var warning = {
            title: String(title || "CRITICAL SYSTEM WARNING"),
            message: String(message || "NeutronOS detected a condition that needs attention."),
            source: String(source || "SYSTEM")
        }
        if (criticalWarningModal.visible) {
            criticalWarningQueue = criticalWarningQueue.concat([warning])
            return
        }
        criticalWarningModal.openWarning(warning.title, warning.message, warning.source)
    }

    function showNextCriticalWarning() {
        if (criticalWarningQueue.length <= 0) {
            forceActiveFocus()
            focusCurrentSection()
            return
        }
        var remaining = criticalWarningQueue.slice(0)
        var warning = remaining.shift()
        criticalWarningQueue = remaining
        Qt.callLater(function() {
            criticalWarningModal.openWarning(warning.title, warning.message, warning.source)
        })
    }

    function log() {
        var text = ""

        for (var i = 0; i < arguments.length; i++) {
            if (i > 0)
                text += " "

            text += String(arguments[i])
        }

        console.log(text)
    }

    function activeUserDisplayName() {
        if (!activeUser)
            return "User"

        try {
            if (activeUser.displayName)
                return String(activeUser.displayName)
        } catch (e1) {
        }

        try {
            if (activeUser.name)
                return String(activeUser.name)
        } catch (e2) {
        }

        try {
            if (activeUser.username)
                return String(activeUser.username)
        } catch (e3) {
        }

        return "User"
    }

    function favoriteAppList() {
        if (!appBackend)
            return []

        try {
            if (appBackend.favoriteApps)
                return appBackend.favoriteApps
        } catch (e1) {
        }

        try {
            if (appBackend.apps)
                return appBackend.apps
        } catch (e2) {
        }

        return []
    }

    function appList() {
        if (!appBackend)
            return []

        try {
            if (appBackend.apps)
                return appBackend.apps
        } catch (e1) {
        }

        try {
            if (appBackend.favoriteApps)
                return appBackend.favoriteApps
        } catch (e2) {
        }

        return []
    }

    function actionList() {
        if (!quickBackend)
            return []

        try {
            if (quickBackend.dockActions)
                return quickBackend.dockActions
        } catch (dockError) {
        }

        try {
            if (quickBackend.actions)
                return quickBackend.actions
        } catch (actionError) {
        }

        return []
    }

    function quickActionNeedsConfirmation(actionData) {
        if (!actionData)
            return false

        try {
            if (quickBackend &&
                    typeof quickBackend.requiresConfirmation === "function") {
                return quickBackend.requiresConfirmation(actionData) === true
            }
        } catch (backendError) {
        }

        try {
            if (actionData.confirmRequired === true ||
                    actionData.danger === true ||
                    actionData.destructive === true) {
                return true
            }
        } catch (dataError) {
        }

        return false
    }

    function favoriteAppCount() {
        return favoriteAppList().length
    }

    function actionCount() {
        return actionList().length
    }

    function dockUnlocked() {
        if (!dockSecurity)
            return false

        try {
            return dockSecurity.unlocked === true
        } catch (e) {
        }

        return false
    }

    function dockArmedMode() {
        if (!dockSecurity)
            return false

        try {
            return dockSecurity.armedMode === true
        } catch (e) {
        }

        return false
    }

    function normalizeControllerAction(button) {
        var b = String(button || "").toLowerCase()

        if (b === "primary" ||
                b === "cross" ||
                b === "x" ||
                b === "ps_cross") {
            return "primary"
        }

        if (b === "cancel" ||
                b === "circle" ||
                b === "o" ||
                b === "ps_circle") {
            return "cancel"
        }

        if (b === "context" ||
                b === "triangle" ||
                b === "ps_triangle") {
            return "context"
        }

        if (b === "secondary" ||
                b === "square" ||
                b === "ps_square") {
            return "secondary"
        }

        if (b === "system" ||
                b === "options" ||
                b === "settings" ||
                b === "start" ||
                b === "menu") {
            return "system"
        }

        if (b === "quick" ||
                b === "share" ||
                b === "create" ||
                b === "select") {
            return "quick"
        }

        if (b === "home" ||
                b === "ps" ||
                b === "playstation" ||
                b === "guide") {
            return "home"
        }

        if (b === "up" || b === "dpad_up")
            return "up"

        if (b === "down" || b === "dpad_down")
            return "down"

        if (b === "left" || b === "dpad_left")
            return "left"

        if (b === "right" || b === "dpad_right")
            return "right"

        if (b === "l1" || b === "lb")
            return "l1"

        if (b === "r1" || b === "rb")
            return "r1"

        if (b === "l2" || b === "lt")
            return "l2"

        if (b === "r2" || b === "rt")
            return "r2"

        if (b === "l3" || b === "ls")
            return "l3"

        if (b === "r3" || b === "rs")
            return "r3"

        return b
    }

    /*
        ============================================================
                            BACKGROUND
        ============================================================
    */

    Image {
        anchors.fill: parent

        source:
            (typeof assetManager !== "undefined" &&
             assetManager &&
             typeof assetManager.themeFile === "function")
            ? assetManager.themeFile("background.png")
            : ""

        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: false
        asynchronous: true
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.36
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        height: parent.height * 0.20
        color: "#02060D"
        opacity: 0.20
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: parent.height * 0.24
        color: "#02060D"
        opacity: 0.24
    }


    /*
        Patch 18 clock presentation bridge. Formatting lives in the persistent
        ClockExperienceManager and is refreshed only once per visible second.
    */
    function refreshClockPresentation() {
        var backend = consoleRoot.clockExperienceBackend

        if (backend) {
            try {
                currentTime = String(backend.currentTimeText || backend.formatCurrentTime() || "--:--")
                currentDate = String(backend.currentDateText || backend.formatCurrentDate() || "")
                currentTimezoneLabel = String(backend.timezoneLabel || "")
                currentClockTint = String(backend.clockTint || "#FFFFFF")
                currentDateTint = String(backend.dateTint || "#9FD8FF")
                currentTimezoneTint = String(backend.timezoneTint || "#7DF9FF")
                currentClockScale = Math.max(80, Math.min(140, Number(backend.clockScale || 100)))
                currentShowDate = Boolean(backend.showDate)
                currentShowTimezone = Boolean(backend.showTimezone)
                return
            } catch (error) {
                consoleRoot.log("Clock presentation refresh failed:", error)
            }
        }

        var now = new Date()
        currentTime = Qt.formatTime(now, "h:mm AP")
        currentDate = Qt.formatDate(now, "dddd, MMMM d")
        currentTimezoneLabel = ""
        currentClockTint = "#FFFFFF"
        currentDateTint = "#9FD8FF"
        currentTimezoneTint = "#7DF9FF"
        currentClockScale = 100
        currentShowDate = true
        currentShowTimezone = false
    }

    function activeUsernameForPersonalization() {
        try {
            if (activeUser && String(activeUser.username || activeUser.name || "").length > 0)
                return String(activeUser.username || activeUser.name)
            if (userBackend && String(userBackend.username || "").length > 0)
                return String(userBackend.username)
        } catch (error) {}
        return "default"
    }

    function resumeSession(generation, user) {
        lifecycleGeneration = Number(generation || lifecycleGeneration)
        activeUser = user || activeUser
        if (personalizationBackend && typeof personalizationBackend.setActiveUser === "function")
            personalizationBackend.setActiveUser(activeUsernameForPersonalization())
        refreshClockPresentation()
    }

    function openSecurityIncident(incident) {
        if (modernDashboard) {
            modernDashboardView.openSecurityIncident(incident || ({}))
            return true
        }
        openSystemDetailModal("security", { incident: incident || ({}) })
        return true
    }

    function prepareForLogout() {
        shellActive = false
        consoleClockTimer.stop()
        settingsTapResetTimer.stop()
        systemBootstrapRefreshTimer.stop()
        sectionMoveCooldownTimer.stop()
        carouselMoveCooldownTimer.stop()
        launchCooldownTimer.stop()
        systemDetailUnloadTimer.stop()
        quickDockGlowAnimation.stop()
        quickDockSweepAnimation.stop()

        queuedCarouselMove = 0
        sectionMoveLocked = false
        carouselMoveLocked = false
        launchLocked = false
        hiddenDockVisible = false
        settingsTapCount = 0

        try {
            if (systemDetailLoader.item && typeof systemDetailLoader.item.close === "function")
                systemDetailLoader.item.close()
        } catch (error1) {}

        systemDetailModalId = ""
        systemDetailModalContext = ({})
        systemDetailModalQmlSource = ""

        var modalItems = [appModal, quickActionModal, quickActionCustomizeModal,
                          helpModal, hiddenDockSecurityModal]
        for (var i = 0; i < modalItems.length; ++i) {
            try {
                if (modalItems[i] && typeof modalItems[i].close === "function")
                    modalItems[i].close()
            } catch (error2) {}
        }

        disarmAll()
        activeUser = null
    }

    /*
        ============================================================
                            TIMERS
        ============================================================
    */


    Connections {
        target: consoleRoot.userBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function refreshActiveUser() {
            try {
                // NEUTRONOS_ACTIVE_USER_GUARD_V1
                // Do not let an empty backend QVariantMap erase the user that
                // Main.qml just authenticated and passed into Console.qml.
                var candidate = consoleRoot.userBackend
                        ? consoleRoot.userBackend.activeUser : null
                var candidateName = ""
                if (candidate)
                    candidateName = String(candidate.username || candidate.accountName || candidate.loginName || "").trim()
                if (candidateName.length > 0)
                    consoleRoot.activeUser = candidate
                if (consoleRoot.personalizationBackend && typeof consoleRoot.personalizationBackend.setActiveUser === "function")
                    consoleRoot.personalizationBackend.setActiveUser(consoleRoot.activeUsernameForPersonalization())
            } catch (error) {}
        }

        function onActiveUserChanged() { refreshActiveUser() }
        function onProfileApplied() { refreshActiveUser() }
        function onProfileRevisionChanged() { refreshActiveUser() }
    }

    Connections {
        target: consoleRoot.personalizationBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onSettingsChanged() {
            consoleRoot.selectedSection = consoleRoot.clampSection(consoleRoot.selectedSection)
            consoleRoot.selectedSystemCard = consoleRoot.safeSelectedSystem()
            systemOverview.selectedSystem = consoleRoot.selectedSystemCard
            apps.setSelectedIndex(consoleRoot.selectedApp)
            consoleRoot.forceActiveFocus()
        }
    }

    Connections {
        target: consoleRoot.clockExperienceBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onSettingsChanged() { consoleRoot.refreshClockPresentation() }
        function onDisplayChanged() { consoleRoot.refreshClockPresentation() }
        function onRevisionChanged() { consoleRoot.refreshClockPresentation() }
    }

    Connections {
        target: consoleRoot.clockBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onSettingsChanged() { consoleRoot.refreshClockPresentation() }
        function onTimezoneChanged() { consoleRoot.refreshClockPresentation() }
    }

    Timer {
        id: consoleClockTimer
        interval: 1000
        running: consoleRoot.shellActive &&
                 consoleRoot.clockExperienceBackend === null
        repeat: true

        onTriggered: consoleRoot.refreshClockPresentation()
    }

    Timer {
        id: settingsTapResetTimer
        interval: 1800
        repeat: false

        onTriggered:
            consoleRoot.settingsTapCount = 0
    }


    Timer {
        id: systemBootstrapRefreshTimer
        interval: 2500
        running: consoleRoot.shellActive
        repeat: false

        onTriggered: {
            if (typeof systemMonitor !== "undefined" &&
                    systemMonitor &&
                    typeof systemMonitor.refresh === "function") {
                systemMonitor.refresh()
            }
        }
    }

    Timer {
        id: sectionMoveCooldownTimer
        interval: 180
        repeat: false

        onTriggered:
            consoleRoot.sectionMoveLocked = false
    }

    Timer {
        id: carouselMoveCooldownTimer
        interval: 95
        repeat: false

        onTriggered: {
            consoleRoot.carouselMoveLocked = false

            if (consoleRoot.queuedCarouselMove !== 0) {
                var direction = consoleRoot.queuedCarouselMove
                consoleRoot.queuedCarouselMove = 0
                consoleRoot.requestCarouselMove(direction)
            }
        }
    }

    Timer {
        id: launchCooldownTimer
        interval: 420
        repeat: false

        onTriggered:
            consoleRoot.launchLocked = false
    }

    Timer {
        id: systemDetailUnloadTimer
        interval: 240
        repeat: false

        onTriggered: {
            consoleRoot.closeResidentSystemDetailPanels("")
            consoleRoot.systemDetailModalId = ""
            consoleRoot.systemDetailModalContext = ({})
            consoleRoot.systemDetailModalQmlSource = ""
            consoleRoot.forceActiveFocus()
            consoleRoot.focusCurrentSection()

            /*
                Do not force a full QML garbage collection after every modal.
                The engine reclaims the unloaded component naturally; forcing
                collection here caused visible controller-navigation hitches.
            */
        }
    }

    /*
        ============================================================
                EVENT-DRIVEN QUICK DOCK ANIMATION
        ============================================================

        No continuous Console dock loop. Motion runs once when the Quick
        Actions section receives focus or its selected action changes.
    */

    SequentialAnimation {
        id: quickDockGlowAnimation
        running: false
        loops: 1

        NumberAnimation {
            target: consoleRoot
            property: "dockGlowPulse"

            from: 0.30
            to: 1.0
            duration: 260
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: consoleRoot
            property: "dockGlowPulse"

            from: 1.0
            to: 0.30
            duration: 520
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation {
        id: quickDockSweepAnimation
        running: false
        loops: 1

        NumberAnimation {
            target: consoleRoot
            property: "dockSweep"

            from: -1.0
            to: 1.0
            duration: 620
            easing.type: Easing.OutCubic
        }
    }

    function playQuickDockMotion() {
        if (!consoleRoot.shellActive ||
                consoleRoot.selectedSection !== 2) {
            return
        }

        quickDockGlowAnimation.stop()
        quickDockSweepAnimation.stop()

        consoleRoot.dockGlowPulse = 0.30
        consoleRoot.dockSweep = -1.0

        quickDockGlowAnimation.restart()
        quickDockSweepAnimation.restart()
    }

    /*
        ============================================================
                            SYSTEM OVERVIEW
        ============================================================
    */

    Item {
        id: systemOverview

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: consoleRoot.systemOverviewAllowed ? 8 : 0
        anchors.leftMargin: 36
        anchors.rightMargin: 36

        height: consoleRoot.systemOverviewAllowed
                ? parent.height * consoleRoot.systemOverviewHeightRatio
                : 0
        visible: !consoleRoot.modernDashboard && consoleRoot.systemOverviewAllowed
        enabled: visible && consoleRoot.shellActive

        property var activeUser: consoleRoot.activeUser
        property int selectedSystem: consoleRoot.selectedSystemCard
        property int armedIndex: -1
        property bool activeAppSelectionMode: false

        function activeView() {
            return consoleRoot.customSystemOverview ? personalizedSystemOverview : defaultSystemOverview
        }
        function moveSelection(delta) {
            var view = activeView()
            if (view && typeof view.moveSelection === "function") view.moveSelection(delta)
            selectedSystem = view ? Number(view.selectedSystem || 0) : 0
            consoleRoot.selectedSystemCard = selectedSystem
        }
        function activateSelected() {
            var view = activeView()
            if (view && typeof view.activateSelected === "function") view.activateSelected()
        }
        function disarmSelected() {
            var view = activeView()
            if (view && typeof view.disarmSelected === "function") return view.disarmSelected()
            return false
        }
        onSelectedSystemChanged: {
            defaultSystemOverview.selectedSystem = selectedSystem
            personalizedSystemOverview.selectedSystem = selectedSystem
        }
        onArmedIndexChanged: {
            defaultSystemOverview.armedIndex = armedIndex
            personalizedSystemOverview.armedIndex = armedIndex
        }

        SystemOverview {
            id: defaultSystemOverview
            anchors.fill: parent
            visible: !consoleRoot.customSystemOverview
            enabled: visible
            activeUser: consoleRoot.activeUser
            controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
            currentTime: consoleRoot.currentTime
            currentDate: consoleRoot.currentDate
            currentTimezoneLabel: consoleRoot.currentTimezoneLabel
            clockTextTint: consoleRoot.currentClockTint
            clockDateTint: consoleRoot.currentDateTint
            clockTimezoneTint: consoleRoot.currentTimezoneTint
            clockScale: consoleRoot.currentClockScale
            showClockDate: consoleRoot.currentShowDate
            showClockTimezone: consoleRoot.currentShowTimezone
            sectionFocused: consoleRoot.selectedSection === 0
            selectedSystem: systemOverview.selectedSystem
            armedIndex: systemOverview.armedIndex
            activeAppSelectionMode: systemOverview.activeAppSelectionMode
            onSelectedSystemChanged: {
                if (systemOverview.selectedSystem !== selectedSystem) systemOverview.selectedSystem = selectedSystem
                consoleRoot.selectedSystemCard = selectedSystem
            }
            onArmedIndexChanged: if (systemOverview.armedIndex !== armedIndex) systemOverview.armedIndex = armedIndex
            onCardClicked: function(cardType, index) {
                consoleRoot.selectedSection = 0
                consoleRoot.selectedSystemCard = index
            }
            onModalRequested: function(modalId, context) {
                consoleRoot.selectedSection = 0
                consoleRoot.selectedSystemCard = selectedSystem
                consoleRoot.disarmAll()
                consoleRoot.openSystemDetailModal(modalId, context)
            }
        }

        PersonalizedSystemOverview {
            id: personalizedSystemOverview
            anchors.fill: parent
            visible: consoleRoot.customSystemOverview
            enabled: visible
            activeUser: consoleRoot.activeUser
            layout: consoleRoot.personalizationBackend ? consoleRoot.personalizationBackend.systemOverviewLayout : []
            currentTime: consoleRoot.currentTime
            currentDate: consoleRoot.currentDate
            currentTimezoneLabel: consoleRoot.currentTimezoneLabel
            sectionFocused: consoleRoot.selectedSection === 0
            selectedSystem: systemOverview.selectedSystem
            armedIndex: systemOverview.armedIndex
            onSelectedSystemChanged: {
                if (systemOverview.selectedSystem !== selectedSystem) systemOverview.selectedSystem = selectedSystem
                consoleRoot.selectedSystemCard = selectedSystem
            }
            onArmedIndexChanged: if (systemOverview.armedIndex !== armedIndex) systemOverview.armedIndex = armedIndex
            onCardClicked: function(cardType, index) {
                consoleRoot.selectedSection = 0
                consoleRoot.selectedSystemCard = index
            }
            onModalRequested: function(modalId, context) {
                consoleRoot.selectedSection = 0
                consoleRoot.selectedSystemCard = selectedSystem
                consoleRoot.disarmAll()
                consoleRoot.openSystemDetailModal(modalId, context)
            }
        }
    }

    Item {
        id: apps
        visible: !consoleRoot.modernDashboard
        enabled: visible && consoleRoot.shellActive

        anchors.top: systemOverview.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: quickActionsDockShell.top
        anchors.topMargin: consoleRoot.systemOverviewAllowed ? 4 : 18
        anchors.leftMargin: 34
        anchors.rightMargin: 34
        anchors.bottomMargin: 8

        property int selectedApp: consoleRoot.selectedApp
        property int appStartIndex: consoleRoot.appStartIndex
        property int visibleAppCount: consoleRoot.visibleAppCount
        property bool sectionFocused: consoleRoot.selectedSection === 1
        property real cameraZoom: consoleRoot.cameraZoom
        property int armedApp: -1

        signal appRequested(var appData, int index)

        function activeLauncher() { return consoleRoot.launcherMode === "grid" ? gridLauncher : carouselLauncher }
        function wrapIndex(index) {
            var launcher = activeLauncher()
            return launcher && typeof launcher.wrapIndex === "function" ? launcher.wrapIndex(index) : Math.max(0, index)
        }
        function setSelectedIndex(index) {
            selectedApp = index
            carouselLauncher.setSelectedIndex(index)
            gridLauncher.setSelectedIndex(index)
        }
        function previousApp() {
            var launcher = activeLauncher()
            if (launcher && typeof launcher.previousApp === "function") launcher.previousApp()
            selectedApp = Number(launcher.selectedApp || 0)
        }
        function nextApp() {
            var launcher = activeLauncher()
            if (launcher && typeof launcher.nextApp === "function") launcher.nextApp()
            selectedApp = Number(launcher.selectedApp || 0)
        }
        function moveUp() {
            var launcher = activeLauncher()
            if (launcher && typeof launcher.moveUp === "function") launcher.moveUp()
            selectedApp = Number(launcher.selectedApp || 0)
        }
        function moveDown() {
            var launcher = activeLauncher()
            if (launcher && typeof launcher.moveDown === "function") launcher.moveDown()
            selectedApp = Number(launcher.selectedApp || 0)
        }
        function activateSelected() {
            var launcher = activeLauncher()
            if (launcher && typeof launcher.activateSelected === "function") launcher.activateSelected()
        }
        function cycleCategory(delta) { if (gridLauncher.visible) gridLauncher.cycleCategory(delta) }
        function cycleSort() { if (gridLauncher.visible) gridLauncher.cycleSort() }

        onSelectedAppChanged: {
            if (consoleRoot.selectedApp !== selectedApp) consoleRoot.selectedApp = selectedApp
            if (carouselLauncher.selectedApp !== selectedApp) carouselLauncher.setSelectedIndex(selectedApp)
            if (gridLauncher.selectedApp !== selectedApp) gridLauncher.setSelectedIndex(selectedApp)
        }
        onArmedAppChanged: {
            carouselLauncher.armedApp = armedApp
            gridLauncher.armedApp = armedApp
        }

        AppsCarousel {
            id: carouselLauncher
            anchors.fill: parent
            visible: consoleRoot.launcherMode !== "grid"
            enabled: visible
            selectedApp: apps.selectedApp
            appStartIndex: apps.appStartIndex
            visibleAppCount: apps.visibleAppCount
            sectionFocused: apps.sectionFocused
            cameraZoom: apps.cameraZoom
            armedApp: apps.armedApp
            onSelectedAppChanged: {
                apps.selectedApp = selectedApp
                apps.appStartIndex = appStartIndex
            }
            onAppStartIndexChanged: apps.appStartIndex = appStartIndex
            onAppRequested: function(appData, index) { apps.appRequested(appData, index) }
        }

        AppGrid {
            id: gridLauncher
            anchors.fill: parent
            visible: consoleRoot.launcherMode === "grid"
            enabled: visible
            selectedApp: apps.selectedApp
            sectionFocused: apps.sectionFocused
            armedApp: apps.armedApp
            cardSizePercent: consoleRoot.personalizationBackend ? Number(consoleRoot.personalizationBackend.gridCardSize || 100) : 100
            spacingPercent: consoleRoot.personalizationBackend ? Number(consoleRoot.personalizationBackend.gridSpacing || 100) : 100
            onSelectedAppChanged: apps.selectedApp = selectedApp
            onAppRequested: function(appData, index) { apps.appRequested(appData, index) }
        }

        onAppRequested: function(appData, index) {
            consoleRoot.selectedSection = 1
            consoleRoot.selectedApp = index
            consoleRoot.disarmAll()
            if (appData) consoleRoot.appLaunchRequested(appData)
        }
    }

    /*
        ============================================================
                        QUICK ACTIONS DOCK SHELL
        ============================================================
    */

    Rectangle {
        id: quickActionsDockShell
        visible: !consoleRoot.modernDashboard
        enabled: visible && consoleRoot.shellActive

        anchors.horizontalCenter: parent.horizontalCenter

        anchors.bottom:
            consoleRoot.hiddenDockVisible
            ? hiddenDock.top
            : parent.bottom

        anchors.bottomMargin:
            consoleRoot.hiddenDockVisible
            ? 12
            : 18

        width:
            Math.min(
                parent.width * 0.92,
                Math.max(
                    height,
                    quickActions.preferredDockWidth + 16
                )
            )

        height:
            Math.max(
                104,
                Math.min(
                    136,
                    parent.height *
                    consoleRoot.quickDockHeightRatio
                )
            )

        radius: height / 2

        color:
            quickActions.customizationArmed
            ? "#321018E8"
            : consoleRoot.selectedSection === 2
              ? "#071426E0"
              : "#071426B8"

        border.width:
            quickActions.customizationArmed || consoleRoot.selectedSection === 2
            ? 2
            : 1

        border.color:
            quickActions.customizationArmed
            ? "#FF3040"
            : consoleRoot.selectedSection === 2
              ? "#7df9ff"
              : "#337df9aa"

        opacity: 0.96
        z: 4
        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"

            opacity:
                consoleRoot.selectedSection === 2
                ? 0.050
                : 0.034
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 1
            color: "#FFFFFF"

            opacity:
                consoleRoot.selectedSection === 2
                ? 0.24
                : 0.12
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -parent.height * 0.72

            width: parent.width * 0.82
            height: parent.height * 1.35
            radius: height / 2

            color:
                consoleRoot.selectedSection === 2
                ? "#7df9ff"
                : "#47c8ff"

            opacity:
                consoleRoot.selectedSection === 2
                ? 0.030 +
                  consoleRoot.dockGlowPulse * 0.040
                : 0.018
        }

        Rectangle {
            width: 140
            height: 2
            radius: 1

            x:
                (parent.width - width) *
                (
                    (consoleRoot.dockSweep + 1.0) /
                    2.0
                )

            anchors.verticalCenter: parent.verticalCenter

            color: "#7df9ff"

            opacity:
                consoleRoot.selectedSection === 2
                ? 0.12 +
                  consoleRoot.dockGlowPulse * 0.20
                : 0.05
        }
    }

    QuickActions {
        id: quickActions

        anchors.fill: quickActionsDockShell
        anchors.margins: 8

        /* Selection is owned here; Console mirrors it through the signal below. */

        sectionFocused:
            consoleRoot.selectedSection === 2

        z: 5

        onSelectedActionChanged: {
            if (consoleRoot.selectedAction !== selectedAction)
                consoleRoot.selectedAction = selectedAction

            consoleRoot.playQuickDockMotion()
        }

        onActionRequested: function(actionData, index) {
            consoleRoot.selectedSection = 2
            consoleRoot.selectedAction = index

            if (consoleRoot.quickActionNeedsConfirmation(actionData)) {
                consoleRoot.disarmAll()
                quickActions.armedAction = index
                quickActionModal.open(actionData)
                return
            }

            consoleRoot.executeQuickAction(actionData)
        }

        onCustomizationRequested: function(selectedSlot) {
            consoleRoot.selectedSection = 2
            var count = consoleRoot.actionCount()
            consoleRoot.selectedAction = count > 0
                    ? Math.max(0, Math.min(count - 1, selectedSlot))
                    : 0
            quickActions.customizationArmed = true
            quickActionCustomizeModal.open(consoleRoot.selectedAction)
        }
    }

    Connections {
        target: consoleRoot.quickBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onDockActionsChanged() {
            var count = consoleRoot.actionCount()
            consoleRoot.selectedAction = count > 0
                    ? Math.max(0, Math.min(count - 1, consoleRoot.selectedAction))
                    : 0
            quickActions.selectedAction = consoleRoot.selectedAction
            Qt.callLater(quickActions.ensureSelectedVisible)
        }

        function onActionLaunchRequested(appData) {
            consoleRoot.appLaunchRequested(appData)
        }

        function onControllerOffRequested() {
            consoleRoot.controllerOffRequested()
        }

        function onScreensaverRequested() {
            consoleRoot.screensaverRequested()
        }

        function onHelpRequested() {
            consoleRoot.openHelpCenter()
        }
    }

    /*
        ============================================================
                            HIDDEN APP DOCK
        ============================================================
    */

    HiddenDock {
        id: hiddenDock

        property int armedDock: -1

        visible:
            consoleRoot.hiddenDockVisible &&
            consoleRoot.dockUnlocked()

        opened:
            consoleRoot.hiddenDockVisible &&
            consoleRoot.dockUnlocked()

        enabled:
            consoleRoot.hiddenDockVisible &&
            consoleRoot.dockUnlocked()

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14

        selectedIndex: consoleRoot.selectedDock
        externallyControlled: true

        sectionFocused:
            consoleRoot.selectedSection === 3

        z: 20
    }

    Connections {
        target: hiddenDock
        ignoreUnknownSignals: true

        /*
            HiddenDock emits compatibility app/action signals in addition to
            itemRequested. Console consumes only the canonical item signal so
            one X press cannot launch or execute the same item multiple times.
        */
        function onItemRequested(itemData, index) {
            consoleRoot.selectedDock = index
            consoleRoot.disarmAll()
            consoleRoot.handleHiddenDockItem(itemData)
        }

        function onClosed() {
            consoleRoot.restoreConsoleFromHiddenDock()
        }
    }

    /*
        ============================================================
              ON-DEMAND SYSTEM DETAIL PANELS
        ============================================================

        Clock and User settings now use the same proven synchronous Loader
        path as every other System Overview panel. Their earlier load failures
        were QML type errors, not a Loader limitation. Unloading them when
        closed releases their category pages, avatar models, timezone models,
        and preview surfaces instead of keeping both large control centers in
        memory for the entire Console session.
    */

    /*
        ============================================================
                    LAZY SYSTEM-DETAIL MODAL
        ============================================================
    */

    Loader {
        id: systemDetailLoader

        anchors.fill: parent
        z: 25000

        active: consoleRoot.systemDetailModalOpen
        visible: active
        enabled: active
        opacity: 1.0

        source: consoleRoot.systemDetailModalQmlSource

        asynchronous: false

        onLoaded: {
            if (!item)
                return

            try {
                item.visible = true
                item.enabled = true
                item.opacity = 1.0
            } catch (error) {
            }

            consoleRoot.openLoadedSystemDetailModal()
        }

        onStatusChanged: {
            if (status === Loader.Error) {
                consoleRoot.systemDetailLoadSource = String(consoleRoot.systemDetailModalQmlSource || "")
                consoleRoot.systemDetailLoadError =
                        "Could not load " +
                        (consoleRoot.systemDetailModalId.length > 0
                         ? consoleRoot.systemDetailModalId.toUpperCase()
                         : "SYSTEM SETTINGS") +
                        "."

                consoleRoot.log(
                    "System detail modal failed to load:",
                    consoleRoot.systemDetailModalId,
                    consoleRoot.systemDetailModalQmlSource
                )

                Qt.callLater(function() {
                    consoleRoot.systemDetailModalId = ""
                    consoleRoot.systemDetailModalContext = ({})
                    systemDetailUnloadTimer.restart()
                    consoleRoot.forceActiveFocus()
                })
            }
        }
    }

    Rectangle {
        id: systemDetailErrorOverlay

        anchors.fill: parent
        visible: consoleRoot.systemDetailLoadError.length > 0
        enabled: visible
        focus: visible
        z: 25010
        color: "#D802050B"

        function closeError() {
            consoleRoot.systemDetailLoadError = ""
            consoleRoot.systemDetailLoadSource = ""
            consoleRoot.forceActiveFocus()
            consoleRoot.focusCurrentSection()
            return true
        }

        function handleControllerPressed(action) {
            var value = String(action || "").toLowerCase()
            if (value === "primary" || value === "x" || value === "confirm" ||
                    value === "cancel" || value === "o" || value === "back" ||
                    value === "system" || value === "home") {
                return closeError()
            }
            return true
        }

        Keys.onPressed: function(event) {
            if (!visible)
                return
            event.accepted = true
            closeError()
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.visible
            cursorShape: Qt.PointingHandCursor
            onClicked: systemDetailErrorOverlay.closeError()
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 160, 980)
            height: 390
            radius: 32
            color: "#071426"
            border.width: 2
            border.color: "#FF3040"

            Column {
                anchors.centerIn: parent
                width: parent.width - 96
                spacing: 22

                Text {
                    width: parent.width
                    text: "SYSTEM PANEL LOAD FAILED"
                    color: "#FF3040"
                    font.pixelSize: 36
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: consoleRoot.systemDetailLoadError
                    color: "#FFFFFF"
                    font.pixelSize: 23
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    text: consoleRoot.systemDetailLoadSource.length > 0
                          ? consoleRoot.systemDetailLoadSource
                          : "The panel source did not report a path."
                    color: "#8AA6C8"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                }

                Text {
                    width: parent.width
                    text: "PRESS X OR O TO RETURN"
                    color: "#7DF9FF"
                    font.pixelSize: 17
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Connections {
        target: systemDetailLoader.item
        ignoreUnknownSignals: true

        function onClosed() {
            systemDetailUnloadTimer.restart()
        }

        function onActionRequested(action, payload) {
            consoleRoot.handleSystemDetailAction(
                consoleRoot.systemDetailModalId,
                action,
                payload
            )
        }
    }

    CriticalWarningModal {
        id: criticalWarningModal

        onDismissed: consoleRoot.showNextCriticalWarning()
    }

    Connections {
        target: consoleRoot.securityBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onLockoutStarted() {
            consoleRoot.showCriticalWarning(
                "SECURITY LOCKOUT ACTIVE",
                "Repeated authentication failures triggered a temporary NeutronOS security lockout.",
                "SECURITY"
            )
        }

        function onUnlockDenied(message, failedAttempts, secondsRemaining) {
            if (Number(secondsRemaining || 0) > 0 || Number(failedAttempts || 0) >= 3) {
                consoleRoot.showCriticalWarning(
                    "AUTHENTICATION BLOCKED",
                    String(message || "Authentication was denied.") +
                    (Number(secondsRemaining || 0) > 0 ? " Try again in " + secondsRemaining + " seconds." : ""),
                    "SECURITY"
                )
            }
        }

        function onOperationFinished(action, success, message, payload) {
            if (!success) {
                consoleRoot.showCriticalWarning(
                    "SECURITY OPERATION FAILED",
                    String(message || (String(action || "Security operation") + " failed.")),
                    "SECURITY"
                )
            }
        }
    }

    Connections {
        target: consoleRoot.monitorBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onThermalThrottledChanged() {
            if (consoleRoot.monitorBackend && consoleRoot.monitorBackend.thermalThrottled) {
                consoleRoot.showCriticalWarning(
                    "THERMAL THROTTLING DETECTED",
                    "The system reduced performance to protect the hardware. Current status: " +
                    String(consoleRoot.monitorBackend.thermalStatus || "Throttled") + ".",
                    "SYSTEM MONITOR"
                )
            }
        }

        function onThrottlingEventsChanged() {
            if (!consoleRoot.monitorBackend)
                return
            var events = Number(consoleRoot.monitorBackend.throttlingEvents || 0)
            if (events > consoleRoot.lastObservedThrottleEvents) {
                consoleRoot.lastObservedThrottleEvents = events
                consoleRoot.showCriticalWarning(
                    "NEW THROTTLE EVENT",
                    "NeutronOS recorded a new CPU throttle event. Check cooling, power delivery, and system temperature.",
                    "SYSTEM MONITOR"
                )
            } else {
                consoleRoot.lastObservedThrottleEvents = events
            }
        }
    }

    Connections {
        target: consoleRoot.appBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onAppActionFinished(appId, actionName, success, message) {
            if (!success && consoleRoot.criticalMessage(message)) {
                consoleRoot.showCriticalWarning(
                    "CRITICAL APP ERROR",
                    String(message || (String(appId || "Application") + " reported a critical failure.")),
                    String(appId || "APPLICATION")
                )
            }
        }
    }

    Connections {
        target: consoleRoot.settingsBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onOperationFinished(action, success, message) {
            if (!success && consoleRoot.criticalMessage(message)) {
                consoleRoot.showCriticalWarning(
                    "CRITICAL SYSTEM ERROR",
                    String(message || (String(action || "System operation") + " failed.")),
                    "SETTINGS"
                )
            }
        }
    }

    /*
        ============================================================
                            EXISTING MODALS
        ============================================================
    */

    /*
        Session/logout controls are global and owned by Main.qml.
        Console intentionally does not instantiate the obsolete UserModal.
    */

    AppModal {
        id: appModal

        activeUser: consoleRoot.activeUser

        onClosed: {
            consoleRoot.disarmAll()
            consoleRoot.focusCurrentSection()
        }

        onFavoriteChanged: function(appId) {
            consoleRoot.selectedSection = 1
            consoleRoot.selectedApp = 0
            apps.setSelectedIndex(0)
        }

        onOpenRequested: function(appData) {
            consoleRoot.disarmAll()
            consoleRoot.appLaunchRequested(appData)
        }

        onRestartRequested: function(appData) {
            consoleRoot.disarmAll()
            consoleRoot.appLaunchRequested(appData)
        }

        onKillRequested: function(appData) {
            consoleRoot.disarmAll()
            consoleRoot.focusCurrentSection()
        }

        onAppUninstalled: function(appId) {
            consoleRoot.selectedSection = 1
            consoleRoot.selectedApp = Math.max(0, Math.min(
                consoleRoot.selectedApp,
                Math.max(0, consoleRoot.favoriteAppCount() - 1)
            ))
            apps.setSelectedIndex(consoleRoot.selectedApp)
        }
    }

    AppCarouselModal {
        id: appCarouselModal

        onClosed: {
            var index = Math.max(
                0,
                Math.min(
                    selectedIndex,
                    Math.max(0, consoleRoot.favoriteAppCount() - 1)
                )
            )

            consoleRoot.selectedSection = 1
            consoleRoot.selectedApp = index
            apps.setSelectedIndex(index)
            consoleRoot.disarmAll()
            consoleRoot.focusCurrentSection()
        }

        onOrderChanged: function(appId, index) {
            consoleRoot.selectedSection = 1
            consoleRoot.selectedApp = index
            apps.setSelectedIndex(index)
        }
    }

    QuickActionModal {
        id: quickActionModal

        onClosed:
            consoleRoot.disarmAll()

        onConfirmed: function(actionData) {
            consoleRoot.executeQuickAction(actionData)
        }

        onCancelled:
            consoleRoot.disarmAll()
    }

    QuickActionCustomizeModal {
        id: quickActionCustomizeModal

        onClosed: {
            quickActions.customizationArmed = false
            consoleRoot.disarmAll()
            consoleRoot.focusCurrentSection()
        }

        onLayoutChanged: {
            var count = consoleRoot.actionCount()
            consoleRoot.selectedAction = count > 0
                    ? Math.max(0, Math.min(count - 1, consoleRoot.selectedAction))
                    : 0
            quickActions.selectedAction = consoleRoot.selectedAction
            Qt.callLater(quickActions.ensureSelectedVisible)
        }
    }

    HelpModal {
        id: helpModal

        onLoginInstructionsRequested: {
            helpModal.close()
            loginInstructionsModal.openManual()
        }

        onClosed: {
            consoleRoot.disarmAll()
            consoleRoot.focusCurrentSection()
        }
    }

    LoginInstructionsModal {
        id: loginInstructionsModal
        onClosed: {
            consoleRoot.disarmAll()
            consoleRoot.focusCurrentSection()
        }
    }

    HiddenDockSecurityModal {
        id: hiddenDockSecurityModal

        onUnlocked: {
            if (consoleRoot.selectedSection !== 3)
                consoleRoot.hiddenDockReturnSection = Math.max(0, Math.min(2, consoleRoot.selectedSection))

            consoleRoot.hiddenDockVisible = true

            if (consoleRoot.dockSecurity &&
                    typeof consoleRoot.dockSecurity.unlock === "function") {
                consoleRoot.dockSecurity.unlock()
            }

            if (hiddenDock &&
                    typeof hiddenDock.playUnlockFlash === "function") {
                hiddenDock.playUnlockFlash()
            }

            consoleRoot.selectedSection = 3
            consoleRoot.disarmAll()
            consoleRoot.focusCurrentSection()
        }

        onCancelled: {
            consoleRoot.disarmAll()
            consoleRoot.focusCurrentSection()
        }
    }

    /*
        ============================================================
                    SYSTEM-DETAIL MODAL ROUTING
                    DIRECT CONTROL CENTERS V2
        ============================================================
    */

    function residentSystemDetailModal(modalId) {
        return null
    }

    function currentSystemDetailModal() {
        return systemDetailLoader.item
    }

    function closeResidentSystemDetailPanels(exceptId) {
        /* All System Overview detail panels are unloaded by the Loader. */
    }

    function systemDetailModalSource(modalId) {
        if (modalId === "cpu")
            return "modals/system/CpuMonitorModal.qml"

        if (modalId === "memory")
            return "modals/system/MemoryMonitorModal.qml"

        if (modalId === "storage")
            return "modals/system/StorageDisplayModal.qml"

        if (modalId === "activeApp")
            return "modals/system/ActiveAppModal.qml"

        if (modalId === "temperature")
            return "modals/system/TemperatureHistoryModal.qml"

        if (modalId === "network")
            return "modals/system/NetworkManagerModal.qml"

        if (modalId === "headerClock")
            return "modals/system/ClockSettingsModal.qml"

        if (modalId === "headerSecurity")
            return "modals/system/HeaderSecurityModal.qml"

        if (modalId === "headerUser")
            return "modals/system/UserProfileSettingsModal.qml"

        if (modalId === "controllerPromo")
            return "modals/system/ControllerPromotionModal.qml"

        if (modalId === "controllerSettings")
            return "modals/system/ControllerSettingsModal.qml"

        if (modalId === "clock")
            return "modals/system/ClockSettingsModal.qml"

        if (modalId === "user")
            return "modals/system/UserProfileSettingsModal.qml"

        if (modalId === "personalization")
            return "modals/system/PersonalizationModal.qml"

        return ""
    }

    function openSystemDetailModal(modalId, context) {
        var resident = residentSystemDetailModal(modalId)
        var source = systemDetailModalSource(modalId)

        if (!resident && source.length <= 0) {
            consoleRoot.log(
                "Unknown System Overview modal:",
                modalId
            )
            return false
        }

        systemDetailUnloadTimer.stop()
        consoleRoot.systemDetailLoadError = ""
        consoleRoot.systemDetailLoadSource = ""
        consoleRoot.closeResidentSystemDetailPanels(modalId)

        consoleRoot.systemDetailModalContext = context || ({})
        // Update the routing id before swapping the explicit Loader source. If a
        // detail panel opens another detail panel while the Loader is already
        // active, synchronous loading then sees the new modal id/context.
        consoleRoot.systemDetailModalId = modalId
        consoleRoot.systemDetailModalQmlSource = source

        if (resident) {
            try {
                resident.visible = true
                resident.enabled = true
                resident.opacity = 1.0
            } catch (visibilityError) {
            }

            consoleRoot.openLoadedSystemDetailModal()
        }

        return true
    }

    function openLoadedSystemDetailModal() {
        var modal = consoleRoot.currentSystemDetailModal()

        if (!modal)
            return false

        var context =
            consoleRoot.systemDetailModalContext ||
            ({})

        try {
            if ("contextData" in modal)
                modal.contextData = context
        } catch (e1) {
        }

        try {
            if ("modalContext" in modal)
                modal.modalContext = context
        } catch (e2) {
        }

        try {
            if ("activeUser" in modal &&
                    context.user) {
                modal.activeUser = context.user
            }
        } catch (e3) {
        }

        if (typeof modal.open === "function") {
            modal.open(context)
        } else if (typeof modal.openModal === "function") {
            modal.openModal(context)
        } else {
            try {
                modal.visible = true
            } catch (e4) {
            }
        }

        if (typeof modal.forceActiveFocus === "function")
            modal.forceActiveFocus()

        return true
    }

    function closeSystemDetailModal() {
        if (!consoleRoot.systemDetailModalOpen)
            return

        var modal = consoleRoot.currentSystemDetailModal()

        if (modal) {
            if (typeof modal.close === "function") {
                modal.close()
            } else if (typeof modal.closeModal === "function") {
                modal.closeModal()
            } else {
                try {
                    modal.visible = false
                } catch (e) {
                }
            }
        }

        systemDetailUnloadTimer.restart()
    }

    function systemDetailPayloadApp(payload) {
        if (payload) {
            try {
                if (payload.app)
                    return payload.app
            } catch (e1) {
            }
        }

        try {
            if (consoleRoot.systemDetailModalContext.app)
                return consoleRoot.systemDetailModalContext.app
        } catch (e2) {
        }

        return null
    }

    function handleSystemDetailAction(
        modalId,
        action,
        payload
    ) {
        var normalized =
            String(action || "")
            .trim()
            .toLowerCase()

        if (normalized === "cancel" ||
                normalized === "close" ||
                normalized === "back") {
            closeSystemDetailModal()
            return
        }

        if (modalId === "user" && normalized === "personalization") {
            consoleRoot.openSystemDetailModal(
                "personalization",
                payload || ({ "username": consoleRoot.activeUsernameForPersonalization() })
            )
            return
        }

        // NEUTRONOS_DIRECT_USER_CONTROL_CENTER_ACTIONS_V2
        if (modalId === "user") {
            if (normalized === "lock") {
                closeSystemDetailModal()
                consoleRoot.logoutRequested()
                return
            }
            if (normalized === "restart") {
                closeSystemDetailModal()
                consoleRoot.restartShellRequested()
                return
            }
            if (normalized === "reboot") {
                closeSystemDetailModal()
                consoleRoot.rebootRequested()
                return
            }
            if (normalized === "logout") {
                closeSystemDetailModal()
                consoleRoot.logoutRequested()
                return
            }
            if (normalized === "poweroff") {
                closeSystemDetailModal()
                consoleRoot.shutdownRequested()
                return
            }
        }

        if (modalId === "clock" && normalized === "clockiconchanged") {
            modernDashboardView.refreshHeaderClockIcon()
            return
        }

        if (modalId === "headerClock") {
            if (normalized === "clockiconchanged") {
                modernDashboardView.refreshHeaderClockIcon()
                return
            }
            if (normalized === "openclocksection") {
                consoleRoot.openSystemDetailModal("clock", {
                    "focusSection": String(payload && payload.section || "format")
                })
                return
            }
        }

        if (modalId === "headerUser") {
            if (normalized === "openusersection") {
                consoleRoot.openSystemDetailModal("user", {
                    "focusSection": String(payload && payload.section || "profile"),
                    "user": payload && payload.user ? payload.user : consoleRoot.activeUser
                })
                return
            }
            if (normalized === "restart") {
                closeSystemDetailModal()
                consoleRoot.restartShellRequested()
                return
            }
            if (normalized === "reboot") {
                closeSystemDetailModal()
                consoleRoot.rebootRequested()
                return
            }
            if (normalized === "logout") {
                closeSystemDetailModal()
                consoleRoot.logoutRequested()
                return
            }
            if (normalized === "poweroff") {
                closeSystemDetailModal()
                consoleRoot.shutdownRequested()
                return
            }
        }

        if (modalId === "controllerPromo" && normalized === "openappstore") {
            var requestedPackageId = String(payload && payload.packageId || "customcontrollers")
            var apps = consoleRoot.appList()
            for (var storeIndex = 0; storeIndex < apps.length; ++storeIndex) {
                var candidate = apps[storeIndex] || ({})
                if (String(candidate.id || candidate.appId || "").toLowerCase() !== "appstore")
                    continue
                var launchData = ({})
                for (var key in candidate)
                    launchData[key] = candidate[key]
                launchData.preselectPackageId = requestedPackageId
                launchData.launchContext = { "packageId": requestedPackageId }
                closeSystemDetailModal()
                consoleRoot.appLaunchRequested(launchData)
                return
            }
            consoleRoot.log("App Store launch target not found for controller promotion")
            return
        }

        if (modalId === "activeApp") {
            var appData =
                systemDetailPayloadApp(payload)

            if (!appData) {
                consoleRoot.log(
                    "Active app action blocked:",
                    normalized,
                    "missing app data"
                )
                return
            }

            if (normalized === "start" ||
                    normalized === "exit" ||
                    normalized === "stop" ||
                    normalized === "restart" ||
                    normalized === "kill") {
                executeAppServiceAction(
                    appData,
                    normalized === "exit" ? "stop" : normalized
                )

                closeSystemDetailModal()
                return
            }
        }

        if (modalId === "storage" &&
                normalized === "apply") {
            if (typeof systemMonitor !== "undefined" &&
                    systemMonitor &&
                    typeof systemMonitor.setDisplayedMounts === "function") {
                systemMonitor.setDisplayedMounts(payload)
            } else {
                consoleRoot.log(
                    "Storage display selection queued:",
                    JSON.stringify(payload || {})
                )
            }

            closeSystemDetailModal()
            return
        }

        if (modalId === "network") {
            if (networkBackend &&
                    typeof networkBackend.executeAction === "function") {
                networkBackend.executeAction(
                    normalized,
                    payload
                )
                return
            }

            consoleRoot.log(
                "Network action queued:",
                normalized
            )
            return
        }


        if (modalId === "controllerSettings") {
            // Desktop v2.4 intentionally keeps the shell controller center
            // connection-only. Light/haptics/custom profiles belong to the
            // optional controller app distributed through the App Store.
            if (normalized === "close")
                closeSystemDetailModal()
            return
        }

        if (modalId === "clock") {
            if (normalized === "presentationchanged") {
                consoleRoot.refreshClockPresentation()
                return
            }

            if (normalized === "timezonechanged") {
                if (clockBackend && typeof clockBackend.setTimezone === "function")
                    clockBackend.setTimezone(String(payload.timezone || "UTC"))
                consoleRoot.refreshClockPresentation()
                return
            }

            if (normalized === "reset") {
                if (clockExperienceBackend && typeof clockExperienceBackend.resetDefaults === "function")
                    clockExperienceBackend.resetDefaults()
                consoleRoot.refreshClockPresentation()
                return
            }

            if (normalized === "apply") {
                if (clockExperienceBackend && typeof clockExperienceBackend.applySettings === "function")
                    clockExperienceBackend.applySettings(payload)

                if (clockBackend && typeof clockBackend.applySettings === "function")
                    clockBackend.applySettings(payload)

                consoleRoot.refreshClockPresentation()
                closeSystemDetailModal()
                return
            }
        }

        if (modalId === "user") {
            if (normalized === "screensavertimeout") {
                /*
                    UserSettingsModal writes directly to ScreensaverManager.
                    Keep the modal open and avoid forwarding this setting to
                    the profile backend.
                */
                return
            }

            if (normalized === "logout" || normalized === "lock") {
                closeSystemDetailModal()
                consoleRoot.logoutRequested()
                return
            }

            if (userBackend &&
                    typeof userBackend.executeAction === "function") {
                userBackend.executeAction(
                    normalized,
                    payload
                )
                return
            }

            consoleRoot.log(
                "User action queued:",
                normalized
            )
            return
        }

        consoleRoot.log(
            "Unhandled System Overview modal action:",
            modalId,
            normalized
        )
    }

    /*
        ============================================================
                        CONTROLLER INPUT API
        ============================================================
    */

    function handleController(button) {
        return handleControllerPressed(button)
    }

    function handleControllerPressed(button) {
        var action =
            normalizeControllerAction(button)

        if (action.length === 0)
            return true

        // Main.qml owns Global Search.  Consume every Console-side route while
        // it is open so no dashboard/app selection can move underneath it.
        if (consoleRoot.globalSearchActive)
            return true

        if (!consoleRoot.shellActive)
            return true

        if (consoleRoot.modalOpen) {
            handleModalController(action)
            return true
        }

        // The Dashboard tab selector is a global modal surface, including
        // while the real Legacy Console is the active view.  Route it before
        // any Legacy/notification handlers so no input leaks underneath.
        if (modernDashboardView && modernDashboardView.selectorOpen)
            return modernDashboardView.handleControllerPressed(action)

        if (!consoleRoot.modernDashboard && action === "home") {
            modernDashboardView.activeMode = "legacy"
            modernDashboardView.selectorOnly = true
            modernDashboardView.openSelector()
            return true
        }

        if (consoleRoot.modernDashboard)
            return modernDashboardView.handleControllerPressed(action)


        if ((action === "l3" || action === "r3") &&
                consoleRoot.selectedSection === 1) {
            if (consoleRoot.launcherMode === "grid") {
                if (action === "l3") apps.cycleCategory(1)
                else apps.cycleSort()
            } else {
                openCarouselSettingsModal()
            }
            return true
        }

        if (action === "cancel") {
            handleCancel()
            return true
        }

        if (action === "primary") {
            activateSelected()
            return true
        }

        if (action === "context" ||
                action === "secondary") {
            // Patch 60K: Triangle owns the Hidden Dock globally.
            openHiddenDockOrSecurity()
            return true
        }

        if (action === "system") {
            // Patch 60K: Start arms the highlighted app and immediately opens
            // its controller-first settings/options modal.
            if (consoleRoot.selectedSection === 1)
                armAndOpenSelectedAppOptions()
            else
                openHiddenDockOrSecurity()
            return true
        }

        if (action === "quick") {
            setSelectedSection(2)
            return true
        }

        if (action === "up" && consoleRoot.selectedSection === 0) {
            consoleRoot.disarmAll()
            consoleRoot.notificationCenterRequested()
            return true
        }

        if (action === "up") {
            if (consoleRoot.selectedSection === 1 && consoleRoot.launcherMode === "grid")
                apps.moveUp()
            else
                requestSectionMove(-1)
            return true
        }

        if (action === "down") {
            if (consoleRoot.selectedSection === 1 && consoleRoot.launcherMode === "grid")
                apps.moveDown()
            else
                requestSectionMove(1)
            return true
        }

        if (action === "l1") { requestSectionMove(-1); return true }
        if (action === "r1") { requestSectionMove(1); return true }

        if (action === "left") {
            moveLeft()
            disarmAll()
            return true
        }

        if (action === "right") {
            moveRight()
            disarmAll()
            return true
        }

        if (action === "l2") {
            if (consoleRoot.selectedSection === 1 && consoleRoot.launcherMode === "grid") apps.cycleCategory(-1)
            else pageLeft()
            disarmAll()
            return true
        }

        if (action === "r2") {
            if (consoleRoot.selectedSection === 1 && consoleRoot.launcherMode === "grid") apps.cycleCategory(1)
            else pageRight()
            disarmAll()
            return true
        }

        return true
    }

    function handleControllerReleased(button) {
        var action = normalizeControllerAction(button)
        if ((consoleRoot.modernDashboard ||
                (modernDashboardView && modernDashboardView.selectorOpen)) &&
                modernDashboardView &&
                typeof modernDashboardView.handleControllerReleased === "function")
            return modernDashboardView.handleControllerReleased(action)
        return true
    }

    function handleModalController(action) {
        var modal = activeModal()

        if (!modal) {
            if (action === "cancel" ||
                    action === "system" ||
                    action === "home") {
                closeOpenModal()
            }

            return
        }

        if (typeof modal.handleControllerPressed === "function") {
            modal.handleControllerPressed(action)
            return
        }

        if (typeof modal.handleController === "function") {
            modal.handleController(action)
            return
        }

        if (action === "cancel" ||
                action === "system" ||
                action === "home") {
            closeOpenModal()
            disarmAll()
        }
    }

    function activeModal() {
        if (criticalWarningModal.visible)
            return criticalWarningModal

        if (systemDetailLoadError.length > 0)
            return systemDetailErrorOverlay

        if (systemDetailModalOpen) {
            var detailModal = consoleRoot.currentSystemDetailModal()
            if (detailModal && detailModal.visible !== false)
                return detailModal
        }

        if (appModal.visible)
            return appModal

        if (appCarouselModal.visible)
            return appCarouselModal

        if (quickActionModal.visible)
            return quickActionModal

        if (quickActionCustomizeModal.visible)
            return quickActionCustomizeModal

        if (helpModal.visible)
            return helpModal

        if (loginInstructionsModal.visible)
            return loginInstructionsModal

        if (hiddenDockSecurityModal.visible)
            return hiddenDockSecurityModal

        if (hiddenDock.performanceProfileModalVisible)
            return hiddenDock

        return null
    }

    /*
        ============================================================
                        SAFE SELECTION HELPERS
        ============================================================
    */

    function maxSelectableSection() {
        return (
            consoleRoot.hiddenDockVisible &&
            consoleRoot.dockUnlocked()
        )
        ? 3
        : 2
    }

    function clampSection(section) {
        var minimum = consoleRoot.systemOverviewAllowed ? 0 : 1
        return Math.max(minimum, Math.min(maxSelectableSection(), section))
    }

    function setSelectedSection(section) {
        var nextSection =
            clampSection(section)

        if (selectedSection !== nextSection)
            selectedSection = nextSection

        disarmAll()
        focusCurrentSection()
    }

    function requestSectionMove(delta) {
        if (sectionMoveLocked)
            return

        sectionMoveLocked = true
        sectionMoveCooldownTimer.restart()

        setSelectedSection(
            selectedSection + delta
        )
    }

    function focusCurrentSection() {
        consoleRoot.forceActiveFocus()
        if (consoleRoot.modernDashboard)
            modernDashboardView.forceActiveFocus()
    }

    function anyArmed() {
        return systemOverview.armedIndex !== -1 ||
               apps.armedApp !== -1 ||
               quickActions.armedAction !== -1 ||
               quickActions.customizationArmed ||
               hiddenDock.armedDock !== -1
    }

    function currentAppIndex() {
        var len = favoriteAppCount()

        if (len <= 0)
            return -1

        if (apps &&
                typeof apps.wrapIndex === "function") {
            return apps.wrapIndex(
                apps.selectedApp
            )
        }

        return Math.max(
            0,
            Math.min(
                selectedApp,
                len - 1
            )
        )
    }

    function safeSelectedAction() {
        var len = actionCount()

        if (len <= 0)
            return -1

        return Math.max(
            0,
            Math.min(
                selectedAction,
                len - 1
            )
        )
    }

    function safeSelectedSystem() {
        var count = consoleRoot.customSystemOverview && consoleRoot.personalizationBackend
                    ? Number(consoleRoot.personalizationBackend.systemOverviewLayout.length || 0)
                    : systemCardTypes.length
        return Math.max(0, Math.min(selectedSystemCard, Math.max(0, count - 1)))
    }

    function hiddenDockCount() {
        if (hiddenDock &&
                typeof hiddenDock.itemCount === "function") {
            return hiddenDock.itemCount()
        }

        return appList().length
    }

    function safeSelectedDock() {
        var len = hiddenDockCount()

        if (len <= 0)
            return -1

        return Math.max(
            0,
            Math.min(
                selectedDock,
                len - 1
            )
        )
    }

    function selectedHiddenDockItem() {
        var idx = safeSelectedDock()

        if (idx === -1)
            return null

        if (hiddenDock &&
                typeof hiddenDock.itemAt === "function") {
            return hiddenDock.itemAt(idx)
        }

        var fallbackApps = appList()
        return fallbackApps[idx] || null
    }

    function syncSelectedAppFromCarousel() {
        if (!apps)
            return

        consoleRoot.selectedApp =
            apps.selectedApp

        consoleRoot.appStartIndex =
            apps.appStartIndex
    }

    /*
        ============================================================
                            APP LAUNCHING
        ============================================================
    */

    function launchSelectedApp() {
        if (launchLocked)
            return

        launchLocked = true
        launchCooldownTimer.restart()

        syncSelectedAppFromCarousel()

        var idx = currentAppIndex()

        if (idx === -1) {
            consoleRoot.log(
                "Launch blocked: no selected app"
            )
            return
        }

        var favorites = favoriteAppList()
        var appData = favorites[idx]

        if (!appData) {
            consoleRoot.log(
                "Launch blocked: appData missing"
            )
            return
        }

        consoleRoot.log(
            "Console requesting app launch:",
            appData.name || "Unknown"
        )

        consoleRoot.log(
            "App id:",
            appData.id || "missing"
        )

        consoleRoot.log(
            "App type:",
            appData.type || "missing"
        )

        consoleRoot.log(
            "App qmlSource:",
            appData.qmlSource || "missing"
        )

        consoleRoot.log(
            "App entry:",
            appData.entry || "missing"
        )

        consoleRoot.log(
            "App running:",
            appData.running
        )

        closeOpenModal()
        disarmAll()

        consoleRoot.appLaunchRequested(appData)
    }

    function armAndOpenSelectedAppOptions() {
        var idx = currentAppIndex()
        if (idx < 0)
            return
        var favorites = favoriteAppList()
        var appData = favorites[idx]
        if (!appData)
            return
        refreshClockPresentation()
        disarmAll()
        selectedSection = 1
        selectedApp = idx
        apps.armedApp = idx
        appModal.open(appData)
    }

    function openSelectedModal() {
        var idx = currentAppIndex()

        if (idx === -1)
            return

        var favorites = favoriteAppList()
        var appData = favorites[idx]

        if (!appData)
            return

        refreshClockPresentation()

        selectedSection = 1
        selectedApp = idx
        disarmAll()
        appModal.open(appData)
    }

    function openCarouselSettingsModal() {
        var index = currentAppIndex()
        var appData = index >= 0 ? favoriteAppList()[index] : null

        disarmAll()
        appCarouselModal.open(appData)
    }

    function openSelectedQuickActionModal() {
        var idx = safeSelectedAction()

        if (idx === -1)
            return

        var actions = actionList()
        var actionData = actions[idx]

        if (!actionData)
            return

        selectedSection = 2
        selectedAction = idx
        quickActions.armedAction = idx
        quickActionModal.open(actionData)
    }

    function openSelectedSystemModal() {
        selectedSection = 0

        systemOverview.selectedSystem =
            safeSelectedSystem()

        selectedSystemCard =
            systemOverview.selectedSystem

        systemOverview.activateSelected()
    }

    /*
        ============================================================
                        HIDDEN DOCK ACTIONS
        ============================================================
    */

    function developerModeIsEnabled() {
        try {
            return typeof developerModeManager !== "undefined" &&
                   developerModeManager &&
                   !!developerModeManager.developerModeEnabled
        } catch (error) {
            return false
        }
    }

    function powerModeBackend() {
        try {
            if (typeof powerModeManager !== "undefined" && powerModeManager)
                return powerModeManager
        } catch (error) {
        }

        return null
    }

    function selectedHiddenActionName() {
        var item = selectedHiddenDockItem()

        if (!item)
            return ""

        try {
            return String(item.action || "").trim().toLowerCase()
        } catch (error) {
            return ""
        }
    }

    function launchSelectedHiddenDockApp() {
        var item = selectedHiddenDockItem()

        if (!item)
            return

        handleHiddenDockItem(item)
    }

    function handleHiddenDockItem(itemData) {
        if (!itemData)
            return

        if (itemData.__kind === "app" &&
                itemData.appData) {
            closeOpenModal()
            prepareHiddenDockItemActivation(itemData)
            consoleRoot.appLaunchRequested(
                itemData.appData
            )
            return
        }

        if (itemData.appData &&
                !itemData.__kind) {
            closeOpenModal()
            prepareHiddenDockItemActivation(itemData)
            consoleRoot.appLaunchRequested(
                itemData.appData
            )
            return
        }

        var action = ""

        try {
            action = String(
                itemData.action || ""
            )
        } catch (e) {
            action = ""
        }

        handleHiddenDockAction(
            action,
            itemData
        )
    }

    function handleHiddenDockAction(
        action,
        itemData
    ) {
        var a =
            String(action || "")
            .trim()
            .toLowerCase()

        if (a.indexOf("app:") === 0 &&
                itemData &&
                itemData.appData) {
            closeOpenModal()
            disarmAll()

            consoleRoot.appLaunchRequested(
                itemData.appData
            )
            return
        }

        if (a === "performance_mode") {
            disarmAll()

            if (!developerModeIsEnabled()) {
                if (hiddenDock && typeof hiddenDock.showStatusMessage === "function")
                    hiddenDock.showStatusMessage("Enable Developer Mode first to use Performance profiles.", true)
                return
            }

            if (!hiddenDock || typeof hiddenDock.openPerformanceProfiles !== "function") {
                if (hiddenDock && typeof hiddenDock.showStatusMessage === "function")
                    hiddenDock.showStatusMessage("Performance profile selector is unavailable.", true)
                return
            }

            hiddenDock.openPerformanceProfiles()
            return
        }

        if (a === "system_overview") {
            closeOpenModal()
            disarmAll()

            selectedSection = 0
            selectedSystemCard = 0
            systemOverview.selectedSystem = 0

            focusCurrentSection()
            return
        }

        if (a === "controller_status") {
            closeOpenModal()
            disarmAll()

            selectedSection = 0
            selectedSystemCard = 8
            systemOverview.selectedSystem = 8

            openSystemDetailModal(
                "user",
                {
                    "user": activeUser,
                    "displayName":
                        activeUserDisplayName()
                }
            )
            return
        }

        if (a === "logs") {
            closeOpenModal()
            prepareHiddenDockItemActivation(itemData)

            consoleRoot.appLaunchRequested({
                "id": "logs",
                "name": "Logs",
                "type": "qml",
                "entry": "apps/logs/Main.qml",
                "qmlSource": "apps/logs/Main.qml"
            })
            return
        }

        if (a === "settings") {
            closeOpenModal()
            prepareHiddenDockItemActivation(itemData)

            consoleRoot.appLaunchRequested({
                "id": "settings",
                "name": "Settings",
                "type": "qml",
                "entry": "apps/settings/Main.qml",
                "qmlSource": "apps/settings/Main.qml"
            })
            return
        }

        if (a === "restart_shell") {
            closeOpenModal()
            disarmAll()

            if (quickBackend &&
                    typeof quickBackend.executeAction === "function") {
                quickBackend.executeAction({
                    "id": "restart_shell",
                    "name": "Restart Shell",
                    "danger": true
                })
                return
            }

            consoleRoot.log(
                "Restart Shell requested, but no quick action backend execute function is available yet"
            )
            return
        }

        if (a === "power_options") {
            closeOpenModal()
            disarmAll()
            consoleRoot.sessionMenuRequested()
            return
        }

        consoleRoot.log(
            "Hidden dock action not handled:",
            a
        )
    }

    /*
        ============================================================
                        QUICK / SERVICE ACTIONS
        ============================================================
    */

    function openHelpCenter() {
        closeOpenModal()
        disarmAll()
        selectedSection = 2
        helpModal.open()
    }

    function executeQuickAction(actionData) {
        closeOpenModal()
        disarmAll()

        if (!actionData) {
            consoleRoot.log(
                "Quick action blocked: missing actionData"
            )
            return
        }

        consoleRoot.log(
            "Confirmed quick action:",
            actionData.name ||
            actionData.id ||
            "Unknown"
        )

        if (String(actionData.id || actionData.backendAction || "").toLowerCase() === "help") {
            openHelpCenter()
            return
        }

        if (quickBackend &&
                typeof quickBackend.executeAction === "function") {
            quickBackend.executeAction(actionData)
            return
        }

        if (quickBackend &&
                typeof quickBackend.runAction === "function") {
            quickBackend.runAction(actionData)
            return
        }

        if (quickBackend &&
                typeof quickBackend.triggerAction === "function") {
            quickBackend.triggerAction(actionData)
            return
        }

        if (actionData.type === "qml" ||
                actionData.type === "web" ||
                actionData.type === "command" ||
                actionData.type === "service-web" ||
                actionData.type === "external") {
            consoleRoot.appLaunchRequested(actionData)
            return
        }

        consoleRoot.log(
            "No quick action backend execute function available yet"
        )
    }

    function executeAppServiceAction(
        appData,
        actionName
    ) {
        if (!appData) {
            consoleRoot.log(
                "Service action blocked:",
                actionName,
                "missing appData"
            )
            return
        }

        consoleRoot.log(
            "Requested app service action:",
            actionName,
            appData.name ||
            appData.id ||
            "Unknown"
        )

        if (appBackend &&
                typeof appBackend.executeAppAction === "function") {
            appBackend.executeAppAction(
                appData,
                actionName
            )
            return
        }

        if (appBackend &&
                typeof appBackend.runAppAction === "function") {
            appBackend.runAppAction(
                appData,
                actionName
            )
            return
        }

        if (appBackend &&
                typeof appBackend.serviceAction === "function") {
            appBackend.serviceAction(
                appData,
                actionName
            )
            return
        }

        consoleRoot.log(
            "No app backend service action available yet"
        )
    }

    /*
        ============================================================
                        ACTIVATE SELECTED
        ============================================================
    */

    function activateSelected() {
        if (selectedSection === 0) {
            systemOverview.selectedSystem =
                safeSelectedSystem()

            selectedSystemCard =
                systemOverview.selectedSystem

            systemOverview.activateSelected()
            return
        }

        if (selectedSection === 1) {
            launchSelectedApp()
            return
        }

        if (selectedSection === 2 &&
                actionCount() > 0) {
            selectedAction = safeSelectedAction()
            quickActions.selectedAction = selectedAction
            quickActions.activateSelected()
            return
        }

        if (selectedSection === 3) {
            if (!consoleRoot.hiddenDockVisible ||
                    !consoleRoot.dockUnlocked()) {
                return
            }

            /*
                Performance Mode is a reversible mode toggle, not a
                destructive action. One X press either toggles it or shows
                the Developer Mode requirement message.
            */
            if (selectedHiddenActionName() === "performance_mode") {
                launchSelectedHiddenDockApp()
                return
            }

            if (hiddenDock.armedDock === selectedDock) {
                launchSelectedHiddenDockApp()
                return
            }

            disarmAll()
            hiddenDock.armedDock = selectedDock
        }
    }

    function handleCancel() {
        if (modalOpen) {
            closeOpenModal()
            disarmAll()
            return
        }

        if (selectedSection === 0 &&
                systemOverview &&
                typeof systemOverview.disarmSelected === "function" &&
                systemOverview.disarmSelected()) {
            return
        }

        if (anyArmed()) {
            disarmAll()
            return
        }

        /*
            O is reserved for back/cancel. With nothing armed and no modal
            open, it intentionally performs no action.
        */
        return
    }

    function openSelectedContext() {
        if (selectedSection === 0) {
            openSelectedSystemModal()
            return
        }

        if (selectedSection === 1) {
            openHiddenDockOrSecurity()
            return
        }

        if (selectedSection === 2) {
            quickActions.selectedAction = safeSelectedAction()
            quickActions.openCustomization()
            return
        }

        if (selectedSection === 3) {
            if (!consoleRoot.hiddenDockVisible ||
                    !consoleRoot.dockUnlocked()) {
                return
            }

            hiddenDock.armedDock =
                selectedDock
        }
    }

    function restoreConsoleFromHiddenDock() {
        consoleRoot.hiddenDockVisible = false

        if (dockSecurity && typeof dockSecurity.lock === "function")
            dockSecurity.lock()

        var targetSection = consoleRoot.hiddenDockReturnSection
        if (targetSection === 3 || targetSection < 0 || targetSection > 2)
            targetSection = 2

        consoleRoot.selectedSection = targetSection
        consoleRoot.disarmAll()

        Qt.callLater(function() {
            if (consoleRoot.shellActive) {
                consoleRoot.forceActiveFocus()
                consoleRoot.focusCurrentSection()
            }
        })
    }

    function prepareHiddenDockItemActivation(itemData) {
        /*
            Close the dock before an app or full-screen action is launched.
            This prevents stale section-3 state from surviving the app return.
        */
        consoleRoot.hiddenDockVisible = false

        if (dockSecurity && typeof dockSecurity.lock === "function")
            dockSecurity.lock()

        consoleRoot.selectedSection = 1
        consoleRoot.disarmAll()
    }

    function openHiddenDockOrSecurity() {
        consoleRoot.settingsTapCount++
        settingsTapResetTimer.restart()

        if (!consoleRoot.hiddenDockVisible && selectedSection !== 3)
            consoleRoot.hiddenDockReturnSection = Math.max(0, Math.min(2, selectedSection))

        if (consoleRoot.dockUnlocked()) {
            consoleRoot.hiddenDockVisible =
                !consoleRoot.hiddenDockVisible

            if (consoleRoot.hiddenDockVisible) {
                selectedSection = 3
            } else {
                restoreConsoleFromHiddenDock()
                return
            }

            disarmAll()
            focusCurrentSection()
            return
        }

        hiddenDockSecurityModal.open()
    }

    /*
        ============================================================
                            MOVEMENT
        ============================================================
    */

    function requestCarouselMove(direction) {
        if (favoriteAppCount() <= 0)
            return

        if (carouselMoveLocked) {
            queuedCarouselMove = direction
            return
        }

        carouselMoveLocked = true
        carouselMoveCooldownTimer.restart()

        moveAppStep(direction)
    }

    function moveAppStep(direction) {
        if (!apps)
            return

        if (direction < 0) {
            if (typeof apps.previousApp === "function")
                apps.previousApp()
        } else {
            if (typeof apps.nextApp === "function")
                apps.nextApp()
        }

        syncSelectedAppFromCarousel()
    }

    function moveLeft() {
        if (selectedSection === 0) {
            systemOverview.moveSelection(-1)

            selectedSystemCard =
                systemOverview.selectedSystem

            return
        }

        if (selectedSection === 1) {
            requestCarouselMove(-1)
            return
        }

        if (selectedSection === 2) {
            if (quickActions.moveSelection(-1))
                selectedAction = quickActions.selectedAction
            playQuickDockMotion()
            return
        }

        if (selectedSection === 3) {
            selectedDock =
                Math.max(
                    0,
                    selectedDock - 1
                )
        }
    }

    function moveRight() {
        if (selectedSection === 0) {
            systemOverview.moveSelection(1)

            selectedSystemCard =
                systemOverview.selectedSystem

            return
        }

        if (selectedSection === 1) {
            requestCarouselMove(1)
            return
        }

        if (selectedSection === 2) {
            if (quickActions.moveSelection(1))
                selectedAction = quickActions.selectedAction
            playQuickDockMotion()
            return
        }

        if (selectedSection === 3) {
            selectedDock =
                Math.min(
                    Math.max(
                        0,
                        hiddenDockCount() - 1
                    ),
                    selectedDock + 1
                )
        }
    }

    function pageLeft() {
        if (selectedSection === 1) {
            for (var i = 0; i < 3; i++)
                moveAppStep(-1)

            syncSelectedAppFromCarousel()
            return
        }

        moveLeft()
    }

    function pageRight() {
        if (selectedSection === 1) {
            for (var i = 0; i < 3; i++)
                moveAppStep(1)

            syncSelectedAppFromCarousel()
            return
        }

        moveRight()
    }

    /*
        ============================================================
                        MODAL / ARMING
        ============================================================
    */

    function prepareForScreensaver() {
        /*
            Pause the Console without resetting its selection, hidden-dock
            state, or active user. The wake input returns to this exact view.
        */
        shellActive = false
        closeOpenModal()
        queuedCarouselMove = 0
        sectionMoveLocked = false
        carouselMoveLocked = false
        launchLocked = false
        disarmAll()
    }

    function prepareForLock() {
        /*
            Main.qml retains Console across Logout/Sleep. Stop every interactive
            surface before the lock transition instead of destroying the full
            Console tree on the same frame.
        */
        shellActive = false
        closeOpenModal()
        hiddenDockVisible = false
        queuedCarouselMove = 0
        sectionMoveLocked = false
        carouselMoveLocked = false
        launchLocked = false

        if (dockSecurity && typeof dockSecurity.lock === "function")
            dockSecurity.lock()

        disarmAll()
    }

    function closeOpenModal() {
        if (criticalWarningModal.visible)
            criticalWarningModal.close()

        if (systemDetailLoadError.length > 0) {
            systemDetailLoadError = ""
            systemDetailLoadSource = ""
        }

        if (systemDetailModalOpen)
            closeSystemDetailModal()

        if (appModal.visible)
            appModal.close()

        if (quickActionModal.visible)
            quickActionModal.close()

        if (quickActionCustomizeModal.visible)
            quickActionCustomizeModal.close()

        if (helpModal.visible)
            helpModal.close()

        if (loginInstructionsModal.visible)
            loginInstructionsModal.close()

        if (hiddenDockSecurityModal.visible)
            hiddenDockSecurityModal.close()
    }

    function disarmAll() {
        systemOverview.armedIndex = -1
        apps.armedApp = -1
        quickActions.armedAction = -1
        if (!quickActionCustomizeModal.visible)
            quickActions.customizationArmed = false
        hiddenDock.armedDock = -1
    }

    /*
        ============================================================
                            ANIMATION
        ============================================================
    */

    Behavior on cameraZoom {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    onSelectedSectionChanged: {
        if (selectedSection === 1)
            cameraZoom = 1.018
        else
            cameraZoom = 1.0

        if (selectedSection !== 0)
            systemOverview.activeAppSelectionMode = false

        if (selectedSection === 2)
            playQuickDockMotion()

        focusCurrentSection()
    }

    onSelectedActionChanged: {
        if (selectedSection === 2)
            playQuickDockMotion()
    }

    onActiveUserChanged: {
        if (systemOverview &&
                "activeUser" in systemOverview) {
            systemOverview.activeUser =
                consoleRoot.activeUser
        }
        Qt.callLater(function() {
            if (!consoleRoot.dashboardLayoutBackend)
                return
            consoleRoot.legacyDashboardActive =
                consoleRoot.dashboardLayoutBackend.legacyAvailable &&
                String(consoleRoot.dashboardLayoutBackend.defaultTab || "system") === "legacy"
        })
    }

    onShellActiveChanged: {
        if (monitorBackend && typeof monitorBackend.setDashboardActive === "function")
            monitorBackend.setDashboardActive(shellActive && modernDashboard)
        if (shellActive) {
            refreshClockPresentation()
            forceActiveFocus()
            focusCurrentSection()

            if (typeof systemMonitor !== "undefined" &&
                    systemMonitor &&
                    typeof systemMonitor.refresh === "function") {
                systemMonitor.refresh()
            }
        } else {
            closeOpenModal()

            quickDockGlowAnimation.stop()
            quickDockSweepAnimation.stop()

            dockGlowPulse = 0.30
            dockSweep = -1.0
        }
    }

    onModernDashboardChanged: {
        if (monitorBackend && typeof monitorBackend.setDashboardActive === "function")
            monitorBackend.setDashboardActive(shellActive && modernDashboard)
    }

    /*
        ============================================================
                    KEYBOARD FALLBACK FOR CONSOLE
        ============================================================
    */

    ModernDashboard {
        id: modernDashboardView
        anchors.fill: parent
        visible: consoleRoot.modernDashboard || selectorOpen
        enabled: visible && consoleRoot.shellActive
        z: 80
        shellActive: consoleRoot.shellActive
        activeUser: consoleRoot.activeUser
        appsBackend: consoleRoot.appBackend
        monitorBackend: consoleRoot.monitorBackend
        storageBackend: (typeof storageManager !== "undefined") ? storageManager : null
        networkBackend: consoleRoot.networkBackend
        securityBackend: consoleRoot.securityBackend
        controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
        notificationBackend: (typeof notificationManager !== "undefined") ? notificationManager : null
        settingsBackend: consoleRoot.settingsBackend
        clockBackend: consoleRoot.clockExperienceBackend

        onDashboardModeRequested: function(mode) {
            consoleRoot.legacyDashboardActive = (mode === "legacy")
            selectorOnly = false
            if (mode !== "legacy")
                activeMode = mode
            consoleRoot.focusCurrentSection()
        }

        onAppLaunchRequested: function(appData) {
            if (appData)
                consoleRoot.appLaunchRequested(appData)
        }
        onNotificationCenterRequested: consoleRoot.notificationCenterRequested()
        onSearchRequested: consoleRoot.globalSearchRequested()
        onSystemDetailRequested: function(modalId, context) {
            if (modalId === "uptime")
                return
            consoleRoot.openSystemDetailModal(modalId, context || {})
        }
        onQuickActionRequested: function(action) {
            if (action === "notifications") {
                consoleRoot.notificationCenterRequested()
            } else if (action === "power") {
                consoleRoot.sessionMenuRequested()
            } else if (action === "help") {
                helpModal.open()
            } else if (action === "lock") {
                consoleRoot.logoutRequested()
            } else if (action === "network") {
                consoleRoot.openSystemDetailModal("network", {})
            } else if (action === "bluetooth") {
                var list = consoleRoot.appList()
                for (var index = 0; index < list.length; ++index) {
                    if (String(list[index].id || "").toLowerCase() === "settings") {
                        consoleRoot.appLaunchRequested(list[index])
                        break
                    }
                }
            } else if (action === "running-apps") {
                consoleRoot.log("Running Apps integration point selected; Patch 82 owns the modal.")
            }
        }
    }

    Connections {
        target: consoleRoot.dashboardLayoutBackend
        function onLayoutChanged() {
            if (!consoleRoot.dashboardLayoutBackend)
                return
            if (!consoleRoot.dashboardLayoutBackend.legacyAvailable &&
                    consoleRoot.legacyDashboardActive) {
                consoleRoot.legacyDashboardActive = false
                modernDashboardView.selectorOnly = false
                modernDashboardView.activeMode = "system"
            }
        }
    }

    Keys.onPressed: function(event) {
        if (event.isAutoRepeat)
            return

        if (consoleRoot.globalSearchActive) {
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Up ||
                event.key === Qt.Key_W) {
            handleControllerPressed("up")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Down ||
                event.key === Qt.Key_S) {
            handleControllerPressed("down")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Left ||
                event.key === Qt.Key_A) {
            handleControllerPressed("left")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Right ||
                event.key === Qt.Key_D) {
            handleControllerPressed("right")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Return ||
                event.key === Qt.Key_Enter ||
                event.key === Qt.Key_Space) {
            handleControllerPressed("primary")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Escape ||
                event.key === Qt.Key_Backspace) {
            handleControllerPressed("cancel")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Tab ||
                event.key === Qt.Key_Menu) {
            handleControllerPressed("system")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_F1) {
            handleControllerPressed("context")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_F2) {
            handleControllerPressed("secondary")
            event.accepted = true
            return
        }

        /*
            F3 and Home are owned globally by Main.qml:
                F3  -> Developer Mode
                Home -> Logout / Sleep session menu

            Console must not consume either key locally.
        */
    }

    /*
        ============================================================
                                INIT
        ============================================================
    */

    Component.onDestruction: consoleRoot.prepareForLogout()

    Component.onCompleted: {
        if (monitorBackend && typeof monitorBackend.setDashboardActive === "function")
            monitorBackend.setDashboardActive(shellActive && modernDashboard)
        if (monitorBackend)
            lastObservedThrottleEvents = Number(monitorBackend.throttlingEvents || 0)
        if (appBackend &&
                typeof appBackend.reloadApps === "function") {
            appBackend.reloadApps()
        }

        if (quickBackend &&
                typeof quickBackend.reloadActions === "function") {
            quickBackend.reloadActions()
        }

        /*
            App/action models are intentionally warmed during preload. System
            telemetry and focus work wait until shellActive becomes true.
        */
        if (shellActive &&
                typeof systemMonitor !== "undefined" &&
                systemMonitor &&
                typeof systemMonitor.refresh === "function") {
            systemMonitor.refresh()
        }

        selectedSection = 1
        selectedSystemCard = 0
        systemOverview.selectedSystem = 0

        disarmAll()
        cameraZoom = 1.018

        if (shellActive) {
            forceActiveFocus()
            focusCurrentSection()
        }

        consoleRoot.log(
            shellActive
            ? "Console completed"
            : "Console preloaded"
        )
    }
}
