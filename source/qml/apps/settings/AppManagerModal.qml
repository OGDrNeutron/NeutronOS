import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components" as Shared

Item {
    id: root
    anchors.fill: parent
    visible: visibleMode
    enabled: visibleMode
    focus: visibleMode
    z: 120

    property bool visibleMode: false
    property var appBackend: null
    property var securityBackend: null
    property string activeUsername: ""
    property bool automaticLoginEnabled: false

    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color panelInset: "#06101F"
    property color textPrimary: "#F4FBFF"
    property color textSecondary: "#A8C2DE"
    property color textMuted: "#7895B5"
    property color divider: "#1D3958"
    property color focusBlue: "#4DA6FF"
    property color cyan: "#23C7E8"
    property color success: "#16C784"
    property color warning: "#F5B942"
    property color danger: "#FF4055"

    property int selectedIndex: 0
    property int actionIndex: 0
    property var selectedApp: ({})
    property var selectedDetails: ({})
    property string statusMessage: ""
    property bool statusError: false
    property string pendingProtectedAction: ""
    property var pendingProtectedApp: ({})
    property string passwordBuffer: ""
    property bool uninstallArmed: false

    signal closeRequested()
    signal launchRequested(var appData)

    ListModel { id: installedModel; dynamicRoles: true }
    readonly property var actions: ["OPEN", "STORAGE", "CLEAR CACHE", "UNINSTALL"]

    Timer {
        id: uninstallArmTimer
        interval: 4000
        repeat: false
        onTriggered: root.uninstallArmed = false
    }

    function open() {
        visibleMode = true
        actionIndex = 0
        selectedIndex = 0
        statusMessage = ""
        statusError = false
        uninstallArmed = false
        refreshApps()
        forceActiveFocus()
    }

    function close() {
        passwordKeyboard.visibleMode = false
        passwordBuffer = ""
        pendingProtectedAction = ""
        pendingProtectedApp = ({})
        visibleMode = false
        closeRequested()
    }

    function refreshApps() {
        installedModel.clear()
        if (!appBackend)
            return
        var source = appBackend.installedApps()
        for (var i = 0; i < source.length; i++)
            installedModel.append(source[i])
        if (installedModel.count <= 0) {
            selectedIndex = -1
            selectedApp = ({})
            selectedDetails = ({})
            return
        }
        selectedIndex = Math.max(0, Math.min(selectedIndex, installedModel.count - 1))
        appList.currentIndex = selectedIndex
        selectCurrent()
    }

    function selectCurrent() {
        if (selectedIndex < 0 || selectedIndex >= installedModel.count) {
            selectedApp = ({})
            selectedDetails = ({})
            return
        }
        selectedApp = installedModel.get(selectedIndex)
        selectedDetails = appBackend ? appBackend.appManagementDetails(selectedApp) : selectedApp
        appList.currentIndex = selectedIndex
        appList.positionViewAtIndex(selectedIndex, ListView.Contain)
        uninstallArmed = false
        uninstallArmTimer.stop()
    }

    function authValid() {
        if (!automaticLoginEnabled)
            return true
        return securityBackend &&
               typeof securityBackend.highPriorityAuthorizationValidFor === "function" &&
               securityBackend.highPriorityAuthorizationValidFor("settings")
    }

    function requestProtected(actionName, appData) {
        pendingProtectedAction = actionName
        pendingProtectedApp = appData
        if (authValid()) {
            executeProtected()
            return
        }
        passwordBuffer = ""
        passwordKeyboard.title = "Confirm Login Password"
        passwordKeyboard.openKeyboard(true)
        passwordKeyboard.forceActiveFocus()
    }

    function executeProtected() {
        var actionName = pendingProtectedAction
        var appData = pendingProtectedApp
        pendingProtectedAction = ""
        pendingProtectedApp = ({})
        if (!appBackend || !appData)
            return
        var ok = false
        if (actionName === "clear-cache")
            ok = appBackend.clearAppCache(appData)
        else if (actionName === "uninstall")
            ok = appBackend.uninstallApp(appData)
        statusError = !ok
        if (!ok && statusMessage.length === 0)
            statusMessage = "The requested app-management action failed."
        refreshApps()
    }

    function commitPassword() {
        passwordKeyboard.visibleMode = false
        var ok = securityBackend &&
                 securityBackend.authorizeHighPriorityAction(activeUsername, passwordBuffer, "settings")
        passwordBuffer = ""
        if (!ok) {
            statusMessage = securityBackend ? String(securityBackend.lastError || "Login password was not accepted.")
                                            : "Security backend unavailable."
            statusError = true
            pendingProtectedAction = ""
            pendingProtectedApp = ({})
            forceActiveFocus()
            return
        }
        statusMessage = "High-priority actions authorized for 15 minutes while Settings remains open."
        statusError = false
        executeProtected()
        forceActiveFocus()
    }

    function performAction() {
        if (!selectedApp || String(selectedApp.id || "").length === 0)
            return
        var action = actions[actionIndex]
        if (action === "OPEN") {
            launchRequested(selectedApp)
            return
        }
        if (action === "STORAGE") {
            selectedDetails = appBackend.appManagementDetails(selectedApp)
            statusMessage = "Storage and usage details refreshed."
            statusError = false
            return
        }
        if (action === "CLEAR CACHE") {
            requestProtected("clear-cache", selectedApp)
            return
        }
        if (action === "UNINSTALL") {
            if (selectedDetails.uninstallable !== true) {
                statusMessage = "This is a protected core or system-owned application."
                statusError = true
                return
            }
            if (!uninstallArmed) {
                uninstallArmed = true
                uninstallArmTimer.restart()
                statusMessage = "Press X again within four seconds to uninstall " + String(selectedApp.name || selectedApp.id) + "."
                statusError = true
                return
            }
            uninstallArmed = false
            uninstallArmTimer.stop()
            requestProtected("uninstall", selectedApp)
        }
    }

    function handleControllerPressed(button) {
        var action = String(button || "").toLowerCase()
        if (passwordKeyboard.visibleMode)
            return passwordKeyboard.handleControllerPressed(action)
        if (action === "cross" || action === "x" || action === "ps_cross") action = "primary"
        else if (action === "circle" || action === "o" || action === "ps_circle") action = "cancel"
        else if (action === "triangle" || action === "ps_triangle") action = "context"
        else if (action === "dpad_up") action = "up"
        else if (action === "dpad_down") action = "down"
        else if (action === "dpad_left") action = "left"
        else if (action === "dpad_right") action = "right"

        if (action === "cancel") { close(); return true }
        if (action === "context") { refreshApps(); statusMessage = "Installed applications refreshed."; statusError = false; return true }
        if (action === "up" && installedModel.count > 0) {
            selectedIndex = (selectedIndex - 1 + installedModel.count) % installedModel.count
            selectCurrent(); return true
        }
        if (action === "down" && installedModel.count > 0) {
            selectedIndex = (selectedIndex + 1) % installedModel.count
            selectCurrent(); return true
        }
        if (action === "left") {
            actionIndex = (actionIndex - 1 + actions.length) % actions.length
            uninstallArmed = false; uninstallArmTimer.stop(); return true
        }
        if (action === "right") {
            actionIndex = (actionIndex + 1) % actions.length
            uninstallArmed = false; uninstallArmTimer.stop(); return true
        }
        if (action === "primary") { performAction(); return true }
        return true
    }

    Rectangle {
        anchors.fill: parent
        color: "#D0000000"
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1540)
        height: Math.min(parent.height - 80, 900)
        radius: 34
        color: root.panelColor
        border.width: 2
        border.color: root.focusBlue

        Column {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 18

            Row {
                width: parent.width
                height: 74
                spacing: 16
                Rectangle {
                    width: 58; height: 58; radius: 18
                    color: root.focusBlue
                    Text { anchors.centerIn: parent; text: "▦"; color: "#04111F"; font.pixelSize: 27; font.bold: true }
                }
                Column {
                    width: parent.width - 330
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text { width: parent.width; text: "Installed App Manager"; color: root.textPrimary; font.pixelSize: 30; font.bold: true }
                    Text { width: parent.width; text: installedModel.count + " installed applications • real storage, cache and usage data"; color: root.textMuted; font.pixelSize: 13 }
                }
                Rectangle {
                    width: 220; height: 44; radius: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.automaticLoginEnabled ? root.panelInset : root.panelRaised
                    border.width: 1
                    border.color: root.automaticLoginEnabled ? root.warning : root.divider
                    Text { anchors.centerIn: parent; text: root.automaticLoginEnabled ? "PASSWORD-GATED" : "STANDARD SECURITY"; color: root.automaticLoginEnabled ? root.warning : root.textMuted; font.pixelSize: 11; font.bold: true }
                }
            }

            Row {
                width: parent.width
                height: parent.height - 172
                spacing: 18

                Rectangle {
                    width: 500
                    height: parent.height
                    radius: 24
                    color: root.panelInset
                    border.width: 1
                    border.color: root.divider

                    ListView {
                        id: appList
                        anchors.fill: parent
                        anchors.margins: 14
                        model: installedModel
                        clip: true
                        spacing: 8
                        currentIndex: root.selectedIndex
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            width: appList.width
                            height: 76
                            radius: 17
                            color: index === root.selectedIndex ? root.focusBlue : root.panelRaised
                            border.width: index === root.selectedIndex ? 2 : 1
                            border.color: index === root.selectedIndex ? "#D9F4FF" : root.divider
                            Row {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12
                                Rectangle {
                                    width: 44; height: 44; radius: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: index === root.selectedIndex ? "#163B61" : root.panelInset
                                    Text { anchors.centerIn: parent; text: String(name || id || "APP").substring(0, 1).toUpperCase(); color: root.cyan; font.pixelSize: 19; font.bold: true }
                                }
                                Column {
                                    width: parent.width - 155
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Text { width: parent.width; text: String(name || id || "Application"); color: index === root.selectedIndex ? "#04111F" : root.textPrimary; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                                    Text { width: parent.width; text: String(category || "Apps") + " • " + String(type || "unknown"); color: index === root.selectedIndex ? "#163B61" : root.textMuted; font.pixelSize: 11; elide: Text.ElideRight }
                                }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: running === true ? "ACTIVE" : "INSTALLED"; color: running === true ? root.success : (index === root.selectedIndex ? "#163B61" : root.textMuted); font.pixelSize: 10; font.bold: true }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width - 518
                    height: parent.height
                    radius: 24
                    color: root.panelRaised
                    border.width: 1
                    border.color: root.divider

                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 15
                        Text { width: parent.width; text: String(root.selectedDetails.name || "No application selected"); color: root.textPrimary; font.pixelSize: 27; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: String(root.selectedDetails.description || "Select an installed application to inspect it."); color: root.textSecondary; font.pixelSize: 14; wrapMode: Text.WordWrap }
                        Rectangle { width: parent.width; height: 1; color: root.divider }
                        Grid {
                            width: parent.width
                            columns: 2
                            rowSpacing: 12
                            columnSpacing: 14
                            Repeater {
                                model: [
                                    ["VERSION", String(root.selectedDetails.version || "Unknown")],
                                    ["LAST USED", String(root.selectedDetails.lastUsedText || "Never opened")],
                                    ["APP STORAGE", String(root.selectedDetails.storageText || "0 B")],
                                    ["CACHE", String(root.selectedDetails.cacheText || "0 B")],
                                    ["SOURCE", String(root.selectedDetails.source || "Unknown")],
                                    ["STATUS", root.selectedDetails.running === true ? "Active" : "Inactive"]
                                ]
                                Rectangle {
                                    width: (parent.width - 14) / 2
                                    height: 82
                                    radius: 17
                                    color: root.panelInset
                                    border.width: 1
                                    border.color: root.divider
                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 13
                                        spacing: 6
                                        Text { width: parent.width; text: modelData[0]; color: root.textMuted; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.0 }
                                        Text { width: parent.width; text: modelData[1]; color: root.textPrimary; font.pixelSize: 15; font.bold: true; elide: Text.ElideMiddle }
                                    }
                                }
                            }
                        }
                        Text { width: parent.width; text: "INSTALL PATH"; color: root.textMuted; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.0 }
                        Text { width: parent.width; text: String(root.selectedDetails.installPath || "Not reported"); color: root.cyan; font.pixelSize: 13; wrapMode: Text.WrapAnywhere }
                        Text { width: parent.width; text: "PERMISSIONS"; color: root.textMuted; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.0 }
                        Text { width: parent.width; text: String(root.selectedDetails.permissionsText || "No declared permissions"); color: root.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap }
                        Item { width: 1; height: 1 }
                        Row {
                            width: parent.width
                            spacing: 10
                            Repeater {
                                model: root.actions
                                Rectangle {
                                    width: (parent.width - 30) / 4
                                    height: 58
                                    radius: 16
                                    color: index === root.actionIndex ? (modelData === "UNINSTALL" ? root.danger : root.focusBlue) : root.panelInset
                                    border.width: index === root.actionIndex ? 2 : 1
                                    border.color: index === root.actionIndex ? "#D9F4FF" : root.divider
                                    opacity: modelData === "UNINSTALL" && root.selectedDetails.uninstallable !== true ? 0.45 : 1.0
                                    Text { anchors.centerIn: parent; text: modelData; color: index === root.actionIndex ? "#04111F" : root.textPrimary; font.pixelSize: 12; font.bold: true }
                                }
                            }
                        }
                        Text { width: parent.width; text: root.statusMessage; visible: root.statusMessage.length > 0; color: root.statusError ? root.danger : root.success; font.pixelSize: 13; font.bold: true; wrapMode: Text.WordWrap }
                    }
                }
            }

            Text {
                width: parent.width
                text: "UP/DOWN  APPS    LEFT/RIGHT  ACTION    X  SELECT    △  REFRESH    O  CLOSE"
                color: root.textMuted
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Shared.VirtualKeyboard {
        id: passwordKeyboard
        anchors.centerIn: parent
        width: Math.min(parent.width - 100, 1500)
        height: Math.min(parent.height - 100, 820)
        z: 200
        visibleMode: false
        visible: visibleMode
        enabled: visibleMode
        active: visibleMode
        largeMode: true
        cancelBehavior: "close"
        onKeyPressed: function(value) { root.passwordBuffer += value }
        onBackspacePressed: {
            if (root.passwordBuffer.length > 0)
                root.passwordBuffer = root.passwordBuffer.substring(0, root.passwordBuffer.length - 1)
        }
        onEnterPressed: root.commitPassword()
        onClosePressed: {
            visibleMode = false
            root.passwordBuffer = ""
            root.pendingProtectedAction = ""
            root.pendingProtectedApp = ({})
            root.forceActiveFocus()
        }
    }

    Connections {
        target: appBackend
        ignoreUnknownSignals: true
        function onAppsChanged() { if (root.visibleMode) root.refreshApps() }
        function onAppActionFinished(appId, actionName, success, message) {
            root.statusMessage = message
            root.statusError = !success
            if (root.visibleMode) root.refreshApps()
        }
    }
}
