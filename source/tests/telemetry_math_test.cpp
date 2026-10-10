#include "TelemetryMath.h"

#include <QCoreApplication>
#include <QtMath>

namespace {
int failures = 0;
void check(bool value) { if (!value) ++failures; }
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    bool valid = false;
    check(TelemetryMath::cpuPercent(100, 80, 200, 130, &valid) == 50 && valid);
    check(TelemetryMath::cpuPercent(100, 80, 100, 80, &valid) == 0 && !valid);
    check(TelemetryMath::memoryUsedBytes(8ULL << 30, 3ULL << 30) == (5ULL << 30));
    check(TelemetryMath::utilizationPercent(1000, 250) == 25);
    check(TelemetryMath::utilizationPercent(0, 250) == 0);
    auto rate = TelemetryMath::byteRate(1000, 5000, 2000);
    check(rate.valid && rate.bytesPerSecond == 2000);
    check(!TelemetryMath::byteRate(5000, 10, 2000).valid);
    check(!TelemetryMath::byteRate(1000, 5000, 2000, false).valid);
    check(TelemetryMath::validCelsius(55.0));
    check(!TelemetryMath::validCelsius(500.0));
    check(qAbs(TelemetryMath::fahrenheitFromCelsius(100.0) - 212.0) < 0.001);
    check(TelemetryMath::activeRaspberryPiThrottle(0x1));
    check(TelemetryMath::activeRaspberryPiThrottle(0x8));
    check(!TelemetryMath::activeRaspberryPiThrottle(0x10000));
    check(!TelemetryMath::activeRaspberryPiThrottle(0x80000));
    check(TelemetryMath::formatUptime(93780) == QStringLiteral("1d 2h 3m"));
    return failures == 0 ? 0 : 1;
}
