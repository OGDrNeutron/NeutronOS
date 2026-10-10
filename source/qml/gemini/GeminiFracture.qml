import QtQuick
import QtQuick3D
import NeutronGemini 1.0
Item {
    id:root
    property var quality:null
    property real elapsed:0
    property bool started:false
    property int warmFrames:0
    signal finished()
    function begin(surface) {
        capture.sourceItem=surface
        capture.scheduleUpdate()
        warmup.running=true
    }
    ShaderEffectSource {id:capture;anchors.fill:parent;live:false;hideSource:root.started;visible:false;recursive:false}
    FrameAnimation {
        id:warmup;running:false
        onTriggered:{root.warmFrames++;if(root.warmFrames>=2){running=false;root.started=true;fall.start()}}
    }
    View3D {
        anchors.fill:parent;visible:root.started
        environment:SceneEnvironment {backgroundMode:SceneEnvironment.Transparent;antialiasingMode:SceneEnvironment.MSAA;antialiasingQuality:SceneEnvironment.Medium}
        OrthographicCamera {objectName:"geminiFractureCamera";z:1000;clipNear:1;clipFar:10000;horizontalMagnification:Math.max(1,root.width)/1672;verticalMagnification:Math.max(1,root.height)/941}
        Model {
            geometry:GeminiFractureGeometry {columns:root.quality?root.quality.fractureColumns:24}
            materials:CustomMaterial {
                shadingMode:CustomMaterial.Unshaded;cullMode:Material.NoCulling
                vertexShader:"shaders/fracture.vert";fragmentShader:"shaders/fracture.frag"
                property real elapsed:root.elapsed
                property TextureInput surfaceMap:TextureInput {texture:Texture{sourceItem:capture}}
                sourceBlend:CustomMaterial.SrcAlpha;destinationBlend:CustomMaterial.OneMinusSrcAlpha
            }
        }
    }
    NumberAnimation {id:fall;objectName:"geminiFractureFall";target:root;property:"elapsed";from:0;to:2.3;duration:2300;onFinished:root.finished()}
}
