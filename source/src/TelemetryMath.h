#pragma once

#include <QtGlobal>
#include <QtMath>
#include <QString>

namespace TelemetryMath {

struct RateSample { quint64 bytesPerSecond = 0; bool valid = false; };

inline int cpuPercent(quint64 previousTotal, quint64 previousIdle,
                      quint64 currentTotal, quint64 currentIdle, bool *valid = nullptr)
{
    const bool ok = currentTotal > previousTotal && currentIdle >= previousIdle;
    if (valid) *valid = ok;
    if (!ok) return 0;
    const quint64 totalDelta = currentTotal - previousTotal;
    const quint64 idleDelta = qMin(totalDelta, currentIdle - previousIdle);
    return qBound(0, qRound(100.0 * double(totalDelta - idleDelta) / double(totalDelta)), 100);
}

inline quint64 memoryUsedBytes(quint64 totalBytes, quint64 availableBytes)
{
    return availableBytes >= totalBytes ? 0 : totalBytes - availableBytes;
}

inline int utilizationPercent(quint64 totalBytes, quint64 usedBytes)
{
    return totalBytes == 0 ? 0 : qBound(0, qRound(100.0 * double(qMin(totalBytes, usedBytes)) / double(totalBytes)), 100);
}

inline RateSample byteRate(quint64 previousBytes, quint64 currentBytes, qint64 elapsedMs,
                           bool sameSource = true)
{
    if (!sameSource || previousBytes == 0 || currentBytes < previousBytes || elapsedMs <= 0)
        return {};
    return {quint64(double(currentBytes - previousBytes) * 1000.0 / double(elapsedMs)), true};
}

inline bool validCelsius(double value) { return value > -40.0 && value < 160.0; }
inline double fahrenheitFromCelsius(double value) { return value * 9.0 / 5.0 + 32.0; }
inline bool activeRaspberryPiThrottle(quint32 flags) { return (flags & 0x0Fu) != 0; }

inline QString formatUptime(quint64 seconds)
{
    const quint64 days = seconds / 86400; seconds %= 86400;
    const quint64 hours = seconds / 3600; seconds %= 3600;
    const quint64 minutes = seconds / 60;
    if (days) return QStringLiteral("%1d %2h %3m").arg(days).arg(hours).arg(minutes);
    if (hours) return QStringLiteral("%1h %2m").arg(hours).arg(minutes);
    return QStringLiteral("%1m").arg(minutes);
}
}
