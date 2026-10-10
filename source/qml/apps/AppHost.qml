import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components" as Components

Item {
    id: root

    anchors.fill: parent
    focus: true
    visible: true
    enabled: true

    /*
        ============================================================
                                PUBLIC API
        ============================================================

        Expected by qml/Main.qml:

            function launch(var appData)
            function launchApp(var appData)
            function closeApp()
            function closeActiveApp()
            function handleControllerPressed(action)
            function handleControllerReleased(action)

            signal appExited()
            signal exitRequested()
            signal appLoadFailed(string message)

        Compatibility signals are kept for your current backend/appManager:

            appStarted(appId, appName)
            appClosed(appId, appName)
            appLoadFailedDetailed(appId, appName, source)
            appWarmupRequested(appData)
    */

    property var activeUser: null
    property bool developerModeEnabled: false
    property int lifecycleGeneration: 0

    property bool appRunning: false
    property bool loading: false
    property bool loadFailed: false
    property bool startupAnimationActive: false
    property bool loaderReady: false

    property string activeAppId: ""
    property string activeAppName: ""
    property string activeAppType: ""
    property string activeAppSource: ""
    property string activeAppUrl: ""
    property string activeAppCommand: ""

    property var activeAppData: null

    property bool appHelpPending: false
    property var helpConsumedActions: ({})
    property int appHelpIntroductionNumber: 0

    property string errorTitle: "App Failed To Launch"
    property string errorMessage: ""

    property int launchSerial: 0
    property int pendingLaunchSerial: 0
    property bool exitInProgress: false
    property bool readySignaled: false

    /*
        Keep this short for production shell feel.
        Service-backed apps can use this as warmup time.
    */
    property int launchDelayMs: 1200
    // Patch 60J: prevent a broken app entry point from leaving AppHost on a
    // permanent loading surface. The watchdog returns to the existing opaque
    // failure panel, where O/X/OPTIONS safely returns to Console.
    property int qmlLaunchTimeoutMs: 45000
    property real launchProgress: 0.0

    property url backgroundSource: (typeof assetManager !== "undefined" &&
                                    assetManager &&
                                    typeof assetManager.themeFile === "function")
                                   ? assetManager.themeFile("background.png")
                                   : Qt.resolvedUrl("../../themes/Default/background.png")

    property url atomSource: (typeof assetManager !== "undefined" &&
                              assetManager &&
                              typeof assetManager.themeFile === "function")
                             ? assetManager.themeFile("atom.png")
                             : Qt.resolvedUrl("../../themes/Default/atom.png")

    readonly property bool qmlAppLoaded: qmlAppLoader.status === Loader.Ready &&
                                         qmlAppLoader.item !== null

    // Apps may expose `controllerExclusiveLock: true` when the physical
    // controller must not trigger any AppHost or shell behavior. Jellyfin uses
    // this while the TV is displaying Roku playback.
    readonly property bool controllerExclusiveLock: qmlAppLoaded &&
                                                   qmlAppLoader.item &&
                                                   ("controllerExclusiveLock" in qmlAppLoader.item) &&
                                                   qmlAppLoader.item.controllerExclusiveLock === true

    readonly property bool fallbackRuntimeActive: appRunning &&
                                                     !loadFailed &&
                                                     loaderReady &&
                                                     activeAppType !== "qml"

    signal appExited()
    signal exitRequested()
    signal appBackgrounded(string appId, string appName)
    signal appLoadFailed(string message)
    signal appReady()

    signal appStarted(string appId, string appName)
    signal appClosed(string appId, string appName)
    signal appLoadFailedDetailed(string appId, string appName, string source)
    signal appWarmupRequested(var appData)

    /*
        ============================================================
                            DATA HELPERS
        ============================================================
    */


    function notifyAppReady() {
        if (readySignaled || loadFailed || !appRunning)
            return
        readySignaled = true
        appReady()
    }

    function roleValue(appData, keys, fallbackValue) {
        if (!appData)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            if (appData[key] !== undefined &&
                    appData[key] !== null &&
                    String(appData[key]).length > 0) {
                return appData[key]
            }
        }

        return fallbackValue
    }

    function boolLike(value) {
        if (value === true)
            return true

        if (value === false)
            return false

        var text = String(value || "").toLowerCase()

        return text === "true" ||
               text === "yes" ||
               text === "1" ||
               text === "running" ||
               text === "started" ||
               text === "active" ||
               text === "online" ||
               text === "ready" ||
               text === "healthy"
    }

    function appIsAlreadyRunning(appData) {
        if (!appData)
            return false

        var directRunning = roleValue(
                    appData,
                    [
                        "running",
                        "isRunning",
                        "serviceRunning",
                        "appRunning",
                        "online",
                        "ready"
                    ],
                    null
                )

        if (directRunning !== null)
            return boolLike(directRunning)

        var statusValue = roleValue(
                    appData,
                    [
                        "status",
                        "state",
                        "runtimeState",
                        "serviceState"
                    ],
                    ""
                )

        return boolLike(statusValue)
    }

    function cleanSourcePath(source) {
        var text = String(source || "")

        if (text.length <= 0)
            return ""

        /*
            AppHost.qml lives in:
                qml/apps/AppHost.qml

            So:
                qml/apps/terminal/Main.qml -> terminal/Main.qml
                apps/terminal/Main.qml     -> terminal/Main.qml
        */

        if (text.indexOf("qml/apps/") === 0)
            text = text.substring(9)

        if (text.indexOf("apps/") === 0)
            text = text.substring(5)

        return text
    }

    function resolvedAppUrl(source, appId) {
        var cleaned = cleanSourcePath(source)

        if (cleaned.length <= 0 && appId && String(appId).length > 0)
            cleaned = String(appId) + "/Main.qml"

        if (cleaned.length <= 0)
            return ""

        if (cleaned.indexOf("qrc:/") === 0 ||
                cleaned.indexOf("file:/") === 0 ||
                cleaned.indexOf("/") === 0) {
            return cleaned
        }

        return Qt.resolvedUrl(cleaned)
    }

    // APP_STORE_UPDATE_ACTIVATION_V2
    function appStoreRuntimeUrl(url, appId, appData) {
        var text = String(url || "")
        if (text.indexOf("/app-store/payload/qml/apps/") < 0)
            return text

        /*
            QQmlEngine caches components by URL. App Store updates intentionally
            replace Main.qml at the same filesystem path, so using that same URL
            can reopen an older compiled component even after installed.json has
            advanced. Key the component URL to installed version and this launch.
        */
        var installedVersion = ""
        try {
            if (typeof appStoreManager !== "undefined" && appStoreManager &&
                    typeof appStoreManager.installedVersion === "function")
                installedVersion = String(appStoreManager.installedVersion(appId) || "")
        } catch (versionError) {}

        if (installedVersion.length <= 0)
            installedVersion = String(roleValue(appData, ["version"], "") || "")

        var separator = text.indexOf("?") >= 0 ? "&" : "?"
        return text + separator +
                "neutronPkgVersion=" + encodeURIComponent(installedVersion) +
                "&neutronPkgLaunch=" + String(root.launchSerial) +
                "&neutronPkgEpoch=" + String(Date.now())
    }

    function activeUsernameForHelp() {
        if (!root.activeUser)
            return "default"
        return String(root.activeUser.username ||
                      root.activeUser.accountName ||
                      root.activeUser.userId || "default")
    }

    function maybeShowAppHelp() {
        if (!root.appRunning || !root.activeAppData ||
                root.activeAppId.length <= 0)
            return
        var backend = (typeof setupWizardManager !== "undefined")
                ? setupWizardManager : null
        if (!backend || typeof backend.registerAppOpen !== "function")
            return
        var result = backend.registerAppOpen(root.activeUsernameForHelp(), root.activeAppId)
        if (result && result.show === true) {
            root.appHelpIntroductionNumber = Number(result.count) || 1
            appHelpOverlay.openAutomatic(root.activeAppData, root.appHelpIntroductionNumber)
        }
    }

    function showAppHelpManual() {
        if (!root.activeAppData)
            return false
        appHelpOverlay.openManual(root.activeAppData)
        return true
    }

    function normalizeAppType(typeValue) {
        var typeText = String(typeValue || "qml").toLowerCase()

        if (typeText === "native")
            return "qml"

        if (typeText === "service")
            return "service-web"

        return typeText
    }

    /*
        ============================================================
                            LAUNCH / CLOSE
        ============================================================
    */

    function launch(appData) {
        return launchApp(appData)
    }

    function requestAppSwitch(appData) {
        Qt.callLater(function() { root.launchApp(appData) })
    }

    function launchApp(appData) {
        if (!appData) {
            failLaunch("No app data was provided.")
            return false
        }

        // Preserve explicit one-shot launch context when AppManager refreshes
        // the canonical registry row below. This lets trusted shell surfaces
        // deep-link into an app without weakening the normal metadata refresh.
        var requestedLaunchData = appData
        var appId = String(roleValue(appData, ["id", "appId", "key"], "unknown"))

        // APP_STORE_UPDATE_ACTIVATION_V2:
        // Always ask AppManager for the newest registry row at launch instead of
        // trusting a dashboard/card object that may pre-date an App Store update.
        try {
            if (typeof appManager !== "undefined" && appManager &&
                    typeof appManager.appById === "function") {
                var refreshedAppData = appManager.appById(appId)
                var refreshedId = String(roleValue(
                    refreshedAppData, ["id", "appId", "key"], ""))
                if (refreshedAppData && refreshedId === appId) {
                    var mergedAppData = ({})
                    for (var refreshedKey in refreshedAppData)
                        mergedAppData[refreshedKey] = refreshedAppData[refreshedKey]
                    try {
                        if (requestedLaunchData.preselectPackageId !== undefined)
                            mergedAppData.preselectPackageId = requestedLaunchData.preselectPackageId
                        if (requestedLaunchData.launchContext !== undefined)
                            mergedAppData.launchContext = requestedLaunchData.launchContext
                    } catch (contextError) {}
                    appData = mergedAppData
                }
            }
        } catch (refreshError) {
            console.log("AppHost could not refresh launch metadata:", refreshError)
        }

        var appName = String(roleValue(appData, ["name", "title", "label"], appId))
        var appType = normalizeAppType(roleValue(appData, ["type", "appType"], "qml"))

        var qmlSource = String(roleValue(appData, ["qmlSource", "source", "path", "entry"], ""))
        var webUrl = String(roleValue(appData, ["url", "webUrl", "endpoint"], ""))
        var command = String(roleValue(appData, ["command", "exec", "executable"], ""))

        var alreadyRunning = appIsAlreadyRunning(appData)

        closeAppSilently()
        exitInProgress = false

        launchSerial = launchSerial + 1
        pendingLaunchSerial = launchSerial

        activeAppId = appId
        activeAppName = appName
        activeAppType = appType
        activeAppData = appData
        activeAppUrl = webUrl
        activeAppCommand = command
        activeAppSource = ""

        errorMessage = ""
        loadFailed = false
        appRunning = true
        loading = true
        loaderReady = false
        startupAnimationActive = false
        readySignaled = false
        launchProgress = 0.0

        if (appType === "qml") {
            activeAppSource = root.appStoreRuntimeUrl(
                        String(resolvedAppUrl(qmlSource, appId)),
                        appId,
                        appData)

            if (activeAppSource.length <= 0) {
                failLaunch("Missing QML entry point for " + appName + ".")
                return false
            }
        } else if (appType === "web" || appType === "service-web") {
            if (activeAppUrl.length <= 0) {
                failLaunch("Missing web URL for " + appName + ".")
                return false
            }
        } else if (appType === "isolated") {
            // The isolated runtime is launched below through AppManager. It is
            // represented by AppHost without embedding its rendering engine.
        } else if (appType === "command" || appType === "external") {
            if (activeAppCommand.length <= 0) {
                failLaunch("Missing command for " + appName + ".")
                return false
            }
        } else {
            failLaunch("Unsupported app type: " + appType)
            return false
        }

        forceActiveFocus()

        console.log("AppHost launching:", activeAppName, activeAppType)

        appStarted(activeAppId, activeAppName)
        try {
            if (typeof appManager !== "undefined" && appManager &&
                    typeof appManager.appLaunched === "function")
                appManager.appLaunched(activeAppId)
        } catch (launchStatusError) {}

        if (appType === "isolated") {
            var runtimeStarted = false
            try {
                runtimeStarted = typeof appManager !== "undefined" && appManager &&
                        typeof appManager.launchExternalRuntime === "function" &&
                        appManager.launchExternalRuntime(activeAppData) === true
            } catch (runtimeError) {
                console.warn("Managed external runtime launch failed:", runtimeError)
            }
            if (!runtimeStarted) {
                failLaunch("The isolated runtime for " + appName + " could not be started.")
                return false
            }
        }

        if (alreadyRunning || appType === "qml" || appType === "isolated" ||
                appType === "command" || appType === "external") {
            /*
                QML and command runtimes can show immediately.
                Service-web apps may use the warmup animation if marked not running.
            */
            loadAppNow()
        } else {
            startLaunchAnimation()
        }

        return true
    }

    function startLaunchAnimation() {
        loaderReady = false
        startupAnimationActive = true
        loading = true

        launchProgressAnimation.stop()
        launchProgress = 0.0
        launchProgressAnimation.start()

        appWarmupRequested(activeAppData)

        launchDelayTimer.restart()
    }

    function loadAppNow() {
        startupAnimationActive = false
        loading = true
        loaderReady = true

        launchDelayTimer.stop()
        if (activeAppType === "qml")
            qmlLaunchWatchdog.restart()
        else
            qmlLaunchWatchdog.stop()
        launchProgressAnimation.stop()
        launchProgress = 1.0

        forceActiveFocus()

        if (activeAppType !== "qml") {
            loading = false
            Qt.callLater(root.notifyAppReady)
            Qt.callLater(root.maybeShowAppHelp) // Patch 64 fallback
        }
    }

    function failLaunch(message) {
        qmlLaunchWatchdog.stop()
        loading = false
        startupAnimationActive = false
        loaderReady = false
        loadFailed = true
        appRunning = true

        errorMessage = message || "The selected app could not be launched."

        try {
            if (typeof appManager !== "undefined" && appManager &&
                    typeof appManager.appClosed === "function")
                appManager.appClosed(activeAppId)
        } catch (failedRuntimeCleanupError) {}

        console.log("AppHost launch failed:", errorMessage)

        appLoadFailed(errorMessage)
        appLoadFailedDetailed(activeAppId, activeAppName, activeAppSource)

        forceActiveFocus()
    }

    function closeApp() {
        if (exitInProgress)
            return

        if (!appRunning && !loading && !startupAnimationActive && !loadFailed)
            return

        exitInProgress = true

        var closedId = activeAppId
        var closedName = activeAppName

        if (qmlAppLoader.item &&
                typeof qmlAppLoader.item.onAppClosing === "function") {
            qmlAppLoader.item.onAppClosing()
        }

        closeAppSilently()

        try {
            if (typeof appManager !== "undefined" && appManager &&
                    typeof appManager.appClosed === "function")
                appManager.appClosed(closedId)
        } catch (closeStatusError) {}

        appClosed(closedId, closedName)

        /*
            Main.qml listens for this and unloads AppHost, then reloads Console.
        */
        appExited()
    }

    function backgroundApp() {
        if (exitInProgress)
            return
        if (!appRunning && !loading && !startupAnimationActive && !loadFailed)
            return

        exitInProgress = true
        var closedId = activeAppId
        var closedName = activeAppName

        try {
            if (qmlAppLoader.item &&
                    typeof qmlAppLoader.item.onAppBackgrounding === "function")
                qmlAppLoader.item.onAppBackgrounding()
        } catch (backgroundHookError) {}

        closeAppSilently()

        try {
            if (typeof appManager !== "undefined" && appManager &&
                    typeof appManager.appBackgrounded === "function")
                appManager.appBackgrounded(closedId)
        } catch (backgroundStatusError) {}

        appBackgrounded(closedId, closedName)
        appExited()
    }

    function closeActiveApp() {
        closeApp()
    }

    function requestExit() {
        /*
            App-requested exit has one canonical completion signal. Emitting
            exitRequested and appExited for the same close caused duplicate
            return-to-Console requests in a single event-loop turn.
        */
        closeApp()
    }

    function requestBackground() {
        backgroundApp()
    }


    function prepareForLogout() {
        exitInProgress = true

        try {
            if (qmlAppLoader.item && typeof qmlAppLoader.item.onAppClosing === "function")
                qmlAppLoader.item.onAppClosing()
        } catch (error) {}

        closeAppSilently()
        activeUser = null
    }

    function closeAppSilently() {
        try {
            if (typeof securityManager !== "undefined" && securityManager &&
                    typeof securityManager.clearHighPriorityAuthorization === "function")
                securityManager.clearHighPriorityAuthorization()
        } catch (securityError) {}

        launchSerial = launchSerial + 1
        pendingLaunchSerial = launchSerial
        launchDelayTimer.stop()
        qmlLaunchWatchdog.stop()
        launchProgressAnimation.stop()

        /*
            Loader.source is declaratively bound below. Assigning it here
            destroys that binding permanently, which leaves every later QML
            app on the "Loading Runtime / Console unloaded" screen.
            Clearing loaderReady and activeAppSource unloads the Loader
            without breaking its binding.
        */
        startupAnimationActive = false
        loaderReady = false
        appRunning = false
        loading = false
        loadFailed = false
        readySignaled = false

        activeAppSource = ""
        activeAppUrl = ""
        activeAppCommand = ""
        activeAppType = ""
        activeAppId = ""
        activeAppName = ""
        activeAppData = null
        root.appHelpPending = false
        root.appHelpIntroductionNumber = 0
        if (appHelpOverlay.visible)
            appHelpOverlay.close()

        errorMessage = ""
        launchProgress = 0.0
    }

    /*
        ============================================================
                            CONTROLLER ROUTING
        ============================================================
    */

    function normalizeControllerAction(button) {
        var b = String(button || "").toLowerCase()

        if (b === "primary" || b === "cross" || b === "x" || b === "ps_cross")
            return "primary"

        if (b === "cancel" || b === "circle" || b === "o" || b === "ps_circle")
            return "cancel"

        if (b === "context" || b === "triangle" || b === "ps_triangle")
            return "context"

        if (b === "secondary" || b === "square" || b === "ps_square")
            return "secondary"

        if (b === "system" || b === "options" || b === "settings" || b === "start" || b === "menu")
            return "system"

        if (b === "quick" || b === "share" || b === "create" || b === "select")
            return "quick"

        if (b === "home" || b === "ps" || b === "playstation" || b === "guide")
            return "home"

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

    function controllerActionToAppButton(action) {
        return action
    }

    function handleController(button) {
        return handleControllerPressed(button)
    }

    function handleControllerPressed(button) {
        var action = normalizeControllerAction(button)

        if (action.length <= 0)
            return true

        if (appHelpOverlay.visible) {
            helpConsumedActions[action] = true
            appHelpOverlay.handleControllerPressed(action)
            return true
        }

        // Exclusive app ownership follows onboarding and precedes quick actions,
        // startup cancellation, fallback behavior, or AppHost exit handling.
        if (root.controllerExclusiveLock) {
            if (qmlAppLoader.item &&
                    typeof qmlAppLoader.item.handleControllerPressed === "function") {
                qmlAppLoader.item.handleControllerPressed(controllerActionToAppButton(action))
            } else if (qmlAppLoader.item &&
                       typeof qmlAppLoader.item.handleController === "function") {
                qmlAppLoader.item.handleController(controllerActionToAppButton(action))
            }
            return true
        }

        if (action === "quick" && root.appRunning && !root.loadFailed) {
            root.showAppHelpManual()
            return true
        }

        if (startupAnimationActive) {
            if (action === "home") {
                /*
                    PS/Home is owned globally by Main.qml so the 3-second
                    power menu can open over every screen.
                */
                return true
            }

            if (action === "cancel" ||
                    action === "system") {
                closeApp()
                return true
            }

            return true
        }

        if (loadFailed) {
            if (action === "home") {
                /*
                    PS/Home is reserved for the global 3-second power menu.
                */
                return true
            }

            if (action === "cancel" ||
                    action === "system" ||
                    action === "primary") {
                closeApp()
                return true
            }

            return true
        }

        if (fallbackRuntimeActive) {
            return handleFallbackRuntimeController(action)
        }

        if (qmlAppLoader.item) {
            var appButton = controllerActionToAppButton(action)

            if (typeof qmlAppLoader.item.handleControllerPressed === "function") {
                qmlAppLoader.item.handleControllerPressed(appButton)
                return true
            }

            if (typeof qmlAppLoader.item.handleController === "function") {
                qmlAppLoader.item.handleController(appButton)
                return true
            }
        }

        if (action === "home") {
            /*
                PS/Home is reserved for Main.qml's global hold modal.
                AppHost must not exit on short Home press.
            */
            return true
        }

        if (action === "cancel" ||
                action === "system") {
            closeApp()
            return true
        }

        return true
    }

    function handleStickMoved(stick, x, y) {
        if (appHelpOverlay.visible) return true
        if (root.controllerExclusiveLock)
            return true

        if (qmlAppLoader.item &&
                typeof qmlAppLoader.item.handleStickMoved === "function") {
            qmlAppLoader.item.handleStickMoved(stick, x, y)
            return true
        }

        return false
    }

    function handleControllerReleased(button) {
        var action = normalizeControllerAction(button)
        if (helpConsumedActions[action]) { delete helpConsumedActions[action]; return true }
        if (appHelpOverlay.visible) return true

        if (action.length <= 0)
            return true

        if (root.controllerExclusiveLock) {
            if (qmlAppLoader.item &&
                    typeof qmlAppLoader.item.handleControllerReleased === "function") {
                qmlAppLoader.item.handleControllerReleased(controllerActionToAppButton(action))
            }
            return true
        }

        if (qmlAppLoader.item &&
                typeof qmlAppLoader.item.handleControllerReleased === "function") {
            qmlAppLoader.item.handleControllerReleased(controllerActionToAppButton(action))
            return true
        }

        return true
    }

    function handleFallbackRuntimeController(action) {
        if (action === "home") {
            /*
                PS/Home is reserved for Main.qml's global hold modal.
                AppHost must not exit on short Home press.
            */
            return true
        }

        if (action === "cancel" ||
                action === "system") {
            closeApp()
            return true
        }

        if (action === "primary") {
            /*
                The fallback runtime surface is already active. Primary is
                intentionally consumed here so the controller focus remains
                inside the app runtime until O/OPTIONS exits or Main.qml opens
                the global PS/Home menu.
            */
            return true
        }

        return true
    }

    /*
        ============================================================
                                QML APP LOADER
        ============================================================
    */

    Loader {
        id: qmlAppLoader
        objectName: "AppHostQmlLoader"

        anchors.fill: parent

        active: root.appRunning &&
                root.loaderReady &&
                root.activeAppType === "qml" &&
                root.activeAppSource.length > 0

        source: root.appRunning &&
                root.loaderReady &&
                root.activeAppType === "qml"
                ? root.activeAppSource
                : ""
        asynchronous: true
        visible: active && status === Loader.Ready

        onLoaded: {
            qmlLaunchWatchdog.stop()
            root.loading = false
            root.loadFailed = false
            root.startupAnimationActive = false

            if (!item)
                return

            if ("appId" in item)
                item.appId = root.activeAppId

            if ("appName" in item)
                item.appName = root.activeAppName

            if ("appData" in item)
                item.appData = root.activeAppData

            if ("activeUser" in item)
                item.activeUser = root.activeUser

            if ("developerModeEnabled" in item)
                item.developerModeEnabled = root.developerModeEnabled

            if ("hostActive" in item)
                item.hostActive = true

            if ("shellMode" in item)
                item.shellMode = "app"

            /*
                Native app contract:
                    signal exitRequested()
            */
            try {
                if (item.exitRequested !== undefined)
                    item.exitRequested.connect(root.requestExit)
            } catch (e) {
                console.log("AppHost could not connect app exitRequested signal:", e)
            }

            try {
                if (item.backgroundRequested !== undefined)
                    item.backgroundRequested.connect(root.requestBackground)
            } catch (backgroundSignalError) {
                console.log("AppHost could not connect app backgroundRequested signal:", backgroundSignalError)
            }

            try {
                if (item.appExited !== undefined)
                    item.appExited.connect(root.requestExit)
            } catch (e2) {
                console.log("AppHost could not connect app appExited signal:", e2)
            }

            try {
                if (item.launchAppRequested !== undefined)
                    item.launchAppRequested.connect(root.requestAppSwitch)
            } catch (e3) {
                console.log("AppHost could not connect app launchAppRequested signal:", e3)
            }

            if (typeof item.onAppLaunched === "function")
                item.onAppLaunched(root.activeAppData)

            item.forceActiveFocus()

            root.notifyAppReady()
            Qt.callLater(root.maybeShowAppHelp)

            console.log("AppHost loaded QML app:", root.activeAppName)
        }

        onStatusChanged: {
            if (status === Loader.Loading) {
                root.loading = true
                root.loadFailed = false
            }

            if (status === Loader.Ready) {
                qmlLaunchWatchdog.stop()
                root.loading = false
                root.loadFailed = false
                root.startupAnimationActive = false

                if (item)
                    item.forceActiveFocus()
            }

            if (status === Loader.Error) {
                qmlLaunchWatchdog.stop()
                root.loading = false
                root.startupAnimationActive = false
                root.loaderReady = false
                root.loadFailed = true
                root.appRunning = true

                root.errorMessage =
                        "Could not load " +
                        root.activeAppName +
                        " from " +
                        root.activeAppSource

                console.log("AppHost loader error:", root.errorMessage)

                root.appLoadFailed(root.errorMessage)
                root.appLoadFailedDetailed(
                            root.activeAppId,
                            root.activeAppName,
                            root.activeAppSource
                        )

                root.forceActiveFocus()
            }
        }
    }

    /*
        ============================================================
                    FALLBACK RUNTIME FOR NON-QML APPS
        ============================================================

        This is a deliberate safe runtime surface for non-QML apps.
        It keeps the console suspended, shows the selected app runtime target,
        and gives the user controller-safe return controls while the backend
        starts or attaches the real service/runtime.

        Runtime targets:
            web/service-web -> controlled web/service endpoint
            command         -> controlled command target
            external        -> controlled external target
    */

    Item {
        id: fallbackRuntime

        anchors.fill: parent
        visible: root.fallbackRuntimeActive

        Rectangle {
            anchors.fill: parent
            color: "#02060D"
        }

        Image {
            anchors.fill: parent
            source: root.backgroundSource
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: false
            asynchronous: true
            opacity: 0.60
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.58
        }

        Rectangle {
            anchors.centerIn: parent

            width: 900
            height: 460
            radius: 42

            color: "#071426e8"
            border.width: 1
            border.color: "#47c8ff99"
            clip: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "#ffffff"
                opacity: 0.045
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#ffffff"
                opacity: 0.24
            }

            Column {
                anchors.fill: parent
                anchors.margins: 42
                spacing: 22

                Text {
                    width: parent.width

                    text: root.activeAppType === "web" || root.activeAppType === "service-web"
                          ? "WEB RUNTIME"
                          : (root.activeAppType === "command"
                             ? "COMMAND RUNTIME"
                             : "EXTERNAL RUNTIME")

                    color: "#7df9ff"
                    font.pixelSize: 16
                    font.bold: true
                    font.letterSpacing: 3
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width

                    text: root.activeAppName.length > 0 ? root.activeAppName : "Application"

                    color: "white"
                    font.pixelSize: 42
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 150
                    radius: 26

                    color: "#091529cc"
                    border.width: 1
                    border.color: "#335577"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 12

                        Text {
                            width: parent.width

                            text: root.activeAppType === "web" || root.activeAppType === "service-web"
                                  ? root.activeAppUrl
                                  : root.activeAppCommand

                            color: "#cfffff"
                            font.pixelSize: 20
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width

                            text: root.activeAppType === "web" || root.activeAppType === "service-web"
                                  ? "Web wrapper will attach here. Console is unloaded while this runtime is active."
                                  : "Terminal/external runtime will attach here. Console is unloaded while this runtime is active."

                            color: "#9fd8ff"
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 42

                    Text {
                        text: "O  Return"
                        color: "#ffb3b3"
                        font.pixelSize: 16
                        font.bold: true
                        font.letterSpacing: 1.4
                    }

                    Text {
                        text: "OPTIONS  Exit"
                        color: "#9fd8ff"
                        font.pixelSize: 16
                        font.bold: true
                        font.letterSpacing: 1.4
                    }
                }
            }
        }
    }

    /*
        ============================================================
                            STARTUP DELAY
        ============================================================
    */

    Timer {
        id: qmlLaunchWatchdog
        interval: root.qmlLaunchTimeoutMs
        repeat: false

        onTriggered: {
            if (!root.appRunning || root.activeAppType !== "qml")
                return
            if (!root.loading || qmlAppLoader.status === Loader.Ready)
                return

            root.failLaunch(
                "Timed out while loading " +
                (root.activeAppName.length > 0 ? root.activeAppName : "application") +
                ". Entry point: " + root.activeAppSource
            )
        }
    }

    Timer {
        id: launchDelayTimer

        interval: root.launchDelayMs
        repeat: false

        onTriggered: {
            if (!root.appRunning)
                return

            if (root.pendingLaunchSerial !== root.launchSerial)
                return

            root.loadAppNow()
        }
    }

    NumberAnimation {
        id: launchProgressAnimation

        target: root
        property: "launchProgress"

        from: 0.0
        to: 1.0

        duration: root.launchDelayMs
        easing.type: Easing.InOutCubic
    }

    /*
        ============================================================
                            LAUNCH ANIMATION
        ============================================================
    */

    Item {
        id: bootScreen

        anchors.fill: parent

        visible: root.startupAnimationActive

        Rectangle {
            anchors.fill: parent
            color: "#02060D"
        }

        Image {
            id: bootBackground

            anchors.fill: parent

            source: root.backgroundSource
            fillMode: Image.PreserveAspectCrop

            smooth: true
            cache: false
            asynchronous: true

            opacity: 0.92
            scale: 1.0

            SequentialAnimation on scale {
                running: root.startupAnimationActive
                loops: Animation.Infinite

                NumberAnimation {
                    from: 1.0
                    to: 1.035
                    duration: 42000
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    from: 1.035
                    to: 1.0
                    duration: 42000
                    easing.type: Easing.InOutSine
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.36
        }

        Rectangle {
            anchors.centerIn: parent

            width: 780
            height: 560
            radius: 42

            color: "#071426cc"
            border.width: 1
            border.color: "#337DF9FF"
            clip: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "#FFFFFF"
                opacity: 0.045
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#FFFFFF"
                opacity: 0.24
            }

            Rectangle {
                id: atomGlow

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 58

                width: 280
                height: 280
                radius: 140

                color: "#7DF9FF"
                opacity: 0.08
            }

            SequentialAnimation {
                running: root.startupAnimationActive
                loops: Animation.Infinite

                NumberAnimation {
                    target: atomGlow
                    property: "opacity"
                    from: 0.045
                    to: 0.145
                    duration: 980
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    target: atomGlow
                    property: "opacity"
                    from: 0.145
                    to: 0.045
                    duration: 980
                    easing.type: Easing.InOutQuad
                }
            }

            Image {
                id: launchAtom

                width: 246
                height: 246

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 74

                source: root.atomSource
                fillMode: Image.PreserveAspectFit

                smooth: true
                cache: false
                asynchronous: true

                rotation: 0
                scale: 1.0
                opacity: 0.95

                RotationAnimation on rotation {
                    running: root.startupAnimationActive
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 6800
                }

                SequentialAnimation on scale {
                    running: root.startupAnimationActive
                    loops: Animation.Infinite

                    NumberAnimation {
                        from: 1.0
                        to: 1.05
                        duration: 1200
                        easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                        from: 1.05
                        to: 1.0
                        duration: 1200
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: launchAtom.bottom
                anchors.topMargin: 26

                spacing: 12

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "LAUNCHING"
                    color: "#7DF9FF"
                    font.pixelSize: 16
                    font.bold: true
                    font.letterSpacing: 3
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 660

                    text: root.activeAppName.length > 0
                          ? root.activeAppName
                          : "Application"

                    color: "white"
                    font.pixelSize: 38
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: root.activeAppType === "service-web"
                          ? "Starting service · Preparing web runtime"
                          : "Preparing fullscreen runtime"

                    color: "#9FD8FF"
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            Rectangle {
                id: progressTrack

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 64

                width: 560
                height: 14
                radius: 7

                color: "#091529"
                border.width: 1
                border.color: "#335577"

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    width: parent.width * root.launchProgress
                    radius: parent.radius

                    color: "#7DF9FF"
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: progressTrack.bottom
                anchors.topMargin: 18

                spacing: 34

                Text {
                    text: "Console Unloaded"
                    color: "#CFFFFF"
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.6
                }

                Text {
                    text: Math.round(root.launchProgress * 100) + "%"
                    color: "#7DF9FF"
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.6
                }

                Text {
                    text: "O  Cancel"
                    color: "#FF9A9A"
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.6
                }
            }
        }
    }

    /*
        ============================================================
                            LOADING SCREEN
        ============================================================
    */

    Item {
        anchors.fill: parent

        visible: root.loading &&
                 !root.startupAnimationActive &&
                 !root.loadFailed &&
                 !root.qmlAppLoaded &&
                 !root.fallbackRuntimeActive

        Rectangle {
            anchors.fill: parent
            color: "#02060D"
        }

        Image {
            anchors.fill: parent

            source: root.backgroundSource
            fillMode: Image.PreserveAspectCrop

            smooth: true
            cache: false
            asynchronous: true

            opacity: 0.88
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.42
        }

        Rectangle {
            anchors.centerIn: parent

            width: 520
            height: 260
            radius: 34

            color: "#071426dd"
            border.width: 1
            border.color: "#4DA6FF88"
            clip: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "#FFFFFF"
                opacity: 0.05
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#FFFFFF"
                opacity: 0.24
            }

            Column {
                anchors.centerIn: parent
                spacing: 16

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Hmm Something is taking a while"
                    color: "#7DF9FF"
                    font.pixelSize: 16
                    font.bold: true
                    font.letterSpacing: 2.2
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 460
                    text: root.activeAppName
                    color: "white"
                    font.pixelSize: 30
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Filesystem must be busy"
                    color: "#9FD8FF"
                    font.pixelSize: 15
                    font.bold: true
                }
            }
        }
    }

    /*
        ============================================================
                            ERROR SCREEN
        ============================================================
    */

    Item {
        anchors.fill: parent
        visible: root.loadFailed

        Rectangle {
            anchors.fill: parent
            color: "#02060D"
        }

        Image {
            anchors.fill: parent
            source: root.backgroundSource
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: false
            asynchronous: true
            opacity: 0.52
        }

        Rectangle {
            anchors.fill: parent
            color: "#02060D"
            opacity: 0.78
        }

        Rectangle {
            anchors.centerIn: parent

            width: 780
            height: 360
            radius: 34

            color: "#16070Bee"
            border.width: 2
            border.color: "#FF3040"
            clip: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "#FFFFFF"
                opacity: 0.045
            }

            Column {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 22

                Row {
                    width: parent.width
                    height: 78
                    spacing: 20

                    Rectangle {
                        width: 70
                        height: 70
                        radius: 22

                        color: "#3A1116DD"
                        border.width: 2
                        border.color: "#FF3040"

                        Text {
                            anchors.centerIn: parent
                            text: "!"
                            color: "#FF9A9A"
                            font.pixelSize: 40
                            font.bold: true
                        }
                    }

                    Column {
                        width: parent.width - 96
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Text {
                            width: parent.width
                            text: root.errorTitle
                            color: "white"
                            font.pixelSize: 32
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.activeAppName
                            color: "#FFB3B3"
                            font.pixelSize: 18
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 118
                    radius: 26

                    color: "#090F1FCC"
                    border.width: 1
                    border.color: "#FF304077"

                    Text {
                        anchors.fill: parent
                        anchors.margins: 22

                        text: root.errorMessage

                        color: "#FFD1D1"
                        font.pixelSize: 17
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 58
                    radius: 20

                    color: "#071426DD"
                    border.width: 1
                    border.color: "#335577"

                    Row {
                        anchors.centerIn: parent
                        spacing: 38

                        Text {
                            text: "O  Close"
                            color: "#7DF9FF"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Text {
                            text: "OPTIONS  Return To Console"
                            color: "#9FD8FF"
                            font.pixelSize: 15
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================

        Main.qml already has the global keyboard/web/controller router.
        This local fallback keeps AppHost usable if focus lands here directly.
    */

    Components.AppHelpOverlay {
        id: appHelpOverlay
        objectName: "AppHostHelpOverlay"
        anchors.fill: parent
        onClosed: root.forceActiveFocus()
    }

    Keys.onPressed: function(event) {
        if (event.isAutoRepeat)
            return

        if (event.key === Qt.Key_Up ||
                event.key === Qt.Key_W) {
            root.handleControllerPressed("up")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Down ||
                event.key === Qt.Key_S) {
            root.handleControllerPressed("down")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Left ||
                event.key === Qt.Key_A) {
            root.handleControllerPressed("left")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Right ||
                event.key === Qt.Key_D) {
            root.handleControllerPressed("right")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Return ||
                event.key === Qt.Key_Enter ||
                event.key === Qt.Key_Space) {
            root.handleControllerPressed("primary")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Escape ||
                event.key === Qt.Key_Backspace) {
            root.handleControllerPressed("cancel")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Menu ||
                event.key === Qt.Key_Tab) {
            root.handleControllerPressed("system")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_F1) {
            root.handleControllerPressed("context")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_F2) {
            root.handleControllerPressed("secondary")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_F3) {
            root.handleControllerPressed("quick")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Home ||
                event.key === Qt.Key_F12) {
            root.handleControllerPressed("home")
            event.accepted = true
            return
        }
    }

    Component.onDestruction: root.prepareForLogout()

    Component.onCompleted: {
        forceActiveFocus()
    }
}
