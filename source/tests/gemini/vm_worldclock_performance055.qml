import QtQuick
QtObject {
 id:flow;property int phase:0;property var login:null;property var main:null;property var clock:null;property double started:Date.now();property double at:0;property var idle:({});property var rotation:({});property var unlock:({})
 function find(item,name){if(!item)return null;if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var hit=find(c[i],name);if(hit)return hit}return null}
 function press(action){login.handleControllerPressed(action);login.handleControllerReleased(action)}
 property Timer ticker:Timer{interval:100;repeat:true;running:true;onTriggered:{
  if(Date.now()-flow.started>180000){ticker.stop();vmBridge.result({passed:false,reason:"Performance observation timeout"});vmBridge.finish(false);return}
  if(flow.phase===0){flow.login=flow.find(vmWindow.contentItem,"GeminiLoginScreen");flow.main=flow.find(vmWindow.contentItem,"GeminiMainRoot");if(!flow.login||!flow.main||!flow.login.active)return;flow.clock=flow.find(vmWindow.contentItem,"GeminiLockClock");flow.at=Date.now();flow.phase=1}
  else if(flow.phase===1){if(Date.now()-flow.at<6000)return;vmBridge.beginPerformance();flow.at=Date.now();flow.phase=2}
  else if(flow.phase===2){if(Date.now()-flow.at<12000)return;flow.idle=vmBridge.performance();flow.press("right");flow.press("x");vmBridge.beginPerformance();flow.at=Date.now();flow.phase=3}
  else if(flow.phase===3){if(Date.now()-flow.at<6000)return;flow.rotation=vmBridge.performance();flow.press("left");flow.press("x");for(var action of ["up","down","left","right"])flow.press(action);flow.phase=4}
  else if(flow.phase===4){var transition=flow.find(vmWindow.contentItem,"GeminiUnlockTransition");if(transition&&transition.started){vmBridge.beginPerformance();flow.phase=5}}
  else if(flow.phase===5){if(flow.main.shellMode!=="console")return;flow.unlock=vmBridge.performance();ticker.stop();vmBridge.result({passed:flow.main.authenticated,idlePerformance:flow.idle,regionRotationPerformance:flow.rotation,unlockPerformance:flow.unlock,synchronousCapturesDuringMeasurement:false,forcesRendering:false});vmBridge.finish(flow.main.authenticated)}
 }}
}
