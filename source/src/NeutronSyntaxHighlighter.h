#pragma once

#include <QQuickTextDocument>
#include <QRegularExpression>
#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QVector>

class NeutronSyntaxHighlighter : public QSyntaxHighlighter
{
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument *textDocument READ textDocument WRITE setTextDocument NOTIFY textDocumentChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)

public:
    explicit NeutronSyntaxHighlighter(QObject *parent = nullptr);

    QQuickTextDocument *textDocument() const;
    void setTextDocument(QQuickTextDocument *document);
    QString language() const;
    void setLanguage(const QString &language);

signals:
    void textDocumentChanged();
    void languageChanged();

protected:
    void highlightBlock(const QString &text) override;

private:
    struct Rule {
        QRegularExpression pattern;
        QTextCharFormat format;
    };

    void rebuildRules();
    QTextCharFormat format(const QColor &color, bool bold = false, bool italic = false) const;

    QQuickTextDocument *m_textDocument = nullptr;
    QString m_language = QStringLiteral("Plain Text");
    QVector<Rule> m_rules;
    QRegularExpression m_multilineStart;
    QRegularExpression m_multilineEnd;
    QTextCharFormat m_commentFormat;
};
