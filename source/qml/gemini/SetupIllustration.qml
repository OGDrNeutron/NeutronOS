import QtQuick
// Remove the near-black matte from reference decorative art at render time.
// Text, fields, navigation and all 3D scenes remain separate live components.
Image {
    fillMode: Image.Stretch
    layer.enabled: true
    layer.effect: ShaderEffect {
        property var source
        fragmentShader: "shaders/setup-illustration.frag.qsb"
    }
}
