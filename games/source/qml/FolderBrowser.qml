import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: browser
    required property var backend
    property var entries: []
    property string location: ""
    property string parentLocation: ""
    property string errorText: ""
    property int selection: 0
    property string section: "locations"
    property alias manualField: manual
    property int editIndex: -1
    signal cancelRequested()
    signal saved(string path)
    signal keyboardRequested(var field)
    function browse(path) {
        var result=backend.browseFolders(path)
        if(!result.ok){errorText=String(result.error||"Location unavailable");return false}
        location=String(result.path||"");parentLocation=String(result.parent||"")
        entries=result.entries||[];selection=0;manual.text=location;errorText="";section="locations"
        return true
    }
    function open(index) {editIndex=index;errorText="";browse("");forceActiveFocus()}
    function save() {
        if(!location.length){errorText="Open a folder, then select Add This Folder.";return}
        var ok=editIndex>=0?backend.editFolder(editIndex,location):backend.addFolder(location)
        if(ok)saved(location)
        else errorText="Folder could not be saved. Check permissions, duplicate locations, and library messages."
    }
    function handleControllerPressed(action) {
        if(action==="cancel"){
            if(section!=="locations"){section="locations";return true}
            if(location.length)browse(parentLocation)
            else cancelRequested()
        } else if(action==="up") {
            if(section==="save")section="manual"
            else if(section==="manual")section="locations"
            else if(selection>=4)selection-=4
            else section="back"
        } else if(action==="down") {
            if(section==="back")section="locations"
            else if(section==="locations"&&selection+4<entries.length)selection+=4
            else if(section==="locations")section="manual"
            else if(section==="manual")section="save"
        } else if(action==="left"&&section==="locations")selection=Math.max(0,selection-1)
        else if(action==="right"&&section==="locations")selection=Math.min(Math.max(0,entries.length-1),selection+1)
        else if(action==="primary") {
            if(section==="back") {if(location.length)browse(parentLocation);else cancelRequested()}
            else if(section==="manual")keyboardRequested(manual)
            else if(section==="save")save()
            else if(entries.length)browse(entries[selection].path)
        }
        return true
    }
    Rectangle {anchors.fill:parent;color:"#e901050d";MouseArea{anchors.fill:parent}}
    NeonPanel {
        anchors.centerIn:parent;width:Math.min(parent.width-48,1180);height:Math.min(parent.height-48,820);illuminated:true
        ColumnLayout {
            anchors.fill:parent;anchors.margins:28;spacing:12
            Text {Layout.fillWidth:true;text:browser.editIndex>=0?"Change Games Folder":"Add Games Folder";color:"white";font.pixelSize:28;font.bold:true}
            RowLayout {
                Layout.fillWidth:true;spacing:16
                NeonPanel {Layout.preferredWidth:115;Layout.preferredHeight:38;illuminated:browser.section==="back"
                    Text{anchors.centerIn:parent;text:"‹ Back";color:"white";font.pixelSize:17}
                    MouseArea{anchors.fill:parent;onClicked:{if(browser.location.length)browser.browse(browser.parentLocation);else browser.cancelRequested()}}
                }
                Text {Layout.fillWidth:true;text:browser.location.length?"Volumes  ›  "+browser.location.split("/").filter(function(p){return p.length}).join("  ›  "):"Drives, mounted volumes & Home";color:"#a9d6ef";font.pixelSize:17;wrapMode:Text.WrapAnywhere}
            }
            GridView {
                id:folders;Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:90;clip:true
                cellWidth:width/4;cellHeight:108;model:browser.entries;currentIndex:browser.selection
                onCurrentIndexChanged:positionViewAtIndex(currentIndex,GridView.Contain)
                delegate:Item {required property int index;required property var modelData;width:folders.cellWidth;height:folders.cellHeight
                    NeonPanel {anchors.fill:parent;anchors.margins:7;illuminated:browser.section==="locations"&&browser.selection===index
                        Column {anchors.fill:parent;anchors.margins:10;spacing:5
                            FolderIcon {kind:modelData.kind;tint:modelData.available?"#79d6ff":"#ffd45a"}
                            Text {width:parent.width;text:String(modelData.name);color:"white";font.pixelSize:16;wrapMode:Text.WrapAnywhere;maximumLineCount:2;elide:Text.ElideRight}
                        }
                        MouseArea {anchors.fill:parent;onClicked:{browser.selection=index;browser.browse(modelData.path)}}
                    }
                }
                Text {anchors.centerIn:parent;visible:!browser.entries.length;text:browser.location.length?"No subfolders. You can add this folder.":"No authorized volumes are available.";color:"#a8cadd";width:parent.width-24;wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter}
            }
            Text {Layout.fillWidth:true;wrapMode:Text.WordWrap;text:"Manual path · X opens the NeutronOS keyboard";color:"#a8cadd";font.pixelSize:16}
            TextField {id:manual;Layout.fillWidth:true;Layout.preferredHeight:46;color:"white";font.pixelSize:18;selectByMouse:true;placeholderText:"/NeutronOS/your-user/Games";placeholderTextColor:"#829eb7";onAccepted:browser.browse(text)
                background:Rectangle{radius:7;color:"#081627";border.color:browser.section==="manual"?"#79d6ff":"#294866";border.width:2}
                MouseArea {anchors.fill:parent;onClicked:{browser.section="manual";browser.keyboardRequested(manual)}}
            }
            Text {Layout.fillWidth:true;text:browser.errorText;color:"#ff6577";font.pixelSize:16;wrapMode:Text.WordWrap;visible:text.length>0}
            NeonPanel {Layout.fillWidth:true;Layout.preferredHeight:48;illuminated:browser.section==="save"
                Text {anchors.centerIn:parent;text:browser.editIndex>=0?"X  Use This Folder":"X  Add This Folder";color:browser.location.length?"white":"#829ab0";font.pixelSize:20}
                MouseArea {anchors.fill:parent;onClicked:browser.save()}
            }
            Text {Layout.fillWidth:true;text:"D-PAD  Navigate    X  Open / Select    O  Back    Back at Volumes cancels";color:"#829ab0";font.pixelSize:14;wrapMode:Text.WordWrap}
        }
    }
}
