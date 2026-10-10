#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QSet>

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
    bool scanning() const { return m_scan.isRunning(); }
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
private:
    struct ScanResult { QVariantList entries; QStringList directories; QString target; bool complete=true; };
    QString m_home,m_state;
    QVariantList m_games;
    QStringList m_roots;
    QFileSystemWatcher m_watch;
    QFutureWatcher<ScanResult> m_scan;
    QTimer m_debounce,m_presence;
    QSet<QString> m_pending;
    bool m_automatic=true,m_quiescent=false,m_destroying=false;
    static ScanResult scan(const QString &root);
    void next();
    void merge();
    void observe();
};
}
