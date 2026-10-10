import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "TimezoneCatalog.js" as TimezoneCatalog

Item {
    id: root
    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 32000

    // NEUTRONOS_HIERARCHICAL_TIMEZONE_PICKER_V2
    signal closed()
    signal timezoneSelected(string zoneId)

    property int stage: 0 // 0 continent, 1 country, 2 timezone
    property int continentIndex: 0
    property int countryIndex: 0
    property int zoneIndex: 0
    property int selectedIndex: 0
    property var entries: []
    property string currentTimezone: "America/New_York"
    property string statusText: "CONTINENT → COUNTRY → TIMEZONE"
    property bool statusError: false

    readonly property color panelColor: "#071426"
    readonly property color raisedColor: "#0B1A30"
    readonly property color focusBlue: "#4DA6FF"
    readonly property color cyan: "#7DF9FF"
    readonly property color red: "#FF3040"
    readonly property color green: "#22FF88"
    readonly property color textWhite: "#F4FBFF"
    readonly property color muted: "#8AA6C8"

    function clockBackend() {
        try {
            return (typeof clockSettingsManager !== "undefined" && clockSettingsManager)
                    ? clockSettingsManager : null
        } catch (error) { return null }
    }

    function clean(value, fallbackValue) {
        if (value === undefined || value === null) return fallbackValue
        var text = String(value).trim()
        return text.length ? text : fallbackValue
    }

    function entryLabel(entry) {
        if (!entry) return ""
        if (stage === 0) return clean(entry.name, "CONTINENT")
        if (stage === 1) return clean(entry.name, clean(entry.code, "COUNTRY"))
        return clean(entry.label, clean(entry.id, "TIMEZONE"))
    }

    function zoneMeta(zoneId) {
        var backend = clockBackend()
        var source = []
        try { source = backend && backend.availableTimezones ? backend.availableTimezones : [] } catch (error) {}
        for (var i = 0; i < source.length; ++i) {
            var row = source[i]
            var id = ""
            try { id = String(row.id || row.timezone || "") } catch (error2) {}
            if (id !== zoneId) continue
            var abbreviation = ""
            var offset = 0
            try { abbreviation = clean(row.abbreviation, "") } catch (error3) {}
            try { offset = Number(row.offsetSeconds || 0) } catch (error4) { offset = 0 }
            var sign = offset < 0 ? "−" : "+"
            var absolute = Math.abs(offset)
            var hours = Math.floor(absolute / 3600)
            var minutes = Math.floor((absolute % 3600) / 60)
            return "UTC" + sign + hours + ":" + (minutes < 10 ? "0" : "") + minutes +
                   (abbreviation.length ? "  •  " + abbreviation : "")
        }
        return zoneId
    }

    function entryMeta(entry) {
        if (!entry) return ""
        if (stage === 0) return String((entry.countries || []).length) + " COUNTRIES"
        if (stage === 1) return String((entry.zones || []).length) + " TIMEZONE" + ((entry.zones || []).length === 1 ? "" : "S")
        return zoneMeta(clean(entry.id, "UTC"))
    }

    function stageTitle() {
        if (stage === 0) return "SELECT CONTINENT"
        if (stage === 1) return "SELECT COUNTRY"
        return "SELECT TIMEZONE"
    }

    function breadcrumb() {
        var continents = TimezoneCatalog.catalog
        if (stage === 0) return "WORLD"
        var continent = continents[continentIndex]
        if (!continent) return "WORLD"
        if (stage === 1) return continent.name
        var country = continent.countries[countryIndex]
        return continent.name + "  ›  " + (country ? country.name : "COUNTRY")
    }

    function rebuildEntries() {
        if (stage === 0) {
            entries = TimezoneCatalog.catalog
            selectedIndex = Math.max(0, Math.min(entries.length - 1, continentIndex))
        } else if (stage === 1) {
            entries = TimezoneCatalog.countriesFor(continentIndex)
            selectedIndex = Math.max(0, Math.min(entries.length - 1, countryIndex))
        } else {
            entries = TimezoneCatalog.zonesFor(continentIndex, countryIndex)
            selectedIndex = Math.max(0, Math.min(entries.length - 1, zoneIndex))
        }
        Qt.callLater(function() {
            if (pickerList && pickerList.count > 0)
                pickerList.positionViewAtIndex(selectedIndex, ListView.Contain)
        })
    }

    function openModal(context) {
        var backend = clockBackend()
        var zone = "America/New_York"
        try { zone = clean(context && context.currentTimezone, clean(backend ? backend.timezone : "", zone)) } catch (error) {}
        currentTimezone = zone
        var path = TimezoneCatalog.findPath(zone)
        continentIndex = path.continent
        countryIndex = path.country
        zoneIndex = path.zone
        stage = 0
        statusError = false
        statusText = "CONTINENT → COUNTRY → TIMEZONE"
        visible = true
        rebuildEntries()
        forceActiveFocus()
    }

    function open(context) { openModal(context) }

    function closeModal() {
        visible = false
        closed()
    }

    function close() { closeModal() }

    function backOneStage() {
        if (stage === 2) {
            stage = 1
            rebuildEntries()
            return
        }
        if (stage === 1) {
            stage = 0
            rebuildEntries()
            return
        }
        closeModal()
    }

    function activateSelected() {
        if (selectedIndex < 0 || selectedIndex >= entries.length) return
        if (stage === 0) {
            continentIndex = selectedIndex
            countryIndex = 0
            zoneIndex = 0
            stage = 1
            rebuildEntries()
            return
        }
        if (stage === 1) {
            countryIndex = selectedIndex
            zoneIndex = 0
            stage = 2
            rebuildEntries()
            return
        }

        var entry = entries[selectedIndex]
        var zoneId = clean(entry ? entry.id : "", "")
        if (!zoneId.length) return
        var backend = clockBackend()
        var ok = false
        try {
            if (backend && typeof backend.setTimezone === "function")
                ok = backend.setTimezone(zoneId)
            else if (backend && typeof backend.executeAction === "function")
                ok = backend.executeAction("setTimezone", { "timezone": zoneId })
        } catch (error) { ok = false }

        statusError = !ok
        statusText = ok ? "TIMEZONE APPLIED  •  " + zoneId : "TIMEZONE COULD NOT BE APPLIED"
        if (ok) {
            currentTimezone = zoneId
            timezoneSelected(zoneId)
            closeModal()
        }
    }

    function move(delta) {
        if (!entries || entries.length <= 0) return
        selectedIndex = Math.max(0, Math.min(entries.length - 1, selectedIndex + delta))
        pickerList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function handleControllerPressed(action) {
        if (!visible) return false
        var normalized = String(action || "").trim().toLowerCase()
        if (normalized === "up") move(-1)
        else if (normalized === "down") move(1)
        else if (normalized === "l1" || normalized === "left") move(-8)
        else if (normalized === "r1" || normalized === "right") move(8)
        else if (normalized === "primary" || normalized === "x" || normalized === "confirm") activateSelected()
        else if (normalized === "cancel" || normalized === "o" || normalized === "back") backOneStage()
        return true
    }

    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return visible }

    Keys.onPressed: function(event) {
        if (!visible) return
        if (event.key === Qt.Key_Up) move(-1)
        else if (event.key === Qt.Key_Down) move(1)
        else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_Left) move(-8)
        else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Right) move(8)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) activateSelected()
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back || event.key === Qt.Key_Backspace) backOneStage()
        event.accepted = true
    }

    Rectangle { anchors.fill: parent; color: "#D8020710" }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 180, 1180)
        height: Math.min(parent.height - 130, 820)
        radius: 30
        color: root.panelColor
        border.width: 3
        border.color: root.focusBlue

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 82
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text { text: root.stageTitle(); color: root.textWhite; font.pixelSize: 25; font.bold: true; font.letterSpacing: 1.2 }
                    Text { text: root.breadcrumb(); color: root.cyan; font.pixelSize: 13; font.bold: true }
                    Text { text: root.stage < 2 ? "X NEXT  •  O BACK  •  D-PAD NAVIGATE" : "X APPLY  •  O BACK  •  D-PAD NAVIGATE"; color: root.muted; font.pixelSize: 11; font.bold: true }
                }
                Rectangle {
                    Layout.preferredWidth: 170
                    Layout.preferredHeight: 46
                    radius: 15
                    color: "#050D18"
                    border.width: 1
                    border.color: "#31516B"
                    Text { anchors.centerIn: parent; text: (root.selectedIndex + 1) + " / " + root.entries.length; color: root.cyan; font.pixelSize: 13; font.bold: true }
                }
            }

            ListView {
                id: pickerList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 7
                model: root.entries
                currentIndex: root.selectedIndex
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
                    width: pickerList.width - 18
                    height: 70
                    radius: 17
                    color: root.selectedIndex === index ? "#12375B" : "#091827"
                    border.width: root.selectedIndex === index ? 3 : 1
                    border.color: root.selectedIndex === index ? root.focusBlue : "#203D55"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        spacing: 12
                        Text { text: root.entryLabel(modelData); color: root.textWhite; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: root.entryMeta(modelData); color: root.cyan; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 300; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                text: root.statusText
                color: root.statusError ? root.red : root.green
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }
}
