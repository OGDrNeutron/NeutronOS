import QtQuick 2.15

ListModel {
    id: root

    /*
        ============================================================
                            FILE PLACES MODEL
        ============================================================

        Sidebar model.

        Backend-ready:
        - Static now.
        - Later we can replace/add devices from C++ backend:
              fileManager.devices
              fileManager.mounts
              fileManager.networkPlaces
    */

    dynamicRoles: true

    signal placeRequested(int index, string path)

    /*
        Roles:
            title
            subtitle
            path
            iconText
            kind
            section
            isHeader
            enabled
            danger
    */

    function resetDefaults() {
        clear()

        appendHeader("FAVORITES")

        appendPlace("Home", "/home/echo", "⌂", "home", "Favorites", "User home")
        appendPlace("Desktop", "/home/echo/Desktop", "▣", "desktop", "Favorites", "Desktop")
        appendPlace("Documents", "/home/echo/Documents", "≡", "documents", "Favorites", "Documents")
        appendPlace("Downloads", "/home/echo/Downloads", "↓", "downloads", "Favorites", "Downloads")
        appendPlace("NeutronOS", "/opt/neutronos", "✦", "neutron", "Favorites", "System project")
        appendPlace("Media", "/mnt/NeutronMedia", "▶", "media", "Favorites", "Media library")

        appendHeader("DEVICES")

        appendPlace("Storage", "/mnt", "◈", "storage", "Devices", "Mounted drives")
        appendPlace("Docker", "/home/echo/docker", "▦", "docker", "Devices", "Docker config")
        appendPlace("Root", "/", "⌁", "root", "Devices", "System root")

        appendHeader("SYSTEM")

        appendPlace("Apps", "/opt/neutronos/qml/apps", "▤", "apps", "System", "Installed apps")
        appendPlace("Themes", "/opt/neutronos/themes", "◌", "themes", "System", "Theme assets")
        appendPlace("Logs", "/var/log", "≋", "logs", "System", "System logs")
        appendPlace("Trash", "/var/lib/neutronos/service/.local/share/Trash/files", "⌫", "trash", "System", "Trash", true)
    }

    function appendHeader(title) {
        append({
            "title": String(title || ""),
            "subtitle": "",
            "path": "",
            "iconText": "",
            "kind": "header",
            "section": String(title || ""),
            "isHeader": true,
            "enabled": false,
            "danger": false
        })
    }

    function appendPlace(title, path, iconText, kind, section, subtitle, danger) {
        append({
            "title": String(title || "Place"),
            "subtitle": String(subtitle || ""),
            "path": String(path || "/home/echo"),
            "iconText": String(iconText || "•"),
            "kind": String(kind || "place"),
            "section": String(section || ""),
            "isHeader": false,
            "enabled": true,
            "danger": danger === true
        })
    }

    function itemAt(index) {
        if (index < 0 || index >= count)
            return null

        return get(index)
    }

    function firstSelectableIndex() {
        for (var i = 0; i < count; i++) {
            var item = get(i)

            if (item && item.enabled === true && item.isHeader !== true)
                return i
        }

        return 0
    }

    function lastSelectableIndex() {
        for (var i = count - 1; i >= 0; i--) {
            var item = get(i)

            if (item && item.enabled === true && item.isHeader !== true)
                return i
        }

        return Math.max(0, count - 1)
    }

    function nextSelectableIndex(index) {
        if (count <= 0)
            return 0

        var start = Math.max(0, Math.min(index + 1, count - 1))

        for (var i = start; i < count; i++) {
            var item = get(i)

            if (item && item.enabled === true && item.isHeader !== true)
                return i
        }

        return lastSelectableIndex()
    }

    function previousSelectableIndex(index) {
        if (count <= 0)
            return 0

        var start = Math.max(0, Math.min(index - 1, count - 1))

        for (var i = start; i >= 0; i--) {
            var item = get(i)

            if (item && item.enabled === true && item.isHeader !== true)
                return i
        }

        return firstSelectableIndex()
    }

    function activate(index) {
        if (index < 0 || index >= count)
            return

        var item = get(index)

        if (!item || item.enabled !== true || item.isHeader === true)
            return

        placeRequested(index, String(item.path || "/home/echo"))
    }

    Component.onCompleted: {
        resetDefaults()
    }
}