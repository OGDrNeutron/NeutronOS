#include "HumanAccountPolicy.h"
#include "BrowserManager.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>
#include <utility>

#ifdef Q_OS_UNIX
#include <pwd.h>
#include <sys/types.h>
#include <unistd.h>
#endif

namespace {
constexpr int kHistoryLimit = 500;
constexpr int kDownloadLimit = 200;

QVariantMap asMap(const QVariant &value)
{
    return value.toMap();
}

QString comparableUrl(const QString &value)
{
    QUrl url = QUrl::fromUserInput(value.trimmed());
    url.setFragment(QString());
    return url.adjusted(QUrl::NormalizePathSegments | QUrl::StripTrailingSlash).toString();
}

QString executable(const QStringList &candidates)
{
    for (const QString &candidate : candidates) {
        const QString path = QStandardPaths::findExecutable(candidate);
        if (!path.isEmpty())
            return path;
    }
    return {};
}
}

BrowserManager::BrowserManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir::cleanPath(neutronRoot)),
      m_stateRoot(QStringLiteral("/var/lib/neutronos/browser-prelogin")),
      m_runtimeRoot(QStringLiteral("/var/lib/neutronos/apps/browser-runtime")),
      m_downloadsPath(QDir::cleanPath(projectOwnerHome() + QStringLiteral("/Downloads"))),
      m_profilePath(QDir::cleanPath(m_stateRoot + QStringLiteral("/profile"))),
      m_cachePath(QDir::cleanPath(m_stateRoot + QStringLiteral("/cache"))),
      m_pythonLabUrl(QUrl::fromLocalFile(QDir::cleanPath(
          neutronRoot + QStringLiteral("/qml/apps/browser/pages/python-lab.html"))).toString()),
      m_extensionsPath(QDir::cleanPath(m_stateRoot + QStringLiteral("/extensions"))),
      m_runtimeStatePath(QDir::cleanPath(m_runtimeRoot + QStringLiteral("/status.json"))),
      m_runtimeSpecPath(QDir::cleanPath(m_runtimeRoot + QStringLiteral("/launch.json"))),
      m_returnSessionPath(QDir::cleanPath(m_runtimeRoot + QStringLiteral("/return-session.json"))),
      m_runtimeControlPath(QDir::cleanPath(m_runtimeRoot + QStringLiteral("/control.json")))
{
    if (!HumanHome::path().isEmpty()) QDir().mkpath(m_stateRoot);
    QDir().mkpath(m_runtimeRoot);
    if (!HumanHome::path().isEmpty()) QDir().mkpath(m_downloadsPath);
    if (!HumanHome::path().isEmpty()) humanSessionChanged();

    m_runtimeTimer.setInterval(2000);
    m_runtimeTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_runtimeTimer, &QTimer::timeout, this, [this]() {
        refreshRuntime();
        if (QCoreApplication::applicationName() == QStringLiteral("NeutronBrowser"))
            consumeRuntimeControl();
    });
    m_runtimeTimer.start();

    load();
    loadExtensionSettings();
    refreshExtensions();
    refreshRuntime();
}

void BrowserManager::humanSessionChanged()
{
    if (HumanHome::path().isEmpty()) {
        m_stateRoot = QStringLiteral("/var/lib/neutronos/browser-prelogin");
        m_downloadsPath.clear();
        m_profilePath = m_stateRoot + QStringLiteral("/profile");
        m_cachePath = m_stateRoot + QStringLiteral("/cache");
        m_extensionsPath = m_stateRoot + QStringLiteral("/extensions");
        m_bookmarks.clear(); m_history.clear(); m_downloads.clear();
        emit bookmarksChanged(); emit historyChanged(); emit downloadsChanged();
        return;
    }
    m_stateRoot = HumanHome::path() + QStringLiteral("/apps/browser");
    m_downloadsPath = HumanHome::path() + QStringLiteral("/Downloads");
    m_profilePath = m_stateRoot + QStringLiteral("/profile");
    m_cachePath = HumanHome::path() + QStringLiteral("/cache/browser");
    m_extensionsPath = m_stateRoot + QStringLiteral("/extensions");
    for (const QString &path : {m_stateRoot, m_downloadsPath, m_profilePath, m_cachePath, m_extensionsPath}) QDir().mkpath(path);
    load(); loadExtensionSettings(); refreshExtensions();
    emit settingsChanged(); emit bookmarksChanged(); emit historyChanged(); emit downloadsChanged();
}

QVariantList BrowserManager::bookmarks() const { return m_bookmarks; }
QVariantList BrowserManager::history() const { return m_history; }
QVariantList BrowserManager::downloads() const { return m_downloads; }
QString BrowserManager::homePage() const { return m_homePage; }
QString BrowserManager::searchEngine() const { return m_searchEngine; }
QString BrowserManager::downloadsPath() const { return m_downloadsPath; }
QString BrowserManager::profilePath() const { return m_profilePath; }
QString BrowserManager::cachePath() const { return m_cachePath; }
QString BrowserManager::pythonLabUrl() const { return m_pythonLabUrl; }
QString BrowserManager::hardwareAccelerationMode() const { return m_hardwareAccelerationMode; }
QVariantList BrowserManager::extensions() const { return m_extensions; }
QString BrowserManager::extensionsPath() const { return m_extensionsPath; }

QString BrowserManager::widevinePath() const
{
    const QStringList candidates = {
        QStringLiteral("/opt/WidevineCdm/_platform_specific/linux_x64/libwidevinecdm.so"),
        QStringLiteral("/usr/lib/chromium/WidevineCdm/_platform_specific/linux_x64/libwidevinecdm.so"),
        QStringLiteral("/usr/lib/chromium-browser/WidevineCdm/_platform_specific/linux_x64/libwidevinecdm.so"),
        QStringLiteral("/usr/lib/widevine/libwidevinecdm.so"),
        QStringLiteral("/opt/google/chrome/WidevineCdm/_platform_specific/linux_x64/libwidevinecdm.so")
    };
    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (info.isFile() && info.isReadable())
            return candidate;
    }
    return {};
}

bool BrowserManager::widevineAvailable() const
{
    return !widevinePath().isEmpty();
}

bool BrowserManager::runtimeActive() const { return m_runtimeActive; }
QString BrowserManager::runtimePhase() const { return m_runtimePhase; }
QString BrowserManager::lastMessage() const { return m_lastMessage; }
QVariantList BrowserManager::runtimeTabs() const { return m_runtimeTabs; }
int BrowserManager::runtimeActiveTab() const { return m_runtimeActiveTab; }
bool BrowserManager::runtimeLaunchAllowed() const { return !m_runtimeActive; }

QVariantMap BrowserManager::runtimeState() const
{
    return {{QStringLiteral("appId"), QStringLiteral("browser")},
            {QStringLiteral("name"), QStringLiteral("Browser")},
            {QStringLiteral("active"), m_runtimeActive},
            {QStringLiteral("phase"), m_runtimePhase},
            {QStringLiteral("message"), m_lastMessage},
            {QStringLiteral("tabs"), m_runtimeTabs},
            {QStringLiteral("activeTab"), m_runtimeActiveTab},
            {QStringLiteral("isolated"), true},
            {QStringLiteral("suspendSupported"), false}};
}

bool BrowserManager::writeRuntimeControl(const QString &action, int tabIndex)
{
    if (!m_runtimeActive)
        return false;
    static const QSet<QString> allowed{QStringLiteral("focus-runtime"),
                                       QStringLiteral("focus-tab"),
                                       QStringLiteral("close-tab"),
                                       QStringLiteral("close-runtime")};
    if (!allowed.contains(action))
        return false;
    if ((action == QStringLiteral("focus-tab") || action == QStringLiteral("close-tab"))
            && (tabIndex < 0 || tabIndex >= m_runtimeTabs.size()))
        return false;
    QJsonObject request{{QStringLiteral("version"), 1},
                        {QStringLiteral("action"), action},
                        {QStringLiteral("tabIndex"), tabIndex},
                        {QStringLiteral("createdUtcMs"), QDateTime::currentMSecsSinceEpoch()}};
    QSaveFile file(m_runtimeControlPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    file.write(QJsonDocument(request).toJson(QJsonDocument::Compact));
    if (!file.commit())
        return false;
#ifdef Q_OS_UNIX
    const QByteArray ownerName = projectOwner().toLocal8Bit();
    const passwd *ownerEntry = ::getpwnam(ownerName.constData());
    if (!ownerEntry || ::chown(m_runtimeControlPath.toLocal8Bit().constData(),
                               ownerEntry->pw_uid, ownerEntry->pw_gid) != 0) {
        QFile::remove(m_runtimeControlPath);
        return false;
    }
#endif
    QFile::setPermissions(m_runtimeControlPath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

bool BrowserManager::requestRuntimeFocus() { return writeRuntimeControl(QStringLiteral("focus-runtime")); }
bool BrowserManager::requestTabFocus(int tabIndex) { return writeRuntimeControl(QStringLiteral("focus-tab"), tabIndex); }
bool BrowserManager::requestTabClose(int tabIndex) { return writeRuntimeControl(QStringLiteral("close-tab"), tabIndex); }
bool BrowserManager::requestRuntimeClose() { return writeRuntimeControl(QStringLiteral("close-runtime")); }

void BrowserManager::consumeRuntimeControl()
{
    QFile file(m_runtimeControlPath);
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    file.close();
    QFile::remove(m_runtimeControlPath);
    if (!document.isObject())
        return;
    const QJsonObject request = document.object();
    const QString action = request.value(QStringLiteral("action")).toString();
    const int tabIndex = request.value(QStringLiteral("tabIndex")).toInt(-1);
    const qint64 created = request.value(QStringLiteral("createdUtcMs")).toVariant().toLongLong();
    if (QDateTime::currentMSecsSinceEpoch() - created > 10000 || created <= 0)
        return;
    if (action == QStringLiteral("focus-runtime") || action == QStringLiteral("close-runtime")) {
        emit runtimeControlRequested(action, -1);
    } else if ((action == QStringLiteral("focus-tab") || action == QStringLiteral("close-tab"))
               && tabIndex >= 0 && tabIndex < m_runtimeTabs.size()) {
        emit runtimeControlRequested(action, tabIndex);
    }
}

void BrowserManager::setHomePage(const QString &value)
{
    const QString normalized = normalizeInput(value);
    if (normalized.isEmpty() || normalized == m_homePage)
        return;
    m_homePage = normalized;
    saveSettings();
    emit settingsChanged();
}

void BrowserManager::setSearchEngine(const QString &value)
{
    const QString clean = value.trimmed();
    if (clean.isEmpty() || !clean.contains(QStringLiteral("%1")) || clean == m_searchEngine)
        return;
    m_searchEngine = clean;
    saveSettings();
    emit settingsChanged();
}

void BrowserManager::setHardwareAccelerationMode(const QString &value)
{
    const QString clean = value.trimmed().toLower();
    if (clean != QStringLiteral("auto") && clean != QStringLiteral("enabled")
            && clean != QStringLiteral("disabled"))
        return;
    if (m_hardwareAccelerationMode == clean)
        return;
    m_hardwareAccelerationMode = clean;
    saveSettings();
    emit settingsChanged();
    setLastMessage(QStringLiteral("Hardware acceleration will change the next time Browser opens."));
}

QString BrowserManager::normalizeInput(const QString &input) const
{
    const QString clean = input.trimmed();
    if (clean.isEmpty())
        return m_homePage;

    const QUrl direct = QUrl::fromUserInput(clean);
    const bool looksLikeUrl = clean.contains(QStringLiteral("://"))
            || clean.startsWith(QStringLiteral("localhost"), Qt::CaseInsensitive)
            || clean.startsWith(QStringLiteral("file:"), Qt::CaseInsensitive)
            || (!clean.contains(QLatin1Char(' ')) && clean.contains(QLatin1Char('.')));

    if (looksLikeUrl && direct.isValid()) {
        const QString scheme = direct.scheme().toLower();
        if (scheme == QStringLiteral("http") || scheme == QStringLiteral("https")
                || scheme == QStringLiteral("file") || scheme == QStringLiteral("data")
                || scheme == QStringLiteral("about")) {
            return direct.toString();
        }
    }
    return m_searchEngine.arg(QString::fromUtf8(QUrl::toPercentEncoding(clean)));
}

bool BrowserManager::isBookmarked(const QString &url) const
{
    const QString needle = comparableUrl(url);
    return std::any_of(m_bookmarks.cbegin(), m_bookmarks.cend(), [&](const QVariant &item) {
        return comparableUrl(asMap(item).value(QStringLiteral("url")).toString()) == needle;
    });
}

void BrowserManager::toggleBookmark(const QString &url, const QString &title)
{
    if (isBookmarked(url)) {
        removeBookmark(url);
        return;
    }
    QVariantMap item;
    item.insert(QStringLiteral("url"), normalizeInput(url));
    item.insert(QStringLiteral("title"), cleanTitle(title, url));
    item.insert(QStringLiteral("createdUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    m_bookmarks.prepend(item);
    saveCollection(QStringLiteral("bookmarks.json"), m_bookmarks);
    emit bookmarksChanged();
    setLastMessage(QStringLiteral("Bookmark added"));
}

void BrowserManager::removeBookmark(const QString &url)
{
    const QString needle = comparableUrl(url);
    QVariantList kept;
    for (const QVariant &entry : std::as_const(m_bookmarks)) {
        const QVariantMap item = asMap(entry);
        if (comparableUrl(item.value(QStringLiteral("url")).toString()) != needle)
            kept.append(item);
    }
    if (kept.size() == m_bookmarks.size())
        return;
    m_bookmarks = kept;
    saveCollection(QStringLiteral("bookmarks.json"), m_bookmarks);
    emit bookmarksChanged();
    setLastMessage(QStringLiteral("Bookmark removed"));
}

void BrowserManager::addHistory(const QString &url, const QString &title)
{
    const QUrl parsed(url);
    const QString scheme = parsed.scheme().toLower();
    if (!parsed.isValid() || (scheme != QStringLiteral("http")
            && scheme != QStringLiteral("https") && scheme != QStringLiteral("file")))
        return;

    const QString comparable = comparableUrl(url);
    QVariantList kept;
    for (const QVariant &entry : std::as_const(m_history)) {
        if (comparableUrl(asMap(entry).value(QStringLiteral("url")).toString()) != comparable)
            kept.append(entry);
    }

    QVariantMap item;
    item.insert(QStringLiteral("url"), parsed.toString());
    item.insert(QStringLiteral("title"), cleanTitle(title, url));
    item.insert(QStringLiteral("visitedUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    kept.prepend(item);
    while (kept.size() > kHistoryLimit)
        kept.removeLast();
    m_history = kept;
    saveCollection(QStringLiteral("history.json"), m_history);
    emit historyChanged();
}

void BrowserManager::clearHistory()
{
    m_history.clear();
    saveCollection(QStringLiteral("history.json"), m_history);
    emit historyChanged();
    setLastMessage(QStringLiteral("History cleared"));
}

void BrowserManager::clearBrowsingData()
{
    clearHistory();
    QDir(m_cachePath).removeRecursively();
    QDir().mkpath(m_cachePath);
    setLastMessage(QStringLiteral("History and browser cache cleared"));
}

QVariantMap BrowserManager::loadSession() const
{
    QFile file(statePath(QStringLiteral("session.json")));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject())
        return {};

    QVariantMap session = document.object().toVariantMap();
    QVariantList tabs = session.value(QStringLiteral("tabs")).toList();
    bool migrated = false;
    for (QVariant &entry : tabs) {
        QVariantMap tab = entry.toMap();
        const QString url = tab.value(QStringLiteral("url")).toString();
        if (url == QStringLiteral("https://duckduckgo.com/") ||
                url == QStringLiteral("https://duckduckgo.com")) {
            tab.insert(QStringLiteral("url"), QStringLiteral("https://www.google.com/"));
            tab.insert(QStringLiteral("title"), QStringLiteral("Google"));
            entry = tab;
            migrated = true;
        }
    }
    if (migrated)
        session.insert(QStringLiteral("tabs"), tabs);
    return session;
}

void BrowserManager::saveSession(const QVariantList &tabs, int activeIndex, bool privateMode)
{
    if (privateMode)
        return;

    QVariantList safeTabs;
    for (const QVariant &entry : tabs) {
        const QVariantMap map = entry.toMap();
        const QString url = map.value(QStringLiteral("url")).toString();
        if (url.startsWith(QStringLiteral("http://"))
                || url.startsWith(QStringLiteral("https://"))
                || url.startsWith(QStringLiteral("file://"))) {
            safeTabs.append(QVariantMap{{QStringLiteral("url"), url},
                                        {QStringLiteral("title"), cleanTitle(
                                             map.value(QStringLiteral("title")).toString(), url)}});
        }
        if (safeTabs.size() >= 12)
            break;
    }
    if (safeTabs.isEmpty())
        safeTabs.append(QVariantMap{{QStringLiteral("url"), m_homePage},
                                    {QStringLiteral("title"), QStringLiteral("Home")}});

    QJsonObject object;
    object.insert(QStringLiteral("tabs"), QJsonArray::fromVariantList(safeTabs));
    object.insert(QStringLiteral("activeIndex"), std::clamp(activeIndex, 0, static_cast<int>(safeTabs.size()) - 1));
    QSaveFile file(statePath(QStringLiteral("session.json")));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
        if (file.commit()) {
            m_runtimeTabs = safeTabs;
            m_runtimeActiveTab = std::clamp(activeIndex, 0, static_cast<int>(safeTabs.size()) - 1);
            emit runtimeChanged();
        }
    }
}

void BrowserManager::noteDownload(const QString &url, const QString &fileName,
                                  const QString &path, qint64 totalBytes,
                                  const QString &status)
{
    removeDownload(path);
    QVariantMap item;
    item.insert(QStringLiteral("url"), url);
    item.insert(QStringLiteral("fileName"), fileName);
    item.insert(QStringLiteral("path"), path);
    item.insert(QStringLiteral("receivedBytes"), 0);
    item.insert(QStringLiteral("totalBytes"), totalBytes);
    item.insert(QStringLiteral("status"), status);
    item.insert(QStringLiteral("startedUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    m_downloads.prepend(item);
    while (m_downloads.size() > kDownloadLimit)
        m_downloads.removeLast();
    saveCollection(QStringLiteral("downloads.json"), m_downloads);
    emit downloadsChanged();
}

void BrowserManager::updateDownload(const QString &path, qint64 receivedBytes,
                                    qint64 totalBytes, const QString &status)
{
    bool changed = false;
    for (int i = 0; i < m_downloads.size(); ++i) {
        QVariantMap item = m_downloads.at(i).toMap();
        if (item.value(QStringLiteral("path")).toString() != path)
            continue;
        item.insert(QStringLiteral("receivedBytes"), receivedBytes);
        item.insert(QStringLiteral("totalBytes"), totalBytes);
        item.insert(QStringLiteral("status"), status);
        if (status == QStringLiteral("Completed") || status == QStringLiteral("Interrupted"))
            item.insert(QStringLiteral("finishedUtc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
        m_downloads[i] = item;
        changed = true;
        break;
    }
    if (!changed)
        return;
    saveCollection(QStringLiteral("downloads.json"), m_downloads);
    emit downloadsChanged();
}

void BrowserManager::removeDownload(const QString &path)
{
    QVariantList kept;
    for (const QVariant &entry : std::as_const(m_downloads)) {
        if (entry.toMap().value(QStringLiteral("path")).toString() != path)
            kept.append(entry);
    }
    if (kept.size() == m_downloads.size())
        return;
    m_downloads = kept;
    saveCollection(QStringLiteral("downloads.json"), m_downloads);
    emit downloadsChanged();
}

bool BrowserManager::openDownloadsFolder() const
{
    return QDesktopServices::openUrl(QUrl::fromLocalFile(m_downloadsPath));
}


void BrowserManager::loadExtensionSettings()
{
    m_enabledExtensions.clear();
    QFile file(statePath(QStringLiteral("extensions.json")));
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isArray())
        return;
    for (const QJsonValue &value : document.array()) {
        const QString id = value.toString().trimmed();
        if (!id.isEmpty() && !id.contains(QLatin1Char('/')) && !id.contains(QStringLiteral("..")))
            m_enabledExtensions.append(id);
    }
    m_enabledExtensions.removeDuplicates();
}

void BrowserManager::saveExtensionSettings() const
{
    QJsonArray array;
    for (const QString &id : m_enabledExtensions)
        array.append(id);
    QSaveFile file(statePath(QStringLiteral("extensions.json")));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
        file.commit();
    }
}

void BrowserManager::refreshExtensions()
{
    QVariantList result;
    const QDir root(m_extensionsPath);
    const QFileInfoList directories = root.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot,
                                                          QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &directory : directories) {
        if (directory.isSymLink())
            continue;
        const QString id = directory.fileName();
        const QString manifestPath = QDir(directory.absoluteFilePath()).filePath(QStringLiteral("manifest.json"));
        QFile manifestFile(manifestPath);
        if (!manifestFile.open(QIODevice::ReadOnly))
            continue;
        const QJsonDocument document = QJsonDocument::fromJson(manifestFile.readAll());
        if (!document.isObject())
            continue;
        const QJsonObject object = document.object();
        QVariantMap item;
        item.insert(QStringLiteral("id"), id);
        item.insert(QStringLiteral("name"), object.value(QStringLiteral("name")).toString(id));
        item.insert(QStringLiteral("version"), object.value(QStringLiteral("version")).toString());
        item.insert(QStringLiteral("description"), object.value(QStringLiteral("description")).toString());
        item.insert(QStringLiteral("enabled"), m_enabledExtensions.contains(id));
        item.insert(QStringLiteral("path"), directory.absoluteFilePath());
        result.append(item);
    }
    if (m_extensions == result)
        return;
    m_extensions = result;
    emit extensionsChanged();
}

void BrowserManager::setExtensionEnabled(const QString &id, bool enabled)
{
    const QString clean = id.trimmed();
    if (clean.isEmpty() || clean.contains(QLatin1Char('/')) || clean.contains(QStringLiteral("..")))
        return;
    const QFileInfo manifest(QDir(m_extensionsPath).filePath(clean + QStringLiteral("/manifest.json")));
    if (!manifest.isFile())
        return;
    if (enabled && !m_enabledExtensions.contains(clean))
        m_enabledExtensions.append(clean);
    if (!enabled)
        m_enabledExtensions.removeAll(clean);
    m_enabledExtensions.removeDuplicates();
    saveExtensionSettings();
    refreshExtensions();
    setLastMessage(QStringLiteral("Extension change will apply the next time Browser opens."));
}

bool BrowserManager::launchBrowser()
{
    refreshRuntime();
    if (!runtimeLaunchAllowed()) {
        setLastMessage(QStringLiteral("Browser session is already starting or active."));
        return true;
    }

    const QString sudoExecutable = executable({QStringLiteral("sudo")});
    const QString browserLauncher = QStringLiteral("/usr/local/libexec/neutronos-browser-launch");
    const QString browserExecutable = QStringLiteral("/usr/local/bin/NeutronBrowser");

    if (sudoExecutable.isEmpty() || !QFileInfo(browserLauncher).isExecutable()
            || !QFileInfo(browserExecutable).isExecutable()) {
        setLastMessage(QStringLiteral("Browser runtime is incomplete. Reapply NeutronOS Patch 68H9."));
        return false;
    }

    if (HumanHome::path().isEmpty()) { setLastMessage(QStringLiteral("An authenticated human account is required.")); return false; }
    m_downloadsPath = HumanHome::path() + QStringLiteral("/Downloads");
    const int shellVt = foregroundVt();
    const int browserVt = chooseBrowserVt(shellVt);
    m_runtimeSessionId = QStringLiteral("%1-%2")
            .arg(QDateTime::currentMSecsSinceEpoch())
            .arg(QCoreApplication::applicationPid());

    QJsonObject spec;
    spec.insert(QStringLiteral("version"), 1);
    spec.insert(QStringLiteral("sessionId"), m_runtimeSessionId);
    spec.insert(QStringLiteral("user"), projectOwner());
    spec.insert(QStringLiteral("humanUser"), HumanHome::sessionUser());
    spec.insert(QStringLiteral("humanHome"), HumanHome::path());
    spec.insert(QStringLiteral("shellVt"), shellVt);
    spec.insert(QStringLiteral("browserVt"), browserVt);

    QSaveFile file(m_runtimeSpecPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        setLastMessage(QStringLiteral("Unable to create the protected browser launch specification."));
        return false;
    }
    file.write(QJsonDocument(spec).toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        setLastMessage(QStringLiteral("Unable to commit the browser launch specification."));
        return false;
    }

#ifdef Q_OS_UNIX
    /*
        NeutronShell may run as root while the isolated Browser must run as the
        unprivileged project owner.  The trusted launcher rejects a root-owned
        request file, so transfer only this one-shot launch specification to
        that account before invoking the supervisor.
    */
    const QByteArray ownerName = projectOwner().toLocal8Bit();
    const passwd *ownerEntry = ::getpwnam(ownerName.constData());
    if (!ownerEntry || ::chown(m_runtimeSpecPath.toLocal8Bit().constData(),
                               ownerEntry->pw_uid, ownerEntry->pw_gid) != 0) {
        QFile::remove(m_runtimeSpecPath);
        setLastMessage(QStringLiteral("Unable to assign the protected browser launch request to the NeutronOS user."));
        return false;
    }
#endif
    QFile::setPermissions(m_runtimeSpecPath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    const QString logPath = QDir(m_runtimeRoot).filePath(QStringLiteral("last-runtime.log"));
    const QString exitPath = QDir(m_runtimeRoot).filePath(QStringLiteral("last-exit-code"));
    QFile::remove(logPath);
    QFile::remove(exitPath);
    QStringList arguments{QStringLiteral("-n"), browserLauncher, m_runtimeSpecPath};
    QProcess launcher;
    launcher.start(sudoExecutable, arguments);
    if (!launcher.waitForFinished(7000)
            || launcher.exitStatus() != QProcess::NormalExit
            || launcher.exitCode() != 0) {
        const QString detail = QString::fromUtf8(launcher.readAll()).trimmed();
        setLastMessage(QStringLiteral("Unable to start the isolated browser session. %1")
                       .arg(detail.isEmpty() ? launcher.errorString() : detail.right(500)));
        return false;
    }

    m_runtimeActive = true;
    m_runtimePhase = QStringLiteral("launching");
    setLastMessage(QStringLiteral("Releasing the NeutronOS display for Browser…"));
    emit runtimeChanged();
    return true;
}

QVariantMap BrowserManager::consumeReturnSession()
{
    QFile file(m_returnSessionPath);
    if (!file.open(QIODevice::ReadOnly))
        return {};

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    file.close();

    // One-shot token: remove it even if malformed so a bad return file can
    // never trap the shell in an automatic-login loop.
    QFile::remove(m_returnSessionPath);

    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return {};

    QVariantMap result = document.object().toVariantMap();
    if (!result.value(QStringLiteral("pending")).toBool())
        return {};
    result.insert(QStringLiteral("pending"), true);
    return result;
}

void BrowserManager::refreshRuntime()
{
    const QVariantMap session = loadSession();
    const QVariantList tabs = session.value(QStringLiteral("tabs")).toList();
    const int activeTab = std::clamp(session.value(QStringLiteral("activeIndex"), 0).toInt(),
                                     0, std::max(0, static_cast<int>(tabs.size()) - 1));
    const auto markUnavailable = [this, &tabs, activeTab]() {
        if (m_runtimeActive || m_runtimePhase != QStringLiteral("idle") ||
                m_runtimeTabs != tabs || m_runtimeActiveTab != activeTab) {
            m_runtimeActive = false;
            m_runtimePhase = QStringLiteral("idle");
            m_runtimeTabs = tabs;
            m_runtimeActiveTab = activeTab;
            emit runtimeChanged();
        }
    };
    QFile file(m_runtimeStatePath);
    if (!file.open(QIODevice::ReadOnly)) {
        markUnavailable();
        return;
    }
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        markUnavailable();
        return;
    }
    const QJsonObject object = document.object();
    const bool active = object.value(QStringLiteral("active")).toBool(false);
    const QString phase = object.value(QStringLiteral("phase")).toString(
        active ? QStringLiteral("active") : QStringLiteral("idle"));
    const QString message = object.value(QStringLiteral("message")).toString();
    bool changed = false;
    if (m_runtimeTabs != tabs) { m_runtimeTabs = tabs; changed = true; }
    if (m_runtimeActiveTab != activeTab) { m_runtimeActiveTab = activeTab; changed = true; }
    if (m_runtimeActive != active) { m_runtimeActive = active; changed = true; }
    if (m_runtimePhase != phase) { m_runtimePhase = phase; changed = true; }
    if (!message.isEmpty())
        setLastMessage(message);
    if (changed)
        emit runtimeChanged();
}

QString BrowserManager::statePath(const QString &name) const
{
    return QDir::cleanPath(m_stateRoot + QLatin1Char('/') + name);
}

void BrowserManager::load()
{
    m_bookmarks = loadCollection(QStringLiteral("bookmarks.json"));
    m_history = loadCollection(QStringLiteral("history.json"));
    m_downloads = loadCollection(QStringLiteral("downloads.json"));
    QFile file(statePath(QStringLiteral("settings.json")));
    bool migratedDefaults = false;
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
        const QString home = object.value(QStringLiteral("homePage")).toString();
        const QString search = object.value(QStringLiteral("searchEngine")).toString();
        const QString acceleration = object.value(QStringLiteral("hardwareAccelerationMode")).toString().toLower();
        if (!home.isEmpty() && home != QStringLiteral("https://duckduckgo.com/") &&
                home != QStringLiteral("https://duckduckgo.com")) {
            m_homePage = home;
        } else if (!home.isEmpty()) {
            migratedDefaults = true;
        }
        if (search.contains(QStringLiteral("%1")) &&
                !search.startsWith(QStringLiteral("https://duckduckgo.com/"))) {
            m_searchEngine = search;
        } else if (!search.isEmpty()) {
            migratedDefaults = true;
        }
        if (acceleration == QStringLiteral("auto") || acceleration == QStringLiteral("enabled")
                || acceleration == QStringLiteral("disabled"))
            m_hardwareAccelerationMode = acceleration;
    }
    if (migratedDefaults)
        saveSettings();
}

void BrowserManager::saveCollection(const QString &name, const QVariantList &items) const
{
    QSaveFile file(statePath(name));
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(QJsonArray::fromVariantList(items)).toJson(QJsonDocument::Indented));
    file.commit();
}

QVariantList BrowserManager::loadCollection(const QString &name) const
{
    QFile file(statePath(name));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isArray() ? document.array().toVariantList() : QVariantList{};
}

void BrowserManager::saveSettings() const
{
    QJsonObject object;
    object.insert(QStringLiteral("homePage"), m_homePage);
    object.insert(QStringLiteral("searchEngine"), m_searchEngine);
    object.insert(QStringLiteral("hardwareAccelerationMode"), m_hardwareAccelerationMode);
    QSaveFile file(statePath(QStringLiteral("settings.json")));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
        file.commit();
    }
}

QString BrowserManager::cleanTitle(const QString &title, const QString &fallback)
{
    QString clean = title.simplified();
    if (clean.isEmpty()) clean = fallback;
    if (clean.size() > 140) clean = clean.left(137) + QStringLiteral("...");
    return clean;
}

void BrowserManager::setLastMessage(const QString &message)
{
    if (m_lastMessage == message)
        return;
    m_lastMessage = message;
    emit lastMessageChanged();
}

QString BrowserManager::projectOwner() const
{
    return QStringLiteral("neutronos");
}

QString BrowserManager::projectOwnerHome() const
{
    return HumanHome::browsePath();
}

int BrowserManager::foregroundVt() const
{
    const QString fgconsole = executable({QStringLiteral("fgconsole")});
    if (fgconsole.isEmpty())
        return 1;
    QProcess process;
    process.start(fgconsole, {});
    if (!process.waitForFinished(1800))
        return 1;
    bool ok = false;
    const int value = QString::fromUtf8(process.readAllStandardOutput()).trimmed().toInt(&ok);
    return ok && value > 0 ? value : 1;
}

int BrowserManager::chooseBrowserVt(int shellVt)
{
    return shellVt == 2 ? 3 : 2;
}
