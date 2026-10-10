import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: visibleMode
    enabled: visibleMode
    focus: visibleMode
    z: 90

    property bool visibleMode: false
    property string mode: ""
    property string fieldKind: ""
    property string modalTitle: "SETTINGS"
    property string modalSubtitle: ""
    property string currentValue: ""
    property string displayValue: ""
    property bool secretValue: false
    property string activeUsername: ""
    property string statusText: ""
    property bool statusError: false

    property string usernameDraft: ""
    property string passwordDraft: ""
    property string displayNameDraft: ""
    property bool administratorDraft: false
    property int selectedRow: 0

    property int comboStage: 0
    property int comboMenuIndex: 0
    property int recoveryMenuIndex: 0
    property string currentComboDraft: ""
    property string newComboDraft: ""
    property string confirmComboDraft: ""
    property bool recoveryChange: false
    property bool comboBusy: false
    property bool recoveryConfigured: false
    property string recoveryMethod: "none"
    property bool recoveryUsbPresent: false
    property int minimumComboLength: 4
    property int maximumComboLength: 15
    property int maximumRollingInputs: 15
    property bool loginComboConfigured: true
    property bool initialComboCreation: false

    property color chromeColor: "#030810"
    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color panelInset: "#06101F"
    property color focusBlue: "#4DA6FF"
    property color neutronCyan: "#7DF9FF"
    property color successGreen: "#22FF88"
    property color warningGold: "#F5C542"
    property color dangerRed: "#FF3040"
    property color purple: "#B75CFF"
    property color textWhite: "#F4FBFF"
    property color mutedText: "#8AA6C8"

    signal closed()
    signal keyboardRequested(string target, string initialValue, string title)
    signal createUserRequested(string username, string displayName, string password, bool administrator)
    signal comboVerificationRequested(string combo)
    signal comboCreationRequested(string newCombo, string confirmation)
    signal comboChangeRequested(string currentCombo, string newCombo, string confirmation, bool recovery)
    signal usbRecoveryRequested()
    signal recoveryCodeRequested(string code)

    readonly property var addUserRows: [
        { key: "username", title: "USER", detail: "Lowercase Linux username", value: usernameDraft.length > 0 ? usernameDraft : "REQUIRED" },
        { key: "password", title: "PASS", detail: "Minimum 8 characters", value: passwordDraft.length > 0 ? "••••••••" : "REQUIRED" },
        { key: "role", title: "ROLE", detail: "Standard user or administrator", value: administratorDraft ? "ADMINISTRATOR" : "STANDARD USER" },
        { key: "customization", title: "CUSTOMIZATION", detail: "Initial display name. Full icon, color and tagline controls remain in User Settings after sign-in.", value: displayNameDraft.length > 0 ? displayNameDraft : "DEFAULT PROFILE" },
        { key: "create", title: "CREATE LOCAL USER", detail: "Create the Linux account with the selected role", value: "X  CREATE" }
    ]

    function openText(kind, titleText, subtitleText, valueText, secret) {
        mode = "text"
        fieldKind = String(kind || "")
        modalTitle = String(titleText || "EDIT SETTING").toUpperCase()
        modalSubtitle = String(subtitleText || "")
        currentValue = String(valueText || "")
        displayValue = secret === true ? "••••••••" : currentValue
        secretValue = secret === true
        statusText = "ENTER A NEW VALUE"
        statusError = false
        visibleMode = true
        forceActiveFocus()
    }

    function openAddUser() {
        mode = "addUser"
        modalTitle = "ADD LOCAL USER"
        modalSubtitle = "Create a local NeutronOS/Linux account"
        usernameDraft = ""
        passwordDraft = ""
        displayNameDraft = ""
        administratorDraft = false
        selectedRow = 0
        statusText = "COMPLETE USER, PASS, ROLE AND CUSTOMIZATION"
        statusError = false
        visibleMode = true
        forceActiveFocus()
        Qt.callLater(function() {
            root.keyboardRequested("phase1UserName", "", "New Username")
        })
    }

    function openCombo(configured, method, minLength, maxLength, rollingMax) {
        mode = "combo"
        modalTitle = "CONTROLLER UNLOCK COMBINATION"
        modalSubtitle = "Replace the active user's controller-first login credential"
        recoveryConfigured = configured === true
        recoveryMethod = String(method || "none")
        minimumComboLength = Math.max(1, Number(minLength || 4))
        maximumComboLength = Math.max(minimumComboLength, Number(maxLength || 15))
        maximumRollingInputs = Math.max(maximumComboLength, Number(rollingMax || 15))
        initialComboCreation = loginComboConfigured !== true
        comboStage = initialComboCreation ? 2 : 0
        comboMenuIndex = 0
        recoveryMenuIndex = 0
        currentComboDraft = ""
        newComboDraft = ""
        confirmComboDraft = ""
        recoveryChange = false
        comboBusy = false
        statusText = initialComboCreation
                   ? "NO CONTROLLER PASSCODE IS SET — CREATE A NEW PASSCODE"
                   : "CURRENT PASSCODE IS REQUIRED UNLESS RECOVERY IS VERIFIED"
        statusError = false
        visibleMode = true
        forceActiveFocus()
    }

    function closeModal() {
        if (!visibleMode)
            return
        passwordDraft = ""
        currentComboDraft = ""
        newComboDraft = ""
        confirmComboDraft = ""
        comboBusy = false
        visibleMode = false
        closed()
    }

    function updateKeyboardPreview(target, value) {
        if (!visibleMode)
            return
        if (target === "phase1UserName") usernameDraft = String(value || "")
        else if (target === "phase1UserPassword") passwordDraft = String(value || "")
        else if (target === "phase1UserDisplay") displayNameDraft = String(value || "")
        else if (mode === "text" && target === fieldKind)
            displayValue = secretValue ? (String(value || "").length > 0 ? "••••••••" : "") : String(value || "")
    }

    function acceptKeyboard(target, value) {
        var text = String(value || "")
        if (target === "phase1UserName") {
            usernameDraft = text.trim()
            selectedRow = 1
            Qt.callLater(function() { root.keyboardRequested("phase1UserPassword", "", "New User Password") })
            return true
        }
        if (target === "phase1UserPassword") {
            passwordDraft = text
            selectedRow = 2
            statusText = "CHOOSE ROLE, THEN OPTIONAL CUSTOMIZATION"
            statusError = false
            return true
        }
        if (target === "phase1UserDisplay") {
            displayNameDraft = text.trim().substring(0, 64)
            selectedRow = 4
            statusText = "ACCOUNT IS READY TO CREATE"
            statusError = false
            return true
        }
        return false
    }

    function setTextResult(success, message, shownValue) {
        statusText = String(message || (success ? "SETTING UPDATED" : "SETTING COULD NOT BE UPDATED"))
        statusError = !success
        if (success && secretValue !== true && shownValue !== undefined)
            displayValue = String(shownValue || "")
    }

    function setUserCreateResult(success, message) {
        statusText = String(message || (success ? "USER ACCOUNT CREATED" : "USER ACCOUNT COULD NOT BE CREATED"))
        statusError = !success
        passwordDraft = ""
        if (success)
            selectedRow = 4
    }

    function comboTokenCount(value) {
        var text = String(value || "").trim()
        if (text.length <= 0)
            return 0
        return text.split("|").filter(function(v) { return String(v).length > 0 }).length
    }

    function tokenForAction(action) {
        var a = String(action || "").toLowerCase()
        // X, Circle, Options and Share are modal controls while capturing.
        if (a === "context") return "TRIANGLE"
        if (a === "secondary") return "SQUARE"
        if (a === "home") return "SYSTEM"
        if (a === "up") return "UP"
        if (a === "down") return "DOWN"
        if (a === "left") return "LEFT"
        if (a === "right") return "RIGHT"
        if (a === "l1") return "L1"
        if (a === "r1") return "R1"
        if (a === "l2") return "L2"
        if (a === "r2") return "R2"
        if (a === "l3") return "L3"
        if (a === "r3") return "R3"
        return ""
    }

    function currentCaptureValue() {
        if (comboStage === 1) return currentComboDraft
        if (comboStage === 2) return newComboDraft
        if (comboStage === 3) return confirmComboDraft
        return ""
    }

    function setCurrentCaptureValue(value) {
        if (comboStage === 1) currentComboDraft = value
        else if (comboStage === 2) newComboDraft = value
        else if (comboStage === 3) confirmComboDraft = value
    }

    function appendComboToken(action) {
        var token = tokenForAction(action)
        if (token.length <= 0)
            return false
        var current = currentCaptureValue()
        var count = comboTokenCount(current)
        var limit = comboStage === 1 ? maximumRollingInputs : maximumComboLength
        if (count >= limit) {
            statusText = "MAXIMUM INPUT LENGTH REACHED"
            statusError = true
            return true
        }
        setCurrentCaptureValue(current.length > 0 ? current + "|" + token : token)
        statusText = "CAPTURED " + (count + 1) + " / " + limit + " INPUTS"
        statusError = false
        return true
    }

    function clearCapture() {
        setCurrentCaptureValue("")
        statusText = "CAPTURE CLEARED"
        statusError = false
    }

    function removeLastCapture() {
        var value = currentCaptureValue()
        var parts = String(value || "").split("|").filter(function(v) { return String(v).length > 0 })
        if (parts.length <= 0) {
            statusText = "NO CAPTURED INPUTS TO DELETE"
            statusError = false
            return
        }
        parts.pop()
        setCurrentCaptureValue(parts.join("|"))
        statusText = "REMOVED LAST INPUT • " + parts.length + " INPUTS REMAIN"
        statusError = false
    }

    function submitCapture() {
        if (comboBusy)
            return
        var value = currentCaptureValue()
        var count = comboTokenCount(value)
        if (comboStage === 1) {
            if (count < 1) {
                statusText = "ENTER THE CURRENT CONTROLLER PASSCODE"
                statusError = true
                return
            }
            comboBusy = true
            statusText = "VERIFYING CURRENT CONTROLLER PASSCODE…"
            statusError = false
            comboVerificationRequested(value)
            return
        }
        if (count < minimumComboLength || count > maximumComboLength) {
            statusText = "NEW PASSCODE MUST USE " + minimumComboLength + "–" + maximumComboLength + " INPUTS"
            statusError = true
            return
        }
        if (comboStage === 2) {
            comboStage = 3
            confirmComboDraft = ""
            statusText = "RE-ENTER THE NEW CONTROLLER PASSCODE"
            statusError = false
            return
        }
        if (comboStage === 3) {
            if (newComboDraft !== confirmComboDraft) {
                confirmComboDraft = ""
                statusText = "PASSCODES DID NOT MATCH — CONFIRM AGAIN"
                statusError = true
                return
            }
            comboBusy = true
            statusText = initialComboCreation
                       ? "CREATING CONTROLLER PASSCODE…"
                       : "REPLACING CONTROLLER PASSCODE…"
            statusError = false
            if (initialComboCreation)
                comboCreationRequested(newComboDraft, confirmComboDraft)
            else
                comboChangeRequested(recoveryChange ? "" : currentComboDraft,
                                     newComboDraft,
                                     confirmComboDraft,
                                     recoveryChange)
        }
    }

    function comboVerificationResult(success, message) {
        comboBusy = false
        statusText = String(message || (success ? "CURRENT PASSCODE VERIFIED" : "CURRENT PASSCODE REJECTED"))
        statusError = !success
        if (success) {
            comboStage = 2
            recoveryChange = false
            newComboDraft = ""
            confirmComboDraft = ""
            statusText = "CURRENT PASSCODE VERIFIED — CREATE A NEW PASSCODE"
        } else {
            currentComboDraft = ""
        }
    }

    function comboCreationResult(success, message) {
        comboBusy = false
        currentComboDraft = ""
        newComboDraft = ""
        confirmComboDraft = ""
        statusText = String(message || (success ? "CONTROLLER PASSCODE CREATED" : "CONTROLLER PASSCODE WAS NOT CREATED"))
        statusError = !success
        if (success)
            loginComboConfigured = true
        comboStage = 7
    }

    function comboChangeResult(success, message) {
        comboBusy = false
        currentComboDraft = ""
        newComboDraft = ""
        confirmComboDraft = ""
        statusText = String(message || (success ? "CONTROLLER PASSCODE REPLACED" : "CONTROLLER PASSCODE WAS NOT CHANGED"))
        statusError = !success
        comboStage = 7
    }

    function recoveryAllowsUsb() {
        var method = String(recoveryMethod || "").toLowerCase()
        return method.indexOf("usb") >= 0 || method.indexOf("drive") >= 0 || method.indexOf("both") >= 0
    }

    function recoveryAllowsCode() {
        var method = String(recoveryMethod || "").toLowerCase()
        return method.indexOf("code") >= 0 || method.indexOf("both") >= 0
    }

    function beginForgotFlow() {
        if (!recoveryConfigured) {
            statusText = "RECOVERY IS NOT ENABLED. THE CURRENT CONTROLLER PASSCODE IS REQUIRED."
            statusError = true
            return
        }
        comboStage = 4
        recoveryMenuIndex = recoveryAllowsUsb() ? 0 : 1
        statusText = "VERIFY AN ENROLLED RECOVERY METHOD"
        statusError = false
    }

    function requestRecoveryCodeKeyboard() {
        comboStage = 6
        statusText = "ENTER THE ENROLLED RECOVERY CODE"
        statusError = false
        keyboardRequested("phase1RecoveryCode", "", "Recovery Code")
    }

    function recoveryVerificationResult(success, message) {
        comboBusy = false
        statusText = String(message || (success ? "RECOVERY VERIFIED" : "RECOVERY VERIFICATION FAILED"))
        statusError = !success
        if (success) {
            recoveryChange = true
            currentComboDraft = ""
            newComboDraft = ""
            confirmComboDraft = ""
            comboStage = 2
            statusText = "RECOVERY VERIFIED — CREATE A NEW CONTROLLER PASSCODE"
        } else if (comboStage === 6) {
            comboStage = 4
        }
    }

    function handleControllerPressed(action) {
        if (!visibleMode)
            return false
        var a = String(action || "").toLowerCase()

        if (mode === "text") {
            if (a === "cancel" || a === "system") {
                closeModal()
                return true
            }
            if (a === "primary") {
                keyboardRequested(fieldKind, secretValue ? "" : currentValue, modalTitle)
                return true
            }
            return true
        }

        if (mode === "addUser") {
            if (a === "cancel") { closeModal(); return true }
            if (a === "up") selectedRow = Math.max(0, selectedRow - 1)
            else if (a === "down") selectedRow = Math.min(addUserRows.length - 1, selectedRow + 1)
            else if ((a === "left" || a === "right") && selectedRow === 2)
                administratorDraft = !administratorDraft
            else if (a === "primary") {
                var key = addUserRows[selectedRow].key
                if (key === "username") keyboardRequested("phase1UserName", usernameDraft, "New Username")
                else if (key === "password") keyboardRequested("phase1UserPassword", "", "New User Password")
                else if (key === "role") administratorDraft = !administratorDraft
                else if (key === "customization") keyboardRequested("phase1UserDisplay", displayNameDraft, "New User Display Name")
                else if (key === "create") {
                    if (usernameDraft.trim().length <= 0 || passwordDraft.length < 8) {
                        statusText = "USER AND AN 8-CHARACTER PASSWORD ARE REQUIRED"
                        statusError = true
                    } else {
                        createUserRequested(usernameDraft.trim(), displayNameDraft.trim(), passwordDraft, administratorDraft)
                    }
                }
            }
            return true
        }

        if (mode !== "combo")
            return true

        // Circle is always the close action for the controller-passcode modal.
        if (a === "cancel") {
            closeModal()
            return true
        }

        if (comboStage === 0) {
            if (a === "up" || a === "down") {
                comboMenuIndex = comboMenuIndex === 0 ? 1 : 0
            } else if (a === "primary" || a === "system") {
                if (comboMenuIndex === 0) {
                    comboStage = 1
                    currentComboDraft = ""
                    recoveryChange = false
                    statusText = "ENTER CURRENT PASSCODE • X / OPTIONS ENTER • SHARE DELETE • CIRCLE CLOSE"
                    statusError = false
                } else {
                    beginForgotFlow()
                }
            }
            return true
        }

        if (comboStage >= 1 && comboStage <= 3) {
            // X and Options submit. Neither can become a passcode token.
            if (a === "primary" || a === "system") {
                submitCapture()
                return true
            }
            // Share removes only the last input so a long sequence does not need to be re-entered.
            if (a === "quick" || a === "share" || a === "select" || a === "create" || a === "capture") {
                removeLastCapture()
                return true
            }
            if (!comboBusy)
                appendComboToken(a)
            return true
        }

        if (comboStage === 4) {
            if (a === "up" || a === "down") {
                recoveryMenuIndex = recoveryMenuIndex === 0 ? 1 : 0
            } else if (a === "primary" || a === "system") {
                if (recoveryMenuIndex === 0) {
                    if (!recoveryAllowsUsb()) {
                        statusText = "USB RECOVERY IS NOT ENROLLED FOR THIS SYSTEM"
                        statusError = true
                    } else {
                        comboStage = 5
                        comboBusy = false
                        statusText = recoveryUsbPresent
                                   ? "RECOVERY DRIVE DETECTED — VERIFYING…"
                                   : "WAITING FOR THE ENROLLED RECOVERY DRIVE…"
                        statusError = false
                        if (recoveryUsbPresent) {
                            comboBusy = true
                            usbRecoveryRequested()
                        }
                    }
                } else {
                    if (!recoveryAllowsCode()) {
                        statusText = "RECOVERY CODE IS NOT ENROLLED FOR THIS SYSTEM"
                        statusError = true
                    } else {
                        requestRecoveryCodeKeyboard()
                    }
                }
            }
            return true
        }

        if (comboStage === 5) {
            if ((a === "primary" || a === "system") && !comboBusy) {
                if (!recoveryUsbPresent) {
                    statusText = "WAITING FOR THE ENROLLED RECOVERY DRIVE…"
                    statusError = false
                } else {
                    comboBusy = true
                    statusText = "VERIFYING ENROLLED RECOVERY DRIVE…"
                    statusError = false
                    usbRecoveryRequested()
                }
            }
            return true
        }

        if (comboStage === 6)
            return true

        if (comboStage === 7) {
            if (a === "primary" || a === "system")
                closeModal()
            return true
        }
        return true
    }

    Timer {
        id: recoveryDriveWaitTimer
        interval: 900
        repeat: true
        running: root.visibleMode && root.mode === "combo" && root.comboStage === 5
        onTriggered: {
            if (root.recoveryUsbPresent && !root.comboBusy) {
                root.comboBusy = true
                root.statusText = "RECOVERY DRIVE DETECTED — VERIFYING…"
                root.statusError = false
                root.usbRecoveryRequested()
            }
        }
    }

    Rectangle { anchors.fill: parent; color: "#E602060D" }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 92, 1260)
        height: mode === "addUser" ? Math.min(parent.height - 74, 820) : Math.min(parent.height - 84, 760)
        radius: 30
        color: root.panelColor
        border.width: 2
        border.color: root.focusBlue
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 118
            color: root.chromeColor
            border.width: 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#25313C"
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                width: 66
                height: 66
                radius: 19
                color: "#102943"
                border.width: 1
                border.color: root.neutronCyan
                Text {
                    anchors.centerIn: parent
                    text: mode === "combo" ? "◇" : mode === "addUser" ? "+" : "✎"
                    color: root.neutronCyan
                    font.pixelSize: 27
                    font.bold: true
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 116
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    width: parent.width
                    text: root.modalTitle
                    color: root.textWhite
                    font.pixelSize: 27
                    font.bold: true
                    font.letterSpacing: 1.0
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.modalSubtitle
                    color: root.mutedText
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 118
            anchors.bottom: statusPanel.top
            anchors.bottomMargin: 16

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14
                visible: root.mode === "text"

                Text {
                    width: parent.width
                    text: root.secretValue ? "ACTIVE LOCAL ACCOUNT PASSWORD" : "CURRENT VALUE"
                    color: root.mutedText
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 1.2
                }
                Rectangle {
                    width: parent.width
                    height: 126
                    radius: 14
                    color: "#081522"
                    border.width: 1
                    border.color: "#203847"
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.displayValue.length > 0 ? root.displayValue : "NOT SET"
                        color: root.textWhite
                        font.pixelSize: 25
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
                Text {
                    width: parent.width
                    text: root.secretValue
                          ? "The new password is held only for the active operation and is not retained in Settings UI state after submission."
                          : "The value is applied only after you confirm the entry."
                    color: root.mutedText
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
            }

            ListView {
                id: userList
                anchors.fill: parent
                anchors.margins: 28
                visible: root.mode === "addUser"
                spacing: 10
                clip: true
                model: root.addUserRows
                currentIndex: root.selectedRow
                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    height: index === 3 ? 116 : 94
                    radius: 14
                    color: index === root.selectedRow ? "#0D263A" : "#081522"
                    border.width: index === root.selectedRow ? 2 : 1
                    border.color: index === root.selectedRow ? root.focusBlue : "#203847"
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: parent.height - 26
                        radius: 3
                        color: index === root.selectedRow ? root.focusBlue : "#263B48"
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 32
                        anchors.right: valueText.left
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Text { width: parent.width; text: modelData.title; color: root.textWhite; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: modelData.detail; color: root.mutedText; font.pixelSize: 13; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                    Text {
                        id: valueText
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(360, implicitWidth)
                        text: modelData.value
                        color: index === 4 ? root.successGreen : root.neutronCyan
                        font.pixelSize: 15
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: 28
                visible: root.mode === "combo"

                Column {
                    anchors.fill: parent
                    spacing: 14
                    visible: root.comboStage === 0

                    Text { width: parent.width; text: "Choose how to authorize the controller-passcode change."; color: root.mutedText; font.pixelSize: 15; wrapMode: Text.WordWrap }
                    Repeater {
                        model: [
                            { title: "USE CURRENT CONTROLLER PASSCODE", detail: "Verify the existing controller credential before creating a replacement.", value: "X / OPTIONS  CONTINUE" },
                            { title: "FORGOT PASSCODE", detail: root.recoveryConfigured ? "Use the enrolled recovery code or recovery drive. The old passcode is not required after recovery verifies." : "Unavailable because no recovery method is enrolled.", value: root.recoveryConfigured ? "X / OPTIONS  RECOVERY" : "NOT AVAILABLE" }
                        ]
                        Rectangle {
                            required property int index
                            required property var modelData
                            width: parent.width
                            height: 138
                            radius: 14
                            color: index === root.comboMenuIndex ? "#0D263A" : "#081522"
                            border.width: index === root.comboMenuIndex ? 2 : 1
                            border.color: index === root.comboMenuIndex ? (index === 1 && !root.recoveryConfigured ? root.warningGold : root.focusBlue) : "#203847"
                            opacity: index === 1 && !root.recoveryConfigured ? 0.72 : 1.0
                            Column {
                                anchors.left: parent.left; anchors.leftMargin: 24
                                anchors.right: valueText.left; anchors.rightMargin: 20
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Text { width: parent.width; text: modelData.title; color: root.textWhite; font.pixelSize: 19; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.detail; color: root.mutedText; font.pixelSize: 14; wrapMode: Text.WordWrap; maximumLineCount: 3 }
                            }
                            Text { id: valueText; anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; text: modelData.value; color: index === 1 && !root.recoveryConfigured ? root.warningGold : root.neutronCyan; font.pixelSize: 14; font.bold: true }
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 116
                        radius: 14
                        color: "#0A1A2F"
                        border.width: 1
                        border.color: "#1D3958"
                        Text {
                            anchors.fill: parent
                            anchors.margins: 20
                            text: root.recoveryConfigured
                                  ? "Recovery enrolled: " + root.recoveryMethod.toUpperCase() + ". A successful recovery verification authorizes the secure replacement flow without requiring the old controller passcode."
                                  : "Recovery is not configured. NeutronOS will not offer a bypass path. The current controller passcode is required to replace it."
                            color: root.recoveryConfigured ? root.successGreen : root.warningGold
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Column {
                    anchors.fill: parent
                    spacing: 18
                    visible: root.comboStage >= 1 && root.comboStage <= 3

                    Text {
                        width: parent.width
                        text: root.comboStage === 1 ? "CURRENT CONTROLLER PASSCODE"
                              : root.comboStage === 2 ? "CREATE NEW CONTROLLER PASSCODE"
                              : "CONFIRM NEW CONTROLLER PASSCODE"
                        color: root.textWhite
                        font.pixelSize: 24
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: root.comboStage === 1
                              ? "Enter the current sequence exactly. It is verified before NeutronOS allows the replacement flow to continue."
                              : "Use controller inputs only. X or OPTIONS enters the captured sequence. SHARE removes the last input. Circle closes the modal."
                        color: root.mutedText
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        width: parent.width
                        height: 160
                        radius: 14
                        color: "#030810"
                        border.width: 2
                        border.color: root.comboBusy ? root.warningGold : root.focusBlue
                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            Repeater {
                                model: root.comboTokenCount(root.currentCaptureValue())
                                Rectangle {
                                    width: 30; height: 30; radius: 15
                                    color: root.neutronCyan
                                    opacity: 0.82
                                    border.width: 1
                                    border.color: "#D9F7FF"
                                }
                            }
                        }
                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 18
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.comboTokenCount(root.currentCaptureValue()) + " INPUTS CAPTURED"
                            color: root.mutedText
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.1
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 100
                        radius: 14
                        color: "#0A1A2F"
                        border.width: 1
                        border.color: "#1D3958"
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 40
                            text: root.comboStage === 1
                                  ? "X / OPTIONS  VERIFY     SHARE  DELETE     O / CIRCLE  CLOSE"
                                  : "X / OPTIONS  ENTER     SHARE  DELETE     O / CIRCLE  CLOSE"
                            color: root.neutronCyan
                            font.pixelSize: 13
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Column {
                    anchors.fill: parent
                    spacing: 14
                    visible: root.comboStage === 4
                    Text { text: "RECOVERY AUTHORIZATION"; color: root.textWhite; font.pixelSize: 24; font.bold: true }
                    Text { width: parent.width; text: "Only an already-enrolled recovery method can authorize a reset without the current controller passcode."; color: root.mutedText; font.pixelSize: 14; wrapMode: Text.WordWrap }
                    Repeater {
                        model: [
                            { title: "RECOVERY DRIVE", detail: root.recoveryAllowsUsb() ? "Insert the enrolled USB recovery drive. NeutronOS verifies it automatically when detected." : "No USB recovery drive is enrolled for this system.", value: root.recoveryAllowsUsb() ? "X / OPTIONS  WAIT" : "NOT ENROLLED" },
                            { title: "RECOVERY CODE", detail: root.recoveryAllowsCode() ? "Enter the enrolled recovery code." : "No recovery code is enrolled for this system.", value: root.recoveryAllowsCode() ? "X / OPTIONS  ENTER CODE" : "NOT ENROLLED" }
                        ]
                        Rectangle {
                            required property int index
                            required property var modelData
                            width: parent.width; height: 138; radius: 14
                            color: index === root.recoveryMenuIndex ? "#0D263A" : "#081522"
                            border.width: index === root.recoveryMenuIndex ? 2 : 1
                            border.color: index === root.recoveryMenuIndex ? root.focusBlue : "#203847"
                            Column {
                                anchors.left: parent.left; anchors.leftMargin: 24
                                anchors.right: valueText.left; anchors.rightMargin: 20
                                anchors.verticalCenter: parent.verticalCenter; spacing: 7
                                Text { width: parent.width; text: modelData.title; color: root.textWhite; font.pixelSize: 19; font.bold: true }
                                Text { width: parent.width; text: modelData.detail; color: root.mutedText; font.pixelSize: 14; wrapMode: Text.WordWrap }
                            }
                            Text { id: valueText; anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; text: modelData.value; color: root.neutronCyan; font.pixelSize: 14; font.bold: true }
                        }
                    }
                }

                Column {
                    anchors.fill: parent
                    spacing: 20
                    visible: root.comboStage === 5
                    Text { text: "WAITING FOR RECOVERY DRIVE"; color: root.textWhite; font.pixelSize: 24; font.bold: true }
                    Rectangle {
                        width: parent.width; height: 260; radius: 14
                        color: "#030810"; border.width: 2; border.color: root.neutronCyan
                        Column {
                            anchors.centerIn: parent; width: parent.width - 80; spacing: 18
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "USB"; color: root.neutronCyan; font.pixelSize: 42; font.bold: true }
                            Text { width: parent.width; text: "Insert the enrolled NeutronOS recovery drive. Only the recovery verification path is used; ordinary removable media does not authorize a controller-passcode reset."; color: root.mutedText; font.pixelSize: 15; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                            Text { width: parent.width; text: root.comboBusy ? "VERIFYING…" : (root.recoveryUsbPresent ? "DRIVE DETECTED" : "WAITING FOR DRIVE"); color: root.comboBusy ? root.warningGold : root.successGreen; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                        }
                    }
                }

                Column {
                    anchors.fill: parent
                    spacing: 20
                    visible: root.comboStage === 6
                    Text { text: "RECOVERY CODE"; color: root.textWhite; font.pixelSize: 24; font.bold: true }
                    Rectangle {
                        width: parent.width; height: 260; radius: 14
                        color: "#030810"; border.width: 2; border.color: root.neutronCyan
                        Column {
                            anchors.centerIn: parent; width: parent.width - 80; spacing: 18
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "••••  ••••  ••••"; color: root.neutronCyan; font.pixelSize: 34; font.bold: true }
                            Text { width: parent.width; text: root.comboBusy ? "VERIFYING THE RECOVERY CODE…" : "Enter the enrolled recovery code to continue."; color: root.mutedText; font.pixelSize: 15; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                        }
                    }
                }

                Column {
                    anchors.fill: parent
                    spacing: 18
                    visible: root.comboStage === 7
                    Text { width: parent.width; text: root.statusError ? "PASSCODE NOT CHANGED" : "PASSCODE REPLACED"; color: root.statusError ? root.dangerRed : root.successGreen; font.pixelSize: 28; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    Rectangle {
                        width: parent.width; height: 240; radius: 14
                        color: "#081522"; border.width: 1; border.color: root.statusError ? root.dangerRed : root.successGreen
                        Text { anchors.fill: parent; anchors.margins: 28; text: root.statusText; color: root.textWhite; font.pixelSize: 17; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    Text { width: parent.width; text: "X / OPTIONS / O  CLOSE"; color: root.neutronCyan; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                }
            }
        }

        Rectangle {
            id: statusPanel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.bottomMargin: 18
            height: 72
            radius: 12
            color: root.statusError ? "#2A1015" : root.chromeColor
            border.width: 1
            border.color: root.statusError ? root.dangerRed : "#315A80"
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: root.statusText
                color: root.statusError ? "#FF8790" : "#C8D5DF"
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
