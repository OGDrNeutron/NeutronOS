import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"
import "modals" as Modals
import "gemini" as Gemini

Item {
    id: login
    objectName: "GeminiLoginScreen"

    signal unlocked(var user)
    signal unlockPulseFinished()
    signal consoleWarmupRequested()

    /*
        ============================================================
                            PUBLIC API FOR MAIN.QML
        ============================================================
    */

    property bool active: true
    property bool setupCovered: false
    property bool setupTransitionActive: false
    onSetupTransitionActiveChanged: {if(!setupTransitionActive)Qt.callLater(maybeOpenLoginInstructions)}
    property int lifecycleGeneration: 0
    property var activeUser: null
    property int selectedUser: 0

    property bool loginSuccess: false
    property bool unlockEmitted: false
    property bool unlockPulseFinishedEmitted: false

    function fractureOriginNormalized() {
        if (!userCard || login.width <= 0 || login.height <= 0)
            return ({ "x": 0.5, "y": 0.43 })
        var center = userCard.mapToItem(login, userCard.width / 2, userCard.height / 2)
        return ({
            "x": Math.max(0.05, Math.min(0.95, center.x / login.width)),
            "y": Math.max(0.05, Math.min(0.95, center.y / login.height))
        })
    }

    /*
        ============================================================
                            BACKEND REFERENCES
        ============================================================
    */

    property var securityBackend: (typeof securityManager !== "undefined") ? securityManager : null
    property var userBackend: (typeof userManager !== "undefined") ? userManager : null
    property var assetBackend: (typeof assetManager !== "undefined") ? assetManager : null
    property var controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
    property var securityCoreBackend: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null
    property var setupBackend: (typeof setupWizardManager !== "undefined") ? setupWizardManager : null

    function maybeOpenLoginInstructions() {
        if (active && !setupTransitionActive && setupBackend && setupBackend.setupComplete === true &&
                setupBackend.loginInstructionsPending === true &&
                !loginInstructionsModal.visible)
            loginInstructionsModal.openAutomatic()
    }

    /*
        ============================================================
                            LOGIN STATE
        ============================================================
    */

    /*
        flowMode:
            combo          = normal future login
            localPassword  = first login account-password gate
            createCombo    = create/confirm controller combo
            locked         = lockout
    */

    property string flowMode: "combo"
    property bool lockoutSyncInProgress: false

    property bool firstLoginRequired: false
    property string loginConfigurationState: "LOADING_UNKNOWN"
    property bool localPasswordVerified: false
    property bool recoverySetupVisible: false

    property string localPasswordText: ""
    property string typedPasswordMask: ""

    property var clockBackend:typeof clockSettingsManager!=="undefined"?clockSettingsManager:null
    property string lockscreenFocus:"user"
    function lockscreenClockIsVisible(){return !clockBackend||clockBackend.lockscreenClockVisible!==false}
    function setLockscreenFocus(value){
        if(cardArmed||loginSuccess||isLockedOut())return
        lockscreenFocus=value==="clock"&&lockscreenClockIsVisible()?"clock":"user"
    }
    function beginClockTimezoneAuthentication(){
        lockscreenFocus="user"
        selectFocused()
        if(clockBackend&&clockBackend.timezoneAuthorizationPending)statusText=clockBackend.worldClockStatus
    }
    Connections {
        target:login.clockBackend;ignoreUnknownSignals:true
        function onLockscreenClockVisibleChanged(){if(!login.lockscreenClockIsVisible())login.lockscreenFocus="user"}
    }
    property bool cardArmed: false
    property string inputBuffer: ""
    property var inputTokens: []
    property int maxInputWindow: 15

    property string comboDraft: ""
    property string comboConfirm: ""
    property bool comboConfirmStep: false
    property string comboDisplayText: ""

    /*
        Main.qml is the single controller router and ControllerManager already
        guarantees one actionPressed event per physical press/release cycle.
        LoginScreen therefore does not discard valid sequence tokens with an
        additional time-based filter. Intentional repeated inputs are preserved.
    */

    /*
        Controller-combo verification runs in SecurityManager's worker thread.
        Every press is captured first. Verification is deferred until the input
        stream has been quiet for 220 ms, so Argon2 and Console warmup never
        compete with rapid sequence entry. Complete rolling candidates remain
        queued in capture order, preserving the last-15-input behavior.
    */
    property var comboVerificationQueue: []
    property bool comboVerificationPending: false
    property string comboVerificationSubmittedBuffer: ""
    property int comboVerificationSubmittedCount: 0
    property int comboVerificationSession: 0
    property int comboVerificationSubmittedSession: 0
    property bool comboInputWindowSealed: false
    property int comboVerificationRetryMs: 110
    property bool consoleWarmupSentForSession: false

    property double lastComboConfirmPrimaryMs: 0
    property int comboConfirmPrimaryBlockMs: 420

    property bool primaryGuardActive: false

    property int homeTapCount: 0
    property bool mercuryPopupVisible: false

    property string statusText: "Profile ready"
    property string errorText: ""

    property string buildNumber: "v0.5.4 candidate"

    /*
        If the backend is not ready yet, this keeps development from bricking
        the shell. Production SecurityManager should replace this by exposing:
            hasLoginCombo(username)
            verifyLocalPassword(username, password)
            createLoginCombo(username, combo)
            verifyLoginCombo(username, combo)
    */
    property bool allowDevelopmentFallback: true
    property string developmentFallbackCombo: "UDLR"

    onActiveChanged: {
        if (!active)
            setControllerLowLatencyMode(false)
        else if (cardArmed && !loginSuccess)
            setControllerLowLatencyMode(true)
        if (active)
            Qt.callLater(maybeOpenLoginInstructions)
    }

    /*
        Reset the retained lock-screen tree without destroying/recreating it.
        Main.qml calls this before a Logout or Sleep transition so returning to
        the lock screen does not allocate the complete LoginScreen on the same
        frame and freeze the shell.
    */
    function prepareForLock(enableScreensaver) {
        if(clockBackend)clockBackend.cancelLockscreenTimezoneRequest()
        lockscreenFocus="user"
        cancelBufferedComboVerification(true)

        mercuryPopupTimer.stop()
        homeTapResetTimer.stop()
        primaryGuardTimer.stop()
        authenticationPulseAnimation.stop()

        /*
            Toggle the retained screen inactive while resetting it. Re-enabling
            on the next event-loop turn restarts every running-bound animation
            reliably after Logout without rebuilding LoginScreen.qml.
        */
        active = false
        loginSuccess = false
        unlockEmitted = false
        unlockPulseFinishedEmitted = false
        cardArmed = false
        primaryGuardActive = false
        homeTapCount = 0
        mercuryPopupVisible = false
        recoverySetupVisible = false

        inputBuffer = ""
        inputTokens = []
        comboDraft = ""
        comboConfirm = ""
        comboConfirmStep = false
        comboDisplayText = ""
        localPasswordText = ""
        typedPasswordMask = ""

        errorText = ""
        statusText = enableScreensaver
                   ? "Screen saver ready"
                   : "Profile ready"

        screenOpacity = 1.0
        unlockCardScale = 1.0
        unlockCardOpacity = 1.0
        unlockStageScale = 1.0
        unlockRippleScale = 0.25
        unlockRippleOpacity = 0.0

        circularStage.scale = 1.0

        setControllerLowLatencyMode(false)
        refreshEnrollmentState()

        Qt.callLater(function() {
            active = true
            forceActiveFocus()
        })
    }

    /*
        ============================================================
                            COLORS
        ============================================================
    */

    property color neutronRed: "#ff3040"
    property color neutronCyan: "#7df9ff"
    property color neutronBlue: "#47c8ff"
    property color neutronPink: "#ff4ea8"
    property color neutronPurple: "#c084fc"
    property color secureGreen: "#22ff88"
    property color glassDark: "#071426"
    property color glassDeep: "#02060D"

    /* Login security badge mirrors the Security app's protection-state rules. */
    readonly property var loginSecurityBackend:
        (typeof securityCoreManager !== "undefined") ? securityCoreManager : null

    /*
        ============================================================
                            ANIMATION STATE
        ============================================================
    */

    property bool animationsEnabled: active && !setupCovered && !isLockedOut()

    property real idlePulse: 0.55
    property real armedPulse: 0.45
    property real successPulse: 0.65

    property real ringPulse: 0.45
    property real ringRotation: 0.0

    property real screenOpacity: 1.0
    property real unlockCardScale: 1.0
    property real unlockCardOpacity: 1.0
    property real unlockStageScale: 1.0
    property real unlockRippleScale: 0.25
    property real unlockRippleOpacity: 0.0

    focus: true
    opacity: screenOpacity

    /*
        ============================================================
                            BACKEND HELPERS
        ============================================================
    */

    function currentUser() {
        try {
            if (userBackend &&
                    userBackend.users &&
                    userBackend.users.length > 0) {
                return userBackend.users[selectedUser]
            }
        } catch (e) {
            console.log("LoginScreen currentUser error:", e)
        }

        return {
            displayName: "User",
            username: "neutronos"
        }
    }

    function currentUsername() {
        var user = currentUser()

        if (user && user.username !== undefined && String(user.username).length > 0)
            return String(user.username)

        return "neutronos"
    }

    function currentDisplayName() {
        var user = currentUser()

        if (user && user.displayName !== undefined && String(user.displayName).length > 0)
            return String(user.displayName)

        return currentUsername()
    }

    /* PATCH 15: PROFILE APPEARANCE HELPERS */
    function profileValue(keys, fallbackValue) {
        var user = currentUser()

        if (!user)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = user[keys[i]]

                if (value !== undefined &&
                        value !== null &&
                        String(value).trim().length > 0) {
                    return value
                }
            } catch (error) {
            }
        }

        return fallbackValue
    }

    function currentNameTint() {
        return String(profileValue(
            ["nameTint", "displayNameTint"],
            "#FFFFFF"
        ))
    }

    function currentAccentColor() {
        return String(profileValue(
            ["accentColor", "profileAccent"],
            neutronCyan
        ))
    }

    function currentProfileTagline() {
        return String(profileValue(
            ["profileTagline", "tagline", "statusMessage"],
            ""
        ))
    }

    function currentAvatarFrame() {
        return String(profileValue(["avatarFrame", "frameStyle"], "circle")).toLowerCase()
    }

    function currentGlowStrength() {
        var value = Number(profileValue(["glowStrength"], 0.65))
        if (isNaN(value))
            return 0.65
        if (value > 1.0)
            value = value / 100.0
        return Math.max(0.0, Math.min(1.0, value))
    }

    function currentAvatarSource() {
        var source = String(profileValue(
            ["resolvedAvatarSource", "avatarSource", "icon", "avatar", "profileIcon"],
            "users/user_icon.png"
        ))

        if (source.indexOf("file:") === 0 ||
                source.indexOf("qrc:") === 0 ||
                source.indexOf("image:") === 0 ||
                source.indexOf("http://") === 0 ||
                source.indexOf("https://") === 0) {
            return source
        }

        try {
            if (userBackend &&
                    typeof userBackend.resolveAvatarSource === "function") {
                var resolved = userBackend.resolveAvatarSource(source)

                if (resolved && String(resolved).length > 0)
                    return resolved
            }
        } catch (error) {
        }

        if (source.indexOf("/") < 0)
            source = "users/" + source

        return themeFile(source)
    }

    function idleProfileStatus() {
        var tagline = currentProfileTagline()
        return tagline.length > 0 ? tagline : statusText
    }

    function themeFile(path) {
        if (assetBackend && typeof assetBackend.themeFile === "function")
            return assetBackend.themeFile(path)

        return ""
    }

    function refreshSecurity() {
        if (securityBackend && typeof securityBackend.refresh === "function")
            securityBackend.refresh()
    }

    function isLockedOut() {
        if (!securityBackend || securityBackend.lockedOut !== true)
            return false

        /*
            Never present a stale lockout flag without an active countdown.
            SecurityManager publishes both values from one state update, so a
            zero/invalid remaining value means the lockout has ended or has not
            finished initializing yet.
        */
        if (securityBackend.secondsRemaining !== undefined)
            return Number(securityBackend.secondsRemaining) > 0

        return true
    }

    function lockoutSecondsRemaining() {
        if (!securityBackend)
            return 0

        if (securityBackend.secondsRemaining !== undefined)
            return Math.max(0, Number(securityBackend.secondsRemaining))

        return 0
    }

    function callBackend(names, args, fallbackValue) {
        if (!securityBackend)
            return fallbackValue

        for (var i = 0; i < names.length; i++) {
            var name = names[i]

            try {
                if (typeof securityBackend[name] === "function")
                    return securityBackend[name].apply(securityBackend, args)
            } catch (e) {
                console.log("Security backend call failed:", name, e)
            }
        }

        return fallbackValue
    }

    function hasLoginCombo(username) {
        var result = callBackend(
                    [
                        "hasLoginCombo",
                        "loginComboConfigured",
                        "isLoginComboConfigured",
                        "comboConfigured",
                        "hasCombo"
                    ],
                    [username],
                    null
                )

        if (result !== null && result !== undefined)
            return result === true

        try {
            if (securityBackend && securityBackend.loginComboConfigured !== undefined)
                return securityBackend.loginComboConfigured === true
        } catch (e) {
        }

        /*
            Development fallback:
            If the backend does not expose combo enrollment yet, behave like
            a combo exists so current testing can still reach Console.
        */
        return allowDevelopmentFallback
    }

    function verifyLocalPassword(username, password) {
        var result = callBackend(
                    [
                        "verifyLocalPassword",
                        "verifyAccountPassword",
                        "verifyUserPassword",
                        "verifyPassword"
                    ],
                    [username, password],
                    null
                )

        if (result !== null && result !== undefined)
            return result === true

        errorText = "SecurityManager must expose verifyLocalPassword(username, password)."
        return false
    }

    function createLoginCombo(username, combo) {
        var result = callBackend(
                    [
                        "createLoginCombo",
                        "setLoginCombo",
                        "enrollLoginCombo",
                        "saveLoginCombo"
                    ],
                    [username, combo],
                    null
                )

        if (result !== null && result !== undefined)
            return result === true

        errorText = "SecurityManager must expose createLoginCombo(username, combo)."
        return false
    }

    function verifyLoginCombo(username, combo) {
        var result = callBackend(
                    [
                        "verifyLoginCombo",
                        "verifyCombo",
                        "checkLoginCombo",
                        "validateLoginCombo"
                    ],
                    [username, combo],
                    null
                )

        if (result !== null && result !== undefined)
            return result === true

        /*
            Development fallback only.
            Remove this once SecurityManager hashing is wired.
        */
        if (allowDevelopmentFallback)
            return combo === developmentFallbackCombo

        errorText = "SecurityManager must expose verifyLoginCombo(username, combo)."
        return false
    }

    function registerFailedAttempt() {
        if (securityBackend && typeof securityBackend.registerFailedAttempt === "function")
            return securityBackend.registerFailedAttempt()

        return false
    }

    function registerSuccess() {
        if (securityBackend && typeof securityBackend.registerSuccess === "function")
            securityBackend.registerSuccess()
    }

    function refreshEnrollmentState() {
        ensureSecurityActiveUser()
        refreshSecurity()

        if (isLockedOut()) {
            flowMode = "locked"
            statusText = "Access suspended"
            return
        }

        var state = "SECURITY_UNAVAILABLE"
        try {
            if (securityBackend && securityBackend.loginConfigurationState !== undefined)
                state = String(securityBackend.loginConfigurationState || "LOADING_UNKNOWN")
        } catch (e) {
            state = "SECURITY_UNAVAILABLE"
        }
        loginConfigurationState = state
        firstLoginRequired = state === "UNCONFIGURED"

        if (state === "UNCONFIGURED") {
            flowMode = "localPassword"
            statusText = "First login required"
        } else if (state === "CONFIGURED") {
            flowMode = "combo"
            statusText = "Profile ready"
        } else {
            flowMode = "unavailable"
            statusText = state === "LOADING_UNKNOWN"
                       ? "Loading security profile"
                       : "Security profile unavailable"
        }

        localPasswordVerified = false
        localPasswordText = ""
        typedPasswordMask = ""
        comboDraft = ""
        comboConfirm = ""
        comboConfirmStep = false
        comboDisplayText = ""
        resetComboDuplicateGuard()
        cancelBufferedComboVerification()
        inputBuffer = ""
        inputTokens = []
        cardArmed = false
        errorText = ""
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on idlePulse {
        running: animationsEnabled && !cardArmed
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.34
            to: 0.92
            duration: 2400
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 0.92
            to: 0.34
            duration: 2100
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation on armedPulse {
        running: active && cardArmed && !loginSuccess && !isLockedOut()
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.58
            to: 1.0
            duration: 920
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.58
            duration: 920
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on successPulse {
        running: loginSuccess
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.54
            to: 1.0
            duration: 360
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            from: 1.0
            to: 0.54
            duration: 520
            easing.type: Easing.InOutCubic
        }
    }

    SequentialAnimation on ringPulse {
        running: active && !setupCovered
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.34
            to: 1.0
            duration: cardArmed || isLockedOut() ? 1200 : 2300
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.34
            duration: cardArmed || isLockedOut() ? 1200 : 1900
            easing.type: Easing.InOutSine
        }
    }

    NumberAnimation on ringRotation {
        running: active && !setupCovered
        from: 0
        to: 360
        duration: cardArmed || isLockedOut() ? 7200 : 9000
        loops: Animation.Infinite
        easing.type: Easing.Linear
    }


    /*
        ============================================================
                            BACKGROUND
        ============================================================
    */

    Rectangle {
        anchors.fill: parent
        color: glassDeep
    }

    Image {
        id: bg

        anchors.fill: parent
        source: themeFile("background.png")
        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: false
        asynchronous: true

        scale: 1.0
        x: 0

        SequentialAnimation on scale {
            running: animationsEnabled
            loops: Animation.Infinite

            NumberAnimation {
                from: 1.0
                to: 1.026
                duration: 52000
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                from: 1.026
                to: 1.0
                duration: 52000
                easing.type: Easing.InOutSine
            }
        }

        SequentialAnimation on x {
            running: animationsEnabled
            loops: Animation.Infinite

            NumberAnimation {
                from: -12
                to: 12
                duration: 62000
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                from: 12
                to: -12
                duration: 62000
                easing.type: Easing.InOutSine
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#02060D"
        opacity: 0.22
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"

        opacity: mercuryPopupVisible
                 ? 0.70
                 : isLockedOut()
                   ? 0.52
                   : cardArmed
                     ? 0.33
                     : 0.27

        Behavior on opacity {
            NumberAnimation {
                duration: 320
                easing.type: Easing.InOutCubic
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 280

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#02060DEE" }
            GradientStop { position: 1.0; color: "#02060D00" }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 340

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#02060D00" }
            GradientStop { position: 1.0; color: "#02060DEE" }
        }
    }


    Gemini.LockPresentation { id:lockPresentation;anchors.fill:parent;host:login }
    Item {
        id:circularStage
        width:Math.min(login.width,login.height)*.74;height:width
        anchors.horizontalCenter:parent.horizontalCenter
        y:login.height*.535-height/2
        Item {
            id:userCard;anchors.centerIn:parent;width:120;height:120
            function startErrorAnimation(){lockPresentation.errorFeedback()}
            function startLockoutAnimation(){lockPresentation.errorFeedback()}
            function nudge(key){}
        }
    }
    /*
        ============================================================
                        FIRST LOGIN PASSWORD MODAL
        ============================================================
    */

    Rectangle {
        id: passwordModalScrim

        anchors.fill: parent

        visible: flowMode === "localPassword" && firstLoginRequired && !loginSuccess
        color: "#01040A"
        opacity: visible ? 0.72 : 0.0

        z: 800
    }

    Rectangle {
        id: passwordModal

        anchors.centerIn: parent

        visible: flowMode === "localPassword" && firstLoginRequired && !loginSuccess

        width: Math.min(parent.width - 56, 1280)
        height: Math.min(parent.height - 56, 900)
        radius: 42

        color: "#050914"
        border.width: 2
        border.color: neutronPurple

        z: 820
        clip: true

        onVisibleChanged: {
            if (visible)
                Qt.callLater(openLocalPasswordKeyboard)
            else
                closeLocalPasswordKeyboard()
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.035
        }

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            Text {
                width: parent.width
                text: "FIRST LOGIN"
                color: neutronPurple
                font.pixelSize: 20
                font.bold: true
                font.letterSpacing: 4
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: "Enter the local account password for " + currentUsername()
                color: "white"
                font.pixelSize: 34
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: "After this, you will create a controller button combo. Future unlocks will use the combo only."
                color: "#9FD8FF"
                font.pixelSize: 17
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 58
                radius: 24
                color: "#071426dd"
                border.width: 1
                border.color: "#7df9ff77"

                TextInput {
                    id: passwordInput

                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24

                    text: localPasswordText
                    echoMode: TextInput.Password
                    color: "white"
                    font.pixelSize: 28
                    font.bold: true
                    verticalAlignment: TextInput.AlignVCenter
                    focus: false

                    onTextChanged: {
                        localPasswordText = text
                    }

                    Keys.onReturnPressed: {
                        statusText = "Press OPTIONS / START to submit password"
                        event.accepted = true
                    }
                    Keys.onEnterPressed: {
                        statusText = "Press OPTIONS / START to submit password"
                        event.accepted = true
                    }
                    Keys.onEscapePressed: cancelLocalPassword()
                }
            }

            VirtualKeyboard {
                id: virtualKeyboard

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, 1160)
                height: 520

                active: passwordModal.visible
                cancelBehavior: "backspace"
                resetOnOpen: false


                onKeyPressed: function(value) {
                    appendPasswordKey(value)
                }

                onBackspacePressed: {
                    if (localPasswordText.length > 0)
                        localPasswordText = localPasswordText.slice(0, localPasswordText.length - 1)

                    passwordInput.text = localPasswordText
                }

                onEnterPressed: {
                    statusText = "Press OPTIONS / START to submit password"
                }

                onClosePressed: {
                    cancelLocalPassword()
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 34

                Text {
                    text: "OPTIONS / START  Submit"
                    color: secureGreen
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1.4
                }

                Text {
                    text: "O  Backspace"
                    color: "#ffb3b3"
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1.4
                }
            }
        }
    }

    /*
        ============================================================
                        CREATE BUTTON COMBO MODAL
        ============================================================
    */

    Rectangle {
        id: createComboScrim

        anchors.fill: parent

        visible: flowMode === "createCombo" && !loginSuccess
        color: "#01040A"
        opacity: visible ? 0.74 : 0.0

        z: 830
    }

    Rectangle {
        id: createComboModal

        anchors.centerIn: parent

        visible: flowMode === "createCombo" && !loginSuccess

        width: 860
        height: 470
        radius: 40

        color: "#050914"
        border.width: 2
        border.color: comboConfirmStep ? secureGreen : neutronCyan

        z: 850
        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.035
        }

        Column {
            anchors.fill: parent
            anchors.margins: 38
            spacing: 22

            Text {
                width: parent.width

                text: comboConfirmStep ? "CONFIRM BUTTON COMBO" : "CREATE BUTTON COMBO"

                color: comboConfirmStep ? secureGreen : neutronCyan
                font.pixelSize: 20
                font.bold: true
                font.letterSpacing: 4
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width

                text: comboConfirmStep
                      ? "Enter the same controller combo again."
                      : "Choose a controller combo for future unlocks."

                color: "white"
                font.pixelSize: 34
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width

                text: "Use D-pad or controller buttons. Minimum 4 inputs. X confirms. O clears or cancels."

                color: "#9FD8FF"
                font.pixelSize: 17
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 112
                radius: 30

                color: "#071426dd"
                border.width: 1
                border.color: comboConfirmStep ? "#22ff8877" : "#7df9ff77"

                Text {
                    anchors.centerIn: parent

                    text: comboDisplayText.length > 0 ? comboDisplayText : "Awaiting input…"

                    color: comboDisplayText.length > 0 ? "white" : "#6f8aaa"
                    font.pixelSize: 30
                    font.bold: true
                    font.letterSpacing: 2
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 36

                Text {
                    text: "X  Confirm"
                    color: secureGreen
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1.4
                }

                Text {
                    text: "O  Clear / Cancel"
                    color: "#ffb3b3"
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1.4
                }

                Text {
                    text: "Keyboard: arrows + Enter"
                    color: "#9FD8FF"
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 1.4
                }
            }
        }
    }

    /*
        ============================================================
                            MERCURY EASTER EGG
        ============================================================
    */

    Rectangle {
        id: modalScrim

        anchors.fill: parent

        visible: opacity > 0
        opacity: mercuryPopupVisible ? 1.0 : 0.0

        color: "#01040A"
        z: 900

        Behavior on opacity {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        id: mercuryPopup

        anchors.centerIn: parent

        width: 720
        height: 390
        radius: 38

        visible: opacity > 0
        opacity: mercuryPopupVisible ? 1 : 0

        z: 920

        color: "#050914"
        border.width: 2
        border.color: neutronCyan

        scale: mercuryPopupVisible ? 1.0 : 0.76
        clip: true

        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 460
                easing.type: Easing.OutBack
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.035
        }

        Image {
            id: mercuryAtom

            width: 126
            height: 126

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 22

            sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
            source: (typeof assetManager !== "undefined" && assetManager) ? assetManager.logo() : themeFile("atom.svg")
            fillMode: Image.PreserveAspectFit

            smooth: true
            cache: false
            asynchronous: true

            opacity: 0.92

            RotationAnimation on rotation {
                running: mercuryPopupVisible && animationsEnabled
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 6800
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: mercuryAtom.bottom
            anchors.topMargin: 14

            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "NeutronOS Gemini"
                color: "white"
                font.pixelSize: 43
                font.bold: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Mercury Edition"
                color: neutronCyan
                font.pixelSize: 31
                font.bold: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Creation Date: 7/4/26"
                color: neutronPurple
                font.pixelSize: 22
                font.bold: true
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Text { text: "Secure"; color: "#D6DADF"; font.pixelSize: 17; font.bold: true }
                Text { text: "|"; color: "#6F7A82"; font.pixelSize: 17; font.bold: true }
                Text { text: "Intelligent"; color: "#D6DADF"; font.pixelSize: 17; font.bold: true }
                Text { text: "|"; color: "#6F7A82"; font.pixelSize: 17; font.bold: true }
                Text { text: "Unstoppable"; color: neutronRed; font.pixelSize: 17; font.bold: true }
            }
        }
    }

    SequentialAnimation {
        id:authenticationPulseAnimation
        ParallelAnimation {
            NumberAnimation{target:login;property:"unlockRippleScale";from:.6;to:2.1;duration:420;easing.type:Easing.OutCubic}
            SequentialAnimation{
                NumberAnimation{target:login;property:"unlockRippleOpacity";from:0;to:.8;duration:90}
                NumberAnimation{target:login;property:"unlockRippleOpacity";to:0;duration:330}
            }
        }
        onFinished:{if(!login.unlockPulseFinishedEmitted){login.unlockPulseFinishedEmitted=true;login.unlockPulseFinished()}}
    }
    /*
        ============================================================
                                TIMERS
        ============================================================
    */

    Timer {
        id: mercuryPopupTimer
        interval: 5000
        repeat: false
        running: mercuryPopupVisible

        onTriggered: mercuryPopupVisible = false
    }

    Timer {
        id: homeTapResetTimer
        interval: 1800
        repeat: false

        onTriggered: homeTapCount = 0
    }

    Timer {
        id: primaryGuardTimer
        interval: 280
        repeat: false

        onTriggered: primaryGuardActive = false
    }

    Timer {
        id: comboVerificationRetryTimer
        interval: login.comboVerificationRetryMs
        repeat: false

        /*
            Quiet-period verifier. Every new token restarts this timer.
            Nothing expensive starts while the user is still pressing buttons.
        */
        onTriggered: login.startNextComboVerification()
    }

    Timer {
        id: securityRefreshTimer
        interval: 10000
        repeat: true
        running: active

        onTriggered: {
            /*
                Never perform filesystem/security refresh work while the user is
                entering a combo or while Argon2 is running.
            */
            if (cardArmed ||
                    comboVerificationPending ||
                    comboVerificationQueue.length > 0) {
                return
            }

            refreshSecurity()

            if (isLockedOut())
                flowMode = "locked"
            else if (flowMode === "locked")
                refreshEnrollmentState()
        }
    }

    /*
        ============================================================
                            CONTROLLER INPUT
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

    function comboTokenForAction(action) {
        if (action === "primary")
            return "X"

        if (action === "cancel")
            return "O"

        if (action === "context")
            return "TRIANGLE"

        if (action === "secondary")
            return "SQUARE"

        if (action === "system")
            return "START"

        if (action === "quick")
            return "SELECT"

        if (action === "home")
            return "SYSTEM"

        if (action === "up")
            return "U"

        if (action === "down")
            return "D"

        if (action === "left")
            return "L"

        if (action === "right")
            return "R"

        if (action === "l1")
            return "L1"

        if (action === "r1")
            return "R1"

        if (action === "l2")
            return "L2"

        if (action === "r2")
            return "R2"

        if (action === "l3")
            return "L3"

        if (action === "r3")
            return "R3"

        return ""
    }

    function comboTokenAllowed(token) {
        /*
            One routed press is one token. Do not suppress intentional repeated
            directions or buttons with a millisecond timer.
        */
        return String(token || "").length > 0
    }

    function resetComboDuplicateGuard() {
        /* Compatibility no-op. Main.qml owns duplicate physical routing. */
    }

    function normalizeComboForCompare(combo) {
        /* Preserve every token, including intentional repeats and shoulder keys. */
        return tokenizeComboString(combo).join("|")
    }

    function comboMatches() {
        return normalizeComboForCompare(comboDraft) === normalizeComboForCompare(comboConfirm)
    }

    function comboLength(combo) {
        return normalizeComboForCompare(combo).length
    }

    function comboForSaving() {
        return normalizeComboForCompare(comboDraft)
    }


    function appendComboToken(action) {
        /*
            X arms the card while unarmed. Once armed, a later X press is a
            legitimate combo token and must be captured like every other button.
        */
        if (action === "system" || action === "start" || action === "options")
            return

        if (action === "cancel")
            return

        var token = comboTokenForAction(action)

        if (token.length <= 0)
            return

        if (!comboTokenAllowed(token))
            return

        if (flowMode === "createCombo") {
            if (comboConfirmStep)
                comboConfirm += token
            else
                comboDraft += token

            updateComboDisplay()
            nudgeUserCard(token)
            return
        }

        if (!cardArmed || loginSuccess || isLockedOut())
            return

        /*
            Once fifteen inputs have been captured, the established failure window
            is sealed until its queued candidates finish verification. This avoids
            discarding or overwriting any input inside the authoritative window.
        */
        if (comboInputWindowSealed)
            return

        var nextTokens = []

        for (var i = 0; i < inputTokens.length; i++)
            nextTokens.push(inputTokens[i])

        nextTokens.push(token)

        while (nextTokens.length > maxInputWindow)
            nextTokens.shift()

        /* Commit capture before any animation or backend work. */
        inputTokens = nextTokens
        inputBuffer = inputTokens.join("")
        errorText = ""
        statusText = "Sequence captured · " + inputTokens.length + "/" + maxInputWindow

        if (inputTokens.length >= maxInputWindow)
            comboInputWindowSealed = true

        enqueueCurrentComboCandidate()

        /* Visual feedback is intentionally deferred off the capture path. */
        nudgeUserCard(token)
    }

    function configuredComboLength() {
        try {
            if (securityBackend && securityBackend.comboLength !== undefined) {
                var length = Number(securityBackend.comboLength)

                if (!isNaN(length) && length > 0)
                    return Math.floor(length)
            }
        } catch (error) {
        }

        return 4
    }

    function ensureSecurityActiveUser() {
        if (!securityBackend)
            return false

        var username = currentUsername()

        try {
            if (securityBackend.activeUsername !== undefined &&
                    String(securityBackend.activeUsername) === username) {
                return true
            }
        } catch (readError) {
        }

        try {
            if (typeof securityBackend.setActiveUsername === "function")
                return securityBackend.setActiveUsername(username) === true
        } catch (usernameError) {
            console.log("LoginScreen setActiveUsername failed:", usernameError)
        }

        try {
            if (typeof securityBackend.setActiveUser === "function")
                return securityBackend.setActiveUser(currentUser()) === true
        } catch (userError) {
            console.log("LoginScreen setActiveUser failed:", userError)
        }

        /* Legacy synchronous backends select the user during verification. */
        return true
    }

    function asyncComboVerificationAvailable() {
        return securityBackend &&
               typeof securityBackend.beginLoginComboVerification === "function"
    }

    function enqueueCurrentComboCandidate() {
        if (flowMode !== "combo" ||
                !cardArmed ||
                loginSuccess ||
                isLockedOut()) {
            return
        }

        var comboLength = configuredComboLength()

        if (inputTokens.length < comboLength)
            return

        var candidate = {
            buffer: inputBuffer,
            count: inputTokens.length,
            session: comboVerificationSession
        }

        var nextQueue = comboVerificationQueue.slice(0)
        nextQueue.push(candidate)
        comboVerificationQueue = nextQueue

        /*
            Do not hash or construct Console while buttons are still arriving.
            Restarting the quiet timer is cheap and guarantees that capture wins.
        */
        comboVerificationRetryTimer.restart()
    }

    function startNextComboVerification() {
        if (comboVerificationPending ||
                loginSuccess ||
                !cardArmed ||
                isLockedOut()) {
            return
        }

        while (comboVerificationQueue.length > 0) {
            var queueCopy = comboVerificationQueue.slice(0)
            var candidate = queueCopy.shift()
            comboVerificationQueue = queueCopy

            if (!candidate || candidate.session !== comboVerificationSession)
                continue

            if (!ensureSecurityActiveUser()) {
                /* User/profile state may still be settling after startup. */
                queueCopy = comboVerificationQueue.slice(0)
                queueCopy.unshift(candidate)
                comboVerificationQueue = queueCopy
                comboVerificationRetryTimer.restart()
                return
            }

            comboVerificationSubmittedBuffer = candidate.buffer
            comboVerificationSubmittedCount = candidate.count
            comboVerificationSubmittedSession = candidate.session

            /*
                Input has now been quiet long enough to begin heavier work.
                Console warmup and Argon2 can overlap without stealing time from
                active button capture.
            */
            if (!consoleWarmupSentForSession) {
                consoleWarmupSentForSession = true
                consoleWarmupRequested()
            }

            if (asyncComboVerificationAvailable()) {
                try {
                    if (securityBackend.operationBusy === true) {
                        queueCopy = comboVerificationQueue.slice(0)
                        queueCopy.unshift(candidate)
                        comboVerificationQueue = queueCopy
                        comboVerificationRetryTimer.restart()
                        return
                    }
                } catch (busyError) {
                }

                var accepted = false

                try {
                    accepted = securityBackend.beginLoginComboVerification(
                        currentUsername(),
                        candidate.buffer
                    ) === true
                } catch (startError) {
                    console.log("LoginScreen async combo verification error:", startError)
                }

                if (accepted) {
                    comboVerificationPending = true
                    return
                }

                queueCopy = comboVerificationQueue.slice(0)
                queueCopy.unshift(candidate)
                comboVerificationQueue = queueCopy
                comboVerificationRetryTimer.restart()
                return
            }

            /*
                Development compatibility only. Production SecurityManager always
                takes the asynchronous worker path above.
            */
            comboVerificationPending = true

            Qt.callLater(function() {
                var submittedSession = comboVerificationSubmittedSession
                var submittedCount = comboVerificationSubmittedCount
                var submittedBuffer = comboVerificationSubmittedBuffer
                var success = verifyLoginCombo(currentUsername(), submittedBuffer)

                comboVerificationPending = false

                if (submittedSession !== comboVerificationSession ||
                        loginSuccess ||
                        !cardArmed) {
                    return
                }

                if (success) {
                    triggerUnlock()
                    return
                }

                handleComboVerificationResult(
                    false,
                    "Incorrect combo",
                    submittedCount,
                    0
                )
            })

            return
        }
    }

    function handleComboVerificationResult(success,
                                            message,
                                            submittedCount,
                                            secondsRemaining) {
        if (loginSuccess || !cardArmed)
            return

        if (success) {
            triggerUnlock()
            return
        }

        if (secondsRemaining > 0 || isLockedOut()) {
            comboVerificationQueue = []
            comboInputWindowSealed = false
            inputTokens = []
            inputBuffer = ""
            cardArmed = false
            flowMode = "locked"
            statusText = "Access suspended"
            errorText = message && message.length > 0
                      ? message
                      : "Login is temporarily locked"

            if (typeof userCard.startLockoutAnimation === "function")
                userCard.startLockoutAnimation()

            return
        }

        /*
            A mismatch before fifteen inputs simply advances to the next captured
            rolling candidate. At fifteen, the backend has registered one failed
            attempt; clear the sealed window and remain armed for another try.
        */
        if (submittedCount >= maxInputWindow &&
                comboVerificationQueue.length === 0) {
            if(clockBackend)clockBackend.cancelLockscreenTimezoneRequest()
            comboInputWindowSealed = false
            inputTokens = []
            inputBuffer = ""
            statusText = "Sequence gate armed"
            errorText = message && message.length > 0
                      ? message
                      : "Incorrect combo"

            if (typeof userCard.startErrorAnimation === "function")
                userCard.startErrorAnimation()

            return
        }

        /* SecurityManager clears operationBusy after emitting its result signal. */
        comboVerificationRetryTimer.restart()
    }

    function cancelBufferedComboVerification(cancelBackend) {
        comboVerificationRetryTimer.stop()
        comboVerificationSession++
        comboVerificationQueue = []
        comboVerificationPending = false
        comboVerificationSubmittedBuffer = ""
        comboVerificationSubmittedCount = 0
        comboVerificationSubmittedSession = comboVerificationSession
        comboInputWindowSealed = false
        consoleWarmupSentForSession = false

        if (cancelBackend === false)
            return

        try {
            if (securityBackend &&
                    securityBackend.activeOperation === "verifyLoginCombo" &&
                    typeof securityBackend.cancelPendingOperation === "function") {
                securityBackend.cancelPendingOperation()
            }
        } catch (error) {
        }
    }

    function comboInputCount(combo) {
        return tokenizeComboString(combo).length
    }

    function tokenizeComboString(combo) {
        var text = String(combo || "").trim().toUpperCase()

        text = text.replace(/ /g, "")
        text = text.replace(/-/g, "")
        text = text.replace(/_/g, "")
        text = text.replace(/,/g, "")
        text = text.replace(/\|/g, "")
        text = text.replace(/>/g, "")

        var knownTokens = [
            "TRIANGLE",
            "SQUARE",
            "SELECT",
            "SYSTEM",
            "START",
            "L1",
            "R1",
            "L2",
            "R2",
            "L3",
            "R3",
            "UP",
            "DOWN",
            "LEFT",
            "RIGHT",
            "CROSS",
            "CIRCLE",
            "PRIMARY",
            "CANCEL",
            "X",
            "O",
            "U",
            "D",
            "L",
            "R"
        ]

        var tokens = []

        while (text.length > 0) {
            var matched = false

            for (var i = 0; i < knownTokens.length; i++) {
                var token = knownTokens[i]

                if (text.indexOf(token) === 0) {
                    var canonical = token

                    if (canonical === "UP")
                        canonical = "U"
                    else if (canonical === "DOWN")
                        canonical = "D"
                    else if (canonical === "LEFT")
                        canonical = "L"
                    else if (canonical === "RIGHT")
                        canonical = "R"
                    else if (canonical === "CROSS" || canonical === "PRIMARY")
                        canonical = "X"
                    else if (canonical === "CIRCLE" || canonical === "CANCEL")
                        canonical = "O"

                    tokens.push(canonical)
                    text = text.slice(token.length)
                    matched = true
                    break
                }
            }

            if (!matched)
                text = text.slice(1)
        }

        return tokens
    }

    function handleController(button) {
        return handleControllerPressed(button)
    }

    function handleControllerPressed(button) {
        if (loginInstructionsModal.visible)
            return loginInstructionsModal.handleControllerPressed(button)
        if (!active)
            return true

        var action = normalizeControllerAction(button)

        if (action.length === 0)
            return true

        if (recoverySetupVisible) {
            return recoverySetupWizard.handleControllerPressed(action)
        }

        if (mercuryPopupVisible) {
            if (action === "cancel" ||
                    action === "primary" ||
                    action === "context" ||
                    action === "system" ||
                    action === "home") {
                mercuryPopupVisible = false
                forceActiveFocus()
            }

            return true
        }

        if (isLockedOut()) {
            flowMode = "locked"

            if (action === "cancel")
                disarmCard()

            return true
        }

        if (flowMode === "localPassword") {
            handlePasswordController(action)
            return true
        }

        if (flowMode === "createCombo") {
            handleCreateComboController(action)
            return true
        }

        // Only these two live lockscreen surfaces participate in navigation.
        // Armed passcode input keeps the existing route below without interception.
        if (!cardArmed) {
            if (action === "up" || action === "right" || action === "down" || action === "left") {
                setLockscreenFocus(action === "up" || action === "right" ? "clock" : "user")
                return true
            }
            if (lockscreenFocus === "clock") {
                if (action === "cancel")setLockscreenFocus("user")
                else lockPresentation.handleClockAction(action)
                return true
            }
        }

        if (action === "primary") {
            if (!cardArmed)
                selectFocused()
            else
                appendComboToken(action)

            return true
        }

        if (action === "cancel") {
            disarmCard()
            return true
        }

        if (action === "home") {
            registerHomeTap()
            return true
        }

        if (action === "l1") {
            if (!cardArmed)
                setSelectedUser(selectedUser - 1)

            return true
        }

        if (action === "r1") {
            if (!cardArmed)
                setSelectedUser(selectedUser + 1)

            return true
        }

        appendComboToken(action)
        return true
    }

    function handleControllerReleased(button) {
        try {
            if (typeof virtualKeyboard !== "undefined" && virtualKeyboard &&
                    typeof virtualKeyboard.handleControllerReleased === "function")
                virtualKeyboard.handleControllerReleased(button)
        } catch (e) {
            console.log("LoginScreen keyboard release route error:", e)
        }
        return true
    }

    function openLocalPasswordKeyboard() {
        try {
            if (typeof virtualKeyboard !== "undefined" &&
                    virtualKeyboard &&
                    typeof virtualKeyboard.openKeyboard === "function") {
                virtualKeyboard.active = true
                virtualKeyboard.cancelBehavior = "backspace"
                virtualKeyboard.openKeyboard("small")
                statusText = "Enter local account password"
                return
            }
        } catch (e) {
            console.log("LoginScreen openLocalPasswordKeyboard error:", e)
        }

        try {
            passwordInput.forceActiveFocus()
        } catch (e2) {
        }
    }

    function closeLocalPasswordKeyboard() {
        try {
            if (typeof virtualKeyboard !== "undefined" &&
                    virtualKeyboard &&
                    virtualKeyboard.visibleMode !== undefined) {
                virtualKeyboard.visibleMode = false
            }
        } catch (e) {
        }
    }

    property string passwordKeyboardLastAction: ""
    property double passwordKeyboardLastActionMs: 0
    property int passwordKeyboardDuplicateBlockMs: 120

    function passwordKeyboardActionAllowed(action) {
        var now = Date.now()

        if (passwordKeyboardLastAction === action &&
                now - passwordKeyboardLastActionMs < passwordKeyboardDuplicateBlockMs) {
            return false
        }

        passwordKeyboardLastAction = action
        passwordKeyboardLastActionMs = now
        return true
    }

    function handlePasswordController(action) {
        /*
            LoginScreen is the controller router for the first-login keyboard.

            The duplicate guard prevents:
                - D-pad jumping two keys
                - X entering two letters
                - O deleting two letters
        */

        if (action === "system" || action === "start" || action === "options") {
            if (passwordKeyboardActionAllowed(action))
                submitLocalPassword()
            return
        }

        try {
            if (typeof virtualKeyboard !== "undefined" &&
                    virtualKeyboard &&
                    typeof virtualKeyboard.handleController === "function") {

                if (!virtualKeyboard.visibleMode)
                    openLocalPasswordKeyboard()

                if (passwordKeyboardActionAllowed(action))
                    virtualKeyboard.handleController(action)

                return
            }
        } catch (e) {
            console.log("LoginScreen password keyboard route error:", e)
        }

        if (action === "primary" || action === "cancel")
            openLocalPasswordKeyboard()
    }

    function comboConfirmPrimaryAllowed() {
        var now = Date.now()

        if (now - lastComboConfirmPrimaryMs < comboConfirmPrimaryBlockMs)
            return false

        lastComboConfirmPrimaryMs = now
        return true
    }

    function handleCreateComboController(action) {
        if (action === "primary") {
            if (comboConfirmPrimaryAllowed())
                confirmComboStep()
            return
        }

        if (action === "cancel") {
            if ((comboConfirmStep && comboLength(comboConfirm) > 0) ||
                    (!comboConfirmStep && comboLength(comboDraft) > 0)) {
                if (comboConfirmStep)
                    comboConfirm = ""
                else
                    comboDraft = ""

                updateComboDisplay()
                return
            }

            if (comboConfirmStep) {
                comboConfirmStep = false
                comboConfirm = ""
                updateComboDisplay()
                return
            }

            flowMode = "localPassword"
            localPasswordVerified = false
            return
        }

        appendComboToken(action)
    }

    /*
        ============================================================
                            LOGIN LOGIC
        ============================================================
    */

    function setSelectedUser(index) {
        try {
            if (!userBackend || !userBackend.users || userBackend.users.length <= 0)
                return

            selectedUser = Math.max(0, Math.min(userBackend.users.length - 1, index))
        } catch (e) {
            selectedUser = 0
        }

        refreshEnrollmentState()
        forceActiveFocus()
    }

    function selectFocused() {
        if (isLockedOut() || loginSuccess)
            return

        if (firstLoginRequired && !localPasswordVerified) {
            flowMode = "localPassword"
            statusText = "Enter local account password"
            Qt.callLater(openLocalPasswordKeyboard)
            passwordInput.forceActiveFocus()
            return
        }

        if (!cardArmed) {
            armCard()
            return
        }

        if (primaryGuardActive)
            return

        safeArmedPrimaryPulse()
    }

    function armCard() {
        refreshSecurity()

        if (isLockedOut() || loginSuccess)
            return

        if (firstLoginRequired && !localPasswordVerified) {
            flowMode = "localPassword"
            statusText = "Enter local account password"
            Qt.callLater(openLocalPasswordKeyboard)
            passwordInput.forceActiveFocus()
            return
        }

        cardArmed = true
        setControllerLowLatencyMode(true)
        cancelBufferedComboVerification()
        inputBuffer = ""
        inputTokens = []
        errorText = ""
        statusText = "Sequence gate armed"

        /* ControllerManager already de-duplicates the physical arm press. */
        primaryGuardActive = false
        primaryGuardTimer.stop()

        if (typeof userCard.forceActiveFocus === "function")
            userCard.forceActiveFocus()

        forceActiveFocus()
    }

    function disarmCard() {
        if(clockBackend)clockBackend.cancelLockscreenTimezoneRequest()
        lockscreenFocus="user"
        if (loginSuccess)
            return

        cardArmed = false
        setControllerLowLatencyMode(false)
        cancelBufferedComboVerification()
        inputBuffer = ""
        inputTokens = []
        primaryGuardActive = false
        homeTapCount = 0
        statusText = firstLoginRequired ? "First login required" : "Profile ready"
        forceActiveFocus()
    }

    function safeArmedPrimaryPulse() {
        nudgeUserCard("X")
    }

    function nudgeUserCard(key) {
        if (typeof userCard.nudge === "function")
            userCard.nudge(key)
    }

    function setControllerLowLatencyMode(enabled) {
        try {
            if (controllerBackend &&
                    typeof controllerBackend.setLowLatencyInputMode === "function") {
                controllerBackend.setLowLatencyInputMode(enabled === true)
            }
        } catch (error) {
            console.log("LoginScreen low-latency controller mode error:", error)
        }
    }

    function submitLocalPassword() {
        if (localPasswordText.length <= 0) {
            errorText = "Enter the local account password."
            return
        }

        if (!verifyLocalPassword(currentUsername(), localPasswordText)) {
            localPasswordText = ""
            passwordInput.text = ""
            errorText = "Incorrect local account password"

            var nowLocked = registerFailedAttempt()

            if (nowLocked || isLockedOut()) {
                flowMode = "locked"
                cardArmed = false
            }

            return
        }

        localPasswordVerified = true
        localPasswordText = ""
        passwordInput.text = ""
        errorText = ""
        flowMode = "createCombo"
        statusText = "Create controller combo"
        comboDraft = ""
        comboConfirm = ""
        comboConfirmStep = false
        resetComboDuplicateGuard()
        lastComboConfirmPrimaryMs = 0
        updateComboDisplay()
        forceActiveFocus()
    }

    function cancelLocalPassword() {
        localPasswordText = ""
        passwordInput.text = ""
        errorText = ""
        flowMode = "localPassword"
        statusText = "First login required"
        forceActiveFocus()
    }

    function appendPasswordKey(value) {
        localPasswordText += String(value || "")
        passwordInput.text = localPasswordText
        passwordInput.cursorPosition = passwordInput.text.length
        passwordInput.forceActiveFocus()
    }

    function updateComboDisplay() {
        var combo = comboConfirmStep ? comboConfirm : comboDraft

        if (combo.length <= 0) {
            comboDisplayText = ""
            return
        }

        comboDisplayText = combo
    }

    function confirmComboStep() {
        if (!comboConfirmStep) {
            if (comboInputCount(comboDraft) < 4) {
                errorText = "Combo must use at least 4 inputs."
                return
            }

            comboConfirmStep = true
            comboConfirm = ""
            errorText = ""
            statusText = "Confirm controller combo"
            updateComboDisplay()
            return
        }

        if (!comboMatches()) {
            errorText = "Combos did not match. Create it again."
            comboDraft = ""
            comboConfirm = ""
            comboConfirmStep = false
            resetComboDuplicateGuard()
            statusText = "Create controller combo"
            updateComboDisplay()
            return
        }

        if (!createLoginCombo(currentUsername(), comboDraft)) {
            if (errorText.length <= 0)
                errorText = "Could not save login combo."

            return
        }

        firstLoginRequired = false
        localPasswordVerified = false
        flowMode = "combo"
        statusText = "Combo created"
        errorText = ""
        comboDraft = ""
        comboConfirm = ""
        comboConfirmStep = false
        updateComboDisplay()

        if (securityCoreBackend && !securityCoreBackend.recoveryConfigured &&
                securityCoreBackend.recoveryDeferred !== true) {
            recoverySetupVisible = true
            statusText = "Create physical recovery key"
            forceActiveFocus()
            return
        }

        triggerUnlock()
    }

    function failedAttempt() {
        cancelBufferedComboVerification()
        inputBuffer = ""
        inputTokens = []

        var nowLocked = registerFailedAttempt()

        if (nowLocked || isLockedOut()) {
            cardArmed = false
            flowMode = "locked"
            statusText = "Access suspended"

            if (typeof userCard.startLockoutAnimation === "function")
                userCard.startLockoutAnimation()
        } else {
            errorText = "Incorrect combo"

            if (typeof userCard.startErrorAnimation === "function")
                userCard.startErrorAnimation()
        }
    }

    function triggerUnlock() {
        if (loginSuccess)
            return

        cancelBufferedComboVerification(false)
        loginSuccess = true
        cardArmed = false
        setControllerLowLatencyMode(false)
        inputTokens = []
        inputBuffer = ""
        primaryGuardActive = false
        homeTapCount = 0
        errorText = ""
        statusText = "Console opening"

        screenOpacity = 1.0
        unlockCardScale = 1.0
        unlockCardOpacity = 1.0
        unlockStageScale = 1.0
        unlockRippleScale = 0.20
        unlockRippleOpacity = 0.0

        circularStage.scale = 1.0
        unlockPulseFinishedEmitted = false

        // Authentication is emitted exactly once now. Main.qml prepares the
        // Dashboard while this short pulse runs, then waits for its signal
        // before requesting the lockscreen texture capture.
        authenticationPulseAnimation.restart()
        finishUnlock()
    }

    function finishUnlock() {
        if (unlockEmitted)
            return

        unlockEmitted = true
        registerSuccess()

        unlocked(currentUser())
    }

    function registerHomeTap() {
        if (!cardArmed || isLockedOut() || loginSuccess)
            return

        homeTapCount++
        homeTapResetTimer.restart()

        if (homeTapCount >= 5) {
            triggerMercuryEdition()
            homeTapCount = 0
        }
    }

    function triggerMercuryEdition() {
        mercuryPopupVisible = true
        mercuryPopupTimer.restart()
    }

    /*
        ============================================================
                            FORMAT HELPERS
        ============================================================
    */

    function greetingPrefix() {
        var h = new Date().getHours()

        if (h < 12)
            return "Good Morning,"

        if (h < 18)
            return "Good Afternoon,"

        return "Good Evening,"
    }

    function formatTime(seconds) {
        var s = Math.max(0, seconds)
        var m = Math.floor(s / 60)
        var r = s % 60

        return m + ":" + (r < 10 ? "0" + r : r)
    }

    function isPsControllerConnected() {
        try {
            if (!controllerBackend)
                return false

            if (!controllerBackend.controllerConnected)
                return false

            var name = String(controllerBackend.controllerName || "").toLowerCase()

            return name.indexOf("wireless controller") >= 0 ||
                   name.indexOf("dualshock") >= 0 ||
                   name.indexOf("dualsense") >= 0 ||
                   name.indexOf("playstation") >= 0 ||
                   name.indexOf("sony") >= 0
        } catch (e) {
            return false
        }
    }

    function controllerBatteryPercent() {
        try {
            if (!controllerBackend)
                return -1

            if (controllerBackend.controllerBatteryAvailable !== undefined &&
                    !controllerBackend.controllerBatteryAvailable)
                return -1

            if (controllerBackend.controllerBatteryPercent !== undefined) {
                var pct = Number(controllerBackend.controllerBatteryPercent)

                if (pct < 0)
                    return -1

                return Math.max(0, Math.min(100, pct))
            }

            if (controllerBackend.batteryPercent !== undefined) {
                var oldPct = Number(controllerBackend.batteryPercent)

                if (oldPct < 0)
                    return -1

                return Math.max(0, Math.min(100, oldPct))
            }
        } catch (e) {
            return -1
        }

        return -1
    }

    function batteryLitBars() {
        var pct = controllerBatteryPercent()

        if (pct < 0)
            return 0

        return Math.max(0, Math.min(5, Math.ceil(pct / 20)))
    }

    Connections {
        target: login.securityBackend
        ignoreUnknownSignals: true

        function onLoginComboVerificationFinished(success,
                                                   message,
                                                   failedAttempts,
                                                   secondsRemaining) {
            var submittedSession = login.comboVerificationSubmittedSession
            var submittedCount = login.comboVerificationSubmittedCount

            login.comboVerificationPending = false

            if (submittedSession !== login.comboVerificationSession ||
                    login.loginSuccess ||
                    !login.cardArmed) {
                return
            }

            login.handleComboVerificationResult(
                success,
                message,
                submittedCount,
                Number(secondsRemaining || 0)
            )
        }
    }

    Connections {
        target: login.securityBackend
        ignoreUnknownSignals: true

        function onStateChanged() {
            if (login.lockoutSyncInProgress)
                return

            if (login.isLockedOut()) {
                login.flowMode = "locked"
                login.cardArmed = false
                login.statusText = "Access suspended"
                return
            }

            if (login.flowMode === "locked") {
                login.lockoutSyncInProgress = true
                login.refreshEnrollmentState()
                login.lockoutSyncInProgress = false
            }
        }

        function onLoginConfigurationStateChanged() {
            login.refreshEnrollmentState()
        }
    }

    Connections {
        target: login.controllerBackend
        ignoreUnknownSignals: true

        function onControllerConnectedChanged() {
            if (!login.controllerBackend ||
                    !login.controllerBackend.controllerConnected)
                return

            if (typeof login.controllerBackend.refreshBattery === "function")
                login.controllerBackend.refreshBattery()
        }
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================
    */

    Keys.onPressed: function(event) {
        if (event.isAutoRepeat)
            return

        if (flowMode === "localPassword")
            return

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

        if (event.key === Qt.Key_Home ||
                event.key === Qt.Key_F12) {
            handleControllerPressed("home")
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
    }


    /* Patch 17 logout-to-login cleanup contract. */
    function resetForNewSession() {
        mercuryPopupTimer.stop()
        homeTapResetTimer.stop()
        primaryGuardTimer.stop()
        authenticationPulseAnimation.stop()
        closeLocalPasswordKeyboard()


        loginSuccess = false
        unlockEmitted = false
        unlockPulseFinishedEmitted = false
        cardArmed = false
        inputBuffer = ""
        inputTokens = []
        comboDraft = ""
        comboConfirm = ""
        comboConfirmStep = false
        comboDisplayText = ""
        localPasswordText = ""
        typedPasswordMask = ""
        primaryGuardActive = false
        homeTapCount = 0
        mercuryPopupVisible = false
        recoverySetupVisible = false
        errorText = ""
        screenOpacity = 1.0
        unlockCardScale = 1.0
        unlockCardOpacity = 1.0
        unlockStageScale = 1.0
        unlockRippleScale = 0.25
        unlockRippleOpacity = 0.0
        active = true

        refreshEnrollmentState()
        statusText = isLockedOut() ? "Access suspended" : "Profile ready"

        Qt.callLater(function() {
            login.forceActiveFocus()
            try {
                if (typeof userCard.forceActiveFocus === "function")
                    userCard.forceActiveFocus()
            } catch (e2) {}
        })
    }

    function prepareForUnload() {
        if(clockBackend)clockBackend.cancelLockscreenTimezoneRequest()
        lockscreenFocus="user"
        mercuryPopupTimer.stop()
        homeTapResetTimer.stop()
        primaryGuardTimer.stop()
        authenticationPulseAnimation.stop()
        closeLocalPasswordKeyboard()
        active = false
        inputTokens = []
        inputBuffer = ""
        localPasswordText = ""
        typedPasswordMask = ""
    }

    RecoverySetupWizard {
        id: recoverySetupWizard
        anchors.fill: parent
        backend: login.securityCoreBackend
        open: login.recoverySetupVisible
        onCompleted: function(skipped) {
            login.recoverySetupVisible = false
            login.statusText = skipped === true
                    ? "Recovery deferred · minimum security"
                    : "Recovery key enrolled"
            login.triggerUnlock()
        }
    }

    // Shared with Console Help so the same instructions remain available manually.
    Modals.LoginInstructionsModal {
        id: loginInstructionsModal
        onAcknowledged: {
            if (!login.setupBackend || !login.setupBackend.acknowledgeLoginInstructions()) {
                login.errorText = login.setupBackend
                        ? String(login.setupBackend.lastError || "Acknowledgement could not be saved")
                        : "Acknowledgement service unavailable"
            }
        }
        onClosed: login.forceActiveFocus()
    }

    Connections {
        target: login.setupBackend
        ignoreUnknownSignals: true
        function onSetupCompleted() { Qt.callLater(login.maybeOpenLoginInstructions) }
        function onSetupStateChanged() { Qt.callLater(login.maybeOpenLoginInstructions) }
    }

    Component.onDestruction: login.prepareForUnload()

    Component.onCompleted: {
        /*
            Defer the first presentation decision until every C++ context
            property has completed construction.  This prevents the retained
            login surface from rendering a lockout based on transitional startup
            values while SecurityManager is loading the active account.
        */
        Qt.callLater(function() {
            refreshEnrollmentState()
            forceActiveFocus()

            if (typeof userCard.forceActiveFocus === "function")
                userCard.forceActiveFocus()

            if (flowMode === "localPassword") {
                Qt.callLater(openLocalPasswordKeyboard)
                passwordInput.forceActiveFocus()
            }
            maybeOpenLoginInstructions()
        })
    }
}
