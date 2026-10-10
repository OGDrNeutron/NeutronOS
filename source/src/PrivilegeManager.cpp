#include "PrivilegeManager.h"
#include "DeveloperModeManager.h"

#include <QFileInfo>
#include <QRegularExpression>

namespace {
const QString kBrokerPath = QStringLiteral("/usr/local/libexec/neutronos-root-broker");

bool safeUnit(const QString &unit)
{
    static const QRegularExpression expression(
        QStringLiteral("^(?:neutronos(?:-[a-z0-9@_.-]+)?|neutron-securityd|"
                       "neutron-security-watchdog|tailscaled|docker|bluetooth|"
                       "ssh|NetworkManager)\\.(?:service|socket|target)$"),
        QRegularExpression::CaseInsensitiveOption);
    return expression.match(unit).hasMatch();
}
}

PrivilegeManager::PrivilegeManager(DeveloperModeManager *developerModeManager,
                                   QObject *parent)
    : QObject(parent),
      m_developerModeManager(developerModeManager)
{
    if (m_developerModeManager) {
        connect(m_developerModeManager,
                &DeveloperModeManager::developerModeChanged,
                this, &PrivilegeManager::changed);
    }

    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] {
        m_output += QString::fromUtf8(m_process.readAllStandardOutput());
    });
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        m_error += QString::fromUtf8(m_process.readAllStandardError());
        emit changed();
    });
    connect(&m_process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int exitCode, QProcess::ExitStatus status) {
        const bool success = status == QProcess::NormalExit && exitCode == 0;
        const QString detail = m_error.trimmed();
        m_running = false;
        m_pending = false;
        emit changed();
        emit completed(success,
                       success ? QStringLiteral("Administrative action completed")
                               : (detail.isEmpty()
                                  ? QStringLiteral("Administrative action failed")
                                  : detail),
                       m_output,
                       exitCode);
    });
}

bool PrivilegeManager::pending() const { return m_pending; }
bool PrivilegeManager::running() const { return m_running; }
bool PrivilegeManager::developerMode() const
{
    return m_developerModeManager &&
           m_developerModeManager->developerModeEnabled();
}
QString PrivilegeManager::title() const { return m_title; }
QString PrivilegeManager::description() const { return m_description; }
QString PrivilegeManager::command() const { return m_command; }
QString PrivilegeManager::lastError() const { return m_error; }

bool PrivilegeManager::requestLooksAllowed(const QString &command,
                                           const QStringList &arguments,
                                           QString *reason)
{
    auto reject = [reason](const QString &message) {
        if (reason)
            *reason = message;
        return false;
    };

    if (command == QStringLiteral("/usr/sbin/reboot") ||
        command == QStringLiteral("/usr/sbin/poweroff")) {
        return arguments.isEmpty() ||
               reject(QStringLiteral("Power actions do not accept arguments."));
    }

    if (command == QStringLiteral("/usr/bin/systemctl") ||
        command == QStringLiteral("/bin/systemctl")) {
        if (arguments.size() != 2)
            return reject(QStringLiteral("System service actions require exactly an action and unit."));
        static const QStringList verbs = {
            QStringLiteral("start"), QStringLiteral("stop"),
            QStringLiteral("restart"), QStringLiteral("reload"),
            QStringLiteral("enable"), QStringLiteral("disable")
        };
        if (!verbs.contains(arguments.at(0)))
            return reject(QStringLiteral("That systemctl action is not authorized."));
        if (!safeUnit(arguments.at(1)))
            return reject(QStringLiteral("That service is not in the NeutronOS administrative allowlist."));
        return true;
    }

    return reject(QStringLiteral("This executable is not authorized by the NeutronOS root broker."));
}

bool PrivilegeManager::request(const QString &title,
                               const QString &description,
                               const QString &command,
                               const QStringList &arguments)
{
    if (m_pending || m_running)
        return false;

    const QFileInfo executable(command);
    QString reason;
    if (!executable.isAbsolute() || !executable.isExecutable() ||
        !requestLooksAllowed(executable.absoluteFilePath(), arguments, &reason)) {
        m_error = reason.isEmpty()
                ? QStringLiteral("An authorized absolute executable path is required.")
                : reason;
        emit changed();
        return false;
    }

    m_title = title.trimmed().isEmpty() ? QStringLiteral("Run as sudo") : title;
    m_description = description;
    m_command = executable.absoluteFilePath();
    m_arguments = arguments;
    m_error.clear();
    m_output.clear();
    m_pending = true;
    emit changed();
    return true;
}

void PrivilegeManager::finishStartFailure(const QString &message)
{
    m_error = message;
    m_running = false;
    emit changed();
}

void PrivilegeManager::proceed(const QString &password)
{
    if (!m_pending || m_running)
        return;
    if (password.isEmpty()) {
        m_error = QStringLiteral("Local account password is required for every root action.");
        emit changed();
        return;
    }
    if (!QFileInfo(kBrokerPath).isExecutable()) {
        m_error = QStringLiteral("The validated NeutronOS root broker is not installed.");
        emit changed();
        return;
    }

    QStringList arguments{
        QStringLiteral("-S"),
        QStringLiteral("-k"),
        QStringLiteral("-p"),
        QString(),
        kBrokerPath,
        QStringLiteral("--"),
        m_command
    };
    arguments.append(m_arguments);

    m_running = true;
    m_error.clear();
    m_output.clear();
    emit changed();

    m_process.start(QStringLiteral("/usr/bin/sudo"), arguments);
    if (!m_process.waitForStarted(5000)) {
        finishStartFailure(m_process.errorString());
        return;
    }

    QByteArray secret = password.toUtf8();
    secret.append('\n');
    m_process.write(secret);
    m_process.closeWriteChannel();
    secret.fill('\0');
}

void PrivilegeManager::cancel()
{
    if (m_running) {
        m_process.terminate();
        if (!m_process.waitForFinished(1200))
            m_process.kill();
    }
    m_pending = false;
    m_running = false;
    m_arguments.clear();
    emit changed();
}
