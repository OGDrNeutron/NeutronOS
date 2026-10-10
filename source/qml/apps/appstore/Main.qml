import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components" as Shared

// App Store premium layout v8
Item {
    id: root
    anchors.fill: parent
    focus: true

    property string appId: "appstore"
    property string appName: "App Store"
    property var appData: ({})
    property var activeUser: null
    property bool hostActive: true
    property bool developerModeEnabled: (typeof developerModeManager !== "undefined")
                                        ? developerModeManager.developerModeEnabled : false
    property var backend: (typeof appStoreManager !== "undefined") ? appStoreManager : null
    property var assetBackend: (typeof assetManager !== "undefined") ? assetManager : null
    property var securityBackend: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null

    // Reference-app navigation contract:
    // 0 top tabs, 1 package list, 2 detail actions, 3 header menu.
    property int focusZone: 0
    property int tabIndex: 0
    property int packageIndex: 0
    property int actionIndex: 0
    property int screenshotIndex: 0
    property bool screenshotFocusActive: false
    property real lastDetailContentY: 0
    readonly property real textScale: 1.40
    property var selectedFootprint: ({})
    property var selectedUninstallPlan: ({})
    property bool packageEngaged: false
    property var topTabs: ["Discover", "Updates", "Installed"]
    property var visiblePackages: []
    property string searchText: ""
    property string selectedFilter: "available"

    property bool keyboardOpen: false
    property string keyboardPurpose: ""
    property string keyboardBuffer: ""
    property bool confirmOpen: false
    property string confirmOperation: ""
    property bool repositoriesOpen: false
    property int repositoryIndex: 0
    property bool statusOpen: false
    property bool exitOpen: false
    property string toastText: ""
    property int startupResumeAttempts: 0
    property bool statusIsOperationResult: false
    property string resultOperation: ""
    property bool resultSuccess: false
    property string resultPackageName: ""
    property string resultPackageVersion: ""
    property string resultReason: ""
    property string resultSolution: ""
    property string resultStage: ""
    property string resultErrorCode: ""
    property string resultDetails: ""
    property bool analysisOpen: false
    property int analysisActionIndex: 0
    property string analyzedPackagePath: ""
    property int contentReturnZone: 1
    property bool screenshotPreviewOpen: false
    property string pendingPreselectPackageId: ""

    property string screenshotPreviewSource: ""
    property string changelogText: ""
    property string changelogRequestKey: ""
    property bool changelogLoading: false

    readonly property bool securityProtected: securityBackend &&
                                                securityBackend.daemonOnline &&
                                                securityBackend.auditValid &&
                                                Number(securityBackend.threatLevel || 5) > 2
    readonly property bool repositoryConnected: backend ? backend.repositoryConnected : false

    readonly property color background: "#050711"
    readonly property color panel: "#d9162134"
    readonly property color panelStrong: "#f21a263c"
    readonly property color panelRaised: "#f01b2940"
    readonly property color border: "#4a688fae"
    readonly property color focusBlue: "#49c8ff"
    readonly property color cyan: "#7df9ff"
    readonly property color purple: "#c084fc"
    readonly property color success: "#35e68a"
    readonly property color warning: "#ffc857"
    readonly property color danger: "#ff4050"
    readonly property color textPrimary: "#f5fbff"
    readonly property color textSecondary: "#aebbd0"
    readonly property color textMuted: "#75869d"

    signal exitRequested()
    signal backgroundRequested()

    function normalizeAction(action) {
        var value = String(action || "").toLowerCase()
        if (value === "x" || value === "cross" || value === "accept" || value === "enter") return "primary"
        if (value === "o" || value === "circle" || value === "back" || value === "escape") return "cancel"
        if (value === "dpadup" || value === "up" || value === "leftstickup") return "up"
        if (value === "dpaddown" || value === "down" || value === "leftstickdown") return "down"
        if (value === "dpadleft" || value === "left" || value === "leftstickleft") return "left"
        if (value === "dpadright" || value === "right" || value === "leftstickright") return "right"
        if (value === "options" || value === "start" || value === "menu" || value === "system") return "start"
        if (value === "triangle" || value === "y" || value === "context" || value === "ps_triangle") return "triangle"
        if (value === "square" || value === "secondary" || value === "ps_square" || value === "xbox-x" || value === "xbox_x") return "square"
        if (value === "r3" || value === "rightstickclick") return "r3"
        if (value === "l1" || value === "leftshoulder") return "l1"
        if (value === "r1" || value === "rightshoulder") return "r1"
        return value
    }

    function tabName() {
        return String(topTabs[Math.max(0, Math.min(tabIndex, topTabs.length - 1))])
    }

    // NEUTRONOS_APPSTORE_PRESELECT_V1
    function launchRequestedPackageId() {
        var id = ""
        try { id = String(appData && appData.preselectPackageId || "").trim() } catch (e1) { id = "" }
        if (!id.length) {
            try { id = String(appData && appData.launchContext && appData.launchContext.packageId || "").trim() } catch (e2) { id = "" }
        }
        return id
    }

    function tryApplyPackagePreselection() {
        if (!backend) return false
        var id = String(pendingPreselectPackageId || launchRequestedPackageId() || "").trim().toLowerCase()
        if (!id.length) return false

        for (var targetTab = 0; targetTab < topTabs.length; ++targetTab) {
            selectTab(targetTab)
            for (var i = 0; i < visiblePackages.length; ++i) {
                if (String(visiblePackages[i].id || "").trim().toLowerCase() === id) {
                    packageIndex = i
                    packageEngaged = true
                    actionIndex = 0
                    focusZone = 2
                    pendingPreselectPackageId = ""
                    if (packageList) packageList.positionViewAtIndex(packageIndex, ListView.Center)
                    resetDetailScroll()
                    loadChangelog()
                    return true
                }
            }
        }

        pendingPreselectPackageId = id
        selectTab(0)
        return false
    }

    function capturePackagePreselection() {
        var id = launchRequestedPackageId()
        if (id.length) pendingPreselectPackageId = id
        Qt.callLater(tryApplyPackagePreselection)
    }

    function refreshVisiblePackages() {
        if (!backend) {
            visiblePackages = []
            packageIndex = 0
            actionIndex = 0
            return
        }
        if (tabIndex === 1) selectedFilter = "updates"
        else if (tabIndex === 2) selectedFilter = "installed"
        else selectedFilter = "available"
        visiblePackages = backend.searchPackages(searchText, "All", selectedFilter)
        packageIndex = Math.max(0, Math.min(packageIndex, Math.max(0, visiblePackages.length - 1)))
        actionIndex = Math.max(0, Math.min(actionIndex, Math.max(0, packageActions(currentPackage()).length - 1)))
        if (packageList) packageList.positionViewAtIndex(packageIndex, ListView.Contain)
        refreshFootprint()
    }

    function selectTab(index) {
        tabIndex = Math.max(0, Math.min(index, topTabs.length - 1))
        packageIndex = 0
        actionIndex = 0
        screenshotIndex = 0
        screenshotFocusActive = false
        packageEngaged = false
        refreshVisiblePackages()
    }

    function scrollDetail(delta) {
        if (!detailFlick) return
        var wasVisible = screenshotSectionActive()
        var maxY = Math.max(0, detailFlick.contentHeight - detailFlick.height)
        detailFlick.contentY = Math.max(0, Math.min(maxY, detailFlick.contentY + delta))
        var nowVisible = screenshotSectionActive()
        if (delta > 0 && nowVisible && !wasVisible) {
            screenshotIndex = 0
            screenshotFocusActive = screenshotGrid && screenshotGrid.shotCount > 0
            ensureSelectedScreenshotVisible()
        } else if (!nowVisible) {
            screenshotFocusActive = false
        }
    }

    function resetDetailScroll() {
        if (detailFlick) detailFlick.contentY = 0
        lastDetailContentY = 0
        screenshotFocusActive = false
    }

    function currentPackage() {
        if (!visiblePackages || visiblePackages.length === 0) return ({})
        return visiblePackages[Math.max(0, Math.min(packageIndex, visiblePackages.length - 1))]
    }

    function detailPackage() {
        return packageEngaged ? currentPackage() : ({})
    }

    function packageActions(item) {
        var actions = []
        if (!item || !item.id) return actions
        if (item.updateEligible || item.updateAvailable)
            actions.push({ id: "update", label: "UPDATE", tone: "warning" })
        else if (item.storeEligible && !item.installed)
            actions.push({ id: "install", label: "INSTALL", tone: "success" })
        if (item.installed && item.managed)
            actions.push({ id: "uninstall", label: "UNINSTALL", tone: "danger" })
        return actions
    }

    function permissionItems(item) {
        var result = []
        if (!item || !item.permissions) return result
        for (var i = 0; i < item.permissions.length; ++i) {
            var value = String(item.permissions[i] || "").trim()
            if (value.length && result.indexOf(value) < 0) result.push(value)
        }
        return result
    }

    function dependencyItems(item) {
        var result = []
        if (!item) return result
        var sources = [item.dependencies, item.debianDependencies]
        for (var s = 0; s < sources.length; ++s) {
            var list = sources[s]
            if (!list) continue
            for (var i = 0; i < list.length; ++i) {
                var value = String(list[i] || "").trim()
                if (value.length && result.indexOf(value) < 0) result.push(value)
            }
        }
        if (item.runtimeRequirements) {
            for (var r = 0; r < item.runtimeRequirements.length; ++r) {
                var requirement = item.runtimeRequirements[r]
                var label = requirement && requirement.type ? String(requirement.type) : "runtime requirement"
                if (result.indexOf(label) < 0) result.push(label)
            }
        }
        return result
    }

    function joinedOrFallback(values, fallback) {
        return values && values.length ? values.join("  •  ") : fallback
    }

    function compatibilityText(item) {
        if (!item || !item.id) return "Select an app to review compatibility"
        if (item.compatible) return "Compatible With This Device"
        var reasons = item.compatibilityReasons || []
        return reasons.length ? reasons.join(" • ") : "Not Compatible With This Device"
    }

    function packageSize(item) {
        if (!backend || !item || !item.id) return "—"
        var bytes = Number(item.sizeBytes || item.size || item.installedBytes || 0)
        return backend.formatBytes(bytes)
    }

    function refreshFootprint() {
        var item = detailPackage()
        selectedFootprint = (backend && item && item.id) ? backend.installFootprint(item.id) : ({})
    }

    function footprintText(key, fallback) {
        if (!backend || !selectedFootprint || selectedFootprint[key] === undefined) return fallback || "—"
        var bytes = Number(selectedFootprint[key] || 0)
        var missing = selectedFootprint.missingDependencies || []
        if (selectedFootprint.known === false && bytes <= 0 && missing.length > 0) return "Unavailable"
        return backend.formatBytes(bytes)
    }

    function diskImpactText() {
        if (!backend || !selectedFootprint || selectedFootprint.totalInstalledBytes === undefined) return "—"
        var prefix = selectedFootprint.diskEstimateLowerBound ? "≥ " : ""
        return prefix + backend.formatBytes(Number(selectedFootprint.totalInstalledBytes || 0))
    }

    function missingDependenciesText(item) {
        var declared = root.dependencyItems(item)
        var missing = selectedFootprint && selectedFootprint.missingDependencies ? selectedFootprint.missingDependencies : []
        var declaredText = root.joinedOrFallback(declared, "No additional dependencies declared")
        if (!item || !item.id) return declaredText
        if (missing && missing.length) return declaredText + "\nMissing on this device: " + missing.join("  •  ")
        return declaredText + "\nEverything required by this package is already present."
    }

    function primaryPackageAction(item) {
        var actions = packageActions(item)
        return actions.length ? actions[0] : ({})
    }

    function packagePillLabel(item) {
        if (!item || !item.id) return ""
        if (backend && backend.busy && String(backend.activePackageId) === String(item.id)) {
            if (backend.activeOperation === "update") return "UPDATING"
            if (backend.activeOperation === "install") return "INSTALLING"
            if (backend.activeOperation === "uninstall") return "REMOVING"
        }
        if (item.updateEligible || item.updateAvailable) return "UPDATE"
        if (item.installed) return "INSTALLED"
        return "INSTALL"
    }

    function packagePillTone(item) {
        var label = packagePillLabel(item)
        if (label === "UPDATE" || label === "UPDATING") return "warning"
        if (label === "REMOVING") return "danger"
        return "success"
    }

    function assetSource(value, fallbackId, kind) {
        var text = String(value || fallbackId || "")
        if (text.length === 0) text = "appstore"

        var isRemote = text.indexOf("http://") === 0 || text.indexOf("https://") === 0

        // Explicit local/QRC URLs are already resolved and should be used as-is.
        if (text.indexOf("file://") === 0 || text.indexOf("qrc:/") === 0)
            return text

        // Prefer installed/local artwork even when the catalog supplies a remote URL.
        // App Store packages install artwork below the AssetManager overlay, so using
        // the remote filename here lets AssetManager find that local copy first.
        if (assetBackend) {
            var lookupName = text
            if (isRemote) {
                var cleanUrl = text
                var queryAt = cleanUrl.indexOf("?")
                if (queryAt >= 0) cleanUrl = cleanUrl.substring(0, queryAt)
                var hashAt = cleanUrl.indexOf("#")
                if (hashAt >= 0) cleanUrl = cleanUrl.substring(0, hashAt)
                var slashAt = cleanUrl.lastIndexOf("/")
                if (slashAt >= 0 && slashAt + 1 < cleanUrl.length) {
                    lookupName = cleanUrl.substring(slashAt + 1)
                    try { lookupName = decodeURIComponent(lookupName) } catch (error) {}
                } else {
                    lookupName = String(fallbackId || "")
                }
            }

            var resolved = kind === "poster" ? assetBackend.appPoster(lookupName) : assetBackend.appIcon(lookupName)
            if (String(resolved || "").length > 0) return resolved

            // If the repository filename differs from the package ID, keep the ID as
            // a second local lookup before falling back to the network.
            var fallbackText = String(fallbackId || "")
            if (fallbackText.length > 0 && fallbackText !== lookupName) {
                resolved = kind === "poster" ? assetBackend.appPoster(fallbackText) : assetBackend.appIcon(fallbackText)
                if (String(resolved || "").length > 0) return resolved
            }
        }

        // No local copy exists. For Discover/new apps, use the catalog/repository URL.
        if (isRemote) return text

        if (text.indexOf("/") >= 0) return "file://" + text

        var directory = kind === "poster" ? "posters" : "icons"
        return Qt.resolvedUrl("../../../themes/Default/apps/" + directory + "/" + text + ".png")
    }

    function screenshotSource(item) {
        if (!item || !item.id) return assetSource("appstore", "appstore", "poster")
        if (!item.screenshots || item.screenshots.length === 0)
            return assetSource(item.poster || item.id, item.id, "poster")
        screenshotIndex = Math.max(0, Math.min(screenshotIndex, item.screenshots.length - 1))
        var source = String(item.screenshots[screenshotIndex])
        if (source.indexOf("http") === 0 || source.indexOf("file:") === 0) return source
        var repo = String(item.repositoryBaseUrl || "")
        return repo.length ? repo + "/" + source : source
    }

    function artworkSource(item) {
        if (!item || !item.id) return assetSource("appstore", "appstore", "poster")
        return assetSource(item.poster || item.id, item.id, "poster")
    }

    function screenshotAt(item, index) {
        if (!item || !item.id || !item.screenshots || index < 0 || index >= item.screenshots.length) return ""
        var source = String(item.screenshots[index] || "")
        if (source.indexOf("http://") === 0 || source.indexOf("https://") === 0 || source.indexOf("file:") === 0 || source.indexOf("qrc:/") === 0) return source
        var repo = String(item.repositoryBaseUrl || "")
        return repo.length ? repo + "/" + source : source
    }

    function changelogFileName(item) {
        if (!item || !item.id) return ""
        var files = {
            "browser": "Browser.md",
            "codex": "Codex.md",
            "gallery": "Gallery.md",
            "games": "Games.md",
            "mediaoptimizer": "MediaOptimizer.md",
            "musicplayer": "MusicPlayer.md",
            "jellyfin": "NeutronMediaLibraries.md",
            "qbittorrent": "qBittorrent.md",
            "texteditor": "TextEditor.md"
        }
        return files[String(item.id)] || ""
    }

    function changelogUrl(item) {
        if (!item || !item.id) return ""
        if (item.changelogUrl && String(item.changelogUrl).length > 0) return String(item.changelogUrl)
        var fileName = changelogFileName(item)
        if (!fileName.length) return ""
        return "https://raw.githubusercontent.com/OGDrNeutron/NeutronOS/main/Apps/changelogs/" + fileName
    }

    function formatChangelog(markdown) {
        var lines = String(markdown || "").replace(/\r/g, "").split("\n")
        var output = []
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i]
            if (/^#\s+/.test(line)) continue
            if (/^##\s+/.test(line)) {
                output.push(line.replace(/^##\s+/, "VERSION ").toUpperCase())
                continue
            }
            if (/^###\s+/.test(line)) {
                output.push(line.replace(/^###\s+/, "").toUpperCase())
                continue
            }
            if (/^-\s+/.test(line)) line = "• " + line.replace(/^-\s+/, "")
            output.push(line)
        }
        while (output.length && String(output[0]).trim().length === 0) output.shift()
        return output.join("\n").trim()
    }

    function loadChangelog() {
        var item = detailPackage()
        if (!item || !item.id) {
            changelogText = ""
            changelogLoading = false
            changelogRequestKey = ""
            return
        }
        var url = changelogUrl(item)
        if (!url.length) {
            changelogText = "No changelog is published for this app yet."
            changelogLoading = false
            changelogRequestKey = String(item.id)
            return
        }
        var requestKey = String(item.id) + "@" + String(item.version || "")
        changelogRequestKey = requestKey
        changelogLoading = true
        changelogText = "Loading current release notes…"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || root.changelogRequestKey !== requestKey) return
            root.changelogLoading = false
            if (xhr.status >= 200 && xhr.status < 300) {
                var formatted = root.formatChangelog(xhr.responseText)
                root.changelogText = formatted.length ? formatted : "No changelog details were returned."
            } else {
                root.changelogText = "Changelog unavailable. Check the repository connection and refresh the catalog."
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function openScreenshot(source) {
        var value = String(source || "")
        if (!value.length) return
        screenshotPreviewSource = value
        screenshotPreviewOpen = true
    }

    function screenshotSectionActive() {
        if (!detailFlick || !screenshotGrid || screenshotGrid.shotCount <= 0) return false
        var viewportTop = detailFlick.contentY
        var viewportBottom = viewportTop + detailFlick.height
        var gridTop = screenshotGrid.y
        var gridBottom = gridTop + screenshotGrid.height
        return gridTop < (viewportBottom - 72) && gridBottom > (viewportTop + 72)
    }

    function ensureSelectedScreenshotVisible() {
        if (!detailFlick || !screenshotGrid || screenshotGrid.shotCount <= 0 || !screenshotFocusActive) return
        screenshotIndex = Math.max(0, Math.min(screenshotIndex, screenshotGrid.shotCount - 1))
        var columns = Math.max(1, screenshotGrid.columns)
        var row = Math.floor(screenshotIndex / columns)
        var shotHeight = screenshotGrid.shotWidth * 9 / 16
        var itemTop = screenshotGrid.y + row * (shotHeight + screenshotGrid.spacing)
        var itemBottom = itemTop + shotHeight
        var viewportTop = detailFlick.contentY
        var viewportBottom = viewportTop + detailFlick.height
        var padding = 28
        var maxY = Math.max(0, detailFlick.contentHeight - detailFlick.height)
        if (itemBottom > viewportBottom - padding) {
            detailFlick.contentY = Math.max(0, Math.min(maxY, itemBottom - detailFlick.height + padding))
        } else if (itemTop < viewportTop + padding) {
            detailFlick.contentY = Math.max(0, Math.min(maxY, itemTop - padding))
        }
        lastDetailContentY = detailFlick.contentY
    }

    function openSelectedScreenshot() {
        if (!detailPanel || !detailPanel.item || !detailPanel.item.id || !screenshotGrid || screenshotGrid.shotCount <= 0) return
        screenshotIndex = Math.max(0, Math.min(screenshotIndex, screenshotGrid.shotCount - 1))
        openScreenshot(screenshotAt(detailPanel.item, screenshotIndex))
    }

    function openNotice(message) {
        statusIsOperationResult = false
        toastText = String(message || "")
        statusOpen = true
    }

    function operationDisplayVerb(operation, successValue) {
        var op = String(operation || "").toLowerCase()
        if (successValue) {
            if (op === "update") return "UPDATED"
            if (op === "uninstall") return "UNINSTALLED"
            return "INSTALLED"
        }
        if (op === "update") return "FAILED TO UPDATE"
        if (op === "uninstall") return "FAILED TO UNINSTALL"
        return "FAILED TO INSTALL"
    }

    function failureStorageDetails(item) {
        if (!item) return ""
        var available = Number(item.availableBytes || 0)
        var required = Number(item.installedBytes || item.sizeBytes || item.size || 0)
        if (!backend || (available <= 0 && required <= 0)) return ""
        var parts = []
        if (available > 0) parts.push("AVAILABLE STORAGE: " + backend.formatBytes(available))
        if (required > 0) parts.push("PACKAGE REQUIREMENT: " + backend.formatBytes(required))
        return parts.join("  •  ")
    }

    function operationFailureInfo(reason, item, operation) {
        var raw = String(reason || "").trim()
        var value = raw.toLowerCase()
        var info = {
            code: "PACKAGE_TRANSACTION_FAILED",
            stage: "PACKAGE TRANSACTION",
            solution: "Retry once. If it fails again, use the exact reason and error code shown here and inspect journalctl -u neutronos.service -b for the matching transaction.",
            details: ""
        }
        var storage = failureStorageDetails(item)

        if (value.indexOf("outside app store managed storage") >= 0 || value.indexOf("managed storage") >= 0) {
            info.code = "APPSTORE_MANAGED_PATH_REJECTED"
            info.stage = "PRIVILEGED INSTALLATION"
            info.solution = "Repair the App Store managed-storage/privileged staging policy and retry. No disk cleanup is required."
            info.details = storage
        } else if (value.indexOf("no space") >= 0 || value.indexOf("not enough free storage") >= 0 || value.indexOf("disk full") >= 0) {
            info.code = "APPSTORE_INSUFFICIENT_STORAGE"
            info.stage = "STORAGE PREFLIGHT"
            info.solution = "Free enough space to satisfy the package requirement plus the App Store safety margin, then retry."
            info.details = storage
        } else if (value.indexOf("checksum") >= 0 || value.indexOf("sha-256") >= 0 || value.indexOf("sha256") >= 0) {
            info.code = "PACKAGE_CHECKSUM_MISMATCH"
            info.stage = "PACKAGE VERIFICATION"
            info.solution = "Refresh the catalog and download the package again. If the digest still differs, the repository package/catalog must be republished together."
        } else if (value.indexOf("signature") >= 0 || value.indexOf("signing key") >= 0 || value.indexOf("not trusted") >= 0 || value.indexOf("public key") >= 0) {
            info.code = "PACKAGE_SIGNATURE_REJECTED"
            info.stage = "TRUST VERIFICATION"
            info.solution = "Verify the catalog and package manifest were signed by the installed NeutronOS release key and that the package files match their authenticated hashes."
        } else if (value.indexOf("compatible") >= 0 || value.indexOf("requires neutronos") >= 0 || value.indexOf("developer mode") >= 0 || value.indexOf("protected built-in") >= 0) {
            info.code = "PACKAGE_COMPATIBILITY_REJECTED"
            info.stage = "COMPATIBILITY PREFLIGHT"
            info.solution = "Resolve the exact NeutronOS version, architecture, Developer Mode, or package-id compatibility requirement shown above, then retry."
            info.details = storage
        } else if (value.indexOf("network") >= 0 || value.indexOf("download") >= 0 || value.indexOf("connection") >= 0 || value.indexOf("host") >= 0 || value.indexOf("https") >= 0 || value.indexOf("ssl") >= 0 || value.indexOf("tls") >= 0) {
            info.code = "PACKAGE_DOWNLOAD_FAILED"
            info.stage = "PACKAGE DOWNLOAD"
            info.solution = "Verify repository reachability, DNS/TLS, and the package URL, then retry. The local package transaction has not completed."
        } else if (value.indexOf("dependency") >= 0 || value.indexOf("apt") >= 0 || value.indexOf("dpkg") >= 0 || value.indexOf("required executable is missing") >= 0) {
            info.code = "PACKAGE_DEPENDENCY_FAILED"
            info.stage = "DEPENDENCY INSTALLATION"
            info.solution = "Resolve the exact missing dependency or package-manager failure shown above, then retry the package transaction."
        } else if (value.indexOf("reserved for neutronos security") >= 0 || value.indexOf("security-reserved") >= 0 || value.indexOf("unsafe privileged system destination") >= 0 || value.indexOf("source/ownership mismatch") >= 0) {
            info.code = "PACKAGE_SECURITY_POLICY_REJECTED"
            info.stage = "SECURITY POLICY"
            info.solution = "The signed package requests a protected destination or authority. Correct the package manifest/system files and sign a new package; do not bypass this policy."
        } else if (value.indexOf("permission denied") >= 0 || value.indexOf("operation not permitted") >= 0 || value.indexOf("root required") >= 0) {
            info.code = "PRIVILEGED_TRANSACTION_DENIED"
            info.stage = "PRIVILEGED INSTALLATION"
            info.solution = "Repair the App Store privileged-helper permissions/policy for this exact operation, then retry. Do not weaken unrelated system permissions."
        } else if (value.indexOf("another package transaction") >= 0) {
            info.code = "PACKAGE_TRANSACTION_BUSY"
            info.stage = "TRANSACTION LOCK"
            info.solution = "Wait for the active package transaction to finish, then retry."
        } else if (value.indexOf("unable to start package transaction helper") >= 0 || value.indexOf("privileged helper") >= 0) {
            info.code = "PACKAGE_HELPER_UNAVAILABLE"
            info.stage = "TRANSACTION HELPER"
            info.solution = "Verify the App Store helper and privileged helper are present/executable, then retry. If needed inspect the NeutronOS service journal for the helper launch error."
        } else if (value.indexOf("package was not found") >= 0 || value.indexOf("unknown package") >= 0 || value.indexOf("package url is missing") >= 0 || value.indexOf("invalid catalog entry") >= 0) {
            info.code = "CATALOG_PACKAGE_UNRESOLVED"
            info.stage = "CATALOG RESOLUTION"
            info.solution = "Refresh the App Store catalog. If the package still cannot be resolved, repair its repository catalog entry."
        } else if (value.indexOf("invalid neutronos package") >= 0 || value.indexOf("invalid napp") >= 0 || value.indexOf("manifest") >= 0 || value.indexOf("archive") >= 0) {
            info.code = "PACKAGE_FORMAT_INVALID"
            info.stage = "PACKAGE INSPECTION"
            info.solution = "Rebuild the .Napp with a valid manifest and required packaged resources, sign the rebuilt bytes, then republish it."
        } else if (value.indexOf("rollback") >= 0) {
            info.code = "PACKAGE_ROLLBACK_FAILED"
            info.stage = "ROLLBACK"
            info.solution = "Do not retry blindly. Inspect the exact rollback reason and NeutronOS journal, then repair the affected package transaction state before another install/update."
        } else if (value.indexOf("no update is available") >= 0) {
            info.code = "PACKAGE_UPDATE_NOT_AVAILABLE"
            info.stage = "UPDATE PREFLIGHT"
            info.solution = "Refresh the catalog and verify the installed and available package versions before trying again."
        }
        return info
    }

    function operationSolution(reason) {
        return operationFailureInfo(reason, detailPackage(), confirmOperation).solution
    }

    function showOperationResult(operation, successValue, message, item) {
        var packageItem = item || detailPackage()
        resultOperation = String(operation || confirmOperation || "install")
        resultSuccess = !!successValue
        if (packageItem && packageItem.id) {
            resultPackageName = String(packageItem.name || packageItem.id)
            resultPackageVersion = String(packageItem.version || "")
        } else if (!resultPackageName.length) {
            resultPackageName = backend ? String(backend.activePackageId || "PACKAGE") : "PACKAGE"
        }
        resultReason = resultSuccess ? "" : String(message || (backend ? backend.lastError : "") || "The package transaction did not complete.")
        var failure = resultSuccess ? ({ code: "", stage: "", solution: "", details: "" }) : operationFailureInfo(resultReason, packageItem, resultOperation)
        resultErrorCode = String(failure.code || "")
        resultStage = String(failure.stage || "")
        resultSolution = String(failure.solution || "")
        resultDetails = String(failure.details || "")
        toastText = String(message || "")
        statusIsOperationResult = true
        statusOpen = true
    }

    function displayStartupResume() {
        if (!backend || !backend.startupResume || backend.startupResume.pending !== true)
            return true
        var resume = backend.startupResume || ({})
        var id = String(resume.packageId || "")
        if (!id.length)
            return true

        try { backend.reload() } catch (reloadError) { }
        refreshVisiblePackages()
        var item = ({})
        try { item = backend.packageById(id) || ({}) } catch (lookupError) { item = ({}) }
        if (!item || !item.id)
            item = ({ id:id, name:id, version:String(resume.version || "") })

        tabIndex = 2
        refreshVisiblePackages()
        for (var i = 0; i < visiblePackages.length; ++i) {
            if (String(visiblePackages[i].id || "") === id) {
                packageIndex = i
                break
            }
        }
        packageEngaged = true
        focusZone = 2
        resultPackageName = String(item.name || id)
        resultPackageVersion = String(resume.version || item.version || "")
        showOperationResult(String(resume.operation || "install"), true,
                            String(resume.message || "Rebuild completed and the package is active."), item)
        if (typeof backend.clearStartupResume === "function")
            backend.clearStartupResume()
        return true
    }

    function openConfirmation(operation) {
        var item = detailPackage()
        if (!item || !item.id || (backend && backend.busy)) return
        confirmOperation = operation
        selectedFootprint = backend ? backend.installFootprint(item.id) : ({})
        selectedUninstallPlan = (operation === "uninstall" && backend) ? backend.uninstallPlan(item.id) : ({})
        confirmOpen = true
    }

    function performConfirmedOperation() {
        var item = detailPackage()
        var started = false
        if (!backend || !item || !item.id) return
        resultOperation = confirmOperation
        resultPackageName = String(item.name || item.id)
        resultPackageVersion = String(item.version || "")
        if (confirmOperation === "install") started = backend.installPackage(item.id)
        else if (confirmOperation === "update") started = backend.updatePackage(item.id)
        else if (confirmOperation === "uninstall") started = backend.uninstallPackage(item.id)
        confirmOpen = false
        if (!started) {
            var reason = backend ? String(backend.lastError || backend.statusMessage || "Operation could not start") : "Operation could not start"
            showOperationResult(confirmOperation, false, reason, item)
        }
    }

    function activateAction() {
        var item = detailPackage()
        var action = primaryPackageAction(item)
        if (!action || !action.id) return
        actionIndex = 0
        openConfirmation(action.id)
    }

    function openKeyboard(purpose, initialText) {
        keyboardPurpose = purpose
        keyboardBuffer = String(initialText || "")
        keyboardOpen = true
        virtualKeyboard.openKeyboard()
    }

    function appendKeyboard(value) {
        if (value === "SPACE") value = " "
        keyboardBuffer += value
    }

    function finishKeyboard() {
        if (keyboardPurpose === "search") {
            searchText = keyboardBuffer
            packageEngaged = false
            refreshVisiblePackages()
        } else if (keyboardPurpose === "manual") {
            if (backend && keyboardBuffer.length > 0) {
                analyzedPackagePath = keyboardBuffer
                var analysis = backend.analyzeLocalPackage(keyboardBuffer)
                if (analysis && analysis.classification) {
                    analysisActionIndex = analysis.classification === "DANGEROUS" ? 1 : 0
                    analysisOpen = true
                } else {
                    openNotice(backend.statusMessage)
                }
            }
        } else if (keyboardPurpose === "repository") {
            var parts = keyboardBuffer.split("|")
            if (backend && parts.length >= 3) {
                if (!backend.addRepository(parts[0], parts[1], parts[2])) {
                    openNotice(backend.statusMessage)
                }
            }
        }
        keyboardOpen = false
        keyboardPurpose = ""
    }

    function handleControllerPressed(action) {
        if (!hostActive) return false
        var value = normalizeAction(action)

        if (screenshotPreviewOpen) {
            screenshotPreviewOpen = false
            screenshotPreviewSource = ""
            return true
        }

        if (keyboardOpen) {
            if (value === "cancel") { keyboardOpen = false; keyboardPurpose = "" }
            return true
        }
        if (analysisOpen) {
            if (value === "left") analysisActionIndex = Math.max(0, analysisActionIndex - 1)
            else if (value === "right") analysisActionIndex = Math.min(2, analysisActionIndex + 1)
            else if (value === "cancel") analysisOpen = false
            else if (value === "primary") {
                if (analysisActionIndex === 0) {
                    if (backend.lastSecurityAnalysis.classification !== "DANGEROUS") backend.installLocalPackage(analyzedPackagePath)
                } else if (analysisActionIndex === 1 && securityBackend) {
                    securityBackend.quarantineAppPackage(analyzedPackagePath)
                } else if (analysisActionIndex === 2) backend.removeAnalyzedPackage(analyzedPackagePath)
                analysisOpen = false
            }
            return true
        }
        if (statusOpen) { if (value === "cancel") statusOpen = false; return true }
        if (backend && backend.rebuilding)
            return true
        if (backend && backend.busy &&
                (String(backend.activeOperation) === "install" || String(backend.activeOperation) === "update"))
            return true
        if (confirmOpen) {
            if (value === "primary") performConfirmedOperation()
            else if (value === "cancel") confirmOpen = false
            return true
        }
        if (exitOpen) return referenceExitModal.handleController(value)
        if (repositoriesOpen) {
            var repositories = backend ? backend.repositories : []
            if (value === "up") repositoryIndex = Math.max(0, repositoryIndex - 1)
            else if (value === "down") repositoryIndex = Math.min(Math.max(0, repositories.length - 1), repositoryIndex + 1)
            else if (value === "cancel" || value === "start") repositoriesOpen = false
            else if (value === "primary" && repositories.length) {
                var repository = repositories[repositoryIndex]
                backend.setRepositoryEnabled(repository.id, !repository.enabled)
            } else if (value === "square" && repositories.length && developerModeEnabled) {
                var selected = repositories[repositoryIndex]
                backend.setRepositoryTrusted(selected.id, !selected.trusted)
            } else if (value === "triangle" && developerModeEnabled) {
                openKeyboard("repository", "Gemini Repository|https://raw.githubusercontent.com/OGDrNeutron/NeutronOS/main/Apps/Gemini/index.json|release-key")
            } else if (value === "r1" && repositories.length && developerModeEnabled) {
                var removable = repositories[repositoryIndex]
                if (!backend.removeRepository(removable.id)) {
                    openNotice("The official repository cannot be removed.")
                } else {
                    repositoryIndex = Math.max(0, Math.min(repositoryIndex, backend.repositories.length - 1))
                }
            }
            return true
        }

        if (value === "cancel") { exitOpen = true; referenceExitModal.openModal(root); return true }
        if (value === "start") { repositoriesOpen = true; repositoryIndex = 0; return true }
        if (value === "r3") { openKeyboard("search", searchText); return true }
        if (value === "triangle") {
            if (developerModeEnabled) openKeyboard("manual", backend.manualPackageDirectory() + "/")
            else { openNotice("Developer Mode is required for manual packages.") }
            return true
        }
        if (value === "square") {
            if (focusZone === 2) {
                activateAction()
            } else {
                selectTab(tabIndex === 1 ? 0 : 1)
                focusZone = 0
            }
            return true
        }
        if (focusZone === 3) {
            if (value === "primary") { exitOpen = true; referenceExitModal.openModal(root) }
            else if (value === "down") focusZone = 0
            return true
        }

        if (focusZone === 0) {
            if (value === "left") selectTab(tabIndex - 1)
            else if (value === "right") selectTab(tabIndex + 1)
            else if (value === "up") focusZone = 3
            else if (value === "down" || value === "primary") {
                if (visiblePackages.length > 0) {
                    if (packageEngaged && contentReturnZone === 2) focusZone = 2
                    else {
                        focusZone = 1
                        contentReturnZone = 1
                        packageEngaged = true
                    }
                }
            }
            return true
        }

        if (focusZone === 1) {
            if (value === "up") {
                if (packageIndex > 0) packageIndex--
                else {
                    focusZone = 0
                    contentReturnZone = 1
                    packageEngaged = visiblePackages.length > 0
                }
            } else if (value === "down") {
                packageIndex = Math.min(Math.max(0, visiblePackages.length - 1), packageIndex + 1)
                packageEngaged = visiblePackages.length > 0
            } else if (value === "right" || value === "primary") {
                if (currentPackage() && currentPackage().id) {
                    focusZone = 2
                    contentReturnZone = 2
                    actionIndex = 0
                }
            }
            packageList.positionViewAtIndex(packageIndex, ListView.Contain)
            refreshFootprint()
            return true
        }

        if (focusZone === 2) {
            if (value === "cancel") {
                screenshotFocusActive = false
                focusZone = 1
                contentReturnZone = 1
            } else if (screenshotFocusActive && screenshotGrid && screenshotGrid.shotCount > 0) {
                var shotCount = screenshotGrid.shotCount
                var columns = Math.max(1, screenshotGrid.columns)
                var oldScreenshotIndex = screenshotIndex
                if (value === "left") {
                    if ((screenshotIndex % columns) > 0) screenshotIndex--
                } else if (value === "right") {
                    if ((screenshotIndex % columns) < columns - 1 && screenshotIndex + 1 < shotCount) screenshotIndex++
                } else if (value === "down") {
                    if (screenshotIndex + columns < shotCount) screenshotIndex += columns
                    else if (screenshotIndex + 1 < shotCount) screenshotIndex++
                } else if (value === "up") {
                    if (screenshotIndex - columns >= 0) screenshotIndex -= columns
                    else {
                        screenshotFocusActive = false
                        scrollDetail(-Math.max(120, detailFlick.height * 0.28))
                    }
                } else if (value === "primary") {
                    openSelectedScreenshot()
                } else if (value === "l1") {
                    screenshotFocusActive = false
                    scrollDetail(-Math.max(240, detailFlick.height * 0.78))
                } else if (value === "r1") {
                    screenshotFocusActive = false
                    scrollDetail(Math.max(240, detailFlick.height * 0.78))
                }
                if (screenshotFocusActive && screenshotIndex !== oldScreenshotIndex)
                    ensureSelectedScreenshotVisible()
            } else if (value === "left") {
                focusZone = 1
                contentReturnZone = 1
            } else if (value === "up") {
                if (detailFlick.contentY <= 8) {
                    focusZone = 0
                    contentReturnZone = 2
                } else scrollDetail(-Math.max(120, detailFlick.height * 0.28))
            } else if (value === "down") {
                scrollDetail(Math.max(120, detailFlick.height * 0.28))
            } else if (value === "l1") {
                scrollDetail(-Math.max(240, detailFlick.height * 0.78))
            } else if (value === "r1") {
                scrollDetail(Math.max(240, detailFlick.height * 0.78))
            } else if (value === "right" && screenshotSectionActive()) {
                screenshotIndex = 0
                screenshotFocusActive = true
                ensureSelectedScreenshotVisible()
            } else if (value === "primary") {
                activateAction()
            }
            return true
        }
        return true
    }

    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return true }
    function prepareForUnload() { }

    onAppDataChanged: capturePackagePreselection()
    onPackageIndexChanged: { screenshotIndex = 0; screenshotFocusActive = false; resetDetailScroll(); if (packageEngaged) loadChangelog() }
    onTabIndexChanged: { resetDetailScroll(); loadChangelog() }
    onPackageEngagedChanged: { if (packageEngaged) { resetDetailScroll(); loadChangelog() } }

    Timer {
        id: startupResumeTimer
        interval: 350
        repeat: false
        onTriggered: {
            root.startupResumeAttempts += 1
            if (!root.displayStartupResume() && root.startupResumeAttempts < 12)
                restart()
        }
    }

    Component.onCompleted: {
        forceActiveFocus()
        if (securityBackend && typeof securityBackend.refresh === "function") securityBackend.refresh()
        if (backend) backend.refreshCatalog()
        refreshVisiblePackages()
        capturePackagePreselection()
        loadChangelog()
        if (backend && backend.startupResume && backend.startupResume.pending === true)
            startupResumeTimer.restart()
    }

    Connections {
        target: backend
        ignoreUnknownSignals: true
        function onCatalogChanged() { root.refreshVisiblePackages(); if (root.pendingPreselectPackageId.length) Qt.callLater(root.tryApplyPackagePreselection); if (root.packageEngaged) root.loadChangelog() }
        function onOperationFinished(packageId, operation, success, message) {
            var item = root.detailPackage()
            if (!item || !item.id || String(item.id) !== String(packageId))
                item = ({ id: packageId, name: root.resultPackageName.length ? root.resultPackageName : packageId, version: root.resultPackageVersion })
            root.showOperationResult(operation, success, message, item)
            root.refreshVisiblePackages()
        }
    }

    Rectangle { anchors.fill: parent; color: root.background }
    Image {
        anchors.fill: parent
        source: root.assetBackend ? root.assetBackend.themeFile("background.png")
                                  : Qt.resolvedUrl("../../../themes/Default/background.png")
        fillMode: Image.PreserveAspectCrop
        opacity: 0.20
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#92050711" }
            GradientStop { position: 0.55; color: "#42091422" }
            GradientStop { position: 1.0; color: "#c0050711" }
        }
    }

    Shared.ReferenceAppHeader {
        id: referenceHeader
        x: 18
        width: parent.width - 36
        anchors.top: parent.top
        z: 50
        appTitle: "App Store"
        primaryStatus: root.securityProtected ? "Secure" : "Attention"
        primaryTone: root.securityProtected ? "success" : "danger"
        secondaryStatus: root.repositoryConnected ? "Connected" : "Disconnected"
        secondaryTone: root.repositoryConnected ? "success" : "danger"
        attention: !root.securityProtected
        menuFocused: root.focusZone === 3 && !root.exitOpen
        onMenuRequested: { root.exitOpen = true; referenceExitModal.openModal(root) }
    }

    Shared.ReferenceAppFooter {
        id: referenceFooter
        x: 18
        width: parent.width - 36
        anchors.bottom: parent.bottom
        z: 50
    }

    Item {
        id: workspace
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: referenceHeader.bottom
        anchors.bottom: referenceFooter.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 12
        anchors.bottomMargin: 12

        Rectangle {
            id: topTabBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 66
            color: "transparent"
            border.width: 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.focusZone === 0 ? "#5B7DF9FF" : "#30475C"
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: 34
                Repeater {
                    model: root.topTabs
                    Item {
                        required property int index
                        required property string modelData
                        width: 230
                        height: 64

                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: activeTabLine.top
                            anchors.bottomMargin: 9
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.toUpperCase()
                                color: root.tabIndex === index ? root.textPrimary : root.textSecondary
                                font.pixelSize: Math.round((root.tabIndex === index ? 15 : 13.5) * root.textScale)
                                font.bold: true
                                font.letterSpacing: 1.5
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: index === 0 ? "Browse catalog" : index === 1 ? "Available upgrades" : "Installed library"
                                color: root.tabIndex === index ? (index === 1 ? root.warning : index === 2 ? root.success : root.cyan) : root.textMuted
                                font.pixelSize: Math.round(8.5 * root.textScale)
                                font.bold: true
                            }
                        }

                        Rectangle {
                            id: activeTabLine
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            height: root.tabIndex === index ? 5 : 2
                            radius: height / 2
                            color: root.tabIndex === index ? (index === 1 ? root.warning : index === 2 ? root.success : root.focusBlue) : "#263C50"
                            opacity: root.focusZone === 0 && root.tabIndex === index ? 1.0 : root.tabIndex === index ? 0.82 : 0.55
                        }

                        Rectangle {
                            visible: root.focusZone === 0 && root.tabIndex === index
                            anchors.horizontalCenter: activeTabLine.horizontalCenter
                            anchors.verticalCenter: activeTabLine.verticalCenter
                            width: activeTabLine.width + 26
                            height: 16
                            radius: 8
                            color: "transparent"
                            border.width: 2
                            border.color: activeTabLine.color
                            opacity: 0.45
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.selectTab(index); root.focusZone = 0 }
                        }
                    }
                }
            }
        }

        Item {
            id: bodyPanels
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topTabBar.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 0

            Rectangle {
                id: packagePanel
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(300, parent.width * 0.184)
                radius: 30
                color: "#EE09131F"
                border.width: root.focusZone === 1 ? 2 : 1
                border.color: root.focusZone === 1 ? root.focusBlue : "#31475C"
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: root.focusZone === 1 ? 3 : 1
                    color: root.focusZone === 1 ? root.focusBlue : "#213246"
                }

                Item {
                    id: listHeader
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 82

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: root.tabName().toUpperCase()
                            color: root.textPrimary
                            font.pixelSize: Math.round(18 * root.textScale)
                            font.bold: true
                            font.letterSpacing: 1.5
                        }
                        Text {
                            text: root.tabIndex === 0 ? "Official NeutronOS apps" : root.tabIndex === 1 ? "Apps ready to update" : "Installed from the store"
                            color: root.textMuted
                            font.pixelSize: Math.round(10 * root.textScale)
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(46, listCount.implicitWidth + 22)
                        height: 34
                        radius: 17
                        color: "#17283A"
                        border.width: 1
                        border.color: "#3A6179"
                        Text {
                            id: listCount
                            anchors.centerIn: parent
                            text: String(root.visiblePackages.length)
                            color: root.cyan
                            font.pixelSize: Math.round(12 * root.textScale)
                            font.bold: true
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: "#2B4054"
                    }
                }

                ListView {
                    id: packageList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: listHeader.bottom
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    spacing: 10
                    clip: true
                    model: root.visiblePackages
                    currentIndex: root.packageIndex

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: packageList.width
                        height: 116
                        radius: height / 2
                        color: root.packageIndex === index && root.packageEngaged ? "#26364D65" : "#141C2939"
                        border.width: root.focusZone === 1 && root.packageIndex === index ? 2 : 1
                        border.color: root.focusZone === 1 && root.packageIndex === index ? root.focusBlue :
                                      root.packageIndex === index && root.packageEngaged ? "#557DF9FF" : "#2A4156"
                        clip: true

                        Rectangle {
                            visible: root.packageIndex === index && root.packageEngaged
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 5
                            color: root.focusBlue
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Rectangle {
                                width: 78
                                height: 78
                                radius: height / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#18283A"
                                border.width: 1
                                border.color: root.packageIndex === index && root.packageEngaged ? "#4A7794" : "#314E66"
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    source: root.assetSource(modelData.icon || modelData.id, modelData.id, "icon")
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                            }

                            Item {
                                width: parent.width - 90
                                height: parent.height

                                Rectangle {
                                    id: updatePillGlow
                                    visible: root.packagePillTone(modelData) === "warning"
                                    anchors.centerIn: rowPill
                                    width: rowPill.width + 12
                                    height: rowPill.height + 12
                                    radius: height / 2
                                    color: "#20FFC857"
                                    border.width: 3
                                    border.color: root.warning
                                    opacity: 0.34
                                    z: 1

                                    SequentialAnimation on opacity {
                                        running: updatePillGlow.visible
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.95; duration: 720; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 0.34; duration: 720; easing.type: Easing.InOutQuad }
                                    }
                                }

                                Rectangle {
                                    id: rowPill
                                    anchors.right: parent.right
                                    z: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(116, rowPillText.implicitWidth + 32)
                                    height: 42
                                    radius: 21
                                    color: root.packagePillTone(modelData) === "warning" ? "#D9A31E" :
                                           root.packagePillTone(modelData) === "danger" ? "#D83A4E" : "#18AD68"
                                    border.width: 1
                                    border.color: "#55FFFFFF"
                                    Text {
                                        id: rowPillText
                                        anchors.centerIn: parent
                                        text: root.packagePillLabel(modelData)
                                        color: "#FFFFFF"
                                        font.pixelSize: Math.round(12 * root.textScale)
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                    }
                                }

                                Text {
                                    id: rowTitle
                                    anchors.left: parent.left
                                    anchors.right: rowPill.left
                                    anchors.rightMargin: 12
                                    anchors.top: parent.top
                                    anchors.topMargin: 17
                                    text: modelData.name || modelData.id
                                    color: root.textPrimary
                                    font.pixelSize: Math.round(16 * root.textScale)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: rowPill.left
                                    anchors.rightMargin: 12
                                    anchors.top: rowTitle.bottom
                                    anchors.topMargin: 7
                                    text: (modelData.developer || "NeutronOS") + "  •  v" + (modelData.version || "0.0.0")
                                    color: root.textSecondary
                                    font.pixelSize: Math.round(10.5 * root.textScale)
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                root.packageIndex = index
                                root.packageEngaged = true
                                root.focusZone = 1
                                root.contentReturnZone = 1
                                root.actionIndex = 0
                                root.screenshotIndex = 0
                                root.refreshFootprint()
                                root.loadChangelog()
                            }
                            onClicked: {
                                root.packageIndex = index
                                root.packageEngaged = true
                                root.focusZone = 1
                                root.contentReturnZone = 1
                                root.refreshFootprint()
                                root.loadChangelog()
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.visiblePackages.length === 0
                        width: parent.width - 28
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.tabIndex === 1 ? "NO UPDATES AVAILABLE" :
                              root.tabIndex === 2 ? "NO INSTALLED STORE PACKAGES" :
                              "NO PACKAGES AVAILABLE"
                        color: root.textSecondary
                        font.pixelSize: Math.round(14 * root.textScale)
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }
            }

            Rectangle {
                id: detailPanel
                anchors.left: packagePanel.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: 30
                color: "#F009131F"
                border.width: root.focusZone === 2 ? 2 : 1
                border.color: root.focusZone === 2 ? root.focusBlue : "#31475C"
                clip: true
                property var item: root.detailPackage()
                property var primaryAction: root.primaryPackageAction(item)

                Rectangle {
                    id: primaryActionButton
                    visible: !!(detailPanel.item && detailPanel.item.id && detailPanel.primaryAction && detailPanel.primaryAction.id)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    anchors.bottomMargin: 16
                    height: 72
                    radius: height / 2
                    color: detailPanel.primaryAction.tone === "warning" ? "#D5A31B" :
                           detailPanel.primaryAction.tone === "danger" ? "#D73C50" : "#17A968"
                    border.width: root.focusZone === 2 ? 3 : 1
                    border.color: root.focusZone === 2 ? root.focusBlue : "#66FFFFFF"
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: "#AAFFFFFF"
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 16
                        Text {
                            text: backend && backend.busy && String(backend.activePackageId) === String(detailPanel.item.id)
                                  ? String(backend.activeOperation || "WORKING").toUpperCase() + "…"
                                  : String(detailPanel.primaryAction.label || "").toUpperCase()
                            color: "#FFFFFF"
                            font.pixelSize: Math.round(18 * root.textScale)
                            font.bold: true
                            font.letterSpacing: 1.4
                        }
                        Rectangle { width: 1; height: 28; anchors.verticalCenter: parent.verticalCenter; color: "#66FFFFFF" }
                        Text {
                            text: backend && backend.busy ? String(backend.statusMessage || "Working") : "SIGNED PACKAGE  •  PRESS □ FOR ACTION"
                            color: "#F2FFFFFF"
                            font.pixelSize: Math.round(10 * root.textScale)
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !backend || !backend.busy
                        onClicked: { root.focusZone = 2; root.contentReturnZone = 2; root.activateAction() }
                    }
                }

                Item {
                    id: defaultStorePage
                    anchors.fill: parent
                    anchors.margins: 32
                    visible: !detailPanel.item.id

                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 70, 900)
                        spacing: 20

                        Text {
                            width: parent.width
                            text: "NEUTRONOS SOFTWARE LIBRARY"
                            color: root.cyan
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Math.round(11 * root.textScale)
                            font.bold: true
                            font.letterSpacing: 2.4
                        }

                        Text {
                            width: parent.width
                            text: "SELECT AN APP"
                            color: root.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Math.round(34 * root.textScale)
                            font.bold: true
                            font.letterSpacing: 1.0
                        }

                        Text {
                            width: Math.min(parent.width, 760)
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.tabIndex === 0
                                  ? "Browse the official signed catalog, then open an app to review storage, permissions, changelog and screenshots."
                                  : root.tabIndex === 1
                                    ? "Select an available update to review exactly what is changing before the package is applied."
                                    : "Select an installed app to review its package details, release history and available actions."
                            color: root.textSecondary
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            lineHeight: 1.2
                            font.pixelSize: Math.round(15 * root.textScale)
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 14

                            Repeater {
                                model: [
                                    { label: "SIGNED", tone: root.success },
                                    { label: "DEPENDENCY-AWARE", tone: root.cyan },
                                    { label: "TRANSACTIONAL", tone: root.purple }
                                ]
                                Rectangle {
                                    required property var modelData
                                    width: Math.max(170, emptyBadgeText.implicitWidth + 44)
                                    height: 54
                                    radius: height / 2
                                    color: "#121C2A3A"
                                    border.width: 1
                                    border.color: modelData.tone
                                    Text {
                                        id: emptyBadgeText
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: modelData.tone
                                        font.pixelSize: Math.round(10.5 * root.textScale)
                                        font.bold: true
                                        font.letterSpacing: 1.0
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: Math.min(parent.width, 720)
                            height: 76
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: height / 2
                            color: root.focusZone === 1 ? "#172C4158" : "#10182535"
                            border.width: root.focusZone === 1 ? 2 : 1
                            border.color: root.focusZone === 1 ? root.focusBlue : "#34526A"

                            Row {
                                anchors.centerIn: parent
                                spacing: 14
                                Text {
                                    text: "←"
                                    color: root.focusBlue
                                    font.pixelSize: Math.round(21 * root.textScale)
                                    font.bold: true
                                }
                                Text {
                                    text: "CHOOSE AN APP FROM " + root.tabName().toUpperCase()
                                    color: root.textPrimary
                                    font.pixelSize: Math.round(12 * root.textScale)
                                    font.bold: true
                                    font.letterSpacing: 1.0
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: detailFlick
                    visible: !!(detailPanel.item && detailPanel.item.id)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: primaryActionButton.visible ? primaryActionButton.top : parent.bottom
                    anchors.leftMargin: 22
                    anchors.rightMargin: 14
                    anchors.topMargin: 22
                    anchors.bottomMargin: primaryActionButton.visible ? 16 : 22
                    clip: true
                    contentWidth: width
                    contentHeight: detailColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    onContentYChanged: {
                        var movingDown = contentY > root.lastDetailContentY + 1
                        var screenshotsVisible = root.screenshotSectionActive()
                        if (movingDown && screenshotsVisible && !root.screenshotFocusActive && screenshotGrid.shotCount > 0) {
                            root.screenshotIndex = 0
                            root.screenshotFocusActive = true
                            root.ensureSelectedScreenshotVisible()
                        } else if (!screenshotsVisible) {
                            root.screenshotFocusActive = false
                        }
                        root.lastDetailContentY = contentY
                    }
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 10
                        contentItem: Rectangle {
                            implicitWidth: 7
                            radius: 4
                            color: root.focusZone === 2 ? root.focusBlue : "#516579"
                            opacity: 0.92
                        }
                    }

                    Column {
                        id: detailColumn
                        width: detailFlick.width - 10
                        spacing: 16

                        Item {
                            id: detailIdentity
                            width: parent.width
                            height: identityContent.implicitHeight + 18

                            Column {
                                id: identityContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 24
                                anchors.rightMargin: 24
                                spacing: 10

                                Text {
                                    width: parent.width
                                    text: String((detailPanel.item && (detailPanel.item.name || detailPanel.item.id)) || "")
                                    color: root.textPrimary
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Math.round(34 * root.textScale)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: Math.min(parent.width, 1080)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    wrapMode: Text.WordWrap
                                    text: detailPanel.item.description || "No repository description provided."
                                    color: root.textSecondary
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Math.round(16.5 * root.textScale)
                                    lineHeight: 1.20
                                }

                                Rectangle {
                                    id: compatibilityPill
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.max(260, compatibilityText.implicitWidth + 42)
                                    height: 44
                                    radius: height / 2
                                    color: detailPanel.item.compatible ? "#1E3C2E" : "#40202A"
                                    border.width: 1
                                    border.color: detailPanel.item.compatible ? root.success : root.danger
                                    Text {
                                        id: compatibilityText
                                        anchors.centerIn: parent
                                        text: detailPanel.item.compatible ? "COMPATIBLE WITH THIS DEVICE" : "INCOMPATIBLE WITH THIS DEVICE"
                                        color: detailPanel.item.compatible ? root.success : root.danger
                                        font.pixelSize: Math.round(10.5 * root.textScale)
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: (detailPanel.item.developer || "NeutronOS") + "  •  v" + (detailPanel.item.version || "0.0.0") + "  •  " + (detailPanel.item.repositoryName || "NeutronOS Official")
                                    color: root.cyan
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Math.round(10.5 * root.textScale)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            id: heroArtwork
                            width: Math.max(360, parent.width * 0.52)
                            height: width
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: 28
                            color: "#0A111B"
                            border.width: 1
                            border.color: root.focusZone === 2 ? "#4A6F8A" : "#2F4B61"
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: root.artworkSource(detailPanel.item)
                                fillMode: Image.Stretch
                                smooth: true
                                asynchronous: true
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 1
                                color: "#66FFFFFF"
                            }
                        }

                        Rectangle {
                            id: packageBar
                            width: parent.width
                            height: 142
                            radius: height / 2
                            color: "#141C2938"
                            border.width: 1
                            border.color: "#31536B"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 32
                                anchors.top: parent.top
                                anchors.topMargin: 12
                                text: "PACKAGE & STORAGE"
                                color: root.cyan
                                font.pixelSize: Math.round(10.5 * root.textScale)
                                font.bold: true
                                font.letterSpacing: 1.1
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                anchors.bottomMargin: 18
                                spacing: 12

                                Repeater {
                                    model: [
                                        { label: "PACKAGE SIZE", value: root.packageSize(detailPanel.item), tone: root.textPrimary },
                                        { label: "TOTAL DOWNLOAD", value: root.footprintText("totalDownloadBytes", "—"), tone: root.textPrimary },
                                        { label: "DISK IMPACT", value: root.diskImpactText(), tone: root.textPrimary },
                                        { label: "MISSING DEPS", value: root.footprintText("missingDependencyBytes", "—"), tone: root.warning }
                                    ]
                                    Rectangle {
                                        required property var modelData
                                        width: (parent.width - 36) / 4
                                        height: 72
                                        radius: height / 2
                                        color: "#0D1724"
                                        border.width: 1
                                        border.color: "#2B455A"
                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData.label
                                                color: root.textMuted
                                                font.pixelSize: Math.round(9 * root.textScale)
                                                font.bold: true
                                                font.letterSpacing: 0.5
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData.value
                                                color: modelData.tone
                                                font.pixelSize: Math.round(15 * root.textScale)
                                                font.bold: true
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: permissionsBar
                            width: parent.width
                            height: permissionsContent.implicitHeight + 44
                            radius: Math.min(height / 2, 46)
                            color: "#141C2938"
                            border.width: 1
                            border.color: "#56446F"

                            Column {
                                id: permissionsContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 22
                                spacing: 12

                                Row {
                                    width: parent.width
                                    Text {
                                        width: parent.width / 2
                                        text: "PERMISSIONS"
                                        color: root.purple
                                        font.pixelSize: Math.round(11 * root.textScale)
                                        font.bold: true
                                        font.letterSpacing: 1.0
                                    }
                                    Text {
                                        width: parent.width / 2
                                        text: "DEPENDENCIES"
                                        color: root.cyan
                                        font.pixelSize: Math.round(11 * root.textScale)
                                        font.bold: true
                                        font.letterSpacing: 1.0
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 24
                                    Text {
                                        width: (parent.width - 24) / 2
                                        text: root.joinedOrFallback(root.permissionItems(detailPanel.item), "No elevated permissions declared")
                                        color: root.textSecondary
                                        font.pixelSize: Math.round(12.5 * root.textScale)
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.14
                                    }
                                    Text {
                                        width: (parent.width - 24) / 2
                                        text: root.missingDependenciesText(detailPanel.item)
                                        color: root.textSecondary
                                        font.pixelSize: Math.round(12.5 * root.textScale)
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.14
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: changelogBar
                            width: parent.width
                            height: changelogContent.implicitHeight + 44
                            radius: Math.min(height / 2, 46)
                            color: "#141C2938"
                            border.width: 1
                            border.color: "#356078"

                            Column {
                                id: changelogContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 22
                                spacing: 12

                                Row {
                                    width: parent.width
                                    Text {
                                        width: parent.width - changelogVersion.implicitWidth - 16
                                        text: "CHANGELOG"
                                        color: root.cyan
                                        font.pixelSize: Math.round(11 * root.textScale)
                                        font.bold: true
                                        font.letterSpacing: 1.0
                                    }
                                    Text {
                                        id: changelogVersion
                                        text: "v" + String(detailPanel.item.version || "0.0.0")
                                        color: root.textPrimary
                                        font.pixelSize: Math.round(10.5 * root.textScale)
                                        font.bold: true
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: root.changelogText.length ? root.changelogText : "No changelog is published for this app yet."
                                    color: root.changelogLoading ? root.textMuted : root.textSecondary
                                    font.pixelSize: Math.round(12.5 * root.textScale)
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.18
                                }
                            }
                        }

                        Rectangle {
                            id: screenshotsBar
                            width: parent.width
                            height: 68
                            radius: height / 2
                            color: "#101A2837"
                            border.width: 1
                            border.color: "#2C485D"
                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                Text {
                                    width: parent.width - screenshotHint.implicitWidth - 12
                                    text: "SCREENSHOTS"
                                    color: root.cyan
                                    font.pixelSize: Math.round(11 * root.textScale)
                                    font.bold: true
                                    font.letterSpacing: 1.0
                                }
                                Text {
                                    id: screenshotHint
                                    text: "CLICK TO VIEW FULL SCREEN"
                                    color: root.textMuted
                                    font.pixelSize: Math.round(9.5 * root.textScale)
                                    font.bold: true
                                }
                            }
                        }

                        Grid {
                            id: screenshotGrid
                            width: parent.width
                            columns: 2
                            spacing: 12
                            property real shotWidth: (width - spacing) / 2
                            property int shotCount: detailPanel.item.screenshots ? Math.min(4, detailPanel.item.screenshots.length) : 0
                            Repeater {
                                model: screenshotGrid.shotCount
                                Rectangle {
                                    required property int index
                                    width: screenshotGrid.shotWidth
                                    height: width * 9 / 16
                                    radius: 34
                                    color: "#0B121D"
                                    border.width: 1
                                    border.color: "#35556B"
                                    clip: true
                                    property bool selectedShot: root.focusZone === 2 && root.screenshotFocusActive && root.screenshotIndex === index
                                    property string shotSource: root.screenshotAt(detailPanel.item, index)

                                    Image {
                                        anchors.fill: parent
                                        source: parent.shotSource
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        asynchronous: true
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: shotMouse.containsMouse ? "#1400C8FF" : "transparent"
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 10
                                        width: 34
                                        height: 34
                                        radius: 17
                                        color: "#B508111C"
                                        border.width: 1
                                        border.color: "#51758E"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "↗"
                                            color: root.textPrimary
                                            font.pixelSize: Math.round(13 * root.textScale)
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: shotMouse
                                        anchors.fill: parent
                                        z: 20
                                        hoverEnabled: true
                                        preventStealing: true
                                        acceptedButtons: Qt.LeftButton
                                        onPressed: function(mouse) { mouse.accepted = true }
                                        onClicked: function(mouse) {
                                            root.focusZone = 2
                                            root.contentReturnZone = 2
                                            root.screenshotIndex = index
                                            root.screenshotFocusActive = true
                                            root.ensureSelectedScreenshotVisible()
                                            root.openScreenshot(parent.shotSource)
                                            mouse.accepted = true
                                        }
                                    }

                                    Rectangle {
                                        id: screenshotFocusRing
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        z: 30
                                        radius: Math.max(0, parent.radius - 2)
                                        color: "transparent"
                                        border.width: 5
                                        border.color: root.focusBlue
                                        visible: parent.selectedShot
                                        opacity: 0.35

                                        SequentialAnimation on opacity {
                                            running: screenshotFocusRing.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
                                            NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: screenshotGrid.shotCount === 0
                            width: parent.width
                            height: 110
                            radius: height / 2
                            color: "#0D1622"
                            border.width: 1
                            border.color: "#2C4559"
                            Text {
                                anchors.centerIn: parent
                                text: "NO SCREENSHOTS PUBLISHED FOR THIS RELEASE"
                                color: root.textMuted
                                font.pixelSize: Math.round(11 * root.textScale)
                                font.bold: true
                                font.letterSpacing: 0.6
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 54
                            radius: height / 2
                            color: root.focusZone === 2 ? "#152D415C" : "#10131D2A"
                            border.width: 1
                            border.color: root.focusZone === 2 ? root.focusBlue : "#2C4054"
                            Text {
                                anchors.centerIn: parent
                                text: root.screenshotFocusActive ? "X  OPEN     ←→  NEAREST SCREENSHOT     ↑↓  MOVE / EXIT UP     □  PACKAGE ACTION     O  APP LIST" : "↑  TAB BAR / SCROLL UP     ↓  SCROLL     L1 / R1  PAGE     □  PACKAGE ACTION     ←  APP LIST"
                                color: root.focusZone === 2 ? root.cyan : root.textMuted
                                font.pixelSize: Math.round(10 * root.textScale)
                                font.bold: true
                                font.letterSpacing: 0.6
                            }
                        }
                        Item { width: 1; height: 8 }
                    }
                }
            }
        }
    }

    Rectangle {
        id: screenshotPreview
        anchors.fill: parent
        visible: root.screenshotPreviewOpen
        color: "#F0000308"
        z: 100

        Rectangle {
            anchors.fill: parent
            anchors.margins: 34
            radius: 18
            color: "#090D14"
            border.width: 2
            border.color: root.focusBlue

            Image {
                anchors.fill: parent
                anchors.margins: 20
                source: root.screenshotPreviewSource
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                width: screenshotCloseHint.implicitWidth + 34
                height: 42
                radius: 21
                color: "#D90A1420"
                border.width: 1
                border.color: "#4B6B82"
                Text {
                    id: screenshotCloseHint
                    anchors.centerIn: parent
                    text: "PRESS ANY BUTTON TO CLOSE"
                    color: root.textPrimary
                    font.pixelSize: Math.round(10.5 * root.textScale)
                    font.bold: true
                    font.letterSpacing: 0.8
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.screenshotPreviewOpen = false
                root.screenshotPreviewSource = ""
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: referenceFooter.top
        height: backend && backend.busy ? 6 : 0
        visible: height > 0
        color: "#17243a"
        z: 51
        Rectangle {
            width: parent.width * (backend ? backend.progress : 0)
            height: parent.height
            color: root.focusBlue
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: backend && backend.busy &&
                 (String(backend.activeOperation) === "install" ||
                  String(backend.activeOperation) === "update" ||
                  String(backend.activeOperation) === "uninstall")
        color: "#D000050B"
        z: 59

        Shared.ReferenceModalPanel {
            id: transactionPanel
            anchors.centerIn: parent
            width: Math.min(parent.width - 100, 940)
            height: Math.min(parent.height - 80, 610)
            radius: 30
            property string op: String(backend ? backend.activeOperation : "")
            property color tone: op === "uninstall" ? root.danger : op === "update" ? root.warning : root.success
            accentColor: tone

            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 14

                Text {
                    width: parent.width
                    text: transactionPanel.op === "uninstall" ? "UNINSTALLING APP" : transactionPanel.op === "update" ? "UPDATING APP" : "INSTALLING APP"
                    color: transactionPanel.tone
                    font.pixelSize: Math.round(22 * root.textScale)
                    font.bold: true
                    font.letterSpacing: 2
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: root.resultPackageName.length ? root.resultPackageName : String(backend ? backend.activePackageId : "Package")
                    color: root.textPrimary
                    font.pixelSize: Math.round(28 * root.textScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: backend && String(backend.operationStage || "").length ? String(backend.operationStage).toUpperCase() : "PACKAGE TRANSACTION"
                    color: transactionPanel.tone
                    font.pixelSize: Math.round(15 * root.textScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    height: 50
                    text: backend && String(backend.operationDetail || "").length ? String(backend.operationDetail) : String(backend ? backend.statusMessage : "Preparing package…")
                    color: root.textSecondary
                    font.pixelSize: Math.round(15 * root.textScale)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    width: parent.width
                    height: 20
                    radius: 10
                    color: "#16263A"
                    border.width: 1
                    border.color: root.border
                    clip: true
                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.max(0, Math.min(1, backend ? Number(backend.progress || 0) : 0))
                        radius: parent.radius
                        color: transactionPanel.tone
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }

                Text {
                    width: parent.width
                    text: Math.round(Math.max(0, Math.min(1, backend ? Number(backend.progress || 0) : 0)) * 100) + "%"
                    color: root.textPrimary
                    font.pixelSize: Math.round(19 * root.textScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    width: parent.width
                    height: 62
                    radius: 18
                    color: transactionPanel.op === "uninstall" ? "#281A1018" : "#24131f34"
                    border.width: 1
                    border.color: transactionPanel.op === "uninstall" ? "#60FF4050" : root.border
                    Text {
                        anchors.fill: parent
                        anchors.margins: 12
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                        text: {
                            if (transactionPanel.op === "uninstall") {
                                var count = Number(root.selectedUninstallPlan.removeCount || 0)
                                var kept = root.selectedUninstallPlan.dependenciesPreserved || []
                                return "REMOVAL PLAN  •  " + count + " package-owned items  •  Shared dependencies preserved" + (kept.length ? "\nPreserved: " + kept.join("  •  ") : "")
                            }
                            var missing = root.selectedFootprint && root.selectedFootprint.missingDependencies ? root.selectedFootprint.missingDependencies : []
                            return missing.length ? "NEW DEPENDENCIES BEING ADDED: " + missing.join("  •  ") : "DEPENDENCIES: Everything required is already installed"
                        }
                        color: transactionPanel.op === "uninstall" ? "#FFD7DC" : root.textPrimary
                        font.pixelSize: Math.round(13.5 * root.textScale)
                        font.bold: true
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 154
                    radius: 18
                    color: "#1D101A2A"
                    border.width: 1
                    border.color: root.border
                    Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8
                        Text {
                            text: transactionPanel.op === "uninstall" ? "REMOVING NOW" : "CURRENT TRANSACTION ITEMS"
                            color: transactionPanel.tone
                            font.pixelSize: Math.round(13 * root.textScale)
                            font.bold: true
                        }
                        Flickable {
                            width: parent.width
                            height: 108
                            clip: true
                            contentWidth: width
                            contentHeight: transactionItemsText.paintedHeight
                            Text {
                                id: transactionItemsText
                                width: parent.width
                                wrapMode: Text.WrapAnywhere
                                text: {
                                    var items = backend ? backend.operationItems : []
                                    return items && items.length ? items.join("\n") : "Waiting for the next verified transaction stage…"
                                }
                                color: root.textSecondary
                                font.pixelSize: Math.round(12.5 * root.textScale)
                                lineHeight: 1.15
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "DO NOT POWER OFF WHILE PACKAGE FILES ARE CHANGING"
                    color: root.danger
                    font.pixelSize: Math.round(11.5 * root.textScale)
                    font.bold: true
                    font.letterSpacing: 0.4
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: backend && backend.rebuilding
        color: "#D600050B"
        z: 61

        Shared.ReferenceModalPanel {
            anchors.centerIn: parent
            width: Math.min(parent.width - 120, 860)
            height: 470
            radius: 30
            accentColor: root.focusBlue

            Column {
                anchors.fill: parent
                anchors.margins: 38
                spacing: 20

                Text {
                    width: parent.width
                    text: "REBUILDING NEUTRONOS"
                    color: root.focusBlue
                    font.pixelSize: Math.round(25 * root.textScale)
                    font.bold: true
                    font.letterSpacing: 1.8
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: root.resultPackageName + (root.resultPackageVersion.length ? "  " + root.resultPackageVersion : "")
                    color: root.textPrimary
                    font.pixelSize: Math.round(18 * root.textScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Item {
                    width: parent.width
                    height: 92
                    Rectangle {
                        anchors.centerIn: parent
                        width: 82; height: 82; radius: 41
                        color: "#16172C3C"
                        border.width: 2
                        border.color: root.focusBlue
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: backend && backend.rebuilding
                            NumberAnimation { to: 1.0; duration: 650 }
                            NumberAnimation { to: 0.48; duration: 650 }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "⚛"
                        color: root.focusBlue
                        font.pixelSize: 62
                        font.bold: true
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 1900
                            loops: Animation.Infinite
                            running: backend && backend.rebuilding
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: backend ? String(backend.rebuildMessage || "Rebuilding NeutronOS…") : "Rebuilding NeutronOS…"
                    color: root.textSecondary
                    font.pixelSize: Math.round(14 * root.textScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 18
                    radius: 9
                    color: "#172534"
                    border.width: 1
                    border.color: root.border
                    clip: true
                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.max(0.02, Math.min(1, backend ? Number(backend.rebuildProgress || 0) : 0))
                        radius: parent.radius
                        color: root.focusBlue
                        Behavior on width { NumberAnimation { duration: 140 } }
                    }
                }
                Text {
                    width: parent.width
                    text: Math.round(Math.max(0, Math.min(1, backend ? Number(backend.rebuildProgress || 0) : 0)) * 100) + "%"
                    color: root.textPrimary
                    font.pixelSize: Math.round(17 * root.textScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 610)
                    height: 48
                    radius: 24
                    color: "#30FF4050"
                    border.width: 1
                    border.color: "#90FF4050"
                    Text {
                        anchors.centerIn: parent
                        text: "DO NOT POWER OFF  •  NEUTRONOS WILL RESTART AUTOMATICALLY"
                        color: "#FFD9DD"
                        font.pixelSize: Math.round(11.5 * root.textScale)
                        font.bold: true
                        font.letterSpacing: 0.35
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.confirmOpen
        color: "#c8000000"
        z: 60
        Shared.ReferenceModalPanel {
            id: confirmPanel
            anchors.centerIn: parent
            width: Math.min(parent.width - 90, 960)
            height: Math.min(parent.height - 70, 730)
            radius: 30
            accentColor: root.confirmOperation === "uninstall" ? root.danger : root.confirmOperation === "update" ? root.warning : root.success
            property var item: root.detailPackage()
            property color tone: root.confirmOperation === "uninstall" ? root.danger : root.confirmOperation === "update" ? root.warning : root.success

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: actionRow.top
                anchors.margins: 30
                anchors.bottomMargin: 18
                spacing: 12

                Text {
                    width: parent.width
                    text: root.confirmOperation.toUpperCase()
                    color: confirmPanel.tone
                    font.pixelSize: Math.round(20 * root.textScale)
                    font.bold: true
                    font.letterSpacing: 2.2
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: (confirmPanel.item.name || "PACKAGE") + (confirmPanel.item.version ? "  " + String(confirmPanel.item.version) : "")
                    color: root.textPrimary
                    font.pixelSize: Math.round(29 * root.textScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 160; height: 4; radius: 2; color: confirmPanel.tone }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: root.confirmOperation === "update"
                          ? "Review exactly what this update adds before the signed transaction begins. The current version remains protected by transactional rollback."
                          : root.confirmOperation === "uninstall"
                            ? "This removes only the exact files and state owned by this App Store package. Shared Debian dependencies are preserved rather than blindly removed."
                            : "Review exactly what will be added. Package bytes and trusted signature are verified before any files change."
                    color: root.textSecondary
                    font.pixelSize: Math.round(15.5 * root.textScale)
                }

                Rectangle {
                    width: parent.width
                    height: root.confirmOperation === "uninstall" ? 282 : 132
                    radius: 20
                    color: root.confirmOperation === "uninstall" ? "#2A1D111A" : "#24131f34"
                    border.width: 1
                    border.color: root.confirmOperation === "uninstall" ? "#70FF4050" : root.border
                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 7
                        Text {
                            text: root.confirmOperation === "uninstall" ? "PACKAGE-OWNED ITEMS TO REMOVE" : "DEPENDENCIES"
                            color: root.confirmOperation === "uninstall" ? root.danger : root.cyan
                            font.pixelSize: Math.round(13.5 * root.textScale)
                            font.bold: true
                        }
                        Flickable {
                            width: parent.width
                            height: root.confirmOperation === "uninstall" ? 224 : 82
                            clip: true
                            contentWidth: width
                            contentHeight: confirmationPlanText.paintedHeight
                            Text {
                                id: confirmationPlanText
                                width: parent.width
                                wrapMode: Text.WrapAnywhere
                                text: {
                                    if (root.confirmOperation === "uninstall") {
                                        var removing = root.selectedUninstallPlan.removeItems || []
                                        return removing.length ? removing.join("\n") : "No removable App Store-owned files were reported."
                                    }
                                    var missing = root.selectedFootprint && root.selectedFootprint.missingDependencies ? root.selectedFootprint.missingDependencies : []
                                    if (missing.length) return "NEW ON THIS DEVICE:\n" + missing.join("\n")
                                    return "No new dependencies need to be added.\nDeclared: " + root.joinedOrFallback(root.dependencyItems(confirmPanel.item), "None")
                                }
                                color: root.textPrimary
                                font.pixelSize: Math.round(12.5 * root.textScale)
                                lineHeight: 1.12
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: root.confirmOperation === "uninstall" ? 104 : 112
                    radius: 20
                    color: "#24131f34"
                    Column {
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 6
                        Text {
                            text: root.confirmOperation === "uninstall" ? "DEPENDENCY POLICY" : "PERMISSIONS & SIZE"
                            color: root.confirmOperation === "uninstall" ? root.warning : root.purple
                            font.pixelSize: Math.round(13.5 * root.textScale)
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: {
                                if (root.confirmOperation === "uninstall") {
                                    var removedDeps = root.selectedUninstallPlan.dependenciesRemoved || []
                                    var preservedDeps = root.selectedUninstallPlan.dependenciesPreserved || []
                                    return "Dependencies removed: " + (removedDeps.length ? removedDeps.join("  •  ") : "NONE") + "\nShared dependencies preserved: " + (preservedDeps.length ? preservedDeps.join("  •  ") : "None declared")
                                }
                                return root.joinedOrFallback(root.permissionItems(confirmPanel.item), "No elevated permissions declared") + "\nPackage size: " + root.packageSize(confirmPanel.item)
                            }
                            color: root.textPrimary
                            font.pixelSize: Math.round(13 * root.textScale)
                        }
                    }
                }
            }

            Row {
                id: actionRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 28
                spacing: 22
                Rectangle {
                    width: 300; height: 62; radius: 21
                    color: root.confirmOperation === "uninstall" ? "#45201622" : "#35204435"
                    border.width: 2; border.color: confirmPanel.tone
                    Text { anchors.centerIn: parent; text: "X  CONFIRM"; color: confirmPanel.tone; font.pixelSize: Math.round(18 * root.textScale); font.bold: true }
                }
                Rectangle {
                    width: 300; height: 62; radius: 21
                    color: "#30231b2c"; border.width: 1; border.color: root.border
                    Text { anchors.centerIn: parent; text: "O  CANCEL"; color: root.textSecondary; font.pixelSize: Math.round(18 * root.textScale); font.bold: true }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.repositoriesOpen
        color: "#c0000000"
        z: 65
        Shared.ReferenceModalPanel {
            anchors.centerIn: parent
            width: 1050
            height: 720
            radius: 32
            accentColor: root.focusBlue
            Column {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 16
                Text { text: "Trusted Repositories"; color: root.textPrimary; font.pixelSize: Math.round(30 * root.textScale); font.bold: true }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "X enables or disables a source. Developer Mode can add, trust, or remove custom repositories. Catalogs and packages still require the installed NeutronOS release public key."
                    color: root.textSecondary
                    font.pixelSize: Math.round(16 * root.textScale)
                }
                ListView {
                    id: repositoryList
                    width: parent.width
                    height: 520
                    model: backend ? backend.repositories : []
                    clip: true
                    spacing: 12
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: repositoryList.width
                        height: 96
                        radius: 22
                        color: root.repositoryIndex === index ? "#3a214b69" : "#21131e31"
                        border.width: root.repositoryIndex === index ? 2 : 1
                        border.color: root.repositoryIndex === index ? root.focusBlue : root.border
                        Row {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 16
                            Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: modelData.enabled ? root.success : root.danger }
                            Column {
                                width: parent.width - 210
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5
                                Text { width: parent.width; elide: Text.ElideRight; text: modelData.name; color: root.textPrimary; font.pixelSize: Math.round(19 * root.textScale); font.bold: true }
                                Text { width: parent.width; elide: Text.ElideMiddle; text: modelData.url; color: root.textSecondary; font.pixelSize: Math.round(13 * root.textScale) }
                            }
                            Rectangle {
                                width: 150
                                height: 42
                                radius: 17
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.trusted ? "#30204435" : "#362e2518"
                                border.width: 1
                                border.color: modelData.trusted ? root.success : root.warning
                                Text { anchors.centerIn: parent; text: modelData.trusted ? "TRUSTED" : "UNTRUSTED"; color: modelData.trusted ? root.success : root.warning; font.pixelSize: Math.round(12 * root.textScale); font.bold: true }
                            }
                        }
                    }
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "X Enable/Disable  •  Triangle Add  •  Square Trust  •  R1 Remove  •  Start/O Close"; color: root.cyan; font.pixelSize: Math.round(15 * root.textScale); font.bold: true }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.statusOpen
        color: "#CC00040A"
        z: 70

        Rectangle {
            id: operationResultGlow
            anchors.centerIn: parent
            width: root.statusIsOperationResult ? Math.min(parent.width - 150, 1040) : Math.min(parent.width - 220, 820)
            height: root.statusIsOperationResult ? (root.resultSuccess ? 360 : 610) : 310
            radius: 30
            color: root.statusIsOperationResult
                   ? (root.resultSuccess ? "#1835E68A" : "#20FF4050")
                   : (backend && backend.lastError.length ? "#20FF4050" : "#1849C8FF")
            border.width: 4
            border.color: root.statusIsOperationResult
                          ? (root.resultSuccess ? root.success : root.danger)
                          : (backend && backend.lastError.length ? root.danger : root.focusBlue)
            opacity: 0.45

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.statusOpen
                NumberAnimation { to: 0.9; duration: 850; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 0.42; duration: 850; easing.type: Easing.InOutQuad }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: operationResultGlow.width - 16
            height: operationResultGlow.height - 16
            radius: 26
            color: root.statusIsOperationResult
                   ? (root.resultSuccess ? "#F2112C24" : "#F22F1119")
                   : "#F20C1724"
            border.width: 2
            border.color: root.statusIsOperationResult
                          ? (root.resultSuccess ? "#A835E68A" : "#B8FF4050")
                          : (backend && backend.lastError.length ? "#A8FF4050" : "#8A49C8FF")

            Column {
                anchors.fill: parent
                anchors.leftMargin: 72
                anchors.rightMargin: 72
                anchors.topMargin: root.statusIsOperationResult ? 48 : 54
                anchors.bottomMargin: 34
                spacing: root.statusIsOperationResult ? (root.resultSuccess ? 16 : 11) : 22

                Text {
                    width: parent.width
                    text: root.statusIsOperationResult
                          ? root.operationDisplayVerb(root.resultOperation, root.resultSuccess)
                          : (backend && backend.lastError.length ? "ACTION FAILED" : "NOTICE")
                    color: root.statusIsOperationResult
                           ? (root.resultSuccess ? root.success : root.danger)
                           : (backend && backend.lastError.length ? root.danger : root.focusBlue)
                    font.pixelSize: Math.round((root.statusIsOperationResult ? 27 : 24) * root.textScale)
                    font.bold: true
                    font.letterSpacing: 1.6
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    visible: root.statusIsOperationResult
                    width: parent.width
                    text: root.resultPackageName + (root.resultPackageVersion.length ? "  " + root.resultPackageVersion : "")
                    color: root.resultSuccess ? "#C9FFE1" : "#FFD4D8"
                    font.pixelSize: Math.round(22 * root.textScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Column {
                    visible: root.statusIsOperationResult && !root.resultSuccess
                    width: parent.width
                    spacing: 8
                    Text {
                        width: parent.width
                        text: "STAGE:  " + root.resultStage + "    •    ERROR:  " + root.resultErrorCode
                        color: root.focusBlue
                        font.pixelSize: Math.round(11.5 * root.textScale)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: "REASON:  " + root.resultReason
                        color: "#FFC4CA"
                        font.pixelSize: Math.round(13.5 * root.textScale)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: "SOLUTION:  " + root.resultSolution
                        color: "#FF8D99"
                        font.pixelSize: Math.round(13.5 * root.textScale)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        visible: root.resultDetails.length > 0
                        width: parent.width
                        text: "DETAILS:  " + root.resultDetails
                        color: root.textSecondary
                        font.pixelSize: Math.round(11.5 * root.textScale)
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }

                Text {
                    visible: !root.statusIsOperationResult
                    width: parent.width
                    height: 92
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: root.toastText
                    color: root.textSecondary
                    font.pixelSize: Math.round(16 * root.textScale)
                }

                Item { width: 1; height: 2 }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 330)
                    height: 54
                    radius: 27
                    color: "#35FF4050"
                    border.width: 2
                    border.color: root.danger
                    Text {
                        anchors.centerIn: parent
                        text: "PRESS  O  TO EXIT"
                        color: "#FFE8EA"
                        font.pixelSize: Math.round(14 * root.textScale)
                        font.bold: true
                        font.letterSpacing: 0.9
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.analysisOpen
        color: "#c0000000"
        z: 75
        Shared.ReferenceModalPanel {
            anchors.centerIn: parent
            width: 980
            height: 570
            radius: 30
            accentColor: root.warning
            Column {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 16
                Text { text: "Third-Party Package Analysis"; color: root.textPrimary; font.pixelSize: Math.round(29 * root.textScale); font.bold: true }
                Text {
                    text: backend ? String(backend.lastSecurityAnalysis.classification || "UNKNOWN") : "UNKNOWN"
                    color: text === "SAFE" ? root.success : text === "DANGEROUS" ? root.danger : root.warning
                    font.pixelSize: Math.round(25 * root.textScale)
                    font.bold: true
                }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: backend ? String(backend.lastSecurityAnalysis.disclaimer || "") : ""; color: root.textSecondary; font.pixelSize: Math.round(15 * root.textScale) }
                ListView {
                    width: parent.width
                    height: 290
                    clip: true
                    spacing: 8
                    model: backend && backend.lastSecurityAnalysis.findings ? backend.lastSecurityAnalysis.findings : []
                    delegate: Text {
                        required property var modelData
                        width: ListView.view.width
                        wrapMode: Text.WordWrap
                        text: "• " + modelData.severity.toUpperCase() + " — " + modelData.description + (modelData.path ? " (" + modelData.path + ")" : "")
                        color: root.textSecondary
                        font.pixelSize: Math.round(14 * root.textScale)
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 18
                    Repeater {
                        model: ["Install", "Quarantine", "Remove"]
                        Rectangle {
                            required property int index
                            required property string modelData
                            width: 190
                            height: 58
                            radius: 20
                            color: root.analysisActionIndex === index ? "#49305f86" : "#21131e31"
                            border.width: root.analysisActionIndex === index ? 2 : 1
                            border.color: root.analysisActionIndex === index ? root.focusBlue : root.border
                            opacity: index === 0 && backend && backend.lastSecurityAnalysis.classification === "DANGEROUS" ? 0.4 : 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: index === 2 ? root.danger : index === 1 ? root.warning : root.success
                                font.pixelSize: Math.round(17 * root.textScale)
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }
    }

    Shared.ReferenceExitModal {
        id: referenceExitModal
        appName: "App Store"
        onExitRequested: root.exitRequested()
        onLeaveRunningRequested: root.backgroundRequested()
        onDismissed: { root.exitOpen = false; root.focusZone = 0; root.forceActiveFocus() }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.keyboardOpen
        color: "#b9000000"
        z: 80
        Column {
            anchors.centerIn: parent
            spacing: 12
            Rectangle {
                width: virtualKeyboard.width
                height: 64
                radius: 18
                color: "#f20c1424"
                border.width: 2
                border.color: root.focusBlue
                Text {
                    anchors.fill: parent
                    anchors.margins: 16
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                    text: root.keyboardBuffer.length ? root.keyboardBuffer :
                          (root.keyboardPurpose === "search" ? "Search packages" : "Path to .napp package")
                    color: root.textPrimary
                    font.pixelSize: Math.round(18 * root.textScale)
                }
            }
            Shared.VirtualKeyboard {
                id: virtualKeyboard
                width: Math.max(0, root.width - 48)
                height: 416
                visibleMode: root.keyboardOpen
                active: root.keyboardOpen
                largeMode: false
                title: root.keyboardPurpose === "search" ? "Search App Store" : "Manual NeutronOS Package"
                onKeyPressed: function(value) { root.appendKeyboard(value) }
                onBackspacePressed: { if (root.keyboardBuffer.length) root.keyboardBuffer = root.keyboardBuffer.slice(0, -1) }
                onEnterPressed: root.finishKeyboard()
                onClosePressed: { root.keyboardOpen = false; root.keyboardPurpose = "" }
            }
        }
    }
}
