import QtQuick
QtObject {
    id: root
    objectName:"GeminiRenderQuality"
    property bool active: false
    property int level: 2
    readonly property int particleCount: level === 2 ? 96 : level === 1 ? 32 : 8
    readonly property int fractureColumns: level === 2 ? 32 : level === 1 ? 24 : 14
    readonly property bool bloom: level > 0
    readonly property string textureTier: level === 2 ? "full" : "reduced"
    property real measuredFps: 0
    property real maximumFrameMs: 0
    property real sampleSeconds: 0
    property int sampleFrames: 0
    property int stableWindows: 0
    property bool discardResumeFrame:true
    onActiveChanged: {sampleSeconds=0;sampleFrames=0;discardResumeFrame=true}
    property FrameAnimation sampler: FrameAnimation {
        running: root.active
        onTriggered: {
            // Provisioning pauses are not measurements of GPU capability.
            if(root.discardResumeFrame){root.discardResumeFrame=false;return}
            root.sampleSeconds += frameTime
            root.sampleFrames++
            root.maximumFrameMs = Math.max(root.maximumFrameMs, frameTime*1000)
            if(root.sampleSeconds < 3)return
            root.measuredFps = root.sampleFrames/root.sampleSeconds
            // Adapt only the effects. Never touch geometry/layout or navigation.
            if(root.measuredFps < 48 && root.level > 0) {
                root.level--; root.stableWindows = 0
            } else if(root.measuredFps > 58 && root.level < 2) {
                root.stableWindows++
                if(root.stableWindows >= 3){root.level++;root.stableWindows=0}
            } else root.stableWindows=0
            root.sampleSeconds=0;root.sampleFrames=0
        }
    }
}
