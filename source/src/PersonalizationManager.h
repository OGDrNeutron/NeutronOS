#pragma once

#include <QObject>
#include <QVariantList>

class PersonalizationManager final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString activeUser READ activeUser NOTIFY settingsChanged)
    Q_PROPERTY(bool systemOverviewEnabled READ systemOverviewEnabled NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList systemOverviewLayout READ systemOverviewLayout NOTIFY settingsChanged)
    Q_PROPERTY(bool systemOverviewCustomized READ systemOverviewCustomized NOTIFY settingsChanged)
    Q_PROPERTY(QString launcherMode READ launcherMode NOTIFY settingsChanged)
    Q_PROPERTY(int gridCardSize READ gridCardSize NOTIFY settingsChanged)
    Q_PROPERTY(int gridSpacing READ gridSpacing NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList availableSystemCards READ availableSystemCards CONSTANT)

public:
    explicit PersonalizationManager(const QString &neutronRoot, QObject *parent = nullptr);

    QString activeUser() const;
    bool systemOverviewEnabled() const;
    QVariantList systemOverviewLayout() const;
    bool systemOverviewCustomized() const;
    QString launcherMode() const;
    int gridCardSize() const;
    int gridSpacing() const;
    QVariantList availableSystemCards() const;

    Q_INVOKABLE void setActiveUser(const QString &username);
    Q_INVOKABLE bool applySystemOverview(const QVariantList &layout, bool enabled);
    Q_INVOKABLE bool resetSystemOverview();
    Q_INVOKABLE bool applyLauncher(const QString &mode, int cardSize, int spacing);
    Q_INVOKABLE bool resetLauncher();
    Q_INVOKABLE QVariantMap snapshot() const;

signals:
    void settingsChanged();
    void saveFailed(const QString &message);

private:
    QString normalizedUser(const QString &username) const;
    QString statePath() const;
    void load();
    bool save();
    QVariantList normalizedLayout(const QVariantList &layout) const;
    static QVariantList defaultLayout();

    QString m_stateRoot;
    QString m_activeUser = QStringLiteral("default");
    bool m_systemOverviewEnabled = true;
    QVariantList m_systemOverviewLayout;
    QString m_launcherMode = QStringLiteral("carousel");
    int m_gridCardSize = 100;
    int m_gridSpacing = 100;
};
