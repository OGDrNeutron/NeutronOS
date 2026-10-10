#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QSocketNotifier>
#include <QFileSystemWatcher>
#include <QVector>
#include <QHash>
#include <QSet>
#include <QDateTime>
#include <QProcess>

class ControllerManager : public QObject
{
    Q_OBJECT

    /*
        ============================================================
                            QML STATE
        ============================================================
    */

    Q_PROPERTY(bool controllerConnected READ controllerConnected NOTIFY controllerConnectedChanged)
    Q_PROPERTY(QString controllerName READ controllerName NOTIFY controllerNameChanged)
    Q_PROPERTY(QString controllerDisplayName READ controllerDisplayName NOTIFY controllerIdentityChanged)
    Q_PROPERTY(QString controllerType READ controllerType NOTIFY controllerIdentityChanged)
    Q_PROPERTY(QString controllerAddress READ controllerAddress NOTIFY controllerIdentityChanged)
    Q_PROPERTY(QString inputSource READ inputSource NOTIFY inputSourceChanged)
    Q_PROPERTY(bool hapticsAvailable READ hapticsAvailable NOTIFY hapticsAvailableChanged)
    Q_PROPERTY(bool lowLatencyInputMode READ lowLatencyInputMode NOTIFY lowLatencyInputModeChanged)
    Q_PROPERTY(int stickDeadZonePercent READ stickDeadZonePercent NOTIFY controllerInputProfileChanged)
    Q_PROPERTY(int triggerThresholdPercent READ triggerThresholdPercent NOTIFY controllerInputProfileChanged)
    Q_PROPERTY(QString inputProfile READ inputProfile NOTIFY controllerInputProfileChanged)

    /*
        Persisted controller-output preferences.
        Light capability is discovered from the Linux LED class and settings
        are cached per verified Bluetooth MAC address.
    */
    Q_PROPERTY(bool controllerLightAvailable READ controllerLightAvailable NOTIFY controllerCapabilitiesChanged)
    Q_PROPERTY(QString controllerLightBackend READ controllerLightBackend NOTIFY controllerCapabilitiesChanged)
    Q_PROPERTY(QString controllerLightColor READ controllerLightColor NOTIFY controllerPreferencesChanged)
    Q_PROPERTY(bool controllerLightEnabled READ controllerLightEnabled NOTIFY controllerPreferencesChanged)
    Q_PROPERTY(QString controllerVibrationLevel READ controllerVibrationLevel NOTIFY controllerPreferencesChanged)
    Q_PROPERTY(QString controllerVibrationPattern READ controllerVibrationPattern NOTIFY controllerPreferencesChanged)
    Q_PROPERTY(bool controllerVibrationEnabled READ controllerVibrationEnabled NOTIFY controllerPreferencesChanged)
    Q_PROPERTY(QString controllerSettingsKey READ controllerSettingsKey NOTIFY controllerIdentityChanged)

    /*
        Boot reconnect policy.  When enabled, NeutronOS attempts to reconnect
        the last verified Bluetooth controller for the first three minutes
        after the shell starts, but only while no controller is connected.
    */
    Q_PROPERTY(bool forceReconnectEnabled READ forceReconnectEnabled NOTIFY forceReconnectChanged)
    Q_PROPERTY(bool forceReconnectActive READ forceReconnectActive NOTIFY forceReconnectChanged)
    Q_PROPERTY(int forceReconnectSecondsRemaining READ forceReconnectSecondsRemaining NOTIFY forceReconnectChanged)
    Q_PROPERTY(QString lastControllerAddress READ lastControllerAddress NOTIFY forceReconnectChanged)

    /*
        Physical device paths for Settings / diagnostics.
    */
    Q_PROPERTY(QString controllerDevicePath READ controllerDevicePath NOTIFY controllerDevicePathChanged)
    Q_PROPERTY(QString motionDevicePath READ motionDevicePath NOTIFY motionDevicePathChanged)
    Q_PROPERTY(QString touchpadDevicePath READ touchpadDevicePath NOTIFY touchpadDevicePathChanged)
    Q_PROPERTY(QString hapticDevicePath READ hapticDevicePath NOTIFY hapticDevicePathChanged)

    /*
        Controller battery.

        Real battery scanner reads:
            /sys/class/power_supply/<device>/capacity
            /sys/class/power_supply/<device>/status
            /sys/class/power_supply/<device>/model_name
            /sys/class/power_supply/<device>/manufacturer
            /sys/class/power_supply/<device>/type

        LoginScreen and console can use:
            controllerBatteryAvailable
            controllerBatteryPercent
            controllerBatteryState
            controllerCharging
    */
    Q_PROPERTY(bool controllerBatteryAvailable READ controllerBatteryAvailable NOTIFY controllerBatteryChanged)
    Q_PROPERTY(int controllerBatteryPercent READ controllerBatteryPercent NOTIFY controllerBatteryChanged)
    Q_PROPERTY(QString controllerBatteryState READ controllerBatteryState NOTIFY controllerBatteryChanged)
    Q_PROPERTY(bool controllerCharging READ controllerCharging NOTIFY controllerBatteryChanged)

    /*
        Debug/status strings for Settings and Controller Status screen.
    */
    Q_PROPERTY(QString controllerBackendStatus READ controllerBackendStatus NOTIFY controllerDebugChanged)
    Q_PROPERTY(QString lastControllerEvent READ lastControllerEvent NOTIFY controllerDebugChanged)

    /*
        PS4 / DualShock motion telemetry.

        IMPORTANT:
        These are visual-only values for QML.
        Motion sensors must never emit:
            up/down/left/right
            buttonPressed()
            actionPressed()
            stickMoved()
            login input
    */
    Q_PROPERTY(bool motionAvailable READ motionAvailable NOTIFY motionAvailableChanged)
    Q_PROPERTY(qreal motionX READ motionX NOTIFY motionChanged)
    Q_PROPERTY(qreal motionY READ motionY NOTIFY motionChanged)
    Q_PROPERTY(qreal motionRoll READ motionRoll NOTIFY motionChanged)
    Q_PROPERTY(qreal motionPitch READ motionPitch NOTIFY motionChanged)

public:
    explicit ControllerManager(QObject *parent = nullptr);
    ~ControllerManager() override;

    bool controllerConnected() const;
    QString controllerName() const;
    QString controllerDisplayName() const;
    QString controllerType() const;
    QString controllerAddress() const;
    QString inputSource() const;
    bool hapticsAvailable() const;
    bool lowLatencyInputMode() const;
    void setStickNavigationActionsEnabled(bool enabled);
    int stickDeadZonePercent() const;
    int triggerThresholdPercent() const;
    QString inputProfile() const;
    bool controllerLightAvailable() const;
    QString controllerLightBackend() const;
    QString controllerLightColor() const;
    bool controllerLightEnabled() const;
    QString controllerVibrationLevel() const;
    QString controllerVibrationPattern() const;
    bool controllerVibrationEnabled() const;
    QString controllerSettingsKey() const;
    bool forceReconnectEnabled() const;
    bool forceReconnectActive() const;
    int forceReconnectSecondsRemaining() const;
    QString lastControllerAddress() const;

    QString controllerDevicePath() const;
    QString motionDevicePath() const;
    QString touchpadDevicePath() const;
    QString hapticDevicePath() const;

    bool controllerBatteryAvailable() const;
    int controllerBatteryPercent() const;
    QString controllerBatteryState() const;
    bool controllerCharging() const;

    QString controllerBackendStatus() const;
    QString lastControllerEvent() const;

    bool motionAvailable() const;
    qreal motionX() const;
    qreal motionY() const;
    qreal motionRoll() const;
    qreal motionPitch() const;

    /*
        Manual refresh hooks for Settings / controller troubleshooting.
    */
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void refreshBattery();
    Q_INVOKABLE void refreshControllerIdentity();
    Q_INVOKABLE void refreshControllerCapabilities();

    /*
        Controller output configuration.

        - Light output uses the Linux multicolor LED class when the active
          controller exposes an RGB lightbar.
        - Vibration level scales all normal NeutronOS haptic feedback.
        - Preferences persist per verified controller MAC address.
    */
    Q_INVOKABLE bool setControllerLightColor(const QString &color);
    Q_INVOKABLE bool setLightColor(const QString &color);
    Q_INVOKABLE bool setLedColor(const QString &color);
    Q_INVOKABLE bool previewControllerLightColor(const QString &color);
    Q_INVOKABLE bool restoreControllerLightColor();
    Q_INVOKABLE bool setControllerLightEnabled(bool enabled);
    Q_INVOKABLE bool setControllerVibrationLevel(const QString &level);
    Q_INVOKABLE bool setControllerVibrationPattern(const QString &pattern);
    Q_INVOKABLE bool setControllerVibrationEnabled(bool enabled);
    Q_INVOKABLE bool saveControllerPreferences(
        const QString &color,
        const QString &vibrationLevel
    );
    Q_INVOKABLE bool saveControllerProfile(
        const QString &color,
        bool lightEnabled,
        const QString &vibrationLevel,
        const QString &vibrationPattern,
        bool vibrationEnabled,
        bool forceReconnectEnabled
    );
    Q_INVOKABLE void previewVibrationLevel(const QString &level);
    Q_INVOKABLE void previewVibrationPattern(
        const QString &pattern,
        const QString &level
    );
    Q_INVOKABLE bool setForceReconnectEnabled(bool enabled);
    Q_INVOKABLE bool forceReconnectNow();

    /*
        Login sequence capture mode:
        - 2 ms precise input polling
        - no per-button force-feedback ioctl work
        - automatically restored when the card disarms
    */
    Q_INVOKABLE void setLowLatencyInputMode(bool enabled);
    Q_INVOKABLE bool setStickDeadZonePercent(int percent);
    Q_INVOKABLE bool setTriggerThresholdPercent(int percent);
    Q_INVOKABLE bool setInputProfile(const QString &profile);
    Q_INVOKABLE bool resetInputTuning();

    /*
        Global Controller Off API.

        Used by:
            qml/Main.qml
            qml/modals/LogoutModal.qml

        Behavior:
            - Releases all held QML actions first so no input sticks.
            - Attempts to disconnect the active Bluetooth controller.
            - Falls back safely if Bluetooth control is unavailable.
            - Returns true only when a backend disconnect command was issued
              successfully.

        Aliases are kept so QML can call whichever name exists:
            controllerManager.controllerOff()
            controllerManager.disconnectController()
            controllerManager.powerOffController()
    */
    Q_INVOKABLE bool controllerOff();
    Q_INVOKABLE bool disconnectController();
    Q_INVOKABLE bool powerOffController();

    /*
        Manual input cleanup for testing / recovery.
        This does not disconnect the device; it only releases held actions.
    */
    Q_INVOKABLE void releaseAllInputs();

    /*
        Haptic feedback API.

        QML usage:
            controllerManager.hapticNavigation()
            controllerManager.hapticConfirm()
            controllerManager.hapticError()
            controllerManager.hapticWarning()
            controllerManager.hapticSuccess()
            controllerManager.hapticPulse(12000, 24000, 80)
    */
    Q_INVOKABLE void hapticPulse(
        int weakMagnitude = 12000,
        int strongMagnitude = 22000,
        int durationMs = 70
    );

    Q_INVOKABLE void hapticNavigation();
    Q_INVOKABLE void hapticConfirm();
    Q_INVOKABLE void hapticError();
    Q_INVOKABLE void hapticWarning();
    Q_INVOKABLE void hapticSuccess();

signals:
    /*
        Backward-compatible signals.

        These emit normalized NeutronOS actions:
            up
            down
            left
            right
            primary
            cancel
            secondary
            context
            system
            home
            quick
            l1
            r1
            l2
            r2
            l3
            r3
    */
    void buttonPressed(const QString &button);
    void buttonReleased(const QString &button);
    void stickMoved(const QString &stick, int x, int y);

    /*
        Preferred signals going forward.
    */
    void actionPressed(const QString &action);
    void actionReleased(const QString &action);

    /*
        Motion sensor signals.
        Visual only. These are for lock screen card tilt.
    */
    void motionChanged();
    void motionAvailableChanged();

    void controllerConnectedChanged();
    void controllerNameChanged();
    void controllerIdentityChanged();
    void inputSourceChanged();
    void hapticsAvailableChanged();
    void lowLatencyInputModeChanged();
    void controllerInputProfileChanged();
    void controllerCapabilitiesChanged();
    void controllerPreferencesChanged();
    void forceReconnectChanged();

    void controllerDevicePathChanged();
    void motionDevicePathChanged();
    void touchpadDevicePathChanged();
    void hapticDevicePathChanged();

    void controllerBatteryChanged();
    void controllerDebugChanged();

private:
    enum class InputDeviceKind
    {
        GamepadInput,
        MotionSensorDevice,
        TouchpadInput,
        IgnoredInput
    };

    struct InputDevice
    {
        QString path;
        QString name;

        int fd = -1;
        QSocketNotifier *notifier = nullptr;

        InputDeviceKind kind = InputDeviceKind::IgnoredInput;

        bool isPlayStation = false;
        bool isGamepad = false;
        bool isMotionSensor = false;
        bool isTouchpad = false;

        QHash<int, QString> buttonMap;
        QHash<int, QString> axisMap;
        QHash<int, int> axisValues;

        /*
            Tracks held actions so buttons/axes do not spam repeated presses.
        */
        QSet<QString> pressedActions;

        /*
            Axis navigation state.
            D-pad and analog navigation emit once, then release on neutral.
        */
        QHash<int, QString> activeAxisActions;

        /*
            Separate stick state from motion state.
            Motion sensor devices must never touch navigation state.
        */
        QHash<QString, int> stickValues;
        QHash<int, int> motionValues;
        bool motionFrameDirty = false;
        bool motionDrainQueued = false;
    };

    struct HapticDevice
    {
        QString path;
        QString name;

        int fd = -1;
        int effectId = -1;
    };

    struct BatteryDevice
    {
        QString path;
        QString name;
        QString modelName;
        QString manufacturer;
        QString type;
        QString scope;

        int capacity = -1;
        QString status = QStringLiteral("Unknown");

        bool valid = false;
        bool likelyController = false;
    };

    /*
        ============================================================
                            TIMERS
        ============================================================
    */

    QTimer m_deviceScanTimer;
    QTimer m_batteryRefreshTimer;
    QTimer m_webReleaseTimer;

    QFileSystemWatcher m_inputDirectoryWatcher;
    QFileSystemWatcher m_webControllerWatcher;

    QTimer m_hapticStopTimer;
    QTimer m_patternTimer;
    QTimer m_forceReconnectTimer;
    QProcess m_forceReconnectProcess;

    /*
        ============================================================
                            DEVICES
        ============================================================
    */

    QVector<InputDevice> m_inputDevices;
    QVector<HapticDevice> m_hapticDevices;

    /*
        Web controller fallback.
        Existing online controller writes here.
    */
    QString m_webControllerFile = QStringLiteral("/run/neutronos/controller.json");
    QString m_lastWebEventKey;

    /*
        Web controller held-state protection.
        Prevents stuck input if the phone/web controller disconnects,
        stops writing the file, or repeats the same press event.
    */
    QSet<QString> m_webHeldActions;
    QSet<QString> m_webHeldDirections;
    QDateTime m_lastWebInputAt;
    int m_webReleaseTimeoutMs = 650;
    bool m_webReadQueued = false;
    bool m_inputRescanQueued = false;

    /*
        Haptic pattern state.
    */
    QVector<int> m_patternWeak;
    QVector<int> m_patternStrong;
    QVector<int> m_patternDurations;
    int m_patternIndex = 0;
    qreal m_patternScale = 1.0;

    /*
        ============================================================
                            PUBLIC STATE
        ============================================================
    */

    bool m_controllerConnected = false;
    bool m_hapticsAvailable = false;
    bool m_lowLatencyInputMode = false;
    bool m_stickNavigationActionsEnabled = true;

    QString m_controllerName = QStringLiteral("None");
    QString m_controllerType = QStringLiteral("Controller");
    QString m_controllerAddress;
    QString m_controllerIdentityCachePath;
    QString m_controllerSettingsPath;
    QString m_inputSource = QStringLiteral("none");

    bool m_controllerLightAvailable = false;
    QString m_controllerLightBackend = QStringLiteral("Unavailable");
    QString m_controllerLightColor = QStringLiteral("#4da6ff");
    bool m_controllerLightEnabled = true;
    QString m_controllerVibrationLevel = QStringLiteral("medium");
    QString m_controllerVibrationPattern = QStringLiteral("soft-pulse");
    bool m_controllerVibrationEnabled = true;
    QString m_controllerLightPath;
    QStringList m_controllerLightChannelPaths;

    bool m_forceReconnectEnabled = false;
    bool m_forceReconnectActive = false;
    QDateTime m_forceReconnectDeadline;
    QString m_lastControllerAddress;

    QString m_controllerDevicePath;
    QString m_motionDevicePath;
    QString m_touchpadDevicePath;
    QString m_hapticDevicePath;

    /*
        Battery state.
    */
    bool m_controllerBatteryAvailable = false;
    int m_controllerBatteryPercent = -1;
    QString m_controllerBatteryState = QStringLiteral("Unknown");
    bool m_controllerCharging = false;
    QString m_controllerBatteryPath;

    /*
        Debug state.
    */
    QString m_controllerBackendStatus = QStringLiteral("Controller backend initializing");
    QString m_lastControllerEvent = QStringLiteral("none");

    /*
        Motion state.
        Range should stay roughly -1.0 to 1.0 for QML.
    */
    bool m_motionAvailable = false;

    qreal m_motionX = 0.0;
    qreal m_motionY = 0.0;
    qreal m_motionRoll = 0.0;
    qreal m_motionPitch = 0.0;

    /*
        Motion tuning.
        These prevent tiny gyro/accelerometer jitter from moving the UI.
    */
    int m_motionDeadzone = 900;
    qreal m_motionScale = 9000.0;

    /*
        Stick tuning.
        Linux sticks are usually around -32768..32767.
        Web sticks are normalized closer to -100..100.
    */
    int m_linuxStickDeadzone = 8000;
    int m_webStickDeadzone = 22;
    int m_stickOutputDeadzone = 12;
    int m_stickMaxValue = 32767;
    int m_stickDeadZonePercent = 12;
    int m_triggerThresholdPercent = 16;
    QString m_inputProfile = QStringLiteral("balanced");

    /*
        ============================================================
                            DEVICE DISCOVERY
        ============================================================
    */

    void scanInputDevices();
    bool openInputDevice(const QString &path, InputDeviceKind kind);
    void closeInputDevices();
    void drainInputDevice(const QString &path);
    void scheduleMotionDeviceDrain(const QString &path);
    void queueInputDeviceScan();
    void updateAdaptiveTimers();

    void pollWebControllerFile();
    void scheduleWebControllerRead();

    /*
        Linux input helpers.
    */
    QString readDeviceName(int fd) const;
    QString readDeviceNameForPath(const QString &path) const;

    bool isGamepadName(const QString &name) const;
    bool isPlayStationName(const QString &name) const;
    bool isMotionSensorName(const QString &name) const;
    bool isTouchpadName(const QString &name) const;

    InputDeviceKind classifyInputDeviceName(const QString &name) const;

    void configureMappings(InputDevice &device);
    void updateConnectionState();

    /*
        ============================================================
                            CONTROLLER OFF / BLUETOOTH
        ============================================================
    */

    bool tryDisconnectBluetoothController(const QString &reason);
    QStringList bluetoothControllerAddressCandidates() const;
    QStringList bluetoothControllerAddressCandidatesFromSysfs() const;
    QStringList bluetoothControllerAddressCandidatesFromBluetoothCtl() const;
    bool runBluetoothCtl(
        const QStringList &arguments,
        QString *standardOutput = nullptr,
        QString *standardError = nullptr
    ) const;
    void startForceReconnectWindow();
    void stopForceReconnectWindow();
    void attemptForceReconnect();

    /*
        Verified controller identity. The controller type is detected from the
        live BlueZ name/modalias and cached per Bluetooth MAC address.
    */
    QString classifyControllerType(
        const QString &identityText,
        const QString &modalias
    ) const;
    QString cachedControllerType(const QString &address) const;
    void cacheControllerType(
        const QString &address,
        const QString &type,
        const QString &verifiedName
    ) const;
    QString extractBluetoothAddress(const QString &text) const;
    QString controllerHardwareIdentityFromSysfs() const;
    void setControllerIdentity(
        const QString &address,
        const QString &type
    );

    /*
        ============================================================
                    CONTROLLER OUTPUT / PREFERENCES
        ============================================================
    */

    void scanControllerLightDevices();
    bool applyControllerLightColor(const QString &color);
    bool applyMulticolorLight(const QString &path, int red, int green, int blue);
    bool applySeparateRgbLight(const QStringList &paths, int red, int green, int blue);
    bool writeTextFile(const QString &path, const QString &value) const;
    QString normalizeLightColor(const QString &color) const;
    QString normalizeVibrationLevel(const QString &level) const;
    QString normalizeVibrationPattern(const QString &pattern) const;
    bool parseLightColor(const QString &color, int *red, int *green, int *blue) const;
    qreal vibrationScale() const;
    QString activeControllerSettingsKey() const;
    void loadControllerPreferences();
    void loadGlobalControllerPreferences();
    bool persistControllerPreferences() const;
    bool persistGlobalControllerPreferences() const;
    void rememberLastControllerAddress(const QString &address);
    void setControllerLightCapability(
        bool available,
        const QString &backend,
        const QString &path,
        const QStringList &channelPaths = QStringList()
    );

    /*
        ============================================================
                            BATTERY
        ============================================================
    */

    void scanControllerBattery();
    BatteryDevice readBatteryDevice(const QString &path) const;
    bool isControllerBatteryDevice(const BatteryDevice &device) const;
    int controllerBatteryScore(const BatteryDevice &device) const;
    QString normalizeBatteryStatus(const QString &status) const;
    QString readTextFile(const QString &path) const;

    void setBatteryUnavailable();
    void setBatteryValues(
        bool available,
        int percent,
        const QString &state,
        bool charging,
        const QString &path
    );

    /*
        ============================================================
                            EVENT HANDLING
        ============================================================
    */

    void handleButtonEvent(InputDevice &device, int code, bool pressed);
    void handleAxisEvent(InputDevice &device, int code, int value);

    /*
        Motion sensor handler.
        This must remain telemetry only.
        It must never emit button/action/stick/navigation signals.
    */
    void handleMotionSensorEvent(InputDevice &device, int code, int value);
    void flushMotionSensorFrame(InputDevice &device);

    /*
        Normalization.
    */
    QString normalizeButton(const QString &button) const;
    QString normalizeAxisDirection(const QString &axis, int value) const;

    int normalizeStickValue(int value) const;

    /*
        Motion helpers.
    */
    qreal normalizeMotionValue(int value) const;
    void setMotionAvailable(bool available);
    void setMotionValues(qreal x, qreal y, qreal roll, qreal pitch);
    void resetMotionValues();

    /*
        Emission helpers.
    */
    void emitActionPressed(const QString &action, const QString &source);
    void emitActionReleased(const QString &action, const QString &source);
    void emitStickMove(const QString &stick, int x, int y, const QString &source);

    void releaseAllPressedForDevice(InputDevice &device, const QString &reason);
    void releaseWebHeldInputs();
    void releaseAllPressedInputs(const QString &reason);
    bool webControllerStale() const;

    /*
        ============================================================
                            STATE SETTERS
        ============================================================
    */

    void setControllerConnected(bool connected);
    void setControllerName(const QString &name);
    void setInputSource(const QString &source);
    void setHapticsAvailable(bool available);

    void setControllerDevicePath(const QString &path);
    void setMotionDevicePath(const QString &path);
    void setTouchpadDevicePath(const QString &path);
    void setHapticDevicePath(const QString &path);

    void setControllerBackendStatus(const QString &status);
    void setLastControllerEvent(const QString &eventText);

    /*
        ============================================================
                            HAPTICS
        ============================================================
    */

    void scanHapticDevices();
    bool openHapticDevice(const QString &path);
    void closeHapticDevices();

    void startRumble(int weakMagnitude, int strongMagnitude, int durationMs);
    void startRumbleRaw(int weakMagnitude, int strongMagnitude, int durationMs);
    void stopRumble();

    void startPattern(
        const QVector<int> &weak,
        const QVector<int> &strong,
        const QVector<int> &durations,
        qreal scale = -1.0
    );
    void playConfiguredVibrationPattern(
        const QString &pattern,
        const QString &level
    );

    void playNextPatternStep();
};
