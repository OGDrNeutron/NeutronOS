import QtQuick
import QtQuick3D
import QtQuick3D.Effects
import NeutronGemini 1.0
View3D {
    id:root
    property var quality:null
    environment:SceneEnvironment {
        backgroundMode:SceneEnvironment.Transparent
        antialiasingMode:SceneEnvironment.MSAA
        antialiasingQuality:SceneEnvironment.Medium
        lightProbe:Texture{source:"assets/atom-studio.jpg"}
        probeExposure:1.4
        effects:root.quality&&!root.quality.bloom?[]:[bloom]
    }
    HDRBloomTonemap{id:bloom;bloomThreshold:0.7;exposure:0;blurFalloff:1.5}
    OrthographicCamera{position:Qt.vector3d(0,75,710);eulerRotation.x:-6;horizontalMagnification:Math.max(1,root.width)/950;verticalMagnification:Math.max(1,root.height)/180;clipFar:1500}
    DirectionalLight{eulerRotation:Qt.vector3d(-45,-25,0);brightness:2;color:"#B6D8FF"}
    PointLight{x:-200;y:80;z:70;color:"#FF0030";brightness:90;quadraticFade:0.08}
    PointLight{x:200;y:80;z:70;color:"#008CFF";brightness:100;quadraticFade:0.08}
    Model{source:"#Cylinder";y:-12;scale:Qt.vector3d(9,0.4,9);materials:PrincipledMaterial{baseColor:"#111B32";metalness:0.98;roughness:0.23}}
    Model{source:"#Cylinder";y:-30;scale:Qt.vector3d(9.3,0.07,9.3);materials:PrincipledMaterial{baseColor:"#22304A";metalness:.9;roughness:.3}}
    Repeater3D{model:6
        Model{required property int index;y:9+index*0.2;eulerRotation.x:90;scale:Qt.vector3d(1.5+index*0.48,1.5+index*0.48,1)
            geometry:GeminiRingGeometry{}
            materials:PrincipledMaterial{baseColor:index%3===0?"#FF123A":"#009FFF";metalness:0.7;roughness:0.2;emissiveFactor:index%3===0?Qt.vector3d(2,0.001,0.02):Qt.vector3d(0.001,0.08,2)}
        }
    }
}
