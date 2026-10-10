#include "TerminalManager.h"
#include "TerminalAssistManager.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QMetaType>
#include <QNetworkInterface>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>
#include <QtGlobal>

#include <algorithm>
#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <utility>
#include <vector>

#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <pty.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

namespace
{
constexpr int ModeWatchIntervalMs = 750;
constexpr int ArmedActionTickMs = 250;
constexpr int ChildReapIntervalMs = 100;
constexpr int PtyShutdownTickMs = 100;
constexpr int WebSweepIntervalMs = 1000;
constexpr int WebPairingCodeLifetimeMs = 60 * 1000;
constexpr int WebLanPairingAttemptLimit = 5;
constexpr int WebTailscalePairingAttemptLimit = 10;
constexpr qint64 WebPairingLockoutMs = 30LL * 60LL * 1000LL;
constexpr int ConfigurationReloadDelayMs = 150;

constexpr int MaximumQuickCommands = 64;
constexpr int MaximumQuickCommandFileBytes = 256 * 1024;
constexpr int MaximumAppearanceFileBytes = 64 * 1024;
constexpr qsizetype MaximumStartupMessageCharacters = 240;
constexpr int MaximumSupplementaryGroups = 128;

bool isTailscaleAddress(const QHostAddress &address)
{
    // Qt can represent an IPv4 peer as either native IPv4 or IPv4-mapped
    // IPv6. Ask QHostAddress for a convertible IPv4 value first so a
    // Tailscale 100.64.0.0/10 client always receives the intended 10-try
    // policy instead of accidentally falling back to the LAN limit.
    bool ipv4Ok = false;
    const quint32 ipv4 = address.toIPv4Address(&ipv4Ok);
    if (ipv4Ok)
        return (ipv4 & 0xFFC00000U) == 0x64400000U; // 100.64.0.0/10

    if (address.protocol() == QAbstractSocket::IPv6Protocol) {
        const Q_IPV6ADDR value = address.toIPv6Address();
        return value[0] == 0xfd && value[1] == 0x7a &&
               value[2] == 0x11 && value[3] == 0x5c &&
               value[4] == 0xa1 && value[5] == 0xe0; // fd7a:115c:a1e0::/48
    }

    return false;
}

QString utcNowIso()
{
    return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

QString environmentText(const char *name)
{
    return QString::fromLocal8Bit(qgetenv(name)).trimmed();
}

bool safeUsername(const QString &username)
{
    static const QRegularExpression pattern(
        QStringLiteral("^[A-Za-z_][A-Za-z0-9_.-]{0,63}$"));

    return pattern.match(username).hasMatch();
}

bool safeIdentifier(const QString &identifier)
{
    static const QRegularExpression pattern(
        QStringLiteral("^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$"));

    return pattern.match(identifier).hasMatch();
}

QString passwdText(const char *text)
{
    return text ? QString::fromLocal8Bit(text).trimmed() : QString();
}

bool isExecutableRegularFile(const QString &path)
{
    const QFileInfo info(path);

    return info.exists() &&
           info.isFile() &&
           !info.isSymLink() &&
           info.isExecutable();
}

bool shellIsBlocked(const QString &path)
{
    const QString clean = QDir::cleanPath(path).toLower();

    return clean.endsWith(QStringLiteral("/nologin")) ||
           clean.endsWith(QStringLiteral("/false"));
}

QString discoverCurrentAccount()
{
#ifdef Q_OS_LINUX
    const QStringList candidates = {
        environmentText("NEUTRONOS_USER"),
        environmentText("SUDO_USER"),
        environmentText("LOGNAME"),
        environmentText("USER")
    };

    for (const QString &candidate : candidates) {
        if (safeUsername(candidate) &&
                candidate != QStringLiteral("root")) {
            return candidate;
        }
    }

    long bufferSize = ::sysconf(_SC_GETPW_R_SIZE_MAX);

    if (bufferSize < 1024)
        bufferSize = 16384;

    std::vector<char> buffer(static_cast<std::size_t>(bufferSize));
    struct passwd account;
    struct passwd *result = nullptr;

    if (::getpwuid_r(
            ::getuid(),
            &account,
            buffer.data(),
            buffer.size(),
            &result) == 0 &&
            result) {
        const QString username = passwdText(result->pw_name);

        if (safeUsername(username) &&
                username != QStringLiteral("root")) {
            return username;
        }
    }

    QDir homeRoot(QStringLiteral("/home"));

    const QFileInfoList homes = homeRoot.entryInfoList(
        QDir::Dirs |
        QDir::Readable |
        QDir::NoDotAndDotDot,
        QDir::Name);

    QString onlyAccount;

    for (const QFileInfo &home : homes) {
        const QString candidate = home.fileName();

        if (!safeUsername(candidate))
            continue;

        const QByteArray encoded = candidate.toLocal8Bit();

        if (::getpwnam_r(
                encoded.constData(),
                &account,
                buffer.data(),
                buffer.size(),
                &result) != 0 ||
                !result ||
                result->pw_uid == 0 ||
                result->pw_uid < 1000) {
            continue;
        }

        if (!onlyAccount.isEmpty())
            return QString();

        onlyAccount = candidate;
    }

    return onlyAccount;
#else
    const QString candidate = environmentText("USER");
    return safeUsername(candidate) ? candidate : QString();
#endif
}

QString findRepositoryRoot(const QString &preferredUsername)
{
    const QString configured = environmentText("NEUTRONOS_ROOT");

    if (!configured.isEmpty()) {
        const QFileInfo configuredInfo(configured);

        if (configuredInfo.exists() &&
                configuredInfo.isDir() &&
                !configuredInfo.isSymLink()) {
            return configuredInfo.absoluteFilePath();
        }
    }

    QDir current(QDir::currentPath());

    for (int depth = 0; depth < 12; ++depth) {
        if (current.exists(QStringLiteral("qml")) &&
                current.exists(QStringLiteral("src"))) {
            return current.absolutePath();
        }

        if (!current.cdUp())
            break;
    }

    QDir applicationDirectory(QCoreApplication::applicationDirPath());

    for (int depth = 0; depth < 12; ++depth) {
        if (applicationDirectory.exists(QStringLiteral("qml")) &&
                applicationDirectory.exists(QStringLiteral("src"))) {
            return applicationDirectory.absolutePath();
        }

        if (!applicationDirectory.cdUp())
            break;
    }

#ifdef Q_OS_LINUX
    if (safeUsername(preferredUsername)) {
        long bufferSize = ::sysconf(_SC_GETPW_R_SIZE_MAX);

        if (bufferSize < 1024)
            bufferSize = 16384;

        std::vector<char> buffer(static_cast<std::size_t>(bufferSize));
        struct passwd account;
        struct passwd *result = nullptr;
        const QByteArray encoded = preferredUsername.toLocal8Bit();

        if (::getpwnam_r(
                encoded.constData(),
                &account,
                buffer.data(),
                buffer.size(),
                &result) == 0 &&
                result) {
            const QString candidate =
                passwdText(result->pw_dir) +
                QStringLiteral("/NeutronOS");

            if (QFileInfo(candidate).isDir())
                return QDir(candidate).absolutePath();
        }
    }
#endif

    QDir homeRoot(
        QStringLiteral("/home"));

    const QFileInfoList homeDirectories =
        homeRoot.entryInfoList(
            QDir::Dirs |
            QDir::Readable |
            QDir::NoDotAndDotDot,
            QDir::Name);

    QString uniqueProject;

    for (const QFileInfo &homeDirectory :
            homeDirectories) {
        const QString candidate =
            QDir(homeDirectory.absoluteFilePath())
                .filePath(
                    QStringLiteral("NeutronOS"));

        const QDir project(candidate);

        if (!project.exists(
                QStringLiteral("qml")) ||
                !project.exists(
                    QStringLiteral("src"))) {
            continue;
        }

        if (!uniqueProject.isEmpty())
            return QDir::homePath() +
                   QStringLiteral("/NeutronOS");

        uniqueProject =
            project.absolutePath();
    }

    if (!uniqueProject.isEmpty())
        return uniqueProject;

    const QString homeCandidate =
        QDir::homePath() +
        QStringLiteral("/NeutronOS");

    return QDir(homeCandidate).absolutePath();
}

QByteArray mapToCompactJson(const QVariantMap &map)
{
    return QJsonDocument(
               QJsonObject::fromVariantMap(map)
           ).toJson(QJsonDocument::Compact);
}

QVariantMap compactJsonToMap(const QByteArray &data)
{
    if (data.isEmpty())
        return QVariantMap();

    QJsonParseError error;

    const QJsonDocument document =
        QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError ||
            !document.isObject()) {
        return QVariantMap();
    }

    return document.object().toVariantMap();
}

bool constantTimeEquals(
    const QByteArray &left,
    const QByteArray &right)
{
    const int maximumLength =
        qMax(left.size(), right.size());

    unsigned int difference =
        static_cast<unsigned int>(
            left.size() ^ right.size());

    for (int index = 0;
            index < maximumLength;
            ++index) {
        const unsigned char leftByte =
            index < left.size()
            ? static_cast<unsigned char>(left.at(index))
            : 0U;

        const unsigned char rightByte =
            index < right.size()
            ? static_cast<unsigned char>(right.at(index))
            : 0U;

        difference |=
            static_cast<unsigned int>(
                leftByte ^ rightByte);
    }

    return difference == 0U;
}

int incompleteUtf8SuffixLength(const QByteArray &bytes)
{
    if (bytes.isEmpty())
        return 0;

    const int length = bytes.size();
    int start = length - 1;
    int continuationCount = 0;

    while (start >= 0 &&
            (static_cast<unsigned char>(bytes.at(start)) & 0xC0U) == 0x80U &&
            continuationCount < 3) {
        --start;
        ++continuationCount;
    }

    if (start < 0)
        return 0;

    const unsigned char lead =
        static_cast<unsigned char>(bytes.at(start));

    int expectedLength = 1;

    if ((lead & 0x80U) == 0U)
        expectedLength = 1;
    else if ((lead & 0xE0U) == 0xC0U)
        expectedLength = 2;
    else if ((lead & 0xF0U) == 0xE0U)
        expectedLength = 3;
    else if ((lead & 0xF8U) == 0xF0U)
        expectedLength = 4;
    else
        return 0;

    const int available = length - start;

    return available < expectedLength
           ? available
           : 0;
}

bool privateOrLocalAddress(const QHostAddress &address)
{
    if (address.isLoopback())
        return true;

    if (address.protocol() != QAbstractSocket::IPv4Protocol)
        return false;

    const quint32 value = address.toIPv4Address();

    const bool ten =
        (value & 0xFF000000U) == 0x0A000000U;

    const bool oneSeventyTwo =
        (value & 0xFFF00000U) == 0xAC100000U;

    const bool oneNinetyTwo =
        (value & 0xFFFF0000U) == 0xC0A80000U;

    const bool linkLocal =
        (value & 0xFFFF0000U) == 0xA9FE0000U;

    const bool carrierGradeNat =
        (value & 0xFFC00000U) == 0x64400000U;

    return ten ||
           oneSeventyTwo ||
           oneNinetyTwo ||
           linkLocal ||
           carrierGradeNat;
}

void childCopyBytes(
    char *destination,
    std::size_t capacity,
    const char *prefix,
    const QByteArray &value)
{
    if (!destination || capacity == 0)
        return;

    std::size_t index = 0;

    if (prefix) {
        for (const char *cursor = prefix;
                *cursor != '\0' &&
                index + 1 < capacity;
                ++cursor) {
            destination[index++] = *cursor;
        }
    }

    const char *source = value.constData();

    for (int sourceIndex = 0;
            sourceIndex < value.size() &&
            index + 1 < capacity;
            ++sourceIndex) {
        destination[index++] = source[sourceIndex];
    }

    destination[index] = '\0';
}

void resetChildSignal(int signalNumber)
{
    struct sigaction action;
    std::memset(&action, 0, sizeof(action));
    action.sa_handler = SIG_DFL;
    ::sigemptyset(&action.sa_mask);
    ::sigaction(signalNumber, &action, nullptr);
}
}

TerminalManager::TerminalManager(
    DeveloperModeManager *developerModeManager,
    QObject *parent)
    : QObject(parent),
      m_developerModeManager(developerModeManager)
{
    m_monotonicClock.start();

    m_regularUsername = discoverCurrentAccount();

    resolvePaths();

    if (!ensureDirectories()) {
        setError(
            QStringLiteral(
                "Terminal state directories are unavailable or unsafe"));
    }

    loadQuickCommands();
    loadAppearance();
    rebuildConfigurationWatchers();

    m_mode = currentModeFromDeveloperManager();

    m_modeWatchTimer.setInterval(ModeWatchIntervalMs);
    m_modeWatchTimer.setSingleShot(false);

    m_armedQuickActionTimer.setInterval(ArmedActionTickMs);
    m_armedQuickActionTimer.setSingleShot(false);

    m_childReapTimer.setInterval(ChildReapIntervalMs);
    m_childReapTimer.setSingleShot(false);

    m_ptyShutdownTimer.setInterval(PtyShutdownTickMs);
    m_ptyShutdownTimer.setSingleShot(false);

    m_webClientSweepTimer.setInterval(WebSweepIntervalMs);
    m_webClientSweepTimer.setSingleShot(false);

    m_configurationReloadTimer.setInterval(
        ConfigurationReloadDelayMs);
    m_configurationReloadTimer.setSingleShot(true);

    connect(
        &m_modeWatchTimer,
        &QTimer::timeout,
        this,
        &TerminalManager::handleModeWatch);

    connect(
        &m_armedQuickActionTimer,
        &QTimer::timeout,
        this,
        &TerminalManager::updateArmedQuickActionState);

    connect(
        &m_childReapTimer,
        &QTimer::timeout,
        this,
        &TerminalManager::reapPtyChild);

    connect(
        &m_ptyShutdownTimer,
        &QTimer::timeout,
        this,
        &TerminalManager::advancePtyShutdown);

    connect(
        &m_webClientSweepTimer,
        &QTimer::timeout,
        this,
        &TerminalManager::sweepWebClients);

    connect(
        &m_configurationReloadTimer,
        &QTimer::timeout,
        this,
        &TerminalManager::reloadWatchedConfiguration);

    connect(
        &m_configurationWatcher,
        &QFileSystemWatcher::fileChanged,
        this,
        &TerminalManager::onConfigPathChanged);

    connect(
        &m_configurationWatcher,
        &QFileSystemWatcher::directoryChanged,
        this,
        &TerminalManager::onConfigPathChanged);

    if (m_developerModeManager) {
        connect(
            m_developerModeManager,
            &DeveloperModeManager::developerModeChanged,
            this,
            [this]() {
                syncModeFromDeveloperManager(false);
            });
    }
}

void TerminalManager::setAssistManager(TerminalAssistManager *assistManager)
{
    if (m_assistManager == assistManager)
        return;

    if (m_assistManager)
        disconnect(m_assistManager, nullptr, this, nullptr);

    m_assistManager = assistManager;

    if (!m_assistManager)
        return;

    m_assistManager->observeDraft(m_inputDraft);

    connect(
        m_assistManager,
        &TerminalAssistManager::snippetsChanged,
        this,
        [this]() {
            if (!m_assistManager)
                return;

            broadcastWebJson({
                {QStringLiteral("type"), QStringLiteral("terminal.snippetsChanged")},
                {QStringLiteral("snippets"), m_assistManager->snippets()}
            });
        });

    connect(
        m_assistManager,
        &TerminalAssistManager::correctionSuggestionChanged,
        this,
        [this]() {
            if (!m_assistManager)
                return;

            broadcastWebJson({
                {QStringLiteral("type"), QStringLiteral("terminal.correctionChanged")},
                {QStringLiteral("suggestion"), m_assistManager->correctionSuggestion()}
            });
        });
}

TerminalManager::~TerminalManager()
{
    m_running = false;

    stopWebMirror();

    m_modeWatchTimer.stop();
    m_armedQuickActionTimer.stop();
    m_childReapTimer.stop();
    m_ptyShutdownTimer.stop();
    m_webClientSweepTimer.stop();
    m_configurationReloadTimer.stop();

    if (m_childPid > 0) {
        sendSignalToPtyProcessGroup(SIGKILL);

        int status = 0;

        while (::waitpid(
                   static_cast<pid_t>(m_childPid),
                   &status,
                   0) < 0 &&
               errno == EINTR) {
        }

        m_childPid = -1;
    }

    closePtyDescriptors();
}

bool TerminalManager::running() const
{
    return m_running;
}

bool TerminalManager::ptyAlive() const
{
    return m_ptyAlive;
}

QString TerminalManager::mode() const
{
    return m_mode;
}

bool TerminalManager::developerMode() const
{
    return m_mode ==
           QStringLiteral("developer");
}

QString TerminalManager::modeLabel() const
{
    return developerMode()
           ? QStringLiteral("DEVELOPER")
           : QStringLiteral("REGULAR");
}

QString TerminalManager::regularUsername() const
{
    return m_regularUsername;
}

void TerminalManager::setRegularUsername(
    const QString &username)
{
    const QString clean =
        username.trimmed();

    if (!safeUsername(clean) ||
            clean == QStringLiteral("root")) {
        setError(
            QStringLiteral(
                "A valid non-root local username is required"));
        return;
    }

    PtyLaunchPlan testPlan;
    QString errorMessage;

    if (!resolveRegularAccount(
            clean,
            &testPlan,
            &errorMessage)) {
        setError(errorMessage);
        return;
    }

    if (m_regularUsername == clean)
        return;

    m_regularUsername = clean;

    resolvePaths();

    if (!ensureDirectories()) {
        setError(
            QStringLiteral(
                "Terminal directories could not be resolved for the selected account"));
        return;
    }

    loadQuickCommands();
    rebuildConfigurationWatchers();

    setError(QString());

    emit regularUserChanged();
    emit statusChanged();

    if (m_running &&
            !developerMode()) {
        m_restartAfterPtyExit = true;
        m_expectedPtyExit = true;

        if (m_ptyAlive)
            requestPtyShutdown();
        else
            startPty();
    }
}

QString TerminalManager::outputText() const
{
    return m_outputText;
}

QString TerminalManager::inputDraft() const
{
    return m_inputDraft;
}

QString TerminalManager::clipboardText() const
{
    return m_clipboardText;
}

QString TerminalManager::selectionText() const
{
    return m_selectionText;
}

QString TerminalManager::promptLabel() const
{
#ifdef Q_OS_LINUX
    /*
        Developer Mode is an OS state, not proof that the GUI process itself
        has uid 0. NeutronShell intentionally runs as the console user on the
        current image, so never advertise a root prompt unless the process can
        actually launch a root PTY.
    */
    if (developerMode() && ::geteuid() == 0)
        return QStringLiteral("root@neutronos:/#");
#endif

    const QString username =
        m_regularUsername.isEmpty()
        ? QStringLiteral("user")
        : m_regularUsername;

    QString hostname = QStringLiteral("system");
#ifdef Q_OS_LINUX
    char hostBuffer[256] = {};
    if (::gethostname(hostBuffer, sizeof(hostBuffer) - 1) == 0) {
        const QString detected = QString::fromLocal8Bit(hostBuffer).trimmed();
        if (!detected.isEmpty())
            hostname = detected;
    }
#endif

    return QStringLiteral("%1@%2:~$")
        .arg(username, hostname);
}

QString TerminalManager::statusText() const
{
    return m_statusText;
}

QString TerminalManager::error() const
{
    return m_error;
}

QString TerminalManager::tintColor() const
{
    return m_tintColor;
}

QString TerminalManager::terminalTextColor() const
{
    return m_terminalTextColor;
}

QString TerminalManager::startupMessage() const
{
    return m_startupMessage;
}

QVariantList TerminalManager::quickCommands() const
{
    QVariantList result;
    result.reserve(m_quickCommands.size());

    for (const QuickCommand &command : m_quickCommands)
        result.append(quickCommandToVariant(command));

    return result;
}

QString TerminalManager::armedQuickActionId() const
{
    return m_armedQuickActionId;
}

int TerminalManager::armedQuickActionSecondsRemaining() const
{
    if (m_armedQuickActionId.isEmpty() ||
            !m_monotonicClock.isValid()) {
        return 0;
    }

    const qint64 remaining =
        m_armedQuickActionUntilMonotonicMs -
        m_monotonicClock.elapsed();

    return remaining > 0
           ? static_cast<int>((remaining + 999) / 1000)
           : 0;
}

bool TerminalManager::webMirrorEnabled() const
{
    return m_webMirrorEnabled;
}

void TerminalManager::setWebMirrorEnabled(bool enabled)
{
    if (m_webMirrorEnabled == enabled)
        return;

    m_webMirrorEnabled = enabled;

    if (!enabled) {
        m_developerWebMirrorConfirmed = false;
        stopWebMirror();
    } else if (m_running) {
        requestStartWebMirror(false);
    }

    emit webMirrorChanged();
    emit webMirrorSecurityChanged();
    emit statusChanged();
}

bool TerminalManager::webMirrorRunning() const
{
    return m_webMirrorRunning;
}

bool TerminalManager::webMirrorLanAccessEnabled() const
{
    return m_webMirrorLanAccessEnabled;
}

void TerminalManager::setWebMirrorLanAccessEnabled(bool enabled)
{
    if (m_webMirrorLanAccessEnabled == enabled)
        return;

    m_webMirrorLanAccessEnabled = enabled;

    const bool wasRunning = m_webMirrorRunning;

    if (wasRunning)
        stopWebMirror();

    if (wasRunning && m_webMirrorEnabled)
        requestStartWebMirror(false);

    emit webMirrorSecurityChanged();
    emit webMirrorChanged();
    emit statusChanged();

    audit(
        QStringLiteral("web_bind_policy_changed"),
        {
            {
                QStringLiteral("lanAccessEnabled"),
                enabled
            }
        });
}

bool TerminalManager::webMirrorNeedsDeveloperConfirmation() const
{
    return developerMode() &&
           !m_developerWebMirrorConfirmed;
}

QString TerminalManager::webBindAddress() const
{
    return m_webBindAddress;
}

QString TerminalManager::webUrl() const
{
    const QString host =
        m_webMirrorLanAccessEnabled
        ? localIpHint()
        : QStringLiteral("127.0.0.1");

    return QStringLiteral("http://%1:%2")
        .arg(host)
        .arg(m_webPort);
}

QString TerminalManager::webToken() const
{
    return webPairingCode();
}

QString TerminalManager::webPairingCode() const
{
    return webPairingCodeActive()
           ? m_webToken
           : QString();
}

int TerminalManager::webPairingCodeSecondsRemaining() const
{
    if (!webPairingCodeActive())
        return 0;

    const qint64 remainingMs =
        m_webTokenExpiresMonotonicMs -
        m_monotonicClock.elapsed();

    return static_cast<int>(
        std::max<qint64>(
            0,
            (remainingMs + 999) / 1000));
}

bool TerminalManager::webPairingCodeActive() const
{
    return !m_webToken.isEmpty() &&
           m_monotonicClock.isValid() &&
           m_webTokenExpiresMonotonicMs >
               m_monotonicClock.elapsed();
}

int TerminalManager::webClientCount() const
{
    return m_webClients.size();
}

int TerminalManager::authenticatedWebClientCount() const
{
    int count = 0;

    for (auto iterator =
             m_webClients.constBegin();
         iterator !=
         m_webClients.constEnd();
         ++iterator) {
        if (iterator.value().authenticated)
            ++count;
    }

    return count;
}

QString TerminalManager::webSecurityState() const
{
    if (!m_webMirrorEnabled)
        return QStringLiteral("Disabled");

    if (webMirrorNeedsDeveloperConfirmation())
        return QStringLiteral("Developer confirmation required");

    if (developerMode() &&
            m_developerWebMirrorConfirmed) {
        return m_webMirrorLanAccessEnabled
               ? QStringLiteral("Developer · LAN confirmed")
               : QStringLiteral("Developer · local confirmed");
    }

    return m_webMirrorLanAccessEnabled
           ? QStringLiteral("LAN access enabled")
           : QStringLiteral("Local device only");
}

QVariantMap TerminalManager::status() const
{
    return makeStatusPayload();
}


void TerminalManager::start()
{
    if (!ensureDirectories()) {
        setError(
            QStringLiteral(
                "Terminal state directories are unavailable or unsafe"));
        setRunning(false);
        return;
    }

    loadQuickCommands();
    loadAppearance();
    rebuildConfigurationWatchers();

    if (!m_modeWatchTimer.isActive())
        m_modeWatchTimer.start();

    syncModeFromDeveloperManager(false);

    setRunning(true);

    if (!m_ptyAlive &&
            !startPty()) {
        setRunning(false);
        return;
    }

    setStatusText(
        QStringLiteral("Terminal ready"));
    setError(QString());

    if (m_webMirrorEnabled)
        requestStartWebMirror(false);

    emit quickCommandsChanged();
    emit statusChanged();

    emit terminalEvent(
        QStringLiteral("started"),
        makeStatusPayload());
}

void TerminalManager::stop()
{
    setRunning(false);

    stopWebMirror();
    clearArmedQuickAction();

    m_modeWatchTimer.stop();

    m_restartAfterPtyExit = false;
    m_expectedPtyExit = true;

    stopPty();

    setStatusText(
        QStringLiteral("Terminal stopped"));

    emit terminalEvent(
        QStringLiteral("stopped"),
        publicWebStatusPayload());
}

void TerminalManager::restart()
{
    if (!ensureDirectories()) {
        setError(
            QStringLiteral(
                "Terminal state directories are unavailable or unsafe"));
        return;
    }

    setRunning(true);
    syncModeFromDeveloperManager(false);

    m_restartAfterPtyExit = true;
    m_expectedPtyExit = true;

    if (m_ptyAlive ||
            m_childPid > 0) {
        requestPtyShutdown();
    } else {
        m_restartAfterPtyExit = false;

        if (!startPty())
            setRunning(false);
    }
}

void TerminalManager::refreshMode()
{
    syncModeFromDeveloperManager(true);
}

void TerminalManager::clearOutput()
{
    if (m_outputText.isEmpty())
        return;

    m_outputText.clear();
    m_utf8Carry.clear();

    emit outputChanged();
    emit statusChanged();

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral("terminal.historyCleared")
            },
            {
                QStringLiteral("status"),
                publicWebStatusPayload()
            }
        });
}

void TerminalManager::clearScreen()
{
    clearOutput();
    sendKey(
        QStringLiteral("ctrl-l"),
        QStringLiteral("qml"));
}

QVariantMap TerminalManager::saveAppearance(
    const QString &tintColorValue,
    const QString &textColorValue,
    const QString &startupMessageValue)
{
    const QString cleanTint = tintColorValue.trimmed().toUpper();
    const QString cleanText = textColorValue.trimmed().toUpper();
    const QString cleanMessage = sanitizeStartupMessage(startupMessageValue);

    if (!validAppearanceColor(cleanTint) ||
            !validAppearanceColor(cleanText)) {
        return {
            {QStringLiteral("ok"), false},
            {QStringLiteral("error"), QStringLiteral("Colors must use #RRGGBB format")}
        };
    }

    if (cleanMessage.isEmpty()) {
        return {
            {QStringLiteral("ok"), false},
            {QStringLiteral("error"), QStringLiteral("Startup message cannot be empty")}
        };
    }

    const QString previousTint = m_tintColor;
    const QString previousText = m_terminalTextColor;
    const QString previousMessage = m_startupMessage;

    m_tintColor = cleanTint;
    m_terminalTextColor = cleanText;
    m_startupMessage = cleanMessage;

    QString writeError;
    if (!saveAppearanceFile(&writeError)) {
        m_tintColor = previousTint;
        m_terminalTextColor = previousText;
        m_startupMessage = previousMessage;
        return {
            {QStringLiteral("ok"), false},
            {QStringLiteral("error"), writeError.isEmpty()
                 ? QStringLiteral("Unable to save terminal customization")
                 : writeError}
        };
    }

    rebuildConfigurationWatchers();
    emit appearanceChanged();
    emit statusChanged();

    return {
        {QStringLiteral("ok"), true},
        {QStringLiteral("message"), QStringLiteral("Appearance saved. The startup message appears with the next shell session.")}
    };
}

QVariantMap TerminalManager::resetAppearance()
{
    return saveAppearance(
        QStringLiteral("#68D8FF"),
        QStringLiteral("#F3FCFF"),
        QStringLiteral("Welcome to NeutronOS Gemini."));
}

void TerminalManager::setInputDraft(
    const QString &text,
    const QString &source)
{
    updateDraft(
        sanitizeDraft(text),
        sanitizeSource(source));
}

void TerminalManager::appendToDraft(
    const QString &text,
    const QString &source)
{
    updateDraft(
        sanitizeDraft(
            m_inputDraft +
            text),
        sanitizeSource(source));
}

void TerminalManager::backspaceDraft(
    const QString &source)
{
    if (m_inputDraft.isEmpty())
        return;

    const int lastIndex =
        m_inputDraft.size() - 1;

    const int removeCount =
        lastIndex >= 1 &&
        m_inputDraft.at(lastIndex)
            .isLowSurrogate() &&
        m_inputDraft.at(lastIndex - 1)
            .isHighSurrogate()
        ? 2
        : 1;

    updateDraft(
        m_inputDraft.left(
            m_inputDraft.size() -
            removeCount),
        sanitizeSource(source));
}

void TerminalManager::clearDraft(
    const QString &source)
{
    updateDraft(
        QString(),
        sanitizeSource(source));
}

void TerminalManager::commitDraft(
    const QString &source)
{
    (void)submitCommand(m_inputDraft, source);
}

QVariantMap TerminalManager::submitCommand(
    const QString &text,
    const QString &source)
{
    const QString safeSource =
        sanitizeSource(source);

    const QString command =
        sanitizeDraft(text);

    /* Keep the backend draft synchronized with the exact visible type-bar text. */
    updateDraft(command, safeSource);

    if (!m_ptyAlive && !startPty()) {
        const QString message =
            m_error.isEmpty()
            ? QStringLiteral("Terminal shell is not available")
            : m_error;

        setError(message);

        return {
            {QStringLiteral("ok"), false},
            {QStringLiteral("error"), message},
            {QStringLiteral("ptyAlive"), false}
        };
    }

    QByteArray bytes =
        command.toUtf8();
    bytes.append('\r');

    if (!queuePtyWrite(bytes)) {
        const QString message =
            m_error.isEmpty()
            ? QStringLiteral("Unable to queue terminal input")
            : m_error;

        setError(message);

        return {
            {QStringLiteral("ok"), false},
            {QStringLiteral("error"), message},
            {QStringLiteral("ptyAlive"), m_ptyAlive}
        };
    }

    if (!command.isEmpty())
        emit commandCommitted(command, safeSource);

    updateDraft(QString(), safeSource);
    setError(QString());

    return {
        {QStringLiteral("ok"), true},
        {QStringLiteral("message"), command.isEmpty()
            ? QStringLiteral("Input sent")
            : QStringLiteral("Command sent")},
        {QStringLiteral("ptyAlive"), m_ptyAlive}
    };
}

void TerminalManager::writeText(
    const QString &text,
    const QString &source)
{
    Q_UNUSED(source)

    if (!m_ptyAlive &&
            !startPty()) {
        return;
    }

    bool truncated = false;

    const QString safeText =
        sanitizePaste(
            text,
            &truncated);

    if (!queuePtyWrite(
            safeText.toUtf8())) {
        setError(
            QStringLiteral(
                "Unable to queue terminal input"));
        return;
    }

    if (truncated) {
        setStatusText(
            QStringLiteral(
                "Input was shortened to protect the terminal"));
    }
}

void TerminalManager::sendKey(
    const QString &key,
    const QString &source)
{
    Q_UNUSED(source)

    if (!m_ptyAlive &&
            !startPty()) {
        return;
    }

    const QByteArray bytes =
        keyToBytes(key);

    if (bytes.isEmpty()) {
        setError(
            QStringLiteral(
                "Unsupported terminal key: %1")
                .arg(key));
        return;
    }

    if (!queuePtyWrite(bytes)) {
        setError(
            QStringLiteral(
                "Unable to queue terminal key"));
    }
}

void TerminalManager::setClipboardText(
    const QString &text,
    const QString &source)
{
    updateClipboard(
        sanitizePaste(text),
        sanitizeSource(source));
}

QString TerminalManager::getClipboardText() const
{
    return m_clipboardText;
}

void TerminalManager::pasteText(
    const QString &text,
    const QString &target,
    const QString &source)
{
    bool truncated = false;

    const QString safeText =
        sanitizePaste(
            text,
            &truncated);

    const QString safeSource =
        sanitizeSource(source);

    updateClipboard(
        safeText,
        safeSource);

    if (target.trimmed().toLower() ==
            QStringLiteral("pty")) {
        writeText(
            safeText,
            safeSource);
    } else {
        appendToDraft(
            safeText,
            safeSource);
    }

    if (truncated) {
        setStatusText(
            QStringLiteral(
                "Paste was shortened to protect the terminal"));
    }
}

void TerminalManager::setSelectionText(
    const QString &text,
    const QString &source)
{
    updateSelection(
        sanitizePaste(text),
        sanitizeSource(source));
}

void TerminalManager::clearSelection(
    const QString &source)
{
    updateSelection(
        QString(),
        sanitizeSource(source));
}

void TerminalManager::copySelection(
    const QString &source)
{
    updateClipboard(
        m_selectionText,
        sanitizeSource(source));
}

void TerminalManager::armQuickAction(
    const QString &id)
{
    const QuickCommand *command =
        findQuickCommand(id);

    if (!command ||
            !command->enabled) {
        setError(
            QStringLiteral(
                "Quick action is unavailable"));
        return;
    }

    const bool requiresArmed =
        command->requiresArmed ||
        commandLooksDangerous(
            command->command);

    if (!requiresArmed) {
        clearArmedQuickAction();
        return;
    }

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    m_armedQuickActionId = id;

    m_armedQuickActionUntilMonotonicMs =
        m_monotonicClock.elapsed() +
        static_cast<qint64>(
            m_armedQuickActionTimeoutSeconds) *
        1000;

    if (!m_armedQuickActionTimer.isActive())
        m_armedQuickActionTimer.start();

    emit armedQuickActionChanged();
    emit statusChanged();

    emit terminalEvent(
        QStringLiteral("quick_action_armed"),
        {
            {
                QStringLiteral("id"),
                id
            },
            {
                QStringLiteral("timeoutSeconds"),
                m_armedQuickActionTimeoutSeconds
            }
        });

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.armedQuickActionChanged")
            },
            {
                QStringLiteral("id"),
                m_armedQuickActionId
            },
            {
                QStringLiteral("secondsRemaining"),
                armedQuickActionSecondsRemaining()
            }
        });
}

void TerminalManager::clearArmedQuickAction()
{
    if (m_armedQuickActionId.isEmpty() &&
            m_armedQuickActionUntilMonotonicMs == 0) {
        return;
    }

    m_armedQuickActionId.clear();
    m_armedQuickActionUntilMonotonicMs = 0;
    m_armedQuickActionTimer.stop();

    emit armedQuickActionChanged();
    emit statusChanged();

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.armedQuickActionChanged")
            },
            {
                QStringLiteral("id"),
                QString()
            },
            {
                QStringLiteral("secondsRemaining"),
                0
            }
        });
}

QVariantMap TerminalManager::runQuickCommand(
    const QString &id,
    bool armed,
    const QString &source)
{
    const QString safeSource =
        sanitizeSource(source);

    QuickCommand *command =
        findQuickCommand(id);

    if (!command) {
        const QVariantMap result =
            quickCommandResult(
                false,
                id,
                QStringLiteral(
                    "Quick action not found"));

        emit quickActionFinished(result);
        return result;
    }

    QString message;

    if (!quickCommandAllowed(
            *command,
            armed,
            safeSource,
            &message)) {
        const QVariantMap result =
            quickCommandResult(
                false,
                id,
                message);

        emit quickActionFinished(result);

        audit(
            QStringLiteral(
                "quick_action_denied"),
            {
                {
                    QStringLiteral("id"),
                    id
                },
                {
                    QStringLiteral("source"),
                    safeSource
                },
                {
                    QStringLiteral("reason"),
                    message
                }
            });

        return result;
    }

    appendOutput(
        QStringLiteral(
            "\r\n[NeutronOS Quick Action] %1\r\n")
            .arg(command->label));

    QByteArray input =
        command->command.toUtf8();

    if (command->enter)
        input.append('\r');

    const bool queued =
        queuePtyWrite(input);

    if (!queued) {
        const QVariantMap result =
            quickCommandResult(
                false,
                id,
                QStringLiteral(
                    "Unable to queue quick action"));

        emit quickActionFinished(result);
        return result;
    }

    clearArmedQuickAction();

    QVariantMap result =
        quickCommandResult(
            true,
            id,
            QStringLiteral("OK"));

    result.insert(
        QStringLiteral("label"),
        command->label);

    audit(
        QStringLiteral("quick_action_run"),
        {
            {
                QStringLiteral("id"),
                id
            },
            {
                QStringLiteral("label"),
                command->label
            },
            {
                QStringLiteral("source"),
                safeSource
            },
            {
                QStringLiteral("mode"),
                m_mode
            }
        });

    emit quickActionFinished(result);

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.quickActionFinished")
            },
            {
                QStringLiteral("result"),
                result
            }
        });

    return result;
}

void TerminalManager::resizeTerminal(
    int columns,
    int rows)
{
    m_columns =
        qBound(20, columns, 500);

    m_rows =
        qBound(8, rows, 200);

    if (m_masterFd >= 0) {
        struct winsize size;
        std::memset(
            &size,
            0,
            sizeof(size));

        size.ws_col =
            static_cast<unsigned short>(
                m_columns);

        size.ws_row =
            static_cast<unsigned short>(
                m_rows);

        ::ioctl(
            m_masterFd,
            TIOCSWINSZ,
            &size);

        if (m_childPid > 0)
            sendSignalToPtyProcessGroup(SIGWINCH);
    }

    emit statusChanged();

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral("terminal.resized")
            },
            {
                QStringLiteral("columns"),
                m_columns
            },
            {
                QStringLiteral("rows"),
                m_rows
            }
        });
}

void TerminalManager::startWebMirror()
{
    requestStartWebMirror(false);
}

void TerminalManager::stopWebMirror()
{
    disconnectWebClients();

    if (m_webServer)
        m_webServer->close();

    m_webClientSweepTimer.stop();

    const bool changed =
        m_webMirrorRunning ||
        !m_webBindAddress.isEmpty();

    const bool hadPairingCode =
        !m_webToken.isEmpty();

    m_webMirrorRunning = false;
    m_webBindAddress.clear();
    m_webToken.clear();
    m_webTokenExpiresMonotonicMs = 0;

    if (hadPairingCode) {
        emit webTokenChanged();
        emit webPairingCodeChanged();
    }

    if (changed || hadPairingCode) {
        emit webMirrorChanged();
        emit webClientCountChanged();
        emit statusChanged();
    }
}

bool TerminalManager::requestStartWebMirror(
    bool confirmDeveloperAccess)
{
    if (!m_webMirrorEnabled) {
        setError(
            QStringLiteral(
                "Terminal web mirror is disabled"));
        return false;
    }

    if (developerMode()) {
        if (confirmDeveloperAccess)
            m_developerWebMirrorConfirmed = true;

        if (!m_developerWebMirrorConfirmed) {
            stopWebMirror();

            setError(
                QStringLiteral(
                    "Developer shell web access requires local confirmation"));

            emit webMirrorSecurityChanged();
            emit statusChanged();

            return false;
        }
    }

    if (!ensureDirectories()) {
        setError(
            QStringLiteral(
                "Terminal web security directories are unavailable"));
        return false;
    }

    QString bindAddress;
    QString bindError;

    if (!selectWebBindAddress(
            &bindAddress,
            &bindError)) {
        setError(bindError);
        return false;
    }

    if (m_webMirrorRunning &&
            m_webBindAddress == bindAddress) {
        return true;
    }

    if (m_webMirrorRunning)
        stopWebMirror();

    if (!m_webServer) {
        m_webServer =
            new QTcpServer(this);

        connect(
            m_webServer,
            &QTcpServer::newConnection,
            this,
            &TerminalManager::handleNewWebConnection);
    }

    const QHostAddress address(bindAddress);

    if (!m_webServer->listen(
            address,
            static_cast<quint16>(
                m_webPort))) {
        setError(
            QStringLiteral(
                "Unable to start terminal web mirror on port %1: %2")
                .arg(m_webPort)
                .arg(m_webServer->errorString()));

        m_webMirrorRunning = false;
        m_webBindAddress.clear();

        emit webMirrorChanged();
        emit statusChanged();

        return false;
    }

    m_webMirrorRunning = true;
    m_webBindAddress = bindAddress;

    if (!m_webClientSweepTimer.isActive())
        m_webClientSweepTimer.start();

    setError(QString());

    setStatusText(
        QStringLiteral(
            "Remote mirror ready: %1")
            .arg(webUrl()));

    emit webMirrorChanged();
    emit webMirrorSecurityChanged();
    emit statusChanged();

    audit(
        QStringLiteral("web_mirror_started"),
        {
            {
                QStringLiteral("bindAddress"),
                bindAddress
            },
            {
                QStringLiteral("developerMode"),
                developerMode()
            },
            {
                QStringLiteral("lanAccessEnabled"),
                m_webMirrorLanAccessEnabled
            }
        });

    return true;
}

bool TerminalManager::confirmDeveloperWebMirrorAccess()
{
    if (!developerMode()) {
        m_developerWebMirrorConfirmed = false;
        emit webMirrorSecurityChanged();
        return requestStartWebMirror(false);
    }

    m_developerWebMirrorConfirmed = true;

    emit webMirrorSecurityChanged();
    emit statusChanged();

    audit(
        QStringLiteral(
            "developer_web_access_confirmed"));

    return requestStartWebMirror(true);
}

void TerminalManager::revokeDeveloperWebMirrorAccess()
{
    const bool changed =
        m_developerWebMirrorConfirmed;

    m_developerWebMirrorConfirmed = false;

    if (developerMode())
        stopWebMirror();

    if (changed) {
        emit webMirrorSecurityChanged();
        emit statusChanged();

        audit(
            QStringLiteral(
                "developer_web_access_revoked"));
    }
}

void TerminalManager::disconnectWebClients()
{
    const QList<QTcpSocket *> sockets =
        m_webClients.keys();

    for (QTcpSocket *socket : sockets) {
        disconnectWebClient(
            socket,
            1001,
            QStringLiteral(
                "Terminal web session closed"));
    }

    if (!sockets.isEmpty()) {
        emit webClientCountChanged();
        emit statusChanged();
    }
}

QString TerminalManager::generateWebPairingCode()
{
    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    refreshWebAuthLockout();
    if (webAuthLocked()) {
        const int seconds = webAuthLockSecondsRemaining();
        setError(QStringLiteral("Remote Mirror pairing is locked. Try again in %1 minute(s).")
                     .arg(qMax(1, (seconds + 59) / 60)));
        return QString();
    }

    /*
        Remote Mirror is deliberately opt-in. Generating a local pairing code
        is itself an explicit local action, so it also enables LAN access and
        starts the mirror when necessary. Existing authenticated clients stay
        connected; only the not-yet-used pairing code is rotated.
    */
    if (!m_webMirrorLanAccessEnabled) {
        m_webMirrorLanAccessEnabled = true;
        emit webMirrorSecurityChanged();
    }

    if (!m_webMirrorEnabled) {
        m_webMirrorEnabled = true;
        emit webMirrorChanged();
    }

    const bool started =
        requestStartWebMirror(
            developerMode());

    if (!started) {
        m_webToken.clear();
        m_webTokenExpiresMonotonicMs = 0;
        emit webTokenChanged();
        emit webPairingCodeChanged();
        return QString();
    }

    m_webToken = generateWebToken();
    m_webTokenExpiresMonotonicMs =
        m_monotonicClock.elapsed() +
        WebPairingCodeLifetimeMs;

    setError(QString());

    emit webTokenChanged();
    emit webPairingCodeChanged();
    emit webMirrorChanged();
    emit webMirrorSecurityChanged();
    emit statusChanged();

    audit(
        QStringLiteral(
            "web_pairing_code_generated"),
        {
            {
                QStringLiteral("lifetimeSeconds"),
                m_webPairingCodeLifetimeSeconds
            }
        });

    return m_webToken;
}

QVariantMap TerminalManager::setRemoteMirrorActive(
    bool enabled)
{
    if (!enabled) {
        setWebMirrorEnabled(false);
        setError(QString());

        return {
            {QStringLiteral("ok"), true},
            {QStringLiteral("enabled"), false},
            {QStringLiteral("running"), false},
            {QStringLiteral("message"), QStringLiteral("Remote mirror disabled")}
        };
    }

    /*
        One atomic local action: enable LAN binding, enable the feature, then
        perform the developer-mode confirmation in the same backend call.
        This avoids the previous QML sequence where the property setter could
        fail once before a second call attempted confirmation.
    */
    if (!m_webMirrorLanAccessEnabled) {
        m_webMirrorLanAccessEnabled = true;
        emit webMirrorSecurityChanged();
    }

    if (!m_webMirrorEnabled) {
        m_webMirrorEnabled = true;
        emit webMirrorChanged();
    }

    const bool started =
        requestStartWebMirror(developerMode());

    if (!started) {
        const QString message =
            m_error.isEmpty()
            ? QStringLiteral("Unable to enable Remote Terminal Mirror")
            : m_error;

        m_webMirrorEnabled = false;
        m_developerWebMirrorConfirmed = false;
        stopWebMirror();
        setError(message);
        emit webMirrorChanged();
        emit webMirrorSecurityChanged();
        emit statusChanged();

        return {
            {QStringLiteral("ok"), false},
            {QStringLiteral("enabled"), false},
            {QStringLiteral("running"), false},
            {QStringLiteral("error"), message}
        };
    }

    return {
        {QStringLiteral("ok"), true},
        {QStringLiteral("enabled"), m_webMirrorEnabled},
        {QStringLiteral("running"), m_webMirrorRunning},
        {QStringLiteral("url"), webUrl()},
        {QStringLiteral("message"), QStringLiteral("Remote mirror enabled")}
    };
}

QVariantMap TerminalManager::generateRemoteMirrorCode()
{
    const QVariantMap enabledResult =
        setRemoteMirrorActive(true);

    if (!enabledResult.value(QStringLiteral("ok")).toBool())
        return enabledResult;

    const QString code =
        generateWebPairingCode();

    if (code.isEmpty()) {
        return {
            {QStringLiteral("ok"), false},
            {QStringLiteral("enabled"), m_webMirrorEnabled},
            {QStringLiteral("running"), m_webMirrorRunning},
            {QStringLiteral("error"), m_error.isEmpty()
                ? QStringLiteral("Unable to generate a Remote Mirror code")
                : m_error}
        };
    }

    return {
        {QStringLiteral("ok"), true},
        {QStringLiteral("enabled"), m_webMirrorEnabled},
        {QStringLiteral("running"), m_webMirrorRunning},
        {QStringLiteral("url"), webUrl()},
        {QStringLiteral("code"), code},
        {QStringLiteral("secondsRemaining"), webPairingCodeSecondsRemaining()},
        {QStringLiteral("message"), QStringLiteral("Connection code generated")}
    };
}

void TerminalManager::regenerateWebToken()
{
    generateWebPairingCode();
}

QVariantMap TerminalManager::refreshStatus()
{
    syncModeFromDeveloperManager(false);
    emit statusChanged();
    return makeStatusPayload();
}


void TerminalManager::resolvePaths()
{
    m_repoRoot =
        findRepositoryRoot(
            m_regularUsername);

    m_stateDir =
        QStringLiteral(
            NEUTRONOS_STATE_DIR) +
        QStringLiteral("/terminal");

    m_securityDir =
        QStringLiteral(
            NEUTRONOS_SECURITY_STATE_DIR) +
        QStringLiteral("/terminal");

    m_configDir =
        QDir(m_stateDir)
            .filePath(
                QStringLiteral("config"));

    m_logDir =
        QStringLiteral(
            NEUTRONOS_LOG_DIR);

    m_quickCommandsPath =
        QDir(m_configDir)
            .filePath(
                QStringLiteral(
                    "terminal_quick_commands.json"));

    m_appearancePath =
        QDir(m_configDir)
            .filePath(
                QStringLiteral(
                    "terminal_appearance.json"));

    m_auditPath =
        QDir(m_logDir)
            .filePath(
                QStringLiteral(
                    "terminal_audit.log"));
}

bool TerminalManager::ensureDirectories()
{
    const QString stateRoot =
        QStringLiteral(
            NEUTRONOS_STATE_DIR);

    const QString securityRoot =
        QStringLiteral(
            NEUTRONOS_SECURITY_STATE_DIR);

    const QString logRoot =
        QStringLiteral(
            NEUTRONOS_LOG_DIR);

    const QStringList protectedPaths = {
        stateRoot,
        securityRoot,
        logRoot
    };

    for (const QString &path :
            protectedPaths) {
        const QFileInfo info(path);

        if (info.exists() &&
                info.isSymLink()) {
            return false;
        }
    }

    const QFileInfo configInfo(
        m_configDir);

    if (configInfo.exists() &&
            configInfo.isSymLink()) {
        return false;
    }

    if (!QDir().mkpath(stateRoot) ||
            !QDir().mkpath(securityRoot) ||
            !QDir().mkpath(logRoot) ||
            !QDir().mkpath(m_configDir)) {
        return false;
    }

#ifdef Q_OS_LINUX
    const uid_t effectiveUser =
        ::geteuid();

    auto secureBase =
        [effectiveUser](
            const QString &path,
            mode_t mode) {
            const QByteArray encoded =
                path.toLocal8Bit();

            if (effectiveUser == 0) {
                if (::chown(
                        encoded.constData(),
                        0,
                        0) != 0) {
                    return false;
                }
            }

            return ::chmod(
                       encoded.constData(),
                       mode) == 0;
        };

    if (!secureBase(
            stateRoot,
            static_cast<mode_t>(0700)) ||
            !secureBase(
                securityRoot,
                static_cast<mode_t>(0700)) ||
            !secureBase(
                logRoot,
                static_cast<mode_t>(0700))) {
        return false;
    }
#endif

    return ensureDirectory(
               m_stateDir,
               true) &&
           ensureDirectory(
               m_securityDir,
               true) &&
           ensureDirectory(
               m_logDir,
               true);
}

bool TerminalManager::ensureDirectory(
    const QString &path,
    bool ownerOnly) const
{
    if (path.trimmed().isEmpty())
        return false;

    const QFileInfo existing(path);

    if (existing.exists() &&
            existing.isSymLink()) {
        return false;
    }

    if (!QDir().mkpath(path))
        return false;

    QFileDevice::Permissions permissions =
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner |
        QFileDevice::ExeOwner;

    if (!ownerOnly) {
        permissions |=
            QFileDevice::ReadGroup |
            QFileDevice::ExeGroup |
            QFileDevice::ReadOther |
            QFileDevice::ExeOther;
    }

    if (!QFile::setPermissions(
            path,
            permissions)) {
        return false;
    }

#ifdef Q_OS_LINUX
    const QByteArray encoded =
        path.toLocal8Bit();

    const mode_t mode =
        ownerOnly
        ? static_cast<mode_t>(0700)
        : static_cast<mode_t>(0755);

    if (::chmod(
            encoded.constData(),
            mode) != 0) {
        return false;
    }

    if (::geteuid() == 0 &&
            ::chown(
                encoded.constData(),
                0,
                0) != 0) {
        return false;
    }
#endif

    return pathIsSafe(
        path,
        true,
        ownerOnly);
}

bool TerminalManager::secureFilePermissions(
    const QString &path) const
{
    const QFileInfo info(path);

    if (!info.exists() ||
            info.isSymLink() ||
            !info.isFile()) {
        return false;
    }

    if (!QFile::setPermissions(
            path,
            QFileDevice::ReadOwner |
            QFileDevice::WriteOwner)) {
        return false;
    }

#ifdef Q_OS_LINUX
    const QByteArray encoded =
        path.toLocal8Bit();

    if (::chmod(
            encoded.constData(),
            static_cast<mode_t>(0600)) != 0) {
        return false;
    }

    if (::geteuid() == 0 &&
            ::chown(
                encoded.constData(),
                0,
                0) != 0) {
        return false;
    }
#endif

    return pathIsSafe(
        path,
        false,
        true);
}

bool TerminalManager::pathIsSafe(
    const QString &path,
    bool directory,
    bool ownerOnly) const
{
#ifdef Q_OS_LINUX
    const QByteArray encoded =
        path.toLocal8Bit();

    struct stat state;

    if (::lstat(
            encoded.constData(),
            &state) != 0) {
        return false;
    }

    if (S_ISLNK(state.st_mode))
        return false;

    if (directory &&
            !S_ISDIR(state.st_mode)) {
        return false;
    }

    if (!directory &&
            !S_ISREG(state.st_mode)) {
        return false;
    }

    if (ownerOnly &&
            (state.st_mode &
             (S_IRWXG | S_IRWXO)) != 0) {
        return false;
    }

    if (ownerOnly &&
            state.st_uid != ::geteuid()) {
        return false;
    }

    return true;
#else
    Q_UNUSED(path)
    Q_UNUSED(directory)
    Q_UNUSED(ownerOnly)
    return true;
#endif
}

void TerminalManager::rebuildConfigurationWatchers()
{
    const QStringList files =
        m_configurationWatcher.files();

    if (!files.isEmpty())
        m_configurationWatcher.removePaths(files);

    const QStringList directories =
        m_configurationWatcher.directories();

    if (!directories.isEmpty())
        m_configurationWatcher.removePaths(directories);

    m_watchedConfigurationPaths.clear();

    auto addPath =
        [this](const QString &path) {
            if (path.isEmpty() ||
                    !QFileInfo::exists(path)) {
                return;
            }

            const QString clean =
                QDir::cleanPath(path);

            if (m_watchedConfigurationPaths.contains(clean))
                return;

            if (m_configurationWatcher.addPath(clean))
                m_watchedConfigurationPaths.insert(clean);
        };

    addPath(m_configDir);
    addPath(m_quickCommandsPath);
    addPath(m_appearancePath);
}

void TerminalManager::scheduleConfigurationReload()
{
    if (!m_configurationReloadTimer.isActive())
        m_configurationReloadTimer.start();
}

void TerminalManager::onConfigPathChanged(
    const QString &path)
{
    Q_UNUSED(path)
    scheduleConfigurationReload();
}

void TerminalManager::reloadWatchedConfiguration()
{
    loadQuickCommands();
    loadAppearance();
    rebuildConfigurationWatchers();
}

bool TerminalManager::validAppearanceColor(const QString &value)
{
    static const QRegularExpression pattern(
        QStringLiteral("^#[0-9A-Fa-f]{6}$"));
    return pattern.match(value.trimmed()).hasMatch();
}

QString TerminalManager::sanitizeStartupMessage(const QString &value)
{
    QString result;
    result.reserve(qMin(value.size(), MaximumStartupMessageCharacters));

    for (const QChar character : value) {
        if (result.size() >= MaximumStartupMessageCharacters)
            break;

        if (character == QLatin1Char('\n') ||
                character == QLatin1Char('\r')) {
            if (!result.endsWith(QLatin1Char('\n')))
                result.append(QLatin1Char('\n'));
            continue;
        }

        if (character.unicode() < 0x20 || character.unicode() == 0x7f)
            continue;

        result.append(character);
    }

    QStringList lines = result.split(QLatin1Char('\n'));
    while (lines.size() > 4)
        lines.removeLast();

    return lines.join(QLatin1Char('\n')).trimmed();
}

bool TerminalManager::saveAppearanceFile(QString *errorMessage) const
{
    QDir configDirectory(m_configDir);
    if (!configDirectory.exists() &&
            !QDir().mkpath(m_configDir)) {
        if (errorMessage)
            *errorMessage = QStringLiteral("Unable to create terminal configuration directory");
        return false;
    }

    QSaveFile file(m_appearancePath);
    if (!file.open(QIODevice::WriteOnly)) {
        if (errorMessage)
            *errorMessage = QStringLiteral("Unable to open terminal appearance configuration");
        return false;
    }

    const QJsonObject object {
        {QStringLiteral("tintColor"), m_tintColor},
        {QStringLiteral("textColor"), m_terminalTextColor},
        {QStringLiteral("startupMessage"), m_startupMessage}
    };

    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("Unable to commit terminal appearance configuration");
        return false;
    }

    QFile::setPermissions(
        m_appearancePath,
        QFileDevice::ReadOwner | QFileDevice::WriteOwner |
        QFileDevice::ReadGroup | QFileDevice::ReadOther);
    return true;
}

void TerminalManager::loadAppearance()
{
    QString tint = QStringLiteral("#68D8FF");
    QString text = QStringLiteral("#F3FCFF");
    QString message = QStringLiteral("Welcome to NeutronOS Gemini.");

    const QFileInfo info(m_appearancePath);
    if (info.exists() && !info.isSymLink() && info.isFile() &&
            info.size() <= MaximumAppearanceFileBytes) {
        QFile file(m_appearancePath);
        if (file.open(QIODevice::ReadOnly)) {
            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
            if (parseError.error == QJsonParseError::NoError && document.isObject()) {
                const QJsonObject object = document.object();
                const QString candidateTint = object.value(QStringLiteral("tintColor")).toString().trimmed().toUpper();
                const QString candidateText = object.value(QStringLiteral("textColor")).toString().trimmed().toUpper();
                const QString candidateMessage = sanitizeStartupMessage(object.value(QStringLiteral("startupMessage")).toString());
                if (validAppearanceColor(candidateTint))
                    tint = candidateTint;
                if (validAppearanceColor(candidateText))
                    text = candidateText;
                if (!candidateMessage.isEmpty())
                    message = candidateMessage;
            }
        }
    }

    const bool changed = tint != m_tintColor || text != m_terminalTextColor || message != m_startupMessage;
    m_tintColor = tint;
    m_terminalTextColor = text;
    m_startupMessage = message;

    if (!info.exists()) {
        QString ignored;
        saveAppearanceFile(&ignored);
    }

    if (changed)
        emit appearanceChanged();
}

void TerminalManager::loadQuickCommands()
{
    saveDefaultQuickCommandsIfMissing();

    QFileInfo fileInfo(m_quickCommandsPath);

    if (!fileInfo.exists() ||
            fileInfo.isSymLink() ||
            !fileInfo.isFile() ||
            fileInfo.size() >
                MaximumQuickCommandFileBytes) {
        setError(
            QStringLiteral(
                "Terminal quick-command configuration is missing or unsafe"));
        return;
    }

    QFile file(m_quickCommandsPath);

    if (!file.open(
            QIODevice::ReadOnly)) {
        setError(
            QStringLiteral(
                "Unable to read terminal quick commands"));
        return;
    }

    const QByteArray data =
        file.read(
            MaximumQuickCommandFileBytes +
            1);

    file.close();

    if (data.size() >
            MaximumQuickCommandFileBytes) {
        setError(
            QStringLiteral(
                "Terminal quick-command configuration is too large"));
        return;
    }

    QJsonParseError parseError;

    const QJsonDocument document =
        QJsonDocument::fromJson(
            data,
            &parseError);

    if (parseError.error !=
            QJsonParseError::NoError ||
            !document.isArray()) {
        setError(
            QStringLiteral(
                "terminal_quick_commands.json must contain a JSON array"));
        return;
    }

    const QJsonArray array =
        document.array();

    QList<QuickCommand> parsed;
    QSet<QString> seenIds;

    const int count =
        std::min(
            static_cast<int>(
                array.size()),
            MaximumQuickCommands);

    for (int index = 0;
            index < count;
            ++index) {
        if (!array.at(index).isObject())
            continue;

        QuickCommand command;
        QString errorMessage;

        if (!parseQuickCommand(
                array.at(index)
                    .toObject()
                    .toVariantMap(),
                &command,
                &errorMessage)) {
            audit(
                QStringLiteral(
                    "quick_command_rejected"),
                {
                    {
                        QStringLiteral("index"),
                        index
                    },
                    {
                        QStringLiteral("reason"),
                        errorMessage
                    }
                });

            continue;
        }

        if (seenIds.contains(
                command.id)) {
            audit(
                QStringLiteral(
                    "quick_command_duplicate"),
                {
                    {
                        QStringLiteral("id"),
                        command.id
                    }
                });

            continue;
        }

        seenIds.insert(command.id);
        parsed.append(command);
    }

    m_quickCommands = parsed;

    setError(QString());

    emit quickCommandsChanged();
    emit statusChanged();
}

void TerminalManager::saveDefaultQuickCommandsIfMissing()
{
    const QFileInfo existing(
        m_quickCommandsPath);

    if (existing.exists())
        return;

    if (!QDir().mkpath(m_configDir))
        return;

    QJsonArray array;

    auto appendCommand =
        [&array](
            const QString &id,
            const QString &label,
            const QString &group,
            const QString &icon,
            const QString &command,
            bool enter,
            bool requiresArmed,
            bool developerOnly,
            bool rootRequired) {
            QJsonObject object;

            object.insert(
                QStringLiteral("id"),
                id);

            object.insert(
                QStringLiteral("label"),
                label);

            object.insert(
                QStringLiteral("group"),
                group);

            object.insert(
                QStringLiteral("icon"),
                icon);

            object.insert(
                QStringLiteral("command"),
                command);

            object.insert(
                QStringLiteral("enter"),
                enter);

            object.insert(
                QStringLiteral("requiresArmed"),
                requiresArmed);

            object.insert(
                QStringLiteral("developerOnly"),
                developerOnly);

            object.insert(
                QStringLiteral("rootRequired"),
                rootRequired);

            object.insert(
                QStringLiteral("enabled"),
                true);

            array.append(object);
        };

    appendCommand(
        QStringLiteral("system-status"),
        QStringLiteral("System Status"),
        QStringLiteral("System"),
        QStringLiteral("monitor"),
        QStringLiteral(
            "uptime && echo && free -h && echo && df -h"),
        true,
        false,
        false,
        false);

    appendCommand(
        QStringLiteral("network-status"),
        QStringLiteral("Network Status"),
        QStringLiteral("System"),
        QStringLiteral("network"),
        QStringLiteral(
            "hostname -I && echo && ip -brief address"),
        true,
        false,
        false,
        false);

    appendCommand(
        QStringLiteral("docker-containers"),
        QStringLiteral("Docker Containers"),
        QStringLiteral("Docker"),
        QStringLiteral("docker"),
        QStringLiteral(
            "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'"),
        true,
        false,
        false,
        false);

    appendCommand(
        QStringLiteral("mediaoptimizer-logs"),
        QStringLiteral("Media Optimizer Logs"),
        QStringLiteral("Logs"),
        QStringLiteral("logs"),
        QStringLiteral(
            "journalctl -u neutronos.service -n 240 --no-pager | grep -iE 'MediaOptimizer|ffmpeg|ffprobe' || true"),
        true,
        false,
        false,
        false);

    appendCommand(
        QStringLiteral("restart-jellyfin"),
        QStringLiteral("Restart Jellyfin"),
        QStringLiteral("Armed"),
        QStringLiteral("restart"),
        QStringLiteral(
            "docker restart jellyfin"),
        true,
        true,
        false,
        false);

    appendCommand(
        QStringLiteral("restart-qbit"),
        QStringLiteral("Restart qBittorrent"),
        QStringLiteral("Armed"),
        QStringLiteral("restart"),
        QStringLiteral(
            "docker restart qbittorrent"),
        true,
        true,
        false,
        false);

    appendCommand(
        QStringLiteral("root-filesystem"),
        QStringLiteral("Root Filesystem"),
        QStringLiteral("Developer"),
        QStringLiteral("terminal"),
        QStringLiteral(
            "cd / && ls -la"),
        true,
        true,
        true,
        true);

    QSaveFile file(
        m_quickCommandsPath);

    file.setDirectWriteFallback(false);

    if (!file.open(
            QIODevice::WriteOnly)) {
        return;
    }

    const QByteArray data =
        QJsonDocument(array)
            .toJson(
                QJsonDocument::Indented);

    if (file.write(data) != data.size()) {
        file.cancelWriting();
        return;
    }

    if (!file.commit())
        return;

    QFile::setPermissions(
        m_quickCommandsPath,
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner |
        QFileDevice::ReadGroup |
        QFileDevice::ReadOther);

#ifdef Q_OS_LINUX
    const QByteArray encoded =
        m_quickCommandsPath.toLocal8Bit();

    ::chmod(
        encoded.constData(),
        static_cast<mode_t>(0644));
#endif
}

bool TerminalManager::parseQuickCommand(
    const QVariantMap &source,
    QuickCommand *result,
    QString *errorMessage) const
{
    if (!result)
        return false;

    QuickCommand command;

    command.id =
        source.value(
            QStringLiteral("id"))
            .toString()
            .trimmed();

    command.label =
        source.value(
            QStringLiteral("label"),
            command.id)
            .toString()
            .trimmed()
            .left(96);

    command.group =
        source.value(
            QStringLiteral("group"),
            QStringLiteral("General"))
            .toString()
            .trimmed()
            .left(64);

    command.icon =
        source.value(
            QStringLiteral("icon"),
            QStringLiteral("terminal"))
            .toString()
            .trimmed()
            .left(128);

    command.command =
        source.value(
            QStringLiteral("command"))
            .toString();

    command.enter =
        source.value(
            QStringLiteral("enter"),
            true)
            .toBool();

    command.requiresArmed =
        source.value(
            QStringLiteral("requiresArmed"),
            false)
            .toBool();

    command.developerOnly =
        source.value(
            QStringLiteral("developerOnly"),
            false)
            .toBool();

    command.rootRequired =
        source.value(
            QStringLiteral("rootRequired"),
            false)
            .toBool();

    command.enabled =
        source.value(
            QStringLiteral("enabled"),
            true)
            .toBool();

    if (!safeIdentifier(command.id)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Invalid quick-command ID");
        }

        return false;
    }

    if (command.command.isEmpty() ||
            command.command.size() > 4096 ||
            command.command.contains(
                QChar(0))) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Invalid quick-command text");
        }

        return false;
    }

    if (command.label.isEmpty())
        command.label = command.id;

    if (command.group.isEmpty())
        command.group =
            QStringLiteral("General");

    command.requiresArmed =
        command.requiresArmed ||
        commandLooksDangerous(
            command.command);

    *result = command;

    if (errorMessage)
        errorMessage->clear();

    return true;
}

QString TerminalManager::currentModeFromDeveloperManager() const
{
    return m_developerModeManager &&
           m_developerModeManager
               ->developerModeEnabled()
           ? QStringLiteral("developer")
           : QStringLiteral("regular");
}

void TerminalManager::syncModeFromDeveloperManager(
    bool forceRestart)
{
    const QString actualMode =
        currentModeFromDeveloperManager();

    const bool changed =
        actualMode != m_mode;

    if (!changed &&
            !forceRestart) {
        return;
    }

    const bool enteringDeveloper =
        actualMode ==
            QStringLiteral("developer") &&
        m_mode != actualMode;

    const bool leavingDeveloper =
        m_mode ==
            QStringLiteral("developer") &&
        actualMode != m_mode;

    if (enteringDeveloper) {
        m_developerWebMirrorConfirmed = false;
        stopWebMirror();
        clearArmedQuickAction();

        emit webMirrorSecurityChanged();

        audit(
            QStringLiteral(
                "developer_mode_entered"));
    }

    setMode(actualMode);

    if (leavingDeveloper) {
        m_developerWebMirrorConfirmed = false;

        emit webMirrorSecurityChanged();

        audit(
            QStringLiteral(
                "developer_mode_left"));
    }

    emit quickCommandsChanged();

    if (m_running &&
            (m_ptyAlive ||
             m_childPid > 0)) {
        m_restartAfterPtyExit = true;
        m_expectedPtyExit = true;
        requestPtyShutdown();
    } else if (m_running) {
        startPty();
    }

    if (m_running &&
            m_webMirrorEnabled &&
            !developerMode()) {
        requestStartWebMirror(false);
    }

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.modeChanged")
            },
            {
                QStringLiteral("mode"),
                m_mode
            },
            {
                QStringLiteral("modeLabel"),
                modeLabel()
            },
            {
                QStringLiteral("status"),
                publicWebStatusPayload()
            }
        });
}

QString TerminalManager::resolveRegularUsername() const
{
    if (safeUsername(
            m_regularUsername) &&
            m_regularUsername !=
                QStringLiteral("root")) {
        return m_regularUsername;
    }

    return discoverCurrentAccount();
}

bool TerminalManager::resolveRegularAccount(
    const QString &username,
    PtyLaunchPlan *plan,
    QString *errorMessage) const
{
    if (!plan)
        return false;

    *plan = PtyLaunchPlan();

    const QString clean =
        username.trimmed();

    if (!safeUsername(clean) ||
            clean ==
                QStringLiteral("root")) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "A valid non-root terminal account is required");
        }

        return false;
    }

#ifdef Q_OS_LINUX
    long bufferSize =
        ::sysconf(_SC_GETPW_R_SIZE_MAX);

    if (bufferSize < 1024)
        bufferSize = 16384;

    std::vector<char> buffer(
        static_cast<std::size_t>(
            bufferSize));

    struct passwd account;
    struct passwd *result = nullptr;

    const QByteArray encoded =
        clean.toLocal8Bit();

    if (::getpwnam_r(
            encoded.constData(),
            &account,
            buffer.data(),
            buffer.size(),
            &result) != 0 ||
            !result) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Local terminal account '%1' was not found")
                    .arg(clean);
        }

        return false;
    }

    if (result->pw_uid == 0) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Regular terminal mode cannot use the root account");
        }

        return false;
    }

    QString shell =
        passwdText(
            result->pw_shell);

    if (shell.isEmpty() ||
            shellIsBlocked(shell) ||
            !isExecutableRegularFile(shell)) {
        shell = regularShellPath();
    }

    if (!isExecutableRegularFile(shell)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "No executable regular-user shell is available");
        }

        return false;
    }

    const QString home =
        passwdText(
            result->pw_dir);

    if (home.isEmpty() ||
            !QFileInfo(home).isDir()) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "The regular terminal account has no usable home directory");
        }

        return false;
    }

    int groupCount = 0;

    ::getgrouplist(
        result->pw_name,
        result->pw_gid,
        nullptr,
        &groupCount);

    groupCount =
        qBound(
            1,
            groupCount,
            MaximumSupplementaryGroups);

    std::vector<gid_t> groups(
        static_cast<std::size_t>(
            groupCount));

    int writableGroupCount =
        groupCount;

    if (::getgrouplist(
            result->pw_name,
            result->pw_gid,
            groups.data(),
            &writableGroupCount) < 0) {
        if (writableGroupCount >
                MaximumSupplementaryGroups) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "The account belongs to too many supplementary groups");
            }

            return false;
        }

        groups.resize(
            static_cast<std::size_t>(
                qMax(
                    1,
                    writableGroupCount)));

        groupCount =
            writableGroupCount;

        if (::getgrouplist(
                result->pw_name,
                result->pw_gid,
                groups.data(),
                &groupCount) < 0) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Unable to resolve supplementary groups for the terminal account");
            }

            return false;
        }
    }

    plan->supplementaryGroups.clear();
    plan->supplementaryGroups.reserve(
        groupCount);

    for (int index = 0;
            index < groupCount;
            ++index) {
        plan->supplementaryGroups.append(
            static_cast<quint32>(
                groups[
                    static_cast<std::size_t>(
                        index)]));
    }

    plan->shellPath =
        shell.toLocal8Bit();

    plan->argumentZero =
        QByteArray("-") +
        QFileInfo(shell)
            .fileName()
            .toLocal8Bit();

    plan->workingDirectory =
        home.toLocal8Bit();

    plan->home =
        home.toLocal8Bit();

    plan->user =
        clean.toLocal8Bit();

    plan->logName =
        plan->user;

    plan->term =
        QByteArrayLiteral(
            "xterm-256color");

    plan->colorTerm =
        QByteArrayLiteral(
            "truecolor");

    plan->terminalMode =
        QByteArrayLiteral(
            "regular");

    plan->developerMode =
        QByteArrayLiteral("0");

    plan->uid =
        static_cast<quint32>(
            result->pw_uid);

    plan->gid =
        static_cast<quint32>(
            result->pw_gid);

    plan->dropPrivileges =
        ::geteuid() == 0;

    if (!plan->dropPrivileges &&
            (::geteuid() !=
                 result->pw_uid ||
             ::getegid() !=
                 result->pw_gid)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "NeutronShell lacks permission to enter the requested regular-user account");
        }

        return false;
    }

    plan->developer = false;
    plan->valid = true;

    if (errorMessage)
        errorMessage->clear();

    return true;
#else
    Q_UNUSED(errorMessage)
    Q_UNUSED(clean)
    return false;
#endif
}

QString TerminalManager::regularShellPath() const
{
    const QString configured =
        environmentText(
            "NEUTRONOS_REGULAR_SHELL");

    if (!configured.isEmpty() &&
            isExecutableRegularFile(
                configured) &&
            !shellIsBlocked(
                configured)) {
        return QDir::cleanPath(
            configured);
    }

    return QStringLiteral(
        "/bin/bash");
}

QString TerminalManager::developerShellPath() const
{
    const QString configured =
        environmentText(
            "NEUTRONOS_DEVELOPER_SHELL");

    if (!configured.isEmpty() &&
            isExecutableRegularFile(
                configured) &&
            !shellIsBlocked(
                configured)) {
        return QDir::cleanPath(
            configured);
    }

    return QStringLiteral(
        "/bin/bash");
}


bool TerminalManager::buildPtyLaunchPlan(
    PtyLaunchPlan *plan,
    QString *errorMessage) const
{
    if (!plan)
        return false;

    *plan = PtyLaunchPlan();

    if (!developerMode()) {
        const QString username =
            resolveRegularUsername();

        return resolveRegularAccount(
            username,
            plan,
            errorMessage);
    }

#ifdef Q_OS_LINUX
    if (::geteuid() != 0) {
        /*
            The production NeutronShell service runs as the signed-in console
            user. Developer Mode must not make Terminal completely unusable
            merely because the GUI process is intentionally unprivileged.
            Fall back to the real local-user PTY and keep the prompt honest.
            Privileged actions continue to follow NeutronOS privilege policy.
        */
        const QString username =
            resolveRegularUsername();

        return resolveRegularAccount(
            username,
            plan,
            errorMessage);
    }
#endif

    const QString shell =
        developerShellPath();

    if (!isExecutableRegularFile(shell)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "No executable developer shell is available");
        }

        return false;
    }

    plan->shellPath =
        shell.toLocal8Bit();

    plan->argumentZero =
        QByteArray("-") +
        QFileInfo(shell)
            .fileName()
            .toLocal8Bit();

    plan->workingDirectory =
        QByteArrayLiteral("/");

    plan->home =
        QByteArrayLiteral("/root");

    plan->user =
        QByteArrayLiteral("root");

    plan->logName =
        QByteArrayLiteral("root");

    plan->term =
        QByteArrayLiteral(
            "xterm-256color");

    plan->colorTerm =
        QByteArrayLiteral(
            "truecolor");

    plan->terminalMode =
        QByteArrayLiteral(
            "developer");

    plan->developerMode =
        QByteArrayLiteral("1");

    plan->uid = 0;
    plan->gid = 0;
    plan->dropPrivileges = false;
    plan->developer = true;
    plan->valid = true;

    if (errorMessage)
        errorMessage->clear();

    return true;
}

void TerminalManager::executePtyChild(
    const PtyLaunchPlan &plan)
{
#ifdef Q_OS_LINUX
    ::umask(
        static_cast<mode_t>(0077));

    resetChildSignal(SIGPIPE);
    resetChildSignal(SIGINT);
    resetChildSignal(SIGTERM);
    resetChildSignal(SIGHUP);
    resetChildSignal(SIGQUIT);
    resetChildSignal(SIGCHLD);

    sigset_t emptySignalMask;
    ::sigemptyset(&emptySignalMask);
    ::sigprocmask(
        SIG_SETMASK,
        &emptySignalMask,
        nullptr);

    if (!plan.valid)
        ::_exit(126);

    if (plan.developer) {
        if (::setgroups(0, nullptr) != 0 ||
                ::setgid(0) != 0 ||
                ::setuid(0) != 0) {
            ::_exit(126);
        }
    } else if (plan.dropPrivileges) {
        gid_t groups[
            MaximumSupplementaryGroups];

        const int groupCount =
            std::min(
                static_cast<int>(
                    plan.supplementaryGroups.size()),
                MaximumSupplementaryGroups);

        for (int index = 0;
                index < groupCount;
                ++index) {
            groups[index] =
                static_cast<gid_t>(
                    plan.supplementaryGroups
                        .at(index));
        }

        if (::setgroups(
                static_cast<std::size_t>(
                    groupCount),
                groupCount > 0
                ? groups
                : nullptr) != 0) {
            ::_exit(126);
        }

        if (::setgid(
                static_cast<gid_t>(
                    plan.gid)) != 0) {
            ::_exit(126);
        }

        if (::setuid(
                static_cast<uid_t>(
                    plan.uid)) != 0) {
            ::_exit(126);
        }

        if (::geteuid() !=
                static_cast<uid_t>(
                    plan.uid) ||
                ::getegid() !=
                static_cast<gid_t>(
                    plan.gid)) {
            ::_exit(126);
        }
    }

    if (::chdir(
            plan.workingDirectory
                .constData()) != 0) {
        ::_exit(126);
    }

    char homeEnvironment[PATH_MAX + 16];
    char userEnvironment[256];
    char logNameEnvironment[256];
    char shellEnvironment[PATH_MAX + 16];
    char termEnvironment[128];
    char colorTermEnvironment[128];
    char modeEnvironment[128];
    char developerEnvironment[64];
    char workingDirectoryEnvironment[PATH_MAX + 16];

    childCopyBytes(
        homeEnvironment,
        sizeof(homeEnvironment),
        "HOME=",
        plan.home);

    childCopyBytes(
        userEnvironment,
        sizeof(userEnvironment),
        "USER=",
        plan.user);

    childCopyBytes(
        logNameEnvironment,
        sizeof(logNameEnvironment),
        "LOGNAME=",
        plan.logName);

    childCopyBytes(
        shellEnvironment,
        sizeof(shellEnvironment),
        "SHELL=",
        plan.shellPath);

    childCopyBytes(
        termEnvironment,
        sizeof(termEnvironment),
        "TERM=",
        plan.term);

    childCopyBytes(
        colorTermEnvironment,
        sizeof(colorTermEnvironment),
        "COLORTERM=",
        plan.colorTerm);

    childCopyBytes(
        modeEnvironment,
        sizeof(modeEnvironment),
        "NEUTRONOS_TERMINAL_MODE=",
        plan.terminalMode);

    childCopyBytes(
        developerEnvironment,
        sizeof(developerEnvironment),
        "NEUTRONOS_DEVELOPER_MODE=",
        plan.developerMode);

    childCopyBytes(
        workingDirectoryEnvironment,
        sizeof(workingDirectoryEnvironment),
        "PWD=",
        plan.workingDirectory);

    char pathEnvironment[] =
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";

    char terminalEnvironment[] =
        "NEUTRONOS_TERMINAL=1";

    char languageEnvironment[] =
        "LANG=C.UTF-8";

    char localeEnvironment[] =
        "LC_ALL=C.UTF-8";

    char *environment[] = {
        homeEnvironment,
        userEnvironment,
        logNameEnvironment,
        shellEnvironment,
        termEnvironment,
        colorTermEnvironment,
        modeEnvironment,
        developerEnvironment,
        workingDirectoryEnvironment,
        pathEnvironment,
        terminalEnvironment,
        languageEnvironment,
        localeEnvironment,
        nullptr
    };

    char *arguments[] = {
        const_cast<char *>(
            plan.argumentZero
                .constData()),
        nullptr
    };

    /*
        Keep the post-fork path deterministic and avoid querying process-wide
        runtime state before exec. NeutronShell marks its own descriptors
        close-on-exec; this bounded close pass removes ordinary inherited
        descriptors that remain.
    */
    constexpr int maximumDescriptor = 4096;

    for (int descriptor = 3;
            descriptor < maximumDescriptor;
            ++descriptor) {
        ::close(descriptor);
    }

    ::execve(
        plan.shellPath.constData(),
        arguments,
        environment);

    ::_exit(127);
#else
    Q_UNUSED(plan)
#endif
}

bool TerminalManager::startPty()
{
    if (m_ptyAlive &&
            m_masterFd >= 0 &&
            m_childPid > 0) {
        return true;
    }

    if (m_ptyShutdownPhase !=
            PtyShutdownPhase::Idle) {
        m_restartAfterPtyExit = true;
        return false;
    }

    closePtyDescriptors();

    PtyLaunchPlan plan;
    QString errorMessage;

    if (!buildPtyLaunchPlan(
            &plan,
            &errorMessage)) {
        setError(errorMessage);
        setPtyAlive(false);
        return false;
    }

    struct winsize size;
    std::memset(
        &size,
        0,
        sizeof(size));

    size.ws_col =
        static_cast<unsigned short>(
            m_columns);

    size.ws_row =
        static_cast<unsigned short>(
            m_rows);

    int masterDescriptor = -1;

    const pid_t child =
        ::forkpty(
            &masterDescriptor,
            nullptr,
            nullptr,
            &size);

    if (child < 0) {
        setError(
            QStringLiteral(
                "Unable to start terminal PTY: %1")
                .arg(
                    QString::fromLocal8Bit(
                        std::strerror(errno))));

        setPtyAlive(false);
        return false;
    }

    if (child == 0)
        executePtyChild(plan);

    m_masterFd =
        masterDescriptor;

    m_childPid =
        static_cast<qint64>(
            child);

    m_expectedPtyExit = false;
    m_restartAfterPtyExit = false;
    m_ptyShutdownPhase =
        PtyShutdownPhase::Idle;

    const int fileStatusFlags =
        ::fcntl(
            m_masterFd,
            F_GETFL,
            0);

    if (fileStatusFlags >= 0) {
        ::fcntl(
            m_masterFd,
            F_SETFL,
            fileStatusFlags |
            O_NONBLOCK);
    }

    const int descriptorFlags =
        ::fcntl(
            m_masterFd,
            F_GETFD,
            0);

    if (descriptorFlags >= 0) {
        ::fcntl(
            m_masterFd,
            F_SETFD,
            descriptorFlags |
            FD_CLOEXEC);
    }

    m_ptyReadNotifier =
        new QSocketNotifier(
            m_masterFd,
            QSocketNotifier::Read,
            this);

    m_ptyWriteNotifier =
        new QSocketNotifier(
            m_masterFd,
            QSocketNotifier::Write,
            this);

    m_ptyWriteNotifier->setEnabled(false);

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    connect(
        m_ptyReadNotifier,
        &QSocketNotifier::activated,
        this,
        [this](
            QSocketDescriptor,
            QSocketNotifier::Type) {
            readPtyOutput();
        });

    connect(
        m_ptyWriteNotifier,
        &QSocketNotifier::activated,
        this,
        [this](
            QSocketDescriptor,
            QSocketNotifier::Type) {
            flushPtyWriteQueue();
        });
#else
    connect(
        m_ptyReadNotifier,
        QOverload<int>::of(
            &QSocketNotifier::activated),
        this,
        [this](int) {
            readPtyOutput();
        });

    connect(
        m_ptyWriteNotifier,
        QOverload<int>::of(
            &QSocketNotifier::activated),
        this,
        [this](int) {
            flushPtyWriteQueue();
        });
#endif

    m_pendingPtyWrite.clear();
    m_utf8Carry.clear();

    if (!m_childReapTimer.isActive())
        m_childReapTimer.start();

    setPtyAlive(true);
    setError(QString());

    appendOutput(
        shellBanner());

#ifdef Q_OS_LINUX
    if (developerMode() && !plan.developer) {
        setStatusText(
            QStringLiteral(
                "Developer Mode active · local-user shell"));
    } else
#endif
    {
        setStatusText(
            QStringLiteral(
                "%1 shell active")
                .arg(modeLabel()));
    }

    audit(
        QStringLiteral("pty_started"),
        {
            {
                QStringLiteral("mode"),
                m_mode
            },
            {
                QStringLiteral("user"),
                QString::fromLocal8Bit(
                    plan.user)
            },
            {
                QStringLiteral("shell"),
                QString::fromLocal8Bit(
                    plan.shellPath)
            }
        });

    emit terminalEvent(
        QStringLiteral("pty_started"),
        publicWebStatusPayload());

    return true;
}

void TerminalManager::stopPty()
{
    m_restartAfterPtyExit = false;
    m_expectedPtyExit = true;
    requestPtyShutdown();
}

void TerminalManager::requestPtyShutdown()
{
    if (m_childPid <= 0) {
        closePtyDescriptors();
        setPtyAlive(false);

        const bool restart =
            m_restartAfterPtyExit &&
            m_running;

        m_restartAfterPtyExit = false;
        m_expectedPtyExit = false;

        if (restart) {
            QTimer::singleShot(
                0,
                this,
                [this]() {
                    if (m_running)
                        startPty();
                });
        }

        return;
    }

    if (m_ptyShutdownPhase !=
            PtyShutdownPhase::Idle) {
        return;
    }

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    m_expectedPtyExit = true;

    m_ptyShutdownPhase =
        PtyShutdownPhase::HangupSent;

    m_ptyShutdownStartedMonotonicMs =
        m_monotonicClock.elapsed();

    sendSignalToPtyProcessGroup(SIGHUP);

    if (!m_ptyShutdownTimer.isActive())
        m_ptyShutdownTimer.start();

    if (!m_childReapTimer.isActive())
        m_childReapTimer.start();
}

void TerminalManager::sendSignalToPtyProcessGroup(
    int signalNumber)
{
    if (m_childPid <= 0)
        return;

    const pid_t child =
        static_cast<pid_t>(
            m_childPid);

    if (::kill(
            -child,
            signalNumber) != 0 &&
            errno != ESRCH) {
        ::kill(
            child,
            signalNumber);
    }
}

void TerminalManager::advancePtyShutdown()
{
    if (m_childPid <= 0) {
        m_ptyShutdownTimer.stop();
        return;
    }

    reapPtyChild();

    if (m_childPid <= 0)
        return;

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    const qint64 elapsed =
        m_monotonicClock.elapsed() -
        m_ptyShutdownStartedMonotonicMs;

    if (elapsed >= 1600 &&
            m_ptyShutdownPhase !=
                PtyShutdownPhase::KillSent) {
        sendSignalToPtyProcessGroup(SIGKILL);
        m_ptyShutdownPhase =
            PtyShutdownPhase::KillSent;
        return;
    }

    if (elapsed >= 600 &&
            m_ptyShutdownPhase ==
                PtyShutdownPhase::HangupSent) {
        sendSignalToPtyProcessGroup(SIGTERM);
        m_ptyShutdownPhase =
            PtyShutdownPhase::TerminateSent;
    }
}

void TerminalManager::reapPtyChild()
{
    if (m_childPid <= 0) {
        m_childReapTimer.stop();
        return;
    }

    int status = 0;

    const pid_t child =
        static_cast<pid_t>(
            m_childPid);

    const pid_t result =
        ::waitpid(
            child,
            &status,
            WNOHANG);

    if (result == 0)
        return;

    if (result == child) {
        finalizePtyExit(
            status,
            m_expectedPtyExit);
        return;
    }

    if (result < 0 &&
            errno == ECHILD) {
        finalizePtyExit(
            status,
            m_expectedPtyExit);
    }
}

void TerminalManager::finalizePtyExit(
    int waitStatus,
    bool expected)
{
    const qint64 exitedPid =
        m_childPid;

    const bool restart =
        m_restartAfterPtyExit &&
        m_running;

    m_childPid = -1;
    m_restartAfterPtyExit = false;
    m_expectedPtyExit = false;
    m_ptyShutdownPhase =
        PtyShutdownPhase::Idle;
    m_ptyShutdownStartedMonotonicMs = 0;

    m_childReapTimer.stop();
    m_ptyShutdownTimer.stop();

    closePtyDescriptors();
    setPtyAlive(false);

    QString exitDescription;

    if (WIFEXITED(waitStatus)) {
        exitDescription =
            QStringLiteral(
                "Shell exited with status %1")
                .arg(
                    WEXITSTATUS(
                        waitStatus));
    } else if (WIFSIGNALED(waitStatus)) {
        exitDescription =
            QStringLiteral(
                "Shell ended by signal %1")
                .arg(
                    WTERMSIG(
                        waitStatus));
    } else {
        exitDescription =
            QStringLiteral(
                "Shell session ended");
    }

    appendOutput(
        QStringLiteral(
            "\r\n[NeutronOS Terminal] %1.\r\n")
            .arg(exitDescription));

    if (expected)
        setStatusText(
            QStringLiteral(
                "Terminal shell stopped"));
    else
        setError(exitDescription);

    audit(
        QStringLiteral("pty_exited"),
        {
            {
                QStringLiteral("pid"),
                exitedPid
            },
            {
                QStringLiteral("expected"),
                expected
            },
            {
                QStringLiteral("description"),
                exitDescription
            }
        });

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.ptyExited")
            },
            {
                QStringLiteral("expected"),
                expected
            },
            {
                QStringLiteral("status"),
                publicWebStatusPayload()
            }
        });

    if (restart) {
        QTimer::singleShot(
            0,
            this,
            [this]() {
                if (m_running)
                    startPty();
            });
    }
}

void TerminalManager::closePtyDescriptors()
{
    if (m_ptyReadNotifier) {
        m_ptyReadNotifier->setEnabled(false);
        m_ptyReadNotifier->deleteLater();
        m_ptyReadNotifier = nullptr;
    }

    if (m_ptyWriteNotifier) {
        m_ptyWriteNotifier->setEnabled(false);
        m_ptyWriteNotifier->deleteLater();
        m_ptyWriteNotifier = nullptr;
    }

    if (m_masterFd >= 0) {
        ::close(m_masterFd);
        m_masterFd = -1;
    }

    m_pendingPtyWrite.clear();
    m_utf8Carry.clear();
}

void TerminalManager::readPtyOutput()
{
    if (m_masterFd < 0)
        return;

    QByteArray collected;
    collected.reserve(32768);

    char buffer[8192];

    while (true) {
        const ssize_t bytesRead =
            ::read(
                m_masterFd,
                buffer,
                sizeof(buffer));

        if (bytesRead > 0) {
            collected.append(
                buffer,
                static_cast<int>(
                    bytesRead));

            if (collected.size() >=
                    32 * 1024) {
                break;
            }

            continue;
        }

        if (bytesRead < 0 &&
                errno == EINTR) {
            continue;
        }

        if (bytesRead < 0 &&
                (errno == EAGAIN ||
                 errno == EWOULDBLOCK)) {
            break;
        }

        if (bytesRead == 0 ||
                (bytesRead < 0 &&
                 errno == EIO)) {
            reapPtyChild();
            break;
        }

        if (bytesRead < 0) {
            setError(
                QStringLiteral(
                    "Terminal PTY read failed: %1")
                    .arg(
                        QString::fromLocal8Bit(
                            std::strerror(errno))));

            m_expectedPtyExit = false;
            requestPtyShutdown();
            break;
        }
    }

    if (!collected.isEmpty()) {
        const QString decoded =
            decodePtyBytes(
                collected);

        appendOutput(decoded);
    }
}

bool TerminalManager::queuePtyWrite(
    const QByteArray &data)
{
    if (data.isEmpty())
        return true;

    if (!m_ptyAlive ||
            m_masterFd < 0) {
        if (!startPty())
            return false;
    }

    if (data.size() >
            m_maxPendingPtyWriteBytes ||
            m_pendingPtyWrite.size() >
                m_maxPendingPtyWriteBytes -
                data.size()) {
        setError(
            QStringLiteral(
                "Terminal input queue limit reached"));
        return false;
    }

    m_pendingPtyWrite.append(data);
    flushPtyWriteQueue();
    updatePtyWriteNotifier();

    return true;
}

bool TerminalManager::writeToPty(
    const QByteArray &data)
{
    return queuePtyWrite(data);
}

void TerminalManager::flushPtyWriteQueue()
{
    if (m_masterFd < 0 ||
            m_pendingPtyWrite.isEmpty()) {
        updatePtyWriteNotifier();
        return;
    }

    while (!m_pendingPtyWrite.isEmpty()) {
        const ssize_t written =
            ::write(
                m_masterFd,
                m_pendingPtyWrite.constData(),
                static_cast<std::size_t>(
                    m_pendingPtyWrite.size()));

        if (written > 0) {
            m_pendingPtyWrite.remove(
                0,
                static_cast<int>(
                    written));

            continue;
        }

        if (written < 0 &&
                errno == EINTR) {
            continue;
        }

        if (written < 0 &&
                (errno == EAGAIN ||
                 errno == EWOULDBLOCK)) {
            break;
        }

        setError(
            QStringLiteral(
                "Terminal PTY write failed: %1")
                .arg(
                    QString::fromLocal8Bit(
                        std::strerror(errno))));

        m_pendingPtyWrite.clear();
        m_expectedPtyExit = false;
        requestPtyShutdown();
        break;
    }

    updatePtyWriteNotifier();
}

void TerminalManager::updatePtyWriteNotifier()
{
    if (!m_ptyWriteNotifier)
        return;

    m_ptyWriteNotifier->setEnabled(
        m_masterFd >= 0 &&
        !m_pendingPtyWrite.isEmpty());
}

QString TerminalManager::decodePtyBytes(
    const QByteArray &bytes)
{
    QByteArray combined =
        m_utf8Carry;

    combined.append(bytes);
    m_utf8Carry.clear();

    const int carryLength =
        incompleteUtf8SuffixLength(
            combined);

    if (carryLength > 0) {
        m_utf8Carry =
            combined.right(
                carryLength);

        combined.chop(
            carryLength);
    }

    return combined.isEmpty()
           ? QString()
           : QString::fromUtf8(
                 combined);
}

void TerminalManager::appendOutput(
    const QString &text)
{
    if (text.isEmpty())
        return;

    m_outputText.append(text);
    trimOutput();

    emit outputChanged();
    emit outputAppended(text);

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.output")
            },
            {
                QStringLiteral("data"),
                text
            }
        });
}

void TerminalManager::trimOutput()
{
    if (m_outputText.size() <=
            m_scrollbackLimit) {
        return;
    }

    const int excess =
        m_outputText.size() -
        m_scrollbackLimit;

    int cut =
        m_outputText.indexOf(
            QLatin1Char('\n'),
            excess);

    if (cut < 0)
        cut = excess;
    else
        ++cut;

    m_outputText.remove(
        0,
        cut);
}

QString TerminalManager::shellBanner() const
{
    // Keep the PTY visually clean. The real login shell is authoritative and
    // may provide its own colored prompt/MOTD; NeutronOS should not prepend a
    // second wall of developer/debug prose to every terminal session.
    return QString();
}

void TerminalManager::handleModeWatch()
{
    syncModeFromDeveloperManager(false);
}

void TerminalManager::updateArmedQuickActionState()
{
    if (m_armedQuickActionId.isEmpty()) {
        m_armedQuickActionTimer.stop();
        return;
    }

    if (!armedQuickActionValid(
            m_armedQuickActionId)) {
        clearArmedQuickAction();
        return;
    }

    emit armedQuickActionChanged();
}

void TerminalManager::setRunning(bool value)
{
    if (m_running == value)
        return;

    m_running = value;

    emit runningChanged();
    emit statusChanged();
}

void TerminalManager::setPtyAlive(bool value)
{
    if (m_ptyAlive == value)
        return;

    m_ptyAlive = value;

    emit ptyAliveChanged();
    emit statusChanged();
}

void TerminalManager::setMode(
    const QString &value)
{
    const QString normalized =
        value == QStringLiteral("developer")
        ? QStringLiteral("developer")
        : QStringLiteral("regular");

    if (m_mode == normalized)
        return;

    m_mode = normalized;

    emit modeChanged();
    emit statusChanged();
}

void TerminalManager::setStatusText(
    const QString &value)
{
    if (m_statusText == value)
        return;

    m_statusText = value;
    emit statusChanged();
}

void TerminalManager::setError(
    const QString &value)
{
    if (m_error == value)
        return;

    m_error = value;

    emit errorChanged();
    emit statusChanged();
}

QString TerminalManager::normalizeKeyName(
    const QString &key) const
{
    QString normalized =
        key.trimmed().toLower();

    normalized.replace(
        QLatin1Char('_'),
        QLatin1Char('-'));

    return normalized;
}

QByteArray TerminalManager::keyToBytes(
    const QString &key) const
{
    const QString normalized =
        normalizeKeyName(key);

    if (normalized ==
            QStringLiteral("enter") ||
            normalized ==
            QStringLiteral("return")) {
        return QByteArray("\r", 1);
    }

    if (normalized ==
            QStringLiteral("tab")) {
        return QByteArray("\t", 1);
    }

    if (normalized ==
            QStringLiteral("backspace")) {
        return QByteArray(1, 0x7f);
    }

    if (normalized ==
            QStringLiteral("escape") ||
            normalized ==
            QStringLiteral("esc")) {
        return QByteArray("\x1b", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-a")) {
        return QByteArray("\x01", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-b")) {
        return QByteArray("\x02", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-c")) {
        return QByteArray("\x03", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-d")) {
        return QByteArray("\x04", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-e")) {
        return QByteArray("\x05", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-f")) {
        return QByteArray("\x06", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-k")) {
        return QByteArray("\x0b", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-l")) {
        return QByteArray("\x0c", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-n")) {
        return QByteArray("\x0e", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-p")) {
        return QByteArray("\x10", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-r")) {
        return QByteArray("\x12", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-u")) {
        return QByteArray("\x15", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-w")) {
        return QByteArray("\x17", 1);
    }

    if (normalized ==
            QStringLiteral("ctrl-z")) {
        return QByteArray("\x1a", 1);
    }

    if (normalized ==
            QStringLiteral("up")) {
        return QByteArray("\x1b[A", 3);
    }

    if (normalized ==
            QStringLiteral("down")) {
        return QByteArray("\x1b[B", 3);
    }

    if (normalized ==
            QStringLiteral("right")) {
        return QByteArray("\x1b[C", 3);
    }

    if (normalized ==
            QStringLiteral("left")) {
        return QByteArray("\x1b[D", 3);
    }

    if (normalized ==
            QStringLiteral("home")) {
        return QByteArray("\x1b[H", 3);
    }

    if (normalized ==
            QStringLiteral("end")) {
        return QByteArray("\x1b[F", 3);
    }

    if (normalized ==
            QStringLiteral("insert")) {
        return QByteArray("\x1b[2~", 4);
    }

    if (normalized ==
            QStringLiteral("delete")) {
        return QByteArray("\x1b[3~", 4);
    }

    if (normalized ==
            QStringLiteral("pageup") ||
            normalized ==
            QStringLiteral("page-up")) {
        return QByteArray("\x1b[5~", 4);
    }

    if (normalized ==
            QStringLiteral("pagedown") ||
            normalized ==
            QStringLiteral("page-down")) {
        return QByteArray("\x1b[6~", 4);
    }

    if (normalized ==
            QStringLiteral("f1")) {
        return QByteArray("\x1bOP", 3);
    }

    if (normalized ==
            QStringLiteral("f2")) {
        return QByteArray("\x1bOQ", 3);
    }

    if (normalized ==
            QStringLiteral("f3")) {
        return QByteArray("\x1bOR", 3);
    }

    if (normalized ==
            QStringLiteral("f4")) {
        return QByteArray("\x1bOS", 3);
    }

    return QByteArray();
}

TerminalManager::QuickCommand *
TerminalManager::findQuickCommand(
    const QString &id)
{
    for (QuickCommand &command :
            m_quickCommands) {
        if (command.id == id)
            return &command;
    }

    return nullptr;
}

const TerminalManager::QuickCommand *
TerminalManager::findQuickCommand(
    const QString &id) const
{
    for (const QuickCommand &command :
            m_quickCommands) {
        if (command.id == id)
            return &command;
    }

    return nullptr;
}

QVariantMap TerminalManager::quickCommandToVariant(
    const QuickCommand &command) const
{
    QVariantMap result;

    result.insert(
        QStringLiteral("id"),
        command.id);

    result.insert(
        QStringLiteral("label"),
        command.label);

    result.insert(
        QStringLiteral("group"),
        command.group);

    result.insert(
        QStringLiteral("icon"),
        command.icon);

    result.insert(
        QStringLiteral("command"),
        command.command);

    result.insert(
        QStringLiteral("enter"),
        command.enter);

    result.insert(
        QStringLiteral("requiresArmed"),
        command.requiresArmed ||
        commandLooksDangerous(
            command.command));

    result.insert(
        QStringLiteral("developerOnly"),
        command.developerOnly);

    result.insert(
        QStringLiteral("rootRequired"),
        command.rootRequired);

    result.insert(
        QStringLiteral("enabled"),
        command.enabled &&
        (!(command.developerOnly ||
           command.rootRequired) ||
         developerMode()));

    result.insert(
        QStringLiteral("armed"),
        armedQuickActionValid(
            command.id));

    result.insert(
        QStringLiteral(
            "armedSecondsRemaining"),
        armedQuickActionValid(
            command.id)
        ? armedQuickActionSecondsRemaining()
        : 0);

    return result;
}

QVariantMap TerminalManager::quickCommandResult(
    bool ok,
    const QString &id,
    const QString &message) const
{
    QVariantMap result;

    result.insert(
        QStringLiteral("ok"),
        ok);

    result.insert(
        QStringLiteral("id"),
        id);

    result.insert(
        QStringLiteral("message"),
        message);

    result.insert(
        QStringLiteral("error"),
        ok ? QString() : message);

    result.insert(
        QStringLiteral("mode"),
        m_mode);

    result.insert(
        QStringLiteral("developerMode"),
        developerMode());

    return result;
}

bool TerminalManager::commandLooksDangerous(
    const QString &command) const
{
    const QString lower =
        command.toLower();

    static const QStringList patterns = {
        QStringLiteral(
            "(^|[;&|]\\s*)rm\\s+[^\\n]*(-[a-z]*r[a-z]*f|-rf|-fr)"),
        QStringLiteral("\\bmkfs(\\.|\\s)"),
        QStringLiteral("(^|[;&|]\\s*)dd\\s+"),
        QStringLiteral("\\b(shutdown|reboot|poweroff|halt)\\b"),
        QStringLiteral("\\bsystemctl\\s+(reboot|poweroff|halt|rescue|emergency)\\b"),
        QStringLiteral("\\bdocker\\s+(rm|kill|stop|restart|prune)\\b"),
        QStringLiteral("\\bpodman\\s+(rm|kill|stop|restart|prune)\\b"),
        QStringLiteral("\\bkill\\s+(-9|-KILL)\\b"),
        QStringLiteral("\\bpkill\\b"),
        QStringLiteral("\\bkillall\\b"),
        QStringLiteral("\\b(chmod|chown)\\s+[^\\n]*-[a-z]*r\\b"),
        QStringLiteral("\\bmount\\s+"),
        QStringLiteral("\\bumount\\s+"),
        QStringLiteral("\\bparted\\b"),
        QStringLiteral("\\bfdisk\\b"),
        QStringLiteral("\\bsfdisk\\b"),
        QStringLiteral("\\bwipefs\\b"),
        QStringLiteral("\\bapt(-get)?\\s+(remove|purge|dist-upgrade|full-upgrade)\\b"),
        QStringLiteral("\\bdnf\\s+(remove|erase|upgrade)\\b"),
        QStringLiteral("\\bpacman\\s+-R"),
        QStringLiteral(">\\s*/dev/(sd|mmcblk|nvme)"),
        QStringLiteral("\\btruncate\\s+[^\\n]*\\s+/"),
        QStringLiteral("\\buser(del|mod|add)\\b"),
        QStringLiteral("\\bgroup(del|mod|add)\\b")
    };

    for (const QString &pattern : patterns) {
        const QRegularExpression expression(
            pattern,
            QRegularExpression::
                CaseInsensitiveOption);

        if (expression.match(lower).hasMatch())
            return true;
    }

    return false;
}

bool TerminalManager::quickCommandAllowed(
    const QuickCommand &command,
    bool callerArmedHint,
    const QString &source,
    QString *message) const
{
    Q_UNUSED(callerArmedHint)

    if (!command.enabled) {
        if (message) {
            *message =
                QStringLiteral(
                    "This quick action is disabled");
        }

        return false;
    }

    if ((command.developerOnly ||
         command.rootRequired) &&
            !developerMode()) {
        if (message) {
            *message =
                QStringLiteral(
                    "This quick action requires Console Developer Mode");
        }

        return false;
    }

    const bool requiresArmed =
        command.requiresArmed ||
        commandLooksDangerous(
            command.command);

    if (requiresArmed &&
            source.startsWith(
                QStringLiteral("web"),
                Qt::CaseInsensitive)) {
        if (message) {
            *message =
                QStringLiteral(
                    "Destructive quick actions must be confirmed on the local display");
        }

        return false;
    }

    if (requiresArmed &&
            !armedQuickActionValid(
                command.id)) {
        if (message) {
            *message =
                QStringLiteral(
                    "This quick action requires an active local armed confirmation");
        }

        return false;
    }

    if (message)
        *message = QStringLiteral("OK");

    return true;
}

bool TerminalManager::armedQuickActionValid(
    const QString &id) const
{
    if (id.isEmpty() ||
            id != m_armedQuickActionId ||
            !m_monotonicClock.isValid()) {
        return false;
    }

    return m_monotonicClock.elapsed() <
           m_armedQuickActionUntilMonotonicMs;
}

QString TerminalManager::sanitizeDraft(
    const QString &text) const
{
    QString result =
        text.left(
            m_maxDraftChars);

    result.remove(QChar(0));

    return result;
}

QString TerminalManager::sanitizePaste(
    const QString &text,
    bool *truncated) const
{
    if (truncated) {
        *truncated =
            text.size() >
            m_maxPasteChars;
    }

    QString result =
        text.left(
            m_maxPasteChars);

    result.remove(QChar(0));

    return result;
}

QString TerminalManager::sanitizeSource(
    const QString &source) const
{
    QString result =
        source.trimmed()
            .left(96);

    result.remove(
        QRegularExpression(
            QStringLiteral(
                "[^A-Za-z0-9_.:-]")));

    return result.isEmpty()
           ? QStringLiteral("unknown")
           : result;
}

void TerminalManager::updateClipboard(
    const QString &text,
    const QString &source)
{
    if (m_clipboardText == text)
        return;

    m_clipboardText = text;

    emit clipboardChanged(
        m_clipboardText,
        source);

    emit statusChanged();

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.clipboardChanged")
            },
            {
                QStringLiteral("clipboard"),
                makeClipboardPayload(
                    source)
            }
        });
}

void TerminalManager::updateSelection(
    const QString &text,
    const QString &source)
{
    if (m_selectionText == text)
        return;

    m_selectionText = text;

    emit selectionChanged(
        m_selectionText,
        source);

    emit statusChanged();

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.selectionChanged")
            },
            {
                QStringLiteral("selection"),
                makeSelectionPayload(
                    source)
            }
        });
}

void TerminalManager::updateDraft(
    const QString &text,
    const QString &source)
{
    if (m_inputDraft == text)
        return;

    m_inputDraft = text;

    emit inputDraftChanged(
        m_inputDraft,
        source);

    emit statusChanged();

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.draftChanged")
            },
            {
                QStringLiteral("inputDraft"),
                makeDraftPayload(
                    source)
            }
        });
}


QString TerminalManager::generateWebToken() const
{
    const quint32 code =
        QRandomGenerator::system()->bounded(100000000U);

    const QString digits =
        QStringLiteral("%1")
            .arg(code, 8, 10, QLatin1Char('0'));

    return digits.left(4) +
           QLatin1Char('-') +
           digits.mid(4);
}

bool TerminalManager::tokenMatches(
    const QString &candidate) const
{
    if (!webPairingCodeActive())
        return false;

    QString normalizedCandidate =
        candidate.trimmed();
    QString normalizedExpected =
        m_webToken;

    normalizedCandidate.remove(
        QLatin1Char('-'));
    normalizedExpected.remove(
        QLatin1Char('-'));

    static const QRegularExpression codePattern(
        QStringLiteral("^[0-9]{8}$"));

    if (!codePattern
            .match(normalizedCandidate)
            .hasMatch()) {
        return false;
    }

    const QByteArray candidateDigest =
        QCryptographicHash::hash(
            normalizedCandidate.toLatin1(),
            QCryptographicHash::Sha256);

    const QByteArray expectedDigest =
        QCryptographicHash::hash(
            normalizedExpected.toLatin1(),
            QCryptographicHash::Sha256);

    return constantTimeEquals(
        candidateDigest,
        expectedDigest);
}

QString TerminalManager::localIpHint() const
{
    const QList<QNetworkInterface> interfaces =
        QNetworkInterface::allInterfaces();

    for (const QNetworkInterface &interface :
            interfaces) {
        if (!(interface.flags() &
              QNetworkInterface::IsUp) ||
                !(interface.flags() &
                  QNetworkInterface::IsRunning) ||
                (interface.flags() &
                 QNetworkInterface::IsLoopBack)) {
            continue;
        }

        for (const QNetworkAddressEntry &entry :
                interface.addressEntries()) {
            const QHostAddress address =
                entry.ip();

            if (address.protocol() ==
                    QAbstractSocket::
                        IPv4Protocol &&
                    privateOrLocalAddress(
                        address) &&
                    !address.isLoopback()) {
                return address.toString();
            }
        }
    }

    return QStringLiteral(
        "127.0.0.1");
}

bool TerminalManager::selectWebBindAddress(
    QString *address,
    QString *errorMessage) const
{
    if (!address)
        return false;

    if (m_webMirrorLanAccessEnabled) {
        *address =
            QHostAddress(
                QHostAddress::AnyIPv4)
                .toString();
    } else {
        *address =
            QHostAddress(
                QHostAddress::LocalHost)
                .toString();
    }

    if (address->isEmpty()) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Unable to resolve terminal web bind address");
        }

        return false;
    }

    if (errorMessage)
        errorMessage->clear();

    return true;
}

void TerminalManager::revokeWebAuthenticationState()
{
    disconnectWebClients();

    audit(
        QStringLiteral(
            "web_sessions_revoked"));
}

void TerminalManager::handleNewWebConnection()
{
    while (m_webServer &&
            m_webServer
                ->hasPendingConnections()) {
        QTcpSocket *socket =
            m_webServer
                ->nextPendingConnection();

        if (!socket)
            continue;

        if (m_webMirrorLanAccessEnabled &&
                !privateOrLocalAddress(
                    socket->peerAddress())) {
            socket->write(
                buildHttpResponse(
                    QByteArrayLiteral(
                        "{\"ok\":false,\"error\":\"LAN clients only\"}"),
                    QByteArrayLiteral(
                        "application/json"),
                    403,
                    QByteArrayLiteral(
                        "Forbidden")));

            socket->disconnectFromHost();
            socket->deleteLater();
            continue;
        }

        if (m_webClients.size() >=
                m_maxWebClients) {
            socket->write(
                buildHttpResponse(
                    QByteArrayLiteral(
                        "{\"ok\":false,\"error\":\"Too many clients\"}"),
                    QByteArrayLiteral(
                        "application/json"),
                    503,
                    QByteArrayLiteral(
                        "Service Unavailable")));

            socket->disconnectFromHost();
            socket->deleteLater();
            continue;
        }

        socket->setReadBufferSize(
            static_cast<qint64>(
                m_maxWebFrameBytes +
                m_maxHttpHeaderBytes +
                m_maxHttpBodyBytes));

        WebClient client;

        client.socket = socket;

        client.id =
            QStringLiteral("web-%1")
                .arg(
                    generateWebToken()
                        .left(10));

        client.name =
            client.id;

        client.sourceAddress =
            socket->peerAddress()
                .toString();

        client.connectedAtMonotonicMs =
            m_monotonicClock.elapsed();

        client.lastActivityMonotonicMs =
            client.connectedAtMonotonicMs;

        client.rateWindowStartedMonotonicMs =
            client.connectedAtMonotonicMs;

        client.connectedAtUtc =
            QDateTime::currentDateTimeUtc();

        m_webClients.insert(
            socket,
            client);

        connect(
            socket,
            &QTcpSocket::readyRead,
            this,
            [this, socket]() {
                handleWebReadyRead(socket);
            });

        connect(
            socket,
            &QTcpSocket::disconnected,
            this,
            [this, socket]() {
                removeWebClient(
                    socket,
                    QStringLiteral(
                        "Disconnected"));
            });

#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
        connect(
            socket,
            &QTcpSocket::errorOccurred,
            this,
            [this, socket](
                QAbstractSocket::SocketError) {
                if (socket &&
                        socket->state() ==
                            QAbstractSocket::
                                UnconnectedState) {
                    removeWebClient(
                        socket,
                        QStringLiteral(
                            "Socket error"));
                }
            });
#else
        connect(
            socket,
            QOverload<
                QAbstractSocket::SocketError
            >::of(
                &QTcpSocket::error),
            this,
            [this, socket](
                QAbstractSocket::SocketError) {
                if (socket &&
                        socket->state() ==
                            QAbstractSocket::
                                UnconnectedState) {
                    removeWebClient(
                        socket,
                        QStringLiteral(
                            "Socket error"));
                }
            });
#endif

        emit webClientCountChanged();
        emit statusChanged();

        audit(
            QStringLiteral(
                "web_client_connected"),
            {
                {
                    QStringLiteral("clientId"),
                    client.id
                },
                {
                    QStringLiteral("address"),
                    client.sourceAddress
                }
            });
    }
}

void TerminalManager::removeWebClient(
    QTcpSocket *socket,
    const QString &reason)
{
    if (!socket)
        return;

    auto iterator =
        m_webClients.find(socket);

    if (iterator ==
            m_webClients.end()) {
        socket->deleteLater();
        return;
    }

    const WebClient client =
        iterator.value();

    m_webClients.erase(iterator);

    socket->disconnect(this);
    socket->deleteLater();

    emit webClientCountChanged();
    emit statusChanged();

    audit(
        QStringLiteral(
            "web_client_removed"),
        {
            {
                QStringLiteral("clientId"),
                client.id
            },
            {
                QStringLiteral("authenticated"),
                client.authenticated
            },
            {
                QStringLiteral("reason"),
                reason
            }
        });

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.webClientCountChanged")
            },
            {
                QStringLiteral("count"),
                authenticatedWebClientCount()
            }
        });
}

void TerminalManager::disconnectWebClient(
    QTcpSocket *socket,
    quint16 closeCode,
    const QString &reason)
{
    if (!socket)
        return;

    auto iterator =
        m_webClients.find(socket);

    if (iterator ==
            m_webClients.end()) {
        socket->abort();
        socket->deleteLater();
        return;
    }

    WebClient &client =
        iterator.value();

    const bool wasAuthenticated =
        client.authenticated;

    client.authenticated = false;

    if (wasAuthenticated) {
        emit webClientCountChanged();
        emit statusChanged();
    }

    if (client.handshakeComplete &&
            !client.closeSent &&
            socket->state() ==
                QAbstractSocket::
                    ConnectedState) {
        QByteArray payload;

        payload.append(
            static_cast<char>(
                (closeCode >> 8) &
                0xFF));

        payload.append(
            static_cast<char>(
                closeCode &
                0xFF));

        payload.append(
            reason.toUtf8()
                .left(120));

        socket->write(
            encodeWebSocketControlFrame(
                0x8,
                payload));

        socket->flush();
        client.closeSent = true;
    }

    socket->disconnectFromHost();

    QPointer<QTcpSocket> guard(socket);

    QTimer::singleShot(
        250,
        this,
        [guard]() {
            if (guard &&
                    guard->state() !=
                        QAbstractSocket::
                            UnconnectedState) {
                guard->abort();
            }
        });
}

bool TerminalManager::webClientMaySend(
    WebClient *client,
    int inputCharacters,
    QString *errorMessage)
{
    if (!client ||
            !client->authenticated) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Web terminal client is not authenticated");
        }

        return false;
    }

    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    const qint64 now =
        m_monotonicClock.elapsed();

    if (now -
            client
                ->rateWindowStartedMonotonicMs >=
            m_rateWindowMs) {
        client->rateWindowStartedMonotonicMs =
            now;

        client->messagesInWindow = 0;
        client->inputCharactersInWindow = 0;
    }

    ++client->messagesInWindow;

    client->inputCharactersInWindow +=
        qMax(
            0,
            inputCharacters);

    client->lastActivityMonotonicMs =
        now;

    if (client->messagesInWindow >
            m_maxMessagesPerRateWindow) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Web terminal message rate exceeded");
        }

        return false;
    }

    if (client->inputCharactersInWindow >
            m_maxInputCharactersPerRateWindow) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Web terminal input rate exceeded");
        }

        return false;
    }

    if (errorMessage)
        errorMessage->clear();

    return true;
}

void TerminalManager::sweepWebClients()
{
    if (!m_monotonicClock.isValid())
        m_monotonicClock.start();

    const qint64 now =
        m_monotonicClock.elapsed();

    if (!m_webToken.isEmpty()) {
        if (m_webTokenExpiresMonotonicMs <= now) {
            m_webToken.clear();
            m_webTokenExpiresMonotonicMs = 0;

            emit webTokenChanged();
            emit webPairingCodeChanged();
            emit statusChanged();

            audit(
                QStringLiteral(
                    "web_pairing_code_expired"));
        } else {
            /* Refresh the visible 60-second countdown once per sweep. */
            emit webPairingCodeChanged();
        }
    }

    const QList<QTcpSocket *> sockets =
        m_webClients.keys();

    for (QTcpSocket *socket : sockets) {
        auto iterator =
            m_webClients.find(socket);

        if (iterator ==
                m_webClients.end()) {
            continue;
        }

        const WebClient &client =
            iterator.value();

        if (!client.handshakeComplete &&
                now -
                    client
                        .connectedAtMonotonicMs >
                    m_webHandshakeTimeoutMs) {
            disconnectWebClient(
                socket,
                1008,
                QStringLiteral(
                    "Handshake timeout"));

            continue;
        }

        if (client.handshakeComplete &&
                now -
                    client
                        .lastActivityMonotonicMs >
                    m_webIdleTimeoutMs) {
            disconnectWebClient(
                socket,
                1001,
                QStringLiteral(
                    "Idle timeout"));
        }
    }
}

void TerminalManager::broadcastWebJson(
    const QVariantMap &message)
{
    const QList<QTcpSocket *> sockets =
        m_webClients.keys();

    for (QTcpSocket *socket : sockets) {
        const auto iterator =
            m_webClients.constFind(socket);

        if (iterator ==
                m_webClients.constEnd() ||
                !iterator.value()
                    .handshakeComplete ||
                !iterator.value()
                    .authenticated) {
            continue;
        }

        sendWebJson(
            socket,
            message);
    }
}

void TerminalManager::sendWebJson(
    QTcpSocket *socket,
    const QVariantMap &message)
{
    if (!socket ||
            socket->state() !=
                QAbstractSocket::
                    ConnectedState) {
        return;
    }

    const auto iterator =
        m_webClients.constFind(socket);

    if (iterator ==
            m_webClients.constEnd() ||
            !iterator.value()
                .handshakeComplete ||
            !iterator.value()
                .authenticated) {
        return;
    }

    if (socket->bytesToWrite() >
            static_cast<qint64>(
                m_maxWebFrameBytes) *
                2) {
        disconnectWebClient(
            socket,
            1011,
            QStringLiteral(
                "Web client is not consuming output"));
        return;
    }

    const QByteArray payload =
        mapToCompactJson(message);

    if (payload.size() >
            m_maxWebMessageBytes) {
        disconnectWebClient(
            socket,
            1009,
            QStringLiteral(
                "Outbound message too large"));
        return;
    }

    socket->write(
        encodeWebSocketTextFrame(
            payload));
}

void TerminalManager::sendWebHello(
    QTcpSocket *socket)
{
    QVariantList publicCommands;

    for (const QuickCommand &command :
            m_quickCommands) {
        QVariantMap item =
            quickCommandToVariant(
                command);

        item.remove(
            QStringLiteral("command"));

        publicCommands.append(item);
    }

    QString history =
        m_outputText;

    QVariantMap clipboard =
        makeClipboardPayload(
            QStringLiteral("system"));

    QVariantMap selection =
        makeSelectionPayload(
            QStringLiteral("system"));

    QVariantMap hello;

    auto rebuildHello =
        [&]() {
            hello.clear();

            hello.insert(
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.hello"));

            hello.insert(
                QStringLiteral("status"),
                publicWebStatusPayload());

            hello.insert(
                QStringLiteral("history"),
                history);

            hello.insert(
                QStringLiteral("inputDraft"),
                makeDraftPayload(
                    QStringLiteral("system")));

            hello.insert(
                QStringLiteral("clipboard"),
                clipboard);

            hello.insert(
                QStringLiteral("selection"),
                selection);

            hello.insert(
                QStringLiteral("quickCommands"),
                publicCommands);

            if (m_assistManager) {
                hello.insert(
                    QStringLiteral("snippets"),
                    m_assistManager->snippets());

                hello.insert(
                    QStringLiteral("correctionSuggestion"),
                    m_assistManager->correctionSuggestion());

                hello.insert(
                    QStringLiteral("smartCorrectionEnabled"),
                    m_assistManager->smartCorrectionEnabled());
            }
        };

    rebuildHello();

    QByteArray encoded =
        mapToCompactJson(hello);

    while (encoded.size() >
               m_maxWebMessageBytes &&
           history.size() > 4096) {
        history =
            history.right(
                history.size() /
                2);

        rebuildHello();

        encoded =
            mapToCompactJson(
                hello);
    }

    if (encoded.size() >
            m_maxWebMessageBytes) {
        clipboard.insert(
            QStringLiteral("text"),
            QString());

        clipboard.insert(
            QStringLiteral("truncated"),
            true);

        selection.insert(
            QStringLiteral("text"),
            QString());

        selection.insert(
            QStringLiteral("truncated"),
            true);

        rebuildHello();

        encoded =
            mapToCompactJson(
                hello);
    }

    if (encoded.size() >
            m_maxWebMessageBytes) {
        history =
            history.right(1024);

        publicCommands.clear();

        rebuildHello();
    }

    sendWebJson(
        socket,
        hello);
}

void TerminalManager::handleWebReadyRead(
    QTcpSocket *socket)
{
    if (!socket)
        return;

    auto iterator =
        m_webClients.find(socket);

    if (iterator ==
            m_webClients.end()) {
        return;
    }

    WebClient &client =
        iterator.value();

    client.rawBuffer.append(
        socket->readAll());

    client.lastActivityMonotonicMs =
        m_monotonicClock.elapsed();

    if (client.handshakeComplete) {
        if (client.rawBuffer.size() >
                m_maxWebFrameBytes +
                14) {
            disconnectWebClient(
                socket,
                1009,
                QStringLiteral(
                    "WebSocket buffer too large"));
            return;
        }

        handleWebSocketFrames(socket);
        return;
    }

    if (client.rawBuffer.size() >
            m_maxHttpHeaderBytes +
            m_maxHttpBodyBytes +
            m_maxWebFrameBytes) {
        socket->write(
            buildHttpResponse(
                QByteArrayLiteral(
                    "{\"ok\":false,\"error\":\"Request too large\"}"),
                QByteArrayLiteral(
                    "application/json"),
                413,
                QByteArrayLiteral(
                    "Payload Too Large")));

        socket->disconnectFromHost();
        return;
    }

    HttpRequest request;
    QString parseError;

    if (!parseHttpRequest(
            &client,
            &request,
            &parseError)) {
        socket->write(
            buildHttpResponse(
                mapToCompactJson(
                    {
                        {
                            QStringLiteral("ok"),
                            false
                        },
                        {
                            QStringLiteral("error"),
                            parseError
                        }
                    }),
                QByteArrayLiteral(
                    "application/json"),
                400,
                QByteArrayLiteral(
                    "Bad Request")));

        socket->disconnectFromHost();
        return;
    }

    if (!request.complete)
        return;

    client.rawBuffer.remove(
        0,
        request.consumedBytes);

    handleHttpRequest(
        socket,
        request);

    if (client.handshakeComplete &&
            !client.rawBuffer.isEmpty()) {
        handleWebSocketFrames(socket);
    }
}

bool TerminalManager::parseHttpRequest(
    WebClient *client,
    HttpRequest *request,
    QString *errorMessage) const
{
    if (!client ||
            !request) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Invalid HTTP parser state");
        }

        return false;
    }

    *request = HttpRequest();

    const int headerEnd =
        client->rawBuffer.indexOf(
            QByteArrayLiteral(
                "\r\n\r\n"));

    if (headerEnd < 0) {
        if (client->rawBuffer.size() >
                m_maxHttpHeaderBytes) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "HTTP headers are too large");
            }

            return false;
        }

        request->valid = true;
        return true;
    }

    if (headerEnd >
            m_maxHttpHeaderBytes) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "HTTP headers are too large");
        }

        return false;
    }

    const QByteArray headerBlock =
        client->rawBuffer.left(
            headerEnd);

    QList<QByteArray> lines =
        headerBlock.split('\n');

    if (lines.isEmpty()) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Missing HTTP request line");
        }

        return false;
    }

    for (QByteArray &line : lines) {
        if (line.endsWith('\r'))
            line.chop(1);
    }

    const QList<QByteArray> requestParts =
        lines.takeFirst()
            .simplified()
            .split(' ');

    if (requestParts.size() != 3) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Malformed HTTP request line");
        }

        return false;
    }

    request->method =
        requestParts.at(0)
            .trimmed()
            .toUpper();

    request->target =
        requestParts.at(1)
            .trimmed();

    if (!request->target.startsWith('/')) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Only origin-form HTTP request targets are supported");
        }

        return false;
    }

    request->version =
        requestParts.at(2)
            .trimmed();

    if (request->version !=
            QByteArrayLiteral(
                "HTTP/1.1")) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Only HTTP/1.1 is supported");
        }

        return false;
    }

    bool contentLengthSeen = false;

    for (const QByteArray &rawLine : lines) {
        if (rawLine.isEmpty())
            continue;

        if (rawLine.startsWith(' ') ||
                rawLine.startsWith('\t')) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Folded HTTP headers are not supported");
            }

            return false;
        }

        const int separator =
            rawLine.indexOf(':');

        if (separator <= 0) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Malformed HTTP header");
            }

            return false;
        }

        const QByteArray key =
            rawLine.left(separator)
                .trimmed()
                .toLower();

        const QByteArray value =
            rawLine.mid(separator + 1)
                .trimmed();

        if (key ==
                QByteArrayLiteral(
                    "content-length")) {
            if (contentLengthSeen) {
                if (errorMessage) {
                    *errorMessage =
                        QStringLiteral(
                            "Duplicate Content-Length header");
                }

                return false;
            }

            contentLengthSeen = true;
        }

        if (request->headers.contains(key) &&
                key !=
                    QByteArrayLiteral(
                        "sec-websocket-protocol")) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Duplicate HTTP header");
            }

            return false;
        }

        if (request->headers.contains(key)) {
            request->headers[key].append(
                QByteArrayLiteral(","));
            request->headers[key].append(value);
        } else {
            request->headers.insert(
                key,
                value);
        }
    }

    if (request->headers.contains(
            QByteArrayLiteral(
                "transfer-encoding"))) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Transfer-Encoding is not supported");
        }

        return false;
    }

    int contentLength = 0;

    if (contentLengthSeen) {
        bool lengthOk = false;

        const qlonglong parsedLength =
            request->headers
                .value(
                    QByteArrayLiteral(
                        "content-length"))
                .toLongLong(
                    &lengthOk);

        if (!lengthOk ||
                parsedLength < 0 ||
                parsedLength >
                    m_maxHttpBodyBytes) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Invalid Content-Length");
            }

            return false;
        }

        contentLength =
            static_cast<int>(
                parsedLength);
    }

    const int bodyOffset =
        headerEnd + 4;

    const int totalLength =
        bodyOffset +
        contentLength;

    request->declaredContentLength =
        contentLength;

    request->valid = true;

    if (client->rawBuffer.size() <
            totalLength) {
        return true;
    }

    request->body =
        client->rawBuffer.mid(
            bodyOffset,
            contentLength);

    request->consumedBytes =
        totalLength;

    request->complete = true;

    if (errorMessage)
        errorMessage->clear();

    return true;
}


void TerminalManager::handleHttpRequest(
    QTcpSocket *socket,
    const HttpRequest &request)
{
    if (!socket)
        return;

    const QUrl url =
        QUrl::fromEncoded(
            request.target,
            QUrl::StrictMode);

    if (!url.isValid()) {
        socket->write(
            buildHttpResponse(
                QByteArrayLiteral(
                    "{\"ok\":false,\"error\":\"Invalid request target\"}"),
                QByteArrayLiteral(
                    "application/json"),
                400,
                QByteArrayLiteral(
                    "Bad Request")));

        socket->disconnectFromHost();
        return;
    }

    const QString path =
        url.path().isEmpty()
        ? QStringLiteral("/")
        : url.path();

    const QByteArray upgrade =
        httpHeaderValue(
            request,
            QByteArrayLiteral(
                "upgrade"))
            .toLower();

    const bool websocketRequest =
        path ==
            QStringLiteral("/ws") &&
        upgrade ==
            QByteArrayLiteral(
                "websocket");

    if (websocketRequest) {
        if (!performWebSocketHandshake(
                socket,
                request)) {
            refreshWebAuthLockout();
            const bool locked = webAuthLocked();
            const int retrySeconds = webAuthLockSecondsRemaining();
            socket->write(
                buildHttpResponse(
                    locked
                        ? QByteArrayLiteral("{\"ok\":false,\"error\":\"Pairing locked for 30 minutes\"}")
                        : QByteArrayLiteral("{\"ok\":false,\"error\":\"Unauthorized or invalid WebSocket request\"}"),
                    QByteArrayLiteral("application/json"),
                    locked ? 429 : 401,
                    locked
                        ? QByteArrayLiteral("Too Many Requests")
                        : QByteArrayLiteral("Unauthorized"),
                    locked
                        ? QList<QByteArray>{QByteArray("Retry-After: ") + QByteArray::number(retrySeconds)}
                        : QList<QByteArray>()));

            socket->disconnectFromHost();
        }

        return;
    }

    if (request.method !=
            QByteArrayLiteral("GET") &&
            request.method !=
                QByteArrayLiteral("POST")) {
        socket->write(
            buildHttpResponse(
                QByteArrayLiteral(
                    "{\"ok\":false,\"error\":\"Method not allowed\"}"),
                QByteArrayLiteral(
                    "application/json"),
                405,
                QByteArrayLiteral(
                    "Method Not Allowed"),
                {
                    QByteArrayLiteral(
                        "Allow: GET, POST")
                }));

        socket->disconnectFromHost();
        return;
    }

    if (request.method ==
            QByteArrayLiteral("GET") &&
            (path ==
                 QStringLiteral("/") ||
             path ==
                 QStringLiteral(
                     "/static/index.html"))) {
        socket->write(
            buildHttpResponse(
                builtinWebPage(),
                QByteArrayLiteral(
                    "text/html; charset=utf-8")));

        socket->disconnectFromHost();
        return;
    }

    if (request.method ==
            QByteArrayLiteral("GET") &&
            path ==
                QStringLiteral("/health")) {
        socket->write(
            buildHttpResponse(
                QByteArrayLiteral(
                    "{\"ok\":true,\"service\":\"neutronos-terminal\"}")));

        socket->disconnectFromHost();
        return;
    }

    if (request.method ==
            QByteArrayLiteral("GET") &&
            path ==
                QStringLiteral("/api/status")) {
        refreshWebAuthLockout();
        const QString sourceAddress = socket->peerAddress().toString();
        const QString candidate = requestWebTokenCandidate(request);

        if (webAuthLocked()) {
            const int seconds = webAuthLockSecondsRemaining();
            socket->write(
                buildHttpResponse(
                    QByteArrayLiteral(
                        "{\"ok\":false,\"error\":\"Pairing temporarily locked\"}"),
                    QByteArrayLiteral(
                        "application/json"),
                    429,
                    QByteArrayLiteral(
                        "Too Many Requests"),
                    {QByteArray("Retry-After: ") + QByteArray::number(seconds)}));
            socket->disconnectFromHost();
            return;
        }

        if (candidate.isEmpty() || !tokenMatches(candidate)) {
            if (!candidate.isEmpty())
                recordWebAuthFailure(sourceAddress);

            const bool lockedNow = webAuthLocked();
            socket->write(
                buildHttpResponse(
                    lockedNow
                        ? QByteArrayLiteral("{\"ok\":false,\"error\":\"Pairing locked for 30 minutes\"}")
                        : QByteArrayLiteral("{\"ok\":false,\"error\":\"Unauthorized\"}"),
                    QByteArrayLiteral("application/json"),
                    lockedNow ? 429 : 401,
                    lockedNow
                        ? QByteArrayLiteral("Too Many Requests")
                        : QByteArrayLiteral("Unauthorized"),
                    lockedNow
                        ? QList<QByteArray>{QByteArray("Retry-After: ") + QByteArray::number(webAuthLockSecondsRemaining())}
                        : QList<QByteArray>()));

            socket->disconnectFromHost();
            return;
        }

        resetWebAuthFailures();

        QVariantMap response;

        response.insert(
            QStringLiteral("ok"),
            true);

        response.insert(
            QStringLiteral("status"),
            publicWebStatusPayload());

        socket->write(
            buildHttpResponse(
                mapToCompactJson(
                    response)));

        socket->disconnectFromHost();
        return;
    }

    if (path ==
            QStringLiteral("/api/message")) {
        socket->write(
            buildHttpResponse(
                QByteArrayLiteral(
                    "{\"ok\":false,\"error\":\"Use the authenticated WebSocket endpoint\"}"),
                QByteArrayLiteral(
                    "application/json"),
                410,
                QByteArrayLiteral(
                    "Gone")));

        socket->disconnectFromHost();
        return;
    }

    socket->write(
        buildHttpResponse(
            QByteArrayLiteral(
                "{\"ok\":false,\"error\":\"Not found\"}"),
            QByteArrayLiteral(
                "application/json"),
            404,
            QByteArrayLiteral(
                "Not Found")));

    socket->disconnectFromHost();
}

QString TerminalManager::requestWebTokenCandidate(
    const HttpRequest &request) const
{
    const QByteArray authorization =
        httpHeaderValue(
            request,
            QByteArrayLiteral(
                "authorization"));

    if (authorization.size() >= 7 &&
            authorization.left(7).toLower() ==
                QByteArrayLiteral("bearer ")) {
        const QString candidate =
            QString::fromLatin1(
                authorization.mid(7))
                .trimmed();
        if (!candidate.isEmpty())
            return candidate;
    }

    const QByteArray protocols =
        httpHeaderValue(
            request,
            QByteArrayLiteral(
                "sec-websocket-protocol"));

    const QList<QByteArray> offered =
        protocols.split(',');

    for (QByteArray protocol : offered) {
        protocol = protocol.trimmed();
        QByteArray candidateBytes;

        if (protocol.startsWith(
                QByteArrayLiteral(
                    "code."))) {
            candidateBytes = protocol.mid(5);
        } else if (protocol.startsWith(
                       QByteArrayLiteral(
                           "token."))) {
            /* Legacy protocol prefix retained for one release cycle. */
            candidateBytes = protocol.mid(6);
        } else {
            continue;
        }

        const QString candidate =
            QString::fromLatin1(
                candidateBytes)
                .trimmed();
        if (!candidate.isEmpty())
            return candidate;
    }

    return QString();
}

bool TerminalManager::requestHasValidWebToken(
    const HttpRequest &request) const
{
    const QString candidate = requestWebTokenCandidate(request);
    return !candidate.isEmpty() && tokenMatches(candidate);
}

bool TerminalManager::webAuthLocked() const
{
    return m_webAuthLockedUntilMs > QDateTime::currentMSecsSinceEpoch();
}

int TerminalManager::webAuthLockSecondsRemaining() const
{
    const qint64 remaining =
        m_webAuthLockedUntilMs - QDateTime::currentMSecsSinceEpoch();
    return remaining > 0
        ? qMax(1, int((remaining + 999) / 1000))
        : 0;
}

void TerminalManager::refreshWebAuthLockout()
{
    if (m_webAuthLockedUntilMs <= 0 || webAuthLocked())
        return;
    m_webAuthLockedUntilMs = 0;
    m_webLanFailedPairingAttempts = 0;
    m_webTailscaleFailedPairingAttempts = 0;
    emit webMirrorSecurityChanged();
}

bool TerminalManager::webSourceIsTailscale(
    const QString &sourceAddress) const
{
    QHostAddress address;
    return address.setAddress(sourceAddress.trimmed()) &&
           isTailscaleAddress(address);
}

int TerminalManager::webAuthAttemptLimit(
    const QString &sourceAddress) const
{
    return webSourceIsTailscale(sourceAddress)
        ? WebTailscalePairingAttemptLimit
        : WebLanPairingAttemptLimit;
}

int TerminalManager::webAuthFailedAttempts(
    const QString &sourceAddress) const
{
    return webSourceIsTailscale(sourceAddress)
        ? m_webTailscaleFailedPairingAttempts
        : m_webLanFailedPairingAttempts;
}

void TerminalManager::recordWebAuthFailure(
    const QString &sourceAddress)
{
    refreshWebAuthLockout();
    if (webAuthLocked())
        return;

    int *counter = webSourceIsTailscale(sourceAddress)
        ? &m_webTailscaleFailedPairingAttempts
        : &m_webLanFailedPairingAttempts;
    ++(*counter);

    const int limit = webAuthAttemptLimit(sourceAddress);
    if (*counter >= limit) {
        m_webAuthLockedUntilMs =
            QDateTime::currentMSecsSinceEpoch() +
            WebPairingLockoutMs;

        audit(
            QStringLiteral("web_pairing_locked"),
            {
                {QStringLiteral("sourceClass"),
                 webSourceIsTailscale(sourceAddress)
                     ? QStringLiteral("tailscale")
                     : QStringLiteral("lan")},
                {QStringLiteral("attemptLimit"), limit},
                {QStringLiteral("lockoutMinutes"), 30}
            });
    }
    emit webMirrorSecurityChanged();
}

void TerminalManager::resetWebAuthFailures()
{
    const bool changed =
        m_webLanFailedPairingAttempts != 0 ||
        m_webTailscaleFailedPairingAttempts != 0 ||
        m_webAuthLockedUntilMs != 0;
    m_webLanFailedPairingAttempts = 0;
    m_webTailscaleFailedPairingAttempts = 0;
    m_webAuthLockedUntilMs = 0;
    if (changed)
        emit webMirrorSecurityChanged();
}


QByteArray TerminalManager::httpHeaderValue(
    const HttpRequest &request,
    const QByteArray &key) const
{
    return request.headers.value(
        key.trimmed().toLower());
}

QByteArray TerminalManager::buildHttpResponse(
    const QByteArray &body,
    const QByteArray &contentType,
    int statusCode,
    const QByteArray &statusText,
    const QList<QByteArray> &extraHeaders) const
{
    QByteArray response;

    response.reserve(
        body.size() +
        512);

    response.append(
        QByteArrayLiteral(
            "HTTP/1.1 "));

    response.append(
        QByteArray::number(
            statusCode));

    response.append(' ');
    response.append(statusText);

    response.append(
        QByteArrayLiteral(
            "\r\nContent-Type: "));

    response.append(contentType);

    response.append(
        QByteArrayLiteral(
            "\r\nContent-Length: "));

    response.append(
        QByteArray::number(
            body.size()));

    response.append(
        QByteArrayLiteral(
            "\r\nCache-Control: no-store, max-age=0"));

    response.append(
        QByteArrayLiteral(
            "\r\nPragma: no-cache"));

    response.append(
        QByteArrayLiteral(
            "\r\nX-Content-Type-Options: nosniff"));

    response.append(
        QByteArrayLiteral(
            "\r\nX-Frame-Options: DENY"));

    response.append(
        QByteArrayLiteral(
            "\r\nReferrer-Policy: no-referrer"));

    response.append(
        QByteArrayLiteral(
            "\r\nPermissions-Policy: camera=(), microphone=(), geolocation=()"));

    response.append(
        QByteArrayLiteral(
            "\r\nContent-Security-Policy: default-src 'self'; connect-src 'self' ws: wss:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self' data:"));

    for (const QByteArray &header :
            extraHeaders) {
        if (header.contains('\r') ||
                header.contains('\n')) {
            continue;
        }

        response.append(
            QByteArrayLiteral(
                "\r\n"));

        response.append(header);
    }

    response.append(
        QByteArrayLiteral(
            "\r\nConnection: close\r\n\r\n"));

    response.append(body);

    return response;
}

QByteArray TerminalManager::builtinWebPage() const
{
    return QByteArrayLiteral(R"HTML(<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#080b10">
<title>NeutronOS Remote Terminal Mirror</title>
<style>
:root{color-scheme:dark;font-family:Inter,ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#080b10;color:#f4f8ff}
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:radial-gradient(circle at 50% -10%,#182434 0,#0b1018 36%,#06080d 78%)}
button,input{font:inherit}button{cursor:pointer}
.shell{height:100dvh;display:flex;align-items:center;justify-content:center;padding:max(18px,env(safe-area-inset-top)) max(16px,env(safe-area-inset-right)) max(18px,env(safe-area-inset-bottom)) max(16px,env(safe-area-inset-left))}
.card{width:min(520px,100%);border:1px solid rgba(255,255,255,.11);border-radius:26px;background:linear-gradient(180deg,rgba(22,29,41,.97),rgba(10,14,21,.98));box-shadow:0 26px 80px rgba(0,0,0,.52),inset 0 1px rgba(255,255,255,.06);padding:32px}
.brand{display:flex;align-items:center;justify-content:center;gap:9px;margin-bottom:20px;color:#67ff9b;font-size:12px;font-weight:800;letter-spacing:.16em;text-transform:uppercase}.dot{width:8px;height:8px;border-radius:50%;background:#67ff9b;box-shadow:0 0 14px #4cff89}
h1{font-size:30px;line-height:1.08;text-align:center;margin:0 0 12px;letter-spacing:-.035em}.lede{margin:0 auto 28px;max-width:430px;text-align:center;color:#9ba9bb;line-height:1.55;font-size:14px}
.code{width:100%;height:64px;border-radius:17px;border:1px solid rgba(255,255,255,.13);background:#070a0f;color:#fff;text-align:center;font-size:26px;font-weight:750;letter-spacing:.14em;outline:none;transition:.18s}.code:focus{border-color:#6c8fff;box-shadow:0 0 0 4px rgba(92,125,255,.13)}
.connect{width:100%;height:54px;border:0;border-radius:16px;margin-top:14px;background:linear-gradient(135deg,#6c8fff,#845bff);color:white;font-weight:750;box-shadow:0 12px 28px rgba(87,92,255,.22)}.connect:active{transform:translateY(1px)}
.error{min-height:22px;margin:14px 0 0;color:#ff7f8d;text-align:center;font-size:13px}.hint{margin-top:18px;color:#6f7c8c;text-align:center;font-size:12px}.hidden{display:none!important}
.terminal-shell{position:fixed;inset:0;display:flex;flex-direction:column;background:#06090e}.topbar{height:60px;flex:0 0 auto;display:flex;align-items:center;gap:12px;padding:0 max(16px,env(safe-area-inset-right)) 0 max(16px,env(safe-area-inset-left));border-bottom:1px solid rgba(255,255,255,.08);background:rgba(10,14,21,.96);backdrop-filter:blur(18px)}
.title{min-width:0;flex:1}.title strong{display:block;font-size:14px}.title span{display:block;margin-top:2px;color:#8190a3;font-size:11px}.status{display:flex;align-items:center;gap:7px;color:#75ff9e;font-size:11px;font-weight:800;letter-spacing:.08em;text-transform:uppercase}.status .dot{width:7px;height:7px}
.output-wrap{position:relative;flex:1;min-height:0;padding:18px}.output{height:100%;margin:0;overflow:auto;overscroll-behavior:contain;white-space:pre-wrap;word-break:break-word;color:#e9f3ff;font:13px/1.55 "SFMono-Regular",Consolas,"Liberation Mono",monospace;scrollbar-width:thin;user-select:text;-webkit-user-select:text}
.inputbar{flex:0 0 auto;display:flex;gap:9px;padding:12px max(12px,env(safe-area-inset-right)) max(12px,env(safe-area-inset-bottom)) max(12px,env(safe-area-inset-left));border-top:1px solid rgba(255,255,255,.09);background:rgba(10,14,20,.98)}
.command{min-width:0;flex:1;height:50px;border-radius:14px;border:1px solid rgba(255,255,255,.12);background:#0a0e15;color:#f4f8ff;padding:0 15px;outline:none}.command:focus{border-color:#6f8cff;box-shadow:0 0 0 3px rgba(92,125,255,.11)}.send{width:78px;height:50px;border:0;border-radius:14px;background:#6c7cff;color:#fff;font-weight:800}.disconnect{border:1px solid rgba(255,255,255,.1);background:transparent;color:#9ba9bb;border-radius:12px;padding:9px 11px;font-size:12px}
@media(max-width:520px){.card{padding:26px 20px;border-radius:22px}h1{font-size:27px}.output-wrap{padding:14px}.topbar{height:56px}.disconnect{padding:8px 9px}.title span{display:none}}
</style>
</head>
<body>
<div id="loginShell" class="shell">
  <section class="card" aria-labelledby="loginTitle">
    <div class="brand"><span class="dot"></span>NeutronOS Secure Link</div>
    <h1 id="loginTitle">Remote Terminal Mirror</h1>
    <p class="lede">Enter the temporary code shown on your NeutronOS display. A validated device attaches to the same live terminal session.</p>
    <input id="codeInput" class="code" inputmode="numeric" autocomplete="one-time-code" autocapitalize="off" spellcheck="false" maxlength="9" placeholder="0000-0000" aria-label="Eight digit pairing code">
    <button id="connectButton" class="connect" type="button">Connect to Terminal</button>
    <p id="loginError" class="error" role="alert"></p>
    <div class="hint">Pairing codes expire after 60 seconds. Five failed LAN codes lock pairing for 30 minutes; Tailscale allows ten attempts.</div>
  </section>
</div>

<main id="terminalShell" class="terminal-shell hidden">
  <header class="topbar">
    <div class="status"><span class="dot"></span><span>Connected</span></div>
    <div class="title"><strong>Remote Terminal Mirror</strong><span id="modeText">Live NeutronOS terminal</span></div>
    <button id="disconnectButton" class="disconnect" type="button">Disconnect</button>
  </header>
  <div class="output-wrap"><pre id="output" class="output" aria-live="polite"></pre></div>
  <form id="commandForm" class="inputbar">
    <input id="commandInput" class="command" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Type a command…" aria-label="Terminal command">
    <button class="send" type="submit">Send</button>
  </form>
</main>

<script>
"use strict";
let socket=null;
const loginShell=document.getElementById("loginShell");
const terminalShell=document.getElementById("terminalShell");
const codeInput=document.getElementById("codeInput");
const loginError=document.getElementById("loginError");
const output=document.getElementById("output");
const commandInput=document.getElementById("commandInput");
const modeText=document.getElementById("modeText");

function normalizeCode(value){
  const digits=String(value||"").replace(/\D/g,"").slice(0,8);
  return digits.length>4?digits.slice(0,4)+"-"+digits.slice(4):digits;
}
function showLogin(message=""){
  loginShell.classList.remove("hidden");
  terminalShell.classList.add("hidden");
  loginError.textContent=message;
  setTimeout(()=>codeInput.focus(),40);
}
function showTerminal(){
  loginShell.classList.add("hidden");
  terminalShell.classList.remove("hidden");
  loginError.textContent="";
  setTimeout(()=>commandInput.focus(),40);
}
function send(message){
  if(!socket||socket.readyState!==WebSocket.OPEN)return false;
  socket.send(JSON.stringify(message));
  return true;
}
function scrollOutput(){output.scrollTop=output.scrollHeight}
function applyStatus(status){
  const state=status||{};
  modeText.textContent=(state.modeLabel||state.mode||"Live")+" · same PTY as NeutronOS";
}
function connect(){
  const code=normalizeCode(codeInput.value);
  codeInput.value=code;
  loginError.textContent="";
  if(!/^\d{4}-\d{4}$/.test(code)){
    loginError.textContent="Enter the eight-digit code shown on NeutronOS.";
    return;
  }
  if(socket){try{socket.close()}catch(_){}}
  const scheme=location.protocol==="https:"?"wss:":"ws:";
  try{
    socket=new WebSocket(`${scheme}//${location.host}/ws`,["neutronos-terminal",`code.${code}`]);
  }catch(_){
    showLogin("Unable to start the secure connection.");
    return;
  }
  socket.addEventListener("open",()=>{
    codeInput.value="";
    showTerminal();
    send({type:"terminal.clientHello",name:"mobile"});
  });
  socket.addEventListener("message",event=>{
    let message;
    try{message=JSON.parse(event.data)}catch(_){return}
    if(message.type==="terminal.hello"){
      output.textContent=message.history||"";
      commandInput.value=message.inputDraft?.text||"";
      applyStatus(message.status);
      scrollOutput();
    }else if(message.type==="terminal.output"){
      output.textContent+=String(message.data||"");
      scrollOutput();
    }else if(message.type==="terminal.draftChanged"){
      const next=message.inputDraft?.text;
      if(typeof next==="string"&&commandInput.value!==next)commandInput.value=next;
    }else if(message.type==="terminal.modeChanged"){
      applyStatus(message.status||message);
    }else if(message.type==="terminal.result"&&message.ok===false){
      loginError.textContent=message.error||"Terminal request failed.";
    }
  });
  socket.addEventListener("close",event=>{
    const reason=event.reason||"Remote terminal disconnected.";
    socket=null;
    showLogin(reason);
  });
  socket.addEventListener("error",()=>{
    loginError.textContent="Connection failed. The code may be wrong or expired, the mirror may be off, or pairing may be temporarily locked after too many attempts.";
  });
}
codeInput.addEventListener("input",()=>{codeInput.value=normalizeCode(codeInput.value)});
codeInput.addEventListener("keydown",event=>{if(event.key==="Enter"){event.preventDefault();connect()}});
document.getElementById("connectButton").addEventListener("click",connect);
document.getElementById("disconnectButton").addEventListener("click",()=>{if(socket)socket.close(1000,"User disconnected")});
commandInput.addEventListener("input",()=>send({type:"terminal.draftSet",text:commandInput.value}));
document.getElementById("commandForm").addEventListener("submit",event=>{
  event.preventDefault();
  if(!send({type:"terminal.draftSet",text:commandInput.value}))return;
  send({type:"terminal.draftCommit"});
});
showLogin();
</script>
</body>
</html>)HTML");
}


QByteArray TerminalManager::websocketAcceptKey(
    const QByteArray &clientKey) const
{
    static const QByteArray magic =
        QByteArrayLiteral(
            "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");

    return QCryptographicHash::hash(
               clientKey +
               magic,
               QCryptographicHash::Sha1)
        .toBase64();
}

bool TerminalManager::performWebSocketHandshake(
    QTcpSocket *socket,
    const HttpRequest &request)
{
    if (!socket ||
            request.method !=
                QByteArrayLiteral("GET")) {
        return false;
    }

    refreshWebAuthLockout();
    if (webAuthLocked())
        return false;

    const QString sourceAddress = socket->peerAddress().toString();
    const QString candidate = requestWebTokenCandidate(request);
    if (candidate.isEmpty())
        return false;

    if (!tokenMatches(candidate)) {
        recordWebAuthFailure(sourceAddress);
        return false;
    }

    resetWebAuthFailures();

    if (developerMode() &&
            !m_developerWebMirrorConfirmed) {
        return false;
    }

    const QByteArray upgrade =
        httpHeaderValue(
            request,
            QByteArrayLiteral("upgrade"))
            .toLower();

    const QByteArray connection =
        httpHeaderValue(
            request,
            QByteArrayLiteral("connection"))
            .toLower();

    const QByteArray version =
        httpHeaderValue(
            request,
            QByteArrayLiteral(
                "sec-websocket-version"));

    const QByteArray clientKey =
        httpHeaderValue(
            request,
            QByteArrayLiteral(
                "sec-websocket-key"))
            .trimmed();

    if (upgrade !=
            QByteArrayLiteral("websocket") ||
            !connection
                .split(',')
                .contains(
                    QByteArrayLiteral(
                        "upgrade")) ||
            version !=
                QByteArrayLiteral("13") ||
            clientKey.isEmpty()) {
        /*
            Connection header values may contain whitespace. Check again with
            a token-aware scan before failing.
        */
        bool upgradeTokenPresent = false;

        const QList<QByteArray> tokens =
            connection.split(',');

        for (QByteArray token : tokens) {
            if (token.trimmed() ==
                    QByteArrayLiteral(
                        "upgrade")) {
                upgradeTokenPresent = true;
                break;
            }
        }

        if (upgrade !=
                QByteArrayLiteral(
                    "websocket") ||
                !upgradeTokenPresent ||
                version !=
                    QByteArrayLiteral("13") ||
                clientKey.isEmpty()) {
            return false;
        }
    }

    const QByteArray offeredProtocols =
        httpHeaderValue(
            request,
            QByteArrayLiteral(
                "sec-websocket-protocol"));

    bool applicationProtocolOffered = false;

    for (QByteArray protocol :
            offeredProtocols.split(',')) {
        if (protocol.trimmed() ==
                QByteArrayLiteral(
                    "neutronos-terminal")) {
            applicationProtocolOffered = true;
            break;
        }
    }

    if (!applicationProtocolOffered)
        return false;

    const QByteArray decodedKey =
        QByteArray::fromBase64(
            clientKey);

    if (decodedKey.size() != 16)
        return false;

    auto iterator =
        m_webClients.find(socket);

    if (iterator ==
            m_webClients.end()) {
        return false;
    }

    QByteArray response;

    response.append(
        QByteArrayLiteral(
            "HTTP/1.1 101 Switching Protocols\r\n"));

    response.append(
        QByteArrayLiteral(
            "Upgrade: websocket\r\n"));

    response.append(
        QByteArrayLiteral(
            "Connection: Upgrade\r\n"));

    response.append(
        QByteArrayLiteral(
            "Sec-WebSocket-Accept: "));

    response.append(
        websocketAcceptKey(
            clientKey));

    response.append(
        QByteArrayLiteral(
            "\r\nSec-WebSocket-Protocol: neutronos-terminal\r\n"));

    response.append(
        QByteArrayLiteral(
            "Cache-Control: no-store\r\n\r\n"));

    if (socket->write(response) < 0)
        return false;

    socket->flush();

    WebClient &client =
        iterator.value();

    client.handshakeComplete = true;
    client.authenticated = true;
    client.lastActivityMonotonicMs =
        m_monotonicClock.elapsed();

    emit webClientCountChanged();
    emit statusChanged();

    audit(
        QStringLiteral(
            "web_client_authenticated"),
        {
            {
                QStringLiteral("clientId"),
                client.id
            },
            {
                QStringLiteral("address"),
                client.sourceAddress
            },
            {
                QStringLiteral("developerMode"),
                developerMode()
            }
        });

    sendWebHello(socket);

    broadcastWebJson(
        {
            {
                QStringLiteral("type"),
                QStringLiteral(
                    "terminal.webClientCountChanged")
            },
            {
                QStringLiteral("count"),
                authenticatedWebClientCount()
            }
        });

    return true;
}

QByteArray TerminalManager::encodeWebSocketTextFrame(
    const QByteArray &payload) const
{
    QByteArray frame;

    frame.reserve(
        payload.size() +
        10);

    frame.append(
        static_cast<char>(
            0x81));

    const quint64 length =
        static_cast<quint64>(
            payload.size());

    if (length < 126) {
        frame.append(
            static_cast<char>(
                length));
    } else if (length <= 65535) {
        frame.append(
            static_cast<char>(
                126));

        frame.append(
            static_cast<char>(
                (length >> 8) &
                0xFF));

        frame.append(
            static_cast<char>(
                length &
                0xFF));
    } else {
        frame.append(
            static_cast<char>(
                127));

        for (int shift = 7;
                shift >= 0;
                --shift) {
            frame.append(
                static_cast<char>(
                    (length >>
                     (shift * 8)) &
                    0xFF));
        }
    }

    frame.append(payload);
    return frame;
}

QByteArray TerminalManager::encodeWebSocketControlFrame(
    quint8 opcode,
    const QByteArray &payload) const
{
    const QByteArray safePayload =
        payload.left(125);

    QByteArray frame;

    frame.reserve(
        safePayload.size() +
        2);

    frame.append(
        static_cast<char>(
            0x80U |
            (opcode &
             0x0FU)));

    frame.append(
        static_cast<char>(
            safePayload.size()));

    frame.append(
        safePayload);

    return frame;
}

bool TerminalManager::decodeNextWebSocketFrame(
    WebClient *client,
    QByteArray *textPayload,
    bool *frameAvailable,
    QString *errorMessage)
{
    if (frameAvailable)
        *frameAvailable = false;

    if (textPayload)
        textPayload->clear();

    if (!client ||
            !client->socket) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Invalid WebSocket client");
        }

        return false;
    }

    QByteArray &buffer =
        client->rawBuffer;

    if (buffer.size() < 2)
        return true;

    const quint8 first =
        static_cast<quint8>(
            buffer.at(0));

    const quint8 second =
        static_cast<quint8>(
            buffer.at(1));

    const bool finalFrame =
        (first & 0x80U) != 0;

    const quint8 reservedBits =
        first & 0x70U;

    const quint8 opcode =
        first & 0x0FU;

    const bool masked =
        (second & 0x80U) != 0;

    quint64 payloadLength =
        second & 0x7FU;

    int offset = 2;

    if (reservedBits != 0) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "WebSocket extensions are not supported");
        }

        return false;
    }

    if (!finalFrame) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Fragmented WebSocket messages are not supported");
        }

        return false;
    }

    if (!masked) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Client WebSocket frames must be masked");
        }

        return false;
    }

    if (payloadLength == 126) {
        if (buffer.size() <
                offset + 2) {
            return true;
        }

        payloadLength =
            (static_cast<quint64>(
                 static_cast<quint8>(
                     buffer.at(offset)))
             << 8) |
            static_cast<quint64>(
                static_cast<quint8>(
                    buffer.at(
                        offset + 1)));

        offset += 2;

        if (payloadLength < 126) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Non-canonical WebSocket frame length");
            }

            return false;
        }
    } else if (payloadLength == 127) {
        if (buffer.size() <
                offset + 8) {
            return true;
        }

        if ((static_cast<quint8>(
                 buffer.at(offset)) &
             0x80U) != 0) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Invalid WebSocket frame length");
            }

            return false;
        }

        payloadLength = 0;

        for (int index = 0;
                index < 8;
                ++index) {
            payloadLength =
                (payloadLength << 8) |
                static_cast<quint64>(
                    static_cast<quint8>(
                        buffer.at(
                            offset +
                            index)));
        }

        offset += 8;

        if (payloadLength <= 65535) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Non-canonical WebSocket frame length");
            }

            return false;
        }
    }

    const bool controlFrame =
        opcode >= 0x8;

    if (controlFrame &&
            payloadLength > 125) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "WebSocket control frame is too large");
        }

        return false;
    }

    if (payloadLength >
            static_cast<quint64>(
                m_maxWebFrameBytes)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "WebSocket frame exceeds the configured limit");
        }

        return false;
    }

    if (buffer.size() <
            offset + 4) {
        return true;
    }

    const QByteArray mask =
        buffer.mid(
            offset,
            4);

    offset += 4;

    if (payloadLength >
            static_cast<quint64>(
                INT_MAX - offset)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "WebSocket frame length overflow");
        }

        return false;
    }

    const int totalLength =
        offset +
        static_cast<int>(
            payloadLength);

    if (buffer.size() <
            totalLength) {
        return true;
    }

    QByteArray payload =
        buffer.mid(
            offset,
            static_cast<int>(
                payloadLength));

    buffer.remove(
        0,
        totalLength);

    for (int index = 0;
            index < payload.size();
            ++index) {
        payload[index] =
            static_cast<char>(
                static_cast<unsigned char>(
                    payload.at(index)) ^
                static_cast<unsigned char>(
                    mask.at(index % 4)));
    }

    if (opcode == 0x8) {
        if (payload.size() == 1) {
            if (errorMessage) {
                *errorMessage =
                    QStringLiteral(
                        "Malformed WebSocket close frame");
            }

            return false;
        }

        if (!client->closeSent &&
                client->socket) {
            client->socket->write(
                encodeWebSocketControlFrame(
                    0x8,
                    payload));

            client->closeSent = true;
        }

        if (client->socket)
            client->socket->disconnectFromHost();

        return true;
    }

    if (opcode == 0x9) {
        if (client->socket) {
            client->socket->write(
                encodeWebSocketControlFrame(
                    0xA,
                    payload));
        }

        return true;
    }

    if (opcode == 0xA)
        return true;

    if (opcode != 0x1) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Only text WebSocket messages are supported");
        }

        return false;
    }

    if (payload.size() >
            m_maxWebMessageBytes) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "WebSocket message is too large");
        }

        return false;
    }

    if (textPayload)
        *textPayload = payload;

    if (frameAvailable)
        *frameAvailable = true;

    if (errorMessage)
        errorMessage->clear();

    return true;
}

void TerminalManager::handleWebSocketFrames(
    QTcpSocket *socket)
{
    if (!socket)
        return;

    auto iterator =
        m_webClients.find(socket);

    if (iterator ==
            m_webClients.end()) {
        return;
    }

    WebClient &client =
        iterator.value();

    while (!client.rawBuffer.isEmpty()) {
        const int before =
            client.rawBuffer.size();

        QByteArray payload;
        bool available = false;
        QString errorMessage;

        if (!decodeNextWebSocketFrame(
                &client,
                &payload,
                &available,
                &errorMessage)) {
            ++client.protocolViolations;

            audit(
                QStringLiteral(
                    "websocket_protocol_violation"),
                {
                    {
                        QStringLiteral("clientId"),
                        client.id
                    },
                    {
                        QStringLiteral("reason"),
                        errorMessage
                    }
                });

            disconnectWebClient(
                socket,
                1002,
                errorMessage);

            return;
        }

        if (client.rawBuffer.size() ==
                before &&
                !available) {
            break;
        }

        if (!available)
            continue;

        const QVariantMap message =
            compactJsonToMap(
                payload);

        if (message.isEmpty()) {
            ++client.protocolViolations;

            sendWebJson(
                socket,
                {
                    {
                        QStringLiteral("type"),
                        QStringLiteral(
                            "terminal.result")
                    },
                    {
                        QStringLiteral("ok"),
                        false
                    },
                    {
                        QStringLiteral("error"),
                        QStringLiteral(
                            "Web terminal message must be a JSON object")
                    }
                });

            if (client.protocolViolations >= 3) {
                disconnectWebClient(
                    socket,
                    1007,
                    QStringLiteral(
                        "Repeated invalid JSON messages"));

                return;
            }

            continue;
        }

        handleWebJsonMessage(
            socket,
            message);

        if (!m_webClients.contains(socket))
            return;
    }
}

void TerminalManager::handleWebJsonMessage(
    QTcpSocket *socket,
    const QVariantMap &message)
{
    if (!socket)
        return;

    auto iterator =
        m_webClients.find(socket);

    if (iterator ==
            m_webClients.end() ||
            !iterator.value()
                .authenticated) {
        return;
    }

    WebClient &client =
        iterator.value();

    const QString type =
        message.value(
            QStringLiteral("type"))
            .toString()
            .trimmed();

    int inputCharacters = 0;

    const QStringList inputFields = {
        QStringLiteral("text"),
        QStringLiteral("data")
    };

    for (const QString &field :
            inputFields) {
        inputCharacters +=
            message.value(field)
                .toString()
                .size();
    }

    QString rateError;

    if (!webClientMaySend(
            &client,
            inputCharacters,
            &rateError)) {
        sendWebJson(
            socket,
            {
                {
                    QStringLiteral("type"),
                    QStringLiteral(
                        "terminal.result")
                },
                {
                    QStringLiteral("ok"),
                    false
                },
                {
                    QStringLiteral("error"),
                    rateError
                }
            });

        disconnectWebClient(
            socket,
            1008,
            rateError);

        return;
    }

    const QString source =
        QStringLiteral("web:%1")
            .arg(client.id);

    QVariantMap result;

    result.insert(
        QStringLiteral("type"),
        QStringLiteral(
            "terminal.result"));

    result.insert(
        QStringLiteral("ok"),
        true);

    if (type ==
            QStringLiteral(
                "terminal.clientHello")) {
        QString name =
            message.value(
                QStringLiteral("name"))
                .toString()
                .trimmed()
                .left(64);

        name.remove(
            QRegularExpression(
                QStringLiteral(
                    "[^A-Za-z0-9 _.:-]")));

        if (!name.isEmpty())
            client.name = name;

        result.insert(
            QStringLiteral("status"),
            publicWebStatusPayload());
    } else if (type ==
                   QStringLiteral(
                       "terminal.draftSet") ||
               type ==
                   QStringLiteral(
                       "draft.set")) {
        setInputDraft(
            message.value(
                QStringLiteral("text"))
                .toString(),
            source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.draftAppend") ||
               type ==
                   QStringLiteral(
                       "draft.append")) {
        appendToDraft(
            message.value(
                QStringLiteral("text"))
                .toString(),
            source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.draftBackspace") ||
               type ==
                   QStringLiteral(
                       "draft.backspace")) {
        backspaceDraft(source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.draftClear") ||
               type ==
                   QStringLiteral(
                       "draft.clear")) {
        clearDraft(source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.draftCommit") ||
               type ==
                   QStringLiteral(
                       "draft.commit")) {
        commitDraft(source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.input") ||
               type ==
                   QStringLiteral("input")) {
        writeText(
            message.value(
                QStringLiteral("data"))
                .toString(),
            source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.key") ||
               type ==
                   QStringLiteral("key")) {
        sendKey(
            message.value(
                QStringLiteral("key"))
                .toString(),
            source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.paste") ||
               type ==
                   QStringLiteral("paste")) {
        pasteText(
            message.value(
                QStringLiteral("text"))
                .toString(),
            message.value(
                QStringLiteral("target"),
                QStringLiteral("draft"))
                .toString(),
            source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.clipboardSet") ||
               type ==
                   QStringLiteral(
                       "clipboard.set")) {
        setClipboardText(
            message.value(
                QStringLiteral("text"))
                .toString(),
            source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.selectionSet") ||
               type ==
                   QStringLiteral(
                       "selection.set")) {
        setSelectionText(
            message.value(
                QStringLiteral("text"))
                .toString(),
            source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.copySelection") ||
               type ==
                   QStringLiteral(
                       "copy.selection")) {
        copySelection(source);
    } else if (type ==
                   QStringLiteral(
                       "terminal.quickRun") ||
               type ==
                   QStringLiteral(
                       "quick.run")) {
        const QVariantMap quickResult =
            runQuickCommand(
                message.value(
                    QStringLiteral("id"))
                    .toString(),
                false,
                source);

        result.insert(
            QStringLiteral("quickResult"),
            quickResult);

        result.insert(
            QStringLiteral("ok"),
            quickResult.value(
                QStringLiteral("ok"))
                .toBool());

        result.insert(
            QStringLiteral("error"),
            quickResult.value(
                QStringLiteral("error"))
                .toString());
    } else if (type ==
                   QStringLiteral(
                       "terminal.snippetInsert")) {
        if (!m_assistManager) {
            result.insert(QStringLiteral("ok"), false);
            result.insert(QStringLiteral("error"), QStringLiteral("Snippet service unavailable"));
        } else {
            const QString snippetId = message.value(QStringLiteral("id")).toString();
            const QString text = m_assistManager->snippetText(snippetId);

            if (text.isEmpty()) {
                result.insert(QStringLiteral("ok"), false);
                result.insert(QStringLiteral("error"), QStringLiteral("Snippet not found"));
            } else {
                const bool append = message.value(QStringLiteral("append"), false).toBool();
                if (append)
                    appendToDraft(text, source);
                else
                    setInputDraft(text, source);

                result.insert(QStringLiteral("snippet"), m_assistManager->snippet(snippetId));
            }
        }
    } else if (type ==
                   QStringLiteral(
                       "terminal.snippetAdd")) {
        if (!m_assistManager) {
            result.insert(QStringLiteral("ok"), false);
            result.insert(QStringLiteral("error"), QStringLiteral("Snippet service unavailable"));
        } else {
            const QVariantMap snippetResult = m_assistManager->addSnippet(
                message.value(QStringLiteral("label")).toString(),
                message.value(QStringLiteral("command")).toString(),
                message.value(QStringLiteral("category"), QStringLiteral("Custom")).toString());
            result.insert(QStringLiteral("ok"), snippetResult.value(QStringLiteral("ok")).toBool());
            result.insert(QStringLiteral("snippet"), snippetResult);
            result.insert(QStringLiteral("error"), snippetResult.value(QStringLiteral("error")).toString());
        }
    } else if (type ==
                   QStringLiteral(
                       "terminal.snippetUpdate")) {
        if (!m_assistManager) {
            result.insert(QStringLiteral("ok"), false);
            result.insert(QStringLiteral("error"), QStringLiteral("Snippet service unavailable"));
        } else {
            const QVariantMap snippetResult = m_assistManager->updateSnippet(
                message.value(QStringLiteral("id")).toString(),
                message.value(QStringLiteral("label")).toString(),
                message.value(QStringLiteral("command")).toString(),
                message.value(QStringLiteral("category")).toString());
            result.insert(QStringLiteral("ok"), snippetResult.value(QStringLiteral("ok")).toBool());
            result.insert(QStringLiteral("snippet"), snippetResult);
            result.insert(QStringLiteral("error"), snippetResult.value(QStringLiteral("error")).toString());
        }
    } else if (type ==
                   QStringLiteral(
                       "terminal.snippetRemove")) {
        const bool ok = m_assistManager &&
            m_assistManager->removeSnippet(message.value(QStringLiteral("id")).toString());
        result.insert(QStringLiteral("ok"), ok);
        if (!ok)
            result.insert(QStringLiteral("error"), QStringLiteral("Unable to remove snippet"));
    } else if (type ==
                   QStringLiteral(
                       "terminal.snippetMove")) {
        const bool ok = m_assistManager &&
            m_assistManager->moveSnippet(
                message.value(QStringLiteral("id")).toString(),
                message.value(QStringLiteral("offset")).toInt());
        result.insert(QStringLiteral("ok"), ok);
        if (!ok)
            result.insert(QStringLiteral("error"), QStringLiteral("Unable to move snippet"));
    } else if (type ==
                   QStringLiteral(
                       "terminal.correctionAccept")) {
        if (!m_assistManager) {
            result.insert(QStringLiteral("ok"), false);
            result.insert(QStringLiteral("error"), QStringLiteral("Correction service unavailable"));
        } else {
            const QString corrected = m_assistManager->acceptSuggestionText();
            if (corrected.isEmpty()) {
                result.insert(QStringLiteral("ok"), false);
                result.insert(QStringLiteral("error"), QStringLiteral("No correction is available"));
            } else {
                setInputDraft(corrected, source);
            }
        }
    } else if (type ==
                   QStringLiteral(
                       "terminal.correctionDismiss")) {
        if (m_assistManager)
            m_assistManager->dismissSuggestion();
    } else if (type ==
                   QStringLiteral(
                       "terminal.correctionEnabled")) {
        if (m_assistManager) {
            m_assistManager->setSmartCorrectionEnabled(
                message.value(QStringLiteral("enabled"), true).toBool());
        } else {
            result.insert(QStringLiteral("ok"), false);
            result.insert(QStringLiteral("error"), QStringLiteral("Correction service unavailable"));
        }
    } else if (type ==
                   QStringLiteral(
                       "terminal.clearScreen") ||
               type ==
                   QStringLiteral(
                       "screen.clear")) {
        clearScreen();
    } else if (type ==
                   QStringLiteral(
                       "terminal.refresh") ||
               type ==
                   QStringLiteral("refresh") ||
               type ==
                   QStringLiteral("ping")) {
        QVariantList publicCommands;

        for (const QuickCommand &command :
                m_quickCommands) {
            QVariantMap commandMap =
                quickCommandToVariant(
                    command);

            commandMap.remove(
                QStringLiteral("command"));

            publicCommands.append(
                commandMap);
        }

        result.insert(
            QStringLiteral("status"),
            publicWebStatusPayload());

        result.insert(
            QStringLiteral("inputDraft"),
            makeDraftPayload(source));

        result.insert(
            QStringLiteral("clipboard"),
            makeClipboardPayload(source));

        result.insert(
            QStringLiteral("selection"),
            makeSelectionPayload(source));

        result.insert(
            QStringLiteral("quickCommands"),
            publicCommands);

        if (m_assistManager) {
            result.insert(QStringLiteral("snippets"), m_assistManager->snippets());
            result.insert(QStringLiteral("correctionSuggestion"), m_assistManager->correctionSuggestion());
            result.insert(QStringLiteral("smartCorrectionEnabled"), m_assistManager->smartCorrectionEnabled());
        }
    } else if (type ==
                   QStringLiteral(
                       "terminal.mode") ||
               type ==
                   QStringLiteral("mode") ||
               type.contains(
                   QStringLiteral(
                       "developer"),
                   Qt::CaseInsensitive) ||
               type.contains(
                   QStringLiteral(
                       "webMirror"),
                   Qt::CaseInsensitive) ||
               type ==
                   QStringLiteral(
                       "terminal.quickArm")) {
        result.insert(
            QStringLiteral("ok"),
            false);

        result.insert(
            QStringLiteral("error"),
            QStringLiteral(
                "This operation is controlled only by the local NeutronOS Console"));
    } else {
        result.insert(
            QStringLiteral("ok"),
            false);

        result.insert(
            QStringLiteral("error"),
            QStringLiteral(
                "Unknown terminal message type: %1")
                .arg(type));
    }

    sendWebJson(
        socket,
        result);
}


QVariantMap TerminalManager::makeStatusPayload() const
{
    QVariantMap result;

    result.insert(
        QStringLiteral("running"),
        m_running);

    result.insert(
        QStringLiteral("ptyAlive"),
        m_ptyAlive);

    result.insert(
        QStringLiteral("mode"),
        m_mode);

    result.insert(
        QStringLiteral("modeLabel"),
        modeLabel());

    result.insert(
        QStringLiteral("developerMode"),
        developerMode());

    result.insert(
        QStringLiteral("regularUsername"),
        m_regularUsername);

    result.insert(
        QStringLiteral("promptLabel"),
        promptLabel());

    result.insert(
        QStringLiteral("statusText"),
        m_statusText);

    result.insert(
        QStringLiteral("error"),
        m_error);

    result.insert(
        QStringLiteral("webMirrorEnabled"),
        m_webMirrorEnabled);

    result.insert(
        QStringLiteral("webMirrorRunning"),
        m_webMirrorRunning);

    result.insert(
        QStringLiteral("webMirrorLanAccessEnabled"),
        m_webMirrorLanAccessEnabled);

    result.insert(
        QStringLiteral(
            "webMirrorNeedsDeveloperConfirmation"),
        webMirrorNeedsDeveloperConfirmation());

    result.insert(
        QStringLiteral("webSecurityState"),
        webSecurityState());

    result.insert(
        QStringLiteral("webBindAddress"),
        m_webBindAddress);

    result.insert(
        QStringLiteral("webUrl"),
        webUrl());

    result.insert(
        QStringLiteral("webPairingCodeActive"),
        webPairingCodeActive());

    result.insert(
        QStringLiteral("webPairingCodeSecondsRemaining"),
        webPairingCodeSecondsRemaining());

    result.insert(
        QStringLiteral("webClientCount"),
        webClientCount());

    result.insert(
        QStringLiteral(
            "authenticatedWebClientCount"),
        authenticatedWebClientCount());

    result.insert(
        QStringLiteral("armedQuickActionId"),
        m_armedQuickActionId);

    result.insert(
        QStringLiteral(
            "armedQuickActionSecondsRemaining"),
        armedQuickActionSecondsRemaining());

    result.insert(
        QStringLiteral("columns"),
        m_columns);

    result.insert(
        QStringLiteral("rows"),
        m_rows);

    result.insert(
        QStringLiteral("pendingInputBytes"),
        m_pendingPtyWrite.size());

    result.insert(
        QStringLiteral("inputDraft"),
        makeDraftPayload());

    result.insert(
        QStringLiteral("clipboard"),
        makeClipboardPayload());

    result.insert(
        QStringLiteral("selection"),
        makeSelectionPayload());

    if (m_developerModeManager) {
        result.insert(
            QStringLiteral(
                "developerModeStatus"),
            m_developerModeManager
                ->status());
    }

    return result;
}

QVariantMap TerminalManager::makeDraftPayload(
    const QString &source) const
{
    QVariantMap result;

    result.insert(
        QStringLiteral("text"),
        m_inputDraft);

    result.insert(
        QStringLiteral("length"),
        m_inputDraft.size());

    result.insert(
        QStringLiteral("source"),
        source);

    return result;
}

QVariantMap TerminalManager::makeClipboardPayload(
    const QString &source) const
{
    QVariantMap result;

    result.insert(
        QStringLiteral("text"),
        m_clipboardText);

    result.insert(
        QStringLiteral("length"),
        m_clipboardText.size());

    result.insert(
        QStringLiteral("hasText"),
        !m_clipboardText.isEmpty());

    result.insert(
        QStringLiteral("source"),
        source);

    return result;
}

QVariantMap TerminalManager::makeSelectionPayload(
    const QString &source) const
{
    QVariantMap result;

    result.insert(
        QStringLiteral("text"),
        m_selectionText);

    result.insert(
        QStringLiteral("length"),
        m_selectionText.size());

    result.insert(
        QStringLiteral("hasText"),
        !m_selectionText.isEmpty());

    result.insert(
        QStringLiteral("source"),
        source);

    return result;
}

QVariantMap TerminalManager::publicWebStatusPayload() const
{
    QVariantMap result;

    result.insert(
        QStringLiteral("running"),
        m_running);

    result.insert(
        QStringLiteral("ptyAlive"),
        m_ptyAlive);

    result.insert(
        QStringLiteral("mode"),
        m_mode);

    result.insert(
        QStringLiteral("modeLabel"),
        modeLabel());

    result.insert(
        QStringLiteral("developerMode"),
        developerMode());

    result.insert(
        QStringLiteral("promptLabel"),
        promptLabel());

    result.insert(
        QStringLiteral("statusText"),
        m_statusText);

    result.insert(
        QStringLiteral("error"),
        m_error);

    result.insert(
        QStringLiteral("webMirrorRunning"),
        m_webMirrorRunning);

    result.insert(
        QStringLiteral("webSecurityState"),
        webSecurityState());

    result.insert(
        QStringLiteral(
            "authenticatedWebClientCount"),
        authenticatedWebClientCount());

    result.insert(
        QStringLiteral("columns"),
        m_columns);

    result.insert(
        QStringLiteral("rows"),
        m_rows);

    return result;
}

QVariantMap TerminalManager::sanitizedAuditDetails(
    const QVariantMap &details) const
{
    QVariantMap sanitized;

    for (auto iterator =
             details.constBegin();
         iterator !=
         details.constEnd();
         ++iterator) {
        const QString lowerKey =
            iterator.key()
                .trimmed()
                .toLower();

        const bool sensitive =
            lowerKey.contains(
                QStringLiteral("token")) ||
            lowerKey.contains(
                QStringLiteral("password")) ||
            lowerKey.contains(
                QStringLiteral("passphrase")) ||
            lowerKey.contains(
                QStringLiteral("secret")) ||
            lowerKey.contains(
                QStringLiteral("clipboard")) ||
            lowerKey.contains(
                QStringLiteral("selection")) ||
            lowerKey.contains(
                QStringLiteral("draft")) ||
            lowerKey.contains(
                QStringLiteral("command")) ||
            lowerKey.contains(
                QStringLiteral("input")) ||
            lowerKey.contains(
                QStringLiteral("output"));

        if (sensitive)
            continue;

        const QVariant value =
            iterator.value();

        if (value.userType() ==
                QMetaType::QVariantMap) {
            sanitized.insert(
                iterator.key(),
                sanitizedAuditDetails(
                    value.toMap()));

            continue;
        }

        if (value.userType() ==
                QMetaType::QVariantList) {
            QVariantList list;

            for (const QVariant &entry :
                    value.toList()) {
                if (entry.userType() ==
                        QMetaType::QVariantMap) {
                    list.append(
                        sanitizedAuditDetails(
                            entry.toMap()));
                } else if (entry.userType() ==
                           QMetaType::QString) {
                    list.append(
                        entry.toString()
                            .left(512));
                } else {
                    list.append(entry);
                }
            }

            sanitized.insert(
                iterator.key(),
                list);

            continue;
        }

        if (value.userType() ==
                QMetaType::QString) {
            sanitized.insert(
                iterator.key(),
                value.toString()
                    .left(1024));

            continue;
        }

        sanitized.insert(
            iterator.key(),
            value);
    }

    return sanitized;
}

void TerminalManager::audit(
    const QString &event,
    const QVariantMap &details) const
{
    if (event.trimmed().isEmpty())
        return;

    if (!ensureDirectory(
            m_logDir,
            true)) {
        return;
    }

    const QFileInfo existing(
        m_auditPath);

    if (existing.exists() &&
            (existing.isSymLink() ||
             !existing.isFile())) {
        return;
    }

    QFile file(
        m_auditPath);

    QIODevice::OpenMode mode =
        QIODevice::WriteOnly |
        QIODevice::Text;

    if (existing.exists() &&
            existing.size() >
                4 * 1024 * 1024) {
        mode |=
            QIODevice::Truncate;
    } else {
        mode |=
            QIODevice::Append;
    }

    if (!file.open(mode))
        return;

    QJsonObject object;

    object.insert(
        QStringLiteral("timestampUtc"),
        utcNowIso());

    object.insert(
        QStringLiteral("event"),
        event.left(128));

    object.insert(
        QStringLiteral("mode"),
        m_mode);

    object.insert(
        QStringLiteral("developerMode"),
        developerMode());

    object.insert(
        QStringLiteral("details"),
        QJsonObject::fromVariantMap(
            sanitizedAuditDetails(
                details)));

    const QByteArray line =
        QJsonDocument(object)
            .toJson(
                QJsonDocument::Compact) +
        QByteArray("\n", 1);

    const qint64 written =
        file.write(line);

    file.flush();
    file.close();

    if (written != line.size())
        return;

    secureFilePermissions(
        m_auditPath);
}
