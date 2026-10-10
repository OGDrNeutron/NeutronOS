import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: true
    enabled: visible
    focus: visible
    z: 30000

    property var contextData: ({})
    property var modalContext: ({})
    property int selectedIndex: 0
    property bool iconPickerOpen: false
    property int iconIndex: 0
    property string statusText: "CLOCK QUICK SETTINGS"

    readonly property color panelColor: "#071426"
    readonly property color panelRaised: "#0B1A30"
    readonly property color panelInset: "#06101F"
    readonly property color electricBlue: "#00A8FF"
    readonly property color neutronCyan: "#7DF9FF"
    readonly property color textWhite: "#F4FBFF"
    readonly property color mutedText: "#8AA6C8"
    readonly property var clockIcons: ["◷", "◴", "◶", "◵", "◉"]
    readonly property var rows: [
        { title: "DATE / TIME", detail: "Date visibility, timezone and regional clock behavior", section: "dateTime", icon: "◷" },
        { title: "CLOCK FORMAT", detail: "12 / 24 hour, seconds and AM / PM presentation", section: "format", icon: "12" },
        { title: "CLOCK ICON", detail: "Choose the icon shown in the System Overview header", section: "icon", icon: "◉" },
        { title: "CLOCK TEXT", detail: "Clock size, spacing and time/date text colors", section: "text", icon: "Aa" }
    ]

    signal closed()
    signal actionRequested(string action, var payload)

    function settingsBackend() {
        try { return (typeof settingsManager !== "undefined" && settingsManager) ? settingsManager : null }
        catch (error) { return null }
    }

    function readIconIndex() {
        var backend = settingsBackend()
        try {
            if (backend && typeof backend.value === "function") {
                var value = Number(backend.value("ui.dashboard.header.clockIcon", 0))
                if (!isNaN(value))
                    return Math.max(0, Math.min(clockIcons.length - 1, Math.round(value)))
            }
        } catch (error) {}
        return 0
    }

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        selectedIndex = 0
        iconPickerOpen = false
        iconIndex = readIconIndex()
        statusText = "CLOCK QUICK SETTINGS"
        visible = true
        forceActiveFocus()
    }

    function openModal(context) { open(context) }

    function close() {
        if (iconPickerOpen) {
            iconPickerOpen = false
            forceActiveFocus()
            return
        }
        visible = false
        closed()
    }
    function closeModal() { close() }

    function activateSelected() {
        var row = rows[Math.max(0, Math.min(rows.length - 1, selectedIndex))]
        if (row.section === "icon") {
            iconPickerOpen = true
            iconIndex = readIconIndex()
            statusText = "LEFT / RIGHT SELECTS • X SAVES"
            return
        }
        actionRequested("openClockSection", { section: row.section })
    }

    function saveIcon() {
        var backend = settingsBackend()
        var saved = false
        try {
            if (backend && typeof backend.setUiPreference === "function")
                saved = backend.setUiPreference("ui.dashboard.header.clockIcon", iconIndex) !== false
        } catch (error) { saved = false }
        statusText = saved ? "CLOCK ICON SAVED" : "CLOCK ICON COULD NOT BE SAVED"
        if (saved)
            actionRequested("clockIconChanged", { index: iconIndex, icon: clockIcons[iconIndex] })
    }

    function handleControllerPressed(action) {
        var a = String(action || "").toLowerCase()
        if (iconPickerOpen) {
            if (a === "left") iconIndex = (iconIndex + clockIcons.length - 1) % clockIcons.length
            else if (a === "right") iconIndex = (iconIndex + 1) % clockIcons.length
            else if (a === "primary" || a === "x" || a === "confirm") saveIcon()
            else if (a === "cancel" || a === "o" || a === "back") { iconPickerOpen = false; statusText = "CLOCK QUICK SETTINGS" }
            return true
        }
        if (a === "up") selectedIndex = Math.max(0, selectedIndex - 1)
        else if (a === "down") selectedIndex = Math.min(rows.length - 1, selectedIndex + 1)
        else if (a === "primary" || a === "x" || a === "confirm") activateSelected()
        else if (a === "cancel" || a === "o" || a === "back") close()
        return true
    }
    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return visible }

    Keys.onPressed: function(event) {
        var a = ""
        if (event.key === Qt.Key_Up) a = "up"
        else if (event.key === Qt.Key_Down) a = "down"
        else if (event.key === Qt.Key_Left) a = "left"
        else if (event.key === Qt.Key_Right) a = "right"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) a = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) a = "cancel"
        if (a.length) { handleControllerPressed(a); event.accepted = true }
    }

    Rectangle { anchors.fill: parent; color: "#D4020710" }

    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 108
        width: Math.min(parent.width - 120, 980)
        height: iconPickerOpen ? 500 : 610
        radius: 30
        color: panelColor
        border.width: 2
        border.color: electricBlue
        clip: true

        Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 28; color: "transparent"; border.width: 1; border.color: "#183D62" }

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            height: 116; color: "#091A30"
            Row {
                anchors.left: parent.left; anchors.leftMargin: 30; anchors.verticalCenter: parent.verticalCenter; spacing: 18
                Rectangle {
                    width: 58; height: 58; radius: 18; color: "#0D2948"; border.width: 2; border.color: electricBlue
                    Text { anchors.centerIn: parent; text: clockIcons[iconIndex]; color: electricBlue; font.pixelSize: 30; font.bold: true }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 5
                    Text { text: "CLOCK"; color: textWhite; font.pixelSize: 27; font.bold: true; font.letterSpacing: 1.1 }
                    Text { text: statusText; color: neutronCyan; font.pixelSize: 12; font.bold: true; font.letterSpacing: 0.8 }
                }
            }
        }

        Column {
            visible: !iconPickerOpen
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 140
            anchors.leftMargin: 28; anchors.rightMargin: 28; spacing: 12
            Repeater {
                model: rows
                Rectangle {
                    required property int index
                    required property var modelData
                    width: parent.width; height: 92; radius: 18
                    color: root.selectedIndex === index ? "#13365B" : panelRaised
                    border.width: root.selectedIndex === index ? 2 : 1
                    border.color: root.selectedIndex === index ? electricBlue : "#214566"
                    Rectangle { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; width: 48; height: 48; radius: 15; color: "#0A223B"; border.width: 1; border.color: root.selectedIndex===index?electricBlue:"#315A80"; Text { anchors.centerIn:parent; text:modelData.icon; color:root.selectedIndex===index?electricBlue:neutronCyan; font.pixelSize:modelData.icon==="Aa"?16:20; font.bold:true } }
                    Column { anchors.left: parent.left; anchors.leftMargin: 82; anchors.right: arrow.left; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Text { width:parent.width; text:modelData.title; color:textWhite; font.pixelSize:18; font.bold:true; font.letterSpacing:0.7 }
                        Text { width:parent.width; text:modelData.detail; color:mutedText; font.pixelSize:13; elide:Text.ElideRight }
                    }
                    Text { id:arrow; anchors.right:parent.right; anchors.rightMargin:22; anchors.verticalCenter:parent.verticalCenter; text:"›"; color:root.selectedIndex===index?electricBlue:"#6687A7"; font.pixelSize:30 }
                    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{ root.selectedIndex=index; root.activateSelected() } }
                }
            }
        }

        Column {
            visible: iconPickerOpen
            anchors.centerIn: parent
            width: parent.width - 100
            spacing: 28
            Text { width:parent.width; text:"CLOCK ICON"; color:textWhite; font.pixelSize:24; font.bold:true; horizontalAlignment:Text.AlignHCenter }
            Text { width:parent.width; text:"Choose one of five persistent header icons"; color:mutedText; font.pixelSize:14; horizontalAlignment:Text.AlignHCenter }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 18
                Repeater {
                    model: clockIcons
                    Rectangle {
                        required property int index
                        required property var modelData
                        width: 108; height: 108; radius: 24
                        color: root.iconIndex===index ? "#153C67" : panelInset
                        border.width: root.iconIndex===index ? 3 : 1
                        border.color: root.iconIndex===index ? electricBlue : "#294D6C"
                        Text { anchors.centerIn:parent; text:modelData; color:root.iconIndex===index?electricBlue:"#D6E8F7"; font.pixelSize:44; font.bold:true }
                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{ root.iconIndex=index; root.saveIcon() } }
                    }
                }
            }
            Text { width:parent.width; text:"LEFT / RIGHT  SELECT    X  SAVE    O  BACK"; color:neutronCyan; font.pixelSize:13; font.bold:true; horizontalAlignment:Text.AlignHCenter; font.letterSpacing:0.8 }
        }
    }
}
