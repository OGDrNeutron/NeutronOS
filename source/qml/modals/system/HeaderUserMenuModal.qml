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
    property var activeUser: null
    property int selectedIndex: 0
    property int armedIndex: -1
    property string statusText: "PROFILE & SESSION"

    readonly property color panelColor: "#071426"
    readonly property color panelRaised: "#0B1A30"
    readonly property color electricBlue: "#00A8FF"
    readonly property color neutronCyan: "#7DF9FF"
    readonly property color dangerRed: "#FF3048"
    readonly property color textWhite: "#F4FBFF"
    readonly property color mutedText: "#8AA6C8"

    readonly property var rows: [
        { id: "displayName", title: "DISPLAY NAME", detail: "Change the name shown throughout NeutronOS", tone: electricBlue, icon: "U" },
        { id: "userIcon", title: "USER ICON", detail: "Choose the profile avatar used on Login and Dashboard", tone: electricBlue, icon: "◉" },
        { id: "restart", title: "RESTART", detail: "Restart neutronos.service without rebooting Linux", tone: "#F5C542", icon: "↻" },
        { id: "reboot", title: "REBOOT", detail: "Restart Linux and all NeutronOS services", tone: "#FF8A3D", icon: "⟳" },
        { id: "logout", title: "LOG OUT", detail: "Return to the NeutronOS login screen", tone: neutronCyan, icon: "↩" },
        { id: "poweroff", title: "POWER OFF", detail: "Safely shut down the system", tone: dangerRed, icon: "⏻" }
    ]

    signal closed()
    signal actionRequested(string action, var payload)

    Timer { id: armTimer; interval: 3200; repeat: false; onTriggered: root.armedIndex = -1 }

    function userMap() {
        if (activeUser) return activeUser
        try { if (contextData && contextData.user) return contextData.user } catch (e) {}
        return ({})
    }
    function userName() {
        var user = userMap()
        try { return String(user.displayName || user.username || "User") } catch (e) { return "User" }
    }
    function userRole() {
        var user = userMap()
        try {
            var value = String(user.role || user.accountRole || user.userRole || "").toLowerCase()
            return value.indexOf("admin") >= 0 ? "Admin" : "User"
        } catch (e) { return "User" }
    }

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        if (contextData && contextData.user) activeUser = contextData.user
        selectedIndex = 0
        armedIndex = -1
        statusText = "PROFILE & SESSION"
        visible = true
        forceActiveFocus()
    }
    function openModal(context) { open(context) }
    function close() { armTimer.stop(); armedIndex = -1; visible = false; closed() }
    function closeModal() { close() }

    function needsArm(id) {
        return id === "restart" || id === "reboot" || id === "logout" || id === "poweroff"
    }

    function activateSelected() {
        var row = rows[Math.max(0, Math.min(rows.length - 1, selectedIndex))]
        if (row.id === "displayName") { actionRequested("openUserSection", { section: "profile", user: userMap() }); return }
        if (row.id === "userIcon") { actionRequested("openUserSection", { section: "icon", user: userMap() }); return }

        if (needsArm(row.id) && armedIndex !== selectedIndex) {
            armedIndex = selectedIndex
            statusText = "PRESS X AGAIN TO CONFIRM " + row.title
            armTimer.restart()
            return
        }

        armedIndex = -1
        armTimer.stop()
        actionRequested(row.id, {})
    }

    function handleControllerPressed(action) {
        var a = String(action || "").toLowerCase()
        if (a === "up") { selectedIndex = Math.max(0, selectedIndex - 1); armedIndex = -1 }
        else if (a === "down") { selectedIndex = Math.min(rows.length - 1, selectedIndex + 1); armedIndex = -1 }
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
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) a = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) a = "cancel"
        if (a.length) { handleControllerPressed(a); event.accepted = true }
    }

    Rectangle { anchors.fill: parent; color: "#D4020710" }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 980)
        height: Math.min(parent.height - 100, 820)
        radius: 32
        color: panelColor
        border.width: 2
        border.color: electricBlue
        clip: true

        Rectangle { anchors.fill:parent;anchors.margins:2;radius:30;color:"transparent";border.width:1;border.color:"#173C60" }

        Rectangle {
            anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;height:126;color:"#091A30"
            Row {
                anchors.left:parent.left;anchors.leftMargin:30;anchors.verticalCenter:parent.verticalCenter;spacing:18
                Rectangle { width:62;height:62;radius:20;color:"#0D2948";border.width:2;border.color:electricBlue;Text{anchors.centerIn:parent;text:"U";color:electricBlue;font.pixelSize:28;font.bold:true} }
                Column { anchors.verticalCenter:parent.verticalCenter;spacing:5
                    Text { text:root.userName();color:textWhite;font.pixelSize:27;font.bold:true }
                    Text { text:root.userRole()+"  •  "+root.statusText;color:electricBlue;font.pixelSize:12;font.bold:true;font.letterSpacing:0.7 }
                }
            }
        }

        Column {
            anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.topMargin:150;anchors.leftMargin:28;anchors.rightMargin:28;spacing:10
            Repeater {
                model: rows
                Rectangle {
                    required property int index
                    required property var modelData
                    width:parent.width;height:88;radius:18
                    color:root.selectedIndex===index?"#14365B":panelRaised
                    border.width:root.selectedIndex===index?2:1
                    border.color:root.armedIndex===index?dangerRed:(root.selectedIndex===index?electricBlue:"#214566")
                    Rectangle { anchors.left:parent.left;anchors.leftMargin:16;anchors.verticalCenter:parent.verticalCenter;width:46;height:46;radius:14;color:"#0A223B";border.width:1;border.color:modelData.tone;Text{anchors.centerIn:parent;text:modelData.icon;color:modelData.tone;font.pixelSize:20;font.bold:true} }
                    Column { anchors.left:parent.left;anchors.leftMargin:78;anchors.right:stateText.left;anchors.rightMargin:14;anchors.verticalCenter:parent.verticalCenter;spacing:5
                        Text { width:parent.width;text:modelData.title;color:textWhite;font.pixelSize:18;font.bold:true;font.letterSpacing:0.7 }
                        Text { width:parent.width;text:modelData.detail;color:mutedText;font.pixelSize:13;elide:Text.ElideRight }
                    }
                    Text { id:stateText;anchors.right:parent.right;anchors.rightMargin:22;anchors.verticalCenter:parent.verticalCenter;text:root.armedIndex===index?"CONFIRM":"›";color:root.armedIndex===index?dangerRed:(root.selectedIndex===index?electricBlue:"#6687A7");font.pixelSize:root.armedIndex===index?12:30;font.bold:true }
                    MouseArea { anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{root.selectedIndex=index;root.activateSelected()} }
                }
            }
        }
    }
}
