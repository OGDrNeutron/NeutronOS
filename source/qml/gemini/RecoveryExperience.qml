import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
Item {
    id:root
    objectName:"GeminiRecoveryExperience"
    property var backend
    property url backdrop:"../../themes/Default/background.png"
    readonly property string view:backend?backend.view:"loading"
    readonly property bool landing:view==="landing"
    readonly property bool working:view==="progress"||view==="success"||view==="loading"
    readonly property bool browsing:view==="selection"||view==="manage"
    readonly property var selectedPoint:backend&&backend.recoveryPoints.length?backend.recoveryPoints[Math.max(0,Math.min(backend.selectedIndex,backend.recoveryPoints.length-1))]:({})
    property var actions:[
        {title:"Restore from Backup",detail:"Restore configuration and data from a verified backup.",icon:"▱",context:"Restore saved settings and user data from a verified backup. Your installed operating system stays in place."},
        {title:"Restore to Clean Image (Keep Data)",detail:"Requires a verified clean-install image.",icon:"↶",context:"Clean installation requires a verified full-install image and a Gemini reimage backend. A staged authenticated update can be applied in this session; backup restore does not reinstall the operating system."},
        {title:"Restore to Clean Image (Erase All)",detail:"Clean-image erase is unavailable in this Recovery session.",icon:"▥",context:"Disk erasure is unavailable in this recovery session. No disk is erased by selecting this menu action."},
        {title:"Manage Backups",detail:"View, verify, and delete protected backup archives.",icon:"▣",context:"Browse real backup metadata. X verifies the selected backup; Square arms deletion, and a second Square confirms. O cancels an armed action."},
        {title:"Advanced Tools",detail:"Review Recovery status and refresh verified backups.",icon:"⚙",context:"Review the actual recovery request, archive integrity, and transaction state. Disk repair and arbitrary commands are not exposed through this controller menu."},
        {title:"Exit to System",detail:"Reboot and continue to NeutronOS.",icon:"⏻",context:"Cancel the one-shot recovery request safely and reboot into the normal signed NeutronOS system. Verified backups are preserved."}
    ]
    function handle(action){return backend&&backend.handleAction(action)}
    function timestamp(value){var d=new Date(String(value||""));return isNaN(d.getTime())?"Not recorded":Qt.formatDateTime(d,"yyyy-MM-dd  HH:mm")}
    function bytes(value){var n=Number(value||0);return n>=1073741824?(n/1073741824).toFixed(2)+" GiB":n>=1048576?(n/1048576).toFixed(1)+" MiB":n.toLocaleString()+" bytes"}
    GeminiRenderQuality{id:renderQuality;active:root.visible}
    Image{anchors.fill:parent;source:root.backdrop;fillMode:Image.PreserveAspectCrop;opacity:.38}
    Rectangle{anchors.fill:parent;color:"#070019";opacity:.3}
    
    Item {
        id:layout;width:1672;height:941;anchors.centerIn:parent;scale:Math.min(root.width/width,root.height/height)
        // GPU platform and an independent live Atom define Recovery, not Setup.
        RecoveryStage{x:0;y:root.landing||root.working?690:790;width:1672;height:150;quality:renderQuality}
        Item {
            id:brand
            x:root.landing?565:root.working?625:65
            y:root.landing?510:root.working?400:16
            width:root.landing?560:root.working?440:460;height:140
            EnergyAtom{x:0;y:0;width:105;height:110;visible:!root.landing&&!root.working;quality:renderQuality}
            Column{x:root.landing||root.working?0:110;spacing:0
                Text{text:"Neutron<font color='#ff102f'>OS</font>";textFormat:Text.RichText;color:"#f7fbff";font.bold:true;font.pixelSize:root.landing?80:root.working?60:50}
                Text{text:"G E M I N I";color:"#00ffb5";font.bold:true;font.pixelSize:root.landing?48:38}
                Text{text:"R E C O V E R Y";color:"#c1ecff";font.pixelSize:root.landing?30:25}
            }
        }
        Text{x:72;y:141;width:1300;text:"System recovery and maintenance tools. Restore from backups or return to a clean image.";color:"#eef5ff";font.pixelSize:20;visible:!root.landing&&!root.working}
        EnergyHalo{quality:renderQuality;x:root.landing?365:root.working?460:935;y:root.landing?-40:root.working?-90:20;width:root.landing?940:root.working?760:630;height:width;animated:root.visible;opacity:.55}
        EnergyAtom{x:root.landing?510:root.working?600:1000;y:root.landing?12:root.working?-20:75;width:root.landing?650:root.working?480:500;height:width;quality:renderQuality;animated:root.visible}
        Rectangle {
            id:landingContinue;objectName:"RecoveryContinue"
            x:635;y:704;width:405;height:74;radius:37;visible:root.landing
            color:"#ec001407";border.color:"#37ff8e";border.width:3
            Rectangle{anchors.fill:parent;anchors.margins:-5;radius:42;color:"transparent";border.width:5;border.color:"#3537ff8e"}
            Rectangle{anchors.fill:parent;anchors.margins:-10;radius:47;color:"transparent";border.width:5;border.color:"#1637ff8e"}
            Text{anchors.centerIn:parent;text:"CONTINUE     ›";color:"#bdffde";font.bold:true;font.pixelSize:29}
            MouseArea{anchors.fill:parent;onClicked:root.handle("primary")}
        }
        Rectangle {
            x:65;y:173;width:795;height:622;radius:18;color:"#7e010815";border.color:"#153958";visible:root.view==="menu"
            Column {
                anchors.fill:parent;anchors.margins:15;spacing:10
                Repeater {
                    model:root.actions
                    Rectangle {
                        required property var modelData
                        required property int index
                        objectName:"RecoveryMenuAction"+index
                        width:760;height:91;radius:11
                        color:root.backend&&root.backend.menuIndex===index?"#c3041735":"#b7010710"
                        border.color:root.backend&&root.backend.menuIndex===index?"#72d9ff":"#276d91";border.width:root.backend&&root.backend.menuIndex===index?3:1
                        Rectangle{anchors.fill:parent;anchors.margins:-4;radius:15;color:"transparent";border.width:4;border.color:"#3350caff";visible:root.backend&&root.backend.menuIndex===index}
                        Rectangle{anchors.fill:parent;anchors.margins:-8;radius:19;color:"transparent";border.width:4;border.color:"#1450caff";visible:root.backend&&root.backend.menuIndex===index}
                        RecoveryGlyph{x:27;y:16;width:54;height:54;kind:index===0?"backup":index===1?"restore":index===2?"trash":index===3?"drive":index===4?"tools":"power";color:index===2?"#ff3546":"#b4dfff"}
                        Column{x:105;y:17;width:580;spacing:7
                            Text{text:modelData.title;color:"white";font.bold:true;font.pixelSize:23}
                            Text{text:modelData.detail;width:560;elide:Text.ElideRight;color:"#d5e3f4";font.pixelSize:18}
                        }
                        Text{x:710;y:21;text:"›";color:"white";font.pixelSize:42}
                        MouseArea{anchors.fill:parent;onClicked:{root.backend.selectIndex(index);root.handle("primary")}}
                    }
                }
            }
        }
        Rectangle {
            x:885;y:600;width:710;height:184;radius:13;visible:root.view==="menu"
            color:"#d5010916";border.color:"#208cb2"
            RecoveryGlyph{x:26;y:22;width:43;height:43;kind:"info";color:"#c7ecff"}
            Column{x:100;y:25;width:580;spacing:10
                Text{text:root.actions[root.backend?root.backend.menuIndex:0].title;color:"white";font.bold:true;font.pixelSize:23}
                Text{text:root.actions[root.backend?root.backend.menuIndex:0].context;width:570;color:"#dfebf7";font.pixelSize:19;wrapMode:Text.Wrap;lineHeight:1.2}
            }
        }
        Item {
            visible:root.browsing
            Text{x:72;y:188;text:root.view==="manage"?"Manage Backups":"Restore from Backup";color:"white";font.bold:true;font.pixelSize:35}
            Text{x:72;y:234;text:root.view==="manage"?"X verifies · Square arms deletion · O cancels":"Select a verified backup to restore configuration and data.";color:"#cce1f5";font.pixelSize:20}
            ListView {
                id:list;objectName:"RecoveryBackupList"
                x:78;y:276;width:744;height:503;spacing:9;clip:true
                model:root.backend?root.backend.recoveryPoints:[];currentIndex:root.backend?root.backend.selectedIndex:0
                delegate:Rectangle {
                    required property var modelData
                    required property int index
                    width:744;height:94;radius:12;color:index===list.currentIndex?"#dd051633":"#c0010914"
                    border.color:index===list.currentIndex?"#80dfff":"#285985";border.width:index===list.currentIndex?3:1
                    RecoveryGlyph{x:23;y:22;width:48;height:48;kind:"backup";color:"#b1dfff"}
                    Column{x:104;y:14;width:550;spacing:5
                        Text{text:String(modelData.name||modelData.version||"Recovery point");width:550;elide:Text.ElideMiddle;color:"white";font.bold:true;font.pixelSize:21}
                        Text{text:root.timestamp(modelData.createdUtc||modelData.modified)+"     "+root.bytes(modelData.size);color:"#cee4f9";font.pixelSize:18}
                        Text{text:String(modelData.profile||"Verified backup")+" · "+(modelData.verified?"Verified":"Unavailable");color:"#9bbfdb";font.pixelSize:16}
                    }
                    MouseArea{anchors.fill:parent;onClicked:root.backend.selectIndex(index)}
                }
            }
            Text{x:100;y:330;visible:list.count===0;width:650;wrapMode:Text.Wrap;text:"No verified backup is available. O returns to Recovery menu.";font.pixelSize:24;color:"#ccdeef"}
            Rectangle {
                objectName:"RecoveryBackupDetails"
                x:844;y:504;width:755;height:278;radius:15;color:"#df020917";border.color:"#2c759d"
                Column{x:30;y:24;width:690;spacing:12
                    Text{text:"Backup Details";font.bold:true;font.pixelSize:24;color:"white"}
                    Text{text:"Name    "+String(root.selectedPoint.name||root.selectedPoint.version||"Unavailable");width:690;elide:Text.ElideMiddle;font.pixelSize:20;color:"#f0f5fc"}
                    Text{text:"Date      "+root.timestamp(root.selectedPoint.createdUtc||root.selectedPoint.modified);font.pixelSize:19;color:"#d2dfed"}
                    Text{text:"Type      "+String(root.selectedPoint.profile||"Not recorded")+"     Size  "+root.bytes(root.selectedPoint.size);font.pixelSize:19;color:"#d2dfed"}
                    Text{text:"SHA256  "+String(root.selectedPoint.sha256||"Not recorded");width:690;elide:Text.ElideMiddle;font.pixelSize:16;color:"#a9c5de"}
                    Text{text:root.backend&&root.backend.armed?root.backend.message:"Restores saved settings and user data. Your installed operating system stays in place.";width:690;wrapMode:Text.Wrap;font.pixelSize:18;color:root.backend&&root.backend.armed?"#ffca54":"#b7d2e9"}
                }
            }
        }
        Rectangle {
            id:progressPanel;objectName:"RecoveryProgressPanel"
            x:337;y:565;width:1000;height:300;radius:21;visible:root.working
            color:"#ed010817";border.color:"#2778d6";border.width:2
            RecoveryGlyph{x:42;y:34;width:70;height:70;kind:"backup";color:"#afdaff"}
            Column{x:156;y:29;width:565;spacing:8
                Text{text:root.backend?root.backend.title:"Preparing Recovery";font.bold:true;font.pixelSize:30;color:"white"}
                Text{text:String(root.selectedPoint.name||root.selectedPoint.version||"Authenticated Recovery");width:560;elide:Text.ElideMiddle;font.pixelSize:21;color:"#cce4f7"}
                Text{text:root.timestamp(root.selectedPoint.createdUtc||root.selectedPoint.modified)+"  ·  "+root.bytes(root.selectedPoint.size);font.pixelSize:20;color:"#b1c9df";visible:root.view!=="loading"}
            }
            Text{x:810;y:32;text:root.backend&&root.backend.progress>=0?root.backend.progress+"%":"…";font.pixelSize:44;font.bold:true;color:"#00ffb1"}
            Text{x:156;y:132;width:780;text:root.backend?root.backend.message:"Loading verified recovery catalog…";elide:Text.ElideRight;font.pixelSize:21;color:"#c5e7ff"}
            Rectangle{x:40;y:170;width:920;height:26;radius:13;color:"#021b25";border.color:"#007a6e"
                Rectangle{width:parent.width*Math.max(0,root.backend?root.backend.progress:0)/100;height:parent.height;radius:13;color:"#00f596"}
            }
            Row{x:48;y:222;spacing:10
                Repeater {
                    model:["Verifying Backup","Preparing Restore","Restoring Configuration/Data","Finalizing"]
                    Item {
                        required property string modelData
                        required property int index
                        width:218;height:62
                        property int stage:root.backend&&root.backend.progress>=94?3:root.backend&&root.backend.progress>=55?2:root.backend&&root.backend.progress>=28?1:0
                        Rectangle{x:95;width:28;height:28;radius:14;color:index<parent.stage?"#00ff91":"#020c18";border.color:index<=parent.stage?"#00ff91":"#6b9abb";border.width:2}
                        Text{y:40;width:218;text:modelData;horizontalAlignment:Text.AlignHCenter;font.pixelSize:15;color:index<=parent.stage?"#eafff8":"#8ea9c3"}
                    }
                }
            }
        }
        Rectangle {
            x:330;y:250;width:1010;height:430;radius:20;visible:root.view==="failure"||root.view==="tools"||root.view==="unavailable"
            color:"#ed010817";border.color:root.view==="failure"?"#ff3145":"#2778d6"
            Column{anchors.fill:parent;anchors.margins:32;spacing:20
                Text{text:root.view==="failure"?"RECOVERY FAILED":root.view==="tools"?"Advanced Tools":root.actions[root.backend?root.backend.menuIndex:0].title;wrapMode:Text.Wrap;width:940;color:root.view==="failure"?"#ff4059":"white";font.bold:true;font.pixelSize:34}
                Text{text:root.view==="tools"?"Authenticated mode: "+String(root.backend.context.mode||"Unknown")+"\nVerified catalog: "+root.backend.recoveryPoints.length+" points\nRequest: "+String(root.backend.context.reason||"Not recorded")+"\nX refreshes and revalidates the catalog. O returns to menu.":root.backend?root.backend.message:"";wrapMode:Text.Wrap;width:940;color:"#d3e7f9";font.pixelSize:23;lineHeight:1.3}
                Repeater{model:root.view==="failure"?["Refresh / Retry","Return to Recovery","Reboot Without Restoring"]:[]
                    Text{required property string modelData;required property int index;text:(root.backend&&root.backend.failureOption===index?"›  ":"   ")+modelData;font.pixelSize:22;color:root.backend&&root.backend.failureOption===index?"#03d4ff":"#b8d2eb"}
                }
            }
        }
        Rectangle {
            x:625;y:807;width:420;height:74;radius:37;visible:!root.landing&&!root.working&&root.view!=="failure"&&root.view!=="tools"&&root.view!=="unavailable"
            color:"#eb001107";border.color:"#41ff9a";border.width:3
            Rectangle{anchors.fill:parent;anchors.margins:-5;radius:42;color:"transparent";border.width:5;border.color:"#3541ff9a"}
            Rectangle{anchors.fill:parent;anchors.margins:-10;radius:47;color:"transparent";border.width:5;border.color:"#1641ff9a"}
            Column{anchors.centerIn:parent;spacing:1
                Text{anchors.horizontalCenter:parent.horizontalCenter;text:root.browsing?(root.view==="manage"?"VERIFY BACKUP":root.backend.armed?"CONFIRM RESTORE":"RESTORE BACKUP"):"SELECT    ›";font.bold:true;font.pixelSize:26;color:"#f2fff7"}
                Text{anchors.horizontalCenter:parent.horizontalCenter;text:"PRESS X";font.bold:true;font.pixelSize:19;color:"#00ffb5"}
            }
            MouseArea{anchors.fill:parent;onClicked:root.handle("primary")}
        }
        Rectangle{x:65;y:850;width:195;height:62;radius:31;visible:!root.landing&&!root.working;color:"#dd020a16";border.color:"#245575"
            Text{anchors.centerIn:parent;text:"✥  Navigate";color:"#e4f0ff";font.pixelSize:19}
        }
        Rectangle{x:1485;y:850;width:135;height:62;radius:31;visible:!root.landing&&!root.working;color:"#dd020a16";border.color:"#245575"
            Text{anchors.centerIn:parent;text:"○  Back";color:"#e4f0ff";font.pixelSize:19}
        }
    }
}
