#pragma once
#include <QPointer>
#include "GameLibrary.h"
#include "GameArtwork.h"
#include "RuntimeAdapters.h"
#include <QObject>
#include <QProcess>
#include <QLocalSocket>
#include <QPointer>
#include <QQuickWindow>
#include <QTimer>
#include <QElapsedTimer>
namespace GeminiGames {
class OwnedProcess final : public QObject {
    Q_OBJECT
public:
    explicit OwnedProcess(QObject *parent=nullptr);
    bool start(const QString &program,const QStringList &arguments,const QProcessEnvironment &environment,const QString &directory,const QString &log);
    bool signal(int number);
    bool running() const { return m_process.state()!=QProcess::NotRunning; }
    qint64 pid() const { return m_process.processId(); }
    void gracefulStop(int timeoutMs=5000);
    void forceStop();
signals:
    void started();
    void exited(int exitCode,bool normal);
    void failed(QString message);
    void stopTimedOut();
private:
    QProcess m_process;
    QTimer m_timeout;
};
class GeminiGamesBackend final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap managerState READ managerState NOTIFY managerChanged)
    Q_PROPERTY(bool managerBusy READ managerBusy NOTIFY managerChanged)
    Q_PROPERTY(QVariantList runtimeChoices READ runtimeChoices NOTIFY managerChanged)
    Q_PROPERTY(QVariantList artworkFiles READ artworkFiles NOTIFY changed)
    Q_PROPERTY(QString artworkDirectory READ artworkDirectory NOTIFY changed)
    Q_PROPERTY(QStringList artworkFormats READ artworkFormats NOTIFY changed)
    Q_PROPERTY(QVariantList games READ games NOTIFY changed)
    Q_PROPERTY(QVariantList roots READ roots NOTIFY changed)
    Q_PROPERTY(QVariantList messages READ messages NOTIFY changed)
    Q_PROPERTY(QVariantList installedRuntimes READ installedRuntimes NOTIFY changed)
    Q_PROPERTY(QVariantMap hardware READ hardware NOTIFY changed)
    Q_PROPERTY(QVariantMap preferences READ preferences NOTIFY changed)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanStatusChanged)
    Q_PROPERTY(int scannedEntries READ scannedEntries NOTIFY scanStatusChanged)
    Q_PROPERTY(bool gameActive READ gameActive NOTIFY sessionChanged)
    Q_PROPERTY(bool backgrounded READ backgrounded NOTIFY sessionChanged)
    Q_PROPERTY(QVariantList controllers READ controllers NOTIFY sessionChanged)
    Q_PROPERTY(bool menuOpen READ menuOpen NOTIFY sessionChanged)
    Q_PROPERTY(bool stopTimedOut READ stopTimedOut NOTIFY sessionChanged)
    Q_PROPERTY(bool gamingMode READ gamingMode NOTIFY sessionChanged)
    Q_PROPERTY(QString gameTitle READ gameTitle NOTIFY sessionChanged)
    Q_PROPERTY(QString menuSource READ menuSource WRITE setMenuSource NOTIFY sessionChanged)
    Q_PROPERTY(int controllerCount READ controllerCount NOTIFY sessionChanged)
public:
    explicit GeminiGamesBackend(QObject *parent=nullptr);
    ~GeminiGamesBackend() override;
    void setSessionIdentity(QObject *identity) { m_identity=identity; }
    Q_INVOKABLE void setSessionIntegrationAvailable(bool available) { m_sessionIntegrationAvailable=available; }
    Q_INVOKABLE void setSystemAccess(bool available);
    Q_INVOKABLE bool initialize();
    Q_INVOKABLE void accountChanged();
    Q_INVOKABLE void startFooterCountdown() { m_footerTimer.start(10000); }
    Q_INVOKABLE void cancelFooterCountdown() { m_footerTimer.stop(); }
    Q_INVOKABLE QVariantMap browseFolders(const QString &path) const;
    Q_INVOKABLE bool addFolder(const QString &path);
    Q_INVOKABLE bool editFolder(int index,const QString &path);
    Q_INVOKABLE bool removeFolder(int index);
    Q_INVOKABLE void rescan();
    Q_INVOKABLE void cancelIndexing() { if(ownsAccount()&&m_library)m_library->cancelScan(); }
    int scannedEntries() const { return ownsAccount()&&m_library?m_library->scannedEntries():0; }
    Q_INVOKABLE void refreshRuntimes() { emit changed(); if(!managerBusy())managerOperation({{"action","status"}}); }
    void setManagerProgram(const QString &path) { m_managerProgram=path; }
    Q_INVOKABLE bool managerOperation(const QVariantMap &request);
    Q_INVOKABLE void cancelManager();
    Q_INVOKABLE void installerControl(const QString &action,const QString &text=QString());
    QVariantMap managerState() const { return ownsAccount()?m_managerState:QVariantMap(); }
    bool managerBusy() const { return m_manager.state()!=QProcess::NotRunning; }
    QVariantList runtimeChoices() const { return ownsAccount()?m_runtimeChoices:QVariantList(); }
    Q_INVOKABLE void refreshArtwork();
    Q_INVOKABLE bool setArtworkAssignment(const QString &id,const QString &path);
    Q_INVOKABLE bool favorite(const QString &id,bool value);
    Q_INVOKABLE bool updateMetadata(const QString &id,const QString &field,const QString &value);
    Q_INVOKABLE bool choosePlatform(const QString &id,const QString &kind);
    Q_INVOKABLE QVariantList recommendations(const QString &id) const;
    Q_INVOKABLE bool configure(const QString &id,const QVariantMap &configuration,bool approved);
    Q_INVOKABLE bool play(const QString &id);
    Q_INVOKABLE bool resumeGame();
    Q_INVOKABLE void closeGame();
    Q_INVOKABLE void forceCloseGame();
    Q_INVOKABLE bool prepareSwitch();
    Q_INVOKABLE void acknowledge(int index);
    Q_INVOKABLE void notify(const QString &message,bool critical=false);
    Q_INVOKABLE bool setPreference(const QString &name,const QVariant &value);
    Q_INVOKABLE bool setControllerProfile(const QString &id,const QVariantMap &profile);
    Q_INVOKABLE void setUiState(const QVariantMap &state);
    Q_INVOKABLE QVariantMap uiState() const { return ownsAccount()?m_uiState:QVariantMap(); }
    Q_INVOKABLE void attachWindow(QObject *window);
    Q_INVOKABLE bool controllerPress(const QString &action);
    Q_INVOKABLE bool controllerRelease(const QString &action);
    Q_INVOKABLE QVariantMap resourceSample() const;
    Q_INVOKABLE QString logPath() const;
    QVariantList games() const { return ownsAccount()?m_presentedGames:QVariantList(); }
    Q_INVOKABLE QVariantList gameSnapshot() const { return games(); }
    QVariantList artworkFiles()const{return ownsAccount()&&m_artwork?m_artwork->files():QVariantList();}
    QString artworkDirectory()const{return ownsAccount()&&m_artwork?m_artwork->directory():QString();}
    QStringList artworkFormats()const{return ownsAccount()&&m_artwork?m_artwork->formats():QStringList();}
    QVariantList roots() const { return ownsAccount()? (m_library?m_library->roots():QVariantList()):QVariantList(); }
    QVariantList messages() const { return ownsAccount()?m_messages:QVariantList(); }
    QVariantList installedRuntimes() const { return RuntimeAdapters::runtimes(); }
    QVariantMap hardware() const { return m_hardware; }
    QVariantMap preferences() const { return ownsAccount()?m_preferences:QVariantMap(); }
    bool scanning() const { return ownsAccount()&&m_library&&m_library->scanning(); }
    bool gameActive() const { return m_process.running()||m_launchPending; }
    bool backgrounded() const {return m_backgrounded;}
    QVariantList controllers() const {return ownsAccount()?m_controllers:QVariantList();}
    bool menuOpen() const { return ownsAccount()&&m_menuOpen; }
    bool stopTimedOut() const { return ownsAccount()&&m_stopTimedOut; }
    bool gamingMode() const { return m_gamingMode; }
    QString gameTitle() const { return ownsAccount()?m_current.value("title").toString():QString(); }
    QString menuSource() const { return m_menuSource; }
    void setMenuSource(const QString &value) { m_menuSource=value;emit sessionChanged(); }
    int controllerCount()const{return ownsAccount()?m_controllerCount:0;}
signals:
    void scanStatusChanged();
    void managerChanged();
    void managerFinished(QString action,bool success,QVariantMap result);
    void runtimeMissing(QString gameId,QString runtime);
    void inputReset();
    void footerTimeout();
    void changed();
    void sessionChanged();
    void modalAction(QString action);
    void backgroundAction(QString action,bool pressed);
    void messagePublished(QString message,bool critical);
    void restoreRequested();
private:
    void refreshGamePresentation();
    QVariantList m_presentedGames;
    QPointer<QObject> m_identity;
    QPointer<GameLibrary> m_library;
    QPointer<GameArtwork> m_artwork;
    QProcess m_manager;
    QString m_managerProgram,m_managerAction;
    QByteArray m_managerBytes;
    QVariantMap m_managerState;
    QVariantList m_runtimeChoices;
    bool m_managerResult=false;
    void consumeManager();
    OwnedProcess m_process;
    QLocalSocket m_input;
    QByteArray m_inputBytes;
    QVariantList m_messages,m_controllers;
    QVariantMap m_hardware,m_preferences,m_uiState,m_current;
    LaunchPlan m_plan;
    QPointer<QQuickWindow> m_window;
    QString m_home,m_menuSource;
    QTimer m_launchTimeout,m_sampleTimer,m_footerTimer;
    QElapsedTimer m_homeHold;
    QTimer m_homeTimer;
    bool m_menuOpen=false,m_stopTimedOut=false,m_gamingMode=false,m_launchPending=false,m_paused=false,m_backgrounded=false,m_closing=false;
    bool m_sessionIntegrationAvailable=false,m_systemAccess=false;
    int m_controllerCount=0;
    bool ownsAccount() const;
    void inputCommand(const QString &command,const QVariantMap &extra={});
    void consumeInput();
    bool launchPrepared();
    void openMenu();
    void restore();
    void savePreferences();
    void recordSample(const QString &phase);
};
}
