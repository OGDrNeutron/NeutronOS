import QtQuick
import QtTest
import "../../../../validation/ui-runtime/qml/apps/gemini-games" as Games
import "../../../../source/qml/apps" as Apps
import "../../../../source/qml/dashboard/v2" as Dashboard
TestCase {
    id:test;objectName:"GeminiMainRoot";name:"Gemini056Games";when:windowShown;visible:true;width:1920;height:1080
    function sharedDesktopCarousel(){return desktop}
    QtObject {
        id:fake
        property var games:[]
        property var roots:[]
        property var messages:[]
        property var installedRuntimes:[]
        property var preferences:({})
        property var hardware:({architecture:"amd64",logicalCpus:4,ramBytes:4294967296})
        property int controllerCount:1
        property bool scanning:false
        property bool gameActive:false
        property bool backgrounded:false
        property bool gamingMode:false
        property bool menuOpen:false
        property url menuSource:""
        property var artworkFiles:[]
        property string artworkDirectory:""
        property var artworkFormats:["png","jpg"]
        property var managerState:({})
        property bool managerBusy:false
        property var runtimeChoices:[{id:"wine",version:"Not installed",installed:false,program:"",source:"Signed App Store approval required"},{id:"dosbox",version:"Not installed",installed:false,program:"",source:"Signed App Store approval required"},{id:"scummvm",version:"Not installed",installed:false,program:"",source:"Signed App Store approval required"}]
        property int managerRequests:0
        property var lastManagerRequest:({})
        signal managerFinished(string action,bool success,var result)
        signal runtimeMissing(string gameId,string runtime)
        function managerOperation(request){managerRequests++;lastManagerRequest=request;var result=request.action==="status"?{games:[],runtimes:runtimeChoices}:request.action==="browse"?browseFolders(request.path):request.action==="inspect"?{candidates:[{path:"/home/player/Games/setup.exe",name:"setup.exe",kind:"exe",architecture:"amd64"},{path:"/home/player/Games/install.msi",name:"install.msi",kind:"msi",architecture:"unknown"}]}:{message:"Operation finished"};managerState=result;Qt.callLater(function(){managerFinished(request.action,true,result)});return true}
        function cancelManager(){}
        property string lastInstallerControl:""
        property string lastInstallerText:""
        function installerControl(action,text){lastInstallerControl=action;lastInstallerText=text||"";return true}
        property int additions:0
        signal footerTimeout()
        signal restoreRequested()
        signal messagePublished(string message,bool critical)
        function initialize(){return true}
        function cancelFooterCountdown(){}
        function uiState(){return {}}
        function setUiState(state){}
        function attachWindow(window){}
        function notify(message,critical){}
        function recommendations(id){return [{id:"native",installed:true,reason:"Use the installed native adapter.",capabilities:{launch:true}}]}
        function configure(id,config,approved){return true}
        function setControllerProfile(id,profile){return true}
        function setArtworkAssignment(id,path){return true}
        function removeFolder(index){return true}
        function refreshArtwork(){}
        function browseFolders(path){if(path==="")return {ok:true,path:"",parent:"",entries:[{name:"Home",path:"/home/player",kind:"home",available:true}]};if(path==="/home/player")return {ok:true,path:path,parent:"",entries:[{name:"Games",path:path+"/Games",kind:"folder",available:true}]};if(path==="/home/player/Games")return {ok:true,path:path,parent:"/home/player",entries:[]};return {ok:false,error:"Permission denied"}}
        function addFolder(path){additions++;roots=[{path:path,online:true}];return true}
        function editFolder(index,path){return addFolder(path)}
        function prepareSwitch(){return true}
    }
    QtObject {
        id:appManager
        property var apps:[{id:"settings",name:"Settings",icon:"file:///gemini/source/themes/Default/apps/icons/settings.png"},{id:"terminal",name:"Terminal",icon:"file:///gemini/source/themes/Default/apps/icons/terminal.png"},{id:"security",name:"Security",icon:"file:///gemini/source/themes/Default/apps/icons/security.png"}]
        property var dashboardApps:apps
        property var runningApps:[]
        property string focusedRuntime:""
        function appById(id){return apps.filter(function(a){return a.id===id})[0]||{}}
        function hasApp(id){return !!appById(id).id}
        function focusRuntime(id){focusedRuntime=id;return true}
    }
    QtObject{id:prefs;property var data:({});function value(key,fall){return data[key]===undefined?fall:data[key]}function queueChange(key,val,mode){data[key]=val;return true}function applyPending(){return true}}
    QtObject{id:networkManager;property string connectionState:"DISCONNECTED";property int connectivity:0}
    QtObject{id:controllerManager;property bool controllerConnected:true;property bool controllerBatteryAvailable:false;property int controllerBatteryPercent:0}
    Dashboard.ModernDashboard{id:desktop;anchors.fill:parent;visible:false;shellActive:false;appsBackend:appManager;settingsBackend:prefs}
    Games.Main {id:games;anchors.fill:parent;backend:fake;carouselHost:desktop}
    SignalSpy{id:exits;target:games;signalName:"exitRequested"}
    function find(item,name){if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var hit=find(c[i],name);if(hit)return hit}return null}
    function press(code){controllerReplay.tap(code)}
    Connections{target:controllerReplay;function onPressed(action){if(!appHost.visible)games.handleControllerPressed(action);else appHost.handleControllerPressed(action)}function onReleased(action){if(!appHost.visible)games.handleControllerReleased(action);else appHost.handleControllerReleased(action)}}
    function init(){games.homeAction=0;fake.managerBusy=false;fake.managerRequests=0;games.carouselHost=desktop;games.exiting=false;games.dialogOpen=false;games.keyboardOpen=false;games.runningPanelOpen=false;games.page=0;games.zone="nav";games.visible=true;appHost.visible=false;exits.clear();find(games,"GamesExitModal").visible=false;fake.additions=0;fake.roots=[]}
    function capture(name){waitForRendering(test);wait(150);grabImage(test).save("/gemini/validation/screenshots/"+name+".png")}
    function test_a_home_folder_keyboard_and_modal_isolation(){
        press(106);compare(games.zone,"content");press(304);verify(games.dialogOpen)
        var browser=find(games,"GamesFolderBrowser");verify(browser.visible);compare(browser.location,"")
        var page=games.page;press(311);press(308);press(307);compare(games.page,page);compare(exits.count,0)
        capture("games-folder-volumes-1080")
        press(304);compare(browser.location,"/home/player");press(304);compare(browser.location,"/home/player/Games")
        capture("games-folder-child-1080")
        press(305);compare(browser.location,"/home/player");press(305);compare(browser.location,"");press(305);verify(!games.dialogOpen);compare(fake.additions,0);compare(exits.count,0)
        press(304);press(304);press(108);compare(browser.section,"manual");press(304);verify(games.keyboardOpen)
        var keyboard=find(games,"GamesSystemKeyboard");verify(keyboard.visibleMode);capture("games-system-keyboard-1080")
        keyboard.keyPressed("/Games");press(305);verify(!games.keyboardOpen);verify(games.dialogOpen)
        browser.browse("/home/player/Games");browser.section="save";press(304);verify(!games.dialogOpen);compare(fake.additions,1)
    }
    function test_keyboard_submit_preserves_text_and_cancel_restores(){
        var field=Qt.createQmlObject('import QtQml; QtObject {property string text:"original"}',test)
        games.openKeyboard(field)
        var keyboard=find(games,"GamesSystemKeyboard")
        keyboard.keyPressed("-submitted");compare(field.text,"original-submitted")
        press(315);verify(!games.keyboardOpen);compare(field.text,"original-submitted")
        games.openKeyboard(field);keyboard.keyPressed("-cancelled");press(305)
        verify(!games.keyboardOpen);compare(field.text,"original-submitted");field.destroy()
        games.openInstallationManager();wait(50)
        var manager=find(games,"GamesInstallationManager");manager.step="progress";fake.managerBusy=true
        press(304);verify(manager.installerInput);press(307);verify(games.keyboardOpen)
        keyboard.keyPressed("fixture-text");press(315);verify(!games.keyboardOpen)
        compare(fake.lastInstallerControl,"text");compare(fake.lastInstallerText,"fixture-text");verify(fake.managerBusy)
        fake.managerBusy=false;games.closeDialog()
    }
    function test_b_circle_reuses_exit_modal(){
        press(305);verify(find(games,"GamesExitModal").visible);compare(exits.count,0);capture("games-exit-1080")
        press(305);verify(!find(games,"GamesExitModal").visible);compare(exits.count,0)
        games.page=7;games.settingsTab=0;games.settingsRow=5;games.zone="settings";press(304);verify(find(games,"GamesExitModal").visible)
        press(304);compare(exits.count,1);press(304);compare(exits.count,1)
    }
    function test_f_populated_screens_and_modals(){
        fake.games=[{id:"fixture",title:"A long game title for controller navigation and dynamic layout verification across supported resolutions",kind:"native",confidence:"confirmed",online:true,favorite:true,lastPlayed:"2026-10-09T12:00:00Z",configuration:{runtime:"native"},candidates:["native","windows"],artworkFile:"/home/player/Games/"+"Long artwork folder/".repeat(12)+"poster.png"}]
        for(var size of [[1920,1080],[1280,720],[1024,768]]){
            test.width=size[0];test.height=size[1]
            for(var page=0;page<8;page++){games.page=page;games.zone=page===7?"settings":"content";capture("games-populated-page-"+page+"-"+size[0]+"x"+size[1])}
            games.page=0;games.zone="content";press(103);compare(games.zone,"home-folder");press(304);verify(games.dialogOpen);games.closeDialog()
            for(var kind of ["setup","profile","artwork","title","folder-remove","platform"]){
                games.showDialog(kind);capture("games-modal-"+kind+"-"+size[0]+"x"+size[1]);press(108);press(108);press(108);press(108);press(108);capture("games-modal-"+kind+"-selection-"+size[0]+"x"+size[1]);press(305);verify(!games.dialogOpen)
            }
            games.reviewRuntime("wine","Review a compatible installed runtime before configuration.");capture("games-modal-dependency-"+size[0]+"x"+size[1]);press(305);verify(!games.dialogOpen)
        }
        fake.games=[];test.width=1920;test.height=1080
    }
    function test_c_every_page_and_long_paths(){
        fake.roots=[{path:"/home/player/Games/"+"Very long folder name with spaces/".repeat(12),online:true},{path:"/media/Disconnected Games",online:false}]
        for(var size of [[1920,1080],[1280,720],[1024,768]]){
            test.width=size[0];test.height=size[1]
            for(var i=0;i<8;i++){games.page=i;games.zone=i===7?"settings":"content";capture("games-page-"+i+"-"+size[0]+"x"+size[1])}
            games.page=7;for(var tab=0;tab<8;tab++){games.settingsTab=tab;games.settingsRow=0;capture("games-settings-"+tab+"-"+size[0]+"x"+size[1])}
        }
        test.width=1920;test.height=1080
    }
    Apps.AppHost{id:appHost;anchors.fill:parent;visible:false;launchDelayMs:0}
    Component{id:exclusive;Item{property bool controllerExclusiveLock:true;property int presses:0;property int releases:0;function handleControllerPressed(a){presses++;return true}function handleControllerReleased(a){releases++;return true}}}
    function test_e_shared_carousel_running_apps_and_status(){
        games.carouselHost=desktop;desktop.desktopCarouselIds=["settings","terminal","security"];desktop.desktopCarouselIndex=0
        games.zone="footer";games.footerIndex=0
        press(106);compare(desktop.desktopCarouselIndex,1);press(105);compare(desktop.desktopCarouselIndex,0)
        var original=desktop.desktopCarouselIds.slice();press(307);verify(desktop.desktopCarouselMoveMode);press(106);compare(desktop.desktopCarouselIds[1],"settings");press(106);compare(desktop.desktopCarouselIds[2],"settings");press(305);verify(!desktop.desktopCarouselMoveMode);compare(desktop.desktopCarouselIds,original)
        press(308);verify(desktop.desktopCarouselSettingsOpen);capture("games-carousel-settings");press(305);verify(!desktop.desktopCarouselSettingsOpen);compare(exits.count,0)
        press(105);compare(games.footerIndex,-1);press(304);verify(games.runningPanelOpen);capture("games-running-empty");press(305);verify(!games.runningPanelOpen)
        appManager.runningApps=[{appId:"terminal",runtimeId:"terminal-runtime",name:"Terminal",canFocus:true},{appId:"settings",runtimeId:"stopped",canFocus:false}]
        games.footerIndex=-1;press(304);compare(games.running.length,1);capture("games-running-actual-model");compare(games.runningAppIcon({appId:"terminal"}),appManager.appById("terminal").icon);compare(games.runningAppIcon({appId:"gemini-games",iconSource:"file:///official-installed-artwork.png"}),"file:///official-installed-artwork.png");press(304);compare(appManager.focusedRuntime,"terminal-runtime")
        networkManager.connectionState="CONNECTED";networkManager.connectivity=4;verify(games.wifiConnected);compare(games.wifiConnectivity,4)
        networkManager.connectivity=2;compare(games.wifiConnectivity,2);controllerManager.controllerBatteryAvailable=false;compare(games.battery,-1)
        controllerManager.controllerBatteryAvailable=true;controllerManager.controllerBatteryPercent=63;compare(games.battery,63);capture("games-footer-live-state")
        appManager.runningApps=[]
    }
    Component{id:desktopRestart;Dashboard.ModernDashboard{width:1920;height:1080;visible:false;shellActive:false;appsBackend:appManager;settingsBackend:prefs}}
    Component{id:gamesRestart;Games.Main{width:1920;height:1080;backend:fake}}
    function test_g_footer_order_options_and_shared_configuration(){
        var footer=find(games,"GamesFooter"),brand=find(games,"GamesFooterBrand"),runningButton=find(games,"GamesFooterRunningApps"),carousel=find(games,"GamesFooterCarousel"),wifi=find(games,"GamesFooterWifi"),battery=find(games,"GamesFooterBattery"),clock=find(games,"GamesFooterClock")
        games.footerVisible=false;games.zone="content";games.forceActiveFocus()
        press(315);verify(games.footerVisible);compare(games.zone,"footer");verify(games.activeFocus)
        press(315);verify(!games.footerVisible);compare(games.zone,"content");verify(games.activeFocus)
        press(315);verify(games.footerVisible);compare(games.zone,"footer")
        desktop.desktopCarouselCapacity=12
        for(var size of [[1920,1080],[1280,720],[1024,768]]){
            test.width=size[0];test.height=size[1];wait(100)
            var items=[brand,runningButton,carousel,wifi,battery,clock]
            for(var i=0;i<items.length;i++){
                var p=items[i].mapToItem(footer,0,0)
                verify(p.x>=0&&p.x+items[i].width<=footer.width,"Footer element fits horizontally")
                verify(p.y>=0&&p.y+items[i].height<=footer.height,"Footer element fits vertically")
                if(i)verify(items[i-1].mapToItem(footer,0,0).x+items[i-1].width<=p.x,"Required order without overlap")
            }
            compare(Math.round(carousel.x+carousel.width/2),Math.round(footer.width/2))
            compare(Math.round(clock.mapToItem(footer,0,0).x+clock.width),Math.round(footer.width-14))
            for(var state of [["DISCONNECTED",0,"#ff4057"],["CONNECTED",2,"#ffd45a"],["CONNECTED",4,"#22ff88"]]){
                networkManager.connectionState=state[0];networkManager.connectivity=state[1];compare(wifi.tint,state[2]);capture("games-footer-corrected-"+size[0]+"-"+state[1]+"-"+state[0])
            }
        }
        desktop.desktopCarouselIds=["security","settings"];desktop.persistDesktopCarouselConfig();wait(20)
        compare(carousel.item.host.desktopCarouselResolvedApps.map(function(a){return a.id}),["security","settings"])
        games.footerIndex=0;desktop.desktopCarouselIndex=0;press(307);press(106);press(304)
        compare(desktop.desktopCarouselIds,["settings","security"])
        compare(JSON.parse(prefs.value(desktop.desktopCarouselIdsKey(),"")),["settings","security"])
        var restartedGames=gamesRestart.createObject(test,{carouselHost:desktop});verify(restartedGames!==null)
        compare(find(restartedGames,"GamesFooterCarousel").item.host,desktop);restartedGames.destroy()
        var restartedDesktop=desktopRestart.createObject(test);verify(restartedDesktop!==null)
        restartedDesktop.restoreDesktopCarouselConfig();compare(restartedDesktop.desktopCarouselIds,["settings","security"])
        restartedDesktop.destroy();test.width=1920;test.height=1080
    }
    function test_d_onboarding_exclusive_input(){
        games.visible=false;appHost.visible=true
        var loader=find(appHost,"AppHostQmlLoader"),overlay=find(appHost,"AppHostHelpOverlay")
        loader.active=true;loader.sourceComponent=exclusive;tryVerify(function(){return loader.item!==null})
        for(var launch=1;launch<=3;launch++){
            loader.item.presses=0;loader.item.releases=0;overlay.openAutomatic({id:"gemini-games",name:"Games"},launch)
            for(var code of [103,108,105,106,308,307,310,311,312,313,314,315,317,318])press(code)
            compare(loader.item.presses,0);compare(loader.item.releases,0);verify(overlay.visible)
            capture("games-onboarding-launch-"+launch)
            // X and Circle dismiss only the wizard; neither reaches the app.
            press(launch===2?305:304);verify(!overlay.visible);compare(loader.item.presses,0)
            press(106);compare(loader.item.presses,1)
        }
        loader.sourceComponent=null;appHost.visible=false;games.visible=true
    }
    function test_h_installer_controller_modal_and_keyboard(){
        games.page=0;games.zone="home-folder";games.homeAction=0;press(106);compare(games.homeAction,1);press(304);verify(games.dialogOpen);compare(games.dialogKind,"installation")
        var manager=find(games,"GamesInstallationManager");verify(manager.visible);wait(50);compare(manager.step,"menu")
        var originalPage=games.page,originalZone=games.zone
        for(var code of [315,307,308,310,311,312,313])press(code)
        compare(games.page,originalPage);compare(games.zone,originalZone);compare(exits.count,0)
        capture("games-installer-menu-1080")
        press(304);wait(50);compare(manager.step,"picker");capture("games-installer-volumes-1080")
        press(304);wait(50);compare(manager.location,"/home/player");press(304);wait(50);compare(manager.location,"/home/player/Games")
        press(108);compare(manager.pickerSection,"manual");press(304);verify(games.keyboardOpen);capture("games-installer-system-keyboard-1080");press(305);verify(!games.keyboardOpen);verify(games.dialogOpen)
        manager.chosen("/home/player/Games/setup.exe");wait(50);compare(manager.step,"candidates");capture("games-installer-candidates-1080")
        press(304);compare(manager.step,"form");capture("games-installer-configuration-1080")
        press(304);compare(manager.step,"runtimes");press(304);compare(manager.step,"form");compare(manager.runtimeId,"wine");compare(fake.lastManagerRequest.action,"inspect")
        manager.selection=12;press(304);compare(manager.step,"install-review");capture("games-installer-explicit-approval-1080")
        var count=fake.managerRequests;press(305);compare(manager.step,"form");compare(fake.managerRequests,count)
        fake.managerBusy=true;press(305);verify(manager.cancelReview);press(315);verify(games.dialogOpen);compare(exits.count,0);fake.managerBusy=false
        games.closeDialog();compare(games.zone,"home-folder")
    }
    function test_i_installer_layout_at_supported_resolutions(){
        games.openInstallationManager();wait(50);var manager=find(games,"GamesInstallationManager")
        for(var size of [[1920,1080],[1280,720],[1024,768]]){
            test.width=size[0];test.height=size[1]
            for(var stage of ["menu","managed","actions","form","runtimes","install-review","patch-review","restore-review","remove-review","runtime-missing","progress","result"]){
                manager.step=stage;manager.preview={source:"/home/player/"+"long-source/".repeat(14)+"patch.exe",target:"/home/player/"+"long-target/".repeat(14)+"game.exe",originalSHA256:"a".repeat(64),patchSHA256:"b".repeat(64),token:"fixture"};capture("games-installation-"+stage+"-"+size[0]+"x"+size[1])
                for(var code of [103,108,105,106,310,311,315])press(code)
                verify(games.dialogOpen);compare(exits.count,0)
            }
        }
        games.closeDialog();test.width=1920;test.height=1080
    }

}
