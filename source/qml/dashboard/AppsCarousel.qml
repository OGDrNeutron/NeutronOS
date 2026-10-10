import QtQuick 2.15
import "../cards"

Item {
    id: root

    property int selectedApp: 0
    property int appStartIndex: 0
    property int visibleAppCount: 7
    property bool sectionFocused: false
    property int armedApp: -1
    property string orientation: "horizontal"

    /*
        Next-generation runtime compatibility.
        The carousel renders whatever AppManager/AppLauncher discovers,
        without hard-coding app IDs or assuming a fixed app list.
    */
    property bool animationsEnabled: visible && enabled

    /*
        Stable slot-based endless carousel.

        Fixes:
            - No every-other-card skipping.
            - No flicker from virtual index jumps.
            - Center slot is always the selected app.
            - Apps wrap endlessly behind fixed visible slots.
            - Fast scrolling is queued safely.
            - Selected card is largest and brightest.
            - Side cards are smaller and dimmer.
            - GPU-cached glide animation replaces the old 3D card flip.
            - Persistent texture-backed card layers avoid subtree repaint churn.
    */

    property int slotCount: visibleAppCount + 2

    property real focusedScale: 1.38
    property real inactiveFocusedScale: 1.10
    property real sideScale: 1.00
    property real farScale: 0.80
    property real edgeScale: 0.60

    property int tileHeight: Math.round(Math.max(530, Math.min(860, height * 0.90)))
    property int tileWidth: Math.round(tileHeight * 0.5625)
    property int tileSpacing: Math.round(Math.max(tileWidth * 0.74, Math.min(tileWidth * 0.90, width / 6.55)))

    property int pedestalHeight: 96
    property int pedestalBottomMargin: 72
    property int cardPedestalGap: 104

    property real cameraZoom: 1.0

    property bool internalSelectionChange: false
    property bool carouselReady: false

    property bool movementLocked: false
    property int queuedMoveSteps: 0
    property int switchDirection: 1
    property int movementStep: 0
    property int pendingSelectedApp: 0
    property bool suppressMovementFinalize: false

    /*
        trackShift:
            0   = stable
            1   = new selected card begins one slot to the right, then slides center
           -1   = new selected card begins one slot to the left, then slides center
    */
    property real trackShift: 0.0

    /*
        Patch 12 performance policy:
        - one short horizontal transition at a time;
        - one coalesced follow-up movement maximum;
        - card contents are cached as scene-graph layers;
        - no per-card idle breathing, floating, sweep, tilt, or pulse clocks.
    */

    signal appRequested(var appData, int index)

    /*
        Persistent ring slots.

        Each delegate keeps the same app identity for the entire swipe. Only
        the completely off-screen edge slot is recycled after the movement
        finishes. This prevents every card from changing its poster source on
        the first animation frame.
    */
    ListModel {
        id: slotModel
    }

    Behavior on cameraZoom {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            DATA HELPERS
        ============================================================
    */

    function appBackend() {
        try {
            if (typeof appManager !== "undefined" && appManager)
                return appManager
        } catch (e) {
        }

        try {
            if (typeof appLauncher !== "undefined" && appLauncher)
                return appLauncher
        } catch (e2) {
        }

        return null
    }

    function appList() {
        var backend = appBackend()

        if (!backend)
            return []

        try {
            if (backend.favoriteApps)
                return backend.favoriteApps
        } catch (e) {
        }

        try {
            if (backend.apps)
                return backend.apps
        } catch (e2) {
        }

        return []
    }

    function appCount() {
        try {
            return appList().length
        } catch (e) {
            return 0
        }
    }

    function wrapIndex(index) {
        var count = appCount()

        if (count <= 0)
            return 0

        index = index % count

        if (index < 0)
            index += count

        return index
    }

    function appAt(index) {
        var count = appCount()

        if (count <= 0)
            return null

        return appList()[wrapIndex(index)]
    }

    function selectedAppData() {
        return appAt(selectedApp)
    }

    function centerSlot() {
        return Math.floor(slotCount / 2)
    }

    function slotRelative(slot) {
        return slot - centerSlot()
    }

    function slotVisualOffset(slot) {
        if (slot >= 0 && slot < slotModel.count)
            return Number(slotModel.get(slot).slotPosition) + trackShift
        return slotRelative(slot) + trackShift
    }

    function slotAppIndex(slot) {
        if (slot >= 0 && slot < slotModel.count)
            return Number(slotModel.get(slot).appIndex)
        return wrapIndex(selectedApp + slotRelative(slot))
    }

    function displayNumber(realIndex) {
        return wrapIndex(realIndex) + 1
    }

    function themeFile(path) {
        try {
            if (typeof assetManager !== "undefined" &&
                    assetManager &&
                    typeof assetManager.themeFile === "function") {
                return assetManager.themeFile(path)
            }
        } catch (e) {
        }

        // This component lives under qml/dashboard, while theme assets are a
        // repository-level sibling of qml. Preserve the SVG atom fallback in
        // minimal/offscreen contexts where AssetManager is intentionally absent.
        return "../../themes/Default/" + (path === "atom.png" ? "atom.svg" : path)
    }

    function selectedIndex() {
        return wrapIndex(selectedApp)
    }

    function circularDiff(fromWrapped, toWrapped) {
        var count = appCount()

        if (count <= 0)
            return 0

        var diff = wrapIndex(toWrapped) - wrapIndex(fromWrapped)

        if (diff > count / 2)
            diff -= count

        if (diff < -count / 2)
            diff += count

        return diff
    }

    function stopMovementForReset() {
        suppressMovementFinalize = true
        movementStartTimer.stop()
        movementAnimation.stop()
        suppressMovementFinalize = false
        movementLocked = false
        movementStep = 0
        queuedMoveSteps = 0
        trackShift = 0
    }

    function rebuildSlots(centerIndex) {
        slotModel.clear()

        var count = appCount()
        if (count <= 0)
            return

        var center = centerSlot()
        var wrappedCenter = wrapIndex(centerIndex)

        for (var i = 0; i < slotCount; ++i) {
            var relative = i - center
            slotModel.append({
                "slotPosition": relative,
                "appIndex": wrapIndex(wrappedCenter + relative)
            })
        }
    }

    function clampSelection() {
        var count = appCount()

        stopMovementForReset()

        if (count <= 0) {
            internalSelectionChange = true
            selectedApp = 0
            appStartIndex = 0
            pendingSelectedApp = 0
            internalSelectionChange = false

            slotModel.clear()
            armedApp = -1
            carouselReady = false
            return
        }

        internalSelectionChange = true
        selectedApp = wrapIndex(selectedApp)
        appStartIndex = selectedApp
        pendingSelectedApp = selectedApp
        internalSelectionChange = false

        rebuildSlots(selectedApp)
        carouselReady = true
    }

    function setSelectedIndex(index) {
        stopMovementForReset()

        internalSelectionChange = true
        selectedApp = wrapIndex(index)
        appStartIndex = selectedApp
        pendingSelectedApp = selectedApp
        internalSelectionChange = false

        rebuildSlots(selectedApp)
        carouselReady = appCount() > 0
    }

    function moveToWrappedIndex(index) {
        var count = appCount()

        if (count <= 0)
            return

        if (!carouselReady)
            clampSelection()

        var diff = circularDiff(selectedApp, index)

        if (diff === 0)
            return

        var direction = diff > 0 ? 1 : -1
        var steps = Math.abs(diff)

        for (var i = 0; i < steps; i++)
            requestMove(direction)
    }

    function requestMove(delta) {
        if (appCount() <= 0)
            return

        if (!carouselReady)
            clampSelection()

        if (delta === 0)
            return

        var step = delta > 0 ? 1 : -1

        if (movementLocked) {
            /*
                Do not build a long animation backlog while the user rapidly
                swipes. Keep only the newest requested direction.
            */
            queuedMoveSteps = step
            return
        }

        applyMove(step)
    }

    function applyMove(step) {
        if (step === 0 || slotModel.count <= 0)
            return

        movementLocked = true
        movementStep = step > 0 ? 1 : -1
        switchDirection = movementStep
        pendingSelectedApp = wrapIndex(selectedApp + movementStep)
        trackShift = 0

        /*
            Enable the temporary card layers first, then begin movement on the
            next event-loop turn. No poster source changes while the cards are
            moving.
        */
        movementStartTimer.restart()
    }

    function finalizeMove() {
        if (suppressMovementFinalize || movementStep === 0)
            return

        var nextSelection = pendingSelectedApp

        internalSelectionChange = true
        selectedApp = nextSelection
        appStartIndex = selectedApp
        internalSelectionChange = false

        trackShift = 0
        movementStep = 0
        movementLocked = false

        // Rebuild the ring from the selected app after the texture layer is
        // disabled. This is symmetric in both directions and prevents a
        // recycled right-edge slot from retaining another app's poster.
        rebuildSlots(selectedApp)

        if (queuedMoveSteps !== 0) {
            var queuedStep = queuedMoveSteps
            queuedMoveSteps = 0
            Qt.callLater(function() { requestMove(queuedStep) })
        }
    }

    function nextApp() {
        requestMove(1)
    }

    function previousApp() {
        requestMove(-1)
    }

    function moveSelection(delta) {
        requestMove(delta)
    }

    function activateSelected() {
        openSelected()
    }

    function disarmSelected() {
        armedApp = -1
    }

    function handleController(action) {
        if (!sectionFocused)
            return false

        if (action === "left") {
            previousApp()
            return true
        }

        if (action === "right") {
            nextApp()
            return true
        }

        if (action === "primary" || action === "x") {
            openSelected()
            return true
        }

        if (action === "cancel" || action === "o") {
            disarmSelected()
            return true
        }

        return false
    }

    function selectApp(index) {
        moveToWrappedIndex(index)
    }

    function openSelected() {
        if (appCount() <= 0)
            return

        var idx = wrapIndex(selectedApp)

        root.armedApp = idx
        root.appRequested(appAt(idx), idx)
    }

    function visibleRange() {
        var result = []
        for (var i = 0; i < slotModel.count; ++i)
            result.push(Number(slotModel.get(i).appIndex))
        return result
    }

    function smoothMix(a, b, t) {
        t = Math.max(0, Math.min(1, t))
        t = t * t * (3 - 2 * t)

        return a + (b - a) * t
    }

    function pedestalTopY() {
        return carouselContainer.height - pedestalBottomMargin - pedestalHeight
    }

    function visualYForBottom(itemHeight, scaleValue, bottomY) {
        return bottomY - itemHeight / 2 - (itemHeight * scaleValue) / 2
    }

    function horizontalOffsetForSlot(offset) {
        var sign = offset < 0 ? -1 : 1
        var distance = Math.abs(offset)

        /*
            Keep the center-to-near and near-to-far spacing unchanged. The
            outermost card is pulled inward so the final gap no longer looks
            detached from the carousel.
        */
        if (distance <= 2.0)
            return offset

        return sign * (2.0 + (distance - 2.0) * 0.68)
    }

    function tileXForOffset(offset, itemWidth) {
        var centerX = carouselContainer.width / 2 - itemWidth / 2
        return centerX + horizontalOffsetForSlot(offset) * root.tileSpacing
    }

    function tileYForOffset(offset, itemHeight) {
        var dist = Math.abs(offset)
        var scaleValue = tileScaleForOffset(offset)

        var baseBottom = pedestalTopY() - cardPedestalGap

        if (dist <= 1.0)
            baseBottom = smoothMix(baseBottom, baseBottom + 20, dist)
        else if (dist <= 2.0)
            baseBottom = smoothMix(baseBottom + 20, baseBottom + 42, dist - 1.0)
        else
            baseBottom = smoothMix(baseBottom + 42, baseBottom + 62, Math.min(1, dist - 2.0))

        return visualYForBottom(itemHeight, scaleValue, baseBottom)
    }

    function tileScaleForOffset(offset) {
        var dist = Math.abs(offset)

        var selectedScale = sectionFocused
                            ? focusedScale
                            : inactiveFocusedScale

        if (dist <= 1.0)
            return smoothMix(selectedScale, sideScale, dist)

        if (dist <= 2.0)
            return smoothMix(sideScale, farScale, dist - 1.0)

        return smoothMix(farScale, edgeScale, Math.min(1, dist - 2.0))
    }

    function tileOpacityForOffset(offset) {
        var dist = Math.abs(offset)

        if (dist <= 1.0)
            return smoothMix(sectionFocused ? 1.0 : 0.88, 0.70, dist)

        if (dist <= 2.0)
            return smoothMix(0.70, 0.42, dist - 1.0)

        if (dist <= 3.0)
            return smoothMix(0.42, 0.20, dist - 2.0)

        return smoothMix(0.20, 0.0, Math.min(1, dist - 3.0))
    }

    function tileZForOffset(offset) {
        var dist = Math.abs(offset)
        return Math.max(1, 500 - dist * 70)
    }

    function tileVisibleForOffset(offset) {
        return Math.abs(offset) <= centerSlot() + 0.95
    }

    /*
        ============================================================
                            MOVEMENT ANIMATION
        ============================================================

        Only trackShift changes during a swipe. The previous arc/tilt/pulse
        properties forced every card subtree to repaint on every frame. Card
        subtrees are now texture-backed and only their outer transforms move.
    */

    Timer {
        id: movementStartTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!root.movementLocked || root.movementStep === 0)
                return
            root.trackShift = 0
            movementAnimation.to = root.movementStep > 0 ? -1.0 : 1.0
            movementAnimation.restart()
        }
    }

    NumberAnimation {
        id: movementAnimation

        target: root
        property: "trackShift"
        from: 0.0
        to: -1.0
        duration: 270
        easing.type: Easing.OutCubic

        onStopped: root.finalizeMove()
    }

    /*
        ============================================================
                            CAROUSEL
        ============================================================
    */

    Item {
        id: carouselContainer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 0
        anchors.bottomMargin: 0

        scale: cameraZoom
        clip: false
        z: 10

        /*
            ============================================================
                            RAISED PEDESTAL
            ============================================================
        */

        Item {
            id: appRowPedestal

            visible: root.appCount() > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.pedestalBottomMargin
            width: Math.min(parent.width * 0.91, root.tileSpacing * 6.05)
            height: root.pedestalHeight + 20
            z: 1

            readonly property color liveAccent:
                root.armedApp === root.wrapIndex(root.selectedApp)
                ? "#FF3040"
                : "#7DF9FF"

            /* Soft floor shadow: depth without a live blur effect. */
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -30
                width: parent.width * 0.90
                height: 46
                radius: 23
                color: "#000000"
                opacity: 0.72
            }

            /* Lower machined chassis. */
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -13
                width: parent.width * 0.97
                height: 70
                radius: 30
                color: "#020711"
                border.width: 1
                border.color: "#1A3048"
            }

            /* Main floating deck. */
            Rectangle {
                id: pedestal
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 88
                radius: 30
                color: root.armedApp === root.wrapIndex(root.selectedApp)
                       ? "#21090F"
                       : "#071524"
                border.width: root.sectionFocused ? 2 : 1
                border.color: appRowPedestal.liveAccent

                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: root.armedApp === root.wrapIndex(root.selectedApp)
                               ? "#44121B" : "#132A40"
                    }
                    GradientStop {
                        position: 0.38
                        color: root.armedApp === root.wrapIndex(root.selectedApp)
                               ? "#220A10" : "#0A1B2D"
                    }
                    GradientStop { position: 1.0; color: "#040A13" }
                }

                /* Precision top lip. */
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 26
                    anchors.rightMargin: 26
                    anchors.topMargin: 7
                    height: 3
                    radius: 2
                    color: appRowPedestal.liveAccent
                    opacity: root.sectionFocused ? 0.78 : 0.32
                }

                /* Recessed runway. */
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.80
                    height: 35
                    radius: 17
                    color: "#020812"
                    border.width: 1
                    border.color: "#294A67"

                    /* One dash per app. The dash ring follows the exact same
                       trackShift as the poster cards, so the next app's dash
                       reaches center on the same frame as its card. */
                    Repeater {
                        model: Math.max(1, root.appCount())
                        Rectangle {
                            required property int index
                            property real appOffset: root.appCount() > 0
                                                     ? root.circularDiff(root.selectedApp, index) + root.trackShift
                                                     : 0
                            property real distanceFromCenter: Math.abs(appOffset)
                            width: 18
                            height: distanceFromCenter < 0.34 ? 5 : 3
                            radius: height / 2
                            x: parent.width / 2 - width / 2 +
                               appOffset * ((parent.width - 54) / 16)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: distanceFromCenter <= 8.4
                            rotation: Math.max(-16, Math.min(16, -appOffset * 2.0))
                            transformOrigin: Item.Center
                            color: appRowPedestal.liveAccent
                            opacity: distanceFromCenter < 0.34
                                     ? 0.95
                                     : 0.20 + Math.max(0, 1.0 - distanceFromCenter / 8.0) * 0.34
                        }
                    }
                }

                /* Elevated magnetic landing pad beneath the selected card. */
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: -8
                    width: Math.min(root.tileWidth * 1.16, 360)
                    height: 26
                    radius: 13
                    color: "#081B2D"
                    border.width: 2
                    border.color: appRowPedestal.liveAccent

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.68
                        height: 8
                        radius: 4
                        color: appRowPedestal.liveAccent
                        opacity: root.sectionFocused ? 0.30 : 0.14
                    }
                }

                /* Symmetric premium edge caps. */
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        x: index === 0 ? 20 : parent.width - width - 20
                        width: 52
                        height: 28
                        radius: 10
                        color: "#0D2237"
                        border.width: 1
                        border.color: "#365A78"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 24
                            height: 3
                            radius: 2
                            color: appRowPedestal.liveAccent
                            opacity: 0.55
                        }
                    }
                }
            }
        }

        /*
            Stable visible slots.
            These slot objects never represent permanent app IDs. Instead, the
            app data wraps through them as selectedApp changes.
        */

        Repeater {
            id: slotRepeater

            model: slotModel

            Item {
                id: tileHost

                required property int index
                required property int slotPosition
                required property int appIndex

                property int slotNumber: index
                property int slotRel: slotPosition
                property real visualOffset: slotPosition + root.trackShift

                /*
                    Card contents stay cached in a scene-graph layer. During a
                    swipe Qt moves/scales the cached texture instead of
                    rebuilding poster, badge, text, and border nodes.
                */

                width: root.tileWidth
                height: root.tileHeight

                visible: root.tileVisibleForOffset(visualOffset)
                enabled: visible

                x: Math.round(root.tileXForOffset(visualOffset, width))
                y: Math.round(root.tileYForOffset(visualOffset, height))

                scale: root.tileScaleForOffset(visualOffset)
                opacity: root.tileOpacityForOffset(visualOffset)

                rotation: 0
                transformOrigin: Item.Center

                z: root.tileZForOffset(visualOffset)

                /*
                    Cache only while moving. At rest the card renders live, so
                    a recycled off-screen slot cannot retain an old poster
                    texture. No delegate changes identity during the swipe.
                */
                layer.enabled: root.movementLocked
                layer.smooth: true
                layer.mipmap: false

                AppTile {
                    id: frontCard

                    anchors.fill: parent

                    slotIndex: tileHost.slotNumber
                    realIndex: tileHost.appIndex
                    displayNumber: root.displayNumber(tileHost.appIndex)

                    appData: root.appAt(tileHost.appIndex)

                    focused: root.sectionFocused &&
                             tileHost.slotPosition === (root.movementLocked
                                                       ? root.movementStep
                                                       : 0)
                    armed: root.armedApp === tileHost.appIndex
                    animationsEnabled: root.animationsEnabled && !root.movementLocked

                    onOpenRequested: {
                        root.armedApp = tileHost.appIndex
                        root.appRequested(appData, tileHost.appIndex)
                    }
                }
            }
        }
    }

    /*
        ============================================================
                            EMPTY STATE
        ============================================================
    */

    Column {
        visible: appCount() === 0

        anchors.centerIn: carouselContainer

        spacing: 24

        Rectangle {
            width: 120
            height: 120
            radius: 60

            color: "#071426AA"

            border.color: "#337DF9FF"
            border.width: 3

            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                anchors.centerIn: parent

                source: root.themeFile("atom.png")

                width: 68
                height: 68

                opacity: 0.72
                smooth: true
                sourceSize.width: 96
                mipmap: false
            }

            SequentialAnimation on scale {
                running: root.animationsEnabled
                loops: Animation.Infinite

                NumberAnimation {
                    from: 1.0
                    to: 1.08
                    duration: 1600
                    easing.type: Easing.InOutSine
                }

                NumberAnimation {
                    from: 1.08
                    to: 1.0
                    duration: 1600
                    easing.type: Easing.InOutSine
                }
            }
        }

        Text {
            text: "No Apps Installed"

            color: "white"

            font.pixelSize: 29
            font.bold: true

            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "Place apps in ~/NeutronOS/qml/apps"

            color: "#9fd8ff"

            font.pixelSize: 17
            font.bold: true

            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    /*
        ============================================================
                            STATE CHANGES
        ============================================================
    */

    Connections {
        target: root.appBackend()
        enabled: target !== null
        ignoreUnknownSignals: true

        function onAppsChanged() {
            root.clampSelection()
        }

        function onFavoriteAppsChanged() {
            root.clampSelection()
        }
    }

    onSectionFocusedChanged: {
        if (sectionFocused && (!carouselReady || slotModel.count !== slotCount))
            clampSelection()
    }

    onSelectedAppChanged: {
        if (internalSelectionChange)
            return

        /* External selection restoration is immediate and deterministic. */
        setSelectedIndex(selectedApp)
    }

    onSlotCountChanged: clampSelection()

    Component.onCompleted: {
        clampSelection()
    }
}
