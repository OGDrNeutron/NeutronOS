import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root

    property var appBackend:
        (typeof appManager !== "undefined" && appManager)
        ? appManager
        : ((typeof appLauncher !== "undefined" && appLauncher)
           ? appLauncher
           : null)

    property var appsModel: []
    property var requestedApp: null
    property int selectedIndex: 0
    property string statusText: "Reorder the app carousel"

    signal closed()
    signal orderChanged(string appId, int index)

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 1260

    Rectangle {
        anchors.fill: parent
        color: "#02040cb8"
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent

        width: Math.min(parent.width * 0.78, 1280)
        height: Math.min(parent.height * 0.76, 780)
        radius: 34

        color: "#07101f"

        border.width: 2
        border.color: "#7df9ff"

        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 34
            spacing: 20

            Text {
                width: parent.width

                text: "APP CAROUSEL"
                color: "#ffffff"

                font.pixelSize: 34
                font.bold: true
                font.letterSpacing: 3

                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width

                text: root.statusText
                color: "#9fd8ff"

                font.pixelSize: 15
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#326a91"
            }

            ListView {
                id: orderList

                width: parent.width
                height: parent.height - 156

                clip: true
                spacing: 10
                interactive: false

                model: root.appsModel
                currentIndex: root.selectedIndex

                delegate: Rectangle {
                    required property int index
                    required property var modelData

                    width: orderList.width
                    height: 78
                    radius: 22

                    color:
                        index === root.selectedIndex
                        ? "#142b42"
                        : "#0d1a2d"

                    border.width:
                        index === root.selectedIndex
                        ? 3
                        : 1

                    border.color:
                        index === root.selectedIndex
                        ? "#4da6ff"
                        : "#29445f"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22

                        spacing: 20

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 58

                            text:
                                (index + 1 < 10 ? "0" : "") +
                                String(index + 1)

                            color:
                                index === root.selectedIndex
                                ? "#ff4ea8"
                                : "#7df9ff"

                            font.pixelSize: 26
                            font.bold: true
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter

                            width: parent.width - 230
                            spacing: 3

                            Text {
                                width: parent.width

                                text: root.appName(modelData)
                                color: "#ffffff"

                                font.pixelSize: 22
                                font.bold: true

                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width

                                text: root.appType(modelData).toUpperCase()
                                color: "#9fd8ff"

                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 1.4
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter

                            text:
                                index === root.selectedIndex
                                ? "◀  MOVE  ▶"
                                : ""

                            color: "#7df9ff"

                            font.pixelSize: 16
                            font.bold: true
                        }
                    }
                }
            }

            Text {
                width: parent.width

                text:
                    "UP / DOWN  SELECT    LEFT / RIGHT  MOVE    " +
                    "X  MAKE FIRST    O  CLOSE"

                color: "#9fd8ff"

                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 1.2

                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Keys.enabled: root.visible

    Keys.onPressed: function(event) {
        var action = ""

        if (event.key === Qt.Key_Up)
            action = "up"
        else if (event.key === Qt.Key_Down)
            action = "down"
        else if (event.key === Qt.Key_Left)
            action = "left"
        else if (event.key === Qt.Key_Right)
            action = "right"
        else if (event.key === Qt.Key_Return ||
                 event.key === Qt.Key_Enter ||
                 event.key === Qt.Key_X)
            action = "primary"
        else if (event.key === Qt.Key_Escape ||
                 event.key === Qt.Key_Backspace ||
                 event.key === Qt.Key_O)
            action = "cancel"

        if (action.length > 0) {
            root.handleControllerPressed(action)
            event.accepted = true
        }
    }

    function appName(app) {
        return app && app.name
               ? String(app.name)
               : "Unknown App"
    }

    function appType(app) {
        return app && app.type
               ? String(app.type)
               : "app"
    }

    function appId(app) {
        return app && app.id
               ? String(app.id)
               : ""
    }

    function backendFavoriteApps() {
        try {
            if (root.appBackend && root.appBackend.favoriteApps)
                return root.appBackend.favoriteApps
        } catch (error) {
        }

        return []
    }

    function refreshModel(preferredId) {
        var targetId = String(preferredId || "")

        if (targetId.length === 0 &&
                root.appsModel.length > 0 &&
                root.selectedIndex >= 0 &&
                root.selectedIndex < root.appsModel.length) {
            targetId = root.appId(
                root.appsModel[root.selectedIndex]
            )
        }

        root.appsModel = backendFavoriteApps()

        if (root.appsModel.length <= 0) {
            root.selectedIndex = 0
            return
        }

        var targetIndex = 0

        for (var index = 0;
             index < root.appsModel.length;
             ++index) {
            if (root.appId(root.appsModel[index]) === targetId) {
                targetIndex = index
                break
            }
        }

        root.selectedIndex = Math.max(
            0,
            Math.min(targetIndex, root.appsModel.length - 1)
        )

        Qt.callLater(function() {
            orderList.positionViewAtIndex(
                root.selectedIndex,
                ListView.Contain
            )
        })
    }

    function findRequestedIndex() {
        var targetId = root.appId(root.requestedApp)

        for (var index = 0;
             index < root.appsModel.length;
             ++index) {
            if (root.appId(root.appsModel[index]) === targetId)
                return index
        }

        return 0
    }

    function open(appData) {
        root.requestedApp = appData || null
        root.appsModel = backendFavoriteApps()
        root.selectedIndex = findRequestedIndex()
        root.statusText = "Reorder the app carousel"
        root.visible = true
        root.forceActiveFocus()

        Qt.callLater(function() {
            orderList.positionViewAtIndex(
                root.selectedIndex,
                ListView.Contain
            )
        })
    }

    function close() {
        root.visible = false
        root.closed()
    }

    function moveSelection(delta) {
        var count = root.appsModel.length

        if (count <= 0)
            return

        root.selectedIndex =
            (root.selectedIndex + delta + count) % count

        orderList.positionViewAtIndex(
            root.selectedIndex,
            ListView.Contain
        )
    }

    function moveSelected(delta) {
        if (root.appsModel.length <= 1)
            return

        var app = root.appsModel[root.selectedIndex]
        var targetIndex = Math.max(
            0,
            Math.min(
                root.appsModel.length - 1,
                root.selectedIndex + delta
            )
        )

        if (targetIndex === root.selectedIndex)
            return

        var success = false

        try {
            if (root.appBackend &&
                    typeof root.appBackend.moveFavorite === "function") {
                success = root.appBackend.moveFavorite(
                    root.appId(app),
                    targetIndex
                )
            } else if (root.appBackend &&
                       typeof root.appBackend.moveFavoriteBy === "function") {
                success = root.appBackend.moveFavoriteBy(
                    root.appId(app),
                    delta
                )
            }
        } catch (error) {
            success = false
        }

        if (!success) {
            root.statusText = "Unable to change carousel order"
            return
        }

        root.selectedIndex = targetIndex
        root.statusText =
            root.appName(app) +
            " moved to position " +
            String(targetIndex + 1)

        root.refreshModel(root.appId(app))
        root.orderChanged(root.appId(app), root.selectedIndex)
    }

    function makeFirst() {
        if (root.appsModel.length <= 0)
            return

        var app = root.appsModel[root.selectedIndex]
        var success = false

        try {
            if (root.appBackend &&
                    typeof root.appBackend.makeFavoriteFirst === "function") {
                success = root.appBackend.makeFavoriteFirst(
                    root.appId(app)
                )
            } else if (root.appBackend &&
                       typeof root.appBackend.moveFavorite === "function") {
                success = root.appBackend.moveFavorite(
                    root.appId(app),
                    0
                )
            }
        } catch (error) {
            success = false
        }

        if (!success) {
            root.statusText = "Unable to move app to first position"
            return
        }

        root.selectedIndex = 0
        root.statusText =
            root.appName(app) +
            " is first in the carousel"

        root.refreshModel(root.appId(app))
        root.orderChanged(root.appId(app), 0)
    }

    function handleControllerPressed(action) {
        var value = String(action || "").toLowerCase()

        if (value === "cancel" ||
                value === "o" ||
                value === "back" ||
                value === "l3" ||
                value === "r3") {
            root.close()
            return true
        }

        if (value === "up") {
            root.moveSelection(-1)
            return true
        }

        if (value === "down") {
            root.moveSelection(1)
            return true
        }

        if (value === "left") {
            root.moveSelected(-1)
            return true
        }

        if (value === "right") {
            root.moveSelected(1)
            return true
        }

        if (value === "primary" ||
                value === "x" ||
                value === "confirm") {
            root.makeFirst()
            return true
        }

        return true
    }

    Connections {
        target: root.appBackend
        ignoreUnknownSignals: true

        function onAppsChanged() {
            var currentId = ""

            if (root.appsModel.length > 0 &&
                    root.selectedIndex >= 0 &&
                    root.selectedIndex < root.appsModel.length) {
                currentId = root.appId(
                    root.appsModel[root.selectedIndex]
                )
            }

            root.refreshModel(currentId)
        }
    }
}
