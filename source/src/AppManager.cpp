#include "HumanAccountPolicy.h"
#include "AppManager.h"
#include "BrowserManager.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSaveFile>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>
#include <QDebug>
#include <QElapsedTimer>
#include <QDateTime>
#include <QDirIterator>
#include <QCoreApplication>
#include <QThread>
#include <QTimer>

#include <algorithm>

AppManager::AppManager(QObject *parent)
    : QObject(parent)
{
    loadManagedPackageIds();
    loadCarouselState();
    loadUsageState();

    // The controller carousel needs the built-in registry immediately, but it
    // must not scan every desktop file and external app directory before the
    // first frame. Populate the deterministic built-ins now and complete the
    // broader discovery after the event loop is running.
    m_apps.clear();
    m_favoriteApps.clear();
    m_hiddenApps.clear();
    m_seenAppIds.clear();
    discoverBuiltInApps();
    rebuildDerivedLists();
    emit appsChanged();

    QTimer::singleShot(1600, this, [this]() {
        discoverAppsOnce();
    });
}

QVariantList AppManager::apps() const
{
    return m_apps;
}

QVariantList AppManager::dashboardApps() const
{
    // The Modern Dashboard is intentionally manifest-first. Only applications
    // with a real, parseable NeutronOS app.json are eligible. This keeps Linux
    // desktop discoveries (VLC, htop, Terminator, etc.) out of the controller
    // launcher while still allowing developer apps such as Codex.
    QHash<QString, QVariantMap> liveAppsById;
    for (const QVariant &entry : m_apps) {
        const QVariantMap app = entry.toMap();
        const QString id = safeId(app.value(QStringLiteral("id")).toString());
        if (!id.isEmpty())
            liveAppsById.insert(id, app);
    }

    QVariantList visibleApps;
    QHash<QString, QVariantMap> appsById;
    QSet<QString> discoveredIds;

    const QString themeIconsRoot =
        neutronRootPath() + QStringLiteral("/themes/Default/apps/icons");
    const QString stateRoot = HumanHome::appStateRoot();
    const QString payloadIconsRoot =
        stateRoot + QStringLiteral("/apps/payload/themes/Default/apps/icons");
    const QStringList iconExtensions = {
        QStringLiteral("png")
    };

    for (const QString &rootPath : neutronAppSearchPaths()) {
        QDir root(rootPath);
        if (!root.exists())
            continue;

        const QFileInfoList dirs = root.entryInfoList(
            QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);

        for (const QFileInfo &dirInfo : dirs) {
            const QString manifestPath =
                dirInfo.absoluteFilePath() + QStringLiteral("/app.json");
            if (!QFileInfo::exists(manifestPath))
                continue;

            QVariantMap manifestApp = readNeutronManifest(manifestPath);
            const QString id = safeId(
                manifestApp.value(QStringLiteral("id")).toString());

            if (id.isEmpty() || discoveredIds.contains(id) ||
                manifestApp.value(QStringLiteral("hidden"), false).toBool() ||
                manifestApp.value(QStringLiteral("systemOnly"), false).toBool()) {
                continue;
            }

            // Let app.json own identity/presentation/launch metadata, then
            // explicitly restore runtime-owned fields from the live registry.
            // A manifest must never overwrite current AppHost/systemd/Docker
            // state with stale "running": false values.
            const QVariantMap liveApp = liveAppsById.value(id);
            QVariantMap app = liveApp;

            for (auto it = manifestApp.constBegin();
                 it != manifestApp.constEnd();
                 ++it) {
                app.insert(it.key(), it.value());
            }

            const QStringList runtimeKeys = {
                QStringLiteral("installed"),
                QStringLiteral("uiRunning"),
                QStringLiteral("backgroundRunning"),
                QStringLiteral("appRunning"),
                QStringLiteral("serviceRunning"),
                QStringLiteral("running"),
                QStringLiteral("statusText"),
                QStringLiteral("statusColor"),
                QStringLiteral("sessionText"),
                QStringLiteral("lastUsedUtc")
            };

            for (const QString &key : runtimeKeys) {
                if (liveApp.contains(key))
                    app.insert(key, liveApp.value(key));
            }

            // Resolve an actual dashboard icon file. DashboardDockIcon already
            // consumes iconSource first; this also fixes Codex, whose installed
            // asset is SVG rather than PNG.
            if (app.value(QStringLiteral("iconSource")).toString().trimmed().isEmpty()) {
                const QString iconName = app.value(QStringLiteral("icon")).toString().trimmed();
                if (!iconName.isEmpty() &&
                    !iconName.contains(QLatin1Char('/')) &&
                    !iconName.contains(QLatin1Char(':'))) {
                    const QStringList iconRoots = {themeIconsRoot, payloadIconsRoot};
                    bool resolved = false;
                    for (const QString &iconRoot : iconRoots) {
                        for (const QString &extension : iconExtensions) {
                            const QString candidate = QDir(iconRoot).filePath(
                                iconName + QLatin1Char('.') + extension);
                            if (QFileInfo::exists(candidate)) {
                                app.insert(QStringLiteral("iconSource"),
                                           QUrl::fromLocalFile(candidate).toString());
                                resolved = true;
                                break;
                            }
                        }
                        if (resolved)
                            break;
                    }
                }
            }

            visibleApps.append(app);
            appsById.insert(id, app);
            discoveredIds.insert(id);
        }
    }

    QVariantList result;
    QSet<QString> addedIds;

    // Slots 1-3 retain their existing persistent pin behavior.
    for (int slot = 0; slot < 3; ++slot) {
        const QString id = safeId(m_pinnedApps.value(slot));
        if (id.isEmpty() || addedIds.contains(id) || !appsById.contains(id))
            continue;

        QVariantMap app = appsById.value(id);
        app.insert(QStringLiteral("pinSlot"), slot + 1);
        result.append(app);
        addedIds.insert(id);
    }

    QVariantList remaining;
    for (const QVariant &entry : visibleApps) {
        const QVariantMap app = entry.toMap();
        const QString id = safeId(app.value(QStringLiteral("id")).toString());
        if (!addedIds.contains(id))
            remaining.append(app);
    }

    // Preserve the existing MRU behavior for all non-pinned applications.
    std::stable_sort(
        remaining.begin(),
        remaining.end(),
        [this](const QVariant &leftValue, const QVariant &rightValue) {
            const QVariantMap left = leftValue.toMap();
            const QVariantMap right = rightValue.toMap();
            const QString leftId = safeId(left.value(QStringLiteral("id")).toString());
            const QString rightId = safeId(right.value(QStringLiteral("id")).toString());

            const QDateTime leftStamp =
                QDateTime::fromString(m_lastUsedByApp.value(leftId), Qt::ISODate);
            const QDateTime rightStamp =
                QDateTime::fromString(m_lastUsedByApp.value(rightId), Qt::ISODate);

            const bool leftRecent = leftStamp.isValid();
            const bool rightRecent = rightStamp.isValid();

            if (leftRecent != rightRecent)
                return leftRecent;
            if (leftRecent && rightRecent && leftStamp != rightStamp)
                return leftStamp > rightStamp;
            return false;
        }
    );

    for (const QVariant &entry : remaining)
        result.append(entry);

    return result;
}

QVariantMap AppManager::pinnedAppAt(int slot) const
{
    if (slot < 1 || slot > 3)
        return {};

    const QString id = safeId(m_pinnedApps.value(slot - 1));
    if (id.isEmpty())
        return {};

    for (const QVariant &entry : dashboardApps()) {
        QVariantMap app = entry.toMap();
        if (safeId(app.value(QStringLiteral("id")).toString()) != id)
            continue;
        app.insert(QStringLiteral("pinSlot"), slot);
        return app;
    }

    return {};
}

int AppManager::pinnedSlotForApp(const QString &appId) const
{
    const QString id = safeId(appId);
    if (id.isEmpty())
        return 0;

    for (int slot = 0; slot < 3; ++slot) {
        if (m_pinnedApps.value(slot) == id)
            return slot + 1;
    }

    return 0;
}

bool AppManager::pinApp(const QString &appId, int slot)
{
    const QString id = safeId(appId);
    if (id.isEmpty() || slot < 1 || slot > 3)
        return false;

    bool eligible = false;
    for (const QVariant &entry : dashboardApps()) {
        if (safeId(entry.toMap().value(QStringLiteral("id")).toString()) == id) {
            eligible = true;
            break;
        }
    }
    if (!eligible)
        return false;

    while (m_pinnedApps.size() < 3)
        m_pinnedApps.append(QString());

    // An application can occupy exactly one pinned slot.
    for (int index = 0; index < 3; ++index) {
        if (m_pinnedApps.at(index) == id)
            m_pinnedApps[index].clear();
    }

    m_pinnedApps[slot - 1] = id;

    if (!saveCarouselState()) {
        qWarning() << "Unable to persist dashboard pin for" << id << "slot" << slot;
        return false;
    }

    emit appsChanged();
    return true;
}

bool AppManager::unpinApp(const QString &appId)
{
    const QString id = safeId(appId);
    if (id.isEmpty())
        return false;

    bool changed = false;
    while (m_pinnedApps.size() < 3)
        m_pinnedApps.append(QString());

    for (int index = 0; index < 3; ++index) {
        if (m_pinnedApps.at(index) == id) {
            m_pinnedApps[index].clear();
            changed = true;
        }
    }

    if (!changed)
        return true;

    if (!saveCarouselState()) {
        qWarning() << "Unable to persist dashboard unpin for" << id;
        return false;
    }

    emit appsChanged();
    return true;
}

QVariantList AppManager::favoriteApps() const
{
    return m_favoriteApps;
}

QVariantList AppManager::hiddenApps() const
{
    return m_hiddenApps;
}

QVariantList AppManager::runningApps() const { return m_runningApps; }
int AppManager::runningAppCount() const { return m_runningApps.size(); }

int AppManager::appCount() const
{
    return m_apps.size();
}

int AppManager::favoriteAppCount() const
{
    return m_favoriteApps.size();
}

int AppManager::hiddenAppCount() const
{
    return m_hiddenApps.size();
}

QVariantList AppManager::installedApps() const
{
    QVariantList result;
    for (const QVariant &entry : m_apps) {
        const QVariantMap app = entry.toMap();
        if (app.value(QStringLiteral("installed"), true).toBool())
            result.append(app);
    }
    return result;
}

QString AppManager::formatBytes(qulonglong bytes) const
{
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1000.0 && unit < 4) {
        value /= 1000.0;
        ++unit;
    }
    return QString::number(value, unit == 0 ? 'f' : 'f', unit == 0 ? 0 : 1) +
           QLatin1Char(' ') + QString::fromLatin1(units[unit]);
}

QVariantMap AppManager::appCardInfo(const QVariantMap &appData) const
{
    QVariantMap app = normalizeApp(appData);
    const QString id = safeId(app.value(QStringLiteral("id")).toString());

    if (id.isEmpty())
        return {};

    auto topLevelExistingPaths = [](const QStringList &rawPaths) {
        QStringList normalized;

        for (const QString &rawPath : rawPaths) {
            QFileInfo info(rawPath);

            if (!info.exists())
                continue;

            const QString path = QDir::cleanPath(
                info.canonicalFilePath().isEmpty()
                    ? info.absoluteFilePath()
                    : info.canonicalFilePath());

            if (!path.isEmpty() && !normalized.contains(path))
                normalized.append(path);
        }

        std::sort(
            normalized.begin(),
            normalized.end(),
            [](const QString &left, const QString &right) {
                return left.length() < right.length();
            });

        QStringList result;

        for (const QString &path : normalized) {
            bool nested = false;

            for (const QString &parent : result) {
                if (path.startsWith(parent + QDir::separator())) {
                    nested = true;
                    break;
                }
            }

            if (!nested)
                result.append(path);
        }

        return result;
    };

    const QString rawType =
        app.value(QStringLiteral("type"), QStringLiteral("qml"))
            .toString()
            .trimmed()
            .toLower();

    QString registrySource =
        app.value(QStringLiteral("source"))
            .toString()
            .trimmed()
            .toLower();

    for (const QVariant &entry : m_apps) {
        const QVariantMap live = entry.toMap();

        if (safeId(
                live.value(QStringLiteral("id"))
                    .toString()) != id) {
            continue;
        }

        registrySource =
            live.value(QStringLiteral("source"))
                .toString()
                .trimmed()
                .toLower();

        break;
    }

    const QString stateRoot = HumanHome::appStateRoot();

    quint64 installBytes = 0;
    QStringList ownedPaths;

    // Ownership is determined from authoritative OS state, never from a
    // hardcoded list of app ids. App Store registration wins over discovery
    // source because an app can begin as a developer install and later be
    // adopted/updated transactionally by the App Store.
    QJsonObject managedPackage;

    QFile installedRegistry(
        QDir(stateRoot).filePath(
            QStringLiteral("apps/installed.json")));

    if (installedRegistry.open(QIODevice::ReadOnly)) {
        const QJsonObject packages =
            QJsonDocument::fromJson(
                installedRegistry.readAll())
                .object()
                .value(QStringLiteral("packages"))
                .toObject();

        managedPackage = packages.value(id).toObject();
    }

    const bool appStoreManaged = !managedPackage.isEmpty();
    const bool osOwned =
        registrySource == QStringLiteral("builtin") ||
        registrySource == QStringLiteral("system");

    QString typeText;
    QString ownershipSource;

    if (appStoreManaged) {
        typeText = QStringLiteral("App Store");
        ownershipSource = QStringLiteral("apps");
    } else if (osOwned) {
        typeText = QStringLiteral("System");
        ownershipSource = QStringLiteral("system");
    } else {
        typeText = QStringLiteral("Dev App");
        ownershipSource = QStringLiteral("developer");
    }

    // App Store packages already have an authoritative ownership registry.
    if (appStoreManaged) {
        const QJsonObject package = managedPackage;

        for (const QJsonValue &value :
             package.value(QStringLiteral("files")).toArray()) {
            const QString relative =
                value.toString().trimmed();

            if (!relative.isEmpty()) {
                ownedPaths.append(
                    QDir(neutronRootPath())
                        .filePath(relative));
            }
        }

        for (const QJsonValue &value :
             package.value(QStringLiteral("systemFiles")).toArray()) {
            const QString destination =
                value.toObject()
                    .value(QStringLiteral("destination"))
                    .toString()
                    .trimmed();

            if (!destination.isEmpty())
                ownedPaths.append(destination);
        }
    }

    // Built-ins and locally managed apps: only measure their app-owned launch
    // tree plus dedicated icon/poster. Do not recurse app storage or cache just
    // to paint a dashboard card.
    if (ownedPaths.isEmpty()) {
        QString installPath =
            app.value(QStringLiteral("appDir"))
                .toString()
                .trimmed();

        if (installPath.isEmpty()) {
            installPath =
                app.value(QStringLiteral("entry"))
                    .toString()
                    .trimmed();
        }

        if (installPath.startsWith(QStringLiteral("file://")))
            installPath = QUrl(installPath).toLocalFile();

        if (!installPath.isEmpty()) {
            const QFileInfo info(installPath);

            if (info.exists() &&
                info.isFile() &&
                rawType == QStringLiteral("qml")) {
                installPath = info.absolutePath();
            }

            ownedPaths.append(installPath);
        }

        auto appendLocalAsset =
            [&ownedPaths](const QVariant &value) {
                const QString raw =
                    value.toString().trimmed();

                if (raw.isEmpty())
                    return;

                const QUrl url(raw);

                const QString local =
                    url.isLocalFile()
                        ? url.toLocalFile()
                        : raw;

                if (!local.isEmpty() &&
                    QFileInfo::exists(local)) {
                    ownedPaths.append(local);
                }
            };

        appendLocalAsset(
            app.value(QStringLiteral("iconSource")));

        appendLocalAsset(
            app.value(QStringLiteral("posterSource")));

        const QString themeRoot =
            QDir(neutronRootPath()).filePath(
                QStringLiteral("themes/Default/apps"));

        const QString iconName =
            app.value(QStringLiteral("icon"))
                .toString()
                .trimmed();

        const QString posterName =
            app.value(QStringLiteral("poster"))
                .toString()
                .trimmed();

        const QStringList extensions = {
            QStringLiteral("png"),
            QStringLiteral("jpg"),
            QStringLiteral("jpeg"),
            QStringLiteral("webp"),
            QStringLiteral("svg")
        };

        for (const QString &extension : extensions) {
            if (!iconName.isEmpty()) {
                const QString candidate =
                    QDir(themeRoot +
                         QStringLiteral("/icons"))
                        .filePath(
                            iconName +
                            QLatin1Char('.') +
                            extension);

                if (QFileInfo::exists(candidate))
                    ownedPaths.append(candidate);
            }

            if (!posterName.isEmpty()) {
                const QString candidate =
                    QDir(themeRoot +
                         QStringLiteral("/posters"))
                        .filePath(
                            posterName +
                            QLatin1Char('.') +
                            extension);

                if (QFileInfo::exists(candidate))
                    ownedPaths.append(candidate);
            }
        }
    }

    for (const QString &path :
         topLevelExistingPaths(ownedPaths)) {
        installBytes += pathSize(path);
    }

    const QString lastUsedUtc =
        m_lastUsedByApp.value(id);

    const QDateTime used =
        QDateTime::fromString(
            lastUsedUtc,
            Qt::ISODate);

    const QString lastOpenedText =
        used.isValid()
            ? used.toLocalTime().toString(
                  QStringLiteral("MMM d, h:mm AP"))
            : QStringLiteral("Never opened");

    QVariantMap result;

    result.insert(
        QStringLiteral("typeText"),
        typeText);

    result.insert(
        QStringLiteral("ownershipSource"),
        ownershipSource);

    result.insert(
        QStringLiteral("appStoreManaged"),
        appStoreManaged);

    result.insert(
        QStringLiteral("systemOwned"),
        osOwned);

    result.insert(
        QStringLiteral("sizeBytes"),
        QVariant::fromValue<qulonglong>(
            installBytes));

    result.insert(
        QStringLiteral("sizeText"),
        installBytes > 0
            ? formatBytes(installBytes)
            : QStringLiteral("Unknown"));

    result.insert(
        QStringLiteral("lastUsedUtc"),
        lastUsedUtc);

    result.insert(
        QStringLiteral("lastOpenedText"),
        lastOpenedText);

    return result;
}

QVariantMap AppManager::appManagementDetails(const QVariantMap &appData) const
{
    QVariantMap app = normalizeApp(appData);
    const QString id = app.value(QStringLiteral("id")).toString();
    if (id.isEmpty())
        return {};

    auto topLevelExistingPaths = [](const QStringList &rawPaths) {
        QStringList normalized;
        for (const QString &rawPath : rawPaths) {
            QFileInfo info(rawPath);
            if (!info.exists())
                continue;
            const QString path = QDir::cleanPath(info.canonicalFilePath().isEmpty()
                                                 ? info.absoluteFilePath()
                                                 : info.canonicalFilePath());
            if (!path.isEmpty() && !normalized.contains(path))
                normalized.append(path);
        }
        std::sort(normalized.begin(), normalized.end(),
                  [](const QString &left, const QString &right) {
                      return left.length() < right.length();
                  });
        QStringList result;
        for (const QString &path : normalized) {
            bool nested = false;
            for (const QString &parent : result) {
                if (path.startsWith(parent + QDir::separator())) {
                    nested = true;
                    break;
                }
            }
            if (!nested)
                result.append(path);
        }
        return result;
    };

    quint64 storageBytes = 0;
    quint64 cacheBytes = 0;
    const QStringList storagePaths = topLevelExistingPaths(managedStoragePaths(app));
    const QStringList cachePaths = topLevelExistingPaths(managedCachePaths(app));
    for (const QString &path : storagePaths)
        storageBytes += pathSize(path);
    for (const QString &path : cachePaths)
        cacheBytes += pathSize(path);

    QString installPath = app.value(QStringLiteral("appDir")).toString().trimmed();
    if (installPath.isEmpty())
        installPath = app.value(QStringLiteral("entry")).toString().trimmed();
    if (installPath.startsWith(QStringLiteral("file://")))
        installPath = QUrl(installPath).toLocalFile();

    QStringList permissions;
    for (const QVariant &permission : app.value(QStringLiteral("permissions")).toList()) {
        const QString text = permission.toString().trimmed();
        if (!text.isEmpty())
            permissions.append(text);
    }

    quint64 installBytes = 0;
    QString measuredInstallPath = installPath;
    QString installedPackageVersion;

    // App Store packages have an authoritative ownership registry. Measure the
    // files that are actually installed for that package rather than a shared
    // shell binary or an arbitrary launch entry.
    const QString stateRoot = HumanHome::appStateRoot();
    QFile installedRegistry(QDir(stateRoot).filePath(QStringLiteral("apps/installed.json")));
    if (installedRegistry.open(QIODevice::ReadOnly)) {
        const QJsonObject packages = QJsonDocument::fromJson(installedRegistry.readAll()).object()
                                         .value(QStringLiteral("packages")).toObject();
        const QJsonObject package = packages.value(id).toObject();
        if (!package.isEmpty()) {
            installedPackageVersion = package.value(QStringLiteral("version")).toString().trimmed();
            QStringList ownedPaths;
            for (const QJsonValue &value : package.value(QStringLiteral("files")).toArray()) {
                const QString relative = value.toString().trimmed();
                if (!relative.isEmpty())
                    ownedPaths.append(QDir(neutronRootPath()).filePath(relative));
            }
            for (const QJsonValue &value : package.value(QStringLiteral("systemFiles")).toArray()) {
                const QString destination = value.toObject().value(QStringLiteral("destination")).toString().trimmed();
                if (!destination.isEmpty())
                    ownedPaths.append(destination);
            }
            const QStringList packagePaths = topLevelExistingPaths(ownedPaths);
            for (const QString &path : packagePaths)
                installBytes += pathSize(path);
            if (!packagePaths.isEmpty())
                measuredInstallPath = QStringLiteral("App Store package ownership registry");
        }
    }

    // Built-in/system apps share NeutronShell, so attributing the full shell to
    // every app would make all sizes identical. Measure the app's own QML tree
    // plus its dedicated icon/poster assets instead.
    if (installBytes == 0) {
        QStringList ownedPaths;
        if (!installPath.isEmpty()) {
            const QFileInfo installInfo(installPath);
            const QString appType = app.value(QStringLiteral("type"), QStringLiteral("qml")).toString().toLower();
            if (installInfo.exists() && installInfo.isFile() && appType == QStringLiteral("qml"))
                measuredInstallPath = installInfo.absolutePath();
            ownedPaths.append(measuredInstallPath);
        }

        auto appendLocalAsset = [&ownedPaths](const QVariant &value) {
            const QString raw = value.toString().trimmed();
            if (raw.isEmpty())
                return;
            const QUrl url(raw);
            const QString local = url.isLocalFile() ? url.toLocalFile() : raw;
            if (!local.isEmpty() && QFileInfo::exists(local))
                ownedPaths.append(local);
        };
        appendLocalAsset(app.value(QStringLiteral("iconSource")));
        appendLocalAsset(app.value(QStringLiteral("posterSource")));

        const QString iconName = app.value(QStringLiteral("icon")).toString().trimmed();
        const QString posterName = app.value(QStringLiteral("poster")).toString().trimmed();
        const QString themeRoot = QDir(neutronRootPath()).filePath(QStringLiteral("themes/Default/apps"));
        const QStringList extensions = {QStringLiteral("png"), QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("webp"), QStringLiteral("svg")};
        for (const QString &extension : extensions) {
            if (!iconName.isEmpty()) {
                const QString candidate = QDir(themeRoot + QStringLiteral("/icons")).filePath(iconName + QLatin1Char('.') + extension);
                if (QFileInfo::exists(candidate)) ownedPaths.append(candidate);
            }
            if (!posterName.isEmpty()) {
                const QString candidate = QDir(themeRoot + QStringLiteral("/posters")).filePath(posterName + QLatin1Char('.') + extension);
                if (QFileInfo::exists(candidate)) ownedPaths.append(candidate);
            }
        }

        const QStringList builtInPaths = topLevelExistingPaths(ownedPaths);
        for (const QString &path : builtInPaths)
            installBytes += pathSize(path);
    }

    auto formatInstallFootprint = [](quint64 bytes) {
        if (bytes == 0)
            return QStringLiteral("Unknown");
        // Dashboard app details are easier to compare in one consistent unit.
        // Keep genuinely tiny footprints readable without pretending shared
        // NeutronShell code belongs to every system app.
        if (bytes < 1024)
            return QStringLiteral("%1 B").arg(bytes);
        const double mib = static_cast<double>(bytes) / (1024.0 * 1024.0);
        return QStringLiteral("%1 MB").arg(QString::number(mib, 'f', mib < 10.0 ? 2 : 1));
    };

    auto formatRuntime = [](qint64 seconds) {
        seconds = qMax<qint64>(0, seconds);
        const qint64 days = seconds / 86400;
        seconds %= 86400;
        const qint64 hours = seconds / 3600;
        seconds %= 3600;
        const qint64 minutes = seconds / 60;
        const qint64 secs = seconds % 60;
        if (days > 0)
            return QStringLiteral("%1d %2h %3m").arg(days).arg(hours).arg(minutes);
        if (hours > 0)
            return QStringLiteral("%1h %2m").arg(hours).arg(minutes);
        if (minutes > 0)
            return QStringLiteral("%1m %2s").arg(minutes).arg(secs);
        return QStringLiteral("%1s").arg(secs);
    };

    QVariantMap details = app;
    const QVariantMap cardInfo = appCardInfo(app);
    details.insert(QStringLiteral("ownershipText"),
                   cardInfo.value(QStringLiteral("typeText"), QStringLiteral("Unknown")));
    details.insert(QStringLiteral("ownershipSource"),
                   cardInfo.value(QStringLiteral("ownershipSource"), QStringLiteral("unknown")));
    details.insert(QStringLiteral("installPath"), QDir::cleanPath(installPath));
    details.insert(QStringLiteral("installRoot"), QDir::cleanPath(measuredInstallPath));
    details.insert(QStringLiteral("installBytes"), QVariant::fromValue<qulonglong>(installBytes));
    details.insert(QStringLiteral("installText"), formatInstallFootprint(installBytes));
    if (!installedPackageVersion.isEmpty())
        details.insert(QStringLiteral("version"), installedPackageVersion);
    details.insert(QStringLiteral("storageBytes"), QVariant::fromValue<qulonglong>(storageBytes));
    details.insert(QStringLiteral("storageText"), formatBytes(storageBytes));
    details.insert(QStringLiteral("cacheBytes"), QVariant::fromValue<qulonglong>(cacheBytes));
    details.insert(QStringLiteral("cacheText"), formatBytes(cacheBytes));
    details.insert(QStringLiteral("lastUsedUtc"), m_lastUsedByApp.value(id));
    const QDateTime used = QDateTime::fromString(m_lastUsedByApp.value(id), Qt::ISODate);
    const QString lastUsedText = used.isValid()
        ? used.toLocalTime().toString(QStringLiteral("MMM d, yyyy  h:mm AP"))
        : QStringLiteral("Never opened");
    details.insert(QStringLiteral("lastUsedText"), lastUsedText);

    const bool running = app.value(QStringLiteral("running"), false).toBool();
    const QDateTime launched = m_runtimeLaunchTimes.value(id);
    const QString runtimeText = running
        ? (launched.isValid()
               ? formatRuntime(launched.secsTo(QDateTime::currentDateTimeUtc()))
               : QStringLiteral("Running"))
        : lastUsedText;
    details.insert(QStringLiteral("runtimeText"), runtimeText);
    details.insert(QStringLiteral("runtimeLabel"), running ? QStringLiteral("Runtime") : QStringLiteral("Last ran"));
    details.insert(QStringLiteral("runtimeStartUtc"), launched.isValid() ? launched.toString(Qt::ISODateWithMs) : QString());

    details.insert(QStringLiteral("permissionsText"), permissions.isEmpty()
                   ? QStringLiteral("No declared permissions")
                   : permissions.join(QStringLiteral(", ")));
    details.insert(QStringLiteral("uninstallable"), canUninstallApp(app));
    details.insert(QStringLiteral("cacheClearable"), !cachePaths.isEmpty());
    return details;
}

QVariantMap AppManager::jellyfinBackendState() const
{
    const QString helper = QStringLiteral("/usr/local/sbin/neutronos-jellyfin-backend-helper");

    // Prefer the narrowly-scoped root helper. It can inspect Docker even when
    // the shell user is not a member of the docker group, so the modal reports
    // the real installation state rather than guessing from permission errors.
    if (QFileInfo::exists(helper)) {
        QString out;
        QString err;
        const int code = runProcess(
            QStringLiteral("/usr/bin/sudo"),
            {QStringLiteral("-n"), helper, QStringLiteral("status")},
            7000,
            &out,
            &err
        );
        if (code == 0 && !out.trimmed().isEmpty()) {
            QJsonParseError parseError;
            const QJsonDocument doc = QJsonDocument::fromJson(out.trimmed().toUtf8(), &parseError);
            if (parseError.error == QJsonParseError::NoError && doc.isObject())
                return doc.object().toVariantMap();
        }
    }

    // Fallback for systems where the helper has not been installed yet.
    const QString container = QStringLiteral("jellyfin");
    const QString dockerUnit = QStringLiteral("docker.service");
    const QString serviceUnit = QStringLiteral("jellyfin.service");
    const QString bridgeUnit = QStringLiteral("neutron-jellyfin-bridge.service");

    const bool dockerInstalled = dockerExists();
    const bool dockerServiceExists = systemdUnitExists(dockerUnit);
    const bool dockerRunning = dockerServiceExists && systemdUnitActive(dockerUnit);
    const bool containerExists = dockerRunning && dockerContainerExists(container);
    const bool containerRunning = containerExists && dockerContainerRunning(container);
    const bool serviceExists = systemdUnitExists(serviceUnit);
    const bool serviceRunning = serviceExists && systemdUnitActive(serviceUnit);
    const bool bridgeExists = systemdUnitExists(bridgeUnit);
    const bool bridgeRunning = bridgeExists && systemdUnitActive(bridgeUnit);

    QString backendType = QStringLiteral("none");
    QString backendLabel = QStringLiteral("Not detected");
    QString jellyfinStatus = QStringLiteral("Not detected");

    if (serviceRunning) {
        backendType = QStringLiteral("system");
        backendLabel = QStringLiteral("System service");
        jellyfinStatus = QStringLiteral("Running");
    } else if (containerRunning) {
        backendType = QStringLiteral("docker");
        backendLabel = QStringLiteral("Docker container");
        jellyfinStatus = QStringLiteral("Running");
    } else if (serviceExists) {
        backendType = QStringLiteral("system");
        backendLabel = QStringLiteral("System service");
        jellyfinStatus = QStringLiteral("Stopped");
    } else if (containerExists) {
        backendType = QStringLiteral("docker");
        backendLabel = QStringLiteral("Docker container");
        jellyfinStatus = QStringLiteral("Stopped");
    } else if (dockerInstalled && dockerServiceExists && !dockerRunning) {
        backendType = QStringLiteral("docker-candidate");
        backendLabel = QStringLiteral("Docker available");
        jellyfinStatus = QStringLiteral("Check after Docker starts");
    }

    QVariantMap result;
    result.insert(QStringLiteral("backendType"), backendType);
    result.insert(QStringLiteral("backendLabel"), backendLabel);
    result.insert(QStringLiteral("jellyfinStatus"), jellyfinStatus);
    result.insert(QStringLiteral("dockerInstalled"), dockerInstalled);
    result.insert(QStringLiteral("dockerServiceExists"), dockerServiceExists);
    result.insert(QStringLiteral("dockerRunning"), dockerRunning);
    result.insert(QStringLiteral("dockerStatus"), !dockerInstalled
                  ? QStringLiteral("Not installed")
                  : (dockerRunning ? QStringLiteral("Running") : QStringLiteral("Stopped")));
    result.insert(QStringLiteral("containerExists"), containerExists);
    result.insert(QStringLiteral("containerRunning"), containerRunning);
    result.insert(QStringLiteral("serviceExists"), serviceExists);
    result.insert(QStringLiteral("serviceRunning"), serviceRunning);
    result.insert(QStringLiteral("bridgeExists"), bridgeExists);
    result.insert(QStringLiteral("bridgeRunning"), bridgeRunning);
    result.insert(QStringLiteral("bridgeStatus"), bridgeExists
                  ? (bridgeRunning ? QStringLiteral("Running") : QStringLiteral("Stopped"))
                  : QStringLiteral("Not installed"));
    result.insert(QStringLiteral("backendRunning"), containerRunning || serviceRunning);
    return result;
}

bool AppManager::requestJellyfinBackendRecovery()
{
    const QString helper = QStringLiteral("/usr/local/sbin/neutronos-jellyfin-backend-helper");
    if (!QFileInfo::exists(helper))
        return false;

    // Recovery can take tens of seconds while systemd/Docker/Jellyfin starts.
    // Never run that wait loop on the QML GUI thread.
    return QProcess::startDetached(
        QStringLiteral("/usr/bin/sudo"),
        {QStringLiteral("-n"), helper, QStringLiteral("ensure")}
    );
}

bool AppManager::ensureJellyfinBackendReady()
{
    const QString helper = QStringLiteral("/usr/local/sbin/neutronos-jellyfin-backend-helper");

    if (QFileInfo::exists(helper)) {
        QString out;
        QString err;
        return runProcess(
            QStringLiteral("/usr/bin/sudo"),
            {QStringLiteral("-n"), helper, QStringLiteral("ensure")},
            50000,
            &out,
            &err
        ) == 0;
    }

    // Fallback for an older installation without the scoped helper. This path
    // may depend on host polkit policy; the cumulative installer always adds
    // the helper/sudoers rule before restarting NeutronOS.
    const QString container = QStringLiteral("jellyfin");
    const QString dockerUnit = QStringLiteral("docker.service");
    const QString serviceUnit = QStringLiteral("jellyfin.service");
    const QString bridgeUnit = QStringLiteral("neutron-jellyfin-bridge.service");

    bool serverReady = false;

    if (systemdUnitExists(serviceUnit)) {
        if (systemdUnitActive(serviceUnit)) {
            serverReady = true;
        } else {
            QString message;
            if (runSystemdAction(serviceUnit, QStringLiteral("start"), &message))
                serverReady = waitForSystemdActive(serviceUnit, 15000);
        }
    }

    // A failed/stale native unit must not prevent Docker fallback.
    if (!serverReady && dockerExists() && systemdUnitExists(dockerUnit)) {
        if (!systemdUnitActive(dockerUnit)) {
            QString message;
            if (runSystemdAction(dockerUnit, QStringLiteral("start"), &message))
                waitForSystemdActive(dockerUnit, 15000);
        }
        if (systemdUnitActive(dockerUnit) && dockerContainerExists(container)) {
            if (dockerContainerRunning(container)) {
                serverReady = true;
            } else {
                QString message;
                if (runDockerAction(container, QStringLiteral("start"), &message))
                    serverReady = waitForDockerRunning(container, 15000);
            }
        }
    }

    bool bridgeReady = false;
    if (systemdUnitExists(bridgeUnit)) {
        if (systemdUnitActive(bridgeUnit)) {
            bridgeReady = true;
        } else {
            QString message;
            if (runSystemdAction(bridgeUnit, QStringLiteral("start"), &message))
                bridgeReady = waitForSystemdActive(bridgeUnit, 10000);
        }
    }

    return serverReady || bridgeReady;
}

/*
    ============================================================
                            PROCESS HELPER
    ============================================================
*/

int AppManager::runProcess(
    const QString &program,
    const QStringList &arguments,
    int timeoutMs,
    QString *standardOutput,
    QString *standardError
) const {
    QProcess process;

    process.start(program, arguments);

    if (!process.waitForStarted(700)) {
        if (standardOutput)
            *standardOutput = QString();

        if (standardError)
            *standardError = QStringLiteral("Failed to start process: ") + program;

        return -127;
    }

    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(500);

        if (standardOutput)
            *standardOutput = QString::fromUtf8(process.readAllStandardOutput());

        if (standardError)
            *standardError = QString::fromUtf8(process.readAllStandardError());

        return -124;
    }

    if (standardOutput)
        *standardOutput = QString::fromUtf8(process.readAllStandardOutput());

    if (standardError)
        *standardError = QString::fromUtf8(process.readAllStandardError());

    return process.exitCode();
}

/*
    ============================================================
                            PUBLIC API
    ============================================================
*/

void AppManager::reloadApps()
{
    discoverAppsOnce();
}

void AppManager::rediscoverApps()
{
    discoverAppsOnce();
}

void AppManager::refreshStatuses()
{
    m_runtimeStatusQueriesEnabled = true;
    refreshStatusesOnce();
}

void AppManager::setBrowserManager(BrowserManager *browserManager)
{
    m_browserManager = browserManager;
    if (!m_browserManager)
        return;
    connect(m_browserManager, &BrowserManager::runtimeChanged, this, [this]() {
        updateAppStatus(QStringLiteral("browser"), m_browserManager->runtimeActive());
        rebuildRunningApps();
    });
    rebuildRunningApps();
}

bool AppManager::launchExternalRuntime(const QVariantMap &appData)
{
    const QVariantMap app = normalizeApp(appData);
    const QString id = app.value(QStringLiteral("id")).toString();
    if (id != QStringLiteral("browser") || !m_browserManager) {
        emit appActionFinished(id, QStringLiteral("launch-runtime"), false,
                               QStringLiteral("No managed external runtime is registered"));
        return false;
    }
    const bool launched = m_browserManager->launchBrowser();
    updateAppStatus(id, launched || m_browserManager->runtimeActive());
    emit appActionFinished(id, QStringLiteral("launch-runtime"), launched,
                           m_browserManager->lastMessage());
    return launched;
}

bool AppManager::focusApp(const QVariantMap &appData)
{
    const QString id = normalizeApp(appData).value(QStringLiteral("id")).toString();
    if (id == QStringLiteral("browser") && m_browserManager) {
        m_browserManager->refreshRuntime();
        return m_browserManager->runtimeActive();
    }
    return !id.isEmpty();
}

bool AppManager::suspendApp(const QVariantMap &appData)
{
    const QString id = normalizeApp(appData).value(QStringLiteral("id")).toString();
    // Browser owns the display while active and does not currently support a
    // safe suspend primitive. Report that honestly instead of killing it.
    return id != QStringLiteral("browser") && !id.isEmpty();
}

bool AppManager::resumeApp(const QVariantMap &appData)
{
    return focusApp(appData);
}

QVariantMap AppManager::runtimeState(const QString &appId) const
{
    const QString id = safeId(appId);
    if (id == QStringLiteral("browser") && m_browserManager)
        return m_browserManager->runtimeState();
    const QVariantMap app = appById(id);
    return {{QStringLiteral("appId"), id},
            {QStringLiteral("active"), app.value(QStringLiteral("running"), false)},
            {QStringLiteral("phase"), app.value(QStringLiteral("running"), false).toBool()
                 ? QStringLiteral("active") : QStringLiteral("idle")}};
}

QVariantMap AppManager::consumeExternalReturnSession()
{
    if (!m_browserManager)
        return {};
    QVariantMap result = m_browserManager->consumeReturnSession();
    if (!result.isEmpty()) {
        result.insert(QStringLiteral("appId"), QStringLiteral("browser"));
        result.insert(QStringLiteral("appName"), QStringLiteral("Browser"));
        appClosed(QStringLiteral("browser"));
    }
    return result;
}

QVariantMap AppManager::runningEntry(const QString &runtimeId) const
{
    for (const QVariant &value : m_runningApps) {
        const QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("runtimeId")).toString() == runtimeId)
            return entry;
    }
    return {};
}

bool AppManager::focusRuntime(const QString &runtimeId)
{
    const QVariantMap entry = runningEntry(runtimeId);
    if (entry.isEmpty() || !entry.value(QStringLiteral("canFocus")).toBool())
        return false;
    const QString appId = entry.value(QStringLiteral("appId")).toString();
    if (entry.value(QStringLiteral("isBrowserTab")).toBool()) {
        if (!m_browserManager || !m_browserManager->requestTabFocus(entry.value(QStringLiteral("tabIndex")).toInt()))
            return false;
    } else if (appId == QStringLiteral("browser") && m_browserManager) {
        if (!m_browserManager->requestRuntimeFocus())
            return false;
    }
    const QVariantMap app = appById(appId);
    if (app.isEmpty())
        return false;
    emit runtimeFocusRequested(app);
    return true;
}

bool AppManager::closeRuntime(const QString &runtimeId)
{
    const QVariantMap entry = runningEntry(runtimeId);
    if (entry.isEmpty() || !entry.value(QStringLiteral("canClose")).toBool())
        return false;
    if (entry.value(QStringLiteral("isBrowserTab")).toBool())
        return m_browserManager && m_browserManager->requestTabClose(entry.value(QStringLiteral("tabIndex")).toInt());
    const QString appId = entry.value(QStringLiteral("appId")).toString();
    if (appId == QStringLiteral("browser") && m_browserManager)
        return m_browserManager->requestRuntimeClose();
    return closeApp(appById(appId));
}

void AppManager::rebuildRunningApps()
{
    QVariantList next;
    QSet<QString> seen;
    auto appendApp = [this, &next, &seen](const QVariantMap &app, const QString &state) {
        const QString appId = app.value(QStringLiteral("id")).toString();
        if (appId.isEmpty() || seen.contains(appId))
            return;
        seen.insert(appId);
        if (!m_runtimeLaunchTimes.contains(appId))
            m_runtimeLaunchTimes.insert(appId, QDateTime::currentDateTimeUtc());
        QVariantMap runtime;
        runtime.insert(QStringLiteral("runtimeId"), QStringLiteral("app:") + appId);
        runtime.insert(QStringLiteral("appId"), appId);
        runtime.insert(QStringLiteral("displayName"), app.value(QStringLiteral("name"), appId));
        // Installed applications may keep artwork in their owned payload,
        // outside the OS theme directory. Propagate the resolved asset URL.
        QString iconSource = app.value(QStringLiteral("iconSource")).toString();
        const QString iconName = app.value(QStringLiteral("icon")).toString();
        if (iconSource.isEmpty() && !iconName.isEmpty() &&
            !iconName.contains(QLatin1Char('/')) && !iconName.contains(QLatin1Char(':'))) {
            const QString asset = QDir(HumanHome::appStateRoot()).filePath(
                QStringLiteral("apps/payload/themes/Default/apps/icons/") + iconName + QStringLiteral(".png"));
            if (QFileInfo::exists(asset)) iconSource = QUrl::fromLocalFile(asset).toString();
        }
        runtime.insert(QStringLiteral("icon"), iconSource.isEmpty() ? app.value(QStringLiteral("icon")) : QVariant(iconSource));
        runtime.insert(QStringLiteral("iconSource"), iconSource);
        runtime.insert(QStringLiteral("poster"), app.value(QStringLiteral("poster")));
        runtime.insert(QStringLiteral("runtimeType"), app.value(QStringLiteral("type"), QStringLiteral("qml")));
        runtime.insert(QStringLiteral("state"), state);
        runtime.insert(QStringLiteral("running"), state == QStringLiteral("active"));
        runtime.insert(QStringLiteral("active"), state == QStringLiteral("active"));
        runtime.insert(QStringLiteral("suspended"), state == QStringLiteral("suspended"));
        runtime.insert(QStringLiteral("focused"), state == QStringLiteral("active"));
        runtime.insert(QStringLiteral("launchTime"), m_runtimeLaunchTimes.value(appId).toString(Qt::ISODateWithMs));
        runtime.insert(QStringLiteral("canClose"), true);
        runtime.insert(QStringLiteral("canFocus"), true);
        runtime.insert(QStringLiteral("isBrowserTab"), false);
        runtime.insert(QStringLiteral("isolationState"), app.value(QStringLiteral("isolationState"), QStringLiteral("standard")));
        next.append(runtime);
    };

    for (const QVariant &value : m_apps) {
        const QVariantMap app = value.toMap();
        const QString id = app.value(QStringLiteral("id")).toString();

        if (m_backgroundApps.contains(id)) {
            appendApp(app, QStringLiteral("suspended"));
        } else if (
            app.value(
                QStringLiteral("appRunning"),
                app.value(QStringLiteral("uiRunning")))
                .toBool()) {
            appendApp(app, QStringLiteral("active"));
        }
    }

    if (m_browserManager && m_browserManager->runtimeActive()) {
        const QVariantMap browser = appById(QStringLiteral("browser"));
        appendApp(browser, QStringLiteral("active"));
        const QVariantList tabs = m_browserManager->runtimeTabs();
        for (int index = 0; index < tabs.size(); ++index) {
            const QVariantMap tab = tabs.at(index).toMap();
            const bool privateMode = tab.value(QStringLiteral("privateMode")).toBool();
            const QUrl url = QUrl::fromUserInput(tab.value(QStringLiteral("url")).toString());
            QVariantMap child;
            child.insert(QStringLiteral("runtimeId"), QStringLiteral("browser:tab:%1").arg(index));
            child.insert(QStringLiteral("appId"), QStringLiteral("browser"));
            child.insert(QStringLiteral("displayName"), privateMode ? QStringLiteral("Private Tab")
                         : tab.value(QStringLiteral("title"), QStringLiteral("Browser Tab")));
            child.insert(QStringLiteral("subtitle"), privateMode ? QStringLiteral("Private browsing") : url.host());
            child.insert(QStringLiteral("icon"), privateMode ? QVariant() : tab.value(QStringLiteral("favicon")));
            child.insert(QStringLiteral("runtimeType"), QStringLiteral("browser-tab"));
            child.insert(QStringLiteral("state"), index == m_browserManager->runtimeActiveTab()
                         ? QStringLiteral("active") : QStringLiteral("background"));
            child.insert(QStringLiteral("active"), index == m_browserManager->runtimeActiveTab());
            child.insert(QStringLiteral("focused"), index == m_browserManager->runtimeActiveTab());
            child.insert(QStringLiteral("canClose"), tabs.size() > 1);
            child.insert(QStringLiteral("canFocus"), true);
            child.insert(QStringLiteral("isBrowserTab"), true);
            child.insert(QStringLiteral("parentRuntimeId"), QStringLiteral("app:browser"));
            child.insert(QStringLiteral("tabIndex"), index);
            child.insert(QStringLiteral("launchTime"), m_runtimeLaunchTimes.value(QStringLiteral("browser")).toString(Qt::ISODateWithMs));
            child.insert(QStringLiteral("isolationState"), QStringLiteral("isolated"));
            next.append(child);
        }
    }
    if (m_runningApps == next)
        return;
    m_runningApps = next;
    emit runningAppsChanged();
}

QVariantMap AppManager::appById(const QString &appId) const
{
    QString cleanId = safeId(appId);
    if (cleanId == QStringLiteral("vidoptimizer"))
        cleanId = QStringLiteral("mediaoptimizer");

    for (const QVariant &item : m_apps) {
        const QVariantMap app = item.toMap();

        if (app.value(QStringLiteral("id")).toString() == cleanId)
            return app;
    }

    return {};
}

QVariantMap AppManager::appAt(int index) const
{
    if (index < 0 || index >= m_apps.size())
        return {};

    return m_apps.at(index).toMap();
}

bool AppManager::hasApp(const QString &appId) const
{
    return !appById(appId).isEmpty();
}

bool AppManager::hasQmlEntry(const QVariantMap &appData) const
{
    return qmlEntryExists(normalizeApp(appData));
}

QString AppManager::resolveQmlEntry(const QVariantMap &appData) const
{
    return resolveQmlEntryPath(normalizeApp(appData));
}

void AppManager::startApp(const QVariantMap &appData)
{
    m_runtimeStatusQueriesEnabled = true;
    executeAppAction(appData, QStringLiteral("start"));
}

void AppManager::stopApp(const QVariantMap &appData)
{
    m_runtimeStatusQueriesEnabled = true;
    executeAppAction(appData, QStringLiteral("stop"));
}

void AppManager::restartApp(const QVariantMap &appData)
{
    m_runtimeStatusQueriesEnabled = true;
    executeAppAction(appData, QStringLiteral("restart"));
}


bool AppManager::prepareAppForLaunch(const QVariantMap &appData)
{
    m_runtimeStatusQueriesEnabled = true;
    const QVariantMap app = normalizeApp(appData);
    const QString id = app.value(QStringLiteral("id")).toString();

    if (id.isEmpty()) {
        emit appActionFinished(id, QStringLiteral("prepare-launch"), false, QStringLiteral("Missing app id"));
        return false;
    }

    QString message;
    const bool ready = ensureBackendReady(app, &message);
    refreshStatusesOnce();
    emit appActionFinished(id, QStringLiteral("prepare-launch"), ready, message);
    return ready;
}

bool AppManager::launchApp(const QVariantMap &appData)
{
    m_runtimeStatusQueriesEnabled = true;
    const QVariantMap app = normalizeApp(appData);
    const QString id = app.value(QStringLiteral("id")).toString();
    const QString type = app.value(QStringLiteral("type")).toString();

    if (id.isEmpty()) {
        emit appActionFinished(id, QStringLiteral("launch"), false, QStringLiteral("Missing app id"));
        return false;
    }

    QString backendMessage;
    if (!ensureBackendReady(app, &backendMessage)) {
        emit appActionFinished(id, QStringLiteral("launch"), false, backendMessage);
        return false;
    }

    if (type == QStringLiteral("qml")) {
        if (!qmlEntryExists(app)) {
            const QString message = QStringLiteral("QML entry missing: ") + resolveQmlEntryPath(app);
            emit appActionFinished(id, QStringLiteral("launch"), false, message);
            return false;
        }

        recordAppUsed(id);
        updateAppStatus(id, true);
        emit appActionFinished(id, QStringLiteral("launch"), true, QStringLiteral("AppHost launch requested"));
        return true;
    }

    if (type == QStringLiteral("web") || type == QStringLiteral("service-web")) {
        recordAppUsed(id);
        updateAppStatus(id, true);
        emit appActionFinished(id, QStringLiteral("launch"), true, QStringLiteral("Web/service app launch requested"));
        return true;
    }

    const QString command = app.value(QStringLiteral("command")).toString().trimmed();

    if (type == QStringLiteral("external") || type == QStringLiteral("command")) {
        QString program;
        QStringList arguments;

        if (!command.isEmpty()) {
            program = QStringLiteral("/bin/sh");
            arguments << QStringLiteral("-lc") << command;
        } else {
            QString entry = app.value(QStringLiteral("entry")).toString().trimmed();

            if (entry.startsWith(QStringLiteral("file://")))
                entry = QUrl(entry).toLocalFile();

            const QFileInfo entryInfo(entry);
            const QString suffix = entryInfo.suffix().toLower();

            if (!entryInfo.exists() || !entryInfo.isFile()) {
                emit appActionFinished(id, QStringLiteral("launch"), false, QStringLiteral("Missing executable/script entry"));
                return false;
            }

            if (suffix == QStringLiteral("py")) {
                program = QStringLiteral("/usr/bin/python3");
                arguments << entryInfo.absoluteFilePath();
            } else if (suffix == QStringLiteral("sh")) {
                program = QStringLiteral("/bin/sh");
                arguments << entryInfo.absoluteFilePath();
            } else if (entryInfo.isExecutable()) {
                program = entryInfo.absoluteFilePath();
            } else {
                emit appActionFinished(id, QStringLiteral("launch"), false, QStringLiteral("Entry is not executable"));
                return false;
            }
        }

        const bool started = QProcess::startDetached(program, arguments);

        if (started) {
            recordAppUsed(id);
            updateAppStatus(id, true);
        }

        emit appActionFinished(
            id,
            QStringLiteral("launch"),
            started,
            started ? QStringLiteral("External app started") : QStringLiteral("Failed to start external app")
        );

        return started;
    }

    recordAppUsed(id);
    updateAppStatus(id, true);
    emit appActionFinished(id, QStringLiteral("launch"), true, QStringLiteral("App marked open"));
    return true;
}

bool AppManager::openApp(const QVariantMap &appData)
{
    return launchApp(appData);
}

bool AppManager::closeApp(const QVariantMap &appData)
{
    const QVariantMap app = normalizeApp(appData);
    const QString id = app.value(QStringLiteral("id")).toString();

    if (id.isEmpty()) {
        emit appActionFinished(id, QStringLiteral("close"), false, QStringLiteral("Missing app id"));
        return false;
    }

    updateAppStatus(id, false);
    emit appActionFinished(id, QStringLiteral("close"), true, QStringLiteral("App marked closed"));
    return true;
}

bool AppManager::runAppAction(const QVariantMap &appData, const QString &actionName)
{
    return executeAppAction(appData, actionName);
}

bool AppManager::serviceAction(const QVariantMap &appData, const QString &actionName)
{
    return executeAppAction(appData, actionName);
}


bool AppManager::setFavorite(const QString &appId, bool favorite)
{
    const QString id = safeId(appId);

    if (id.isEmpty())
        return false;

    bool found = false;

    for (int index = 0; index < m_apps.size(); ++index) {
        QVariantMap app = m_apps.at(index).toMap();

        if (app.value(QStringLiteral("id")).toString() != id)
            continue;

        app[QStringLiteral("favorite")] = favorite;
        m_apps[index] = app;
        found = true;
        break;
    }

    if (!found)
        return false;

    m_favoriteOverrides.insert(id, favorite);
    m_favoriteOrder.removeAll(id);

    if (favorite)
        m_favoriteOrder.append(id);

    if (!saveCarouselState())
        qWarning() << "Unable to persist favorite state for" << id;

    rebuildDerivedLists();
    emit appsChanged();
    return true;
}

bool AppManager::makeFavoriteFirst(const QString &appId)
{
    const QString id = safeId(appId);

    if (id.isEmpty())
        return false;

    bool found = false;

    for (int index = 0; index < m_apps.size(); ++index) {
        QVariantMap app = m_apps.at(index).toMap();

        if (app.value(QStringLiteral("id")).toString() != id)
            continue;

        app[QStringLiteral("favorite")] = true;
        m_apps[index] = app;
        found = true;
        break;
    }

    if (!found)
        return false;

    m_favoriteOverrides.insert(id, true);
    m_favoriteOrder.removeAll(id);
    m_favoriteOrder.prepend(id);

    if (!saveCarouselState())
        qWarning() << "Unable to persist first favorite" << id;

    rebuildDerivedLists();
    emit appsChanged();
    return true;
}

bool AppManager::moveFavorite(const QString &appId, int targetIndex)
{
    const QString id = safeId(appId);

    if (id.isEmpty())
        return false;

    QStringList currentOrder;

    for (const QVariant &item : m_favoriteApps) {
        const QString favoriteId =
            item.toMap().value(QStringLiteral("id")).toString();

        if (!favoriteId.isEmpty())
            currentOrder.append(favoriteId);
    }

    const int currentIndex = currentOrder.indexOf(id);

    if (currentIndex < 0)
        return false;

    targetIndex = qBound(
        0,
        targetIndex,
        qMax(0, currentOrder.size() - 1)
    );

    if (targetIndex == currentIndex)
        return true;

    currentOrder.move(currentIndex, targetIndex);
    m_favoriteOrder = currentOrder;

    if (!saveCarouselState()) {
        qWarning() << "Unable to persist carousel order";
        return false;
    }

    rebuildDerivedLists();
    emit appsChanged();
    return true;
}

bool AppManager::moveFavoriteBy(const QString &appId, int delta)
{
    const QString id = safeId(appId);
    QStringList currentOrder;

    for (const QVariant &item : m_favoriteApps) {
        const QString favoriteId =
            item.toMap().value(QStringLiteral("id")).toString();

        if (!favoriteId.isEmpty())
            currentOrder.append(favoriteId);
    }

    const int currentIndex = currentOrder.indexOf(id);

    if (currentIndex < 0)
        return false;

    return moveFavorite(
        id,
        qBound(
            0,
            currentIndex + delta,
            qMax(0, currentOrder.size() - 1)
        )
    );
}

bool AppManager::canUninstallApp(const QVariantMap &appData) const
{
    const QVariantMap app = normalizeApp(appData);
    const QString id = safeId(app.value(QStringLiteral("id")).toString());

    if (id.isEmpty())
        return false;

    if (app.contains(QStringLiteral("uninstallable")) &&
            !app.value(QStringLiteral("uninstallable")).toBool()) {
        return false;
    }

    const QString category =
        app.value(QStringLiteral("category")).toString().trimmed().toLower();
    const bool systemApp =
        app.value(QStringLiteral("systemOnly"), false).toBool() ||
        category == QStringLiteral("system");

    if (systemApp)
        return false;

    if (m_managedPackageIds.contains(id))
        return true;

    auto resolvedPath = [](const QString &rawPath) -> QString {
        QString path = rawPath.trimmed();

        if (path.startsWith(QStringLiteral("file://")))
            path = QUrl(path).toLocalFile();

        if (path.isEmpty())
            return QString();

        QFileInfo info(path);
        const QString canonical = info.canonicalFilePath();

        return QDir::cleanPath(canonical.isEmpty()
                               ? info.absoluteFilePath()
                               : canonical);
    };

    auto isInside = [&resolvedPath](const QString &candidate,
                                    const QString &root) -> bool {
        const QString child = resolvedPath(candidate);
        const QString base = resolvedPath(root);

        if (child.isEmpty() || base.isEmpty() || child == base)
            return false;

        return child.startsWith(base + QDir::separator());
    };

    QStringList managedRoots = neutronAppSearchPaths();
    managedRoots.append(configAppSearchPaths());
    managedRoots << HumanHome::appStateRoot() +
        QStringLiteral("/apps/payload");
    managedRoots << QStringLiteral("/var/lib/neutronos/apps");
    managedRoots << HumanHome::browsePath() + QStringLiteral("/.local/share/applications");
    managedRoots << HumanHome::browsePath() + QStringLiteral("/apps");

    QStringList candidates;
    candidates << app.value(QStringLiteral("appDir")).toString();
    candidates << app.value(QStringLiteral("configPath")).toString();
    candidates << app.value(QStringLiteral("desktopFile")).toString();

    for (const QString &candidate : candidates) {
        if (candidate.trimmed().isEmpty())
            continue;

        for (const QString &root : managedRoots) {
            if (isInside(candidate, root))
                return true;
        }
    }

    return false;
}

bool AppManager::uninstallApp(const QVariantMap &appData)
{
    const QVariantMap app = normalizeApp(appData);
    const QString id = safeId(app.value(QStringLiteral("id")).toString());

    if (id.isEmpty()) {
        emit appActionFinished(id, QStringLiteral("uninstall"), false, QStringLiteral("Missing app id"));
        return false;
    }

    if (!highPriorityAuthorizedForSettings()) {
        emit appActionFinished(
            id, QStringLiteral("uninstall"), false,
            QStringLiteral("Login password authorization is required while Automatic Login is enabled")
        );
        return false;
    }

    if (!canUninstallApp(app)) {
        emit appActionFinished(
            id,
            QStringLiteral("uninstall"),
            false,
            QStringLiteral("This app is protected or is not owned by NeutronOS")
        );
        return false;
    }

    const QString uninstallCommand =
        app.value(QStringLiteral("uninstallCommand")).toString().trimmed();

    if (!uninstallCommand.isEmpty()) {
        QString output;
        QString error;
        const int rc = runProcess(
            QStringLiteral("/bin/sh"),
            QStringList() << QStringLiteral("-lc") << uninstallCommand,
            30000,
            &output,
            &error
        );

        if (rc != 0) {
            emit appActionFinished(
                id,
                QStringLiteral("uninstall"),
                false,
                error.trimmed().isEmpty()
                    ? QStringLiteral("App uninstall command failed")
                    : error.trimmed()
            );
            return false;
        }
    }

    const QString docker = app.value(QStringLiteral("docker")).toString().trimmed();
    const QString service = app.value(QStringLiteral("service")).toString().trimmed();

    if (!docker.isEmpty() || !service.isEmpty()) {
        QString stopMessage;

        if (!docker.isEmpty() && commandExists(QStringLiteral("docker")))
            runDockerAction(docker, QStringLiteral("stop"), &stopMessage);
        else if (!service.isEmpty())
            runSystemdAction(service, QStringLiteral("stop"), &stopMessage);
    }

    auto resolvedPath = [](const QString &rawPath) -> QString {
        QString path = rawPath.trimmed();

        if (path.startsWith(QStringLiteral("file://")))
            path = QUrl(path).toLocalFile();

        if (path.isEmpty())
            return QString();

        QFileInfo info(path);
        const QString canonical = info.canonicalFilePath();

        return QDir::cleanPath(canonical.isEmpty()
                               ? info.absoluteFilePath()
                               : canonical);
    };

    auto isInside = [&resolvedPath](const QString &candidate,
                                    const QString &root) -> bool {
        const QString child = resolvedPath(candidate);
        const QString base = resolvedPath(root);

        if (child.isEmpty() || base.isEmpty() || child == base)
            return false;

        return child.startsWith(base + QDir::separator());
    };

    QStringList managedRoots = neutronAppSearchPaths();
    managedRoots.append(configAppSearchPaths());

    const QString appStorePayload = HumanHome::appStateRoot() +
        QStringLiteral("/apps/payload");
    const QString iconsRoot =
        appStorePayload + QStringLiteral("/themes/Default/apps/icons");
    const QString postersRoot =
        appStorePayload + QStringLiteral("/themes/Default/apps/posters");

    managedRoots << iconsRoot;
    managedRoots << postersRoot;
    managedRoots << QStringLiteral("/var/lib/neutronos/apps");
    managedRoots << HumanHome::browsePath() + QStringLiteral("/.local/share/applications");
    managedRoots << HumanHome::browsePath() + QStringLiteral("/apps");

    QStringList targets;
    targets << app.value(QStringLiteral("appDir")).toString();
    targets << app.value(QStringLiteral("configPath")).toString();
    targets << app.value(QStringLiteral("desktopFile")).toString();
    targets << QStringLiteral("/var/lib/neutronos/apps/") + id;
    targets << HumanHome::browsePath() + QStringLiteral("/apps/") + id;

    const QVariant ownedFilesValue = app.value(QStringLiteral("ownedFiles"));

    for (const QVariant &owned : ownedFilesValue.toList())
        targets << owned.toString();

    const QStringList assetExtensions = {
        QStringLiteral("png"),
        QStringLiteral("jpg"),
        QStringLiteral("jpeg"),
        QStringLiteral("webp"),
        QStringLiteral("svg")
    };

    for (const QString &extension : assetExtensions) {
        targets << iconsRoot + QLatin1Char('/') + id + QLatin1Char('.') + extension;
        targets << postersRoot + QLatin1Char('/') + id + QLatin1Char('.') + extension;
    }

    QStringList approvedTargets;

    for (const QString &rawTarget : targets) {
        const QString target = resolvedPath(rawTarget);

        if (target.isEmpty() || approvedTargets.contains(target))
            continue;

        bool approved = false;

        for (const QString &root : managedRoots) {
            if (isInside(target, root)) {
                approved = true;
                break;
            }
        }

        if (approved)
            approvedTargets.append(target);
    }

    std::sort(
        approvedTargets.begin(),
        approvedTargets.end(),
        [](const QString &left, const QString &right) {
            return left.length() > right.length();
        }
    );

    bool removedAnything = false;
    QStringList failures;

    for (const QString &target : approvedTargets) {
        const QFileInfo info(target);

        if (!info.exists() && !info.isSymLink())
            continue;

        bool removed = false;

        if (info.isDir() && !info.isSymLink())
            removed = QDir(target).removeRecursively();
        else
            removed = QFile::remove(target);

        if (removed)
            removedAnything = true;
        else
            failures.append(target);
    }

    if (!failures.isEmpty()) {
        emit appActionFinished(
            id,
            QStringLiteral("uninstall"),
            false,
            QStringLiteral("Unable to remove: ") + failures.join(QStringLiteral(", "))
        );
        return false;
    }

    if (!removedAnything) {
        emit appActionFinished(
            id,
            QStringLiteral("uninstall"),
            false,
            QStringLiteral("No NeutronOS-owned app files were found")
        );
        return false;
    }

    m_favoriteOverrides.remove(id);
    m_favoriteOrder.removeAll(id);
    for (int slot = 0; slot < m_pinnedApps.size(); ++slot) {
        if (m_pinnedApps.at(slot) == id)
            m_pinnedApps[slot].clear();
    }
    saveCarouselState();
    discoverAppsOnce();

    emit appActionFinished(
        id,
        QStringLiteral("uninstall"),
        true,
        QStringLiteral("App and NeutronOS-owned files removed")
    );

    return true;
}

bool AppManager::executeAppAction(const QVariantMap &appData, const QString &actionName)
{
    const QVariantMap app = normalizeApp(appData);

    const QString id = app.value(QStringLiteral("id")).toString();
    const QString action = actionName.trimmed().toLower();

    if (id.isEmpty() || action.isEmpty()) {
        emit appActionFinished(id, action, false, QStringLiteral("Missing app/action data"));
        return false;
    }

    if (action == QStringLiteral("open") || action == QStringLiteral("launch"))
        return launchApp(app);

    if (action == QStringLiteral("close"))
        return closeApp(app);

    const QString docker = app.value(QStringLiteral("docker")).toString().trimmed();
    const QString service = app.value(QStringLiteral("service")).toString().trimmed();
    const QString backendAction = action == QStringLiteral("exit")
                                  ? QStringLiteral("stop")
                                  : action;

    QString message;
    bool success = false;

    if (!docker.isEmpty() && dockerContainerExists(docker)) {
        success = runDockerAction(docker, backendAction, &message);
        refreshStatusesOnce();
        emit appActionFinished(id, action, success, message);
        return success;
    }

    if (!service.isEmpty() && systemdUnitExists(service)) {
        success = runSystemdAction(service, backendAction, &message);
        refreshStatusesOnce();
        emit appActionFinished(id, action, success, message);
        return success;
    }

    if (action == QStringLiteral("start")) {
        updateAppStatus(id, true);
        emit appActionFinished(id, action, true, QStringLiteral("App marked started"));
        return true;
    }

    if (action == QStringLiteral("stop")) {
        updateAppStatus(id, false);
        emit appActionFinished(id, action, true, QStringLiteral("App marked stopped"));
        return true;
    }

    if (action == QStringLiteral("kill")) {
        updateAppStatus(id, false);
        emit appActionFinished(id, action, true, QStringLiteral("App session force-stopped"));
        return true;
    }

    if (action == QStringLiteral("restart")) {
        updateAppStatus(id, false);
        updateAppStatus(id, true);
        emit appActionFinished(id, action, true, QStringLiteral("App session restarted"));
        return true;
    }

    if (action == QStringLiteral("logs")) {
        emit appActionFinished(id, action, true, QStringLiteral("Logs should be opened through the Logs app"));
        return true;
    }

    message = QStringLiteral("No service backend available for action: ") + action;
    emit appActionFinished(id, action, false, message);
    return false;
}

void AppManager::appLaunched(const QString &appId)
{
    const QString cleanId = safeId(appId);
    m_backgroundApps.remove(cleanId);
    m_runtimeLaunchTimes.insert(cleanId, QDateTime::currentDateTimeUtc());
    recordAppUsed(cleanId);
    updateAppStatus(cleanId, true);
    rebuildRunningApps();
}

void AppManager::appClosed(const QString &appId)
{
    const QString cleanId = safeId(appId);
    m_backgroundApps.remove(cleanId);
    m_runtimeLaunchTimes.remove(cleanId);
    updateAppStatus(cleanId, false);
    rebuildRunningApps();
}

void AppManager::appBackgrounded(const QString &appId)
{
    const QString cleanId = safeId(appId);
    if (cleanId.isEmpty())
        return;
    m_backgroundApps.insert(cleanId);
    updateAppStatus(cleanId, false);
    rebuildRunningApps();
}

/*
    ============================================================
                            DISCOVERY
    ============================================================
*/

void AppManager::discoverAppsOnce()
{
    loadManagedPackageIds();
    m_apps.clear();
    m_favoriteApps.clear();
    m_hiddenApps.clear();
    m_seenAppIds.clear();

    /*
        Built-ins are registered first so core apps keep their intended
        favorite/priority metadata. Unknown drop-in folders are then added
        without a rebuild.
    */
    discoverBuiltInApps();
    discoverNeutronApps();
    discoverExternalNeutronAppDirs();
    discoverConfigApps();
    discoverDesktopApps();

    std::sort(m_apps.begin(), m_apps.end(), [](const QVariant &a, const QVariant &b) {
        const QVariantMap appA = a.toMap();
        const QVariantMap appB = b.toMap();

        const int pA = appA.value(QStringLiteral("priority"), 999).toInt();
        const int pB = appB.value(QStringLiteral("priority"), 999).toInt();

        if (pA == pB) {
            return appA.value(QStringLiteral("name")).toString().toLower() <
                   appB.value(QStringLiteral("name")).toString().toLower();
        }

        return pA < pB;
    });

    if (m_runtimeStatusQueriesEnabled)
        refreshStatusesOnce();
    else {
        rebuildDerivedLists();
        emit appsChanged();
    }
}

void AppManager::refreshStatusesOnce()
{
    QVariantList updated;

    for (const QVariant &item : m_apps)
        updated.append(withLiveStatus(item.toMap()));

    m_apps = updated;
    rebuildDerivedLists();

    emit appsChanged();
}

QString AppManager::neutronRootPath() const
{
    const QByteArray envRoot = qgetenv("NEUTRONOS_ROOT");

    if (!envRoot.isEmpty()) {
        const QString path = QDir::cleanPath(QString::fromLocal8Bit(envRoot));

        if (QFileInfo::exists(path))
            return path;
    }

    const QString echoRoot = QStringLiteral("/opt/neutronos");

    if (QFileInfo::exists(echoRoot))
        return echoRoot;

    const QString homeRoot = QStringLiteral("/opt/neutronos");

    if (QFileInfo::exists(homeRoot))
        return homeRoot;

    const QString currentRoot = QDir::cleanPath(QDir::currentPath());

    if (QFileInfo::exists(currentRoot + QStringLiteral("/qml/Main.qml")))
        return currentRoot;

    return homeRoot;
}

QString AppManager::appsRootPath() const
{
    return neutronRootPath() + QStringLiteral("/qml/apps");
}

QStringList AppManager::neutronAppSearchPaths() const
{
    QStringList paths;
    const QString stateRoot = HumanHome::appStateRoot();

    /*
        App Store payload is the authoritative runtime copy for managed apps.
        It must be discovered before any legacy/source-tree copy with the same
        package id; addApp() intentionally keeps the first installed match.
        Without this ordering an old ~/NeutronOS/qml/apps/<id> tree can mask a
        newer signed .Napp forever, even though the App Store registry and
        payload were updated successfully.
    */
    paths << stateRoot + QStringLiteral("/apps/payload/qml/apps");
    paths << appsRootPath();
    paths << neutronRootPath() + QStringLiteral("/apps");
    paths << QStringLiteral("/var/lib/neutronos/apps");

    return paths;
}

QStringList AppManager::configAppSearchPaths() const
{
    QStringList paths;
    const QString stateRoot = HumanHome::appStateRoot();

    paths << stateRoot + QStringLiteral("/apps/payload/config/apps");
    paths << neutronRootPath() + QStringLiteral("/config/apps");

    return paths;
}

void AppManager::discoverNeutronApps()
{
    for (const QString &rootPath : neutronAppSearchPaths()) {
        QDir root(rootPath);

        if (!root.exists())
            continue;

        const QFileInfoList dirs = root.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);

        for (const QFileInfo &dirInfo : dirs) {
            const QString appDir = dirInfo.absoluteFilePath();
            const QString manifestPath = appDir + QStringLiteral("/app.json");
            const QString mainPath = appDir + QStringLiteral("/Main.qml");

            QVariantMap app;

            if (QFileInfo::exists(manifestPath)) {
                app = readNeutronManifest(manifestPath);
            } else if (QFileInfo::exists(mainPath)) {
                const QString id = safeId(dirInfo.fileName());

                app[QStringLiteral("id")] = id;
                app[QStringLiteral("name")] = displayNameFromId(id);
                app[QStringLiteral("subtitle")] = QStringLiteral("NeutronOS App");
                app[QStringLiteral("description")] = QStringLiteral("Drop-in NeutronOS QML app.");
                app[QStringLiteral("type")] = QStringLiteral("qml");
                app[QStringLiteral("qmlSource")] = dirInfo.fileName() + QStringLiteral("/Main.qml");
                app[QStringLiteral("entry")] = mainPath;
                app[QStringLiteral("source")] = QStringLiteral("neutron");
                app[QStringLiteral("category")] = QStringLiteral("Apps");
                app[QStringLiteral("icon")] = id;
                app[QStringLiteral("poster")] = id;
                app[QStringLiteral("favorite")] = false;
                app[QStringLiteral("hidden")] = false;
                app[QStringLiteral("priority")] = 300;
                app[QStringLiteral("installed")] = true;
                app[QStringLiteral("version")] = QStringLiteral("1.0.0");
                app[QStringLiteral("launchMode")] = QStringLiteral("apphost");
                app[QStringLiteral("fullscreen")] = true;
                app[QStringLiteral("controllerOnly")] = true;
                app[QStringLiteral("suspendsConsole")] = true;
            }

            if (!app.isEmpty()) {
                app[QStringLiteral("appDir")] = appDir;
                /* AppHost resolves relative QML against the immutable built-in
                   app root. Installed/state-backed apps therefore publish an
                   absolute entry and never require a writable overlay there. */
                const QString builtInRoot = QDir::cleanPath(appsRootPath());
                if (QDir::cleanPath(rootPath) != builtInRoot && QFileInfo::exists(mainPath))
                    app[QStringLiteral("qmlSource")] = mainPath;

                /*
                    APP_STORE_QML_RUNTIME_GENERATIONS_V3

                    The writable payload tree remains the authoritative installed
                    bytes, but App Store-managed QML launches from a verified,
                    immutable runtime generation recorded in installed.json.
                    Every install/update gets a new absolute directory, which also
                    changes the URL of relative imports (modals/components/etc.).
                    This prevents QQmlEngine from reusing an older compiled child
                    component after a package update.
                */
                const QString id = safeId(app.value(QStringLiteral("id")).toString());
                const QString runtimeSource = m_managedRuntimeQmlSources.value(id).trimmed();
                if (!runtimeSource.isEmpty() && QFileInfo::exists(runtimeSource)) {
                    app[QStringLiteral("qmlSource")] = runtimeSource;
                    app[QStringLiteral("entry")] = runtimeSource;
                    app[QStringLiteral("appDir")] = QFileInfo(runtimeSource).absolutePath();
                    app[QStringLiteral("appStoreRuntimeIsolated")] = true;
                }

                addApp(app);
            }
        }
    }
}

void AppManager::discoverExternalNeutronAppDirs()
{
    /*
        Reserved for future signed/installed app packages.
        Kept separate so policy can be tightened without changing QML.
    */
}

void AppManager::discoverConfigApps()
{
    int priority = 180;

    for (const QString &rootPath : configAppSearchPaths()) {
        QDir root(rootPath);

        if (!root.exists())
            continue;

        const QFileInfoList files = root.entryInfoList(QStringList() << QStringLiteral("*.json"), QDir::Files, QDir::Name);

        for (const QFileInfo &fileInfo : files) {
            QVariantMap app = readJsonAppFile(
                fileInfo.absoluteFilePath(),
                priority++,
                QStringLiteral("config")
            );

            if (!app.isEmpty())
                addApp(app);
        }
    }
}

void AppManager::discoverDesktopApps()
{
    QStringList locations;
    locations << QStringLiteral("/usr/share/applications");

    const QString localApps = HumanHome::browsePath() + QStringLiteral("/.local/share/applications");

    if (!localApps.isEmpty())
        locations << localApps;

    int priority = 700;

    for (const QString &location : locations) {
        QDir dir(location);

        if (!dir.exists())
            continue;

        const QFileInfoList files = dir.entryInfoList(QStringList() << QStringLiteral("*.desktop"), QDir::Files, QDir::Name);

        for (const QFileInfo &fileInfo : files) {
            QVariantMap app = readDesktopFile(fileInfo.absoluteFilePath(), priority++);

            if (!app.isEmpty())
                addApp(app);
        }
    }
}

void AppManager::discoverBuiltInApps()
{
    addApp({
        {QStringLiteral("id"), QStringLiteral("terminal")},
        {QStringLiteral("name"), QStringLiteral("Terminal")},
        {QStringLiteral("subtitle"), QStringLiteral("NeutronOS shell")},
        {QStringLiteral("description"), QStringLiteral("Native NeutronOS terminal app.")},
        {QStringLiteral("category"), QStringLiteral("System")},
        {QStringLiteral("type"), QStringLiteral("qml")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("qmlSource"), QStringLiteral("terminal/Main.qml")},
        {QStringLiteral("entry"), appsRootPath() + QStringLiteral("/terminal/Main.qml")},
        {QStringLiteral("icon"), QStringLiteral("terminal")},
        {QStringLiteral("poster"), QStringLiteral("terminal")},
        {QStringLiteral("installed"), QFileInfo::exists(appsRootPath() + QStringLiteral("/terminal/Main.qml"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), true},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 10},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("terminal"), QStringLiteral("filesystem")})},
        {QStringLiteral("version"), QStringLiteral("1.0.0")},
        {QStringLiteral("launchMode"), QStringLiteral("apphost")},
        {QStringLiteral("fullscreen"), true},
        {QStringLiteral("controllerOnly"), true},
        {QStringLiteral("suspendsConsole"), true}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("settings")},
        {QStringLiteral("name"), QStringLiteral("Settings")},
        {QStringLiteral("subtitle"), QStringLiteral("System Configuration")},
        {QStringLiteral("description"), QStringLiteral("Configure NeutronOS, controller, display, network, theme, and security.")},
        {QStringLiteral("category"), QStringLiteral("System")},
        {QStringLiteral("type"), QStringLiteral("qml")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("qmlSource"), QStringLiteral("settings/Main.qml")},
        {QStringLiteral("entry"), appsRootPath() + QStringLiteral("/settings/Main.qml")},
        {QStringLiteral("icon"), QStringLiteral("settings")},
        {QStringLiteral("poster"), QStringLiteral("settings")},
        {QStringLiteral("installed"), QFileInfo::exists(appsRootPath() + QStringLiteral("/settings/Main.qml"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), true},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 15},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("settings")})},
        {QStringLiteral("version"), QStringLiteral("1.0.0")},
        {QStringLiteral("launchMode"), QStringLiteral("apphost")},
        {QStringLiteral("fullscreen"), true},
        {QStringLiteral("controllerOnly"), true},
        {QStringLiteral("suspendsConsole"), true}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("logs")},
        {QStringLiteral("name"), QStringLiteral("Logs")},
        {QStringLiteral("subtitle"), QStringLiteral("Live System Logs")},
        {QStringLiteral("description"), QStringLiteral("View live and historical journal, Docker, file, and NeutronOS script logs.")},
        {QStringLiteral("category"), QStringLiteral("System")},
        {QStringLiteral("type"), QStringLiteral("qml")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("qmlSource"), QStringLiteral("logs/Main.qml")},
        {QStringLiteral("entry"), appsRootPath() + QStringLiteral("/logs/Main.qml")},
        {QStringLiteral("icon"), QStringLiteral("logs")},
        {QStringLiteral("poster"), QStringLiteral("logs")},
        {QStringLiteral("installed"), QFileInfo::exists(appsRootPath() + QStringLiteral("/logs/Main.qml"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), true},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 20},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("logs"), QStringLiteral("systemd"), QStringLiteral("docker"), QStringLiteral("filesystem")})},
        {QStringLiteral("version"), QStringLiteral("2.0.0")},
        {QStringLiteral("launchMode"), QStringLiteral("apphost")},
        {QStringLiteral("fullscreen"), true},
        {QStringLiteral("controllerOnly"), true},
        {QStringLiteral("suspendsConsole"), true}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("storage")},
        {QStringLiteral("name"), QStringLiteral("Storage")},
        {QStringLiteral("subtitle"), QStringLiteral("Mounts & Filesystems")},
        {QStringLiteral("description"), QStringLiteral("Inspect boot storage, media drives, mounted disks, and storage health.")},
        {QStringLiteral("category"), QStringLiteral("System")},
        {QStringLiteral("type"), QStringLiteral("qml")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("qmlSource"), QStringLiteral("storage/Main.qml")},
        {QStringLiteral("entry"), appsRootPath() + QStringLiteral("/storage/Main.qml")},
        {QStringLiteral("icon"), QStringLiteral("storage")},
        {QStringLiteral("poster"), QStringLiteral("storage")},
        {QStringLiteral("installed"), QFileInfo::exists(appsRootPath() + QStringLiteral("/storage/Main.qml"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), true},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 25},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("filesystem"), QStringLiteral("storage")})},
        {QStringLiteral("version"), QStringLiteral("1.0.0")},
        {QStringLiteral("launchMode"), QStringLiteral("apphost")},
        {QStringLiteral("fullscreen"), true},
        {QStringLiteral("controllerOnly"), true},
        {QStringLiteral("suspendsConsole"), true}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("docker")},
        {QStringLiteral("name"), QStringLiteral("Docker")},
        {QStringLiteral("subtitle"), QStringLiteral("Container Manager")},
        {QStringLiteral("description"), QStringLiteral("Create, inspect, edit, start, stop, and remove Docker containers with controller-first safety confirmations.")},
        {QStringLiteral("category"), QStringLiteral("System")},
        {QStringLiteral("type"), QStringLiteral("qml")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("qmlSource"), QStringLiteral("docker/Main.qml")},
        {QStringLiteral("entry"), appsRootPath() + QStringLiteral("/docker/Main.qml")},
        {QStringLiteral("icon"), QStringLiteral("docker")},
        {QStringLiteral("poster"), QStringLiteral("docker")},
        {QStringLiteral("installed"), QFileInfo::exists(appsRootPath() + QStringLiteral("/docker/Main.qml"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), true},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 30},
        {QStringLiteral("version"), QStringLiteral("2.0.0")},
        {QStringLiteral("launchMode"), QStringLiteral("apphost")},
        {QStringLiteral("fullscreen"), true},
        {QStringLiteral("controllerOnly"), true},
        {QStringLiteral("suspendsConsole"), true},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("docker"), QStringLiteral("systemd"), QStringLiteral("filesystem")})}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("jellyfin")},
        {QStringLiteral("name"), QStringLiteral("Neutron Media Libraries")},
        {QStringLiteral("subtitle"), QStringLiteral("Jellyfin Media")},
        {QStringLiteral("description"), QStringLiteral("Controller-first Jellyfin media library with local, Roku, offline Wi-Fi, and direct LAN playback setup.")},
        {QStringLiteral("category"), QStringLiteral("Media")},
        {QStringLiteral("type"), QStringLiteral("qml")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("qmlSource"), QStringLiteral("jellyfin/Main.qml")},
        {QStringLiteral("entry"), appsRootPath() + QStringLiteral("/jellyfin/Main.qml")},
        {QStringLiteral("icon"), QStringLiteral("jellyfin")},
        {QStringLiteral("poster"), QStringLiteral("jellyfin")},
        {QStringLiteral("installed"), QFileInfo::exists(appsRootPath() + QStringLiteral("/jellyfin/Main.qml"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), true},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 40},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("network"), QStringLiteral("state"), QStringLiteral("media-playback")})},
        {QStringLiteral("version"), QStringLiteral("1.0.4")},
        {QStringLiteral("launchMode"), QStringLiteral("apphost")},
        {QStringLiteral("fullscreen"), true},
        {QStringLiteral("controllerOnly"), true},
        {QStringLiteral("suspendsConsole"), true}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("qbittorrent")},
        {QStringLiteral("name"), QStringLiteral("qBittorrent Manager")},
        {QStringLiteral("subtitle"), QStringLiteral("Transfer Control")},
        {QStringLiteral("description"), QStringLiteral("Fullscreen controller-first qBittorrent manager for torrents, files, refresh, remove, force start, and local .torrent imports.")},
        {QStringLiteral("category"), QStringLiteral("Network")},
        {QStringLiteral("type"), QStringLiteral("qml")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("qmlSource"), QStringLiteral("qbittorrent/Main.qml")},
        {QStringLiteral("entry"), appsRootPath() + QStringLiteral("/qbittorrent/Main.qml")},
        {QStringLiteral("url"), QStringLiteral("http://localhost:8080")},
        {QStringLiteral("docker"), QStringLiteral("qbittorrent")},
        {QStringLiteral("service"), QStringLiteral("qbittorrent.service")},
        {QStringLiteral("icon"), QStringLiteral("qbittorrent")},
        {QStringLiteral("poster"), QStringLiteral("qbittorrent")},
        {QStringLiteral("installed"), QFileInfo::exists(appsRootPath() + QStringLiteral("/qbittorrent/Main.qml")) ||
                                      dockerContainerExists(QStringLiteral("qbittorrent")) ||
                                      systemdUnitExists(QStringLiteral("qbittorrent.service"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), true},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 50},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("network"), QStringLiteral("docker"), QStringLiteral("filesystem")})},
        {QStringLiteral("version"), QStringLiteral("1.0.0")},
        {QStringLiteral("launchMode"), QStringLiteral("apphost")},
        {QStringLiteral("fullscreen"), true},
        {QStringLiteral("controllerOnly"), true},
        {QStringLiteral("suspendsConsole"), true},
        {QStringLiteral("controllerMap"), QStringLiteral("X primary, O back, Triangle files/context, Start options")}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("mediaoptimizer")},
        {QStringLiteral("name"), QStringLiteral("Media Optimizer")},
        {QStringLiteral("subtitle"), QStringLiteral("Roku Compatibility Manager")},
        {QStringLiteral("description"), QStringLiteral("Analyze media compatibility, manage audio and subtitle tracks, estimate savings, and run guarded FFmpeg optimization.")},
        {QStringLiteral("category"), QStringLiteral("Media")},
        {QStringLiteral("type"), QStringLiteral("qml")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("qmlSource"), QStringLiteral("mediaoptimizer/Main.qml")},
        {QStringLiteral("entry"), appsRootPath() + QStringLiteral("/mediaoptimizer/Main.qml")},
        {QStringLiteral("icon"), QStringLiteral("optimizer")},
        {QStringLiteral("poster"), QStringLiteral("optimizer")},
        {QStringLiteral("installed"), QFileInfo::exists(appsRootPath() + QStringLiteral("/mediaoptimizer/Main.qml"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), true},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 60},
        {QStringLiteral("version"), QStringLiteral("2.0.0")},
        {QStringLiteral("launchMode"), QStringLiteral("apphost")},
        {QStringLiteral("fullscreen"), true},
        {QStringLiteral("controllerOnly"), true},
        {QStringLiteral("suspendsConsole"), true},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("filesystem"), QStringLiteral("media"), QStringLiteral("ffmpeg")})}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("tailscale")},
        {QStringLiteral("name"), QStringLiteral("Tailscale")},
        {QStringLiteral("subtitle"), QStringLiteral("Private Network")},
        {QStringLiteral("description"), QStringLiteral("Private remote access network status.")},
        {QStringLiteral("category"), QStringLiteral("Network")},
        {QStringLiteral("type"), QStringLiteral("command")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("service"), QStringLiteral("tailscaled.service")},
        {QStringLiteral("command"), QStringLiteral("tailscale status")},
        {QStringLiteral("icon"), QStringLiteral("tailscale")},
        {QStringLiteral("poster"), QStringLiteral("tailscale")},
        {QStringLiteral("installed"), commandExists(QStringLiteral("tailscale")) ||
                                      systemdUnitExists(QStringLiteral("tailscaled.service"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), false},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 90},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("network"), QStringLiteral("systemd")})}
    });

    const QString sshService =
        systemdUnitExists(QStringLiteral("ssh.service"))
        ? QStringLiteral("ssh.service")
        : QStringLiteral("sshd.service");

    addApp({
        {QStringLiteral("id"), QStringLiteral("ssh")},
        {QStringLiteral("name"), QStringLiteral("SSH")},
        {QStringLiteral("subtitle"), QStringLiteral("Remote Access")},
        {QStringLiteral("description"), QStringLiteral("SSH server remote access.")},
        {QStringLiteral("category"), QStringLiteral("System")},
        {QStringLiteral("type"), QStringLiteral("service-web")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("url"), QStringLiteral("internal://ssh")},
        {QStringLiteral("service"), sshService},
        {QStringLiteral("icon"), QStringLiteral("ssh")},
        {QStringLiteral("poster"), QStringLiteral("ssh")},
        {QStringLiteral("command"), QStringLiteral("systemctl status ") + sshService},
        {QStringLiteral("installed"), systemdUnitExists(sshService)},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), false},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 100},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("network"), QStringLiteral("systemd")})}
    });

    addApp({
        {QStringLiteral("id"), QStringLiteral("portainer")},
        {QStringLiteral("name"), QStringLiteral("Portainer")},
        {QStringLiteral("subtitle"), QStringLiteral("Docker Manager")},
        {QStringLiteral("description"), QStringLiteral("Docker management web console.")},
        {QStringLiteral("category"), QStringLiteral("System")},
        {QStringLiteral("type"), QStringLiteral("web")},
        {QStringLiteral("source"), QStringLiteral("builtin")},
        {QStringLiteral("url"), QStringLiteral("http://localhost:9000")},
        {QStringLiteral("docker"), QStringLiteral("portainer")},
        {QStringLiteral("service"), QStringLiteral("portainer.service")},
        {QStringLiteral("icon"), QStringLiteral("portainer")},
        {QStringLiteral("poster"), QStringLiteral("portainer")},
        {QStringLiteral("installed"), dockerContainerExists(QStringLiteral("portainer")) ||
                                      systemdUnitExists(QStringLiteral("portainer.service"))},
        {QStringLiteral("running"), false},
        {QStringLiteral("uiRunning"), false},
        {QStringLiteral("sessionText"), QStringLiteral("Closed")},
        {QStringLiteral("favorite"), false},
        {QStringLiteral("hidden"), false},
        {QStringLiteral("priority"), 110},
        {QStringLiteral("permissions"), stringListToVariantList({QStringLiteral("network"), QStringLiteral("docker")})}
    });
}

/*
    ============================================================
                            MANIFESTS
    ============================================================
*/


QVariantMap AppManager::readJsonAppFile(const QString &path, int priority, const QString &sourceName) const
{
    QFile file(path);

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "Unable to open app json:" << path << file.errorString();
        return {};
    }

    const QByteArray data = file.readAll();
    file.close();

    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "Invalid app json:" << path << error.errorString();
        return {};
    }

    QVariantMap app = doc.object().toVariantMap();

    if (!app.contains(QStringLiteral("priority")))
        app[QStringLiteral("priority")] = priority;

    if (!app.contains(QStringLiteral("source")))
        app[QStringLiteral("source")] = sourceName;

    if (!app.contains(QStringLiteral("configPath")))
        app[QStringLiteral("configPath")] = path;

    return normalizeApp(app);
}

QVariantMap AppManager::readNeutronManifest(const QString &manifestPath) const
{
    QVariantMap app = readJsonAppFile(manifestPath, 200, QStringLiteral("neutron"));

    if (app.isEmpty())
        return {};

    const QFileInfo manifestInfo(manifestPath);
    const QString appDir = manifestInfo.absolutePath();
    const QString folderName = QFileInfo(appDir).fileName();
    const QString mainPath = appDir + QStringLiteral("/Main.qml");

    if (!app.contains(QStringLiteral("id")) || app.value(QStringLiteral("id")).toString().trimmed().isEmpty())
        app[QStringLiteral("id")] = safeId(folderName);

    if (!app.contains(QStringLiteral("name")) || app.value(QStringLiteral("name")).toString().trimmed().isEmpty())
        app[QStringLiteral("name")] = displayNameFromId(app.value(QStringLiteral("id")).toString());

    if (!app.contains(QStringLiteral("type")))
        app[QStringLiteral("type")] = QStringLiteral("qml");

    if (!app.contains(QStringLiteral("qmlSource")) && QFileInfo::exists(mainPath))
        app[QStringLiteral("qmlSource")] = folderName + QStringLiteral("/Main.qml");

    if (!app.contains(QStringLiteral("entry")) && QFileInfo::exists(mainPath))
        app[QStringLiteral("entry")] = mainPath;

    if (!app.contains(QStringLiteral("appDir")))
        app[QStringLiteral("appDir")] = appDir;

    if (!app.contains(QStringLiteral("icon")))
        app[QStringLiteral("icon")] = safeId(folderName);

    if (!app.contains(QStringLiteral("poster")))
        app[QStringLiteral("poster")] = safeId(folderName);

    if (!app.contains(QStringLiteral("installed")))
        app[QStringLiteral("installed")] = QFileInfo::exists(mainPath);

    if (!app.contains(QStringLiteral("priority")))
        app[QStringLiteral("priority")] = 200;

    return normalizeApp(app);
}

bool AppManager::hasValidDashboardManifest(const QVariantMap &app) const
{
    const QString id = safeId(app.value(QStringLiteral("id")).toString());
    if (id.isEmpty())
        return false;

    QStringList candidates;

    const QString configPath = app.value(QStringLiteral("configPath")).toString().trimmed();
    if (!configPath.isEmpty() && QFileInfo(configPath).fileName() == QStringLiteral("app.json"))
        candidates.append(configPath);

    const QString appDir = app.value(QStringLiteral("appDir")).toString().trimmed();
    if (!appDir.isEmpty())
        candidates.append(QDir(appDir).filePath(QStringLiteral("app.json")));

    for (const QString &root : neutronAppSearchPaths())
        candidates.append(QDir(root).filePath(id + QStringLiteral("/app.json")));

    candidates.removeDuplicates();

    for (const QString &manifestPath : candidates) {
        QFile file(manifestPath);
        if (!file.exists() || !file.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;

        QJsonParseError error;
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
        file.close();

        if (error.error != QJsonParseError::NoError ||
            !doc.isObject() ||
            doc.object().isEmpty()) {
            continue;
        }

        const QJsonObject object = doc.object();
        const QString manifestId = safeId(object.value(QStringLiteral("id")).toString());

        // Missing id is valid because readNeutronManifest() derives it from
        // the folder. A declared id must still identify this registry app.
        if (!manifestId.isEmpty() && manifestId != id)
            continue;

        return true;
    }

    return false;
}

QVariantMap AppManager::readDesktopFile(const QString &desktopPath, int priority) const
{
    QFile file(desktopPath);

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};

    QVariantMap values;
    QTextStream in(&file);
    bool inDesktopEntry = false;

    while (!in.atEnd()) {
        const QString raw = in.readLine().trimmed();

        if (raw.isEmpty() || raw.startsWith(QStringLiteral("#")))
            continue;

        if (raw.startsWith(QStringLiteral("[")) && raw.endsWith(QStringLiteral("]"))) {
            inDesktopEntry = raw == QStringLiteral("[Desktop Entry]");
            continue;
        }

        if (!inDesktopEntry)
            continue;

        const int idx = raw.indexOf(QStringLiteral("="));

        if (idx <= 0)
            continue;

        const QString key = raw.left(idx).trimmed();
        const QString value = raw.mid(idx + 1).trimmed();

        if (!values.contains(key))
            values[key] = value;
    }

    file.close();

    if (values.value(QStringLiteral("Type")).toString() != QStringLiteral("Application"))
        return {};

    if (values.value(QStringLiteral("NoDisplay")).toString().toLower() == QStringLiteral("true") ||
            values.value(QStringLiteral("Hidden")).toString().toLower() == QStringLiteral("true")) {
        return {};
    }

    const QString name = values.value(QStringLiteral("Name")).toString().trimmed();
    const QString exec = cleanDesktopExec(values.value(QStringLiteral("Exec")).toString());

    if (name.isEmpty() || exec.isEmpty())
        return {};

    const QString command = firstCommandToken(exec);

    if (!commandExists(command))
        return {};

    const QFileInfo info(desktopPath);

    QVariantMap app;
    app[QStringLiteral("id")] = QStringLiteral("linux_") + safeId(info.completeBaseName());
    app[QStringLiteral("name")] = name;
    app[QStringLiteral("subtitle")] = values.value(QStringLiteral("Comment"), QStringLiteral("Installed Linux app")).toString();
    app[QStringLiteral("description")] = values.value(QStringLiteral("Comment"), QString()).toString();
    app[QStringLiteral("category")] = QStringLiteral("Installed");
    app[QStringLiteral("type")] = QStringLiteral("external");
    app[QStringLiteral("source")] = QStringLiteral("desktop");
    app[QStringLiteral("desktopFile")] = desktopPath;
    app[QStringLiteral("command")] = exec;
    app[QStringLiteral("icon")] = values.value(QStringLiteral("Icon"), QStringLiteral("app")).toString();
    app[QStringLiteral("poster")] = values.value(QStringLiteral("Icon"), QStringLiteral("app")).toString();
    app[QStringLiteral("installed")] = true;
    app[QStringLiteral("running")] = false;
    app[QStringLiteral("uiRunning")] = false;
    app[QStringLiteral("sessionText")] = QStringLiteral("Closed");
    app[QStringLiteral("favorite")] = false;
    app[QStringLiteral("hidden")] = false;
    app[QStringLiteral("priority")] = priority;
    app[QStringLiteral("permissions")] = stringListToVariantList({QStringLiteral("external")});
    app[QStringLiteral("version")] = QString();

    return normalizeApp(app);
}

/*
    ============================================================
                            NORMALIZATION
    ============================================================
*/

QString AppManager::normalizedType(const QString &type) const
{
    const QString t = type.trimmed().toLower();

    if (t == QStringLiteral("native"))
        return QStringLiteral("qml");

    if (t == QStringLiteral("cpp") ||
            t == QStringLiteral("binary") ||
            t == QStringLiteral("executable")) {
        return QStringLiteral("external");
    }

    if (t == QStringLiteral("python") ||
            t == QStringLiteral("py") ||
            t == QStringLiteral("script") ||
            t == QStringLiteral("shell") ||
            t == QStringLiteral("sh")) {
        return QStringLiteral("command");
    }

    if (t == QStringLiteral("url"))
        return QStringLiteral("web");

    if (t == QStringLiteral("desktop"))
        return QStringLiteral("external");

    if (t == QStringLiteral("systemd") || t == QStringLiteral("service"))
        return QStringLiteral("service-web");

    if (t == QStringLiteral("service_web"))
        return QStringLiteral("service-web");

    if (t == QStringLiteral("qml") ||
            t == QStringLiteral("isolated") ||
            t == QStringLiteral("web") ||
            t == QStringLiteral("service-web") ||
            t == QStringLiteral("command") ||
            t == QStringLiteral("external")) {
        return t;
    }

    return QStringLiteral("qml");
}

QString AppManager::displayNameFromId(const QString &id) const
{
    QString text = id.trimmed();

    if (text.isEmpty())
        return QStringLiteral("App");

    text.replace(QStringLiteral("_"), QStringLiteral(" "));
    text.replace(QStringLiteral("-"), QStringLiteral(" "));

    QStringList words = text.split(QStringLiteral(" "), Qt::SkipEmptyParts);

    for (QString &word : words) {
        if (word.isEmpty())
            continue;

        word = word.left(1).toUpper() + word.mid(1);
    }

    return words.join(QStringLiteral(" "));
}

QVariantMap AppManager::normalizeApp(QVariantMap app) const
{
    const QString rawId = app.value(QStringLiteral("id")).toString();
    QString id = safeId(rawId.isEmpty()
                        ? app.value(QStringLiteral("name")).toString()
                        : rawId);

    if (id.isEmpty())
        return {};

    const bool legacyOptimizerAlias = id == QStringLiteral("vidoptimizer");
    if (legacyOptimizerAlias) {
        id = QStringLiteral("mediaoptimizer");
        app[QStringLiteral("id")] = id;
        app[QStringLiteral("name")] = QStringLiteral("Media Optimizer");
        app[QStringLiteral("subtitle")] = QStringLiteral("Roku Compatibility Manager");
        app[QStringLiteral("description")] = QStringLiteral("Analyze media compatibility, manage tracks, estimate savings, and run guarded FFmpeg optimization.");
        app[QStringLiteral("category")] = QStringLiteral("Media");
        app[QStringLiteral("type")] = QStringLiteral("qml");
        app[QStringLiteral("source")] = QStringLiteral("legacy-alias");
        app[QStringLiteral("qmlSource")] = QStringLiteral("mediaoptimizer/Main.qml");
        app[QStringLiteral("entry")] = appsRootPath() + QStringLiteral("/mediaoptimizer/Main.qml");
        app[QStringLiteral("icon")] = QStringLiteral("optimizer");
        app[QStringLiteral("poster")] = QStringLiteral("optimizer");
        app[QStringLiteral("favorite")] = true;
        app[QStringLiteral("hidden")] = false;
        app[QStringLiteral("priority")] = 60;
        app[QStringLiteral("version")] = QStringLiteral("2.0.0");
        app[QStringLiteral("launchMode")] = QStringLiteral("apphost");
        app[QStringLiteral("fullscreen")] = true;
        app[QStringLiteral("controllerOnly")] = true;
        app[QStringLiteral("suspendsConsole")] = true;
        app.remove(QStringLiteral("service"));
        app.remove(QStringLiteral("docker"));
        app.remove(QStringLiteral("url"));
        app.remove(QStringLiteral("command"));
    }

    QString requestedType = app.value(QStringLiteral("type")).toString().trimmed();

    if (requestedType.isEmpty()) {
        const QString entryHint = app.value(QStringLiteral("entry")).toString().trimmed().toLower();

        if (entryHint.endsWith(QStringLiteral(".py")) ||
                entryHint.endsWith(QStringLiteral(".sh"))) {
            requestedType = QStringLiteral("command");
        } else if (!entryHint.isEmpty() &&
                   !entryHint.endsWith(QStringLiteral(".qml"))) {
            requestedType = QStringLiteral("external");
        } else {
            requestedType = QStringLiteral("qml");
        }
    }

    const QString type = normalizedType(requestedType);

    app[QStringLiteral("id")] = id;
    app[QStringLiteral("name")] = app.value(QStringLiteral("name"), displayNameFromId(id)).toString();
    app[QStringLiteral("subtitle")] = app.value(QStringLiteral("subtitle"), QString()).toString();
    app[QStringLiteral("description")] = app.value(QStringLiteral("description"), QString()).toString();
    app[QStringLiteral("category")] = app.value(QStringLiteral("category"), QStringLiteral("Apps")).toString();
    app[QStringLiteral("type")] = type;
    app[QStringLiteral("source")] = app.value(QStringLiteral("source"), QStringLiteral("unknown")).toString();

    app[QStringLiteral("icon")] = app.value(QStringLiteral("icon"), id).toString();
    app[QStringLiteral("poster")] = app.value(QStringLiteral("poster"), id).toString();

    app[QStringLiteral("favorite")] = app.value(QStringLiteral("favorite"), false).toBool();
    app[QStringLiteral("hidden")] = app.value(QStringLiteral("hidden"), false).toBool();
    app[QStringLiteral("priority")] = app.value(QStringLiteral("priority"), 999).toInt();

    if (!app.contains(QStringLiteral("permissions")))
        app[QStringLiteral("permissions")] = QVariantList();

    if (!app.contains(QStringLiteral("version")))
        app[QStringLiteral("version")] = QString();

    if (!app.contains(QStringLiteral("author")))
        app[QStringLiteral("author")] = QString();

    if (!app.contains(QStringLiteral("launchMode")))
        app[QStringLiteral("launchMode")] = type == QStringLiteral("qml") ? QStringLiteral("apphost") : type;

    if (!app.contains(QStringLiteral("fullscreen")))
        app[QStringLiteral("fullscreen")] = true;

    if (!app.contains(QStringLiteral("controllerOnly")))
        app[QStringLiteral("controllerOnly")] = true;

    if (!app.contains(QStringLiteral("suspendsConsole")))
        app[QStringLiteral("suspendsConsole")] = true;

    if (!app.contains(QStringLiteral("uiRunning")))
        app[QStringLiteral("uiRunning")] = false;

    if (!app.contains(QStringLiteral("sessionText")))
        app[QStringLiteral("sessionText")] = app.value(QStringLiteral("uiRunning")).toBool()
                                            ? QStringLiteral("Open")
                                            : QStringLiteral("Closed");

    if (type == QStringLiteral("qml")) {
        const QString entry = resolveQmlEntryPath(app);

        if (!entry.isEmpty()) {
            app[QStringLiteral("entry")] = entry;
            if (!app.contains(QStringLiteral("appDir")) ||
                    app.value(QStringLiteral("appDir")).toString().trimmed().isEmpty()) {
                app[QStringLiteral("appDir")] = QFileInfo(entry).absolutePath();
            }
        }

        if (!app.contains(QStringLiteral("qmlSource")) || app.value(QStringLiteral("qmlSource")).toString().trimmed().isEmpty())
            app[QStringLiteral("qmlSource")] = resolveQmlSource(app);

        app[QStringLiteral("installed")] = app.value(QStringLiteral("installed"), QFileInfo::exists(entry)).toBool();
    } else if (type == QStringLiteral("web") || type == QStringLiteral("service-web")) {
        if (!app.contains(QStringLiteral("url")))
            app[QStringLiteral("url")] = QString();

        app[QStringLiteral("installed")] = app.value(QStringLiteral("installed"), true).toBool();
    } else if (type == QStringLiteral("command") || type == QStringLiteral("external")) {
        if (!app.contains(QStringLiteral("command")))
            app[QStringLiteral("command")] = QString();

        QString entry = app.value(QStringLiteral("entry")).toString().trimmed();

        if (entry.startsWith(QStringLiteral("file://")))
            entry = QUrl(entry).toLocalFile();

        const bool hasLaunchTarget =
            !app.value(QStringLiteral("command")).toString().trimmed().isEmpty() ||
            (!entry.isEmpty() && QFileInfo::exists(entry));

        app[QStringLiteral("installed")] =
            app.value(QStringLiteral("installed"), hasLaunchTarget).toBool();
    } else {
        app[QStringLiteral("installed")] = app.value(QStringLiteral("installed"), true).toBool();
    }

    const bool running = app.value(QStringLiteral("running"), false).toBool();
    app[QStringLiteral("statusText")] = running ? QStringLiteral("Active") : QStringLiteral("Inactive");
    app[QStringLiteral("statusColor")] = running ? QStringLiteral("#22ff88") : QStringLiteral("#ff3040");
    app[QStringLiteral("lastUsedUtc")] = m_lastUsedByApp.value(id);

    return app;
}

QVariantMap AppManager::withLiveStatus(QVariantMap app) const
{
    app = normalizeApp(app);

    const QString id =
        app.value(QStringLiteral("id"))
            .toString();

    const QString type =
        app.value(QStringLiteral("type"))
            .toString();

    const QString service =
        app.value(QStringLiteral("service"))
            .toString()
            .trimmed();

    const QString docker =
        app.value(QStringLiteral("docker"))
            .toString()
            .trimmed();

    bool installed =
        app.value(
            QStringLiteral("installed"),
            true)
            .toBool();

    const bool uiRunning =
        app.value(
            QStringLiteral("uiRunning"),
            false)
            .toBool();

    const bool backgroundRunning =
        m_backgroundApps.contains(id) ||
        app.value(
            QStringLiteral("backgroundRunning"))
            .toBool();

    const bool appRunning =
        uiRunning ||
        backgroundRunning;

    bool serviceRunning = false;

    if (!docker.isEmpty()) {
        installed =
            dockerContainerExists(docker) ||
            installed;

        serviceRunning =
            dockerContainerRunning(docker);
    } else if (!service.isEmpty()) {
        installed =
            systemdUnitExists(service) ||
            installed;

        serviceRunning =
            systemdUnitActive(service);
    } else if (id == QStringLiteral("docker")) {
        installed =
            dockerExists() ||
            installed;

        serviceRunning =
            systemdUnitActive(
                QStringLiteral("docker.service"));
    } else if (id == QStringLiteral("jellyfin")) {
        installed =
            dockerContainerExists(
                QStringLiteral("jellyfin")) ||
            systemdUnitExists(
                QStringLiteral("jellyfin.service")) ||
            qmlEntryExists(app) ||
            installed;

        serviceRunning =
            dockerContainerRunning(
                QStringLiteral("jellyfin")) ||
            systemdUnitActive(
                QStringLiteral("jellyfin.service"));
    } else if (id == QStringLiteral("qbittorrent")) {
        installed =
            dockerContainerExists(
                QStringLiteral("qbittorrent")) ||
            systemdUnitExists(
                QStringLiteral("qbittorrent.service")) ||
            systemdUnitExists(
                QStringLiteral("qbittorrent-nox.service")) ||
            qmlEntryExists(app) ||
            installed;

        serviceRunning =
            dockerContainerRunning(
                QStringLiteral("qbittorrent")) ||
            systemdUnitActive(
                QStringLiteral("qbittorrent.service")) ||
            systemdUnitActive(
                QStringLiteral("qbittorrent-nox.service"));
    } else if (id == QStringLiteral("tailscale")) {
        installed =
            systemdUnitExists(
                QStringLiteral("tailscaled.service")) ||
            commandExists(
                QStringLiteral("tailscale")) ||
            installed;

        serviceRunning =
            systemdUnitActive(
                QStringLiteral("tailscaled.service"));
    } else if (id == QStringLiteral("portainer")) {
        installed =
            dockerContainerExists(
                QStringLiteral("portainer")) ||
            installed;

        serviceRunning =
            dockerContainerRunning(
                QStringLiteral("portainer"));
    } else if (type == QStringLiteral("qml")) {
        installed = qmlEntryExists(app);
    }

    const bool running =
        appRunning ||
        serviceRunning;

    app[QStringLiteral("installed")] =
        installed;

    app[QStringLiteral("uiRunning")] =
        uiRunning;

    app[QStringLiteral("backgroundRunning")] =
        backgroundRunning;

    app[QStringLiteral("appRunning")] =
        appRunning;

    app[QStringLiteral("serviceRunning")] =
        serviceRunning;

    // Keep the legacy aggregate for old surfaces, but modern Dashboard v2 uses
    // appRunning/serviceRunning independently.
    app[QStringLiteral("running")] =
        running;

    if (appRunning) {
        app[QStringLiteral("statusText")] =
            backgroundRunning && !uiRunning
            ? QStringLiteral("Background")
            : QStringLiteral("Active");

        app[QStringLiteral("statusColor")] =
            backgroundRunning && !uiRunning
            ? QStringLiteral("#7df9ff")
            : QStringLiteral("#22ff88");
    } else if (serviceRunning) {
        app[QStringLiteral("statusText")] =
            QStringLiteral("Service Active");

        app[QStringLiteral("statusColor")] =
            QStringLiteral("#22ff88");
    } else {
        app[QStringLiteral("statusText")] =
            QStringLiteral("Inactive");

        app[QStringLiteral("statusColor")] =
            QStringLiteral("#ff3040");
    }

    return app;
}

void AppManager::addApp(const QVariantMap &rawApp)
{
    QVariantMap app = normalizeApp(rawApp);
    const QString id = app.value(QStringLiteral("id")).toString();

    if (id.isEmpty())
        return;

    if (m_favoriteOverrides.contains(id))
        app[QStringLiteral("favorite")] = m_favoriteOverrides.value(id);
    else if (m_managedPackageIds.contains(id) &&
             !app.value(QStringLiteral("hidden")).toBool() &&
             !app.value(QStringLiteral("systemOnly")).toBool())
        app[QStringLiteral("favorite")] = true;

    if (m_seenAppIds.contains(id)) {
        /*
            A built-in registry placeholder may exist even after its source
            QML has been removed. App Store payload discovery happens later,
            so an installed managed package must be allowed to replace an
            uninstalled placeholder with the same id. Installed built-ins are
            never displaced by this rule.
        */
        for (int index = 0; index < m_apps.size(); ++index) {
            const QVariantMap existing = m_apps.at(index).toMap();
            if (existing.value(QStringLiteral("id")).toString() != id)
                continue;

            const bool existingInstalled =
                existing.value(QStringLiteral("installed"), false).toBool();
            const bool replacementInstalled =
                app.value(QStringLiteral("installed"), false).toBool();

            if (!existingInstalled && replacementInstalled &&
                    m_managedPackageIds.contains(id)) {
                m_apps[index] = app;
            }
            return;
        }
        return;
    }

    m_seenAppIds.insert(id);
    m_apps.append(app);
}

void AppManager::rebuildDerivedLists()
{
    m_favoriteApps.clear();
    m_hiddenApps.clear();

    QHash<QString, QVariantMap> favoritesById;
    QStringList discoveredFavoriteIds;

    for (const QVariant &item : m_apps) {
        const QVariantMap app = item.toMap();
        const QString id = app.value(QStringLiteral("id")).toString();

        if (app.value(QStringLiteral("hidden")).toBool() ||
            !app.value(QStringLiteral("favorite")).toBool()) {
            m_hiddenApps.append(app);
            continue;
        }

        favoritesById.insert(id, app);
        discoveredFavoriteIds.append(id);
    }

    QStringList effectiveOrder = m_favoriteOrder;

    for (const QString &id : discoveredFavoriteIds) {
        if (!effectiveOrder.contains(id))
            effectiveOrder.append(id);
    }

    QStringList cleanedOrder;

    for (const QString &id : effectiveOrder) {
        if (!favoritesById.contains(id) || cleanedOrder.contains(id))
            continue;

        m_favoriteApps.append(favoritesById.value(id));
        cleanedOrder.append(id);
    }

    if (cleanedOrder != m_favoriteOrder) {
        m_favoriteOrder = cleanedOrder;

        if (!saveCarouselState())
            qWarning() << "Unable to persist cleaned carousel order";
    }
}

void AppManager::updateAppStatus(const QString &appId, bool uiRunning)
{
    const QString cleanId = safeId(appId);

    for (int i = 0; i < m_apps.size(); ++i) {
        QVariantMap app = m_apps[i].toMap();

        if (app.value(QStringLiteral("id")).toString() != cleanId)
            continue;

        const bool backgroundRunning =
            m_backgroundApps.contains(cleanId);

        app[QStringLiteral("uiRunning")] =
            uiRunning;

        app[QStringLiteral("backgroundRunning")] =
            backgroundRunning;

        app[QStringLiteral("sessionText")] =
            uiRunning
            ? QStringLiteral("Open")
            : (backgroundRunning
               ? QStringLiteral("Background")
               : QStringLiteral("Closed"));

        app = withLiveStatus(app);

        // withLiveStatus reads the values above and computes appRunning and
        // serviceRunning separately. Reassert session text after live probes.
        app[QStringLiteral("uiRunning")] =
            uiRunning;

        app[QStringLiteral("backgroundRunning")] =
            backgroundRunning;

        app[QStringLiteral("appRunning")] =
            uiRunning || backgroundRunning;

        app[QStringLiteral("running")] =
            app.value(
                QStringLiteral("appRunning"))
                .toBool() ||
            app.value(
                QStringLiteral("serviceRunning"))
                .toBool();

        app[QStringLiteral("sessionText")] =
            uiRunning
            ? QStringLiteral("Open")
            : (backgroundRunning
               ? QStringLiteral("Background")
               : QStringLiteral("Closed"));

        m_apps[i] = app;

        rebuildDerivedLists();
        emit appsChanged();

        rebuildRunningApps();
        return;
    }
}

QString AppManager::usageStatePath() const
{
    const QString stateRoot = HumanHome::appStateRoot();
    return QDir::cleanPath(stateRoot + QStringLiteral("/apps/usage.json"));
}

void AppManager::loadUsageState()
{
    m_lastUsedByApp.clear();
    QFile file(usageStatePath());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return;
    const QJsonObject values = document.object().value(QStringLiteral("lastUsed")).toObject();
    bool migratedLegacyOptimizer = false;
    for (auto it = values.begin(); it != values.end(); ++it) {
        QString id = safeId(it.key());
        if (id == QStringLiteral("vidoptimizer")) {
            id = QStringLiteral("mediaoptimizer");
            migratedLegacyOptimizer = true;
        }
        const QString stamp = it.value().toString().trimmed();
        if (!id.isEmpty() && QDateTime::fromString(stamp, Qt::ISODate).isValid())
            m_lastUsedByApp.insert(id, stamp);
    }
    file.close();
    if (migratedLegacyOptimizer && !saveUsageState())
        qWarning() << "Unable to persist Media Optimizer usage migration";
}

bool AppManager::saveUsageState() const
{
    QDir().mkpath(QFileInfo(usageStatePath()).absolutePath());
    QJsonObject values;
    for (auto it = m_lastUsedByApp.cbegin(); it != m_lastUsedByApp.cend(); ++it)
        values.insert(it.key(), it.value());
    QJsonObject root;
    root.insert(QStringLiteral("version"), 1);
    root.insert(QStringLiteral("lastUsed"), values);
    root.insert(QStringLiteral("savedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    QSaveFile file(usageStatePath());
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return file.commit();
}

void AppManager::recordAppUsed(const QString &appId)
{
    const QString id = safeId(appId);
    if (id.isEmpty())
        return;
    m_lastUsedByApp.insert(id, QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    saveUsageState();
}

quint64 AppManager::pathSize(const QString &path) const
{
    const QFileInfo root(path);
    if (!root.exists() || root.isSymLink())
        return 0;
    if (root.isFile())
        return static_cast<quint64>(qMax<qint64>(0, root.size()));

    quint64 total = 0;
    QDirIterator iterator(path, QDir::Files | QDir::NoDotAndDotDot,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext()) {
        iterator.next();
        const QFileInfo info = iterator.fileInfo();
        if (!info.isSymLink())
            total += static_cast<quint64>(qMax<qint64>(0, info.size()));
    }
    return total;
}

QStringList AppManager::managedStoragePaths(const QVariantMap &app) const
{
    const QString id = safeId(app.value(QStringLiteral("id")).toString());
    QStringList paths;
    const QString appDir = app.value(QStringLiteral("appDir")).toString().trimmed();
    const QString configPath = app.value(QStringLiteral("configPath")).toString().trimmed();
    if (!appDir.isEmpty())
        paths << appDir;
    if (!configPath.isEmpty())
        paths << configPath;
    if (!id.isEmpty()) {
        paths << neutronRootPath() + QStringLiteral("/state/apps/") + id;
        paths << QStringLiteral("/var/lib/neutronos/apps/") + id;
    }
    paths.removeDuplicates();
    return paths;
}

QStringList AppManager::managedCachePaths(const QVariantMap &app) const
{
    const QString id = safeId(app.value(QStringLiteral("id")).toString());
    if (id.isEmpty())
        return {};
    QStringList paths{
        neutronRootPath() + QStringLiteral("/state/apps/") + id + QStringLiteral("/cache"),
        neutronRootPath() + QStringLiteral("/state/cache/") + id,
        QStringLiteral("/var/cache/neutronos/") + id,
        HumanHome::browsePath() + QStringLiteral("/cache/neutronos/") + id
    };
    const QString declared = app.value(QStringLiteral("cachePath")).toString().trimmed();
    if (!declared.isEmpty())
        paths << declared;
    paths.removeDuplicates();
    return paths;
}

bool AppManager::removeManagedPath(const QString &path, const QStringList &allowedRoots) const
{
    QFileInfo info(path);
    if (!info.exists())
        return true;
    if (info.isSymLink())
        return QFile::remove(info.absoluteFilePath());

    const QString candidate = QDir::cleanPath(info.canonicalFilePath().isEmpty()
                                              ? info.absoluteFilePath()
                                              : info.canonicalFilePath());
    bool allowed = false;
    for (const QString &rawRoot : allowedRoots) {
        QFileInfo rootInfo(rawRoot);
        const QString root = QDir::cleanPath(rootInfo.canonicalFilePath().isEmpty()
                                             ? rootInfo.absoluteFilePath()
                                             : rootInfo.canonicalFilePath());
        if (!root.isEmpty() && candidate.startsWith(root + QDir::separator())) {
            allowed = true;
            break;
        }
    }
    if (!allowed)
        return false;
    if (info.isDir())
        return QDir(candidate).removeRecursively();
    return QFile::remove(candidate);
}

bool AppManager::automaticLoginEnabled() const
{
    QFile file(QStringLiteral("/var/lib/neutronos/settings/control-centre.json"));
    if (!file.open(QIODevice::ReadOnly))
        return false;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return false;
    return document.object().value(QStringLiteral("values")).toObject()
        .value(QStringLiteral("user.autoLogin")).toBool(false);
}

bool AppManager::highPriorityAuthorizedForSettings() const
{
    if (!automaticLoginEnabled())
        return true;
    if (!qApp)
        return false;
    const QString appId = qApp->property("neutronHighPriorityAppId").toString();
    const qint64 expires = qApp->property("neutronHighPriorityExpiresUtcMs").toLongLong();
    return appId == QStringLiteral("settings") &&
           expires > QDateTime::currentDateTimeUtc().toMSecsSinceEpoch();
}

bool AppManager::clearAppCache(const QVariantMap &appData)
{
    const QVariantMap app = normalizeApp(appData);
    const QString id = app.value(QStringLiteral("id")).toString();
    if (id.isEmpty()) {
        emit appActionFinished(id, QStringLiteral("clear-cache"), false,
                               QStringLiteral("Missing app id"));
        return false;
    }
    if (!highPriorityAuthorizedForSettings()) {
        emit appActionFinished(id, QStringLiteral("clear-cache"), false,
                               QStringLiteral("Login password authorization is required while Automatic Login is enabled"));
        return false;
    }

    const QStringList allowedRoots{
        neutronRootPath() + QStringLiteral("/state/cache"),
        neutronRootPath() + QStringLiteral("/state/apps"),
        QStringLiteral("/var/cache/neutronos"),
        HumanHome::browsePath() + QStringLiteral("/cache/neutronos")
    };
    bool ok = true;
    bool found = false;
    for (const QString &path : managedCachePaths(app)) {
        if (!QFileInfo::exists(path))
            continue;
        found = true;
        if (!removeManagedPath(path, allowedRoots))
            ok = false;
    }
    emit appActionFinished(id, QStringLiteral("clear-cache"), ok,
                           ok ? (found ? QStringLiteral("Application cache cleared")
                                       : QStringLiteral("No application cache was present"))
                              : QStringLiteral("One or more protected cache paths could not be cleared"));
    return ok;
}

QString AppManager::carouselStatePath() const
{
    return HumanHome::appStateRoot() + QStringLiteral("/apps/carousel.json");
}

QString AppManager::legacyCarouselStatePath() const
{
    const QString stateRoot = qEnvironmentVariable("NEUTRONOS_STATE_DIR", QStringLiteral("/var/lib/neutronos"));
    return QDir::cleanPath(stateRoot + QStringLiteral("/apps/carousel.json"));
}

bool AppManager::setActiveUser(const QString &username)
{
    const QString clean = safeId(username);
    const QString next = clean.isEmpty() ? QStringLiteral("default") : clean;
    if (next == m_activeCarouselUser)
        return true;
    m_activeCarouselUser = next;
    loadManagedPackageIds();
    rediscoverApps();
    m_favoriteOrder.clear();
    m_favoriteOverrides.clear();
    loadCarouselState();
    rebuildDerivedLists();
    emit appsChanged();
    return true;
}

void AppManager::loadManagedPackageIds()
{
    m_managedPackageIds.clear();
    m_managedRuntimeQmlSources.clear();
    const QString stateRoot = HumanHome::appStateRoot();
    QFile file(QDir(stateRoot).filePath(QStringLiteral("apps/installed.json")));
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonObject packages = QJsonDocument::fromJson(file.readAll()).object()
                                     .value(QStringLiteral("packages")).toObject();
    for (auto iterator = packages.constBegin(); iterator != packages.constEnd(); ++iterator) {
        const QString id = safeId(iterator.key());
        if (id.isEmpty())
            continue;

        m_managedPackageIds.insert(id);

        const QJsonObject package = iterator.value().toObject();
        QString runtimeSource = package.value(QStringLiteral("runtimeQmlSource"))
                                    .toString().trimmed();
        if (runtimeSource.startsWith(QStringLiteral("file://")))
            runtimeSource = QUrl(runtimeSource).toLocalFile();

        const QString cleanRuntimeSource = QDir::cleanPath(runtimeSource);
        const QString packageRuntimeRoot = QDir::cleanPath(
            QDir(stateRoot).filePath(QStringLiteral("apps/runtime/") + id));
        const QString expectedSuffix = QStringLiteral("/payload/qml/apps/") +
            id + QStringLiteral("/Main.qml");

        if (!cleanRuntimeSource.isEmpty() && QFileInfo(cleanRuntimeSource).isAbsolute() &&
                cleanRuntimeSource.startsWith(packageRuntimeRoot + QStringLiteral("/")) &&
                cleanRuntimeSource.endsWith(expectedSuffix) &&
                QFileInfo::exists(cleanRuntimeSource)) {
            m_managedRuntimeQmlSources.insert(id, cleanRuntimeSource);
        }
    }
}

void AppManager::loadCarouselState()
{
    m_pinnedApps.clear();
    m_pinnedApps << QString() << QString() << QString();

    QFile file(carouselStatePath());

    bool migratingLegacy = false;
    if (!file.open(QIODevice::ReadOnly)) {
        if (m_activeCarouselUser == QStringLiteral("default"))
            return;
        file.setFileName(legacyCarouselStatePath());
        if (!file.open(QIODevice::ReadOnly))
            return;
        migratingLegacy = true;
    }

    QJsonParseError error;
    const QJsonDocument document =
        QJsonDocument::fromJson(file.readAll(), &error);

    if (error.error != QJsonParseError::NoError ||
        !document.isObject()) {
        qWarning() << "Invalid carousel state:" << error.errorString();
        return;
    }

    const QJsonObject object = document.object();
    bool migratedLegacyOptimizer = false;

    const QJsonArray pinnedValues =
        object.value(QStringLiteral("pinnedApps")).toArray();

    QSet<QString> loadedPins;
    for (int slot = 0; slot < 3 && slot < pinnedValues.size(); ++slot) {
        QString id = safeId(pinnedValues.at(slot).toString());
        if (id == QStringLiteral("vidoptimizer")) {
            id = QStringLiteral("mediaoptimizer");
            migratedLegacyOptimizer = true;
        }

        if (!id.isEmpty() && !loadedPins.contains(id)) {
            m_pinnedApps[slot] = id;
            loadedPins.insert(id);
        }
    }

    for (const QJsonValue &value :
         object.value(QStringLiteral("favoriteOrder")).toArray()) {
        QString id = safeId(value.toString());
        if (id == QStringLiteral("vidoptimizer")) {
            id = QStringLiteral("mediaoptimizer");
            migratedLegacyOptimizer = true;
        }

        if (!id.isEmpty() && !m_favoriteOrder.contains(id))
            m_favoriteOrder.append(id);
    }

    const QJsonObject overrides =
        object.value(QStringLiteral("favoriteOverrides")).toObject();

    for (auto iterator = overrides.constBegin();
         iterator != overrides.constEnd();
         ++iterator) {
        QString id = safeId(iterator.key());
        if (id == QStringLiteral("vidoptimizer")) {
            id = QStringLiteral("mediaoptimizer");
            migratedLegacyOptimizer = true;
        }

        if (!id.isEmpty())
            m_favoriteOverrides.insert(id, iterator.value().toBool());
    }

    if ((migratedLegacyOptimizer || migratingLegacy) && !saveCarouselState())
        qWarning() << "Unable to persist Media Optimizer carousel migration";
}

bool AppManager::saveCarouselState() const
{
    const QString path = carouselStatePath();

    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;

    QJsonArray order;

    for (const QString &id : m_favoriteOrder)
        order.append(id);

    QJsonObject overrides;

    for (auto iterator = m_favoriteOverrides.constBegin();
         iterator != m_favoriteOverrides.constEnd();
         ++iterator) {
        overrides.insert(iterator.key(), iterator.value());
    }

    QJsonArray pinned;
    for (int slot = 0; slot < 3; ++slot)
        pinned.append(m_pinnedApps.value(slot));

    QJsonObject object;
    object.insert(QStringLiteral("favoriteOrder"), order);
    object.insert(QStringLiteral("favoriteOverrides"), overrides);
    object.insert(QStringLiteral("pinnedApps"), pinned);

    QSaveFile file(path);

    if (!file.open(QIODevice::WriteOnly))
        return false;

    const QByteArray payload =
        QJsonDocument(object).toJson(QJsonDocument::Indented);

    if (file.write(payload) != payload.size())
        return false;

    return file.commit();
}

/*
    ============================================================
                            ACTION HELPERS
    ============================================================
*/

bool AppManager::ensureBackendReady(const QVariantMap &app, QString *message)
{
    const QString id = app.value(QStringLiteral("id")).toString();
    const QString type = app.value(QStringLiteral("type")).toString().trimmed();
    const QString docker = app.value(QStringLiteral("docker")).toString().trimmed();
    const QString service = app.value(QStringLiteral("service")).toString().trimmed();

    // Jellyfin's NeutronOS app is a controller-first QML frontend. Its own
    // bridge/status/setup UI must remain reachable even if the Jellyfin server
    // container/service is stopped, misconfigured, or still starting.
    if (id == QStringLiteral("jellyfin") && type == QStringLiteral("qml")) {
        const bool qmlReady = qmlEntryExists(app);
        if (message) {
            *message = qmlReady
                     ? QStringLiteral("Jellyfin frontend is ready; backend state will be handled inside the app")
                     : QStringLiteral("Jellyfin QML entry is missing");
        }
        return qmlReady;
    }

    // Docker is intentionally disabled at boot. Start the engine only after
    // the user explicitly launches a Docker-backed app.
    if (!docker.isEmpty() && systemdUnitExists(QStringLiteral("docker.service")) &&
        !systemdUnitActive(QStringLiteral("docker.service"))) {
        QString dockerStartMessage;
        if (!runSystemdAction(QStringLiteral("docker.service"),
                              QStringLiteral("start"),
                              &dockerStartMessage)) {
            if (message)
                *message = dockerStartMessage.isEmpty()
                         ? QStringLiteral("Unable to start Docker on demand")
                         : dockerStartMessage;
            return false;
        }
        if (!waitForSystemdActive(QStringLiteral("docker.service"), 15000)) {
            if (message)
                *message = QStringLiteral("Docker did not become ready");
            return false;
        }
    }

    if (id == QStringLiteral("qbittorrent")) {
        if (dockerContainerExists(QStringLiteral("qbittorrent"))) {
            if (!dockerContainerRunning(QStringLiteral("qbittorrent"))) {
                QString startMessage;
                if (!runDockerAction(QStringLiteral("qbittorrent"), QStringLiteral("start"), &startMessage)) {
                    if (message) *message = startMessage;
                    return false;
                }
            }
            const bool ready = waitForDockerRunning(QStringLiteral("qbittorrent"), 15000);
            if (message) *message = ready ? QStringLiteral("qBittorrent container is ready")
                                         : QStringLiteral("qBittorrent container did not start");
            return ready;
        }
        const QStringList qbitUnits{QStringLiteral("qbittorrent.service"),
                                    QStringLiteral("qbittorrent-nox.service")};
        for (const QString &unit : qbitUnits) {
            if (!systemdUnitExists(unit))
                continue;
            if (!systemdUnitActive(unit)) {
                QString startMessage;
                if (!runSystemdAction(unit, QStringLiteral("start"), &startMessage)) {
                    if (message) *message = startMessage;
                    return false;
                }
            }
            const bool ready = waitForSystemdActive(unit, 15000);
            if (message) *message = ready ? QStringLiteral("qBittorrent service is ready")
                                         : QStringLiteral("qBittorrent service did not start");
            return ready;
        }
    }

    if (!docker.isEmpty() && dockerContainerExists(docker)) {
        if (dockerContainerRunning(docker)) {
            if (message) *message = QStringLiteral("Container already running");
            return true;
        }

        QString startMessage;
        if (!runDockerAction(docker, QStringLiteral("start"), &startMessage)) {
            if (message) *message = startMessage.isEmpty()
                                 ? QStringLiteral("Unable to start container: ") + docker
                                 : startMessage;
            return false;
        }

        const bool ready = waitForDockerRunning(docker, 12000);
        if (message) *message = ready
                             ? QStringLiteral("Container is ready")
                             : QStringLiteral("Container did not become ready: ") + docker;
        return ready;
    }

    if (!service.isEmpty() && systemdUnitExists(service)) {
        if (systemdUnitActive(service)) {
            if (message) *message = QStringLiteral("Service already running");
            return true;
        }

        QString startMessage;
        if (!runSystemdAction(service, QStringLiteral("start"), &startMessage)) {
            if (message) *message = startMessage.isEmpty()
                                 ? QStringLiteral("Unable to start service: ") + service
                                 : startMessage;
            return false;
        }

        const bool ready = waitForSystemdActive(service, 12000);
        if (message) *message = ready
                             ? QStringLiteral("Service is ready")
                             : QStringLiteral("Service did not become ready: ") + service;
        return ready;
    }

    if (message) {
        *message = id.isEmpty()
                 ? QStringLiteral("No service preparation required")
                 : QStringLiteral("Ready to open ") + id;
    }
    return true;
}

bool AppManager::waitForSystemdActive(const QString &unit, int timeoutMs) const
{
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < timeoutMs) {
        if (systemdUnitActive(unit))
            return true;
        QThread::msleep(250);
    }
    return systemdUnitActive(unit);
}

bool AppManager::waitForDockerRunning(const QString &container, int timeoutMs) const
{
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < timeoutMs) {
        if (dockerContainerRunning(container))
            return true;
        QThread::msleep(250);
    }
    return dockerContainerRunning(container);
}

bool AppManager::runSystemdAction(const QString &unit, const QString &actionName, QString *message)
{
    const QString action = actionName.trimmed().toLower();

    if (unit.isEmpty()) {
        if (message)
            *message = QStringLiteral("Missing systemd unit");
        return false;
    }

    QString systemctlAction;

    if (action == QStringLiteral("start") || action == QStringLiteral("open"))
        systemctlAction = QStringLiteral("start");
    else if (action == QStringLiteral("stop"))
        systemctlAction = QStringLiteral("stop");
    else if (action == QStringLiteral("kill"))
        systemctlAction = QStringLiteral("kill");
    else if (action == QStringLiteral("restart"))
        systemctlAction = QStringLiteral("restart");
    else if (action == QStringLiteral("logs")) {
        if (message)
            *message = QStringLiteral("Logs should be opened through Logs app for ") + unit;
        return true;
    } else if (action == QStringLiteral("status")) {
        systemctlAction = QStringLiteral("status");
    } else {
        if (message)
            *message = QStringLiteral("Unsupported systemd action: ") + action;
        return false;
    }

    QString out;
    QString err;

    QStringList systemctlArguments;
    const bool qbitUnit = unit == QStringLiteral("qbittorrent.service") ||
                          unit == QStringLiteral("qbittorrent-nox.service");

    int code = -1;
    if (systemctlAction == QStringLiteral("kill") && qbitUnit) {
        // Killing a process governed by Restart= can make systemd launch it
        // again. Stop the unit first, then force-kill any remaining process.
        code = runProcess(
            QStringLiteral("systemctl"),
            {QStringLiteral("stop"), unit},
            10000,
            &out,
            &err
        );
        QString killOut;
        QString killErr;
        const int killCode = runProcess(
            QStringLiteral("systemctl"),
            {QStringLiteral("kill"), QStringLiteral("--kill-who=all"),
             QStringLiteral("--signal=SIGKILL"), unit},
            5000,
            &killOut,
            &killErr
        );
        if (code == 0 || killCode == 0)
            code = 0;
        if (!killOut.trimmed().isEmpty()) {
            out += QLatin1Char('\n');
            out += killOut;
        }
        if (!killErr.trimmed().isEmpty()) {
            err += QLatin1Char('\n');
            err += killErr;
        }
    } else {
        if (systemctlAction == QStringLiteral("kill"))
            systemctlArguments << QStringLiteral("kill") << QStringLiteral("--kill-who=all")
                               << QStringLiteral("--signal=SIGKILL") << unit;
        else
            systemctlArguments << systemctlAction << unit;

        code = runProcess(
            QStringLiteral("systemctl"),
            systemctlArguments,
            10000,
            &out,
            &err
        );
    }

    if (message) {
        const QString cleanOut = out.trimmed();
        const QString cleanErr = err.trimmed();
        *message = code == 0
                   ? (cleanOut.isEmpty() ? QStringLiteral("systemctl action completed") : cleanOut)
                   : (cleanErr.isEmpty() ? QStringLiteral("systemctl action failed") : cleanErr);
    }

    return code == 0;
}

bool AppManager::runDockerAction(const QString &container, const QString &actionName, QString *message)
{
    const QString action = actionName.trimmed().toLower();

    if (container.isEmpty()) {
        if (message)
            *message = QStringLiteral("Missing Docker container");
        return false;
    }

    QString dockerAction;

    if (action == QStringLiteral("start") || action == QStringLiteral("open"))
        dockerAction = QStringLiteral("start");
    else if (action == QStringLiteral("stop"))
        dockerAction = QStringLiteral("stop");
    else if (action == QStringLiteral("kill"))
        dockerAction = QStringLiteral("kill");
    else if (action == QStringLiteral("restart"))
        dockerAction = QStringLiteral("restart");
    else if (action == QStringLiteral("logs")) {
        if (message)
            *message = QStringLiteral("Logs should be opened through Logs app for ") + container;
        return true;
    } else {
        if (message)
            *message = QStringLiteral("Unsupported Docker action: ") + action;
        return false;
    }

    QString out;
    QString err;

    int code = -1;
    if (dockerAction == QStringLiteral("stop") || dockerAction == QStringLiteral("kill")) {
        // Preserve the configured restart policy. An explicit Docker stop is
        // already treated as an intentional stop; mutating --restart to "no"
        // silently disabled qBittorrent autostart across later boots.
        if (dockerAction == QStringLiteral("kill")) {
            code = runProcess(
                QStringLiteral("docker"),
                {QStringLiteral("kill"), container},
                8000,
                &out,
                &err
            );
        } else {
            code = runProcess(
                QStringLiteral("docker"),
                {QStringLiteral("stop"), QStringLiteral("--time"), QStringLiteral("8"), container},
                12000,
                &out,
                &err
            );
            if (code != 0) {
                QString killOut;
                QString killErr;
                const int killCode = runProcess(
                    QStringLiteral("docker"),
                    {QStringLiteral("kill"), container},
                    8000,
                    &killOut,
                    &killErr
                );
                if (!killOut.trimmed().isEmpty()) {
                    out += QLatin1Char('\n');
                    out += killOut;
                }
                if (!killErr.trimmed().isEmpty()) {
                    err += QLatin1Char('\n');
                    err += killErr;
                }
                code = killCode;
            }
        }
    } else {
        code = runProcess(
            QStringLiteral("docker"),
            QStringList() << dockerAction << container,
            12000,
            &out,
            &err
        );
    }

    if (message) {
        const QString cleanOut = out.trimmed();
        const QString cleanErr = err.trimmed();
        *message = code == 0
                   ? (cleanOut.isEmpty() ? QStringLiteral("docker action completed") : cleanOut)
                   : (cleanErr.isEmpty() ? QStringLiteral("docker action failed") : cleanErr);
    }

    return code == 0;
}

/*
    ============================================================
                            QML ENTRY HELPERS
    ============================================================
*/

QString AppManager::resolveQmlEntryPath(const QVariantMap &app) const
{
    QString entry = app.value(QStringLiteral("entry")).toString().trimmed();

    if (entry.startsWith(QStringLiteral("file://")))
        entry = QUrl(entry).toLocalFile();

    if (!entry.isEmpty()) {
        if (QFileInfo(entry).isAbsolute())
            return QDir::cleanPath(entry);

        if (entry.startsWith(QStringLiteral("qml/apps/")))
            return QDir::cleanPath(neutronRootPath() + QStringLiteral("/") + entry);

        if (entry.startsWith(QStringLiteral("apps/")))
            return QDir::cleanPath(appsRootPath() + QStringLiteral("/") + entry.mid(QStringLiteral("apps/").length()));

        return QDir::cleanPath(appsRootPath() + QStringLiteral("/") + entry);
    }

    QString source = app.value(QStringLiteral("qmlSource")).toString().trimmed();

    if (source.startsWith(QStringLiteral("file://")))
        source = QUrl(source).toLocalFile();

    if (source.isEmpty())
        source = safeId(app.value(QStringLiteral("id")).toString()) + QStringLiteral("/Main.qml");

    if (QFileInfo(source).isAbsolute())
        return QDir::cleanPath(source);

    if (source.startsWith(QStringLiteral("qml/apps/")))
        return QDir::cleanPath(neutronRootPath() + QStringLiteral("/") + source);

    if (source.startsWith(QStringLiteral("apps/")))
        return QDir::cleanPath(appsRootPath() + QStringLiteral("/") + source.mid(QStringLiteral("apps/").length()));

    return QDir::cleanPath(appsRootPath() + QStringLiteral("/") + source);
}

QString AppManager::resolveQmlSource(const QVariantMap &app) const
{
    QString source = app.value(QStringLiteral("qmlSource")).toString().trimmed();

    if (!source.isEmpty())
        return source;

    QString entry = app.value(QStringLiteral("entry")).toString().trimmed();

    if (entry.startsWith(QStringLiteral("file://")))
        entry = QUrl(entry).toLocalFile();

    const QString root = appsRootPath() + QStringLiteral("/");

    if (!entry.isEmpty() && entry.startsWith(root))
        return entry.mid(root.length());

    const QString id = safeId(app.value(QStringLiteral("id")).toString());

    if (!id.isEmpty())
        return id + QStringLiteral("/Main.qml");

    return QString();
}

bool AppManager::qmlEntryExists(const QVariantMap &app) const
{
    const QString entry = resolveQmlEntryPath(app);
    return !entry.isEmpty() && QFileInfo::exists(entry);
}

/*
    ============================================================
                            UTILITIES
    ============================================================
*/

QVariantList AppManager::stringListToVariantList(const QStringList &values) const
{
    QVariantList list;

    for (const QString &value : values)
        list.append(value);

    return list;
}

QString AppManager::cleanDesktopExec(const QString &exec) const
{
    QString cleaned = exec;

    cleaned.remove(QRegularExpression(QStringLiteral("%[fFuUdDnNickvm]")));
    cleaned = cleaned.simplified();

    return cleaned;
}

QString AppManager::firstCommandToken(const QString &command) const
{
    QString cleaned = command.trimmed();

    if (cleaned.isEmpty())
        return QString();

    if (cleaned.startsWith(QStringLiteral("\""))) {
        const int end = cleaned.indexOf(QStringLiteral("\""), 1);

        if (end > 1)
            return cleaned.mid(1, end - 1);
    }

    return cleaned.split(QStringLiteral(" ")).first();
}

QString AppManager::safeId(const QString &value) const
{
    QString id = value.trimmed().toLower();

    id.replace(QRegularExpression(QStringLiteral("[^a-z0-9_-]+")), QStringLiteral("_"));
    id.replace(QRegularExpression(QStringLiteral("_+")), QStringLiteral("_"));

    while (id.startsWith(QStringLiteral("_")))
        id.remove(0, 1);

    while (id.endsWith(QStringLiteral("_")))
        id.chop(1);

    return id;
}

bool AppManager::commandExists(const QString &command) const
{
    if (command.trimmed().isEmpty())
        return false;

    QFileInfo info(command);

    if (info.isAbsolute())
        return info.exists() && info.isExecutable();

    return runProcess(QStringLiteral("which"), QStringList() << command, 700) == 0;
}

bool AppManager::systemdUnitExists(const QString &unit) const
{
    if (!m_runtimeStatusQueriesEnabled)
        return false;
    if (unit.trimmed().isEmpty())
        return false;

    QString output;
    QString error;

    const int code = runProcess(
        QStringLiteral("systemctl"),
        QStringList() << QStringLiteral("list-unit-files") << unit << QStringLiteral("--no-legend"),
        1500,
        &output,
        &error
    );

    Q_UNUSED(error);

    if (code != 0 && output.trimmed().isEmpty())
        return false;

    return output.contains(unit);
}

bool AppManager::systemdUnitActive(const QString &unit) const
{
    if (!m_runtimeStatusQueriesEnabled)
        return false;
    if (unit.trimmed().isEmpty())
        return false;

    return runProcess(
        QStringLiteral("systemctl"),
        QStringList() << QStringLiteral("is-active") << QStringLiteral("--quiet") << unit,
        900
    ) == 0;
}

bool AppManager::dockerExists() const
{
    return commandExists(QStringLiteral("docker")) ||
           systemdUnitExists(QStringLiteral("docker.service"));
}

bool AppManager::dockerContainerExists(const QString &name) const
{
    if (!m_runtimeStatusQueriesEnabled)
        return false;
    if (name.trimmed().isEmpty() || !commandExists(QStringLiteral("docker")))
        return false;

    QString output;

    const int code = runProcess(
        QStringLiteral("docker"),
        QStringList() << QStringLiteral("ps") << QStringLiteral("-a") << QStringLiteral("--format") << QStringLiteral("{{.Names}}"),
        2200,
        &output
    );

    if (code != 0 && output.trimmed().isEmpty())
        return false;

    const QStringList lines = output.split(QStringLiteral("\n"));

    for (const QString &line : lines) {
        const QString cleanLine = line.trimmed();

        if (cleanLine.compare(name, Qt::CaseInsensitive) == 0)
            return true;
    }

    return false;
}

bool AppManager::dockerContainerRunning(const QString &name) const
{
    if (!m_runtimeStatusQueriesEnabled)
        return false;
    if (name.trimmed().isEmpty() || !commandExists(QStringLiteral("docker")))
        return false;

    QString output;

    const int code = runProcess(
        QStringLiteral("docker"),
        QStringList() << QStringLiteral("inspect") << QStringLiteral("-f") << QStringLiteral("{{.State.Running}}") << name,
        2200,
        &output
    );

    if (code != 0)
        return false;

    return output.trimmed() == QStringLiteral("true");
}
