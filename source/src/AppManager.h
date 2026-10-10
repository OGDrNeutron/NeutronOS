#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QStringList>
#include <QSet>
#include <QHash>
#include <QDateTime>

class BrowserManager;

class AppManager : public QObject
{
    Q_OBJECT

    /*
        ============================================================
                            APP REGISTRY STATE
        ============================================================

        Filesystem-first app model.

        Apps can be dropped into:
            ~/NeutronOS/qml/apps/<appId>/Main.qml

        Optional manifest:
            ~/NeutronOS/qml/apps/<appId>/app.json

        No rebuild required for:
            - new QML app folders
            - app manifests
            - icon/poster/background swaps
    */

    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
    Q_PROPERTY(QVariantList dashboardApps READ dashboardApps NOTIFY appsChanged)
    Q_PROPERTY(QVariantList favoriteApps READ favoriteApps NOTIFY appsChanged)
    Q_PROPERTY(QVariantList hiddenApps READ hiddenApps NOTIFY appsChanged)

    Q_PROPERTY(int appCount READ appCount NOTIFY appsChanged)
    Q_PROPERTY(int favoriteAppCount READ favoriteAppCount NOTIFY appsChanged)
    Q_PROPERTY(int hiddenAppCount READ hiddenAppCount NOTIFY appsChanged)

    Q_PROPERTY(QString neutronRoot READ neutronRootPath CONSTANT)
    Q_PROPERTY(QString appsRoot READ appsRootPath CONSTANT)
    Q_PROPERTY(QVariantList runningApps READ runningApps NOTIFY runningAppsChanged)
    Q_PROPERTY(int runningAppCount READ runningAppCount NOTIFY runningAppsChanged)

public:
    explicit AppManager(QObject *parent = nullptr);

    QVariantList apps() const;
    QVariantList dashboardApps() const;
    QVariantList favoriteApps() const;
    QVariantList hiddenApps() const;

    int appCount() const;
    int favoriteAppCount() const;
    int hiddenAppCount() const;
    QVariantList runningApps() const;
    int runningAppCount() const;

    /*
        Runtime paths exposed for QML/testing.
    */
    Q_INVOKABLE QString neutronRootPath() const;
    Q_INVOKABLE QString appsRootPath() const;

    /*
        Reload / discovery.

        reloadApps():
            Rebuild registry from filesystem/config/built-ins.

        rediscoverApps():
            Alias for reloadApps(), kept for QML compatibility.

        refreshStatuses():
            Refresh running/active states without rebuilding the app list.
    */
    Q_INVOKABLE void reloadApps();
    Q_INVOKABLE void rediscoverApps();
    Q_INVOKABLE void refreshStatuses();
    Q_INVOKABLE bool setActiveUser(const QString &username);

    /*
        Lookup helpers for QML/AppHost.
    */
    Q_INVOKABLE QVariantMap appById(const QString &appId) const;
    Q_INVOKABLE QVariantMap appAt(int index) const;
    Q_INVOKABLE bool hasApp(const QString &appId) const;
    Q_INVOKABLE bool hasQmlEntry(const QVariantMap &appData) const;
    Q_INVOKABLE QString resolveQmlEntry(const QVariantMap &appData) const;

    /*
        Service/app control.

        These are intentionally backend-safe. If an app is a QML-only app,
        start/open/launch marks the UI session open. If the app is tied to
        Docker or systemd, service control is attempted.
    */
    Q_INVOKABLE void startApp(const QVariantMap &appData);
    Q_INVOKABLE void stopApp(const QVariantMap &appData);
    Q_INVOKABLE void restartApp(const QVariantMap &appData);

    Q_INVOKABLE bool prepareAppForLaunch(const QVariantMap &appData);
    Q_INVOKABLE bool launchApp(const QVariantMap &appData);
    Q_INVOKABLE bool openApp(const QVariantMap &appData);
    Q_INVOKABLE bool closeApp(const QVariantMap &appData);
    Q_INVOKABLE bool launchExternalRuntime(const QVariantMap &appData);
    Q_INVOKABLE bool focusApp(const QVariantMap &appData);
    Q_INVOKABLE bool suspendApp(const QVariantMap &appData);
    Q_INVOKABLE bool resumeApp(const QVariantMap &appData);
    Q_INVOKABLE QVariantMap runtimeState(const QString &appId) const;
    Q_INVOKABLE QVariantMap consumeExternalReturnSession();
    Q_INVOKABLE bool focusRuntime(const QString &runtimeId);
    Q_INVOKABLE bool closeRuntime(const QString &runtimeId);

    void setBrowserManager(BrowserManager *browserManager);

    Q_INVOKABLE bool executeAppAction(const QVariantMap &appData, const QString &actionName);
    Q_INVOKABLE bool runAppAction(const QVariantMap &appData, const QString &actionName);
    Q_INVOKABLE bool serviceAction(const QVariantMap &appData, const QString &actionName);

    /*
        User-controlled carousel organization.

        The registry remains filesystem-first. These methods only persist
        favorite state and the visible favorite order in NeutronOS state.
    */
    Q_INVOKABLE bool setFavorite(const QString &appId, bool favorite);
    Q_INVOKABLE bool makeFavoriteFirst(const QString &appId);
    Q_INVOKABLE bool moveFavorite(const QString &appId, int targetIndex);
    Q_INVOKABLE bool moveFavoriteBy(const QString &appId, int delta);
    Q_INVOKABLE bool pinApp(const QString &appId, int slot);
    Q_INVOKABLE bool unpinApp(const QString &appId);
    Q_INVOKABLE int pinnedSlotForApp(const QString &appId) const;
    Q_INVOKABLE QVariantMap pinnedAppAt(int slot) const;

    /*
        Authenticated uninstall is initiated by QML only after the login
        combo has been verified. The backend still enforces path ownership
        and refuses to remove core/built-in or system-owned applications.
    */
    Q_INVOKABLE bool canUninstallApp(const QVariantMap &appData) const;
    Q_INVOKABLE bool uninstallApp(const QVariantMap &appData);

    /*
        Settings > Apps & Services management surface. These methods expose
        only measured/validated data and operate solely on NeutronOS-owned
        cache and application paths.
    */
    Q_INVOKABLE QVariantList installedApps() const;
    Q_INVOKABLE QVariantMap appCardInfo(const QVariantMap &appData) const;
    Q_INVOKABLE QVariantMap appManagementDetails(const QVariantMap &appData) const;
    Q_INVOKABLE QVariantMap jellyfinBackendState() const;
    Q_INVOKABLE bool ensureJellyfinBackendReady();
    Q_INVOKABLE bool requestJellyfinBackendRecovery();
    Q_INVOKABLE bool clearAppCache(const QVariantMap &appData);
    Q_INVOKABLE QString formatBytes(qulonglong bytes) const;

    /*
        AppHost lifecycle notifications.

        AppHost calls these when a QML app becomes active or closes so the
        console carousel can show running/session state immediately.
    */
    Q_INVOKABLE void appLaunched(const QString &appId);
    Q_INVOKABLE void appClosed(const QString &appId);
    Q_INVOKABLE void appBackgrounded(const QString &appId);

signals:
    void appsChanged();
    void appActionFinished(QString appId, QString actionName, bool success, QString message);
    void runningAppsChanged();
    void runtimeFocusRequested(QVariantMap appData);

private:
    QVariantList m_apps;
    QVariantList m_favoriteApps;
    QVariantList m_hiddenApps;

    /*
        Prevent duplicate app IDs when a built-in app also exists as a
        filesystem drop-in folder.
    */
    QSet<QString> m_seenAppIds;
    QSet<QString> m_managedPackageIds;
    // App Store installs launch through an immutable, generation-specific QML
    // runtime tree. A unique absolute source path prevents QQmlEngine from
    // reusing child components compiled for an older package generation.
    QHash<QString, QString> m_managedRuntimeQmlSources;
    QString m_activeCarouselUser = QStringLiteral("default");

    QHash<QString, bool> m_favoriteOverrides;
    QStringList m_favoriteOrder;
    QStringList m_pinnedApps;
    QHash<QString, QString> m_lastUsedByApp;
    QSet<QString> m_backgroundApps;
    bool m_runtimeStatusQueriesEnabled = false;
    BrowserManager *m_browserManager = nullptr;
    QVariantList m_runningApps;
    QHash<QString, QDateTime> m_runtimeLaunchTimes;

    void discoverAppsOnce();
    void refreshStatusesOnce();

    void discoverNeutronApps();
    void discoverExternalNeutronAppDirs();
    void discoverConfigApps();
    void discoverDesktopApps();
    void discoverBuiltInApps();

    void rebuildDerivedLists();
    void addApp(const QVariantMap &app);
    void updateAppStatus(const QString &appId, bool uiRunning);
    void rebuildRunningApps();
    QVariantMap runningEntry(const QString &runtimeId) const;

    QString carouselStatePath() const;
    QString legacyCarouselStatePath() const;
    void loadCarouselState();
    void loadManagedPackageIds();
    bool saveCarouselState() const;

    QString usageStatePath() const;
    void loadUsageState();
    bool saveUsageState() const;
    void recordAppUsed(const QString &appId);

    quint64 pathSize(const QString &path) const;
    QStringList managedStoragePaths(const QVariantMap &app) const;
    QStringList managedCachePaths(const QVariantMap &app) const;
    bool removeManagedPath(const QString &path, const QStringList &allowedRoots) const;
    bool automaticLoginEnabled() const;
    bool highPriorityAuthorizedForSettings() const;

    QVariantMap normalizeApp(QVariantMap app) const;
    QVariantMap withLiveStatus(QVariantMap app) const;

    QVariantMap readNeutronManifest(const QString &manifestPath) const;
    bool hasValidDashboardManifest(const QVariantMap &app) const;
    QVariantMap readDesktopFile(const QString &desktopPath, int priority) const;
    QVariantMap readJsonAppFile(const QString &path, int priority, const QString &sourceName) const;

    QStringList neutronAppSearchPaths() const;
    QStringList configAppSearchPaths() const;

    QString cleanDesktopExec(const QString &exec) const;
    QString firstCommandToken(const QString &command) const;
    QString safeId(const QString &value) const;
    QString normalizedType(const QString &type) const;
    QString displayNameFromId(const QString &id) const;

    QString resolveQmlEntryPath(const QVariantMap &app) const;
    QString resolveQmlSource(const QVariantMap &app) const;

    QVariantList stringListToVariantList(const QStringList &values) const;

    bool qmlEntryExists(const QVariantMap &app) const;

    bool commandExists(const QString &command) const;
    bool systemdUnitExists(const QString &unit) const;
    bool systemdUnitActive(const QString &unit) const;

    bool dockerExists() const;
    bool dockerContainerExists(const QString &name) const;
    bool dockerContainerRunning(const QString &name) const;

    bool runSystemdAction(const QString &unit, const QString &actionName, QString *message);
    bool runDockerAction(const QString &container, const QString &actionName, QString *message);
    bool ensureBackendReady(const QVariantMap &app, QString *message);
    bool waitForSystemdActive(const QString &unit, int timeoutMs) const;
    bool waitForDockerRunning(const QString &container, int timeoutMs) const;

    int runProcess(
        const QString &program,
        const QStringList &arguments,
        int timeoutMs,
        QString *standardOutput = nullptr,
        QString *standardError = nullptr
    ) const;
};
