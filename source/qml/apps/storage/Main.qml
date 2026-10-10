import QtQuick 2.15
import "../../modals/system" as SystemModals
import "../../components" as Shared

Item {
    id: app
    anchors.fill: parent
    focus: true
    property string appId: "storage"
    property string appName: "Storage"
    property var appData: ({})
    property var activeUser: null
    property bool developerModeEnabled: false
    property bool hostActive: true
    property bool exitVisible: false
    signal exitRequested()
    signal backgroundRequested()

    SystemModals.StorageDisplayModal {
        id: storagePanel
        anchors.fill: parent
        visible: true
        enabled: !app.exitVisible
        focus: !app.exitVisible
        contextData: ({ source: "storage-app", fullManager: true })
        modalContext: contextData
        onClosed: app.openExitMenu()
    }

    Shared.ReferenceExitModal {
        id: storageExitModal
        appName: "Storage"
        onExitRequested: app.exitRequested()
        onLeaveRunningRequested: app.backgroundRequested()
        onDismissed: {
            app.exitVisible = false
            storagePanel.open({ source: "storage-app", fullManager: true })
            storagePanel.forceActiveFocus()
        }
    }

    function openExitMenu() {
        exitVisible = true
        storageExitModal.openModal(storagePanel)
    }
    Component.onCompleted: {
        storagePanel.open({ source: "storage-app", fullManager: true })
        storagePanel.forceActiveFocus()
    }
    function normalize(button) {
        var value = String(button || "").toLowerCase().replace(/-/g, "_")
        if (value === "x" || value === "cross" || value === "primary") return "primary"
        if (value === "o" || value === "circle" || value === "cancel") return "cancel"
        if (value === "dpad_left") return "left"
        if (value === "dpad_right") return "right"
        if (value === "dpad_up") return "up"
        if (value === "dpad_down") return "down"
        return value
    }
    function handleController(button) { return handleControllerPressed(button) }
    function handleControllerPressed(button) {
        var value = normalize(button)
        if (exitVisible) return storageExitModal.handleController(value)
        if (storagePanel && typeof storagePanel.handleControllerPressed === "function")
            return storagePanel.handleControllerPressed(button)
        if (value === "cancel") { openExitMenu(); return true }
        return true
    }
    function handleControllerReleased(button) { return true }
}
