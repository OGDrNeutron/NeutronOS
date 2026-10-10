#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QByteArray>

class DockSecurityManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool hasPasscode READ hasPasscode NOTIFY securityChanged)
    Q_PROPERTY(bool unlocked READ unlocked NOTIFY securityChanged)
    Q_PROPERTY(bool setupMode READ setupMode NOTIFY securityChanged)
    Q_PROPERTY(bool armedMode READ armedMode NOTIFY securityChanged)
    Q_PROPERTY(QString displayCombo READ displayCombo NOTIFY securityChanged)
    Q_PROPERTY(int inputLength READ inputLength NOTIFY securityChanged)
    Q_PROPERTY(bool tamperLocked READ tamperLocked NOTIFY securityChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY securityChanged)

public:
    explicit DockSecurityManager(QObject *parent = nullptr);

    bool hasPasscode() const;
    bool unlocked() const;
    bool setupMode() const;
    bool armedMode() const;
    QString displayCombo() const;
    int inputLength() const;
    bool tamperLocked() const;
    QString statusMessage() const;

    Q_INVOKABLE void beginSetup();
    Q_INVOKABLE void beginUnlock();
    Q_INVOKABLE void clearInput();
    Q_INVOKABLE void backspaceInput();
    Q_INVOKABLE void addInput(const QString &button);

    Q_INVOKABLE bool savePasscode();
    Q_INVOKABLE bool verifyPasscode();

    Q_INVOKABLE void lock();
    Q_INVOKABLE void unlock();

    /*
        Debug/emergency helper while building.
        Does not unlock the dock; only clears the in-memory entry state.
    */
    Q_INVOKABLE void resetInputState();

signals:
    void securityChanged();
    void unlockedChanged();
    void tamperLockTriggered(QString reason);

private:
    bool m_hasPasscode = false;
    bool m_unlocked = false;
    bool m_setupMode = false;
    bool m_armedMode = false;
    bool m_tamperLocked = false;

    QString m_statusMessage;
    QStringList m_input;

    int m_minComboLength = 3;
    int m_maxComboLength = 16;

    int m_pbkdf2Iterations = 180000;
    int m_saltBytes = 32;
    int m_hashBytes = 32;

    QString neutronRootPath() const;
    QString securityDirPath() const;
    QString configPath() const;
    QString markerPath() const;

    void ensureSecurityDir() const;

    bool markerExists() const;
    bool writeMarker() const;

    bool loadPasscode();
    bool writePasscode(const QByteArray &salt,
                       const QByteArray &hash,
                       int tokenCount,
                       int iterations);

    void triggerTamperLock(const QString &reason);

    QString normalizedButton(const QString &button) const;
    QString canonicalCombo(const QStringList &combo) const;

    QByteArray randomBytes(int count) const;
    QByteArray pbkdf2Sha256(const QByteArray &password,
                            const QByteArray &salt,
                            int iterations,
                            int dkLen) const;

    bool constantTimeEquals(const QByteArray &a, const QByteArray &b) const;

    QByteArray readFile(const QString &path) const;
    bool writeSecureFile(const QString &path, const QByteArray &data) const;

    bool verifyComboAgainstStored(const QStringList &combo);
};