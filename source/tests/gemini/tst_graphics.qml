import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
TestCase {
    id:test
    name:"GeminiGraphics"
    when:windowShown
    width:800;height:800;visible:true
    Gemini.GeminiRenderQuality {id:renderQuality;active:false}
    Rectangle {anchors.fill:parent;color:"#01040B"}
    Loader {id:render;anchors.fill:parent}
    Component {id:atom;Gemini.NeutronAtom{quality:renderQuality;animated:false}}
    Component {id:earth;Gemini.TimezoneEarth{quality:renderQuality;animated:false}}
    function cleanup(){render.sourceComponent=null}
    function test_rapid_graphics_lifecycle() {
        for(var i=0;i<16;i++) {
            render.sourceComponent=i%2?earth:atom
            tryCompare(render,"status",Loader.Ready)
            waitForRendering(render)
            render.sourceComponent=null
            wait(20)
        }
    }
    function test_shared_atom_renders(){
        render.sourceComponent=atom
        tryCompare(render,"status",Loader.Ready)
        waitForRendering(render)
        var result=null
        tryVerify(function(){result=grabImage(render);return result.pixel(Math.floor(result.width/2),Math.floor(result.height/2))!==result.pixel(5,5)},20000,"Atom must render after rapid page lifecycle")
        verify(result.width>0)
        result.save("/tmp/gemini-graphics-atom.png")
    }
    function test_earth_renders_and_region_interpolates(){
        render.sourceComponent=earth
        tryCompare(render,"status",Loader.Ready)
        wait(300)
        var old=render.item.longitude
        render.item.region="Europe"
        console.info("Region animation starts at",old,"for",render.item.region)
        tryVerify(function(){return render.item.longitude!==old},1000)
        verify(Math.abs(render.item.longitude-15)>0.1)
        tryCompare(render.item,"longitude",15,10000)
        var result=grabImage(render)
        verify(result.pixel(400,400) !== result.pixel(5,5), "Earth must render a sphere, not a blank surface")
        result.save("/tmp/gemini-graphics-earth.png")
    }
}
