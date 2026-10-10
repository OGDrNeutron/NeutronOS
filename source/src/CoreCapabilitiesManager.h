#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class SecurityCoreManager;

class CoreCapabilitiesManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap releaseInfo READ releaseInfo NOTIFY changed)
    Q_PROPERTY(QVariantList appPermissions READ appPermissions NOTIFY changed)
    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY changed)
    Q_PROPERTY(QVariantList audioOutputs READ audioOutputs NOTIFY changed)
    Q_PROPERTY(QVariantList displayModes READ displayModes NOTIFY changed)
    Q_PROPERTY(QVariantList services READ services NOTIFY changed)
    Q_PROPERTY(QVariantList helpSections READ helpSections NOTIFY changed)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchChanged)
    Q_PROPERTY(QVariantList networkDiagnostics READ networkDiagnostics NOTIFY changed)
    Q_PROPERTY(QVariantList securityTimeline READ securityTimeline NOTIFY changed)
    Q_PROPERTY(QVariantList securityProfiles READ securityProfiles NOTIFY changed)
    Q_PROPERTY(QString uiScale READ uiScale NOTIFY preferencesChanged)
    Q_PROPERTY(QString dndMode READ dndMode NOTIFY preferencesChanged)
    Q_PROPERTY(QString adaptiveDashboard READ adaptiveDashboard NOTIFY preferencesChanged)
    Q_PROPERTY(QString activeSecurityProfile READ activeSecurityProfile NOTIFY preferencesChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY changed)

public:
    explicit CoreCapabilitiesManager(const QString &root, SecurityCoreManager *security, QObject *parent = nullptr);
    QVariantMap releaseInfo() const { return m_releaseInfo; }
    QVariantList appPermissions() const { return m_appPermissions; }
    QVariantList bluetoothDevices() const { return m_bluetoothDevices; }
    QVariantList audioOutputs() const { return m_audioOutputs; }
    QVariantList displayModes() const { return m_displayModes; }
    QVariantList services() const { return m_services; }
    QVariantList helpSections() const { return m_helpSections; }
    QVariantList searchResults() const { return m_searchResults; }
    QVariantList networkDiagnostics() const { return m_networkDiagnostics; }
    QVariantList securityTimeline() const { return m_securityTimeline; }
    QVariantList securityProfiles() const { return m_securityProfiles; }
    QString uiScale() const { return m_uiScale; }
    QString dndMode() const { return m_dndMode; }
    QString adaptiveDashboard() const { return m_adaptiveDashboard; }
    QString activeSecurityProfile() const { return m_activeSecurityProfile; }
    QString lastMessage() const { return m_lastMessage; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool setUiScale(const QString &value);
    Q_INVOKABLE bool setDndMode(const QString &value);
    Q_INVOKABLE bool setAdaptiveDashboard(const QString &value);
    Q_INVOKABLE bool setAppPermission(const QString &appId, const QString &permission, const QString &state);
    Q_INVOKABLE bool applySecurityProfile(const QString &profile, bool confirmed = false);
    Q_INVOKABLE bool requestServiceAction(const QString &unit, const QString &action);
    Q_INVOKABLE bool requestBluetoothAction(const QString &address, const QString &action);
    Q_INVOKABLE bool setAudioVolume(int percent);
    Q_INVOKABLE bool setAudioMute(bool muted);
    Q_INVOKABLE bool testAudio(const QString &channel);
    Q_INVOKABLE bool requestDisplayMode(const QString &mode);
    Q_INVOKABLE void runNetworkDiagnostics();
    Q_INVOKABLE void search(const QString &query);

signals:
    void changed();
    void preferencesChanged();
    void searchChanged();
    void displayConfirmationRequired(const QString &mode, int seconds);

private:
    QString m_root;
    SecurityCoreManager *m_security = nullptr;
    QVariantMap m_releaseInfo;
    QVariantList m_appPermissions, m_bluetoothDevices, m_audioOutputs, m_displayModes;
    QVariantList m_services, m_helpSections, m_searchResults, m_networkDiagnostics;
    QVariantList m_securityTimeline, m_securityProfiles;
    QString m_uiScale = QStringLiteral("automatic");
    QString m_dndMode = QStringLiteral("off");
    QString m_adaptiveDashboard = QStringLiteral("subtle");
    QString m_activeSecurityProfile = QStringLiteral("NORMAL");
    QString m_lastMessage;

    QString preferencesPath() const;
    QString permissionsPath() const;
    void loadPreferences();
    bool savePreferences() const;
    void loadRelease();
    void loadPermissions();
    void loadBluetooth();
    void loadAudio();
    void loadDisplay();
    void loadServices();
    void loadHelp();
    void loadSecurity();
    static QString output(const QString &program, const QStringList &arguments, int timeout = 3000);
    static bool allowed(const QString &value, const QStringList &values);
    static QVariantMap result(const QString &name, const QString &status, const QString &summary,
                              const QString &evidence, const QString &suggestion = QString());
};
