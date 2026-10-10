import QtQuick
import QtQuick3D
import NeutronGemini 1.0
Item {
    id:root
    objectName:"GeminiUnlockTransition"
    property Item captureSource:null
    property real originX:.5
    property real originY:.535
    property real elapsed:0
    property bool started:false
    property int warmFrames:0
    readonly property bool snapshotRetained:capture.sourceItem!==null
    property url coreAvatarSource:""
    property int columns:24
    GeminiRenderQuality{id:renderQuality;active:root.captureSource!==null&&root.captureSource.visible&&!root.started}
    readonly property string stage:!started?"idle":elapsed<.35?"crack":elapsed<.8?"separate":elapsed<2.2?"swirl":elapsed<2.65?"consolidate":elapsed<2.95?"compress":elapsed<3.45?"explode":"reveal"
    signal captureReady(int shardCount)
    signal captureCommitted()
    signal fractureStarted(int shardCount)
    signal transitionFailed(string reason)
    signal finished(bool fallbackUsed)
    visible:started||warmup.running
    function start(){
        if(started||warmup.running)return
        elapsed=0;warmFrames=0;columns=renderQuality.fractureColumns
        coreAvatarSource=captureSource&&captureSource.item&&typeof captureSource.item.currentAvatarSource==="function"?captureSource.item.currentAvatarSource():""
        capture.sourceItem=captureSource;capture.scheduleUpdate();warmup.start()
    }
    function reset(){timeline.stop();warmup.stop();started=false;elapsed=0;capture.sourceItem=null;coreAvatarSource=""}
    ShaderEffectSource{id:capture;anchors.fill:parent;live:false;visible:false;hideSource:false;recursive:false}
    FrameAnimation {
        id:warmup;running:false
        onTriggered:{
            root.warmFrames++
            if(root.warmFrames<2)return
            stop();root.started=true
            root.captureReady(root.columns*Math.round(root.columns*941/1672))
            root.captureCommitted();root.fractureStarted(root.columns*Math.round(root.columns*941/1672))
            timeline.start()
        }
    }
    View3D {
        anchors.fill:parent;visible:root.started
        environment:SceneEnvironment{backgroundMode:SceneEnvironment.Transparent;antialiasingMode:SceneEnvironment.MSAA;antialiasingQuality:SceneEnvironment.Medium}
        OrthographicCamera{z:1000;clipNear:1;clipFar:10000;horizontalMagnification:Math.max(1,root.width)/1672;verticalMagnification:Math.max(1,root.height)/941}
        Model {
            geometry:GeminiFractureGeometry{columns:root.columns}
            materials:CustomMaterial {
                shadingMode:CustomMaterial.Unshaded;cullMode:Material.NoCulling
                vertexShader:"shaders/unlock-swirl.vert";fragmentShader:"shaders/unlock-swirl.frag"
                property real elapsed:root.elapsed
                property vector2d impact:Qt.vector2d(root.originX,root.originY)
                property TextureInput surfaceMap:TextureInput{texture:Texture{sourceItem:capture}}
                sourceBlend:CustomMaterial.SrcAlpha;destinationBlend:CustomMaterial.OneMinusSrcAlpha
            }
        }
    }
    Rectangle {
        anchors.centerIn:parent;anchors.horizontalCenterOffset:(root.originX-.5)*root.width;anchors.verticalCenterOffset:(root.originY-.5)*root.height
        width:120;height:120;radius:60;color:"#d5ffff";border.color:"#00ff9d";border.width:4
        visible:root.started&&root.elapsed>2.2
        opacity:root.elapsed<2.95?Math.min(1,(root.elapsed-2.2)*3):Math.max(0,1-(root.elapsed-2.95)*2.5)
        scale:root.elapsed<2.95?Math.max(.18,1-(root.elapsed-2.2)):1+Math.pow(Math.max(0,root.elapsed-2.95),.7)*16
        Image{id:coreAvatar;anchors.fill:parent;anchors.margins:14;source:root.coreAvatarSource;fillMode:Image.PreserveAspectFit;visible:root.elapsed<2.95&&status===Image.Ready}
        Item{anchors.fill:parent;visible:root.elapsed<2.95&&coreAvatar.status!==Image.Ready
            Rectangle{anchors.horizontalCenter:parent.horizontalCenter;y:26;width:31;height:31;radius:16;color:"#06364b"}
            Rectangle{anchors.horizontalCenter:parent.horizontalCenter;y:64;width:55;height:30;radius:12;color:"#06364b"}
        }
    }
    Repeater {
        model:root.columns*2
        Rectangle {
            required property int index
            property real theta:index*2.399963
            property real burst:Math.max(0,root.elapsed-2.95)
            width:3;height:24+index%6*8;radius:2;color:index%3===0?"#ff2850":index%2?"#00ff9d":"#27cdff"
            x:root.originX*root.width+Math.cos(theta)*burst*root.width*(.5+index%4*.18)
            y:root.originY*root.height+Math.sin(theta)*burst*root.height*(.6+index%5*.18)
            rotation:theta*180/Math.PI-90
            visible:root.started&&burst>0
            opacity:Math.max(0,1-burst*1.4)
            scale:1+burst*2
        }
    }
    NumberAnimation{id:timeline;target:root;property:"elapsed";from:0;to:3.8;duration:3800;onFinished:{root.started=false;capture.sourceItem=null;root.coreAvatarSource="";root.finished(false)}}
}
