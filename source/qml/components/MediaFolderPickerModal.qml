import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: picker
    anchors.fill: parent
    visible: open
    enabled: visible
    focus: visible
    z: 1000

    property bool open: false
    property var backend: null
    property string title: "Select Media Folder"
    property string currentPath: ""
    property int selectedIndex: 0
    property var entries: []
    property var suggestions: []
    signal accepted(string path)
    signal cancelled()

    function refresh() {
        if (!backend) { entries = []; return }
        entries = backend.directoryEntries(currentPath)
        selectedIndex = Math.max(0, Math.min(selectedIndex, entries.length))
        folderList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function openPicker(path) {
        if (!backend) return
        currentPath = String(path || backend.canonicalUserHome())
        selectedIndex = 0
        suggestions = backend.suggestedLibraryRoots()
        open = true
        refresh()
        forceActiveFocus()
    }

    function closePicker() { open = false; cancelled() }

    function activate() {
        if (selectedIndex === 0) {
            accepted(currentPath)
            open = false
            return
        }
        var item = entries[selectedIndex - 1]
        if (!item || !item.path) return
        currentPath = item.path
        selectedIndex = 0
        refresh()
    }

    function handleControllerPressed(action) {
        var a = String(action || "").toLowerCase()
        if (a === "x" || a === "cross" || a === "primary") a = "primary"
        if (a === "o" || a === "circle" || a === "cancel") a = "cancel"
        if (a === "square" || a === "secondary") a = "square"
        if (a === "triangle" || a === "context") a = "triangle"
        if (a === "cancel") { closePicker(); return true }
        if (a === "up") selectedIndex = Math.max(0, selectedIndex - 1)
        else if (a === "down") selectedIndex = Math.min(entries.length, selectedIndex + 1)
        else if (a === "left" || a === "triangle") {
            currentPath = backend.parentDirectory(currentPath)
            selectedIndex = 0
            refresh()
        } else if (a === "primary") activate()
        else if (a === "square" || a === "start") { accepted(currentPath); open = false }
        folderList.positionViewAtIndex(selectedIndex, ListView.Contain)
        return true
    }

    Rectangle { anchors.fill: parent; color: "#D9020610" }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 90, 980)
        height: Math.min(parent.height - 80, 720)
        radius: 30
        color: "#FA081729"
        border.width: 3
        border.color: "#73E6FF"

        Column {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 14
            Text { text: picker.title; color: "#F4FBFF"; font.pixelSize: 31; font.bold: true }
            Text { width: parent.width; text: picker.currentPath; color: "#73E6FF"; font.pixelSize: 15; elide: Text.ElideMiddle }
            Rectangle { width: parent.width; height: 1; color: "#28445F" }
            ListView {
                id: folderList
                width: parent.width
                height: parent.height - 150
                clip: true
                model: [{name: "Use This Folder", path: picker.currentPath, choose: true}].concat(picker.entries)
                spacing: 7
                delegate: Rectangle {
                    width: folderList.width
                    height: 58
                    radius: 15
                    color: picker.selectedIndex === index ? "#173F61" : "#0D2239"
                    border.width: picker.selectedIndex === index ? 2 : 1
                    border.color: picker.selectedIndex === index ? "#73E6FF" : "#28445F"
                    Row {
                        anchors.fill: parent; anchors.margins: 14; spacing: 14
                        Text { text: modelData.choose ? "✓" : "▣"; color: modelData.choose ? "#48E891" : "#B58AFF"; font.pixelSize: 22 }
                        Text { text: modelData.name; color: "#F4FBFF"; font.pixelSize: 17; font.bold: picker.selectedIndex === index; verticalAlignment: Text.AlignVCenter }
                        Item { width: 1; height: 1 }
                    }
                }
            }
            Text { text: "X Open / Choose   □ or START Use Folder   △ / ← Parent   O Cancel"; color: "#8AA8C3"; font.pixelSize: 13 }
        }
    }
}
