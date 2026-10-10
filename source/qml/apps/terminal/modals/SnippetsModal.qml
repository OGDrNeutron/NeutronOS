import QtQuick 2.15
import QtQuick.Controls 2.15

import "../components"

Item {
    id: root

    anchors.fill: parent
    visible: false
    focus: visible
    z: 1200

    property var snippets: []
    property int categoryIndex: 0
    property int snippetIndex: 0
    property int pane: 0
    property string armedDeleteId: ""

    readonly property var categories: buildCategories()
    readonly property var visibleSnippets: snippetsForCategory(currentCategory())

    signal closeRequested()
    signal insertRequested(string snippetId)
    signal addRequested()
    signal editRequested(var snippetData)
    signal removeRequested(string snippetId)
    signal moveRequested(string snippetId, int offset)

    function buildCategories() {
        var output = ["ALL"]
        var seen = ({ "ALL": true })
        var source = snippets || []
        for (var i = 0; i < source.length; ++i) {
            var category = String(source[i].category || "Custom").toUpperCase()
            if (!seen[category]) {
                seen[category] = true
                output.push(category)
            }
        }
        return output
    }

    function currentCategory() {
        if (categories.length <= 0)
            return "ALL"
        var index = Math.max(0, Math.min(categories.length - 1, categoryIndex))
        return categories[index]
    }

    function snippetsForCategory(category) {
        var output = []
        var source = snippets || []
        for (var i = 0; i < source.length; ++i) {
            if (category === "ALL" || String(source[i].category || "Custom").toUpperCase() === category)
                output.push(source[i])
        }
        return output
    }

    function selectedSnippet() {
        if (visibleSnippets.length <= 0)
            return null
        var index = Math.max(0, Math.min(visibleSnippets.length - 1, snippetIndex))
        return visibleSnippets[index]
    }

    function open() {
        visible = true
        pane = 0
        categoryIndex = 0
        snippetIndex = 0
        armedDeleteId = ""
        forceActiveFocus()
    }

    function close() {
        visible = false
        armedDeleteId = ""
        closeRequested()
    }

    function moveUp() {
        armedDeleteId = ""
        if (pane === 0)
            categoryIndex = Math.max(0, categoryIndex - 1)
        else
            snippetIndex = Math.max(0, snippetIndex - 1)
    }

    function moveDown() {
        armedDeleteId = ""
        if (pane === 0)
            categoryIndex = Math.min(categories.length - 1, categoryIndex + 1)
        else
            snippetIndex = Math.min(Math.max(0, visibleSnippets.length - 1), snippetIndex + 1)
    }

    function activate() {
        armedDeleteId = ""
        if (pane === 0) {
            pane = 1
            snippetIndex = 0
            return
        }
        var item = selectedSnippet()
        if (item)
            insertRequested(String(item.id || ""))
    }

    function requestEdit() {
        var item = selectedSnippet()
        if (pane === 1 && item)
            editRequested(item)
    }

    function requestDelete() {
        var item = selectedSnippet()
        if (pane !== 1 || !item)
            return
        var id = String(item.id || "")
        if (armedDeleteId === id) {
            armedDeleteId = ""
            removeRequested(id)
        } else {
            armedDeleteId = id
            deleteArmTimer.restart()
        }
    }

    function moveSelected(offset) {
        var item = selectedSnippet()
        if (pane === 1 && item)
            moveRequested(String(item.id || ""), offset)
    }

    function normalizeAction(button) {
        var b = String(button || "").toLowerCase().replace(/\s+/g, "_").replace(/-/g, "_")
        if (b === "primary" || b === "x" || b === "cross" || b === "a") return "primary"
        if (b === "cancel" || b === "o" || b === "circle" || b === "b") return "cancel"
        if (b === "secondary" || b === "square" || b === "xbox_x") return "secondary"
        if (b === "context" || b === "triangle" || b === "y") return "context"
        if (b === "system" || b === "start" || b === "options" || b === "menu") return "system"
        if (b === "dpad_up") return "up"
        if (b === "dpad_down") return "down"
        if (b === "dpad_left") return "left"
        if (b === "dpad_right") return "right"
        if (b === "lb") return "l1"
        if (b === "rb") return "r1"
        return b
    }

    function handleControllerPressed(button) {
        if (!visible)
            return false
        var action = normalizeAction(button)
        if (action === "up") { moveUp(); return true }
        if (action === "down") { moveDown(); return true }
        if (action === "left") { pane = 0; armedDeleteId = ""; return true }
        if (action === "right") { pane = 1; snippetIndex = 0; armedDeleteId = ""; return true }
        if (action === "primary") { activate(); return true }
        if (action === "secondary") { addRequested(); return true }
        if (action === "context") { requestEdit(); return true }
        if (action === "system") { requestDelete(); return true }
        if (action === "l1") { moveSelected(-1); return true }
        if (action === "r1") { moveSelected(1); return true }
        if (action === "cancel") {
            if (pane === 1) pane = 0
            else close()
            return true
        }
        return true
    }

    function handleControllerReleased(button) { return visible }

    Timer {
        id: deleteArmTimer
        interval: 5000
        repeat: false
        onTriggered: root.armedDeleteId = ""
    }

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.72 }

    TerminalGlassPanel {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1620)
        height: Math.min(parent.height - 100, 920)
        radius: 38
        padding: 28
        strong: true
        focused: true

        Column {
            anchors.fill: parent
            spacing: 20

            Row {
                width: parent.width
                height: 74
                spacing: 20

                Column {
                    width: parent.width - 410
                    spacing: 5
                    Text { text: "SNIPPETS"; color: "#F3FCFF"; font.pixelSize: 34; font.bold: true; font.letterSpacing: 2.5 }
                    Text { text: "Reusable commands and code shared with the phone terminal"; color: "#77A9C8"; font.pixelSize: 15 }
                }

                Text {
                    width: 390
                    text: "X INSERT  •  □ ADD  •  △ EDIT\nOPTIONS DELETE  •  L1/R1 REORDER"
                    color: "#9FD8FF"
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 13
                    font.bold: true
                    lineHeight: 1.25
                }
            }

            Row {
                width: parent.width
                height: parent.height - 112
                spacing: 18

                TerminalGlassPanel {
                    width: 310
                    height: parent.height
                    radius: 28
                    padding: 14
                    focused: root.pane === 0
                    strong: root.pane === 0

                    ListView {
                        id: categoryList
                        anchors.fill: parent
                        spacing: 10
                        clip: true
                        model: root.categories
                        currentIndex: root.categoryIndex

                        delegate: Rectangle {
                            width: categoryList.width
                            height: 72
                            radius: 18
                            color: index === root.categoryIndex ? "#143B63" : "#08182ACC"
                            border.width: root.pane === 0 && index === root.categoryIndex ? 3 : 1
                            border.color: root.pane === 0 && index === root.categoryIndex ? "#68D8FF" : "#294B68"

                            Text {
                                anchors.fill: parent
                                anchors.margins: 16
                                text: String(modelData)
                                color: index === root.categoryIndex ? "#FFFFFF" : "#B9EEFF"
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 18
                                font.bold: true
                                font.letterSpacing: 1.2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                TerminalGlassPanel {
                    width: parent.width - 328
                    height: parent.height
                    radius: 28
                    padding: 16
                    focused: root.pane === 1
                    strong: root.pane === 1

                    ListView {
                        id: snippetList
                        anchors.fill: parent
                        spacing: 12
                        clip: true
                        model: root.visibleSnippets
                        currentIndex: root.snippetIndex

                        delegate: Rectangle {
                            width: snippetList.width
                            height: 116
                            radius: 22
                            color: root.armedDeleteId === String(modelData.id || "")
                                   ? "#5E101B"
                                   : (index === root.snippetIndex ? "#12395F" : "#071727DD")
                            border.width: root.pane === 1 && index === root.snippetIndex ? 3 : 1
                            border.color: root.armedDeleteId === String(modelData.id || "")
                                          ? "#FF3048"
                                          : (root.pane === 1 && index === root.snippetIndex ? "#68D8FF" : "#274A68")

                            Row {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 18

                                Column {
                                    width: parent.width - 170
                                    spacing: 8
                                    Text { width: parent.width; text: String(modelData.label || "Snippet"); color: "#F3FCFF"; font.pixelSize: 21; font.bold: true; elide: Text.ElideRight }
                                    Text { width: parent.width; text: String(modelData.command || ""); color: "#9FD8FF"; font.family: "monospace"; font.pixelSize: 14; elide: Text.ElideRight }
                                }

                                Column {
                                    width: 150
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Text { width: parent.width; text: String(modelData.category || "Custom").toUpperCase(); color: "#77A9C8"; horizontalAlignment: Text.AlignRight; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.2 }
                                    Text { width: parent.width; text: root.armedDeleteId === String(modelData.id || "") ? "PRESS OPTIONS AGAIN" : "X INSERT"; color: root.armedDeleteId === String(modelData.id || "") ? "#FF7185" : "#27FF9A"; horizontalAlignment: Text.AlignRight; font.pixelSize: 12; font.bold: true }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.visibleSnippets.length === 0
                            text: "No snippets in this category\nPress □ to add one"
                            color: "#77A9C8"
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 20
                            lineHeight: 1.35
                        }
                    }
                }
            }
        }
    }

    Keys.onPressed: function(event) {
        if (!visible) return
        if (event.key === Qt.Key_Up) { handleControllerPressed("up"); event.accepted = true; return }
        if (event.key === Qt.Key_Down) { handleControllerPressed("down"); event.accepted = true; return }
        if (event.key === Qt.Key_Left) { handleControllerPressed("left"); event.accepted = true; return }
        if (event.key === Qt.Key_Right) { handleControllerPressed("right"); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { handleControllerPressed("primary"); event.accepted = true; return }
        if (event.key === Qt.Key_Escape) { handleControllerPressed("cancel"); event.accepted = true; return }
    }
}
