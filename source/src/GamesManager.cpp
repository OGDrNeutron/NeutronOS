#include "HumanAccountPolicy.h"
#include "GamesManager.h"

#include <QCryptographicHash>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcessEnvironment>
#include <QHash>
#include <QSet>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>
#include <QTimer>
#include <QUrl>

#include <algorithm>
#include <utility>
#include <csignal>
#include <sys/types.h>

namespace {

const QSet<QString> SupportedExtensions = {
    QStringLiteral("z64"), QStringLiteral("n64"), QStringLiteral("v64"),
    QStringLiteral("cue"), QStringLiteral("chd"), QStringLiteral("pbp"), QStringLiteral("bin"),
    QStringLiteral("sfc"), QStringLiteral("smc"), QStringLiteral("fig"),
    QStringLiteral("nes"), QStringLiteral("fds"),
    QStringLiteral("gba"), QStringLiteral("gb"), QStringLiteral("gbc"),
    QStringLiteral("nds"),
    QStringLiteral("md"), QStringLiteral("gen"), QStringLiteral("smd"), QStringLiteral("sms"), QStringLiteral("gg"),
    QStringLiteral("gcm"), QStringLiteral("rvz"), QStringLiteral("wbfs"), QStringLiteral("wad"),
    QStringLiteral("cso"), QStringLiteral("iso"),
    QStringLiteral("zip"), QStringLiteral("7z"),
    QStringLiteral("swf")
};

QString humanDate(const QDateTime &value)
{
    if (!value.isValid())
        return QStringLiteral("Never");
    return value.toLocalTime().toString(QStringLiteral("MMM d, yyyy  h:mm AP"));
}

QString safeString(const QJsonObject &object, const QString &key)
{
    return object.value(key).toString().trimmed();
}

} // namespace

GamesManager::GamesManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent),
      m_neutronRoot(QDir(neutronRoot).absolutePath()),
      m_romRoot(QStringLiteral("/var/lib/neutronos/games-prelogin/roms")),
      m_cardsRoot(QStringLiteral("/var/lib/neutronos/games-prelogin/cards")),
      m_statePath(QStringLiteral("/var/lib/neutronos/games-prelogin/games.json")),
      m_runtimeDirectory(QStringLiteral("/var/lib/neutronos/apps/games-runtime")),
      m_externalStatePath(QDir(m_runtimeDirectory).filePath(QStringLiteral("external-session.json"))),
      m_externalCommandPath(QDir(m_runtimeDirectory).filePath(QStringLiteral("external-command.json"))),
      m_externalSpecPath(QDir(m_runtimeDirectory).filePath(QStringLiteral("external-launch.json")))
{
    QDir().mkpath(m_runtimeDirectory);
    if (!HumanHome::path().isEmpty()) humanSessionChanged();

    connect(&m_gameProcess, &QProcess::started,
            this, &GamesManager::handleProcessStarted);
    connect(&m_gameProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &GamesManager::handleProcessFinished);
    connect(&m_gameProcess, &QProcess::errorOccurred,
            this, &GamesManager::handleProcessError);
    connect(&m_gameProcess, &QProcess::readyReadStandardOutput,
            this, &GamesManager::collectProcessOutput);
    connect(&m_gameProcess, &QProcess::readyReadStandardError,
            this, &GamesManager::collectProcessOutput);

    m_gameProcess.setProcessChannelMode(QProcess::MergedChannels);

    connect(&m_installerProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, &GamesManager::handleInstallerFinished);
    connect(&m_installerProcess, &QProcess::errorOccurred,
            this, &GamesManager::handleInstallerError);
    connect(&m_installerProcess, &QProcess::readyReadStandardOutput,
            this, &GamesManager::collectInstallerOutput);
    connect(&m_installerProcess, &QProcess::readyReadStandardError,
            this, &GamesManager::collectInstallerOutput);
    m_installerProcess.setProcessChannelMode(QProcess::MergedChannels);

    m_externalPollTimer = new QTimer(this);
    m_externalPollTimer->setInterval(300);
    connect(m_externalPollTimer, &QTimer::timeout,
            this, &GamesManager::pollExternalSession);
    m_externalPollTimer->start();

    pollExternalSession();
    loadState();
    QTimer::singleShot(2400, this, &GamesManager::refresh);
}

void GamesManager::humanSessionChanged()
{
    m_order.clear(); m_settings = QJsonObject(); m_usage = QJsonObject();
    const QString home = HumanHome::path();
    if (home.isEmpty()) {
        m_romRoot = QStringLiteral("/var/lib/neutronos/games-prelogin/roms");
        m_cardsRoot = QStringLiteral("/var/lib/neutronos/games-prelogin/cards");
        m_statePath = QStringLiteral("/var/lib/neutronos/games-prelogin/games.json");
        m_games.clear();
        refresh();
        return;
    }
    m_romRoot = home + QStringLiteral("/Games/roms");
    m_cardsRoot = home + QStringLiteral("/Games/cards");
    m_statePath = home + QStringLiteral("/apps/games/games.json");
    m_runtimeDirectory = home + QStringLiteral("/apps/games/runtime");
    m_externalStatePath = m_runtimeDirectory + QStringLiteral("/external-session.json");
    m_externalCommandPath = m_runtimeDirectory + QStringLiteral("/external-command.json");
    m_externalSpecPath = m_runtimeDirectory + QStringLiteral("/external-launch.json");
    for (const QString &path : {m_romRoot, m_cardsRoot, QFileInfo(m_statePath).absolutePath(),
                              m_runtimeDirectory, m_runtimeDirectory + QStringLiteral("/saves"),
                              m_runtimeDirectory + QStringLiteral("/states")}) QDir().mkpath(path);
    loadState();
    refresh();
}

GamesManager::~GamesManager()
{
    if (installerRunning())
        cancelEmulatorInstall();
    // An external game session intentionally stops neutronos.service so that
    // RetroArch can become the only DRM/KMS owner.  Never terminate that
    // independent systemd session from this object's destructor.
    if (m_gameProcess.state() != QProcess::NotRunning)
        stopGame();
}

QVariantList GamesManager::games() const { return m_games; }
bool GamesManager::gameRunning() const
{
    return m_externalGameActive || m_gameProcess.state() != QProcess::NotRunning;
}
bool GamesManager::gamePaused() const { return m_externalGamePaused || m_gamePaused; }
QString GamesManager::runningGameId() const { return m_runningGameId; }
QString GamesManager::runningGameTitle() const { return m_runningGameTitle; }
QString GamesManager::lastMessage() const { return m_lastMessage; }
QString GamesManager::romRoot() const { return m_romRoot; }
QString GamesManager::cardsRoot() const { return m_cardsRoot; }
bool GamesManager::installerRunning() const { return m_installerProcess.state() != QProcess::NotRunning; }
QString GamesManager::installerStatus() const { return m_installerStatus; }
int GamesManager::installerProgress() const { return m_installerProgress; }

QString GamesManager::formatBytes(qulonglong bytes) const
{
    static const QStringList units = {
        QStringLiteral("B"), QStringLiteral("KB"), QStringLiteral("MB"),
        QStringLiteral("GB"), QStringLiteral("TB")
    };
    double value = static_cast<double>(bytes);
    int unit = 0;
    while (value >= 1024.0 && unit < units.size() - 1) {
        value /= 1024.0;
        ++unit;
    }
    return QString::number(value, unit == 0 ? 'f' : 'f', unit == 0 ? 0 : 1)
           + QStringLiteral(" ") + units.at(unit);
}

void GamesManager::setMessage(const QString &message)
{
    if (m_lastMessage == message)
        return;
    m_lastMessage = message;
    emit lastMessageChanged();
}

void GamesManager::setInstallerStatus(const QString &message, int progress)
{
    bool changed = false;
    if (m_installerStatus != message) {
        m_installerStatus = message;
        changed = true;
    }
    if (progress >= 0) {
        const int bounded = qBound<int>(0, progress, 100);
        if (m_installerProgress != bounded) {
            m_installerProgress = bounded;
            changed = true;
        }
    }
    if (changed)
        emit installerChanged();
}

QString GamesManager::normalizedSystemToken(const QString &value)
{
    QString token = value.trimmed().toLower();
    token.remove(QLatin1Char(' '));
    token.remove(QLatin1Char('-'));
    token.remove(QLatin1Char('_'));
    return token;
}

QString GamesManager::detectSystem(const QString &absolutePath, const QString &extension) const
{
    const QString pathToken = normalizedSystemToken(QFileInfo(absolutePath).absolutePath());
    const QList<QPair<QString, QString>> folderTokens = {
        {QStringLiteral("playstation1"), QStringLiteral("ps1")},
        {QStringLiteral("playstation"), QStringLiteral("ps1")},
        {QStringLiteral("psx"), QStringLiteral("ps1")},
        {QStringLiteral("ps1"), QStringLiteral("ps1")},
        {QStringLiteral("nintendo64"), QStringLiteral("n64")},
        {QStringLiteral("n64"), QStringLiteral("n64")},
        {QStringLiteral("supernintendo"), QStringLiteral("snes")},
        {QStringLiteral("snes"), QStringLiteral("snes")},
        {QStringLiteral("gameboyadvance"), QStringLiteral("gba")},
        {QStringLiteral("gba"), QStringLiteral("gba")},
        {QStringLiteral("gameboycolor"), QStringLiteral("gbc")},
        {QStringLiteral("gbc"), QStringLiteral("gbc")},
        {QStringLiteral("gameboy"), QStringLiteral("gb")},
        {QStringLiteral("nintendods"), QStringLiteral("nds")},
        {QStringLiteral("nds"), QStringLiteral("nds")},
        {QStringLiteral("gamecube"), QStringLiteral("gamecube")},
        {QStringLiteral("wii"), QStringLiteral("wii")},
        {QStringLiteral("psp"), QStringLiteral("psp")},
        {QStringLiteral("playstation2"), QStringLiteral("ps2")},
        {QStringLiteral("ps2"), QStringLiteral("ps2")},
        {QStringLiteral("dreamcast"), QStringLiteral("dreamcast")},
        {QStringLiteral("arcade"), QStringLiteral("arcade")},
        {QStringLiteral("megadrive"), QStringLiteral("genesis")},
        {QStringLiteral("genesis"), QStringLiteral("genesis")},
        {QStringLiteral("mastersystem"), QStringLiteral("sms")},
        {QStringLiteral("nes"), QStringLiteral("nes")},
        {QStringLiteral("flash"), QStringLiteral("flash")}
    };
    for (const auto &entry : folderTokens) {
        if (pathToken.contains(entry.first))
            return entry.second;
    }

    if (extension == QStringLiteral("z64") || extension == QStringLiteral("n64") || extension == QStringLiteral("v64"))
        return QStringLiteral("n64");
    if (extension == QStringLiteral("cue") || extension == QStringLiteral("pbp"))
        return QStringLiteral("ps1");
    if (extension == QStringLiteral("sfc") || extension == QStringLiteral("smc") || extension == QStringLiteral("fig"))
        return QStringLiteral("snes");
    if (extension == QStringLiteral("nes") || extension == QStringLiteral("fds"))
        return QStringLiteral("nes");
    if (extension == QStringLiteral("gba"))
        return QStringLiteral("gba");
    if (extension == QStringLiteral("gbc"))
        return QStringLiteral("gbc");
    if (extension == QStringLiteral("gb"))
        return QStringLiteral("gb");
    if (extension == QStringLiteral("nds"))
        return QStringLiteral("nds");
    if (extension == QStringLiteral("md") || extension == QStringLiteral("gen") || extension == QStringLiteral("smd"))
        return QStringLiteral("genesis");
    if (extension == QStringLiteral("sms") || extension == QStringLiteral("gg"))
        return QStringLiteral("sms");
    if (extension == QStringLiteral("gcm") || extension == QStringLiteral("rvz"))
        return QStringLiteral("gamecube");
    if (extension == QStringLiteral("wbfs") || extension == QStringLiteral("wad"))
        return QStringLiteral("wii");
    if (extension == QStringLiteral("cso"))
        return QStringLiteral("psp");
    if (extension == QStringLiteral("chd"))
        return QStringLiteral("ps1");
    if (extension == QStringLiteral("swf"))
        return QStringLiteral("flash");
    return QStringLiteral("unknown");
}

QString GamesManager::displaySystem(const QString &system) const
{
    const QHash<QString, QString> labels = {
        {QStringLiteral("n64"), QStringLiteral("N64")},
        {QStringLiteral("ps1"), QStringLiteral("PS1")},
        {QStringLiteral("snes"), QStringLiteral("SNES")},
        {QStringLiteral("nes"), QStringLiteral("NES")},
        {QStringLiteral("gba"), QStringLiteral("GBA")},
        {QStringLiteral("gbc"), QStringLiteral("GBC")},
        {QStringLiteral("gb"), QStringLiteral("GB")},
        {QStringLiteral("nds"), QStringLiteral("NDS")},
        {QStringLiteral("genesis"), QStringLiteral("GENESIS")},
        {QStringLiteral("sms"), QStringLiteral("MASTER SYSTEM")},
        {QStringLiteral("gamecube"), QStringLiteral("GAMECUBE")},
        {QStringLiteral("wii"), QStringLiteral("WII")},
        {QStringLiteral("psp"), QStringLiteral("PSP")},
        {QStringLiteral("ps2"), QStringLiteral("PS2")},
        {QStringLiteral("dreamcast"), QStringLiteral("DREAMCAST")},
        {QStringLiteral("arcade"), QStringLiteral("ARCADE")},
        {QStringLiteral("flash"), QStringLiteral("FLASH")},
        {QStringLiteral("cloud"), QStringLiteral("CLOUD")},
        {QStringLiteral("unknown"), QStringLiteral("UNKNOWN")}
    };
    return labels.value(system, system.toUpper());
}

QString GamesManager::displayTitle(const QString &path) const
{
    QString title = QFileInfo(path).completeBaseName();
    title.replace(QLatin1Char('_'), QLatin1Char(' '));
    title.replace(QLatin1Char('.'), QLatin1Char(' '));
    while (title.contains(QStringLiteral("  ")))
        title.replace(QStringLiteral("  "), QStringLiteral(" "));
    return title.trimmed();
}

QString GamesManager::gameIdForPath(const QString &relativePath) const
{
    const QByteArray digest = QCryptographicHash::hash(relativePath.toUtf8(), QCryptographicHash::Sha1).toHex();
    return QStringLiteral("game-") + QString::fromLatin1(digest.left(16));
}

QJsonObject GamesManager::readSidecar(const QString &absolutePath) const
{
    const QFileInfo info(absolutePath);
    const QStringList candidates = {
        info.absolutePath() + QLatin1Char('/') + info.completeBaseName() + QStringLiteral(".json"),
        absolutePath + QStringLiteral(".json")
    };
    for (const QString &path : candidates) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            continue;
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
        if (error.error == QJsonParseError::NoError && document.isObject())
            return document.object();
    }
    return {};
}

QString GamesManager::cardForRom(const QString &absolutePath, const QJsonObject &sidecar) const
{
    const QString requested = safeString(sidecar, QStringLiteral("card"));
    if (!requested.isEmpty()) {
        const QFileInfo requestedInfo(QDir(m_cardsRoot).filePath(requested));
        if (requestedInfo.exists() && requestedInfo.isFile())
            return QUrl::fromLocalFile(requestedInfo.absoluteFilePath()).toString();
    }

    const QString base = QFileInfo(absolutePath).completeBaseName();
    const QString relativeDirectory = QDir(m_romRoot).relativeFilePath(QFileInfo(absolutePath).absolutePath());
    const QStringList extensions = {QStringLiteral("png"), QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("webp")};
    for (const QString &extension : extensions) {
        const QStringList candidates = {
            QDir(m_cardsRoot).filePath(base + QLatin1Char('.') + extension),
            QDir(m_cardsRoot).filePath(relativeDirectory + QLatin1Char('/') + base + QLatin1Char('.') + extension)
        };
        for (const QString &candidate : candidates) {
            if (QFileInfo::exists(candidate))
                return QUrl::fromLocalFile(QFileInfo(candidate).absoluteFilePath()).toString();
        }
    }
    return QString();
}

QString GamesManager::findCore(const QStringList &names) const
{
    const QStringList roots = {
        QStringLiteral("/usr/lib/aarch64-linux-gnu/libretro"),
        QStringLiteral("/usr/lib/arm-linux-gnueabihf/libretro"),
        QStringLiteral("/usr/lib/libretro"),
        QStringLiteral("/usr/local/lib/libretro"),
        QStringLiteral("/opt/retropie/libretrocores")
    };
    for (const QString &root : roots) {
        for (const QString &name : names) {
            const QString direct = QDir(root).filePath(name);
            if (QFileInfo::exists(direct))
                return QFileInfo(direct).absoluteFilePath();
        }
    }
    return QString();
}

QString GamesManager::executable(const QStringList &names) const
{
    for (const QString &name : names) {
        const QFileInfo direct(name);
        if (direct.isAbsolute() && direct.exists() && direct.isFile() && direct.isExecutable())
            return direct.absoluteFilePath();
        const QString path = QStandardPaths::findExecutable(name);
        if (!path.isEmpty())
            return path;
    }
    return QString();
}

bool GamesManager::flatpakApplicationInstalled(const QString &applicationId) const
{
    const QString flatpak = executable({QStringLiteral("flatpak")});
    if (flatpak.isEmpty() || applicationId.trimmed().isEmpty())
        return false;
    QProcess process;
    process.start(flatpak, QStringList{QStringLiteral("info"), QStringLiteral("--system"), applicationId});
    if (!process.waitForFinished(2500))
        return false;
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}

QVariantList GamesManager::emulatorOptions(const QString &system, const QJsonObject &sidecar) const
{
    QVariantList options;
    const QString retroarch = executable({QStringLiteral("retroarch")});

    auto addRetro = [&](const QString &id, const QString &label, const QStringList &cores) {
        if (retroarch.isEmpty())
            return;
        const QString core = findCore(cores);
        if (core.isEmpty())
            return;
        options.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("label"), label},
            {QStringLiteral("kind"), QStringLiteral("retroarch")},
            {QStringLiteral("program"), retroarch},
            {QStringLiteral("core"), core}
        });
    };

    auto addStandalone = [&](const QString &id, const QString &label, const QStringList &programs, const QString &kind) {
        const QString program = executable(programs);
        if (program.isEmpty())
            return;
        options.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("label"), label},
            {QStringLiteral("kind"), kind},
            {QStringLiteral("program"), program}
        });
    };

    if (system == QStringLiteral("n64")) {
        addRetro(QStringLiteral("retroarch-mupen64plus-next"), QStringLiteral("RetroArch · Mupen64Plus-Next"),
                 {QStringLiteral("mupen64plus_next_libretro.so"), QStringLiteral("mupen64plus_libretro.so"), QStringLiteral("parallel_n64_libretro.so")});
        addStandalone(QStringLiteral("mupen64plus"), QStringLiteral("Mupen64Plus"),
                      {QStringLiteral("mupen64plus")}, QStringLiteral("mupen64plus"));
    } else if (system == QStringLiteral("ps1")) {
        addRetro(QStringLiteral("retroarch-pcsx-rearmed"), QStringLiteral("RetroArch · PCSX-ReARMed"),
                 {QStringLiteral("pcsx_rearmed_libretro.so"), QStringLiteral("mednafen_psx_hw_libretro.so"), QStringLiteral("mednafen_psx_libretro.so")});
        addStandalone(QStringLiteral("pcsxr"), QStringLiteral("PCSX-R"),
                      {QStringLiteral("pcsxr")}, QStringLiteral("pcsx"));
        addStandalone(QStringLiteral("pcsx-rearmed"), QStringLiteral("PCSX-ReARMed"),
                      {QStringLiteral("pcsx-rearmed"), QStringLiteral("pcsx_rearmed")}, QStringLiteral("pcsx"));
    } else if (system == QStringLiteral("snes")) {
        addRetro(QStringLiteral("retroarch-snes9x"), QStringLiteral("RetroArch · Snes9x"),
                 {QStringLiteral("snes9x_libretro.so"), QStringLiteral("snes9x2010_libretro.so")});
    } else if (system == QStringLiteral("nes")) {
        addRetro(QStringLiteral("retroarch-nestopia"), QStringLiteral("RetroArch · Nestopia"),
                 {QStringLiteral("nestopia_libretro.so"), QStringLiteral("fceumm_libretro.so")});
    } else if (system == QStringLiteral("gba")) {
        addRetro(QStringLiteral("retroarch-mgba"), QStringLiteral("RetroArch · mGBA"),
                 {QStringLiteral("mgba_libretro.so")});
    } else if (system == QStringLiteral("gb") || system == QStringLiteral("gbc")) {
        addRetro(QStringLiteral("retroarch-gambatte"), QStringLiteral("RetroArch · Gambatte"),
                 {QStringLiteral("gambatte_libretro.so"), QStringLiteral("mgba_libretro.so")});
    } else if (system == QStringLiteral("nds")) {
        addRetro(QStringLiteral("retroarch-melonds"), QStringLiteral("RetroArch · melonDS"),
                 {QStringLiteral("melonds_libretro.so"), QStringLiteral("desmume_libretro.so")});
    } else if (system == QStringLiteral("genesis") || system == QStringLiteral("sms")) {
        addRetro(QStringLiteral("retroarch-genesis-plus-gx"), QStringLiteral("RetroArch · Genesis Plus GX"),
                 {QStringLiteral("genesis_plus_gx_libretro.so"), QStringLiteral("picodrive_libretro.so")});
    } else if (system == QStringLiteral("arcade")) {
        addRetro(QStringLiteral("retroarch-fbneo"), QStringLiteral("RetroArch · FinalBurn Neo"),
                 {QStringLiteral("fbneo_libretro.so"), QStringLiteral("mame2003_plus_libretro.so")});
    } else if (system == QStringLiteral("dreamcast")) {
        addRetro(QStringLiteral("retroarch-flycast"), QStringLiteral("RetroArch · Flycast"),
                 {QStringLiteral("flycast_libretro.so")});
    } else if (system == QStringLiteral("gamecube") || system == QStringLiteral("wii")) {
        addStandalone(QStringLiteral("dolphin"), QStringLiteral("Dolphin"),
                      {QStringLiteral("dolphin-emu-nogui"), QStringLiteral("dolphin-emu")}, QStringLiteral("dolphin"));
    } else if (system == QStringLiteral("psp")) {
        addStandalone(QStringLiteral("ppsspp"), QStringLiteral("PPSSPP"),
                      {QStringLiteral("PPSSPPSDL"), QStringLiteral("ppsspp")}, QStringLiteral("ppsspp"));
        addRetro(QStringLiteral("retroarch-ppsspp"), QStringLiteral("RetroArch · PPSSPP"),
                 {QStringLiteral("ppsspp_libretro.so")});
    } else if (system == QStringLiteral("ps2")) {
        addStandalone(QStringLiteral("play"), QStringLiteral("Play!"),
                      {QStringLiteral("Play!"), QStringLiteral("play-qt"), QStringLiteral("play")}, QStringLiteral("play"));
    } else if (system == QStringLiteral("flash")) {
        const QString ruffle = executable({QStringLiteral("ruffle"), QStringLiteral("/opt/neutronos/bin/ruffle")});
        const QString cage = executable({QStringLiteral("cage")});
        if (!ruffle.isEmpty() && !cage.isEmpty()) {
            options.append(QVariantMap{
                {QStringLiteral("id"), QStringLiteral("ruffle")},
                {QStringLiteral("label"), QStringLiteral("Ruffle · Flash Player")},
                {QStringLiteral("kind"), QStringLiteral("ruffle")},
                {QStringLiteral("program"), cage},
                {QStringLiteral("player"), ruffle}
            });
        }
    }

    const QString sidecarCore = safeString(sidecar, QStringLiteral("core"));
    if (!retroarch.isEmpty() && !sidecarCore.isEmpty()) {
        const QFileInfo coreInfo(sidecarCore);
        if (coreInfo.exists() && coreInfo.isFile() && coreInfo.absoluteFilePath().contains(QStringLiteral("libretro"))) {
            options.prepend(QVariantMap{
                {QStringLiteral("id"), QStringLiteral("retroarch-sidecar")},
                {QStringLiteral("label"), QStringLiteral("RetroArch · Custom Core")},
                {QStringLiteral("kind"), QStringLiteral("retroarch")},
                {QStringLiteral("program"), retroarch},
                {QStringLiteral("core"), coreInfo.absoluteFilePath()}
            });
        }
    }

    return options;
}

QVariantList GamesManager::installerOptionsForSystem(const QString &system,
                                                     const QString &serviceId) const
{
    QVariantList options;
    auto addApt = [&](const QString &id,
                      const QString &label,
                      const QString &description,
                      const QStringList &packages,
                      const QString &performance,
                      const QString &bios,
                      const QString &sizeText,
                      bool recommended) {
        options.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("label"), label},
            {QStringLiteral("description"), description},
            {QStringLiteral("installerKind"), QStringLiteral("apt")},
            {QStringLiteral("packages"), packages},
            {QStringLiteral("performance"), performance},
            {QStringLiteral("bios"), bios},
            {QStringLiteral("sizeText"), sizeText},
            {QStringLiteral("recommended"), recommended}
        });
    };

    if (system == QStringLiteral("n64")) {
        addApt(QStringLiteral("mupen64plus"), QStringLiteral("Mupen64Plus"),
               QStringLiteral("Standalone N64 emulator with direct controller support."),
               {QStringLiteral("mupen64plus-ui-console"), QStringLiteral("mupen64plus-video-all"),
                QStringLiteral("mupen64plus-input-all"), QStringLiteral("mupen64plus-audio-all")},
               QStringLiteral("Best Pi 4 performance"), QStringLiteral("No BIOS required"),
               QStringLiteral("About 35 MB"), true);
        addApt(QStringLiteral("retroarch-mupen64plus-next"), QStringLiteral("RetroArch · Mupen64Plus"),
               QStringLiteral("RetroArch frontend with the Debian Mupen64Plus Libretro core."),
               {QStringLiteral("retroarch"), QStringLiteral("libretro-mupen64plus")},
               QStringLiteral("Good compatibility"), QStringLiteral("No BIOS required"),
               QStringLiteral("About 70 MB"), false);
    } else if (system == QStringLiteral("ps1")) {
        addApt(QStringLiteral("pcsxr"), QStringLiteral("PCSX-R"),
               QStringLiteral("Standalone PlayStation emulator available for Debian ARM64."),
               {QStringLiteral("pcsxr")},
               QStringLiteral("Lightweight"), QStringLiteral("BIOS recommended for best compatibility"),
               QStringLiteral("About 20 MB"), true);
        addApt(QStringLiteral("retroarch-pcsx-rearmed"), QStringLiteral("RetroArch · Beetle/PCSX"),
               QStringLiteral("RetroArch with Debian's PlayStation Libretro core."),
               {QStringLiteral("retroarch"), QStringLiteral("libretro-beetle-psx")},
               QStringLiteral("Accurate but heavier"), QStringLiteral("PlayStation BIOS recommended"),
               QStringLiteral("About 75 MB"), false);
    } else if (system == QStringLiteral("snes")) {
        addApt(QStringLiteral("retroarch-snes9x"), QStringLiteral("RetroArch · Snes9x"),
               QStringLiteral("Snes9x Libretro core with controller autodetection."),
               {QStringLiteral("retroarch"), QStringLiteral("libretro-snes9x")},
               QStringLiteral("Excellent"), QStringLiteral("No BIOS required"),
               QStringLiteral("About 65 MB"), true);
    } else if (system == QStringLiteral("nes")) {
        addApt(QStringLiteral("retroarch-nestopia"), QStringLiteral("RetroArch · Nestopia"),
               QStringLiteral("Accurate NES/Famicom emulation through RetroArch."),
               {QStringLiteral("retroarch"), QStringLiteral("libretro-nestopia")},
               QStringLiteral("Excellent"), QStringLiteral("No BIOS required"),
               QStringLiteral("About 65 MB"), true);
    } else if (system == QStringLiteral("gba")) {
        addApt(QStringLiteral("retroarch-mgba"), QStringLiteral("RetroArch · mGBA"),
               QStringLiteral("Fast Game Boy Advance emulation with save-state support."),
               {QStringLiteral("retroarch"), QStringLiteral("libretro-mgba")},
               QStringLiteral("Excellent"), QStringLiteral("BIOS optional"),
               QStringLiteral("About 65 MB"), true);
    } else if (system == QStringLiteral("gb") || system == QStringLiteral("gbc")) {
        addApt(QStringLiteral("retroarch-gambatte"), QStringLiteral("RetroArch · Gambatte"),
               QStringLiteral("Game Boy and Game Boy Color emulator optimized for low-power hardware."),
               {QStringLiteral("retroarch"), QStringLiteral("libretro-gambatte")},
               QStringLiteral("Excellent"), QStringLiteral("No BIOS required"),
               QStringLiteral("About 65 MB"), true);
    } else if (system == QStringLiteral("nds")) {
        addApt(QStringLiteral("retroarch-melonds"), QStringLiteral("RetroArch · DeSmuME"),
               QStringLiteral("Nintendo DS emulation through Debian's DeSmuME Libretro core."),
               {QStringLiteral("retroarch"), QStringLiteral("libretro-desmume")},
               QStringLiteral("Experimental on Pi 4"), QStringLiteral("Firmware may be required by some games"),
               QStringLiteral("About 75 MB"), true);
    } else if (system == QStringLiteral("genesis") || system == QStringLiteral("sms")) {
        addApt(QStringLiteral("retroarch-genesis-plus-gx"), QStringLiteral("RetroArch · Genesis Plus GX"),
               QStringLiteral("Genesis, Mega Drive and Master System emulation."),
               {QStringLiteral("retroarch"), QStringLiteral("libretro-genesisplusgx")},
               QStringLiteral("Excellent"), QStringLiteral("No BIOS required for most games"),
               QStringLiteral("About 65 MB"), true);
    } else if (system == QStringLiteral("gamecube") || system == QStringLiteral("wii")) {
        addApt(QStringLiteral("dolphin"), QStringLiteral("Dolphin"),
               QStringLiteral("GameCube and Wii emulator. Demanding games may require Performance mode."),
               {QStringLiteral("dolphin-emu")},
               QStringLiteral("Experimental on Pi 4"), QStringLiteral("No BIOS required"),
               QStringLiteral("About 170 MB"), true);
    } else if (system == QStringLiteral("psp")) {
        addApt(QStringLiteral("ppsspp"), QStringLiteral("PPSSPP"),
               QStringLiteral("Standalone PSP emulator with native controller support."),
               {QStringLiteral("ppsspp")},
               QStringLiteral("Varies by game"), QStringLiteral("No BIOS required"),
               QStringLiteral("About 120 MB"), true);
    } else if (system == QStringLiteral("flash")) {
        options.append(QVariantMap{
            {QStringLiteral("id"), QStringLiteral("ruffle")},
            {QStringLiteral("label"), QStringLiteral("Ruffle · Official ARM64")},
            {QStringLiteral("description"), QStringLiteral("Downloads the latest official Linux ARM64 Ruffle desktop release and installs the fullscreen runtime.")},
            {QStringLiteral("installerKind"), QStringLiteral("ruffle")},
            {QStringLiteral("performance"), QStringLiteral("Excellent for most 2D Flash games")},
            {QStringLiteral("bios"), QStringLiteral("No BIOS required")},
            {QStringLiteral("sizeText"), QStringLiteral("About 30–80 MB")},
            {QStringLiteral("recommended"), true}
        });
    } else if (system == QStringLiteral("cloud")) {
        if (serviceId == QStringLiteral("moonlight")) {
            options.append(QVariantMap{
                {QStringLiteral("id"), QStringLiteral("moonlight-flatpak")},
                {QStringLiteral("label"), QStringLiteral("Moonlight")},
                {QStringLiteral("description"), QStringLiteral("Installs Moonlight system-wide from Flathub for Sunshine/PC streaming.")},
                {QStringLiteral("installerKind"), QStringLiteral("moonlight")},
                {QStringLiteral("performance"), QStringLiteral("Recommended cloud/remote-play option")},
                {QStringLiteral("bios"), QStringLiteral("Requires a Sunshine host or compatible PC")},
                {QStringLiteral("sizeText"), QStringLiteral("About 250 MB")},
                {QStringLiteral("recommended"), true}
            });
        } else {
            addApt(QStringLiteral("cloud-browser"), QStringLiteral("Cloud Browser Runtime"),
                   QStringLiteral("Installs Chromium and the Cage kiosk compositor for controller-friendly cloud gaming."),
                   {QStringLiteral("chromium"), QStringLiteral("cage")},
                   QStringLiteral("Experimental on Pi 4"), QStringLiteral("Service account required"),
                   QStringLiteral("About 350 MB"), true);
        }
    }
    return options;
}

QVariantList GamesManager::cloudServiceEntries() const
{
    QVariantList services;
    const QString cage = executable({QStringLiteral("cage")});
    const QString chromium = executable({QStringLiteral("chromium"), QStringLiteral("chromium-browser")});
    const QString moonlightNative = executable({QStringLiteral("moonlight"), QStringLiteral("moonlight-qt")});
    const QString flatpak = executable({QStringLiteral("flatpak")});

    auto cloudEntry = [&](const QString &id,
                          const QString &title,
                          const QString &serviceId,
                          const QString &description,
                          const QString &url,
                          bool experimental) {
        QVariantList emulators;
        if (serviceId == QStringLiteral("moonlight")) {
            if (!cage.isEmpty() && !moonlightNative.isEmpty()) {
                emulators.append(QVariantMap{
                    {QStringLiteral("id"), QStringLiteral("moonlight-native")},
                    {QStringLiteral("label"), QStringLiteral("Moonlight")},
                    {QStringLiteral("kind"), QStringLiteral("moonlight")},
                    {QStringLiteral("program"), cage},
                    {QStringLiteral("client"), moonlightNative}
                });
            } else if (!cage.isEmpty() && !flatpak.isEmpty()
                       && flatpakApplicationInstalled(QStringLiteral("com.moonlight_stream.Moonlight"))) {
                emulators.append(QVariantMap{
                    {QStringLiteral("id"), QStringLiteral("moonlight-flatpak")},
                    {QStringLiteral("label"), QStringLiteral("Moonlight · Flatpak")},
                    {QStringLiteral("kind"), QStringLiteral("moonlight-flatpak")},
                    {QStringLiteral("program"), cage},
                    {QStringLiteral("flatpak"), flatpak},
                    {QStringLiteral("applicationId"), QStringLiteral("com.moonlight_stream.Moonlight")}
                });
            }
        } else if (!cage.isEmpty() && !chromium.isEmpty()) {
            emulators.append(QVariantMap{
                {QStringLiteral("id"), QStringLiteral("cloud-browser")},
                {QStringLiteral("label"), QStringLiteral("Chromium Cloud Runtime")},
                {QStringLiteral("kind"), QStringLiteral("cloud-browser")},
                {QStringLiteral("program"), cage},
                {QStringLiteral("browser"), chromium},
                {QStringLiteral("url"), url}
            });
        }

        const QJsonObject gameSettings = m_settings.value(id).toObject();
        const QJsonObject gameUsage = m_usage.value(id).toObject();
        QString selectedId = gameSettings.value(QStringLiteral("emulatorId")).toString();
        QString selectedLabel;
        for (const QVariant &entry : emulators) {
            const QVariantMap option = entry.toMap();
            if (selectedId.isEmpty() || option.value(QStringLiteral("id")).toString() == selectedId) {
                selectedId = option.value(QStringLiteral("id")).toString();
                selectedLabel = option.value(QStringLiteral("label")).toString();
                break;
            }
        }
        services.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("title"), title},
            {QStringLiteral("system"), QStringLiteral("cloud")},
            {QStringLiteral("typeLabel"), QStringLiteral("CLOUD")},
            {QStringLiteral("kind"), QStringLiteral("cloud")},
            {QStringLiteral("serviceId"), serviceId},
            {QStringLiteral("path"), QString()},
            {QStringLiteral("relativePath"), QStringLiteral("Cloud/") + serviceId},
            {QStringLiteral("extension"), QStringLiteral("STREAM")},
            {QStringLiteral("card"), QString()},
            {QStringLiteral("sizeBytes"), static_cast<qulonglong>(0)},
            {QStringLiteral("sizeText"), QStringLiteral("STREAM")},
            {QStringLiteral("modified"), QStringLiteral("Service")},
            {QStringLiteral("lastPlayed"), gameUsage.value(QStringLiteral("lastPlayed")).toString(QStringLiteral("Never"))},
            {QStringLiteral("playCount"), gameUsage.value(QStringLiteral("playCount")).toInt(0)},
            {QStringLiteral("description"), description},
            {QStringLiteral("emulators"), emulators},
            {QStringLiteral("emulatorId"), selectedId},
            {QStringLiteral("emulatorLabel"), selectedLabel.isEmpty() ? QStringLiteral("RUNTIME NOT INSTALLED") : selectedLabel},
            {QStringLiteral("launchReady"), !emulators.isEmpty()},
            {QStringLiteral("aspect"), gameSettings.value(QStringLiteral("aspect")).toString(QStringLiteral("16:9"))},
            {QStringLiteral("profile"), gameSettings.value(QStringLiteral("profile")).toString(QStringLiteral("BALANCED"))},
            {QStringLiteral("integerScale"), false},
            {QStringLiteral("experimental"), experimental},
            {QStringLiteral("url"), url}
        });
    };

    cloudEntry(QStringLiteral("cloud-moonlight"), QStringLiteral("Moonlight PC Streaming"),
               QStringLiteral("moonlight"),
               QStringLiteral("Stream games from a Sunshine-equipped gaming PC with direct controller passthrough."),
               QString(), false);
    cloudEntry(QStringLiteral("cloud-xbox"), QStringLiteral("Xbox Cloud Gaming"),
               QStringLiteral("xbox"),
               QStringLiteral("Launch Xbox Cloud Gaming in a dedicated controller-friendly browser session."),
               QStringLiteral("https://www.xbox.com/play"), true);
    cloudEntry(QStringLiteral("cloud-luna"), QStringLiteral("Amazon Luna"),
               QStringLiteral("luna"),
               QStringLiteral("Launch Amazon Luna in a dedicated browser session."),
               QStringLiteral("https://luna.amazon.com"), true);
    cloudEntry(QStringLiteral("cloud-geforce"), QStringLiteral("GeForce NOW"),
               QStringLiteral("geforce"),
               QStringLiteral("Experimental browser launcher. Linux ARM64 is not officially supported by NVIDIA."),
               QStringLiteral("https://play.geforcenow.com"), true);
    return services;
}

QVariantMap GamesManager::scanRom(const QString &absolutePath) const
{
    const QFileInfo info(absolutePath);
    const QString relative = QDir(m_romRoot).relativeFilePath(info.absoluteFilePath());
    const QString extension = info.suffix().toLower();
    const QJsonObject sidecar = readSidecar(absolutePath);
    QString system = normalizedSystemToken(safeString(sidecar, QStringLiteral("system")));
    if (system.isEmpty())
        system = detectSystem(absolutePath, extension);
    QString title = safeString(sidecar, QStringLiteral("title"));
    if (title.isEmpty())
        title = displayTitle(absolutePath);
    const QString id = gameIdForPath(relative);
    const QJsonObject gameSettings = m_settings.value(id).toObject();
    const QJsonObject gameUsage = m_usage.value(id).toObject();
    const QVariantList emulators = emulatorOptions(system, sidecar);

    QString selectedEmulatorId = gameSettings.value(QStringLiteral("emulatorId")).toString();
    QString selectedEmulatorLabel;
    for (const QVariant &entry : emulators) {
        const QVariantMap option = entry.toMap();
        if (selectedEmulatorId.isEmpty() || option.value(QStringLiteral("id")).toString() == selectedEmulatorId) {
            selectedEmulatorId = option.value(QStringLiteral("id")).toString();
            selectedEmulatorLabel = option.value(QStringLiteral("label")).toString();
            break;
        }
    }

    return QVariantMap{
        {QStringLiteral("id"), id},
        {QStringLiteral("title"), title},
        {QStringLiteral("system"), system},
        {QStringLiteral("kind"), QStringLiteral("rom")},
        {QStringLiteral("typeLabel"), displaySystem(system)},
        {QStringLiteral("path"), info.absoluteFilePath()},
        {QStringLiteral("relativePath"), relative},
        {QStringLiteral("extension"), extension.toUpper()},
        {QStringLiteral("card"), cardForRom(absolutePath, sidecar)},
        {QStringLiteral("sizeBytes"), static_cast<qulonglong>(info.size())},
        {QStringLiteral("sizeText"), formatBytes(static_cast<qulonglong>(info.size()))},
        {QStringLiteral("modified"), humanDate(info.lastModified())},
        {QStringLiteral("lastPlayed"), gameUsage.value(QStringLiteral("lastPlayed")).toString(QStringLiteral("Never"))},
        {QStringLiteral("playCount"), gameUsage.value(QStringLiteral("playCount")).toInt(0)},
        {QStringLiteral("description"), safeString(sidecar, QStringLiteral("description"))},
        {QStringLiteral("emulators"), emulators},
        {QStringLiteral("emulatorId"), selectedEmulatorId},
        {QStringLiteral("emulatorLabel"), selectedEmulatorLabel.isEmpty() ? QStringLiteral("NOT INSTALLED") : selectedEmulatorLabel},
        {QStringLiteral("launchReady"), !emulators.isEmpty()},
        {QStringLiteral("aspect"), gameSettings.value(QStringLiteral("aspect")).toString(QStringLiteral("AUTO"))},
        {QStringLiteral("profile"), gameSettings.value(QStringLiteral("profile")).toString(QStringLiteral("BALANCED"))},
        {QStringLiteral("integerScale"), gameSettings.value(QStringLiteral("integerScale")).toBool(false)}
    };
}

void GamesManager::refresh()
{
    QVariantList discovered;
    const QString canonicalRoot = QFileInfo(m_romRoot).canonicalFilePath();
    QDirIterator iterator(m_romRoot,
                          QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext()) {
        const QString path = iterator.next();
        if (path.startsWith(m_cardsRoot + QDir::separator()))
            continue;
        const QFileInfo info(path);
        const QString canonicalPath = info.canonicalFilePath();
        if (canonicalRoot.isEmpty() || canonicalPath.isEmpty()
                || !canonicalPath.startsWith(canonicalRoot + QDir::separator()))
            continue;
        if (!SupportedExtensions.contains(info.suffix().toLower()))
            continue;
        discovered.append(scanRom(canonicalPath));
    }

    const QVariantList cloudServices = cloudServiceEntries();
    for (const QVariant &service : cloudServices)
        discovered.append(service);

    std::sort(discovered.begin(), discovered.end(), [](const QVariant &left, const QVariant &right) {
        return left.toMap().value(QStringLiteral("title")).toString().localeAwareCompare(
                   right.toMap().value(QStringLiteral("title")).toString()) < 0;
    });

    QVariantList ordered;
    QHash<QString, QVariantMap> byId;
    for (const QVariant &entry : discovered) {
        const QVariantMap game = entry.toMap();
        byId.insert(game.value(QStringLiteral("id")).toString(), game);
    }
    for (const QString &id : std::as_const(m_order)) {
        if (byId.contains(id))
            ordered.append(byId.take(id));
    }
    for (const QVariant &entry : discovered) {
        const QVariantMap game = entry.toMap();
        const QString id = game.value(QStringLiteral("id")).toString();
        if (byId.contains(id)) {
            ordered.append(byId.take(id));
        }
    }

    m_games = ordered;
    rebuildOrderFromGames();
    saveState();
    setMessage(QStringLiteral("Library ready: %1 game and cloud entr%2.")
               .arg(m_games.size())
               .arg(m_games.size() == 1 ? QStringLiteral("y") : QStringLiteral("ies")));
    emit gamesChanged();
}

void GamesManager::rebuildOrderFromGames()
{
    m_order.clear();
    for (const QVariant &entry : std::as_const(m_games))
        m_order.append(entry.toMap().value(QStringLiteral("id")).toString());
}

QVariantMap GamesManager::findGame(const QString &gameId) const
{
    for (const QVariant &entry : m_games) {
        const QVariantMap game = entry.toMap();
        if (game.value(QStringLiteral("id")).toString() == gameId)
            return game;
    }
    return {};
}

int GamesManager::gameIndex(const QString &gameId) const
{
    for (int index = 0; index < m_games.size(); ++index) {
        if (m_games.at(index).toMap().value(QStringLiteral("id")).toString() == gameId)
            return index;
    }
    return -1;
}

QVariantMap GamesManager::gameDetails(const QString &gameId) const
{
    return findGame(gameId);
}

QVariantList GamesManager::compatibleInstallers(const QString &gameId) const
{
    const QVariantMap game = findGame(gameId);
    if (game.isEmpty())
        return {};
    return installerOptionsForSystem(game.value(QStringLiteral("system")).toString(),
                                     game.value(QStringLiteral("serviceId")).toString());
}

bool GamesManager::moveGameBy(const QString &gameId, int delta)
{
    const int index = gameIndex(gameId);
    if (index < 0 || m_games.isEmpty())
        return false;
    const int count = static_cast<int>(m_games.size());
    return moveGameTo(gameId, qBound<int>(0, index + delta, count - 1));
}

bool GamesManager::moveGameTo(const QString &gameId, int targetIndex)
{
    const int index = gameIndex(gameId);
    if (index < 0 || m_games.isEmpty())
        return false;
    const int count = static_cast<int>(m_games.size());
    targetIndex = qBound<int>(0, targetIndex, count - 1);
    if (index == targetIndex)
        return true;
    const QVariant game = m_games.takeAt(index);
    m_games.insert(targetIndex, game);
    rebuildOrderFromGames();
    saveState();
    emit gamesChanged();
    setMessage(QStringLiteral("Game order saved."));
    return true;
}

bool GamesManager::setGameSetting(const QString &gameId,
                                  const QString &key,
                                  const QVariant &value)
{
    if (gameIndex(gameId) < 0)
        return false;
    static const QSet<QString> allowed = {
        QStringLiteral("emulatorId"), QStringLiteral("aspect"),
        QStringLiteral("profile"), QStringLiteral("integerScale")
    };
    if (!allowed.contains(key))
        return false;
    QJsonObject object = m_settings.value(gameId).toObject();
    object.insert(key, QJsonValue::fromVariant(value));
    m_settings.insert(gameId, object);
    if (!saveState())
        return false;
    refresh();
    return true;
}

QVariantMap GamesManager::selectedEmulator(const QVariantMap &game) const
{
    const QString selected = game.value(QStringLiteral("emulatorId")).toString();
    const QVariantList options = game.value(QStringLiteral("emulators")).toList();
    for (const QVariant &entry : options) {
        const QVariantMap option = entry.toMap();
        if (option.value(QStringLiteral("id")).toString() == selected)
            return option;
    }
    return options.isEmpty() ? QVariantMap{} : options.first().toMap();
}

QString GamesManager::writeRetroArchConfig(const QVariantMap &game) const
{
    // Debian's RetroArch package can be installed without the separate
    // joypad-autoconfig data package.  In that state the udev driver detects
    // the controller but reports it as "not configured", so games receive no
    // buttons even though NeutronOS can still observe the Start-button hold.
    // Keep a NeutronOS-owned, deterministic profile for the controller that is
    // actually used by the shell and point RetroArch at that profile directory.
    const QString autoconfigRoot = QDir(m_runtimeDirectory)
            .filePath(QStringLiteral("autoconfig"));
    const QString udevAutoconfig = QDir(autoconfigRoot)
            .filePath(QStringLiteral("udev"));
    if (!QDir().mkpath(udevAutoconfig))
        return QString();

    const QString dualShockProfilePath = QDir(udevAutoconfig)
            .filePath(QStringLiteral("Sony DualShock 4 Controller.cfg"));
    QSaveFile dualShockProfile(dualShockProfilePath);
    if (!dualShockProfile.open(QIODevice::WriteOnly | QIODevice::Text))
        return QString();
    QTextStream profileStream(&dualShockProfile);
    profileStream << "input_driver = \"udev\"\n";
    profileStream << "input_device = \"Sony Interactive Entertainment Wireless Controller\"\n";
    profileStream << "input_device_display_name = \"Sony DualShock 4 Controller (v2)\"\n";
    profileStream << "input_vendor_id = \"1356\"\n";
    profileStream << "input_product_id = \"2508\"\n";
    profileStream << "input_device_alt1 = \"Wireless Controller\"\n";
    profileStream << "input_device_display_name_alt1 = \"Sony DualShock 4 Controller (v2)\"\n";
    profileStream << "input_vendor_id_alt1 = \"1356\"\n";
    profileStream << "input_product_id_alt1 = \"2508\"\n";
    profileStream << "input_device_alt2 = \"Sony Computer Entertainment Wireless Controller\"\n";
    profileStream << "input_device_display_name_alt2 = \"Sony DualShock 4 Controller (v1)\"\n";
    profileStream << "input_vendor_id_alt2 = \"1356\"\n";
    profileStream << "input_product_id_alt2 = \"1476\"\n";
    profileStream << "input_b_btn = \"0\"\n";
    profileStream << "input_y_btn = \"3\"\n";
    profileStream << "input_select_btn = \"8\"\n";
    profileStream << "input_start_btn = \"9\"\n";
    profileStream << "input_up_btn = \"h0up\"\n";
    profileStream << "input_down_btn = \"h0down\"\n";
    profileStream << "input_left_btn = \"h0left\"\n";
    profileStream << "input_right_btn = \"h0right\"\n";
    profileStream << "input_a_btn = \"1\"\n";
    profileStream << "input_x_btn = \"2\"\n";
    profileStream << "input_l_btn = \"4\"\n";
    profileStream << "input_r_btn = \"5\"\n";
    profileStream << "input_l2_axis = \"+2\"\n";
    profileStream << "input_r2_axis = \"+5\"\n";
    profileStream << "input_l3_btn = \"11\"\n";
    profileStream << "input_r3_btn = \"12\"\n";
    profileStream << "input_l_x_plus_axis = \"+0\"\n";
    profileStream << "input_l_x_minus_axis = \"-0\"\n";
    profileStream << "input_l_y_plus_axis = \"+1\"\n";
    profileStream << "input_l_y_minus_axis = \"-1\"\n";
    profileStream << "input_r_x_plus_axis = \"+3\"\n";
    profileStream << "input_r_x_minus_axis = \"-3\"\n";
    profileStream << "input_r_y_plus_axis = \"+4\"\n";
    profileStream << "input_r_y_minus_axis = \"-4\"\n";
    profileStream << "input_menu_toggle_btn = \"10\"\n";
    profileStream << "input_b_btn_label = \"Cross\"\n";
    profileStream << "input_y_btn_label = \"Square\"\n";
    profileStream << "input_select_btn_label = \"Share\"\n";
    profileStream << "input_start_btn_label = \"Options\"\n";
    profileStream << "input_a_btn_label = \"Circle\"\n";
    profileStream << "input_x_btn_label = \"Triangle\"\n";
    profileStream << "input_l_btn_label = \"L1\"\n";
    profileStream << "input_r_btn_label = \"R1\"\n";
    profileStream << "input_l2_axis_label = \"L2 Trigger\"\n";
    profileStream << "input_r2_axis_label = \"R2 Trigger\"\n";
    if (!dualShockProfile.commit())
        return QString();

    const QString path = QDir(m_runtimeDirectory).filePath(QStringLiteral("retroarch-neutronos.cfg"));
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return QString();
    QTextStream stream(&file);
    // NeutronOS launches RetroArch on a real Linux virtual terminal. Force the
    // KMS/EGL console path instead of allowing an old desktop-oriented user
    // configuration (X11, Wayland, glcore, SDL, etc.) to win video setup.
    stream << "video_driver = \"gl\"\n";
    stream << "video_context_driver = \"wayland\"\n";
    stream << "video_fullscreen = \"true\"\n";
    stream << "video_windowed_fullscreen = \"false\"\n";
    stream << "video_threaded = \"false\"\n";
    stream << "video_shared_context = \"false\"\n";
    stream << "video_vsync = \"true\"\n";
    stream << "input_driver = \"udev\"\n";
    stream << "input_joypad_driver = \"udev\"\n";
    stream << "input_autodetect_enable = \"true\"\n";
    stream << "joypad_autoconfig_dir = \"" << autoconfigRoot << "\"\n";
    stream << "input_max_users = \"4\"\n";
    stream << "input_player1_joypad_index = \"0\"\n";
    // Let the left stick control digital-only systems such as NES while the
    // physical D-pad remains available through the hat bindings above.
    stream << "input_player1_analog_dpad_mode = \"1\"\n";
    stream << "audio_driver = \"alsa\"\n";
    stream << "menu_driver = \"rgui\"\n";
    stream << "pause_nonactive = \"false\"\n";
    stream << "savestate_auto_save = \"true\"\n";
    stream << "savestate_auto_load = \"true\"\n";
    stream << "savestate_file_compression = \"true\"\n";
    stream << "savestate_directory = \"" << QDir(m_runtimeDirectory).filePath(QStringLiteral("states")) << "\"\n";
    stream << "savefile_directory = \"" << QDir(m_runtimeDirectory).filePath(QStringLiteral("saves")) << "\"\n";
    const QString aspect = game.value(QStringLiteral("aspect")).toString();
    if (aspect == QStringLiteral("4:3")) {
        stream << "video_aspect_ratio_auto = \"false\"\n";
        stream << "video_aspect_ratio = \"1.333333\"\n";
    } else if (aspect == QStringLiteral("16:9")) {
        stream << "video_aspect_ratio_auto = \"false\"\n";
        stream << "video_aspect_ratio = \"1.777778\"\n";
    } else {
        stream << "video_aspect_ratio_auto = \"true\"\n";
    }
    stream << "video_scale_integer = \""
           << (game.value(QStringLiteral("integerScale")).toBool() ? "true" : "false")
           << "\"\n";
    const QString gameProfile = game.value(QStringLiteral("profile")).toString();
    if (gameProfile == QStringLiteral("ECO")) {
        stream << "video_smooth = \"false\"\n";
        stream << "audio_latency = \"96\"\n";
    } else if (gameProfile == QStringLiteral("PERFORMANCE")) {
        stream << "video_smooth = \"true\"\n";
        stream << "audio_latency = \"48\"\n";
    } else {
        stream << "video_smooth = \"true\"\n";
        stream << "audio_latency = \"64\"\n";
    }
    if (!file.commit())
        return QString();
    return path;
}

bool GamesManager::prepareLaunch(const QVariantMap &game,
                                 const QVariantMap &emulator,
                                 QString *program,
                                 QStringList *arguments,
                                 QString *errorMessage)
{
    if (game.isEmpty() || emulator.isEmpty()) {
        *errorMessage = QStringLiteral("No compatible emulator or cloud runtime is installed.");
        return false;
    }

    const QString kind = emulator.value(QStringLiteral("kind")).toString();
    const QString emulatorProgram = emulator.value(QStringLiteral("program")).toString();
    const QString romPath = game.value(QStringLiteral("path")).toString();
    const bool requiresRom = kind != QStringLiteral("moonlight")
                             && kind != QStringLiteral("moonlight-flatpak")
                             && kind != QStringLiteral("cloud-browser");

    if (emulatorProgram.isEmpty() || !QFileInfo::exists(emulatorProgram)) {
        *errorMessage = QStringLiteral("The selected runtime is no longer installed.");
        return false;
    }
    if (requiresRom && (romPath.isEmpty() || !QFileInfo::exists(romPath))) {
        *errorMessage = QStringLiteral("The selected game file is no longer available.");
        return false;
    }

    QStringList emulatorArguments;
    if (kind == QStringLiteral("retroarch")) {
        const QString core = emulator.value(QStringLiteral("core")).toString();
        if (!QFileInfo::exists(core)) {
            *errorMessage = QStringLiteral("The selected Libretro core is missing.");
            return false;
        }
        const QString config = writeRetroArchConfig(game);
        emulatorArguments << QStringLiteral("--verbose")
                          << QStringLiteral("--fullscreen")
                          << QStringLiteral("-L") << core;
        if (!config.isEmpty())
            emulatorArguments << QStringLiteral("--appendconfig") << config;
        emulatorArguments << romPath;
    } else if (kind == QStringLiteral("dolphin")) {
        emulatorArguments << QStringLiteral("-b") << QStringLiteral("-e") << romPath;
    } else if (kind == QStringLiteral("mupen64plus")) {
        emulatorArguments << QStringLiteral("--fullscreen") << romPath;
    } else if (kind == QStringLiteral("pcsx")) {
        emulatorArguments << QStringLiteral("-cdfile") << romPath;
    } else if (kind == QStringLiteral("play")) {
        emulatorArguments << QStringLiteral("--disc") << romPath;
    } else if (kind == QStringLiteral("ruffle")) {
        const QString player = emulator.value(QStringLiteral("player")).toString();
        if (player.isEmpty() || !QFileInfo::exists(player)) {
            *errorMessage = QStringLiteral("Ruffle is installed incompletely.");
            return false;
        }
        emulatorArguments << QStringLiteral("-s") << QStringLiteral("--")
                          << player << QStringLiteral("--fullscreen") << romPath;
    } else if (kind == QStringLiteral("moonlight")) {
        const QString client = emulator.value(QStringLiteral("client")).toString();
        if (client.isEmpty() || !QFileInfo::exists(client)) {
            *errorMessage = QStringLiteral("The Moonlight client is incomplete.");
            return false;
        }
        emulatorArguments << QStringLiteral("-s") << QStringLiteral("--") << client;
    } else if (kind == QStringLiteral("moonlight-flatpak")) {
        const QString flatpak = emulator.value(QStringLiteral("flatpak")).toString();
        if (flatpak.isEmpty() || !QFileInfo::exists(flatpak)) {
            *errorMessage = QStringLiteral("Flatpak is not available for Moonlight.");
            return false;
        }
        emulatorArguments << QStringLiteral("-s") << QStringLiteral("--")
                          << flatpak << QStringLiteral("run")
                          << emulator.value(QStringLiteral("applicationId")).toString();
    } else if (kind == QStringLiteral("cloud-browser")) {
        const QString browser = emulator.value(QStringLiteral("browser")).toString();
        const QString url = emulator.value(QStringLiteral("url")).toString();
        if (browser.isEmpty() || !QFileInfo::exists(browser) || url.isEmpty()) {
            *errorMessage = QStringLiteral("The cloud browser runtime is incomplete.");
            return false;
        }
        emulatorArguments << QStringLiteral("-s") << QStringLiteral("--")
                          << browser
                          << QStringLiteral("--kiosk")
                          << QStringLiteral("--start-fullscreen")
                          << QStringLiteral("--no-first-run")
                          << QStringLiteral("--disable-session-crashed-bubble")
                          << QStringLiteral("--disable-infobars")
                          << QStringLiteral("--enable-features=UseOzonePlatform")
                          << QStringLiteral("--ozone-platform=wayland")
                          << url;
    } else if (kind != QStringLiteral("moonlight")) {
        emulatorArguments << romPath;
    }

    // Return the actual emulator command.  Patch 49 launches it from an
    // independent systemd scope after neutronos.service has stopped and
    // released EGLFS/DRM.  Starting a second KMS owner while NeutronShell is
    // alive is what caused video_driver_init_internal() to fail.
    m_shellVt = foregroundVt();
    m_gameVt = chooseGameVt(m_shellVt);
    *program = emulatorProgram;
    *arguments = emulatorArguments;
    m_usesProcessGroup = false;
    return true;
}

bool GamesManager::beginPreparedLaunch(const QVariantMap &game,
                                       const QVariantMap &emulator)
{
    QString program;
    QStringList arguments;
    QString errorMessage;
    if (!prepareLaunch(game, emulator, &program, &arguments, &errorMessage)) {
        setMessage(errorMessage);
        emit gameLaunchFailed(errorMessage);
        return false;
    }

    m_runningGameId = game.value(QStringLiteral("id")).toString();
    m_runningGameTitle = game.value(QStringLiteral("title")).toString();
    m_gamePaused = false;
    m_stopRequested = false;
    m_processLog.clear();

    const QString gamePath = game.value(QStringLiteral("path")).toString();
    const QString workingDirectory = gamePath.isEmpty()
            ? m_romRoot
            : QFileInfo(gamePath).absolutePath();

    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    if (emulator.value(QStringLiteral("kind")).toString() == QStringLiteral("retroarch")) {
        environment.remove(QStringLiteral("DISPLAY"));
        environment.remove(QStringLiteral("WAYLAND_DISPLAY"));
        environment.remove(QStringLiteral("QT_QPA_PLATFORM"));
        environment.insert(QStringLiteral("XDG_SESSION_TYPE"), QStringLiteral("wayland"));
        environment.insert(QStringLiteral("WAYLAND_DISPLAY"), QStringLiteral("wayland-0"));
        environment.insert(QStringLiteral("XDG_RUNTIME_DIR"), QStringLiteral("/run/neutronos-compositor"));
        environment.insert(QStringLiteral("SDL_VIDEODRIVER"), QStringLiteral("wayland"));
        environment.insert(QStringLiteral("SDL_AUDIODRIVER"), QStringLiteral("alsa"));
    }

    if (beginExternalLaunch(game, emulator, program, arguments,
                            environment, workingDirectory, &errorMessage)) {
        setMessage(QStringLiteral("Preparing %1. NeutronOS will release the display for the emulator.")
                   .arg(m_runningGameTitle));
        emit runtimeChanged();
        emit gameStarted(m_runningGameId, m_runningGameTitle);
        return true;
    }

    m_runningGameId.clear();
    m_runningGameTitle.clear();
    setMessage(errorMessage);
    emit runtimeChanged();
    emit gameLaunchFailed(errorMessage);
    return false;
}

bool GamesManager::beginExternalLaunch(const QVariantMap &game,
                                       const QVariantMap &emulator,
                                       const QString &program,
                                       const QStringList &arguments,
                                       const QProcessEnvironment &environment,
                                       const QString &workingDirectory,
                                       QString *errorMessage)
{
    const QString systemdRun = executable({QStringLiteral("systemd-run")});
    const QString python = executable({QStringLiteral("python3")});
    const QString supervisor = QDir(m_neutronRoot)
            .filePath(QStringLiteral("scripts/neutronos-game-supervisor.py"));
    const QString runtimeHelper = QDir(m_neutronRoot)
            .filePath(QStringLiteral("scripts/neutronos-game-runtime.sh"));

    if (systemdRun.isEmpty() || python.isEmpty()
            || !QFileInfo(supervisor).isReadable()
            || !QFileInfo(runtimeHelper).isExecutable()) {
        *errorMessage = QStringLiteral("The NeutronOS display-handoff runtime is not installed correctly.");
        return false;
    }

    m_shellVt = foregroundVt();
    m_gameVt = chooseGameVt(m_shellVt);
    m_externalSessionId = QStringLiteral("%1-%2")
            .arg(QDateTime::currentMSecsSinceEpoch())
            .arg(QCoreApplication::applicationPid());

    QJsonArray argumentArray;
    for (const QString &argument : arguments)
        argumentArray.append(argument);

    QJsonObject environmentObject;
    const QStringList environmentEntries = environment.toStringList();
    for (const QString &entry : environmentEntries) {
        const qsizetype separator = entry.indexOf(QLatin1Char('='));
        if (separator > 0)
            environmentObject.insert(entry.left(separator), entry.mid(separator + 1));
    }

    QJsonObject spec;
    spec.insert(QStringLiteral("version"), 1);
    spec.insert(QStringLiteral("humanUser"), HumanHome::sessionUser());
    spec.insert(QStringLiteral("humanHome"), HumanHome::path());
    spec.insert(QStringLiteral("sessionId"), m_externalSessionId);
    spec.insert(QStringLiteral("gameId"), game.value(QStringLiteral("id")).toString());
    spec.insert(QStringLiteral("title"), game.value(QStringLiteral("title")).toString());
    spec.insert(QStringLiteral("kind"), emulator.value(QStringLiteral("kind")).toString());
    spec.insert(QStringLiteral("program"), program);
    spec.insert(QStringLiteral("arguments"), argumentArray);
    spec.insert(QStringLiteral("environment"), environmentObject);
    spec.insert(QStringLiteral("workingDirectory"), workingDirectory);
    spec.insert(QStringLiteral("shellVt"), m_shellVt);
    spec.insert(QStringLiteral("gameVt"), m_gameVt);
    spec.insert(QStringLiteral("statePath"), m_externalStatePath);
    spec.insert(QStringLiteral("commandPath"), m_externalCommandPath);
    spec.insert(QStringLiteral("logPath"), QDir(m_runtimeDirectory)
                .filePath(QStringLiteral("last-runtime.log")));
    spec.insert(QStringLiteral("exitCodePath"), QDir(m_runtimeDirectory)
                .filePath(QStringLiteral("last-exit-code")));
    spec.insert(QStringLiteral("pidPath"), QDir(m_runtimeDirectory)
                .filePath(QStringLiteral("runtime.pid")));
    spec.insert(QStringLiteral("runtimeHelper"), runtimeHelper);
    spec.insert(QStringLiteral("user"), QJsonObject::fromVariantMap(m_sessionUser));

    QSaveFile specFile(m_externalSpecPath);
    if (!specFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        *errorMessage = QStringLiteral("Unable to create the protected game launch specification.");
        return false;
    }
    specFile.write(QJsonDocument(spec).toJson(QJsonDocument::Indented));
    if (!specFile.commit()) {
        *errorMessage = QStringLiteral("Unable to commit the game launch specification.");
        return false;
    }
    QFile::setPermissions(m_externalSpecPath,
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    QFile::remove(m_externalCommandPath);

    const QString unitName = QStringLiteral("neutronos-game-session-%1")
            .arg(m_externalSessionId);
    QStringList runArguments{
        QStringLiteral("--unit=%1").arg(unitName),
        QStringLiteral("--collect"),
        QStringLiteral("--no-block"),
        QStringLiteral("--property=Type=exec"),
        QStringLiteral("--property=User=root"),
        QStringLiteral("--property=Group=root"),
        QStringLiteral("--property=KillMode=mixed"),
        QStringLiteral("--property=TimeoutStopSec=10s"),
        python,
        supervisor,
        m_externalSpecPath
    };

    QProcess launcher;
    launcher.start(systemdRun, runArguments);
    if (!launcher.waitForFinished(6000)
            || launcher.exitStatus() != QProcess::NormalExit
            || launcher.exitCode() != 0) {
        const QString detail = QString::fromUtf8(launcher.readAll()).trimmed();
        *errorMessage = QStringLiteral("Unable to start the isolated game session. %1")
                .arg(detail.isEmpty() ? launcher.errorString() : detail.right(500));
        return false;
    }

    m_externalGameActive = true;
    m_externalGamePaused = false;
    m_externalPhase = QStringLiteral("launching");
    return true;
}

int GamesManager::foregroundVt() const
{
    const QString fgconsole = executable({QStringLiteral("fgconsole")});
    if (fgconsole.isEmpty())
        return 1;
    QProcess process;
    process.start(fgconsole, QStringList{});
    if (!process.waitForFinished(1500))
        return 1;
    bool ok = false;
    const int vt = QString::fromUtf8(process.readAllStandardOutput()).trimmed().toInt(&ok);
    return ok && vt > 0 ? vt : 1;
}

int GamesManager::chooseGameVt(int shellVt) const
{
    return shellVt == 2 ? 3 : 2;
}

bool GamesManager::switchVt(int vt) const
{
    Q_UNUSED(vt);
    // Gemini's shared Wayland compositor retains its firmware-selected VT.
    return true;
}


bool GamesManager::signalProcessGroup(int signalNumber) const
{
    const qint64 pid = m_gameProcess.processId();
    if (pid <= 0)
        return false;
    const pid_t target = static_cast<pid_t>(pid);
    if (m_usesProcessGroup)
        return ::kill(-target, signalNumber) == 0;
    return ::kill(target, signalNumber) == 0;
}

bool GamesManager::launchGame(const QString &gameId)
{
    return launchGameForUser(gameId, QVariantMap{});
}

bool GamesManager::launchGameForUser(const QString &gameId,
                                     const QVariantMap &sessionUser)
{
    if (HumanHome::path().isEmpty()) {
        setMessage(QStringLiteral("An authenticated human account is required."));
        return false;
    }
    if (installerRunning()) {
        setMessage(QStringLiteral("Wait for the current emulator installation to finish."));
        return false;
    }
    if (gameRunning()) {
        setMessage(QStringLiteral("A game is already running."));
        return false;
    }
    const QVariantMap game = findGame(gameId);
    if (game.isEmpty()) {
        setMessage(QStringLiteral("The selected game is no longer available."));
        return false;
    }
    m_sessionUser = sessionUser;
    const QVariantMap emulator = selectedEmulator(game);
    if (emulator.isEmpty()) {
        const QVariantList installers = compatibleInstallers(gameId);
        const QString message = installers.isEmpty()
                ? QStringLiteral("No compatible emulator installer is available for this system.")
                : QStringLiteral("Choose a compatible emulator to install.");
        setMessage(message);
        if (!installers.isEmpty())
            emit emulatorInstallRequired(gameId, installers);
        else
            emit gameLaunchFailed(message);
        return false;
    }
    return beginPreparedLaunch(game, emulator);
}

QVariantMap GamesManager::consumeReturnSession()
{
    QVariantMap state = readExternalState();
    if (!state.value(QStringLiteral("returnPending")).toBool())
        return QVariantMap{};

    QVariantMap result = state;
    result.insert(QStringLiteral("pending"), true);
    state.insert(QStringLiteral("returnPending"), false);
    writeExternalState(state);

    const QString sessionId = result.value(QStringLiteral("sessionId")).toString();
    if (!result.value(QStringLiteral("active")).toBool()
            && !sessionId.isEmpty()
            && m_lastCompletedExternalSessionId != sessionId) {
        m_lastCompletedExternalSessionId = sessionId;
        updateUsageAfterLaunch(result.value(QStringLiteral("gameId")).toString());
        refresh();
    }
    return result;
}

bool GamesManager::installEmulatorAndLaunch(const QString &gameId,
                                            const QString &installerId)
{
    if (installerRunning() || gameRunning())
        return false;
    const QVariantMap game = findGame(gameId);
    if (game.isEmpty()) {
        setMessage(QStringLiteral("The selected library item is no longer available."));
        return false;
    }

    QVariantMap installer;
    const QVariantList installers = compatibleInstallers(gameId);
    for (const QVariant &entry : installers) {
        const QVariantMap option = entry.toMap();
        if (option.value(QStringLiteral("id")).toString() == installerId) {
            installer = option;
            break;
        }
    }
    if (installer.isEmpty()) {
        setMessage(QStringLiteral("That emulator installer is not compatible with the selected game."));
        return false;
    }

    QString program;
    QStringList arguments;
    const QString kind = installer.value(QStringLiteral("installerKind")).toString();
    if (kind == QStringLiteral("apt")) {
        program = executable({QStringLiteral("apt-get")});
        if (program.isEmpty()) {
            setMessage(QStringLiteral("apt-get is not available."));
            return false;
        }
        arguments << QStringLiteral("-y") << QStringLiteral("install");
        const QStringList packages = installer.value(QStringLiteral("packages")).toStringList();
        if (packages.isEmpty()) {
            setMessage(QStringLiteral("The installer has no package list."));
            return false;
        }
        arguments.append(packages);
    } else if (kind == QStringLiteral("ruffle")) {
        program = QDir(m_neutronRoot).filePath(QStringLiteral("scripts/install-ruffle-amd64.py"));
        if (!QFileInfo::exists(program)) {
            setMessage(QStringLiteral("The Ruffle installer helper is missing."));
            return false;
        }
    } else if (kind == QStringLiteral("moonlight")) {
        program = QDir(m_neutronRoot).filePath(QStringLiteral("scripts/install-moonlight-flatpak.sh"));
        if (!QFileInfo::exists(program)) {
            setMessage(QStringLiteral("The Moonlight installer helper is missing."));
            return false;
        }
    } else {
        setMessage(QStringLiteral("Unsupported emulator installation method."));
        return false;
    }

    m_pendingInstallGameId = gameId;
    m_pendingInstallerId = installerId;
    m_installerLog.clear();
    m_installerProgress = 5;
    setInstallerStatus(QStringLiteral("Installing %1…").arg(installer.value(QStringLiteral("label")).toString()), 5);
    m_installerProcess.start(program, arguments);
    if (!m_installerProcess.waitForStarted(3000)) {
        const QString message = QStringLiteral("Unable to start emulator installation: %1")
                                .arg(m_installerProcess.errorString());
        m_pendingInstallGameId.clear();
        m_pendingInstallerId.clear();
        setInstallerStatus(message, 0);
        setMessage(message);
        emit emulatorInstallFinished(false, message);
        return false;
    }
    emit installerChanged();
    return true;
}

bool GamesManager::cancelEmulatorInstall()
{
    if (!installerRunning())
        return false;
    m_installerProcess.terminate();
    if (!m_installerProcess.waitForFinished(1500))
        m_installerProcess.kill();
    setInstallerStatus(QStringLiteral("Emulator installation cancelled."), 0);
    setMessage(m_installerStatus);
    return true;
}

void GamesManager::collectInstallerOutput()
{
    m_installerLog += QString::fromUtf8(m_installerProcess.readAll());
    if (m_installerLog.size() > 24000)
        m_installerLog = m_installerLog.right(24000);
    QString latest = m_installerLog.trimmed().section(QLatin1Char('\n'), -1).trimmed();
    if (latest.isEmpty())
        latest = QStringLiteral("Installing emulator components…");
    setInstallerStatus(latest.left(180), qMin(92, m_installerProgress + 4));
}

void GamesManager::handleInstallerFinished(int exitCode, QProcess::ExitStatus status)
{
    collectInstallerOutput();
    const QString gameId = m_pendingInstallGameId;
    const QString installerId = m_pendingInstallerId;
    m_pendingInstallGameId.clear();
    m_pendingInstallerId.clear();

    const bool success = status == QProcess::NormalExit && exitCode == 0;
    if (!success) {
        const QString detail = m_installerLog.trimmed().right(500);
        const QString message = QStringLiteral("Emulator installation failed. %1").arg(detail);
        setInstallerStatus(message, 0);
        setMessage(message);
        emit installerChanged();
        emit emulatorInstallFinished(false, message);
        return;
    }

    setInstallerStatus(QStringLiteral("Installation complete. Detecting the new emulator…"), 96);
    refresh();
    QVariantMap game = findGame(gameId);
    const QVariantList detected = game.value(QStringLiteral("emulators")).toList();
    QVariantMap selected;
    for (const QVariant &entry : detected) {
        const QVariantMap option = entry.toMap();
        if (option.value(QStringLiteral("id")).toString() == installerId) {
            selected = option;
            break;
        }
    }
    if (selected.isEmpty() && !detected.isEmpty())
        selected = detected.first().toMap();

    if (selected.isEmpty()) {
        const QString message = QStringLiteral("Installation completed, but NeutronOS could not detect the emulator runtime.");
        setInstallerStatus(message, 100);
        setMessage(message);
        emit installerChanged();
        emit emulatorInstallFinished(false, message);
        return;
    }

    QJsonObject settings = m_settings.value(gameId).toObject();
    settings.insert(QStringLiteral("emulatorId"), selected.value(QStringLiteral("id")).toString());
    m_settings.insert(gameId, settings);
    saveState();
    refresh();
    game = findGame(gameId);

    const QString message = QStringLiteral("%1 installed. Launching %2…")
                            .arg(selected.value(QStringLiteral("label")).toString(),
                                 game.value(QStringLiteral("title")).toString());
    setInstallerStatus(message, 100);
    setMessage(message);
    emit installerChanged();
    emit emulatorInstallFinished(true, message);
    beginPreparedLaunch(game, selectedEmulator(game));
}

void GamesManager::handleInstallerError(QProcess::ProcessError error)
{
    Q_UNUSED(error)
    const QString message = QStringLiteral("Emulator installer error: %1")
                            .arg(m_installerProcess.errorString());
    setInstallerStatus(message, 0);
    setMessage(message);
    emit emulatorInstallFinished(false, message);
}

void GamesManager::handleProcessStarted()
{
    setMessage(QStringLiteral("%1 is running. Hold Settings for 3 seconds to return to NeutronOS.")
               .arg(m_runningGameTitle));
    emit runtimeChanged();
    emit gameStarted(m_runningGameId, m_runningGameTitle);
}

void GamesManager::collectProcessOutput()
{
    m_processLog += QString::fromUtf8(m_gameProcess.readAll());
    if (m_processLog.size() > 8192)
        m_processLog = m_processLog.right(8192);
}

void GamesManager::handleProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    collectProcessOutput();
    const QString finishedId = m_runningGameId;
    const QString finishedTitle = m_runningGameTitle;

    const QString statusPath = QDir(m_runtimeDirectory)
                               .filePath(QStringLiteral("last-exit-code"));
    const QString logPath = QDir(m_runtimeDirectory)
                            .filePath(QStringLiteral("last-runtime.log"));

    QString runtimeLog;
    QFile logFile(logPath);
    if (logFile.open(QIODevice::ReadOnly | QIODevice::Text))
        runtimeLog = QString::fromUtf8(logFile.readAll());
    if (!runtimeLog.trimmed().isEmpty()) {
        m_processLog += runtimeLog;
        if (m_processLog.size() > 32768)
            m_processLog = m_processLog.right(32768);
    }

    bool emulatorStatusAvailable = false;
    int emulatorExitCode = -1;
    QFile statusFile(statusPath);
    if (statusFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        bool ok = false;
        const int recorded = QString::fromUtf8(statusFile.readAll()).trimmed().toInt(&ok);
        if (ok) {
            emulatorStatusAvailable = true;
            emulatorExitCode = recorded;
        }
    }

    // When the helper recorded an emulator result, that is authoritative.
    // openvt may return non-zero solely because VT_DISALLOCATE failed after a
    // successful game session; that cleanup warning must not be presented as
    // an emulator failure.  Intentional Exit is also a clean NeutronOS action.
    const bool clean = m_stopRequested
            || (emulatorStatusAvailable && emulatorExitCode == 0)
            || (!emulatorStatusAvailable
                && status == QProcess::NormalExit
                && exitCode == 0);

    switchVt(m_shellVt);
    m_gamePaused = false;
    m_stopRequested = false;
    m_runningGameId.clear();
    m_runningGameTitle.clear();
    updateUsageAfterLaunch(finishedId);
    refresh();

    QString detail = m_processLog.trimmed();
    if (!emulatorStatusAvailable && detail.isEmpty())
        detail = QStringLiteral("The game session did not report an emulator exit status.");
    if (detail.size() > 420)
        detail = detail.right(420);

    setMessage(clean
               ? QStringLiteral("%1 closed normally.").arg(finishedTitle)
               : QStringLiteral("%1 closed with an emulator error. %2")
                     .arg(finishedTitle, detail));
    emit runtimeChanged();
    emit gameStopped(finishedId, finishedTitle, clean);
}

void GamesManager::handleProcessError(QProcess::ProcessError error)
{
    Q_UNUSED(error)
    setMessage(QStringLiteral("Game runtime error: %1").arg(m_gameProcess.errorString()));
}

bool GamesManager::pauseForExitMenu()
{
    if (!gameRunning())
        return false;
    if (m_externalGamePaused)
        return true;
    if (m_externalGameActive) {
        setMessage(QStringLiteral("The external game session handles the three-second Settings hold."));
        return false;
    }
    if (!m_gamePaused) {
        if (!signalProcessGroup(SIGSTOP)) {
            setMessage(QStringLiteral("Unable to pause the emulator process."));
            return false;
        }
        switchVt(m_shellVt);
        m_gamePaused = true;
        setMessage(QStringLiteral("Game paused. Choose Resume or Exit."));
        emit runtimeChanged();
    }
    return true;
}

bool GamesManager::resumeGame()
{
    if (m_externalGameActive && m_externalGamePaused) {
        if (!writeExternalCommand(QStringLiteral("resume"))) {
            setMessage(QStringLiteral("Unable to send Resume to the game-session supervisor."));
            return false;
        }
        setMessage(QStringLiteral("Resuming game…"));
        return true;
    }
    if (!gameRunning() || !m_gamePaused)
        return false;
    if (!signalProcessGroup(SIGCONT)) {
        setMessage(QStringLiteral("Unable to resume the emulator process."));
        return false;
    }
    m_gamePaused = false;
    switchVt(m_gameVt);
    setMessage(QStringLiteral("Game resumed."));
    emit runtimeChanged();
    return true;
}

bool GamesManager::stopGame()
{
    if (!gameRunning())
        return false;
    if (m_externalGameActive) {
        if (!writeExternalCommand(QStringLiteral("exit"))) {
            setMessage(QStringLiteral("Unable to send Exit to the game-session supervisor."));
            return false;
        }
        setMessage(QStringLiteral("Closing game…"));
        return true;
    }
    m_stopRequested = true;
    if (m_gamePaused)
        signalProcessGroup(SIGCONT);
    switchVt(m_shellVt);
    m_gamePaused = false;
    signalProcessGroup(SIGTERM);
    QTimer::singleShot(2200, this, [this]() {
        if (gameRunning())
            signalProcessGroup(SIGKILL);
    });
    setMessage(QStringLiteral("Closing game…"));
    emit runtimeChanged();
    return true;
}


QVariantMap GamesManager::readExternalState() const
{
    QFile file(m_externalStatePath);
    if (!file.open(QIODevice::ReadOnly))
        return QVariantMap{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object().toVariantMap() : QVariantMap{};
}

bool GamesManager::writeExternalState(const QVariantMap &state) const
{
    QSaveFile file(m_externalStatePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    file.write(QJsonDocument(QJsonObject::fromVariantMap(state))
               .toJson(QJsonDocument::Indented));
    if (!file.commit())
        return false;
    QFile::setPermissions(m_externalStatePath,
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

bool GamesManager::writeExternalCommand(const QString &action) const
{
    if (action != QStringLiteral("resume") && action != QStringLiteral("exit"))
        return false;
    QJsonObject command;
    command.insert(QStringLiteral("action"), action);
    command.insert(QStringLiteral("sessionId"), m_externalSessionId);
    command.insert(QStringLiteral("createdAt"),
                   QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
    QSaveFile file(m_externalCommandPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    file.write(QJsonDocument(command).toJson(QJsonDocument::Compact));
    if (!file.commit())
        return false;
    QFile::setPermissions(m_externalCommandPath,
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

void GamesManager::pollExternalSession()
{
    const QVariantMap state = readExternalState();
    if (state.isEmpty())
        return;

    const QString sessionId = state.value(QStringLiteral("sessionId")).toString();
    const QString phase = state.value(QStringLiteral("phase")).toString();
    const bool active = state.value(QStringLiteral("active")).toBool();
    const bool paused = state.value(QStringLiteral("paused")).toBool();
    const QString gameId = state.value(QStringLiteral("gameId")).toString();
    const QString title = state.value(QStringLiteral("title")).toString();
    const QString message = state.value(QStringLiteral("message")).toString();

    const bool runtimeChangedValue = m_externalGameActive != active
            || m_externalGamePaused != paused
            || m_externalPhase != phase
            || (!gameId.isEmpty() && m_runningGameId != gameId)
            || (!title.isEmpty() && m_runningGameTitle != title);

    const bool wasActive = m_externalGameActive;
    m_externalSessionId = sessionId;
    m_externalGameActive = active;
    m_externalGamePaused = paused;
    m_externalPhase = phase;
    if (!gameId.isEmpty())
        m_runningGameId = gameId;
    if (!title.isEmpty())
        m_runningGameTitle = title;
    if (!message.isEmpty())
        setMessage(message);

    if (runtimeChangedValue)
        emit runtimeChanged();

    if (wasActive && !active && !sessionId.isEmpty()
            && m_lastCompletedExternalSessionId != sessionId) {
        m_lastCompletedExternalSessionId = sessionId;
        const bool clean = state.value(QStringLiteral("cleanExit")).toBool();
        updateUsageAfterLaunch(gameId);
        refresh();
        emit gameStopped(gameId, title, clean);
    }
}

void GamesManager::updateUsageAfterLaunch(const QString &gameId)
{
    if (gameId.isEmpty())
        return;
    QJsonObject object = m_usage.value(gameId).toObject();
    object.insert(QStringLiteral("lastPlayed"),
                  QDateTime::currentDateTime().toString(QStringLiteral("MMM d, yyyy  h:mm AP")));
    object.insert(QStringLiteral("playCount"), object.value(QStringLiteral("playCount")).toInt(0) + 1);
    m_usage.insert(gameId, object);
    saveState();
}

void GamesManager::loadState()
{
    QFile file(m_statePath);
    if (!file.open(QIODevice::ReadOnly))
        return;
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return;
    const QJsonObject root = document.object();
    const QJsonArray order = root.value(QStringLiteral("order")).toArray();
    for (const QJsonValue &value : order) {
        const QString id = value.toString();
        if (!id.isEmpty())
            m_order.append(id);
    }
    m_settings = root.value(QStringLiteral("settings")).toObject();
    m_usage = root.value(QStringLiteral("usage")).toObject();
}

bool GamesManager::saveState() const
{
    QJsonArray order;
    for (const QString &id : m_order)
        order.append(id);
    QJsonObject root;
    root.insert(QStringLiteral("version"), 1);
    root.insert(QStringLiteral("order"), order);
    root.insert(QStringLiteral("settings"), m_settings);
    root.insert(QStringLiteral("usage"), m_usage);
    QSaveFile file(m_statePath);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return file.commit();
}
