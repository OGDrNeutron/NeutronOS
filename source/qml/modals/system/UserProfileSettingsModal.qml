import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

Item {
    id: root

    // NEUTRONOS_USER_FULL_CONTROL_CENTER_V2

    anchors.fill: parent
    visible: true
    enabled: visible
    focus: visible
    opacity: 1.0
    z: 30000


    /* Shared Controller Control Center visual language. */
    property color chromeColor: "#030810"
    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color panelInset: "#06101F"
    property color focusBlue: "#4DA6FF"
    property color neutronCyan: "#7DF9FF"
    property color dangerRed: "#FF3040"
    property color successGreen: "#22FF88"
    property color textWhite: "#F4FBFF"
    property color mutedText: "#8AA6C8"

    signal closed()
    signal actionRequested(string action, var payload)

    property var contextData: ({})
    property var modalContext: ({})
    property var activeUser: null
    property bool profileOnly: false

    property int focusZone: 0          // 0 category rail, 1 settings, 2 footer
    property int selectedCategory: 0
    property int selectedRow: 0
    property int selectedFooter: 0
    property int armedAccountRow: -1

    property string draftDisplayName: ""
    property string draftTagline: "LOCAL SYSTEM PROFILE"
    property string draftAvatarId: ""
    property string draftAvatarSource: "users/user_icon.png"
    property string draftNameTint: "#FFFFFF"
    property string draftAccentColor: "#7DF9FF"
    property string draftFrameStyle: "circle"
    property int draftGlowStrength: 60

    property real nameHue: 0
    property real nameSaturation: 0
    property real nameLightness: 100
    property real accentHue: 181
    property real accentSaturation: 100
    property real accentLightness: 75

    property var avatarModel: []
    property int selectedAvatar: 0
    property string statusText: "PROFILE SETTINGS ARE PERSISTENT"
    property bool statusError: false

    property bool keyboardOpen: false
    property string keyboardField: ""
    property string keyboardBuffer: ""

    readonly property var categories: profileOnly ? [
        { "id": "profile", "title": "PROFILE", "subtitle": "Name and personal message", "iconKind": "profile" },
        { "id": "icon", "title": "ICON", "subtitle": "Avatar library and frame", "iconKind": "avatar" },
        { "id": "nameColor", "title": "NAME COLOR", "subtitle": "Preset and full HSL tint", "iconKind": "palette" },
        { "id": "appearance", "title": "APPEARANCE", "subtitle": "Accent, glow and styling", "iconKind": "appearance" },
        { "id": "console", "title": "CONSOLE", "subtitle": "System cards, launcher and screensaver", "iconKind": "console" }
    ] : [
        { "id": "profile", "title": "PROFILE", "subtitle": "Name and personal message", "iconKind": "profile" },
        { "id": "icon", "title": "ICON", "subtitle": "Avatar library and frame", "iconKind": "avatar" },
        { "id": "nameColor", "title": "NAME COLOR", "subtitle": "Preset and full HSL tint", "iconKind": "palette" },
        { "id": "appearance", "title": "APPEARANCE", "subtitle": "Accent, glow and styling", "iconKind": "appearance" },
        { "id": "console", "title": "CONSOLE", "subtitle": "System cards, launcher and screensaver", "iconKind": "console" },
        { "id": "account", "title": "ACCOUNT", "subtitle": "Lock, restart, reboot and power", "iconKind": "power" }
    ]

    readonly property var colorPresets: [
        { "name": "WHITE", "value": "#FFFFFF" },
        { "name": "ICE", "value": "#DCEEFF" },
        { "name": "CYAN", "value": "#7DF9FF" },
        { "name": "SKY", "value": "#47C8FF" },
        { "name": "BLUE", "value": "#4DA6FF" },
        { "name": "ROYAL", "value": "#3B82F6" },
        { "name": "INDIGO", "value": "#6366F1" },
        { "name": "VIOLET", "value": "#8B5CF6" },
        { "name": "PURPLE", "value": "#C084FC" },
        { "name": "MAGENTA", "value": "#E879F9" },
        { "name": "ROSE", "value": "#F472B6" },
        { "name": "PINK", "value": "#FF4EA8" },
        { "name": "CORAL", "value": "#FB7185" },
        { "name": "RED", "value": "#FF3040" },
        { "name": "ORANGE", "value": "#F97316" },
        { "name": "AMBER", "value": "#F59E0B" },
        { "name": "GOLD", "value": "#F5C542" },
        { "name": "LIME", "value": "#D9F542" },
        { "name": "LEAF", "value": "#A3E635" },
        { "name": "GREEN", "value": "#22FF88" },
        { "name": "EMERALD", "value": "#10B981" },
        { "name": "TEAL", "value": "#14B8A6" },
        { "name": "MINT", "value": "#2DD4BF" },
        { "name": "AQUA", "value": "#67E8F9" },
        { "name": "SLATE", "value": "#94A3B8" },
        { "name": "STEEL", "value": "#64748B" },
        { "name": "SILVER", "value": "#CBD5E1" },
        { "name": "CREAM", "value": "#FDE68A" },
        { "name": "SALMON", "value": "#FCA5A5" },
        { "name": "LAVENDER", "value": "#C4B5FD" }
    ]

    readonly property var frameStyles: ["circle", "rounded", "square"]

    function userBackend() {
        try {
            return (typeof userManager !== "undefined" && userManager) ? userManager : null
        } catch (error) {
            return null
        }
    }

    function appearanceBackend() {
        return userBackend()
    }

    function assetBackend() {
        try {
            return (typeof assetManager !== "undefined" && assetManager) ? assetManager : null
        } catch (error) {
            return null
        }
    }

    function clean(value, fallbackValue) {
        if (value === undefined || value === null)
            return fallbackValue
        var text = String(value).trim()
        return text.length > 0 && text !== "undefined" && text !== "null" ? text : fallbackValue
    }

    function valueFrom(object, keys, fallbackValue) {
        if (!object)
            return fallbackValue
        for (var i = 0; i < keys.length; ++i) {
            try {
                var value = object[keys[i]]
                if (value !== undefined && value !== null && String(value).length > 0)
                    return value
            } catch (error) {}
        }
        return fallbackValue
    }

    function activeUserMap() {
        var backend = userBackend()
        try {
            if (backend && backend.activeUser)
                return backend.activeUser
        } catch (error) {}
        if (activeUser)
            return activeUser
        if (contextData && contextData.user)
            return contextData.user
        return ({})
    }

    function username() {
        return clean(valueFrom(activeUserMap(), ["username", "accountName", "id"], "neutronos"), "neutronos")
    }

    function resolveAvatar(source) {
        var value = clean(source, "users/user_icon.png")
        var lower = value.toLowerCase()
        if (lower.indexOf("file:") === 0 || lower.indexOf("qrc:") === 0 ||
                lower.indexOf("http://") === 0 || lower.indexOf("https://") === 0 ||
                lower.indexOf("image://") === 0) {
            return value
        }
        var backend = assetBackend()
        try {
            if (backend && typeof backend.themeFile === "function")
                return backend.themeFile(value)
        } catch (error) {}
        return value
    }

    function avatarId(entry) {
        if (typeof entry === "string")
            return entry
        return clean(valueFrom(entry, ["id", "avatarId", "name", "source"], ""), "")
    }

    function avatarSource(entry) {
        if (typeof entry === "string")
            return entry
        return clean(valueFrom(entry, ["source", "icon", "path", "avatar"], ""), "")
    }

    function avatarLabel(entry) {
        var label = typeof entry === "string"
                    ? entry
                    : clean(valueFrom(entry, ["displayName", "label", "name", "id"], "Avatar"), "Avatar")
        var slash = label.lastIndexOf("/")
        if (slash >= 0)
            label = label.substring(slash + 1)
        var dot = label.lastIndexOf(".")
        if (dot > 0)
            label = label.substring(0, dot)
        return label.toUpperCase()
    }

    function loadAvatars() {
        var raw = []
        var backend = userBackend()
        try {
            if (backend)
                raw = backend.availableAvatars || backend.avatarOptions || []
        } catch (error) {}

        var list = []
        var seen = ({})
        for (var i = 0; raw && i < raw.length; ++i) {
            var id = avatarId(raw[i])
            var source = avatarSource(raw[i])
            var key = id.length > 0 ? id : source
            if (key.length <= 0 || seen[key])
                continue
            seen[key] = true
            list.push(raw[i])
        }

        if (list.length <= 0)
            list.push({ "id": "default", "source": "users/user_icon.png", "displayName": "Default" })

        avatarModel = list
        selectedAvatar = 0
        for (var j = 0; j < list.length; ++j) {
            if (avatarId(list[j]) === draftAvatarId || avatarSource(list[j]) === draftAvatarSource) {
                selectedAvatar = j
                break
            }
        }
        chooseAvatar(selectedAvatar)
    }

    function chooseAvatar(index) {
        if (!avatarModel || avatarModel.length <= 0)
            return
        selectedAvatar = (index + avatarModel.length) % avatarModel.length
        draftAvatarId = avatarId(avatarModel[selectedAvatar])
        draftAvatarSource = avatarSource(avatarModel[selectedAvatar])
        if (draftAvatarSource.length <= 0)
            draftAvatarSource = draftAvatarId
        settingsList.positionViewAtIndex(selectedRow, ListView.Contain)
    }

    function hexPart(value) {
        var text = Math.max(0, Math.min(255, Math.round(value))).toString(16).toUpperCase()
        return text.length < 2 ? "0" + text : text
    }

    function hslToHex(hue, saturation, lightness) {
        var h = ((Number(hue) % 360) + 360) % 360 / 360
        var s = Math.max(0, Math.min(100, Number(saturation))) / 100
        var l = Math.max(0, Math.min(100, Number(lightness))) / 100
        var r, g, b

        if (s === 0) {
            r = g = b = l
        } else {
            var hueToRgb = function(p, q, t) {
                if (t < 0) t += 1
                if (t > 1) t -= 1
                if (t < 1 / 6) return p + (q - p) * 6 * t
                if (t < 1 / 2) return q
                if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
                return p
            }
            var q = l < 0.5 ? l * (1 + s) : l + s - l * s
            var p = 2 * l - q
            r = hueToRgb(p, q, h + 1 / 3)
            g = hueToRgb(p, q, h)
            b = hueToRgb(p, q, h - 1 / 3)
        }
        return "#" + hexPart(r * 255) + hexPart(g * 255) + hexPart(b * 255)
    }

    function hexToHsl(hex) {
        var text = String(hex || "#FFFFFF").replace("#", "")
        if (text.length !== 6)
            text = "FFFFFF"
        var r = parseInt(text.substring(0, 2), 16) / 255
        var g = parseInt(text.substring(2, 4), 16) / 255
        var b = parseInt(text.substring(4, 6), 16) / 255
        var max = Math.max(r, g, b)
        var min = Math.min(r, g, b)
        var h = 0
        var s = 0
        var l = (max + min) / 2
        var d = max - min
        if (d !== 0) {
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
            if (max === r)
                h = ((g - b) / d + (g < b ? 6 : 0)) / 6
            else if (max === g)
                h = ((b - r) / d + 2) / 6
            else
                h = ((r - g) / d + 4) / 6
        }
        return { "h": Math.round(h * 360), "s": Math.round(s * 100), "l": Math.round(l * 100) }
    }

    function syncHslFromColors() {
        var name = hexToHsl(draftNameTint)
        nameHue = name.h
        nameSaturation = name.s
        nameLightness = name.l
        var accent = hexToHsl(draftAccentColor)
        accentHue = accent.h
        accentSaturation = accent.s
        accentLightness = accent.l
    }

    function loadDraft() {
        var user = activeUserMap()
        var backend = userBackend()

        try {
            if (backend && typeof backend.refreshProfile === "function")
                backend.refreshProfile()
        } catch (refreshError) {}

        draftDisplayName = clean(valueFrom(user, ["displayName", "name", "username"], "User"), "User")
        draftTagline = clean(valueFrom(user, ["profileTagline", "tagline", "statusMessage"], "LOCAL SYSTEM PROFILE"), "LOCAL SYSTEM PROFILE")
        draftNameTint = clean(valueFrom(user, ["nameTint", "displayNameTint"], "#FFFFFF"), "#FFFFFF").toUpperCase()
        draftAccentColor = clean(valueFrom(user, ["accentColor", "profileAccent"], "#7DF9FF"), "#7DF9FF").toUpperCase()
        draftFrameStyle = clean(valueFrom(user, ["avatarFrame", "frameStyle"], "circle"), "circle").toLowerCase()
        draftGlowStrength = Number(valueFrom(user, ["glowStrength"], 0.65))
        if (isNaN(draftGlowStrength))
            draftGlowStrength = 65
        else if (draftGlowStrength <= 1.0)
            draftGlowStrength = Math.round(draftGlowStrength * 100)
        draftGlowStrength = Math.max(0, Math.min(100, Math.round(draftGlowStrength)))
        draftAvatarId = clean(valueFrom(user, ["avatarId"], ""), "")
        draftAvatarSource = clean(valueFrom(user, ["avatarSource", "resolvedAvatarSource", "icon", "avatar"], "users/user_icon.png"), "users/user_icon.png")

        try {
            if (backend) {
                draftTagline = clean(backend.profileTagline, draftTagline)
                draftNameTint = clean(backend.nameTint, draftNameTint).toUpperCase()
                draftAccentColor = clean(backend.accentColor, draftAccentColor).toUpperCase()
                draftFrameStyle = clean(backend.avatarFrame, draftFrameStyle).toLowerCase()
                var backendGlow = Number(backend.glowStrength)
                if (!isNaN(backendGlow))
                    draftGlowStrength = Math.max(0, Math.min(100, Math.round(backendGlow <= 1.0 ? backendGlow * 100 : backendGlow)))
            }
        } catch (backendError) {}

        syncHslFromColors()
        loadAvatars()
    }

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        focusZone = 0
        selectedCategory = 0
        selectedRow = 0
        selectedFooter = 0
        armedAccountRow = -1
        statusText = "PROFILE SETTINGS ARE PERSISTENT"
        statusError = false
        visible = true
        loadDraft()
        var requested = ""
        try { requested = String(contextData.focusSection || "").trim() } catch (error) { requested = "" }
        if (requested === "icon") selectedCategory = 1
        else if (requested === "profile") selectedCategory = 0
        if (requested.length > 0) focusZone = 1
        selectedRow = 0
        clampRow()
        forceActiveFocus()
    }

    function openModal(context) { open(context) }

    function close() {
        if (!visible)
            return
        keyboardOpen = false
        profileKeyboard.visibleMode = false
        visible = false
        closed()
    }

    function closeModal() { close() }

    function categoryId() { return categories[selectedCategory].id }

    function rowModel() {
        var id = categoryId()
        if (id === "profile") {
            return [
                { "key": "displayName", "title": "DISPLAY NAME", "subtitle": "Shown on Login and throughout the Console", "value": draftDisplayName },
                { "key": "tagline", "title": "PROFILE TAGLINE", "subtitle": "Short message shown beneath your name", "value": draftTagline },
                { "key": "save", "title": "APPLY PROFILE", "subtitle": "Save all profile and appearance changes", "value": "SAVE NOW", "accent": "#22FF88" }
            ]
        }
        if (id === "icon") {
            return [
                { "key": "avatar", "title": "PROFILE ICON", "subtitle": "LEFT / RIGHT cycles the discovered icon library", "value": avatarModel.length > 0 ? avatarLabel(avatarModel[selectedAvatar]) : "DEFAULT" },
                { "key": "refreshAvatars", "title": "REFRESH ICON LIBRARY", "subtitle": "Scan themes/Default/users for new images", "value": avatarModel.length + " FOUND" },
                { "key": "frame", "title": "ICON FRAME", "subtitle": "Circle, rounded or square", "value": draftFrameStyle.toUpperCase() }
            ]
        }
        if (id === "nameColor") {
            return [
                { "key": "namePreset", "title": "COLOR PRESET", "subtitle": "Thirty curated profile-name colors", "value": presetName(draftNameTint), "color": draftNameTint },
                { "key": "nameHue", "title": "HUE", "subtitle": "Full 0–359 degree color range", "value": Math.round(nameHue) + "°", "color": draftNameTint },
                { "key": "nameSaturation", "title": "SATURATION", "subtitle": "Color strength", "value": Math.round(nameSaturation) + "%", "color": draftNameTint },
                { "key": "nameLightness", "title": "LIGHTNESS", "subtitle": "Brightness of the name tint", "value": Math.round(nameLightness) + "%", "color": draftNameTint }
            ]
        }
        if (id === "appearance") {
            return [
                { "key": "accentPreset", "title": "PROFILE ACCENT", "subtitle": "Frame, focus and Login highlight color", "value": presetName(draftAccentColor), "color": draftAccentColor },
                { "key": "accentHue", "title": "ACCENT HUE", "subtitle": "Full 0–359 degree accent range", "value": Math.round(accentHue) + "°", "color": draftAccentColor },
                { "key": "accentSaturation", "title": "ACCENT SATURATION", "subtitle": "Accent color strength", "value": Math.round(accentSaturation) + "%", "color": draftAccentColor },
                { "key": "accentLightness", "title": "ACCENT LIGHTNESS", "subtitle": "Accent brightness", "value": Math.round(accentLightness) + "%", "color": draftAccentColor },
                { "key": "glow", "title": "ICON GLOW", "subtitle": "Persistent glow strength from 0–100%", "value": draftGlowStrength + "%", "color": draftAccentColor }
            ]
        }
        if (id === "console") {
            return [
                { "key": "personalization", "title": "PERSONALIZE CONSOLE", "subtitle": "Rearrange or hide System Overview cards, choose launcher mode and configure screensavers", "value": "OPEN", "accent": "#7DF9FF" },
                { "key": "overviewHint", "title": "PER-USER LAYOUT", "subtitle": "Changes are saved separately for " + username(), "value": "PERSISTENT" }
            ]
        }
        return [
            { "key": "lock", "title": "LOCK CONSOLE", "subtitle": "Return to Login without ending the local account", "value": "LOCK", "accent": "#7DF9FF", "iconKind": "lock" },
            { "key": "restart", "title": "RESTART NEUTRONOS", "subtitle": "Restart neutronos.service without rebooting Linux", "value": "RESTART", "accent": "#0047AB", "iconKind": "restart" },
            { "key": "reboot", "title": "REBOOT SYSTEM", "subtitle": "Press X twice to reboot the NeutronOS device", "value": armedAccountRow === 2 ? "ARMED" : "REBOOT", "accent": "#F5C542", "iconKind": "reboot" },
            { "key": "logout", "title": "LOG OUT", "subtitle": "Press X twice to end the current NeutronOS session", "value": armedAccountRow === 3 ? "ARMED" : "LOGOUT", "accent": "#FF5870", "iconKind": "logout" },
            { "key": "poweroff", "title": "POWER OFF", "subtitle": "Press X twice to shut the NeutronOS device down", "value": armedAccountRow === 4 ? "ARMED" : "POWER OFF", "accent": "#FF3040", "iconKind": "power" },
            { "key": "reload", "title": "RELOAD SAVED PROFILE", "subtitle": "Discard draft changes and reload persistent values", "value": "RELOAD" },
            { "key": "reset", "title": "RESET APPEARANCE", "subtitle": "Restore NeutronOS profile defaults", "value": "RESET", "accent": "#F5C542" }
        ]
    }

    function rowCount() { return rowModel().length }

    function clampRow() {
        selectedRow = Math.max(0, Math.min(rowCount() - 1, selectedRow))
        Qt.callLater(function() { settingsList.positionViewAtIndex(selectedRow, ListView.Contain) })
    }

    function changeCategory(delta) {
        selectedCategory = (selectedCategory + delta + categories.length) % categories.length
        selectedRow = 0
        armedAccountRow = -1
        settingsList.positionViewAtBeginning()
    }

    function presetIndex(color) {
        var target = String(color || "").toUpperCase()
        for (var i = 0; i < colorPresets.length; ++i) {
            if (colorPresets[i].value === target)
                return i
        }
        return 0
    }

    function presetName(color) {
        var index = presetIndex(color)
        return colorPresets[index].name + "  " + String(color).toUpperCase()
    }

    function cyclePreset(target, delta) {
        var current = target === "name" ? draftNameTint : draftAccentColor
        var next = (presetIndex(current) + delta + colorPresets.length) % colorPresets.length
        if (target === "name")
            draftNameTint = colorPresets[next].value
        else
            draftAccentColor = colorPresets[next].value
        syncHslFromColors()
    }

    function cycleFrame(delta) {
        var index = frameStyles.indexOf(draftFrameStyle)
        if (index < 0) index = 0
        draftFrameStyle = frameStyles[(index + delta + frameStyles.length) % frameStyles.length]
    }

    function adjustRow(delta) {
        var rows = rowModel()
        if (selectedRow < 0 || selectedRow >= rows.length)
            return false
        var key = rows[selectedRow].key
        if (key === "avatar") chooseAvatar(selectedAvatar + delta)
        else if (key === "frame") cycleFrame(delta)
        else if (key === "namePreset") cyclePreset("name", delta)
        else if (key === "accentPreset") cyclePreset("accent", delta)
        else if (key === "nameHue") { nameHue = (nameHue + delta * 5 + 360) % 360; draftNameTint = hslToHex(nameHue, nameSaturation, nameLightness) }
        else if (key === "nameSaturation") { nameSaturation = Math.max(0, Math.min(100, nameSaturation + delta * 5)); draftNameTint = hslToHex(nameHue, nameSaturation, nameLightness) }
        else if (key === "nameLightness") { nameLightness = Math.max(10, Math.min(100, nameLightness + delta * 5)); draftNameTint = hslToHex(nameHue, nameSaturation, nameLightness) }
        else if (key === "accentHue") { accentHue = (accentHue + delta * 5 + 360) % 360; draftAccentColor = hslToHex(accentHue, accentSaturation, accentLightness) }
        else if (key === "accentSaturation") { accentSaturation = Math.max(0, Math.min(100, accentSaturation + delta * 5)); draftAccentColor = hslToHex(accentHue, accentSaturation, accentLightness) }
        else if (key === "accentLightness") { accentLightness = Math.max(10, Math.min(100, accentLightness + delta * 5)); draftAccentColor = hslToHex(accentHue, accentSaturation, accentLightness) }
        else if (key === "glow") draftGlowStrength = Math.max(0, Math.min(100, draftGlowStrength + delta * 5))
        else return false
        return true
    }

    function beginKeyboard(field, value) {
        keyboardField = field
        keyboardBuffer = String(value || "")
        keyboardOpen = true
        profileKeyboard.resetOnOpen = true
        profileKeyboard.openKeyboard("large")
    }

    function finishKeyboard(accepted) {
        if (accepted) {
            var text = keyboardBuffer.trim()
            if (keyboardField === "displayName") {
                if (text.length < 1) {
                    statusText = "DISPLAY NAME CANNOT BE EMPTY"
                    statusError = true
                    return
                }
                draftDisplayName = text.substring(0, 48)
            } else {
                draftTagline = text.length > 0 ? text.substring(0, 80) : "LOCAL SYSTEM PROFILE"
            }
        }
        keyboardOpen = false
        profileKeyboard.visibleMode = false
        forceActiveFocus()
    }

    function applyAll() {
        var ok = false
        var users = userBackend()
        try {
            if (users && typeof users.applyProfile === "function") {
                ok = users.applyProfile({
                    "username": username(),
                    "displayName": draftDisplayName,
                    "profileTagline": draftTagline,
                    "tagline": draftTagline,
                    "nameTint": draftNameTint,
                    "accentColor": draftAccentColor,
                    "avatarFrame": draftFrameStyle,
                    "frameStyle": draftFrameStyle,
                    "glowStrength": Math.max(0, Math.min(1, Number(draftGlowStrength) / 100)),
                    "avatarId": draftAvatarId,
                    "avatar": draftAvatarSource,
                    "icon": draftAvatarSource,
                    "avatarSource": draftAvatarSource
                }) === true
            }
        } catch (error) {
            ok = false
        }

        statusError = !ok
        statusText = ok
                     ? "PROFILE SAVED AND APPLIED IMMEDIATELY"
                     : "PROFILE SETTINGS COULD NOT BE SAVED"
        return ok
    }

    function activateRow() {
        var rows = rowModel()
        var key = rows[selectedRow].key
        var destructive = key === "reboot" || key === "logout" || key === "poweroff"
        armedAccountRow = destructive ? armedAccountRow : -1
        if (key === "displayName") beginKeyboard("displayName", draftDisplayName)
        else if (key === "tagline") beginKeyboard("tagline", draftTagline)
        else if (key === "save") applyAll()
        else if (key === "avatar") chooseAvatar(selectedAvatar + 1)
        else if (key === "refreshAvatars") {
            var backend = userBackend()
            try { if (backend && typeof backend.refreshAvatars === "function") backend.refreshAvatars() } catch (error) {}
            loadAvatars()
            statusText = "ICON LIBRARY REFRESHED"
            statusError = false
        }
        else if (key === "frame") cycleFrame(1)
        else if (key.indexOf("Preset") >= 0) adjustRow(1)
        else if (key.indexOf("Hue") >= 0 || key.indexOf("Saturation") >= 0 || key.indexOf("Lightness") >= 0 || key === "glow") adjustRow(1)
        else if (key === "personalization") {
            actionRequested("personalization", { "username": username(), "tab": 0 })
        }
        else if (key === "overviewHint") {
            actionRequested("personalization", { "username": username(), "tab": 0 })
        }
        else if (key === "lock") {
            actionRequested("lock", { "username": username() })
        }
        else if (key === "restart") {
            actionRequested("restart", { "username": username() })
        }
        else if (key === "reboot" || key === "logout" || key === "poweroff") {
            if (armedAccountRow !== selectedRow) {
                armedAccountRow = selectedRow
                statusText = key.toUpperCase() + " ARMED — PRESS X AGAIN"
                statusError = true
            } else {
                actionRequested(key, { "username": username() })
            }
        }
        else if (key === "reload") {
            loadDraft()
            statusText = "SAVED PROFILE RELOADED"
            statusError = false
        }
        else if (key === "reset") {
            draftTagline = "LOCAL SYSTEM PROFILE"
            draftNameTint = "#FFFFFF"
            draftAccentColor = "#7DF9FF"
            draftFrameStyle = "circle"
            draftGlowStrength = 60
            syncHslFromColors()
            statusText = "DEFAULT APPEARANCE LOADED — SAVE TO APPLY"
            statusError = false
        }
        return true
    }

    function handleControllerPressed(action) {
        if (!visible)
            return false
        if (keyboardOpen)
            return profileKeyboard.handleController(action)

        var a = String(action || "").toLowerCase()
        if (a === "l1") { changeCategory(-1); return true }
        if (a === "r1") { changeCategory(1); return true }
        if (a === "cancel" || a === "o" || a === "back") {
            if (focusZone !== 0) { focusZone = 0; return true }
            close(); return true
        }

        if (focusZone === 0) {
            if (a === "up") changeCategory(-1)
            else if (a === "down") changeCategory(1)
            else if (a === "right" || a === "primary" || a === "x") { focusZone = 1; selectedRow = 0; clampRow() }
            else if (a === "left") focusZone = 2
            return true
        }

        if (focusZone === 1) {
            if (a === "up") { if (selectedRow <= 0) focusZone = 0; else { selectedRow--; clampRow() } }
            else if (a === "down") { if (selectedRow >= rowCount() - 1) focusZone = 2; else { selectedRow++; clampRow() } }
            else if (a === "left") adjustRow(-1)
            else if (a === "right") adjustRow(1)
            else if (a === "primary" || a === "x" || a === "confirm") activateRow()
            return true
        }

        if (focusZone === 2) {
            if (a === "left") selectedFooter = (selectedFooter + 2) % 3
            else if (a === "right") selectedFooter = (selectedFooter + 1) % 3
            else if (a === "up") { focusZone = 1; selectedRow = rowCount() - 1; clampRow() }
            else if (a === "primary" || a === "x") {
                if (selectedFooter === 0) { if (applyAll()) close() }
                else if (selectedFooter === 1) loadDraft()
                else close()
            }
            return true
        }
        return true
    }

    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return visible }

    Keys.onPressed: function(event) {
        if (event.isAutoRepeat)
            return
        var action = ""
        if (event.key === Qt.Key_Up || event.key === Qt.Key_W) action = "up"
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) action = "down"
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_A) action = "left"
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) action = "right"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) action = "cancel"
        else if (event.key === Qt.Key_Q) action = "l1"
        else if (event.key === Qt.Key_E) action = "r1"
        if (action.length > 0) {
            handleControllerPressed(action)
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#D4020710"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 76, 1600)
        height: Math.min(parent.height - 54, 990)
        radius: 34
        color: root.panelColor
        border.width: 2
        border.color: "#486B94"
        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 32
            color: "transparent"
            border.width: 1
            border.color: "#16385A"
        }

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 142
            color: root.chromeColor

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 34
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18

                Rectangle {
                    width: 68
                    height: 68
                    radius: 21
                    color: "#102A48"
                    border.width: 2
                    border.color: root.draftAccentColor

                    Text {
                        anchors.centerIn: parent
                        text: "U"
                        color: root.textWhite
                        font.pixelSize: 27
                        font.bold: true
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Text {
                        text: "USER PROFILE CONTROL CENTER"
                        color: root.textWhite
                        font.pixelSize: 28
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Text {
                        text: "IDENTITY  •  ICON  •  COLOR  •  ACCOUNT"
                        color: root.draftAccentColor
                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 0.9
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                width: 650
                height: 94
                radius: 22
                color: "#071222"
                border.width: 1
                border.color: root.draftAccentColor

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66
                    height: 66
                    radius: root.draftFrameStyle === "square" ? 12 : (root.draftFrameStyle === "rounded" ? 21 : 33)
                    color: "#0B2038"
                    border.width: 2
                    border.color: root.draftAccentColor
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: root.draftAccentColor
                        opacity: 0.05 + root.draftGlowStrength / 100 * 0.13
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 5
                        source: root.resolveAvatar(root.draftAvatarSource)
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.draftAvatarSource.length <= 0
                        text: root.draftDisplayName.length > 0 ? root.draftDisplayName.charAt(0).toUpperCase() : "U"
                        color: root.draftNameTint
                        font.pixelSize: 25
                        font.bold: true
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 104
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        width: parent.width
                        text: root.draftDisplayName
                        color: root.draftNameTint
                        font.pixelSize: 25
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.draftTagline
                        color: root.draftAccentColor
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.username().toUpperCase() + "  •  LOCAL PROFILE"
                        color: root.mutedText
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        Rectangle {
            id: rail
            anchors.left: parent.left
            anchors.top: header.bottom
            anchors.bottom: footer.top
            width: 310
            color: root.chromeColor

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Repeater {
                    model: root.categories

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: parent.width
                        height: 102
                        radius: 20
                        color: root.selectedCategory === index ? "#17365D" : "#09182B"
                        border.width: root.focusZone === 0 && root.selectedCategory === index ? 2 : 1
                        border.color: root.selectedCategory === index
                                      ? (root.focusZone === 0 ? root.focusBlue : root.draftAccentColor)
                                      : "#17304D"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 13
                            anchors.verticalCenter: parent.verticalCenter
                            width: 42
                            height: 42
                            radius: 14
                            color: root.selectedCategory === index ? root.focusBlue : "#10263E"
                            border.width: 1
                            border.color: root.selectedCategory === index ? root.draftAccentColor : "#315A80"

                            ControlCenterIcon {
                                anchors.centerIn: parent
                                width: 27
                                height: 27
                                kind: modelData.iconKind
                                accent: root.selectedCategory === index ? "#04111F" : root.draftAccentColor
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 68
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                width: parent.width
                                text: modelData.title
                                color: root.textWhite
                                font.pixelSize: 18
                                font.bold: true
                                font.letterSpacing: 1.1
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.subtitle
                                color: root.selectedCategory === index ? "#CBEFFF" : root.mutedText
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.7
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: "#214464"
            }
        }

        Rectangle {
            id: contentPanel
            anchors.left: rail.right
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top
            color: root.panelInset

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14

                Text {
                    width: parent.width
                    text: root.categories[root.selectedCategory].title
                    color: root.textWhite
                    font.pixelSize: 31
                    font.bold: true
                    font.letterSpacing: 1.1
                }

                Text {
                    width: parent.width
                    text: root.categories[root.selectedCategory].subtitle + ". Changes remain persistent after reboot."
                    color: root.mutedText
                    font.pixelSize: 16
                    elide: Text.ElideRight
                }

                ListView {
                    id: settingsList
                    width: parent.width
                    height: parent.height - 84
                    clip: true
                    spacing: 12
                    model: root.rowModel()
                    currentIndex: root.selectedRow
                    interactive: false
                    rightMargin: 18
                    cacheBuffer: 360

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOn
                        width: 9
                        contentItem: Rectangle { radius: 5; color: root.draftAccentColor }
                        background: Rectangle { radius: 5; color: "#142A3D" }
                    }

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: settingsList.width - 18
                        height: 100
                        radius: 20
                        color: root.focusZone === 1 && root.selectedRow === index
                               ? ((modelData.key === "logout" || modelData.key === "reboot" || modelData.key === "poweroff") && root.armedAccountRow === index ? "#49111A" : "#17365D")
                               : root.panelRaised
                        border.width: root.focusZone === 1 && root.selectedRow === index ? 2 : 1
                        border.color: root.focusZone === 1 && root.selectedRow === index
                                      ? ((modelData.key === "logout" || modelData.key === "poweroff") ? root.dangerRed : (modelData.key === "reboot" ? "#F5C542" : root.focusBlue))
                                      : (modelData.accent || modelData.color || "#284B6E")

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: parent.height - 28
                            radius: 4
                            color: (modelData.key === "logout" || modelData.key === "poweroff")
                                   ? root.dangerRed
                                   : (root.focusZone === 1 && root.selectedRow === index ? root.focusBlue : (modelData.color || root.draftAccentColor))
                        }

                        ControlCenterIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 34
                            visible: String(modelData.iconKind || "").length > 0
                            kind: String(modelData.iconKind || "power")
                            accent: modelData.accent || modelData.color || root.draftAccentColor
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: String(modelData.iconKind || "").length > 0 ? 82 : 38
                            anchors.right: valueBox.left
                            anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                width: parent.width
                                text: modelData.title
                                color: (modelData.key === "logout" || modelData.key === "poweroff") ? "#FF8D98" : root.textWhite
                                font.pixelSize: 19
                                font.bold: true
                                font.letterSpacing: 0.7
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.subtitle
                                color: root.mutedText
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: valueBox
                            anchors.right: parent.right
                            anchors.rightMargin: 22
                            anchors.verticalCenter: parent.verticalCenter
                            width: 300
                            height: 60
                            radius: 18
                            color: root.panelColor
                            border.width: 1
                            border.color: modelData.color || modelData.accent || root.draftAccentColor

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 22
                                text: modelData.value
                                color: modelData.color || modelData.accent || root.textWhite
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
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
            height: 86
            color: root.chromeColor

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: footerActions.left
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    width: parent.width
                    text: root.statusText
                    color: root.statusError ? "#FF9DA5" : root.draftAccentColor
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 0.55
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: "L1/R1 CATEGORY  •  D-PAD NAVIGATE/CHANGE  •  X SELECT  •  O BACK"
                    color: root.mutedText
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 0.45
                    elide: Text.ElideRight
                }
            }

            Row {
                id: footerActions
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Repeater {
                    model: ["SAVE & CLOSE", "RELOAD", "CLOSE"]

                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        width: index === 0 ? 210 : 150
                        height: 58
                        radius: 18
                        color: root.focusZone === 2 && root.selectedFooter === index ? "#17365D" : "#071426"
                        border.width: root.focusZone === 2 && root.selectedFooter === index ? 2 : 1
                        border.color: root.focusZone === 2 && root.selectedFooter === index
                                      ? root.focusBlue
                                      : (index === 0 ? root.successGreen : "#315A80")

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: root.textWhite
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 0.7
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: profileKeyboardOverlay
        anchors.fill: parent
        visible: keyboardOpen
        enabled: visible
        color: "#E602060D"
        z: 40000

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 100, 1540)
            height: 516
            radius: 24
            color: root.chromeColor
            border.width: 1
            border.color: "#30445B"
            clip: true

            Rectangle {
                id: profileKeyboardField
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 14
                height: 102
                radius: 16
                color: root.panelInset
                border.width: 2
                border.color: root.draftAccentColor

                Column {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22
                    anchors.topMargin: 14
                    anchors.bottomMargin: 12
                    spacing: 5

                    Text {
                        width: parent.width
                        text: keyboardField === "displayName" ? "DISPLAY NAME" : "PROFILE TAGLINE"
                        color: root.draftAccentColor
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 1.1
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: keyboardBuffer.length > 0 ? keyboardBuffer : "TYPE HERE…"
                        color: keyboardBuffer.length > 0 ? root.textWhite : root.mutedText
                        font.pixelSize: 25
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                id: profileKeyboardViewport
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 14
                height: 376
                clip: true

                VirtualKeyboard {
                    id: profileKeyboard
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 432
                    title: ""
                    cancelBehavior: "close"
                    active: root.keyboardOpen

                    onKeyPressed: function(value) {
                        var limit = keyboardField === "displayName" ? 48 : 80
                        if (keyboardBuffer.length < limit)
                            keyboardBuffer += value
                    }
                    onBackspacePressed: keyboardBuffer = keyboardBuffer.slice(0, -1)
                    onEnterPressed: finishKeyboard(true)
                    onClosePressed: finishKeyboard(false)
                }

                // Crop the shared keyboard's standalone title strip; the
                // profile field above now owns the modal label and value.
            }
        }
    }

}
