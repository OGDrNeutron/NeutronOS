import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            NEUTRON TEXT FIELD
        ============================================================

        Purpose:
            Reusable controller-first text input surface.

        Used for:
            - Login password fallback.
            - Developer Mode keyboard fallback.
            - Terminal type bar.
            - Settings fields.
            - Search bars.
            - Web mirror token entry.
            - App configuration text input.

        Design rules:
            - This is NOT a QtQuick Controls TextField.
            - Uses raw TextInput.
            - No invalid background property.
            - Controller-first.
            - X begins editing / accepts.
            - O cancels editing.
            - Triangle clears when allowed.
            - Pointer support is optional fallback only.
            - Blue focus means selected/navigation focus.
            - Red error/armed state is visual only here.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles/text only.
            - Animations pause when hidden.
            - No placeholder behavior.
    */

    property alias text: input.text

    property string placeholderText: ""
    property string label: ""
    property string subtext: ""
    property string helperText: ""

    property int fieldIndex: -1

    property bool selected: false
    property bool focused: selected
    property bool editing: false
    property bool disabled: false
    property bool readOnly: false
    property bool passwordMode: false
    property bool error: false
    property bool warning: false
    property bool success: false
    property bool required: false
    property bool clearAllowed: true

    property bool pointerEnabled: true
    property bool keyboardEnabled: true
    property bool animationsEnabled: visible && enabled
    property bool showFocusRing: true
    property bool showStatusDot: error || warning || success || required
    property bool showLabel: label.length > 0
    property bool showHelper: helperText.length > 0 || subtext.length > 0 || error || warning || success
    property bool compact: false

    property int maximumLength: 32767
    property int echoMode: passwordMode ? TextInput.Password : TextInput.Normal
    property int inputMethodHints: Qt.ImhNone

    property real radius: compact ? 18 : 22
    property real pressScale: 1.0
    property real pulse: 0.42
    property real sweep: -1.0

    property color glassColor: "#071426d8"
    property color glassFocusedColor: "#0a1b34e8"
    property color borderColor: "#2b5d8f77"
    property color focusColor: "#4da6ff"
    property color accentColor: "#7df9ff"
    property color dangerColor: "#ff3040"
    property color warningColor: "#facc15"
    property color successColor: "#22ff88"
    property color textColor: "white"
    property color placeholderColor: "#6f86a8"
    property color subtextColor: "#8aa6c8"
    property color disabledColor: "#05080faa"

    signal accepted(string text, int fieldIndex)
    signal cancelled(int fieldIndex)
    signal cleared(int fieldIndex)
    signal textEdited(string text, int fieldIndex)
    signal editingStarted(int fieldIndex)
    signal editingFinished(string text, int fieldIndex)
    signal focusedRequested(int fieldIndex)
    signal virtualKeyboardRequested(int fieldIndex, string currentText)

    implicitWidth: 360
    implicitHeight: compact ? 52 : showLabel || showHelper ? 82 : 62

    focus: focused
    activeFocusOnTab: keyboardEnabled

    opacity: disabled ? 0.50 : 1.0
    scale: pressScale * (focused && !disabled ? 1.012 : 1.0)

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
        running: root.animationsEnabled && (root.focused || root.editing || root.error || root.warning || root.success)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.32
            to: 1.0
            duration: root.error ? 560 : root.editing ? 1180 : 1700
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.32
            duration: root.error ? 560 : root.editing ? 1180 : 1700
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && (root.focused || root.editing || root.error)
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.error ? 1200 : 2800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.error ? 1200 : 2800
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

        anchors.fill: fieldPanel

        radius: root.radius
        padding: 0

        focused: root.focused && !root.error && !root.disabled
        armed: root.error && !root.disabled
        highlighted: root.editing || root.success || root.warning
        disabled: root.disabled

        panelColor: root.focused || root.editing ? root.glassFocusedColor : root.glassColor
        borderColor: root.borderColor
        focusColor: root.focusColor
        accentColor: root.currentAccentColor()
        dangerColor: root.dangerColor

        sweepEnabled: true
        pulseEnabled: true
        showTopLine: true
        showInnerLine: true
        showOuterGlow: true
        showBottomLine: root.editing || root.success || root.warning
    }

    FocusRing {
        anchors.fill: fieldPanel

        visible: root.showFocusRing
        focused: root.focused && !root.error && !root.disabled

        radius: root.radius
        margin: 4
        lineWidth: 2

        showCorners: false
        showBottomBar: false
    }

    /*
        ============================================================
                            LAYOUT ANCHOR
        ============================================================
    */

    Item {
        id: fieldPanel

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        height: root.compact ? 48 : 56
    }

    /*
        ============================================================
                            LABEL / HELPER
        ============================================================
    */

    Text {
        id: labelText

        visible: root.showLabel && !root.compact

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: fieldPanel.top
        anchors.bottomMargin: 5

        text: root.displayLabel()

        color: root.currentAccentColor()

        font.pixelSize: 12
        font.bold: true
        font.letterSpacing: 1.0

        elide: Text.ElideRight
        maximumLineCount: 1
    }

    Text {
        id: helper

        visible: root.showHelper && !root.compact

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: fieldPanel.bottom
        anchors.topMargin: 5

        text: root.displayHelperText()

        color: root.error ? root.dangerColor :
               root.warning ? root.warningColor :
               root.success ? root.successColor :
                              root.subtextColor

        font.pixelSize: 11
        font.bold: root.error || root.warning || root.success
        font.letterSpacing: 0.4

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

    /*
        ============================================================
                                INPUT
        ============================================================
    */

    TextInput {
        id: input

        anchors.left: fieldPanel.left
        anchors.right: statusArea.left
        anchors.verticalCenter: fieldPanel.verticalCenter
        anchors.leftMargin: 18
        anchors.rightMargin: 10

        height: fieldPanel.height - 14

        enabled: !root.disabled && !root.readOnly
        focus: root.editing && !root.disabled && !root.readOnly

        color: root.disabled ? root.subtextColor : root.textColor
        selectedTextColor: "#02060d"
        selectionColor: root.currentAccentColor()

        font.pixelSize: root.compact ? 16 : 18
        font.bold: true
        font.letterSpacing: 0.3

        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignLeft

        echoMode: root.echoMode
        maximumLength: root.maximumLength
        inputMethodHints: root.inputMethodHints

        cursorVisible: root.editing && activeFocus
        clip: true

        onTextEdited: {
            root.textEdited(text, root.fieldIndex)
        }

        onAccepted: {
            root.accept()
        }

        Keys.onEscapePressed: {
            root.cancelEdit()
        }

        Keys.onBackPressed: {
            root.cancelEdit()
        }
    }

    Text {
        visible: input.text.length <= 0 && !root.editing

        anchors.left: input.left
        anchors.right: input.right
        anchors.verticalCenter: input.verticalCenter

        text: root.placeholderText

        color: root.placeholderColor

        font.pixelSize: root.compact ? 16 : 18
        font.bold: true
        font.letterSpacing: 0.2

        elide: Text.ElideRight
        maximumLineCount: 1
    }

    /*
        ============================================================
                            STATUS AREA
        ============================================================
    */

    Item {
        id: statusArea

        anchors.right: fieldPanel.right
        anchors.verticalCenter: fieldPanel.verticalCenter
        anchors.rightMargin: 14

        width: 34
        height: fieldPanel.height

        Rectangle {
            visible: root.showStatusDot

            anchors.centerIn: parent

            width: root.editing ? 12 : 10
            height: width
            radius: width / 2

            color: root.currentAccentColor()
            opacity: root.error || root.warning ? 0.55 + root.pulse * 0.35 : 0.95

            border.width: 1
            border.color: "#02060d"
        }

        Text {
            visible: !root.showStatusDot && root.passwordMode

            anchors.centerIn: parent

            text: "●"

            color: root.subtextColor

            font.pixelSize: 11
            font.bold: true
        }
    }

    /*
        ============================================================
                            MOVING TOP SWEEP
        ============================================================
    */

    Rectangle {
        visible: root.focused || root.editing || root.error || root.warning || root.success

        width: Math.max(46, fieldPanel.width * 0.18)
        height: 1
        radius: 1

        x: fieldPanel.x + (fieldPanel.width - width) * ((root.sweep + 1.0) / 2.0)
        y: fieldPanel.y

        color: root.currentAccentColor()
        opacity: root.disabled ? 0.0 :
                 root.error ? 0.24 + root.pulse * 0.22 :
                 root.editing ? 0.20 + root.pulse * 0.18 :
                                0.14 + root.pulse * 0.12
    }

    /*
        ============================================================
                            OPTIONAL POINTER FALLBACK
        ============================================================
    */

    MouseArea {
        anchors.fill: fieldPanel

        enabled: root.pointerEnabled && !root.disabled
        acceptedButtons: Qt.LeftButton
        hoverEnabled: root.pointerEnabled

        onEntered: {
            root.focusedRequested(root.fieldIndex)
        }

        onPressed: {
            root.pressScale = 0.985
        }

        onReleased: {
            root.pressScale = 1.0
        }

        onCanceled: {
            root.pressScale = 1.0
        }

        onClicked: {
            root.beginEdit()
        }
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================
    */

    Keys.enabled: root.keyboardEnabled && root.focused && !root.disabled && !root.editing

    Keys.onReturnPressed: root.beginEdit()
    Keys.onEnterPressed: root.beginEdit()
    Keys.onSpacePressed: root.beginEdit()

    /*
        ============================================================
                            PUBLIC API
        ============================================================
    */

    function beginEdit() {
        if (root.disabled || root.readOnly)
            return false

        root.selected = true
        root.focused = true
        root.editing = true

        root.forceActiveFocus()
        input.forceActiveFocus()

        root.editingStarted(root.fieldIndex)
        root.virtualKeyboardRequested(root.fieldIndex, input.text)

        return true
    }

    function accept() {
        if (root.disabled)
            return false

        if (!root.editing) {
            beginEdit()
            return true
        }

        root.editing = false
        root.forceActiveFocus()

        root.editingFinished(input.text, root.fieldIndex)
        root.accepted(input.text, root.fieldIndex)

        return true
    }

    function cancelEdit() {
        if (!root.editing)
            return false

        root.editing = false
        root.forceActiveFocus()
        root.cancelled(root.fieldIndex)

        return true
    }

    function clear() {
        if (root.disabled || root.readOnly || !root.clearAllowed)
            return false

        input.text = ""
        root.textEdited(input.text, root.fieldIndex)
        root.cleared(root.fieldIndex)

        return true
    }

    function setFocused(value) {
        root.focused = !!value
        root.selected = root.focused

        if (root.focused)
            root.focusedRequested(root.fieldIndex)
        else if (root.editing)
            cancelEdit()
    }

    function setSelected(value) {
        root.selected = !!value
        root.focused = root.selected
    }

    function handleController(action) {
        if (root.disabled)
            return false

        var normalized = normalizeController(action)

        if (normalized === "X" || normalized === "START") {
            if (root.editing)
                return accept()

            return beginEdit()
        }

        if (normalized === "O") {
            if (root.editing)
                return cancelEdit()

            return false
        }

        if (normalized === "TRIANGLE") {
            return clear()
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

    function displayLabel() {
        return cleanText(root.label)
    }

    function displayHelperText() {
        if (root.error)
            return cleanText(root.helperText).length > 0 ? root.helperText : "Invalid entry"

        if (root.warning)
            return cleanText(root.helperText).length > 0 ? root.helperText : "Check this value"

        if (root.success)
            return cleanText(root.helperText).length > 0 ? root.helperText : "Saved"

        if (cleanText(root.helperText).length > 0)
            return root.helperText

        return cleanText(root.subtext)
    }

    function currentAccentColor() {
        if (root.disabled)
            return root.subtextColor

        if (root.error)
            return root.dangerColor

        if (root.warning)
            return root.warningColor

        if (root.success)
            return root.successColor

        if (root.editing)
            return root.accentColor

        if (root.focused || root.selected)
            return root.focusColor

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
            focusedRequested(fieldIndex)
        } else if (editing) {
            cancelEdit()
        }
    }

    onVisibleChanged: {
        if (!visible) {
            pulse = 0.42
            sweep = -1.0
            pressScale = 1.0
            editing = false
        }
    }
}