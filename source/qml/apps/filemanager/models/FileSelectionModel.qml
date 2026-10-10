import QtQuick 2.15

QtObject {
    id: root

    /*
        ============================================================
                        FILE SELECTION MODEL
        ============================================================

        Lightweight selection state helper.

        Current behavior:
        - Single armed item for controller action flow.
        - X selects/arms a file.
        - O cancels armed selection.
        - Action modal can operate on armed file.

        Backend-ready:
        - Later this can be expanded into multi-select.
        - The UI already routes actions through stable path/name data.
    */

    property int selectedIndex: 0
    property int armedIndex: -1

    property string armedPath: ""
    property string armedName: ""
    property string armedKind: ""
    property bool armedIsDirectory: false

    readonly property bool hasArmedItem: armedIndex >= 0 && armedPath.length > 0

    signal selectedChanged(int index)
    signal armedChanged(int index, string path)
    signal cleared()

    function clampSelected(count) {
        var total = Number(count || 0)

        if (total <= 0) {
            selectedIndex = 0
            clearArmed()
            return
        }

        selectedIndex = Math.max(0, Math.min(selectedIndex, total - 1))
    }

    function setSelected(index, count) {
        var total = Number(count || 0)

        if (total <= 0) {
            selectedIndex = 0
            selectedChanged(selectedIndex)
            return
        }

        selectedIndex = Math.max(0, Math.min(Number(index || 0), total - 1))
        selectedChanged(selectedIndex)
    }

    function arm(index, fileData) {
        if (!fileData)
            return

        armedIndex = Number(index || 0)
        armedPath = String(fileData.path || "")
        armedName = String(fileData.name || "Selected Item")
        armedKind = String(fileData.kind || fileData.type || "file")
        armedIsDirectory = fileData.isDirectory === true ||
                            String(fileData.type || "").toLowerCase() === "folder" ||
                            String(fileData.kind || "").toLowerCase() === "folder"

        armedChanged(armedIndex, armedPath)
    }

    function clearArmed() {
        armedIndex = -1
        armedPath = ""
        armedName = ""
        armedKind = ""
        armedIsDirectory = false

        cleared()
    }

    function isArmed(index, path) {
        if (!hasArmedItem)
            return false

        if (String(path || "").length > 0)
            return String(path || "") === armedPath

        return Number(index || 0) === armedIndex
    }

    function armedData() {
        if (!hasArmedItem)
            return null

        return {
            "name": armedName,
            "path": armedPath,
            "kind": armedKind,
            "type": armedIsDirectory ? "folder" : "file",
            "isDirectory": armedIsDirectory
        }
    }
}