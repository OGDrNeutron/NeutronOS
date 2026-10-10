#include "TerminalAssistManager.h"

#include <QTimer>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QVector>

#include <algorithm>
#include <utility>

namespace
{
constexpr int MaximumSnippets = 256;
constexpr int MaximumSnippetLabel = 64;
constexpr int MaximumSnippetCategory = 40;
constexpr int MaximumSnippetCommand = 12000;
constexpr int MaximumDictionaryEntries = 12000;
constexpr int MaximumRecentTokens = 64;

QString cleanSingleLine(const QString &value, int maximumLength)
{
    QString clean = value;
    clean.replace(QRegularExpression(QStringLiteral("[\\r\\n\\t]+")), QStringLiteral(" "));
    clean = clean.simplified().left(maximumLength);
    return clean;
}

QString defaultCategory(const QString &value)
{
    const QString clean = cleanSingleLine(value, MaximumSnippetCategory);
    return clean.isEmpty() ? QStringLiteral("Custom") : clean;
}

void addAliasesFromFile(const QString &path, QSet<QString> *dictionary)
{
    if (!dictionary)
        return;

    QFile file(path);

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    static const QRegularExpression aliasPattern(
        QStringLiteral("^\\s*alias\\s+([A-Za-z0-9_.+-]{2,64})\\s*=")
    );

    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine());
        const QRegularExpressionMatch match = aliasPattern.match(line);

        if (match.hasMatch())
            dictionary->insert(match.captured(1).toLower());
    }
}

QJsonObject snippetObject(
    const QString &id,
    const QString &label,
    const QString &category,
    const QString &command,
    int order)
{
    QJsonObject object;
    object.insert(QStringLiteral("id"), id);
    object.insert(QStringLiteral("label"), label);
    object.insert(QStringLiteral("category"), category);
    object.insert(QStringLiteral("command"), command);
    object.insert(QStringLiteral("order"), order);
    return object;
}
}

TerminalAssistManager::TerminalAssistManager(QObject *parent)
    : QObject(parent)
{
    m_stateDir = QStringLiteral(NEUTRONOS_STATE_DIR) + QStringLiteral("/terminal");
    m_snippetsPath = QDir(m_stateDir).filePath(QStringLiteral("snippets.json"));
    m_settingsPath = QDir(m_stateDir).filePath(QStringLiteral("assist-settings.json"));

    ensureStateDirectory();
    loadSettings();
    loadSnippets();

    // Scanning every PATH directory is useful only for Terminal suggestions
    // and previously delayed the shell's first QML load.
    QTimer::singleShot(3200, this, [this]() {
        refreshCommandDictionary();
    });
}

QVariantList TerminalAssistManager::snippets() const
{
    QVariantList result;
    result.reserve(m_snippets.size());

    for (const SnippetRecord &record : m_snippets)
        result.append(snippetToVariant(record));

    return result;
}

QVariantMap TerminalAssistManager::correctionSuggestion() const
{
    return m_correctionSuggestion;
}

bool TerminalAssistManager::smartCorrectionEnabled() const
{
    return m_smartCorrectionEnabled;
}

void TerminalAssistManager::setSmartCorrectionEnabled(bool enabled)
{
    if (m_smartCorrectionEnabled == enabled)
        return;

    m_smartCorrectionEnabled = enabled;
    saveSettings();

    if (!enabled)
        setCorrectionSuggestion(QVariantMap());

    emit smartCorrectionEnabledChanged();
}

QVariantMap TerminalAssistManager::snippet(const QString &id) const
{
    const int index = indexOfSnippet(id);
    return index >= 0 ? snippetToVariant(m_snippets.at(index)) : QVariantMap();
}

QVariantMap TerminalAssistManager::addSnippet(
    const QString &label,
    const QString &command,
    const QString &category)
{
    if (m_snippets.size() >= MaximumSnippets)
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"), QStringLiteral("Snippet limit reached")}};

    const QString cleanLabel = cleanSingleLine(label, MaximumSnippetLabel);
    const QString cleanCommand = command.left(MaximumSnippetCommand).trimmed();

    if (cleanLabel.isEmpty() || cleanCommand.isEmpty())
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"), QStringLiteral("Label and command are required")}};

    SnippetRecord record;
    record.id = createSnippetId(cleanLabel);
    record.label = cleanLabel;
    record.category = defaultCategory(category);
    record.command = cleanCommand;
    record.order = m_snippets.size();

    m_snippets.append(record);
    normalizeOrder();

    if (!saveSnippets()) {
        m_snippets.removeLast();
        normalizeOrder();
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"), QStringLiteral("Unable to save snippets")}};
    }

    emit snippetsChanged();

    QVariantMap result = snippetToVariant(record);
    result.insert(QStringLiteral("ok"), true);
    return result;
}

QVariantMap TerminalAssistManager::updateSnippet(
    const QString &id,
    const QString &label,
    const QString &command,
    const QString &category)
{
    const int index = indexOfSnippet(id);

    if (index < 0)
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"), QStringLiteral("Snippet not found")}};

    const QString cleanLabel = cleanSingleLine(label, MaximumSnippetLabel);
    const QString cleanCommand = command.left(MaximumSnippetCommand).trimmed();

    if (cleanLabel.isEmpty() || cleanCommand.isEmpty())
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"), QStringLiteral("Label and command are required")}};

    const SnippetRecord previous = m_snippets.at(index);
    SnippetRecord &record = m_snippets[index];
    record.label = cleanLabel;
    record.category = defaultCategory(category);
    record.command = cleanCommand;

    if (!saveSnippets()) {
        m_snippets[index] = previous;
        return {{QStringLiteral("ok"), false},
                {QStringLiteral("error"), QStringLiteral("Unable to save snippets")}};
    }

    emit snippetsChanged();

    QVariantMap result = snippetToVariant(record);
    result.insert(QStringLiteral("ok"), true);
    return result;
}

bool TerminalAssistManager::removeSnippet(const QString &id)
{
    const int index = indexOfSnippet(id);

    if (index < 0)
        return false;

    const SnippetRecord removed = m_snippets.takeAt(index);
    normalizeOrder();

    if (!saveSnippets()) {
        m_snippets.insert(index, removed);
        normalizeOrder();
        return false;
    }

    emit snippetsChanged();
    return true;
}

bool TerminalAssistManager::moveSnippet(const QString &id, int offset)
{
    const int index = indexOfSnippet(id);

    if (index < 0 || offset == 0)
        return false;

    const int target = qBound(0, index + offset, m_snippets.size() - 1);

    if (target == index)
        return false;

    m_snippets.move(index, target);
    normalizeOrder();

    if (!saveSnippets()) {
        m_snippets.move(target, index);
        normalizeOrder();
        return false;
    }

    emit snippetsChanged();
    return true;
}

QString TerminalAssistManager::snippetText(const QString &id) const
{
    const int index = indexOfSnippet(id);
    return index >= 0 ? m_snippets.at(index).command : QString();
}

void TerminalAssistManager::observeDraft(const QString &draft)
{
    if (!m_smartCorrectionEnabled) {
        setCorrectionSuggestion(QVariantMap());
        return;
    }

    setCorrectionSuggestion(buildCorrectionSuggestion(draft));
}

void TerminalAssistManager::recordCommand(const QString &command)
{
    const QString token = commandToken(command).toLower();

    if (token.isEmpty())
        return;

    m_recentCommandTokens.removeAll(token);
    m_recentCommandTokens.prepend(token);

    while (m_recentCommandTokens.size() > MaximumRecentTokens)
        m_recentCommandTokens.removeLast();

    m_commandDictionary.insert(token);
}

QString TerminalAssistManager::acceptSuggestionText()
{
    const QString corrected = m_correctionSuggestion.value(QStringLiteral("corrected")).toString();
    setCorrectionSuggestion(QVariantMap());
    return corrected;
}

void TerminalAssistManager::dismissSuggestion()
{
    setCorrectionSuggestion(QVariantMap());
}

void TerminalAssistManager::refreshCommandDictionary()
{
    QSet<QString> dictionary;

    const QStringList builtins = {
        QStringLiteral("alias"), QStringLiteral("bg"), QStringLiteral("bind"),
        QStringLiteral("break"), QStringLiteral("builtin"), QStringLiteral("cd"),
        QStringLiteral("command"), QStringLiteral("continue"), QStringLiteral("declare"),
        QStringLiteral("dirs"), QStringLiteral("disown"), QStringLiteral("neutronos"),
        QStringLiteral("enable"), QStringLiteral("eval"), QStringLiteral("exec"),
        QStringLiteral("exit"), QStringLiteral("export"), QStringLiteral("false"),
        QStringLiteral("fg"), QStringLiteral("getopts"), QStringLiteral("hash"),
        QStringLiteral("help"), QStringLiteral("history"), QStringLiteral("jobs"),
        QStringLiteral("kill"), QStringLiteral("let"), QStringLiteral("local"),
        QStringLiteral("logout"), QStringLiteral("mapfile"), QStringLiteral("popd"),
        QStringLiteral("printf"), QStringLiteral("pushd"), QStringLiteral("pwd"),
        QStringLiteral("read"), QStringLiteral("readarray"), QStringLiteral("readonly"),
        QStringLiteral("return"), QStringLiteral("set"), QStringLiteral("shift"),
        QStringLiteral("shopt"), QStringLiteral("source"), QStringLiteral("suspend"),
        QStringLiteral("test"), QStringLiteral("times"), QStringLiteral("trap"),
        QStringLiteral("true"), QStringLiteral("type"), QStringLiteral("typeset"),
        QStringLiteral("ulimit"), QStringLiteral("umask"), QStringLiteral("unalias"),
        QStringLiteral("unset"), QStringLiteral("wait"), QStringLiteral("systemctl"),
        QStringLiteral("journalctl"), QStringLiteral("docker"), QStringLiteral("podman"),
        QStringLiteral("git"), QStringLiteral("cmake"), QStringLiteral("ninja"),
        QStringLiteral("make"), QStringLiteral("python3"), QStringLiteral("pip3"),
        QStringLiteral("ls"), QStringLiteral("cp"), QStringLiteral("mv"),
        QStringLiteral("rm"), QStringLiteral("mkdir"), QStringLiteral("rmdir"),
        QStringLiteral("cat"), QStringLiteral("less"), QStringLiteral("grep"),
        QStringLiteral("sed"), QStringLiteral("awk"), QStringLiteral("find"),
        QStringLiteral("chmod"), QStringLiteral("chown"), QStringLiteral("sudo"),
        QStringLiteral("ssh"), QStringLiteral("scp"), QStringLiteral("rsync"),
        QStringLiteral("curl"), QStringLiteral("wget"), QStringLiteral("tar"),
        QStringLiteral("unzip"), QStringLiteral("zip"), QStringLiteral("df"),
        QStringLiteral("du"), QStringLiteral("free"), QStringLiteral("top"),
        QStringLiteral("htop"), QStringLiteral("ps"), QStringLiteral("pkill"),
        QStringLiteral("killall"), QStringLiteral("ip"), QStringLiteral("ping"),
        QStringLiteral("ss"), QStringLiteral("nmcli"), QStringLiteral("bluetoothctl"),
        QStringLiteral("mount"), QStringLiteral("umount"), QStringLiteral("lsblk"),
        QStringLiteral("smartctl"), QStringLiteral("reboot"), QStringLiteral("shutdown")
    };

    for (const QString &item : builtins)
        dictionary.insert(item);

    /*
        Read alias names without invoking an interactive shell. This keeps the
        dictionary lightweight and avoids executing user-controlled startup
        files. Only the alias identifier before '=' is parsed.
    */
    QStringList aliasFiles = {
        QStringLiteral("/etc/bash.bashrc"),
        QStringLiteral("/root/.bashrc"),
        QStringLiteral("/root/.bash_aliases"),
        QStringLiteral("/home/echo/.bashrc"),
        QStringLiteral("/home/echo/.bash_aliases")
    };

    const QString loginUser = QString::fromLocal8Bit(qgetenv("SUDO_USER")).trimmed();
    if (!loginUser.isEmpty() && loginUser != QStringLiteral("root")) {
        aliasFiles.append(QStringLiteral("/home/%1/.bashrc").arg(loginUser));
        aliasFiles.append(QStringLiteral("/home/%1/.bash_aliases").arg(loginUser));
    }

    aliasFiles.removeDuplicates();
    for (const QString &aliasFile : std::as_const(aliasFiles))
        addAliasesFromFile(aliasFile, &dictionary);

    const QString pathValue = QString::fromLocal8Bit(qgetenv("PATH"));
    const QStringList pathEntries = pathValue.split(QLatin1Char(':'), Qt::SkipEmptyParts);

    for (const QString &directoryPath : pathEntries) {
        QDir directory(directoryPath);

        if (!directory.exists())
            continue;

        const QFileInfoList entries = directory.entryInfoList(
            QDir::Files | QDir::Executable | QDir::NoDotAndDotDot,
            QDir::Name);

        for (const QFileInfo &entry : entries) {
            dictionary.insert(entry.fileName().toLower());

            if (dictionary.size() >= MaximumDictionaryEntries)
                break;
        }

        if (dictionary.size() >= MaximumDictionaryEntries)
            break;
    }

    for (const QString &recent : std::as_const(m_recentCommandTokens))
        dictionary.insert(recent.toLower());

    m_commandDictionary = dictionary;
}

bool TerminalAssistManager::ensureStateDirectory() const
{
    const QFileInfo existing(m_stateDir);

    if (existing.exists() && existing.isSymLink())
        return false;

    if (!QDir().mkpath(m_stateDir))
        return false;

    QFile::setPermissions(
        m_stateDir,
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner |
        QFileDevice::ExeOwner);

    return true;
}

void TerminalAssistManager::loadSettings()
{
    QFile file(m_settingsPath);

    if (!file.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());

    if (!document.isObject())
        return;

    m_smartCorrectionEnabled = document.object().value(QStringLiteral("smartCorrectionEnabled")).toBool(true);
}

void TerminalAssistManager::saveSettings() const
{
    if (!ensureStateDirectory())
        return;

    QJsonObject object;
    object.insert(QStringLiteral("version"), 1);
    object.insert(QStringLiteral("smartCorrectionEnabled"), m_smartCorrectionEnabled);

    QSaveFile file(m_settingsPath);

    if (!file.open(QIODevice::WriteOnly))
        return;

    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));

    if (file.commit()) {
        QFile::setPermissions(
            m_settingsPath,
            QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    }
}

void TerminalAssistManager::loadSnippets()
{
    m_snippets.clear();

    QFile file(m_snippetsPath);

    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll());

        if (document.isArray()) {
            const QJsonArray array = document.array();

            for (const QJsonValue &value : array) {
                if (!value.isObject() || m_snippets.size() >= MaximumSnippets)
                    continue;

                const QJsonObject object = value.toObject();
                SnippetRecord record;
                record.id = cleanSingleLine(object.value(QStringLiteral("id")).toString(), 80);
                record.label = cleanSingleLine(object.value(QStringLiteral("label")).toString(), MaximumSnippetLabel);
                record.category = defaultCategory(object.value(QStringLiteral("category")).toString());
                record.command = object.value(QStringLiteral("command")).toString().left(MaximumSnippetCommand).trimmed();
                record.order = object.value(QStringLiteral("order")).toInt(m_snippets.size());

                if (record.id.isEmpty() || record.label.isEmpty() || record.command.isEmpty())
                    continue;

                if (indexOfSnippet(record.id) >= 0)
                    continue;

                m_snippets.append(record);
            }
        }
    }

    if (m_snippets.isEmpty()) {
        seedDefaultSnippets();
        saveSnippets();
    }

    std::stable_sort(
        m_snippets.begin(),
        m_snippets.end(),
        [](const SnippetRecord &left, const SnippetRecord &right) {
            return left.order < right.order;
        });

    normalizeOrder();
}

bool TerminalAssistManager::saveSnippets() const
{
    if (!ensureStateDirectory())
        return false;

    QJsonArray array;

    for (const SnippetRecord &record : m_snippets) {
        array.append(snippetObject(
            record.id,
            record.label,
            record.category,
            record.command,
            record.order));
    }

    QSaveFile file(m_snippetsPath);

    if (!file.open(QIODevice::WriteOnly))
        return false;

    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));

    if (!file.commit())
        return false;

    QFile::setPermissions(
        m_snippetsPath,
        QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    return true;
}

void TerminalAssistManager::seedDefaultSnippets()
{
    const QList<SnippetRecord> defaults = {
        {QStringLiteral("system-status"), QStringLiteral("System Status"), QStringLiteral("System"), QStringLiteral("uptime && echo && free -h && echo && df -h"), 0},
        {QStringLiteral("shell-status"), QStringLiteral("NeutronOS Service Status"), QStringLiteral("NeutronOS"), QStringLiteral("systemctl --no-pager --full status neutronos.service"), 1},
        {QStringLiteral("shell-logs"), QStringLiteral("NeutronOS Recent Logs"), QStringLiteral("NeutronOS"), QStringLiteral("journalctl -u neutronos.service -n 120 --no-pager"), 2},
        {QStringLiteral("docker-list"), QStringLiteral("Docker Containers"), QStringLiteral("Docker"), QStringLiteral("docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'"), 3},
        {QStringLiteral("network-status"), QStringLiteral("Network Status"), QStringLiteral("Network"), QStringLiteral("ip -brief address && echo && ip route"), 4},
        {QStringLiteral("git-status"), QStringLiteral("Git Status"), QStringLiteral("Development"), QStringLiteral("git status --short --branch"), 5},
        {QStringLiteral("rebuild-shell"), QStringLiteral("Rebuild NeutronOS"), QStringLiteral("NeutronOS"), QStringLiteral("cd ~/NeutronOS && cmake -S . -B build && cmake --build build -j$(nproc)"), 6},
        {QStringLiteral("find-large-files"), QStringLiteral("Largest Files"), QStringLiteral("Files"), QStringLiteral("find . -type f -printf '%s %p\\n' 2>/dev/null | sort -nr | head -40"), 7}
    };

    m_snippets = defaults;
}

void TerminalAssistManager::normalizeOrder()
{
    for (int index = 0; index < m_snippets.size(); ++index)
        m_snippets[index].order = index;
}

QVariantMap TerminalAssistManager::snippetToVariant(const SnippetRecord &record) const
{
    return {
        {QStringLiteral("id"), record.id},
        {QStringLiteral("label"), record.label},
        {QStringLiteral("category"), record.category},
        {QStringLiteral("command"), record.command},
        {QStringLiteral("order"), record.order}
    };
}

int TerminalAssistManager::indexOfSnippet(const QString &id) const
{
    const QString clean = id.trimmed();

    for (int index = 0; index < m_snippets.size(); ++index) {
        if (m_snippets.at(index).id == clean)
            return index;
    }

    return -1;
}

QString TerminalAssistManager::createSnippetId(const QString &label) const
{
    QString base = label.toLower();
    base.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    base.remove(QRegularExpression(QStringLiteral("^-+|-+$")));

    if (base.isEmpty())
        base = QStringLiteral("snippet");

    base = base.left(44);
    QString candidate = base;
    int suffix = 2;

    while (indexOfSnippet(candidate) >= 0) {
        candidate = QStringLiteral("%1-%2").arg(base).arg(suffix++);
    }

    return candidate;
}

QVariantMap TerminalAssistManager::buildCorrectionSuggestion(const QString &draft) const
{
    if (!correctionEligible(draft))
        return QVariantMap();

    const QString token = commandToken(draft);
    const QString lowerToken = token.toLower();

    if (lowerToken.isEmpty() || m_commandDictionary.contains(lowerToken))
        return QVariantMap();

    int bestDistance = 99;
    QString best;
    int equallyGoodCandidates = 0;

    for (const QString &candidate : m_commandDictionary) {
        if (candidate.isEmpty())
            continue;

        const int lengthDifference = qAbs(candidate.size() - lowerToken.size());

        if (lengthDifference > 2)
            continue;

        const int distance = editDistance(lowerToken, candidate);
        const int allowed = lowerToken.size() <= 4 ? 1 : 2;

        if (distance > allowed)
            continue;

        if (distance < bestDistance) {
            bestDistance = distance;
            best = candidate;
            equallyGoodCandidates = 1;
        } else if (distance == bestDistance) {
            ++equallyGoodCandidates;
            if (best.isEmpty() || candidate.size() < best.size() ||
                    (candidate.size() == best.size() && candidate < best)) {
                best = candidate;
            }
        }
    }

    if (best.isEmpty())
        return QVariantMap();

    const QString corrected = replaceCommandToken(draft, best);
    const bool dangerous = dangerousCommandToken(best);
    const bool ambiguous = equallyGoodCandidates > 1;

    return {
        {QStringLiteral("visible"), true},
        {QStringLiteral("original"), draft},
        {QStringLiteral("originalToken"), token},
        {QStringLiteral("replacementToken"), best},
        {QStringLiteral("corrected"), corrected},
        {QStringLiteral("distance"), bestDistance},
        {QStringLiteral("dangerous"), dangerous},
        {QStringLiteral("ambiguous"), ambiguous},
        {QStringLiteral("requiresConfirmation"), dangerous || ambiguous},
        {QStringLiteral("message"), QStringLiteral("Did you mean %1?").arg(best)}
    };
}

void TerminalAssistManager::setCorrectionSuggestion(const QVariantMap &suggestion)
{
    if (m_correctionSuggestion == suggestion)
        return;

    m_correctionSuggestion = suggestion;
    emit correctionSuggestionChanged();
}

bool TerminalAssistManager::correctionEligible(const QString &draft)
{
    const QString clean = draft.trimmed();

    if (clean.isEmpty() || clean.size() > 256 || clean.contains(QLatin1Char('\n')) || clean.contains(QLatin1Char('\r')))
        return false;

    static const QRegularExpression unsafe(
        QStringLiteral("[\\\"'`/\\\\|&;<>$(){}\\[\\]*?~]")
    );

    if (unsafe.match(clean).hasMatch())
        return false;

    const QString token = commandToken(clean);
    static const QRegularExpression tokenPattern(QStringLiteral("^[A-Za-z0-9_.+-]{2,64}$"));
    return tokenPattern.match(token).hasMatch();
}

QString TerminalAssistManager::commandToken(const QString &draft)
{
    const QString clean = draft.trimmed();
    const int space = clean.indexOf(QRegularExpression(QStringLiteral("\\s")));
    return space < 0 ? clean : clean.left(space);
}

QString TerminalAssistManager::replaceCommandToken(
    const QString &draft,
    const QString &replacement)
{
    const int start = draft.indexOf(QRegularExpression(QStringLiteral("\\S")));

    if (start < 0)
        return replacement;

    int end = start;

    while (end < draft.size() && !draft.at(end).isSpace())
        ++end;

    return draft.left(start) + replacement + draft.mid(end);
}

int TerminalAssistManager::editDistance(const QString &left, const QString &right)
{
    QVector<int> previous(right.size() + 1);
    QVector<int> current(right.size() + 1);

    for (int column = 0; column <= right.size(); ++column)
        previous[column] = column;

    for (int row = 1; row <= left.size(); ++row) {
        current[0] = row;

        for (int column = 1; column <= right.size(); ++column) {
            const int cost = left.at(row - 1) == right.at(column - 1) ? 0 : 1;
            current[column] = std::min({
                previous[column] + 1,
                current[column - 1] + 1,
                previous[column - 1] + cost
            });
        }

        previous.swap(current);
    }

    return previous[right.size()];
}

bool TerminalAssistManager::dangerousCommandToken(const QString &token)
{
    static const QSet<QString> dangerous = {
        QStringLiteral("rm"), QStringLiteral("dd"), QStringLiteral("mkfs"),
        QStringLiteral("fdisk"), QStringLiteral("parted"), QStringLiteral("wipefs"),
        QStringLiteral("shutdown"), QStringLiteral("reboot"), QStringLiteral("poweroff"),
        QStringLiteral("kill"), QStringLiteral("killall"), QStringLiteral("pkill"),
        QStringLiteral("systemctl")
    };

    return dangerous.contains(token.toLower());
}
