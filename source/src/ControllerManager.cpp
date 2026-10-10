#include "ControllerManager.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QSaveFile>
#include <QRegularExpression>
#include <QStringList>
#include <QVariant>
#include <QDateTime>
#include <QSocketNotifier>
#include <QFileSystemWatcher>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <cerrno>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace {

constexpr int DEVICE_SCAN_CONNECTED_MS = 60000;
constexpr int DEVICE_SCAN_DISCONNECTED_MS = 5000;
constexpr int BATTERY_REFRESH_CONNECTED_MS = 60000;
constexpr int BATTERY_REFRESH_DISCONNECTED_MS = 30000;
constexpr int MOTION_DRAIN_MS = 33;
constexpr int INPUT_RESCAN_DEBOUNCE_MS = 120;
constexpr int STICK_EMIT_DELTA = 2;

bool testBit(int bit, const unsigned long *array)
{
    return (array[bit / (8 * sizeof(unsigned long))] >> (bit % (8 * sizeof(unsigned long)))) & 1UL;
}

int clampMagnitude(int value)
{
    return std::max(0, std::min(65535, value));
}

int clampPercent(int value)
{
    return std::max(0, std::min(100, value));
}

QString cleanDeviceName(const char *name)
{
    return QString::fromLocal8Bit(name).trimmed();
}

qreal clampUnit(qreal value)
{
    if (value < -1.0)
        return -1.0;

    if (value > 1.0)
        return 1.0;

    return value;
}

} // namespace

ControllerManager::ControllerManager(QObject *parent)
    : QObject(parent)
{
    connect(
        &m_deviceScanTimer,
        &QTimer::timeout,
        this,
        &ControllerManager::scanInputDevices
    );

    connect(
        &m_batteryRefreshTimer,
        &QTimer::timeout,
        this,
        &ControllerManager::scanControllerBattery
    );

    connect(
        &m_inputDirectoryWatcher,
        &QFileSystemWatcher::directoryChanged,
        this,
        [this](const QString &) { queueInputDeviceScan(); }
    );

    connect(
        &m_webControllerWatcher,
        &QFileSystemWatcher::fileChanged,
        this,
        [this](const QString &) { scheduleWebControllerRead(); }
    );

    connect(
        &m_webControllerWatcher,
        &QFileSystemWatcher::directoryChanged,
        this,
        [this](const QString &) { scheduleWebControllerRead(); }
    );

    connect(
        &m_webReleaseTimer,
        &QTimer::timeout,
        this,
        &ControllerManager::releaseWebHeldInputs
    );

    connect(
        &m_hapticStopTimer,
        &QTimer::timeout,
        this,
        &ControllerManager::stopRumble
    );

    connect(
        &m_patternTimer,
        &QTimer::timeout,
        this,
        &ControllerManager::playNextPatternStep
    );

    connect(
        &m_forceReconnectTimer,
        &QTimer::timeout,
        this,
        &ControllerManager::attemptForceReconnect
    );

    connect(
        &m_forceReconnectProcess,
        QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
        this,
        [this](int exitCode, QProcess::ExitStatus exitStatus) {
            const bool success =
                exitStatus == QProcess::NormalExit && exitCode == 0;

            const QString output = QString::fromLocal8Bit(
                m_forceReconnectProcess.readAllStandardOutput()
            ).trimmed();
            const QString error = QString::fromLocal8Bit(
                m_forceReconnectProcess.readAllStandardError()
            ).trimmed();

            if (success) {
                setControllerBackendStatus(
                    QStringLiteral("Bluetooth reconnect command completed")
                );
            } else {
                setLastControllerEvent(
                    QStringLiteral("Bluetooth reconnect attempt failed: ") +
                    (error.isEmpty() ? output : error)
                );
            }
        }
    );

    m_hapticStopTimer.setSingleShot(true);
    m_patternTimer.setSingleShot(true);
    m_webReleaseTimer.setSingleShot(true);
    m_forceReconnectTimer.setInterval(8000);

    m_deviceScanTimer.setTimerType(Qt::VeryCoarseTimer);
    m_batteryRefreshTimer.setTimerType(Qt::VeryCoarseTimer);
    m_webReleaseTimer.setTimerType(Qt::CoarseTimer);

    const QString inputDirectory = QStringLiteral("/dev/input");
    if (QFileInfo::exists(inputDirectory))
        m_inputDirectoryWatcher.addPath(inputDirectory);

    const QString webDirectory = QFileInfo(m_webControllerFile).absolutePath();
    if (QFileInfo::exists(webDirectory))
        m_webControllerWatcher.addPath(webDirectory);
    if (QFileInfo::exists(m_webControllerFile))
        m_webControllerWatcher.addPath(m_webControllerFile);

    const QString stateDirectory = qEnvironmentVariable(
        "NEUTRONOS_STATE_DIR",
        "/var/lib/neutronos"
    );

    QDir().mkpath(stateDirectory);
    m_controllerIdentityCachePath = QDir(stateDirectory).filePath(
        QStringLiteral("controller_identity_cache.json")
    );
    m_controllerSettingsPath = QDir(stateDirectory).filePath(
        QStringLiteral("controller_settings.json")
    );

    loadGlobalControllerPreferences();

    setControllerBackendStatus(QStringLiteral("Controller backend starting"));

    // Input must be available at Login, but haptics and battery discovery do
    // not need to block the first frame.
    scanInputDevices();
    QTimer::singleShot(900, this, [this]() {
        scanHapticDevices();
        scanControllerBattery();
    });

    updateAdaptiveTimers();

    if (!m_controllerConnected && QFileInfo::exists(m_webControllerFile))
        scheduleWebControllerRead();

    if (m_forceReconnectEnabled && !m_controllerConnected) {
        QTimer::singleShot(1200, this, [this]() {
            if (m_forceReconnectEnabled && !m_controllerConnected)
                startForceReconnectWindow();
        });
    }
}

ControllerManager::~ControllerManager()
{
    stopRumble();
    closeInputDevices();
    closeHapticDevices();
}

/*
    ============================================================
                            GETTERS
    ============================================================
*/

bool ControllerManager::controllerConnected() const
{
    return m_controllerConnected;
}

QString ControllerManager::controllerName() const
{
    return m_controllerName;
}

QString ControllerManager::controllerDisplayName() const
{
    const QString identity = (m_controllerType + QLatin1Char(' ') + m_controllerName).toLower();
    if (identity.contains(QStringLiteral("dualsense")) || identity.contains(QStringLiteral("054c:0ce6")))
        return QStringLiteral("DualSense");
    if (identity.contains(QStringLiteral("dualshock")) || identity.contains(QStringLiteral("054c:05c4")) ||
            identity.contains(QStringLiteral("054c:09cc")) ||
            (identity.contains(QStringLiteral("playstation")) && identity.contains(QStringLiteral("wireless controller"))))
        return QStringLiteral("DualShock 4");
    if (identity.contains(QStringLiteral("xbox")) || identity.contains(QStringLiteral("xinput")) || identity.contains(QStringLiteral("microsoft")))
        return QStringLiteral("Xbox Wireless Controller");
    if (identity.contains(QStringLiteral("switch pro")) || identity.contains(QStringLiteral("nintendo")) || identity.contains(QStringLiteral("057e:2009")))
        return QStringLiteral("Switch Pro Controller");
    const QString name = m_controllerName.trimmed();
    if (!name.isEmpty() && name.compare(QStringLiteral("none"), Qt::CaseInsensitive) != 0 &&
            name.compare(QStringLiteral("wireless controller"), Qt::CaseInsensitive) != 0)
        return name;
    return QStringLiteral("Controller");
}

QString ControllerManager::controllerType() const
{
    return m_controllerType;
}

QString ControllerManager::controllerAddress() const
{
    return m_controllerAddress;
}

QString ControllerManager::inputSource() const
{
    return m_inputSource;
}

bool ControllerManager::hapticsAvailable() const
{
    return m_hapticsAvailable;
}

bool ControllerManager::lowLatencyInputMode() const
{
    return m_lowLatencyInputMode;
}

void ControllerManager::setStickNavigationActionsEnabled(bool enabled)
{
    m_stickNavigationActionsEnabled = enabled;
}

int ControllerManager::stickDeadZonePercent() const
{
    return m_stickDeadZonePercent;
}

int ControllerManager::triggerThresholdPercent() const
{
    return m_triggerThresholdPercent;
}

QString ControllerManager::inputProfile() const
{
    return m_inputProfile;
}

bool ControllerManager::controllerLightAvailable() const
{
    return m_controllerLightAvailable;
}

QString ControllerManager::controllerLightBackend() const
{
    return m_controllerLightBackend;
}

QString ControllerManager::controllerLightColor() const
{
    return m_controllerLightColor;
}

bool ControllerManager::controllerLightEnabled() const
{
    return m_controllerLightEnabled;
}

QString ControllerManager::controllerVibrationLevel() const
{
    return m_controllerVibrationLevel;
}

QString ControllerManager::controllerVibrationPattern() const
{
    return m_controllerVibrationPattern;
}

bool ControllerManager::controllerVibrationEnabled() const
{
    return m_controllerVibrationEnabled;
}

QString ControllerManager::controllerSettingsKey() const
{
    return activeControllerSettingsKey();
}

bool ControllerManager::forceReconnectEnabled() const
{
    return m_forceReconnectEnabled;
}

bool ControllerManager::forceReconnectActive() const
{
    return m_forceReconnectActive;
}

int ControllerManager::forceReconnectSecondsRemaining() const
{
    if (!m_forceReconnectActive || !m_forceReconnectDeadline.isValid())
        return 0;

    const qint64 remaining =
        QDateTime::currentDateTimeUtc().secsTo(m_forceReconnectDeadline);

    return static_cast<int>(std::max<qint64>(0, std::min<qint64>(180, remaining)));
}

QString ControllerManager::lastControllerAddress() const
{
    return m_lastControllerAddress;
}

void ControllerManager::setLowLatencyInputMode(bool enabled)
{
    if (m_lowLatencyInputMode == enabled)
        return;

    m_lowLatencyInputMode = enabled;

    /*
        Physical input is delivered by QSocketNotifier as soon as the evdev
        descriptor becomes readable. Login mode therefore no longer needs a
        2 ms wake-up timer; it only suppresses incidental haptic work.
    */
    if (enabled)
        stopRumble();

    emit lowLatencyInputModeChanged();
}

bool ControllerManager::setStickDeadZonePercent(int percent)
{
    const int value = std::max(0, std::min(35, percent));
    if (m_stickDeadZonePercent == value)
        return persistControllerPreferences();
    releaseAllPressedInputs(QStringLiteral("controller dead zone changed"));
    m_stickDeadZonePercent = value;
    m_linuxStickDeadzone = static_cast<int>(32767.0 * value / 100.0);
    m_webStickDeadzone = value;
    m_stickOutputDeadzone = value;
    m_inputProfile = QStringLiteral("custom");
    emit controllerInputProfileChanged();
    return persistControllerPreferences();
}

bool ControllerManager::setTriggerThresholdPercent(int percent)
{
    const int value = std::max(1, std::min(80, percent));
    if (m_triggerThresholdPercent == value)
        return persistControllerPreferences();
    releaseAllPressedInputs(QStringLiteral("controller trigger threshold changed"));
    m_triggerThresholdPercent = value;
    m_inputProfile = QStringLiteral("custom");
    emit controllerInputProfileChanged();
    return persistControllerPreferences();
}

bool ControllerManager::setInputProfile(const QString &profile)
{
    const QString value = profile.trimmed().toLower();
    int deadZone = 12;
    int trigger = 16;
    QString normalized = value;
    if (value == QStringLiteral("precision")) { deadZone = 7; trigger = 10; }
    else if (value == QStringLiteral("relaxed")) { deadZone = 20; trigger = 26; }
    else { normalized = QStringLiteral("balanced"); }
    releaseAllPressedInputs(QStringLiteral("controller input profile changed"));
    m_inputProfile = normalized;
    m_stickDeadZonePercent = deadZone;
    m_triggerThresholdPercent = trigger;
    m_linuxStickDeadzone = static_cast<int>(32767.0 * deadZone / 100.0);
    m_webStickDeadzone = deadZone;
    m_stickOutputDeadzone = deadZone;
    emit controllerInputProfileChanged();
    return persistControllerPreferences();
}

bool ControllerManager::resetInputTuning()
{
    return setInputProfile(QStringLiteral("balanced"));
}

QString ControllerManager::controllerDevicePath() const
{
    return m_controllerDevicePath;
}

QString ControllerManager::motionDevicePath() const
{
    return m_motionDevicePath;
}

QString ControllerManager::touchpadDevicePath() const
{
    return m_touchpadDevicePath;
}

QString ControllerManager::hapticDevicePath() const
{
    return m_hapticDevicePath;
}

bool ControllerManager::controllerBatteryAvailable() const
{
    return m_controllerBatteryAvailable;
}

int ControllerManager::controllerBatteryPercent() const
{
    return m_controllerBatteryPercent;
}

QString ControllerManager::controllerBatteryState() const
{
    return m_controllerBatteryState;
}

bool ControllerManager::controllerCharging() const
{
    return m_controllerCharging;
}

QString ControllerManager::controllerBackendStatus() const
{
    return m_controllerBackendStatus;
}

QString ControllerManager::lastControllerEvent() const
{
    return m_lastControllerEvent;
}

bool ControllerManager::motionAvailable() const
{
    return m_motionAvailable;
}

qreal ControllerManager::motionX() const
{
    return m_motionX;
}

qreal ControllerManager::motionY() const
{
    return m_motionY;
}

qreal ControllerManager::motionRoll() const
{
    return m_motionRoll;
}

qreal ControllerManager::motionPitch() const
{
    return m_motionPitch;
}

void ControllerManager::refreshDevices()
{
    scanInputDevices();
    scanHapticDevices();
    scanControllerBattery();
    refreshControllerIdentity();
    scanControllerLightDevices();
}

void ControllerManager::refreshBattery()
{
    scanControllerBattery();
}

void ControllerManager::refreshControllerCapabilities()
{
    scanHapticDevices();
    scanControllerLightDevices();
    loadControllerPreferences();

    if (m_controllerLightAvailable)
        restoreControllerLightColor();
}

void ControllerManager::refreshControllerIdentity()
{
    if (!m_controllerConnected) {
        setControllerIdentity(QString(), QStringLiteral("Controller"));
        return;
    }

    QString address;
    const QStringList sysfsCandidates =
        bluetoothControllerAddressCandidatesFromSysfs();

    if (!sysfsCandidates.isEmpty())
        address = sysfsCandidates.constFirst().trimmed().toUpper();

    if (address.isEmpty())
        address = extractBluetoothAddress(m_controllerBatteryPath);

    QString batteryIdentity;

    if (!m_controllerBatteryPath.isEmpty()) {
        batteryIdentity = readTextFile(
            m_controllerBatteryPath + QStringLiteral("/model_name")
        );

        const QString manufacturer = readTextFile(
            m_controllerBatteryPath + QStringLiteral("/manufacturer")
        );

        if (!manufacturer.isEmpty())
            batteryIdentity += QStringLiteral(" ") + manufacturer;
    }

    QStringList identityParts;
    identityParts << m_controllerName
                  << batteryIdentity
                  << controllerHardwareIdentityFromSysfs();

    const QString identityText =
        identityParts.join(QLatin1Char(' ')).trimmed();

    QString type = classifyControllerType(identityText, QString());

    if (!address.isEmpty() &&
            (type == QStringLiteral("Controller") ||
             type == QStringLiteral("PlayStation Controller"))) {
        const QString cached = cachedControllerType(address);

        if (!cached.isEmpty())
            type = cached;
    }

    setControllerIdentity(address, type);

    if (type != QStringLiteral("Controller")) {
        setControllerBackendStatus(
            QStringLiteral("Controller verified: ") + type
        );
    }

    if (!address.isEmpty() &&
            type != QStringLiteral("Controller") &&
            type != QStringLiteral("PlayStation Controller")) {
        cacheControllerType(address, type, m_controllerName);
    }
}

/*
    ============================================================
                    GLOBAL CONTROLLER OFF API
    ============================================================
*/

bool ControllerManager::controllerOff()
{
    releaseAllPressedInputs(QStringLiteral("controller off requested"));
    releaseWebHeldInputs();

    if (m_hapticsAvailable)
        hapticWarning();

    const bool issued = tryDisconnectBluetoothController(QStringLiteral("controllerOff"));

    if (issued) {
        setControllerBackendStatus(QStringLiteral("Controller disconnect command sent"));
        setLastControllerEvent(QStringLiteral("controller off requested"));
    } else {
        setControllerBackendStatus(QStringLiteral("Controller Off unavailable: no Bluetooth controller address found"));
        setLastControllerEvent(QStringLiteral("controller off unavailable"));
    }

    return issued;
}

bool ControllerManager::disconnectController()
{
    return controllerOff();
}

bool ControllerManager::powerOffController()
{
    return controllerOff();
}

void ControllerManager::releaseAllInputs()
{
    releaseAllPressedInputs(QStringLiteral("manual releaseAllInputs"));
    releaseWebHeldInputs();
}

/*
    ============================================================
                        DEVICE DISCOVERY
    ============================================================
*/

void ControllerManager::scanInputDevices()
{
    QDir inputDir(QStringLiteral("/dev/input"));

    if (!inputDir.exists()) {
        closeInputDevices();
        setControllerBackendStatus(QStringLiteral("No /dev/input directory"));
        updateConnectionState();
        return;
    }

    const QFileInfoList eventFiles =
        inputDir.entryInfoList(
            QStringList() << QStringLiteral("event*"),
            QDir::System | QDir::Files
        );

    QSet<QString> existingPaths;

    for (const InputDevice &device : m_inputDevices) {
        if (device.fd >= 0)
            existingPaths.insert(device.path);
    }

    QList<QFileInfo> gamepadEvents;
    QList<QFileInfo> motionEvents;

    QString detectedTouchpadPath = QFileInfo::exists(m_touchpadDevicePath)
        ? m_touchpadDevicePath
        : QString();

    for (const QFileInfo &info : eventFiles) {
        const QString path = info.absoluteFilePath();

        if (existingPaths.contains(path) || path == m_touchpadDevicePath)
            continue;

        const QString name = readDeviceNameForPath(path);
        const InputDeviceKind kind = classifyInputDeviceName(name);

        if (kind == InputDeviceKind::TouchpadInput) {
            if (detectedTouchpadPath.isEmpty())
                detectedTouchpadPath = path;

            continue;
        }

        if (kind == InputDeviceKind::GamepadInput) {
            gamepadEvents.append(info);
        } else if (kind == InputDeviceKind::MotionSensorDevice) {
            motionEvents.append(info);
        }
    }

    setTouchpadDevicePath(detectedTouchpadPath);

    /*
        Open in priority order:
        1. Real gamepad input
        2. Motion sensor telemetry
        Touchpad is intentionally ignored.
    */
    for (const QFileInfo &info : gamepadEvents)
        openInputDevice(info.absoluteFilePath(), InputDeviceKind::GamepadInput);

    for (const QFileInfo &info : motionEvents)
        openInputDevice(info.absoluteFilePath(), InputDeviceKind::MotionSensorDevice);

    /*
        Remove unplugged devices.

        Important:
        If a controller is unplugged while a direction/button is held,
        QML would otherwise never receive the release event. That can leave
        the login screen, carousel, or dock feeling stuck.
    */
    for (int i = m_inputDevices.size() - 1; i >= 0; --i) {
        if (m_inputDevices[i].fd < 0 ||
            !QFileInfo::exists(m_inputDevices[i].path)) {
            releaseAllPressedForDevice(m_inputDevices[i], QStringLiteral("device removed"));

            if (m_inputDevices[i].notifier) {
                m_inputDevices[i].notifier->setEnabled(false);
                m_inputDevices[i].notifier->deleteLater();
                m_inputDevices[i].notifier = nullptr;
            }

            if (m_inputDevices[i].fd >= 0)
                ::close(m_inputDevices[i].fd);

            m_inputDevices.removeAt(i);
        }
    }

    updateConnectionState();
}

bool ControllerManager::openInputDevice(const QString &path, InputDeviceKind kind)
{
    if (kind == InputDeviceKind::TouchpadInput ||
        kind == InputDeviceKind::IgnoredInput) {
        return false;
    }

    const int fd = ::open(path.toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK);

    if (fd < 0)
        return false;

    const QString name = readDeviceName(fd);
    // Gemini session proxy pads belong exclusively to game runtimes. Keep
    // registration, battery and Bluetooth identity on the physical controller.
    if (name.startsWith(QStringLiteral("Gemini P"))) {
        ::close(fd);
        return false;
    }

    const InputDeviceKind realKind = classifyInputDeviceName(name);

    /*
        Trust the actual kernel device name over the scan-time guess.
    */
    if (realKind != kind)
        kind = realKind;

    if (kind == InputDeviceKind::TouchpadInput ||
        kind == InputDeviceKind::IgnoredInput) {
        ::close(fd);
        return false;
    }

    unsigned long evBits[(EV_MAX / (8 * sizeof(unsigned long))) + 1] = {};

    if (::ioctl(fd, EVIOCGBIT(0, sizeof(evBits)), evBits) < 0) {
        ::close(fd);
        return false;
    }

    const bool hasKeys = testBit(EV_KEY, evBits);
    const bool hasAbs = testBit(EV_ABS, evBits);

    if (kind == InputDeviceKind::GamepadInput) {
        if (!hasKeys && !hasAbs) {
            ::close(fd);
            return false;
        }

        if (!isGamepadName(name)) {
            ::close(fd);
            return false;
        }
    }

    if (kind == InputDeviceKind::MotionSensorDevice) {
        if (!hasAbs) {
            ::close(fd);
            return false;
        }
    }

    InputDevice device;
    device.path = path;
    device.name = name.isEmpty() ? path : name;
    device.fd = fd;
    device.kind = kind;

    device.isPlayStation = isPlayStationName(device.name);
    device.isGamepad = kind == InputDeviceKind::GamepadInput;
    device.isMotionSensor = kind == InputDeviceKind::MotionSensorDevice;
    device.isTouchpad = kind == InputDeviceKind::TouchpadInput;

    configureMappings(device);

    m_inputDevices.append(device);

    InputDevice &storedDevice = m_inputDevices.last();
    storedDevice.notifier = new QSocketNotifier(
        storedDevice.fd,
        QSocketNotifier::Read,
        this
    );

    connect(
        storedDevice.notifier,
        &QSocketNotifier::activated,
        this,
        [this, path, kind](QSocketDescriptor, QSocketNotifier::Type) {
            if (kind == InputDeviceKind::MotionSensorDevice)
                scheduleMotionDeviceDrain(path);
            else
                drainInputDevice(path);
        }
    );

    if (storedDevice.kind == InputDeviceKind::GamepadInput)
        setLastControllerEvent(QStringLiteral("Gamepad attached: ") + storedDevice.name + QStringLiteral(" @ ") + storedDevice.path);
    else if (storedDevice.kind == InputDeviceKind::MotionSensorDevice)
        setLastControllerEvent(QStringLiteral("Motion telemetry attached: ") + storedDevice.name + QStringLiteral(" @ ") + storedDevice.path);

    updateConnectionState();

    return true;
}

void ControllerManager::closeInputDevices()
{
    for (InputDevice &device : m_inputDevices) {
        releaseAllPressedForDevice(device, QStringLiteral("closing input devices"));

        if (device.notifier) {
            device.notifier->setEnabled(false);
            delete device.notifier;
            device.notifier = nullptr;
        }

        if (device.fd >= 0)
            ::close(device.fd);

        device.fd = -1;
    }

    m_inputDevices.clear();

    resetMotionValues();
    setMotionAvailable(false);

    setControllerDevicePath(QString());
    setMotionDevicePath(QString());
    setTouchpadDevicePath(QString());

    updateConnectionState();
}

QString ControllerManager::readDeviceName(int fd) const
{
    char name[256];
    std::memset(name, 0, sizeof(name));

    if (::ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0)
        return QString();

    return cleanDeviceName(name);
}

QString ControllerManager::readDeviceNameForPath(const QString &path) const
{
    const int fd = ::open(path.toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK);

    if (fd < 0)
        return QString();

    const QString name = readDeviceName(fd);

    ::close(fd);

    return name;
}

bool ControllerManager::isGamepadName(const QString &name) const
{
    const QString n = name.toLower();

    if (isMotionSensorName(name) || isTouchpadName(name))
        return false;

    return n.contains(QStringLiteral("dualshock")) ||
           n.contains(QStringLiteral("dualsense")) ||
           n.contains(QStringLiteral("wireless controller")) ||
           n.contains(QStringLiteral("playstation")) ||
           n.contains(QStringLiteral("sony")) ||
           n.contains(QStringLiteral("gamepad")) ||
           n.contains(QStringLiteral("joystick")) ||
           n.contains(QStringLiteral("xbox")) ||
           n.contains(QStringLiteral("8bitdo")) ||
           n.contains(QStringLiteral("controller"));
}

bool ControllerManager::isPlayStationName(const QString &name) const
{
    const QString n = name.toLower();

    return n.contains(QStringLiteral("dualshock")) ||
           n.contains(QStringLiteral("dualsense")) ||
           n.contains(QStringLiteral("wireless controller")) ||
           n.contains(QStringLiteral("playstation")) ||
           n.contains(QStringLiteral("sony"));
}

bool ControllerManager::isMotionSensorName(const QString &name) const
{
    const QString n = name.toLower();

    return n.contains(QStringLiteral("motion")) ||
           n.contains(QStringLiteral("sensor")) ||
           n.contains(QStringLiteral("accelerometer")) ||
           n.contains(QStringLiteral("gyro")) ||
           n.contains(QStringLiteral("gyroscope"));
}

bool ControllerManager::isTouchpadName(const QString &name) const
{
    const QString n = name.toLower();

    return n.contains(QStringLiteral("touchpad")) ||
           n.contains(QStringLiteral("mouse"));
}

ControllerManager::InputDeviceKind ControllerManager::classifyInputDeviceName(const QString &name) const
{
    /*
        Order matters.

        PS4 creates:
            Wireless Controller                 -> GamepadInput
            Wireless Controller Motion Sensors  -> MotionSensorDevice
            Wireless Controller Touchpad        -> TouchpadInput
    */

    if (isMotionSensorName(name))
        return InputDeviceKind::MotionSensorDevice;

    if (isTouchpadName(name))
        return InputDeviceKind::TouchpadInput;

    if (isGamepadName(name))
        return InputDeviceKind::GamepadInput;

    return InputDeviceKind::IgnoredInput;
}

void ControllerManager::configureMappings(InputDevice &device)
{
    device.buttonMap.clear();
    device.axisMap.clear();
    device.axisValues.clear();
    device.stickValues.clear();
    device.motionValues.clear();
    device.pressedActions.clear();
    device.activeAxisActions.clear();

    /*
        Motion devices are intentionally NOT mapped to directions.
        event5 motion sensors will never produce up/down/left/right.
    */
    if (device.kind == InputDeviceKind::MotionSensorDevice)
        return;

    if (device.kind != InputDeviceKind::GamepadInput)
        return;

    /*
        PlayStation / standard Linux gamepad layout:
            Cross      BTN_SOUTH
            Circle     BTN_EAST
            Square     BTN_WEST
            Triangle   BTN_NORTH
            Share      BTN_SELECT
            Options    BTN_START
            PS/Home    BTN_MODE
    */

    device.buttonMap[BTN_SOUTH] = QStringLiteral("primary");
    device.buttonMap[BTN_EAST] = QStringLiteral("cancel");
    device.buttonMap[BTN_WEST] = QStringLiteral("secondary");
    device.buttonMap[BTN_NORTH] = QStringLiteral("context");

    device.buttonMap[BTN_SELECT] = QStringLiteral("quick");
    device.buttonMap[BTN_START] = QStringLiteral("system");
    device.buttonMap[BTN_MODE] = QStringLiteral("home");

    device.buttonMap[BTN_TL] = QStringLiteral("l1");
    device.buttonMap[BTN_TR] = QStringLiteral("r1");
    device.buttonMap[BTN_TL2] = QStringLiteral("l2");
    device.buttonMap[BTN_TR2] = QStringLiteral("r2");
    device.buttonMap[BTN_THUMBL] = QStringLiteral("l3");
    device.buttonMap[BTN_THUMBR] = QStringLiteral("r3");

    /*
        D-pad can arrive as buttons on some controllers.
    */
    device.buttonMap[KEY_UP] = QStringLiteral("up");
    device.buttonMap[KEY_DOWN] = QStringLiteral("down");
    device.buttonMap[KEY_LEFT] = QStringLiteral("left");
    device.buttonMap[KEY_RIGHT] = QStringLiteral("right");

    /*
        Axes.
    */
    device.axisMap[ABS_X] = QStringLiteral("left_x");
    device.axisMap[ABS_Y] = QStringLiteral("left_y");
    device.axisMap[ABS_RX] = QStringLiteral("right_x");
    device.axisMap[ABS_RY] = QStringLiteral("right_y");

    device.axisMap[ABS_HAT0X] = QStringLiteral("dpad_x");
    device.axisMap[ABS_HAT0Y] = QStringLiteral("dpad_y");

    device.axisMap[ABS_Z] = QStringLiteral("l2_axis");
    device.axisMap[ABS_RZ] = QStringLiteral("r2_axis");
}

void ControllerManager::updateConnectionState()
{
    bool hasGamepad = false;
    bool hasMotion = false;

    QString bestName;
    QString bestGamepadPath;
    QString bestMotionPath;

    for (const InputDevice &device : m_inputDevices) {
        if (device.kind == InputDeviceKind::GamepadInput) {
            hasGamepad = true;

            if (bestName.isEmpty()) {
                bestName = device.name;
                bestGamepadPath = device.path;
            }

            if (device.isPlayStation) {
                bestName = device.name;
                bestGamepadPath = device.path;
                break;
            }
        }
    }

    for (const InputDevice &device : m_inputDevices) {
        if (device.kind == InputDeviceKind::MotionSensorDevice) {
            hasMotion = true;

            if (bestMotionPath.isEmpty())
                bestMotionPath = device.path;
        }
    }

    setControllerConnected(hasGamepad);
    setMotionAvailable(hasMotion);
    setControllerDevicePath(hasGamepad ? bestGamepadPath : QString());
    setMotionDevicePath(hasMotion ? bestMotionPath : QString());

    if (!hasMotion)
        resetMotionValues();

    if (!hasGamepad) {
        setControllerName(QStringLiteral("None"));
        setInputSource(QStringLiteral("web"));
        setControllerBackendStatus(QStringLiteral("No physical controller detected; web fallback ready"));
        return;
    }

    setControllerName(bestName.isEmpty() ? QStringLiteral("Controller") : bestName);
    setInputSource(QStringLiteral("playstation"));
    setControllerBackendStatus(
        QStringLiteral("Controller ready: ") +
        (bestName.isEmpty() ? QStringLiteral("Controller") : bestName)
    );
}

/*
    ============================================================
                    VERIFIED CONTROLLER IDENTITY
    ============================================================
*/

QString ControllerManager::classifyControllerType(
    const QString &identityText,
    const QString &modalias
) const {
    const QString identity = identityText.trimmed().toLower();
    const QString alias = modalias.trimmed().toLower();
    const QString blob = identity + QStringLiteral(" ") + alias;

    const bool sonyVendor =
        blob.contains(QStringLiteral("v054c")) ||
        blob.contains(QStringLiteral("sony")) ||
        blob.contains(QStringLiteral("playstation"));

    if (blob.contains(QStringLiteral("dualsense edge")) ||
            (sonyVendor && blob.contains(QStringLiteral("0df2")))) {
        return QStringLiteral("DualSense Edge");
    }

    if (blob.contains(QStringLiteral("dualsense")) ||
            (sonyVendor && blob.contains(QStringLiteral("0ce6")))) {
        return QStringLiteral("DualSense");
    }

    if (blob.contains(QStringLiteral("dualshock 4")) ||
            blob.contains(QStringLiteral("dualshock4")) ||
            (sonyVendor &&
             (blob.contains(QStringLiteral("05c4")) ||
              blob.contains(QStringLiteral("09cc")) ||
              blob.contains(QStringLiteral("0ba0"))))) {
        return QStringLiteral("DualShock 4");
    }

    if (blob.contains(QStringLiteral("dualshock 3")) ||
            (sonyVendor && blob.contains(QStringLiteral("0268")))) {
        return QStringLiteral("DualShock 3");
    }

    if (sonyVendor &&
            (blob.contains(QStringLiteral("wireless controller")) ||
             blob.contains(QStringLiteral("controller")))) {
        return QStringLiteral("PlayStation Controller");
    }

    if (blob.contains(QStringLiteral("xbox elite")))
        return QStringLiteral("Xbox Elite Controller");

    if (blob.contains(QStringLiteral("xbox")))
        return QStringLiteral("Xbox Controller");

    if (blob.contains(QStringLiteral("joy-con")))
        return QStringLiteral("Joy-Con");

    if (blob.contains(QStringLiteral("switch pro")) ||
            blob.contains(QStringLiteral("nintendo pro controller")) ||
            blob.contains(QStringLiteral("pro controller"))) {
        return QStringLiteral("Switch Pro Controller");
    }

    if (blob.contains(QStringLiteral("8bitdo")))
        return QStringLiteral("8BitDo Controller");

    if (blob.contains(QStringLiteral("steam controller")))
        return QStringLiteral("Steam Controller");

    return QStringLiteral("Controller");
}

QString ControllerManager::cachedControllerType(const QString &address) const
{
    const QString key = address.trimmed().toUpper();

    if (key.isEmpty() || m_controllerIdentityCachePath.isEmpty())
        return QString();

    QFile file(m_controllerIdentityCachePath);

    if (!file.open(QIODevice::ReadOnly))
        return QString();

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    file.close();

    if (!document.isObject())
        return QString();

    const QJsonObject entry = document.object().value(key).toObject();
    return entry.value(QStringLiteral("type")).toString().trimmed();
}

void ControllerManager::cacheControllerType(
    const QString &address,
    const QString &type,
    const QString &verifiedName
) const {
    const QString key = address.trimmed().toUpper();
    const QString cleanType = type.trimmed();

    if (key.isEmpty() ||
            cleanType.isEmpty() ||
            cleanType == QStringLiteral("Controller") ||
            m_controllerIdentityCachePath.isEmpty()) {
        return;
    }

    QJsonObject root;
    QFile existing(m_controllerIdentityCachePath);

    if (existing.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(existing.readAll());
        existing.close();

        if (document.isObject())
            root = document.object();
    }

    QJsonObject entry;
    entry.insert(QStringLiteral("type"), cleanType);
    entry.insert(QStringLiteral("name"), verifiedName.trimmed());
    entry.insert(
        QStringLiteral("updatedUtc"),
        QDateTime::currentDateTimeUtc().toString(Qt::ISODate)
    );

    root.insert(key, entry);

    QDir().mkpath(QFileInfo(m_controllerIdentityCachePath).absolutePath());

    QSaveFile output(m_controllerIdentityCachePath);

    if (!output.open(QIODevice::WriteOnly))
        return;

    output.write(QJsonDocument(root).toJson(QJsonDocument::Indented));

    if (!output.commit())
        return;

    QFile::setPermissions(
        m_controllerIdentityCachePath,
        QFileDevice::ReadOwner | QFileDevice::WriteOwner
    );
}

QString ControllerManager::extractBluetoothAddress(const QString &text) const
{
    static const QRegularExpression addressRegex(
        QStringLiteral("([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})")
    );

    const QRegularExpressionMatch match = addressRegex.match(text);

    if (!match.hasMatch())
        return QString();

    return match.captured(1).toUpper();
}

QString ControllerManager::controllerHardwareIdentityFromSysfs() const
{
    QStringList roots;

    if (!m_controllerDevicePath.isEmpty()) {
        const QString canonical =
            QFileInfo(m_controllerDevicePath).canonicalFilePath();

        if (!canonical.isEmpty())
            roots.append(canonical);
    }

    if (!m_controllerBatteryPath.isEmpty()) {
        const QString canonical =
            QFileInfo(m_controllerBatteryPath).canonicalFilePath();

        if (!canonical.isEmpty())
            roots.append(canonical);
    }

    QStringList identityParts;
    QSet<QString> visited;

    const QStringList identityFiles = {
        QStringLiteral("modalias"),
        QStringLiteral("uevent"),
        QStringLiteral("manufacturer"),
        QStringLiteral("product"),
        QStringLiteral("name"),
        QStringLiteral("idVendor"),
        QStringLiteral("idProduct")
    };

    for (const QString &root : roots) {
        QString path = root;

        if (QFileInfo(path).isFile())
            path = QFileInfo(path).dir().absolutePath();

        for (int depth = 0; depth < 14 && !path.isEmpty(); ++depth) {
            const QString canonical = QFileInfo(path).canonicalFilePath();
            const QString visitKey = canonical.isEmpty() ? path : canonical;

            if (!visited.contains(visitKey)) {
                visited.insert(visitKey);

                for (const QString &fileName : identityFiles) {
                    const QString value = readTextFile(
                        QDir(path).filePath(fileName)
                    );

                    if (!value.isEmpty())
                        identityParts.append(value);
                }
            }

            const QString nextPath = QFileInfo(path).dir().absolutePath();

            if (nextPath == path || nextPath == QStringLiteral("/"))
                break;

            path = nextPath;
        }
    }

    identityParts.removeDuplicates();
    return identityParts.join(QLatin1Char(' '));
}

void ControllerManager::setControllerIdentity(
    const QString &address,
    const QString &type
) {
    const QString cleanAddress = address.trimmed().toUpper();
    const QString cleanType = type.trimmed().isEmpty()
                              ? QStringLiteral("Controller")
                              : type.trimmed();

    if (m_controllerAddress == cleanAddress &&
            m_controllerType == cleanType) {
        return;
    }

    m_controllerAddress = cleanAddress;
    m_controllerType = cleanType;
    emit controllerIdentityChanged();

    if (!cleanAddress.isEmpty())
        rememberLastControllerAddress(cleanAddress);

    loadControllerPreferences();

    QTimer::singleShot(0, this, [this]() {
        if (m_controllerConnected)
            scanControllerLightDevices();
    });
}

/*
    ============================================================
                CONTROLLER OUTPUT / PREFERENCES
    ============================================================
*/

QString ControllerManager::normalizeLightColor(const QString &color) const
{
    QString value = color.trimmed().toLower();

    if (!value.startsWith(QLatin1Char('#')))
        value.prepend(QLatin1Char('#'));

    static const QRegularExpression pattern(
        QStringLiteral("^#[0-9a-f]{6}$")
    );

    if (!pattern.match(value).hasMatch())
        return QStringLiteral("#4da6ff");

    return value;
}

QString ControllerManager::normalizeVibrationLevel(const QString &level) const
{
    const QString value = level.trimmed().toLower();

    if (value == QStringLiteral("low") ||
            value == QStringLiteral("medium") ||
            value == QStringLiteral("high")) {
        return value;
    }

    return QStringLiteral("medium");
}

QString ControllerManager::normalizeVibrationPattern(const QString &pattern) const
{
    QString value = pattern.trimmed().toLower();
    value.replace(QLatin1Char('_'), QLatin1Char('-'));
    value.replace(QLatin1Char(' '), QLatin1Char('-'));

    const QStringList validPatterns = {
        QStringLiteral("soft-pulse"),
        QStringLiteral("double-tap"),
        QStringLiteral("heartbeat"),
        QStringLiteral("rising-wave"),
        QStringLiteral("heavy-impact")
    };

    if (validPatterns.contains(value))
        return value;

    return QStringLiteral("soft-pulse");
}

bool ControllerManager::parseLightColor(
    const QString &color,
    int *red,
    int *green,
    int *blue
) const {
    const QString value = normalizeLightColor(color);
    bool okRed = false;
    bool okGreen = false;
    bool okBlue = false;

    const int r = value.mid(1, 2).toInt(&okRed, 16);
    const int g = value.mid(3, 2).toInt(&okGreen, 16);
    const int b = value.mid(5, 2).toInt(&okBlue, 16);

    if (!okRed || !okGreen || !okBlue)
        return false;

    if (red)
        *red = r;

    if (green)
        *green = g;

    if (blue)
        *blue = b;

    return true;
}

qreal ControllerManager::vibrationScale() const
{
    if (m_controllerVibrationLevel == QStringLiteral("low"))
        return 0.55;

    if (m_controllerVibrationLevel == QStringLiteral("high"))
        return 1.45;

    return 1.0;
}

QString ControllerManager::activeControllerSettingsKey() const
{
    const QString address = m_controllerAddress.trimmed().toUpper();

    if (!address.isEmpty())
        return address;

    QString fallback = m_controllerName.trimmed().toLower();
    fallback.replace(
        QRegularExpression(QStringLiteral("[^a-z0-9]+")),
        QStringLiteral("-")
    );
    fallback.remove(QRegularExpression(QStringLiteral("^-+|-+$")));

    if (fallback.isEmpty() || fallback == QStringLiteral("none"))
        return QStringLiteral("default");

    return QStringLiteral("wired:") + fallback;
}

void ControllerManager::loadControllerPreferences()
{
    QString color = QStringLiteral("#4da6ff");
    bool lightEnabled = true;
    QString vibration = QStringLiteral("medium");
    QString vibrationPattern = QStringLiteral("soft-pulse");
    bool vibrationEnabled = true;
    int stickDeadZone = 12;
    int triggerThreshold = 16;
    QString inputProfile = QStringLiteral("balanced");

    QFile file(m_controllerSettingsPath);

    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
        file.close();

        if (document.isObject()) {
            const QJsonObject entry = document.object()
                .value(activeControllerSettingsKey())
                .toObject();

            if (!entry.isEmpty()) {
                color = normalizeLightColor(
                    entry.value(QStringLiteral("lightColor")).toString(color)
                );
                lightEnabled = entry.value(
                    QStringLiteral("lightEnabled")
                ).toBool(lightEnabled);
                vibration = normalizeVibrationLevel(
                    entry.value(QStringLiteral("vibrationLevel")).toString(vibration)
                );
                vibrationPattern = normalizeVibrationPattern(
                    entry.value(QStringLiteral("vibrationPattern"))
                        .toString(vibrationPattern)
                );
                vibrationEnabled = entry.value(
                    QStringLiteral("vibrationEnabled")
                ).toBool(vibrationEnabled);
                stickDeadZone = std::max(0, std::min(35, entry.value(
                    QStringLiteral("stickDeadZonePercent")
                ).toInt(stickDeadZone)));
                triggerThreshold = std::max(1, std::min(80, entry.value(
                    QStringLiteral("triggerThresholdPercent")
                ).toInt(triggerThreshold)));
                inputProfile = entry.value(QStringLiteral("inputProfile"))
                    .toString(inputProfile).trimmed().toLower();
            }
        }
    }

    const bool changed =
        m_controllerLightColor != color ||
        m_controllerLightEnabled != lightEnabled ||
        m_controllerVibrationLevel != vibration ||
        m_controllerVibrationPattern != vibrationPattern ||
        m_controllerVibrationEnabled != vibrationEnabled ||
        m_stickDeadZonePercent != stickDeadZone ||
        m_triggerThresholdPercent != triggerThreshold ||
        m_inputProfile != inputProfile;

    m_controllerLightColor = color;
    m_controllerLightEnabled = lightEnabled;
    m_controllerVibrationLevel = vibration;
    m_controllerVibrationPattern = vibrationPattern;
    m_controllerVibrationEnabled = vibrationEnabled;
    m_stickDeadZonePercent = stickDeadZone;
    m_triggerThresholdPercent = triggerThreshold;
    m_inputProfile = inputProfile.isEmpty() ? QStringLiteral("balanced") : inputProfile;
    m_linuxStickDeadzone = static_cast<int>(32767.0 * m_stickDeadZonePercent / 100.0);
    m_webStickDeadzone = m_stickDeadZonePercent;
    m_stickOutputDeadzone = m_stickDeadZonePercent;

    if (changed) {
        emit controllerPreferencesChanged();
        emit controllerInputProfileChanged();
    }
}

void ControllerManager::loadGlobalControllerPreferences()
{
    bool forceReconnect = false;
    QString lastAddress;

    QFile file(m_controllerSettingsPath);

    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
        file.close();

        if (document.isObject()) {
            const QJsonObject root = document.object();
            const QJsonObject global = root
                .value(QStringLiteral("_global"))
                .toObject();

            forceReconnect = global.value(
                QStringLiteral("forceReconnectEnabled")
            ).toBool(false);
            lastAddress = global.value(
                QStringLiteral("lastControllerAddress")
            ).toString().trimmed().toUpper();

            /*
                Patch 09 files did not yet contain the global section.
                Recover the most recently updated MAC-keyed profile so Force
                Reconnect works immediately after upgrading.
            */
            if (lastAddress.isEmpty()) {
                static const QRegularExpression addressPattern(
                    QStringLiteral("^[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}$")
                );

                QDateTime newest;

                for (auto it = root.constBegin(); it != root.constEnd(); ++it) {
                    const QString candidate = it.key().trimmed().toUpper();

                    if (!addressPattern.match(candidate).hasMatch())
                        continue;

                    const QDateTime updated = QDateTime::fromString(
                        it.value().toObject()
                            .value(QStringLiteral("updatedUtc"))
                            .toString(),
                        Qt::ISODate
                    );

                    if (lastAddress.isEmpty() ||
                            (!updated.isValid() ? !newest.isValid() :
                             !newest.isValid() || updated > newest)) {
                        lastAddress = candidate;
                        newest = updated;
                    }
                }
            }
        }
    }

    const bool changed =
        m_forceReconnectEnabled != forceReconnect ||
        m_lastControllerAddress != lastAddress;

    m_forceReconnectEnabled = forceReconnect;
    m_lastControllerAddress = lastAddress;

    if (changed)
        emit forceReconnectChanged();
}

bool ControllerManager::persistControllerPreferences() const
{
    if (m_controllerSettingsPath.isEmpty())
        return false;

    QJsonObject root;
    QFile existing(m_controllerSettingsPath);

    if (existing.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(existing.readAll());
        existing.close();

        if (document.isObject())
            root = document.object();
    }

    QJsonObject entry;
    entry.insert(QStringLiteral("lightColor"), m_controllerLightColor);
    entry.insert(QStringLiteral("lightEnabled"), m_controllerLightEnabled);
    entry.insert(QStringLiteral("vibrationLevel"), m_controllerVibrationLevel);
    entry.insert(QStringLiteral("vibrationPattern"), m_controllerVibrationPattern);
    entry.insert(QStringLiteral("vibrationEnabled"), m_controllerVibrationEnabled);
    entry.insert(QStringLiteral("stickDeadZonePercent"), m_stickDeadZonePercent);
    entry.insert(QStringLiteral("triggerThresholdPercent"), m_triggerThresholdPercent);
    entry.insert(QStringLiteral("inputProfile"), m_inputProfile);
    entry.insert(QStringLiteral("controllerType"), m_controllerType);
    entry.insert(QStringLiteral("controllerName"), m_controllerName);
    entry.insert(
        QStringLiteral("updatedUtc"),
        QDateTime::currentDateTimeUtc().toString(Qt::ISODate)
    );

    root.insert(activeControllerSettingsKey(), entry);

    QJsonObject global = root.value(QStringLiteral("_global")).toObject();
    global.insert(QStringLiteral("forceReconnectEnabled"), m_forceReconnectEnabled);
    global.insert(QStringLiteral("lastControllerAddress"), m_lastControllerAddress);
    global.insert(
        QStringLiteral("updatedUtc"),
        QDateTime::currentDateTimeUtc().toString(Qt::ISODate)
    );
    root.insert(QStringLiteral("_global"), global);

    QDir().mkpath(QFileInfo(m_controllerSettingsPath).absolutePath());

    QSaveFile output(m_controllerSettingsPath);

    if (!output.open(QIODevice::WriteOnly))
        return false;

    if (output.write(QJsonDocument(root).toJson(QJsonDocument::Indented)) < 0)
        return false;

    if (!output.commit())
        return false;

    QFile::setPermissions(
        m_controllerSettingsPath,
        QFileDevice::ReadOwner | QFileDevice::WriteOwner
    );

    return true;
}

bool ControllerManager::persistGlobalControllerPreferences() const
{
    if (m_controllerSettingsPath.isEmpty())
        return false;

    QJsonObject root;
    QFile existing(m_controllerSettingsPath);

    if (existing.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(existing.readAll());
        existing.close();

        if (document.isObject())
            root = document.object();
    }

    QJsonObject global = root.value(QStringLiteral("_global")).toObject();
    global.insert(QStringLiteral("forceReconnectEnabled"), m_forceReconnectEnabled);
    global.insert(QStringLiteral("lastControllerAddress"), m_lastControllerAddress);
    global.insert(
        QStringLiteral("updatedUtc"),
        QDateTime::currentDateTimeUtc().toString(Qt::ISODate)
    );
    root.insert(QStringLiteral("_global"), global);

    QDir().mkpath(QFileInfo(m_controllerSettingsPath).absolutePath());

    QSaveFile output(m_controllerSettingsPath);

    if (!output.open(QIODevice::WriteOnly))
        return false;

    if (output.write(QJsonDocument(root).toJson(QJsonDocument::Indented)) < 0)
        return false;

    if (!output.commit())
        return false;

    QFile::setPermissions(
        m_controllerSettingsPath,
        QFileDevice::ReadOwner | QFileDevice::WriteOwner
    );

    return true;
}

void ControllerManager::rememberLastControllerAddress(const QString &address)
{
    const QString cleanAddress = address.trimmed().toUpper();

    static const QRegularExpression addressPattern(
        QStringLiteral("^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$")
    );

    if (!addressPattern.match(cleanAddress).hasMatch() ||
            m_lastControllerAddress == cleanAddress) {
        return;
    }

    m_lastControllerAddress = cleanAddress;
    persistGlobalControllerPreferences();
    emit forceReconnectChanged();
}

bool ControllerManager::writeTextFile(
    const QString &path,
    const QString &value
) const {
    QFile file(path);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;

    QByteArray bytes = value.toLocal8Bit();

    if (!bytes.endsWith('\n'))
        bytes.append('\n');

    const qint64 written = file.write(bytes);
    const bool flushed = file.flush();
    file.close();

    return written == bytes.size() && flushed;
}

void ControllerManager::setControllerLightCapability(
    bool available,
    const QString &backend,
    const QString &path,
    const QStringList &channelPaths
) {
    const QString cleanBackend = available
        ? backend.trimmed()
        : QStringLiteral("Unavailable");
    const QString cleanPath = available ? path : QString();
    const QStringList cleanChannels = available
        ? channelPaths
        : QStringList();

    const bool changed =
        m_controllerLightAvailable != available ||
        m_controllerLightBackend != cleanBackend ||
        m_controllerLightPath != cleanPath ||
        m_controllerLightChannelPaths != cleanChannels;

    m_controllerLightAvailable = available;
    m_controllerLightBackend = cleanBackend;
    m_controllerLightPath = cleanPath;
    m_controllerLightChannelPaths = cleanChannels;

    if (changed)
        emit controllerCapabilitiesChanged();
}

void ControllerManager::scanControllerLightDevices()
{
    if (!m_controllerConnected) {
        setControllerLightCapability(false, QString(), QString());
        return;
    }

    QDir ledRoot(QStringLiteral("/sys/class/leds"));

    if (!ledRoot.exists()) {
        setControllerLightCapability(false, QString(), QString());
        return;
    }

    const QFileInfoList entries = ledRoot.entryInfoList(
        QDir::Dirs | QDir::NoDotAndDotDot | QDir::System
    );

    QString bestMulticolorPath;
    int bestMulticolorScore = -1;
    QHash<QString, QHash<QString, QString>> rgbGroups;

    const QString controllerBlob =
        (m_controllerType + QStringLiteral(" ") + m_controllerName)
        .toLower();
    const bool playStationController =
        controllerBlob.contains(QStringLiteral("dualshock")) ||
        controllerBlob.contains(QStringLiteral("dualsense")) ||
        controllerBlob.contains(QStringLiteral("playstation")) ||
        controllerBlob.contains(QStringLiteral("sony"));

    for (const QFileInfo &entry : entries) {
        const QString path = entry.absoluteFilePath();
        const QString name = entry.fileName();
        const QString lower = name.toLower();
        const QString identity = (
            lower + QStringLiteral(" ") +
            readTextFile(QDir(path).filePath(QStringLiteral("device/uevent"))).toLower() +
            QStringLiteral(" ") +
            readTextFile(QDir(path).filePath(QStringLiteral("device/modalias"))).toLower()
        );

        if (QFileInfo::exists(QDir(path).filePath(QStringLiteral("multi_intensity"))) &&
                QFileInfo::exists(QDir(path).filePath(QStringLiteral("brightness")))) {
            int score = 10;

            if (lower.contains(QStringLiteral(":rgb:indicator")))
                score += 160;

            if (identity.contains(QStringLiteral("playstation")) ||
                    identity.contains(QStringLiteral("dualsense")) ||
                    identity.contains(QStringLiteral("dualshock")) ||
                    identity.contains(QStringLiteral("sony"))) {
                score += 120;
            }

            if (playStationController)
                score += 45;

            /*
                Never claim an unrelated RGB LED.  Require either the
                standard hid-playstation indicator name or a controller-
                specific PlayStation/Sony identity match.
            */
            if (score >= 100 && score > bestMulticolorScore) {
                bestMulticolorScore = score;
                bestMulticolorPath = path;
            }
        }

        const QStringList colors = {
            QStringLiteral("red"),
            QStringLiteral("green"),
            QStringLiteral("blue")
        };

        for (const QString &color : colors) {
            const QString colonSuffix = QStringLiteral(":") + color;
            const QString dashSuffix = QStringLiteral("-") + color;
            QString prefix;

            if (lower.endsWith(colonSuffix))
                prefix = lower.left(lower.length() - colonSuffix.length());
            else if (lower.endsWith(dashSuffix))
                prefix = lower.left(lower.length() - dashSuffix.length());

            const bool controllerSpecificRgb =
                playStationController ||
                prefix.contains(QStringLiteral("playstation")) ||
                prefix.contains(QStringLiteral("dualshock")) ||
                prefix.contains(QStringLiteral("dualsense")) ||
                prefix.contains(QStringLiteral("sony"));

            if (!prefix.isEmpty() &&
                    controllerSpecificRgb &&
                    QFileInfo::exists(QDir(path).filePath(QStringLiteral("brightness")))) {
                rgbGroups[prefix].insert(color, path);
            }
        }
    }

    if (!bestMulticolorPath.isEmpty()) {
        setControllerLightCapability(
            true,
            QStringLiteral("Linux multicolor LED"),
            bestMulticolorPath
        );
        restoreControllerLightColor();
        return;
    }

    for (auto it = rgbGroups.constBegin(); it != rgbGroups.constEnd(); ++it) {
        const QHash<QString, QString> group = it.value();

        if (!group.contains(QStringLiteral("red")) ||
                !group.contains(QStringLiteral("green")) ||
                !group.contains(QStringLiteral("blue"))) {
            continue;
        }

        const QStringList paths = {
            group.value(QStringLiteral("red")),
            group.value(QStringLiteral("green")),
            group.value(QStringLiteral("blue"))
        };

        setControllerLightCapability(
            true,
            QStringLiteral("Linux RGB LED"),
            it.key(),
            paths
        );
        restoreControllerLightColor();
        return;
    }

    setControllerLightCapability(false, QString(), QString());
}

bool ControllerManager::applyMulticolorLight(
    const QString &path,
    int red,
    int green,
    int blue
) {
    const QString indexText = readTextFile(
        QDir(path).filePath(QStringLiteral("multi_index"))
    );
    QStringList indices = indexText.split(
        QRegularExpression(QStringLiteral("\\s+")),
        Qt::SkipEmptyParts
    );

    if (indices.isEmpty()) {
        indices = {
            QStringLiteral("red"),
            QStringLiteral("green"),
            QStringLiteral("blue")
        };
    }

    QStringList intensityValues;

    for (const QString &index : indices) {
        const QString channel = index.trimmed().toLower();

        if (channel.contains(QStringLiteral("red")))
            intensityValues.append(QString::number(red));
        else if (channel.contains(QStringLiteral("green")))
            intensityValues.append(QString::number(green));
        else if (channel.contains(QStringLiteral("blue")))
            intensityValues.append(QString::number(blue));
        else
            intensityValues.append(QStringLiteral("0"));
    }

    const QString triggerPath = QDir(path).filePath(QStringLiteral("trigger"));

    if (QFileInfo::exists(triggerPath))
        writeTextFile(triggerPath, QStringLiteral("none"));

    if (!writeTextFile(
            QDir(path).filePath(QStringLiteral("multi_intensity")),
            intensityValues.join(QLatin1Char(' '))
        )) {
        return false;
    }

    bool brightnessOk = false;
    int maxBrightness = readTextFile(
        QDir(path).filePath(QStringLiteral("max_brightness"))
    ).toInt(&brightnessOk);

    if (!brightnessOk || maxBrightness <= 0)
        maxBrightness = 255;

    return writeTextFile(
        QDir(path).filePath(QStringLiteral("brightness")),
        QString::number(maxBrightness)
    );
}

bool ControllerManager::applySeparateRgbLight(
    const QStringList &paths,
    int red,
    int green,
    int blue
) {
    if (paths.size() < 3)
        return false;

    const QList<int> values = { red, green, blue };
    bool success = true;

    for (int index = 0; index < 3; ++index) {
        const QString path = paths.at(index);
        const QString triggerPath = QDir(path).filePath(QStringLiteral("trigger"));

        if (QFileInfo::exists(triggerPath))
            writeTextFile(triggerPath, QStringLiteral("none"));

        bool maxOk = false;
        int maxBrightness = readTextFile(
            QDir(path).filePath(QStringLiteral("max_brightness"))
        ).toInt(&maxOk);

        if (!maxOk || maxBrightness <= 0)
            maxBrightness = 255;

        const int scaled = qBound(
            0,
            qRound(values.at(index) * maxBrightness / 255.0),
            maxBrightness
        );

        success = writeTextFile(
            QDir(path).filePath(QStringLiteral("brightness")),
            QString::number(scaled)
        ) && success;
    }

    return success;
}

bool ControllerManager::applyControllerLightColor(const QString &color)
{
    if (!m_controllerLightAvailable)
        return false;

    int red = 0;
    int green = 0;
    int blue = 0;

    if (!parseLightColor(color, &red, &green, &blue))
        return false;

    if (!m_controllerLightChannelPaths.isEmpty()) {
        return applySeparateRgbLight(
            m_controllerLightChannelPaths,
            red,
            green,
            blue
        );
    }

    if (!m_controllerLightPath.isEmpty()) {
        return applyMulticolorLight(
            m_controllerLightPath,
            red,
            green,
            blue
        );
    }

    return false;
}

bool ControllerManager::setControllerLightColor(const QString &color)
{
    const QString normalized = normalizeLightColor(color);
    const bool changed = m_controllerLightColor != normalized;
    m_controllerLightColor = normalized;

    if (changed)
        emit controllerPreferencesChanged();

    const bool persisted = persistControllerPreferences();
    const bool applied = !m_controllerLightAvailable ||
        restoreControllerLightColor();

    return persisted && applied;
}

bool ControllerManager::setLightColor(const QString &color)
{
    return setControllerLightColor(color);
}

bool ControllerManager::setLedColor(const QString &color)
{
    return setControllerLightColor(color);
}

bool ControllerManager::previewControllerLightColor(const QString &color)
{
    if (!m_controllerLightEnabled)
        return false;

    return applyControllerLightColor(normalizeLightColor(color));
}

bool ControllerManager::restoreControllerLightColor()
{
    if (!m_controllerLightAvailable)
        return false;

    return applyControllerLightColor(
        m_controllerLightEnabled
        ? m_controllerLightColor
        : QStringLiteral("#000000")
    );
}

bool ControllerManager::setControllerLightEnabled(bool enabled)
{
    const bool changed = m_controllerLightEnabled != enabled;
    m_controllerLightEnabled = enabled;

    if (changed)
        emit controllerPreferencesChanged();

    const bool persisted = persistControllerPreferences();
    const bool applied = !m_controllerLightAvailable ||
        restoreControllerLightColor();

    return persisted && applied;
}

bool ControllerManager::setControllerVibrationLevel(const QString &level)
{
    const QString normalized = normalizeVibrationLevel(level);
    const bool changed = m_controllerVibrationLevel != normalized;
    m_controllerVibrationLevel = normalized;

    if (changed)
        emit controllerPreferencesChanged();

    return persistControllerPreferences();
}

bool ControllerManager::setControllerVibrationPattern(const QString &pattern)
{
    const QString normalized = normalizeVibrationPattern(pattern);
    const bool changed = m_controllerVibrationPattern != normalized;
    m_controllerVibrationPattern = normalized;

    if (changed)
        emit controllerPreferencesChanged();

    return persistControllerPreferences();
}

bool ControllerManager::setControllerVibrationEnabled(bool enabled)
{
    const bool changed = m_controllerVibrationEnabled != enabled;
    m_controllerVibrationEnabled = enabled;

    if (!enabled) {
        m_patternTimer.stop();
        stopRumble();
    }

    if (changed)
        emit controllerPreferencesChanged();

    return persistControllerPreferences();
}

bool ControllerManager::saveControllerPreferences(
    const QString &color,
    const QString &vibrationLevel
) {
    return saveControllerProfile(
        color,
        m_controllerLightEnabled,
        vibrationLevel,
        m_controllerVibrationPattern,
        m_controllerVibrationEnabled,
        m_forceReconnectEnabled
    );
}

bool ControllerManager::saveControllerProfile(
    const QString &color,
    bool lightEnabled,
    const QString &vibrationLevel,
    const QString &vibrationPattern,
    bool vibrationEnabled,
    bool forceReconnectEnabled
) {
    const QString normalizedColor = normalizeLightColor(color);
    const QString normalizedVibration = normalizeVibrationLevel(vibrationLevel);
    const QString normalizedPattern = normalizeVibrationPattern(vibrationPattern);

    const bool controllerChanged =
        m_controllerLightColor != normalizedColor ||
        m_controllerLightEnabled != lightEnabled ||
        m_controllerVibrationLevel != normalizedVibration ||
        m_controllerVibrationPattern != normalizedPattern ||
        m_controllerVibrationEnabled != vibrationEnabled;

    const bool reconnectChanged =
        m_forceReconnectEnabled != forceReconnectEnabled;

    m_controllerLightColor = normalizedColor;
    m_controllerLightEnabled = lightEnabled;
    m_controllerVibrationLevel = normalizedVibration;
    m_controllerVibrationPattern = normalizedPattern;
    m_controllerVibrationEnabled = vibrationEnabled;
    m_forceReconnectEnabled = forceReconnectEnabled;

    if (!m_controllerVibrationEnabled) {
        m_patternTimer.stop();
        stopRumble();
    }

    if (controllerChanged)
        emit controllerPreferencesChanged();

    if (reconnectChanged)
        emit forceReconnectChanged();

    const bool persisted = persistControllerPreferences();
    const bool applied = !m_controllerLightAvailable ||
        restoreControllerLightColor();

    if (m_forceReconnectEnabled && !m_controllerConnected)
        startForceReconnectWindow();
    else if (!m_forceReconnectEnabled)
        stopForceReconnectWindow();

    return persisted && applied;
}

void ControllerManager::previewVibrationLevel(const QString &level)
{
    previewVibrationPattern(m_controllerVibrationPattern, level);
}

void ControllerManager::previewVibrationPattern(
    const QString &pattern,
    const QString &level
) {
    if (!m_controllerVibrationEnabled)
        return;

    playConfiguredVibrationPattern(
        normalizeVibrationPattern(pattern),
        normalizeVibrationLevel(level)
    );
}

bool ControllerManager::setForceReconnectEnabled(bool enabled)
{
    if (m_forceReconnectEnabled == enabled)
        return persistGlobalControllerPreferences();

    m_forceReconnectEnabled = enabled;
    emit forceReconnectChanged();

    const bool persisted = persistGlobalControllerPreferences();

    if (enabled && !m_controllerConnected)
        startForceReconnectWindow();
    else if (!enabled)
        stopForceReconnectWindow();

    return persisted;
}

bool ControllerManager::forceReconnectNow()
{
    if (m_controllerConnected) {
        setControllerBackendStatus(QStringLiteral("Controller is already connected"));
        return true;
    }

    if (m_lastControllerAddress.trimmed().isEmpty()) {
        setControllerBackendStatus(
            QStringLiteral("Force Reconnect unavailable: no saved controller")
        );
        return false;
    }

    startForceReconnectWindow();
    attemptForceReconnect();
    return true;
}

/*
    ============================================================
                    FORCE RECONNECT / BLUETOOTH
    ============================================================
*/

void ControllerManager::startForceReconnectWindow()
{
    if (m_controllerConnected || m_lastControllerAddress.trimmed().isEmpty()) {
        stopForceReconnectWindow();
        return;
    }

    m_forceReconnectDeadline = QDateTime::currentDateTimeUtc().addSecs(180);

    if (!m_forceReconnectActive) {
        m_forceReconnectActive = true;
        emit forceReconnectChanged();
    }

    if (!m_forceReconnectTimer.isActive())
        m_forceReconnectTimer.start();

    setControllerBackendStatus(
        QStringLiteral("Force Reconnect active for saved controller ") +
        m_lastControllerAddress
    );

    QTimer::singleShot(0, this, [this]() {
        attemptForceReconnect();
    });
}

void ControllerManager::stopForceReconnectWindow()
{
    m_forceReconnectTimer.stop();
    m_forceReconnectDeadline = QDateTime();

    if (m_forceReconnectActive) {
        m_forceReconnectActive = false;
        emit forceReconnectChanged();
    }
}

void ControllerManager::attemptForceReconnect()
{
    if (!m_forceReconnectActive)
        return;

    if (m_controllerConnected) {
        setControllerBackendStatus(QStringLiteral("Controller reconnected"));
        stopForceReconnectWindow();
        return;
    }

    if (!m_forceReconnectDeadline.isValid() ||
            QDateTime::currentDateTimeUtc() >= m_forceReconnectDeadline) {
        setControllerBackendStatus(
            QStringLiteral("Force Reconnect window completed")
        );
        stopForceReconnectWindow();
        return;
    }

    emit forceReconnectChanged();

    const QString address = m_lastControllerAddress.trimmed().toUpper();

    if (address.isEmpty()) {
        setControllerBackendStatus(
            QStringLiteral("Force Reconnect unavailable: no saved controller")
        );
        stopForceReconnectWindow();
        return;
    }

    if (m_forceReconnectProcess.state() != QProcess::NotRunning)
        return;

    m_forceReconnectProcess.setProgram(QStringLiteral("bluetoothctl"));
    m_forceReconnectProcess.setArguments(
        QStringList() << QStringLiteral("connect") << address
    );
    m_forceReconnectProcess.start();

    if (!m_forceReconnectProcess.waitForStarted(120)) {
        setLastControllerEvent(
            QStringLiteral("Force Reconnect could not start bluetoothctl")
        );
    } else {
        setControllerBackendStatus(
            QStringLiteral("Attempting Bluetooth controller reconnect")
        );
    }
}

/*
    ============================================================
                    CONTROLLER OFF / BLUETOOTH
    ============================================================
*/

bool ControllerManager::tryDisconnectBluetoothController(const QString &reason)
{
    Q_UNUSED(reason);

    const QStringList candidates = bluetoothControllerAddressCandidates();

    if (candidates.isEmpty())
        return false;

    bool issued = false;
    QString lastStdout;
    QString lastStderr;

    for (const QString &address : candidates) {
        if (address.trimmed().isEmpty())
            continue;

        QString standardOutput;
        QString standardError;

        if (runBluetoothCtl(
                QStringList() << QStringLiteral("disconnect") << address,
                &standardOutput,
                &standardError
            )) {
            issued = true;
            lastStdout = standardOutput;
            lastStderr = standardError;
            break;
        }

        lastStdout = standardOutput;
        lastStderr = standardError;
    }

    if (!issued) {
        setLastControllerEvent(
            QStringLiteral("bluetooth disconnect failed: ") +
            (lastStderr.trimmed().isEmpty() ? lastStdout.trimmed() : lastStderr.trimmed())
        );
    }

    return issued;
}

QStringList ControllerManager::bluetoothControllerAddressCandidates() const
{
    QStringList candidates;

    const auto addUnique = [&candidates](const QString &address) {
        const QString clean = address.trimmed().toUpper();

        if (clean.isEmpty())
            return;

        if (!candidates.contains(clean))
            candidates.append(clean);
    };

    for (const QString &address : bluetoothControllerAddressCandidatesFromSysfs())
        addUnique(address);

    for (const QString &address : bluetoothControllerAddressCandidatesFromBluetoothCtl())
        addUnique(address);

    return candidates;
}

QStringList ControllerManager::bluetoothControllerAddressCandidatesFromSysfs() const
{
    QStringList candidates;

    QStringList roots;

    if (!m_controllerDevicePath.isEmpty())
        roots.append(QFileInfo(m_controllerDevicePath).canonicalFilePath());

    for (const InputDevice &device : m_inputDevices) {
        if (device.kind == InputDeviceKind::GamepadInput) {
            const QString canonical = QFileInfo(device.path).canonicalFilePath();

            if (!canonical.isEmpty())
                roots.append(canonical);
        }
    }

    const QRegularExpression addressRegex(
        QStringLiteral("([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})")
    );

    for (const QString &rootPath : roots) {
        QString path = rootPath;

        for (int depth = 0; depth < 14 && !path.isEmpty(); ++depth) {
            const QRegularExpressionMatch match = addressRegex.match(path);

            if (match.hasMatch()) {
                const QString address = match.captured(1).toUpper();

                if (!candidates.contains(address))
                    candidates.append(address);
            }

            QFileInfo info(path);
            const QDir parent = info.dir();
            const QString nextPath = parent.absolutePath();

            if (nextPath == path || nextPath == QStringLiteral("/"))
                break;

            path = nextPath;
        }
    }

    return candidates;
}

QStringList ControllerManager::bluetoothControllerAddressCandidatesFromBluetoothCtl() const
{
    QString standardOutput;
    QString standardError;

    if (!runBluetoothCtl(
            QStringList() << QStringLiteral("devices") << QStringLiteral("Connected"),
            &standardOutput,
            &standardError
        )) {
        Q_UNUSED(standardError);
        return QStringList();
    }

    QStringList candidates;

    const QString controllerNameLower = m_controllerName.toLower();
    const QStringList lines = standardOutput.split(QLatin1Char('\n'), Qt::SkipEmptyParts);

    const QRegularExpression lineRegex(
        QStringLiteral("^\\s*Device\\s+([0-9A-Fa-f:]{17})\\s+(.+)\\s*$")
    );

    for (const QString &line : lines) {
        const QRegularExpressionMatch match = lineRegex.match(line.trimmed());

        if (!match.hasMatch())
            continue;

        const QString address = match.captured(1).toUpper();
        const QString name = match.captured(2).trimmed();
        const QString nameLower = name.toLower();

        const bool matchesKnownController =
            (!controllerNameLower.isEmpty() &&
             controllerNameLower != QStringLiteral("none") &&
             (nameLower.contains(controllerNameLower) || controllerNameLower.contains(nameLower))) ||
            isGamepadName(name) ||
            isPlayStationName(name);

        if (!matchesKnownController)
            continue;

        if (!candidates.contains(address))
            candidates.append(address);
    }

    return candidates;
}

bool ControllerManager::runBluetoothCtl(
    const QStringList &arguments,
    QString *standardOutput,
    QString *standardError
) const {
    QProcess process;

    process.setProgram(QStringLiteral("bluetoothctl"));
    process.setArguments(arguments);

    process.start();

    if (!process.waitForStarted(1000)) {
        if (standardError)
            *standardError = QStringLiteral("bluetoothctl did not start");

        return false;
    }

    if (!process.waitForFinished(3000)) {
        process.kill();
        process.waitForFinished(500);

        if (standardError)
            *standardError = QStringLiteral("bluetoothctl timed out");

        return false;
    }

    const QString out = QString::fromLocal8Bit(process.readAllStandardOutput());
    const QString err = QString::fromLocal8Bit(process.readAllStandardError());

    if (standardOutput)
        *standardOutput = out;

    if (standardError)
        *standardError = err;

    return process.exitStatus() == QProcess::NormalExit &&
           process.exitCode() == 0;
}

/*
    ============================================================
                            BATTERY
    ============================================================
*/

void ControllerManager::scanControllerBattery()
{
    QDir powerDir(QStringLiteral("/sys/class/power_supply"));

    if (!powerDir.exists()) {
        setBatteryUnavailable();
        return;
    }

    const QFileInfoList entries =
        powerDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System);

    BatteryDevice bestDevice;
    int bestScore = -1;

    for (const QFileInfo &info : entries) {
        BatteryDevice device = readBatteryDevice(info.absoluteFilePath());

        if (!device.valid)
            continue;

        const int score = controllerBatteryScore(device);

        if (score <= 0 || score <= bestScore)
            continue;

        device.likelyController = true;
        bestDevice = device;
        bestScore = score;
    }

    if (!bestDevice.valid || !bestDevice.likelyController) {
        setBatteryUnavailable();
        return;
    }

    const int percent = clampPercent(bestDevice.capacity);
    const QString state = normalizeBatteryStatus(bestDevice.status);
    const bool charging = state == QStringLiteral("Charging");

    setBatteryValues(
        true,
        percent,
        state,
        charging,
        bestDevice.path
    );
}

ControllerManager::BatteryDevice ControllerManager::readBatteryDevice(const QString &path) const
{
    BatteryDevice device;

    QFileInfo info(path);

    device.path = path;
    device.name = info.fileName();
    device.modelName = readTextFile(path + QStringLiteral("/model_name"));
    device.manufacturer = readTextFile(path + QStringLiteral("/manufacturer"));
    device.type = readTextFile(path + QStringLiteral("/type"));
    device.scope = readTextFile(path + QStringLiteral("/scope"));
    device.status = normalizeBatteryStatus(readTextFile(path + QStringLiteral("/status")));

    bool capacityOk = false;
    const QString capacityText = readTextFile(path + QStringLiteral("/capacity"));
    const int capacityValue = capacityText.toInt(&capacityOk);

    device.capacity = capacityOk ? capacityValue : -1;

    const QString typeLower = device.type.toLower();

    device.valid =
        capacityOk &&
        (
            typeLower.contains(QStringLiteral("battery")) ||
            device.name.toLower().contains(QStringLiteral("battery")) ||
            path.toLower().contains(QStringLiteral("battery"))
        );

    return device;
}

bool ControllerManager::isControllerBatteryDevice(const BatteryDevice &device) const
{
    return controllerBatteryScore(device) > 0;
}

int ControllerManager::controllerBatteryScore(const BatteryDevice &device) const
{
    QString blob =
        device.path + QStringLiteral(" ") +
        device.name + QStringLiteral(" ") +
        device.modelName + QStringLiteral(" ") +
        device.manufacturer + QStringLiteral(" ") +
        device.type + QStringLiteral(" ") +
        device.scope;

    blob = blob.toLower();

    int score = 0;

    const QString controllerName = m_controllerName.trimmed().toLower();
    const QString deviceIdentity =
        (device.name + QStringLiteral(" ") +
         device.modelName + QStringLiteral(" ") +
         device.manufacturer).toLower();

    if (!controllerName.isEmpty() &&
            controllerName != QStringLiteral("none") &&
            (deviceIdentity.contains(controllerName) ||
             controllerName.contains(deviceIdentity))) {
        score += 100;
    }

    if (blob.contains(QStringLiteral("dualsense")) ||
            blob.contains(QStringLiteral("dualshock")) ||
            blob.contains(QStringLiteral("playstation")) ||
            blob.contains(QStringLiteral("wireless controller")) ||
            blob.contains(QStringLiteral("wireless_controller")) ||
            blob.contains(QStringLiteral("sony interactive")) ||
            blob.contains(QStringLiteral("hid-playstation")) ||
            blob.contains(QStringLiteral("hid-sony"))) {
        score += 140;
    }

    /*
        Current hid-playstation kernels commonly expose names such as:
            ps-controller-battery-XX:XX:XX:XX:XX:XX
        These paths do not necessarily include the words Sony or DualSense.
    */
    if (blob.contains(QStringLiteral("ps-controller")) ||
            blob.contains(QStringLiteral("controller-battery")) ||
            blob.contains(QStringLiteral("controller_battery"))) {
        score += 180;
    }

    if (blob.contains(QStringLiteral("ps4")) ||
            blob.contains(QStringLiteral("ps5")) ||
            blob.contains(QStringLiteral("sony"))) {
        score += 80;
    }

    const QString scope = device.scope.trimmed().toLower();

    if (scope == QStringLiteral("device"))
        score += 45;

    const QString type = device.type.trimmed().toLower();

    if (type.contains(QStringLiteral("battery")))
        score += 20;

    /*
        A device-scoped battery is a safe final fallback only while a physical
        gamepad is actually connected. This avoids selecting the Pi power rail
        or a system UPS battery.
    */
    if (score < 60 &&
            m_controllerConnected &&
            scope == QStringLiteral("device") &&
            type.contains(QStringLiteral("battery"))) {
        score = 60;
    }

    return score;
}

QString ControllerManager::normalizeBatteryStatus(const QString &status) const
{
    const QString s = status.trimmed().toLower();

    if (s == QStringLiteral("charging"))
        return QStringLiteral("Charging");

    if (s == QStringLiteral("discharging"))
        return QStringLiteral("Discharging");

    if (s == QStringLiteral("full"))
        return QStringLiteral("Full");

    if (s == QStringLiteral("not charging"))
        return QStringLiteral("Not Charging");

    return QStringLiteral("Unknown");
}

QString ControllerManager::readTextFile(const QString &path) const
{
    QFile file(path);

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();

    const QString text = QString::fromLocal8Bit(file.readAll()).trimmed();

    file.close();

    return text;
}

void ControllerManager::setBatteryUnavailable()
{
    setBatteryValues(
        false,
        -1,
        QStringLiteral("Unknown"),
        false,
        QString()
    );
}

void ControllerManager::setBatteryValues(
    bool available,
    int percent,
    const QString &state,
    bool charging,
    const QString &path
) {
    const bool changed =
        m_controllerBatteryAvailable != available ||
        m_controllerBatteryPercent != percent ||
        m_controllerBatteryState != state ||
        m_controllerCharging != charging ||
        m_controllerBatteryPath != path;

    if (!changed)
        return;

    m_controllerBatteryAvailable = available;
    m_controllerBatteryPercent = percent;
    m_controllerBatteryState = state;
    m_controllerCharging = charging;
    m_controllerBatteryPath = path;

    emit controllerBatteryChanged();

    if (m_controllerConnected &&
            !m_controllerBatteryPath.isEmpty() &&
            (m_controllerAddress.isEmpty() ||
             m_controllerType == QStringLiteral("Controller") ||
             m_controllerType == QStringLiteral("PlayStation Controller"))) {
        QTimer::singleShot(0, this, [this]() {
            if (m_controllerConnected)
                refreshControllerIdentity();
        });
    }
}

/*
    ============================================================
                        PHYSICAL INPUT
    ============================================================
*/

void ControllerManager::scheduleMotionDeviceDrain(const QString &path)
{
    for (InputDevice &device : m_inputDevices) {
        if (device.path != path ||
            device.kind != InputDeviceKind::MotionSensorDevice ||
            device.fd < 0 ||
            device.motionDrainQueued) {
            continue;
        }

        device.motionDrainQueued = true;
        if (device.notifier)
            device.notifier->setEnabled(false);

        QTimer::singleShot(MOTION_DRAIN_MS, this, [this, path]() {
            drainInputDevice(path);

            for (InputDevice &current : m_inputDevices) {
                if (current.path != path)
                    continue;

                current.motionDrainQueued = false;
                if (current.notifier && current.fd >= 0)
                    current.notifier->setEnabled(true);
                break;
            }
        });

        return;
    }
}

void ControllerManager::drainInputDevice(const QString &path)
{
    for (InputDevice &device : m_inputDevices) {
        if (device.path != path || device.fd < 0)
            continue;

        input_event event;
        bool motionFrameReady = false;

        while (true) {
            errno = 0;
            const ssize_t bytes = ::read(device.fd, &event, sizeof(event));

            if (bytes != sizeof(event)) {
                if (bytes == 0 ||
                    (bytes < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
                    if (device.notifier)
                        device.notifier->setEnabled(false);
                    if (device.fd >= 0) {
                        ::close(device.fd);
                        device.fd = -1;
                    }
                    queueInputDeviceScan();
                }
                break;
            }

            if (device.kind == InputDeviceKind::MotionSensorDevice) {
                if (event.type == EV_ABS) {
                    handleMotionSensorEvent(device, event.code, event.value);
                } else if (event.type == EV_SYN &&
                           event.code == SYN_REPORT &&
                           device.motionFrameDirty) {
                    motionFrameReady = true;
                }
                continue;
            }

            if (event.type == EV_SYN)
                continue;

            if (device.kind != InputDeviceKind::GamepadInput)
                continue;

            if (event.type == EV_KEY) {
                handleButtonEvent(device, event.code, event.value != 0);
            } else if (event.type == EV_ABS) {
                handleAxisEvent(device, event.code, event.value);
            }
        }

        if (motionFrameReady && device.fd >= 0)
            flushMotionSensorFrame(device);

        return;
    }
}

void ControllerManager::queueInputDeviceScan()
{
    if (m_inputRescanQueued)
        return;

    m_inputRescanQueued = true;

    QTimer::singleShot(INPUT_RESCAN_DEBOUNCE_MS, this, [this]() {
        m_inputRescanQueued = false;
        scanInputDevices();
    });
}

void ControllerManager::updateAdaptiveTimers()
{
    const int deviceScanInterval = m_controllerConnected
        ? DEVICE_SCAN_CONNECTED_MS
        : DEVICE_SCAN_DISCONNECTED_MS;

    if (m_deviceScanTimer.interval() != deviceScanInterval)
        m_deviceScanTimer.setInterval(deviceScanInterval);
    if (!m_deviceScanTimer.isActive())
        m_deviceScanTimer.start();

    const int batteryInterval = m_controllerConnected
        ? BATTERY_REFRESH_CONNECTED_MS
        : BATTERY_REFRESH_DISCONNECTED_MS;

    if (m_batteryRefreshTimer.interval() != batteryInterval)
        m_batteryRefreshTimer.setInterval(batteryInterval);
    if (!m_batteryRefreshTimer.isActive())
        m_batteryRefreshTimer.start();
}

void ControllerManager::handleButtonEvent(InputDevice &device, int code, bool pressed)
{
    if (device.kind != InputDeviceKind::GamepadInput)
        return;

    if (!device.buttonMap.contains(code))
        return;

    const QString action = device.buttonMap.value(code);

    if (action.isEmpty())
        return;

    const QString key = QStringLiteral("button:") + action;

    if (pressed) {
        if (device.pressedActions.contains(key))
            return;

        device.pressedActions.insert(key);
        emitActionPressed(action, device.name);
    } else {
        if (!device.pressedActions.contains(key))
            return;

        device.pressedActions.remove(key);
        emitActionReleased(action, device.name);
    }
}

void ControllerManager::handleAxisEvent(InputDevice &device, int code, int value)
{
    if (device.kind != InputDeviceKind::GamepadInput)
        return;

    if (!device.axisMap.contains(code))
        return;

    const QString axis = device.axisMap.value(code);

    device.axisValues[code] = value;

    if (axis == QStringLiteral("left_x") ||
        axis == QStringLiteral("left_y") ||
        axis == QStringLiteral("right_x") ||
        axis == QStringLiteral("right_y")) {
        const QString stick =
            axis.startsWith(QStringLiteral("left"))
            ? QStringLiteral("leftstick")
            : QStringLiteral("rightstick");

        int x = 0;
        int y = 0;

        if (stick == QStringLiteral("leftstick")) {
            x = normalizeStickValue(device.axisValues.value(ABS_X, 0));
            y = normalizeStickValue(device.axisValues.value(ABS_Y, 0));
        } else {
            x = normalizeStickValue(device.axisValues.value(ABS_RX, 0));
            y = normalizeStickValue(device.axisValues.value(ABS_RY, 0));
        }

        const QString xKey = stick + QStringLiteral("_x");
        const QString yKey = stick + QStringLiteral("_y");
        const int previousX = device.stickValues.value(xKey, 0);
        const int previousY = device.stickValues.value(yKey, 0);

        const bool xChanged =
            (x == 0 && previousX != 0) ||
            (x != 0 && std::abs(x - previousX) >= STICK_EMIT_DELTA);
        const bool yChanged =
            (y == 0 && previousY != 0) ||
            (y != 0 && std::abs(y - previousY) >= STICK_EMIT_DELTA);

        if (xChanged || yChanged) {
            device.stickValues[xKey] = x;
            device.stickValues[yKey] = y;
            emitStickMove(stick, x, y, device.name);
        }
    }

    const bool analogStickAxis =
        axis == QStringLiteral("left_x") || axis == QStringLiteral("left_y") ||
        axis == QStringLiteral("right_x") || axis == QStringLiteral("right_y");

    // Standalone Browser consumes analog sticks through stickMoved().  Disabling
    // synthesized stick directions there keeps the D-pad independent while the
    // left stick performs spatial anchor navigation and the right stick drives
    // the fast cursor.  The normal NeutronShell controller behavior is unchanged.
    if (analogStickAxis && !m_stickNavigationActionsEnabled)
        return;

    const QString direction = normalizeAxisDirection(axis, value);

    QString negativeAction;
    QString positiveAction;

    if (axis == QStringLiteral("left_x") ||
        axis == QStringLiteral("right_x") ||
        axis == QStringLiteral("dpad_x")) {
        negativeAction = QStringLiteral("left");
        positiveAction = QStringLiteral("right");
    } else if (axis == QStringLiteral("left_y") ||
               axis == QStringLiteral("right_y") ||
               axis == QStringLiteral("dpad_y")) {
        negativeAction = QStringLiteral("up");
        positiveAction = QStringLiteral("down");
    } else if (axis == QStringLiteral("l2_axis")) {
        negativeAction = QString();
        positiveAction = QStringLiteral("l2");
    } else if (axis == QStringLiteral("r2_axis")) {
        negativeAction = QString();
        positiveAction = QStringLiteral("r2");
    } else {
        return;
    }

    const QString negativeKey = QStringLiteral("axis:") + axis + QStringLiteral(":") + negativeAction;
    const QString positiveKey = QStringLiteral("axis:") + axis + QStringLiteral(":") + positiveAction;

    if (direction == QStringLiteral("negative")) {
        if (!negativeAction.isEmpty() && !device.pressedActions.contains(negativeKey)) {
            device.pressedActions.insert(negativeKey);
            emitActionPressed(negativeAction, device.name);
        }

        if (!positiveAction.isEmpty() && device.pressedActions.contains(positiveKey)) {
            device.pressedActions.remove(positiveKey);
            emitActionReleased(positiveAction, device.name);
        }

        return;
    }

    if (direction == QStringLiteral("positive")) {
        if (!positiveAction.isEmpty() && !device.pressedActions.contains(positiveKey)) {
            device.pressedActions.insert(positiveKey);
            emitActionPressed(positiveAction, device.name);
        }

        if (!negativeAction.isEmpty() && device.pressedActions.contains(negativeKey)) {
            device.pressedActions.remove(negativeKey);
            emitActionReleased(negativeAction, device.name);
        }

        return;
    }

    if (!negativeAction.isEmpty() && device.pressedActions.contains(negativeKey)) {
        device.pressedActions.remove(negativeKey);
        emitActionReleased(negativeAction, device.name);
    }

    if (!positiveAction.isEmpty() && device.pressedActions.contains(positiveKey)) {
        device.pressedActions.remove(positiveKey);
        emitActionReleased(positiveAction, device.name);
    }
}

void ControllerManager::handleMotionSensorEvent(InputDevice &device, int code, int value)
{
    if (device.kind != InputDeviceKind::MotionSensorDevice)
        return;

    device.motionValues[code] = value;
    device.motionFrameDirty = true;
}

void ControllerManager::flushMotionSensorFrame(InputDevice &device)
{
    if (device.kind != InputDeviceKind::MotionSensorDevice ||
        !device.motionFrameDirty) {
        return;
    }

    device.motionFrameDirty = false;

    const int rawX = device.motionValues.value(ABS_X, 0);
    const int rawY = device.motionValues.value(ABS_Y, 0);
    const int rawRX = device.motionValues.value(ABS_RX, rawX);
    const int rawRY = device.motionValues.value(ABS_RY, rawY);

    setMotionValues(
        normalizeMotionValue(rawX),
        normalizeMotionValue(rawY),
        normalizeMotionValue(rawRX),
        normalizeMotionValue(rawRY)
    );
}

/*
    ============================================================
                    WEB CONTROLLER FALLBACK
    ============================================================
*/

void ControllerManager::scheduleWebControllerRead()
{
    if (m_controllerConnected || m_webReadQueued)
        return;

    m_webReadQueued = true;

    QTimer::singleShot(0, this, [this]() {
        m_webReadQueued = false;

        if (m_controllerConnected)
            return;

        if (QFileInfo::exists(m_webControllerFile) &&
            !m_webControllerWatcher.files().contains(m_webControllerFile)) {
            m_webControllerWatcher.addPath(m_webControllerFile);
        }

        pollWebControllerFile();
    });
}

void ControllerManager::pollWebControllerFile()
{
    if (m_controllerConnected)
        return;

    QFile file(m_webControllerFile);

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (!m_webHeldActions.isEmpty() || !m_webHeldDirections.isEmpty())
            m_webReleaseTimer.start(m_webReleaseTimeoutMs);

        return;
    }

    const QByteArray data = file.readAll();
    file.close();

    const QJsonDocument doc = QJsonDocument::fromJson(data);

    if (!doc.isObject()) {
        if (!m_webHeldActions.isEmpty() || !m_webHeldDirections.isEmpty())
            m_webReleaseTimer.start(m_webReleaseTimeoutMs);

        return;
    }

    const QJsonObject obj = doc.object();

    const QString rawButton = obj.value(QStringLiteral("button")).toString();
    const QString button = normalizeButton(rawButton);
    const QString state = obj.value(QStringLiteral("state")).toString().trimmed().toLower();
    const qint64 time = obj.value(QStringLiteral("time")).toVariant().toLongLong();

    int x = obj.value(QStringLiteral("x")).toInt();
    int y = obj.value(QStringLiteral("y")).toInt();

    if (std::abs(x) < m_webStickDeadzone)
        x = 0;

    if (std::abs(y) < m_webStickDeadzone)
        y = 0;

    const QString eventKey =
        button + QStringLiteral(":") +
        state + QStringLiteral(":") +
        QString::number(x) + QStringLiteral(":") +
        QString::number(y) + QStringLiteral(":") +
        QString::number(time);

    /*
        Duplicate event protection.

        The web controller may write the same press repeatedly. That must not
        spam login combo input or menu navigation.
    */
    if (eventKey == m_lastWebEventKey)
        return;

    m_lastWebEventKey = eventKey;
    m_lastWebInputAt = QDateTime::currentDateTimeUtc();
    m_webReleaseTimer.start(m_webReleaseTimeoutMs);

    if (button.isEmpty())
        return;

    setInputSource(QStringLiteral("web"));

    if (state == QStringLiteral("press")) {
        if (m_webHeldActions.contains(button))
            return;

        m_webHeldActions.insert(button);
        emitActionPressed(button, QStringLiteral("web"));
        return;
    }

    if (state == QStringLiteral("release")) {
        if (m_webHeldActions.contains(button)) {
            m_webHeldActions.remove(button);
            emitActionReleased(button, QStringLiteral("web"));
        }

        if (m_webHeldDirections.contains(button)) {
            m_webHeldDirections.remove(button);
            emitActionReleased(button, QStringLiteral("web"));
        }

        if (m_webHeldActions.isEmpty() && m_webHeldDirections.isEmpty())
            m_webReleaseTimer.stop();

        return;
    }

    if (state != QStringLiteral("move"))
        return;

    emitStickMove(button, x, y, QStringLiteral("web"));

    const QString stick = button.toLower();

    if (stick != QStringLiteral("leftstick") &&
        stick != QStringLiteral("rightstick")) {
        return;
    }

    QSet<QString> wantedDirections;

    if (x < -m_webStickDeadzone)
        wantedDirections.insert(QStringLiteral("left"));
    else if (x > m_webStickDeadzone)
        wantedDirections.insert(QStringLiteral("right"));

    if (y < -m_webStickDeadzone)
        wantedDirections.insert(QStringLiteral("up"));
    else if (y > m_webStickDeadzone)
        wantedDirections.insert(QStringLiteral("down"));

    const QStringList allDirections = {
        QStringLiteral("left"),
        QStringLiteral("right"),
        QStringLiteral("up"),
        QStringLiteral("down")
    };

    for (const QString &direction : allDirections) {
        if (wantedDirections.contains(direction) &&
                !m_webHeldDirections.contains(direction)) {
            m_webHeldDirections.insert(direction);
            emitActionPressed(direction, QStringLiteral("web"));
        } else if (!wantedDirections.contains(direction) &&
                   m_webHeldDirections.contains(direction)) {
            m_webHeldDirections.remove(direction);
            emitActionReleased(direction, QStringLiteral("web"));
        }
    }
}

/*
    ============================================================
                        NORMALIZATION
    ============================================================
*/

QString ControllerManager::normalizeButton(const QString &button) const
{
    QString b = button.trimmed().toLower();

    b.replace(QStringLiteral(" "), QStringLiteral("_"));
    b.replace(QStringLiteral("-"), QStringLiteral("_"));

    if (b == QStringLiteral("primary") ||
        b == QStringLiteral("cancel") ||
        b == QStringLiteral("secondary") ||
        b == QStringLiteral("context") ||
        b == QStringLiteral("system") ||
        b == QStringLiteral("home") ||
        b == QStringLiteral("quick") ||
        b == QStringLiteral("up") ||
        b == QStringLiteral("down") ||
        b == QStringLiteral("left") ||
        b == QStringLiteral("right") ||
        b == QStringLiteral("l1") ||
        b == QStringLiteral("r1") ||
        b == QStringLiteral("l2") ||
        b == QStringLiteral("r2") ||
        b == QStringLiteral("l3") ||
        b == QStringLiteral("r3")) {
        return b;
    }

    if (b == QStringLiteral("cross") ||
        b == QStringLiteral("x") ||
        b == QStringLiteral("ps_cross") ||
        b == QStringLiteral("button_cross")) {
        return QStringLiteral("primary");
    }

    if (b == QStringLiteral("circle") ||
        b == QStringLiteral("o") ||
        b == QStringLiteral("ps_circle") ||
        b == QStringLiteral("button_circle")) {
        return QStringLiteral("cancel");
    }

    if (b == QStringLiteral("square") ||
        b == QStringLiteral("ps_square") ||
        b == QStringLiteral("button_square")) {
        return QStringLiteral("secondary");
    }

    if (b == QStringLiteral("triangle") ||
        b == QStringLiteral("ps_triangle") ||
        b == QStringLiteral("button_triangle")) {
        return QStringLiteral("context");
    }

    if (b == QStringLiteral("options") ||
        b == QStringLiteral("settings") ||
        b == QStringLiteral("start") ||
        b == QStringLiteral("menu")) {
        return QStringLiteral("system");
    }

    if (b == QStringLiteral("share") ||
        b == QStringLiteral("create") ||
        b == QStringLiteral("select")) {
        return QStringLiteral("quick");
    }

    if (b == QStringLiteral("ps") ||
        b == QStringLiteral("playstation") ||
        b == QStringLiteral("home")) {
        return QStringLiteral("home");
    }

    if (b == QStringLiteral("dpad_up") ||
        b == QStringLiteral("leftstick_up") ||
        b == QStringLiteral("rightstick_up")) {
        return QStringLiteral("up");
    }

    if (b == QStringLiteral("dpad_down") ||
        b == QStringLiteral("leftstick_down") ||
        b == QStringLiteral("rightstick_down")) {
        return QStringLiteral("down");
    }

    if (b == QStringLiteral("dpad_left") ||
        b == QStringLiteral("leftstick_left") ||
        b == QStringLiteral("rightstick_left")) {
        return QStringLiteral("left");
    }

    if (b == QStringLiteral("dpad_right") ||
        b == QStringLiteral("leftstick_right") ||
        b == QStringLiteral("rightstick_right")) {
        return QStringLiteral("right");
    }

    if (b == QStringLiteral("left_stick") || b == QStringLiteral("leftstick"))
        return QStringLiteral("leftstick");

    if (b == QStringLiteral("right_stick") || b == QStringLiteral("rightstick"))
        return QStringLiteral("rightstick");

    if (b == QStringLiteral("lb"))
        return QStringLiteral("l1");

    if (b == QStringLiteral("rb"))
        return QStringLiteral("r1");

    if (b == QStringLiteral("lt"))
        return QStringLiteral("l2");

    if (b == QStringLiteral("rt"))
        return QStringLiteral("r2");

    return b;
}

QString ControllerManager::normalizeAxisDirection(const QString &axis, int value) const
{
    if (axis == QStringLiteral("dpad_x") || axis == QStringLiteral("dpad_y")) {
        if (value < 0)
            return QStringLiteral("negative");

        if (value > 0)
            return QStringLiteral("positive");

        return QString();
    }

    if (axis == QStringLiteral("l2_axis") || axis == QStringLiteral("r2_axis")) {
        /*
            Some controllers expose triggers as 0..255.
            Some expose them as a wider absolute range.
        */
        const int maximum = std::abs(value) <= 255 ? 255 : 32767;
        const int threshold = std::max(1, maximum * m_triggerThresholdPercent / 100);
        if (value > threshold)
            return QStringLiteral("positive");

        return QString();
    }

    if (value < -m_linuxStickDeadzone)
        return QStringLiteral("negative");

    if (value > m_linuxStickDeadzone)
        return QStringLiteral("positive");

    return QString();
}

int ControllerManager::normalizeStickValue(int value) const
{
    if (std::abs(value) < m_linuxStickDeadzone)
        return 0;

    const qreal normalized =
        static_cast<qreal>(value) / static_cast<qreal>(m_stickMaxValue);

    int output = static_cast<int>(clampUnit(normalized) * 100.0);

    if (std::abs(output) < m_stickOutputDeadzone)
        output = 0;

    return std::max(-100, std::min(100, output));
}

/*
    ============================================================
                        MOTION HELPERS
    ============================================================
*/

qreal ControllerManager::normalizeMotionValue(int value) const
{
    if (std::abs(value) < m_motionDeadzone)
        return 0.0;

    return clampUnit(static_cast<qreal>(value) / m_motionScale);
}

void ControllerManager::setMotionAvailable(bool available)
{
    if (m_motionAvailable == available)
        return;

    m_motionAvailable = available;
    emit motionAvailableChanged();
}

void ControllerManager::setMotionValues(qreal x, qreal y, qreal roll, qreal pitch)
{
    x = clampUnit(x);
    y = clampUnit(y);
    roll = clampUnit(roll);
    pitch = clampUnit(pitch);

    if (qFuzzyCompare(m_motionX, x) &&
        qFuzzyCompare(m_motionY, y) &&
        qFuzzyCompare(m_motionRoll, roll) &&
        qFuzzyCompare(m_motionPitch, pitch)) {
        return;
    }

    m_motionX = x;
    m_motionY = y;
    m_motionRoll = roll;
    m_motionPitch = pitch;

    emit motionChanged();
}

void ControllerManager::resetMotionValues()
{
    setMotionValues(0.0, 0.0, 0.0, 0.0);
}

/*
    ============================================================
                        EMISSION HELPERS
    ============================================================
*/

void ControllerManager::emitActionPressed(const QString &action, const QString &source)
{
    const QString clean = normalizeButton(action);

    if (clean.isEmpty())
        return;

    setInputSource(source);
    setLastControllerEvent(QStringLiteral("pressed: ") + clean + QStringLiteral(" [") + source + QStringLiteral("]"));

    emit buttonPressed(clean);
    emit actionPressed(clean);

    /*
        Login capture prioritizes lossless input over per-press rumble. Success
        and error patterns can still be invoked explicitly by QML.
    */
    if (m_lowLatencyInputMode)
        return;

    if (clean == QStringLiteral("up") ||
        clean == QStringLiteral("down") ||
        clean == QStringLiteral("left") ||
        clean == QStringLiteral("right")) {
        hapticNavigation();
    } else if (clean == QStringLiteral("primary")) {
        hapticConfirm();
    } else if (clean == QStringLiteral("cancel")) {
        hapticPulse(6500, 11000, 42);
    } else if (clean == QStringLiteral("context") || clean == QStringLiteral("system")) {
        hapticPulse(9000, 16000, 58);
    }
}

void ControllerManager::emitActionReleased(const QString &action, const QString &source)
{
    const QString clean = normalizeButton(action);

    if (clean.isEmpty())
        return;

    setInputSource(source);
    setLastControllerEvent(QStringLiteral("released: ") + clean + QStringLiteral(" [") + source + QStringLiteral("]"));

    emit buttonReleased(clean);
    emit actionReleased(clean);
}

void ControllerManager::emitStickMove(const QString &stick, int x, int y, const QString &source)
{
    const QString clean = normalizeButton(stick);

    if (clean.isEmpty())
        return;

    setInputSource(source);

    if (x != 0 || y != 0) {
        setLastControllerEvent(
            QStringLiteral("stick: ") +
            clean +
            QStringLiteral(" x=") +
            QString::number(x) +
            QStringLiteral(" y=") +
            QString::number(y) +
            QStringLiteral(" [") +
            source +
            QStringLiteral("]")
        );
    }

    emit stickMoved(clean, x, y);
}

void ControllerManager::releaseAllPressedForDevice(InputDevice &device, const QString &reason)
{
    Q_UNUSED(reason);

    if (device.pressedActions.isEmpty())
        return;

    const QList<QString> keys = device.pressedActions.values();

    for (const QString &key : keys) {
        QString action;

        if (key.startsWith(QStringLiteral("button:"))) {
            action = key.mid(QStringLiteral("button:").length());
        } else if (key.startsWith(QStringLiteral("axis:"))) {
            const int lastColon = key.lastIndexOf(QStringLiteral(":"));

            if (lastColon >= 0 && lastColon < key.length() - 1)
                action = key.mid(lastColon + 1);
        }

        if (!action.isEmpty())
            emitActionReleased(action, device.name);
    }

    device.pressedActions.clear();
    device.activeAxisActions.clear();

    if (device.kind == InputDeviceKind::GamepadInput) {
        emitStickMove(QStringLiteral("leftstick"), 0, 0, device.name);
        emitStickMove(QStringLiteral("rightstick"), 0, 0, device.name);
    }
}

bool ControllerManager::webControllerStale() const
{
    if (!m_lastWebInputAt.isValid())
        return false;

    return m_lastWebInputAt.msecsTo(QDateTime::currentDateTimeUtc()) >
            m_webReleaseTimeoutMs;
}

void ControllerManager::releaseWebHeldInputs()
{
    if (m_webHeldActions.isEmpty() && m_webHeldDirections.isEmpty())
        return;

    const QList<QString> heldActions = m_webHeldActions.values();

    for (const QString &action : heldActions)
        emitActionReleased(action, QStringLiteral("web"));

    const QList<QString> heldDirections = m_webHeldDirections.values();

    for (const QString &direction : heldDirections)
        emitActionReleased(direction, QStringLiteral("web"));

    m_webHeldActions.clear();
    m_webHeldDirections.clear();
    m_webReleaseTimer.stop();

    emitStickMove(QStringLiteral("leftstick"), 0, 0, QStringLiteral("web"));
    emitStickMove(QStringLiteral("rightstick"), 0, 0, QStringLiteral("web"));

    m_lastWebInputAt = QDateTime();
}

void ControllerManager::releaseAllPressedInputs(const QString &reason)
{
    for (InputDevice &device : m_inputDevices)
        releaseAllPressedForDevice(device, reason);

    releaseWebHeldInputs();
}

/*
    ============================================================
                        STATE SETTERS
    ============================================================
*/

void ControllerManager::setControllerConnected(bool connected)
{
    if (m_controllerConnected == connected)
        return;

    m_controllerConnected = connected;
    emit controllerConnectedChanged();
    updateAdaptiveTimers();

    if (connected) {
        stopForceReconnectWindow();
        releaseWebHeldInputs();
    } else {
        scheduleWebControllerRead();
    }

    if (!connected) {
        setBatteryUnavailable();
        setControllerLightCapability(false, QString(), QString());
        setControllerIdentity(QString(), QStringLiteral("Controller"));
        return;
    }

    /*
        The hid-playstation power_supply, LED class, and BlueZ identity can
        appear shortly after the input node. Refresh in stages and reapply the
        saved output profile once the MAC identity is known.
    */
    QTimer::singleShot(350, this, [this]() {
        if (m_controllerConnected)
            scanControllerBattery();
    });

    QTimer::singleShot(650, this, [this]() {
        if (m_controllerConnected)
            refreshControllerIdentity();
    });

    QTimer::singleShot(900, this, [this]() {
        if (m_controllerConnected) {
            loadControllerPreferences();
            scanControllerLightDevices();
        }
    });

    QTimer::singleShot(1700, this, [this]() {
        if (m_controllerConnected)
            scanControllerLightDevices();
    });
}

void ControllerManager::setControllerName(const QString &name)
{
    if (m_controllerName == name)
        return;

    m_controllerName = name;
    emit controllerNameChanged();

    if (m_controllerConnected) {
        QTimer::singleShot(0, this, [this]() {
            if (m_controllerConnected)
                refreshControllerIdentity();
        });
    }
}

void ControllerManager::setInputSource(const QString &source)
{
    if (m_inputSource == source)
        return;

    m_inputSource = source;
    emit inputSourceChanged();
}

void ControllerManager::setHapticsAvailable(bool available)
{
    if (m_hapticsAvailable == available)
        return;

    m_hapticsAvailable = available;
    emit hapticsAvailableChanged();
}

void ControllerManager::setControllerDevicePath(const QString &path)
{
    if (m_controllerDevicePath == path)
        return;

    m_controllerDevicePath = path;
    emit controllerDevicePathChanged();
}

void ControllerManager::setMotionDevicePath(const QString &path)
{
    if (m_motionDevicePath == path)
        return;

    m_motionDevicePath = path;
    emit motionDevicePathChanged();
}

void ControllerManager::setTouchpadDevicePath(const QString &path)
{
    if (m_touchpadDevicePath == path)
        return;

    m_touchpadDevicePath = path;
    emit touchpadDevicePathChanged();
}

void ControllerManager::setHapticDevicePath(const QString &path)
{
    if (m_hapticDevicePath == path)
        return;

    m_hapticDevicePath = path;
    emit hapticDevicePathChanged();
}

void ControllerManager::setControllerBackendStatus(const QString &status)
{
    if (m_controllerBackendStatus == status)
        return;

    m_controllerBackendStatus = status;
    emit controllerDebugChanged();
}

void ControllerManager::setLastControllerEvent(const QString &eventText)
{
    if (m_lastControllerEvent == eventText)
        return;

    m_lastControllerEvent = eventText;
    emit controllerDebugChanged();
}

/*
    ============================================================
                            HAPTICS
    ============================================================
*/

void ControllerManager::scanHapticDevices()
{
    closeHapticDevices();

    QDir inputDir(QStringLiteral("/dev/input"));

    if (!inputDir.exists()) {
        setHapticsAvailable(false);
        setHapticDevicePath(QString());
        return;
    }

    const QFileInfoList events =
        inputDir.entryInfoList(
            QStringList() << QStringLiteral("event*"),
            QDir::System | QDir::Files
        );

    for (const QFileInfo &info : events)
        openHapticDevice(info.absoluteFilePath());

    setHapticsAvailable(!m_hapticDevices.isEmpty());

    if (m_hapticDevices.isEmpty())
        setHapticDevicePath(QString());
    else
        setHapticDevicePath(m_hapticDevices.first().path);
}

bool ControllerManager::openHapticDevice(const QString &path)
{
    const int fd = ::open(path.toLocal8Bit().constData(), O_RDWR | O_NONBLOCK);

    if (fd < 0)
        return false;

    const QString name = readDeviceName(fd);
    const InputDeviceKind kind = classifyInputDeviceName(name);

    /*
        Haptics must belong to the real controller node.
        Never try rumble on motion sensors or touchpad nodes.
    */
    if (kind != InputDeviceKind::GamepadInput) {
        ::close(fd);
        return false;
    }

    unsigned long evBits[(EV_MAX / (8 * sizeof(unsigned long))) + 1] = {};

    if (::ioctl(fd, EVIOCGBIT(0, sizeof(evBits)), evBits) < 0) {
        ::close(fd);
        return false;
    }

    if (!testBit(EV_FF, evBits)) {
        ::close(fd);
        return false;
    }

    unsigned long ffBits[(FF_MAX / (8 * sizeof(unsigned long))) + 1] = {};

    if (::ioctl(fd, EVIOCGBIT(EV_FF, sizeof(ffBits)), ffBits) < 0) {
        ::close(fd);
        return false;
    }

    if (!testBit(FF_RUMBLE, ffBits)) {
        ::close(fd);
        return false;
    }

    HapticDevice device;
    device.path = path;
    device.name = name;
    device.fd = fd;
    device.effectId = -1;

    m_hapticDevices.append(device);

    return true;
}

void ControllerManager::closeHapticDevices()
{
    for (HapticDevice &device : m_hapticDevices) {
        if (device.fd >= 0) {
            if (device.effectId >= 0)
                ::ioctl(device.fd, EVIOCRMFF, device.effectId);

            ::close(device.fd);
        }

        device.fd = -1;
        device.effectId = -1;
    }

    m_hapticDevices.clear();
}

void ControllerManager::hapticPulse(int weakMagnitude, int strongMagnitude, int durationMs)
{
    startRumble(weakMagnitude, strongMagnitude, durationMs);
}

void ControllerManager::hapticNavigation()
{
    startRumble(4000, 8000, 24);
}

void ControllerManager::hapticConfirm()
{
    playConfiguredVibrationPattern(
        m_controllerVibrationPattern,
        m_controllerVibrationLevel
    );
}

void ControllerManager::hapticError()
{
    startPattern(
        QVector<int>({22000, 0, 22000, 0, 28000}),
        QVector<int>({42000, 0, 42000, 0, 52000}),
        QVector<int>({80, 55, 80, 55, 120})
    );
}

void ControllerManager::hapticWarning()
{
    startPattern(
        QVector<int>({14000, 0, 14000}),
        QVector<int>({26000, 0, 26000}),
        QVector<int>({70, 70, 95})
    );
}

void ControllerManager::hapticSuccess()
{
    playConfiguredVibrationPattern(
        m_controllerVibrationPattern,
        m_controllerVibrationLevel
    );
}

void ControllerManager::startRumble(int weakMagnitude, int strongMagnitude, int durationMs)
{
    if (!m_controllerVibrationEnabled)
        return;

    const qreal scale = vibrationScale();

    startRumbleRaw(
        qRound(weakMagnitude * scale),
        qRound(strongMagnitude * scale),
        durationMs
    );
}

void ControllerManager::startRumbleRaw(int weakMagnitude, int strongMagnitude, int durationMs)
{
    if (m_hapticDevices.isEmpty()) {
        scanHapticDevices();

        if (m_hapticDevices.isEmpty())
            return;
    }

    weakMagnitude = clampMagnitude(weakMagnitude);
    strongMagnitude = clampMagnitude(strongMagnitude);
    durationMs = std::max(10, std::min(2000, durationMs));

    for (HapticDevice &device : m_hapticDevices) {
        if (device.fd < 0)
            continue;

        if (device.effectId >= 0) {
            ::ioctl(device.fd, EVIOCRMFF, device.effectId);
            device.effectId = -1;
        }

        ff_effect effect;
        std::memset(&effect, 0, sizeof(effect));

        effect.type = FF_RUMBLE;
        effect.id = -1;
        effect.u.rumble.weak_magnitude = static_cast<unsigned short>(weakMagnitude);
        effect.u.rumble.strong_magnitude = static_cast<unsigned short>(strongMagnitude);
        effect.replay.length = static_cast<unsigned short>(durationMs);
        effect.replay.delay = 0;

        if (::ioctl(device.fd, EVIOCSFF, &effect) < 0)
            continue;

        device.effectId = effect.id;

        input_event play;
        std::memset(&play, 0, sizeof(play));

        play.type = EV_FF;
        play.code = effect.id;
        play.value = 1;

        ::write(device.fd, &play, sizeof(play));
    }

    m_hapticStopTimer.start(durationMs + 25);
}

void ControllerManager::stopRumble()
{
    m_hapticStopTimer.stop();

    for (HapticDevice &device : m_hapticDevices) {
        if (device.fd < 0 || device.effectId < 0)
            continue;

        input_event stop;
        std::memset(&stop, 0, sizeof(stop));

        stop.type = EV_FF;
        stop.code = device.effectId;
        stop.value = 0;

        ::write(device.fd, &stop, sizeof(stop));
    }
}

void ControllerManager::startPattern(
    const QVector<int> &weak,
    const QVector<int> &strong,
    const QVector<int> &durations,
    qreal scale
) {
    if (!m_controllerVibrationEnabled ||
            weak.isEmpty() || strong.isEmpty() || durations.isEmpty()) {
        return;
    }

    m_patternTimer.stop();
    stopRumble();

    m_patternWeak = weak;
    m_patternStrong = strong;
    m_patternDurations = durations;
    m_patternIndex = 0;
    m_patternScale = scale < 0.0 ? vibrationScale() : scale;

    playNextPatternStep();
}

void ControllerManager::playConfiguredVibrationPattern(
    const QString &pattern,
    const QString &level
) {
    if (!m_controllerVibrationEnabled)
        return;

    const QString normalizedPattern = normalizeVibrationPattern(pattern);
    const QString normalizedLevel = normalizeVibrationLevel(level);

    qreal scale = 1.0;

    if (normalizedLevel == QStringLiteral("low"))
        scale = 0.55;
    else if (normalizedLevel == QStringLiteral("high"))
        scale = 1.45;

    if (normalizedPattern == QStringLiteral("double-tap")) {
        startPattern(
            QVector<int>({7200, 0, 9000}),
            QVector<int>({13500, 0, 17000}),
            QVector<int>({42, 48, 58}),
            scale
        );
        return;
    }

    if (normalizedPattern == QStringLiteral("heartbeat")) {
        startPattern(
            QVector<int>({6000, 0, 10500, 0}),
            QVector<int>({11500, 0, 22000, 0}),
            QVector<int>({48, 55, 82, 65}),
            scale
        );
        return;
    }

    if (normalizedPattern == QStringLiteral("rising-wave")) {
        startPattern(
            QVector<int>({4200, 7000, 10500, 14500}),
            QVector<int>({8000, 13500, 21500, 30000}),
            QVector<int>({38, 46, 58, 80}),
            scale
        );
        return;
    }

    if (normalizedPattern == QStringLiteral("heavy-impact")) {
        startPattern(
            QVector<int>({11000, 0, 18000, 0, 23000}),
            QVector<int>({25000, 0, 39000, 0, 52000}),
            QVector<int>({65, 45, 90, 55, 135}),
            scale
        );
        return;
    }

    startPattern(
        QVector<int>({5200}),
        QVector<int>({10500}),
        QVector<int>({52}),
        scale
    );
}

void ControllerManager::playNextPatternStep()
{
    if (m_patternIndex >= m_patternDurations.size()) {
        stopRumble();
        return;
    }

    const int weak =
        m_patternIndex < m_patternWeak.size() ? m_patternWeak[m_patternIndex] : 0;

    const int strong =
        m_patternIndex < m_patternStrong.size() ? m_patternStrong[m_patternIndex] : 0;

    const int duration = m_patternDurations[m_patternIndex];

    if (weak > 0 || strong > 0) {
        startRumbleRaw(
            qRound(weak * m_patternScale),
            qRound(strong * m_patternScale),
            duration
        );
    } else {
        stopRumble();
    }

    m_patternIndex++;
    m_patternTimer.start(std::max(20, duration));
}
