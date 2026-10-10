#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class DeveloperModeManager;

#ifndef NEUTRONOS_STATE_DIR
#define NEUTRONOS_STATE_DIR "/var/lib/neutronos"
#endif

class PowerModeManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)
    Q_PROPERTY(QString displayName READ displayName NOTIFY modeChanged)
    Q_PROPERTY(QString iconName READ iconName NOTIFY modeChanged)
    Q_PROPERTY(bool performanceModeEnabled READ performanceModeEnabled NOTIFY modeChanged)
    Q_PROPERTY(bool normalModeEnabled READ normalModeEnabled NOTIFY modeChanged)
    Q_PROPERTY(bool available READ available NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY statusChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusChanged)
    Q_PROPERTY(int normalFrequencyCapMhz READ normalFrequencyCapMhz CONSTANT)

public:
    explicit PowerModeManager(DeveloperModeManager *developerModeManager,
                              QObject *parent = nullptr);

    QString mode() const;
    QString displayName() const;
    QString iconName() const;

    bool performanceModeEnabled() const;
    bool normalModeEnabled() const;
    bool available() const;

    QString lastError() const;
    QString statusMessage() const;

    int normalFrequencyCapMhz() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap togglePerformanceMode();
    Q_INVOKABLE QVariantMap setPerformanceMode(bool enabled);
    Q_INVOKABLE QVariantMap setNormalMode();

signals:
    void modeChanged();
    void statusChanged();
    void operationCompleted(bool ok, const QString &message);

private slots:
    void handleDeveloperModeChanged();

private:
    static constexpr quint64 kNormalMaxFrequencyKhz = 1500000ULL;

    DeveloperModeManager *m_developerModeManager = nullptr;

    QString m_mode = QStringLiteral("normal");
    QString m_lastError;
    QString m_statusMessage = QStringLiteral("Normal mode active");
    bool m_available = false;

    QString stateFilePath() const;
    QStringList policyDirectories() const;

    bool developerModeEnabled() const;

    QString readTextFile(const QString &path) const;
    quint64 readUnsignedFile(const QString &path) const;
    bool writeTextFile(const QString &path,
                       const QString &value,
                       QString *errorMessage = nullptr) const;

    QStringList availableGovernors(const QString &policyDirectory) const;
    QString preferredNormalGovernor(const QString &policyDirectory) const;
    quint64 hardwareMaximumKhz(const QString &policyDirectory) const;
    quint64 hardwareMinimumKhz(const QString &policyDirectory) const;

    bool managedPerformanceProfileActive() const;

    bool applyPerformance(QString *errorMessage = nullptr);
    bool applyNormal(QString *errorMessage = nullptr);

    bool savePersistedMode(const QString &mode,
                           QString *errorMessage = nullptr) const;
    QString loadPersistedMode() const;

    void setMode(const QString &mode);
    void setAvailable(bool available);
    void setStatus(const QString &statusMessage,
                   const QString &errorMessage = QString());

    QVariantMap result(bool ok, const QString &message) const;
};
