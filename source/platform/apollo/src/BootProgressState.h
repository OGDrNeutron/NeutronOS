#pragma once

#include <QString>

class BootProgressState final
{
public:
    explicit BootProgressState(QString stateDirectory = {});

    static QString defaultStateDirectory();

    bool begin(QString *error = nullptr) const;
    bool advance(int percent, const QString &milestone,
                 QString *error = nullptr) const;
    int progress() const;

    bool writeMarker(const QString &name, const QByteArray &content,
                     QString *error = nullptr) const;
    bool hasMarker(const QString &name) const;
    bool removeMarker(const QString &name) const;

    QString stateDirectory() const;
    QString markerPath(const QString &name) const;

private:
    bool ensureDirectory(QString *error) const;
    bool appendEvent(int percent, const QString &milestone,
                     QString *error) const;

    QString m_stateDirectory;
};
