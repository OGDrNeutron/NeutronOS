#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

/*
    ============================================================
                              ASSET MANAGER
    ============================================================

    Filesystem-first theme/app asset resolver.

    Immutable built-in asset locations:
        ~/NeutronOS/themes/Default/
        ~/NeutronOS/themes/Default/users/
        ~/NeutronOS/themes/Default/apps/icons/
        ~/NeutronOS/themes/Default/apps/posters/
        ~/NeutronOS/qml/apps/<appId>/

    Rules:
        - No PNG/JPG/WebP/SVG files are embedded in CMake.
        - No app QML folders are embedded in CMake.
        - Packaged theme assets are read-only at runtime.
        - App Store assets live below /NeutronOS/<username>/apps/payload.
        - No quickactions asset folder.
        - Filesystem is the source of truth.
*/

class AssetManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString neutronRootPath READ neutronRootPath CONSTANT)
    Q_PROPERTY(QString qmlPath READ qmlPath CONSTANT)
    Q_PROPERTY(QString appsPath READ appsPath CONSTANT)

    Q_PROPERTY(QString themePath READ themePath CONSTANT)
    Q_PROPERTY(QString themeUrl READ themeUrl CONSTANT)

    Q_PROPERTY(QString usersPath READ usersPath CONSTANT)
    Q_PROPERTY(QString iconsPath READ iconsPath CONSTANT)
    Q_PROPERTY(QString postersPath READ postersPath CONSTANT)

public:
    explicit AssetManager(QObject *parent = nullptr);

    QString neutronRootPath() const;
    QString qmlPath() const;
    QString appsPath() const;

    QString themePath() const;
    QString themeUrl() const;

    QString usersPath() const;
    QString iconsPath() const;
    QString postersPath() const;

    /*
        Theme URL resolver.

        QML should usually call:
            assetManager.themeFile("background.png")
            assetManager.themeFile("apps/icons/terminal.png")
            assetManager.themeFile("apps/posters/terminal.png")
            assetManager.themeFile("users/user_icon.png")

        Return:
            file:///opt/neutronos/themes/Default/<path>

        If the file does not exist, returns an empty string unless the caller
        passed an already-valid absolute URL.
    */
    Q_INVOKABLE QString themeFile(const QString &relativePath) const;

    /*
        Local filesystem resolver.

        Returns:
            /opt/neutronos/themes/Default/<path>

        Returns empty string when missing.
    */
    Q_INVOKABLE QString resolvePath(const QString &relativePath) const;
    Q_INVOKABLE QString themeLocalFile(const QString &relativePath) const;

    /*
        App icon/poster helpers.

        These use only:
            themes/Default/apps/icons/
            themes/Default/apps/posters/

        They never use:
            themes/Default/quickactions/
    */
    Q_INVOKABLE QString appIcon(const QString &name) const;
    Q_INVOKABLE QString appPoster(const QString &name) const;

    Q_INVOKABLE QString appIconPath(const QString &name) const;
    Q_INVOKABLE QString appPosterPath(const QString &name) const;

    /*
        User/profile asset helpers.
    */
    Q_INVOKABLE QString userIcon() const;
    Q_INVOKABLE QString userIcon(const QString &fileName) const;

    /*
        Common theme background helpers.
    */
    Q_INVOKABLE QString background() const;
    Q_INVOKABLE QString background(const QString &fileName) const;
    Q_INVOKABLE QString logo() const;
    Q_INVOKABLE QString logo(const QString &fileName) const;
    Q_INVOKABLE QString firstThemeAsset(const QStringList &candidates) const;

    /*
        Drop-in app path helpers.

        appRoot("terminal"):
            ~/NeutronOS/qml/apps/terminal

        appMainQml("terminal"):
            ~/NeutronOS/qml/apps/terminal/Main.qml

        appMainUrl("terminal"):
            file:///opt/neutronos/qml/apps/terminal/Main.qml
    */
    Q_INVOKABLE QString appRoot(const QString &appId) const;
    Q_INVOKABLE QString appMainQml(const QString &appId) const;
    Q_INVOKABLE QString appMainUrl(const QString &appId) const;
    Q_INVOKABLE bool appExists(const QString &appId) const;

    /*
        Existence checks.
    */
    Q_INVOKABLE bool themeExists(const QString &relativePath) const;
    Q_INVOKABLE bool fileExists(const QString &pathOrUrl) const;

    /*
        Name/path cleanup helpers exposed for QML compatibility.
    */
    Q_INVOKABLE QString cleanAssetPath(const QString &path) const;
    Q_INVOKABLE QString normalizeAssetNameForQml(const QString &name) const;
    Q_INVOKABLE QString normalizeAppIdForQml(const QString &appId) const;

    /*
        Runtime refresh.

        AssetManager does not embed or cache image bytes. Most QML Image
        items reload when their source changes. This signal gives screens a
        simple hook to refresh their source strings after assets are replaced.
    */
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void ensureDirectories();

signals:
    void themeChanged();
    void assetsChanged();

private:
    QString m_neutronRootPath;
    QString m_qmlPath;
    QString m_appsPath;
    QString m_themePath;
    QString m_usersPath;
    QString m_iconsPath;
    QString m_postersPath;
    QString m_installedAppsPath;
    QString m_installedIconsPath;
    QString m_installedPostersPath;

    void resolveRuntimePaths();
    void ensureThemeDirectories() const;

    QString cleanRelativePath(const QString &relativePath) const;
    QString cleanAbsolutePath(const QString &path) const;

    QString normalizeAssetName(const QString &name) const;
    QString normalizeAppId(const QString &appId) const;

    QString localThemePath(const QString &relativePath) const;
    QString localAppPath(const QString &appId, const QString &relativePath = QString()) const;

    QString fileUrlForPath(const QString &path) const;
    QString localPathFromUrl(const QString &pathOrUrl) const;

    bool isResolvedUrl(const QString &path) const;
    bool isImageFileName(const QString &path) const;
};
