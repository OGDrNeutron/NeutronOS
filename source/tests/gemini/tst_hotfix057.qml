import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
import "../../qml/dashboard/v2" as Dashboard
TestCase {
 id:test; name:"Gemini057Hotfix"; when:windowShown; visible:true; width:1920;height:1080
 QtObject{id:security;property bool indicatorOnline:true;property int indicatorScore:92;property bool daemonOnline:false;property int securityScore:-1}
 QtObject{id:pad;property bool controllerConnected:true;property string controllerName:"DualSense Wireless Controller";property string controllerDevicePath:"/dev/input/event58";property bool controllerBatteryAvailable:true;property int controllerBatteryPercent:72;property bool controllerCharging:false}
 QtObject{id:host
  property bool loginSuccess:false;property bool animationsEnabled:true;property bool cardArmed:false;property string lockscreenFocus:"user";property string errorText:"";property string statusText:"Profile ready";property var inputTokens:[];property var controllerBackend:pad;property var loginSecurityBackend:security;property real unlockRippleScale:1;property real unlockRippleOpacity:0
  function greetingPrefix(){return "GOOD AFTERNOON."}function currentDisplayName(){return "Gemini Test Profile"}function currentAvatarSource(){return ""}function selectFocused(){cardArmed=true}function setLockscreenFocus(v){lockscreenFocus=v}function beginClockTimezoneAuthentication(){}function isLockedOut(){return false}function formatTime(v){return "0:00"}function lockoutSecondsRemaining(){return 0}
 }
 Rectangle{anchors.fill:parent;color:"#02060d"}
 Image{anchors.fill:parent;source:"../../themes/Default/background.png";fillMode:Image.PreserveAspectCrop}
 Rectangle{anchors.fill:parent;color:"#02060d";opacity:.22}
 Dashboard.ModernDashboard{id:desktop;anchors.fill:parent;visible:false;shellActive:false;securityBackend:security;controllerBackend:pad}
 Gemini.LockPresentation{id:lock;anchors.fill:parent;host:host}
 function find(item,name){if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var hit=find(c[i],name);if(hit)return hit}return null}
 function capture(item,name){waitForRendering(item);wait(200);grabImage(item).save("/gemini/validation/screenshots/"+name+".png")}
 function test_a_clock_and_overview(){
  var housing=find(lock,"GeminiClockHousing"),earth=find(lock,"GeminiLockClockEarth"),panel=find(lock,"GeminiLockControllerPanel")
  compare(housing.width,372*.75);compare(housing.height,126*.75);compare(earth.width,180);compare(earth.height,180)
  compare(panel.x+panel.width/2,1672/2);verify(panel.y>=811);verify(panel.y+panel.height<=905)
  tryCompare(panel,"connectionLabel","Bluetooth",6000);compare(panel.battery,72)
  wait(1800);capture(test,"057-lockscreen-overview");capture(panel,"057-controller-bluetooth-72-percent")
 }
 function test_b_security_synchronization_and_reconnection(){
  var label=find(lock,"GeminiLockSecurityLabel")
  for(var state of [{score:92,label:"Secure"},{score:65,label:"Weak Protection"},{score:20,label:"Unsecure"}]){
   security.indicatorScore=state.score;compare(label.text,state.label);compare(desktop.headerSecurityLabel(),label.text)
   lock.visible=false;desktop.visible=true;wait(40);compare(desktop.headerSecurityLabel(),state.label);desktop.visible=false;lock.visible=true;compare(label.text,state.label)
  }
  security.indicatorOnline=false;compare(label.text,"Unavailable");compare(desktop.headerSecurityLabel(),"Unavailable")
  security.indicatorOnline=true;security.indicatorScore=92;compare(label.text,"Secure")
  capture(test,"057-security-lockscreen-secure");desktop.visible=true;lock.visible=false;capture(test,"057-security-desktop-secure");desktop.visible=false;lock.visible=true
 }
 function test_c_transport_battery_disconnect_and_stale_reply(){
  var panel=find(lock,"GeminiLockControllerPanel")
  pad.controllerDevicePath="/dev/input/event57";compare(panel.connectionLabel,"Verifying connection");tryCompare(panel,"connectionLabel","Wired",6000)
  pad.controllerBatteryPercent=31;compare(panel.battery,31);capture(panel,"057-controller-usb-31-percent")
  pad.controllerDevicePath="/dev/input/event59";wait(100);pad.controllerDevicePath="/dev/input/event58";tryCompare(panel,"connectionLabel","Bluetooth",6000);wait(2400);compare(panel.connectionLabel,"Bluetooth")
  pad.controllerBatteryAvailable=false;compare(panel.battery,-1);capture(panel,"057-controller-battery-unavailable")
  pad.controllerConnected=false;compare(panel.connectionLabel,"Disconnected");compare(panel.battery,-1);compare(panel.controllerName,"Controller disconnected")
  pad.controllerConnected=true;pad.controllerBatteryAvailable=true;pad.controllerBatteryPercent=72;tryCompare(panel,"connectionLabel","Bluetooth",6000)
 }
}
