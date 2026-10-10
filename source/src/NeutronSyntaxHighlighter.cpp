#include "NeutronSyntaxHighlighter.h"
#include <utility>

#include <QColor>
#include <QFont>
#include <QTextDocument>

NeutronSyntaxHighlighter::NeutronSyntaxHighlighter(QObject *parent)
    : QSyntaxHighlighter(parent)
{
    rebuildRules();
}

QQuickTextDocument *NeutronSyntaxHighlighter::textDocument() const { return m_textDocument; }

void NeutronSyntaxHighlighter::setTextDocument(QQuickTextDocument *document)
{
    if (m_textDocument == document)
        return;
    m_textDocument = document;
    setDocument(document ? document->textDocument() : nullptr);
    emit textDocumentChanged();
}

QString NeutronSyntaxHighlighter::language() const { return m_language; }

void NeutronSyntaxHighlighter::setLanguage(const QString &language)
{
    if (m_language == language)
        return;
    m_language = language;
    rebuildRules();
    rehighlight();
    emit languageChanged();
}

QTextCharFormat NeutronSyntaxHighlighter::format(const QColor &color, bool bold, bool italic) const
{
    QTextCharFormat value;
    value.setForeground(color);
    if (bold) value.setFontWeight(QFont::DemiBold);
    value.setFontItalic(italic);
    return value;
}

void NeutronSyntaxHighlighter::rebuildRules()
{
    m_rules.clear();
    const QTextCharFormat keyword = format(QColor(QStringLiteral("#8EC5FF")), true);
    const QTextCharFormat type = format(QColor(QStringLiteral("#C59CFF")), true);
    const QTextCharFormat string = format(QColor(QStringLiteral("#A7E6A1")));
    const QTextCharFormat number = format(QColor(QStringLiteral("#FFD37A")));
    const QTextCharFormat comment = format(QColor(QStringLiteral("#6F8DA8")), false, true);
    const QTextCharFormat property = format(QColor(QStringLiteral("#75E6FF")));
    const QTextCharFormat tag = format(QColor(QStringLiteral("#FF8FB8")), true);
    const QTextCharFormat heading = format(QColor(QStringLiteral("#7DF9FF")), true);
    m_commentFormat = comment;

    auto add = [this](const QString &pattern, const QTextCharFormat &style) {
        m_rules.append({QRegularExpression(pattern), style});
    };

    add(QStringLiteral("\\b[0-9]+(?:\\.[0-9]+)?\\b"), number);
    add(QStringLiteral("\"(?:\\\\.|[^\"\\\\])*\""), string);
    add(QStringLiteral("'(?:\\\\.|[^'\\\\])*'"), string);

    const QString lower = m_language.toLower();
    if (lower.contains(QStringLiteral("python"))) {
        add(QStringLiteral("\\b(?:and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\\b"), keyword);
        add(QStringLiteral("#[^\\n]*"), comment);
        add(QStringLiteral("\\b(?:int|str|float|bool|list|dict|set|tuple|object)\\b"), type);
    } else if (lower.contains(QStringLiteral("html")) || lower.contains(QStringLiteral("xml"))) {
        add(QStringLiteral("</?[A-Za-z][^>]*>"), tag);
        add(QStringLiteral("\\b[A-Za-z_:][-A-Za-z0-9_:.]*(?=\\s*=)"), property);
        add(QStringLiteral("<!--[\\s\\S]*?-->"), comment);
    } else if (lower.contains(QStringLiteral("css"))) {
        add(QStringLiteral("[.#]?[A-Za-z_-][A-Za-z0-9_-]*(?=\\s*\\{)"), tag);
        add(QStringLiteral("\\b[A-Za-z-]+(?=\\s*:)"), property);
        add(QStringLiteral("/\\*[^*]*\\*+(?:[^/*][^*]*\\*+)*/"), comment);
    } else if (lower.contains(QStringLiteral("markdown"))) {
        add(QStringLiteral("^#{1,6}\\s+.*$"), heading);
        add(QStringLiteral("\\*\\*[^*]+\\*\\*|__[^_]+__"), keyword);
        add(QStringLiteral("`[^`]+`"), string);
        add(QStringLiteral("^>.*$"), comment);
    } else if (lower.contains(QStringLiteral("json"))) {
        add(QStringLiteral("\"[^\"]+\"(?=\\s*:)"), property);
        add(QStringLiteral("\\b(?:true|false|null)\\b"), keyword);
    } else {
        add(QStringLiteral("\\b(?:alignas|alignof|and|asm|auto|bool|break|case|catch|char|class|const|constexpr|continue|default|delete|do|double|else|enum|explicit|export|extern|false|float|for|friend|if|inline|int|long|namespace|new|nullptr|operator|private|protected|public|register|return|short|signed|sizeof|static|struct|switch|template|this|throw|true|try|typedef|typename|union|unsigned|using|virtual|void|volatile|while|property|signal|readonly|required|function|import|pragma|var|let|const)\\b"), keyword);
        add(QStringLiteral("\\b(?:QString|QVariant|QObject|Item|Rectangle|Text|Image|Loader|Timer|ListView|GridView|Component|MouseArea|Connections)\\b"), type);
        add(QStringLiteral("//[^\\n]*"), comment);
        add(QStringLiteral("\\b[A-Za-z_][A-Za-z0-9_]*(?=\\s*:)"), property);
    }

    m_multilineStart = QRegularExpression(QStringLiteral("/\\*"));
    m_multilineEnd = QRegularExpression(QStringLiteral("\\*/"));
}

void NeutronSyntaxHighlighter::highlightBlock(const QString &text)
{
    for (const Rule &rule : std::as_const(m_rules)) {
        auto matches = rule.pattern.globalMatch(text);
        while (matches.hasNext()) {
            const QRegularExpressionMatch match = matches.next();
            setFormat(match.capturedStart(), match.capturedLength(), rule.format);
        }
    }

    const QString lower = m_language.toLower();
    if (lower.contains(QStringLiteral("python")) || lower.contains(QStringLiteral("markdown")) ||
        lower.contains(QStringLiteral("json")) || lower.contains(QStringLiteral("html")) ||
        lower.contains(QStringLiteral("xml"))) {
        setCurrentBlockState(0);
        return;
    }

    setCurrentBlockState(0);
    int start = previousBlockState() == 1 ? 0 : text.indexOf(m_multilineStart);
    while (start >= 0) {
        const QRegularExpressionMatch endMatch = m_multilineEnd.match(text, start + 2);
        int length = 0;
        if (!endMatch.hasMatch()) {
            setCurrentBlockState(1);
            length = text.length() - start;
        } else {
            length = endMatch.capturedEnd() - start;
        }
        setFormat(start, length, m_commentFormat);
        if (!endMatch.hasMatch())
            break;
        start = text.indexOf(m_multilineStart, start + length);
    }
}
