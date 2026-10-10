import QtQuick
import QtQuick.Controls
import QtQuick.Window
import NeutronOS.Managers 1.0
import "modals"
import "gemini"

Item {
    id: root
    objectName: "GeminiMainRoot"

    // Optional package session: application-native modules are installed by NAPP.
    property var packageSession: null
    property string packageSessionAppId: ""
    // Package session API v1: app identity and controller permission come from
    // the installed application framework, never the backend's claimed ID.
    function registerPackageSession(backend) {
        if (!root.authenticated || !appHostLoader.item || !backend || typeof appManager === "undefined") return false
        var id=appHostLoader.item.activeAppId
        var app=appManager.appById(id)
        if (!id || typeof appStoreManager === "undefined" || !appStoreManager.isInstalled(id) ||
                !app.permissions || app.permissions.indexOf("controller")<0) return false
        if(root.packageSession && root.packageSession !== backend && root.packageSession.gameActive) return false
        root.packageSessionAppId=id
        root.packageSession=backend
        backend.setSessionIntegrationAvailable(true)
        backend.setSystemAccess(root.packageSessionAllowed)
        return true
    }
    property var pendingPackageSwitch: null
    property string packageInputOwner: "idle"
    readonly property bool packageSessionAllowed: root.authenticated && !root.inputLocked && (root.inAppMode || root.inConsoleMode) && !RemoteKeyboardManager.keyboardActive && !globalSearchCenter.visible && !(root.notificationCenterVisible() && notificationCenterOverlay.securityComboOpen)
    onPackageSessionAllowedChanged: if (packageSession) packageSession.setSystemAccess(packageSessionAllowed)
    onPackageSessionChanged: if (packageSession) packageSession.setSystemAccess(packageSessionAllowed)
    function switchFromPackageSession(appData) {
        if (!appData || !appHostLoader.item || appHostLoader.item.activeAppId !== root.packageSessionAppId)
            return
        if (packageSession && !packageSession.prepareSwitch())
            return
        pendingPackageSwitch = appData
        appHostLoader.item.backgroundApp()
        packageSwitchTimer.restart()
    }
    Timer {
        id: packageSwitchTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (!root.pendingPackageSwitch) { stop(); return }
            if (root.shellMode === "console") {
                var targetApp = root.pendingPackageSwitch
                root.pendingPackageSwitch = null
                stop()
                root.beginLaunchApp(targetApp)
            }
        }
    }
    Loader {
        id: packageMenuLoader
        anchors.fill: parent
        z: 10000
        visible: root.packageSessionAllowed
        source: root.packageSession ? root.packageSession.menuSource : ""
        onLoaded: item.session = root.packageSession
    }
    Connections {
        target: root.packageSession
        function onSessionChanged() {
            var session = root.packageSession
            if(typeof appStoreManager!=="undefined")appStoreManager.setApplicationSessionState(root.packageSessionAppId,session.gameActive)
            var owner = !session.gameActive ? "idle" : session.menuOpen ? "menu" : session.backgrounded ? "background" : "game"
            if (owner !== root.packageInputOwner) {
                root.packageInputOwner = owner
                root.clearStickNavigation()
                if (root.inputController) root.inputController.releaseAllInputs()
                root.pressedActionEdges = ({})
            }
        }
        function onInputReset() {
            root.clearStickNavigation()
            if (root.inputController) root.inputController.releaseAllInputs()
            root.pressedActionEdges = ({})
        }
        function onBackgroundAction(action, pressed) {
            if (pressed) root.routeControllerPressed(action)
            else root.routeControllerReleased(action)
        }
        function onRestoreRequested() {
            if (root.shellMode === "console" && typeof appManager !== "undefined")
                root.beginLaunchApp(appManager.appById(root.packageSessionAppId))
        }
    }



    /* NEUTRONOS_REMOTE_UI_BRIDGE_V2
       Runtime-only bridge for authenticated web-controller app launching and
       native phone-keyboard focus detection. The HTTP listener is loopback-only. */
    property string remoteUiBridgeBase: "http://127.0.0.1:8094"
    property string remoteUiPendingAppId: ""

    // Lifecycle transition cover. This is intentionally independent of the
    // cold-boot progress state: shell restart must never replay 60 -> 100.
    property bool powerTransitionVisible: false
    property string powerTransitionKind: ""
    property string powerTransitionPendingAction: ""

    function remoteUiRequest(method, path, payload, callback) {
        try {
            var xhr = new XMLHttpRequest()
            xhr.open(method, remoteUiBridgeBase + path, true)
            xhr.setRequestHeader("Accept", "application/json")
            if (payload !== null && payload !== undefined)
                xhr.setRequestHeader("Content-Type", "application/json")
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return
                var value = null
                try { value = JSON.parse(xhr.responseText || "{}") } catch (error) { value = null }
                if (callback)
                    callback(xhr.status, value)
            }
            xhr.send(payload !== null && payload !== undefined ? JSON.stringify(payload) : null)
        } catch (error) {
            if (callback)
                callback(0, null)
        }
    }

    function remoteUiTextInputFocused() {
        try {
            var shellWindow = root.Window.window
            var item = shellWindow ? shellWindow.activeFocusItem : null
            if (!item || item.visible === false || item.enabled === false)
                return false
            var hasText = typeof item.text !== "undefined"
            var hasCursor = typeof item.cursorPosition !== "undefined"
            var hasHints = typeof item.inputMethodHints !== "undefined"
            var editable = typeof item.readOnly === "undefined" || item.readOnly !== true
            return hasText && editable && (hasCursor || hasHints)
        } catch (error) {
            return false
        }
    }

    function remoteUiLaunchRequested(appId) {
        appId = String(appId || "").trim()
        if (appId.length === 0)
            return
        if (root.shellMode === "console") {
            try {
                if (typeof appManager !== "undefined" && appManager && typeof appManager.appById === "function") {
                    var appData = appManager.appById(appId)
                    if (appData && String(appData.id || "").length > 0) {
                        root.remoteUiPendingAppId = ""
                        root.beginLaunchApp(appData)
                        return
                    }
                }
            } catch (error) {
                console.warn("Remote controller app launch failed:", appId, error)
            }
            return
        }
        root.remoteUiPendingAppId = appId
        if (root.shellMode === "app")
            root.beginReturnToConsole()
    }

    Timer {
        id: remoteUiBridgeTimer
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            root.remoteUiRequest("GET", "/command/next", null, function(status, value) {
                if (status === 200 && value && value.command && value.command.op === "launchApp")
                    root.remoteUiLaunchRequested(value.command.appId)
            })

            root.remoteUiRequest("POST", "/focus",
                                 ({"textInputActive": root.remoteUiTextInputFocused()}), null)

            if (root.remoteUiPendingAppId.length > 0 && root.shellMode === "console")
                root.remoteUiLaunchRequested(root.remoteUiPendingAppId)
        }
    }
    /* END_NEUTRONOS_REMOTE_UI_BRIDGE_V2 */

    width: 1920
    height: 1080
    function itemContainsFocus(ancestor, focusedItem) {
        var current = focusedItem
        while (current) {
            if (current === ancestor)
                return true
            current = current.parent
        }
        return false
    }
    readonly property var destinationSurfaceItem:
        setupWizardLoader.active ? setupWizardLoader.item : lockLoader.item
    readonly property bool destinationSurfaceReady:
        destinationSurfaceItem !== null &&
        (setupWizardLoader.active
         ? setupWizardLoader.status === Loader.Ready
         : lockLoader.status === Loader.Ready)
    readonly property bool destinationFocusReady: {
        var shellWindow = root.Window.window
        return destinationSurfaceReady && shellWindow &&
               itemContainsFocus(destinationSurfaceItem,
                                 shellWindow.activeFocusItem)
    }
    readonly property bool destinationInputReady:
        destinationSurfaceReady && destinationFocusReady && !root.inputLocked &&
        (setupWizardLoader.active
         ? setupWizardLoader.visible && setupWizardLoader.item !== null
         : root.shellMode === "lock" && lockLoader.enabled &&
           lockLoader.visible && lockLoader.item !== null)

    Rectangle { anchors.fill: parent; color: "#050814"; z: -100000 }

    /* Backend-ready session hooks. */
    signal screensaverRequested()
    signal sessionLogoutRequested()

    property bool setupFractureRetained: false
    property bool screensaverPending: false
    property bool logoutModalRetained: false
    property bool developerModalRequested: false

    readonly property bool firstBootSetupVisible:
        setupWizardLoader.item && setupWizardLoader.item.visible === true

    readonly property var screensaverBackend:
        (typeof screensaverManager !== "undefined" && screensaverManager)
        ? screensaverManager
        : null

    property real screensaverOpacity: 0.0
    property double lastActivityAt: Date.now()
    property bool screensaverWakePending: false
    property string screensaverReturnMode: "lock"
    property double screensaverWakeConsumeUntil: 0
    property bool screensaverStickNeedsNeutral: false

    property bool l1Down: false
    property bool r1Down: false
    property bool l1Forwarded: false
    property bool r1Forwarded: false
    property bool shoulderChordTriggered: false
    property int shoulderChordWindowMs: 120

    /* Logged-in emergency controller escape: PS/Home + L1 + R1 for 4 seconds. */
    property bool emergencyHomeDown: false
    property bool emergencyChordActive: false
    property bool emergencyChordConsumed: false
    property bool emergencyChordTriggered: false
    property int emergencyChordHoldMs: 4000
    property bool homePowerHoldTriggered: false
    property int homePowerHoldMs: 1050

    /* Patch 68J4B: live Main.qml terminal handoff repair. */
    property bool systemTerminalHandoffPending: false

    /* Patch 60G global capture chord state. */
    property bool captureL3Down: false
    property bool captureR3Down: false
    property bool captureL3Forwarded: false
    property bool captureR3Forwarded: false
    property bool captureStickChordTriggered: false
    property bool captureDecisionPending: false
    property bool captureRecordingChordTriggered: false
    property bool captureR1Consumed: false
    property int captureChordWindowMs: 180
    property string captureToastText: ""
    property bool captureToastError: false

    /*
        ============================================================
                    NEUTRONOS ROOT STATE
        ============================================================

        Runtime order:
            1. lock
               - LoginScreen.qml is loaded and owns input.
               - Console.qml may be preloaded only while input capture is idle.
               - AppHost.qml is not active.

            2. console
               - Console.qml is loaded.
               - LoginScreen.qml is unloaded.
               - AppHost.qml is unloaded.

            3. app
               - AppHost.qml is loaded.
               - Console.qml is unloaded.
               - LoginScreen.qml is unloaded.

        Global session behavior:
            - One PS/Home press opens LogoutModal.qml from Console or an app.
            - L1 + R1 opens Developer Mode; F3 is the keyboard fallback.
            - Screensaver mode unloads the Login, Console, and AppHost trees.
    */

    property string shellMode: "lock"

    readonly property bool inLockMode: shellMode === "lock"
    readonly property bool inUnlockTransition: shellMode === "unlocking"
    readonly property bool inConsoleMode: shellMode === "console"
    readonly property bool inAppLaunchTransition: shellMode === "launchingApp"
    readonly property bool inAppMode: shellMode === "app"
    readonly property bool inConsoleReturnTransition: shellMode === "returningConsole"
    readonly property bool inLockReturnTransition: shellMode === "locking"
    readonly property bool inScreensaverMode: shellMode === "screensaver"
    readonly property bool inScreensaverWakeTransition: shellMode === "waking"

    readonly property bool transitioning: inUnlockTransition ||
                                          inAppLaunchTransition ||
                                          inConsoleReturnTransition ||
                                          inLockReturnTransition ||
                                          inScreensaverWakeTransition

    property bool inputLocked: false
    property bool authenticated: false

    property var activeUser: null
    property var pendingSecurityIncident: null
    property bool pendingSecurityAppLaunch: false
    property bool automaticLoginAttempted: false
    property bool gameSessionReturnPending: false
    property var gameSessionReturnData: ({})
    property bool appHostSessionReturnPending: false
    property var appHostSessionReturnData: ({})
    property var startupAppHostReturnSession:
        (typeof appHostStartupReturnSession !== "undefined" && appHostStartupReturnSession)
        ? appHostStartupReturnSession
        : ({})
    property int appHostReturnResolveAttempts: 0
    property bool browserReturnModalVisible: false
    property bool appHostReturnCoverVisible:
        startupAppHostReturnSession && startupAppHostReturnSession.pending === true
    /*
        Patch 17-18 deterministic session residency.
        Exactly one primary surface remains resident after each transition.
    */
    property int lifecycleGeneration: 0
    property bool lockResident: true
    property bool consoleResident: false
    property bool appHostResident: false
    property bool lifecycleCleanupActive: false
    property var pendingAppData: null
    property bool appLaunchSubmitted: false
    property bool appLaunchReady: false
    property bool appLaunchFractureStarted: false
    property bool appLaunchFractureRelease: false
    property bool appLaunchSlowNotice: false
    property int returnConsoleWaitAttempts: 0

    /*
        Console readiness is part of the root state machine.

        Main.qml must never complete lock -> console transition until
        Console.qml is loaded successfully. This prevents the blank/blue
        screen after successful login.
    */
    property bool consoleReady: false
    property bool unlockRevealPending: false
    property string unlockState: "LOCKED"
    property bool unlockPulseComplete: false
    property bool fractureSequenceStarted: false
    property string unlockFailureReason: ""
    property int unlockGeneration: 0
    property double unlockStartedAtMs: 0
    property string consoleLoadError: ""

    /*
        Console preload is deliberately separate from authentication.

        The Console object tree may be created while the lock screen is
        visible, but it remains invisible, disabled, shell-inactive, and
        excluded from the controller router until shellMode becomes
        "console". This warms QML, models, and image requests without
        changing the proven lock-screen input path.
    */
    property bool consolePreloadRequested: false

    property real lockOpacity: 1.0
    property real consoleOpacity: 0.0
    property real appOpacity: 0.0

    /*
        Release memory after a screen Loader has been deactivated and its
        transition has completed. This does not stop or simplify any visual
        animation; it only asks the QML engine to collect objects that are no
        longer reachable after lock/console/app screen swaps.
    */
    Timer {
        id: idleResourceReleaseTimer
        interval: 1500
        repeat: false

        onTriggered: {
            gc()
        }
    }

    onShellModeChanged: {
        if (root.shellMode !== "console") {
            root.clearStickNavigation()
            if (notificationCenterOverlay.opened)
                notificationCenterOverlay.closeCenter()
        }

        /*
            LoginScreen and Console are deliberately retained. Running a full
            QML garbage collection when entering Console or returning to Lock
            stalls the first interactive frames even though neither retained
            tree is collectible. App teardown schedules collection explicitly.
        */
        if (root.shellMode !== "returningConsole")
            idleResourceReleaseTimer.stop()

        Qt.callLater(root.scheduleAutomaticScreensaver)
    }

    /*
        C++ managers.

        Expected context properties:
            controllerManager
            webControllerManager or webController
            userManager
            securityManager
            appLauncher / appManager
            developerModeManager
    */

    property var inputController: (typeof controllerManager !== "undefined") ? controllerManager : null

    property var inputWebController: (typeof webControllerManager !== "undefined")
                                     ? webControllerManager
                                     : ((typeof webController !== "undefined") ? webController : null)

    /* Source-independent edge state. A button is dispatched once on its
       up-to-down edge and cannot fire again until its matching release. */
    property var pressedActionEdges: ({})
    property string heldDirectionAction: ""
    property bool directionalRepeatTick: false
    // Footer's discrete navigation bypasses costly per-press timer and settings
    // refresh. Keep the actual activity timestamp current on every press.
    property double lastFooterTimerMaintenanceAt: 0

    Timer {
        id: directionRepeatDelay
        interval: 360
        repeat: false
        onTriggered: if (root.heldDirectionAction.length > 0) {
            root.fireDirectionalRepeat()
            directionRepeatTimer.start()
        }
    }
    Timer {
        id: directionRepeatTimer
        interval: 165
        repeat: true
        onTriggered: root.fireDirectionalRepeat()
    }

    Timer {
        id: controllerBluetoothIdleTimer
        interval: 15 * 60 * 1000
        repeat: false
        onTriggered: {
            if (!root.controllerBluetoothConnectedNow())
                return
            try {
                if (root.inputController && typeof root.inputController.powerOffController === "function")
                    root.inputController.powerOffController()
            } catch (error) {}
        }
    }

    /*
        Stick backup throttle.
    */

    property int lastStickActionMs: 0
    property int stickRepeatMs: 165
    property string heldStickAction: ""

    // A reactive gate, not a one-time check in the repeat callback: cancel
    // pending D-pad AND analog repeat at the instant focus enters the footer
    // carousel. Crucially, retain the physical stick latch until neutral.
    readonly property bool consoleOneShotNavigation:
        root.shellMode === "console" && consoleLoader.item &&
        consoleLoader.item.suppressDirectionalRepeat === true
    onConsoleOneShotNavigationChanged: {
        if (consoleOneShotNavigation) {
            root.stopDirectionalRepeatTimers()
            stickNavigationRepeat.stop()
        }
    }

    /* Global session overlays. */

    property bool logoutModalOpen: false
    property bool logoutModalRequested: false
    property bool diagnosticsCenterOpen: false
    property bool searchL2Down: false
    property bool searchR2Down: false
    property var globalSearchConsumedActions: ({})
    property int bluetoothControllerIdleMinutes: 15

    onAuthenticatedChanged: Qt.callLater(root.refreshBluetoothControllerIdleTimer)

    /*
        ============================================================
                            ACTION NORMALIZATION
        ============================================================
    */

    function handleFirstBootSetupCompleted() {
        root.inputLocked = false
        root.authenticated = false
        root.shellMode = "lock"
        root.lockOpacity = 1.0
        root.consoleOpacity = 0.0
        root.appOpacity = 0.0
        if (lockLoader.item) {
            if ("active" in lockLoader.item)
                lockLoader.item.active = true
            // Unloading Setup changes the enabled focus scope. Focus Login
            // after that change, without the fallback stealing it immediately.
            Qt.callLater(function(){if(lockLoader.item)lockLoader.item.forceActiveFocus()})
        } else keyboardFallback.forceActiveFocus()
        root.markUserActivity()
    }

    function normalizeAction(action) {
        var a = String(action || "").trim().toLowerCase()

        if (a === "primary" || a === "x" || a === "cross" || a === "a" || a === "ps_cross")
            return "primary"

        if (a === "cancel" || a === "o" || a === "circle" || a === "b" || a === "ps_circle")
            return "cancel"

        if (a === "context" || a === "triangle" || a === "tri" || a === "y" || a === "ps_triangle")
            return "context"

        if (a === "secondary" || a === "square" || a === "xbox_x" || a === "ps_square")
            return "secondary"

        if (a === "system" || a === "options" || a === "settings" || a === "start" || a === "menu")
            return "system"

        if (a === "quick" || a === "share" || a === "create" || a === "select")
            return "quick"

        if (a === "home" || a === "ps" || a === "playstation" || a === "guide")
            return "home"

        if (a === "up" || a === "dpad_up")
            return "up"

        if (a === "down" || a === "dpad_down")
            return "down"

        if (a === "left" || a === "dpad_left")
            return "left"

        if (a === "right" || a === "dpad_right")
            return "right"

        if (a === "l1" || a === "lb")
            return "l1"

        if (a === "r1" || a === "rb")
            return "r1"

        if (a === "l2" || a === "lt")
            return "l2"

        if (a === "r2" || a === "rt")
            return "r2"

        if (a === "l3" || a === "ls")
            return "l3"

        if (a === "r3" || a === "rs")
            return "r3"

        return a
    }

    function acceptPressEdge(clean) {
        if (pressedActionEdges[clean] === true)
            return false
        var next = Object.assign({}, pressedActionEdges)
        next[clean] = true
        pressedActionEdges = next
        return true
    }

    function releasePressEdge(clean) {
        var next = Object.assign({}, pressedActionEdges)
        delete next[clean]
        pressedActionEdges = next
    }

    function fireDirectionalRepeat() {
        if (heldDirectionAction.length === 0)
            return
        if (root.consoleSuppressDirectionalRepeat()) {
            root.heldDirectionAction = ""
            directionRepeatDelay.stop()
            directionRepeatTimer.stop()
            return
        }
        directionalRepeatTick = true
        releasePressEdge(heldDirectionAction)
        routeControllerPressed(heldDirectionAction)
        directionalRepeatTick = false
    }

    function consoleSuppressDirectionalRepeat() {
        try {
            return root.shellMode === "console" && consoleLoader.item &&
                   consoleLoader.item.suppressDirectionalRepeat === true
        } catch (error) {}
        return false
    }

    function routeControllerOneShot(action) {
        var clean = normalizeAction(action)
        routeControllerPressed(clean)
        Qt.callLater(function() { routeControllerReleased(clean) })
    }

    /*
        ============================================================
                    GLOBAL SESSION / DEVELOPER OVERLAYS
        ============================================================
    */

    function logoutModalItem() {
        return logoutModalLoader.item
    }

    function developerModalItem() {
        return developerModeModalLoader.item
    }

    function isLogoutModalVisible() {
        var item = logoutModalItem()
        return item && item.visible === true
    }

    function isDeveloperModalVisible() {
        var item = developerModalItem()
        return item && item.visible === true
    }

    function controllerBluetoothConnectedNow() {
        try {
            return root.inputController &&
                   root.inputController.controllerConnected === true &&
                   root.inputController.controllerCharging !== true &&
                   String(root.inputController.controllerAddress || "").trim().length > 0
        } catch (error) {}
        return false
    }

    function readBluetoothControllerIdleMinutes() {
        var minutes = 15
        try {
            if (typeof settingsManager !== "undefined" && settingsManager &&
                    typeof settingsManager.value === "function") {
                var value = Number(settingsManager.value("controller.bluetoothInactivityMinutes", 15))
                if (!isNaN(value))
                    minutes = Math.max(0, Math.min(240, Math.round(value)))
            }
        } catch (error) {}
        root.bluetoothControllerIdleMinutes = minutes
        return minutes
    }

    function refreshBluetoothControllerIdleTimer() {
        var minutes = root.readBluetoothControllerIdleMinutes()
        if (!root.authenticated || !root.controllerBluetoothConnectedNow() || minutes <= 0) {
            controllerBluetoothIdleTimer.stop()
            return
        }
        controllerBluetoothIdleTimer.interval = Math.max(60000, minutes * 60000)
        controllerBluetoothIdleTimer.restart()
    }

    function markUserActivity() {
        root.lastActivityAt = Date.now()
        root.scheduleAutomaticScreensaver()
        root.refreshBluetoothControllerIdleTimer()
    }

    function markDiscreteFooterActivity() {
        var now = Date.now()
        root.lastActivityAt = now
        // The screensaver deadline checks lastActivityAt when it fires, so
        // moving that deadline every key event is unnecessary. Updating it
        // at most once a second also avoids synchronous settingsManager.value
        // IPC in refreshBluetoothControllerIdleTimer on every carousel step.
        if (now - root.lastFooterTimerMaintenanceAt >= 1000) {
            root.lastFooterTimerMaintenanceAt = now
            root.scheduleAutomaticScreensaver()
            root.refreshBluetoothControllerIdleTimer()
        }
    }

    function openLogoutModal() {
        if (root.inputLocked || root.inScreensaverMode ||
                root.inScreensaverWakeTransition)
            return false

        if (root.shellMode !== "console" && root.shellMode !== "app" &&
                root.shellMode !== "launchingApp" &&
                root.shellMode !== "returningConsole") {
            return false
        }

        if (root.isDeveloperModalVisible())
            root.closeDeveloperModeModal()

        root.logoutModalOpen = true
        root.logoutModalRequested = true

        if (root.inputController &&
                typeof root.inputController.hapticWarning === "function") {
            root.inputController.hapticWarning()
        }

        if (logoutModalLoader.item)
            root.openLoadedLogoutModal()

        return true
    }

    function openLoadedLogoutModal() {
        var item = logoutModalLoader.item

        if (!root.logoutModalRequested || !item)
            return

        item.open({
            "shellMode": root.shellMode,
            "authenticated": root.authenticated,
            "activeUser": root.activeUser
        })

        item.forceActiveFocus()
    }

    function closeLogoutModal() {
        root.logoutModalRequested = false

        var item = logoutModalItem()

        if (item && item.visible) {
            item.close()
            return
        }

        root.logoutModalOpen = false
    }

    function routeLogoutModalPressed(action) {
        var item = logoutModalItem()

        if (!item || !item.visible)
            return false

        if (typeof item.handleControllerPressed === "function")
            return item.handleControllerPressed(action)

        if (typeof item.handleController === "function")
            return item.handleController(action)

        return true
    }

    function routeLogoutModalReleased(action) {
        var item = logoutModalItem()

        if (!item || !item.visible)
            return false

        if (typeof item.handleControllerReleased === "function")
            return item.handleControllerReleased(action)

        return true
    }

    function openDeveloperModeModal() {
        if (!root.authenticated || root.inputLocked ||
                root.inScreensaverMode || root.inScreensaverWakeTransition)
            return false

        if (root.isLogoutModalVisible())
            root.closeLogoutModal()

        root.developerModalRequested = true

        if (developerModeModalLoader.item)
            root.openLoadedDeveloperModeModal()

        return true
    }

    function openLoadedDeveloperModeModal() {
        var item = developerModalItem()

        if (!root.developerModalRequested || !item)
            return

        if (typeof item.openModal === "function")
            item.openModal()
        else if (typeof item.open === "function")
            item.open()
        else
            item.visible = true

        item.forceActiveFocus()
    }

    function closeDeveloperModeModal() {
        root.developerModalRequested = false

        var item = developerModalItem()

        if (!item) {
            root.restorePrimarySurfaceFocus()
            return
        }

        if (typeof item.close === "function")
            item.close()
        else {
            item.visible = false
            root.restorePrimarySurfaceFocus()
        }
    }

    function restorePrimarySurfaceFocus() {
        Qt.callLater(function() {
            if (root.shellMode === "console" && consoleLoader.item) {
                consoleLoader.item.forceActiveFocus()
                return
            }

            if ((root.shellMode === "app" ||
                    root.shellMode === "launchingApp" ||
                    root.shellMode === "returningConsole") &&
                    appHostLoader.item) {
                appHostLoader.item.forceActiveFocus()
                return
            }

            if (root.shellMode === "lock" && root.destinationSurfaceItem) {
                root.destinationSurfaceItem.forceActiveFocus()
                return
            }

            keyboardFallback.forceActiveFocus()
        })
    }

    function routeDeveloperModalPressed(action) {
        var item = developerModalItem()

        if (!item || !item.visible)
            return false

        if (typeof item.handleControllerPressed === "function")
            return item.handleControllerPressed(action)

        if (typeof item.handleController === "function")
            return item.handleController(action)

        return true
    }

    function routeDeveloperModalReleased(action) {
        var item = developerModalItem()

        if (!item || !item.visible)
            return false

        if (typeof item.handleControllerReleased === "function")
            return item.handleControllerReleased(action)

        return true
    }

    function handleLogoutModalLogout() {
        root.closeLogoutModal()

        Qt.callLater(function() {
            root.sessionLogoutRequested()
            root.beginReturnToLock(false)
        })
    }

    function handleLogoutModalLock() {
        root.closeLogoutModal()
        Qt.callLater(function() { root.beginReturnToLock(false) })
    }

    function dispatchAuthorizedPowerAction() {
        var action = String(root.powerTransitionPendingAction || "")
        if (!action.length)
            return
        root.powerTransitionPendingAction = ""

        if (typeof settingsManager === "undefined" || !settingsManager ||
                typeof settingsManager.runAction !== "function") {
            root.powerTransitionVisible = false
            root.powerTransitionKind = ""
            return
        }

        var accepted = settingsManager.runAction(action, {})
        if (!accepted) {
            root.powerTransitionVisible = false
            root.powerTransitionKind = ""
        }
    }

    function runAuthorizedPowerAction(action) {
        root.closeLogoutModal()
        var normalized = String(action || "").toLowerCase()

        if (normalized === "restart-shell" || normalized === "reboot" ||
                normalized === "shutdown") {
            root.powerTransitionPendingAction = normalized
            root.powerTransitionKind = normalized === "shutdown" ? "shutdown" : "reboot"
            root.powerTransitionVisible = true
            powerTransitionDispatchTimer.restart()
            return
        }

        Qt.callLater(function() {
            if (typeof settingsManager !== "undefined" && settingsManager &&
                    typeof settingsManager.runAction === "function")
                settingsManager.runAction(normalized, {})
        })
    }

    Timer {
        id: powerTransitionDispatchTimer
        interval: 700
        repeat: false
        onTriggered: root.dispatchAuthorizedPowerAction()
    }

    function handleLogoutModalSleep() {
        root.closeLogoutModal()

        Qt.callLater(function() {
            root.activateScreensaver("sleep")
        })
    }

    function handleLogoutModalCancel() {
        root.closeLogoutModal()
    }

    function handleLogoutModalControllerOff() {
        root.closeLogoutModal()
        Qt.callLater(root.requestControllerOff)
    }

    function screensaverTimeoutMinutes() {
        if (!root.screensaverBackend)
            return 0

        try {
            return Math.max(
                0,
                Number(root.screensaverBackend.timeoutMinutes) || 0
            )
        } catch (error) {
            return 0
        }
    }

    function automaticScreensaverEligible() {
        return root.authenticated &&
               root.shellMode === "console" &&
               !root.inputLocked &&
               !root.isLogoutModalVisible() &&
               !root.isDeveloperModalVisible() &&
               root.screensaverTimeoutMinutes() > 0
    }

    function scheduleAutomaticScreensaver() {
        inactivityDeadlineTimer.stop()

        if (!root.automaticScreensaverEligible())
            return

        var timeoutMs = root.screensaverTimeoutMinutes() * 60000
        var elapsedMs = Math.max(0, Date.now() - root.lastActivityAt)
        var remainingMs = Math.max(1, timeoutMs - elapsedMs)

        inactivityDeadlineTimer.interval = Math.max(250, remainingMs)
        inactivityDeadlineTimer.restart()
    }

    function activateScreensaver(reason) {
        if (root.inScreensaverMode || root.inScreensaverWakeTransition)
            return false

        // System search is owned by Main rather than Console. Close it before
        // unloading Console so it can never remain above the screensaver.
        if (globalSearchCenter.visible)
            globalSearchCenter.closeCenter()

        root.closeLogoutModal()
        root.closeDeveloperModeModal()

        var normalizedReason = String(reason || "").toLowerCase()
        var resumeConsole = root.authenticated &&
                            root.shellMode === "console" &&
                            consoleLoader.item &&
                            consoleLoader.status === Loader.Ready &&
                            normalizedReason !== "sleep"

        root.screensaverReturnMode = resumeConsole ? "console" : "lock"

        if (resumeConsole) {
            if (consoleLoader.item &&
                    typeof consoleLoader.item.prepareForScreensaver === "function") {
                consoleLoader.item.prepareForScreensaver()
            } else if (consoleLoader.item && "shellActive" in consoleLoader.item) {
                consoleLoader.item.shellActive = false
            }

            root.consoleResident = true
            root.lockResident = false
            root.consoleReady = true
        } else {
            if (consoleLoader.item &&
                    typeof consoleLoader.item.prepareForLock === "function") {
                consoleLoader.item.prepareForLock()
            } else if (consoleLoader.item && "shellActive" in consoleLoader.item) {
                consoleLoader.item.shellActive = false
            }

            if (appHostLoader.item) {
                if (typeof appHostLoader.item.closeAppSilently === "function")
                    appHostLoader.item.closeAppSilently()
                else if (typeof appHostLoader.item.closeApp === "function")
                    appHostLoader.item.closeApp()
            }

            root.authenticated = false
            root.activeUser = null
            root.consoleReady = false
            root.consoleResident = false
            root.lockResident = true
        }

        root.pendingAppData = null
        root.appLaunchSubmitted = false
        root.inputLocked = false
        root.screensaverPending = false
        root.screensaverWakePending = false
        root.logoutModalRetained = false
        root.developerModalRequested = false

        root.lockOpacity = 0.0
        root.consoleOpacity = 0.0
        root.appOpacity = 0.0
        root.screensaverOpacity = 1.0
        root.shellMode = "screensaver"
        root.clearStickNavigation()

        if (root.screensaverBackend) {
            try {
                root.screensaverBackend.activate()
            } catch (error) {
                console.warn("Unable to activate screensaver backend:", error)
            }
        }

        root.screensaverRequested()
        return true
    }

    function wakeScreensaver() {
        if (!root.inScreensaverMode || root.screensaverWakePending)
            return false

        root.screensaverWakePending = true
        root.screensaverWakeConsumeUntil = Date.now() + 700
        root.inputLocked = true
        root.clearStickNavigation()
        root.shellMode = "waking"
        root.screensaverOpacity = 1.0

        if (root.screensaverReturnMode === "console") {
            root.lockOpacity = 0.0
            root.consoleOpacity = 0.0
        } else {
            root.lockOpacity = 0.0
            root.consoleOpacity = 0.0
        }

        Qt.callLater(root.finishScreensaverWakeWhenReady)
        return true
    }

    function finishScreensaverWakeWhenReady() {
        if (!root.inScreensaverWakeTransition)
            return

        if (root.screensaverReturnMode === "console") {
            if (!consoleLoader.item || consoleLoader.status !== Loader.Ready) {
                screensaverWakeReadyTimer.restart()
                return
            }

            if ("activeUser" in consoleLoader.item)
                consoleLoader.item.activeUser = root.activeUser

            if ("shellActive" in consoleLoader.item)
                consoleLoader.item.shellActive = false
        } else {
            if (!lockLoader.item || lockLoader.status !== Loader.Ready) {
                screensaverWakeReadyTimer.restart()
                return
            }

            if (typeof lockLoader.item.prepareForLock === "function")
                lockLoader.item.prepareForLock(false)
            else if ("active" in lockLoader.item)
                lockLoader.item.active = true
        }

        screensaverWakeAnimation.restart()
    }

    function finishScreensaverWake() {
        if (!root.inScreensaverWakeTransition)
            return

        if (root.screensaverBackend) {
            try {
                root.screensaverBackend.deactivate()
            } catch (error) {
            }
        }

        root.screensaverOpacity = 0.0
        root.screensaverWakePending = false
        root.inputLocked = false
        root.markUserActivity()

        if (root.screensaverReturnMode === "console" &&
                consoleLoader.item &&
                consoleLoader.status === Loader.Ready) {
            root.lockOpacity = 0.0
            root.consoleOpacity = 1.0
            root.shellMode = "console"
            root.consoleResident = true
            root.lockResident = false
            root.consoleReady = true

            if ("shellActive" in consoleLoader.item)
                consoleLoader.item.shellActive = true

            consoleLoader.item.forceActiveFocus()
            return
        }

        root.consoleOpacity = 0.0
        root.lockOpacity = 1.0
        root.shellMode = "lock"
        root.lockResident = true
        root.consoleResident = false

        if (lockLoader.item) {
            if ("active" in lockLoader.item)
                lockLoader.item.active = true

            lockLoader.item.forceActiveFocus()
        }

        keyboardFallback.forceActiveFocus()
    }

    function requestControllerOff() {
        var backend = root.inputController

        if (!backend) {
            console.warn("Controller Off requested, but controllerManager is unavailable.")
            return false
        }

        try {
            if (typeof backend.controllerOff === "function")
                return backend.controllerOff()
        } catch (e1) {
            console.warn("controllerOff failed:", e1)
        }

        try {
            if (typeof backend.disconnectController === "function")
                return backend.disconnectController()
        } catch (e2) {
            console.warn("disconnectController failed:", e2)
        }

        try {
            if (typeof backend.powerOffController === "function")
                return backend.powerOffController()
        } catch (e3) {
            console.warn("powerOffController failed:", e3)
        }

        console.warn("Controller Off backend method is not implemented yet.")

        if (backend && typeof backend.hapticWarning === "function")
            backend.hapticWarning()

        return false
    }

    /*
        ============================================================
                            SINGLE INPUT ROUTER
        ============================================================
    */

    function notificationCenterVisible() {
        return root.shellMode === "console" && notificationCenterOverlay.opened
    }

    function openNotificationCenter() {
        if (root.shellMode !== "console" || root.inputLocked ||
                root.isLogoutModalVisible() || root.isDeveloperModalVisible())
            return false
        notificationCenterOverlay.openCenter()
        return true
    }

    function closeNotificationCenter() {
        if (!notificationCenterOverlay.opened)
            return false
        notificationCenterOverlay.closeCenter()
        return true
    }

    function sharedDesktopCarousel() {
        return consoleLoader.item ? consoleLoader.item.desktopCarouselController : null
    }

    function appControllerExclusiveLockActive() {
        if (root.shellMode !== "app" || !appHostLoader.item)
            return false

        try {
            return appHostLoader.item.controllerExclusiveLock === true
        } catch (error) {
            return false
        }
    }

    function dispatchControllerPressed(clean) {
        if (root.browserReturnModalVisible) {
            if (clean === "primary" || clean === "cancel" || clean === "system") {
                root.browserReturnModalVisible = false
                keyboardFallback.forceActiveFocus()
                if (consoleLoader.item) consoleLoader.item.forceActiveFocus()
            }
            return
        }
        if (root.inputLocked)
            return

        if (root.shellMode === "lock") {
            var lockItem = lockLoader.item

            if (lockItem && typeof lockItem.handleControllerPressed === "function") {
                lockItem.handleControllerPressed(clean)
                return
            }

            if (lockItem && typeof lockItem.handleController === "function") {
                lockItem.handleController(clean)
                return
            }

            return
        }

        if (root.inUnlockTransition || root.inLockReturnTransition ||
                root.inScreensaverWakeTransition)
            return

        if (root.shellMode === "app") {
            var appItem = appHostLoader.item

            if (appItem && typeof appItem.handleControllerPressed === "function") {
                appItem.handleControllerPressed(clean)
                return
            }

            if (appItem && typeof appItem.handleController === "function") {
                appItem.handleController(clean)
                return
            }

            if (clean === "cancel")
                root.beginReturnToConsole()

            return
        }

        if (root.shellMode === "console") {
            var consoleItem = consoleLoader.item

            if (consoleItem && typeof consoleItem.handleControllerPressed === "function") {
                consoleItem.handleControllerPressed(clean)
                return
            }

            if (consoleItem && typeof consoleItem.handleController === "function")
                consoleItem.handleController(clean)
        }
    }

    function dispatchControllerReleased(clean) {
        if (root.inputLocked)
            return

        if (root.shellMode === "app") {
            var appItem = appHostLoader.item

            if (appItem && typeof appItem.handleControllerReleased === "function")
                appItem.handleControllerReleased(clean)

            return
        }

        if (root.shellMode === "console") {
            var consoleItem = consoleLoader.item

            if (consoleItem && typeof consoleItem.handleControllerReleased === "function")
                consoleItem.handleControllerReleased(clean)

            return
        }

        if (root.shellMode === "lock") {
            var lockItem = lockLoader.item

            if (lockItem && typeof lockItem.handleControllerReleased === "function")
                lockItem.handleControllerReleased(clean)
        }
    }

    function captureBackend() {
        return (typeof captureManager !== "undefined" && captureManager)
               ? captureManager
               : null
    }

    function captureRecordingActive() {
        var backend = root.captureBackend()
        return backend ? backend.recording === true : false
    }

    function showCaptureToast(message, errorState) {
        root.captureToastText = String(message || "")
        root.captureToastError = errorState === true
        captureToastTimer.restart()
    }

    function formatCaptureTime(totalSeconds) {
        var seconds = Math.max(0, Number(totalSeconds) || 0)
        var minutes = Math.floor(seconds / 60)
        var remainder = Math.floor(seconds % 60)
        return (minutes < 10 ? "0" : "") + minutes + ":" +
               (remainder < 10 ? "0" : "") + remainder
    }

    function takeGlobalScreenshot() {
        var backend = root.captureBackend()
        if (!backend || typeof backend.captureScreenshot !== "function") {
            root.showCaptureToast("Screenshot service unavailable", true)
            return false
        }
        return backend.captureScreenshot(root.Window.window)
    }

    function startGlobalRecording() {
        var backend = root.captureBackend()
        if (!backend || typeof backend.startRecording !== "function") {
            root.showCaptureToast("Recording service unavailable", true)
            return false
        }
        return backend.startRecording(root.Window.window)
    }

    function stopGlobalRecording() {
        var backend = root.captureBackend()
        if (!backend || typeof backend.stopRecording !== "function")
            return false
        return backend.stopRecording()
    }

    function forwardCaptureStickPress(action) {
        if (root.captureStickChordTriggered)
            return

        if (action === "l3") {
            if (!root.captureL3Down || root.captureL3Forwarded)
                return
            root.captureL3Forwarded = true
        } else {
            if (!root.captureR3Down || root.captureR3Forwarded)
                return
            root.captureR3Forwarded = true
        }
        root.dispatchControllerPressed(action)
    }

    function startCaptureRecordingChord() {
        if (!root.captureStickChordTriggered)
            return false

        captureDecisionTimer.stop()
        root.captureDecisionPending = false
        root.captureRecordingChordTriggered = true
        root.captureR1Consumed = true
        r1DispatchTimer.stop()

        if (root.r1Forwarded)
            root.dispatchControllerReleased("r1")
        root.r1Forwarded = false

        root.startGlobalRecording()
        return true
    }

    function triggerCaptureStickChordIfReady() {
        if (!root.captureL3Down || !root.captureR3Down ||
                root.captureStickChordTriggered)
            return false

        root.captureStickChordTriggered = true
        root.captureDecisionPending = true
        root.captureRecordingChordTriggered = false

        // Consume the physical stick pair as a global capture chord.
        l3DispatchTimer.stop()
        r3DispatchTimer.stop()

        if (root.captureL3Forwarded)
            root.dispatchControllerReleased("l3")
        if (root.captureR3Forwarded)
            root.dispatchControllerReleased("r3")
        root.captureL3Forwarded = false
        root.captureR3Forwarded = false

        if (root.r1Down)
            return root.startCaptureRecordingChord()

        captureDecisionTimer.restart()
        return true
    }

    function releaseCaptureStick(action) {
        var wasChord = root.captureStickChordTriggered

        if (action === "l3") {
            l3DispatchTimer.stop()
            if (!wasChord && !root.captureL3Forwarded) {
                root.captureL3Forwarded = true
                root.dispatchControllerPressed("l3")
            }
            if (root.captureL3Forwarded)
                root.dispatchControllerReleased("l3")
            root.captureL3Down = false
            root.captureL3Forwarded = false
        } else {
            r3DispatchTimer.stop()
            if (!wasChord && !root.captureR3Forwarded) {
                root.captureR3Forwarded = true
                root.dispatchControllerPressed("r3")
            }
            if (root.captureR3Forwarded)
                root.dispatchControllerReleased("r3")
            root.captureR3Down = false
            root.captureR3Forwarded = false
        }

        if (!root.captureL3Down && !root.captureR3Down &&
                !root.captureDecisionPending) {
            root.captureStickChordTriggered = false
            root.captureRecordingChordTriggered = false
        }
    }

    function emergencyExitEligible() {
        return root.authenticated &&
               (root.shellMode === "console" ||
                root.shellMode === "app" ||
                root.shellMode === "launchingApp" ||
                root.shellMode === "returningConsole") &&
               !root.inScreensaverMode &&
               !root.inScreensaverWakeTransition
    }

    function cancelEmergencyChord() {
        emergencyExitTimer.stop()
        root.emergencyChordActive = false
    }


    function requestSystemTerminalHandoff(sourceName) {
        if (!root.emergencyExitEligible() ||
                root.systemTerminalHandoffPending) {
            return false
        }

        root.systemTerminalHandoffPending = true
        root.inputLocked = true
        emergencyExitTimer.stop()

        if (root.isLogoutModalVisible())
            root.closeLogoutModal()
        if (root.isDeveloperModalVisible())
            root.closeDeveloperModeModal()

        root.showCaptureToast("Opening the NeutronOS system terminal…", false)

        var launched = false
        try {
            var safeSource = String(sourceName || "unknown")
                    .replace(/[^A-Za-z0-9_.-]/g, "_")

            if (typeof appManager !== "undefined" && appManager &&
                    typeof appManager.launchApp === "function") {
                launched = appManager.launchApp({
                    "id": "neutronos-console-handoff",
                    "name": "NeutronOS System Terminal",
                    "type": "command",
                    "command": "/usr/local/bin/neutronos-open-terminal " + safeSource,
                    "installed": true
                }) === true
            }
        } catch (handoffError) {
            console.error("System terminal handoff failed:", handoffError)
            launched = false
        }

        if (!launched) {
            root.systemTerminalHandoffPending = false
            root.inputLocked = false
            root.showCaptureToast(
                "The system terminal handoff could not be started; NeutronOS stayed open",
                true
            )
            root.restorePrimarySurfaceFocus()
            return false
        }

        systemTerminalHandoffGuard.restart()
        return true
    }

    function updateEmergencyChord() {
        if (!root.emergencyExitEligible() || !root.emergencyHomeDown ||
                !root.l1Down || !root.r1Down) {
            if (root.emergencyChordActive)
                root.cancelEmergencyChord()
            return false
        }

        root.emergencyChordConsumed = true
        root.emergencyChordActive = true
        homePowerHoldTimer.stop()
        developerChordTimer.stop()
        l1DispatchTimer.stop()
        r1DispatchTimer.stop()

        if (root.l1Forwarded)
            root.dispatchControllerReleased("l1")
        if (root.r1Forwarded)
            root.dispatchControllerReleased("r1")

        root.l1Forwarded = false
        root.r1Forwarded = false
        emergencyExitTimer.restart()
        return true
    }

    function triggerShoulderChordIfReady() {
        if (!root.l1Down || !root.r1Down || root.shoulderChordTriggered)
            return false

        if (!root.authenticated ||
                (root.shellMode !== "console" && root.shellMode !== "app")) {
            return false
        }

        root.shoulderChordTriggered = true
        l1DispatchTimer.stop()
        r1DispatchTimer.stop()

        if (root.l1Forwarded)
            root.dispatchControllerReleased("l1")
        if (root.r1Forwarded)
            root.dispatchControllerReleased("r1")

        root.l1Forwarded = false
        root.r1Forwarded = false

        if (root.updateEmergencyChord())
            return true

        /* Small delay lets PS/Home join the chord before Developer Mode opens. */
        developerChordTimer.restart()
        return true
    }

    function forwardShoulderPress(action) {
        if (root.shoulderChordTriggered)
            return

        if (action === "l1") {
            if (!root.l1Down || root.l1Forwarded)
                return

            root.l1Forwarded = true
        } else {
            if (!root.r1Down || root.r1Forwarded)
                return

            root.r1Forwarded = true
        }

        root.dispatchControllerPressed(action)
    }

    function routeControllerPressed(action) {
        var clean = normalizeAction(action)

        if (clean.length === 0)
            return

        if (!root.acceptPressEdge(clean))
            return

        // Notification combo authentication owns every button, including PS/R3.
        // Without this early route global Home/capture shortcuts intercept valid tokens.
        if (root.notificationCenterVisible() && notificationCenterOverlay.securityComboOpen) {
            root.stopDirectionalRepeatTimers()
            root.markUserActivity()
            notificationCenterOverlay.handleControllerPressed(clean)
            return
        }

        // Notification Center owns both stick clicks before the global
        // L3+R3 capture chord. Otherwise L3 never reaches its security arm gate.
        // Every other input follows the existing route unchanged.
        if (root.notificationCenterVisible() && (clean === "l3" || clean === "r3")) {
            root.stopDirectionalRepeatTimers()
            root.markUserActivity()
            notificationCenterOverlay.handleControllerPressed(clean)
            return
        }

        // Global Search is a true shell modal. Route it before the shared
        // VirtualKeyboard shortcut path so its embedded keyboard cannot leak
        // D-pad/face-button input through to Console underneath.
        if (globalSearchCenter.visible) {
            // Keep the analog stick's neutral latch intact while killing every
            // repeat timer. Otherwise a held stick generates a new synthetic
            // D-pad press on every axis sample and appears to control Console
            // behind the modal.
            root.stopDirectionalRepeatTimers()
            root.markUserActivity()
            root.globalSearchConsumedActions[clean] = true
            globalSearchCenter.handleControllerPressed(clean)
            return
        }

        /*
            The shared virtual keyboard owns the complete controller while it
            is visible. Route this before shell-global Home, capture and search
            chords so L2/L3/R3 keep their keyboard meanings and PS/Home opens
            the Remote Keyboard pairing surface instead of the session menu.
        */
        if (RemoteKeyboardManager.keyboardActive) {
            root.clearStickNavigation()
            root.markUserActivity()

            // First Boot Setup owns its embedded VirtualKeyboard directly.
            // dispatchControllerPressed() only understands the normal lock,
            // console, and app surfaces, so routing setup keyboard input there
            // drops D-pad/X into the lock path while Circle can still close via
            // the keyboard's own controller connection. Keep the complete
            // keyboard controller contract inside SetupWizard while setup is
            // visible, then use the normal shared-keyboard route everywhere else.
            if (root.firstBootSetupVisible && setupWizardLoader.item &&
                    typeof setupWizardLoader.item.handleControllerPressed === "function") {
                setupWizardLoader.item.handleControllerPressed(clean)
                return
            }

            // The keyboard owns PS/Home too. VirtualKeyboard uses the same
            // button to open Remote and, while Remote is visible, to close it
            // and return to the keyboard exactly like Circle.
            root.dispatchControllerPressed(clean)
            return
        }

        // Owned Games input is routed before ordinary shell shortcuts only
        // during a live session. Authentication and keyboard ownership above
        // retain their existing precedence.
        if (root.packageSessionAllowed && root.packageSession && root.packageSession.controllerPress(clean)) {
            root.clearStickNavigation()
            return
        }

        // A QML app can take exclusive ownership of the physical controller.
        // This check intentionally runs before every shell-global shortcut:
        // Home/PS, developer chords, capture/recording, notification/search,
        // and AppHost help/exit behavior. The active app receives the press and
        // is responsible for deciding whether that one action has meaning.
        if (root.appControllerExclusiveLockActive()) {
            root.clearStickNavigation()
            root.dispatchControllerPressed(clean)
            return
        }

        if (!root.directionalRepeatTick && !root.consoleSuppressDirectionalRepeat() &&
                (clean === "up" || clean === "down" || clean === "left" || clean === "right")) {
            root.heldDirectionAction = clean
            directionRepeatTimer.stop()
            directionRepeatDelay.restart()
        } else if (root.consoleSuppressDirectionalRepeat() &&
                (clean === "up" || clean === "down" || clean === "left" || clean === "right")) {
            root.heldDirectionAction = ""
            directionRepeatDelay.stop()
            directionRepeatTimer.stop()
        }

        if (root.consoleOneShotNavigation &&
                (clean === "left" || clean === "right" || clean === "up" || clean === "down"))
            root.markDiscreteFooterActivity()
        else
            root.markUserActivity()

        if (globalSecurityModal.opened) {
            globalSecurityModal.handleControllerPressed(clean)
            return
        }

        if (root.firstBootSetupVisible) {
            if (setupWizardLoader.item &&
                    typeof setupWizardLoader.item.handleControllerPressed === "function")
                setupWizardLoader.item.handleControllerPressed(clean)
            return
        }

        /* The wake press is intentionally consumed. */
        if (root.inScreensaverMode) {
            root.wakeScreensaver()
            return
        }

        if (root.inScreensaverWakeTransition)
            return

        if (Date.now() < root.screensaverWakeConsumeUntil)
            return

        /* Recording stop is intentionally a global single R1 press. */
        if (clean === "r1" && root.captureRecordingActive()) {
            root.captureR1Consumed = true
            root.stopGlobalRecording()
            return
        }

        /* L3 + R3 captures; adding R1 inside the chord starts recording. */
        if (clean === "l3") {
            root.captureL3Down = true
            if (!root.triggerCaptureStickChordIfReady())
                l3DispatchTimer.restart()
            return
        }

        if (clean === "r3") {
            root.captureR3Down = true
            if (!root.triggerCaptureStickChordIfReady())
                r3DispatchTimer.restart()
            return
        }

        if (clean === "r1" && root.captureDecisionPending &&
                root.captureL3Down && root.captureR3Down) {
            root.r1Down = true
            root.startCaptureRecordingChord()
            return
        }

        if (diagnosticsCenter.visible) {
            diagnosticsCenter.handleControllerPressed(clean)
            return
        }

        if (globalSearchCenter.visible) {
            // Global app search belongs to Console only. While an AppHost app
            // owns the shell, consume the chord/input here instead of drawing
            // the system search surface over the application.
            if (root.shellMode === "console")
                globalSearchCenter.handleControllerPressed(clean)
            return
        }

        if (clean === "l2" || clean === "r2") {
            if (clean === "l2") root.searchL2Down = true
            else root.searchR2Down = true
            if (root.searchL2Down && root.searchR2Down && root.authenticated &&
                    root.shellMode === "console") {
                root.searchL2Down = false
                root.searchR2Down = false
                root.clearStickNavigation()
                globalSearchCenter.openCenter()
                return
            }
        }

        if (root.isLogoutModalVisible()) {
            root.routeLogoutModalPressed(clean)
            return
        }

        // Controller Connection may temporarily own Home/PS/Xbox/Switch while
        // it verifies the Bluetooth controller that just connected. Route that
        // physical press into the open modal before the normal global Home menu.
        if (clean === "home" && root.shellMode === "console" &&
                consoleLoader.item &&
                consoleLoader.item.controllerPairHomeCaptureActive === true) {
            root.dispatchControllerPressed(clean)
            return
        }

        /*
            One PS/Home press opens the global session modal from Console or
            any active app. On the Login screen Home continues to belong to
            LoginScreen (including its existing Easter-egg handling).
        */
        if (clean === "home" && root.emergencyExitEligible()) {
            root.emergencyHomeDown = true
            root.emergencyChordConsumed = false
            root.homePowerHoldTriggered = false
            homePowerHoldTimer.restart()
            root.updateEmergencyChord()
            return
        }

        if (root.isDeveloperModalVisible()) {
            root.routeDeveloperModalPressed(clean)
            return
        }

        if (root.notificationCenterVisible()) {
            notificationCenterOverlay.handleControllerPressed(clean)
            return
        }

        if (clean === "l1") {
            root.l1Down = true

            if (root.updateEmergencyChord())
                return

            if (!root.triggerShoulderChordIfReady())
                l1DispatchTimer.restart()

            return
        }

        if (clean === "r1") {
            root.r1Down = true

            if (root.updateEmergencyChord())
                return

            if (!root.triggerShoulderChordIfReady())
                r1DispatchTimer.restart()

            return
        }

        root.dispatchControllerPressed(clean)
    }

    function routeControllerReleased(action) {
        var clean = normalizeAction(action)

        if (clean.length === 0)
            return

        root.releasePressEdge(clean)
        if (root.packageSessionAllowed && root.packageSession && root.packageSession.controllerRelease(clean))
            return


        if (root.notificationCenterVisible() && notificationCenterOverlay.securityComboOpen) {
            notificationCenterOverlay.handleControllerReleased(clean)
            return
        }

        // Release is routed before the shell's capture-chord release handler,
        // allowing the next independent L3 press to confirm the armed action.
        if (root.notificationCenterVisible() && (clean === "l3" || clean === "r3")) {
            notificationCenterOverlay.handleControllerReleased(clean)
            return
        }

        if (root.globalSearchConsumedActions[clean] === true) {
            delete root.globalSearchConsumedActions[clean]
            if (globalSearchCenter.visible)
                globalSearchCenter.handleControllerReleased(clean)
            return
        }

        /*
            Releases must take the same direct path as presses while the shared
            keyboard is open. In particular this guarantees Square release
            always stops held-backspace repeat.
        */
        if (RemoteKeyboardManager.keyboardActive) {
            if (clean === root.heldDirectionAction) {
                root.heldDirectionAction = ""
                directionRepeatDelay.stop()
                directionRepeatTimer.stop()
            }

            if (root.firstBootSetupVisible && setupWizardLoader.item &&
                    typeof setupWizardLoader.item.handleControllerReleased === "function") {
                setupWizardLoader.item.handleControllerReleased(clean)
                return
            }

            root.dispatchControllerReleased(clean)
            return
        }

        if (root.appControllerExclusiveLockActive()) {
            if (clean === root.heldDirectionAction) {
                root.heldDirectionAction = ""
                directionRepeatDelay.stop()
                directionRepeatTimer.stop()
            }
            root.dispatchControllerReleased(clean)
            return
        }

        if (clean === root.heldDirectionAction) {
            root.heldDirectionAction = ""
            directionRepeatDelay.stop()
            directionRepeatTimer.stop()
        }

        if (root.firstBootSetupVisible) {
            if (setupWizardLoader.item &&
                    typeof setupWizardLoader.item.handleControllerReleased === "function")
                setupWizardLoader.item.handleControllerReleased(clean)
            return
        }

        if (root.inScreensaverMode || root.inScreensaverWakeTransition)
            return

        if (clean === "home" && root.emergencyHomeDown) {
            homePowerHoldTimer.stop()
            var openSessionMenu = !root.emergencyChordConsumed &&
                                  !root.homePowerHoldTriggered &&
                                  !root.emergencyChordTriggered &&
                                  !root.l1Down && !root.r1Down
            root.emergencyHomeDown = false
            root.homePowerHoldTriggered = false
            root.cancelEmergencyChord()
            if (openSessionMenu) {
                if (root.shellMode === "console")
                    root.dispatchControllerPressed("home")
                else
                    root.openLogoutModal()
            }
            if (!root.l1Down && !root.r1Down) {
                root.emergencyChordConsumed = false
                root.emergencyChordTriggered = false
            }
            return
        }

        if ((clean === "l1" || clean === "r1") &&
                (root.emergencyChordActive || root.emergencyChordConsumed)) {
            root.cancelEmergencyChord()
            developerChordTimer.stop()
            if (clean === "l1") {
                l1DispatchTimer.stop()
                root.l1Down = false
                root.l1Forwarded = false
            } else {
                r1DispatchTimer.stop()
                root.r1Down = false
                root.r1Forwarded = false
            }
            if (!root.emergencyHomeDown && !root.l1Down && !root.r1Down) {
                root.emergencyChordConsumed = false
                root.emergencyChordTriggered = false
                root.shoulderChordTriggered = false
            }
            return
        }

        if (clean === "l3" || clean === "r3") {
            root.releaseCaptureStick(clean)
            return
        }

        if (clean === "r1" && root.captureR1Consumed) {
            root.captureR1Consumed = false
            root.r1Down = false
            root.r1Forwarded = false
            if (!root.l1Down)
                root.shoulderChordTriggered = false
            return
        }

        // Patch 60K: consume the physical L1/R1 releases that opened the
        // Developer Mode modal. They must never be routed into the newly
        // opened modal as navigation/cancel input.
        if (root.shoulderChordTriggered && (clean === "l1" || clean === "r1")) {
            if (clean === "l1") {
                l1DispatchTimer.stop()
                root.l1Down = false
                root.l1Forwarded = false
            } else {
                r1DispatchTimer.stop()
                root.r1Down = false
                root.r1Forwarded = false
            }
            if (!root.l1Down && !root.r1Down)
                root.shoulderChordTriggered = false
            return
        }

        if (diagnosticsCenter.visible) {
            diagnosticsCenter.handleControllerReleased(clean)
            return
        }

        if (globalSearchCenter.visible) {
            if (root.shellMode === "console")
                globalSearchCenter.handleControllerReleased(clean)
            return
        }
        if (clean === "l2") root.searchL2Down = false
        if (clean === "r2") root.searchR2Down = false

        if (root.isLogoutModalVisible()) {
            root.routeLogoutModalReleased(clean)
            return
        }

        if (root.isDeveloperModalVisible()) {
            root.routeDeveloperModalReleased(clean)
            return
        }

        if (root.notificationCenterVisible()) {
            notificationCenterOverlay.handleControllerReleased(clean)
            return
        }

        if (clean === "l1") {
            l1DispatchTimer.stop()

            if (!root.shoulderChordTriggered && !root.l1Forwarded) {
                root.l1Forwarded = true
                root.dispatchControllerPressed("l1")
            }

            if (root.l1Forwarded)
                root.dispatchControllerReleased("l1")

            root.l1Down = false
            root.l1Forwarded = false

            if (!root.r1Down)
                root.shoulderChordTriggered = false

            return
        }

        if (clean === "r1") {
            r1DispatchTimer.stop()

            if (!root.shoulderChordTriggered && !root.r1Forwarded) {
                root.r1Forwarded = true
                root.dispatchControllerPressed("r1")
            }

            if (root.r1Forwarded)
                root.dispatchControllerReleased("r1")

            root.r1Down = false
            root.r1Forwarded = false

            if (!root.l1Down)
                root.shoulderChordTriggered = false

            return
        }

        root.dispatchControllerReleased(clean)
    }

    function stopDirectionalRepeatTimers() {
        stickNavigationRepeat.stop()
        root.heldDirectionAction = ""
        directionRepeatDelay.stop()
        directionRepeatTimer.stop()
    }

    function clearStickNavigation() {
        // Analog navigation is synthesized into the same directional action
        // stream as D-pad presses. Synthesize the matching release when the
        // stick returns to neutral so modal/carousel one-shot latches cannot
        // remain stuck and a direction cannot continue moving on its own.
        var releasedAction = root.heldStickAction
        root.heldStickAction = ""
        if (releasedAction.length > 0) {
            root.releasePressEdge(releasedAction)
            root.dispatchControllerReleased(releasedAction)
        }
        root.stopDirectionalRepeatTimers()
    }

    function routeStickMove(stick, x, y) {
        var sx = Number(x || 0)
        var sy = Number(y || 0)

        // Exclusive controller mode blocks both sticks at the shell boundary.
        // No analog movement is forwarded to AppHost or converted to D-pad.
        if (root.appControllerExclusiveLockActive()) {
            root.clearStickNavigation()
            return
        }

        /* Any deliberate stick movement wakes the saver and is consumed. */
        if (root.inScreensaverMode) {
            var wakeThreshold = (Math.abs(sx) > 100 || Math.abs(sy) > 100)
                                ? 9000
                                : 24
            if (Math.abs(sx) >= wakeThreshold || Math.abs(sy) >= wakeThreshold) {
                root.screensaverStickNeedsNeutral = true
                root.wakeScreensaver()
            }
            root.clearStickNavigation()
            return
        }

        if (root.screensaverStickNeedsNeutral) {
            var neutralThreshold = (Math.abs(sx) > 100 || Math.abs(sy) > 100)
                                   ? 9000
                                   : 24
            if (Math.abs(sx) < neutralThreshold && Math.abs(sy) < neutralThreshold)
                root.screensaverStickNeedsNeutral = false
            root.clearStickNavigation()
            return
        }

        if (Date.now() < root.screensaverWakeConsumeUntil) {
            root.clearStickNavigation()
            return
        }

        /*
            Apps that expose handleStickMoved() receive the original analog
            values through AppHost.  The Browser uses this for directional link
            focus on the left stick and accelerated cursor motion on the right
            stick.  Returning here prevents the same physical movement from
            also being converted into a duplicate D-pad action.
        */
        if (!root.inputLocked && root.shellMode === "app") {
            var activeHost = appHostLoader.item
            if (activeHost && typeof activeHost.handleStickMoved === "function") {
                try {
                    if (activeHost.handleStickMoved(stick, sx, sy) === true) {
                        root.clearStickNavigation()
                        return
                    }
                } catch (stickError) {
                    console.warn("AppHost analog routing failed:", stickError)
                }
            }
        }

        /*
            Apps without a raw-stick handler and the Console retain the normal
            controller-first directional navigation contract.
        */
        if (root.inputLocked ||
                (root.shellMode !== "console" && root.shellMode !== "app")) {
            root.clearStickNavigation()
            return
        }

        var engageThreshold = 42
        var releaseThreshold = 24

        if (Math.abs(sx) > 100 || Math.abs(sy) > 100) {
            engageThreshold = 18000
            releaseThreshold = 9000
        }

        if (Math.abs(sx) < releaseThreshold &&
                Math.abs(sy) < releaseThreshold) {
            root.clearStickNavigation()
            return
        }

        var action = ""

        if (Math.abs(sx) > Math.abs(sy)) {
            if (sx <= -engageThreshold)
                action = "left"
            else if (sx >= engageThreshold)
                action = "right"
        } else {
            if (sy <= -engageThreshold)
                action = "up"
            else if (sy >= engageThreshold)
                action = "down"
        }

        if (action.length === 0)
            return

        if (root.heldStickAction === action)
            return

        // If the stick crosses directly from one direction to another without
        // first sampling neutral, release the previous synthetic action before
        // issuing the new one.
        if (root.heldStickAction.length > 0) {
            var previousStickAction = root.heldStickAction
            root.releasePressEdge(previousStickAction)
            root.dispatchControllerReleased(previousStickAction)
        }

        root.heldStickAction = action
        root.lastStickActionMs = Date.now()
        root.routeControllerPressed(action)
        if (globalSearchCenter.visible) {
            // Search uses one analog navigation step per deflection. Neutral
            // releases the latch in the normal path above.
            stickNavigationRepeat.stop()
        } else if (!root.consoleSuppressDirectionalRepeat()) {
            stickNavigationRepeat.restart()
        } else {
            // Keep the analog direction latched until the stick returns to
            // neutral. Clearing it here caused every subsequent axis sample
            // to look like a brand-new press, which made carousel move mode
            // run continuously after a single deflection.
            stickNavigationRepeat.stop()
        }
    }

    /* PATCH 15: PERSISTENT ACTIVE PROFILE SYNC */
    function syncActiveUserProfile(user) {
        var resolved = user

        if (!resolved) {
            try {
                if (typeof userManager !== "undefined" &&
                        userManager &&
                        userManager.activeUser) {
                    resolved = userManager.activeUser
                }
            } catch (error) {
            }
        }

        if (!resolved)
            return

        root.activeUser = resolved

        if (consoleLoader.item && "activeUser" in consoleLoader.item)
            consoleLoader.item.activeUser = resolved

        if (appHostLoader.item && "activeUser" in appHostLoader.item)
            appHostLoader.item.activeUser = resolved

        if (lockLoader.item && "activeUser" in lockLoader.item)
            lockLoader.item.activeUser = resolved
    }

    Connections {
        target: (typeof userManager !== "undefined") ? userManager : null
        ignoreUnknownSignals: true

        function onActiveUserChanged() {
            if (root.packageSession) {
                root.packageSession.accountChanged()
                root.packageSession.setSystemAccess(root.packageSessionAllowed)
            }
            if (root.authenticated)
                root.syncActiveUserProfile(null)
        }

        function onProfileApplied(user) {
            root.syncActiveUserProfile(user)
        }
    }

    Connections {
        target: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null
        ignoreUnknownSignals: true
        function onSecurityEventRaised(event) {
            if (Number(event.severity || 0) >= 4 && root.authenticated)
                globalSecurityModal.openIncident(event)
        }
    }

    Connections {
        target: root.screensaverBackend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onTimeoutMinutesChanged() {
            root.scheduleAutomaticScreensaver()
        }
    }

    /*
        ============================================================
                            PHYSICAL CONTROLLER
        ============================================================
    */

    Connections {
        target: root.inputController
        ignoreUnknownSignals: true

        /*
            ControllerManager emits actionPressed/actionReleased as the
            canonical discrete controller stream. It also exposes
            buttonPressed/buttonReleased and stick/axis compatibility aliases.

            Listening to every button alias routes one physical D-pad press
            more than once, which caused System Overview to skip alternate
            cards. Buttons stay on the canonical action stream; analog values
            use only stickMoved() below and pass through the duplicate guard.
        */
        function onActionPressed(action) {
            root.routeControllerPressed(action)
        }

        function onActionReleased(action) {
            root.routeControllerReleased(action)
        }

        /*
            D-pad remains on the canonical action stream. Physical analog
            sticks use the dedicated normalized stick stream with deadzone and
            repeat handling, so one stick deflection never duplicates D-pad
            input.
        */
        function onStickMoved(stick, x, y) {
            root.routeStickMove(stick, x, y)
        }

        function onControllerConnectedChanged() {
            if (root.packageSession && root.inputController && !root.inputController.controllerConnected)
                root.packageSession.controllerRelease("home")
            root.refreshBluetoothControllerIdleTimer()
        }

        function onControllerChargingChanged() {
            root.refreshBluetoothControllerIdleTimer()
        }

        function onControllerAddressChanged() {
            root.refreshBluetoothControllerIdleTimer()
        }
    }

    Connections {
        target: (typeof settingsManager !== "undefined") ? settingsManager : null
        enabled: target !== null
        ignoreUnknownSignals: true
        function onValuesChanged() {
            root.refreshBluetoothControllerIdleTimer()
        }
    }

    /*
        ============================================================
                            WEB CONTROLLER BACKUP
        ============================================================
    */

    Connections {
        target: root.inputWebController
        ignoreUnknownSignals: true

        function onActionPressed(action) {
            root.routeControllerPressed(action)
        }

        function onButtonPressed(button) {
            root.routeControllerPressed(button)
        }

        function onButtonReleased(button) {
            root.routeControllerReleased(button)
        }

        function onActionReleased(action) {
            root.routeControllerReleased(action)
        }

        function onWebAction(action) {
            root.routeControllerOneShot(action)
        }

        function onControllerAction(action) {
            root.routeControllerOneShot(action)
        }

        function onKeyPressed(key) {
            root.routeControllerOneShot(key)
        }

        function onStickMoved(stick, x, y) {
            root.routeStickMove(stick, x, y)
        }

        function onAxisMoved(stick, x, y) {
            root.routeStickMove(stick, x, y)
        }
    }

    /*
        ============================================================
                            LOCK SCREEN LOADER
        ============================================================
    */

    Loader {
        id: setupWizardLoader
        anchors.fill: parent
        z: 60000
        active: (typeof setupWizardManager !== "undefined" &&
                 setupWizardManager && (setupWizardManager.setupRequired || root.setupFractureRetained))
        source: active ? Qt.resolvedUrl("SetupWizard.qml") : ""
        asynchronous: false
        visible: active && status === Loader.Ready
        onLoaded: { if (item) item.forceActiveFocus() }
    }

    // Pause only covered Login cosmetics; the live Login resumes behind Ready.
    Binding {
        target:lockLoader.item
        property:"setupCovered"
        value:setupWizardLoader.active && setupWizardLoader.item && setupWizardLoader.item.stepIndex < 9
        when:lockLoader.item!==null
        restoreMode:Binding.RestoreNone
    }
    Binding {
        target:lockLoader.item
        property:"setupTransitionActive"
        value:root.setupFractureRetained
        when:lockLoader.item!==null
        restoreMode:Binding.RestoreNone
    }
    Connections {
        target:setupWizardLoader.item
        function onCompletionStarting() {
            root.setupFractureRetained=true
            root.inputLocked=true
            root.authenticated=false
            root.shellMode="lock";root.lockOpacity=1;root.consoleOpacity=0;root.appOpacity=0
            if(lockLoader.item && "active" in lockLoader.item)lockLoader.item.active=true
        }
        function onCompletionAborted() {root.setupFractureRetained=false;root.inputLocked=false}
        function onCompleted() {root.setupFractureRetained=false;root.handleFirstBootSetupCompleted()}
    }

    Connections {
        target: (typeof setupWizardManager !== "undefined")
                ? setupWizardManager : null
        function onSetupCompleted() {
            if(root.setupFractureRetained)return
            root.handleFirstBootSetupCompleted()
        }
    }

    Loader {
        id: lockLoader

        anchors.fill: parent

        /*
            Retain LoginScreen after unlock. Its active property pauses timers
            and animations, but retaining the object removes the expensive
            synchronous reconstruction that previously froze Logout.
        */
        active: root.lockResident

        source: "LoginScreen.qml"

        visible: root.shellMode === "lock" ||
                 root.shellMode === "unlocking" ||
                 root.shellMode === "locking" ||
                 root.shellMode === "waking"
        // First-time Setup owns input while the retained Login tree is covered.
        enabled: root.shellMode === "lock" && !setupWizardLoader.active
        opacity: root.lockOpacity

        z: 5

        asynchronous: false

        onLoaded: {
            if (!item)
                return

            if ("active" in item)
                item.active = root.shellMode === "lock" ||
                              root.shellMode === "waking"

            if ("activeUser" in item)
                item.activeUser = root.activeUser

            if (root.shellMode === "waking") {
                Qt.callLater(root.finishScreensaverWakeWhenReady)
                return
            }

            if (!setupWizardLoader.active)
                item.forceActiveFocus()

            /*
                Let the lock screen finish its first frame before beginning
                asynchronous Console construction.
            */
            consolePreloadTimer.restart()
        }

        Connections {
            target: lockLoader.item
            ignoreUnknownSignals: true

            function onUnlocked(user) {
                root.beginUnlockToConsole(user)
            }

            function onUnlockPulseFinished() {
                if (root.shellMode !== "unlocking")
                    return
                root.unlockPulseComplete = true
                root.logUnlock("AUTH_PULSE_COMPLETE")
                root.startUnlockRevealWhenConsoleReady()
            }


            function onCardArmedChanged() {
                if (!lockLoader.item || root.shellMode !== "lock")
                    return

                // Card arming must not cancel the scheduled background
                // preload. That deferred the full Console construction until
                // authentication and caused the physical ~10 second pause.
                if (!root.consoleReady && !lockLoader.item.loginSuccess)
                    consolePreloadTimer.restart()
            }

            function onConsoleWarmupRequested() {
                if (root.shellMode === "lock" && !root.authenticated) {
                    root.consolePreloadRequested = true
                    root.consoleResident = true
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
    }

    /*
        ============================================================
                                CONSOLE LOADER
        ============================================================
    */

    Loader {
        id: consoleLoader

        anchors.fill: parent

        /*
            Console is loaded during unlock and kept loaded while authenticated.
            It is not controller-active until shellMode === "console".
        */
        active: root.consoleResident

        source: "Console.qml"

        /*
            While locked, Console is instantiated but not part of the visible
            or enabled scene. Physical controller input continues to route
            only through lockLoader because shellMode remains "lock".
        */
        visible: active && root.shellMode !== "lock"
        enabled: root.shellMode === "console" && !globalSearchCenter.visible
        opacity: root.consoleOpacity

        // During app launch the live Console intentionally sits above the
        // fracture overlay. That masks the crack-propagation phase. The moment
        // the shard animation actually starts, appLaunchFractureRelease drops
        // Console below AppHost so only the clean fracture/fall is visible.
        z: root.shellMode === "launchingApp" && !root.appLaunchFractureRelease ? 10 : 2

        // A verified AppHost return already has an opaque cover frame. Load
        // Console in one pass so Browser exit is not stretched by incremental
        // lock-screen rendering on the Pi.
        asynchronous: !root.appHostReturnCoverVisible

        function configureConsoleItem() {
            if (!item)
                return

            root.consoleReady = true
            root.consoleLoadError = ""

            if ("activeUser" in item)
                item.activeUser = root.activeUser

            if ("lifecycleGeneration" in item)
                item.lifecycleGeneration = root.lifecycleGeneration

            // Preloading must construct the destination only.  Applying a
            // user session while still locked caused expensive layout/profile
            // work twice (Loader.Ready and onLoaded) and left authentication
            // waiting roughly four seconds for a destination already built.
            if (root.shellMode !== "lock" && root.activeUser &&
                    typeof item.resumeSession === "function")
                item.resumeSession(root.lifecycleGeneration, root.activeUser)

            if ("shellActive" in item)
                item.shellActive = root.shellMode === "console"

            if ("globalSearchActive" in item)
                item.globalSearchActive = Qt.binding(function() { return globalSearchCenter.visible })

            /*
                Loader.enabled and Console.shellActive jointly keep the
                preloaded tree non-interactive. Do not assign item.enabled
                here because that would overwrite Console.qml's binding.
            */
            if (root.shellMode === "console") {
                item.forceActiveFocus()
            } else if (root.shellMode === "lock" && root.destinationSurfaceItem) {
                root.destinationSurfaceItem.forceActiveFocus()
            }
        }

        onLoaded: {
            console.log("Main.qml: Console.qml loaded")
            configureConsoleItem()

            if (root.unlockRevealPending)
                root.startUnlockRevealWhenConsoleReady()
        }

        onStatusChanged: {
            if (status === Loader.Ready) {
                console.log("Main.qml: consoleLoader ready")
                root.consoleReady = item !== null
                if (root.unlockRevealPending)
                    root.startUnlockRevealWhenConsoleReady()
            } else if (status === Loader.Error) {
                root.consoleReady = false
                root.consoleLoadError = "Console.qml failed to load"
                root.inputLocked = false
                console.warn("Main.qml: Console.qml failed to load")
                if (root.shellMode === "unlocking")
                    root.remainAtLoginAfterConsoleFailure(root.consoleLoadError)
            } else if (status === Loader.Null) {
                root.consoleReady = false
            }
        }

        Connections {
            target: consoleLoader.item
            ignoreUnknownSignals: true

            function onAppLaunchRequested(appData) {
                root.beginLaunchApp(appData)
            }

            function onNotificationCenterRequested() {
                root.openNotificationCenter()
            }

            function onGlobalSearchRequested() {
                if (root.shellMode === "console") {
                    root.clearStickNavigation()
                    globalSearchCenter.openCenter()
                }
            }

            function onLogoutRequested() {
                root.beginReturnToLock(false)
            }

            function onSessionMenuRequested() {
                root.openLogoutModal()
            }

            function onScreensaverRequested() {
                root.activateScreensaver("quick-action")
            }

            function onControllerOffRequested() {
                root.requestControllerOff()
            }

            function onRestartShellRequested() {
                root.runAuthorizedPowerAction("restart-shell")
            }

            function onRebootRequested() {
                root.runAuthorizedPowerAction("reboot")
            }

            function onShutdownRequested() {
                root.runAuthorizedPowerAction("shutdown")
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 240
                easing.type: Easing.OutCubic
            }
        }
    }

    NotificationCenterOverlay {
        id: notificationCenterOverlay
        anchors.fill: parent
        backgroundSource: consoleLoader
        backend: (typeof notificationManager !== "undefined") ? notificationManager : null
        systemBackend: (typeof systemMonitor !== "undefined") ? systemMonitor : null
        networkBackend: (typeof networkManager !== "undefined") ? networkManager : null
        mediaBackend: (typeof musicPlayerManager !== "undefined") ? musicPlayerManager : null
        securityBackend: (typeof securityManager !== "undefined") ? securityManager : null
        authenticatedUsername: root.authenticated && root.activeUser && root.activeUser.username
                               ? String(root.activeUser.username) : ""
        z: 120

        onClosed: {
            if (root.shellMode === "console" && consoleLoader.item)
                consoleLoader.item.forceActiveFocus()
        }

        onNotificationActionRequested: function(action, payload) {
            // Patch 55 records actions for future app routing. Marking the
            // notification read is already complete; no app is opened from
            // behind the user's back in this first release.
            console.log("Notification action selected:", action)
        }
    }

    Connections {
        target: root.captureBackend()
        enabled: target !== null
        ignoreUnknownSignals: true

        function onScreenshotSaved(path) {
            root.showCaptureToast("Screenshot Captured", false)
        }

        function onRecordingStarted(path) {
            root.showCaptureToast("Screen recording started • R1 stops", false)
        }

        function onRecordingStopped(path) {
            root.showCaptureToast("Screen recording saved to Gallery", false)
        }

        function onCaptureError(message) {
            root.showCaptureToast(message, true)
        }
    }

    Rectangle {
        id: recordingIndicator
        visible: root.captureRecordingActive() &&
                 root.captureBackend() &&
                 root.captureBackend().showIndicator === true
        z: 190
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 30
        anchors.rightMargin: 34
        width: 154
        height: 48
        radius: 24
        color: "#E61D2638"
        border.width: 1
        border.color: "#FF6374"

        Row {
            anchors.centerIn: parent
            spacing: 12

            Rectangle {
                width: 14
                height: 14
                radius: 7
                color: "#FF3148"

                SequentialAnimation on opacity {
                    running: recordingIndicator.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 650 }
                    NumberAnimation { to: 1.0; duration: 650 }
                }
            }

            Text {
                text: root.captureBackend()
                      ? root.formatCaptureTime(root.captureBackend().elapsedSeconds)
                      : "00:00"
                color: "white"
                font.pixelSize: 22
                font.bold: true
            }
        }
    }

    Rectangle {
        id: captureToast
        visible: root.captureToastText.length > 0
        z: 195
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 74
        width: Math.min(parent.width - 80, Math.max(260, captureToastLabel.implicitWidth + 48))
        height: 44
        radius: 22
        color: root.captureToastError ? "#E6461721" : "#F0182638"
        border.width: 1
        border.color: root.captureToastError ? "#FF5B6B" : "#56C8FF"

        Text {
            id: captureToastLabel
            anchors.centerIn: parent
            text: root.captureToastText
            color: "white"
            font.pixelSize: 20
            font.bold: true
        }
    }

    Rectangle {
        id: browserReturnErrorOverlay
        anchors.fill: parent
        visible: root.browserReturnModalVisible
        color: "#E6000000"
        z: 9800
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 140, 1100)
            height: 470
            radius: 34
            color: "#071426"
            border.width: 3
            border.color: "#FF4055"
            Column {
                anchors.fill: parent
                anchors.margins: 38
                spacing: 24
                Text { width: parent.width; text: "BROWSER SESSION ENDED"; color: "#FF7180"; font.pixelSize: 32; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text {
                    width: parent.width
                    text: String((root.appHostSessionReturnData || ({})).message || "The application failed to start. NeutronOS restored your Console session safely.")
                    color: "#F4FBFF"
                    font.pixelSize: 19
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: String((root.appHostSessionReturnData || ({})).logPath || "")
                    color: "#8CA9C3"
                    font.pixelSize: 14
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 330; height: 76; radius: 38; color: "#17365D"; border.width: 2; border.color: "#4DA6FF"
                    Text { anchors.centerIn: parent; text: "X / O  RETURN TO CONSOLE"; color: "#7DF9FF"; font.pixelSize: 16; font.bold: true }
                }
            }
        }
    }

    Rectangle {
        id: consoleLoadErrorOverlay

        anchors.fill: parent
        visible: root.consoleLoadError.length > 0 &&
                 (root.shellMode === "lock" || root.shellMode === "unlocking" ||
                  root.shellMode === "console")

        z: 40
        color: "#050814"

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 160, 980)
            spacing: 18

            Text {
                width: parent.width
                text: "CONSOLE LOAD FAILED"
                color: "#ff3040"
                font.pixelSize: 42
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.consoleLoadError
                color: "white"
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: "Check journalctl -u neutronos.service for the Console.qml error."
                color: "#7df9ff"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }


    /*
        ============================================================
                                APPHOST LOADER
        ============================================================
    */

    Loader {
        id: appHostLoader

        anchors.fill: parent

        active: root.appHostResident

        source: "apps/AppHost.qml"

        visible: active
        opacity: root.appOpacity

        z: 4

        asynchronous: false

        onLoaded: {
            if (!item)
                return

            if ("activeUser" in item)
                item.activeUser = root.activeUser

            if ("lifecycleGeneration" in item)
                item.lifecycleGeneration = root.lifecycleGeneration

            if ("developerModeEnabled" in item &&
                    typeof developerModeManager !== "undefined") {
                item.developerModeEnabled = developerModeManager.developerModeEnabled
            }

            if (root.pendingAppData)
                root.completeAppLaunch()
        }

        Connections {
            target: appHostLoader.item
            ignoreUnknownSignals: true

            function onAppExited() {
                root.beginReturnToConsole()
            }

            function onExitRequested() {
                root.beginReturnToConsole()
            }

            function onAppReady() {
                root.beginAppLaunchFracture()
            }

            function onAppLoadFailed(message) {
                console.warn("AppHost load failed:", message)
                if (root.shellMode === "launchingApp") {
                    appLaunchSlowTimer.stop()
                    appLaunchFractureWatchdog.stop()
                    root.appLaunchSlowNotice = false
                    root.appLaunchFractureRelease = true
                    root.finishLaunchApp()
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
    }

    Connections {
        target: (typeof appManager !== "undefined") ? appManager : null
        ignoreUnknownSignals: true

        function onRuntimeFocusRequested(appData) {
            if (root.shellMode === "app" && appHostLoader.item &&
                    appHostLoader.item.activeAppId === root.packageSessionAppId) {
                root.switchFromPackageSession(appData)
                return
            }
            if (root.shellMode === "console")
                root.beginLaunchApp(appData)
        }
    }

    /*
        ============================================================
                            UNLOCK REVEAL EFFECTS
        ============================================================
    */

    GeminiUnlockTransition {
        id: unlockFractureOverlay
        anchors.fill: parent
        z: 9
        captureSource: lockLoader
        onCaptureReady: function(shardCount) {
            if (root.shellMode !== "unlocking")
                return
            root.unlockState = "CRACKING"
            root.logUnlock("CAPTURE_READY", "SHARDS_CREATED=" + shardCount)
        }
        onCaptureCommitted: {
            if (root.shellMode !== "unlocking")
                return
            root.unlockState = "FRACTURING"
            root.lockOpacity = 0.0
            root.logUnlock("LOGIN_HIDDEN")
        }
        onFractureStarted: function(shardCount) {
            if (root.shellMode === "unlocking")
                root.logUnlock("FRACTURE_STARTED", "SHARDS_CREATED=" + shardCount)
        }
        onTransitionFailed: function(reason) {
            root.unlockFailureReason = String(reason || "UNKNOWN")
            root.logUnlock("FRACTURE_RENDERER_FAILURE", root.unlockFailureReason)
        }
        onFinished: function(fallbackUsed) {
            if (root.shellMode !== "unlocking")
                return
            root.unlockState = "HANDOFF"
            root.logUnlock("FRACTURE_COMPLETE", fallbackUsed ? "FALLBACK" : "TEXTURED")
            root.finishUnlockToConsole()
        }
    }



    /* Console -> App uses the dashboard shard engine but hides crack propagation. */
    UnlockFractureOverlay {
        id: appLaunchFractureOverlay
        anchors.fill: parent
        z: 9
        captureSource: consoleLoader

        onCaptureReady: function(shardCount) {
            if (root.shellMode !== "launchingApp")
                return
        }

        onCaptureCommitted: {
            if (root.shellMode !== "launchingApp")
                return
        }

        onFractureStarted: function(shardCount) {
            if (root.shellMode !== "launchingApp")
                return
            root.appLaunchFractureRelease = true
        }

        onTransitionFailed: function(reason) {
            if (root.shellMode !== "launchingApp")
                return
            console.warn("App launch fracture renderer failed:", String(reason || "UNKNOWN"))
            root.appLaunchFractureRelease = true
            appLaunchFractureWatchdog.stop()
            root.finishLaunchApp()
        }

        onFinished: function(fallbackUsed) {
            if (root.shellMode !== "launchingApp")
                return
            root.appLaunchFractureRelease = true
            appLaunchFractureWatchdog.stop()
            root.finishLaunchApp()
        }
    }



    Item {
        id: slowAppLaunchOverlay
        anchors.fill: parent
        z: 14
        visible: root.shellMode === "launchingApp" && root.appLaunchSlowNotice

        Rectangle {
            anchors.fill: parent
            color: "#02060D"
            opacity: 0.90
        }

        Rectangle {
            anchors.centerIn: parent
            width: 720
            height: 250
            radius: 34
            color: "#071426F2"
            border.width: 1
            border.color: "#337DF9FF"

            Column {
                anchors.centerIn: parent
                width: parent.width - 70
                spacing: 16

                Text {
                    width: parent.width
                    text: "Hmm Something is taking a while"
                    color: "#F4FBFF"
                    font.pixelSize: 29
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    text: "Filesystem must be busy"
                    color: "#7DF9FF"
                    font.pixelSize: 19
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: root.pendingAppData
                          ? String(root.pendingAppData.name || root.pendingAppData.displayName || root.pendingAppData.id || "Application")
                          : "Application"
                    color: "#9FD8FF"
                    font.pixelSize: 16
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }

    ParallelAnimation {
        id: lockReturnAnimation
        running: false

        NumberAnimation {
            target: root
            property: "lockOpacity"
            from: 0.0
            to: 1.0
            duration: 300
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "consoleOpacity"
            to: 0.0
            duration: 250
            easing.type: Easing.InOutCubic
        }

        NumberAnimation {
            target: root
            property: "appOpacity"
            to: 0.0
            duration: 250
            easing.type: Easing.InOutCubic
        }

        onFinished: root.finishReturnToLock()
    }

    /*
        ============================================================
                            TIMERS
        ============================================================
    */

    Timer {
        id: consolePreloadTimer

        /*
            Yield one frame to the lock surface, then construct the inactive
            Console tree. Authentication may happen immediately, so this work
            must not wait for the card to become armed.
        */
        interval: 16
        repeat: false

        onTriggered: {
            if (root.shellMode !== "lock" || root.authenticated)
                return

            if (root.consoleResident)
                return

            root.consolePreloadRequested = true
            root.consoleResident = true
            root.logUnlock("CONSOLE_PRELOAD_REQUESTED")

            /*
                Console.qml may request focus from its own construction code.
                Restore the lock screen on the following event-loop turn.
                Controller routing itself remains shellMode-based.
            */
            Qt.callLater(function() {
                if (root.shellMode === "lock" && root.destinationSurfaceItem)
                    root.destinationSurfaceItem.forceActiveFocus()
            })
        }
    }

    Timer {
        id: stickNavigationRepeat

        interval: root.stickRepeatMs
        repeat: true
        running: false

        onTriggered: {
            if (root.heldStickAction.length === 0 ||
                    root.inputLocked ||
                    root.shellMode !== "console") {
                root.clearStickNavigation()
                return
            }

            if (root.consoleSuppressDirectionalRepeat()) {
                // Do NOT call clearStickNavigation() here. It erases the
                // physical heldStickAction and synthesizes a release while the
                // axis is still held. The next axis sample then re-engages and
                // triggers an endless stream of apparent new key presses.
                // Stop repeat only; routeStickMove() releases on real neutral.
                stickNavigationRepeat.stop()
                root.stopDirectionalRepeatTimers()
                return
            }

            root.lastStickActionMs = Date.now()
            root.routeControllerPressed(root.heldStickAction)
        }
    }

    Timer {
        id: l1DispatchTimer
        interval: root.shoulderChordWindowMs
        repeat: false
        onTriggered: root.forwardShoulderPress("l1")
    }

    Timer {
        id: r1DispatchTimer
        interval: root.shoulderChordWindowMs
        repeat: false
        onTriggered: root.forwardShoulderPress("r1")
    }

    Timer {
        id: developerChordTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root.emergencyHomeDown && root.updateEmergencyChord())
                return
            if (root.l1Down && root.r1Down && root.shoulderChordTriggered &&
                    root.authenticated &&
                    (root.shellMode === "console" || root.shellMode === "app"))
                root.openDeveloperModeModal()
        }
    }

    Timer {
        id: homePowerHoldTimer
        interval: root.homePowerHoldMs
        repeat: false
        onTriggered: {
            if (!root.emergencyHomeDown || root.l1Down || root.r1Down ||
                    root.emergencyChordActive || !root.emergencyExitEligible())
                return
            root.homePowerHoldTriggered = true
            root.emergencyChordConsumed = true
            root.openLogoutModal()
        }
    }

    Timer {
        id: emergencyExitTimer
        interval: root.emergencyChordHoldMs
        repeat: false
        onTriggered: {
            if (!root.emergencyChordActive || !root.emergencyExitEligible() ||
                    !root.emergencyHomeDown || !root.l1Down || !root.r1Down)
                return
            root.emergencyChordTriggered = true
            root.inputLocked = true
            root.requestSystemTerminalHandoff("controller-ps-l1-r1")
        }
    }

    Timer {
        id: systemTerminalHandoffGuard
        interval: 6000
        repeat: false
        onTriggered: {
            if (!root.systemTerminalHandoffPending)
                return

            root.systemTerminalHandoffPending = false
            root.inputLocked = false
            root.showCaptureToast(
                "The system terminal did not take control; NeutronOS stayed open",
                true
            )
            root.restorePrimarySurfaceFocus()
        }
    }


    Timer {
        id: l3DispatchTimer
        interval: root.captureChordWindowMs
        repeat: false
        onTriggered: root.forwardCaptureStickPress("l3")
    }

    Timer {
        id: r3DispatchTimer
        interval: root.captureChordWindowMs
        repeat: false
        onTriggered: root.forwardCaptureStickPress("r3")
    }

    Timer {
        id: captureDecisionTimer
        interval: root.captureChordWindowMs
        repeat: false
        onTriggered: {
            if (!root.captureDecisionPending)
                return
            root.captureDecisionPending = false
            if (!root.captureRecordingChordTriggered)
                root.takeGlobalScreenshot()
            if (!root.captureL3Down && !root.captureR3Down) {
                root.captureStickChordTriggered = false
                root.captureRecordingChordTriggered = false
            }
        }
    }

    Timer {
        id: captureToastTimer
        interval: 2600
        repeat: false
        onTriggered: root.captureToastText = ""
    }

    Timer {
        id: inactivityDeadlineTimer
        interval: 60000
        repeat: false
        running: false

        onTriggered: {
            if (!root.automaticScreensaverEligible())
                return

            var timeoutMs = root.screensaverTimeoutMinutes() * 60000
            var elapsedMs = Date.now() - root.lastActivityAt

            if (timeoutMs > 0 && elapsedMs >= timeoutMs)
                root.activateScreensaver("inactivity")
            else
                root.scheduleAutomaticScreensaver()
        }
    }

    Timer {
        id: screensaverWakeReadyTimer
        interval: 30
        repeat: false
        onTriggered: root.finishScreensaverWakeWhenReady()
    }

    ParallelAnimation {
        id: screensaverWakeAnimation

        NumberAnimation {
            target: root
            property: "screensaverOpacity"
            from: 1.0
            to: 0.0
            duration: 240
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "lockOpacity"
            to: root.screensaverReturnMode === "lock" ? 1.0 : 0.0
            duration: 240
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: root
            property: "consoleOpacity"
            to: root.screensaverReturnMode === "console" ? 1.0 : 0.0
            duration: 240
            easing.type: Easing.OutCubic
        }

        onFinished: root.finishScreensaverWake()
    }

    Timer {
        id: consoleReadinessWatchdog
        // Console is constructed asynchronously on the 2 GB Pi. Keep this
        // deadline independent from the much shorter renderer watchdog so a
        // healthy Loader.Loading state is never misreported as Loader.Error.
        interval: 30000
        repeat: false
        onTriggered: {
            if (root.shellMode !== "unlocking" || !root.unlockRevealPending)
                return
            root.logUnlock("CONSOLE_LOAD_TIMEOUT", "status=" + consoleLoader.status)
            root.remainAtLoginAfterConsoleFailure(
                        "Console.qml did not become ready within 30 seconds")
        }
    }

    Timer {
        id: unlockTransitionWatchdog
        interval: 5600
        repeat: false
        onTriggered: {
            if (root.shellMode === "unlocking") {
                root.logUnlock("COMPLETION_NOT_FIRED", root.unlockState)
                root.finishUnlockFailSafe("unlock transition watchdog expired")
            }
        }
    }

    Timer {
        id: appLaunchFinalizeTimer
        interval: 80
        repeat: false
        onTriggered: root.beginAppLaunchFracture()
    }

    Timer {
        id: appLaunchSlowTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (root.shellMode === "launchingApp" && !root.appLaunchReady)
                root.appLaunchSlowNotice = true
        }
    }

    Timer {
        id: appLaunchFractureWatchdog
        interval: 6000
        repeat: false
        onTriggered: {
            if (root.shellMode !== "launchingApp" || !root.appLaunchFractureStarted)
                return
            console.warn("App launch fracture watchdog expired; completing fail-safe handoff")
            root.appLaunchFractureRelease = true
            appLaunchFractureOverlay.reset()
            root.finishLaunchApp()
        }
    }

    Timer {
        id: returnConsoleFinalizeTimer
        interval: 120
        repeat: false

        onTriggered: {
            root.finishReturnToConsole()
        }
    }

    /*
        ============================================================
                            STATE HELPERS
        ============================================================
    */

    function resolveLoginUser() {
        try {
            if (lockLoader.item && "selectedUser" in lockLoader.item &&
                    typeof userManager !== "undefined" &&
                    userManager.users &&
                    userManager.users.length > 0) {
                return userManager.users[lockLoader.item.selectedUser]
            }
        } catch (e) {
            console.warn("Unable to resolve selected login user:", e)
        }

        try {
            if (typeof userManager !== "undefined" && userManager) {
                if (userManager.activeUser)
                    return userManager.activeUser
                if (userManager.users && userManager.users.length > 0)
                    return userManager.users[0]
            }
        } catch (fallbackError) {
            console.warn("Unable to resolve automatic-login user:", fallbackError)
        }

        return {}
    }

    function resolveUserByName(userName) {
        var wanted = String(userName || "").trim().toLowerCase()
        try {
            if (typeof userManager !== "undefined" && userManager && userManager.users) {
                for (var i = 0; i < userManager.users.length; ++i) {
                    var candidate = userManager.users[i] || ({})
                    var names = [candidate.username, candidate.name, candidate.loginName]
                    for (var j = 0; j < names.length; ++j) {
                        if (String(names[j] || "").trim().toLowerCase() === wanted && wanted.length > 0)
                            return candidate
                    }
                }
            }
        } catch (error) {
            console.warn("Unable to resolve returned browser user:", error)
        }
        return root.resolveLoginUser()
    }

    function logUnlock(state, detail) {
        var elapsed = root.unlockStartedAtMs > 0
                ? " [+" + Math.max(0, Math.round(Date.now() - root.unlockStartedAtMs)) + "ms]"
                : ""
        var suffix = detail === undefined || detail === null || String(detail).length === 0
                ? "" : " " + String(detail)
        console.info("UNLOCK: " + String(state) + elapsed + suffix)
    }

    function startUnlockRevealWhenConsoleReady() {
        if (root.shellMode !== "unlocking")
            return

        if (!root.unlockPulseComplete) {
            root.logUnlock("WAITING_FOR_AUTH_PULSE")
            return
        }

        if (!consoleLoader.item || consoleLoader.status !== Loader.Ready) {
            root.consoleReady = false
            console.warn("Main.qml: unlock waiting for Console.qml")
            return
        }

        root.unlockRevealPending = false
        root.consoleReady = true
        root.consoleLoadError = ""
        consoleReadinessWatchdog.stop()

        if ("activeUser" in consoleLoader.item)
            consoleLoader.item.activeUser = root.activeUser

        // Dashboard is fully rendered but non-interactive underneath the lock.
        root.consoleOpacity = 1.0

        if ("shellActive" in consoleLoader.item)
            consoleLoader.item.shellActive = false

        if (root.appHostSessionReturnPending) {
            root.unlockState = "HANDOFF"
            root.finishUnlockToConsole()
            return
        }

        if (!root.fractureSequenceStarted) {
            root.fractureSequenceStarted = true
            root.logUnlock("CONSOLE_READY")
            root.unlockState = "CAPTURING"
            root.logUnlock("CAPTURE_REQUESTED")
            // From this point the Console is proven ready; the existing
            // bounded watchdog now measures only capture/fracture/handoff.
            unlockTransitionWatchdog.restart()
            var impact = ({ "x": 0.5, "y": 0.43 })
            if (lockLoader.item &&
                    typeof lockLoader.item.fractureOriginNormalized === "function")
                impact = lockLoader.item.fractureOriginNormalized()
            unlockFractureOverlay.originX = Number(impact.x)
            unlockFractureOverlay.originY = Number(impact.y)
            unlockFractureOverlay.start()
        }
    }

    /*
        ============================================================
                            LOCK → CONSOLE
        ============================================================
    */

    function beginUnlockToConsole(user) {
        if (root.shellMode !== "lock") {
            root.logUnlock("AUTH_SUCCESS duplicate authentication ignored", root.shellMode)
            return
        }

        root.closeLogoutModal()


        root.lifecycleGeneration += 1
        root.lifecycleCleanupActive = false
        root.lockResident = true
        root.consoleResident = true
        root.appHostResident = false

        root.authenticated = true
        root.activeUser = user || root.resolveLoginUser()
        Qt.callLater(root.refreshBluetoothControllerIdleTimer)

        // NEUTRONOS_AUTHENTICATED_USER_BINDING_V1
        // UserManager::setActiveUser() is explicitly designed to be called
        // after successful authentication. Keep the backend authoritative so
        // every dashboard/profile surface receives the authenticated account.
        try {
            if (typeof userManager !== "undefined" &&
                    userManager &&
                    typeof userManager.setActiveUser === "function" &&
                    root.activeUser) {
                if (userManager.setActiveUser(root.activeUser) && userManager.activeUser)
                    root.activeUser = userManager.activeUser
            }
        } catch (activeUserError) {
            console.warn("Unable to bind authenticated user profile:", activeUserError)
        }

        if (typeof securityCoreManager !== "undefined" && securityCoreManager)
            securityCoreManager.setShellSessionAuthenticated(true)

        root.inputLocked = true
        root.shellMode = "unlocking"
        root.unlockGeneration += 1
        root.unlockState = "AUTH_SUCCESS"
        root.unlockFailureReason = ""
        root.unlockStartedAtMs = Date.now()
        root.logUnlock("AUTH_SUCCESS")

        root.lockOpacity = 1.0
        root.consoleOpacity = 0.0
        root.appOpacity = 0.0

        root.pendingAppData = null
        root.appLaunchSubmitted = false

        root.consoleReady = consoleLoader.status === Loader.Ready &&
                            consoleLoader.item !== null
        root.unlockRevealPending = true
        root.unlockPulseComplete = !(lockLoader.item &&
                                     lockLoader.item.loginSuccess === true)
        root.fractureSequenceStarted = false
        root.consoleLoadError = ""
        unlockTransitionWatchdog.stop()
        consoleReadinessWatchdog.restart()
        root.consolePreloadRequested = true

        if (consoleLoader.item && typeof consoleLoader.item.resumeSession === "function")
            consoleLoader.item.resumeSession(root.lifecycleGeneration, root.activeUser)

        /*
            Keep LoginScreen active through the visual handoff. Input is already
            disabled by shellMode, but its success animation and background
            motion must continue until Console fully covers it.
        */
        if (lockLoader.item && "active" in lockLoader.item)
            lockLoader.item.active = true

        if (root.inputController && typeof root.inputController.hapticSuccess === "function")
            root.inputController.hapticSuccess()

        /*
            Permanent loader-safe unlock:
            start reveal only after Console.qml is actually ready.
        */
        Qt.callLater(root.startUnlockRevealWhenConsoleReady)
    }


    function finishUnlockToConsole() {
        if (root.shellMode !== "unlocking")
            return

        if (!consoleLoader.item || consoleLoader.status !== Loader.Ready) {
            root.remainAtLoginAfterConsoleFailure(
                        "Console.qml was not ready when unlock finished")
            return
        }

        root.unlockState = "HANDOFF"
        root.unlockRevealPending = false
        root.consoleReady = true
        root.consoleLoadError = ""
        consoleReadinessWatchdog.stop()
        unlockTransitionWatchdog.stop()

        root.shellMode = "console"
        root.consoleResident = true
        root.appHostResident = false
        root.lockResident = false
        root.inputLocked = false

        root.lockOpacity = 0.0
        root.consoleOpacity = 1.0
        root.appOpacity = 0.0
        root.appHostReturnCoverVisible = false

        if ("activeUser" in consoleLoader.item)
            consoleLoader.item.activeUser = root.activeUser

        if ("shellActive" in consoleLoader.item)
            consoleLoader.item.shellActive = true

        if (root.pendingSecurityAppLaunch) {
            root.pendingSecurityAppLaunch = false
            root.pendingSecurityIncident = null
            Qt.callLater(function() { root.launchSecurityAppNow() })
        } else if (root.pendingSecurityIncident) {
            var incident = root.pendingSecurityIncident
            root.pendingSecurityIncident = null
            if (typeof consoleLoader.item.openSecurityIncident === "function")
                consoleLoader.item.openSecurityIncident(incident)
        }

        if (lockLoader.item && "active" in lockLoader.item)
            lockLoader.item.active = false

        root.unlockState = "COMPLETE"
        root.logUnlock("LOGIN_HIDDEN")
        keyboardFallback.forceActiveFocus()
        consoleLoader.item.forceActiveFocus()
        root.logUnlock("DASHBOARD_FOCUSED")
        root.logUnlock("HANDOFF_COMPLETE")
        root.markUserActivity()

        if (root.gameSessionReturnPending) {
            root.gameSessionReturnPending = false
            gameSessionAppLaunchTimer.restart()
        }
        if (root.appHostSessionReturnPending) {
            root.appHostSessionReturnPending = false
            root.startupAppHostReturnSession = ({})
            var appResult = root.appHostSessionReturnData || ({})
            if (String(appResult.appId || "").toLowerCase() === "appstore" &&
                    appResult.cleanExit === true) {
                // A validated rebuild resume lands on Console first so the
                // authenticated shell lifecycle is restored normally, then
                // immediately reopens App Store to its saved success result.
                Qt.callLater(function() {
                    if (root.shellMode !== "console" ||
                            typeof appManager === "undefined" || !appManager)
                        return
                    try {
                        var storeApp = appManager.appById("appstore")
                        if (storeApp && String(storeApp.id || "").length > 0)
                            root.beginLaunchApp(storeApp)
                    } catch (resumeLaunchError) {
                        console.warn("Unable to reopen App Store after rebuild:", resumeLaunchError)
                    }
                })
            } else if (appResult.cleanExit !== true) {
                root.browserReturnModalVisible = true
            }
        }
    }

    function remainAtLoginAfterConsoleFailure(reason) {
        root.consoleReady = false
        root.consoleLoadError = String(reason || "Console.qml failed to load")
        root.unlockFailureReason = root.consoleLoadError
        root.logUnlock("CONSOLE_NOT_READY", root.consoleLoadError)
        console.warn("Main.qml: refused to finish unlock because Console.qml is not ready")

        consoleReadinessWatchdog.stop()
        unlockTransitionWatchdog.stop()
        unlockFractureOverlay.reset()
        root.unlockRevealPending = false
        root.fractureSequenceStarted = false
        root.authenticated = false
        root.inputLocked = false
        root.shellMode = "lock"
        root.unlockState = "LOCKED"
        root.lockResident = true
        root.lockOpacity = 1.0
        root.consoleOpacity = 0.0

        if (typeof securityCoreManager !== "undefined" && securityCoreManager)
            securityCoreManager.setShellSessionAuthenticated(false)
        if (lockLoader.item) {
            if (typeof lockLoader.item.resetForNewSession === "function")
                lockLoader.item.resetForNewSession()
            if ("active" in lockLoader.item)
                lockLoader.item.active = true
            lockLoader.item.forceActiveFocus()
        }
    }

    function finishUnlockFailSafe(reason) {
        if (root.shellMode !== "unlocking")
            return
        root.unlockFailureReason = String(reason || "renderer failure")
        root.logUnlock("FAIL_SAFE_HANDOFF", root.unlockFailureReason)
        if (!consoleLoader.item || consoleLoader.status !== Loader.Ready) {
            root.remainAtLoginAfterConsoleFailure(
                        "Console.qml is unavailable; unlock fail-safe remained at login")
            return
        }
        unlockFractureOverlay.reset()
        root.lockOpacity = 0.0
        root.consoleOpacity = 1.0
        root.unlockState = "HANDOFF"
        root.finishUnlockToConsole()
    }


    /*
        ============================================================
                            CONSOLE → APPHOST
        ============================================================
    */

    function resolvedRegistryApp(appData) {
        if (!appData)
            return null

        var appId = ""
        try {
            appId = String(appData.appId || appData.id || "").trim()
        } catch (error) {
            appId = ""
        }

        if (appId.length > 0 &&
                typeof appManager !== "undefined" &&
                appManager &&
                typeof appManager.appById === "function") {
            try {
                var registered = appManager.appById(appId)
                if (registered && String(registered.id || "").length > 0)
                    return registered
            } catch (lookupError) {
                console.warn("Unable to resolve registered app:", appId, lookupError)
            }
        }

        return appData
    }

    function beginLaunchApp(appData) {
        if (root.shellMode !== "console")
            return

        if (!appData)
            return

        root.closeLogoutModal()
        root.searchL2Down = false
        root.searchR2Down = false
        if (globalSearchCenter.visible)
            globalSearchCenter.closeCenter()

        var preparedAppData = root.resolvedRegistryApp(appData)
        var preparedAppId = String(preparedAppData && preparedAppData.id || "").toLowerCase()
        var frontendOwnsBackendRecovery = preparedAppId === "jellyfin"

        // Jellyfin must open even when Docker/the server is stopped. The visible
        // Jellyfin frontend owns disconnected and recovery behavior.
        if (!frontendOwnsBackendRecovery &&
                typeof appManager !== "undefined" &&
                appManager &&
                typeof appManager.prepareAppForLaunch === "function") {
            var ready = false
            try {
                ready = appManager.prepareAppForLaunch(preparedAppData) === true
            } catch (prepareError) {
                console.warn("App backend preparation failed:", prepareError)
                ready = false
            }

            if (!ready) {
                console.warn("App launch blocked because its backend did not become ready:",
                             preparedAppData && (preparedAppData.name || preparedAppData.id || "Unknown"))
                root.inputLocked = false
                root.shellMode = "console"
                if (consoleLoader.item && "shellActive" in consoleLoader.item)
                    consoleLoader.item.shellActive = true
                return
            }
        }

        appData = preparedAppData

        root.consoleResident = true
        root.appHostResident = true
        root.lockResident = false

        root.pendingAppData = appData
        root.appLaunchSubmitted = false
        root.appLaunchReady = false
        root.appLaunchFractureStarted = false
        root.appLaunchFractureRelease = false
        root.appLaunchSlowNotice = false
        appLaunchFractureOverlay.reset()
        appLaunchFractureWatchdog.stop()
        appLaunchSlowTimer.restart()

        root.inputLocked = true
        root.shellMode = "launchingApp"

        root.appOpacity = 1.0
        root.consoleOpacity = 1.0
        root.lockOpacity = 0.0

        if (consoleLoader.item && "shellActive" in consoleLoader.item)
            consoleLoader.item.shellActive = false

        if (root.inputController && typeof root.inputController.hapticSelection === "function")
            root.inputController.hapticSelection()

        if (appHostLoader.item)
            completeAppLaunch()
    }

    function completeAppLaunch() {
        if (root.shellMode !== "launchingApp")
            return

        if (!appHostLoader.item)
            return

        if (root.appLaunchSubmitted)
            return

        root.appLaunchSubmitted = true

        if (root.pendingAppData &&
                typeof appHostLoader.item.launch === "function") {
            appHostLoader.item.launch(root.pendingAppData)
        } else if (root.pendingAppData) {
            console.warn("AppHost.launch(appData) is not available yet.")
        }

        // AppHost.appReady starts the fracture only after the destination exists.
    }

    function beginAppLaunchFracture() {
        if (root.shellMode !== "launchingApp")
            return

        if (root.appLaunchFractureStarted)
            return

        root.appLaunchReady = true
        root.appLaunchSlowNotice = false
        appLaunchSlowTimer.stop()

        if (!consoleLoader.item || consoleLoader.status !== Loader.Ready) {
            root.appLaunchFractureRelease = true
            root.finishLaunchApp()
            return
        }

        root.appLaunchFractureStarted = true
        root.appLaunchFractureRelease = false
        appLaunchFractureOverlay.reset()
        appLaunchFractureOverlay.originX = 0.5
        appLaunchFractureOverlay.originY = 0.5
        appLaunchFractureWatchdog.restart()
        Qt.callLater(function() {
            if (root.shellMode === "launchingApp" && root.appLaunchFractureStarted)
                appLaunchFractureOverlay.start()
        })
    }

    function finishLaunchApp() {
        if (root.shellMode !== "launchingApp")
            return

        appLaunchSlowTimer.stop()
        appLaunchFractureWatchdog.stop()
        root.appLaunchSlowNotice = false
        root.appLaunchFractureRelease = true

        root.shellMode = "app"
        root.appHostResident = true
        // Keep the already-built Console dormant behind AppHost. Rebuilding
        // the full Dashboard on every app exit accounted for 5–7 seconds in
        // the physical journal; shellActive=false already suspends its visual
        // timers and telemetry.
        root.consoleResident = true
        root.lockResident = false
        root.inputLocked = false

        root.consoleOpacity = 0.0
        root.appOpacity = 1.0
        root.lockOpacity = 0.0

        if (appHostLoader.item)
            appHostLoader.item.forceActiveFocus()

        keyboardFallback.forceActiveFocus()
    }

    /*
        ============================================================
                            APPHOST → CONSOLE
        ============================================================
    */

    function beginReturnToConsole() {
        if (root.shellMode !== "app" &&
                root.shellMode !== "launchingApp")
            return

        root.closeLogoutModal()

        appLaunchSlowTimer.stop()
        appLaunchFractureWatchdog.stop()
        root.appLaunchSlowNotice = false
        root.appLaunchFractureStarted = false
        root.appLaunchFractureRelease = true
        appLaunchFractureOverlay.reset()

        root.consoleResident = true
        root.appHostResident = true
        root.lockResident = false

        root.inputLocked = true
        root.shellMode = "returningConsole"
        root.returnConsoleWaitAttempts = 0

        root.consoleOpacity = 0.0
        root.appOpacity = 1.0
        root.lockOpacity = 0.0

        returnConsoleFinalizeTimer.restart()
    }

    function finishReturnToConsole() {
        if (root.shellMode !== "returningConsole")
            return

        /*
            Console.qml is loaded asynchronously. Do not unload AppHost or
            complete the transition until the Console object actually exists.
            Finishing after the old fixed 120 ms delay caused an empty/partial
            Console when returning from Hidden Dock launches on the Pi.
        */
        if (consoleLoader.status !== Loader.Ready || !consoleLoader.item) {
            root.returnConsoleWaitAttempts += 1

            if (consoleLoader.status === Loader.Error ||
                    root.returnConsoleWaitAttempts >= 250) {
                root.consoleLoadError = consoleLoader.status === Loader.Error
                        ? "Console.qml failed to reload after the app closed"
                        : "Console.qml did not become ready after the app closed"

                root.pendingAppData = null
                root.appLaunchSubmitted = false
                root.shellMode = "console"
                root.consoleResident = true
                root.appHostResident = false
                root.lockResident = false
                root.inputLocked = false
                root.consoleOpacity = 1.0
                root.appOpacity = 0.0
                root.lockOpacity = 0.0
                keyboardFallback.forceActiveFocus()
                idleResourceReleaseTimer.restart()
                return
            }

            returnConsoleFinalizeTimer.restart()
            return
        }

        root.returnConsoleWaitAttempts = 0
        root.pendingAppData = null
        root.appLaunchSubmitted = false

        root.shellMode = "console"
        root.consoleResident = true
        root.appHostResident = false
        root.lockResident = false
        root.inputLocked = false

        root.consoleOpacity = 1.0
        root.appOpacity = 0.0
        root.lockOpacity = 0.0

        if (typeof consoleLoader.item.resumeSession === "function")
            consoleLoader.item.resumeSession(root.lifecycleGeneration, root.activeUser)

        if ("shellActive" in consoleLoader.item)
            consoleLoader.item.shellActive = true

        if (root.pendingSecurityAppLaunch) {
            root.pendingSecurityAppLaunch = false
            root.pendingSecurityIncident = null
            Qt.callLater(function() { root.launchSecurityAppNow() })
        } else if (root.pendingSecurityIncident) {
            var incident = root.pendingSecurityIncident
            root.pendingSecurityIncident = null
            if (typeof consoleLoader.item.openSecurityIncident === "function")
                consoleLoader.item.openSecurityIncident(incident)
        }

        Qt.callLater(function() {
            if (root.shellMode === "console" && consoleLoader.item)
                consoleLoader.item.forceActiveFocus()
        })

        root.markUserActivity()

        /* AppHost becomes inactive only after Console is confirmed ready. */
        idleResourceReleaseTimer.restart()
    }

    /*
        ============================================================
                            CONSOLE / APP → LOCK
        ============================================================
    */

    function beginReturnToLock(enableScreensaver) {
        if (root.shellMode !== "console" &&
                root.shellMode !== "app" &&
                root.shellMode !== "launchingApp") {
            return
        }

        root.closeLogoutModal()


        root.lifecycleCleanupActive = true
        root.lockResident = true

        if (consoleLoader.item &&
                typeof consoleLoader.item.prepareForLogout === "function") {
            consoleLoader.item.prepareForLogout()
        }
        root.screensaverPending = enableScreensaver === true
        root.inputLocked = true
        root.authenticated = false
        if (typeof securityCoreManager !== "undefined" && securityCoreManager)
            securityCoreManager.setShellSessionAuthenticated(false)

        if (consoleLoader.item &&
                typeof consoleLoader.item.prepareForLock === "function") {
            consoleLoader.item.prepareForLock()
        } else if (consoleLoader.item && "shellActive" in consoleLoader.item) {
            consoleLoader.item.shellActive = false
        }

        if (appHostLoader.item) {
            if (typeof appHostLoader.item.prepareForLogout === "function")
                appHostLoader.item.prepareForLogout()
            else if (typeof appHostLoader.item.closeAppSilently === "function")
                appHostLoader.item.closeAppSilently()
            else if (typeof appHostLoader.item.closeApp === "function")
                appHostLoader.item.closeApp()
        }

        root.pendingAppData = null
        root.appLaunchSubmitted = false
        root.shellMode = "locking"

        root.lockOpacity = 0.0

        if (root.appOpacity > root.consoleOpacity) {
            root.appOpacity = 1.0
            root.consoleOpacity = 0.0
        } else {
            root.consoleOpacity = 1.0
            root.appOpacity = 0.0
        }

        if (lockLoader.item) {
            if (typeof lockLoader.item.prepareForLock === "function")
                lockLoader.item.prepareForLock(root.screensaverPending)
            else if ("active" in lockLoader.item)
                lockLoader.item.active = true
        }

        if (root.inputController &&
                typeof root.inputController.hapticWarning === "function") {
            root.inputController.hapticWarning()
        }

        lockReturnAnimation.restart()
    }

    function finishReturnToLock() {
        if (root.shellMode !== "locking")
            return

        root.activeUser = null
        root.authenticated = false
        root.pendingAppData = null
        root.appLaunchSubmitted = false


        root.consoleResident = false
        root.appHostResident = false
        root.lockResident = true
        root.lifecycleCleanupActive = false
        root.consoleReady = false
        root.consoleLoadError = ""

        root.lockOpacity = 1.0
        root.consoleOpacity = 0.0
        root.appOpacity = 0.0
        unlockFractureOverlay.reset()
        unlockTransitionWatchdog.stop()
        root.unlockState = "LOCKED"
        root.unlockPulseComplete = false
        root.fractureSequenceStarted = false
        root.unlockFailureReason = ""

        if (lockLoader.item &&
                typeof lockLoader.item.resetForNewSession === "function") {
            lockLoader.item.resetForNewSession()
        }

        if (lockLoader.item) {
            if ("active" in lockLoader.item)
                lockLoader.item.active = true

            lockLoader.item.forceActiveFocus()
        }

        root.shellMode = "lock"
        root.inputLocked = false
        keyboardFallback.forceActiveFocus()

        if (root.screensaverPending) {
            root.screensaverPending = false
            Qt.callLater(function() { root.activateScreensaver("sleep") })
        }
    }

    /*
        ============================================================
                            GLOBAL LOGOUT MODAL
        ============================================================
    */

    Loader {
        id: logoutModalLoader

        anchors.fill: parent

        /*
            Load after authentication and retain after first creation. This
            makes opening instant and avoids destroying the modal during the
            logout transition.
        */
        active: !root.inScreensaverMode &&
                !root.inScreensaverWakeTransition &&
                (root.logoutModalRetained ||
                 root.logoutModalRequested ||
                 root.logoutModalOpen ||
                 root.shellMode === "console" ||
                 root.shellMode === "app")
        source: "modals/LogoutModal.qml"

        visible: active
        z: 60

        asynchronous: true

        onLoaded: {
            if (!item)
                return

            root.logoutModalRetained = true
            item.visible = false

            if (root.logoutModalRequested)
                Qt.callLater(root.openLoadedLogoutModal)
        }

        Connections {
            target: logoutModalLoader.item
            ignoreUnknownSignals: true

            function onLogoutRequested() {
                root.handleLogoutModalLogout()
            }

            function onLockRequested() {
                root.handleLogoutModalLock()
            }

            function onRestartShellRequested() {
                root.runAuthorizedPowerAction("restart-shell")
            }

            function onDiagnosticsRequested() {
                root.diagnosticsCenterOpen = true
                diagnosticsCenter.openCenter()
            }

            function onRecoveryRequested() {
                if (typeof updateRecoveryManager !== "undefined")
                    updateRecoveryManager.prepareRecoveryMode()
            }

            function onRebootRequested() {
                root.runAuthorizedPowerAction("reboot")
            }

            function onShutdownRequested() {
                root.runAuthorizedPowerAction("shutdown")
            }

            function onCancelled() {
                root.handleLogoutModalCancel()
            }

            function onClosed() {
                root.logoutModalOpen = false
                root.logoutModalRequested = false
                root.markUserActivity()
                Qt.callLater(function() {
                    if (root.shellMode === "lock" && lockLoader.item)
                        lockLoader.item.forceActiveFocus()
                    else
                        keyboardFallback.forceActiveFocus()
                })
            }
        }
    }

    DiagnosticsCenter {
        id: diagnosticsCenter
        anchors.fill: parent
        backend: (typeof diagnosticsManager !== "undefined") ? diagnosticsManager : null
        z: 12000
        onClosed: {
            root.diagnosticsCenterOpen = false
            keyboardFallback.forceActiveFocus()
        }
    }

    GlobalSearchCenter {
        id: globalSearchCenter
        anchors.fill: parent
        z: 12500
        appsBackend: (typeof appManager !== "undefined") ? appManager : null
        shellActive: root.shellMode === "console" &&
                     !root.inScreensaverMode &&
                     !root.inScreensaverWakeTransition
        onClosed: {
            root.searchL2Down = false
            root.searchR2Down = false
            keyboardFallback.forceActiveFocus()
        }
        onActionRequested: function(action) {
            if (action.indexOf("open-app:") === 0 && typeof appManager !== "undefined") {
                var id = action.substring(9)
                var apps = appManager.apps || []
                for (var i=0;i<apps.length;i++) if (String(apps[i].id)===id) { root.beginLaunchApp(apps[i]); break }
            } else if (action.indexOf("settings:") === 0 && typeof appManager !== "undefined") {
                var registry = appManager.apps || []
                for (var j=0;j<registry.length;j++) if (String(registry[j].id)==="settings") { root.beginLaunchApp(registry[j]); break }
            }
        }
    }

    /*
        ============================================================
                        GLOBAL DEVELOPER MODE MODAL
        ============================================================
    */

    Loader {
        id: developerModeModalLoader

        anchors.fill: parent
        active: !root.inScreensaverMode &&
                !root.inScreensaverWakeTransition &&
                (root.authenticated || root.developerModalRequested)
        source: "components/DeveloperModeModal.qml"
        visible: active
        asynchronous: true
        z: 70

        onLoaded: {
            if (!item)
                return

            item.visible = false

            if (root.developerModalRequested)
                Qt.callLater(root.openLoadedDeveloperModeModal)
        }

        Connections {
            target: developerModeModalLoader.item
            ignoreUnknownSignals: true

            function refreshTerminalMode() {
                try {
                    if (typeof terminalManager !== "undefined" &&
                            terminalManager &&
                            typeof terminalManager.refreshMode === "function") {
                        terminalManager.refreshMode()
                    }
                } catch (error) {
                }
            }

            function onDeveloperModeEnabled() {
                refreshTerminalMode()
                root.markUserActivity()
            }

            function onDeveloperModeDisabled() {
                refreshTerminalMode()
                root.markUserActivity()
            }

            function onClosed() {
                root.developerModalRequested = false
                root.markUserActivity()
                root.restorePrimarySurfaceFocus()
            }
        }
    }

    /*
        ============================================================
                            SCREENSAVER LAYER
        ============================================================
    */

    Loader {
        id: screensaverLoader

        anchors.fill: parent
        active: root.inScreensaverMode ||
                root.inScreensaverWakeTransition
        source: "screensaver/ScreensaverView.qml"
        visible: active
        opacity: root.screensaverOpacity
        asynchronous: false
        z: 80

        onLoaded: {
            if (!item)
                return

            item.manager = root.screensaverBackend
            item.active = root.inScreensaverMode ||
                          root.inScreensaverWakeTransition
        }

        onActiveChanged: {
            if (!active || !item)
                return

            item.manager = root.screensaverBackend
            item.active = true
            Qt.callLater(function() { item.forceActiveFocus() })
        }

        Connections {
            target: screensaverLoader.item
            ignoreUnknownSignals: true

            function onWakeRequested() {
                root.wakeScreensaver()
            }
        }
    }

    Shortcut {
        sequence: "Home"
        context: Qt.ApplicationShortcut
        enabled: !root.inScreensaverMode &&
                 !root.inScreensaverWakeTransition &&
                 !root.isLogoutModalVisible() &&
                 !root.isDeveloperModalVisible() &&
                 (root.shellMode === "console" ||
                  root.shellMode === "app" ||
                  root.shellMode === "launchingApp" ||
                  root.shellMode === "returningConsole")

        onActivated: {
            root.markUserActivity()
            root.openLogoutModal()
        }
    }

    /* Logged-in emergency escape: close NeutronShell and return to tty1. */
    Shortcut {
        sequence: "Ctrl+Alt+Delete"
        context: Qt.ApplicationShortcut
        enabled: root.authenticated &&
                 !root.inLockMode &&
                 !root.inUnlockTransition &&
                 !root.inScreensaverMode &&
                 !root.inScreensaverWakeTransition

        onActivated: {
            root.inputLocked = true
            root.requestSystemTerminalHandoff("keyboard-ctrl-alt-delete")
        }
    }

    Shortcut {
        sequence: "Ctrl+Alt+F1"
        context: Qt.ApplicationShortcut
        enabled: root.authenticated &&
                 !root.inLockMode &&
                 !root.inUnlockTransition &&
                 !root.inScreensaverMode &&
                 !root.inScreensaverWakeTransition
        onActivated: root.requestSystemTerminalHandoff("keyboard-ctrl-alt-f1")
    }

    Shortcut {
        sequence: "Ctrl+Alt+F2"
        context: Qt.ApplicationShortcut
        enabled: root.authenticated &&
                 !root.inLockMode &&
                 !root.inUnlockTransition &&
                 !root.inScreensaverMode &&
                 !root.inScreensaverWakeTransition
        onActivated: root.requestSystemTerminalHandoff("keyboard-ctrl-alt-f2")
    }

    Shortcut {
        sequence: "Ctrl+Alt+Esc"
        context: Qt.ApplicationShortcut
        enabled: root.authenticated &&
                 !root.inLockMode &&
                 !root.inUnlockTransition &&
                 !root.inScreensaverMode &&
                 !root.inScreensaverWakeTransition
        onActivated: root.requestSystemTerminalHandoff("keyboard-ctrl-alt-escape")
    }


    Shortcut {
        sequence: "F3"
        context: Qt.ApplicationShortcut
        enabled: root.authenticated &&
                 !root.inScreensaverMode &&
                 !root.inScreensaverWakeTransition &&
                 !root.isLogoutModalVisible() &&
                 !root.isDeveloperModalVisible()

        onActivated: {
            root.markUserActivity()
            root.openDeveloperModeModal()
        }
    }

    Shortcut {
        sequence: "F10"
        context: Qt.ApplicationShortcut
        onActivated: root.takeGlobalScreenshot()
    }

    Shortcut {
        sequence: "Shift+F10"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (root.captureRecordingActive())
                root.stopGlobalRecording()
            else
                root.startGlobalRecording()
        }
    }

    /*
        ============================================================
                        KEYBOARD FALLBACK CONTROLLER
        ============================================================
    */

    Item {
        id: keyboardFallback

        anchors.fill: parent
        focus: true
        activeFocusOnTab: true
        enabled: !root.inScreensaverMode &&
                 !root.inScreensaverWakeTransition

        z: 30

        Keys.onPressed: function(event) {
            if (event.isAutoRepeat)
                return

            if (event.key === Qt.Key_Escape ||
                    event.key === Qt.Key_Backspace) {
                root.routeControllerPressed("cancel")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Return ||
                    event.key === Qt.Key_Enter ||
                    event.key === Qt.Key_Space) {
                root.routeControllerPressed("primary")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Up ||
                    event.key === Qt.Key_W) {
                root.routeControllerPressed("up")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Down ||
                    event.key === Qt.Key_S) {
                root.routeControllerPressed("down")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Left ||
                    event.key === Qt.Key_A) {
                root.routeControllerPressed("left")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Right ||
                    event.key === Qt.Key_D) {
                root.routeControllerPressed("right")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Tab) {
                root.routeControllerPressed("system")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_F1) {
                root.routeControllerPressed("context")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_F2) {
                root.routeControllerPressed("secondary")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_PageUp) {
                root.routeControllerPressed("l1")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_PageDown) {
                root.routeControllerPressed("r1")
                event.accepted = true
                return
            }
        }

        Keys.onReleased: function(event) {
            if (event.isAutoRepeat)
                return

            if (event.key === Qt.Key_Escape ||
                    event.key === Qt.Key_Backspace) {
                root.routeControllerReleased("cancel")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Return ||
                    event.key === Qt.Key_Enter ||
                    event.key === Qt.Key_Space) {
                root.routeControllerReleased("primary")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Up ||
                    event.key === Qt.Key_W) {
                root.routeControllerReleased("up")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Down ||
                    event.key === Qt.Key_S) {
                root.routeControllerReleased("down")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Left ||
                    event.key === Qt.Key_A) {
                root.routeControllerReleased("left")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Right ||
                    event.key === Qt.Key_D) {
                root.routeControllerReleased("right")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_Tab) {
                root.routeControllerReleased("system")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_F1) {
                root.routeControllerReleased("context")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_F2) {
                root.routeControllerReleased("secondary")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_PageUp) {
                root.routeControllerReleased("l1")
                event.accepted = true
                return
            }

            if (event.key === Qt.Key_PageDown) {
                root.routeControllerReleased("r1")
                event.accepted = true
                return
            }
        }

        Component.onCompleted: {
            forceActiveFocus()
        }
    }

    /*
        Keeps keyboard fallback alive after loaders swap screens.
    */

    /*
        Focus is restored explicitly by screen transitions and modal closure.
        Continuous focus polling is intentionally avoided.
    */

    Timer {
        id: appHostSessionReturnTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root.shellMode !== "lock" ||
                    typeof appManager === "undefined" || !appManager ||
                    typeof appManager.consumeExternalReturnSession !== "function")
                return
            var returned = root.startupAppHostReturnSession || ({})
            if (returned.pending !== true) {
                try { returned = appManager.consumeExternalReturnSession() || ({}) }
                catch (error) { console.warn("Unable to inspect AppHost return session:", error); return }
            }
            if (returned.pending !== true)
                return
            root.consolePreloadRequested = true
            root.consoleResident = true
            var user = root.resolveUserByName(returned.userName)
            if (!user || Object.keys(user).length === 0) {
                root.appHostReturnResolveAttempts += 1
                if (root.appHostReturnResolveAttempts < 120) {
                    root.startupAppHostReturnSession = returned
                    appHostSessionReturnTimer.restart()
                    return
                }
                console.warn("Browser return user did not become available; remaining fail-closed at login.")
                root.startupAppHostReturnSession = ({})
                return
            }
            root.appHostReturnResolveAttempts = 0
            root.automaticLoginAttempted = true
            root.appHostSessionReturnData = returned
            root.appHostSessionReturnPending = true
            try {
                if (typeof securityManager !== "undefined" && securityManager)
                    securityManager.setActiveUser(user)
            } catch (securityError) {
                console.warn("Unable to restore browser-session user:", securityError)
            }
            root.beginUnlockToConsole(user)
        }
    }

    Timer {
        id: gameSessionReturnTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (root.shellMode !== "lock" ||
                    typeof gamesManager === "undefined" ||
                    !gamesManager ||
                    typeof gamesManager.consumeReturnSession !== "function")
                return

            var returned = ({})
            try {
                returned = gamesManager.consumeReturnSession() || ({})
            } catch (error) {
                console.warn("Unable to inspect the trusted game return session:", error)
                return
            }
            if (returned.pending !== true)
                return

            var user = returned.user || root.resolveLoginUser()
            if (!user || Object.keys(user).length === 0) {
                console.warn("Game session returned without a valid local user.")
                return
            }

            root.automaticLoginAttempted = true
            root.gameSessionReturnData = returned
            root.gameSessionReturnPending = true
            try {
                if (typeof securityManager !== "undefined" && securityManager)
                    securityManager.setActiveUser(user)
            } catch (securityError) {
                console.warn("Unable to restore the trusted game-session user:", securityError)
            }
            root.beginUnlockToConsole(user)
        }
    }

    Timer {
        id: gameSessionAppLaunchTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (root.shellMode !== "console")
                return
            try {
                var gamesApp = (typeof appManager !== "undefined" && appManager &&
                                typeof appManager.appById === "function")
                               ? appManager.appById("games") : null
                if (gamesApp)
                    root.beginLaunchApp(gamesApp)
            } catch (error) {
                console.warn("Unable to reopen Games after the external session:", error)
            }
        }
    }

    Timer {
        id: automaticLoginStartupTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (root.automaticLoginAttempted || root.shellMode !== "lock")
                return
            root.automaticLoginAttempted = true

            var enabled = false
            try {
                enabled = typeof settingsManager !== "undefined" && settingsManager &&
                          settingsManager.value("user.autoLogin", false) === true
            } catch (settingsError) {
                console.warn("Automatic Login setting could not be read:", settingsError)
            }
            if (!enabled)
                return

            var user = root.resolveLoginUser()
            if (!user || Object.keys(user).length === 0) {
                console.warn("Automatic Login was enabled but no local user could be resolved.")
                return
            }

            try {
                if (typeof securityManager !== "undefined" && securityManager)
                    securityManager.setActiveUser(user)
            } catch (securityError) {
                console.warn("Automatic Login could not initialize the security profile:", securityError)
            }

            console.log("Main.qml: Automatic Login entering Console for", String(user.username || user.name || "local user"))
            root.beginUnlockToConsole(user)
        }
    }

    Component.onCompleted: {
        root.shellMode = "lock"
        root.inputLocked = false
        root.authenticated = false
        if (typeof securityCoreManager !== "undefined" && securityCoreManager)
            securityCoreManager.setShellSessionAuthenticated(false)

        root.lockOpacity = 1.0
        root.consoleOpacity = 0.0
        root.appOpacity = 0.0

        root.logoutModalOpen = false
        root.logoutModalRequested = false
        root.developerModalRequested = false
        root.screensaverOpacity = 0.0
        root.screensaverWakePending = false
        root.l1Down = false
        root.r1Down = false
        root.l1Forwarded = false
        root.r1Forwarded = false
        root.shoulderChordTriggered = false
        root.emergencyHomeDown = false
        root.emergencyChordActive = false
        root.emergencyChordConsumed = false
        root.emergencyChordTriggered = false
        root.markUserActivity()

        root.pendingAppData = null
        root.appLaunchSubmitted = false
        root.consoleReady = false
        root.unlockRevealPending = false
        root.consoleLoadError = ""
        root.consolePreloadRequested = false

        root.unlockState = "LOCKED"
        root.unlockPulseComplete = false
        root.fractureSequenceStarted = false
        root.unlockFailureReason = ""

        keyboardFallback.forceActiveFocus()

        /*
            Fallback for unusual startup ordering where lockLoader was already
            ready before its onLoaded handler could start the timer.
        */
        consolePreloadTimer.restart()
        appHostSessionReturnTimer.restart()
        gameSessionReturnTimer.restart()
        automaticLoginStartupTimer.restart()
    }

    /* Browser runs on an isolated VT.  Its signed one-shot return token keeps
       this opaque frame above LoginScreen until the authenticated Console has
       rendered, preventing the lock surface from flashing during restoration. */
    Item {
        anchors.fill: parent
        z: 9999
        visible: root.appHostReturnCoverVisible
        enabled: false
        Image {
            anchors.fill: parent
            source: "../themes/Default/screensavers/Nebula.png"
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            cache: true
        }
        Rectangle { anchors.fill: parent; color: "#7200030C" }
        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * .14
            height: width
            sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
            source: (typeof assetManager !== "undefined" && assetManager)
                    ? assetManager.logo() : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: false
            cache: true
        }
    }

    function launchSecurityAppNow() {
        if (root.shellMode !== "console" ||
            typeof appManager === "undefined" ||
            !appManager)
            return false

        var securityApp = null
        if (typeof appManager.appById === "function") {
            try { securityApp = appManager.appById("security") }
            catch (error) { securityApp = null }
        }

        if (!securityApp || !String(securityApp.id || "").length) {
            var apps = appManager.apps || []
            for (var i = 0; i < apps.length; ++i) {
                if (String(apps[i].id || "") === "security") {
                    securityApp = apps[i]
                    break
                }
            }
        }

        if (!securityApp)
            return false

        root.beginLaunchApp(securityApp)
        return true
    }

    function requestSecurityAppFromGlobalIncident(incident) {
        root.pendingSecurityIncident = incident || ({})

        if (root.shellMode === "app" || root.shellMode === "launchingApp") {
            root.pendingSecurityAppLaunch = true
            if (appHostLoader.item &&
                typeof appHostLoader.item.closeAppSilently === "function")
                appHostLoader.item.closeAppSilently()
            root.beginReturnToConsole()
            return
        }

        if (root.shellMode === "console") {
            root.pendingSecurityAppLaunch = false
            root.pendingSecurityIncident = null
            Qt.callLater(function() { root.launchSecurityAppNow() })
        }
    }

    Item {
        anchors.fill: parent
        z: 2000000
        visible: root.powerTransitionVisible
        enabled: visible

        Rectangle {
            anchors.fill: parent
            color: "black"
        }

        Image {
            anchors.fill: parent
            source: root.powerTransitionVisible && root.powerTransitionKind.length > 0
                    ? "image://neutron-boot/" + root.powerTransitionKind
                    : ""
            sourceSize: Qt.size(Math.max(1, Math.round(root.width)),
                                Math.max(1, Math.round(root.height)))
            fillMode: Image.Stretch
            asynchronous: false
            cache: false
            smooth: true
            mipmap: false
        }
    }

    GlobalSecurityEventModal {
        id: globalSecurityModal
        anchors.fill: parent
        securityBackend: (typeof securityCoreManager !== "undefined")
                         ? securityCoreManager : null

        onOpenSecurityRequested: function(incident) {
            root.requestSecurityAppFromGlobalIncident(incident)
        }

        onAuditRequested: function(incident) {
            if (typeof securityCoreManager !== "undefined" && securityCoreManager) {
                securityCoreManager.verifyIntegrity()
                securityCoreManager.requestSnapshot()
            }
        }

        onLockdownRequested: function(incident) {
            if (typeof securityCoreManager !== "undefined" && securityCoreManager) {
                securityCoreManager.setManualThreatLevel(1)
                securityCoreManager.requestSnapshot()
            }
        }

        onApproveRequested: function(incident) {
            if (typeof securityCoreManager !== "undefined" && securityCoreManager) {
                var eventId = String(
                    incident.eventId || incident.id || incident.eventID || ""
                )
                if (eventId.length)
                    securityCoreManager.acknowledgeEvent(eventId)
                securityCoreManager.createIntegrityBaseline()
                securityCoreManager.requestSnapshot()
            }
        }
    }

    RunAsSudoModal { anchors.fill: parent }
}
