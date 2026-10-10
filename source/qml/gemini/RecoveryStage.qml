import QtQuick
import QtQuick3D
import QtQuick3D.Effects
import NeutronGemini 1.0
// Recovery has its own recessed metallic deck; no Setup stage is instantiated.
View3D {
 id:root
 property var quality:null
 environment:SceneEnvironment{
  backgroundMode:SceneEnvironment.Transparent
  lightProbe:Texture{source:"assets/atom-studio.jpg"}
  probeExposure:.25
  antialiasingMode:SceneEnvironment.MSAA
  effects:root.quality&&!root.quality.bloom?[]:[bloom]
 }
 HDRBloomTonemap{id:bloom;bloomThreshold:1.2;blurFalloff:1.1}
 OrthographicCamera{z:760;y:190;eulerRotation.x:-14;horizontalMagnification:Math.max(1,root.width)/950;verticalMagnification:Math.max(1,root.height)/160;clipFar:1800}
 DirectionalLight{eulerRotation:Qt.vector3d(-38,-25,0);brightness:1.3;color:"#729ac9"}
 PointLight{x:-340;y:80;z:50;color:"#ff1637";brightness:35;quadraticFade:.1}
 PointLight{x:340;y:80;z:50;color:"#009bff";brightness:35;quadraticFade:.1}
 Model{source:"#Cube";y:-22;scale:Qt.vector3d(11,.12,8);materials:PrincipledMaterial{baseColor:"#02040b";metalness:.6;roughness:.35}}
 Repeater3D{model:12
  Model{required property int index;x:(index-5.5)*88;y:-15;z:120
   source:"#Cube";scale:Qt.vector3d(.81,.022,7)
   materials:PrincipledMaterial{baseColor:index%2?"#101b2b":"#060a16";metalness:.95;roughness:.2}
  }
 }
 Repeater3D{model:3
  Model{required property int index;y:-12+index;eulerRotation.x:90;geometry:GeminiRingGeometry{}scale:Qt.vector3d(2.3+index*.58,2.3+index*.58,.35)
   materials:PrincipledMaterial{baseColor:index===1?"#b60026":"#004b9a";metalness:.9;roughness:.2;emissiveFactor:index===1?Qt.vector3d(.9,0,.02):Qt.vector3d(0,.13,1.2)}
  }
 }
 Repeater3D{model:8
  Model{required property int index;x:(index-3.5)*135;y:-10;z:-130;source:"#Cube";scale:Qt.vector3d(.42,.023,.08)
   materials:PrincipledMaterial{baseColor:index%2?"#009cff":"#ff0028";emissiveFactor:index%2?Qt.vector3d(0,.5,3):Qt.vector3d(3,0,.02)}
  }
 }
}
