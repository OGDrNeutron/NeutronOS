#include "BootVisualSource.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QFile>
#include <QImageReader>
#include <QPainter>
#include <QProcess>

namespace {
constexpr auto kApprovedArchiveSha256 =
    "53185c65cd9792a91acba1bc22ffacf2cd42f43aeb5a6b2773bf9ef30350264f";
constexpr auto kDefaultArchive = "/home/echo/NeutronOS/design-reference/Boot.zip";
constexpr auto kUnzip = "/usr/bin/unzip";
constexpr int kSourceWidth = 1920;
constexpr int kSourceHeight = 1080;

void setError(QString *destination, const QString &message)
{
    if (destination)
        *destination = message;
}
}

BootVisualSource::BootVisualSource(QString archivePath)
    : m_archivePath(archivePath.trimmed().isEmpty()
                        ? defaultArchivePath()
                        : std::move(archivePath))
{
}

QString BootVisualSource::defaultArchivePath()
{
    const QString configured = qEnvironmentVariable("NEUTRONOS_BOOT_ZIP").trimmed();
    return configured.isEmpty() ? QString::fromLatin1(kDefaultArchive) : configured;
}

QString BootVisualSource::expectedArchiveSha256()
{
    return QString::fromLatin1(kApprovedArchiveSha256);
}

bool BootVisualSource::isProgressPercent(int percent)
{
    return percent >= 0 && percent <= 100 && percent % 5 == 0;
}

QString BootVisualSource::progressEntryName(int percent)
{
    if (!isProgressPercent(percent))
        return {};
    return QStringLiteral("AbootNew_fixed/neutronos_progress_%1.png")
        .arg(percent, 3, 10, QLatin1Char('0'));
}

QString BootVisualSource::specialEntryName(const QString &name)
{
    const QString normalized = name.trimmed().toLower();
    if (normalized != QStringLiteral("reboot") &&
        normalized != QStringLiteral("shutdown"))
        return {};
    return QStringLiteral("AbootNew_fixed/neutronos_%1.png").arg(normalized);
}

bool BootVisualSource::validateArchive(QString *error) const
{
    QFile archive(m_archivePath);
    if (!archive.open(QIODevice::ReadOnly)) {
        setError(error, QStringLiteral("cannot open approved Boot.zip: %1")
                            .arg(archive.errorString()));
        return false;
    }

    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&archive)) {
        setError(error, QStringLiteral("cannot hash approved Boot.zip"));
        return false;
    }

    const QString actual = QString::fromLatin1(hash.result().toHex());
    if (actual != expectedArchiveSha256()) {
        setError(error, QStringLiteral("approved Boot.zip SHA-256 mismatch: %1")
                            .arg(actual));
        return false;
    }
    return true;
}

QImage BootVisualSource::imageFromEntry(const QString &entry, QString *error) const
{
    if (entry.isEmpty()) {
        setError(error, QStringLiteral("unsupported boot frame"));
        return {};
    }

    QProcess unzip;
    unzip.setProgram(QString::fromLatin1(kUnzip));
    unzip.setArguments({QStringLiteral("-p"), m_archivePath, entry});
    unzip.start(QIODevice::ReadOnly);
    if (!unzip.waitForStarted(3000)) {
        setError(error, QStringLiteral("could not start unzip for %1").arg(entry));
        return {};
    }
    if (!unzip.waitForFinished(15000)) {
        unzip.kill();
        unzip.waitForFinished();
        setError(error, QStringLiteral("timed out reading %1 from Boot.zip").arg(entry));
        return {};
    }
    if (unzip.exitStatus() != QProcess::NormalExit || unzip.exitCode() != 0) {
        setError(error, QStringLiteral("unzip rejected %1: %2")
                            .arg(entry, QString::fromLocal8Bit(unzip.readAllStandardError()).trimmed()));
        return {};
    }

    const QByteArray encoded = unzip.readAllStandardOutput();
    QBuffer buffer;
    buffer.setData(encoded);
    if (!buffer.open(QIODevice::ReadOnly)) {
        setError(error, QStringLiteral("could not buffer %1").arg(entry));
        return {};
    }

    QImageReader reader(&buffer, "png");
    reader.setAutoTransform(false);
    QImage image = reader.read();
    if (image.isNull()) {
        setError(error, QStringLiteral("could not decode %1: %2")
                            .arg(entry, reader.errorString()));
        return {};
    }
    if (image.size() != QSize(kSourceWidth, kSourceHeight)) {
        setError(error, QStringLiteral("unexpected dimensions for %1: %2x%3")
                            .arg(entry)
                            .arg(image.width())
                            .arg(image.height()));
        return {};
    }
    return image;
}

QImage BootVisualSource::progressFrame(int percent, QString *error) const
{
    return imageFromEntry(progressEntryName(percent), error);
}

QImage BootVisualSource::specialFrame(const QString &name, QString *error) const
{
    return imageFromEntry(specialEntryName(name), error);
}

QImage BootVisualSource::composedProgressFrame(int percent, const QSize &targetSize,
                                               QString *error) const
{
    if (targetSize.width() <= 0 || targetSize.height() <= 0 ||
        targetSize.width() > 16384 || targetSize.height() > 16384) {
        setError(error, QStringLiteral("invalid output geometry %1x%2")
                            .arg(targetSize.width())
                            .arg(targetSize.height()));
        return {};
    }

    const QImage source = progressFrame(percent, error);
    if (source.isNull())
        return {};

    const QImage scaled = source.scaled(targetSize, Qt::KeepAspectRatio,
                                        Qt::SmoothTransformation);
    QImage canvas(targetSize, QImage::Format_RGB32);
    if (canvas.isNull()) {
        setError(error, QStringLiteral("could not allocate output canvas"));
        return {};
    }
    canvas.fill(Qt::black);

    QPainter painter(&canvas);
    painter.setCompositionMode(QPainter::CompositionMode_Source);
    painter.drawImage((targetSize.width() - scaled.width()) / 2,
                      (targetSize.height() - scaled.height()) / 2,
                      scaled);
    painter.end();
    return canvas;
}

QImage BootVisualSource::composedSpecialFrame(const QString &name,
                                                 const QSize &targetSize,
                                                 QString *error) const
{
    if (targetSize.width() <= 0 || targetSize.height() <= 0 ||
        targetSize.width() > 16384 || targetSize.height() > 16384) {
        setError(error, QStringLiteral("invalid output geometry %1x%2")
                            .arg(targetSize.width())
                            .arg(targetSize.height()));
        return {};
    }

    const QImage source = specialFrame(name, error);
    if (source.isNull())
        return {};

    const QImage scaled = source.scaled(targetSize, Qt::KeepAspectRatio,
                                        Qt::SmoothTransformation);
    QImage canvas(targetSize, QImage::Format_RGB32);
    if (canvas.isNull()) {
        setError(error, QStringLiteral("could not allocate output canvas"));
        return {};
    }
    canvas.fill(Qt::black);

    QPainter painter(&canvas);
    painter.setCompositionMode(QPainter::CompositionMode_Source);
    painter.drawImage((targetSize.width() - scaled.width()) / 2,
                      (targetSize.height() - scaled.height()) / 2,
                      scaled);
    painter.end();
    return canvas;
}

QString BootVisualSource::archivePath() const
{
    return m_archivePath;
}
