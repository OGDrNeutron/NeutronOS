#pragma once

#include <QObject>
#include <QByteArray>
#include <QDateTime>
#include <QElapsedTimer>
#include <QFileSystemWatcher>
#include <QHash>
#include <QList>
#include <QPointer>
#include <QQueue>
#include <QSet>
#include <QSocketNotifier>
#include <QString>
#include <QStringList>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

#include <cstddef>

#include "DeveloperModeManager.h"

/*
    ========================================================================
                              TERMINAL MANAGER
    ========================================================================

    Canonical NeutronOS Terminal backend exposed to QML.

    Ownership rules:

        - There is exactly one PTY session.
        - HDMI/QML and the web mirror attach to the same PTY.
        - The draft, clipboard, selection, quick actions, and scrollback are
          shared by HDMI/QML and authenticated web clients.
        - Developer Mode remains Console-owned/global.
        - TerminalManager never enables Developer Mode.
        - TerminalManager only reads DeveloperModeManager state.
        - Entering Developer Mode never silently exposes a root shell over the
          network. Web access must be explicitly reconfirmed after the mode
          changes to developer.

    Shell behavior:

        Developer Mode OFF:
            - A validated local non-root account is used.
            - The PTY child drops supplementary groups, GID, and UID before
              exec.
            - Failure to resolve or drop to the regular account fails closed.
            - sudo retains the normal Linux password policy.

        Developer Mode ON:
            - The PTY may launch the configured root/developer shell.
            - The state is inherited only from DeveloperModeManager.
            - Terminal web access is stopped and its sessions are revoked until
              the HDMI/QML user explicitly confirms developer web access.

    Web-mirror security:

        - No unauthenticated endpoint returns terminal state.
        - Pairing codes are transient, eight digits, and expire after 60 seconds.
        - The code is not accepted through a URL query parameter or persisted.
        - Browser WebSocket authentication uses a protocol/header challenge,
          not localStorage or a code-bearing URL.
        - Existing authenticated sessions remain valid when a new code is made.
        - Client frames must be masked.
        - Fragmented, oversized, malformed, binary, and unsupported frames are
          rejected.
        - HTTP requests are processed only after their complete declared body
          has arrived.
        - Per-client request/message/input rate limits are enforced.
        - LAN listening is explicit. Loopback is the default.
        - The root/developer PTY is never auto-published.
        - Session and audit state remain protected by NeutronOS ownership rules.

    Performance:

        - PTY writes are queued and flushed through a write notifier. The QML
          thread never sleeps waiting for EAGAIN.
        - PTY shutdown and child reaping are timer-driven. The QML thread never
          blocks in waitpid loops.
        - UTF-8 carry bytes are retained between PTY reads.
        - Scrollback is bounded.
        - Web broadcasts are bounded and sent only to authenticated clients.

    Existing QML method and property names are preserved.
*/

#ifndef NEUTRONOS_STATE_DIR
#define NEUTRONOS_STATE_DIR "/var/lib/neutronos"
#endif

#ifndef NEUTRONOS_SECURITY_STATE_DIR
#define NEUTRONOS_SECURITY_STATE_DIR "/var/lib/neutronos/security"
#endif

#ifndef NEUTRONOS_LOG_DIR
#define NEUTRONOS_LOG_DIR "/var/log/neutronos"
#endif

class TerminalAssistManager;

class TerminalManager final : public QObject
{
    Q_OBJECT

    /*
        --------------------------------------------------------------------
                              PTY / APP STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool running
               READ running
               NOTIFY runningChanged)

    Q_PROPERTY(bool ptyAlive
               READ ptyAlive
               NOTIFY ptyAliveChanged)

    Q_PROPERTY(QString mode
               READ mode
               NOTIFY modeChanged)

    Q_PROPERTY(bool developerMode
               READ developerMode
               NOTIFY modeChanged)

    Q_PROPERTY(QString modeLabel
               READ modeLabel
               NOTIFY modeChanged)

    Q_PROPERTY(QString regularUsername
               READ regularUsername
               WRITE setRegularUsername
               NOTIFY regularUserChanged)

    /*
        --------------------------------------------------------------------
                            SHARED TERMINAL STATE
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString outputText
               READ outputText
               NOTIFY outputChanged)

    Q_PROPERTY(QString inputDraft
               READ inputDraft
               NOTIFY inputDraftChanged)

    Q_PROPERTY(QString clipboardText
               READ clipboardText
               NOTIFY clipboardChanged)

    Q_PROPERTY(QString selectionText
               READ selectionText
               NOTIFY selectionChanged)

    Q_PROPERTY(QString promptLabel
               READ promptLabel
               NOTIFY modeChanged)

    Q_PROPERTY(QString statusText
               READ statusText
               NOTIFY statusChanged)

    Q_PROPERTY(QString error
               READ error
               NOTIFY errorChanged)

    Q_PROPERTY(QString tintColor
               READ tintColor
               NOTIFY appearanceChanged)

    Q_PROPERTY(QString terminalTextColor
               READ terminalTextColor
               NOTIFY appearanceChanged)

    Q_PROPERTY(QString startupMessage
               READ startupMessage
               NOTIFY appearanceChanged)

    /*
        --------------------------------------------------------------------
                              QUICK COMMANDS
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QVariantList quickCommands
               READ quickCommands
               NOTIFY quickCommandsChanged)

    Q_PROPERTY(QString armedQuickActionId
               READ armedQuickActionId
               NOTIFY armedQuickActionChanged)

    Q_PROPERTY(int armedQuickActionSecondsRemaining
               READ armedQuickActionSecondsRemaining
               NOTIFY armedQuickActionChanged)

    /*
        --------------------------------------------------------------------
                               WEB MIRROR
        --------------------------------------------------------------------
    */

    Q_PROPERTY(bool webMirrorEnabled
               READ webMirrorEnabled
               WRITE setWebMirrorEnabled
               NOTIFY webMirrorChanged)

    Q_PROPERTY(bool webMirrorRunning
               READ webMirrorRunning
               NOTIFY webMirrorChanged)

    Q_PROPERTY(bool webMirrorLanAccessEnabled
               READ webMirrorLanAccessEnabled
               WRITE setWebMirrorLanAccessEnabled
               NOTIFY webMirrorSecurityChanged)

    Q_PROPERTY(bool webMirrorNeedsDeveloperConfirmation
               READ webMirrorNeedsDeveloperConfirmation
               NOTIFY webMirrorSecurityChanged)

    Q_PROPERTY(QString webBindAddress
               READ webBindAddress
               NOTIFY webMirrorChanged)

    Q_PROPERTY(QString webUrl
               READ webUrl
               NOTIFY webMirrorChanged)

    Q_PROPERTY(QString webToken
               READ webToken
               NOTIFY webTokenChanged)

    Q_PROPERTY(QString webPairingCode
               READ webPairingCode
               NOTIFY webPairingCodeChanged)

    Q_PROPERTY(int webPairingCodeSecondsRemaining
               READ webPairingCodeSecondsRemaining
               NOTIFY webPairingCodeChanged)

    Q_PROPERTY(bool webPairingCodeActive
               READ webPairingCodeActive
               NOTIFY webPairingCodeChanged)

    Q_PROPERTY(int webClientCount
               READ webClientCount
               NOTIFY webClientCountChanged)

    Q_PROPERTY(int authenticatedWebClientCount
               READ authenticatedWebClientCount
               NOTIFY webClientCountChanged)

    Q_PROPERTY(QString webSecurityState
               READ webSecurityState
               NOTIFY webMirrorSecurityChanged)

    /*
        --------------------------------------------------------------------
                                DIAGNOSTICS
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QVariantMap status
               READ status
               NOTIFY statusChanged)

public:
    explicit TerminalManager(
        DeveloperModeManager *developerModeManager,
        QObject *parent = nullptr);

    ~TerminalManager() override;

    void setAssistManager(TerminalAssistManager *assistManager);

    /*
        PTY/application state.
    */
    bool running() const;
    bool ptyAlive() const;

    QString mode() const;
    bool developerMode() const;
    QString modeLabel() const;

    QString regularUsername() const;
    void setRegularUsername(const QString &username);

    /*
        Shared terminal state.
    */
    QString outputText() const;
    QString inputDraft() const;
    QString clipboardText() const;
    QString selectionText() const;

    QString promptLabel() const;
    QString statusText() const;
    QString error() const;

    QString tintColor() const;
    QString terminalTextColor() const;
    QString startupMessage() const;

    /*
        Quick commands.
    */
    QVariantList quickCommands() const;
    QString armedQuickActionId() const;
    int armedQuickActionSecondsRemaining() const;

    /*
        Web mirror.
    */
    bool webMirrorEnabled() const;
    void setWebMirrorEnabled(bool enabled);

    bool webMirrorRunning() const;

    bool webMirrorLanAccessEnabled() const;
    void setWebMirrorLanAccessEnabled(bool enabled);

    bool webMirrorNeedsDeveloperConfirmation() const;

    QString webBindAddress() const;
    QString webUrl() const;
    QString webToken() const;
    QString webPairingCode() const;
    int webPairingCodeSecondsRemaining() const;
    bool webPairingCodeActive() const;

    int webClientCount() const;
    int authenticatedWebClientCount() const;

    QString webSecurityState() const;

    QVariantMap status() const;

    /*
        --------------------------------------------------------------------
                              APP LIFECYCLE
        --------------------------------------------------------------------
    */

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void refreshMode();

    /*
        --------------------------------------------------------------------
                              TERMINAL OUTPUT
        --------------------------------------------------------------------
    */

    Q_INVOKABLE void clearOutput();
    Q_INVOKABLE void clearScreen();

    Q_INVOKABLE QVariantMap saveAppearance(
        const QString &tintColor,
        const QString &textColor,
        const QString &startupMessage);

    Q_INVOKABLE QVariantMap resetAppearance();

    /*
        --------------------------------------------------------------------
                            SHARED TYPE BAR
        --------------------------------------------------------------------
    */

    Q_INVOKABLE void setInputDraft(
        const QString &text,
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE void appendToDraft(
        const QString &text,
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE void backspaceDraft(
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE void clearDraft(
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE void commitDraft(
        const QString &source = QStringLiteral("qml"));

    /*
        Submit the exact text visible in the local/remote type bar.
        Returns an explicit result so UI callers never have to infer whether
        PTY startup or input delivery failed.
    */
    Q_INVOKABLE QVariantMap submitCommand(
        const QString &text,
        const QString &source = QStringLiteral("qml"));

    /*
        Direct PTY input.
    */
    Q_INVOKABLE void writeText(
        const QString &text,
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE void sendKey(
        const QString &key,
        const QString &source = QStringLiteral("qml"));

    /*
        --------------------------------------------------------------------
                         SHARED CLIPBOARD / SELECTION
        --------------------------------------------------------------------
    */

    Q_INVOKABLE void setClipboardText(
        const QString &text,
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE QString getClipboardText() const;

    Q_INVOKABLE void pasteText(
        const QString &text,
        const QString &target = QStringLiteral("draft"),
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE void setSelectionText(
        const QString &text,
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE void clearSelection(
        const QString &source = QStringLiteral("qml"));

    Q_INVOKABLE void copySelection(
        const QString &source = QStringLiteral("qml"));

    /*
        --------------------------------------------------------------------
                              QUICK COMMANDS
        --------------------------------------------------------------------

        Armed confirmation is server-owned. A caller-supplied boolean cannot
        bypass it. A destructive command runs only when:

            - the same command ID is currently armed,
            - the arming window has not expired,
            - the backend-required mode is active,
            - the command record remains valid.
    */

    Q_INVOKABLE void armQuickAction(const QString &id);
    Q_INVOKABLE void clearArmedQuickAction();

    Q_INVOKABLE QVariantMap runQuickCommand(
        const QString &id,
        bool armed = false,
        const QString &source = QStringLiteral("qml"));

    /*
        --------------------------------------------------------------------
                               PTY GEOMETRY
        --------------------------------------------------------------------
    */

    Q_INVOKABLE void resizeTerminal(int columns, int rows);

    /*
        --------------------------------------------------------------------
                               WEB MIRROR
        --------------------------------------------------------------------

        Existing startWebMirror() remains available. In developer mode it will
        fail closed unless confirmDeveloperWebMirrorAccess() was called from
        the local HDMI/QML session after the mode transition.

        requestStartWebMirror(true) is the preferred explicit local action.
    */

    Q_INVOKABLE void startWebMirror();
    Q_INVOKABLE void stopWebMirror();

    Q_INVOKABLE bool requestStartWebMirror(
        bool confirmDeveloperAccess = false);

    Q_INVOKABLE bool confirmDeveloperWebMirrorAccess();
    Q_INVOKABLE void revokeDeveloperWebMirrorAccess();

    Q_INVOKABLE void disconnectWebClients();

    /*
        Generates a one-time eight-digit pairing code in XXXX-XXXX format.
        The code is valid for 60 seconds and is never persisted to disk.
        Existing authenticated sessions remain attached to the live PTY.
    */
    Q_INVOKABLE QString generateWebPairingCode();

    /*
        Atomic Remote Mirror actions for QML. These replace the fragile
        multi-property sequence previously used by the modal and return the
        actual backend success/error state.
    */
    Q_INVOKABLE QVariantMap setRemoteMirrorActive(bool enabled);
    Q_INVOKABLE QVariantMap generateRemoteMirrorCode();

    /*
        Legacy QML compatibility. This now generates a transient pairing code.
    */
    Q_INVOKABLE void regenerateWebToken();

    Q_INVOKABLE QVariantMap refreshStatus();

signals:
    /*
        PTY/application state.
    */
    void runningChanged();
    void ptyAliveChanged();
    void modeChanged();
    void regularUserChanged();

    /*
        Shared terminal state.
    */
    void outputChanged();
    void outputAppended(const QString &text);

    void inputDraftChanged(const QString &text,
                           const QString &source);

    void commandCommitted(const QString &command,
                          const QString &source);

    void clipboardChanged(const QString &text,
                          const QString &source);

    void selectionChanged(const QString &text,
                          const QString &source);

    void statusChanged();
    void errorChanged();
    void appearanceChanged();

    /*
        Quick commands.
    */
    void quickCommandsChanged();
    void armedQuickActionChanged();
    void quickActionFinished(const QVariantMap &result);

    /*
        Web mirror.
    */
    void webMirrorChanged();
    void webMirrorSecurityChanged();
    void webTokenChanged();
    void webPairingCodeChanged();
    void webClientCountChanged();

    /*
        General structured event feed.
    */
    void terminalEvent(const QString &event,
                       const QVariantMap &details);

private slots:
    /*
        PTY I/O/lifecycle.
    */
    void readPtyOutput();
    void flushPtyWriteQueue();
    void reapPtyChild();
    void advancePtyShutdown();

    /*
        Mode/arming.
    */
    void handleModeWatch();
    void updateArmedQuickActionState();

    /*
        Web.
    */
    void handleNewWebConnection();
    void sweepWebClients();

    /*
        Config watching.
    */
    void onConfigPathChanged(const QString &path);
    void reloadWatchedConfiguration();

private:
    /*
        ====================================================================
                              QUICK COMMAND MODEL
        ====================================================================
    */

    struct QuickCommand
    {
        QString id;
        QString label;
        QString group;
        QString icon;
        QString command;

        bool enter = true;
        bool requiresArmed = false;
        bool developerOnly = false;
        bool rootRequired = false;
        bool enabled = true;
    };

    /*
        ====================================================================
                               PTY LAUNCH MODEL
        ====================================================================

        Every string and ID needed by the child is resolved before forkpty().
        The post-fork child path must not call QObject, allocate Qt objects,
        query NSS/PAM, emit signals, or touch shared application state.
    */

    struct PtyLaunchPlan
    {
        QByteArray shellPath;
        QByteArray argumentZero;
        QByteArray workingDirectory;

        QByteArray home;
        QByteArray user;
        QByteArray logName;

        QByteArray term;
        QByteArray colorTerm;
        QByteArray terminalMode;
        QByteArray developerMode;

        QVector<quint32> supplementaryGroups;

        quint32 uid = 0;
        quint32 gid = 0;

        bool dropPrivileges = false;
        bool developer = false;
        bool valid = false;

        QString error;
    };

    enum class PtyShutdownPhase
    {
        Idle,
        HangupSent,
        TerminateSent,
        KillSent
    };

    /*
        ====================================================================
                              WEB CLIENT MODEL
        ====================================================================
    */

    struct WebClient
    {
        QPointer<QTcpSocket> socket;

        bool handshakeComplete = false;
        bool authenticated = false;
        bool closeSent = false;

        QString id;
        QString name;
        QString sourceAddress;

        QByteArray rawBuffer;

        qint64 connectedAtMonotonicMs = 0;
        qint64 lastActivityMonotonicMs = 0;
        qint64 rateWindowStartedMonotonicMs = 0;

        int messagesInWindow = 0;
        int inputCharactersInWindow = 0;
        int protocolViolations = 0;

        QDateTime connectedAtUtc;
    };

    struct HttpRequest
    {
        QByteArray method;
        QByteArray target;
        QByteArray version;

        QHash<QByteArray, QByteArray> headers;
        QByteArray body;

        int declaredContentLength = 0;
        int consumedBytes = 0;

        bool complete = false;
        bool valid = false;
    };

    /*
        ====================================================================
                               CORE DEPENDENCY
        ====================================================================
    */

    DeveloperModeManager *m_developerModeManager = nullptr;
    TerminalAssistManager *m_assistManager = nullptr;

    /*
        ====================================================================
                               APP / PTY STATE
        ====================================================================
    */

    bool m_running = false;
    bool m_ptyAlive = false;

    QString m_mode = QStringLiteral("regular");
    QString m_regularUsername;

    QString m_outputText;
    QString m_inputDraft;
    QString m_clipboardText;
    QString m_selectionText;

    QString m_statusText = QStringLiteral("Ready");
    QString m_error;

    QByteArray m_utf8Carry;
    QByteArray m_pendingPtyWrite;

    int m_masterFd = -1;
    qint64 m_childPid = -1;

    QSocketNotifier *m_ptyReadNotifier = nullptr;
    QSocketNotifier *m_ptyWriteNotifier = nullptr;

    PtyShutdownPhase m_ptyShutdownPhase =
        PtyShutdownPhase::Idle;

    qint64 m_ptyShutdownStartedMonotonicMs = 0;

    bool m_restartAfterPtyExit = false;
    bool m_expectedPtyExit = false;

    /*
        ====================================================================
                               QUICK COMMAND STATE
        ====================================================================
    */

    QList<QuickCommand> m_quickCommands;

    QString m_armedQuickActionId;
    qint64 m_armedQuickActionUntilMonotonicMs = 0;

    int m_armedQuickActionTimeoutSeconds = 8;

    /*
        ====================================================================
                                WEB STATE
        ====================================================================
    */

    bool m_webMirrorEnabled = false;
    bool m_webMirrorRunning = false;

    bool m_webMirrorLanAccessEnabled = false;
    bool m_developerWebMirrorConfirmed = false;

    QString m_webToken;
    qint64 m_webTokenExpiresMonotonicMs = 0;
    QString m_webBindAddress;

    int m_webPort = 8092;
    int m_webPairingCodeLifetimeSeconds = 60;
    int m_webLanFailedPairingAttempts = 0;
    int m_webTailscaleFailedPairingAttempts = 0;
    qint64 m_webAuthLockedUntilMs = 0;

    QTcpServer *m_webServer = nullptr;
    QHash<QTcpSocket *, WebClient> m_webClients;

    /*
        ====================================================================
                                RESOURCE LIMITS
        ====================================================================
    */

    int m_columns = 120;
    int m_rows = 34;

    int m_scrollbackLimit = 180000;
    int m_maxPasteChars = 20000;
    int m_maxDraftChars = 4000;

    int m_maxPendingPtyWriteBytes = 256 * 1024;

    int m_maxHttpHeaderBytes = 32 * 1024;
    int m_maxHttpBodyBytes = 256 * 1024;
    int m_maxWebFrameBytes = 1024 * 1024;
    int m_maxWebMessageBytes = 256 * 1024;

    int m_maxWebClients = 4;

    int m_webHandshakeTimeoutMs = 10000;
    int m_webIdleTimeoutMs = 30 * 60 * 1000;

    int m_maxMessagesPerRateWindow = 120;
    int m_maxInputCharactersPerRateWindow = 50000;
    int m_rateWindowMs = 10000;

    /*
        ====================================================================
                                   PATHS
        ====================================================================
    */

    QString m_repoRoot;

    QString m_stateDir;
    QString m_securityDir;
    QString m_configDir;
    QString m_logDir;

    QString m_quickCommandsPath;
    QString m_appearancePath;
    QString m_auditPath;

    QString m_tintColor = QStringLiteral("#68D8FF");
    QString m_terminalTextColor = QStringLiteral("#F3FCFF");
    QString m_startupMessage = QStringLiteral("Welcome to NeutronOS Gemini.");

    /*
        ====================================================================
                              TIMERS / WATCHERS
        ====================================================================
    */

    QElapsedTimer m_monotonicClock;

    QTimer m_modeWatchTimer;
    QTimer m_armedQuickActionTimer;
    QTimer m_childReapTimer;
    QTimer m_ptyShutdownTimer;
    QTimer m_webClientSweepTimer;
    QTimer m_configurationReloadTimer;

    QFileSystemWatcher m_configurationWatcher;
    QSet<QString> m_watchedConfigurationPaths;

    /*
        ====================================================================
                              PATH / CONFIGURATION
        ====================================================================
    */

    void resolvePaths();

    bool ensureDirectories();
    bool ensureDirectory(const QString &path,
                         bool ownerOnly) const;

    bool secureFilePermissions(const QString &path) const;
    bool pathIsSafe(const QString &path,
                    bool directory,
                    bool ownerOnly) const;

    void rebuildConfigurationWatchers();
    void scheduleConfigurationReload();

    void loadQuickCommands();
    void saveDefaultQuickCommandsIfMissing();

    void loadAppearance();
    bool saveAppearanceFile(QString *errorMessage = nullptr) const;
    static bool validAppearanceColor(const QString &value);
    static QString sanitizeStartupMessage(const QString &value);

    bool parseQuickCommand(const QVariantMap &source,
                           QuickCommand *result,
                           QString *errorMessage) const;

    /*
        ====================================================================
                                MODE / USER
        ====================================================================
    */

    QString currentModeFromDeveloperManager() const;

    void syncModeFromDeveloperManager(
        bool forceRestart = false);

    QString resolveRegularUsername() const;

    bool resolveRegularAccount(
        const QString &username,
        PtyLaunchPlan *plan,
        QString *errorMessage) const;

    QString regularShellPath() const;
    QString developerShellPath() const;

    /*
        ====================================================================
                                PTY LIFECYCLE
        ====================================================================
    */

    bool startPty();
    void stopPty();

    bool buildPtyLaunchPlan(
        PtyLaunchPlan *plan,
        QString *errorMessage) const;

    static void executePtyChild(
        const PtyLaunchPlan &plan);

    void finalizePtyExit(
        int waitStatus,
        bool expected);

    void closePtyDescriptors();

    void requestPtyShutdown();
    void sendSignalToPtyProcessGroup(int signalNumber);

    /*
        ====================================================================
                                  PTY I/O
        ====================================================================
    */

    bool queuePtyWrite(const QByteArray &data);
    bool writeToPty(const QByteArray &data);

    void updatePtyWriteNotifier();

    QString decodePtyBytes(const QByteArray &bytes);
    void appendOutput(const QString &text);
    void trimOutput();

    QString shellBanner() const;

    /*
        ====================================================================
                                PROPERTY SETTERS
        ====================================================================
    */

    void setRunning(bool value);
    void setPtyAlive(bool value);
    void setMode(const QString &value);
    void setStatusText(const QString &value);
    void setError(const QString &value);

    /*
        ====================================================================
                                 KEY INPUT
        ====================================================================
    */

    QString normalizeKeyName(const QString &key) const;
    QByteArray keyToBytes(const QString &key) const;

    /*
        ====================================================================
                               QUICK COMMANDS
        ====================================================================
    */

    QuickCommand *findQuickCommand(const QString &id);
    const QuickCommand *findQuickCommand(const QString &id) const;

    QVariantMap quickCommandToVariant(
        const QuickCommand &command) const;

    QVariantMap quickCommandResult(
        bool ok,
        const QString &id,
        const QString &message) const;

    bool commandLooksDangerous(
        const QString &command) const;

    bool quickCommandAllowed(
        const QuickCommand &command,
        bool callerArmedHint,
        const QString &source,
        QString *message) const;

    bool armedQuickActionValid(
        const QString &id) const;

    /*
        ====================================================================
                         DRAFT / PASTE / CLIPBOARD
        ====================================================================
    */

    QString sanitizeDraft(const QString &text) const;

    QString sanitizePaste(
        const QString &text,
        bool *truncated = nullptr) const;

    QString sanitizeSource(
        const QString &source) const;

    void updateClipboard(
        const QString &text,
        const QString &source);

    void updateSelection(
        const QString &text,
        const QString &source);

    void updateDraft(
        const QString &text,
        const QString &source);

    /*
        ====================================================================
                              WEB TOKEN / BINDING
        ====================================================================
    */

    QString generateWebToken() const;

    bool tokenMatches(
        const QString &candidate) const;

    QString localIpHint() const;

    bool selectWebBindAddress(
        QString *address,
        QString *errorMessage) const;

    void revokeWebAuthenticationState();

    /*
        ====================================================================
                              WEB CLIENT CONTROL
        ====================================================================
    */

    void removeWebClient(
        QTcpSocket *socket,
        const QString &reason = QString());

    void disconnectWebClient(
        QTcpSocket *socket,
        quint16 closeCode,
        const QString &reason);

    bool webClientMaySend(
        WebClient *client,
        int inputCharacters,
        QString *errorMessage);

    void broadcastWebJson(
        const QVariantMap &message);

    void sendWebJson(
        QTcpSocket *socket,
        const QVariantMap &message);

    void sendWebHello(
        QTcpSocket *socket);

    /*
        ====================================================================
                                  HTTP
        ====================================================================
    */

    void handleWebReadyRead(
        QTcpSocket *socket);

    bool parseHttpRequest(
        WebClient *client,
        HttpRequest *request,
        QString *errorMessage) const;

    void handleHttpRequest(
        QTcpSocket *socket,
        const HttpRequest &request);

    bool requestHasValidWebToken(
        const HttpRequest &request) const;

    QString requestWebTokenCandidate(
        const HttpRequest &request) const;

    bool webAuthLocked() const;
    int webAuthLockSecondsRemaining() const;
    void refreshWebAuthLockout();
    bool webSourceIsTailscale(const QString &sourceAddress) const;
    int webAuthAttemptLimit(const QString &sourceAddress) const;
    int webAuthFailedAttempts(const QString &sourceAddress) const;
    void recordWebAuthFailure(const QString &sourceAddress);
    void resetWebAuthFailures();

    QByteArray httpHeaderValue(
        const HttpRequest &request,
        const QByteArray &key) const;

    QByteArray buildHttpResponse(
        const QByteArray &body,
        const QByteArray &contentType =
            QByteArrayLiteral("application/json"),
        int statusCode = 200,
        const QByteArray &statusText =
            QByteArrayLiteral("OK"),
        const QList<QByteArray> &extraHeaders =
            QList<QByteArray>()) const;

    QByteArray builtinWebPage() const;

    /*
        ====================================================================
                                WEBSOCKET
        ====================================================================
    */

    bool performWebSocketHandshake(
        QTcpSocket *socket,
        const HttpRequest &request);

    QByteArray websocketAcceptKey(
        const QByteArray &clientKey) const;

    QByteArray encodeWebSocketTextFrame(
        const QByteArray &payload) const;

    QByteArray encodeWebSocketControlFrame(
        quint8 opcode,
        const QByteArray &payload) const;

    bool decodeNextWebSocketFrame(
        WebClient *client,
        QByteArray *textPayload,
        bool *frameAvailable,
        QString *errorMessage);

    void handleWebSocketFrames(
        QTcpSocket *socket);

    void handleWebJsonMessage(
        QTcpSocket *socket,
        const QVariantMap &message);

    /*
        ====================================================================
                              STATUS PAYLOADS
        ====================================================================
    */

    QVariantMap makeStatusPayload() const;

    QVariantMap makeDraftPayload(
        const QString &source = QString()) const;

    QVariantMap makeClipboardPayload(
        const QString &source = QString()) const;

    QVariantMap makeSelectionPayload(
        const QString &source = QString()) const;

    QVariantMap publicWebStatusPayload() const;

    /*
        ====================================================================
                                    AUDIT
        ====================================================================
    */

    QVariantMap sanitizedAuditDetails(
        const QVariantMap &details) const;

    void audit(
        const QString &event,
        const QVariantMap &details =
            QVariantMap()) const;
};
