#include "DockSecurityManager.h"

#include <QCryptographicHash>
#include <QMessageAuthenticationCode>
#include <QRandomGenerator>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QDebug>

DockSecurityManager::DockSecurityManager(QObject *parent)
    : QObject(parent)
{
    ensureSecurityDir();

    m_hasPasscode = loadPasscode();

    if (markerExists()) {
        if (!m_hasPasscode) {
            triggerTamperLock(QStringLiteral("Hidden dock security file missing or corrupt"));
        }
    } else if (!m_hasPasscode) {
        /*
            First-time setup is allowed.
        */
        m_statusMessage = QStringLiteral("Hidden dock setup required");
    } else {
        m_hasPasscode = false;
        triggerTamperLock(QStringLiteral("Hidden dock security marker missing"));
    }
}

bool DockSecurityManager::hasPasscode() const
{
    return m_hasPasscode;
}

bool DockSecurityManager::unlocked() const
{
    return m_unlocked;
}

bool DockSecurityManager::setupMode() const
{
    return m_setupMode;
}

bool DockSecurityManager::armedMode() const
{
    return m_armedMode;
}

QString DockSecurityManager::displayCombo() const
{
    return m_input.isEmpty() ? QString() : m_input.join(QStringLiteral("  "));
}

int DockSecurityManager::inputLength() const
{
    return m_input.length();
}

bool DockSecurityManager::tamperLocked() const
{
    return m_tamperLocked;
}

QString DockSecurityManager::statusMessage() const
{
    return m_statusMessage;
}

/*
    ============================================================
                            PATHS
    ============================================================
*/

QString DockSecurityManager::neutronRootPath() const
{
    const QString echoRoot = QStringLiteral("/opt/neutronos");

    if (QFileInfo::exists(echoRoot))
        return echoRoot;

    return QDir::homePath() + QStringLiteral("/NeutronOS");
}

QString DockSecurityManager::securityDirPath() const
{
    return neutronRootPath() + QStringLiteral("/state/security");
}

QString DockSecurityManager::configPath() const
{
    return securityDirPath() + QStringLiteral("/hidden_dock_combo.hash");
}

QString DockSecurityManager::markerPath() const
{
    return securityDirPath() + QStringLiteral("/hidden_dock_initialized.lock");
}

void DockSecurityManager::ensureSecurityDir() const
{
    QDir().mkpath(neutronRootPath());
    QDir().mkpath(neutronRootPath() + QStringLiteral("/state"));
    QDir().mkpath(securityDirPath());

    QFile::setPermissions(
        securityDirPath(),
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner |
        QFileDevice::ExeOwner
    );
}

/*
    ============================================================
                            PUBLIC FLOW
    ============================================================
*/

void DockSecurityManager::beginSetup()
{
    if (m_tamperLocked) {
        m_statusMessage = QStringLiteral("Hidden dock security is tamper locked");
        emit securityChanged();
        return;
    }

    m_input.clear();
    m_setupMode = true;
    m_armedMode = false;
    m_unlocked = false;
    m_statusMessage = QStringLiteral("Create hidden dock combo");

    emit securityChanged();
}

void DockSecurityManager::beginUnlock()
{
    if (m_tamperLocked) {
        m_statusMessage = QStringLiteral("Hidden dock security is tamper locked");
        emit securityChanged();
        return;
    }

    if (!m_hasPasscode) {
        beginSetup();
        return;
    }

    m_input.clear();
    m_setupMode = false;
    m_armedMode = true;
    m_unlocked = false;
    m_statusMessage = QStringLiteral("Enter hidden dock combo");

    emit securityChanged();
}

void DockSecurityManager::clearInput()
{
    m_input.clear();
    emit securityChanged();
}

void DockSecurityManager::backspaceInput()
{
    if (!m_input.isEmpty()) {
        m_input.removeLast();
        emit securityChanged();
    }
}

void DockSecurityManager::addInput(const QString &button)
{
    if (m_tamperLocked)
        return;

    const QString clean = normalizedButton(button);

    if (clean.isEmpty())
        return;

    if (m_input.length() >= m_maxComboLength)
        m_input.removeFirst();

    m_input.append(clean);

    if (m_setupMode)
        m_statusMessage = QStringLiteral("Creating combo");
    else if (m_armedMode)
        m_statusMessage = QStringLiteral("Checking combo");

    emit securityChanged();
}

bool DockSecurityManager::savePasscode()
{
    if (m_tamperLocked) {
        m_statusMessage = QStringLiteral("Hidden dock security is tamper locked");
        emit securityChanged();
        return false;
    }

    if (m_input.length() < m_minComboLength) {
        m_statusMessage = QStringLiteral("Combo too short");
        emit securityChanged();
        return false;
    }

    if (m_input.length() > m_maxComboLength) {
        m_statusMessage = QStringLiteral("Combo too long");
        emit securityChanged();
        return false;
    }

    const QString canonical = canonicalCombo(m_input);
    const QByteArray salt = randomBytes(m_saltBytes);
    const QByteArray hash = pbkdf2Sha256(
        canonical.toUtf8(),
        salt,
        m_pbkdf2Iterations,
        m_hashBytes
    );

    if (!writePasscode(salt, hash, m_input.length(), m_pbkdf2Iterations)) {
        m_statusMessage = QStringLiteral("Could not save hidden dock combo");
        emit securityChanged();
        return false;
    }

    if (!writeMarker()) {
        m_statusMessage = QStringLiteral("Could not write hidden dock marker");
        emit securityChanged();
        return false;
    }

    m_hasPasscode = true;
    m_setupMode = false;
    m_armedMode = false;
    m_unlocked = true;
    m_input.clear();
    m_statusMessage = QStringLiteral("Hidden dock unlocked");

    emit unlockedChanged();
    emit securityChanged();

    return true;
}

bool DockSecurityManager::verifyPasscode()
{
    if (m_tamperLocked) {
        m_statusMessage = QStringLiteral("Hidden dock security is tamper locked");
        emit securityChanged();
        return false;
    }

    if (!m_hasPasscode) {
        m_statusMessage = QStringLiteral("Hidden dock combo not configured");
        emit securityChanged();
        return false;
    }

    if (m_input.isEmpty()) {
        m_statusMessage = QStringLiteral("Enter combo first");
        emit securityChanged();
        return false;
    }

    const bool ok = verifyComboAgainstStored(m_input);

    if (ok) {
        m_unlocked = true;
        m_armedMode = false;
        m_setupMode = false;
        m_input.clear();
        m_statusMessage = QStringLiteral("Hidden dock unlocked");

        emit unlockedChanged();
        emit securityChanged();
        return true;
    }

    m_unlocked = false;
    m_input.clear();
    m_statusMessage = QStringLiteral("Incorrect hidden dock combo");

    emit securityChanged();
    return false;
}

void DockSecurityManager::lock()
{
    m_unlocked = false;
    m_armedMode = false;
    m_setupMode = false;
    m_input.clear();
    m_statusMessage = m_hasPasscode
                      ? QStringLiteral("Hidden dock locked")
                      : QStringLiteral("Hidden dock setup required");

    emit unlockedChanged();
    emit securityChanged();
}

void DockSecurityManager::unlock()
{
    if (m_tamperLocked) {
        m_statusMessage = QStringLiteral("Hidden dock security is tamper locked");
        emit securityChanged();
        return;
    }

    /*
        Used by QML after a modal has already verified/unlocked.
        Do not use this as a password bypass in backend-only flows.
    */
    m_unlocked = true;
    m_armedMode = false;
    m_setupMode = false;
    m_input.clear();
    m_statusMessage = QStringLiteral("Hidden dock unlocked");

    emit unlockedChanged();
    emit securityChanged();
}

void DockSecurityManager::resetInputState()
{
    m_input.clear();
    m_setupMode = false;
    m_armedMode = false;

    if (!m_unlocked)
        m_statusMessage = m_hasPasscode
                          ? QStringLiteral("Hidden dock locked")
                          : QStringLiteral("Hidden dock setup required");

    emit securityChanged();
}

/*
    ============================================================
                            STORAGE
    ============================================================
*/

QByteArray DockSecurityManager::readFile(const QString &path) const
{
    QFile file(path);

    if (!file.open(QIODevice::ReadOnly))
        return {};

    const QByteArray data = file.readAll();
    file.close();

    return data;
}

bool DockSecurityManager::writeSecureFile(const QString &path, const QByteArray &data) const
{
    ensureSecurityDir();

    const QString tempPath = path + QStringLiteral(".tmp");

    QFile file(tempPath);

    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "DockSecurityManager failed to write temp file:" << tempPath;
        return false;
    }

    file.write(data);
    file.flush();
    file.close();

    QFile::setPermissions(
        tempPath,
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner
    );

    if (QFile::exists(path))
        QFile::remove(path);

    if (!QFile::rename(tempPath, path)) {
        QFile::remove(tempPath);
        qWarning() << "DockSecurityManager failed to rename temp file:" << path;
        return false;
    }

    QFile::setPermissions(
        path,
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner
    );

    return true;
}

bool DockSecurityManager::markerExists() const
{
    return QFileInfo::exists(markerPath());
}

bool DockSecurityManager::writeMarker() const
{
    const QByteArray data =
        QByteArray("NeutronOS hidden dock initialized\n") +
        QDateTime::currentDateTimeUtc().toString(Qt::ISODate).toUtf8() +
        QByteArray("\n");

    return writeSecureFile(markerPath(), data);
}

bool DockSecurityManager::loadPasscode()
{
    const QByteArray data = readFile(configPath());

    if (data.isEmpty())
        return false;

    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError || !doc.isObject())
        return false;

    const QJsonObject obj = doc.object();

    const QString kdf = obj.value(QStringLiteral("kdf")).toString();
    const int iterations = obj.value(QStringLiteral("iterations")).toInt();
    const int tokenCount = obj.value(QStringLiteral("tokenCount")).toInt();

    const QByteArray salt =
        QByteArray::fromBase64(obj.value(QStringLiteral("salt")).toString().toLatin1());

    const QByteArray hash =
        QByteArray::fromBase64(obj.value(QStringLiteral("hash")).toString().toLatin1());

    if (kdf != QStringLiteral("pbkdf2-sha256"))
        return false;

    if (iterations <= 0 || tokenCount < m_minComboLength)
        return false;

    if (salt.isEmpty() || hash.isEmpty())
        return false;

    return true;
}

bool DockSecurityManager::writePasscode(const QByteArray &salt,
                                        const QByteArray &hash,
                                        int tokenCount,
                                        int iterations)
{
    QJsonObject obj;

    obj[QStringLiteral("version")] = 1;
    obj[QStringLiteral("kdf")] = QStringLiteral("pbkdf2-sha256");
    obj[QStringLiteral("iterations")] = iterations;
    obj[QStringLiteral("tokenCount")] = tokenCount;
    obj[QStringLiteral("salt")] = QString::fromLatin1(salt.toBase64());
    obj[QStringLiteral("hash")] = QString::fromLatin1(hash.toBase64());
    obj[QStringLiteral("createdAt")] =
        QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    return writeSecureFile(
        configPath(),
        QJsonDocument(obj).toJson(QJsonDocument::Indented)
    );
}

void DockSecurityManager::triggerTamperLock(const QString &reason)
{
    m_tamperLocked = true;
    m_unlocked = false;
    m_setupMode = false;
    m_armedMode = false;
    m_input.clear();
    m_statusMessage = reason;

    emit tamperLockTriggered(reason);
    emit securityChanged();
}

/*
    ============================================================
                            COMBO / HASHING
    ============================================================
*/

QString DockSecurityManager::normalizedButton(const QString &button) const
{
    QString clean = button.trimmed().toUpper();

    if (clean == QStringLiteral("PRIMARY") ||
        clean == QStringLiteral("CROSS") ||
        clean == QStringLiteral("PS_CROSS")) {
        clean = QStringLiteral("X");
    } else if (clean == QStringLiteral("CANCEL") ||
               clean == QStringLiteral("CIRCLE") ||
               clean == QStringLiteral("PS_CIRCLE")) {
        clean = QStringLiteral("O");
    } else if (clean == QStringLiteral("TRI") ||
               clean == QStringLiteral("PS_TRIANGLE")) {
        clean = QStringLiteral("TRIANGLE");
    } else if (clean == QStringLiteral("PS_SQUARE")) {
        clean = QStringLiteral("SQUARE");
    } else if (clean == QStringLiteral("OPTIONS") ||
               clean == QStringLiteral("SETTINGS") ||
               clean == QStringLiteral("MENU")) {
        clean = QStringLiteral("START");
    } else if (clean == QStringLiteral("SHARE") ||
               clean == QStringLiteral("CREATE")) {
        clean = QStringLiteral("SELECT");
    } else if (clean == QStringLiteral("PS") ||
               clean == QStringLiteral("PLAYSTATION") ||
               clean == QStringLiteral("GUIDE")) {
        clean = QStringLiteral("SYSTEM");
    } else if (clean == QStringLiteral("UP")) {
        clean = QStringLiteral("U");
    } else if (clean == QStringLiteral("DOWN")) {
        clean = QStringLiteral("D");
    } else if (clean == QStringLiteral("LEFT")) {
        clean = QStringLiteral("L");
    } else if (clean == QStringLiteral("RIGHT")) {
        clean = QStringLiteral("R");
    }

    const QStringList allowed = {
        QStringLiteral("U"),
        QStringLiteral("D"),
        QStringLiteral("L"),
        QStringLiteral("R"),
        QStringLiteral("X"),
        QStringLiteral("O"),
        QStringLiteral("SQUARE"),
        QStringLiteral("TRIANGLE"),
        QStringLiteral("START"),
        QStringLiteral("SELECT"),
        QStringLiteral("SYSTEM"),
        QStringLiteral("L1"),
        QStringLiteral("R1"),
        QStringLiteral("L2"),
        QStringLiteral("R2"),
        QStringLiteral("L3"),
        QStringLiteral("R3")
    };

    return allowed.contains(clean) ? clean : QString();
}

QString DockSecurityManager::canonicalCombo(const QStringList &combo) const
{
    QStringList clean;

    for (const QString &button : combo) {
        const QString normalized = normalizedButton(button);

        if (!normalized.isEmpty())
            clean.append(normalized);
    }

    return clean.join(QStringLiteral("|"));
}

QByteArray DockSecurityManager::randomBytes(int count) const
{
    QByteArray bytes;
    bytes.resize(qMax(1, count));

    for (int i = 0; i < bytes.size(); ++i) {
        bytes[i] = static_cast<char>(QRandomGenerator::global()->generate() & 0xFF);
    }

    return bytes;
}

QByteArray DockSecurityManager::pbkdf2Sha256(const QByteArray &password,
                                             const QByteArray &salt,
                                             int iterations,
                                             int dkLen) const
{
    const int hashLen = 32;
    const int blockCount = (dkLen + hashLen - 1) / hashLen;

    QByteArray derived;
    derived.reserve(blockCount * hashLen);

    for (int block = 1; block <= blockCount; ++block) {
        QByteArray saltBlock = salt;

        saltBlock.append(static_cast<char>((block >> 24) & 0xFF));
        saltBlock.append(static_cast<char>((block >> 16) & 0xFF));
        saltBlock.append(static_cast<char>((block >> 8) & 0xFF));
        saltBlock.append(static_cast<char>(block & 0xFF));

        QByteArray u = QMessageAuthenticationCode::hash(
            saltBlock,
            password,
            QCryptographicHash::Sha256
        );

        QByteArray t = u;

        for (int i = 1; i < iterations; ++i) {
            u = QMessageAuthenticationCode::hash(
                u,
                password,
                QCryptographicHash::Sha256
            );

            for (int j = 0; j < t.size(); ++j) {
                t[j] = static_cast<char>(
                    static_cast<unsigned char>(t.at(j)) ^
                    static_cast<unsigned char>(u.at(j))
                );
            }
        }

        derived.append(t);
    }

    derived.truncate(dkLen);
    return derived;
}

bool DockSecurityManager::constantTimeEquals(const QByteArray &a, const QByteArray &b) const
{
    if (a.size() != b.size())
        return false;

    unsigned char diff = 0;

    for (int i = 0; i < a.size(); ++i) {
        diff |= static_cast<unsigned char>(a.at(i)) ^
                static_cast<unsigned char>(b.at(i));
    }

    return diff == 0;
}

bool DockSecurityManager::verifyComboAgainstStored(const QStringList &combo)
{
    const QByteArray data = readFile(configPath());

    if (data.isEmpty())
        return false;

    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &error);

    if (error.error != QJsonParseError::NoError || !doc.isObject())
        return false;

    const QJsonObject obj = doc.object();

    const int iterations = obj.value(QStringLiteral("iterations")).toInt(m_pbkdf2Iterations);
    const int tokenCount = obj.value(QStringLiteral("tokenCount")).toInt(0);

    const QByteArray salt =
        QByteArray::fromBase64(obj.value(QStringLiteral("salt")).toString().toLatin1());

    const QByteArray expectedHash =
        QByteArray::fromBase64(obj.value(QStringLiteral("hash")).toString().toLatin1());

    if (iterations <= 0 || tokenCount <= 0 || salt.isEmpty() || expectedHash.isEmpty())
        return false;

    if (combo.length() != tokenCount)
        return false;

    const QString canonical = canonicalCombo(combo);

    const QByteArray candidateHash = pbkdf2Sha256(
        canonical.toUtf8(),
        salt,
        iterations,
        expectedHash.size()
    );

    return constantTimeEquals(candidateHash, expectedHash);
}