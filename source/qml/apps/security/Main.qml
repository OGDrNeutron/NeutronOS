import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components" as Shared
import "components"

Item {
    id: root
    anchors.fill: parent
    focus: true

    property string appId: "security"
    property string appName: "Security"
    property var appData: ({})
    property bool hostActive: true
    property var backend: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null
    property var authBackend: (typeof securityManager !== "undefined") ? securityManager : null
    property var controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
    signal exitRequested()
    signal backgroundRequested()

    readonly property color bg: "#02060D"
    readonly property color panel: "#081522"
    readonly property color raised: "#0D2033"
    readonly property color inset: "#04101B"
    readonly property color border: "#23445E"
    readonly property color textMain: "#F4FBFF"
    readonly property color textMuted: "#91AEC5"
    readonly property color cyan: "#63E8FF"
    readonly property color blue: "#4C9EFF"
    readonly property color green: "#42E69C"
    readonly property color yellow: "#FFD166"
    readonly property color orange: "#FF9F43"
    readonly property color red: "#FF4D63"
    readonly property color purple: "#B47AFF"

    readonly property var tabs: ["OVERVIEW", "EVENTS", "HARDENING", "PORTS", "BANS", "PERIPHERALS", "PASSWORDS", "RECOVERY", "MALWARE", "INTEGRITY", "DEVICES", "DEFCON", "AUDIT"]
    readonly property var strictnessLabels: ["LOW", "MEDIUM", "HIGH"]
    readonly property var defconLevels: [5,4,3,2,1]

    property int tabIndex: 0
    property string activeNavLabel: "Threat Protection"
    property int selectedIndex: 0
    property int strictnessIndex: backend && backend.learningMode ? 0 : (backend && backend.responseEngineEnabled ? 2 : 1)
    property bool introActive: true
    property int introStage: 0
    property bool armed: false
    property string armedAction: ""
    property string toast: ""
    property bool toastError: false
    property bool authOpen: false
    property string authPurpose: ""
    property string authStage: "combo"
    property string comboBuffer: ""
    property bool keyboardOpen: false
    property string keyboardBuffer: ""
    property double sensitiveUntil: 0
    property bool credentialEditorOpen: false
    property bool headerFocused: false
    // Controller focus zones: 0 = settings rail, 1 = active setting content, 2 = header menu.
    property int focusZone: 0
    property int lastBodyFocusZone: 0
    property int navSelectedIndex: 2
    property bool exitMenuOpen: false
    property bool searchFocused: false
    property string searchQuery: ""
    property string keyboardPurpose: ""
    property int credentialField: 0
    property string credentialName: ""
    property string credentialUsername: ""
    property string credentialPassword: ""
    property string credentialId: ""
    property var revealedSecret: backend && backend.revealedVaultSecret ? backend.revealedVaultSecret : ({})
    property var flaggedEventIds: ({})
    property var locallyAcknowledgedEventIds: ({})
    property bool sshListenersOpen: false
    property int sshListenerIndex: 0
    property bool listenerDetailOpen: false
    property var listenerDetailItem: ({})
    property bool appPermissionsListOpen: false
    property bool appPermissionModalOpen: false
    property int appPermissionIndex: 0
    property var appPermissionItem: ({})
    property bool vaultChoiceOpen: false
    property int vaultChoiceIndex: 0
    property bool vaultComboEntryOpen: false
    property string vaultComboEntryMode: "verify"
    property string vaultComboBuffer: ""
    property string vaultComboFirst: ""
    property bool vaultComboConfirming: false
    property string vaultComboOperation: ""
    property bool pendingVaultAdd: false
    property double scanUiNowMs: Date.now()

    // Complete Security navigation. Multiple settings may share a backend surface,
    // but every backend-backed security area is directly reachable from the left rail.
    readonly property var navEntries: [
        {section:"OVERVIEW", label:"Security Status", icon:"◉", target:0},
        {section:"", label:"Security Events", icon:"◇", target:1},

        {section:"PROTECTION", label:"Threat Protection", icon:"LOCK", target:0},
        {section:"", label:"Response Engine", icon:"↯", target:0},
        {section:"", label:"Enforcement", icon:"✓", target:0},
        {section:"", label:"Learning Mode", icon:"◎", target:0},
        {section:"", label:"Malware Defense", icon:"✣", target:8},
        {section:"", label:"Ransomware Shield", icon:"▣", target:8},
        {section:"", label:"Quarantine", icon:"◈", target:8},
        {section:"", label:"Integrity Protection", icon:"✓", target:9},

        {section:"NETWORK", label:"Firewall", icon:"▦", target:3},
        {section:"", label:"Listening Ports", icon:"⇄", target:3},
        {section:"", label:"Banned Sources", icon:"⊘", target:4},
        {section:"", label:"SSH Access", icon:">_", target:3},
        {section:"", label:"Network Privacy", icon:"◉", target:4},

        {section:"ACCESS", label:"Authentication", icon:"♙", target:6},
        {section:"", label:"Password Vault", icon:"▣", target:6},
        {section:"", label:"Device Lock", icon:"◇", target:2},
        {section:"", label:"Peripherals", icon:"▣", target:5},
        {section:"", label:"Trusted Devices", icon:"◈", target:10},

        {section:"SYSTEM", label:"System Hardening", icon:"◆", target:2},
        {section:"", label:"App Permissions", icon:"▦", target:2},
        {section:"", label:"Recovery", icon:"↺", target:7},
        {section:"", label:"Audit Log", icon:"▤", target:12},
        {section:"", label:"DEFCON", icon:"△", target:11}
    ]

    function navigateToLabel(label) {
        for(var i=0;i<navEntries.length;++i){
            if(String(navEntries[i].label)===String(label)){
                searchQuery=""
                navSelectedIndex=i
                navList.currentIndex=i
                navList.positionViewAtIndex(i,ListView.Contain)
                tabIndex=Number(navEntries[i].target)
                activeNavLabel=String(navEntries[i].label)
                selectedIndex=0
                setBodyFocus(0)
                return true
            }
        }
        return false
    }
    function rejectedActivity() { return backend&&backend.rejectedActivity?backend.rejectedActivity:[] }
    function auditEntries() { return backend&&backend.auditEntries?backend.auditEntries:[] }
    function installedApps() { return backend&&backend.installedApps?backend.installedApps:[] }
    function vaultComboState() { return backend&&backend.vaultCombo?backend.vaultCombo:({mode:"unset",configured:false}) }
    function formatDuration(seconds) {
        var n=Math.max(0,Math.floor(Number(seconds||0)))
        var d=Math.floor(n/86400),h=Math.floor((n%86400)/3600),m=Math.floor((n%3600)/60)
        if(d>0)return d+"d "+h+"h"
        if(h>0)return h+"h "+m+"m"
        return m+"m"
    }
    function listenerName(item) { return firstValue(item,["friendlyName","processName","service","process"],"Unknown listening service") }
    function listenerPurpose(item) { return firstValue(item,["purpose","expectedReason"],"A local process is accepting network connections.") }
    function beginVaultLoginCombo() {
        authPurpose="vault-login"
        authStage="combo"
        comboBuffer=""
        authOpen=true
    }
    function openAddCredentialEditor() {
        credentialId=""
        credentialName=""
        credentialUsername=""
        credentialPassword=""
        credentialField=0
        credentialEditorOpen=true
    }
    function beginVaultUnlock() {
        if(!backend)return
        var mode=String(vaultComboState().mode||"unset")
        if(mode==="unset"){vaultChoiceIndex=0;vaultChoiceOpen=true;return}
        if(mode==="custom"){vaultComboEntryMode="verify";vaultComboBuffer="";vaultComboFirst="";vaultComboConfirming=false;vaultComboEntryOpen=true;return}
        beginVaultLoginCombo()
    }
    function submitVaultComboEntry() {
        var normalized=String(vaultComboBuffer||"").trim()
        if(!normalized.length){showToast("Enter a controller combo first",true);return}
        if(vaultComboEntryMode==="verify") {
            vaultComboOperation="verify"
            backend.verifyVaultCombo(normalized)
            vaultComboEntryOpen=false
            return
        }
        if(!vaultComboConfirming){
            vaultComboFirst=normalized
            vaultComboBuffer=""
            vaultComboConfirming=true
            showToast("Re-enter the new vault combo, then press START",false)
            return
        }
        if(normalized!==vaultComboFirst){vaultComboBuffer="";vaultComboConfirming=false;vaultComboFirst="";showToast("Vault combo confirmation did not match",true);return}
        vaultComboOperation="set"
        backend.setVaultCombo(normalized)
        vaultComboEntryOpen=false
    }
    function filteredNavEntries() {
        var q=String(searchQuery||"").trim().toLowerCase()
        if(!q.length) return navEntries
        var out=[]
        for(var i=0;i<navEntries.length;++i){
            var e=navEntries[i]
            if(String(e.label).toLowerCase().indexOf(q)>=0 || String(e.section).toLowerCase().indexOf(q)>=0) out.push(e)
        }
        return out
    }
    function openSettingsSearch() {
        searchFocused=true
        keyboardPurpose="search"
        keyboardBuffer=searchQuery
        keyboardOpen=true
        // Settings Search uses the exact same compact keyboard presentation
        // as Add Secure Credential.
        secureKeyboard.openKeyboard("small")
    }
    function commitSettingsSearch() {
        searchQuery=keyboardBuffer
        var matches=filteredNavEntries()
        if(matches.length){tabIndex=Number(matches[0].target); activeNavLabel=String(matches[0].label); selectedIndex=0}
        keyboardBuffer=""
        keyboardPurpose=""
        keyboardOpen=false
        forceActiveFocus()
    }

    function normalize(action) {
        var a=String(action||"").toLowerCase().replace(/-/g,"_")
        if(a==="x"||a==="cross"||a==="primary") return "primary"
        if(a==="o"||a==="circle"||a==="cancel"||a==="back") return "cancel"
        if(a==="square"||a==="secondary") return "secondary"
        if(a==="triangle"||a==="context") return "context"
        if(a==="start"||a==="system"||a==="options") return "system"
        if(a==="r3"||a==="rs"||a==="rightstickclick"||a==="right_stick_button") return "r3"
        if(a.indexOf("up")>=0) return "up"
        if(a.indexOf("down")>=0) return "down"
        if(a.indexOf("left")>=0) return "left"
        if(a.indexOf("right")>=0) return "right"
        return a
    }

    function showToast(message, error) { toast=String(message||""); toastError=error===true; toastTimer.restart() }
    function statusColor(level) { var n=Number(level); return n<=1?red:n===2?orange:n===3?yellow:n===4?"#72D86F":"#42FF70" }
    function securityScoreColor(value) {
        // NEUTRONOS_SECURITY_SCORE_COLOR_THRESHOLDS_V2
        var n = Math.max(0, Math.min(100, Number(value || 0)))
        if (n >= 80) return green
        if (n >= 55) return yellow
        return red
    }
    function scanStats() { return backend && backend.stats ? backend.stats : ({}) }
    function scanPanelActive() {
        var s=scanStats()
        return s.scanRunning===true || s.scanResultVisible===true
    }
    function requestMalwareScan(kind) {
        var s=scanStats()
        if(s.scanRunning===true){
            showToast("A malware scan is already running", true)
            return false
        }
        if(!backend) return false
        if(kind==="neutronos") backend.scanNeutronOS()
        else backend.scanDownloads()
        return true
    }
    function formatScanTime(seconds) {
        var n=Math.max(0,Math.floor(Number(seconds||0)))
        var h=Math.floor(n/3600), m=Math.floor((n%3600)/60), sec=n%60
        if(h>0) return String(h)+":"+(m<10?"0":"")+String(m)+":"+(sec<10?"0":"")+String(sec)
        return String(m)+":"+(sec<10?"0":"")+String(sec)
    }
    function liveScanElapsedSeconds() {
        var st=scanStats()
        if(st.scanRunning===true && String(st.scanStartedAt||"").length){
            var started=Date.parse(String(st.scanStartedAt))
            if(!isNaN(started)) return Math.max(0,(scanUiNowMs-started)/1000.0)
        }
        return Number(st.scanElapsedSeconds||0)
    }
    function defconReadinessName(level) {
        var n=Math.max(1,Math.min(5,Number(level||5)))
        if(n===5)return "Normal Operation"
        if(n===4)return "Elevated Monitoring"
        if(n===3)return "Heightened Defense"
        if(n===2)return "Active Containment"
        return "Emergency Lockdown"
    }
    function activeThreatCount() {
        if(backend && backend.stats && backend.stats.activeThreats !== undefined)
            return Math.max(0, Number(backend.stats.activeThreats||0))
        return suspiciousEvents().length
    }
    function activeThreatText() {
        var n=activeThreatCount()
        return n===0?"No active threats":String(n)+" active threat"+(n===1?"":"s")
    }
    function trustColor(state) { var s=String(state||"").toLowerCase(); return s.indexOf("block")>=0||s.indexOf("malicious")>=0||s.indexOf("suspicious")>=0?red:s.indexOf("trust")>=0||s.indexOf("verified")>=0||s.indexOf("known")>=0?green:yellow }
    function deviceTrustState(device) {
        var d=device||({}); var mount=String(d.mountPoint||d.mount||""); var label=String(d.label||d.mountName||d.name||"").toLowerCase();
        var state=String(d.trustState||d.classification||d.status||"")
        if(mount==="/"||mount.indexOf("/boot")===0||d.bootDevice===true||label==="boot"||label==="rootfs") return "verified boot"
        if(d.registeredMount===true||d.cleanObservations>=3||state.toLowerCase().indexOf("trust")>=0||state.toLowerCase().indexOf("known")>=0) return "trusted"
        return state.length?state:"unknown"
    }
    function sensitiveAuthorized() { return Date.now()<sensitiveUntil }
    function beginAuth(purpose) { authPurpose=purpose; authStage="combo"; comboBuffer=""; authOpen=true }
    function comboToken(a) { if(a==="primary")return "X"; if(a==="secondary")return "SQUARE"; if(a==="context")return "TRIANGLE"; if(a==="system")return "SYSTEM"; if(a==="up")return "U"; if(a==="down")return "D"; if(a==="left")return "L"; if(a==="right")return "R"; return "" }
    function submitCombo() {
        if(authPurpose==="vault-login") {
            var vaultCombo=comboBuffer
            comboBuffer=""
            authOpen=false
            if(backend) backend.unlockVaultWithLoginCombo(vaultCombo)
            return
        }
        var user=authBackend?String(authBackend.activeUsername||""):""
        if(!authBackend||!user.length||!authBackend.verifyLoginCombo(user,comboBuffer)){comboBuffer="";showToast("Controller combo rejected",true);return}
        authStage="password"; keyboardBuffer=""; keyboardOpen=true; secureKeyboard.openKeyboard(true)
    }
    function finishPassword() {
        var user=authBackend?String(authBackend.activeUsername||""):""; var password=keyboardBuffer; keyboardBuffer=""
        if(!authBackend||!user.length||!authBackend.verifyLocalPassword(user,password)){showToast("Account password rejected",true);return}
        sensitiveUntil=Date.now()+300000; authOpen=false; keyboardOpen=false
        showToast("Sensitive access authorized for five minutes",false)
        password=""
    }

    function allEvents() { return backend&&backend.events?backend.events:[] }
    function events() {
        var src=allEvents(), out=[]
        for(var i=0;i<src.length;++i){
            var e=src[i]||({}), id=String(e.id||"")
            if(e.acknowledged===true) continue
            if(id.length && locallyAcknowledgedEventIds[id]===true) continue
            out.push(e)
        }
        return out
    }
    function markEventLocallyAcknowledged(id) {
        id=String(id||"")
        if(!id.length) return
        var next={}
        for(var key in locallyAcknowledgedEventIds) if(locallyAcknowledgedEventIds.hasOwnProperty(key)) next[key]=locallyAcknowledgedEventIds[key]
        next[id]=true
        locallyAcknowledgedEventIds=next
    }
    function ports() { return backend&&backend.listeningPorts?backend.listeningPorts:[] }
    function sshListeners() {
        var p=ports(), out=[]
        for(var i=0;i<p.length;++i){
            var item=p[i]||({})
            var service=String(item.service||item.process||item.processName||item.name||"").toLowerCase()
            if(Number(item.port||0)===22 || service.indexOf("ssh")>=0) out.push(item)
        }
        return out
    }
    function isEventFlagged(item) {
        item=item||({})
        var id=String(item.id||"")
        return item.flagged===true || (id.length>0 && flaggedEventIds[id]===true)
    }
    function toggleSelectedEventFlag() {
        if(tabIndex!==1) return
        var item=currentItem()||({}), id=String(item.id||"")
        if(!id.length){showToast("Selected event has no event ID",true);return}
        var next={}
        for(var key in flaggedEventIds) if(flaggedEventIds.hasOwnProperty(key)) next[key]=flaggedEventIds[key]
        var newFlag = next[id]!==true
        if(newFlag) next[id]=true; else delete next[id]
        flaggedEventIds=next
        if(backend&&backend.setEventFlagged) backend.setEventFlagged(id,newFlag)
        showToast(newFlag?"Event flagged for review":"Event flag removed",false)
    }
    function acknowledgeAllEvents() {
        if(tabIndex!==1 || !backend) return
        var pending=events(), ids=[]
        for(var i=0;i<pending.length;++i){
            var event=pending[i]||({}), id=String(event.id||"")
            if(id.length && event.acknowledged!==true) ids.push(id)
        }
        if(!ids.length){showToast("All security events are already acknowledged",false);return}

        // Optimistically clear the review list once, then perform ONE daemon
        // mutation. The previous implementation sent one IPC request per event,
        // which caused a train of acknowledgement pills and could overflow the
        // request queue on a busy Pi.
        for(var j=0;j<ids.length;++j) markEventLocallyAcknowledged(ids[j])
        selectedIndex=0
        backend.acknowledgeAllEvents()
    }
    function bans() { return backend&&backend.bannedSources?backend.bannedSources:[] }
    function peripherals() {
        var all=backend&&backend.peripherals?backend.peripherals:[]; var out=[]
        for(var i=0;i<all.length;++i){var d=all[i]||({});var kind=String(d.subsystem||d.type||d.deviceType||"").toLowerCase();if(kind.indexOf("block")<0&&kind.indexOf("storage")<0&&kind.indexOf("disk")<0)out.push(d)}
        return out
    }
    function devices() {
        var all=backend&&backend.peripherals?backend.peripherals:[]; var out=[]
        for(var i=0;i<all.length;++i){var d=all[i]||({});if(String(d.trustState||"").toLowerCase()==="trusted")out.push(d)}
        return out
    }
    function malware() {
        var out=[]; var findings=backend&&backend.malwareFindings?backend.malwareFindings:[]
        for(var i=0;i<findings.length;++i){var f=findings[i];f.quarantineApplication=false;out.push(f)}
        var apps=backend&&backend.quarantinedApps?backend.quarantinedApps:[]
        for(var j=0;j<apps.length;++j){var q=apps[j];q.quarantineApplication=true;out.push(q)}
        return out
    }
    function integrity() { return backend&&backend.integrityChanges?backend.integrityChanges:[] }
    function hardening() { return backend&&backend.hardeningProfiles?backend.hardeningProfiles:[] }
    function vault() { return backend&&backend.vaultEntries?backend.vaultEntries:[] }
    function modelForTab() {
        if(tabIndex===1)return events(); if(tabIndex===2)return hardening(); if(tabIndex===3)return ports(); if(tabIndex===4)return rejectedActivity(); if(tabIndex===5)return peripherals(); if(tabIndex===6)return vault(); if(tabIndex===8)return malware(); if(tabIndex===9)return integrity(); if(tabIndex===10)return devices(); if(tabIndex===11)return defconLevels; if(tabIndex===12)return auditEntries(); return []
    }
    function tabTitle() { return activeNavLabel || ["Threat Protection","Security Events","System Hardening","Listening Ports","Banned Sources","Peripherals","Password Vault","Recovery","Malware Defense","Integrity Protection","Trusted Devices","DEFCON","Audit Log"][Math.max(0,Math.min(12,tabIndex))] }
    function tabSubtitle() {
        return [
            "Real-time defense against malware and emerging threats.",
            "Review security events raised by NeutronOS and acknowledge investigated activity.",
            "Preview, select and apply host-hardening profiles with rollback support.",
            "Inspect services currently listening for network connections.",
            "Review blocked network sources and revoke or extend bans.",
            "Control newly attached USB, HID and other peripheral devices.",
            "Store encrypted credentials behind controller-combo and local-password authorization.",
            "Configure recovery codes, USB recovery media and protected snapshots.",
            "Scan downloads and NeutronOS, quarantine findings and manage isolated applications.",
            "Verify protected system files and manage the trusted integrity baseline.",
            "Review storage devices and promote known devices to trusted status.",
            "Set the active defensive readiness level and control the automated response engine.",
            "Validate the tamper-evident security audit chain and inspect its current head."
        ][Math.max(0,Math.min(12,tabIndex))]
    }
    function firstValue(o, keys, fallback) {
        o=o||({}); for(var i=0;i<keys.length;i++){var v=o[keys[i]]; if(v!==undefined&&v!==null&&String(v).length)return String(v)} return fallback||""
    }
    function itemTitle(item) {
        item=item||({})
        if(tabIndex===1)return (isEventFlagged(item)?"⚑  ":"")+firstValue(item,["title","type","eventType","message"],"Security event")
        if(tabIndex===2)return firstValue(item,["title","name","id","profile"],"Hardening action")
        if(tabIndex===3)return listenerName(item)+" — "+listenerPurpose(item)
        if(tabIndex===4)return firstValue(item,["title","subject","address","sourceAddress","source"],"Rejected security activity")
        if(tabIndex===5)return firstValue(item,["name","product","label","deviceId","id"],"Peripheral")
        if(tabIndex===6)return firstValue(item,["name","title","username"],"Stored credential")
        if(tabIndex===8)return firstValue(item,["signature","name","path","itemId","id"],item.quarantineApplication?"Quarantined application":"Malware finding")
        if(tabIndex===9)return firstValue(item,["path","name","file"],"Protected file")
        if(tabIndex===10)return firstValue(item,["label","name","product","device","path","deviceId"],"Storage device")
        if(tabIndex===11)return "DEFCON "+String(item)
        if(tabIndex===12){var d=item.details||({});return String(item.action||"Security audit event").replace(/_/g," ").toUpperCase()}
        return "Security item"
    }
    function itemDetail(item) {
        item=item||({})
        if(tabIndex===1)return firstValue(item,["description","message","detail","reason"],"Event recorded by the security service")
        if(tabIndex===2){var base=firstValue(item,["description","detail","summary"],item.selected?"Selected for application":"Available hardening action");var changes=item.changes||[];return base+(changes.length?"  Changes: "+changes.join(" • "):"")}
        if(tabIndex===3)return String(item.protocol||"TCP").toUpperCase()+"  "+String(item.address||"0.0.0.0")+":"+String(item.port||"?")+"  •  "+String(item.processName||"unknown process")+(item.pid?("  PID "+item.pid):"")
        if(tabIndex===4)return firstValue(item,["reason","description","message"],"Rejected or blocked by NeutronOS security policy")
        if(tabIndex===5)return firstValue(item,["subsystem","type","vendor","deviceType","status"],"Attached peripheral")
        if(tabIndex===6)return firstValue(item,["username","account","description"],"Encrypted vault entry")
        if(tabIndex===8)return firstValue(item,["path","description","reason","status"],item.quarantineApplication?"Application isolated from the normal launcher":"Security finding")
        if(tabIndex===9)return firstValue(item,["change","status","reason","expectedHash"],"Integrity change requires review")
        if(tabIndex===10)return firstValue(item,["mountPoint","mount","path","device","subsystem"],"Storage device")
        if(tabIndex===11){var l=Number(item);return l===5?"Normal operation. Full monitoring stays active with minimal restrictions; suspicious behavior is logged and scored.":l===4?"Elevated monitoring. NeutronOS increases scrutiny, correlates anomalies more aggressively, and prepares enforcement without broad containment.":l===3?"Heightened defense. Enforcement is enabled, suspicious sources can be blocked automatically, and risky changes receive immediate attention.":l===2?"Severe containment. Remote services are restricted, network containment is applied, and active threats are isolated while recovery access is preserved.":"Emergency lockdown. Maximum containment disconnects unnecessary remote access and applies the strongest defensive restrictions; recovery enrollment is required."}
        if(tabIndex===12){var details=item.details||({});var parts=[];for(var k in details){if(details.hasOwnProperty(k)&&["hash","previousHash"].indexOf(k)<0)parts.push(k+": "+String(details[k]))}return String(item.timestamp||"")+(parts.length?"  •  "+parts.join("  •  "):"")}
        return ""
    }
    function itemState(item) {
        item=item||({})
        if(tabIndex===1){if(isEventFlagged(item))return "FLAGGED";if(item.acknowledged===true)return "ACKNOWLEDGED";return firstValue(item,["severityLabel","status","severity"],"NEW")}
        if(tabIndex===2)return item.selected?"SELECTED":firstValue(item,["status","state"],"AVAILABLE")
        if(tabIndex===3)return item.suspicious===true?"REVIEW":(item.expected===true?"EXPECTED":"LISTENING")
        if(tabIndex===4)return firstValue(item,["state","status"],"REJECTED")
        if(tabIndex===5)return firstValue(item,["trustState","classification","status"],"UNTRUSTED").toUpperCase()
        if(tabIndex===6)return backend&&backend.vaultUnlocked?"UNLOCKED":"LOCKED"
        if(tabIndex===8)return item.quarantineApplication?"QUARANTINED":firstValue(item,["status","severityLabel","severity"],"DETECTED")
        if(tabIndex===9)return firstValue(item,["status","changeType","state"],"CHANGED")
        if(tabIndex===10)return deviceTrustState(item).toUpperCase()
        if(tabIndex===11)return Number(item)===Number(backend?backend.threatLevel:5)?"ACTIVE":"AVAILABLE"
        if(tabIndex===12)return String(item.action||"").indexOf("security_event")>=0?"THREAT":"LOG"
        return ""
    }
    function stateTone(state) { var s=String(state||"").toLowerCase(); if(s.indexOf("flagged")>=0)return orange; return (s.indexOf("block")>=0||s.indexOf("detect")>=0||s.indexOf("critical")>=0||s.indexOf("severe")>=0||s.indexOf("change")>=0)?red:(s.indexOf("attention")>=0||s.indexOf("unknown")>=0||s.indexOf("untrust")>=0)?yellow:green }
    function actionHint() {
        if(isDedicatedView()){
            if(activeNavLabel==="Response Engine")return "X TOGGLE RESPONSE ENGINE     △ SETTINGS SEARCH"
            if(activeNavLabel==="Enforcement")return "X TOGGLE ENFORCEMENT     △ SETTINGS SEARCH"
            if(activeNavLabel==="Learning Mode")return "X TOGGLE LEARNING MODE     △ SETTINGS SEARCH"
            if(activeNavLabel==="SSH Access")return "X TOGGLE / VIEW     △ SETTINGS SEARCH"
            return "X REFRESH     △ SETTINGS SEARCH"
        }
        if(tabIndex===1)return "X ACKNOWLEDGE     □ FLAG     R3 ACKNOWLEDGE ALL"
        if(tabIndex===2)return "X SELECT     □ APPLY SELECTED     △ ROLLBACK     START SELECT ALL"
        if(tabIndex===3)return "X DETAILS"
        if(tabIndex===4)return "X RESOLVE / UNBAN     □ PERMANENT BAN"
        if(tabIndex===5)return "X TRUST     □ BLOCK     △ ALLOW ONCE"
        if(tabIndex===6)return "X REVEAL / UNLOCK     □ DELETE     △ ADD"
        if(tabIndex===7)return "X RECOVERY ACTION     △ SNAPSHOT"
        if(tabIndex===8)return "X SCAN / RUN     □ QUARANTINE / DELETE     △ FULL SCAN / RESTORE"
        if(tabIndex===9)return "X VERIFY     □ REPLACE BASELINE     R3 APPROVE ALL + CLEAR"
        if(tabIndex===10)return "X TRUST DEVICE"
        if(tabIndex===11)return "X SET LEVEL     □ NORMALIZE     △ RESPONSE ENGINE"
        if(tabIndex===12)return "X ACKNOWLEDGE THREAT / NORMALIZE     □ REFRESH"
        return "X SELECT"
    }
    function isDedicatedView() {
        return ["Security Status","Response Engine","Enforcement","Learning Mode","Ransomware Shield","Quarantine","Firewall","SSH Access","Network Privacy","Authentication","Device Lock","App Permissions"].indexOf(activeNavLabel) >= 0
    }
    function sshPortCount() {
        var p=ports(), n=0
        for(var i=0;i<p.length;++i) if(Number(p[i].port||0)===22 || String(p[i].service||p[i].process||"").toLowerCase().indexOf("ssh")>=0) ++n
        return n
    }
    function attentionCount() { return backend&&backend.stats ? Number(backend.stats.attentionCount||0) : 0 }
    // NEUTRONOS_FIREWALL_TELEMETRY_FIX_V1
    function firewallProtectionState() {
        if (!backend || !backend.daemonOnline) return "OFFLINE"
        var s = backend.stats || ({})
        var state = String(s.firewallProtectionState || "").toUpperCase()
        if (state.length > 0) return state
        return s.firewallActive ? "SECURE" : "OFFLINE"
    }
    function firewallProtected() {
        if (!backend || !backend.daemonOnline) return false
        var s = backend.stats || ({})
        var state = firewallProtectionState()
        return Boolean(s.firewallActive) && state === "SECURE"
    }
    function firewallProtectionTone() {
        var state = firewallProtectionState()
        if (state === "SECURE") return green
        if (state === "DEGRADED") return yellow
        return red
    }
    function suspiciousEvents() {
        var src=events(), out=[]
        for(var i=0;i<src.length;++i){
            var e=src[i]||({})
            var sev=String(e.severityLabel||e.severity||e.status||"").toLowerCase()
            var text=(String(e.title||e.type||e.eventType||"")+" "+String(e.message||e.description||e.detail||e.reason||"")).toLowerCase()
            var suspicious = sev.indexOf("critical")>=0 || sev.indexOf("high")>=0 || sev.indexOf("severe")>=0 || sev.indexOf("warning")>=0 || sev.indexOf("attention")>=0 || text.indexOf("suspicious")>=0 || text.indexOf("blocked")>=0 || text.indexOf("malware")>=0 || text.indexOf("attack")>=0 || text.indexOf("intrusion")>=0
            if(suspicious && !e.acknowledged) out.push(e)
        }
        return out
    }
    function latestSuspicious() { var s=suspiciousEvents(); return s.length?s[0]:({}) }
    function latestSuspiciousTitle() { var e=latestSuspicious(); return firstValue(e,["title","type","eventType","message"],"Suspicious activity detected") }
    function latestSuspiciousDetail() { var e=latestSuspicious(); return firstValue(e,["description","detail","reason","message"],"Review Security Events for details") }
    function latestSuspiciousTime() { var e=latestSuspicious(); return firstValue(e,["time","timestamp","createdAt","createdAtUtc","occurredAt"],"Latest event") }
    function overallNeedsAttention() {
        if(!backend || !backend.daemonOnline || !backend.auditValid) return true
        if(integrity().length>0) return true
        if(backend.malwareFindings && backend.malwareFindings.length>0) return true
        if(suspiciousEvents().length>0) return true
        return false
    }
    function overallStateLabel() { return overallNeedsAttention()?"ATTENTION":"PROTECTED" }
    function overallStateDetail() {
        if(!backend || !backend.daemonOnline) return "Security service unavailable"
        return defconReadinessName(backend.threatLevel)+"  •  "+activeThreatText()
    }
    function dedicatedSubtitle() {
        if(activeNavLabel==="Security Status") return "Complete live breakdown of the current protection configuration, strength, readiness and notices."
        if(activeNavLabel==="Response Engine") return "Configure NeutronOS automated threat response and see the conditions that govern automatic containment."
        if(activeNavLabel==="Enforcement") return "Control whether security policy is actively enforced or only observed and reported."
        if(activeNavLabel==="Learning Mode") return "Observe normal system behavior without aggressive automatic response while NeutronOS learns the baseline."
        if(activeNavLabel==="Ransomware Shield") return "Review the containment layers that limit destructive file activity and protect system integrity."
        if(activeNavLabel==="Quarantine") return "Inspect isolated findings and applications kept away from normal execution."
        if(activeNavLabel==="Firewall") return "Review network exposure, blocked sources and the protection state surrounding listening services."
        if(activeNavLabel==="SSH Access") return "Inspect SSH exposure and the authentication state that protects remote shell access."
        if(activeNavLabel==="Network Privacy") return "Review externally reachable services, blocked sources and network-facing security posture."
        if(activeNavLabel==="Authentication") return "Review controller-combo, local-password, PAM and lockout protection for the active user."
        if(activeNavLabel==="Device Lock") return "Review session authorization, lockout state and high-priority access safeguards."
        if(activeNavLabel==="App Permissions") return "Review enforcement and hardening controls that constrain applications and attached devices."
        return "Security configuration details."
    }
    function dedicatedRows() {
        if(activeNavLabel==="Security Status") return [
            {t:"Security Strength",d:"Composite score calculated from the active protection state",v:String(backend?backend.securityScore:0)+" / 100",tone:statusColor(backend?backend.threatLevel:5)},
            {t:"Security Service",d:"Core security daemon availability",v:backend&&backend.daemonOnline?"ONLINE":"OFFLINE",tone:backend&&backend.daemonOnline?green:red},
            {t:"Readiness",d:String(backend?backend.suggestedThreatReason||"Current defensive readiness":"Service unavailable"),v:backend?String(backend.threatLabel||("DEFCON "+backend.threatLevel)):"DEFCON 5",tone:statusColor(backend?backend.threatLevel:5)},
            {t:"Response Engine",d:"Automated containment and response",v:backend&&backend.responseEngineEnabled?"ENABLED":"DISABLED",tone:backend&&backend.responseEngineEnabled?green:yellow},
            {t:"Policy Enforcement",d:"Active policy application",v:backend&&backend.enforcementEnabled?"ENABLED":"OBSERVE",tone:backend&&backend.enforcementEnabled?green:yellow},
            {t:"Learning Mode",d:"Behavior-baseline learning",v:backend&&backend.learningMode?"ACTIVE":"OFF",tone:backend&&backend.learningMode?yellow:green},
            {t:"Integrity",d:"Protected-file baseline state",v:String(backend?backend.integrityStatus||"UNKNOWN":"OFFLINE").toUpperCase(),tone:backend&&backend.integrityChanges&&backend.integrityChanges.length?orange:green},
            {t:"Audit Chain",d:"Tamper-evident security audit validation",v:backend&&backend.auditValid?"VALID":"ATTENTION",tone:backend&&backend.auditValid?green:red},
            {t:"Recovery",d:"Emergency recovery enrollment",v:backend&&backend.recoveryConfigured?"CONFIGURED":"NOT ENROLLED",tone:backend&&backend.recoveryConfigured?green:yellow},
            {t:"Notices",d:"Current items requiring review",v:String(attentionCount())+" ACTIVE",tone:attentionCount()>0?orange:green}
        ]
        if(activeNavLabel==="Response Engine") return [
            {t:"Response Engine",d:"Automatically contain confirmed suspicious activity",v:backend&&backend.responseEngineEnabled?"ENABLED":"DISABLED",tone:backend&&backend.responseEngineEnabled?green:yellow},
            {t:"Enforcement Dependency",d:"Automatic response is most effective with enforcement enabled",v:backend&&backend.enforcementEnabled?"READY":"DISABLED",tone:backend&&backend.enforcementEnabled?green:orange},
            {t:"Learning Mode",d:"Learning mode reduces aggressive automated actions",v:backend&&backend.learningMode?"ACTIVE":"OFF",tone:backend&&backend.learningMode?yellow:green},
            {t:"Current Readiness",d:String(backend?backend.suggestedThreatReason||"No escalation notice":"Service unavailable"),v:backend?String(backend.threatLabel||("DEFCON "+backend.threatLevel)):"UNKNOWN",tone:statusColor(backend?backend.threatLevel:5)},
            {t:"Pending Notices",d:"Security events currently requiring attention",v:String(attentionCount()),tone:attentionCount()>0?orange:green}
        ]
        if(activeNavLabel==="Enforcement") return [
            {t:"Policy Enforcement",d:"Apply security policy instead of observation-only behavior",v:backend&&backend.enforcementEnabled?"ENABLED":"OBSERVE ONLY",tone:backend&&backend.enforcementEnabled?green:yellow},
            {t:"Response Engine",d:"Automated containment state",v:backend&&backend.responseEngineEnabled?"ENABLED":"DISABLED",tone:backend&&backend.responseEngineEnabled?green:yellow},
            {t:"Learning Mode",d:"Baseline-learning state",v:backend&&backend.learningMode?"ACTIVE":"OFF",tone:backend&&backend.learningMode?yellow:green},
            {t:"Active Hardening",d:"Current host-hardening profile",v:String(backend?backend.activeHardeningProfile||"DEFAULT":"UNKNOWN"),tone:green},
            {t:"Rollback",d:"Previous hardening state available for recovery",v:backend&&backend.hardeningRollbackAvailable?"AVAILABLE":"NONE",tone:backend&&backend.hardeningRollbackAvailable?yellow:green}
        ]
        if(activeNavLabel==="Learning Mode") return [
            {t:"Learning Mode",d:"Observe activity and learn the normal baseline",v:backend&&backend.learningMode?"ACTIVE":"DISABLED",tone:backend&&backend.learningMode?yellow:green},
            {t:"Response Engine",d:"Automated response state while learning",v:backend&&backend.responseEngineEnabled?"ENABLED":"DISABLED",tone:backend&&backend.responseEngineEnabled?green:yellow},
            {t:"Enforcement",d:"Policy enforcement state while learning",v:backend&&backend.enforcementEnabled?"ENABLED":"OBSERVE",tone:backend&&backend.enforcementEnabled?green:yellow},
            {t:"Recorded Events",d:"Security events available for baseline review",v:String(events().length),tone:events().length?yellow:green},
            {t:"Current Readiness",d:"Threat level remains visible while learning",v:backend?String(backend.threatLabel||("DEFCON "+backend.threatLevel)):"UNKNOWN",tone:statusColor(backend?backend.threatLevel:5)}
        ]
        if(activeNavLabel==="Ransomware Shield") return [
            {t:"Containment Engine",d:"Automated response used to isolate destructive behavior",v:backend&&backend.responseEngineEnabled?"ARMED":"DISABLED",tone:backend&&backend.responseEngineEnabled?green:orange},
            {t:"Policy Enforcement",d:"Prevents policy violations from remaining observation-only",v:backend&&backend.enforcementEnabled?"ACTIVE":"OBSERVE",tone:backend&&backend.enforcementEnabled?green:yellow},
            {t:"Quarantined Findings",d:"Threat items isolated by the security service",v:String((backend&&backend.quarantinedItems?backend.quarantinedItems.length:0)+(backend&&backend.quarantinedApps?backend.quarantinedApps.length:0)),tone:green},
            {t:"Integrity Changes",d:"Protected files that differ from the trusted baseline",v:String(integrity().length),tone:integrity().length?red:green},
            {t:"Audit Chain",d:"Tamper-evident event history",v:backend&&backend.auditValid?"VALID":"ATTENTION",tone:backend&&backend.auditValid?green:red}
        ]
        if(activeNavLabel==="Quarantine") return [
            {t:"Malware Findings",d:"Detected items awaiting or undergoing isolation",v:String(backend&&backend.malwareFindings?backend.malwareFindings.length:0),tone:backend&&backend.malwareFindings&&backend.malwareFindings.length?orange:green},
            {t:"Quarantined Items",d:"Files isolated from normal access",v:String(backend&&backend.quarantinedItems?backend.quarantinedItems.length:0),tone:green},
            {t:"Quarantined Apps",d:"Applications isolated from normal launching",v:String(backend&&backend.quarantinedApps?backend.quarantinedApps.length:0),tone:green},
            {t:"Integrity State",d:"Protected baseline verification",v:String(backend?backend.integrityStatus||"UNKNOWN":"OFFLINE").toUpperCase(),tone:integrity().length?orange:green}
        ]
        if(activeNavLabel==="Firewall") return [
            {t:"Firewall Protection",d:(backend&&backend.stats)?String(backend.stats.firewallReason||"Kernel firewall protection state"):"Kernel firewall protection state",v:firewallProtectionState(),tone:firewallProtectionTone()},
            {t:"Listening Services",d:"Ports currently accepting network connections",v:String(ports().length),tone:ports().length>8?yellow:green},
            {t:"Blocked Sources",d:"Remote sources currently banned",v:String(bans().length),tone:green},
            {t:"Policy Enforcement",d:"Active network security policy application",v:backend&&backend.enforcementEnabled?"ENABLED":"OBSERVE",tone:backend&&backend.enforcementEnabled?green:yellow},
            {t:"Response Engine",d:"Automatic response to suspicious network behavior",v:backend&&backend.responseEngineEnabled?"ENABLED":"DISABLED",tone:backend&&backend.responseEngineEnabled?green:yellow}
        ]
        if(activeNavLabel==="SSH Access") return [
            {t:"SSH Service",d:"Enable or disable the system SSH remote-access service",v:backend&&backend.sshStatus&&backend.sshStatus.active?"ON":"OFF",tone:backend&&backend.sshStatus&&backend.sshStatus.active?green:yellow},
            {t:"SSH Exposure",d:"Detected SSH listeners on port 22 or SSH-labelled services",v:sshPortCount()>0?(String(sshPortCount())+" LISTENER(S)"):"NOT EXPOSED",tone:sshPortCount()>0?yellow:green},
            {t:"Tailscale",d:"Encrypted private-network connectivity for trusted devices",v:backend&&backend.tailscaleStatus&&backend.tailscaleStatus.active?"ON":"OFF",tone:backend&&backend.tailscaleStatus&&backend.tailscaleStatus.active?green:yellow},
            {t:"Tailscale IP",d:"Current private Tailscale address",v:backend&&backend.tailscaleStatus?String(backend.tailscaleStatus.ip||"NOT CONNECTED"):"UNKNOWN",tone:backend&&backend.tailscaleStatus&&backend.tailscaleStatus.ip?green:yellow},
            {t:"Active User",d:"Current authenticated NeutronOS account",v:authBackend?String(authBackend.activeUsername||"UNKNOWN"):"UNKNOWN",tone:green},
            {t:"Login Combo",d:"Controller-combo protection for the active user",v:authBackend&&authBackend.comboConfiguredForActiveUser?"CONFIGURED":"MISSING",tone:authBackend&&authBackend.comboConfiguredForActiveUser?green:orange},
            {t:"PAM Session",d:"Local PAM authentication session",v:authBackend&&authBackend.pamSessionOpen?"OPEN":"CLOSED",tone:green},
            {t:"Lockout State",d:"Failed-login protection",v:authBackend&&authBackend.lockedOut?"LOCKED OUT":"CLEAR",tone:authBackend&&authBackend.lockedOut?red:green}
        ]
        if(activeNavLabel==="Network Privacy") return [
            {t:"Network Exposure",d:"Services currently reachable through listening sockets",v:String(ports().length)+" LISTENING",tone:ports().length>8?yellow:green},
            {t:"Blocked Sources",d:"Remote sources denied by NeutronOS",v:String(bans().length),tone:green},
            {t:"SSH Exposure",d:"SSH listeners detected",v:sshPortCount()>0?"EXPOSED":"CLOSED",tone:sshPortCount()>0?yellow:green},
            {t:"Security Service",d:"Network security telemetry availability",v:backend&&backend.daemonOnline?"ONLINE":"OFFLINE",tone:backend&&backend.daemonOnline?green:red},
            {t:"Active Notices",d:"Security notices requiring review",v:String(attentionCount()),tone:attentionCount()>0?orange:green}
        ]
        if(activeNavLabel==="Authentication") return [
            {t:"Active User",d:"Account currently protected by NeutronOS authentication",v:authBackend?String(authBackend.activeUsername||"UNKNOWN"):"UNKNOWN",tone:green},
            {t:"Controller Combo",d:"Controller-first login factor",v:authBackend&&authBackend.comboConfiguredForActiveUser?"CONFIGURED":"SETUP REQUIRED",tone:authBackend&&authBackend.comboConfiguredForActiveUser?green:orange},
            {t:"Combo Length",d:"Configured controller sequence length",v:authBackend?String(authBackend.comboLength||0):"0",tone:green},
            {t:"Local Password",d:"Local password verification state for this session",v:authBackend&&authBackend.localPasswordVerified?"VERIFIED":"NOT VERIFIED",tone:authBackend&&authBackend.localPasswordVerified?green:yellow},
            {t:"Failed Attempts",d:String(authBackend?authBackend.lastFailureReason||"No recent authentication failure":"Unavailable"),v:authBackend?String(authBackend.failedAttempts||0):"0",tone:authBackend&&authBackend.failedAttempts>0?orange:green},
            {t:"Lockout",d:"Progressive lockout protection",v:authBackend&&authBackend.lockedOut?(String(authBackend.lockoutRemainingSeconds||0)+" SEC"):"CLEAR",tone:authBackend&&authBackend.lockedOut?red:green},
            {t:"PAM",d:"Local PAM session state",v:authBackend&&authBackend.pamSessionOpen?"SESSION OPEN":"CLOSED",tone:green}
        ]
        if(activeNavLabel==="Device Lock") return [
            {t:"Lockout Protection",d:"Progressive failed-attempt lockout",v:authBackend&&authBackend.lockedOut?"ACTIVE":"READY",tone:authBackend&&authBackend.lockedOut?red:green},
            {t:"High-Priority Authorization",d:"Temporary authorization for privileged actions",v:authBackend&&authBackend.highPriorityAuthorized?"AUTHORIZED":"LOCKED",tone:authBackend&&authBackend.highPriorityAuthorized?yellow:green},
            {t:"Authorization Remaining",d:"Seconds remaining on high-priority authorization",v:authBackend?String(authBackend.highPriorityAuthorizationRemaining||0)+" SEC":"0 SEC",tone:green},
            {t:"Security Directory",d:"Permissions and ownership safety check",v:authBackend&&authBackend.securityDirectorySafe?"SAFE":"ATTENTION",tone:authBackend&&authBackend.securityDirectorySafe?green:red},
            {t:"PAM Session",d:"Authenticated local session",v:authBackend&&authBackend.pamSessionOpen?"OPEN":"CLOSED",tone:green}
        ]
        if(activeNavLabel==="App Permissions") return [
            {t:"Apps",d:"Browse installed NeutronOS applications and declared permissions",v:String(installedApps().length)+" INSTALLED",tone:green},
            {t:"Policy Enforcement",d:"Whether application security policy is actively applied",v:backend&&backend.enforcementEnabled?"ENFORCED":"OBSERVE",tone:backend&&backend.enforcementEnabled?green:yellow},
            {t:"Hardening Profile",d:"Current host policy baseline",v:String(backend?backend.activeHardeningProfile||"DEFAULT":"UNKNOWN"),tone:green},
            {t:"Peripheral Controls",d:"Attached devices visible to the security service",v:String(peripherals().length)+" DEVICE(S)",tone:green},
            {t:"Quarantined Apps",d:"Applications prevented from normal launching",v:String(backend&&backend.quarantinedApps?backend.quarantinedApps.length:0),tone:green},
            {t:"Security Events",d:"Permission or policy events available for review",v:String(events().length),tone:events().length?yellow:green}
        ]
        return []
    }
    function maxIndex(){if(isDedicatedView())return Math.max(0,dedicatedRows().length-1);if(tabIndex===0)return 8;if(tabIndex===7)return 2;var m=modelForTab();return Math.max(0,m.length-1)}
    function moveContent(delta){
        selectedIndex=Math.max(0,Math.min(maxIndex(),selectedIndex+delta))
        if(isDedicatedView() && dedicatedList){dedicatedList.currentIndex=selectedIndex;dedicatedList.positionViewAtIndex(selectedIndex,ListView.Contain)}
        else if(contentList){contentList.currentIndex=selectedIndex;contentList.positionViewAtIndex(selectedIndex,ListView.Contain)}
    }
    function moveNav(delta){
        var m=filteredNavEntries()
        if(!m.length)return
        var nextIndex=Math.max(0,Math.min(m.length-1,navSelectedIndex+delta))
        if(nextIndex===navSelectedIndex)return
        navSelectedIndex=nextIndex
        navList.currentIndex=navSelectedIndex
        navList.positionViewAtIndex(navSelectedIndex,ListView.Contain)
        // The left rail is a live navigator: moving onto a setting immediately
        // refreshes the center surface. X is reserved for actions inside a surface.
        activateNavSelection()
    }
    function activateNavSelection(){
        var m=filteredNavEntries()
        if(!m.length)return
        var e=m[Math.max(0,Math.min(navSelectedIndex,m.length-1))]
        tabIndex=Number(e.target)
        activeNavLabel=String(e.label)
        selectedIndex=0
        armed=false
        armedAction=""
        searchFocused=false
    }
    function preferredNavLabel(index){return ["Threat Protection","Security Events","System Hardening","Firewall","Banned Sources","Peripherals","Password Vault","Recovery","Malware Defense","Integrity","Trusted Devices","DEFCON","Audit Log"][Math.max(0,Math.min(12,index))]}
    function setBodyFocus(zone){
        focusZone=Math.max(0,Math.min(1,zone))
        lastBodyFocusZone=focusZone
        headerFocused=false
    }
    function focusHeader(){lastBodyFocusZone=focusZone===2?lastBodyFocusZone:focusZone;focusZone=2;headerFocused=true}
    function leaveHeader(){focusZone=lastBodyFocusZone;headerFocused=false}
    function arm(name){if(armed&&armedAction===name)return true;armed=true;armedAction=name;showToast(name+" armed — press the same button again",false);return false}
    function currentItem(){var m=modelForTab();return m.length?m[Math.max(0,Math.min(selectedIndex,m.length-1))]:({})}
    function applyStrictness(){
        if(!backend)return
        if(strictnessIndex===0){backend.setResponseEngineEnabled(false);backend.setEnforcementEnabled(false);backend.setLearningMode(true)}
        else if(strictnessIndex===1){backend.setLearningMode(false);backend.setEnforcementEnabled(true);backend.setResponseEngineEnabled(false)}
        else {backend.setLearningMode(false);backend.setEnforcementEnabled(true);backend.setResponseEngineEnabled(true)}
        showToast("Security strictness set to "+strictnessLabels[strictnessIndex],false)
    }

    function primaryAction(){
        var item=currentItem()||({})
        if(isDedicatedView()){
            if(!backend && activeNavLabel!=="Authentication" && activeNavLabel!=="Device Lock") return
            if(activeNavLabel==="Security Status" && selectedIndex===8) { navigateToLabel("Recovery"); return }
            if(activeNavLabel==="Response Engine" && selectedIndex===0) backend.setResponseEngineEnabled(!backend.responseEngineEnabled)
            else if(activeNavLabel==="Response Engine" && selectedIndex===1) backend.setEnforcementEnabled(!backend.enforcementEnabled)
            else if(activeNavLabel==="Response Engine" && selectedIndex===2) backend.setLearningMode(!backend.learningMode)
            else if(activeNavLabel==="Enforcement" && selectedIndex===0) backend.setEnforcementEnabled(!backend.enforcementEnabled)
            else if(activeNavLabel==="Learning Mode" && selectedIndex===0) backend.setLearningMode(!backend.learningMode)
            else if(activeNavLabel==="Quarantine" && selectedIndex===0) root.requestMalwareScan("downloads")
            else if(activeNavLabel==="SSH Access" && selectedIndex===0) backend.setSshEnabled(!Boolean(backend.sshStatus&&backend.sshStatus.active))
            else if(activeNavLabel==="SSH Access" && selectedIndex===1){
                var listeners=sshListeners(); if(listeners.length){sshListenerIndex=0;sshListenersOpen=true}else showToast("No SSH listeners are currently exposed",false)
            }
            else if(activeNavLabel==="SSH Access" && selectedIndex===2) backend.setTailscaleEnabled(!Boolean(backend.tailscaleStatus&&backend.tailscaleStatus.active))
            else if(activeNavLabel==="App Permissions" && selectedIndex===0){appPermissionIndex=0;appPermissionsListOpen=true}
            else backend&&backend.refresh()
            return
        }
        if(tabIndex===0){
            if(!backend)return
            if(selectedIndex===0) backend.refresh()
            else if(selectedIndex===1) backend.setResponseEngineEnabled(!backend.responseEngineEnabled)
            else if(selectedIndex===2) backend.setEnforcementEnabled(!backend.enforcementEnabled)
            else if(selectedIndex===3) root.requestMalwareScan("downloads")
            else if(selectedIndex===4) navigateToLabel("Peripherals")
            else if(selectedIndex===5) backend.refresh()
            else if(selectedIndex===6) backend.setResponseEngineEnabled(!backend.responseEngineEnabled)
            else if(selectedIndex===7) backend.verifyIntegrity()
            else if(selectedIndex===8) root.requestMalwareScan("neutronos")
        }
        else if(tabIndex===1){if(backend&&item.id){var eid=String(item.id);markEventLocallyAcknowledged(eid);selectedIndex=Math.max(0,Math.min(selectedIndex,events().length-1));backend.acknowledgeEvent(eid)}}
        else if(tabIndex===2){if(backend)backend.toggleHardeningAction(String(item.id||item.name||""))}
        else if(tabIndex===3){if(item&&Object.keys(item).length){listenerDetailItem=item;listenerDetailOpen=true}else if(backend)backend.refresh()}
        else if(tabIndex===4){
            var ip=String(item.address||item.sourceAddress||"")
            var eventId=String(item.eventId||"")
            if(ip.length&&arm("UNBAN "+ip)&&backend){backend.unblockSource(ip);armed=false}
            else if(eventId.length&&backend){backend.acknowledgeEvent(eventId);if(backend.setEventFlagged)backend.setEventFlagged(eventId,false)}
            else showToast("This rejected item is retained as security history",false)
        }
        else if(tabIndex===5){var did=String(item.id||item.deviceId||item.stableId||"");if(did.length&&backend)backend.trustPeripheral(did)}
        else if(tabIndex===6){if(!backend||!backend.vaultUnlocked)beginVaultUnlock();else if(item.id)backend.revealVaultEntry(String(item.id))}
        else if(tabIndex===7){if(!sensitiveAuthorized())beginAuth("recovery");else if(backend){if(selectedIndex===2)backend.requestSnapshot();else if(selectedIndex===0&&!backend.recoveryConfigured)backend.generateRecoveryCode();else if(selectedIndex===1&&backend.recoveryUsbCandidates.length)backend.enrollUsbRecovery(String(backend.recoveryUsbCandidates[0].path||backend.recoveryUsbCandidates[0].device||""));else backend.verifyUsbRecovery()}}
        else if(tabIndex===8){if(item.quarantineApplication&&backend){var entry=String(item.entrypoint||"");if(entry.length)backend.runQuarantinedApp(String(item.id),entry,false);else showToast("No executable entry point was declared",true)}else if(backend)root.requestMalwareScan("downloads")}
        else if(tabIndex===9){if(backend)backend.verifyIntegrity()}
        else if(tabIndex===10){var sid=String(item.id||item.deviceId||item.stableId||"");if(sid.length&&backend)backend.trustPeripheral(sid)}
        else if(tabIndex===11){var level=Number(item);if(level===1&&!backend.recoveryConfigured){showToast("DEFCON 1 requires an enrolled recovery key",true);return}if(arm("DEFCON "+level)&&backend){backend.setManualThreatLevel(level);armed=false}}
        else if(tabIndex===12){if(backend){var d=item.details||({});var eventId=String(d.eventId||d.id||"");backend.neutralizeEvent(eventId)}}
    }

    function secondaryAction(){
        var item=currentItem()||({})
        if(tabIndex===1)toggleSelectedEventFlag()
        else if(tabIndex===2&&backend){if(arm("APPLY SELECTED HARDENING")&&backend){backend.applyHardening("selected");armed=false}}
        else if(tabIndex===4){var ip=String(item.address||"");if(ip.length&&arm("PERMANENT BAN "+ip)&&backend){backend.blockSource(ip,5256000);armed=false}}
        else if(tabIndex===5){var id=String(item.id||item.deviceId||item.stableId||"");if(id.length&&arm("BLOCK DEVICE")&&backend){backend.blockPeripheral(id);armed=false}}
        else if(tabIndex===6&&backend&&backend.vaultUnlocked&&item.id){if(arm("DELETE PASSWORD")&&backend){backend.deleteVaultEntry(String(item.id));armed=false}}
        else if(tabIndex===8&&backend&&item.id){if(item.quarantineApplication){if(arm("DELETE QUARANTINED APP")){backend.deleteQuarantinedApp(String(item.id));armed=false}}else if(arm("QUARANTINE")){backend.quarantineFinding(String(item.id));armed=false}}
        else if(tabIndex===9&&backend){if(arm("REPLACE INTEGRITY BASELINE")&&backend){backend.createIntegrityBaseline();armed=false}}
        else if(tabIndex===11&&backend){if(arm("RETURN TO DEFCON 5")&&backend){backend.deescalateToNormal();armed=false}}
        else if(tabIndex===12&&backend)backend.refresh()
    }

    function contextAction(){
        var item=currentItem()||({})
        if(tabIndex===2&&backend&&backend.hardeningRollbackAvailable){if(arm("ROLLBACK HARDENING")&&backend){backend.rollbackHardening();armed=false}}
        else if(tabIndex===5&&backend){var id=String(item.id||item.deviceId||item.stableId||"");if(id.length)backend.allowPeripheralOnce(id)}
        else if(tabIndex===6&&backend){
            if(backend.vaultUnlocked){
                pendingVaultAdd=false
                openAddCredentialEditor()
            } else {
                pendingVaultAdd=true
                beginVaultUnlock()
            }
        }
        else if(tabIndex===7&&backend){backend.requestSnapshot()}
        else if(tabIndex===8&&backend){if(item.quarantineApplication&&item.id){if(arm("RESTORE FOR RE-ANALYSIS")){backend.restoreQuarantinedApp(String(item.id));armed=false}}else root.requestMalwareScan("neutronos")}
        else if(tabIndex===11&&backend)backend.setResponseEngineEnabled(!backend.responseEngineEnabled)
    }

    function handleControllerPressed(action){
        var a=normalize(action)
        if(listenerDetailOpen){if(a==="primary"||a==="cancel"||a==="left"){listenerDetailOpen=false;listenerDetailItem=({})}return true}
        if(appPermissionModalOpen){if(a==="primary"||a==="cancel"||a==="left"){appPermissionModalOpen=false}return true}
        if(appPermissionsListOpen){
            var apps=installedApps()
            if(a==="cancel"||a==="left"){appPermissionsListOpen=false;return true}
            if(a==="up")appPermissionIndex=Math.max(0,appPermissionIndex-1)
            else if(a==="down")appPermissionIndex=Math.min(Math.max(0,apps.length-1),appPermissionIndex+1)
            else if(a==="primary"&&apps.length){appPermissionItem=apps[appPermissionIndex]||({});appPermissionModalOpen=true}
            return true
        }
        if(vaultChoiceOpen){
            if(a==="cancel"){vaultChoiceOpen=false;return true}
            if(a==="up"||a==="left")vaultChoiceIndex=0
            else if(a==="down"||a==="right")vaultChoiceIndex=1
            else if(a==="primary"){
                vaultChoiceOpen=false
                if(vaultChoiceIndex===0){vaultComboEntryMode="set";vaultComboBuffer="";vaultComboFirst="";vaultComboConfirming=false;vaultComboEntryOpen=true}
                else {vaultComboOperation="login";backend.setVaultComboMode("login")}
            }
            return true
        }
        if(vaultComboEntryOpen){
            if(a==="cancel"){vaultComboEntryOpen=false;vaultComboBuffer="";vaultComboFirst="";vaultComboConfirming=false;return true}
            if(a==="system"){submitVaultComboEntry();return true}
            var vt=comboToken(a);if(vt.length)vaultComboBuffer+=(vaultComboBuffer.length?" ":"")+vt
            return true
        }
        if(sshListenersOpen){
            var listeners=sshListeners()
            if(a==="up") sshListenerIndex=Math.max(0,sshListenerIndex-1)
            else if(a==="down") sshListenerIndex=Math.min(Math.max(0,listeners.length-1),sshListenerIndex+1)
            else if(a==="primary"||a==="cancel"||a==="left") sshListenersOpen=false
            return true
        }
        if(exitMenuOpen){referenceExitModal.handleController(a);return true}
        if(introActive){if(a==="cancel")introActive=false;return true}
        if(keyboardOpen)return secureKeyboard.handleControllerPressed(a)
        if(revealedSecret&&String(revealedSecret.id||"").length){if(a==="cancel"||a==="primary"){if(backend)backend.clearRevealedVaultSecret()}return true}
        if(authOpen){if(a==="cancel"){authOpen=false;comboBuffer=""}else if(authStage==="combo"){if(a==="system")submitCombo();else{var t=comboToken(a);if(t.length){comboBuffer+=(comboBuffer.length?" ":"")+t}}}return true}
        if(credentialEditorOpen){if(a==="cancel")credentialEditorOpen=false;else if(a==="up")credentialField=Math.max(0,credentialField-1);else if(a==="down")credentialField=Math.min(3,credentialField+1);else if(a==="primary"){if(credentialField===3){if(backend&&backend.saveVaultEntry(credentialId,credentialName,credentialUsername,credentialPassword)){credentialEditorOpen=false;showToast("Credential saved",false)}}else{keyboardBuffer=credentialField===0?credentialName:credentialField===1?credentialUsername:credentialPassword;keyboardOpen=true;secureKeyboard.openKeyboard("small")}}return true}
        if(a==="context"){
            // Password Vault owns Triangle for adding a credential. DEFCON owns
            // Triangle for Response Engine. Everywhere else it remains Search.
            if(tabIndex===6 || tabIndex===11) contextAction();
            else openSettingsSearch();
            return true
        }
        if(a==="r3"){
            if(tabIndex===1 && focusZone===1) {
                acknowledgeAllEvents()
            } else if(tabIndex===9 && focusZone===1 && backend) {
                var changeCount = integrity().length
                if(changeCount<=0) {
                    showToast("Integrity baseline is already clean", false)
                } else {
                    var action = "APPROVE "+String(changeCount)+" INTEGRITY CHANGES"
                    if(arm(action)) {
                        // Replacing the trusted baseline is the authoritative backend
                        // operation that approves the current filesystem state. Once
                        // securityd writes the new baseline, the next snapshot clears
                        // integrityChanges instead of merely hiding them in QML.
                        backend.createIntegrityBaseline()
                        armed=false
                        armedAction=""
                        showToast("Approving current state and rebuilding integrity baseline", false)
                    }
                }
            }
            return true
        }
        if(focusZone===2 || headerFocused){
            headerFocused=true
            if(a==="primary"){exitMenuOpen=true;referenceExitModal.openModal(root)}
            else if(a==="left"){setBodyFocus(1)}
            else if(a==="down"||a==="cancel"||a==="system"){leaveHeader()}
            // Left from the three-dot anchor always returns to the middle panel.
            return true
        }
        if(a==="cancel"){if(armed){armed=false;armedAction=""}else{exitMenuOpen=true;referenceExitModal.openModal(root)}return true}
        // START remains a direct shortcut to the colored three-dot menu.
        if(a==="system"){focusHeader();return true}

        // Horizontal navigation is deterministic: settings rail -> content -> menu dots.
        // Moving left reverses that path. No control inside a panel steals D-pad left/right.
        if(a==="right"){
            if(focusZone===0)setBodyFocus(1)
            else if(focusZone===1)focusHeader()
            return true
        }
        if(a==="left"){
            if(focusZone===1)setBodyFocus(0)
            return true
        }

        if(focusZone===0){
            // Settings rail: one D-pad press always means exactly one setting.
            if(a==="up"){
                if(navSelectedIndex<=0)focusHeader(); else moveNav(-1)
                return true
            }
            if(a==="down"){moveNav(1);return true}
            if(a==="primary"){return true}
            // Secondary actions belong to the active content, never the navigation rail.
            return true
        }

        // Active setting content: up/down stay in the current setting. At the first option, Up anchors the menu dots.
        if(a==="up"){
            if(selectedIndex<=0)focusHeader(); else moveContent(-1)
            return true
        }
        if(a==="down"){moveContent(1);return true}
        if(a==="primary"){primaryAction();return true}
        if(a==="secondary"){secondaryAction();return true}
        return true
    }
    function handleControllerReleased(action){return true}

    Component.onCompleted:{focusZone=0;lastBodyFocusZone=0;navSelectedIndex=2;forceActiveFocus();if(backend)backend.refresh();introSequence.start()}
    Connections {
        target:backend
        ignoreUnknownSignals:true
        function onOperationFinished(success,message){
            showToast(message,!success)
            if(!success && pendingVaultAdd && String(message||"").toLowerCase().indexOf("vault")>=0)
                pendingVaultAdd=false
            if(vaultComboOperation.length){
                var op=vaultComboOperation;vaultComboOperation=""
                if(success && op==="login") beginVaultLoginCombo()
            }
        }
        function onStateChanged(){
            if(pendingVaultAdd && backend && backend.vaultUnlocked){
                pendingVaultAdd=false
                openAddCredentialEditor()
            }
        }
        function onSecurityEventRaised(event){showToast(String(event.title||"Security event"),Number(event.severity||1)>=4)}
    }
    Timer{id:toastTimer;interval:3300;repeat:false;onTriggered:toast=""}
    Timer{id:scanUiClock;interval:250;repeat:true;running:root.scanPanelActive();onTriggered:root.scanUiNowMs=Date.now()}

    // qBittorrent-style application shell: thin shared header/footer, dense three-column body.
    Rectangle { anchors.fill: parent; color: bg }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#030812" }
            GradientStop { position: 0.55; color: "#02070D" }
            GradientStop { position: 1.0; color: "#03110C" }
        }
    }

    Header {
        id: referenceHeader
        x: 18
        width: parent.width - 36
        anchors.top: parent.top
        // Fixed app-chrome height. Do not scale this with display width; on 1440p/4K
        // that made the header swell back toward the old oversized design.
        height: 54
        z: 50
        secure: !root.overallNeedsAttention() && Number(backend?backend.threatLevel||5:5) > 2
        securityScore: backend && backend.securityScore!==undefined ? Math.max(0,Math.min(100,Math.round(Number(backend.securityScore)))) : -1
        menuFocused: root.headerFocused && !root.exitMenuOpen
        onMenuRequested: { root.exitMenuOpen = true; referenceExitModal.openModal(root) }
    }

    Footer {
        id: referenceFooter
        x: 18
        width: parent.width - 36
        anchors.bottom: parent.bottom
        height: 72
        z: 50
        hintText: ""
        controllerBackend: root.controllerBackend
    }

    // LEFT: Security settings navigation. Intentionally mirrors the approved reference density.
    Rectangle {
        id: referenceNav
        anchors.left: parent.left
        anchors.top: referenceHeader.bottom
        anchors.bottom: referenceFooter.top
        anchors.leftMargin: 12
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        width: Math.max(235, Math.min(290, parent.width * 0.14))
        radius: 8
        color: "#07101AEE"
        border.width: 1
        border.color: "#25313C"

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Text { text: "SECURITY SETTINGS"; color: "#B5B8BC"; font.pixelSize: 20; font.bold: true; font.letterSpacing: 1.0 }

            Rectangle {
                id: searchField
                width: parent.width; height: 44; radius: 6; color: "#050B12"; border.width: searchFocused ? 2 : 1; border.color: searchFocused ? green : "#27323D"
                Text { anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 13; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "⌕  " + ((keyboardOpen && keyboardPurpose==="search") ? keyboardBuffer : (searchQuery.length ? searchQuery : "Search settings...")); color: searchQuery.length || (keyboardOpen&&keyboardPurpose==="search") ? textMain : "#7D8792"; font.pixelSize: 20; elide: Text.ElideRight }
                MouseArea { anchors.fill: parent; onClicked: openSettingsSearch() }
            }

            ListView {
                id: navList
                width: parent.width
                height: parent.height - 72
                clip: true
                spacing: 2
                currentIndex: navSelectedIndex
                model: filteredNavEntries()
                delegate: Item {
                    required property int index
                    required property var modelData
                    width: ListView.view.width
                    height: modelData.section.length ? 70 : 50
                    Text {
                        visible: modelData.section.length > 0
                        anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: 5
                        text: modelData.section; color: "#7E858D"; font.pixelSize: 16; font.bold: true; font.letterSpacing: .7
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: 44; radius: 6
                        color: (focusZone===0 && navSelectedIndex===index) ? "#103A2B" : (activeNavLabel === String(modelData.label) ? "#0A2A20" : "transparent")
                        border.width: (focusZone===0 && navSelectedIndex===index) || activeNavLabel === String(modelData.label) ? 1 : 0
                        border.color: (focusZone===0 && navSelectedIndex===index) ? cyan : green
                        LockMark { visible: String(modelData.icon)==="LOCK"; anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 27; accent: green }
                        Text { visible: String(modelData.icon)!=="LOCK"; anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; color: activeNavLabel===String(modelData.label)?green:"#7F8EAA"; font.pixelSize: 23; font.bold: true }
                        Text { anchors.left: parent.left; anchors.leftMargin: 42; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: activeNavLabel===String(modelData.label)?textMain:"#D5D9DD"; font.pixelSize: 20; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: { navSelectedIndex=index; setBodyFocus(0); activateNavSelection() } }
                    }
                }
            }
        }
    }

    // RIGHT: persistent overall state, recent checks and suspicious activity.
    Rectangle {
        id: referenceStatusRail
        anchors.right: parent.right
        anchors.top: referenceHeader.bottom
        anchors.bottom: referenceFooter.top
        anchors.rightMargin: 12
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        width: Math.max(360, parent.width * 0.285)
        radius: 8
        color: "#06100DEE"
        border.width: 1
        border.color: "#26382F"

        Column {
            anchors.fill: parent; anchors.margins: 18; spacing: 13
            Text { text: "SECURITY STATE"; color: "#AEB4B2"; font.pixelSize: 23; font.bold: true; font.letterSpacing: 1.0 }

            Item {
                width: parent.width; height: Math.min(260, referenceStatusRail.height * .31)
                Rectangle { anchors.centerIn: parent; width: 190; height: 190; radius: 95; color: "transparent"; border.width: 1; border.color: "#164A29" }
                Rectangle { anchors.centerIn: parent; width: 150; height: 150; radius: 75; color: "transparent"; border.width: 1; border.color: "#196332" }
                DefconFace {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 0
                    width: 142
                    height: 142
                    level: backend ? Number(backend.threatLevel || 5) : 5
                    accent: statusColor(level)
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 18; text: root.overallStateLabel(); color: textMain; font.pixelSize: 20; font.bold: true }
            }

            Text { anchors.horizontalCenter: parent.horizontalCenter; text: backend?String(backend.threatLabel||("DEFCON "+backend.threatLevel)):"DEFCON 5"; color: statusColor(backend?backend.threatLevel:5); font.pixelSize: 41; font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.overallStateDetail(); color: "#A7AAA9"; font.pixelSize: 18 }

            Item {
                width: parent.width; height: 92
                Column {
                    anchors.centerIn: parent; spacing: 0
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SECURITY SCORE"; color: "#D2D8D5"; font.pixelSize: 20; font.bold: true; font.letterSpacing: 1.0 }
                    Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 7
                        Text { text: String(backend?backend.securityScore:0); color: securityScoreColor(backend?backend.securityScore:0); font.pixelSize: 48; font.bold: true }
                        Text { anchors.baseline: parent.children[0].baseline; text: "/ 100"; color: "#AEB4B2"; font.pixelSize: 19; font.bold: true }
                    }
                }
                Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: backend&&backend.auditValid?"LIVE":"CHECK"; color: backend&&backend.auditValid?green:yellow; font.pixelSize: 15; font.bold: true }
            }
            Item {
                width: parent.width; height: 13
                // NEUTRONOS_SECURITY_APP_SCORE_TRACER_V1
                Rectangle {
                    id: appScoreGlowOuter
                    anchors.left: parent.left
                    anchors.leftMargin: -6
                    anchors.verticalCenter: parent.verticalCenter
                    width: appScoreFill.width + 12
                    height: 21
                    radius: 11
                    color: securityScoreColor(backend?backend.securityScore:0)
                    property real pulseOpacity: 0.10
                    opacity: appScoreFill.width > 0 ? pulseOpacity : 0
                    SequentialAnimation on pulseOpacity {
                        running: root.visible && appScoreFill.width > 0
                        loops: Animation.Infinite
                        NumberAnimation { from:0.08; to:0.28; duration:820; easing.type:Easing.InOutSine }
                        NumberAnimation { from:0.28; to:0.08; duration:820; easing.type:Easing.InOutSine }
                    }
                }
                Rectangle {
                    id: appScoreGlowInner
                    anchors.left: parent.left
                    anchors.leftMargin: -2
                    anchors.verticalCenter: parent.verticalCenter
                    width: appScoreFill.width + 4
                    height: 15
                    radius: 8
                    color: securityScoreColor(backend?backend.securityScore:0)
                    opacity: appScoreFill.width > 0 ? 0.22 : 0
                }
                Rectangle {
                    id: appScoreTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 9; radius: 5; color: "#15241C"
                }
                Rectangle {
                    id: appScoreFill
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width*Math.max(0,Math.min(100,backend?backend.securityScore:0))/100
                    height: 9; radius: 5; color: securityScoreColor(backend?backend.securityScore:0)
                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
                Rectangle {
                    id: appScoreTracer
                    property real phase: 0.0
                    readonly property real barW: Math.max(0,appScoreFill.width)
                    readonly property real barH: Math.max(1,appScoreFill.height)
                    readonly property real perimeter: Math.max(1,2*(barW+barH))
                    readonly property real distance: phase*perimeter
                    width: 7; height: 7; radius: 4
                    color: { var n=Number(backend?backend.securityScore:0); return n>=80?"#C8FFE3":n>=55?"#FFF7A6":"#FFC0CA" }
                    border.width: 1; border.color: "white"
                    opacity: barW>24 ? 0.98 : 0
                    x: { var d=distance,w=barW,h=barH;if(d<w)return appScoreFill.x+d-width/2;if(d<w+h)return appScoreFill.x+w-width/2;if(d<2*w+h)return appScoreFill.x+w-(d-w-h)-width/2;return appScoreFill.x-width/2 }
                    y: { var d=distance,w=barW,h=barH,top=appScoreFill.y;if(d<w)return top-height/2;if(d<w+h)return top+(d-w)-height/2;if(d<2*w+h)return top+h-height/2;return top+h-(d-2*w-h)-height/2 }
                    NumberAnimation on phase { from:0;to:1;duration:1900;loops:Animation.Infinite;running:root.visible&&appScoreTracer.opacity>0 }
                }
            }
            Rectangle { width: parent.width; height: 1; color: "#24312B" }

            Text { text: "RECENT CHECKS"; color: "#AEB4B2"; font.pixelSize: 19; font.bold: true; font.letterSpacing: .8 }
            Repeater {
                model: [
                    {n:"Malware Scan", s:(backend&&backend.malwareFindings&&backend.malwareFindings.length)?"Attention":"Passed"},
                    {n:"Firewall Policy", s:firewallProtectionState()==="SECURE"?"Verified":firewallProtectionState()==="DEGRADED"?"Attention":"Offline"},
                    {n:"System Integrity", s:backend&&backend.integrityChanges&&backend.integrityChanges.length?"Attention":"Passed"}
                ]
                Rectangle {
                    width: parent.width; height: 38; radius: 5; color: "#050B09"; border.width: 1; border.color: "#202C26"
                    Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "✓"; color: modelData.s==="Attention"?yellow:green; font.pixelSize: 18 }
                    Text { anchors.left: parent.left; anchors.leftMargin: 38; anchors.verticalCenter: parent.verticalCenter; text: modelData.n; color: "#D5D8D6"; font.pixelSize: 18 }
                    Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.s; color: modelData.s==="Attention"?yellow:modelData.s==="Offline"?red:green; font.pixelSize: 18 }
                }
            }

            Text { text: "SUSPICIOUS ACTIVITY"; color: "#AEB4B2"; font.pixelSize: 19; font.bold: true; font.letterSpacing: .8 }
            Rectangle {
                width: parent.width; height: suspiciousEvents().length?76:58; radius: 5; color: "#050B09"; border.width: 1; border.color: suspiciousEvents().length?"#5A3A19":"#1D4A2D"
                Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: suspiciousEvents().length?"!":"☺"; color: suspiciousEvents().length?orange:green; font.pixelSize: 22; font.bold: true }
                Column {
                    anchors.left: parent.left; anchors.leftMargin: 44; anchors.right: parent.right; anchors.rightMargin: 86; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    Text { width: parent.width; text: suspiciousEvents().length?latestSuspiciousTitle():"No suspicious activity detected"; color: suspiciousEvents().length?textMain:green; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight }
                    Text { visible: suspiciousEvents().length>0; width: parent.width; text: latestSuspiciousDetail(); color: textMuted; font.pixelSize: 15; elide: Text.ElideRight }
                    Text { visible: suspiciousEvents().length>0; width: parent.width; text: latestSuspiciousTime(); color: "#77827D"; font.pixelSize: 14; elide: Text.ElideRight }
                }
                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: suspiciousEvents().length?String(suspiciousEvents().length)+" ACTIVE":"CLEAR"; color: suspiciousEvents().length?orange:green; font.pixelSize: 15; font.bold: true }
            }

            Text { text: "SECURITY OVERVIEW"; color: "#AEB4B2"; font.pixelSize: 19; font.bold: true; font.letterSpacing: .8 }
            Grid {
                width: parent.width; columns: 2; columnSpacing: 8; rowSpacing: 8
                Repeater {
                    model: [
                        {n:"Response Engine",v:backend&&backend.responseEngineEnabled?"ON":"OFF",tone:backend&&backend.responseEngineEnabled?green:yellow},
                        {n:"Enforcement",v:backend&&backend.enforcementEnabled?"ON":"OFF",tone:backend&&backend.enforcementEnabled?green:yellow},
                        {n:"Learning Mode",v:backend&&backend.learningMode?"ON":"OFF",tone:backend&&backend.learningMode?yellow:green},
                        {n:"Integrity",v:integrity().length?String(integrity().length)+" NOTICE":"VERIFIED",tone:integrity().length?orange:green},
                        {n:"Blocked Sources",v:String(bans().length),tone:bans().length?green:textMuted},
                        {n:"Quarantine",v:String((backend&&backend.quarantinedItems?backend.quarantinedItems.length:0)+(backend&&backend.quarantinedApps?backend.quarantinedApps.length:0)),tone:green}
                    ]
                    Rectangle {
                        width: (referenceStatusRail.width-44)/2; height: 48; radius: 5; color: "#050B09"; border.width: 1; border.color: "#202C26"
                        Column { anchors.fill: parent; anchors.margins: 7; spacing: 1
                            Text { width: parent.width; text: modelData.n; color: "#858E89"; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: modelData.v; color: modelData.tone; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                        }
                    }
                }
            }
            Rectangle {
                visible: root.scanPanelActive()
                width: parent.width
                height: visible ? 184 : 0
                radius: 6
                color: "#07120EEE"
                border.width: 1
                border.color: scanStats().scanRunning===true ? cyan : (Number(scanStats().scanThreatsFound||0)>0 ? orange : green)

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 7
                    Row {
                        width: parent.width
                        Text { text: scanStats().scanRunning===true ? "MALWARE SCAN IN PROGRESS" : "MALWARE SCAN RESULT"; color: scanStats().scanRunning===true?cyan:green; font.pixelSize: 18; font.bold: true }
                        Item { width: Math.max(0,parent.width-parent.children[0].implicitWidth-parent.children[2].implicitWidth-12); height: 1 }
                        Text { text: scanStats().scanRunning===true ? "RUNNING" : "COMPLETE"; color: scanStats().scanRunning===true?cyan:green; font.pixelSize: 15; font.bold: true }
                    }
                    Text { width: parent.width; text: "Target: "+String(scanStats().scanTarget||"NeutronOS"); color: textMain; font.pixelSize: 16; elide: Text.ElideMiddle }
                    Row {
                        spacing: 22
                        Text { text: "Elapsed  "+root.formatScanTime(root.liveScanElapsedSeconds()); color: textMuted; font.pixelSize: 16 }
                        Text { text: "Threats  "+String(scanStats().scanThreatsFound||0); color: Number(scanStats().scanThreatsFound||0)>0?orange:green; font.pixelSize: 16; font.bold: true }
                    }
                    Text { width: parent.width; text: String(scanStats().scanStatus||scanStats().scanLastResult||""); color: scanStats().scanRunning===true?textMuted:(Number(scanStats().scanThreatsFound||0)>0?orange:green); font.pixelSize: 15; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                    Text { visible: scanStats().scanRunning===true; width: parent.width; text: "Current file: "+String(scanStats().scanCurrentFile||"Starting scan…"); color: "#7FA6BC"; font.pixelSize: 14; elide: Text.ElideMiddle }
                    Text { visible: scanStats().scanRunning!==true; width: parent.width; text: "Result remains visible for 5 minutes."; color: "#6F7D76"; font.pixelSize: 13 }
                }
            }
            Text { visible: !root.scanPanelActive(); text: backend&&backend.daemonOnline?"Live protection telemetry from neutron-securityd.":"Protection service is not reporting online."; color: "#7F8984"; font.pixelSize: 15 }
        }
    }

    // CENTER: every navigation destination has a real frontend surface bound to SecurityCoreManager.
    Rectangle {
        id: centerPanel
        anchors.left: referenceNav.right
        anchors.right: referenceStatusRail.left
        anchors.top: referenceHeader.bottom
        anchors.bottom: referenceFooter.top
        anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.topMargin: 16; anchors.bottomMargin: 16
        radius: 8; color: "#06101AEE"; border.width: 1; border.color: "#25313C"; clip: true

        Column {
            id: overviewPanel
            anchors.fill: parent; anchors.margins: 18; spacing: 8; visible: tabIndex === 0 && activeNavLabel === "Threat Protection"
            Row {
                width: parent.width; height: 64; spacing: 15
                LockMark { width: 46; height: 52; anchors.verticalCenter: parent.verticalCenter; accent: green }
                Column { anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    Text { text: "Threat Protection"; color: textMain; font.pixelSize: 29; font.bold: true }
                    Text { text: "Real-time defense against malware and emerging threats."; color: "#A8AFB5"; font.pixelSize: 16 }
                }
            }
            Rectangle { width: parent.width; height: 1; color: "#1B2832" }
            Repeater {
                model: [
                    {i:"◎",t:"Real-time Protection",d:"Security daemon actively monitors the system",v:backend&&backend.daemonOnline?"ON":"OFF",on:backend&&backend.daemonOnline},
                    {i:"☼",t:"Behavior Monitoring",d:"Automated response engine reacts to suspicious behavior",v:backend&&backend.responseEngineEnabled?"ON":"OFF",on:backend&&backend.responseEngineEnabled},
                    {i:"◎",t:"Enforcement",d:"Applies active security policy instead of observation-only mode",v:backend&&backend.enforcementEnabled?"ON":"OFF",on:backend&&backend.enforcementEnabled},
                    {i:"⇩",t:"Download Scanning",d:"Scan the downloads area for known threats",v:"RUN",on:true},
                    {i:"▣",t:"Peripheral Monitoring",d:"Review attached USB, storage and input devices",v:String(peripherals().length)+" devices",on:true},
                    {i:"☁",t:"Threat Intelligence",d:"Live daemon correlation and event reporting",v:backend&&backend.daemonOnline?"Live":"Offline",on:backend&&backend.daemonOnline},
                    {i:"▤",t:"Automatic Response",d:"Contain confirmed threats using the response engine",v:backend&&backend.responseEngineEnabled?"ON":"OFF",on:backend&&backend.responseEngineEnabled},
                    {i:"♢",t:"Integrity Protection",d:"Verify protected NeutronOS files against the baseline",v:backend&&backend.integrityChanges&&backend.integrityChanges.length?"Attention":String(backend?backend.integrityStatus||"Ready":"Offline"),on:!(backend&&backend.integrityChanges&&backend.integrityChanges.length)},
                    {i:"▦",t:"Full NeutronOS Scan",d:"Inspect protected application and system paths",v:"RUN",on:true}
                ]
                Rectangle {
                    width: parent.width; height: Math.max(52,(centerPanel.height-250)/9)
                    color: (focusZone===1 && selectedIndex === index) ? "#0A2A20" : "transparent"; border.width: (focusZone===1 && selectedIndex === index) ? 1 : 0; border.color: green; radius: 5
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: "#17242E" }
                    Text { anchors.left: parent.left; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: modelData.i; color: green; font.pixelSize: 29; font.bold: true }
                    Column { anchors.left: parent.left; anchors.leftMargin: 49; anchors.right: parent.right; anchors.rightMargin: 135; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { width: parent.width; text: modelData.t; color: textMain; font.pixelSize: 21; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: modelData.d; color: "#9AA4AD"; font.pixelSize: 17; elide: Text.ElideRight }
                    }
                    Rectangle { visible: modelData.v === "ON" || modelData.v === "OFF"; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; width: 50; height: 27; radius: 14; color: modelData.on?green:"#273039"
                        Rectangle { width: 21; height: 21; radius: 11; anchors.verticalCenter: parent.verticalCenter; x:modelData.on?26:3; color:"white" }
                    }
                    Text { visible: modelData.v !== "ON" && modelData.v !== "OFF"; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text:modelData.v; color:modelData.on?green:yellow; font.pixelSize:16; font.bold: true }
                }
            }
            Rectangle {
                width: parent.width; height: 38; radius: 5; color: "#07151A"; border.width: 1; border.color: "#1E3C2A"
                Text { anchors.centerIn: parent; text: actionHint(); color: green; font.pixelSize: 17; font.bold: true; font.letterSpacing: .2 }
            }
        }

        Item {
            id: dedicatedPanel
            anchors.fill: parent
            anchors.margins: 18
            visible: isDedicatedView()

            Column {
                anchors.fill: parent
                spacing: 10
                Item {
                    width: parent.width
                    height: 82
                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.rightMargin: 210
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text { width: parent.width; text: activeNavLabel; color: textMain; font.pixelSize: 29; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: dedicatedSubtitle(); color: "#AAB3BA"; font.pixelSize: 18; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                    Rectangle {
                        width: 176; height: 38; radius: 19
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#071A12"; border.width: 1
                        border.color: backend&&backend.daemonOnline?green:red
                        Text { anchors.centerIn: parent; text: backend&&backend.daemonOnline?"SERVICE ONLINE":"SERVICE OFFLINE"; color: backend&&backend.daemonOnline?green:red; font.pixelSize: 16; font.bold: true }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: "#1B2832" }
                ListView {
                    id: dedicatedList
                    width: parent.width
                    height: parent.height - 180
                    model: dedicatedRows()
                    currentIndex: selectedIndex
                    spacing: 8
                    clip: true
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: dedicatedList.width
                        height: 76
                        radius: 7
                        color: (focusZone===1 && index===selectedIndex)?"#0A2A20":"#07111A"
                        border.width: 1
                        border.color: (focusZone===1 && index===selectedIndex)?green:"#24323C"
                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 16
                            anchors.right: valuePill.left; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text { width: parent.width; text: modelData.t; color: textMain; font.pixelSize: 21; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: modelData.d; color: textMuted; font.pixelSize: 16; elide: Text.ElideRight }
                        }
                        Rectangle {
                            id: valuePill
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(112, dedicatedValue.implicitWidth+24)
                            height: 32; radius: 16
                            color: "#071A12"; border.width: 1; border.color: modelData.tone
                            Text { id: dedicatedValue; anchors.centerIn: parent; text: modelData.v; color: modelData.tone; font.pixelSize: 16; font.bold: true }
                        }
                    }
                }
                Rectangle {
                    width: parent.width; height: 38; radius: 5; color:"#07151A"; border.width:1; border.color:"#1E3C2A"
                    Text { anchors.centerIn:parent; text:actionHint(); color:green; font.pixelSize:17; font.bold:true; font.letterSpacing:.2 }
                }
            }
        }

        Item {
            id: sectionPanel
            anchors.fill: parent; anchors.margins: 18; visible: tabIndex !== 0 && !isDedicatedView()

            Column {
                anchors.fill: parent; spacing: 10
                Item {
                    width: parent.width; height: 82
                    Column { anchors.left: parent.left; anchors.right: parent.right; anchors.rightMargin: 210; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { width: parent.width; text: tabTitle(); color: textMain; font.pixelSize: 29; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: tabSubtitle(); color: "#AAB3BA"; font.pixelSize: 18; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                    Rectangle { width: 176; height: 38; radius: 19; anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; color: "#071A12"; border.width: 1; border.color: backend&&backend.daemonOnline?green:red
                        Text { anchors.centerIn: parent; text: backend&&backend.daemonOnline?"SERVICE ONLINE":"SERVICE OFFLINE"; color: backend&&backend.daemonOnline?green:red; font.pixelSize: 16; font.bold: true }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: "#1B2832" }

                // Recovery is stateful even before any recovery media exists, so it gets a dedicated control surface.
                Column {
                    width: parent.width; spacing: 10; visible: tabIndex === 7
                    Rectangle { width: parent.width; height: 92; radius: 7; color: (focusZone===1 && selectedIndex===0)?"#0A2A20":"#07111A"; border.width: 1; border.color:(focusZone===1 && selectedIndex===0)?green:"#24323C"
                        Column { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                            Text { text: backend&&backend.recoveryConfigured?"Recovery enrollment":"Create Recovery Code"; color:textMain; font.pixelSize:22; font.bold:true }
                            Text { text: backend&&backend.recoveryConfigured?("Method: "+String(backend.recoveryMethod||"configured")):"Generate a one-time recovery code and confirm enrollment."; color:textMuted; font.pixelSize:16 }
                        }
                        Text { anchors.right:parent.right; anchors.rightMargin:16; anchors.verticalCenter:parent.verticalCenter; text:backend&&backend.recoveryConfigured?"CONFIGURED":"X GENERATE"; color:green; font.pixelSize:16; font.bold:true }
                    }
                    Rectangle { width: parent.width; height: 92; radius: 7; color: (focusZone===1 && selectedIndex===1)?"#0A2A20":"#07111A"; border.width: 1; border.color:(focusZone===1 && selectedIndex===1)?green:"#24323C"
                        Column { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                            Text { text:"USB Recovery Key"; color:textMain; font.pixelSize:22; font.bold:true }
                            Text { text:(backend&&backend.recoveryUsbCandidates?backend.recoveryUsbCandidates.length:0)+" eligible device(s) detected"; color:textMuted; font.pixelSize:16 }
                        }
                        Text { anchors.right:parent.right; anchors.rightMargin:16; anchors.verticalCenter:parent.verticalCenter; text:"X ENROLL / VERIFY"; color:green; font.pixelSize:16; font.bold:true }
                    }
                    Rectangle { width: parent.width; height: 92; radius: 7; color: (focusZone===1 && selectedIndex===2)?"#0A2A20":"#07111A"; border.width: 1; border.color:(focusZone===1 && selectedIndex===2)?green:"#24323C"
                        Column { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                            Text { text:"Protected Snapshot"; color:textMain; font.pixelSize:22; font.bold:true }
                            Text { text:"Request a recovery snapshot of the current protected state."; color:textMuted; font.pixelSize:16 }
                        }
                        Text { anchors.right:parent.right; anchors.rightMargin:16; anchors.verticalCenter:parent.verticalCenter; text:"△ SNAPSHOT"; color:green; font.pixelSize:16; font.bold:true }
                    }
                    Rectangle { width: parent.width; height: 72; radius: 7; color:"#07111A"; border.width:1; border.color:"#24323C"
                        Text { anchors.left:parent.left; anchors.leftMargin:16; anchors.verticalCenter:parent.verticalCenter; text:"Recovery minimum lock"; color:textMain; font.pixelSize:18; font.bold:true }
                        Text { anchors.right:parent.right; anchors.rightMargin:16; anchors.verticalCenter:parent.verticalCenter; text:backend&&backend.recoveryMinimumLocked?"LOCKED":"AVAILABLE"; color:backend&&backend.recoveryMinimumLocked?yellow:green; font.pixelSize:16; font.bold:true }
                    }
                }

                // Audit always presents chain state, even with no event rows.
                Column {
                    width: parent.width; spacing: 10; visible: tabIndex === 12
                    Rectangle { width: parent.width; height: 124; radius: 7; color:"#07111A"; border.width:1; border.color:backend&&backend.auditValid?"#235B3C":"#5B2D35"
                        Text { anchors.left:parent.left; anchors.leftMargin:18; anchors.top:parent.top; anchors.topMargin:16; text:"AUDIT CHAIN"; color:textMuted; font.pixelSize:15; font.bold:true }
                        Text { anchors.left:parent.left; anchors.leftMargin:18; anchors.top:parent.top; anchors.topMargin:43; text:backend&&backend.auditValid?"VALID":"ATTENTION"; color:backend&&backend.auditValid?green:red; font.pixelSize:28; font.bold:true }
                        Text { anchors.left:parent.left; anchors.leftMargin:160; anchors.right:parent.right; anchors.rightMargin:18; anchors.verticalCenter:parent.verticalCenter; text:"Head: "+String(backend?backend.auditHead||"Unavailable":"Unavailable"); color:textMain; font.pixelSize:16; font.family:"monospace"; elide:Text.ElideMiddle }
                    }
                    Rectangle { width: parent.width; height: 100; radius:7; color:"#07111A"; border.width:1; border.color:"#24323C"
                        Column { anchors.fill:parent; anchors.margins:16; spacing:7
                            Text { text:"Security Service"; color:textMain; font.pixelSize:22; font.bold:true }
                            Text { text:"Daemon: "+String(backend?backend.daemonStatus||"offline":"offline")+"    Last error: "+String(backend?backend.lastErrorCode||"none":"none"); color:textMuted; font.pixelSize:16 }
                            Text { text:"The 25 most recent meaningful security actions appear below. X on a threat entry acknowledges it as neutralized and returns to DEFCON 5."; color:green; font.pixelSize:16 }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: visible ? 68 : 0
                    radius: 7
                    visible: tabIndex === 9 && integrity().length > 0
                    color: "#1A1508"
                    border.width: 1
                    border.color: orange
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text { text: String(integrity().length)+" UNAPPROVED INTEGRITY CHANGES"; color: orange; font.pixelSize: 20; font.bold: true }
                        Text { text: "R3 twice approves the current filesystem state, replaces the trusted baseline, and clears this list."; color: textMain; font.pixelSize: 15 }
                    }
                }

                ListView {
                    id: contentList
                    width: parent.width
                    height: parent.height - 170 - ((tabIndex===9 && integrity().length>0) ? 78 : 0) - (tabIndex===12 ? 244 : 0)
                    visible: tabIndex !== 7
                    model: modelForTab(); currentIndex: selectedIndex; spacing: 8; clip: true
                    delegate: Rectangle {
                        required property int index; required property var modelData
                        width: contentList.width; height: tabIndex===11?150:(tabIndex===2?128:(tabIndex===3?96:86)); radius: 7
                        color: (focusZone===1 && index===selectedIndex)?"#0A2A20":"#07111A"; border.width:1; border.color:(focusZone===1 && index===selectedIndex)?green:"#24323C"
                        Column { anchors.left:parent.left; anchors.leftMargin:16; anchors.right:stateBadge.left; anchors.rightMargin:16; anchors.verticalCenter:parent.verticalCenter; spacing:5
                            Text { width:parent.width; text:itemTitle(modelData); color:textMain; font.pixelSize:22; font.bold:true; elide:Text.ElideRight }
                            Text { width:parent.width; text:itemDetail(modelData); color:textMuted; font.pixelSize:tabIndex===11||tabIndex===2?16:18; wrapMode:(tabIndex===11||tabIndex===2)?Text.WordWrap:Text.NoWrap; maximumLineCount:(tabIndex===11||tabIndex===2)?4:1; elide:Text.ElideRight }
                        }
                        Rectangle { id:stateBadge; anchors.right:parent.right; anchors.rightMargin:14; anchors.verticalCenter:parent.verticalCenter; width:Math.max(90,stateText.implicitWidth+22); height:30; radius:15; color:"#071A12"; border.width:1; border.color:stateTone(itemState(modelData))
                            Text { id:stateText; anchors.centerIn:parent; text:itemState(modelData); color:stateTone(text); font.pixelSize:16; font.bold:true }
                        }
                    }

                    Item {
                        anchors.centerIn: parent; width: Math.min(parent.width-40,560); height: 220; visible: contentList.count===0
                        Column { anchors.centerIn:parent; width:parent.width; spacing:12; visible: activeNavLabel!=="Malware Defense" && activeNavLabel!=="Integrity Protection"
                            Text { anchors.horizontalCenter:parent.horizontalCenter; text: tabIndex===1?"✓":(tabIndex===6?(backend&&backend.vaultUnlocked?"＋":"▣"):"○"); color:green; font.pixelSize:52; font.bold:true }
                            Text { width:parent.width; text: tabIndex===1?"No security events reported":tabIndex===2?"No hardening profiles reported":tabIndex===3?"No listening ports reported":tabIndex===4?"No rejected or blocked activity":tabIndex===5?"No peripherals awaiting review":tabIndex===6?(backend&&backend.vaultUnlocked?"No Saved Passwords":"Password Vault Locked"):tabIndex===10?"No trusted devices reported":"No data reported"; color:textMain; font.pixelSize:22; font.bold:true; horizontalAlignment:Text.AlignHCenter }
                            Text { width:parent.width; text: tabIndex===6?(backend&&backend.vaultUnlocked?"Your encrypted vault is open and empty. Press △ to add your first password.":"Press X to unlock with your controller combo. No local account password is used for normal vault access."):"The backend currently has no records for this section. The controls remain active."; color:textMuted; font.pixelSize:16; horizontalAlignment:Text.AlignHCenter; wrapMode:Text.WordWrap }
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 38; radius: 5; color:"#07151A"; border.width:1; border.color:"#1E3C2A"
                    Text { anchors.centerIn:parent; text:actionHint(); color:green; font.pixelSize:17; font.bold:true; font.letterSpacing:.2 }
                }
            }
        }
    }

    Rectangle {
        id: sshListenerOverlay
        anchors.fill: parent
        visible: sshListenersOpen
        color: "#D9000000"
        z: 690

        Rectangle {
            width: Math.min(920, parent.width - 100)
            height: Math.min(620, parent.height - 120)
            anchors.centerIn: parent
            radius: 18
            color: "#07111A"
            border.width: 2
            border.color: green

            Column {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 12
                Text { text: "SSH LISTENERS"; color: textMain; font.pixelSize: 28; font.bold: true }
                Text { text: "Active SSH exposure reported by neutron-securityd"; color: textMuted; font.pixelSize: 17 }
                Rectangle { width: parent.width; height: 1; color: "#1B2832" }
                ListView {
                    id: sshListenerList
                    width: parent.width
                    height: parent.height - 128
                    model: sshListeners()
                    currentIndex: sshListenerIndex
                    spacing: 8
                    clip: true
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: sshListenerList.width
                        height: 82
                        radius: 7
                        color: index===sshListenerIndex ? "#0A2A20" : "#081522"
                        border.width: 1
                        border.color: index===sshListenerIndex ? green : "#24323C"
                        Column {
                            anchors.left: parent.left; anchors.leftMargin: 16
                            anchors.right: parent.right; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                width: parent.width
                                text: String(modelData.processName||modelData.service||modelData.process||"SSH listener") + "   " + String(modelData.protocol||"tcp").toUpperCase() + " " + String(modelData.address||"0.0.0.0") + ":" + String(modelData.port||22)
                                color: textMain; font.pixelSize: 20; font.bold: true; elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: "Scope: " + String(modelData.scope||"unknown") + (modelData.expected===true ? "   •   Expected listener" : "") + (String(modelData.expectedReason||"").length ? "   •   "+String(modelData.expectedReason) : "")
                                color: modelData.expected===true ? green : yellow; font.pixelSize: 16; elide: Text.ElideRight
                            }
                        }
                    }
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "↑/↓ REVIEW     X / O CLOSE"; color: green; font.pixelSize: 16; font.bold: true }
            }
        }
    }

    Rectangle {
        id: listenerDetailOverlay
        anchors.fill: parent
        visible: listenerDetailOpen
        color: "#E0000000"
        z: 704
        Rectangle {
            width: Math.min(900,parent.width-100); height: Math.min(620,parent.height-120)
            anchors.centerIn: parent; radius: 20; color: panel; border.width: 2
            border.color: listenerDetailItem.suspicious===true?orange:green
            Column {
                anchors.fill: parent; anchors.margins: 28; spacing: 14
                Text { text: listenerName(listenerDetailItem); color:textMain; font.pixelSize:30; font.bold:true }
                Text { width:parent.width; text: listenerPurpose(listenerDetailItem); color:textMuted; font.pixelSize:19; wrapMode:Text.WordWrap }
                Rectangle { width:parent.width; height:1; color:border }
                Grid {
                    width:parent.width; columns:2; columnSpacing:26; rowSpacing:12
                    Text { text:"SERVICE OWNER"; color:textMuted; font.pixelSize:15; font.bold:true }
                    Text { text:String(listenerDetailItem.processUser||"Unknown"); color:textMain; font.pixelSize:18; font.bold:true }
                    Text { text:"PROCESS"; color:textMuted; font.pixelSize:15; font.bold:true }
                    Text { text:String(listenerDetailItem.processName||"Unknown")+(listenerDetailItem.pid?("  PID "+listenerDetailItem.pid):""); color:textMain; font.pixelSize:18 }
                    Text { text:"NETWORK ENDPOINT"; color:textMuted; font.pixelSize:15; font.bold:true }
                    Text { text:String(listenerDetailItem.protocol||"tcp").toUpperCase()+"  "+String(listenerDetailItem.address||"*")+":"+String(listenerDetailItem.port||"?"); color:cyan; font.pixelSize:18; font.family:"monospace" }
                    Text { text:"EXPOSURE"; color:textMuted; font.pixelSize:15; font.bold:true }
                    Text { text:String(listenerDetailItem.scope||"unknown").toUpperCase(); color:listenerDetailItem.scope==="external"?yellow:green; font.pixelSize:18; font.bold:true }
                    Text { text:"RUNNING"; color:textMuted; font.pixelSize:15; font.bold:true }
                    Text { text:formatDuration(listenerDetailItem.runningSeconds)+(String(listenerDetailItem.startedAt||"").length?("  •  since "+listenerDetailItem.startedAt):""); color:textMain; font.pixelSize:18 }
                    Text { text:"SECURITY ASSESSMENT"; color:textMuted; font.pixelSize:15; font.bold:true }
                    Text { text:listenerDetailItem.suspicious===true?"SUSPICIOUS — REVIEW REQUIRED":String(listenerDetailItem.assessment||"Observed listening service"); color:listenerDetailItem.suspicious===true?orange:(listenerDetailItem.expected===true?green:yellow); font.pixelSize:18; font.bold:true }
                }
                Rectangle { width:parent.width; height:1; color:border }
                Text { width:parent.width; text:String(listenerDetailItem.expectedReason||"").length?String(listenerDetailItem.expectedReason):"NeutronOS has not classified this listener as a known exception. Confirm the owning application and whether the exposure is intentional."; color:textMuted; font.pixelSize:16; wrapMode:Text.WordWrap }
                Item { width:1; height:1; Layout.fillHeight:true }
                Text { anchors.horizontalCenter:parent.horizontalCenter; text:"X / O CLOSE"; color:green; font.pixelSize:17; font.bold:true }
            }
        }
    }

    Rectangle {
        id: appPermissionsOverlay
        anchors.fill: parent
        visible: appPermissionsListOpen
        color: "#E0000000"
        z: 703
        Rectangle {
            width:Math.min(960,parent.width-100); height:Math.min(690,parent.height-110)
            anchors.centerIn:parent; radius:20; color:panel; border.width:2; border.color:green
            Column {
                anchors.fill:parent; anchors.margins:24; spacing:12
                Text { text:"APP PERMISSIONS"; color:textMain; font.pixelSize:29; font.bold:true }
                Text { text:"Installed NeutronOS applications and the permissions declared by their manifests."; color:textMuted; font.pixelSize:17 }
                Rectangle { width:parent.width;height:1;color:border }
                ListView {
                    id:appPermissionsList; width:parent.width; height:parent.height-126; model:installedApps(); currentIndex:appPermissionIndex; spacing:7; clip:true
                    delegate:Rectangle {
                        required property int index; required property var modelData
                        width:appPermissionsList.width; height:78; radius:7; color:index===appPermissionIndex?"#0A2A20":"#07111A"; border.width:1; border.color:index===appPermissionIndex?green:"#24323C"
                        Column { anchors.left:parent.left;anchors.leftMargin:15;anchors.right:permCount.left;anchors.rightMargin:15;anchors.verticalCenter:parent.verticalCenter;spacing:4
                            Text { width:parent.width;text:String(modelData.name||modelData.id||"App");color:textMain;font.pixelSize:21;font.bold:true;elide:Text.ElideRight }
                            Text { width:parent.width;text:String(modelData.description||modelData.category||"");color:textMuted;font.pixelSize:15;elide:Text.ElideRight }
                        }
                        Text { id:permCount;anchors.right:parent.right;anchors.rightMargin:15;anchors.verticalCenter:parent.verticalCenter;text:String((modelData.permissions||[]).length)+" PERMISSIONS";color:green;font.pixelSize:15;font.bold:true }
                    }
                }
                Text { anchors.horizontalCenter:parent.horizontalCenter;text:"↑/↓ APP     X DETAILS     O BACK";color:green;font.pixelSize:16;font.bold:true }
            }
        }
    }

    Rectangle {
        id: appPermissionDetailOverlay
        anchors.fill:parent; visible:appPermissionModalOpen; color:"#EA000000"; z:706
        Rectangle {
            width:Math.min(820,parent.width-120); height:Math.min(590,parent.height-140); anchors.centerIn:parent; radius:20;color:panel;border.width:2;border.color:green
            Column {
                anchors.fill:parent;anchors.margins:26;spacing:12
                Text { text:String(appPermissionItem.name||appPermissionItem.id||"Application");color:textMain;font.pixelSize:30;font.bold:true }
                Text { width:parent.width;text:String(appPermissionItem.description||"");color:textMuted;font.pixelSize:17;wrapMode:Text.WordWrap;maximumLineCount:3;elide:Text.ElideRight }
                Row { spacing:18
                    Text { text:"VERSION  "+String(appPermissionItem.version||"Unknown");color:cyan;font.pixelSize:15;font.bold:true }
                    Text { text:"CATEGORY  "+String(appPermissionItem.category||"App");color:cyan;font.pixelSize:15;font.bold:true }
                }
                Rectangle { width:parent.width;height:1;color:border }
                Text { text:"DECLARED PERMISSIONS";color:textMuted;font.pixelSize:16;font.bold:true }
                Flow {
                    width:parent.width; spacing:8
                    Repeater {
                        model:appPermissionItem.permissions||[]
                        Rectangle { width:Math.max(120,permissionText.implicitWidth+26);height:34;radius:17;color:"#071A12";border.width:1;border.color:green
                            Text { id:permissionText;anchors.centerIn:parent;text:String(modelData);color:green;font.pixelSize:15;font.bold:true }
                        }
                    }
                }
                Text { visible:!(appPermissionItem.permissions||[]).length;text:"No permissions declared by this application manifest.";color:yellow;font.pixelSize:17 }
                Item { width:1;height:1;Layout.fillHeight:true }
                Text { anchors.horizontalCenter:parent.horizontalCenter;text:"X / O CLOSE";color:green;font.pixelSize:16;font.bold:true }
            }
        }
    }

    Rectangle {
        id:vaultChoiceOverlay
        anchors.fill:parent;visible:vaultChoiceOpen;color:"#E8000000";z:708
        Rectangle {
            width:760;height:390;anchors.centerIn:parent;radius:22;color:panel;border.width:2;border.color:green
            Column {
                anchors.fill:parent;anchors.margins:28;spacing:16
                Text { text:"PASSWORD VAULT COMBO";color:textMain;font.pixelSize:29;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter }
                Text { width:parent.width;text:"By default the vault uses your normal NeutronOS login combo. Do you want a different controller combo just for Password Vault?";color:textMuted;font.pixelSize:18;wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter }
                Repeater {
                    model:[{t:"YES — CREATE VAULT COMBO",d:"Use a separate controller sequence for vault access."},{t:"NO — USE LOGIN COMBO",d:"Keep the same combo used by the NeutronOS login screen."}]
                    Rectangle { width:parent.width;height:76;radius:8;color:index===vaultChoiceIndex?"#0A2A20":"#07111A";border.width:1;border.color:index===vaultChoiceIndex?green:"#24323C"
                        Column { anchors.centerIn:parent;spacing:3
                            Text { anchors.horizontalCenter:parent.horizontalCenter;text:modelData.t;color:textMain;font.pixelSize:20;font.bold:true }
                            Text { anchors.horizontalCenter:parent.horizontalCenter;text:modelData.d;color:textMuted;font.pixelSize:15 }
                        }
                    }
                }
                Text { anchors.horizontalCenter:parent.horizontalCenter;text:"↑/↓ CHOOSE     X CONFIRM     O CANCEL";color:green;font.pixelSize:16;font.bold:true }
            }
        }
    }

    Rectangle {
        id:vaultComboEntryOverlay
        anchors.fill:parent;visible:vaultComboEntryOpen;color:"#EC000000";z:709
        Rectangle {
            width:780;height:430;anchors.centerIn:parent;radius:22;color:panel;border.width:2;border.color:green
            Column {
                anchors.fill:parent;anchors.margins:30;spacing:18
                Text { text:vaultComboEntryMode==="set"?(vaultComboConfirming?"CONFIRM VAULT COMBO":"CREATE VAULT COMBO"):"ENTER VAULT COMBO";color:textMain;font.pixelSize:29;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter }
                Text { width:parent.width;text:vaultComboEntryMode==="set"?"Enter 4–15 controller inputs. Press START when complete. You will enter it twice.":"Enter the custom vault combo and press START.";color:textMuted;font.pixelSize:18;wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter }
                Rectangle { width:parent.width;height:110;radius:10;color:"#050B10";border.width:1;border.color:green
                    Text { anchors.centerIn:parent;width:parent.width-30;text:vaultComboBuffer.length?vaultComboBuffer:"Waiting for controller inputs…";color:vaultComboBuffer.length?green:textMuted;font.pixelSize:23;font.bold:true;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap }
                }
                Text { width:parent.width;text:"The controller combo is the vault unlock factor. NeutronOS does not request the local account password for normal vault access.";color:green;font.pixelSize:15;wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter }
                Item { width:1;height:1;Layout.fillHeight:true }
                Text { anchors.horizontalCenter:parent.horizontalCenter;text:"CONTROLLER INPUTS     START SUBMIT     O CANCEL";color:green;font.pixelSize:16;font.bold:true }
            }
        }
    }

    Shared.ReferenceExitModal {
        id: referenceExitModal
        appName: "Security"
        onExitRequested: root.exitRequested()
        onLeaveRunningRequested: root.backgroundRequested()
        onDismissed: { root.exitMenuOpen = false; root.headerFocused = false; root.forceActiveFocus() }
    }

    Rectangle{anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;anchors.bottomMargin:38;width:Math.min(760,parent.width-80);height:toast.length?62:0;radius:18;color:toastError?"#501824":"#123D34";border.width:toast.length?2:0;border.color:toastError?red:green;visible:toast.length>0;z:500;Text{anchors.centerIn:parent;width:parent.width-30;text:toast;color:textMain;font.pixelSize:16;font.bold:true;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap}}

    Rectangle{anchors.fill:parent;visible:revealedSecret&&String(revealedSecret.id||"").length>0;color:"#E8000000";z:705
        Rectangle{anchors.centerIn:parent;width:820;height:420;radius:30;color:panel;border.width:3;border.color:green
            Column{anchors.fill:parent;anchors.margins:30;spacing:18
                Text{text:"DECRYPTED CREDENTIAL";color:green;font.pixelSize:27;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
                Text{text:String(revealedSecret.name||"Credential");color:textMain;font.pixelSize:24;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
                Rectangle{width:parent.width;height:88;radius:18;color:inset;border.width:1;border.color:border
                    Column{anchors.fill:parent;anchors.margins:14;spacing:5;Text{text:"USERNAME";color:textMuted;font.pixelSize:13;font.bold:true}Text{width:parent.width;text:String(revealedSecret.username||"");color:textMain;font.pixelSize:20;elide:Text.ElideRight}}
                }
                Rectangle{width:parent.width;height:110;radius:18;color:inset;border.width:2;border.color:green
                    Column{anchors.fill:parent;anchors.margins:14;spacing:5;Text{text:"PASSWORD — AUTO-HIDES AFTER 30 SECONDS";color:textMuted;font.pixelSize:13;font.bold:true}Text{width:parent.width;text:String(revealedSecret.password||"");color:textMain;font.pixelSize:22;font.family:"monospace";wrapMode:Text.WrapAnywhere}}
                }
                Text{text:"X OR O HIDE NOW";color:textMuted;font.pixelSize:15;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
            }
        }
    }

    Rectangle{anchors.fill:parent;visible:authOpen;color:"#E0000000";z:700
        Rectangle{anchors.centerIn:parent;width:760;height:authStage==="combo"?350:230;radius:30;color:panel;border.width:3;border.color:purple
            Column{anchors.fill:parent;anchors.margins:28;spacing:18;Text{anchors.horizontalCenter:parent.horizontalCenter;text:authPurpose==="vault-login"?"UNLOCK PASSWORD VAULT":"SECURITY REAUTHENTICATION";color:textMain;font.pixelSize:28;font.bold:true}Text{width:parent.width;text:authStage==="combo"?(authPurpose==="vault-login"?"Enter your normal NeutronOS login combo, then press START.":"Enter your controller button combo, then press START."):"Enter the account password.";color:textMuted;font.pixelSize:16;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap}Text{visible:authStage==="combo";width:parent.width;text:comboBuffer.length?comboBuffer:"WAITING FOR COMBO";color:cyan;font.pixelSize:22;font.family:"monospace";font.bold:true;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WrapAnywhere}Text{anchors.horizontalCenter:parent.horizontalCenter;text:authStage==="combo"?"START CONTINUE   O CANCEL":"VIRTUAL KEYBOARD ACTIVE";color:purple;font.pixelSize:15;font.bold:true}}
        }
    }

    Rectangle{anchors.fill:parent;visible:credentialEditorOpen;color:"#E0000000";z:710
        Rectangle{anchors.centerIn:parent;width:820;height:520;radius:30;color:panel;border.width:3;border.color:green;Column{anchors.fill:parent;anchors.margins:28;spacing:14;Text{text:"Add Secure Credential";color:textMain;font.pixelSize:29;font.bold:true}Repeater{model:[{t:"NAME",v:credentialName},{t:"USERNAME",v:credentialUsername},{t:"PASSWORD",v:credentialPassword.length?"••••••••":""},{t:"SAVE ENCRYPTED CREDENTIAL",v:""}];Rectangle{width:parent.width;height:78;radius:17;color:credentialField===index?"#174A43":raised;border.width:credentialField===index?3:1;border.color:credentialField===index?green:border;Column{anchors.fill:parent;anchors.margins:12;spacing:4;Text{text:modelData.t;color:credentialField===index?green:textMuted;font.pixelSize:14;font.bold:true}Text{width:parent.width;text:modelData.v;color:textMain;font.pixelSize:18;elide:Text.ElideRight}}}}Text{text:"↑/↓ FIELD   X EDIT / SAVE   O CANCEL";color:textMuted;font.pixelSize:15;font.bold:true}}}
    }

    // Search and credential entry deliberately share one compact keyboard
    // footprint and opacity so Security has one consistent input surface.
    Rectangle {
        id: secureKeyboardBackdrop
        visible: keyboardOpen
        x: secureKeyboard.x - 12
        y: secureKeyboard.y - 12
        width: secureKeyboard.width + 24
        height: secureKeyboard.height + 24
        radius: 26
        color: "#FC061126"
        border.width: 1
        border.color: "#557DF9FF"
        z: 899
    }

    Shared.VirtualKeyboard {
        id: secureKeyboard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        width: Math.round(920 * 0.80)
        height: Math.round(430 * 0.80)
        visibleMode: keyboardOpen
        active: keyboardOpen
        z: 900

        onKeyPressed: function(value) { keyboardBuffer += value }
        onBackspacePressed: keyboardBuffer = keyboardBuffer.slice(0, -1)
        onEnterPressed: {
            visibleMode = false
            if (keyboardPurpose === "search") {
                commitSettingsSearch()
                return
            }
            keyboardOpen = false
            if (authOpen && authStage === "password")
                finishPassword()
            else if (credentialEditorOpen) {
                if (credentialField === 0)
                    credentialName = keyboardBuffer
                else if (credentialField === 1)
                    credentialUsername = keyboardBuffer
                else
                    credentialPassword = keyboardBuffer
                keyboardBuffer = ""
                forceActiveFocus()
            }
        }
        onClosePressed: {
            visibleMode = false
            keyboardOpen = false
            if (keyboardPurpose === "search") {
                searchQuery = keyboardBuffer
                keyboardPurpose = ""
            }
            keyboardBuffer = ""
            forceActiveFocus()
        }
    }

    Rectangle{id:introOverlay;anchors.fill:parent;visible:introActive;color:bg;z:1000;opacity:1
        Column{anchors.centerIn:parent;spacing:26
            Item{width:240;height:250;anchors.horizontalCenter:parent.horizontalCenter
                Rectangle{id:lockBody;width:176;height:142;radius:30;anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;color:"#0C2638";border.width:5;border.color:introStage>=1?green:cyan
                    Behavior on border.color{ColorAnimation{duration:300}}
                    Rectangle{width:28;height:28;radius:14;anchors.horizontalCenter:parent.horizontalCenter;anchors.verticalCenter:parent.verticalCenter;color:green}
                    Rectangle{width:8;height:44;radius:4;anchors.horizontalCenter:parent.horizontalCenter;anchors.top:parent.verticalCenter;anchors.topMargin:8;color:green}
                }
                Rectangle{id:shackle;width:116;height:108;radius:58;anchors.horizontalCenter:parent.horizontalCenter;y:introStage>=1?2:43;color:"transparent";border.width:12;border.color:introStage>=1?green:cyan;rotation:introStage>=1?13:0;transformOrigin:Item.BottomLeft
                    Behavior on y{NumberAnimation{duration:620;easing.type:Easing.OutBack}}
                    Behavior on rotation{NumberAnimation{duration:620;easing.type:Easing.OutBack}}
                    Behavior on border.color{ColorAnimation{duration:300}}
                }
                SequentialAnimation on scale{running:introActive&&introStage===0;loops:Animation.Infinite;NumberAnimation{to:1.045;duration:520;easing.type:Easing.InOutSine}NumberAnimation{to:1.0;duration:520;easing.type:Easing.InOutSine}}
            }
            Text{anchors.horizontalCenter:parent.horizontalCenter;text:introStage>=1?"SECURITY UNLOCKED":"NEUTRONOS SECURITY";color:textMain;font.pixelSize:30;font.bold:true;font.letterSpacing:2}
            Text{anchors.horizontalCenter:parent.horizontalCenter;text:introStage>=1?"PROTECTION LAYERS ONLINE":"VERIFYING PROTECTION LAYERS";color:green;font.pixelSize:15;font.bold:true;font.letterSpacing:1.6}
        }
    }
    SequentialAnimation{id:introSequence
        PauseAnimation{duration:520}
        ScriptAction{script:introStage=1}
        PauseAnimation{duration:720}
        NumberAnimation{target:introOverlay;property:"opacity";to:0;duration:300;easing.type:Easing.InOutQuad}
        ScriptAction{script:{introActive=false;introOverlay.opacity=1;forceActiveFocus()}}
    }

    Rectangle { anchors.centerIn:centerPanel; width:420; height:105; radius:52; z:35; visible:activeNavLabel==="Malware Defense"&&malware().length===0; color:"#183F30"; border.width:3; border.color:green; Text { anchors.centerIn:parent; text:"NO MALWARE"; color:green; font.pixelSize:29; font.bold:true; font.letterSpacing:2 } }
    Rectangle { anchors.centerIn:centerPanel; width:520; height:105; radius:52; z:35; visible:activeNavLabel==="Integrity Protection"&&integrity().length===0; color:"#183F30"; border.width:3; border.color:green; Text { anchors.centerIn:parent; text:"INTEGRITY VERIFIED"; color:green; font.pixelSize:29; font.bold:true } }

    Keys.onPressed:function(event){var a="";if(event.key===Qt.Key_Left)a="left";else if(event.key===Qt.Key_Right)a="right";else if(event.key===Qt.Key_Up)a="up";else if(event.key===Qt.Key_Down)a="down";else if(event.key===Qt.Key_Return||event.key===Qt.Key_Enter)a="primary";else if(event.key===Qt.Key_Escape||event.key===Qt.Key_Back||event.key===Qt.Key_Menu)a="cancel";else if(event.key===Qt.Key_Space)a="secondary";else if(event.key===Qt.Key_T)a="context";else if(event.key===Qt.Key_R)a="r3";if(a.length){event.accepted=handleControllerPressed(a)}}
}
