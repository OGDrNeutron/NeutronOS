#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QStringList>
#include <QJsonObject>

class QTimer;
class QProcessEnvironment;

class GamesManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList games READ games NOTIFY gamesChanged)
    Q_PROPERTY(bool gameRunning READ gameRunning NOTIFY runtimeChanged)
    Q_PROPERTY(bool gamePaused READ gamePaused NOTIFY runtimeChanged)
    Q_PROPERTY(QString runningGameId READ runningGameId NOTIFY runtimeChanged)
    Q_PROPERTY(QString runningGameTitle READ runningGameTitle NOTIFY runtimeChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY lastMessageChanged)
    Q_PROPERTY(QString romRoot READ romRoot CONSTANT)
    Q_PROPERTY(QString cardsRoot READ cardsRoot CONSTANT)
    Q_PROPERTY(bool installerRunning READ installerRunning NOTIFY installerChanged)
    Q_PROPERTY(QString installerStatus READ installerStatus NOTIFY installerChanged)
    Q_PROPERTY(int installerProgress READ installerProgress NOTIFY installerChanged)

public:
    Q_INVOKABLE void humanSessionChanged();
    explicit GamesManager(const QString &neutronRoot, QObject *parent = nullptr);
    ~GamesManager() override;

    QVariantList games() const;
    bool gameRunning() const;
    bool gamePaused() const;
    QString runningGameId() const;
    QString runningGameTitle() const;
    QString lastMessage() const;
    QString romRoot() const;
    QString cardsRoot() const;
    bool installerRunning() const;
    QString installerStatus() const;
    int installerProgress() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE QVariantMap gameDetails(const QString &gameId) const;
    Q_INVOKABLE QVariantList compatibleInstallers(const QString &gameId) const;
    Q_INVOKABLE bool moveGameBy(const QString &gameId, int delta);
    Q_INVOKABLE bool moveGameTo(const QString &gameId, int targetIndex);
    Q_INVOKABLE bool setGameSetting(const QString &gameId,
                                    const QString &key,
                                    const QVariant &value);
    Q_INVOKABLE bool launchGame(const QString &gameId);
    Q_INVOKABLE bool launchGameForUser(const QString &gameId,
                                       const QVariantMap &sessionUser);
    Q_INVOKABLE QVariantMap consumeReturnSession();
    Q_INVOKABLE bool installEmulatorAndLaunch(const QString &gameId,
                                              const QString &installerId);
    Q_INVOKABLE bool cancelEmulatorInstall();
    Q_INVOKABLE bool pauseForExitMenu();
    Q_INVOKABLE bool resumeGame();
    Q_INVOKABLE bool stopGame();
    Q_INVOKABLE QString formatBytes(qulonglong bytes) const;

signals:
    void gamesChanged();
    void runtimeChanged();
    void lastMessageChanged();
    void installerChanged();
    void emulatorInstallRequired(QString gameId, QVariantList options);
    void emulatorInstallFinished(bool success, QString message);
    void gameLaunchFailed(QString message);
    void gameStarted(QString gameId, QString title);
    void gameStopped(QString gameId, QString title, bool cleanExit);

private slots:
    void handleProcessStarted();
    void handleProcessFinished(int exitCode, QProcess::ExitStatus status);
    void handleProcessError(QProcess::ProcessError error);
    void collectProcessOutput();
    void collectInstallerOutput();
    void handleInstallerFinished(int exitCode, QProcess::ExitStatus status);
    void handleInstallerError(QProcess::ProcessError error);

private:
    QString m_neutronRoot;
    QString m_romRoot;
    QString m_cardsRoot;
    QString m_statePath;
    QString m_runtimeDirectory;
    QVariantList m_games;
    QStringList m_order;
    QJsonObject m_settings;
    QJsonObject m_usage;
    QProcess m_gameProcess;
    QProcess m_installerProcess;
    QString m_runningGameId;
    QString m_runningGameTitle;
    QString m_lastMessage;
    QString m_processLog;
    QString m_installerStatus;
    QString m_installerLog;
    QString m_pendingInstallGameId;
    QString m_pendingInstallerId;
    int m_installerProgress = 0;
    int m_shellVt = 1;
    int m_gameVt = 2;
    bool m_gamePaused = false;
    bool m_usesProcessGroup = false;
    bool m_stopRequested = false;
    QString m_externalStatePath;
    QString m_externalCommandPath;
    QString m_externalSpecPath;
    QString m_externalSessionId;
    QString m_externalPhase;
    QString m_lastCompletedExternalSessionId;
    QVariantMap m_sessionUser;
    QTimer *m_externalPollTimer = nullptr;
    bool m_externalGameActive = false;
    bool m_externalGamePaused = false;

    void loadState();
    bool saveState() const;
    QVariantMap scanRom(const QString &absolutePath) const;
    QVariantList cloudServiceEntries() const;
    QString detectSystem(const QString &absolutePath, const QString &extension) const;
    QString displaySystem(const QString &system) const;
    QString displayTitle(const QString &path) const;
    QString gameIdForPath(const QString &relativePath) const;
    QString cardForRom(const QString &absolutePath, const QJsonObject &sidecar) const;
    QJsonObject readSidecar(const QString &absolutePath) const;
    QVariantList emulatorOptions(const QString &system, const QJsonObject &sidecar = {}) const;
    QVariantList installerOptionsForSystem(const QString &system,
                                           const QString &serviceId = QString()) const;
    QVariantMap selectedEmulator(const QVariantMap &game) const;
    QVariantMap findGame(const QString &gameId) const;
    int gameIndex(const QString &gameId) const;
    QString findCore(const QStringList &names) const;
    QString executable(const QStringList &names) const;
    bool flatpakApplicationInstalled(const QString &applicationId) const;
    bool prepareLaunch(const QVariantMap &game,
                       const QVariantMap &emulator,
                       QString *program,
                       QStringList *arguments,
                       QString *errorMessage);
    bool beginPreparedLaunch(const QVariantMap &game,
                             const QVariantMap &emulator);
    bool beginExternalLaunch(const QVariantMap &game,
                             const QVariantMap &emulator,
                             const QString &program,
                             const QStringList &arguments,
                             const QProcessEnvironment &environment,
                             const QString &workingDirectory,
                             QString *errorMessage);
    QVariantMap readExternalState() const;
    bool writeExternalState(const QVariantMap &state) const;
    bool writeExternalCommand(const QString &action) const;
    void pollExternalSession();
    QString writeRetroArchConfig(const QVariantMap &game) const;
    int foregroundVt() const;
    int chooseGameVt(int shellVt) const;
    bool switchVt(int vt) const;
    bool signalProcessGroup(int signalNumber) const;
    void setMessage(const QString &message);
    void setInstallerStatus(const QString &message, int progress = -1);
    void updateUsageAfterLaunch(const QString &gameId);
    void rebuildOrderFromGames();
    static QString normalizedSystemToken(const QString &value);
};
