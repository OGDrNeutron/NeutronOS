#include "FramebufferWriter.h"

#include <QFile>

#ifdef Q_OS_LINUX
#include <fcntl.h>
#include <linux/fb.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

#include <cstring>

namespace {
void setError(QString *destination, const QString &message)
{
    if (destination)
        *destination = message;
}

quint32 scaleChannel(quint32 value, quint32 length)
{
    if (length == 0)
        return 0;
    const quint32 maximum = length >= 31 ? 0x7fffffffU : ((1U << length) - 1U);
    return (value * maximum + 127U) / 255U;
}
}

bool FramebufferWriter::Geometry::operator==(const Geometry &other) const
{
    return width == other.width && height == other.height &&
           bitsPerPixel == other.bitsPerPixel && lineLength == other.lineLength &&
           redOffset == other.redOffset && redLength == other.redLength &&
           greenOffset == other.greenOffset && greenLength == other.greenLength &&
           blueOffset == other.blueOffset && blueLength == other.blueLength &&
           transparencyOffset == other.transparencyOffset &&
           transparencyLength == other.transparencyLength;
}

bool FramebufferWriter::Geometry::isValid() const
{
    return width > 0 && height > 0 && lineLength > 0 &&
           (bitsPerPixel == 16 || bitsPerPixel == 24 || bitsPerPixel == 32);
}

QString FramebufferWriter::Geometry::description() const
{
    return QStringLiteral("%1x%2 %3bpp stride=%4 rgb=%5/%6,%7/%8,%9/%10")
        .arg(width).arg(height).arg(bitsPerPixel).arg(lineLength)
        .arg(redOffset).arg(redLength)
        .arg(greenOffset).arg(greenLength)
        .arg(blueOffset).arg(blueLength);
}

FramebufferWriter::FramebufferWriter(QString device)
    : m_device(std::move(device))
{
}

FramebufferWriter::Geometry FramebufferWriter::probe(QString *error) const
{
    Geometry geometry;
#ifdef Q_OS_LINUX
    const QByteArray device = QFile::encodeName(m_device);
    const int fd = ::open(device.constData(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        setError(error, QStringLiteral("cannot open %1").arg(m_device));
        return geometry;
    }

    fb_var_screeninfo variable{};
    fb_fix_screeninfo fixed{};
    if (::ioctl(fd, FBIOGET_VSCREENINFO, &variable) != 0 ||
        ::ioctl(fd, FBIOGET_FSCREENINFO, &fixed) != 0) {
        ::close(fd);
        setError(error, QStringLiteral("cannot query %1 geometry").arg(m_device));
        return geometry;
    }
    ::close(fd);

    geometry.width = static_cast<int>(variable.xres);
    geometry.height = static_cast<int>(variable.yres);
    geometry.bitsPerPixel = static_cast<int>(variable.bits_per_pixel);
    geometry.lineLength = static_cast<int>(fixed.line_length);
    geometry.redOffset = variable.red.offset;
    geometry.redLength = variable.red.length;
    geometry.greenOffset = variable.green.offset;
    geometry.greenLength = variable.green.length;
    geometry.blueOffset = variable.blue.offset;
    geometry.blueLength = variable.blue.length;
    geometry.transparencyOffset = variable.transp.offset;
    geometry.transparencyLength = variable.transp.length;
    if (!geometry.isValid()) {
        setError(error, QStringLiteral("unsupported %1 geometry: %2")
                            .arg(m_device, geometry.description()));
        return {};
    }
#else
    setError(error, QStringLiteral("framebuffer output is supported only on Linux"));
#endif
    return geometry;
}

bool FramebufferWriter::write(const QImage &nativeSizeImage, Geometry *outputGeometry,
                              QString *error) const
{
#ifdef Q_OS_LINUX
    const QByteArray device = QFile::encodeName(m_device);
    const int fd = ::open(device.constData(), O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        setError(error, QStringLiteral("cannot open %1 for output").arg(m_device));
        return false;
    }

    fb_var_screeninfo variable{};
    fb_fix_screeninfo fixed{};
    if (::ioctl(fd, FBIOGET_VSCREENINFO, &variable) != 0 ||
        ::ioctl(fd, FBIOGET_FSCREENINFO, &fixed) != 0) {
        ::close(fd);
        setError(error, QStringLiteral("cannot query %1 for output").arg(m_device));
        return false;
    }

    Geometry geometry;
    geometry.width = static_cast<int>(variable.xres);
    geometry.height = static_cast<int>(variable.yres);
    geometry.bitsPerPixel = static_cast<int>(variable.bits_per_pixel);
    geometry.lineLength = static_cast<int>(fixed.line_length);
    geometry.redOffset = variable.red.offset;
    geometry.redLength = variable.red.length;
    geometry.greenOffset = variable.green.offset;
    geometry.greenLength = variable.green.length;
    geometry.blueOffset = variable.blue.offset;
    geometry.blueLength = variable.blue.length;
    geometry.transparencyOffset = variable.transp.offset;
    geometry.transparencyLength = variable.transp.length;
    if (!geometry.isValid() || nativeSizeImage.size() != QSize(geometry.width, geometry.height)) {
        ::close(fd);
        setError(error, QStringLiteral("frame/image geometry mismatch: %1 versus %2x%3")
                            .arg(geometry.description())
                            .arg(nativeSizeImage.width())
                            .arg(nativeSizeImage.height()));
        return false;
    }

    const size_t mapLength = static_cast<size_t>(fixed.smem_len);
    const size_t startOffset =
        static_cast<size_t>(variable.yoffset) * fixed.line_length +
        static_cast<size_t>(variable.xoffset) * variable.bits_per_pixel / 8U;
    const size_t requiredLength = startOffset +
        static_cast<size_t>(geometry.height - 1) * fixed.line_length +
        static_cast<size_t>(geometry.width) * geometry.bitsPerPixel / 8U;
    if (requiredLength > mapLength) {
        ::close(fd);
        setError(error, QStringLiteral("%1 framebuffer memory is smaller than its geometry")
                            .arg(m_device));
        return false;
    }
    void *mapping = ::mmap(nullptr, mapLength, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapping == MAP_FAILED) {
        ::close(fd);
        setError(error, QStringLiteral("cannot map %1").arg(m_device));
        return false;
    }

    const QImage source = nativeSizeImage.convertToFormat(QImage::Format_RGB32);
    auto *base = static_cast<uchar *>(mapping) + startOffset;
    const int bytesPerPixel = geometry.bitsPerPixel / 8;
    for (int y = 0; y < geometry.height; ++y) {
        const QRgb *input = reinterpret_cast<const QRgb *>(source.constScanLine(y));
        uchar *output = base + static_cast<size_t>(y) * fixed.line_length;
        for (int x = 0; x < geometry.width; ++x) {
            quint32 value =
                (scaleChannel(qRed(input[x]), geometry.redLength) << geometry.redOffset) |
                (scaleChannel(qGreen(input[x]), geometry.greenLength) << geometry.greenOffset) |
                (scaleChannel(qBlue(input[x]), geometry.blueLength) << geometry.blueOffset);
            if (geometry.transparencyLength)
                value |= scaleChannel(255, geometry.transparencyLength)
                         << geometry.transparencyOffset;
            std::memcpy(output + static_cast<size_t>(x) * bytesPerPixel,
                        &value, static_cast<size_t>(bytesPerPixel));
        }
    }
    ::msync(mapping, mapLength, MS_ASYNC);
    ::munmap(mapping, mapLength);
    ::close(fd);
    if (outputGeometry)
        *outputGeometry = geometry;
    return true;
#else
    Q_UNUSED(nativeSizeImage)
    Q_UNUSED(outputGeometry)
    setError(error, QStringLiteral("framebuffer output is supported only on Linux"));
    return false;
#endif
}
