#include "LogsManager.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>

LogsManager::LogsManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot))
{
    refreshSources();
}

LogsManager::~LogsManager()
{
    stopLive();
}

QVariantList LogsManager::sources() const { return m_sources; }
QString LogsManager::output() const { return m_output; }
bool LogsManager::live() const { return m_live; }
bool LogsManager::busy() const { return m_busy; }
QString LogsManager::activeSourceId() const { return m_activeSourceId; }
QString LogsManager::activeSourceName() const { return m_activeSourceName; }
QString LogsManager::lastMessage() const { return m_lastMessage; }

QString LogsManager::executable(const QString &name)
{
    return QStandardPaths::findExecutable(name);
}

QString LogsManager::sourceId(const QString &type, const QString &target)
{
    const QByteArray digest = QCryptographicHash::hash(
        (type + QLatin1Char(':') + target).toUtf8(),
        QCryptographicHash::Sha256
    ).toHex().left(16);
    return type + QLatin1Char('-') + QString::fromLatin1(digest);
}

int LogsManager::runSync(const QString &program,
                         const QStringList &arguments,
                         QByteArray *standardOutput,
                         QByteArray *standardError,
                         int timeoutMs)
{
    QProcess process;
    process.setProgram(program);
    process.setArguments(arguments);
    process.start();
    if (!process.waitForStarted(3000)) {
        if (standardError)
            *standardError = process.errorString().toUtf8();
        return -1;
    }
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(1000);
        if (standardError)
            *standardError = QByteArrayLiteral("Command timed out");
        return -124;
    }
    if (standardOutput)
        *standardOutput = process.readAllStandardOutput();
    if (standardError)
        *standardError = process.readAllStandardError();
    return process.exitCode();
}

void LogsManager::discoverSystemd(QVariantList *target) const
{
    const QString systemctl = executable(QStringLiteral("systemctl"));
    if (systemctl.isEmpty())
        return;
    QByteArray output;
    QByteArray error;
    const int rc = runSync(
        systemctl,
        {QStringLiteral("list-units"), QStringLiteral("--type=service"),
         QStringLiteral("--all"), QStringLiteral("--no-legend"),
         QStringLiteral("--no-pager"), QStringLiteral("--plain")},
        &output,
        &error,
        12000
    );
    if (rc != 0)
        return;

    const QStringList lines = QString::fromUtf8(output).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    const QRegularExpression spaces(QStringLiteral("\\s+"));
    for (const QString &line : lines) {
        QString trimmed = line.trimmed();
        if (trimmed.startsWith(QChar(0x25CF)))
            trimmed = trimmed.mid(1).trimmed();
        if (trimmed.isEmpty())
            continue;
        const QStringList parts = trimmed.split(spaces, Qt::SkipEmptyParts);
        if (parts.size() < 4)
            continue;
        const QString unit = parts.at(0);
        const QString active = parts.value(2);
        const QString sub = parts.value(3);
        const int descriptionStart = trimmed.indexOf(sub) + sub.size();
        const QString description = descriptionStart >= 0
            ? trimmed.mid(descriptionStart).trimmed()
            : unit;
        QVariantMap item;
        item[QStringLiteral("id")] = sourceId(QStringLiteral("service"), unit);
        item[QStringLiteral("type")] = QStringLiteral("service");
        item[QStringLiteral("target")] = unit;
        item[QStringLiteral("name")] = unit;
        item[QStringLiteral("description")] = description;
        item[QStringLiteral("running")] = active == QStringLiteral("active");
        item[QStringLiteral("status")] = active + QLatin1Char('/') + sub;

        QString origin = QStringLiteral("system");
        const QString loweredUnit = unit.toLower();
        if (loweredUnit.startsWith(QStringLiteral("neutron"))) {
            origin = QStringLiteral("neutronos");
        } else {
            const QFileInfo etcUnit(QDir(QStringLiteral("/etc/systemd/system")).filePath(unit));
            const QFileInfo localUnit(QDir(QStringLiteral("/usr/local/lib/systemd/system")).filePath(unit));
            if (etcUnit.exists() || etcUnit.isSymLink() || localUnit.exists() || localUnit.isSymLink())
                origin = QStringLiteral("user");
        }
        item[QStringLiteral("origin")] = origin;
        item[QStringLiteral("originLabel")] = origin == QStringLiteral("neutronos")
            ? QStringLiteral("NeutronOS")
            : (origin == QStringLiteral("user") ? QStringLiteral("User installed") : QStringLiteral("System"));
        item[QStringLiteral("liveSupported")] = true;
        target->append(item);
    }
}

void LogsManager::discoverDocker(QVariantList *target) const
{
    const QString docker = executable(QStringLiteral("docker"));
    if (docker.isEmpty())
        return;
    QByteArray output;
    QByteArray error;
    const int rc = runSync(
        docker,
        {QStringLiteral("ps"), QStringLiteral("-a"),
         QStringLiteral("--format"), QStringLiteral("{{.ID}}\t{{.Names}}\t{{.State}}\t{{.Status}}")},
        &output,
        &error,
        10000
    );
    if (rc != 0)
        return;
    const QStringList lines = QString::fromUtf8(output).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QStringList parts = line.split(QLatin1Char('\t'));
        if (parts.size() < 3)
            continue;
        const QString id = parts.at(0).trimmed();
        const QString name = parts.at(1).trimmed();
        const QString state = parts.at(2).trimmed();
        QVariantMap item;
        item[QStringLiteral("id")] = sourceId(QStringLiteral("docker"), id);
        item[QStringLiteral("type")] = QStringLiteral("docker");
        item[QStringLiteral("target")] = id;
        item[QStringLiteral("name")] = name;
        item[QStringLiteral("description")] = QStringLiteral("Docker container");
        item[QStringLiteral("running")] = state.compare(QStringLiteral("running"), Qt::CaseInsensitive) == 0;
        item[QStringLiteral("status")] = parts.value(3, state).trimmed();
        item[QStringLiteral("liveSupported")] = true;
        target->append(item);
    }
}

void LogsManager::discoverLogFiles(QVariantList *target) const
{
    QStringList candidates = {
        QStringLiteral("/var/log/syslog"),
        QStringLiteral("/var/log/messages"),
        QStringLiteral("/var/log/kern.log"),
        QStringLiteral("/var/log/auth.log"),
        QStringLiteral("/var/log/daemon.log"),
        m_neutronRoot + QStringLiteral("/state/apps/browser/runtime/last-runtime.log"),
        m_neutronRoot + QStringLiteral("/state/apps/browser/runtime/last-exit-code")
    };
    const QStringList roots = {
        m_neutronRoot + QStringLiteral("/state/logs"),
        QStringLiteral("/var/log/neutronos")
    };
    for (const QString &root : roots) {
        QDirIterator iterator(root, {QStringLiteral("*.log"), QStringLiteral("*.txt")},
                              QDir::Files, QDirIterator::Subdirectories);
        while (iterator.hasNext())
            candidates.append(iterator.next());
    }
    candidates.removeDuplicates();
    for (const QString &path : candidates) {
        const QFileInfo info(path);
        if (!info.exists() || !info.isFile() || !info.isReadable())
            continue;
        QVariantMap item;
        item[QStringLiteral("id")] = sourceId(QStringLiteral("file"), info.absoluteFilePath());
        item[QStringLiteral("type")] = QStringLiteral("file");
        item[QStringLiteral("target")] = info.absoluteFilePath();
        item[QStringLiteral("name")] = info.fileName();
        item[QStringLiteral("description")] = info.absolutePath();
        item[QStringLiteral("running")] = false;
        item[QStringLiteral("status")] = QStringLiteral("log file");
        item[QStringLiteral("liveSupported")] = true;
        item[QStringLiteral("modified")] = info.lastModified().toString(Qt::ISODate);
        target->append(item);
    }
}

void LogsManager::discoverScripts(QVariantList *target) const
{
    const QString scriptsRoot = m_neutronRoot + QStringLiteral("/scripts");
    QDirIterator iterator(scriptsRoot, {QStringLiteral("*.sh"), QStringLiteral("*.py")},
                          QDir::Files, QDirIterator::Subdirectories);
    while (iterator.hasNext()) {
        const QFileInfo info(iterator.next());
        QVariantMap item;
        item[QStringLiteral("id")] = sourceId(QStringLiteral("script"), info.absoluteFilePath());
        item[QStringLiteral("type")] = QStringLiteral("script");
        item[QStringLiteral("target")] = info.absoluteFilePath();
        item[QStringLiteral("name")] = info.fileName();
        item[QStringLiteral("description")] = QStringLiteral("NeutronOS service script · last available content");
        item[QStringLiteral("running")] = false;
        item[QStringLiteral("status")] = info.isExecutable() ? QStringLiteral("executable") : QStringLiteral("script");
        item[QStringLiteral("liveSupported")] = false;
        item[QStringLiteral("modified")] = info.lastModified().toString(Qt::ISODate);
        target->append(item);
    }
}

void LogsManager::refreshSources()
{
    QVariantList next;
    discoverSystemd(&next);
    discoverDocker(&next);
    discoverLogFiles(&next);
    discoverScripts(&next);
    m_sources = next;
    m_lastMessage = QStringLiteral("%1 log source%2 available.")
                        .arg(next.size())
                        .arg(next.size() == 1 ? QString() : QStringLiteral("s"));
    emit sourcesChanged();
    emit stateChanged();
}

QVariantMap LogsManager::findSource(const QString &sourceIdValue) const
{
    for (const QVariant &entry : m_sources) {
        const QVariantMap source = entry.toMap();
        if (source.value(QStringLiteral("id")).toString() == sourceIdValue)
            return source;
    }
    return {};
}

QVariantMap LogsManager::sourceDetails(const QString &sourceIdValue) const
{
    return findSource(sourceIdValue);
}

void LogsManager::appendOutput(const QByteArray &data)
{
    if (data.isEmpty())
        return;
    m_output.append(QString::fromUtf8(data));
    if (m_output.size() > m_maxOutputCharacters)
        m_output = m_output.right(m_maxOutputCharacters);
    emit outputChanged();
}

void LogsManager::setMessage(const QString &message)
{
    m_lastMessage = message;
    emit stateChanged();
}

bool LogsManager::startSource(const QVariantMap &source, bool liveMode, int lines)
{
    if (source.isEmpty()) {
        setMessage(QStringLiteral("The selected log source no longer exists."));
        return false;
    }
    stopLive();
    clearOutput();

    const QString type = source.value(QStringLiteral("type")).toString();
    const QString target = source.value(QStringLiteral("target")).toString();
    QString program;
    QStringList arguments;

    if (type == QStringLiteral("service")) {
        program = executable(QStringLiteral("journalctl"));
        if (liveMode)
            arguments << QStringLiteral("-f");
        arguments << QStringLiteral("-u") << target
                  << QStringLiteral("-n") << QString::number(qBound(20, lines, 5000))
                  << QStringLiteral("--no-pager") << QStringLiteral("-o") << QStringLiteral("short-iso");
    } else if (type == QStringLiteral("docker")) {
        program = executable(QStringLiteral("docker"));
        arguments << QStringLiteral("logs");
        if (liveMode)
            arguments << QStringLiteral("--follow");
        arguments << QStringLiteral("--tail") << QString::number(qBound(20, lines, 5000)) << target;
    } else if (type == QStringLiteral("file")) {
        program = executable(QStringLiteral("tail"));
        arguments << (liveMode ? QStringLiteral("-F") : QStringLiteral("-n"));
        if (liveMode)
            arguments << QStringLiteral("-n") << QString::number(qBound(20, lines, 5000));
        else
            arguments << QString::number(qBound(20, lines, 5000));
        arguments << target;
    } else if (type == QStringLiteral("script")) {
        QFile file(target);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            setMessage(QStringLiteral("Unable to read the selected script."));
            return false;
        }
        appendOutput(QByteArrayLiteral("# Script source: ") + target.toUtf8() + QByteArrayLiteral("\n\n"));
        appendOutput(file.readAll());
        m_activeSourceId = source.value(QStringLiteral("id")).toString();
        m_activeSourceName = source.value(QStringLiteral("name")).toString();
        m_live = false;
        m_busy = false;
        setMessage(QStringLiteral("Last available script content loaded."));
        return true;
    }

    if (program.isEmpty()) {
        setMessage(QStringLiteral("Required log command is unavailable."));
        return false;
    }

    if (!m_process) {
        m_process = new QProcess(this);
        connect(m_process, &QProcess::readyReadStandardOutput, this, &LogsManager::onReadyRead);
        connect(m_process, &QProcess::readyReadStandardError, this, &LogsManager::onReadyRead);
        connect(m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                this, &LogsManager::onFinished);
        connect(m_process, &QProcess::errorOccurred, this, &LogsManager::onProcessError);
    }

    m_activeSourceId = source.value(QStringLiteral("id")).toString();
    m_activeSourceName = source.value(QStringLiteral("name")).toString();
    m_live = liveMode;
    m_busy = true;
    m_lastMessage = liveMode ? QStringLiteral("Live logs connected.")
                             : QStringLiteral("Loading last available logs.");
    emit stateChanged();

    m_process->setProgram(program);
    m_process->setArguments(arguments);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_process->start();
    return true;
}

bool LogsManager::loadLive(const QString &sourceIdValue)
{
    const QVariantMap source = findSource(sourceIdValue);
    if (!source.value(QStringLiteral("liveSupported")).toBool())
        return loadHistory(sourceIdValue, 500);
    return startSource(source, true, 150);
}

bool LogsManager::loadHistory(const QString &sourceIdValue, int lines)
{
    return startSource(findSource(sourceIdValue), false, lines);
}

bool LogsManager::stopLive()
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->terminate();
        if (!m_process->waitForFinished(800))
            m_process->kill();
        m_process->deleteLater();
        m_process = nullptr;
    }
    const bool changed = m_live || m_busy;
    m_live = false;
    m_busy = false;
    if (changed)
        emit stateChanged();
    return changed;
}

void LogsManager::clearOutput()
{
    if (m_output.isEmpty())
        return;
    m_output.clear();
    emit outputChanged();
}

void LogsManager::onReadyRead()
{
    if (!m_process)
        return;
    appendOutput(m_process->readAllStandardOutput());
    appendOutput(m_process->readAllStandardError());
}

void LogsManager::onFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    onReadyRead();
    const bool wasLive = m_live;
    m_busy = false;
    m_live = false;
    if (exitStatus == QProcess::NormalExit && exitCode == 0)
        m_lastMessage = wasLive ? QStringLiteral("Live log stream ended.")
                                : QStringLiteral("Last available logs loaded.");
    else
        m_lastMessage = QStringLiteral("Log command ended with code %1.").arg(exitCode);
    emit stateChanged();
}

void LogsManager::onProcessError(QProcess::ProcessError error)
{
    Q_UNUSED(error)
    m_busy = false;
    m_live = false;
    m_lastMessage = m_process ? m_process->errorString() : QStringLiteral("Log process failed.");
    emit stateChanged();
}
