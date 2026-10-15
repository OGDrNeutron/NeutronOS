import QtQuick
import QtTest
import "../../qml/apps/settings" as Settings
TestCase {
 id:t;name:"Settings059";visible:true;width:1672;height:941;when:windowShown
 QtObject {
  id:preferences;property string themeMode:"dark";property bool developerModeEnabled:false;property int pendingCount:0;property bool autoLogin:false;property int applyCalls:0;property string lastMessage:"Fixture apply rejected";property var pendingChanges:({});property var systemInfo:({prettyProductName:"Debian — test fixture"});property var integrityReport:({valid:false,title:"Unavailable",summary:"Fixture"})
  function refresh(){}
  function value(key,fallback){return key==="user.autoLogin"?autoLogin:fallback}
  function applyPending(){applyCalls++;return false}
  function setThemeMode(mode){themeMode=mode}
  function setUiPreference(key,value){}
  function discardPending(){pendingCount=0}
 }
 QtObject{id:controller;property bool controllerConnected:true;property bool controllerBatteryAvailable:false;property int controllerBatteryPercent:-1}
 QtObject{id:security;property bool indicatorOnline:false;property int indicatorScore:-1;property bool daemonOnline:false;property bool auditValid:false;property int threatLevel:5}
 QtObject{id:network;property string connectionState:"DISCONNECTED";property int connectivity:0}
 Settings.Main{id:ui;anchors.fill:parent;settingsBackend:preferences;controllerBackend:controller;securityCoreBackend:security}
 function init(){ui.exitModalVisible=false;ui.searchText="";ui.selectSidebar(0);ui.focusZone=0;preferences.themeMode="dark";preferences.autoLogin=false;preferences.pendingCount=0;preferences.pendingChanges=({});preferences.applyCalls=0;ui.statusMessage="";ui.statusError=false;ui.closeKeyboard()}
 function test_categories_and_all_pages_accessible(){
  compare(ui.categories.length,19);compare(ui.centerEntries.length,12)
  var pages={}
  for(var i=1;i<ui.categories.length;i++){
   ui.selectSidebar(i)
   for(var p of ui.centerEntries){pages[p.id]=true;ui.openCategoryById(p.id);compare(ui.currentCategoryId(),p.id);verify(findChild(ui,"SettingsControls059").count>0,p.id);verify(!ui.statusError,p.id)}
  }
  compare(Object.keys(pages).length,24);compare(ui.categories[18].title,"Extra")
 }
 function test_promoted_categories_and_empty_extra(){
  var expected=["Home","System","Display","Network","Bluetooth","Controller","Storage","Security","Power","Apps","Appearance","Date & Time","Audio","Accessibility","Notifications","Advanced","Help","About","Extra"]
  for(var i=0;i<expected.length;i++)compare(ui.categories[i].title,expected[i])
  ui.selectSidebar(0);compare(ui.centerEntries.length,12);compare(ui.centerEntries[11].id,"about")
  ui.selectCenter(11);ui.activateCenter();compare(ui.sidebarIndex,17);compare(ui.currentCategoryId(),"about")
  for(var id of ["audio","accessibility","notifications","advanced","help"]){
   ui.openCategoryById(id);compare(ui.categories[ui.sidebarIndex].id,id);compare(ui.centerEntries.length,1);compare(ui.currentCategoryId(),id)
   verify(findChild(ui,"SettingsControls059").count>0);ui.focusZone=4;ui.activateCenter();compare(ui.focusZone,1)
  }
  ui.selectSidebar(18);compare(ui.centerEntries.length,0);compare(ui.currentCategoryId(),"extra");ui.selectCenter(-1);ui.activateCenter();verify(!ui.statusError)
  ui.focusZone=0;ui.handleControllerPressed("up");compare(ui.sidebarIndex,17);ui.handleControllerPressed("down");compare(ui.sidebarIndex,18)
  var sidebar=findChild(ui,"SettingsSidebar059");wait(60);verify(sidebar.contentY>0);verify(sidebar.currentItem.y>=sidebar.contentY);verify(sidebar.currentItem.y+sidebar.currentItem.height<=sidebar.contentY+sidebar.height+1)
  ui.handleControllerPressed("down");compare(ui.sidebarIndex,0)
 }
 function test_navigation_and_theme(){
  ui.handleControllerPressed("right");compare(ui.focusZone,4)
  ui.handleControllerPressed("primary");compare(ui.sidebarIndex,1)
  ui.handleControllerPressed("primary");compare(ui.focusZone,1)
  ui.handleControllerPressed("cancel");compare(ui.focusZone,4)
  ui.handleControllerPressed("secondary");compare(preferences.themeMode,"light")
  var category=ui.sidebarIndex;var zone=ui.focusZone;ui.handleControllerPressed("system");compare(ui.sidebarIndex,category);compare(ui.focusZone,zone)
  ui.handleControllerPressed("cancel");compare(ui.focusZone,0)
 }
 function test_footer_live_data_and_context(){
  var footer=findChild(ui,"SettingsFooter059");verify(footer!==null)
  compare(footer.battery,-1);compare(footer.securityScore,-1)
  controller.controllerBatteryAvailable=true;controller.controllerBatteryPercent=63;compare(footer.battery,63)
  controller.controllerBatteryAvailable=false;compare(footer.battery,-1)
  security.indicatorOnline=true;security.indicatorScore=90;compare(footer.securityLabel,"Secure")
  security.indicatorScore=70;compare(footer.securityLabel,"Weak Protection")
  security.indicatorScore=40;compare(footer.securityLabel,"Unsecure")
  security.indicatorOnline=false;compare(footer.securityLabel,"Unavailable")
  ui.focusZone=-1;compare(footer.contextText,"SECURE. INTELLIGENT. UNSTOPPABLE.")
  ui.selectSidebar(3);ui.focusZone=0;compare(footer.contextText,"CONNECT. DISCOVER. COMMUNICATE.")
 }
 function test_keyboard_and_protected_apply(){
  ui.handleControllerPressed("context");verify(ui.keyboardOpen);compare(ui.keyboardTarget,"search");ui.closeKeyboard()
  preferences.autoLogin=true;preferences.pendingChanges=({"advanced.safeMode":true});preferences.pendingCount=1
  ui.applyPendingWithAuthorization();verify(ui.keyboardOpen);compare(ui.keyboardTarget,"highPriorityPassword");compare(preferences.applyCalls,0);ui.closeKeyboard()
  ui.pendingProtectedKind="";preferences.autoLogin=false;preferences.pendingChanges=({"audio.volume":40})
  ui.focusZone=2;ui.rebootChoice=1;ui.handleControllerPressed("primary");compare(preferences.applyCalls,1);verify(ui.statusError);compare(preferences.pendingCount,1)
  ui.focusZone=2;ui.rebootChoice=0;ui.handleControllerPressed("primary");compare(preferences.pendingCount,0)
 }
 function test_wifi_transitions(){
  var footer=findChild(ui,"SettingsFooter059");footer.networkBackend=network
  network.connectionState="CONNECTED";network.connectivity=4;compare(footer.wifiColor,"#22ff88")
  network.connectivity=2;compare(footer.wifiColor,"#ffd45a")
  network.connectionState="DISCONNECTED";compare(footer.wifiColor,"#ff4057")
  footer.networkBackend=Qt.binding(function(){return ui.networkBackend})
 }
 function test_footer_default_colors_and_passive_updates(){
  var footer=findChild(ui,"SettingsFooter059");var label=findChild(ui,"SettingsFooterContext")
  compare(footer.contextText,"SECURE. INTELLIGENT. UNSTOPPABLE.");compare(label.color,"#94ebff");verify(label.text.indexOf("<font color='#ff4057'>UNSTOPPABLE.</font>")>=0)
  ui.selectCenter(4);compare(footer.contextText,ui.defaultFooterMotto)
  security.indicatorOnline=true;security.indicatorScore=42;controller.controllerBatteryAvailable=true;controller.controllerBatteryPercent=37;footer.localNow=new Date()
  ui.refreshPage();compare(footer.contextText,ui.defaultFooterMotto)
  ui.selectSidebar(3);var active=footer.contextText;ui.refreshPage();footer.localNow=new Date();security.indicatorScore=95;compare(footer.contextText,active)
  controller.controllerBatteryAvailable=false;security.indicatorOnline=false
 }
 function test_footer_hint_expiration_and_priority(){
  var footer=findChild(ui,"SettingsFooter059")
  ui.showControllerHint("X SELECT · O BACK",40);compare(footer.contextText,"X SELECT · O BACK");wait(90);compare(footer.contextText,ui.defaultFooterMotto)
  ui.selectSidebar(3);var selected=footer.contextText;ui.showControllerHint("NAVIGATE WITH D-PAD",50);compare(footer.contextText,"NAVIGATE WITH D-PAD");wait(90);compare(footer.contextText,selected)
  ui.showControllerHint("FIRST HINT",40);ui.showControllerHint("SECOND HINT",120);wait(70);compare(footer.contextText,"SECOND HINT");wait(100);compare(footer.contextText,selected)
 }
 function test_footer_default_restoration_and_modal_close(){
  var footer=findChild(ui,"SettingsFooter059");ui.selectSidebar(3);verify(footer.contextText!==ui.defaultFooterMotto)
  ui.selectSidebar(0);compare(footer.contextText,ui.defaultFooterMotto)
  ui.openKeyboard("search","","Search Settings");ui.showControllerHint("TYPE THEN CONFIRM",1000);ui.closeKeyboard();compare(footer.contextText,ui.defaultFooterMotto)
  ui.selectSidebar(3);ui.focusZone=-1;compare(footer.contextText,ui.defaultFooterMotto)
 }
 function test_passive_refresh_preserves_selected_setting(){
  ui.selectSidebar(1);ui.focusZone=1;ui.handleControllerPressed("down");var list=findChild(ui,"SettingsControls059");var selected=list.currentIndex;var message=ui.footerContext
  ui.refreshPage();compare(list.currentIndex,selected);compare(ui.footerContext,message)
 }
 function test_render_home_and_extra(){
  ui.selectSidebar(0);ui.focusZone=4;wait(500);grabImage(ui).save('/gemini/validation/screenshots/settings059-home-development.png')
  ui.selectSidebar(1);ui.focusZone=1;wait(100);grabImage(ui).save('/gemini/validation/screenshots/settings059-system-development.png')
  for(var id of ["audio","accessibility","notifications","advanced","help"]){ui.openCategoryById(id);wait(100);grabImage(ui).save("/gemini/validation/screenshots/settings059-"+id+"-development.png")}
  ui.selectSidebar(18);wait(100);grabImage(ui).save('/gemini/validation/screenshots/settings059-extra-development.png')
  preferences.themeMode="light";wait(100);grabImage(ui).save('/gemini/validation/screenshots/settings059-light-development.png')
 }
}
