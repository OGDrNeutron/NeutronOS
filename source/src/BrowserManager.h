#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QStringList>
#include <QSet>

class BrowserManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList bookmarks READ bookmarks NOTIFY bookmarksChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(QVariantList downloads READ downloads NOTIFY downloadsChanged)
    Q_PROPERTY(QString homePage READ homePage WRITE setHomePage NOTIFY settingsChanged)
    Q_PROPERTY(QString searchEngine READ searchEngine WRITE setSearchEngine NOTIFY settingsChanged)
    Q_PROPERTY(QString downloadsPath READ downloadsPath CONSTANT)
    Q_PROPERTY(QString profilePath READ profilePath CONSTANT)
    Q_PROPERTY(QString cachePath READ cachePath CONSTANT)
    Q_PROPERTY(QString pythonLabUrl READ pythonLabUrl CONSTANT)
    Q_PROPERTY(QString hardwareAccelerationMode READ hardwareAccelerationMode WRITE setHardwareAccelerationMode NOTIFY settingsChanged)
    Q_PROPERTY(bool widevineAvailable READ widevineAvailable NOTIFY settingsChanged)
    Q_PROPERTY(QString widevinePath READ widevinePath NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList extensions READ extensions NOTIFY extensionsChanged)
    Q_PROPERTY(QString extensionsPath READ extensionsPath CONSTANT)
    Q_PROPERTY(bool runtimeActive READ runtimeActive NOTIFY runtimeChanged)
    Q_PROPERTY(QString runtimePhase READ runtimePhase NOTIFY runtimeChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY lastMessageChanged)
    Q_PROPERTY(QVariantMap runtimeState READ runtimeState NOTIFY runtimeChanged)
    Q_PROPERTY(QVariantList runtimeTabs READ runtimeTabs NOTIFY runtimeChanged)
    Q_PROPERTY(int runtimeActiveTab READ runtimeActiveTab NOTIFY runtimeChanged)
    Q_PROPERTY(bool runtimeLaunchAllowed READ runtimeLaunchAllowed NOTIFY runtimeChanged)

public:
    Q_INVOKABLE void humanSessionChanged();
    explicit BrowserManager(const QString &neutronRoot, QObject *parent = nullptr);

    QVariantList bookmarks() const;
    QVariantList history() const;
    QVariantList downloads() const;

    QString homePage() const;
    QString searchEngine() const;
    QString downloadsPath() const;
    QString profilePath() const;
    QString cachePath() const;
    QString pythonLabUrl() const;
    QString hardwareAccelerationMode() const;
    bool widevineAvailable() const;
    QString widevinePath() const;
    QVariantList extensions() const;
    QString extensionsPath() const;
    bool runtimeActive() const;
    QString runtimePhase() const;
    QString lastMessage() const;
    QVariantMap runtimeState() const;
    QVariantList runtimeTabs() const;
    int runtimeActiveTab() const;
    bool runtimeLaunchAllowed() const;

    void setHomePage(const QString &value);
    void setSearchEngine(const QString &value);
    void setHardwareAccelerationMode(const QString &value);

    Q_INVOKABLE QString normalizeInput(const QString &input) const;
    Q_INVOKABLE bool isBookmarked(const QString &url) const;
    Q_INVOKABLE void toggleBookmark(const QString &url, const QString &title);
    Q_INVOKABLE void removeBookmark(const QString &url);
    Q_INVOKABLE void addHistory(const QString &url, const QString &title);
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void clearBrowsingData();
    Q_INVOKABLE QVariantMap loadSession() const;
    Q_INVOKABLE void saveSession(const QVariantList &tabs, int activeIndex, bool privateMode);
    Q_INVOKABLE void noteDownload(const QString &url, const QString &fileName,
                                  const QString &path, qint64 totalBytes,
                                  const QString &status);
    Q_INVOKABLE void updateDownload(const QString &path, qint64 receivedBytes,
                                    qint64 totalBytes, const QString &status);
    Q_INVOKABLE void removeDownload(const QString &path);
    Q_INVOKABLE bool openDownloadsFolder() const;
    Q_INVOKABLE void refreshExtensions();
    Q_INVOKABLE void setExtensionEnabled(const QString &id, bool enabled);

    // Runs the Chromium/Qt WebEngine process as the unprivileged project owner.
    // NeutronShell itself remains root-owned and never embeds WebEngine.
    Q_INVOKABLE bool launchBrowser();
    Q_INVOKABLE void refreshRuntime();
    Q_INVOKABLE QVariantMap consumeReturnSession();
    Q_INVOKABLE bool requestRuntimeFocus();
    Q_INVOKABLE bool requestTabFocus(int tabIndex);
    Q_INVOKABLE bool requestTabClose(int tabIndex);
    Q_INVOKABLE bool requestRuntimeClose();

signals:
    void bookmarksChanged();
    void historyChanged();
    void downloadsChanged();
    void settingsChanged();
    void extensionsChanged();
    void runtimeChanged();
    void lastMessageChanged();
    void runtimeControlRequested(QString action, int tabIndex);

private:
    QString statePath(const QString &name) const;
    void load();
    void saveCollection(const QString &name, const QVariantList &items) const;
    QVariantList loadCollection(const QString &name) const;
    void saveSettings() const;
    void loadExtensionSettings();
    void saveExtensionSettings() const;
    static QString cleanTitle(const QString &title, const QString &fallback);
    void setLastMessage(const QString &message);
    QString projectOwner() const;
    QString projectOwnerHome() const;
    int foregroundVt() const;
    static int chooseBrowserVt(int shellVt);

    QString m_neutronRoot;
    QString m_stateRoot;
    QString m_runtimeRoot;
    QString m_downloadsPath;
    QString m_profilePath;
    QString m_cachePath;
    QString m_pythonLabUrl;
    QString m_extensionsPath;
    QString m_runtimeStatePath;
    QString m_runtimeSpecPath;
    QString m_returnSessionPath;
    QString m_runtimeControlPath;
    QVariantList m_bookmarks;
    QVariantList m_history;
    QVariantList m_downloads;
    QVariantList m_extensions;
    QStringList m_enabledExtensions;
    QString m_homePage = QStringLiteral("https://www.google.com/");
    QString m_searchEngine = QStringLiteral("https://www.google.com/search?q=%1");
    QString m_hardwareAccelerationMode = QStringLiteral("auto");
    QString m_runtimeSessionId;
    QString m_runtimePhase = QStringLiteral("idle");
    QString m_lastMessage;
    bool m_runtimeActive = false;
    QVariantList m_runtimeTabs;
    int m_runtimeActiveTab = 0;
    QTimer m_runtimeTimer;
    bool writeRuntimeControl(const QString &action, int tabIndex = -1);
    void consumeRuntimeControl();
};
