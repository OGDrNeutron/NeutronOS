import QtQuick
import QtQuick3D
import QtQuick3D.Effects
import QtQuick3D.Particles3D
import NeutronGemini 1.0
// One Gemini energy system shared by Lock and Recovery; Setup stays unchanged.
View3D {
    id:root
    objectName:"GeminiEnergyAtom"
    property bool animated:true
    property bool nucleusVisible:true
    property string feedback:"neutral"
    property var quality:null
    readonly property bool moving:visible&&animated
    function energy(index) {
        if(feedback==="error")return Qt.vector3d(4.0,.006,.02)
        if(feedback==="success")return Qt.vector3d(.008,3.2,.5)
        return index===1?Qt.vector3d(4,.008,.08):Qt.vector3d(.005,.65,4)
    }
    environment:SceneEnvironment {
        backgroundMode:SceneEnvironment.Transparent
        antialiasingMode:SceneEnvironment.MSAA
        antialiasingQuality:SceneEnvironment.Medium
        lightProbe:Texture{source:"assets/atom-studio.jpg"}
        probeExposure:2.2
        effects:root.quality&&!root.quality.bloom?[]:[bloom]
    }
    HDRBloomTonemap{id:bloom;bloomThreshold:.65;exposure:0;blurFalloff:1.8}
    PerspectiveCamera{z:420;fieldOfView:39;clipNear:1;clipFar:1500}
    DirectionalLight{eulerRotation:Qt.vector3d(-30,-20,0);brightness:1.6;color:"#d3e8ff"}
    PointLight{x:-170;y:100;z:180;color:root.feedback==="success"?"#00ff88":"#009dff";brightness:24;quadraticFade:.05}
    PointLight{x:170;y:-60;z:150;color:root.feedback==="success"?"#00ff88":"#ff163c";brightness:20;quadraticFade:.05}
    Node {
        eulerRotation:Qt.vector3d(-7,10,0)
        Model {
            visible:root.nucleusVisible;source:"#Sphere";scale:Qt.vector3d(.49,.49,.49)
            materials:PrincipledMaterial{baseColor:"#83bce6";metalness:.85;roughness:.16;emissiveFactor:Qt.vector3d(.02,.14,.4);clearcoatAmount:1;clearcoatRoughnessAmount:.06}
        }
        Repeater3D {
            model:3
            delegate:Node {
                id:orbit
                required property int index
                property real phase:index*123
                property vector3d tint:root.energy(index)
                eulerRotation:Qt.vector3d(orbit.index===0?24:orbit.index===1?-37:70,orbit.index===2?36:12,orbit.index*58)
                NumberAnimation on phase{from:orbit.index*123;to:orbit.index*123+360;duration:3800+orbit.index*1100;loops:Animation.Infinite;running:root.moving}
                // Only the moving heads and their fading wakes are rendered.
                Repeater3D {
                    model:root.quality&&root.quality.level===0?1:3
                    delegate:Model {
                        required property int index
                        geometry:GeminiRingGeometry{}
                        scale:Qt.vector3d(1+index*.009,1+index*.009,1+index*1.1)
                        materials:CustomMaterial {
                            shadingMode:CustomMaterial.Unshaded;cullMode:Material.NoCulling
                            vertexShader:"shaders/atom-energy.vert";fragmentShader:"shaders/energy-trail.frag"
                            sourceBlend:CustomMaterial.SrcAlpha;destinationBlend:CustomMaterial.One
                            property real orbitPhase:orbit.phase
                            property real wakeLength:.29-orbit.index*.02
                            property real halo:index===0?1.0:.22
                            property vector3d energyColor:orbit.tint
                        }
                    }
                }
                Repeater3D {
                    model:2
                    delegate:Node {
                        required property int index
                        property real angle:(orbit.phase+index*180)*Math.PI/180
                        x:110*Math.cos(angle);y:110*Math.sin(angle)
                        Model {
                            source:"#Sphere";scale:Qt.vector3d(.16,.16,.16)
                            materials:PrincipledMaterial{baseColor:"#efffff";metalness:.78;roughness:.08;emissiveFactor:Qt.vector3d(orbit.tint.x*.6,orbit.tint.y*.6,orbit.tint.z*.6)}
                        }
                        Model {
                            source:"#Sphere";scale:Qt.vector3d(.22,.22,.22)
                            materials:PrincipledMaterial{baseColor:root.feedback==="error"?"#ff2040":root.feedback==="success"?"#00ff8b":orbit.index===1?"#ff2240":"#009dff";opacity:.18;lighting:PrincipledMaterial.NoLighting}
                        }
                    }
                }
            }
        }
        ParticleSystem3D {
            id:particles;running:root.moving
            SpriteParticle3D {
                id:sparks;maxAmount:root.quality?root.quality.particleCount:64
                color:root.feedback==="error"?"#ff1740":root.feedback==="success"?"#00ff96":"#25baff"
                sprite:Texture{source:"assets/energy-spark.png"}blendMode:SpriteParticle3D.Screen;billboard:true
                fadeInDuration:150;fadeOutDuration:900
            }
            ParticleEmitter3D {
                particle:sparks;emitRate:root.moving?(root.quality?root.quality.particleCount/3:20):0;lifeSpan:2600
                particleScale:.75;particleScaleVariation:.45
                shape:ParticleShape3D{type:ParticleShape3D.Sphere;extents:Qt.vector3d(118,118,35)}
                velocity:VectorDirection3D{direction:Qt.vector3d(0,2,0);directionVariation:Qt.vector3d(12,8,8)}
            }
        }
    }
}
