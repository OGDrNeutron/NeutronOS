pragma Singleton
import QtQuick
QtObject {
    property int authenticatedClientCount: 0
    property bool running: false
    property bool pairingPanelVisible: false
    property bool pairingCodeActive: false
    property string pairingCode: ""
    property int pairingSecondsRemaining: 0
    property string status: ""
    property string url: ""
    function setKeyboardActive(value) {}
    function hidePairingPanel() {}
    function showPairingPanel() {}
    function generatePairingCode() {}
}
