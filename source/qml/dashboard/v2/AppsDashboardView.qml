import QtQuick

Item {
    id: root

    property var backend: null
    property bool controllerActive: false
    property int selectedIndex: 0

    signal appLaunchRequested(var appData)
    signal detailsRequested(string kind, var context)
    signal actionsRequested(string kind, var context)

    readonly property real uiScale: Math.max(
        0.90,
        Math.min(
            1.40,
            Math.min(width / 1840, height / 860)
        )
    )

    // Exact manifest-first model shared with the dashboard app row.
    readonly property var apps:
        backend && backend.dashboardApps
        ? backend.dashboardApps
        : []

    readonly property int visibleColumns: 4
    readonly property int visibleRows: 2

    readonly property real cellW:
        appGrid.width / visibleColumns

    readonly property real cellH:
        appGrid.height / visibleRows

    readonly property real infoPanelHeight:
        94 * uiScale

    function wrapIndex(index) {
        if (!apps || apps.length <= 0)
            return 0

        var count = apps.length
        return ((index % count) + count) % count
    }

    function currentApp() {
        if (!apps || apps.length <= 0)
            return null

        return apps[wrapIndex(selectedIndex)]
    }

    function smoothReveal(index, immediate) {
        if (!apps || apps.length <= 0)
            return

        var row = Math.floor(index / visibleColumns)
        var rowTop = row * appGrid.cellHeight
        var rowBottom = rowTop + appGrid.cellHeight

        var viewportTop = appGrid.contentY
        var viewportBottom = viewportTop + appGrid.height

        var target = viewportTop

        if (rowTop < viewportTop + 1) {
            target = rowTop
        } else if (rowBottom > viewportBottom - 1) {
            target = rowBottom - appGrid.height
        } else {
            return
        }

        var maxY = Math.max(
            0,
            appGrid.contentHeight - appGrid.height
        )

        target = Math.max(0, Math.min(target, maxY))

        scrollAnimation.stop()

        if (immediate) {
            appGrid.contentY = target
            return
        }

        scrollAnimation.from = appGrid.contentY
        scrollAnimation.to = target
        scrollAnimation.start()
    }

    function clampSelection() {
        if (!apps || apps.length <= 0) {
            selectedIndex = 0
            appGrid.currentIndex = -1
            return
        }

        selectedIndex = wrapIndex(selectedIndex)

        Qt.callLater(function() {
            appGrid.currentIndex = root.selectedIndex
            root.smoothReveal(root.selectedIndex, true)
        })
    }

    function selectApp(index, immediate) {
        if (!apps || apps.length <= 0)
            return

        var wrapped = wrapIndex(index)

        selectedIndex = wrapped
        appGrid.currentIndex = wrapped
        smoothReveal(wrapped, immediate === true)
    }

    function handleControllerPressed(action) {
        if (!apps || apps.length <= 0)
            return true

        if (action === "left") {
            selectApp(selectedIndex - 1, false)
        } else if (action === "right") {
            selectApp(selectedIndex + 1, false)
        } else if (action === "up") {
            selectApp(selectedIndex - visibleColumns, false)
        } else if (action === "down") {
            selectApp(selectedIndex + visibleColumns, false)
        } else if (action === "primary" && currentApp()) {
            appLaunchRequested(currentApp())
        } else if (action === "context" && currentApp()) {
            detailsRequested(
                "application",
                { app: currentApp() }
            )
        } else if (action === "secondary" && currentApp()) {
            actionsRequested(
                "application",
                { app: currentApp() }
            )
        }

        return true
    }

    function refreshLiveStatuses() {
        if (
            backend &&
            typeof backend.refreshStatuses === "function"
        ) {
            backend.refreshStatuses()
        }
    }

    onAppsChanged: clampSelection()

    onBackendChanged: {
        clampSelection()
        Qt.callLater(refreshLiveStatuses)
    }

    onWidthChanged: clampSelection()

    Component.onCompleted: {
        clampSelection()
        Qt.callLater(refreshLiveStatuses)
    }

    Connections {
        target: root.backend
        ignoreUnknownSignals: true

        function onAppsChanged() {
            root.clampSelection()
        }
    }

    // Service/App states are cheap enough to refresh periodically on this page,
    // but we do not run heavyweight app-size scans here.
    Timer {
        interval: 5000
        repeat: true
        running:
            root.visible &&
            root.backend !== null

        onTriggered: root.refreshLiveStatuses()
    }

    NumberAnimation {
        id: scrollAnimation

        target: appGrid
        property: "contentY"

        duration: 240
        easing.type: Easing.InOutCubic
    }

    Item {
        anchors.fill: parent

        GridView {
            id: appGrid

            anchors.fill: parent
            anchors.margins: 1 * root.uiScale

            clip: true
            interactive: false

            model: root.apps
            currentIndex: root.selectedIndex

            cellWidth: root.cellW
            cellHeight: root.cellH

            cacheBuffer: height
            highlightMoveDuration: 170

            delegate: Item {
                required property int index
                required property var modelData

                width: appGrid.cellWidth
                height: appGrid.cellHeight

                DashboardAppTile {
                    id: tile

                    // The 1:1 poster is fully displayed, then the information
                    // panel is physically added below it. Nothing covers art.
                    readonly property real posterSide: Math.min(
                        parent.width - 8 * root.uiScale,
                        parent.height -
                            root.infoPanelHeight -
                            6 * root.uiScale,
                        420 * root.uiScale
                    )

                    width: posterSide
                    height:
                        posterSide +
                        root.infoPanelHeight

                    anchors.centerIn: parent

                    backend: root.backend
                    appData: modelData

                    selected:
                        root.controllerActive &&
                        root.selectedIndex === index

                    accent: "#49DFFF"
                    uiScale: root.uiScale

                    onFocused: {
                        root.selectApp(index, false)
                    }

                    onActivated: {
                        root.selectApp(index, false)
                        root.appLaunchRequested(modelData)
                    }

                    onDetailsRequested: {
                        root.selectApp(index, false)

                        root.detailsRequested(
                            "application",
                            { app: modelData }
                        )
                    }

                    onActionsRequested: {
                        root.selectApp(index, false)

                        root.actionsRequested(
                            "application",
                            { app: modelData }
                        )
                    }
                }
            }
        }

        Rectangle {
            visible: !root.apps || root.apps.length === 0

            anchors.centerIn: parent

            width: 430 * root.uiScale
            height: 132 * root.uiScale
            radius: 18 * root.uiScale

            color: "#DA091522"
            border.width: 1.5 * root.uiScale
            border.color: "#49DFFF"

            Column {
                anchors.centerIn: parent
                spacing: 7 * root.uiScale

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: "NO DASHBOARD APPS AVAILABLE"

                    color: "#F6FAFF"
                    font.pixelSize: 18 * root.uiScale
                    font.bold: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: "Waiting for manifest-backed AppManager entries…"

                    color: "#9DB2C9"
                    font.pixelSize: 12.5 * root.uiScale
                }
            }
        }
    }
}
