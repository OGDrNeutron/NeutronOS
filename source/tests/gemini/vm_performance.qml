import QtQuick
QtObject {
    id:probe
    property var wizard:null
    property int phase:0
    property double phaseStarted:Date.now()
    property var samples:[]
    function find(item,name){if(!item)return null;if(item.objectName===name)return item;var children=item.children||[];for(var i=0;i<children.length;i++){var v=find(children[i],name);if(v)return v}return null}
    property Timer timer:Timer {
        interval:250;repeat:true;running:true
        onTriggered:{
            if(!probe.wizard){probe.wizard=probe.find(vmWindow.contentItem,"GeminiSetupWizard");if(!probe.wizard)return;vmBridge.beginPerformance();probe.phaseStarted=Date.now();return}
            if(Date.now()-probe.phaseStarted<12000)return
            var value=vmBridge.performance();value.state=["welcome-atom","earth-idle","earth-region-rotation","ready-atom-stage"][probe.phase];probe.samples.push(value);console.info("GEMINI_PERFORMANCE",JSON.stringify(value))
            probe.phase++;probe.phaseStarted=Date.now()
            if(probe.phase===1){probe.wizard.setStep(1)}
            else if(probe.phase===2){probe.wizard.timezone="Europe/London"}
            else if(probe.phase===3){probe.wizard.setStep(9)}
            else {running=false;vmBridge.result({passed:true,performanceSamples:probe.samples,frameSwappedInstrumentation:true,forcesRendering:false,productionManagers:true});vmBridge.finish(true);return}
            vmBridge.beginPerformance()
        }
    }
}
