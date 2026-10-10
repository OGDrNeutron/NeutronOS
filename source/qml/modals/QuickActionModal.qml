import QtQuick 2.15
import "../common"

Rectangle {
    id: root

    /*
        ============================================================
                            QUICK ACTION MODAL
        ============================================================

        Preserved from original:
            - Full-screen modal overlay.
            - actionData input.
            - actionName.
            - danger mode.
            - selectedTab / armedTab.
            - Confirm / Run button.
            - Cancel button.
            - confirmed(actionData).
            - cancelled().
            - closed().
            - Keyboard fallback.
            - Controller navigation.
            - ModalTabButton usage.
            - Background click closes.
            - Panel click does not close.

        Next-gen updates:
            - Explicit QtQuick 2.15 import.
            - Safe controllerManager access.
            - Safe actionData field parsing.
            - Supports id/actionId/name/title/label/subtitle/description.
            - Supports danger/destructive/confirmRequired/requiresConfirmation.
            - Proper focus and armed separation.
            - Dangerous actions pulse red.
            - O cancels armed state before close.
            - START/OPTIONS confirms selected tab.
            - Expanded controller aliases.
            - Optional pointer fallback.
            - Animations pause when hidden.
            - No placeholder behavior.
    */

    property var actionData: null

    property string actionName: actionTitle(actionData)
    property string actionSubtitle: actionDescription(actionData)
    property string actionId: actionIdentifier(actionData)

    property bool danger: actionDanger(actionData)
    property bool destructive: danger
    property bool busy: actionBusy(actionData)
    property bool disabled: actionDisabled(actionData)

    property int armedTab: -1
    property int selectedTab: 0

    property bool pointerEnabled: true
    property bool animationsEnabled: visible && enabled

    /*
        Original behavior preserved:
            confirm() emits confirmed(actionData) and does not force close.
        Parent may close after action execution.

        Set true only if a parent wants this modal to dismiss immediately.
    */
    property bool autoCloseOnConfirm: false

    property color neutronBlue: "#7df9ff"
    property color focusBlue: "#4da6ff"
    property color dangerRed: "#ff3040"
    property color successGreen: "#22ff88"
    property color warningGold: "#f5c542"
    property color mutedBlue: "#8aa6c8"
    property color purpleAccent: "#a855f7"

    property real pulse: 0.48
    property real sweep: -1.0

    signal closed()
    signal confirmed(var actionData)
    signal cancelled()

    anchors.fill: parent

    visible: false
    color: "#F5000000"
    z: 999
    focus: visible
    Keys.enabled: visible

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.35
            to: 1.0
            duration: root.danger ? 620 : 1600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.35
            duration: root.danger ? 620 : 1600
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.danger ? 1200 : 3400
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.danger ? 1200 : 3400
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                                API
        ============================================================
    */

    function open(action) {
        actionData = action
        selectedTab = 0
        armedTab = -1
        visible = true
        root.forceActiveFocus()
        clampSelected()
    }

    function close() {
        visible = false
        selectedTab = 0
        armedTab = -1
        closed()
    }

    function tabCount() {
        return 2
    }

    function clampSelected() {
        var count = tabCount()

        if (count <= 0) {
            selectedTab = 0
            armedTab = -1
            return
        }

        if (selectedTab < 0)
            selectedTab = count - 1

        if (selectedTab >= count)
            selectedTab = 0

        if (armedTab >= count)
            armedTab = -1
    }

    function moveSelection(delta) {
        if (tabCount() <= 0)
            return false

        selectedTab = (selectedTab + delta + tabCount()) % tabCount()

        /*
            Moving selection cancels the red armed confirm state.
        */
        armedTab = -1

        return true
    }

    function activateSelected() {
        clampSelected()

        if (selectedTab === 0) {
            if (disabled || busy)
                return true

            /*
                This modal is already the confirmation layer. For dangerous
                actions, first X arms the confirm tab, second X confirms.
            */
            if (danger && armedTab !== 0) {
                armedTab = 0
                return true
            }

            confirm()
            return true
        }

        armedTab = -1
        cancelled()
        close()
        return true
    }

    function confirm() {
        if (disabled || busy)
            return

        armedTab = 0
        confirmed(actionData)

        if (autoCloseOnConfirm)
            close()
    }

    function cancelOrClose() {
        if (armedTab >= 0) {
            armedTab = -1
            return true
        }

        cancelled()
        close()
        return true
    }

    /*
        ============================================================
                            CONTROLLER INPUT
        ============================================================
    */

    function normalizeController(button) {
        var b = String(button || "").trim().toUpperCase()

        if (b === "DPAD_LEFT" || b === "LEFT")
            return "LEFT"

        if (b === "DPAD_RIGHT" || b === "RIGHT")
            return "RIGHT"

        if (b === "DPAD_UP" || b === "UP")
            return "UP"

        if (b === "DPAD_DOWN" || b === "DOWN")
            return "DOWN"

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

        if (b === "CONTEXT" ||
                b === "TRI" ||
                b === "TRIANGLE" ||
                b === "Y" ||
                b === "PS_TRIANGLE") {
            return "TRIANGLE"
        }

        if (b === "SYSTEM" ||
                b === "START" ||
                b === "OPTIONS" ||
                b === "OPTION" ||
                b === "MENU") {
            return "START"
        }

        return b
    }

    function handleController(button) {
        if (!visible)
            return false

        var action = normalizeController(button)

        if (action === "LEFT" || action === "UP") {
            moveSelection(-1)
            return true
        }

        if (action === "RIGHT" || action === "DOWN") {
            moveSelection(1)
            return true
        }

        if (action === "X" || action === "START") {
            activateSelected()
            return true
        }

        if (action === "O") {
            cancelOrClose()
            return true
        }

        if (action === "TRIANGLE") {
            selectedTab = 1
            cancelOrClose()
            return true
        }

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
                            SAFE HELPERS
        ============================================================
    */

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

    function valueFor(source, keys, fallbackValue) {
        if (!source)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = source[keys[i]]

                if (value !== undefined &&
                        value !== null &&
                        String(value).trim().length > 0) {
                    return String(value)
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function boolFor(source, keys, fallbackValue) {
        if (!source)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var raw = source[keys[i]]

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
                        text === "danger" ||
                        text === "destructive" ||
                        text === "required" ||
                        text === "confirm" ||
                        text === "disabled" ||
                        text === "busy" ||
                        text === "running") {
                    return true
                }

                if (text === "false" ||
                        text === "0" ||
                        text === "no" ||
                        text === "safe" ||
                        text === "enabled" ||
                        text === "idle" ||
                        text === "available") {
                    return false
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function actionIdentifier(action) {
        var id = valueFor(action, [
                              "id",
                              "actionId",
                              "backendAction",
                              "action",
                              "command",
                              "commandId"
                          ], "")

        if (id.length > 0)
            return id

        return actionTitle(action)
    }

    function actionTitle(action) {
        var title = valueFor(action, [
                                "name",
                                "title",
                                "label",
                                "displayName"
                            ], "")

        if (title.length > 0)
            return title

        var id = valueFor(action, [
                              "id",
                              "actionId",
                              "backendAction",
                              "action"
                          ], "")

        if (id.length > 0)
            return id

        return "Action"
    }

    function actionDescription(action) {
        var text = valueFor(action, [
                                "subtitle",
                                "description",
                                "hint",
                                "type"
                            ], "")

        if (text.length > 0)
            return text

        if (actionDanger(action))
            return "System Level Action."

        return "Run Anyway?"
    }

    function actionDanger(action) {
        if (boolFor(action, [
                    "danger",
                    "destructive",
                    "confirmRequired",
                    "requiresConfirmation"
                ], false)) {
            return true
        }

        var id = actionIdentifier(action).toLowerCase()
        var title = actionTitle(action).toLowerCase()
        var combined = id + " " + title

        return combined.indexOf("shutdown") >= 0 ||
               combined.indexOf("poweroff") >= 0 ||
               combined.indexOf("reboot") >= 0 ||
               combined.indexOf("restart") >= 0 ||
               combined.indexOf("delete") >= 0 ||
               combined.indexOf("remove") >= 0 ||
               combined.indexOf("uninstall") >= 0 ||
               combined.indexOf("kill") >= 0 ||
               combined.indexOf("stop") >= 0
    }

    function actionBusy(action) {
        return boolFor(action, [
                           "busy",
                           "working",
                           "running",
                           "inProgress"
                       ], false)
    }

    function actionDisabled(action) {
        return boolFor(action, [
                           "disabled",
                           "locked",
                           "unavailable"
                       ], false)
    }

    function confirmText() {
        if (disabled)
            return "Unavailable"

        if (busy)
            return "Working"

        if (danger)
            return armedTab === 0 ? "Confirm" : "Arm"

        return "Run"
    }

    function confirmSubtext() {
        if (disabled)
            return "Blocked"

        if (busy)
            return "Please wait"

        if (danger)
            return armedTab === 0 ? "Press X to proceed" : "Proceed carefully"

        return "Execute action"
    }

    function helperText() {
        if (disabled)
            return "This action is unavailable."

        if (busy)
            return "This action is already running."

        if (danger && armedTab === 0)
            return "ARMED: Press X again to confirm, or O to cancel."

        if (danger)
            return "This can affect system services. Press X to arm first."

        return "Press X to run, or O to cancel."
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================
    */

    Keys.onLeftPressed: moveSelection(-1)
    Keys.onRightPressed: moveSelection(1)
    Keys.onUpPressed: moveSelection(-1)
    Keys.onDownPressed: moveSelection(1)
    Keys.onReturnPressed: activateSelected()
    Keys.onEnterPressed: activateSelected()
    Keys.onSpacePressed: activateSelected()
    Keys.onEscapePressed: cancelOrClose()
    Keys.onBackPressed: cancelOrClose()

    /*
        ============================================================
                            POINTER FALLBACK
        ============================================================
    */

    MouseArea {
        anchors.fill: parent

        enabled: root.pointerEnabled
        acceptedButtons: Qt.LeftButton

        onClicked: root.cancelOrClose()
    }

    /*
        ============================================================
                                PANEL
        ============================================================
    */

    Rectangle {
        id: modalBg

        width: Math.min(parent.width * 0.46, 820)
        height: Math.min(parent.height * 0.46, 520)

        anchors.centerIn: parent

        radius: 32

        color: "#020814"

        border.color: root.danger ? root.dangerRed : root.neutronBlue
        border.width: root.danger ? 4 : 3

        activeFocusOnTab: true

        scale: root.visible ? 1.0 : 0.94
        opacity: root.visible ? 1.0 : 0.0

        Behavior on scale {
            enabled: root.animationsEnabled

            NumberAnimation {
                duration: 180
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
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2

            radius: parent.radius - 2
            color: "#07101F"

            border.color: "#223D7D"
            border.width: 1
            z: -1
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 28
            anchors.rightMargin: 28
            anchors.topMargin: 16

            height: 1

            color: root.danger ? root.dangerRed : root.neutronBlue
            opacity: 0.65 + root.pulse * 0.18
        }

        Rectangle {
            visible: root.animationsEnabled

            width: Math.max(70, parent.width * 0.20)
            height: 2
            radius: 1

            x: 28 + (parent.width - 56 - width) * ((root.sweep + 1.0) / 2.0)
            y: 22

            color: root.danger ? root.dangerRed : root.neutronBlue
            opacity: root.danger ? 0.50 + root.pulse * 0.24 :
                                    0.28 + root.pulse * 0.18
        }

        Rectangle {
            visible: root.danger

            anchors.fill: parent
            anchors.margins: -16

            radius: parent.radius + 16
            color: root.dangerRed
            opacity: 0.035 + root.pulse * 0.030
            z: -2
        }

        MouseArea {
            anchors.fill: parent

            enabled: root.pointerEnabled
            acceptedButtons: Qt.LeftButton

            onClicked: function(mouse) {
                mouse.accepted = true
            }
        }

        Column {
            anchors.centerIn: parent

            width: parent.width - 76
            spacing: 18

            Text {
                width: parent.width

                text: root.actionName

                color: "white"

                font.pixelSize: 32
                font.bold: true
                font.letterSpacing: 0.3

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width

                text: root.actionSubtitle.length > 0
                      ? root.actionSubtitle
                      : root.danger
                        ? "System Level Action."
                        : "Run Anyway?"

                color: root.danger ? "#FFD4D8" : "#D8F4FF"

                font.pixelSize: 16
                font.bold: root.danger

                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Rectangle {
                width: parent.width
                height: 52
                radius: 20

                color: root.danger
                       ? root.armedTab === 0
                         ? "#3A0710"
                         : "#26080C"
                       : "#081426"

                border.width: 1
                border.color: root.danger
                              ? root.dangerRed
                              : "#4DA6FF"

                Text {
                    anchors.centerIn: parent

                    width: parent.width - 28

                    text: root.helperText()

                    color: root.danger
                           ? root.armedTab === 0
                             ? "#ffd1d1"
                             : "#ffb1b1"
                           : "#b9eeff"

                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 0.8

                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Row {
                spacing: 16

                anchors.horizontalCenter: parent.horizontalCenter

                ModalTabButton {
                    width: 220
                    height: 74

                    text: root.confirmText()
                    subtext: root.confirmSubtext()

                    danger: root.danger
                    focused: root.selectedTab === 0
                    active: root.selectedTab === 0
                    armed: root.armedTab === 0

                    enabled: !root.disabled && !root.busy

                    pointerEnabled: root.pointerEnabled
                    pointerFocusEnabled: false

                    onClicked: {
                        root.selectedTab = 0
                        root.activateSelected()
                    }
                }

                ModalTabButton {
                    width: 220
                    height: 74

                    text: "Cancel"
                    subtext: "Return"

                    danger: false
                    focused: root.selectedTab === 1
                    active: root.selectedTab === 1
                    armed: root.selectedTab === 1

                    pointerEnabled: root.pointerEnabled
                    pointerFocusEnabled: false

                    onClicked: {
                        root.selectedTab = 1
                        root.cancelled()
                        root.close()
                    }
                }
            }

            Text {
                width: parent.width

                text: "D-PAD choose  •  X select / confirm  •  O cancel"

                color: "#D1E2F5"

                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1.2

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    /*
        ============================================================
                            CONTROLLER CONNECTION
        ============================================================
    */

    Connections {
        target: root.controllerBackend()
        enabled: root.visible
        ignoreUnknownSignals: true

        function onButtonPressed(button) {
            root.handleController(button)
        }

        function onStickMoved(stick, x, y) {
            if (!root.visible)
                return

            var threshold = 55

            if (x > threshold)
                root.handleController("RIGHT")
            else if (x < -threshold)
                root.handleController("LEFT")
            else if (y > threshold)
                root.handleController("DOWN")
            else if (y < -threshold)
                root.handleController("UP")
        }
    }

    onSelectedTabChanged: {
        clampSelected()
    }

    onVisibleChanged: {
        if (!visible)
            armedTab = -1
    }
}