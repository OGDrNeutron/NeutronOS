import QtQuick 2.15

Item {
    id: root

    property var appData: null
    property var activeUser: null

    property var appBackend:
        (typeof appManager !== "undefined" && appManager)
        ? appManager
        : ((typeof appLauncher !== "undefined" && appLauncher)
           ? appLauncher
           : null)

    property var securityBackend:
        (typeof securityManager !== "undefined" && securityManager)
        ? securityManager
        : null

    property var appStoreBackend:
        (typeof appStoreManager !== "undefined" && appStoreManager)
        ? appStoreManager
        : null

    property int selectedIndex: 0
    property int armedIndex: -1
    property string mode: "menu"
    property string statusText: "Choose an app action"
    property var comboTokens: []
    property bool verificationPending: false
    property int verificationSession: 0
    property string pendingUninstallId: ""

    readonly property color neutronBlue: "#7df9ff"
    readonly property color focusBlue: "#4da6ff"
    readonly property color dangerRed: "#ff3040"
    readonly property color successGreen: "#22ff88"
    readonly property color panelColor: "#07101f"
    readonly property color rowColor: "#0d1a2d"

    signal closed()
    signal openRequested(var appData)
    signal restartRequested(var appData)
    signal killRequested(var appData)
    signal favoriteChanged(string appId)
    signal appUninstalled(string appId)

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 1260

    Rectangle {
        anchors.fill: parent
        color: "#02040cc8"
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: Math.min(parent.width * 0.70, 1040)
        height: Math.min(parent.height * 0.78, 820)
        radius: 34
        color: root.panelColor
        border.width: 2
        border.color:
            root.mode === "auth" || root.mode === "verifying"
            ? root.dangerRed
            : root.neutronBlue
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 34
            spacing: 18

            Text {
                width: parent.width
                text: root.appName()
                color: "#ffffff"
                font.pixelSize: 34
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text:
                    root.mode === "auth"
                    ? "ENTER LOGIN COMBO"
                    : (root.mode === "verifying"
                       ? "VERIFYING LOGIN COMBO"
                       : (root.mode === "uninstalling"
                          ? "UNINSTALLING APP"
                          : "APP CONTROLS"))
                color:
                    root.mode === "menu"
                    ? root.neutronBlue
                    : root.dangerRed
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 2
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.statusText
                color: "#a8c9e8"
                font.pixelSize: 15
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#31516d"
            }

            Item {
                width: parent.width
                height: parent.height - 180

                Column {
                    anchors.fill: parent
                    spacing: 10
                    visible: root.mode === "menu"

                    Repeater {
                        model: root.actionItems()

                        delegate: Rectangle {
                            required property int index
                            required property var modelData

                            width: parent.width
                            height: 72
                            radius: 24
                            color:
                                index === root.selectedIndex
                                ? (root.armedIndex === index
                                   ? "#3a1119"
                                   : "#142b42")
                                : root.rowColor
                            border.width: index === root.selectedIndex ? 3 : 1
                            border.color:
                                root.armedIndex === index
                                ? root.dangerRed
                                : (index === root.selectedIndex
                                   ? root.focusBlue
                                   : "#29445f")

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 24
                                anchors.rightMargin: 24
                                spacing: 20

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 54
                                    height: 54
                                    radius: 18
                                    color:
                                        modelData.danger
                                        ? "#351018"
                                        : "#0b2538"
                                    border.width: 2
                                    border.color:
                                        modelData.danger
                                        ? root.dangerRed
                                        : root.neutronBlue

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.glyph
                                        color:
                                            modelData.danger
                                            ? root.dangerRed
                                            : root.neutronBlue
                                        font.pixelSize: 21
                                        font.bold: true
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 94
                                    spacing: 5

                                    Text {
                                        width: parent.width
                                        text:
                                            root.armedIndex === index
                                            ? "PRESS X AGAIN TO CONFIRM"
                                            : modelData.title
                                        color:
                                            root.armedIndex === index
                                            ? root.dangerRed
                                            : "#ffffff"
                                        font.pixelSize: 21
                                        font.bold: true
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.subtitle
                                        color: "#8fb4d5"
                                        font.pixelSize: 14
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width * 0.82
                    spacing: 22
                    visible: root.mode === "auth" || root.mode === "verifying"

                    Rectangle {
                        width: parent.width
                        height: 128
                        radius: 30
                        color: "#120a13"
                        border.width: 2
                        border.color: root.dangerRed

                        Row {
                            anchors.centerIn: parent
                            spacing: 14

                            Repeater {
                                model: Math.max(1, root.configuredComboLength())

                                delegate: Rectangle {
                                    required property int index
                                    width: 28
                                    height: 54
                                    radius: 10
                                    color:
                                        index < root.comboTokens.length
                                        ? root.dangerRed
                                        : "#f6f7fb"
                                    opacity:
                                        index < root.comboTokens.length
                                        ? 1.0
                                        : 0.52

                                    SequentialAnimation on opacity {
                                        running:
                                            root.visible &&
                                            root.mode === "verifying" &&
                                            index === (root.comboTokens.length - 1)
                                        loops: Animation.Infinite

                                        NumberAnimation {
                                            from: 0.35
                                            to: 1.0
                                            duration: 320
                                        }

                                        NumberAnimation {
                                            from: 1.0
                                            to: 0.35
                                            duration: 320
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text:
                            root.mode === "verifying"
                            ? "Authentication in progress…"
                            : "Enter the same controller sequence used to unlock NeutronOS."
                        color: "#ffffff"
                        font.pixelSize: 18
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        text:
                            root.mode === "auth"
                            ? "Every button press is captured. Keyboard Escape cancels."
                            : "Do not close NeutronOS while verification is running."
                        color: "#8fb4d5"
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    Timer {
        id: verificationQuietTimer
        interval: 170
        repeat: false
        onTriggered: root.beginVerification()
    }

    Timer {
        id: authTimeoutTimer
        interval: 12000
        repeat: false
        onTriggered: {
            if (root.mode === "auth")
                root.cancelAuthentication("Authentication timed out")
        }
    }

    Timer {
        id: closeTimer
        interval: 220
        repeat: false
        onTriggered: root.close()
    }

    Connections {
        target: root.securityBackend
        ignoreUnknownSignals: true

        function onLoginComboVerificationFinished(success,
                                                   message,
                                                   failedAttempts,
                                                   secondsRemaining) {
            if (!root.verificationPending)
                return

            root.verificationPending = false

            if (success) {
                root.statusText = "Login combo accepted"
                root.performUninstall()
                return
            }

            root.mode = "auth"
            root.comboTokens = []
            root.statusText =
                Number(secondsRemaining || 0) > 0
                ? "Locked out for " + String(secondsRemaining) + " seconds"
                : (String(message || "").length > 0
                   ? String(message)
                   : "Incorrect login combo. Try again.")
            authTimeoutTimer.restart()
        }
    }

    Connections {
        target: root.appStoreBackend
        ignoreUnknownSignals: true

        function onOperationFinished(packageId, operation, success, message) {
            var id = String(packageId || "")
            if (root.pendingUninstallId.length === 0 ||
                    id !== root.pendingUninstallId ||
                    String(operation || "") !== "uninstall")
                return

            root.pendingUninstallId = ""
            root.comboTokens = []
            root.armedIndex = -1

            if (!success) {
                root.mode = "menu"
                root.statusText = String(message || "App Store uninstall failed")
                return
            }

            root.mode = "menu"
            root.statusText = String(message || "App uninstalled")
            root.appUninstalled(id)
            closeTimer.restart()
        }
    }

    Keys.onPressed: function(event) {
        if (!root.visible)
            return

        if (root.mode === "uninstalling") {
            event.accepted = true
            return
        }

        if (root.mode === "auth" || root.mode === "verifying") {
            if (event.key === Qt.Key_Escape) {
                root.cancelAuthentication("Uninstall cancelled")
                event.accepted = true
                return
            }

            if (root.mode === "auth") {
                var token = root.keyboardToken(event.key)

                if (token.length > 0) {
                    root.captureToken(token)
                    event.accepted = true
                }
            }

            return
        }

        if (event.key === Qt.Key_Up) {
            root.moveSelection(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            root.moveSelection(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Return ||
                   event.key === Qt.Key_Enter ||
                   event.key === Qt.Key_Space) {
            root.activateSelected()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
        }
    }

    function open(app) {
        appData = app || null
        selectedIndex = 0
        armedIndex = -1
        mode = "menu"
        statusText = "Choose an app action"
        comboTokens = []
        verificationPending = false
        pendingUninstallId = ""
        verificationSession++
        visible = true
        forceActiveFocus()
    }

    function close() {
        if (pendingUninstallId.length > 0)
            return

        verificationQuietTimer.stop()
        authTimeoutTimer.stop()

        if (securityBackend &&
                typeof securityBackend.cancelPendingOperation === "function" &&
                verificationPending) {
            try {
                securityBackend.cancelPendingOperation()
            } catch (error) {
            }
        }

        verificationPending = false
        comboTokens = []
        mode = "menu"
        visible = false
        closed()
    }

    function appId() {
        if (!appData)
            return ""

        return String(appData.id || appData.appId || "")
    }

    function appName() {
        if (!appData)
            return "APP"

        return String(appData.name || appData.title || appId() || "APP")
    }

    function isSystemApp() {
        if (!appData)
            return true

        try {
            if (appData.systemOnly === true || appData.uninstallable === false)
                return true
        } catch (error) {
        }

        return String(appData.category || "").trim().toLowerCase() === "system"
    }

    function actionItems() {
        var favorite = false

        try {
            favorite = appData && appData.favorite === true
        } catch (error) {
        }

        var items = [
            { key: "open", title: "Open", subtitle: "Launch this app now", glyph: "X", danger: false },
            { key: "restart", title: "Restart", subtitle: "Restart the service, container, or app session, then open it", glyph: "↻", danger: false },
            { key: "kill", title: "Kill", subtitle: "Force-stop the app, service, or container", glyph: "!", danger: true },
            { key: "favorite", title: favorite ? "Favorite • Move First" : "Favorite", subtitle: "Make this app first in the carousel", glyph: "★", danger: false }
        ]

        if (!isSystemApp()) {
            items.push({
                key: "uninstall",
                title: "Uninstall",
                subtitle: "Remove this app and only its package-owned files",
                glyph: "×",
                danger: true
            })
        }

        items.push({ key: "cancel", title: "Cancel", subtitle: "Return to the app carousel", glyph: "O", danger: false })
        return items
    }

    function moveSelection(delta) {
        var count = actionItems().length
        selectedIndex = (selectedIndex + delta + count) % count
        armedIndex = -1
    }

    function activateSelected() {
        var items = actionItems()
        if (selectedIndex < 0 || selectedIndex >= items.length) {
            selectedIndex = 0
            armedIndex = -1
            return
        }

        var action = String(items[selectedIndex].key || "")

        if (action === "open") {
            openApp()
            return
        }

        if (action === "restart") {
            restartApp()
            return
        }

        if (action === "kill") {
            if (armedIndex !== selectedIndex) {
                armedIndex = selectedIndex
                statusText = "Kill is destructive. Press X again to force-stop the app."
                return
            }

            killApp()
            return
        }

        if (action === "favorite") {
            favoriteApp()
            return
        }

        if (action === "uninstall") {
            if (!canUninstall()) {
                statusText = "This app is protected and cannot be uninstalled"
                armedIndex = -1
                return
            }

            if (armedIndex !== selectedIndex) {
                armedIndex = selectedIndex
                statusText = "Uninstall is destructive. Press X again to authenticate."
                return
            }

            beginUninstallAuthentication()
            return
        }

        close()
    }

    function openApp() {
        if (!appData) {
            statusText = "App data is unavailable"
            return
        }

        var target = appData
        close()
        openRequested(target)
    }

    function restartApp() {
        if (!appBackend || !appData) {
            statusText = "App backend is unavailable"
            return
        }

        var success = false

        try {
            if (typeof appBackend.executeAppAction === "function")
                success = appBackend.executeAppAction(appData, "restart") === true
            else if (typeof appBackend.restartApp === "function") {
                appBackend.restartApp(appData)
                success = true
            }
        } catch (error) {
            statusText = "Restart failed: " + String(error)
            return
        }

        if (!success) {
            statusText = "Restart is not available for this app"
            armedIndex = -1
            return
        }

        var target = appData
        statusText = "Restarted • opening app"
        armedIndex = -1
        close()
        restartRequested(target)
    }

    function killApp() {
        if (!appBackend || !appData) {
            statusText = "App backend is unavailable"
            armedIndex = -1
            return
        }

        var success = false

        try {
            if (typeof appBackend.executeAppAction === "function")
                success = appBackend.executeAppAction(appData, "kill") === true
            else if (typeof appBackend.stopApp === "function") {
                appBackend.stopApp(appData)
                success = true
            } else if (typeof appBackend.closeApp === "function")
                success = appBackend.closeApp(appData) === true
        } catch (error) {
            statusText = "Kill failed: " + String(error)
            armedIndex = -1
            return
        }

        if (!success) {
            statusText = "Kill is not available for this app"
            armedIndex = -1
            return
        }

        var target = appData
        statusText = "App force-stopped"
        armedIndex = -1
        close()
        killRequested(target)
    }

    function favoriteApp() {
        if (!appBackend || appId().length === 0) {
            statusText = "App backend is unavailable"
            return
        }

        var success = false

        try {
            if (typeof appBackend.makeFavoriteFirst === "function")
                success = appBackend.makeFavoriteFirst(appId()) === true
            else if (typeof appBackend.setFavorite === "function")
                success = appBackend.setFavorite(appId(), true) === true
        } catch (error) {
            statusText = "Favorite update failed: " + String(error)
            return
        }

        if (!success) {
            statusText = "Unable to update carousel favorite"
            return
        }

        statusText = "Moved to the first carousel position"
        favoriteChanged(appId())
        closeTimer.restart()
    }

    function canUninstall() {
        if (!appData || isSystemApp())
            return false

        var id = appId()

        try {
            if (appStoreBackend &&
                    typeof appStoreBackend.isInstalled === "function" &&
                    appStoreBackend.isInstalled(id) === true)
                return true
        } catch (storeError) {
        }

        if (!appBackend)
            return false

        try {
            if (typeof appBackend.canUninstallApp === "function")
                return appBackend.canUninstallApp(appData) === true
        } catch (error) {
        }

        return false
    }

    function activeUsername() {
        try {
            if (activeUser) {
                if (activeUser.username)
                    return String(activeUser.username)

                if (activeUser.name)
                    return String(activeUser.name)
            }
        } catch (error) {
        }

        try {
            if (securityBackend && securityBackend.activeUsername)
                return String(securityBackend.activeUsername)
        } catch (securityError) {
        }

        return ""
    }

    function prepareSecurityUser() {
        if (!securityBackend)
            return false

        var username = activeUsername()

        if (username.length === 0)
            return false

        try {
            if (typeof securityBackend.setActiveUsername === "function")
                return securityBackend.setActiveUsername(username) === true
        } catch (error) {
            return false
        }

        return true
    }

    function configuredComboLength() {
        try {
            if (securityBackend && Number(securityBackend.comboLength) > 0)
                return Math.max(1, Number(securityBackend.comboLength))
        } catch (error) {
        }

        return 6
    }

    function beginUninstallAuthentication() {
        if (!prepareSecurityUser()) {
            statusText = "Unable to select the active login account"
            return
        }

        var username = activeUsername()
        var configured = true

        try {
            if (typeof securityBackend.loginComboConfiguredForUser === "function")
                configured = securityBackend.loginComboConfiguredForUser(username) === true
        } catch (error) {
            configured = false
        }

        if (!configured) {
            statusText = "A login combo must be configured before uninstalling apps"
            return
        }

        verificationSession++
        comboTokens = []
        armedIndex = -1
        mode = "auth"
        statusText = "Enter login combo"
        authTimeoutTimer.restart()
        forceActiveFocus()
    }

    function captureToken(token) {
        if (mode !== "auth" || verificationPending)
            return

        var value = String(token || "").trim().toUpperCase()

        if (value.length === 0)
            return

        var next = comboTokens.slice(0)
        next.push(value)

        if (next.length > 15)
            next.shift()

        comboTokens = next
        statusText = "Sequence captured • " + String(comboTokens.length) + "/15"
        authTimeoutTimer.restart()

        if (comboTokens.length >= configuredComboLength())
            verificationQuietTimer.restart()
    }

    function beginVerification() {
        if (mode !== "auth" || verificationPending)
            return

        if (comboTokens.length < configuredComboLength())
            return

        if (!prepareSecurityUser()) {
            statusText = "Unable to prepare login security"
            return
        }

        if (!securityBackend ||
                typeof securityBackend.beginLoginComboVerification !== "function") {
            statusText = "Asynchronous login verification is unavailable"
            return
        }

        try {
            if (securityBackend.operationBusy === true) {
                verificationQuietTimer.restart()
                return
            }
        } catch (busyError) {
        }

        var accepted = false

        try {
            accepted = securityBackend.beginLoginComboVerification(
                activeUsername(),
                comboTokens.join("|")
            ) === true
        } catch (error) {
            statusText = "Unable to start login verification"
            return
        }

        if (!accepted) {
            statusText = "Security backend is busy. Retrying…"
            verificationQuietTimer.restart()
            return
        }

        verificationPending = true
        mode = "verifying"
        statusText = "Verifying login combo"
        authTimeoutTimer.stop()
    }

    function cancelAuthentication(message) {
        verificationQuietTimer.stop()
        authTimeoutTimer.stop()
        comboTokens = []
        verificationPending = false
        mode = "menu"
        armedIndex = -1
        statusText = message || "Choose an app action"
    }

    function performUninstall() {
        if (!appData || isSystemApp()) {
            mode = "menu"
            statusText = "This app is protected and cannot be uninstalled"
            return
        }

        var id = appId()

        try {
            if (appStoreBackend &&
                    typeof appStoreBackend.isInstalled === "function" &&
                    appStoreBackend.isInstalled(id) === true) {
                if (typeof appStoreBackend.uninstallPackage !== "function") {
                    mode = "menu"
                    statusText = "App Store uninstall backend is unavailable"
                    return
                }

                if (appStoreBackend.uninstallPackage(id) !== true) {
                    mode = "menu"
                    statusText = String(appStoreBackend.statusMessage || "The package could not be uninstalled")
                    return
                }

                pendingUninstallId = id
                mode = "uninstalling"
                statusText = "Removing App Store package safely…"
                comboTokens = []
                return
            }
        } catch (storeError) {
            mode = "menu"
            statusText = "App Store uninstall failed: " + String(storeError)
            return
        }

        if (!appBackend || typeof appBackend.uninstallApp !== "function") {
            mode = "menu"
            statusText = "Uninstall backend is unavailable"
            return
        }

        var success = false

        try {
            success = appBackend.uninstallApp(appData) === true
        } catch (error) {
            mode = "menu"
            statusText = "Uninstall failed: " + String(error)
            return
        }

        if (!success) {
            mode = "menu"
            comboTokens = []
            statusText = "The app could not be uninstalled"
            return
        }

        statusText = "App uninstalled"
        appUninstalled(id)
        closeTimer.restart()
    }

    function normalizeController(button) {
        var b = String(button || "").trim().toLowerCase()

        if (b === "primary" || b === "cross" || b === "x" || b === "ps_cross")
            return "primary"
        if (b === "cancel" || b === "circle" || b === "o" || b === "ps_circle")
            return "cancel"
        if (b === "context" || b === "triangle" || b === "ps_triangle")
            return "context"
        if (b === "secondary" || b === "square" || b === "ps_square")
            return "secondary"
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
        if (b === "system" || b === "options" || b === "start" || b === "menu")
            return "system"
        if (b === "quick" || b === "share" || b === "select" || b === "create")
            return "quick"
        if (b === "home" || b === "ps" || b === "guide" || b === "playstation")
            return "home"

        return b
    }

    function comboToken(action) {
        if (action === "primary") return "X"
        if (action === "cancel") return "O"
        if (action === "context") return "TRIANGLE"
        if (action === "secondary") return "SQUARE"
        if (action === "up") return "U"
        if (action === "down") return "D"
        if (action === "left") return "L"
        if (action === "right") return "R"
        if (action === "l1") return "L1"
        if (action === "r1") return "R1"
        if (action === "l2") return "L2"
        if (action === "r2") return "R2"
        if (action === "l3") return "L3"
        if (action === "r3") return "R3"
        if (action === "system") return "START"
        if (action === "quick") return "SELECT"
        if (action === "home") return "SYSTEM"
        return ""
    }

    function handleControllerPressed(button) {
        var action = normalizeController(button)

        if (mode === "uninstalling")
            return true

        if (mode === "auth") {
            captureToken(comboToken(action))
            return true
        }

        if (mode === "verifying")
            return true

        if (action === "up" || action === "left") {
            moveSelection(-1)
            return true
        }

        if (action === "down" || action === "right") {
            moveSelection(1)
            return true
        }

        if (action === "primary" || action === "context") {
            activateSelected()
            return true
        }

        if (action === "cancel") {
            if (armedIndex >= 0) {
                armedIndex = -1
                statusText = "Choose an app action"
            } else {
                close()
            }
            return true
        }

        return true
    }

    function handleControllerReleased(button) {
        return true
    }

    function keyboardToken(key) {
        if (key === Qt.Key_Up) return "U"
        if (key === Qt.Key_Down) return "D"
        if (key === Qt.Key_Left) return "L"
        if (key === Qt.Key_Right) return "R"
        if (key === Qt.Key_X || key === Qt.Key_Return || key === Qt.Key_Enter) return "X"
        if (key === Qt.Key_O) return "O"
        if (key === Qt.Key_T) return "TRIANGLE"
        if (key === Qt.Key_S) return "SQUARE"
        if (key === Qt.Key_Q) return "L1"
        if (key === Qt.Key_E) return "R1"
        if (key === Qt.Key_Z) return "L2"
        if (key === Qt.Key_C) return "R2"
        if (key === Qt.Key_Home) return "SYSTEM"
        return ""
    }
}
