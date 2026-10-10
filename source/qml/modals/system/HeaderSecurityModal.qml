import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components"

Item {
    id: root
    anchors.fill: parent
    visible: true
    enabled: visible
    focus: visible
    z: 30000

    property var contextData: ({})
    property var modalContext: ({})
    property var securityBackend: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null
    property int tabIndex: 0
    property int selectedIndex: 0
    property int focusZone: 0    // 0 tabs, 1 list, 2 footer
    property int footerIndex: 0
    property bool integrityArmed: false
    property string statusText: "LIVE SECURITY REVIEW"

    readonly property color panelColor: "#071426"
    readonly property color panelRaised: "#0B1A30"
    readonly property color panelInset: "#06101F"
    readonly property color electricBlue: "#00A8FF"
    readonly property color neutronCyan: "#7DF9FF"
    readonly property color successGreen: "#22FF88"
    readonly property color dangerRed: "#FF3048"
    readonly property color warningGold: "#F5C542"
    readonly property color textWhite: "#F4FBFF"
    readonly property color mutedText: "#8AA6C8"

    signal closed()
    signal actionRequested(string action, var payload)

    Timer { id: armTimer; interval: 3800; repeat: false; onTriggered: root.integrityArmed = false }
    Timer {
        id: refreshTimer
        interval: 900
        repeat: false
        onTriggered: {
            try { if (root.securityBackend && typeof root.securityBackend.refresh === "function") root.securityBackend.refresh() } catch (e) {}
        }
    }

    function integrityItems() {
        try { return securityBackend && securityBackend.integrityChanges ? securityBackend.integrityChanges : [] }
        catch (e) { return [] }
    }

    function notificationItems() {
        var source = []
        var out = []
        try { source = securityBackend && securityBackend.events ? securityBackend.events : [] } catch (e) { source = [] }
        for (var i = 0; i < source.length; ++i) {
            var event = source[i] || ({})
            if (event.acknowledged !== true)
                out.push(event)
        }
        return out
    }

    function currentItems() { return tabIndex === 0 ? integrityItems() : notificationItems() }
    function rowTitle(item) {
        if (!item) return "Security item"
        if (tabIndex === 0)
            return String(item.path || item.file || item.name || item.component || "Integrity change")
        return String(item.title || item.eventType || item.type || "Security notification")
    }
    function rowDetail(item) {
        if (!item) return ""
        if (tabIndex === 0)
            return String(item.reason || item.status || item.change || item.detail || "Protected content differs from the trusted baseline")
        return String(item.message || item.description || item.reason || item.detail || "Review this event in Security")
    }
    function rowTone(item) {
        if (tabIndex === 0) return warningGold
        var text = String(item && (item.severityLabel || item.severity || item.status) || "").toLowerCase()
        if (text.indexOf("critical") >= 0 || text.indexOf("high") >= 0 || text.indexOf("severe") >= 0) return dangerRed
        if (text.indexOf("warning") >= 0 || text.indexOf("medium") >= 0) return warningGold
        return neutronCyan
    }

    function clampSelection() {
        var count = currentItems().length
        selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, count - 1)))
        if (securityList && count > 0)
            securityList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function selectTab(index) {
        tabIndex = Math.max(0, Math.min(1, index))
        selectedIndex = 0
        integrityArmed = false
        statusText = tabIndex === 0 ? "TRUSTED BASELINE REVIEW" : "SECURITY NOTIFICATIONS"
        clampSelection()
    }

    function open(context) {
        contextData = context || ({})
        modalContext = contextData
        tabIndex = 0
        selectedIndex = 0
        focusZone = 0
        footerIndex = 0
        integrityArmed = false
        statusText = "LIVE SECURITY REVIEW"
        visible = true
        try { if (securityBackend && typeof securityBackend.refresh === "function") securityBackend.refresh() } catch (e) {}
        forceActiveFocus()
    }
    function openModal(context) { open(context) }
    function close() { armTimer.stop(); visible = false; integrityArmed = false; closed() }
    function closeModal() { close() }

    function acknowledgeSelected() {
        var items = notificationItems()
        if (selectedIndex < 0 || selectedIndex >= items.length || !securityBackend) return
        var item = items[selectedIndex] || ({})
        var id = String(item.id || "")
        if (!id.length) { statusText = "SELECTED EVENT HAS NO EVENT ID"; return }
        try {
            if (typeof securityBackend.acknowledgeEvent === "function") {
                securityBackend.acknowledgeEvent(id)
                statusText = "NOTIFICATION ACKNOWLEDGED"
                refreshTimer.restart()
            }
        } catch (e) { statusText = "NOTIFICATION COULD NOT BE CLEARED" }
    }

    function clearAllNotifications() {
        if (!securityBackend) return
        try {
            if (typeof securityBackend.acknowledgeAllEvents === "function") {
                securityBackend.acknowledgeAllEvents()
                statusText = "SECURITY NOTIFICATIONS ACKNOWLEDGED"
                selectedIndex = 0
                refreshTimer.restart()
            }
        } catch (e) { statusText = "NOTIFICATIONS COULD NOT BE CLEARED" }
    }

    function approveIntegrityBaseline() {
        if (!securityBackend || integrityItems().length <= 0) {
            statusText = "INTEGRITY BASELINE IS ALREADY CLEAN"
            return
        }
        if (!integrityArmed) {
            integrityArmed = true
            statusText = "PRESS X AGAIN TO APPROVE CURRENT FILESYSTEM STATE"
            armTimer.restart()
            return
        }
        integrityArmed = false
        armTimer.stop()
        try {
            if (typeof securityBackend.createIntegrityBaseline === "function") {
                securityBackend.createIntegrityBaseline()
                statusText = "REBUILDING TRUSTED INTEGRITY BASELINE"
                selectedIndex = 0
                refreshTimer.restart()
            } else statusText = "INTEGRITY BASELINE ACTION IS UNAVAILABLE"
        } catch (e) { statusText = "INTEGRITY BASELINE COULD NOT BE REBUILT" }
    }

    function footerAction() {
        if (footerIndex === 1) { close(); return }
        if (tabIndex === 0) approveIntegrityBaseline()
        else clearAllNotifications()
    }

    function handleControllerPressed(action) {
        var a = String(action || "").toLowerCase()
        var count = currentItems().length
        if (a === "cancel" || a === "o" || a === "back") { close(); return true }

        if (focusZone === 0) {
            if (a === "left") selectTab(0)
            else if (a === "right") selectTab(1)
            else if (a === "down") focusZone = count > 0 ? 1 : 2
            else if (a === "primary" || a === "x") focusZone = count > 0 ? 1 : 2
            return true
        }
        if (focusZone === 1) {
            if (a === "up") {
                if (selectedIndex <= 0) focusZone = 0
                else { selectedIndex--; clampSelection() }
            } else if (a === "down") {
                if (selectedIndex >= count - 1) focusZone = 2
                else { selectedIndex++; clampSelection() }
            } else if ((a === "primary" || a === "x") && tabIndex === 1) acknowledgeSelected()
            else if (a === "left" || a === "right") { selectTab(a === "left" ? 0 : 1); focusZone = 0 }
            return true
        }
        if (focusZone === 2) {
            if (a === "left") footerIndex = 0
            else if (a === "right") footerIndex = 1
            else if (a === "up") focusZone = count > 0 ? 1 : 0
            else if (a === "primary" || a === "x") footerAction()
            return true
        }
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
        anchors.centerIn: parent
        width: Math.min(parent.width - 100, 1460)
        height: Math.min(parent.height - 70, 920)
        radius: 34
        color: panelColor
        border.width: 2
        border.color: electricBlue
        clip: true

        Rectangle { anchors.fill:parent;anchors.margins:2;radius:32;color:"transparent";border.width:1;border.color:"#173C60" }

        Rectangle {
            anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;height:220;color:"#091A30"
            SecurityScorePresentation {
                anchors.top:parent.top
                anchors.topMargin:18
                anchors.horizontalCenter:parent.horizontalCenter
                width:Math.min(560,parent.width-96)
                height:58
                backend:root.securityBackend
                labelPixelSize:26
                barHeight:10
            }
            Row {
                anchors.left:parent.left;anchors.leftMargin:32;anchors.bottom:parent.bottom;anchors.bottomMargin:24;spacing:18
                Rectangle { width:64;height:64;radius:20;color:"#0D2948";border.width:2;border.color:securityBackend&&securityBackend.auditValid?successGreen:dangerRed; Text{anchors.centerIn:parent;text:"◆";color:securityBackend&&securityBackend.auditValid?successGreen:dangerRed;font.pixelSize:27;font.bold:true} }
                Column { anchors.verticalCenter:parent.verticalCenter;spacing:5
                    Text { text:"SECURITY CONTROL";color:textWhite;font.pixelSize:28;font.bold:true;font.letterSpacing:1.1 }
                    Text { text:statusText;color:neutronCyan;font.pixelSize:12;font.bold:true;font.letterSpacing:0.8 }
                }
            }
            Row {
                anchors.right:parent.right;anchors.rightMargin:28;anchors.bottom:parent.bottom;anchors.bottomMargin:24;spacing:12
                Repeater {
                    model:[{title:"INTEGRITY",count:root.integrityItems().length},{title:"NOTIFICATIONS",count:root.notificationItems().length}]
                    Rectangle {
                        required property int index; required property var modelData
                        width:190;height:64;radius:18;color:root.tabIndex===index?"#14365B":"#0A182A";border.width:root.focusZone===0&&root.tabIndex===index?2:1;border.color:root.tabIndex===index?electricBlue:"#25496A"
                        Column{anchors.centerIn:parent;spacing:2;Text{text:modelData.title;color:textWhite;font.pixelSize:13;font.bold:true;horizontalAlignment:Text.AlignHCenter;width:180}Text{text:String(modelData.count);color:modelData.count>0?(index===0?warningGold:dangerRed):successGreen;font.pixelSize:16;font.bold:true;horizontalAlignment:Text.AlignHCenter;width:180}}
                        MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{root.selectTab(index);root.focusZone=0}}
                    }
                }
            }
        }

        ListView {
            id: securityList
            anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.topMargin:246;anchors.bottom:footer.top;anchors.leftMargin:28;anchors.rightMargin:28;anchors.bottomMargin:18
            clip:true;spacing:10;model:root.currentItems();currentIndex:root.selectedIndex
            delegate: Rectangle {
                required property int index; required property var modelData
                width:securityList.width;height:92;radius:18
                color:root.focusZone===1&&root.selectedIndex===index?"#14365B":panelRaised
                border.width:root.focusZone===1&&root.selectedIndex===index?2:1
                border.color:root.focusZone===1&&root.selectedIndex===index?electricBlue:"#214566"
                Rectangle{anchors.left:parent.left;anchors.leftMargin:16;anchors.verticalCenter:parent.verticalCenter;width:7;height:58;radius:4;color:root.rowTone(modelData)}
                Column{anchors.left:parent.left;anchors.leftMargin:38;anchors.right:state.left;anchors.rightMargin:18;anchors.verticalCenter:parent.verticalCenter;spacing:6
                    Text{width:parent.width;text:root.rowTitle(modelData);color:textWhite;font.pixelSize:18;font.bold:true;elide:Text.ElideMiddle}
                    Text{width:parent.width;text:root.rowDetail(modelData);color:mutedText;font.pixelSize:13;elide:Text.ElideRight}
                }
                Text{id:state;anchors.right:parent.right;anchors.rightMargin:22;anchors.verticalCenter:parent.verticalCenter;text:root.tabIndex===1?"X  ACK":"REVIEW";color:root.rowTone(modelData);font.pixelSize:12;font.bold:true}
                MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{root.selectedIndex=index;root.focusZone=1;if(root.tabIndex===1)root.acknowledgeSelected()}}
            }
            Text { anchors.centerIn:parent;visible:securityList.count===0;text:root.tabIndex===0?"No integrity changes":"No pending security notifications";color:successGreen;font.pixelSize:22;font.bold:true }
        }

        Rectangle {
            id: footer
            anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:110;color:"#08182A";border.width:1;border.color:"#173A5A"
            Row {
                anchors.centerIn:parent;spacing:18
                Rectangle {
                    width:450;height:66;radius:18;color:root.focusZone===2&&root.footerIndex===0?"#153D64":"#0B2137";border.width:root.focusZone===2&&root.footerIndex===0?2:1;border.color:root.integrityArmed?dangerRed:(root.focusZone===2&&root.footerIndex===0?electricBlue:"#315A80")
                    Text{anchors.centerIn:parent;text:root.tabIndex===0?(root.integrityArmed?"X  APPROVE BASELINE":"APPROVE & CLEAR INTEGRITY"):"ACKNOWLEDGE ALL NOTIFICATIONS";color:root.integrityArmed?dangerRed:(root.tabIndex===0?warningGold:neutronCyan);font.pixelSize:15;font.bold:true}
                    MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{root.focusZone=2;root.footerIndex=0;root.footerAction()}}
                }
                Rectangle {
                    width:210;height:66;radius:18;color:root.focusZone===2&&root.footerIndex===1?"#153D64":"#0B2137";border.width:root.focusZone===2&&root.footerIndex===1?2:1;border.color:root.focusZone===2&&root.footerIndex===1?electricBlue:"#315A80"
                    Text{anchors.centerIn:parent;text:"CLOSE";color:textWhite;font.pixelSize:15;font.bold:true}
                    MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:root.close()}
                }
            }
        }
    }
}
