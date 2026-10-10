#pragma once

#include <QObject>
#include <QFutureWatcher>
#include <QMap>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>
#include <atomic>

class UserManager;
class StorageManager;
class DeveloperModeManager;
class ScreensaverManager;
class NetworkManager;
class ControllerManager;
class PowerModeManager;

class SettingsManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString themeMode READ themeMode NOTIFY themeChanged)
    Q_PROPERTY(bool darkMode READ darkMode NOTIFY themeChanged)
    Q_PROPERTY(QString dashboardMode READ dashboardMode NOTIFY dashboardModeChanged)
    Q_PROPERTY(QVariantMap values READ values NOTIFY valuesChanged)
    Q_PROPERTY(QVariantMap systemInfo READ systemInfo NOTIFY valuesChanged)
    Q_PROPERTY(QVariantMap pendingChanges READ pendingChanges NOTIFY pendingChangesChanged)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY pendingChangesChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY operationChanged)
    Q_PROPERTY(QString operationName READ operationName NOTIFY operationChanged)
    Q_PROPERTY(QString operationStatus READ operationStatus NOTIFY operationChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY operationChanged)
    Q_PROPERTY(QVariantList storageUsage READ storageUsage NOTIFY storageUsageChanged)
    Q_PROPERTY(bool storageScanBusy READ storageScanBusy NOTIFY storageUsageChanged)
    Q_PROPERTY(int storageScanProgress READ storageScanProgress NOTIFY storageUsageChanged)
    Q_PROPERTY(bool developerModeEnabled READ developerModeEnabled NOTIFY developerModeChanged)
    Q_PROPERTY(QVariantMap integrityReport READ integrityReport NOTIFY integrityReportChanged)
    Q_PROPERTY(bool integrityCheckBusy READ integrityCheckBusy NOTIFY integrityReportChanged)

public:
    explicit SettingsManager(const QString &neutronRoot,
                             UserManager *userManager,
                             StorageManager *storageManager,
                             DeveloperModeManager *developerModeManager,
                             ScreensaverManager *screensaverManager,
                             NetworkManager *networkManager,
                             ControllerManager *controllerManager,
                             PowerModeManager *powerModeManager,
                             QObject *parent = nullptr);
    ~SettingsManager() override;

    QString themeMode() const;
    bool darkMode() const;
    QString dashboardMode() const;
    QVariantMap values() const;
    QVariantMap systemInfo() const;
    QVariantMap pendingChanges() const;
    int pendingCount() const;
    bool busy() const;
    QString operationName() const;
    QString operationStatus() const;
    QString lastMessage() const;
    QVariantList storageUsage() const;
    bool storageScanBusy() const;
    int storageScanProgress() const;
    bool developerModeEnabled() const;
    QVariantMap integrityReport() const;
    bool integrityCheckBusy() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariant value(const QString &key, const QVariant &fallback = QVariant()) const;
    Q_INVOKABLE bool queueChange(const QString &key,
                                 const QVariant &value,
                                 const QString &applyMode = QStringLiteral("apply"));
    Q_INVOKABLE bool setThemeMode(const QString &mode);
    Q_INVOKABLE bool setDashboardMode(const QString &mode);
    Q_INVOKABLE bool setUiPreference(const QString &key, const QVariant &value);
    Q_INVOKABLE void discardPending();
    Q_INVOKABLE bool applyPending();
    Q_INVOKABLE QVariantMap validatePending() const;

    Q_INVOKABLE void scanStorageUsage();
    Q_INVOKABLE void cancelStorageScan();
    Q_INVOKABLE void runSystemIntegrityCheck();

    Q_INVOKABLE bool runAction(const QString &action,
                               const QVariantMap &payload = QVariantMap());
    Q_INVOKABLE bool changePassword(const QString &newPassword);
    Q_INVOKABLE bool createUser(const QString &username,
                                const QString &displayName,
                                const QString &password,
                                bool administrator);
    Q_INVOKABLE bool removeUser(const QString &username);
    Q_INVOKABLE bool connectWifi(const QString &ssid,
                                 const QString &password,
                                 const QString &country = QString());
    Q_INVOKABLE QString formatBytes(quint64 bytes) const;
    static QString humanBytes(quint64 bytes);

signals:
    void themeChanged();
    void dashboardModeChanged();
    void valuesChanged();
    void pendingChangesChanged();
    void operationChanged();
    void storageUsageChanged();
    void developerModeChanged();
    void integrityReportChanged();
    void operationFinished(const QString &action, bool success, const QString &message);
    void rebootRequired(const QString &reason);
    void logoutRequired(const QString &reason);

private slots:
    void handleStorageScanFinished();
    void handleOperationFinished(int exitCode, QProcess::ExitStatus status);
    void handleIntegrityCheckFinished();

private:
    struct PendingEntry {
        QVariant value;
        QString applyMode;
    };

    QString m_neutronRoot;
    UserManager *m_userManager = nullptr;
    StorageManager *m_storageManager = nullptr;
    DeveloperModeManager *m_developerModeManager = nullptr;
    ScreensaverManager *m_screensaverManager = nullptr;
    NetworkManager *m_networkManager = nullptr;
    ControllerManager *m_controllerManager = nullptr;
    PowerModeManager *m_powerModeManager = nullptr;

    QString m_themeMode = QStringLiteral("dark");
    QVariantMap m_values;
    QVariantMap m_systemInfo;
    QMap<QString, PendingEntry> m_pending;
    QVariantList m_storageUsage;
    bool m_storageScanBusy = false;
    int m_storageScanProgress = 0;
    std::atomic_bool m_cancelStorageScan { false };

    bool m_busy = false;
    QString m_operationName;
    QString m_operationStatus;
    QString m_lastMessage;
    QProcess m_operationProcess;
    QString m_pendingOperationAction;
    QFutureWatcher<QVariantList> m_storageWatcher;
    QFutureWatcher<QVariantMap> m_integrityWatcher;
    QVariantMap m_integrityReport;
    bool m_integrityCheckBusy = false;

    QString settingsDirectory() const;
    QString settingsPath() const;
    QString storageCachePath() const;
    void loadSettings();
    bool saveSettings() const;
    void loadStorageCache();
    bool saveStorageCache() const;
    void rebuildSystemInfo();
    void rebuildValues();
    QVariantMap buildIntegrityReport() const;
    QString bootConfigText() const;
    bool bootConfigEnabled(const QString &key, bool fallback = false) const;
    bool bootOverlayEnabled(const QString &overlayPrefix) const;
    bool serviceActive(const QStringList &units) const;
    bool serviceInstalled(const QStringList &units) const;
    QString serviceDisplayState(const QStringList &units) const;
    QVariantMap pendingVariantMap() const;
    bool applyOne(const QString &key, const QVariant &value, QString *message);
    bool writeBootConfigValue(const QString &key, const QString &value, QString *message);
    bool setServiceEnabled(const QStringList &units, bool enabled, QString *message);
    bool runCommandBlocking(const QString &program,
                            const QStringList &arguments,
                            int timeoutMs,
                            QString *output,
                            QString *message) const;
    bool startOperation(const QString &action,
                        const QString &program,
                        const QStringList &arguments,
                        const QString &statusText);
    QString activeUsername() const;
    bool validHostname(const QString &hostname) const;
    bool validUsername(const QString &username) const;
    static QVariantList buildStorageUsage(const QVariantList &devices,
                                          std::atomic_bool *cancelFlag);
    static QString readTextFile(const QString &path);
    static QString executable(const QString &name);
    static bool writeTextFileAtomically(const QString &path,
                                        const QByteArray &data,
                                        QString *message);
};
