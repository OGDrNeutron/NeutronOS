import QtQuick
import QtQuick3D
import QtQuick3D.Effects
View3D {
    id:root
    property string region:"North America"
    readonly property string regionMask:region.indexOf("Europe")>=0?"europe":region.indexOf("Asia")>=0?"asia":region.indexOf("Africa")>=0?"africa":region.indexOf("Oceania")>=0?"oceania":region.indexOf("South America")>=0?"south-america":region.indexOf("Antarctica")>=0?"antarctica":region==="Worldwide"?"world":"america"
    property var quality:null
    property bool animated:true
    property real longitude:region.indexOf("Europe")>=0?15:region.indexOf("Asia")>=0?95:region.indexOf("Africa")>=0?20:region.indexOf("Oceania")>=0?135:region.indexOf("South America")>=0?-65:region.indexOf("Antarctica")>=0?0:-100
    property real latitude:region.indexOf("Europe")>=0?48:region.indexOf("Asia")>=0?30:region.indexOf("Africa")>=0?5:region.indexOf("Oceania")>=0?-25:region.indexOf("South America")>=0?-15:region.indexOf("Antarctica")>=0?-75:35
    // Setup retains its validated decorative lighting; the world clock opts in.
    property bool astronomicalLighting:false
    property vector3d solarDirection:Qt.vector3d(1,0,0)
    property real idleAngle:0
    property real spinAngle:0 // Optional clock rotation; setup keeps the default zero.
    Behavior on longitude {NumberAnimation{duration:1400;easing.type:Easing.InOutCubic}}
    Behavior on latitude {NumberAnimation{duration:1400;easing.type:Easing.InOutCubic}}
    SequentialAnimation on idleAngle {
        running:root.visible&&root.animated;loops:Animation.Infinite
        NumberAnimation{to:1.8;duration:22000;easing.type:Easing.InOutSine}
        NumberAnimation{to:-1.8;duration:22000;easing.type:Easing.InOutSine}
    }
    environment:SceneEnvironment {backgroundMode:SceneEnvironment.Transparent;effects:root.quality&&!root.quality.bloom?[]:[earthBloom];antialiasingMode:SceneEnvironment.MSAA;antialiasingQuality:root.quality&&root.quality.level===0?SceneEnvironment.Medium:SceneEnvironment.High}
    HDRBloomTonemap {id:earthBloom;bloomThreshold:0.45;exposure:-0.35;blurFalloff:1.8}
    PerspectiveCamera {z:170;fieldOfView:38;clipNear:1;clipFar:400}
    Node {
        eulerRotation.x:root.latitude
        Node {
            eulerRotation.y:-root.longitude+root.idleAngle+root.spinAngle
        Model {
            source:"#Sphere"
            materials:CustomMaterial {
                shadingMode:CustomMaterial.Unshaded
                property real solarLighting:root.astronomicalLighting?1:0
                property vector3d solarDirection:root.solarDirection
                vertexShader:"shaders/earth.vert";fragmentShader:"shaders/earth.frag"
                property TextureInput regionMap:TextureInput {texture:Texture{source:"assets/earth-region-"+root.regionMask+".png"}}
                property vector2d selectedPoint:Qt.vector2d((root.longitude+180)/360,(90-root.latitude)/180)
                property real regionVisible:root.regionMask==="world"?0:1
                property TextureInput dayMap:TextureInput {texture:Texture{source:"assets/earth-day-"+(root.quality?root.quality.textureTier:"full")+".jpg";generateMipmaps:true;mipFilter:Texture.Linear}}
                property TextureInput nightMap:TextureInput {texture:Texture{source:"assets/earth-night-"+(root.quality?root.quality.textureTier:"full")+".jpg";generateMipmaps:true;mipFilter:Texture.Linear}}
            }
        }
        Model {
            source:"#Sphere";scale:Qt.vector3d(1.008,1.008,1.008)
            materials:CustomMaterial {
                shadingMode:CustomMaterial.Unshaded
                property real solarLighting:root.astronomicalLighting?1:0
                property vector3d solarDirection:root.solarDirection
                vertexShader:"shaders/earth.vert";fragmentShader:"shaders/clouds.frag"
                sourceBlend:CustomMaterial.SrcAlpha;destinationBlend:CustomMaterial.OneMinusSrcAlpha
                property TextureInput cloudMap:TextureInput{texture:Texture{source:"assets/earth-clouds-"+(root.quality?root.quality.textureTier:"full")+".png";generateMipmaps:true}}
            }
        }
        Model {
            source:"#Sphere";scale:Qt.vector3d(1.04,1.04,1.04)
            materials:CustomMaterial {
                shadingMode:CustomMaterial.Unshaded
                property real solarLighting:root.astronomicalLighting?1:0
                property vector3d solarDirection:root.solarDirection;vertexShader:"shaders/earth.vert";fragmentShader:"shaders/atmosphere.frag"
                sourceBlend:CustomMaterial.SrcAlpha;destinationBlend:CustomMaterial.One
                cullMode:Material.NoCulling
            }
        }
        }
    }
}
