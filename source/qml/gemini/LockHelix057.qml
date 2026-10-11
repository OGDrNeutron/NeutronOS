import QtQuick

// Static luminous strands are painted once. Scene-graph rotation supplies flow;
// accepted authentication inputs each own an independent, short-lived pulse.
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
    Canvas {
        id: strands
        anchors.fill: parent
        rotation: root.turn
        renderTarget: Canvas.Image
        onPaint: {
            var ctx=getContext("2d"), cx=width/2, cy=height/2, radius=width*.435
            ctx.clearRect(0,0,width,height)
            var colors=["#00cfff","#ff164c","#743dff","#58efff","#ff3e75","#147bff"]
            for(var strand=0;strand<24;strand++) {
                ctx.beginPath()
                for(var i=0;i<=240;i++) {
                    var a=i/240*Math.PI*2
                    var r=radius + Math.sin(a*3+strand*Math.PI/3)*width*.038 + Math.sin(a*7+strand)*width*.007 + Math.sin(a*29+strand)*width*.0018
                    var x=cx+Math.cos(a)*r, y=cy+Math.sin(a)*r
                    if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y)
                }
                ctx.strokeStyle=colors[strand%6]
                // Explicit soft halos are portable across Qt Canvas renderers.
                ctx.globalAlpha=.055;ctx.lineWidth=18;ctx.stroke()
                ctx.globalAlpha=.12;ctx.lineWidth=9;ctx.stroke()
                ctx.globalAlpha=strand<12?.8:.4;ctx.lineWidth=strand<12?2.1:1;ctx.stroke()
                if(strand%3===0){ctx.strokeStyle="#c8faff";ctx.globalAlpha=.65;ctx.lineWidth=.7;ctx.stroke()}

            }
            // Small highlights give depth without a live particle simulation.
            for(var n=0;n<72;n++) {
                var t=n/72*Math.PI*2, rr=radius+Math.sin(t*3+n%3)*width*.035
                ctx.beginPath();ctx.arc(cx+Math.cos(t)*rr,cy+Math.sin(t)*rr,n%9===0?2.8:1.1,0,Math.PI*2)
                ctx.fillStyle=colors[n%6];ctx.globalAlpha=.8;ctx.shadowColor=ctx.fillStyle;ctx.shadowBlur=12;ctx.fill()
            }
        }
    }
    Repeater {
        model: pulses
        delegate: Item {
            id: pulse
            required property int pulseId
            required property real origin
            property real travel: 0
            readonly property real angle: (origin+travel*310)*Math.PI/180
            readonly property real radius: root.width*.435 + Math.sin(angle*3)*root.width*.025
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
