#pragma once

#include <QObject>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QHash>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

/*
    ========================================================================
                              USER MANAGER
    ========================================================================

    UserManager owns the non-secret local profile data used by:

        - qml/LoginScreen.qml
        - qml/Console.qml
        - qml/modals/system/UserSettingsModal.qml

    Responsibilities:

        - Resolve the currently authenticated local Linux account.
        - Expose the active NeutronOS user as a structured QVariantMap.
        - Persist display name, tagline, colors, avatar, frame, and glow.
        - Discover real profile icons from the active theme.
        - Preserve immutable account identity fields such as username, UID,
          home directory, and role.
        - Emit lock, logout, and login-combo workflow requests to Main.qml.
        - Never store passwords, controller combinations, hashes, or tokens.
        - Never alter Linux groups, account passwords, or sudo policy.
        - Never execute shell commands.

    Profile persistence:

        ~/NeutronOS/state/users/<username>/profile.json

    Theme avatar discovery:

        ~/NeutronOS/themes/<theme>/users/

    The profile role is descriptive UI metadata. Production role/permission
    enforcement remains in the security and authorization backends.

    UserSettingsModal.qml action contract:

        applyProfile
        lock
        logout
        refreshSecurity
        cancel

    "requestKeyboard" is a Console/UI action and must not be forwarded here.
*/

class UserManager final : public QObject
{
    Q_OBJECT

    /*
        --------------------------------------------------------------------
                              ACTIVE USER
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QVariantMap activeUser
               READ activeUser
               NOTIFY activeUserChanged)

    Q_PROPERTY(QVariantMap currentUser
               READ activeUser
               NOTIFY activeUserChanged)

    Q_PROPERTY(QVariantMap user
               READ activeUser
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString userId
               READ userId
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString username
               READ username
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString accountName
               READ username
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString displayName
               READ displayName
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString name
               READ displayName
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString profileTagline
               READ profileTagline
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString tagline
               READ profileTagline
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString nameTint
               READ nameTint
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString accentColor
               READ accentColor
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString avatarFrame
               READ avatarFrame
               NOTIFY activeUserChanged)

    Q_PROPERTY(double glowStrength
               READ glowStrength
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString role
               READ role
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString accountRole
               READ role
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString avatarId
               READ avatarId
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString icon
               READ avatarSource
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString avatar
               READ avatarSource
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString avatarSource
               READ avatarSource
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString profileIcon
               READ avatarSource
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString homeDirectory
               READ homeDirectory
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString home
               READ homeDirectory
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString lastLogin
               READ lastLogin
               NOTIFY activeUserChanged)

    Q_PROPERTY(QString lastSignIn
               READ lastLogin
               NOTIFY activeUserChanged)

    Q_PROPERTY(bool profileWritable
               READ profileWritable
               NOTIFY profileWritableChanged)

    /*
        --------------------------------------------------------------------
                              USER MODELS
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QVariantList availableUsers
               READ availableUsers
               NOTIFY availableUsersChanged)

    Q_PROPERTY(QVariantList users
               READ availableUsers
               NOTIFY availableUsersChanged)

    Q_PROPERTY(QVariantList userProfiles
               READ availableUsers
               NOTIFY availableUsersChanged)

    Q_PROPERTY(QVariantList availableAvatars
               READ availableAvatars
               NOTIFY availableAvatarsChanged)

    Q_PROPERTY(QVariantList avatarOptions
               READ availableAvatars
               NOTIFY availableAvatarsChanged)

    Q_PROPERTY(QVariantList profileIcons
               READ availableAvatars
               NOTIFY availableAvatarsChanged)

    /*
        --------------------------------------------------------------------
                           STATE / REVISION
        --------------------------------------------------------------------
    */

    Q_PROPERTY(QString activeTheme
               READ activeTheme
               NOTIFY activeThemeChanged)

    Q_PROPERTY(bool operationBusy
               READ operationBusy
               NOTIFY operationBusyChanged)

    Q_PROPERTY(QString lastError
               READ lastError
               NOTIFY lastErrorChanged)

    Q_PROPERTY(QString lastOperation
               READ lastOperation
               NOTIFY lastOperationChanged)

    Q_PROPERTY(int userRevision
               READ userRevision
               NOTIFY userRevisionChanged)

    Q_PROPERTY(int profileRevision
               READ profileRevision
               NOTIFY profileRevisionChanged)

public:
    explicit UserManager(QObject *parent = nullptr);
    ~UserManager() override;

    /*
        Active account.
    */
    QVariantMap activeUser() const;
    QString userId() const;
    QString username() const;
    QString displayName() const;
    QString profileTagline() const;
    QString nameTint() const;
    QString accentColor() const;
    QString avatarFrame() const;
    double glowStrength() const;
    QString role() const;
    QString avatarId() const;
    QString avatarSource() const;
    QString homeDirectory() const;
    QString lastLogin() const;
    bool profileWritable() const;

    /*
        Models.
    */
    QVariantList availableUsers() const;
    QVariantList availableAvatars() const;

    /*
        State.
    */
    QString activeTheme() const;
    bool operationBusy() const;
    QString lastError() const;
    QString lastOperation() const;
    int userRevision() const;
    int profileRevision() const;

    /*
        Refresh APIs do not mutate identity or security state.
    */
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshProfile();
    Q_INVOKABLE void refreshAvatars();
    Q_INVOKABLE void refreshUsers();

    /*
        Sets the authenticated session identity after LoginScreen succeeds.

        The supplied context may include:
            id
            userId
            username
            displayName
            role
            icon
            avatarId
            homeDirectory
            lastLogin

        Immutable Linux identity fields are revalidated against the local
        account database before being exposed.
    */
    Q_INVOKABLE bool setActiveUser(const QVariantMap &userContext);
    Q_INVOKABLE bool setActiveUserByName(const QString &username);
    Q_INVOKABLE void clearActiveUser();

    /*
        Generic Console.qml action router.
    */
    Q_INVOKABLE bool executeAction(const QString &action,
                                   const QVariantMap &payload = QVariantMap());

    /*
        Profile mutation.
    */
    Q_INVOKABLE bool applyProfile(const QVariantMap &payload);
    Q_INVOKABLE bool setDisplayName(const QString &displayName);
    Q_INVOKABLE bool setAvatar(const QString &avatarIdOrSource);

    /*
        Read-only lookup helpers.
    */
    Q_INVOKABLE QVariantMap userProfile(const QString &username) const;
    Q_INVOKABLE QString resolveAvatarSource(const QString &source) const;
    Q_INVOKABLE bool isValidDisplayName(const QString &displayName) const;
    Q_INVOKABLE bool isValidProfileColor(const QString &colorValue) const;
    Q_INVOKABLE bool isAllowedAvatar(const QString &avatarIdOrSource) const;

    /*
        Cancels local operation bookkeeping only.
    */
    Q_INVOKABLE void cancelPendingOperation();

signals:
    /*
        Aggregate compatibility signal.
    */
    void userChanged();

    /*
        Model and profile state.
    */
    void activeUserChanged();
    void availableUsersChanged();
    void availableAvatarsChanged();
    void profileWritableChanged();
    void activeThemeChanged();

    void userRevisionChanged();
    void profileRevisionChanged();

    /*
        Operation state.
    */
    void operationBusyChanged();
    void lastErrorChanged();
    void lastOperationChanged();

    /*
        Profile operation lifecycle.
    */
    void operationStarted(const QString &action,
                          const QVariantMap &payload);

    void operationFinished(const QString &action,
                           bool success,
                           const QString &message,
                           const QVariantMap &payload);

    void profileApplied(const QVariantMap &user);

    /*
        Session/security workflow requests.

        Main.qml / Console.qml decides how these requests change shell state.
        UserManager intentionally does not own LoginScreen or security hashes.
    */
    void lockRequested(const QVariantMap &context);
    void logoutRequested(const QVariantMap &context);
    void loginComboChangeRequested(const QVariantMap &context);
    void securityRefreshRequested(const QVariantMap &context);

private slots:
    /*
        Filesystem changes are coalesced to avoid rebuilding models repeatedly.
    */
    void onWatchedPathChanged(const QString &path);
    void coalescedRefresh();

private:
    struct SystemUserRecord
    {
        QString username;
        QString displayName;
        QString homeDirectory;
        QString shell;
        QString role = QStringLiteral("Admin");
        quint64 uid = 0;
        quint64 gid = 0;
        bool valid = false;
    };

    struct ProfileRecord
    {
        QString displayName;
        QString profileTagline;
        QString nameTint = QStringLiteral("#FFFFFF");
        QString accentColor = QStringLiteral("#7DF9FF");
        QString avatarFrame = QStringLiteral("circle");
        double glowStrength = 0.65;
        QString role = QStringLiteral("Admin");
        QString avatarId;
        QString avatarSource = QStringLiteral("users/user_icon.png");
        QString lastLogin;
        QDateTime updatedAt;
        bool valid = false;
    };

    struct AvatarRecord
    {
        QString id;
        QString name;
        QString source;
        QString absolutePath;
        QString theme;
        bool builtIn = false;
    };

    /*
        Current models.
    */
    QVariantMap m_activeUser;
    QVariantList m_availableUsers;
    QVariantList m_availableAvatars;

    /*
        Flattened active-user fields.
    */
    QString m_userId;
    QString m_username;
    QString m_displayName;
    QString m_profileTagline;
    QString m_nameTint = QStringLiteral("#FFFFFF");
    QString m_accentColor = QStringLiteral("#7DF9FF");
    QString m_avatarFrame = QStringLiteral("circle");
    double m_glowStrength = 0.65;
    QString m_role = QStringLiteral("Admin");
    QString m_avatarId = QStringLiteral("users/user_icon.png");
    QString m_avatarSource = QStringLiteral("users/user_icon.png");
    QString m_homeDirectory;
    QString m_lastLogin = QStringLiteral("--");

    /*
        Theme and persistence state.
    */
    QString m_activeTheme = QStringLiteral("Default");
    bool m_profileWritable = false;

    /*
        Operation and revision state.
    */
    bool m_operationBusy = false;
    QString m_lastError;
    QString m_lastOperation;
    int m_userRevision = 0;
    int m_profileRevision = 0;
    QString m_pendingAction;
    QVariantMap m_pendingPayload;
    quint64 m_operationSerial = 0;

    /*
        Discovery caches.
    */
    QHash<QString, SystemUserRecord> m_systemUsers;
    QHash<QString, ProfileRecord> m_profiles;
    QHash<QString, AvatarRecord> m_avatarsById;
    QHash<QString, QString> m_avatarIdBySource;

    /*
        File-change monitoring. No continuous polling timer is used.
    */
    QFileSystemWatcher m_fileWatcher;
    QTimer m_refreshCoalesceTimer;
    QSet<QString> m_watchedPaths;

    /*
        Initialization and refresh.
    */
    void initializeWatchers();
    void rebuildWatchers();
    void scheduleRefresh(int delayMs = 100);

    void discoverSystemUsers();
    void discoverProfiles();
    void discoverAvatars();
    void rebuildAvailableUsers();
    void rebuildAvailableAvatars();
    void rebuildActiveUser();

    /*
        System account lookup.
    */
    SystemUserRecord currentSystemUser() const;
    SystemUserRecord systemUserByName(const QString &username) const;
    bool shouldExposeSystemUser(const SystemUserRecord &record) const;
    QString roleForSystemUser(const SystemUserRecord &record) const;

    /*
        Profile persistence.
    */
    ProfileRecord loadProfileRecord(const QString &username) const;
    bool saveProfileRecord(const QString &username,
                           const ProfileRecord &profile) const;

    QString profileDirectory(const QString &username) const;
    QString profileFilePath(const QString &username) const;
    QString usersStateRoot() const;

    /*
        Theme and avatar paths.
    */
    QString neutronOsRoot() const;
    QString themeRoot() const;
    QString usersThemeDirectory() const;
    QString activeThemeFilePath() const;
    QString readActiveTheme() const;

    AvatarRecord avatarRecordForValue(const QString &avatarIdOrSource) const;
    QVariantMap avatarToMap(const AvatarRecord &avatar) const;
    QString avatarStableId(const QString &source,
                           const QString &absolutePath) const;

    bool isImageFile(const QString &fileName) const;
    bool pathInsideAllowedAvatarRoots(const QString &absolutePath) const;
    QString normalizedAvatarSource(const QString &source) const;

    /*
        User map construction.
    */
    QVariantMap buildUserMap(const SystemUserRecord &systemUser,
                             const ProfileRecord &profile) const;

    QVariantMap mergeUserContext(const QVariantMap &base,
                                 const QVariantMap &context) const;

    bool applyActiveUserMap(const QVariantMap &userMap,
                            bool emitSignals = true);

    /*
        Validation.
    */
    bool validateProfilePayload(const QVariantMap &payload,
                                QString *displayNameValue,
                                QString *profileTaglineValue,
                                QString *nameTintValue,
                                QString *accentColorValue,
                                QString *avatarFrameValue,
                                double *glowStrengthValue,
                                AvatarRecord *avatarValue,
                                QString *errorMessage) const;

    QString normalizedDisplayName(const QString &value) const;
    QString normalizedProfileTagline(const QString &value) const;
    QString normalizedProfileColor(const QString &value,
                                   const QString &fallback) const;
    QString normalizedAvatarFrame(const QString &value) const;
    double normalizedGlowStrength(const QVariant &value,
                                  double fallback) const;
    QString normalizedUsername(const QString &value) const;
    QString normalizedRole(const QString &value) const;
    QString normalizedAction(const QString &action) const;

    /*
        Session-action payloads.
    */
    QVariantMap sessionPayload(const QVariantMap &payload,
                               const QString &action) const;

    /*
        Revision helpers.
    */
    void incrementUserRevision();
    void incrementProfileRevision();

    /*
        Operation lifecycle.
    */
    void beginOperation(const QString &action,
                        const QVariantMap &payload);

    void finishOperation(const QString &action,
                         bool success,
                         const QString &message,
                         const QVariantMap &payload = QVariantMap());

    void setOperationBusy(bool busy);
    void setLastError(const QString &message);
    void setLastOperation(const QString &message);
    void clearPendingOperation();

    QVariantMap sanitizedPayload(const QVariantMap &payload) const;
};
