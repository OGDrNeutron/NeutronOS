import QtQuick
import QtTest
import "../../qml" as Shell

TestCase {
    name: "ConsoleLoad"
    when: windowShown
    width: 960
    height: 540

    Shell.Console {
        id: consoleSurface
        anchors.fill: parent
        shellActive: false
    }

    function test_consoleInstantiated() {
        verify(consoleSurface !== null)
        compare(consoleSurface.shellActive, false)
    }
}
