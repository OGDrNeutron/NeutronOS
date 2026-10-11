#include "ClockSettingsManager.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QRegularExpression>
#include <QProcess>
#include <QSaveFile>
#include <QTimeZone>
#include <QTimer>
#include <QUuid>
#include <QVariant>
#include <QtGlobal>

#include <algorithm>
#include <cmath>
#include <QPointF>
#include <QHash>
#include <QTextStream>
#ifdef Q_OS_UNIX
#include <unistd.h>
#endif

namespace
{
const QString TimedateService =
    QStringLiteral(
        "org.freedesktop.timedate1"
    );

const QString TimedatePath =
    QStringLiteral(
        "/org/freedesktop/timedate1"
    );

const QString TimedateInterface =
    QStringLiteral(
        "org.freedesktop.timedate1"
    );

const QString PropertiesInterface =
    QStringLiteral(
        "org.freedesktop.DBus.Properties"
    );

constexpr int ClockRefreshIntervalMs = 1000;
constexpr int RefreshCoalesceDelayMs = 120;
constexpr int DbusOperationTimeoutMs = 30000;

QString neutronOsRootPath()
{
    const QString environmentRoot =
        QString::fromLocal8Bit(
            qgetenv("NEUTRONOS_ROOT")
        ).trimmed();

    if (!environmentRoot.isEmpty())
        return QDir::cleanPath(environmentRoot);

    return QDir::cleanPath(
        QDir::homePath() +
        QStringLiteral("/NeutronOS")
    );
}

QString payloadString(
    const QVariantMap &payload,
    const QStringList &keys)
{
    for (const QString &key : keys) {
        if (!payload.contains(key))
            continue;

        const QString value =
            payload.value(key)
                .toString()
                .trimmed();

        if (!value.isEmpty())
            return value;
    }

    return QString();
}

bool payloadContainsAny(
    const QVariantMap &payload,
    const QStringList &keys)
{
    for (const QString &key : keys) {
        if (payload.contains(key))
            return true;
    }

    return false;
}

QString systemTimezoneId()
{
    const QByteArray identifier =
        QTimeZone::systemTimeZoneId();

    if (!identifier.isEmpty())
        return QString::fromUtf8(identifier);

    return QStringLiteral("UTC");
}

QString cleanedTimezoneId(
    const QString &value)
{
    QString result =
        value.trimmed();

    if (result.compare(
            QStringLiteral("Etc/UTC"),
            Qt::CaseInsensitive) == 0 ||
            result.compare(
                QStringLiteral("Etc/GMT"),
                Qt::CaseInsensitive) == 0 ||
            result.compare(
                QStringLiteral("GMT"),
                Qt::CaseInsensitive) == 0) {
        return QStringLiteral("UTC");
    }

    return result;
}

QString friendlyTimezonePart(
    QString value)
{
    value.replace(
        QStringLiteral("_"),
        QStringLiteral(" ")
    );

    return value.trimmed();
}

bool isTruthyText(
    const QVariant &value,
    bool fallback)
{
    if (!value.isValid() ||
            value.isNull()) {
        return fallback;
    }

    if (value.type() ==
            QVariant::Bool) {
        return value.toBool();
    }

    const QString text =
        value.toString()
            .trimmed()
            .toLower();

    if (text == QStringLiteral("true") ||
            text == QStringLiteral("1") ||
            text == QStringLiteral("yes") ||
            text == QStringLiteral("on") ||
            text == QStringLiteral("24") ||
            text == QStringLiteral("24h") ||
            text == QStringLiteral("24-hour")) {
        return true;
    }

    if (text == QStringLiteral("false") ||
            text == QStringLiteral("0") ||
            text == QStringLiteral("no") ||
            text == QStringLiteral("off") ||
            text == QStringLiteral("12") ||
            text == QStringLiteral("12h") ||
            text == QStringLiteral("12-hour")) {
        return false;
    }

    return fallback;
}
}

/*
    ========================================================================
                              CONSTRUCTION
    ========================================================================
*/

ClockSettingsManager::ClockSettingsManager(
    QObject *parent)
    : QObject(parent)
{
    m_clockTimer.setInterval(
        ClockRefreshIntervalMs
    );

    m_clockTimer.setSingleShot(false);

    m_refreshCoalesceTimer.setInterval(
        RefreshCoalesceDelayMs
    );

    m_refreshCoalesceTimer.setSingleShot(true);

    connect(
        &m_clockTimer,
        &QTimer::timeout,
        this,
        &ClockSettingsManager::updateCurrentDateTime
    );

    connect(
        &m_refreshCoalesceTimer,
        &QTimer::timeout,
        this,
        &ClockSettingsManager::coalescedRefresh
    );

    m_worldAuthorizationTimer.setSingleShot(true);
    m_worldAuthorizationTimer.setInterval(60000);
    connect(&m_worldAuthorizationTimer, &QTimer::timeout, this, [this]() {
        cancelLockscreenTimezoneRequest();
        setWorldStatus(QStringLiteral("Timezone authorization expired; local timezone unchanged"));
    });
    m_worldProcessTimer.setSingleShot(true);
    m_worldProcessTimer.setInterval(15000);
    connect(&m_worldProcessTimer, &QTimer::timeout, this, [this]() {
        m_worldProcessTimedOut = true;
        m_worldProcess.kill();
    });
    connect(&m_worldProcess, qOverload<int,QProcess::ExitStatus>(&QProcess::finished),
            this, &ClockSettingsManager::finishWorldTimezone);
    connect(&m_worldProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) finishWorldTimezone(-1, QProcess::CrashExit);
    });
    loadPreferences();
    rebuildTimezoneModel();
    readSystemTimezone();
    updateCurrentDateTime();

    QTimer::singleShot(1800, this, [this]() {
        rebuildTimezoneModel();
        initializeServiceWatcher();
        refreshServiceState();
    });

    m_clockTimer.start();
}

ClockSettingsManager::~ClockSettingsManager()
{
    disconnectTimedateSignals();
}

/*
    ========================================================================
                                  GETTERS
    ========================================================================
*/

bool ClockSettingsManager::use24Hour() const
{
    return m_use24Hour;
}

QString ClockSettingsManager::clockFormat() const
{
    return m_use24Hour
           ? QStringLiteral("24")
           : QStringLiteral("12");
}

QString ClockSettingsManager::timezone() const
{
    return m_timezone;
}

QVariantList ClockSettingsManager::availableTimezones() const
{
    return m_availableTimezones;
}

int ClockSettingsManager::timezoneRevision() const
{
    return m_timezoneRevision;
}

QString ClockSettingsManager::clockTint() const
{
    return m_clockTint;
}

bool ClockSettingsManager::available() const
{
    return m_available;
}

bool ClockSettingsManager::operationBusy() const
{
    return m_operationBusy;
}

QString ClockSettingsManager::lastError() const
{
    return m_lastError;
}

QString ClockSettingsManager::lastOperation() const
{
    return m_lastOperation;
}

QDateTime ClockSettingsManager::currentDateTime() const
{
    return m_currentDateTime;
}

/*
    ========================================================================
                            PUBLIC REFRESH API
    ========================================================================
*/

void ClockSettingsManager::refresh()
{
    coalescedRefresh();
}

void ClockSettingsManager::refreshTimezones()
{
    rebuildTimezoneModel();
    readSystemTimezone();
    updateCurrentDateTime();
}

/*
    ========================================================================
                              ACTION ROUTER
    ========================================================================
*/

bool ClockSettingsManager::executeAction(
    const QString &action,
    const QVariantMap &payload)
{
    const QString normalized =
        normalizedAction(action);

    if (normalized ==
            QStringLiteral("apply") ||
            normalized ==
            QStringLiteral("applysettings") ||
            normalized ==
            QStringLiteral("save")) {
        return applySettings(payload);
    }

    if (normalized ==
            QStringLiteral("refresh") ||
            normalized ==
            QStringLiteral("refreshsettings")) {
        if (m_operationBusy)
            return false;

        beginOperation(
            QStringLiteral("refresh"),
            payload
        );

        coalescedRefresh();

        finishOperation(
            QStringLiteral("refresh"),
            true,
            QStringLiteral(
                "Clock settings refreshed"
            ),
            payload
        );

        return true;
    }

    if (normalized ==
            QStringLiteral("refreshtimezones")) {
        if (m_operationBusy)
            return false;

        beginOperation(
            QStringLiteral(
                "refreshTimezones"
            ),
            payload
        );

        refreshTimezones();

        finishOperation(
            QStringLiteral(
                "refreshTimezones"
            ),
            true,
            QStringLiteral(
                "Timezone list refreshed"
            ),
            payload
        );

        return true;
    }

    if (normalized ==
            QStringLiteral("settimezone")) {
        return setTimezone(
            normalizedTimezone(
                payload,
                m_timezone
            )
        );
    }

    if (normalized ==
            QStringLiteral("setuse24hour") ||
            normalized ==
            QStringLiteral("settimeformat")) {
        return setUse24Hour(
            normalizedUse24Hour(
                payload,
                m_use24Hour
            )
        );
    }

    if (normalized ==
            QStringLiteral("setclocktint") ||
            normalized ==
            QStringLiteral("settint")) {
        return setClockTint(
            normalizedTint(
                payload,
                m_clockTint
            )
        );
    }

    if (normalized ==
            QStringLiteral("cancel")) {
        cancelPendingOperation();
        return true;
    }

    setLastError(
        QStringLiteral(
            "Unsupported clock action: %1"
        ).arg(action)
    );

    return false;
}

/*
    ========================================================================
                          SETTINGS APPLICATION
    ========================================================================
*/

bool ClockSettingsManager::applySettings(
    const QVariantMap &payload)
{
    if (m_operationBusy)
        return false;

    bool requestedUse24Hour = m_use24Hour;
    QString requestedTimezone = m_timezone;
    QString requestedTint = m_clockTint;
    QString errorMessage;

    if (!validateSettingsPayload(
            payload,
            &requestedUse24Hour,
            &requestedTimezone,
            &requestedTint,
            &errorMessage)) {
        setLastError(errorMessage);
        return false;
    }

    const QVariantMap safePayload =
        sanitizedPayload(payload);

    if (requestedTimezone ==
            m_timezone) {
        beginOperation(
            QStringLiteral("apply"),
            safePayload
        );

        commitLocalSettings(
            requestedUse24Hour,
            requestedTint
        );

        const bool saved =
            savePreferences();

        finishOperation(
            QStringLiteral("apply"),
            saved,
            saved
            ? QStringLiteral(
                  "Clock settings applied"
              )
            : QStringLiteral(
                  "Clock settings changed but could not be persisted"
              ),
            safePayload
        );

        return saved;
    }

    m_pendingTimezone =
        requestedTimezone;

    m_pendingUse24Hour =
        requestedUse24Hour;

    m_pendingClockTint =
        requestedTint;

    return requestTimezoneChange(
        requestedTimezone,
        safePayload
    );
}

bool ClockSettingsManager::setUse24Hour(
    bool enabled)
{
    QVariantMap payload;

    payload[
        QStringLiteral("use24Hour")
    ] = enabled;

    payload[
        QStringLiteral("format")
    ] = enabled
        ? QStringLiteral("24")
        : QStringLiteral("12");

    payload[
        QStringLiteral("timezone")
    ] = m_timezone;

    payload[
        QStringLiteral("clockTint")
    ] = m_clockTint;

    return applySettings(payload);
}

bool ClockSettingsManager::setClockTint(
    const QString &color)
{
    QVariantMap payload;

    payload[
        QStringLiteral("use24Hour")
    ] = m_use24Hour;

    payload[
        QStringLiteral("timezone")
    ] = m_timezone;

    payload[
        QStringLiteral("clockTint")
    ] = color;

    return applySettings(payload);
}

bool ClockSettingsManager::setTimezone(
    const QString &timezoneId)
{
    QVariantMap payload;

    payload[
        QStringLiteral("use24Hour")
    ] = m_use24Hour;

    payload[
        QStringLiteral("timezone")
    ] = timezoneId;

    payload[
        QStringLiteral("clockTint")
    ] = m_clockTint;

    return applySettings(payload);
}

/*
    ========================================================================
                              TIME PREVIEWS
    ========================================================================
*/

QString ClockSettingsManager::formattedTimeForZone(
    const QString &timezoneId,
    bool use24HourFormat) const
{
    const QDateTime dateTime =
        dateTimeForZone(timezoneId);

    if (!dateTime.isValid())
        return QStringLiteral("--:--");

    return QLocale::system().toString(
        dateTime.time(),
        use24HourFormat
        ? QStringLiteral("HH:mm")
        : QStringLiteral("h:mm AP")
    );
}

QString ClockSettingsManager::formattedDateForZone(
    const QString &timezoneId) const
{
    const QDateTime dateTime =
        dateTimeForZone(timezoneId);

    if (!dateTime.isValid())
        return QStringLiteral("--");

    return QLocale::system().toString(
        dateTime.date(),
        QStringLiteral(
            "dddd, MMMM d"
        )
    );
}

QString ClockSettingsManager::previewTime(
    const QString &timezoneId,
    bool use24HourFormat) const
{
    return formattedTimeForZone(
        timezoneId,
        use24HourFormat
    );
}

QString ClockSettingsManager::previewDate(
    const QString &timezoneId) const
{
    return formattedDateForZone(
        timezoneId
    );
}

bool ClockSettingsManager::isValidTimezone(
    const QString &timezoneId) const
{
    const QString normalized =
        cleanedTimezoneId(
            timezoneId
        );

    if (normalized.isEmpty())
        return false;

    if (normalized ==
            QStringLiteral("UTC")) {
        return true;
    }

    const QTimeZone zone(
        normalized.toUtf8()
    );

    return zone.isValid();
}

bool ClockSettingsManager::isValidTint(
    const QString &color) const
{
    return !normalizedColor(color)
        .isEmpty();
}

/*
    ========================================================================
                          CANCELLATION
    ========================================================================
*/

void ClockSettingsManager::cancelPendingOperation()
{
    ++m_operationSerial;

    const QString action =
        m_pendingAction;

    const QVariantMap payload =
        m_pendingPayload;

    clearPendingTransaction();
    setOperationBusy(false);

    setLastOperation(
        QStringLiteral(
            "Clock operation cancelled locally"
        )
    );

    if (!action.isEmpty()) {
        emit operationFinished(
            action,
            false,
            QStringLiteral(
                "Operation cancelled locally"
            ),
            payload
        );
    }
}

/*
    ========================================================================
                         SERVICE LIFECYCLE
    ========================================================================
*/

void ClockSettingsManager::initializeServiceWatcher()
{
    if (m_serviceWatcher)
        return;

    m_serviceWatcher =
        new QDBusServiceWatcher(
            TimedateService,
            QDBusConnection::systemBus(),
            QDBusServiceWatcher::WatchForRegistration |
            QDBusServiceWatcher::WatchForUnregistration,
            this
        );

    connect(
        m_serviceWatcher,
        &QDBusServiceWatcher::serviceRegistered,
        this,
        &ClockSettingsManager::onServiceRegistered
    );

    connect(
        m_serviceWatcher,
        &QDBusServiceWatcher::serviceUnregistered,
        this,
        &ClockSettingsManager::onServiceUnregistered
    );
}

void ClockSettingsManager::connectTimedateSignals()
{
    disconnectTimedateSignals();

    QDBusConnection::systemBus()
        .connect(
            TimedateService,
            TimedatePath,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onTimedatePropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );
}

void ClockSettingsManager::disconnectTimedateSignals()
{
    QDBusConnection::systemBus()
        .disconnect(
            TimedateService,
            TimedatePath,
            PropertiesInterface,
            QStringLiteral(
                "PropertiesChanged"
            ),
            this,
            SLOT(
                onTimedatePropertiesChanged(
                    QString,
                    QVariantMap,
                    QStringList
                )
            )
        );
}

void ClockSettingsManager::onServiceRegistered(
    const QString &serviceName)
{
    if (serviceName != TimedateService)
        return;

    const bool changed =
        !m_available;

    m_available = true;
    connectTimedateSignals();

    if (changed)
        emit availabilityChanged();

    m_refreshCoalesceTimer.start(0);
}

void ClockSettingsManager::onServiceUnregistered(
    const QString &serviceName)
{
    if (serviceName != TimedateService)
        return;

    disconnectTimedateSignals();

    const bool changed =
        m_available;

    m_available = false;

    if (changed)
        emit availabilityChanged();

    if (m_operationBusy) {
        const QString interruptedAction =
            m_pendingAction.isEmpty()
            ? QStringLiteral("apply")
            : m_pendingAction;

        const QVariantMap interruptedPayload =
            m_pendingPayload;

        ++m_operationSerial;

        finishOperation(
            interruptedAction,
            false,
            QStringLiteral(
                "System timezone service became unavailable"
            ),
            interruptedPayload
        );
    }

    /*
        QTimeZone reads the operating system's current zone independently of
        timedated. Retain a usable clock even while the service is restarting.
    */
    const QString fallback =
        systemTimezoneId();

    if (fallback != m_timezone &&
            isValidTimezone(fallback)) {
        m_timezone = fallback;
        emit timezoneChanged();
        emit settingsChanged();
    }

    updateCurrentDateTime();
}

void ClockSettingsManager::onTimedatePropertiesChanged(
    const QString &interfaceName,
    const QVariantMap &changedProperties,
    const QStringList &invalidatedProperties)
{
    Q_UNUSED(invalidatedProperties)

    if (interfaceName !=
            TimedateInterface) {
        return;
    }

    if (changedProperties.contains(
            QStringLiteral("Timezone"))) {
        const QString changedTimezone =
            cleanedTimezoneId(
                changedProperties.value(
                    QStringLiteral("Timezone")
                ).toString()
            );

        if (isValidTimezone(
                changedTimezone) &&
                changedTimezone !=
                m_timezone) {
            m_timezone = changedTimezone;
            savePreferences();

            emit timezoneChanged();
            emit settingsChanged();
            updateCurrentDateTime();
        }
    }

    m_refreshCoalesceTimer.start(
        RefreshCoalesceDelayMs
    );
}

/*
    ========================================================================
                            PERSISTENCE
    ========================================================================
*/

QString ClockSettingsManager::preferencesFilePath() const
{
    return neutronOsRootPath() +
           QStringLiteral(
               "/state/settings/clock.json"
           );
}

void ClockSettingsManager::loadPreferences()
{
    const QString path =
        preferencesFilePath();

    QFile file(path);

    if (!file.open(
            QIODevice::ReadOnly |
            QIODevice::Text)) {
        m_timezone =
            systemTimezoneId();

        if (!isValidTimezone(
                m_timezone)) {
            m_timezone =
                QStringLiteral("UTC");
        }

        return;
    }

    QJsonParseError error;

    const QJsonDocument document =
        QJsonDocument::fromJson(
            file.readAll(),
            &error
        );

    file.close();

    if (error.error !=
            QJsonParseError::NoError ||
            !document.isObject()) {
        m_timezone =
            systemTimezoneId();

        if (!isValidTimezone(
                m_timezone)) {
            m_timezone =
                QStringLiteral("UTC");
        }

        return;
    }

    const QJsonObject object =
        document.object();

    const QFileInfo preferenceInfo(path);
    bool trustedOwner = !preferenceInfo.isSymLink() &&
        !(preferenceInfo.permissions() & (QFileDevice::WriteGroup|QFileDevice::WriteOther));
#ifdef Q_OS_UNIX
    trustedOwner = trustedOwner && (preferenceInfo.ownerId()==static_cast<uint>(geteuid()) || preferenceInfo.ownerId()==0);
#endif
    m_lockscreenDetailsVisible = trustedOwner?object.value(QStringLiteral("lockscreenDetailsVisible")).toBool(true):true;
    m_lockscreenClockVisible = trustedOwner?object.value(QStringLiteral("lockscreenClockVisible")).toBool(true):true;
    m_lockscreenWelcomeVisible = trustedOwner?object.value(QStringLiteral("lockscreenWelcomeVisible")).toBool(true):true;
    m_use24Hour =
        object.value(
            QStringLiteral("use24Hour")
        ).toBool(false);

    const QString tint =
        normalizedColor(
            object.value(
                QStringLiteral("clockTint")
            ).toString()
        );

    if (!tint.isEmpty())
        m_clockTint = tint;

    const QString savedTimezone =
        cleanedTimezoneId(
            object.value(
                QStringLiteral("timezone")
            ).toString()
        );

    if (isValidTimezone(
            savedTimezone)) {
        m_timezone = savedTimezone;
    } else {
        m_timezone =
            systemTimezoneId();

        if (!isValidTimezone(
                m_timezone)) {
            m_timezone =
                QStringLiteral("UTC");
        }
    }
}

bool ClockSettingsManager::savePreferences() const
{
    const QString path =
        preferencesFilePath();

    const QFileInfo info(path);

    if (!QDir().mkpath(
            info.absolutePath())) {
        return false;
    }

    QJsonObject object;

    object.insert(
        QStringLiteral("version"),
        1
    );

    object.insert(
        QStringLiteral("use24Hour"),
        m_use24Hour
    );

    object.insert(
        QStringLiteral("clockTint"),
        m_clockTint
    );

    object.insert(
        QStringLiteral("timezone"),
        m_timezone
    );

    object.insert(
        QStringLiteral("updatedAt"),
        QDateTime::currentDateTimeUtc()
            .toString(Qt::ISODateWithMs)
    );

    object.insert(QStringLiteral("lockscreenDetailsVisible"), m_lockscreenDetailsVisible);
    object.insert(QStringLiteral("lockscreenClockVisible"), m_lockscreenClockVisible);
    object.insert(QStringLiteral("lockscreenWelcomeVisible"), m_lockscreenWelcomeVisible);
    QSaveFile file(path);

    if (!file.open(
            QIODevice::WriteOnly |
            QIODevice::Text)) {
        return false;
    }

    if (!file.setPermissions(QFileDevice::ReadOwner|QFileDevice::WriteOwner)) {
        file.cancelWriting();
        return false;
    }
    const QJsonDocument document(object);

    if (file.write(
            document.toJson(
                QJsonDocument::Indented
            )) < 0) {
        file.cancelWriting();
        return false;
    }

    if (!file.commit())
        return false;

    QFile::setPermissions(
        path,
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner
    );

    return true;
}

/*
    ========================================================================
                           REFRESH OPERATIONS
    ========================================================================
*/

void ClockSettingsManager::refreshServiceState()
{
    QDBusConnectionInterface *interface =
        QDBusConnection::systemBus()
            .interface();

    bool serviceAvailable = false;

    if (interface) {
        const QDBusReply<bool> reply =
            interface->isServiceRegistered(
                TimedateService
            );

        serviceAvailable =
            reply.isValid() &&
            reply.value();
    }

    if (m_available ==
            serviceAvailable) {
        if (m_available)
            connectTimedateSignals();

        return;
    }

    m_available = serviceAvailable;

    if (m_available)
        connectTimedateSignals();
    else
        disconnectTimedateSignals();

    emit availabilityChanged();
}

void ClockSettingsManager::readSystemTimezone()
{
    QString detectedTimezone;

    if (m_available) {
        QDBusInterface properties(
            TimedateService,
            TimedatePath,
            PropertiesInterface,
            QDBusConnection::systemBus()
        );

        if (properties.isValid()) {
            const QDBusReply<QDBusVariant> reply =
                properties.call(
                    QStringLiteral("Get"),
                    TimedateInterface,
                    QStringLiteral("Timezone")
                );

            if (reply.isValid()) {
                detectedTimezone =
                    cleanedTimezoneId(
                        reply.value()
                            .variant()
                            .toString()
                    );
            }
        }
    }

    if (!isValidTimezone(
            detectedTimezone)) {
        detectedTimezone =
            systemTimezoneId();
    }

    if (!isValidTimezone(
            detectedTimezone)) {
        detectedTimezone =
            QStringLiteral("UTC");
    }

    if (detectedTimezone ==
            m_timezone) {
        return;
    }

    m_timezone = detectedTimezone;
    savePreferences();

    emit timezoneChanged();
    emit settingsChanged();

    updateCurrentDateTime();
}

void ClockSettingsManager::rebuildTimezoneModel()
{
    const QVariantList oldModel =
        m_availableTimezones;

    QList<QByteArray> identifiers =
        QTimeZone::availableTimeZoneIds();

    if (!identifiers.contains(
            QByteArrayLiteral("UTC"))) {
        identifiers.append(
            QByteArrayLiteral("UTC")
        );
    }

    QVariantList model;
    QSet<QString> ids;

    for (const QByteArray &identifier :
            identifiers) {
        const QString timezoneId =
            cleanedTimezoneId(
                QString::fromUtf8(
                    identifier
                )
            );

        if (timezoneId.isEmpty() ||
                ids.contains(
                    timezoneId) ||
                !isValidTimezone(
                    timezoneId)) {
            continue;
        }

        ids.insert(timezoneId);
        model.append(
            timezoneToMap(
                timezoneId
            )
        );
    }

    const QString current =
        cleanedTimezoneId(
            m_timezone
        );

    if (isValidTimezone(current) &&
            !ids.contains(current)) {
        ids.insert(current);

        model.append(
            timezoneToMap(current)
        );
    }

    std::sort(
        model.begin(),
        model.end(),
        [](const QVariant &left,
           const QVariant &right) {
            const QVariantMap leftMap =
                left.toMap();

            const QVariantMap rightMap =
                right.toMap();

            const int leftOffset =
                leftMap.value(
                    QStringLiteral(
                        "offsetSeconds"
                    )
                ).toInt();

            const int rightOffset =
                rightMap.value(
                    QStringLiteral(
                        "offsetSeconds"
                    )
                ).toInt();

            if (leftOffset != rightOffset)
                return leftOffset < rightOffset;

            return QString::localeAwareCompare(
                       leftMap.value(
                           QStringLiteral(
                               "id"
                           )
                       ).toString(),
                       rightMap.value(
                           QStringLiteral(
                               "id"
                           )
                       ).toString()
                   ) < 0;
        }
    );

    m_availableTimezones = model;
    m_availableTimezoneIds = ids;

    if (oldModel !=
            m_availableTimezones) {
        emit availableTimezonesChanged();
        incrementTimezoneRevision();
    }
}

void ClockSettingsManager::incrementTimezoneRevision()
{
    ++m_timezoneRevision;

    if (m_timezoneRevision >
            1000000000) {
        m_timezoneRevision = 1;
    }

    emit timezoneRevisionChanged();
}

void ClockSettingsManager::coalescedRefresh()
{
    refreshServiceState();
    readSystemTimezone();

    if (m_availableTimezones.isEmpty())
        rebuildTimezoneModel();

    updateCurrentDateTime();
}

/*
    ========================================================================
                       VALIDATION AND NORMALIZATION
    ========================================================================
*/

bool ClockSettingsManager::validateSettingsPayload(
    const QVariantMap &payload,
    bool *use24HourValue,
    QString *timezoneValue,
    QString *tintValue,
    QString *errorMessage) const
{
    const bool format =
        normalizedUse24Hour(
            payload,
            m_use24Hour
        );

    const QString timezoneId =
        normalizedTimezone(
            payload,
            m_timezone
        );

    if (!isValidTimezone(
            timezoneId)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Invalid timezone: %1"
                ).arg(timezoneId);
        }

        return false;
    }

    const QStringList tintKeys = {
        QStringLiteral("clockTint"),
        QStringLiteral("textTint"),
        QStringLiteral("clockTextColor"),
        QStringLiteral("tint")
    };

    QString tint;

    if (payloadContainsAny(
            payload,
            tintKeys)) {
        tint =
            normalizedColor(
                payloadString(
                    payload,
                    tintKeys
                )
            );

        if (tint.isEmpty()) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Clock tint must use #RRGGBB or #AARRGGBB"
                    );
            }

            return false;
        }
    } else {
        tint = m_clockTint;
    }

    if (use24HourValue)
        *use24HourValue = format;

    if (timezoneValue)
        *timezoneValue = timezoneId;

    if (tintValue)
        *tintValue = tint;

    if (errorMessage)
        errorMessage->clear();

    return true;
}

bool ClockSettingsManager::normalizedUse24Hour(
    const QVariantMap &payload,
    bool fallbackValue) const
{
    const QStringList keys = {
        QStringLiteral("use24Hour"),
        QStringLiteral("timeFormat24Hour"),
        QStringLiteral("format"),
        QStringLiteral("clockFormat"),
        QStringLiteral("timeFormat")
    };

    for (const QString &key : keys) {
        if (!payload.contains(key))
            continue;

        return isTruthyText(
            payload.value(key),
            fallbackValue
        );
    }

    return fallbackValue;
}

QString ClockSettingsManager::normalizedTimezone(
    const QVariantMap &payload,
    const QString &fallbackValue) const
{
    const QString value =
        payloadString(
            payload,
            QStringList()
                << QStringLiteral("timezone")
                << QStringLiteral(
                    "currentTimezone"
                )
                << QStringLiteral("timeZone")
        );

    if (value.isEmpty())
        return cleanedTimezoneId(
            fallbackValue
        );

    return cleanedTimezoneId(value);
}

QString ClockSettingsManager::normalizedTint(
    const QVariantMap &payload,
    const QString &fallbackValue) const
{
    const QString value =
        payloadString(
            payload,
            QStringList()
                << QStringLiteral("clockTint")
                << QStringLiteral("textTint")
                << QStringLiteral(
                    "clockTextColor"
                )
                << QStringLiteral("tint")
        );

    if (value.isEmpty())
        return normalizedColor(
            fallbackValue
        );

    const QString normalized =
        normalizedColor(value);

    return normalized.isEmpty()
           ? normalizedColor(
                 fallbackValue
             )
           : normalized;
}

QString ClockSettingsManager::normalizedColor(
    const QString &color) const
{
    QString value =
        color.trimmed()
            .toUpper();

    if (value.isEmpty())
        return QString();

    if (!value.startsWith(
            QStringLiteral("#"))) {
        return QString();
    }

    const QRegularExpression shortPattern(
        QStringLiteral(
            "^#([0-9A-F]{3})$"
        )
    );

    const QRegularExpressionMatch shortMatch =
        shortPattern.match(value);

    if (shortMatch.hasMatch()) {
        const QString compact =
            shortMatch.captured(1);

        value =
            QStringLiteral("#") +
            QString(compact[0]) +
            QString(compact[0]) +
            QString(compact[1]) +
            QString(compact[1]) +
            QString(compact[2]) +
            QString(compact[2]);

        return value;
    }

    const QRegularExpression fullPattern(
        QStringLiteral(
            "^#(?:[0-9A-F]{6}|[0-9A-F]{8})$"
        )
    );

    if (!fullPattern.match(
            value
        ).hasMatch()) {
        return QString();
    }

    return value;
}

QString ClockSettingsManager::normalizedAction(
    const QString &action) const
{
    QString result =
        action.trimmed()
            .toLower();

    result.remove(
        QRegularExpression(
            QStringLiteral(
                "[\\s_\\-]"
            )
        )
    );

    return result;
}

/*
    ========================================================================
                         TIMEZONE MODEL HELPERS
    ========================================================================
*/

QString ClockSettingsManager::timezoneDisplayName(
    const QString &timezoneId) const
{
    const QString normalized =
        cleanedTimezoneId(
            timezoneId
        );

    if (normalized ==
            QStringLiteral("UTC")) {
        return QStringLiteral("UTC");
    }

    const QString region =
        timezoneRegion(normalized);

    const QString city =
        timezoneCity(normalized);

    if (!city.isEmpty() &&
            !region.isEmpty()) {
        return city +
               QStringLiteral(" — ") +
               region;
    }

    if (!city.isEmpty())
        return city;

    return normalized;
}

QString ClockSettingsManager::timezoneRegion(
    const QString &timezoneId) const
{
    const QString normalized =
        cleanedTimezoneId(
            timezoneId
        );

    if (normalized ==
            QStringLiteral("UTC")) {
        return QStringLiteral("UTC");
    }

    const QStringList parts =
        normalized.split(
            QStringLiteral("/"),
            Qt::SkipEmptyParts
        );

    if (parts.isEmpty())
        return QString();

    return friendlyTimezonePart(
        parts.first()
    );
}

QString ClockSettingsManager::timezoneCity(
    const QString &timezoneId) const
{
    const QString normalized =
        cleanedTimezoneId(
            timezoneId
        );

    if (normalized ==
            QStringLiteral("UTC")) {
        return QStringLiteral(
            "Coordinated Universal Time"
        );
    }

    const QStringList parts =
        normalized.split(
            QStringLiteral("/"),
            Qt::SkipEmptyParts
        );

    if (parts.isEmpty())
        return normalized;

    return friendlyTimezonePart(
        parts.last()
    );
}

QString ClockSettingsManager::utcOffsetText(
    int offsetSeconds) const
{
    const QChar sign =
        offsetSeconds < 0
        ? QLatin1Char('-')
        : QLatin1Char('+');

    const int absoluteSeconds =
        qAbs(offsetSeconds);

    const int hours =
        absoluteSeconds / 3600;

    const int minutes =
        (
            absoluteSeconds % 3600
        ) / 60;

    return QStringLiteral("UTC%1%2:%3")
        .arg(sign)
        .arg(
            hours,
            2,
            10,
            QLatin1Char('0')
        )
        .arg(
            minutes,
            2,
            10,
            QLatin1Char('0')
        );
}

QVariantMap ClockSettingsManager::timezoneToMap(
    const QString &timezoneId) const
{
    QVariantMap result;

    const QString normalized =
        effectiveTimezone(
            timezoneId
        );

    const QTimeZone zone(
        normalized.toUtf8()
    );

    const QDateTime utcNow =
        QDateTime::currentDateTimeUtc();

    const int offsetSeconds =
        zone.isValid()
        ? zone.offsetFromUtc(utcNow)
        : 0;

    const QString displayName =
        timezoneDisplayName(
            normalized
        );

    result[
        QStringLiteral("id")
    ] = normalized;

    result[
        QStringLiteral("timezone")
    ] = normalized;

    result[
        QStringLiteral("timeZone")
    ] = normalized;

    result[
        QStringLiteral("value")
    ] = normalized;

    result[
        QStringLiteral("name")
    ] = displayName;

    result[
        QStringLiteral("displayName")
    ] = displayName;

    result[
        QStringLiteral("label")
    ] = displayName;

    result[
        QStringLiteral("region")
    ] = timezoneRegion(normalized);

    result[
        QStringLiteral("city")
    ] = timezoneCity(normalized);

    result[
        QStringLiteral("utcOffset")
    ] = utcOffsetText(
        offsetSeconds
    );

    result[
        QStringLiteral("offset")
    ] = result.value(
        QStringLiteral("utcOffset")
    );

    result[
        QStringLiteral("offsetSeconds")
    ] = offsetSeconds;

    result[
        QStringLiteral("abbreviation")
    ] = zone.isValid()
        ? zone.abbreviation(utcNow)
        : QStringLiteral("UTC");

    result[
        QStringLiteral("current")
    ] = normalized == m_timezone;

    result[
        QStringLiteral("valid")
    ] = zone.isValid();

    return result;
}

/*
    ========================================================================
                              TIME FORMATTING
    ========================================================================
*/

QDateTime ClockSettingsManager::dateTimeForZone(
    const QString &timezoneId) const
{
    const QString effective =
        effectiveTimezone(
            timezoneId
        );

    const QTimeZone zone(
        effective.toUtf8()
    );

    if (!zone.isValid())
        return QDateTime();

    return QDateTime::currentDateTimeUtc()
        .toTimeZone(zone);
}

QString ClockSettingsManager::effectiveTimezone(
    const QString &timezoneId) const
{
    const QString requested =
        cleanedTimezoneId(
            timezoneId
        );

    if (isValidTimezone(requested))
        return requested;

    const QString current =
        cleanedTimezoneId(
            m_timezone
        );

    if (isValidTimezone(current))
        return current;

    const QString system =
        systemTimezoneId();

    if (isValidTimezone(system))
        return system;

    return QStringLiteral("UTC");
}

/*
    ========================================================================
                           D-BUS TIMEZONE CHANGE
    ========================================================================
*/

bool ClockSettingsManager::requestTimezoneChange(
    const QString &timezoneId,
    const QVariantMap &payload)
{
    if (!isValidTimezone(timezoneId)) {
        setLastError(QStringLiteral("Invalid timezone: %1").arg(timezoneId));
        clearPendingTransaction();
        return false;
    }

    beginOperation(QStringLiteral("apply"), payload);
    QProcess process;
    process.start(QStringLiteral("/usr/bin/sudo"),
                  {QStringLiteral("-n"),
                   QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                   QStringLiteral("set-timezone"), timezoneId});
    if (!process.waitForFinished(15000)) {
        process.kill();
        process.waitForFinished(1000);
        finishOperation(QStringLiteral("apply"), false,
                        QStringLiteral("Timezone service timed out"), payload);
        return false;
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        QString error = QString::fromUtf8(process.readAllStandardError()).trimmed();
        if (error.isEmpty())
            error = QString::fromUtf8(process.readAllStandardOutput()).trimmed();
        finishOperation(QStringLiteral("apply"), false,
                        error.isEmpty() ? QStringLiteral("Timezone change failed") : error,
                        payload);
        return false;
    }

    commitLocalSettings(m_pendingUse24Hour, m_pendingClockTint);
    commitTimezone(m_pendingTimezone);
    const bool saved = savePreferences();
    finishOperation(QStringLiteral("apply"), saved,
                    saved ? QStringLiteral("Clock settings applied")
                          : QStringLiteral("Timezone changed, but local clock preferences could not be persisted"),
                    payload);
    m_refreshCoalesceTimer.start(RefreshCoalesceDelayMs);
    return saved;
}

void ClockSettingsManager::onSetTimezoneFinished(
    QDBusPendingCallWatcher *watcher)
{
    const quint64 serial =
        watcher->property(
            "serial"
        ).toULongLong();

    const QVariantMap payload =
        watcher->property(
            "payload"
        ).toMap();

    if (serial != m_operationSerial) {
        watcher->deleteLater();
        return;
    }

    if (watcher->isError()) {
        const QString message =
            watcher->error().message()
                .trimmed();

        finishOperation(
            QStringLiteral("apply"),
            false,
            message.isEmpty()
            ? QStringLiteral(
                  "System timezone change failed"
              )
            : message,
            payload
        );

        watcher->deleteLater();
        return;
    }

    commitLocalSettings(
        m_pendingUse24Hour,
        m_pendingClockTint
    );

    commitTimezone(
        m_pendingTimezone
    );

    const bool saved =
        savePreferences();

    finishOperation(
        QStringLiteral("apply"),
        saved,
        saved
        ? QStringLiteral(
              "Clock settings applied"
          )
        : QStringLiteral(
              "Timezone changed, but local clock preferences could not be persisted"
          ),
        payload
    );

    m_refreshCoalesceTimer.start(
        RefreshCoalesceDelayMs
    );

    watcher->deleteLater();
}

/*
    ========================================================================
                         TRANSACTION COMMIT
    ========================================================================
*/

void ClockSettingsManager::commitLocalSettings(
    bool use24HourValue,
    const QString &tintValue)
{
    const QString normalizedTintValue =
        normalizedColor(
            tintValue
        );

    bool changed = false;

    if (m_use24Hour !=
            use24HourValue) {
        m_use24Hour =
            use24HourValue;

        emit use24HourChanged();
        changed = true;
    }

    if (!normalizedTintValue.isEmpty() &&
            m_clockTint !=
            normalizedTintValue) {
        m_clockTint =
            normalizedTintValue;

        emit clockTintChanged();
        changed = true;
    }

    if (changed)
        emit settingsChanged();
}

void ClockSettingsManager::commitTimezone(
    const QString &timezoneId)
{
    const QString normalized =
        cleanedTimezoneId(
            timezoneId
        );

    if (!isValidTimezone(normalized) ||
            m_timezone == normalized) {
        updateCurrentDateTime();
        return;
    }

    m_timezone = normalized;

    emit timezoneChanged();
    emit settingsChanged();

    updateCurrentDateTime();
}

void ClockSettingsManager::clearPendingTransaction()
{
    m_pendingTimezone.clear();
    m_pendingUse24Hour = m_use24Hour;
    m_pendingClockTint = m_clockTint;
    m_pendingPayload.clear();
    m_pendingAction.clear();
}

/*
    ========================================================================
                         OPERATION LIFECYCLE
    ========================================================================
*/

void ClockSettingsManager::beginOperation(
    const QString &action,
    const QVariantMap &payload)
{
    ++m_operationSerial;

    m_pendingAction = action;
    m_pendingPayload =
        sanitizedPayload(payload);

    setLastError(QString());

    setLastOperation(
        QStringLiteral(
            "%1 started"
        ).arg(action)
    );

    setOperationBusy(true);

    emit operationStarted(
        action,
        m_pendingPayload
    );
}

void ClockSettingsManager::finishOperation(
    const QString &action,
    bool success,
    const QString &message,
    const QVariantMap &payload)
{
    const QVariantMap safePayload =
        payload.isEmpty()
        ? m_pendingPayload
        : sanitizedPayload(payload);

    if (success)
        setLastError(QString());
    else
        setLastError(message);

    setLastOperation(message);
    setOperationBusy(false);

    clearPendingTransaction();

    emit operationFinished(
        action,
        success,
        message,
        safePayload
    );
}

void ClockSettingsManager::setOperationBusy(
    bool busy)
{
    if (m_operationBusy == busy)
        return;

    m_operationBusy = busy;
    emit operationBusyChanged();
}

void ClockSettingsManager::setLastError(
    const QString &message)
{
    if (m_lastError == message)
        return;

    m_lastError = message;
    emit lastErrorChanged();
}

void ClockSettingsManager::setLastOperation(
    const QString &message)
{
    if (m_lastOperation == message)
        return;

    m_lastOperation = message;
    emit lastOperationChanged();
}

QVariantMap ClockSettingsManager::sanitizedPayload(
    const QVariantMap &payload) const
{
    QVariantMap result;

    for (auto iterator =
             payload.constBegin();
         iterator != payload.constEnd();
         ++iterator) {
        const QString normalizedKey =
            iterator.key()
                .trimmed()
                .toLower();

        if (normalizedKey.contains(
                QStringLiteral("password")) ||
                normalizedKey.contains(
                    QStringLiteral("secret")) ||
                normalizedKey.contains(
                    QStringLiteral("token"))) {
            continue;
        }

        if (iterator.value().type() ==
                QVariant::Map) {
            result.insert(
                iterator.key(),
                sanitizedPayload(
                    iterator.value()
                        .toMap()
                )
            );

            continue;
        }

        result.insert(
            iterator.key(),
            iterator.value()
        );
    }

    return result;
}

/*
    ========================================================================
                              CLOCK TICK
    ========================================================================
*/

void ClockSettingsManager::updateCurrentDateTime()
{
    const QDateTime updated =
        dateTimeForZone(
            m_timezone
        );

    if (!updated.isValid())
        return;

    if (m_currentDateTime.isValid() &&
            m_currentDateTime.toSecsSinceEpoch() ==
            updated.toSecsSinceEpoch() &&
            m_currentDateTime.timeZone() ==
            updated.timeZone()) {
        return;
    }

    m_currentDateTime = updated;
    emit currentDateTimeChanged();
}
// World-clock presentation uses the same authoritative timedated state and clock.json.
namespace {
QHash<QString,QPointF> worldClockCoordinates()
{
    QHash<QString,QPointF> result;
    const QRegularExpression pattern(QStringLiteral("^([+-])(\\d{2})(\\d{2})(\\d{2})?([+-])(\\d{3})(\\d{2})(\\d{2})?$"));
    for (const QString &table : {QStringLiteral("/usr/share/zoneinfo/zone.tab"), QStringLiteral("/usr/share/zoneinfo/zone1970.tab")}) {
        QFile file(table); if (!file.open(QIODevice::ReadOnly)) continue;
        while (!file.atEnd()) {
            const QString line = QString::fromUtf8(file.readLine()).trimmed();
            if (line.startsWith(QLatin1Char('#'))) continue;
            const QStringList fields = line.split(QLatin1Char('\t'));
            if (fields.size() < 3) continue;
            const auto match = pattern.match(fields[1]); if (!match.hasMatch()) continue;
            const double latitude = (match.captured(2).toInt()+match.captured(3).toInt()/60.0+match.captured(4).toInt()/3600.0)*(match.captured(1)==QStringLiteral("-")?-1:1);
            const double longitude = (match.captured(6).toInt()+match.captured(7).toInt()/60.0+match.captured(8).toInt()/3600.0)*(match.captured(5)==QStringLiteral("-")?-1:1);
            result.insert(fields[2], QPointF(longitude,latitude));
        }
    }
    return result;
}
}

bool ClockSettingsManager::setLockscreenDetailsVisible(bool visible)
{
    if (visible == m_lockscreenDetailsVisible) return true;
    const bool previous = m_lockscreenDetailsVisible;
    m_lockscreenDetailsVisible = visible;
    if (!savePreferences()) {
        m_lockscreenDetailsVisible = previous;
        setLastError(QStringLiteral("Lockscreen visibility could not be saved"));
        return false;
    }
    emit lockscreenDetailsVisibleChanged();
    emit settingsChanged();
    return true;
}

bool ClockSettingsManager::setLockscreenClockVisible(bool visible)
{
    if (visible == m_lockscreenClockVisible) return true;
    const bool previous = m_lockscreenClockVisible; m_lockscreenClockVisible = visible;
    if (!savePreferences()) { m_lockscreenClockVisible = previous; setLastError(QStringLiteral("Lockscreen clock visibility could not be saved")); return false; }
    if (!visible) cancelLockscreenTimezoneRequest();
    emit lockscreenClockVisibleChanged(); emit settingsChanged(); return true;
}
bool ClockSettingsManager::setLockscreenWelcomeVisible(bool visible)
{
    if (visible == m_lockscreenWelcomeVisible) return true;
    const bool previous = m_lockscreenWelcomeVisible; m_lockscreenWelcomeVisible = visible;
    if (!savePreferences()) { m_lockscreenWelcomeVisible = previous; setLastError(QStringLiteral("Lockscreen welcome visibility could not be saved")); return false; }
    emit lockscreenWelcomeVisibleChanged(); emit settingsChanged(); return true;
}
QVariantList ClockSettingsManager::worldClockRegions() const
{
    QVariantList regions;
    for (const QString &zone : {QStringLiteral("America/New_York"),QStringLiteral("America/Los_Angeles"),QStringLiteral("America/Sao_Paulo"),QStringLiteral("Europe/London"),QStringLiteral("Europe/Paris"),QStringLiteral("Africa/Cairo"),QStringLiteral("Africa/Johannesburg"),QStringLiteral("Asia/Dubai"),QStringLiteral("Asia/Kolkata"),QStringLiteral("Asia/Kathmandu"),QStringLiteral("Asia/Tokyo"),QStringLiteral("Australia/Sydney"),QStringLiteral("Pacific/Auckland")}) {
        if (QTimeZone::isTimeZoneIdAvailable(zone.toUtf8())) regions.append(worldClockRegion(zone));
    }
    return regions;
}
QVariantMap ClockSettingsManager::worldClockRegion(const QString &zone) const
{
    const QString id = effectiveTimezone(zone);
    static const auto coordinates = worldClockCoordinates();
    QString coordinateId = id;
    if (!coordinates.contains(coordinateId)) {
        const QString canonical = QFileInfo(QStringLiteral("/usr/share/zoneinfo/")+id).canonicalFilePath();
        const QString prefix = QStringLiteral("/usr/share/zoneinfo/");
        if (canonical.startsWith(prefix)) coordinateId = canonical.mid(prefix.size());
    }
    const QPointF point = coordinates.value(coordinateId, QPointF(0,51.48));
    return {{QStringLiteral("timezone"),id},{QStringLiteral("label"),friendlyTimezonePart(id.section(QLatin1Char('/'),-1))},
            {QStringLiteral("longitude"),point.x()},{QStringLiteral("latitude"),point.y()},
            {QStringLiteral("coordinatesAvailable"),coordinates.contains(coordinateId)||id==QStringLiteral("UTC")}};
}
QVariantMap ClockSettingsManager::worldClockDisplay(const QString &zone, const QDateTime &instant) const
{
    const QString id = effectiveTimezone(zone);
    const QDateTime value = instant.toTimeZone(QTimeZone(id.toUtf8()));
    if (!value.isValid()) return {};
    const QLocale locale = QLocale::system();
    const QString period = m_use24Hour ? QString() : locale.toString(value.time(),QStringLiteral("AP"));
    QString clockText = locale.toString(value.time(),m_use24Hour?QStringLiteral("HH:mm"):QStringLiteral("h:mm AP"));
    if (!m_use24Hour) {
        clockText.chop(period.size());
        clockText = clockText.trimmed();
    }
    return {{QStringLiteral("timezone"),id},
            {QStringLiteral("time"),clockText},
            {QStringLiteral("period"),period},
            {QStringLiteral("date"),locale.toString(value.date(),QStringLiteral("ddd, MMM d, yyyy"))},
            {QStringLiteral("offsetSeconds"),value.offsetFromUtc()},
            {QStringLiteral("utcMs"),instant.toMSecsSinceEpoch()}};
}
QVariantMap ClockSettingsManager::solarPosition(const QDateTime &instant) const
{
    // NOAA General Solar Position Calculations (approximate geometric Sun, UTC).
    // https://gml.noaa.gov/grad/solcalc/solareqns.PDF
    if (!instant.isValid()) return {};
    const QDateTime utc = instant.toUTC(); const auto time = utc.time();
    constexpr double pi = 3.14159265358979323846;
    const double hours = time.hour()+time.minute()/60.0+(time.second()+time.msec()/1000.0)/3600.0;
    const double gamma = 2*pi/utc.date().daysInYear()*(utc.date().dayOfYear()-1+(hours-12)/24.0);
    const double equation = 229.18*(0.000075+0.001868*std::cos(gamma)-0.032077*std::sin(gamma)-0.014615*std::cos(2*gamma)-0.040849*std::sin(2*gamma));
    const double declination = 0.006918-0.399912*std::cos(gamma)+0.070257*std::sin(gamma)-0.006758*std::cos(2*gamma)+0.000907*std::sin(2*gamma)-0.002697*std::cos(3*gamma)+0.00148*std::sin(3*gamma);
    const double longitude = std::remainder(180-hours*15-equation/4,360.0);
    const double radians = longitude*pi/180;
    return {{QStringLiteral("x"),std::cos(declination)*std::cos(radians)},
            {QStringLiteral("y"),std::sin(declination)},
            {QStringLiteral("z"),std::cos(declination)*std::sin(radians)},
            {QStringLiteral("subsolarLatitude"),declination*180/pi},
            {QStringLiteral("subsolarLongitude"),longitude},
            {QStringLiteral("equationOfTimeMinutes"),equation},
            {QStringLiteral("utcMs"),instant.toMSecsSinceEpoch()}};
}
void ClockSettingsManager::setWorldStatus(const QString &message)
{
    if (message == m_worldStatus)
        return;
    m_worldStatus = message;
    emit worldClockStatusChanged();
}
void ClockSettingsManager::setLockscreenAuthenticationProvider(std::function<QVariantMap()> provider)
{
    m_authenticationProvider=std::move(provider);
}
bool ClockSettingsManager::requestLockscreenTimezone(const QString &zone)
{
    static const QRegularExpression installedId(QStringLiteral("^[A-Za-z_+-]+(?:/[A-Za-z0-9_+-]+)*$"));
    if (!m_lockscreenClockVisible || m_operationBusy || timezoneAuthorizationPending() ||
        !installedId.match(zone).hasMatch() || !QTimeZone::isTimeZoneIdAvailable(zone.toUtf8()) || zone == m_timezone) {
        setWorldStatus(QStringLiteral("Timezone request is unavailable or unchanged")); return false;
    }
    const QVariantMap identity = m_authenticationProvider?m_authenticationProvider():QVariantMap();
    const QString user = identity.value(QStringLiteral("username")).toString();
    if (user.isEmpty() || identity.value(QStringLiteral("busy"),true).toBool() || identity.value(QStringLiteral("lockedOut"),true).toBool()) {
        setWorldStatus(QStringLiteral("Local controller authentication is unavailable; timezone unchanged")); return false;
    }
    m_worldRequestedZone=zone; m_worldRequestedUser=user; m_worldAuthorizationTimer.start();
    emit timezoneAuthorizationPendingChanged();
    setWorldStatus(QStringLiteral("Authenticate with controller passcode to apply %1").arg(zone)); return true;
}
void ClockSettingsManager::cancelLockscreenTimezoneRequest()
{
    if (!timezoneAuthorizationPending()) return;
    m_worldAuthorizationTimer.stop(); m_worldRequestedZone.clear(); m_worldRequestedUser.clear();
    emit timezoneAuthorizationPendingChanged(); setWorldStatus(QStringLiteral("Timezone request cancelled; local timezone unchanged"));
}
void ClockSettingsManager::completeLockscreenTimezoneAuthorization(const QString &verifiedUser)
{
    if (!timezoneAuthorizationPending() || !m_worldAuthorizationTimer.isActive()) return;
    const QVariantMap identity = m_authenticationProvider?m_authenticationProvider():QVariantMap();
    if (verifiedUser != m_worldRequestedUser || verifiedUser != identity.value(QStringLiteral("username")).toString() ||
        identity.value(QStringLiteral("lockedOut"),true).toBool() || m_operationBusy) {
        cancelLockscreenTimezoneRequest(); return;
    }
    m_worldApplyingZone=m_worldRequestedZone;
    m_worldRequestedZone.clear();m_worldRequestedUser.clear();m_worldAuthorizationTimer.stop();emit timezoneAuthorizationPendingChanged();
    m_worldProcessTimedOut=false;
    beginOperation(QStringLiteral("lockscreen-timezone"),{{QStringLiteral("timezone"),m_worldApplyingZone}});
    setWorldStatus(QStringLiteral("Applying authenticated system timezone…"));
    m_worldProcess.start(QStringLiteral("/usr/bin/sudo"),{QStringLiteral("-n"),QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),QStringLiteral("set-timezone"),m_worldApplyingZone});
    m_worldProcessTimer.start();
}
void ClockSettingsManager::finishWorldTimezone(int exitCode, QProcess::ExitStatus status)
{
    if (m_worldApplyingZone.isEmpty()) return;
    m_worldProcessTimer.stop(); const QString expected=m_worldApplyingZone;m_worldApplyingZone.clear();
    const auto result=QJsonDocument::fromJson(m_worldProcess.readAllStandardOutput()).object();
    const bool verified=!m_worldProcessTimedOut && status==QProcess::NormalExit && exitCode==0 &&
        result.value(QStringLiteral("success")).toBool() && result.value(QStringLiteral("timezone")).toString()==expected;
    bool saved=false;
    if (verified) { commitTimezone(expected); saved=savePreferences(); }
    const QString message=verified?(saved?QStringLiteral("Local timezone updated: %1").arg(expected):QStringLiteral("System timezone updated; clock preference persistence failed")):
        (m_worldProcessTimedOut?QStringLiteral("Timezone operation timed out; verify system timezone"):
         QStringLiteral("Timezone service failed; system timezone was not confirmed"));
    setWorldStatus(message);finishOperation(QStringLiteral("lockscreen-timezone"),verified&&saved,message);
    m_refreshCoalesceTimer.start(RefreshCoalesceDelayMs);
}
