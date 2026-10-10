import QtQuick
import "../../components" as Components

Item {
    id: root
    property var backend: null
    property bool opened: false
    property int section: 0
    property int selectedIndex: 0
    property int actionIndex: 0
    property bool editingName: false
    property bool previewOpen: false
    property string editingTabId: ""
    property string pendingName: ""
    property int sizeStage: 0
    property string pendingSizeFamily: ""
    readonly property var widgets: backend && backend.widgets ? backend.widgets : []
    readonly property var tabs: backend && backend.customTabs ? backend.customTabs : []
    readonly property var rows: section === 0 ? widgets : tabs
    signal closed()
    visible: opened; enabled: opened; z: 700

    function openManager() { section=0; selectedIndex=0; actionIndex=0;sizeStage=0;pendingSizeFamily=""; opened=true; forceActiveFocus() }
    function closeManager() { sizeStage=0;pendingSizeFamily="";opened=false; keyboard.closeKeyboard(); closed() }
    function current() { return rows.length ? rows[Math.max(0,Math.min(selectedIndex,rows.length-1))] : null }
    function widgetActions() {
        var item=current(); if(!item)return []
        var values=[item.enabled===false?"Enable":"Disable","Move Earlier","Move Later"]
        if(String(item.id)!=="temperature") values.push("Size")
        values.push("Reset Widget","Restore Default Placement")
        return values
    }
    function sizeVariants(){var item=current();return item&&backend&&backend.availableSizeVariants?backend.availableSizeVariants(String(item.id)):[]}
    function sizeChoices(){
        if(sizeStage===1){var out=[],families=["small","medium","large"],variants=sizeVariants();for(var i=0;i<families.length;++i){var ok=false;for(var j=0;j<variants.length;++j)if(String(variants[j].family)===families[i]&&variants[j].available!==false)ok=true;out.push({id:families[i],label:families[i].charAt(0).toUpperCase()+families[i].slice(1),available:ok})}return out}
        if(sizeStage===2){var choices=[],all=sizeVariants();for(var n=0;n<all.length;++n)if(String(all[n].family)===pendingSizeFamily)choices.push(all[n]);return choices}
        return []
    }
    function executeSizeChoice(){
        var item=current(),choices=sizeChoices();if(!item||actionIndex<0||actionIndex>=choices.length)return
        var choice=choices[actionIndex];if(choice.available===false)return
        if(sizeStage===1){pendingSizeFamily=String(choice.id);if(pendingSizeFamily==="small"){var variants=sizeVariants();for(var i=0;i<variants.length;++i)if(String(variants[i].id)==="small-square"&&variants[i].available!==false){backend.setWidgetSize(String(item.id),"small-square");sizeStage=0;actionIndex=0;return}}else{sizeStage=2;actionIndex=0}return}
        if(sizeStage===2&&backend.setWidgetSize(String(item.id),String(choice.id))){sizeStage=0;pendingSizeFamily="";actionIndex=0}
    }
    function executeWidget() {
        var item=current(), actions=widgetActions(); if(!item||!backend||!actions.length)return
        var action=String(actions[actionIndex])
        if(action==="Enable"||action==="Disable")backend.setWidgetEnabled(String(item.id),action==="Enable")
        else if(action==="Move Earlier")backend.moveWidget(String(item.id),-1)
        else if(action==="Move Later")backend.moveWidget(String(item.id),1)
        else if(action==="Size"){sizeStage=1;actionIndex=0}
        else if(action==="Reset Widget")backend.resetWidget(String(item.id))
        else if(action==="Restore Default Placement")backend.resetLayout()
    }
    function createTab() { editingTabId="";editingName=true;pendingName="";keyboard.openKeyboard(false) }
    function renameTab() {
        var item=current(); if(!item||String(item.id)==="create")return
        editingTabId=String(item.id);editingName=true;pendingName=String(item.name||"");keyboard.openKeyboard(false)
    }
    function handleControllerPressed(action) {
        if(!opened)return false
        if(editingName)return keyboard.handleControllerPressed(action)
        if(previewOpen){if(action==="cancel"||action==="context"||action==="primary")previewOpen=false;return true}
        if(action==="cancel"){
            if(sizeStage===2){sizeStage=1;pendingSizeFamily="";actionIndex=0;return true}
            if(sizeStage===1){sizeStage=0;actionIndex=0;return true}
            closeManager();return true
        }
        if(sizeStage>0){
            if(action==="left"||action==="up")actionIndex=Math.max(0,actionIndex-1)
            else if(action==="right"||action==="down")actionIndex=Math.min(Math.max(0,sizeChoices().length-1),actionIndex+1)
            else if(action==="primary")executeSizeChoice()
            return true
        }
        if(action==="l1"||action==="r1"){section=section===0?1:0;selectedIndex=0;actionIndex=0;return true}
        if(action==="up")selectedIndex=Math.max(0,selectedIndex-1)
        else if(action==="down")selectedIndex=Math.min(Math.max(0,(section===0?widgets.length-1:tabs.length)),selectedIndex+1)
        else if(action==="left"&&section===0)actionIndex=Math.max(0,actionIndex-1)
        else if(action==="right"&&section===0)actionIndex=Math.min(Math.max(0,widgetActions().length-1),actionIndex+1)
        else if(action==="primary"){
            if(section===0)executeWidget()
            else if(selectedIndex>=tabs.length)createTab()
            else renameTab()
        } else if(action==="secondary"&&section===1&&current())backend.deleteCustomTab(String(current().id))
        else if(action==="context"&&section===0&&current())previewOpen=true
        else if(action==="context"&&section===1)createTab()
        return true
    }
    Rectangle { visible:root.previewOpen;z:22;anchors.centerIn:parent;width:720;height:360;radius:28;color:"#FA071426";border.width:3;border.color:"#35DFFF"
        Column { anchors.fill:parent;anchors.margins:30;spacing:18
            Text{text:"WIDGET PREVIEW";color:"#61E8FF";font.pixelSize:16;font.bold:true;font.letterSpacing:2}
            Text{width:parent.width;text:root.current()?String(root.current().title||"Widget"):"Widget";color:"white";font.pixelSize:34;font.bold:true}
            Text{width:parent.width;text:root.current()?((root.current().enabled===false?"DISABLED":"ENABLED")+"  •  "+String(root.current().size||"fixed").toUpperCase()+"  •  POSITION "+(Number(root.current().order)+1)):"Unavailable";color:"#AFC8DE";font.pixelSize:19}
            Text{width:parent.width;text:"The live Dashboard card keeps its authoritative telemetry and focus treatment. Changes apply immediately and the responsive grid reflows around it.";color:"#C7D8E8";font.pixelSize:16;wrapMode:Text.WordWrap}
            Text{width:parent.width;text:"X / △ / O  CLOSE";color:"#55DFFF";font.pixelSize:14;font.bold:true;horizontalAlignment:Text.AlignHCenter}
        }
    }
    Rectangle { visible:root.sizeStage>0;z:23;anchors.centerIn:parent;width:760;height:480;radius:28;color:"#FA071426";border.width:3;border.color:"#35DFFF"
        Column { anchors.fill:parent;anchors.margins:28;spacing:14
            Text{width:parent.width;text:root.sizeStage===1?"CHOOSE SIZE FAMILY":root.pendingSizeFamily.toUpperCase()+" SHAPE";color:"white";font.pixelSize:28;font.bold:true}
            Text{width:parent.width;text:"Unavailable choices cannot fit the complete visible System Overview layout.";color:"#AFC8DE";font.pixelSize:15;wrapMode:Text.WordWrap}
            Repeater{model:root.sizeChoices();delegate:Rectangle{required property int index;required property var modelData;width:parent.width;height:72;radius:14;opacity:modelData.available===false?.4:1;color:index===root.actionIndex&&modelData.available!==false?"#17466A":"#0A1A2A";border.width:index===root.actionIndex?2:1;border.color:modelData.available===false?"#526071":index===root.actionIndex?"#35DFFF":"#31506D";Text{anchors.centerIn:parent;text:String(modelData.label)+(modelData.available===false?"  •  UNAVAILABLE":"");color:modelData.available===false?"#7C8B9C":"white";font.pixelSize:18;font.bold:true}}}
            Text{width:parent.width;text:"D-PAD  CHOOSE     X  SELECT     O  BACK";color:"#55DFFF";font.pixelSize:14;font.bold:true;horizontalAlignment:Text.AlignHCenter}
        }
    }
    function handleControllerReleased(action){if(editingName&&keyboard.handleControllerReleased)return keyboard.handleControllerReleased(action);return opened}

    Rectangle { anchors.fill:parent; color:"#F4050A13" }
    Rectangle {
        anchors.fill:parent; anchors.margins:46; radius:30; color:"#F0071423"; border.width:3; border.color:"#31DFFF"
        Column { anchors.fill:parent; anchors.margins:30; spacing:16
            Text { text:"SYSTEM OVERVIEW MANAGER"; color:"white"; font.pixelSize:30; font.bold:true }
            Row { spacing:12
                Repeater { model:["AVAILABLE WIDGETS","CUSTOM TABS"]
                    delegate:Rectangle { required property int index; required property string modelData; width:260;height:48;radius:14;color:root.section===index?"#15466A":"#0A1A2B";border.width:root.section===index?2:1;border.color:root.section===index?"#35DFFF":"#31506D";Text{anchors.centerIn:parent;text:modelData;color:"white";font.pixelSize:15;font.bold:true} }
                }
            }
            ListView { id:list; width:parent.width; height:parent.height-160; spacing:10; clip:true; model:root.section===0?root.widgets:root.tabs.concat([{id:"create",name:"＋ CREATE CUSTOM TAB",type:"create"}]); currentIndex:root.selectedIndex
                delegate:Rectangle { required property int index; required property var modelData; width:list.width;height:82;radius:18;color:index===root.selectedIndex?"#153653":"#091827";border.width:index===root.selectedIndex?3:1;border.color:index===root.selectedIndex?"#35DFFF":"#29455F"
                    Row { anchors.fill:parent;anchors.margins:16;spacing:18
                        Text { width:42;anchors.verticalCenter:parent.verticalCenter;text:root.section===0?(modelData.enabled===false?"○":"◉"):String(modelData.icon||"◈");color:modelData.enabled===false?"#72879E":"#52EDA2";font.pixelSize:25 }
                        Column { width:330;anchors.verticalCenter:parent.verticalCenter;spacing:5;Text{text:String(modelData.title||modelData.name||"Unknown");color:"white";font.pixelSize:19;font.bold:true}Text{text:root.section===0?((modelData.enabled===false?"DISABLED":"ENABLED")+" • "+String(modelData.size||"fixed").toUpperCase()+" • POSITION "+(Number(modelData.order)+1)):String(modelData.type||"widgets").toUpperCase();color:"#9EB8D2";font.pixelSize:13} }
                        Text { visible:root.section===0&&index===root.selectedIndex;width:parent.width-450;anchors.verticalCenter:parent.verticalCenter;text:root.widgetActions().join("   •   ");color:"#5BDFFF";font.pixelSize:14;wrapMode:Text.WordWrap }
                    }
                }
            }
            Text { width:parent.width;text:section===0?"L1/R1 TABS  •  D-PAD SELECT ACTION  •  X APPLY  •  O CLOSE":"L1/R1 SECTIONS  •  X RENAME / CREATE  •  △ CREATE TAB  •  □ DELETE  •  O CLOSE";color:"#75DFFF";font.pixelSize:14;font.bold:true;horizontalAlignment:Text.AlignHCenter }
        }
    }
    Components.VirtualKeyboard { id:keyboard;anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:560;z:20;visible:root.editingName
        onKeyPressed:function(value){root.pendingName+=value}
        onBackspacePressed:root.pendingName=root.pendingName.slice(0,-1)
        onEnterPressed:{if(root.backend&&root.pendingName.trim().length){if(root.editingTabId.length)root.backend.renameCustomTab(root.editingTabId,root.pendingName);else root.backend.createCustomTab(root.pendingName,"◈","system")}root.editingName=false;root.editingTabId="";closeKeyboard();root.forceActiveFocus()}
        onClosePressed:{root.editingName=false;closeKeyboard();root.forceActiveFocus()}
    }
    Rectangle { visible:root.editingName;z:21;anchors.horizontalCenter:parent.horizontalCenter;y:65;width:760;height:76;radius:18;color:"#F20B1B2D";border.width:3;border.color:"#35DFFF";Text{anchors.centerIn:parent;text:root.pendingName.length?root.pendingName:"Name your custom Dashboard tab";color:root.pendingName.length?"white":"#7895B5";font.pixelSize:22} }
}
