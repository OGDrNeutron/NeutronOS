#pragma once

#include <QObject>
#include <QProcess>
#include <functional>
#include <QDateTime>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

class QDBusPendingCallWatcher;
class QDBusServiceWatcher;

/*
    ========================================================================
                       CLOCK SETTINGS MANAGER
    ========================================================================

    ClockSettingsManager owns the production clock preferences used by:

        - qml/modals/system/ClockSettingsModal.qml
        - the System Overview clock card
        - any shared Console header/footer clock

    Responsibilities:

        - Persist the user's 12-hour / 24-hour preference.
        - Persist the clock text tint.
        - Read and change the system timezone through systemd-timedated:
              org.freedesktop.timedate1
        - Enumerate real IANA timezone identifiers without shell commands.
        - Produce timezone-aware preview strings for QML.
        - Expose asynchronous operation results.
        - Use the existing authorized privileged helper for verified timezone changes.
        - Require fresh controller authentication for lockscreen timezone requests.

    Persistence:

        ~/NeutronOS/state/settings/clock.json

    System timezone:

        Existing neutronos privileged helper set-timezone operation;
        systemd-timedated provides authoritative timezone state.

    ClockSettingsModal.qml Apply payload:

        {
            "use24Hour": true,
            "format": "24",
            "timezone": "America/New_York",
            "textTint": "#7DF9FF",
            "clockTint": "#7DF9FF"
        }
*/

class ClockSettingsManager final : public QObject
{
    Q_OBJECT

    /*
        --------------------------------------------------------------------
                              TIME FORMAT
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool use24Hour
               READ use24Hour
               NOTIFY use24HourChanged)

    Q_PROPERTY(bool timeFormat24Hour
               READ use24Hour
               NOTIFY use24HourChanged)

    Q_PROPERTY(QString clockFormat
               READ clockFormat
               NOTIFY use24HourChanged)

    Q_PROPERTY(QString timeFormat
               READ clockFormat
               NOTIFY use24HourChanged)

    /*
        --------------------------------------------------------------------
                              TIMEZONE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString timezone
               READ timezone
               NOTIFY timezoneChanged)

    Q_PROPERTY(QString currentTimezone
               READ timezone
               NOTIFY timezoneChanged)

    Q_PROPERTY(QString timeZone
               READ timezone
               NOTIFY timezoneChanged)

    Q_PROPERTY(QVariantList availableTimezones
               READ availableTimezones
               NOTIFY availableTimezonesChanged)

    Q_PROPERTY(QVariantList timezones
               READ availableTimezones
               NOTIFY availableTimezonesChanged)

    Q_PROPERTY(QVariantList timeZones
               READ availableTimezones
               NOTIFY availableTimezonesChanged)

    Q_PROPERTY(int timezoneRevision
               READ timezoneRevision
               NOTIFY timezoneRevisionChanged)

    /*
        --------------------------------------------------------------------
                              CLOCK TINT
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString clockTint
               READ clockTint
               NOTIFY clockTintChanged)

    Q_PROPERTY(QString textTint
               READ clockTint
               NOTIFY clockTintChanged)

    Q_PROPERTY(QString clockTextColor
               READ clockTint
               NOTIFY clockTintChanged)

    /*
        --------------------------------------------------------------------
                              SERVICE STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool available
               READ available
               NOTIFY availabilityChanged)

    Q_PROPERTY(bool operationBusy
               READ operationBusy
               NOTIFY operationBusyChanged)

    Q_PROPERTY(QString lastError
               READ lastError
               NOTIFY lastErrorChanged)

    Q_PROPERTY(QString lastOperation
               READ lastOperation
               NOTIFY lastOperationChanged)

    Q_PROPERTY(QDateTime currentDateTime
               READ currentDateTime
               NOTIFY currentDateTimeChanged)

    Q_PROPERTY(bool lockscreenDetailsVisible READ lockscreenDetailsVisible WRITE setLockscreenDetailsVisible NOTIFY lockscreenDetailsVisibleChanged)
    Q_PROPERTY(bool lockscreenClockVisible READ lockscreenClockVisible WRITE setLockscreenClockVisible NOTIFY lockscreenClockVisibleChanged)
    Q_PROPERTY(bool lockscreenWelcomeVisible READ lockscreenWelcomeVisible WRITE setLockscreenWelcomeVisible NOTIFY lockscreenWelcomeVisibleChanged)
    Q_PROPERTY(QVariantList worldClockRegions READ worldClockRegions CONSTANT)
    Q_PROPERTY(bool timezoneAuthorizationPending READ timezoneAuthorizationPending NOTIFY timezoneAuthorizationPendingChanged)
    Q_PROPERTY(QString worldClockStatus READ worldClockStatus NOTIFY worldClockStatusChanged)

public:
    bool lockscreenDetailsVisible() const { return m_lockscreenDetailsVisible; }
    Q_INVOKABLE bool setLockscreenDetailsVisible(bool visible);
    bool lockscreenClockVisible() const { return m_lockscreenClockVisible; }
    bool lockscreenWelcomeVisible() const { return m_lockscreenWelcomeVisible; }
    Q_INVOKABLE bool setLockscreenClockVisible(bool visible);
    Q_INVOKABLE bool setLockscreenWelcomeVisible(bool visible);
    QVariantList worldClockRegions() const;
    Q_INVOKABLE QVariantMap worldClockRegion(const QString &zone) const;
    Q_INVOKABLE QVariantMap worldClockDisplay(const QString &zone, const QDateTime &instant) const;
    Q_INVOKABLE QVariantMap solarPosition(const QDateTime &instant) const;
    bool timezoneAuthorizationPending() const { return !m_worldRequestedZone.isEmpty(); }
    QString worldClockStatus() const { return m_worldStatus; }
    Q_INVOKABLE bool requestLockscreenTimezone(const QString &zone);
    Q_INVOKABLE void cancelLockscreenTimezoneRequest();
    // C++-only authority wiring. QML cannot manufacture a verified authentication result.
    void setLockscreenAuthenticationProvider(std::function<QVariantMap()> provider);
    void completeLockscreenTimezoneAuthorization(const QString &verifiedUser);

    explicit ClockSettingsManager(QObject *parent = nullptr);
    ~ClockSettingsManager() override;

    /*
        Preferences.
    */
    bool use24Hour() const;
    QString clockFormat() const;
    QString timezone() const;
    QVariantList availableTimezones() const;
    int timezoneRevision() const;
    QString clockTint() const;

    /*
        Backend state.
    */
    bool available() const;
    bool operationBusy() const;
    QString lastError() const;
    QString lastOperation() const;
    QDateTime currentDateTime() const;

    /*
        Full refresh does not change any setting.
    */
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshTimezones();

    /*
        Generic action entry point for Console.qml.
    */
    Q_INVOKABLE bool executeAction(const QString &action,
                                   const QVariantMap &payload = QVariantMap());

    /*
        Atomic settings application.

        Local preferences are validated before the timezone request begins.
        If the timezone changes asynchronously, local preferences are committed
        only when the D-Bus request succeeds. If timezone is unchanged, the
        local preferences are committed immediately.
    */
    Q_INVOKABLE bool applySettings(const QVariantMap &payload);

    /*
        Direct setters for other NeutronOS surfaces.
    */
    Q_INVOKABLE bool setUse24Hour(bool enabled);
    Q_INVOKABLE bool setClockTint(const QString &color);
    Q_INVOKABLE bool setTimezone(const QString &timezoneId);

    /*
        Timezone-aware preview methods used by ClockSettingsModal.qml.
        Invalid timezone IDs safely fall back to the system timezone.
    */
    Q_INVOKABLE QString formattedTimeForZone(const QString &timezoneId,
                                             bool use24HourFormat) const;

    Q_INVOKABLE QString formattedDateForZone(const QString &timezoneId) const;

    Q_INVOKABLE QString previewTime(const QString &timezoneId,
                                    bool use24HourFormat) const;

    Q_INVOKABLE QString previewDate(const QString &timezoneId) const;

    /*
        Validation helpers are invokable so UI tests can verify proposed
        values without mutating settings.
    */
    Q_INVOKABLE bool isValidTimezone(const QString &timezoneId) const;
    Q_INVOKABLE bool isValidTint(const QString &color) const;

    /*
        Cancels local pending state. A D-Bus request already accepted by
        timedated may still complete at the system level.
    */
    Q_INVOKABLE void cancelPendingOperation();

signals:
    /*
        Aggregate compatibility signal.
    */
    void settingsChanged();
    void lockscreenDetailsVisibleChanged();
    void lockscreenClockVisibleChanged();
    void lockscreenWelcomeVisibleChanged();
    void timezoneAuthorizationPendingChanged();
    void worldClockStatusChanged();

    /*
        Domain-specific properties.
    */
    void use24HourChanged();
    void timezoneChanged();
    void availableTimezonesChanged();
    void timezoneRevisionChanged();
    void clockTintChanged();

    void availabilityChanged();
    void operationBusyChanged();
    void lastErrorChanged();
    void lastOperationChanged();
    void currentDateTimeChanged();

    /*
        Operation lifecycle.
    */
    void operationStarted(const QString &action,
                          const QVariantMap &payload);

    void operationFinished(const QString &action,
                           bool success,
                           const QString &message,
                           const QVariantMap &payload);

private slots:
    void finishWorldTimezone(int exitCode, QProcess::ExitStatus status);
    /*
        D-Bus service lifecycle.
    */
    void onServiceRegistered(const QString &serviceName);
    void onServiceUnregistered(const QString &serviceName);

    /*
        org.freedesktop.DBus.Properties.PropertiesChanged
    */
    void onTimedatePropertiesChanged(const QString &interfaceName,
                                     const QVariantMap &changedProperties,
                                     const QStringList &invalidatedProperties);

    /*
        Asynchronous SetTimezone reply.
    */
    void onSetTimezoneFinished(QDBusPendingCallWatcher *watcher);

    /*
        Current clock preview tick. This timer runs only while the manager
        exists and emits at most once per second.
    */
    void updateCurrentDateTime();

    /*
        Coalesces D-Bus signal bursts.
    */
    void coalescedRefresh();

private:
    bool m_lockscreenDetailsVisible = true;
    bool m_lockscreenClockVisible = true;
    bool m_lockscreenWelcomeVisible = true;
    std::function<QVariantMap()> m_authenticationProvider;
    QString m_worldRequestedZone, m_worldRequestedUser, m_worldApplyingZone, m_worldStatus;
    QTimer m_worldAuthorizationTimer, m_worldProcessTimer;
    QProcess m_worldProcess;
    bool m_worldProcessTimedOut = false;
    void setWorldStatus(const QString &message);
    /*
        Preferences.
    */
    bool m_use24Hour = false;
    QString m_timezone = QStringLiteral("UTC");
    QString m_clockTint = QStringLiteral("#FFFFFF");

    /*
        Available timezone model.
        Each entry contains:
            id
            timezone
            name
            displayName
            region
            city
            utcOffset
            offsetSeconds
    */
    QVariantList m_availableTimezones;
    QSet<QString> m_availableTimezoneIds;
    int m_timezoneRevision = 0;

    /*
        System service and operation state.
    */
    bool m_available = false;
    bool m_operationBusy = false;
    QString m_lastError;
    QString m_lastOperation;

    /*
        Current clock value.
    */
    QDateTime m_currentDateTime;

    /*
        Pending atomic settings transaction.
    */
    QString m_pendingTimezone;
    bool m_pendingUse24Hour = false;
    QString m_pendingClockTint = QStringLiteral("#FFFFFF");
    QVariantMap m_pendingPayload;
    QString m_pendingAction;
    quint64 m_operationSerial = 0;

    /*
        Timers.
    */
    QTimer m_clockTimer;
    QTimer m_refreshCoalesceTimer;

    /*
        D-Bus watcher.
    */
    QDBusServiceWatcher *m_serviceWatcher = nullptr;

    /*
        Service and persistence setup.
    */
    void initializeServiceWatcher();
    void connectTimedateSignals();
    void disconnectTimedateSignals();

    void loadPreferences();
    bool savePreferences() const;
    QString preferencesFilePath() const;

    /*
        Refresh operations.
    */
    void refreshServiceState();
    void readSystemTimezone();
    void rebuildTimezoneModel();
    void incrementTimezoneRevision();

    /*
        Validation and normalization.
    */
    bool validateSettingsPayload(const QVariantMap &payload,
                                 bool *use24HourValue,
                                 QString *timezoneValue,
                                 QString *tintValue,
                                 QString *errorMessage) const;

    bool normalizedUse24Hour(const QVariantMap &payload,
                             bool fallbackValue) const;

    QString normalizedTimezone(const QVariantMap &payload,
                               const QString &fallbackValue) const;

    QString normalizedTint(const QVariantMap &payload,
                           const QString &fallbackValue) const;

    QString normalizedColor(const QString &color) const;
    QString normalizedAction(const QString &action) const;

    /*
        Timezone model helpers.
    */
    QString timezoneDisplayName(const QString &timezoneId) const;
    QString timezoneRegion(const QString &timezoneId) const;
    QString timezoneCity(const QString &timezoneId) const;
    QString utcOffsetText(int offsetSeconds) const;
    QVariantMap timezoneToMap(const QString &timezoneId) const;

    /*
        Time formatting.
    */
    QDateTime dateTimeForZone(const QString &timezoneId) const;
    QString effectiveTimezone(const QString &timezoneId) const;

    /*
        D-Bus operation.
    */
    bool requestTimezoneChange(const QString &timezoneId,
                               const QVariantMap &payload);

    /*
        Transaction commit/rollback.
    */
    void commitLocalSettings(bool use24HourValue,
                             const QString &tintValue);

    void commitTimezone(const QString &timezoneId);
    void clearPendingTransaction();

    /*
        Operation lifecycle.
    */
    void beginOperation(const QString &action,
                        const QVariantMap &payload);

    void finishOperation(const QString &action,
                         bool success,
                         const QString &message,
                         const QVariantMap &payload = QVariantMap());

    void setOperationBusy(bool busy);
    void setLastError(const QString &message);
    void setLastOperation(const QString &message);

    QVariantMap sanitizedPayload(const QVariantMap &payload) const;
};