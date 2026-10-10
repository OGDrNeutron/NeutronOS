import QtQuick 2.15
import QtTest 1.15

TestCase {
    name: "OptionalCodexPackage"
    when: windowShown
    width: 1920
    height: 1080

    function test_installed_component_constructs() {
        var component = Qt.createComponent("../../qml/apps/codex/Main.qml")
        if (component.status === Component.Error &&
                String(component.errorString()).indexOf("No such file") >= 0)
            skip("optional Codex package is not installed")
        compare(component.status, Component.Ready, component.errorString())
        var object = component.createObject(this, { width: 1920, height: 1080 })
        verify(object !== null, component.errorString())
        compare(object.appId, "codex")
        compare(object.backend.appVersion, "1.0.0-alpha.1")
        object.destroy()
    }
}
