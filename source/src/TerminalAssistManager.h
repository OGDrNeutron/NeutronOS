#pragma once

#include <QObject>
#include <QList>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#ifndef NEUTRONOS_STATE_DIR
#define NEUTRONOS_STATE_DIR "/var/lib/neutronos"
#endif

class TerminalAssistManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList snippets
               READ snippets
               NOTIFY snippetsChanged)

    Q_PROPERTY(QVariantMap correctionSuggestion
               READ correctionSuggestion
               NOTIFY correctionSuggestionChanged)

    Q_PROPERTY(bool smartCorrectionEnabled
               READ smartCorrectionEnabled
               WRITE setSmartCorrectionEnabled
               NOTIFY smartCorrectionEnabledChanged)

public:
    explicit TerminalAssistManager(QObject *parent = nullptr);

    QVariantList snippets() const;
    QVariantMap correctionSuggestion() const;

    bool smartCorrectionEnabled() const;
    void setSmartCorrectionEnabled(bool enabled);

    Q_INVOKABLE QVariantMap snippet(const QString &id) const;

    Q_INVOKABLE QVariantMap addSnippet(
        const QString &label,
        const QString &command,
        const QString &category = QStringLiteral("Custom"));

    Q_INVOKABLE QVariantMap updateSnippet(
        const QString &id,
        const QString &label,
        const QString &command,
        const QString &category);

    Q_INVOKABLE bool removeSnippet(const QString &id);
    Q_INVOKABLE bool moveSnippet(const QString &id, int offset);
    Q_INVOKABLE QString snippetText(const QString &id) const;

    Q_INVOKABLE void observeDraft(const QString &draft);
    Q_INVOKABLE void recordCommand(const QString &command);

    Q_INVOKABLE QString acceptSuggestionText();
    Q_INVOKABLE void dismissSuggestion();
    Q_INVOKABLE void refreshCommandDictionary();

signals:
    void snippetsChanged();
    void correctionSuggestionChanged();
    void smartCorrectionEnabledChanged();

private:
    struct SnippetRecord
    {
        QString id;
        QString label;
        QString category;
        QString command;
        int order = 0;
    };

    QList<SnippetRecord> m_snippets;
    QVariantMap m_correctionSuggestion;
    bool m_smartCorrectionEnabled = true;

    QSet<QString> m_commandDictionary;
    QStringList m_recentCommandTokens;

    QString m_stateDir;
    QString m_snippetsPath;
    QString m_settingsPath;

    bool ensureStateDirectory() const;
    void loadSettings();
    void saveSettings() const;

    void loadSnippets();
    bool saveSnippets() const;
    void seedDefaultSnippets();
    void normalizeOrder();

    QVariantMap snippetToVariant(const SnippetRecord &record) const;
    int indexOfSnippet(const QString &id) const;
    QString createSnippetId(const QString &label) const;

    QVariantMap buildCorrectionSuggestion(const QString &draft) const;
    void setCorrectionSuggestion(const QVariantMap &suggestion);

    static bool correctionEligible(const QString &draft);
    static QString commandToken(const QString &draft);
    static QString replaceCommandToken(
        const QString &draft,
        const QString &replacement);
    static int editDistance(const QString &left, const QString &right);
    static bool dangerousCommandToken(const QString &token);
};
