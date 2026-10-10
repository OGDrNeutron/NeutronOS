#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QTimer>
#include <QVariantList>
#include <QHash>
#include <QSet>

namespace GeminiGames {
class GameArtwork final : public QObject {
    Q_OBJECT
public:
    explicit GameArtwork(const QString &home,QObject *parent=nullptr);
    ~GameArtwork() override;
    bool valid()const{return m_valid;}
    QString directory()const{return m_directory;}
    QVariantList files()const{return m_files;}
    QStringList formats()const{return m_formats;}
    QVariantList decorate(const QVariantList &games)const;
    bool contains(const QString &path)const;
    void refresh();
    void setQuiescent(bool value);
    static QString normalizedTitle(const QString &title);
signals:
    void changed();
    void error(QString message);
private:
    struct Result {QVariantList files;QStringList errors;};
    QString m_directory,m_cache;
    QStringList m_formats,m_unwatched;
    QVariantList m_files;
    QHash<QString,QStringList> m_exact,m_normalized;
    QHash<QString,QVariantMap> m_byPath;
    QFileSystemWatcher m_watch;
    QFutureWatcher<Result> m_scan;
    QTimer m_debounce,m_presence;
    QSet<QString> m_dirty;
    bool m_valid=false,m_quiescent=false,m_pending=false,m_destroying=false;
    static Result scan(const QString &directory,const QString &cache,const QStringList &formats,const QVariantList &previous,const QSet<QString> &dirty);
    void start();
    void merge();
};
}
