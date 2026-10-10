#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class DeveloperModeManager;

class TextEditorManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY documentChanged)
    Q_PROPERTY(QString displayName READ displayName NOTIFY documentChanged)
    Q_PROPERTY(bool untitled READ untitled NOTIFY documentChanged)
    Q_PROPERTY(QString text READ text NOTIFY documentChanged)
    Q_PROPERTY(QString encoding READ encoding NOTIFY documentChanged)
    Q_PROPERTY(QString language READ language NOTIFY documentChanged)
    Q_PROPERTY(bool dirty READ dirty NOTIFY dirtyChanged)
    Q_PROPERTY(bool recoveryAvailable READ recoveryAvailable NOTIFY recoveryChanged)
    Q_PROPERTY(QVariantList recentFiles READ recentFiles NOTIFY recentFilesChanged)
    Q_PROPERTY(QVariantList diagnostics READ diagnostics NOTIFY diagnosticsChanged)
    Q_PROPERTY(QVariantList corrections READ corrections NOTIFY correctionsChanged)

public:
    explicit TextEditorManager(const QString &neutronRoot,
                               DeveloperModeManager *developerModeManager,
                               QObject *parent = nullptr);

    bool busy() const;
    QString error() const;
    QString currentPath() const;
    QString displayName() const;
    bool untitled() const;
    QString text() const;
    QString encoding() const;
    QString language() const;
    bool dirty() const;
    bool recoveryAvailable() const;
    QVariantList recentFiles() const;
    QVariantList diagnostics() const;
    QVariantList corrections() const;

    Q_INVOKABLE void initialize();
    Q_INVOKABLE void newUntitled();
    Q_INVOKABLE bool openFile(const QString &path);
    Q_INVOKABLE bool createDocument(const QString &path, const QString &initialText = QString());
    Q_INVOKABLE void updateText(const QString &text);
    Q_INVOKABLE bool save();
    Q_INVOKABLE bool saveAs(const QString &path);
    Q_INVOKABLE bool writeRecovery(const QString &path, const QString &text);
    Q_INVOKABLE QVariantMap recoveryInfo(const QString &path) const;
    Q_INVOKABLE bool restoreRecovery(const QString &path);
    Q_INVOKABLE bool discardRecovery(const QString &path);
    Q_INVOKABLE bool requiresDeveloperMode(const QString &path) const;
    Q_INVOKABLE bool canWritePath(const QString &path) const;
    Q_INVOKABLE bool isSupported(const QString &path) const;
    Q_INVOKABLE QString languageForPath(const QString &path) const;
    Q_INVOKABLE QStringList supportedExtensions() const;
    Q_INVOKABLE QString defaultDocumentsPath() const;
    Q_INVOKABLE QVariantMap fileInfo(const QString &path) const;
    Q_INVOKABLE QVariantList checkSyntax(const QString &text, const QString &language = QString());
    Q_INVOKABLE QVariantList suggestCorrections(const QString &text,
                                                int cursorPosition,
                                                const QString &language = QString());
    Q_INVOKABLE void clearDiagnostics();
    Q_INVOKABLE void clearCorrections();

signals:
    void busyChanged();
    void errorChanged();
    void documentChanged();
    void dirtyChanged();
    void recoveryChanged();
    void recentFilesChanged();
    void diagnosticsChanged();
    void correctionsChanged();
    void saved(const QString &path);
    void opened(const QString &path);
    void operationFailed(const QString &message);

private:
    void setBusy(bool busy);
    void setError(const QString &error);
    void setDirty(bool dirty);
    void setDocument(const QString &path, const QString &text, const QString &encoding);
    QString normalizedPath(const QString &path) const;
    QString userHomePath() const;
    QString recoveryPathFor(const QString &path) const;
    QString backupPathFor(const QString &path) const;
    QString recentFilePath() const;
    void loadRecentFiles();
    bool saveRecentFiles() const;
    void addRecentFile(const QString &path);
    bool saveToPath(const QString &path);
    QVariantMap makeDiagnostic(const QString &severity,
                               const QString &message,
                               const QString &text,
                               int offset,
                               int length = 1) const;
    QVariantMap makeCorrection(const QString &title,
                               const QString &detail,
                               const QString &text,
                               int start,
                               int length,
                               const QString &replacement,
                               const QString &kind) const;
    void addBracketDiagnostics(const QString &text,
                               const QString &language,
                               QVariantList &result) const;
    void addPythonDiagnostics(const QString &text, QVariantList &result) const;
    void addHtmlDiagnostics(const QString &text, QVariantList &result) const;
    void addExternalPythonDiagnostic(const QString &text, QVariantList &result) const;

    QString m_neutronRoot;
    DeveloperModeManager *m_developerModeManager = nullptr;
    bool m_busy = false;
    QString m_error;
    QString m_currentPath;
    QString m_displayName = QStringLiteral("Untitled 1");
    QString m_text;
    QString m_encoding = QStringLiteral("UTF-8");
    QString m_language = QStringLiteral("Plain Text");
    bool m_dirty = false;
    bool m_recoveryAvailable = false;
    QVariantList m_recentFiles;
    QVariantList m_diagnostics;
    QVariantList m_corrections;
    int m_untitledCounter = 0;
};
