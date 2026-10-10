#include "SystemMonitor.h"
#if defined(NEUTRONOS_PLATFORM_GEMINI)
#include "../platform/gemini/GeminiHardware.h"
#endif

#include "TelemetryMath.h"

#include <QAbstractSocket>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAddressEntry>
#include <QNetworkInterface>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QTextStream>
#include <QThread>
#include <QVariantMap>
#include <QtMath>
#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>
#include <limits>
#include <utility>

#ifdef Q_OS_LINUX
#include <pwd.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <unistd.h>
#endif

namespace {

QString neutronOsRootPath()
{
    const QString configured = QString::fromLocal8Bit(qgetenv("NEUTRONOS_ROOT")).trimmed();
    return configured.isEmpty()
        ? QDir::cleanPath(QDir::homePath() + QStringLiteral("/NeutronOS"))
        : QDir::cleanPath(configured);
}

QString storageSelectionFilePath()
{
    return neutronOsRootPath() + QStringLiteral("/state/system/storage_display.json");
}

QString thermalBaselineFilePath()
{
    return neutronOsRootPath() + QStringLiteral("/state/system/thermal_baseline.json");
}

QString readTrimmedFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromUtf8(file.readAll()).trimmed();
}

QString normalizedSortKey(const QString &value, const QString &fallback)
{
    QString key = value.trimmed().toLower();
    if (key == QStringLiteral("ram"))
        key = QStringLiteral("memory");

    if (key == QStringLiteral("cpu") ||
        key == QStringLiteral("memory") ||
        key == QStringLiteral("name") ||
        key == QStringLiteral("pid")) {
        return key;
    }

    return fallback;
}

QString formatCpuFrequencyKhz(quint64 khz)
{
    if (khz == 0)
        return QStringLiteral("--");

    const double mhz = static_cast<double>(khz) / 1000.0;
    if (mhz >= 1000.0)
        return QString::number(mhz / 1000.0, 'f', 2) + QStringLiteral(" GHz");

    return QString::number(mhz, 'f', 0) + QStringLiteral(" MHz");
}

struct CpuCounterSnapshot
{
    QString label;
    int logicalCore = -1;
    quint64 total = 0;
    quint64 idle = 0;
};

QVector<CpuCounterSnapshot> readCpuCounterSnapshot()
{
    QVector<CpuCounterSnapshot> result;

#ifndef Q_OS_LINUX
    /*
        Desktop development fallback.

        NeutronOS production runs on Linux/Raspberry Pi and never enters this
        branch. The counters are cumulative and advance on every call so the
        same two-snapshot CPU calculation path remains exercised on Windows
        and macOS builds without inventing a separate UI-only code path.
    */
    static quint64 mockTick = 0;
    mockTick += 100;

    auto appendMock =
        [&result, mockTick](
            const QString &label,
            int logicalCore,
            quint64 busyPercent,
            quint64 phase
        ) {
            const quint64 total =
                100000 + mockTick + phase;

            const quint64 idle =
                total -
                ((total * busyPercent) / 100);

            CpuCounterSnapshot snapshot;
            snapshot.label = label;
            snapshot.logicalCore = logicalCore;
            snapshot.total = total;
            snapshot.idle = idle;

            result.append(snapshot);
        };

    appendMock(QStringLiteral("cpu"), -1, 37, 0);
    appendMock(QStringLiteral("cpu0"), 0, 29, 7);
    appendMock(QStringLiteral("cpu1"), 1, 41, 13);
    appendMock(QStringLiteral("cpu2"), 2, 35, 19);
    appendMock(QStringLiteral("cpu3"), 3, 43, 23);

    return result;
#else
    QFile file(QStringLiteral("/proc/stat"));

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    /*
        procfs files report a size of zero even though they contain readable
        data. QTextStream::atEnd() can therefore return true before the first
        read on some Qt/Linux combinations. Read the complete pseudo-file
        first and then parse its lines so CPU telemetry always receives a
        real snapshot.
    */
    const QList<QByteArray> lines =
        file.readAll().split('\n');

    for (const QByteArray &rawLine : lines) {
        const QString line =
            QString::fromUtf8(rawLine).trimmed();

        if (!line.startsWith(QStringLiteral("cpu")))
            break;

        const QStringList fields =
            line.simplified().split(
                QLatin1Char(' '),
                Qt::SkipEmptyParts
            );

        if (fields.size() < 5)
            continue;

        const QString label = fields.at(0);

        bool validLabel = false;
        int logicalCore = -1;

        if (label == QStringLiteral("cpu")) {
            validLabel = true;
        } else if (label.size() > 3 &&
                   label.startsWith(QStringLiteral("cpu"))) {
            bool coreOk = false;
            logicalCore = label.mid(3).toInt(&coreOk);
            validLabel = coreOk && logicalCore >= 0;
        }

        if (!validLabel)
            continue;

        auto counterAt =
            [&fields](int index) -> quint64 {
                if (index < 0 ||
                    index >= fields.size()) {
                    return 0;
                }

                bool ok = false;
                const quint64 value =
                    fields.at(index).toULongLong(&ok);

                return ok ? value : 0;
            };

        const quint64 user = counterAt(1);
        const quint64 nice = counterAt(2);
        const quint64 system = counterAt(3);
        const quint64 idle = counterAt(4);
        const quint64 ioWait = counterAt(5);
        const quint64 irq = counterAt(6);
        const quint64 softIrq = counterAt(7);
        const quint64 steal = counterAt(8);

        const quint64 idleAll = idle + ioWait;
        const quint64 nonIdle =
            user + nice + system + irq + softIrq + steal;
        const quint64 total = idleAll + nonIdle;

        if (total == 0)
            continue;

        CpuCounterSnapshot snapshot;
        snapshot.label = label;
        snapshot.logicalCore = logicalCore;
        snapshot.total = total;
        snapshot.idle = idleAll;

        result.append(snapshot);
    }

    return result;
#endif
}

struct CpuUptimeSnapshot
{
    bool valid = false;
    double uptimeSeconds = 0.0;
    double idleSeconds = 0.0;
};

CpuUptimeSnapshot readCpuUptimeSnapshot()
{
    CpuUptimeSnapshot snapshot;

#ifdef Q_OS_LINUX
    QFile file(QStringLiteral("/proc/uptime"));

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return snapshot;

    const QStringList fields =
        QString::fromUtf8(file.readAll())
            .simplified()
            .split(
                QLatin1Char(' '),
                Qt::SkipEmptyParts
            );

    if (fields.size() < 2)
        return snapshot;

    bool uptimeOk = false;
    bool idleOk = false;

    snapshot.uptimeSeconds =
        fields.at(0).toDouble(&uptimeOk);
    snapshot.idleSeconds =
        fields.at(1).toDouble(&idleOk);
    snapshot.valid =
        uptimeOk &&
        idleOk &&
        snapshot.uptimeSeconds >= 0.0 &&
        snapshot.idleSeconds >= 0.0;
#else
    /*
        Desktop fallback follows the same cumulative-counter behavior as the
        mock /proc/stat path.
    */
    static double mockUptime = 1000.0;
    static double mockIdle = 2500.0;

    mockUptime += 1.0;
    mockIdle += 2.45;

    snapshot.valid = true;
    snapshot.uptimeSeconds = mockUptime;
    snapshot.idleSeconds = mockIdle;
#endif

    return snapshot;
}

struct CpuCoreIdleSnapshot
{
    int logicalCore = -1;
    quint64 idleMicroseconds = 0;
    quint64 frequencyKhz = 0;
};

QVector<CpuCoreIdleSnapshot> readCpuCoreIdleSnapshots()
{
    QVector<CpuCoreIdleSnapshot> result;

#ifdef Q_OS_LINUX
    const QDir cpuRoot(QStringLiteral("/sys/devices/system/cpu"));
    const QStringList entries = cpuRoot.entryList(
        QStringList() << QStringLiteral("cpu*"),
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::Name
    );

    const QRegularExpression cpuPattern(
        QStringLiteral("^cpu(\\d+)$")
    );

    for (const QString &entry : entries) {
        const QRegularExpressionMatch match =
            cpuPattern.match(entry);

        if (!match.hasMatch())
            continue;

        bool coreOk = false;
        const int coreIndex =
            match.captured(1).toInt(&coreOk);

        if (!coreOk || coreIndex < 0)
            continue;

        const QString corePath =
            cpuRoot.filePath(entry);

        const QString onlineText =
            readTrimmedFile(corePath + QStringLiteral("/online"));

        if (!onlineText.isEmpty() && onlineText == QStringLiteral("0"))
            continue;

        const QDir idleRoot(
            corePath + QStringLiteral("/cpuidle")
        );

        if (!idleRoot.exists())
            continue;

        const QStringList idleStates = idleRoot.entryList(
            QStringList() << QStringLiteral("state*"),
            QDir::Dirs | QDir::NoDotAndDotDot,
            QDir::Name
        );

        quint64 totalIdleMicroseconds = 0;
        bool measuredAnyState = false;

        for (const QString &state : idleStates) {
            bool idleOk = false;
            const quint64 idleValue =
                readTrimmedFile(
                    idleRoot.filePath(
                        state + QStringLiteral("/time")
                    )
                ).toULongLong(&idleOk);

            if (!idleOk)
                continue;

            totalIdleMicroseconds += idleValue;
            measuredAnyState = true;
        }

        if (!measuredAnyState)
            continue;

        quint64 frequencyKhz =
            readTrimmedFile(
                corePath +
                QStringLiteral("/cpufreq/scaling_cur_freq")
            ).toULongLong();

        if (frequencyKhz == 0) {
            frequencyKhz =
                readTrimmedFile(
                    QStringLiteral(
                        "/sys/devices/system/cpu/cpufreq/"
                        "policy%1/scaling_cur_freq"
                    ).arg(coreIndex)
                ).toULongLong();
        }

        CpuCoreIdleSnapshot snapshot;
        snapshot.logicalCore = coreIndex;
        snapshot.idleMicroseconds = totalIdleMicroseconds;
        snapshot.frequencyKhz = frequencyKhz;
        result.append(snapshot);
    }

    std::sort(
        result.begin(),
        result.end(),
        [](const CpuCoreIdleSnapshot &left,
           const CpuCoreIdleSnapshot &right) {
            return left.logicalCore < right.logicalCore;
        }
    );
#endif

    return result;
}

QHash<QString, quint64> readMemInfoKb()
{
    QHash<QString, quint64> result;

    QFile file(QStringLiteral("/proc/meminfo"));

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    /*
        /proc/meminfo is a procfs pseudo-file and commonly reports a file
        length of zero. Avoid QTextStream::atEnd(), which can incorrectly
        treat it as empty before the first read.
    */
    const QList<QByteArray> lines =
        file.readAll().split('\n');

    for (const QByteArray &rawLine : lines) {
        const QString line =
            QString::fromUtf8(rawLine).trimmed();

        const int colon = line.indexOf(QLatin1Char(':'));

        if (colon <= 0)
            continue;

        const QString key =
            line.left(colon).trimmed();

        const QString valueText =
            line.mid(colon + 1)
                .simplified()
                .section(QLatin1Char(' '), 0, 0);

        bool ok = false;
        const quint64 value =
            valueText.toULongLong(&ok);

        if (ok)
            result.insert(key, value);
    }

    return result;
}


/*
    Lightweight native process telemetry.

    The release shell must never spawn `ps` on a repeating timer. On a Pi,
    walking every process and formatting a complete table inside an external
    utility can briefly consume an entire core, distort the very CPU list it
    is measuring, and create avoidable process/QProcess allocations.

    This scanner reads the kernel's compact /proc records on a worker thread.
    SystemMonitor computes CPU deltas when the result returns to the GUI
    thread, so no QML code parses files and no helper process is launched.
*/
struct NativeProcessRecord
{
    qlonglong pid = 0;
    QString name;
    QString user;
    QString state;
    quint64 cpuTicks = 0;
    quint64 startTicks = 0;
    quint64 residentBytes = 0;
};

struct NativeProcessSnapshot
{
    QVector<NativeProcessRecord> records;
    quint64 totalCpuTicks = 0;
    quint64 uptimeTicks = 0;
    quint64 totalMemoryBytes = 0;
    quint64 clockTicksPerSecond = 100;
    int logicalCores = 1;
};

quint64 readAggregateCpuTicks()
{
#ifdef Q_OS_LINUX
    QFile file(QStringLiteral("/proc/stat"));

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return 0;

    const QString line =
        QString::fromUtf8(file.readLine()).simplified();

    const QStringList fields =
        line.split(QLatin1Char(' '), Qt::SkipEmptyParts);

    if (fields.isEmpty() || fields.first() != QStringLiteral("cpu"))
        return 0;

    quint64 total = 0;

    for (int index = 1; index < fields.size(); ++index) {
        bool ok = false;
        const quint64 value = fields.at(index).toULongLong(&ok);
        if (ok)
            total += value;
    }

    return total;
#else
    return 0;
#endif
}

QString usernameForUid(quint32 uid, QHash<quint32, QString> &cache)
{
    const auto cached = cache.constFind(uid);
    if (cached != cache.constEnd())
        return cached.value();

    QString result = QString::number(uid);

#ifdef Q_OS_LINUX
    long bufferSize = ::sysconf(_SC_GETPW_R_SIZE_MAX);
    if (bufferSize < 1024)
        bufferSize = 16384;

    QByteArray buffer;
    buffer.resize(static_cast<int>(bufferSize));

    struct passwd account;
    struct passwd *resolved = nullptr;

    if (::getpwuid_r(
            static_cast<uid_t>(uid),
            &account,
            buffer.data(),
            static_cast<std::size_t>(buffer.size()),
            &resolved) == 0 &&
        resolved &&
        resolved->pw_name) {
        const QString name =
            QString::fromLocal8Bit(resolved->pw_name).trimmed();
        if (!name.isEmpty())
            result = name;
    }
#endif

    cache.insert(uid, result);
    return result;
}

NativeProcessSnapshot scanNativeProcesses()
{
    NativeProcessSnapshot snapshot;

#ifdef Q_OS_LINUX
    const long clockTicks = ::sysconf(_SC_CLK_TCK);
    const long pageSize = ::sysconf(_SC_PAGESIZE);

    snapshot.clockTicksPerSecond =
        clockTicks > 0
        ? static_cast<quint64>(clockTicks)
        : 100ULL;

    const quint64 pageBytes =
        pageSize > 0
        ? static_cast<quint64>(pageSize)
        : 4096ULL;

    snapshot.logicalCores =
        qMax(1, QThread::idealThreadCount());
    snapshot.totalCpuTicks = readAggregateCpuTicks();

    QFile uptimeFile(QStringLiteral("/proc/uptime"));
    if (uptimeFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool ok = false;
        const double seconds =
            QString::fromUtf8(uptimeFile.readLine())
                .simplified()
                .section(QLatin1Char(' '), 0, 0)
                .toDouble(&ok);

        if (ok && seconds >= 0.0) {
            snapshot.uptimeTicks =
                static_cast<quint64>(
                    seconds *
                    static_cast<double>(snapshot.clockTicksPerSecond)
                );
        }
    }

    const QHash<QString, quint64> memory = readMemInfoKb();
    snapshot.totalMemoryBytes =
        memory.value(QStringLiteral("MemTotal")) * 1024ULL;

    const QDir procRoot(QStringLiteral("/proc"));
    const QStringList entries = procRoot.entryList(
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::NoSort
    );

    snapshot.records.reserve(entries.size());
    QHash<quint32, QString> userCache;

    for (const QString &entry : entries) {
        bool pidOk = false;
        const qlonglong pid = entry.toLongLong(&pidOk);

        if (!pidOk || pid <= 0)
            continue;

        const QString processPath = procRoot.filePath(entry);
        QFile statFile(processPath + QStringLiteral("/stat"));

        if (!statFile.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;

        const QString raw =
            QString::fromLocal8Bit(statFile.readAll()).trimmed();

        const int openParen = raw.indexOf(QLatin1Char('('));
        const int closeParen = raw.lastIndexOf(QLatin1Char(')'));

        if (openParen < 0 || closeParen <= openParen)
            continue;

        const QString name =
            raw.mid(openParen + 1, closeParen - openParen - 1);

        const QStringList fields =
            raw.mid(closeParen + 1)
                .simplified()
                .split(QLatin1Char(' '), Qt::SkipEmptyParts);

        /*
            fields[0]  = stat field 3  (state)
            fields[11] = stat field 14 (utime)
            fields[12] = stat field 15 (stime)
            fields[19] = stat field 22 (starttime)
            fields[21] = stat field 24 (rss pages)
        */
        if (fields.size() <= 21)
            continue;

        bool utimeOk = false;
        bool stimeOk = false;
        bool startOk = false;
        bool rssOk = false;

        const quint64 userTicks =
            fields.at(11).toULongLong(&utimeOk);
        const quint64 systemTicks =
            fields.at(12).toULongLong(&stimeOk);
        const quint64 startTicks =
            fields.at(19).toULongLong(&startOk);
        const qlonglong rssPages =
            fields.at(21).toLongLong(&rssOk);

        if (!utimeOk || !stimeOk || !startOk || !rssOk)
            continue;

        quint32 uid = 0;
        const QByteArray encodedPath = processPath.toLocal8Bit();
        struct stat processStat;

        if (::stat(encodedPath.constData(), &processStat) == 0)
            uid = static_cast<quint32>(processStat.st_uid);

        NativeProcessRecord record;
        record.pid = pid;
        record.name = name.isEmpty()
            ? QStringLiteral("process")
            : name;
        record.user = usernameForUid(uid, userCache);
        record.state = fields.at(0);
        record.cpuTicks = userTicks + systemTicks;
        record.startTicks = startTicks;
        record.residentBytes =
            rssPages > 0
            ? static_cast<quint64>(rssPages) * pageBytes
            : 0ULL;

        snapshot.records.append(record);
    }
#endif

    return snapshot;
}

QHash<QString, QString> deviceUuidMap()
{
    QHash<QString, QString> result;
    QDir dir(QStringLiteral("/dev/disk/by-uuid"));

    if (!dir.exists())
        return result;

    const QFileInfoList entries = dir.entryInfoList(
        QDir::Files | QDir::System | QDir::NoDotAndDotDot
    );

    for (const QFileInfo &entry : entries) {
        QString target = entry.symLinkTarget();
        if (target.isEmpty())
            continue;

        QFileInfo targetInfo(target);
        QString canonical = targetInfo.canonicalFilePath();
        if (canonical.isEmpty())
            canonical = QDir::cleanPath(target);

        result.insert(canonical, entry.fileName());
    }

    return result;
}

double processCpuValue(const QVariant &entry)
{
    return entry.toMap().value(QStringLiteral("cpu")).toDouble();
}

double processMemoryValue(const QVariant &entry)
{
    return entry.toMap().value(QStringLiteral("memory")).toDouble();
}

QString processNameValue(const QVariant &entry)
{
    return entry.toMap().value(QStringLiteral("name")).toString();
}

qlonglong processPidValue(const QVariant &entry)
{
    return entry.toMap().value(QStringLiteral("pid")).toLongLong();
}

void sortProcessList(QVariantList &list, const QString &sortKey)
{
    const QString key = normalizedSortKey(sortKey, QStringLiteral("cpu"));

    std::sort(list.begin(), list.end(),
              [key](const QVariant &left, const QVariant &right) {
        if (key == QStringLiteral("memory")) {
            const double l = processMemoryValue(left);
            const double r = processMemoryValue(right);
            if (!qFuzzyCompare(l + 1.0, r + 1.0))
                return l > r;
            return processCpuValue(left) > processCpuValue(right);
        }

        if (key == QStringLiteral("name")) {
            const int comparison = QString::localeAwareCompare(
                processNameValue(left), processNameValue(right)
            );
            if (comparison != 0)
                return comparison < 0;
            return processPidValue(left) < processPidValue(right);
        }

        if (key == QStringLiteral("pid"))
            return processPidValue(left) < processPidValue(right);

        const double l = processCpuValue(left);
        const double r = processCpuValue(right);
        if (!qFuzzyCompare(l + 1.0, r + 1.0))
            return l > r;
        return processMemoryValue(left) > processMemoryValue(right);
    });
}

QVariantList limitedList(const QVariantList &source, int maximum)
{
    return maximum > 0 && source.size() > maximum
        ? source.mid(0, maximum)
        : source;
}

} // namespace

SystemMonitor::SystemMonitor(QObject *parent)
    : QObject(parent)
{
    loadDisplayedMountIds();
    loadThermalBaseline();

    connect(&m_fastTimer, &QTimer::timeout,
            this, &SystemMonitor::refreshFast);
    connect(&m_cacheTimer, &QTimer::timeout,
            this, &SystemMonitor::refreshCache);
    connect(&m_speedTestTimer, &QTimer::timeout,
            this, &SystemMonitor::updateSpeedTestAge);
    connect(&m_temperatureHistoryTimer, &QTimer::timeout,
            this, &SystemMonitor::sampleTemperatureHistory);

    m_fastTimer.setInterval(2000);
    m_cacheTimer.setInterval(15000);
    m_speedTestTimer.setInterval(60000);
    m_temperatureHistoryTimer.setInterval(TemperatureHistorySampleIntervalMs);

    // Draw Login first; telemetry fills immediately after the event loop starts.
    QTimer::singleShot(0, this, &SystemMonitor::refreshFast);
    QTimer::singleShot(1100, this, &SystemMonitor::refreshCache);
    QTimer::singleShot(1400, this, &SystemMonitor::sampleTemperatureHistory);

    m_fastTimer.start();
    m_cacheTimer.start();
    m_speedTestTimer.start();
    m_temperatureHistoryTimer.start();

    /*
        refreshFast() above establishes the initial cumulative CPU baseline.
        Take one early follow-up sample so total and per-core usage populate
        promptly instead of waiting for the first two-second timer tick.
    */
    QTimer::singleShot(
        750,
        this,
        &SystemMonitor::updateCpu
    );
}

/* Getters */

QString SystemMonitor::cpu() const { return m_cpu; }
int SystemMonitor::cpuPercent() const { return m_cpuPercent; }
QString SystemMonitor::cpuFrequency() const { return m_cpuFrequency; }
quint64 SystemMonitor::cpuFrequencyHz() const { return m_cpuFrequencyHz; }
QString SystemMonitor::cpuModel() const { return m_cpuModel; }
bool SystemMonitor::cpuValid() const { return m_cpuValid; }
QString SystemMonitor::cpuGovernor() const { return m_cpuGovernor; }
QString SystemMonitor::loadAverage() const { return m_loadAverage; }
double SystemMonitor::load1() const { return m_load1; }
double SystemMonitor::load5() const { return m_load5; }
double SystemMonitor::load15() const { return m_load15; }
int SystemMonitor::processCount() const { return m_processCount; }
QVariantList SystemMonitor::cpuCores() const { return m_cpuCores; }
int SystemMonitor::cpuCoreCount() const { return m_cpuCores.size(); }
QVariantMap SystemMonitor::cpuCoreAt(int index) const
{
    if (index < 0 || index >= m_cpuCores.size())
        return {};

    return m_cpuCores.at(index).toMap();
}
QVariantList SystemMonitor::cpuProcesses() const { return m_cpuProcesses; }
QVariantList SystemMonitor::processList() const { return m_processList; }
QVariantList SystemMonitor::topCpuProcesses() const { return m_topCpuProcesses; }

QString SystemMonitor::ram() const { return m_ram; }
int SystemMonitor::ramPercent() const { return m_ramPercent; }
QString SystemMonitor::ramUsed() const { return m_ramUsed; }
QString SystemMonitor::ramTotal() const { return m_ramTotal; }
QString SystemMonitor::ramAvailable() const { return m_ramAvailable; }
QString SystemMonitor::memoryCached() const { return m_memoryCached; }
QString SystemMonitor::memoryBuffers() const { return m_memoryBuffers; }
quint64 SystemMonitor::ramUsedBytes() const { return m_ramUsedBytes; }
quint64 SystemMonitor::ramTotalBytes() const { return m_ramTotalBytes; }
quint64 SystemMonitor::ramAvailableBytes() const { return m_ramAvailableBytes; }
quint64 SystemMonitor::memoryCachedBytes() const { return m_memoryCachedBytes; }
quint64 SystemMonitor::memoryBuffersBytes() const { return m_memoryBuffersBytes; }
QString SystemMonitor::swapUsed() const { return m_swapUsed; }
QString SystemMonitor::swapTotal() const { return m_swapTotal; }
quint64 SystemMonitor::swapUsedBytes() const { return m_swapUsedBytes; }
quint64 SystemMonitor::swapTotalBytes() const { return m_swapTotalBytes; }
int SystemMonitor::swapPercent() const { return m_swapPercent; }
int SystemMonitor::memoryPressurePercent() const { return m_memoryPressurePercent; }
bool SystemMonitor::memoryValid() const { return m_memoryValid; }
QVariantList SystemMonitor::memoryProcesses() const { return m_memoryProcesses; }
QVariantList SystemMonitor::topRamProcesses() const { return m_topRamProcesses; }

QVariantList SystemMonitor::mounts() const { return m_mounts; }
QString SystemMonitor::bootStorage() const { return m_bootStorage; }
int SystemMonitor::bootStoragePercent() const { return m_bootStoragePercent; }
QString SystemMonitor::mediaStorage() const { return m_mediaStorage; }
int SystemMonitor::mediaStoragePercent() const { return m_mediaStoragePercent; }

QVariantList SystemMonitor::displayedMountIds() const
{
    QVariantList result;
    for (const QString &id : m_displayedMountIds)
        result.append(id);
    return result;
}

QVariantList SystemMonitor::storageDisplaySlots() const
{
    return m_storageDisplaySlots;
}

QString SystemMonitor::temperature() const { return m_temperature; }
double SystemMonitor::cpuTemperature() const { return m_cpuTemperatureF; }
double SystemMonitor::temperatureCelsius() const { return m_cpuTemperatureC; }
bool SystemMonitor::temperatureValid() const { return m_temperatureValid; }
QString SystemMonitor::temperatureUnit() const { return QStringLiteral("F"); }
QString SystemMonitor::thermalStatus() const { return m_thermalStatus; }
bool SystemMonitor::thermalThrottled() const { return m_thermalThrottled; }
int SystemMonitor::throttlingEvents() const { return m_throttlingEvents; }
double SystemMonitor::temperatureWarningThreshold() const { return m_temperatureWarningThresholdF; }
double SystemMonitor::temperatureCriticalThreshold() const { return m_temperatureCriticalThresholdF; }

QVariantList SystemMonitor::temperatureHistory() const
{
    QVariantList result;
    result.reserve(m_temperatureHistorySamples.size());

    for (const ThermalSample &sample : m_temperatureHistorySamples) {
        QVariantMap entry;
        entry[QStringLiteral("timestamp")] = sample.timestampMs;
        entry[QStringLiteral("temperature")] = sample.temperatureF;
        entry[QStringLiteral("throttled")] = sample.throttled;
        result.append(entry);
    }

    return result;
}

int SystemMonitor::temperatureHistoryRevision() const
{
    return m_temperatureHistoryRevision;
}

double SystemMonitor::learnedTemperatureBaseline() const
{
    return m_learnedTemperatureBaselineF;
}

QString SystemMonitor::adaptiveThermalStatus() const
{
    if (!m_temperatureValid)
        return QStringLiteral("Unavailable");
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    if (m_thermalThrottled || m_cpuTemperatureF >= m_temperatureCriticalThresholdF)
#else
    if (m_thermalThrottled || m_cpuTemperatureF >= qMin(160.0, m_temperatureCriticalThresholdF))
#endif
        return QStringLiteral("Critical");
    if (m_learnedTemperatureBaselineF <= 0.0)
        return m_cpuTemperatureF >= m_temperatureWarningThresholdF
            ? QStringLiteral("Warmer Than Usual")
            : QStringLiteral("Stable");
    const double difference = m_cpuTemperatureF - m_learnedTemperatureBaselineF;
    if (difference < -10.0)
        return QStringLiteral("Cooler Than Usual");
    if (difference > 10.0)
        return QStringLiteral("Warmer Than Usual");
    return QStringLiteral("Stable");
}

QString SystemMonitor::network() const { return m_network; }
QString SystemMonitor::wifiInterface() const { return m_wifiInterface; }
QString SystemMonitor::activeInterface() const { return m_activeInterface; }
QString SystemMonitor::connectionType() const { return m_connectionType; }
bool SystemMonitor::networkConnected() const { return m_networkValid; }
bool SystemMonitor::networkValid() const { return m_networkValid; }
quint64 SystemMonitor::rxBytesPerSecond() const { return m_rxBytesPerSecond; }
quint64 SystemMonitor::txBytesPerSecond() const { return m_txBytesPerSecond; }
QString SystemMonitor::ssid() const { return m_ssid; }
QString SystemMonitor::wifiSignal() const { return m_wifiSignal; }
QString SystemMonitor::localIp() const { return m_localIp; }
QString SystemMonitor::tailscaleIp() const { return m_tailscaleIp; }
QString SystemMonitor::upload() const { return m_upload; }
QString SystemMonitor::download() const { return m_download; }
QString SystemMonitor::speedTestDownload() const { return m_speedTestDownload; }
QString SystemMonitor::speedTestUpload() const { return m_speedTestUpload; }
QString SystemMonitor::speedTestUpdated() const { return m_speedTestUpdated; }
QString SystemMonitor::speedTestAge() const { return m_speedTestAge; }
bool SystemMonitor::speedTestRunning() const { return m_speedTestRunning; }
QString SystemMonitor::uptime() const { return m_uptime; }
quint64 SystemMonitor::uptimeSeconds() const { return m_uptimeSeconds; }
QDateTime SystemMonitor::bootDateTime() const { return m_bootDateTime; }
bool SystemMonitor::uptimeValid() const { return m_uptimeValid; }
bool SystemMonitor::dashboardActive() const { return m_dashboardActive; }
int SystemMonitor::fastUpdateIntervalMs() const { return m_fastTimer.interval(); }

void SystemMonitor::setDashboardActive(bool active)
{
    if (m_dashboardActive == active)
        return;
    m_dashboardActive = active;
    m_fastTimer.setInterval(active ? 2000 : 6000);
    m_cacheTimer.setInterval(active ? 15000 : 30000);
    emit dashboardActiveChanged();
    if (active)
        refreshFast();
}
QString SystemMonitor::lastAptUpdate() const { return m_lastAptUpdate; }
QString SystemMonitor::systemMode() const { return m_systemMode; }
QVariantList SystemMonitor::networkApps() const { return m_networkApps; }
QVariantList SystemMonitor::serviceHealth() const { return m_serviceHealth; }

/* Public API */

void SystemMonitor::refresh()
{
    const qint64 now =
        QDateTime::currentMSecsSinceEpoch();

    const qint64 lastManualRefresh =
        property("_lastManualRefreshMs").toLongLong();

    if (lastManualRefresh > 0 &&
        now - lastManualRefresh < 2000) {
        return;
    }

    setProperty("_lastManualRefreshMs", now);

    refreshFast();

    if (m_processList.isEmpty())
        updateTopProcessesAsync();
}

void SystemMonitor::runSpeedTestNow()
{
    runCachedSpeedTest();
}

void SystemMonitor::refreshCpuMonitor()
{
    /*
        The backend timer owns the normal CPU cadence. A modal-open request
        only takes a new cumulative sample when the cached value is actually
        stale; this prevents QML from creating a second competing sampler.
    */
    updateLoadAverage();

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const int staleAfterMs = qMax(750, m_fastTimer.interval() - 150);

    if (m_lastCpuSampleMs <= 0 ||
        nowMs - m_lastCpuSampleMs >= staleAfterMs) {
        updateCpu();
    }

    updateCpuDetails();

    if (m_processCount <= 0)
        updateProcessCount();

    if (m_processList.isEmpty())
        updateTopProcessesAsync();
}

void SystemMonitor::refreshMemoryMonitor()
{
    updateRam();

    if (m_processCount <= 0)
        updateProcessCount();

    if (m_processList.isEmpty())
        updateTopProcessesAsync();
}

QVariantMap SystemMonitor::memorySnapshot() const
{
    QVariantMap snapshot;

    snapshot.insert(QStringLiteral("percent"), m_ramPercent);
    snapshot.insert(QStringLiteral("usedBytes"), m_ramUsedBytes);
    snapshot.insert(QStringLiteral("totalBytes"), m_ramTotalBytes);
    snapshot.insert(QStringLiteral("availableBytes"), m_ramAvailableBytes);
    snapshot.insert(QStringLiteral("cachedBytes"), m_memoryCachedBytes);
    snapshot.insert(QStringLiteral("buffersBytes"), m_memoryBuffersBytes);
    snapshot.insert(QStringLiteral("swapUsedBytes"), m_swapUsedBytes);
    snapshot.insert(QStringLiteral("swapTotalBytes"), m_swapTotalBytes);
    snapshot.insert(QStringLiteral("swapPercent"), m_swapPercent);
    snapshot.insert(QStringLiteral("pressurePercent"), m_memoryPressurePercent);

    snapshot.insert(QStringLiteral("usedText"), m_ramUsed);
    snapshot.insert(QStringLiteral("totalText"), m_ramTotal);
    snapshot.insert(QStringLiteral("availableText"), m_ramAvailable);
    snapshot.insert(QStringLiteral("cachedText"), m_memoryCached);
    snapshot.insert(QStringLiteral("buffersText"), m_memoryBuffers);
    snapshot.insert(QStringLiteral("swapUsedText"), m_swapUsed);
    snapshot.insert(QStringLiteral("swapTotalText"), m_swapTotal);

    return snapshot;
}

void SystemMonitor::refreshProcesses()
{
    updateProcessCount();
    updateTopProcessesAsync();
}

void SystemMonitor::refreshStorage()
{
    updateMounts();
    emit systemChanged();
}

void SystemMonitor::refreshMounts()
{
    refreshStorage();
}

void SystemMonitor::refreshTemperatureHistory()
{
    updateTemperature();
    sampleTemperatureHistory();
    emit systemChanged();
}

void SystemMonitor::refreshThermalHistory()
{
    refreshTemperatureHistory();
}

void SystemMonitor::setProcessSort(const QString &sortKey)
{
    const QString normalized = normalizedSortKey(sortKey, QStringLiteral("cpu"));
    if (m_processSort == normalized && !m_processList.isEmpty())
        return;

    m_processSort = normalized;
    QVariantList sorted = m_processList.isEmpty() ? m_cpuProcesses : m_processList;
    sortProcessList(sorted, m_processSort);
    sorted = limitedList(sorted, 128);

    if (m_processList != sorted) {
        m_processList = sorted;
        emit processDataChanged();
        emit systemChanged();
    }
}

void SystemMonitor::setMemoryProcessSort(const QString &sortKey)
{
    const QString normalized = normalizedSortKey(sortKey, QStringLiteral("memory"));
    if (m_memoryProcessSort == normalized && !m_memoryProcesses.isEmpty())
        return;

    m_memoryProcessSort = normalized;
    QVariantList sorted = m_memoryProcesses.isEmpty() ? m_processList : m_memoryProcesses;
    sortProcessList(sorted, m_memoryProcessSort);
    sorted = limitedList(sorted, 128);

    if (m_memoryProcesses != sorted) {
        m_memoryProcesses = sorted;
        emit processDataChanged();
        emit systemChanged();
    }
}

bool SystemMonitor::setDisplayedMounts(const QVariant &payload)
{
    const QStringList parsed = parseDisplayedMountIds(payload);

    if (parsed.size() != 2 ||
        parsed[0].trimmed().isEmpty() ||
        parsed[1].trimmed().isEmpty() ||
        parsed[0] == parsed[1]) {
        return false;
    }

    m_displayedMountIds = parsed;
    const bool saved = saveDisplayedMountIds();

    rebuildStorageDisplaySlots();
    emit displayedMountIdsChanged();
    emit storageChanged();
    emit systemChanged();

    return saved;
}

QVariantList SystemMonitor::getTemperatureHistory(int rangeSeconds) const
{
    const int bounded = qBound(300, rangeSeconds, 86400);
    const qint64 minimumTime =
        QDateTime::currentMSecsSinceEpoch() - static_cast<qint64>(bounded) * 1000;

    QVariantList result;

    for (const ThermalSample &sample : m_temperatureHistorySamples) {
        if (sample.timestampMs < minimumTime)
            continue;

        QVariantMap entry;
        entry[QStringLiteral("timestamp")] = sample.timestampMs;
        entry[QStringLiteral("temperature")] = sample.temperatureF;
        entry[QStringLiteral("throttled")] = sample.throttled;
        result.append(entry);
    }

    return result;
}

void SystemMonitor::requestTemperatureHistory(int rangeSeconds)
{
    setTemperatureHistoryRange(rangeSeconds);
}

void SystemMonitor::setTemperatureHistoryRange(int rangeSeconds)
{
    m_temperatureHistoryRangeSeconds = qBound(300, rangeSeconds, 86400);
    emitTemperatureHistorySignals();
}

/* Refresh orchestration */

void SystemMonitor::refreshFast()
{
    ++m_fastTick;

    if (m_fastTick > 1000000)
        m_fastTick = 1;

    updateLoadAverage();
    updateCpu();
    updateRam();
    updateTemperature();
    updateNetwork();
    updateUptime();

    if (m_fastTick == 1 ||
        m_fastTick % 3 == 0 ||
        m_cpuFrequency == QStringLiteral("--")) {
        updateCpuDetails();
    }

    if (m_fastTick == 1 ||
        m_fastTick % 5 == 0 ||
        m_processCount <= 0) {
        updateProcessCount();
    }

    emit systemChanged();
}

void SystemMonitor::refreshCache()
{
    ++m_cacheTick;

    updateMounts();
    updateThermalStatus();
    updateSystemMode();
    updateSpeedTestAge();

    if (m_cacheTick % 20 == 0 || m_lastAptUpdate == QStringLiteral("--"))
        updateLastAptUpdate();

    if (m_cacheTick % 8 == 0)
        updateServiceHealthAsync();

    if (m_cacheTick % 12 == 0)
        updateTopProcessesAsync();

    if (m_cacheTick % 16 == 0)
        updateNetworkAppsAsync();

    if (m_cacheTick > 1000000)
        m_cacheTick = 0;

    emit systemChanged();
}

/* Process helpers */

int SystemMonitor::runProcess(const QString &program,
                              const QStringList &arguments,
                              int timeoutMs,
                              QString *standardOutput,
                              QString *standardError) const
{
    QProcess process;
    process.start(program, arguments);

    if (!process.waitForStarted(400)) {
        if (standardOutput)
            standardOutput->clear();
        if (standardError)
            *standardError = QStringLiteral("Failed to start process");
        return -127;
    }

    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(250);

        if (standardOutput)
            *standardOutput = QString::fromUtf8(process.readAllStandardOutput());
        if (standardError)
            *standardError = QString::fromUtf8(process.readAllStandardError());

        return -124;
    }

    if (standardOutput)
        *standardOutput = QString::fromUtf8(process.readAllStandardOutput());
    if (standardError)
        *standardError = QString::fromUtf8(process.readAllStandardError());

    return process.exitCode();
}

bool SystemMonitor::commandExists(const QString &command) const
{
    const QString trimmed = command.trimmed();
    if (trimmed.isEmpty())
        return false;

    const QFileInfo info(trimmed);
    if (info.isAbsolute())
        return info.exists() && info.isExecutable();

    return !QStandardPaths::findExecutable(trimmed).isEmpty();
}

bool SystemMonitor::systemdUnitActive(const QString &unit) const
{
    if (unit.trimmed().isEmpty())
        return false;

    return runProcess(
        QStringLiteral("systemctl"),
        QStringList() << QStringLiteral("is-active")
                      << QStringLiteral("--quiet")
                      << unit,
        700
    ) == 0;
}

/* CPU */

void SystemMonitor::updateCpu()
{
    /*
        CPU utilization is derived from cumulative Linux counters.

        The sampling owner is SystemMonitor's telemetry timer—not QML. Calls
        that arrive too close together are ignored so an open modal cannot
        collapse the measurement window and overwrite a valid sample with 0%.

        Primary source:
            /proc/stat aggregate and per-core counters

        Independent aggregate fallback:
            /proc/uptime elapsed capacity versus combined idle time

        Final low-activity fallback:
            normalized one-minute load average, used only when both cumulative
            sources report zero repeatedly while runnable work still exists.
    */
    const qint64 nowMs =
        QDateTime::currentMSecsSinceEpoch();

    if (m_lastCpuSampleMs > 0 &&
        nowMs - m_lastCpuSampleMs < 500) {
        return;
    }

    const QVector<CpuCounterSnapshot> samples =
        readCpuCounterSnapshot();

    /*
        Read the independent fallback before validating /proc/stat.

        Some hardened or restricted runtime environments expose /proc/stat
        with zeroed counters rather than failing the open. The old code
        treated that as an empty sample and returned before /proc/uptime or
        load average could be used, leaving cpuPercent permanently at zero.
    */
    const CpuUptimeSnapshot uptimeSnapshot =
        readCpuUptimeSnapshot();

    int logicalCoreCount = 0;

    for (const CpuCounterSnapshot &sample : samples) {
        if (sample.logicalCore >= 0)
            ++logicalCoreCount;
    }

    if (logicalCoreCount <= 0)
        logicalCoreCount = QThread::idealThreadCount();

    logicalCoreCount =
        qMax(1, logicalCoreCount);

    const QString oldCpu = m_cpu;
    const int oldPercent = m_cpuPercent;
    const QVariantList oldCores = m_cpuCores;
    const bool oldValid = m_cpuValid;

    if (samples.isEmpty()) {
        /*
            When /proc/stat is restricted, derive each core independently
            from cumulative cpuidle residency exposed by sysfs. This is a
            real per-core measurement: elapsed wall time minus each core's
            idle-state delta. It is not a copy of the aggregate percentage.
        */
        const QVector<CpuCoreIdleSnapshot> idleCoreSamples =
            readCpuCoreIdleSnapshots();

        QVariantList fallbackCoreRows;
        int measuredIdleCoreCount = 0;
        double measuredIdleCoreTotal = 0.0;

        const qint64 coreElapsedMs =
            m_lastCoreIdleSampleMs > 0
            ? nowMs - m_lastCoreIdleSampleMs
            : 0;

        int highestIdleCore = -1;

        for (const CpuCoreIdleSnapshot &sample : idleCoreSamples) {
            const int coreIndex = sample.logicalCore;

            if (coreIndex < 0)
                continue;

            highestIdleCore = qMax(highestIdleCore, coreIndex);

            if (m_lastSysfsCoreIdleUsec.size() <= coreIndex) {
                m_lastSysfsCoreIdleUsec.resize(coreIndex + 1);
                m_coreSmoothedPercent.resize(coreIndex + 1);
            }

            const quint64 previousIdle =
                m_lastSysfsCoreIdleUsec.at(coreIndex);

            bool measured = false;
            double rawUsage = 0.0;

            if (coreElapsedMs > 0 &&
                previousIdle > 0 &&
                sample.idleMicroseconds >= previousIdle) {
                const double elapsedMicroseconds =
                    static_cast<double>(coreElapsedMs) * 1000.0;

                const double idleDelta = qMin(
                    static_cast<double>(
                        sample.idleMicroseconds - previousIdle
                    ),
                    elapsedMicroseconds
                );

                if (elapsedMicroseconds > 0.0) {
                    rawUsage = qBound(
                        0.0,
                        100.0 *
                            (elapsedMicroseconds - idleDelta) /
                            elapsedMicroseconds,
                        100.0
                    );

                    measured = true;
                    ++measuredIdleCoreCount;
                    measuredIdleCoreTotal += rawUsage;
                }
            }

            m_lastSysfsCoreIdleUsec[coreIndex] =
                sample.idleMicroseconds;

            double &smoothed =
                m_coreSmoothedPercent[coreIndex];

            if (measured) {
                smoothed =
                    smoothed <= 0.0
                    ? rawUsage
                    : (0.55 * rawUsage) +
                      (0.45 * smoothed);
            }

            const int displayedUsage =
                smoothed > 0.05
                ? qBound(1, qRound(smoothed), 100)
                : 0;

            QVariantMap core;
            core[QStringLiteral("index")] = coreIndex;
            core[QStringLiteral("name")] =
                QStringLiteral("CPU %1").arg(coreIndex);
            core[QStringLiteral("usage")] = displayedUsage;
            core[QStringLiteral("percent")] = displayedUsage;
            core[QStringLiteral("cpu")] = displayedUsage;
            core[QStringLiteral("load")] = displayedUsage;
            core[QStringLiteral("rawUsage")] = rawUsage;
            core[QStringLiteral("measured")] = measured;
            core[QStringLiteral("source")] =
                QStringLiteral("sysfs-cpuidle");
            core[QStringLiteral("frequency")] =
                formatCpuFrequencyKhz(sample.frequencyKhz);
            core[QStringLiteral("frequencyText")] =
                core.value(QStringLiteral("frequency"));

            fallbackCoreRows.append(core);
        }

        if (highestIdleCore >= 0) {
            const int required = highestIdleCore + 1;
            m_lastSysfsCoreIdleUsec.resize(required);
            m_coreSmoothedPercent.resize(required);
        }

        if (!idleCoreSamples.isEmpty())
            m_lastCoreIdleSampleMs = nowMs;

        if (!fallbackCoreRows.isEmpty())
            m_cpuCores = fallbackCoreRows;

        const double loadEstimate =
            qBound(
                0.0,
                100.0 * m_load1 /
                    static_cast<double>(logicalCoreCount),
                100.0
            );

        double fallbackPercent = loadEstimate;
        bool uptimeMeasured = false;

        if (uptimeSnapshot.valid &&
            m_lastCpuUptimeSeconds > 0.0 &&
            uptimeSnapshot.uptimeSeconds > m_lastCpuUptimeSeconds &&
            uptimeSnapshot.idleSeconds >= m_lastCpuIdleSeconds) {
            const double elapsedSeconds =
                uptimeSnapshot.uptimeSeconds -
                m_lastCpuUptimeSeconds;

            const double capacitySeconds =
                elapsedSeconds *
                static_cast<double>(logicalCoreCount);

            const double idleDelta =
                uptimeSnapshot.idleSeconds -
                m_lastCpuIdleSeconds;

            if (capacitySeconds > 0.0) {
                const double boundedIdle =
                    qBound(
                        0.0,
                        idleDelta,
                        capacitySeconds
                    );

                const double uptimePercent =
                    qBound(
                        0.0,
                        100.0 *
                            (capacitySeconds - boundedIdle) /
                            capacitySeconds,
                        100.0
                    );

                /*
                    A permanently zero idle counter is another restricted-proc
                    symptom. Trust it only when it actually advances, or when
                    load average independently confirms near-total saturation.
                */
                if (idleDelta > 0.0001 || loadEstimate >= 90.0) {
                    fallbackPercent = uptimePercent;
                    uptimeMeasured = true;
                }
            }
        }

        if (!uptimeMeasured && measuredIdleCoreCount > 0) {
            fallbackPercent =
                measuredIdleCoreTotal /
                static_cast<double>(measuredIdleCoreCount);
        }

        if (uptimeSnapshot.valid) {
            m_lastCpuUptimeSeconds = uptimeSnapshot.uptimeSeconds;
            m_lastCpuIdleSeconds = uptimeSnapshot.idleSeconds;
        }

        if (fallbackPercent > 0.01) {
            m_consecutiveZeroCpuSamples = 0;
            m_cpuSmoothedPercent =
                m_cpuSmoothedPercent <= 0.0
                ? fallbackPercent
                : (0.55 * fallbackPercent) +
                  (0.45 * m_cpuSmoothedPercent);
        } else {
            ++m_consecutiveZeroCpuSamples;
            m_cpuSmoothedPercent *= 0.72;

            if (m_cpuSmoothedPercent < 0.05)
                m_cpuSmoothedPercent = 0.0;
        }

        m_cpuPercent =
            m_cpuSmoothedPercent > 0.05
            ? qBound(
                  1,
                  qRound(m_cpuSmoothedPercent),
                  100
              )
            : 0;
        m_cpuValid = uptimeMeasured || measuredIdleCoreCount > 0;

        m_cpu =
            QString::number(m_cpuPercent) +
            QStringLiteral("%");

        m_lastCpuSampleMs = nowMs;

        if (!property("_cpuReadFailureLogged").toBool()) {
            qWarning()
                << "SystemMonitor: /proc/stat CPU counters are unavailable or zero;"
                << "aggregateSource="
                << (uptimeMeasured
                    ? "uptime"
                    : measuredIdleCoreCount > 0
                      ? "sysfs-cpuidle"
                      : "load-average")
                << "percent=" << m_cpuPercent
                << "perCoreRows=" << m_cpuCores.size()
                << "cores=" << logicalCoreCount;
            setProperty("_cpuReadFailureLogged", true);
        }

        if (oldCpu != m_cpu ||
            oldPercent != m_cpuPercent ||
            oldCores != m_cpuCores ||
            oldValid != m_cpuValid) {
            emit cpuMonitorChanged();
            emit systemChanged();
        }

        return;
    }

    if (property("_cpuReadFailureLogged").toBool()) {
        qInfo()
            << "SystemMonitor: /proc/stat CPU counters recovered";
    }

    setProperty("_cpuReadFailureLogged", false);

    /*
        First valid read establishes baselines and immediately publishes the
        discovered core model. A constructor single-shot and the regular timer
        provide subsequent deltas.
    */
    if (!m_cpuCounterBaselineReady) {
        QVariantList baselineCores;
        int highestCore = -1;

        for (const CpuCounterSnapshot &sample : samples) {
            if (sample.label == QStringLiteral("cpu")) {
                m_lastTotal = sample.total;
                m_lastIdle = sample.idle;
                continue;
            }

            const int coreIndex =
                sample.logicalCore;

            if (coreIndex < 0)
                continue;

            highestCore =
                qMax(highestCore, coreIndex);

            if (m_lastCoreTotal.size() <= coreIndex) {
                m_lastCoreTotal.resize(coreIndex + 1);
                m_lastCoreIdle.resize(coreIndex + 1);
                m_coreSmoothedPercent.resize(coreIndex + 1);
            }

            m_lastCoreTotal[coreIndex] =
                sample.total;
            m_lastCoreIdle[coreIndex] =
                sample.idle;
            m_coreSmoothedPercent[coreIndex] =
                0.0;

            quint64 frequencyKhz =
                readTrimmedFile(
                    QStringLiteral(
                        "/sys/devices/system/cpu/"
                        "cpu%1/cpufreq/scaling_cur_freq"
                    ).arg(coreIndex)
                ).toULongLong();

            if (frequencyKhz == 0) {
                frequencyKhz =
                    readTrimmedFile(
                        QStringLiteral(
                            "/sys/devices/system/cpu/"
                            "cpufreq/policy%1/scaling_cur_freq"
                        ).arg(coreIndex)
                    ).toULongLong();
            }

            QVariantMap core;
            core[QStringLiteral("index")] = coreIndex;
            core[QStringLiteral("name")] =
                QStringLiteral("CPU %1").arg(coreIndex);
            core[QStringLiteral("usage")] = 0;
            core[QStringLiteral("percent")] = 0;
            core[QStringLiteral("cpu")] = 0;
            core[QStringLiteral("load")] = 0;
            core[QStringLiteral("measured")] = false;
            core[QStringLiteral("frequency")] =
                formatCpuFrequencyKhz(frequencyKhz);
            core[QStringLiteral("frequencyText")] =
                core.value(QStringLiteral("frequency"));

            baselineCores.append(core);
        }

        if (highestCore >= 0) {
            const int required =
                highestCore + 1;
            m_lastCoreTotal.resize(required);
            m_lastCoreIdle.resize(required);
            m_coreSmoothedPercent.resize(required);
        }

        if (!baselineCores.isEmpty())
            m_cpuCores = baselineCores;

        if (uptimeSnapshot.valid) {
            m_lastCpuUptimeSeconds =
                uptimeSnapshot.uptimeSeconds;
            m_lastCpuIdleSeconds =
                uptimeSnapshot.idleSeconds;
        }

        m_cpuCounterBaselineReady =
            m_lastTotal > 0 || !baselineCores.isEmpty();

        m_lastCpuSampleMs = nowMs;

        if (oldCores != m_cpuCores) {
            emit cpuMonitorChanged();
            emit systemChanged();
        }

        return;
    }

    bool aggregateCounterMeasured = false;
    double aggregateCounterPercent = 0.0;

    QVariantList coreRows;
    int highestCoreIndex = -1;
    int measuredCoreCount = 0;
    double measuredCoreTotal = 0.0;

    for (const CpuCounterSnapshot &sample : samples) {
        if (sample.label == QStringLiteral("cpu")) {
            if (m_lastTotal > 0 &&
                sample.total > m_lastTotal) {
                const quint64 totalDelta =
                    sample.total - m_lastTotal;

                const quint64 idleDelta =
                    sample.idle >= m_lastIdle
                    ? sample.idle - m_lastIdle
                    : 0;

                const quint64 boundedIdleDelta =
                    qMin(idleDelta, totalDelta);

                const quint64 busyDelta =
                    totalDelta - boundedIdleDelta;

                aggregateCounterPercent =
                    totalDelta > 0
                    ? 100.0 *
                      static_cast<double>(busyDelta) /
                      static_cast<double>(totalDelta)
                    : 0.0;

                aggregateCounterMeasured = true;
            }

            m_lastTotal = sample.total;
            m_lastIdle = sample.idle;
            continue;
        }

        const int coreIndex =
            sample.logicalCore;

        if (coreIndex < 0)
            continue;

        highestCoreIndex =
            qMax(highestCoreIndex, coreIndex);

        if (m_lastCoreTotal.size() <= coreIndex) {
            m_lastCoreTotal.resize(coreIndex + 1);
            m_lastCoreIdle.resize(coreIndex + 1);
            m_coreSmoothedPercent.resize(coreIndex + 1);
        }

        const quint64 previousTotal =
            m_lastCoreTotal.at(coreIndex);
        const quint64 previousIdle =
            m_lastCoreIdle.at(coreIndex);

        bool measured = false;
        double rawUsage = 0.0;

        if (previousTotal > 0 &&
            sample.total > previousTotal) {
            const quint64 totalDelta =
                sample.total - previousTotal;

            const quint64 idleDelta =
                sample.idle >= previousIdle
                ? sample.idle - previousIdle
                : 0;

            const quint64 boundedIdleDelta =
                qMin(idleDelta, totalDelta);

            const quint64 busyDelta =
                totalDelta - boundedIdleDelta;

            rawUsage =
                totalDelta > 0
                ? 100.0 *
                  static_cast<double>(busyDelta) /
                  static_cast<double>(totalDelta)
                : 0.0;

            measured = true;
            ++measuredCoreCount;
            measuredCoreTotal += rawUsage;
        }

        m_lastCoreTotal[coreIndex] =
            sample.total;
        m_lastCoreIdle[coreIndex] =
            sample.idle;

        double &smoothed =
            m_coreSmoothedPercent[coreIndex];

        if (measured) {
            smoothed =
                smoothed <= 0.0
                ? rawUsage
                : (0.55 * rawUsage) +
                  (0.45 * smoothed);
        }

        const int displayedUsage =
            smoothed > 0.05
            ? qBound(
                  1,
                  qRound(smoothed),
                  100
              )
            : 0;

        quint64 frequencyKhz =
            readTrimmedFile(
                QStringLiteral(
                    "/sys/devices/system/cpu/"
                    "cpu%1/cpufreq/scaling_cur_freq"
                ).arg(coreIndex)
            ).toULongLong();

        if (frequencyKhz == 0) {
            frequencyKhz =
                readTrimmedFile(
                    QStringLiteral(
                        "/sys/devices/system/cpu/"
                        "cpufreq/policy%1/scaling_cur_freq"
                    ).arg(coreIndex)
                ).toULongLong();
        }

        QVariantMap core;
        core[QStringLiteral("index")] = coreIndex;
        core[QStringLiteral("name")] =
            QStringLiteral("CPU %1").arg(coreIndex);
        core[QStringLiteral("usage")] =
            displayedUsage;
        core[QStringLiteral("percent")] =
            displayedUsage;
        core[QStringLiteral("cpu")] =
            displayedUsage;
        core[QStringLiteral("load")] =
            displayedUsage;
        core[QStringLiteral("rawUsage")] =
            rawUsage;
        core[QStringLiteral("measured")] =
            measured;
        core[QStringLiteral("frequency")] =
            formatCpuFrequencyKhz(frequencyKhz);
        core[QStringLiteral("frequencyText")] =
            core.value(QStringLiteral("frequency"));

        coreRows.append(core);
    }

    if (highestCoreIndex >= 0) {
        const int required =
            highestCoreIndex + 1;

        m_lastCoreTotal.resize(required);
        m_lastCoreIdle.resize(required);
        m_coreSmoothedPercent.resize(required);
    }

    double uptimePercent = -1.0;

    if (uptimeSnapshot.valid &&
        m_lastCpuUptimeSeconds > 0.0 &&
        uptimeSnapshot.uptimeSeconds >
            m_lastCpuUptimeSeconds &&
        uptimeSnapshot.idleSeconds >=
            m_lastCpuIdleSeconds) {
        const double elapsedSeconds =
            uptimeSnapshot.uptimeSeconds -
            m_lastCpuUptimeSeconds;

        const double capacitySeconds =
            elapsedSeconds *
            static_cast<double>(
                logicalCoreCount
            );

        const double idleSeconds =
            qMin(
                uptimeSnapshot.idleSeconds -
                    m_lastCpuIdleSeconds,
                capacitySeconds
            );

        if (capacitySeconds > 0.0) {
            uptimePercent =
                100.0 *
                (capacitySeconds - idleSeconds) /
                capacitySeconds;
        }
    }

    if (uptimeSnapshot.valid) {
        m_lastCpuUptimeSeconds =
            uptimeSnapshot.uptimeSeconds;
        m_lastCpuIdleSeconds =
            uptimeSnapshot.idleSeconds;
    }

    double rawAggregate = -1.0;

    if (aggregateCounterMeasured)
        rawAggregate = aggregateCounterPercent;

    /*
        Prefer the independent uptime result when the /proc/stat result is
        unexpectedly zero but elapsed capacity shows actual work.
    */
    if (uptimePercent > rawAggregate)
        rawAggregate = uptimePercent;

    if (rawAggregate < 0.0 &&
        measuredCoreCount > 0) {
        rawAggregate =
            measuredCoreTotal /
            static_cast<double>(
                measuredCoreCount
            );
    }

    /*
        A nonzero load average means runnable or uninterruptible work exists.
        Use a conservative normalized estimate only after both cumulative
        measurements report zero, preventing a permanently dead 0% gauge.
    */
    if (rawAggregate <= 0.01 &&
        m_load1 > 0.0) {
        const double loadEstimate =
            qBound(
                0.0,
                100.0 *
                m_load1 /
                static_cast<double>(
                    logicalCoreCount
                ),
                100.0
            );

        if (loadEstimate > rawAggregate)
            rawAggregate = loadEstimate;
    }

    rawAggregate =
        qBound(
            0.0,
            rawAggregate,
            100.0
        );

    if (rawAggregate > 0.01) {
        m_consecutiveZeroCpuSamples = 0;

        m_cpuSmoothedPercent =
            m_cpuSmoothedPercent <= 0.0
            ? rawAggregate
            : (0.55 * rawAggregate) +
              (0.45 * m_cpuSmoothedPercent);
    } else {
        ++m_consecutiveZeroCpuSamples;

        /*
            Fade a previous real value instead of instantly dropping to zero
            on one tickless-idle interval. A truly idle system reaches zero
            naturally after consecutive samples.
        */
        m_cpuSmoothedPercent *= 0.72;

        if (m_cpuSmoothedPercent < 0.05)
            m_cpuSmoothedPercent = 0.0;
    }

    m_cpuPercent =
        m_cpuSmoothedPercent > 0.05
        ? qBound(
              1,
              qRound(m_cpuSmoothedPercent),
              100
          )
        : 0;
    m_cpuValid = aggregateCounterMeasured || uptimePercent >= 0.0 || measuredCoreCount > 0;

    m_cpu =
        QString::number(m_cpuPercent) +
        QStringLiteral("%");

    if (!coreRows.isEmpty())
        m_cpuCores = coreRows;

    m_lastCpuSampleMs = nowMs;

    if (!property("_cpuSampleConfirmed").toBool() &&
        aggregateCounterMeasured) {
        qInfo()
            << "SystemMonitor: CPU telemetry active"
            << "percent=" << m_cpuPercent
            << "cores=" << m_cpuCores.size();

        setProperty("_cpuSampleConfirmed", true);
    }

    if (m_consecutiveZeroCpuSamples == 5) {
        qWarning()
            << "SystemMonitor: CPU remained at zero for five samples"
            << "load1=" << m_load1
            << "cores=" << logicalCoreCount
            << "statMeasured=" << aggregateCounterMeasured
            << "uptimePercent=" << uptimePercent;
    }

    if (oldCpu != m_cpu ||
        oldPercent != m_cpuPercent ||
        oldCores != m_cpuCores ||
        oldValid != m_cpuValid) {
        emit cpuMonitorChanged();
        emit systemChanged();
    }
}

void SystemMonitor::updateCpuDetails()
{
    const QString oldFrequency = m_cpuFrequency;
    const QString oldGovernor = m_cpuGovernor;
    const quint64 oldFrequencyHz = m_cpuFrequencyHz;
    const QString oldModel = m_cpuModel;

    m_cpuFrequencyHz = detectCpuFrequencyHz();
    m_cpuFrequency = m_cpuFrequencyHz > 0 ? formatCpuFrequencyKhz(m_cpuFrequencyHz / 1000) : QStringLiteral("--");
    m_cpuGovernor = detectCpuGovernor();
    QFile cpuInfo(QStringLiteral("/proc/cpuinfo"));
    if (cpuInfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!cpuInfo.atEnd()) {
            const QString line = QString::fromUtf8(cpuInfo.readLine()).trimmed();
            const int colon = line.indexOf(QLatin1Char(':'));
            if (colon > 0 && (line.left(colon).trimmed().compare(QStringLiteral("model name"), Qt::CaseInsensitive) == 0
                              || line.left(colon).trimmed().compare(QStringLiteral("model"), Qt::CaseInsensitive) == 0)) {
                m_cpuModel = line.mid(colon + 1).trimmed();
                if (!m_cpuModel.isEmpty()) break;
            }
        }
    }
#if defined(NEUTRONOS_PLATFORM_GEMINI)
    if (m_cpuModel.isEmpty()) m_cpuModel = GeminiHardware::model();
#else
    if (m_cpuModel.isEmpty()) {
        QFile deviceModel(QStringLiteral("/proc/device-tree/model"));
        if (deviceModel.open(QIODevice::ReadOnly)) {
            QByteArray modelBytes = deviceModel.readAll();
            modelBytes.replace('\0', ' ');
            m_cpuModel = QString::fromUtf8(modelBytes).trimmed();
        }
    }
#endif
    if (m_cpuModel.isEmpty()) m_cpuModel = QStringLiteral("--");

    if (oldFrequency != m_cpuFrequency || oldGovernor != m_cpuGovernor ||
        oldFrequencyHz != m_cpuFrequencyHz || oldModel != m_cpuModel)
        emit cpuMonitorChanged();
}

void SystemMonitor::updateLoadAverage()
{
    const QString oldText = m_loadAverage;
    const double old1 = m_load1;
    const double old5 = m_load5;
    const double old15 = m_load15;

    QFile file(QStringLiteral("/proc/loadavg"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    const QStringList values = QString::fromUtf8(file.readLine())
                                   .simplified()
                                   .split(QStringLiteral(" "));
    file.close();

    if (values.size() < 3)
        return;

    bool ok1 = false;
    bool ok5 = false;
    bool ok15 = false;

    const double load1Value = values[0].toDouble(&ok1);
    const double load5Value = values[1].toDouble(&ok5);
    const double load15Value = values[2].toDouble(&ok15);

    if (!ok1 || !ok5 || !ok15)
        return;

    m_load1 = load1Value;
    m_load5 = load5Value;
    m_load15 = load15Value;
    m_loadAverage = QStringLiteral("%1  %2  %3")
                        .arg(m_load1, 0, 'f', 2)
                        .arg(m_load5, 0, 'f', 2)
                        .arg(m_load15, 0, 'f', 2);

    if (oldText != m_loadAverage ||
        !qFuzzyCompare(old1 + 1.0, m_load1 + 1.0) ||
        !qFuzzyCompare(old5 + 1.0, m_load5 + 1.0) ||
        !qFuzzyCompare(old15 + 1.0, m_load15 + 1.0)) {
        emit cpuMonitorChanged();
    }
}

void SystemMonitor::updateProcessCount()
{
    const int oldCount = m_processCount;
    const QStringList entries = QDir(QStringLiteral("/proc")).entryList(
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::NoSort
    );

    int count = 0;

    for (const QString &entry : entries) {
        bool numeric = false;
        entry.toInt(&numeric);
        if (numeric)
            ++count;
    }

    m_processCount = count;

    if (oldCount != m_processCount)
        emit processDataChanged();
}

QString SystemMonitor::detectCpuFrequency() const
{
    const quint64 hz = detectCpuFrequencyHz();
    return hz > 0 ? formatCpuFrequencyKhz(hz / 1000) : QStringLiteral("--");
}

quint64 SystemMonitor::detectCpuFrequencyHz() const
{
    quint64 totalKhz = 0;
    int samples = 0;

    QDir cpuDir(QStringLiteral("/sys/devices/system/cpu"));
    const QStringList cpuEntries = cpuDir.entryList(
        QStringList() << QStringLiteral("cpu[0-9]*"),
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::Name
    );

    const QRegularExpression cpuPattern(QStringLiteral("^cpu\\d+$"));

    for (const QString &entry : cpuEntries) {
        if (!cpuPattern.match(entry).hasMatch())
            continue;

        bool ok = false;
        const quint64 khz = readTrimmedFile(
            cpuDir.filePath(entry + QStringLiteral("/cpufreq/scaling_cur_freq"))
        ).toULongLong(&ok);

        if (ok && khz > 0) {
            totalKhz += khz;
            ++samples;
        }
    }

    if (samples > 0)
        return (totalKhz / static_cast<quint64>(samples)) * 1000;

    QFile cpuInfo(QStringLiteral("/proc/cpuinfo"));
    if (cpuInfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream stream(&cpuInfo);
        double totalMhz = 0.0;
        int count = 0;

        while (!stream.atEnd()) {
            const QString line = stream.readLine();
            if (!line.startsWith(QStringLiteral("cpu MHz"), Qt::CaseInsensitive))
                continue;

            const int colon = line.indexOf(QLatin1Char(':'));
            if (colon < 0)
                continue;

            bool ok = false;
            const double mhz = line.mid(colon + 1).trimmed().toDouble(&ok);

            if (ok && mhz > 0.0) {
                totalMhz += mhz;
                ++count;
            }
        }

        if (count > 0) {
            return static_cast<quint64>((totalMhz / static_cast<double>(count)) * 1000000.0);
        }
    }

    return 0;
}

QString SystemMonitor::detectCpuGovernor() const
{
    const QStringList candidates = {
        QStringLiteral("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
        QStringLiteral("/sys/devices/system/cpu/cpufreq/policy0/scaling_governor")
    };

    for (const QString &path : candidates) {
        const QString value = readTrimmedFile(path).trimmed().toLower();

        if (value.isEmpty())
            continue;

        /*
            NeutronOS presents product-facing power-mode names rather than
            leaking raw Linux governor names into the System Overview UI.
        */
        if (value == QStringLiteral("ondemand") ||
                value == QStringLiteral("schedutil") ||
                value == QStringLiteral("conservative")) {
            return QStringLiteral("Normal");
        }

        if (value == QStringLiteral("performance"))
            return QStringLiteral("Performance");

        if (value == QStringLiteral("powersave"))
            return QStringLiteral("Eco");

        return value;
    }

    return QStringLiteral("--");
}

/* Memory */

void SystemMonitor::updateRam()
{
    const QString oldRam = m_ram;
    const int oldPercent = m_ramPercent;
    const QString oldUsed = m_ramUsed;
    const QString oldTotal = m_ramTotal;
    const QString oldAvailable = m_ramAvailable;
    const QString oldCached = m_memoryCached;
    const QString oldBuffers = m_memoryBuffers;
    const QString oldSwapUsed = m_swapUsed;
    const QString oldSwapTotal = m_swapTotal;
    const quint64 oldUsedBytes = m_ramUsedBytes;
    const quint64 oldTotalBytes = m_ramTotalBytes;
    const quint64 oldAvailableBytes = m_ramAvailableBytes;
    const quint64 oldCachedBytes = m_memoryCachedBytes;
    const quint64 oldBuffersBytes = m_memoryBuffersBytes;
    const quint64 oldSwapUsedBytes = m_swapUsedBytes;
    const quint64 oldSwapTotalBytes = m_swapTotalBytes;
    const int oldSwapPercent = m_swapPercent;
    const int oldPressure = m_memoryPressurePercent;
    const bool oldMemoryValid = m_memoryValid;

    const QHash<QString, quint64> memory =
        readMemInfoKb();

    quint64 totalKb =
        memory.value(QStringLiteral("MemTotal"));
    quint64 availableKb =
        memory.value(QStringLiteral("MemAvailable"));
    const quint64 freeKb =
        memory.value(QStringLiteral("MemFree"));
    quint64 buffersKb =
        memory.value(QStringLiteral("Buffers"));
    const quint64 cachedKb =
        memory.value(QStringLiteral("Cached"));
    const quint64 reclaimableKb =
        memory.value(QStringLiteral("SReclaimable"));
    const quint64 sharedKb =
        memory.value(QStringLiteral("Shmem"));
    quint64 swapTotalKb =
        memory.value(QStringLiteral("SwapTotal"));
    quint64 swapFreeKb =
        memory.value(QStringLiteral("SwapFree"));

    quint64 effectiveCacheKb =
        cachedKb + reclaimableKb;

    if (effectiveCacheKb > sharedKb)
        effectiveCacheKb -= sharedKb;
    else
        effectiveCacheKb = 0;

    if (availableKb == 0 && totalKb > 0) {
        availableKb =
            freeKb +
            buffersKb +
            effectiveCacheKb;
    }

#ifdef Q_OS_LINUX
    /*
        MemAvailable is the only trustworthy source for the user-facing
        "usable RAM remaining" value. The sysinfo fallback exposes free RAM
        and buffers but not Linux's reclaimable page cache, so presenting it
        as MemAvailable can overstate usage by tens of percentage points.

        If /proc/meminfo is temporarily unavailable during very early startup,
        preserve the last valid sample and retry on the next backend tick.
        Never replace a correct sample with an intentionally incomplete one.
    */
    const bool hasKernelMemorySnapshot =
        totalKb > 0 &&
        memory.contains(QStringLiteral("MemAvailable"));

    if (!hasKernelMemorySnapshot) {
        m_memoryValid = false;
        if (!property("_meminfoWarningLogged").toBool()) {
            qWarning()
                << "SystemMonitor: /proc/meminfo or MemAvailable is unavailable;"
                << "preserving the last valid RAM sample";
            setProperty("_meminfoWarningLogged", true);
        }

        if (oldMemoryValid != m_memoryValid)
            emit memoryMonitorChanged();
        return;
    }

    if (!property("_meminfoActiveLogged").toBool()) {
        qInfo()
            << "SystemMonitor: memory telemetry active"
            << "totalKiB=" << totalKb
            << "availableKiB=" << availableKb;
        setProperty("_meminfoActiveLogged", true);
    }
#else
    if (totalKb == 0) {
        /*
            Desktop development fallback only. Values are intentionally
            plausible and stable; Raspberry Pi/Linux builds always use
            /proc/meminfo with sysinfo as the kernel fallback.
        */
        totalKb = 8ULL * 1024ULL * 1024ULL;
        availableKb = 5ULL * 1024ULL * 1024ULL;
        buffersKb = 128ULL * 1024ULL;
        effectiveCacheKb = 1024ULL * 1024ULL;
        swapTotalKb = 2ULL * 1024ULL * 1024ULL;
        swapFreeKb = 1536ULL * 1024ULL;
    }
#endif

    if (totalKb == 0)
        return;

    m_memoryValid = true;

    availableKb =
        qMin(
            availableKb,
            totalKb
        );

    const quint64 usedKb =
        totalKb - availableKb;

    const quint64 swapUsedKb =
        swapTotalKb >= swapFreeKb
        ? swapTotalKb - swapFreeKb
        : 0;

    m_ramTotalBytes = totalKb * 1024;
    m_ramAvailableBytes = availableKb * 1024;
    m_ramUsedBytes = usedKb * 1024;
    m_memoryCachedBytes = effectiveCacheKb * 1024;
    m_memoryBuffersBytes = buffersKb * 1024;
    m_swapTotalBytes = swapTotalKb * 1024;
    m_swapUsedBytes = swapUsedKb * 1024;

    m_ramPercent =
        qBound(
            0,
            qRound(
                100.0 *
                static_cast<double>(usedKb) /
                static_cast<double>(totalKb)
            ),
            100
        );

    m_swapPercent =
        swapTotalKb > 0
        ? qBound(
              0,
              qRound(
                  100.0 *
                  static_cast<double>(swapUsedKb) /
                  static_cast<double>(swapTotalKb)
              ),
              100
          )
        : 0;

    m_ramUsed =
        formatBytes(m_ramUsedBytes);
    m_ramTotal =
        formatBytes(m_ramTotalBytes);
    m_ramAvailable =
        formatBytes(m_ramAvailableBytes);
    m_memoryCached =
        formatBytes(m_memoryCachedBytes);
    m_memoryBuffers =
        formatBytes(m_memoryBuffersBytes);
    m_swapUsed =
        formatBytes(m_swapUsedBytes);
    m_swapTotal =
        formatBytes(m_swapTotalBytes);
    m_ram =
        m_ramUsed +
        QStringLiteral(" / ") +
        m_ramTotal;

    updateMemoryPressure();

    const bool changed =
        oldRam != m_ram ||
        oldPercent != m_ramPercent ||
        oldUsed != m_ramUsed ||
        oldTotal != m_ramTotal ||
        oldAvailable != m_ramAvailable ||
        oldCached != m_memoryCached ||
        oldBuffers != m_memoryBuffers ||
        oldSwapUsed != m_swapUsed ||
        oldSwapTotal != m_swapTotal ||
        oldUsedBytes != m_ramUsedBytes ||
        oldTotalBytes != m_ramTotalBytes ||
        oldAvailableBytes != m_ramAvailableBytes ||
        oldCachedBytes != m_memoryCachedBytes ||
        oldBuffersBytes != m_memoryBuffersBytes ||
        oldSwapUsedBytes != m_swapUsedBytes ||
        oldSwapTotalBytes != m_swapTotalBytes ||
        oldSwapPercent != m_swapPercent ||
        oldPressure != m_memoryPressurePercent ||
        oldMemoryValid != m_memoryValid;

    if (changed) {
        emit memoryMonitorChanged();
        emit systemChanged();
    }
}

void SystemMonitor::updateMemoryPressure()
{
    QFile file(QStringLiteral("/proc/pressure/memory"));

    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString output = QString::fromUtf8(file.readAll());
        file.close();

        const QRegularExpression pattern(
            QStringLiteral("some\\s+avg10=([0-9.]+)")
        );

        const QRegularExpressionMatch match = pattern.match(output);

        if (match.hasMatch()) {
            m_memoryPressurePercent = qBound(
                0,
                qRound(match.captured(1).toDouble()),
                100
            );
            return;
        }
    }

    const int ramPressure = m_ramPercent <= 65
        ? 0
        : qBound(
              0,
              qRound(
                  static_cast<double>(m_ramPercent - 65) *
                  100.0 / 35.0
              ),
              100
          );

    const int swapPenalty = qRound(static_cast<double>(m_swapPercent) * 0.25);
    m_memoryPressurePercent = qBound(0, ramPressure + swapPenalty, 100);
}

/* Storage */

void SystemMonitor::updateMounts()
{
    const QVariantList oldMounts = m_mounts;
    const QString oldBoot = m_bootStorage;
    const int oldBootPercent = m_bootStoragePercent;
    const QString oldMedia = m_mediaStorage;
    const int oldMediaPercent = m_mediaStoragePercent;

    QVariantList result;
    const QHash<QString, QString> uuidMap = deviceUuidMap();
    const QList<QStorageInfo> volumes = QStorageInfo::mountedVolumes();

    for (const QStorageInfo &storage : volumes) {
        if (!storage.isValid() || !storage.isReady() || storage.bytesTotal() <= 0)
            continue;

        const QString mountPoint = QDir::cleanPath(storage.rootPath());
        QString device = QString::fromUtf8(storage.device());
        const QFileInfo deviceInfo(device);
        const QString canonical = deviceInfo.canonicalFilePath();

        if (!canonical.isEmpty())
            device = canonical;

        const QString fsType = QString::fromUtf8(storage.fileSystemType());

        if (shouldIgnoreMount(mountPoint, device, fsType))
            continue;

        const quint64 total = static_cast<quint64>(storage.bytesTotal());
        const quint64 available = static_cast<quint64>(
            qMax<qint64>(0, storage.bytesAvailable())
        );
        const quint64 used = total >= available ? total - available : 0;
        const int percent = total > 0
            ? qBound(
                  0,
                  qRound(
                      100.0 * static_cast<double>(used) /
                      static_cast<double>(total)
                  ),
                  100
              )
            : 0;

        const QString name = mountName(mountPoint, device, fsType);
        const QString uuid = uuidMap.value(device);
        const QString stableId = !uuid.isEmpty()
            ? QStringLiteral("uuid:") + uuid
            : !device.isEmpty()
              ? QStringLiteral("device:") + device
              : QStringLiteral("mount:") + mountPoint;

        const QString usedText = formatBytes(used);
        const QString totalText = formatBytes(total);
        const QString availableText = formatBytes(available);
        const QString text = usedText + QStringLiteral(" / ") + totalText;
        const bool isBoot = mountPoint == QStringLiteral("/");
        const bool isMedia =
            mountPoint.startsWith(QStringLiteral("/mnt/")) ||
            mountPoint.startsWith(QStringLiteral("/media/"));

        QVariantMap mount;
        mount[QStringLiteral("id")] = stableId;
        mount[QStringLiteral("stableId")] = stableId;
        mount[QStringLiteral("deviceId")] = stableId;
        mount[QStringLiteral("uuid")] = uuid;
        mount[QStringLiteral("name")] = name;
        mount[QStringLiteral("displayName")] = name;
        mount[QStringLiteral("label")] = name;
        mount[QStringLiteral("mountPoint")] = mountPoint;
        mount[QStringLiteral("mount")] = mountPoint;
        mount[QStringLiteral("path")] = mountPoint;
        mount[QStringLiteral("device")] = device;
        mount[QStringLiteral("devicePath")] = device;
        mount[QStringLiteral("filesystem")] = fsType;
        mount[QStringLiteral("fs")] = fsType;
        mount[QStringLiteral("fsType")] = fsType;
        mount[QStringLiteral("used")] = usedText;
        mount[QStringLiteral("usedText")] = usedText;
        mount[QStringLiteral("usedHuman")] = usedText;
        mount[QStringLiteral("usedBytes")] = static_cast<qulonglong>(used);
        mount[QStringLiteral("total")] = totalText;
        mount[QStringLiteral("totalText")] = totalText;
        mount[QStringLiteral("totalHuman")] = totalText;
        mount[QStringLiteral("totalBytes")] = static_cast<qulonglong>(total);
        mount[QStringLiteral("size")] = totalText;
        mount[QStringLiteral("sizeBytes")] = static_cast<qulonglong>(total);
        mount[QStringLiteral("available")] = availableText;
        mount[QStringLiteral("availableBytes")] = static_cast<qulonglong>(available);
        mount[QStringLiteral("text")] = text;
        mount[QStringLiteral("percent")] = percent;
        mount[QStringLiteral("usedPercent")] = percent;
        mount[QStringLiteral("usagePercent")] = percent;
        mount[QStringLiteral("usage")] = percent;
        mount[QStringLiteral("connected")] = true;
        mount[QStringLiteral("mounted")] = true;
        mount[QStringLiteral("isBoot")] = isBoot;
        mount[QStringLiteral("isMedia")] = isMedia;
        mount[QStringLiteral("removable")] =
            device.startsWith(QStringLiteral("/dev/sd")) ||
            device.startsWith(QStringLiteral("/dev/usb"));

        result.append(mount);
    }

    std::sort(result.begin(), result.end(),
              [](const QVariant &left, const QVariant &right) {
        const QVariantMap l = left.toMap();
        const QVariantMap r = right.toMap();

        const bool lBoot = l.value(QStringLiteral("isBoot")).toBool();
        const bool rBoot = r.value(QStringLiteral("isBoot")).toBool();

        if (lBoot != rBoot)
            return lBoot;

        const bool lMedia = l.value(QStringLiteral("isMedia")).toBool();
        const bool rMedia = r.value(QStringLiteral("isMedia")).toBool();

        if (lMedia != rMedia)
            return lMedia;

        const qulonglong lSize = l.value(QStringLiteral("totalBytes")).toULongLong();
        const qulonglong rSize = r.value(QStringLiteral("totalBytes")).toULongLong();

        if (lSize != rSize)
            return lSize > rSize;

        return QString::localeAwareCompare(
                   l.value(QStringLiteral("name")).toString(),
                   r.value(QStringLiteral("name")).toString()
               ) < 0;
    });

    m_mounts = result;
    rebuildStorageDisplaySlots();

    if (oldMounts != m_mounts ||
        oldBoot != m_bootStorage ||
        oldBootPercent != m_bootStoragePercent ||
        oldMedia != m_mediaStorage ||
        oldMediaPercent != m_mediaStoragePercent) {
        emit storageChanged();
    }
}

void SystemMonitor::rebuildStorageDisplaySlots()
{
    const QStringList oldIds = m_displayedMountIds;
    const QVariantList oldSlots = m_storageDisplaySlots;

    QString bootId;
    QString preferredExpansionId;
    qulonglong preferredExpansionSize = 0;
    bool preferredExpansionIsMedia = false;

    // The System Overview has fixed semantic slots: slot zero is always the
    // operating-system/boot filesystem and slot one is expansion storage.
    // Rebuild those roles on every refresh instead of trusting stale saved
    // selections, which can otherwise make two partitions from the same
    // external disk appear as both dashboard cards.
    for (const QVariant &entry : m_mounts) {
        const QVariantMap mount = entry.toMap();
        const QString id = stableMountId(mount);
        if (id.isEmpty())
            continue;

        if (mount.value(QStringLiteral("isBoot")).toBool()) {
            bootId = id;
            continue;
        }

        const bool isMedia = mount.value(QStringLiteral("isMedia")).toBool();
        const qulonglong size = mount.value(QStringLiteral("totalBytes")).toULongLong();
        if (preferredExpansionId.isEmpty()
                || (isMedia && !preferredExpansionIsMedia)
                || (isMedia == preferredExpansionIsMedia && size > preferredExpansionSize)) {
            preferredExpansionId = id;
            preferredExpansionSize = size;
            preferredExpansionIsMedia = isMedia;
        }
    }

    QString savedExpansionId;
    for (const QString &savedId : std::as_const(m_displayedMountIds)) {
        if (savedId.isEmpty() || savedId == bootId)
            continue;
        for (const QVariant &entry : m_mounts) {
            const QVariantMap mount = entry.toMap();
            if (stableMountId(mount) == savedId
                    && !mount.value(QStringLiteral("isBoot")).toBool()) {
                savedExpansionId = savedId;
                break;
            }
        }
        if (!savedExpansionId.isEmpty())
            break;
    }

    QStringList normalizedIds;
    if (!bootId.isEmpty())
        normalizedIds.append(bootId);

    const QString expansionId = !savedExpansionId.isEmpty()
        ? savedExpansionId
        : preferredExpansionId;
    if (!expansionId.isEmpty() && expansionId != bootId)
        normalizedIds.append(expansionId);

    // Fall back gracefully on unusual systems where the root filesystem was
    // not reported by the mount collector, while still avoiding duplicates.
    for (const QVariant &entry : m_mounts) {
        if (normalizedIds.size() >= 2)
            break;
        const QString id = stableMountId(entry.toMap());
        if (!id.isEmpty() && !normalizedIds.contains(id))
            normalizedIds.append(id);
    }

    while (normalizedIds.size() > 2)
        normalizedIds.removeLast();
    m_displayedMountIds = normalizedIds;

    QVariantList displaySlots;

    for (int index = 0; index < m_displayedMountIds.size(); ++index) {
        const QString id = m_displayedMountIds[index];
        QVariantMap resolved;
        bool found = false;

        for (const QVariant &entry : m_mounts) {
            const QVariantMap mount = entry.toMap();

            if (stableMountId(mount) == id) {
                resolved = mount;
                found = true;
                break;
            }
        }

        if (!found) {
            resolved[QStringLiteral("id")] = id;
            resolved[QStringLiteral("stableId")] = id;
            resolved[QStringLiteral("deviceId")] = id;
            resolved[QStringLiteral("name")] = QStringLiteral("Unavailable Device");
            resolved[QStringLiteral("displayName")] = QStringLiteral("Unavailable Device");
            resolved[QStringLiteral("label")] = QStringLiteral("Unavailable Device");
            resolved[QStringLiteral("connected")] = false;
            resolved[QStringLiteral("mounted")] = false;
            resolved[QStringLiteral("percent")] = 0;
            resolved[QStringLiteral("usedPercent")] = 0;
            resolved[QStringLiteral("used")] = QStringLiteral("--");
            resolved[QStringLiteral("total")] = QStringLiteral("--");
            resolved[QStringLiteral("text")] = QStringLiteral("--");
        }

        // Dashboard labels describe the role, while the Storage app still
        // retains and displays the real vendor/model/device fields.
        if (index == 0 && resolved.value(QStringLiteral("isBoot")).toBool()) {
            resolved[QStringLiteral("name")] = QStringLiteral("Boot");
            resolved[QStringLiteral("displayName")] = QStringLiteral("Boot");
            resolved[QStringLiteral("label")] = QStringLiteral("Boot");
            resolved[QStringLiteral("role")] = QStringLiteral("BOOT");
        } else if (index == 1 && found) {
            // Mounted media is identified by its real volume/mount name
            // (for example NeutronMedia), not the generic Expansion role.
            resolved[QStringLiteral("role")] = QStringLiteral("EXPANSION");
        }

        resolved[QStringLiteral("slot")] = index;
        displaySlots.append(resolved);
    }

    while (displaySlots.size() < 2) {
        QVariantMap unavailable;
        const int slot = displaySlots.size();
        unavailable.insert(QStringLiteral("id"), slot == 0 ? QStringLiteral("boot-unavailable")
                                                            : QStringLiteral("media-unavailable"));
        unavailable.insert(QStringLiteral("label"), slot == 0 ? QStringLiteral("Boot")
                                                               : QStringLiteral("Media Unavailable"));
        unavailable.insert(QStringLiteral("role"), slot == 0 ? QStringLiteral("BOOT")
                                                              : QStringLiteral("EXPANSION"));
        unavailable.insert(QStringLiteral("slot"), slot);
        unavailable.insert(QStringLiteral("connected"), false);
        unavailable.insert(QStringLiteral("mounted"), false);
        unavailable.insert(QStringLiteral("usedPercent"), 0);
        unavailable.insert(QStringLiteral("percent"), 0);
        unavailable.insert(QStringLiteral("used"), QStringLiteral("--"));
        unavailable.insert(QStringLiteral("available"), QStringLiteral("--"));
        unavailable.insert(QStringLiteral("total"), QStringLiteral("--"));
        unavailable.insert(QStringLiteral("filesystem"), QStringLiteral("--"));
        displaySlots.append(unavailable);
    }

    m_storageDisplaySlots = displaySlots;

    auto assignCompatibilitySlot = [](const QVariantList &slotList,
                                      int index,
                                      QString &text,
                                      int &percent) {
        if (index < 0 || index >= slotList.size()) {
            text = QStringLiteral("--");
            percent = 0;
            return;
        }

        const QVariantMap slot = slotList[index].toMap();

        if (!slot.value(QStringLiteral("connected")).toBool()) {
            text = QStringLiteral("--");
            percent = 0;
            return;
        }

        text = slot.value(QStringLiteral("text")).toString();
        if (text.isEmpty()) {
            text = slot.value(QStringLiteral("used")).toString() +
                   QStringLiteral(" / ") +
                   slot.value(QStringLiteral("total")).toString();
        }

        percent = slot.value(QStringLiteral("percent")).toInt();
    };

    assignCompatibilitySlot(
        m_storageDisplaySlots, 0, m_bootStorage, m_bootStoragePercent
    );
    assignCompatibilitySlot(
        m_storageDisplaySlots, 1, m_mediaStorage, m_mediaStoragePercent
    );

    if (oldIds != m_displayedMountIds)
        saveDisplayedMountIds();

    if (oldIds != m_displayedMountIds || oldSlots != m_storageDisplaySlots)
        emit displayedMountIdsChanged();
}

void SystemMonitor::loadDisplayedMountIds()
{
    m_displayedMountIds.clear();

    QFile file(storageSelectionFilePath());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    QJsonParseError error;
    const QJsonDocument document =
        QJsonDocument::fromJson(file.readAll(), &error);
    file.close();

    if (error.error != QJsonParseError::NoError)
        return;

    QJsonArray ids;

    if (document.isArray())
        ids = document.array();
    else if (document.isObject())
        ids = document.object().value(QStringLiteral("ids")).toArray();

    for (const QJsonValue &entry : ids) {
        const QString id = entry.toString().trimmed();

        if (!id.isEmpty() && !m_displayedMountIds.contains(id))
            m_displayedMountIds.append(id);

        if (m_displayedMountIds.size() == 2)
            break;
    }
}

bool SystemMonitor::saveDisplayedMountIds() const
{
    const QString path = storageSelectionFilePath();
    const QFileInfo info(path);

    if (!QDir().mkpath(info.absolutePath()))
        return false;

    QJsonArray ids;
    for (const QString &id : m_displayedMountIds)
        ids.append(id);

    QJsonObject object;
    object.insert(QStringLiteral("version"), 1);
    object.insert(QStringLiteral("ids"), ids);

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    const QByteArray data = QJsonDocument(object).toJson(QJsonDocument::Compact);

    if (file.write(data) != data.size()) {
        file.cancelWriting();
        return false;
    }

    return file.commit();
}

QStringList SystemMonitor::parseDisplayedMountIds(const QVariant &payload) const
{
    QStringList result;

    auto appendUnique = [&result](const QString &value) {
        const QString id = value.trimmed();
        if (!id.isEmpty() && !result.contains(id))
            result.append(id);
    };

    const QVariantMap map = payload.toMap();

    if (!map.isEmpty()) {
        const QVariantList ids = map.value(QStringLiteral("ids")).toList();
        for (const QVariant &entry : ids)
            appendUnique(entry.toString());

        appendUnique(map.value(QStringLiteral("slot1Id")).toString());
        appendUnique(map.value(QStringLiteral("slot2Id")).toString());

        const QVariantList requestedSlots = map.value(QStringLiteral("slots")).toList();

        for (const QVariant &slotValue : requestedSlots) {
            const QVariantMap slot = slotValue.toMap();
            QString id = slot.value(QStringLiteral("id")).toString();

            if (id.trimmed().isEmpty())
                id = stableMountId(slot.value(QStringLiteral("mount")).toMap());

            appendUnique(id);
        }
    }

    for (const QVariant &entry : payload.toList()) {
        const QVariantMap item = entry.toMap();
        appendUnique(item.isEmpty() ? entry.toString() : stableMountId(item));
    }

    for (const QString &entry : payload.toStringList())
        appendUnique(entry);

    while (result.size() > 2)
        result.removeLast();

    return result;
}

QString SystemMonitor::mountName(const QString &mountPoint,
                                 const QString &device,
                                 const QString &fsType) const
{
    Q_UNUSED(fsType)

    if (mountPoint == QStringLiteral("/"))
        return QStringLiteral("Boot");

    QStorageInfo storage(mountPoint);
    QString label = storage.displayName().trimmed();

    if (label.isEmpty())
        label = storage.name().trimmed();

    if (!label.isEmpty() &&
        label.compare(QStringLiteral("rootfs"), Qt::CaseInsensitive) != 0 &&
        label.compare(QStringLiteral("overlay"), Qt::CaseInsensitive) != 0) {
        return label;
    }

    if (mountPoint.startsWith(QStringLiteral("/mnt/")) ||
        mountPoint.startsWith(QStringLiteral("/media/"))) {
        const QString name = QFileInfo(mountPoint).fileName();
        if (!name.isEmpty())
            return name;
    }

    if (!device.isEmpty()) {
        const QString name = QFileInfo(device).fileName();
        if (!name.isEmpty())
            return name;
    }

    return mountPoint;
}

QString SystemMonitor::stableMountId(const QVariantMap &mount) const
{
    const QStringList keys = {
        QStringLiteral("id"),
        QStringLiteral("stableId"),
        QStringLiteral("deviceId"),
        QStringLiteral("uuid"),
        QStringLiteral("device"),
        QStringLiteral("devicePath"),
        QStringLiteral("mountPoint"),
        QStringLiteral("mount"),
        QStringLiteral("path"),
        QStringLiteral("name")
    };

    for (const QString &key : keys) {
        QString value = mount.value(key).toString().trimmed();

        if (value.isEmpty())
            continue;

        if (key == QStringLiteral("uuid") &&
            !value.startsWith(QStringLiteral("uuid:"))) {
            value.prepend(QStringLiteral("uuid:"));
        }

        return value;
    }

    return {};
}

bool SystemMonitor::shouldIgnoreMount(const QString &mountPoint,
                                      const QString &device,
                                      const QString &fsType) const
{
    if (mountPoint.isEmpty())
        return true;

    if (mountPoint == QStringLiteral("/"))
        return false;

    if (mountPoint.startsWith(QStringLiteral("/mnt/")) ||
        mountPoint.startsWith(QStringLiteral("/media/"))) {
        return false;
    }

    const QString lowerMount = mountPoint.toLower();
    const QString lowerDevice = device.toLower();
    const QString lowerFs = fsType.toLower();

    const QStringList ignoredFileSystems = {
        QStringLiteral("tmpfs"),
        QStringLiteral("devtmpfs"),
        QStringLiteral("proc"),
        QStringLiteral("sysfs"),
        QStringLiteral("cgroup"),
        QStringLiteral("overlay"),
        QStringLiteral("squashfs"),
        QStringLiteral("tracefs"),
        QStringLiteral("debugfs"),
        QStringLiteral("fusectl"),
        QStringLiteral("ramfs"),
        QStringLiteral("nsfs"),
        QStringLiteral("autofs")
    };

    for (const QString &ignored : ignoredFileSystems) {
        if (lowerFs.contains(ignored))
            return true;
    }

    const QStringList ignoredPrefixes = {
        QStringLiteral("/proc"),
        QStringLiteral("/sys"),
        QStringLiteral("/run"),
        QStringLiteral("/dev"),
        QStringLiteral("/tmp"),
        QStringLiteral("/var/tmp"),
        QStringLiteral("/boot/firmware"),
        QStringLiteral("/var/lib/docker"),
        QStringLiteral("/snap")
    };

    for (const QString &prefix : ignoredPrefixes) {
        if (lowerMount.startsWith(prefix))
            return true;
    }

    if (lowerDevice.contains(QStringLiteral("overlay")) ||
        lowerDevice.contains(QStringLiteral("tmpfs"))) {
        return true;
    }

    return !lowerDevice.startsWith(QStringLiteral("/dev/"));
}

/* Temperature */

void SystemMonitor::updateTemperature()
{
    const QString oldText = m_temperature;
    const double oldValue = m_cpuTemperatureF;
    const bool oldValid = m_temperatureValid;

#if defined(NEUTRONOS_PLATFORM_GEMINI)
    const auto temperature = GeminiHardware::cpuTemperature();
    m_temperatureValid = temperature.available && TelemetryMath::validCelsius(temperature.celsius);
    m_cpuTemperatureC = m_temperatureValid ? temperature.celsius : 0.0;
    m_cpuTemperatureF = m_temperatureValid ? TelemetryMath::fahrenheitFromCelsius(temperature.celsius) : 0.0;
    m_temperature = m_temperatureValid ? QString::number(m_cpuTemperatureF, 'f', 1) + QStringLiteral("°F") : QStringLiteral("--");
    m_temperatureWarningThresholdF = TelemetryMath::fahrenheitFromCelsius(temperature.warning);
    m_temperatureCriticalThresholdF = TelemetryMath::fahrenheitFromCelsius(temperature.critical);
#else
    QString raw = readTrimmedFile(
        QStringLiteral("/sys/class/thermal/thermal_zone0/temp")
    );

    if (raw.isEmpty()) {
        QDir thermalDir(QStringLiteral("/sys/class/thermal"));
        const QStringList zones = thermalDir.entryList(
            QStringList() << QStringLiteral("thermal_zone*"),
            QDir::Dirs | QDir::NoDotAndDotDot,
            QDir::Name
        );

        for (const QString &zone : zones) {
            const QString zonePath = thermalDir.filePath(zone);
            const QString type =
                readTrimmedFile(zonePath + QStringLiteral("/type")).toLower();

            if (!type.contains(QStringLiteral("cpu")) &&
                !type.contains(QStringLiteral("soc"))) {
                continue;
            }

            raw = readTrimmedFile(zonePath + QStringLiteral("/temp"));
            if (!raw.isEmpty())
                break;
        }
    }

    bool ok = false;
    const double rawValue = raw.toDouble(&ok);

    if (!ok) {
        m_temperature = QStringLiteral("--");
        m_cpuTemperatureF = 0.0;
        m_cpuTemperatureC = 0.0;
        m_temperatureValid = false;
    } else {
        const double celsius = qAbs(rawValue) > 500.0
            ? rawValue / 1000.0
            : rawValue;
        m_temperatureValid = TelemetryMath::validCelsius(celsius);
        m_cpuTemperatureC = m_temperatureValid ? celsius : 0.0;
        m_cpuTemperatureF = m_temperatureValid ? TelemetryMath::fahrenheitFromCelsius(celsius) : 0.0;
        m_temperature = m_temperatureValid
            ? QString::number(m_cpuTemperatureF, 'f', 1) + QStringLiteral("°F")
            : QStringLiteral("--");
    }

#endif

    if (oldText != m_temperature)
        emit temperatureChanged();

    if (!qFuzzyCompare(oldValue + 1.0, m_cpuTemperatureF + 1.0) || oldValid != m_temperatureValid) {
        emit cpuTemperatureChanged();
        emit adaptiveThermalStatusChanged();
    }
}

void SystemMonitor::updateThermalStatus()
{
    const QString oldStatus = m_thermalStatus;
    const bool oldThrottled = m_thermalThrottled;

    bool known = false;
    bool throttledNow = false;

#if !defined(NEUTRONOS_PLATFORM_GEMINI)
    if (commandExists(QStringLiteral("vcgencmd"))) {
        QString output;
        const int code = runProcess(
            QStringLiteral("vcgencmd"),
            QStringList() << QStringLiteral("get_throttled"),
            450,
            &output
        );

        const QRegularExpression pattern(QStringLiteral("0x([0-9a-fA-F]+)"));
        const QRegularExpressionMatch match = pattern.match(output);

        if (code == 0 && match.hasMatch()) {
            bool ok = false;
            const quint32 flags = match.captured(1).toUInt(&ok, 16);

            if (ok) {
                known = true;
                // Bits 0..3 describe conditions active now. Bits 16..19 are
                // historical "has occurred" diagnostics and must not leave
                // the Dashboard permanently warning after recovery.
                throttledNow = TelemetryMath::activeRaspberryPiThrottle(flags);
            }
        }
    }

#endif
    if (!known) {
        bool ok = false;
        const qulonglong count = readTrimmedFile(
            QStringLiteral(
                "/sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count"
            )
        ).toULongLong(&ok);

        // thermal_throttle_count is historical only. Preserve it for event
        // diagnostics without treating it as a current throttle condition.
        if (ok && count > static_cast<qulonglong>(m_throttlingEvents)) {
            m_throttlingEvents = static_cast<int>(qMin<qulonglong>(
                count, static_cast<qulonglong>(std::numeric_limits<int>::max())));
            emit throttlingEventsChanged();
        }
    }

    m_thermalThrottled = known && throttledNow;
    m_thermalStatus = !known
        ? QStringLiteral("Unknown")
        : m_thermalThrottled
          ? QStringLiteral("Throttled")
          : QStringLiteral("No Throttle");

    if (!oldThrottled && m_thermalThrottled) {
        ++m_throttlingEvents;
        emit throttlingEventsChanged();
    }

    if (oldStatus != m_thermalStatus)
        emit thermalStatusChanged();

    if (oldThrottled != m_thermalThrottled) {
        emit thermalThrottledChanged();
        emit adaptiveThermalStatusChanged();
    }
}

void SystemMonitor::sampleTemperatureHistory()
{
    if (m_cpuTemperatureF <= 0.0)
        updateTemperature();

    if (m_cpuTemperatureF > 0.0) {
        appendTemperatureSample(
            m_cpuTemperatureF,
            m_thermalThrottled,
            QDateTime::currentMSecsSinceEpoch()
        );
    }
}

void SystemMonitor::appendTemperatureSample(double temperatureF,
                                            bool throttled,
                                            qint64 timestampMs)
{
    if (temperatureF <= 0.0)
        return;

    if (timestampMs <= 0)
        timestampMs = QDateTime::currentMSecsSinceEpoch();

    ThermalSample sample;
    sample.timestampMs = timestampMs;
    sample.temperatureF = temperatureF;
    sample.throttled = throttled;

    if (!m_temperatureHistorySamples.isEmpty()) {
        ThermalSample &last = m_temperatureHistorySamples.last();

        if (qAbs(last.timestampMs - timestampMs) <
            TemperatureHistorySampleIntervalMs / 2) {
            last = sample;
            emitTemperatureHistorySignals();
            return;
        }
    }

    m_temperatureHistorySamples.append(sample);

    if (m_temperatureHistorySamples.size() > TemperatureHistoryCapacity) {
        m_temperatureHistorySamples.remove(
            0,
            m_temperatureHistorySamples.size() - TemperatureHistoryCapacity
        );
    }

    updateAdaptiveThermalBaseline();

    emitTemperatureHistorySignals();
}

void SystemMonitor::loadThermalBaseline()
{
    QFile file(thermalBaselineFilePath());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return;
    const QJsonObject object = document.object();
    const double baseline = object.value(QStringLiteral("baselineF")).toDouble();
    const int sampleCount = object.value(QStringLiteral("sampleCount")).toInt();
    if (baseline >= 70.0 && baseline <= 175.0 && sampleCount > 0) {
        m_learnedTemperatureBaselineF = baseline;
        m_thermalBaselineSampleCount = sampleCount;
    }
}

void SystemMonitor::saveThermalBaseline() const
{
    const QFileInfo info(thermalBaselineFilePath());
    if (!QDir().mkpath(info.absolutePath()))
        return;
    QJsonObject object;
    object.insert(QStringLiteral("schemaVersion"), 1);
    object.insert(QStringLiteral("baselineF"), m_learnedTemperatureBaselineF);
    object.insert(QStringLiteral("sampleCount"), m_thermalBaselineSampleCount);
    object.insert(QStringLiteral("updatedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    QSaveFile file(info.absoluteFilePath());
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    file.commit();
}

void SystemMonitor::updateAdaptiveThermalBaseline()
{
    QVector<double> candidates;
    const int first = qMax(0, m_temperatureHistorySamples.size() - 120);
    for (int index = first; index < m_temperatureHistorySamples.size(); ++index) {
        const ThermalSample &sample = m_temperatureHistorySamples.at(index);
        // Active throttle and critical samples are incidents, never "normal".
        if (!sample.throttled && sample.temperatureF >= 70.0 && sample.temperatureF < 160.0)
            candidates.append(sample.temperatureF);
    }
    if (candidates.isEmpty())
        return;
    std::sort(candidates.begin(), candidates.end());
    const int trim = candidates.size() >= 10 ? candidates.size() / 10 : 0;
    double total = 0.0;
    int count = 0;
    for (int index = trim; index < candidates.size() - trim; ++index) {
        total += candidates.at(index);
        ++count;
    }
    if (count <= 0)
        return;
    const double robustMean = total / count;
    const double oldBaseline = m_learnedTemperatureBaselineF;
    if (m_learnedTemperatureBaselineF <= 0.0)
        m_learnedTemperatureBaselineF = robustMean;
    else {
        // At one sample per minute this limits drift to 15°F/hour, ensuring a
        // temporary heat spike cannot immediately redefine the baseline.
        const double requested = (robustMean - m_learnedTemperatureBaselineF) * 0.08;
        m_learnedTemperatureBaselineF += qBound(-0.25, requested, 0.25);
    }
    ++m_thermalBaselineSampleCount;
    if (!qFuzzyCompare(oldBaseline + 1.0, m_learnedTemperatureBaselineF + 1.0)) {
        emit thermalBaselineChanged();
        emit adaptiveThermalStatusChanged();
    }
    if (m_thermalBaselineSampleCount <= 3 || m_thermalBaselineSampleCount % 10 == 0)
        saveThermalBaseline();
}

void SystemMonitor::emitTemperatureHistorySignals()
{
    ++m_temperatureHistoryRevision;

    if (m_temperatureHistoryRevision > 1000000000)
        m_temperatureHistoryRevision = 1;

    emit temperatureHistoryChanged();
    emit thermalHistoryChanged();
    emit cpuTemperatureHistoryChanged();
    emit temperatureHistoryRevisionChanged();
}

/* Network */

void SystemMonitor::updateNetwork()
{
    const qint64 sampleMs = QDateTime::currentMSecsSinceEpoch();
    m_network = QStringLiteral("Disconnected");
    m_localIp = QStringLiteral("--");
    m_tailscaleIp = detectTailscaleIp();
    m_activeInterface = QStringLiteral("--");
    m_connectionType = QStringLiteral("disconnected");
    m_networkValid = false;

    const QString detectedWifi = detectWifiInterface();
    QString activeInterface;
    bool activeIsWifi = false;

    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();

    if (!detectedWifi.isEmpty() && detectedWifi != QStringLiteral("--")) {
        for (const QNetworkInterface &iface : interfaces) {
            if (iface.name() != detectedWifi)
                continue;

            if (!(iface.flags() & QNetworkInterface::IsUp) ||
                !(iface.flags() & QNetworkInterface::IsRunning)) {
                continue;
            }

            for (const QNetworkAddressEntry &entry : iface.addressEntries()) {
                if (entry.ip().protocol() != QAbstractSocket::IPv4Protocol)
                    continue;

                activeInterface = iface.name();
                activeIsWifi = true;
                m_wifiInterface = iface.name();
                m_localIp = entry.ip().toString();
                break;
            }

            if (!activeInterface.isEmpty())
                break;
        }
    }

    if (activeInterface.isEmpty()) {
        for (const QNetworkInterface &iface : interfaces) {
            const QString name = iface.name();

            if (!(iface.flags() & QNetworkInterface::IsUp) ||
                !(iface.flags() & QNetworkInterface::IsRunning) ||
                (iface.flags() & QNetworkInterface::IsLoopBack)) {
                continue;
            }

            if (name == QStringLiteral("lo") ||
                name.startsWith(QStringLiteral("docker")) ||
                name.startsWith(QStringLiteral("veth")) ||
                name.startsWith(QStringLiteral("br-")) ||
                name.startsWith(QStringLiteral("tailscale")) ||
                name.startsWith(QStringLiteral("virbr"))) {
                continue;
            }

            for (const QNetworkAddressEntry &entry : iface.addressEntries()) {
                if (entry.ip().protocol() != QAbstractSocket::IPv4Protocol)
                    continue;

                activeInterface = iface.name();
                m_localIp = entry.ip().toString();
                break;
            }

            if (!activeInterface.isEmpty())
                break;
        }
    }

    if (!detectedWifi.isEmpty() && detectedWifi != QStringLiteral("--"))
        m_wifiInterface = detectedWifi;
    else if (activeInterface.isEmpty())
        m_wifiInterface = QStringLiteral("--");

    if (activeIsWifi &&
        !m_wifiInterface.isEmpty() &&
        m_wifiInterface != QStringLiteral("--")) {
        if (m_fastTick % 5 == 0 || m_ssid == QStringLiteral("--")) {
            const QString detectedSsid = detectSsid(m_wifiInterface);
            m_ssid = detectedSsid.isEmpty() ? QStringLiteral("--") : detectedSsid;
            updateWifiSignal(m_wifiInterface);
        }

        m_network = m_ssid != QStringLiteral("--")
            ? m_ssid
            : QStringLiteral("Wi-Fi");
        m_connectionType = QStringLiteral("wifi");
    } else {
        m_ssid = QStringLiteral("--");
        m_wifiSignal = QStringLiteral("--");

        if (!activeInterface.isEmpty())
            m_network = QStringLiteral("Ethernet");
        if (!activeInterface.isEmpty())
            m_connectionType = QStringLiteral("ethernet");
    }

    if (activeInterface.isEmpty()) {
        m_download = QStringLiteral("0 B/s");
        m_upload = QStringLiteral("0 B/s");
        m_lastRx = 0;
        m_lastTx = 0;
        m_rxBytesPerSecond = 0;
        m_txBytesPerSecond = 0;
        m_lastNetworkInterface.clear();
        m_lastNetworkSampleMs = 0;
        return;
    }

    m_activeInterface = activeInterface;
    m_networkValid = true;

    QFile file(QStringLiteral("/proc/net/dev"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    quint64 totalRx = 0;
    quint64 totalTx = 0;
    QTextStream stream(&file);

    while (!stream.atEnd()) {
        const QString line = stream.readLine();

        if (!line.contains(QLatin1Char(':')))
            continue;

        const QStringList pair = line.split(QLatin1Char(':'));
        if (pair.size() < 2 || pair[0].trimmed() != activeInterface)
            continue;

        const QStringList values = pair[1].simplified().split(QStringLiteral(" "));
        if (values.size() < 16)
            continue;

        totalRx = values[0].toULongLong();
        totalTx = values[8].toULongLong();
        break;
    }

    file.close();

    const bool sameInterface = m_lastNetworkInterface == activeInterface;
    if (!sameInterface || m_lastNetworkSampleMs <= 0) {
        m_lastRx = totalRx;
        m_lastTx = totalTx;
        m_lastNetworkInterface = activeInterface;
        m_lastNetworkSampleMs = sampleMs;
        m_rxBytesPerSecond = 0;
        m_txBytesPerSecond = 0;
        m_download = QStringLiteral("0 B/s");
        m_upload = QStringLiteral("0 B/s");
        return;
    }

    const TelemetryMath::RateSample rx = TelemetryMath::byteRate(m_lastRx, totalRx, sampleMs - m_lastNetworkSampleMs, sameInterface);
    const TelemetryMath::RateSample tx = TelemetryMath::byteRate(m_lastTx, totalTx, sampleMs - m_lastNetworkSampleMs, sameInterface);

    m_lastRx = totalRx;
    m_lastTx = totalTx;
    m_lastNetworkSampleMs = sampleMs;
    m_rxBytesPerSecond = rx.valid ? rx.bytesPerSecond : 0;
    m_txBytesPerSecond = tx.valid ? tx.bytesPerSecond : 0;
    m_download = formatSpeed(m_rxBytesPerSecond);
    m_upload = formatSpeed(m_txBytesPerSecond);
}

void SystemMonitor::updateWifiSignal(const QString &interfaceName)
{
    if (interfaceName.isEmpty() || interfaceName == QStringLiteral("--") ||
        !commandExists(QStringLiteral("iw"))) {
        m_wifiSignal = QStringLiteral("--");
        return;
    }

    QString output;

    runProcess(
        QStringLiteral("iw"),
        QStringList() << QStringLiteral("dev")
                      << interfaceName
                      << QStringLiteral("link"),
        450,
        &output
    );

    const QRegularExpression pattern(
        QStringLiteral("signal:\\s*(-?\\d+)\\s*dBm")
    );
    const QRegularExpressionMatch match = pattern.match(output);

    m_wifiSignal = match.hasMatch()
        ? match.captured(1) + QStringLiteral(" dBm")
        : QStringLiteral("--");
}

QString SystemMonitor::detectWifiInterface() const
{
    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();

    for (const QNetworkInterface &iface : interfaces) {
        const QString name = iface.name();

        if (!(iface.flags() & QNetworkInterface::IsUp))
            continue;

        if (name.startsWith(QStringLiteral("wlan")) ||
            name.startsWith(QStringLiteral("wlx")) ||
            name.startsWith(QStringLiteral("wlp"))) {
            return name;
        }
    }

    if (!commandExists(QStringLiteral("iw")))
        return QStringLiteral("--");

    QString output;

    runProcess(
        QStringLiteral("iw"),
        QStringList() << QStringLiteral("dev"),
        450,
        &output
    );

    const QRegularExpression pattern(QStringLiteral("Interface\\s+(\\S+)"));
    QRegularExpressionMatchIterator iterator = pattern.globalMatch(output);

    while (iterator.hasNext()) {
        const QString name = iterator.next().captured(1).trimmed();
        if (!name.isEmpty())
            return name;
    }

    return QStringLiteral("--");
}

QString SystemMonitor::detectSsid(const QString &interfaceName) const
{
    if (interfaceName.isEmpty() || interfaceName == QStringLiteral("--"))
        return QStringLiteral("--");

    if (commandExists(QStringLiteral("iwgetid"))) {
        QString output;

        runProcess(
            QStringLiteral("iwgetid"),
            QStringList() << interfaceName << QStringLiteral("-r"),
            450,
            &output
        );

        output = output.trimmed();

        if (!output.isEmpty())
            return output;
    }

    if (commandExists(QStringLiteral("iw"))) {
        QString output;

        runProcess(
            QStringLiteral("iw"),
            QStringList() << QStringLiteral("dev")
                          << interfaceName
                          << QStringLiteral("link"),
            450,
            &output
        );

        const QRegularExpression pattern(QStringLiteral("SSID:\\s*(.+)"));
        const QRegularExpressionMatch match = pattern.match(output);

        if (match.hasMatch()) {
            const QString value = match.captured(1).trimmed();
            if (!value.isEmpty())
                return value;
        }
    }

    return QStringLiteral("--");
}

QString SystemMonitor::detectTailscaleIp() const
{
    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();

    for (const QNetworkInterface &iface : interfaces) {
        if (!iface.name().toLower().startsWith(QStringLiteral("tailscale")) ||
            !(iface.flags() & QNetworkInterface::IsUp)) {
            continue;
        }

        for (const QNetworkAddressEntry &entry : iface.addressEntries()) {
            if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol)
                return entry.ip().toString();
        }
    }

    return QStringLiteral("--");
}

/* Uptime, updates, and operating mode */

void SystemMonitor::updateUptime()
{
    QFile file(QStringLiteral("/proc/uptime"));

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_uptime = QStringLiteral("--");
        m_uptimeSeconds = 0;
        m_bootDateTime = QDateTime();
        m_uptimeValid = false;
        return;
    }

    const QString raw = QString::fromUtf8(file.readAll()).trimmed();
    file.close();

    const quint64 seconds = static_cast<quint64>(
        raw.split(QStringLiteral(" ")).value(0).toDouble()
    );
    m_uptimeSeconds = seconds;
    m_uptimeValid = true;
    m_bootDateTime = QDateTime::currentDateTime().addSecs(-qint64(seconds));
    m_uptime = TelemetryMath::formatUptime(seconds);
}

void SystemMonitor::updateLastAptUpdate()
{
    const QStringList candidates = {
        QStringLiteral("/var/lib/apt/periodic/update-success-stamp"),
        QStringLiteral("/var/log/apt/history.log")
    };

    for (const QString &path : candidates) {
        const QFileInfo info(path);

        if (!info.exists() || !info.lastModified().isValid())
            continue;

        m_lastAptUpdate =
            info.lastModified().toString(QStringLiteral("MMM d h:mm AP"));
        return;
    }

    m_lastAptUpdate = QStringLiteral("--");
}

void SystemMonitor::updateSystemMode()
{
    QString mode = QStringLiteral("IDLE MODE");

    for (const QVariant &entry : m_networkApps) {
        const QVariantMap app = entry.toMap();
        const QString name =
            app.value(QStringLiteral("name")).toString().toLower();
        const int percent =
            app.value(QStringLiteral("percent")).toInt();

        if (percent <= 0)
            continue;

        if (name.contains(QStringLiteral("qbittorrent")) ||
            name.contains(QStringLiteral("qbit"))) {
            mode = QStringLiteral("DOWNLOAD MODE");
            break;
        }

        if (name.contains(QStringLiteral("jellyfin"))) {
            mode = QStringLiteral("MEDIA MODE");
            break;
        }

        if (name.contains(QStringLiteral("optimizer")) ||
            name.contains(QStringLiteral("vid"))) {
            mode = QStringLiteral("OPTIMIZER MODE");
            break;
        }
    }

    if (m_cpuPercent > 75)
        mode = QStringLiteral("PERFORMANCE MODE");

    m_systemMode = mode;
}

/* PATCH16A_PROCESS_DETAILS_BEGIN
   Selected process drilldown */

QVariantMap SystemMonitor::processDetails(qint64 pid) const
{
    QVariantMap result;
    result[QStringLiteral("pid")] = pid;
    result[QStringLiteral("available")] = false;

    if (pid <= 0) {
        result[QStringLiteral("error")] = QStringLiteral("Invalid process identifier");
        return result;
    }

    const QString procRoot = QStringLiteral("/proc/%1").arg(pid);
    const QFileInfo procInfo(procRoot);

    if (!procInfo.exists() || !procInfo.isDir()) {
        result[QStringLiteral("error")] = QStringLiteral("Process is no longer running");
        return result;
    }

    auto readProcBytes = [&procRoot](const QString &relativePath) -> QByteArray {
        QFile file(procRoot + QLatin1Char('/') + relativePath);
        if (!file.open(QIODevice::ReadOnly))
            return {};
        return file.readAll();
    };

    auto readProcText = [&readProcBytes](const QString &relativePath) -> QString {
        return QString::fromUtf8(readProcBytes(relativePath)).trimmed();
    };

    QHash<QString, QString> statusValues;
    const QStringList statusLines =
        readProcText(QStringLiteral("status"))
            .split(QLatin1Char('\n'), Qt::SkipEmptyParts);

    for (const QString &line : statusLines) {
        const int colon = line.indexOf(QLatin1Char(':'));
        if (colon <= 0)
            continue;
        statusValues.insert(
            line.left(colon).trimmed(),
            line.mid(colon + 1).simplified()
        );
    }

    auto statusValue = [&statusValues](const QString &key) -> QString {
        return statusValues.value(key).trimmed();
    };

    const QString statText = readProcText(QStringLiteral("stat"));
    const int commandOpen = statText.indexOf(QLatin1Char('('));
    const int commandClose = statText.lastIndexOf(QLatin1Char(')'));
    QString statCommand;
    QStringList statFields;

    if (commandOpen >= 0 && commandClose > commandOpen) {
        statCommand = statText.mid(
            commandOpen + 1,
            commandClose - commandOpen - 1
        );
        statFields = statText.mid(commandClose + 1)
            .simplified()
            .split(QLatin1Char(' '), Qt::SkipEmptyParts);
    }

    auto statField = [&statFields](int index) -> QString {
        return index >= 0 && index < statFields.size()
            ? statFields.at(index)
            : QString();
    };

    QString processName = statusValue(QStringLiteral("Name"));
    if (processName.isEmpty())
        processName = statCommand;

    QVariantMap sampledProcess;
    const QList<QVariantList> sampledLists = {
        m_processList,
        m_cpuProcesses,
        m_memoryProcesses
    };

    for (const QVariantList &list : sampledLists) {
        for (const QVariant &entry : list) {
            const QVariantMap candidate = entry.toMap();
            if (candidate.value(QStringLiteral("pid")).toLongLong() == pid ||
                candidate.value(QStringLiteral("processId")).toLongLong() == pid) {
                sampledProcess = candidate;
                break;
            }
        }
        if (!sampledProcess.isEmpty())
            break;
    }

    if (processName.isEmpty()) {
        processName = sampledProcess.value(QStringLiteral("name")).toString();
    }
    if (processName.isEmpty())
        processName = QStringLiteral("Unknown process");

    QByteArray commandLineBytes = readProcBytes(QStringLiteral("cmdline"));
    for (char &character : commandLineBytes) {
        if (character == '\0')
            character = ' ';
    }
    const QString commandLine =
        QString::fromUtf8(commandLineBytes).simplified();

    QString executablePath = QFile::symLinkTarget(
        procRoot + QStringLiteral("/exe")
    );
    QString workingDirectory = QFile::symLinkTarget(
        procRoot + QStringLiteral("/cwd")
    );

    QString userName = procInfo.owner();
    if (userName.isEmpty())
        userName = sampledProcess.value(QStringLiteral("user")).toString();

    const QString state = !statusValue(QStringLiteral("State")).isEmpty()
        ? statusValue(QStringLiteral("State"))
        : statField(0);

    const qint64 parentPid = statField(1).toLongLong();
    const qint64 priority = statField(15).toLongLong();
    const qint64 niceValue = statField(16).toLongLong();
    qint64 threadCount = statusValue(QStringLiteral("Threads")).toLongLong();
    if (threadCount <= 0)
        threadCount = statField(17).toLongLong();

    quint64 residentBytes = 0;
    quint64 virtualBytes = 0;

    const QRegularExpression memoryPattern(
        QStringLiteral("^([0-9]+)\\s+kB$"),
        QRegularExpression::CaseInsensitiveOption
    );

    auto parseStatusKb = [&memoryPattern, &statusValue](const QString &key) -> quint64 {
        const QRegularExpressionMatch match =
            memoryPattern.match(statusValue(key));
        return match.hasMatch()
            ? match.captured(1).toULongLong() * 1024ULL
            : 0ULL;
    };

    residentBytes = parseStatusKb(QStringLiteral("VmRSS"));
    virtualBytes = parseStatusKb(QStringLiteral("VmSize"));

    if (residentBytes == 0) {
        residentBytes = sampledProcess
            .value(QStringLiteral("memoryBytes"))
            .toULongLong();
    }

    double cpuPercent = sampledProcess
        .value(QStringLiteral("cpu"))
        .toDouble();
    double memoryPercent = sampledProcess
        .value(QStringLiteral("memory"))
        .toDouble();

    if (memoryPercent <= 0.0 && m_ramTotalBytes > 0 && residentBytes > 0) {
        memoryPercent =
            (static_cast<double>(residentBytes) /
             static_cast<double>(m_ramTotalBytes)) * 100.0;
    }

#ifdef Q_OS_LINUX
    const long clockTicksValue = sysconf(_SC_CLK_TCK);
    const long pageSizeValue = sysconf(_SC_PAGESIZE);
#else
    const long clockTicksValue = 100;
    const long pageSizeValue = 4096;
#endif

    const quint64 clockTicks = clockTicksValue > 0
        ? static_cast<quint64>(clockTicksValue)
        : 100ULL;
    const quint64 pageSize = pageSizeValue > 0
        ? static_cast<quint64>(pageSizeValue)
        : 4096ULL;

    const quint64 userTicks = statField(11).toULongLong();
    const quint64 systemTicks = statField(12).toULongLong();
    const quint64 cpuSeconds = (userTicks + systemTicks) / clockTicks;
    const quint64 startTicks = statField(19).toULongLong();

    if (residentBytes == 0) {
        const qint64 residentPages = statField(21).toLongLong();
        if (residentPages > 0)
            residentBytes = static_cast<quint64>(residentPages) * pageSize;
    }
    if (virtualBytes == 0)
        virtualBytes = statField(20).toULongLong();

    double uptimeSeconds = 0.0;
    const QString uptimeText = readTrimmedFile(QStringLiteral("/proc/uptime"));
    if (!uptimeText.isEmpty()) {
        uptimeSeconds = uptimeText
            .section(QLatin1Char(' '), 0, 0)
            .toDouble();
    }

    quint64 elapsedSeconds = 0;
    QDateTime startTime;
    if (startTicks > 0 && uptimeSeconds > 0.0) {
        const double processStartAfterBoot =
            static_cast<double>(startTicks) /
            static_cast<double>(clockTicks);
        elapsedSeconds = static_cast<quint64>(
            qMax(0.0, uptimeSeconds - processStartAfterBoot)
        );
        startTime = QDateTime::currentDateTime().addSecs(
            -static_cast<qint64>(elapsedSeconds)
        );
    }

    QHash<QString, quint64> ioValues;
    const QStringList ioLines =
        readProcText(QStringLiteral("io"))
            .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : ioLines) {
        const int colon = line.indexOf(QLatin1Char(':'));
        if (colon <= 0)
            continue;
        ioValues.insert(
            line.left(colon).trimmed(),
            line.mid(colon + 1).trimmed().toULongLong()
        );
    }

    const QDir fdDirectory(procRoot + QStringLiteral("/fd"));
    const int openFiles = fdDirectory.exists()
        ? fdDirectory.entryList(
              QDir::AllEntries | QDir::NoDotAndDotDot,
              QDir::Name
          ).size()
        : -1;

    QString cgroupPath;
    const QStringList cgroupLines =
        readProcText(QStringLiteral("cgroup"))
            .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : cgroupLines) {
        const int secondColon = line.indexOf(
            QLatin1Char(':'),
            line.indexOf(QLatin1Char(':')) + 1
        );
        if (secondColon < 0)
            continue;
        const QString candidate = line.mid(secondColon + 1).trimmed();
        if (!candidate.isEmpty()) {
            cgroupPath = candidate;
            if (candidate != QStringLiteral("/"))
                break;
        }
    }

    QString serviceUnit;
    const QRegularExpression servicePattern(
        QStringLiteral("(?:^|/)([^/]+\\.(?:service|scope))(?:/|$)")
    );
    const QRegularExpressionMatch serviceMatch =
        servicePattern.match(cgroupPath);
    if (serviceMatch.hasMatch())
        serviceUnit = serviceMatch.captured(1);

    result[QStringLiteral("available")] = true;
    result[QStringLiteral("name")] = processName;
    result[QStringLiteral("processName")] = processName;
    result[QStringLiteral("user")] = userName.isEmpty() ? QStringLiteral("--") : userName;
    result[QStringLiteral("state")] = state.isEmpty() ? QStringLiteral("--") : state;
    result[QStringLiteral("parentPid")] = parentPid;
    result[QStringLiteral("threads")] = threadCount;
    result[QStringLiteral("priority")] = priority;
    result[QStringLiteral("nice")] = niceValue;
    result[QStringLiteral("executable")] = executablePath.isEmpty() ? QStringLiteral("Unavailable") : executablePath;
    result[QStringLiteral("workingDirectory")] = workingDirectory.isEmpty() ? QStringLiteral("Unavailable") : workingDirectory;
    result[QStringLiteral("commandLine")] = commandLine.isEmpty() ? processName : commandLine;
    result[QStringLiteral("cpuPercent")] = cpuPercent;
    result[QStringLiteral("memoryPercent")] = memoryPercent;
    result[QStringLiteral("residentBytes")] = residentBytes;
    result[QStringLiteral("residentMemory")] = formatBytes(residentBytes);
    result[QStringLiteral("virtualBytes")] = virtualBytes;
    result[QStringLiteral("virtualMemory")] = formatBytes(virtualBytes);
    result[QStringLiteral("cpuTimeSeconds")] = cpuSeconds;
    result[QStringLiteral("cpuTime")] = formatDuration(cpuSeconds);
    result[QStringLiteral("startTime")] = startTime.isValid()
        ? startTime.toString(QStringLiteral("yyyy-MM-dd  hh:mm:ss"))
        : QStringLiteral("Unavailable");
    result[QStringLiteral("elapsedSeconds")] = elapsedSeconds;
    result[QStringLiteral("elapsedRuntime")] = elapsedSeconds > 0
        ? formatDuration(elapsedSeconds)
        : sampledProcess.value(QStringLiteral("runtime"), QStringLiteral("--")).toString();
    result[QStringLiteral("openFiles")] = openFiles >= 0
        ? QString::number(openFiles)
        : QStringLiteral("Unavailable");
    result[QStringLiteral("serviceUnit")] = serviceUnit.isEmpty()
        ? QStringLiteral("None detected")
        : serviceUnit;
    result[QStringLiteral("cgroup")] = cgroupPath.isEmpty()
        ? QStringLiteral("Unavailable")
        : cgroupPath;
    result[QStringLiteral("readBytes")] = ioValues.value(QStringLiteral("read_bytes"));
    result[QStringLiteral("writeBytes")] = ioValues.value(QStringLiteral("write_bytes"));
    result[QStringLiteral("diskRead")] = formatBytes(ioValues.value(QStringLiteral("read_bytes")));
    result[QStringLiteral("diskWrite")] = formatBytes(ioValues.value(QStringLiteral("write_bytes")));
    result[QStringLiteral("charactersRead")] = formatBytes(ioValues.value(QStringLiteral("rchar")));
    result[QStringLiteral("charactersWritten")] = formatBytes(ioValues.value(QStringLiteral("wchar")));
    result[QStringLiteral("voluntaryContextSwitches")] =
        statusValue(QStringLiteral("voluntary_ctxt_switches"));
    result[QStringLiteral("nonvoluntaryContextSwitches")] =
        statusValue(QStringLiteral("nonvoluntary_ctxt_switches"));

    return result;
}
/* PATCH16A_PROCESS_DETAILS_END */

/* Asynchronous process telemetry */

void SystemMonitor::updateTopProcessesAsync()
{
    if (m_topProcessBusy)
        return;

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();

    /*
        Multiple visible QML surfaces can request the same snapshot during a
        signal burst. Coalesce those requests instead of starting duplicate
        scans. The normal CPU modal cadence is slower than this guard.
    */
    if (m_lastProcessRefreshMs > 0 &&
        nowMs - m_lastProcessRefreshMs < 2000) {
        return;
    }

    m_topProcessBusy = true;

    auto *watcher =
        new QFutureWatcher<NativeProcessSnapshot>(this);

    connect(
        watcher,
        &QFutureWatcher<NativeProcessSnapshot>::finished,
        this,
        [this, watcher]() {
        const NativeProcessSnapshot snapshot =
            watcher->result();

        QVariantList processes;
        processes.reserve(snapshot.records.size());

        QHash<qlonglong, quint64> currentCpuTicks;
        QHash<qlonglong, quint64> currentStartTicks;
        currentCpuTicks.reserve(snapshot.records.size());
        currentStartTicks.reserve(snapshot.records.size());

        const bool intervalSampleValid =
            m_lastProcessTotalTicks > 0 &&
            snapshot.totalCpuTicks > m_lastProcessTotalTicks;

        const quint64 totalDelta =
            intervalSampleValid
            ? snapshot.totalCpuTicks - m_lastProcessTotalTicks
            : 0ULL;

        const double maximumCpuPercent =
            static_cast<double>(qMax(1, snapshot.logicalCores)) * 100.0;

        for (const NativeProcessRecord &record : snapshot.records) {
            currentCpuTicks.insert(record.pid, record.cpuTicks);
            currentStartTicks.insert(record.pid, record.startTicks);

            double cpu = 0.0;

            const bool sameProcess =
                m_lastProcessStartTicks.value(record.pid, 0) ==
                record.startTicks;

            if (intervalSampleValid &&
                sameProcess &&
                m_lastProcessCpuTicks.contains(record.pid) &&
                record.cpuTicks >= m_lastProcessCpuTicks.value(record.pid)) {
                const quint64 processDelta =
                    record.cpuTicks -
                    m_lastProcessCpuTicks.value(record.pid);

                if (totalDelta > 0) {
                    cpu =
                        100.0 *
                        static_cast<double>(processDelta) *
                        static_cast<double>(qMax(1, snapshot.logicalCores)) /
                        static_cast<double>(totalDelta);
                }
            } else if (snapshot.clockTicksPerSecond > 0 &&
                       snapshot.uptimeTicks > record.startTicks) {
                /*
                    First snapshot fallback: average CPU since process start.
                    The following native snapshot switches to interval usage.
                */
                const double elapsedSeconds =
                    static_cast<double>(
                        snapshot.uptimeTicks - record.startTicks
                    ) /
                    static_cast<double>(snapshot.clockTicksPerSecond);

                if (elapsedSeconds > 0.0) {
                    const double cpuSeconds =
                        static_cast<double>(record.cpuTicks) /
                        static_cast<double>(snapshot.clockTicksPerSecond);

                    cpu = 100.0 * cpuSeconds / elapsedSeconds;
                }
            }

            cpu = qBound(0.0, cpu, maximumCpuPercent);

            const double memory =
                snapshot.totalMemoryBytes > 0
                ? 100.0 *
                  static_cast<double>(record.residentBytes) /
                  static_cast<double>(snapshot.totalMemoryBytes)
                : 0.0;

            quint64 elapsedSeconds = 0;

            if (snapshot.clockTicksPerSecond > 0 &&
                snapshot.uptimeTicks > record.startTicks) {
                elapsedSeconds =
                    (snapshot.uptimeTicks - record.startTicks) /
                    snapshot.clockTicksPerSecond;
            }

            QVariantMap item;
            item[QStringLiteral("pid")] = record.pid;
            item[QStringLiteral("processId")] = record.pid;
            item[QStringLiteral("name")] = record.name;
            item[QStringLiteral("command")] = record.name;
            item[QStringLiteral("processName")] = record.name;
            item[QStringLiteral("comm")] = record.name;
            item[QStringLiteral("user")] = record.user;
            item[QStringLiteral("username")] = record.user;
            item[QStringLiteral("owner")] = record.user;
            item[QStringLiteral("cpu")] = cpu;
            item[QStringLiteral("cpuPercent")] = cpu;
            item[QStringLiteral("usage")] = cpu;
            item[QStringLiteral("memory")] = memory;
            item[QStringLiteral("memoryPercent")] = memory;
            item[QStringLiteral("ram")] = memory;
            item[QStringLiteral("mem")] = memory;
            item[QStringLiteral("memoryBytes")] = record.residentBytes;
            item[QStringLiteral("residentBytes")] = record.residentBytes;
            item[QStringLiteral("rssBytes")] = record.residentBytes;
            item[QStringLiteral("rss")] = record.residentBytes;
            item[QStringLiteral("state")] = record.state;
            item[QStringLiteral("status")] = record.state;
            item[QStringLiteral("runtime")] = formatDuration(elapsedSeconds);
            item[QStringLiteral("elapsed")] =
                item.value(QStringLiteral("runtime"));
            item[QStringLiteral("time")] =
                item.value(QStringLiteral("runtime"));

            processes.append(item);
        }

        m_lastProcessCpuTicks = currentCpuTicks;
        m_lastProcessStartTicks = currentStartTicks;
        m_lastProcessTotalTicks = snapshot.totalCpuTicks;
        m_lastProcessRefreshMs = QDateTime::currentMSecsSinceEpoch();

        applyProcessSnapshot(processes);

        m_topProcessBusy = false;
        watcher->deleteLater();
    });

    watcher->setFuture(
        QtConcurrent::run(scanNativeProcesses)
    );
}

void SystemMonitor::applyProcessSnapshot(const QVariantList &processes)
{
    QVariantList cpuSorted = processes;
    QVariantList memorySorted = processes;
    QVariantList generalSorted = processes;
    QVariantList memoryModalSorted = processes;

    sortProcessList(cpuSorted, QStringLiteral("cpu"));
    sortProcessList(memorySorted, QStringLiteral("memory"));
    sortProcessList(generalSorted, m_processSort);
    sortProcessList(memoryModalSorted, m_memoryProcessSort);

    m_cpuProcesses = limitedList(cpuSorted, 128);
    m_memoryProcesses = limitedList(memoryModalSorted, 128);
    m_processList = limitedList(generalSorted, 128);
    m_processCount = processes.size();

    QVariantList legacyCpu = limitedList(cpuSorted, 4);
    QVariantList legacyMemory = limitedList(memorySorted, 4);

    for (QVariant &entry : legacyCpu) {
        QVariantMap item = entry.toMap();
        item[QStringLiteral("percent")] = qMin(
            100,
            qRound(item.value(QStringLiteral("cpu")).toDouble())
        );
        entry = item;
    }

    for (QVariant &entry : legacyMemory) {
        QVariantMap item = entry.toMap();
        item[QStringLiteral("percent")] = qMin(
            100,
            qRound(item.value(QStringLiteral("memory")).toDouble())
        );
        entry = item;
    }

    m_topCpuProcesses = legacyCpu;
    m_topRamProcesses = legacyMemory;

    emit processDataChanged();
    emit systemChanged();
}

/* Asynchronous network and service lists */

void SystemMonitor::updateNetworkAppsAsync()
{
    if (m_networkAppsBusy || !commandExists(QStringLiteral("docker")))
        return;

    m_networkAppsBusy = true;
    QProcess *process = new QProcess(this);

    connect(
        process,
        QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
        this,
        [this, process](int, QProcess::ExitStatus) {
        const QStringList lines =
            QString::fromUtf8(process->readAllStandardOutput())
                .split(QStringLiteral("\n"), Qt::SkipEmptyParts);

        QVariantList result;
        QList<QVariantMap> temporary;
        quint64 totalRate = 0;

        for (const QString &line : lines) {
            const QStringList parts = line.split(QStringLiteral("|"));
            if (parts.size() < 2)
                continue;

            const QString name = parts[0].trimmed();
            const QStringList io =
                parts[1].trimmed().split(QStringLiteral("/"));

            if (io.size() < 2)
                continue;

            const quint64 rx = parseHumanBytes(io[0].trimmed());
            const quint64 tx = parseHumanBytes(io[1].trimmed());
            const quint64 previousRx = m_lastContainerRx.value(name, rx);
            const quint64 previousTx = m_lastContainerTx.value(name, tx);

            quint64 rate = 0;
            if (rx >= previousRx)
                rate += rx - previousRx;
            if (tx >= previousTx)
                rate += tx - previousTx;

            m_lastContainerRx[name] = rx;
            m_lastContainerTx[name] = tx;

            QVariantMap item;
            item[QStringLiteral("name")] = name;
            item[QStringLiteral("rx")] = formatBytes(rx);
            item[QStringLiteral("tx")] = formatBytes(tx);
            item[QStringLiteral("rateBytes")] = static_cast<qulonglong>(rate);
            item[QStringLiteral("rate")] = formatSpeed(rate / 240);

            totalRate += rate;
            temporary.append(item);
        }

        for (QVariantMap item : temporary) {
            const quint64 rate =
                item.value(QStringLiteral("rateBytes")).toULongLong();

            item[QStringLiteral("percent")] = totalRate > 0
                ? qRound(
                      100.0 * static_cast<double>(rate) /
                      static_cast<double>(totalRate)
                  )
                : 0;

            result.append(item);
        }

        m_networkApps = result;
        m_networkAppsBusy = false;
        process->deleteLater();

        emit systemChanged();
    });

    connect(
        process,
        &QProcess::errorOccurred,
        this,
        [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;

        m_networkAppsBusy = false;
        process->deleteLater();
    });

    process->start(
        QStringLiteral("docker"),
        QStringList()
            << QStringLiteral("stats")
            << QStringLiteral("--no-stream")
            << QStringLiteral("--format")
            << QStringLiteral("{{.Name}}|{{.NetIO}}")
    );

    QTimer::singleShot(3500, process, [process]() {
        if (process->state() != QProcess::NotRunning)
            process->kill();
    });
}

void SystemMonitor::updateServiceHealthAsync()
{
    if (m_serviceHealthBusy)
        return;

    m_serviceHealthBusy = true;
    QProcess *process = new QProcess(this);

    connect(
        process,
        QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
        this,
        [this, process](int, QProcess::ExitStatus) {
        const QStringList lines =
            QString::fromUtf8(process->readAllStandardOutput())
                .split(QStringLiteral("\n"), Qt::SkipEmptyParts);

        QVariantList result;

        for (const QString &line : lines) {
            const QStringList parts = line.split(QStringLiteral("|"));
            if (parts.size() < 2)
                continue;

            QVariantMap item;
            item[QStringLiteral("name")] = parts[0].trimmed();
            item[QStringLiteral("running")] =
                parts[1].trimmed() == QStringLiteral("1");
            result.append(item);
        }

        m_serviceHealth = result;
        m_serviceHealthBusy = false;
        process->deleteLater();

        emit systemChanged();
    });

    connect(
        process,
        &QProcess::errorOccurred,
        this,
        [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;

        m_serviceHealthBusy = false;
        process->deleteLater();
    });

    const QString script =
        QStringLiteral(
            "docker inspect -f '{{.State.Running}}' jellyfin 2>/dev/null | grep -q true && echo 'Jellyfin|1' || echo 'Jellyfin|0';"
        ) +
        QStringLiteral(
            "docker inspect -f '{{.State.Running}}' qbittorrent 2>/dev/null | grep -q true && echo 'qBit|1' || echo 'qBit|0';"
        ) +
        QStringLiteral(
            "systemctl is-active --quiet docker && echo 'Docker|1' || echo 'Docker|0';"
        ) +
        QStringLiteral(
            "systemctl is-active --quiet tailscaled && echo 'Tailscale|1' || echo 'Tailscale|0';"
        );

    process->start(
        QStringLiteral("/bin/sh"),
        QStringList() << QStringLiteral("-c") << script
    );

    QTimer::singleShot(2500, process, [process]() {
        if (process->state() != QProcess::NotRunning)
            process->kill();
    });
}

/* Speed test */

void SystemMonitor::runCachedSpeedTest()
{
    if (m_speedTestRunning)
        return;

    if (!commandExists(QStringLiteral("speedtest-cli")) &&
        !commandExists(QStringLiteral("speedtest"))) {
        m_speedTestUpdated = QStringLiteral("INSTALL SPEEDTEST");
        m_speedTestAge = QStringLiteral("INSTALL SPEEDTEST");
        emit systemChanged();
        return;
    }

    m_speedTestRunning = true;
    m_speedTestUpdated = QStringLiteral("TEST RUNNING");
    m_speedTestAge = QStringLiteral("TEST RUNNING");
    emit systemChanged();

    QProcess *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);

    connect(
        process,
        QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
        this,
        [this, process](int, QProcess::ExitStatus) {
        parseSpeedTestOutput(QString::fromUtf8(process->readAll()));
        m_speedTestRunning = false;
        updateSpeedTestAge();
        process->deleteLater();
        emit systemChanged();
    });

    connect(
        process,
        &QProcess::errorOccurred,
        this,
        [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;

        m_speedTestRunning = false;
        m_speedTestUpdated = QStringLiteral("TEST FAILED");
        m_speedTestAge = QStringLiteral("TEST FAILED");
        process->deleteLater();
        emit systemChanged();
    });

    const QString script =
        QStringLiteral(
            "if command -v speedtest-cli >/dev/null 2>&1; then "
            "speedtest-cli --simple 2>&1; "
            "elif command -v speedtest >/dev/null 2>&1; then "
            "speedtest --accept-license --accept-gdpr 2>&1; "
            "else echo 'SPEEDTEST_NOT_INSTALLED'; fi"
        );

    process->start(
        QStringLiteral("/bin/sh"),
        QStringList() << QStringLiteral("-c") << script
    );

    QTimer::singleShot(90000, process, [this, process]() {
        if (process->state() == QProcess::NotRunning)
            return;

        process->kill();

        if (m_speedTestDownload == QStringLiteral("--") &&
            m_speedTestUpload == QStringLiteral("--")) {
            m_speedTestUpdated = QStringLiteral("TEST TIMEOUT");
            m_speedTestAge = QStringLiteral("TEST TIMEOUT");
        }

        m_speedTestRunning = false;
        emit systemChanged();
    });
}

void SystemMonitor::updateSpeedTestAge()
{
    if (m_speedTestRunning) {
        m_speedTestUpdated = QStringLiteral("TEST RUNNING");
        m_speedTestAge = QStringLiteral("TEST RUNNING");
        return;
    }

    if (!m_lastSpeedTestTime.isValid()) {
        if (m_speedTestUpdated.isEmpty())
            m_speedTestUpdated = QStringLiteral("MANUAL TEST READY");
        if (m_speedTestAge.isEmpty())
            m_speedTestAge = QStringLiteral("MANUAL TEST READY");
        return;
    }

    const QString age =
        QStringLiteral("UPDATED ") + formatAge(m_lastSpeedTestTime);

    m_speedTestUpdated = age;
    m_speedTestAge = age;
}

void SystemMonitor::parseSpeedTestOutput(const QString &output)
{
    if (output.contains(QStringLiteral("SPEEDTEST_NOT_INSTALLED"))) {
        if (m_speedTestDownload == QStringLiteral("--") &&
            m_speedTestUpload == QStringLiteral("--")) {
            m_speedTestUpdated = QStringLiteral("INSTALL SPEEDTEST");
            m_speedTestAge = QStringLiteral("INSTALL SPEEDTEST");
        }
        return;
    }

    const QRegularExpression downloadPattern(
        QStringLiteral("Download:\\s*([0-9.]+)\\s*([A-Za-z/]+)"),
        QRegularExpression::CaseInsensitiveOption
    );
    const QRegularExpression uploadPattern(
        QStringLiteral("Upload:\\s*([0-9.]+)\\s*([A-Za-z/]+)"),
        QRegularExpression::CaseInsensitiveOption
    );

    const QRegularExpressionMatch downloadMatch = downloadPattern.match(output);
    const QRegularExpressionMatch uploadMatch = uploadPattern.match(output);

    auto toMbps = [](double value, const QString &unit) {
        const QString lower = unit.toLower();
        if (lower.contains(QStringLiteral("g")))
            return value * 1000.0;
        if (lower.contains(QStringLiteral("k")))
            return value / 1000.0;
        return value;
    };

    bool receivedResult = false;

    if (downloadMatch.hasMatch()) {
        m_speedTestDownload = formatMbps(
            toMbps(
                downloadMatch.captured(1).toDouble(),
                downloadMatch.captured(2)
            )
        );
        receivedResult = true;
    }

    if (uploadMatch.hasMatch()) {
        m_speedTestUpload = formatMbps(
            toMbps(
                uploadMatch.captured(1).toDouble(),
                uploadMatch.captured(2)
            )
        );
        receivedResult = true;
    }

    if (receivedResult) {
        m_lastSpeedTestTime = QDateTime::currentDateTime();
        m_speedTestUpdated = QStringLiteral("UPDATED NOW");
        m_speedTestAge = QStringLiteral("UPDATED NOW");
    } else if (m_speedTestDownload == QStringLiteral("--") &&
               m_speedTestUpload == QStringLiteral("--")) {
        m_speedTestUpdated = QStringLiteral("TEST FAILED");
        m_speedTestAge = QStringLiteral("TEST FAILED");
    }
}

/* Formatting */

QString SystemMonitor::formatBytes(quint64 bytes) const
{
    const QStringList units = {
        QStringLiteral("B"),
        QStringLiteral("KiB"),
        QStringLiteral("MiB"),
        QStringLiteral("GiB"),
        QStringLiteral("TiB")
    };

    double value = static_cast<double>(bytes);
    int unit = 0;

    while (value >= 1024.0 && unit < units.size() - 1) {
        value /= 1024.0;
        ++unit;
    }

    const int decimals = unit == 0 ? 0 : unit >= 3 ? 2 : 1;

    return QString::number(value, 'f', decimals) +
           QStringLiteral(" ") +
           units[unit];
}

QString SystemMonitor::formatSpeed(quint64 bytesPerSecond) const
{
    return formatBytes(bytesPerSecond) + QStringLiteral("/s");
}

QString SystemMonitor::formatMbps(double mbps) const
{
    mbps = qMax(0.0, mbps);

    if (mbps >= 100.0)
        return QString::number(mbps, 'f', 0) + QStringLiteral(" Mbps");

    if (mbps >= 10.0)
        return QString::number(mbps, 'f', 1) + QStringLiteral(" Mbps");

    return QString::number(mbps, 'f', 2) + QStringLiteral(" Mbps");
}

QString SystemMonitor::formatAge(const QDateTime &time) const
{
    if (!time.isValid())
        return QStringLiteral("MANUAL TEST READY");

    qint64 seconds = time.secsTo(QDateTime::currentDateTime());
    seconds = qMax<qint64>(0, seconds);

    if (seconds < 30)
        return QStringLiteral("NOW");

    if (seconds < 60)
        return QString::number(seconds) + QStringLiteral(" SEC AGO");

    const qint64 minutes = seconds / 60;

    if (minutes < 60) {
        return QString::number(minutes) +
               (minutes == 1
                    ? QStringLiteral(" MIN AGO")
                    : QStringLiteral(" MINS AGO"));
    }

    const qint64 hours = minutes / 60;

    if (hours < 24) {
        return QString::number(hours) +
               (hours == 1
                    ? QStringLiteral(" HR AGO")
                    : QStringLiteral(" HRS AGO"));
    }

    const qint64 days = hours / 24;

    return QString::number(days) +
           (days == 1
                ? QStringLiteral(" DAY AGO")
                : QStringLiteral(" DAYS AGO"));
}

QString SystemMonitor::formatDuration(quint64 totalSeconds) const
{
    const quint64 days = totalSeconds / 86400;
    totalSeconds %= 86400;

    const quint64 hours = totalSeconds / 3600;
    totalSeconds %= 3600;

    const quint64 minutes = totalSeconds / 60;
    const quint64 seconds = totalSeconds % 60;

    if (days > 0) {
        return QStringLiteral("%1d %2h %3m")
            .arg(days)
            .arg(hours)
            .arg(minutes);
    }

    if (hours > 0) {
        return QStringLiteral("%1h %2m %3s")
            .arg(hours)
            .arg(minutes)
            .arg(seconds);
    }

    if (minutes > 0) {
        return QStringLiteral("%1m %2s")
            .arg(minutes)
            .arg(seconds);
    }

    return QStringLiteral("%1s").arg(seconds);
}

quint64 SystemMonitor::parseHumanBytes(const QString &value) const
{
    const QRegularExpression pattern(
        QStringLiteral("([0-9.]+)\\s*([A-Za-z]+)")
    );
    const QRegularExpressionMatch match = pattern.match(value);

    if (!match.hasMatch())
        return 0;

    const double number = match.captured(1).toDouble();
    const QString unit = match.captured(2).toLower();

    double multiplier = 1.0;

    if (unit.startsWith(QStringLiteral("kb")) ||
        unit.startsWith(QStringLiteral("kib"))) {
        multiplier = 1024.0;
    } else if (unit.startsWith(QStringLiteral("mb")) ||
               unit.startsWith(QStringLiteral("mib"))) {
        multiplier = 1024.0 * 1024.0;
    } else if (unit.startsWith(QStringLiteral("gb")) ||
               unit.startsWith(QStringLiteral("gib"))) {
        multiplier = 1024.0 * 1024.0 * 1024.0;
    } else if (unit.startsWith(QStringLiteral("tb")) ||
               unit.startsWith(QStringLiteral("tib"))) {
        multiplier = 1024.0 * 1024.0 * 1024.0 * 1024.0;
    }

    return static_cast<quint64>(number * multiplier);
}
