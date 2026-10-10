import QtQuick
import QtQuick.Effects

Item {
    id: root
    property var backgroundSource: null
    property bool effectActive: false

    ShaderEffectSource {
        id: backgroundCapture
        anchors.fill: parent
        sourceItem: root.backgroundSource
        live: root.effectActive
        recursive: true
        hideSource: false
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: backgroundCapture
        visible: root.effectActive
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: -0.30
        brightness: -0.18
    }
}
