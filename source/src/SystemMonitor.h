#pragma once

#include <QObject>
#include <QDateTime>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

/*
    ========================================================================
                              SYSTEM MONITOR
    ========================================================================

    SystemMonitor is the read-mostly telemetry backend used by:

        - qml/systemwidgets/SystemOverview.qml
        - CpuMonitorModal.qml
        - MemoryMonitorModal.qml
        - StorageDisplayModal.qml
        - TemperatureHistoryModal.qml

    Design rules:

        - Fast telemetry stays inexpensive and non-blocking.
        - Expensive process/service discovery remains asynchronous.
        - Temperature history is retained in a bounded in-memory ring buffer.
        - Storage display choices are persisted by stable mount identifiers.
        - QML receives structured QVariantList data, not command output.
        - Existing property names are preserved for compatibility.
        - New aliases match the production modal contracts.
        - SystemMonitor never executes privileged/destructive actions.
*/

class SystemMonitor final : public QObject
{
    Q_OBJECT

    /*
        --------------------------------------------------------------------
                                CPU SUMMARY
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString cpu
               READ cpu
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString cpuText
               READ cpu
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString cpuDisplay
               READ cpu
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(int cpuPercent
               READ cpuPercent
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(int cpuUsagePercent
               READ cpuPercent
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(int cpuUsage
               READ cpuPercent
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(int cpuLoadPercent
               READ cpuPercent
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(int cpuLoad
               READ cpuPercent
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString cpuFrequency
               READ cpuFrequency
               NOTIFY cpuMonitorChanged)
    Q_PROPERTY(quint64 cpuFrequencyHz READ cpuFrequencyHz NOTIFY cpuMonitorChanged)
    Q_PROPERTY(QString cpuModel READ cpuModel NOTIFY cpuMonitorChanged)
    Q_PROPERTY(bool cpuValid READ cpuValid NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString cpuFrequencyText
               READ cpuFrequency
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString frequency
               READ cpuFrequency
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString clockSpeed
               READ cpuFrequency
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString cpuGovernor
               READ cpuGovernor
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString governor
               READ cpuGovernor
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString scalingGovernor
               READ cpuGovernor
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString loadAverage
               READ loadAverage
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QString loadAverageText
               READ loadAverage
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(double load1
               READ load1
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(double load5
               READ load5
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(double load15
               READ load15
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(int processCount
               READ processCount
               NOTIFY processDataChanged)

    Q_PROPERTY(int activeProcessCount
               READ processCount
               NOTIFY processDataChanged)

    /*
        Each core entry is expected to contain:

            index
            name
            usage
            frequency
    */
    Q_PROPERTY(QVariantList cpuCores
               READ cpuCores
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QVariantList perCoreUsage
               READ cpuCores
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QVariantList cpuCoreUsage
               READ cpuCores
               NOTIFY cpuMonitorChanged)

    Q_PROPERTY(QVariantList coreUsage
               READ cpuCores
               NOTIFY cpuMonitorChanged)

    /*
        Deterministic per-core accessors for QML.

        QVariantList conversion differs slightly between Qt/QML revisions.
        cpuCoreCount + cpuCoreAt() lets the CPU modal rebuild a small native
        ListModel without copying or guessing how a QVariantList is exposed.
    */
    Q_PROPERTY(int cpuCoreCount
               READ cpuCoreCount
               NOTIFY cpuMonitorChanged)

    /*
        Each process entry is expected to contain:

            pid
            name
            user
            cpu
            memory
            memoryBytes
            state
            runtime
    */
    Q_PROPERTY(QVariantList cpuProcesses
               READ cpuProcesses
               NOTIFY processDataChanged)

    Q_PROPERTY(QVariantList processesByCpu
               READ cpuProcesses
               NOTIFY processDataChanged)

    Q_PROPERTY(QVariantList processList
               READ processList
               NOTIFY processDataChanged)

    Q_PROPERTY(QVariantList processes
               READ processList
               NOTIFY processDataChanged)

    Q_PROPERTY(QVariantList topCpuProcesses
               READ topCpuProcesses
               NOTIFY processDataChanged)

    /*
        --------------------------------------------------------------------
                              MEMORY SUMMARY
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString ram
               READ ram
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memory
               READ ram
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryText
               READ ram
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString ramText
               READ ram
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int ramPercent
               READ ramPercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int memoryPercent
               READ ramPercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int memoryUsage
               READ ramPercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int memoryUsagePercent
               READ ramPercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int ramUsage
               READ ramPercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int ramUsagePercent
               READ ramPercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString ramUsed
               READ ramUsed
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryUsed
               READ ramUsed
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString ramUsedText
               READ ramUsed
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryUsedText
               READ ramUsed
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString ramTotal
               READ ramTotal
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryTotal
               READ ramTotal
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString ramTotalText
               READ ramTotal
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryTotalText
               READ ramTotal
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString ramAvailable
               READ ramAvailable
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryAvailable
               READ ramAvailable
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString ramAvailableText
               READ ramAvailable
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryAvailableText
               READ ramAvailable
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryCached
               READ memoryCached
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString cachedMemory
               READ memoryCached
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryCachedText
               READ memoryCached
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString cachedMemoryText
               READ memoryCached
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryBuffers
               READ memoryBuffers
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString bufferedMemory
               READ memoryBuffers
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString memoryBuffersText
               READ memoryBuffers
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString bufferedMemoryText
               READ memoryBuffers
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 ramUsedBytes
               READ ramUsedBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 memoryUsedBytes
               READ ramUsedBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 ramTotalBytes
               READ ramTotalBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 memoryTotalBytes
               READ ramTotalBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 ramAvailableBytes
               READ ramAvailableBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 memoryAvailableBytes
               READ ramAvailableBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 memoryCachedBytes
               READ memoryCachedBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 memoryBuffersBytes
               READ memoryBuffersBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString swapUsed
               READ swapUsed
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString swapUsedText
               READ swapUsed
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString swapTotal
               READ swapTotal
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QString swapTotalText
               READ swapTotal
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 swapUsedBytes
               READ swapUsedBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(quint64 swapTotalBytes
               READ swapTotalBytes
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int swapPercent
               READ swapPercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int swapUsagePercent
               READ swapPercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int memoryPressure
               READ memoryPressurePercent
               NOTIFY memoryMonitorChanged)
    Q_PROPERTY(bool memoryValid READ memoryValid NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int memoryPressurePercent
               READ memoryPressurePercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(int pressurePercent
               READ memoryPressurePercent
               NOTIFY memoryMonitorChanged)

    Q_PROPERTY(QVariantList memoryProcesses
               READ memoryProcesses
               NOTIFY processDataChanged)

    Q_PROPERTY(QVariantList processesByMemory
               READ memoryProcesses
               NOTIFY processDataChanged)

    Q_PROPERTY(QVariantList topRamProcesses
               READ topRamProcesses
               NOTIFY processDataChanged)

    /*
        --------------------------------------------------------------------
                                STORAGE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QVariantList mounts
               READ mounts
               NOTIFY storageChanged)

    Q_PROPERTY(QVariantList storageDevices
               READ mounts
               NOTIFY storageChanged)

    Q_PROPERTY(QString bootStorage
               READ bootStorage
               NOTIFY storageChanged)

    Q_PROPERTY(int bootStoragePercent
               READ bootStoragePercent
               NOTIFY storageChanged)

    Q_PROPERTY(QString mediaStorage
               READ mediaStorage
               NOTIFY storageChanged)

    Q_PROPERTY(int mediaStoragePercent
               READ mediaStoragePercent
               NOTIFY storageChanged)

    /*
        Stable identifiers for the two mounts displayed by System Overview.
        These values survive mount-order changes and reconnects.
    */
    Q_PROPERTY(QVariantList displayedMountIds
               READ displayedMountIds
               NOTIFY displayedMountIdsChanged)

    Q_PROPERTY(QVariantList selectedStorageIds
               READ displayedMountIds
               NOTIFY displayedMountIdsChanged)

    /*
        Resolved slot objects. An unavailable saved device remains represented
        with connected=false so the UI does not silently replace it.
    */
    Q_PROPERTY(QVariantList storageDisplaySlots
               READ storageDisplaySlots
               NOTIFY displayedMountIdsChanged)

    /*
        --------------------------------------------------------------------
                              TEMPERATURE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString temperature
               READ temperature
               NOTIFY temperatureChanged)

    Q_PROPERTY(QString temp
               READ temperature
               NOTIFY temperatureChanged)

    Q_PROPERTY(QString cpuTemp
               READ temperature
               NOTIFY temperatureChanged)

    Q_PROPERTY(double cpuTemperature
               READ cpuTemperature
               NOTIFY cpuTemperatureChanged)
    Q_PROPERTY(double temperatureCelsius READ temperatureCelsius NOTIFY cpuTemperatureChanged)
    Q_PROPERTY(double temperatureFahrenheit READ cpuTemperature NOTIFY cpuTemperatureChanged)
    Q_PROPERTY(bool temperatureValid READ temperatureValid NOTIFY cpuTemperatureChanged)

    Q_PROPERTY(double temperatureValue
               READ cpuTemperature
               NOTIFY cpuTemperatureChanged)

    Q_PROPERTY(QString temperatureUnit
               READ temperatureUnit
               CONSTANT)

    Q_PROPERTY(QString thermalUnit
               READ temperatureUnit
               CONSTANT)

    Q_PROPERTY(QString thermalStatus
               READ thermalStatus
               NOTIFY thermalStatusChanged)

    Q_PROPERTY(QString throttleStatus
               READ thermalStatus
               NOTIFY thermalStatusChanged)

    Q_PROPERTY(QString thermalState
               READ thermalStatus
               NOTIFY thermalStatusChanged)

    Q_PROPERTY(QString throttled
               READ thermalStatus
               NOTIFY thermalStatusChanged)

    Q_PROPERTY(bool thermalThrottled
               READ thermalThrottled
               NOTIFY thermalThrottledChanged)

    Q_PROPERTY(int throttlingEvents
               READ throttlingEvents
               NOTIFY throttlingEventsChanged)

    Q_PROPERTY(int thermalThrottleCount
               READ throttlingEvents
               NOTIFY throttlingEventsChanged)

    Q_PROPERTY(double temperatureWarningThreshold
               READ temperatureWarningThreshold
               NOTIFY temperatureThresholdsChanged)

    Q_PROPERTY(double thermalWarningThreshold
               READ temperatureWarningThreshold
               NOTIFY temperatureThresholdsChanged)

    Q_PROPERTY(double warningTemperature
               READ temperatureWarningThreshold
               NOTIFY temperatureThresholdsChanged)

    Q_PROPERTY(double temperatureCriticalThreshold
               READ temperatureCriticalThreshold
               NOTIFY temperatureThresholdsChanged)

    Q_PROPERTY(double thermalCriticalThreshold
               READ temperatureCriticalThreshold
               NOTIFY temperatureThresholdsChanged)

    Q_PROPERTY(double criticalTemperature
               READ temperatureCriticalThreshold
               NOTIFY temperatureThresholdsChanged)

    Q_PROPERTY(QVariantList temperatureHistory
               READ temperatureHistory
               NOTIFY temperatureHistoryChanged)

    Q_PROPERTY(QVariantList thermalHistory
               READ temperatureHistory
               NOTIFY thermalHistoryChanged)

    Q_PROPERTY(QVariantList cpuTemperatureHistory
               READ temperatureHistory
               NOTIFY cpuTemperatureHistoryChanged)

    Q_PROPERTY(int temperatureHistoryRevision
               READ temperatureHistoryRevision
               NOTIFY temperatureHistoryRevisionChanged)
    Q_PROPERTY(double learnedTemperatureBaseline
               READ learnedTemperatureBaseline
               NOTIFY thermalBaselineChanged)
    Q_PROPERTY(QString adaptiveThermalStatus
               READ adaptiveThermalStatus
               NOTIFY adaptiveThermalStatusChanged)

    /*
        --------------------------------------------------------------------
                                NETWORK
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString network
               READ network
               NOTIFY systemChanged)

    Q_PROPERTY(QString wifiInterface
               READ wifiInterface
               NOTIFY systemChanged)

    Q_PROPERTY(QString interface
               READ wifiInterface
               NOTIFY systemChanged)

    Q_PROPERTY(QString networkInterface
               READ activeInterface
               NOTIFY systemChanged)
    Q_PROPERTY(QString activeInterface READ activeInterface NOTIFY systemChanged)
    Q_PROPERTY(QString connectionType READ connectionType NOTIFY systemChanged)
    Q_PROPERTY(bool networkConnected READ networkConnected NOTIFY systemChanged)
    Q_PROPERTY(bool networkValid READ networkValid NOTIFY systemChanged)
    Q_PROPERTY(quint64 rxBytesPerSecond READ rxBytesPerSecond NOTIFY systemChanged)
    Q_PROPERTY(quint64 txBytesPerSecond READ txBytesPerSecond NOTIFY systemChanged)

    Q_PROPERTY(QString ssid
               READ ssid
               NOTIFY systemChanged)

    Q_PROPERTY(QString networkSsid
               READ ssid
               NOTIFY systemChanged)

    Q_PROPERTY(QString wifiSsid
               READ ssid
               NOTIFY systemChanged)

    Q_PROPERTY(QString networkName
               READ ssid
               NOTIFY systemChanged)

    Q_PROPERTY(QString wifiSignal
               READ wifiSignal
               NOTIFY systemChanged)

    Q_PROPERTY(QString localIp
               READ localIp
               NOTIFY systemChanged)

    Q_PROPERTY(QString ip
               READ localIp
               NOTIFY systemChanged)

    Q_PROPERTY(QString ipv4
               READ localIp
               NOTIFY systemChanged)

    Q_PROPERTY(QString networkIp
               READ localIp
               NOTIFY systemChanged)

    Q_PROPERTY(QString tailscaleIp
               READ tailscaleIp
               NOTIFY systemChanged)

    Q_PROPERTY(QString tailnetIp
               READ tailscaleIp
               NOTIFY systemChanged)

    Q_PROPERTY(QString tsIp
               READ tailscaleIp
               NOTIFY systemChanged)

    Q_PROPERTY(QString upload
               READ upload
               NOTIFY systemChanged)

    Q_PROPERTY(QString uploadSpeed
               READ upload
               NOTIFY systemChanged)

    Q_PROPERTY(QString download
               READ download
               NOTIFY systemChanged)

    Q_PROPERTY(QString downloadSpeed
               READ download
               NOTIFY systemChanged)

    Q_PROPERTY(QString speedTestDownload
               READ speedTestDownload
               NOTIFY systemChanged)

    Q_PROPERTY(QString speedTestUpload
               READ speedTestUpload
               NOTIFY systemChanged)

    Q_PROPERTY(QString speedTestUpdated
               READ speedTestUpdated
               NOTIFY systemChanged)

    Q_PROPERTY(QString speedTestAge
               READ speedTestAge
               NOTIFY systemChanged)

    Q_PROPERTY(bool speedTestRunning
               READ speedTestRunning
               NOTIFY systemChanged)

    /*
        --------------------------------------------------------------------
                            GENERAL SYSTEM STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString uptime
               READ uptime
               NOTIFY systemChanged)

    Q_PROPERTY(QString systemUptime
               READ uptime
               NOTIFY systemChanged)
    Q_PROPERTY(quint64 uptimeSeconds READ uptimeSeconds NOTIFY systemChanged)
    Q_PROPERTY(QDateTime bootDateTime READ bootDateTime NOTIFY systemChanged)
    Q_PROPERTY(bool uptimeValid READ uptimeValid NOTIFY systemChanged)
    Q_PROPERTY(bool dashboardActive READ dashboardActive WRITE setDashboardActive NOTIFY dashboardActiveChanged)
    Q_PROPERTY(int fastUpdateIntervalMs READ fastUpdateIntervalMs NOTIFY dashboardActiveChanged)

    Q_PROPERTY(QString lastAptUpdate
               READ lastAptUpdate
               NOTIFY systemChanged)

    Q_PROPERTY(QString aptLastUpdate
               READ lastAptUpdate
               NOTIFY systemChanged)

    Q_PROPERTY(QString lastUpdate
               READ lastAptUpdate
               NOTIFY systemChanged)

    Q_PROPERTY(QString systemMode
               READ systemMode
               NOTIFY systemChanged)

    Q_PROPERTY(QVariantList networkApps
               READ networkApps
               NOTIFY systemChanged)

    Q_PROPERTY(QVariantList serviceHealth
               READ serviceHealth
               NOTIFY systemChanged)

public:
    explicit SystemMonitor(QObject *parent = nullptr);

    /*
        CPU
    */
    QString cpu() const;
    int cpuPercent() const;
    QString cpuFrequency() const;
    quint64 cpuFrequencyHz() const;
    QString cpuModel() const;
    bool cpuValid() const;
    QString cpuGovernor() const;
    QString loadAverage() const;
    double load1() const;
    double load5() const;
    double load15() const;
    int processCount() const;
    QVariantList cpuCores() const;
    int cpuCoreCount() const;
    Q_INVOKABLE QVariantMap cpuCoreAt(int index) const;
    QVariantList cpuProcesses() const;
    QVariantList processList() const;
    QVariantList topCpuProcesses() const;

    /*
        Memory
    */
    QString ram() const;
    int ramPercent() const;
    QString ramUsed() const;
    QString ramTotal() const;
    QString ramAvailable() const;
    QString memoryCached() const;
    QString memoryBuffers() const;

    quint64 ramUsedBytes() const;
    quint64 ramTotalBytes() const;
    quint64 ramAvailableBytes() const;
    quint64 memoryCachedBytes() const;
    quint64 memoryBuffersBytes() const;

    QString swapUsed() const;
    QString swapTotal() const;
    quint64 swapUsedBytes() const;
    quint64 swapTotalBytes() const;
    int swapPercent() const;
    int memoryPressurePercent() const;
    bool memoryValid() const;

    QVariantList memoryProcesses() const;
    QVariantList topRamProcesses() const;

    /*
        Storage
    */
    QVariantList mounts() const;
    QString bootStorage() const;
    int bootStoragePercent() const;
    QString mediaStorage() const;
    int mediaStoragePercent() const;

    QVariantList displayedMountIds() const;
    QVariantList storageDisplaySlots() const;

    /*
        Temperature
    */
    QString temperature() const;
    double cpuTemperature() const;
    double temperatureCelsius() const;
    bool temperatureValid() const;
    QString temperatureUnit() const;
    QString thermalStatus() const;
    bool thermalThrottled() const;
    int throttlingEvents() const;
    double temperatureWarningThreshold() const;
    double temperatureCriticalThreshold() const;
    QVariantList temperatureHistory() const;
    int temperatureHistoryRevision() const;
    double learnedTemperatureBaseline() const;
    QString adaptiveThermalStatus() const;

    /*
        Network
    */
    QString network() const;
    QString wifiInterface() const;
    QString activeInterface() const;
    QString connectionType() const;
    bool networkConnected() const;
    bool networkValid() const;
    quint64 rxBytesPerSecond() const;
    quint64 txBytesPerSecond() const;
    QString ssid() const;
    QString wifiSignal() const;
    QString localIp() const;
    QString tailscaleIp() const;
    QString upload() const;
    QString download() const;

    QString speedTestDownload() const;
    QString speedTestUpload() const;
    QString speedTestUpdated() const;
    QString speedTestAge() const;
    bool speedTestRunning() const;

    /*
        General
    */
    QString uptime() const;
    quint64 uptimeSeconds() const;
    QDateTime bootDateTime() const;
    bool uptimeValid() const;
    bool dashboardActive() const;
    int fastUpdateIntervalMs() const;
    Q_INVOKABLE void setDashboardActive(bool active);
    QString lastAptUpdate() const;
    QString systemMode() const;

    QVariantList networkApps() const;
    QVariantList serviceHealth() const;

    /*
        Existing full refresh.
    */
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void runSpeedTestNow();

    /*
        Modal-specific refresh entry points.
        These keep QML free of process parsing and command execution.
    */
    Q_INVOKABLE void refreshCpuMonitor();
    Q_INVOKABLE void refreshMemoryMonitor();
    Q_INVOKABLE QVariantMap memorySnapshot() const;
    Q_INVOKABLE void refreshProcesses();
    Q_INVOKABLE void refreshStorage();
    Q_INVOKABLE void refreshMounts();
    Q_INVOKABLE void refreshTemperatureHistory();
    Q_INVOKABLE void refreshThermalHistory();

    /*
        Local list ordering. The modals can sort locally, but these methods
        let the backend preserve a requested order for subsequent snapshots.
    */
    Q_INVOKABLE void setProcessSort(const QString &sortKey);
    Q_INVOKABLE void setMemoryProcessSort(const QString &sortKey);

    /* PATCH16A_PROCESS_DETAILS_BEGIN
        Returns a structured snapshot for one Linux process. The method reads
        only the selected /proc entry and is called on demand when the user
        opens Process Details.
    */
    Q_INVOKABLE QVariantMap processDetails(qint64 pid) const;
    /* PATCH16A_PROCESS_DETAILS_END */

    /*
        Persists the two System Overview storage slots.

        Accepted payloads:
            - QVariantList / QStringList of two stable IDs.
            - QVariantMap with ids, slot1Id, slot2Id, or slots.
    */
    Q_INVOKABLE bool setDisplayedMounts(const QVariant &payload);

    /*
        Temperature history API. Range values are seconds.
    */
    Q_INVOKABLE QVariantList getTemperatureHistory(int rangeSeconds) const;
    Q_INVOKABLE void requestTemperatureHistory(int rangeSeconds);
    Q_INVOKABLE void setTemperatureHistoryRange(int rangeSeconds);

signals:
    /*
        Compatibility signal for the existing System Overview.
    */
    void systemChanged();

    /*
        Domain-specific signals avoid forcing every detailed modal to rebuild
        when an unrelated metric changes.
    */
    void cpuMonitorChanged();
    void memoryMonitorChanged();
    void processDataChanged();
    void storageChanged();
    void displayedMountIdsChanged();

    void temperatureChanged();
    void cpuTemperatureChanged();
    void thermalStatusChanged();
    void thermalThrottledChanged();
    void throttlingEventsChanged();
    void temperatureThresholdsChanged();

    void temperatureHistoryChanged();
    void thermalHistoryChanged();
    void cpuTemperatureHistoryChanged();
    void temperatureHistoryRevisionChanged();
    void thermalBaselineChanged();
    void adaptiveThermalStatusChanged();
    void dashboardActiveChanged();

private:
    struct ThermalSample
    {
        qint64 timestampMs = 0;
        double temperatureF = 0.0;
        bool throttled = false;
    };

    /*
        Timers
    */
    QTimer m_fastTimer;
    QTimer m_cacheTimer;
    QTimer m_speedTestTimer;
    QTimer m_temperatureHistoryTimer;

    /*
        CPU
    */
    QString m_cpu = "--";
    int m_cpuPercent = 0;
    QString m_cpuFrequency = "--";
    quint64 m_cpuFrequencyHz = 0;
    QString m_cpuModel = "--";
    bool m_cpuValid = false;
    QString m_cpuGovernor = "--";
    QString m_loadAverage = "--";
    double m_load1 = 0.0;
    double m_load5 = 0.0;
    double m_load15 = 0.0;
    int m_processCount = 0;

    QVariantList m_cpuCores;
    QVariantList m_processList;
    QVariantList m_cpuProcesses;
    QVariantList m_topCpuProcesses;

    QVector<quint64> m_lastCoreTotal;
    QVector<quint64> m_lastCoreIdle;

    QString m_processSort = QStringLiteral("cpu");
    QString m_memoryProcessSort = QStringLiteral("memory");

    /*
        Memory
    */
    QString m_ram = "--";
    int m_ramPercent = 0;
    QString m_ramUsed = "--";
    QString m_ramTotal = "--";
    QString m_ramAvailable = "--";
    QString m_memoryCached = "--";
    QString m_memoryBuffers = "--";

    quint64 m_ramUsedBytes = 0;
    quint64 m_ramTotalBytes = 0;
    quint64 m_ramAvailableBytes = 0;
    quint64 m_memoryCachedBytes = 0;
    quint64 m_memoryBuffersBytes = 0;

    QString m_swapUsed = "--";
    QString m_swapTotal = "--";
    quint64 m_swapUsedBytes = 0;
    quint64 m_swapTotalBytes = 0;
    int m_swapPercent = 0;
    int m_memoryPressurePercent = 0;
    bool m_memoryValid = false;

    QVariantList m_memoryProcesses;
    QVariantList m_topRamProcesses;

    /*
        Storage
    */
    QVariantList m_mounts;

    QString m_bootStorage = "--";
    int m_bootStoragePercent = 0;
    QString m_mediaStorage = "--";
    int m_mediaStoragePercent = 0;

    QStringList m_displayedMountIds;
    QVariantList m_storageDisplaySlots;

    /*
        Temperature
    */
    QString m_temperature = "--";
    double m_cpuTemperatureF = 0.0;
    double m_cpuTemperatureC = 0.0;
    bool m_temperatureValid = false;
    QString m_thermalStatus = QStringLiteral("No Throttle");
    bool m_thermalThrottled = false;
    int m_throttlingEvents = 0;

    double m_temperatureWarningThresholdF = 150.0;
    double m_temperatureCriticalThresholdF = 176.0;

    QVector<ThermalSample> m_temperatureHistorySamples;
    int m_temperatureHistoryRevision = 0;
    int m_temperatureHistoryRangeSeconds = 3600;
    double m_learnedTemperatureBaselineF = 0.0;
    int m_thermalBaselineSampleCount = 0;

    static constexpr int TemperatureHistoryCapacity = 1440;
    static constexpr int TemperatureHistorySampleIntervalMs = 60000;

    void loadThermalBaseline();
    void saveThermalBaseline() const;
    void updateAdaptiveThermalBaseline();

    /*
        Network
    */
    QString m_network = QStringLiteral("Disconnected");
    QString m_wifiInterface = "--";
    QString m_activeInterface = "--";
    QString m_connectionType = "disconnected";
    bool m_networkValid = false;
    quint64 m_rxBytesPerSecond = 0;
    quint64 m_txBytesPerSecond = 0;
    QString m_lastNetworkInterface;
    qint64 m_lastNetworkSampleMs = 0;
    QString m_ssid = "--";
    QString m_wifiSignal = "--";
    QString m_localIp = "--";
    QString m_tailscaleIp = "--";
    QString m_upload = QStringLiteral("0 B/s");
    QString m_download = QStringLiteral("0 B/s");

    QString m_speedTestDownload = "--";
    QString m_speedTestUpload = "--";
    QString m_speedTestUpdated = QStringLiteral("MANUAL TEST READY");
    QString m_speedTestAge = QStringLiteral("MANUAL TEST READY");
    bool m_speedTestRunning = false;
    QDateTime m_lastSpeedTestTime;

    /*
        General
    */
    QString m_uptime = "--";
    quint64 m_uptimeSeconds = 0;
    QDateTime m_bootDateTime;
    bool m_uptimeValid = false;
    bool m_dashboardActive = false;
    QString m_lastAptUpdate = "--";
    QString m_systemMode = QStringLiteral("IDLE MODE");

    QVariantList m_networkApps;
    QVariantList m_serviceHealth;

    /*
        Sampling state
    */
    quint64 m_lastTotal = 0;
    quint64 m_lastIdle = 0;
    bool m_cpuCounterBaselineReady = false;

    /*
        CPU telemetry sampling state.

        CPU percentage is derived from cumulative /proc/stat counters. These
        fields prevent modal refresh requests from resetting the sampling
        window and provide an independent /proc/uptime fallback plus light
        smoothing for a stable controller UI.
    */
    qint64 m_lastCpuSampleMs = 0;
    double m_lastCpuUptimeSeconds = 0.0;
    double m_lastCpuIdleSeconds = 0.0;
    double m_cpuSmoothedPercent = 0.0;
    QVector<double> m_coreSmoothedPercent;

    /*
        Per-core fallback state. When /proc/stat is unavailable, Linux sysfs
        cpuidle residency counters still provide independent cumulative idle
        time for each logical core. The backend converts those deltas into
        real per-core utilization instead of copying the aggregate value.
    */
    QVector<quint64> m_lastSysfsCoreIdleUsec;
    qint64 m_lastCoreIdleSampleMs = 0;

    int m_consecutiveZeroCpuSamples = 0;

    quint64 m_lastRx = 0;
    quint64 m_lastTx = 0;

    int m_fastTick = 0;
    int m_cacheTick = 0;

    bool m_topProcessBusy = false;

    /*
        Native /proc process sampler state.

        The old implementation launched `ps` repeatedly. On a small Pi this
        could consume an entire core and then report itself as a top process.
        Cumulative process ticks are retained here so the asynchronous native
        sampler can calculate interval CPU usage without spawning utilities.
    */
    QHash<qlonglong, quint64> m_lastProcessCpuTicks;
    QHash<qlonglong, quint64> m_lastProcessStartTicks;
    quint64 m_lastProcessTotalTicks = 0;
    qint64 m_lastProcessRefreshMs = 0;

    bool m_networkAppsBusy = false;
    bool m_serviceHealthBusy = false;

    QHash<QString, quint64> m_lastContainerRx;
    QHash<QString, quint64> m_lastContainerTx;

    /*
        Refresh orchestration
    */
    void refreshFast();
    void refreshCache();

    void updateCpu();
    void updateCpuDetails();
    void updateLoadAverage();
    void updateProcessCount();

    void updateRam();
    void updateMemoryPressure();

    void updateMounts();
    void rebuildStorageDisplaySlots();
    void loadDisplayedMountIds();
    bool saveDisplayedMountIds() const;
    QStringList parseDisplayedMountIds(const QVariant &payload) const;

    void updateTemperature();
    void updateThermalStatus();
    void sampleTemperatureHistory();
    void appendTemperatureSample(double temperatureF,
                                 bool throttled,
                                 qint64 timestampMs = 0);
    void emitTemperatureHistorySignals();

    void updateNetwork();
    void updateWifiSignal(const QString &interfaceName);
    void updateUptime();
    void updateLastAptUpdate();
    void updateSystemMode();

    void updateTopProcessesAsync();
    void applyProcessSnapshot(const QVariantList &processes);
    void updateNetworkAppsAsync();
    void updateServiceHealthAsync();

    void runCachedSpeedTest();
    void updateSpeedTestAge();
    void parseSpeedTestOutput(const QString &output);

    /*
        Detection helpers
    */
    QString detectWifiInterface() const;
    QString detectSsid(const QString &interfaceName) const;
    QString detectTailscaleIp() const;
    QString detectCpuFrequency() const;
    quint64 detectCpuFrequencyHz() const;
    QString detectCpuGovernor() const;

    /*
        Formatting helpers
    */
    QString formatBytes(quint64 bytes) const;
    QString formatSpeed(quint64 bytesPerSecond) const;
    QString formatMbps(double mbps) const;
    QString formatAge(const QDateTime &time) const;
    QString formatDuration(quint64 seconds) const;

    QString mountName(const QString &mountPoint,
                      const QString &device,
                      const QString &fsType) const;

    QString stableMountId(const QVariantMap &mount) const;

    bool shouldIgnoreMount(const QString &mountPoint,
                           const QString &device,
                           const QString &fsType) const;

    quint64 parseHumanBytes(const QString &value) const;

    bool commandExists(const QString &command) const;
    bool systemdUnitActive(const QString &unit) const;

    int runProcess(const QString &program,
                   const QStringList &arguments,
                   int timeoutMs,
                   QString *standardOutput = nullptr,
                   QString *standardError = nullptr) const;
};
