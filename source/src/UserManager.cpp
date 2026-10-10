#include "UserManager.h"
#include "HumanAccountPolicy.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTimer>
#include <QUrl>
#include <QVariant>
#include <QtGlobal>

#include <algorithm>
#include <utility>
#include <vector>

#include <grp.h>
#include <pwd.h>
#include <sys/types.h>
#include <unistd.h>

namespace
{
constexpr int RefreshCoalesceDelayMs = 120;
constexpr int MaximumDisplayNameLength = 48;
constexpr int MaximumProfileTaglineLength = 72;
constexpr double DefaultGlowStrength = 0.65;

QString environmentValue(const char *name)
{
    return QString::fromLocal8Bit(
               qgetenv(name)
           ).trimmed();
}

QString gecosDisplayName(const QString &gecos,
                         const QString &username)
{
    QString value =
        gecos.section(
            QLatin1Char(','),
            0,
            0
        ).trimmed();

    if (value.isEmpty())
        value = username;

    return value;
}

bool safeUsername(const QString &username)
{
    static const QRegularExpression pattern(
        QStringLiteral(
            "^[A-Za-z_][A-Za-z0-9_.-]{0,63}$"
        )
    );

    return pattern.match(username)
        .hasMatch();
}

bool safeThemeName(const QString &theme)
{
    static const QRegularExpression pattern(
        QStringLiteral(
            "^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$"
        )
    );

    return pattern.match(theme)
        .hasMatch();
}

bool userInNamedGroup(const QString &username,
                      gid_t primaryGid,
                      const QByteArray &groupName)
{
    if (username.isEmpty() ||
            groupName.isEmpty()) {
        return false;
    }

    // Startup account discovery is intentionally local-only.  Consulting
    // `group: files winbind` here can hold LoginScreen behind optional domain
    // and RADIUS availability. Explicit authentication still uses PAM/NSS.
    QFile groups(QStringLiteral("/etc/group"));
    if (!groups.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    const QByteArray encodedUsername = username.toUtf8();
    while (!groups.atEnd()) {
        const QList<QByteArray> fields = groups.readLine().trimmed().split(':');
        if (fields.size() < 4 || fields.at(0) != groupName)
            continue;
        bool gidOk = false;
        const gid_t targetGid = static_cast<gid_t>(fields.at(2).toUInt(&gidOk));
        if (gidOk && primaryGid == targetGid)
            return true;
        for (const QByteArray &member : fields.at(3).split(',')) {
            if (member.trimmed() == encodedUsername)
                return true;
        }
        return false;
    }

    return false;
}

QString variantString(const QVariantMap &map,
                      const QStringList &keys,
                      const QString &fallback = QString())
{
    for (const QString &key : keys) {
        if (!map.contains(key))
            continue;

        const QString value =
            map.value(key)
                .toString()
                .trimmed();

        if (!value.isEmpty())
            return value;
    }

    return fallback;
}

QVariant nestedVariant(const QVariantMap &payload,
                       const QStringList &keys)
{
    for (const QString &key : keys) {
        if (payload.contains(key))
            return payload.value(key);
    }

    const QVariantMap user =
        payload.value(
            QStringLiteral("user")
        ).toMap();

    for (const QString &key : keys) {
        if (user.contains(key))
            return user.value(key);
    }

    return QVariant();
}

QString humanFileName(QString fileName)
{
    const int dot =
        fileName.lastIndexOf(
            QLatin1Char('.')
        );

    if (dot > 0)
        fileName.truncate(dot);

    fileName.replace(
        QLatin1Char('_'),
        QLatin1Char(' ')
    );

    fileName.replace(
        QLatin1Char('-'),
        QLatin1Char(' ')
    );

    QStringList words =
        fileName.simplified()
            .split(
                QLatin1Char(' '),
                Qt::SkipEmptyParts
            );

    for (QString &word : words) {
        if (!word.isEmpty()) {
            word[0] =
                word[0].toUpper();
        }
    }

    return words.join(
        QLatin1Char(' ')
    );
}

QString currentLoginStamp()
{
    return QDateTime::currentDateTime()
        .toString(
            QStringLiteral(
                "MMM d, yyyy h:mm AP"
            )
        );
}

bool variantIsMap(const QVariant &value)
{
    return value.userType() ==
           QMetaType::QVariantMap;
}

bool variantIsList(const QVariant &value)
{
    return value.userType() ==
           QMetaType::QVariantList;
}
}

/*
    ========================================================================
                              CONSTRUCTION
    ========================================================================
*/

UserManager::UserManager(QObject *parent)
    : QObject(parent)
{
    m_refreshCoalesceTimer.setSingleShot(
        true
    );

    m_refreshCoalesceTimer.setInterval(
        RefreshCoalesceDelayMs
    );

    connect(
        &m_refreshCoalesceTimer,
        &QTimer::timeout,
        this,
        &UserManager::coalescedRefresh
    );

    connect(
        &m_fileWatcher,
        &QFileSystemWatcher::fileChanged,
        this,
        &UserManager::onWatchedPathChanged
    );

    connect(
        &m_fileWatcher,
        &QFileSystemWatcher::directoryChanged,
        this,
        &UserManager::onWatchedPathChanged
    );

    m_activeTheme =
        readActiveTheme();

    discoverSystemUsers();
    discoverProfiles();
    discoverAvatars();

    rebuildAvailableUsers();
    rebuildAvailableAvatars();

    const SystemUserRecord current =
        currentSystemUser();

    if (current.valid) {
        const ProfileRecord profile =
            m_profiles.value(
                current.username,
                loadProfileRecord(
                    current.username
                )
            );

        applyActiveUserMap(
            buildUserMap(
                current,
                profile
            ),
            false
        );
    }

    rebuildAvailableUsers();
    rebuildWatchers();
}

UserManager::~UserManager()
{
    m_refreshCoalesceTimer.stop();

    const QStringList files =
        m_fileWatcher.files();

    if (!files.isEmpty())
        m_fileWatcher.removePaths(files);

    const QStringList directories =
        m_fileWatcher.directories();

    if (!directories.isEmpty())
        m_fileWatcher.removePaths(directories);
}

/*
    ========================================================================
                                  GETTERS
    ========================================================================
*/

QVariantMap UserManager::activeUser() const
{
    return m_activeUser;
}

QString UserManager::userId() const
{
    return m_userId;
}

QString UserManager::username() const
{
    return m_username;
}

QString UserManager::displayName() const
{
    return m_displayName;
}

QString UserManager::profileTagline() const
{
    return m_profileTagline;
}

QString UserManager::nameTint() const
{
    return m_nameTint;
}

QString UserManager::accentColor() const
{
    return m_accentColor;
}

QString UserManager::avatarFrame() const
{
    return m_avatarFrame;
}

double UserManager::glowStrength() const
{
    return m_glowStrength;
}

QString UserManager::role() const
{
    return m_role;
}

QString UserManager::avatarId() const
{
    return m_avatarId;
}

QString UserManager::avatarSource() const
{
    return m_avatarSource;
}

QString UserManager::homeDirectory() const
{
    return m_homeDirectory;
}

QString UserManager::lastLogin() const
{
    return m_lastLogin;
}

bool UserManager::profileWritable() const
{
    return m_profileWritable;
}

QVariantList UserManager::availableUsers() const
{
    return m_availableUsers;
}

QVariantList UserManager::availableAvatars() const
{
    return m_availableAvatars;
}

QString UserManager::activeTheme() const
{
    return m_activeTheme;
}

bool UserManager::operationBusy() const
{
    return m_operationBusy;
}

QString UserManager::lastError() const
{
    return m_lastError;
}

QString UserManager::lastOperation() const
{
    return m_lastOperation;
}

int UserManager::userRevision() const
{
    return m_userRevision;
}

int UserManager::profileRevision() const
{
    return m_profileRevision;
}

/*
    ========================================================================
                              REFRESH API
    ========================================================================
*/

void UserManager::refresh()
{
    coalescedRefresh();
}

void UserManager::refreshProfile()
{
    discoverProfiles();
    rebuildAvailableUsers();
    rebuildActiveUser();
    rebuildWatchers();
}

void UserManager::refreshAvatars()
{
    const QString detectedTheme =
        readActiveTheme();

    if (detectedTheme !=
            m_activeTheme) {
        m_activeTheme =
            detectedTheme;

        emit activeThemeChanged();
    }

    discoverAvatars();
    rebuildAvailableAvatars();
    rebuildActiveUser();
    rebuildAvailableUsers();
    rebuildWatchers();
}

void UserManager::refreshUsers()
{
    discoverSystemUsers();
    discoverProfiles();
    rebuildAvailableUsers();
    rebuildActiveUser();
    rebuildWatchers();
}

/*
    ========================================================================
                         ACTIVE USER SELECTION
    ========================================================================
*/

bool UserManager::setActiveUser(
    const QVariantMap &userContext)
{
    QString requestedUsername =
        normalizedUsername(
            variantString(
                userContext,
                QStringList()
                    << QStringLiteral("username")
                    << QStringLiteral("accountName")
                    << QStringLiteral("loginName")
            )
        );

    if (requestedUsername.isEmpty()) {
        const QString identifier =
            variantString(
                userContext,
                QStringList()
                    << QStringLiteral("userId")
                    << QStringLiteral("id")
            );

        if (safeUsername(identifier))
            requestedUsername = identifier;
    }

    if (requestedUsername.isEmpty()) {
        setLastError(
            QStringLiteral(
                "A valid local username is required"
            )
        );

        return false;
    }

    SystemUserRecord systemUser =
        m_systemUsers.value(
            requestedUsername
        );

    if (!systemUser.valid)
        systemUser =
            systemUserByName(
                requestedUsername
            );

    if (!systemUser.valid) {
        setLastError(
            QStringLiteral(
                "Local account '%1' was not found"
            ).arg(requestedUsername)
        );

        return false;
    }

    ProfileRecord profile =
        m_profiles.value(
            requestedUsername,
            loadProfileRecord(
                requestedUsername
            )
        );

    QVariantMap userMap =
        buildUserMap(
            systemUser,
            profile
        );

    userMap =
        mergeUserContext(
            userMap,
            userContext
        );

    /*
        setActiveUser is called after successful authentication. Record the
        session timestamp only in non-secret profile metadata.
    */
    profile.lastLogin =
        currentLoginStamp();

    profile.updatedAt =
        QDateTime::currentDateTimeUtc();

    profile.role =
        roleForSystemUser(
            systemUser
        );

    if (!userMap.value(
            QStringLiteral("displayName")
        ).toString().trimmed().isEmpty()) {
        profile.displayName =
            normalizedDisplayName(
                userMap.value(
                    QStringLiteral(
                        "displayName"
                    )
                ).toString()
            );
    }

    const AvatarRecord selectedAvatar =
        avatarRecordForValue(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral("avatarId")
                    << QStringLiteral("icon")
                    << QStringLiteral("avatarSource")
            )
        );

    if (!selectedAvatar.id.isEmpty()) {
        profile.avatarId =
            selectedAvatar.id;

        profile.avatarSource =
            selectedAvatar.source;
    }

    const bool profileSaved =
        saveProfileRecord(
            requestedUsername,
            profile
        );

    profile.valid = true;
    m_profiles.insert(
        requestedUsername,
        profile
    );

    userMap =
        buildUserMap(
            systemUser,
            profile
        );

    userMap =
        mergeUserContext(
            userMap,
            userContext
        );

    userMap[
        QStringLiteral("lastLogin")
    ] = profile.lastLogin;

    userMap[
        QStringLiteral("lastSignIn")
    ] = profile.lastLogin;

    const bool changed =
        applyActiveUserMap(
            userMap,
            true
        );

    rebuildAvailableUsers();
    rebuildWatchers();

    setLastError(QString());

    setLastOperation(
        profileSaved
        ? QStringLiteral(
              "Active user session updated"
          )
        : QStringLiteral(
              "Active user updated; profile metadata could not be persisted"
          )
    );

    return changed ||
           !m_activeUser.isEmpty();
}

bool UserManager::setActiveUserByName(
    const QString &usernameValue)
{
    QVariantMap context;

    context[
        QStringLiteral("username")
    ] = usernameValue;

    return setActiveUser(context);
}

void UserManager::clearActiveUser()
{
    HumanHome::setSessionUser(QString());
    const bool hadUser =
        !m_activeUser.isEmpty();

    const bool oldWritable =
        m_profileWritable;

    m_activeUser.clear();

    m_userId.clear();
    m_username.clear();
    m_displayName.clear();
    m_profileTagline.clear();
    m_nameTint = QStringLiteral("#FFFFFF");
    m_accentColor = QStringLiteral("#7DF9FF");
    m_avatarFrame = QStringLiteral("circle");
    m_glowStrength = DefaultGlowStrength;
    m_role =
        QStringLiteral("Admin");

    m_avatarId =
        QStringLiteral(
            "users/user_icon.png"
        );

    m_avatarSource =
        QStringLiteral(
            "users/user_icon.png"
        );

    m_homeDirectory.clear();
    m_lastLogin =
        QStringLiteral("--");

    m_profileWritable = false;

    if (!hadUser &&
            !oldWritable) {
        return;
    }

    if (oldWritable)
        emit profileWritableChanged();

    emit activeUserChanged();
    emit userChanged();

    incrementUserRevision();
    rebuildAvailableUsers();
}

/*
    ========================================================================
                              ACTION ROUTER
    ========================================================================
*/

bool UserManager::executeAction(
    const QString &action,
    const QVariantMap &payload)
{
    const QString normalized =
        normalizedAction(action);

    if (normalized ==
            QStringLiteral("applyprofile") ||
            normalized ==
            QStringLiteral("apply") ||
            normalized ==
            QStringLiteral("saveprofile")) {
        return applyProfile(payload);
    }

    if (normalized ==
            QStringLiteral("setdisplayname")) {
        return setDisplayName(
            nestedVariant(
                payload,
                QStringList()
                    << QStringLiteral(
                        "displayName"
                    )
                    << QStringLiteral("name")
            ).toString()
        );
    }

    if (normalized ==
            QStringLiteral("setavatar") ||
            normalized ==
            QStringLiteral("seticon")) {
        return setAvatar(
            nestedVariant(
                payload,
                QStringList()
                    << QStringLiteral("avatarId")
                    << QStringLiteral("icon")
                    << QStringLiteral(
                        "avatarSource"
                    )
            ).toString()
        );
    }

    if (normalized ==
            QStringLiteral("changelogincombo") ||
            normalized ==
            QStringLiteral("createlogincombo")) {
        const QVariantMap context =
            sessionPayload(
                payload,
                QStringLiteral(
                    "changeLoginCombo"
                )
            );

        beginOperation(
            QStringLiteral(
                "changeLoginCombo"
            ),
            context
        );

        emit loginComboChangeRequested(
            context
        );

        finishOperation(
            QStringLiteral(
                "changeLoginCombo"
            ),
            true,
            QStringLiteral(
                "Login combo change requested"
            ),
            context
        );

        return true;
    }

    if (normalized ==
            QStringLiteral("lock") ||
            normalized ==
            QStringLiteral("lockconsole")) {
        const QVariantMap context =
            sessionPayload(
                payload,
                QStringLiteral("lock")
            );

        beginOperation(
            QStringLiteral("lock"),
            context
        );

        emit lockRequested(context);

        finishOperation(
            QStringLiteral("lock"),
            true,
            QStringLiteral(
                "Console lock requested"
            ),
            context
        );

        return true;
    }

    if (normalized ==
            QStringLiteral("logout") ||
            normalized ==
            QStringLiteral("signout")) {
        const QVariantMap context =
            sessionPayload(
                payload,
                QStringLiteral("logout")
            );

        beginOperation(
            QStringLiteral("logout"),
            context
        );

        emit logoutRequested(context);

        finishOperation(
            QStringLiteral("logout"),
            true,
            QStringLiteral(
                "Logout requested"
            ),
            context
        );

        return true;
    }

    if (normalized ==
            QStringLiteral(
                "refreshsecurity"
            )) {
        const QVariantMap context =
            sessionPayload(
                payload,
                QStringLiteral(
                    "refreshSecurity"
                )
            );

        beginOperation(
            QStringLiteral(
                "refreshSecurity"
            ),
            context
        );

        emit securityRefreshRequested(
            context
        );

        finishOperation(
            QStringLiteral(
                "refreshSecurity"
            ),
            true,
            QStringLiteral(
                "Security refresh requested"
            ),
            context
        );

        return true;
    }

    if (normalized ==
            QStringLiteral("refresh") ||
            normalized ==
            QStringLiteral("refreshprofile")) {
        beginOperation(
            QStringLiteral("refresh"),
            sanitizedPayload(payload)
        );

        refresh();

        finishOperation(
            QStringLiteral("refresh"),
            true,
            QStringLiteral(
                "User profile refreshed"
            ),
            payload
        );

        return true;
    }

    if (normalized ==
            QStringLiteral("cancel")) {
        cancelPendingOperation();
        return true;
    }

    setLastError(
        QStringLiteral(
            "Unsupported user action: %1"
        ).arg(action)
    );

    return false;
}

/*
    ========================================================================
                         PROFILE MUTATION
    ========================================================================
*/

bool UserManager::applyProfile(
    const QVariantMap &payload)
{
    if (m_operationBusy)
        return false;

    if (m_username.isEmpty() ||
            m_activeUser.isEmpty()) {
        setLastError(
            QStringLiteral(
                "No authenticated user is active"
            )
        );

        return false;
    }

    const QString requestedUsername =
        normalizedUsername(
            nestedVariant(
                payload,
                QStringList()
                    << QStringLiteral("username")
                    << QStringLiteral(
                        "accountName"
                    )
                    << QStringLiteral("userId")
            ).toString()
        );

    if (!requestedUsername.isEmpty() &&
            requestedUsername !=
            m_username &&
            requestedUsername !=
            m_userId) {
        setLastError(
            QStringLiteral(
                "Profile changes may only target the active user"
            )
        );

        return false;
    }

    QString requestedDisplayName;
    QString requestedProfileTagline;
    QString requestedNameTint;
    QString requestedAccentColor;
    QString requestedAvatarFrame;
    double requestedGlowStrength = DefaultGlowStrength;
    AvatarRecord requestedAvatar;
    QString errorMessage;

    if (!validateProfilePayload(
            payload,
            &requestedDisplayName,
            &requestedProfileTagline,
            &requestedNameTint,
            &requestedAccentColor,
            &requestedAvatarFrame,
            &requestedGlowStrength,
            &requestedAvatar,
            &errorMessage)) {
        setLastError(errorMessage);
        return false;
    }

    const QVariantMap safePayload =
        sanitizedPayload(payload);

    beginOperation(
        QStringLiteral("applyProfile"),
        safePayload
    );

    const SystemUserRecord systemUser =
        m_systemUsers.value(
            m_username,
            systemUserByName(
                m_username
            )
        );

    if (!systemUser.valid) {
        finishOperation(
            QStringLiteral("applyProfile"),
            false,
            QStringLiteral(
                "The active local account no longer exists"
            ),
            safePayload
        );

        return false;
    }

    ProfileRecord profile =
        m_profiles.value(
            m_username,
            loadProfileRecord(
                m_username
            )
        );

    profile.displayName =
        requestedDisplayName;

    profile.profileTagline =
        requestedProfileTagline;

    profile.nameTint =
        requestedNameTint;

    profile.accentColor =
        requestedAccentColor;

    profile.avatarFrame =
        requestedAvatarFrame;

    profile.glowStrength =
        requestedGlowStrength;

    profile.role =
        roleForSystemUser(
            systemUser
        );

    profile.avatarId =
        requestedAvatar.id;

    profile.avatarSource =
        requestedAvatar.source;

    if (profile.lastLogin.isEmpty())
        profile.lastLogin = m_lastLogin;

    profile.updatedAt =
        QDateTime::currentDateTimeUtc();

    profile.valid = true;

    if (!saveProfileRecord(
            m_username,
            profile)) {
        finishOperation(
            QStringLiteral("applyProfile"),
            false,
            QStringLiteral(
                "Account settings could not be saved"
            ),
            safePayload
        );

        return false;
    }

    m_profiles.insert(
        m_username,
        profile
    );

    const QVariantMap updatedUser =
        buildUserMap(
            systemUser,
            profile
        );

    applyActiveUserMap(
        updatedUser,
        true
    );

    rebuildAvailableUsers();
    rebuildWatchers();

    incrementProfileRevision();

    finishOperation(
        QStringLiteral("applyProfile"),
        true,
        QStringLiteral(
            "Account settings applied"
        ),
        safePayload
    );

    emit profileApplied(
        m_activeUser
    );

    return true;
}

bool UserManager::setDisplayName(
    const QString &displayNameValue)
{
    QVariantMap payload;

    payload[
        QStringLiteral("username")
    ] = m_username;

    payload[
        QStringLiteral("displayName")
    ] = displayNameValue;

    payload[
        QStringLiteral("avatarId")
    ] = m_avatarId;

    payload[
        QStringLiteral("avatarSource")
    ] = m_avatarSource;

    payload[QStringLiteral("profileTagline")] = m_profileTagline;
    payload[QStringLiteral("nameTint")] = m_nameTint;
    payload[QStringLiteral("accentColor")] = m_accentColor;
    payload[QStringLiteral("avatarFrame")] = m_avatarFrame;
    payload[QStringLiteral("glowStrength")] = m_glowStrength;

    return applyProfile(payload);
}

bool UserManager::setAvatar(
    const QString &avatarIdOrSource)
{
    QVariantMap payload;

    payload[
        QStringLiteral("username")
    ] = m_username;

    payload[
        QStringLiteral("displayName")
    ] = m_displayName;

    payload[
        QStringLiteral("avatarId")
    ] = avatarIdOrSource;

    payload[
        QStringLiteral("avatarSource")
    ] = avatarIdOrSource;

    payload[QStringLiteral("profileTagline")] = m_profileTagline;
    payload[QStringLiteral("nameTint")] = m_nameTint;
    payload[QStringLiteral("accentColor")] = m_accentColor;
    payload[QStringLiteral("avatarFrame")] = m_avatarFrame;
    payload[QStringLiteral("glowStrength")] = m_glowStrength;

    return applyProfile(payload);
}

/*
    ========================================================================
                          READ-ONLY HELPERS
    ========================================================================
*/

QVariantMap UserManager::userProfile(
    const QString &usernameValue) const
{
    const QString normalized =
        normalizedUsername(
            usernameValue
        );

    if (normalized.isEmpty())
        return QVariantMap();

    SystemUserRecord systemUser =
        m_systemUsers.value(
            normalized
        );

    if (!systemUser.valid)
        systemUser =
            systemUserByName(
                normalized
            );

    if (!systemUser.valid)
        return QVariantMap();

    const ProfileRecord profile =
        m_profiles.value(
            normalized,
            loadProfileRecord(
                normalized
            )
        );

    return buildUserMap(
        systemUser,
        profile
    );
}

QString UserManager::resolveAvatarSource(
    const QString &source) const
{
    const AvatarRecord avatar =
        avatarRecordForValue(source);

    if (avatar.absolutePath.isEmpty())
        return QString();

    return QUrl::fromLocalFile(
        avatar.absolutePath
    ).toString();
}

bool UserManager::isValidDisplayName(
    const QString &displayNameValue) const
{
    const QString normalized =
        normalizedDisplayName(
            displayNameValue
        );

    return !normalized.isEmpty() &&
           normalized.size() <=
           MaximumDisplayNameLength;
}

bool UserManager::isValidProfileColor(
    const QString &colorValue) const
{
    return !normalizedProfileColor(
                colorValue,
                QString()
            ).isEmpty();
}

bool UserManager::isAllowedAvatar(
    const QString &avatarIdOrSource) const
{
    const AvatarRecord avatar =
        avatarRecordForValue(
            avatarIdOrSource
        );

    return !avatar.id.isEmpty() &&
           !avatar.absolutePath.isEmpty() &&
           QFileInfo::exists(
               avatar.absolutePath
           ) &&
           pathInsideAllowedAvatarRoots(
               avatar.absolutePath
           );
}

/*
    ========================================================================
                             CANCELLATION
    ========================================================================
*/

void UserManager::cancelPendingOperation()
{
    ++m_operationSerial;

    const QString action =
        m_pendingAction;

    const QVariantMap payload =
        m_pendingPayload;

    clearPendingOperation();
    setOperationBusy(false);

    setLastOperation(
        QStringLiteral(
            "User operation cancelled locally"
        )
    );

    if (!action.isEmpty()) {
        emit operationFinished(
            action,
            false,
            QStringLiteral(
                "Operation cancelled locally"
            ),
            payload
        );
    }
}

/*
    ========================================================================
                         FILESYSTEM WATCHERS
    ========================================================================
*/

void UserManager::initializeWatchers()
{
    rebuildWatchers();
}

void UserManager::rebuildWatchers()
{
    const QStringList oldFiles =
        m_fileWatcher.files();

    if (!oldFiles.isEmpty())
        m_fileWatcher.removePaths(oldFiles);

    const QStringList oldDirectories =
        m_fileWatcher.directories();

    if (!oldDirectories.isEmpty()) {
        m_fileWatcher.removePaths(
            oldDirectories
        );
    }

    m_watchedPaths.clear();

    auto addPath = [this](const QString &path) {
        const QString cleaned =
            QDir::cleanPath(path);

        if (cleaned.isEmpty() ||
                m_watchedPaths.contains(
                    cleaned) ||
                !QFileInfo::exists(
                    cleaned)) {
            return;
        }

        if (m_fileWatcher.addPath(cleaned))
            m_watchedPaths.insert(cleaned);
    };

    addPath(
        QStringLiteral("/etc/passwd")
    );

    addPath(
        QStringLiteral("/etc/group")
    );

    addPath(
        activeThemeFilePath()
    );

    const QString settingsDirectory =
        QFileInfo(
            activeThemeFilePath()
        ).absolutePath();

    addPath(settingsDirectory);
    addPath(usersStateRoot());
    addPath(themeRoot());
    addPath(usersThemeDirectory());

    if (m_activeTheme !=
            QStringLiteral("Default")) {
        addPath(
            neutronOsRoot() +
            QStringLiteral(
                "/themes/Default/users"
            )
        );
    }

    for (auto iterator =
             m_profiles.constBegin();
         iterator != m_profiles.constEnd();
         ++iterator) {
        addPath(
            profileDirectory(
                iterator.key()
            )
        );

        addPath(
            profileFilePath(
                iterator.key()
            )
        );
    }
}

void UserManager::onWatchedPathChanged(
    const QString &path)
{
    Q_UNUSED(path)
    scheduleRefresh();
}

void UserManager::scheduleRefresh(
    int delayMs)
{
    const int boundedDelay =
        qBound(
            0,
            delayMs,
            5000
        );

    if (m_refreshCoalesceTimer.isActive() &&
            m_refreshCoalesceTimer
                .remainingTime() <=
            boundedDelay) {
        return;
    }

    m_refreshCoalesceTimer.start(
        boundedDelay
    );
}

void UserManager::coalescedRefresh()
{
    const QString detectedTheme =
        readActiveTheme();

    if (detectedTheme !=
            m_activeTheme) {
        m_activeTheme =
            detectedTheme;

        emit activeThemeChanged();
    }

    discoverSystemUsers();
    discoverProfiles();
    discoverAvatars();

    rebuildAvailableAvatars();
    rebuildActiveUser();
    rebuildAvailableUsers();
    rebuildWatchers();
}

/*
    ========================================================================
                         ACCOUNT DISCOVERY
    ========================================================================
*/

void UserManager::discoverSystemUsers()
{
    QHash<QString, SystemUserRecord> discovered;
    QFile passwdFile(QStringLiteral("/etc/passwd"));
    if (!passwdFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_systemUsers.clear();
        return;
    }

    while (!passwdFile.atEnd()) {
        const QList<QByteArray> fields = passwdFile.readLine().trimmed().split(':');
        if (fields.size() < 7)
            continue;
        bool uidOk = false;
        bool gidOk = false;
        const quint64 uid = fields.at(2).toULongLong(&uidOk);
        const quint64 gid = fields.at(3).toULongLong(&gidOk);
        if (!uidOk || !gidOk)
            continue;

        SystemUserRecord record;

        record.username =
            normalizedUsername(
                QString::fromUtf8(fields.at(0))
            );

        if (record.username.isEmpty())
            continue;

        record.displayName =
            gecosDisplayName(
                QString::fromUtf8(fields.at(4)),
                record.username
            );

        record.homeDirectory =
            QString::fromUtf8(fields.at(5)).trimmed();

        record.shell =
            QString::fromUtf8(fields.at(6)).trimmed();

        record.uid = uid;
        record.gid = gid;

        record.valid = true;
        record.role =
            roleForSystemUser(record);

        if (shouldExposeSystemUser(record)) {
            discovered.insert(
                record.username,
                record
            );
        }
    }

    /*
        Ensure the active and effective session account remain addressable
        even if local UID filtering would normally hide them.
    */
    const SystemUserRecord current =
        currentSystemUser();

    if (current.valid) {
        discovered.insert(
            current.username,
            current
        );
    }

    if (!m_username.isEmpty()) {
        const SystemUserRecord active =
            systemUserByName(
                m_username
            );

        if (active.valid) {
            discovered.insert(
                active.username,
                active
            );
        }
    }

    m_systemUsers = discovered;
}

void UserManager::discoverProfiles()
{
    QHash<QString, ProfileRecord> profiles;

    for (auto iterator =
             m_systemUsers.constBegin();
         iterator !=
         m_systemUsers.constEnd();
         ++iterator) {
        profiles.insert(
            iterator.key(),
            loadProfileRecord(
                iterator.key()
            )
        );
    }

    m_profiles = profiles;
}

void UserManager::discoverAvatars()
{
    m_avatarsById.clear();
    m_avatarIdBySource.clear();

    QStringList themeNames;
    themeNames.append(m_activeTheme);

    if (m_activeTheme !=
            QStringLiteral("Default")) {
        themeNames.append(
            QStringLiteral("Default")
        );
    }

    QSet<QString> discoveredSources;

    for (const QString &themeName :
            std::as_const(themeNames)) {
        const QString themeUsersDirectory =
            neutronOsRoot() +
            QStringLiteral("/themes/") +
            themeName +
            QStringLiteral("/users");

        QDir directory(
            themeUsersDirectory
        );

        if (!directory.exists())
            continue;

        QDirIterator iterator(
            themeUsersDirectory,
            QDir::Files |
            QDir::Readable |
            QDir::NoSymLinks |
            QDir::NoDotAndDotDot,
            QDirIterator::Subdirectories
        );

        while (iterator.hasNext()) {
            const QString absolutePath =
                iterator.next();

            const QFileInfo info(
                absolutePath
            );

            if (!isImageFile(
                    info.fileName()) ||
                    !pathInsideAllowedAvatarRoots(
                        absolutePath)) {
                continue;
            }

            const QString relativeToUsers =
                QDir(
                    themeUsersDirectory
                ).relativeFilePath(
                    absolutePath
                );

            const QString source =
                QDir::cleanPath(
                    QStringLiteral("users/") +
                    relativeToUsers
                );

            if (source.contains(
                    QStringLiteral("../")) ||
                    discoveredSources.contains(
                        source)) {
                continue;
            }

            AvatarRecord avatar;

            avatar.source = source;
            avatar.absolutePath =
                info.canonicalFilePath();

            if (avatar.absolutePath.isEmpty()) {
                avatar.absolutePath =
                    info.absoluteFilePath();
            }

            avatar.theme = themeName;
            avatar.builtIn =
                source ==
                QStringLiteral(
                    "users/user_icon.png"
                );

            avatar.id =
                avatarStableId(
                    source,
                    avatar.absolutePath
                );

            avatar.name =
                avatar.builtIn
                ? QStringLiteral("Default")
                : humanFileName(
                      info.fileName()
                  );

            if (avatar.id.isEmpty())
                continue;

            discoveredSources.insert(
                source
            );

            m_avatarsById.insert(
                avatar.id,
                avatar
            );

            m_avatarIdBySource.insert(
                source,
                avatar.id
            );

            m_avatarIdBySource.insert(
                avatar.absolutePath,
                avatar.id
            );

            m_avatarIdBySource.insert(
                QUrl::fromLocalFile(
                    avatar.absolutePath
                ).toString(),
                avatar.id
            );
        }
    }
}

void UserManager::rebuildAvailableUsers()
{
    QVariantList rebuilt;

    QList<SystemUserRecord> records =
        m_systemUsers.values();

    std::sort(
        records.begin(),
        records.end(),
        [this](const SystemUserRecord &left,
               const SystemUserRecord &right) {
            const bool leftActive =
                left.username ==
                m_username;

            const bool rightActive =
                right.username ==
                m_username;

            if (leftActive != rightActive)
                return leftActive;

            const int displayComparison =
                QString::localeAwareCompare(
                    left.displayName,
                    right.displayName
                );

            if (displayComparison != 0)
                return displayComparison < 0;

            return QString::localeAwareCompare(
                       left.username,
                       right.username
                   ) < 0;
        }
    );

    for (const SystemUserRecord &record :
            std::as_const(records)) {
        const ProfileRecord profile =
            m_profiles.value(
                record.username,
                loadProfileRecord(
                    record.username
                )
            );

        QVariantMap userMap =
            buildUserMap(
                record,
                profile
            );

        const bool active =
            record.username ==
            m_username;

        userMap[
            QStringLiteral("active")
        ] = active;

        userMap[
            QStringLiteral("current")
        ] = active;

        userMap[
            QStringLiteral("selected")
        ] = active;

        rebuilt.append(userMap);
    }

    if (rebuilt ==
            m_availableUsers) {
        return;
    }

    m_availableUsers = rebuilt;

    emit availableUsersChanged();
    emit userChanged();

    incrementUserRevision();
}

void UserManager::rebuildAvailableAvatars()
{
    QList<AvatarRecord> records =
        m_avatarsById.values();

    std::sort(
        records.begin(),
        records.end(),
        [](const AvatarRecord &left,
           const AvatarRecord &right) {
            if (left.builtIn !=
                    right.builtIn) {
                return left.builtIn;
            }

            if (left.theme !=
                    right.theme) {
                if (left.theme ==
                        QStringLiteral(
                            "Default"
                        )) {
                    return false;
                }

                if (right.theme ==
                        QStringLiteral(
                            "Default"
                        )) {
                    return true;
                }
            }

            const int nameComparison =
                QString::localeAwareCompare(
                    left.name,
                    right.name
                );

            if (nameComparison != 0)
                return nameComparison < 0;

            return left.source <
                   right.source;
        }
    );

    QVariantList rebuilt;

    for (const AvatarRecord &record :
            std::as_const(records)) {
        rebuilt.append(
            avatarToMap(record)
        );
    }

    if (rebuilt ==
            m_availableAvatars) {
        return;
    }

    m_availableAvatars = rebuilt;

    emit availableAvatarsChanged();
    emit userChanged();

    incrementProfileRevision();
}

void UserManager::rebuildActiveUser()
{
    if (m_username.isEmpty()) {
        const SystemUserRecord current =
            currentSystemUser();

        if (!current.valid)
            return;

        const ProfileRecord profile =
            m_profiles.value(
                current.username,
                loadProfileRecord(
                    current.username
                )
            );

        applyActiveUserMap(
            buildUserMap(
                current,
                profile
            ),
            true
        );

        return;
    }

    SystemUserRecord systemUser =
        m_systemUsers.value(
            m_username
        );

    if (!systemUser.valid)
        systemUser =
            systemUserByName(
                m_username
            );

    if (!systemUser.valid) {
        clearActiveUser();
        return;
    }

    ProfileRecord profile =
        m_profiles.value(
            m_username,
            loadProfileRecord(
                m_username
            )
        );

    applyActiveUserMap(
        buildUserMap(
            systemUser,
            profile
        ),
        true
    );
}

/*
    ========================================================================
                         SYSTEM ACCOUNT LOOKUP
    ========================================================================
*/

UserManager::SystemUserRecord
UserManager::currentSystemUser() const
{
    QStringList candidates;

    const QString configured =
        normalizedUsername(
            environmentValue(
                "NEUTRONOS_USER"
            )
        );

    if (!configured.isEmpty())
        candidates.append(configured);

    const QString sudoUser =
        normalizedUsername(
            environmentValue(
                "SUDO_USER"
            )
        );

    if (!sudoUser.isEmpty() &&
            sudoUser !=
            QStringLiteral("root")) {
        candidates.append(sudoUser);
    }

    const QString logName =
        normalizedUsername(
            environmentValue(
                "LOGNAME"
            )
        );

    if (!logName.isEmpty() &&
            logName !=
            QStringLiteral("root")) {
        candidates.append(logName);
    }

    const QString environmentUser =
        normalizedUsername(
            environmentValue(
                "USER"
            )
        );

    if (!environmentUser.isEmpty() &&
            environmentUser !=
            QStringLiteral("root")) {
        candidates.append(
            environmentUser
        );
    }

    const QString projectOwner =
        normalizedUsername(
            QFileInfo(
                neutronOsRoot()
            ).owner()
        );

    if (!projectOwner.isEmpty() &&
            projectOwner !=
            QStringLiteral("root")) {
        candidates.append(
            projectOwner
        );
    }

    QSet<QString> attempted;

    for (const QString &candidate :
            std::as_const(candidates)) {
        if (attempted.contains(candidate))
            continue;

        attempted.insert(candidate);

        const SystemUserRecord record =
            systemUserByName(
                candidate
            );

        if (record.valid && shouldExposeSystemUser(record))
            return record;
    }

    QFile passwdFile(QStringLiteral("/etc/passwd"));
    if (passwdFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const quint64 currentUid = static_cast<quint64>(getuid());
        while (!passwdFile.atEnd()) {
            const QList<QByteArray> fields = passwdFile.readLine().trimmed().split(':');
            bool uidOk = false;
            if (fields.size() >= 7 &&
                    fields.at(2).toULongLong(&uidOk) == currentUid && uidOk) {
                const QString username = QString::fromUtf8(fields.at(0));
                const SystemUserRecord record = systemUserByName(username);
                return shouldExposeSystemUser(record) ? record : SystemUserRecord();
            }
        }
    }
    return SystemUserRecord();
}

UserManager::SystemUserRecord
UserManager::systemUserByName(
    const QString &usernameValue) const
{
    const QString normalized =
        normalizedUsername(
            usernameValue
        );

    if (normalized.isEmpty())
        return SystemUserRecord();

    QFile passwdFile(QStringLiteral("/etc/passwd"));
    if (!passwdFile.open(QIODevice::ReadOnly | QIODevice::Text))
        return SystemUserRecord();

    QList<QByteArray> fields;
    const QByteArray encoded = normalized.toUtf8();
    while (!passwdFile.atEnd()) {
        const QList<QByteArray> candidate = passwdFile.readLine().trimmed().split(':');
        if (candidate.size() >= 7 && candidate.at(0) == encoded) {
            fields = candidate;
            break;
        }
    }
    bool uidOk = false;
    bool gidOk = false;
    if (fields.size() < 7)
        return SystemUserRecord();
    const quint64 uid = fields.at(2).toULongLong(&uidOk);
    const quint64 gid = fields.at(3).toULongLong(&gidOk);
    if (!uidOk || !gidOk)
        return SystemUserRecord();

    SystemUserRecord record;

    record.username =
        normalizedUsername(
            QString::fromUtf8(fields.at(0))
        );

    record.displayName =
        gecosDisplayName(
            QString::fromUtf8(fields.at(4)),
            record.username
        );

    record.homeDirectory =
        QString::fromUtf8(fields.at(5)).trimmed();

    record.shell =
        QString::fromUtf8(fields.at(6)).trimmed();

    record.uid = uid;
    record.gid = gid;

    record.valid =
        !record.username.isEmpty();

    record.role =
        roleForSystemUser(record);

    return record;
}

bool UserManager::shouldExposeSystemUser(
    const SystemUserRecord &record) const
{
    if (!record.valid ||
            record.username.isEmpty()) {
        return false;
    }

    return HumanAccountPolicy::isHuman(record.username,
                                       record.uid,
                                       record.homeDirectory,
                                       record.shell);
}

QString UserManager::roleForSystemUser(
    const SystemUserRecord &record) const
{
    if (!record.valid)
        return QStringLiteral("Admin");

    if (record.uid == 0)
        return QStringLiteral("Admin");

    const gid_t primaryGid =
        static_cast<gid_t>(
            record.gid
        );

    if (userInNamedGroup(
            record.username,
            primaryGid,
            QByteArrayLiteral("sudo")) ||
            userInNamedGroup(
                record.username,
                primaryGid,
                QByteArrayLiteral("wheel")) ||
            userInNamedGroup(
                record.username,
                primaryGid,
                QByteArrayLiteral("admin"))) {
        return QStringLiteral("Admin");
    }

    return QStringLiteral("User");
}

/*
    ========================================================================
                          PROFILE PERSISTENCE
    ========================================================================
*/

UserManager::ProfileRecord
UserManager::loadProfileRecord(
    const QString &usernameValue) const
{
    ProfileRecord profile;

    const QString normalized =
        normalizedUsername(
            usernameValue
        );

    const SystemUserRecord systemUser =
        systemUserByName(normalized);

    profile.displayName =
        systemUser.valid
        ? systemUser.displayName
        : normalized;

    profile.profileTagline.clear();
    profile.nameTint = QStringLiteral("#FFFFFF");
    profile.accentColor = QStringLiteral("#7DF9FF");
    profile.avatarFrame = QStringLiteral("circle");
    profile.glowStrength = DefaultGlowStrength;

    profile.role =
        roleForSystemUser(
            systemUser
        );

    profile.avatarId =
        QStringLiteral(
            "users/user_icon.png"
        );

    profile.avatarSource =
        QStringLiteral(
            "users/user_icon.png"
        );

    profile.lastLogin =
        QStringLiteral("--");

    profile.valid =
        !normalized.isEmpty();

    if (normalized.isEmpty())
        return profile;

    QFile file(
        profileFilePath(normalized)
    );

    if (!file.open(
            QIODevice::ReadOnly |
            QIODevice::Text)) {
        return profile;
    }

    QJsonParseError parseError;

    const QJsonDocument document =
        QJsonDocument::fromJson(
            file.readAll(),
            &parseError
        );

    file.close();

    if (parseError.error !=
            QJsonParseError::NoError ||
            !document.isObject()) {
        return profile;
    }

    const QJsonObject object =
        document.object();

    const QString storedDisplayName =
        normalizedDisplayName(
            object.value(
                QStringLiteral(
                    "displayName"
                )
            ).toString()
        );

    if (isValidDisplayName(
            storedDisplayName)) {
        profile.displayName =
            storedDisplayName;
    }

    profile.profileTagline =
        normalizedProfileTagline(
            object.value(
                QStringLiteral("profileTagline")
            ).toString()
        );

    profile.nameTint =
        normalizedProfileColor(
            object.value(
                QStringLiteral("nameTint")
            ).toString(),
            QStringLiteral("#FFFFFF")
        );

    profile.accentColor =
        normalizedProfileColor(
            object.value(
                QStringLiteral("accentColor")
            ).toString(),
            QStringLiteral("#7DF9FF")
        );

    profile.avatarFrame =
        normalizedAvatarFrame(
            object.value(
                QStringLiteral("avatarFrame")
            ).toString()
        );

    profile.glowStrength =
        normalizedGlowStrength(
            object.value(
                QStringLiteral("glowStrength")
            ).toVariant(),
            DefaultGlowStrength
        );

    const QString storedAvatarId =
        object.value(
            QStringLiteral("avatarId")
        ).toString()
         .trimmed();

    const QString storedAvatarSource =
        normalizedAvatarSource(
            object.value(
                QStringLiteral(
                    "avatarSource"
                )
            ).toString()
        );

    if (!storedAvatarId.isEmpty())
        profile.avatarId =
            storedAvatarId;

    if (!storedAvatarSource.isEmpty())
        profile.avatarSource =
            storedAvatarSource;

    const QString storedLastLogin =
        object.value(
            QStringLiteral("lastLogin")
        ).toString()
         .trimmed();

    if (!storedLastLogin.isEmpty())
        profile.lastLogin =
            storedLastLogin;

    profile.updatedAt =
        QDateTime::fromString(
            object.value(
                QStringLiteral("updatedAt")
            ).toString(),
            Qt::ISODateWithMs
        );

    if (!profile.updatedAt.isValid()) {
        profile.updatedAt =
            QFileInfo(
                profileFilePath(
                    normalized
                )
            ).lastModified()
             .toUTC();
    }

    profile.valid = true;
    return profile;
}

bool UserManager::saveProfileRecord(
    const QString &usernameValue,
    const ProfileRecord &profile) const
{
    const QString normalized =
        normalizedUsername(
            usernameValue
        );

    if (normalized.isEmpty())
        return false;

    const QString directoryPath =
        profileDirectory(normalized);

    if (!QDir().mkpath(directoryPath))
        return false;

    QFile::setPermissions(
        directoryPath,
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner |
        QFileDevice::ExeOwner
    );

    QJsonObject object;

    object.insert(
        QStringLiteral("version"),
        2
    );

    object.insert(
        QStringLiteral("username"),
        normalized
    );

    object.insert(
        QStringLiteral("displayName"),
        profile.displayName
    );

    object.insert(
        QStringLiteral("profileTagline"),
        profile.profileTagline
    );

    object.insert(
        QStringLiteral("nameTint"),
        profile.nameTint
    );

    object.insert(
        QStringLiteral("accentColor"),
        profile.accentColor
    );

    object.insert(
        QStringLiteral("avatarFrame"),
        profile.avatarFrame
    );

    object.insert(
        QStringLiteral("glowStrength"),
        profile.glowStrength
    );

    /*
        Role is informational and always derived from the local account.
    */
    object.insert(
        QStringLiteral("role"),
        profile.role
    );

    object.insert(
        QStringLiteral("avatarId"),
        profile.avatarId
    );

    object.insert(
        QStringLiteral("avatarSource"),
        profile.avatarSource
    );

    object.insert(
        QStringLiteral("lastLogin"),
        profile.lastLogin
    );

    object.insert(
        QStringLiteral("updatedAt"),
        (
            profile.updatedAt.isValid()
            ? profile.updatedAt
            : QDateTime::currentDateTimeUtc()
        ).toString(
            Qt::ISODateWithMs
        )
    );

    const QString path =
        profileFilePath(normalized);

    QSaveFile file(path);

    if (!file.open(
            QIODevice::WriteOnly |
            QIODevice::Text)) {
        return false;
    }

    const QJsonDocument document(object);

    if (file.write(
            document.toJson(
                QJsonDocument::Indented
            )) < 0) {
        file.cancelWriting();
        return false;
    }

    if (!file.commit())
        return false;

    QFile::setPermissions(
        path,
        QFileDevice::ReadOwner |
        QFileDevice::WriteOwner
    );

    return true;
}

QString UserManager::profileDirectory(
    const QString &usernameValue) const
{
    const QString normalized =
        normalizedUsername(
            usernameValue
        );

    if (normalized.isEmpty())
        return QString();

    return usersStateRoot() +
           QLatin1Char('/') +
           normalized;
}

QString UserManager::profileFilePath(
    const QString &usernameValue) const
{
    const QString directory =
        profileDirectory(
            usernameValue
        );

    if (directory.isEmpty())
        return QString();

    return directory +
           QStringLiteral(
               "/profile.json"
           );
}

QString UserManager::usersStateRoot() const
{
    return neutronOsRoot() +
           QStringLiteral(
               "/state/users"
           );
}

/*
    ========================================================================
                         THEME / AVATAR PATHS
    ========================================================================
*/

QString UserManager::neutronOsRoot() const
{
    const QString configured =
        environmentValue(
            "NEUTRONOS_ROOT"
        );

    if (!configured.isEmpty()) {
        return QDir::cleanPath(
            configured
        );
    }

    return QDir::cleanPath(
        QStringLiteral("/opt/neutronos")
    );
}

QString UserManager::themeRoot() const
{
    return neutronOsRoot() +
           QStringLiteral("/themes/") +
           m_activeTheme;
}

QString UserManager::usersThemeDirectory() const
{
    return themeRoot() +
           QStringLiteral("/users");
}

QString UserManager::activeThemeFilePath() const
{
    return neutronOsRoot() +
           QStringLiteral(
               "/state/settings/theme.json"
           );
}

QString UserManager::readActiveTheme() const
{
    const QStringList candidates = {
        activeThemeFilePath(),
        neutronOsRoot() +
            QStringLiteral(
                "/config/theme.json"
            ),
        neutronOsRoot() +
            QStringLiteral(
                "/state/theme.json"
            ),
        neutronOsRoot() +
            QStringLiteral(
                "/config/theme.conf"
            )
    };

    for (const QString &path :
            candidates) {
        QFile file(path);

        if (!file.open(
                QIODevice::ReadOnly |
                QIODevice::Text)) {
            continue;
        }

        const QByteArray raw =
            file.readAll();

        file.close();

        QString theme;

        QJsonParseError parseError;

        const QJsonDocument document =
            QJsonDocument::fromJson(
                raw,
                &parseError
            );

        if (parseError.error ==
                QJsonParseError::NoError &&
                document.isObject()) {
            const QJsonObject object =
                document.object();

            const QStringList keys = {
                QStringLiteral("activeTheme"),
                QStringLiteral("theme"),
                QStringLiteral("name")
            };

            for (const QString &key :
                    keys) {
                theme =
                    object.value(key)
                        .toString()
                        .trimmed();

                if (!theme.isEmpty())
                    break;
            }
        } else {
            theme =
                QString::fromUtf8(raw)
                    .trimmed();

            if (theme.contains(
                    QLatin1Char('='))) {
                theme =
                    theme.section(
                        QLatin1Char('='),
                        1
                    ).trimmed();
            }

            theme.remove(
                QLatin1Char('"')
            );

            theme.remove(
                QLatin1Char('\'')
            );
        }

        if (!safeThemeName(theme))
            continue;

        const QString candidateRoot =
            neutronOsRoot() +
            QStringLiteral("/themes/") +
            theme;

        if (QFileInfo::exists(
                candidateRoot)) {
            return theme;
        }
    }

    return QStringLiteral("Default");
}

UserManager::AvatarRecord
UserManager::avatarRecordForValue(
    const QString &avatarIdOrSource) const
{
    const QString value =
        avatarIdOrSource.trimmed();

    if (value.isEmpty())
        return AvatarRecord();

    if (m_avatarsById.contains(value))
        return m_avatarsById.value(value);

    if (m_avatarIdBySource.contains(value)) {
        return m_avatarsById.value(
            m_avatarIdBySource.value(
                value
            )
        );
    }

    const QString normalizedSource =
        normalizedAvatarSource(value);

    if (!normalizedSource.isEmpty() &&
            m_avatarIdBySource.contains(
                normalizedSource)) {
        return m_avatarsById.value(
            m_avatarIdBySource.value(
                normalizedSource
            )
        );
    }

    QString localPath = value;

    const QUrl url(value);

    if (url.isLocalFile())
        localPath = url.toLocalFile();

    const QFileInfo info(localPath);

    if (info.isAbsolute()) {
        QString absolute =
            info.canonicalFilePath();

        if (absolute.isEmpty())
            absolute = info.absoluteFilePath();

        if (m_avatarIdBySource.contains(
                absolute)) {
            return m_avatarsById.value(
                m_avatarIdBySource.value(
                    absolute
                )
            );
        }
    }

    return AvatarRecord();
}

QVariantMap UserManager::avatarToMap(
    const AvatarRecord &avatar) const
{
    QVariantMap result;

    result[
        QStringLiteral("id")
    ] = avatar.id;

    result[
        QStringLiteral("avatarId")
    ] = avatar.id;

    result[
        QStringLiteral("iconId")
    ] = avatar.id;

    result[
        QStringLiteral("name")
    ] = avatar.name;

    result[
        QStringLiteral("displayName")
    ] = avatar.name;

    result[
        QStringLiteral("label")
    ] = avatar.name;

    result[
        QStringLiteral("source")
    ] = avatar.source;

    result[
        QStringLiteral("icon")
    ] = avatar.source;

    result[
        QStringLiteral("avatar")
    ] = avatar.source;

    result[
        QStringLiteral("path")
    ] = avatar.source;

    result[
        QStringLiteral("absolutePath")
    ] = avatar.absolutePath;

    result[
        QStringLiteral("resolvedSource")
    ] = QUrl::fromLocalFile(
        avatar.absolutePath
    ).toString();

    result[
        QStringLiteral("theme")
    ] = avatar.theme;

    result[
        QStringLiteral("builtIn")
    ] = avatar.builtIn;

    result[
        QStringLiteral("default")
    ] = avatar.builtIn;

    return result;
}

QString UserManager::avatarStableId(
    const QString &source,
    const QString &absolutePath) const
{
    const QString normalizedSource =
        normalizedAvatarSource(source);

    if (!normalizedSource.isEmpty())
        return normalizedSource;

    const QFileInfo info(absolutePath);

    if (!info.fileName().isEmpty()) {
        return QStringLiteral("users/") +
               info.fileName();
    }

    return QString();
}

bool UserManager::isImageFile(
    const QString &fileName) const
{
    const QString suffix =
        QFileInfo(fileName)
            .suffix()
            .toLower();

    return suffix ==
               QStringLiteral("png") ||
           suffix ==
               QStringLiteral("jpg") ||
           suffix ==
               QStringLiteral("jpeg") ||
           suffix ==
               QStringLiteral("webp") ||
           suffix ==
               QStringLiteral("svg");
}

bool UserManager::pathInsideAllowedAvatarRoots(
    const QString &absolutePath) const
{
    QFileInfo targetInfo(absolutePath);

    QString target =
        targetInfo.canonicalFilePath();

    if (target.isEmpty())
        target = targetInfo.absoluteFilePath();

    target =
        QDir::cleanPath(target);

    const QStringList roots = {
        usersThemeDirectory(),
        neutronOsRoot() +
            QStringLiteral(
                "/themes/Default/users"
            )
    };

    for (const QString &rootPath :
            roots) {
        QFileInfo rootInfo(rootPath);

        QString root =
            rootInfo.canonicalFilePath();

        if (root.isEmpty())
            root = rootInfo.absoluteFilePath();

        root =
            QDir::cleanPath(root);

        if (root.isEmpty())
            continue;

        if (target == root ||
                target.startsWith(
                    root +
                    QLatin1Char('/')
                )) {
            return true;
        }
    }

    return false;
}

QString UserManager::normalizedAvatarSource(
    const QString &source) const
{
    QString value =
        source.trimmed();

    if (value.isEmpty())
        return QString();

    const QUrl url(value);

    if (url.isLocalFile())
        value = url.toLocalFile();

    QFileInfo info(value);

    if (info.isAbsolute()) {
        QString absolute =
            info.canonicalFilePath();

        if (absolute.isEmpty())
            absolute = info.absoluteFilePath();

        if (!pathInsideAllowedAvatarRoots(
                absolute)) {
            return QString();
        }

        const QString activeRoot =
            QDir::cleanPath(
                usersThemeDirectory()
            );

        if (absolute.startsWith(
                activeRoot +
                QLatin1Char('/'))) {
            return QDir::cleanPath(
                QStringLiteral("users/") +
                QDir(activeRoot)
                    .relativeFilePath(
                        absolute
                    )
            );
        }

        const QString defaultRoot =
            QDir::cleanPath(
                neutronOsRoot() +
                QStringLiteral(
                    "/themes/Default/users"
                )
            );

        if (absolute.startsWith(
                defaultRoot +
                QLatin1Char('/'))) {
            return QDir::cleanPath(
                QStringLiteral("users/") +
                QDir(defaultRoot)
                    .relativeFilePath(
                        absolute
                    )
            );
        }

        return QString();
    }

    value.replace(
        QLatin1Char('\\'),
        QLatin1Char('/')
    );

    value =
        QDir::cleanPath(value);

    const QString activePrefix =
        QStringLiteral("themes/") +
        m_activeTheme +
        QStringLiteral("/");

    const QString defaultPrefix =
        QStringLiteral(
            "themes/Default/"
        );

    if (value.startsWith(activePrefix))
        value.remove(0, activePrefix.size());

    if (value.startsWith(defaultPrefix))
        value.remove(0, defaultPrefix.size());

    const int usersIndex =
        value.indexOf(
            QStringLiteral("users/")
        );

    if (usersIndex > 0)
        value = value.mid(usersIndex);

    if (!value.startsWith(
            QStringLiteral("users/"))) {
        value =
            QStringLiteral("users/") +
            value;
    }

    value =
        QDir::cleanPath(value);

    if (value == QStringLiteral("users") ||
            value.startsWith(
                QStringLiteral("../")) ||
            value.contains(
                QStringLiteral("/../"))) {
        return QString();
    }

    return value;
}

/*
    ========================================================================
                         USER MAP CONSTRUCTION
    ========================================================================
*/

QVariantMap UserManager::buildUserMap(
    const SystemUserRecord &systemUser,
    const ProfileRecord &profile) const
{
    QVariantMap result;

    const QString effectiveDisplayName =
        isValidDisplayName(
            profile.displayName
        )
        ? normalizedDisplayName(
              profile.displayName
          )
        : systemUser.displayName;

    AvatarRecord avatar =
        avatarRecordForValue(
            !profile.avatarId.isEmpty()
            ? profile.avatarId
            : profile.avatarSource
        );

    if (avatar.id.isEmpty()) {
        avatar =
            avatarRecordForValue(
                profile.avatarSource
            );
    }

    QString effectiveAvatarId =
        profile.avatarId;

    QString effectiveAvatarSource =
        normalizedAvatarSource(
            profile.avatarSource
        );

    if (!avatar.id.isEmpty()) {
        effectiveAvatarId =
            avatar.id;

        effectiveAvatarSource =
            avatar.source;
    }

    if (effectiveAvatarId.isEmpty()) {
        effectiveAvatarId =
            QStringLiteral(
                "users/user_icon.png"
            );
    }

    if (effectiveAvatarSource.isEmpty()) {
        effectiveAvatarSource =
            QStringLiteral(
                "users/user_icon.png"
            );
    }

    const QString effectiveRole =
        roleForSystemUser(
            systemUser
        );

    const QString effectiveLastLogin =
        profile.lastLogin.isEmpty()
        ? QStringLiteral("--")
        : profile.lastLogin;

    result[
        QStringLiteral("id")
    ] = systemUser.username;

    result[
        QStringLiteral("userId")
    ] = systemUser.username;

    result[
        QStringLiteral("username")
    ] = systemUser.username;

    result[
        QStringLiteral("accountName")
    ] = systemUser.username;

    result[
        QStringLiteral("loginName")
    ] = systemUser.username;

    result[
        QStringLiteral("uid")
    ] = static_cast<qulonglong>(
        systemUser.uid
    );

    result[
        QStringLiteral("gid")
    ] = static_cast<qulonglong>(
        systemUser.gid
    );

    result[
        QStringLiteral("displayName")
    ] = effectiveDisplayName;

    result[
        QStringLiteral("name")
    ] = effectiveDisplayName;

    result[
        QStringLiteral("fullName")
    ] = effectiveDisplayName;

    result[QStringLiteral("profileTagline")] =
        normalizedProfileTagline(profile.profileTagline);
    result[QStringLiteral("tagline")] =
        normalizedProfileTagline(profile.profileTagline);
    result[QStringLiteral("statusMessage")] =
        normalizedProfileTagline(profile.profileTagline);
    result[QStringLiteral("nameTint")] =
        normalizedProfileColor(profile.nameTint, QStringLiteral("#FFFFFF"));
    result[QStringLiteral("displayNameTint")] =
        normalizedProfileColor(profile.nameTint, QStringLiteral("#FFFFFF"));
    result[QStringLiteral("accentColor")] =
        normalizedProfileColor(profile.accentColor, QStringLiteral("#7DF9FF"));
    result[QStringLiteral("profileAccent")] =
        normalizedProfileColor(profile.accentColor, QStringLiteral("#7DF9FF"));
    result[QStringLiteral("avatarFrame")] =
        normalizedAvatarFrame(profile.avatarFrame);
    result[QStringLiteral("avatarShape")] =
        normalizedAvatarFrame(profile.avatarFrame);
    result[QStringLiteral("glowStrength")] =
        normalizedGlowStrength(profile.glowStrength, DefaultGlowStrength);

    result[
        QStringLiteral("role")
    ] = effectiveRole;

    result[
        QStringLiteral("accountRole")
    ] = effectiveRole;

    result[
        QStringLiteral("permissionRole")
    ] = effectiveRole;

    result[
        QStringLiteral("avatarId")
    ] = effectiveAvatarId;

    result[
        QStringLiteral("iconId")
    ] = effectiveAvatarId;

    result[
        QStringLiteral("profileIconId")
    ] = effectiveAvatarId;

    result[
        QStringLiteral("icon")
    ] = effectiveAvatarSource;

    result[
        QStringLiteral("avatar")
    ] = effectiveAvatarSource;

    result[
        QStringLiteral("avatarSource")
    ] = effectiveAvatarSource;

    result[
        QStringLiteral("profileIcon")
    ] = effectiveAvatarSource;

    result[
        QStringLiteral("resolvedAvatarSource")
    ] = resolveAvatarSource(
        effectiveAvatarId
    );

    result[
        QStringLiteral("homeDirectory")
    ] = systemUser.homeDirectory;

    result[
        QStringLiteral("home")
    ] = systemUser.homeDirectory;

    result[
        QStringLiteral("homePath")
    ] = systemUser.homeDirectory;

    result[
        QStringLiteral("shell")
    ] = systemUser.shell;

    result[
        QStringLiteral("lastLogin")
    ] = effectiveLastLogin;

    result[
        QStringLiteral("lastSignIn")
    ] = effectiveLastLogin;

    result[
        QStringLiteral("lastSession")
    ] = effectiveLastLogin;

    const QString profilePath =
        profileDirectory(
            systemUser.username
        );

    bool writable = false;

    if (!profilePath.isEmpty()) {
        QDir().mkpath(profilePath);

        QFile::setPermissions(
            profilePath,
            QFileDevice::ReadOwner |
            QFileDevice::WriteOwner |
            QFileDevice::ExeOwner
        );

        writable =
            QFileInfo(profilePath)
                .isWritable();
    }

    result[
        QStringLiteral("profileWritable")
    ] = writable;

    result[
        QStringLiteral("local")
    ] = true;

    result[
        QStringLiteral("valid")
    ] = systemUser.valid;

    return result;
}

QVariantMap UserManager::mergeUserContext(
    const QVariantMap &base,
    const QVariantMap &context) const
{
    QVariantMap result = base;

    const QString requestedDisplayName =
        normalizedDisplayName(
            variantString(
                context,
                QStringList()
                    << QStringLiteral(
                        "displayName"
                    )
                    << QStringLiteral("name")
                    << QStringLiteral(
                        "fullName"
                    )
            )
        );

    if (isValidDisplayName(
            requestedDisplayName)) {
        result[
            QStringLiteral("displayName")
        ] = requestedDisplayName;

        result[
            QStringLiteral("name")
        ] = requestedDisplayName;

        result[
            QStringLiteral("fullName")
        ] = requestedDisplayName;
    }

    const QString avatarValue =
        variantString(
            context,
            QStringList()
                << QStringLiteral("avatarId")
                << QStringLiteral("iconId")
                << QStringLiteral("icon")
                << QStringLiteral("avatar")
                << QStringLiteral(
                    "avatarSource"
                )
                << QStringLiteral(
                    "profileIcon"
                )
        );

    const AvatarRecord avatar =
        avatarRecordForValue(
            avatarValue
        );

    if (!avatar.id.isEmpty()) {
        result[
            QStringLiteral("avatarId")
        ] = avatar.id;

        result[
            QStringLiteral("iconId")
        ] = avatar.id;

        result[
            QStringLiteral(
                "profileIconId"
            )
        ] = avatar.id;

        result[
            QStringLiteral("icon")
        ] = avatar.source;

        result[
            QStringLiteral("avatar")
        ] = avatar.source;

        result[
            QStringLiteral(
                "avatarSource"
            )
        ] = avatar.source;

        result[
            QStringLiteral(
                "profileIcon"
            )
        ] = avatar.source;

        result[
            QStringLiteral(
                "resolvedAvatarSource"
            )
        ] = QUrl::fromLocalFile(
            avatar.absolutePath
        ).toString();
    }

    const QString contextTagline =
        normalizedProfileTagline(
            variantString(
                context,
                QStringList()
                    << QStringLiteral("profileTagline")
                    << QStringLiteral("tagline")
                    << QStringLiteral("statusMessage")
            )
        );

    if (!contextTagline.isEmpty()) {
        result[QStringLiteral("profileTagline")] = contextTagline;
        result[QStringLiteral("tagline")] = contextTagline;
        result[QStringLiteral("statusMessage")] = contextTagline;
    }

    const QString contextNameTint =
        normalizedProfileColor(
            variantString(
                context,
                QStringList()
                    << QStringLiteral("nameTint")
                    << QStringLiteral("displayNameTint")
            ),
            QString()
        );

    if (!contextNameTint.isEmpty()) {
        result[QStringLiteral("nameTint")] = contextNameTint;
        result[QStringLiteral("displayNameTint")] = contextNameTint;
    }

    const QString contextAccentColor =
        normalizedProfileColor(
            variantString(
                context,
                QStringList()
                    << QStringLiteral("accentColor")
                    << QStringLiteral("profileAccent")
            ),
            QString()
        );

    if (!contextAccentColor.isEmpty()) {
        result[QStringLiteral("accentColor")] = contextAccentColor;
        result[QStringLiteral("profileAccent")] = contextAccentColor;
    }

    const QString contextAvatarFrameValue =
        variantString(
            context,
            QStringList()
                << QStringLiteral("avatarFrame")
                << QStringLiteral("avatarShape")
        );

    if (!contextAvatarFrameValue.isEmpty()) {
        const QString contextAvatarFrame =
            normalizedAvatarFrame(
                contextAvatarFrameValue
            );

        result[QStringLiteral("avatarFrame")] = contextAvatarFrame;
        result[QStringLiteral("avatarShape")] = contextAvatarFrame;
    }

    if (context.contains(QStringLiteral("glowStrength"))) {
        result[QStringLiteral("glowStrength")] =
            normalizedGlowStrength(
                context.value(QStringLiteral("glowStrength")),
                DefaultGlowStrength
            );
    }

    const QString contextLastLogin =
        variantString(
            context,
            QStringList()
                << QStringLiteral(
                    "lastLogin"
                )
                << QStringLiteral(
                    "lastSignIn"
                )
                << QStringLiteral(
                    "lastSession"
                )
        );

    if (!contextLastLogin.isEmpty()) {
        result[
            QStringLiteral("lastLogin")
        ] = contextLastLogin;

        result[
            QStringLiteral("lastSignIn")
        ] = contextLastLogin;

        result[
            QStringLiteral("lastSession")
        ] = contextLastLogin;
    }

    /*
        Linux identity fields and role intentionally remain sourced from base.
    */
    return result;
}

bool UserManager::applyActiveUserMap(
    const QVariantMap &userMap,
    bool emitSignals)
{
    if (userMap.isEmpty())
        return false;

    const QVariantMap oldUser =
        m_activeUser;

    const bool oldWritable =
        m_profileWritable;

    m_activeUser = userMap;

    m_userId =
        variantString(
            userMap,
            QStringList()
                << QStringLiteral("userId")
                << QStringLiteral("id")
                << QStringLiteral("username")
        );

    m_username =
        normalizedUsername(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral("username")
                    << QStringLiteral(
                        "accountName"
                    )
                    << QStringLiteral("id")
            )
        );

    m_displayName =
        normalizedDisplayName(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral(
                        "displayName"
                    )
                    << QStringLiteral("name"),
                m_username
            )
        );

    if (m_displayName.isEmpty())
        m_displayName = m_username;

    m_profileTagline =
        normalizedProfileTagline(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral("profileTagline")
                    << QStringLiteral("tagline")
                    << QStringLiteral("statusMessage")
            )
        );

    m_nameTint =
        normalizedProfileColor(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral("nameTint")
                    << QStringLiteral("displayNameTint")
            ),
            QStringLiteral("#FFFFFF")
        );

    m_accentColor =
        normalizedProfileColor(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral("accentColor")
                    << QStringLiteral("profileAccent")
            ),
            QStringLiteral("#7DF9FF")
        );

    m_avatarFrame =
        normalizedAvatarFrame(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral("avatarFrame")
                    << QStringLiteral("avatarShape"),
                QStringLiteral("circle")
            )
        );

    m_glowStrength =
        normalizedGlowStrength(
            userMap.value(
                QStringLiteral("glowStrength"),
                DefaultGlowStrength
            ),
            DefaultGlowStrength
        );

    m_role =
        normalizedRole(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral("role")
                    << QStringLiteral(
                        "accountRole"
                    ),
                QStringLiteral("Admin")
            )
        );

    m_avatarId =
        variantString(
            userMap,
            QStringList()
                << QStringLiteral("avatarId")
                << QStringLiteral("iconId"),
            QStringLiteral(
                "users/user_icon.png"
            )
        );

    m_avatarSource =
        normalizedAvatarSource(
            variantString(
                userMap,
                QStringList()
                    << QStringLiteral("icon")
                    << QStringLiteral("avatar")
                    << QStringLiteral(
                        "avatarSource"
                    )
                    << QStringLiteral(
                        "profileIcon"
                    ),
                QStringLiteral(
                    "users/user_icon.png"
                )
            )
        );

    if (m_avatarSource.isEmpty()) {
        m_avatarSource =
            QStringLiteral(
                "users/user_icon.png"
            );
    }

    HumanHome::setSessionUser(m_username);

    m_homeDirectory =
        variantString(
            userMap,
            QStringList()
                << QStringLiteral(
                    "homeDirectory"
                )
                << QStringLiteral("home")
                << QStringLiteral(
                    "homePath"
                )
        );

    m_lastLogin =
        variantString(
            userMap,
            QStringList()
                << QStringLiteral(
                    "lastLogin"
                )
                << QStringLiteral(
                    "lastSignIn"
                ),
            QStringLiteral("--")
        );

    m_profileWritable =
        userMap.value(
            QStringLiteral(
                "profileWritable"
            ),
            false
        ).toBool();

    if (oldUser ==
            m_activeUser &&
            oldWritable ==
            m_profileWritable) {
        return false;
    }

    if (!emitSignals)
        return true;

    if (oldWritable !=
            m_profileWritable) {
        emit profileWritableChanged();
    }

    emit activeUserChanged();
    emit userChanged();

    incrementUserRevision();

    return true;
}

/*
    ========================================================================
                              VALIDATION
    ========================================================================
*/

bool UserManager::validateProfilePayload(
    const QVariantMap &payload,
    QString *displayNameValue,
    QString *profileTaglineValue,
    QString *nameTintValue,
    QString *accentColorValue,
    QString *avatarFrameValue,
    double *glowStrengthValue,
    AvatarRecord *avatarValue,
    QString *errorMessage) const
{
    const QString requestedDisplayName =
        normalizedDisplayName(
            nestedVariant(
                payload,
                QStringList()
                    << QStringLiteral(
                        "displayName"
                    )
                    << QStringLiteral("name")
            ).toString()
        );

    if (!isValidDisplayName(
            requestedDisplayName)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "Display name must contain 1 to %1 visible characters"
                ).arg(
                    MaximumDisplayNameLength
                );
        }

        return false;
    }

    const QString requestedProfileTagline =
        normalizedProfileTagline(
            nestedVariant(
                payload,
                QStringList()
                    << QStringLiteral("profileTagline")
                    << QStringLiteral("tagline")
                    << QStringLiteral("statusMessage")
            ).toString()
        );

    const QString requestedNameTint =
        normalizedProfileColor(
            nestedVariant(
                payload,
                QStringList()
                    << QStringLiteral("nameTint")
                    << QStringLiteral("displayNameTint")
            ).toString(),
            m_nameTint.isEmpty()
            ? QStringLiteral("#FFFFFF")
            : m_nameTint
        );

    if (requestedNameTint.isEmpty()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("The selected name tint is invalid");
        return false;
    }

    const QString requestedAccentColor =
        normalizedProfileColor(
            nestedVariant(
                payload,
                QStringList()
                    << QStringLiteral("accentColor")
                    << QStringLiteral("profileAccent")
            ).toString(),
            m_accentColor.isEmpty()
            ? QStringLiteral("#7DF9FF")
            : m_accentColor
        );

    if (requestedAccentColor.isEmpty()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("The selected profile accent is invalid");
        return false;
    }

    const QString requestedAvatarFrameValue =
        nestedVariant(
            payload,
            QStringList()
                << QStringLiteral("avatarFrame")
                << QStringLiteral("avatarShape")
        ).toString();

    const QString requestedAvatarFrame =
        normalizedAvatarFrame(
            requestedAvatarFrameValue.isEmpty()
            ? m_avatarFrame
            : requestedAvatarFrameValue
        );

    const double requestedGlowStrength =
        normalizedGlowStrength(
            nestedVariant(
                payload,
                QStringList()
                    << QStringLiteral("glowStrength")
            ),
            DefaultGlowStrength
        );

    QString requestedAvatar =
        nestedVariant(
            payload,
            QStringList()
                << QStringLiteral("avatarId")
                << QStringLiteral("iconId")
                << QStringLiteral("icon")
                << QStringLiteral("avatar")
                << QStringLiteral(
                    "avatarSource"
                )
                << QStringLiteral(
                    "profileIcon"
                )
        ).toString()
         .trimmed();

    if (requestedAvatar.isEmpty())
        requestedAvatar = m_avatarId;

    AvatarRecord avatar =
        avatarRecordForValue(
            requestedAvatar
        );

    if (avatar.id.isEmpty()) {
        avatar =
            avatarRecordForValue(
                m_avatarSource
            );
    }

    if (avatar.id.isEmpty() ||
            !QFileInfo::exists(
                avatar.absolutePath) ||
            !pathInsideAllowedAvatarRoots(
                avatar.absolutePath)) {
        if (errorMessage) {
            *errorMessage =
                QStringLiteral(
                    "The selected profile icon is unavailable"
                );
        }

        return false;
    }

    if (displayNameValue)
        *displayNameValue =
            requestedDisplayName;

    if (profileTaglineValue)
        *profileTaglineValue = requestedProfileTagline;

    if (nameTintValue)
        *nameTintValue = requestedNameTint;

    if (accentColorValue)
        *accentColorValue = requestedAccentColor;

    if (avatarFrameValue)
        *avatarFrameValue = requestedAvatarFrame;

    if (glowStrengthValue)
        *glowStrengthValue = requestedGlowStrength;

    if (avatarValue)
        *avatarValue = avatar;

    if (errorMessage)
        errorMessage->clear();

    return true;
}

QString UserManager::normalizedDisplayName(
    const QString &value) const
{
    QString result = value;

    result.replace(
        QRegularExpression(
            QStringLiteral(
                "[\\x00-\\x1F\\x7F]"
            )
        ),
        QStringLiteral(" ")
    );

    result =
        result.simplified();

    if (result.size() >
            MaximumDisplayNameLength) {
        return QString();
    }

    return result;
}

QString UserManager::normalizedProfileTagline(
    const QString &value) const
{
    QString result = value;

    result.replace(
        QRegularExpression(
            QStringLiteral("[\x00-\x1F\x7F]")
        ),
        QStringLiteral(" ")
    );

    result = result.simplified();

    if (result.size() > MaximumProfileTaglineLength)
        result = result.left(MaximumProfileTaglineLength).trimmed();

    return result;
}

QString UserManager::normalizedProfileColor(
    const QString &value,
    const QString &fallback) const
{
    QString result = value.trimmed().toUpper();

    if (!result.startsWith(QLatin1Char('#')))
        result.prepend(QLatin1Char('#'));

    static const QRegularExpression pattern(
        QStringLiteral("^#[0-9A-F]{6}$")
    );

    if (pattern.match(result).hasMatch())
        return result;

    return fallback;
}

QString UserManager::normalizedAvatarFrame(
    const QString &value) const
{
    const QString normalized =
        value.trimmed().toLower();

    if (normalized == QStringLiteral("rounded") ||
            normalized == QStringLiteral("rounded-square") ||
            normalized == QStringLiteral("rounded_square")) {
        return QStringLiteral("rounded");
    }

    if (normalized == QStringLiteral("square"))
        return QStringLiteral("square");

    return QStringLiteral("circle");
}

double UserManager::normalizedGlowStrength(
    const QVariant &value,
    double fallback) const
{
    bool ok = false;
    const double number = value.toDouble(&ok);

    if (!ok)
        return qBound(0.0, fallback, 1.0);

    return qBound(0.0, number, 1.0);
}

QString UserManager::normalizedUsername(
    const QString &value) const
{
    const QString result =
        value.trimmed();

    return safeUsername(result)
           ? result
           : QString();
}

QString UserManager::normalizedRole(
    const QString &value) const
{
    const QString result =
        value.trimmed();

    if (result.compare(
            QStringLiteral("Admin"),
            Qt::CaseInsensitive) == 0 ||
            result.compare(
                QStringLiteral(
                    "Administrator"
                ),
                Qt::CaseInsensitive) == 0) {
        return QStringLiteral("Admin");
    }

    if (result.compare(
            QStringLiteral("User"),
            Qt::CaseInsensitive) == 0 ||
            result.compare(
                QStringLiteral("Standard"),
                Qt::CaseInsensitive) == 0) {
        return QStringLiteral("User");
    }

    return QStringLiteral("Admin");
}

QString UserManager::normalizedAction(
    const QString &action) const
{
    QString result =
        action.trimmed()
            .toLower();

    result.remove(
        QRegularExpression(
            QStringLiteral(
                "[\\s_\\-]"
            )
        )
    );

    return result;
}

/*
    ========================================================================
                         SESSION ACTION PAYLOADS
    ========================================================================
*/

QVariantMap UserManager::sessionPayload(
    const QVariantMap &payload,
    const QString &action) const
{
    QVariantMap result =
        sanitizedPayload(payload);

    result[
        QStringLiteral("action")
    ] = action;

    result[
        QStringLiteral("user")
    ] = m_activeUser;

    result[
        QStringLiteral("userId")
    ] = m_userId;

    result[
        QStringLiteral("username")
    ] = m_username;

    result[
        QStringLiteral("displayName")
    ] = m_displayName;

    result[
        QStringLiteral("role")
    ] = m_role;

    result[
        QStringLiteral("requestedAt")
    ] = QDateTime::currentDateTimeUtc()
            .toString(
                Qt::ISODateWithMs
            );

    return result;
}

/*
    ========================================================================
                           REVISION HELPERS
    ========================================================================
*/

void UserManager::incrementUserRevision()
{
    ++m_userRevision;

    if (m_userRevision >
            1000000000) {
        m_userRevision = 1;
    }

    emit userRevisionChanged();
}

void UserManager::incrementProfileRevision()
{
    ++m_profileRevision;

    if (m_profileRevision >
            1000000000) {
        m_profileRevision = 1;
    }

    emit profileRevisionChanged();
}

/*
    ========================================================================
                         OPERATION LIFECYCLE
    ========================================================================
*/

void UserManager::beginOperation(
    const QString &action,
    const QVariantMap &payload)
{
    ++m_operationSerial;

    m_pendingAction = action;

    m_pendingPayload =
        sanitizedPayload(payload);

    setLastError(QString());

    setLastOperation(
        QStringLiteral(
            "%1 started"
        ).arg(action)
    );

    setOperationBusy(true);

    emit operationStarted(
        action,
        m_pendingPayload
    );
}

void UserManager::finishOperation(
    const QString &action,
    bool success,
    const QString &message,
    const QVariantMap &payload)
{
    const QVariantMap safePayload =
        payload.isEmpty()
        ? m_pendingPayload
        : sanitizedPayload(payload);

    if (success)
        setLastError(QString());
    else
        setLastError(message);

    setLastOperation(message);
    setOperationBusy(false);

    clearPendingOperation();

    emit operationFinished(
        action,
        success,
        message,
        safePayload
    );
}

void UserManager::setOperationBusy(
    bool busy)
{
    if (m_operationBusy == busy)
        return;

    m_operationBusy = busy;
    emit operationBusyChanged();
}

void UserManager::setLastError(
    const QString &message)
{
    if (m_lastError == message)
        return;

    m_lastError = message;
    emit lastErrorChanged();
}

void UserManager::setLastOperation(
    const QString &message)
{
    if (m_lastOperation == message)
        return;

    m_lastOperation = message;
    emit lastOperationChanged();
}

void UserManager::clearPendingOperation()
{
    m_pendingAction.clear();
    m_pendingPayload.clear();
}

QVariantMap UserManager::sanitizedPayload(
    const QVariantMap &payload) const
{
    QVariantMap result;

    for (auto iterator =
             payload.constBegin();
         iterator != payload.constEnd();
         ++iterator) {
        const QString normalizedKey =
            iterator.key()
                .trimmed()
                .toLower();

        const bool sensitive =
            normalizedKey.contains(
                QStringLiteral("password")) ||
            normalizedKey.contains(
                QStringLiteral("passphrase")) ||
            normalizedKey.contains(
                QStringLiteral("secret")) ||
            normalizedKey.contains(
                QStringLiteral("token")) ||
            normalizedKey.contains(
                QStringLiteral("hash")) ||
            normalizedKey ==
                QStringLiteral("combo") ||
            normalizedKey ==
                QStringLiteral(
                    "controllercombo"
                ) ||
            normalizedKey ==
                QStringLiteral(
                    "logincombo"
                ) ||
            normalizedKey ==
                QStringLiteral("sequence") ||
            normalizedKey ==
                QStringLiteral("code");

        if (sensitive)
            continue;

        const QVariant value =
            iterator.value();

        if (variantIsMap(value)) {
            result.insert(
                iterator.key(),
                sanitizedPayload(
                    value.toMap()
                )
            );

            continue;
        }

        if (variantIsList(value)) {
            QVariantList sanitizedList;

            for (const QVariant &entry :
                    value.toList()) {
                if (variantIsMap(entry)) {
                    sanitizedList.append(
                        sanitizedPayload(
                            entry.toMap()
                        )
                    );
                } else {
                    sanitizedList.append(
                        entry
                    );
                }
            }

            result.insert(
                iterator.key(),
                sanitizedList
            );

            continue;
        }

        result.insert(
            iterator.key(),
            value
        );
    }

    return result;
}
