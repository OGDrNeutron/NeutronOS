import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "ReferenceApps"
    when: windowShown
    width: 1920
    height: 1080

    Item { id: host; anchors.fill: parent }

    readonly property var appSources: [
        "../../qml/apps/settings/Main.qml",
        "../../qml/apps/security/Main.qml",
        "../../qml/apps/appstore/Main.qml",
        "../../qml/apps/qbittorrent/Main.qml",
        "../../qml/apps/musicplayer/Main.qml",
        "../../qml/apps/filemanager/Main.qml",
        "../../qml/apps/gallery/Main.qml",
        "../../qml/apps/games/Main.qml",
        "../../qml/apps/terminal/Main.qml"
    ]

    function instantiate(relativeSource, widthValue, heightValue) {
        var startedAt = Date.now()
        var component = Qt.createComponent(Qt.resolvedUrl(relativeSource))
        tryCompare(component, "status", Component.Ready, 4000,
                   relativeSource + ": " + component.errorString())
        var instance = component.createObject(host, {
            width: widthValue,
            height: heightValue,
            visible: false
        })
        verify(instance !== null, relativeSource + ": " + component.errorString())
        if ("hostActive" in instance) instance.hostActive = false
        wait(1)
        console.log("APP_LOAD_TIMING", relativeSource,
                    widthValue + "x" + heightValue,
                    (Date.now() - startedAt) + "ms")
        instance.destroy()
    }

    function test_1080pConstruction() {
        for (var i = 0; i < appSources.length; ++i)
            instantiate(appSources[i], 1920, 1080)
    }

    function test_4kConstruction() {
        for (var i = 0; i < appSources.length; ++i)
            instantiate(appSources[i], 3840, 2160)
    }
}
