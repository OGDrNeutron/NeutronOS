#include "DockerManager.h"

#include <QDateTime>
#include <QAbstractSocket>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaType>
#include <QNetworkInterface>
#include <QHostAddress>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>

namespace {
QString variantString(const QVariantMap &map, const QString &key)
{
    return map.value(key).toString().trimmed();
}

bool looksRunning(const QString &state)
{
    const QString normalized = state.trimmed().toLower();
    return normalized == QStringLiteral("running") ||
           normalized == QStringLiteral("restarting") ||
           normalized == QStringLiteral("paused");
}

QString primaryHostIpv4()
{
    struct Candidate {
        int score = 0;
        QString address;
    };

    Candidate best;
    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : interfaces) {
        const auto flags = iface.flags();
        if (!flags.testFlag(QNetworkInterface::IsUp) ||
            !flags.testFlag(QNetworkInterface::IsRunning) ||
            flags.testFlag(QNetworkInterface::IsLoopBack)) {
            continue;
        }

        const QString name = iface.name().toLower();
        if (name.startsWith(QStringLiteral("docker")) ||
            name.startsWith(QStringLiteral("br-")) ||
            name.startsWith(QStringLiteral("veth")) ||
            name.startsWith(QStringLiteral("tailscale")) ||
            name.startsWith(QStringLiteral("tun")) ||
            name.startsWith(QStringLiteral("tap"))) {
            continue;
        }

        int interfaceScore = 10;
        if (name.startsWith(QStringLiteral("eth")) ||
            name.startsWith(QStringLiteral("en")))
            interfaceScore = 40;
        else if (name.startsWith(QStringLiteral("wlan")) ||
                 name.startsWith(QStringLiteral("wl")))
            interfaceScore = 35;

        for (const QNetworkAddressEntry &entry : iface.addressEntries()) {
            const QHostAddress address = entry.ip();
            if (address.protocol() != QAbstractSocket::IPv4Protocol || address.isLoopback())
                continue;
            const QString text = address.toString();
            if (text.startsWith(QStringLiteral("169.254.")) || text == QStringLiteral("0.0.0.0"))
                continue;
            if (interfaceScore > best.score)
                best = {interfaceScore, text};
        }
    }
    return best.address;
}

QString publishedHostAddress(const QString &bindingAddress, const QString &fallback)
{
    const QString address = bindingAddress.trimmed();
    if (address.isEmpty() || address == QStringLiteral("0.0.0.0") || address == QStringLiteral("::"))
        return fallback.isEmpty() ? QStringLiteral("localhost") : fallback;
    return address;
}
}

DockerManager::DockerManager(QObject *parent)
    : QObject(parent)
{
    QTimer::singleShot(2600, this, &DockerManager::refresh);
}

DockerManager::~DockerManager()
{
    cancelOperation();
}

QVariantList DockerManager::containers() const { return m_containers; }
bool DockerManager::dockerAvailable() const { return m_dockerAvailable; }
bool DockerManager::daemonActive() const { return m_daemonActive; }
bool DockerManager::daemonEnabled() const { return m_daemonEnabled; }
bool DockerManager::busy() const { return m_busy; }
QString DockerManager::operationName() const { return m_operationName; }
QString DockerManager::operationStatus() const { return m_operationStatus; }
int DockerManager::operationProgress() const { return m_operationProgress; }
QString DockerManager::lastMessage() const { return m_lastMessage; }

QString DockerManager::dockerExecutable()
{
    return QStandardPaths::findExecutable(QStringLiteral("docker"));
}

QString DockerManager::humanBytes(qulonglong bytes)
{
    static const QStringList units = {
        QStringLiteral("B"), QStringLiteral("KiB"), QStringLiteral("MiB"),
        QStringLiteral("GiB"), QStringLiteral("TiB")
    };
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < units.size() - 1) {
        value /= 1024.0;
        ++unit;
    }
    return QStringLiteral("%1 %2").arg(value, 0, unit == 0 ? 'f' : 'f', unit == 0 ? 0 : 1)
                                 .arg(units.at(unit));
}

QString DockerManager::formatBytes(qulonglong bytes) const
{
    return humanBytes(bytes);
}

QString DockerManager::sanitizedName(const QString &name)
{
    const QString clean = name.trimmed();
    static const QRegularExpression pattern(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$"));
    return pattern.match(clean).hasMatch() ? clean : QString();
}

QString DockerManager::sanitizedImage(const QString &image)
{
    const QString clean = image.trimmed();
    static const QRegularExpression pattern(
        QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,255}$"));
    return pattern.match(clean).hasMatch() ? clean : QString();
}

QStringList DockerManager::splitLines(const QVariant &value)
{
    QString text;
    if (value.metaType().id() == QMetaType::QStringList)
        return value.toStringList();
    text = value.toString();
    QStringList output;
    const QStringList lines = text.split(QRegularExpression(QStringLiteral("[\r\n,]+")), Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QString clean = line.trimmed();
        if (!clean.isEmpty())
            output.append(clean);
    }
    return output;
}

bool DockerManager::safeArgumentLine(const QString &value)
{
    if (value.isEmpty() || value.size() > 1024)
        return false;
    for (const QChar ch : value) {
        if (ch.unicode() < 0x20 && ch != QLatin1Char('\t'))
            return false;
    }
    return true;
}

QVariantMap DockerManager::result(bool ok, const QString &message)
{
    return {{QStringLiteral("ok"), ok}, {QStringLiteral("message"), message}};
}

int DockerManager::runSync(const QString &program,
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
        process.waitForFinished(2000);
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

void DockerManager::refresh()
{
    const QString docker = dockerExecutable();
    const bool available = !docker.isEmpty();

    bool daemonActiveNow = false;
    bool daemonEnabledNow = false;
    const QString systemctl = QStandardPaths::findExecutable(QStringLiteral("systemctl"));
    if (!systemctl.isEmpty()) {
        daemonActiveNow = runSync(systemctl,
                                  {QStringLiteral("is-active"), QStringLiteral("--quiet"),
                                   QStringLiteral("docker.service")},
                                  nullptr, nullptr, 4000) == 0;
        daemonEnabledNow = runSync(systemctl,
                                   {QStringLiteral("is-enabled"), QStringLiteral("--quiet"),
                                    QStringLiteral("docker.service")},
                                   nullptr, nullptr, 4000) == 0;
    }

    const bool availabilityChangedNow =
        available != m_dockerAvailable ||
        daemonActiveNow != m_daemonActive ||
        daemonEnabledNow != m_daemonEnabled;

    m_dockerAvailable = available;
    m_daemonActive = daemonActiveNow;
    m_daemonEnabled = daemonEnabledNow;

    if (availabilityChangedNow)
        emit availabilityChanged();

    QVariantList next;
    if (!available) {
        m_containers = next;
        m_lastMessage = QStringLiteral("Docker is not installed.");
        emit containersChanged();
        emit operationChanged();
        return;
    }

    if (!m_daemonActive) {
        m_containers = next;
        m_lastMessage = QStringLiteral("Docker engine is stopped.");
        emit containersChanged();
        emit operationChanged();
        return;
    }

    QByteArray output;
    QByteArray error;
    const int rc = runSync(
        docker,
        {QStringLiteral("ps"), QStringLiteral("-a"), QStringLiteral("--no-trunc"),
         QStringLiteral("--format"), QStringLiteral("{{json .}}")},
        &output,
        &error,
        12000
    );

    if (rc != 0) {
        m_lastMessage = error.trimmed().isEmpty()
            ? QStringLiteral("Unable to query Docker containers.")
            : QString::fromUtf8(error).trimmed();
        emit operationChanged();
        return;
    }

    const QList<QByteArray> lines = output.split('\n');
    for (const QByteArray &line : lines) {
        if (line.trimmed().isEmpty())
            continue;
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject())
            continue;
        const QJsonObject object = document.object();
        const QString id = object.value(QStringLiteral("ID")).toString();
        const QString name = object.value(QStringLiteral("Names")).toString();
        const QString state = object.value(QStringLiteral("State")).toString();
        QVariantMap item;
        item[QStringLiteral("id")] = id;
        item[QStringLiteral("name")] = name;
        item[QStringLiteral("image")] = object.value(QStringLiteral("Image")).toString();
        item[QStringLiteral("state")] = state;
        item[QStringLiteral("running")] = looksRunning(state);
        item[QStringLiteral("status")] = object.value(QStringLiteral("Status")).toString();
        item[QStringLiteral("ports")] = object.value(QStringLiteral("Ports")).toString();
        item[QStringLiteral("mounts")] = object.value(QStringLiteral("Mounts")).toString();
        item[QStringLiteral("networks")] = object.value(QStringLiteral("Networks")).toString();
        item[QStringLiteral("createdAt")] = object.value(QStringLiteral("CreatedAt")).toString();
        item[QStringLiteral("runningFor")] = object.value(QStringLiteral("RunningFor")).toString();
        item[QStringLiteral("command")] = object.value(QStringLiteral("Command")).toString();
        next.append(item);
    }

    m_containers = next;
    m_lastMessage = QStringLiteral("%1 container%2 detected.")
                        .arg(next.size())
                        .arg(next.size() == 1 ? QString() : QStringLiteral("s"));
    emit containersChanged();
    emit operationChanged();
}

QVariantMap DockerManager::findContainer(const QString &containerId) const
{
    const QString needle = containerId.trimmed();
    for (const QVariant &entry : m_containers) {
        const QVariantMap item = entry.toMap();
        const QString id = item.value(QStringLiteral("id")).toString();
        const QString name = item.value(QStringLiteral("name")).toString();
        if (id == needle || name == needle || (!needle.isEmpty() && id.startsWith(needle)))
            return item;
    }
    return {};
}

bool DockerManager::knownContainer(const QString &containerId) const
{
    return !findContainer(containerId).isEmpty();
}

QVariantMap DockerManager::containerDetails(const QString &containerId) const
{
    const QVariantMap summary = findContainer(containerId);
    if (summary.isEmpty())
        return result(false, QStringLiteral("Unknown Docker container."));

    const QString docker = dockerExecutable();
    QByteArray output;
    QByteArray error;
    const int rc = runSync(docker,
                           {QStringLiteral("inspect"), summary.value(QStringLiteral("id")).toString()},
                           &output,
                           &error,
                           12000);
    if (rc != 0)
        return result(false, QString::fromUtf8(error).trimmed());

    const QJsonDocument document = QJsonDocument::fromJson(output);
    if (!document.isArray() || document.array().isEmpty())
        return result(false, QStringLiteral("Docker inspect returned no details."));

    const QJsonObject object = document.array().at(0).toObject();
    const QJsonObject config = object.value(QStringLiteral("Config")).toObject();
    const QJsonObject host = object.value(QStringLiteral("HostConfig")).toObject();
    const QJsonObject state = object.value(QStringLiteral("State")).toObject();
    const QJsonObject network = object.value(QStringLiteral("NetworkSettings")).toObject();

    QVariantMap details = summary;
    details[QStringLiteral("ok")] = true;
    details[QStringLiteral("fullId")] = object.value(QStringLiteral("Id")).toString();
    details[QStringLiteral("created")] = object.value(QStringLiteral("Created")).toString();
    details[QStringLiteral("platform")] = object.value(QStringLiteral("Platform")).toString();
    details[QStringLiteral("restartPolicy")] = host.value(QStringLiteral("RestartPolicy")).toObject()
                                                   .value(QStringLiteral("Name")).toString();
    details[QStringLiteral("cpuNano")] = static_cast<qlonglong>(host.value(QStringLiteral("NanoCpus")).toDouble());
    details[QStringLiteral("memoryBytes")] = static_cast<qlonglong>(host.value(QStringLiteral("Memory")).toDouble());
    details[QStringLiteral("workingDir")] = config.value(QStringLiteral("WorkingDir")).toString();
    details[QStringLiteral("user")] = config.value(QStringLiteral("User")).toString();
    details[QStringLiteral("hostname")] = config.value(QStringLiteral("Hostname")).toString();
    details[QStringLiteral("exitCode")] = state.value(QStringLiteral("ExitCode")).toInt();
    details[QStringLiteral("startedAt")] = state.value(QStringLiteral("StartedAt")).toString();
    details[QStringLiteral("finishedAt")] = state.value(QStringLiteral("FinishedAt")).toString();
    details[QStringLiteral("ipAddress")] = network.value(QStringLiteral("IPAddress")).toString();

    const QString containerName = summary.value(QStringLiteral("name")).toString().trimmed();
    details[QStringLiteral("startCommand")] = containerName.isEmpty()
        ? QString()
        : QStringLiteral("sudo docker start %1").arg(containerName);

    QStringList environment;
    for (const QJsonValue &value : config.value(QStringLiteral("Env")).toArray())
        environment.append(value.toString());
    details[QStringLiteral("environment")] = environment;

    QStringList command;
    for (const QJsonValue &value : config.value(QStringLiteral("Cmd")).toArray())
        command.append(value.toString());
    details[QStringLiteral("commandList")] = command;

    QStringList binds;
    for (const QJsonValue &value : host.value(QStringLiteral("Binds")).toArray())
        binds.append(value.toString());
    details[QStringLiteral("binds")] = binds;

    QStringList savedLocations;
    QStringList mountDetails;
    const QJsonArray mounts = object.value(QStringLiteral("Mounts")).toArray();
    for (const QJsonValue &value : mounts) {
        const QJsonObject mount = value.toObject();
        const QString source = mount.value(QStringLiteral("Source")).toString().trimmed();
        const QString destination = mount.value(QStringLiteral("Destination")).toString().trimmed();
        const QString name = mount.value(QStringLiteral("Name")).toString().trimmed();
        const QString type = mount.value(QStringLiteral("Type")).toString().trimmed();
        const bool readWrite = mount.value(QStringLiteral("RW")).toBool(true);

        QString storedAt = source;
        if (storedAt.isEmpty() && !name.isEmpty())
            storedAt = QStringLiteral("Docker volume: %1").arg(name);
        if (!storedAt.isEmpty() && !savedLocations.contains(storedAt))
            savedLocations.append(storedAt);

        QString description = storedAt;
        if (!destination.isEmpty()) {
            if (!description.isEmpty())
                description += QStringLiteral("  →  ");
            description += destination;
        }
        if (!type.isEmpty())
            description += QStringLiteral("  [%1]").arg(type);
        if (!readWrite)
            description += QStringLiteral("  [read-only]");
        if (!description.isEmpty())
            mountDetails.append(description);
    }
    details[QStringLiteral("savedLocations")] = savedLocations;
    details[QStringLiteral("mountDetails")] = mountDetails;

    const QString hostIpv4 = primaryHostIpv4();
    details[QStringLiteral("hostIpAddress")] = hostIpv4;

    const QJsonObject portBindings = host.value(QStringLiteral("PortBindings")).toObject();
    QStringList ports;
    QStringList publishedEndpoints;
    for (auto it = portBindings.constBegin(); it != portBindings.constEnd(); ++it) {
        const QString containerPort = it.key();
        const QString protocol = containerPort.section(QLatin1Char('/'), 1, 1).toUpper();
        for (const QJsonValue &bindingValue : it.value().toArray()) {
            const QJsonObject binding = bindingValue.toObject();
            const QString bindingAddress = binding.value(QStringLiteral("HostIp")).toString();
            const QString hostPort = binding.value(QStringLiteral("HostPort")).toString().trimmed();
            if (hostPort.isEmpty())
                continue;

            const QString address = publishedHostAddress(bindingAddress, hostIpv4);
            const QString endpoint = QStringLiteral("%1:%2%3")
                .arg(address, hostPort, protocol == QStringLiteral("UDP")
                                      ? QStringLiteral("  UDP")
                                      : QString());
            if (!publishedEndpoints.contains(endpoint))
                publishedEndpoints.append(endpoint);

            ports.append(bindingAddress + QLatin1Char(':') + hostPort +
                         QLatin1Char(':') + containerPort);
        }
    }
    details[QStringLiteral("portBindings")] = ports;
    details[QStringLiteral("publishedEndpoints")] = publishedEndpoints;
    return details;
}

void DockerManager::setOperation(const QString &name,
                                 const QString &status,
                                 int progress,
                                 const QString &message)
{
    m_operationName = name;
    m_operationStatus = status;
    m_operationProgress = progress;
    if (!message.isEmpty())
        m_lastMessage = message;
    emit operationChanged();
}

bool DockerManager::startSteps(const QString &operationName,
                               const QList<CommandStep> &steps)
{
    if (m_busy || steps.isEmpty())
        return false;
    m_busy = true;
    m_steps = steps;
    m_stepIndex = -1;
    m_output.clear();
    setOperation(operationName, QStringLiteral("Preparing"), 0);
    startNextStep();
    return true;
}

void DockerManager::startNextStep()
{
    ++m_stepIndex;
    if (m_stepIndex >= m_steps.size()) {
        finishOperation(true, m_operationName + QStringLiteral(" completed."));
        return;
    }

    if (!m_process) {
        m_process = new QProcess(this);
        connect(m_process, &QProcess::readyReadStandardOutput, this, &DockerManager::onReadyRead);
        connect(m_process, &QProcess::readyReadStandardError, this, &DockerManager::onReadyRead);
        connect(m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                this, &DockerManager::onFinished);
        connect(m_process, &QProcess::errorOccurred,
                this, &DockerManager::onProcessError);
    }

    const CommandStep &step = m_steps.at(m_stepIndex);
    const int progress = static_cast<int>((100.0 * m_stepIndex) / qMax(1, m_steps.size()));
    setOperation(m_operationName, step.description, progress);
    m_process->setProgram(step.program);
    m_process->setArguments(step.arguments);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);
    m_process->start();
}

void DockerManager::finishOperation(bool success, const QString &message)
{
    m_busy = false;
    m_operationProgress = success ? 100 : -1;
    m_operationStatus = success ? QStringLiteral("Complete") : QStringLiteral("Failed");
    m_lastMessage = message;
    m_steps.clear();
    m_stepIndex = -1;
    emit operationChanged();
    refresh();
    emit operationFinished(success, message);
}

void DockerManager::onReadyRead()
{
    if (!m_process)
        return;
    m_output += m_process->readAllStandardOutput();
    m_output += m_process->readAllStandardError();
    if (m_output.size() > 512 * 1024)
        m_output = m_output.right(512 * 1024);
}

void DockerManager::onFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (!m_busy || m_stepIndex < 0 || m_stepIndex >= m_steps.size())
        return;
    onReadyRead();
    const CommandStep step = m_steps.at(m_stepIndex);
    const bool ok = exitStatus == QProcess::NormalExit && (exitCode == 0 || step.tolerateNonZero);
    if (!ok) {
        const QString detail = QString::fromUtf8(m_output).trimmed();
        finishOperation(false, detail.isEmpty() ? step.description + QStringLiteral(" failed.") : detail);
        return;
    }
    m_output.clear();
    startNextStep();
}

bool DockerManager::toggleContainer(const QString &containerId)
{
    if (!m_daemonActive) {
        m_lastMessage = QStringLiteral("Start the Docker engine before managing containers.");
        emit operationChanged();
        return false;
    }
    const QVariantMap container = findContainer(containerId);
    if (container.isEmpty() || m_busy)
        return false;

    const bool running = container.value(QStringLiteral("running")).toBool();
    const QString id = container.value(QStringLiteral("id")).toString();
    const QString docker = dockerExecutable();

    if (running) {
        // docker stop records an intentional stop and suppresses the restart
        // policy for this daemon lifetime. Never rewrite the user's persistent
        // autostart policy merely because the UI requested a stop.
        return startSteps(
            QStringLiteral("Stop Container"),
            {
                {docker,
                 {QStringLiteral("stop"), QStringLiteral("--time"), QStringLiteral("8"), id},
                 QStringLiteral("Stopping container"),
                 false}
            }
        );
    }

    return startSteps(
        QStringLiteral("Start Container"),
        {{docker, {QStringLiteral("start"), id},
          QStringLiteral("Starting container"), false}}
    );
}

bool DockerManager::createContainer(const QVariantMap &configuration)
{
    if (m_busy || !m_dockerAvailable || !m_daemonActive) {
        m_lastMessage = !m_dockerAvailable
            ? QStringLiteral("Docker is not installed.")
            : QStringLiteral("Start the Docker engine before creating a container.");
        emit operationChanged();
        return false;
    }
    const QString name = sanitizedName(variantString(configuration, QStringLiteral("name")));
    const QString image = sanitizedImage(variantString(configuration, QStringLiteral("image")));
    if (name.isEmpty() || image.isEmpty()) {
        m_lastMessage = QStringLiteral("Container name or image is invalid.");
        emit operationChanged();
        return false;
    }

    QStringList createArgs{QStringLiteral("create"), QStringLiteral("--name"), name};
    const QString restart = variantString(configuration, QStringLiteral("restartPolicy")).toLower();
    const QStringList allowedRestart = {QStringLiteral("no"), QStringLiteral("always"),
                                        QStringLiteral("unless-stopped"), QStringLiteral("on-failure")};
    createArgs << QStringLiteral("--restart") << (allowedRestart.contains(restart) ? restart : QStringLiteral("no"));

    for (const QString &port : splitLines(configuration.value(QStringLiteral("ports")))) {
        if (!safeArgumentLine(port))
            return false;
        createArgs << QStringLiteral("-p") << port;
    }
    for (const QString &volume : splitLines(configuration.value(QStringLiteral("volumes")))) {
        if (!safeArgumentLine(volume))
            return false;
        createArgs << QStringLiteral("-v") << volume;
    }
    for (const QString &environment : splitLines(configuration.value(QStringLiteral("environment")))) {
        if (!safeArgumentLine(environment) || !environment.contains(QLatin1Char('=')))
            return false;
        createArgs << QStringLiteral("-e") << environment;
    }

    createArgs << image;
    const QString command = variantString(configuration, QStringLiteral("command"));
    if (!command.isEmpty()) {
        if (!safeArgumentLine(command))
            return false;
        createArgs.append(QProcess::splitCommand(command));
    }

    const QString docker = dockerExecutable();
    QList<CommandStep> steps;
    steps.append({docker, {QStringLiteral("pull"), image}, QStringLiteral("Pulling image"), false});
    steps.append({docker, createArgs, QStringLiteral("Creating container"), false});
    return startSteps(QStringLiteral("Create Container"), steps);
}

bool DockerManager::updateContainer(const QString &containerId,
                                    const QVariantMap &configuration)
{
    if (!m_daemonActive) {
        m_lastMessage = QStringLiteral("Start the Docker engine before editing containers.");
        emit operationChanged();
        return false;
    }
    const QVariantMap container = findContainer(containerId);
    if (container.isEmpty() || m_busy)
        return false;
    const QString docker = dockerExecutable();
    const QString id = container.value(QStringLiteral("id")).toString();
    QList<CommandStep> steps;

    const QString newName = sanitizedName(variantString(configuration, QStringLiteral("name")));
    if (!newName.isEmpty() && newName != container.value(QStringLiteral("name")).toString())
        steps.append({docker, {QStringLiteral("rename"), id, newName}, QStringLiteral("Renaming container"), false});

    const QString requestedRestart =
        variantString(configuration, QStringLiteral("restartPolicy")).toLower();
    const QStringList allowedRestart = {
        QStringLiteral("no"), QStringLiteral("always"),
        QStringLiteral("unless-stopped"), QStringLiteral("on-failure")
    };
    const QString restartPolicy = allowedRestart.contains(requestedRestart)
        ? requestedRestart
        : QStringLiteral("no");

    QStringList updateArgs{QStringLiteral("update"),
                           QStringLiteral("--restart"), restartPolicy};

    bool cpuOk = false;
    const double cpus = configuration.value(QStringLiteral("cpus")).toDouble(&cpuOk);
    if (cpuOk && cpus >= 0.1 && cpus <= 64.0)
        updateArgs << QStringLiteral("--cpus") << QString::number(cpus, 'f', 2);

    const QString memory = variantString(configuration, QStringLiteral("memory"));
    static const QRegularExpression memoryPattern(QStringLiteral("^[0-9]+(?:[kKmMgG])?$"));
    if (!memory.isEmpty() && memoryPattern.match(memory).hasMatch())
        updateArgs << QStringLiteral("--memory") << memory.toLower();

    if (updateArgs.size() > 1) {
        updateArgs << id;
        steps.append({docker, updateArgs, QStringLiteral("Updating limits and restart policy"), false});
    }

    if (steps.isEmpty()) {
        m_lastMessage = QStringLiteral("No editable settings changed.");
        emit operationChanged();
        return false;
    }
    return startSteps(QStringLiteral("Edit Container"), steps);
}

bool DockerManager::removeContainer(const QString &containerId,
                                    const QString &confirmation)
{
    if (!m_daemonActive) {
        m_lastMessage = QStringLiteral("Start the Docker engine before removing containers.");
        emit operationChanged();
        return false;
    }
    const QVariantMap container = findContainer(containerId);
    if (container.isEmpty() || m_busy)
        return false;
    const QString name = container.value(QStringLiteral("name")).toString();
    if (confirmation.trimmed() != QStringLiteral("REMOVE ") + name) {
        m_lastMessage = QStringLiteral("Removal confirmation did not match.");
        emit operationChanged();
        return false;
    }
    const QString id = container.value(QStringLiteral("id")).toString();
    return startSteps(
        QStringLiteral("Remove Container"),
        {{dockerExecutable(), {QStringLiteral("rm"), QStringLiteral("-f"), id},
          QStringLiteral("Removing container"), false}}
    );
}

bool DockerManager::cancelOperation()
{
    if (!m_busy)
        return false;
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->terminate();
        if (!m_process->waitForFinished(1200))
            m_process->kill();
    }
    if (m_busy)
        finishOperation(false, QStringLiteral("Docker operation cancelled."));
    return true;
}


void DockerManager::onProcessError(QProcess::ProcessError error)
{
    Q_UNUSED(error)
    if (!m_busy)
        return;
    finishOperation(false, m_process ? m_process->errorString()
                                     : QStringLiteral("Docker process failed."));
}
