#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class PerformanceManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(QString piModel READ piModel NOTIFY stateChanged)
    Q_PROPERTY(QString modelKey READ modelKey NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap modelLimits READ modelLimits NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap telemetry READ telemetry NOTIFY telemetryChanged)
    Q_PROPERTY(QVariantMap currentConfiguration READ currentConfiguration NOTIFY configurationChanged)
    Q_PROPERTY(QVariantList defaultProfiles READ defaultProfiles NOTIFY stateChanged)
    Q_PROPERTY(QVariantList savedProfiles READ savedProfiles NOTIFY profilesChanged)
    Q_PROPERTY(QVariantList availableProfiles READ availableProfiles NOTIFY profilesChanged)
    Q_PROPERTY(QVariantList autoRecommendations READ autoRecommendations NOTIFY telemetryChanged)
    Q_PROPERTY(bool autoConfigAllowed READ autoConfigAllowed NOTIFY telemetryChanged)
    Q_PROPERTY(QString healthMessage READ healthMessage NOTIFY telemetryChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY operationChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY operationChanged)

public:
    explicit PerformanceManager(QObject *parent = nullptr);

    bool available() const;
    QString piModel() const;
    QString modelKey() const;
    QVariantMap modelLimits() const;
    QVariantMap telemetry() const;
    QVariantMap currentConfiguration() const;
    QVariantList defaultProfiles() const;
    QVariantList savedProfiles() const;
    QVariantList availableProfiles() const;
    QVariantList autoRecommendations() const;
    bool autoConfigAllowed() const;
    QString healthMessage() const;
    bool busy() const;
    QString lastMessage() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap profileConfiguration(const QString &profileName) const;
    Q_INVOKABLE QVariantMap saveCustomProfile(const QVariantMap &configuration);
    Q_INVOKABLE QVariantMap evaluateConfiguration(const QVariantMap &configuration) const;
    Q_INVOKABLE QVariantMap applyConfiguration(const QVariantMap &configuration,
                                                bool allowUnhealthyOverride = false);

signals:
    void stateChanged();
    void telemetryChanged();
    void configurationChanged();
    void operationChanged();
    void configurationApplied(const QVariantMap &configuration);
    void profilesChanged();

private:
    struct ModelSpec {
        QString key;
        QString filter;
        int stockMin = 600;
        int stockMax = 1500;
        int stockGpu = 500;
        int manualMax = 2000;
        int gpuMax = 650;
        int balancedMax = 1800;
        int balancedGpu = 525;
        int performanceMax = 2000;
        int performanceGpu = 550;
        int hotC = 75;
        int cautionC = 65;
    };

    QTimer m_refreshTimer;
    QString m_piModel;
    ModelSpec m_spec;
    QVariantMap m_telemetry;
    QVariantMap m_currentConfiguration;
    QVariantList m_profiles;
    QVariantList m_savedProfiles;
    QVariantList m_recommendations;
    QString m_healthMessage;
    bool m_available = false;
    bool m_autoConfigAllowed = false;
    bool m_busy = false;
    QString m_lastMessage;
    quint64 m_previousTotalJiffies = 0;
    quint64 m_previousIdleJiffies = 0;
    qint64 m_lastJournalCheckMs = 0;
    bool m_recentKernelWarning = false;
    bool m_runtimePolicySynchronized = false;
    int m_runtimePolicyAttempts = 0;

    static QString readTextFile(const QString &path);
    static bool writeTextFileAtomically(const QString &path,
                                        const QByteArray &data,
                                        QString *errorMessage);
    static QString runCommand(const QString &program,
                              const QStringList &arguments,
                              int timeoutMs = 1000);

    QString detectPiModel() const;
    ModelSpec determineModelSpec(const QString &model) const;
    QString configPath() const;
    QString profileStorePath() const;
    void loadSavedProfiles();
    bool persistSavedProfiles(QString *errorMessage = nullptr) const;
    QVariantMap stockConfiguration() const;
    QVariantMap normalizeConfiguration(const QVariantMap &configuration) const;
    QVariantMap parseManagedConfiguration() const;
    QVariantList buildDefaultProfiles() const;
    QVariantList buildRecommendations() const;
    QVariantMap sampleTelemetry();
    double sampleCpuLoadPercent();
    quint32 throttledFlags() const;
    bool coolingDetected() const;
    bool recentKernelPowerOrThermalWarning();
    bool writeManagedBlock(const QVariantMap &configuration,
                           QString *errorMessage);
    bool applyRuntimePolicy(const QVariantMap &configuration,
                            QString *errorMessage = nullptr);
    QVariantMap result(bool ok, const QString &message,
                       const QVariantMap &extra = QVariantMap()) const;
};
