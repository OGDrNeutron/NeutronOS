import QtQuick
import QtQuick3D
import QtQuick3D.Effects
import QtQuick3D.Particles3D
import NeutronGemini 1.0

View3D {
    id: root
    property bool animated: true
    property var quality: null
    readonly property bool moving: visible && animated
    environment: SceneEnvironment {
        backgroundMode: SceneEnvironment.Transparent
        antialiasingMode: SceneEnvironment.MSAA
        antialiasingQuality: root.quality && root.quality.level === 0 ? SceneEnvironment.Medium : SceneEnvironment.High
        lightProbe: Texture { source: "assets/atom-studio.jpg" }
        probeExposure: 3.0
        effects: root.quality && !root.quality.bloom ? [] : [bloom]
    }
    HDRBloomTonemap { id: bloom; bloomThreshold: 0.4; exposure: 0; blurFalloff: 1.5 }
    PerspectiveCamera { z: 420; fieldOfView: 39; clipNear: 1; clipFar: 1200 }
    PointLight { x:-180; y:100; z:180; color:"#0088ff"; brightness:26; quadraticFade:0.05 }
    PointLight { x:180; y:-60; z:130; color:"#ff153a"; brightness:22; quadraticFade:0.05 }
    DirectionalLight { eulerRotation.x:-30; eulerRotation.y:-20; brightness:1.2; color:"#d3e8ff" }
    Node {
        eulerRotation: Qt.vector3d(-12,8,0)
        Model {
            source:"#Sphere"; scale:Qt.vector3d(0.53,0.53,0.53)
            materials: PrincipledMaterial {
                baseColor:"#e0eaff";metalness:0.82;roughness:0.13
                emissiveFactor:Qt.vector3d(0.005,0.01,0.02)
                clearcoatAmount:1;clearcoatRoughnessAmount:0.075
            }
        }
        Repeater3D {
            model:3
            delegate: Node {
                id:orbit
                required property int index
                property real phase: index*115
                eulerRotation.z:index*60+8*Math.sin(phase*Math.PI/180)
                NumberAnimation on phase {
                    from:orbit.index*115;to:orbit.index*115+360;duration:14000+orbit.index*3200
                    loops:Animation.Infinite;running:root.moving
                }
                Node {
                    eulerRotation:Qt.vector3d(65+4*Math.cos(orbit.phase*Math.PI/180),8*Math.sin(orbit.phase*Math.PI/180),0)
                    Model {
                        geometry:GeminiRingGeometry {}
                        materials:PrincipledMaterial {
                            baseColor:orbit.index===1?"#ff1535":"#12baff";metalness:0.65;roughness:0.2
                            emissiveFactor:orbit.index===1?Qt.vector3d(3,0.002,0.01):Qt.vector3d(0.001,0.03,3)
                        }
                    }
                    Repeater3D {
                        model:root.quality&&root.quality.level===0?0:2
                        delegate:Model {
                            required property int index
                            geometry:GeminiRingGeometry {}
                            scale:Qt.vector3d(1.012+index*.012,1.012+index*.012,1)
                            materials:CustomMaterial {
                                shadingMode:CustomMaterial.Unshaded
                                vertexShader:"shaders/atom-energy.vert";fragmentShader:"shaders/atom-energy.frag"
                                sourceBlend:CustomMaterial.SrcAlpha;destinationBlend:CustomMaterial.One
                                property real orbitPhase:orbit.phase+index*90
                                property vector3d energyColor:orbit.index===1?Qt.vector3d(3,.005,.03):Qt.vector3d(.005,.16,3)
                            }
                        }
                    }
                    Repeater3D {
                        model:2
                        delegate:Model {
                            required property int index
                            property real angle:(orbit.phase+index*180)*Math.PI/180
                            x:110*Math.cos(angle);y:110*Math.sin(angle)
                            source:"#Sphere";scale:Qt.vector3d(0.20,0.20,0.20)
                            materials:PrincipledMaterial {
                                baseColor:orbit.index===1?"#ffc1b9":"#b6faff";metalness:0.8;roughness:0.1
                                emissiveFactor:orbit.index===1?Qt.vector3d(0.6,0.01,0.02):Qt.vector3d(0.006,0.2,0.6)
                            }
                        }
                    }
                }
            }
        }
        ParticleSystem3D {
            id:particles
            running:root.moving
            SpriteParticle3D {
                id:sparks;maxAmount:root.quality?root.quality.particleCount:32
                color:"#29b5ff";colorVariation:Qt.vector4d(0.4,0.1,0.1,0)
                fadeInDuration:200;fadeOutDuration:800
                sprite:Texture {source:"assets/energy-spark.png"}
                blendMode:SpriteParticle3D.Screen
                billboard:true
            }
            ParticleEmitter3D {
                particle:sparks;emitRate:root.moving?(root.quality?root.quality.particleCount/4:8):0;lifeSpan:4000
                particleScale:1.2;particleScaleVariation:0.6
                shape:ParticleShape3D {type:ParticleShape3D.Sphere;extents:Qt.vector3d(115,115,80)}
                velocity:VectorDirection3D {direction:Qt.vector3d(0,4,0);directionVariation:Qt.vector3d(10,6,10)}
            }
        }
    }
}
