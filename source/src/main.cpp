#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlProperty>
#include <QCoreApplication>
#include <QUrl>
#include <QCursor>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QDebug>
#include <QStringList>
#include <QByteArray>
#include <QObject>
#include <QTimer>
#include <QSaveFile>
#include <QtQml/qqml.h>
#include <QQuickWindow>
#include <QVariantMap>
#include <QElapsedTimer>
#include <QEvent>
#include <QThread>
#include <QImageReader>

#ifdef Q_OS_LINUX
#include <sys/stat.h>
#include <unistd.h>
#endif

#include "UserManager.h"
#include "SetupWizardManager.h"
#include "AssetManager.h"
#include "ControllerManager.h"
#include "SecurityManager.h"
#include "SecurityCoreManager.h"
#include "AppManager.h"
#include "QuickActionManager.h"
#include "ScreensaverManager.h"
#include "SystemMonitor.h"
#include "DashboardLayoutManager.h"
#include "FractureEffect.h"
#include "GeminiGeometry.h"
#include "StorageManager.h"
#include "ClockSettingsManager.h"
#include "ClockExperienceManager.h"
#include "NetworkManager.h"
#include "DockSecurityManager.h"
#include "DeveloperModeManager.h"
#include "PrivilegeManager.h"
#include "TerminalManager.h"
#include "TerminalAssistManager.h"
#include "PowerModeManager.h"
#include "PerformanceManager.h"
#include "PersonalizationManager.h"
#include "SettingsManager.h"
#include "UpdateRecoveryManager.h"
#include "BackupRestoreManager.h"
#include "RecoveryModeManager.h"
#include "DiagnosticsManager.h"
#include "CoreCapabilitiesManager.h"
#include "NotificationManager.h"
#include "CaptureManager.h"
#include "BrowserManager.h"
#include "AppStoreManager.h"
#include "PackageAppBridgeManager.h"
#include "GalleryManager.h"
#include "TextEditorManager.h"
#include "NeutronSyntaxHighlighter.h"
#include "MusicPlayerManager.h"
#include "QBitTorrentManager.h"
#include "FileManager.h"
#include "GamesManager.h"
#include "DockerManager.h"
#include "LogsManager.h"
#include "MediaOptimizerManager.h"

#ifndef NEUTRONOS_STATE_DIR
#define NEUTRONOS_STATE_DIR "/var/lib/neutronos"
#endif

#ifndef NEUTRONOS_SECURITY_STATE_DIR
#define NEUTRONOS_SECURITY_STATE_DIR "/var/lib/neutronos/security"
#endif

class ShellReadinessBridge final : public QObject
{
    Q_OBJECT
public:
    explicit ShellReadinessBridge(bool smokeTest, QObject *parent = nullptr)
        : QObject(parent)
    {
        if (!smokeTest) {
            QFile::remove(QStringLiteral("/run/neutronos/login-ready"));
            QFile::remove(QStringLiteral("/run/neutronos/shell-frame-ready"));
        }
    }
    Q_INVOKABLE void markDestinationPresented()
    {
        if (m_destinationPresented) return;
        m_destinationPresented = true;
        QDir().mkpath(QStringLiteral("/run/neutronos"));
        for (const QString &name : {QStringLiteral("login-ready"), QStringLiteral("shell-frame-ready")}) {
            QSaveFile marker(QStringLiteral("/run/neutronos/") + name);
            if (marker.open(QIODevice::WriteOnly | QIODevice::Text)) {
                marker.write("ready\n"); marker.commit();
            }
        }
        qInfo() << "NeutronOS graphical destination presented";
    }
private:
    bool m_destinationPresented = false;
};

static QString defaultNeutronRootPath()
{
    return QStringLiteral("/opt/neutronos");
}

static QString cleanPath(const QString &path)
{
    return QDir::cleanPath(path);
}

static bool pathHasMainQml(const QString &root)
{
    return QFileInfo::exists(
        cleanPath(root + QStringLiteral("/qml/Main.qml"))
    );
}

static QString resolveNeutronRootPath()
{
    /*
        Filesystem-first runtime.

        Priority:
            1. NEUTRONOS_ROOT environment variable.
            2. ~/NeutronOS.
            3. Current working directory if it contains qml/Main.qml.
            4. Application directory parent fallback.

        This keeps:
            - QML editable without rebuilding.
            - apps drop-in capable without rebuilding.
            - themes/assets swappable without rebuilding.
    */

    const QByteArray envRoot = qgetenv("NEUTRONOS_ROOT");

    if (!envRoot.isEmpty()) {
        const QString envPath = cleanPath(QString::fromLocal8Bit(envRoot));

        if (pathHasMainQml(envPath))
            return envPath;

        qWarning() << "NEUTRONOS_ROOT is set but qml/Main.qml was not found:" << envPath;
    }

    const QString homeRoot = cleanPath(defaultNeutronRootPath());

    if (pathHasMainQml(homeRoot))
        return homeRoot;

    const QString currentRoot = cleanPath(QDir::currentPath());

    if (pathHasMainQml(currentRoot))
        return currentRoot;

    const QString appDir = cleanPath(QCoreApplication::applicationDirPath());
    const QString appParentRoot = cleanPath(
        QDir(appDir).absoluteFilePath(QStringLiteral(".."))
    );

    if (pathHasMainQml(appParentRoot))
        return appParentRoot;

    /*
        Final fallback keeps paths predictable.
        The QML load failure will point at ~/NeutronOS/qml/Main.qml.
    */
    return homeRoot;
}

static void configureRuntimeEnvironment()
{
    /*
        HDMI / controller-first shell behavior.
        Cursor should never appear on the TV shell.
    */

    /*
        Conservative Pi-friendly QML defaults.
        Styling is handled by NeutronOS QML components.
    */
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");

    // Qt 6.8.2 threaded Quick 3D material teardown crashed under rapid page
    // changes in the GPU VM. Keep scene synchronization and teardown on one
    // thread while retaining GPU rendering. Explicit diagnostic overrides stay.
    if (qEnvironmentVariableIsEmpty("QSG_RENDER_LOOP"))
        qputenv("QSG_RENDER_LOOP", "basic");

    /* Production boot: keep Qt's compiled QML cache enabled. Qt invalidates
       filesystem cache entries when the source file changes. */
    qunsetenv("QML_DISABLE_DISK_CACHE");

    /*
        Patch 52 Safe Mode is an explicit persistent recovery flag. The
        basic render loop avoids the threaded scene-graph path while the
        user repairs display, theme, or animation problems. It does not
        switch NeutronOS to software rendering or expose a root shell.
    */
    QString safeModeRoot = qEnvironmentVariable("NEUTRONOS_ROOT").trimmed();
    if (safeModeRoot.isEmpty())
        safeModeRoot = defaultNeutronRootPath();
    if (!QFileInfo::exists(QDir(safeModeRoot).filePath(QStringLiteral("qml/Main.qml"))) &&
        QFileInfo::exists(QStringLiteral("/opt/neutronos/qml/Main.qml")))
        safeModeRoot = QStringLiteral("/opt/neutronos");
    const QString safeModeFlag = QDir(safeModeRoot)
                                     .filePath(QStringLiteral("state/update-recovery/safe-mode-next-boot"));
    if (QFileInfo::exists(safeModeFlag)) {
        qputenv("NEUTRONOS_SAFE_MODE", "1");
        qputenv("QSG_RENDER_LOOP", "basic");
    }

    /*
        Security state is not under ~/NeutronOS anymore.
        Managers also have compile-time defaults, but exporting these makes
        diagnostics and future subprocesses consistent.
    */
    qputenv("NEUTRONOS_STATE_DIR", QByteArray(NEUTRONOS_STATE_DIR));
    qputenv("NEUTRONOS_SECURITY_STATE_DIR", QByteArray(NEUTRONOS_SECURITY_STATE_DIR));
}

static bool ensureDirectory(const QString &path, bool secure)
{
    QDir dir(path);

    if (!dir.exists()) {
        if (secure) {
            qCritical() << "Privileged state setup did not create required directory:" << path;
            return false;
        }
        if (!QDir().mkpath(path)) {
            qWarning() << "Failed to create directory:" << path;
            return false;
        }
    }

    return true;
}

static bool securityDirectoryLooksSafe(const QString &path)
{
#ifdef Q_OS_LINUX
    struct stat st;
    const QByteArray bytes = path.toLocal8Bit();

    if (::stat(bytes.constData(), &st) != 0) {
        qWarning() << "Could not stat security directory:" << path;
        return false;
    }

    const bool ownerExpected =
        st.st_uid == ::geteuid() || st.st_uid == static_cast<uid_t>(0);
    const bool groupAccess = (st.st_mode & S_IRWXG) != 0;
    const bool worldAccess = (st.st_mode & S_IRWXO) != 0;

    if (!ownerExpected)
        qWarning() << "SECURITY WARNING: directory owner is neither root nor the NeutronShell runtime user:" << path;
    if (groupAccess || worldAccess)
        qWarning() << "SECURITY WARNING: directory permissions are too open:" << path;

    return ownerExpected && !groupAccess && !worldAccess;
#else
    Q_UNUSED(path)
    return true;
#endif
}

static void ensureRuntimeDirectories(const QString &root)
{
    /*
       The installed NeutronOS root is immutable payload.  Startup must never
       create config, QML, theme, or application directories there.  The
       release packager owns those paths and the shell only reads them.
    */
    const QStringList packagedDirectories = {
        root,
        root + QStringLiteral("/qml"),
        root + QStringLiteral("/qml/apps"),
        root + QStringLiteral("/config"),
        root + QStringLiteral("/config/app-store"),
        root + QStringLiteral("/config/app-store/repository"),
        root + QStringLiteral("/themes/Default"),
        root + QStringLiteral("/themes/Default/users"),
        root + QStringLiteral("/themes/Default/apps/icons"),
        root + QStringLiteral("/themes/Default/apps/posters")
    };

    for (const QString &path : packagedDirectories) {
        const QFileInfo info(path);
        if (!info.isDir() || !info.isReadable())
            qCritical() << "Required immutable payload directory is unavailable:" << path;
    }

    /*
       /usr/local/sbin/neutronos-state-setup is the only component allowed to
       create, chown, or chmod authoritative state. NeutronShell only validates
       it. This prevents the unprivileged GUI from fighting the root setup
       helper on every startup.
    */
    const QString statePath = QStringLiteral(NEUTRONOS_STATE_DIR);
    const QString securityPath = QStringLiteral(NEUTRONOS_SECURITY_STATE_DIR);
    ensureDirectory(statePath, true);
    ensureDirectory(securityPath, true);
    securityDirectoryLooksSafe(statePath);
    securityDirectoryLooksSafe(securityPath);
}

static void exposeSystemContext(QQmlApplicationEngine &engine, const QString &root)
{
    const QString qmlPath = root + QStringLiteral("/qml");
    const QString themePath = root + QStringLiteral("/themes/Default");
    const QString appsPath = qmlPath + QStringLiteral("/apps");

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosName"),
        QStringLiteral("NeutronOS")
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosCodename"),
        QStringLiteral("Gemini")
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosVersion"),
        QCoreApplication::applicationVersion()
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosRootPath"),
        root
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosQmlPath"),
        qmlPath
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosAppsPath"),
        appsPath
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosThemePath"),
        themePath
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosIconsPath"),
        themePath + QStringLiteral("/apps/icons")
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosPostersPath"),
        themePath + QStringLiteral("/apps/posters")
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosUsersPath"),
        themePath + QStringLiteral("/users")
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosStatePath"),
        QStringLiteral(NEUTRONOS_STATE_DIR)
    );

    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronosSecurityPath"),
        QStringLiteral(NEUTRONOS_SECURITY_STATE_DIR)
    );
}


static void configureQmlImportPaths(QQmlApplicationEngine &engine, const QString &root)
{
    const QString qmlPath = root + QStringLiteral("/qml");

    /*
        Filesystem QML import paths.

        This allows:
            - qml/Main.qml to update without rebuild.
            - qml/apps/<appId>/Main.qml drop-in without rebuild.
            - shared components to update without rebuild.
            - themes/assets to update without rebuild.
    */

    engine.addImportPath(qmlPath);
    engine.addImportPath(qmlPath + QStringLiteral("/common"));
    engine.addImportPath(qmlPath + QStringLiteral("/components"));
    engine.addImportPath(qmlPath + QStringLiteral("/cards"));
    engine.addImportPath(qmlPath + QStringLiteral("/dashboard"));
    engine.addImportPath(qmlPath + QStringLiteral("/modals"));
    engine.addImportPath(qmlPath + QStringLiteral("/systemwidgets"));
    engine.addImportPath(qmlPath + QStringLiteral("/apps"));
}

int main(int argc, char *argv[])
{
    configureRuntimeEnvironment();

    QGuiApplication app(argc, argv);
    const bool smokeTest = app.arguments().contains(QStringLiteral("--smoke-test"));

    QCoreApplication::setApplicationName(QStringLiteral("NeutronShell"));
    QCoreApplication::setApplicationVersion(QStringLiteral(NEUTRONOS_VERSION));
    QCoreApplication::setOrganizationName(QStringLiteral("DrNeutron"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("neutronos.local"));

    app.setOverrideCursor(Qt::BlankCursor);

    const QString neutronRoot = resolveNeutronRootPath();
    const QString qmlRoot = neutronRoot + QStringLiteral("/qml");
    const QString mainQmlPath = qmlRoot + QStringLiteral("/Main.qml");

    if (app.arguments().contains(QStringLiteral("--svg-smoke-test"))) {
        const QStringList svgAssets = {
            neutronRoot + QStringLiteral("/themes/Default/atom.svg")
        };
        for (const QString &path : svgAssets) {
            QImageReader reader(path);
            if (!reader.canRead()) {
                qCritical() << "Qt SVG runtime cannot decode" << path
                            << reader.errorString();
                return 2;
            }
            const QImage decoded = reader.read();
            if (decoded.isNull()) {
                qCritical() << "Qt SVG runtime returned an empty image for" << path
                            << reader.errorString();
                return 2;
            }
            qInfo() << "Qt SVG runtime decoded" << path << decoded.size();
        }
        return 0;
    }

    ensureRuntimeDirectories(neutronRoot);

#ifdef Q_OS_LINUX
    if (::geteuid() == 0) {
        qWarning() << "SECURITY WARNING: NeutronShell should run as the unprivileged display user.";
    }
#endif

    qmlRegisterType<NeutronSyntaxHighlighter>("NeutronOS", 1, 0, "NeutronSyntaxHighlighter");
    qmlRegisterType<GeminiRingGeometry>("NeutronGemini", 1, 0, "GeminiRingGeometry");
        qmlRegisterType<GeminiHelixGeometry>("NeutronGemini",1,0,"GeminiHelixGeometry");
    qmlRegisterType<GeminiFractureGeometry>("NeutronGemini", 1, 0, "GeminiFractureGeometry");
    qmlRegisterType<FractureEffect>("NeutronEffects", 1, 0, "FractureEffect");

    if (app.arguments().contains(QStringLiteral("--recovery"))) {
        QCoreApplication::setApplicationName(QStringLiteral("NeutronRecovery"));
        QQmlApplicationEngine recoveryEngine;
        configureQmlImportPaths(recoveryEngine, neutronRoot);
        exposeSystemContext(recoveryEngine, neutronRoot);
        ControllerManager recoveryControllerManager;
        RecoveryModeManager recoveryModeManager;
        recoveryEngine.rootContext()->setContextProperty(
            QStringLiteral("controllerManager"), &recoveryControllerManager);
        recoveryEngine.rootContext()->setContextProperty(
            QStringLiteral("recoveryModeManager"), &recoveryModeManager);
        const QString recoveryQmlPath = qmlRoot + QStringLiteral("/Recovery.qml");
        recoveryEngine.load(QUrl::fromLocalFile(recoveryQmlPath));
        if (recoveryEngine.rootObjects().isEmpty()) {
            qCritical() << "NeutronOS Recovery could not load" << recoveryQmlPath;
            return -1;
        }
        return app.exec();
    }

    QQmlApplicationEngine engine;

    configureQmlImportPaths(engine, neutronRoot);
    ShellReadinessBridge shellReadiness(smokeTest);
    engine.rootContext()->setContextProperty(QStringLiteral("neutronSmokeTest"),
                                             smokeTest);
    engine.rootContext()->setContextProperty(QStringLiteral("shellReadiness"),
                                             &shellReadiness);
    const QString shellWindowPath = qmlRoot + QStringLiteral("/ShellWindow.qml");
    engine.load(QUrl::fromLocalFile(shellWindowPath));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "NeutronShell could not create its fullscreen window";
        return -1;
    }

    /*
        ============================================================
                            CORE MANAGERS
        ============================================================

        Managers live for the full lifetime of the shell.
        QML receives pointers only. QML does not own/delete them.

        SecurityManager and DeveloperModeManager now use:
            /var/lib/neutronos/security
            /var/lib/neutronos

        instead of:
            ~/NeutronOS/state/security

        This protects lockouts, combo hashes, and developer-mode state from
        normal user tampering.
    */

    UserManager userManager;
    AssetManager assetManager;
    ControllerManager controllerManager;
    SecurityManager securityManager;
    SecurityCoreManager securityCoreManager(neutronRoot, &securityManager);
    AppManager appManager;
    QuickActionManager quickActionManager;
    ScreensaverManager screensaverManager(
        neutronRoot + QStringLiteral("/themes/Default/screensavers"),
        neutronRoot + QStringLiteral("/state/screensaver")
    );
    SystemMonitor systemMonitor;
    DashboardLayoutManager dashboardLayoutManager(neutronRoot);
    StorageManager storageManager;
    ClockSettingsManager clockSettingsManager;
    clockSettingsManager.setLockscreenAuthenticationProvider([&securityManager]() {
        return QVariantMap{{QStringLiteral("username"),securityManager.activeUsername()},
                           {QStringLiteral("busy"),securityManager.operationBusy()},
                           {QStringLiteral("lockedOut"),securityManager.lockedOut()}};
    });
    QObject::connect(&securityManager, &SecurityManager::unlockGranted, &clockSettingsManager,
                     [&clockSettingsManager,&securityManager](const QVariantMap &) {
                         clockSettingsManager.completeLockscreenTimezoneAuthorization(securityManager.activeUsername());
                     });
    QObject::connect(&securityManager, &SecurityManager::activeUserChanged, &clockSettingsManager,
                     &ClockSettingsManager::cancelLockscreenTimezoneRequest);
    QObject::connect(&securityManager, &SecurityManager::lockoutStarted, &clockSettingsManager,
                     &ClockSettingsManager::cancelLockscreenTimezoneRequest);
    QObject::connect(&securityManager, &SecurityManager::unlockDenied, &clockSettingsManager,
                     &ClockSettingsManager::cancelLockscreenTimezoneRequest);
    ClockExperienceManager clockExperienceManager;
    auto synchronizeDesktopClockTimezone = [&clockSettingsManager,
                                             &clockExperienceManager]() {
        QVariantMap clockPayload;
        clockPayload.insert(QStringLiteral("timezone"),
                            clockSettingsManager.timezone());
        clockExperienceManager.applySettings(clockPayload);
    };
    QObject::connect(&clockSettingsManager,
                     &ClockSettingsManager::timezoneChanged,
                     &clockExperienceManager,
                     synchronizeDesktopClockTimezone);
    synchronizeDesktopClockTimezone();
    NetworkManager networkManager;
    DockSecurityManager dockSecurityManager;

    /*
        Console-level Developer Mode manager.

        Console owns Developer Mode globally.
        Terminal reads Developer Mode state; Terminal does not own it.
    */
    DeveloperModeManager developerModeManager;
    PrivilegeManager privilegeManager(&developerModeManager);
    PowerModeManager powerModeManager(&developerModeManager);
    PerformanceManager performanceManager;
    PersonalizationManager personalizationManager(neutronRoot);
    SettingsManager settingsManager(
        neutronRoot,
        &userManager,
        &storageManager,
        &developerModeManager,
        &screensaverManager,
        &networkManager,
        &controllerManager,
        &powerModeManager
    );
    UpdateRecoveryManager updateRecoveryManager(neutronRoot, &developerModeManager);
    BackupRestoreManager backupRestoreManager(neutronRoot, &updateRecoveryManager);
    DiagnosticsManager diagnosticsManager(neutronRoot);
    NotificationManager notificationManager(neutronRoot);
    securityManager.setNotificationManager(&notificationManager);
    CoreCapabilitiesManager coreCapabilitiesManager(neutronRoot, &securityCoreManager);
    BrowserManager browserManager(neutronRoot);
    appManager.setBrowserManager(&browserManager);

    AppStoreManager appStoreManager(
        neutronRoot,
        &appManager,
        &developerModeManager,
        &securityCoreManager
    );

    // Consume both handoff channels exactly once. A cryptographically validated
    // App Store rebuild resume takes precedence over an external-app return.
    const QVariantMap externalReturnSession = appManager.consumeExternalReturnSession();
    const QVariantMap appStoreReturnSession = appStoreManager.startupResume();
    const QVariantMap appHostStartupReturnSession =
        appStoreReturnSession.value(QStringLiteral("pending")).toBool()
            ? appStoreReturnSession : externalReturnSession;
    // An AppHost return is a session restoration, not a fresh boot. Never
    // cover the authenticated return path with the cold-boot visual.

    // Generic, dormant bridge for signed App Store packages. App-specific
    // protocol code remains inside each transactional package; the base shell
    // only validates ownership and transports bounded JSON messages.
    PackageAppBridgeManager packageAppBridgeManager(neutronRoot);
    QObject::connect(&appStoreManager, &AppStoreManager::rebuildStarted,
                     &packageAppBridgeManager, &PackageAppBridgeManager::stopAll);
    GalleryManager galleryManager(neutronRoot);
    CaptureManager captureManager(neutronRoot, &notificationManager);
    TextEditorManager textEditorManager(neutronRoot, &developerModeManager);
    MusicPlayerManager musicPlayerManager(neutronRoot);
    QBitTorrentManager qbitTorrentManager(neutronRoot);
    SetupWizardManager setupWizardManager(neutronRoot);

    /*
        Native controller-first File Manager backend.

        Provides real directory enumeration, text/code editing, Quick Look,
        metadata, copy/move/Trash, archives, authenticated encryption, and
        guarded removable-volume formatting.
    */
    FileManager fileManager;

    /*
        Controller-first ROM and emulator manager.

        GamesManager discovers ROMs from qml/apps/games/roms, persists library
        order and per-game settings, and launches validated emulators on a
        dedicated virtual terminal so NeutronShell can remain resident.
    */
    GamesManager gamesManager(neutronRoot);
    QObject::connect(&userManager, &UserManager::activeUserChanged, &assetManager, &AssetManager::refresh);
    QObject::connect(&userManager, &UserManager::activeUserChanged, &packageAppBridgeManager, &PackageAppBridgeManager::stopAll);
    QObject::connect(&userManager, &UserManager::activeUserChanged, &browserManager,
                     &BrowserManager::humanSessionChanged);
    QObject::connect(&userManager, &UserManager::activeUserChanged, &gamesManager,
                     &GamesManager::humanSessionChanged);
    QObject::connect(&userManager, &UserManager::activeUserChanged, &appStoreManager,
                     &AppStoreManager::reload);


    /*
        Native controller-first Docker, Logs, and Media Optimizer backends.
        Docker and Logs execute only validated argument lists. Media Optimizer
        checks the authoritative DeveloperModeManager before video transcoding.
    */
    DockerManager dockerManager;
    LogsManager logsManager(neutronRoot);
    MediaOptimizerManager mediaOptimizerManager(neutronRoot, &developerModeManager);

    /*
        Notification Center event pipeline.

        Connections live in C++ so important events are retained even while
        Console.qml is unloaded for an active app or Leave Running session.
        QML owns presentation only; persistence and deduplication stay native.
    */
    auto postNotification = [&notificationManager](const QString &category,
                                                   const QString &title,
                                                   const QString &message,
                                                   const QString &priority,
                                                   const QString &source,
                                                   const QString &action = QString(),
                                                   const QVariantMap &payload = QVariantMap()) {
        notificationManager.publish(category, title, message, priority, source, action, payload);
    };

    QObject::connect(&securityManager, &SecurityManager::lockoutStarted,
                     &notificationManager, [postNotification]() {
        postNotification(QStringLiteral("security"),
                         QStringLiteral("Security lockout active"),
                         QStringLiteral("Repeated authentication failures triggered a temporary NeutronOS lockout."),
                         QStringLiteral("critical"),
                         QStringLiteral("Security"));
    });

    QObject::connect(&securityManager, &SecurityManager::operationFinished,
                     &notificationManager,
                     [postNotification](const QString &action, bool success,
                                        const QString &message, const QVariantMap &payload) {
        if (!success) {
            postNotification(QStringLiteral("security"),
                             QStringLiteral("Security operation failed"),
                             message.isEmpty() ? action + QStringLiteral(" failed.") : message,
                             QStringLiteral("critical"),
                             QStringLiteral("Security"),
                             QStringLiteral("open-settings-security"), payload);
        }
    });

    QObject::connect(&securityCoreManager, &SecurityCoreManager::securityEventRaised,
                     &notificationManager, [postNotification](const QVariantMap &event) {
        const int severity = event.value(QStringLiteral("severity"), 1).toInt();
        postNotification(QStringLiteral("security"),
                         event.value(QStringLiteral("title"), QStringLiteral("Security event")).toString(),
                         event.value(QStringLiteral("message"), QStringLiteral("The Security Core reported a new event.")).toString(),
                         severity >= 4 ? QStringLiteral("critical") : severity >= 3 ? QStringLiteral("warning") : QStringLiteral("info"),
                         QStringLiteral("Security Core"), QStringLiteral("open-security"), event);
    });

    QObject::connect(&systemMonitor, &SystemMonitor::thermalThrottledChanged,
                     &notificationManager, [&systemMonitor, postNotification]() {
        if (!systemMonitor.thermalThrottled())
            return;
        postNotification(QStringLiteral("system"),
                         QStringLiteral("Thermal throttling detected"),
                         QStringLiteral("The system reduced performance to protect the hardware. Status: ")
                             + systemMonitor.thermalStatus(),
                         QStringLiteral("critical"),
                         QStringLiteral("System Monitor"),
                         QStringLiteral("open-logs"));
    });

    QObject::connect(&systemMonitor, &SystemMonitor::throttlingEventsChanged,
                     &notificationManager,
                     [&systemMonitor, postNotification,
                      lastThrottleCount = systemMonitor.throttlingEvents()]() mutable {
        const int count = systemMonitor.throttlingEvents();
        if (count > lastThrottleCount) {
            postNotification(QStringLiteral("system"),
                             QStringLiteral("New throttle event"),
                             QStringLiteral("Check cooling, power delivery, and CPU temperature."),
                             QStringLiteral("warning"),
                             QStringLiteral("System Monitor"),
                             QStringLiteral("open-logs"));
        }
        lastThrottleCount = count;
    });

    QObject::connect(&appManager, &AppManager::appActionFinished,
                     &notificationManager,
                     [postNotification](const QString &appId, const QString &action,
                                        bool success, const QString &message) {
        if (!success) {
            postNotification(QStringLiteral("apps"),
                             QStringLiteral("Application action failed"),
                             message.isEmpty() ? appId + QStringLiteral(" ") + action + QStringLiteral(" failed.") : message,
                             QStringLiteral("warning"), appId,
                             QStringLiteral("open-app-manager"));
        }
    });

    QObject::connect(&quickActionManager, &QuickActionManager::actionFinished,
                     &notificationManager,
                     [postNotification](const QString &actionId, bool success, const QString &message) {
        if (!success) {
            postNotification(QStringLiteral("system"),
                             QStringLiteral("Quick action failed"),
                             message.isEmpty() ? actionId + QStringLiteral(" failed.") : message,
                             QStringLiteral("warning"),
                             QStringLiteral("Quick Actions"));
        }
    });

    QObject::connect(&settingsManager, &SettingsManager::operationFinished,
                     &notificationManager,
                     [postNotification](const QString &action, bool success, const QString &message) {
        if (!success) {
            postNotification(QStringLiteral("system"),
                             QStringLiteral("Settings operation failed"),
                             message.isEmpty() ? action + QStringLiteral(" failed.") : message,
                             QStringLiteral("warning"),
                             QStringLiteral("Settings"),
                             QStringLiteral("open-settings"));
        }
    });

    QObject::connect(&networkManager, &NetworkManager::operationFinished,
                     &notificationManager,
                     [postNotification](const QString &action, bool success,
                                        const QString &message, const QVariantMap &payload) {
        if (!success) {
            postNotification(QStringLiteral("network"),
                             QStringLiteral("Network operation failed"),
                             message.isEmpty() ? action + QStringLiteral(" failed.") : message,
                             QStringLiteral("warning"),
                             QStringLiteral("Network"),
                             QStringLiteral("open-settings-network"), payload);
        }
    });

    QObject::connect(&storageManager, &StorageManager::operationFinished,
                     &notificationManager,
                     [postNotification](bool success, const QString &message) {
        postNotification(QStringLiteral("storage"),
                         success ? QStringLiteral("Storage operation complete")
                                 : QStringLiteral("Storage operation failed"),
                         message,
                         success ? QStringLiteral("success") : QStringLiteral("warning"),
                         QStringLiteral("Storage"),
                         QStringLiteral("open-storage"));
    });

    QObject::connect(&storageManager, &StorageManager::optimizationFinished,
                     &notificationManager,
                     [postNotification](bool success, const QString &message) {
        postNotification(QStringLiteral("storage"),
                         success ? QStringLiteral("Storage optimization ready")
                                 : QStringLiteral("Storage optimization failed"),
                         message,
                         success ? QStringLiteral("success") : QStringLiteral("warning"),
                         QStringLiteral("Storage"),
                         QStringLiteral("open-storage"));
    });

    QObject::connect(&updateRecoveryManager, &UpdateRecoveryManager::operationFinished,
                     &notificationManager,
                     [postNotification](const QString &operation, bool success, const QString &message) {
        postNotification(QStringLiteral("updates"),
                         success ? QStringLiteral("Update & Recovery complete")
                                 : QStringLiteral("Update & Recovery failed"),
                         message.isEmpty() ? operation : message,
                         success ? QStringLiteral("success") : QStringLiteral("critical"),
                         QStringLiteral("Update & Recovery"),
                         QStringLiteral("open-settings-updates"));
    });

    QObject::connect(&appStoreManager, &AppStoreManager::operationFinished,
                     &notificationManager,
                     [postNotification](const QString &packageId, const QString &operation,
                                        bool success, const QString &message) {
        postNotification(
            QStringLiteral("apps"),
            success ? QStringLiteral("App Store completed")
                    : QStringLiteral("App Store action failed"),
            message,
            success ? QStringLiteral("success") : QStringLiteral("error"),
            QStringLiteral("appstore"),
            packageId + QStringLiteral(":") + operation,
            QVariantMap{{QStringLiteral("packageId"), packageId},
                        {QStringLiteral("operation"), operation}}
        );
    });

    QObject::connect(&musicPlayerManager, &MusicPlayerManager::scanFinished,
                     &notificationManager,
                     [postNotification](bool success, const QString &message) {
        postNotification(QStringLiteral("media"),
                         success ? QStringLiteral("Music library ready")
                                 : QStringLiteral("Music library scan failed"),
                         message,
                         success ? QStringLiteral("success") : QStringLiteral("warning"),
                         QStringLiteral("Music Player"),
                         QStringLiteral("open-musicplayer"));
    });

    QObject::connect(&musicPlayerManager, &MusicPlayerManager::playbackError,
                     &notificationManager,
                     [postNotification](const QString &message) {
        postNotification(QStringLiteral("media"),
                         QStringLiteral("Music playback error"),
                         message,
                         QStringLiteral("warning"),
                         QStringLiteral("Music Player"),
                         QStringLiteral("open-musicplayer"));
    });

    QObject::connect(&backupRestoreManager, &BackupRestoreManager::operationFinished,
                     &notificationManager,
                     [postNotification](const QString &operation, bool success, const QString &message) {
        postNotification(QStringLiteral("backup"),
                         success ? QStringLiteral("Backup & Restore complete")
                                 : QStringLiteral("Backup & Restore failed"),
                         message.isEmpty() ? operation : message,
                         success ? QStringLiteral("success") : QStringLiteral("critical"),
                         QStringLiteral("Backup & Restore"),
                         QStringLiteral("open-settings-backup"));
    });

    QObject::connect(&dockerManager, &DockerManager::operationFinished,
                     &notificationManager,
                     [postNotification](bool success, const QString &message) {
        postNotification(QStringLiteral("docker"),
                         success ? QStringLiteral("Docker operation complete")
                                 : QStringLiteral("Docker operation failed"),
                         message,
                         success ? QStringLiteral("success") : QStringLiteral("warning"),
                         QStringLiteral("Docker"),
                         QStringLiteral("open-docker"));
    });

    QObject::connect(&mediaOptimizerManager, &MediaOptimizerManager::scanFinished,
                     &notificationManager,
                     [postNotification](bool success, const QString &message) {
        postNotification(QStringLiteral("media"),
                         success ? QStringLiteral("Media scan complete")
                                 : QStringLiteral("Media scan failed"),
                         message,
                         success ? QStringLiteral("success") : QStringLiteral("warning"),
                         QStringLiteral("Media Optimizer"),
                         QStringLiteral("open-mediaoptimizer"));
    });

    QObject::connect(&mediaOptimizerManager, &MediaOptimizerManager::optimizationFinished,
                     &notificationManager,
                     [postNotification](bool success, const QString &message, const QString &outputPath) {
        QVariantMap payload;
        payload[QStringLiteral("outputPath")] = outputPath;
        postNotification(QStringLiteral("media"),
                         success ? QStringLiteral("Media optimization complete")
                                 : QStringLiteral("Media optimization failed"),
                         message,
                         success ? QStringLiteral("success") : QStringLiteral("warning"),
                         QStringLiteral("Media Optimizer"),
                         QStringLiteral("open-mediaoptimizer"), payload);
    });

    QObject::connect(&gamesManager, &GamesManager::gameLaunchFailed,
                     &notificationManager, [postNotification](const QString &message) {
        postNotification(QStringLiteral("games"),
                         QStringLiteral("Game launch failed"), message,
                         QStringLiteral("warning"), QStringLiteral("Games"),
                         QStringLiteral("open-games"));
    });

    QObject::connect(&gamesManager, &GamesManager::emulatorInstallFinished,
                     &notificationManager,
                     [postNotification](bool success, const QString &message) {
        postNotification(QStringLiteral("games"),
                         success ? QStringLiteral("Emulator installed")
                                 : QStringLiteral("Emulator installation failed"),
                         message,
                         success ? QStringLiteral("success") : QStringLiteral("warning"),
                         QStringLiteral("Games"),
                         QStringLiteral("open-games"));
    });

    QObject::connect(&gamesManager, &GamesManager::gameStopped,
                     &notificationManager,
                     [postNotification](const QString &, const QString &title, bool cleanExit) {
        postNotification(QStringLiteral("games"),
                         cleanExit ? QStringLiteral("Game session ended")
                                   : QStringLiteral("Game closed with an error"),
                         title,
                         cleanExit ? QStringLiteral("info") : QStringLiteral("warning"),
                         QStringLiteral("Games"),
                         QStringLiteral("open-games"));
    });

    /*
        Terminal backend.

        Owns:
            - shared PTY session
            - HDMI/QML terminal bridge
            - web mirror backend
            - copy/paste bridge
            - quick commands
            - regular/developer shell mode based on DeveloperModeManager
    */
    TerminalAssistManager terminalAssistManager;
    TerminalManager terminalManager(&developerModeManager);
    terminalManager.setAssistManager(&terminalAssistManager);

    QObject::connect(
        &terminalManager,
        &TerminalManager::inputDraftChanged,
        &terminalAssistManager,
        [&terminalAssistManager](const QString &text, const QString &) {
            terminalAssistManager.observeDraft(text);
        });

    QObject::connect(
        &terminalManager,
        &TerminalManager::commandCommitted,
        &terminalAssistManager,
        [&terminalAssistManager](const QString &command, const QString &) {
            terminalAssistManager.recordCommand(command);
        });

    QObject::connect(
        &captureManager,
        &CaptureManager::screenshotSaved,
        &galleryManager,
        [&galleryManager](const QString &) { galleryManager.refresh(); }
    );
    QObject::connect(
        &captureManager,
        &CaptureManager::recordingStopped,
        &galleryManager,
        [&galleryManager](const QString &) { galleryManager.refresh(); }
    );

    /*
        ============================================================
                        QML CONTEXT PROPERTIES
        ============================================================
    */

    exposeSystemContext(engine, neutronRoot);
    engine.rootContext()->setContextProperty(
        QStringLiteral("neutronSafeMode"),
        qEnvironmentVariableIsSet("NEUTRONOS_SAFE_MODE")
    );

    engine.rootContext()->setContextProperty(QStringLiteral("userManager"), &userManager);
    engine.rootContext()->setContextProperty(QStringLiteral("assetManager"), &assetManager);
    engine.rootContext()->setContextProperty(QStringLiteral("controllerManager"), &controllerManager);
    engine.rootContext()->setContextProperty(QStringLiteral("securityManager"), &securityManager);
    engine.rootContext()->setContextProperty(QStringLiteral("securityCoreManager"), &securityCoreManager);
    engine.rootContext()->setContextProperty(QStringLiteral("systemMonitor"), &systemMonitor);
    engine.rootContext()->setContextProperty(QStringLiteral("dashboardLayoutManager"), &dashboardLayoutManager);
    engine.rootContext()->setContextProperty(QStringLiteral("storageManager"), &storageManager);
    engine.rootContext()->setContextProperty(QStringLiteral("clockSettingsManager"), &clockSettingsManager);
    engine.rootContext()->setContextProperty(QStringLiteral("clockExperienceManager"), &clockExperienceManager);
    engine.rootContext()->setContextProperty(QStringLiteral("networkManager"), &networkManager);

    /*
        Transitional compatibility.

        Current backend class:
            AppManager

        QML-compatible names:
            appManager
            appLauncher
    */
    engine.rootContext()->setContextProperty(QStringLiteral("appManager"), &appManager);
    engine.rootContext()->setContextProperty(QStringLiteral("appLauncher"), &appManager);

    engine.rootContext()->setContextProperty(QStringLiteral("quickActionManager"), &quickActionManager);
    engine.rootContext()->setContextProperty(QStringLiteral("screensaverManager"), &screensaverManager);
    engine.rootContext()->setContextProperty(QStringLiteral("dockSecurityManager"), &dockSecurityManager);

    engine.rootContext()->setContextProperty(QStringLiteral("developerModeManager"), &developerModeManager);
    engine.rootContext()->setContextProperty(QStringLiteral("privilegeManager"), &privilegeManager);
    engine.rootContext()->setContextProperty(QStringLiteral("powerModeManager"), &powerModeManager);
    engine.rootContext()->setContextProperty(QStringLiteral("performanceManager"), &performanceManager);
    engine.rootContext()->setContextProperty(QStringLiteral("personalizationManager"), &personalizationManager);
    engine.rootContext()->setContextProperty(QStringLiteral("settingsManager"), &settingsManager);
    engine.rootContext()->setContextProperty(QStringLiteral("updateRecoveryManager"), &updateRecoveryManager);
    engine.rootContext()->setContextProperty(QStringLiteral("backupRestoreManager"), &backupRestoreManager);
    engine.rootContext()->setContextProperty(QStringLiteral("diagnosticsManager"), &diagnosticsManager);
    engine.rootContext()->setContextProperty(QStringLiteral("coreCapabilitiesManager"), &coreCapabilitiesManager);
    engine.rootContext()->setContextProperty(QStringLiteral("notificationManager"), &notificationManager);
    engine.rootContext()->setContextProperty(QStringLiteral("captureManager"), &captureManager);
    engine.rootContext()->setContextProperty(QStringLiteral("browserManager"), &browserManager);
    engine.rootContext()->setContextProperty(QStringLiteral("appHostStartupReturnSession"), appHostStartupReturnSession);
    engine.rootContext()->setContextProperty(QStringLiteral("appStoreManager"), &appStoreManager);
    engine.rootContext()->setContextProperty(QStringLiteral("packageAppBridgeManager"), &packageAppBridgeManager);
    engine.rootContext()->setContextProperty(QStringLiteral("galleryManager"), &galleryManager);
    engine.rootContext()->setContextProperty(QStringLiteral("textEditorManager"), &textEditorManager);
    engine.rootContext()->setContextProperty(QStringLiteral("musicPlayerManager"), &musicPlayerManager);
    engine.rootContext()->setContextProperty(QStringLiteral("qbitManager"), &qbitTorrentManager);
    engine.rootContext()->setContextProperty(QStringLiteral("setupWizardManager"), &setupWizardManager);
    engine.rootContext()->setContextProperty(QStringLiteral("terminalManager"), &terminalManager);
    engine.rootContext()->setContextProperty(QStringLiteral("terminalAssistManager"), &terminalAssistManager);

    engine.rootContext()->setContextProperty(QStringLiteral("fileManager"), &fileManager);
    engine.rootContext()->setContextProperty(QStringLiteral("fileManagerBackend"), &fileManager);
    engine.rootContext()->setContextProperty(QStringLiteral("gamesManager"), &gamesManager);
    engine.rootContext()->setContextProperty(QStringLiteral("dockerManager"), &dockerManager);
    engine.rootContext()->setContextProperty(QStringLiteral("logsManager"), &logsManager);
    engine.rootContext()->setContextProperty(QStringLiteral("mediaOptimizerManager"), &mediaOptimizerManager);

    /*
        Future web-controller backend note.

        When WebControllerManager exists, expose it as:
            webControllerManager

        Main.qml already safely checks for:
            webControllerManager
            webController
    */

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [mainQmlPath](QObject *object, const QUrl &objectUrl) {
            if (object)
                return;

            qCritical() << "NeutronShell failed to load root QML:" << objectUrl;
            qCritical() << "Expected filesystem path:" << mainQmlPath;

            QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection
    );

    if (!QFileInfo::exists(mainQmlPath)) {
        qCritical() << "Missing Main.qml:" << mainQmlPath;
        qCritical() << "Set NEUTRONOS_ROOT or run from a valid ~/NeutronOS tree.";
        return -1;
    }

    qInfo() << "NeutronShell loading filesystem QML:" << mainQmlPath;
    qInfo() << "NeutronOS root:" << neutronRoot;
    qInfo() << "NeutronOS QML path:" << qmlRoot;
    qInfo() << "NeutronOS apps path:" << qmlRoot + QStringLiteral("/apps");
    qInfo() << "NeutronOS theme path:" << neutronRoot + QStringLiteral("/themes/Default");
    qInfo() << "NeutronOS state path:" << QStringLiteral(NEUTRONOS_STATE_DIR);
    qInfo() << "NeutronOS security path:" << QStringLiteral(NEUTRONOS_SECURITY_STATE_DIR);

    QObject *shellWindow = engine.rootObjects().constFirst();
    if (!QMetaObject::invokeMethod(shellWindow, "loadShell", Qt::DirectConnection)) {
        qCritical() << "NeutronShell single-window root rejected Main.qml loading";
        return -1;
    }

    if (smokeTest) {
        QElapsedTimer deadline;
        deadline.start();
        const int smokeTimeout = qEnvironmentVariableIntValue(
            "NEUTRONOS_SMOKE_TIMEOUT_MS") > 0
            ? qEnvironmentVariableIntValue("NEUTRONOS_SMOKE_TIMEOUT_MS")
            : 60000;
        while (!QQmlProperty::read(shellWindow,
                                   QStringLiteral("smokeUiReady")).toBool()
               && deadline.elapsed() < smokeTimeout) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
            QThread::msleep(2);
        }
        if (!QQmlProperty::read(shellWindow,
                                QStringLiteral("smokeUiReady")).toBool()) {
            qCritical() << "NeutronShell smoke test timed out before graphical destination readiness";
            return 1;
        }
        qInfo() << "NeutronShell smoke test loaded the graphical destination";
        shellWindow->deleteLater();
        QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
        return 0;
    }

    return app.exec();
}

#include "main.moc"
