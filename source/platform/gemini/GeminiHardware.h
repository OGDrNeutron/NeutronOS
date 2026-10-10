#pragma once

#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QString>
#include <QtGlobal>
#include <cmath>

// Linux interfaces used by Gemini. The optional sysfs root permits offline
// inspection against a captured tree; production callers use the real /sys.
namespace GeminiHardware {
inline QString readText(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()).trimmed() : QString();
}

inline QString dmiValue(const QString &key, const QString &sysfsRoot = QStringLiteral("/sys"))
{
    const QString value = readText(sysfsRoot + QStringLiteral("/class/dmi/id/") + key);
    if (value.compare(QStringLiteral("To be filled by O.E.M."), Qt::CaseInsensitive) == 0 ||
        value.compare(QStringLiteral("Default string"), Qt::CaseInsensitive) == 0 ||
        value.compare(QStringLiteral("Not Specified"), Qt::CaseInsensitive) == 0)
        return QString();
    return value;
}

inline QString model(const QString &sysfsRoot = QStringLiteral("/sys"))
{
    const QString vendor = dmiValue(QStringLiteral("sys_vendor"), sysfsRoot);
    const QString product = dmiValue(QStringLiteral("product_name"), sysfsRoot);
    return product.startsWith(vendor, Qt::CaseInsensitive) ? product : (vendor + QLatin1Char(' ') + product).trimmed();
}

inline QString firmware(const QString &sysfsRoot = QStringLiteral("/sys"))
{
    return dmiValue(QStringLiteral("bios_version"), sysfsRoot);
}

struct Temperature {
    bool available = false;
    double celsius = 0.0;
    double warning = 75.0;
    double critical = 82.0;
    QString source;
};

inline bool temperatureValue(const QString &path, double *value)
{
    bool ok = false;
    const double degrees = readText(path).toDouble(&ok) / 1000.0;
    if (!ok || !std::isfinite(degrees) || degrees < -40.0 || degrees > 150.0)
        return false;
    *value = degrees;
    return true;
}

inline bool cpuSensorName(const QString &name)
{
    return QRegularExpression(QStringLiteral("(^cpu|cpu[ _-]|package|physical id|^core[ _-]?[0-9]|^tctl$|^tdie$|x86_pkg_temp)"),
                              QRegularExpression::CaseInsensitiveOption).match(name).hasMatch();
}

inline Temperature cpuTemperature(const QString &sysfsRoot = QStringLiteral("/sys"))
{
    Temperature result;
    const QDir hwmonRoot(sysfsRoot + QStringLiteral("/class/hwmon"));
    for (const QString &entry : hwmonRoot.entryList({QStringLiteral("hwmon*")}, QDir::Dirs | QDir::NoDotAndDotDot)) {
        const QDir sensor(hwmonRoot.filePath(entry));
        const QString driver = readText(sensor.filePath(QStringLiteral("name"))).toLower();
        const bool cpuDriver = driver == QStringLiteral("coretemp") || driver == QStringLiteral("k10temp") ||
                               driver == QStringLiteral("zenpower") || driver == QStringLiteral("via_cputemp");
        for (const QString &input : sensor.entryList({QStringLiteral("temp*_input")}, QDir::Files)) {
            const QString base = input.left(input.size() - QStringLiteral("_input").size());
            if (!cpuDriver && !cpuSensorName(readText(sensor.filePath(base + QStringLiteral("_label")))))
                continue;
            double degrees = 0.0;
            if (!temperatureValue(sensor.filePath(input), &degrees) || (result.available && degrees <= result.celsius))
                continue;
            result = Temperature();
            result.available = true;
            result.celsius = degrees;
            result.source = sensor.filePath(input);
            double threshold = 0.0;
            if (temperatureValue(sensor.filePath(base + QStringLiteral("_crit")), &threshold) && threshold > 0.0) {
                result.critical = threshold;
                result.warning = threshold - 10.0;
            }
            if (temperatureValue(sensor.filePath(base + QStringLiteral("_max")), &threshold) &&
                threshold > 0.0 && threshold < result.critical)
                result.warning = threshold;
        }
    }
    if (result.available)
        return result;

    const QDir thermalRoot(sysfsRoot + QStringLiteral("/class/thermal"));
    for (const QString &entry : thermalRoot.entryList({QStringLiteral("thermal_zone*")}, QDir::Dirs | QDir::NoDotAndDotDot)) {
        const QDir zone(thermalRoot.filePath(entry));
        if (!cpuSensorName(readText(zone.filePath(QStringLiteral("type")))))
            continue;
        double degrees = 0.0;
        if (!temperatureValue(zone.filePath(QStringLiteral("temp")), &degrees) || (result.available && degrees <= result.celsius))
            continue;
        result = Temperature();
        result.available = true;
        result.celsius = degrees;
        result.source = zone.filePath(QStringLiteral("temp"));
        for (const QString &type : zone.entryList({QStringLiteral("trip_point_*_type")}, QDir::Files)) {
            double threshold = 0.0;
            if (readText(zone.filePath(type)) == QStringLiteral("critical") &&
                temperatureValue(zone.filePath(type.left(type.size() - 5) + QStringLiteral("_temp")), &threshold) && threshold > 0.0) {
                result.critical = threshold;
                result.warning = threshold - 10.0;
            }
        }
    }
    return result;
}

inline QStringList cpuPolicies(const QString &sysfsRoot = QStringLiteral("/sys"))
{
    const QDir root(sysfsRoot + QStringLiteral("/devices/system/cpu/cpufreq"));
    QStringList policies;
    for (const QString &entry : root.entryList({QStringLiteral("policy*")}, QDir::Dirs | QDir::NoDotAndDotDot))
        policies.append(root.filePath(entry));
    return policies;
}

inline quint64 frequencyKhz(const QString &policy, const QString &key)
{
    return readText(QDir(policy).filePath(key)).toULongLong();
}
}
