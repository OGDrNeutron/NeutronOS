import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: manager
    objectName: "GamesInstallationManager"
    required property var backend
    property string step: "menu"
    property string returnStep: "menu"
    property string purpose: "install"
    property string location: ""
    property string parentLocation: ""
    property var entries: []
    property var candidates: []
    property var managedGames: []
    property var game: ({})
    property var initialGame: ({})
    property var preview: ({})
    property var patchItems: []
    property string sourcePath: ""
    property string installerPath: ""
    property var discs: []
    property string patchSource: ""
    property string patchTarget: ""
    property string errorText: ""
    property string operation: "install"
    property string mode: "install"
    property string runtimeId: "wine"
    property string runtimeProgram: ""
    property string runtimeVersion: ""
    property string graphics: "wined3d"
    property bool componentsConfirmed: false
    property bool allowNetwork: false
    property int selection: 0
    property string pickerSection: "entries"
    property bool cancelReview: false
    property string installerArguments: "[]"
    property bool installerInput: false
    property bool loading: false
    property string retryRuntime: ""
    signal closeRequested()
    signal keyboardRequested(var field)
    signal runtimeRequested(string runtime)

    readonly property var menu: ["Install an EXE / MSI / ISO game", "Import an existing game folder", "Import DOS / ScummVM data", "Manage a registered game", "Import the selected library executable", "Import ScummVM game data folder"]
    readonly property var actions: ["Runtime and compatibility settings", "Select launch executable", "Reinstall", "Repair", "Uninstall tracked game files · preserve saves", "Run local Windows component installer", "Apply local patch / replacement", "Restore original patched file", "Remove library entry · retain files and saves"]
    readonly property var formRows: ["Runtime: "+runtimeId+" · "+(runtimeVersion||"select an installed version or request one at launch"), "Runtime executable / version path", "Working directory", "Launch arguments (JSON array)", "Compatibility environment (JSON object)", "Graphics: "+graphics, "DXVK / VKD3D components already supplied: "+(componentsConfirmed?"Yes":"No"), "DOSBox configuration file", "ScummVM game ID", "Existing Steam client path (Proton)", "Network access: "+(allowNetwork?"Allowed":"Blocked"), "Additional discs: "+discs.length, operation==="configure"?"Save configuration · no runtime installed":operation==="import"?"Import game · runtime may be missing":"Review and approve installer", "Installer arguments (JSON array)"]

    function request(data) {
        errorText=""
        if(!backend.managerOperation(data)){errorText=backend.managerState.message||"Games manager is busy or the authenticated session is unavailable.";return false}
        return true
    }
    function open(selected) {
        initialGame=selected||({});game=initialGame.installation||({});managedGames=[];selection=0;step="menu";errorText="";cancelReview=false;sourcePath="";discs=[];loading=true
        if(!backend.managerBusy)request({action:"status"});forceActiveFocus()
    }
    function openPicker(why) {purpose=why;returnStep=step;step="picker";selection=0;pickerSection="entries";browse("")}
    function browse(path) {request({action:"browse",path:path})}
    function chosen(path) {
        if(purpose==="disc"){if(!String(path).toLowerCase().endsWith(".iso")){errorText="Choose an ISO9660 disc image.";return}if(discs.indexOf(path)<0)discs=discs.concat([path]);step="form";selection=11;return}
        if(purpose==="runtime"){runtimeProgram=path;runtimeField.text=path;step="form";selection=1;return}
        if(purpose==="patch-source"){patchSource=path;openPicker("patch-target");return}
        if(purpose==="patch-target"){patchTarget=path;step="patch-review";selection=0;request({action:"patch-preview",id:game.id,source:patchSource,target:patchTarget});return}
        if(purpose==="launch"){launchField.text=path;operation="configure";step="form";selection=12;return}
        if(purpose==="uninstaller"){sourcePath=path;installerPath=path;operation="install";mode="uninstall";step="form";selection=12;return}
        if(purpose==="component"){sourcePath=path;installerPath=path;operation="install";mode="install";step="form";selection=12;return}
        sourcePath=path;step="candidates";selection=0;request({action:"inspect",path:path})
    }
    function selectCandidate(candidate) {
        if(operation==="import"){sourcePath=candidate.path;runtimeId=candidate.kind==="dos"?"dosbox":"wine";beginForm()}
        else if(operation==="configure"){launchField.text=candidate.path;step="form";selection=12}
        else{installerPath=candidate.path;beginForm()}
    }
    function configuration() {
        var args,environment
        try{args=JSON.parse(argumentsField.text||"[]");environment=JSON.parse(environmentField.text||"{}");if(!Array.isArray(args)||typeof environment!=="object"||Array.isArray(environment)||environment===null)throw new Error("Invalid shape")}
        catch(e){errorText="Arguments must be a JSON array of strings; compatibility overrides must be a JSON object.";return null}
        return {runtime:runtimeId,runtimeProgram:runtimeField.text,arguments:args,environment:environment,workingDirectory:workingField.text,graphics:graphics,graphicsComponentsConfirmed:componentsConfirmed,network:allowNetwork,dosboxConfig:dosField.text,scummvmGameId:scummField.text,steamClientPath:steamField.text}
    }
    function beginForm() {
        step="form";selection=0;errorText="";var c=game.configuration||({})
        if(c.runtime)runtimeId=c.runtime
        runtimeProgram=c.runtimeProgram||"";runtimeField.text=runtimeProgram;runtimeVersion=""
        workingField.text=c.workingDirectory||"";argumentsField.text=JSON.stringify(c.arguments||[]);environmentField.text=JSON.stringify(c.environment||{})
        graphics=c.graphics||"wined3d";componentsConfirmed=!!c.graphicsComponentsConfirmed;allowNetwork=!!c.network
        dosField.text=c.dosboxConfig||"";scummField.text=c.scummvmGameId||"";steamField.text=c.steamClientPath||"";launchField.text=game.path||""
    }
    function saveOrReview() {
        var c=configuration();if(!c)return
        if(operation==="configure"){request({action:"configure",id:game.id,configuration:c,executable:launchField.text});return}
        if(operation==="import"){request({action:"import",path:sourcePath,configuration:c});return}
        step="install-review";selection=0
    }
    function approveInstall() {
        var c=configuration();if(!c)return
        var installerArgs;try{installerArgs=JSON.parse(installerArgumentsField.text||"[]");if(!Array.isArray(installerArgs))throw new Error("Array required")}catch(e){errorText="Installer arguments must be a JSON array of strings.";return}
        var data={installerArguments:installerArgs,action:"install",path:sourcePath,installer:installerPath,discs:discs,configuration:c,approved:true,mode:mode}
        if(game.id)data.id=game.id
        step="progress";request(data)
    }
    function formActivate() {
        if(selection===0){step="runtimes";selection=0;return}
        var fields={1:runtimeField,2:workingField,3:argumentsField,4:environmentField,7:dosField,8:scummField,9:steamField}
        if(fields[selection])keyboardRequested(fields[selection])
        else if(selection===5)graphics=graphics==="wined3d"?"dxvk":graphics==="dxvk"?"vkd3d":"wined3d"
        else if(selection===6)componentsConfirmed=!componentsConfirmed
        else if(selection===10)allowNetwork=!allowNetwork
        else if(selection===11)openPicker("disc")
        else if(selection===13)keyboardRequested(installerArgumentsField)
        else saveOrReview()
    }
    function activate() {
        if(step==="menu") {
            game=({});mode="install";discs=[];installerPath="";runtimeId="wine"
            if(selection===0){operation="install";openPicker("install")}
            else if(selection===1){operation="import";openPicker("import-folder")}
            else if(selection===2){operation="import";runtimeId="dosbox";openPicker("legacy")}
            else if(selection===3){step="managed";selection=0}
            else if(selection===5){operation="import";runtimeId="scummvm";openPicker("scummvm")}
            else if(initialGame.path){operation="import";sourcePath=initialGame.path;beginForm()}
            else errorText="Select a game in the library first."
        } else if(step==="picker") {
            if(pickerSection==="manual"){keyboardRequested(manualField);return}
            if(pickerSection==="use"){if(purpose==="scummvm"&&location){sourcePath=location;beginForm()}else if((purpose==="import-folder"||purpose==="legacy")&&location){sourcePath=location;step="candidates";request({action:"inspect",path:location})}else if(manualField.text)chosen(manualField.text);return}
            if(entries.length){var item=entries[selection];if(item.kind==="folder"||item.kind==="drive"||item.kind==="home")browse(item.path);else chosen(item.path)}
        } else if(step==="candidates"&&candidates.length)selectCandidate(candidates[selection])
        else if(step==="managed"&&managedGames.length){game=managedGames[selection];step="actions";selection=0}
        else if(step==="actions") {
            if(selection===0){operation="configure";beginForm()}
            else if(selection===1){operation="configure";beginForm();openPicker("launch")}
            else if(selection===4){step="uninstall-review";selection=0;request({action:"uninstall-plan",id:game.id})}
            else if(selection===2||selection===3){mode=selection===2?"reinstall":selection===3?"repair":"uninstall";operation="install";sourcePath=game.source||"";discs=game.discs||[];installerPath=game.installer||"";if(!sourcePath){errorText="Imported games have no managed installer. Original files are retained.";return}beginForm();selection=12}
            else if(selection===5){operation="install";beginForm();openPicker("component")}
            else if(selection===6)openPicker("patch-source")
            else if(selection===7){step="patches";selection=0;request({action:"patches",id:game.id})}
            else{step="remove-review";selection=0}
        } else if(step==="runtimes") {
            var r=backend.runtimeChoices[selection];if(!r)return
            runtimeId=r.id;runtimeProgram=r.program||"";runtimeField.text=runtimeProgram;runtimeVersion=r.version||"";step="form";selection=0
        } else if(step==="form")formActivate()
        else if(step==="install-review")approveInstall()
        else if(step==="patch-review"&&preview.token)request({action:"patch-apply",id:game.id,source:patchSource,target:patchTarget,token:preview.token,approved:true})
        else if(step==="patches"&&patchItems.length){preview=patchItems[selection];step="restore-review";selection=0}
        else if(step==="restore-review")request({action:"patch-restore",id:game.id,target:preview.target,approved:true})
        else if(step==="uninstall-review"&&preview.token)request({action:"uninstall",id:game.id,token:preview.token,approved:true})
        else if(step==="remove-review")request({action:"remove",id:game.id,approved:true})
        else if(step==="runtime-missing")runtimeRequested(retryRuntime)
        else if(step==="result"){step="menu";selection=0;request({action:"status"})}
    }
    function back() {
        if(step==="picker"&&pickerSection!=="entries"){pickerSection="entries";return}
        if(step==="picker"&&location){browse(parentLocation);return}
        if(step==="menu"){closeRequested();return}
        if(step==="form"||step==="runtimes"||step==="install-review"){step=step==="runtimes"||step==="install-review"?"form":game.id?"actions":"menu";selection=0;return}
        step=step==="picker"?returnStep:step==="actions"?"managed":"menu";selection=0;errorText=""
    }
    function keyboardAccepted(field){if(field===installerText){backend.installerControl("text",installerText.text);installerText.text=""}}
    function handleControllerPressed(action) {
        if(backend.managerBusy&&installerInput){if(action==="cancel")installerInput=false;else if(action==="context"){installerText.text="";keyboardRequested(installerText)}else backend.installerControl(action);return true}
        if(backend.managerBusy&&step==="progress"&&action==="primary"&&!cancelReview){if(runtimeId!=="wine"){errorText="Controller assistance is available for Wine installer windows. Proton installer UI support requires per-title validation.";return true}installerInput=true;return true}
        if(backend.managerBusy){if(action==="cancel")cancelReview=!cancelReview;else if(action==="primary"&&cancelReview){backend.cancelManager();cancelReview=false}return true}
        if(action==="l1"||action==="r1"){details.contentY=Math.max(0,Math.min(Math.max(0,details.contentHeight-details.height),details.contentY+(action==="l1"?-90:90)));return true}
        if(action==="cancel"){back();return true}
        if(action==="primary"){activate();return true}
        if(step==="picker") {
            if(action==="up"){if(pickerSection==="use")pickerSection="manual";else if(pickerSection==="manual")pickerSection="entries";else selection=Math.max(0,selection-4)}
            else if(action==="down"){if(pickerSection==="entries"&&selection+4<entries.length)selection+=4;else if(pickerSection==="entries")pickerSection="manual";else pickerSection="use"}
            else if(action==="left"&&pickerSection==="entries")selection=Math.max(0,selection-1)
            else if(action==="right"&&pickerSection==="entries")selection=Math.min(entries.length-1,selection+1)
        } else if(action==="up"||action==="down") {
            var length=rows.length;selection=Math.max(0,Math.min(Math.max(0,length-1),selection+(action==="up"?-1:1)))
            if(!length)details.contentY=Math.max(0,Math.min(details.contentHeight-details.height,details.contentY+(action==="up"?-70:70)))
        }
        return true
    }
    readonly property var rows: step==="menu"?menu:step==="actions"?actions:step==="managed"?managedGames.map(function(g){return g.title+" · "+g.status}):step==="candidates"?candidates.map(function(c){return c.name+" · "+(c.architecture||c.kind)}):step==="form"?formRows:step==="runtimes"?backend.runtimeChoices.map(function(r){return r.id+" · "+r.version+"\n"+(r.program||r.source)}):step==="patches"?patchItems.map(function(p){return (p.active?"Patched: ":"Backup: ")+p.target}):["install-review","patch-review","restore-review","remove-review","uninstall-review","runtime-missing","result"].indexOf(step)>=0?[step==="runtime-missing"?"Review signed runtime options":step==="result"?"Return to installation manager":"X  Confirm · "+(step==="uninstall-review"?"remove the reviewed tracked game files":step==="remove-review"?"remove entry and retain all files":step==="restore-review"?"restore original file":step==="patch-review"?"apply local patch":"run installer")]:[]
    readonly property string detail: step==="form"?"Configuration changes never install a runtime. X edits fields with the NeutronOS keyboard.\n"+(game.title||sourcePath)+"\n"+(selection===1?runtimeField.text:selection===2?workingField.text:selection===3?argumentsField.text:selection===4?environmentField.text:selection===7?dosField.text:selection===8?scummField.text:selection===9?steamField.text:selection===13?installerArgumentsField.text:""):
        step==="install-review"?"Installer: "+sourcePath+"\nSelected executable: "+installerPath+"\nRuntime: "+runtimeId+" "+runtimeField.text+"\nOperation: "+mode+"\nDiscs: "+discs.join("\n")+"\n\nUntrusted installers execute code. Confirm only software you trust. Installers run in an isolated per-game prefix. Disc images stay read-only. No optional runtime will be installed automatically. The external installer's own UI and compatibility vary by title.":
        step==="patch-review"||step==="restore-review"?"Game: "+(game.title||"")+"\nSource: "+(preview.source||patchSource)+"\nTarget to modify: "+(preview.target||patchTarget)+"\nOriginal SHA-256: "+(preview.originalSHA256||"")+"\nReplacement SHA-256: "+(preview.patchSHA256||"")+"\n\n"+(preview.warning||"Restore verifies both the backup and current patched file before changing it."):
        step==="uninstall-review"?String(preview.message||"Preparing exact removal list…")+"\n\nFiles to remove:\n"+(preview.remove||[]).map(function(p){return p.path}).join("\n")+"\n\nFiles retained:\n"+(preview.retained||[]).map(function(p){return p.path+" · "+p.reason}).join("\n")+"\nPrefix retained: "+(preview.prefixRetained||""):
        step==="remove-review"?"Remove "+game.title+" from this library? All installation files, Wine prefixes, backups and saves will remain. This action does not uninstall optional runtimes.":
        step==="runtime-missing"?"The selected "+retryRuntime+" runtime is unavailable. Review a compatible signed App Store provider and explicitly approve its version, source and footprint. Circle cancels without installing software.":
        step==="progress"?String(backend.managerState.stage||"Preparing")+"\n"+String(backend.managerState.detail||""):
        step==="result"?String(backend.managerState.message||"Operation completed."):
        step==="managed"&&!managedGames.length?"No managed games yet. Import an executable or install a game to register it.":
        step==="candidates"&&!candidates.length?"No supported executables were detected. Circle returns; use the file browser or manual path to select an executable.":
        step==="runtimes"?"Select an installed runtime version, or save a missing-runtime selection. Optional runtime installation always needs a separate signed App Store approval. Compatibility is per game.":
        step==="actions"?game.title+"\n"+game.root:"Controller-first local game installation and compatibility. Original media and imported game files are preserved."

    Connections {
        target: manager.backend
        function onManagerFinished(action,success,result) {
            if(!manager.visible)return
            manager.loading=false;manager.cancelReview=false;manager.installerInput=false
            if(!success){manager.errorText=result.message||"Operation failed. Review Games logs.";if(action==="install")manager.step="result";return}
            if(action==="status"){manager.managedGames=result.games||[];return}
            if(action==="browse"){manager.entries=result.entries||[];manager.location=result.path||"";manager.parentLocation=result.parent||"";manualField.text=manager.location;manager.selection=0;manager.pickerSection="entries";return}
            if(action==="inspect"){manager.candidates=result.candidates||[];manager.selection=0;return}
            if(action==="uninstall-plan"){manager.preview=result.uninstallPlan||({});return}
            if(action==="patch-preview"){manager.preview=result.preview||({});return}
            if(action==="patches"){manager.patchItems=result.patches||[];return}
            if(result.game)manager.game=result.game
            if(result.runtimeMissing){manager.retryRuntime=result.runtime;manager.step="runtime-missing";return}
            if(action==="install"&&result.candidates&&result.candidates.length){manager.operation="configure";manager.candidates=result.candidates;manager.beginForm();manager.step="candidates";manager.selection=0;return}
            manager.step="result";manager.selection=0
        }
    }
    Rectangle {anchors.fill:parent;color:"#ed01050d";MouseArea{anchors.fill:parent}}
    NeonPanel {
        anchors.centerIn:parent;width:Math.min(parent.width-40,1180);height:Math.min(parent.height-40,850);illuminated:true
        ColumnLayout {
            anchors.fill:parent;anchors.margins:26;spacing:12
            Text {Layout.fillWidth:true;text:"Games · Installation & Compatibility";font.pixelSize:26;font.bold:true;color:"white";wrapMode:Text.WordWrap}
            Text {Layout.fillWidth:true;visible:manager.step==="picker";text:manager.location?"Volumes  ›  "+manager.location.split("/").filter(function(p){return p.length}).join("  ›  "):"Home & mounted volumes";color:"#9bd2ed";font.pixelSize:16;wrapMode:Text.WrapAnywhere}
            Flickable {id:details;Layout.fillWidth:true;Layout.preferredHeight:manager.step==="picker"?0:Math.min(190,detailText.implicitHeight+6);visible:manager.step!=="picker";clip:true;contentHeight:detailText.implicitHeight
                Text{id:detailText;width:details.width;text:manager.detail;color:"#b7d0e2";font.pixelSize:17;wrapMode:Text.WrapAnywhere}
                ScrollBar.vertical:ScrollBar{}
            }
            GridView {
                Layout.fillWidth:true;Layout.fillHeight:true;visible:manager.step==="picker";clip:true;cellWidth:width/4;cellHeight:105;model:manager.entries;currentIndex:manager.selection
                onCurrentIndexChanged:positionViewAtIndex(currentIndex,GridView.Contain)
                delegate:Item{required property int index;required property var modelData;width:GridView.view.cellWidth;height:105
                    NeonPanel{anchors.fill:parent;anchors.margins:6;illuminated:manager.pickerSection==="entries"&&manager.selection===index
                        Column{anchors.fill:parent;anchors.margins:10;spacing:5
                            FolderIcon{visible:modelData.kind!=="file";kind:modelData.kind}
                            Text{visible:modelData.kind==="file";text:"▣ "+String(modelData.name).split(".").pop().toUpperCase();color:"#79d6ff";font.pixelSize:20}
                            Text{width:parent.width;text:modelData.name;color:"white";font.pixelSize:15;wrapMode:Text.WrapAnywhere;maximumLineCount:2;elide:Text.ElideRight}
                        }
                        MouseArea{anchors.fill:parent;onClicked:{manager.selection=index;manager.pickerSection="entries";manager.activate()}}
                    }
                }
            }
            ListView {
                id:list;Layout.fillWidth:true;Layout.fillHeight:true;visible:manager.step!=="picker";clip:true;spacing:8;model:manager.rows;currentIndex:manager.selection
                onCurrentIndexChanged:positionViewAtIndex(currentIndex,ListView.Contain)
                delegate:NeonPanel{required property int index;required property string modelData;width:list.width;height:Math.max(44,rowText.implicitHeight+22);illuminated:manager.selection===index
                    Text{id:rowText;anchors{left:parent.left;right:parent.right;verticalCenter:parent.verticalCenter;margins:14} text:modelData;color:"white";font.pixelSize:17;wrapMode:Text.WrapAnywhere}
                    MouseArea{anchors.fill:parent;onClicked:{if(!manager.backend.managerBusy){manager.selection=index;manager.activate()}}}
                }
                ScrollBar.vertical:ScrollBar{}
            }
            TextField {id:manualField;Layout.fillWidth:true;visible:manager.step==="picker";placeholderText:"Manual path · X opens NeutronOS keyboard";color:"white";font.pixelSize:17
                background:Rectangle{color:"#081627";radius:6;border.width:2;border.color:manager.pickerSection==="manual"?"#79d6ff":"#294866"}
                MouseArea{anchors.fill:parent;onClicked:{manager.pickerSection="manual";manager.keyboardRequested(manualField)}}
            }
            NeonPanel{Layout.fillWidth:true;Layout.preferredHeight:44;visible:manager.step==="picker";illuminated:manager.pickerSection==="use"
                Text{anchors.centerIn:parent;text:manager.purpose==="scummvm"?"X  Use this ScummVM data folder":manager.purpose==="import-folder"||manager.purpose==="legacy"?"X  Scan this folder":"X  Use typed file path";color:"white";font.pixelSize:17}
                MouseArea{anchors.fill:parent;onClicked:{manager.pickerSection="use";manager.activate()}}
            }
            Text {Layout.fillWidth:true;visible:manager.errorText.length>0;text:manager.errorText;color:"#ff6577";font.pixelSize:16;wrapMode:Text.WrapAnywhere}
            BusyIndicator{Layout.alignment:Qt.AlignHCenter;running:manager.backend.managerBusy;visible:running;Layout.preferredHeight:32;Layout.preferredWidth:32}
            Text {Layout.fillWidth:true;text:manager.installerInput?"Installer controls: D-PAD arrows · L1/R1 fields · X Enter · Triangle type · Circle return":manager.cancelReview?"X  Cancel the installer · retain files    Circle  Continue waiting":manager.backend.managerBusy&&manager.step==="progress"?"X  Control installer window    Circle  Review cancellation":"D-PAD  Navigate    L1/R1  Scroll details    X  Confirm    Circle  Back / Cancel";color:manager.cancelReview?"#ffd45a":"#829ab0";font.pixelSize:15;wrapMode:Text.WordWrap}
        }
    }
    Item {visible:false
        TextField{id:installerArgumentsField;text:"[]"} TextField{id:installerText} TextField{id:runtimeField} TextField{id:workingField} TextField{id:argumentsField} TextField{id:environmentField}
        TextField{id:dosField} TextField{id:scummField} TextField{id:steamField} TextField{id:launchField}
    }
}
