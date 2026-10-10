import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root

    signal unlocked()
    signal cancelled()

    /*
        ============================================================
                        HIDDEN DOCK SECURITY MODAL
        ============================================================

        Purpose:
            Protects the hidden app dock with a controller combo.

        Original behavior preserved:
            - Full-screen dark modal.
            - Setup mode creates the hidden dock combo.
            - Unlock mode verifies the saved combo.
            - Setup mode shows the combo once.
            - Unlock mode masks the combo as * * * *.
            - Tamper lockout blocks input.
            - X confirms.
            - O backspaces, or closes when empty.
            - System clears input.
            - Direction buttons and face/shoulder buttons build combo.
            - Input debounce prevents accidental repeated entries.
            - Success state closes and emits unlocked().
            - Cancel state emits cancelled().
            - No MouseArea.
            - No Button.
            - Motion/stick input is not accepted here.

        Next-gen updates:
            - Safe dockSecurityManager access everywhere.
            - Fail-closed if dockSecurityManager is missing.
            - Expanded controller aliases.
            - Timers/animations stop safely when hidden.
            - Input is cleared on close.
            - No direct backend reference that can crash if manager is missing.
            - Still controller-first.
            - No placeholder behavior.
    */

    property int visualState: 0
    /*
        0 = normal
        1 = success
        2 = error / locked
    */

    property string statusText: ""

    property bool inputDebounceActive: false
    property string lastAcceptedInput: ""

    property bool animationsEnabled: visible && enabled

    property color neutronBlue: "#7df9ff"
    property color neutronRed: "#ff3040"
    property color secureGreen: "#22ff88"

    property color accentColor: visualState === 1
                                ? secureGreen
                                : visualState === 2
                                  ? neutronRed
                                  : isTamperLocked()
                                    ? neutronRed
                                    : neutronBlue

    anchors.fill: parent

    visible: false
    color: "#01040A"
    opacity: visible ? 1.0 : 0.0

    z: 1200
    focus: visible
    Keys.enabled: visible

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            BACKEND HELPERS
        ============================================================
    */

    function manager() {
        try {
            if (typeof dockSecurityManager !== "undefined" && dockSecurityManager)
                return dockSecurityManager
        } catch (e) {
        }

        return null
    }

    function managerAvailable() {
        return manager() !== null
    }

    function managerString(propName, fallbackValue) {
        var m = manager()

        if (!m)
            return fallbackValue

        try {
            var value = m[propName]

            if (value === undefined || value === null)
                return fallbackValue

            return String(value)
        } catch (e) {
            return fallbackValue
        }
    }

    function managerBool(propName, fallbackValue) {
        var m = manager()

        if (!m)
            return fallbackValue

        try {
            var value = m[propName]

            if (value === undefined || value === null)
                return fallbackValue

            return !!value
        } catch (e) {
            return fallbackValue
        }
    }

    function managerInt(propName, fallbackValue) {
        var m = manager()

        if (!m)
            return fallbackValue

        try {
            var value = Number(m[propName])

            if (isNaN(value))
                return fallbackValue

            return Math.max(0, Math.floor(value))
        } catch (e) {
            return fallbackValue
        }
    }

    function isTamperLocked() {
        return managerBool("tamperLocked", false)
    }

    function hasPasscode() {
        return managerBool("hasPasscode", false)
    }

    function isSetupMode() {
        return managerBool("setupMode", false)
    }

    function inputLength() {
        return managerInt("inputLength", 0)
    }

    function statusMessage() {
        return managerString("statusMessage", "")
    }

    function displayCombo() {
        return managerString("displayCombo", "")
    }

    function callManager(methodName) {
        var m = manager()

        if (!m)
            return false

        try {
            if (typeof m[methodName] === "function")
                return m[methodName]()
        } catch (e) {
            return false
        }

        return false
    }

    function callManagerWithArg(methodName, arg) {
        var m = manager()

        if (!m)
            return false

        try {
            if (typeof m[methodName] === "function")
                return m[methodName](arg)
        } catch (e) {
            return false
        }

        return false
    }

    function beginUnlock() {
        return callManager("beginUnlock")
    }

    function beginSetup() {
        return callManager("beginSetup")
    }

    function clearBackendInput() {
        callManager("clearInput")
    }

    function backspaceBackendInput() {
        callManager("backspaceInput")
    }

    function addBackendInput(button) {
        callManagerWithArg("addInput", button)
    }

    function saveBackendPasscode() {
        return callManager("savePasscode")
    }

    function verifyBackendPasscode() {
        return callManager("verifyPasscode")
    }

    /*
        ============================================================
                            MODAL API
        ============================================================
    */

    function open() {
        successClose.stop()
        feedbackReset.stop()
        inputDebounceTimer.stop()

        visualState = 0
        statusText = ""
        inputDebounceActive = false
        lastAcceptedInput = ""

        if (!managerAvailable()) {
            statusText = "Hidden dock security backend unavailable"
            visualState = 2
            visible = true
            forceActiveFocus()
            return
        }

        if (isTamperLocked()) {
            statusText = statusMessage()
            visualState = 2
        } else if (hasPasscode()) {
            beginUnlock()
        } else {
            beginSetup()
        }

        visible = true
        forceActiveFocus()
    }

    function close() {
        successClose.stop()
        feedbackReset.stop()
        inputDebounceTimer.stop()

        visible = false
        visualState = 0
        statusText = ""
        inputDebounceActive = false
        lastAcceptedInput = ""

        clearBackendInput()

        cancelled()
    }

    function closeAfterUnlock() {
        successClose.stop()
        feedbackReset.stop()
        inputDebounceTimer.stop()

        visible = false
        visualState = 0
        statusText = ""
        inputDebounceActive = false
        lastAcceptedInput = ""

        clearBackendInput()

        unlocked()
    }

    /*
        ============================================================
                            INPUT HELPERS
        ============================================================
    */

    function normalizeButton(button) {
        var b = String(button || "").trim().toUpperCase()

        if (b.length <= 0)
            return ""

        if (b === "PRIMARY" ||
                b === "CROSS" ||
                b === "A" ||
                b === "X" ||
                b === "PS_CROSS") {
            return "X"
        }

        if (b === "CANCEL" ||
                b === "CIRCLE" ||
                b === "B" ||
                b === "O" ||
                b === "PS_CIRCLE") {
            return "O"
        }

        if (b === "SECONDARY" ||
                b === "SQUARE" ||
                b === "XBOX_X" ||
                b === "PS_SQUARE") {
            return "SQUARE"
        }

        if (b === "CONTEXT" ||
                b === "TRI" ||
                b === "TRIANGLE" ||
                b === "Y" ||
                b === "PS_TRIANGLE") {
            return "TRIANGLE"
        }

        if (b === "SYSTEM" ||
                b === "OPTIONS" ||
                b === "OPTION" ||
                b === "START" ||
                b === "SETTINGS" ||
                b === "MENU" ||
                b === "GUIDE" ||
                b === "HOME" ||
                b === "PS" ||
                b === "PLAYSTATION") {
            return "SYSTEM"
        }

        if (b === "SHARE" ||
                b === "BACK" ||
                b === "SELECT" ||
                b === "VIEW") {
            return "SELECT"
        }

        if (b === "DPAD_UP")
            return "UP"

        if (b === "DPAD_DOWN")
            return "DOWN"

        if (b === "DPAD_LEFT")
            return "LEFT"

        if (b === "DPAD_RIGHT")
            return "RIGHT"

        if (b === "UP" ||
                b === "DOWN" ||
                b === "LEFT" ||
                b === "RIGHT") {
            return b
        }

        if (b === "L1" || b === "LB")
            return "L1"

        if (b === "R1" || b === "RB")
            return "R1"

        if (b === "L2" || b === "LT")
            return "L2"

        if (b === "R2" || b === "RT")
            return "R2"

        if (b === "L3" || b === "LS")
            return "L3"

        if (b === "R3" || b === "RS")
            return "R3"

        return b
    }

    function comboInputAllowed(action) {
        return action === "UP" ||
               action === "DOWN" ||
               action === "LEFT" ||
               action === "RIGHT" ||
               action === "SQUARE" ||
               action === "TRIANGLE" ||
               action === "L1" ||
               action === "R1" ||
               action === "L2" ||
               action === "R2" ||
               action === "L3" ||
               action === "R3"
    }

    function maskedComboText() {
        if (!managerAvailable())
            return "Security backend unavailable"

        if (inputLength() <= 0)
            return "Waiting for input..."

        /*
            First setup shows the actual combo so the user can verify it.
            Unlock mode hides it.
        */
        if (isSetupMode())
            return displayCombo()

        var text = ""

        for (var i = 0; i < inputLength(); i++) {
            if (i > 0)
                text += " "

            text += "*"
        }

        return text
    }

    function addCombo(button) {
        if (!root.visible)
            return

        if (!managerAvailable()) {
            visualState = 2
            statusText = "Security backend unavailable"
            feedbackReset.restart()
            return
        }

        if (isTamperLocked())
            return

        var cleanButton = normalizeButton(button)

        if (cleanButton.length <= 0)
            return

        if (!comboInputAllowed(cleanButton))
            return

        /*
            Combo input must be deliberate.
            Prevents one noisy event burst from adding repeated inputs.
        */
        if (inputDebounceActive && cleanButton === lastAcceptedInput)
            return

        lastAcceptedInput = cleanButton
        inputDebounceActive = true
        inputDebounceTimer.restart()

        visualState = 0
        statusText = ""

        addBackendInput(cleanButton)
    }

    function confirm() {
        if (!root.visible)
            return

        if (!managerAvailable()) {
            statusText = "Security backend unavailable"
            visualState = 2
            feedbackReset.restart()
            return
        }

        if (isTamperLocked()) {
            close()
            return
        }

        if (inputLength() <= 0) {
            statusText = isSetupMode() ? "Enter a combo first" : "Enter dock combo"
            visualState = 2
            feedbackReset.restart()
            return
        }

        if (isSetupMode()) {
            if (inputLength() < 3) {
                statusText = "Use at least 3 inputs"
                visualState = 2
                feedbackReset.restart()
                return
            }

            if (saveBackendPasscode()) {
                statusText = "Hidden dock combo saved"
                visualState = 1
                successClose.restart()
            } else {
                statusText = "Could not save combo"
                visualState = 2
                feedbackReset.restart()
            }

            return
        }

        if (verifyBackendPasscode()) {
            statusText = "Dock unlocked"
            visualState = 1
            successClose.restart()
        } else {
            statusText = "Wrong combo"
            visualState = 2
            feedbackReset.restart()
        }
    }

    function clearCombo() {
        if (!root.visible)
            return

        clearBackendInput()

        root.visualState = 0
        root.statusText = ""

        inputDebounceActive = false
        lastAcceptedInput = ""
    }

    function cancelOrBackspace() {
        if (!root.visible)
            return

        if (!managerAvailable()) {
            close()
            return
        }

        if (isTamperLocked()) {
            close()
            return
        }

        if (inputLength() > 0) {
            backspaceBackendInput()
            visualState = 0
            statusText = ""
            inputDebounceActive = false
            lastAcceptedInput = ""
            return
        }

        close()
    }

    function handleController(button) {
        if (!root.visible)
            return false

        var action = normalizeButton(button)

        if (!managerAvailable()) {
            if (action === "O" || action === "X" || action === "SYSTEM") {
                root.close()
                return true
            }

            return true
        }

        if (isTamperLocked()) {
            if (action === "O" || action === "X" || action === "SYSTEM")
                root.close()

            return true
        }

        if (comboInputAllowed(action)) {
            root.addCombo(action)
            return true
        }

        if (action === "X") {
            root.confirm()
            return true
        }

        if (action === "O") {
            root.cancelOrBackspace()
            return true
        }

        if (action === "SYSTEM") {
            root.clearCombo()
            return true
        }

        if (action === "SELECT") {
            if (inputLength() > 0) {
                backspaceBackendInput()
                inputDebounceActive = false
                lastAcceptedInput = ""
            }

            return true
        }

        /*
            Modal consumes controller input while open so commands do not leak
            into the hidden dock underneath.
        */
        return true
    }

    function handleControllerPressed(button) {
        return handleController(button)
    }

    function handleControllerReleased(button) {
        return visible
    }

    /*
        ============================================================
                            TIMERS
        ============================================================
    */

    Timer {
        id: inputDebounceTimer

        interval: 130
        repeat: false
        running: false

        onTriggered: {
            inputDebounceActive = false
            lastAcceptedInput = ""
        }
    }

    Timer {
        id: feedbackReset

        interval: 720
        repeat: false
        running: false

        onTriggered: visualState = 0
    }

    Timer {
        id: successClose

        interval: 680
        repeat: false
        running: false

        onTriggered: {
            root.closeAfterUnlock()
        }
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================

        Debug/keyboard fallback only.
        Controller remains primary.
    */

    Keys.onUpPressed: addCombo("UP")
    Keys.onDownPressed: addCombo("DOWN")
    Keys.onLeftPressed: addCombo("LEFT")
    Keys.onRightPressed: addCombo("RIGHT")
    Keys.onReturnPressed: confirm()
    Keys.onEnterPressed: confirm()
    Keys.onSpacePressed: confirm()
    Keys.onEscapePressed: cancelOrBackspace()
    Keys.onBackPressed: cancelOrBackspace()

    Keys.onPressed: function(event) {
        if (!root.visible)
            return

        if (event.key === Qt.Key_Backspace) {
            cancelOrBackspace()
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Delete) {
            clearCombo()
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_PageUp) {
            addCombo("L1")
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_PageDown) {
            addCombo("R1")
            event.accepted = true
            return
        }
    }

    /*
        ============================================================
                            BACKGROUND
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        color: "#01040A"
        opacity: 1.0
    }

    Rectangle {
        anchors.fill: parent

        color: "#071426"
        opacity: 0.26
    }

    Rectangle {
        anchors.centerIn: parent

        width: parent.width * 0.92
        height: parent.height * 0.82
        radius: 46

        color: "#000000"
        opacity: 0.30
    }

    /*
        ============================================================
                            PANEL
        ============================================================
    */

    Rectangle {
        id: panel

        width: Math.min(820, parent.width * 0.62)
        height: Math.min(500, parent.height * 0.58)

        anchors.centerIn: parent

        radius: 38

        color: "#050914"
        opacity: 1.0
        border.width: 3
        border.color: root.accentColor

        clip: true
        activeFocusOnTab: false

        scale: root.visible ? 1.0 : 0.92

        Behavior on scale {
            enabled: root.animationsEnabled

            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        Behavior on border.color {
            enabled: root.animationsEnabled

            ColorAnimation {
                duration: 160
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

            y: -210

            width: parent.width * 0.92
            height: 330
            radius: height / 2

            color: root.accentColor
            opacity: visualState === 2 ? 0.095 : 0.070
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            width: 7
            radius: 4

            color: root.accentColor
            opacity: visualState === 2 ? 0.95 : 0.72
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 34
            anchors.rightMargin: 34
            anchors.topMargin: 18

            height: 1

            color: root.accentColor
            opacity: 0.75
        }

        Column {
            anchors.fill: parent
            anchors.margins: 38

            spacing: 20

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter

                text: !root.managerAvailable()
                      ? "Hidden Dock Security Offline"
                      : root.isTamperLocked()
                        ? "Hidden Dock Security Lockout"
                        : root.isSetupMode()
                          ? "Set Hidden Dock Combo"
                          : "Hidden Dock Armed"

                color: "white"

                font.pixelSize: 38
                font.bold: true

                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter

                text: !root.managerAvailable()
                      ? "DockSecurityManager is not available. Hidden dock access is blocked fail-closed."
                      : root.isTamperLocked()
                        ? root.statusMessage()
                        : root.isSetupMode()
                          ? "Enter a controller combo, then press X to save."
                          : "Enter your saved combo, then press X to unlock."

                color: !root.managerAvailable() || root.isTamperLocked()
                       ? "#ff9a9a"
                       : root.isSetupMode()
                         ? "#9fd8ff"
                         : "#ffb3b3"

                font.pixelSize: 18
                font.bold: true

                wrapMode: Text.WordWrap
                maximumLineCount: 3
            }

            Rectangle {
                width: parent.width
                height: 86
                radius: 24

                color: visualState === 1
                       ? "#0f3a25"
                       : visualState === 2
                         ? "#3a0909"
                         : "#050814"

                border.width: 2
                border.color: root.accentColor

                clip: true

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1

                    radius: parent.radius - 1
                    color: "#FFFFFF"
                    opacity: 0.025
                }

                Text {
                    anchors.centerIn: parent

                    width: parent.width - 32

                    horizontalAlignment: Text.AlignHCenter

                    text: !root.managerAvailable()
                          ? "Security backend unavailable"
                          : root.isTamperLocked()
                            ? "Recovery required"
                            : root.maskedComboText()

                    color: !root.managerAvailable() || root.isTamperLocked()
                           ? "#ff9a9a"
                           : root.inputLength() > 0
                             ? "white"
                             : "#6f8fb8"

                    font.pixelSize: !root.managerAvailable() || root.isTamperLocked()
                                    ? 24
                                    : root.inputLength() > 10
                                      ? 22
                                      : 25

                    font.bold: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter

                text: statusText.length > 0
                      ? statusText
                      : !root.managerAvailable()
                        ? "Press O to close"
                        : root.isTamperLocked()
                          ? ""
                          : root.isSetupMode()
                            ? "Setup shows combo · X saves · O backspace/cancel"
                            : "Combo hidden · X confirms · O backspace/cancel · System clears"

                color: visualState === 1
                       ? "#9cffc6"
                       : visualState === 2
                         ? "#ff9a9a"
                         : "#8aa6c8"

                font.pixelSize: 16
                font.bold: true

                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter

                spacing: 16

                Rectangle {
                    width: 230
                    height: 64
                    radius: 22

                    color: "#101d42"
                    border.width: 2
                    border.color: root.accentColor

                    Text {
                        anchors.centerIn: parent

                        text: !root.managerAvailable()
                              ? "BLOCKED"
                              : root.isTamperLocked()
                                ? "LOCKED"
                                : root.isSetupMode()
                                  ? "X  SAVE COMBO"
                                  : "X  UNLOCK"

                        color: "white"

                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }

                Rectangle {
                    width: 230
                    height: 64
                    radius: 22

                    color: "#221018"
                    border.width: 2
                    border.color: root.neutronRed

                    Text {
                        anchors.centerIn: parent

                        text: "O  BACK / CLOSE"

                        color: "#ffd1d1"

                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (!visible) {
            successClose.stop()
            feedbackReset.stop()
            inputDebounceTimer.stop()

            inputDebounceActive = false
            lastAcceptedInput = ""

            clearBackendInput()
        }
    }

    onEnabledChanged: {
        if (!enabled) {
            successClose.stop()
            feedbackReset.stop()
            inputDebounceTimer.stop()

            inputDebounceActive = false
            lastAcceptedInput = ""
        }
    }
}