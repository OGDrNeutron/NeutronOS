import QtQuick 2.15

QtObject {
    id: root

    /*
        ============================================================
                    FILE MANAGER BACKEND ADAPTER
        ============================================================

        Backend-ready bridge.

        Current mode:
        - Works now with safe mock/local placeholder data.

        Future C++ mode:
        - Automatically routes to a native backend if either object exists:
              fileManager
              fileManagerBackend

        Expected future C++ invokable API:
            initialize()
            loadDirectory(path)
            createFolder(parentPath, folderName)
            deletePath(path)
            renamePath(path, newName)
            movePath(sourcePath, destinationPath)
            copyPath(sourcePath, destinationPath)
            duplicatePath(path)
            openPath(path)

        Expected future C++ signals:
            directoryLoaded(string path, QVariantList items)
            operationCompleted(QString actionId, QString path)
            operationFailed(QString message)
            busyChanged()
            errorChanged()
    */

    property var nativeBackend: {
        if (typeof fileManager !== "undefined")
            return fileManager

        if (typeof fileManagerBackend !== "undefined")
            return fileManagerBackend

        return null
    }

    property bool nativeAvailable: nativeBackend !== null
    property bool ready: false
    property bool busy: false
    property string errorText: ""
    property string currentPath: "/home/echo"

    signal directoryLoaded(string path, var items)
    signal operationCompleted(string actionId, string path)
    signal operationFailed(string message)

    /*
        ============================================================
                            NATIVE CONNECTIONS
        ============================================================
    */

    Connections {
        target: root.nativeBackend
        ignoreUnknownSignals: true

        function onDirectoryLoaded(path, items) {
            root.busy = false
            root.errorText = ""
            root.currentPath = String(path || root.currentPath)
            root.directoryLoaded(root.currentPath, root.normalizeItems(items || [], root.currentPath))
        }

        function onOperationCompleted(actionId, path) {
            root.busy = false
            root.errorText = ""
            root.operationCompleted(String(actionId || ""), String(path || root.currentPath))
        }

        function onOperationFailed(message) {
            root.busy = false
            root.errorText = String(message || "File operation failed.")
            root.operationFailed(root.errorText)
        }

        function onBusyChanged() {
            if (root.nativeBackend && root.nativeBackend.busy !== undefined)
                root.busy = root.nativeBackend.busy
        }

        function onErrorChanged() {
            if (root.nativeBackend && root.nativeBackend.error !== undefined)
                root.errorText = String(root.nativeBackend.error || "")
        }
    }

    /*
        ============================================================
                            PUBLIC API
        ============================================================
    */

    function initialize() {
        if (nativeAvailable) {
            ready = true

            if (nativeBackend.ready !== undefined)
                ready = nativeBackend.ready === true

            if (nativeBackend.busy !== undefined)
                busy = nativeBackend.busy === true

            if (nativeBackend.error !== undefined)
                errorText = String(nativeBackend.error || "")

            if (typeof nativeBackend.initialize === "function")
                nativeBackend.initialize()

            return
        }

        ready = true
        busy = false
        errorText = ""
    }

    function loadDirectory(path) {
        var cleanPath = normalizePath(path)

        currentPath = cleanPath
        errorText = ""

        if (nativeAvailable && typeof nativeBackend.loadDirectory === "function") {
            busy = true

            var result = nativeBackend.loadDirectory(cleanPath)

            /*
                Supports both async C++ signal mode and sync return mode.
            */
            if (result !== undefined && result !== null) {
                busy = false
                directoryLoaded(cleanPath, normalizeItems(result, cleanPath))
            }

            return
        }

        busy = true
        mockLoadTimer.path = cleanPath
        mockLoadTimer.restart()
    }

    function createFolder(parentPath, folderName) {
        var cleanParent = normalizePath(parentPath)
        var cleanName = String(folderName || "").trim()

        if (cleanName.length <= 0) {
            fail("Folder name cannot be empty.")
            return
        }

        if (nativeAvailable && typeof nativeBackend.createFolder === "function") {
            busy = true
            nativeBackend.createFolder(cleanParent, cleanName)
            return
        }

        busy = true
        mockOperationTimer.actionId = "createFolder"
        mockOperationTimer.path = joinPath(cleanParent, cleanName)
        mockOperationTimer.restart()
    }

    function deletePath(path) {
        var cleanPath = normalizePath(path)

        if (cleanPath.length <= 0) {
            fail("No file selected.")
            return
        }

        if (nativeAvailable && typeof nativeBackend.deletePath === "function") {
            busy = true
            nativeBackend.deletePath(cleanPath)
            return
        }

        busy = true
        mockOperationTimer.actionId = "delete"
        mockOperationTimer.path = cleanPath
        mockOperationTimer.restart()
    }

    function renamePath(path, newName) {
        var cleanPath = normalizePath(path)
        var cleanName = String(newName || "").trim()

        if (cleanPath.length <= 0 || cleanName.length <= 0) {
            fail("Rename requires a selected file and a new name.")
            return
        }

        if (nativeAvailable && typeof nativeBackend.renamePath === "function") {
            busy = true
            nativeBackend.renamePath(cleanPath, cleanName)
            return
        }

        busy = true
        mockOperationTimer.actionId = "rename"
        mockOperationTimer.path = cleanPath
        mockOperationTimer.restart()
    }

    function movePath(sourcePath, destinationPath) {
        var cleanSource = normalizePath(sourcePath)
        var cleanDestination = normalizePath(destinationPath)

        if (cleanSource.length <= 0 || cleanDestination.length <= 0) {
            fail("Move requires a source and destination.")
            return
        }

        if (nativeAvailable && typeof nativeBackend.movePath === "function") {
            busy = true
            nativeBackend.movePath(cleanSource, cleanDestination)
            return
        }

        busy = true
        mockOperationTimer.actionId = "move"
        mockOperationTimer.path = cleanSource
        mockOperationTimer.restart()
    }

    function copyPath(sourcePath, destinationPath) {
        var cleanSource = normalizePath(sourcePath)
        var cleanDestination = normalizePath(destinationPath)

        if (cleanSource.length <= 0 || cleanDestination.length <= 0) {
            fail("Copy requires a source and destination.")
            return
        }

        if (nativeAvailable && typeof nativeBackend.copyPath === "function") {
            busy = true
            nativeBackend.copyPath(cleanSource, cleanDestination)
            return
        }

        busy = true
        mockOperationTimer.actionId = "copy"
        mockOperationTimer.path = cleanSource
        mockOperationTimer.restart()
    }

    function duplicatePath(path) {
        var cleanPath = normalizePath(path)

        if (cleanPath.length <= 0) {
            fail("Duplicate requires a selected file.")
            return
        }

        if (nativeAvailable && typeof nativeBackend.duplicatePath === "function") {
            busy = true
            nativeBackend.duplicatePath(cleanPath)
            return
        }

        busy = true
        mockOperationTimer.actionId = "duplicate"
        mockOperationTimer.path = cleanPath
        mockOperationTimer.restart()
    }

    function openPath(path) {
        var cleanPath = normalizePath(path)

        if (cleanPath.length <= 0) {
            fail("No file selected.")
            return
        }

        if (nativeAvailable && typeof nativeBackend.openPath === "function") {
            nativeBackend.openPath(cleanPath)
            return
        }

        operationCompleted("open", cleanPath)
    }

    /*
        ============================================================
                            NORMALIZATION
        ============================================================
    */

    function normalizePath(path) {
        var text = String(path || "").trim()

        if (text.length <= 0)
            return "/home/echo"

        while (text.length > 1 && text.endsWith("/"))
            text = text.substring(0, text.length - 1)

        return text
    }

    function baseName(path) {
        var text = normalizePath(path)
        var parts = text.split("/")

        if (parts.length <= 0)
            return text

        var last = parts[parts.length - 1]

        if (last.length <= 0)
            return "/"

        return last
    }

    function parentPath(path) {
        var text = normalizePath(path)

        if (text === "/")
            return "/"

        var idx = text.lastIndexOf("/")

        if (idx <= 0)
            return "/"

        return text.substring(0, idx)
    }

    function joinPath(parent, child) {
        var p = normalizePath(parent)
        var c = String(child || "").trim()

        if (p === "/")
            return "/" + c

        return p + "/" + c
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

        if (ext === "mkv" || ext === "mp4" || ext === "mov" || ext === "avi" || ext === "webm" || ext === "m4v")
            return "video"

        if (ext === "jpg" || ext === "jpeg" || ext === "png" || ext === "webp" || ext === "gif" || ext === "svg")
            return "image"

        if (ext === "mp3" || ext === "flac" || ext === "wav" || ext === "aac" || ext === "m4a" || ext === "ogg")
            return "audio"

        if (ext === "zip" || ext === "7z" || ext === "rar" || ext === "tar" || ext === "gz")
            return "archive"

        if (ext === "iso" || ext === "img")
            return "disk"

        if (ext === "qml" || ext === "cpp" || ext === "h" || ext === "js" || ext === "py" || ext === "html" || ext === "css" || ext === "json")
            return "code"

        if (ext === "txt" || ext === "md" || ext === "log" || ext === "pdf" || ext === "doc" || ext === "docx")
            return "document"

        return "file"
    }

    function normalizeItem(source, fallbackParent) {
        var name = String(valueFrom(source, ["name", "fileName", "displayName"], "Untitled"))
        var path = String(valueFrom(source, ["path", "filePath", "absolutePath"], joinPath(fallbackParent, name)))
        var isDirectory = boolFrom(valueFrom(source, ["isDirectory", "directory", "folder"], false))
        var size = Number(valueFrom(source, ["size", "bytes", "fileSize"], 0))
        var modified = String(valueFrom(source, ["modified", "modifiedTime", "lastModified"], ""))
        var permissions = String(valueFrom(source, ["permissions", "mode"], ""))
        var hidden = boolFrom(valueFrom(source, ["hidden", "isHidden"], false))
        var readable = boolFrom(valueFrom(source, ["readable", "canRead"], true))
        var writable = boolFrom(valueFrom(source, ["writable", "canWrite"], true))
        var kind = String(valueFrom(source, ["kind", "type"], kindFor(name, isDirectory)))

        return {
            "name": name,
            "path": path,
            "parentPath": parentPath(path),
            "isDirectory": isDirectory,
            "type": isDirectory ? "folder" : "file",
            "kind": kind,
            "extension": extensionFor(name),
            "size": size,
            "sizeText": formatBytes(size),
            "modified": modified,
            "permissions": permissions,
            "hidden": hidden,
            "readable": readable,
            "writable": writable,
            "icon": String(valueFrom(source, ["icon"], "")),
            "preview": String(valueFrom(source, ["preview"], "")),
            "selected": false,
            "armed": false
        }
    }

    function normalizeItems(items, parentPathValue) {
        var result = []

        if (!items)
            return result

        for (var i = 0; i < items.length; i++)
            result.push(normalizeItem(items[i], parentPathValue))

        result.sort(function(a, b) {
            if (a.isDirectory && !b.isDirectory)
                return -1

            if (!a.isDirectory && b.isDirectory)
                return 1

            return String(a.name).toLowerCase().localeCompare(String(b.name).toLowerCase())
        })

        return result
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

        var text = String(value || "").toLowerCase()

        return text === "true" || text === "1" || text === "yes"
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

    function fail(message) {
        busy = false
        errorText = String(message || "File operation failed.")
        operationFailed(errorText)
    }

    /*
        ============================================================
                            MOCK DATA
        ============================================================
    */

    function mockItemsForPath(path) {
        var p = normalizePath(path)

        if (p === "/" || p === "/home" || p === "/home/echo") {
            return [
                folder("Desktop", joinPath(p, "Desktop")),
                folder("Documents", joinPath(p, "Documents")),
                folder("Downloads", joinPath(p, "Downloads")),
                folder("Media", "/mnt/NeutronMedia"),
                folder("NeutronOS", "/opt/neutronos"),
                folder("Docker", "/home/echo/docker"),
                file("readme.txt", joinPath(p, "readme.txt"), 18432),
                file("system-notes.md", joinPath(p, "system-notes.md"), 12048),
                file("movie-poster.png", joinPath(p, "movie-poster.png"), 2469000),
                file("sample-video.mkv", joinPath(p, "sample-video.mkv"), 734003200),
                file("archive.zip", joinPath(p, "archive.zip"), 8724152),
                file("disk-image.iso", joinPath(p, "disk-image.iso"), 2147483648)
            ]
        }

        if (p === "/opt/neutronos") {
            return [
                folder("qml", joinPath(p, "qml")),
                folder("src", joinPath(p, "src")),
                folder("themes", joinPath(p, "themes")),
                folder("build", joinPath(p, "build")),
                file("CMakeLists.txt", joinPath(p, "CMakeLists.txt"), 8192),
                file("main.cpp", joinPath(p, "main.cpp"), 12400),
                file("README.md", joinPath(p, "README.md"), 34000)
            ]
        }

        if (p === "/mnt/NeutronMedia") {
            return [
                folder("Movies", joinPath(p, "Movies")),
                folder("Shows", joinPath(p, "Shows")),
                folder("Downloads", joinPath(p, "Downloads")),
                file("library-status.json", joinPath(p, "library-status.json"), 1024)
            ]
        }

        return [
            folder("Folder A", joinPath(p, "Folder A")),
            folder("Folder B", joinPath(p, "Folder B")),
            file("Document.txt", joinPath(p, "Document.txt"), 4096),
            file("Image.png", joinPath(p, "Image.png"), 884120),
            file("Video.mkv", joinPath(p, "Video.mkv"), 104857600),
            file("Archive.zip", joinPath(p, "Archive.zip"), 2048000)
        ]
    }

    function folder(name, path) {
        return {
            "name": name,
            "path": path,
            "isDirectory": true,
            "kind": "folder",
            "size": 0,
            "modified": "Today"
        }
    }

    function file(name, path, size) {
        return {
            "name": name,
            "path": path,
            "isDirectory": false,
            "kind": kindFor(name, false),
            "size": size,
            "modified": "Today"
        }
    }

    /*
        ============================================================
                            MOCK TIMERS
        ============================================================
    */

    Timer {
        id: mockLoadTimer

        interval: 120
        repeat: false

        property string path: "/home/echo"

        onTriggered: {
            root.busy = false
            root.errorText = ""
            root.currentPath = path
            root.directoryLoaded(path, root.normalizeItems(root.mockItemsForPath(path), path))
        }
    }

    Timer {
        id: mockOperationTimer

        interval: 180
        repeat: false

        property string actionId: ""
        property string path: ""

        onTriggered: {
            root.busy = false
            root.errorText = ""
            root.operationCompleted(actionId, path)
        }
    }
}