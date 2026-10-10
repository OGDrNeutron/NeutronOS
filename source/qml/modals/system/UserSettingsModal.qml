import QtQuick 2.15

/*
    Compatibility alias.

    The production Console route uses UserProfileSettingsModal.qml. Keeping
    this tiny wrapper preserves older app/plugin references without retaining
    a second byte-for-byte copy of the full settings panel.
*/
UserProfileSettingsModal {
}
