import QtQuick
// Static GPU haze. No animation driver or CPU Canvas repaint loop.
ShaderEffect {
    property real strength:1
    property real readyScene:0
    fragmentShader:"shaders/setup-atmosphere.frag.qsb"
}
