#include "GameLibrary.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QXmlStreamReader>
#include <QtConcurrent>
#include <sys/stat.h>
#include <unistd.h>
#include <QStorageInfo>

namespace GeminiGames {
namespace {
QByteArray bytes(const QString &path,qint64 limit=65536) { QFile f(path); return f.open(QIODevice::ReadOnly)?f.read(limit):QByteArray(); }
QString hash(const QByteArray &b) { return QString::fromLatin1(QCryptographicHash::hash(b,QCryptographicHash::Sha256).toHex()); }
QString vdf(const QString &s,const QString &key) { return QRegularExpression("\""+QRegularExpression::escape(key)+"\"\\s*\"([^\"]*)\"").match(s).captured(1); }
bool inside(const QString &p,const QString &root) { return p==root || p.startsWith(root+"/"); }
}
GameLibrary::GameLibrary(const QString &home,QObject *parent):QObject(parent),m_home(QDir::cleanPath(home)),m_state(m_home+"/apps/gemini-games") {
    QDir().mkpath(m_state);
    auto doc=QJsonDocument::fromJson(bytes(m_state+"/library.json",16*1024*1024)).object();
    m_games=doc.value("games").toArray().toVariantList();
    for(const auto &v:doc.value("roots").toArray()) if(v.isString()) m_roots.append(v.toString());
    m_automatic=doc.value("automatic").toBool(true);
    if(m_roots.isEmpty()) m_roots.append(m_home+"/Games");
    m_debounce.setInterval(350);m_debounce.setSingleShot(true);
    m_presence.setInterval(15000);
    connect(&m_debounce,&QTimer::timeout,this,&GameLibrary::next);
    connect(&m_watch,&QFileSystemWatcher::directoryChanged,this,[this](const QString &p){if(m_automatic)rescan(p);});
    connect(&m_watch,&QFileSystemWatcher::fileChanged,this,[this](const QString &p){if(m_automatic)rescan(QFileInfo(p).absolutePath());});
    connect(&m_scan,&QFutureWatcher<ScanResult>::finished,this,&GameLibrary::merge);
    connect(&m_presence,&QTimer::timeout,this,[this]{observe();});
    m_presence.start();observe();
}
GameLibrary::~GameLibrary(){m_destroying=true;disconnect(&m_scan,nullptr,this,nullptr);m_scan.waitForFinished();}
QVariantList GameLibrary::roots() const { QVariantList out; for(const auto &p:m_roots) out.append(QVariantMap{{"path",p},{"online",QFileInfo(p).isDir()}});return out; }
bool GameLibrary::permittedFolder(const QString &path) const {
    const QString canonical=QFileInfo(path).canonicalFilePath();
    if(canonical.isEmpty() || !QDir::isAbsolutePath(path))return false;
    const QStringList bases={m_home,"/media","/run/media","/mnt","/NeutronMedia","/srv/neutronos/user-data"};
    for(const auto &base:bases) {
        const auto resolved=QFileInfo(base).canonicalFilePath();
        if(!resolved.isEmpty() && inside(canonical,resolved))return true;
    }
    return false;
}
QVariantMap GameLibrary::browseFolders(const QString &path) const {
    QVariantList entries;
    if(path.isEmpty()) {
        QSet<QString> seen;
        auto add=[&](const QString &location,const QString &label,const QString &kind) {
            QString canonical=QFileInfo(location).canonicalFilePath();
            if(canonical.isEmpty()||seen.contains(canonical)||!permittedFolder(canonical))return;
            seen.insert(canonical);
            entries.append(QVariantMap{{"path",canonical},{"name",label},{"kind",kind},{"available",::access(QFile::encodeName(canonical).constData(),R_OK|X_OK)==0}});
        };
        add(m_home,"Home","home");
        for(const auto &volume:QStorageInfo::mountedVolumes()) {
            if(volume.isValid()&&volume.isReady())add(volume.rootPath(),volume.displayName().isEmpty()?volume.rootPath():volume.displayName(),"drive");
        }
        for(const auto &base:QStringList{"/media","/run/media","/mnt"}) {
            QDir dir(base);
            for(const auto &entry:dir.entryInfoList(QDir::Dirs|QDir::NoDotAndDotDot,QDir::Name))add(entry.absoluteFilePath(),entry.fileName(),"drive");
        }
        return {{"ok",true},{"path",""},{"parent",""},{"entries",entries}};
    }
    QFileInfo info(path);QString canonical=info.canonicalFilePath();
    if(!info.isDir() || canonical.isEmpty())return {{"ok",false},{"error","Folder is unavailable or no longer exists."}};
    if(!permittedFolder(path))return {{"ok",false},{"error","Choose a folder in Home or an authorized mounted volume."}};
    if(::access(QFile::encodeName(canonical).constData(),R_OK|X_OK)!=0)return {{"ok",false},{"error","Permission denied: this folder cannot be read and entered."}};
    QDir dir(canonical);
    for(const auto &entry:dir.entryInfoList(QDir::Dirs|QDir::NoDotAndDotDot,QDir::DirsFirst|QDir::Name|QDir::IgnoreCase)) {
        if(!permittedFolder(entry.absoluteFilePath()))continue;
        entries.append(QVariantMap{{"path",entry.canonicalFilePath()},{"name",entry.fileName()},{"kind","folder"},{"available",::access(QFile::encodeName(entry.absoluteFilePath()).constData(),R_OK|X_OK)==0}});
    }
    QString parent=QFileInfo(canonical).dir().absolutePath();
    if(!permittedFolder(parent))parent.clear();
    return {{"ok",true},{"path",canonical},{"parent",parent},{"entries",entries}};
}
bool GameLibrary::addRoot(const QString &path) {
    QFileInfo f(path);QString p=f.canonicalFilePath();
    if(!f.isDir()||p.isEmpty()||!permittedFolder(path)||::access(QFile::encodeName(p).constData(),R_OK|X_OK)!=0){emit error("Choose an existing, readable folder in Home or an authorized volume.");return false;}
    if(m_roots.contains(p)){emit error("This folder is already in the Games library.");return false;}
    for(const auto &root:m_roots) if(inside(p,root)||inside(root,p)){emit error("Overlapping library folders are already covered.");return false;}
    m_roots.append(p);if(!save()){m_roots.removeLast();return false;}observe();rescan(p);emit changed();return true;
}
bool GameLibrary::editRoot(int i,const QString &path){
    if(i<0||i>=m_roots.size())return false;
    const QString old=m_roots[i],p=QFileInfo(path).canonicalFilePath();
    if(old==p)return true;
    if(!permittedFolder(path)||!QFileInfo(p).isDir()||::access(QFile::encodeName(p).constData(),R_OK|X_OK)!=0){emit error("Choose an existing, readable folder in Home or an authorized volume.");return false;}
    for(int n=0;n<m_roots.size();++n)if(n!=i&&(inside(p,m_roots[n])||inside(m_roots[n],p))){emit error("This folder overlaps an existing Games library location.");return false;}
    const auto oldGames=m_games;
    m_roots[i]=p;
    for(auto &v:m_games){auto g=v.toMap();if(g.value("root")==old){g["managed"]=false;g["online"]=false;v=g;}}
    if(!save()){m_roots[i]=old;m_games=oldGames;return false;}
    observe();rescan(p);emit changed();return true;
}
bool GameLibrary::removeRoot(int i){if(i<0||i>=m_roots.size())return false;const auto previousRoots=m_roots;const auto previousGames=m_games;QString p=m_roots.takeAt(i);for(auto &v:m_games){auto g=v.toMap();if(g.value("root")==p){g["managed"]=false;g["online"]=false;v=g;}}if(!save()){m_roots=previousRoots;m_games=previousGames;return false;}m_pending.remove(p);emit changed();return true;}
void GameLibrary::setAutomatic(bool enabled){m_automatic=enabled;save();emit changed();}
void GameLibrary::setQuiescent(bool enabled){m_quiescent=enabled;if(enabled){m_presence.stop();m_debounce.stop();}else{m_presence.start();observe();if(!m_pending.isEmpty())m_debounce.start();}}
void GameLibrary::observe(){bool delta=false;for(auto &v:m_games){auto g=v.toMap();bool online=(m_roots.contains(g.value("root").toString())||g.contains("installation"))&&QFileInfo::exists(g.value("path").toString());if(g.value("online").toBool()!=online){g["online"]=online;v=g;delta=true;}}
    for(const auto &p:m_roots){if(QFileInfo(p).isDir()&&!m_watch.directories().contains(p)){m_watch.addPath(p);if(m_automatic)rescan(p);}}
    if(delta) {save();emit changed();}
}
QString GameLibrary::materialSignature(const QString &p){QFileInfo f(p);return hash(bytes(p)+QByteArray::number(f.size())+QByteArray::number(f.lastModified().toMSecsSinceEpoch()));}
QVariantMap GameLibrary::recognize(const QString &path){
    QFileInfo f(path);if(!f.isFile()||f.isSymLink())return {};
    QByteArray b=bytes(path);QString ext=f.suffix().toLower(),folder=f.absolutePath();
    if(ext=="exe")for(const auto &part:folder.split('/'))if(QStringList{"redist","redistributables","_commonredist"}.contains(part.toLower()))return {};
    QString kind,title=f.completeBaseName(),arch,confidence="high";QStringList candidates,evidence;
    quint32 gc=b.size()>32?quint32(quint8(b[28]))<<24|quint32(quint8(b[29]))<<16|quint32(quint8(b[30]))<<8|quint8(b[31]):0;
    quint32 wii=b.size()>28?quint32(quint8(b[24]))<<24|quint32(quint8(b[25]))<<16|quint32(quint8(b[26]))<<8|quint8(b[27]):0;
    if(f.fileName().startsWith("appmanifest_")&&ext=="acf"){
        QString s=QString::fromUtf8(b),id=vdf(s,"appid"),dir=vdf(s,"installdir");
        if(!QRegularExpression("^[0-9]+$").match(id).hasMatch()||dir.isEmpty()||dir.contains('/')||dir=="..")return {};
        kind="steam";title=vdf(s,"name");evidence<<"Steam appmanifest appid + install directory";
    } else if(b.startsWith("\x7f" "ELF")&&b.size()>20){
        bool le=quint8(b[5])==1;int machine=le?(quint8(b[18])|quint8(b[19])<<8):(quint8(b[18])<<8|quint8(b[19]));
        arch=machine==62?"amd64":machine==3?"i386":machine==183?"aarch64":"other";
        if(ext=="rpx"&&machine==20&&QDir(folder+"/../content").exists()){kind="wiiu";arch="ppc";evidence<<"PowerPC RPX + code/content structure";}
        else if(f.isExecutable()&&(machine==62||machine==3||machine==183)){kind="linux";confidence="likely";evidence<<"ELF machine + executable permission";}
        else return {};
    } else if(b.startsWith("MZ")&&b.size()>64){
        quint32 offset=quint8(b[60])|quint32(quint8(b[61]))<<8|quint32(quint8(b[62]))<<16|quint32(quint8(b[63]))<<24;
        QFile pe(path);QByteArray hdr;if(pe.open(QIODevice::ReadOnly)&&offset<quint64(f.size())&&pe.seek(offset))hdr=pe.read(6);
        if(!hdr.startsWith(QByteArray("PE\0\0",4))||hdr.size()<6)return {};
        int machine=quint8(hdr[4])|quint8(hdr[5])<<8;arch=machine==0x8664?"amd64":machine==0x14c?"i386":"other";kind="windows";confidence="likely";
        QString name=f.fileName().toLower();
        if((name=="t6mp.exe"||name=="t6sp.exe")&&(QFileInfo::exists(folder+"/zone")||QFileInfo::exists(folder+"/plutonium.exe"))){kind="plutonium";title="Plutonium T6 — "+title;evidence<<"T6 executable + zone/launcher structure";}
        if(name.contains("farcry6")||name=="ubisoftconnect.exe"||QFileInfo::exists(folder+"/uplay_r1_loader64.dll")){kind="ubisoft";evidence<<"Ubisoft executable/loader evidence";}
        evidence<<"MZ + PE machine header (Windows executable; may be a utility)";
    } else if(gc==0xc2339f3d||wii==0x5d1c9ea3){kind=gc==0xc2339f3d?"gamecube":"wii";evidence<<"Disc system magic";}
    else if(b.startsWith(QByteArray::fromHex("80371240"))||b.startsWith(QByteArray::fromHex("37804012"))||b.startsWith(QByteArray::fromHex("40123780"))){kind="n64";evidence<<"N64 cartridge header + byte order";}
    else if(b.size()>0x8006&&b.mid(0x8001,5)=="CD001"){
        QFile iso(path);QByteArray region;if(iso.open(QIODevice::ReadOnly)&&iso.seek(0x8000))region=iso.read(1024*1024);
        if(region.contains("PSP_GAME")){kind="psp";evidence<<"ISO9660 volume + PSP_GAME entry";}
        else {kind="ambiguous";confidence="ambiguous";candidates<<"ps1"<<"ps2"<<"pc-disc";evidence<<"ISO9660 disc; console identity unknown";}
    } else if(ext=="apk"&&b.startsWith("PK")){
        QFile zip(path);QByteArray tail;if(zip.open(QIODevice::ReadOnly)){zip.seek(qMax<qint64>(0,f.size()-65536));tail=zip.readAll();}
        if(!b.startsWith(QByteArray::fromHex("504b0304"))||!tail.contains(QByteArray::fromHex("504b0506"))||!tail.contains(QByteArray::fromHex("504b0102"))||!tail.contains("AndroidManifest.xml"))return {};
        kind="android";evidence<<"ZIP + AndroidManifest.xml";
    } else if((ext=="swf")&&(b.startsWith("FWS")||b.startsWith("CWS")||b.startsWith("ZWS"))){kind="flash";evidence<<"SWF format header";}
    else if(ext=="nes"&&b.startsWith(QByteArray("NES\x1a",4))){kind="nes";evidence<<"iNES header";}
    else if((ext=="gb"||ext=="gbc")&&b.size()>0x134&&b.mid(0x104,4)==QByteArray::fromHex("ceed6666")){kind="gameboy";evidence<<"Cartridge logo header";}
    else if(ext=="cue"&&QString::fromUtf8(b).contains(QRegularExpression("FILE\\s+\"[^\"]+\"\\s+BINARY",QRegularExpression::CaseInsensitiveOption))){kind="ambiguous";confidence="ambiguous";candidates<<"ps1"<<"saturn"<<"pc-disc";evidence<<"Cue sheet; select console";}
    else if(ext=="json"&&f.fileName().endsWith(".game.json")){
        auto obj=QJsonDocument::fromJson(b).object();QString provider=obj.value("provider").toString();
        if(provider=="cloud"||provider=="remote"){QUrl u(obj.value("url").toString());if(provider=="cloud"&&(u.scheme()!="https"||u.host().isEmpty()))return {};if(provider=="remote"&&obj.value("client").toString()!="moonlight")return {};kind=provider;title=obj.value("title").toString(title);evidence<<"Explicit user streaming descriptor";}
        else return {};
    } else if(ext=="iso"&&b.size()>0x9006&&b.mid(0x8001,5)=="BEA01"&&
              (b.mid(0x8801,5)=="NSR02"||b.mid(0x8801,5)=="NSR03")&&b.mid(0x9001,5)=="TEA01") {
        kind="archive";confidence="container";evidence<<"Disc volume descriptors BEA01/NSR/TEA01; contents and platform unverified; authorized mount/extraction required";
    } else if((ext=="7z"&&b.size()>=32&&b.startsWith(QByteArray::fromHex("377abcaf271c"))) ||
              (ext=="zip"&&b.size()>=22&&(b.startsWith(QByteArray::fromHex("504b0304"))||b.startsWith(QByteArray::fromHex("504b0506"))))){
        kind="archive";confidence="container";evidence<<"Archive extension and container magic; game data/platform not verified; extraction/setup required";
    } else if(ext=="sfc"||ext=="smc"||ext=="gba"||ext=="chd"||ext=="pbp"){kind="ambiguous";confidence="ambiguous";candidates<<"snes"<<"gba"<<"ps1"<<"retroarch";evidence<<"Container/extension hint only; user decision required";}
    else return {};
    QString canonical=f.canonicalFilePath();QString id=hash(canonical.toUtf8());
    auto side=QJsonDocument::fromJson(bytes(path+".metadata.json")).object();
    QString artwork;
    for(const QString &name:{f.completeBaseName()+".jpg",f.completeBaseName()+".png",QString("cover.jpg"),QString("cover.png")}){QString a=folder+"/"+name;if(QFileInfo(a).isFile()){artwork=QUrl::fromLocalFile(a).toString();break;}}
    QVariantMap out{{"id",id},{"path",canonical},{"title",side.value("title").toString(title)},{"kind",kind},{"architecture",arch},{"confidence",confidence},{"candidates",candidates},{"evidence",evidence},{"artwork",artwork},{"signature",materialSignature(path)},{"contentSignature",hash(b+QByteArray::number(f.size()))},{"size",f.size()},{"online",true},{"managed",true}};
    if(kind=="steam"){QString s=QString::fromUtf8(b);out["steamId"]=vdf(s,"appid");out["installDirectory"]=folder+"/common/"+vdf(s,"installdir");out["online"]=QDir(out["installDirectory"].toString()).exists();}
    if(kind=="archive"){out["archiveFormat"]=ext=="iso"?"udf-disc":ext;out["requiresExtraction"]=true;}
    if(kind=="cloud"||kind=="remote"){auto o=QJsonDocument::fromJson(b).object();out["url"]=o.value("url").toString();out["host"]=o.value("host").toString();out["remoteApp"]=o.value("app").toString();}
    if(kind=="wiiu"){out["updatePresent"]=QDir(folder+"/../../update").exists();out["dlcPresent"]=QDir(folder+"/../../dlc").exists();}
    return out;
}
GameLibrary::ScanResult GameLibrary::scan(const QString &root){ScanResult result;result.target=root;
    if(!QFileInfo(root).isDir()){result.complete=false;return result;}
    result.directories<<root;
    QDirIterator it(root,QDir::AllEntries|QDir::NoDotAndDotDot|QDir::NoSymLinks,QDirIterator::Subdirectories);
    int count=0;while(it.hasNext()) {QString p=it.next();auto f=it.fileInfo();if(++count>200000){result.complete=false;break;}
        if(f.isDir()){if(result.directories.size()<8000)result.directories<<p;continue;}
        const QString e=f.suffix().toLower();
        if(!f.isExecutable()&&!QStringList{"exe","acf","rpx","iso","gcm","n64","z64","v64","apk","swf","nes","gb","gbc","cue","sfc","smc","gba","chd","pbp","zip","7z","json","x86_64","bin"}.contains(e))continue;
        auto g=recognize(p);if(!g.isEmpty())result.entries.append(g);
    }return result;
}
void GameLibrary::rescan(const QString &target){if(m_destroying)return;QString p=QDir::cleanPath(target);if(target.isEmpty()){for(const auto &root:m_roots)m_pending.insert(root);}else for(const auto &root:m_roots)if(inside(p,root)){m_pending.insert(p);break;}
    // Coalesce child changes beneath an already queued ancestor.
    const auto pending=m_pending.values();for(const auto &a:pending)for(const auto &b:pending)if(a!=b&&inside(b,a))m_pending.remove(b);
    if(!m_quiescent)m_debounce.start();
}
void GameLibrary::next(){if(m_quiescent||m_scan.isRunning()||m_pending.isEmpty())return;QString p=*m_pending.begin();m_pending.remove(p);m_scan.setFuture(QtConcurrent::run([p]{return scan(p);}));emit changed();}
void GameLibrary::merge(){auto result=m_scan.result();QString owner;for(const auto &root:m_roots)if(inside(result.target,root)){owner=root;break;}
    if(!owner.isEmpty()){
        QSet<QString> seen;
        for(auto value:result.entries){auto entry=value.toMap();QString id=entry.value("id").toString();seen.insert(id);entry["root"]=owner;
            int found=-1;for(int i=0;i<m_games.size();i++)if((m_games[i].toMap().value("id")==id||m_games[i].toMap().value("path")==entry.value("path"))){found=i;break;}
            if(found>=0){auto old=m_games[found].toMap();if(old.contains("installation")){entry["id"]=old.value("id");seen.insert(old.value("id").toString());entry["root"]=old.value("root");}for(const QString &k:{QString("favorite"),QString("lastPlayed"),QString("playCount"),QString("configuration"),QString("chosenKind"),QString("controllerProfile"),QString("titleOverride"),QString("artworkOverride"),QString("installation"),QString("installationPending")})if(old.contains(k))entry[k]=old[k];m_games[found]=entry;}
            else m_games.append(entry);
            QString p=entry.value("path").toString();if(!m_watch.files().contains(p)&&m_watch.files().size()<8000)m_watch.addPath(p);
        }
        for(auto &v:m_games){auto g=v.toMap();if(inside(g.value("path").toString(),result.target)&&!seen.contains(g.value("id").toString())&&(result.complete||!QFileInfo(result.target).isDir())){g["online"]=false;v=g;}}
        if(!result.complete)emit error("Scan incomplete or storage unavailable; existing entries retained.");
        for(const auto &p:result.directories)if(!m_watch.directories().contains(p))m_watch.addPath(p);
        QHash<QString,QStringList> duplicates;for(const auto &v:m_games){auto g=v.toMap();duplicates[g.value("contentSignature").toString()].append(g.value("id").toString());}
        for(auto &v:m_games){auto g=v.toMap();auto ids=duplicates.value(g.value("contentSignature").toString());ids.removeAll(g.value("id").toString());g["possibleDuplicates"]=ids;v=g;}
        save();
    }emit changed();next();
}
QVariantMap GameLibrary::find(const QString &id)const{for(const auto &v:m_games)if(v.toMap().value("id")==id)return v.toMap();return {};}
bool GameLibrary::update(const QString &id,const QVariantMap &metadata){static const QStringList permitted={"favorite","lastPlayed","playCount","configuration","chosenKind","controllerProfile","titleOverride","artworkOverride"};for(auto &v:m_games){auto g=v.toMap();if(g.value("id")!=id)continue;for(auto it=metadata.begin();it!=metadata.end();++it)if(permitted.contains(it.key()))g[it.key()]=it.value();v=g;bool ok=save();emit changed();return ok;}return false;}
bool GameLibrary::save(){QSaveFile f(m_state+"/library.json");if(!f.open(QIODevice::WriteOnly)){emit error("Unable to persist library: "+f.errorString());return false;}f.write(QJsonDocument(QJsonObject{{"schema",1},{"roots",QJsonArray::fromStringList(m_roots)},{"games",QJsonArray::fromVariantList(m_games)},{"automatic",m_automatic}}).toJson());if(!f.commit()){emit error("Library save failed: "+f.errorString());return false;}return true;}
bool GameLibrary::registerInstallation(const QVariantMap &record){
    const QString id=record.value("id").toString(),path=record.value("path").toString(),root=record.value("root").toString();
    if(!QRegularExpression("^[a-f0-9]{64}$").match(id).hasMatch()||!permittedFolder(root)||!permittedFolder(path))return false;
    auto game=find(id);auto configuration=record.value("configuration").toMap();configuration["signature"]=materialSignature(path);
    game.insert("id",id);game.insert("path",path);game.insert("root",root);game.insert("title",record.value("title"));game.insert("kind",record.value("kind"));game.insert("architecture",record.value("architecture"));game.insert("configuration",configuration);game.insert("signature",configuration.value("signature"));game.insert("managed",true);game.insert("online",QFileInfo(path).isFile());game.insert("confidence","User-selected installation");game.insert("installation",record);game.insert("installationPending",record.value("status")!="ready");
    const auto previous=m_games;bool replaced=false;for(auto &v:m_games)if(v.toMap().value("id")==id){v=game;replaced=true;break;}if(!replaced)m_games.append(game);
    if(!save()){m_games=previous;return false;}emit changed();return true;
}
bool GameLibrary::retireInstallation(const QString &id){const auto previous=m_games;for(int i=m_games.size()-1;i>=0;--i)if(m_games[i].toMap().value("id")==id&&m_games[i].toMap().contains("installation"))m_games.removeAt(i);if(!save()){m_games=previous;return false;}emit changed();return true;}

}
