import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
import "../../qml" as Shell
import "../../qml/dashboard/v2" as Dashboard
TestCase {
 id:test;name:"Gemini057OfficialLock";when:windowShown;visible:true;width:1672;height:941
 QtObject{id:security;property bool indicatorOnline:true;property int indicatorScore:92}
 QtObject{id:pad;property bool controllerConnected:true;property string controllerName:"DualSense";property string controllerDevicePath:"/dev/input/event58";property bool controllerBatteryAvailable:true;property int controllerBatteryPercent:72;property bool controllerCharging:false}
 QtObject{id:host
  signal authenticationInputAccepted()
  property bool loginSuccess:false;property bool animationsEnabled:true;property bool cardArmed:false;property string lockscreenFocus:"user";property string errorText:"";property string statusText:"Profile ready";property var inputTokens:[];property var controllerBackend:pad;property var loginSecurityBackend:security;property real unlockRippleScale:1;property real unlockRippleOpacity:0
  function greetingPrefix(){return "Good Afternoon,"}function currentDisplayName(){return "Gemini Test Profile"}function currentAvatarSource(){return ""}function selectFocused(){cardArmed=true}function setLockscreenFocus(v){lockscreenFocus=v}function beginClockTimezoneAuthentication(){}function isLockedOut(){return false}function formatTime(v){return "0:00"}function lockoutSecondsRemaining(){return 0}
 }
 Rectangle{anchors.fill:parent;color:"#02060d"}
 Image{anchors.fill:parent;source:"../../themes/Default/background.png";fillMode:Image.PreserveAspectCrop}
 Rectangle{anchors.fill:parent;color:"#02060d";opacity:.22}
 Dashboard.ModernDashboard{id:desktop;anchors.fill:parent;visible:false;shellActive:false;securityBackend:security;controllerBackend:pad}
 Gemini.LockPresentation{id:lock;anchors.fill:parent;host:host;clockBackend:worldClockTestBackend}
 Shell.LoginScreen{id:login;visible:false;active:false;clockBackend:worldClockTestBackend;securityBackend:null;userBackend:null;setupBackend:null;controllerBackend:null}
 SignalSpy{id:accepted;target:login;signalName:"authenticationInputAccepted"}
 function find(item,name){if(item.objectName===name)return item;for(var c of item.children||[]){var hit=find(c,name);if(hit)return hit}return null}
 function capture(item,name){waitForRendering(item);wait(120);grabImage(item).save("/gemini/validation/screenshots/"+name+"-final.png")}
 function init(){host.cardArmed=false;host.animationsEnabled=true;lock.visible=true;desktop.visible=false;worldClockTestBackend.setLockscreenDetailsVisible(true);worldClockTestBackend.setLockscreenClockVisible(true)}
 function test_a_reference_layout_and_security(){
  var welcome=find(lock,"GeminiLockWelcome"),clock=find(lock,"GeminiLockClock"),panel=find(lock,"GeminiLockControllerPanel"),label=find(lock,"GeminiLockSecurityLabel")
  compare(welcome.y,47);compare(welcome.height,114);compare(clock.x,1255);compare(panel.width,426);compare(panel.x+panel.width/2,836)
  verify(!find(lock,"GeminiLockSecurityBadge"));verify(welcome.visible);verify(!find(lock,"GeminiLockPasscodeCount"));verify(!find(panel,"GeminiLockControllerTransport"))
  for(var n of [92,65,20]){security.indicatorScore=n;compare(label.text,desktop.headerSecurityLabel());verify(welcome.accent===lock.securityColor)}
  security.indicatorOnline=false;compare(label.text,"Unavailable");security.indicatorOnline=true;security.indicatorScore=92
  wait(300);capture(test,"057-r3-official-lock-secure");capture(panel,"057-r3-controller-closeup")
  lock.visible=false;desktop.visible=true;capture(test,"057-r3-desktop-matching-secure");desktop.visible=false;lock.visible=true
  security.indicatorScore=20;capture(test,"057-r3-official-lock-unsecure");security.indicatorScore=92
 }
 function test_b_independent_clockwise_pulses_and_shutdown(){
  var ring=find(lock,"GeminiLockHelix");verify(!ring.running);host.authenticationInputAccepted();compare(ring.activePulseCount,0)
  host.cardArmed=true;verify(ring.running);var count=ring.acceptedPulseCount,turn=ring.turn
  for(var n=0;n<15;n++)host.authenticationInputAccepted()
  compare(ring.acceptedPulseCount,count+15);compare(ring.activePulseCount,15)
  tryVerify(function(){return ring.turn>turn},2000);capture(test,"057-r3-armed-purple-input-pulses")
  tryCompare(ring,"activePulseCount",0,2500)
  host.authenticationInputAccepted();compare(ring.activePulseCount,1);host.cardArmed=false;compare(ring.activePulseCount,0);verify(!ring.running)
  host.cardArmed=true;host.authenticationInputAccepted();lock.visible=false;compare(ring.activePulseCount,0);verify(!ring.running)
 }
 function test_c_hidden_timers_restore_and_clock_controls(){
  var clock=find(lock,"GeminiLockClock"),panel=find(lock,"GeminiLockControllerPanel"),welcome=find(lock,"GeminiLockWelcome")
  clock.returnToLocal();var original=clock.displayedTimezone;lock.handleClockAction("primary");verify(clock.displayedTimezone!==original);lock.handleClockAction("secondary");compare(clock.displayedTimezone,original)
  verify(worldClockTestBackend.setLockscreenDetailsVisible(false));verify(!clock.visible);verify(!panel.visible);verify(!panel.active);verify(welcome.visible)
  var phase=clock.earthAngle,instant=clock.now.getTime();wait(1150);compare(clock.earthAngle,phase);compare(clock.now.getTime(),instant);capture(test,"057-r3-persistent-details-hidden")
  verify(worldClockTestBackend.setLockscreenDetailsVisible(true));verify(clock.visible);verify(panel.active);wait(1100);verify(clock.now.getTime()>instant)
 }
 function test_d_real_accepted_input_and_toggle_route(){
  login.active=true;login.flowMode="combo";login.loginSuccess=false;login.cardArmed=false;login.lockscreenFocus="clock";accepted.clear()
  login.handleControllerPressed("options");verify(!worldClockTestBackend.lockscreenDetailsVisible);compare(login.lockscreenFocus,"user")
  login.handleControllerPressed("start");verify(worldClockTestBackend.lockscreenDetailsVisible)
  login.cardArmed=true;login.inputTokens=[];login.comboInputWindowSealed=false
  login.handleControllerPressed("options");verify(worldClockTestBackend.lockscreenDetailsVisible);compare(accepted.count,0)
  login.appendComboToken("not-a-button");compare(accepted.count,0)
  login.appendComboToken("primary");compare(accepted.count,1);compare(login.inputTokens.length,1)
  login.comboInputWindowSealed=true;login.appendComboToken("secondary");compare(accepted.count,1)
  login.cardArmed=false;login.active=false
 }
 function test_e_controller_transport_symbols_and_battery(){
  var panel=find(lock,"GeminiLockControllerPanel"),icon=find(lock,"GeminiLockControllerTransportIcon")
  verify(panel.dualSense);compare(panel.controllerName,"DualSense");tryCompare(panel,"connectionLabel","Bluetooth",6000);verify(icon.visible)
  pad.controllerDevicePath="/dev/input/event57";tryCompare(panel,"connectionLabel","Wired",6000);verify(icon.visible);pad.controllerBatteryPercent=31;compare(panel.battery,31);capture(panel,"057-r4-controller-usb")
  pad.controllerBatteryAvailable=false;compare(panel.battery,-1);capture(panel,"057-r4-controller-battery-unknown")
  pad.controllerConnected=false;compare(panel.connectionLabel,"Disconnected");verify(!icon.visible);compare(panel.battery,-1)
  pad.controllerConnected=true;pad.controllerBatteryAvailable=true;pad.controllerBatteryPercent=72;pad.controllerDevicePath="/dev/input/event58";tryCompare(panel,"connectionLabel","Bluetooth",6000)
  capture(panel,"057-r4-controller-bluetooth")
 }

}
