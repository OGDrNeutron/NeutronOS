#pragma once

#include <QObject>
#include <QFileDevice>
#include <QProcess>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class SetupWizardManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool setupRequired READ setupRequired NOTIFY setupStateChanged)
    Q_PROPERTY(bool setupComplete READ setupComplete NOTIFY setupStateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY operationChanged)
    Q_PROPERTY(QString status READ status NOTIFY operationChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY operationChanged)

    Q_PROPERTY(bool bluetoothAvailable READ bluetoothAvailable NOTIFY bluetoothChanged)
    Q_PROPERTY(bool bluetoothScanning READ bluetoothScanning NOTIFY bluetoothChanged)
    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY bluetoothChanged)
    Q_PROPERTY(QString rememberedUsbController READ rememberedUsbController NOTIFY bluetoothChanged)
    Q_PROPERTY(bool controllerPaired READ controllerPaired NOTIFY bluetoothChanged)

    Q_PROPERTY(QVariantList recoveryTargets READ recoveryTargets NOTIFY recoveryChanged)
    Q_PROPERTY(QString recoveryCode READ recoveryCode NOTIFY recoveryChanged)
    Q_PROPERTY(bool recoveryWritten READ recoveryWritten NOTIFY recoveryChanged)
    Q_PROPERTY(QString remoteControllerToken READ remoteControllerToken NOTIFY releasePreferencesChanged)
    Q_PROPERTY(QVariantList setupDomains READ setupDomains NOTIFY setupStateChanged)
    Q_PROPERTY(QVariantMap storagePlan READ storagePlan NOTIFY storageChanged)
    Q_PROPERTY(bool storageBusy READ storageBusy NOTIFY storageChanged)
    Q_PROPERTY(QString storageStage READ storageStage NOTIFY storageChanged)
    Q_PROPERTY(bool loginInstructionsPending READ loginInstructionsPending NOTIFY setupStateChanged)

public:
    explicit SetupWizardManager(const QString &neutronRoot,
                                QObject *parent = nullptr);
    ~SetupWizardManager() override;

    bool setupRequired() const;
    bool setupComplete() const;
    bool busy() const;
    QString status() const;
    QString lastError() const;

    bool bluetoothAvailable() const;
    bool bluetoothScanning() const;
    QVariantList bluetoothDevices() const;
    QString rememberedUsbController() const;
    bool controllerPaired() const;

    QVariantList recoveryTargets() const;
    QString recoveryCode() const;
    bool recoveryWritten() const;
    QString remoteControllerToken() const;
    QVariantList setupDomains() const { return m_setupDomains; }
    Q_INVOKABLE QString domainStatus(const QString &domainId) const;
    QVariantMap storagePlan() const { return m_storagePlan; }
    bool storageBusy() const { return m_storageBusy; }
    QString storageStage() const { return m_storageStage; }
    bool loginInstructionsPending() const { return m_setupComplete && !m_loginInstructionsAcknowledged; }
    Q_INVOKABLE bool refreshStoragePlan();
    Q_INVOKABLE bool provisionStorage(const QString &fingerprint);
    Q_INVOKABLE bool acknowledgeLoginInstructions();

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool applyRegion(const QString &timezone,
                                 const QString &locale,
                                 const QString &keyboardLayout);
    Q_INVOKABLE bool applyIdentity(const QString &hostname,
                                   const QString &username,
                                   const QString &displayName,
                                   const QString &password);

    Q_INVOKABLE void rememberUsbController(const QString &controllerName,
                                           const QString &devicePath = QString());
    Q_INVOKABLE bool confirmControllerRegistration();
    Q_INVOKABLE bool startBluetoothScan();
    Q_INVOKABLE void stopBluetoothScan();
    Q_INVOKABLE void refreshBluetoothDevices();
    Q_INVOKABLE bool pairAndTrustController(const QString &address,
                                            const QString &currentUsbControllerName);

    Q_INVOKABLE void refreshRecoveryTargets();
    Q_INVOKABLE QString ensureRecoveryCode();
    Q_INVOKABLE bool writeRecoveryDrive(const QString &mountPath);

    Q_INVOKABLE bool savePreferences(const QVariantMap &preferences);
    Q_INVOKABLE bool completeSetup();
    Q_INVOKABLE bool recordOptionalStep(const QString &step, bool skipped);
    Q_INVOKABLE bool resetSetupForNextBoot();

    Q_INVOKABLE QVariantMap registerAppOpen(const QString &username,
                                            const QString &appId);
    Q_INVOKABLE int appHelpCount(const QString &username,
                                 const QString &appId) const;
    Q_INVOKABLE bool shouldShowAppHelp(const QString &username,
                                       const QString &appId) const;
    Q_INVOKABLE bool suppressAutomaticAppHelp(const QString &username,
                                              const QString &appId);

signals:
    void setupStateChanged();
    void operationChanged();
    void bluetoothChanged();
    void recoveryChanged();
    void releasePreferencesChanged();
    void identityApplied(bool success, QString username, QString message);
    void regionApplied(bool success, QString message);
    void bluetoothOperationFinished(bool success, QString message);
    void setupCompleted();
    void storageChanged();
    void storageProgress(QString stage, QString message);
    void storageProvisioningFinished(bool success, QVariantMap result, QString message);

private slots:
    void onBluetoothProcessFinished(int exitCode,
                                    QProcess::ExitStatus exitStatus);
    void onStorageReadyRead();
    void onStorageProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onStorageProcessError(QProcess::ProcessError error);

private:
    QString m_neutronRoot;
    QString m_stateDirectory;
    bool m_setupComplete = false;
    QVariantMap m_optionalSteps;
    bool m_busy = false;
    QString m_status;
    QString m_lastError;

    bool m_bluetoothAvailable = false;
    bool m_bluetoothScanning = false;
    QVariantList m_bluetoothDevices;
    QString m_rememberedUsbController;
    QString m_rememberedUsbDevicePath;
    bool m_controllerPaired = false;
    bool m_regionConfigured = false;
    QString m_pendingBluetoothOperation;
    QString m_pendingBluetoothAddress;
    QProcess m_bluetoothProcess;

    QVariantList m_recoveryTargets;
    QString m_recoveryCode;
    bool m_recoveryWritten = false;
    QString m_remoteControllerToken;
    QVariantList m_setupDomains;
    QVariantMap m_storagePlan;
    bool m_storageBusy = false;
    QString m_storageStage;
    QByteArray m_storageOutputBuffer;
    QVariantMap m_storageResult;
    QProcess m_storageProcess;
    bool m_loginInstructionsAcknowledged = false;

    QString setupStatePath() const;
    QString preferencesPath() const;
    QString recoveryStatePath() const;
    QString appHelpStatePath() const;

    void ensureStateDirectory();
    void loadState();
    bool saveSetupState() const;
    bool existingInstallationIsConfigured() const;
    QVariantList detectSetupDomains() const;

    void setBusy(bool busy, const QString &status = QString());
    void setError(const QString &message);
    void clearError();

    static QString normalizedUsername(const QString &username);
    static QString normalizedHostname(const QString &hostname);
    static QString normalizedControllerName(const QString &name);
    static bool safeMountPath(const QString &path);
    static bool localUserExists(const QString &username);
    static bool commandExists(const QString &command);
    static int runProcess(const QString &program,
                          const QStringList &arguments,
                          int timeoutMs,
                          QString *standardOutput = nullptr,
                          QString *standardError = nullptr,
                          const QByteArray &standardInput = QByteArray());

    bool writeJsonAtomic(const QString &path,
                         const QVariantMap &payload,
                         QFileDevice::Permissions permissions) const;
    QVariantMap readJsonMap(const QString &path) const;

    QVariantMap loadHelpState() const;
    bool saveHelpState(const QVariantMap &state) const;
    QString helpKey(const QString &username, const QString &appId) const;

    QVariantList enumerateBluetoothDevices() const;
    QVariantList enumerateRecoveryTargets() const;
    QString generateRecoveryCode() const;
};
