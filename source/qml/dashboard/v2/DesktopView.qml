import QtQuick

Item {
    id: root
    focus: true

    property var appsBackend: null
    property var layoutBackend: null
    property var monitorBackend: null
    property var storageBackend: null
    property var networkBackend: null
    property var securityBackend: null
    property var notificationBackend: null
    property var clockBackend: null
    property var controllerBackend: null
    property var activeUser: null
    property bool shellActive: false
    property bool controllerActive: true
    property string iconSizeMode: "large"
    property bool autoSeedEnabled: false

    // The shell computes these once for the active display and then leaves them
    // fixed for the lifetime of the shell session. The Desktop never chases
    // resize events after that initial scan.
    property int scannedScreenWidth: 0
    property int scannedScreenHeight: 0
    property int gridColumns: 20
    property int gridRows: 10
    property real fixedCellSize: 0
    property real gridHorizontalInset: 10

    // Session-owned Desktop layout. ModernDashboard owns this array so it
    // survives switching between Desktop and the existing dashboard pages.
    property var desktopItems: []

    property int selectedIndex: 0
    property bool moveMode: false
    property int movingIndex: -1
    property int moveOriginColumn: 0
    property int moveOriginRow: 0
    property bool drawerOpen: false
    property int drawerTab: 0       // 0 Apps, 1 Widgets
    property int drawerIndex: 0
    property bool actionPanelOpen: false
    property int actionIndex: 0
    property bool actionConfirm: false
    property bool defaultsSeeded: false
    property bool movePreviewMinimal: false
    property string statusText: ""
    readonly property real uiScale: Math.max(1, Math.min(2, Math.min(width / 1920, height / 1080)))

    readonly property bool controllerModalOpen: drawerOpen || actionPanelOpen || moveMode
    readonly property real usableGridWidth: Math.max(1, width - gridHorizontalInset * 2)
    readonly property real cellSize: fixedCellSize > 0
                                     ? fixedCellSize
                                     : Math.max(1, Math.floor(Math.min(usableGridWidth / gridColumns,
                                                                      height / gridRows)))
    readonly property real gridWidth: cellSize * gridColumns
    readonly property real gridHeight: cellSize * gridRows
    readonly property real gridOriginX: gridHorizontalInset + Math.max(0, (usableGridWidth - gridWidth) / 2)
    readonly property real gridOriginY: Math.max(0, (height - gridHeight) / 2)
    readonly property var drawerEntries: drawerTab === 0 ? availableApps() : availableWidgets()
    readonly property string currentHighlightTitle: highlightedTitle()

    signal desktopLayoutChanged(var items)
    signal desktopLayoutCommitted(var items)
    signal detailsRequested(string kind, var context)
    signal actionsRequested(string kind, var context)
    signal appLaunchRequested(var appData)
    signal topBoundaryRequested()
    signal rightBoundaryRequested()
    signal bottomBoundaryRequested()
    signal defaultSeedCompleted()

    function safeText(value) {
        return String(value === undefined || value === null ? "" : value).trim()
    }

    function cloneObject(source) {
        var target = {}
        source = source || ({})
        for (var key in source)
            target[key] = source[key]
        return target
    }

    function cloneItems(source) {
        var out = []
        source = source || []
        for (var i = 0; i < source.length; ++i)
            out.push(cloneObject(source[i]))
        return out
    }

    function commitItems(items) {
        desktopItems = items
        desktopLayoutChanged(items)
        selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, items.length - 1)))
    }

    function appId(app) {
        app = app || ({})
        return safeText(app.id || app.appId || app.name)
    }

    function validManifestIds() {
        return [
            "appstore",
            "docker",
            "filemanager",
            "logs",
            "neutronremotesystems",
            "security",
            "settings",
            "storage",
            "terminal"
        ]
    }

    function appHasValidJson(app) {
        app = app || ({})
        var id = appId(app)
        if (!id.length)
            return false
        try {
            if (appsBackend && typeof appsBackend.hasValidDashboardManifest === "function")
                return appsBackend.hasValidDashboardManifest(app) === true
        } catch (error) {}
        var manifestPath = safeText(app.manifestPath || app.appJsonPath || app.manifest || app.dashboardManifest)
        if (manifestPath.toLowerCase().indexOf("app.json") >= 0)
            return true
        return validManifestIds().indexOf(id) >= 0
    }

    function highlightedTitle() {
        if (drawerOpen && drawerEntries.length > 0) {
            var entry = drawerEntries[Math.max(0, Math.min(drawerIndex, drawerEntries.length - 1))] || ({})
            if (drawerTab === 0)
                return appName(entry)
            var label = widgetName(entry)
            return label.toLowerCase().indexOf("widget") >= 0 ? label : label + " Widget"
        }
        if (!controllerActive && !moveMode)
            return ""
        var item = selectedItem()
        if (!item)
            return ""
        if (item.type === "app")
            return appName(item.appData || ({}))
        var widgetLabel = safeText(item.title || widgetName(item.widgetData || ({})))
        return widgetLabel.toLowerCase().indexOf("widget") >= 0 ? widgetLabel : widgetLabel + " Widget"
    }

    function availableApps() {
        if (!appsBackend)
            return []
        try {
            // dashboardApps() is AppManager's manifest-qualified application
            // list.  Using it directly keeps shell helpers such as SSH/htop out
            // while allowing future downloaded apps with a valid app.json in.
            if (appsBackend.dashboardApps)
                return appsBackend.dashboardApps || []
            var source = appsBackend.apps ? appsBackend.apps : []
            var out = []
            for (var i = 0; i < source.length; ++i)
                if (appHasValidJson(source[i] || ({})))
                    out.push(source[i])
            return out
        } catch (error) {
            return []
        }
    }

    function availableWidgets() {
        if (!layoutBackend)
            return []
        try {
            var source = layoutBackend.widgets
            if ((!source || source.length === 0) &&
                    typeof layoutBackend.widgetsForTab === "function")
                source = layoutBackend.widgetsForTab("system")
            return source || []
        } catch (error) {
            return []
        }
    }

    function appManagementDetails(app) {
        try {
            if (appsBackend && typeof appsBackend.appManagementDetails === "function")
                return appsBackend.appManagementDetails(app || ({})) || ({})
        } catch (error) {}
        return ({})
    }

    function isSystemApp(app) {
        app = app || ({})
        if (app.system === true || app.isSystem === true || app.systemApp === true ||
                app.builtIn === true || app.builtin === true)
            return true
        var category = safeText(app.category || app.group || app.section).toLowerCase()
        if (category === "system" || category.indexOf("system") >= 0)
            return true
        var details = appManagementDetails(app)
        var owner = safeText(details.ownershipText || details.typeText || app.ownership || app.sourceType).toLowerCase()
        return owner === "system" || owner.indexOf("system") >= 0
    }

    function canUninstallApp(app) {
        try {
            return !!(appsBackend && typeof appsBackend.canUninstallApp === "function" &&
                      appsBackend.canUninstallApp(app || ({})))
        } catch (error) { return false }
    }

    function seedDefaultSystemApps() {
        if (!autoSeedEnabled)
            return
        if (defaultsSeeded)
            return
        if (desktopItems && desktopItems.length > 0) {
            defaultsSeeded = true
            defaultSeedCompleted()
            return
        }
        var apps = availableApps()
        if (!apps || apps.length === 0)
            return
        var items = []
        var row = 0
        for (var i = 0; i < apps.length && row < gridRows; ++i) {
            var app = apps[i] || ({})
            if (!isSystemApp(app))
                continue
            items.push({
                type: "app",
                sourceId: safeText(app.id || app.appId || app.name),
                title: appName(app),
                gridColumn: 0,
                gridRow: row,
                columnSpan: 1,
                rowSpan: 1,
                appData: app
            })
            row++
        }
        defaultsSeeded = true
        if (items.length > 0) {
            commitItems(items)
            desktopLayoutCommitted(items)
        }
        defaultSeedCompleted()
    }

    function appIconSource(app) {
        app = app || ({})
        var raw = safeText(app.iconSource || app.iconPath || app.icon)
        if (!raw)
            return ""
        if (raw.indexOf(":") >= 0 || raw.indexOf("/") >= 0)
            return raw
        return Qt.resolvedUrl("../../../themes/Default/apps/icons/" + raw + ".png")
    }

    function widgetIconSource(widget) {
        widget = widget || ({})
        var raw = safeText(widget.iconSource || widget.iconPath || widget.icon)
        if (raw.length) {
            if (raw.indexOf(":") >= 0 || raw.indexOf("/") >= 0)
                return raw
            return Qt.resolvedUrl("../../../themes/Default/widgets/" + raw + ".png")
        }
        var id = safeText(widget.id)
        return id.length ? Qt.resolvedUrl("../../../themes/Default/widgets/" + id + ".png") : ""
    }

    function appName(app) {
        app = app || ({})
        return safeText(app.name || app.displayName || app.title || app.id) || "Application"
    }

    function widgetName(widget) {
        widget = widget || ({})
        return safeText(widget.title || widget.name || widget.id) || "Widget"
    }

    function widgetDefaultGeometry(widget) {
        widget = widget || ({})
        var family = safeText(widget.sizeFamily || widget.size).toLowerCase()
        var shape = safeText(widget.shape || widget.variant).toLowerCase()

        if (family.indexOf("large") >= 0) {
            if (shape.indexOf("tall") >= 0) return ({ columns: 4, rows: 6 })
            if (shape.indexOf("square") >= 0) return ({ columns: 6, rows: 6 })
            return ({ columns: 6, rows: 4 })
        }
        if (family.indexOf("medium") >= 0) {
            if (shape.indexOf("tall") >= 0) return ({ columns: 2, rows: 4 })
            if (shape.indexOf("square") >= 0) return ({ columns: 4, rows: 4 })
            return ({ columns: 4, rows: 2 })
        }

        // Fixed widgets such as Temperature enter the Desktop at Small size.
        return ({ columns: 2, rows: 2 })
    }

    function nearestWidgetProfile(columns, rows) {
        var profiles = [
            { columns: 2, rows: 2, family: "small", variant: "small-square", shape: "square" },
            { columns: 4, rows: 2, family: "medium", variant: "medium-wide", shape: "wide" },
            { columns: 2, rows: 4, family: "medium", variant: "medium-tall", shape: "tall" },
            { columns: 4, rows: 4, family: "medium", variant: "medium-square", shape: "square" },
            { columns: 6, rows: 4, family: "large", variant: "large-wide", shape: "wide" },
            { columns: 4, rows: 6, family: "large", variant: "large-tall", shape: "tall" },
            { columns: 6, rows: 6, family: "large", variant: "large-square", shape: "square" }
        ]
        var best = profiles[0]
        var bestDistance = Number.POSITIVE_INFINITY
        for (var i = 0; i < profiles.length; ++i) {
            var dx = Number(columns) - profiles[i].columns
            var dy = Number(rows) - profiles[i].rows
            var distance = dx * dx + dy * dy
            if (distance < bestDistance) {
                bestDistance = distance
                best = profiles[i]
            }
        }
        return best
    }

    function rectangleOverlaps(aColumn, aRow, aColumns, aRows,
                               bColumn, bRow, bColumns, bRows) {
        return aColumn < bColumn + bColumns &&
               aColumn + aColumns > bColumn &&
               aRow < bRow + bRows &&
               aRow + aRows > bRow
    }

    function canPlace(column, row, columns, rows, ignoredIndex) {
        if (column < 0 || row < 0 ||
                column + columns > gridColumns ||
                row + rows > gridRows)
            return false

        for (var i = 0; i < desktopItems.length; ++i) {
            if (i === ignoredIndex)
                continue
            var item = desktopItems[i] || ({})
            if (rectangleOverlaps(column, row, columns, rows,
                                  Number(item.gridColumn || 0),
                                  Number(item.gridRow || 0),
                                  Number(item.columnSpan || 1),
                                  Number(item.rowSpan || 1)))
                return false
        }
        return true
    }

    function firstOpenSpot(columns, rows) {
        for (var row = 0; row <= gridRows - rows; ++row)
            for (var column = 0; column <= gridColumns - columns; ++column)
                if (canPlace(column, row, columns, rows, -1))
                    return ({ column: column, row: row })
        return null
    }

    function itemCenter(item) {
        item = item || ({})
        return ({
            x: Number(item.gridColumn || 0) + Number(item.columnSpan || 1) / 2,
            y: Number(item.gridRow || 0) + Number(item.rowSpan || 1) / 2
        })
    }

    function rangesOverlap(a0, a1, b0, b1) {
        return Math.min(a1, b1) > Math.max(a0, b0)
    }

    function spatialNeighbor(direction) {
        if (desktopItems.length === 0)
            return -1
        var currentIndex = Math.max(0, Math.min(selectedIndex, desktopItems.length - 1))
        var currentVisual = desktopRepeater.itemAt(currentIndex)
        if (!currentVisual || !currentVisual.visible || !currentVisual.enabled ||
                currentVisual.width <= 0 || currentVisual.height <= 0)
            return -1
        var currentPoint = currentVisual.mapToItem(root, 0, 0)
        var cLeft = currentPoint.x
        var cTop = currentPoint.y
        var cRight = cLeft + currentVisual.width
        var cBottom = cTop + currentVisual.height
        var cX = (cLeft + cRight) / 2
        var cY = (cTop + cBottom) / 2
        var best = -1
        var bestDistance = Number.POSITIVE_INFINITY
        var bestAngle = Number.POSITIVE_INFINITY
        var bestCenterDistance = Number.POSITIVE_INFINITY

        for (var i = 0; i < desktopItems.length; ++i) {
            if (i === selectedIndex)
                continue
            var candidate = desktopItems[i] || ({})
            if (candidate.visible === false || candidate.enabled === false)
                continue
            var candidateVisual = desktopRepeater.itemAt(i)
            if (!candidateVisual || !candidateVisual.visible || !candidateVisual.enabled ||
                    candidateVisual.width <= 0 || candidateVisual.height <= 0)
                continue
            var candidatePoint = candidateVisual.mapToItem(root, 0, 0)
            var left = candidatePoint.x
            var top = candidatePoint.y
            var right = left + candidateVisual.width
            var bottom = top + candidateVisual.height
            var x = (left + right) / 2
            var y = (top + bottom) / 2
            var forwardGap = 0
            var perpendicularGap = 0
            var primaryCenter = 0
            var perpendicularCenter = 0
            var eligible = false

            if (direction === "right") {
                eligible = x > cX
                forwardGap = Math.max(0, left - cRight)
                perpendicularGap = bottom <= cTop ? cTop - bottom : top >= cBottom ? top - cBottom : 0
                primaryCenter = x - cX
                perpendicularCenter = Math.abs(y - cY)
            } else if (direction === "left") {
                eligible = x < cX
                forwardGap = Math.max(0, cLeft - right)
                perpendicularGap = bottom <= cTop ? cTop - bottom : top >= cBottom ? top - cBottom : 0
                primaryCenter = cX - x
                perpendicularCenter = Math.abs(y - cY)
            } else if (direction === "down") {
                eligible = y > cY
                forwardGap = Math.max(0, top - cBottom)
                perpendicularGap = right <= cLeft ? cLeft - right : left >= cRight ? left - cRight : 0
                primaryCenter = y - cY
                perpendicularCenter = Math.abs(x - cX)
            } else if (direction === "up") {
                eligible = y < cY
                forwardGap = Math.max(0, cTop - bottom)
                perpendicularGap = right <= cLeft ? cLeft - right : left >= cRight ? left - cRight : 0
                primaryCenter = cY - y
                perpendicularCenter = Math.abs(x - cX)
            }

            if (!eligible)
                continue
            var distance = Math.sqrt(forwardGap * forwardGap + perpendicularGap * perpendicularGap)
            var angle = perpendicularCenter / Math.max(1, primaryCenter)
            var centerDistance = Math.sqrt(primaryCenter * primaryCenter + perpendicularCenter * perpendicularCenter)
            if (distance < bestDistance - 0.001 ||
                    (Math.abs(distance - bestDistance) <= 0.001 && angle < bestAngle - 0.000001) ||
                    (Math.abs(distance - bestDistance) <= 0.001 && Math.abs(angle - bestAngle) <= 0.000001 && centerDistance < bestCenterDistance - 0.001) ||
                    (Math.abs(distance - bestDistance) <= 0.001 && Math.abs(angle - bestAngle) <= 0.000001 && Math.abs(centerDistance - bestCenterDistance) <= 0.001 && i < best)) {
                bestDistance = distance
                bestAngle = angle
                bestCenterDistance = centerDistance
                best = i
            }
        }
        return best
    }

    function navigate(direction) {
        var next = spatialNeighbor(direction)
        if (next >= 0) {
            selectedIndex = next
            return true
        }
        if (direction === "up")
            topBoundaryRequested()
        else if (direction === "right")
            rightBoundaryRequested()
        else if (direction === "down")
            bottomBoundaryRequested()
        return true
    }

    function containsApp(appId) {
        appId = safeText(appId)
        for (var i = 0; i < desktopItems.length; ++i)
            if (desktopItems[i].type === "app" && safeText(desktopItems[i].sourceId) === appId)
                return i
        return -1
    }

    function containsWidget(widgetId) {
        widgetId = safeText(widgetId)
        for (var i = 0; i < desktopItems.length; ++i)
            if (desktopItems[i].type === "widget" && safeText(desktopItems[i].sourceId) === widgetId)
                return i
        return -1
    }

    function addDrawerSelection() {
        if (drawerEntries.length === 0)
            return false
        var source = drawerEntries[Math.max(0, Math.min(drawerIndex, drawerEntries.length - 1))] || ({})
        var items = cloneItems(desktopItems)
        var newItem = ({})
        var existing = -1

        if (drawerTab === 0) {
            var appId = root.appId(source)
            existing = containsApp(appId)
            if (existing >= 0) {
                drawerOpen = false
                selectedIndex = existing
                beginMove(existing)
                return true
            }
            var appSpot = firstOpenSpot(1, 1)
            if (!appSpot) {
                statusText = "No free Desktop square is available."
                return true
            }
            newItem = {
                type: "app",
                sourceId: appId,
                title: appName(source),
                gridColumn: appSpot.column,
                gridRow: appSpot.row,
                columnSpan: 1,
                rowSpan: 1,
                appData: source
            }
        } else {
            var widgetId = safeText(source.id)
            existing = containsWidget(widgetId)
            if (existing >= 0) {
                drawerOpen = false
                selectedIndex = existing
                beginMove(existing)
                return true
            }
            var geometry = widgetDefaultGeometry(source)
            var widgetSpot = firstOpenSpot(geometry.columns, geometry.rows)
            if (!widgetSpot) {
                statusText = "No free Desktop area fits this widget."
                return true
            }
            newItem = {
                type: "widget",
                sourceId: widgetId,
                title: widgetName(source),
                gridColumn: widgetSpot.column,
                gridRow: widgetSpot.row,
                columnSpan: geometry.columns,
                rowSpan: geometry.rows,
                widgetData: source
            }
        }

        items.push(newItem)
        selectedIndex = items.length - 1
        commitItems(items)
        drawerOpen = false
        beginMove(selectedIndex)
        return true
    }

    function beginMove(index) {
        if (index < 0 || index >= desktopItems.length)
            return false
        selectedIndex = index
        movingIndex = index
        moveOriginColumn = Number(desktopItems[index].gridColumn || 0)
        moveOriginRow = Number(desktopItems[index].gridRow || 0)
        moveMode = true
        movePreviewMinimal = false
        statusText = "MOVE MODE • D-PAD / STICKS MOVE • X PLACE • □ PREVIEW • O CANCEL"
        return true
    }

    function moveSelected(direction) {
        if (!moveMode || movingIndex < 0 || movingIndex >= desktopItems.length)
            return false
        var item = desktopItems[movingIndex] || ({})
        var column = Number(item.gridColumn || 0)
        var row = Number(item.gridRow || 0)
        if (direction === "left") column--
        else if (direction === "right") column++
        else if (direction === "up") row--
        else if (direction === "down") row++
        else return true

        var columns = Number(item.columnSpan || 1)
        var rows = Number(item.rowSpan || 1)
        if (!canPlace(column, row, columns, rows, movingIndex))
            return true

        var items = cloneItems(desktopItems)
        items[movingIndex].gridColumn = column
        items[movingIndex].gridRow = row
        commitItems(items)
        selectedIndex = movingIndex
        return true
    }

    function finishMove(commit) {
        if (!moveMode)
            return false
        if (!commit && movingIndex >= 0 && movingIndex < desktopItems.length) {
            var items = cloneItems(desktopItems)
            items[movingIndex].gridColumn = moveOriginColumn
            items[movingIndex].gridRow = moveOriginRow
            commitItems(items)
        }
        moveMode = false
        movingIndex = -1
        movePreviewMinimal = false
        statusText = ""
        desktopLayoutCommitted(desktopItems)
        return true
    }

    function selectedItem() {
        return desktopItems.length > 0
               ? desktopItems[Math.max(0, Math.min(selectedIndex, desktopItems.length - 1))]
               : null
    }

    function activateSelected() {
        var item = selectedItem()
        if (!item)
            return true
        if (item.type === "app")
            appLaunchRequested(item.appData || ({}))
        else
            detailsSelected()
        return true
    }

    function detailsSelected() {
        return openActionPanel()
    }

    function openActionPanel() {
        if (!selectedItem())
            return true
        actionIndex = 0
        actionConfirm = false
        actionPanelOpen = true
        statusText = ""
        forceActiveFocus()
        return true
    }

    function closeActionPanel() {
        actionPanelOpen = false
        actionConfirm = false
        actionIndex = 0
        forceActiveFocus()
    }

    function removeSelectedDesktopItem() {
        if (selectedIndex < 0 || selectedIndex >= desktopItems.length)
            return false
        var items = cloneItems(desktopItems)
        items.splice(selectedIndex, 1)
        selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, items.length - 1)))
        commitItems(items)
        desktopLayoutCommitted(items)
        closeActionPanel()
        return true
    }

    function actionRows() {
        var item = selectedItem()
        if (!item)
            return []
        if (item.type === "app") {
            var rows = [
                { id: "open", title: "OPEN APP", detail: "Launch or focus this application", danger: false },
                { id: "remove", title: "REMOVE ICON", detail: "Remove this shortcut from Desktop only", danger: false }
            ]
            if (canUninstallApp(item.appData || ({})))
                rows.push({ id: "uninstall", title: "UNINSTALL", detail: "Remove this installed application from NeutronOS", danger: true })
            return rows
        }
        return [
            { id: "details", title: "WIDGET DETAILS", detail: "Open the widget information panel", danger: false },
            { id: "move", title: "MOVE WIDGET", detail: "Reposition this widget on the Desktop grid", danger: false },
            { id: "remove", title: "REMOVE WIDGET", detail: "Remove this widget from Desktop", danger: true }
        ]
    }

    function executeActionRow() {
        var rows = actionRows()
        if (actionIndex < 0 || actionIndex >= rows.length)
            return true
        var row = rows[actionIndex]
        var item = selectedItem()
        if (!item)
            return true
        if (row.danger && !actionConfirm) {
            actionConfirm = true
            return true
        }
        if (item.type === "app") {
            if (row.id === "open") {
                closeActionPanel()
                appLaunchRequested(item.appData || ({}))
            } else if (row.id === "remove") {
                removeSelectedDesktopItem()
            } else if (row.id === "uninstall") {
                var accepted = true
                try {
                    if (appsBackend && typeof appsBackend.uninstallApp === "function") {
                        var result = appsBackend.uninstallApp(item.appData || ({}))
                        if (result === false) accepted = false
                    } else accepted = false
                } catch (error) { accepted = false }
                if (accepted) removeSelectedDesktopItem()
                else { actionConfirm = false; statusText = "Uninstall request was not accepted." }
            }
        } else {
            if (row.id === "details") {
                closeActionPanel()
                detailsRequested(safeText(item.sourceId), { widget: item.widgetData || ({}), desktopItem: item, tabId: "desktop" })
            } else if (row.id === "move") {
                closeActionPanel()
                beginMove(selectedIndex)
            } else if (row.id === "remove") {
                removeSelectedDesktopItem()
            }
        }
        return true
    }

    function openDrawer() {
        drawerOpen = true
        drawerTab = Math.max(0, Math.min(1, drawerTab))
        drawerIndex = 0
        statusText = ""
        forceActiveFocus()
    }

    function closeDrawer() {
        drawerOpen = false
        statusText = ""
        forceActiveFocus()
    }

    function resetInteractionState() {
        if (moveMode)
            finishMove(false)
        drawerOpen = false
        actionPanelOpen = false
        actionConfirm = false
        movePreviewMinimal = false
        statusText = ""
        forceActiveFocus()
    }

    function handleControllerPressed(action) {
        action = safeText(action).toLowerCase()

        if (actionPanelOpen) {
            if (action === "cancel") { closeActionPanel(); return true }
            if (action === "up") { actionIndex = Math.max(0, actionIndex - 1); actionConfirm = false; return true }
            if (action === "down") { actionIndex = Math.min(Math.max(0, actionRows().length - 1), actionIndex + 1); actionConfirm = false; return true }
            if (action === "primary") return executeActionRow()
            return true
        }

        if (drawerOpen) {
            if (action === "cancel" || action === "system") {
                closeDrawer()
                return true
            }
            if (action === "up") {
                drawerTab = 0
                drawerIndex = Math.min(drawerIndex, Math.max(0, drawerEntries.length - 1))
                return true
            }
            if (action === "down") {
                drawerTab = 1
                drawerIndex = Math.min(drawerIndex, Math.max(0, drawerEntries.length - 1))
                return true
            }
            if (action === "l1") {
                drawerTab = Math.max(0, drawerTab - 1)
                drawerIndex = Math.min(drawerIndex, Math.max(0, drawerEntries.length - 1))
                return true
            }
            if (action === "r1") {
                drawerTab = Math.min(1, drawerTab + 1)
                drawerIndex = Math.min(drawerIndex, Math.max(0, drawerEntries.length - 1))
                return true
            }
            if (action === "left") {
                drawerIndex = Math.max(0, drawerIndex - 1)
                return true
            }
            if (action === "right") {
                drawerIndex = Math.min(Math.max(0, drawerEntries.length - 1), drawerIndex + 1)
                return true
            }
            if (action === "primary")
                return addDrawerSelection()
            return true
        }

        if (moveMode) {
            if (action === "primary") return finishMove(true)
            if (action === "cancel") return finishMove(false)
            if (action === "secondary") {
                movePreviewMinimal = !movePreviewMinimal
                statusText = movePreviewMinimal
                        ? "MOVE MODE • MINIMAL PREVIEW • D-PAD / STICKS MOVE • X PLACE • □ NORMAL • O CANCEL"
                        : "MOVE MODE • D-PAD / STICKS MOVE • X PLACE • □ PREVIEW • O CANCEL"
                return true
            }
            if (action === "left" || action === "right" || action === "up" || action === "down")
                return moveSelected(action)
            return true
        }

        if (action === "system" || action === "options" || action === "menu") {
            openDrawer()
            return true
        }
        if (action === "left" || action === "right" || action === "up" || action === "down")
            return navigate(action)
        if (action === "primary")
            return activateSelected()
        // PlayStation Square opens Desktop details/actions for the selected object.
        if (action === "secondary")
            return detailsSelected()
        // PlayStation Triangle is the dashboard context action. On Desktop it
        // deliberately becomes the quick move action requested for shortcuts/widgets.
        if (action === "context")
            return beginMove(selectedIndex)
        return true
    }

    function handleControllerReleased(action) {
        return controllerActive
    }

    onDrawerTabChanged: drawerIndex = 0
    onDesktopItemsChanged: selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, desktopItems.length - 1)))
    onAppsBackendChanged: if (autoSeedEnabled) Qt.callLater(seedDefaultSystemApps)
    Component.onCompleted: if (autoSeedEnabled) Qt.callLater(seedDefaultSystemApps)

    Connections {
        target: root.appsBackend
        ignoreUnknownSignals: true
        function onAppsChanged() { root.seedDefaultSystemApps() }
    }

    Item {
        id: desktopGrid
        x: root.gridOriginX
        y: root.gridOriginY
        width: root.gridWidth
        height: root.gridHeight
        clip: true

        Repeater {
            id: desktopRepeater
            model: root.desktopItems

            delegate: Item {
                id: desktopObject
                required property int index
                required property var modelData

                x: Number(modelData.gridColumn || 0) * root.cellSize
                y: Number(modelData.gridRow || 0) * root.cellSize
                width: Number(modelData.columnSpan || 1) * root.cellSize
                height: Number(modelData.rowSpan || 1) * root.cellSize
                transformOrigin: Item.Center
                z: root.moveMode && root.movingIndex === index ? 30 : 2

                SequentialAnimation on rotation {
                    id: moveShake
                    running: root.moveMode && root.movingIndex === desktopObject.index
                    loops: Animation.Infinite
                    NumberAnimation { from: -1.3; to: 1.3; duration: 85; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.3; to: -1.3; duration: 85; easing.type: Easing.InOutSine }
                    onStopped: desktopObject.rotation = 0
                }

                Loader {
                    anchors.fill: parent
                    anchors.margins: 0
                    sourceComponent: modelData.type === "app" ? appShortcutComponent : widgetComponent
                }

                Component {
                    id: appShortcutComponent
                    Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) * (root.iconSizeMode === "small" ? 0.72 : 1.00)
                            height: width
                            radius: Math.max(14, width * 0.16)
                            color: "transparent"
                            border.width: root.controllerActive && root.selectedIndex === desktopObject.index ? 4 : 0
                            border.color: "#4DA6FF"
                            // Keep the selected icon locked to its grid square. Selection is
                            // shown with the focus border rather than enlarging beyond the cell.
                            scale: 1.0

                            Image {
                                id: desktopAppIcon
                                anchors.fill: parent
                                anchors.margins: 4
                                source: root.appIconSource(modelData.appData || ({}))
                                sourceSize.width: 500
                                sourceSize.height: 500
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: desktopAppIcon.status === Image.Error ||
                                         root.appIconSource(modelData.appData || ({})).length === 0
                                text: root.appName(modelData.appData || ({})).slice(0, 1).toUpperCase()
                                color: "#7DF9FF"
                                font.pixelSize: Math.max(28, parent.width * 0.34)
                                font.bold: true
                            }
                        }
                    }
                }

                Component {
                    id: widgetComponent
                    AdaptiveWidget {
                        readonly property var nearestProfile: root.nearestWidgetProfile(
                                                                  Number(modelData.columnSpan || 2),
                                                                  Number(modelData.rowSpan || 2))
                        widgetId: root.safeText(modelData.sourceId)
                        widgetVariant: nearestProfile.variant
                        widgetSize: nearestProfile.family
                        shapeVariant: nearestProfile.shape
                        title: root.safeText(modelData.title)
                        selected: root.controllerActive && root.selectedIndex === desktopObject.index
                        moving: root.moveMode && root.movingIndex === desktopObject.index
                        // DashboardCard normally grows selected widgets slightly. Desktop
                        // placement must remain pixel-aligned with the same cell edges as apps.
                        scale: 1.0
                        viewportWidth: root.width
                        monitorBackend: root.monitorBackend
                        networkBackend: root.networkBackend
                        securityBackend: root.securityBackend
                        notificationBackend: root.notificationBackend
                        clockBackend: root.clockBackend
                        activeUser: root.activeUser
                        controllerBackend: root.controllerBackend
                        appsBackend: root.appsBackend
                        storageBackend: root.storageBackend
                        storageSlot: widgetId === "media-storage" ? 1 : 0
                        storageData: root.monitorBackend && root.monitorBackend.storageDisplaySlots &&
                                     root.monitorBackend.storageDisplaySlots.length > storageSlot
                                     ? root.monitorBackend.storageDisplaySlots[storageSlot] : ({})
                        animationEnabled: root.visible && root.shellActive
                        transparentShell: root.movePreviewMinimal && root.moveMode && root.movingIndex === desktopObject.index
                        opacity: 1.0
                    }
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 8
        visible: root.desktopItems.length === 0 && !root.drawerOpen
        opacity: 0.64

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "DESKTOP"
            color: "#8AA6C8"
            font.pixelSize: 18
            font.bold: true
            font.letterSpacing: 3
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "OPTIONS  •  ADD APPS & WIDGETS"
            color: "#5E7898"
            font.pixelSize: 13
            font.bold: true
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        visible: root.statusText.length > 0
        text: root.statusText
        color: "#7DF9FF"
        font.pixelSize: 13
        font.bold: true
    }

    Rectangle {
        id: drawer
        z: 100
        width: Math.min(root.width * 0.80, 1500)
        height: Math.min(root.height * 0.38, 440)
        x: (root.width - width) / 2
        y: root.drawerOpen ? 0 : -height - 24
        radius: 0
        color: "#F2030810"
        border.width: 0
        clip: true
        visible: y > -height - 20

        Behavior on y {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            color: "#4DA6FF"
            opacity: 0.78
        }

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Repeater {
                    model: ["APPS", "WIDGETS"]
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: 180
                        height: 48
                        radius: 13
                        color: root.drawerTab === index ? "#17365D" : "#071426"
                        border.width: root.drawerTab === index ? 2 : 1
                        border.color: root.drawerTab === index ? "#4DA6FF" : "#1D3958"
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: root.drawerTab === index ? "#7DF9FF" : "#8AA6C8"
                            font.pixelSize: 15
                            font.bold: true
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: parent.height - 98
                clip: true

                ListView {
                    id: drawerList
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 18
                    interactive: false
                    currentIndex: root.drawerIndex
                    model: root.drawerEntries

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: 172
                        height: drawerList.height - 8
                        radius: 20
                        color: index === root.drawerIndex ? "#0D263A" : "#071426"
                        border.width: index === root.drawerIndex ? 3 : 1
                        border.color: index === root.drawerIndex ? "#4DA6FF" : "#1D3958"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Item {
                                width: parent.width
                                height: parent.height - 56

                                Image {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width, parent.height) * 0.78
                                    height: width
                                    visible: root.drawerTab === 0
                                    source: root.appIconSource(modelData)
                                    sourceSize.width: 500
                                    sourceSize.height: 500
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width, parent.height) * 0.70
                                    height: width
                                    radius: width * 0.22
                                    visible: root.drawerTab === 1
                                    color: "#0B1A30"
                                    border.width: 2
                                    border.color: "#7DF9FF"

                                    Image {
                                        id: drawerWidgetIcon
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        visible: root.drawerTab === 1
                                        source: root.widgetIconSource(modelData)
                                        sourceSize.width: 500
                                        sourceSize.height: 500
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !drawerWidgetIcon.visible || drawerWidgetIcon.status === Image.Error || String(drawerWidgetIcon.source).length === 0
                                        text: "▦"
                                        color: "#7DF9FF"
                                        font.pixelSize: parent.width * 0.34
                                        font.bold: true
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: root.drawerTab === 0 ? root.appName(modelData) : root.widgetName(modelData)
                                color: "#F4FBFF"
                                font.pixelSize: 14
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: actionShade
        anchors.fill: parent
        visible: root.actionPanelOpen
        color: "#A8000308"
        z: 180

        MouseArea { anchors.fill: parent; onClicked: root.closeActionPanel() }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.54, 860)
            height: Math.min(parent.height * 0.62, 650)
            radius: 28
            color: "#F5071426"
            border.width: 2
            border.color: root.actionConfirm ? "#FF4057" : "#4DA6FF"

            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 16

                Text {
                    width: parent.width
                    text: {
                        var item = root.selectedItem()
                        return item && item.type === "app" ? root.appName(item.appData || ({})).toUpperCase() : root.safeText(item ? item.title : "WIDGET").toUpperCase()
                    }
                    color: "#F4FBFF"
                    font.pixelSize: 26
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.actionConfirm ? "PRESS X AGAIN TO CONFIRM" : (root.selectedItem() && root.selectedItem().type === "app" ? "APP DETAILS & ACTIONS" : "WIDGET DETAILS & ACTIONS")
                    color: root.actionConfirm ? "#FF6577" : "#7DF9FF"
                    font.pixelSize: 13
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    font.letterSpacing: 2
                }

                ListView {
                    id: actionList
                    width: parent.width
                    height: parent.height - 112
                    spacing: 10
                    interactive: false
                    model: root.actionRows()
                    currentIndex: root.actionIndex

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: actionList.width
                        height: 84
                        radius: 17
                        color: index === root.actionIndex ? (modelData.danger ? "#39141E" : "#0D263A") : "#081522"
                        border.width: index === root.actionIndex ? 2 : 1
                        border.color: index === root.actionIndex ? (modelData.danger ? "#FF4057" : "#4DA6FF") : "#203847"

                        Row {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 14
                            Rectangle {
                                width: 46; height: 46; radius: 13
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.danger ? "#311019" : "#091B2D"
                                border.width: 1
                                border.color: modelData.danger ? "#FF4057" : "#315D86"
                                Text { anchors.centerIn: parent; text: modelData.id === "open" ? "▶" : modelData.id === "uninstall" ? "×" : modelData.id === "move" ? "↔" : modelData.id === "details" ? "i" : "−"; color: modelData.danger ? "#FF6577" : "#7DF9FF"; font.pixelSize: 20; font.bold: true }
                            }
                            Column {
                                width: parent.width - 70
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text { width: parent.width; text: modelData.title; color: "#F4FBFF"; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.detail; color: "#8AA6C8"; font.pixelSize: 12; elide: Text.ElideRight }
                            }
                        }
                    }
                }
            }
        }
    }

}
