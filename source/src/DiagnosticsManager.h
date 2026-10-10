#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QFutureWatcher>

class DiagnosticsManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY stageChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY lastMessageChanged)
    Q_PROPERTY(QString lastRun READ lastRun NOTIFY diagnosticsChanged)
    Q_PROPERTY(QVariantList checks READ checks NOTIFY diagnosticsChanged)
    Q_PROPERTY(int passedCount READ passedCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(int warningCount READ warningCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(int failedCount READ failedCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(QString systemSummary READ systemSummary NOTIFY diagnosticsChanged)
    Q_PROPERTY(QString overallHealth READ overallHealth NOTIFY diagnosticsChanged)
    Q_PROPERTY(QString lastBundlePath READ lastBundlePath NOTIFY bundleChanged)

public:
    explicit DiagnosticsManager(const QString &neutronRoot, QObject *parent = nullptr);

    bool busy() const { return m_busy; }
    int progress() const { return m_progress; }
    QString stage() const { return m_stage; }
    QString lastMessage() const { return m_lastMessage; }
    QString lastRun() const { return m_lastRun; }
    QVariantList checks() const { return m_checks; }
    int passedCount() const { return m_passedCount; }
    int warningCount() const { return m_warningCount; }
    int failedCount() const { return m_failedCount; }
    QString systemSummary() const { return m_systemSummary; }
    QString overallHealth() const { return m_failedCount > 0 ? QStringLiteral("FAIL") :
                                           m_warningCount > 0 ? QStringLiteral("WARNING") : QStringLiteral("PASS"); }
    QString lastBundlePath() const { return m_lastBundlePath; }

    Q_INVOKABLE bool runFullDiagnostics();
    Q_INVOKABLE bool refresh();
    Q_INVOKABLE bool rerunCheck(const QString &checkId);
    Q_INVOKABLE bool exportSupportBundle();
    Q_INVOKABLE QString reportText() const;

signals:
    void busyChanged();
    void progressChanged();
    void stageChanged();
    void lastMessageChanged();
    void diagnosticsChanged();
    void bundleChanged();

private:
    QVariantMap collectDiagnostics() const;
    QVariantMap buildSupportBundle() const;
    void setBusy(bool value);
    void setProgress(int value);
    void setStage(const QString &value);
    void setLastMessage(const QString &value);
    static QString commandOutput(const QString &program, const QStringList &arguments, int timeoutMs = 5000);
    static QString readText(const QString &path);
    static QString redact(const QString &text);

    QString m_neutronRoot;
    bool m_busy = false;
    int m_progress = 0;
    QString m_stage = QStringLiteral("Ready");
    QString m_lastMessage = QStringLiteral("Diagnostics have not run yet.");
    QString m_lastRun = QStringLiteral("Never");
    QVariantList m_checks;
    int m_passedCount = 0;
    int m_warningCount = 0;
    int m_failedCount = 0;
    QString m_systemSummary = QStringLiteral("Waiting for diagnostics");
    QString m_lastBundlePath;
    QString m_requestedCheckId;
    QFutureWatcher<QVariantMap> m_diagnosticsWatcher;
    QFutureWatcher<QVariantMap> m_bundleWatcher;
};
