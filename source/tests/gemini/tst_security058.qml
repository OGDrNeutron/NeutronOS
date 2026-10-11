import QtQuick
import QtTest
import "../../qml/components" as Components
import "../../qml/apps/security/components" as SecurityComponents
import "../../qml/components/SecurityIndicator.js" as Indicator
import "../../qml/gemini" as Gemini
import "../../qml/dashboard/v2" as Dashboard
TestCase {
 id:t;name:"Security058AuthoritativeProjection";visible:true;width:1672;height:941;when:windowShown
 QtObject{id:backend;property bool indicatorOnline:true;property int indicatorScore:100;property bool daemonOnline:true;property int securityScore:indicatorScore}
 QtObject{id:host;property var loginSecurityBackend:backend;property var controllerBackend:null;property bool loginSuccess:false;property bool animationsEnabled:false;property bool cardArmed:false;property string lockscreenFocus:"user";property string errorText:"";property string statusText:"";property var inputTokens:[];property real unlockRippleScale:1;property real unlockRippleOpacity:0;signal authenticationInputAccepted();function greetingPrefix(){return "Test"}function currentDisplayName(){return "Test"}function currentAvatarSource(){return ""}function isLockedOut(){return false}function lockoutSecondsRemaining(){return 0}}
 Gemini.LockPresentation{id:lock;anchors.fill:parent;host:host;clockBackend:worldClockTestBackend}
 Components.SecurityScorePresentation{id:app;backend:backend}
 SecurityComponents.Header{id:appHeader;securityScore:Indicator.score(backend)}
 Dashboard.SecurityDashboardView{id:securityApp;backend:backend;visible:false}
 function test_same_score_and_state_across_state_and_lock_changes(){
  for(var score of [100,90,75,70,55,54,0]){
   backend.indicatorOnline=true;backend.indicatorScore=score;compare(app.score,score);compare(securityApp.securityScore(),score);compare(findChild(lock,"GeminiLockSecurityLabel").text,Indicator.label(backend))
   compare(app.strength,Indicator.label(backend));compare(appHeader.protectionText,Indicator.label(backend).toUpperCase());compare(securityApp.securityStrength(),Indicator.label(backend))
   lock.visible=false;lock.visible=true;compare(app.score,score)
  }
 }
 function test_unavailable_never_secure(){backend.indicatorOnline=false;compare(app.score,-1);compare(app.strength,"Unavailable");compare(appHeader.protectionText,"UNAVAILABLE");compare(securityApp.securityScore(),-1);compare(securityApp.securityStrength(),"Unavailable");compare(Indicator.score({daemonOnline:true,securityScore:Infinity}),-1);compare(Indicator.score({daemonOnline:true,securityScore:-1}),-1);compare(Indicator.score(null),-1)}
}
