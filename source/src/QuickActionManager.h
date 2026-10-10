#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QStringList>
#include <QSet>

/*
    NeutronOS Patch 20 quick-action registry.

    The backend owns the complete action catalogue and a persistent dynamic
    Console dock. QML only renders the lists and requests assignments or
    execution; it never runs shell commands directly.
*/
class QuickActionManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList actions READ actions NOTIFY actionsChanged)
    Q_PROPERTY(QVariantList dockActions READ dockActions NOTIFY dockActionsChanged)
    Q_PROPERTY(int actionCount READ actionCount NOTIFY actionsChanged)
    Q_PROPERTY(int dockSlotCount READ dockSlotCount NOTIFY dockActionsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastMessage READ lastMessage NOTIFY lastMessageChanged)
    Q_PROPERTY(QString neutronRoot READ neutronRootPath CONSTANT)
    Q_PROPERTY(QString appsRoot READ appsRootPath CONSTANT)
    Q_PROPERTY(QString configRoot READ configRootPath CONSTANT)

public:
    explicit QuickActionManager(QObject *parent = nullptr);

    QVariantList actions() const;
    QVariantList dockActions() const;
    int actionCount() const;
    int dockSlotCount() const;
    bool busy() const;
    QString lastMessage() const;

    QString neutronRootPath() const;
    QString appsRootPath() const;
    QString configRootPath() const;

    Q_INVOKABLE void reloadActions();
    Q_INVOKABLE void refreshActions();
    Q_INVOKABLE void rediscoverActions();

    Q_INVOKABLE QVariantMap actionById(const QString &actionId) const;
    Q_INVOKABLE QVariantMap actionAt(int index) const;
    Q_INVOKABLE QVariantMap dockActionAt(int slot) const;
    Q_INVOKABLE bool hasAction(const QString &actionId) const;

    Q_INVOKABLE bool setDockAction(int slot, const QString &actionId);
    Q_INVOKABLE bool appendDockAction(const QString &actionId);
    Q_INVOKABLE bool removeDockAction(int slot);
    Q_INVOKABLE bool moveDockAction(int fromSlot, int toSlot);
    Q_INVOKABLE bool resetDockActions();
    Q_INVOKABLE QStringList dockActionIds() const;

    Q_INVOKABLE bool executeAction(const QVariantMap &actionData);
    Q_INVOKABLE bool runAction(const QVariantMap &actionData);
    Q_INVOKABLE bool triggerAction(const QVariantMap &actionData);
    Q_INVOKABLE bool executeActionById(const QString &actionId);

    Q_INVOKABLE bool isLaunchAction(const QVariantMap &actionData) const;
    Q_INVOKABLE bool isDangerAction(const QVariantMap &actionData) const;
    Q_INVOKABLE bool requiresConfirmation(const QVariantMap &actionData) const;

signals:
    void actionsChanged();
    void dockActionsChanged();
    void busyChanged();
    void lastMessageChanged();
    void actionFinished(QString actionId, bool success, QString message);
    void actionLaunchRequested(QVariantMap appData);
    void controllerOffRequested();
    void screensaverRequested();
    void helpRequested();

private:
    QVariantList m_actions;
    QVariantList m_dockActions;
    QStringList m_dockActionIds;
    QSet<QString> m_seenActionIds;

    bool m_busy = false;
    QString m_lastMessage;

    QString m_neutronRootPath;
    QString m_appsRootPath;
    QString m_configRootPath;
    QString m_statePath;
    bool m_dockStateNeedsSave = false;

    void resolveRuntimePaths();
    QString resolveNeutronRootPath() const;

    void discoverActions();
    void discoverBuiltInActions();
    void discoverDropInAppActions();
    void discoverConfigActions();
    void discoverScriptActions();
    void discoverServiceActions();

    void discoverConfigFile(const QString &path);
    void discoverAppDirectory(const QString &directoryPath, int priority);
    void addAction(const QVariantMap &action);
    QVariantMap normalizeAction(QVariantMap action) const;

    QVariantMap readJsonObject(const QString &path) const;
    QVariantList readJsonArray(const QString &path) const;

    QString safeId(const QString &value) const;
    QString displayNameFromId(const QString &id) const;
    QString normalizedType(const QString &type) const;
    QString cleanPath(const QString &path) const;
    QString appMainQmlSource(const QString &appId) const;
    QString sharedIconFor(const QVariantMap &action) const;

    void loadDockState();
    bool saveDockState() const;
    void normalizeDockAssignments();
    void rebuildDockActions();
    QStringList defaultDockActionIds() const;

    void setBusy(bool busy);
    void setLastMessage(const QString &message);

    bool executeSystemAction(const QVariantMap &actionData);
    bool executeServiceAction(const QVariantMap &actionData);
    bool executeScriptAction(const QVariantMap &actionData);

    bool runCommandAction(const QString &actionId,
                          const QString &program,
                          const QStringList &arguments,
                          int timeoutMs);
    bool runSystemdAction(const QString &actionId,
                          const QString &unit,
                          const QString &actionName);
    bool runDockerAction(const QString &actionId,
                         const QString &container,
                         const QString &actionName);

    int runProcess(const QString &program,
                   const QStringList &arguments,
                   int timeoutMs,
                   QString *standardOutput = nullptr,
                   QString *standardError = nullptr) const;

    bool commandExists(const QString &command) const;
    bool systemdUnitExists(const QString &unit) const;
    bool dockerContainerExists(const QString &name) const;
    QStringList variantToStringList(const QVariant &value) const;
};
