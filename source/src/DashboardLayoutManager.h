#pragma once

#include <QObject>
#include <QVariantList>

class DashboardLayoutManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString activeUser READ activeUser NOTIFY layoutChanged)
    Q_PROPERTY(QString defaultTab READ defaultTab NOTIFY layoutChanged)
    Q_PROPERTY(QString homeTab READ homeTab NOTIFY layoutChanged)
    Q_PROPERTY(QVariantList widgets READ widgets NOTIFY layoutChanged)
    Q_PROPERTY(bool legacyAvailable READ legacyAvailable NOTIFY layoutChanged)
    Q_PROPERTY(QVariantList customTabs READ customTabs NOTIFY layoutChanged)
    Q_PROPERTY(QVariantList availableTabs READ availableTabs NOTIFY layoutChanged)
    Q_PROPERTY(int gridColumns READ gridColumns CONSTANT)
    Q_PROPERTY(int gridRows READ gridRows CONSTANT)

public:
    explicit DashboardLayoutManager(const QString &neutronRoot, QObject *parent = nullptr);

    QString activeUser() const { return m_activeUser; }
    QString defaultTab() const { return m_defaultTab; }
    QString homeTab() const { return m_homeTab; }
    QVariantList widgets() const { return m_widgets; }
    bool legacyAvailable() const { return m_legacyAvailable; }
    QVariantList customTabs() const { return m_customTabs; }
    QVariantList availableTabs() const;
    int gridColumns() const { return 15; }
    int gridRows() const { return 4; }

    Q_INVOKABLE bool setActiveUser(const QString &username);
    Q_INVOKABLE bool setDefaultTab(const QString &tab);
    Q_INVOKABLE bool setHomeTab(const QString &tab);
    Q_INVOKABLE bool setLegacyAvailable(bool available);
    Q_INVOKABLE bool setWidgetSize(const QString &widgetId, const QString &size);
    Q_INVOKABLE bool canSetWidgetSize(const QString &widgetId, const QString &variant) const;
    Q_INVOKABLE QVariantList availableSizeVariants(const QString &widgetId) const;
    Q_INVOKABLE bool validateLayout() const;
    Q_INVOKABLE bool setWidgetEnabled(const QString &widgetId, bool enabled);
    Q_INVOKABLE bool resetWidget(const QString &widgetId);
    Q_INVOKABLE bool moveWidget(const QString &widgetId, int delta);
    Q_INVOKABLE bool beginWidgetMove(const QString &widgetId);
    Q_INVOKABLE bool previewWidgetMove(int delta);
    Q_INVOKABLE bool commitWidgetMove();
    Q_INVOKABLE bool cancelWidgetMove();
    Q_INVOKABLE QVariantMap widget(const QString &widgetId) const;
    Q_INVOKABLE QString createCustomTab(const QString &name, const QString &icon = QStringLiteral("◈"),
                                        const QString &layoutTemplate = QStringLiteral("system"));
    Q_INVOKABLE bool renameCustomTab(const QString &tabId, const QString &name);
    Q_INVOKABLE bool deleteCustomTab(const QString &tabId);
    Q_INVOKABLE bool makeRunningAppTab(const QVariantMap &runtime);
    Q_INVOKABLE QVariantMap customTab(const QString &tabId) const;
    Q_INVOKABLE QVariantList widgetsForTab(const QString &tabId) const;
    Q_INVOKABLE bool setTabWidgetEnabled(const QString &tabId, const QString &widgetId, bool enabled);
    Q_INVOKABLE bool setTabWidgetSize(const QString &tabId, const QString &widgetId, const QString &size);
    Q_INVOKABLE bool moveTabWidget(const QString &tabId, const QString &widgetId, int delta);
    Q_INVOKABLE bool beginTabWidgetMove(const QString &tabId, const QString &widgetId);
    Q_INVOKABLE bool previewTabWidgetMove(int delta);
    Q_INVOKABLE bool commitTabWidgetMove();
    Q_INVOKABLE bool cancelTabWidgetMove();
    Q_INVOKABLE void resetLayout();

signals:
    void layoutChanged();

private:
    QString m_neutronRoot;
    QString m_activeUser = QStringLiteral("default");
    QString m_defaultTab = QStringLiteral("desktop");
    QString m_homeTab = QStringLiteral("system");
    bool m_legacyAvailable = true;
    QVariantList m_widgets;
    QVariantList m_customTabs;
    QVariantList m_customTabsMoveSnapshot;
    QVariantList m_moveSnapshot;
    QString m_movingWidgetId;
    QString m_movingTabId;

    static QString normalizedUser(const QString &username);
    static QString normalizedTab(const QString &tab);
    static QString normalizedSize(const QString &widgetId, const QString &size);
    static QVariantList defaultWidgets();
    QString statePath() const;
    void load();
    bool save() const;
    bool normalizeAndReflow();
    static bool packWidgets(QVariantList &widgets, bool preservePositions);
    static QVariantMap variantGeometry(const QString &variant);
    static bool layoutIsValid(const QVariantList &widgets);
    bool moveWidgetInMemory(const QString &widgetId, int delta);
    static bool isLegacyDefaultLayout(const QVariantList &widgets);
    static bool isBrokenGeneratedLayout(const QVariantList &widgets);
    static bool isSixWidgetGeneratedDefault(const QVariantList &widgets);
    static bool isSwappedSchemaFiveGeneratedLayout(const QVariantList &widgets);
    int customTabIndex(const QString &tabId) const;
    bool tabAvailable(const QString &tabId) const;
    int indexOf(const QString &widgetId) const;
};
