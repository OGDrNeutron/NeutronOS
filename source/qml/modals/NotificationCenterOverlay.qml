import QtQuick
import QtQuick.Controls
import "../components"

Item {
    id: root

    property var backend: null
    property var backgroundSource: null
    property var systemBackend: null
    property var networkBackend: null
    property var mediaBackend: null
    property var securityBackend: null
    property string authenticatedUsername: ""
    // Cleared on cancel, close, expiry, and verification completion.
    property bool securityComboOpen: false
    property var securityComboTokens: []
    property bool securityComboPending: false
    property int securityComboEpoch: 0
    property int securityComboSubmittedEpoch: -1
    property int securityComboSubmittedCount: 0
    property string securityComboMessage: "Enter your login controller combo."
    property bool opened: false
    property bool clearArmed: false
    property bool l3Pressed: false
    property bool r3Pressed: false
    property int selectedIndex: 0
    property int filterIndex: 0
    property bool mediaControlsFocused: false
    property var visibleNotifications: []
    property string actionStatus: ""

    readonly property var filters: [
        { id: "all", label: "ALL" },
        { id: "system", label: "SYSTEM" },
        { id: "security", label: "SECURITY" },
        { id: "storage", label: "STORAGE" },
        { id: "network", label: "NETWORK" },
        { id: "apps", label: "APPS" },
        { id: "updates", label: "UPDATES" }
    ]

    signal closed()
    signal notificationActionRequested(string action, var payload)

    anchors.fill: parent
    visible: opened || closeSignalTimer.running
    enabled: opened
    opacity: opened ? 1.0 : 0.0
    z: 500

    function clean(value, fallback) {
        var text = String(value === undefined || value === null ? "" : value).trim()
        return text.length > 0 ? text : String(fallback || "--")
    }

    function openCenter() {
        resetSecurityCombo()
        clearArmed = false
        l3Pressed = false
        r3Pressed = false
        clearArmTimer.stop()
        actionStatus = ""
        mediaControlsFocused = false
        refreshNotifications()
        opened = true
        forceActiveFocus()
    }

    function closeCenter() {
        if (!opened)
            return
        clearArmed = false
        l3Pressed = false
        r3Pressed = false
        clearArmTimer.stop()
        resetSecurityCombo()
        opened = false
        closeSignalTimer.restart()
    }

    function refreshNotifications() {
        var source = []
        try {
            source = backend && backend.notifications ? backend.notifications : []
        } catch (error) {
            source = []
        }

        var filterId = filters[Math.max(0, Math.min(filterIndex, filters.length - 1))].id
        var output = []
        for (var index = 0; index < source.length; index++) {
            var item = source[index]
            if (filterId === "all" || String(item.category || "system") === filterId)
                output.push(item)
        }
        visibleNotifications = output
        selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, output.length - 1)))
        notificationList.currentIndex = output.length > 0 ? selectedIndex : -1
    }

    function cycleFilter(delta) {
        filterIndex = (filterIndex + delta + filters.length) % filters.length
        selectedIndex = 0
        refreshNotifications()
    }

    function mediaAvailable() {
        try { return mediaBackend && mediaBackend.currentTrack && String(mediaBackend.currentTrack.title || "").length > 0 }
        catch (error) { return false }
    }

    function moveSelection(delta) {
        if (mediaControlsFocused) {
            if (delta > 0 && visibleNotifications.length > 0) {
                mediaControlsFocused = false
                selectedIndex = 0
                notificationList.currentIndex = selectedIndex
                notificationList.positionViewAtIndex(selectedIndex, ListView.Contain)
            }
            return
        }
        if (delta < 0 && selectedIndex <= 0 && mediaAvailable()) {
            mediaControlsFocused = true
            notificationList.currentIndex = -1
            return
        }
        if (visibleNotifications.length <= 0) {
            if (mediaAvailable()) mediaControlsFocused = true
            return
        }
        selectedIndex = Math.max(0, Math.min(visibleNotifications.length - 1, selectedIndex + delta))
        notificationList.currentIndex = selectedIndex
        notificationList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function selectedNotification() {
        if (selectedIndex < 0 || selectedIndex >= visibleNotifications.length)
            return null
        return visibleNotifications[selectedIndex]
    }

    function activateSelected() {
        var item = selectedNotification()
        if (!item)
            return
        if (backend && typeof backend.markRead === "function")
            backend.markRead(String(item.id || ""), true)
        if (String(item.action || "").length > 0)
            notificationActionRequested(String(item.action), item.payload || {})
        refreshNotifications()
    }

    function dismissSelected() {
        var item = selectedNotification()
        if (!item)
            return
        if (backend && typeof backend.dismiss === "function") {
            var removed=backend.dismiss(String(item.id || ""))
            actionStatus=removed?"Notification cleared":"Critical security notifications are protected"
        }
        refreshNotifications()
    }

    function securityNotificationCount() {
        var source=backend&&backend.notifications?backend.notifications:[], count=0
        for(var i=0;i<source.length;++i)if(String(source[i].category||"").toLowerCase()==="security")count++
        return count
    }

    function resetSecurityCombo() {
        securityComboEpoch++
        securityComboOpen=false
        securityComboPending=false
        securityComboSubmittedEpoch=-1
        securityComboTokens=[]
        securityComboQuietTimer.stop()
        securityComboRetryTimer.stop()
        securityComboExpiry.stop()
        securityComboMessage="Enter your login controller combo."
    }

    function comboBackendReady() {
        return securityBackend &&
               typeof securityBackend.beginAuthenticatedNotificationClear === "function" &&
               String(authenticatedUsername || "").trim().length>0 &&
               !(securityBackend.lockedOut===true && Number(securityBackend.secondsRemaining||0)>0)
    }

    function openSecurityCombo() {
        clearArmed=false
        clearArmTimer.stop()
        if (!comboBackendReady()) {
            actionStatus="Login combo verification unavailable or locked. Security notifications were not cleared."
            return
        }
        resetSecurityCombo()
        securityComboOpen=true
        securityComboExpiry.restart()
        securityComboMessage="Enter the login controller combo to clear all Security notifications."
        forceActiveFocus()
    }

    function comboToken(action) {
        var mapping={primary:"X",cancel:"O",context:"TRIANGLE",secondary:"SQUARE",
                     system:"START",quick:"SELECT",home:"SYSTEM",
                     up:"U",down:"D",left:"L",right:"R",
                     l1:"L1",r1:"R1",l2:"L2",r2:"R2",l3:"L3",r3:"R3"}
        return mapping[action] || ""
    }

    function configuredComboLength() {
        try {
            var count=Number(securityBackend.comboLength)
            if (isFinite(count) && count>0 && count<=15) return Math.floor(count)
        }catch(e){}
        // LoginScreen uses 4 if the backend does not advertise a length.
        return 4
    }

    function captureSecurityCombo(action) {
        if (!securityComboOpen) return true
        var token=comboToken(action)
        if (!token.length) return true
        if (securityComboTokens.length>=15 ||
                (securityBackend && securityBackend.lockedOut===true &&
                 Number(securityBackend.secondsRemaining||0)>0)) {
            securityComboMessage="Authentication locked or input window full. Cancel and try again."
            return true
        }
        var copy=securityComboTokens.slice(0)
        copy.push(token)
        securityComboTokens=copy
        securityComboMessage="Sequence captured: "+copy.length+" / 15"
        securityComboExpiry.restart()
        if (copy.length>=configuredComboLength()) securityComboQuietTimer.restart()
        return true
    }

    function beginSecurityComboVerification() {
        if (!securityComboOpen || securityComboPending ||
                securityComboTokens.length<configuredComboLength()) return
        if (!comboBackendReady()) {
            securityComboMessage="Authentication unavailable or locked. Nothing was deleted."
            return
        }
        if (securityBackend.operationBusy===true) {
            securityComboRetryTimer.restart()
            return
        }
        var accepted=false
        try {
            accepted=securityBackend.beginAuthenticatedNotificationClear(
                authenticatedUsername, securityComboTokens.join(""))===true
        }catch(e){accepted=false}
        if (!accepted) {
            securityComboMessage="Authentication is busy. Retrying without clearing notifications."
            securityComboRetryTimer.restart()
            return
        }
        securityComboPending=true
        securityComboSubmittedEpoch=securityComboEpoch
        securityComboSubmittedCount=securityComboTokens.length
        securityComboMessage="Verifying controller combo…"
    }

    function finishSecurityComboVerification(result) {
        if (!securityComboOpen || !securityComboPending ||
                securityComboSubmittedEpoch!==securityComboEpoch) return
        var submittedCount=securityComboSubmittedCount
        securityComboPending=false
        var secondsRemaining=Number(result&&result.secondsRemaining||0)
        if (result && result.success===true && Number(result.remainingSecurity)===0) {
            resetSecurityCombo()
            refreshNotifications()
            actionStatus="Authenticated: cleared " + Number(result.removed||0) +
                         " Security notifications. " + Number(result.total||0) + " notifications remain."
            forceActiveFocus()
            return
        }
        if (result && result.success===true) {
            resetSecurityCombo()
            refreshNotifications()
            actionStatus="Security clear incomplete. Check notification storage."
            return
        }
        if (Number(secondsRemaining||0)>0 ||
                (securityBackend && securityBackend.lockedOut===true)) {
            resetSecurityCombo()
            actionStatus="Login combo rejected; security lockout active. No notifications deleted."
            return
        }
        if (submittedCount>=15) {
            securityComboTokens=[]
            securityComboMessage="Incorrect combo. Press Cancel to exit or enter a new sequence."
            return
        }
        securityComboMessage="Incorrect sequence. Continue entering your login combo."
        if (securityComboTokens.length>submittedCount) securityComboQuietTimer.restart()
    }

    // L3 is exclusively a two-press Security-notification action.
    // First edge arms; a second *separate* edge opens login-combo verification.
    // Neither edge clears ordinary notices or invokes clearSecurity().
    function performL3SecurityClear() {
        if (!opened || securityComboOpen) return
        if (!clearArmed) {
            if (securityNotificationCount() <= 0) {
                actionStatus="No Security notifications to clear"
                return
            }
            clearArmed=true
            clearArmTimer.restart()
            actionStatus="Security clear armed. Release L3, then press L3 again to enter your login combo."
        } else {
            openSecurityCombo()
        }
    }

    // R3 clears ordinary and dismissible Security presentation records without
    // authentication. The compiled backend intentionally retains protected
    // Security alerts; those require a separate authenticated backend method.
    function performR3Clear() {
        if (!opened || securityComboOpen) return
        if (!backend || typeof backend.clearAll !== "function") {
            actionStatus = "Notification clear unavailable; no notifications deleted."
            return
        }
        var before = backend.notifications ? backend.notifications.length : 0
        var result = false
        try { result = backend.clearAll() === true }
        catch (error) { result = false }
        refreshNotifications()
        var after = backend.notifications ? backend.notifications.length : 0
        if (!result) {
            actionStatus = "Notification clear failed; verify notification storage."
        } else if (before > after) {
            actionStatus = "Cleared " + (before - after) +
                    " normal/dismissible notifications. Protected Security alerts remain."
        } else {
            actionStatus = "No normal or dismissible Security notifications to clear."
        }
        forceActiveFocus()
    }

    function handleControllerPressed(action) {
        if (!opened)
            return false
        if (securityComboOpen) return captureSecurityCombo(action)

        if (action === "cancel" || action === "home") {
            closeCenter()
            return true
        }
        if (action === "up") {
            moveSelection(-1)
            return true
        }
        if (action === "down") {
            moveSelection(1)
            return true
        }
        if (mediaControlsFocused) {
            if (action === "left" || action === "l1") {
                if (mediaBackend && typeof mediaBackend.previous === "function") mediaBackend.previous()
                return true
            }
            if (action === "right" || action === "r1") {
                if (mediaBackend && typeof mediaBackend.next === "function") mediaBackend.next()
                return true
            }
            if (action === "primary") {
                if (mediaBackend && typeof mediaBackend.togglePause === "function") mediaBackend.togglePause()
                return true
            }
            if (action === "secondary") {
                if (mediaBackend && typeof mediaBackend.stop === "function") mediaBackend.stop()
                return true
            }
        }
        if (action === "left" || action === "l1") {
            cycleFilter(-1)
            return true
        }
        if (action === "right" || action === "r1") {
            cycleFilter(1)
            return true
        }
        if (action === "primary") {
            activateSelected()
            return true
        }
        if (action === "context") {
            var detail=selectedNotification();if(detail)notificationActionRequested("details",detail)
            return true
        }
        if (action === "secondary") {
            dismissSelected()
            return true
        }
        if (action === "l3") {
            if (l3Pressed) return true
            l3Pressed=true
            performL3SecurityClear()
            return true
        }
        if (action === "r3") {
            if (r3Pressed) return true
            r3Pressed = true
            performR3Clear()
            return true
        }
        return true
    }

    function handleControllerReleased(action) {
        if(action==="l3")l3Pressed=false
        if(action==="r3")r3Pressed=false
        return opened
    }

    function priorityColor(priority) {
        var value = String(priority || "info").toLowerCase()
        if (value === "critical") return "#ff344d"
        if (value === "warning") return "#ffb52e"
        if (value === "success") return "#45e58c"
        return "#55c9ff"
    }

    function categoryIcon(category) {
        var value = String(category || "system").toLowerCase()
        if (value === "security") return "◆"
        if (value === "storage") return "▰"
        if (value === "network") return "⌁"
        if (value === "apps") return "▦"
        if (value === "updates") return "↥"
        if (value === "backup") return "↺"
        if (value === "games") return "✦"
        if (value === "docker") return "⬡"
        if (value === "media") return "▶"
        return "●"
    }

    function formatTimestamp(timestampMs) {
        var value = Number(timestampMs || 0)
        if (!isFinite(value) || value <= 0)
            return "NOW"
        var date = new Date(value)
        return date.toLocaleString(Qt.locale(), "MMM d  h:mm AP")
    }

    function temperatureText() {
        try {
            if (systemBackend && systemBackend.temperature)
                return clean(systemBackend.temperature, "--")
            if (systemBackend && Number(systemBackend.cpuTemperature) > 0)
                return Math.round(Number(systemBackend.cpuTemperature)) + "°F"
        } catch (error) {}
        return "--"
    }

    function networkText() {
        try {
            if (networkBackend && networkBackend.connectedSsid)
                return clean(networkBackend.connectedSsid, "OFFLINE")
            if (systemBackend && systemBackend.ssid)
                return clean(systemBackend.ssid, "OFFLINE")
        } catch (error) {}
        return "OFFLINE"
    }

    function storageText() {
        try {
            var slots = systemBackend && systemBackend.storageDisplaySlots ? systemBackend.storageDisplaySlots : []
            if (slots.length > 0) {
                var boot = slots[0]
                if (boot.text) return clean(boot.text, "--")
                if (boot.used && boot.total) return String(boot.used) + " / " + String(boot.total)
                if (boot.usedPercent !== undefined) return Math.round(Number(boot.usedPercent)) + "% USED"
            }
        } catch (error) {}
        return "--"
    }

    function healthText() {
        try {
            if (systemBackend && systemBackend.thermalThrottled)
                return "THROTTLED"
        } catch (error) {}
        return "SYSTEM NORMAL"
    }

    Loader {
        id: blurLayerLoader
        anchors.fill: parent
        active: root.opened
        source: "NotificationBlurLayer.qml"

        onLoaded: {
            if (!item)
                return
            item.backgroundSource = Qt.binding(function() { return root.backgroundSource })
            item.effectActive = Qt.binding(function() { return root.opened })
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#B0030610"
        visible: root.opened
    }

    Rectangle {
        id: panel
        width: parent.width
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        color: "#FA050B16"
        border.width: 0
        border.color: "#7055DFFF"
        radius: 0

        Rectangle {
            width: 128
            height: 7
            radius: 4
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#B319E9FF"
        }

        Column {
            id: headerColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 34
            anchors.leftMargin: Math.max(64,parent.width*.045)
            anchors.rightMargin: Math.max(64,parent.width*.045)
            spacing: 18

            Row {
                width: parent.width
                height: 74
                spacing: 18

                Column {
                    width: parent.width - unreadPill.width - 24
                    spacing: 4

                    Text {
                        text: "Notification Center"
                        color: "#FFFFFF"
                        font.pixelSize: 34
                        font.bold: true
                        font.letterSpacing: 0.4
                    }

                    Text {
                        text: "Important NeutronOS activity, system health, and completed work"
                        color: "#A9C1D8"
                        font.pixelSize: 18
                    }
                }

                Rectangle {
                    id: unreadPill
                    width: 190
                    height: 54
                    radius: 27
                    anchors.verticalCenter: parent.verticalCenter
                        color: "#34111D38"
                    border.width: 2
                        border.color: "#805F5CFF"

                    Text {
                        anchors.centerIn: parent
                        text: (root.backend ? Number(root.backend.unreadCount || 0) : 0) + " UNREAD"
                        color: "#D7F2FF"
                        font.pixelSize: 18
                        font.bold: true
                    }
                }
            }

            Row {
                width: parent.width
                height: 88
                spacing: 14

                Repeater {
                    model: [
                        { label: "HEALTH", value: root.healthText(), accent: root.healthText() === "SYSTEM NORMAL" ? "#45E58C" : "#FF4C63" },
                        { label: "CPU TEMP", value: root.temperatureText(), accent: "#FF6D8F" },
                        { label: "NETWORK", value: root.networkText(), accent: "#55C9FF" },
                        { label: "BOOT STORAGE", value: root.storageText(), accent: "#A985FF" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: (headerColumn.width - 42) / 4
                        height: 88
                        radius: 14
                        color: "#B20A1324"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.13)

                        Rectangle {
                            width: 5
                            height: parent.height - 26
                            radius: 3
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.accent
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 30
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: modelData.label
                                color: "#8FA9BF"
                                font.pixelSize: 13
                                font.bold: true
                                font.letterSpacing: 1.2
                            }
                            Text {
                                width: parent.width
                                text: modelData.value
                                color: "#FFFFFF"
                                font.pixelSize: 21
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: 44
                spacing: 10

                Repeater {
                    model: root.filters
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        height: 42
                        width: Math.max(112, filterText.implicitWidth + 34)
                        radius: 12
                        color: root.filterIndex === index ? "#B51D3370" : "#A20A1222"
                        border.width: root.filterIndex === index ? 2 : 1
                        border.color: root.filterIndex === index ? "#19E9FF" : "#4352626E"

                        Text {
                            id: filterText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.filterIndex === index ? "white" : "#A5B6C7"
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }
                }
            }
        }

        Rectangle {
            id: mediaCard
            anchors.top: headerColumn.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 16
            anchors.leftMargin: Math.max(64,parent.width*.045)
            anchors.rightMargin: Math.max(64,parent.width*.045)
            height: root.mediaAvailable() ? 112 : 0
            visible: height > 0
            radius: 30
            color: root.mediaControlsFocused ? "#D22D4664" : "#B51C2B3D"
            border.width: root.mediaControlsFocused ? 3 : 1
            border.color: root.mediaControlsFocused ? "#73E6FF" : "#39566C7A"

            Row {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 18
                Rectangle {
                    width: 76; height: 76; radius: 22
                    color: "#173A57"
                    border.width: 1; border.color: "#4CA7FF"
                    Text { anchors.centerIn: parent; text: root.mediaBackend && root.mediaBackend.playing && !root.mediaBackend.paused ? "Ⅱ" : "▶"; color: "#73E6FF"; font.pixelSize: 30; font.bold: true }
                }
                Column {
                    width: parent.width - 430
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text { width: parent.width; text: root.mediaBackend ? String(root.mediaBackend.currentTrack.title || "Nothing Playing") : "Nothing Playing"; color: "white"; font.pixelSize: 22; font.bold: true; elide: Text.ElideRight }
                    Text { width: parent.width; text: root.mediaBackend ? String(root.mediaBackend.currentTrack.artist || "Music Player") : "Music Player"; color: "#73E6FF"; font.pixelSize: 15; elide: Text.ElideRight }
                    Rectangle {
                        width: parent.width; height: 7; radius: 4; color: "#183149"
                        Rectangle { width: parent.width * ((root.mediaBackend && root.mediaBackend.durationMs > 0) ? Math.min(1, root.mediaBackend.positionMs / root.mediaBackend.durationMs) : 0); height: parent.height; radius: parent.radius; color: "#B58AFF" }
                    }
                }
                Text {
                    width: 300
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mediaControlsFocused ? "← PREVIOUS   X PLAY/PAUSE   → NEXT   □ STOP" : "↑ SELECT MUSIC CONTROLS"
                    color: root.mediaControlsFocused ? "#FFFFFF" : "#9FB8CA"
                    font.pixelSize: 14
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WordWrap
                }
            }
        }

        ListView {
            id: notificationList
            anchors.top: mediaCard.visible ? mediaCard.bottom : headerColumn.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.topMargin: 18
            anchors.leftMargin: Math.max(64,parent.width*.045)
            anchors.rightMargin: Math.max(64,parent.width*.045)
            anchors.bottomMargin: 14
            clip: true
            spacing: 12
            model: root.visibleNotifications
            currentIndex: root.visibleNotifications.length > 0 ? root.selectedIndex : -1
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                required property int index
                required property var modelData
                width: notificationList.width
                height: 116
                radius: 34
                color: index === root.selectedIndex ? "#D2323D53" : (modelData.read ? "#A51E2533" : "#C52A3244")
                border.width: index === root.selectedIndex ? 3 : 1
                border.color: index === root.selectedIndex ? "#70D7FF" : Qt.rgba(1, 1, 1, 0.10)

                Rectangle {
                    width: 7
                    height: parent.height - 28
                    radius: 4
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.priorityColor(modelData.priority)
                }

                Rectangle {
                    width: 70
                    height: 70
                    radius: 23
                    anchors.left: parent.left
                    anchors.leftMargin: 34
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(0.15, 0.55, 0.85, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(0.45, 0.85, 1.0, 0.35)

                    Text {
                        anchors.centerIn: parent
                        text: root.categoryIcon(modelData.category)
                        color: root.priorityColor(modelData.priority)
                        font.pixelSize: 31
                        font.bold: true
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 124
                    anchors.right: timeColumn.left
                    anchors.rightMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Row {
                        width: parent.width
                        spacing: 12

                        Text {
                            width: Math.max(0, parent.width - categoryLabel.width - 14)
                            text: root.clean(modelData.title, "NeutronOS Notification")
                            color: "#FFFFFF"
                            font.pixelSize: 22
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            id: categoryLabel
                            text: String(modelData.category || "system").toUpperCase()
                            color: root.priorityColor(modelData.priority)
                            font.pixelSize: 13
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.clean(modelData.message, "")
                        color: "#B8C8D8"
                        font.pixelSize: 17
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }
                }

                Column {
                    id: timeColumn
                    width: 190
                    anchors.right: parent.right
                    anchors.rightMargin: 28
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        width: parent.width
                        text: root.formatTimestamp(modelData.timestampMs)
                        color: "#8FA7BC"
                        font.pixelSize: 14
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                    }
                    Text {
                        width: parent.width
                        text: root.clean(modelData.source, "NEUTRONOS")
                        color: "#6DD7FF"
                        font.pixelSize: 13
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }
                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        anchors.right: parent.right
                        visible: !Boolean(modelData.read)
                        color: "#5AD7FF"
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.visibleNotifications.length === 0
                text: "NO NOTIFICATIONS\nNeutronOS will place system, security, storage, network, app, and update events here."
                color: "#8DA4B9"
                font.pixelSize: 21
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.45
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 78
            color: "#A40B101C"
            border.width: 1
            border.color: "#223F566A"

            Row { anchors.centerIn:parent;spacing:14
                ModalActionButton{width:210;height:56;glyph:"X";label:"SELECT / OPEN";accent:"#35DFFF";onActivated:root.activateSelected()}
                ModalActionButton{width:210;height:56;glyph:"□";label:"CLEAR SELECTED";accent:"#C861FF";destructive:true;onActivated:root.dismissSelected()}
                ModalActionButton{width:210;height:56;glyph:"△";label:"DETAILS";accent:"#74FF50";onActivated:{var detail=root.selectedNotification();if(detail)root.notificationActionRequested("details",detail)}}
                ModalActionButton{width:190;height:56;glyph:"R3";label:"CLEAR DISMISSIBLE";accent:"#35DFFF";onActivated:root.performR3Clear()}
                ModalActionButton{width:210;height:56;glyph:"L3";label:root.clearArmed?"CONFIRM SECURITY":"ARM SECURITY";accent:"#FFB13B";destructive:root.clearArmed;onActivated:root.performL3SecurityClear()}
                ModalActionButton{width:170;height:56;glyph:"O";label:"CLOSE";accent:"#FF526A";onActivated:root.closeCenter()}
            }
            Text{anchors.right:parent.right;anchors.rightMargin:28;anchors.bottom:parent.top;anchors.bottomMargin:8;text:root.actionStatus;color:"#FFB85A";font.pixelSize:14;font.bold:true}
        }
    }

    // Dedicated authentication gate. All controller actions are captured here
    // via Main.qml before global shortcuts while this panel is visible.
    Rectangle {
        id: securityComboBackdrop
        anchors.fill: parent
        z: 2000
        color: "#E9030712"
        visible: root.opened && root.securityComboOpen
        enabled: visible
        MouseArea { anchors.fill: parent; onClicked: {} }
        Rectangle {
            width: Math.min(parent.width-64, 740)
            height: 380
            radius: 28
            anchors.centerIn: parent
            color: "#09172C"
            border.width: 3
            border.color: "#F7D85B"
            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 20
                Text { text: "SECURITY AUTHENTICATION"; color: "#F7D85B"; font.pixelSize: 28; font.bold: true }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Enter your login controller combo. Only successfully verified input can clear dismissible Security notifications."
                    color: "#F4FBFF"; font.pixelSize: 19
                }
                Text {
                    width: parent.width
                    text: root.securityComboMessage
                    color: "#B4D0E8"; font.pixelSize: 17
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    width: parent.width; height: 64; radius: 14
                    color: "#06101F"; border.width: 1; border.color: "#43728A"
                    Text {
                        anchors.centerIn: parent
                        text: root.securityComboTokens.length > 0
                              ? "● ".repeat(root.securityComboTokens.length)
                              : "AWAITING CONTROLLER INPUT"
                        color: "#F7D85B"; font.pixelSize: 22; font.bold: true
                    }
                }
                Item { width: 1; height: 3 }
                Rectangle {
                    width: 205; height: 48; radius: 12
                    color: "#251724"; border.width: 1; border.color: "#FF526A"
                    Text { anchors.centerIn: parent; text: "CANCEL"; color: "#FFFFFF"; font.pixelSize: 17; font.bold: true }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.resetSecurityCombo(); root.actionStatus="Security clear cancelled"; root.forceActiveFocus() }
                    }
                }
            }
        }
    }

    Timer { id: securityComboQuietTimer; interval: 220; repeat: false; onTriggered: root.beginSecurityComboVerification() }
    Timer { id: securityComboRetryTimer; interval: 160; repeat: false; onTriggered: root.beginSecurityComboVerification() }
    Timer { id: securityComboExpiry; interval: 90000; repeat: false; onTriggered: {
        root.resetSecurityCombo(); root.actionStatus="Security authentication expired. No notifications deleted."
    } }
    Connections {
        target: root.securityBackend
        ignoreUnknownSignals: true
        function onAuthenticatedNotificationClearFinished(result) {
            root.finishSecurityComboVerification(result)
        }
    }

    Timer {
        id: clearArmTimer
        interval: 3500
        repeat: false
        onTriggered: { root.clearArmed=false; root.actionStatus="Security clear confirmation expired" }
    }

    Timer {
        id: closeSignalTimer
        interval: 380
        repeat: false
        onTriggered: root.closed()
    }

    Connections {
        target: root.backend
        enabled: target !== null
        ignoreUnknownSignals: true
        function onNotificationsChanged() { root.refreshNotifications() }
    }

    onFilterIndexChanged: refreshNotifications()
}
