#include "HumanAccountPolicy.h"
#include "AssetManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <QByteArray>
#include <QRegularExpression>
#include <QDebug>

/*
    ============================================================
                              HELPERS
    ============================================================
*/

static QString cleanRuntimePath(const QString &path)
{
    return QDir::cleanPath(path);
}

static QString homeNeutronRoot()
{
    return cleanRuntimePath(QDir::homePath() + QStringLiteral("/NeutronOS"));
}

static bool hasMainQml(const QString &root)
{
    return QFileInfo::exists(
        cleanRuntimePath(root + QStringLiteral("/qml/Main.qml"))
    );
}

static QString resolveRuntimeRoot()
{
    const QByteArray envRoot = qgetenv("NEUTRONOS_ROOT");

    if (!envRoot.isEmpty()) {
        const QString envPath = cleanRuntimePath(QString::fromLocal8Bit(envRoot));

        if (hasMainQml(envPath))
            return envPath;

        qWarning() << "AssetManager: NEUTRONOS_ROOT set but qml/Main.qml not found:" << envPath;
    }

    const QString homeRoot = homeNeutronRoot();

    if (hasMainQml(homeRoot))
        return homeRoot;

    const QString currentRoot = cleanRuntimePath(QDir::currentPath());

    if (hasMainQml(currentRoot))
        return currentRoot;

    const QString appDir = cleanRuntimePath(QCoreApplication::applicationDirPath());
    const QString appParentRoot = cleanRuntimePath(QDir(appDir).absoluteFilePath(QStringLiteral("..")));

    if (hasMainQml(appParentRoot))
        return appParentRoot;

    return homeRoot;
}

/*
    ============================================================
                            CONSTRUCTION
    ============================================================
*/

AssetManager::AssetManager(QObject *parent)
    : QObject(parent)
{
    resolveRuntimePaths();
    ensureThemeDirectories();
}

/*
    ============================================================
                            PATH PROPERTIES
    ============================================================
*/

QString AssetManager::neutronRootPath() const
{
    return m_neutronRootPath;
}

QString AssetManager::qmlPath() const
{
    return m_qmlPath;
}

QString AssetManager::appsPath() const
{
    return m_appsPath;
}

QString AssetManager::themePath() const
{
    return m_themePath;
}

QString AssetManager::themeUrl() const
{
    return fileUrlForPath(m_themePath);
}

QString AssetManager::usersPath() const
{
    return m_usersPath;
}

QString AssetManager::iconsPath() const
{
    return m_iconsPath;
}

QString AssetManager::postersPath() const
{
    return m_postersPath;
}

/*
    ============================================================
                            THEME RESOLUTION
    ============================================================
*/

QString AssetManager::themeFile(const QString &relativePath) const
{
    const QString clean = cleanAssetPath(relativePath);

    if (clean.isEmpty())
        return QString();

    /*
        Keep already-valid resolved URLs intact. This preserves compatibility
        with Image providers, remote images, and any legacy qrc sources while
        keeping NeutronOS itself filesystem-first.
    */
    if (isResolvedUrl(clean))
        return clean;

    if (clean.startsWith(QStringLiteral("apps/icons/"))) {
        const QString installed = cleanRuntimePath(
            m_installedIconsPath + QLatin1Char('/') + QFileInfo(clean).fileName());
        if (QFileInfo::exists(installed))
            return fileUrlForPath(installed);
    } else if (clean.startsWith(QStringLiteral("apps/posters/"))) {
        const QString installed = cleanRuntimePath(
            m_installedPostersPath + QLatin1Char('/') + QFileInfo(clean).fileName());
        if (QFileInfo::exists(installed))
            return fileUrlForPath(installed);
    }

    const QString local = localThemePath(clean);

    if (!QFileInfo::exists(local)) {
        if (QFileInfo(clean).completeBaseName().compare(QStringLiteral("atom"), Qt::CaseInsensitive) == 0) {
            const QStringList atomCandidates = {QStringLiteral("atom.svg"), QStringLiteral("atom.png"),
                                                QStringLiteral("atom.jpeg"), QStringLiteral("atom.jpg")};
            for (const QString &candidate : atomCandidates) {
                const QString atomPath = localThemePath(candidate);
                if (QFileInfo::exists(atomPath))
                    return fileUrlForPath(atomPath);
            }
        }
        return QString();
    }

    return fileUrlForPath(local);
}

QString AssetManager::resolvePath(const QString &relativePath) const
{
    return themeLocalFile(relativePath);
}

QString AssetManager::themeLocalFile(const QString &relativePath) const
{
    const QString clean = cleanAssetPath(relativePath);

    if (clean.isEmpty())
        return QString();

    const QString localFromUrl = localPathFromUrl(clean);

    if (!localFromUrl.isEmpty()) {
        const QString localClean = cleanAbsolutePath(localFromUrl);

        if (QFileInfo::exists(localClean))
            return localClean;

        return QString();
    }

    QFileInfo absoluteInfo(clean);

    if (absoluteInfo.isAbsolute()) {
        const QString absolute = cleanAbsolutePath(clean);

        if (QFileInfo::exists(absolute))
            return absolute;

        return QString();
    }

    const QString local = localThemePath(clean);

    if (!QFileInfo::exists(local))
        return QString();

    return local;
}

/*
    ============================================================
                            APP ICONS / POSTERS
    ============================================================
*/

QString AssetManager::appIcon(const QString &name) const
{
    const QString path = appIconPath(name);

    if (path.isEmpty())
        return QString();

    return fileUrlForPath(path);
}

QString AssetManager::appPoster(const QString &name) const
{
    const QString path = appPosterPath(name);

    if (path.isEmpty())
        return QString();

    return fileUrlForPath(path);
}

QString AssetManager::appIconPath(const QString &name) const
{
    QString clean = cleanAssetPath(name);

    if (clean.isEmpty())
        return QString();

    const QString localFromUrl = localPathFromUrl(clean);

    if (!localFromUrl.isEmpty()) {
        const QString localClean = cleanAbsolutePath(localFromUrl);

        if (QFileInfo::exists(localClean))
            return localClean;

        return QString();
    }

    QFileInfo info(clean);

    if (info.isAbsolute()) {
        const QString absolute = cleanAbsolutePath(clean);

        if (QFileInfo::exists(absolute))
            return absolute;

        return QString();
    }

    /*
        Accept full theme-relative paths for compatibility, but never route
        quick actions into a separate quickactions folder.
    */
    if (clean.startsWith(QStringLiteral("apps/icons/"))) {
        const QString installed = cleanRuntimePath(
            m_installedIconsPath + QLatin1Char('/') + QFileInfo(clean).fileName());
        if (QFileInfo::exists(installed))
            return installed;
        const QString local = localThemePath(clean);

        if (QFileInfo::exists(local))
            return local;

        return QString();
    }

    if (clean.startsWith(QStringLiteral("icons/"))) {
        clean = clean.mid(QStringLiteral("icons/").size());
    }

    if (clean.startsWith(QStringLiteral("quickactions/")) ||
            clean.startsWith(QStringLiteral("actions/icons/"))) {
        clean = QFileInfo(clean).fileName();
    }

    clean = normalizeAssetName(clean);

    if (clean.isEmpty())
        return QString();

    if (!isImageFileName(clean))
        clean += QStringLiteral(".png");

    const QString installed = cleanRuntimePath(m_installedIconsPath + QStringLiteral("/") + clean);

    if (QFileInfo::exists(installed))
        return installed;

    const QString local = cleanRuntimePath(m_iconsPath + QStringLiteral("/") + clean);

    if (QFileInfo::exists(local))
        return local;

    /*
        Case-insensitive fallback for names like Jellyfin.png vs jellyfin.png.
    */
    QDir iconsDir(m_iconsPath);
    const QFileInfoList entries = iconsDir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);

    for (const QFileInfo &entry : entries) {
        if (entry.fileName().compare(clean, Qt::CaseInsensitive) == 0)
            return cleanRuntimePath(entry.absoluteFilePath());
    }

    return QString();
}

QString AssetManager::appPosterPath(const QString &name) const
{
    QString clean = cleanAssetPath(name);

    if (clean.isEmpty())
        return QString();

    const QString localFromUrl = localPathFromUrl(clean);

    if (!localFromUrl.isEmpty()) {
        const QString localClean = cleanAbsolutePath(localFromUrl);

        if (QFileInfo::exists(localClean))
            return localClean;

        return QString();
    }

    QFileInfo info(clean);

    if (info.isAbsolute()) {
        const QString absolute = cleanAbsolutePath(clean);

        if (QFileInfo::exists(absolute))
            return absolute;

        return QString();
    }

    if (clean.startsWith(QStringLiteral("apps/posters/"))) {
        const QString installed = cleanRuntimePath(
            m_installedPostersPath + QLatin1Char('/') + QFileInfo(clean).fileName());
        if (QFileInfo::exists(installed))
            return installed;
        const QString local = localThemePath(clean);

        if (QFileInfo::exists(local))
            return local;

        return QString();
    }

    if (clean.startsWith(QStringLiteral("posters/"))) {
        clean = clean.mid(QStringLiteral("posters/").size());
    }

    if (clean.startsWith(QStringLiteral("quickactions/")) ||
            clean.startsWith(QStringLiteral("actions/posters/"))) {
        clean = QFileInfo(clean).fileName();
    }

    clean = normalizeAssetName(clean);

    if (clean.isEmpty())
        return QString();

    if (!isImageFileName(clean))
        clean += QStringLiteral(".png");

    const QString installed = cleanRuntimePath(m_installedPostersPath + QStringLiteral("/") + clean);

    if (QFileInfo::exists(installed))
        return installed;

    const QString local = cleanRuntimePath(m_postersPath + QStringLiteral("/") + clean);

    if (QFileInfo::exists(local))
        return local;

    QDir postersDir(m_postersPath);
    const QFileInfoList entries = postersDir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);

    for (const QFileInfo &entry : entries) {
        if (entry.fileName().compare(clean, Qt::CaseInsensitive) == 0)
            return cleanRuntimePath(entry.absoluteFilePath());
    }

    return QString();
}

/*
    ============================================================
                            USER / BACKGROUND / LOGO
    ============================================================
*/

QString AssetManager::userIcon() const
{
    return userIcon(QStringLiteral("user_icon.png"));
}

QString AssetManager::userIcon(const QString &fileName) const
{
    QString clean = cleanAssetPath(fileName);

    if (clean.isEmpty())
        clean = QStringLiteral("user_icon.png");

    const QString localFromUrl = localPathFromUrl(clean);

    if (!localFromUrl.isEmpty()) {
        const QString localClean = cleanAbsolutePath(localFromUrl);

        if (QFileInfo::exists(localClean))
            return fileUrlForPath(localClean);

        return QString();
    }

    QFileInfo info(clean);

    if (info.isAbsolute()) {
        const QString absolute = cleanAbsolutePath(clean);

        if (QFileInfo::exists(absolute))
            return fileUrlForPath(absolute);

        return QString();
    }

    if (clean.startsWith(QStringLiteral("users/")))
        clean = clean.mid(QStringLiteral("users/").size());

    if (!isImageFileName(clean))
        clean += QStringLiteral(".png");

    const QString local = cleanRuntimePath(m_usersPath + QStringLiteral("/") + clean);

    if (QFileInfo::exists(local))
        return fileUrlForPath(local);

    return QString();
}

QString AssetManager::background() const
{
    return background(QStringLiteral("background.png"));
}

QString AssetManager::background(const QString &fileName) const
{
    QString clean = cleanAssetPath(fileName);

    if (clean.isEmpty())
        clean = QStringLiteral("background.png");

    return themeFile(clean);
}

QString AssetManager::logo() const
{
    return firstThemeAsset({QStringLiteral("atom.svg"), QStringLiteral("atom.png"),
                            QStringLiteral("atom.jpeg"), QStringLiteral("atom.jpg")});
}

QString AssetManager::logo(const QString &fileName) const
{
    QString clean = cleanAssetPath(fileName);

    if (clean.isEmpty())
        return logo();

    if (QFileInfo(clean).completeBaseName().compare(QStringLiteral("atom"), Qt::CaseInsensitive) == 0)
        return logo();

    return themeFile(clean);
}

QString AssetManager::firstThemeAsset(const QStringList &candidates) const
{
    for (const QString &candidate : candidates) {
        const QString resolved = themeFile(candidate);
        if (!resolved.isEmpty())
            return resolved;
    }
    return QString();
}

/*
    ============================================================
                            DROP-IN APP PATHS
    ============================================================
*/

QString AssetManager::appRoot(const QString &appId) const
{
    const QString cleanId = normalizeAppId(appId);

    if (cleanId.isEmpty())
        return QString();

    const QString installed = cleanRuntimePath(
        m_installedAppsPath + QStringLiteral("/") + cleanId);
    if (QFileInfo::exists(installed + QStringLiteral("/Main.qml")))
        return installed;
    return cleanRuntimePath(m_appsPath + QStringLiteral("/") + cleanId);
}

QString AssetManager::appMainQml(const QString &appId) const
{
    const QString root = appRoot(appId);

    if (root.isEmpty())
        return QString();

    return cleanRuntimePath(root + QStringLiteral("/Main.qml"));
}

QString AssetManager::appMainUrl(const QString &appId) const
{
    const QString mainPath = appMainQml(appId);

    if (mainPath.isEmpty())
        return QString();

    if (!QFileInfo::exists(mainPath))
        return QString();

    return fileUrlForPath(mainPath);
}

bool AssetManager::appExists(const QString &appId) const
{
    const QString mainPath = appMainQml(appId);

    if (mainPath.isEmpty())
        return false;

    return QFileInfo::exists(mainPath);
}

/*
    ============================================================
                            EXISTENCE
    ============================================================
*/

bool AssetManager::themeExists(const QString &relativePath) const
{
    const QString path = themeLocalFile(relativePath);

    return !path.isEmpty() && QFileInfo::exists(path);
}

bool AssetManager::fileExists(const QString &pathOrUrl) const
{
    const QString clean = cleanAssetPath(pathOrUrl);

    if (clean.isEmpty())
        return false;

    if (clean.startsWith(QStringLiteral("qrc:/")) ||
            clean.startsWith(QStringLiteral("image://")) ||
            clean.startsWith(QStringLiteral("http://")) ||
            clean.startsWith(QStringLiteral("https://"))) {
        return true;
    }

    const QString localFromUrl = localPathFromUrl(clean);

    if (!localFromUrl.isEmpty())
        return QFileInfo::exists(cleanAbsolutePath(localFromUrl));

    QFileInfo info(clean);

    if (info.isAbsolute())
        return info.exists();

    return themeExists(clean);
}

/*
    ============================================================
                            QML HELPERS
    ============================================================
*/

QString AssetManager::cleanAssetPath(const QString &path) const
{
    QString clean = path.trimmed();

    if (clean.isEmpty())
        return QString();

    clean.replace(QStringLiteral("\\"), QStringLiteral("/"));

    while (clean.startsWith(QStringLiteral("./")))
        clean = clean.mid(2);

    while (clean.contains(QStringLiteral("//")) &&
           !clean.startsWith(QStringLiteral("file://")) &&
           !clean.startsWith(QStringLiteral("http://")) &&
           !clean.startsWith(QStringLiteral("https://")) &&
           !clean.startsWith(QStringLiteral("image://"))) {
        clean.replace(QStringLiteral("//"), QStringLiteral("/"));
    }

    return clean.trimmed();
}

QString AssetManager::normalizeAssetNameForQml(const QString &name) const
{
    return normalizeAssetName(name);
}

QString AssetManager::normalizeAppIdForQml(const QString &appId) const
{
    return normalizeAppId(appId);
}

void AssetManager::refresh()
{
    resolveRuntimePaths();
    ensureThemeDirectories();

    emit themeChanged();
    emit assetsChanged();
}

void AssetManager::ensureDirectories()
{
    ensureThemeDirectories();
}

/*
    ============================================================
                            PRIVATE PATH SETUP
    ============================================================
*/

void AssetManager::resolveRuntimePaths()
{
    m_neutronRootPath = resolveRuntimeRoot();
    m_qmlPath = cleanRuntimePath(m_neutronRootPath + QStringLiteral("/qml"));
    m_appsPath = cleanRuntimePath(m_qmlPath + QStringLiteral("/apps"));

    m_themePath = cleanRuntimePath(m_neutronRootPath + QStringLiteral("/themes/Default"));
    m_usersPath = cleanRuntimePath(m_themePath + QStringLiteral("/users"));
    m_iconsPath = cleanRuntimePath(m_themePath + QStringLiteral("/apps/icons"));
    m_postersPath = cleanRuntimePath(m_themePath + QStringLiteral("/apps/posters"));
    const QString stateRoot = HumanHome::appStateRoot();
    const QString payloadRoot = cleanRuntimePath(
        stateRoot + QStringLiteral("/apps/payload"));
    m_installedAppsPath = payloadRoot + QStringLiteral("/qml/apps");
    m_installedIconsPath = payloadRoot + QStringLiteral("/themes/Default/apps/icons");
    m_installedPostersPath = payloadRoot + QStringLiteral("/themes/Default/apps/posters");
}

void AssetManager::ensureThemeDirectories() const
{
    const QStringList dirs = {
        m_neutronRootPath,
        m_qmlPath,
        m_appsPath,
        m_themePath,
        m_usersPath,
        cleanRuntimePath(m_themePath + QStringLiteral("/apps")),
        m_iconsPath,
        m_postersPath
    };

    for (const QString &path : dirs) {
        const QFileInfo info(path);
        if (!info.isDir() || !info.isReadable())
            qWarning() << "AssetManager: required packaged directory is unavailable:" << path;
    }
}

/*
    ============================================================
                            PRIVATE CLEANUP
    ============================================================
*/

QString AssetManager::cleanRelativePath(const QString &relativePath) const
{
    QString clean = cleanAssetPath(relativePath);

    if (clean.isEmpty())
        return QString();

    const QString localFromUrl = localPathFromUrl(clean);

    if (!localFromUrl.isEmpty())
        clean = localFromUrl;

    QFileInfo info(clean);

    if (info.isAbsolute())
        return cleanRuntimePath(info.absoluteFilePath());

    clean = cleanRuntimePath(clean);

    while (clean.startsWith(QStringLiteral("../")))
        clean = clean.mid(3);

    while (clean.startsWith(QStringLiteral("/")))
        clean = clean.mid(1);

    if (clean == QStringLiteral("."))
        return QString();

    return clean;
}

QString AssetManager::cleanAbsolutePath(const QString &path) const
{
    QString clean = cleanAssetPath(path);

    if (clean.isEmpty())
        return QString();

    const QString localFromUrl = localPathFromUrl(clean);

    if (!localFromUrl.isEmpty())
        clean = localFromUrl;

    QFileInfo info(clean);

    if (info.isAbsolute())
        return cleanRuntimePath(info.absoluteFilePath());

    return cleanRuntimePath(clean);
}

QString AssetManager::normalizeAssetName(const QString &name) const
{
    QString clean = cleanAssetPath(name);

    if (clean.isEmpty())
        return QString();

    if (isResolvedUrl(clean))
        return clean;

    clean = QFileInfo(clean).fileName().trimmed();

    if (clean.isEmpty())
        return QString();

    /*
        Keep filename case intact because the user already has mixed-case
        assets such as Jellyfin.png and Jellyfin.fill.png.
    */
    clean.replace(QRegularExpression(QStringLiteral("[\\r\\n\\t]+")), QStringLiteral(""));
    clean.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral("_"));

    return clean;
}

QString AssetManager::normalizeAppId(const QString &appId) const
{
    QString clean = cleanAssetPath(appId).trimmed().toLower();

    if (clean.isEmpty())
        return QString();

    if (clean.contains(QStringLiteral("/")))
        clean = QFileInfo(clean).fileName().toLower();

    clean.replace(QRegularExpression(QStringLiteral("[^a-z0-9_\\-]+")), QStringLiteral("-"));
    clean.replace(QRegularExpression(QStringLiteral("-+")), QStringLiteral("-"));

    while (clean.startsWith(QStringLiteral("-")))
        clean = clean.mid(1);

    while (clean.endsWith(QStringLiteral("-")))
        clean.chop(1);

    return clean;
}

QString AssetManager::localThemePath(const QString &relativePath) const
{
    const QString clean = cleanRelativePath(relativePath);

    if (clean.isEmpty())
        return QString();

    QFileInfo info(clean);

    if (info.isAbsolute())
        return cleanRuntimePath(info.absoluteFilePath());

    return cleanRuntimePath(m_themePath + QStringLiteral("/") + clean);
}

QString AssetManager::localAppPath(const QString &appId, const QString &relativePath) const
{
    const QString root = appRoot(appId);

    if (root.isEmpty())
        return QString();

    const QString cleanRelative = cleanRelativePath(relativePath);

    if (cleanRelative.isEmpty())
        return root;

    return cleanRuntimePath(root + QStringLiteral("/") + cleanRelative);
}

QString AssetManager::fileUrlForPath(const QString &path) const
{
    const QString clean = cleanAbsolutePath(path);

    if (clean.isEmpty())
        return QString();

    return QUrl::fromLocalFile(clean).toString();
}

QString AssetManager::localPathFromUrl(const QString &pathOrUrl) const
{
    const QString clean = cleanAssetPath(pathOrUrl);

    if (!clean.startsWith(QStringLiteral("file://")))
        return QString();

    const QUrl url(clean);

    if (!url.isValid() || !url.isLocalFile())
        return QString();

    return cleanRuntimePath(url.toLocalFile());
}

bool AssetManager::isResolvedUrl(const QString &path) const
{
    const QString clean = cleanAssetPath(path).toLower();

    return clean.startsWith(QStringLiteral("file://")) ||
           clean.startsWith(QStringLiteral("qrc:/")) ||
           clean.startsWith(QStringLiteral("image://")) ||
           clean.startsWith(QStringLiteral("http://")) ||
           clean.startsWith(QStringLiteral("https://"));
}

bool AssetManager::isImageFileName(const QString &path) const
{
    const QString lower = cleanAssetPath(path).toLower();

    return lower.endsWith(QStringLiteral(".png")) ||
           lower.endsWith(QStringLiteral(".jpg")) ||
           lower.endsWith(QStringLiteral(".jpeg")) ||
           lower.endsWith(QStringLiteral(".webp")) ||
           lower.endsWith(QStringLiteral(".svg"));
}
