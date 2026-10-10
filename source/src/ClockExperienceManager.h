#pragma once

#include <QObject>
#include <QString>
#include <QDateTime>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>

class ClockExperienceManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool use24Hour READ use24Hour NOTIFY settingsChanged)
    Q_PROPERTY(bool showSeconds READ showSeconds NOTIFY settingsChanged)
    Q_PROPERTY(bool showDate READ showDate NOTIFY settingsChanged)
    Q_PROPERTY(bool showWeekday READ showWeekday NOTIFY settingsChanged)
    Q_PROPERTY(bool showTimezone READ showTimezone NOTIFY settingsChanged)
    Q_PROPERTY(bool uppercaseMeridiem READ uppercaseMeridiem NOTIFY settingsChanged)
    Q_PROPERTY(QString dateFormat READ dateFormat NOTIFY settingsChanged)
    Q_PROPERTY(QString clockStyle READ clockStyle NOTIFY settingsChanged)
    Q_PROPERTY(QString timezone READ timezone NOTIFY settingsChanged)
    Q_PROPERTY(QString clockTint READ clockTint NOTIFY settingsChanged)
    Q_PROPERTY(QString dateTint READ dateTint NOTIFY settingsChanged)
    Q_PROPERTY(QString timezoneTint READ timezoneTint NOTIFY settingsChanged)
    Q_PROPERTY(int clockScale READ clockScale NOTIFY settingsChanged)
    Q_PROPERTY(QString currentTimeText READ currentTimeText NOTIFY displayChanged)
    Q_PROPERTY(QString currentDateText READ currentDateText NOTIFY displayChanged)
    Q_PROPERTY(QString timezoneLabel READ timezoneLabel NOTIFY displayChanged)
    Q_PROPERTY(QVariantList availableTimezones READ availableTimezones NOTIFY availableTimezonesChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit ClockExperienceManager(QObject *parent = nullptr);

    bool use24Hour() const;
    bool showSeconds() const;
    bool showDate() const;
    bool showWeekday() const;
    bool showTimezone() const;
    bool uppercaseMeridiem() const;
    QString dateFormat() const;
    QString clockStyle() const;
    QString timezone() const;
    QString clockTint() const;
    QString dateTint() const;
    QString timezoneTint() const;
    int clockScale() const;
    QString currentTimeText() const;
    QString currentDateText() const;
    QString timezoneLabel() const;
    QVariantList availableTimezones() const;
    int revision() const;
    QString lastError() const;

    Q_INVOKABLE bool applySettings(const QVariantMap &payload);
    Q_INVOKABLE bool executeAction(const QString &action,
                                   const QVariantMap &payload = QVariantMap());
    Q_INVOKABLE bool resetDefaults();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshTimezones();
    Q_INVOKABLE QString formatTime(const QDateTime &dateTime) const;
    Q_INVOKABLE QString formatDate(const QDateTime &dateTime) const;
    Q_INVOKABLE QString formatCurrentTime() const;
    Q_INVOKABLE QString formatCurrentDate() const;
    Q_INVOKABLE bool isValidTimezone(const QString &timezoneId) const;
    Q_INVOKABLE bool isValidColor(const QString &color) const;

signals:
    void settingsChanged();
    void displayChanged();
    void availableTimezonesChanged();
    void revisionChanged();
    void lastErrorChanged();
    void operationFinished(const QString &action,
                           bool success,
                           const QString &message,
                           const QVariantMap &payload);

private slots:
    void updateDisplay();

private:
    bool m_use24Hour = false;
    bool m_showSeconds = false;
    bool m_showDate = true;
    bool m_showWeekday = true;
    bool m_showTimezone = false;
    bool m_uppercaseMeridiem = true;
    QString m_dateFormat = QStringLiteral("long");
    QString m_clockStyle = QStringLiteral("standard");
    QString m_timezone;
    QString m_clockTint = QStringLiteral("#FFFFFF");
    QString m_dateTint = QStringLiteral("#9FD8FF");
    QString m_timezoneTint = QStringLiteral("#7DF9FF");
    int m_clockScale = 100;

    QString m_currentTimeText;
    QString m_currentDateText;
    QString m_timezoneLabel;
    QVariantList m_availableTimezones;
    int m_revision = 0;
    QString m_lastError;
    QTimer m_displayTimer;

    QString settingsFilePath() const;
    void loadSettings();
    bool saveSettings();
    void rebuildTimezoneModel();
    void setLastError(const QString &message);
    void bumpRevision();
    QDateTime currentDateTimeInZone() const;
    QString normalizedColor(const QString &value,
                            const QString &fallback) const;
    QString normalizedDateFormat(const QString &value) const;
    QString normalizedClockStyle(const QString &value) const;
    QString normalizedTimezone(const QString &value) const;
    bool payloadBool(const QVariantMap &payload,
                     const QStringList &keys,
                     bool fallback) const;
    QString payloadString(const QVariantMap &payload,
                          const QStringList &keys,
                          const QString &fallback) const;
    int payloadInt(const QVariantMap &payload,
                   const QStringList &keys,
                   int fallback) const;
};
