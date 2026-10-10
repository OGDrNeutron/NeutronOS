#include "RecoveryModeManager.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTimer>

namespace {
QString sudoPath()
{
    return qEnvironmentVariable("NEUTRONOS_RECOVERY_SUDO", QStringLiteral("/usr/bin/sudo"));
}
QString helperPath()
{
    return qEnvironmentVariable("NEUTRONOS_RECOVERY_HELPER",
                                QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"));
}
}

RecoveryModeManager::RecoveryModeManager(QObject *parent)
    : QObject(parent)
{
    m_process.setProcessChannelMode(QProcess::MergedChannels);
    connect(&m_process, &QProcess::readyReadStandardOutput,
            this, &RecoveryModeManager::onReadyRead);
    connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &RecoveryModeManager::onFinished);
    QTimer::singleShot(0, this, &RecoveryModeManager::refresh);
}

QVariantList RecoveryModeManager::recoveryPoints() const { return m_recoveryPoints; }
int RecoveryModeManager::selectedIndex() const { return m_selectedIndex; }
int RecoveryModeManager::failureOption() const { return m_failureOption; }
QString RecoveryModeManager::view() const { return m_view; }
QString RecoveryModeManager::title() const { return m_title; }
QString RecoveryModeManager::message() const { return m_message; }
int RecoveryModeManager::progress() const { return m_progress; }
bool RecoveryModeManager::armed() const { return m_armed; }
bool RecoveryModeManager::busy() const { return m_busy; }

bool RecoveryModeManager::start(Operation operation, const QStringList &arguments)
{
    const QString sudoProgram = sudoPath();
    const QString helperProgram = helperPath();
    if (m_process.state() != QProcess::NotRunning || !QFileInfo(sudoProgram).isExecutable() ||
        !QFileInfo(helperProgram).isExecutable()) {
        fail(QStringLiteral("The authenticated Recovery service is unavailable."));
        return false;
    }
    m_operation = operation;
    m_output.clear();
    m_pendingProgress.clear();
    m_busy = true;
    emit stateChanged();
    QStringList args{QStringLiteral("-n"), helperProgram};
    args.append(arguments);
    m_process.start(sudoProgram, args);
    if (!m_process.waitForStarted(3000)) {
        fail(QStringLiteral("Recovery could not start its authenticated operation."));
        return false;
    }
    return true;
}

void RecoveryModeManager::refresh()
{
    if (m_busy)
        return;
    m_view = QStringLiteral("loading");
    m_title = QStringLiteral("Preparing Recovery");
    m_message = QStringLiteral("Loading the verified recovery catalog…");
    m_progress = -1;
    m_armed = false;
    start(Operation::Status, {QStringLiteral("recovery-status")});
}

QString RecoveryModeManager::selectedPath() const
{
    if (m_selectedIndex < 0 || m_selectedIndex >= m_recoveryPoints.size())
        return {};
    return m_recoveryPoints.at(m_selectedIndex).toMap().value(QStringLiteral("path")).toString();
}

void RecoveryModeManager::beginApply()
{
    const QVariantMap point = (m_selectedIndex >= 0 && m_selectedIndex < m_recoveryPoints.size())
        ? m_recoveryPoints.at(m_selectedIndex).toMap() : QVariantMap();
    const QString kind = point.value(QStringLiteral("kind")).toString();
    const QString path = selectedPath();
    if (kind == QStringLiteral("backup") && path.isEmpty()) {
        fail(QStringLiteral("The selected recovery point is no longer available."));
        return;
    }
    m_view = QStringLiteral("progress");
    m_title = kind == QStringLiteral("update")
        ? QStringLiteral("Installing NeutronOS Update")
        : QStringLiteral("Restoring Recovery Point");
    m_message = QStringLiteral("Verifying the authenticated recovery request…");
    m_progress = 5;
    m_armed = false;
    start(Operation::Apply, kind == QStringLiteral("update")
              ? QStringList{QStringLiteral("recovery-apply-update")}
              : QStringList{QStringLiteral("recovery-apply-backup"), path});
}

void RecoveryModeManager::cancelRecovery()
{
    m_view = QStringLiteral("progress");
    m_title = QStringLiteral("Cancelling Recovery");
    m_message = QStringLiteral("Recording cancellation safely…");
    m_progress = -1;
    m_armed = false;
    start(Operation::Cancel, {QStringLiteral("recovery-cancel")});
}

void RecoveryModeManager::requestReboot()
{
    start(Operation::Reboot, {QStringLiteral("recovery-reboot")});
}


void RecoveryModeManager::selectIndex(int index)
{
    if(m_busy) return;
    if(m_view == QStringLiteral("menu")) m_menuIndex=qBound(0,index,5);
    else if((m_view == QStringLiteral("selection") || m_view == QStringLiteral("manage")) && !m_recoveryPoints.isEmpty())
        m_selectedIndex=qBound(0,index,int(m_recoveryPoints.size())-1);
    m_armed=false;
    emit stateChanged();
}

bool RecoveryModeManager::handleAction(const QString &rawAction)
{
    const QString action=rawAction.trimmed().toLower();
    if(m_busy) return true;
    if(m_view == QStringLiteral("landing")) {
        if(action == QStringLiteral("primary")) {m_view=QStringLiteral("menu");emit stateChanged();}
        return true;
    }
    if(m_view == QStringLiteral("menu")) {
        if(action == QStringLiteral("up") || action == QStringLiteral("down")) {
            m_menuIndex=(m_menuIndex+(action==QStringLiteral("up")?-1:1)+6)%6;
        } else if(action == QStringLiteral("cancel")) m_view=QStringLiteral("landing");
        else if(action == QStringLiteral("primary")) {
            m_armed=false;
            if(m_menuIndex==0) m_view=QStringLiteral("selection");
            else if(m_menuIndex==3) m_view=QStringLiteral("manage");
            else if(m_menuIndex==4) m_view=QStringLiteral("tools");
            else if(m_menuIndex==5) {cancelRecovery();return true;}
            else if(m_menuIndex==1 && m_context.value(QStringLiteral("mode")).toString()==QStringLiteral("UPDATE"))
                m_view=QStringLiteral("selection");
            else {
                m_view=QStringLiteral("unavailable");
                m_message=QStringLiteral("A signature-verified full-install image and a supported Gemini reimage backend are required. This Recovery session preserves OS-owned code and does not erase disks. Return to System to stage a supported update.");
            }
        }
        emit stateChanged();return true;
    }
    if(m_view == QStringLiteral("tools") || m_view == QStringLiteral("unavailable")) {
        if(action==QStringLiteral("cancel"))m_view=QStringLiteral("menu");
        else if(action==QStringLiteral("primary") && m_view==QStringLiteral("tools")) {
            m_catalogReturn=QStringLiteral("tools");refresh();return true;
        }
        emit stateChanged();return true;
    }
    if(m_view==QStringLiteral("selection") || m_view==QStringLiteral("manage")) {
        if((action==QStringLiteral("up") || action==QStringLiteral("down")) && !m_recoveryPoints.isEmpty()) {
            m_selectedIndex=(m_selectedIndex+(action==QStringLiteral("up")?-1:1)+m_recoveryPoints.size())%m_recoveryPoints.size();m_armed=false;
        } else if(action==QStringLiteral("cancel")) {
            if(m_armed)m_armed=false;
            else m_view=QStringLiteral("menu");
        } else if(action==QStringLiteral("primary") && m_view==QStringLiteral("manage")) {
            if(selectedPath().isEmpty())m_message=QStringLiteral("No verified backup is selected.");
            else {m_message=QStringLiteral("Verifying selected backup…");start(Operation::Verify,{QStringLiteral("backup-verify"),selectedPath()});return true;}
        } else if(action==QStringLiteral("secondary") && m_view==QStringLiteral("manage")) {
            if(selectedPath().isEmpty())m_message=QStringLiteral("No verified backup is selected.");
            else if(!m_armed){m_armed=true;m_message=QStringLiteral("DELETE ARMED — Press Square again to delete only this backup. O cancels.");}
            else {m_armed=false;start(Operation::Delete,{QStringLiteral("backup-delete"),selectedPath()});return true;}
        } else if(action==QStringLiteral("primary") && m_view==QStringLiteral("selection")) {
            if(m_recoveryPoints.isEmpty())m_message=QStringLiteral("No verified recovery point is available.");
            else if(!m_armed){m_armed=true;m_message=QStringLiteral("RESTORE ARMED — Press X again to restore. O cancels.");}
            else {beginApply();return true;}
        }
        emit stateChanged();return true;
    }
    if(m_view == QStringLiteral("failure")) {
        if(action==QStringLiteral("up") || action==QStringLiteral("down"))m_failureOption=(m_failureOption+(action==QStringLiteral("up")?-1:1)+3)%3;
        else if(action==QStringLiteral("cancel")) {m_view=QStringLiteral("menu");m_armed=false;}
        else if(action==QStringLiteral("primary")) {
            if(m_failureOption==0) {m_catalogReturn=QStringLiteral("menu");refresh();return true;}
            if(m_failureOption==1){m_view=QStringLiteral("menu");m_armed=false;}
            else {cancelRecovery();return true;}
        }
        emit stateChanged();return true;
    }
    return true;
}

void RecoveryModeManager::onReadyRead()
{
    const QByteArray data = m_process.readAllStandardOutput();
    m_output.append(data);

    m_pendingProgress.append(data);
    const QRegularExpression progressPattern(QStringLiteral("^PROGRESS:(\\d{1,3}):(.*)$"));
    int newline=-1;
    while((newline=m_pendingProgress.indexOf('\n'))>=0) {
        const QByteArray line=m_pendingProgress.left(newline);
        m_pendingProgress.remove(0,newline+1);
        const auto match=progressPattern.match(QString::fromUtf8(line).trimmed());
        if(!match.hasMatch())continue;
        m_progress=qBound(0,match.captured(1).toInt(),100);
        m_message=match.captured(2).trimmed();
        emit stateChanged();
    }
}

QString RecoveryModeManager::sanitizedMessage(const QByteArray &output)
{
    QString message = QString::fromUtf8(output).trimmed();
    const QStringList lines = message.split('\n', Qt::SkipEmptyParts);
    message = lines.isEmpty() ? QStringLiteral("The Recovery operation failed.") : lines.constLast().trimmed();
    if (message.startsWith(QStringLiteral("{"))) {
        const QJsonObject object = QJsonDocument::fromJson(message.toUtf8()).object();
        message = object.value(QStringLiteral("message")).toString(message);
    }
    message.replace(QRegularExpression(QStringLiteral("/home/[^ ]+")), QStringLiteral("the protected recovery store"));
    return message.left(360);
}

void RecoveryModeManager::onFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    onReadyRead();
    const Operation operation = m_operation;
    m_operation = Operation::None;
    m_busy = false;
    if (operation == Operation::Status && exitStatus == QProcess::NormalExit && exitCode == 0) {
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(m_output.trimmed(), &error);
        const QJsonObject object = document.object();
        if (error.error != QJsonParseError::NoError || !document.isObject() ||
            object.value(QStringLiteral("active")).toBool() != true) {
            fail(QStringLiteral("The staged Recovery request is unavailable or invalid."));
            return;
        }
        m_context=object.toVariantMap();
        m_recoveryPoints.clear();
        const QJsonArray points = object.value(QStringLiteral("recoveryPoints")).toArray();
        const QString authorized = object.value(QStringLiteral("authorizedArchive")).toString();
        int authorizedIndex = -1;
        for (const QJsonValue &value : points) {
            QVariantMap point = value.toObject().toVariantMap();
            point.insert(QStringLiteral("kind"), QStringLiteral("backup"));
            if (point.value(QStringLiteral("path")).toString() == authorized)
                authorizedIndex = m_recoveryPoints.size();
            m_recoveryPoints.append(point);
        }
        if (object.value(QStringLiteral("mode")).toString() == QStringLiteral("UPDATE")) {
            QVariantMap point = object.value(QStringLiteral("update")).toObject().toVariantMap();
            point.insert(QStringLiteral("kind"), QStringLiteral("update"));
            point.insert(QStringLiteral("profile"), QStringLiteral("SIGNED UPDATE"));
            point.insert(QStringLiteral("verified"), true);
            m_recoveryPoints = {point};
            authorizedIndex = 0;
        }
        m_selectedIndex = authorizedIndex >= 0 ? authorizedIndex : 0;
        m_view = m_catalogReturn;
        m_catalogReturn=QStringLiteral("landing");
        m_title = object.value(QStringLiteral("mode")).toString() == QStringLiteral("UPDATE")
            ? QStringLiteral("Install Authenticated Update")
            : QStringLiteral("Restore Recovery Point");
        m_message = QStringLiteral("Select a verified recovery point. Press X twice to continue.");
        m_progress = -1;
        emit stateChanged();
        return;
    }
    if ((operation == Operation::Verify || operation == Operation::Delete) && exitStatus == QProcess::NormalExit && exitCode == 0) {
        m_message=operation==Operation::Verify?QStringLiteral("Backup verified against its checksum and archive manifest."):QStringLiteral("Selected backup deleted. Refreshing the catalog…");
        m_armed=false;
        if(operation==Operation::Delete){m_catalogReturn=QStringLiteral("manage");refresh();return;}
        m_view=QStringLiteral("manage");emit stateChanged();return;
    }
    if (operation == Operation::Apply && exitStatus == QProcess::NormalExit && exitCode == 0) {
        m_view = QStringLiteral("success");
        m_title = QStringLiteral("RESTORE COMPLETE");
        m_message = QStringLiteral("Recovery completed successfully. Rebooting into NeutronOS…");
        m_progress = 100;
        emit stateChanged();
        QTimer::singleShot(3500, this, &RecoveryModeManager::requestReboot);
        return;
    }
    if (operation == Operation::Cancel && exitStatus == QProcess::NormalExit && exitCode == 0) {
        m_view = QStringLiteral("progress");
        m_title = QStringLiteral("Recovery Cancelled");
        m_message = QStringLiteral("Rebooting without restoring…");
        emit stateChanged();
        QTimer::singleShot(800, this, &RecoveryModeManager::requestReboot);
        return;
    }
    if (operation == Operation::Reboot && exitStatus == QProcess::NormalExit && exitCode == 0)
        return;
    fail(sanitizedMessage(m_output));
}

void RecoveryModeManager::fail(const QString &message)
{
    m_operation = Operation::None;
    m_busy = false;
    m_view = QStringLiteral("failure");
    m_title = QStringLiteral("RECOVERY FAILED");
    m_message = message;
    m_progress = -1;
    m_armed = false;
    m_failureOption = 0;
    emit stateChanged();
}
