import QtQuick
import NeutronBoot 1.0
Item {
    id: root
    objectName: "neutronBootOverlay"
    property bool active: presentation.active
    property bool readiness: false
    property bool surfaceReady: false
    property int stage: 0
    property bool captureActive: false
    property bool motionStarted: false
    property real fractureProgress: 0
    readonly property int percent: presentation.percent
    readonly property int shardCount: fracture.shardCount
    readonly property bool recovery: presentation.recovery
    signal finished(bool verified)
    visible: active
    enabled: false

    BootPresentation {
        id: presentation
        onRecoveryChanged: {
            if (!recovery) {
                root.stage = root.percent >= 100 ? 5 : root.percent >= 95 ? 4 :
                             root.percent >= 85 ? 3 : root.percent >= 75 ? 2 :
                             root.percent >= 65 ? 1 : 0
                watchdog.restart()
                if (root.percent < 100) atom.restart()
                return
            }
            atom.stop(); hold.stop(); captureTimeout.stop(); watchdog.stop(); suction.stop()
            root.motionStarted = false; root.captureActive = false
            root.fractureProgress = 0
            console.info("BOOT: RECOVERY acknowledged; login transition cancelled")
        }
    }
    function complete(verified) {
        if (!active || recovery) return
        if (!presentation.finish(verified)) return
        hold.stop(); watchdog.stop(); captureTimeout.stop(); atom.stop(); suction.stop()
        active = false
        finished(verified)
    }
    // Called only by the owning window's real onFrameSwapped handler.
    function framePresented(inputReady, created) {
        readiness = inputReady; surfaceReady = created
        if (!active) return
        if (recovery) { presentation.acknowledgeRecoveryFrame(); return }
        if (stage === 0 && artwork.loaded) {
            if (presentation.advance(65, "qt-window-and-shell-created")) stage = 1
        } else if (stage === 1 && created) {
            if (presentation.advance(75, "login-surface-created")) stage = 2
        } else if (stage === 2 && inputReady) {
            if (presentation.advance(85, "login-focused-input-ready")) stage = 3
        } else if (stage === 3 && inputReady) {
            if (presentation.advance(95, "login-covered-frame-rendered")) stage = 4
        } else if (stage === 4 && inputReady) {
            if (presentation.advance(100, "login-rendered-focused-input-ready")) {
                stage = 5; atom.stop()
            }
        } else if (stage === 5 && inputReady) {
            // This swap actually presented the verified 100% frame.
            stage = 6; hold.start()
        } else if (captureActive && !motionStarted && inputReady && fracture.textureAvailable()) {
            motionStarted = true; captureTimeout.stop(); suction.start()
        }
    }
    BootArtwork {
        id: artwork
        anchors.fill: parent
        referenceUrl: presentation.active ? presentation.referenceUrl : ""
        percent: presentation.percent
        recovery: presentation.recovery
        // Ensure the scene behind the opaque cover participates in rendering.
        opacity: 0.999999
    }
    NumberAnimation {
        id: atom
        target: artwork; property: "phase"
        from: 0; to: 1; duration: 4200; loops: Animation.Infinite
        running: root.active
    }
    ShaderEffectSource {
        id: snapshot
        anchors.fill: parent
        sourceItem: root.captureActive ? artwork : null
        live: false
        hideSource: root.motionStarted
        // One capture capped at 1080p, preserving the active aspect ratio.
        textureSize: Qt.size(Math.max(1, Math.round(root.width * Math.min(1, 1920 / root.width, 1080 / root.height))),
                             Math.max(1, Math.round(root.height * Math.min(1, 1920 / root.width, 1080 / root.height))))
        visible: root.captureActive
        opacity: 0.000001
    }
    SuctionEffect {
        id: fracture
        anchors.fill: parent
        visible: root.captureActive
        sourceItem: root.captureActive ? snapshot : null
        progress: root.fractureProgress
    }
    NumberAnimation {
        id: suction
        target: root; property: "fractureProgress"
        from: 0.000001; to: 1; duration: 1000
        onFinished: root.complete(true)
    }
    Timer {
        id: hold
        interval: 110
        onTriggered: {
            if (!root.readiness) { root.stage = 5; return }
            root.captureActive = true
            snapshot.scheduleUpdate()
            captureTimeout.start()
        }
    }
    Timer {
        id: captureTimeout
        interval: 350
        onTriggered: root.complete(root.readiness)
    }
    Timer {
        id: watchdog
        interval: 20000
        running: root.active
        onTriggered: {
            console.warn("Boot presentation watchdog released the login surface")
            root.complete(false)
        }
    }
}
