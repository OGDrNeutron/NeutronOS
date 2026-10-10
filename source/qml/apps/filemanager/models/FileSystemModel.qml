import QtQuick 2.15

ListModel {
    id: root

    /*
        ============================================================
                        FILE SYSTEM DISPLAY MODEL
        ============================================================

        UI-facing file/folder model.

        Backend-ready:
        - Receives normalized items from FileManagerBackendAdapter.qml.
        - Keeps a source cache.
        - Applies search filtering.
        - Applies sort order.
        - Exposes stable roles for FileGrid/FileTile/List/Details views.

        Expected item roles:
            name
            path
            parentPath
            isDirectory
            type
            kind
            extension
            size
            sizeText
            modified
            permissions
            hidden
            readable
            writable
            icon
            preview
            selected
            armed
    */

    dynamicRoles: true

    property string currentPath: "/home/echo"
    property string searchQuery: ""
    property string sortKey: "name"
    property bool sortAscending: true
    property bool showHidden: false

    property var sourceItems: []
    property int folderCount: 0
    property int fileCount: 0
    property int hiddenCount: 0
    property int totalSourceCount: 0

    signal modelReset()
    signal itemActivated(int index, var itemData)

    /*
        ============================================================
                            PUBLIC API
        ============================================================
    */

    function replaceItems(items) {
        var normalized = []

        if (items) {
            for (var i = 0; i < items.length; i++)
                normalized.push(normalizeItem(items[i]))
        }

        sourceItems = normalized
        totalSourceCount = normalized.length

        rebuild()
    }

    function appendFile(itemData) {
        var next = sourceItems.slice()
        next.push(normalizeItem(itemData))
        sourceItems = next
        totalSourceCount = next.length

        rebuild()
    }

    function removeByPath(path) {
        var cleanPath = String(path || "")
        var next = []

        for (var i = 0; i < sourceItems.length; i++) {
            if (String(sourceItems[i].path || "") !== cleanPath)
                next.push(sourceItems[i])
        }

        sourceItems = next
        totalSourceCount = next.length

        rebuild()
    }

    function updateByPath(path, itemData) {
        var cleanPath = String(path || "")
        var next = sourceItems.slice()
        var replaced = false

        for (var i = 0; i < next.length; i++) {
            if (String(next[i].path || "") === cleanPath) {
                next[i] = normalizeItem(itemData)
                replaced = true
                break
            }
        }

        if (!replaced)
            next.push(normalizeItem(itemData))

        sourceItems = next
        totalSourceCount = next.length

        rebuild()
    }

    function clearItems() {
        sourceItems = []
        totalSourceCount = 0
        folderCount = 0
        fileCount = 0
        hiddenCount = 0

        clear()
        modelReset()
    }

    function itemAt(index) {
        if (index < 0 || index >= count)
            return null

        return get(index)
    }

    function pathAt(index) {
        var item = itemAt(index)

        if (!item)
            return ""

        return String(item.path || "")
    }

    function nameAt(index) {
        var item = itemAt(index)

        if (!item)
            return ""

        return String(item.name || "")
    }

    function isDirectoryAt(index) {
        var item = itemAt(index)

        if (!item)
            return false

        return item.isDirectory === true
    }

    function indexOfPath(path) {
        var cleanPath = String(path || "")

        for (var i = 0; i < count; i++) {
            if (String(get(i).path || "") === cleanPath)
                return i
        }

        return -1
    }

    function activate(index) {
        var item = itemAt(index)

        if (!item)
            return

        itemActivated(index, item)
    }

    /*
        ============================================================
                        FILTER / SORT / REBUILD
        ============================================================
    */

    function rebuild() {
        var query = String(searchQuery || "").trim().toLowerCase()
        var visibleItems = []

        folderCount = 0
        fileCount = 0
        hiddenCount = 0

        for (var i = 0; i < sourceItems.length; i++) {
            var item = normalizeItem(sourceItems[i])

            if (item.hidden === true)
                hiddenCount++

            if (item.hidden === true && !showHidden)
                continue

            if (query.length > 0) {
                var haystack = (
                    String(item.name || "") + " " +
                    String(item.path || "") + " " +
                    String(item.kind || "") + " " +
                    String(item.extension || "")
                ).toLowerCase()

                if (haystack.indexOf(query) < 0)
                    continue
            }

            visibleItems.push(item)
        }

        visibleItems.sort(compareItems)

        clear()

        for (var j = 0; j < visibleItems.length; j++) {
            var displayItem = visibleItems[j]

            if (displayItem.isDirectory === true)
                folderCount++
            else
                fileCount++

            append(displayItem)
        }

        modelReset()
    }

    function compareItems(a, b) {
        /*
            Folders first always, like a console/media file browser.
        */

        if (a.isDirectory === true && b.isDirectory !== true)
            return -1

        if (a.isDirectory !== true && b.isDirectory === true)
            return 1

        var dir = sortAscending ? 1 : -1
        var key = String(sortKey || "name").toLowerCase()

        if (key === "size") {
            var sa = Number(a.size || 0)
            var sb = Number(b.size || 0)

            if (sa < sb)
                return -1 * dir

            if (sa > sb)
                return 1 * dir

            return compareText(a.name, b.name, 1)
        }

        if (key === "modified" || key === "date") {
            var ma = String(a.modified || "")
            var mb = String(b.modified || "")

            if (ma < mb)
                return -1 * dir

            if (ma > mb)
                return 1 * dir

            return compareText(a.name, b.name, 1)
        }

        if (key === "type" || key === "kind") {
            var ka = String(a.kind || a.type || "")
            var kb = String(b.kind || b.type || "")

            var typeCompare = compareText(ka, kb, dir)

            if (typeCompare !== 0)
                return typeCompare

            return compareText(a.name, b.name, 1)
        }

        if (key === "extension") {
            var ea = String(a.extension || "")
            var eb = String(b.extension || "")

            var extCompare = compareText(ea, eb, dir)

            if (extCompare !== 0)
                return extCompare

            return compareText(a.name, b.name, 1)
        }

        return compareText(a.name, b.name, dir)
    }

    function compareText(a, b, dir) {
        var aa = String(a || "").toLowerCase()
        var bb = String(b || "").toLowerCase()

        if (aa < bb)
            return -1 * dir

        if (aa > bb)
            return 1 * dir

        return 0
    }

    /*
        ============================================================
                            NORMALIZATION
        ============================================================
    */

    function normalizeItem(source) {
        var name = String(valueFrom(source, ["name", "fileName", "displayName"], "Untitled"))
        var path = String(valueFrom(source, ["path", "filePath", "absolutePath"], joinPath(currentPath, name)))
        var isDir = boolFrom(valueFrom(source, ["isDirectory", "directory", "folder"], false))
        var ext = String(valueFrom(source, ["extension", "ext"], extensionFor(name))).toLowerCase()
        var kind = String(valueFrom(source, ["kind", "type"], kindFor(name, isDir))).toLowerCase()
        var sizeValue = Number(valueFrom(source, ["size", "bytes", "fileSize"], 0))

        return {
            "name": name,
            "path": path,
            "parentPath": String(valueFrom(source, ["parentPath"], parentPath(path))),
            "isDirectory": isDir,
            "type": isDir ? "folder" : "file",
            "kind": kind,
            "extension": ext,
            "size": isNaN(sizeValue) ? 0 : sizeValue,
            "sizeText": String(valueFrom(source, ["sizeText"], formatBytes(sizeValue))),
            "modified": String(valueFrom(source, ["modified", "modifiedTime", "lastModified"], "")),
            "permissions": String(valueFrom(source, ["permissions", "mode"], "")),
            "hidden": boolFrom(valueFrom(source, ["hidden", "isHidden"], name.indexOf(".") === 0)),
            "readable": boolFrom(valueFrom(source, ["readable", "canRead"], true)),
            "writable": boolFrom(valueFrom(source, ["writable", "canWrite"], true)),
            "icon": String(valueFrom(source, ["icon"], "")),
            "preview": String(valueFrom(source, ["preview"], "")),
            "selected": boolFrom(valueFrom(source, ["selected"], false)),
            "armed": boolFrom(valueFrom(source, ["armed"], false))
        }
    }

    function valueFrom(source, keys, fallbackValue) {
        if (!source)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            if (source[key] !== undefined && source[key] !== null)
                return source[key]
        }

        return fallbackValue
    }

    function boolFrom(value) {
        if (value === true)
            return true

        if (value === false)
            return false

        if (value === 1)
            return true

        if (value === 0)
            return false

        var text = String(value || "").toLowerCase()

        return text === "true" ||
               text === "1" ||
               text === "yes" ||
               text === "y"
    }

    function extensionFor(name) {
        var text = String(name || "")
        var idx = text.lastIndexOf(".")

        if (idx < 0 || idx >= text.length - 1)
            return ""

        return text.substring(idx + 1).toLowerCase()
    }

    function kindFor(name, isDirectory) {
        if (isDirectory)
            return "folder"

        var ext = extensionFor(name)

        if (ext === "mkv" ||
                ext === "mp4" ||
                ext === "mov" ||
                ext === "avi" ||
                ext === "webm" ||
                ext === "m4v")
            return "video"

        if (ext === "jpg" ||
                ext === "jpeg" ||
                ext === "png" ||
                ext === "webp" ||
                ext === "gif" ||
                ext === "svg")
            return "image"

        if (ext === "mp3" ||
                ext === "flac" ||
                ext === "wav" ||
                ext === "aac" ||
                ext === "m4a" ||
                ext === "ogg")
            return "audio"

        if (ext === "zip" ||
                ext === "7z" ||
                ext === "rar" ||
                ext === "tar" ||
                ext === "gz")
            return "archive"

        if (ext === "iso" ||
                ext === "img")
            return "disk"

        if (ext === "qml" ||
                ext === "cpp" ||
                ext === "h" ||
                ext === "js" ||
                ext === "py" ||
                ext === "html" ||
                ext === "css" ||
                ext === "json")
            return "code"

        if (ext === "txt" ||
                ext === "md" ||
                ext === "log" ||
                ext === "pdf" ||
                ext === "doc" ||
                ext === "docx")
            return "document"

        return "file"
    }

    function parentPath(path) {
        var text = String(path || currentPath)

        if (text === "/")
            return "/"

        while (text.length > 1 && text.endsWith("/"))
            text = text.substring(0, text.length - 1)

        var idx = text.lastIndexOf("/")

        if (idx <= 0)
            return "/"

        return text.substring(0, idx)
    }

    function joinPath(parent, child) {
        var p = String(parent || "/")
        var c = String(child || "")

        while (p.length > 1 && p.endsWith("/"))
            p = p.substring(0, p.length - 1)

        if (p === "/")
            return "/" + c

        return p + "/" + c
    }

    function formatBytes(bytes) {
        var value = Number(bytes || 0)

        if (isNaN(value) || value <= 0)
            return "0 B"

        if (value < 1024)
            return Math.round(value) + " B"

        value = value / 1024

        if (value < 1024)
            return value.toFixed(1) + " KB"

        value = value / 1024

        if (value < 1024)
            return value.toFixed(1) + " MB"

        value = value / 1024

        if (value < 1024)
            return value.toFixed(2) + " GB"

        value = value / 1024
        return value.toFixed(2) + " TB"
    }

    /*
        ============================================================
                            PROPERTY WATCHERS
        ============================================================
    */

    onSearchQueryChanged: rebuild()
    onSortKeyChanged: rebuild()
    onSortAscendingChanged: rebuild()
    onShowHiddenChanged: rebuild()
}