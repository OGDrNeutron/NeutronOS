#pragma once

#include <QObject>
#include <QByteArray>
#include <QHash>
#include <QList>
#include <QSet>
#include <QString>
#include <QVariant>

class QTcpServer;
class QTcpSocket;
class QTimer;

class RemoteKeyboardManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY stateChanged)
    Q_PROPERTY(QString url READ url NOTIFY stateChanged)
    Q_PROPERTY(QString qrImage READ qrImage NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(quint16 port READ port NOTIFY stateChanged)
    Q_PROPERTY(bool keyboardActive READ keyboardActive NOTIFY stateChanged)
    Q_PROPERTY(bool pairingPanelVisible READ pairingPanelVisible NOTIFY stateChanged)
    Q_PROPERTY(QString pairingCode READ pairingCode NOTIFY stateChanged)
    Q_PROPERTY(int pairingSecondsRemaining READ pairingSecondsRemaining NOTIFY stateChanged)
    Q_PROPERTY(bool pairingCodeActive READ pairingCodeActive NOTIFY stateChanged)
    Q_PROPERTY(int authenticatedClientCount READ authenticatedClientCount NOTIFY stateChanged)

public:
    explicit RemoteKeyboardManager(const QString &neutronRoot, QObject *parent = nullptr);
    ~RemoteKeyboardManager() override;

    bool running() const;
    QString url() const;
    QString qrImage() const;
    QString status() const;
    quint16 port() const;
    bool keyboardActive() const;
    bool pairingPanelVisible() const;
    QString pairingCode() const;
    int pairingSecondsRemaining() const;
    bool pairingCodeActive() const;
    int authenticatedClientCount() const;

    // Compatibility API retained for existing callers.
    Q_INVOKABLE bool start(const QString &initialText = QString());
    Q_INVOKABLE void stop();
    Q_INVOKABLE bool regenerate(const QString &initialText = QString());
    Q_INVOKABLE void setInitialText(const QString &text);
    Q_INVOKABLE QVariant keyboardSetting(const QString &key, const QVariant &fallback = QVariant()) const;
    Q_INVOKABLE bool saveKeyboardSetting(const QString &key, const QVariant &value);

    // Controller-first Remote Keyboard API used by the shared VKB.
    Q_INVOKABLE void setKeyboardActive(bool active);
    Q_INVOKABLE bool showPairingPanel();
    Q_INVOKABLE void hidePairingPanel();
    Q_INVOKABLE QString generatePairingCode();

signals:
    void stateChanged();
    void textSubmitted(const QString &text);
    void backspaceRequested(int count);
    void enterRequested();

private:
    QString m_neutronRoot;
    QTcpServer *m_server = nullptr;
    QTimer *m_pairingTimer = nullptr;
    QTimer *m_graceTimer = nullptr;
    QString m_url;
    QString m_qrImage;
    QString m_status;
    QString m_initialText;
    QString m_pairingCode;
    qint64 m_pairingExpiresAtMs = 0;
    bool m_keyboardActive = false;
    bool m_pairingPanelVisible = false;
    quint16 m_port = 0;
    QHash<QTcpSocket *, QByteArray> m_buffers;
    QSet<QString> m_authenticatedSessions;
    int m_lanFailedPairingAttempts = 0;
    int m_tailscaleFailedPairingAttempts = 0;
    qint64 m_authLockedUntilMs = 0;

    QString preferredAddress() const;
    QString stateDirectory() const;
    QString settingsPath() const;
    QString makeSessionToken() const;
    QString makePairingCode() const;
    bool ensureServerRunning();
    void clearPairingCode();
    void expireGraceSession();
    void setStatus(const QString &status);
    bool authLocked() const;
    int authLockSecondsRemaining() const;
    void refreshAuthLockout();
    bool peerIsTailscale(QTcpSocket *socket) const;
    int authAttemptLimit(QTcpSocket *socket) const;
    int authFailedAttempts(QTcpSocket *socket) const;
    void recordAuthFailure(QTcpSocket *socket);
    void resetAuthFailures();

    QByteArray pairingPageHtml() const;
    QByteArray keyboardPageHtml() const;
    QByteArray lockedPageHtml() const;

    void handleNewConnection();
    void handleReadyRead(QTcpSocket *socket);
    void processRequest(QTcpSocket *socket, const QByteArray &request);

    QString headerValue(const QByteArray &request, const QByteArray &headerName) const;
    QString sessionFromRequest(const QByteArray &request) const;
    bool sessionValid(const QByteArray &request) const;

    void sendResponse(QTcpSocket *socket,
                      int statusCode,
                      const QByteArray &statusText,
                      const QByteArray &contentType,
                      const QByteArray &body,
                      const QList<QByteArray> &extraHeaders = {});
};
