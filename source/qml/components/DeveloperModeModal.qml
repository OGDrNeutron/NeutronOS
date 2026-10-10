import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: modal

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 9999

    property string phase: "warning"
    // warning, create, confirm, verify, success, error
    property string firstCode: ""
    property string currentCode: ""
    property string normalizedCode: ""
    property string successfulAction: ""
    property string selectedButton: "enable"

    readonly property bool comboEntryPhase: phase === "create" || phase === "confirm" || phase === "verify"
    readonly property bool animationsEnabled: visible && enabled

    // Current NeutronOS default modal palette, matching the Storage/Settings family.
    property color spaceBlack: "#02060D"
    property color chromeColor: "#030810"
    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color panelInset: "#06101F"
    property color focusBlue: "#4DA6FF"
    property color neutronCyan: "#7DF9FF"
    property color textPrimary: "#F4FBFF"
    property color textSecondary: "#C8D5DF"
    property color textMuted: "#8AA6C8"
    property color dangerRed: "#FF3040"
    property color successGreen: "#22FF88"
    property color developerPurple: "#B75CFF"
    property color warningGold: "#F5C542"

    signal closed()
    signal developerModeEnabled()
    signal developerModeDisabled()

    function backend() {
        try {
            if (typeof developerModeManager !== "undefined" && developerModeManager)
                return developerModeManager
        } catch (error) {}
        return null
    }

    function managerAvailable() {
        return backend() !== null
    }

    function backendDeveloperModeEnabled() {
        var manager = backend()
        if (!manager)
            return false
        try { return !!manager.developerModeEnabled } catch (error) { return false }
    }

    function backendCodeCreated() {
        var manager = backend()
        if (!manager)
            return false
        try { return !!manager.codeCreated } catch (error) { return false }
    }

    function backendButtonState() {
        var manager = backend()
        if (!manager)
            return ""
        try { return String(manager.buttonState || "") } catch (error) { return "" }
    }

    function backendError() {
        var manager = backend()
        if (!manager)
            return "developerModeManager unavailable"
        try { return String(manager.error || "") } catch (error) { return "" }
    }

    function clearCodes() {
        firstCode = ""
        currentCode = ""
        normalizedCode = ""
        if (fallbackInput)
            fallbackInput.text = ""
    }

    Connections {
        target: modal.backend()
        ignoreUnknownSignals: true

        function onDeveloperModeChanged() {
            var manager = modal.backend()
            if (!manager)
                return
            modal.phase = "success"
            modal.selectedButton = "cancel"
            modal.successfulAction = manager.developerModeEnabled ? "enabled" : "disabled"
            successPulse.restart()
            if (manager.developerModeEnabled)
                modal.developerModeEnabled()
            else
                modal.developerModeDisabled()
        }

        function onButtonStateChanged() {
            var state = modal.backendButtonState()
            if (state === "green")
                successPulse.restart()
            else if (state === "red")
                errorShake.restart()
        }

        function onErrorChanged() {
            if (modal.backendError().length > 0) {
                modal.phase = "error"
                modal.selectedButton = "enable"
                errorShake.restart()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#E602060D"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 110, 1120)
        height: Math.min(parent.height - 86, 760)
        radius: 30
        color: modal.panelColor
        border.width: 2
        border.color: modal.phase === "success"
                      ? modal.successGreen
                      : modal.phase === "error"
                        ? modal.dangerRed
                        : modal.developerPurple
        clip: true

        scale: modal.visible ? 1.0 : 0.97
        opacity: modal.visible ? 1.0 : 0.0

        Behavior on scale {
            enabled: modal.animationsEnabled
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            enabled: modal.animationsEnabled
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            enabled: modal.animationsEnabled
            ColorAnimation { duration: 140 }
        }

        // Header
        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 112
            color: modal.chromeColor

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                height: 64
                radius: 18
                color: "#171126"
                border.width: 1
                border.color: modal.developerPurple

                // Compact developer authority mark built in QML, no external asset dependency.
                Rectangle {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    radius: 9
                    color: "transparent"
                    border.width: 2
                    border.color: modal.developerPurple
                    rotation: 45
                }
                Text {
                    anchors.centerIn: parent
                    text: "N"
                    color: modal.textPrimary
                    font.pixelSize: 22
                    font.bold: true
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 112
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Text {
                    width: parent.width
                    text: "DEVELOPER MODE"
                    color: modal.textPrimary
                    font.pixelSize: 28
                    font.bold: true
                    font.letterSpacing: 1.4
                }
                Text {
                    width: parent.width
                    text: modal.backendDeveloperModeEnabled()
                          ? "Protected system authority is currently enabled"
                          : "Protected system authority and advanced controls"
                    color: modal.textMuted
                    font.pixelSize: 14
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#25313C"
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 16

                // Preserve the established warnings exactly, only redesign their presentation.
                Rectangle {
                    width: parent.width
                    height: 112
                    radius: 16
                    color: "#2A1015"
                    border.width: 1
                    border.color: "#70313A"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 5
                        radius: 3
                        color: modal.dangerRed
                    }

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        anchors.topMargin: 15
                        anchors.bottomMargin: 12
                        spacing: 6

                        Text {
                            width: parent.width
                            text: "Warning Developer Mode overrides all safety nets, does NOT require sudo, can break system if misused"
                            color: modal.dangerRed
                            font.pixelSize: 18
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: "Use with care :)"
                            color: modal.successGreen
                            font.pixelSize: 16
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: comboBody.height
                    radius: 18
                    color: modal.panelInset
                    border.width: 1
                    border.color: modal.phase === "error"
                                  ? "#70313A"
                                  : modal.phase === "success"
                                    ? "#2A694B"
                                    : "#203847"

                    Column {
                        id: comboBody
                        width: parent.width
                        height: implicitHeight + 36
                        anchors.centerIn: parent
                        leftPadding: 22
                        rightPadding: 22
                        spacing: 12

                        Row {
                            width: parent.width - 44
                            height: 44
                            spacing: 12

                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                anchors.verticalCenter: parent.verticalCenter
                                color: modal.phase === "success"
                                       ? modal.successGreen
                                       : modal.phase === "error"
                                         ? modal.dangerRed
                                         : modal.developerPurple
                            }

                            Text {
                                width: parent.width - 22
                                anchors.verticalCenter: parent.verticalCenter
                                text: modal.instructionTitle()
                                color: modal.textPrimary
                                font.pixelSize: 22
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            width: parent.width - 44
                            text: modal.instructionBody()
                            color: modal.textSecondary
                            font.pixelSize: 14
                            lineHeight: 1.1
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            width: parent.width - 44
                            height: 104
                            radius: 14
                            color: "#030810"
                            border.width: 2
                            border.color: modal.phase === "error"
                                          ? modal.dangerRed
                                          : modal.phase === "success"
                                            ? modal.successGreen
                                            : modal.focusBlue

                            Row {
                                anchors.centerIn: parent
                                spacing: 9

                                Repeater {
                                    model: modal.codeParts()
                                    delegate: Rectangle {
                                        width: Math.max(48, tokenLabel.implicitWidth + 20)
                                        height: 38
                                        radius: 10
                                        color: "#102A42"
                                        border.width: 1
                                        border.color: modal.neutronCyan
                                        Text {
                                            id: tokenLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: modal.textPrimary
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }
                                }

                                Text {
                                    visible: modal.codeParts().length === 0
                                    text: modal.phase === "warning"
                                          ? "Controller passcode input begins after ENABLE"
                                          : modal.phase === "success"
                                            ? "Developer Mode is active"
                                            : "Awaiting controller inputs…"
                                    color: modal.textMuted
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }
                        }

                        TextField {
                            id: fallbackInput
                            width: parent.width - 44
                            height: 48
                            visible: modal.comboEntryPhase
                            text: modal.currentCode
                            color: modal.textPrimary
                            selectionColor: modal.focusBlue
                            selectedTextColor: modal.spaceBlack
                            font.pixelSize: 17
                            font.bold: true
                            font.family: "monospace"
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: "Keyboard fallback: L1,R1,UP,TRIANGLE"
                            placeholderTextColor: "#66839F"

                            onTextEdited: {
                                modal.currentCode = fallbackInput.text
                                modal.normalizedCode = modal.normalize(modal.currentCode)
                            }

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    modal.submitCode()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Escape) {
                                    modal.close()
                                    event.accepted = true
                                }
                            }

                            background: Rectangle {
                                radius: 12
                                color: "#081522"
                                border.width: 1
                                border.color: modal.comboEntryPhase ? modal.focusBlue : "#203847"
                            }
                        }

                        Rectangle {
                            width: parent.width - 44
                            height: 66
                            radius: 13
                            color: "#0A1A2F"
                            border.width: 1
                            border.color: "#1D3958"
                            visible: modal.comboEntryPhase

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                Repeater {
                                    model: [
                                        { key: "X", text: "ENTER", color: modal.neutronCyan },
                                        { key: "OPTIONS", text: "ENTER", color: modal.neutronCyan },
                                        { key: "SHARE", text: "DELETE", color: modal.textSecondary },
                                        { key: "O", text: "CLOSE", color: modal.dangerRed }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        height: 38
                                        width: controlText.implicitWidth + 28
                                        radius: 10
                                        color: "#081522"
                                        border.width: 1
                                        border.color: modelData.color
                                        Text {
                                            id: controlText
                                            anchors.centerIn: parent
                                            text: modelData.key + "  " + modelData.text
                                            color: modelData.color
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width - 44
                            visible: modal.backendError().length > 0 || !modal.managerAvailable()
                            text: modal.backendError()
                            color: modal.dangerRed
                            font.pixelSize: 13
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14
                    visible: !modal.comboEntryPhase

                    Rectangle {
                        id: cancelButton
                        width: 200
                        height: 58
                        radius: 14
                        property bool selected: modal.selectedButton === "cancel"
                        color: selected ? "#102A42" : "#081522"
                        border.width: selected ? 2 : 1
                        border.color: selected ? modal.focusBlue : "#203847"
                        Text {
                            anchors.centerIn: parent
                            text: "CLOSE"
                            color: modal.textPrimary
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                    }

                    Rectangle {
                        id: enableButton
                        width: 240
                        height: 58
                        radius: 14
                        property bool selected: modal.selectedButton === "enable"
                        color: modal.enableButtonColor()
                        border.width: selected ? 2 : 1
                        border.color: modal.enableButtonBorder()
                        Text {
                            anchors.centerIn: parent
                            text: modal.enableButtonText()
                            color: modal.textPrimary
                            font.pixelSize: 15
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                    }
                }
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 64
            color: modal.chromeColor

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#25313C"
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 40
                text: modal.footerText()
                color: modal.textMuted
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    SequentialAnimation {
        id: errorShake
        running: false
        NumberAnimation { target: panel; property: "x"; from: panel.x; to: panel.x - 10; duration: 45 }
        NumberAnimation { target: panel; property: "x"; from: panel.x - 10; to: panel.x + 10; duration: 70 }
        NumberAnimation { target: panel; property: "x"; from: panel.x + 10; to: panel.x; duration: 45 }
    }

    SequentialAnimation {
        id: successPulse
        running: false
        NumberAnimation { target: panel; property: "scale"; to: 1.018; duration: 100 }
        NumberAnimation { target: panel; property: "scale"; to: 1.0; duration: 130 }
    }

    function openModal() {
        visible = true
        forceActiveFocus()

        if (!managerAvailable()) {
            phase = "error"
            selectedButton = "cancel"
            clearCodes()
            errorShake.restart()
            return
        }

        try {
            var manager = backend()
            if (manager && typeof manager.refresh === "function")
                manager.refresh()
        } catch (error) {}

        phase = "warning"
        selectedButton = "enable"
        successfulAction = ""
        clearCodes()
    }

    function open() { openModal() }

    function close() {
        visible = false
        phase = "warning"
        selectedButton = "enable"
        successfulAction = ""
        clearCodes()
        closed()
    }

    function cancel() { close() }

    function instructionTitle() {
        if (!managerAvailable())
            return "BACKEND UNAVAILABLE"
        if (phase === "warning") {
            if (backendDeveloperModeEnabled())
                return "Developer Mode is currently enabled"
            if (backendCodeCreated())
                return "Enter your Developer Mode controller combo"
            return "Create your Developer Mode controller combo"
        }
        if (phase === "create") return "Enter new controller combo"
        if (phase === "confirm") return "Confirm the same combo"
        if (phase === "verify") return "Enter controller combo"
        if (phase === "success") return "Developer Mode enabled"
        if (phase === "error") return "Developer Mode blocked"
        return "Developer Mode"
    }

    function instructionBody() {
        if (!managerAvailable())
            return "developerModeManager is not exposed to QML. Developer Mode is blocked fail-closed."
        if (phase === "warning") {
            if (backendDeveloperModeEnabled())
                return "Developer Mode is already active. Terminal and system tools can read the global developer state from Console."
            if (backendCodeCreated())
                return "Press Enable, enter your controller combo, then press X or OPTIONS to verify. Keyboard fallback can type the same code."
            return "First setup requires creating a controller button combo. Use at least 3 buttons. Keyboard fallback can type the same combo text."
        }
        if (phase === "create")
            return "Press controller buttons in order. Press X or OPTIONS when finished. SHARE removes the last input. Circle closes the modal."
        if (phase === "confirm")
            return "Repeat the exact same combo. It will be saved only as a salted hash, never plain text."
        if (phase === "verify")
            return "Enter your saved controller combo. Press X or OPTIONS when finished."
        if (phase === "success")
            return "Developer Mode is enabled globally. Terminal reads this state, but Console owns it."
        if (phase === "error")
            return "The combo was rejected or could not be saved. Try again or cancel."
        return ""
    }

    function footerText() {
        if (comboEntryPhase)
            return "X / OPTIONS  ENTER     SHARE  DELETE     O / CIRCLE  CLOSE"
        if (phase === "success")
            return "Developer Mode " + (successfulAction === "disabled" ? "disabled" : "enabled") + "  •  X / OPTIONS / O closes"
        return "LEFT / RIGHT  CHOOSE     X / OPTIONS  SELECT     O / CIRCLE  CLOSE"
    }

    function enableButtonText() {
        if (!managerAvailable()) return "UNAVAILABLE"
        var state = backendButtonState()
        if (state === "purple") return "VERIFYING…"
        if (phase === "success") return "CLOSE"
        if (state === "red" || phase === "error") return "TRY AGAIN"
        if (backendDeveloperModeEnabled()) return "DISABLE"
        if (phase === "create") return "ENTER COMBO"
        if (phase === "confirm") return "CONFIRM"
        if (phase === "verify") return "VERIFY"
        return "ENABLE"
    }

    function enableButtonColor() {
        if (!managerAvailable()) return "#26080C"
        var state = backendButtonState()
        if (state === "purple") return "#29123F"
        if (state === "green" || phase === "success") return "#0B2B20"
        if (state === "red" || phase === "error") return "#2A1015"
        return enableButton.selected ? "#241236" : "#0B1A30"
    }

    function enableButtonBorder() {
        if (!managerAvailable()) return modal.dangerRed
        var state = backendButtonState()
        if (state === "purple") return modal.developerPurple
        if (state === "green" || phase === "success") return modal.successGreen
        if (state === "red" || phase === "error") return modal.dangerRed
        return enableButton.selected ? modal.developerPurple : "#315A80"
    }

    function codeParts() {
        if (phase === "warning" || phase === "success")
            return []
        var n = normalizedCode.length > 0 ? normalizedCode : normalize(currentCode)
        if (n.length <= 0)
            return []
        return n.split(",").filter(function(part) { return String(part).length > 0 })
    }

    function normalize(raw) {
        var text = String(raw || "").trim()
        if (!managerAvailable())
            return text
        try {
            var manager = backend()
            if (manager && typeof manager.normalizeCode === "function")
                return manager.normalizeCode(text)
        } catch (error) {}
        return text
    }

    // Main.qml routes PlayStation names to these semantic actions before the modal sees them.
    // Keep aliases for direct/raw callers, but user-facing terminology is Options / Share only.
    function semanticAction(button) {
        var b = String(button || "").trim().toLowerCase().replace(/-/g, "_")
        if (b === "primary" || b === "x" || b === "cross" || b === "a" || b === "ps_cross") return "primary"
        if (b === "cancel" || b === "o" || b === "circle" || b === "b" || b === "ps_circle") return "cancel"
        if (b === "context" || b === "triangle" || b === "tri" || b === "y" || b === "ps_triangle") return "context"
        if (b === "secondary" || b === "square" || b === "xbox_x" || b === "ps_square") return "secondary"
        if (b === "system" || b === "options" || b === "option" || b === "settings" || b === "start" || b === "menu") return "system"
        if (b === "quick" || b === "share" || b === "create" || b === "select" || b === "capture" || b === "view") return "quick"
        if (b === "home" || b === "ps" || b === "playstation" || b === "guide") return "home"
        if (b === "dpad_up") return "up"
        if (b === "dpad_down") return "down"
        if (b === "dpad_left") return "left"
        if (b === "dpad_right") return "right"
        if (b === "lb") return "l1"
        if (b === "rb") return "r1"
        if (b === "lt") return "l2"
        if (b === "rt") return "r2"
        if (b === "ls") return "l3"
        if (b === "rs") return "r3"
        return b
    }

    function tokenForAction(action) {
        var a = semanticAction(action)
        // X, Circle, Options and Share are modal controls during passcode capture.
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

    function appendButtonToCode(action) {
        if (!comboEntryPhase)
            return false
        var token = tokenForAction(action)
        if (token.length <= 0)
            return false
        if (currentCode.length > 0)
            currentCode += ","
        currentCode += token
        normalizedCode = normalize(currentCode)
        fallbackInput.text = normalizedCode
        fallbackInput.cursorPosition = fallbackInput.text.length
        return true
    }

    function removeLastButton() {
        if (!comboEntryPhase)
            return
        var parts = codeParts()
        if (parts.length <= 0)
            return
        parts.pop()
        currentCode = parts.join(",")
        normalizedCode = normalize(currentCode)
        fallbackInput.text = normalizedCode
        fallbackInput.cursorPosition = fallbackInput.text.length
    }

    function disableDeveloperModeNow() {
        if (!managerAvailable()) {
            phase = "error"
            selectedButton = "cancel"
            return
        }
        var manager = backend()
        var ok = false
        try {
            if (manager && typeof manager.disableDeveloperMode === "function")
                ok = manager.disableDeveloperMode() !== false
            else if (manager && typeof manager.disable === "function")
                ok = manager.disable() !== false
            else if (manager && typeof manager.turnOff === "function")
                ok = manager.turnOff() !== false
        } catch (error) { ok = false }

        if (ok || !backendDeveloperModeEnabled()) {
            successfulAction = "disabled"
            phase = "success"
            selectedButton = "cancel"
            successPulse.restart()
            developerModeDisabled()
        } else {
            phase = "error"
            selectedButton = "enable"
            errorShake.restart()
        }
    }

    function beginEnableFlow() {
        if (!managerAvailable()) {
            phase = "error"
            selectedButton = "cancel"
            errorShake.restart()
            return
        }
        if (backendDeveloperModeEnabled()) {
            disableDeveloperModeNow()
            return
        }
        currentCode = ""
        normalizedCode = ""
        fallbackInput.text = ""
        phase = backendCodeCreated() ? "verify" : "create"
        selectedButton = "enable"
        fallbackInput.forceActiveFocus()
    }

    function submitCode() {
        if (!managerAvailable()) {
            phase = "error"
            selectedButton = "cancel"
            errorShake.restart()
            return
        }

        normalizedCode = normalize(currentCode)

        if (phase === "create") {
            if (codeParts().length < 3) {
                errorShake.restart()
                return
            }
            firstCode = normalizedCode
            currentCode = ""
            normalizedCode = ""
            fallbackInput.text = ""
            phase = "confirm"
            fallbackInput.forceActiveFocus()
            return
        }

        if (phase === "confirm") {
            var confirmResult = null
            try {
                confirmResult = backend().validateCodeConfirmation(firstCode, currentCode)
            } catch (error) {
                confirmResult = { "ok": false, "normalizedCode": "" }
            }
            if (!confirmResult || !confirmResult.ok) {
                currentCode = ""
                normalizedCode = ""
                fallbackInput.text = ""
                errorShake.restart()
                return
            }

            var createResult = null
            try {
                createResult = backend().enableWithCode(confirmResult.normalizedCode)
            } catch (error2) {
                createResult = { "ok": false }
            }
            if (createResult && createResult.ok) {
                successfulAction = "enabled"
                phase = "success"
                selectedButton = "cancel"
                developerModeEnabled()
                successPulse.restart()
            } else {
                phase = "error"
                selectedButton = "enable"
                errorShake.restart()
            }
            return
        }

        if (phase === "verify") {
            var result = null
            try {
                result = backend().enableWithCode(normalizedCode)
            } catch (error3) {
                result = { "ok": false }
            }
            if (result && result.ok) {
                successfulAction = "enabled"
                phase = "success"
                selectedButton = "cancel"
                developerModeEnabled()
                successPulse.restart()
            } else {
                phase = "error"
                selectedButton = "enable"
                errorShake.restart()
            }
            return
        }

        if (phase === "error") {
            phase = backendCodeCreated() ? "verify" : "create"
            currentCode = ""
            normalizedCode = ""
            fallbackInput.text = ""
            selectedButton = "enable"
            fallbackInput.forceActiveFocus()
        }
    }

    function activateSelected() {
        if (selectedButton === "cancel") {
            close()
            return
        }
        if (phase === "warning") {
            beginEnableFlow()
            return
        }
        if (phase === "error") {
            submitCode()
            return
        }
        if (phase === "success") {
            close()
            return
        }
    }

    function moveLeft() {
        if (!comboEntryPhase)
            selectedButton = "cancel"
    }

    function moveRight() {
        if (!comboEntryPhase)
            selectedButton = "enable"
    }

    function handleController(button) {
        if (!visible)
            return false

        var action = semanticAction(button)

        // Circle is always the modal close button, including while capturing a combo.
        if (action === "cancel") {
            close()
            return true
        }

        if (comboEntryPhase) {
            // X and Options both enter/submit the captured combo. They are not passcode tokens.
            if (action === "primary" || action === "system") {
                submitCode()
                return true
            }
            // Share is the edit key. It removes one captured input instead of becoming a token.
            if (action === "quick") {
                removeLastButton()
                return true
            }
            appendButtonToCode(action)
            return true
        }

        if (action === "left") {
            moveLeft()
            return true
        }
        if (action === "right") {
            moveRight()
            return true
        }
        if (action === "primary" || action === "system") {
            activateSelected()
            return true
        }
        return true
    }

    function handleControllerPressed(button) { return handleController(button) }
    function handleControllerReleased(button) { return visible }

    Keys.onPressed: function(event) {
        if (!visible)
            return
        if (event.key === Qt.Key_Left) {
            moveLeft(); event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            moveRight(); event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            comboEntryPhase ? submitCode() : activateSelected()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            close(); event.accepted = true
        }
    }

    onVisibleChanged: {
        if (!visible)
            clearCodes()
    }
}
