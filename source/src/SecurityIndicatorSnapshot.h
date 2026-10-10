#pragma once
#include <QDateTime>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cmath>

// Read-only presentation of securityd's existing protected snapshot. No
// authentication, scoring, enforcement, or privileged state is implemented here.
struct SecurityIndicatorSnapshot {
    bool online=false;
    int score=-1;
    static SecurityIndicatorSnapshot parse(const QByteArray &data,const QDateTime &now){
        const auto state=QJsonDocument::fromJson(data).object();
        const auto heartbeat=QDateTime::fromString(state.value("heartbeat").toString(),Qt::ISODate);
        const auto value=state.value("securityScore");const double score=value.toDouble(-1);
        // securityd publishes a heartbeat every five seconds. An old file is
        // never evidence of a live service, including across reboot/logout.
        if(!heartbeat.isValid()||heartbeat.msecsTo(now)<0||heartbeat.msecsTo(now)>20000||
           !value.isDouble()||!std::isfinite(score)||score<0||score>100)return {};
        return {true,qRound(score)};
    }
    static SecurityIndicatorSnapshot read(const QString &path,const QDateTime &now){
        const int fd=::open(QFile::encodeName(path).constData(),O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        if(fd<0)return {};
        struct stat info{};
        if(fstat(fd,&info)!=0||!S_ISREG(info.st_mode)||info.st_uid!=0||(info.st_mode&0022)||info.st_size>1024*1024){::close(fd);return {};}
        QFile file;if(!file.open(fd,QIODevice::ReadOnly,QFileDevice::AutoCloseHandle)){::close(fd);return {};}
        return parse(file.read(1024*1024),now);
    }
};
