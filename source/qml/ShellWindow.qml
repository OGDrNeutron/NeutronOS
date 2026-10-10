import QtQuick
import QtQuick.Controls
import QtQuick.Window

ApplicationWindow {
    id: root
    width: 1920
    height: 1080
    visibility: Window.FullScreen
    title: "NeutronOS Gemini 0.5 candidate"
    color: "#050814"
    property bool destinationPresentationArmed: false
    property bool bootFocusRequested: false
    property bool destinationPresented: false
    function loadShell() { shellLoader.source = "Main.qml" }
    function focusInitialDestination() {
        if (destinationPresented || !shellLoader.item || !shellLoader.item.destinationSurfaceReady)
            return
        var destination = shellLoader.item.destinationSurfaceItem
        if (destination)
            destination.forceActiveFocus()
        root.update()
    }
    onActiveChanged: { if (active) Qt.callLater(root.focusInitialDestination) }
    Loader {
        id: shellLoader
        anchors.fill: parent
        asynchronous: false
        onLoaded: Qt.callLater(root.focusInitialDestination)
    }
    readonly property bool realUiReady:
        root.active && shellLoader.status === Loader.Ready && shellLoader.item &&
        shellLoader.item.destinationSurfaceReady === true &&
        shellLoader.item.destinationInputReady === true
    readonly property bool smokeUiReady:
        shellLoader.status === Loader.Ready && shellLoader.item &&
        shellLoader.item.destinationSurfaceReady === true &&
        shellLoader.item.inputLocked === false
    onRealUiReadyChanged: { if (realUiReady) root.update() }

    onFrameSwapped: {
        if (shellLoader.item && shellLoader.item.destinationSurfaceReady && !bootFocusRequested) {
            // Main's startup keyboard fallback may take focus after Login's
            // onLoaded. Restore the actual destination once for this handoff.
            bootFocusRequested = true
            if (shellLoader.item.destinationSurfaceItem)
                shellLoader.item.destinationSurfaceItem.forceActiveFocus()
            root.update()
        }
        if (realUiReady && !destinationPresented &&
                !(typeof neutronSmokeTest !== "undefined" && neutronSmokeTest === true)) {
            destinationPresented = true;
            shellReadiness.markDestinationPresented();
        }
    }
}
