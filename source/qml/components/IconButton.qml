import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                               ICON BUTTON
        ============================================================

        Purpose:
            Reusable controller-first icon action component.

        Used for:
            - Toolbar icons.
            - Dock icons.
            - App header controls.
            - Modal action icons.
            - Quick command shortcuts.
            - Settings rows.
            - Small app/service controls.

        Design rules:
            - This is NOT a QtQuick Controls Button.
            - Controller-first.
            - Pointer support is optional fallback only.
            - Blue focus means selected/navigation focus.
            - Red armed state means destructive confirmation.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles/text/image only.
            - Animations stop when hidden/inactive.
            - Uses apps/icons only, never quickactions paths.
    */

    property var actionData: null

    property string actionId: valueFor(actionData, [
                                          "id",
                                          "actionId",
                                          "backendAction",
                                          "action",
                                          "command"
                                      ], "")

    property string text: valueFor(actionData, [
                                      "name",
                                      "title",
                                      "label",
                                      "displayName"
                                  ], "")

    property string label: text
    property string subtitle: valueFor(actionData, [
                                           "subtitle",
                                           "description",
                                           "hint",
                                           "type"
                                       ], "")

    property string iconName: valueFor(actionData, [
                                           "icon",
                                           "iconName",
                                           "iconId"
                                       ], "")

    property string iconSource: valueFor(actionData, [
                                             "iconSource",
                                             "iconPath",
                                             "image",
                                             "imageSource"
                                         ], "")

    property string fallbackGlyph: ""

    property int buttonIndex: -1

    property bool focused: false
    property bool selected: focused
    property bool checked: false
    property bool armed: false
    property bool danger: inferredDanger()
    property bool destructive: danger
    property bool busy: boolFor(actionData, [
                                    "busy",
                                    "working",
                                    "running",
                                    "inProgress"
                                ], false)
    property bool disabled: boolFor(actionData, [
                                        "disabled",
                                        "locked",
                                        "unavailable"
                                    ], false)

    property bool pointerEnabled: true
    property bool keyboardEnabled: true
    property bool animationsEnabled: visible && enabled
    property bool showLabel: true
    property bool showSubtitle: subtitle.length > 0
    property bool showStatusDot: false
    property bool showFrame: true
    property bool showFocusRing: true
    property bool showArmedRing: true
    property bool compact: false

    property real radius: compact ? 18 : 22
    property real iconSize: compact ? 28 : 38

    property color glassColor: checked ? "#0d2547e8" : "#071426d8"
    property color glassColorFocused: "#0a1b34ec"
    property color glassColorArmed: "#26070cdd"
    property color borderColor: "#2b5d8f77"
    property color focusColor: "#4da6ff"
    property color accentColor: "#7df9ff"
    property color dangerColor: "#ff3040"
    property color successColor: "#22ff88"
    property color warningColor: "#facc15"
    property color disabledColor: "#05080faa"
    property color textColor: "white"
    property color subtitleColor: "#8aa6c8"

    property real pulse: 0.42
    property real sweep: -1.0
    property real pressScale: 1.0

    signal clicked(var actionData, string actionId, int buttonIndex)
    signal activated(var actionData, string actionId, int buttonIndex)
    signal armedRequested(var actionData, string actionId, int buttonIndex)
    signal disarmedRequested(var actionData, string actionId, int buttonIndex)
    signal focusedRequested(int buttonIndex)
    signal detailsRequested(var actionData, string actionId, int buttonIndex)

    implicitWidth: compact ? 72 : 104
    implicitHeight: compact ? 72 : 104

    focus: focused
    activeFocusOnTab: keyboardEnabled

    opacity: disabled ? 0.52 : 1.0
    scale: pressScale * (focused && !disabled ? 1.035 : 1.0)

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 120
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
            duration: root.armed ? 560 : root.busy ? 780 : 1600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.32
            duration: root.armed ? 560 : root.busy ? 780 : 1600
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && (root.focused || root.armed || root.busy)
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.armed ? 1250 : 2600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.armed ? 1250 : 2600
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                                FRAME
        ============================================================
    */

    Rectangle {
        id: frame

        anchors.fill: parent

        visible: root.showFrame

        radius: root.radius

        color: root.currentGlassColor()

        border.width: root.focused || root.armed || root.checked ? 2 : 1
        border.color: root.currentBorderColor()

        Behavior on color {
            enabled: root.animationsEnabled

            ColorAnimation {
                duration: 150
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

            radius: Math.max(0, parent.radius - 2)

            color: "#ffffff"
            opacity: root.disabled ? 0.012 : 0.030
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 7

            height: 1
            radius: 1

            color: "#ffffff"
            opacity: root.disabled ? 0.025 : 0.095
        }

        Rectangle {
            width: Math.max(28, parent.width * 0.28)
            height: 1
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)
            y: 0

            color: root.armed ? root.dangerColor : root.accentColor
            opacity: root.focused || root.armed || root.busy
                     ? 0.18 + root.pulse * 0.18
                     : 0.0
        }
    }

    /*
        ============================================================
                            FOCUS / ARMED RINGS
        ============================================================
    */

    FocusRing {
        anchors.fill: parent

        visible: root.showFocusRing
        focused: root.focused && !root.armed && !root.disabled

        radius: root.radius
        margin: 4
        lineWidth: 2

        showBottomBar: false
        showCorners: !root.compact
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
        showBottomWarningBar: !root.compact
        showCorners: !root.compact
    }

    /*
        ============================================================
                            CONTENT
        ============================================================
    */

    Column {
        id: contentColumn

        anchors.centerIn: parent

        width: parent.width - 16
        spacing: root.compact ? 3 : 5

        Item {
            anchors.horizontalCenter: parent.horizontalCenter

            width: root.iconSize + 8
            height: root.iconSize + 8

            Rectangle {
                anchors.centerIn: parent

                width: root.iconSize + 8
                height: root.iconSize + 8
                radius: width / 2

                color: root.currentAccentColor()
                opacity: root.busy ? 0.09 + root.pulse * 0.08 :
                         root.focused || root.checked ? 0.075 + root.pulse * 0.045 :
                         root.armed ? 0.10 + root.pulse * 0.070 :
                                      0.035
            }

            Image {
                id: iconImage

                anchors.centerIn: parent

                width: root.iconSize
                height: root.iconSize

                source: root.resolvedIconSource()

                fillMode: Image.PreserveAspectFit

                smooth: true
                asynchronous: true
                cache: true
                sourceSize.width: 128
                mipmap: false

                opacity: status === Image.Ready ? 1.0 : 0.0
            }

            Text {
                visible: iconImage.status !== Image.Ready

                anchors.centerIn: parent

                text: root.resolvedGlyph()

                color: root.currentAccentColor()

                font.pixelSize: root.glyphPixelSize()
                font.bold: true
                font.letterSpacing: root.resolvedGlyph().length > 1 ? 0.2 : 1.0

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Text {
            visible: root.showLabel

            width: parent.width

            text: root.displayLabel()

            color: root.disabled ? root.subtitleColor : root.textColor

            font.pixelSize: root.compact ? 10 : 12
            font.bold: true
            font.letterSpacing: 0.5

            horizontalAlignment: Text.AlignHCenter

            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            visible: root.showSubtitle && !root.compact

            width: parent.width

            text: root.displaySubtitle()

            color: root.armed ? "#ffb1b1" : root.subtitleColor

            font.pixelSize: 9
            font.bold: root.armed

            horizontalAlignment: Text.AlignHCenter

            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    /*
        ============================================================
                            STATUS DOT / BUSY
        ============================================================
    */

    Rectangle {
        visible: root.showStatusDot || root.busy || root.checked

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 8
        anchors.topMargin: 8

        width: root.busy ? 12 : 10
        height: width
        radius: width / 2

        color: root.busy ? root.warningColor :
               root.checked ? root.successColor :
               root.currentAccentColor()

        opacity: root.busy ? 0.55 + root.pulse * 0.35 : 0.95

        border.width: 1
        border.color: "#02060d"
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
            root.pressScale = 0.965
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

    /*
        ============================================================
                            PUBLIC API
        ============================================================
    */

    function activate() {
        if (root.disabled)
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

    function disarm() {
        if (!root.armed)
            return false

        root.armed = false
        root.disarmedRequested(root.actionData, root.actionId, root.buttonIndex)
        return true
    }

    function setFocused(value) {
        root.focused = !!value

        if (root.focused)
            root.focusedRequested(root.buttonIndex)
    }

    function setArmed(value) {
        root.armed = !!value
    }

    function handleController(action) {
        if (root.disabled)
            return false

        var normalized = normalizeController(action)

        if (normalized === "X" || normalized === "START") {
            return activate()
        }

        if (normalized === "O") {
            return disarm()
        }

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

    function assetBackend() {
        try {
            if (typeof assetManager !== "undefined" && assetManager)
                return assetManager
        } catch (e) {
        }

        return null
    }

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

    function isAbsoluteSource(value) {
        var src = cleanText(value).toLowerCase()

        return src.indexOf("file:") === 0 ||
               src.indexOf("qrc:") === 0 ||
               src.indexOf("http://") === 0 ||
               src.indexOf("https://") === 0 ||
               src.indexOf("image://") === 0
    }

    function hasImageExtension(value) {
        var src = cleanText(value).toLowerCase()

        return src.indexOf(".png") > 0 ||
               src.indexOf(".jpg") > 0 ||
               src.indexOf(".jpeg") > 0 ||
               src.indexOf(".webp") > 0 ||
               src.indexOf(".svg") > 0
    }

    function themeFile(path) {
        var cleanPath = cleanText(path)

        if (cleanPath.length <= 0)
            return ""

        if (isAbsoluteSource(cleanPath))
            return cleanPath

        var assets = assetBackend()

        if (assets && typeof assets.themeFile === "function") {
            try {
                return assets.themeFile(cleanPath)
            } catch (e) {
            }
        }

        return "../themes/Default/" + cleanPath
    }

    function sanitizeIcon(value) {
        var icon = cleanText(value)

        if (icon.length <= 0)
            return ""

        icon = icon.replace(/\\/g, "/")

        if (isAbsoluteSource(icon))
            return icon

        if (icon.indexOf("/") >= 0)
            return icon

        if (hasImageExtension(icon))
            icon = icon.substring(0, icon.lastIndexOf("."))

        icon = icon.toLowerCase()
        icon = icon.replace(/\s+/g, "")
        icon = icon.replace(/[^a-z0-9_\-]/g, "")

        return icon
    }

    function resolvedIconSource() {
        var direct = cleanText(root.iconSource)

        if (direct.length > 0) {
            if (isAbsoluteSource(direct))
                return direct

            if (direct.indexOf("/") >= 0)
                return themeFile(direct)

            return themeFile("apps/icons/" + sanitizeIcon(direct) + ".png")
        }

        var icon = sanitizeIcon(root.iconName)

        if (icon.length > 0) {
            if (isAbsoluteSource(icon))
                return icon

            if (icon.indexOf("/") >= 0)
                return themeFile(icon)

            return themeFile("apps/icons/" + icon + ".png")
        }

        var idIcon = sanitizeIcon(root.actionId)

        if (idIcon.length > 0)
            return themeFile("apps/icons/" + idIcon + ".png")

        return ""
    }

    function displayLabel() {
        var out = cleanText(root.label)

        if (out.length > 0)
            return out

        out = cleanText(root.text)

        if (out.length > 0)
            return out

        out = cleanText(root.actionId)

        if (out.length > 0)
            return out

        return "Action"
    }

    function displaySubtitle() {
        return cleanText(root.subtitle)
    }

    function resolvedGlyph() {
        var explicitGlyph = cleanText(root.fallbackGlyph)

        if (explicitGlyph.length > 0)
            return explicitGlyph

        var combined = (root.actionId + " " + root.displayLabel()).toLowerCase()

        if (combined.indexOf("shutdown") >= 0 ||
                combined.indexOf("power") >= 0) {
            return "⏻"
        }

        if (combined.indexOf("restart") >= 0 ||
                combined.indexOf("reboot") >= 0) {
            return "↻"
        }

        if (combined.indexOf("update") >= 0)
            return "↑"

        if (combined.indexOf("logs") >= 0 ||
                combined.indexOf("journal") >= 0) {
            return "≡"
        }

        if (combined.indexOf("settings") >= 0 ||
                combined.indexOf("config") >= 0) {
            return "⚙"
        }

        if (combined.indexOf("terminal") >= 0 ||
                combined.indexOf("shell") >= 0) {
            return ">_"
        }

        if (combined.indexOf("storage") >= 0 ||
                combined.indexOf("disk") >= 0) {
            return "▣"
        }

        if (combined.indexOf("docker") >= 0 ||
                combined.indexOf("container") >= 0) {
            return "◆"
        }

        if (combined.indexOf("jellyfin") >= 0)
            return "J"

        if (combined.indexOf("qbit") >= 0 ||
                combined.indexOf("torrent") >= 0) {
            return "Q"
        }

        var labelText = displayLabel()

        if (labelText.length > 0)
            return labelText.charAt(0).toUpperCase()

        return "•"
    }

    function glyphPixelSize() {
        var glyph = resolvedGlyph()

        if (glyph.length > 2)
            return root.compact ? 13 : 16

        if (glyph.length > 1)
            return root.compact ? 16 : 20

        return root.compact ? 25 : 31
    }

    function inferredDanger() {
        if (boolFor(actionData, [
                    "danger",
                    "destructive",
                    "confirmRequired",
                    "requiresConfirmation"
                ], false)) {
            return true
        }

        var combined = (root.actionId + " " + root.text + " " + root.label).toLowerCase()

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

    function currentGlassColor() {
        if (root.disabled)
            return root.disabledColor

        if (root.armed)
            return root.glassColorArmed

        if (root.focused || root.selected)
            return root.glassColorFocused

        return root.glassColor
    }

    function currentBorderColor() {
        if (root.disabled)
            return "#1f2a4488"

        if (root.armed)
            return root.dangerColor

        if (root.focused || root.selected)
            return root.focusColor

        if (root.checked)
            return root.successColor

        return root.borderColor
    }

    function currentAccentColor() {
        if (root.disabled)
            return root.subtitleColor

        if (root.armed)
            return root.dangerColor

        if (root.busy)
            return root.warningColor

        if (root.checked)
            return root.successColor

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

    onFocusedChanged: {
        if (focused)
            focusedRequested(buttonIndex)
    }

    onVisibleChanged: {
        if (!visible) {
            pulse = 0.42
            sweep = -1.0
            pressScale = 1.0
        }
    }
}
