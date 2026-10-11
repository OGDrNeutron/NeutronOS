import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
import "../../qml" as Shell
import "../../qml/dashboard/v2" as Dashboard
TestCase {
 id:test;name:"Gemini058IndependentHelix";when:windowShown;visible:true;width:1672;height:941
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
 function capture(item,name){waitForRendering(item);wait(120);grabImage(item).save("/gemini/validation/screenshots/"+name+"-dna-final.png")}
 function init(){host.cardArmed=false;host.animationsEnabled=true;lock.visible=true;desktop.visible=false;worldClockTestBackend.setLockscreenDetailsVisible(true);worldClockTestBackend.setLockscreenClockVisible(true)}

 function test_b_simultaneous_atom_helix_and_transient_arcs(){
  var atom=find(lock,"GeminiLockInnerAtom"),ring=find(lock,"GeminiLockHelix")
  verify(atom.visible);verify(atom.moving);compare(atom.width,570);compare(atom.height,570)
  host.cardArmed=true;verify(atom.visible);verify(atom.moving);verify(ring.running);verify(find(ring,"GeminiLockHelix3D"))
  var blue=findChild(ring,"GeminiHelixBlueStrand"),red=findChild(ring,"GeminiHelixRedStrand"); verify(blue);verify(red);var phase=ring.turn;wait(500);tryVerify(function(){return ring.turn>phase},2000);compare(blue.eulerRotation.z,ring.blueTurn);compare(red.eulerRotation.z,ring.redTurn);verify(ring.blueTurn<0);verify(ring.redTurn>18)
  capture(test,"058-focused-armed-helix-inner-atom");capture(ring,"058-focused-dna-close-up")
  var first=grabImage(atom);wait(180);var second=grabImage(atom);verify(!first.equals(second),"Inner atom renders independent movement while armed")
  var count=ring.acceptedPulseCount;for(var n=0;n<8;n++)host.authenticationInputAccepted()
  compare(ring.acceptedPulseCount,count+8);compare(ring.activePulseCount,8);verify(atom.moving)
  capture(test,"058-focused-armed-purple-arc-pulses")
  tryCompare(ring,"activePulseCount",0,2500);verify(atom.moving);verify(ring.running)
  host.authenticationInputAccepted();host.cardArmed=false;compare(ring.activePulseCount,0);verify(!ring.running);verify(atom.moving)
  lock.visible=false;verify(!atom.moving);verify(!ring.running)
 }
}
