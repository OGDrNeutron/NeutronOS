#include "HumanAccountPolicy.h"
#include "AppStoreManager.h"

#include "AppManager.h"
#include "DeveloperModeManager.h"
#include "SecurityCoreManager.h"

#include <QByteArray>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSet>
#include <QtGlobal>
#include <QSaveFile>
#include <QTimer>
#include <QTcpSocket>
#include <QStorageInfo>
#include <QTemporaryDir>
#include <QTemporaryFile>
#include <QSysInfo>
#include <QUrl>
#include <QUrlQuery>
#include <QUuid>
#include <QVersionNumber>

#include <algorithm>
#include <utility>

namespace {
constexpr auto kSchemaVersion = 1;

QString cleanText(const QVariant &value)
{
    return value.toString().trimmed();
}

QVariantList jsonArrayToVariantList(const QJsonValue &value)
{
    return value.isArray() ? value.toArray().toVariantList() : QVariantList();
}

bool boolValue(const QVariantMap &map, const QString &key, bool fallback = false)
{
    return map.contains(key) ? map.value(key).toBool() : fallback;
}

QString canonicalArch(QString arch)
{
    arch = arch.trimmed().toLower();
    if (arch == QStringLiteral("arm64"))
        return QStringLiteral("aarch64");
    if (arch == QStringLiteral("x86_64"))
        return QStringLiteral("amd64");
    return arch;
}


QByteArray runReadOnlyCommand(const QString &program, const QStringList &arguments, int timeoutMs, int *exitCode = nullptr)
{
    QProcess process;
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    environment.insert(QStringLiteral("LANG"), QStringLiteral("C"));
    process.setProcessEnvironment(environment);
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(program, arguments, QIODevice::ReadOnly);
    if (!process.waitForStarted(1500)) {
        if (exitCode)
            *exitCode = -1;
        return {};
    }
    if (!process.waitForFinished(timeoutMs)) {
        process.kill();
        process.waitForFinished(1000);
        if (exitCode)
            *exitCode = -2;
        return process.readAll();
    }
    if (exitCode)
        *exitCode = process.exitCode();
    return process.readAll();
}

bool verifyReleaseSignature(const QByteArray &document, const QByteArray &signature)
{
    if (document.isEmpty() || signature.isEmpty())
        return false;
    QTemporaryDir directory;
    if (!directory.isValid())
        return false;
    const QString docPath = directory.filePath(QStringLiteral("catalog.json"));
    const QString sigPath = directory.filePath(QStringLiteral("catalog.json.sig"));
    QFile doc(docPath), sig(sigPath);
    if (!doc.open(QIODevice::WriteOnly) || doc.write(document) != document.size() ||
        !sig.open(QIODevice::WriteOnly) || sig.write(signature) != signature.size())
        return false;
    doc.close(); sig.close();
    int code = -1;
    runReadOnlyCommand(QStringLiteral("/usr/local/libexec/neutronos-release-verify"),
                       {QStringLiteral("verify"), docPath, sigPath}, 30000, &code);
    return code == 0;
}

bool debianPackageInstalled(const QString &packageName)
{
    if (packageName.trimmed().isEmpty() || !QFileInfo::exists(QStringLiteral("/usr/bin/dpkg-query")))
        return false;
    int exitCode = -1;
    const QByteArray output = runReadOnlyCommand(
        QStringLiteral("/usr/bin/dpkg-query"),
        {QStringLiteral("-W"), QStringLiteral("-f=${Status}"), packageName},
        2500,
        &exitCode
    );
    return exitCode == 0 && output.contains("install ok installed");
}

bool systemdUnitExists(const QString &unit)
{
    const QString name = unit.trimmed();
    if (name.isEmpty() || !QFileInfo::exists(QStringLiteral("/usr/bin/systemctl")))
        return false;
    int exitCode = -1;
    const QByteArray output = runReadOnlyCommand(
        QStringLiteral("/usr/bin/systemctl"),
        {QStringLiteral("show"), QStringLiteral("--property=LoadState"), QStringLiteral("--value"), name},
        2500,
        &exitCode
    ).trimmed();
    return exitCode == 0 && output != "not-found" && !output.isEmpty();
}

bool dockerObjectExists(const QStringList &arguments)
{
    if (!QFileInfo::exists(QStringLiteral("/usr/bin/docker")))
        return false;
    int exitCode = -1;
    runReadOnlyCommand(QStringLiteral("/usr/bin/docker"), arguments, 3500, &exitCode);
    return exitCode == 0;
}


bool tcpEndpointAvailable(const QString &host, quint16 port)
{
    QTcpSocket socket;
    socket.connectToHost(host, port);
    const bool connected = socket.waitForConnected(500);
    if (connected)
        socket.disconnectFromHost();
    return connected;
}

qulonglong decimalSizeToBytes(QString number, QString unit)
{
    number.remove(QLatin1Char(','));
    bool ok = false;
    const double value = number.toDouble(&ok);
    if (!ok || value < 0)
        return 0;
    unit = unit.trimmed().toUpper();
    double multiplier = 1.0;
    if (unit == QStringLiteral("KB")) multiplier = 1000.0;
    else if (unit == QStringLiteral("MB")) multiplier = 1000.0 * 1000.0;
    else if (unit == QStringLiteral("GB")) multiplier = 1000.0 * 1000.0 * 1000.0;
    else if (unit == QStringLiteral("TB")) multiplier = 1000.0 * 1000.0 * 1000.0 * 1000.0;
    return static_cast<qulonglong>(value * multiplier + 0.5);
}

bool aptSimulationSizes(const QStringList &packages, qulonglong *downloadBytes, qulonglong *installedBytes)
{
    if (downloadBytes)
        *downloadBytes = 0;
    if (installedBytes)
        *installedBytes = 0;
    if (packages.isEmpty())
        return true;
    if (!QFileInfo::exists(QStringLiteral("/usr/bin/apt-get")))
        return false;

    QStringList args{QStringLiteral("-s"), QStringLiteral("--no-install-recommends"), QStringLiteral("install")};
    args.append(packages);
    int exitCode = -1;
    const QString output = QString::fromUtf8(runReadOnlyCommand(QStringLiteral("/usr/bin/apt-get"), args, 8000, &exitCode));
    if (exitCode != 0)
        return false;

    const QRegularExpression downloadRx(
        QStringLiteral(R"(Need to get\s+([0-9.,]+)\s*([kMGT]?B)\s+of archives)"),
        QRegularExpression::CaseInsensitiveOption
    );
    const QRegularExpression installedRx(
        QStringLiteral(R"(After this operation,\s+([0-9.,]+)\s*([kMGT]?B)\s+of additional disk space will be used)"),
        QRegularExpression::CaseInsensitiveOption
    );
    const auto downloadMatch = downloadRx.match(output);
    const auto installedMatch = installedRx.match(output);
    if (downloadBytes && downloadMatch.hasMatch())
        *downloadBytes = decimalSizeToBytes(downloadMatch.captured(1), downloadMatch.captured(2));
    if (installedBytes && installedMatch.hasMatch())
        *installedBytes = decimalSizeToBytes(installedMatch.captured(1), installedMatch.captured(2));

    // APT may omit the "Need to get" line when all archives are already cached.
    // That is still a valid zero-download estimate.
    return true;
}

qulonglong architectureSizeHint(const QVariantMap &requirement, const QString &baseKey, const QString &arch)
{
    const QVariantMap byArch = requirement.value(baseKey + QStringLiteral("ByArch")).toMap();
    if (!byArch.isEmpty()) {
        if (byArch.contains(arch))
            return byArch.value(arch).toULongLong();
        const QString alternate = arch == QStringLiteral("aarch64") ? QStringLiteral("arm64") :
                                  arch == QStringLiteral("amd64") ? QStringLiteral("x86_64") : QString();
        if (!alternate.isEmpty() && byArch.contains(alternate))
            return byArch.value(alternate).toULongLong();
    }
    return requirement.value(baseKey, 0).toULongLong();
}
}

AppStoreManager::AppStoreManager(
    const QString &neutronRoot,
    AppManager *appManager,
    DeveloperModeManager *developerModeManager,
    SecurityCoreManager *securityCoreManager,
    QObject *parent
)
    : QObject(parent)
    , m_neutronRoot(QDir::cleanPath(neutronRoot))
    , m_appManager(appManager)
    , m_developerModeManager(developerModeManager)
    , m_securityCoreManager(securityCoreManager)
    , m_network(new QNetworkAccessManager(this))
    , m_operationProcess(new QProcess(this))
    , m_rebuildProcess(new QProcess(this))
{
    ensureDirectories();
    ensureDefaultConfiguration();

    // This read is fail-closed and one-shot. A valid record can only have been
    // armed by this App Store after a signed package transaction and successful
    // rebuild. It is consumed before the ordinary login surface is shown.
    consumeStartupResume();

    // Catalog and repository parsing are not required to render Login. Keep
    // construction cheap and warm the App Store after the shell is visible.
    QTimer::singleShot(2200, this, [this]() {
        loadRepositories();
        loadInstalledRegistry();
        loadCatalogCache();
        rebuildCatalog();
    });

    if (m_developerModeManager) {
        connect(m_developerModeManager, &DeveloperModeManager::developerModeChanged,
                this, &AppStoreManager::developerModeChanged);
    }

    connect(m_operationProcess, &QProcess::readyReadStandardOutput, this, [this]() {
        const QByteArray bytes = m_operationProcess->readAllStandardOutput();
        m_operationOutput += bytes;
        consumeOperationBytes(bytes);
    });
    connect(m_operationProcess, &QProcess::readyReadStandardError, this, [this]() {
        m_operationOutput += m_operationProcess->readAllStandardError();
    });
    connect(m_operationProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
        const QByteArray finalStandardOutput = m_operationProcess->readAllStandardOutput();
        m_operationOutput += finalStandardOutput;
        consumeOperationBytes(finalStandardOutput);
        m_operationOutput += m_operationProcess->readAllStandardError();

        const QVariantMap result = parseLastJsonObject(m_operationOutput);
        QString message = result.value(QStringLiteral("message")).toString().trimmed();
        if (message.isEmpty())
            message = QString::fromUtf8(m_operationOutput).trimmed();
        if (message.isEmpty())
            message = exitCode == 0 ? QStringLiteral("Operation completed")
                                    : QStringLiteral("Package operation failed");

        const bool success = exitStatus == QProcess::NormalExit && exitCode == 0;
        if (success) {
            loadInstalledRegistry();
            rebuildCatalog();
            if (m_appManager)
                m_appManager->rediscoverApps();

            if (result.value(QStringLiteral("requiresRebuild")).toBool()) {
                finishOperation(false, QStringLiteral("Package requires an unsupported OS rebuild; install a precompiled compatible NAPP."));
                return;
            }
        }
        finishOperation(success, message);
    });

    m_rebuildProcess->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_rebuildProcess, &QProcess::readyRead, this, &AppStoreManager::consumeRebuildOutput);
    connect(m_rebuildProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            &AppStoreManager::handleRebuildFinished);
}

AppStoreManager::~AppStoreManager() = default;

QVariantList AppStoreManager::catalog() const { return m_catalog; }
QVariantList AppStoreManager::repositories() const { return m_repositories; }
QStringList AppStoreManager::categories() const { return m_categories; }
int AppStoreManager::availableCount() const
{
    int count = 0;
    for (const QVariant &value : m_catalog) {
        if (value.toMap().value(QStringLiteral("storeEligible")).toBool())
            ++count;
    }
    return count;
}

int AppStoreManager::updateCount() const
{
    int count = 0;
    for (const QVariant &value : m_catalog) {
        if (value.toMap().value(QStringLiteral("updateEligible")).toBool())
            ++count;
    }
    return count;
}

bool AppStoreManager::busy() const { return m_busy; }
bool AppStoreManager::repositoryConnected() const { return m_repositoryConnected; }
QString AppStoreManager::activeOperation() const { return m_activeOperation; }
QString AppStoreManager::activePackageId() const { return m_activePackageId; }
QString AppStoreManager::statusMessage() const { return m_statusMessage; }
QString AppStoreManager::lastError() const { return m_lastError; }
double AppStoreManager::progress() const { return m_progress; }

bool AppStoreManager::developerModeEnabled() const
{
    return m_developerModeManager && m_developerModeManager->developerModeEnabled();
}

QString AppStoreManager::configDirectory() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("config/app-store"));
}

QString AppStoreManager::stateDirectory() const
{
    const QString stateRoot = HumanHome::appStateRoot();
    return QDir(stateRoot).filePath(QStringLiteral("apps"));
}

QString AppStoreManager::repositoriesPath() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("repositories.json"));
}

QString AppStoreManager::catalogCachePath() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("catalog-cache.json"));
}

QString AppStoreManager::installedRegistryPath() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("installed.json"));
}

QString AppStoreManager::downloadDirectory() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("downloads"));
}

QString AppStoreManager::helperScriptPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("scripts/neutronos-appstore-package.py"));
}

QString AppStoreManager::versionPath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("config/version.json"));
}


QVariantMap AppStoreManager::uninstallPlan(const QString &packageId) const
{
    const QString id = normalizeId(packageId);
    const QVariantMap record = m_installedRegistry.value(id).toMap();
    if (record.isEmpty())
        return {};

    QStringList packageFiles = variantStringList(record.value(QStringLiteral("files")));
    QStringList buildFiles = variantStringList(record.value(QStringLiteral("buildFiles")));
    QStringList stateItems = variantStringList(record.value(QStringLiteral("uninstallState")));
    QStringList systemFiles;
    const QVariantList systemEntries = record.value(QStringLiteral("systemFiles")).toList();
    for (const QVariant &value : systemEntries) {
        const QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("ownership")).toString().trimmed().toLower() != QStringLiteral("package"))
            continue;
        const QString destination = entry.value(QStringLiteral("destination")).toString().trimmed();
        if (!destination.isEmpty() && !systemFiles.contains(destination))
            systemFiles.append(destination);
    }
    QStringList preservedDependencies = variantStringList(record.value(QStringLiteral("debianDependencies")));
    QStringList removeItems;
    for (const QStringList *group : {&packageFiles, &buildFiles, &stateItems, &systemFiles}) {
        for (const QString &entry : *group) {
            if (!entry.trimmed().isEmpty() && !removeItems.contains(entry))
                removeItems.append(entry);
        }
    }
    QVariantMap result;
    result.insert(QStringLiteral("known"), true);
    result.insert(QStringLiteral("packageFiles"), packageFiles);
    result.insert(QStringLiteral("buildFiles"), buildFiles);
    result.insert(QStringLiteral("stateItems"), stateItems);
    result.insert(QStringLiteral("systemFiles"), systemFiles);
    result.insert(QStringLiteral("removeItems"), removeItems);
    result.insert(QStringLiteral("removeCount"), removeItems.size());
    result.insert(QStringLiteral("dependenciesRemoved"), QStringList{});
    result.insert(QStringLiteral("dependenciesPreserved"), preservedDependencies);
    result.insert(QStringLiteral("sharedDependenciesPreserved"), true);
    return result;
}

QString AppStoreManager::appStoreRootPath() const { return stateDirectory(); }

QString AppStoreManager::manualPackageDirectory() const
{
    return QDir(stateDirectory()).filePath(QStringLiteral("packages"));
}

void AppStoreManager::ensureDirectories()
{
    if (HumanHome::path().isEmpty()) { QDir().mkpath(stateDirectory()); return; }
    const QStringList paths = {
        stateDirectory(),
        downloadDirectory(),
        QDir(stateDirectory()).filePath(QStringLiteral("staging")),
        QDir(stateDirectory()).filePath(QStringLiteral("rollback")),
        QDir(stateDirectory()).filePath(QStringLiteral("payload")),
        manualPackageDirectory()
    };
    for (const QString &path : paths)
        QDir().mkpath(path);
}

void AppStoreManager::ensureDefaultConfiguration()
{
    if (!QFileInfo::exists(repositoriesPath())) {
        const QVariantMap defaults = readJsonObject(
            QDir(configDirectory()).filePath(QStringLiteral("repositories.json"))
        );
        if (!defaults.isEmpty())
            writeJsonObject(repositoriesPath(), defaults);
    }

    if (!QFileInfo::exists(installedRegistryPath())) {
        QVariantMap root;
        root.insert(QStringLiteral("schema"), kSchemaVersion);
        root.insert(QStringLiteral("packages"), QVariantMap());
        writeJsonObject(installedRegistryPath(), root);
    }
}

QVariantMap AppStoreManager::readJsonObject(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return {};
    return document.object().toVariantMap();
}

bool AppStoreManager::writeJsonObject(const QString &path, const QVariantMap &object) const
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(QJsonObject::fromVariantMap(object)).toJson(QJsonDocument::Indented));
    return file.commit();
}

void AppStoreManager::loadRepositories()
{
    const QVariantMap root = readJsonObject(repositoriesPath());
    m_repositories = root.value(QStringLiteral("repositories")).toList();
    // Existing 0.5.3 user state may still reference the Apollo catalog.
    // Never query it on Gemini, even before a settings migration is saved.
    if (currentPlatform() == QStringLiteral("gemini")) {
        for (QVariant &value : m_repositories) {
            QVariantMap repo = value.toMap();
            if (repo.value(QStringLiteral("id")).toString() == QStringLiteral("neutronos-official")) {
                repo.insert(QStringLiteral("url"), QStringLiteral("https://raw.githubusercontent.com/OGDrNeutron/NeutronOS/main/Apps/Gemini/index.json"));
                value = repo;
            }
        }
    }
    emit repositoriesChanged();
}

void AppStoreManager::loadInstalledRegistry()
{
    const QVariantMap root = readJsonObject(installedRegistryPath());
    m_installedRegistry = root.value(QStringLiteral("packages")).toMap();
}

void AppStoreManager::loadCatalogCache()
{
    // A plain user-state cache has no signed bytes to authenticate. Refresh
    // from the independently signed catalog before exposing install actions.
    m_remoteCatalog.clear();
}

void AppStoreManager::saveCatalogCache() const
{
    QVariantMap root;
    root.insert(QStringLiteral("schema"), kSchemaVersion);
    root.insert(QStringLiteral("refreshedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    root.insert(QStringLiteral("packages"), m_remoteCatalog);
    writeJsonObject(catalogCachePath(), root);
}

void AppStoreManager::reload()
{
    ensureDirectories();
    ensureDefaultConfiguration();
    loadRepositories();
    loadInstalledRegistry();
    loadCatalogCache();
    rebuildCatalog();
}

void AppStoreManager::refreshCatalog()
{
    if (m_busy)
        return;

    loadRepositories();
    m_remoteCatalog.clear();
    m_pendingCatalogReplies = 0;
    m_successfulCatalogSources = 0;
    m_usedBundledCatalog = false;
    setBusy(true);
    setProgress(0.0);
    setStatus(QStringLiteral("Refreshing trusted repositories"));

    for (const QVariant &value : std::as_const(m_repositories)) {
        const QVariantMap repository = value.toMap();
        if (!boolValue(repository, QStringLiteral("enabled"), true))
            continue;
        fetchRepository(repository);
    }

    if (m_pendingCatalogReplies == 0)
        finishCatalogRefresh();
}

bool AppStoreManager::loadBundledGeminiCatalog(const QVariantMap &repository)
{
    if (currentPlatform() != QStringLiteral("gemini") ||
        repository.value(QStringLiteral("id")).toString() != QStringLiteral("neutronos-official")) return false;
    const QString path = QDir(m_neutronRoot).filePath(QStringLiteral("config/app-store/repository/Gemini/index.json"));
    QFile document(path), signature(path + QStringLiteral(".sig"));
    if (!document.open(QIODevice::ReadOnly) || !signature.open(QIODevice::ReadOnly)) return false;
    const QByteArray bytes = document.readAll();
    if (!verifyReleaseSignature(bytes, signature.readAll())) return false;
    QVariantMap bundled = repository;
    bundled.insert(QStringLiteral("url"), path);
    consumeRepositoryDocument(bytes, bundled);
    m_usedBundledCatalog = true;
    return true;
}

void AppStoreManager::fetchRepository(const QVariantMap &repository)
{
    const QUrl url(cleanText(repository.value(QStringLiteral("url"))));
    if (!url.isValid() || url.isEmpty())
        return;

    if (url.isLocalFile() || url.scheme().isEmpty()) {
        QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
        if (QDir::isRelativePath(path))
            path = QDir(m_neutronRoot).filePath(path);
        QFile file(path);
        QFile signature(path + QStringLiteral(".sig"));
        if (file.open(QIODevice::ReadOnly) && signature.open(QIODevice::ReadOnly)) {
            const QByteArray document = file.readAll(), sig = signature.readAll();
            if (verifyReleaseSignature(document, sig)) {
                consumeRepositoryDocument(document, repository);
                ++m_successfulCatalogSources;
            }
        }
        return;
    }

    if (url.scheme() != QStringLiteral("https") && url.scheme() != QStringLiteral("http"))
        return;

    QUrl requestUrl(url);
    QUrlQuery query(requestUrl);
    query.addQueryItem(QStringLiteral("_neutron_refresh"),
                       QString::number(QDateTime::currentMSecsSinceEpoch()));
    requestUrl.setQuery(query);

    QNetworkRequest request(requestUrl);
    request.setTransferTimeout(15000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("NeutronOS-AppStore/1.0"));
    request.setRawHeader(QByteArrayLiteral("Cache-Control"), QByteArrayLiteral("no-cache"));
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                         QNetworkRequest::AlwaysNetwork);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = m_network->get(request);
    m_replyRepositories.insert(reply, repository);
    ++m_pendingCatalogReplies;

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QVariantMap repository = m_replyRepositories.take(reply);
        if (reply->error() != QNetworkReply::NoError) {
            if (loadBundledGeminiCatalog(repository)) ++m_successfulCatalogSources;
            reply->deleteLater();
            --m_pendingCatalogReplies;
            if (m_pendingCatalogReplies == 0) finishCatalogRefresh();
            return;
        }
        const QByteArray document = reply->readAll();
        QUrl signatureUrl = reply->url();
        signatureUrl.setQuery(QString());
        signatureUrl.setPath(signatureUrl.path() + QStringLiteral(".sig"));
        QNetworkRequest signatureRequest(signatureUrl);
        signatureRequest.setTransferTimeout(15000);
        signatureRequest.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                                      QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply *sigReply = m_network->get(signatureRequest);
        connect(sigReply, &QNetworkReply::finished, this, [this, sigReply, document, repository]() {
            if (sigReply->error() == QNetworkReply::NoError &&
                verifyReleaseSignature(document, sigReply->readAll())) {
                consumeRepositoryDocument(document, repository);
                ++m_successfulCatalogSources;
            } else if (loadBundledGeminiCatalog(repository)) {
                ++m_successfulCatalogSources;
            }
            sigReply->deleteLater();
            --m_pendingCatalogReplies;
            if (m_pendingCatalogReplies == 0) finishCatalogRefresh();
        });
        reply->deleteLater();
    });
}

void AppStoreManager::consumeRepositoryDocument(
    const QByteArray &bytes,
    const QVariantMap &repository
)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(bytes, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return;

    const QJsonObject root = document.object();
    if (root.value(QStringLiteral("schema")).toInt(1) != kSchemaVersion)
        return;

    const QVariantList packages = jsonArrayToVariantList(root.value(QStringLiteral("packages")));
    for (const QVariant &value : packages) {
        QVariantMap package = normalizedPackage(value.toMap(), repository);
        if (!package.value(QStringLiteral("id")).toString().isEmpty() &&
            variantStringList(package.value(QStringLiteral("platforms"))).contains(currentPlatform()) &&
            ([&package, this]() {
                for (const QString &candidate : variantStringList(package.value(QStringLiteral("architectures"))))
                    if (canonicalArch(candidate) == currentArchitecture()) return true;
                return false;
            })()) {
            package.insert(QStringLiteral("catalogVerified"), true);
            m_remoteCatalog.append(package);
        }
    }
}

void AppStoreManager::finishCatalogRefresh()
{
    saveCatalogCache();
    rebuildCatalog();
    setProgress(1.0);
    setBusy(false);
    const bool connected = m_successfulCatalogSources > 0;
    setRepositoryConnected(connected);
    if (connected || !m_remoteCatalog.isEmpty())
        setStatus(m_usedBundledCatalog
                      ? QStringLiteral("Verified bundled Gemini catalog; remote unavailable")
                      : QStringLiteral("Catalog refreshed"));
    else
        setStatus(QStringLiteral("Catalog refresh completed; no repository data was available"));
}

QVariantMap AppStoreManager::normalizedPackage(
    QVariantMap package,
    const QVariantMap &repository
) const
{
    const QString id = normalizeId(package.value(QStringLiteral("id")).toString());
    package.insert(QStringLiteral("id"), id);
    if (!package.contains(QStringLiteral("name")))
        package.insert(QStringLiteral("name"), id);
    if (!package.contains(QStringLiteral("version")))
        package.insert(QStringLiteral("version"), QStringLiteral("0.0.0"));
    if (!package.contains(QStringLiteral("category")))
        package.insert(QStringLiteral("category"), QStringLiteral("Apps"));
    if (!package.contains(QStringLiteral("permissions")))
        package.insert(QStringLiteral("permissions"), QVariantList());
    if (!package.contains(QStringLiteral("dependencies"))) {
        package.insert(QStringLiteral("dependencies"),
                       package.value(QStringLiteral("debianDependencies"), QVariantList()));
    }
    if (!package.contains(QStringLiteral("sizeBytes")))
        package.insert(QStringLiteral("sizeBytes"), package.value(QStringLiteral("size"), 0));
    if (!package.contains(QStringLiteral("installedBytes")))
        package.insert(QStringLiteral("installedBytes"), package.value(QStringLiteral("sizeBytes"), 0));
    if (!package.contains(QStringLiteral("screenshots")))
        package.insert(QStringLiteral("screenshots"), QVariantList());

    package.insert(QStringLiteral("repositoryId"), repository.value(QStringLiteral("id")));
    package.insert(QStringLiteral("repositoryName"), repository.value(QStringLiteral("name")));

    const QString repositoryUrlText = cleanText(repository.value(QStringLiteral("url")));
    QUrl repositoryUrl(repositoryUrlText);
    if (repositoryUrl.scheme().isEmpty() && QDir::isRelativePath(repositoryUrlText))
        repositoryUrl = QUrl::fromLocalFile(QDir(m_neutronRoot).filePath(repositoryUrlText));
    const QUrl repositoryBase = repositoryUrl.adjusted(QUrl::RemoveFilename);
    package.insert(QStringLiteral("repositoryBaseUrl"), repositoryBase.toString());
    const QString packageUrlText = cleanText(package.value(QStringLiteral("packageUrl")));
    if (!packageUrlText.isEmpty()) {
        const QUrl packageUrl(packageUrlText);
        if (packageUrl.isRelative())
            package.insert(QStringLiteral("packageUrl"), repositoryBase.resolved(packageUrl).toString());
    }

    for (const QString &assetKey : {QStringLiteral("icon"), QStringLiteral("poster")}) {
        const QString assetText = cleanText(package.value(assetKey));
        if (assetText.contains(QLatin1Char('/'))) {
            const QUrl assetUrl(assetText);
            if (assetUrl.isRelative())
                package.insert(assetKey, repositoryBase.resolved(assetUrl).toString());
        }
    }
    QVariantList resolvedScreenshots;
    for (const QVariant &screenValue : package.value(QStringLiteral("screenshots")).toList()) {
        const QString screenText = screenValue.toString().trimmed();
        const QUrl screenUrl(screenText);
        resolvedScreenshots.append(screenUrl.isRelative()
                                       ? repositoryBase.resolved(screenUrl).toString()
                                       : screenText);
    }
    package.insert(QStringLiteral("screenshots"), resolvedScreenshots);
    package.insert(QStringLiteral("repositoryTrusted"),
                   boolValue(repository, QStringLiteral("trusted"), false));
    if (cleanText(package.value(QStringLiteral("keyId"))).isEmpty())
        package.insert(QStringLiteral("keyId"), repository.value(QStringLiteral("keyId")));
    package.insert(QStringLiteral("localOnly"), false);
    return package;
}

QVariantList AppStoreManager::scanLocalApplications() const
{
    QVariantList result;
    const QDir appsDir(QDir(m_neutronRoot).filePath(QStringLiteral("qml/apps")));
    const QFileInfoList directories = appsDir.entryInfoList(
        QDir::Dirs | QDir::NoDotAndDotDot,
        QDir::Name | QDir::IgnoreCase
    );

    for (const QFileInfo &directory : directories) {
        const QString manifestPath = QDir(directory.absoluteFilePath())
                                         .filePath(QStringLiteral("app.json"));
        QVariantMap manifest = readJsonObject(manifestPath);
        if (manifest.isEmpty() || !QFileInfo::exists(
                QDir(directory.absoluteFilePath()).filePath(QStringLiteral("Main.qml")))) {
            continue;
        }

        const QString id = normalizeId(
            manifest.value(QStringLiteral("id"), directory.fileName()).toString()
        );
        manifest.insert(QStringLiteral("id"), id);
        manifest.insert(QStringLiteral("name"),
                        manifest.value(QStringLiteral("name"), id));
        manifest.insert(QStringLiteral("version"),
                        manifest.value(QStringLiteral("version"), QStringLiteral("0.0.0")));
        manifest.insert(QStringLiteral("category"),
                        manifest.value(QStringLiteral("category"), QStringLiteral("Apps")));
        manifest.insert(QStringLiteral("description"),
                        manifest.value(QStringLiteral("description"),
                                       QStringLiteral("Installed NeutronOS application")));
        manifest.insert(QStringLiteral("permissions"),
                        manifest.value(QStringLiteral("permissions"), QVariantList()));
        manifest.insert(QStringLiteral("screenshots"),
                        manifest.value(QStringLiteral("screenshots"), QVariantList()));
        manifest.insert(QStringLiteral("installed"), true);
        manifest.insert(QStringLiteral("installedVersion"),
                        manifest.value(QStringLiteral("version")));
        manifest.insert(QStringLiteral("localOnly"), true);
        manifest.insert(QStringLiteral("protected"), !m_installedRegistry.contains(id));
        manifest.insert(QStringLiteral("repositoryName"), QStringLiteral("Installed locally"));
        result.append(manifest);
    }
    return result;
}

QVariantMap AppStoreManager::storefrontStatusForPackage(const QVariantMap &package) const
{
    QStringList reasons;

    if (package.value(QStringLiteral("localOnly")).toBool())
        reasons.append(QStringLiteral("Local applications are managed in Settings"));
    if (!package.value(QStringLiteral("repositoryTrusted")).toBool())
        reasons.append(QStringLiteral("Repository is not trusted"));

    const QString packageUrl = cleanText(package.value(QStringLiteral("packageUrl")));
    if (packageUrl.isEmpty())
        reasons.append(QStringLiteral("Package download URL is missing"));

    const QString digest = cleanText(package.value(QStringLiteral("sha256"))).toLower();
    static const QRegularExpression digestPattern(QStringLiteral("^[0-9a-f]{64}$"));
    if (!digestPattern.match(digest).hasMatch())
        reasons.append(QStringLiteral("SHA-256 package digest is missing or invalid"));

    if (!package.value(QStringLiteral("catalogVerified")).toBool())
        reasons.append(QStringLiteral("Catalog release signature is not verified"));
    if (!variantStringList(package.value(QStringLiteral("platforms"))).contains(currentPlatform()))
        reasons.append(QStringLiteral("Package platform is incompatible"));
    bool archMatch = false;
    for (const QString &candidate : variantStringList(package.value(QStringLiteral("architectures"))))
        if (canonicalArch(candidate) == currentArchitecture()) archMatch = true;
    if (!archMatch) reasons.append(QStringLiteral("Package CPU architecture is incompatible"));

    const bool signatureReady = reasons.isEmpty();
    QVariantMap result;
    result.insert(QStringLiteral("signatureReady"), signatureReady);
    result.insert(QStringLiteral("reasons"), reasons);
    result.insert(QStringLiteral("status"), signatureReady
                  ? QStringLiteral("Authenticated catalog; NAPP verified before install")
                  : reasons.join(QStringLiteral(" • ")));
    return result;
}

QVariantMap AppStoreManager::decoratedPackage(QVariantMap package) const
{
    const QString id = normalizeId(package.value(QStringLiteral("id")).toString());
    QVariantMap installed = m_installedRegistry.value(id).toMap();
    if (!installed.isEmpty() &&
        !variantStringList(installed.value(QStringLiteral("platforms"))).contains(currentPlatform()))
        installed.clear();
    QString localVersion = installed.value(QStringLiteral("version")).toString();

    if (localVersion.isEmpty()) {
        const QString manifestPath = QDir(m_neutronRoot).filePath(
            QStringLiteral("qml/apps/%1/app.json").arg(id)
        );
        localVersion = readJsonObject(manifestPath).value(QStringLiteral("version")).toString();
    }

    const bool installedFlag = QFileInfo::exists(
        QDir(m_neutronRoot).filePath(QStringLiteral("qml/apps/%1/Main.qml").arg(id))
    ) || !installed.isEmpty();
    const QString availableVersion = package.value(QStringLiteral("version")).toString();
    const bool updateFlag = installedFlag && !localVersion.isEmpty() &&
        compareVersions(availableVersion, localVersion) > 0;

    package.insert(QStringLiteral("installed"), installedFlag);
    package.insert(QStringLiteral("installedVersion"), localVersion);
    package.insert(QStringLiteral("updateAvailable"), updateFlag);
    package.insert(QStringLiteral("managed"), !installed.isEmpty());
    package.insert(QStringLiteral("rollbackAvailable"),
                   installed.value(QStringLiteral("rollbackAvailable"), false).toBool());

    const QVariantMap compatibility = compatibilityForPackage(package);
    const bool compatible = compatibility.value(QStringLiteral("compatible")).toBool();
    package.insert(QStringLiteral("compatible"), compatible);
    package.insert(QStringLiteral("compatibilityReasons"),
                   compatibility.value(QStringLiteral("reasons")));
    package.insert(QStringLiteral("availableBytes"),
                   compatibility.value(QStringLiteral("availableBytes")));
    package.insert(QStringLiteral("legacyAdoption"),
                   compatibility.value(QStringLiteral("legacyAdoption"), false));
    package.insert(QStringLiteral("legacyVersion"),
                   compatibility.value(QStringLiteral("legacyVersion")));

    const QVariantMap storefront = storefrontStatusForPackage(package);
    const bool signatureReady = storefront.value(QStringLiteral("signatureReady")).toBool();
    package.insert(QStringLiteral("signatureReady"), signatureReady);
    package.insert(QStringLiteral("signatureStatus"), storefront.value(QStringLiteral("status")));
    package.insert(QStringLiteral("signatureReasons"), storefront.value(QStringLiteral("reasons")));
    package.insert(QStringLiteral("storeEligible"),
                   !installedFlag && compatible && signatureReady);
    package.insert(QStringLiteral("updateEligible"),
                   updateFlag && compatible && signatureReady);

    if (!package.contains(QStringLiteral("developer")))
        package.insert(QStringLiteral("developer"), package.value(QStringLiteral("author"), QStringLiteral("NeutronOS Developer")));
    if (!package.contains(QStringLiteral("shortDescription")))
        package.insert(QStringLiteral("shortDescription"), package.value(QStringLiteral("subtitle"), package.value(QStringLiteral("description"))));
    if (!package.contains(QStringLiteral("ageRating")))
        package.insert(QStringLiteral("ageRating"), QStringLiteral("Everyone"));
    if (!package.contains(QStringLiteral("rating")))
        package.insert(QStringLiteral("rating"), 0.0);
    if (!package.contains(QStringLiteral("ratingCount")))
        package.insert(QStringLiteral("ratingCount"), 0);
    if (!package.contains(QStringLiteral("featured")))
        package.insert(QStringLiteral("featured"), false);

    return package;
}

void AppStoreManager::rebuildCatalog()
{
    QHash<QString, QVariantMap> merged;

    // The storefront is built only from repository packages. Installed local apps
    // remain visible in Settings > Apps & Services > App Manager, not in the store.
    for (const QVariant &value : std::as_const(m_remoteCatalog)) {
        QVariantMap package = value.toMap();
        const QString id = normalizeId(package.value(QStringLiteral("id")).toString());
        if (id.isEmpty())
            continue;
        if (!merged.contains(id) ||
            compareVersions(package.value(QStringLiteral("version")).toString(),
                            merged.value(id).value(QStringLiteral("version")).toString()) > 0) {
            merged.insert(id, package);
        }
    }

    QList<QVariantMap> packages;
    packages.reserve(merged.size());
    for (auto it = merged.cbegin(); it != merged.cend(); ++it)
        packages.append(decoratedPackage(it.value()));

    std::sort(packages.begin(), packages.end(), [](const QVariantMap &left, const QVariantMap &right) {
        const bool leftFeatured = left.value(QStringLiteral("featured")).toBool();
        const bool rightFeatured = right.value(QStringLiteral("featured")).toBool();
        if (leftFeatured != rightFeatured)
            return leftFeatured;
        return left.value(QStringLiteral("name")).toString().localeAwareCompare(
                   right.value(QStringLiteral("name")).toString()) < 0;
    });

    m_catalog.clear();
    QSet<QString> categorySet;
    for (const QVariantMap &package : std::as_const(packages)) {
        m_catalog.append(package);
        if (package.value(QStringLiteral("storeEligible")).toBool()) {
            categorySet.insert(package.value(QStringLiteral("category"),
                                             QStringLiteral("Apps")).toString());
        }
    }

    m_categories = QStringList{QStringLiteral("All")};
    QStringList discovered = categorySet.values();
    discovered.sort(Qt::CaseInsensitive);
    for (const QString &category : discovered) {
        if (!m_categories.contains(category, Qt::CaseInsensitive))
            m_categories.append(category);
    }

    emit catalogChanged();
}

QVariantMap AppStoreManager::packageById(const QString &packageId) const
{
    const QString id = normalizeId(packageId);
    for (const QVariant &value : m_catalog) {
        const QVariantMap package = value.toMap();
        if (package.value(QStringLiteral("id")).toString() == id)
            return package;
    }
    return {};
}

QVariantList AppStoreManager::searchPackages(
    const QString &query,
    const QString &category,
    const QString &filter
) const
{
    const QString needle = query.trimmed().toLower();
    const QString categoryNeedle = category.trimmed().toLower();
    const QString filterNeedle = filter.trimmed().toLower();
    QVariantList result;

    for (const QVariant &value : m_catalog) {
        const QVariantMap package = value.toMap();
        const bool storeEligible = package.value(QStringLiteral("storeEligible")).toBool();
        const bool updateEligible = package.value(QStringLiteral("updateEligible")).toBool();
        const bool installed = package.value(QStringLiteral("installed")).toBool();
        const bool featured = package.value(QStringLiteral("featured")).toBool();

        bool include = false;
        if (filterNeedle == QStringLiteral("updates") ||
            categoryNeedle == QStringLiteral("updates")) {
            include = updateEligible;
        } else if (filterNeedle == QStringLiteral("installed") ||
                   categoryNeedle == QStringLiteral("installed")) {
            include = installed;
        } else if (filterNeedle == QStringLiteral("featured") ||
                   categoryNeedle == QStringLiteral("featured")) {
            include = storeEligible && featured;
        } else {
            include = storeEligible;
        }
        if (!include)
            continue;

        if (!categoryNeedle.isEmpty() && categoryNeedle != QStringLiteral("all") &&
            categoryNeedle != QStringLiteral("updates") &&
            categoryNeedle != QStringLiteral("installed") &&
            categoryNeedle != QStringLiteral("featured") &&
            package.value(QStringLiteral("category")).toString().toLower() != categoryNeedle) {
            continue;
        }

        if (!needle.isEmpty()) {
            const QString haystack = QStringLiteral("%1 %2 %3 %4 %5")
                .arg(package.value(QStringLiteral("name")).toString(),
                     package.value(QStringLiteral("subtitle")).toString(),
                     package.value(QStringLiteral("shortDescription")).toString(),
                     package.value(QStringLiteral("description")).toString(),
                     package.value(QStringLiteral("developer")).toString())
                .toLower();
            if (!haystack.contains(needle))
                continue;
        }
        result.append(package);
    }
    return result;
}

bool AppStoreManager::isInstalled(const QString &packageId) const
{
    return packageById(packageId).value(QStringLiteral("installed")).toBool();
}

QString AppStoreManager::installedVersion(const QString &packageId) const
{
    return packageById(packageId).value(QStringLiteral("installedVersion")).toString();
}

bool AppStoreManager::updateAvailable(const QString &packageId) const
{
    return packageById(packageId).value(QStringLiteral("updateAvailable")).toBool();
}

QVariantMap AppStoreManager::compatibilityFor(const QString &packageId) const
{
    return compatibilityForPackage(packageById(packageId));
}

QVariantMap AppStoreManager::compatibilityForPackage(const QVariantMap &package) const
{
    QVariantMap result;
    QStringList reasons;
    const QString arch = currentArchitecture();
    const QStringList platforms = variantStringList(package.value(QStringLiteral("platforms")));
    if (!platforms.contains(currentPlatform()))
        reasons.append(QStringLiteral("Requires a signed compatible NeutronOS platform"));
    const QStringList architectures = variantStringList(package.value(QStringLiteral("architectures")));
    if (architectures.isEmpty())
        reasons.append(QStringLiteral("Signed CPU architecture is missing"));
    if (!architectures.isEmpty()) {
        bool matched = false;
        for (const QString &candidate : architectures) {
            const QString normalized = canonicalArch(candidate);
            if (normalized == arch) {
                matched = true;
                break;
            }
        }
        if (!matched)
            reasons.append(QStringLiteral("Requires architecture: %1").arg(architectures.join(QStringLiteral(", "))));
    }

    if(package.value(QStringLiteral("rebuildRequired")).toBool() || !package.value(QStringLiteral("buildFiles")).toList().isEmpty())
        reasons.append(QStringLiteral("Requires an obsolete OS rebuild; a precompiled application package is needed"));
    const QVariantMap requirements=package.value(QStringLiteral("osRequirements")).toMap();
    const QVariantMap available=readJsonObject(QStringLiteral("/etc/neutronos/app-capabilities.json"));
    const QVariantMap requested=requirements.value(QStringLiteral("capabilities")).toMap();
    const QVariantMap capabilities=available.value(QStringLiteral("capabilities")).toMap();
    for(auto it=requested.cbegin();it!=requested.cend();++it)
        if(capabilities.value(it.key()).toInt()<it.value().toInt())
            reasons.append(QStringLiteral("Missing OS capability: %1; update NeutronOS first").arg(it.key()));
    const QString requiredQt=requirements.value(QStringLiteral("qtVersion")).toString();
    if(!requiredQt.isEmpty() && requiredQt!=available.value(QStringLiteral("qtVersion")).toString())
        reasons.append(QStringLiteral("Requires a different Qt runtime ABI"));
    const QString currentVersion = currentNeutronVersion();
    const QString minimumVersion = cleanText(package.value(QStringLiteral("minNeutronOS")));
    const QString maximumVersion = cleanText(package.value(QStringLiteral("maxNeutronOS")));
    if (!minimumVersion.isEmpty() && compareVersions(currentVersion, minimumVersion) < 0)
        reasons.append(QStringLiteral("Requires NeutronOS %1 or newer").arg(minimumVersion));
    if (!maximumVersion.isEmpty() && compareVersions(currentVersion, maximumVersion) > 0)
        reasons.append(QStringLiteral("Supports NeutronOS up to %1").arg(maximumVersion));

    const qulonglong requiredBytes = package.value(QStringLiteral("installedBytes"),
                                                    package.value(QStringLiteral("sizeBytes"), 0)).toULongLong();
    const QStorageInfo storage(m_neutronRoot);
    const qulonglong availableBytes = storage.isValid() ? storage.bytesAvailable() : 0;
    const qulonglong safetyMargin = 32ULL * 1024ULL * 1024ULL;
    if (requiredBytes > 0 && availableBytes > 0 && requiredBytes + safetyMargin > availableBytes)
        reasons.append(QStringLiteral("Not enough free storage"));

    if (package.value(QStringLiteral("requiresDeveloperMode"), false).toBool() &&
        !developerModeEnabled()) {
        reasons.append(QStringLiteral("Developer Mode is required"));
    }

    const QString packageId = normalizeId(package.value(QStringLiteral("id")).toString());
    const QString localManifestPath = QDir(m_neutronRoot).filePath(
        QStringLiteral("qml/apps/%1/app.json").arg(packageId)
    );
    const QString localMainPath = QDir(m_neutronRoot).filePath(
        QStringLiteral("qml/apps/%1/Main.qml").arg(packageId)
    );
    const bool localAppExists = !packageId.isEmpty() && QFileInfo::exists(localMainPath);
    const QVariantMap localManifest = localAppExists ? readJsonObject(localManifestPath) : QVariantMap{};
    const QString localManifestId = normalizeId(localManifest.value(QStringLiteral("id")).toString());
    const QString localVersion = localManifest.value(QStringLiteral("version")).toString().trimmed();
    const QString availableVersion = package.value(QStringLiteral("version")).toString().trimmed();
    const QVariantMap installedEntry = m_installedRegistry.value(packageId).toMap();
    const bool appStoreManaged = !installedEntry.isEmpty() &&
        variantStringList(installedEntry.value(QStringLiteral("platforms"))).contains(currentPlatform());
    if (!installedEntry.isEmpty() && !appStoreManaged)
        reasons.append(QStringLiteral("Installed package belongs to an unknown or different NeutronOS platform"));
    const bool developerManual = package.value(QStringLiteral("developerManual"), false).toBool();
    const bool officialRepositoryPackage =
        package.value(QStringLiteral("repositoryId")).toString() == QStringLiteral("neutronos-official") &&
        package.value(QStringLiteral("catalogVerified")).toBool();
    const bool officialSystemPackage =
        package.value(QStringLiteral("systemPackage"), false).toBool() && officialRepositoryPackage;
    const bool legacyAdoption =
        localAppExists && !appStoreManaged && officialRepositoryPackage &&
        !package.value(QStringLiteral("localOnly")).toBool() && !developerManual &&
        !localVersion.isEmpty() && localManifestId == packageId &&
        compareVersions(availableVersion, localVersion) > 0;

    if (localAppExists && !appStoreManaged && !package.value(QStringLiteral("localOnly")).toBool() &&
        !developerManual && !officialSystemPackage && !legacyAdoption) {
        reasons.append(QStringLiteral("A protected built-in app already uses this package id"));
    }

    result.insert(QStringLiteral("legacyAdoption"), legacyAdoption);
    result.insert(QStringLiteral("legacyVersion"), legacyAdoption ? localVersion : QString());
    result.insert(QStringLiteral("compatible"), reasons.isEmpty());
    result.insert(QStringLiteral("reasons"), reasons);
    result.insert(QStringLiteral("architecture"), arch);
    result.insert(QStringLiteral("neutronVersion"), currentVersion);
    result.insert(QStringLiteral("requiredBytes"), requiredBytes);
    result.insert(QStringLiteral("availableBytes"), availableBytes);
    return result;
}

bool AppStoreManager::installPackage(const QString &packageId)
{
    if (!m_applicationSessionId.isEmpty() && m_applicationSessionId == normalizeId(packageId)) {
        setStatus(QStringLiteral("Close the active application session before changing this package"), QStringLiteral("Application session is still running"));
        return false;
    }
    if (m_busy)
        return false;
    const QVariantMap package = packageById(packageId);
    if (package.isEmpty()) {
        setStatus(QStringLiteral("Package was not found"), QStringLiteral("Unknown package"));
        return false;
    }
    if (package.value(QStringLiteral("localOnly")).toBool()) {
        setStatus(QStringLiteral("This installed app has no repository package"),
                  QStringLiteral("No install source"));
        return false;
    }
    const QVariantMap compatibility = compatibilityForPackage(package);
    if (!compatibility.value(QStringLiteral("compatible")).toBool()) {
        setStatus(QStringLiteral("Package is not compatible"),
                  compatibility.value(QStringLiteral("reasons")).toStringList().join(QStringLiteral("; ")));
        return false;
    }
    return beginRemoteInstall(package, QStringLiteral("install"));
}

bool AppStoreManager::updatePackage(const QString &packageId)
{
    if (!m_applicationSessionId.isEmpty() && m_applicationSessionId == normalizeId(packageId)) {
        setStatus(QStringLiteral("Close the active application session before changing this package"), QStringLiteral("Application session is still running"));
        return false;
    }
    if (m_busy)
        return false;
    if (!updateAvailable(packageId)) {
        setStatus(QStringLiteral("No update is available"));
        return false;
    }
    const QVariantMap package = packageById(packageId);
    if (package.isEmpty()) {
        setStatus(QStringLiteral("Package was not found"), QStringLiteral("Unknown package"));
        return false;
    }
    const QVariantMap compatibility = compatibilityForPackage(package);
    if (!compatibility.value(QStringLiteral("compatible")).toBool()) {
        setStatus(QStringLiteral("Update is not compatible"),
                  compatibility.value(QStringLiteral("reasons")).toStringList().join(QStringLiteral("; ")));
        return false;
    }
    return beginRemoteInstall(package, QStringLiteral("update"));
}

bool AppStoreManager::beginRemoteInstall(const QVariantMap &package, const QString &operation)
{
    if (HumanHome::path().isEmpty()) {
        setStatus(QStringLiteral("An authenticated human account with USER DATA storage is required"));
        return false;
    }

    const QString transactionHome = HumanHome::path();
    if (m_busy)
        return false;
    ensureDirectories();
    if (!package.value(QStringLiteral("repositoryTrusted")).toBool()) {
        setStatus(QStringLiteral("Repository is not trusted"),
                  QStringLiteral("Enable trust only after verifying its key"));
        return false;
    }

    const QUrl url(cleanText(package.value(QStringLiteral("packageUrl"))));
    if (!url.isValid() || url.isEmpty()) {
        setStatus(QStringLiteral("Package URL is missing"), QStringLiteral("Invalid catalog entry"));
        return false;
    }

    m_activeOperation = operation;
    m_activePackageId = package.value(QStringLiteral("id")).toString();
    m_pendingPackage = package;
    emit operationStateChanged();
    setBusy(true);
    setProgress(0.0);
    setOperationDetail(QStringLiteral("DOWNLOAD"),
                       operation == QStringLiteral("update")
                           ? QStringLiteral("Downloading signed update package")
                           : QStringLiteral("Downloading signed package"));
    setStatus(operation == QStringLiteral("update")
                  ? QStringLiteral("Downloading update")
                  : QStringLiteral("Downloading package"));

    if (url.isLocalFile() || url.scheme().isEmpty()) {
        QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
        if (QDir::isRelativePath(path))
            path = QDir(m_neutronRoot).filePath(path);
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            finishOperation(false, QStringLiteral("Unable to open package file"));
            return false;
        }
        return consumeDownloadedPackage(file.readAll(), package, operation);
    }

    if (url.scheme() != QStringLiteral("https")) {
        finishOperation(false, QStringLiteral("Trusted repositories must use HTTPS or local files"));
        return false;
    }

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("NeutronOS-AppStore/1.0"));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = m_network->get(request);
    m_packageReply = reply;
    connect(reply, &QNetworkReply::downloadProgress, this,
            [this](qint64 received, qint64 total) {
        if (total > 0) {
            const double ratio = std::clamp(static_cast<double>(received) /
                                            static_cast<double>(total), 0.0, 1.0);
            setProgress(ratio * 0.22);
            setOperationDetail(QStringLiteral("DOWNLOAD"),
                               QStringLiteral("%1 of %2 received")
                                   .arg(formatBytes(static_cast<qulonglong>(std::max<qint64>(0, received))),
                                        formatBytes(static_cast<qulonglong>(std::max<qint64>(0, total)))));
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, package, operation, transactionHome]() {
        m_packageReply.clear();
        if (HumanHome::path() != transactionHome) {
            reply->deleteLater();
            finishOperation(false, QStringLiteral("The human session changed during package download"));
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            const QString error = reply->errorString();
            reply->deleteLater();
            finishOperation(false, error);
            return;
        }
        const QByteArray bytes = reply->readAll();
        reply->deleteLater();
        consumeDownloadedPackage(bytes, package, operation);
    });
    return true;
}

bool AppStoreManager::consumeDownloadedPackage(
    const QByteArray &bytes,
    const QVariantMap &package,
    const QString &operation
)
{
    if (HumanHome::path().isEmpty()) {
        finishOperation(false, QStringLiteral("The human session ended before package staging"));
        return false;
    }
    setProgress(std::max(progress(), 0.24));
    setOperationDetail(QStringLiteral("VERIFY PACKAGE"),
                       QStringLiteral("Checking package checksum and trusted signature"));
    QString error;
    if (!verifyPackageBytes(bytes, package, &error)) {
        finishOperation(false, error);
        return false;
    }

    setProgress(std::max(progress(), 0.28));
    setOperationDetail(QStringLiteral("STAGE PACKAGE"),
                       QStringLiteral("Writing verified package into App Store managed storage"));

    const QString id = package.value(QStringLiteral("id")).toString();
    const QString version = package.value(QStringLiteral("version")).toString();
    const QString fileName = QStringLiteral("%1-%2-%3.napp")
        .arg(id, version, QUuid::createUuid().toString(QUuid::WithoutBraces));
    const QString path = QDir(downloadDirectory()).filePath(fileName);
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) {
        finishOperation(false, QStringLiteral("Unable to save verified package"));
        return false;
    }

    setProgress(0.30);
    setOperationDetail(QStringLiteral("INSPECT PACKAGE"),
                       operation == QStringLiteral("update")
                           ? QStringLiteral("Preparing transactional update")
                           : QStringLiteral("Preparing transactional installation"));
    setStatus(operation == QStringLiteral("update")
                  ? QStringLiteral("Preparing verified update")
                  : QStringLiteral("Preparing verified package"));

    const QString helperCommand = operation == QStringLiteral("update")
        ? QStringLiteral("install")
        : operation;

    QStringList helperArguments{
        helperCommand,
        QStringLiteral("--root"), m_neutronRoot,
        QStringLiteral("--state-root"),
        HumanHome::appStateRoot(),
        QStringLiteral("--package"), path,
        QStringLiteral("--expected-id"), id,
        QStringLiteral("--expected-version"), version,
        QStringLiteral("--expected-sha256"),
        cleanText(package.value(QStringLiteral("sha256"))).toLower(),
        QStringLiteral("--source"), package.value(QStringLiteral("repositoryId")).toString()
    };

    const QVariantMap compatibility = compatibilityForPackage(package);
    if (operation == QStringLiteral("update") &&
        compatibility.value(QStringLiteral("legacyAdoption"), false).toBool()) {
        helperArguments.append(QStringLiteral("--adopt-legacy-source"));
        helperArguments.append(QStringLiteral("--legacy-version"));
        helperArguments.append(compatibility.value(QStringLiteral("legacyVersion")).toString());
    }

    startHelperOperation(operation, id, helperArguments);
    return true;
}

bool AppStoreManager::verifyPackageBytes(const QByteArray &bytes, const QVariantMap &package,
                                         QString *error) const
{
    if (!package.value(QStringLiteral("catalogVerified")).toBool() ||
        !compatibilityForPackage(package).value(QStringLiteral("compatible")).toBool()) {
        if (error) *error = QStringLiteral("Catalog signature or platform compatibility is invalid");
        return false;
    }
    QTemporaryFile temporary(QDir::tempPath() + QStringLiteral("/neutronos-napp-XXXXXX.napp"));
    if (!temporary.open() || temporary.write(bytes) != bytes.size()) {
        if (error) *error = QStringLiteral("Unable to verify downloaded NAPP bytes");
        return false;
    }
    temporary.flush();
    QProcess verifier;
    verifier.start(QStringLiteral("/usr/local/libexec/neutronos-napp-verify"),
        {QStringLiteral("verify"), temporary.fileName(), QStringLiteral("--expected-sha"),
         cleanText(package.value(QStringLiteral("sha256"))).toLower(),
         QStringLiteral("--expected-id"), cleanText(package.value(QStringLiteral("id"))),
         QStringLiteral("--expected-version"), cleanText(package.value(QStringLiteral("version")))});
    if (!verifier.waitForFinished(30000) || verifier.exitCode() != 0) {
        if (error) *error = QString::fromUtf8(verifier.readAllStandardError()).trimmed();
        if (error && error->isEmpty()) *error = QStringLiteral("NAPP release signature or payload is invalid");
        return false;
    }
    const QJsonDocument verified = QJsonDocument::fromJson(verifier.readAllStandardOutput());
    if (!verified.isObject()) {
        if (error) *error = QStringLiteral("NAPP verifier returned invalid metadata");
        return false;
    }
    const QVariantMap signedManifest = verified.object().value(QStringLiteral("manifest")).toObject().toVariantMap();
    if (variantStringList(signedManifest.value(QStringLiteral("platforms"))) !=
            variantStringList(package.value(QStringLiteral("platforms"))) ||
        variantStringList(signedManifest.value(QStringLiteral("architectures"))) !=
            variantStringList(package.value(QStringLiteral("architectures")))) {
        if (error) *error = QStringLiteral("NAPP signed compatibility differs from authenticated catalog");
        return false;
    }
    return true;
}

QVariantMap AppStoreManager::inspectLocalPackage(const QString &path, QString *error) const
{
    QProcess process;
    process.start(QStringLiteral("python3"),
                  QStringList{helperScriptPath(), QStringLiteral("inspect"),
                              QStringLiteral("--root"), m_neutronRoot,
                              QStringLiteral("--package"), path});
    if (!process.waitForStarted(3000) || !process.waitForFinished(15000)) {
        if (error) *error = QStringLiteral("Package inspection timed out");
        return {};
    }
    const QByteArray output = process.readAllStandardOutput();
    const QJsonDocument document = QJsonDocument::fromJson(output.trimmed());
    if (process.exitCode() != 0 || !document.isObject()) {
        if (error) {
            *error = QString::fromUtf8(process.readAllStandardError()).trimmed();
            if (error->isEmpty())
                *error = QStringLiteral("Invalid NeutronOS package");
        }
        return {};
    }
    return document.object().toVariantMap();
}

bool AppStoreManager::installLocalPackage(const QString &packagePath)
{
    Q_UNUSED(packagePath)
    setStatus(QStringLiteral("Gemini requires a release-signed NAPP from an authenticated catalog"));
    return false;
}

QVariantMap AppStoreManager::analyzeLocalPackage(const QString &packagePath)
{
    if (!developerModeEnabled()) {
        setStatus(QStringLiteral("Developer Mode is required"),
                  QStringLiteral("Third-party package analysis is gated by Developer Mode"));
        return {};
    }
    QString path = packagePath.trimmed();
    if (path.startsWith(QStringLiteral("file://")))
        path = QUrl(path).toLocalFile();
    path = QDir::cleanPath(path);
    if (!QFileInfo(path).isFile()) {
        setStatus(QStringLiteral("Manual package was not found"), path);
        return {};
    }
    QProcess process;
    process.setProgram(QStringLiteral("python3"));
    process.setArguments({m_neutronRoot + QStringLiteral("/scripts/neutronos-app-security.py"),
                          QStringLiteral("analyze"), QStringLiteral("--package"), path});
    process.start();
    if (!process.waitForStarted(3000) || !process.waitForFinished(30000)) {
        setStatus(QStringLiteral("Security analysis unavailable"), QStringLiteral("Analysis timed out"));
        return {};
    }
    const QJsonDocument result = QJsonDocument::fromJson(process.readAllStandardOutput());
    if (process.exitCode() != 0 || !result.isObject()) {
        setStatus(QStringLiteral("Package analysis failed"),
                  QString::fromUtf8(process.readAllStandardError()).trimmed());
        return {};
    }
    m_lastSecurityAnalysis = result.object().toVariantMap();
    emit securityAnalysisChanged();
    setStatus(QStringLiteral("Security analysis: %1")
                  .arg(m_lastSecurityAnalysis.value(QStringLiteral("classification")).toString()),
              m_lastSecurityAnalysis.value(QStringLiteral("disclaimer")).toString());
    return m_lastSecurityAnalysis;
}


bool AppStoreManager::removeAnalyzedPackage(const QString &packagePath)
{
    const QFileInfo candidate(QDir::cleanPath(packagePath));
    const QString canonicalRoot = QFileInfo(manualPackageDirectory()).canonicalFilePath();
    const QString canonicalCandidate = candidate.canonicalFilePath();
    if (canonicalRoot.isEmpty() || canonicalCandidate.isEmpty() || candidate.isSymLink() ||
        !canonicalCandidate.startsWith(canonicalRoot + QLatin1Char('/'))) {
        setStatus(QStringLiteral("Removal denied"),
                  QStringLiteral("Only packages in the managed staging directory may be removed"));
        return false;
    }
    if (!QFile::remove(canonicalCandidate)) {
        setStatus(QStringLiteral("Removal failed"),
                  QStringLiteral("The staged package could not be removed"));
        return false;
    }
    m_lastSecurityAnalysis.clear();
    emit securityAnalysisChanged();
    setStatus(QStringLiteral("Staged package removed"));
    return true;
}

bool AppStoreManager::uninstallPackage(const QString &packageId)
{
    if (!m_applicationSessionId.isEmpty() && m_applicationSessionId == normalizeId(packageId)) {
        setStatus(QStringLiteral("Close the active application session before changing this package"), QStringLiteral("Application session is still running"));
        return false;
    }
    if (HumanHome::path().isEmpty()) {
        setStatus(QStringLiteral("An authenticated human account with USER DATA storage is required"));
        return false;
    }

    if (m_busy)
        return false;
    const QString id = normalizeId(packageId);
    if (!m_installedRegistry.contains(id)) {
        setStatus(QStringLiteral("Protected or unmanaged apps cannot be uninstalled here"),
                  QStringLiteral("Only App Store-managed packages are removable"));
        return false;
    }
    m_activeOperation = QStringLiteral("uninstall");
    m_activePackageId = id;
    emit operationStateChanged();
    setBusy(true);
    setProgress(0.04);
    const QVariantMap plan = uninstallPlan(id);
    setOperationDetail(QStringLiteral("PLAN REMOVAL"),
                       QStringLiteral("Preparing exact App Store-owned removal set"),
                       variantStringList(plan.value(QStringLiteral("removeItems"))));
    setStatus(QStringLiteral("Preparing package removal"));
    startHelperOperation(QStringLiteral("uninstall"), id,
                         QStringList{
                             QStringLiteral("uninstall"),
                             QStringLiteral("--root"), m_neutronRoot,
                             QStringLiteral("--state-root"),
                             HumanHome::appStateRoot(),
                             QStringLiteral("--package-id"), id
                         });
    return true;
}

bool AppStoreManager::rollbackPackage(const QString &packageId)
{
    if (!m_applicationSessionId.isEmpty() && m_applicationSessionId == normalizeId(packageId)) {
        setStatus(QStringLiteral("Close the active application session before changing this package"), QStringLiteral("Application session is still running"));
        return false;
    }
    if (HumanHome::path().isEmpty()) {
        setStatus(QStringLiteral("An authenticated human account with USER DATA storage is required"));
        return false;
    }

    if (m_busy)
        return false;
    const QString id = normalizeId(packageId);
    if (!m_installedRegistry.contains(id)) {
        setStatus(QStringLiteral("No App Store transaction exists for this app"));
        return false;
    }
    m_activeOperation = QStringLiteral("rollback");
    m_activePackageId = id;
    emit operationStateChanged();
    setBusy(true);
    setProgress(0.2);
    setStatus(QStringLiteral("Restoring previous package version"));
    startHelperOperation(QStringLiteral("rollback"), id,
                         QStringList{
                             QStringLiteral("rollback"),
                             QStringLiteral("--root"), m_neutronRoot,
                             QStringLiteral("--state-root"),
                             HumanHome::appStateRoot(),
                             QStringLiteral("--package-id"), id
                         });
    return true;
}

void AppStoreManager::startHelperOperation(
    const QString &operation,
    const QString &packageId,
    const QStringList &arguments
)
{
    if (HumanHome::path().isEmpty()) {
        finishOperation(false, QStringLiteral("An authenticated human account is required for package transactions"));
        return;
    }
    if (m_operationProcess->state() != QProcess::NotRunning) {
        finishOperation(false, QStringLiteral("Another package transaction is active"));
        return;
    }
    m_activeOperation = operation;
    m_activePackageId = packageId;
    m_operationOutput.clear();
    m_operationLineBuffer.clear();
    emit operationStateChanged();
    m_operationProcess->setProgram(QStringLiteral("python3"));
    m_operationProcess->setArguments(QStringList{helperScriptPath()} + arguments);
    m_operationProcess->start();
    if (!m_operationProcess->waitForStarted(3000))
        finishOperation(false, QStringLiteral("Unable to start package transaction helper"));
}

void AppStoreManager::finishOperation(bool success, const QString &message)
{
    const QString packageId = m_activePackageId;
    const QString operation = m_activeOperation;
    setProgress(success ? 1.0 : 0.0);
    setBusy(false);
    setStatus(message, success ? QString() : message);
    m_activePackageId.clear();
    m_activeOperation.clear();
    m_pendingPackage.clear();
    m_operationLineBuffer.clear();
    m_operationStage.clear();
    m_operationDetail.clear();
    m_operationItems.clear();
    emit operationDetailChanged();
    emit operationStateChanged();
    emit operationFinished(packageId, operation, success, message);
}


void AppStoreManager::setOperationDetail(
    const QString &stage,
    const QString &detail,
    const QStringList &items
)
{
    const QString normalizedStage = stage.trimmed();
    const QString normalizedDetail = detail.trimmed();
    if (m_operationStage == normalizedStage &&
        m_operationDetail == normalizedDetail &&
        m_operationItems == items)
        return;
    m_operationStage = normalizedStage;
    m_operationDetail = normalizedDetail;
    m_operationItems = items;
    emit operationDetailChanged();
}

void AppStoreManager::applyOperationEvent(const QVariantMap &event)
{
    if (event.value(QStringLiteral("event")).toString() != QStringLiteral("progress"))
        return;
    bool ok = false;
    const double reported = event.value(QStringLiteral("progress")).toDouble(&ok);
    if (ok)
        setProgress(std::max(progress(), std::clamp(reported, 0.0, 1.0)));
    const QString stage = event.value(QStringLiteral("stage")).toString();
    const QString detail = event.value(QStringLiteral("detail")).toString();
    const QStringList items = variantStringList(event.value(QStringLiteral("items")));
    setOperationDetail(stage, detail, items);
    if (!detail.trimmed().isEmpty())
        setStatus(detail);
    else if (!stage.trimmed().isEmpty())
        setStatus(stage);
}

void AppStoreManager::consumeOperationBytes(const QByteArray &bytes)
{
    if (bytes.isEmpty())
        return;
    m_operationLineBuffer += bytes;
    qsizetype newline = -1;
    while ((newline = m_operationLineBuffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_operationLineBuffer.left(newline).trimmed();
        m_operationLineBuffer.remove(0, newline + 1);
        if (line.isEmpty())
            continue;
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error == QJsonParseError::NoError && document.isObject())
            applyOperationEvent(document.object().toVariantMap());
    }
}


QVariantMap AppStoreManager::parseLastJsonObject(const QByteArray &bytes) const
{
    const QList<QByteArray> lines = bytes.split('\n');
    for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
        const QByteArray candidate = it->trimmed();
        if (candidate.isEmpty())
            continue;
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(candidate, &parseError);
        if (parseError.error == QJsonParseError::NoError && document.isObject())
            return document.object().toVariantMap();
    }
    return {};
}

void AppStoreManager::consumeStartupResume()
{
    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(QStringLiteral("sudo"),
                  QStringList{QStringLiteral("-n"),
                              QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                              QStringLiteral("appstore-consume-resume")});
    if (!process.waitForStarted(1500))
        return;
    if (!process.waitForFinished(4000)) {
        process.kill();
        process.waitForFinished(500);
        return;
    }
    const QByteArray output = process.readAll();
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
        return;

    QVariantMap payload = parseLastJsonObject(output);
    if (!payload.value(QStringLiteral("pending")).toBool())
        return;

    payload.insert(QStringLiteral("appId"), QStringLiteral("appstore"));
    payload.insert(QStringLiteral("appName"), QStringLiteral("App Store"));
    payload.insert(QStringLiteral("cleanExit"), true);
    payload.insert(QStringLiteral("message"), QStringLiteral("Rebuild completed and the installed package is active."));
    m_startupResume = payload;
    emit startupResumeChanged();
}

void AppStoreManager::clearStartupResume()
{
    if (m_startupResume.isEmpty())
        return;
    m_startupResume.clear();
    emit startupResumeChanged();
}

void AppStoreManager::setRebuildState(bool rebuilding, double progress, const QString &message)
{
    progress = std::clamp(progress, 0.0, 1.0);
    const bool changed = m_rebuilding != rebuilding ||
                         !qFuzzyCompare(m_rebuildProgress, progress) ||
                         m_rebuildMessage != message;
    m_rebuilding = rebuilding;
    m_rebuildProgress = progress;
    m_rebuildMessage = message;
    setProgress(progress);
    setStatus(message);
    if (changed)
        emit rebuildStateChanged();
}

void AppStoreManager::beginRebuild(const QVariantMap &)
{
    finishOperation(false, QStringLiteral("App Store cannot rebuild operating-system components."));
}


void AppStoreManager::consumeRebuildOutput()
{
    m_rebuildOutput += m_rebuildProcess->readAll();
    if (m_rebuildOutput.size() > 512 * 1024)
        m_rebuildOutput = m_rebuildOutput.right(512 * 1024);

    if (m_rebuildStage != QStringLiteral("build") && m_rebuildStage != QStringLiteral("root-native"))
        return;

    const QString text = QString::fromUtf8(m_rebuildOutput.right(32768));
    const QRegularExpression expression(QStringLiteral(R"(\[(\d+)\/(\d+)\])"));
    auto iterator = expression.globalMatch(text);
    int done = 0;
    int total = 0;
    while (iterator.hasNext()) {
        const QRegularExpressionMatch match = iterator.next();
        done = match.captured(1).toInt();
        total = match.captured(2).toInt();
    }
    if (total > 0) {
        const double fraction = std::clamp(static_cast<double>(done) / static_cast<double>(total), 0.0, 1.0);
        const double progress = 0.14 + fraction * 0.76;
        setRebuildState(true, progress,
                        QStringLiteral("Rebuilding NeutronOS  •  %1 / %2").arg(done).arg(total));
    }
}

void AppStoreManager::handleRebuildFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    consumeRebuildOutput();
    if (!m_rebuilding)
        return;

    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        QString detail = QString::fromUtf8(m_rebuildOutput).trimmed();
        if (detail.size() > 1600)
            detail = detail.right(1600);
        QString label = m_rebuildStage == QStringLiteral("configure") ? QStringLiteral("configure") :
                        m_rebuildStage == QStringLiteral("validate") ? QStringLiteral("validation") :
                                                                       QStringLiteral("build");
        QString message = QStringLiteral("NeutronOS %1 failed").arg(label);
        if (!detail.isEmpty())
            message += QStringLiteral(": ") + detail;
        failRebuild(message);
        return;
    }

    if (m_rebuildStage == QStringLiteral("root-native")) {
        const QVariantMap result = parseLastJsonObject(m_rebuildOutput);
        if (!result.value(QStringLiteral("success")).toBool()) {
            failRebuild(QStringLiteral("The signed native rebuild did not report validated success."));
            return;
        }
        m_rebuildShellInstalled = true;
        setRebuildState(true, 0.97, QStringLiteral("Validated shell installed  •  Authenticating restart"));
        armAuthenticatedRestart();
        return;
    }
    failRebuild(QStringLiteral("The App Store rebuild entered an unknown validation stage."));
}

bool AppStoreManager::restoreOriginalShell(QString *error)
{
    const QString ticket = m_pendingRebuildResult.value(QStringLiteral("rebuildTicket")).toString();
    if (ticket.isEmpty()) return true;
    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(QStringLiteral("/usr/bin/sudo"),
                  {QStringLiteral("-n"), QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                   QStringLiteral("appstore-rebuild-restore"), ticket});
    if (!process.waitForStarted(2500) || !process.waitForFinished(30000) || process.exitCode() != 0) {
        if (error) *error = QString::fromUtf8(process.readAll()).trimmed();
        return false;
    }
    m_rebuildShellInstalled = false;
    return true;
}


void AppStoreManager::cleanupRebuildWorkspace()
{
    if (!m_rebuildWorkspace.isEmpty())
        QDir(m_rebuildWorkspace).removeRecursively();
    m_rebuildWorkspace.clear();
    m_rebuildBuildDirectory.clear();
    m_rebuildStagedShell.clear();
    m_rebuildOriginalShellBackup.clear();
    m_rebuildOriginalPermissions = 0;
    m_rebuildStage.clear();
    m_rebuildOutput.clear();
}

bool AppStoreManager::rollbackPackageSynchronously(QString *error)
{
    const QString packageId = m_pendingRebuildResult.value(QStringLiteral("packageId"), m_activePackageId).toString().trimmed();
    if (packageId.isEmpty()) {
        if (error) *error = QStringLiteral("No package id was available for rollback");
        return false;
    }

    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(QStringLiteral("python3"),
                  QStringList{helperScriptPath(), QStringLiteral("rollback"),
                              QStringLiteral("--root"), m_neutronRoot,
                              QStringLiteral("--state-root"),
                              HumanHome::appStateRoot(),
                              QStringLiteral("--package-id"), packageId});
    if (!process.waitForStarted(2500) || !process.waitForFinished(45000)) {
        process.kill();
        process.waitForFinished(500);
        if (error) *error = QStringLiteral("Rollback helper did not complete");
        return false;
    }
    const QByteArray output = process.readAll();
    const QVariantMap result = parseLastJsonObject(output);
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 ||
            result.value(QStringLiteral("success"), true).toBool() == false) {
        if (error) {
            const QString message = result.value(QStringLiteral("message")).toString().trimmed();
            *error = message.isEmpty() ? QString::fromUtf8(output).trimmed() : message;
        }
        return false;
    }

    loadInstalledRegistry();
    rebuildCatalog();
    if (m_appManager)
        m_appManager->rediscoverApps();
    return true;
}

void AppStoreManager::failRebuild(const QString &message)
{
    if (m_rebuildProcess && m_rebuildProcess->state() != QProcess::NotRunning) {
        m_rebuildProcess->kill();
        m_rebuildProcess->waitForFinished(1000);
    }

    const QString originalOperation = m_pendingRebuildResult.value(
        QStringLiteral("originalOperation"), m_activeOperation).toString();
    QString restoreError;
    const bool shellRestored = restoreOriginalShell(&restoreError);
    QString rollbackError;
    const bool rolledBack = rollbackPackageSynchronously(&rollbackError);

    setRebuildState(false, 0.0, QString());
    m_activeOperation = originalOperation == QStringLiteral("rebuild")
        ? QStringLiteral("install") : originalOperation;
    emit operationStateChanged();

    QString finalMessage = message;
    if (!shellRestored && !restoreError.isEmpty())
        finalMessage += QStringLiteral("  WARNING: previous NeutronShell restoration failed: ") + restoreError;
    if (rolledBack)
        finalMessage += QStringLiteral("  The package transaction was restored to its previous state.");
    else if (!rollbackError.isEmpty())
        finalMessage += QStringLiteral("  Automatic rollback also failed: ") + rollbackError;

    cleanupRebuildWorkspace();
    m_pendingRebuildResult.clear();
    finishOperation(false, finalMessage);
}

void AppStoreManager::armAuthenticatedRestart()
{
    const QString shellPath = QDir(m_neutronRoot).filePath(QStringLiteral("build/NeutronShell"));
    QFile shell(shellPath);
    if (!QFileInfo(shellPath).isFile() || !QFileInfo(shellPath).isExecutable() || !shell.open(QIODevice::ReadOnly)) {
        failRebuild(QStringLiteral("The rebuilt NeutronShell binary could not be validated."));
        return;
    }
    const QString shellSha = QString::fromLatin1(
        QCryptographicHash::hash(shell.readAll(), QCryptographicHash::Sha256).toHex());
    shell.close();

    const QVariantMap identity = m_securityCoreManager
        ? m_securityCoreManager->authenticatedSessionIdentity() : QVariantMap{};
    const QString userName = identity.value(QStringLiteral("userName")).toString().trimmed();
    const QString sessionId = identity.value(QStringLiteral("sessionId")).toString().trimmed();
    if (userName.isEmpty()) {
        failRebuild(QStringLiteral("The App Store could not prove an authenticated NeutronOS session, so the login-bypass restart was refused."));
        return;
    }

    const QString packageId = m_pendingRebuildResult.value(QStringLiteral("packageId"), m_activePackageId).toString().trimmed();
    const QString operation = m_pendingRebuildResult.value(QStringLiteral("originalOperation")).toString().trimmed();
    const QString version = m_pendingRebuildResult.value(QStringLiteral("version")).toString().trimmed();
    const QString ticket = m_pendingRebuildResult.value(QStringLiteral("rebuildTicket")).toString().trimmed();
    if (packageId.isEmpty() || ticket.isEmpty() ||
            (operation != QStringLiteral("install") && operation != QStringLiteral("update") && operation != QStringLiteral("uninstall"))) {
        failRebuild(QStringLiteral("The rebuild finished, but its authenticated App Store restart ticket was invalid."));
        return;
    }

    setRebuildState(true, 0.985, QStringLiteral("Authenticating NeutronOS restart"));

    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(QStringLiteral("sudo"),
                  QStringList{QStringLiteral("-n"),
                              QStringLiteral("/usr/local/sbin/neutronos-privileged-helper"),
                              QStringLiteral("appstore-arm-resume-and-restart"),
                              ticket, packageId, operation, version, userName, sessionId, shellPath, shellSha});
    if (!process.waitForStarted(2500) || !process.waitForFinished(10000)) {
        process.kill();
        process.waitForFinished(500);
        failRebuild(QStringLiteral("The rebuilt shell passed validation, but the authenticated restart could not be armed."));
        return;
    }
    const QByteArray output = process.readAll();
    const QVariantMap result = parseLastJsonObject(output);
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 ||
            result.value(QStringLiteral("success"), false).toBool() == false) {
        QString reason = result.value(QStringLiteral("message")).toString().trimmed();
        if (reason.isEmpty()) reason = QString::fromUtf8(output).trimmed();
        failRebuild(reason.isEmpty()
                    ? QStringLiteral("Authenticated App Store restart was rejected.")
                    : QStringLiteral("Authenticated App Store restart was rejected: ") + reason);
        return;
    }

    // systemctl --no-block has accepted the restart. Do not emit the ordinary
    // success modal in this process; the one-shot resume record makes the new
    // NeutronShell reopen App Store directly on the green Installed/Updated result.
    setRebuildState(true, 1.0, QStringLiteral("Rebuild complete  •  Restarting NeutronOS"));
    m_rebuildShellInstalled = false;
    cleanupRebuildWorkspace();
}

bool AppStoreManager::addRepository(
    const QString &name,
    const QString &url,
    const QString &keyId
)
{
    if (!developerModeEnabled()) {
        setStatus(QStringLiteral("Developer Mode is required to add repositories"));
        return false;
    }
    const QUrl parsed(url.trimmed());
    if (!parsed.isValid() || parsed.isEmpty()) {
        setStatus(QStringLiteral("Repository URL is invalid"));
        return false;
    }
    QVariantMap repository;
    repository.insert(QStringLiteral("id"), normalizeId(
        name.isEmpty() ? parsed.host() : name
    ) + QStringLiteral("-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8));
    repository.insert(QStringLiteral("name"), name.trimmed().isEmpty()
                                               ? parsed.host()
                                               : name.trimmed());
    repository.insert(QStringLiteral("url"), parsed.toString());
    repository.insert(QStringLiteral("keyId"), keyId.trimmed());
    repository.insert(QStringLiteral("enabled"), true);
    repository.insert(QStringLiteral("trusted"), false);
    m_repositories.append(repository);

    QVariantMap root;
    root.insert(QStringLiteral("schema"), kSchemaVersion);
    root.insert(QStringLiteral("repositories"), m_repositories);
    if (!writeJsonObject(repositoriesPath(), root))
        return false;
    emit repositoriesChanged();
    setStatus(QStringLiteral("Repository added as untrusted"));
    return true;
}

bool AppStoreManager::removeRepository(const QString &repositoryId)
{
    if (!developerModeEnabled())
        return false;
    const QString id = repositoryId.trimmed();
    QVariantList next;
    bool removed = false;
    for (const QVariant &value : std::as_const(m_repositories)) {
        const QVariantMap repository = value.toMap();
        if (repository.value(QStringLiteral("id")).toString() == id) {
            if (id == QStringLiteral("neutronos-official"))
                return false;
            removed = true;
            continue;
        }
        next.append(repository);
    }
    if (!removed)
        return false;
    m_repositories = next;
    QVariantMap root;
    root.insert(QStringLiteral("schema"), kSchemaVersion);
    root.insert(QStringLiteral("repositories"), m_repositories);
    const bool saved = writeJsonObject(repositoriesPath(), root);
    if (saved)
        emit repositoriesChanged();
    return saved;
}

bool AppStoreManager::setRepositoryEnabled(const QString &repositoryId, bool enabled)
{
    bool changed = false;
    for (QVariant &value : m_repositories) {
        QVariantMap repository = value.toMap();
        if (repository.value(QStringLiteral("id")).toString() == repositoryId) {
            repository.insert(QStringLiteral("enabled"), enabled);
            value = repository;
            changed = true;
            break;
        }
    }
    if (!changed)
        return false;
    QVariantMap root;
    root.insert(QStringLiteral("schema"), kSchemaVersion);
    root.insert(QStringLiteral("repositories"), m_repositories);
    const bool saved = writeJsonObject(repositoriesPath(), root);
    if (saved)
        emit repositoriesChanged();
    return saved;
}

bool AppStoreManager::setRepositoryTrusted(const QString &repositoryId, bool trusted)
{
    if (!developerModeEnabled())
        return false;
    bool changed = false;
    for (QVariant &value : m_repositories) {
        QVariantMap repository = value.toMap();
        if (repository.value(QStringLiteral("id")).toString() == repositoryId) {
            // This switch enables a source; it cannot add or replace a signer.
            // Every catalog still verifies against the fixed OS release key.
            repository.insert(QStringLiteral("trusted"), trusted);
            value = repository;
            changed = true;
            break;
        }
    }
    if (!changed)
        return false;
    QVariantMap root;
    root.insert(QStringLiteral("schema"), kSchemaVersion);
    root.insert(QStringLiteral("repositories"), m_repositories);
    const bool saved = writeJsonObject(repositoriesPath(), root);
    if (saved)
        emit repositoriesChanged();
    return saved;
}

QString AppStoreManager::currentPlatform() const
{
    QFile osRelease(QStringLiteral("/etc/os-release"));
    if (!osRelease.open(QIODevice::ReadOnly)) return {};
    const QByteArray text = osRelease.readAll();
    if (!QRegularExpression(QStringLiteral("(?:^|\n)ID=\"?neutronos\"?(?:\n|$)")).match(QString::fromUtf8(text)).hasMatch()) return {};
    const QRegularExpression variant(QStringLiteral("(?:^|\n)VARIANT_ID=([a-z]+)(?:\n|$)"));
    const auto match = variant.match(QString::fromUtf8(text));
    const QString name = match.hasMatch() ? match.captured(1) : QString();
    const QString arch = currentArchitecture();
    if ((name == QStringLiteral("gemini") && arch == QStringLiteral("amd64")) ||
        (name == QStringLiteral("apollo") && arch == QStringLiteral("aarch64"))) return name;
    return {};
}

QString AppStoreManager::currentArchitecture() const
{
    return canonicalArch(QSysInfo::currentCpuArchitecture());
}

QString AppStoreManager::currentNeutronVersion() const
{
    const QVariantMap root = readJsonObject(versionPath());
    const QString version = root.value(QStringLiteral("version")).toString();
    return version.isEmpty() ? QStringLiteral("1.0.0-alpha") : version;
}

int AppStoreManager::compareVersions(const QString &left, const QString &right)
{
    const QString leftCore = left.section(QLatin1Char('-'), 0, 0);
    const QString rightCore = right.section(QLatin1Char('-'), 0, 0);
    const QVersionNumber leftVersion = QVersionNumber::fromString(leftCore);
    const QVersionNumber rightVersion = QVersionNumber::fromString(rightCore);
    const int comparison = QVersionNumber::compare(leftVersion, rightVersion);
    if (comparison != 0)
        return comparison;
    return QString::compare(left, right, Qt::CaseInsensitive);
}

QString AppStoreManager::normalizeId(const QString &value)
{
    QString id = value.trimmed().toLower();
    id.replace(QRegularExpression(QStringLiteral("[^a-z0-9._-]+")), QStringLiteral("-"));
    while (id.startsWith(QLatin1Char('-')))
        id.remove(0, 1);
    while (id.endsWith(QLatin1Char('-')))
        id.chop(1);
    return id.left(96);
}

QStringList AppStoreManager::variantStringList(const QVariant &value)
{
    QStringList result;
    for (const QVariant &item : value.toList())
        result.append(item.toString());
    if (result.isEmpty() && value.canConvert<QString>()) {
        const QString text = value.toString().trimmed();
        if (!text.isEmpty())
            result = text.split(QLatin1Char(','), Qt::SkipEmptyParts);
    }
    for (QString &item : result)
        item = item.trimmed();
    return result;
}

QByteArray AppStoreManager::decodeBinary(const QString &value)
{
    const QByteArray text = value.trimmed().toLatin1();
    if (text.isEmpty())
        return {};
    const QByteArray hex = QByteArray::fromHex(text);
    if (!hex.isEmpty() &&
        QString::compare(QString::fromLatin1(hex.toHex()),
                         QString::fromLatin1(text),
                         Qt::CaseInsensitive) == 0) {
        return hex;
    }
    return QByteArray::fromBase64(text);
}


QVariantMap AppStoreManager::installFootprint(const QString &packageId) const
{
    QVariantMap result;
    const QVariantMap package = packageById(packageId);
    if (package.isEmpty()) {
        result.insert(QStringLiteral("known"), false);
        result.insert(QStringLiteral("message"), QStringLiteral("Package metadata unavailable"));
        return result;
    }

    const qulonglong packageBytes = package.value(QStringLiteral("sizeBytes"),
                                                  package.value(QStringLiteral("size"), 0)).toULongLong();
    const qulonglong packageInstalledBytes = package.value(QStringLiteral("installedBytes"), packageBytes).toULongLong();
    QStringList aptCandidates = variantStringList(package.value(QStringLiteral("debianDependencies")));
    if (aptCandidates.isEmpty()) {
        const QStringList declared = variantStringList(package.value(QStringLiteral("dependencies")));
        const QRegularExpression packageNameRx(QStringLiteral(R"(^([A-Za-z0-9][A-Za-z0-9+._-]*))"));
        for (const QString &entry : declared) {
            const auto match = packageNameRx.match(entry.trimmed());
            if (match.hasMatch() && !entry.contains(QStringLiteral(" ")))
                aptCandidates.append(match.captured(1));
        }
    }

    QStringList missingLabels;
    qulonglong runtimeDownloadBytes = 0;
    qulonglong runtimeInstalledBytes = 0;
    bool diskEstimateLowerBound = false;
    bool dependencyEstimateKnown = true;
    const QString arch = currentArchitecture();

    const QVariantList runtimeRequirements = package.value(QStringLiteral("runtimeRequirements")).toList();
    for (const QVariant &runtimeValue : runtimeRequirements) {
        const QVariantMap requirement = runtimeValue.toMap();
        const QString type = requirement.value(QStringLiteral("type")).toString().trimmed();
        if (type != QStringLiteral("jellyfin-server"))
            continue;

        const QString systemUnit = requirement.value(QStringLiteral("systemUnit"), QStringLiteral("jellyfin.service")).toString();
        const QString containerName = requirement.value(QStringLiteral("containerName"), QStringLiteral("jellyfin")).toString();
        const QString image = requirement.value(QStringLiteral("image")).toString();
        const QString digest = requirement.value(QStringLiteral("imageDigest")).toString();

        bool backendPresent = systemdUnitExists(systemUnit);
        // Jellyfin's standard local HTTP endpoint is also a safe, unprivileged
        // signal that an existing native/container backend is already usable.
        if (!backendPresent && type == QStringLiteral("jellyfin-server"))
            backendPresent = tcpEndpointAvailable(QStringLiteral("127.0.0.1"), 8096);
        const bool dockerCliPresent = QFileInfo::exists(QStringLiteral("/usr/bin/docker"));
        const bool dockerDaemonPresent = systemdUnitExists(requirement.value(QStringLiteral("dockerUnit"),
                                                                              QStringLiteral("docker.service")).toString());
        if (!backendPresent && dockerCliPresent && dockerDaemonPresent && !containerName.isEmpty())
            backendPresent = dockerObjectExists({QStringLiteral("container"), QStringLiteral("inspect"), containerName});

        if (backendPresent)
            continue;

        const QStringList dockerPackages = variantStringList(requirement.value(QStringLiteral("dockerPackages")));
        for (const QString &dockerPackage : dockerPackages) {
            const QString lower = dockerPackage.toLower();
            if (lower.contains(QStringLiteral("cli"))) {
                if (!dockerCliPresent)
                    aptCandidates.append(dockerPackage);
            } else if (!dockerDaemonPresent) {
                aptCandidates.append(dockerPackage);
            }
        }

        bool imagePresent = false;
        if (dockerCliPresent && dockerDaemonPresent && !image.isEmpty()) {
            QString imageReference = image;
            if (!digest.isEmpty())
                imageReference = image.section(QLatin1Char(':'), 0, 0) + QLatin1Char('@') + digest;
            imagePresent = dockerObjectExists({QStringLiteral("image"), QStringLiteral("inspect"), imageReference});
            if (!imagePresent)
                imagePresent = dockerObjectExists({QStringLiteral("image"), QStringLiteral("inspect"), image});
        }
        if (!imagePresent && !image.isEmpty()) {
            const qulonglong imageDownload = architectureSizeHint(requirement, QStringLiteral("imageDownloadBytes"), arch);
            const qulonglong imageInstalled = architectureSizeHint(requirement, QStringLiteral("imageInstalledBytes"), arch);
            if (imageDownload > 0) {
                runtimeDownloadBytes += imageDownload;
                missingLabels.append(QStringLiteral("%1 container image").arg(type == QStringLiteral("jellyfin-server")
                                                                              ? QStringLiteral("Jellyfin") : type));
            } else {
                dependencyEstimateKnown = false;
                missingLabels.append(QStringLiteral("%1 container image (size unavailable)").arg(image));
            }
            if (imageInstalled > 0) {
                runtimeInstalledBytes += imageInstalled;
            } else if (imageDownload > 0) {
                // Compressed registry size is a defensible lower bound until the image is pulled.
                runtimeInstalledBytes += imageDownload;
                diskEstimateLowerBound = true;
            }
        }
    }

    aptCandidates.removeAll(QString());
    aptCandidates.removeDuplicates();
    QStringList missingAptPackages;
    for (const QString &candidate : std::as_const(aptCandidates)) {
        if (!debianPackageInstalled(candidate))
            missingAptPackages.append(candidate);
    }
    for (const QString &candidate : std::as_const(missingAptPackages)) {
        if (!missingLabels.contains(candidate))
            missingLabels.append(candidate);
    }

    qulonglong aptDownloadBytes = 0;
    qulonglong aptInstalledBytes = 0;
    if (!aptSimulationSizes(missingAptPackages, &aptDownloadBytes, &aptInstalledBytes))
        dependencyEstimateKnown = false;

    const qulonglong missingDependencyDownloadBytes = aptDownloadBytes + runtimeDownloadBytes;
    const qulonglong missingDependencyInstalledBytes = aptInstalledBytes + runtimeInstalledBytes;
    const qulonglong totalDownloadBytes = packageBytes + missingDependencyDownloadBytes;
    const qulonglong totalInstalledBytes = packageInstalledBytes + missingDependencyInstalledBytes;

    result.insert(QStringLiteral("known"), dependencyEstimateKnown);
    result.insert(QStringLiteral("packageBytes"), QVariant::fromValue(packageBytes));
    result.insert(QStringLiteral("missingDependencyBytes"), QVariant::fromValue(missingDependencyDownloadBytes));
    result.insert(QStringLiteral("missingDependencyInstalledBytes"), QVariant::fromValue(missingDependencyInstalledBytes));
    result.insert(QStringLiteral("totalDownloadBytes"), QVariant::fromValue(totalDownloadBytes));
    result.insert(QStringLiteral("totalInstalledBytes"), QVariant::fromValue(totalInstalledBytes));
    result.insert(QStringLiteral("diskEstimateLowerBound"), diskEstimateLowerBound);
    result.insert(QStringLiteral("missingDependencies"), missingLabels);
    result.insert(QStringLiteral("missingDebianPackages"), missingAptPackages);
    result.insert(QStringLiteral("runtimeRequirementsPresent"), !runtimeRequirements.isEmpty());
    return result;
}

QString AppStoreManager::formatBytes(qulonglong bytes) const
{
    static const QStringList units = {QStringLiteral("B"), QStringLiteral("KB"),
                                      QStringLiteral("MB"), QStringLiteral("GB"),
                                      QStringLiteral("TB")};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1000.0 && unit < units.size() - 1) {
        value /= 1000.0;
        ++unit;
    }
    if (unit == 0)
        return QStringLiteral("%1 B").arg(bytes);
    int precision = value >= 100.0 ? 0 : (value >= 10.0 ? 1 : 2);
    QString number = QString::number(value, 'f', precision);
    while (number.contains(QLatin1Char('.')) && number.endsWith(QLatin1Char('0')))
        number.chop(1);
    if (number.endsWith(QLatin1Char('.')))
        number.chop(1);
    return QStringLiteral("%1 %2").arg(number, units.at(unit));
}

void AppStoreManager::setRepositoryConnected(bool connected)
{
    if (m_repositoryConnected == connected)
        return;
    m_repositoryConnected = connected;
    emit repositoryConnectedChanged();
}

void AppStoreManager::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void AppStoreManager::setProgress(double progress)
{
    progress = std::clamp(progress, 0.0, 1.0);
    if (qFuzzyCompare(m_progress, progress))
        return;
    m_progress = progress;
    emit progressChanged();
}

void AppStoreManager::setStatus(const QString &message, const QString &error)
{
    m_statusMessage = message;
    m_lastError = error;
    emit statusMessageChanged();
}
