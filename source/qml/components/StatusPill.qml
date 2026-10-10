import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                              STATUS PILL
        ============================================================

        Purpose:
            Reusable compact status badge.

        Used for:
            - Login screen controller status.
            - Local Secure pill.
            - Battery status.
            - Network / SSID status.
            - App running/stopped status.
            - Service running/stopped status.
            - Developer Mode enabled/disabled badge.
            - Console header badges.
            - App toolbar badges.

        Design rules:
            - Green means healthy/running/secure.
            - Red means stopped/locked/error/danger.
            - Yellow means warning/charging/busy.
            - Blue/cyan means informational/neutral.
            - Purple means special/developer/profile.
            - No MouseArea by default.
            - Optional pointer fallback only.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles/text only.
            - Animations pause when hidden.
            - No placeholder behavior.
    */

    property var statusData: null

    property string text: valueFor(statusData, [
                                      "text",
                                      "label",
                                      "name",
                                      "title",
                                      "status",
                                      "state"
                                  ], "Status")

    property string subtext: valueFor(statusData, [
                                         "subtext",
                                         "subtitle",
                                         "description",
                                         "hint"
                                     ], "")

    property string iconText: valueFor(statusData, [
                                          "iconText",
                                          "glyph",
                                          "symbol"
                                      ], "")

    property string mode: valueFor(statusData, [
                                      "mode",
                                      "type",
                                      "level",
                                      "tone"
                                  ], "info")

    property int percent: intFor(statusData, [
                                     "percent",
                                     "battery",
                                     "batteryPercent",
                                     "value"
                                 ], -1)

    property int pillIndex: -1

    property bool focused: false
    property bool selected: focused
    property bool active: boolFor(statusData, [
                                     "active",
                                     "running",
                                     "connected",
                                     "secure",
                                     "enabled",
                                     "online"
                                 ], false)

    property bool warning: boolFor(statusData, [
                                      "warning",
                                      "charging",
                                      "busy",
                                      "pending"
                                  ], false)

    property bool danger: boolFor(statusData, [
                                     "danger",
                                     "error",
                                     "locked",
                                     "stopped",
                                     "offline",
                                     "failed",
                                     "critical"
                                 ], false)

    property bool success: boolFor(statusData, [
                                      "success",
                                      "healthy",
                                      "ready",
                                      "secure",
                                      "running",
                                      "connected",
                                      "online"
                                  ], false)

    property bool disabled: boolFor(statusData, [
                                        "disabled",
                                        "unavailable",
                                        "muted"
                                    ], false)

    property bool compact: false
    property bool showDot: true
    property bool showIcon: iconText.length > 0
    property bool showSubtext: subtext.length > 0 && !compact
    property bool showPercent: percent >= 0
    property bool showPercentBar: false
    property bool showFocusRing: true
    property bool showSweep: true
    property bool pulseWhenActive: true
    property bool pointerEnabled: false
    property bool animationsEnabled: visible && enabled

    property real radius: height / 2
    property real pulse: 0.42
    property real sweep: -1.0
    property real pressScale: 1.0

    property color infoColor: "#7df9ff"
    property color focusColor: "#4da6ff"
    property color successColor: "#22ff88"
    property color warningColor: "#facc15"
    property color dangerColor: "#ff3040"
    property color purpleColor: "#a855f7"
    property color mutedColor: "#8aa6c8"

    property color glassColor: "#071426d8"
    property color glassFocusedColor: "#0a1b34e8"
    property color glassDangerColor: "#26070cdd"
    property color glassSuccessColor: "#16472fe8"
    property color glassWarningColor: "#40340de8"
    property color glassInfoColor: "#103249e8"
    property color borderColor: "#2b5d8f77"
    property color textColor: "white"
    property color subtextColor: "#8aa6c8"

    signal clicked(var statusData, int pillIndex)
    signal activated(var statusData, int pillIndex)
    signal focusedRequested(int pillIndex)
    signal detailsRequested(var statusData, int pillIndex)

    implicitWidth: computedWidth()
    implicitHeight: compact ? 32 : showSubtext ? 48 : 36

    width: implicitWidth
    height: implicitHeight

    opacity: disabled ? 0.50 : 1.0
    scale: pressScale * (focused && !disabled ? 1.018 : 1.0)

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
        running: root.animationsEnabled &&
                 (root.focused || root.warning || root.danger || root.success || root.active) &&
                 root.pulseWhenActive
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.32
            to: 1.0
            duration: root.danger ? 560 :
                      root.warning ? 760 :
                      root.success || root.active ? 1500 :
                                                     1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.32
            duration: root.danger ? 560 :
                      root.warning ? 760 :
                      root.success || root.active ? 1500 :
                                                     1800
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && root.showSweep &&
                 (root.focused || root.warning || root.danger || root.success || root.active)
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.danger ? 1250 : 3200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.danger ? 1250 : 3200
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                                PANEL
        ============================================================
    */

    Rectangle {
        id: panel

        anchors.fill: parent

        radius: root.radius

        color: root.currentGlassColor()

        border.width: root.focused || root.selected ? 2 : 1
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
            opacity: root.disabled ? 0.014 : 0.030
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 5

            height: 1
            radius: 1

            color: "#ffffff"
            opacity: root.disabled ? 0.020 : 0.085
        }

        Rectangle {
            visible: root.showSweep

            width: Math.max(32, parent.width * 0.22)
            height: 1
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)
            y: 0

            color: root.currentAccentColor()
            opacity: root.focused || root.warning || root.danger || root.success || root.active
                     ? 0.18 + root.pulse * 0.16
                     : 0.0
        }
    }

    FocusRing {
        anchors.fill: parent

        visible: root.showFocusRing
        focused: root.focused && !root.disabled

        radius: root.radius
        margin: 3
        lineWidth: 2

        showCorners: false
        showBottomBar: false
        showSweep: false
        showOuterGlow: true
    }

    /*
        ============================================================
                                CONTENT
        ============================================================
    */

    Row {
        id: contentRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.compact ? 10 : 12
        anchors.rightMargin: root.compact ? 10 : 12

        spacing: root.compact ? 6 : 8

        Rectangle {
            visible: root.showDot

            anchors.verticalCenter: parent.verticalCenter

            width: root.compact ? 8 : 10
            height: width
            radius: width / 2

            color: root.currentAccentColor()
            opacity: root.warning || root.danger ? 0.52 + root.pulse * 0.36 : 0.95

            border.width: 1
            border.color: "#02060d"
        }

        Text {
            visible: root.showIcon

            anchors.verticalCenter: parent.verticalCenter

            text: root.iconText

            color: root.currentAccentColor()

            font.pixelSize: root.compact ? 12 : 14
            font.bold: true
            font.letterSpacing: 0.4

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            width: Math.max(12, implicitWidth)
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            width: parent.width -
                   (root.showDot ? 10 + parent.spacing : 0) -
                   (root.showIcon ? 18 + parent.spacing : 0) -
                   (root.showPercent ? percentText.width + parent.spacing : 0)

            spacing: -1

            Text {
                width: parent.width

                text: root.displayText()

                color: root.disabled ? root.subtextColor : root.textColor

                font.pixelSize: root.compact ? 11 : 13
                font.bold: true
                font.letterSpacing: 0.6

                elide: Text.ElideRight
                maximumLineCount: 1
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                visible: root.showSubtext

                width: parent.width

                text: root.displaySubtext()

                color: root.subtextColor

                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.2

                elide: Text.ElideRight
                maximumLineCount: 1
                verticalAlignment: Text.AlignVCenter
            }
        }

        Text {
            id: percentText

            visible: root.showPercent

            anchors.verticalCenter: parent.verticalCenter

            text: root.clampedPercent() + "%"

            color: root.currentAccentColor()

            font.pixelSize: root.compact ? 10 : 12
            font.bold: true
            font.letterSpacing: 0.2

            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    /*
        ============================================================
                            OPTIONAL PERCENT BAR
        ============================================================
    */

    Rectangle {
        visible: root.showPercentBar && root.showPercent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.bottomMargin: 4

        height: 3
        radius: height / 2

        color: "#22324a"

        Rectangle {
            width: parent.width * (root.clampedPercent() / 100.0)
            height: parent.height
            radius: parent.radius

            color: root.currentAccentColor()

            Behavior on width {
                enabled: root.animationsEnabled

                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }
        }
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
            root.focusedRequested(root.pillIndex)
        }

        onPressed: {
            root.pressScale = 0.975
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
                            PUBLIC API
        ============================================================
    */

    function activate() {
        if (root.disabled)
            return false

        root.activated(root.statusData, root.pillIndex)
        root.clicked(root.statusData, root.pillIndex)
        return true
    }

    function setFocused(value) {
        root.focused = !!value
        root.selected = root.focused

        if (root.focused)
            root.focusedRequested(root.pillIndex)
    }

    function setSelected(value) {
        root.selected = !!value
        root.focused = root.selected
    }

    function handleController(action) {
        if (root.disabled)
            return false

        var normalized = normalizeController(action)

        if (normalized === "X" || normalized === "START")
            return activate()

        if (normalized === "TRIANGLE") {
            root.detailsRequested(root.statusData, root.pillIndex)
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

    function intFor(source, keys, fallbackValue) {
        if (!source)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = Number(source[keys[i]])

                if (!isNaN(value))
                    return Math.round(value)
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
                        textValue === "connected" ||
                        textValue === "online" ||
                        textValue === "secure" ||
                        textValue === "enabled" ||
                        textValue === "healthy" ||
                        textValue === "ready" ||
                        textValue === "warning" ||
                        textValue === "charging" ||
                        textValue === "busy" ||
                        textValue === "danger" ||
                        textValue === "error" ||
                        textValue === "locked" ||
                        textValue === "stopped" ||
                        textValue === "offline" ||
                        textValue === "failed" ||
                        textValue === "critical" ||
                        textValue === "disabled") {
                    return true
                }

                if (textValue === "false" ||
                        textValue === "0" ||
                        textValue === "no" ||
                        textValue === "stopped" ||
                        textValue === "inactive" ||
                        textValue === "offline" ||
                        textValue === "unlocked" ||
                        textValue === "idle" ||
                        textValue === "safe" ||
                        textValue === "available") {
                    return false
                }
            } catch (e2) {
            }
        }

        return fallbackValue
    }

    function clampedPercent() {
        var value = Number(root.percent)

        if (isNaN(value))
            value = 0

        return Math.max(0, Math.min(100, Math.round(value)))
    }

    function displayText() {
        var out = cleanText(root.text)

        if (out.length > 0)
            return out

        return "Status"
    }

    function displaySubtext() {
        return cleanText(root.subtext)
    }

    function currentGlassColor() {
        if (root.disabled)
            return "#05080faa"

        if (root.danger)
            return root.glassDangerColor

        if (root.warning)
            return root.glassWarningColor

        if (root.success || root.active)
            return root.glassSuccessColor

        if (root.mode.toLowerCase() === "developer" ||
                root.mode.toLowerCase() === "special" ||
                root.mode.toLowerCase() === "profile")
            return "#321858e8"

        if (root.focused || root.selected)
            return root.glassFocusedColor

        return root.mode.toLowerCase() === "info" ? root.glassInfoColor : root.glassColor
    }

    function currentBorderColor() {
        if (root.disabled)
            return "#1f2a4488"

        if (root.danger)
            return root.dangerColor

        if (root.warning)
            return root.warningColor

        if (root.success || root.active)
            return root.successColor

        if (root.mode.toLowerCase() === "developer" ||
                root.mode.toLowerCase() === "special" ||
                root.mode.toLowerCase() === "profile") {
            return root.purpleColor
        }

        if (root.focused || root.selected)
            return root.focusColor

        return root.borderColor
    }

    function currentAccentColor() {
        if (root.disabled)
            return root.mutedColor

        if (root.danger)
            return root.dangerColor

        if (root.warning)
            return root.warningColor

        if (root.success || root.active)
            return root.successColor

        if (root.mode.toLowerCase() === "developer" ||
                root.mode.toLowerCase() === "special" ||
                root.mode.toLowerCase() === "profile") {
            return root.purpleColor
        }

        if (root.focused || root.selected)
            return root.infoColor

        return root.infoColor
    }

    function computedWidth() {
        var base = root.compact ? 92 : 122

        var textLen = root.displayText().length
        var subLen = root.displaySubtext().length

        base += Math.min(160, textLen * (root.compact ? 6 : 7))

        if (root.showSubtext)
            base = Math.max(base, 120 + Math.min(170, subLen * 5))

        if (root.showIcon)
            base += 20

        if (root.showDot)
            base += 14

        if (root.showPercent)
            base += 42

        return Math.max(root.compact ? 96 : 132, Math.min(base, root.compact ? 260 : 340))
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
            focusedRequested(pillIndex)
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
