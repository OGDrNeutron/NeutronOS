#pragma once
#include <QString>
#include <QVariantMap>
#include <QVariantList>
#include <QProcessEnvironment>
namespace GeminiGames {
struct LaunchPlan { QString runtime,program,workingDirectory; QStringList arguments; QProcessEnvironment environment; QVariantMap capabilities; QString error; };
class RuntimeAdapters {
public:
    static QVariantList runtimes();
    static bool runtimeAvailable(const QVariantMap &configuration);
    static bool validEnvironment(const QVariantMap &environment);
    static QVariantMap hardware();
    static QVariantList recommendations(const QVariantMap &game,const QVariantMap &hardware,const QVariantList &runtimes);
    static LaunchPlan plan(const QVariantMap &game,const QVariantMap &configuration,const QString &stateDirectory);
    static QVariantMap capabilities(const QString &runtime);
};
}
