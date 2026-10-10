#include "BootProgressState.h"
#include "BootVisualSource.h"
#include "FramebufferWriter.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QFileInfo>
#include <QTimer>

#include <array>

namespace {
struct Milestone {
    int percent;
    const char *unit;
    const char *label;
    bool allowActivating;
};

constexpr std::array<Milestone, 11> kSystemMilestones{{
    {10, "systemd-remount-fs.service", "root-filesystem-ready", false},
    {15, "systemd-udev-trigger.service", "device-discovery-ready", false},
    {20, "neutronos-state-setup.service", "neutronos-state-ready", false},
    {25, "neutronos-firewall-guard.service", "firewall-ready", false},
    {30, "neutron-securityd.service", "security-core-ready", false},
    {35, "neutron-security-watchdog.service", "security-watchdog-ready", false},
    {40, "neutronos-controller-transport.service", "controller-transport-ready", false},
    {45, "neutron-remote-service-state.service", "remote-system-state-ready", false},
    {50, "neutron-remote-service.service", "remote-system-service-ready", false},
    {55, "systemd-user-sessions.service", "login-sessions-ready", false},
    {60, "neutronos.service", "neutron-shell-starting", true},
}};

struct UnitStateProbe {
    QString activeState;
    QString error;
    bool unavailable = false;
};

bool isNoSuchUnitError(const QDBusError &error)
{
    return error.name() == QStringLiteral("org.freedesktop.systemd1.NoSuchUnit") ||
           error.name().endsWith(QStringLiteral(".NoSuchUnit"));
}

UnitStateProbe unitActiveState(const QString &unit)
{
    /*
     * This renderer starts in sysinit, before the normal system bus is
     * guaranteed to exist. QDBusConnection::systemBus() caches its first
     * connection attempt, so an early failure can otherwise leave milestone
     * polling permanently disconnected and progress frozen at 5%. Use a
     * named connection and explicitly discard failed attempts so each timer
     * tick can reconnect once dbus becomes available.
     */
    static const QString connectionName =
        QStringLiteral("neutronos-boot-renderer-system-bus");

    QDBusConnection bus = QDBusConnection::connectToBus(
        QDBusConnection::SystemBus, connectionName);
    if (!bus.isConnected()) {
        UnitStateProbe result;
        const QDBusError error = bus.lastError();
        result.error = error.isValid()
            ? QStringLiteral("system bus unavailable: %1: %2")
                  .arg(error.name(), error.message())
            : QStringLiteral("system bus unavailable");
        QDBusConnection::disconnectFromBus(connectionName);
        return result;
    }

    QDBusInterface manager(QStringLiteral("org.freedesktop.systemd1"),
                           QStringLiteral("/org/freedesktop/systemd1"),
                           QStringLiteral("org.freedesktop.systemd1.Manager"), bus);
    if (!manager.isValid()) {
        UnitStateProbe result;
        const QDBusError error = manager.lastError();
        result.error = error.isValid()
            ? QStringLiteral("systemd manager unavailable: %1: %2")
                  .arg(error.name(), error.message())
            : QStringLiteral("systemd manager unavailable");
        return result;
    }

    const QDBusReply<QDBusObjectPath> path =
        manager.call(QStringLiteral("GetUnit"), unit);
    if (!path.isValid()) {
        UnitStateProbe result;
        result.unavailable = isNoSuchUnitError(path.error());
        result.error = QStringLiteral("GetUnit(%1) failed: %2: %3")
                           .arg(unit, path.error().name(), path.error().message());
        return result;
    }

    QDBusInterface properties(QStringLiteral("org.freedesktop.systemd1"),
                              path.value().path(),
                              QStringLiteral("org.freedesktop.DBus.Properties"), bus);
    const QDBusReply<QVariant> state = properties.call(
        QStringLiteral("Get"), QStringLiteral("org.freedesktop.systemd1.Unit"),
        QStringLiteral("ActiveState"));
    if (!state.isValid()) {
        UnitStateProbe result;
        result.error = QStringLiteral("ActiveState(%1) failed: %2: %3")
                           .arg(unit, state.error().name(), state.error().message());
        return result;
    }

    UnitStateProbe result;
    result.activeState = state.value().toString();
    return result;
}

int validateAndCompose(const QStringList &arguments)
{
    BootVisualSource source;
    QString error;
    if (!source.validateArchive(&error)) {
        qCritical().noquote() << error;
        return 2;
    }
    for (int percent = 0; percent <= 100; percent += 5) {
        if (source.progressFrame(percent, &error).isNull()) {
            qCritical().noquote() << error;
            return 2;
        }
    }

    const QImage wide = source.composedProgressFrame(100, QSize(3840, 2160), &error);
    const QImage tall = source.composedProgressFrame(0, QSize(1920, 1280), &error);
    if (wide.size() != QSize(3840, 2160) || tall.size() != QSize(1920, 1280) ||
        tall.pixelColor(0, 0) != QColor(Qt::black)) {
        qCritical().noquote() << "boot composition self-test failed" << error;
        return 2;
    }

    if (arguments.size() == 6 && arguments.at(1) == QStringLiteral("--compose")) {
        bool percentOk = false;
        bool widthOk = false;
        bool heightOk = false;
        const int percent = arguments.at(2).toInt(&percentOk);
        const int width = arguments.at(3).toInt(&widthOk);
        const int height = arguments.at(4).toInt(&heightOk);
        if (!percentOk || !widthOk || !heightOk) {
            qCritical() << "invalid --compose arguments";
            return 2;
        }
        const QImage output = source.composedProgressFrame(percent, QSize(width, height), &error);
        if (output.isNull() || !output.save(arguments.at(5), "PNG")) {
            qCritical().noquote() << "could not save composed frame:" << error;
            return 2;
        }
    }

    qInfo().noquote() << "Boot.zip validated" << source.archivePath()
                      << BootVisualSource::expectedArchiveSha256();
    return 0;
}

int stateSelfTest(const QString &directory)
{
    BootProgressState state(directory);
    QString error;
    if (!state.begin(&error) ||
        !state.advance(5, QStringLiteral("framebuffer-ready"), &error) ||
        !state.advance(0, QStringLiteral("backward-update-ignored"), &error) ||
        state.advance(99, QStringLiteral("invalid-99"), &error) ||
        !state.advance(10, QStringLiteral("root-filesystem-ready"), &error) ||
        state.progress() != 10) {
        qCritical().noquote() << "boot state self-test failed:" << error;
        return 2;
    }
    qInfo() << "Boot progress state self-test passed" << state.progress();
    return 0;
}

int probeMilestones()
{
    bool transportHealthy = true;
    for (const Milestone &milestone : kSystemMilestones) {
        const UnitStateProbe probe =
            unitActiveState(QString::fromLatin1(milestone.unit));
        if (probe.unavailable) {
            qWarning().noquote() << milestone.percent << milestone.unit
                                 << "unavailable" << probe.error;
            continue;
        }
        if (probe.activeState.isEmpty()) {
            qWarning().noquote() << milestone.percent << milestone.unit
                                 << "query-error" << probe.error;
            transportHealthy = false;
            continue;
        }
        qInfo().noquote() << milestone.percent << milestone.unit
                          << probe.activeState;
    }
    return transportHealthy ? 0 : 2;
}
}

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("NeutronBootRenderer"));
    const QStringList arguments = application.arguments();

    if (arguments.contains(QStringLiteral("--validate")) ||
        arguments.contains(QStringLiteral("--compose")))
        return validateAndCompose(arguments);

    const qsizetype stateSelfTestIndex = arguments.indexOf(
        QStringLiteral("--state-self-test"));
    if (stateSelfTestIndex >= 0) {
        if (stateSelfTestIndex + 1 >= arguments.size()) {
            qCritical() << "--state-self-test requires a directory";
            return 2;
        }
        return stateSelfTest(arguments.at(stateSelfTestIndex + 1));
    }

    if (arguments.contains(QStringLiteral("--probe-milestones")))
        return probeMilestones();

    if (arguments.contains(QStringLiteral("--probe-framebuffer"))) {
        FramebufferWriter writer;
        QString error;
        const auto geometry = writer.probe(&error);
        if (!geometry.isValid()) {
            qCritical().noquote() << error;
            return 2;
        }
        qInfo().noquote() << geometry.description();
        return 0;
    }

    BootVisualSource source;
    QString error;
    if (!source.validateArchive(&error)) {
        qCritical().noquote() << "Boot renderer disabled:" << error;
        return 1;
    }

    BootProgressState state;
    if (!state.begin(&error)) {
        qCritical().noquote() << "Boot renderer could not initialize state:" << error;
        return 1;
    }

    FramebufferWriter framebuffer;
    FramebufferWriter::Geometry lastGeometry;
    int renderedProgress = -1;
    bool framebufferReady = false;
    qsizetype nextMilestone = 0;
    QString lastMilestoneProbeError;

    QTimer timer;
    timer.setInterval(100);
    const auto tick = [&] {
        if (QFileInfo::exists(QStringLiteral("/run/neutronos/login-ready"))) {
            qInfo() << "Boot renderer observed revealed Login readiness";
            application.quit();
            return;
        }

        const bool displayTaken = state.hasMarker(QStringLiteral("display-taken"));
        QString probeError;
        const auto geometry = framebuffer.probe(&probeError);
        if (!displayTaken && geometry.isValid()) {
            const int current = qMax(0, state.progress());
            if (current != renderedProgress || geometry != lastGeometry) {
                QString composeError;
                const QImage frame = source.composedProgressFrame(
                    current, QSize(geometry.width, geometry.height), &composeError);
                FramebufferWriter::Geometry writtenGeometry;
                if (!frame.isNull() && framebuffer.write(frame, &writtenGeometry, &composeError)) {
                    renderedProgress = current;
                    lastGeometry = writtenGeometry;
                    if (!framebufferReady) {
                        framebufferReady = true;
                        state.advance(5, QStringLiteral("framebuffer-ready"), &composeError);
                        qInfo() << "BOOT_PROGRESS" << 5 << "framebuffer-ready";
                        return;
                    }
                    qInfo().noquote() << "BOOT_FRAME" << renderedProgress
                                      << writtenGeometry.description();
                } else {
                    qWarning().noquote() << "Boot framebuffer write failed:" << composeError;
                }
            }
        }

        if ((!framebufferReady && !displayTaken) || nextMilestone >=
                                     static_cast<qsizetype>(kSystemMilestones.size()))
            return;
        const Milestone &milestone = kSystemMilestones.at(
            static_cast<size_t>(nextMilestone));
        const UnitStateProbe probe =
            unitActiveState(QString::fromLatin1(milestone.unit));

        if (probe.unavailable) {
            qWarning().noquote() << "Boot milestone unavailable; skipping"
                                 << milestone.unit << probe.error;
            QString transitionError;
            if (state.advance(milestone.percent,
                              QString::fromLatin1(milestone.label),
                              &transitionError)) {
                qInfo().noquote() << "BOOT_PROGRESS" << milestone.percent
                                  << milestone.label << "unit-unavailable";
                ++nextMilestone;
                lastMilestoneProbeError.clear();
            } else {
                qWarning().noquote() << "Boot progress update failed:"
                                     << transitionError;
            }
            return;
        }

        if (probe.activeState.isEmpty()) {
            if (!probe.error.isEmpty() && probe.error != lastMilestoneProbeError) {
                qWarning().noquote() << "Boot milestone query waiting:"
                                     << milestone.unit << probe.error;
                lastMilestoneProbeError = probe.error;
            }
            return;
        }

        if (!lastMilestoneProbeError.isEmpty()) {
            qInfo().noquote() << "Boot milestone query recovered:"
                              << milestone.unit << probe.activeState;
            lastMilestoneProbeError.clear();
        }

        if (probe.activeState != QStringLiteral("active") &&
            !(milestone.allowActivating &&
              probe.activeState == QStringLiteral("activating")))
            return;

        QString transitionError;
        if (state.advance(milestone.percent, QString::fromLatin1(milestone.label),
                          &transitionError)) {
            qInfo().noquote() << "BOOT_PROGRESS" << milestone.percent << milestone.label;
            ++nextMilestone;
        } else {
            qWarning().noquote() << "Boot progress update failed:" << transitionError;
        }
    };
    QObject::connect(&timer, &QTimer::timeout, &application, tick);
    timer.start();
    QTimer::singleShot(0, &application, tick);
    return application.exec();
}
