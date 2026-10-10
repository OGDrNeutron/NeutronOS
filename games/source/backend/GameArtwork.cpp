#include "GameArtwork.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>
#include <QtConcurrent>

namespace GeminiGames {
QString GameArtwork::normalizedTitle(const QString &title){
    QString value=title.normalized(QString::NormalizationForm_C).toCaseFolded();
    value.replace(QRegularExpression("[\\s_.-]+")," ");return value.trimmed();
}
GameArtwork::GameArtwork(const QString &home,QObject *parent):QObject(parent),m_directory(home+"/apps/gemini-games/artwork"),m_cache(home+"/apps/gemini-games/artwork-cache"){
    // Reject redirected storage before creating or reading personal directories.
    for(const auto &path:QStringList{home,home+"/apps",home+"/apps/gemini-games",m_directory,m_cache}){
        QFileInfo info(path);
        if(info.exists()&&(info.isSymLink()||info.canonicalFilePath()!=QDir::cleanPath(path)))return;
        if(!info.exists()&&!QDir().mkpath(path))return;
    }
    auto available=QImageReader::supportedImageFormats();
    for(const auto &format:QStringList{"png","jpg","jpeg","webp"})if(available.contains(format.toLatin1())||(format=="jpg"&&available.contains("jpeg")))m_formats.append(format);
    m_valid=true;m_debounce.setInterval(250);m_debounce.setSingleShot(true);m_presence.setInterval(15000);
    connect(&m_debounce,&QTimer::timeout,this,&GameArtwork::start);
    connect(&m_scan,&QFutureWatcher<Result>::finished,this,&GameArtwork::merge);
    connect(&m_watch,&QFileSystemWatcher::directoryChanged,this,[this]{refresh();});
    connect(&m_watch,&QFileSystemWatcher::fileChanged,this,[this](const QString &path){m_dirty.insert(path);refresh();});
    connect(&m_presence,&QTimer::timeout,this,[this]{
        if(!m_watch.directories().contains(m_directory)&&QFileInfo(m_directory).isDir()){m_watch.addPath(m_directory);refresh();}
        // Watch limits vary by kernel; poll only files not covered by a watcher.
        for(const auto &path:m_unwatched){auto old=m_byPath.value(path);QFileInfo info(path);
            if(!info.isFile()||info.isSymLink()||info.size()!=old.value("bytes").toLongLong()||info.lastModified().toMSecsSinceEpoch()!=old.value("modified").toLongLong()){m_dirty.insert(path);refresh();}
        }
    });
    m_watch.addPath(m_directory);m_presence.start();refresh();
}
GameArtwork::~GameArtwork(){m_destroying=true;m_cancel->store(true);disconnect(&m_scan,nullptr,this,nullptr);}
void GameArtwork::refresh(){if(!m_valid||m_destroying)return;m_pending=true;if(!m_quiescent)m_debounce.start();}
void GameArtwork::setQuiescent(bool value){m_quiescent=value;if(value){m_debounce.stop();m_presence.stop();}else{m_presence.start();if(m_pending)m_debounce.start();}}
void GameArtwork::start(){if(!m_pending||m_scan.isRunning()||m_quiescent)return;m_pending=false;auto directory=m_directory,cache=m_cache;auto formats=m_formats;auto previous=m_files;auto dirty=m_dirty;auto cancel=m_cancel;m_dirty.clear();m_scan.setFuture(QtConcurrent::run([directory,cache,formats,previous,dirty,cancel]{return scan(directory,cache,formats,previous,dirty,cancel);}));}
GameArtwork::Result GameArtwork::scan(const QString &directory,const QString &cache,const QStringList &formats,const QVariantList &previous,const QSet<QString> &dirty,const std::shared_ptr<std::atomic_bool> &cancel){
    Result result;QHash<QString,QVariantMap> prior;for(const auto &v:previous){auto f=v.toMap();prior.insert(f.value("path").toString(),f);}
    // Recheck after watchers fire: an artwork directory replaced with a symlink is not trusted.
    for(const auto &path:QStringList{directory,cache})if(QFileInfo(path).isSymLink()||QFileInfo(path).canonicalFilePath()!=path)return result;
    QDir dir(directory);int count=0;
    for(const auto &file:dir.entryInfoList(QDir::Files|QDir::NoSymLinks,QDir::Name)){
        if(cancel->load())break;
        if(++count>10000){result.errors<<"Artwork index reached its safe file limit.";break;}
        if(!formats.contains(file.suffix().toLower())||file.size()>64*1024*1024||file.canonicalFilePath()!=file.absoluteFilePath())continue;
        auto old=prior.value(file.absoluteFilePath());
        if(!dirty.contains(file.absoluteFilePath())&&!old.isEmpty()&&old.value("bytes").toLongLong()==file.size()&&old.value("modified").toLongLong()==file.lastModified().toMSecsSinceEpoch()){
            QString thumbnail=QUrl(old.value("thumbnail").toString()).toLocalFile();if(QFileInfo(thumbnail).isFile()&&!QFileInfo(thumbnail).isSymLink()){result.files.append(old);continue;}
        }
        QFile original(file.absoluteFilePath());if(!original.open(QIODevice::ReadOnly))continue;
        QCryptographicHash hash(QCryptographicHash::Sha256);if(!hash.addData(&original))continue;
        auto digest=QString::fromLatin1(hash.result().toHex());QString thumbnail=cache+"/"+digest+".png";
        if(QFileInfo(thumbnail).isSymLink())continue;
        if(!QFileInfo::exists(thumbnail)){
            original.seek(0);QImageReader reader(&original);reader.setAutoTransform(true);QSize size=reader.size();
            if(!size.isValid()||qint64(size.width())*size.height()>32000000)continue;
            reader.setScaledSize(size.scaled(QSize(512,768),Qt::KeepAspectRatio));QImage image=reader.read();
            if(image.isNull()){result.errors<<"Could not decode artwork: "+file.fileName();continue;}
            image=image.scaled(QSize(512,768),Qt::KeepAspectRatio,Qt::SmoothTransformation);
            QSaveFile out(thumbnail);if(!out.open(QIODevice::WriteOnly)||!image.save(&out,"PNG")||!out.commit())continue;
        }
        // Discard inconsistent reads if the original was replaced during thumbnail creation.
        QFileInfo after(file.absoluteFilePath());if(after.size()!=file.size()||after.lastModified()!=file.lastModified())continue;
        result.files.append(QVariantMap{{"path",file.absoluteFilePath()},{"fileName",file.fileName()},{"title",file.completeBaseName()},{"thumbnail",QUrl::fromLocalFile(thumbnail).toString()},{"sha256",digest},{"bytes",file.size()},{"modified",file.lastModified().toMSecsSinceEpoch()}});
    }return result;
}
void GameArtwork::merge(){auto result=m_scan.result();m_files=result.files;m_exact.clear();m_normalized.clear();m_byPath.clear();
    if(!m_watch.files().isEmpty())m_watch.removePaths(m_watch.files());
    QStringList paths;
    for(const auto &value:m_files){auto file=value.toMap();QString path=file.value("path").toString(),title=file.value("title").toString();m_exact[title].append(path);m_normalized[normalizedTitle(title)].append(path);m_byPath.insert(path,file);paths<<path;}
    m_unwatched=paths.isEmpty()?QStringList():m_watch.addPaths(paths);
    for(const auto &message:result.errors){emit error(message);}
    emit changed();if(m_pending&&!m_quiescent)m_debounce.start();
}
bool GameArtwork::contains(const QString &path)const{return m_byPath.contains(path);}
QVariantList GameArtwork::decorate(const QVariantList &games)const{
    QVariantList out;
    for(const auto &value:games){auto game=value.toMap();QString title=game.value("titleOverride",game.value("title")).toString();QString manual=game.value("artworkOverride").toString();
        if(manual.startsWith("file:"))manual=QUrl(manual).toLocalFile();
        QStringList matches=m_exact.value(title);if(matches.isEmpty())matches=m_normalized.value(normalizedTitle(title));
        QString selected=manual.isEmpty()?(matches.size()==1?matches.first():QString()):manual;
        QString display=m_byPath.value(selected).value("thumbnail").toString();
        if(display.isEmpty())display=game.value("artwork").toString();
        game["artworkDisplay"]=display;game["artworkFile"]=selected;game["artworkCandidates"]=matches;game["artworkAutomatic"]=manual.isEmpty();
        game["artworkSelectionRequired"]=manual.isEmpty()&&matches.size()>1;game["manualArtworkMissing"]=!manual.isEmpty()&&!m_byPath.contains(manual);
        out.append(game);
    }return out;
}
}
