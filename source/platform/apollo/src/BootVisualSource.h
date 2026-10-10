#pragma once

#include <QImage>
#include <QString>

class BootVisualSource final
{
public:
    explicit BootVisualSource(QString archivePath = {});

    static QString defaultArchivePath();
    static QString expectedArchiveSha256();
    static bool isProgressPercent(int percent);
    static QString progressEntryName(int percent);
    static QString specialEntryName(const QString &name);

    bool validateArchive(QString *error = nullptr) const;
    QImage progressFrame(int percent, QString *error = nullptr) const;
    QImage composedProgressFrame(int percent, const QSize &targetSize,
                                 QString *error = nullptr) const;
    QImage specialFrame(const QString &name, QString *error = nullptr) const;
    QImage composedSpecialFrame(const QString &name, const QSize &targetSize,
                                QString *error = nullptr) const;

    QString archivePath() const;

private:
    QImage imageFromEntry(const QString &entry, QString *error) const;

    QString m_archivePath;
};
