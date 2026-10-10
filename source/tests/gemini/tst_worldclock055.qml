import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
TestCase {
 id:test;name:"Gemini055WorldClock";when:windowShown;visible:true;width:1920;height:1080
 QtObject {
  id:host
  property bool loginSuccess:false
  property bool animationsEnabled:true
  property bool cardArmed:false
  property string lockscreenFocus:"user"
  property string errorText:""
  property string statusText:"Profile ready"
  property var inputTokens:[]
  property var controllerBackend:null
  property real unlockRippleScale:1
  property real unlockRippleOpacity:0
  function greetingPrefix(){return "GOOD AFTERNOON."}
  function currentDisplayName(){return "Gemini VM"}
  function currentAvatarSource(){return ""}
  function selectFocused(){cardArmed=true}
  function setLockscreenFocus(value){if(!cardArmed)lockscreenFocus=value}
  function beginClockTimezoneAuthentication(){lockscreenFocus="user";cardArmed=true}
  function loginSecurityIsSecure(){return false}
  function isLockedOut(){return false}
  function formatTime(t){return "0:00"}
  function lockoutSecondsRemaining(){return 0}
 }
 Rectangle{anchors.fill:parent;color:"#02060d"}
 Image{anchors.fill:parent;source:"../../themes/Default/background.png";fillMode:Image.PreserveAspectCrop}
 Rectangle{anchors.fill:parent;color:"#02060d";opacity:.22}
 Gemini.LockPresentation{id:lock;anchors.fill:parent;host:host;clockBackend:worldClockTestBackend}
 function find(item,name){if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var hit=find(c[i],name);if(hit)return hit}return null}
 function init(){worldClockTestBackend.setLockscreenClockVisible(true);worldClockTestBackend.setLockscreenWelcomeVisible(true);host.cardArmed=false;host.lockscreenFocus="user"}
 function test_a_clock_geometry_and_world_regions(){
  var clock=find(lock,"GeminiLockClock"),earth=find(lock,"GeminiLockClockEarth"),planet=find(lock,"GeminiClockPlanetInstrument"),housing=find(lock,"GeminiClockHousing"),card=find(lock,"GeminiLockUserIcon")
  compare(clock.x,1211);compare(clock.y,57);compare(planet.x,244);compare(planet.y,0);compare(planet.width,170);compare(earth.width,180);compare(housing.x,12);compare(housing.width,372*.75);compare(card.width,170)
  verify(planet.z>housing.z);verify(housing.x+housing.width>planet.x+37.5);verify(housing.x+housing.width<planet.x+planet.width/2)
  host.lockscreenFocus="clock";verify(clock.focused)
  var zone=worldClockTestBackend.timezone;clock.returnToLocal();compare(clock.displayedTimezone,zone)
  var seen={};for(var i=0;i<worldClockTestBackend.worldClockRegions.length;i++){lock.handleClockAction("primary");seen[clock.displayedTimezone]=true;compare(clock.localTime,worldClockTestBackend.worldClockDisplay(clock.displayedTimezone,clock.now).time)}
  compare(Object.keys(seen).length,worldClockTestBackend.worldClockRegions.length);compare(worldClockTestBackend.timezone,zone)
  clock.selectedTimezone="Asia/Kathmandu";wait(1550);verify(Math.abs(earth.latitude-clock.selectedRegion.latitude)<.01);verify(Math.abs(((earth.longitude-clock.orientationPhase-clock.selectedRegion.longitude+540)%360)-180)<.01)
  lock.handleClockAction("secondary");compare(clock.displayedTimezone,zone);compare(worldClockTestBackend.timezone,zone)
  // Unit fixture lacks the C++ production authentication authority: it must fail closed.
  clock.selectedTimezone=zone==="Asia/Kathmandu"?"Europe/London":"Asia/Kathmandu";verify(!clock.requestLocalTimezone());compare(worldClockTestBackend.timezone,zone)
  var selected=clock.selectedTimezone;host.cardArmed=true;lock.handleClockAction("primary");lock.handleClockAction("secondary");compare(clock.selectedTimezone,selected);verify(!clock.requestLocalTimezone());host.cardArmed=false
 }
 function test_b_visibility_immediate_security_independent(){
  var clock=find(lock,"GeminiLockClock"),welcome=find(lock,"GeminiLockWelcome"),security=find(lock,"GeminiLockSecurityBadge")
  verify(worldClockTestBackend.setLockscreenClockVisible(false));verify(!clock.visible);verify(!lock.clockVisible)
  verify(worldClockTestBackend.setLockscreenWelcomeVisible(false));verify(!welcome.visible);verify(security.visible);compare(security.y,189)
  verify(worldClockTestBackend.setLockscreenClockVisible(true));verify(clock.visible);verify(worldClockTestBackend.setLockscreenWelcomeVisible(true));verify(welcome.visible)
 }
 function test_c_gpu_day_night_and_mixed(){
  var clock=find(lock,"GeminiLockClock"),earth=find(lock,"GeminiLockClockEarth")
  // Deterministic test-only UTC instant: production always binds Date.now().
  clock.animated=false;clock.earthAngle=0;clock.now=new Date("2026-03-20T12:00:00Z");verify(earth.astronomicalLighting)
  var sun=JSON.stringify(clock.solarData)
  for(var state of [{name:"daytime",zone:"Europe/London"},{name:"nighttime",zone:"Asia/Tokyo"},{name:"mixed",zone:"Asia/Kolkata"}]){
   clock.selectedTimezone=state.zone;wait(1550);clock.now=new Date("2026-03-20T12:00:00Z");compare(JSON.stringify(clock.solarData),sun);waitForRendering(lock);wait(150);clock.now=new Date("2026-03-20T12:00:00Z");grabImage(test).save("/tmp/gemini-world-clock-"+state.name+".png")
  }
  clock.returnToLocal();clock.now=new Date();clock.animated=true;wait(600);grabImage(test).save("/tmp/gemini-world-clock-live.png")
 }
 function test_d_continuous_eastward_rotation(){
  var clock=find(lock,"GeminiLockClock"),earth=find(lock,"GeminiLockClockEarth");compare(clock.earthRotationPeriodMs,60000)
  var start=clock.earthAngle,time=Date.now();wait(15000);var quarter=(clock.earthAngle-start+360)%360;verify(Math.abs(quarter-90)<5)
  clock.nextRegion();wait(45000);var phase=(clock.earthAngle-start+360)%360;verify(phase<6||phase>354)
  compare(earth.spinAngle,clock.earthAngle);console.info("WORLD_CLOCK_ROTATION",JSON.stringify({elapsedMs:Date.now()-time,quarterDegrees:quarter,finalPhaseDegrees:phase}))
 }
 function captureSolar(zone,name){
  var clock=find(lock,"GeminiLockClock");clock.animated=false;clock.earthAngle=0;clock.selectedTimezone=zone
  wait(1600);clock.now=new Date("2026-03-20T12:00:00Z");lock.visible=false;wait(100);lock.visible=true;waitForRendering(lock);wait(600);clock.now=new Date("2026-03-20T12:00:00Z");grabImage(test).save("/tmp/gemini-world-final-"+name+".png")
 }
 function test_e_capture_day(){captureSolar("Europe/London","daytime")}
 function test_f_capture_night(){captureSolar("Asia/Tokyo","nighttime")}
 function test_g_capture_mixed(){captureSolar("Asia/Kolkata","mixed")}

}
