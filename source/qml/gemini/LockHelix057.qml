import QtQuick
import QtQuick3D
import QtQuick3D.Effects
import NeutronGemini 1.0

// Static 3D tubular strands share one orbit, with actual depth at every crossing.
// Only their parent transform animates; accepted inputs own independent transient arcs.
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
    // One inexpensive annular pass supplies soft plasma emission around the real tubes.
    ShaderEffect {
        anchors.fill:parent
        property real phase:root.turn/360
        fragmentShader:Qt.resolvedUrl("shaders/lock-helix057.frag.qsb")
    }
    View3D {
        id:helixView
        objectName:"GeminiLockHelix3D"
        anchors.fill:parent
        environment:SceneEnvironment {
            backgroundMode:SceneEnvironment.Transparent
            antialiasingMode:SceneEnvironment.MSAA
            antialiasingQuality:SceneEnvironment.Medium
            lightProbe:Texture{source:"assets/atom-studio.jpg"}
            probeExposure:1.1
            effects:root.quality&&!root.quality.bloom?[]:[helixBloom]
        }
        HDRBloomTonemap{id:helixBloom;bloomThreshold:1.0;exposure:0;blurFalloff:1.6}
        OrthographicCamera{z:500;clipNear:1;clipFar:1000;horizontalMagnification:Math.max(.001,root.width/660);verticalMagnification:Math.max(.001,root.height/660)}
        DirectionalLight{eulerRotation:Qt.vector3d(-35,-25,0);brightness:1.8;color:"#e2ecff"}
        PointLight{x:-180;y:180;z:160;brightness:18;quadraticFade:.08;color:"#75c9ff"}
        GeminiHelixGeometry{id:tube;tubeRadius:3.8}
        GeminiHelixGeometry{id:blueRungs;structure:1}
        GeminiHelixGeometry{id:redRungs;structure:2}
        GeminiHelixGeometry{id:molecules;structure:3}
        GeminiHelixGeometry{id:core;tubeRadius:.65}
        Node {
            eulerRotation.z:-root.turn
            Model{geometry:tube;materials:PrincipledMaterial{baseColor:"#006bdd";metalness:.55;roughness:.23;emissiveFactor:Qt.vector3d(.005,.9,3.5);clearcoatAmount:1}}
            Model{geometry:tube;eulerRotation.z:18;materials:PrincipledMaterial{baseColor:"#e80024";metalness:.55;roughness:.23;emissiveFactor:Qt.vector3d(3.5,.008,.08);clearcoatAmount:1}}
            Model{geometry:blueRungs;materials:PrincipledMaterial{baseColor:"#0754a1";metalness:.7;roughness:.2;emissiveFactor:Qt.vector3d(.005,.2,.65);clearcoatAmount:1}}
            Model{geometry:redRungs;materials:PrincipledMaterial{baseColor:"#ae0627";metalness:.7;roughness:.2;emissiveFactor:Qt.vector3d(.65,.003,.05);clearcoatAmount:1}}
            Model{geometry:molecules;materials:PrincipledMaterial{baseColor:"#0064c8";metalness:.4;roughness:.16;emissiveFactor:Qt.vector3d(.005,.5,1.9);clearcoatAmount:1}}
            Model{geometry:molecules;eulerRotation.z:18;materials:PrincipledMaterial{baseColor:"#dc062b";metalness:.4;roughness:.16;emissiveFactor:Qt.vector3d(1.9,.004,.08);clearcoatAmount:1}}
            Model{geometry:core;materials:PrincipledMaterial{baseColor:"#d6f5ff";emissiveFactor:Qt.vector3d(.6,2.7,5.)}}
            Model{geometry:core;eulerRotation.z:18;materials:PrincipledMaterial{baseColor:"#ffe5ed";emissiveFactor:Qt.vector3d(5.,.6,1.2)}}
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
            // A small tangential shader lights both strands along an arc; no dot sprites.
            x: root.width/2+Math.cos(angle)*root.width*(260/660)-width/2
            y: root.height/2+Math.sin(angle)*root.height*(260/660)-height/2
            width: 128; height: 120
            rotation: angle*180/Math.PI
            opacity: Math.pow(1-travel, .75)
            ShaderEffect {
                anchors.fill:parent
                property real flowAngle:pulse.angle-root.turn*Math.PI/180
                property vector2d extent:Qt.vector2d(pulse.width/root.width,pulse.height/root.height)
                fragmentShader:Qt.resolvedUrl("shaders/lock-helix-pulse057.frag.qsb")
            }
            NumberAnimation on travel {
                from: 0; to: 1; duration: 1800; running: root.running
                easing.type: Easing.Linear
                onFinished: root.removePulse(pulse.pulseId)
            }
        }
    }
}
