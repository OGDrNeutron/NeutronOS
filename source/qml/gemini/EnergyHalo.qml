import QtQuick
import QtQuick3D
import QtQuick3D.Effects
import NeutronGemini 1.0
// Metallic hardware rails and segmented energy are rendered as one GPU scene.
View3D {
    id:root
    property bool animated:true
    property string feedback:"neutral"
    property var quality:null
    property real turn:0
    NumberAnimation on turn{from:0;to:360;duration:42000;loops:Animation.Infinite;running:root.visible&&root.animated}
    environment:SceneEnvironment {
        backgroundMode:SceneEnvironment.Transparent
        antialiasingMode:SceneEnvironment.MSAA;antialiasingQuality:SceneEnvironment.Medium
        lightProbe:Texture{source:"assets/atom-studio.jpg"}
        probeExposure:2.2
        effects:root.quality&&!root.quality.bloom?[]:[bloom]
    }
    HDRBloomTonemap{id:bloom;bloomThreshold:.55;blurFalloff:1.7}
    PerspectiveCamera{z:326;fieldOfView:39;clipNear:1;clipFar:1000}
    DirectionalLight{eulerRotation:Qt.vector3d(-30,-30,0);brightness:2;color:"#8ec8ff"}
    PointLight{x:80;y:100;z:180;color:"#00caff";brightness:20;quadraticFade:.1}
    Repeater3D {
        model:4
        Node {
            id:railNode
            required property int index
            property real tier:1-index*.045
            scale:Qt.vector3d(tier,tier,1)
            Model {
                geometry:GeminiRingGeometry{}
                scale:Qt.vector3d(1,1,3)
                materials:PrincipledMaterial{baseColor:"#174469";metalness:.94;roughness:.18;clearcoatAmount:1}
            }
            Model {
                z:3;geometry:GeminiRingGeometry{}
                scale:Qt.vector3d(1,1,2)
                materials:CustomMaterial {
                    shadingMode:CustomMaterial.Unshaded;cullMode:Material.NoCulling
                    vertexShader:"shaders/energy-halo.vert";fragmentShader:"shaders/energy-halo.frag"
                    property real motion:root.turn*(railNode.index%2?-.8:1)
                    property real rail:railNode.index
                    property real mode:root.feedback==="error"?1:root.feedback==="success"?2:0
                    sourceBlend:CustomMaterial.SrcAlpha;destinationBlend:CustomMaterial.One
                }
            }
        }
    }
}
