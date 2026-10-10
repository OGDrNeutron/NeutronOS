#pragma once

#include "BootVisualSource.h"

#include <QQuickImageProvider>

class BootImageProvider final : public QQuickImageProvider
{
public:
    explicit BootImageProvider(QString archivePath = {});

    QImage requestImage(const QString &id, QSize *size,
                        const QSize &requestedSize) override;
    bool validate(QString *error = nullptr) const;

private:
    BootVisualSource m_source;
};
