#include "SetupWizardManager.h"
#include "HumanAccountPolicy.h"
#include <QTimer>
#include <QEventLoop>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>

#include <pwd.h>
#include <unistd.h>

#include <algorithm>
#include <functional>
#include <utility>

namespace
{
constexpr int AutomaticHelpLimit = 3;

QString cleanText(const QString &value)
{
    QString text = value.trimmed();
    text.remove(QChar::Null);
    return text;
}

QString shellQuote(QString value)
{
    value.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QStringLiteral("'") + value + QStringLiteral("'");
}

}

SetupWizardManager::SetupWizardManager(const QString &neutronRoot,
                                       QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_stateDirectory(QStringLiteral("/var/lib/neutronos/setup"))
{
    ensureStateDirectory();
    loadState();

    connect(&m_bluetoothProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            &SetupWizardManager::onBluetoothProcessFinished);

    m_storageProcess.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_storageProcess, &QProcess::readyReadStandardOutput,
            this, &SetupWizardManager::onStorageReadyRead);
    connect(&m_storageProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &SetupWizardManager::onStorageProcessFinished);
    connect(&m_storageProcess, &QProcess::errorOccurred,
            this, &SetupWizardManager::onStorageProcessError);

    QTimer::singleShot(1200, this, &SetupWizardManager::refresh);
}

SetupWizardManager::~SetupWizardManager()
{
    if (m_bluetoothProcess.state() != QProcess::NotRunning) {
        m_bluetoothProcess.kill();
        m_bluetoothProcess.waitForFinished(1000);
    }
    if (m_storageProcess.state() != QProcess::NotRunning) {
        m_storageProcess.kill();
        m_storageProcess.waitForFinished(1000);
    }
}

bool SetupWizardManager::setupRequired() const { return !m_setupComplete; }
bool SetupWizardManager::setupComplete() const { return m_setupComplete; }
bool SetupWizardManager::busy() const { return m_busy; }
QString SetupWizardManager::status() const { return m_status; }
QString SetupWizardManager::lastError() const { return m_lastError; }
bool SetupWizardManager::bluetoothAvailable() const { return m_bluetoothAvailable; }
bool SetupWizardManager::bluetoothScanning() const { return m_bluetoothScanning; }
QVariantList SetupWizardManager::bluetoothDevices() const { return m_bluetoothDevices; }
QString SetupWizardManager::rememberedUsbController() const { return m_rememberedUsbController; }
bool SetupWizardManager::controllerPaired() const { return m_controllerPaired; }
QVariantList SetupWizardManager::recoveryTargets() const { return m_recoveryTargets; }
QString SetupWizardManager::recoveryCode() const { return m_recoveryCode; }
bool SetupWizardManager::recoveryWritten() const { return m_recoveryWritten; }
QString SetupWizardManager::remoteControllerToken() const { return m_remoteControllerToken; }

QString SetupWizardManager::domainStatus(const QString &domainId) const
{
    for (const QVariant &value : m_setupDomains) {
        const QVariantMap domain = value.toMap();
        if (domain.value(QStringLiteral("id")).toString() == domainId)
            return domain.value(QStringLiteral("status")).toString();
    }
    return QStringLiteral("not-configured");
}

bool SetupWizardManager::refreshStoragePlan()
{
    clearError();
    QString output;
    QString error;
    const int result = runProcess(QStringLiteral("/usr/bin/sudo"),
                                  {QStringLiteral("-n"),
                                   QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                                   QStringLiteral("storage-setup"), QStringLiteral("inspect")},
                                  15000, &output, &error);
    const QJsonDocument document = QJsonDocument::fromJson(output.toUtf8());
    m_storagePlan = result == 0 && document.isObject()
            ? document.object().toVariantMap() : QVariantMap();
    if (m_storagePlan.isEmpty()) {
        const QString message = document.isObject()
                ? document.object().value(QStringLiteral("message")).toString() : QString();
        setError(!message.isEmpty() ? message :
                 (error.trimmed().isEmpty() ? output.trimmed() : error.trimmed()));
    }
    emit storageChanged();
    return !m_storagePlan.isEmpty();
}

bool SetupWizardManager::provisionStorage(const QString &fingerprint)
{
    clearError();
    if (m_storageBusy || m_storageProcess.state() != QProcess::NotRunning) {
        setError(QStringLiteral("Storage provisioning is already running"));
        return false;
    }
    if (fingerprint != m_storagePlan.value(QStringLiteral("fingerprint")).toString()) {
        setError(QStringLiteral("Storage confirmation is stale"));
        return false;
    }
    m_storageBusy = true;
    m_storageStage = QStringLiteral("Validating installation drive");
    m_storageOutputBuffer.clear();
    m_storageResult.clear();
    setBusy(true, m_storageStage);
    emit storageChanged();
    emit storageProgress(QStringLiteral("validating"), m_storageStage);
    m_storageProcess.start(QStringLiteral("/usr/bin/sudo"),
                           {QStringLiteral("-n"),
                            QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                            QStringLiteral("storage-setup"), QStringLiteral("provision"),
                            fingerprint});
    if (!m_storageProcess.waitForStarted(3000)) {
        m_storageBusy = false;
        setBusy(false, QStringLiteral("Storage provisioning could not start"));
        setError(m_storageProcess.errorString());
        emit storageChanged();
        return false;
    }
    QTimer::singleShot(210000, this, [this]() {
        if (m_storageBusy && m_storageProcess.state() != QProcess::NotRunning) {
            m_storageStage = QStringLiteral("Storage operation timed out");
            m_storageProcess.kill();
        }
    });
    return true;
}

void SetupWizardManager::onStorageReadyRead()
{
    m_storageOutputBuffer += m_storageProcess.readAllStandardOutput();
    while (true) {
        const int newline = m_storageOutputBuffer.indexOf('\n');
        if (newline < 0)
            break;
        const QByteArray line = m_storageOutputBuffer.left(newline).trimmed();
        m_storageOutputBuffer.remove(0, newline + 1);
        if (line.isEmpty())
            continue;
        const QJsonDocument document = QJsonDocument::fromJson(line);
        if (!document.isObject())
            continue;
        const QVariantMap value = document.object().toVariantMap();
        if (value.value(QStringLiteral("event")).toString() == QStringLiteral("progress")) {
            m_storageStage = value.value(QStringLiteral("message")).toString();
            emit storageChanged();
            emit storageProgress(value.value(QStringLiteral("stage")).toString(), m_storageStage);
        } else {
            m_storageResult = value;
        }
    }
}

void SetupWizardManager::onStorageProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    onStorageReadyRead();
    const QByteArray tail = m_storageOutputBuffer.trimmed();
    if (!tail.isEmpty()) {
        const QJsonDocument document = QJsonDocument::fromJson(tail);
        if (document.isObject())
            m_storageResult = document.object().toVariantMap();
    }
    m_storageOutputBuffer.clear();
    const QString standardError = QString::fromUtf8(m_storageProcess.readAllStandardError()).trimmed();
    const bool success = exitStatus == QProcess::NormalExit && exitCode == 0 &&
            m_storageResult.value(QStringLiteral("success")).toBool();
    QString message = m_storageResult.value(QStringLiteral("message")).toString().trimmed();
    if (message.isEmpty())
        message = standardError.isEmpty() ? QStringLiteral("Storage provisioning failed") : standardError;
    m_storageBusy = false;
    if (success) {
        m_storageStage = QStringLiteral("Complete");
        m_storagePlan = m_storageResult;
        clearError();
        setBusy(false, QStringLiteral("User data partition verified"));
    } else {
        m_storageStage = QStringLiteral("Storage provisioning needs attention");
        setBusy(false, m_storageStage);
        setError(message);
    }
    emit storageChanged();
    emit storageProvisioningFinished(success, m_storageResult, message);
}

void SetupWizardManager::onStorageProcessError(QProcess::ProcessError error)
{
    if (error != QProcess::FailedToStart)
        return;
    m_storageBusy = false;
    m_storageStage = QStringLiteral("Storage provisioning could not start");
    setBusy(false, m_storageStage);
    setError(m_storageProcess.errorString());
    emit storageChanged();
    emit storageProvisioningFinished(false, QVariantMap(), m_lastError);
}

QString SetupWizardManager::setupStatePath() const
{
    return m_stateDirectory + QStringLiteral("/setup.json");
}

QString SetupWizardManager::preferencesPath() const
{
    return m_stateDirectory + QStringLiteral("/preferences.json");
}

QString SetupWizardManager::recoveryStatePath() const
{
    return m_stateDirectory + QStringLiteral("/recovery.json");
}

QString SetupWizardManager::appHelpStatePath() const
{
    return m_stateDirectory + QStringLiteral("/app-help.json");
}

void SetupWizardManager::ensureStateDirectory()
{
    QDir().mkpath(m_stateDirectory);
    QFile::setPermissions(m_stateDirectory,
                          QFileDevice::ReadOwner |
                          QFileDevice::WriteOwner |
                          QFileDevice::ExeOwner);
}

void SetupWizardManager::loadState()
{
    const QVariantMap state = readJsonMap(setupStatePath());
    if (!state.isEmpty()) {
        m_optionalSteps = state.value(QStringLiteral("optionalSteps")).toMap();
        m_setupComplete = state.value(QStringLiteral("completed"), false).toBool();
        m_controllerPaired = state.value(QStringLiteral("controllerPaired"), false).toBool();
        m_regionConfigured = state.value(QStringLiteral("regionConfigured"), false).toBool();
        m_recoveryWritten = state.value(QStringLiteral("recoveryWritten"), false).toBool();
        m_loginInstructionsAcknowledged =
            state.value(QStringLiteral("loginInstructionsAcknowledged"), false).toBool();
        return;
    }

    /*
        Patch 64 must not force an upgrade install back through first boot.
        A clean release image deliberately omits all of these configured-state
        signals, so it still opens the wizard.
    */
    if (existingInstallationIsConfigured()) {
        m_setupComplete = true;
        saveSetupState();
    }
}

bool SetupWizardManager::existingInstallationIsConfigured() const
{
    const QDir securityUsers(QStringLiteral("/var/lib/neutronos/security/users"));
    const auto hasHumanOwner = [](const QString &username) {
        return username != QStringLiteral("neutronos") && HumanAccountPolicy::namedUserIsHuman(username);
    };

    if (securityUsers.exists()) {
        for (const QString &name : securityUsers.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            if (hasHumanOwner(name))
                return true;
        }
    }

    // Generic security/telemetry state is created during factory boot and is
    // not evidence that onboarding has completed. Only a profile directory
    // tied to a real human account can migrate an older install to complete.
    const QDir profiles(m_neutronRoot + QStringLiteral("/state/users"));
    if (profiles.exists()) {
        for (const QString &name : profiles.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            if (hasHumanOwner(name))
                return true;
        }
    }

    return false;
}

bool SetupWizardManager::saveSetupState() const
{
    QVariantMap state;
    state.insert(QStringLiteral("version"), 1);
    state.insert(QStringLiteral("completed"), m_setupComplete);
    state.insert(QStringLiteral("optionalSteps"), m_optionalSteps);
    state.insert(QStringLiteral("controllerPaired"), m_controllerPaired);
    state.insert(QStringLiteral("regionConfigured"), m_regionConfigured);
    state.insert(QStringLiteral("recoveryWritten"), m_recoveryWritten);
    state.insert(QStringLiteral("loginInstructionsAcknowledged"),
                 m_loginInstructionsAcknowledged);
    state.insert(QStringLiteral("updatedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    return writeJsonAtomic(setupStatePath(), state,
                           QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}

void SetupWizardManager::setBusy(bool busy, const QString &status)
{
    if (m_busy == busy && (status.isEmpty() || status == m_status))
        return;
    m_busy = busy;
    if (!status.isEmpty())
        m_status = status;
    emit operationChanged();
}

void SetupWizardManager::setError(const QString &message)
{
    m_lastError = message.trimmed();
    if (!m_lastError.isEmpty())
        m_status = m_lastError;
    emit operationChanged();
}

void SetupWizardManager::clearError()
{
    if (m_lastError.isEmpty())
        return;
    m_lastError.clear();
    emit operationChanged();
}

void SetupWizardManager::refresh()
{
    clearError();
    m_bluetoothAvailable = commandExists(QStringLiteral("bluetoothctl"));
    m_bluetoothDevices = enumerateBluetoothDevices();
    m_recoveryTargets = enumerateRecoveryTargets();
    m_setupDomains = detectSetupDomains();

    const QVariantMap recovery = readJsonMap(recoveryStatePath());
    if (!recovery.isEmpty()) {
        m_recoveryCode = recovery.value(QStringLiteral("displayCode")).toString();
        m_recoveryWritten = recovery.value(QStringLiteral("written"), m_recoveryWritten).toBool();
    }

    emit bluetoothChanged();
    emit recoveryChanged();
    emit setupStateChanged();
}

QVariantList SetupWizardManager::detectSetupDomains() const
{
    QVariantList result;
    auto add = [&result](const QString &id, bool configured, bool required, const QString &detail, bool invalid = false) {
        result.append(QVariantMap{{QStringLiteral("id"), id},
                                  {QStringLiteral("status"), configured ? QStringLiteral("configured") : invalid ? QStringLiteral("invalid") : QStringLiteral("not-configured")},
                                  {QStringLiteral("required"), required},
                                  {QStringLiteral("detail"), detail}});
    };

    bool validUser = false;
    QFile passwd(QStringLiteral("/etc/passwd"));
    if (passwd.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!passwd.atEnd()) {
            const QList<QByteArray> fields = passwd.readLine().trimmed().split(':');
            bool uidOk = false;
            const int uid = fields.size() > 2 ? fields.at(2).toInt(&uidOk) : -1;
            const QString home = fields.size() > 5 ? QString::fromLocal8Bit(fields.at(5)) : QString();
            const QString shell = fields.size() > 6 ? QString::fromLocal8Bit(fields.at(6)) : QString();
            const QString username = fields.isEmpty() ? QString() : QString::fromLocal8Bit(fields.at(0));
            if (uidOk && HumanAccountPolicy::isHuman(username, uid, home, shell)) {
                validUser = true;
                break;
            }
        }
    }
    const QDir securityUsers(QStringLiteral("/var/lib/neutronos/security/users"));
    const bool combo = securityUsers.exists() && !securityUsers.entryList(QDir::Dirs | QDir::NoDotAndDotDot).isEmpty();
    const QVariantMap setupState = readJsonMap(setupStatePath());
    const QString timezone = setupState.value(QStringLiteral("timezone")).toString();
    const bool systemTimezone = QFileInfo(QStringLiteral("/etc/localtime")).exists();
    const QFileInfo localeFile(QStringLiteral("/etc/default/locale"));
    const QFileInfo keyboardFile(QStringLiteral("/etc/default/keyboard"));
    const bool locale = localeFile.exists() && localeFile.size() > 0;
    const bool keyboard = keyboardFile.exists() && keyboardFile.size() > 0;
    QFile host(QStringLiteral("/etc/hostname"));
    const bool hostReadable = host.open(QIODevice::ReadOnly);
    const QString hostnameText = hostReadable ? QString::fromUtf8(host.readAll()).trimmed() : QString();
    const bool hostname = !hostnameText.isEmpty() && !normalizedHostname(hostnameText).isEmpty();
    const QFileInfo preferencesFile(preferencesPath());
    const bool preferences = !readJsonMap(preferencesPath()).isEmpty();
    bool liveLink = false;
    const QDir interfaces(QStringLiteral("/sys/class/net"));
    for (const QString &interfaceName : interfaces.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (interfaceName == QStringLiteral("lo"))
            continue;
        QFile carrier(interfaces.filePath(interfaceName + QStringLiteral("/carrier")));
        if (carrier.open(QIODevice::ReadOnly) && carrier.readAll().trimmed() == QByteArrayLiteral("1")) {
            liveLink = true;
            break;
        }
    }
    const QDir nmConnections(QStringLiteral("/etc/NetworkManager/system-connections"));
    const bool savedConnection = nmConnections.exists() &&
                                 !nmConnections.entryList(QDir::Files | QDir::NoDotAndDotDot).isEmpty();
    const bool network = liveLink || savedConnection || setupState.value(QStringLiteral("networkConfigured")).toBool();

    add(QStringLiteral("account"), validUser, true, QStringLiteral("A valid interactive Linux/NeutronOS user"));
    add(QStringLiteral("controller-combo"), combo, true, QStringLiteral("Per-user controller unlock credential"));
    // Factory region files are usable defaults, not an onboarding decision.
    add(QStringLiteral("timezone"), m_regionConfigured && (systemTimezone || !timezone.isEmpty()), true, QStringLiteral("System timezone confirmed during setup"));
    add(QStringLiteral("locale"), m_regionConfigured && locale, true, QStringLiteral("System locale"), localeFile.exists() && !locale);
    add(QStringLiteral("keyboard"), m_regionConfigured && keyboard, true, QStringLiteral("Keyboard layout"), keyboardFile.exists() && !keyboard);
    add(QStringLiteral("hostname"), hostname, true, QStringLiteral("System hostname"), hostReadable && !hostname);
    add(QStringLiteral("network"), network, false, QStringLiteral("Ethernet or NetworkManager configuration"));
    add(QStringLiteral("controller"), m_controllerPaired, false, QStringLiteral("Bluetooth controller pairing"));
    add(QStringLiteral("preferences"), preferences, true, QStringLiteral("Dashboard, privacy, theme and security preferences"), preferencesFile.exists() && !preferences);
    return result;
}

QString SetupWizardManager::normalizedUsername(const QString &username)
{
    const QString value = cleanText(username).toLower();
    static const QRegularExpression pattern(QStringLiteral("^[a-z_][a-z0-9_-]{0,31}$"));
    return pattern.match(value).hasMatch() ? value : QString();
}

QString SetupWizardManager::normalizedHostname(const QString &hostname)
{
    QString value = cleanText(hostname).toLower();
    value.replace(QRegularExpression(QStringLiteral("[^a-z0-9-]")), QStringLiteral("-"));
    value.replace(QRegularExpression(QStringLiteral("-+")), QStringLiteral("-"));
    value = value.left(63);
    while (value.startsWith(QLatin1Char('-'))) value.remove(0, 1);
    while (value.endsWith(QLatin1Char('-'))) value.chop(1);
    return value;
}

QString SetupWizardManager::normalizedControllerName(const QString &name)
{
    QString value = cleanText(name).toLower();
    value.remove(QRegularExpression(QStringLiteral("[^a-z0-9]+")));
    value.replace(QStringLiteral("wirelesscontroller"), QStringLiteral("controller"));
    return value;
}

bool SetupWizardManager::applyRegion(const QString &timezone,
                                     const QString &locale,
                                     const QString &keyboardLayout)
{
    clearError();
    const QString cleanTimezone = cleanText(timezone);
    const QString cleanLocale = cleanText(locale);
    const QString cleanKeyboard = cleanText(keyboardLayout);

    if (cleanTimezone.isEmpty()) {
        setError(QStringLiteral("A time zone is required"));
        emit regionApplied(false, m_lastError);
        return false;
    }

    setBusy(true, QStringLiteral("Applying region settings"));
    QString output;
    QString error;
    const int result = runProcess(QStringLiteral("sudo"),
                                  {QStringLiteral("-n"),
                                   QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                                   QStringLiteral("setup-region"),
                                   cleanTimezone, cleanLocale, cleanKeyboard},
                                  20000, &output, &error);
    bool success = result == 0;
    if (success) {
        m_regionConfigured = true;
        if (!saveSetupState()) {
            m_regionConfigured = false;
            success = false;
            error = QStringLiteral("Region settings applied, but setup progress could not be saved");
        }
        m_setupDomains = detectSetupDomains();
        emit setupStateChanged();
    }
    setBusy(false, success ? QStringLiteral("Region settings applied")
                           : QStringLiteral("Region settings failed"));
    if (!success)
        setError(error.trimmed().isEmpty() ? output.trimmed() : error.trimmed());
    emit regionApplied(success, success ? m_status : m_lastError);
    return success;
}

bool SetupWizardManager::localUserExists(const QString &username)
{
    if (username.isEmpty())
        return false;
    const QByteArray encoded = username.toLocal8Bit();
    return ::getpwnam(encoded.constData()) != nullptr;
}

bool SetupWizardManager::applyIdentity(const QString &hostname,
                                       const QString &username,
                                       const QString &displayName,
                                       const QString &password)
{
    clearError();
    const QString cleanHost = normalizedHostname(hostname);
    const QString cleanUser = normalizedUsername(username);
    const QString cleanDisplay = cleanText(displayName).left(64);

    if (cleanHost.isEmpty() || cleanUser.isEmpty()) {
        setError(QStringLiteral("Hostname and username contain unsupported characters"));
        emit identityApplied(false, cleanUser, m_lastError);
        return false;
    }
    if (password.size() < 8) {
        setError(QStringLiteral("The account password must contain at least 8 characters"));
        emit identityApplied(false, cleanUser, m_lastError);
        return false;
    }

    const QString helper = QStringLiteral("/usr/local/sbin/neutronos-privileged-helper");
    const QFileInfo helperInfo(helper);
    if (!helperInfo.isFile() || !helperInfo.isExecutable()) {
        setError(QStringLiteral("The account creation service is not installed correctly"));
        qCritical().noquote() << "Setup account helper missing or not executable:" << helper;
        emit identityApplied(false, cleanUser, m_lastError);
        return false;
    }

    setBusy(true, QStringLiteral("Creating the local account"));
    QString output;
    QString error;
    const QByteArray input = password.toUtf8() + '\n';
    const bool privileged = ::geteuid() == 0;
    const QString program = privileged ? helper : QStringLiteral("/usr/bin/sudo");
    QStringList arguments;
    if (!privileged)
        arguments << QStringLiteral("-n") << helper;
    arguments << QStringLiteral("setup-identity") << cleanHost << cleanUser << cleanDisplay;
    const int result = runProcess(program, arguments,
                                  300000, &output, &error, input);
    const bool success = result == 0;
    setBusy(false, success ? QStringLiteral("Account and hostname configured")
                           : QStringLiteral("Account setup failed"));
    if (!success) {
        setError(error.trimmed().isEmpty() ? output.trimmed() : error.trimmed());
        qWarning().noquote() << "Setup account creation failed:" << m_lastError;
    }
    emit identityApplied(success, cleanUser, success ? m_status : m_lastError);
    return success;
}

void SetupWizardManager::rememberUsbController(const QString &controllerName,
                                                const QString &devicePath)
{
    m_rememberedUsbController = cleanText(controllerName);
    m_rememberedUsbDevicePath = cleanText(devicePath);
    emit bluetoothChanged();
}

bool SetupWizardManager::confirmControllerRegistration()
{
    clearError();
    // Ask the existing bridge for its live BlueZ verification, including the
    // controller identity it captured over USB. Keep the working pair path.
    QNetworkAccessManager manager;
    QNetworkReply *reply = manager.get(QNetworkRequest(QUrl(QStringLiteral("http://127.0.0.1:48173/registration"))));
    QEventLoop loop;
    QTimer deadline;
    deadline.setSingleShot(true);
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    connect(&deadline, &QTimer::timeout, reply, &QNetworkReply::abort);
    deadline.start(4000);
    loop.exec();
    const QVariantMap state = QJsonDocument::fromJson(reply->readAll()).object().toVariantMap();
    const bool verified = reply->error() == QNetworkReply::NoError &&
                          reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 200;
    if (!verified || state.value(QStringLiteral("address")).toString().isEmpty() ||
        !state.value(QStringLiteral("paired")).toBool() ||
        !state.value(QStringLiteral("trusted")).toBool() ||
        !state.value(QStringLiteral("connected")).toBool() ||
        state.value(QStringLiteral("usb_present")).toBool()) {
        setError(QStringLiteral("Controller registration is not yet paired, trusted and connected"));
        return false;
    }
    const bool previous = m_controllerPaired;
    m_controllerPaired = true;
    if (!saveSetupState()) {
        m_controllerPaired = previous;
        setError(QStringLiteral("Controller is connected, but setup progress could not be saved"));
        return false;
    }
    m_setupDomains = detectSetupDomains();
    emit bluetoothChanged();
    emit setupStateChanged();
    return true;
}

bool SetupWizardManager::startBluetoothScan()
{
    clearError();
    if (!m_bluetoothAvailable) {
        setError(QStringLiteral("Bluetooth tools are not installed"));
        emit bluetoothOperationFinished(false, m_lastError);
        return false;
    }
    if (m_bluetoothProcess.state() != QProcess::NotRunning)
        return false;

    m_pendingBluetoothOperation = QStringLiteral("scan");
    m_bluetoothScanning = true;
    setBusy(true, QStringLiteral("Scanning for Bluetooth controllers"));
    emit bluetoothChanged();

    m_bluetoothProcess.start(QStringLiteral("bluetoothctl"),
                             {QStringLiteral("--timeout"), QStringLiteral("12"),
                              QStringLiteral("scan"), QStringLiteral("on")});
    return true;
}

void SetupWizardManager::stopBluetoothScan()
{
    if (m_bluetoothProcess.state() != QProcess::NotRunning &&
            m_pendingBluetoothOperation == QStringLiteral("scan")) {
        m_bluetoothProcess.terminate();
        if (!m_bluetoothProcess.waitForFinished(750))
            m_bluetoothProcess.kill();
    }
    runProcess(QStringLiteral("bluetoothctl"),
               {QStringLiteral("scan"), QStringLiteral("off")},
               3000, nullptr, nullptr);
    m_bluetoothScanning = false;
    setBusy(false, QStringLiteral("Bluetooth scan stopped"));
    emit bluetoothChanged();
}

void SetupWizardManager::refreshBluetoothDevices()
{
    m_bluetoothDevices = enumerateBluetoothDevices();
    emit bluetoothChanged();
}

bool SetupWizardManager::pairAndTrustController(const QString &address,
                                                 const QString &currentUsbControllerName)
{
    clearError();
    const QString cleanAddress = address.trimmed().toUpper();
    static const QRegularExpression macPattern(
        QStringLiteral("^[0-9A-F]{2}(:[0-9A-F]{2}){5}$"));
    if (!macPattern.match(cleanAddress).hasMatch()) {
        setError(QStringLiteral("The selected Bluetooth address is invalid"));
        emit bluetoothOperationFinished(false, m_lastError);
        return false;
    }

    const QString remembered = normalizedControllerName(m_rememberedUsbController);
    const QString current = normalizedControllerName(currentUsbControllerName);
    if (remembered.isEmpty() || current.isEmpty() ||
            (!remembered.contains(current) && !current.contains(remembered))) {
        setError(QStringLiteral("Reconnect the same controller by USB before confirmation"));
        emit bluetoothOperationFinished(false, m_lastError);
        return false;
    }

    if (m_bluetoothProcess.state() != QProcess::NotRunning)
        return false;

    m_pendingBluetoothOperation = QStringLiteral("pair");
    m_pendingBluetoothAddress = cleanAddress;
    setBusy(true, QStringLiteral("Pairing and trusting the controller"));

    const QString command = QStringLiteral(
        "bluetoothctl power on >/dev/null 2>&1 && "
        "bluetoothctl --timeout 30 pair %1 && "
        "bluetoothctl trust %1 && "
        "bluetoothctl connect %1").arg(shellQuote(cleanAddress));
    m_bluetoothProcess.start(QStringLiteral("/bin/sh"),
                             {QStringLiteral("-c"), command});
    return true;
}

void SetupWizardManager::onBluetoothProcessFinished(int exitCode,
                                                     QProcess::ExitStatus exitStatus)
{
    const QString operation = m_pendingBluetoothOperation;
    const QString standardError = QString::fromUtf8(m_bluetoothProcess.readAllStandardError()).trimmed();
    const QString standardOutput = QString::fromUtf8(m_bluetoothProcess.readAllStandardOutput()).trimmed();
    m_pendingBluetoothOperation.clear();

    if (operation == QStringLiteral("scan")) {
        m_bluetoothScanning = false;
        m_bluetoothDevices = enumerateBluetoothDevices();
        const bool success = exitStatus == QProcess::NormalExit && exitCode == 0;
        setBusy(false, success ? QStringLiteral("Bluetooth scan complete")
                               : QStringLiteral("Bluetooth scan ended"));
        emit bluetoothChanged();
        emit bluetoothOperationFinished(success,
             success ? m_status : (standardError.isEmpty() ? standardOutput : standardError));
        return;
    }

    if (operation == QStringLiteral("pair")) {
        const bool success = exitStatus == QProcess::NormalExit && exitCode == 0;
        m_controllerPaired = success;
        if (success) {
            saveSetupState();
            setBusy(false, QStringLiteral("Controller paired, trusted and connected"));
        } else {
            setBusy(false, QStringLiteral("Controller pairing failed"));
            setError(standardError.isEmpty() ?
                         (standardOutput.isEmpty() ? QStringLiteral("Bluetooth pairing failed") : standardOutput)
                       : standardError);
        }
        emit bluetoothChanged();
        emit bluetoothOperationFinished(success, success ? m_status : m_lastError);
    }
}

QVariantList SetupWizardManager::enumerateBluetoothDevices() const
{
    QVariantList devices;
    if (!commandExists(QStringLiteral("bluetoothctl")))
        return devices;

    QString output;
    if (runProcess(QStringLiteral("bluetoothctl"),
                   {QStringLiteral("devices")}, 4000, &output, nullptr) != 0) {
        return devices;
    }

    static const QRegularExpression linePattern(
        QStringLiteral("^Device\\s+([0-9A-Fa-f:]{17})\\s+(.+)$"));
    const QStringList lines = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QRegularExpressionMatch match = linePattern.match(line.trimmed());
        if (!match.hasMatch())
            continue;
        const QString address = match.captured(1).toUpper();
        const QString name = match.captured(2).trimmed();
        const QString lower = name.toLower();
        const bool likelyController = lower.contains(QStringLiteral("controller")) ||
                                      lower.contains(QStringLiteral("gamepad")) ||
                                      lower.contains(QStringLiteral("dualshock")) ||
                                      lower.contains(QStringLiteral("dualsense")) ||
                                      lower.contains(QStringLiteral("xbox")) ||
                                      lower.contains(QStringLiteral("8bitdo"));
        QVariantMap device;
        device.insert(QStringLiteral("address"), address);
        device.insert(QStringLiteral("name"), name);
        device.insert(QStringLiteral("likelyController"), likelyController);
        devices.append(device);
    }

    std::stable_sort(devices.begin(), devices.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("likelyController")).toBool() >
               b.toMap().value(QStringLiteral("likelyController")).toBool();
    });
    return devices;
}

void SetupWizardManager::refreshRecoveryTargets()
{
    m_recoveryTargets = enumerateRecoveryTargets();
    emit recoveryChanged();
}

QString SetupWizardManager::generateRecoveryCode() const
{
    static const QString alphabet = QStringLiteral("ABCDEFGHJKLMNPQRSTUVWXYZ23456789");
    QStringList groups;
    for (int group = 0; group < 4; ++group) {
        QString part;
        for (int index = 0; index < 5; ++index) {
            part.append(alphabet.at(QRandomGenerator::system()->bounded(alphabet.size())));
        }
        groups.append(part);
    }
    return groups.join(QLatin1Char('-'));
}

QString SetupWizardManager::ensureRecoveryCode()
{
    if (!m_recoveryCode.isEmpty())
        return m_recoveryCode;

    m_recoveryCode = generateRecoveryCode();
    const QByteArray salt = QByteArray::number(QRandomGenerator::system()->generate64(), 16);
    const QByteArray digest = QCryptographicHash::hash(
        salt + m_recoveryCode.toUtf8(), QCryptographicHash::Sha256).toHex();

    QVariantMap state;
    state.insert(QStringLiteral("version"), 1);
    state.insert(QStringLiteral("salt"), QString::fromLatin1(salt));
    state.insert(QStringLiteral("sha256"), QString::fromLatin1(digest));
    state.insert(QStringLiteral("displayCode"), m_recoveryCode);
    state.insert(QStringLiteral("written"), false);
    state.insert(QStringLiteral("createdAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    writeJsonAtomic(recoveryStatePath(), state,
                    QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    emit recoveryChanged();
    return m_recoveryCode;
}

bool SetupWizardManager::safeMountPath(const QString &path)
{
    const QString clean = QDir::cleanPath(path);
    return clean.startsWith(QStringLiteral("/media/")) ||
           clean.startsWith(QStringLiteral("/run/media/")) ||
           clean.startsWith(QStringLiteral("/mnt/"));
}

bool SetupWizardManager::writeRecoveryDrive(const QString &mountPath)
{
    clearError();
    const QString cleanMount = QDir::cleanPath(mountPath);
    if (!safeMountPath(cleanMount) || !QFileInfo(cleanMount).isDir()) {
        setError(QStringLiteral("Select a mounted removable drive"));
        return false;
    }

    ensureRecoveryCode();
    const QVariantMap localState = readJsonMap(recoveryStatePath());
    QVariantMap drivePayload;
    drivePayload.insert(QStringLiteral("format"), QStringLiteral("NeutronOS Recovery Key"));
    drivePayload.insert(QStringLiteral("version"), 1);
    drivePayload.insert(QStringLiteral("recoveryCode"), m_recoveryCode);
    drivePayload.insert(QStringLiteral("fingerprint"), localState.value(QStringLiteral("sha256")));
    drivePayload.insert(QStringLiteral("createdAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    const QString path = cleanMount + QStringLiteral("/.neutronos-recovery.json");
    if (!writeJsonAtomic(path, drivePayload,
                         QFileDevice::ReadOwner | QFileDevice::WriteOwner)) {
        setError(QStringLiteral("Unable to write the recovery key to the selected drive"));
        return false;
    }

    QVariantMap updated = localState;
    updated.insert(QStringLiteral("written"), true);
    updated.insert(QStringLiteral("drivePath"), cleanMount);
    updated.insert(QStringLiteral("writtenAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    writeJsonAtomic(recoveryStatePath(), updated,
                    QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    m_recoveryWritten = true;
    saveSetupState();
    m_status = QStringLiteral("Recovery drive created");
    emit operationChanged();
    emit recoveryChanged();
    return true;
}

QVariantList SetupWizardManager::enumerateRecoveryTargets() const
{
    QVariantList targets;
    QString output;
    if (runProcess(QStringLiteral("lsblk"),
                   {QStringLiteral("-J"), QStringLiteral("-o"),
                    QStringLiteral("NAME,PATH,TYPE,RM,SIZE,LABEL,FSTYPE,MOUNTPOINTS")},
                   5000, &output, nullptr) != 0) {
        return targets;
    }

    const QJsonDocument document = QJsonDocument::fromJson(output.toUtf8());
    const QJsonArray devices = document.object().value(QStringLiteral("blockdevices")).toArray();
    std::function<void(const QJsonObject &, bool)> visit;
    visit = [&](const QJsonObject &object, bool parentRemovable) {
        const bool removable = object.value(QStringLiteral("rm")).toBool(parentRemovable);
        const QString type = object.value(QStringLiteral("type")).toString();
        const QJsonArray mounts = object.value(QStringLiteral("mountpoints")).toArray();
        if (removable && (type == QStringLiteral("part") || type == QStringLiteral("crypt"))) {
            for (const QJsonValue &value : mounts) {
                const QString mount = value.toString();
                if (mount.isEmpty() || !safeMountPath(mount))
                    continue;
                QVariantMap target;
                target.insert(QStringLiteral("path"), object.value(QStringLiteral("path")).toString());
                target.insert(QStringLiteral("mountPath"), mount);
                target.insert(QStringLiteral("name"), object.value(QStringLiteral("name")).toString());
                target.insert(QStringLiteral("label"), object.value(QStringLiteral("label")).toString());
                target.insert(QStringLiteral("size"), object.value(QStringLiteral("size")).toString());
                target.insert(QStringLiteral("filesystem"), object.value(QStringLiteral("fstype")).toString());
                targets.append(target);
            }
        }
        for (const QJsonValue &child : object.value(QStringLiteral("children")).toArray())
            visit(child.toObject(), removable);
    };
    for (const QJsonValue &device : devices)
        visit(device.toObject(), false);
    return targets;
}

bool SetupWizardManager::savePreferences(const QVariantMap &preferences)
{
    clearError();
    QVariantMap payload = preferences;
    payload.insert(QStringLiteral("version"), 2);
    payload.insert(QStringLiteral("updatedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    const bool written = writeJsonAtomic(preferencesPath(), payload,
                                         QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    if (!written) {
        setError(QStringLiteral("Unable to save setup preferences"));
        return false;
    }

    QString output;
    QString error;
    const int result = runProcess(QStringLiteral("sudo"),
                                  {QStringLiteral("-n"),
                                  QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                                   QStringLiteral("apply-preferences"),
                                   preferencesPath()},
                                  240000, &output, &error);
    if (result != 0) {
        setError(error.trimmed().isEmpty() ? output.trimmed() : error.trimmed());
        return false;
    }

    QFile tokenFile(m_stateDirectory + QStringLiteral("/remote-token.txt"));
    if (tokenFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_remoteControllerToken = QString::fromUtf8(tokenFile.readAll()).trimmed();
        tokenFile.close();
        QFile::remove(tokenFile.fileName());
    } else {
        m_remoteControllerToken.clear();
    }
    emit releasePreferencesChanged();
    return true;
}

bool SetupWizardManager::recordOptionalStep(const QString &step, bool skipped)
{
    if (step != QStringLiteral("network") && step != QStringLiteral("controller") &&
        step != QStringLiteral("recovery")) {
        setError(QStringLiteral("This setup page cannot be skipped"));
        return false;
    }
    const QVariantMap previous = m_optionalSteps;
    m_optionalSteps.insert(step, skipped ? QStringLiteral("skipped") : QStringLiteral("configured"));
    if (!saveSetupState()) {
        m_optionalSteps = previous;
        setError(QStringLiteral("Unable to save optional setup decision"));
        return false;
    }
    emit setupStateChanged();
    return true;
}

bool SetupWizardManager::completeSetup()
{
    clearError();
    m_setupDomains = detectSetupDomains();
    for (const QVariant &value : std::as_const(m_setupDomains)) {
        const QVariantMap domain = value.toMap();
        if (domain.value(QStringLiteral("required")).toBool() &&
            domain.value(QStringLiteral("status")).toString() != QStringLiteral("configured")) {
            setError(QStringLiteral("Required setup domain is incomplete: %1")
                         .arg(domain.value(QStringLiteral("id")).toString()));
            emit setupStateChanged();
            return false;
        }
    }
    m_setupComplete = true;
    if (!saveSetupState()) {
        m_setupComplete = false;
        setError(QStringLiteral("Unable to finalize first-boot setup"));
        return false;
    }
    QSaveFile request(m_stateDirectory + QStringLiteral("/finalize-request"));
    if (!request.open(QIODevice::WriteOnly) || request.write("finalize-v1\n") != 12 || !request.commit()) {
        m_setupComplete = false;
        saveSetupState();
        setError(QStringLiteral("Setup finalization request could not be saved; retry completion"));
        return false;
    }
    m_status = QStringLiteral("NeutronOS setup complete");
    emit operationChanged();
    emit setupStateChanged();
    emit setupCompleted();
    return true;
}

bool SetupWizardManager::acknowledgeLoginInstructions()
{
    if (!m_setupComplete)
        return false;
    if (m_loginInstructionsAcknowledged)
        return true;
    m_loginInstructionsAcknowledged = true;
    if (!saveSetupState()) {
        m_loginInstructionsAcknowledged = false;
        setError(QStringLiteral("Unable to save login instruction acknowledgement"));
        return false;
    }
    emit setupStateChanged();
    return true;
}

bool SetupWizardManager::resetSetupForNextBoot()
{
    m_setupComplete = false;
    m_optionalSteps.clear();
    m_regionConfigured = false;
    m_controllerPaired = false;
    m_recoveryWritten = false;
    m_loginInstructionsAcknowledged = false;
    QFile::remove(setupStatePath());
    emit setupStateChanged();
    return true;
}

QString SetupWizardManager::helpKey(const QString &username,
                                    const QString &appId) const
{
    QString user = normalizedUsername(username);
    if (user.isEmpty())
        user = QStringLiteral("default");
    QString app = appId.trimmed().toLower();
    app.replace(QRegularExpression(QStringLiteral("[^a-z0-9_.-]")), QStringLiteral("_"));
    return user + QLatin1Char('/') + app;
}

QVariantMap SetupWizardManager::loadHelpState() const
{
    return readJsonMap(appHelpStatePath());
}

bool SetupWizardManager::saveHelpState(const QVariantMap &state) const
{
    return writeJsonAtomic(appHelpStatePath(), state,
                           QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}

QVariantMap SetupWizardManager::registerAppOpen(const QString &username,
                                                const QString &appId)
{
    QVariantMap state = loadHelpState();
    const QString key = helpKey(username, appId);
    QVariantMap entry = state.value(key).toMap();
    const int previous = qBound(0, entry.value(QStringLiteral("count"), 0).toInt(), AutomaticHelpLimit);
    const bool suppressed = entry.value(QStringLiteral("suppressed"), false).toBool();
    const bool show = !suppressed && previous < AutomaticHelpLimit;
    const int count = show ? previous + 1 : previous;

    entry.insert(QStringLiteral("count"), count);
    entry.insert(QStringLiteral("lastOpenedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    entry.insert(QStringLiteral("suppressed"), suppressed);
    state.insert(key, entry);
    saveHelpState(state);

    QVariantMap result;
    result.insert(QStringLiteral("show"), show);
    result.insert(QStringLiteral("count"), count);
    result.insert(QStringLiteral("remaining"), qMax(0, AutomaticHelpLimit - count));
    return result;
}

int SetupWizardManager::appHelpCount(const QString &username,
                                     const QString &appId) const
{
    const QVariantMap entry = loadHelpState().value(helpKey(username, appId)).toMap();
    return qBound(0, entry.value(QStringLiteral("count"), 0).toInt(), AutomaticHelpLimit);
}

bool SetupWizardManager::shouldShowAppHelp(const QString &username,
                                           const QString &appId) const
{
    const QVariantMap entry = loadHelpState().value(helpKey(username, appId)).toMap();
    return !entry.value(QStringLiteral("suppressed"), false).toBool() &&
           entry.value(QStringLiteral("count"), 0).toInt() < AutomaticHelpLimit;
}

bool SetupWizardManager::suppressAutomaticAppHelp(const QString &username,
                                                   const QString &appId)
{
    QVariantMap state = loadHelpState();
    const QString key = helpKey(username, appId);
    QVariantMap entry = state.value(key).toMap();
    entry.insert(QStringLiteral("count"), AutomaticHelpLimit);
    entry.insert(QStringLiteral("suppressed"), true);
    state.insert(key, entry);
    return saveHelpState(state);
}

bool SetupWizardManager::commandExists(const QString &command)
{
    return !QStandardPaths::findExecutable(command).isEmpty();
}

int SetupWizardManager::runProcess(const QString &program,
                                   const QStringList &arguments,
                                   int timeoutMs,
                                   QString *standardOutput,
                                   QString *standardError,
                                   const QByteArray &standardInput)
{
    QProcess process;
    process.setProcessChannelMode(QProcess::SeparateChannels);
    process.start(program, arguments);
    if (!process.waitForStarted(3000)) {
        if (standardError)
            *standardError = process.errorString();
        return -1;
    }
    if (!standardInput.isEmpty()) {
        process.write(standardInput);
        process.closeWriteChannel();
    }
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(1000);
        if (standardError)
            *standardError = QStringLiteral("Command timed out: %1").arg(program);
        return -2;
    }
    if (standardOutput)
        *standardOutput = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
    if (standardError)
        *standardError = QString::fromUtf8(process.readAllStandardError()).trimmed();
    return process.exitStatus() == QProcess::NormalExit ? process.exitCode() : -3;
}

bool SetupWizardManager::writeJsonAtomic(const QString &path,
                                         const QVariantMap &payload,
                                         QFileDevice::Permissions permissions) const
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    file.setPermissions(permissions);
    const QJsonDocument document(QJsonObject::fromVariantMap(payload));
    if (file.write(document.toJson(QJsonDocument::Indented)) < 0)
        return false;
    if (!file.commit())
        return false;

    /* FAT/exFAT recovery media may not implement POSIX chmod. The secure
       local state directory still requires owner-only permissions. */
    if (QDir::cleanPath(path).startsWith(QDir::cleanPath(m_stateDirectory)))
        return QFile::setPermissions(path, permissions);

    QFile::setPermissions(path, permissions);
    return true;
}

QVariantMap SetupWizardManager::readJsonMap(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object().toVariantMap() : QVariantMap();
}
