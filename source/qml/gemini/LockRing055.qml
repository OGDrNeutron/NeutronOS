import QtQuick
import QtQuick3D
import QtQuick3D.Effects
import NeutronGemini 1.0

// Lock-only refinement. Recovery's existing shared halo remains unchanged.
View3D {
    id:root
    objectName:"GeminiLockRing"
    property bool animated:true
    property string feedback:"neutral"
    property var quality:null
    property real turn:0
    property int pulseCount:0
    property int nextWave:0
    property int waveRevision:0
    readonly property int rotationPeriodMs:42000
    readonly property bool moving:visible&&animated
    readonly property vector4d wavesA:Qt.vector4d(root.ageAt(0),root.ageAt(1),root.ageAt(2),root.ageAt(3))
    readonly property vector4d wavesB:Qt.vector4d(root.ageAt(4),root.ageAt(5),root.ageAt(6),root.ageAt(7))
    readonly property vector4d wavesC:Qt.vector4d(root.ageAt(8),root.ageAt(9),root.ageAt(10),root.ageAt(11))
    readonly property vector4d wavesD:Qt.vector4d(root.ageAt(12),root.ageAt(13),root.ageAt(14),root.ageAt(15))
    function ageAt(index){var revision=root.waveRevision;var item=waves.itemAt(index);return item?item.age:2}
    function acceptedInput(){
        var wave=waves.itemAt(nextWave)
        wave.begin();nextWave=(nextWave+1)%16;pulseCount++
    }
    // Sixteen independent short wakes cover the complete fifteen-input window.
    // Only these scalar uniforms animate; no per-frame JavaScript or geometry work.
    Repeater {
        id:waves;model:16
        onItemAdded:root.waveRevision++
        Item {
            id:wave
            property real age:2
            function begin(){travel.stop();age=0;travel.start()}
            NumberAnimation{id:travel;target:wave;property:"age";from:0;to:1;duration:1150;easing.type:Easing.Linear}
        }
    }
    NumberAnimation on turn {from:0;to:360;duration:root.rotationPeriodMs;loops:Animation.Infinite;running:root.moving;easing.type:Easing.Linear}
    environment:SceneEnvironment {
        backgroundMode:SceneEnvironment.Transparent
        antialiasingMode:SceneEnvironment.MSAA;antialiasingQuality:SceneEnvironment.Medium
        lightProbe:Texture{source:"assets/atom-studio.jpg"}probeExposure:2.2
        effects:root.quality&&!root.quality.bloom?[]:[bloom]
    }
    HDRBloomTonemap{id:bloom;bloomThreshold:.8;blurFalloff:1.8}
    PerspectiveCamera{z:326;fieldOfView:39;clipNear:1;clipFar:1000}
    DirectionalLight{eulerRotation:Qt.vector3d(-30,-30,0);brightness:2;color:"#8ec8ff"}
    Repeater3D {
        model:4
        Node {
            id:railNode
            required property int index
            property real tier:1-index*.041
            scale:Qt.vector3d(tier,tier,1)
            Model {
                geometry:GeminiRingGeometry{}scale:Qt.vector3d(1,1,3)
                materials:PrincipledMaterial{baseColor:"#14364d";metalness:.94;roughness:.18;clearcoatAmount:1}
            }
            Model {
                z:3;geometry:GeminiRingGeometry{}scale:Qt.vector3d(1,1,2)
                materials:CustomMaterial {
                    shadingMode:CustomMaterial.Unshaded;cullMode:Material.NoCulling
                    vertexShader:"shaders/energy-halo.vert";fragmentShader:"shaders/lock-ring055.frag"
                    property real motion:root.turn
                    property real rail:railNode.index
                    property real mode:root.feedback==="error"?1:root.feedback==="success"?2:0
                    property vector4d wavesA:root.wavesA
                    property vector4d wavesB:root.wavesB
                    property vector4d wavesC:root.wavesC
                    property vector4d wavesD:root.wavesD
                    sourceBlend:CustomMaterial.SrcAlpha;destinationBlend:CustomMaterial.One
                }
            }
        }
    }
}
