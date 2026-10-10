import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var backend: null
    property bool opened: false
    property int selectedIndex: 0
    property int actionIndex: 0
    property bool actionsOpen: false
    property bool makeTabConfirm: false
    readonly property var entries: backend && backend.runningApps ? backend.runningApps : []
    signal closed()
    signal makeAppTabRequested(var runtime)

    anchors.fill: parent
    visible: opened || closeTimer.running
    enabled: opened
    z: 160

    function openTray() {
        selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, entries.length - 1)))
        actionIndex = 0
        actionsOpen = false
        makeTabConfirm = false
        opened = true
        forceActiveFocus()
    }
    function closeTray() {
        if (!opened) return
        opened = false
        closeTimer.restart()
    }
    function selectedEntry() {
        return selectedIndex >= 0 && selectedIndex < entries.length ? entries[selectedIndex] : null
    }
    function normalizeActionForEntry() {
        var entry = selectedEntry()
        if (!entry) { actionIndex = 0; return }
        if (actionIndex === 0 && entry.canFocus !== true && entry.canClose === true) actionIndex = 1
        if (actionIndex === 1 && entry.canClose !== true && entry.canFocus === true) actionIndex = 0
    }
    function activateAction() {
        var entry = selectedEntry()
        if (!entry || !backend) return
        if (actionIndex === 0 && entry.canFocus === true && typeof backend.focusRuntime === "function") {
            var accepted = backend.focusRuntime(String(entry.runtimeId || "")) === true
            if (accepted) closeTray()
        } else if (actionIndex === 1 && entry.canClose === true && typeof backend.closeRuntime === "function") {
            backend.closeRuntime(String(entry.runtimeId || ""))
        }
    }
    function handleControllerPressed(action) {
        if (!opened) return false
        if (actionsOpen) {
            if (action === "cancel") { actionsOpen=false;makeTabConfirm=false;return true }
            if (action === "up") actionIndex=Math.max(0,actionIndex-1)
            else if (action === "down") actionIndex=Math.min(2,actionIndex+1)
            else if (action === "primary") {
                var entry=selectedEntry(); if(!entry)return true
                if(actionIndex===0&&entry.canFocus===true&&backend&&backend.focusRuntime){backend.focusRuntime(String(entry.runtimeId||""));closeTray()}
                else if(actionIndex===1&&entry.canClose===true&&backend&&backend.closeRuntime)backend.closeRuntime(String(entry.runtimeId||""))
                else if(actionIndex===2){if(!makeTabConfirm)makeTabConfirm=true;else{makeAppTabRequested(entry);makeTabConfirm=false;actionsOpen=false}}
            }
            return true
        }
        if (action === "cancel" || action === "home") { closeTray(); return true }
        if (action === "up") { selectedIndex = Math.max(0, selectedIndex - 1); actionIndex = 0; list.positionViewAtIndex(selectedIndex, ListView.Contain); normalizeActionForEntry(); return true }
        if (action === "down") { selectedIndex = Math.min(Math.max(0, entries.length - 1), selectedIndex + 1); actionIndex = 0; list.positionViewAtIndex(selectedIndex, ListView.Contain); normalizeActionForEntry(); return true }
        if (action === "left") { actionIndex = 0; normalizeActionForEntry(); return true }
        if (action === "secondary") { actionsOpen=true;actionIndex=0;makeTabConfirm=false;return true }
        if (action === "right" || action === "context") { actionIndex = 1; normalizeActionForEntry(); return true }
        if (action === "primary") { activateAction(); return true }
        return true
    }

    Rectangle {
        visible: root.actionsOpen
        anchors.centerIn: parent
        width: Math.min(720,parent.width*.60); height: 390; radius: 28
        color:"#FA071426"; border.width:3; border.color:root.makeTabConfirm?"#FFB13B":"#35DFFF"; z:20
        Column { anchors.fill:parent;anchors.margins:28;spacing:14
            Text { text:root.makeTabConfirm?"ADD THIS RUNNING APPLICATION AS A DASHBOARD TAB?":"RUNNING APP ACTIONS";color:"white";font.pixelSize:24;font.bold:true }
            Text { text:root.makeTabConfirm?"X YES   •   O NO":String(root.selectedEntry()?root.selectedEntry().displayName||root.selectedEntry().appId:"Application");color:root.makeTabConfirm?"#FFCA68":"#AFC5DB";font.pixelSize:16 }
            Repeater { model:["Focus Existing Session","Close","Make App a Tab"]
                delegate:Rectangle { required property int index;required property string modelData;width:parent.width;height:64;radius:15;color:root.actionIndex===index?"#183F5F":"#0B1B2B";border.width:root.actionIndex===index?3:1;border.color:index===2?"#C65DFF":root.actionIndex===index?"#35DFFF":"#2C4963";Text{anchors.centerIn:parent;text:modelData.toUpperCase();color:"white";font.pixelSize:16;font.bold:true} }
            }
        }
    }

    Timer { id: closeTimer; interval: 180; onTriggered: root.closed() }
    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onRunningAppsChanged() {
            root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, Math.max(0, root.entries.length - 1)))
            root.normalizeActionForEntry()
        }
    }

    MouseArea { anchors.fill: parent; onClicked: root.closeTray() }

    Rectangle {
        id: panel
        width: Math.min(540, root.width * .34)
        height: Math.min(root.height * .61, Math.max(180, 106 + root.entries.length * 84))
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.height * .115 + 12
        radius: 18
        color: "#F0070D1B"
        border.width: 1
        border.color: "#895D5CFF"
        opacity: root.opened ? 1 : 0
        scale: root.opened ? 1 : .96
        transformOrigin: Item.BottomRight
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        Row {
            id: heading
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 18; height: 46
            Text { width: parent.width - countPill.width; text: "Running Apps"; color: "#F7FAFF"; font.pixelSize: 22; font.weight: Font.Medium }
            Rectangle { id: countPill; width: 54; height: 30; radius: 15; color: "#171A38"; border.width: 1; border.color: "#19E9FF"
                Text { anchors.centerIn: parent; text: root.entries.length; color: "#19E9FF"; font.pixelSize: 14; font.bold: true }
            }
        }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: heading.bottom; anchors.leftMargin: 18; anchors.rightMargin: 18; height: 1; color: "#263853" }

        Text {
            visible: root.entries.length === 0
            anchors.centerIn: parent
            text: "No active apps"
            color: "#9EB0C7"
            font.pixelSize: 17
        }

        ListView {
            id: list
            visible: root.entries.length > 0
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: heading.bottom; anchors.bottom: parent.bottom
            anchors.margins: 14; anchors.topMargin: 14
            model: root.entries
            currentIndex: root.selectedIndex
            spacing: 8
            clip: true

            delegate: Rectangle {
                required property int index
                required property var modelData
                width: list.width
                height: 76
                radius: 13
                color: root.selectedIndex === index ? "#D0131C35" : "#A0091120"
                border.width: root.selectedIndex === index ? 2 : 1
                border.color: root.selectedIndex === index ? "#19E9FF" : "#30425B"
                x: modelData.isBrowserTab === true ? 20 : 0

                Row {
                    anchors.fill: parent; anchors.margins: 10; spacing: 10
                    Rectangle {
                        width: 48; height: 48; radius: 10; color: "#0B1425"; border.width: 1; border.color: modelData.isBrowserTab === true ? "#7B19FF" : "#315071"
                        readonly property string artwork: String(modelData.icon || modelData.poster || "")
                        readonly property bool hasArtwork: artwork.indexOf("/") >= 0 || artwork.indexOf(":") >= 0
                        Image { anchors.fill: parent; anchors.margins: 6; visible: parent.hasArtwork; source: parent.hasArtwork ? parent.artwork : ""; fillMode: Image.PreserveAspectFit; asynchronous: true; cache: true }
                        Text { visible: !parent.hasArtwork; anchors.centerIn: parent; text: modelData.isBrowserTab === true ? "▱" : "▦"; color: "#19E9FF"; font.pixelSize: 22 }
                    }
                    Column {
                        width: parent.width - 190; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                        Text { width: parent.width; text: String(modelData.displayName || modelData.appId || "Application"); color: "white"; font.pixelSize: 15; font.weight: Font.Medium; elide: Text.ElideRight }
                        Text { width: parent.width; text: String(modelData.subtitle || modelData.state || "active"); color: modelData.active === true ? "#20F58B" : "#A8B5CA"; font.pixelSize: 11; elide: Text.ElideRight }
                    }
                    Row { anchors.verticalCenter: parent.verticalCenter; spacing: 7
                        Rectangle { visible: modelData.canFocus === true; width: 42; height: 38; radius: 9; color: root.selectedIndex === index && root.actionIndex === 0 ? "#243F62" : "#101929"; border.width: 1; border.color: root.selectedIndex === index && root.actionIndex === 0 ? "#19E9FF" : "#344860"; Text { anchors.centerIn: parent; text: "↗"; color: "#19E9FF"; font.pixelSize: 18 }
                            MouseArea { anchors.fill: parent; onClicked: { root.selectedIndex=index; root.actionIndex=0; root.activateAction() } }
                        }
                        Rectangle { visible: modelData.canClose === true; width: 42; height: 38; radius: 9; color: root.selectedIndex === index && root.actionIndex === 1 ? "#4A1930" : "#101929"; border.width: 1; border.color: root.selectedIndex === index && root.actionIndex === 1 ? "#FF4382" : "#344860"; Text { anchors.centerIn: parent; text: "×"; color: "#FF4382"; font.pixelSize: 20 }
                            MouseArea { anchors.fill: parent; onClicked: { root.selectedIndex=index; root.actionIndex=1; root.activateAction() } }
                        }
                    }
                }
                MouseArea { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: parent.width - 100; onClicked: { root.selectedIndex=index; root.actionIndex=0 } }
            }
        }
    }
}
