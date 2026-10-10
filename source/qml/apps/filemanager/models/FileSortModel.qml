import QtQuick 2.15

ListModel {
    id: root

    /*
        ============================================================
                            FILE SORT MODEL
        ============================================================

        Sort menu model.

        Roles:
            title
            subtitle
            sortKey
            ascending
            iconText
            enabled
    */

    dynamicRoles: true

    signal sortRequested(string sortKey, bool ascending)

    function resetDefaults() {
        clear()

        appendSort("Name A-Z", "Folders first, then files alphabetically", "name", true, "A")
        appendSort("Name Z-A", "Reverse alphabetical order", "name", false, "Z")
        appendSort("Type", "Group by file type", "kind", true, "T")
        appendSort("Extension", "Sort by file extension", "extension", true, ".")
        appendSort("Size Smallest", "Small files first", "size", true, "↑")
        appendSort("Size Largest", "Large files first", "size", false, "↓")
        appendSort("Modified Oldest", "Oldest items first", "modified", true, "◷")
        appendSort("Modified Newest", "Newest items first", "modified", false, "◴")
    }

    function appendSort(title, subtitle, sortKey, ascending, iconText) {
        append({
            "title": String(title || "Sort"),
            "subtitle": String(subtitle || ""),
            "sortKey": String(sortKey || "name"),
            "ascending": ascending === true,
            "iconText": String(iconText || "•"),
            "enabled": true
        })
    }

    function itemAt(index) {
        if (index < 0 || index >= count)
            return null

        return get(index)
    }

    function activate(index) {
        if (index < 0 || index >= count)
            return

        var item = get(index)

        if (!item || item.enabled !== true)
            return

        sortRequested(String(item.sortKey || "name"), item.ascending === true)
    }

    function indexFor(sortKey, ascending) {
        var key = String(sortKey || "name")
        var asc = ascending === true

        for (var i = 0; i < count; i++) {
            var item = get(i)

            if (String(item.sortKey || "") === key &&
                    item.ascending === asc)
                return i
        }

        return 0
    }

    Component.onCompleted: {
        resetDefaults()
    }
}