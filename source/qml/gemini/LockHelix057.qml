import QtQuick

// A single GPU shader renders a coherent double helix; only its periodic phase
// animates. Each accepted authentication input owns an independent pulse.
Item {
    id: root
    objectName: "GeminiLockHelix"
    property var quality: null
    property bool armed: false
    property bool animated: true
    readonly property bool running: visible && armed && animated
    readonly property int activePulseCount: pulses.count
    property int acceptedPulseCount: 0
    property int nextPulseId: 0
    property real turn: 0
    visible: armed
    function acceptedInput() {
        if (!running) return
        acceptedPulseCount++
        pulses.append({pulseId: ++nextPulseId, origin: turn + (nextPulseId * 37) % 360})
    }
    function removePulse(id) {
        for (var i=0; i<pulses.count; ++i)
            if (pulses.get(i).pulseId === id) {pulses.remove(i); return}
    }
    onRunningChanged: { if (!running) pulses.clear() }
    ListModel {id: pulses}
    NumberAnimation on turn {
        from: 0; to: 360; duration: 14000; loops: Animation.Infinite
        running: root.running; easing.type: Easing.Linear
    }
    ShaderEffect {
        anchors.fill:parent
        property real phase:root.turn/360
        fragmentShader:Qt.resolvedUrl("shaders/lock-helix057.frag.qsb")
    }
    Repeater {
        model: pulses
        delegate: Item {
            id: pulse
            required property int pulseId
            required property real origin
            property real travel: 0
            readonly property real angle: (origin+travel*310)*Math.PI/180
            readonly property real radius: root.width*(.425 + Math.sin((angle-root.turn*Math.PI/180)*6)*.019)
            x: root.width/2+Math.cos(angle)*radius-width/2
            y: root.height/2+Math.sin(angle)*radius-height/2
            width: 52; height: 52
            opacity: Math.pow(1-travel, .75)
            Canvas {
                anchors.fill:parent
                onPaint: {
                    var ctx=getContext("2d"),r=width/2,g=ctx.createRadialGradient(r,r,0,r,r,r)
                    g.addColorStop(0,"#fff1ff");g.addColorStop(.12,"#edc3ff")
                    g.addColorStop(.27,"#db72ff");g.addColorStop(.48,"#b946ff")
                    g.addColorStop(.72,"#55a000ff");g.addColorStop(1,"#00000000")
                    ctx.fillStyle=g;ctx.fillRect(0,0,width,height)
                }
            }
            NumberAnimation on travel {
                from: 0; to: 1; duration: 1800; running: root.running
                easing.type: Easing.Linear
                onFinished: root.removePulse(pulse.pulseId)
            }
        }
    }
}
