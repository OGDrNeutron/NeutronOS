#include "BootImageProvider.h"

BootImageProvider::BootImageProvider(QString archivePath)
    : QQuickImageProvider(QQuickImageProvider::Image),
      m_source(std::move(archivePath))
{
}

QImage BootImageProvider::requestImage(const QString &id, QSize *size,
                                       const QSize &requestedSize)
{
    bool validPercent = false;
    const int percent = id.section(QLatin1Char('/'), 0, 0).toInt(&validPercent);
    const QSize target = requestedSize.isValid() ? requestedSize : QSize(1920, 1080);
    QString error;
    QImage image;
    if (validPercent) {
        image = m_source.composedProgressFrame(percent, target, &error);
    } else {
        const QString special = id.section(QLatin1Char('/'), 0, 0).trimmed().toLower();
        image = m_source.composedSpecialFrame(special, target, &error);
    }
    if (size)
        *size = image.size();
    return image;
}

bool BootImageProvider::validate(QString *error) const
{
    return m_source.validateArchive(error);
}
