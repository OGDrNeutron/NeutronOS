import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components" as Shared
import "components"
import "modals"
import "models"

Item {
    id: app

    property string appId: "filemanager"
    property string appName: "NeutronOS File Manager"
    signal exitRequested()
    signal backgroundRequested()

    focus: true

    property string currentPath: backendAvailable ? fileManager.homePath : "/home/echo"
    property int selectedIndex: 0
    property int selectedPlaceIndex: 0
    property string focusZone: "content"       // sidebar, content, actions, input, preview, editor, volumes
    property string viewMode: "list"
    property var settingsBackend: (typeof settingsManager !== "undefined") ? settingsManager : null
    property var assetBackend: (typeof assetManager !== "undefined") ? assetManager : null
    property bool lightMode: settingsBackend ? settingsBackend.themeMode === "light" : false
    property color windowColor: lightMode ? "#F4F6F8" : "#020712"
    property color sidebarColor: lightMode ? "#FFFFFF" : "#071426"
    property color panelColor: lightMode ? "#FFFFFF" : "#0A182B"
    property color panelRaised: lightMode ? "#F7F9FB" : "#0E213A"
    property color panelInset: lightMode ? "#E9EEF4" : "#06101F"
    property color textPrimary: lightMode ? "#080B10" : "#F4FBFF"
    property color textSecondary: lightMode ? "#2F3945" : "#A8C2DE"
    property color textMuted: lightMode ? "#65717E" : "#7895B5"
    property color divider: lightMode ? "#CFD6DE" : "#1D3958"
    property color focusBlue: "#4DA6FF"
    property color cyan: "#23C7E8"
    property color success: "#16C784"
    property color warning: "#F5B942"
    property color danger: "#FF4055"
    property color purple: "#A855F7"
    property bool showHidden: true
    property bool busy: backendAvailable ? fileManager.busy : false
    property string errorText: backendAvailable ? fileManager.error : "FileManager backend is unavailable."
    readonly property bool backendAvailable: typeof fileManager !== "undefined" && fileManager !== null

    // Controller-first arming / destination workflow.
    property bool armed: false
    property var armedItem: ({})
    property bool destinationMode: false
    property string transferMode: "move"
    property string originPath: ""

    property bool actionMenuOpen: false
    property int actionIndex: 0

    property bool inputModalOpen: false
    property string inputMode: ""
    property string inputTitle: ""
    property string inputHint: ""
    property var inputOptions: []
    property int inputOptionIndex: 0
    property bool inputNeedsPassword: false

    property bool previewOpen: false
    property var previewData: ({})
    property string previewPath: ""
    property bool metadataMode: false
    property real imageZoom: 1.0
    property real imagePanX: 0
    property real imagePanY: 0

    property bool editorOpen: false
    property string editorPath: ""
    property bool editorTruncated: false
    property bool editorDirty: false
    property bool editorDiscardArmed: false

    property bool volumeModalOpen: false
    property bool exitModalOpen: false
    property int exitChoice: 0
    property bool quickPlacesModalOpen: false
    property int quickPlaceSlot: 0
    property bool searchMode: false
    property bool searchPending: false
    property string searchQuery: ""
    property string browsePathBeforeSearch: ""
    property bool keyboardOpen: false
    property string keyboardTarget: ""
    property int volumeIndex: 0
    property int filesystemIndex: 0
    property var filesystemOptions: ["ext4", "exfat", "fat32", "ntfs"]

    onSelectedIndexChanged: previewDebounce.restart()

    property string statusText: destinationMode
                                ? ((transferMode === "copy" ? "COPY" : "MOVE") + " DESTINATION: " + currentPath)
                                : (armed ? "ARMED: " + String(armedItem.name || "") : "Ready")

    ListModel { id: fileModel }
    ListModel { id: placeModel }
    ListModel { id: actionModel }
    ListModel { id: volumeModel }
    ListModel { id: tagModel }
    ListModel { id: sftpModel }

    component AtomAnimation: Item {
        id: atomRoot
        property bool running: visible
        Image {
            anchors.fill: parent
            source: app.themeFile("atom.png")
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            cache: true
            opacity: app.lightMode ? 0.82 : 0.96
            RotationAnimation on rotation {
                running: atomRoot.running
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 9000
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.20
            height: width
            radius: width / 2
            color: app.purple
            opacity: 0.28
            SequentialAnimation on scale {
                running: atomRoot.running
                loops: Animation.Infinite
                NumberAnimation { from: 0.72; to: 1.18; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.18; to: 0.72; duration: 1100; easing.type: Easing.InOutSine }
            }
        }
    }

    property var pathHistory: []
    property int historyIndex: -1
    property bool historyNavigationPending: false
    property bool manualPreviewPending: false
    property int previewActionIndex: 0
    property bool tagModalOpen: false
    property int tagIndex: 0
    property int tagsRevision: 0
    property string activeTagFilter: ""
    property bool customTagEditorOpen: false
    property int customTagFieldIndex: 0
    property int customTagColorIndex: 0
    property int customTagIconIndex: 0
    property var tagColors: ["#21C8FF", "#A25CFF", "#FF4D63", "#FFB23E", "#43E89A", "#F2E85C", "#FF54C7", "#7C8BFF"]
    property var tagIcons: ["★", "♥", "⚙", "⌂", "☁", "⚡", "◆", "●", "✦", "♟", "♫", "▣"]

    property bool newItemModalOpen: false
    property int newItemStage: 0
    property int newItemKindIndex: 0
    property int newItemTypeIndex: 0
    property var newItemTypes: ["txt", "py", "sh", "qml", "json", "js", "cpp", "h", "md", "html", "css", "yaml", "xml", "service", "desktop", "apk", "ipa", "zip", "tar", "log", "conf", "csv"]

    property bool sftpModalOpen: false
    property string sftpMode: "list"
    property int sftpIndex: 0
    property int sftpFieldIndex: 0
    property string sftpEditingId: ""
    property int sftpAuthIndex: 0

    readonly property var securityBackend:
        (typeof securityCoreManager !== "undefined") ? securityCoreManager : null
    readonly property var controllerBackend:
        (typeof controllerManager !== "undefined") ? controllerManager : null

    function securitySuspiciousEvents() {
        var source = securityBackend && securityBackend.events ? securityBackend.events : []
        var out = []
        for (var i = 0; i < source.length; ++i) {
            var event = source[i] || ({})
            var severity = String(event.severityLabel || event.severity || event.status || "").toLowerCase()
            var details = (
                String(event.title || event.type || event.eventType || "") + " " +
                String(event.message || event.description || event.detail || event.reason || "")
            ).toLowerCase()
            var suspicious =
                severity.indexOf("critical") >= 0 ||
                severity.indexOf("high") >= 0 ||
                severity.indexOf("severe") >= 0 ||
                severity.indexOf("warning") >= 0 ||
                severity.indexOf("attention") >= 0 ||
                details.indexOf("suspicious") >= 0 ||
                details.indexOf("blocked") >= 0 ||
                details.indexOf("malware") >= 0 ||
                details.indexOf("attack") >= 0 ||
                details.indexOf("intrusion") >= 0
            if (suspicious && event.acknowledged !== true)
                out.push(event)
        }
        return out
    }

    function securityNeedsAttention() {
        if (!securityBackend ||
            securityBackend.daemonOnline !== true ||
            securityBackend.auditValid !== true)
            return true
        if (securityBackend.integrityChanges && securityBackend.integrityChanges.length > 0)
            return true
        if (securityBackend.malwareFindings && securityBackend.malwareFindings.length > 0)
            return true
        if (securitySuspiciousEvents().length > 0)
            return true
        if (Number(securityBackend.threatLevel || 5) <= 2)
            return true
        return false
    }

    function historyRecord(path) {
        var clean = String(path || "")
        if (!clean.length)
            return
        if (historyNavigationPending) {
            historyNavigationPending = false
            return
        }
        if (historyIndex >= 0 && historyIndex < pathHistory.length &&
            String(pathHistory[historyIndex]) === clean)
            return
        var next = []
        for (var i = 0; i <= historyIndex && i < pathHistory.length; ++i)
            next.push(pathHistory[i])
        next.push(clean)
        pathHistory = next
        historyIndex = pathHistory.length - 1
    }

    function goBack() {
        if (!backendAvailable || historyIndex <= 0)
            return
        historyIndex--
        historyNavigationPending = true
        fileManager.loadDirectory(String(pathHistory[historyIndex]))
    }

    function goForward() {
        if (!backendAvailable || historyIndex < 0 || historyIndex >= pathHistory.length - 1)
            return
        historyIndex++
        historyNavigationPending = true
        fileManager.loadDirectory(String(pathHistory[historyIndex]))
    }

    function goUp() {
        loadPath(parentPath(currentPath))
    }

    function refreshCurrent() {
        if (!backendAvailable)
            return
        historyNavigationPending = true
        fileManager.refresh()
    }

    function folderCount() {
        var count = 0
        for (var i = 0; i < fileModel.count; ++i)
            if (fileModel.get(i).isDir === true) count++
        return count
    }

    function fileCountOnly() {
        return Math.max(0, fileModel.count - folderCount())
    }

    function currentFreeText() {
        if (!backendAvailable)
            return "-- available"
        var volumes = fileManager.listVolumes()
        var best = null
        var bestLength = -1
        var path = String(currentPath || "/")
        for (var i = 0; i < volumes.length; ++i) {
            var v = volumes[i] || ({})
            var mount = String(v.mountPath || "")
            if (!mount.length)
                continue
            var matches = path === mount ||
                          (mount === "/" ? path.startsWith("/") :
                           path.startsWith(mount.endsWith("/") ? mount : mount + "/"))
            if (matches && mount.length > bestLength) {
                best = v
                bestLength = mount.length
            }
        }
        return best ? String(best.freeText || "--") + " available" : "-- available"
    }

    function sidebarIcon(name) {
        var value = String(name || "").toLowerCase()
        if (value === "home") return "⌂"
        if (value === "desktop") return "▱"
        if (value === "documents") return "▤"
        if (value === "downloads") return "⇩"
        if (value === "pictures") return "▧"
        if (value === "music") return "♫"
        if (value === "videos") return "▣"
        if (value === "shared") return "⌘"
        if (value.indexOf("neutron") >= 0) return "▰"
        return "▰"
    }

    function previewSelected() {
        if (!backendAvailable)
            return
        var item = selectedItem()
        if (!item || !item.path) {
            previewData = ({})
            previewPath = ""
            return
        }

        manualPreviewPending = false
        previewPath = String(item.path)

        if (item.isDir) {
            fileManager.requestMetadata(item.path)
            return
        }

        var extension = String(item.extension || "").toLowerCase()
        var type = String(item.icon || item.mimeType || extension || "").toLowerCase()

        var imageExtensions = [
            "png","jpg","jpeg","webp","gif","bmp","svg","ico","tif","tiff"
        ]

        var textExtensions = [
            "txt","text","md","markdown","qml","js","mjs","ts","tsx","jsx",
            "py","pyw","sh","bash","zsh","fish","c","cc","cpp","cxx","h","hh",
            "hpp","hxx","java","kt","kts","rs","go","swift","m","mm","cs","php",
            "rb","pl","lua","r","sql","html","htm","css","scss","sass","less",
            "xml","json","json5","yaml","yml","toml","ini","conf","cfg","service",
            "desktop","log","csv","tsv","properties","env","gitignore","cmake",
            "gradle","pro","pri","mk","makefile"
        ]

        var imageLike =
            type.indexOf("image") >= 0 ||
            imageExtensions.indexOf(extension) >= 0

        var textLike =
            type.indexOf("text") >= 0 ||
            type.indexOf("json") >= 0 ||
            type.indexOf("xml") >= 0 ||
            type.indexOf("script") >= 0 ||
            textExtensions.indexOf(extension) >= 0 ||
            String(item.name || "").toLowerCase() === "makefile" ||
            String(item.name || "").toLowerCase() === "cmakelists.txt"

        if (imageLike || textLike)
            fileManager.requestQuickLook(item.path)
        else
            fileManager.requestMetadata(item.path)
    }

    function previewTextSnippet() {
        var value = String(previewData && previewData.text !== undefined ? previewData.text : "")
        if (!value.length)
            return ""
        if (value.length > 4200)
            value = value.slice(0, 4200) + "\n…"
        return value
    }

    function humanPermissions(value) {
        var p = String(value || "")
        if (p.indexOf("Owner:") === 0)
            return p
        if (p.length < 9)
            return p.length ? p : "Unavailable"
        if (p.length === 10)
            p = p.slice(1)
        function scope(offset) {
            var parts = []
            if (p.charAt(offset) === "r") parts.push("Read")
            if (p.charAt(offset + 1) === "w") parts.push("Write")
            if (p.charAt(offset + 2) === "x") parts.push("Execute")
            return parts.length ? parts.join(" & ") : "No access"
        }
        return "Owner: " + scope(0) + "  •  Group: " + scope(3) + "  •  Others: " + scope(6)
    }

    function refreshTags() {
        tagModel.clear()
        if (!backendAvailable || !fileManager.tagDefinitions)
            return
        var defs = fileManager.tagDefinitions || []
        for (var i = 0; i < defs.length; ++i)
            tagModel.append(defs[i])
        tagIndex = Math.max(0, Math.min(tagModel.count - 1, tagIndex))
    }

    function tagsForSelected() {
        var revision = tagsRevision
        var item = selectedItem()
        if (!backendAvailable || !item || !item.path || typeof fileManager.tagsForPath !== "function")
            return []
        return fileManager.tagsForPath(item.path) || []
    }

    function pathHasTag(path, tagId) {
        if (!backendAvailable || !path || !tagId || typeof fileManager.tagsForPath !== "function")
            return false
        var assigned = fileManager.tagsForPath(path) || []
        for (var i = 0; i < assigned.length; ++i)
            if (String(assigned[i].id || "") === String(tagId || ""))
                return true
        return false
    }

    function selectedHasTag(tagId) {
        var assigned = tagsForSelected()
        for (var i = 0; i < assigned.length; ++i)
            if (String(assigned[i].id || "") === String(tagId || "")) return true
        return false
    }

    function openTagModal() {
        if (!selectedItem()) return
        refreshTags()
        tagIndex = 0
        customTagEditorOpen = false
        tagModalOpen = true
        focusZone = "tags"
        forceActiveFocus()
    }

    function closeTagModal() {
        tagModalOpen = false
        customTagEditorOpen = false
        focusZone = "preview"
        forceActiveFocus()
    }

    function toggleSelectedTag() {
        if (!backendAvailable || tagModel.count <= 0 || !selectedItem()) return
        var tag = tagModel.get(tagIndex)
        var id = String(tag.id || "")
        if (!id.length) return
        if (selectedHasTag(id)) fileManager.removeTag(selectedItem().path, id)
        else fileManager.assignTag(selectedItem().path, id)
    }

    function createAndAssignCustomTag() {
        if (!backendAvailable || !selectedItem()) return
        var name = customTagNameInput.text.trim()
        if (!name.length) {
            errorBanner.text = "Enter a name for the custom tag."
            errorBannerTimer.restart()
            return
        }
        var color = String(tagColors[customTagColorIndex] || "#21C8FF")
        var icon = String(tagIcons[customTagIconIndex] || "★")
        var id = fileManager.createCustomTag(name, color, icon)
        if (String(id || "").length) {
            fileManager.assignTag(selectedItem().path, id)
            refreshTags()
            customTagEditorOpen = false
        }
    }

    function openNewItemModal() {
        if (!backendAvailable || newItemModalOpen || tagModalOpen || sftpModalOpen)
            return
        newItemStage = 0
        newItemKindIndex = 0
        newItemTypeIndex = 0
        newItemNameInput.text = ""
        newItemModalOpen = true
        focusZone = "newItem"
        forceActiveFocus()
    }

    function closeNewItemModal() {
        newItemModalOpen = false
        newItemStage = 0
        focusZone = "content"
        forceActiveFocus()
    }

    function finishNewItemName() {
        var name = newItemNameInput.text.trim()
        if (!name.length) {
            errorBanner.text = "Enter a file or folder name."
            errorBannerTimer.restart()
            return
        }
        if (newItemKindIndex === 0) {
            fileManager.createFolder(currentPath, name)
            closeNewItemModal()
        } else {
            newItemStage = 2
            forceActiveFocus()
        }
    }

    function createNewTypedFile() {
        var name = newItemNameInput.text.trim()
        var type = String(newItemTypes[newItemTypeIndex] || "txt")
        if (!name.length) return
        if (name.lastIndexOf(".") <= 0)
            name += "." + type
        fileManager.createFile(currentPath, name, type)
        closeNewItemModal()
    }

    function refreshSftpModel() {
        sftpModel.clear()
        if (!backendAvailable || !fileManager.sftpConnections)
            return
        var rows = fileManager.sftpConnections || []
        for (var i = 0; i < rows.length; ++i)
            sftpModel.append(rows[i])
        sftpIndex = Math.max(0, Math.min(sftpModel.count - 1, sftpIndex))
    }

    function openSftpModal(profileId) {
        refreshSftpModel()
        sftpMode = "list"
        sftpIndex = 0
        if (profileId) {
            for (var i = 0; i < sftpModel.count; ++i) {
                if (String(sftpModel.get(i).id || "") === String(profileId)) {
                    sftpIndex = i
                    break
                }
            }
        }
        sftpModalOpen = true
        focusZone = "sftp"
        forceActiveFocus()
    }

    function closeSftpModal() {
        sftpModalOpen = false
        sftpMode = "list"
        focusZone = "sidebar"
        forceActiveFocus()
    }

    function loadSftpEditor(profile) {
        var p = profile || ({})
        sftpEditingId = String(p.id || "")
        sftpNameInput.text = String(p.name || "")
        sftpHostInput.text = String(p.host || "")
        sftpUserInput.text = String(p.user || "")
        sftpPortInput.text = String(p.port || 22)
        sftpPathInput.text = String(p.remotePath || "/")
        sftpPasswordInput.text = ""
        sftpAuthIndex = String(p.auth || "key") === "password" ? 1 : 0
        sftpFieldIndex = 0
        sftpMode = "edit"
    }

    function connectEditedSftp() {
        if (!backendAvailable || typeof fileManager.saveSftpConnection !== "function") return
        var id = fileManager.saveSftpConnection(
                    sftpEditingId,
                    sftpNameInput.text.trim(),
                    sftpHostInput.text.trim(),
                    Number(sftpPortInput.text || 22),
                    sftpUserInput.text.trim(),
                    sftpPathInput.text.trim() || "/",
                    sftpAuthIndex === 1 ? "password" : "key")
        if (!String(id || "").length) return
        sftpEditingId = String(id)
        fileManager.connectSftp(sftpEditingId, sftpAuthIndex === 1 ? sftpPasswordInput.text : "")
    }

    function themeFile(path) {
        try {
            if (assetBackend && typeof assetBackend.themeFile === "function")
                return String(assetBackend.themeFile(path) || "")
        } catch (error) {}
        return ""
    }

    function toggleTheme() {
        if (!settingsBackend || typeof settingsBackend.setThemeMode !== "function")
            return
        settingsBackend.setThemeMode(lightMode ? "dark" : "light")
    }

    function cycleViewMode() {
        viewMode = viewMode === "list" ? "grid" : "list"
        statusToast.text = "VIEW: " + viewMode.toUpperCase()
        statusToastTimer.restart()
        ensureContentSelectionVisible()
    }

    function fileGlyph(item) {
        if (!item) return "▤"
        if (item.isDir) return "▰"
        var icon = String(item.icon || "file")
        var ext = String(item.extension || "").toLowerCase()
        if (icon === "archive" || ext === "zip" || ext.indexOf("tar") === 0 || ext === "7z") return "▦"
        if (icon === "image") return "▧"
        if (icon === "video") return "▶"
        if (icon === "audio") return "♫"
        if (icon === "encrypted" || ext === "nenc" || ext === "gpg") return "◆"
        if (ext === "py") return "PY"
        if (ext === "cpp" || ext === "cc" || ext === "cxx" || ext === "c") return "C++"
        if (ext === "h" || ext === "hpp") return "H"
        if (ext === "qml") return "QML"
        if (ext === "json") return "{}"
        if (icon === "code") return "</>"
        return "▤"
    }

    function openExitModal() {
        exitChoice = 0
        exitModalOpen = true
        referenceExitModal.openModal(app)
    }

    function openQuickPlacesModal() {
        quickPlaceSlot = 0
        quickPlacesModalOpen = true
        forceActiveFocus()
    }

    function quickPlaceForSlot(slot) {
        if (!backendAvailable) return null
        var places = fileManager.quickPlaces || []
        for (var i = 0; i < places.length; ++i)
            if (Number(places[i].slot) === Number(slot)) return places[i]
        return null
    }

    function openKeyboard(target, title) {
        keyboardTarget = target
        keyboardOpen = true
        virtualKeyboard.title = title || "File Manager Keyboard"
        virtualKeyboard.openKeyboard(true)
        virtualKeyboard.forceActiveFocus()
    }

    function keyboardTextInput() {
        if (keyboardTarget === "search") return searchInput
        if (keyboardTarget === "primary") return primaryInput
        if (keyboardTarget === "secondary") return secondaryInput
        if (keyboardTarget === "editor") return editorText
        if (keyboardTarget === "volumeLabel") return volumeLabelInput
        if (keyboardTarget === "formatConfirm") return formatConfirmInput
        if (keyboardTarget === "customTagName") return customTagNameInput
        if (keyboardTarget === "newItemName") return newItemNameInput
        if (keyboardTarget === "sftpName") return sftpNameInput
        if (keyboardTarget === "sftpHost") return sftpHostInput
        if (keyboardTarget === "sftpUser") return sftpUserInput
        if (keyboardTarget === "sftpPort") return sftpPortInput
        if (keyboardTarget === "sftpPath") return sftpPathInput
        if (keyboardTarget === "sftpPassword") return sftpPasswordInput
        return null
    }

    function keyboardAppend(value) {
        var target = keyboardTextInput()
        if (!target) return
        target.insert(target.cursorPosition, String(value || ""))
    }

    function keyboardBackspace() {
        var target = keyboardTextInput()
        if (!target || target.cursorPosition <= 0) return
        target.remove(target.cursorPosition - 1, target.cursorPosition)
    }

    function closeKeyboard(commit) {
        var target = keyboardTarget
        virtualKeyboard.visibleMode = false
        keyboardOpen = false
        keyboardTarget = ""
        if (commit && target === "search") {
            runSearch()
        } else if (commit && target === "primary") {
            if (inputNeedsPassword) openKeyboard("secondary", "Encryption Password")
            else confirmInput()
        } else if (commit && target === "secondary") {
            confirmInput()
        } else if (commit && target === "newItemName") {
            finishNewItemName()
        }
        forceActiveFocus()
    }

    function openSearchBar() {
        if (editorOpen || previewOpen || inputModalOpen || actionMenuOpen ||
            volumeModalOpen || tagModalOpen || newItemModalOpen || sftpModalOpen)
            return
        focusZone = "search"
        openKeyboard("search", "Search Files")
    }

    function runSearch() {
        activeTagFilter = ""
        if (!backendAvailable) return
        var query = searchInput.text.trim()
        searchQuery = query
        if (query.length === 0) {
            clearSearch()
            return
        }
        if (!searchMode) browsePathBeforeSearch = currentPath
        searchMode = true
        searchPending = true
        fileManager.searchFiles(query, currentPath, true, 750)
    }

    function clearSearch() {
        searchPending = false
        searchMode = false
        searchQuery = ""
        searchInput.text = ""
        if (browsePathBeforeSearch.length > 0) {
            var restore = browsePathBeforeSearch
            browsePathBeforeSearch = ""
            loadPath(restore)
        } else {
            loadPath(currentPath)
        }
    }

    function selectedItem() {
        if (fileModel.count <= 0)
            return null
        selectedIndex = Math.max(0, Math.min(fileModel.count - 1, selectedIndex))
        return fileModel.get(selectedIndex)
    }

    function parentPath(path) {
        var value = String(path || "/")
        while (value.length > 1 && value.endsWith("/"))
            value = value.slice(0, -1)
        var slash = value.lastIndexOf("/")
        return slash <= 0 ? "/" : value.slice(0, slash)
    }

    function loadPath(path) {
        if (!backendAvailable)
            return
        fileManager.loadDirectory(String(path || fileManager.homePath))
    }

    function refreshPlaces() {
        placeModel.clear()
        if (!backendAvailable)
            return

        var home = String(fileManager.homePath || "/home/echo")
        var favorites = [
            {name:"Home", path:home},
            {name:"Desktop", path:home + "/Desktop"},
            {name:"Documents", path:home + "/Documents"},
            {name:"Downloads", path:home + "/Downloads"},
            {name:"Pictures", path:home + "/Pictures"},
            {name:"Music", path:home + "/Music"},
            {name:"Videos", path:home + "/Videos"}
        ]

        for (var i = 0; i < favorites.length; ++i) {
            var f = favorites[i]
            placeModel.append({
                name:f.name,
                path:f.path,
                icon:sidebarIcon(f.name),
                section:"FAVORITES",
                showSection:i === 0,
                quick:false,
                slot:-1,
                freeText:"",
                enabled:true
            })
        }

        var volumes = fileManager.listVolumes()
        for (var v = 0; v < volumes.length; ++v) {
            var volume = volumes[v] || ({})
            var mount = String(volume.mountPath || "")
            var device = String(volume.device || "")

            // The boot/system filesystem is intentionally branded NeutronOS.
            // Every other drive uses the actual name discovered from Linux.
            var name = volume.system === true
                       ? "NeutronOS"
                       : String(volume.name || "").trim()

            if (volume.system !== true &&
                (!name.length || name === mount || name === "/")) {
                var mountParts = mount.split("/")
                for (var mp = mountParts.length - 1; mp >= 0; --mp) {
                    if (String(mountParts[mp] || "").length) {
                        name = String(mountParts[mp])
                        break
                    }
                }
            }

            if (volume.system !== true &&
                (!name.length || name === "/")) {
                var deviceParts = device.split("/")
                for (var dp = deviceParts.length - 1; dp >= 0; --dp) {
                    if (String(deviceParts[dp] || "").length) {
                        name = String(deviceParts[dp])
                        break
                    }
                }
            }

            if (!name.length)
                continue

            placeModel.append({
                name:name,
                path:mount,
                icon:"▰",
                section:"STORAGE",
                showSection:v === 0,
                quick:false,
                slot:-1,
                freeText:String(volume.freeText || ""),
                enabled:true
            })
        }

        placeModel.append({
            name:"Shared",
            path:"/mnt",
            icon:"⌘",
            section:"NETWORK",
            showSection:true,
            special:"shared",
            quick:false,
            slot:-1,
            freeText:"",
            enabled:true
        })

        placeModel.append({
            name:"SFTP Servers",
            path:"",
            icon:"⇄",
            section:"",
            showSection:false,
            special:"sftp",
            quick:false,
            slot:-1,
            freeText: backendAvailable && fileManager.sftpAvailable ? "READY" : "N/A",
            enabled:true
        })

        if (backendAvailable && fileManager.sftpConnections) {
            var remoteRows = fileManager.sftpConnections || []
            for (var s = 0; s < remoteRows.length; ++s) {
                var remote = remoteRows[s] || ({})
                placeModel.append({
                    name:String(remote.name || remote.host || "SFTP"),
                    path:String(remote.mountPath || ""),
                    icon:"⇄",
                    section:"",
                    showSection:false,
                    special:"sftpProfile",
                    profileId:String(remote.id || ""),
                    quick:false,
                    slot:-1,
                    freeText:remote.connected === true ? "CONNECTED" : "OFFLINE",
                    enabled:true
                })
            }
        }

        placeModel.append({
            name:"Work",
            path:"",
            icon:"💼",
            section:"TAGS",
            showSection:true,
            special:"tagFilter",
            tagId:"work",
            quick:false,
            slot:-1,
            freeText:"",
            enabled:true
        })
        placeModel.append({
            name:"Personal",
            path:"",
            icon:"👤",
            section:"",
            showSection:false,
            special:"tagFilter",
            tagId:"personal",
            quick:false,
            slot:-1,
            freeText:"",
            enabled:true
        })
        placeModel.append({
            name:"Important",
            path:"",
            icon:"▲",
            iconColor:"#FF4055",
            section:"",
            showSection:false,
            special:"tagFilter",
            tagId:"important",
            quick:false,
            slot:-1,
            freeText:"",
            enabled:true
        })

        selectedPlaceIndex = Math.max(0, Math.min(placeModel.count - 1, selectedPlaceIndex))
    }

    function refreshVolumes() {
        volumeModel.clear()
        if (!backendAvailable)
            return
        var volumes = fileManager.listVolumes()
        for (var i = 0; i < volumes.length; ++i)
            volumeModel.append(volumes[i])
        volumeIndex = Math.max(0, Math.min(volumeModel.count - 1, volumeIndex))
    }

    function clearArm() {
        armed = false
        armedItem = ({})
        destinationMode = false
        transferMode = "move"
        originPath = ""
    }

    function armFile(item) {
        if (!item || item.isDir)
            return
        armed = true
        armedItem = item
        destinationMode = false
        transferMode = "move"
        originPath = currentPath
    }

    function armFolder(item) {
        if (!item || !item.isDir)
            return
        armed = true
        armedItem = item
        destinationMode = false
        transferMode = "move"
        originPath = currentPath
    }

    function beginTransfer(mode) {
        if (!armed || !armedItem.path)
            return
        transferMode = mode === "copy" ? "copy" : "move"
        destinationMode = true
        fileManager.setClipboardPath(armedItem.path, transferMode)
        actionMenuOpen = false
        focusZone = "content"
    }

    function commitTransfer() {
        if (!destinationMode || !armedItem.path)
            return
        if (transferMode === "copy")
            fileManager.copyPath(armedItem.path, currentPath)
        else
            fileManager.movePath(armedItem.path, currentPath)
    }

    function pasteSystemText(target) {
        if (!backendAvailable || !target)
            return
        var text = fileManager.pasteText()
        if (text.length > 0)
            target.insert(target.cursorPosition, text)
    }

    function addAction(id, label, destructive) {
        actionModel.append({ "actionId": id, "label": label, "destructive": destructive === true })
    }

    function openActions() {
        actionModel.clear()
        actionIndex = 0
        var item = armed ? armedItem : selectedItem()
        if (item && item.path) {
            if (item.isDir)
                addAction("open", "Open Folder")
            else if (fileManager.isEditable(item.path))
                addAction("edit", "Open in Editor")
            else
                addAction("open", "Open / Quick Look")

            addAction("quicklook", "Quick Look")
            addAction("metadata", "File Metadata")
            addAction("copy", "Copy To…")
            addAction("move", "Move To…")
            addAction("rename", "Rename")
            addAction("duplicate", "Duplicate")
            addAction("compress", "Compress")
            if (!item.isDir && fileManager.isArchive(item.path))
                addAction("extract", "Extract Here")
            if (!item.isDir && (String(item.path).endsWith(".nenc") || String(item.path).endsWith(".gpg")))
                addAction("decrypt", "Decrypt")
            else
                addAction("encrypt", "Encrypt")
            addAction("trash", "Move to Trash", true)
        }

        // Folder-level tools remain available from every action menu.
        addAction("newFile", "Create File Here")
        addAction("newFolder", "Create Folder Here")
        if (fileManager.clipboardPath.length > 0)
            addAction("pasteFiles", "Paste " + fileManager.clipboardMode + " Here")
        addAction("refresh", "Refresh Folder")
        addAction("volumes", "Volumes / Format")
        actionMenuOpen = true
        focusZone = "actions"
    }

    function runAction(actionId) {
        var item = armed ? armedItem : selectedItem()
        actionMenuOpen = false

        if (actionId === "open") {
            if (item.isDir)
                loadPath(item.path)
            else
                fileManager.openPath(item.path)
            focusZone = "content"
        } else if (actionId === "edit") {
            fileManager.readTextFile(item.path)
        } else if (actionId === "quicklook") {
            fileManager.requestQuickLook(item.path)
        } else if (actionId === "metadata") {
            metadataMode = true
            fileManager.requestMetadata(item.path)
        } else if (actionId === "copy") {
            if (!armed) {
                armed = true
                armedItem = item
                originPath = currentPath
            }
            beginTransfer("copy")
        } else if (actionId === "move") {
            if (!armed) {
                armed = true
                armedItem = item
                originPath = currentPath
            }
            beginTransfer("move")
        } else if (actionId === "rename") {
            if (!armed) {
                armed = true
                armedItem = item
            }
            openInput("rename", "Rename", "Enter the new file or folder name.", [String(item.name)], false)
            primaryInput.text = String(item.name)
            primaryInput.selectAll()
        } else if (actionId === "duplicate") {
            fileManager.duplicatePath(item.path)
        } else if (actionId === "compress") {
            if (!armed) {
                armed = true
                armedItem = item
            }
            openInput("compress", "Compress", "Choose an archive format and destination name.", fileManager.supportedArchiveFormats, false)
            primaryInput.text = fileManager.suggestedArchiveName(item.path, String(inputOptions[inputOptionIndex] || "zip"))
        } else if (actionId === "extract") {
            if (!armed) {
                armed = true
                armedItem = item
            }
            openInput("extract", "Extract Archive", "Choose the directory where this archive will be unpacked.", [], false)
            primaryInput.text = currentPath
        } else if (actionId === "encrypt") {
            if (!armed) {
                armed = true
                armedItem = item
            }
            openInput("encrypt", "Encrypt", "Password must contain at least 8 characters.", fileManager.supportedEncryptionMethods, true)
            primaryInput.text = fileManager.suggestedEncryptedName(item.path)
            secondaryInput.text = ""
        } else if (actionId === "decrypt") {
            if (!armed) {
                armed = true
                armedItem = item
            }
            openInput("decrypt", "Decrypt", "Enter the encryption password and destination.", ["auto", "xchacha20-poly1305", "gpg-aes256"], true)
            primaryInput.text = currentPath
            secondaryInput.text = ""
        } else if (actionId === "trash") {
            if (!armed) {
                armed = true
                armedItem = item
            }
            openInput("trash", "Move to Trash", "Type TRASH to confirm. The item can be recovered from the desktop Trash.", [], false)
            primaryInput.text = ""
        } else if (actionId === "newFile") {
            openInput("newFile", "Create File", "Select a template or type an extension directly.",
                      ["blank", "txt", "py", "cpp", "h", "json", "qml", "js", "sh", "md", "html", "yaml", "xml", "service", "zip", "tar"], false)
            primaryInput.text = "new-file.txt"
        } else if (actionId === "newFolder") {
            openInput("newFolder", "Create Folder", "Enter a folder name.", [], false)
            primaryInput.text = "New Folder"
            primaryInput.selectAll()
        } else if (actionId === "pasteFiles") {
            fileManager.pasteClipboardPath(currentPath)
        } else if (actionId === "refresh") {
            loadPath(currentPath)
        } else if (actionId === "volumes") {
            refreshVolumes()
            volumeModalOpen = true
            focusZone = "volumes"
            formatConfirmInput.text = ""
            volumeLabelInput.text = ""
            Qt.callLater(function() { formatConfirmInput.forceActiveFocus() })
        }
    }

    function openInput(mode, title, hint, options, needsPassword) {
        inputMode = mode
        inputTitle = title
        inputHint = hint
        inputOptions = options || []
        inputOptionIndex = 0
        inputNeedsPassword = needsPassword === true
        inputModalOpen = true
        focusZone = "input"
        Qt.callLater(function() { primaryInput.forceActiveFocus() })
    }

    function closeInput() {
        inputModalOpen = false
        inputMode = ""
        focusZone = "content"
        forceActiveFocus()
    }

    function selectedInputOption() {
        if (!inputOptions || inputOptions.length <= 0)
            return ""
        inputOptionIndex = Math.max(0, Math.min(inputOptions.length - 1, inputOptionIndex))
        return String(inputOptions[inputOptionIndex])
    }

    function confirmInput() {
        var value = primaryInput.text.trim()
        var option = selectedInputOption()
        if (inputMode === "rename") {
            fileManager.renamePath(armedItem.path, value)
        } else if (inputMode === "newFolder") {
            fileManager.createFolder(currentPath, value)
        } else if (inputMode === "newFile") {
            if (option !== "" && option !== "blank" && value.indexOf(".") < 0)
                value += "." + option
            fileManager.createFile(currentPath, value, option)
        } else if (inputMode === "compress") {
            fileManager.compressPaths([armedItem.path], value, option || "zip")
        } else if (inputMode === "extract") {
            fileManager.extractArchive(armedItem.path, value)
        } else if (inputMode === "encrypt") {
            fileManager.encryptPath(armedItem.path, value, secondaryInput.text, option || "xchacha20-poly1305")
        } else if (inputMode === "decrypt") {
            fileManager.decryptPath(armedItem.path, value, secondaryInput.text, option || "auto")
        } else if (inputMode === "trash") {
            if (value !== "TRASH") {
                errorBanner.text = "Type TRASH exactly to confirm."
                errorBannerTimer.restart()
                return
            }
            fileManager.deletePath(armedItem.path)
        }
        closeInput()
    }

    function editorMoveCursorHorizontal(delta) {
        if (!editorOpen)
            return
        var next = Math.max(0, Math.min(editorText.length,
                                         editorText.cursorPosition + Number(delta)))
        editorText.cursorPosition = next
        editorText.forceActiveFocus()
    }

    function editorMoveCursorVertical(delta) {
        if (!editorOpen)
            return

        var content = String(editorText.text || "")
        var pos = Math.max(0, Math.min(content.length, editorText.cursorPosition))
        var lineStart = content.lastIndexOf("\n", Math.max(0, pos - 1)) + 1
        var column = pos - lineStart

        if (delta < 0) {
            if (lineStart <= 0)
                return
            var previousEnd = lineStart - 1
            var previousStart = content.lastIndexOf("\n", Math.max(0, previousEnd - 1)) + 1
            var previousLength = previousEnd - previousStart
            editorText.cursorPosition = previousStart + Math.min(column, previousLength)
        } else {
            var currentEnd = content.indexOf("\n", pos)
            if (currentEnd < 0)
                return
            var nextStart = currentEnd + 1
            var nextEnd = content.indexOf("\n", nextStart)
            if (nextEnd < 0)
                nextEnd = content.length
            var nextLength = nextEnd - nextStart
            editorText.cursorPosition = nextStart + Math.min(column, nextLength)
        }

        editorText.forceActiveFocus()
    }

    function editorBackspace() {
        if (!editorOpen || editorTruncated)
            return
        var pos = editorText.cursorPosition
        if (pos <= 0)
            return
        editorText.remove(pos - 1, pos)
        editorText.cursorPosition = pos - 1
        editorDirty = true
        editorText.forceActiveFocus()
    }

    function saveEditor() {
        if (!editorOpen)
            return
        if (editorTruncated) {
            errorBanner.text = "This large-file preview is read-only and cannot be saved."
            errorBannerTimer.restart()
            return
        }
        fileManager.saveTextFile(editorPath, editorText.text)
        editorDirty = false
        editorDiscardArmed = false
    }

    function resetImageViewer() {
        imageZoom = 1.0
        imagePanX = 0
        imagePanY = 0
    }

    function zoomImage(delta) {
        if (!previewOpen || String(previewData.previewType || "") !== "image")
            return
        var oldZoom = imageZoom
        imageZoom = Math.max(0.5, Math.min(6.0, imageZoom + Number(delta)))
        if (Math.abs(imageZoom - oldZoom) > 0.001) {
            imagePanX = imagePanX * imageZoom / oldZoom
            imagePanY = imagePanY * imageZoom / oldZoom
        }
    }

    function panImage(dx, dy) {
        if (!previewOpen || String(previewData.previewType || "") !== "image")
            return
        imagePanX += Number(dx)
        imagePanY += Number(dy)
    }

    function primaryAction() {
        if (focusZone === "header" && !exitModalOpen) { openExitModal(); return }
        if (focusZone === "preview" && !previewOpen && !tagModalOpen) {
            if (previewActionIndex === 1) { openTagModal(); return }

            var previewItem = selectedItem()
            if (!previewItem) return

            if (previewItem.isDir) {
                loadPath(previewItem.path)
                return
            }

            var extension = String(previewItem.extension || "").toLowerCase()
            var type = String(previewItem.icon || previewItem.mimeType || extension || "").toLowerCase()
            var imageLike =
                type.indexOf("image") >= 0 ||
                ["png","jpg","jpeg","webp","gif","bmp","svg","ico","tif","tiff"].indexOf(extension) >= 0

            if (imageLike) {
                resetImageViewer()
                manualPreviewPending = true
                fileManager.requestQuickLook(previewItem.path)
            } else if (backendAvailable && fileManager.isEditable(previewItem.path)) {
                fileManager.readTextFile(previewItem.path)
            } else {
                fileManager.openPath(previewItem.path)
            }
            return
        }
        if (busy)
            return
        if (editorOpen) {
            if (editorTruncated) {
                errorBanner.text = "This large-file preview is read-only."
                errorBannerTimer.restart()
                return
            }
            openKeyboard("editor", "Edit File")
            return
        }
        if (previewOpen) {
            previewOpen = false
            focusZone = "content"
            forceActiveFocus()
            return
        }
        if (volumeModalOpen) {
            if (volumeModel.count > 0) {
                var volume = volumeModel.get(volumeIndex)
                if (volume.system) {
                    errorBanner.text = "The NeutronOS system device cannot be formatted."
                    errorBannerTimer.restart()
                    return
                }
                fileManager.formatVolume(volume.device,
                                         filesystemOptions[filesystemIndex],
                                         volumeLabelInput.text,
                                         formatConfirmInput.text)
                volumeModalOpen = false
                focusZone = "content"
            }
            return
        }
        if (inputModalOpen) {
            openKeyboard(secondaryInput.activeFocus ? "secondary" : "primary", secondaryInput.activeFocus ? "Encryption Password" : inputTitle)
            return
        }
        if (actionMenuOpen) {
            if (actionModel.count > 0)
                runAction(actionModel.get(actionIndex).actionId)
            return
        }
        if (focusZone === "search") {
            openKeyboard("search", "Search Files")
            return
        }
        if (focusZone === "sidebar") {
            if (placeModel.count > 0) {
                var place = placeModel.get(selectedPlaceIndex)
                if (String(place.special || "") === "sftp") {
                    openSftpModal("")
                } else if (String(place.special || "") === "sftpProfile") {
                    activeTagFilter = ""
                    if (String(place.freeText || "") === "CONNECTED" && String(place.path || "").length) {
                        loadPath(place.path)
                        focusZone = "content"
                    } else {
                        openSftpModal(String(place.profileId || ""))
                    }
                } else if (String(place.special || "") === "tagFilter") {
                    activeTagFilter = String(place.tagId || "")
                    historyNavigationPending = true
                    fileManager.refresh()
                    focusZone = "content"
                } else if (place.enabled !== false && String(place.path || "").length > 0) {
                    activeTagFilter = ""
                    loadPath(place.path)
                    focusZone = "content"
                }
            }
            return
        }
        var item = selectedItem()
        if (!item)
            return
        if (destinationMode) {
            if (item.isDir)
                loadPath(item.path)
            return
        }
        if (item.isDir) {
            loadPath(item.path)
        } else if (!armed) {
            armFile(item)
        } else if (String(armedItem.path) === String(item.path)) {
            openActions()
        } else {
            armFile(item)
        }
    }

    function contextAction() {
        if (editorOpen || previewOpen || inputModalOpen || actionMenuOpen || volumeModalOpen ||
            tagModalOpen || newItemModalOpen || sftpModalOpen)
            return
        openNewItemModal()
    }

    function secondaryAction() {
        if (editorOpen) {
            pasteSystemText(editorText)
            return
        }
        if (inputModalOpen) {
            if (secondaryInput.activeFocus)
                pasteSystemText(secondaryInput)
            else
                pasteSystemText(primaryInput)
            return
        }
        if (volumeModalOpen) {
            if (formatConfirmInput.activeFocus)
                pasteSystemText(formatConfirmInput)
            else
                pasteSystemText(volumeLabelInput)
            return
        }
        if (destinationMode) {
            commitTransfer()
            return
        }
        // Patch 60B: Square pastes the prepared file operation directly.
        // Start > Paste remains available as a secondary route.
        if (backendAvailable && fileManager.clipboardPath.length > 0) {
            fileManager.pasteClipboardPath(currentPath)
            return
        }
        if (armed) {
            beginTransfer("move")
            return
        }
        toggleTheme()
    }

    function quickCopyAction() {
        if (armed) {
            beginTransfer("copy")
            return
        }
        var item = selectedItem()
        if (item) {
            armed = true
            armedItem = item
            originPath = currentPath
            beginTransfer("copy")
        }
    }

    function cancelAction() {
        if (busy)
            return
        if (editorOpen) {
            if (editorDirty && !editorDiscardArmed) {
                editorDiscardArmed = true
                editorDiscardTimer.restart()
                errorBanner.text = "Unsaved changes: save with X/START, or press O again to discard."
                errorBannerTimer.restart()
                return
            }
            editorOpen = false
            editorPath = ""
            editorText.text = ""
            editorDirty = false
            editorDiscardArmed = false
            focusZone = "content"
            forceActiveFocus()
            return
        }
        if (previewOpen) {
            previewOpen = false
            focusZone = "content"
            forceActiveFocus()
            return
        }
        if (volumeModalOpen) {
            volumeModalOpen = false
            focusZone = "content"
            forceActiveFocus()
            return
        }
        if (inputModalOpen) {
            closeInput()
            return
        }
        if (actionMenuOpen) {
            actionMenuOpen = false
            focusZone = "content"
            return
        }
        if (destinationMode || armed) {
            clearArm()
            if (originPath.length > 0)
                loadPath(originPath)
            return
        }
        openExitModal()
    }

    function contentColumnCount() {
        if (viewMode === "grid")
            return Math.max(1, Math.floor((contentPanel.width - 28) / fileGrid.cellWidth))
        return 1
    }

    function ensureContentSelectionVisible() {
        if (fileModel.count <= 0)
            return
        selectedIndex = Math.max(0, Math.min(fileModel.count - 1, selectedIndex))
        if (viewMode === "grid")
            fileGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
        else
            fileList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function setContentSelection(index) {
        if (fileModel.count <= 0)
            return false
        var next = Math.max(0, Math.min(fileModel.count - 1, Number(index)))
        var changed = next !== selectedIndex
        selectedIndex = next
        ensureContentSelectionVisible()
        return changed
    }

    function moveVertical(delta) {
        if (focusZone === "preview" && !previewOpen && !tagModalOpen) {
            return
        }
        if (editorOpen || previewOpen)
            return
        if (volumeModalOpen) {
            if (volumeModel.count > 0)
                volumeIndex = Math.max(0, Math.min(volumeModel.count - 1, volumeIndex + delta))
            return
        }
        if (inputModalOpen)
            return
        if (actionMenuOpen) {
            if (actionModel.count > 0)
                actionIndex = Math.max(0, Math.min(actionModel.count - 1, actionIndex + delta))
            return
        }
        if (focusZone === "search") {
            if (delta > 0) focusZone = "content"
            else focusZone = "sidebar"
            return
        }
        if (focusZone === "sidebar") {
            if (delta < 0 && selectedPlaceIndex === 0) {
                focusZone = "search"
                return
            }
            if (placeModel.count > 0) {
                selectedPlaceIndex = Math.max(0, Math.min(placeModel.count - 1, selectedPlaceIndex + delta))
                placesList.positionViewAtIndex(selectedPlaceIndex, ListView.Contain)
            }
            return
        }
        if (focusZone === "content") {
            if (delta < 0 && selectedIndex === 0) {
                focusZone = "search"
                return
            }
            if (fileModel.count > 0)
                setContentSelection(selectedIndex + delta * contentColumnCount())
        }
    }

    function moveHorizontal(delta) {
        if (volumeModalOpen) {
            filesystemIndex = (filesystemIndex + delta + filesystemOptions.length) % filesystemOptions.length
            return
        }
        if (inputModalOpen && inputOptions.length > 0) {
            inputOptionIndex = (inputOptionIndex + delta + inputOptions.length) % inputOptions.length
            return
        }
        if (actionMenuOpen || editorOpen || previewOpen || tagModalOpen || newItemModalOpen || sftpModalOpen)
            return

        if (focusZone === "header") {
            if (delta < 0) {
                focusZone = "preview"
                previewActionIndex = 1
            }
            return
        }
        if (focusZone === "search") {
            focusZone = delta < 0 ? "sidebar" : "content"
            return
        }
        if (focusZone === "sidebar") {
            if (delta > 0) {
                focusZone = "content"
                ensureContentSelectionVisible()
            }
            return
        }
        if (focusZone === "preview") {
            if (delta > 0) {
                if (previewActionIndex === 0)
                    previewActionIndex = 1
                else
                    focusZone = "header"
            } else {
                if (previewActionIndex === 1)
                    previewActionIndex = 0
                else
                    focusZone = "content"
            }
            return
        }
        if (focusZone !== "content") return

        if (viewMode === "list") {
            if (delta < 0) focusZone = "sidebar"
            else focusZone = "preview"
            return
        }

        if (fileModel.count <= 0) {
            focusZone = delta < 0 ? "sidebar" : "preview"
            return
        }
        var columns = contentColumnCount()
        var col = selectedIndex % columns
        var atLeft = col === 0
        var atRight = col === columns - 1 || selectedIndex === fileModel.count - 1
        if (delta < 0 && atLeft) {
            focusZone = "sidebar"
            return
        }
        if (delta > 0 && atRight) {
            focusZone = "preview"
            return
        }
        setContentSelection(selectedIndex + delta)
    }

    function handleControllerPressed(button) { return handleController(button) }
    function handleController(button) {
        var b = String(button || "").toLowerCase().replace(/\s+/g, "_").replace(/-/g, "_")
        if (b === "dpad_up" || b === "leftstick_up" || b === "rightstick_up") b = "up"
        else if (b === "dpad_down" || b === "leftstick_down" || b === "rightstick_down") b = "down"
        else if (b === "dpad_left" || b === "leftstick_left" || b === "rightstick_left") b = "left"
        else if (b === "dpad_right" || b === "leftstick_right" || b === "rightstick_right") b = "right"
        if (keyboardOpen) {
            if (b === "cancel" || b === "o" || b === "circle" || b === "back") {
                closeKeyboard(false)
                return true
            }
            return virtualKeyboard.handleControllerPressed(b)
        }

        if (editorOpen) {
            if (b === "left") { editorMoveCursorHorizontal(-1); return true }
            if (b === "right") { editorMoveCursorHorizontal(1); return true }
            if (b === "up") { editorMoveCursorVertical(-1); return true }
            if (b === "down") { editorMoveCursorVertical(1); return true }
            if (b === "secondary" || b === "square") { editorBackspace(); return true }
            if (b === "primary" || b === "x") { primaryAction(); return true }
            if (b === "system" || b === "start") { saveEditor(); return true }
            if (b === "cancel" || b === "o") { cancelAction(); return true }
            return true
        }

        if (previewOpen && String(previewData.previewType || "") === "image") {
            if (b === "left") { panImage(-42, 0); return true }
            if (b === "right") { panImage(42, 0); return true }
            if (b === "up") { panImage(0, -42); return true }
            if (b === "down") { panImage(0, 42); return true }
            if (b === "l1") { zoomImage(-0.25); return true }
            if (b === "r1") { zoomImage(0.25); return true }
            if (b === "cancel" || b === "o") { cancelAction(); return true }
            return true
        }
        if (tagModalOpen) {
            if (customTagEditorOpen) {
                if (b === "up") customTagFieldIndex = Math.max(0, customTagFieldIndex - 1)
                else if (b === "down") customTagFieldIndex = Math.min(3, customTagFieldIndex + 1)
                else if (b === "left" && customTagFieldIndex === 1) customTagColorIndex = (customTagColorIndex + tagColors.length - 1) % tagColors.length
                else if (b === "right" && customTagFieldIndex === 1) customTagColorIndex = (customTagColorIndex + 1) % tagColors.length
                else if (b === "left" && customTagFieldIndex === 2) customTagIconIndex = (customTagIconIndex + tagIcons.length - 1) % tagIcons.length
                else if (b === "right" && customTagFieldIndex === 2) customTagIconIndex = (customTagIconIndex + 1) % tagIcons.length
                else if (b === "primary" || b === "x") {
                    if (customTagFieldIndex === 0) openKeyboard("customTagName", "Custom Tag Name")
                    else if (customTagFieldIndex === 3) createAndAssignCustomTag()
                } else if (b === "cancel" || b === "o") customTagEditorOpen = false
                return true
            }
            if (b === "up") tagIndex = Math.max(0, tagIndex - 1)
            else if (b === "down") tagIndex = Math.min(Math.max(0, tagModel.count - 1), tagIndex + 1)
            else if (b === "primary" || b === "x") toggleSelectedTag()
            else if (b === "context" || b === "triangle") { customTagEditorOpen = true; customTagFieldIndex = 0; customTagNameInput.text = "" }
            else if (b === "cancel" || b === "o") closeTagModal()
            return true
        }
        if (newItemModalOpen) {
            if (b === "cancel" || b === "o") { closeNewItemModal(); return true }
            if (newItemStage === 0) {
                if (b === "left" || b === "up") newItemKindIndex = 0
                else if (b === "right" || b === "down") newItemKindIndex = 1
                else if (b === "primary" || b === "x") {
                    newItemStage = 1
                    newItemNameInput.text = newItemKindIndex === 0 ? "New Folder" : "new-file"
                    openKeyboard("newItemName", newItemKindIndex === 0 ? "Folder Name" : "File Name")
                }
                return true
            }
            if (newItemStage === 1) {
                if (b === "primary" || b === "x") openKeyboard("newItemName", newItemKindIndex === 0 ? "Folder Name" : "File Name")
                return true
            }
            if (newItemStage === 2) {
                if (b === "left" || b === "up") newItemTypeIndex = (newItemTypeIndex + newItemTypes.length - 1) % newItemTypes.length
                else if (b === "right" || b === "down") newItemTypeIndex = (newItemTypeIndex + 1) % newItemTypes.length
                else if (b === "primary" || b === "x") createNewTypedFile()
                return true
            }
        }
        if (sftpModalOpen) {
            if (b === "cancel" || b === "o") { if (sftpMode === "edit") sftpMode = "list"; else closeSftpModal(); return true }
            if (sftpMode === "list") {
                if (b === "up") sftpIndex = Math.max(0, sftpIndex - 1)
                else if (b === "down") sftpIndex = Math.min(Math.max(0, sftpModel.count - 1), sftpIndex + 1)
                else if (b === "context" || b === "triangle") loadSftpEditor(({}))
                else if (b === "secondary" || b === "square") {
                    if (sftpModel.count > 0) {
                        var sp = sftpModel.get(sftpIndex)
                        if (sp.connected === true) fileManager.disconnectSftp(String(sp.id || ""))
                        else fileManager.removeSftpConnection(String(sp.id || ""))
                    }
                } else if (b === "primary" || b === "x") {
                    if (sftpModel.count <= 0) loadSftpEditor(({}))
                    else {
                        var prof = sftpModel.get(sftpIndex)
                        if (prof.connected === true && String(prof.mountPath || "").length) {
                            closeSftpModal(); loadPath(String(prof.mountPath))
                        } else loadSftpEditor(prof)
                    }
                }
                return true
            }
            if (sftpMode === "edit") {
                if (b === "up") sftpFieldIndex = Math.max(0, sftpFieldIndex - 1)
                else if (b === "down") sftpFieldIndex = Math.min(7, sftpFieldIndex + 1)
                else if ((b === "left" || b === "right") && sftpFieldIndex === 5) sftpAuthIndex = sftpAuthIndex === 0 ? 1 : 0
                else if (b === "primary" || b === "x") {
                    var targets = ["sftpName","sftpHost","sftpUser","sftpPort","sftpPath","","sftpPassword",""]
                    var labels = ["Server Name","Host","Username","Port","Remote Path","Authentication","Password","Connect"]
                    if (sftpFieldIndex === 5) sftpAuthIndex = sftpAuthIndex === 0 ? 1 : 0
                    else if (sftpFieldIndex === 7) connectEditedSftp()
                    else if (sftpFieldIndex === 6 && sftpAuthIndex === 0) {}
                    else openKeyboard(targets[sftpFieldIndex], labels[sftpFieldIndex])
                }
                return true
            }
        }
        if (exitModalOpen) {
            if ((b === "primary" || b === "x") && referenceExitModal.selectedIndex < 2 && editorDirty) {
                    errorBanner.text = "Save or discard the open editor changes before leaving File Manager."
                    errorBannerTimer.restart()
            } else referenceExitModal.handleController(b)
            return true
        }
        if (focusZone === "header") {
            if (b === "primary" || b === "x") openExitModal()
            else if (b === "left" || b === "down" || b === "cancel" || b === "o") focusZone = "preview"
            return true
        }
        if (quickPlacesModalOpen) {
            if (b === "up" || b === "left") quickPlaceSlot = (quickPlaceSlot + 7) % 8
            else if (b === "down" || b === "right") quickPlaceSlot = (quickPlaceSlot + 1) % 8
            else if (b === "primary" || b === "x") { fileManager.assignQuickPlace(quickPlaceSlot, currentPath, ""); refreshPlaces() }
            else if (b === "context" || b === "triangle" || b === "secondary" || b === "square") { fileManager.removeQuickPlace(quickPlaceSlot); refreshPlaces() }
            else if (b === "cancel" || b === "o" || b === "system" || b === "start") { quickPlacesModalOpen = false; forceActiveFocus() }
            return true
        }
        if (b === "up") { if (focusZone === "search") focusZone = "header"; else moveVertical(-1); return true }
        if (b === "down") { moveVertical(1); return true }
        if (b === "left") { moveHorizontal(-1); return true }
        if (b === "right") { moveHorizontal(1); return true }
        if (b === "primary" || b === "x") { primaryAction(); return true }
        if (b === "context" || b === "triangle") { openSearchBar(); return true }
        if (b === "secondary" || b === "square") { cycleViewMode(); return true }
        if (b === "cancel" || b === "o") { cancelAction(); return true }
        if (b === "system" || b === "start") {
            if (focusZone === "sidebar") openQuickPlacesModal()
            else if (focusZone === "search") clearSearch()
            else openActions()
            return true
        }
        if (b === "quick") { quickCopyAction(); return true }
        if (b === "l1") { if (!editorOpen && !previewOpen && !inputModalOpen) goBack(); return true }
        if (b === "r1") { if (!editorOpen && !previewOpen && !inputModalOpen) goForward(); return true }
        if (b === "r3") {
            if (!editorOpen && !previewOpen && !inputModalOpen &&
                !actionMenuOpen && !volumeModalOpen && !tagModalOpen &&
                !newItemModalOpen && !sftpModalOpen)
                openNewItemModal()
            return true
        }
        if (b === "l2") { var item = selectedItem(); if (item) fileManager.requestMetadata(item.path); metadataMode = true; return true }
        if (b === "r2") { quickCopyAction(); return true }
        return false
    }

    Keys.onPressed: function(event) {
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_S && editorOpen) {
            if (!editorTruncated) {
                fileManager.saveTextFile(editorPath, editorText.text)
                editorDirty = false
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Up) { moveVertical(-1); event.accepted = true
        } else if (event.key === Qt.Key_Down) { moveVertical(1); event.accepted = true
        } else if (event.key === Qt.Key_Left) { moveHorizontal(-1); event.accepted = true
        } else if (event.key === Qt.Key_Right) { moveHorizontal(1); event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { primaryAction(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) { cancelAction(); event.accepted = true
        } else if (event.key === Qt.Key_F1 || event.key === Qt.Key_Menu) {
            if (editorOpen)
                primaryAction()
            else
                openActions()
            event.accepted = true
        } else if (event.key === Qt.Key_F5) { loadPath(currentPath); event.accepted = true }
    }

    Connections {
        target: backendAvailable ? fileManager : null
        ignoreUnknownSignals: true

        function onDirectoryLoaded(path, items) {
            searchPending = false
            currentPath = String(path)
            historyRecord(currentPath)
            if (!destinationMode) {
                searchMode = false
                searchQuery = ""
                searchInput.text = ""
            }
            fileModel.clear()
            for (var i = 0; i < items.length; ++i) {
                var item = items[i]
                if (!showHidden && item.hidden)
                    continue
                if (activeTagFilter.length > 0 && !pathHasTag(String(item.path || ""), activeTagFilter))
                    continue
                fileModel.append({
                    "name": String(item.name || ""),
                    "path": String(item.path || ""),
                    "type": String(item.type || "file"),
                    "isDir": Boolean(item.isDir),
                    "sizeText": String(item.sizeText || ""),
                    "modifiedText": String(item.modifiedText || ""),
                    "mimeType": String(item.mimeType || ""),
                    "extension": String(item.extension || ""),
                    "icon": String(item.icon || "file"),
                    "hidden": Boolean(item.hidden),
                    "writable": Boolean(item.writable)
                })
            }
            selectedIndex = Math.max(0, Math.min(fileModel.count - 1, selectedIndex))
        }


        function onSearchCompleted(query, rootPath, items) {
            searchPending = false
            searchMode = true
            searchQuery = String(query)
            fileModel.clear()
            for (var i = 0; i < items.length; ++i) {
                var item = items[i]
                if (!showHidden && item.hidden) continue
                fileModel.append({
                    "name": String(item.name || ""),
                    "path": String(item.path || ""),
                    "parentPath": String(item.parentPath || ""),
                    "type": String(item.type || "file"),
                    "isDir": Boolean(item.isDir),
                    "sizeText": String(item.sizeText || ""),
                    "modifiedText": String(item.modifiedText || ""),
                    "mimeType": String(item.mimeType || ""),
                    "extension": String(item.extension || ""),
                    "icon": String(item.icon || "file"),
                    "hidden": Boolean(item.hidden),
                    "writable": Boolean(item.writable),
                    "searchResult": true
                })
            }
            selectedIndex = fileModel.count > 0 ? 0 : -1
            focusZone = "content"
            statusToast.text = fileModel.count + " SEARCH RESULT" + (fileModel.count === 1 ? "" : "S")
            statusToastTimer.restart()
        }

        function onQuickPlacesChanged() {
            refreshPlaces()
        }
        function onTagsChanged() {
            tagsRevision++
            refreshTags()
            previewDebounce.restart()
        }
        function onSftpConnectionsChanged() {
            refreshSftpModel()
            refreshPlaces()
        }

        function onOperationCompleted(actionId, path) {
            var action = String(actionId)
            if (action === "move")
                fileManager.clearClipboardPath()
            if (action !== "clipboard-copy" && action !== "clipboard-move" && action !== "save-text")
                clearArm()
            if (action === "sftp-connected") {
                sftpModalOpen = false
                sftpMode = "list"
                refreshSftpModel()
                refreshPlaces()
                loadPath(String(path || currentPath))
                focusZone = "content"
            } else if (action === "sftp-disconnected") {
                refreshSftpModel()
                refreshPlaces()
            } else if (action !== "load-directory" && action !== "clipboard-copy" && action !== "clipboard-move") {
                loadPath(currentPath)
            }
            statusToast.text = action.replace(/-/g, " ").toUpperCase() + " COMPLETE"
            statusToastTimer.restart()
        }

        function onOperationFailed(message) {
            searchPending = false
            errorBanner.text = String(message)
            errorBannerTimer.restart()
        }

        function onQuickLookReady(path, preview) {
            previewPath = String(path)
            previewData = preview
            metadataMode = false
            if (String(preview.previewType || "") === "image")
                resetImageViewer()
            if (manualPreviewPending) {
                manualPreviewPending = false
                previewOpen = true
                focusZone = "preview"
            }
        }

        function onMetadataReady(path, metadata) {
            previewPath = String(path)
            previewData = metadata
            metadataMode = true
            if (manualPreviewPending) {
                manualPreviewPending = false
                previewOpen = true
                focusZone = "preview"
            }
        }

        function onTextFileLoaded(path, text, encoding, truncated) {
            editorPath = String(path)
            editorText.text = String(text)
            editorText.cursorPosition = 0
            editorTruncated = Boolean(truncated)
            editorDirty = false
            editorDiscardArmed = false
            editorOpen = true
            focusZone = "editor"
            Qt.callLater(function() { editorText.forceActiveFocus() })
        }
    }

    Component.onCompleted: {
        forceActiveFocus()
        if (backendAvailable) {
            refreshPlaces()
            refreshTags()
            refreshSftpModel()
            fileManager.initialize()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#02060D"
    }

    Image {
        anchors.fill: parent
        source: app.themeFile("background.png")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        opacity: status === Image.Ready ? 0.12 : 0
    }

    Rectangle {
        anchors.fill: parent
        color: "#C9020710"
    }

    Header {
        id: referenceHeader
        x: 18
        width: parent.width - 36
        anchors.top: parent.top
        height: 54
        z: 120
        secure: !app.securityNeedsAttention()
        securityScore: app.securityBackend && app.securityBackend.securityScore!==undefined ? Math.max(0,Math.min(100,Math.round(Number(app.securityBackend.securityScore)))) : -1
        menuFocused: app.focusZone === "header" && !app.exitModalOpen
        onMenuRequested: app.openExitModal()
    }

    Footer {
        id: referenceFooter
        x: 18
        width: parent.width - 36
        anchors.bottom: parent.bottom
        height: 72
        z: 120
        controllerBackend: app.controllerBackend
        hintText: "D-PAD Navigate   X Open   □ View   △ Search   R3 Add   START Actions   O Exit"
    }

    Timer {
        id: previewDebounce
        interval: 260
        repeat: false
        onTriggered: app.previewSelected()
    }

    // -----------------------------------------------------------------
    // LEFT: LOCATIONS / FAVORITES / STORAGE / NETWORK
    // -----------------------------------------------------------------
    Rectangle {
        id: sidebar
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.top: referenceHeader.bottom
        anchors.topMargin: 10
        anchors.bottom: referenceFooter.top
        anchors.bottomMargin: 10
        width: Math.max(255, Math.min(325, parent.width * 0.16))
        color: "#B8040B15"
        border.width: focusZone === "sidebar" ? 2 : 1
        border.color: focusZone === "sidebar" ? app.focusBlue : "#243246"
        radius: 5

        Text {
            id: locationsTitle
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.top: parent.top
            anchors.topMargin: 14
            text: "LOCATIONS"
            color: "#A8AEB9"
            font.pixelSize: 22
            font.bold: true
            font.letterSpacing: 0.7
        }

        ListView {
            id: placesList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: locationsTitle.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 10
            model: placeModel
            currentIndex: selectedPlaceIndex
            interactive: false
            clip: true
            spacing: 0

            onCurrentIndexChanged: {
                if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)
            }

            delegate: Item {
                width: placesList.width
                height: model.showSection === true ? 70 : 50

                Text {
                    visible: model.showSection === true
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: 5
                    text: String(model.section || "")
                    color: "#7E8798"
                    font.pixelSize: 16
                    font.bold: true
                    font.letterSpacing: 0.9
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 44
                    radius: 6
                    color: focusZone === "sidebar" && selectedPlaceIndex === index
                           ? "#13233B" : "transparent"
                    border.width: focusZone === "sidebar" && selectedPlaceIndex === index ? 1 : 0
                    border.color: focusZone === "sidebar" && selectedPlaceIndex === index
                                  ? "#21C8FF" : "transparent"

                    Rectangle {
                        visible: focusZone === "sidebar" && selectedPlaceIndex === index
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: "#E230FF"
                    }

                    Item {
                        id: sidebarIconCell
                        anchors.left: parent.left
                        anchors.leftMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36

                        readonly property string iconName: String(model.name || "").toLowerCase()
                        readonly property string specialType: String(model.special || "")
                        readonly property bool selectedIcon:
                            focusZone === "sidebar" && selectedPlaceIndex === index
                        readonly property bool importantIcon:
                            iconName === "important"
                        readonly property color iconTone:
                            importantIcon
                            ? (selectedIcon ? "#FF7890" : "#FF4058")
                            : (selectedIcon ? "#FFFFFF" :
                               (String(model.section || "") === "STORAGE"
                                ? "#BFD6FF" : "#55DEFF"))

                        Rectangle {
                            anchors.centerIn: parent
                            width: 34
                            height: 34
                            radius: 8
                            color: sidebarIconCell.importantIcon
                                   ? "#2411181E"
                                   : (sidebarIconCell.selectedIcon ? "#253C5A" : "#120A1521")
                            border.width: sidebarIconCell.selectedIcon ? 2 : 1
                            border.color: sidebarIconCell.iconTone
                        }

                        Canvas {
                            id: sidebarGlyph
                            anchors.centerIn: parent
                            width: 27
                            height: 27
                            antialiasing: true

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.clearRect(0, 0, width, height)

                                var tone = sidebarIconCell.iconTone
                                ctx.strokeStyle = tone
                                ctx.fillStyle = tone
                                ctx.lineWidth = sidebarIconCell.selectedIcon ? 2.4 : 2.15
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"

                                function line(x1, y1, x2, y2) {
                                    ctx.beginPath()
                                    ctx.moveTo(x1, y1)
                                    ctx.lineTo(x2, y2)
                                    ctx.stroke()
                                }

                                function rect(x, y, w, h) {
                                    ctx.beginPath()
                                    ctx.rect(x, y, w, h)
                                    ctx.stroke()
                                }

                                function circle(x, y, r) {
                                    ctx.beginPath()
                                    ctx.arc(x, y, r, 0, Math.PI * 2)
                                    ctx.stroke()
                                }

                                var n = sidebarIconCell.iconName
                                var special = sidebarIconCell.specialType

                                if (n === "home") {
                                    ctx.beginPath()
                                    ctx.moveTo(4, 13)
                                    ctx.lineTo(13.5, 5)
                                    ctx.lineTo(23, 13)
                                    ctx.stroke()
                                    ctx.beginPath()
                                    ctx.moveTo(7, 12)
                                    ctx.lineTo(7, 22)
                                    ctx.lineTo(20, 22)
                                    ctx.lineTo(20, 12)
                                    ctx.stroke()
                                    rect(12, 16, 4, 6)
                                    return
                                }

                                if (n === "desktop") {
                                    rect(4, 5, 19, 13)
                                    line(10, 22, 17, 22)
                                    line(13.5, 18, 13.5, 22)
                                    return
                                }

                                if (n === "documents") {
                                    ctx.beginPath()
                                    ctx.moveTo(7, 3)
                                    ctx.lineTo(17, 3)
                                    ctx.lineTo(22, 8)
                                    ctx.lineTo(22, 24)
                                    ctx.lineTo(7, 24)
                                    ctx.closePath()
                                    ctx.stroke()
                                    line(17, 3, 17, 9)
                                    line(17, 9, 22, 9)
                                    line(10, 14, 19, 14)
                                    line(10, 18, 19, 18)
                                    return
                                }

                                if (n === "downloads") {
                                    line(13.5, 4, 13.5, 17)
                                    ctx.beginPath()
                                    ctx.moveTo(8.5, 12)
                                    ctx.lineTo(13.5, 17.5)
                                    ctx.lineTo(18.5, 12)
                                    ctx.stroke()
                                    line(6, 22, 21, 22)
                                    return
                                }

                                if (n === "pictures") {
                                    rect(4, 5, 19, 17)
                                    circle(18.5, 9.5, 2)
                                    ctx.beginPath()
                                    ctx.moveTo(6.5, 19)
                                    ctx.lineTo(11, 14)
                                    ctx.lineTo(14.5, 17)
                                    ctx.lineTo(17, 14)
                                    ctx.lineTo(21, 19)
                                    ctx.stroke()
                                    return
                                }

                                if (n === "music") {
                                    line(11, 6, 11, 19)
                                    line(11, 6, 20, 4)
                                    line(20, 4, 20, 17)
                                    circle(8, 20, 3)
                                    circle(17, 18, 3)
                                    return
                                }

                                if (n === "videos") {
                                    rect(4, 6, 19, 16)
                                    ctx.beginPath()
                                    ctx.moveTo(11, 10)
                                    ctx.lineTo(18, 14)
                                    ctx.lineTo(11, 18)
                                    ctx.closePath()
                                    ctx.stroke()
                                    return
                                }

                                if (n === "work") {
                                    rect(4, 9, 19, 13)
                                    ctx.beginPath()
                                    ctx.moveTo(9, 9)
                                    ctx.lineTo(9, 6)
                                    ctx.lineTo(18, 6)
                                    ctx.lineTo(18, 9)
                                    ctx.stroke()
                                    line(4, 14, 23, 14)
                                    line(12, 13, 15, 13)
                                    return
                                }

                                if (n === "personal") {
                                    circle(13.5, 8, 4)
                                    ctx.beginPath()
                                    ctx.arc(13.5, 22, 8, Math.PI, Math.PI * 2)
                                    ctx.stroke()
                                    return
                                }

                                if (n === "important") {
                                    ctx.beginPath()
                                    ctx.moveTo(13.5, 4)
                                    ctx.lineTo(24, 23)
                                    ctx.lineTo(3, 23)
                                    ctx.closePath()
                                    ctx.stroke()
                                    line(13.5, 10, 13.5, 16)
                                    circle(13.5, 19.5, 0.7)
                                    return
                                }

                                if (special === "sftp" || special === "sftpProfile" ||
                                    n.indexOf("sftp") >= 0) {
                                    line(4, 9, 21, 9)
                                    ctx.beginPath()
                                    ctx.moveTo(17, 5)
                                    ctx.lineTo(22, 9)
                                    ctx.lineTo(17, 13)
                                    ctx.stroke()

                                    line(23, 18, 6, 18)
                                    ctx.beginPath()
                                    ctx.moveTo(10, 14)
                                    ctx.lineTo(5, 18)
                                    ctx.lineTo(10, 22)
                                    ctx.stroke()
                                    return
                                }

                                if (special === "shared" || n === "shared") {
                                    circle(6, 14, 2.7)
                                    circle(21, 7, 2.7)
                                    circle(21, 21, 2.7)
                                    line(8.5, 12.5, 18.5, 8.3)
                                    line(8.5, 15.5, 18.5, 19.7)
                                    return
                                }

                                // Storage / mounted volume.
                                ctx.beginPath()
                                ctx.moveTo(5, 8)
                                ctx.quadraticCurveTo(5, 5, 8, 5)
                                ctx.lineTo(20, 5)
                                ctx.quadraticCurveTo(23, 5, 23, 8)
                                ctx.lineTo(20, 20)
                                ctx.quadraticCurveTo(19.5, 23, 17, 23)
                                ctx.lineTo(7, 23)
                                ctx.quadraticCurveTo(4.5, 23, 4, 20)
                                ctx.closePath()
                                ctx.stroke()
                                line(8, 18.5, 19, 18.5)
                                ctx.beginPath()
                                ctx.arc(18.5, 14.5, 1.4, 0, Math.PI * 2)
                                ctx.fill()
                            }

                            Connections {
                                target: sidebarIconCell
                                function onIconToneChanged() { sidebarGlyph.requestPaint() }
                                function onIconNameChanged() { sidebarGlyph.requestPaint() }
                                function onSpecialTypeChanged() { sidebarGlyph.requestPaint() }
                                function onSelectedIconChanged() { sidebarGlyph.requestPaint() }
                            }

                            Component.onCompleted: requestPaint()
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 52
                        anchors.right: freeLabel.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(model.name || "Location")
                        color: model.enabled === false ? "#566273" : "#E6EBF4"
                        font.pixelSize: 20
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        id: freeLabel
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: String(model.freeText || "").length > 0
                        text: String(model.section || "") === "STORAGE"
                              ? String(model.freeText || "") + " free"
                              : String(model.freeText || "")
                        color: "#AEB7CA"
                        font.pixelSize: 14
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // CENTER: NAVIGATION + SEARCH + LIST/ICON VIEW
    // -----------------------------------------------------------------
    Rectangle {
        id: contentPanel
        anchors.left: sidebar.right
        anchors.leftMargin: 10
        anchors.right: referenceDetails.left
        anchors.rightMargin: 10
        anchors.top: sidebar.top
        anchors.bottom: sidebar.bottom
        color: "#AE030A14"
        border.width: focusZone === "content" || focusZone === "search" ? 2 : 1
        border.color: focusZone === "content" || focusZone === "search" ? "#1F9FFF" : "#243246"
        radius: 5
        clip: true

        Rectangle {
            id: toolbar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 70
            color: "#7D050C17"
            border.width: 0

            Row {
                id: navButtons
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Repeater {
                    model: [
                        {glyph:"←", enabled:app.historyIndex > 0, action:"back"},
                        {glyph:"→", enabled:app.historyIndex >= 0 && app.historyIndex < app.pathHistory.length - 1, action:"forward"},
                        {glyph:"↑", enabled:app.currentPath !== "/", action:"up"},
                        {glyph:"↻", enabled:true, action:"refresh"}
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: 40
                        height: 40
                        radius: 4
                        color: "#07111E"
                        border.width: 1
                        border.color: modelData.enabled ? "#2C4057" : "#172332"
                        opacity: modelData.enabled ? 1.0 : 0.45

                        Text {
                            anchors.centerIn: parent
                            text: String(modelData.glyph)
                            color: "#E8EDF6"
                            font.pixelSize: 20
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.enabled
                            onClicked: {
                                if (modelData.action === "back") app.goBack()
                                else if (modelData.action === "forward") app.goForward()
                                else if (modelData.action === "up") app.goUp()
                                else app.refreshCurrent()
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: breadcrumb
                anchors.left: navButtons.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(240, parent.width * 0.34)
                height: 40
                radius: 5
                color: "#07111E"
                border.width: 1
                border.color: "#1D2C40"

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 13
                    text: app.searchMode
                          ? ("Search / " + app.searchQuery)
                          : String(app.currentPath || "/")
                    color: "#C6CCD7"
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }
            }

            Rectangle {
                id: newButton
                anchors.right: searchBar.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 78
                height: 40
                radius: 5
                color: "#07111E"
                border.width: 1
                border.color: "#1A9EFF"

                Text {
                    anchors.centerIn: parent
                    text: "+  NEW"
                    color: "#6FD9FF"
                    font.pixelSize: 11
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: app.openActions()
                }
            }

            Rectangle {
                id: searchBar
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(185, parent.width * 0.23)
                height: 40
                radius: 5
                color: "#07111E"
                border.width: focusZone === "search" ? 2 : 1
                border.color: focusZone === "search" ? "#21C8FF" : "#1D2C40"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⌕"
                    color: "#AEB8CA"
                    font.pixelSize: 16
                }

                TextInput {
                    id: searchInput
                    anchors.left: parent.left
                    anchors.leftMargin: 34
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    text: app.searchQuery
                    color: "#E6EBF4"
                    selectionColor: "#1A8CFF"
                    selectedTextColor: "#FFFFFF"
                    font.pixelSize: 12
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    inputMethodHints: Qt.ImhNoPredictiveText
                    onAccepted: app.runSearch()
                }

                Text {
                    visible: searchInput.text.length === 0
                    anchors.left: parent.left
                    anchors.leftMargin: 34
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search files..."
                    color: "#667286"
                    font.pixelSize: 12
                }
            }
        }

        Rectangle {
            id: listHeader
            visible: app.viewMode === "list"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: toolbar.bottom
            height: 39
            color: "#4C050B14"
            border.width: 0

            Text { x:16; width:parent.width*.40; anchors.verticalCenter:parent.verticalCenter; text:"NAME  ↑"; color:"#8894A6"; font.pixelSize:14; font.bold:true }
            Text { x:parent.width*.44; width:parent.width*.20; anchors.verticalCenter:parent.verticalCenter; text:"TYPE"; color:"#8894A6"; font.pixelSize:14; font.bold:true }
            Text { x:parent.width*.66; width:parent.width*.19; anchors.verticalCenter:parent.verticalCenter; text:"MODIFIED"; color:"#8894A6"; font.pixelSize:14; font.bold:true }
            Text { anchors.right:parent.right; anchors.rightMargin:18; width:parent.width*.12; anchors.verticalCenter:parent.verticalCenter; text:"SIZE"; color:"#8894A6"; font.pixelSize:14; font.bold:true; horizontalAlignment:Text.AlignRight }

            Rectangle { anchors.left:parent.left; anchors.right:parent.right; anchors.bottom:parent.bottom; height:1; color:"#1C2A3C" }
        }

        Rectangle {
            id: searchWaitingOverlay
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: toolbar.bottom
            anchors.bottom: statusStrip.top
            visible: app.searchPending
            z: 20
            color: "#84030A14"

            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.62
                height: 8
                radius: 4
                color: "#142035"
                clip: true

                Rectangle {
                    id: searchProgressBar
                    width: parent.width * 0.28
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#14BFFF" }
                        GradientStop { position: 1.0; color: "#B838FF" }
                    }

                    SequentialAnimation on x {
                        running: app.searchPending
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: -searchProgressBar.width
                            to: searchProgressBar.parent.width
                            duration: 1050
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            Text {
                anchors.top: parent.top
                anchors.topMargin: 24
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SEARCHING…"
                color: "#D9E6F7"
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1.2
            }

            MouseArea { anchors.fill: parent }
        }

        Text {
            anchors.centerIn: fileArea
            visible: fileModel.count === 0 && !busy
            text: errorText.length > 0 ? errorText :
                  (searchMode ? "No files matched this search" : "This folder is empty")
            color: errorText.length > 0 ? app.danger : "#718096"
            font.pixelSize: 17
            font.bold: true
            z: 3
        }

        Item {
            id: fileArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: app.viewMode === "list" ? listHeader.bottom : toolbar.bottom
            anchors.bottom: statusStrip.top
            clip: true

            ListView {
                id: fileList
                visible: app.viewMode === "list"
                anchors.fill: parent
                model: fileModel
                currentIndex: selectedIndex
                interactive: false
                clip: true
                spacing: 0

                delegate: Rectangle {
                    width: fileList.width
                    height: 58
                    color: selectedIndex === index && focusZone === "content"
                           ? "#10243A" : "transparent"
                    border.width: 0

                    Rectangle {
                        visible: selectedIndex === index && focusZone === "content"
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: "#1CCBFF"
                    }
                    Rectangle {
                        visible: selectedIndex === index && focusZone === "content"
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: "#E02BFF"
                    }

                    Text {
                        x: 17
                        anchors.verticalCenter: parent.verticalCenter
                        text: app.fileGlyph(model)
                        color: model.isDir ? "#2FC8FF" :
                               String(model.icon || "") === "encrypted" ? "#B85EFF" : "#9E64FF"
                        font.pixelSize: String(text).length > 2 ? 15 : 24
                        font.bold: true
                    }
                    Text {
                        x: 51
                        width: parent.width * .36
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(model.name || "")
                        color: "#E8EDF6"
                        font.pixelSize: 17
                        elide: Text.ElideMiddle
                    }
                    Text {
                        x: parent.width * .44
                        width: parent.width * .19
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.isDir ? "Folder" :
                              (String(model.extension || "").length
                               ? String(model.extension).toUpperCase() + " File"
                               : String(model.type || "File"))
                        color: "#9EA7B8"
                        font.pixelSize: 15
                        elide: Text.ElideRight
                    }
                    Text {
                        x: parent.width * .66
                        width: parent.width * .19
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(model.modifiedText || "")
                        color: "#9EA7B8"
                        font.pixelSize: 15
                        elide: Text.ElideRight
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        width: parent.width * .11
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.isDir ? "—" : String(model.sizeText || "—")
                        color: "#C2C9D6"
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: "#142235"
                    }
                }
            }

            GridView {
                id: fileGrid
                visible: app.viewMode === "grid"
                anchors.fill: parent
                anchors.margins: 14
                model: fileModel
                currentIndex: selectedIndex
                interactive: false
                clip: true
                cellWidth: 160
                cellHeight: 142

                delegate: Rectangle {
                    width: 146
                    height: 128
                    radius: 5
                    color: selectedIndex === index && focusZone === "content"
                           ? "#10243A" : "#08111E"
                    border.width: selectedIndex === index && focusZone === "content" ? 1 : 1
                    border.color: selectedIndex === index && focusZone === "content"
                                  ? "#21C8FF" : "#18263A"

                    Rectangle {
                        visible: selectedIndex === index && focusZone === "content"
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: "#E230FF"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 14
                        text: app.fileGlyph(model)
                        color: model.isDir ? "#29C8FF" : "#9C5BFF"
                        font.pixelSize: String(text).length > 2 ? 20 : 38
                        font.bold: true
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        y: 58
                        height: 31
                        text: String(model.name || "")
                        color: "#E8EDF6"
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 7
                        text: model.isDir ? "Folder" : String(model.sizeText || "")
                        color: "#78859A"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle {
            id: statusStrip
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 40
            color: "#62050B14"
            border.width: 0

            Rectangle { anchors.left:parent.left; anchors.right:parent.right; anchors.top:parent.top; height:1; color:"#1C2A3C" }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: (app.activeTagFilter.length
                       ? ("TAG: " + app.activeTagFilter.toUpperCase() + "  •  ")
                       : "") +
                      fileModel.count + " items  •  " +
                      app.folderCount() + " folders, " +
                      app.fileCountOnly() + " files"
                color: "#9CA6B7"
                font.pixelSize: 10
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: app.currentFreeText()
                color: "#B7C0CF"
                font.pixelSize: 10
            }
        }
    }

    // -----------------------------------------------------------------
    // RIGHT: PREVIEW / DETAILS
    // -----------------------------------------------------------------
    Rectangle {
        id: referenceDetails
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.top: sidebar.top
        anchors.bottom: sidebar.bottom
        width: Math.max(360, parent.width * 0.285)
        color: "#AE030A14"
        border.width: focusZone === "preview" ? 2 : 1
        border.color: focusZone === "preview" ? "#21C8FF" : "#243246"
        radius: 5
        clip: true

        property var itemData: app.selectedItem() || ({})
        readonly property bool hasPreview:
            String(app.previewPath || "") === String(itemData.path || "")
        readonly property var livePreview:
            hasPreview ? app.previewData : ({})

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 9

            Text {
                width: parent.width
                text: "PREVIEW"
                color: "#AEB7C7"
                font.pixelSize: 19
                font.bold: true
                font.letterSpacing: 0.6
            }

            Rectangle {
                id: previewViewport
                width: parent.width
                height: Math.max(190, parent.height * 0.31)
                color: "#050B13"
                border.width: 1
                border.color: "#18283B"
                radius: 4
                clip: true

                readonly property string previewType:
                    String(referenceDetails.livePreview.previewType || "").toLowerCase()
                readonly property bool imagePreview:
                    previewType === "image" &&
                    String(referenceDetails.livePreview.url ||
                           referenceDetails.livePreview.previewUrl || "").length > 0
                readonly property bool textPreview:
                    previewType === "text" &&
                    app.previewTextSnippet().length > 0

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: "#122032"
                    opacity: .65
                }

                Image {
                    id: previewImage
                    anchors.fill: parent
                    anchors.margins: 10
                    source: previewViewport.imagePreview
                            ? String(referenceDetails.livePreview.url ||
                                     referenceDetails.livePreview.previewUrl || "")
                            : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                    visible: previewViewport.imagePreview && status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: previewViewport.textPreview
                    radius: 3
                    color: "#D9060C16"
                    border.width: 1
                    border.color: "#1C3248"

                    Text {
                        anchors.fill: parent
                        anchors.margins: 8
                        text: app.previewTextSnippet()
                        color: "#D8E2F0"
                        font.family: "monospace"
                        font.pixelSize: 11
                        lineHeight: 1.08
                        wrapMode: Text.WrapAnywhere
                        verticalAlignment: Text.AlignTop
                        clip: true
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !previewViewport.textPreview &&
                             !(previewViewport.imagePreview && previewImage.status === Image.Ready)
                    text: referenceDetails.itemData.isDir === true
                          ? "▰"
                          : app.fileGlyph(referenceDetails.itemData)
                    color: referenceDetails.itemData.isDir === true ? "#2DCBFF" : "#A761FF"
                    font.pixelSize: 62
                    font.bold: true
                }
            }

            Text {
                width: parent.width
                text: String(referenceDetails.itemData.name || "No file selected")
                color: "#F0F3F8"
                font.pixelSize: 22
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: referenceDetails.itemData.isDir === true
                      ? "Folder"
                      : (String(referenceDetails.itemData.extension || "").length
                         ? String(referenceDetails.itemData.extension).toUpperCase() + " File"
                         : String(referenceDetails.itemData.type || "File"))
                color: "#9DA7B8"
                font.pixelSize: 16
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#1B293A"
            }

            Text {
                text: "DETAILS"
                color: "#AEB7C7"
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 0.5
            }

            Repeater {
                model: [
                    {label:"Size", value:String(referenceDetails.itemData.sizeText || "—")},
                    {label:"Modified", value:String(referenceDetails.itemData.modifiedText || "—")},
                    {label:"Owner", value:String(referenceDetails.livePreview.owner || "neutronos")},
                    {label:"Permissions", value:app.humanPermissions(referenceDetails.livePreview.permissionsText || referenceDetails.livePreview.permissions || referenceDetails.livePreview.mode || "")}
                ]

                delegate: Row {
                    required property var modelData
                    width: parent.width
                    height: modelData.label === "Permissions" ? 46 : 30
                    spacing: 8

                    Text {
                        width: parent.width * .36
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(modelData.label)
                        color: "#7F8999"
                        font.pixelSize: 15
                    }
                    Text {
                        width: parent.width * .64 - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(modelData.value)
                        color: "#C6CCD7"
                        font.pixelSize: modelData.label === "Permissions" ? 13 : 15
                        wrapMode: modelData.label === "Permissions" ? Text.WordWrap : Text.NoWrap
                        maximumLineCount: modelData.label === "Permissions" ? 2 : 1
                        elide: Text.ElideRight
                    }
                }
            }

            Text {
                text: "PATH"
                color: "#AEB7C7"
                font.pixelSize: 15
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 38
                color: "#07111E"
                border.width: 1
                border.color: "#1A2A3C"
                radius: 4

                Text {
                    anchors.fill: parent
                    anchors.margins: 8
                    text: String(referenceDetails.itemData.path || "")
                    color: "#A8B2C2"
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }
            }


            Text {
                width: parent.width
                text: "TAGS"
                color: "#AEB7C7"
                font.pixelSize: 15
                font.bold: true
            }

            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: app.tagsForSelected()
                    delegate: Rectangle {
                        required property var modelData
                        width: tagChipText.implicitWidth + 28
                        height: 28
                        radius: 6
                        color: "#15121F"
                        border.width: 1
                        border.color: String(modelData.color || "#21C8FF")
                        Text {
                            id: tagChipText
                            anchors.centerIn: parent
                            text: String(modelData.icon || "★") + "  " + String(modelData.name || "Tag")
                            color: String(modelData.color || "#DCE7F7")
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                }
            }

            Item {
                width: 1
                height: Math.max(0, referenceDetails.height - y - 76)
            }

            Row {
                width: parent.width
                height: 48
                spacing: 8

                Rectangle {
                    width: parent.width - 64
                    height: parent.height
                    radius: 5
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#058DFF" }
                        GradientStop { position: 1.0; color: "#B429F2" }
                    }
                    border.width: app.focusZone === "preview" && app.previewActionIndex === 0 ? 2 : 0
                    border.color: "#FFFFFF"
                    Text { anchors.centerIn: parent; text: "▰   OPEN"; color: "#FFFFFF"; font.pixelSize: 16; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: { app.previewActionIndex = 0; app.focusZone = "preview"; app.primaryAction() } }
                }

                Rectangle {
                    width: 56
                    height: parent.height
                    radius: 5
                    color: "#07111E"
                    border.width: app.focusZone === "preview" && app.previewActionIndex === 1 ? 2 : 1
                    border.color: app.focusZone === "preview" && app.previewActionIndex === 1 ? "#21C8FF" : "#30445E"
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater { model: 3; Rectangle { width: 6; height: 6; radius: 3; color: index === 0 ? "#21C8FF" : index === 1 ? "#7965FF" : "#E230FF" } }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { app.previewActionIndex = 1; app.focusZone = "preview"; app.openTagModal() } }
                }
            }
        }
    }

    // TAGS -----------------------------------------------------------------
    Rectangle {
        id: tagOverlay
        anchors.fill: parent
        visible: app.tagModalOpen
        color: "#C9000000"
        z: 155

        Rectangle {
            anchors.centerIn: parent
            width: 760
            height: 650
            radius: 20
            color: "#06101A"
            border.width: 2
            border.color: "#21C8FF"

            Column {
                anchors.fill: parent
                anchors.margins: 26
                spacing: 14

                Text { width: parent.width; text: customTagEditorOpen ? "CUSTOM TAG" : "FILE TAGS"; color: "#F2F6FF"; font.pixelSize: 26; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: customTagEditorOpen ? "Choose a name, color and icon." : "X toggles a tag on the selected file. Triangle creates a custom tag."; color: "#98A6BA"; font.pixelSize: 15; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                Rectangle { width: parent.width; height: 1; color: "#243246" }

                ListView {
                    visible: !customTagEditorOpen
                    width: parent.width
                    height: parent.height - 115
                    model: tagModel
                    currentIndex: tagIndex
                    interactive: false
                    spacing: 6

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 58
                        radius: 7
                        color: tagIndex === index ? "#102B3D" : "#07111C"
                        border.width: tagIndex === index ? 2 : 1
                        border.color: tagIndex === index ? "#21C8FF" : "#243246"
                        Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: String(model.icon || "★"); color: String(model.color || "#21C8FF"); font.pixelSize: 24; font.bold: true }
                        Text { anchors.left: parent.left; anchors.leftMargin: 58; anchors.verticalCenter: parent.verticalCenter; text: String(model.name || "Tag"); color: "#F0F4FB"; font.pixelSize: 19; font.bold: true }
                        Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: app.selectedHasTag(model.id) ? "ASSIGNED" : ""; color: "#43E89A"; font.pixelSize: 15; font.bold: true }
                    }
                }

                Column {
                    visible: customTagEditorOpen
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: [
                            {label:"NAME", value:customTagNameInput.text.length ? customTagNameInput.text : "Custom Tag"},
                            {label:"COLOR", value:String(tagColors[customTagColorIndex])},
                            {label:"ICON", value:String(tagIcons[customTagIconIndex])},
                            {label:"CREATE", value:"Assign to selected file"}
                        ]
                        delegate: Rectangle {
                            width: parent.width
                            height: 70
                            radius: 8
                            color: customTagFieldIndex === index ? "#102B3D" : "#07111C"
                            border.width: customTagFieldIndex === index ? 2 : 1
                            border.color: customTagFieldIndex === index ? "#21C8FF" : "#243246"
                            Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: "#8795AA"; font.pixelSize: 15; font.bold: true }
                            Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: modelData.value; color: index === 1 ? String(tagColors[customTagColorIndex]) : index === 2 ? String(tagColors[customTagColorIndex]) : "#F1F5FB"; font.pixelSize: index === 2 ? 25 : 18; font.bold: true }
                        }
                    }
                    TextInput { id: customTagNameInput; visible: false }
                }

                Text { width: parent.width; text: customTagEditorOpen ? "UP/DOWN Field   X Edit/Create   LEFT/RIGHT Color/Icon   O Back" : "UP/DOWN Select   X Assign/Remove   △ Custom   O Close"; color: "#718198"; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    // NEW FILE / FOLDER ------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        visible: app.newItemModalOpen
        color: "#C9000000"
        z: 154
        Rectangle {
            anchors.centerIn: parent
            width: 720
            height: 480
            radius: 20
            color: "#06101A"
            border.width: 2
            border.color: "#43E89A"
            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 20
                Text { width: parent.width; text: "NEW FILE / FOLDER"; color: "#F2F6FF"; font.pixelSize: 27; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: newItemStage === 0 ? "What do you want to create?" : newItemStage === 1 ? "Choose the name." : "Choose the file type."; color: "#9DAABD"; font.pixelSize: 17; horizontalAlignment: Text.AlignHCenter }
                Row {
                    visible: newItemStage === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 18
                    Repeater {
                        model: [{name:"FOLDER", icon:"▰"}, {name:"FILE", icon:"▤"}]
                        delegate: Rectangle {
                            width: 270; height: 130; radius: 12
                            color: newItemKindIndex === index ? "#123527" : "#07111C"
                            border.width: newItemKindIndex === index ? 2 : 1
                            border.color: newItemKindIndex === index ? "#43E89A" : "#243246"
                            Column { anchors.centerIn: parent; spacing: 8; Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: "#43E89A"; font.pixelSize: 36 } Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; color: "#F1F5FB"; font.pixelSize: 20; font.bold: true } }
                        }
                    }
                }
                Rectangle {
                    visible: newItemStage === 1
                    width: parent.width; height: 72; radius: 10; color: "#07111C"; border.width: 2; border.color: "#43E89A"
                    Text { anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: newItemNameInput.text.length ? newItemNameInput.text : "Press X to enter a name"; color: "#F1F5FB"; font.pixelSize: 19 }
                    TextInput { id: newItemNameInput; visible: false }
                }
                Rectangle {
                    visible: newItemStage === 2
                    width: parent.width; height: 90; radius: 10; color: "#07111C"; border.width: 2; border.color: "#43E89A"
                    Column { anchors.centerIn: parent; spacing: 4; Text { anchors.horizontalCenter: parent.horizontalCenter; text: newItemNameInput.text; color: "#AAB6C8"; font.pixelSize: 15 } Text { anchors.horizontalCenter: parent.horizontalCenter; text: "◀   ." + String(newItemTypes[newItemTypeIndex]) + "   ▶"; color: "#43E89A"; font.pixelSize: 24; font.bold: true } }
                }
                Item { width: 1; height: 1 }
                Text { width: parent.width; text: newItemStage === 0 ? "LEFT/RIGHT Choose   X Continue   O Cancel" : newItemStage === 1 ? "X Enter Name   O Cancel" : "LEFT/RIGHT Type   X Create   O Cancel"; color: "#718198"; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    // SFTP ------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        visible: app.sftpModalOpen
        color: "#C9000000"
        z: 153
        Rectangle {
            anchors.centerIn: parent
            width: 900
            height: 700
            radius: 20
            color: "#06101A"
            border.width: 2
            border.color: "#21C8FF"
            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12
                Text { width: parent.width; text: sftpMode === "list" ? "SFTP SERVERS" : "SFTP CONNECTION"; color: "#F2F6FF"; font.pixelSize: 28; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: backendAvailable && fileManager.sftpAvailable ? "Remote servers mount through SSHFS so normal File Manager open/edit/save operations work." : "SSHFS is not installed. Install the sshfs package to enable SFTP mounts."; color: backendAvailable && fileManager.sftpAvailable ? "#91A2B8" : "#FFB23E"; font.pixelSize: 15; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                Rectangle { width: parent.width; height: 1; color: "#243246" }

                ListView {
                    visible: sftpMode === "list"
                    width: parent.width
                    height: parent.height - 125
                    model: sftpModel
                    currentIndex: sftpIndex
                    interactive: false
                    spacing: 7
                    delegate: Rectangle {
                        width: ListView.view.width; height: 70; radius: 8
                        color: sftpIndex === index ? "#102B3D" : "#07111C"
                        border.width: sftpIndex === index ? 2 : 1
                        border.color: sftpIndex === index ? "#21C8FF" : "#243246"
                        Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "⇄"; color: model.connected === true ? "#43E89A" : "#21C8FF"; font.pixelSize: 26; font.bold: true }
                        Column { anchors.left: parent.left; anchors.leftMargin: 60; anchors.right: parent.right; anchors.rightMargin: 145; anchors.verticalCenter: parent.verticalCenter; spacing: 2; Text { width: parent.width; text: String(model.name || model.host || "SFTP"); color: "#F1F5FB"; font.pixelSize: 19; font.bold: true; elide: Text.ElideRight } Text { width: parent.width; text: String(model.user || "") + "@" + String(model.host || "") + ":" + String(model.remotePath || "/"); color: "#8F9EB2"; font.pixelSize: 14; elide: Text.ElideMiddle } }
                        Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: model.connected === true ? "CONNECTED" : "OFFLINE"; color: model.connected === true ? "#43E89A" : "#FFB23E"; font.pixelSize: 14; font.bold: true }
                    }
                }

                Column {
                    visible: sftpMode === "edit"
                    width: parent.width
                    spacing: 7
                    Repeater {
                        model: ["NAME","HOST","USERNAME","PORT","REMOTE PATH","AUTH","PASSWORD","CONNECT"]
                        delegate: Rectangle {
                            width: parent.width; height: 56; radius: 7
                            color: sftpFieldIndex === index ? "#102B3D" : "#07111C"
                            border.width: sftpFieldIndex === index ? 2 : 1
                            border.color: sftpFieldIndex === index ? "#21C8FF" : "#243246"
                            Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: "#8392A8"; font.pixelSize: 14; font.bold: true }
                            Text { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; width: parent.width * .62; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle; text: index === 0 ? sftpNameInput.text : index === 1 ? sftpHostInput.text : index === 2 ? sftpUserInput.text : index === 3 ? sftpPortInput.text : index === 4 ? sftpPathInput.text : index === 5 ? (sftpAuthIndex === 0 ? "SSH KEY" : "PASSWORD") : index === 6 ? (sftpAuthIndex === 0 ? "Not required" : (sftpPasswordInput.text.length ? "••••••••" : "Enter password")) : "SAVE & CONNECT"; color: index === 7 ? "#43E89A" : "#F1F5FB"; font.pixelSize: 16; font.bold: index === 7 }
                        }
                    }
                    TextInput { id:sftpNameInput; visible:false }
                    TextInput { id:sftpHostInput; visible:false }
                    TextInput { id:sftpUserInput; visible:false }
                    TextInput { id:sftpPortInput; visible:false; inputMethodHints: Qt.ImhDigitsOnly }
                    TextInput { id:sftpPathInput; visible:false }
                    TextInput { id:sftpPasswordInput; visible:false; echoMode: TextInput.Password }
                }

                Text { width: parent.width; text: sftpMode === "list" ? "X Open/Edit   △ Add Server   □ Disconnect/Remove   O Close" : "UP/DOWN Field   X Edit/Connect   LEFT/RIGHT Auth   O Back"; color: "#718198"; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        id: quickPlacesOverlay
        anchors.fill: parent
        visible: app.quickPlacesModalOpen
        color: "#C2000000"
        z: 48

        Rectangle {
            anchors.centerIn: parent
            width: 980
            height: 700
            radius: 36
            color: app.panelColor
            border.width: 3
            border.color: app.warning

            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 18

                Text {
                    width: parent.width
                    text: "QUICK STORAGE TABS"
                    color: app.textPrimary
                    font.pixelSize: 31
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: "Assign the current folder to one of eight fast-access slots. Quick tabs appear beneath the standard Places list."
                    color: app.textSecondary
                    font.pixelSize: 15
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    width: parent.width
                    height: 64
                    radius: 18
                    color: app.panelInset
                    border.width: 1
                    border.color: app.divider
                    Text {
                        anchors.fill: parent
                        anchors.margins: 14
                        text: "CURRENT FOLDER  •  " + app.currentPath
                        color: app.cyan
                        font.pixelSize: 14
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                    }
                }
                Grid {
                    id: quickSlotGrid
                    width: parent.width
                    columns: 4
                    columnSpacing: 14
                    rowSpacing: 14

                    Repeater {
                        model: 8
                        Rectangle {
                            property var assignedPlace: app.quickPlaceForSlot(index)
                            width: (quickSlotGrid.width - 42) / 4
                            height: 150
                            radius: 24
                            color: index === app.quickPlaceSlot
                                   ? (app.lightMode ? "#FFF3D6" : "#4A3510") : app.panelRaised
                            border.width: index === app.quickPlaceSlot ? 3 : 1
                            border.color: index === app.quickPlaceSlot ? app.warning : app.divider

                            Column {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 8
                                Text {
                                    width: parent.width
                                    text: "SLOT " + (index + 1)
                                    color: app.warning
                                    font.pixelSize: 12
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    width: parent.width
                                    text: parent.parent.assignedPlace ? String(parent.parent.assignedPlace.name || "Quick Place") : "EMPTY"
                                    color: app.textPrimary
                                    font.pixelSize: 16
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    height: 52
                                    text: parent.parent.assignedPlace ? String(parent.parent.assignedPlace.path || "") : "Press X to assign the current folder"
                                    color: app.textMuted
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: "D-PAD SELECT   •   X ASSIGN CURRENT FOLDER   •   △ / □ REMOVE SLOT   •   O CLOSE"
                    color: app.textMuted
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        id: exitOverlay
        anchors.fill: parent
        visible: false
        color: "#C2000000"
        z: 160

        Rectangle {
            anchors.centerIn: parent
            width: 980
            height: 440
            radius: 34
            color: app.panelColor
            border.width: 2
            border.color: app.exitChoice === 2 ? app.danger : (app.exitChoice === 1 ? app.purple : app.success)

            Column {
                anchors.fill: parent
                anchors.margins: 36
                spacing: 24
                Text { width: parent.width; text: "LEAVE FILE MANAGER"; color: app.textPrimary; font.pixelSize: 32; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text {
                    width: parent.width
                    text: app.editorDirty
                          ? "A file still has unsaved changes. Resume and save or discard it before leaving."
                          : "Leave Running closes the visual file browser while active native copy, move, archive, encryption, or formatting work continues."
                    color: app.editorDirty ? app.warning : app.textSecondary
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 18
                    Repeater {
                        model: [
                            { label: "RESUME", tone: app.success },
                            { label: "LEAVE RUNNING", tone: app.purple },
                            { label: "EXIT", tone: app.danger }
                        ]
                        Rectangle {
                            required property var modelData; required property int index
                            width: 270; height: 92; radius: 28
                            color: app.exitChoice === index ? Qt.rgba(modelData.tone.r, modelData.tone.g, modelData.tone.b, 0.34) : app.panelRaised
                            border.width: app.exitChoice === index ? 3 : 1
                            border.color: modelData.tone
                            opacity: app.editorDirty && index > 0 ? 0.45 : 1.0
                            Text { anchors.centerIn: parent; text: modelData.label; color: modelData.tone; font.pixelSize: 18; font.bold: true }
                        }
                    }
                }
                Text { width: parent.width; text: "LEFT / RIGHT  CHOOSE     X  CONFIRM     O  RESUME"; color: app.textMuted; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Shared.ReferenceExitModal {
        id: referenceExitModal
        appName: "File Manager"
        onExitRequested: app.exitRequested()
        onLeaveRunningRequested: app.backgroundRequested()
        onDismissed: { app.exitModalOpen = false; app.forceActiveFocus() }
    }

    Shared.VirtualKeyboard {
        id: virtualKeyboard
        z: 175
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        active: visibleMode
        largeMode: true
        cancelBehavior: "close"
        title: "File Manager Keyboard"

        onKeyPressed: function(value) { app.keyboardAppend(value) }
        onBackspacePressed: app.keyboardBackspace()
        onEnterPressed: {
            if (app.keyboardTarget === "editor")
                app.keyboardAppend("\n")
            else
                app.closeKeyboard(true)
        }
        onClosePressed: app.closeKeyboard(false)
    }

    // Action menu
    Rectangle {
        visible: actionMenuOpen
        anchors.fill: parent
        color: "#b8000000"
        z: 50

        Rectangle {
            width: 520
            height: Math.min(650, 128 + actionModel.count * 52)
            anchors.centerIn: parent
            radius: 32
            color: app.panelColor
            border.width: 2
            border.color: app.focusBlue

            Text {
                x: 28
                y: 22
                text: armed ? "Armed Item Actions" : (selectedItem() ? "File Actions" : "File Manager Tools")
                color: app.textPrimary
                font.pixelSize: 25
                font.bold: true
            }
            Text {
                x: 28
                y: 56
                width: parent.width - 56
                text: armed ? String(armedItem.path || "") : currentPath
                color: app.textMuted
                font.pixelSize: 12
                elide: Text.ElideMiddle
            }

            ListView {
                x: 22
                y: 90
                width: parent.width - 44
                height: parent.height - 130
                model: actionModel
                currentIndex: actionIndex
                interactive: false
                clip: true
                spacing: 7

                delegate: Rectangle {
                    width: parent.width
                    height: 45
                    radius: 15
                    color: actionIndex === index ? (app.lightMode ? "#DCEEFF" : "#17365D") : app.panelRaised
                    border.width: actionIndex === index ? 2 : 1
                    border.color: model.destructive && actionIndex === index ? app.danger
                                  : actionIndex === index ? app.focusBlue : app.divider
                    Text {
                        anchors.centerIn: parent
                        text: String(model.label || "")
                        color: model.destructive ? app.danger : "white"
                        font.pixelSize: 15
                        font.bold: true
                    }
                }
            }
        }
    }

    // Generic input modal
    Rectangle {
        visible: inputModalOpen
        anchors.fill: parent
        color: "#c0000000"
        z: 60

        Rectangle {
            width: 720
            height: inputNeedsPassword ? 430 : 350
            anchors.centerIn: parent
            radius: 32
            color: app.panelColor
            border.width: 2
            border.color: inputMode === "trash" ? app.danger : app.focusBlue

            Text {
                x: 32
                y: 24
                text: inputTitle
                color: inputMode === "trash" ? app.danger : "white"
                font.pixelSize: 27
                font.bold: true
            }
            Text {
                x: 32
                y: 65
                width: parent.width - 64
                text: inputHint
                color: app.textSecondary
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }

            Rectangle {
                x: 32
                y: 112
                width: parent.width - 64
                height: 58
                radius: 17
                color: app.panelInset
                border.width: primaryInput.activeFocus ? 2 : 1
                border.color: primaryInput.activeFocus ? app.focusBlue : app.divider
                TextInput {
                    id: primaryInput
                    anchors.fill: parent
                    anchors.margins: 15
                    color: app.textPrimary
                    font.pixelSize: 17
                    selectByMouse: false
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    onAccepted: inputNeedsPassword ? secondaryInput.forceActiveFocus() : confirmInput()
                }
            }

            Rectangle {
                visible: inputOptions.length > 0
                x: 32
                y: 185
                width: parent.width - 64
                height: 48
                radius: 16
                color: "#152497ff"
                border.width: 1
                border.color: "#4a9cff"
                Text {
                    anchors.centerIn: parent
                    text: "◀  " + selectedInputOption() + "  ▶"
                    color: app.textPrimary
                    font.pixelSize: 15
                    font.bold: true
                }
            }

            Rectangle {
                visible: inputNeedsPassword
                x: 32
                y: inputOptions.length > 0 ? 248 : 190
                width: parent.width - 64
                height: 58
                radius: 17
                color: app.panelInset
                border.width: secondaryInput.activeFocus ? 2 : 1
                border.color: secondaryInput.activeFocus ? app.purple : app.divider
                TextInput {
                    id: secondaryInput
                    anchors.fill: parent
                    anchors.margins: 15
                    color: app.textPrimary
                    font.pixelSize: 17
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    selectByMouse: false
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    onAccepted: confirmInput()
                }
                Text {
                    visible: secondaryInput.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    x: 15
                    text: "Encryption password"
                    color: app.textMuted
                    font.pixelSize: 15
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 22
                text: "X/Enter Confirm   □ Paste   ◀▶ Option   O Cancel"
                color: app.textMuted
                font.pixelSize: 12
            }
        }
    }

    // Quick Look / metadata
    Rectangle {
        visible: previewOpen
        anchors.fill: parent
        color: "#c0000000"
        z: 70

        Rectangle {
            width: parent.width * 0.82
            height: parent.height * 0.82
            anchors.centerIn: parent
            radius: 34
            color: app.panelColor
            border.width: 2
            border.color: metadataMode ? app.purple : app.focusBlue

            Text {
                x: 30
                y: 22
                text: metadataMode ? "File Metadata" : "Quick Look"
                color: app.textPrimary
                font.pixelSize: 27
                font.bold: true
            }
            Text {
                x: 30
                y: 60
                width: parent.width - 60
                text: previewPath
                color: app.textSecondary
                font.pixelSize: 12
                elide: Text.ElideMiddle
            }

            Item {
                id: imageViewer
                visible: !metadataMode && String(previewData.previewType || "") === "image"
                x: 24
                y: 88
                width: parent.width - 48
                height: parent.height - 145
                clip: true

                Image {
                    id: fullImagePreview
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: app.imagePanX
                    anchors.verticalCenterOffset: app.imagePanY
                    width: parent.width * app.imageZoom
                    height: parent.height * app.imageZoom
                    source: previewData.url || previewData.previewUrl || ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    width: imageZoomText.implicitWidth + 18
                    height: 30
                    radius: 15
                    color: "#B807111D"
                    border.width: 1
                    border.color: "#37516D"

                    Text {
                        id: imageZoomText
                        anchors.centerIn: parent
                        text: Math.round(app.imageZoom * 100) + "%"
                        color: "#E5EDF8"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }

            ScrollView {
                x: 32
                y: 92
                width: parent.width - 64
                height: parent.height - 150
                visible: metadataMode || String(previewData.previewType || "") !== "image"
                clip: true

                TextArea {
                    readOnly: true
                    selectByMouse: false
                    wrapMode: String(previewData.previewType || "") === "hex" ? TextEdit.NoWrap : TextEdit.Wrap
                    color: app.textPrimary
                    font.family: String(previewData.previewType || "") === "text" || String(previewData.previewType || "") === "hex" ? "monospace" : "sans-serif"
                    font.pixelSize: 14
                    text: {
                        if (!previewData)
                            return ""
                        if (!metadataMode && previewData.previewType === "text")
                            return String(previewData.text || "")
                        if (!metadataMode && previewData.previewType === "hex")
                            return String(previewData.text || "")
                        if (!metadataMode && previewData.previewType === "archive") {
                            var lines = [String(previewData.summary || "Archive")]
                            var entries = previewData.entries || []
                            for (var i = 0; i < entries.length; ++i)
                                lines.push(String(entries[i].name || entries[i]))
                            return lines.join("\n")
                        }
                        var keys = ["name", "path", "parent", "type", "mimeType", "extension", "sizeText", "dimensions",
                                    "owner", "group", "permissions", "readable", "writable", "executable", "hidden", "symlink",
                                    "symlinkTarget", "created", "modified", "accessed", "canonicalPath", "sha256", "summary"]
                        var output = []
                        for (var k = 0; k < keys.length; ++k) {
                            var key = keys[k]
                            if (previewData[key] !== undefined && String(previewData[key]).length > 0)
                                output.push(key + ":  " + String(previewData[key]))
                        }
                        return output.join("\n\n")
                    }
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 18
                text: String(previewData.previewType || "") === "image"
                      ? "D-PAD Pan   L1 Zoom Out   R1 Zoom In   O Close"
                      : "O Close"
                color: app.textMuted
                font.pixelSize: 12
            }
        }
    }

    // Full text/code editor
    Rectangle {
        visible: editorOpen
        anchors.fill: parent
        color: app.windowColor
        z: 80

        Rectangle {
            x: 24
            y: 20
            width: parent.width - 48
            height: 72
            radius: 24
            color: app.panelColor
            border.width: 1
            border.color: editorDirty ? app.warning : app.focusBlue

            Text {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 280
                text: editorPath + (editorDirty ? "  • modified" : "")
                color: app.textPrimary
                font.pixelSize: 15
                font.bold: true
                elide: Text.ElideMiddle
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                text: editorTruncated ? "READ-ONLY PREVIEW (FILE TOO LARGE)" : "UTF-8 EDITOR"
                color: editorTruncated ? app.warning : app.success
                font.pixelSize: 12
                font.bold: true
            }
        }

        Rectangle {
            x: 24
            y: 108
            width: parent.width - 48
            height: parent.height - 178
            radius: 22
            color: app.panelInset
            border.width: 1
            border.color: "#32445f"

            ScrollView {
                anchors.fill: parent
                anchors.margins: 12
                clip: true
                TextArea {
                    id: editorText
                    readOnly: editorTruncated
                    focus: editorOpen && !keyboardOpen
                    cursorVisible: editorOpen
                    selectByMouse: false
                    wrapMode: TextEdit.NoWrap
                    color: app.textPrimary
                    selectionColor: "#4d2497ff"
                    selectedTextColor: "white"
                    font.family: "monospace"
                    font.pixelSize: 15
                    persistentSelection: true
                    background: Rectangle { color: "transparent" }
                    onTextChanged: if (editorOpen && !editorTruncated) editorDirty = true
                }
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 20
            text: "D-PAD Cursor   X Keyboard   □ Backspace   START Save   O Close"
            color: app.textSecondary
            font.pixelSize: 12
            font.bold: true
        }
    }

    // Volume and formatting modal. System devices are marked and blocked by C++ too.
    Rectangle {
        visible: volumeModalOpen
        anchors.fill: parent
        color: "#c0000000"
        z: 90

        Rectangle {
            width: 850
            height: 610
            anchors.centerIn: parent
            radius: 34
            color: app.panelColor
            border.width: 2
            border.color: app.warning

            Text {
                x: 30
                y: 24
                text: "Volumes / Format"
                color: app.textPrimary
                font.pixelSize: 27
                font.bold: true
            }
            Text {
                x: 30
                y: 62
                width: parent.width - 60
                text: "Formatting permanently erases a non-system volume. NeutronOS blocks its boot device in both the UI and backend."
                color: app.warning
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }

            ListView {
                id: volumesList
                x: 28
                y: 112
                width: parent.width - 56
                height: 230
                model: volumeModel
                currentIndex: volumeIndex
                interactive: false
                clip: true
                spacing: 8

                delegate: Rectangle {
                    width: volumesList.width
                    height: 66
                    radius: 18
                    color: volumeIndex === index ? (app.lightMode ? "#DCEEFF" : "#17365D") : app.panelRaised
                    border.width: volumeIndex === index ? 2 : 1
                    border.color: model.system ? app.danger : volumeIndex === index ? app.focusBlue : app.divider
                    Text {
                        x: 16
                        y: 11
                        width: parent.width - 32
                        text: String(model.name || model.device || "Volume") + (model.system ? "  • SYSTEM / LOCKED" : "")
                        color: model.system ? app.danger : "white"
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        x: 16
                        y: 37
                        width: parent.width - 32
                        text: String(model.device || "") + "  •  " + String(model.filesystem || "unknown") + "  •  " + String(model.freeText || "") + " free"
                        color: app.textMuted
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }

            Rectangle {
                x: 30
                y: 360
                width: parent.width - 60
                height: 44
                radius: 15
                color: "#152497ff"
                border.width: 1
                border.color: "#4a9cff"
                Text {
                    anchors.centerIn: parent
                    text: "Filesystem  ◀  " + filesystemOptions[filesystemIndex] + "  ▶"
                    color: app.textPrimary
                    font.pixelSize: 14
                    font.bold: true
                }
            }

            Rectangle {
                x: 30
                y: 420
                width: parent.width - 60
                height: 52
                radius: 16
                color: app.panelInset
                border.width: volumeLabelInput.activeFocus ? 2 : 1
                border.color: volumeLabelInput.activeFocus ? app.focusBlue : app.divider
                TextInput {
                    id: volumeLabelInput
                    anchors.fill: parent
                    anchors.margins: 14
                    color: app.textPrimary
                    font.pixelSize: 16
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                }
                Text {
                    visible: volumeLabelInput.text.length === 0
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Volume label (optional)"
                    color: app.textMuted
                    font.pixelSize: 14
                }
            }

            Rectangle {
                x: 30
                y: 486
                width: parent.width - 60
                height: 52
                radius: 16
                color: app.panelInset
                border.width: formatConfirmInput.activeFocus ? 2 : 1
                border.color: formatConfirmInput.activeFocus ? app.danger : app.divider
                TextInput {
                    id: formatConfirmInput
                    anchors.fill: parent
                    anchors.margins: 14
                    color: app.textPrimary
                    font.pixelSize: 16
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    onAccepted: primaryAction()
                }
                Text {
                    visible: formatConfirmInput.text.length === 0
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Type FORMAT to confirm"
                    color: app.danger
                    font.pixelSize: 14
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 18
                text: "↑↓ Volume   ◀▶ Filesystem   X Format   □ Paste   O Cancel"
                color: app.textMuted
                font.pixelSize: 12
            }
        }
    }

    Rectangle {
        id: errorBanner
        property alias text: errorBannerLabel.text
        visible: opacity > 0.01
        opacity: 0
        z: 200
        anchors.top: parent.top
        anchors.topMargin: 25
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 80, errorBannerLabel.implicitWidth + 50)
        height: 54
        radius: 19
        color: "#ff3a1720"
        border.width: 2
        border.color: app.danger
        Text {
            id: errorBannerLabel
            anchors.centerIn: parent
            width: parent.width - 30
            text: ""
            color: "#ffd7da"
            font.pixelSize: 13
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }
    Timer {
        id: errorBannerTimer
        interval: 5000
        onTriggered: errorBanner.opacity = 0
        onRunningChanged: if (running) errorBanner.opacity = 1
    }

    Rectangle {
        id: statusToast
        property alias text: statusToastLabel.text
        visible: opacity > 0.01
        opacity: 0
        z: 190
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 78
        anchors.horizontalCenter: parent.horizontalCenter
        width: statusToastLabel.implicitWidth + 46
        height: 46
        radius: 18
        color: "#e6183c32"
        border.width: 1
        border.color: "#22ff88"
        Text {
            id: statusToastLabel
            anchors.centerIn: parent
            color: app.success
            font.pixelSize: 12
            font.bold: true
        }
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }
    Timer {
        id: statusToastTimer
        interval: 2500
        onTriggered: statusToast.opacity = 0
        onRunningChanged: if (running) statusToast.opacity = 1
    }


    Timer {
        id: editorDiscardTimer
        interval: 3500
        onTriggered: editorDiscardArmed = false
    }

}
