import QtQuick
QtObject {
 id:flow
 property int phase:0
 property double started:Date.now()
 property var assertions:[]
 property var progressEvents:[]
 property var performance:({})
 property int lastStage:-1
 function check(value,label){if(!value)throw Error(label);assertions.push(label);console.info("GEMINI_RECOVERY054_ASSERT",label)}
 function finish(success,reason){ticker.stop();vmBridge.result({passed:success,kind:"recovery054",reason:reason||"",assertions:assertions,progressEvents:progressEvents,performance:performance,productionRecoveryManager:true,realProtectedBackup:true});vmBridge.finish(success)}
 property Connections monitor:Connections {
  target:recoveryModeManager
  function onStateChanged(){
   if(recoveryModeManager.view!=="progress")return
   var p=recoveryModeManager.progress
   if(p<0)return
   progressEvents.push({percent:p,message:recoveryModeManager.message})
   var stage=p>=94?3:p>=55?2:p>=28?1:0
   if(stage!==flow.lastStage){flow.lastStage=stage;vmBridge.capture("recovery-progress-"+stage)}
  }
 }
 property Timer ticker:Timer {
  running:true;repeat:true;interval:450
  onTriggered:{try{
   if(Date.now()-flow.started>300000)throw Error("Recovery timed out")
   if(flow.phase===0){
    if(recoveryModeManager.view!=="landing")return
    flow.check(recoveryModeManager.recoveryPoints.length>0,"Real verified backup catalog loaded")
    vmBridge.capture("recovery-landing");vmBridge.beginPerformance();flow.started=Date.now();flow.phase=1
   }else if(flow.phase===1){
    if(Date.now()-flow.started<6000)return
    flow.performance=vmBridge.performance();flow.performance.state="recovery-atom-idle"
    recoveryModeManager.handleAction("primary");flow.check(recoveryModeManager.view==="menu","Landing X enters Recovery menu")
    vmBridge.capture("recovery-menu");flow.phase=2
   }else if(flow.phase===2){
    recoveryModeManager.handleAction("down");flow.check(recoveryModeManager.menuIndex===1,"Controller menu navigation")
    recoveryModeManager.handleAction("primary");flow.check(recoveryModeManager.view==="unavailable"&&!recoveryModeManager.busy,"Unsupported reimage operation remains gated")
    recoveryModeManager.handleAction("cancel");recoveryModeManager.selectIndex(3);recoveryModeManager.handleAction("primary")
    flow.check(recoveryModeManager.view==="manage","Manage Backups opens real catalog")
    recoveryModeManager.handleAction("secondary");flow.check(recoveryModeManager.armed,"Backup deletion requires confirmation")
    recoveryModeManager.handleAction("cancel");flow.check(!recoveryModeManager.armed,"Back cancels deletion without modifying archive")
    recoveryModeManager.handleAction("primary");flow.phase=3
   }else if(flow.phase===3){
    if(recoveryModeManager.busy)return
    flow.check(recoveryModeManager.view==="manage"&&recoveryModeManager.message.indexOf("verified")>=0,"Guarded verification of actual backup succeeds")
    recoveryModeManager.handleAction("cancel");recoveryModeManager.selectIndex(0);recoveryModeManager.handleAction("primary")
    flow.check(recoveryModeManager.view==="selection","Restore browser entered")
    vmBridge.capture("recovery-backups")
    recoveryModeManager.handleAction("primary");flow.check(recoveryModeManager.armed,"Restore requires explicit second confirmation")
    recoveryModeManager.handleAction("cancel");flow.check(!recoveryModeManager.armed,"Back cancels armed restore")
    recoveryModeManager.handleAction("primary");recoveryModeManager.handleAction("primary")
    flow.check(recoveryModeManager.busy,"Confirmed restore starts real authenticated helper")
    flow.phase=4
   }else if(flow.phase===4){
    if(recoveryModeManager.busy)return
    flow.check(recoveryModeManager.view==="success"&&recoveryModeManager.progress===100,"Real backup restoration completes")
    flow.check(flow.progressEvents.some(function(e){return e.percent===8})&&flow.progressEvents.some(function(e){return e.percent===55})&&flow.progressEvents.some(function(e){return e.percent===94}),"Progress follows actual verify/restore/finalize output")
    vmBridge.capture("recovery-success");flow.finish(true,"")
   }
  }catch(error){flow.finish(false,String(error))}}
 }
}
