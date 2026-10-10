import QtQuick
import QtTest
import "../../qml" as Shell
TestCase {
 id:test;name:"Gemini056Security";when:windowShown;visible:true;width:1920;height:1080
 QtObject{
  id:securityCoreManager
  property bool daemonOnline:false
  property bool auditValid:false
  property int threatLevel:5
  property var integrityChanges:[]
  property var malwareFindings:[]
  property var events:[]
  function refresh(){}
 }
 Shell.LoginScreen{id:login;anchors.fill:parent;active:false;animationsEnabled:false}
 function find(item,name){if(item.objectName===name)return item;var c=item.children||[];for(var i=0;i<c.length;i++){var hit=find(c[i],name);if(hit)return hit}return null}
 function test_authoritative_transitions(){
  var badge=find(login,"GeminiLockSecurityBadge");verify(badge!==null);verify(!badge.known);verify(!badge.secure);compare(String(badge.accent),"#ffd45a")
  grabImage(test).save("/gemini/validation/screenshots/lock-security-unavailable.png")
  securityCoreManager.daemonOnline=true;securityCoreManager.auditValid=true;compare(badge.known,true);compare(badge.secure,true);compare(String(badge.accent),"#00ff87")
  grabImage(test).save("/gemini/validation/screenshots/lock-security-secure.png")
  for(var reason of ["audit","integrity","malware","event","threat"]){
   securityCoreManager.auditValid=reason!=="audit";securityCoreManager.integrityChanges=reason==="integrity"?[{}]:[];securityCoreManager.malwareFindings=reason==="malware"?[{}]:[];securityCoreManager.events=reason==="event"?[{severity:"critical",acknowledged:false}]:[];securityCoreManager.threatLevel=reason==="threat"?1:5
   verify(!badge.secure,reason);compare(String(badge.accent),"#ff1735")
  }
  grabImage(test).save("/gemini/validation/screenshots/lock-security-attention.png")
  securityCoreManager.daemonOnline=false;verify(!badge.known);verify(!badge.secure);compare(String(badge.accent),"#ffd45a")
 }
}
