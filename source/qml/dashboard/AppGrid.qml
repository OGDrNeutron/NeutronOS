import QtQuick 2.15
import "../cards"

Item {
    id: root

    property int selectedApp: 0
    property int currentFilteredIndex: 0
    property int appStartIndex: 0
    property int visibleAppCount: 8
    property bool sectionFocused: false
    property int armedApp: -1
    property int cardSizePercent: 100
    property int spacingPercent: 100
    property string categoryFilter: "ALL"
    property string sortMode: "FAVORITES"
    property var filteredApps: []

    signal appRequested(var appData, int index)

    function appBackend() {
        try { if (typeof appManager !== "undefined" && appManager) return appManager } catch (e) {}
        try { if (typeof appLauncher !== "undefined" && appLauncher) return appLauncher } catch (e2) {}
        return null
    }

    function appList() {
        var backend = appBackend()
        if (!backend) return []
        try { if (backend.favoriteApps) return backend.favoriteApps } catch (e) {}
        try { if (backend.apps) return backend.apps } catch (e2) {}
        return []
    }

    function appName(app) {
        try { return String(app.name || app.title || app.displayName || app.id || "App") } catch (e) { return "App" }
    }

    function appCategory(app) {
        try { return String(app.category || app.group || "Apps").toUpperCase() } catch (e) { return "APPS" }
    }

    function categories() {
        var values = ["ALL"]
        var seen = ({ "ALL": true })
        var list = appList()
        for (var i = 0; i < list.length; ++i) {
            var value = appCategory(list[i])
            if (!seen[value]) { seen[value] = true; values.push(value) }
        }
        return values
    }

    function rebuild() {
        var list = []
        var source = appList()
        for (var i = 0; i < source.length; ++i) {
            if (categoryFilter === "ALL" || appCategory(source[i]) === categoryFilter)
                list.push({ "app": source[i], "realIndex": i })
        }
        if (sortMode === "A-Z") {
            list.sort(function(a, b) { return appName(a.app).localeCompare(appName(b.app)) })
        } else if (sortMode === "CATEGORY") {
            list.sort(function(a, b) {
                var ca = appCategory(a.app), cb = appCategory(b.app)
                if (ca === cb) return appName(a.app).localeCompare(appName(b.app))
                return ca.localeCompare(cb)
            })
        }
        filteredApps = list
        var found = 0
        for (var j = 0; j < list.length; ++j) {
            if (Number(list[j].realIndex) === Number(selectedApp)) { found = j; break }
        }
        currentFilteredIndex = Math.max(0, Math.min(found, Math.max(0, list.length - 1)))
        if (list.length > 0) selectedApp = Number(list[currentFilteredIndex].realIndex)
        grid.currentIndex = currentFilteredIndex
    }

    function appCount() { return filteredApps.length }
    function wrapIndex(index) {
        var count = appCount()
        if (count <= 0) return 0
        index %= count
        return index < 0 ? index + count : index
    }
    function selectedAppData() {
        return filteredApps.length > 0 ? filteredApps[currentFilteredIndex].app : null
    }
    function setSelectedIndex(realIndex) {
        var found = 0
        for (var i = 0; i < filteredApps.length; ++i) {
            if (Number(filteredApps[i].realIndex) === Number(realIndex)) { found = i; break }
        }
        currentFilteredIndex = Math.max(0, Math.min(found, Math.max(0, filteredApps.length - 1)))
        if (filteredApps.length > 0) selectedApp = Number(filteredApps[currentFilteredIndex].realIndex)
        grid.currentIndex = currentFilteredIndex
        grid.positionViewAtIndex(currentFilteredIndex, GridView.Contain)
    }
    function columns() { return Math.max(2, Math.floor(width / Math.max(180, cellWidth))) }
    function setFilteredIndex(index) {
        if (filteredApps.length <= 0) return
        currentFilteredIndex = Math.max(0, Math.min(index, filteredApps.length - 1))
        selectedApp = Number(filteredApps[currentFilteredIndex].realIndex)
        grid.currentIndex = currentFilteredIndex
        grid.positionViewAtIndex(currentFilteredIndex, GridView.Contain)
    }
    function requestHorizontal(delta) { setFilteredIndex(currentFilteredIndex + delta) }
    function requestVertical(delta) { setFilteredIndex(currentFilteredIndex + delta * columns()) }
    function previousApp() { requestHorizontal(-1) }
    function nextApp() { requestHorizontal(1) }
    function moveUp() { requestVertical(-1) }
    function moveDown() { requestVertical(1) }
    function activateSelected() {
        var item = filteredApps[currentFilteredIndex]
        if (item) appRequested(item.app, item.realIndex)
    }
    function cycleCategory(delta) {
        var values = categories()
        var index = values.indexOf(categoryFilter)
        if (index < 0) index = 0
        categoryFilter = values[(index + delta + values.length) % values.length]
        rebuild()
    }
    function cycleSort() {
        sortMode = sortMode === "FAVORITES" ? "A-Z" : (sortMode === "A-Z" ? "CATEGORY" : "FAVORITES")
        rebuild()
    }

    readonly property real cardWidth: Math.max(150, Math.min(270, 210 * cardSizePercent / 100))
    readonly property real cardHeight: cardWidth * 1.18
    readonly property real cellWidth: cardWidth + 28 * spacingPercent / 100
    readonly property real cellHeight: cardHeight + 34 * spacingPercent / 100

    Component.onCompleted: rebuild()

    Connections {
        target: root.appBackend()
        ignoreUnknownSignals: true
        function onAppsChanged() { root.rebuild() }
        function onFavoritesChanged() { root.rebuild() }
        function onModelChanged() { root.rebuild() }
    }

    Rectangle {
        anchors.fill: parent
        radius: 28
        color: "#080E19"
        border.width: root.sectionFocused ? 2 : 1
        border.color: root.sectionFocused ? "#4DA6FF" : "#20344C"
    }

    Row {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        height: 44
        spacing: 16
        Text { text: "DESKTOP / CARD GRID"; color: "#F4FBFF"; font.pixelSize: 20; font.bold: true }
        Rectangle { width: 2; height: 24; color: "#36516F" }
        Text { text: "CATEGORY  " + root.categoryFilter; color: "#7DF9FF"; font.pixelSize: 15; font.bold: true }
        Text { text: "SORT  " + root.sortMode; color: "#C084FC"; font.pixelSize: 15; font.bold: true }
        Item { width: Math.max(1, parent.width - 720); height: 1 }
        Text { text: "L2/R2 CATEGORY  •  L3 CATEGORY  •  R3 SORT"; color: "#8AA6C8"; font.pixelSize: 13; font.bold: true }
    }

    GridView {
        id: grid
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        clip: true
        cellWidth: root.cellWidth
        cellHeight: root.cellHeight
        model: root.filteredApps
        currentIndex: root.currentFilteredIndex
        highlightMoveDuration: 160
        keyNavigationEnabled: false
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight

            AppTile {
                anchors.centerIn: parent
                width: root.cardWidth
                height: root.cardHeight
                appData: modelData.app
                realIndex: modelData.realIndex
                displayNumber: modelData.realIndex + 1
                focused: root.sectionFocused && index === root.currentFilteredIndex
                armed: root.armedApp === modelData.realIndex
                onOpenRequested: function(data, realIndex) { root.appRequested(data, realIndex) }
            }
        }
    }

    Text {
        visible: root.filteredApps.length <= 0
        anchors.centerIn: parent
        text: "NO APPS IN THIS CATEGORY"
        color: "#8AA6C8"
        font.pixelSize: 22
        font.bold: true
    }
}
