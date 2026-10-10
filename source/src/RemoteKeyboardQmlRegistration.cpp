#include "RemoteKeyboardManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJSEngine>
#include <QQmlEngine>
#include <QtQml/qqml.h>

namespace {
QString neutronRootPath()
{
    const QString configured = qEnvironmentVariable("NEUTRONOS_ROOT").trimmed();
    if (!configured.isEmpty())
        return QDir::cleanPath(configured);

    const QString standard = QStringLiteral("/opt/neutronos");
    if (QFileInfo::exists(standard))
        return standard;

    return QDir::cleanPath(QDir::homePath() + QStringLiteral("/NeutronOS"));
}

QObject *createRemoteKeyboardManager(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(engine)
    Q_UNUSED(scriptEngine)
    return new RemoteKeyboardManager(neutronRootPath());
}

void registerRemoteKeyboardType()
{
    qmlRegisterSingletonType<RemoteKeyboardManager>(
        "NeutronOS.Managers", 1, 0, "RemoteKeyboardManager", createRemoteKeyboardManager);
}
}

Q_COREAPP_STARTUP_FUNCTION(registerRemoteKeyboardType)
