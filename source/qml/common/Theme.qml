import QtQuick 2.15

QtObject {
    id: root

    readonly property bool lightMode: {
        try {
            return typeof settingsManager !== "undefined" && settingsManager &&
                   settingsManager.themeMode === "light"
        } catch (error) {
            return false
        }
    }

    /*
        ============================================================
                                  THEME
        ============================================================

        Purpose:
            Compatibility + production theme object for older shared QML
            files that still use:

                Theme { id: theme }

        Used by:
            qml/dashboard/HiddenAppDock.qml
            qml/dashboard/ConsoleHeader.qml
            qml/dashboard/QuickActionsDock.qml
            qml/dashboard/ConsoleBackground.qml
            qml/modals/OptionsModal.qml
            qml/modals/ConfirmModal.qml

        Design:
            - NeutronOS Gemini dark cosmic / liquid glass theme.
            - Controller-first colors.
            - Blue focus.
            - Red armed/destructive.
            - Green running/success.
            - Yellow warning.
            - Purple special/developer.
            - No backend dependency.
            - No shader.
            - No animations.
            - No placeholder behavior.

        Notes:
            This file intentionally exposes both:
                1) Direct properties:
                    theme.background
                    theme.text
                    theme.focus
                    theme.danger
                    theme.radius

                2) Grouped properties:
                    theme.colors.background
                    theme.metrics.radius
                    theme.fonts.title

            That keeps older QML files working while newer files can use
            clearer grouped access.
    */

    /*
        ============================================================
                                COLORS
        ============================================================
    */

    property QtObject colors: QtObject {
        id: colorsGroup

        property color background: root.lightMode ? "#EEF2F7" : "#02040c"
        property color backgroundSoft: root.lightMode ? "#F8FAFC" : "#050816"
        property color backgroundElevated: root.lightMode ? "#FFFFFF" : "#071426"
        property color backgroundPanel: root.lightMode ? "#F8FAFCF2" : "#071426d8"
        property color backgroundPanelStrong: root.lightMode ? "#FFFFFFFA" : "#071426f5"
        property color backgroundModal: root.lightMode ? "#E8EEF6F5" : "#02040cf2"
        property color backgroundDanger: "#26070cdd"
        property color backgroundDisabled: root.lightMode ? "#E2E8F0CC" : "#05080faa"

        property color glass: root.lightMode ? "#FFFFFFE8" : "#071426d8"
        property color glassSoft: root.lightMode ? "#F8FAFCCC" : "#071426aa"
        property color glassStrong: root.lightMode ? "#FFFFFFF5" : "#10172ad9"
        property color glassFocused: root.lightMode ? "#DCEEFFEE" : "#0a1b34e8"
        property color glassArmed: "#26070cdd"
        property color glassOverlay: root.lightMode ? "#E8EEF6F2" : "#02040cf2"

        property color border: root.lightMode ? "#94A3B866" : "#2b5d8f77"
        property color borderSoft: root.lightMode ? "#CBD5E166" : "#223d7d66"
        property color borderStrong: root.lightMode ? "#4DA6FF88" : "#337df966"
        property color borderGlass: root.lightMode ? "#CBD5E1FF" : "#223d7dff"

        property color text: root.lightMode ? "#10233E" : "#ffffff"
        property color textSoft: root.lightMode ? "#294766" : "#cfeaff"
        property color textMuted: root.lightMode ? "#64748B" : "#8aa6c8"
        property color textDim: root.lightMode ? "#7C8EA3" : "#6f86a8"
        property color textDanger: "#ffd1d1"
        property color textWarning: "#ffe7a3"
        property color textSuccess: "#b8ffd8"

        property color accent: "#7df9ff"
        property color accentSoft: "#9fd8ff"
        property color accentDeep: "#1663a7"

        property color focus: "#4da6ff"
        property color focusBright: "#7df9ff"
        property color focusSoft: "#9fd8ff"
        property color focusDeep: root.lightMode ? "#DCEEFF" : "#06162d"

        property color danger: "#ff3040"
        property color dangerSoft: "#ff6b7a"
        property color dangerDeep: "#3a0710"

        property color success: "#22ff88"
        property color successSoft: "#9cffc6"
        property color successDeep: "#073a22"

        property color warning: "#facc15"
        property color warningSoft: "#f5c542"
        property color warningDeep: "#3a2c07"

        property color purple: "#a855f7"
        property color purpleSoft: "#c084fc"
        property color purpleBright: "#d8b4fe"
        property color pink: "#e879f9"
        property color rose: "#f472b6"

        property color online: "#22ff88"
        property color offline: "#ff3040"
        property color running: "#22ff88"
        property color stopped: "#ff3040"
        property color locked: "#ff3040"
        property color secure: "#22ff88"

        property color transparent: "#00000000"
        property color white: "#ffffff"
        property color black: "#000000"
    }

    /*
        ============================================================
                                METRICS
        ============================================================
    */

    property QtObject metrics: QtObject {
        id: metricsGroup

        property int radiusSmall: 14
        property int radiusMedium: 22
        property int radiusLarge: 28
        property int radiusXLarge: 34
        property int radiusPill: 999

        property int spacingTiny: 4
        property int spacingSmall: 8
        property int spacingMedium: 14
        property int spacingLarge: 20
        property int spacingXLarge: 28

        property int paddingSmall: 10
        property int paddingMedium: 16
        property int paddingLarge: 24
        property int paddingXLarge: 30

        property int borderThin: 1
        property int borderMedium: 2
        property int borderThick: 3
        property int borderArmed: 4

        property int iconSmall: 24
        property int iconMedium: 38
        property int iconLarge: 64
        property int iconXLarge: 92

        property int tileSmallWidth: 104
        property int tileSmallHeight: 104

        property int appTileWidth: 260
        property int appTileHeight: 390

        property int posterWidth: 180
        property int posterHeight: 270

        property int toolbarHeight: 82
        property int toolbarCompactHeight: 66

        property int footerHeight: 46
        property int modalWidth: 940
        property int modalHeight: 660

        property real focusScale: 1.035
        property real pressScale: 0.965
        property real selectedScale: 1.06
        property real sideCardScale: 0.82

        property int fastAnimation: 120
        property int normalAnimation: 180
        property int slowAnimation: 360
        property int carouselAnimation: 420
    }

    /*
        ============================================================
                                  FONTS
        ============================================================
    */

    property QtObject fonts: QtObject {
        id: fontsGroup

        property string family: "Inter"
        property string fallbackFamily: "Segoe UI"

        property int tiny: 9
        property int small: 11
        property int body: 13
        property int medium: 15
        property int large: 18
        property int title: 24
        property int titleLarge: 34
        property int hero: 52
        property int brand: 68

        property real letterSpacingSmall: 0.4
        property real letterSpacingMedium: 0.9
        property real letterSpacingLarge: 1.6
        property real letterSpacingBrand: 2.4
    }

    /*
        ============================================================
                            DIRECT COLOR ALIASES
        ============================================================
    */

    property alias background: colorsGroup.background
    property alias backgroundSoft: colorsGroup.backgroundSoft
    property alias backgroundElevated: colorsGroup.backgroundElevated
    property alias backgroundPanel: colorsGroup.backgroundPanel
    property alias backgroundPanelStrong: colorsGroup.backgroundPanelStrong
    property alias backgroundModal: colorsGroup.backgroundModal
    property alias backgroundDanger: colorsGroup.backgroundDanger
    property alias backgroundDisabled: colorsGroup.backgroundDisabled

    property alias glass: colorsGroup.glass
    property alias glassSoft: colorsGroup.glassSoft
    property alias glassStrong: colorsGroup.glassStrong
    property alias glassFocused: colorsGroup.glassFocused
    property alias glassArmed: colorsGroup.glassArmed
    property alias glassOverlay: colorsGroup.glassOverlay

    property alias border: colorsGroup.border
    property alias borderSoft: colorsGroup.borderSoft
    property alias borderStrong: colorsGroup.borderStrong
    property alias borderGlass: colorsGroup.borderGlass

    property alias text: colorsGroup.text
    property alias textSoft: colorsGroup.textSoft
    property alias textMuted: colorsGroup.textMuted
    property alias textDim: colorsGroup.textDim
    property alias textDanger: colorsGroup.textDanger
    property alias textWarning: colorsGroup.textWarning
    property alias textSuccess: colorsGroup.textSuccess

    property alias accent: colorsGroup.accent
    property alias accentSoft: colorsGroup.accentSoft
    property alias accentDeep: colorsGroup.accentDeep

    property alias focus: colorsGroup.focus
    property alias focusBright: colorsGroup.focusBright
    property alias focusSoft: colorsGroup.focusSoft
    property alias focusDeep: colorsGroup.focusDeep

    property alias danger: colorsGroup.danger
    property alias dangerSoft: colorsGroup.dangerSoft
    property alias dangerDeep: colorsGroup.dangerDeep

    property alias success: colorsGroup.success
    property alias successSoft: colorsGroup.successSoft
    property alias successDeep: colorsGroup.successDeep

    property alias warning: colorsGroup.warning
    property alias warningSoft: colorsGroup.warningSoft
    property alias warningDeep: colorsGroup.warningDeep

    property alias purple: colorsGroup.purple
    property alias purpleSoft: colorsGroup.purpleSoft
    property alias purpleBright: colorsGroup.purpleBright
    property alias pink: colorsGroup.pink
    property alias rose: colorsGroup.rose

    property alias online: colorsGroup.online
    property alias offline: colorsGroup.offline
    property alias running: colorsGroup.running
    property alias stopped: colorsGroup.stopped
    property alias locked: colorsGroup.locked
    property alias secure: colorsGroup.secure

    /*
        ============================================================
                            COMMON LEGACY ALIASES
        ============================================================
    */

    property alias bg: colorsGroup.background
    property alias panel: colorsGroup.backgroundPanel
    property alias panelStrong: colorsGroup.backgroundPanelStrong
    property alias card: colorsGroup.glass
    property alias cardFocused: colorsGroup.glassFocused
    property alias cardArmed: colorsGroup.glassArmed
    property alias primary: colorsGroup.accent
    property alias secondary: colorsGroup.purple
    property alias muted: colorsGroup.textMuted
    property alias cyan: colorsGroup.accent
    property alias blue: colorsGroup.focus
    property alias red: colorsGroup.danger
    property alias green: colorsGroup.success
    property alias yellow: colorsGroup.warning
    property alias magenta: colorsGroup.pink

    property alias backgroundColor: colorsGroup.background
    property alias panelColor: colorsGroup.backgroundPanel
    property alias cardColor: colorsGroup.glass
    property alias borderColor: colorsGroup.border
    property alias textColor: colorsGroup.text
    property alias mutedTextColor: colorsGroup.textMuted
    property alias accentColor: colorsGroup.accent
    property alias focusColor: colorsGroup.focus
    property alias dangerColor: colorsGroup.danger
    property alias warningColor: colorsGroup.warning
    property alias successColor: colorsGroup.success
    property alias purpleColor: colorsGroup.purple

    /*
        ============================================================
                            DIRECT METRIC ALIASES
        ============================================================
    */

    property alias radiusSmall: metricsGroup.radiusSmall
    property alias radiusMedium: metricsGroup.radiusMedium
    property alias radiusLarge: metricsGroup.radiusLarge
    property alias radiusXLarge: metricsGroup.radiusXLarge
    property alias radiusPill: metricsGroup.radiusPill

    property alias spacingTiny: metricsGroup.spacingTiny
    property alias spacingSmall: metricsGroup.spacingSmall
    property alias spacingMedium: metricsGroup.spacingMedium
    property alias spacingLarge: metricsGroup.spacingLarge
    property alias spacingXLarge: metricsGroup.spacingXLarge

    property alias paddingSmall: metricsGroup.paddingSmall
    property alias paddingMedium: metricsGroup.paddingMedium
    property alias paddingLarge: metricsGroup.paddingLarge
    property alias paddingXLarge: metricsGroup.paddingXLarge

    property alias borderThin: metricsGroup.borderThin
    property alias borderMedium: metricsGroup.borderMedium
    property alias borderThick: metricsGroup.borderThick
    property alias borderArmed: metricsGroup.borderArmed

    property alias radius: metricsGroup.radiusLarge
    property alias spacing: metricsGroup.spacingMedium
    property alias padding: metricsGroup.paddingMedium

    /*
        ============================================================
                                HELPERS
        ============================================================
    */

    function clamp(value, minValue, maxValue) {
        var n = Number(value)

        if (isNaN(n))
            n = minValue

        return Math.max(minValue, Math.min(maxValue, n))
    }

    function percent(value) {
        return clamp(value, 0, 100)
    }

    function alpha(colorValue, opacityValue) {
        return Qt.rgba(
            colorValue.r,
            colorValue.g,
            colorValue.b,
            clamp(opacityValue, 0, 1)
        )
    }

    function withAlpha(colorValue, opacityValue) {
        return alpha(colorValue, opacityValue)
    }

    function lighter(colorValue, factor) {
        return Qt.lighter(colorValue, factor === undefined ? 1.25 : factor)
    }

    function darker(colorValue, factor) {
        return Qt.darker(colorValue, factor === undefined ? 1.25 : factor)
    }

    function statusColor(status) {
        var s = String(status || "").trim().toLowerCase()

        if (s === "running" ||
                s === "online" ||
                s === "active" ||
                s === "connected" ||
                s === "secure" ||
                s === "ready" ||
                s === "success" ||
                s === "healthy") {
            return colorsGroup.success
        }

        if (s === "warning" ||
                s === "busy" ||
                s === "pending" ||
                s === "charging" ||
                s === "limited") {
            return colorsGroup.warning
        }

        if (s === "stopped" ||
                s === "offline" ||
                s === "error" ||
                s === "failed" ||
                s === "locked" ||
                s === "danger" ||
                s === "critical") {
            return colorsGroup.danger
        }

        if (s === "developer" ||
                s === "special" ||
                s === "profile") {
            return colorsGroup.purple
        }

        return colorsGroup.accent
    }

    function statusText(status) {
        var s = String(status || "").trim()

        if (s.length <= 0)
            return "--"

        return s
    }

    function usageColor(value) {
        var p = percent(value)

        if (p >= 90)
            return colorsGroup.danger

        if (p >= 75)
            return colorsGroup.warning

        return colorsGroup.success
    }

    function tempColor(valueF) {
        var t = Number(valueF)

        if (isNaN(t) || t <= 0)
            return colorsGroup.purple

        if (t >= 185)
            return colorsGroup.danger

        if (t >= 165)
            return colorsGroup.rose

        if (t >= 145)
            return colorsGroup.warning

        return colorsGroup.success
    }

    function boolColor(value) {
        return value ? colorsGroup.success : colorsGroup.danger
    }

    function focusBorder(focused, armed) {
        if (armed)
            return colorsGroup.danger

        if (focused)
            return colorsGroup.focus

        return colorsGroup.border
    }

    function cardBackground(focused, armed, disabled) {
        if (disabled)
            return colorsGroup.backgroundDisabled

        if (armed)
            return colorsGroup.glassArmed

        if (focused)
            return colorsGroup.glassFocused

        return colorsGroup.glass
    }

    function cleanText(value, fallbackValue) {
        if (value === undefined || value === null)
            return fallbackValue === undefined ? "" : fallbackValue

        var text = String(value).trim()

        if (text === "undefined" || text === "null" || text.length <= 0)
            return fallbackValue === undefined ? "" : fallbackValue

        return text
    }

    function appVersionText(version) {
        var clean = cleanText(version, "")

        if (clean.length <= 0)
            return ""

        if (clean.charAt(0).toLowerCase() === "v")
            return clean

        return "V" + clean
    }

    function assetPath(path) {
        var clean = cleanText(path, "")

        if (clean.length <= 0)
            return ""

        if (clean.indexOf("file:") === 0 ||
                clean.indexOf("qrc:") === 0 ||
                clean.indexOf("http://") === 0 ||
                clean.indexOf("https://") === 0 ||
                clean.indexOf("image://") === 0) {
            return clean
        }

        return "../themes/Default/" + clean
    }

    function iconPath(name) {
        var clean = cleanText(name, "")

        if (clean.length <= 0)
            return ""

        if (clean.indexOf("/") >= 0)
            return assetPath(clean)

        return assetPath("apps/icons/" + clean + ".png")
    }

    function posterPath(name) {
        var clean = cleanText(name, "")

        if (clean.length <= 0)
            return ""

        if (clean.indexOf("/") >= 0)
            return assetPath(clean)

        return assetPath("apps/posters/" + clean + ".png")
    }

    function userIconPath(name) {
        var clean = cleanText(name, "user_icon.png")

        if (clean.indexOf("/") >= 0)
            return assetPath(clean)

        return assetPath("users/" + clean)
    }

    function isDangerAction(name) {
        var text = String(name || "").toLowerCase()

        return text.indexOf("shutdown") >= 0 ||
               text.indexOf("poweroff") >= 0 ||
               text.indexOf("reboot") >= 0 ||
               text.indexOf("restart") >= 0 ||
               text.indexOf("stop") >= 0 ||
               text.indexOf("kill") >= 0 ||
               text.indexOf("delete") >= 0 ||
               text.indexOf("remove") >= 0 ||
               text.indexOf("uninstall") >= 0
    }
}