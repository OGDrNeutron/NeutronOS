import QtQuick
import QtTest
import "../../../../validation/ui-runtime/qml/apps/gemini-games" as Games
TestCase {
 id:test;objectName:"GeminiMainRoot";name:"Gemini057NativeGames";when:windowShown;visible:true;width:1920;height:1080
 Games.Main{id:games;anchors.fill:parent}
 property int heartbeats:0
 property double previousBeat:Date.now()
 property double maximumGap:0
 Timer{interval:20;repeat:true;running:true;onTriggered:{var now=Date.now();test.maximumGap=Math.max(test.maximumGap,now-test.previousBeat);test.previousBeat=now;test.heartbeats++}}
 Connections{target:controllerReplay;function onPressed(action){games.handleControllerPressed(action)}function onReleased(action){games.handleControllerReleased(action)}}
 function capture(name){waitForRendering(test);grabImage(test).save("/gemini/validation/screenshots/"+name+".png")}
 function test_native_index_and_navigation(){
  games.page=0;games.zone="nav";test.previousBeat=Date.now();test.maximumGap=0;verify(games.backend.initialize());games.backend.rescan();tryVerify(function(){return games.backend.scanning},10000)
  var count=heartbeats;controllerReplay.tap(108);compare(games.page,1)
  wait(200);capture("057-games-indexing-responsive-native")
  tryVerify(function(){return !games.backend.scanning&&games.backend.games.length===3000},60000)
  verify(heartbeats>count+5);console.info("NATIVE_GAMES_EVENT_LOOP",JSON.stringify({maximumGapMs:maximumGap,ticks:heartbeats,records:games.backend.games.length}))
  verify(maximumGap<1000,"Rendered Games event loop must remain responsive: "+maximumGap)
  controllerReplay.tap(106);compare(games.zone,"content");controllerReplay.tap(106);verify(games.selectedGame>0)
  capture("057-games-open-library-native");games.backend.rescan();tryVerify(function(){return games.backend.scanning},10000)
  games.backend.cancelIndexing();tryVerify(function(){return !games.backend.scanning},30000);compare(games.backend.games.length,3000)
  games.visible=false;wait(100);games.visible=true;verify(games.backend.initialize());wait(700);verify(!games.backend.scanning);compare(games.backend.games.length,3000)
  capture("057-games-after-cancel-native")
 }
}
