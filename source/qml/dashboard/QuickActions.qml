import QtQuick 2.15

Item {
    id: root

    property int selectedAction: 0
    property int armedAction: -1
    property bool customizationArmed: false
    property bool sectionFocused: false
    property bool animationsEnabled: visible && enabled

    readonly property real slotWidth: 78
    readonly property real slotHeight: 88
    readonly property real slotSpacing: 14
    readonly property real horizontalPadding: 18
    readonly property real preferredDockWidth:
        Math.max(
            108,
            horizontalPadding * 2 +
            actionCount() * slotWidth +
            Math.max(0, actionCount() - 1) * slotSpacing
        )

    readonly property var backend:
        (typeof quickActionManager !== "undefined" && quickActionManager)
        ? quickActionManager
        : null

    /* Direct property binding keeps the model reactive to dockActionsChanged. */
    readonly property var dockModel: {
        if (!backend)
            return []
        try {
            return backend.dockActions || []
        } catch (error) {
            return []
        }
    }

    signal actionRequested(var actionData, int index)
    signal customizationRequested(int selectedSlot)

    function actionList() {
        return dockModel || []
    }

    function actionCount() {
        return actionList().length
    }

    function actionAt(index) {
        var list = actionList()
        if (index < 0 || index >= list.length)
            return null
        return list[index]
    }

    function clampSelection() {
        var count = actionCount()
        if (count <= 0) {
            selectedAction = 0
            armedAction = -1
            return
        }
        selectedAction = Math.max(0, Math.min(count - 1, selectedAction))
        if (armedAction >= count)
            armedAction = -1
        Qt.callLater(ensureSelectedVisible)
    }

    function ensureSelectedVisible() {
        if (!dockList || dockList.count <= 0)
            return
        var index = Math.max(0, Math.min(dockList.count - 1, selectedAction))
        dockList.positionViewAtIndex(index, ListView.Contain)
    }

    function moveSelection(delta) {
        var count = actionCount()
        if (count <= 0)
            return false
        selectedAction = (selectedAction + delta + count) % count
        armedAction = -1
        ensureSelectedVisible()
        return true
    }

    function activateSelected() {
        var data = actionAt(selectedAction)
        if (!data)
            return false
        actionRequested(data, selectedAction)
        return true
    }

    function openCustomization() {
        customizationArmed = true
        customizationRequested(selectedAction)
        return true
    }

    function disarm() {
        armedAction = -1
        customizationArmed = false
    }

    function clean(value) {
        if (value === undefined || value === null)
            return ""
        return String(value).trim()
    }

    function absoluteSource(value) {
        var text = clean(value).toLowerCase()
        return text.indexOf("file:") === 0 || text.indexOf("qrc:") === 0 ||
               text.indexOf("http://") === 0 || text.indexOf("https://") === 0 ||
               text.indexOf("image://") === 0
    }

    function themeFile(path) {
        try {
            if (typeof assetManager !== "undefined" && assetManager &&
                    typeof assetManager.themeFile === "function")
                return assetManager.themeFile(path)
        } catch (error) {
        }
        return "../../themes/Default/" + path
    }

    function iconSource(data) {
        if (!data)
            return ""
        var raw = clean(data.icon || data.iconPath || data.id || "atom").replace(/\\/g, "/")
        if (absoluteSource(raw))
            return raw
        if (raw.indexOf("apps/") === 0)
            return themeFile(raw)
        if (raw.indexOf("icons/") === 0)
            return themeFile("apps/" + raw)
        if (raw.indexOf("/") >= 0)
            return raw
        if (!/\.(png|jpg|jpeg|webp|svg)$/i.test(raw))
            raw += ".png"
        return themeFile("apps/icons/" + raw)
    }

    ListView {
        id: dockList

        anchors.fill: parent
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        orientation: ListView.Horizontal
        spacing: root.slotSpacing
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        model: root.dockModel
        currentIndex: root.actionCount() > 0
                      ? Math.max(0, Math.min(root.actionCount() - 1, root.selectedAction))
                      : -1
        highlightFollowsCurrentItem: true
        highlightMoveDuration: root.animationsEnabled ? 170 : 0
        preferredHighlightBegin: Math.max(0, width / 2 - root.slotWidth / 2)
        preferredHighlightEnd: preferredHighlightBegin + root.slotWidth
        highlightRangeMode: ListView.ApplyRange

        delegate: Item {
            id: slot
            required property int index
            required property var modelData
            property var actionData: modelData
            readonly property bool visuallySelected:
                ListView.isCurrentItem && root.sectionFocused

            width: root.slotWidth
            height: root.slotHeight
            scale: slot.visuallySelected ? 1.12 : 1.0
            z: slot.visuallySelected ? 20 : 1

            Behavior on scale {
                enabled: root.animationsEnabled
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: iconCard
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72
                height: 72
                radius: 18
                color: root.customizationArmed
                       ? "#361016"
                       : slot.visuallySelected
                         ? "#102D47"
                         : "#0A1727"
                border.width: slot.visuallySelected ? 2 : 1
                border.color: root.customizationArmed
                              ? "#FF3040"
                              : slot.visuallySelected
                                ? "#7DF9FF"
                                : "#496A8A"
                clip: true

                Image {
                    id: actionIcon
                    anchors.fill: parent
                    anchors.margins: 6
                    source: root.iconSource(slot.actionData)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                    sourceSize.width: 192
                    opacity: status === Image.Ready ? 1.0 : 0.0
                }

                Image {
                    anchors.centerIn: parent
                    width: 38
                    height: 38
                    source: root.themeFile("atom.png")
                    fillMode: Image.PreserveAspectFit
                    visible: actionIcon.status !== Image.Ready
                    opacity: 0.68
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.height * 0.42
                    color: "#FFFFFF"
                    opacity: 0.10
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: "#55FFFFFF"
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: slot.visuallySelected ? 26 : 7
                height: 5
                radius: 3
                color: root.customizationArmed
                       ? "#FF3040"
                       : slot.visuallySelected
                         ? "#7DF9FF"
                         : "#52708C"
                opacity: root.sectionFocused ? 1.0 : 0.55

                Behavior on width {
                    enabled: root.animationsEnabled
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.selectedAction = index
                    root.ensureSelectedVisible()
                    root.activateSelected()
                }
            }
        }
    }

    Connections {
        target: root.backend
        enabled: target !== null
        ignoreUnknownSignals: true

        function onDockActionsChanged() {
            root.clampSelection()
        }
    }

    onSelectedActionChanged: ensureSelectedVisible()
    onWidthChanged: Qt.callLater(ensureSelectedVisible)
    Component.onCompleted: clampSelection()
}
