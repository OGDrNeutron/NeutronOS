#include "BrowserManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    QTemporaryDir root;
    if (!root.isValid())
        return 10;

    const QString runtime = root.path() + QStringLiteral("/state/apps/browser-runtime");
    QDir().mkpath(runtime);
    QFile status(runtime + QStringLiteral("/status.json"));
    if (!status.open(QIODevice::WriteOnly))
        return 11;
    status.write("{\"active\":true,\"phase\":\"browser\",\"message\":\"active\"}");
    status.close();

    BrowserManager manager(root.path());
    if (!manager.runtimeActive() || manager.runtimeLaunchAllowed())
        return 12;

    int notifications = 0;
    QObject::connect(&manager, &BrowserManager::runtimeChanged,
                     [&notifications]() { ++notifications; });
    if (!QFile::remove(status.fileName()))
        return 13;
    manager.refreshRuntime();

    if (manager.runtimeActive())
        return 14;
    if (manager.runtimePhase() != QStringLiteral("idle"))
        return 15;
    if (!manager.runtimeLaunchAllowed())
        return 16;
    if (notifications != 1)
        return 17;
    return 0;
}
