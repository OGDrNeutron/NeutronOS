#include "JellyfinManager.h"
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
    if (!configured.isEmpty() &&
        QFileInfo::exists(QDir(configured).filePath(QStringLiteral("qml/Main.qml")))) {
        return QDir::cleanPath(configured);
    }

    const QString standard = QStringLiteral("/opt/neutronos");
    if (QFileInfo::exists(QDir(standard).filePath(QStringLiteral("qml/Main.qml"))))
        return standard;

    return QDir::cleanPath(QDir::homePath() + QStringLiteral("/NeutronOS"));
}

QObject *createJellyfinManager(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(engine)
    Q_UNUSED(scriptEngine)
    return new JellyfinManager(neutronRootPath());
}

QObject *createRemoteKeyboardManager(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(engine)
    Q_UNUSED(scriptEngine)
    return new RemoteKeyboardManager(neutronRootPath());
}

void registerNeutronManagerTypes()
{
    qmlRegisterSingletonType<JellyfinManager>(
        "NeutronOS.Managers", 1, 0, "JellyfinManager", createJellyfinManager);
    qmlRegisterSingletonType<RemoteKeyboardManager>(
        "NeutronOS.Managers", 1, 0, "RemoteKeyboardManager", createRemoteKeyboardManager);
}
}

Q_COREAPP_STARTUP_FUNCTION(registerNeutronManagerTypes)
