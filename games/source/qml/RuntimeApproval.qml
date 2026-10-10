import QtQuick

Rectangle {
    id: review
    objectName: "GamesRuntimeApproval"
    property var store
    property var backend
    property string runtime: ""
    property string reason: ""
    property int selected: 0
    property bool confirming: false
    property var proposal: ({})
    property var footprint: ({})
    readonly property var providers: {
        var catalog=store ? store.catalog : []
        var token=" "+runtime.toLowerCase()+" "
        return catalog.filter(function(p){
            var text=" "+String(p.name+" "+p.id+" "+(p.description || "")).toLowerCase().replace(/[^a-z0-9]+/g," ")+" "
            return p.signatureReady===true && p.compatible===true && !p.localOnly &&
                   (p.storeEligible===true || p.updateEligible===true) && text.indexOf(token)>=0
        })
    }
    signal closeRequested()
    signal beforeInstall()
    color: "#e701050e"

    function requestInstall() {
        // Catalog entries and footprint can change while confirmation is open.
        var current=store ? store.packageById(proposal.id) : ({})
        var previousFootprint=footprint
        footprint=store && current.id ? store.installFootprint(current.id) : ({})
        if(!current.id || current.signatureReady!==true || current.compatible!==true ||
                !(current.storeEligible===true || current.updateEligible===true)) {
            backend.notify("The runtime package is no longer available from a verified compatible catalog. Refresh the App Store.",true)
            return
        }
        if(store.busy || backend.gameActive){backend.notify("Finish the active game or App Store operation before installing a runtime.");return}
        if(footprint.known!==true){backend.notify("Runtime disk usage could not be estimated. Refresh the App Store and its dependency metadata before installation.",true);return}
        // Require another review if the package identity/version/hash or footprint changed.
        if(JSON.stringify([current.version,current.sha256,current.packageUrl,current.description,current.debianDependencies,current.permissions])!==
                JSON.stringify([proposal.version,proposal.sha256,proposal.packageUrl,proposal.description,proposal.debianDependencies,proposal.permissions]) ||
                previousFootprint.totalInstalledBytes!==footprint.totalInstalledBytes || previousFootprint.totalDownloadBytes!==footprint.totalDownloadBytes ||
                previousFootprint.diskEstimateLowerBound!==footprint.diskEstimateLowerBound) {
            proposal=current;backend.notify("Runtime package details changed. Review the current version before approving it.");return
        }
        beforeInstall()
        var accepted=current.updateEligible===true ? store.updatePackage(current.id) : store.installPackage(current.id)
        if(accepted)closeRequested()
        else backend.notify(store.lastError || store.statusMessage || "The App Store could not start this runtime installation.",true)
    }
    function handleControllerPressed(action) {
        if(action==="cancel"){if(confirming)confirming=false;else closeRequested()}
        else if(confirming&&(action==="up" || action==="down"))details.contentY=Math.max(0,Math.min(Math.max(0,details.contentHeight-details.height),details.contentY+(action==="up"?-80:80)))
        else if(!confirming&&action==="up")selected=Math.max(0,selected-1)
        else if(!confirming&&action==="down")selected=Math.min(providers.length-1,selected+1)
        else if(action==="primary") {
            if(confirming)requestInstall()
            else if(providers.length){proposal=providers[selected];footprint=store.installFootprint(proposal.id);details.contentY=0;confirming=true}
        }
    }
    onVisibleChanged: if(visible){selected=0;confirming=false;proposal=({});footprint=({})}
    onProvidersChanged: selected=Math.max(0,Math.min(selected,providers.length-1))
    NeonPanel {
        anchors.centerIn: parent;width: Math.min(parent.width*0.82,1150);height: Math.min(parent.height*0.87,800);illuminated: true
        Text { x: 30;y: 24;text: "Runtime Setup  ·  "+review.runtime.toUpperCase();color: "white";font.pixelSize: 29;font.bold: true }
        Text { x: 30;y: 75;width: parent.width-60;text: review.reason+"\nInstalling a runtime does not establish game compatibility. Review each package's contents and caveats.";color: "#93c9e7";font.pixelSize: 17;wrapMode: Text.Wrap }
        Text {
            x: 30;y: 165;width: parent.width-60;visible: !review.confirming&&!review.providers.length
            text: "No compatible signed package candidate for this runtime is available in the current Gemini App Store catalog.\n\nRefresh the App Store or supply an already installed compatible runtime. No software has been installed."
            color: "#c4d5e3";font.pixelSize: 21;wrapMode: Text.Wrap
        }
        ListView {
            id: packages
            x: 30;y: 165;width: parent.width-60;height: parent.height-265;clip: true;spacing: 12
            visible: !review.confirming;model: review.providers;currentIndex: review.selected
            onCurrentIndexChanged: positionViewAtIndex(currentIndex,ListView.Contain)
            delegate: NeonPanel {
                width: packages.width;height: 90;illuminated: review.selected===index
                Text { x: 18;y: 12;width: parent.width-36;text: modelData.name+"  ·  "+(modelData.version || "");color: "white";font.pixelSize: 20;elide: Text.ElideRight }
                Text { x: 18;y: 46;width: parent.width-36;text: modelData.repositoryName+"  ·  "+(modelData.description || "");color: "#abc8db";font.pixelSize: 15;elide: Text.ElideRight }
                MouseArea { anchors.fill: parent;onClicked: {review.selected=index;review.handleControllerPressed("primary")} }
            }
        }
        Flickable {
            id: details
            x: 30;y: 165;width: parent.width-60;height: parent.height-285;clip: true;visible: review.confirming
            contentHeight: detailText.height;boundsBehavior: Flickable.StopAtBounds
            Text {
                id: detailText;width: details.width;wrapMode: Text.Wrap;color: "#c4d5e3";font.pixelSize: 18
                text: review.proposal.name+"  "+(review.proposal.version || "")+"\n"+(review.proposal.description || "")+
                      "\n\nSource: "+(review.proposal.repositoryName || "")+"\n"+(review.proposal.packageUrl || "")+
                      "\nDeclared Debian packages: "+(review.proposal.debianDependencies || []).join(", ")+
                      "\nDependency source: the system's configured Debian repositories."+
                      "\n\nEstimated disk usage: "+(review.footprint.known && review.store ? (review.footprint.diskEstimateLowerBound?"at least ":"")+review.store.formatBytes(review.footprint.totalInstalledBytes) : "Unavailable; installation is blocked")+
                      "\nEstimated download: "+(review.footprint.known && review.store ? review.store.formatBytes(review.footprint.totalDownloadBytes) : "Unavailable")+
                      "\n\nImpact: shared system packages and an App Store application overlay. Shared Debian dependencies remain installed when the app is removed. Personal game files remain separate."+
                      "\nPermissions: "+(review.proposal.permissions || []).join(", ")+
                      "\n\nCaveats: verify that this package provides "+review.runtime+". Launcher, BIOS/firmware, GPU and per-title requirements may still apply. The App Store will verify the NAPP and privileged operations again."
            }
        }
        NeonPanel {
            x: 30;y: parent.height-100;width: parent.width-60;height: 45;visible: review.confirming;illuminated: true
            Text { anchors.centerIn: parent;text: review.footprint.known?"X  Approve App Store Installation":"Disk estimate unavailable  ·  Installation blocked";color: "white";font.pixelSize: 18 }
            MouseArea { anchors.fill: parent;onClicked: review.requestInstall() }
        }
        Text { x: 30;y: parent.height-42;width: parent.width-60;text: review.confirming?"↑ ↓ Scroll details    X Approve    Circle Back":"↑ ↓ Select Package    X Review    Circle Cancel";color: "#4ac9ff";font.pixelSize: 16 }
    }
}
