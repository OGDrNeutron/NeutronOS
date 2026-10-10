#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QSet>
#include <atomic>
#include <memory>

namespace GeminiGames {
class GameLibrary final : public QObject {
    Q_OBJECT
public:
    explicit GameLibrary(const QString &home, QObject *parent=nullptr);
    ~GameLibrary() override;
    QVariantList games() const { return m_games; }
    QVariantList roots() const;
    QString home() const { return m_home; }
    QString stateDirectory() const { return m_state; }
    bool initialized() const { return !m_loading; }
    bool scanning() const { return m_loading || m_busy; }
    bool recoveryRequired() const { return m_recoveryRequired; }
    int scannedEntries() const { return m_progress->load(); }
    void cancelScan();
    bool addRoot(const QString &path);
    QVariantMap browseFolders(const QString &path) const;
    bool permittedFolder(const QString &path) const;
    bool editRoot(int index, const QString &path);
    bool removeRoot(int index);
    void rescan(const QString &target=QString());
    bool update(const QString &id, const QVariantMap &metadata);
    QVariantMap find(const QString &id) const;
    void setAutomatic(bool enabled);
    void setQuiescent(bool enabled);
    bool automatic() const { return m_automatic; }
    static QVariantMap recognize(const QString &path);
    static QString materialSignature(const QString &path);
    bool save();
    bool registerInstallation(const QVariantMap &record);
    bool retireInstallation(const QString &id);
signals:
    void changed();
    void error(QString message);
    void scanStatusChanged();
private:
    struct ScanResult { QVariantList entries, games; QStringList directories, files; QString target, issue; QByteArray serialized; quint64 generation=0; bool complete=true,retryRequired=false,unavailable=false; };
    struct LoadResult { QVariantList games; QStringList roots; bool automatic=true,valid=true; QString issue; };
    QString m_home,m_state;
    QVariantList m_games;
    QStringList m_roots;
    QFileSystemWatcher m_watch;
    QFutureWatcher<ScanResult> m_scan;
    QFutureWatcher<LoadResult> m_load;
    std::shared_ptr<std::atomic_bool> m_cancel=std::make_shared<std::atomic_bool>(false);
    std::shared_ptr<std::atomic_int> m_progress=std::make_shared<std::atomic_int>(0);
    quint64 m_generation=0;
    bool m_loading=true,m_busy=false,m_recoveryRequired=false,m_persistenceValid=true;
    QSet<QString> m_watched;
    QStringList m_watchQueue;
    QTimer m_debounce,m_presence,m_status,m_watchTimer;
    QSet<QString> m_pending;
    bool m_automatic=true,m_quiescent=false,m_destroying=false;
    static ScanResult scan(const QString &root,const QString &state,const std::shared_ptr<std::atomic_bool> &cancel,const std::shared_ptr<std::atomic_int> &progress);
    static ScanResult prepare(ScanResult result,const QVariantList &previous,const QStringList &roots,bool automatic,quint64 generation);
    void queueScan(const QString &target);
    void next();
    void merge();
    void observe();
};
}
