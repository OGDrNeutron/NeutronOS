import QtQuick 2.15
import "../../../components" as Shared

Shared.ReferenceExitModal {
    id: root
    property bool developerMode: false
    property bool ptyAlive: false
    signal closeRequested()
    signal returnRequested()
    signal backgroundRequested()

    function open() { openModal(null) }
    function close() { closeModal() }
    function handleControllerPressed(button) { return handleController(button) }
    function handleControllerReleased(button) { return visible }

    appName: "Terminal"
    onExitRequested: returnRequested()
    onLeaveRunningRequested: backgroundRequested()
    onDismissed: closeRequested()
}
