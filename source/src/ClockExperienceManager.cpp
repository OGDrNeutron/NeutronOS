#include "ClockExperienceManager.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QSaveFile>
#include <QTimeZone>
#include <QTimer>
#include <QtGlobal>

#include <algorithm>

namespace
{
QString neutronRootPath()
{
    const QString environmentRoot =
        QString::fromLocal8Bit(qgetenv("NEUTRONOS_ROOT")).trimmed();

    if (!environmentRoot.isEmpty())
        return QDir::cleanPath(environmentRoot);

    return QDir::cleanPath(QDir::homePath() + QStringLiteral("/NeutronOS"));
}

QString friendlyTimezoneName(QString identifier)
{
    identifier.replace(QLatin1Char('_'), QLatin1Char(' '));
    identifier.replace(QLatin1Char('/'), QStringLiteral(" · "));
    return identifier;
}
}

ClockExperienceManager::ClockExperienceManager(QObject *parent)
    : QObject(parent)
{
    const QByteArray systemZone = QTimeZone::systemTimeZoneId();
    m_timezone = systemZone.isEmpty()
        ? QStringLiteral("UTC")
        : QString::fromUtf8(systemZone);

    loadSettings();
    updateDisplay();
    QTimer::singleShot(1900, this, [this]() { rebuildTimezoneModel(); });

    m_displayTimer.setInterval(1000);
    m_displayTimer.setTimerType(Qt::VeryCoarseTimer);
    m_displayTimer.setSingleShot(false);

    connect(&m_displayTimer,
            &QTimer::timeout,
            this,
            &ClockExperienceManager::updateDisplay);

    m_displayTimer.start();
}

bool ClockExperienceManager::use24Hour() const { return m_use24Hour; }
bool ClockExperienceManager::showSeconds() const { return m_showSeconds; }
bool ClockExperienceManager::showDate() const { return m_showDate; }
bool ClockExperienceManager::showWeekday() const { return m_showWeekday; }
bool ClockExperienceManager::showTimezone() const { return m_showTimezone; }
bool ClockExperienceManager::uppercaseMeridiem() const { return m_uppercaseMeridiem; }
QString ClockExperienceManager::dateFormat() const { return m_dateFormat; }
QString ClockExperienceManager::clockStyle() const { return m_clockStyle; }
QString ClockExperienceManager::timezone() const { return m_timezone; }
QString ClockExperienceManager::clockTint() const { return m_clockTint; }
QString ClockExperienceManager::dateTint() const { return m_dateTint; }
QString ClockExperienceManager::timezoneTint() const { return m_timezoneTint; }
int ClockExperienceManager::clockScale() const { return m_clockScale; }
QString ClockExperienceManager::currentTimeText() const { return m_currentTimeText; }
QString ClockExperienceManager::currentDateText() const { return m_currentDateText; }
QString ClockExperienceManager::timezoneLabel() const { return m_timezoneLabel; }
QVariantList ClockExperienceManager::availableTimezones() const { return m_availableTimezones; }
int ClockExperienceManager::revision() const { return m_revision; }
QString ClockExperienceManager::lastError() const { return m_lastError; }

bool ClockExperienceManager::applySettings(const QVariantMap &payload)
{
    const bool newUse24Hour = payloadBool(
        payload,
        {QStringLiteral("use24Hour"), QStringLiteral("timeFormat24Hour")},
        m_use24Hour);

    const bool newShowSeconds = payloadBool(
        payload,
        {QStringLiteral("showSeconds")},
        m_showSeconds);

    const bool newShowDate = payloadBool(
        payload,
        {QStringLiteral("showDate")},
        m_showDate);

    const bool newShowWeekday = payloadBool(
        payload,
        {QStringLiteral("showWeekday")},
        m_showWeekday);

    const bool newShowTimezone = payloadBool(
        payload,
        {QStringLiteral("showTimezone"), QStringLiteral("showZone")},
        m_showTimezone);

    const bool newUppercaseMeridiem = payloadBool(
        payload,
        {QStringLiteral("uppercaseMeridiem"), QStringLiteral("uppercaseAmPm")},
        m_uppercaseMeridiem);

    const QString newDateFormat = normalizedDateFormat(
        payloadString(payload,
                      {QStringLiteral("dateFormat")},
                      m_dateFormat));

    const QString newClockStyle = normalizedClockStyle(
        payloadString(payload,
                      {QStringLiteral("clockStyle")},
                      m_clockStyle));

    const QString requestedTimezone = payloadString(
        payload,
        {QStringLiteral("timezone"), QStringLiteral("timeZone")},
        m_timezone);

    const QString newTimezone = normalizedTimezone(requestedTimezone);

    if (newTimezone.isEmpty()) {
        setLastError(QStringLiteral("Invalid timezone: %1").arg(requestedTimezone));
        emit operationFinished(QStringLiteral("apply"),
                               false,
                               m_lastError,
                               payload);
        return false;
    }

    const QString newClockTint = normalizedColor(
        payloadString(payload,
                      {QStringLiteral("clockTint"), QStringLiteral("textTint")},
                      m_clockTint),
        m_clockTint);

    const QString newDateTint = normalizedColor(
        payloadString(payload,
                      {QStringLiteral("dateTint"), QStringLiteral("clockDateColor")},
                      m_dateTint),
        m_dateTint);

    const QString newTimezoneTint = normalizedColor(
        payloadString(payload,
                      {QStringLiteral("timezoneTint"), QStringLiteral("zoneTint")},
                      m_timezoneTint),
        m_timezoneTint);

    const int newClockScale = qBound(
        80,
        payloadInt(payload,
                   {QStringLiteral("clockScale"), QStringLiteral("scale")},
                   m_clockScale),
        140);

    m_use24Hour = newUse24Hour;
    m_showSeconds = newShowSeconds;
    m_showDate = newShowDate;
    m_showWeekday = newShowWeekday;
    m_showTimezone = newShowTimezone;
    m_uppercaseMeridiem = newUppercaseMeridiem;
    m_dateFormat = newDateFormat;
    m_clockStyle = newClockStyle;
    m_timezone = newTimezone;
    m_clockTint = newClockTint;
    m_dateTint = newDateTint;
    m_timezoneTint = newTimezoneTint;
    m_clockScale = newClockScale;

    const bool saved = saveSettings();

    if (!saved) {
        setLastError(QStringLiteral("Clock settings changed but could not be persisted"));
        emit settingsChanged();
        updateDisplay();
        emit operationFinished(QStringLiteral("apply"),
                               false,
                               m_lastError,
                               payload);
        return false;
    }

    setLastError(QString());
    bumpRevision();
    emit settingsChanged();
    updateDisplay();

    emit operationFinished(QStringLiteral("apply"),
                           true,
                           QStringLiteral("Clock settings applied immediately"),
                           payload);
    return true;
}

bool ClockExperienceManager::executeAction(const QString &action,
                                           const QVariantMap &payload)
{
    const QString normalized = action.trimmed().toLower();

    if (normalized == QStringLiteral("apply") ||
        normalized == QStringLiteral("save") ||
        normalized == QStringLiteral("applysettings")) {
        return applySettings(payload);
    }

    if (normalized == QStringLiteral("reset") ||
        normalized == QStringLiteral("resetdefaults")) {
        return resetDefaults();
    }

    if (normalized == QStringLiteral("refresh") ||
        normalized == QStringLiteral("reload")) {
        refresh();
        return true;
    }

    return false;
}

bool ClockExperienceManager::resetDefaults()
{
    QVariantMap defaults;
    defaults.insert(QStringLiteral("use24Hour"), false);
    defaults.insert(QStringLiteral("showSeconds"), false);
    defaults.insert(QStringLiteral("showDate"), true);
    defaults.insert(QStringLiteral("showWeekday"), true);
    defaults.insert(QStringLiteral("showTimezone"), false);
    defaults.insert(QStringLiteral("uppercaseMeridiem"), true);
    defaults.insert(QStringLiteral("dateFormat"), QStringLiteral("long"));
    defaults.insert(QStringLiteral("clockStyle"), QStringLiteral("standard"));
    const QByteArray systemZone = QTimeZone::systemTimeZoneId();
    defaults.insert(QStringLiteral("timezone"),
                    systemZone.isEmpty() ? QStringLiteral("UTC")
                                         : QString::fromUtf8(systemZone));
    defaults.insert(QStringLiteral("clockTint"), QStringLiteral("#FFFFFF"));
    defaults.insert(QStringLiteral("dateTint"), QStringLiteral("#9FD8FF"));
    defaults.insert(QStringLiteral("timezoneTint"), QStringLiteral("#7DF9FF"));
    defaults.insert(QStringLiteral("clockScale"), 100);
    return applySettings(defaults);
}

void ClockExperienceManager::refresh()
{
    loadSettings();
    rebuildTimezoneModel();
    bumpRevision();
    emit settingsChanged();
    updateDisplay();
}

void ClockExperienceManager::refreshTimezones()
{
    rebuildTimezoneModel();
}

QString ClockExperienceManager::formatTime(const QDateTime &dateTime) const
{
    QDateTime value = dateTime;
    if (!value.isValid())
        value = currentDateTimeInZone();

    QString pattern;

    if (m_use24Hour) {
        pattern = m_showSeconds
            ? QStringLiteral("HH:mm:ss")
            : QStringLiteral("HH:mm");
    } else {
        pattern = m_showSeconds
            ? QStringLiteral("h:mm:ss AP")
            : QStringLiteral("h:mm AP");
    }

    QString result = QLocale::system().toString(value, pattern);

    if (!m_use24Hour && !m_uppercaseMeridiem) {
        result.replace(QStringLiteral("AM"), QStringLiteral("am"));
        result.replace(QStringLiteral("PM"), QStringLiteral("pm"));
    }

    if (m_clockStyle == QStringLiteral("compact"))
        result.remove(QLatin1Char(' '));

    return result;
}

QString ClockExperienceManager::formatDate(const QDateTime &dateTime) const
{
    if (!m_showDate)
        return QString();

    QDateTime value = dateTime;
    if (!value.isValid())
        value = currentDateTimeInZone();

    QString pattern;

    if (m_dateFormat == QStringLiteral("mdy"))
        pattern = m_showWeekday ? QStringLiteral("ddd · MM/dd/yyyy")
                                : QStringLiteral("MM/dd/yyyy");
    else if (m_dateFormat == QStringLiteral("dmy"))
        pattern = m_showWeekday ? QStringLiteral("ddd · dd/MM/yyyy")
                                : QStringLiteral("dd/MM/yyyy");
    else if (m_dateFormat == QStringLiteral("iso"))
        pattern = m_showWeekday ? QStringLiteral("ddd · yyyy-MM-dd")
                                : QStringLiteral("yyyy-MM-dd");
    else if (m_dateFormat == QStringLiteral("medium"))
        pattern = m_showWeekday ? QStringLiteral("ddd, MMM d, yyyy")
                                : QStringLiteral("MMM d, yyyy");
    else
        pattern = m_showWeekday ? QStringLiteral("dddd, MMMM d")
                                : QStringLiteral("MMMM d");

    return QLocale::system().toString(value.date(), pattern);
}

QString ClockExperienceManager::formatCurrentTime() const
{
    return formatTime(currentDateTimeInZone());
}

QString ClockExperienceManager::formatCurrentDate() const
{
    return formatDate(currentDateTimeInZone());
}

bool ClockExperienceManager::isValidTimezone(const QString &timezoneId) const
{
    const QByteArray id = timezoneId.trimmed().toUtf8();
    return !id.isEmpty() && QTimeZone(id).isValid();
}

bool ClockExperienceManager::isValidColor(const QString &color) const
{
    return QColor(color.trimmed()).isValid();
}

void ClockExperienceManager::updateDisplay()
{
    const QDateTime now = currentDateTimeInZone();
    const QString newTime = formatTime(now);
    const QString newDate = formatDate(now);
    const QString newZone = m_showTimezone
        ? QTimeZone(m_timezone.toUtf8()).abbreviation(now)
        : QString();

    if (newTime == m_currentTimeText &&
        newDate == m_currentDateText &&
        newZone == m_timezoneLabel) {
        return;
    }

    m_currentTimeText = newTime;
    m_currentDateText = newDate;
    m_timezoneLabel = newZone;
    emit displayChanged();
}

QString ClockExperienceManager::settingsFilePath() const
{
    return neutronRootPath() + QStringLiteral("/state/settings/clock-experience.json");
}

void ClockExperienceManager::loadSettings()
{
    QFile file(settingsFilePath());

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    file.close();

    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        setLastError(QStringLiteral("Clock preference file is invalid"));
        return;
    }

    const QJsonObject object = document.object();
    QVariantMap payload = object.toVariantMap();

    const QString previousError = m_lastError;
    applySettings(payload);

    if (!previousError.isEmpty() && m_lastError.isEmpty())
        setLastError(previousError);
}

bool ClockExperienceManager::saveSettings()
{
    const QString path = settingsFilePath();
    const QFileInfo info(path);

    if (!QDir().mkpath(info.absolutePath()))
        return false;

    QJsonObject object;
    object.insert(QStringLiteral("version"), 2);
    object.insert(QStringLiteral("use24Hour"), m_use24Hour);
    object.insert(QStringLiteral("showSeconds"), m_showSeconds);
    object.insert(QStringLiteral("showDate"), m_showDate);
    object.insert(QStringLiteral("showWeekday"), m_showWeekday);
    object.insert(QStringLiteral("showTimezone"), m_showTimezone);
    object.insert(QStringLiteral("uppercaseMeridiem"), m_uppercaseMeridiem);
    object.insert(QStringLiteral("dateFormat"), m_dateFormat);
    object.insert(QStringLiteral("clockStyle"), m_clockStyle);
    object.insert(QStringLiteral("timezone"), m_timezone);
    object.insert(QStringLiteral("clockTint"), m_clockTint);
    object.insert(QStringLiteral("dateTint"), m_dateTint);
    object.insert(QStringLiteral("timezoneTint"), m_timezoneTint);
    object.insert(QStringLiteral("clockScale"), m_clockScale);
    object.insert(QStringLiteral("updatedAt"),
                  QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));

    QSaveFile file(path);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    const QJsonDocument document(object);

    if (file.write(document.toJson(QJsonDocument::Indented)) < 0) {
        file.cancelWriting();
        return false;
    }

    if (!file.commit())
        return false;

    QFile::setPermissions(path,
                          QFileDevice::ReadOwner |
                          QFileDevice::WriteOwner);
    return true;
}

void ClockExperienceManager::rebuildTimezoneModel()
{
    QVariantList result;
    const QList<QByteArray> ids = QTimeZone::availableTimeZoneIds();
    result.reserve(ids.size());

    for (const QByteArray &id : ids) {
        const QTimeZone zone(id);
        if (!zone.isValid())
            continue;

        const QDateTime now = QDateTime::currentDateTimeUtc();
        QVariantMap item;
        item.insert(QStringLiteral("id"), QString::fromUtf8(id));
        item.insert(QStringLiteral("timezone"), QString::fromUtf8(id));
        item.insert(QStringLiteral("displayName"), friendlyTimezoneName(QString::fromUtf8(id)));
        item.insert(QStringLiteral("abbreviation"), zone.abbreviation(now));
        item.insert(QStringLiteral("offsetSeconds"), zone.offsetFromUtc(now));
        result.append(item);
    }

    std::sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap left = a.toMap();
        const QVariantMap right = b.toMap();
        const int leftOffset = left.value(QStringLiteral("offsetSeconds")).toInt();
        const int rightOffset = right.value(QStringLiteral("offsetSeconds")).toInt();

        if (leftOffset != rightOffset)
            return leftOffset < rightOffset;

        return left.value(QStringLiteral("id")).toString() <
               right.value(QStringLiteral("id")).toString();
    });

    m_availableTimezones = result;
    emit availableTimezonesChanged();
}

void ClockExperienceManager::setLastError(const QString &message)
{
    if (m_lastError == message)
        return;

    m_lastError = message;
    emit lastErrorChanged();
}

void ClockExperienceManager::bumpRevision()
{
    ++m_revision;
    emit revisionChanged();
}

QDateTime ClockExperienceManager::currentDateTimeInZone() const
{
    const QTimeZone zone(m_timezone.toUtf8());

    if (!zone.isValid())
        return QDateTime::currentDateTime();

    return QDateTime::currentDateTimeUtc().toTimeZone(zone);
}

QString ClockExperienceManager::normalizedColor(const QString &value,
                                                const QString &fallback) const
{
    QColor color(value.trimmed());
    if (!color.isValid())
        return fallback.toUpper();

    return color.name(QColor::HexRgb).toUpper();
}

QString ClockExperienceManager::normalizedDateFormat(const QString &value) const
{
    const QString normalized = value.trimmed().toLower();
    const QStringList allowed = {
        QStringLiteral("long"),
        QStringLiteral("medium"),
        QStringLiteral("mdy"),
        QStringLiteral("dmy"),
        QStringLiteral("iso")
    };

    return allowed.contains(normalized) ? normalized : QStringLiteral("long");
}

QString ClockExperienceManager::normalizedClockStyle(const QString &value) const
{
    const QString normalized = value.trimmed().toLower();
    const QStringList allowed = {
        QStringLiteral("standard"),
        QStringLiteral("compact"),
        QStringLiteral("wide")
    };

    return allowed.contains(normalized) ? normalized : QStringLiteral("standard");
}

QString ClockExperienceManager::normalizedTimezone(const QString &value) const
{
    QString normalized = value.trimmed();

    if (normalized == QStringLiteral("Etc/UTC") ||
        normalized == QStringLiteral("GMT")) {
        normalized = QStringLiteral("UTC");
    }

    return isValidTimezone(normalized) ? normalized : QString();
}

bool ClockExperienceManager::payloadBool(const QVariantMap &payload,
                                         const QStringList &keys,
                                         bool fallback) const
{
    for (const QString &key : keys) {
        if (!payload.contains(key))
            continue;

        const QVariant value = payload.value(key);
        if (value.metaType().id() == QMetaType::Bool)
            return value.toBool();

        const QString text = value.toString().trimmed().toLower();
        if (text == QStringLiteral("true") || text == QStringLiteral("1") ||
            text == QStringLiteral("yes") || text == QStringLiteral("on"))
            return true;
        if (text == QStringLiteral("false") || text == QStringLiteral("0") ||
            text == QStringLiteral("no") || text == QStringLiteral("off"))
            return false;
    }

    return fallback;
}

QString ClockExperienceManager::payloadString(const QVariantMap &payload,
                                              const QStringList &keys,
                                              const QString &fallback) const
{
    for (const QString &key : keys) {
        if (!payload.contains(key))
            continue;

        const QString value = payload.value(key).toString().trimmed();
        if (!value.isEmpty())
            return value;
    }

    return fallback;
}

int ClockExperienceManager::payloadInt(const QVariantMap &payload,
                                       const QStringList &keys,
                                       int fallback) const
{
    for (const QString &key : keys) {
        if (!payload.contains(key))
            continue;

        bool ok = false;
        const int value = payload.value(key).toInt(&ok);
        if (ok)
            return value;
    }

    return fallback;
}
