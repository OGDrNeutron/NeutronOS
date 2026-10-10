import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components"

Item {
    id: root

    // NEUTRONOS_CLOCK_FULL_CONTROL_CENTER_V2

    anchors.fill: parent
    visible: true
    enabled: visible
    focus: visible
    opacity: 1.0
    z: 30000


    /* Shared Controller Control Center visual language. */
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

    property int focusZone: 0             // 0 category rail, 1 rows, 2 footer
    property int selectedCategory: 0
    property int selectedRow: 0
    property int selectedFooter: 0
    property int armedRow: -1

    property bool draftUse24Hour: false
    property bool draftShowSeconds: false
    property bool draftUppercaseMeridiem: true
    property bool draftShowDate: true
    property bool draftShowWeekday: true
    property bool draftShowTimezone: false
    property string draftDateFormat: "long"
    property string draftClockStyle: "standard"
    property string draftTimezone: "UTC"
    property string draftClockTint: "#FFFFFF"
    property string draftDateTint: "#9FD8FF"
    property string draftTimezoneTint: "#7DF9FF"
    property int draftClockScale: 100
    property int clockHeaderIconIndex: 0

    property var rows: []
    property string statusText: "CHANGES APPLY IMMEDIATELY AND PERSIST"
    property bool statusError: false

    property bool timezoneBrowserOpen: false
    property var timezoneRows: []
    property int selectedTimezone: 0

    readonly property var categories: [
        { "id": "time", "title": "TIME", "subtitle": "Format and seconds", "iconKind": "time" },
        { "id": "date", "title": "DATE", "subtitle": "Visibility and order", "iconKind": "calendar" },
        { "id": "region", "title": "REGION", "subtitle": "Timezone and label", "iconKind": "globe" },
        { "id": "appearance", "title": "APPEARANCE", "subtitle": "Style, size, icon and color", "iconKind": "appearance" },
        { "id": "preview", "title": "PREVIEW", "subtitle": "Review and restore", "iconKind": "eye" }
    ]
    readonly property var clockHeaderIconKinds: ["clockClassic", "clockDigital", "clockMinimal", "clockRing", "clockDot"]

    readonly property var dateFormats: ["long", "medium", "mdy", "dmy", "iso"]
    readonly property var clockStyles: ["standard", "compact", "wide"]
    readonly property var colorPresets: [
        "#FFFFFF", "#DCEEFF", "#7DF9FF", "#47C8FF", "#4DA6FF",
        "#6366F1", "#8B5CF6", "#C084FC", "#E879F9", "#F472B6",
        "#FF3040", "#F97316", "#F5C542", "#D9F542", "#22FF88",
        "#10B981", "#14B8A6", "#94A3B8", "#64748B", "#CBD5E1"
    ]

    function backend() {
        try {
            if (typeof clockExperienceManager !== "undefined" && clockExperienceManager)
                return clockExperienceManager
        } catch (error) {}
        try {
            if (typeof clockSettingsManager !== "undefined" && clockSettingsManager)
                return clockSettingsManager
        } catch (error2) {}
        return null
    }

    function systemClockBackend() {
        try {
            return (typeof clockSettingsManager !== "undefined" && clockSettingsManager)
                   ? clockSettingsManager : null
        } catch (error) {
            return null
        }
    }

    function uiSettingsBackend() {
        try {
            return (typeof settingsManager !== "undefined" && settingsManager)
                   ? settingsManager : null
        } catch (error) {
            return null
        }
    }

    function readHeaderIconIndex() {
        var settings = uiSettingsBackend()
        try {
            if (settings && typeof settings.value === "function") {
                var value = Number(settings.value("ui.dashboard.header.clockIcon", 0))
                if (!isNaN(value))
                    return Math.max(0, Math.min(clockHeaderIconKinds.length - 1, Math.round(value)))
            }
        } catch (error) {}
        return 0
    }

    function saveHeaderIconIndex(value) {
        var next = Math.max(0, Math.min(clockHeaderIconKinds.length - 1, Math.round(Number(value))))
        var settings = uiSettingsBackend()
        var ok = false
        try {
            if (settings && typeof settings.setUiPreference === "function")
                ok = settings.setUiPreference("ui.dashboard.header.clockIcon", next) !== false
        } catch (error) { ok = false }
        if (ok) {
            clockHeaderIconIndex = next
            statusError = false
            statusText = "SYSTEM OVERVIEW CLOCK ICON UPDATED"
            actionRequested("clockIconChanged", { "index": next, "kind": clockHeaderIconKinds[next] })
        } else {
            statusError = true
            statusText = "CLOCK ICON COULD NOT BE SAVED"
        }
        rebuildRows()
        return ok
    }

    function clean(value, fallbackValue) {
        if (value === undefined || value === null)
            return fallbackValue
        var text = String(value).trim()
        return text.length > 0 && text !== "undefined" && text !== "null" ? text : fallbackValue
    }

    function readBool(object, key, fallbackValue) {
        try {
            if (object && object[key] !== undefined && object[key] !== null)
                return Boolean(object[key])
        } catch (error) {}
        return fallbackValue
    }

    function readInt(object, key, fallbackValue) {
        try {
            if (object && object[key] !== undefined && object[key] !== null) {
                var value = Number(object[key])
                if (!isNaN(value))
                    return Math.round(value)
            }
        } catch (error) {}
        return fallbackValue
    }

    function readString(object, key, fallbackValue) {
        try {
            if (object && object[key] !== undefined && object[key] !== null)
                return clean(object[key], fallbackValue)
        } catch (error) {}
        return fallbackValue
    }

    function loadFromBackend() {
        var clock = backend()
        draftUse24Hour = readBool(clock, "use24Hour", false)
        draftShowSeconds = readBool(clock, "showSeconds", false)
        draftUppercaseMeridiem = readBool(clock, "uppercaseMeridiem", true)
        draftShowDate = readBool(clock, "showDate", true)
        draftShowWeekday = readBool(clock, "showWeekday", true)
        draftShowTimezone = readBool(clock, "showTimezone", false)
        draftDateFormat = readString(clock, "dateFormat", "long")
        draftClockStyle = readString(clock, "clockStyle", "standard")
        draftTimezone = readString(clock, "timezone", "UTC")
        draftClockTint = readString(clock, "clockTint", "#FFFFFF")
        draftDateTint = readString(clock, "dateTint", "#9FD8FF")
        draftTimezoneTint = readString(clock, "timezoneTint", "#7DF9FF")
        draftClockScale = Math.max(80, Math.min(140, readInt(clock, "clockScale", 100)))
        clockHeaderIconIndex = readHeaderIconIndex()
        rebuildRows()
        rebuildTimezoneRows()
    }

    function currentRows() {
        var id = categories[selectedCategory].id
        if (id === "time") {
            return [
                { "key": "format", "title": "TIME FORMAT", "description": "Choose a 12-hour or 24-hour clock", "value": draftUse24Hour ? "24 HOUR" : "12 HOUR", "kind": "choice" },
                { "key": "seconds", "title": "SHOW SECONDS", "description": "Display seconds in the Console clock", "value": draftShowSeconds ? "ON" : "OFF", "kind": "toggle" },
                { "key": "meridiem", "title": "AM / PM LETTERS", "description": "Uppercase or lowercase meridiem", "value": draftUppercaseMeridiem ? "UPPERCASE" : "lowercase", "kind": "choice", "enabled": !draftUse24Hour }
            ]
        }
        if (id === "date") {
            return [
                { "key": "showDate", "title": "SHOW DATE", "description": "Show or hide the date under the clock", "value": draftShowDate ? "ON" : "OFF", "kind": "toggle" },
                { "key": "weekday", "title": "SHOW WEEKDAY", "description": "Include the day of the week", "value": draftShowWeekday ? "ON" : "OFF", "kind": "toggle", "enabled": draftShowDate },
                { "key": "dateFormat", "title": "DATE FORMAT", "description": "Long, medium, US, international or ISO", "value": dateFormatLabel(), "kind": "choice", "enabled": draftShowDate }
            ]
        }
        if (id === "region") {
            return [
                { "key": "timezone", "title": "TIMEZONE", "description": "Open the complete controller-selectable timezone list", "value": draftTimezone, "kind": "browser" },
                { "key": "showTimezone", "title": "SHOW ZONE LABEL", "description": "Display EST, EDT, UTC and similar labels", "value": draftShowTimezone ? "ON" : "OFF", "kind": "toggle" },
                { "key": "applySystemZone", "title": "APPLY TO SYSTEM", "description": "Set the Linux system timezone to the selected zone", "value": "PRESS X", "kind": "action" }
            ]
        }
        if (id === "appearance") {
            return [
                { "key": "headerIcon", "title": "SYSTEM OVERVIEW ICON", "description": "Five persistent clock icons for the System Overview tab", "value": "ICON " + (clockHeaderIconIndex + 1) + " OF 5", "kind": "icon" },
                { "key": "style", "title": "CLOCK STYLE", "description": "Standard, compact or wide spacing", "value": draftClockStyle.toUpperCase(), "kind": "choice" },
                { "key": "scale", "title": "CLOCK SIZE", "description": "Scale the Console clock from 80% to 140%", "value": draftClockScale + "%", "kind": "slider" },
                { "key": "clockTint", "title": "TIME COLOR", "description": "Tint used for the main time", "value": draftClockTint, "kind": "color" },
                { "key": "dateTint", "title": "DATE COLOR", "description": "Tint used for the date line", "value": draftDateTint, "kind": "color" },
                { "key": "timezoneTint", "title": "ZONE COLOR", "description": "Tint used for the timezone label", "value": draftTimezoneTint, "kind": "color" }
            ]
        }
        return [
            { "key": "preview", "title": "LIVE CONSOLE PREVIEW", "description": previewDateText(), "value": previewTimeText(), "kind": "preview" },
            { "key": "reload", "title": "RELOAD SAVED SETTINGS", "description": "Discard local draft values and reload persistence", "value": "PRESS X", "kind": "action" },
            { "key": "reset", "title": "RESET CLOCK SETTINGS", "description": "Restore all Clock & Date defaults", "value": armedRow === 2 ? "PRESS X AGAIN" : "PRESS X", "kind": "danger" }
        ]
    }

    function rebuildRows() {
        rows = currentRows()
        if (selectedRow >= rows.length)
            selectedRow = Math.max(0, rows.length - 1)
        Qt.callLater(function() {
            if (settingsList && settingsList.count > 0)
                settingsList.positionViewAtIndex(selectedRow, ListView.Contain)
        })
    }

    function timezoneId(entry) {
        if (typeof entry === "string")
            return entry
        try { return clean(entry.id || entry.timezone, "UTC") } catch (error) { return "UTC" }
    }

    function timezoneLabel(entry) {
        if (typeof entry === "string")
            return String(entry).replace(/_/g, " ")
        try { return clean(entry.displayName, timezoneId(entry).replace(/_/g, " ")) } catch (error) { return timezoneId(entry) }
    }

    function timezoneMeta(entry) {
        if (typeof entry === "string")
            return ""
        try {
            var abbreviation = clean(entry.abbreviation, "")
            var offset = Number(entry.offsetSeconds || 0)
            var sign = offset < 0 ? "−" : "+"
            var absolute = Math.abs(offset)
            var hours = Math.floor(absolute / 3600)
            var minutes = Math.floor((absolute % 3600) / 60)
            return "UTC" + sign + hours + ":" + (minutes < 10 ? "0" : "") + minutes + (abbreviation.length > 0 ? "  •  " + abbreviation : "")
        } catch (error) {
            return ""
        }
    }

    function rebuildTimezoneRows() {
        var clock = backend()
        var source = []
        try { source = clock && clock.availableTimezones ? clock.availableTimezones : [] } catch (error) {}
        if (!source || source.length <= 0)
            source = [ { "id": draftTimezone, "displayName": draftTimezone } ]
        timezoneRows = source
        selectedTimezone = 0
        for (var i = 0; i < timezoneRows.length; ++i) {
            if (timezoneId(timezoneRows[i]) === draftTimezone) {
                selectedTimezone = i
                break
            }
        }
    }

    function dateFormatLabel() {
        if (draftDateFormat === "mdy") return "MM/DD/YYYY"
        if (draftDateFormat === "dmy") return "DD/MM/YYYY"
        if (draftDateFormat === "iso") return "YYYY-MM-DD"
        return draftDateFormat.toUpperCase()
    }

    function previewTimeText() {
        var clock = backend()
        try {
            if (clock && typeof clock.formatCurrentTime === "function")
                return clean(clock.formatCurrentTime(), "--:--")
            return clean(clock.currentTimeText, "--:--")
        } catch (error) {
            return "--:--"
        }
    }

    function previewDateText() {
        var clock = backend()
        try {
            var dateText = clean(clock.currentDateText, "DATE HIDDEN")
            var zoneText = clean(clock.timezoneLabel, "")
            return zoneText.length > 0 ? dateText + "  •  " + zoneText : dateText
        } catch (error) {
            return "DATE PREVIEW"
        }
    }

    function payload() {
        return {
            "use24Hour": draftUse24Hour,
            "showSeconds": draftShowSeconds,
            "uppercaseMeridiem": draftUppercaseMeridiem,
            "showDate": draftShowDate,
            "showWeekday": draftShowWeekday,
            "showTimezone": draftShowTimezone,
            "dateFormat": draftDateFormat,
            "clockStyle": draftClockStyle,
            "timezone": draftTimezone,
            "clockTint": draftClockTint,
            "dateTint": draftDateTint,
            "timezoneTint": draftTimezoneTint,
            "clockScale": draftClockScale
        }
    }

    function applyDraft(message) {
        var clock = backend()
        var ok = false
        try {
            if (clock && typeof clock.applySettings === "function")
                ok = clock.applySettings(payload())
            else if (clock && typeof clock.executeAction === "function")
                ok = clock.executeAction("apply", payload())
        } catch (error) {
            ok = false
        }
        statusError = !ok
        statusText = ok ? (message || "APPLIED IMMEDIATELY") : "CLOCK SETTINGS COULD NOT BE APPLIED"
        rebuildRows()
        return ok
    }

    function cycleValue(array, value, delta) {
        var index = array.indexOf(value)
        if (index < 0) index = 0
        return array[(index + delta + array.length) % array.length]
    }

    function cycleColor(value, delta) {
        return cycleValue(colorPresets, String(value).toUpperCase(), delta)
    }

    function adjustSelected(delta) {
        if (focusZone !== 1 || rows.length <= 0)
            return false
        var row = rows[selectedRow]
        if (row.enabled === false)
            return false
        var key = row.key
        if (key === "format") draftUse24Hour = !draftUse24Hour
        else if (key === "seconds") draftShowSeconds = !draftShowSeconds
        else if (key === "meridiem") draftUppercaseMeridiem = !draftUppercaseMeridiem
        else if (key === "showDate") draftShowDate = !draftShowDate
        else if (key === "weekday") draftShowWeekday = !draftShowWeekday
        else if (key === "dateFormat") draftDateFormat = cycleValue(dateFormats, draftDateFormat, delta)
        else if (key === "showTimezone") draftShowTimezone = !draftShowTimezone
        else if (key === "headerIcon") {
            var nextIcon = (clockHeaderIconIndex + delta + clockHeaderIconKinds.length) % clockHeaderIconKinds.length
            saveHeaderIconIndex(nextIcon)
            return true
        }
        else if (key === "style") draftClockStyle = cycleValue(clockStyles, draftClockStyle, delta)
        else if (key === "scale") draftClockScale = Math.max(80, Math.min(140, draftClockScale + delta * 5))
        else if (key === "clockTint") draftClockTint = cycleColor(draftClockTint, delta)
        else if (key === "dateTint") draftDateTint = cycleColor(draftDateTint, delta)
        else if (key === "timezoneTint") draftTimezoneTint = cycleColor(draftTimezoneTint, delta)
        else return false
        armedRow = -1
        applyDraft("APPLIED IMMEDIATELY")
        return true
    }

    function applySystemTimezone() {
        var systemClock = systemClockBackend()
        var ok = false
        try {
            if (systemClock && typeof systemClock.setTimezone === "function")
                ok = systemClock.setTimezone(draftTimezone)
            else if (systemClock && typeof systemClock.executeAction === "function")
                ok = systemClock.executeAction("setTimezone", { "timezone": draftTimezone })
        } catch (error) { ok = false }
        statusError = !ok
        statusText = ok ? "LINUX SYSTEM TIMEZONE UPDATED" : "SYSTEM TIMEZONE REQUIRES BACKEND PERMISSION"
    }

    function activateSelected() {
        if (focusZone === 0) {
            focusZone = 1
            rebuildRows()
            return
        }
        if (focusZone === 2) {
            if (selectedFooter === 0) loadFromBackend()
            else close()
            return
        }
        if (rows.length <= 0)
            return
        var key = rows[selectedRow].key
        if (key === "timezone") {
            rebuildTimezoneRows()
            timezoneBrowserOpen = true
            timezoneList.positionViewAtIndex(selectedTimezone, ListView.Center)
            timezoneList.forceActiveFocus()
            return
        }
        if (key === "applySystemZone") {
            applySystemTimezone()
            return
        }
        if (key === "reload") {
            loadFromBackend()
            statusError = false
            statusText = "SAVED CLOCK SETTINGS RELOADED"
            return
        }
        if (key === "reset") {
            if (armedRow !== selectedRow) {
                armedRow = selectedRow
                statusError = true
                statusText = "RESET ARMED — PRESS X AGAIN"
                rebuildRows()
            } else {
                var clock = backend()
                var ok = false
                try {
                    if (clock && typeof clock.resetDefaults === "function")
                        ok = clock.resetDefaults()
                    else if (clock && typeof clock.executeAction === "function")
                        ok = clock.executeAction("reset", {})
                } catch (error) {}
                loadFromBackend()
                armedRow = -1
                statusError = !ok
                statusText = ok ? "CLOCK SETTINGS RESTORED" : "RESET FAILED"
            }
            return
        }
        adjustSelected(1)
    }

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        focusZone = 0
        selectedCategory = 0
        selectedRow = 0
        selectedFooter = 0
        armedRow = -1
        timezoneBrowserOpen = false
        statusError = false
        statusText = "CHANGES APPLY IMMEDIATELY AND PERSIST"
        visible = true
        loadFromBackend()

        // Header Clock menu can open the established full settings panel at
        // the exact section the user selected instead of dumping them at the
        // first category every time.
        var requested = ""
        try { requested = String(contextData.focusSection || "").trim() } catch (error) { requested = "" }
        if (requested === "dateTime") selectedCategory = 1
        else if (requested === "format") selectedCategory = 0
        else if (requested === "icon") selectedCategory = 3
        else if (requested === "text") selectedCategory = 3
        if (requested.length > 0) focusZone = 1
        selectedRow = requested === "icon" ? 0 : 0
        rebuildRows()
        forceActiveFocus()
    }

    function openModal(context) { open(context) }

    function close() {
        if (!visible) return
        timezoneBrowserOpen = false
        visible = false
        closed()
    }

    function closeModal() { close() }

    function handleControllerPressed(action) {
        if (!visible)
            return false

        var normalized = String(action || "").trim().toLowerCase()

        if (timezoneBrowserOpen) {
            if (normalized === "up") {
                selectedTimezone = Math.max(0, selectedTimezone - 1)
                timezoneList.positionViewAtIndex(selectedTimezone, ListView.Contain)
            } else if (normalized === "down") {
                selectedTimezone = Math.min(timezoneRows.length - 1, selectedTimezone + 1)
                timezoneList.positionViewAtIndex(selectedTimezone, ListView.Contain)
            } else if (normalized === "l1" || normalized === "left") {
                selectedTimezone = Math.max(0, selectedTimezone - 10)
                timezoneList.positionViewAtIndex(selectedTimezone, ListView.Center)
            } else if (normalized === "r1" || normalized === "right") {
                selectedTimezone = Math.min(timezoneRows.length - 1, selectedTimezone + 10)
                timezoneList.positionViewAtIndex(selectedTimezone, ListView.Center)
            } else if (normalized === "primary" || normalized === "x" || normalized === "confirm") {
                if (selectedTimezone >= 0 && selectedTimezone < timezoneRows.length) {
                    draftTimezone = timezoneId(timezoneRows[selectedTimezone])
                    timezoneBrowserOpen = false
                    // NEUTRONOS_CLOCK_TIMEZONE_APPLY_V1
                    var preferenceApplied = applyDraft("TIMEZONE PREFERENCE APPLIED")
                    if (preferenceApplied)
                        applySystemTimezone()
                    forceActiveFocus()
                }
            } else if (normalized === "cancel" || normalized === "o" || normalized === "back") {
                timezoneBrowserOpen = false
                forceActiveFocus()
            }
            return true
        }

        if (normalized === "cancel" || normalized === "o" || normalized === "back") {
            if (focusZone === 1 || focusZone === 2) {
                focusZone = 0
                armedRow = -1
            } else {
                close()
            }
            return true
        }

        if (normalized === "l1") {
            selectedCategory = (selectedCategory - 1 + categories.length) % categories.length
            selectedRow = 0
            focusZone = 1
            rebuildRows()
            return true
        }

        if (normalized === "r1") {
            selectedCategory = (selectedCategory + 1) % categories.length
            selectedRow = 0
            focusZone = 1
            rebuildRows()
            return true
        }

        if (normalized === "left") {
            if (focusZone === 1)
                adjustSelected(-1)
            else if (focusZone === 2)
                selectedFooter = Math.max(0, selectedFooter - 1)
            return true
        }

        if (normalized === "right") {
            if (focusZone === 1)
                adjustSelected(1)
            else if (focusZone === 2)
                selectedFooter = Math.min(1, selectedFooter + 1)
            else
                focusZone = 1
            return true
        }

        if (normalized === "up") {
            armedRow = -1
            if (focusZone === 0) {
                selectedCategory = Math.max(0, selectedCategory - 1)
                selectedRow = 0
                rebuildRows()
            } else if (focusZone === 1) {
                selectedRow = Math.max(0, selectedRow - 1)
                settingsList.positionViewAtIndex(selectedRow, ListView.Contain)
            } else {
                focusZone = 1
            }
            return true
        }

        if (normalized === "down") {
            armedRow = -1
            if (focusZone === 0) {
                selectedCategory = Math.min(categories.length - 1, selectedCategory + 1)
                selectedRow = 0
                rebuildRows()
            } else if (focusZone === 1) {
                if (selectedRow < rows.length - 1) {
                    selectedRow += 1
                    settingsList.positionViewAtIndex(selectedRow, ListView.Contain)
                } else {
                    focusZone = 2
                }
            }
            return true
        }

        if (normalized === "primary" || normalized === "x" || normalized === "confirm") {
            activateSelected()
            return true
        }

        return true
    }

    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return visible }

    Keys.onPressed: function(event) {
        if (!visible || timezoneBrowserOpen)
            return
        var key = event.key
        if (key === Qt.Key_Escape || key === Qt.Key_Back || key === Qt.Key_Backspace) {
            if (focusZone === 1 || focusZone === 2) {
                focusZone = 0
                armedRow = -1
            } else close()
            event.accepted = true
            return
        }
        if (key === Qt.Key_Left) {
            if (focusZone === 1 && adjustSelected(-1)) {}
            else if (focusZone === 2) selectedFooter = Math.max(0, selectedFooter - 1)
            else if (focusZone === 0) {}
            event.accepted = true
            return
        }
        if (key === Qt.Key_Right) {
            if (focusZone === 1 && adjustSelected(1)) {}
            else if (focusZone === 2) selectedFooter = Math.min(1, selectedFooter + 1)
            else if (focusZone === 0) focusZone = 1
            event.accepted = true
            return
        }
        if (key === Qt.Key_Up) {
            armedRow = -1
            if (focusZone === 0) {
                selectedCategory = Math.max(0, selectedCategory - 1)
                selectedRow = 0
                rebuildRows()
            } else if (focusZone === 1) {
                selectedRow = Math.max(0, selectedRow - 1)
                settingsList.positionViewAtIndex(selectedRow, ListView.Contain)
            } else focusZone = 1
            event.accepted = true
            return
        }
        if (key === Qt.Key_Down) {
            armedRow = -1
            if (focusZone === 0) {
                selectedCategory = Math.min(categories.length - 1, selectedCategory + 1)
                selectedRow = 0
                rebuildRows()
            } else if (focusZone === 1) {
                if (selectedRow < rows.length - 1) {
                    selectedRow += 1
                    settingsList.positionViewAtIndex(selectedRow, ListView.Contain)
                } else focusZone = 2
            }
            event.accepted = true
            return
        }
        if (key === Qt.Key_PageUp || key === Qt.Key_Q) {
            selectedCategory = (selectedCategory - 1 + categories.length) % categories.length
            selectedRow = 0
            focusZone = 1
            rebuildRows()
            event.accepted = true
            return
        }
        if (key === Qt.Key_PageDown || key === Qt.Key_E) {
            selectedCategory = (selectedCategory + 1) % categories.length
            selectedRow = 0
            focusZone = 1
            rebuildRows()
            event.accepted = true
            return
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            activateSelected()
            event.accepted = true
        }
    }

    Connections {
        target: backend()
        enabled: target !== null
        ignoreUnknownSignals: true

        function onDisplayChanged() { rebuildRows() }
        function onSettingsChanged() { if (root.visible && !root.timezoneBrowserOpen) root.loadFromBackend() }
        function onAvailableTimezonesChanged() { root.rebuildTimezoneRows() }
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
            color: "#091A30"

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
                    border.color: root.neutronCyan

                    ControlCenterIcon {
                        anchors.centerIn: parent
                        width: 42
                        height: 42
                        kind: "time"
                        accent: root.neutronCyan
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Text {
                        text: "CLOCK & DATE CONTROL CENTER"
                        color: root.textWhite
                        font.pixelSize: 28
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Text {
                        text: "LIVE TIME  •  REGION  •  APPEARANCE  •  PERSISTENT"
                        color: root.neutronCyan
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
                height: 88
                radius: 22
                color: "#071222"
                border.width: 1
                border.color: root.draftClockTint

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    spacing: 22

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 270
                        spacing: 2

                        Text {
                            width: parent.width
                            text: root.previewTimeText()
                            color: root.draftClockTint
                            font.pixelSize: Math.round(29 * root.draftClockScale / 100)
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.previewDateText()
                            visible: root.draftShowDate
                            color: root.draftDateTint
                            font.pixelSize: 13
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 52
                        color: "#27496B"
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 290
                        spacing: 7

                        Text {
                            width: parent.width
                            text: root.draftTimezone
                            color: root.draftTimezoneTint
                            font.pixelSize: 16
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.draftClockStyle.toUpperCase() + "  •  " + root.draftClockScale + "%"
                            color: root.mutedText
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.7
                        }
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
            color: "#071221"

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
                        color: root.selectedCategory === index
                               ? "#17365D"
                               : "#09182B"
                        border.width: root.focusZone === 0 && root.selectedCategory === index ? 2 : 1
                        border.color: root.selectedCategory === index
                                      ? (root.focusZone === 0 ? root.focusBlue : root.neutronCyan)
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
                            border.color: root.selectedCategory === index ? root.neutronCyan : "#315A80"

                            ControlCenterIcon {
                                anchors.centerIn: parent
                                width: 27
                                height: 27
                                kind: modelData.iconKind
                                accent: root.selectedCategory === index ? "#04111F" : root.neutronCyan
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
                    text: root.categories[root.selectedCategory].subtitle + ". Changes apply immediately and remain after restart."
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
                    model: root.rows
                    currentIndex: root.selectedRow
                    interactive: false
                    rightMargin: 18

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOn
                        width: 9
                        contentItem: Rectangle { radius: 5; color: root.focusBlue }
                        background: Rectangle { radius: 5; color: "#142A3D" }
                    }

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: settingsList.width - 18
                        height: modelData.kind === "preview" ? 176 : 100
                        radius: 20
                        color: root.focusZone === 1 && root.selectedRow === index
                               ? (modelData.kind === "danger" && root.armedRow === index ? "#49111A" : "#17365D")
                               : root.panelRaised
                        border.width: root.focusZone === 1 && root.selectedRow === index ? 2 : 1
                        border.color: root.focusZone === 1 && root.selectedRow === index
                                      ? (modelData.kind === "danger" ? root.dangerRed : root.focusBlue)
                                      : "#284B6E"
                        opacity: modelData.enabled === false ? 0.45 : 1.0

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: parent.height - 28
                            radius: 4
                            color: modelData.kind === "danger"
                                   ? root.dangerRed
                                   : (root.focusZone === 1 && root.selectedRow === index ? root.focusBlue : "#264B70")
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 38
                            anchors.right: valueBox.left
                            anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                width: parent.width
                                text: modelData.title
                                color: modelData.kind === "danger" ? "#FF8D98" : root.textWhite
                                font.pixelSize: 19
                                font.bold: true
                                font.letterSpacing: 0.7
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.description
                                color: root.mutedText
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: valueBox
                            anchors.right: parent.right
                            anchors.rightMargin: 22
                            anchors.verticalCenter: parent.verticalCenter
                            width: modelData.kind === "preview" ? 360 : 280
                            height: modelData.kind === "preview" ? 126 : 60
                            radius: 18
                            color: root.panelColor
                            border.width: 1
                            border.color: modelData.kind === "color"
                                          ? modelData.value
                                          : (modelData.kind === "danger" ? root.dangerRed : "#315A80")

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 28
                                spacing: 6

                                Text {
                                    width: parent.width
                                    text: modelData.value
                                    color: modelData.kind === "color"
                                           ? modelData.value
                                           : (modelData.kind === "danger" ? "#FF8D98" : root.neutronCyan)
                                    font.pixelSize: modelData.kind === "preview"
                                                    ? Math.round(31 * root.draftClockScale / 100)
                                                    : 17
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: modelData.kind === "preview"
                                    text: root.previewDateText()
                                    color: root.draftDateTint
                                    font.pixelSize: 13
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
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
            color: "#081629"

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
                    color: root.statusError ? "#FF9DA5" : root.neutronCyan
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 0.55
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: "L1/R1 CATEGORY  •  D-PAD NAVIGATE  •  LEFT/RIGHT CHANGE  •  X SELECT  •  O BACK"
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
                    model: ["RELOAD", "CLOSE"]

                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        width: index === 0 ? 190 : 160
                        height: 58
                        radius: 18
                        color: root.focusZone === 2 && root.selectedFooter === index ? "#17365D" : "#071426"
                        border.width: root.focusZone === 2 && root.selectedFooter === index ? 2 : 1
                        border.color: root.focusZone === 2 && root.selectedFooter === index ? root.focusBlue : "#315A80"

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
        anchors.fill: parent
        visible: timezoneBrowserOpen
        color: "#02040CFA"
        z: 40000

        Keys.onPressed: function(event) {
            if (!timezoneBrowserOpen)
                return
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back || event.key === Qt.Key_Backspace) {
                timezoneBrowserOpen = false
                root.forceActiveFocus()
            } else if (event.key === Qt.Key_Up) {
                selectedTimezone = Math.max(0, selectedTimezone - 1)
                timezoneList.positionViewAtIndex(selectedTimezone, ListView.Contain)
            } else if (event.key === Qt.Key_Down) {
                selectedTimezone = Math.min(timezoneRows.length - 1, selectedTimezone + 1)
                timezoneList.positionViewAtIndex(selectedTimezone, ListView.Contain)
            } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Q) {
                selectedTimezone = Math.max(0, selectedTimezone - 10)
                timezoneList.positionViewAtIndex(selectedTimezone, ListView.Center)
            } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_E) {
                selectedTimezone = Math.min(timezoneRows.length - 1, selectedTimezone + 10)
                timezoneList.positionViewAtIndex(selectedTimezone, ListView.Center)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (selectedTimezone >= 0 && selectedTimezone < timezoneRows.length) {
                    draftTimezone = timezoneId(timezoneRows[selectedTimezone])
                    timezoneBrowserOpen = false
                    applyDraft("TIMEZONE APPLIED IMMEDIATELY")
                    root.forceActiveFocus()
                }
            }
            event.accepted = true
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 180, 1180)
            height: Math.min(parent.height - 130, 820)
            radius: 30
            color: "#071426"
            border.width: 3
            border.color: "#4DA6FF"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: "SELECT TIMEZONE"; color: "white"; font.pixelSize: 24; font.bold: true; font.letterSpacing: 1.4 }
                        Text { text: "FULL SYSTEM LIST  •  L1 / R1 JUMP TEN  •  X SELECT  •  O CANCEL"; color: "#8AA6C8"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 0.8 }
                    }
                    Rectangle { Layout.preferredWidth: 230; Layout.preferredHeight: 46; radius: 15; color: "#050D18"; border.width: 1; border.color: "#31516B"; Text { anchors.centerIn: parent; text: (selectedTimezone + 1) + " / " + timezoneRows.length; color: "#7DF9FF"; font.pixelSize: 13; font.bold: true } }
                }

                ListView {
                    id: timezoneList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 7
                    model: timezoneRows
                    currentIndex: selectedTimezone
                    interactive: false
                    rightMargin: 18
                    focus: timezoneBrowserOpen

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOn
                        width: 9
                        contentItem: Rectangle { radius: 5; color: "#4DA6FF" }
                        background: Rectangle { radius: 5; color: "#142A3D" }
                    }

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: timezoneList.width - 18
                        height: 68
                        radius: 17
                        color: selectedTimezone === index ? "#12375B" : "#091827"
                        border.width: selectedTimezone === index ? 3 : 1
                        border.color: selectedTimezone === index ? "#4DA6FF" : "#203D55"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12
                            Text { text: timezoneLabel(modelData); color: "white"; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { text: timezoneMeta(modelData); color: "#7DF9FF"; font.pixelSize: 12; font.bold: true }
                        }
                    }
                }
            }
        }
    }
}
