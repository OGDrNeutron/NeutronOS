import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
TestCase {
 id:test;name:"Gemini055SolarGPU";when:windowShown;visible:true;width:1920;height:1080
 Rectangle{anchors.fill:parent;color:"#02060d"}
 property date instant:new Date("2026-03-20T03:00:00Z")
 readonly property var solar:worldClockTestBackend.solarPosition(instant)
 Gemini.TimezoneEarth{id:earth;x:600;y:120;width:720;height:720;region:"Worldwide";latitude:35.65;longitude:139.74;animated:false;astronomicalLighting:true;solarDirection:Qt.vector3d(test.solar.x,test.solar.y,test.solar.z)}
 function test_solar_geometry_and_emission(){
  wait(1650)
  var stats={}
  for(var state of [{name:"day",utc:"2026-03-20T03:00:00Z"},{name:"night",utc:"2026-03-20T15:00:00Z"},{name:"mixed",utc:"2026-03-20T09:00:00Z"}]){
   instant=new Date(state.utc);wait(350);waitForRendering(earth);var capture=grabImage(test);capture.save("/tmp/gemini-solar-"+state.name+".png")
   var total=0,count=0,warm=0,max=0
   for(var y=210;y<750;y+=2)for(var x=690;x<1230;x+=2){var dx=x-960,dy=y-480;if(dx*dx+dy*dy>260*260)continue;var r=capture.red(x,y),g=capture.green(x,y),b=capture.blue(x,y);total+=(r+g+b)/3;count++;if(r>80&&r>g*1.12&&g>b*1.2)warm++;max=Math.max(max,r)}
   stats[state.name]={mean:total/count,warmPixels:warm,samples:count,maximumRed:max}
  }
  verify(stats.day.mean>stats.night.mean*2,"Night terrain is naturally darker than day: "+JSON.stringify(stats))
  verify(stats.night.warmPixels>30,"Populated night region emits visible warm city lights: "+JSON.stringify(stats))
  console.info("SOLAR_GPU_STATISTICS",JSON.stringify(stats))
 }
}
