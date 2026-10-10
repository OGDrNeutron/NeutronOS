#include "NotificationManager.h"
#include "SecurityManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

#include <sodium.h>
#include <sys/stat.h>
#include <cstdlib>

static void require(bool ok, const char *message)
{
    if (!ok) { qCritical("%s", message); std::exit(1); }
}

static QVariantMap submit(SecurityManager &security, const QString &combo)
{
    QEventLoop loop;
    QVariantMap result;
    QObject::connect(&security, &SecurityManager::authenticatedNotificationClearFinished,
                     &loop, [&](const QVariantMap &value) { result = value; loop.quit(); });
    require(security.beginAuthenticatedNotificationClear(QStringLiteral("neutronos"), combo),
            "real login verifier must accept the active user's request");
    QTimer::singleShot(20000, &loop, &QEventLoop::quit);
    loop.exec();
    require(!result.isEmpty(), "authenticated clear must return an authoritative result");
    return result;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    require(argc == 2, "specify an isolated test-state directory inside the workspace");
    require(sodium_init() >= 0, "libsodium initialization failed");
    const QString base = QString::fromLocal8Bit(argv[1]);
    require(base.startsWith(QStringLiteral("/mnt/NeutronMedia/NeutronOS-Apollo-RC1-Workspace/tests/")),
            "test state must be confined to the release workspace");
    const QString securityRoot = QStringLiteral("/var/lib/neutronos/security");
    const QString userDir = securityRoot + QStringLiteral("/users/echo");
    require(QDir().mkpath(userDir), "isolated Security directory creation failed");
    require(::chmod(securityRoot.toLocal8Bit().constData(), 0700) == 0, "Security root mode");
    require(::chmod((securityRoot + QStringLiteral("/users")).toLocal8Bit().constData(), 0700) == 0,
            "Security users mode");
    require(::chmod(userDir.toLocal8Bit().constData(), 0700) == 0, "Security user mode");

    char encoded[crypto_pwhash_STRBYTES]{};
    const QByteArray canonical("UP|DOWN|LEFT|RIGHT");
    require(crypto_pwhash_str(encoded, canonical.constData(), canonical.size(),
                              crypto_pwhash_OPSLIMIT_INTERACTIVE,
                              crypto_pwhash_MEMLIMIT_INTERACTIVE) == 0,
            "test combo hash generation failed");
    QJsonObject record{{QStringLiteral("version"), 3},
                       {QStringLiteral("username"), QStringLiteral("neutronos")},
                       {QStringLiteral("kdf"), QStringLiteral("argon2id")},
                       {QStringLiteral("scheme"), QStringLiteral("libsodium-crypto-pwhash-str")},
                       {QStringLiteral("tokenCount"), 4},
                       {QStringLiteral("hash"), QString::fromLatin1(encoded)}};
    const QString comboPath = userDir + QStringLiteral("/combo.json");
    QFile comboFile(comboPath);
    require(comboFile.open(QIODevice::WriteOnly | QIODevice::Truncate), "isolated combo fixture open");
    require(comboFile.write(QJsonDocument(record).toJson()) > 0, "isolated combo fixture write");
    comboFile.close();
    require(::chmod(comboPath.toLocal8Bit().constData(), 0600) == 0, "combo fixture mode");
    sodium_memzero(encoded, sizeof encoded);

    const QString auditDir = QStringLiteral("/var/lib/neutronos/security-core");
    require(QDir().mkpath(auditDir), "audit fixture directory");
    QFile audit(auditDir + QStringLiteral("/audit-sentinel"));
    require(audit.open(QIODevice::WriteOnly), "audit fixture open");
    require(audit.write("independent-audit-record") == 24, "audit fixture write");
    audit.close();

    NotificationManager notifications(base + QStringLiteral("/notification-state"));
    SecurityManager security;
    security.setNotificationManager(&notifications);
    require(security.setActiveUsername(QStringLiteral("neutronos")), "active local user binding");
    require(security.loginComboConfigured(), "existing login combo record must load");
    require(notifications.metaObject()->indexOfMethod("clearAllSecurityAuthenticated()") < 0,
            "protected clear must not be QML-invokable");
    require(!security.beginAuthenticatedNotificationClear(QStringLiteral("root"), QStringLiteral("U|D|L|R")),
            "another local user must not clear notifications");

    notifications.publish(QStringLiteral("system"), QStringLiteral("Normal"),
                          QStringLiteral("Routine"), QStringLiteral("info"),
                          QStringLiteral("test"), QString(), {});
    notifications.publish(QStringLiteral("security"), QStringLiteral("Dismissible"),
                          QStringLiteral("Warning"), QStringLiteral("warning"),
                          QStringLiteral("test"), QString(), {});
    notifications.publish(QStringLiteral("security"), QStringLiteral("Critical"),
                          QStringLiteral("Protected"), QStringLiteral("critical"),
                          QStringLiteral("test"), QString(), {});
    notifications.publish(QStringLiteral("security"), QStringLiteral("Policy hold"),
                          QStringLiteral("Non-dismissible"), QStringLiteral("warning"),
                          QStringLiteral("test"), QString(),
                          {{QStringLiteral("dismissible"), false}});
    require(notifications.totalCount() == 4, "four test notifications should publish");
    require(notifications.clearAll(), "R3 must succeed without authentication");
    require(notifications.totalCount() == 2, "R3 must leave exactly protected Security notices");

    int unlocks = 0;
    QObject::connect(&security, &SecurityManager::unlockGranted, &app,
                     [&](const QVariantMap &) { ++unlocks; });
    const QVariantMap rejected = submit(security, QStringLiteral("U|D|L|L"));
    require(!rejected.value(QStringLiteral("success")).toBool(), "incorrect combo must be rejected");
    require(rejected.value(QStringLiteral("removed")).toInt() == 0,
            "incorrect combo must delete nothing");
    require(notifications.totalCount() == 2, "incorrect combo must retain both protected notices");
    require(unlocks == 0, "notification authentication must not unlock the console");

    const QVariantMap accepted = submit(security, QStringLiteral("U|D|L|R"));
    require(accepted.value(QStringLiteral("success")).toBool(), "correct combo must authorize clear");
    require(accepted.value(QStringLiteral("removed")).toInt() == 2,
            "correct combo must remove both protected and non-dismissible notices");
    require(accepted.value(QStringLiteral("remainingSecurity")).toInt() == 0,
            "no Security notification may remain");
    require(accepted.value(QStringLiteral("total")).toInt() == 0 && notifications.totalCount() == 0,
            "R3 followed by authenticated L3 must leave zero notifications");
    require(unlocks == 0, "L3 clear must never emit console unlock");
    require(audit.open(QIODevice::ReadOnly) && audit.readAll() == QByteArray("independent-audit-record"),
            "independent audit history must survive notification deletion");
    return 0;
}
