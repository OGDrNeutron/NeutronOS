#include "TextEditorManager.h"
#include "DeveloperModeManager.h"

#include <algorithm>
#include <utility>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QList>
#include <QPair>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QVector>

namespace {
constexpr qint64 MaximumEditorBytes = 8 * 1024 * 1024;
constexpr int MaximumDiagnosticBytes = 1024 * 1024;
constexpr int MaximumSuggestions = 16;

QString hashName(const QString &value)
{
    return QString::fromLatin1(QCryptographicHash::hash(value.toUtf8(), QCryptographicHash::Sha256).toHex());
}

QString matchingCloser(QChar opener)
{
    if (opener == QLatin1Char('(')) return QStringLiteral(")");
    if (opener == QLatin1Char('[')) return QStringLiteral("]");
    if (opener == QLatin1Char('{')) return QStringLiteral("}");
    return QString();
}

bool isMatchingPair(QChar opener, QChar closer)
{
    return (opener == QLatin1Char('(') && closer == QLatin1Char(')'))
        || (opener == QLatin1Char('[') && closer == QLatin1Char(']'))
        || (opener == QLatin1Char('{') && closer == QLatin1Char('}'));
}

bool isVoidHtmlTag(const QString &tag)
{
    static const QSet<QString> tags = {
        QStringLiteral("area"), QStringLiteral("base"), QStringLiteral("br"),
        QStringLiteral("col"), QStringLiteral("embed"), QStringLiteral("hr"),
        QStringLiteral("img"), QStringLiteral("input"), QStringLiteral("link"),
        QStringLiteral("meta"), QStringLiteral("param"), QStringLiteral("source"),
        QStringLiteral("track"), QStringLiteral("wbr")
    };
    return tags.contains(tag.toLower());
}
}

TextEditorManager::TextEditorManager(const QString &neutronRoot,
                                     DeveloperModeManager *developerModeManager,
                                     QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_developerModeManager(developerModeManager)
{
}

bool TextEditorManager::busy() const { return m_busy; }
QString TextEditorManager::error() const { return m_error; }
QString TextEditorManager::currentPath() const { return m_currentPath; }
QString TextEditorManager::displayName() const { return m_displayName; }
bool TextEditorManager::untitled() const { return m_currentPath.isEmpty(); }
QString TextEditorManager::text() const { return m_text; }
QString TextEditorManager::encoding() const { return m_encoding; }
QString TextEditorManager::language() const { return m_language; }
bool TextEditorManager::dirty() const { return m_dirty; }
bool TextEditorManager::recoveryAvailable() const { return m_recoveryAvailable; }
QVariantList TextEditorManager::recentFiles() const { return m_recentFiles; }
QVariantList TextEditorManager::diagnostics() const { return m_diagnostics; }
QVariantList TextEditorManager::corrections() const { return m_corrections; }

void TextEditorManager::initialize()
{
    QDir().mkpath(defaultDocumentsPath());
    QDir().mkpath(QDir(m_neutronRoot).filePath(QStringLiteral("state/texteditor/recovery")));
    QDir().mkpath(QDir(m_neutronRoot).filePath(QStringLiteral("state/texteditor/backups")));
    loadRecentFiles();
}

void TextEditorManager::newUntitled()
{
    ++m_untitledCounter;
    m_currentPath.clear();
    m_displayName = QStringLiteral("Untitled %1").arg(m_untitledCounter);
    m_text.clear();
    m_encoding = QStringLiteral("UTF-8");
    m_language = QStringLiteral("Plain Text");
    m_recoveryAvailable = false;
    setDirty(false);
    setError(QString());
    clearDiagnostics();
    clearCorrections();
    emit recoveryChanged();
    emit documentChanged();
}

QString TextEditorManager::normalizedPath(const QString &path) const
{
    if (path.trimmed().isEmpty())
        return QString();
    QFileInfo info(path);
    const QString canonical = info.canonicalFilePath();
    return QDir::cleanPath(canonical.isEmpty() ? info.absoluteFilePath() : canonical);
}

QString TextEditorManager::userHomePath() const
{
    const QFileInfo rootInfo(m_neutronRoot);
    const QString parent = QDir::cleanPath(rootInfo.absoluteDir().absolutePath());
    if (!parent.isEmpty() && parent != QStringLiteral("/"))
        return parent;
    return QDir::cleanPath(QDir::homePath());
}

bool TextEditorManager::openFile(const QString &path)
{
    const QString normalized = normalizedPath(path);
    QFileInfo info(normalized);
    if (!info.exists() || !info.isFile()) {
        setError(QStringLiteral("The selected file does not exist."));
        emit operationFailed(m_error);
        return false;
    }
    if (!isSupported(normalized)) {
        setError(QStringLiteral("This file type is not enabled in Text Editor."));
        emit operationFailed(m_error);
        return false;
    }
    if (info.size() > MaximumEditorBytes) {
        setError(QStringLiteral("The file is larger than the 8 MB safe editing limit."));
        emit operationFailed(m_error);
        return false;
    }

    setBusy(true);
    QFile file(normalized);
    if (!file.open(QIODevice::ReadOnly)) {
        setBusy(false);
        setError(file.errorString());
        emit operationFailed(m_error);
        return false;
    }
    QByteArray bytes = file.readAll();
    const QString encoding = QStringLiteral("UTF-8");
    if (bytes.startsWith("\xEF\xBB\xBF"))
        bytes.remove(0, 3);
    const QString decoded = QString::fromUtf8(bytes);
    setDocument(normalized, decoded, encoding);
    addRecentFile(normalized);
    const QFileInfo recovery(recoveryPathFor(normalized));
    m_recoveryAvailable = recovery.exists() && recovery.lastModified() > info.lastModified();
    emit recoveryChanged();
    setBusy(false);
    emit opened(normalized);
    return true;
}

bool TextEditorManager::createDocument(const QString &path, const QString &initialText)
{
    const QString normalized = normalizedPath(path);
    if (normalized.isEmpty()) {
        setError(QStringLiteral("A file path is required."));
        emit operationFailed(m_error);
        return false;
    }
    setDocument(normalized, initialText, QStringLiteral("UTF-8"));
    setDirty(true);
    m_recoveryAvailable = false;
    emit recoveryChanged();
    return true;
}

void TextEditorManager::updateText(const QString &text)
{
    if (m_text == text)
        return;
    m_text = text;
    setDirty(true);
    clearDiagnostics();
    clearCorrections();
}

bool TextEditorManager::save()
{
    return saveToPath(m_currentPath);
}

bool TextEditorManager::saveAs(const QString &path)
{
    return saveToPath(normalizedPath(path));
}

bool TextEditorManager::saveToPath(const QString &path)
{
    const QString normalized = normalizedPath(path);
    if (normalized.isEmpty()) {
        setError(QStringLiteral("Choose a filename with Save As."));
        emit operationFailed(m_error);
        return false;
    }
    if (!isSupported(normalized)) {
        setError(QStringLiteral("The file extension is not supported by Text Editor."));
        emit operationFailed(m_error);
        return false;
    }
    if (!canWritePath(normalized)) {
        setError(requiresDeveloperMode(normalized)
            ? QStringLiteral("Developer Mode is required to modify this system path.")
            : QStringLiteral("The selected location is not writable."));
        emit operationFailed(m_error);
        return false;
    }

    setBusy(true);
    QDir().mkpath(QFileInfo(normalized).dir().absolutePath());

    if (QFileInfo::exists(normalized)) {
        QFile previous(normalized);
        if (previous.open(QIODevice::ReadOnly)) {
            QSaveFile backup(backupPathFor(normalized));
            if (backup.open(QIODevice::WriteOnly)) {
                backup.write(previous.readAll());
                backup.commit();
            }
        }
    }

    QSaveFile output(normalized);
    if (!output.open(QIODevice::WriteOnly | QIODevice::Text)) {
        setBusy(false);
        setError(output.errorString());
        emit operationFailed(m_error);
        return false;
    }
    const QByteArray bytes = m_text.toUtf8();
    if (output.write(bytes) != bytes.size() || !output.commit()) {
        setBusy(false);
        setError(output.errorString());
        emit operationFailed(m_error);
        return false;
    }

    m_currentPath = normalized;
    m_displayName = QFileInfo(normalized).fileName();
    m_language = languageForPath(normalized);
    setDirty(false);
    discardRecovery(normalized);
    addRecentFile(normalized);
    setBusy(false);
    emit documentChanged();
    emit saved(normalized);
    return true;
}

bool TextEditorManager::writeRecovery(const QString &path, const QString &text)
{
    const QString normalized = normalizedPath(path);
    if (normalized.isEmpty())
        return false;
    QJsonObject object;
    object.insert(QStringLiteral("schema"), 1);
    object.insert(QStringLiteral("path"), normalized);
    object.insert(QStringLiteral("savedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    object.insert(QStringLiteral("text"), text);
    QSaveFile output(recoveryPathFor(normalized));
    if (!output.open(QIODevice::WriteOnly))
        return false;
    output.write(QJsonDocument(object).toJson(QJsonDocument::Compact));
    const bool ok = output.commit();
    if (ok && normalized == m_currentPath && !m_recoveryAvailable) {
        m_recoveryAvailable = true;
        emit recoveryChanged();
    }
    return ok;
}

QVariantMap TextEditorManager::recoveryInfo(const QString &path) const
{
    const QString normalized = normalizedPath(path);
    if (normalized.isEmpty())
        return {};
    QFile file(recoveryPathFor(normalized));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
    QVariantMap result = object.toVariantMap();
    result.insert(QStringLiteral("exists"), true);
    return result;
}

bool TextEditorManager::restoreRecovery(const QString &path)
{
    const QVariantMap recovery = recoveryInfo(path);
    if (!recovery.value(QStringLiteral("exists")).toBool())
        return false;
    setDocument(normalizedPath(path), recovery.value(QStringLiteral("text")).toString(), QStringLiteral("UTF-8"));
    setDirty(true);
    m_recoveryAvailable = true;
    emit recoveryChanged();
    return true;
}

bool TextEditorManager::discardRecovery(const QString &path)
{
    const QString normalized = normalizedPath(path);
    if (normalized.isEmpty())
        return true;
    const QString recovery = recoveryPathFor(normalized);
    const bool ok = !QFileInfo::exists(recovery) || QFile::remove(recovery);
    if (normalized == m_currentPath) {
        m_recoveryAvailable = false;
        emit recoveryChanged();
    }
    return ok;
}

bool TextEditorManager::requiresDeveloperMode(const QString &path) const
{
    const QString normalized = normalizedPath(path);
    const QString home = userHomePath() + QLatin1Char('/');
    const QString project = QDir::cleanPath(m_neutronRoot) + QLatin1Char('/');
    if (normalized == userHomePath() || normalized.startsWith(home))
        return false;
    if (normalized == QDir::cleanPath(m_neutronRoot) || normalized.startsWith(project))
        return false;
    static const QStringList protectedRoots = {
        QStringLiteral("/boot"), QStringLiteral("/etc"), QStringLiteral("/opt"),
        QStringLiteral("/root"), QStringLiteral("/usr"), QStringLiteral("/var")
    };
    for (const QString &root : protectedRoots) {
        if (normalized == root || normalized.startsWith(root + QLatin1Char('/')))
            return true;
    }
    return true;
}

bool TextEditorManager::canWritePath(const QString &path) const
{
    const QString normalized = normalizedPath(path);
    if (normalized.isEmpty())
        return false;
    if (requiresDeveloperMode(normalized)
        && (!m_developerModeManager || !m_developerModeManager->developerModeEnabled()))
        return false;
    const QFileInfo info(normalized);
    if (info.exists())
        return info.isFile() && info.isWritable();

    QDir parent = info.dir();
    while (!parent.exists() && parent.cdUp()) {
    }
    return QFileInfo(parent.absolutePath()).isWritable();
}

bool TextEditorManager::isSupported(const QString &path) const
{
    const QString suffix = QFileInfo(path).suffix().toLower();
    return supportedExtensions().contains(suffix);
}

QString TextEditorManager::languageForPath(const QString &path) const
{
    const QString suffix = QFileInfo(path).suffix().toLower();
    if (suffix == QStringLiteral("md") || suffix == QStringLiteral("markdown")) return QStringLiteral("Markdown");
    if (suffix == QStringLiteral("json")) return QStringLiteral("JSON");
    if (suffix == QStringLiteral("py")) return QStringLiteral("Python");
    if (suffix == QStringLiteral("cpp") || suffix == QStringLiteral("cc") || suffix == QStringLiteral("cxx") || suffix == QStringLiteral("c") || suffix == QStringLiteral("h") || suffix == QStringLiteral("hpp")) return QStringLiteral("C/C++");
    if (suffix == QStringLiteral("qml")) return QStringLiteral("QML");
    if (suffix == QStringLiteral("js")) return QStringLiteral("JavaScript");
    if (suffix == QStringLiteral("html") || suffix == QStringLiteral("htm")) return QStringLiteral("HTML");
    if (suffix == QStringLiteral("css")) return QStringLiteral("CSS");
    if (suffix == QStringLiteral("xml")) return QStringLiteral("XML");
    if (suffix == QStringLiteral("sh") || suffix == QStringLiteral("bash")) return QStringLiteral("Shell");
    if (suffix == QStringLiteral("ini") || suffix == QStringLiteral("conf") || suffix == QStringLiteral("cfg") || suffix == QStringLiteral("service") || suffix == QStringLiteral("desktop") || suffix == QStringLiteral("toml") || suffix == QStringLiteral("yaml") || suffix == QStringLiteral("yml")) return QStringLiteral("Configuration");
    return QStringLiteral("Plain Text");
}

QStringList TextEditorManager::supportedExtensions() const
{
    return {QStringLiteral("txt"), QStringLiteral("md"), QStringLiteral("markdown"),
            QStringLiteral("json"), QStringLiteral("py"), QStringLiteral("cpp"),
            QStringLiteral("cc"), QStringLiteral("cxx"), QStringLiteral("c"),
            QStringLiteral("h"), QStringLiteral("hpp"), QStringLiteral("qml"),
            QStringLiteral("js"), QStringLiteral("html"), QStringLiteral("htm"),
            QStringLiteral("css"), QStringLiteral("xml"), QStringLiteral("sh"),
            QStringLiteral("bash"), QStringLiteral("ini"), QStringLiteral("conf"),
            QStringLiteral("cfg"), QStringLiteral("service"), QStringLiteral("desktop"),
            QStringLiteral("toml"), QStringLiteral("yaml"), QStringLiteral("yml")};
}

QString TextEditorManager::defaultDocumentsPath() const
{
    return QDir(userHomePath()).filePath(QStringLiteral("Documents"));
}

QVariantMap TextEditorManager::fileInfo(const QString &path) const
{
    const QFileInfo info(normalizedPath(path));
    QVariantMap result;
    result.insert(QStringLiteral("path"), info.absoluteFilePath());
    result.insert(QStringLiteral("name"), info.fileName());
    result.insert(QStringLiteral("exists"), info.exists());
    result.insert(QStringLiteral("bytes"), static_cast<qulonglong>(info.size()));
    result.insert(QStringLiteral("modified"), info.lastModified().toString(Qt::ISODateWithMs));
    result.insert(QStringLiteral("language"), languageForPath(info.absoluteFilePath()));
    result.insert(QStringLiteral("requiresDeveloperMode"), requiresDeveloperMode(info.absoluteFilePath()));
    result.insert(QStringLiteral("writable"), canWritePath(info.absoluteFilePath()));
    return result;
}

QVariantMap TextEditorManager::makeDiagnostic(const QString &severity,
                                               const QString &message,
                                               const QString &text,
                                               int offset,
                                               int length) const
{
    const int textLength = static_cast<int>(text.size());
    const int safeOffset = std::clamp(offset, 0, textLength);
    const QString prefix = text.left(safeOffset);
    const int line = prefix.count(QLatin1Char('\n')) + 1;
    const int lastNewline = prefix.lastIndexOf(QLatin1Char('\n'));
    const int column = safeOffset - lastNewline;
    QVariantMap result;
    result.insert(QStringLiteral("severity"), severity);
    result.insert(QStringLiteral("message"), message);
    result.insert(QStringLiteral("line"), line);
    result.insert(QStringLiteral("column"), column);
    result.insert(QStringLiteral("start"), safeOffset);
    result.insert(QStringLiteral("length"), std::max(1, length));
    return result;
}

QVariantMap TextEditorManager::makeCorrection(const QString &title,
                                               const QString &detail,
                                               const QString &text,
                                               int start,
                                               int length,
                                               const QString &replacement,
                                               const QString &kind) const
{
    const int textLength = static_cast<int>(text.size());
    const int safeStart = std::clamp(start, 0, textLength);
    const int safeLength = std::clamp(length, 0, textLength - safeStart);
    const int contextStart = std::max(0, safeStart - 28);
    const int contextEnd = std::min(textLength, safeStart + safeLength + 32);
    QString before = text.mid(contextStart, safeStart - contextStart);
    QString old = text.mid(safeStart, safeLength);
    QString after = text.mid(safeStart + safeLength, contextEnd - safeStart - safeLength);
    before.replace(QLatin1Char('\n'), QLatin1Char(' '));
    old.replace(QLatin1Char('\n'), QStringLiteral("↵"));
    after.replace(QLatin1Char('\n'), QLatin1Char(' '));

    QVariantMap result = makeDiagnostic(QStringLiteral("suggestion"), detail, text, safeStart, std::max(1, safeLength));
    result.insert(QStringLiteral("title"), title);
    result.insert(QStringLiteral("replacement"), replacement);
    result.insert(QStringLiteral("kind"), kind);
    result.insert(QStringLiteral("preview"), QStringLiteral("%1[%2 → %3]%4").arg(before).arg(old).arg(replacement).arg(after));
    return result;
}

void TextEditorManager::addBracketDiagnostics(const QString &text,
                                               const QString &language,
                                               QVariantList &result) const
{
    struct Entry { QChar character; int position; };
    QVector<Entry> stack;
    const QString lower = language.toLower();
    const bool hashComments = lower.contains(QStringLiteral("python"))
        || lower.contains(QStringLiteral("shell"))
        || lower.contains(QStringLiteral("configuration"));
    bool lineComment = false;
    bool blockComment = false;
    QChar quote;
    bool escaped = false;

    for (int i = 0; i < static_cast<int>(text.size()); ++i) {
        const QChar ch = text.at(i);
        const QChar next = i + 1 < static_cast<int>(text.size()) ? text.at(i + 1) : QChar();
        if (lineComment) {
            if (ch == QLatin1Char('\n')) lineComment = false;
            continue;
        }
        if (blockComment) {
            if (ch == QLatin1Char('*') && next == QLatin1Char('/')) {
                blockComment = false;
                ++i;
            }
            continue;
        }
        if (!quote.isNull()) {
            if (escaped) {
                escaped = false;
            } else if (ch == QLatin1Char('\\')) {
                escaped = true;
            } else if (ch == quote) {
                quote = QChar();
            }
            continue;
        }
        if (hashComments && ch == QLatin1Char('#')) {
            lineComment = true;
            continue;
        }
        if (!hashComments && ch == QLatin1Char('/') && next == QLatin1Char('/')) {
            lineComment = true;
            ++i;
            continue;
        }
        if (!hashComments && ch == QLatin1Char('/') && next == QLatin1Char('*')) {
            blockComment = true;
            ++i;
            continue;
        }
        if (ch == QLatin1Char('\'') || ch == QLatin1Char('"') || ch == QLatin1Char('`')) {
            quote = ch;
            continue;
        }
        if (ch == QLatin1Char('(') || ch == QLatin1Char('[') || ch == QLatin1Char('{')) {
            stack.append({ch, i});
        } else if (ch == QLatin1Char(')') || ch == QLatin1Char(']') || ch == QLatin1Char('}')) {
            if (stack.isEmpty()) {
                result.append(makeDiagnostic(QStringLiteral("error"),
                                             QStringLiteral("Closing '%1' has no matching opener.").arg(ch),
                                             text, i));
            } else if (!isMatchingPair(stack.constLast().character, ch)) {
                result.append(makeDiagnostic(QStringLiteral("error"),
                                             QStringLiteral("Closing '%1' does not match '%2'.")
                                                 .arg(ch).arg(stack.constLast().character),
                                             text, i));
                stack.removeLast();
            } else {
                stack.removeLast();
            }
        }
    }

    if (!quote.isNull()) {
        result.append(makeDiagnostic(QStringLiteral("error"),
                                     QStringLiteral("String beginning with '%1' is not closed.").arg(quote),
                                     text, std::max(0, static_cast<int>(text.size()) - 1)));
    }
    if (blockComment) {
        result.append(makeDiagnostic(QStringLiteral("error"),
                                     QStringLiteral("Block comment is not closed."),
                                     text, std::max(0, static_cast<int>(text.size()) - 1)));
    }
    for (auto it = stack.crbegin(); it != stack.crend(); ++it) {
        result.append(makeDiagnostic(QStringLiteral("error"),
                                     QStringLiteral("Opening '%1' is missing '%2'.")
                                         .arg(it->character).arg(matchingCloser(it->character)),
                                     text, it->position));
    }
}

void TextEditorManager::addPythonDiagnostics(const QString &text, QVariantList &result) const
{
    const QStringList lines = text.split(QLatin1Char('\n'));
    int offset = 0;
    for (const QString &line : lines) {
        int spaces = 0;
        int tabs = 0;
        while (spaces + tabs < static_cast<int>(line.size())) {
            const QChar ch = line.at(spaces + tabs);
            if (ch == QLatin1Char(' ')) ++spaces;
            else if (ch == QLatin1Char('\t')) ++tabs;
            else break;
        }
        if (tabs > 0) {
            result.append(makeDiagnostic(QStringLiteral("warning"),
                                         spaces > 0
                                             ? QStringLiteral("Mixed spaces and tabs in Python indentation.")
                                             : QStringLiteral("Tab indentation can be converted to four spaces."),
                                         text, offset, spaces + tabs));
        } else if (spaces > 0 && spaces % 4 != 0 && !line.trimmed().isEmpty()) {
            result.append(makeDiagnostic(QStringLiteral("warning"),
                                         QStringLiteral("Python indentation is not a multiple of four spaces."),
                                         text, offset, spaces));
        }
        offset += static_cast<int>(line.size()) + 1;
    }
}

void TextEditorManager::addHtmlDiagnostics(const QString &text, QVariantList &result) const
{
    struct Tag { QString name; int position; };
    QVector<Tag> stack;
    const QRegularExpression tagPattern(QStringLiteral("<\\s*(/?)\\s*([A-Za-z][A-Za-z0-9:_-]*)[^>]*?>"));
    auto matches = tagPattern.globalMatch(text);
    while (matches.hasNext()) {
        const QRegularExpressionMatch match = matches.next();
        const QString whole = match.captured(0);
        const bool closing = !match.captured(1).isEmpty();
        const QString name = match.captured(2).toLower();
        const bool selfClosing = whole.trimmed().endsWith(QStringLiteral("/>")) || isVoidHtmlTag(name);
        if (selfClosing)
            continue;
        if (!closing) {
            stack.append({name, match.capturedStart()});
        } else if (stack.isEmpty()) {
            result.append(makeDiagnostic(QStringLiteral("error"),
                                         QStringLiteral("Closing tag </%1> has no opening tag.").arg(name),
                                         text, match.capturedStart(), match.capturedLength()));
        } else if (stack.constLast().name != name) {
            result.append(makeDiagnostic(QStringLiteral("error"),
                                         QStringLiteral("Closing tag </%1> does not match <%2>.")
                                             .arg(name).arg(stack.constLast().name),
                                         text, match.capturedStart(), match.capturedLength()));
            stack.removeLast();
        } else {
            stack.removeLast();
        }
    }
    for (auto it = stack.crbegin(); it != stack.crend(); ++it) {
        result.append(makeDiagnostic(QStringLiteral("error"),
                                     QStringLiteral("Tag <%1> is not closed.").arg(it->name),
                                     text, it->position));
    }
}

void TextEditorManager::addExternalPythonDiagnostic(const QString &text, QVariantList &result) const
{
    const QString python = QStandardPaths::findExecutable(QStringLiteral("python3"));
    if (python.isEmpty() || text.toUtf8().size() > MaximumDiagnosticBytes)
        return;

    QTemporaryFile temporary(QDir::tempPath() + QStringLiteral("/neutronos-texteditor-XXXXXX.py"));
    temporary.setAutoRemove(true);
    if (!temporary.open())
        return;
    temporary.write(text.toUtf8());
    temporary.flush();

    QProcess process;
    const QString program = QStringLiteral(
        "import pathlib,sys; p=pathlib.Path(sys.argv[1]); "
        "compile(p.read_text(encoding='utf-8'), str(p), 'exec')");
    process.start(python, {QStringLiteral("-c"), program, temporary.fileName()});
    if (!process.waitForStarted(1000))
        return;
    if (!process.waitForFinished(2500)) {
        process.kill();
        process.waitForFinished(500);
        result.append(makeDiagnostic(QStringLiteral("warning"),
                                     QStringLiteral("Python syntax check timed out; structural checks still completed."),
                                     text, 0));
        return;
    }
    if (process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0)
        return;

    const QString errorOutput = QString::fromUtf8(process.readAllStandardError()).trimmed();
    const QRegularExpression linePattern(QStringLiteral("line\\s+(\\d+)"));
    const QRegularExpressionMatch lineMatch = linePattern.match(errorOutput);
    const int lineNumber = lineMatch.hasMatch() ? lineMatch.captured(1).toInt() : 1;
    int offset = 0;
    const QStringList lines = text.split(QLatin1Char('\n'));
    for (int i = 0; i < lineNumber - 1 && i < lines.size(); ++i)
        offset += static_cast<int>(lines.at(i).size()) + 1;

    QString message = QStringLiteral("Python reported a syntax error.");
    const QStringList outputLines = errorOutput.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    if (!outputLines.isEmpty())
        message = outputLines.constLast().trimmed();
    result.append(makeDiagnostic(QStringLiteral("error"), message, text, offset));
}

QVariantList TextEditorManager::checkSyntax(const QString &text, const QString &language)
{
    QVariantList result;
    const QString effectiveLanguage = language.trimmed().isEmpty() ? m_language : language;
    const QString lower = effectiveLanguage.toLower();

    if (text.toUtf8().size() > MaximumDiagnosticBytes) {
        result.append(makeDiagnostic(QStringLiteral("warning"),
                                     QStringLiteral("Quick syntax checking is limited to 1 MB documents."),
                                     text, 0));
    } else if (lower.contains(QStringLiteral("json"))) {
        QJsonParseError parseError;
        QJsonDocument::fromJson(text.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            const QByteArray utf8 = text.toUtf8();
            const int byteOffset = std::clamp(static_cast<int>(parseError.offset), 0, static_cast<int>(utf8.size()));
            const int characterOffset = static_cast<int>(QString::fromUtf8(utf8.left(byteOffset)).size());
            result.append(makeDiagnostic(QStringLiteral("error"), parseError.errorString(), text, characterOffset));
        }
    } else {
        addBracketDiagnostics(text, effectiveLanguage, result);
        if (lower.contains(QStringLiteral("python"))) {
            addPythonDiagnostics(text, result);
            addExternalPythonDiagnostic(text, result);
        }
        if (lower.contains(QStringLiteral("html")) || lower.contains(QStringLiteral("xml")))
            addHtmlDiagnostics(text, result);
    }

    m_diagnostics = result;
    emit diagnosticsChanged();
    return m_diagnostics;
}

QVariantList TextEditorManager::suggestCorrections(const QString &text,
                                                    int cursorPosition,
                                                    const QString &language)
{
    QVariantList nearCursor;
    QVariantList other;
    QSet<QString> seen;
    const int textLength = static_cast<int>(text.size());
    const int safeCursor = std::clamp(cursorPosition, 0, textLength);
    const QString lowerLanguage = (language.trimmed().isEmpty() ? m_language : language).toLower();

    auto addSuggestion = [&](const QVariantMap &item) {
        const QString key = QStringLiteral("%1:%2:%3")
            .arg(item.value(QStringLiteral("start")).toInt())
            .arg(item.value(QStringLiteral("length")).toInt())
            .arg(item.value(QStringLiteral("replacement")).toString());
        if (seen.contains(key) || nearCursor.size() + other.size() >= MaximumSuggestions)
            return;
        seen.insert(key);
        const int start = item.value(QStringLiteral("start")).toInt();
        const int length = item.value(QStringLiteral("length")).toInt();
        if (safeCursor >= start && safeCursor <= start + std::max(1, length))
            nearCursor.append(item);
        else
            other.append(item);
    };

    struct WordFix { const char *wrong; const char *right; };
    static const WordFix fixes[] = {
        {"pritn", "print"}, {"retrun", "return"}, {"improt", "import"},
        {"fucntion", "function"}, {"funciton", "function"}, {"cosnt", "const"},
        {"strign", "string"}, {"fasle", "false"}, {"ture", "true"},
        {"widht", "width"}, {"heigth", "height"}, {"lenght", "length"},
        {"teh", "the"}, {"adn", "and"}, {"recieve", "receive"}
    };
    for (const WordFix &fix : fixes) {
        const QRegularExpression pattern(QStringLiteral("\\b%1\\b").arg(QString::fromLatin1(fix.wrong)),
                                         QRegularExpression::CaseInsensitiveOption);
        auto matches = pattern.globalMatch(text);
        while (matches.hasNext()) {
            const QRegularExpressionMatch match = matches.next();
            QString replacement = QString::fromLatin1(fix.right);
            const QString captured = match.captured(0);
            if (!captured.isEmpty() && captured.at(0).isUpper())
                replacement[0] = replacement.at(0).toUpper();
            addSuggestion(makeCorrection(QStringLiteral("Correct “%1”").arg(captured),
                                         QStringLiteral("Replace the likely typo with “%1”.").arg(replacement),
                                         text, match.capturedStart(), match.capturedLength(), replacement,
                                         QStringLiteral("word")));
        }
    }

    const QList<QPair<QChar, QString>> quoteFixes = {
        {QChar(u'\u2018'), QStringLiteral("'")}, {QChar(u'\u2019'), QStringLiteral("'")},
        {QChar(u'\u201C'), QStringLiteral("\"")}, {QChar(u'\u201D'), QStringLiteral("\"")}
    };
    for (const auto &fix : quoteFixes) {
        int position = text.indexOf(fix.first);
        while (position >= 0) {
            addSuggestion(makeCorrection(QStringLiteral("Use a straight quote"),
                                         QStringLiteral("Smart quotes can break source code and configuration files."),
                                         text, position, 1, fix.second, QStringLiteral("quote")));
            position = text.indexOf(fix.first, position + 1);
        }
    }

    if (lowerLanguage.contains(QStringLiteral("python"))) {
        const QRegularExpression tabs(QStringLiteral("(?m)^(\\t+)"));
        auto matches = tabs.globalMatch(text);
        while (matches.hasNext()) {
            const QRegularExpressionMatch match = matches.next();
            const QString replacement(match.capturedLength() * 4, QLatin1Char(' '));
            addSuggestion(makeCorrection(QStringLiteral("Convert indentation to spaces"),
                                         QStringLiteral("Replace each leading tab with four spaces."),
                                         text, match.capturedStart(), match.capturedLength(), replacement,
                                         QStringLiteral("indentation")));
        }
    }

    const QRegularExpression trailing(QStringLiteral("(?m)[ \\t]+$"));
    auto trailingMatches = trailing.globalMatch(text);
    int trailingCount = 0;
    while (trailingMatches.hasNext() && trailingCount < 4) {
        const QRegularExpressionMatch match = trailingMatches.next();
        addSuggestion(makeCorrection(QStringLiteral("Remove trailing whitespace"),
                                     QStringLiteral("Remove spaces or tabs at the end of this line."),
                                     text, match.capturedStart(), match.capturedLength(), QString(),
                                     QStringLiteral("whitespace")));
        ++trailingCount;
    }

    // Offer one unambiguous missing-closing-character correction.
    QVector<QPair<QChar, int>> stack;
    bool mismatch = false;
    QChar quote;
    bool escaped = false;
    for (int i = 0; i < textLength; ++i) {
        const QChar ch = text.at(i);
        if (!quote.isNull()) {
            if (escaped) escaped = false;
            else if (ch == QLatin1Char('\\')) escaped = true;
            else if (ch == quote) quote = QChar();
            continue;
        }
        if (ch == QLatin1Char('\'') || ch == QLatin1Char('"') || ch == QLatin1Char('`')) {
            quote = ch;
        } else if (ch == QLatin1Char('(') || ch == QLatin1Char('[') || ch == QLatin1Char('{')) {
            stack.append({ch, i});
        } else if (ch == QLatin1Char(')') || ch == QLatin1Char(']') || ch == QLatin1Char('}')) {
            if (stack.isEmpty() || !isMatchingPair(stack.constLast().first, ch)) {
                mismatch = true;
                break;
            }
            stack.removeLast();
        }
    }
    if (!mismatch && quote.isNull() && stack.size() == 1) {
        const QString closer = matchingCloser(stack.constLast().first);
        addSuggestion(makeCorrection(QStringLiteral("Add missing %1").arg(closer),
                                     QStringLiteral("Close the unmatched %1 opened on line %2.")
                                         .arg(stack.constLast().first)
                                         .arg(makeDiagnostic(QString(), QString(), text, stack.constLast().second)
                                                  .value(QStringLiteral("line")).toInt()),
                                     text, textLength, 0, closer, QStringLiteral("delimiter")));
    }

    QVariantList result = nearCursor;
    for (const QVariant &item : std::as_const(other)) {
        if (result.size() >= MaximumSuggestions)
            break;
        result.append(item);
    }
    m_corrections = result;
    emit correctionsChanged();
    return m_corrections;
}

void TextEditorManager::clearDiagnostics()
{
    if (m_diagnostics.isEmpty())
        return;
    m_diagnostics.clear();
    emit diagnosticsChanged();
}

void TextEditorManager::clearCorrections()
{
    if (m_corrections.isEmpty())
        return;
    m_corrections.clear();
    emit correctionsChanged();
}

void TextEditorManager::setBusy(bool busy)
{
    if (m_busy == busy) return;
    m_busy = busy;
    emit busyChanged();
}

void TextEditorManager::setError(const QString &error)
{
    if (m_error == error) return;
    m_error = error;
    emit errorChanged();
}

void TextEditorManager::setDirty(bool dirty)
{
    if (m_dirty == dirty) return;
    m_dirty = dirty;
    emit dirtyChanged();
}

void TextEditorManager::setDocument(const QString &path, const QString &text, const QString &encoding)
{
    m_currentPath = path;
    m_displayName = path.isEmpty() ? m_displayName : QFileInfo(path).fileName();
    m_text = text;
    m_encoding = encoding;
    m_language = path.isEmpty() ? QStringLiteral("Plain Text") : languageForPath(path);
    setDirty(false);
    setError(QString());
    clearDiagnostics();
    clearCorrections();
    emit documentChanged();
}

QString TextEditorManager::recoveryPathFor(const QString &path) const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/texteditor/recovery/%1.json").arg(hashName(path)));
}

QString TextEditorManager::backupPathFor(const QString &path) const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/texteditor/backups/%1.bak").arg(hashName(path)));
}

QString TextEditorManager::recentFilePath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/texteditor/recent.json"));
}

void TextEditorManager::loadRecentFiles()
{
    m_recentFiles.clear();
    QFile file(recentFilePath());
    if (!file.open(QIODevice::ReadOnly)) {
        emit recentFilesChanged();
        return;
    }
    const QJsonArray array = QJsonDocument::fromJson(file.readAll()).object().value(QStringLiteral("files")).toArray();
    for (const QJsonValue &value : array) {
        const QString path = normalizedPath(value.toString());
        if (QFileInfo::exists(path)) {
            QVariantMap item;
            item.insert(QStringLiteral("path"), path);
            item.insert(QStringLiteral("name"), QFileInfo(path).fileName());
            item.insert(QStringLiteral("language"), languageForPath(path));
            m_recentFiles.append(item);
        }
    }
    emit recentFilesChanged();
}

bool TextEditorManager::saveRecentFiles() const
{
    QJsonArray array;
    for (const QVariant &value : m_recentFiles)
        array.append(value.toMap().value(QStringLiteral("path")).toString());
    QJsonObject object;
    object.insert(QStringLiteral("schema"), 1);
    object.insert(QStringLiteral("files"), array);
    QSaveFile file(recentFilePath());
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    return file.commit();
}

void TextEditorManager::addRecentFile(const QString &path)
{
    const QString normalized = normalizedPath(path);
    QVariantList updated;
    QVariantMap current;
    current.insert(QStringLiteral("path"), normalized);
    current.insert(QStringLiteral("name"), QFileInfo(normalized).fileName());
    current.insert(QStringLiteral("language"), languageForPath(normalized));
    updated.append(current);
    for (const QVariant &value : std::as_const(m_recentFiles)) {
        const QVariantMap item = value.toMap();
        if (item.value(QStringLiteral("path")).toString() != normalized && updated.size() < 12)
            updated.append(item);
    }
    m_recentFiles = updated;
    saveRecentFiles();
    emit recentFilesChanged();
}
