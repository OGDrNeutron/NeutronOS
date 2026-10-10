import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
TestCase {
 id:test;name:"Gemini054LockRecovery";when:windowShown;visible:true;width:1280;height:720
 QtObject {
  id:host
  property bool loginSuccess:false
  property bool animationsEnabled:true
  property bool cardArmed:false
  property string errorText:""
  property string statusText:"Profile ready"
  property var inputTokens:[]
  property bool secure:false
  function greetingPrefix(){return "GOOD AFTERNOON,"}
  function currentDisplayName(){return "DrNeutron"}
  function currentAvatarSource(){return ""}
  function selectFocused(){cardArmed=true}
  function loginSecurityIsSecure(){return secure}
  function isLockedOut(){return false}
  function formatTime(t){return "0:00"}
  function lockoutSecondsRemaining(){return 0}
  property real unlockRippleScale:1
  property real unlockRippleOpacity:0
 }
 QtObject {
  id:recovery
  property string view:"landing"
  property int menuIndex:0
  property int selectedIndex:0
  property int failureOption:0
  property bool armed:false
  property string title:"Restoring Backup"
  property string message:"Restoring configuration…"
  property int progress:55
  property var context:({mode:"BACKUP_RESTORE",reason:"Verified VM fixture"})
  property var recoveryPoints:[{name:"Gemini VM verified backup",size:4096,createdUtc:"2026-10-08T12:00:00Z",profile:"CONFIG",sha256:"0123456789abcdef",verified:true}]
  function handleAction(action){if(view==="landing"&&action==="primary")view="menu";else if(action==="down")menuIndex=(menuIndex+1)%6;return true}
  function selectIndex(index){selectedIndex=index}
 }
 Rectangle{anchors.fill:parent;color:"#030814"}
 Image{anchors.fill:parent;source:"../../themes/Default/background.png";fillMode:Image.PreserveAspectCrop;opacity:.45}
 Gemini.LockPresentation{id:lock;anchors.fill:parent;host:host}
 Gemini.RecoveryExperience{id:recoveryUi;anchors.fill:parent;backend:recovery;visible:false}
 Rectangle{id:liveDestination;anchors.fill:parent;color:"#123456";visible:false}
 Gemini.GeminiUnlockTransition{id:transition;anchors.fill:parent;captureSource:lock}
 SignalSpy{id:done;target:transition;signalName:"finished"}
 function capture(name,item){waitForRendering(item);wait(450);grabImage(test).save("/tmp/gemini-054-"+name+".png")}
 function test_all_design_states(){
  host.secure=false;capture("lock-unsecure",lock)
  host.secure=true;capture("lock-secure",lock)
  host.errorText="Incorrect passcode";wait(150);compare(lock.feedback,"error");grabImage(test).save("/tmp/gemini-054-lock-error.png")
  tryCompare(lock,"feedback","neutral",3000);host.errorText=""
  host.loginSuccess=true;compare(lock.feedback,"success");capture("lock-success",lock)
  host.loginSuccess=false;lock.visible=false;recoveryUi.visible=true
  for(var i=0;i<4;i++){
   recovery.view=["landing","menu","selection","progress"][i]
   capture(["recovery-landing","recovery-menu","recovery-backups","recovery-progress"][i],recoveryUi)
  }
  recoveryUi.visible=false;lock.visible=true
 }
 function test_gpu_transition_sequence(){
  liveDestination.visible=true;transition.start()
  tryCompare(transition,"started",true,10000)
  var stages=[]
  for(var i=0;i<19;i++){
   if(stages.indexOf(transition.stage)<0)stages.push(transition.stage)
   wait(180)
  }
  done.wait(3000)
  for(var j=0;j<6;j++)verify(stages.indexOf(["crack","separate","swirl","consolidate","compress","explode"][j])>=0,JSON.stringify(stages))
  verify(liveDestination.visible);verify(!transition.started);verify(!transition.snapshotRetained,"Completed unlock releases its frozen surface")
  transition.reset();compare(transition.elapsed,0)
  done.clear();transition.start();tryCompare(transition,"started",true,10000);done.wait(5000)
  verify(!transition.started&&!transition.snapshotRetained,"Repeated unlock also releases GPU capture")
  transition.reset();liveDestination.visible=false
 }
}
