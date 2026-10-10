import QtQuick
QtObject {
 id:flow
 property int phase:0
 property var login:null
 property var clock:null
 property var texts:[]
 property var result:({})
 property double started:Date.now()
 function find(item,name){if(!item)return null;if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var hit=find(c[i],name);if(hit)return hit}return null}
 property Timer timer:Timer {interval:250;repeat:true;running:true;onTriggered:{
  try {
   if(Date.now()-flow.started>45000)throw Error("Clock diagnostic timeout")
   if(flow.phase===0){
    flow.login=flow.find(vmWindow.contentItem,"GeminiLoginScreen");flow.clock=flow.find(flow.login,"GeminiLockClock");if(!flow.clock)return
    flow.texts=[flow.find(flow.clock,"GeminiLockLocalTime"),flow.find(flow.clock,"GeminiLockMeridiem"),flow.find(flow.clock,"GeminiLockLocalDate")]
    if(flow.texts.some(function(t){return !t}))throw Error("Missing clock text objects")
    flow.result={localTime:flow.clock.localTime,localPeriod:flow.clock.localPeriod,localDate:flow.clock.localDate,use24Hour:flow.clock.use24Hour,texts:flow.texts.map(function(t){return {name:t.objectName,text:t.text,visible:t.visible,opacity:t.opacity,width:t.width,height:t.height,renderType:t.renderType}})}
    flow.started=Date.now();flow.phase=1
   }else if(flow.phase===1&&Date.now()-flow.started>1500){
    vmBridge.capture("clock-original-live")
    for(var i=0;i<flow.texts.length;i++)flow.texts[i].renderType=Text.CurveRendering
    flow.started=Date.now();flow.phase=2
   }else if(flow.phase===2&&Date.now()-flow.started>1500){
    vmBridge.capture("clock-curve-live");flow.result.passed=flow.result.localDate.length>0&&flow.result.localTime.length>0
    vmBridge.result(flow.result);timer.stop();vmBridge.finish(flow.result.passed)
   }
  }catch(e){vmBridge.result({passed:false,error:String(e)});timer.stop();vmBridge.finish(false)}
 }}
}
