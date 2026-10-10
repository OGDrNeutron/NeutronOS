import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
TestCase {
    id:test;name:"GeminiFractureRendering";when:windowShown
    width:1280;height:720;visible:true
    Rectangle{anchors.fill:parent;color:"#B82020";Text{anchors.centerIn:parent;text:"LIVE UNDERLAY";color:"white";font.pixelSize:64}}
    Rectangle{id:paper;anchors.fill:parent;color:"#0044FF"
        Repeater{model:24;Rectangle{required property int index;x:index%6*213;y:Math.floor(index/6)*180;width:106;height:90;color:"#00CCFF"}}
        Text{anchors.centerIn:parent;text:"GEMINI FINAL SETUP SURFACE";color:"white";font.pixelSize:48}
    }
    Gemini.GeminiFracture{id:fracture;anchors.fill:parent}
    function test_fragments_reveal_live_underlay(){
        fracture.begin(paper)
        tryCompare(fracture,"started",true,10000)
        var fall=findChild(fracture,"geminiFractureFall")
        verify(fall!==null);fall.pause()
        var camera=findChild(fracture,"geminiFractureCamera")
        console.info("FRACTURE_CAMERA",camera.horizontalMagnification,camera.verticalMagnification,fracture.width,fracture.height)
        var times=[0,0.2,0.5,0.8,1.1,1.5,2.2]
        for(var i=0;i<times.length;i++){
            fracture.elapsed=times[i];waitForRendering(fracture);wait(80)
            var frame=grabImage(test)
            frame.save("/tmp/gemini-fracture-probe-"+i+".png")
            var surfaceSamples=0
            for(var y=20;y<700;y+=40)for(var x=20;x<1260;x+=40){var c=frame.pixel(x,y);if(c.b>0.5&&c.r<0.3)surfaceSamples++}
            console.info("FRACTURE_SURFACE_SAMPLES",times[i],surfaceSamples)
            if(i===0)verify(surfaceSamples>500,"Frozen setup surface must cover the viewport before impact")
            if(i===3)verify(surfaceSamples>20&&surfaceSamples<500,"Irregular fragments must reveal partial live underlay")
            if(i===6)compare(surfaceSamples,0,"All fragments must fall off screen")
        }
    }
}
