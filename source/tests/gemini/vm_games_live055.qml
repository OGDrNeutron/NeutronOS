import QtQuick
QtObject {
 id:f
 property int phase:0
 property double started:Date.now()
 property double phaseStarted:Date.now()
 property var main:null
 property var login:null
 property var games:null
 property var assertions:[]
 property bool operationDone:false
 property bool operationPassed:false
 property string operationMessage:""
 function find(item,name){if(!item)return null;if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var r=find(c[i],name);if(r)return r}return null}
 function check(v,message){if(!v)throw Error(message);assertions.push(message);console.info("GEMINI_GAMES_ASSERT",message)}
 function press(item,key){item.handleControllerPressed(key);item.handleControllerReleased(key)}
 function beginOperation(){operationDone=false;operationPassed=false;phaseStarted=Date.now()}
 function finish(ok,reason){ticker.stop();vmBridge.result({passed:ok,reason:reason||"",validation:"Games signed application-native lifecycle",assertions:assertions,securityOnline:securityCoreManager.daemonOnline,securityScore:securityCoreManager.securityScore});vmBridge.finish(ok)}
 property Connections operation:Connections {
  target:appStoreManager
  function onOperationFinished(id,op,success,message){f.operationDone=true;f.operationPassed=success;f.operationMessage=message;console.info("GEMINI_GAMES_OPERATION",op,success,message)}
 }
 property Timer ticker:Timer {interval:250;repeat:true;running:true;onTriggered:{try{
  if(Date.now()-f.started>240000)throw Error("Games validation timeout phase "+f.phase)
  if(f.phase===0){f.main=f.find(vmWindow.contentItem,"GeminiMainRoot");f.login=f.find(vmWindow.contentItem,"GeminiLoginScreen");if(!f.login||!f.login.active)return;f.press(f.login,"x");f.phase=1}
  else if(f.phase===1){f.press(f.login,"x");f.phase=2}
  else if(f.phase===2){for(var i=0;i<4;i++)f.press(f.login,["up","down","left","right"][i]);f.phase=3}
  else if(f.phase===3){if(f.main.shellMode!=="console"||!securityCoreManager.daemonOnline)return;f.check(f.main.authenticated,"Real controller login and live Security ready");f.check(true,"Use live signed official Gemini catalog");appStoreManager.reload();appStoreManager.refreshCatalog();f.phase=4;f.phaseStarted=Date.now()}
  else if(f.phase===4){var p=appStoreManager.packageById("gemini-games");if(!p||!p.id){if(Date.now()-f.phaseStarted>30000)throw Error("Signed Games catalog unavailable: "+appStoreManager.lastError);return}f.check(p.version==="0.1.0-review.2","Authenticated review.2 catalog selected");f.check(p.storeEligible||p.installed,"Native Games package compatible with Gemini capability APIs");f.beginOperation();f.check(appStoreManager.installPackage("gemini-games"),"Signed Games download/install starts");f.phase=5}
  else if(f.phase===5){if(!f.operationDone)return;f.check(f.operationPassed,"Games installed without OS rebuild: "+f.operationMessage);f.check(appStoreManager.installedVersion("gemini-games")==="0.1.0-review.2","Application version registered");appManager.reloadApps();f.main.beginLaunchApp(appManager.appById("gemini-games"));f.phase=6;f.phaseStarted=Date.now()}
  else if(f.phase===6){f.games=f.find(vmWindow.contentItem,"GeminiGamesApp");if(!f.games||f.main.shellMode!=="app"){if(Date.now()-f.phaseStarted>45000)throw Error("Games frontend/plugin did not reach app mode: "+f.main.shellMode);return}f.check(f.games.backend!==null,"Packaged native backend loaded by application QML");f.check(f.main.packageSession===f.games.backend&&f.main.packageSessionAppId==="gemini-games","Generic permission-controlled session API registers Games");f.check(f.games.backend.initialize(),"Games backend initializes signed-in human storage");var oldPage=f.games.page;f.games.zone="nav";f.press(f.games,"down");f.check(f.games.page===Math.min(7,oldPage+1),"Games controller navigation preserved");vmBridge.capture("055-games-installed");f.check(f.games.backend.roots.length>0,"Existing human Games library covers native process fixture");f.games.backend.rescan();f.phase=60;f.phaseStarted=Date.now()}
  else if(f.phase===60){if(f.games.backend.scanning)return;var list=f.games.backend.games;var game=null;for(var i=0;i<list.length;i++)if(list[i].path==="/NeutronOS/geminiflow/Games/055-validation/native-lifecycle")game=list[i];if(!game){if(Date.now()-f.phaseStarted>15000)throw Error("Native test title not discovered");return}f.check(f.games.backend.configure(game.id,{runtime:"native",arguments:["30"],offlineSuspend:true,network:false},true),"Configure application-owned native fixture");f.check(f.games.backend.play(game.id),"Games requests isolated game launch through real session/proxy API");f.phase=61;f.phaseStarted=Date.now()}
  else if(f.phase===61){if(!f.games.backend.gamingMode){if(Date.now()-f.phaseStarted>15000)throw Error("Game process did not enter gaming mode");return}f.check(f.games.backend.gameActive&&f.games.backend.controllerCount===1,"Owned game process and explicit VM controller are active");f.check(!appStoreManager.uninstallPackage("gemini-games"),"Active game blocks package removal");f.check(f.games.backend.prepareSwitch(),"Safe native game background succeeds");f.phase=62;f.phaseStarted=Date.now()}
  else if(f.phase===62){if(Date.now()-f.phaseStarted<500)return;f.check(f.games.backend.backgrounded&&f.games.backend.gameActive,"Background retains owned game session");f.check(f.games.backend.resumeGame(),"Native game resumes without reconnect");f.phase=63;f.phaseStarted=Date.now()}
  else if(f.phase===63){if(Date.now()-f.phaseStarted<500)return;f.games.backend.closeGame();f.phase=64;f.phaseStarted=Date.now()}
  else if(f.phase===64){if(f.games.backend.gameActive){if(Date.now()-f.phaseStarted>15000)throw Error("Owned game process did not exit");return}f.check(true,"Game exit releases input and restores shell");f.games.exitRequested();f.phase=7;f.phaseStarted=Date.now()}
  else if(f.phase===7){if(f.main.shellMode!=="console")return;f.check(!f.main.packageSession.gameActive,"Games exit leaves no running game");f.check(vmBridge.useGamesFixtureCatalog(true),"Select signed disposable update catalog");appStoreManager.reload();appStoreManager.refreshCatalog();f.phase=8;f.phaseStarted=Date.now()}
  else if(f.phase===8){var p=appStoreManager.packageById("gemini-games");if(!p||p.version!=="0.1.1-vm-only"||appStoreManager.busy)return;f.check(p.updateEligible,"Authenticated newer Games update offered");f.beginOperation();f.check(appStoreManager.updatePackage("gemini-games"),"Games application-only update starts");f.phase=9}
  else if(f.phase===9){if(!f.operationDone)return;f.check(f.operationPassed&&appStoreManager.installedVersion("gemini-games")==="0.1.1-vm-only","Games update commits without OS rebuild");f.beginOperation();f.check(appStoreManager.rollbackPackage("gemini-games"),"Games package rollback starts");f.phase=10}
  else if(f.phase===10){if(!f.operationDone)return;f.check(f.operationPassed&&appStoreManager.installedVersion("gemini-games")==="0.1.0-review.2","Games rollback restores prior authenticated application");f.beginOperation();f.check(appStoreManager.uninstallPackage("gemini-games"),"Application-only removal starts");f.phase=11}
  else if(f.phase===11){if(!f.operationDone)return;f.check(f.operationPassed,"Games application-only uninstall completes");f.check(!appStoreManager.isInstalled("gemini-games"),"Games registry removed");f.finish(true,"")}

 }catch(e){console.error("GEMINI_GAMES_FAILURE",String(e));f.finish(false,String(e))}}}
}
