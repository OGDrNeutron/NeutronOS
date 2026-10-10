import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Shapes

Item {
    id:root
    FontLoader{id:bodyTypeface;source:"assets/fonts/Montserrat-Regular.ttf"}
    FontLoader{id:boldTypeface;source:"assets/fonts/Montserrat-Bold.ttf"}
    FontLoader{id:identityTypeface;source:"assets/fonts/Orbitron-Bold.ttf"}
    readonly property string bodyFont:bodyTypeface.name
    required property var wizard
    property var quality:null
    readonly property var w:wizard
    readonly property var network:typeof networkManager!=="undefined"?networkManager:null
    readonly property var clock:typeof clockSettingsManager!=="undefined"?clockSettingsManager:null
    readonly property var core:typeof securityCoreManager!=="undefined"?securityCoreManager:null
    readonly property var controller:typeof controllerManager!=="undefined"?controllerManager:null
    readonly property var ssids:network?network.availableNetworks:[]
    readonly property var chosenNetwork:w.selectedWifi && w.selectedWifi.ssid?w.selectedWifi:ssids.length?ssids[Math.min(w.selectedIndex,ssids.length-1)]:({})
    property date now:new Date()
    function title(){return ["Welcome To NeutronOS","Time Zone","Network Setup","Controller Pairing","User Account & Controller Passcode","Storage","Recovery","Security Configuration","Initial Experience","NeutronOS is Ready"][w.stepIndex]}
    function wifiFrequency(network) {
        if(network.frequencyText)return String(network.frequencyText)
        var mhz=Number(network.frequencyMhz||network.frequency)
        if(isFinite(mhz)&&mhz>0)return (mhz/1000).toFixed(1)+" GHz"
        return String(network.band||"—")
    }
    function controllerName(){return String(w.bluetoothCandidate.name||(controller?controller.controllerName:"")||"Controller")}
    function selectRow(index){w.selectedIndex=index;w.handleControllerPressed("primary")}
    function currentTime(){var tick=root.now;return clock?clock.formattedTimeForZone(w.timezone,false):Qt.formatTime(root.now,"h:mm AP")}
    function currentDate(){var tick=root.now;return clock?clock.formattedDateForZone(w.timezone):Qt.formatDate(root.now,"dddd, MMMM d, yyyy")}
    Timer {interval:1000;running:root.visible&&w.stepIndex===1;repeat:true;onTriggered:root.now=new Date()}
    Rectangle {anchors.fill:parent;color:"#01040B"}
    Item {
        id:canvas
        width:1672;height:941;anchors.centerIn:parent
        scale:Math.min(root.width/width,root.height/height)
        Rectangle {anchors.fill:parent;gradient:Gradient{GradientStop{position:0;color:"#01030B"}GradientStop{position:0.65;color:"#010819"}GradientStop{position:1;color:"#00142D"}}}
        SetupAtmosphere {x:0;y:0;width:1672;height:790;strength:w.stepIndex===0?0.7:1;readyScene:w.stepIndex===9?1:0}
        Image {x:0;y:w.stepIndex===9?810:818;width:1672;height:123;source:w.stepIndex===9?"assets/ready-floor.png":"assets/floor.png";fillMode:Image.Stretch}
        Rectangle {x:0;y:810;width:1672;height:80;gradient:Gradient{GradientStop{position:0;color:"#010715"}GradientStop{position:1;color:"transparent"}}}
        Loader {x:54;y:13;width:110;height:100;active:w.stepIndex>0&&w.stepIndex<9;sourceComponent:Component{NeutronAtom{quality:root.quality;animated:!w.fractureActive}}}
        Column {x:w.stepIndex===9?674:174;y:w.stepIndex===9?31:30;visible:w.stepIndex!==0;spacing:0
            Row {spacing:0
                Text{text:"Neutron";color:"white";font.family:root.bodyFont;font.pixelSize:w.stepIndex===9?50:38;font.weight:Font.Bold}
                Text{text:"OS";color:"#FC0027";font.family:root.bodyFont;font.pixelSize:w.stepIndex===9?50:38;font.weight:Font.Bold}
            }
            Text {text:"GEMINI";color:"#00FF68";font.family:"Orbitron";font.pixelSize:w.stepIndex===9?50:28;font.weight:Font.Bold;font.letterSpacing:2}
        }
        Text {visible:w.stepIndex>0&&w.stepIndex<9;x:w.stepIndex===7?75:94;y:w.stepIndex===1?163:w.stepIndex===8?80:137;width:w.stepIndex===8?1480:1490;height:82;text:root.title();color:"#FBFCFF";font.family:root.bodyFont;font.pixelSize:w.stepIndex===1?70:w.stepIndex===4?55:w.stepIndex===7?56:60;font.weight:Font.Bold;horizontalAlignment:w.stepIndex===8?Text.AlignHCenter:Text.AlignLeft}
        Loader {
            id:page
            objectName:"setupPageSurface"
            anchors.fill:parent
            sourceComponent:[welcome,timezone,networkPage,controllerPage,account,storage,recovery,security,experience,ready][w.stepIndex]
            onLoaded:{opacity=0;enter.restart()}
        }
        NumberAnimation {id:enter;target:page;property:"opacity";to:1;duration:150}
        Text {x:70;y:912;width:1532;visible:w.stepIndex>0&&w.stepIndex<9;text:w.comboRecording?"D-PAD / BUTTONS  PASSCODE     OPTIONS  FINISH     O  CANCEL":"D-PAD  NAVIGATE      X  SELECT      O  BACK"+([2,6].indexOf(w.stepIndex)>=0?"      □  SKIP":"")+(w.stepIndex===1?"      △  LOCALE / KEYBOARD":w.stepIndex===8?"      △  MORE PREFERENCES":"");color:"#96B3D4";font.family:root.bodyFont;font.pixelSize:15;font.letterSpacing:1;horizontalAlignment:Text.AlignHCenter}
        SetupPanel {visible:w.pickerOpen;x:92;y:312;width:622;height:411;z:20
            ListView {id:regionList;anchors.fill:parent;anchors.margins:12;clip:true;model:w.pickerEntries;currentIndex:w.pickerIndex;onCurrentIndexChanged:positionViewAtIndex(currentIndex,ListView.Contain)
                delegate:SetupField {required property int index;required property var modelData;width:regionList.width;height:56;selected:index===w.pickerIndex;text:String(modelData.name||modelData.label||modelData.id);chevron:false;onActivated:{w.pickerIndex=index;w.selectRegionEntry()}}
            }
        }
        SetupPanel {visible:w.avatarPickerOpen;x:480;y:270;width:712;height:465;z:25
            Text{x:25;y:20;text:"CHOOSE YOUR ICON";color:"white";font.family:root.bodyFont;font.pixelSize:28;font.weight:Font.Bold}
            GridView {id:avatars;x:22;y:76;width:668;height:360;clip:true;cellWidth:132;cellHeight:120;model:typeof userManager!=="undefined"?userManager.availableAvatars:[];currentIndex:w.avatarPickerIndex;onCurrentIndexChanged:positionViewAtIndex(currentIndex,GridView.Contain)
                delegate:Rectangle {required property int index;required property var modelData;width:122;height:110;radius:12;color:"#0A182A";border.color:index===w.avatarPickerIndex?"#2DFF80":"#23466C";border.width:index===w.avatarPickerIndex?2:1
                    Image{x:18;y:8;width:86;height:78;source:modelData.resolvedSource||modelData.source;fillMode:Image.PreserveAspectFit}
                    Text{x:4;y:87;width:114;text:modelData.label||modelData.name;color:"white";font.family:root.bodyFont;font.pixelSize:12;elide:Text.ElideRight;horizontalAlignment:Text.AlignHCenter}
                    MouseArea{anchors.fill:parent;onClicked:{w.avatarPickerIndex=index;w.selectAvatar()}}
                }
            }
        }
        SetupPanel {visible:w.localePanelOpen;x:95;y:470;width:619;height:210;z:21
            Text{x:22;y:14;text:"LOCALE & KEYBOARD";color:"white";font.family:root.bodyFont;font.pixelSize:20;font.weight:Font.Bold}
            SetupField{x:16;y:55;width:587;height:60;text:"Locale: "+w.localeName;selected:w.localePanelIndex===0;chevron:false;onActivated:{w.localePanelIndex=0;w.openKeyboard("locale",false)}}
            SetupField{x:16;y:130;width:587;height:60;text:"Keyboard: "+w.keyboardLayout;selected:w.localePanelIndex===1;chevron:false;onActivated:{w.localePanelIndex=1;w.openKeyboard("keyboard",false)}}
        }
    }
    Component {
        id:welcome
        Item {
            EnergyAtom {x:516;y:15;width:640;height:540;quality:root.quality;animated:root.visible&&!w.fractureActive}
            Text {x:100;y:555;width:1472;textFormat:Text.RichText;text:"Welcome To Neutron<span style='color:#FF002B'>OS</span>";color:"white";font.family:root.bodyFont;font.pixelSize:78;font.weight:Font.Bold;horizontalAlignment:Text.AlignHCenter}
            Text {x:100;y:647;width:1472;text:"GEMINI";color:"#06FF70";font.family:"Orbitron";font.pixelSize:65;font.weight:Font.Bold;font.letterSpacing:3;horizontalAlignment:Text.AlignHCenter}
            SetupAction {x:594;y:749;width:485;height:87;text:"PRESS X TO BEGIN";hint:"";chevron:false;onActivated:w.handleControllerPressed("primary")}
        }
    }
    Component {
        id:timezone
        Item {
            Text {x:96;y:245;width:645;text:"Set your time zone to ensure accurate time, networking,\nsecurity logs, and system services.";color:"#CCE1FF";font.family:root.bodyFont;font.pixelSize:24;lineHeight:1.5}
            Repeater {model:[{label:"REGION",value:w.regionLabel,icon:"globe"},{label:"COUNTRY",value:w.countryLabel==="USA"?"United States":w.countryLabel,icon:"flag"},{label:"TIME ZONE",value:w.timezone==="America/New_York"?"Eastern Time (New York)":w.timezone==="Europe/Berlin"?"Central European Time (Berlin)":w.timezoneLabel,icon:"clock"}]
                delegate:Item {required property int index;required property var modelData;x:94;y:325+109*index;width:618;height:97
                    Text {y:0;text:modelData.label;color:"#9BACCE";font.family:root.bodyFont;font.pixelSize:15;font.weight:Font.Bold;font.letterSpacing:1}
                    SetupField {y:30;width:618;height:69;text:modelData.value;iconKind:modelData.icon;selected:w.selectedIndex===index;onActivated:root.selectRow(index)}
                }
            }
            TimezoneEarth {x:705;y:118;width:650;height:650;region:w.regionLabel;quality:root.quality;animated:!w.fractureActive}
            SetupPanel {x:1368;y:298;width:248;height:255
                Text{x:0;y:24;width:248;text:"CURRENT TIME";color:"#C6DBF7";font.family:root.bodyFont;font.pixelSize:17;font.weight:Font.Bold;horizontalAlignment:Text.AlignHCenter}
                Text{x:12;y:67;width:224;text:root.currentTime();color:"white";font.family:root.bodyFont;font.pixelSize:35;font.weight:Font.Bold;horizontalAlignment:Text.AlignHCenter;fontSizeMode:Text.Fit;minimumPixelSize:26}
                Text{x:14;y:126;width:220;text:root.currentDate();color:"#A6C4E9";font.family:root.bodyFont;font.pixelSize:16;wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter}
                Rectangle{x:22;y:173;width:204;height:1;color:"#273F68"}
                Text{x:18;y:192;width:212;text:w.timezone.replace(/_/g," ");color:"#C9E0FF";font.family:root.bodyFont;font.pixelSize:16;horizontalAlignment:Text.AlignHCenter;elide:Text.ElideRight}
            }
            SetupAction {x:623;y:735;width:426;height:88;onActivated:w.continueRegion()}
        }
    }
    Component {
        id:networkPage
        Item {
            Text{x:96;y:204;text:"Connect to a Wi-Fi network to access the internet, download updates,\nand enable online services.";color:"#CAE0FA";font.family:root.bodyFont;font.pixelSize:24}
            Text{x:103;y:270;text:root.network&&root.network.scanning?"SCANNING…":"AVAILABLE NETWORKS";color:"#91ACCD";font.family:root.bodyFont;font.pixelSize:16;font.weight:Font.Bold;font.letterSpacing:1}
            ListView {id:wifiList;x:101;y:302;width:650;height:423;clip:true;spacing:5;model:root.ssids;currentIndex:Math.min(w.selectedIndex,count-1);onCurrentIndexChanged:positionViewAtIndex(currentIndex,ListView.Contain)
                footer:SetupField{width:650;height:56;text:"Other Network (Hidden SSID)";strongText:false;textSize:23;selected:w.selectedIndex===wifiList.count;chevronText:"›";onActivated:w.openHiddenWifi()}
                delegate:SetupField {required property int index;required property var modelData;width:650;height:56;selected:w.selectedIndex===index&&!w.wifiModalOpen;text:String(modelData.ssid);chevron:false
                    SetupGlyph{x:510;y:16;width:24;height:24;kind:"lock";visible:String(modelData.security||"Open").toLowerCase().indexOf("open")<0;color:"white"}
                    SetupSignal{x:596;y:11;width:39;height:31;scale:0.78;strength:modelData.signalPercent||0}
                    onActivated:root.selectRow(index)
                }
            }
            Text{x:109;y:457;width:610;visible:!root.ssids.length;text:root.network&&root.network.available?"No networks found. Press Triangle to scan again.\nSquare skips network setup.":"No Wi-Fi adapter is available.\nSquare skips network setup.";color:"#91AACA";font.family:root.bodyFont;font.pixelSize:23;wrapMode:Text.WordWrap}
            SetupPanel {x:855;y:238;width:714;height:461
                Text{x:31;y:24;width:650;text:String(root.chosenNetwork.ssid||"Wi-Fi");color:"white";font.family:root.bodyFont;font.pixelSize:36;font.weight:Font.Bold;elide:Text.ElideRight}
                SetupGlyph{x:32;y:77;width:25;height:25;kind:"lock";color:"#12FF6B"}
                Text{x:75;y:79;width:607;text:w.wifiConnecting?w.wifiConnectionState:root.network&&root.network.connectionState==="CONNECTED"&&root.network.connectedSsid===root.chosenNetwork.ssid?"Connected":String(root.chosenNetwork.security||"Open").toLowerCase().indexOf("open")>=0?"Open network":"Secured";color:"#DFEDF9";font.family:root.bodyFont;font.pixelSize:21;elide:Text.ElideRight}
                Rectangle{x:36;y:117;width:640;height:1;color:"#245078"}
                Repeater{model:[{label:"Signal Strength",value:""},{label:"Security",value:String(root.chosenNetwork.security||"—")},{label:"Frequency",value:root.wifiFrequency(root.chosenNetwork)}]
                    Item{required property int index;required property var modelData;x:36;y:145+38*index
                        Text{text:modelData.label;color:"#B3E1FC";font.family:root.bodyFont;font.pixelSize:22}
                        Text{objectName:index===2?"setupWifiFrequency":"";x:356;text:modelData.value;color:"white";font.family:root.bodyFont;font.pixelSize:22}
                        SetupSignal{x:356;y:-5;visible:index===0;strength:root.chosenNetwork.signalPercent||0}
                    }
                }
                Rectangle{x:36;y:263;width:640;height:1;color:"#245078"}
                Text{x:36;y:285;text:"Enter Wi-Fi Password";color:"#B5E5FF";font.family:root.bodyFont;font.pixelSize:21}
                SetupField{x:36;y:317;width:640;height:58;iconKind:"lock";strongText:false;text:w.wifiPassword.length?(w.wifiPasswordVisible?w.wifiPassword:"••••••••"):"Enter password…";selected:w.wifiModalOpen&&w.wifiModalIndex===0;focusColor:"#00B9FF";chevron:false;textSize:22;onActivated:w.openKeyboard("wifiPassword",true)}
                SetupGlyph{x:602;y:332;width:29;height:29;kind:"eye";color:"white";MouseArea{anchors.fill:parent;onClicked:w.wifiPasswordVisible=!w.wifiPasswordVisible}}
                SetupField{x:36;y:389;width:310;height:52;text:(w.wifiPasswordVisible?"☑":"□")+"  Show Password";textSize:20;chevron:false;selected:w.wifiModalOpen&&w.wifiModalIndex===1;onActivated:{w.wifiModalIndex=1;w.wifiPasswordVisible=!w.wifiPasswordVisible}}

            }
            SetupAction {x:599;y:739;width:451;height:85;selected:w.wifiModalOpen&&(w.wifiModalIndex===2||w.wifiModalIndex===3);text:w.wifiConnecting?"CONNECTING…":root.network&&root.network.connectionState==="CONNECTED"?"CONTINUE":"CONNECT";enabled:!w.wifiConnecting
                onActivated:{if(root.network&&root.network.connectionState==="CONNECTED"){w.wifiModalOpen=false;if(w.recordOptional("network",false))w.setStep(3)}else {if(!w.wifiModalOpen)w.openWifiConnection(root.chosenNetwork);w.connectSelectedWifi()}}
            }
        }
    }
    Component {
        id:controllerPage
        Item {
            Text{x:102;y:219;width:722;text:"Connect and pair your controller via Bluetooth for a wireless\nexperience. Your controller will be remembered for this device.";color:"#C8E9F7";font.family:root.bodyFont;font.pixelSize:23;lineHeight:1.4}
            Text{x:107;y:306;text:"CONNECTED CONTROLLER";color:"#A2DDFF";font.family:root.bodyFont;font.pixelSize:19;font.letterSpacing:1.5}
            SetupField{x:90;y:335;width:720;height:85;text:root.controllerName();iconKind:"controller";selected:true;chevron:true;chevronText:"›";textSize:25;onActivated:w.handleControllerPressed("primary")}
            SetupPanel{x:846;y:237;width:751;height:479;border.color:"#008FFF";radius:20
                Text{x:37;y:30;width:677;text:root.controllerName();color:"white";font.family:root.bodyFont;font.pixelSize:38;font.weight:Font.Bold;elide:Text.ElideRight}
                Text{x:37;y:91;width:677;text:String(w.bluetoothCandidate.manufacturer||"Bluetooth controller");color:"#ABD8F6";font.family:root.bodyFont;font.pixelSize:23;elide:Text.ElideRight}
                Rectangle{x:37;y:138;width:674;height:1;color:"#29527F"}
                Repeater{model:[{label:"Connection Type",value:w.controllerRegistration.verified?"Bluetooth (Wireless)":w.controllerRegistration.connectionLabel},{label:"Bluetooth Address",value:String(w.bluetoothCandidate.address||root.controller&&root.controller.controllerAddress||"—")},{label:"Status",value:({wired:"Wired",waiting_disconnect:"Waiting for disconnect",scanning:"Scanning",registering:"Reading USB identity",bonding:"Pairing",trusting:"Trusting",connecting:"Connecting",connected:"Connected",error:"Failure"})[w.controllerRegistration.phase]||"Ready to pair"}]
                    Item{required property int index;required property var modelData;x:37;y:163+40*index
                        Text{text:modelData.label;color:"#C4EDFC";font.family:root.bodyFont;font.pixelSize:22}
                        Text{x:376;width:300;text:modelData.value;color:index===2?(w.bluetoothStage===3?"#00FF65":"#FF1639"):"white";font.family:root.bodyFont;font.pixelSize:22;font.weight:index===2?Font.Bold:Font.Normal;elide:Text.ElideRight}
                    }
                }
                Rectangle{x:37;y:287;width:674;height:1;color:"#29527F"}
                Repeater{model:["Paired","Connected","Trusted"]
                    Item{required property int index;required property var modelData;x:61+239*index;y:310
                        Text{text:modelData+":";color:"#BEE9F8";font.family:root.bodyFont;font.pixelSize:21}
                        Text{x:index===0?94:index===1?133:102;text:w.bluetoothCandidate[String(modelData).toLowerCase()]===true?"Yes":"No";color:w.bluetoothStage===3?"#0AFF65":"#FF1234";font.family:root.bodyFont;font.pixelSize:21;font.weight:Font.Bold}
                        Rectangle{x:178;y:0;width:1;height:28;color:"#244E79";visible:index<2}
                    }
                }
                Rectangle{x:37;y:357;width:674;height:1;color:"#29527F"}
                Rectangle{x:146;y:375;width:50;height:50;radius:25;color:"#002C12";border.color:"#80FF98";border.width:3;visible:w.bluetoothStage===3;Text{anchors.centerIn:parent;text:"✓";color:"#86FF9E";font.pixelSize:36}}
                Text{x:w.bluetoothStage===3?216:50;y:w.bluetoothStage===3?380:383;width:w.bluetoothStage===3?489:653;text:w.controllerRegistration.verified?"Controller paired successfully":w.controllerRegistration.instructions;wrapMode:Text.WordWrap;color:w.bluetoothStage===3?"#54FF8E":"#C7EDFA";font.family:root.bodyFont;font.pixelSize:w.bluetoothStage===3?27:21;font.weight:w.bluetoothStage===3?Font.Bold:Font.Normal;horizontalAlignment:w.bluetoothStage===3?Text.AlignLeft:Text.AlignHCenter}
                Text{x:50;y:433;width:653;text:w.controllerRegistration.verified?"Your controller is paired, connected, and trusted for this device.":"USB identity → unplug → scan exact controller → pair → verify Bluetooth";color:"#C8EEF8";font.family:root.bodyFont;font.pixelSize:18;horizontalAlignment:Text.AlignHCenter}
            }
            SetupAction{x:w.bluetoothStage===3?613:599;y:749;width:w.bluetoothStage===3?447:479;height:98;text:w.bluetoothStage===3?"CONTINUE":"PAIR CONTROLLER";onActivated:w.handleControllerPressed("primary")}
        }
    }
    Component {
        id:account
        Item {
            Text{x:104;y:222;text:"Create your account and set a controller passcode to sign in.";color:"#CEE2FB";font.family:root.bodyFont;font.pixelSize:23}
            SetupIllustration{x:70;y:280;width:542;height:356;source:"assets/account-illustration.png";fillMode:Image.Stretch}
            Image{x:187;y:305;width:310;height:310;visible:w.selectedAvatar.length>0;source:typeof userManager!=="undefined"?userManager.resolveAvatarSource(w.selectedAvatar):"";fillMode:Image.PreserveAspectFit}
            SetupField{x:211;y:650;width:275;height:54;text:"CHANGE ICON";selected:w.accountIconFocused;chevron:false;textSize:19;onActivated:w.openAvatarPicker()}
            Text{x:94;y:720;width:476;text:"YOUR IDENTITY. YOUR UNIVERSE.";color:"#B0D1F4";font.family:root.bodyFont;font.pixelSize:22;horizontalAlignment:Text.AlignHCenter}
            SetupPanel{x:650;y:244;width:962;height:510
                Repeater {model:[{label:"Hostname",field:0,value:w.hostname,help:"Name of your PC",icon:"display"},{label:"Username",field:1,value:w.username||"Create username",help:"Your Linux account",icon:"user"},{label:"Display Name",field:2,value:w.displayName||"Your display name",help:"Shown in NeutronOS",icon:"user"},{label:"Password",field:3,value:w.accountPassword.length?(w.passwordVisible?w.accountPassword:"••••••••"):"Enter password",help:"At least 8 characters",icon:"lock"},{label:"Confirm Password",field:4,value:w.confirmPassword.length?(w.passwordVisible?w.confirmPassword:"••••••••"):"Repeat password",help:"Must match password",icon:"lock"},{label:"Controller Passcode",field:5,value:w.comboConfigured&&!w.comboRecording?"••••••":w.comboStatus,help:"4–10 controller inputs",icon:"controller"}]
                    Item {required property int index;required property var modelData;x:20;y:18+81*index;width:920;height:63
                        SetupGlyph{x:4;y:12;kind:modelData.icon}
                        Text{x:62;y:18;width:229;text:modelData.label;color:"#D8E8FC";font.family:root.bodyFont;font.pixelSize:21;font.weight:Font.Bold}
                        SetupField{x:297;y:3;width:384;height:56;text:modelData.value;textSize:20;selected:!w.accountIconFocused&&w.selectedIndex===modelData.field;chevron:false;onActivated:w.activateAccountField(modelData.field)}
                        SetupGlyph{x:635;y:17;width:28;height:28;kind:"eye";color:"white";visible:modelData.field===3||modelData.field===4;MouseArea{anchors.fill:parent;onClicked:w.passwordVisible=!w.passwordVisible}}
                        Rectangle{x:4;y:72;width:912;height:1;color:"#1D3550";visible:index<5}
                        Text{x:707;y:16;width:205;text:modelData.help;color:"#B8CEE8";font.family:root.bodyFont;font.pixelSize:16;wrapMode:Text.WordWrap}
                    }
                }
            }
            Row{x:955;y:765;spacing:9
                Text{text:"Press";color:"#C6DAF5";font.family:root.bodyFont;font.pixelSize:17}
                Rectangle{width:20;height:20;radius:3;color:"transparent";border.color:"#F2B9FA";border.width:2}
                Text{text:"to "+(w.passwordVisible?"Hide":"Show")+" Password";color:"#C6DAF5";font.family:root.bodyFont;font.pixelSize:17}
            }

            SetupAction{x:620;y:801;width:430;height:81;selected:!w.accountIconFocused&&w.selectedIndex===6;onActivated:w.continueAccount()}
        }
    }
    Component {
        id:storage
        Item {
            Text{x:104;y:210;width:538;text:"This device is partitioned for NeutronOS. The system\npartition is pre-configured and you can allocate the remaining\nspace for user data.";wrapMode:Text.WordWrap;color:"#D9EBF7";font.family:root.bodyFont;font.pixelSize:20;lineHeight:1.4}
            SetupIllustration{x:65;y:300;width:555;height:410;source:"assets/storage-illustration.png"}
            Text{x:93;y:727;width:478;text:"FAST. SECURE. EXPANDABLE.";color:"#DCEBF8";font.family:root.bodyFont;font.pixelSize:16;font.letterSpacing:6;horizontalAlignment:Text.AlignHCenter}
            SetupPanel{x:681;y:139;width:931;height:603;border.color:"#00CFFF";radius:18
                SetupGlyph{x:31;y:31;width:64;height:64;kind:"storage";color:"white"}
                Rectangle{x:112;y:33;width:1;height:58;color:"#1C344F"}
                Text{x:130;y:26;text:"Internal Storage";color:"white";font.family:root.bodyFont;font.pixelSize:31;font.weight:Font.Bold}
                Text{x:130;y:72;text:"Total Capacity: "+w.storageSize(w.storagePlan.diskBytes);color:"#B9EBF7";font.family:root.bodyFont;font.pixelSize:21}
                Text{x:570;y:20;width:334;text:w.storageSize(w.storagePlan.availableBytes);color:"#20FF72";font.family:root.bodyFont;font.pixelSize:44;font.weight:Font.Bold;horizontalAlignment:Text.AlignRight}
                Text{x:570;y:76;width:334;text:"Available for User Data";color:"#C9F3FF";font.family:root.bodyFont;font.pixelSize:20;horizontalAlignment:Text.AlignRight}
                Rectangle{x:21;y:120;width:887;height:1;color:"#254F73"}
                Repeater{model:[{name:"Boot Partition",color:"#FF002B",bytes:Number(w.storagePlan.boot?w.storagePlan.boot.sectors:0)*512,detail:"System boot files\n(read-only)"},{name:"System Partition",color:"#0088FF",bytes:w.storagePlan.systemBytes,detail:"NeutronOS core files\n(read-only)"},{name:"User Data Partition",color:"#00ED62",bytes:w.storagePlan.availableBytes,detail:"Your files, apps, media,\nand personal data\n(read/write)"}]
                    Item{required property int index;required property var modelData;x:27+303*index;y:149;width:288;height:151
                        Rectangle{width:44;height:44;radius:9;color:modelData.color}
                        Text{x:65;y:2;text:modelData.name;color:"white";font.family:root.bodyFont;font.pixelSize:21;font.weight:Font.Bold}
                        Text{x:65;y:35;text:w.storageSize(modelData.bytes);color:"white";font.family:root.bodyFont;font.pixelSize:21;font.weight:Font.Bold}
                        Text{x:65;y:70;width:221;text:modelData.detail;color:"#C5EDF6";font.family:root.bodyFont;font.pixelSize:19;lineHeight:1.4}
                        Rectangle{x:264;width:1;height:142;color:"#254F73";visible:index<2}
                    }
                }
                Rectangle{x:21;y:309;width:887;height:1;color:"#254F73"}
                SetupPanel{x:21;y:330;width:887;height:250;radius:15
                    SetupGlyph{x:18;y:21;width:63;height:63;kind:"storage";color:"white"}
                    Text{x:108;y:16;text:String(w.storagePlan.status||"")==="existing"?"User Data Partition Ready":"Create User Data Partition";color:"white";font.family:root.bodyFont;font.pixelSize:27;font.weight:Font.Bold}
                    Text{x:108;y:56;width:757;text:"Allocate the remaining space for your personal files, apps, and media.";color:"#C7EBFA";font.family:root.bodyFont;font.pixelSize:19}
                    Rectangle{x:21;y:102;width:842;height:1;color:"#295575"}
                    Repeater{model:[{label:"Available for User Data:",value:w.storageSize(w.storagePlan.availableBytes)},{label:"Minimum Size:",value:"4 GiB"},{label:"Maximum Size:",value:w.storageSize(w.storagePlan.availableBytes)}]
                        Item{required property int index;required property var modelData;x:38;y:124+39*index
                            Text{text:modelData.label;color:"#C5ECF7";font.family:root.bodyFont;font.pixelSize:21}
                            Text{x:355;text:modelData.value;color:"white";font.family:root.bodyFont;font.pixelSize:21}
                        }
                    }
                }
            }
            SetupAction{x:613;y:766;width:450;height:87;onActivated:root.selectRow(w.selectedIndex===0?0:1)}
            Text{x:688;y:876;width:515;text:w.selectedIndex===1?"Keep current storage · Up / Down to change":"Create user data · Up / Down to change";color:"#9EBAD5";font.family:root.bodyFont;font.pixelSize:15;horizontalAlignment:Text.AlignHCenter}
            SetupPanel{visible:w.storageConfirmOpen;x:527;y:364;width:619;height:236;z:30
                Text{x:28;y:23;width:563;text:"Create the verified DATA partition?\nThis writes only to the unused space shown above.";color:"white";font.family:root.bodyFont;font.pixelSize:23;wrapMode:Text.WordWrap}
                SetupField{x:24;y:153;width:276;height:57;text:"CONFIRM";selected:w.selectedIndex===0;chevron:false;onActivated:root.selectRow(0)}
                SetupField{x:319;y:153;width:276;height:57;text:"CANCEL";selected:w.selectedIndex===1;chevron:false;onActivated:root.selectRow(1)}
            }
        }
    }
    Component {
        id:recovery
        Item {
            Text{x:109;y:210;width:516;text:"Your recovery key restores access if your\npassword or controller passcode is lost.\nSave your key safely. Optionally save a recovery\nbundle on a mounted USB drive.";wrapMode:Text.WordWrap;color:"#E0EDF8";font.family:root.bodyFont;font.pixelSize:20;lineHeight:1.2}
            SetupIllustration{x:60;y:330;width:554;height:400;source:"assets/recovery-illustration.png"}
            Text{x:79;y:749;width:525;text:"PROTECT. RECOVER. NEVER LOSE ACCESS.";color:"#DCEBF8";font.family:root.bodyFont;font.pixelSize:14;font.letterSpacing:4;horizontalAlignment:Text.AlignHCenter}
            SetupPanel{x:654;y:80;width:957;height:299;radius:16;border.color:"#00CEFF"
                SetupGlyph{x:31;y:19;width:66;height:66;kind:"key";color:"white"}
                Rectangle{x:112;y:24;width:1;height:57;color:"#17364F"}
                Text{x:130;y:15;text:"Your Recovery Key";color:"white";font.family:root.bodyFont;font.pixelSize:31;font.weight:Font.Bold}
                Text{x:130;y:60;width:802;text:"This key can be used to recover your account and regain access to NeutronOS.\nSave it in a secure location (e.g. written down or a password manager).";color:"#C8EBFA";font.family:root.bodyFont;font.pixelSize:19;lineHeight:1.35}
                SetupField{x:30;y:130;width:724;height:65;text:String(w.backend()?w.backend().recoveryCode:"")||"Generating recovery key…";chevron:false;textSize:24}
                SetupField{x:770;y:130;width:166;height:65;text:"COPY";selected:w.recoveryActionIndex===0;chevron:false;textSize:21;onActivated:w.copyRecoveryKey()}
                Rectangle{x:30;y:208;width:906;height:72;radius:12;color:"#171400";border.color:"#EABD00";border.width:2
                    Text{x:18;y:12;text:"⚠";color:"#F5C900";font.pixelSize:36}
                    Text{x:85;y:12;width:796;text:"Keep this key safe. Anyone with this key can potentially recover access\nto your system.";color:"#FFEB9E";font.family:root.bodyFont;font.pixelSize:19;lineHeight:1.35}
                }
            }
            SetupPanel{x:654;y:397;width:957;height:380;radius:16;border.color:"#00CEFF"
                SetupGlyph{x:34;y:20;width:60;height:60;kind:"storage";color:"white"}
                Text{x:129;y:16;text:"Save a Recovery Bundle";color:"white";font.family:root.bodyFont;font.pixelSize:31;font.weight:Font.Bold}
                Text{x:129;y:61;width:797;text:"Save an encrypted recovery bundle to an already-mounted USB drive.";color:"#C7ECFA";font.family:root.bodyFont;font.pixelSize:19}
                SetupPanel{x:26;y:99;width:560;height:263;radius:12
                    Text{x:17;y:14;text:"Available USB Drives";color:"#B7EFFF";font.family:root.bodyFont;font.pixelSize:19}
                    ListView{id:recoveryTargets;x:14;y:48;width:532;height:194;clip:true;spacing:3;model:w.backend()?w.backend().recoveryTargets:[];currentIndex:w.recoveryIndex
                        delegate:SetupField{required property int index;required property var modelData;width:532;height:47;iconKind:"storage";text:String(modelData.label||modelData.name||modelData.mountPath);selected:index===w.recoveryIndex&&w.recoveryActionIndex===1;chevron:false;textSize:17;onActivated:{w.recoveryIndex=index;w.recoveryActionIndex=1}}
                    }
                    Text{x:20;y:74;width:510;visible:!recoveryTargets.count;text:"No removable drive mounted.\nPress Square to skip.";color:"#AFCBE5";font.family:root.bodyFont;font.pixelSize:20;lineHeight:1.5}
                }
                SetupPanel{x:604;y:99;width:332;height:263;radius:12
                    SetupGlyph{x:20;y:19;width:33;height:33;kind:"storage";color:"white"}
                    Text{x:79;y:16;width:240;text:"The encrypted bundle helps\nrestore access to your\nNeutronOS installation.";color:"#D2EDF7";font.family:root.bodyFont;font.pixelSize:17;lineHeight:1.3}
                    SetupGlyph{x:20;y:93;width:33;height:33;kind:"info";color:"white"}
                    Text{x:79;y:91;width:240;text:"Existing files are preserved.\nNo drive is formatted.";color:"#C8EAF6";font.family:root.bodyFont;font.pixelSize:17;lineHeight:1.4}
                    Text{x:24;y:151;width:285;text:(w.recoveryConfirmOpen?"☑":"□")+"   Confirm selected drive";color:"#BBD9F0";font.family:root.bodyFont;font.pixelSize:17}
                    SetupField{x:16;y:209;width:302;height:47;text:"SAVE RECOVERY BUNDLE";chevron:false;textSize:16;selected:w.recoveryActionIndex===2;enabled:recoveryTargets.count>0;onActivated:{w.recoveryActionIndex=2;w.handleControllerPressed("primary")}}
                }
            }
            SetupAction{x:620;y:795;width:430;height:81;selected:w.recoveryActionIndex===3;onActivated:{w.recoveryActionIndex=3;w.handleControllerPressed("primary")}}
            SetupPanel{visible:w.recoveryConfirmOpen;x:502;y:375;width:668;height:217;z:30
                Text{x:28;y:22;width:612;text:"Save the recovery bundle to the selected drive?\nNo drive will be formatted.";color:"white";font.family:root.bodyFont;font.pixelSize:24;wrapMode:Text.WordWrap}
                SetupField{x:27;y:140;width:614;height:55;text:"X  SAVE     O  CANCEL";selected:true;chevron:false;onActivated:w.handleControllerPressed("primary")}
            }
        }
    }
    Component {
        id:security
        Item {
            readonly property int score:w.simulatedSecurity.score
            readonly property var stats:root.core?root.core.stats||{}:({})
            Text{x:75;y:198;text:"Configure your security settings and learn how the security score is calculated.";color:"#DCEBF7";font.family:root.bodyFont;font.pixelSize:22}
            SetupPanel{x:38;y:233;width:421;height:580;border.color:"#00AAFF"
                Repeater{model:[{name:"Security Profile",icon:"shield"},{name:"Learning Mode",icon:"brain"},{name:"Enforcement Mode",icon:"gavel"},{name:"Response Engine",icon:"chip"},{name:"Background Malware Scan",icon:"search"},{name:"Hardening Profile",icon:"shield"},{name:"Threat Severity",icon:"list"},{name:"Automatic Ban Threshold",icon:"ban"}]
                    Item{required property int index;required property var modelData;x:14;y:15+67.5*index;width:398;height:62
                        SetupField{anchors.fill:parent;text:modelData.name;iconKind:modelData.icon;selected:w.securityPanel==="left"&&w.selectedIndex===index;focusColor:"#159DFF";selectedFill:"#072448";idleFill:"transparent";idleBorder:false;strongText:false;chevron:false;textSize:18;onActivated:{w.selectedIndex=index;w.securityPanel="right";w.securityChoiceIndex=w.securityProfileIndex}}
                        Rectangle{x:1;y:62;width:389;height:1;color:"#174B70";visible:index<7}
                    }
                }
            }
            SetupPanel{x:475;y:231;width:762;height:582;border.color:"#009DFF";radius:19
                SetupGlyph{x:26;y:22;width:62;height:62;kind:"shield";color:"white"}
                Text{x:119;y:18;text:w.selectedIndex===0||w.selectedIndex===8?"Security Profile":["","Learning Mode","Enforcement Mode","Response Engine","Background Malware Scan","Hardening Profile","Threat Severity","Automatic Ban Threshold"][w.selectedIndex];color:"white";font.family:root.bodyFont;font.pixelSize:30;font.weight:Font.Bold}
                Text{x:119;y:60;width:621;text:"Choose how NeutronOS protects your system. This sets the base configuration for all security features.";wrapMode:Text.WordWrap;color:"#D0E9F6";font.family:root.bodyFont;font.pixelSize:18;lineHeight:1.35}
                Column{x:23;y:120;spacing:16;visible:w.selectedIndex===0||w.selectedIndex===8
                    Repeater{model:[{label:"Balanced (Recommended)",detail:"Strong protection with minimal interruption.\nIdeal for daily use."},{label:"Strict",detail:"Maximum protection and enforcement.\nBest for high-risk environments."},{label:"Custom",detail:"Manually configure each security feature."}]
                        SetupPanel{required property int index;required property var modelData;width:718;height:index===2?82:98;radius:13;border.width:w.securityProfileIndex===index?2:1;border.color:w.securityPanel==="right"&&w.securityChoiceIndex===index?"#77F7FF":w.securityProfileIndex===index?"#1DFF78":"#126CB0"
                            SetupGlyph{x:31;y:21;width:52;height:52;kind:"shield";color:"white"}
                            Text{x:114;y:13;text:modelData.label;color:w.securityProfileIndex===index?"#59FF99":"white";font.family:root.bodyFont;font.pixelSize:21;font.weight:Font.Bold}
                            Text{x:114;y:42;width:528;text:modelData.detail;color:"#C8E8F5";font.family:root.bodyFont;font.pixelSize:18;lineHeight:1.3}
                            Rectangle{x:661;y:parent.height/2-14;width:28;height:28;radius:14;color:"transparent";border.width:2;border.color:w.securityProfileIndex===index?"#00FF75":"#159EFF";Rectangle{anchors.centerIn:parent;width:16;height:16;radius:8;color:"#00FF75";visible:w.securityProfileIndex===index}}
                            MouseArea{anchors.fill:parent;onClicked:{w.securityChoiceIndex=index;w.securityProfileIndex=index;w.securityPanel="right"}}
                        }
                    }
                }
                Column{x:29;y:155;width:705;spacing:29;visible:w.selectedIndex>0&&w.selectedIndex<8
                    Text{width:705;text:w.securityProfileIndex===2?"Press X to change. Left switches panels; Up / Down navigates.":"Select Custom to adjust individual protection settings.";color:"#BEDAFB";font.family:root.bodyFont;font.pixelSize:24;wrapMode:Text.WordWrap}
                    SetupField{width:705;height:82;selected:w.securityPanel==="right";chevron:false;text:w.selectedIndex===1?((w.securityProfileIndex===2?w.securityLearningMode:false)?"Enabled":"Disabled"):w.selectedIndex===2?((w.securityProfileIndex===2?w.securityEnforcementEnabled:true)?"Enabled":"Disabled"):w.selectedIndex===3?((w.securityProfileIndex===2?w.securityResponseEngineEnabled:true)?"Enabled":"Disabled"):w.selectedIndex===4?((w.securityProfileIndex===2?w.securityBackgroundScanEnabled:true)?"Enabled":"Disabled"):w.selectedIndex===5?(w.securityProfileIndex===0?"Balanced":w.securityProfileIndex===1?"Strict":w.securityHardeningOptions[w.securityHardeningIndex]):w.selectedIndex===6?(w.securityProfileIndex===2?w.securitySeverityOptions[w.securitySeverityIndex]:"High"):(w.securityProfileIndex===2?w.securityBanOptions[w.securityBanIndex]:5)+" events";onActivated:w.handleControllerPressed("primary")}
                }
                Rectangle{x:23;y:449;width:718;height:1;color:"#376687"}
                SetupGlyph{x:25;y:461;width:39;height:39;kind:"info";color:"#83D2FF"}
                Text{x:82;y:461;text:"About Security Profiles";color:"white";font.family:root.bodyFont;font.pixelSize:21;font.weight:Font.Bold}
                Text{x:82;y:491;width:646;text:"The security profile adjusts learning mode, enforcement, scanning\nbehavior, and automatic response thresholds. Choose Custom to\nchange individual settings.";color:"#C5E7F6";font.family:root.bodyFont;font.pixelSize:17;lineHeight:1.4}
            }
            SetupPanel{x:1251;y:129;width:386;height:684;border.color:"#00AAFF";radius:17
                Text{x:30;y:18;text:"Simulated Score";color:"white";font.family:root.bodyFont;font.pixelSize:28;font.weight:Font.Bold}
                Text{x:30;y:57;width:325;text:"Preview for "+w.simulatedSecurity.profile+". This is not your live security score.";wrapMode:Text.WordWrap;color:"#D5E9F6";font.family:root.bodyFont;font.pixelSize:18;lineHeight:1.3}
                Repeater{model:["#FF263B","#FF8D20","#F0D31A","#BDEE17","#06F875","#05D49E"]
                    Shape{required property int index;required property var modelData;x:82;y:104;width:222;height:123;ShapePath{strokeColor:modelData;strokeWidth:14;fillColor:"transparent";PathAngleArc{centerX:111;centerY:111;radiusX:102;radiusY:102;startAngle:180+index*30.5;sweepAngle:29}}}
                }
                Text{x:0;y:148;width:386;text:"○";color:"#00FF7A";font.family:root.bodyFont;font.pixelSize:65;horizontalAlignment:Text.AlignHCenter}
                Text{x:0;y:206;width:386;text:"SIMULATION · "+w.simulatedSecurity.profile.toUpperCase();color:"white";font.family:root.bodyFont;font.pixelSize:25;font.weight:Font.Bold;horizontalAlignment:Text.AlignHCenter}
                Text{x:68;y:235;text:String(w.simulatedSecurity.score);color:"#37FF8A";font.family:root.bodyFont;font.pixelSize:58;font.weight:Font.Bold}
                Text{x:226;y:255;text:"/ 100";color:"white";font.family:root.bodyFont;font.pixelSize:30}
                Rectangle{x:26;y:307;width:333;height:22;radius:7;gradient:Gradient{orientation:Gradient.Horizontal;GradientStop{position:0;color:"#FF1638"}GradientStop{position:0.3;color:"#FFAD17"}GradientStop{position:0.6;color:"#DCFF15"}GradientStop{position:1;color:"#00FCB1"}}}
                Repeater{model:6;Text{required property int index;x:25+index*66;y:340;text:String(index*20);color:"#D2E5F4";font.family:root.bodyFont;font.pixelSize:16}}
                SetupPanel{x:15;y:368;width:356;height:302;radius:14;border.color:"#00BFFF"
                    SetupGlyph{x:20;y:16;width:30;height:30;kind:"chart";color:"white"}
                    Text{x:66;y:13;text:"Score Factors";color:"white";font.family:root.bodyFont;font.pixelSize:22;font.weight:Font.Bold}
                    Repeater{model:[{name:"Base rating",value:"100"},{name:"Firewall assumption",value:"SECURE"},{name:"Failed services",value:"0"},{name:"Events (24h)",value:"0"},{name:"Selected profile",value:w.simulatedSecurity.profile},{name:"Profile score bonus",value:"None"},{name:"Score source",value:"Simulation"}]

                        Item{required property int index;required property var modelData;x:18;y:52+27*index;width:320;height:26
                            Text{text:modelData.name;color:"#DEEBF7";font.family:root.bodyFont;font.pixelSize:16}
                            Text{x:216;width:104;text:modelData.value;color:"#10FF80";font.family:root.bodyFont;font.pixelSize:16;horizontalAlignment:Text.AlignRight;elide:Text.ElideRight}
                            Rectangle{y:25;width:320;height:1;color:"#20364C";visible:index<8}
                        }
                    }
                }
            }
            SetupAction{x:663;y:823;width:347;height:66;text:"CONTINUE";onActivated:w.setStep(8)}
        }
    }
    Component {
        id:experience
        Item {
            Text{x:105;y:150;width:1462;text:"Customize your display, audio, power, and connectivity preferences for the best experience on your device.";color:"#C4DFFB";font.family:root.bodyFont;font.pixelSize:23;horizontalAlignment:Text.AlignHCenter}
            SetupPanel{x:70;y:185;width:1536;height:637;border.color:"#00BFFF"
                Repeater{model:[{label:"Audio Output",detail:"Choose your default audio device.",value:w.audioOutputLabel(),glyph:"audio",row:0},{label:"Video Output",detail:"Using the current display mode.",value:"Automatic · "+Screen.width+" × "+Screen.height,glyph:"display",row:1},{label:"Power Preference",detail:"Balance performance and power usage.",value:w.performanceOptions[w.performanceIndex],glyph:"power",row:2},{label:"SSH After Setup",detail:"Remote access with your Linux account.",value:w.sshEnabledOnFinish?"Enabled":"Disabled",glyph:"ssh",row:3},{label:"Remote Controller",detail:"Control NeutronOS from another device.",value:(w.remoteControllerEnabled?"Enabled":"Disabled")+" · "+w.controllerConnectionLabel,glyph:"controller",row:4},{label:"Display Confirmation",detail:"Confirm the picture fits your screen.",value:w.displayConfirmed?"Confirmed":"Review later",glyph:"display",row:5},{label:"Default Tab",detail:"Choose your landing page after login.",value:w.dashboardTabOptions[w.dashboardTabIndex],glyph:"home",row:6}]
                    Item{required property int index;required property var modelData;x:20;y:12+88*index;width:1496;height:80
                        SetupField{anchors.fill:parent;text:"";selected:w.selectedIndex===modelData.row;focusColor:"#2F8CFF";selectedFill:"#031833";idleFill:"#030C1A";chevron:false;onActivated:root.selectRow(modelData.row)}
                        SetupGlyph{x:33;y:14;width:58;height:52;kind:modelData.glyph;color:"white"}
                        Text{x:136;y:12;text:modelData.label;color:"#EBF4FE";font.family:root.bodyFont;font.pixelSize:24;font.weight:Font.Bold}
                        Text{x:136;y:44;text:modelData.detail;color:"#B5D0F1";font.family:root.bodyFont;font.pixelSize:19}
                        SetupField{x:972;y:8;width:492;height:65;text:modelData.value;iconKind:modelData.row===3?"lock":modelData.glyph;strongText:false;focusColor:"#00CFFF";idleFill:"#020C1B";textSize:21;chevron:modelData.row!==1;onActivated:root.selectRow(modelData.row)}
                        
                    }
                }
            }
            SetupAction{x:618;y:833;width:436;height:66;onActivated:w.continuePreferences()}
            SetupPanel{visible:w.experienceExtraPanel;x:303;y:338;width:1066;height:321;z:25
                Text{x:27;y:22;text:"MORE PREFERENCES";color:"white";font.family:root.bodyFont;font.pixelSize:28;font.weight:Font.Bold}
                Repeater{model:["Screensaver: "+w.screensaverOptions[w.screensaverIndex]+" minutes","Launcher: "+w.launcherOptions[w.launcherIndex],"Privacy: "+w.privacyOptions[w.privacyIndex]]
                    SetupField{required property int index;required property var modelData;x:25;y:84+70*index;width:1016;height:57;text:modelData;selected:w.experienceExtraIndex===index;onActivated:{w.experienceExtraIndex=index;w.handleControllerPressed("primary")}}
                }
            }
        }
    }
    Component {
        id:ready
        Item {
            ReadyHalo{x:384;y:1;width:904;height:665;quality:root.quality}
            SetupStage{x:374;y:488;width:924;height:158;quality:root.quality}
            EnergyAtom{x:556;y:111;width:560;height:510;quality:root.quality;animated:root.visible&&!w.fractureActive}
            Text{x:105;y:628;width:1462;textFormat:Text.RichText;text:"Neutron<span style='color:#FF0027'>OS</span> is Ready";color:"white";font.family:root.bodyFont;font.pixelSize:93;font.weight:Font.Bold;horizontalAlignment:Text.AlignHCenter}
            Text{x:205;y:739;width:1262;text:"YOUR SYSTEM IS CONFIGURED AND READY TO GO";color:"#C9EBFF";font.family:root.bodyFont;font.pixelSize:23;font.letterSpacing:6;horizontalAlignment:Text.AlignHCenter}
            SetupAction{x:595;y:791;width:485;height:85;onActivated:w.handleControllerPressed("primary")}
        }
    }
}
