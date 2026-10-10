import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: picker
    anchors.fill: parent
    visible: open
    enabled: visible
    focus: visible
    z: 1200

    property bool open: false
    property var backend: null
    property string title: "Choose SRT Subtitle"
    property string currentPath: ""
    property var extensions: ["srt"]
    property var entries: []
    property int selectedIndex: 0
    signal accepted(string path)
    signal cancelled()

    function refresh() {
        entries = backend && typeof backend.mediaPickerEntries === "function"
                ? backend.mediaPickerEntries(currentPath, extensions) : []
        selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, entries.length - 1)))
        list.positionViewAtIndex(selectedIndex, ListView.Contain)
    }
    function openPicker(path) {
        currentPath = String(path || (backend ? backend.canonicalUserHome() : "/"))
        selectedIndex = 0
        open = true
        refresh()
        forceActiveFocus()
    }
    function closePicker() { open = false; cancelled() }
    function activate() {
        var item = entries[selectedIndex]
        if (!item) return
        if (item.directory) {
            currentPath = item.path
            selectedIndex = 0
            refresh()
        } else {
            open = false
            accepted(item.path)
        }
    }
    function handleControllerPressed(action) {
        var a = String(action || "").toLowerCase()
        if (a === "x" || a === "cross") a = "primary"
        if (a === "o" || a === "circle") a = "cancel"
        if (a === "triangle" || a === "context") a = "triangle"
        if (a === "cancel") { closePicker(); return true }
        if (a === "up") selectedIndex = Math.max(0, selectedIndex - 1)
        else if (a === "down") selectedIndex = Math.min(Math.max(0, entries.length - 1), selectedIndex + 1)
        else if (a === "left" || a === "triangle") {
            currentPath = backend ? backend.parentDirectory(currentPath) : currentPath
            selectedIndex = 0
            refresh()
        } else if (a === "primary") activate()
        list.positionViewAtIndex(selectedIndex, ListView.Contain)
        return true
    }

    Rectangle { anchors.fill: parent; color: "#E0020610" }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 90, 1040)
        height: Math.min(parent.height - 80, 760)
        radius: 32
        color: "#FC081729"
        border.width: 3
        border.color: "#73E6FF"
        Column {
            anchors.fill: parent; anchors.margins: 28; spacing: 14
            Text { text: picker.title; color: "#F4FBFF"; font.pixelSize: 31; font.bold: true }
            Text { width: parent.width; text: picker.currentPath; color: "#73E6FF"; font.pixelSize: 15; elide: Text.ElideMiddle }
            Rectangle { width: parent.width; height: 1; color: "#28445F" }
            ListView {
                id: list
                width: parent.width; height: parent.height - 148; clip: true; spacing: 7
                model: picker.entries
                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width: list.width; height: 60; radius: 15
                    color: picker.selectedIndex === index ? "#173F61" : "#0D2239"
                    border.width: picker.selectedIndex === index ? 2 : 1
                    border.color: picker.selectedIndex === index ? "#73E6FF" : "#28445F"
                    Row {
                        anchors.fill: parent; anchors.margins: 14; spacing: 14
                        Text { text: modelData.directory ? "▣" : "≡"; color: modelData.directory ? "#B58AFF" : "#48E891"; font.pixelSize: 22 }
                        Text { width: parent.width - 50; text: modelData.name; color: "#F4FBFF"; font.pixelSize: 17; font.bold: picker.selectedIndex === index; elide: Text.ElideMiddle }
                    }
                }
                Text { anchors.centerIn: parent; visible: list.count === 0; text: "No matching files in this folder"; color: "#8AA8C3"; font.pixelSize: 18 }
            }
            Text { text: "X Open / Select   △ / ← Parent   O Cancel"; color: "#8AA8C3"; font.pixelSize: 13 }
        }
    }
}
