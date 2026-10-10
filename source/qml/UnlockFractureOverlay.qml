import QtQuick
import NeutronEffects 1.0

Item {
    id: root

    property Item captureSource: null
    property string transitionState: "IDLE"
    property bool running: false
    property bool captureActive: false
    property bool fallbackUsed: false
    property real progress: 0
    property int captureAttempts: 0
    property bool progressLogged: false
    property real originX: 0.5
    property real originY: 0.43
    readonly property int crackDuration: 240
    readonly property int shardFallDuration: 2700

    signal captureReady(int shardCount)
    signal captureCommitted()
    signal fractureStarted(int shardCount)
    signal transitionFailed(string reason)
    signal finished(bool fallbackUsed)

    visible: running
    enabled: false
    opacity: running ? 1 : 0

    function logState(message) {
        console.info("UNLOCK: " + message)
    }

    function reset() {
        captureProbe.stop()
        captureTimeout.stop()
        animationWatchdog.stop()
        animationTick.stop()
        fractureAnimation.stop()
        progress = 0
        running = false
        captureActive = false
        fallbackUsed = false
        captureAttempts = 0
        progressLogged = false
        transitionState = "IDLE"
        fracture.fallbackRenderer = false
    }

    function start() {
        reset()
        running = true
        transitionState = "CAPTURING"
        logState("CAPTURE_REQUESTED")
        // Seed is assigned once per transition. FractureEffect defers topology
        // generation until progress becomes non-zero, after all QML geometry
        // properties have settled.
        fracture.seed = Math.floor(Date.now() % 2147483647)

        if (!captureSource || width <= 0 || height <= 0 ||
                captureSource.width <= 0 || captureSource.height <= 0 ||
                !captureSource.visible) {
            startFallback("CAPTURE_INVALID")
            return
        }

        captureActive = true
        progress = .001
        snapshot.scheduleUpdate()
        captureProbe.start()
        captureTimeout.start()
        animationWatchdog.start()
    }

    function beginFracture() {
        captureProbe.stop()
        captureTimeout.stop()
        transitionState = "CRACKING"
        logState("CAPTURE_READY")
        logState("SHARDS_CREATED=" + fracture.shardCount)
        captureReady(fracture.shardCount)
        captureCommitted()
        transitionState = "FRACTURING"
        logState("FRACTURE_STARTED")
        fractureStarted(fracture.shardCount)
        animationTick.start()
        fractureAnimation.restart()
    }

    function startFallback(reason) {
        if (!running)
            running = true
        captureProbe.stop()
        captureTimeout.stop()
        captureActive = false
        fallbackUsed = true
        fracture.fallbackRenderer = true
        transitionState = "FRACTURING"
        progress = .001
        logState(reason)
        logState("SHARDS_CREATED=" + fracture.shardCount + " FALLBACK")
        transitionFailed(reason)
        captureCommitted()
        logState("FRACTURE_STARTED FALLBACK")
        fractureStarted(fracture.shardCount)
        animationTick.start()
        animationWatchdog.restart()
        fractureAnimation.restart()
    }

    function completeAnimation() {
        if (!running)
            return
        captureProbe.stop()
        captureTimeout.stop()
        animationWatchdog.stop()
        animationTick.stop()
        transitionState = "COMPLETE"
        progress = 1
        logState("FRACTURE_COMPLETE" + (fallbackUsed ? " FALLBACK" : ""))
        finished(fallbackUsed)
        // The synchronous completion callback may now hide LoginScreen. Keep
        // the source texture alive until that callback has returned.
        captureActive = false
        running = false
        progress = 0
        fracture.fallbackRenderer = false
    }

    ShaderEffectSource {
        id: snapshot
        anchors.fill: parent
        sourceItem: root.captureActive ? root.captureSource : null
        live: false
        hideSource: false
        textureSize: Qt.size(Math.max(1, Math.min(2560, root.width)),
                             Math.max(1, Math.min(1440, root.height)))
        visible: root.captureActive
        opacity: .001
        recursive: true
    }

    Timer {
        id: captureProbe
        interval: 16
        repeat: true
        onTriggered: {
            root.captureAttempts++
            snapshot.scheduleUpdate()
            if (fracture.textureReady && fracture.shardCount > 0)
                root.beginFracture()
        }
    }

    Timer {
        id: captureTimeout
        interval: 1500
        repeat: false
        onTriggered: root.startFallback(fracture.shardCount > 0
                                        ? "TEXTURE_PROVIDER_MISSING"
                                        : "ZERO_SHARDS")
    }

    Timer {
        id: animationTick
        interval: 260
        repeat: true
        onTriggered: {
            if (!fractureAnimation.running) {
                root.logState("ANIMATION_NOT_RUNNING")
                root.startFallback("ANIMATION_NOT_RUNNING")
            } else if (!root.progressLogged && root.progress >= .18) {
                root.progressLogged = true
                root.logState("ANIMATION_TICK/STATE=" + root.transitionState)
            }
        }
    }

    Timer {
        id: animationWatchdog
        interval: 5000
        repeat: false
        onTriggered: {
            root.logState("COMPLETION_NOT_FIRED")
            root.transitionFailed("COMPLETION_NOT_FIRED")
            root.completeAnimation()
        }
    }

    FractureEffect {
        id: fracture
        anchors.fill: parent
        visible: root.running
        progress: root.progress
        originX: root.originX
        originY: root.originY
        sourceItem: root.captureActive ? snapshot : null
    }

    SequentialAnimation {
        id: fractureAnimation

        NumberAnimation {
            target: root
            property: "progress"
            from: .001
            to: .30
            duration: root.crackDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "progress"
            from: .30
            to: 1
            duration: root.shardFallDuration
            easing.type: Easing.Linear
        }
        onFinished: root.completeAnimation()
    }

    Component.onDestruction: reset()
}
