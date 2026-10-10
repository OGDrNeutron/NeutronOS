#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>

class LogsManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList sources READ sources NOTIFY sourcesChanged)
    Q_PROPERTY(QString output READ output NOTIFY outputChanged)
    Q_PROPERTY(bool live READ live NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(QString activeSourceId READ activeSourceId NOTIFY stateChanged)
    Q_PROPERTY(QString activeSourceName READ activeSourceName NOTIFY stateChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY stateChanged)

public:
    explicit LogsManager(const QString &neutronRoot, QObject *parent = nullptr);
    ~LogsManager() override;

    QVariantList sources() const;
    QString output() const;
    bool live() const;
    bool busy() const;
    QString activeSourceId() const;
    QString activeSourceName() const;
    QString lastMessage() const;

    Q_INVOKABLE void refreshSources();
    Q_INVOKABLE bool loadLive(const QString &sourceId);
    Q_INVOKABLE bool loadHistory(const QString &sourceId, int lines = 500);
    Q_INVOKABLE bool stopLive();
    Q_INVOKABLE void clearOutput();
    Q_INVOKABLE QVariantMap sourceDetails(const QString &sourceId) const;

signals:
    void sourcesChanged();
    void outputChanged();
    void stateChanged();

private:
    QString m_neutronRoot;
    QVariantList m_sources;
    QString m_output;
    bool m_live = false;
    bool m_busy = false;
    QString m_activeSourceId;
    QString m_activeSourceName;
    QString m_lastMessage;
    QProcess *m_process = nullptr;
    int m_maxOutputCharacters = 1200000;

    QVariantMap findSource(const QString &sourceId) const;
    bool startSource(const QVariantMap &source, bool liveMode, int lines);
    void appendOutput(const QByteArray &data);
    void setMessage(const QString &message);
    static int runSync(const QString &program,
                       const QStringList &arguments,
                       QByteArray *standardOutput,
                       QByteArray *standardError,
                       int timeoutMs = 12000);
    static QString executable(const QString &name);
    static QString sourceId(const QString &type, const QString &target);
    void discoverSystemd(QVariantList *target) const;
    void discoverDocker(QVariantList *target) const;
    void discoverLogFiles(QVariantList *target) const;
    void discoverScripts(QVariantList *target) const;

private slots:
    void onReadyRead();
    void onFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessError(QProcess::ProcessError error);
};
