#pragma once

#include <QImage>
#include <QString>

class FramebufferWriter final
{
public:
    struct Geometry {
        int width = 0;
        int height = 0;
        int bitsPerPixel = 0;
        int lineLength = 0;
        quint32 redOffset = 0;
        quint32 redLength = 0;
        quint32 greenOffset = 0;
        quint32 greenLength = 0;
        quint32 blueOffset = 0;
        quint32 blueLength = 0;
        quint32 transparencyOffset = 0;
        quint32 transparencyLength = 0;

        bool operator==(const Geometry &other) const;
        bool operator!=(const Geometry &other) const { return !(*this == other); }
        bool isValid() const;
        QString description() const;
    };

    explicit FramebufferWriter(QString device = QStringLiteral("/dev/fb0"));

    Geometry probe(QString *error = nullptr) const;
    bool write(const QImage &nativeSizeImage, Geometry *geometry = nullptr,
               QString *error = nullptr) const;

private:
    QString m_device;
};
