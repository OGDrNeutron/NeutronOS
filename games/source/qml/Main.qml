import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "native/review5" as Native
import "../../components" as Shared

FocusScope {
    id: root
    objectName: "GeminiGamesApp"
    anchors.fill: parent
    focus: true
    property var activeUser: null
    property bool developerModeEnabled: false
    readonly property bool controllerExclusiveLock: true
    property var backend: Native.GamesBackend
    readonly property var applications: typeof appManager !== "undefined" ? appManager : null
    readonly property var systemController: typeof controllerManager !== "undefined" ? controllerManager : null
    property var storeBackend: typeof appStoreManager !== "undefined" ? appStoreManager : null
    property string runtimeReason: ""
    property string pendingRuntimePackage: ""
    property string pendingLaunchId: ""
    property bool pendingLaunchReady: false
    property bool returnToInstaller: false
    property int homeAction: 0
    property var shellRoot: null
    property var navigation: ["Home", "Library", "Platforms", "Favorites", "Recently Played", "Play Now", "Emulators", "Settings"]
    property var navSymbols: ["⌂", "▦", "◇", "☆", "◷", "▷", "♧", "⚙"]
    property int page: 0
    property string zone: "nav"
    property int selectedGame: 0
    property int selectedPlatform: 0
    property int selectedDetail: 0
    property int settingsTab: 0
    property int settingsRow: 0
    property int footerIndex: 0
    property int installedIndex: 0
    property bool runningPanelOpen: false
    property var carouselHost: null
    property var keyboardField: null
    property string keyboardOriginal: ""
    property bool exiting: false
    property var modalConsumedActions: ({})
    readonly property var network: typeof networkManager!=="undefined" ? networkManager : null
    property date localNow: new Date()
    readonly property bool wifiConnected: !!network && network.connectionState==="CONNECTED"
    readonly property int wifiConnectivity: network && network.connectivity!==undefined ? network.connectivity : 0
    readonly property int battery: systemController && systemController.controllerConnected && systemController.controllerBatteryAvailable===true && isFinite(Number(systemController.controllerBatteryPercent)) ? Math.max(0,Math.min(100,Math.round(Number(systemController.controllerBatteryPercent)))) : -1
    readonly property bool carouselModal: !!carouselHost && (carouselHost.desktopCarouselSettingsOpen || carouselHost.desktopCarouselRemoveModalOpen || carouselHost.desktopCarouselMoveMode)
    signal backgroundRequested()
    property int messageIndex: 0
    property bool footerVisible: true
    property bool footerManual: false
    property string footerReturnZone: "nav"
    property bool installedCarousel: false
    property string platformFilter: ""
    property string searchText: ""
    property int libraryFilter: 0
    property bool dialogOpen: false
    property string dialogKind: ""
    property int dialogRow: 0
    property bool keyboardOpen: false
    property int keyboardIndex: 0
    property bool suspendOffline: false
    property bool networkAllowed: false
    property string previousZone: "nav"
    property string runtimeChoice: ""
    property string selectedId: ""
    property var settingsTabs: ["General", "Performance", "Emulators", "Graphics", "Controllers", "Library", "Appearance", "Advanced"]
    readonly property var running: applications ? applications.runningApps.filter(function(a){return a.canFocus === true}) : []
    readonly property var installed: applications ? applications.apps.filter(function(a){return a.id !== "gemini-games" && a.hidden !== true && a.id !== "games" && (!a.platforms || a.platforms.indexOf("gemini") >= 0)}) : []
    readonly property var gameItems: {
        // Observe the property signal once; a returned sequence is a value copy.
        // Slicing a C++ reference sequence can call its getter for every item.
        var observed=backend.games
        var list=backend.gameSnapshot ? backend.gameSnapshot() : observed.slice()
        list=list.filter(function(g){
            if(g.managed===false)return false
            if(page===3 && !g.favorite)return false
            if(page===4 && !g.lastPlayed)return false
            if(page===5 && (!g.online || !g.configuration || !g.configuration.runtime))return false
            if(platformFilter && String(g.chosenKind || g.kind)!==platformFilter)return false
            if(searchText && String(g.titleOverride || g.title).toLowerCase().indexOf(searchText.toLowerCase())<0)return false
            if(libraryFilter===1 && !g.online)return false
            if(libraryFilter===2 && !g.favorite)return false
            return true
        })
        list.sort(function(a,b){return page===4 ? String(b.lastPlayed).localeCompare(String(a.lastPlayed)) : String(a.titleOverride || a.title).localeCompare(String(b.titleOverride || b.title))})
        return list
    }
    readonly property var currentGame: selectedGame>=0 && selectedGame<gameItems.length ? gameItems[selectedGame] : ({})
    readonly property var platforms: {
        var counts={};backend.games.forEach(function(g){if(g.managed===false)return;var k=String(g.chosenKind || g.kind);counts[k]=(counts[k] || 0)+1})
        return Object.keys(counts).sort().map(function(k){return {name:k,count:counts[k]}})
    }
    readonly property var recent: backend.games.filter(function(g){return g.managed!==false && !!g.lastPlayed}).sort(function(a,b){return String(b.lastPlayed).localeCompare(String(a.lastPlayed))}).slice(0,4)
    readonly property var pendingMessages: backend.messages.map(function(m,i){return {text:m.text,critical:m.critical,acknowledged:m.acknowledged,index:i}}).filter(function(m){return !m.acknowledged})
    readonly property var settingRows: {
        switch(settingsTab) {
        case 0:return ["Add Folder", "Edit Selected Folder", "Remove Selected Folder", backend.scanning?"Cancel Indexing":"Rescan Library", "Automatic Scanning", "Exit Games"]
        case 1:return ["Low-resource Gaming Session", "Measured CPU / RAM / GPU", "PC Power Policy Availability"]
        case 2:return backend.installedRuntimes.map(function(r){return r.id+"  ·  "+(r.installed?"Installed":"Not installed")})
        case 3:return ["Display / GPU Diagnostics", "Runtime Fullscreen Capabilities"]
        case 4:return ["Controller Status", "Selected Game Controller Profile", "Controller Mapping Documentation"]
        case 5:return ["Selected Game Artwork", "Selected Game Title", "Possible Duplicates", "Refresh Artwork", "Rescan Library"]
        case 6:return ["Interface Animations", "Show Game Artwork"]
        default:return ["Session Resource Measurements", "Game Log Location", "Rebuild Library Index", "Reset Interface Preferences"]
        }
    }
    property int selectedFolder: 0

    readonly property real scaleFactor: width/1672
    signal exitRequested()
    signal appReady()

    function normalized(action) {
        var a=String(action).toLowerCase()
        return a==="x" || a==="cross" ? "primary" : a==="o" || a==="circle" ? "cancel" : a==="triangle" ? "context" : a==="square" ? "secondary" : a==="start" || a==="options" ? "system" : a
    }
    function runningAppIcon(runtime) {
        var raw=String(runtime.iconSource||runtime.icon||"")
        if(raw.indexOf(":")>=0||raw.indexOf("/")>=0)return raw
        var app=carouselHost?carouselHost.findBaseAppById(runtime.appId):null
        if(!app&&applications)app=applications.appById(runtime.appId)
        return carouselHost?carouselHost.appIconSource(app):raw
    }
    function moveZone(next) {zone=next;if(next!=="footer")installedCarousel=false;forceActiveFocus()}
    function persist() {backend.setUiState({page:page,selectedGame:selectedGame,selectedId:String(currentGame.id || ""),platformFilter:platformFilter,settingsTab:settingsTab,settingsRow:settingsRow})}
    function onAppBackgrounding() {persist()}
    function onAppClosing() {persist()}
    function reviewRuntime(id,reason) {
        if(backend.gameActive){backend.notify("Close the active game before installing or updating a runtime.");return}
        previousZone=zone;runtimeChoice=id;runtimeReason=reason || "Required by games configured for "+id+"."
        dialogKind="dependency";dialogOpen=true;moveZone("dialog")
    }
    function openExit() { if(backend.managerBusy){backend.notify("Finish or cancel the installer before exiting Games.");return}if(!dialogOpen && !runningPanelOpen && !exiting)exitModal.openModal(root) }
    function openKeyboard(field) {keyboardField=field;keyboardOriginal=field.text;keyboardOpen=true;systemKeyboard.openKeyboard("small");if(root.Window.window){root.Window.window.show();root.Window.window.raise();root.Window.window.requestActivate()}systemKeyboard.forceActiveFocus()}
    function closeKeyboard(cancel) {if(cancel&&keyboardField)keyboardField.text=keyboardOriginal;keyboardOpen=false;systemKeyboard.closeKeyboard();root.forceActiveFocus()}
    function openInstallationManager() {previousZone=zone;dialogKind="installation";dialogOpen=true;moveZone("dialog");installationManager.open(currentGame)}
    function showDialog(kind) {
        if(kind==="setup"&&currentGame.installation){openInstallationManager();installationManager.game=currentGame.installation;installationManager.operation="configure";installationManager.beginForm();return}
        previousZone=zone;dialogKind=kind;dialogRow=0;keyboardOpen=false;dialogOpen=true;selectedId=String(currentGame.id || "");inputA.text="";inputB.text="";inputC.text="";inputD.text="";suspendOffline=false;networkAllowed=false
        if(kind==="folder-edit" && backend.roots.length)inputA.text=backend.roots[selectedFolder].path
        if(kind==="setup") {var rec=backend.recommendations(selectedId);runtimeChoice=rec.length?String(rec[0].id):"";var c=currentGame.configuration || {};inputA.text=c.launcher || "";inputB.text=c.core || "";inputC.text=JSON.stringify(c.arguments || []);suspendOffline=!!c.offlineSuspend;networkAllowed=!!c.network}
        if(kind==="profile") {var p=currentGame.controllerProfile || {};inputA.text=JSON.stringify(p.buttons || {});inputB.text=JSON.stringify(p.invertAxes || []);inputC.text=p.sdlMapping || "";inputD.text=JSON.stringify(p.assignments || {})}
        if(kind==="title")inputA.text=currentGame.titleOverride || currentGame.title || ""
        if(kind==="artwork")inputA.text=String(currentGame.artworkOverride || currentGame.artwork || "").replace(/^file:\/\//,"")
        moveZone("dialog")
        if(kind==="folder" || kind==="folder-edit")folderBrowser.open(kind==="folder-edit"?selectedFolder:-1)
    }
    function closeDialog() {if(keyboardOpen)closeKeyboard(true);dialogOpen=false;moveZone(previousZone)}
    function saveDialog() {
        if(dialogKind==="folder"){if(!backend.addFolder(inputA.text))return}
        else if(dialogKind==="folder-edit"){if(!backend.editFolder(selectedFolder,inputA.text))return}
        else if(dialogKind==="folder-remove"){if(!backend.removeFolder(selectedFolder)){backend.notify("Folder could not be removed from the saved library.",true);return}}
        else if(dialogKind==="setup") {
            var args
            try {args=JSON.parse(inputC.text || "[]");if(!Array.isArray(args))throw new Error("Arguments must be an array")}catch(e){backend.notify("Arguments must be a JSON array of strings.",true);return}
            if(!backend.configure(selectedId,{runtime:runtimeChoice,launcher:inputA.text,core:inputB.text,arguments:args,offlineSuspend:suspendOffline,network:networkAllowed},true))return
        } else if(dialogKind==="profile") {
            try {if(!backend.setControllerProfile(selectedId,{buttons:JSON.parse(inputA.text || "{}"),invertAxes:JSON.parse(inputB.text || "[]"),sdlMapping:inputC.text,assignments:JSON.parse(inputD.text || "{}")}))throw new Error("Profile rejected")}catch(e){backend.notify("Invalid controller profile: "+e,true);return}
        } else if(dialogKind==="title" || dialogKind==="artwork")backend.updateMetadata(selectedId,dialogKind,inputA.text)
        closeDialog()
    }
    function playSelected() {
        if(!currentGame.id)return
        if(currentGame.requiresExtraction){backend.notify("This archive needs user-authorized extraction and a compatible installed runtime. Original game files have not been changed.");return}
        if(storeBackend&&storeBackend.busy){backend.notify("Wait for the current App Store operation before launching a game.");return}
        if(String(currentGame.confidence)==="ambiguous"&&!currentGame.chosenKind){showDialog("platform");return}
        if(!currentGame.configuration || !currentGame.configuration.runtime){showDialog("setup");return}
        persist();backend.play(currentGame.id)
    }
    function activateApp(app, runtimeId) {
        if(!applications||!app)return
        if(!backend.prepareSwitch())return
        persist()
        if(runtimeId && applications.focusRuntime(runtimeId))return
        if(shellRoot && typeof shellRoot.switchFromPackageSession==="function")shellRoot.switchFromPackageSession(app)
        else backend.notify("App switching requires the installed Gemini shell integration.",true)
    }
    function settingsAction() {
        var row=settingsRow
        if(settingsTab===0){if(row===0)showDialog("folder");else if(row===1)showDialog("folder-edit");else if(row===2)showDialog("folder-remove");else if(row===3){if(backend.scanning)backend.cancelIndexing();else backend.rescan();}else if(row===4)backend.setPreference("automaticScan",backend.preferences.automaticScan===false);else openExit()}
        else if(settingsTab===1){if(row===0)backend.setPreference("lowResource",backend.preferences.lowResource===false);else if(row===1)backend.notify(JSON.stringify(backend.resourceSample()));else backend.notify("PC clock/power controls are unavailable until a supported Gemini policy service is verified. No hardware settings changed.")}
        else if(settingsTab===2){var r=backend.installedRuntimes[row];if(!r.installed&&r.capabilities.launch)reviewRuntime(r.id);else backend.notify(r.installed ? r.id+" is installed. Configure per game; runtime availability does not guarantee compatibility." : r.id+" has no supported Gemini launch adapter yet.")}
        else if(settingsTab===3)backend.notify(row===0?JSON.stringify(backend.hardware):"Fullscreen is requested only through supported runtime flags; arbitrary GPU/scaling/FPS overrides are not applied.")
        else if(settingsTab===4){
            if(row===1&&currentGame.id)showDialog("profile")
            else if(row===0)backend.notify(systemController && systemController.controllerConnected ? "Connected: "+(systemController.controllerDisplayName || systemController.controllerName)+"\n"+systemController.inputSource : "No controller is registered in the current Gemini interface.")
            else backend.notify("The default profile preserves your controller layout. Select a game to change its buttons or invert a stick. Hold PS/Home for three seconds during play to open the game menu.")
        }
        else if(settingsTab===5){if(row===0&&currentGame.id)showDialog("artwork");else if(row===1&&currentGame.id)showDialog("title");else if(row===2)backend.notify("Possible duplicates use sampled content plus file size; no games are merged or deleted automatically. "+JSON.stringify(currentGame.possibleDuplicates || []));else if(row===3)backend.refreshArtwork();else backend.rescan()}
        else if(settingsTab===6)backend.setPreference(row===0?"animations":"artwork",backend.preferences[row===0?"animations":"artwork"]===false)
        else if(row===0)backend.notify(JSON.stringify(backend.resourceSample()));else if(row===1)backend.notify(backend.logPath());else if(row===2)backend.rescan();else {backend.setPreference("animations",true);backend.setPreference("artwork",true);backend.setPreference("lowResource",true)}
    }
    function revealDialogSelection() {
        if(!dialogOpen||["setup","title","folder-remove"].indexOf(dialogKind)<0)return
        var items=dialogKind==="setup"?[inputA,inputB,inputC].concat(runtimeChoice==="native"?[offlineToggle,networkToggle,dialogSave]:[networkToggle,dialogSave]):dialogKind==="title"?[inputA,dialogSave]:[dialogSave]
        var item=items[Math.min(dialogRow,items.length-1)]
        if(!item)return
        var point=item.mapToItem(dialogColumn,0,0)
        if(point.y<dialogScroll.contentY)dialogScroll.contentY=point.y
        else if(point.y+item.height>dialogScroll.contentY+dialogScroll.height)dialogScroll.contentY=Math.min(Math.max(0,dialogScroll.contentHeight-dialogScroll.height),point.y+item.height-dialogScroll.height)
    }
    onDialogRowChanged:Qt.callLater(revealDialogSelection)
    function revealDetailSelection(){
        if(zone!=="detail")return
        var item=detailActions.itemAt(selectedDetail);if(!item)return
        var y=item.mapToItem(detailColumn,0,0).y
        if(y<detailScroll.contentY)detailScroll.contentY=y
        else if(y+item.height>detailScroll.contentY+detailScroll.height)detailScroll.contentY=Math.min(Math.max(0,detailScroll.contentHeight-detailScroll.height),y+item.height-detailScroll.height)
    }
    onSelectedDetailChanged:Qt.callLater(revealDetailSelection)
    function dialogFields(){return dialogKind==="setup"?3:dialogKind==="profile"?4:dialogKind==="folder-remove"||dialogKind==="platform"?0:1}
    function handleControllerPressed(action) {
        var a=normalized(action)
        if(exitModal.visible||keyboardOpen||dialogOpen||runningPanelOpen||carouselModal)modalConsumedActions[a]=true
        if(exiting)return true
        if(exitModal.visible){exitModal.handleController(a);return true}
        if(keyboardOpen){systemKeyboard.handleControllerPressed(a);return true}
        if(backend.gameActive && !backend.backgrounded)return true
        if(dialogOpen) {
            if(dialogKind==="installation"){installationManager.handleControllerPressed(a);return true}
            if(dialogKind==="folder"||dialogKind==="folder-edit"){folderBrowser.handleControllerPressed(a);return true}
            if(dialogKind==="dependency"){runtimeApproval.handleControllerPressed(a);return true}
            if(dialogKind==="artwork"){artworkDialog.handleControllerPressed(a);return true}
            if(dialogKind==="profile"){controllerProfile.handleControllerPressed(a);return true}

            if(a==="cancel"){closeDialog();return true}
            if(dialogKind==="platform"){var choices=currentGame.candidates || [];if(a==="up")dialogRow=Math.max(0,dialogRow-1);else if(a==="down")dialogRow=Math.min(choices.length-1,dialogRow+1);else if(a==="primary"){backend.choosePlatform(selectedId,choices[dialogRow]);closeDialog()}return true}
            var max=dialogFields()+(dialogKind==="setup"?(runtimeChoice==="native"?2:1):0)
            if(a==="up")dialogRow=Math.max(0,dialogRow-1)
            else if(a==="down")dialogRow=Math.min(max,dialogRow+1)
            else if(a==="primary"){if(dialogRow<dialogFields()){openKeyboard(dialogRow===0?inputA:dialogRow===1?inputB:dialogRow===2?inputC:inputD)}else if(dialogKind==="setup"&&runtimeChoice==="native"&&dialogRow===3)suspendOffline=!suspendOffline;else if(dialogKind==="setup"&&dialogRow===(runtimeChoice==="native"?4:3))networkAllowed=!networkAllowed;else saveDialog()}
            return true
        }
        if(runningPanelOpen){
            if(a==="cancel"){runningPanelOpen=false;root.forceActiveFocus()}
            else if(a==="left"||a==="up")footerIndex=Math.max(0,footerIndex-1)
            else if(a==="right"||a==="down")footerIndex=Math.min(Math.max(0,running.length-1),footerIndex+1)
            else if(a==="primary"&&running.length){var app=running[footerIndex];runningPanelOpen=false;activateApp(applications.appById(app.appId),app.runtimeId)}
            return true
        }
        if(carouselModal){carouselHost.handleSharedCarouselPressed(a);root.forceActiveFocus();return true}
        if(a==="cancel"){openExit();return true}
        if(a==="system") {backend.cancelFooterCountdown();footerManual=true;footerVisible=!footerVisible;if(footerVisible){footerReturnZone=zone;moveZone("footer")}else moveZone(footerReturnZone);return true}
        if(((a==="r1"&&zone!=="settings")||(a==="context"&&page===7))&&pendingMessages.length){messageIndex=0;moveZone("messages");return true}
        if(zone==="messages"){if(a==="left"||a==="up")messageIndex=Math.max(0,messageIndex-1);else if(a==="right"||a==="down")messageIndex=Math.min(pendingMessages.length-1,messageIndex+1);else if(a==="primary"&&pendingMessages.length){backend.acknowledge(pendingMessages[messageIndex].index);messageIndex=Math.max(0,Math.min(messageIndex,pendingMessages.length-1));if(!pendingMessages.length)moveZone("nav")}else if(a==="cancel")moveZone("nav");return true}
        if(zone==="footer") {
            if(a==="up"){moveZone(footerReturnZone);return true}
            if(footerIndex===-1){
                if(a==="right")footerIndex=0
                else if(a==="primary"){footerIndex=0;runningPanelOpen=true}
                return true
            }
            if(carouselHost){
                if(a==="left"&&carouselHost.desktopCarouselIndex===0)footerIndex=-1
                else if(a==="primary")activateApp(carouselHost.selectedDesktopCarouselApp())
                else carouselHost.handleSharedCarouselPressed(a)
                root.forceActiveFocus()
            }
            return true
        }
        if(zone==="home-folder") {
            if(a==="primary"){if(homeAction===0)showDialog("folder");else openInstallationManager()}
            else if(a==="right")homeAction=1
            else if(a==="left"&&homeAction===1)homeAction=0
            else if(a==="down")moveZone("content")
            else if(a==="left")moveZone("nav")
            return true
        }
        if(zone==="nav") {
            if(a==="up")page=Math.max(0,page-1)
            else if(a==="down")page=Math.min(navigation.length-1,page+1)
            else if(a==="right"||a==="primary")moveZone(page===7?"tabs":"content")
            else if(a==="cancel"){persist();exitRequested()}
            selectedGame=0;platformFilter="";return true
        }
        if(zone==="tabs") {if(a==="left"){if(settingsTab===0)moveZone("nav");else settingsTab--}else if(a==="right")settingsTab=Math.min(settingsTabs.length-1,settingsTab+1);else if(a==="down"||a==="primary"){settingsRow=0;moveZone("settings")}else if(a==="cancel")moveZone("nav");return true}
        if(zone==="settings") {if(a==="up"){if(settingsRow===0)moveZone("tabs");else settingsRow--}else if(a==="down")settingsRow=Math.min(settingRows.length-1,settingsRow+1);else if(a==="left"||a==="cancel")moveZone("nav");else if(a==="l1")selectedFolder=Math.max(0,selectedFolder-1);else if(a==="r1")selectedFolder=Math.min(backend.roots.length-1,selectedFolder+1);else if(a==="primary")settingsAction();return true}
        if(zone==="detail") {if(a==="up")selectedDetail=Math.max(0,selectedDetail-1);else if(a==="down")selectedDetail=Math.min(4,selectedDetail+1);else if(a==="left"||a==="cancel")moveZone("content");else if(a==="primary"){if(selectedDetail===0)playSelected();else if(selectedDetail===1)showDialog("setup");else if(selectedDetail===2)backend.favorite(currentGame.id,!currentGame.favorite);else if(selectedDetail===3)showDialog("profile");else openInstallationManager()}return true}
        if(page===2){if(a==="left"){if(selectedPlatform%4===0)moveZone("nav");else selectedPlatform--}else if(a==="right")selectedPlatform=Math.min(platforms.length-1,selectedPlatform+1);else if(a==="up")selectedPlatform=Math.max(0,selectedPlatform-4);else if(a==="down")selectedPlatform=Math.min(platforms.length-1,selectedPlatform+4);else if(a==="primary"&&platforms.length){platformFilter=platforms[selectedPlatform].name;page=1;selectedGame=0}else if(a==="cancel")moveZone("nav");return true}
        if(page===6){if(a==="up")selectedGame=Math.max(0,selectedGame-1);else if(a==="down")selectedGame=Math.min(backend.installedRuntimes.length-1,selectedGame+1);else if(a==="left"||a==="cancel")moveZone("nav");else if(a==="primary")backend.notify(JSON.stringify(backend.installedRuntimes[selectedGame]));return true}
        if(page===0&&a==="up"){moveZone("home-folder");return true}
        if(page===0&&a==="primary"){if(currentGame.id)playSelected();else showDialog("folder");return true}
        var columns=page===0?1:5
        if(a==="left"){if(selectedGame%columns===0)moveZone("nav");else selectedGame--}
        else if(a==="right"){if(selectedGame+1>=gameItems.length || (page!==0&&selectedGame%columns===4))moveZone("detail");else selectedGame++}
        else if(a==="up")selectedGame=Math.max(0,selectedGame-columns)
        else if(a==="down")selectedGame=Math.min(gameItems.length-1,selectedGame+columns)
        else if(a==="primary"){selectedDetail=0;moveZone("detail")}
        else if(a==="secondary")showDialog("setup")
        else if(a==="context"&&currentGame.id)backend.favorite(currentGame.id,!currentGame.favorite)
        else if(a==="l1")libraryFilter=(libraryFilter+1)%3
        else if(a==="cancel")moveZone("nav")
        return true
    }
    function handleControllerReleased(action) {
        var a=normalized(action)
        if(keyboardOpen){systemKeyboard.handleControllerReleased(a);delete modalConsumedActions[a];return true}
        if(carouselModal&&carouselHost){carouselHost.handleControllerReleased(a);delete modalConsumedActions[a];return true}
        if(modalConsumedActions[a]){delete modalConsumedActions[a];return true}
        if(!dialogOpen&&!exitModal.visible&&!runningPanelOpen&&zone==="footer"&&carouselHost)carouselHost.handleControllerReleased(a)
        return true
    }
    onZoneChanged: if(zone!=="footer")installedCarousel=false
    onGameItemsChanged: selectedGame=Math.max(0,Math.min(selectedGame,gameItems.length-1))
    onRunningChanged: footerIndex=Math.max(0,Math.min(footerIndex,running.length-1))
    onActiveUserChanged: {
        backend.initialize()
        var state=backend.uiState()
        page=Number(state.page || 0);settingsTab=Number(state.settingsTab || 0)
        selectedGame=Number(state.selectedGame || 0);platformFilter=String(state.platformFilter || "")
        selectedId="";pendingRuntimePackage="";dialogOpen=false
        moveZone("nav")
    }
    Connections { target: root.backend
        function onManagerFinished(action,success,result){if(action==="status"&&root.pendingLaunchReady&&root.pendingLaunchId){var id=root.pendingLaunchId;root.pendingLaunchId="";root.pendingLaunchReady=false;if(!root.backend.play(id))root.backend.notify("The installed runtime could not launch the game. Review its per-game settings.",true)}}
        function onRuntimeMissing(gameId,runtime){root.pendingLaunchId=gameId;root.reviewRuntime(runtime,"The configured runtime is missing. Cancel to keep this game registered without installing software.")}
        function onFooterTimeout(){if(!root.footerManual){root.footerVisible=false;if(root.zone==="footer")root.moveZone(root.footerReturnZone)}}
        function onRestoreRequested(){root.footerVisible=false;root.moveZone("content")}
        function onMessagePublished(message,critical){if(typeof notificationManager!=="undefined")notificationManager.publish("applications","Gemini Games",message,critical?"critical":"normal","gemini-games","open-gemini-games",({}))}
    }
    Connections {
        target: root.storeBackend
        function onOperationFinished(packageId,operation,success,message) {
            if(packageId!==root.pendingRuntimePackage)return
            root.pendingRuntimePackage=""
            root.backend.refreshRuntimes()
            root.backend.notify(success?"Runtime package verified. Checking the selected runtime before retrying.":message,!success)
            root.pendingLaunchReady=success&&root.pendingLaunchId.length>0
            if(!success)root.pendingLaunchId=""
            if(root.returnToInstaller){root.returnToInstaller=false;root.openInstallationManager()}
        }
    }
    Component.onCompleted: {
        backend.cancelFooterCountdown();backend.initialize();var state=backend.uiState();page=Number(state.page || 0);settingsTab=Number(state.settingsTab || 0);selectedGame=Number(state.selectedGame || 0);platformFilter=String(state.platformFilter || "")
        backend.menuSource=Qt.resolvedUrl("GameMenu.qml");backend.attachWindow(root.Window.window)
        var parentItem=root.parent
        while(parentItem){if(parentItem.objectName==="GeminiMainRoot"){shellRoot=parentItem;if(typeof parentItem.registerPackageSession === "function")parentItem.registerPackageSession(backend);break}parentItem=parentItem.parent}
        carouselHost=shellRoot&&typeof shellRoot.sharedDesktopCarousel==="function"?shellRoot.sharedDesktopCarousel():null
        appReady()
    }
    Component.onDestruction: {backend.cancelFooterCountdown();persist()}
    Keys.onPressed: function(event) {var a=event.key===Qt.Key_Up?"up":event.key===Qt.Key_Down?"down":event.key===Qt.Key_Left?"left":event.key===Qt.Key_Right?"right":event.key===Qt.Key_Return?"primary":event.key===Qt.Key_Escape?"cancel":event.key===Qt.Key_F1?"system":event.key===Qt.Key_F2?"secondary":event.key===Qt.Key_F3?"context":"";if(a){handleControllerPressed(a);event.accepted=true}}

    SpaceBackdrop { anchors.fill: parent }
    Item {
        id: surface
        anchors.fill: parent
        visible: !backend.gamingMode || backend.menuOpen
        enabled: !root.dialogOpen && !root.keyboardOpen && !exitModal.visible && !root.runningPanelOpen && !root.carouselModal
        ControllerGlyph { x: 22*root.scaleFactor; y: 12*root.scaleFactor; width: 120*root.scaleFactor; height: 85*root.scaleFactor }
        Text { x: 164*root.scaleFactor; y: 24*root.scaleFactor; text: "G A M E S"; color: "#eaf7ff"; font.pixelSize: 39*root.scaleFactor; font.letterSpacing: 7 }
        Text { anchors.right: parent.right; anchors.rightMargin: 32; y: 24; text: "NEUTRONOS GEMINI  /  AMD64"; color: "#51bfe8"; font.pixelSize: 13; font.letterSpacing: 2 }
        NeonPanel {
            x: 20*root.scaleFactor; y: 119*root.scaleFactor; width: 215*root.scaleFactor; height: parent.height-y-90*root.scaleFactor
            Column { anchors { fill: parent; margins: 8*root.scaleFactor } spacing: 6*root.scaleFactor
                Repeater { model: root.navigation
                    NeonPanel { width: parent.width; height: 57*root.scaleFactor; illuminated: root.page===index && root.zone==="nav"; fill: root.page===index?"#d0051230":"transparent"; radius: 10
                        Row { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 14*root.scaleFactor } spacing: 17*root.scaleFactor
                            Text { text: root.navSymbols[index]; color: "#eafaff"; font.pixelSize: 32*root.scaleFactor }
                            Text { text: index===4?"Recent":modelData; color: "#dde9f6"; font.pixelSize: 18*root.scaleFactor; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: {root.page=index;root.selectedGame=0;root.platformFilter="";root.moveZone("nav")} }
                    }
                }
            }
        }
        NeonPanel {
            id: mainPanel
            x: 253*root.scaleFactor; y: 77*root.scaleFactor; width: parent.width-x-16*root.scaleFactor; height: parent.height-y-105*root.scaleFactor
            radius: 18
            Text { x: 28; y: 17; text: root.navigation[root.page]+(root.platformFilter?" / "+root.platformFilter:""); color: "white"; font.pixelSize: 34*root.scaleFactor; font.bold: true }
            Text { anchors.right: parent.right; anchors.rightMargin: 26; y: 29; text: backend.scanning ? "INDEXING · "+backend.scannedEntries+" CHECKED" : backend.games.length+" DISCOVERED  ·  L1 FILTER"; color: "#66c8ed"; font.pixelSize: 13 }
            Item {
                id: libraryBody
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 16; topMargin: 75 }
                visible: root.page!==7&&root.page!==2&&root.page!==6
                Item {
                    id: hero
                    x: 0; y: 0; width: parent.width; height: parent.height*0.48; visible: root.page===0
                    NeonPanel { anchors.fill: parent; radius: 16 }
                    Image { anchors.fill: parent; anchors.margins: 2; source: root.currentGame.artworkDisplay || root.currentGame.artwork || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: 0.65 }
                    Rectangle { anchors.fill: parent; color: "transparent"; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop {position: 0; color: "#fa010610"} GradientStop {position: 0.65; color: "#40010a13"} GradientStop {position: 1; color: "#0c010810"} } }
                    NeonPanel {anchors{right:parent.right;top:parent.top;margins:24}width:190*root.scaleFactor;height:44*root.scaleFactor;illuminated:root.zone==="home-folder"&&root.homeAction===0
                        Text{anchors.centerIn:parent;text:"+ Add Folder";color:"white";font.pixelSize:18*root.scaleFactor}
                        MouseArea{anchors.fill:parent;onClicked:root.showDialog("folder")}
                    }
                    NeonPanel {anchors{right:parent.right;top:parent.top;rightMargin:24;topMargin:78*root.scaleFactor}width:190*root.scaleFactor;height:44*root.scaleFactor;illuminated:root.zone==="home-folder"&&root.homeAction===1
                        Text{anchors.centerIn:parent;text:"Install / Import";color:"white";font.pixelSize:18*root.scaleFactor}
                        MouseArea{anchors.fill:parent;onClicked:root.openInstallationManager()}
                    }
                    Column { x: 28; y: 25; width: parent.width*0.52; spacing: 18*root.scaleFactor
                        Text { text: root.currentGame.titleOverride || root.currentGame.title || "Your games. Your Gemini."; color: "white"; font.pixelSize: 40*root.scaleFactor; font.bold: true; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2 }
                        Text { text: root.currentGame.id ? String(root.currentGame.chosenKind || root.currentGame.kind).toUpperCase()+"  ·  "+(root.currentGame.online?"Storage available":"Storage disconnected") : "Add a Games folder to build your native library."; color: "#bfd8e9"; font.pixelSize: 19*root.scaleFactor; width: parent.width; wrapMode: Text.Wrap }
                        NeonPanel { width: 260*root.scaleFactor; height: 54*root.scaleFactor; illuminated: root.zone==="content"; radius: 28
                            Text { anchors.centerIn: parent; text: root.currentGame.id ? "X  Play Game" : "+  Add Folder"; color: "white"; font.pixelSize: 21*root.scaleFactor; font.bold: true }
                            MouseArea { anchors.fill: parent; onClicked: root.currentGame.id?root.playSelected():root.showDialog("folder") }
                        }
                    }
                }
                Text { visible: root.page===0; y: hero.height+15; text: root.recent.length?"Continue Playing  /  Your Library":"Your Library"; color: "white"; font.pixelSize: 22*root.scaleFactor; font.bold: true }
                GridView {
                    id: grid
                    x: 0; y: root.page===0?hero.height+55:0; width: parent.width*0.69; height: parent.height-y
                    clip: true; model: root.gameItems; currentIndex: root.selectedGame
                    cellWidth: width/(root.page===0?4:5); cellHeight: root.page===0?height:cellWidth*1.23
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex,GridView.Contain)
                    delegate: Item { width: grid.cellWidth; height: grid.cellHeight
                        GameCard { width: parent.width-12; height: Math.min(parent.height-12,width*1.22); game: modelData; illuminated: root.zone==="content"&&root.selectedGame===index; showArtwork: backend.preferences.artwork!==false
                            MouseArea { anchors.fill: parent; onClicked: {root.selectedGame=index;root.moveZone("detail")} }
                        }
                    }
                    Text { anchors.centerIn: parent; visible: grid.count===0; text: "No games in this view.\nSettings → General → Add Folder\nX acknowledges messages · R1 opens messages"; color: "#a3bace"; font.pixelSize: 18*root.scaleFactor; horizontalAlignment: Text.AlignHCenter }
                }
                NeonPanel {
                    anchors { right: parent.right; top: grid.top; bottom: parent.bottom } width: parent.width*0.29
                    Flickable{id:detailScroll;anchors.fill:parent;anchors.margins:18;clip:true;contentHeight:detailColumn.implicitHeight
                    ScrollBar.vertical:ScrollBar{}
                    Column {id:detailColumn; width:detailScroll.width; spacing: (root.page===0?8:15)*root.scaleFactor
                        Image { width: parent.width; height: 160*root.scaleFactor; sourceSize: Qt.size(512,768); source: root.currentGame.artworkDisplay || root.currentGame.artwork || ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; visible: root.page!==0 && source.toString().length>0 }
                        Text { width: parent.width; text: root.currentGame.titleOverride || root.currentGame.title || "Game Info"; color: "white"; font.bold: true; font.pixelSize: (root.page===0?20:25)*root.scaleFactor; wrapMode: Text.Wrap; maximumLineCount: 2 }
                        Text { width: parent.width; text: root.currentGame.id ? (root.page===0 ? "Platform   "+String(root.currentGame.chosenKind || root.currentGame.kind)+"\nLast played   "+(root.currentGame.lastPlayed || "Never") : "Platform   "+String(root.currentGame.chosenKind || root.currentGame.kind)+"\nDetection   "+root.currentGame.confidence+"\nStorage   "+(root.currentGame.online?"Available":"Disconnected")+"\nLast played   "+(root.currentGame.lastPlayed || "Never")) : "Discover real games from your folders. Configuration and compatibility are evaluated before launch."; color: "#b4ccdd"; font.pixelSize: 16*root.scaleFactor; wrapMode: Text.Wrap; lineHeight: 1.5 }
                        Repeater {id:detailActions; model: ["▷  Play Game", "⚙  Runtime Setup", root.currentGame.favorite?"★  Remove Favorite":"☆  Add Favorite", "♧  Controller Profile", "▣  Install / Compatibility"]
                            NeonPanel { width: parent.width; height: (root.page===0?34:48)*root.scaleFactor; radius: index===0?26:8; illuminated: root.zone==="detail"&&root.selectedDetail===index
                                Text { anchors.centerIn: parent; text: modelData; color: "white"; font.pixelSize: 17*root.scaleFactor }
                                MouseArea { anchors.fill: parent; onClicked: {root.selectedDetail=index;root.moveZone("detail");root.handleControllerPressed("primary")} }
                            }
                        }
                    }
                    }
                }
            }
            GridView {
                anchors { fill: parent; margins: 20; topMargin: 90; rightMargin: 360*root.scaleFactor }
                visible: root.page===2; model: root.platforms; clip: true; cellWidth: width/4; cellHeight: cellWidth*0.91
                delegate: Item { width: GridView.view.cellWidth; height: GridView.view.cellHeight
                    NeonPanel { anchors.fill: parent; anchors.margins: 7; illuminated: root.zone==="content"&&root.selectedPlatform===index
                        Text { anchors.centerIn: parent; text: "◇\n"+modelData.name.toUpperCase()+"\n"+modelData.count+" games"; color: "#e9f8ff"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 23*root.scaleFactor; lineHeight: 1.4 }
                        MouseArea { anchors.fill: parent; onClicked: {root.selectedPlatform=index;root.moveZone("content");root.handleControllerPressed("primary")} }
                    }
                }
                Text { anchors.centerIn: parent; visible: root.platforms.length===0; text: "Platforms appear when games are discovered."; color: "#a8bdce"; font.pixelSize: 19 }
            }
            Column {
                visible: root.page===2; anchors { right: parent.right; rightMargin: 35; top: parent.top; topMargin: 110 } width: 300*root.scaleFactor; spacing: 25
                Text { width: parent.width; text: root.platforms.length?root.platforms[root.selectedPlatform].name.toUpperCase():"PLATFORMS"; color: "white"; font.pixelSize: 30*root.scaleFactor; font.bold: true; wrapMode: Text.Wrap }
                Text { width: parent.width; text: "Counts come from your library. Console identity and a suitable runtime must be confirmed before launch. Unsupported systems remain visible for review."; color: "#aec7d9"; font.pixelSize: 18*root.scaleFactor; wrapMode: Text.Wrap }
                NeonPanel { width: parent.width; height: 55; illuminated: root.zone==="content"
                    Text { anchors.centerIn: parent; text: "X  View Games"; color: "white"; font.pixelSize: 20 }
                }
            }
            ListView {
                anchors { fill: parent; margins: 22; topMargin: 90 } visible: root.page===6; clip: true; model: backend.installedRuntimes; spacing: 10
                delegate: NeonPanel { width: ListView.view.width; height: 64; illuminated: root.zone==="content"&&root.selectedGame===index
                    Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 24 } text: modelData.id.toUpperCase()+"  ·  "+(modelData.installed?"Installed":"Not installed"); color: "white"; font.pixelSize: 20 }
                    Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 24 } text: modelData.installed?modelData.program:"Requires reviewed setup"; color: "#79acc7"; font.pixelSize: 16 }
                    MouseArea { anchors.fill: parent; onClicked: {root.selectedGame=index;root.moveZone("content");root.handleControllerPressed("primary")} }
                }
            }
            Item {
                anchors.fill: parent; visible: root.page===7
                Row { x: 24; y: 64; spacing: 15*root.scaleFactor
                    Repeater { model: root.settingsTabs
                        NeonPanel { width: 120*root.scaleFactor; height: 42*root.scaleFactor; radius: 8; illuminated: root.settingsTab===index&&(root.zone==="tabs"||root.zone==="settings")
                            Text { anchors.centerIn: parent; text: modelData; color: "white"; font.pixelSize: 16*root.scaleFactor }
                            MouseArea { anchors.fill: parent; onClicked: {root.settingsTab=index;root.settingsRow=0;root.moveZone("tabs")} }
                        }
                    }
                }
                NeonPanel {
                    x: 22; y: 128; width: parent.width*0.34; height: parent.height-y-24
                    Column {
                        anchors.fill:parent;anchors.margins:18;spacing:14
                        Text{width:parent.width;text:"Game Folder Locations";color:"white";font.pixelSize:21*root.scaleFactor;font.bold:true;wrapMode:Text.WordWrap}
                        ListView {
                            id:folderLocations;width:parent.width;height:Math.max(80,parent.height-folderHelp.height-70*root.scaleFactor);clip:true;spacing:10
                            model:backend.roots;currentIndex:root.selectedFolder
                            onCurrentIndexChanged:positionViewAtIndex(currentIndex,ListView.Contain)
                            delegate:NeonPanel{
                                required property int index;required property var modelData
                                width:folderLocations.width;height:folderLabel.implicitHeight+statusLabel.implicitHeight+28;illuminated:root.selectedFolder===index
                                Column{anchors{left:parent.left;right:parent.right;top:parent.top;margins:12}spacing:4
                                    Text{id:folderLabel;width:parent.width;text:modelData.path;color:"#dceaff";font.pixelSize:15*root.scaleFactor;wrapMode:Text.WrapAnywhere}
                                    Text{id:statusLabel;width:parent.width;text:modelData.online?"Storage available":"Storage disconnected";color:modelData.online?"#22ff88":"#ffd45a";font.pixelSize:13*root.scaleFactor;wrapMode:Text.WordWrap}
                                }
                                MouseArea{anchors.fill:parent;onClicked:root.selectedFolder=index}
                            }
                            ScrollBar.vertical:ScrollBar{}
                        }
                        Text{id:folderHelp;width:parent.width;text:"L1 / R1 select a folder.\nRemoving a folder preserves all game files. Disconnected drives keep their library records.";color:"#829eb7";font.pixelSize:16*root.scaleFactor;wrapMode:Text.WordWrap}
                    }
                }
                NeonPanel {
                    x: parent.width*0.37; y: 128; width: parent.width*0.34; height: parent.height-y-24
                    Column { anchors.fill: parent; anchors.margins: 18; spacing: 13*root.scaleFactor
                        Text { width:parent.width;wrapMode:Text.WordWrap;text: root.settingsTabs[root.settingsTab]; color: "white"; font.pixelSize: 23*root.scaleFactor; font.bold: true }
                        ListView { id: settingsActions; width: parent.width; height: parent.height-58; clip: true; model: root.settingRows; spacing: 13*root.scaleFactor; currentIndex: root.settingsRow
                            onCurrentIndexChanged: positionViewAtIndex(currentIndex,ListView.Contain)
                            delegate: NeonPanel { width: settingsActions.width; height: Math.max(54*root.scaleFactor,settingLabel.implicitHeight+24); radius: 8; illuminated: root.zone==="settings"&&root.settingsRow===index
                                Text { id:settingLabel;anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 13 } text: modelData; color: "#e4f1fa"; font.pixelSize: 17*root.scaleFactor; wrapMode:Text.WordWrap }
                                MouseArea { anchors.fill: parent; onClicked: {root.settingsRow=index;root.moveZone("settings");root.settingsAction()} }
                            }
                        }
                    }
                }
                NeonPanel {
                    x: parent.width*0.73; y: 128; width: parent.width*0.25; height: parent.height-y-24
                    Flickable{id:hardwareScroll;anchors.fill:parent;contentHeight:hardwareColumn.implicitHeight+40;clip:true
                    Column {id:hardwareColumn;width:hardwareScroll.width-40;x:20;y:20;spacing:24
                        Text { width:parent.width;wrapMode:Text.WordWrap;text: "Session & Hardware"; color: "white"; font.pixelSize: 21*root.scaleFactor; font.bold: true }
                        Text { width: parent.width; text: "Architecture   "+backend.hardware.architecture+"\nCPU threads   "+backend.hardware.logicalCpus+"\nRAM   "+Math.round(backend.hardware.ramBytes/1073741824)+" GiB\nGame controllers   "+backend.controllerCount; color: "#aad2e7"; font.pixelSize: 16*root.scaleFactor; lineHeight: 1.7 }
                        Text { width: parent.width; text: "Runtimes are never installed silently. Performance, driver APIs, controller profiles and game-specific compatibility must be verified on this PC."; color: "#829ab0"; font.pixelSize: 16*root.scaleFactor; wrapMode: Text.Wrap }
                        Text { width: parent.width; text: "PS / Home\nHold continuously for 3 seconds during gameplay."; color: "#3ed7ff"; font.pixelSize: 18*root.scaleFactor; wrapMode: Text.Wrap }
                    }
                        ScrollBar.vertical:ScrollBar{}
                    }
                }
            }
        }
        NeonPanel {
            anchors { left: mainPanel.left; right: mainPanel.right; bottom: footer.top; bottomMargin: 8 } height: root.pendingMessages.length?44:0; visible: root.pendingMessages.length>0; illuminated: root.zone==="messages"; z: 4
            Text { anchors.fill: parent; anchors.margins: 12; text: root.pendingMessages.length?((root.pendingMessages[root.zone==="messages"?root.messageIndex:root.pendingMessages.length-1].critical?"!  ":"ⓘ  ")+root.pendingMessages[root.zone==="messages"?root.messageIndex:root.pendingMessages.length-1].text+"  ·  R1 (Square in Settings) Messages / X Acknowledge"):""; color: "#d1e8f4"; font.pixelSize: 14; elide: Text.ElideRight }
        }
        Item {
            id: footer; objectName:"GamesFooter"
            anchors {bottom:parent.bottom;left:parent.left;right:parent.right}
            height:root.footerVisible?Math.max(36,36*root.scaleFactor):0
            visible:root.footerVisible&&!backend.gamingMode
            Rectangle{anchors.fill:parent;color:"#f2081320"}
            Rectangle{anchors.top:parent.top;width:parent.width;height:1;color:"#35506a"}
            Row {
                id:footerLeft;objectName:"GamesFooterLeft"
                x:12;anchors.verticalCenter:parent.verticalCenter;spacing:12
                Text{
                    objectName:"GamesFooterBrand"
                    text:"Neutron<font color='#ff4057'>OS</font>";textFormat:Text.RichText
                    color:"#f4fbff";font.pixelSize:16;font.bold:true;anchors.verticalCenter:parent.verticalCenter
                }
                NeonPanel {
                    objectName:"GamesFooterRunningApps"
                    width:140;height:28;radius:8;illuminated:root.zone==="footer"&&root.footerIndex===-1
                    Text{anchors.centerIn:parent;text:"▣  Running Apps";color:"white";font.pixelSize:14}
                    MouseArea{anchors.fill:parent;onClicked:{root.footerReturnZone=root.zone;root.zone="footer";root.footerIndex=0;root.runningPanelOpen=true}}
                }
            }
            Loader {
                objectName:"GamesFooterCarousel"
                anchors.centerIn:parent
                width:Math.max(0,parent.width-2*Math.max(footerLeft.width+12,footerStatus.width+14)-24)
                height:parent.height
                active:root.carouselHost!==null
                sourceComponent:Component{Shared.DesktopAppCarousel{
                    host:root.carouselHost
                    uiScale:Math.min(.84,Math.max(.70,root.width/1920),parent.width/Math.max(44,host.desktopCarouselResolvedApps.length*44))
                    focused:root.zone==="footer"&&root.footerIndex!==-1
                    onAppRequested:function(app){root.activateApp(app)}
                }}
            }
            Row {
                id:footerStatus;objectName:"GamesFooterStatus"
                anchors.right:parent.right;anchors.rightMargin:14;anchors.verticalCenter:parent.verticalCenter;spacing:12
                WifiSignal{
                    objectName:"GamesFooterWifi";anchors.verticalCenter:parent.verticalCenter
                    tint:!root.wifiConnected?"#ff4057":root.wifiConnectivity===4?"#22ff88":"#ffd45a"
                }
                Row{objectName:"GamesFooterBattery";spacing:3;anchors.verticalCenter:parent.verticalCenter
                    Row{spacing:3;anchors.verticalCenter:parent.verticalCenter
                        Repeater{model:5;Rectangle{width:5;height:17;radius:1;color:root.battery>=0&&index<Math.ceil(root.battery/20)?"#22ff88":"#294052"}}
                    }
                    Text{text:root.battery>=0?root.battery+"%":"—%";color:root.battery>=0?"#dceaff":"#829ab0";font.pixelSize:14;anchors.verticalCenter:parent.verticalCenter}
                }
                Text{objectName:"GamesFooterClock";text:Qt.formatTime(root.localNow,"h:mm AP");color:"#dceaff";font.pixelSize:15;anchors.verticalCenter:parent.verticalCenter}
            }
        }
    }

    Timer{interval:1000;repeat:true;running:root.visible;onTriggered:root.localNow=new Date()}
    InstallationManager {id:installationManager;anchors.fill:parent;z:55;visible:root.dialogOpen&&root.dialogKind==="installation";backend:root.backend;onCloseRequested:root.closeDialog();onKeyboardRequested:function(field){root.openKeyboard(field)}
        onRuntimeRequested:function(runtime){root.returnToInstaller=true;root.reviewRuntime(runtime,"Installer requires an explicitly approved compatible runtime. No optional runtime has been installed.")}}
    FolderBrowser{
        id:folderBrowser;objectName:"GamesFolderBrowser";anchors.fill:parent;z:50;visible:root.dialogOpen&&(root.dialogKind==="folder"||root.dialogKind==="folder-edit")
        backend:root.backend
        onCancelRequested:root.closeDialog()
        onSaved:function(path){root.backend.notify("Games folder saved: "+path);root.closeDialog()}
        onKeyboardRequested:function(field){root.openKeyboard(field)}
    }
    Shared.ReferenceExitModal{
        id:exitModal;objectName:"GamesExitModal";appName:"Games";z:70
        onExitRequested:{if(!root.exiting){root.exiting=true;root.persist();root.exitRequested()}}
        onLeaveRunningRequested:{if(root.backend.prepareSwitch()){root.persist();root.backgroundRequested()}}
        onDismissed:root.forceActiveFocus()
    }
    Loader{
        anchors{left:parent.left;right:parent.right;bottom:parent.bottom;bottomMargin:footer.height}z:65
        active:root.carouselHost!==null
        sourceComponent:Component{Shared.DesktopCarouselDialogs{host:root.carouselHost}}
    }
    Rectangle{
        anchors.fill:parent;visible:root.runningPanelOpen;color:"#8801050d";z:60
        MouseArea{anchors.fill:parent}
        NeonPanel{
            anchors{left:parent.left;bottom:parent.bottom;leftMargin:12;bottomMargin:footer.height+8}
            width:Math.min(parent.width-24,620);height:150;illuminated:true
            Text{x:16;y:12;text:"Running Applications";color:"white";font.pixelSize:18;font.bold:true}
            ListView{
                x:12;y:42;width:parent.width-24;height:96;clip:true;orientation:ListView.Horizontal;spacing:10;model:root.running;currentIndex:root.footerIndex
                onCurrentIndexChanged:positionViewAtIndex(currentIndex,ListView.Contain)
                delegate:NeonPanel{required property int index;required property var modelData;width:100;height:88;illuminated:root.footerIndex===index
                    Image{objectName:"GamesRunningAppIcon";anchors.horizontalCenter:parent.horizontalCenter;y:8;width:42;height:42;source:root.runningAppIcon(modelData);fillMode:Image.PreserveAspectFit}
                    Text{x:6;y:54;width:parent.width-12;text:modelData.displayName||modelData.name||modelData.appId;color:"white";font.pixelSize:13;wrapMode:Text.WordWrap;maximumLineCount:2;elide:Text.ElideRight;horizontalAlignment:Text.AlignHCenter}
                    MouseArea{anchors.fill:parent;onClicked:{root.footerIndex=index;root.runningPanelOpen=false;root.activateApp(root.applications.appById(modelData.appId),modelData.runtimeId)}}
                }
                Text{anchors.centerIn:parent;visible:!root.running.length;text:"No running applications";color:"#a8cadd";font.pixelSize:16}
            }
        }
    }
    Rectangle{anchors.fill:parent;visible:root.keyboardOpen;color:"#9b01050d";z:79;MouseArea{anchors.fill:parent}}
    Shared.VirtualKeyboard{
        id:systemKeyboard;objectName:"GamesSystemKeyboard";z:80;anchors{left:parent.left;right:parent.right;bottom:parent.bottom;margins:18}
        height:Math.min(416,root.height*.48);active:root.keyboardOpen;largeMode:false;sizeMultiplier:.7;title:"Games · Enter Path";cancelBehavior:"close"
        onKeyPressed:function(value){if(root.keyboardField)root.keyboardField.text+=value}
        onBackspacePressed:if(root.keyboardField)root.keyboardField.text=root.keyboardField.text.slice(0,-1)
        onClearAllRequested:if(root.keyboardField)root.keyboardField.text=""
        onClosePressed:if(root.keyboardOpen)root.closeKeyboard(true)
        onEnterPressed:{var path=root.keyboardField?root.keyboardField.text:"";root.closeKeyboard(false);if(root.dialogKind==="installation")installationManager.keyboardAccepted(root.keyboardField);if(root.dialogKind==="folder"||root.dialogKind==="folder-edit")folderBrowser.browse(path)}
    }

    ArtworkDialog {id: artworkDialog;anchors.fill: parent;visible: root.dialogOpen&&root.dialogKind==="artwork";z: 21;backend: root.backend;game: root.currentGame;onCloseRequested: root.closeDialog()}
    RuntimeApproval {id: runtimeApproval;anchors.fill: parent;visible: root.dialogOpen&&root.dialogKind==="dependency";z: 21;store: root.storeBackend;backend: root.backend;runtime: root.runtimeChoice;reason: root.runtimeReason;onCloseRequested: {root.closeDialog();if(root.returnToInstaller&&!root.pendingRuntimePackage){root.returnToInstaller=false;root.openInstallationManager()}}
        onBeforeInstall: {root.pendingRuntimePackage=runtimeApproval.proposal.id;root.persist()}}
    ControllerProfile {id: controllerProfile;anchors.fill: parent;visible: root.dialogOpen&&root.dialogKind==="profile";z: 21;backend: root.backend;game: root.currentGame;onCloseRequested: root.closeDialog()}
    Rectangle {
        anchors.fill: parent; visible: root.dialogOpen && root.dialogKind!=="installation" && root.dialogKind!=="artwork" && root.dialogKind!=="profile" && root.dialogKind!=="dependency" && root.dialogKind!=="folder" && root.dialogKind!=="folder-edit"; color: "#dc01050d"; z: 20
        NeonPanel {
            anchors.centerIn: parent; width: Math.min(parent.width*0.76,1050); height: Math.min(parent.height*0.85,740); illuminated: true
            Flickable {
                id:dialogScroll;anchors.fill:parent;anchors.margins:30;clip:true;contentHeight:dialogColumn.implicitHeight
                ScrollBar.vertical:ScrollBar{}
                Column { id:dialogColumn;width:dialogScroll.width;spacing:17
                Text { text: root.dialogKind==="setup"?"Runtime Setup":root.dialogKind==="profile"?"Controller Profile":root.dialogKind==="platform"?"Choose a likely platform":root.dialogKind==="folder-remove"?"Remove Library Folder":"Library Configuration"; color: "white"; font.pixelSize: 29; font.bold: true }
                Text { width: parent.width; text: root.dialogKind==="setup" ? "Candidate: "+root.runtimeChoice+"\n"+(backend.recommendations(root.selectedId).length?backend.recommendations(root.selectedId)[0].reason:"")+"\nSaving explicitly approves this launch configuration; no software is installed." : root.dialogKind==="profile" ? "Button codes are evdev gamepad codes. Analog inversion preserves ranges. SDL mapping is optional; PS/Home cannot be remapped. Use controller identities from diagnostics to persist player assignments." : root.dialogKind==="folder-remove" ? "Remove only the selected folder from discovery. Original games will remain untouched." : "X edits the selected field using the controller keyboard. Circle returns focus."; color: "#a8cadd"; wrapMode: Text.Wrap; font.pixelSize: 17 }
                Repeater { model: root.dialogKind==="platform"?(root.currentGame.candidates || []):[]
                    NeonPanel { width: parent.width; height: 45; illuminated: root.dialogRow===index
                        Text { anchors.centerIn: parent; text: modelData; color: "white"; font.pixelSize: 19 }
                    }
                }
                Text { width:parent.width;wrapMode:Text.WordWrap;visible: root.dialogFields()>0; text: root.dialogKind==="profile"?"Button map JSON (e.g. {\"304\":305,\"305\":304})":root.dialogKind==="setup"?"Windows / Plutonium launcher (.exe), if required":"Folder, title or artwork path"; color: "#57caf8"; font.pixelSize: 15 }
                TextField { id: inputA; width: parent.width; visible: root.dialogFields()>0; color: "white"; font.pixelSize: 18; background: Rectangle { color: "#071627"; radius: 6; border.width: 2; border.color: root.dialogRow===0?"#74d8ff":"#23475d" } }
                Text { width:parent.width;wrapMode:Text.WordWrap;visible: root.dialogFields()>1; text: root.dialogKind==="profile"?"Invert analog axes JSON (e.g. [1,4])":"Installed libretro core path, if required"; color: "#57caf8"; font.pixelSize: 15 }
                TextField { id: inputB; width: parent.width; visible: root.dialogFields()>1; color: "white"; font.pixelSize: 18; background: Rectangle { color: "#071627"; radius: 6; border.width: 2; border.color: root.dialogRow===1?"#74d8ff":"#23475d" } }
                Text { width:parent.width;wrapMode:Text.WordWrap;visible: root.dialogFields()>2; text: root.dialogKind==="profile"?"Optional SDL gamepad mapping":"Arguments as a JSON array of strings"; color: "#57caf8"; font.pixelSize: 15 }
                TextField { id: inputC; width: parent.width; visible: root.dialogFields()>2; color: "white"; font.pixelSize: 18; background: Rectangle { color: "#071627"; radius: 6; border.width: 2; border.color: root.dialogRow===2?"#74d8ff":"#23475d" } }
                Text {width:parent.width;wrapMode:Text.WordWrap; visible: root.dialogKind==="profile"; text: "Player assignments JSON (controller identity → zero-based player slot)"; color: "#57caf8"; font.pixelSize: 15 }
                TextField { id: inputD; width: parent.width; visible: root.dialogKind==="profile"; color: "white"; font.pixelSize: 18; background: Rectangle { color: "#071627"; radius: 6; border.width: 2; border.color: root.dialogRow===3?"#74d8ff":"#23475d" } }
                NeonPanel { id:offlineToggle;width: parent.width; height: Math.max(42,offlineText.implicitHeight+20); visible: root.dialogKind==="setup"&&root.runtimeChoice==="native"; illuminated: root.dialogRow===3
                    Text { id:offlineText;anchors.centerIn: parent;width:parent.width-24;wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter; text: (root.suspendOffline?"[On]":"[Off]")+"  Native offline process suspend (disable for online games)"; color: "#d6edfc"; font.pixelSize: 16 }
                }
                NeonPanel {id:networkToggle; width: parent.width; height: 42; visible: root.dialogKind==="setup"; illuminated: root.dialogRow===(root.runtimeChoice==="native"?4:3)
                    Text { anchors.centerIn: parent; text: (root.networkAllowed?"[On]":"[Off]")+"  Allow game network access"; color: "#d6edfc"; font.pixelSize: 16 }
                }
                NeonPanel {id:dialogSave; width: parent.width; height: 52; visible: root.dialogKind!=="platform"; illuminated: root.dialogRow===root.dialogFields()+(root.dialogKind==="setup"?(root.runtimeChoice==="native"?2:1):0)
                    Text { anchors.centerIn: parent; text: root.dialogKind==="folder-remove"?"X  Remove Folder · Keep Game Files":"X  Approve & Save"; color: "white"; font.pixelSize: 20 }
                    MouseArea { anchors.fill: parent; onClicked: root.saveDialog() }
                }
                }
            }
        }

    }
}
