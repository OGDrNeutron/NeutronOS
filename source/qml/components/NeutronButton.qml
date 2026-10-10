import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                             NEUTRON BUTTON
        ============================================================

        Preserved from existing file:
            - text property.
            - subtext property.
            - selected property.
            - disabled property.
            - default width: 220.
            - default height: 56 or 72 when subtext exists.
            - selected maps to focus styling.
            - danger styling support.

        Production updates:
            - Removed Theme.qml dependency.
            - Removed Metrics.qml dependency.
            - Removed GlassCard dependency from this button layer.
            - Uses GlassPanel, FocusRing, and ArmedRing.
            - Controller-first activation.
            - Optional pointer fallback only.
            - Supports dangerous arm-before-confirm behavior.
            - Supports checked, busy, compact, wide, and primary styles.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles/text only.
            - Animations pause when hidden.
            - No placeholder behavior.
    */

    property var actionData: null

    property string text: valueFor(actionData, [
                                      "name",
                                      "title",
                                      "label",
                                      "displayName"
                                  ], "Button")

    property string subtext: valueFor(actionData, [
                                         "subtext",
                                         "subtitle",
                                         "description",
                                         "hint"
                                     ], "")

    property string actionId: valueFor(actionData, [
                                          "id",
                                          "actionId",
                                          "backendAction",
                                          "action",
                                          "command"
                                      ], "")

    property int buttonIndex: -1

    property bool selected: false
    property bool focused: selected
    property bool active: focused || selected
    property bool checked: boolFor(actionData, [
                                      "checked",
                                      "active",
                                      "enabled"
                                  ], false)

    property bool disabled: boolFor(actionData, [
                                        "disabled",
                                        "locked",
                                        "unavailable"
                                    ], false)

    property bool busy: boolFor(actionData, [
                                    "busy",
                                    "working",
                                    "running",
                                    "inProgress"
                                ], false)

    property bool danger: boolFor(actionData, [
                                      "danger",
                                      "destructive",
                                      "confirmRequired",
                                      "requiresConfirmation"
                                  ], false) || inferredDanger()

    property bool destructive: danger
    property bool armed: false
    property bool primary: false
    property bool compact: false
    property bool wide: false

    property bool pointerEnabled: true
    property bool keyboardEnabled: true
    property bool animationsEnabled: visible && enabled
    property bool showFocusRing: true
    property bool showArmedRing: true
    property bool showStatusDot: busy || checked
    property bool autoDisarmOnFocusLoss: true

    property real radius: compact ? 18 : 22
    property real pressScale: 1.0
    property real pulse: 0.42
    property real sweep: -1.0

    property color glassColor: "#071426d8"
    property color glassFocusedColor: "#0a1b34e8"
    property color glassArmedColor: "#26070cdd"
    property color borderColor: "#2b5d8f77"
    property color focusColor: "#4da6ff"
    property color accentColor: "#7df9ff"
    property color primaryColor: "#a855f7"
    property color dangerColor: "#ff3040"
    property color successColor: "#22ff88"
    property color warningColor: "#facc15"
    property color textColor: "white"
    property color subtextColor: "#8aa6c8"
    property color disabledColor: "#05080faa"

    signal clicked(var actionData, string actionId, int buttonIndex)
    signal activated(var actionData, string actionId, int buttonIndex)
    signal armedRequested(var actionData, string actionId, int buttonIndex)
    signal disarmedRequested(var actionData, string actionId, int buttonIndex)
    signal focusedRequested(int buttonIndex)
    signal detailsRequested(var actionData, string actionId, int buttonIndex)

    width: wide ? 300 : 220
    height: compact ? 48 : root.displaySubtext().length > 0 ? 72 : 56

    focus: focused
    activeFocusOnTab: keyboardEnabled

    opacity: disabled ? 0.48 : 1.0
    scale: pressScale * (focused && !disabled ? 1.025 : 1.0)

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 130
            easing.type: Easing.OutCubic
        }
    }

    Behavior on scale {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled && (root.focused || root.armed || root.checked || root.busy)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.32
            to: 1.0
            duration: root.armed ? 560 : root.busy ? 760 : 1600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.32
            duration: root.armed ? 560 : root.busy ? 760 : 1600
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && (root.focused || root.armed || root.primary || root.busy)
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.armed ? 1250 : 2800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.armed ? 1250 : 2800
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                                PANEL
        ============================================================
    */

    GlassPanel {
        id: panel

        anchors.fill: parent

        radius: root.radius
        padding: 0

        focused: root.focused && !root.armed && !root.disabled
        armed: root.armed && !root.disabled
        highlighted: root.primary || root.checked
        disabled: root.disabled

        panelColor: root.armed ? root.glassArmedColor :
                    root.focused ? root.glassFocusedColor :
                                   root.glassColor

        borderColor: root.borderColor
        focusColor: root.focusColor
        accentColor: root.currentAccentColor()
        dangerColor: root.dangerColor

        sweepEnabled: true
        pulseEnabled: true
        showTopLine: true
        showInnerLine: true
        showOuterGlow: true
        showBottomLine: root.primary || root.checked || root.busy
    }

    FocusRing {
        anchors.fill: parent

        visible: root.showFocusRing
        focused: root.focused && !root.armed && !root.disabled

        radius: root.radius
        margin: 4
        lineWidth: 2

        showCorners: false
        showBottomBar: false
    }

    ArmedRing {
        anchors.fill: parent

        visible: root.showArmedRing
        armed: root.armed && !root.disabled

        radius: root.radius
        margin: 5
        lineWidth: 3

        label: "ARMED"
        subtitle: root.compact ? "" : "CONFIRM"
        showSubtitle: !root.compact
        showCorners: false
        showBottomWarningBar: false
    }

    /*
        ============================================================
                                CONTENT
        ============================================================
    */

    Row {
        id: contentRow

        anchors.fill: parent
        anchors.leftMargin: root.compact ? 14 : 18
        anchors.rightMargin: root.compact ? 14 : 18

        spacing: 10

        Rectangle {
            id: statusPip

            visible: root.showStatusDot || root.primary || root.danger

            anchors.verticalCenter: parent.verticalCenter

            width: root.compact ? 8 : 10
            height: width
            radius: width / 2

            color: root.currentAccentColor()

            opacity: root.busy ? 0.55 + root.pulse * 0.35 :
                     root.focused || root.armed || root.checked || root.primary ? 0.95 :
                                                                                   0.72

            border.width: 1
            border.color: "#02060d"
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            width: parent.width -
                   parent.spacing -
                   (statusPip.visible ? statusPip.width : 0)

            spacing: root.compact ? 1 : 3

            Text {
                width: parent.width

                text: root.displayText()

                color: root.disabled ? root.subtextColor :
                       root.armed ? "#ffd1d1" :
                                    root.textColor

                font.pixelSize: root.compact ? 14 : 17
                font.bold: true
                font.letterSpacing: 0.4

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                elide: Text.ElideRight
                maximumLineCount: 1

                Behavior on color {
                    enabled: root.animationsEnabled

                    ColorAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Text {
                visible: root.displaySubtext().length > 0 && !root.compact

                width: parent.width

                text: root.armed ? "Press X again to confirm" : root.displaySubtext()

                color: root.armed ? "#ffb1b1" :
                       root.busy ? root.warningColor :
                                   root.subtextColor

                font.pixelSize: 11
                font.bold: root.armed || root.busy
                font.letterSpacing: root.armed ? 0.7 : 0.2

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                elide: Text.ElideRight
                maximumLineCount: 1

                Behavior on color {
                    enabled: root.animationsEnabled

                    ColorAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    /*
        ============================================================
                            MOVING TOP SWEEP
        ============================================================
    */

    Rectangle {
        visible: root.focused || root.armed || root.primary || root.busy

        width: Math.max(46, root.width * 0.22)
        height: 1
        radius: 1

        x: (root.width - width) * ((root.sweep + 1.0) / 2.0)
        y: 0

        color: root.currentAccentColor()
        opacity: root.disabled ? 0.0 :
                 root.armed ? 0.24 + root.pulse * 0.22 :
                 root.busy ? 0.18 + root.pulse * 0.20 :
                              0.16 + root.pulse * 0.14
    }

    /*
        ============================================================
                            OPTIONAL POINTER FALLBACK
        ============================================================
    */

    MouseArea {
        anchors.fill: parent

        enabled: root.pointerEnabled && !root.disabled
        acceptedButtons: Qt.LeftButton
        hoverEnabled: root.pointerEnabled

        onEntered: {
            root.focusedRequested(root.buttonIndex)
        }

        onPressed: {
            root.pressScale = 0.970
        }

        onReleased: {
            root.pressScale = 1.0
        }

        onCanceled: {
            root.pressScale = 1.0
        }

        onClicked: {
            root.activate()
        }
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================
    */

    Keys.enabled: root.keyboardEnabled && root.focused && !root.disabled

    Keys.onReturnPressed: root.activate()
    Keys.onEnterPressed: root.activate()
    Keys.onSpacePressed: root.activate()
    Keys.onEscapePressed: root.disarm()
    Keys.onBackPressed: root.disarm()

    /*
        ============================================================
                            PUBLIC API
        ============================================================
    */

    function activate() {
        if (root.disabled || root.busy)
            return false

        if (root.destructive || root.danger) {
            if (!root.armed) {
                root.armed = true
                root.armedRequested(root.actionData, root.actionId, root.buttonIndex)
                return true
            }

            root.activated(root.actionData, root.actionId, root.buttonIndex)
            root.clicked(root.actionData, root.actionId, root.buttonIndex)
            return true
        }

        root.activated(root.actionData, root.actionId, root.buttonIndex)
        root.clicked(root.actionData, root.actionId, root.buttonIndex)
        return true
    }

    function click() {
        return activate()
    }

    function disarm() {
        if (!root.armed)
            return false

        root.armed = false
        root.disarmedRequested(root.actionData, root.actionId, root.buttonIndex)
        return true
    }

    function setFocused(value) {
        root.focused = !!value
        root.selected = root.focused

        if (root.focused)
            root.focusedRequested(root.buttonIndex)
    }

    function setSelected(value) {
        root.selected = !!value
        root.focused = root.selected
    }

    function setArmed(value) {
        root.armed = !!value
    }

    function handleController(action) {
        if (root.disabled)
            return false

        var normalized = normalizeController(action)

        if (normalized === "X" || normalized === "START")
            return activate()

        if (normalized === "O")
            return disarm()

        if (normalized === "TRIANGLE") {
            root.detailsRequested(root.actionData, root.actionId, root.buttonIndex)
            return true
        }

        return false
    }

    /*
        ============================================================
                            SAFE HELPERS
        ============================================================
    */

    function cleanText(value) {
        if (value === undefined || value === null)
            return ""

        var out = String(value).trim()

        if (out === "undefined" || out === "null")
            return ""

        return out
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

                var textValue = String(raw).trim().toLowerCase()

                if (textValue === "true" ||
                        textValue === "1" ||
                        textValue === "yes" ||
                        textValue === "running" ||
                        textValue === "active" ||
                        textValue === "busy" ||
                        textValue === "disabled" ||
                        textValue === "danger" ||
                        textValue === "destructive" ||
                        textValue === "required") {
                    return true
                }

                if (textValue === "false" ||
                        textValue === "0" ||
                        textValue === "no" ||
                        textValue === "stopped" ||
                        textValue === "inactive" ||
                        textValue === "idle" ||
                        textValue === "enabled" ||
                        textValue === "safe") {
                    return false
                }
            } catch (e2) {
            }
        }

        return fallbackValue
    }

    function displayText() {
        var out = cleanText(root.text)

        if (out.length > 0)
            return out

        out = cleanText(root.actionId)

        if (out.length > 0)
            return out

        return "Button"
    }

    function displaySubtext() {
        return cleanText(root.subtext)
    }

    function inferredDanger() {
        var combined = (root.actionId + " " + root.text + " " + root.subtext).toLowerCase()

        return combined.indexOf("shutdown") >= 0 ||
               combined.indexOf("poweroff") >= 0 ||
               combined.indexOf("reboot") >= 0 ||
               combined.indexOf("restart") >= 0 ||
               combined.indexOf("stop") >= 0 ||
               combined.indexOf("kill") >= 0 ||
               combined.indexOf("delete") >= 0 ||
               combined.indexOf("remove") >= 0 ||
               combined.indexOf("uninstall") >= 0
    }

    function currentAccentColor() {
        if (root.disabled)
            return root.subtextColor

        if (root.armed)
            return root.dangerColor

        if (root.danger)
            return root.dangerColor

        if (root.busy)
            return root.warningColor

        if (root.checked)
            return root.successColor

        if (root.primary)
            return root.primaryColor

        if (root.focused || root.selected)
            return root.accentColor

        return root.accentColor
    }

    function normalizeController(button) {
        var b = String(button || "").trim().toUpperCase()

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

    onSelectedChanged: {
        focused = selected
    }

    onFocusedChanged: {
        if (focused) {
            selected = true
            focusedRequested(buttonIndex)
        } else if (autoDisarmOnFocusLoss) {
            armed = false
        }
    }

    onVisibleChanged: {
        if (!visible) {
            pulse = 0.42
            sweep = -1.0
            pressScale = 1.0
        }
    }
}