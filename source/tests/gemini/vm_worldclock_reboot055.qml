import QtQuick
QtObject {
 id:flow;property var login:null;property var main:null;property var assertions:[];property int phase:0;property double started:Date.now();property double phaseStarted:0;property var idle:({});property var unlock:({})
 function find(item,name){if(!item)return null;if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var hit=find(c[i],name);if(hit)return hit}return null}
 function check(value,label){if(!value)throw Error(label);assertions.push(label);console.info("WORLD_REBOOT_ASSERT",label)}
 function press(action){login.handleControllerPressed(action);login.handleControllerReleased(action)}
 function finish(passed,reason){ticker.stop();vmBridge.result({passed:passed,reason:reason||"",assertions:assertions,timezone:clockSettingsManager.timezone,securityOnline:securityCoreManager.daemonOnline,securityScore:securityCoreManager.securityScore,idlePerformance:idle,unlockPerformance:unlock});vmBridge.finish(passed)}
 property Timer ticker:Timer{interval:250;repeat:true;running:true;onTriggered:{try{
  if(Date.now()-flow.started>180000)throw Error("World reboot validation timeout")
  if(flow.phase===0){
   flow.main=flow.find(vmWindow.contentItem,"GeminiMainRoot");flow.login=flow.find(vmWindow.contentItem,"GeminiLoginScreen");if(!flow.main||!flow.login||!flow.login.active)return
   flow.check(setupWizardManager.setupComplete,"Setup remains completed after reboot")
   flow.check(clockSettingsManager.timezone==="Asia/Kathmandu","Verified system timezone persists after reboot")
   flow.check(!clockSettingsManager.lockscreenClockVisible&&!clockSettingsManager.lockscreenWelcomeVisible,"Both backend visibility preferences persist after reboot")
   var clock=flow.find(vmWindow.contentItem,"GeminiLockClock"),welcome=flow.find(vmWindow.contentItem,"GeminiLockWelcome"),security=flow.find(vmWindow.contentItem,"GeminiLockSecurityBadge")
   flow.check(!clock.visible&&!welcome.visible&&security.visible,"Hidden clock/welcome and independent Security apply immediately on boot")
   flow.press("right");flow.check(flow.login.lockscreenFocus==="user","Hidden clock excluded from controller focus after reboot")
   vmBridge.capture("world-reboot-hidden")
   flow.check(clockSettingsManager.setLockscreenClockVisible(true)&&clockSettingsManager.setLockscreenWelcomeVisible(true),"Future Settings backend can restore both visible components")
   flow.press("right");flow.check(flow.login.lockscreenFocus==="clock","Visible clock regains focus navigation")
   flow.press("x");flow.press("square");flow.check(clock.displayedTimezone==="Asia/Kathmandu"&&clock.isLocal,"Square references newly persisted local timezone")
   flow.press("triangle");flow.check(!clockSettingsManager.timezoneAuthorizationPending&&!flow.login.cardArmed,"Triangle is inactive when selected timezone is already local")
   flow.press("left");flow.check(flow.login.lockscreenFocus==="user","D-pad Left returns to user card")
   vmBridge.beginPerformance();flow.phaseStarted=Date.now();flow.phase=1
  }else if(flow.phase===1){
   if(Date.now()-flow.phaseStarted<12000)return
   flow.idle=vmBridge.performance();flow.press("x");flow.check(flow.login.cardArmed,"User X preserves passcode arming")
   var ring=flow.find(vmWindow.contentItem,"GeminiLockRing"),before=ring.pulseCount
   for(var action of ["up","down","left","right"])flow.press(action)
   flow.check(ring.pulseCount===before+4,"Verified passcode inputs retain independent luminous waves")
   vmBridge.beginPerformance();flow.phase=2
  }else if(flow.phase===2){
   if(flow.main.shellMode!=="console")return
   flow.unlock=vmBridge.performance();flow.check(flow.main.authenticated,"Real passcode login succeeds after timezone/visibility reboot")
   flow.phaseStarted=Date.now();flow.phase=3
  }else if(flow.phase===3){
   if(Date.now()-flow.phaseStarted<4000)return
   flow.check(securityCoreManager.daemonOnline&&securityCoreManager.securityScore>=0,"Authoritative Security initializes after reboot and human login")
   flow.check(flow.find(vmWindow.contentItem,"GeminiLoginScreen")===null,"Login unloads after unchanged Console reveal")
   vmBridge.capture("world-reboot-console");flow.finish(true,"")
  }
 }catch(error){flow.finish(false,String(error))}}}
}
