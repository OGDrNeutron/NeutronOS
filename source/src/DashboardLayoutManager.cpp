#include "DashboardLayoutManager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QHash>
#include <QSet>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStringList>
#include <QUuid>

#include <algorithm>

namespace {
constexpr int DashboardColumns = 15;
constexpr int DashboardRows = 4;

QVariantMap widgetEntry(const QString &id, const QString &title, const QString &variant,
                        int order, int column, int row, bool enabled = true,
                        const QString &exclusiveGroup = QString())
{
    QString family = variant.section(QLatin1Char('-'), 0, 0);
    QString shape = variant.section(QLatin1Char('-'), 1, 1);
    if (variant == QStringLiteral("fixed")) {
        family = QStringLiteral("fixed");
        shape = QStringLiteral("square");
    }
    return {{QStringLiteral("id"), id}, {QStringLiteral("title"), title},
            {QStringLiteral("size"), variant}, {QStringLiteral("variant"), variant},
            {QStringLiteral("sizeFamily"), family}, {QStringLiteral("shape"), shape},
            {QStringLiteral("order"), order}, {QStringLiteral("position"), order},
            {QStringLiteral("gridColumn"), column}, {QStringLiteral("gridRow"), row},
            {QStringLiteral("enabled"), enabled},
            {QStringLiteral("exclusiveGroup"), exclusiveGroup}};
}
}

DashboardLayoutManager::DashboardLayoutManager(const QString &neutronRoot, QObject *parent)
    : QObject(parent), m_neutronRoot(QDir::cleanPath(neutronRoot))
{
    load();
}

QString DashboardLayoutManager::normalizedUser(const QString &username)
{
    const QString value = username.trimmed().toLower();
    static const QRegularExpression valid(QStringLiteral("^[a-z_][a-z0-9_-]{0,31}$"));
    return valid.match(value).hasMatch() ? value : QStringLiteral("default");
}

QString DashboardLayoutManager::normalizedTab(const QString &tab)
{
    const QString value = tab.trimmed().toLower();
    if (value == QStringLiteral("desktop") || value == QStringLiteral("system") ||
        value == QStringLiteral("security") ||
        value == QStringLiteral("storage") || value == QStringLiteral("apps") ||
        value == QStringLiteral("legacy"))
        return value;
    if (value == QStringLiteral("system overview"))
        return QStringLiteral("system");
    if (QRegularExpression(QStringLiteral("^custom-[a-z0-9-]{1,80}$")).match(value).hasMatch())
        return value;
    return QStringLiteral("system");
}

QString DashboardLayoutManager::normalizedSize(const QString &widgetId, const QString &size)
{
    if (widgetId == QStringLiteral("temperature"))
        return QStringLiteral("fixed");
    const QString value = size.trimmed().toLower();
    if (value == QStringLiteral("small")) return QStringLiteral("small-square");
    if (value == QStringLiteral("medium")) return QStringLiteral("medium-wide");
    if (value == QStringLiteral("large")) return QStringLiteral("large-wide");
    static const QStringList valid = {
        QStringLiteral("small-square"), QStringLiteral("medium-square"),
        QStringLiteral("medium-wide"), QStringLiteral("medium-tall"),
        QStringLiteral("large-square"), QStringLiteral("large-wide"),
        QStringLiteral("large-tall")};
    return valid.contains(value) ? value : QStringLiteral("small-square");
}

QVariantList DashboardLayoutManager::defaultWidgets()
{
    // Modal Reference composition on a resolution-independent 15x4 grid.
    // Media Storage and Uptime are mutually-exclusive occupants of one slot;
    // SystemOverviewView chooses from authoritative storage availability.
    return {widgetEntry(QStringLiteral("cpu"), QStringLiteral("CPU"), QStringLiteral("small-square"), 0, 0, 0),
            widgetEntry(QStringLiteral("memory"), QStringLiteral("RAM"), QStringLiteral("small-square"), 1, 2, 0),
            widgetEntry(QStringLiteral("storage"), QStringLiteral("Boot Storage"), QStringLiteral("medium-wide"), 2, 4, 0),
            widgetEntry(QStringLiteral("media-storage"), QStringLiteral("Extra Storage"), QStringLiteral("medium-wide"), 3, 8, 0, true, QStringLiteral("secondary-storage")),
            widgetEntry(QStringLiteral("uptime"), QStringLiteral("Uptime"), QStringLiteral("medium-wide"), 4, 8, 0, true, QStringLiteral("secondary-storage")),
            widgetEntry(QStringLiteral("user-clock"), QStringLiteral("User / Clock"), QStringLiteral("large-wide"), 5, 0, 2),
            widgetEntry(QStringLiteral("temperature"), QStringLiteral("Temperature"), QStringLiteral("fixed"), 6, 6, 2),
            widgetEntry(QStringLiteral("network"), QStringLiteral("Network"), QStringLiteral("medium-wide"), 7, 8, 2),
            widgetEntry(QStringLiteral("security"), QStringLiteral("Security Status"), QStringLiteral("large-tall"), 8, 12, 0)};
}

QVariantMap DashboardLayoutManager::variantGeometry(const QString &variant)
{
    const QString value = variant.trimmed().toLower();
    if (value == QStringLiteral("fixed") || value == QStringLiteral("small-square"))
        return {{QStringLiteral("columnSpan"), 2}, {QStringLiteral("rowSpan"), 2}};
    if (value == QStringLiteral("medium-square"))
        return {{QStringLiteral("columnSpan"), 3}, {QStringLiteral("rowSpan"), 3}};
    if (value == QStringLiteral("medium-wide"))
        return {{QStringLiteral("columnSpan"), 4}, {QStringLiteral("rowSpan"), 2}};
    if (value == QStringLiteral("medium-tall"))
        return {{QStringLiteral("columnSpan"), 2}, {QStringLiteral("rowSpan"), 3}};
    if (value == QStringLiteral("large-square"))
        return {{QStringLiteral("columnSpan"), 4}, {QStringLiteral("rowSpan"), 4}};
    if (value == QStringLiteral("large-wide"))
        return {{QStringLiteral("columnSpan"), 6}, {QStringLiteral("rowSpan"), 2}};
    if (value == QStringLiteral("large-tall"))
        return {{QStringLiteral("columnSpan"), 3}, {QStringLiteral("rowSpan"), 4}};
    return {};
}

bool DashboardLayoutManager::isSixWidgetGeneratedDefault(const QVariantList &widgets)
{
    const QStringList ids = {QStringLiteral("cpu"), QStringLiteral("memory"),
                             QStringLiteral("temperature"), QStringLiteral("storage"),
                             QStringLiteral("network"), QStringLiteral("security")};
    const QStringList sizes = {QStringLiteral("medium"), QStringLiteral("medium"),
                               QStringLiteral("fixed"), QStringLiteral("medium"),
                               QStringLiteral("medium"), QStringLiteral("medium")};
    if (widgets.size() != ids.size())
        return false;
    for (int index = 0; index < ids.size(); ++index) {
        const QVariantMap widget = widgets.at(index).toMap();
        if (widget.value(QStringLiteral("id")).toString() != ids.at(index) ||
                widget.value(QStringLiteral("size")).toString() != sizes.at(index) ||
                widget.value(QStringLiteral("order"), index).toInt() != index ||
                !widget.value(QStringLiteral("enabled"), true).toBool())
            return false;
    }
    return true;
}

bool DashboardLayoutManager::isSwappedSchemaFiveGeneratedLayout(const QVariantList &widgets)
{
    // Schema 5 briefly shipped this exact generated composition.  It put the
    // user card in the right column and Security along the lower row.  Match
    // every id, variant and logical position so a user-authored layout is not
    // mistaken for the generated physical-test regression.
    const struct Fingerprint {
        const char *id;
        const char *variant;
        int column;
        int row;
    } fingerprint[] = {
        {"cpu", "small-square", 0, 0},
        {"memory", "medium-wide", 2, 0},
        {"temperature", "fixed", 6, 0},
        {"storage", "medium-wide", 8, 0},
        {"media-storage", "medium-wide", 0, 2},
        {"user-clock", "small-square", 12, 0},
        {"network", "small-square", 4, 2},
        {"security", "large-wide", 6, 2},
        {"uptime", "small-square", 0, 2},
    };
    if (widgets.size() != static_cast<int>(std::size(fingerprint)))
        return false;
    for (int index = 0; index < widgets.size(); ++index) {
        const QVariantMap item = widgets.at(index).toMap();
        const Fingerprint &expected = fingerprint[index];
        if (item.value(QStringLiteral("id")).toString() != QLatin1String(expected.id) ||
                item.value(QStringLiteral("variant"), item.value(QStringLiteral("size"))).toString() != QLatin1String(expected.variant) ||
                item.value(QStringLiteral("gridColumn"), -1).toInt() != expected.column ||
                item.value(QStringLiteral("gridRow"), -1).toInt() != expected.row ||
                !item.value(QStringLiteral("enabled"), true).toBool())
            return false;
    }
    return true;
}

bool DashboardLayoutManager::isBrokenGeneratedLayout(const QVariantList &widgets)
{
    int enabled = 0;
    bool cpu = false, memory = false;
    const QStringList generatedIds = {QStringLiteral("cpu"), QStringLiteral("memory"),
                                      QStringLiteral("temperature"), QStringLiteral("storage"),
                                      QStringLiteral("network"), QStringLiteral("security")};
    const QStringList generatedSizes = {QStringLiteral("large"), QStringLiteral("small"),
                                        QStringLiteral("fixed"), QStringLiteral("small"),
                                        QStringLiteral("small"), QStringLiteral("small")};
    bool priorGeneratedComposition = widgets.size() == generatedIds.size();
    int generatedIndex = 0;
    for (const QVariant &entry : widgets) {
        const QVariantMap item = entry.toMap();
        if (priorGeneratedComposition) {
            priorGeneratedComposition = generatedIndex < generatedIds.size() &&
                    item.value(QStringLiteral("id")).toString() == generatedIds.at(generatedIndex) &&
                    item.value(QStringLiteral("size")).toString() == generatedSizes.at(generatedIndex) &&
                    item.value(QStringLiteral("order")).toInt() == generatedIndex &&
                    item.value(QStringLiteral("enabled"), true).toBool();
        }
        ++generatedIndex;
        if (!item.value(QStringLiteral("enabled"), true).toBool())
            continue;
        ++enabled;
        cpu |= item.value(QStringLiteral("id")).toString() == QStringLiteral("cpu");
        memory |= item.value(QStringLiteral("id")).toString() == QStringLiteral("memory");
    }
    // Both fingerprints were shipped generated defaults during the physical
    // regression: CPU/RAM-only, and the all-enabled but half-empty 3+1+2 / 1+1+1
    // composition. Exact matching avoids touching an intentional user layout.
    return (enabled == 2 && cpu && memory) || priorGeneratedComposition;
}

bool DashboardLayoutManager::isLegacyDefaultLayout(const QVariantList &widgets)
{
    const QStringList ids = {QStringLiteral("cpu"), QStringLiteral("memory"),
                             QStringLiteral("temperature"), QStringLiteral("storage"),
                             QStringLiteral("network"), QStringLiteral("security")};
    if (widgets.size() != ids.size())
        return false;
    for (int index = 0; index < ids.size(); ++index) {
        const QVariantMap widget = widgets.at(index).toMap();
        if (widget.value(QStringLiteral("id")).toString() != ids.at(index) ||
                !widget.value(QStringLiteral("enabled"), true).toBool() ||
                widget.value(QStringLiteral("order"), index).toInt() != index)
            return false;
        const QString size = widget.value(QStringLiteral("size")).toString();
        if (ids.at(index) == QStringLiteral("temperature")) {
            if (size != QStringLiteral("fixed")) return false;
        } else if (size != QStringLiteral("small")) {
            return false;
        }
    }
    return true;
}

QString DashboardLayoutManager::statePath() const
{
    return QDir(m_neutronRoot).filePath(QStringLiteral("state/users/%1/dashboard.json").arg(m_activeUser));
}

int DashboardLayoutManager::indexOf(const QString &widgetId) const
{
    for (int i = 0; i < m_widgets.size(); ++i)
        if (m_widgets.at(i).toMap().value(QStringLiteral("id")).toString() == widgetId)
            return i;
    return -1;
}

bool DashboardLayoutManager::packWidgets(QVariantList &widgets, bool preservePositions)
{
    bool occupied[DashboardRows][DashboardColumns] = {};
    QHash<QString, QVariantMap> exclusivePlacements;

    auto fits = [&occupied](int column, int row, int columnSpan, int rowSpan) {
        if (column < 0 || row < 0 || columnSpan < 1 || rowSpan < 1 ||
                column + columnSpan > DashboardColumns || row + rowSpan > DashboardRows)
            return false;
        for (int y = row; y < row + rowSpan; ++y)
            for (int x = column; x < column + columnSpan; ++x)
                if (occupied[y][x]) return false;
        return true;
    };
    auto occupy = [&occupied](int column, int row, int columnSpan, int rowSpan) {
        for (int y = row; y < row + rowSpan; ++y)
            for (int x = column; x < column + columnSpan; ++x)
                occupied[y][x] = true;
    };

    // Reserve full-height columns first. This both guarantees that tall
    // widgets remain visible during compact repacks and preserves the named
    // default's Security column on the right instead of fragmenting its only
    // legal four-row region with smaller cards.
    QSet<int> preplaced;
    for (int index = 0; index < widgets.size(); ++index) {
        QVariantMap value = widgets.at(index).toMap();
        if (!value.value(QStringLiteral("enabled"), true).toBool()) continue;
        const QVariantMap geometry = variantGeometry(value.value(QStringLiteral("variant"), value.value(QStringLiteral("size"))).toString());
        const int columnSpan = geometry.value(QStringLiteral("columnSpan")).toInt();
        const int rowSpan = geometry.value(QStringLiteral("rowSpan")).toInt();
        if (rowSpan != DashboardRows || columnSpan < 1) continue;
        int column = preservePositions ? value.value(QStringLiteral("gridColumn"), -1).toInt()
                                       : DashboardColumns - columnSpan;
        if (!fits(column, 0, columnSpan, rowSpan)) column = DashboardColumns - columnSpan;
        if (!fits(column, 0, columnSpan, rowSpan)) return false;
        value[QStringLiteral("gridColumn")] = column;
        value[QStringLiteral("gridRow")] = 0;
        value[QStringLiteral("columnSpan")] = columnSpan;
        value[QStringLiteral("rowSpan")] = rowSpan;
        occupy(column, 0, columnSpan, rowSpan);
        widgets[index] = value;
        preplaced.insert(index);
    }

    for (int index = 0; index < widgets.size(); ++index) {
        if (preplaced.contains(index)) continue;
        QVariantMap value = widgets.at(index).toMap();
        const QString variant = value.value(QStringLiteral("variant"), value.value(QStringLiteral("size"))).toString();
        const QVariantMap geometry = variantGeometry(variant);
        if (geometry.isEmpty()) return false;
        const int columnSpan = geometry.value(QStringLiteral("columnSpan")).toInt();
        const int rowSpan = geometry.value(QStringLiteral("rowSpan")).toInt();
        value[QStringLiteral("columnSpan")] = columnSpan;
        value[QStringLiteral("rowSpan")] = rowSpan;

        if (!value.value(QStringLiteral("enabled"), true).toBool()) {
            widgets[index] = value;
            continue;
        }

        const QString exclusiveGroup = value.value(QStringLiteral("exclusiveGroup")).toString();
        if (!exclusiveGroup.isEmpty() && exclusivePlacements.contains(exclusiveGroup)) {
            const QVariantMap placement = exclusivePlacements.value(exclusiveGroup);
            value[QStringLiteral("gridColumn")] = placement.value(QStringLiteral("gridColumn"));
            value[QStringLiteral("gridRow")] = placement.value(QStringLiteral("gridRow"));
            value[QStringLiteral("columnSpan")] = placement.value(QStringLiteral("columnSpan"));
            value[QStringLiteral("rowSpan")] = placement.value(QStringLiteral("rowSpan"));
            widgets[index] = value;
            continue;
        }

        int column = preservePositions ? value.value(QStringLiteral("gridColumn"), -1).toInt() : -1;
        int row = preservePositions ? value.value(QStringLiteral("gridRow"), -1).toInt() : -1;
        if (!fits(column, row, columnSpan, rowSpan)) {
            column = -1;
            row = -1;
            for (int candidateRow = 0; candidateRow <= DashboardRows - rowSpan && row < 0; ++candidateRow) {
                for (int candidateColumn = 0; candidateColumn <= DashboardColumns - columnSpan; ++candidateColumn) {
                    if (!fits(candidateColumn, candidateRow, columnSpan, rowSpan)) continue;
                    column = candidateColumn;
                    row = candidateRow;
                    break;
                }
            }
        }
        if (column < 0 || row < 0) return false;
        value[QStringLiteral("gridColumn")] = column;
        value[QStringLiteral("gridRow")] = row;
        occupy(column, row, columnSpan, rowSpan);
        if (!exclusiveGroup.isEmpty()) exclusivePlacements.insert(exclusiveGroup, value);
        widgets[index] = value;
    }
    return true;
}

bool DashboardLayoutManager::layoutIsValid(const QVariantList &widgets)
{
    QVariantList copy = widgets;
    if (!packWidgets(copy, true)) return false;
    for (int index = 0; index < widgets.size(); ++index) {
        const QVariantMap before = widgets.at(index).toMap();
        if (!before.value(QStringLiteral("enabled"), true).toBool()) continue;
        const QVariantMap after = copy.at(index).toMap();
        for (const QString &key : {QStringLiteral("gridColumn"), QStringLiteral("gridRow"),
                                   QStringLiteral("columnSpan"), QStringLiteral("rowSpan")})
            if (before.value(key).toInt() != after.value(key).toInt()) return false;
    }
    return true;
}

bool DashboardLayoutManager::normalizeAndReflow()
{
    const QVariantList defaults = defaultWidgets();
    QVariantList normalized;
    for (const QVariant &fallbackValue : defaults) {
        QVariantMap value = fallbackValue.toMap();
        const QString id = value.value(QStringLiteral("id")).toString();
        for (const QVariant &candidateValue : std::as_const(m_widgets)) {
            const QVariantMap candidate = candidateValue.toMap();
            if (candidate.value(QStringLiteral("id")).toString() != id)
                continue;
            const QString variant = normalizedSize(id, candidate.value(QStringLiteral("variant"), candidate.value(QStringLiteral("size"))).toString());
            value[QStringLiteral("size")] = variant;
            value[QStringLiteral("variant")] = variant;
            value[QStringLiteral("sizeFamily")] = variant == QStringLiteral("fixed") ? QStringLiteral("fixed") : variant.section(QLatin1Char('-'), 0, 0);
            value[QStringLiteral("shape")] = variant == QStringLiteral("fixed") ? QStringLiteral("square") : variant.section(QLatin1Char('-'), 1, 1);
            value[QStringLiteral("enabled")] = candidate.value(QStringLiteral("enabled"), true).toBool();
            value[QStringLiteral("order")] = candidate.value(QStringLiteral("order"), value.value(QStringLiteral("order"))).toInt();
            value[QStringLiteral("gridColumn")] = candidate.value(QStringLiteral("gridColumn"), value.value(QStringLiteral("gridColumn"))).toInt();
            value[QStringLiteral("gridRow")] = candidate.value(QStringLiteral("gridRow"), value.value(QStringLiteral("gridRow"))).toInt();
            break;
        }
        normalized.append(value);
    }
    std::stable_sort(normalized.begin(), normalized.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("order")).toInt() < b.toMap().value(QStringLiteral("order")).toInt();
    });
    int visiblePosition = 0;
    for (int i = 0; i < normalized.size(); ++i) {
        QVariantMap value = normalized.at(i).toMap();
        value[QStringLiteral("order")] = i;
        value[QStringLiteral("position")] = value.value(QStringLiteral("enabled")).toBool() ? visiblePosition++ : -1;
        normalized[i] = value;
    }
    if (!packWidgets(normalized, true) && !packWidgets(normalized, false))
        return false;
    m_widgets = normalized;
    return true;
}

void DashboardLayoutManager::load()
{
    m_widgets = defaultWidgets();
    m_defaultTab = QStringLiteral("desktop");
    m_homeTab = QStringLiteral("system");
    m_legacyAvailable = true;
    m_customTabs.clear();
    bool persistMigration = false;
    QFile file(statePath());
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
        if (document.isObject()) {
            const QJsonObject root = document.object();
            const int schema = root.value(QStringLiteral("schemaVersion")).toInt(1);
            persistMigration = schema < 6;
            m_defaultTab = normalizedTab(root.value(QStringLiteral("defaultTab")).toString(QStringLiteral("desktop")));
            m_homeTab = normalizedTab(root.value(QStringLiteral("homeTab")).toString(QStringLiteral("system")));
            // Before schema 3, false was an implicit generated default and
            // cannot be distinguished from user intent. Restore the physically
            // expected Legacy selector once, then persist explicit v3 state.
            m_legacyAvailable = schema < 3 ? true : root.value(QStringLiteral("legacyAvailable")).toBool(true);
            if (root.value(QStringLiteral("widgets")).isArray())
                m_widgets = root.value(QStringLiteral("widgets")).toArray().toVariantList();
            if (root.value(QStringLiteral("customTabs")).isArray())
                m_customTabs = root.value(QStringLiteral("customTabs")).toArray().toVariantList();
            if (schema < 2 &&
                    isLegacyDefaultLayout(m_widgets))
                m_widgets = defaultWidgets();
            if (schema < 3 && isBrokenGeneratedLayout(m_widgets))
                m_widgets = defaultWidgets();
            // Schema 3 shipped the physically incomplete six-card generated
            // composition. Only its exact fingerprint is upgraded; a user-
            // customized six-card layout is preserved and merely gains any
            // newly registered widgets through normalizeAndReflow().
            if (schema < 4 && isSixWidgetGeneratedDefault(m_widgets))
                m_widgets = defaultWidgets();
            if (schema < 6 && isSwappedSchemaFiveGeneratedLayout(m_widgets))
                m_widgets = defaultWidgets();
        }
    }
    const QVariantList loadedWidgets = m_widgets;
    if (!normalizeAndReflow()) {
        m_widgets = defaultWidgets();
        normalizeAndReflow();
        persistMigration = true;
    }
    if (m_widgets != loadedWidgets)
        persistMigration = true;
    if (!m_legacyAvailable && m_defaultTab == QStringLiteral("legacy"))
        m_defaultTab = QStringLiteral("system");
    if (!tabAvailable(m_defaultTab)) m_defaultTab = QStringLiteral("desktop");
    if (!tabAvailable(m_homeTab)) m_homeTab = QStringLiteral("system");
    if (persistMigration)
        save();
}

bool DashboardLayoutManager::save() const
{
    const QFileInfo info(statePath());
    if (!QDir().mkpath(info.absolutePath()))
        return false;
    QJsonObject root;
    root.insert(QStringLiteral("schemaVersion"), 6);
    root.insert(QStringLiteral("user"), m_activeUser);
    root.insert(QStringLiteral("defaultTab"), m_defaultTab);
    root.insert(QStringLiteral("homeTab"), m_homeTab);
    root.insert(QStringLiteral("legacyAvailable"), m_legacyAvailable);
    root.insert(QStringLiteral("widgets"), QJsonArray::fromVariantList(m_widgets));
    root.insert(QStringLiteral("customTabs"), QJsonArray::fromVariantList(m_customTabs));
    root.insert(QStringLiteral("updatedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    QSaveFile file(statePath());
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return file.commit();
}

bool DashboardLayoutManager::setActiveUser(const QString &username)
{
    const QString user = normalizedUser(username);
    if (user == m_activeUser)
        return true;
    m_moveSnapshot.clear();
    m_movingWidgetId.clear();
    m_activeUser = user;
    load();
    emit layoutChanged();
    return true;
}

bool DashboardLayoutManager::setDefaultTab(const QString &tab)
{
    const QString value = normalizedTab(tab);
    if (!tabAvailable(value))
        return false;
    if (value == m_defaultTab)
        return true;
    m_defaultTab = value;
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::setHomeTab(const QString &tab)
{
    QString value = normalizedTab(tab);
    if (!tabAvailable(value)) value = QStringLiteral("system");
    if (value == m_homeTab) return true;
    m_homeTab = value;
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::setLegacyAvailable(bool available)
{
    if (m_legacyAvailable == available &&
            (available || m_defaultTab != QStringLiteral("legacy")))
        return true;
    m_legacyAvailable = available;
    if (!available && m_defaultTab == QStringLiteral("legacy"))
        m_defaultTab = QStringLiteral("system");
    if (!available && m_homeTab == QStringLiteral("legacy"))
        m_homeTab = QStringLiteral("system");
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::setWidgetSize(const QString &widgetId, const QString &size)
{
    const int index = indexOf(widgetId);
    const QString variant = normalizedSize(widgetId, size);
    if (index < 0 || !canSetWidgetSize(widgetId, variant))
        return false;
    const QVariantList snapshot = m_widgets;
    QVariantMap value = m_widgets.at(index).toMap();
    value[QStringLiteral("size")] = variant;
    value[QStringLiteral("variant")] = variant;
    value[QStringLiteral("sizeFamily")] = variant == QStringLiteral("fixed") ? QStringLiteral("fixed") : variant.section(QLatin1Char('-'), 0, 0);
    value[QStringLiteral("shape")] = variant == QStringLiteral("fixed") ? QStringLiteral("square") : variant.section(QLatin1Char('-'), 1, 1);
    m_widgets[index] = value;
    if (!normalizeAndReflow()) {
        m_widgets = snapshot;
        return false;
    }
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::canSetWidgetSize(const QString &widgetId, const QString &requested) const
{
    const int index = indexOf(widgetId);
    if (index < 0) return false;
    const QString variant = normalizedSize(widgetId, requested);
    if (widgetId == QStringLiteral("temperature")) return variant == QStringLiteral("fixed");
    QVariantList candidate = m_widgets;
    QVariantMap value = candidate.at(index).toMap();
    value[QStringLiteral("size")] = variant;
    value[QStringLiteral("variant")] = variant;
    value[QStringLiteral("sizeFamily")] = variant.section(QLatin1Char('-'), 0, 0);
    value[QStringLiteral("shape")] = variant.section(QLatin1Char('-'), 1, 1);
    candidate[index] = value;
    QVariantList compactCandidate = candidate;
    return packWidgets(candidate, true) || packWidgets(compactCandidate, false);
}

QVariantList DashboardLayoutManager::availableSizeVariants(const QString &widgetId) const
{
    if (widgetId == QStringLiteral("temperature"))
        return {QVariantMap{{QStringLiteral("id"), QStringLiteral("fixed")},
                            {QStringLiteral("label"), QStringLiteral("Fixed Small Square")},
                            {QStringLiteral("family"), QStringLiteral("fixed")},
                            {QStringLiteral("shape"), QStringLiteral("square")},
                            {QStringLiteral("available"), true}}};
    const QVariantList definitions = {
        QVariantMap{{QStringLiteral("id"), QStringLiteral("small-square")}, {QStringLiteral("label"), QStringLiteral("Small Square")}, {QStringLiteral("family"), QStringLiteral("small")}, {QStringLiteral("shape"), QStringLiteral("square")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("medium-square")}, {QStringLiteral("label"), QStringLiteral("Medium Square")}, {QStringLiteral("family"), QStringLiteral("medium")}, {QStringLiteral("shape"), QStringLiteral("square")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("medium-wide")}, {QStringLiteral("label"), QStringLiteral("Medium Wide")}, {QStringLiteral("family"), QStringLiteral("medium")}, {QStringLiteral("shape"), QStringLiteral("wide")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("medium-tall")}, {QStringLiteral("label"), QStringLiteral("Medium Tall")}, {QStringLiteral("family"), QStringLiteral("medium")}, {QStringLiteral("shape"), QStringLiteral("tall")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("large-square")}, {QStringLiteral("label"), QStringLiteral("Large Square")}, {QStringLiteral("family"), QStringLiteral("large")}, {QStringLiteral("shape"), QStringLiteral("square")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("large-wide")}, {QStringLiteral("label"), QStringLiteral("Large Wide")}, {QStringLiteral("family"), QStringLiteral("large")}, {QStringLiteral("shape"), QStringLiteral("wide")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("large-tall")}, {QStringLiteral("label"), QStringLiteral("Large Tall")}, {QStringLiteral("family"), QStringLiteral("large")}, {QStringLiteral("shape"), QStringLiteral("tall")}}};
    QVariantList result;
    for (const QVariant &definitionValue : definitions) {
        QVariantMap definition = definitionValue.toMap();
        definition[QStringLiteral("available")] = canSetWidgetSize(widgetId, definition.value(QStringLiteral("id")).toString());
        result.append(definition);
    }
    return result;
}

bool DashboardLayoutManager::validateLayout() const
{
    return layoutIsValid(m_widgets);
}

bool DashboardLayoutManager::setWidgetEnabled(const QString &widgetId, bool enabled)
{
    const int index = indexOf(widgetId);
    if (index < 0)
        return false;
    const QVariantList snapshot = m_widgets;
    QVariantMap value = m_widgets.at(index).toMap();
    value[QStringLiteral("enabled")] = enabled;
    m_widgets[index] = value;
    if (!normalizeAndReflow()) {
        m_widgets = snapshot;
        return false;
    }
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::resetWidget(const QString &widgetId)
{
    const int index = indexOf(widgetId);
    if (index < 0) return false;
    QVariantMap replacement;
    for (const QVariant &entry : defaultWidgets()) {
        if (entry.toMap().value(QStringLiteral("id")).toString() == widgetId) {
            replacement = entry.toMap();
            break;
        }
    }
    if (replacement.isEmpty()) return false;
    const QVariantList snapshot = m_widgets;
    replacement[QStringLiteral("order")] = m_widgets.at(index).toMap().value(QStringLiteral("order"), index);
    m_widgets[index] = replacement;
    if (!normalizeAndReflow()) {
        m_widgets = snapshot;
        return false;
    }
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::moveWidget(const QString &widgetId, int delta)
{
    if (!moveWidgetInMemory(widgetId, delta))
        return false;
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::moveWidgetInMemory(const QString &widgetId, int delta)
{
    const int from = indexOf(widgetId);
    if (from < 0 || delta == 0)
        return from >= 0;
    const int last = static_cast<int>(m_widgets.size()) - 1;
    const int to = std::max(0, std::min(last, from + delta));
    if (from == to)
        return true;
    const QVariantList snapshot = m_widgets;
    m_widgets.move(from, to);
    // normalizeAndReflow() sorts by this field. Update it to the previewed
    // list order first, otherwise every D-pad move sorts itself straight back
    // to the original location before the view can render it.
    for (int index = 0; index < m_widgets.size(); ++index) {
        QVariantMap entry = m_widgets.at(index).toMap();
        entry[QStringLiteral("order")] = index;
        entry[QStringLiteral("gridColumn")] = -1;
        entry[QStringLiteral("gridRow")] = -1;
        m_widgets[index] = entry;
    }
    if (!normalizeAndReflow()) {
        m_widgets = snapshot;
        return false;
    }
    return true;
}

bool DashboardLayoutManager::beginWidgetMove(const QString &widgetId)
{
    if (indexOf(widgetId) < 0 || !m_movingWidgetId.isEmpty())
        return false;
    m_moveSnapshot = m_widgets;
    m_movingWidgetId = widgetId;
    return true;
}

bool DashboardLayoutManager::previewWidgetMove(int delta)
{
    if (m_movingWidgetId.isEmpty() || delta == 0)
        return false;
    if (!moveWidgetInMemory(m_movingWidgetId, delta))
        return false;
    emit layoutChanged();
    return true;
}

bool DashboardLayoutManager::commitWidgetMove()
{
    if (m_movingWidgetId.isEmpty())
        return false;
    m_moveSnapshot.clear();
    m_movingWidgetId.clear();
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::cancelWidgetMove()
{
    if (m_movingWidgetId.isEmpty())
        return false;
    m_widgets = m_moveSnapshot;
    m_moveSnapshot.clear();
    m_movingWidgetId.clear();
    normalizeAndReflow();
    emit layoutChanged();
    return true;
}

QVariantMap DashboardLayoutManager::widget(const QString &widgetId) const
{
    const int index = indexOf(widgetId);
    return index >= 0 ? m_widgets.at(index).toMap() : QVariantMap();
}

int DashboardLayoutManager::customTabIndex(const QString &tabId) const
{
    for (int i=0;i<m_customTabs.size();++i)
        if (m_customTabs.at(i).toMap().value(QStringLiteral("id")).toString() == tabId) return i;
    return -1;
}

bool DashboardLayoutManager::tabAvailable(const QString &tabId) const
{
    if (tabId == QStringLiteral("desktop") || tabId == QStringLiteral("system") ||
        tabId == QStringLiteral("security") ||
        tabId == QStringLiteral("storage") || tabId == QStringLiteral("apps")) return true;
    if (tabId == QStringLiteral("legacy")) return m_legacyAvailable;
    return customTabIndex(tabId) >= 0;
}

QVariantList DashboardLayoutManager::availableTabs() const
{
    QVariantList tabs{{QVariantMap{{"id","desktop"},{"label","Desktop"},{"icon","▤"}}},
                      {QVariantMap{{"id","system"},{"label","System Overview"},{"icon","◉"}}},
                      {QVariantMap{{"id","security"},{"label","Security"},{"icon","◈"}}},
                      {QVariantMap{{"id","storage"},{"label","Storage"},{"icon","▣"}}},
                      {QVariantMap{{"id","apps"},{"label","Apps"},{"icon","▦"}}}};
    if (m_legacyAvailable) tabs.append(QVariantMap{{"id","legacy"},{"label","Legacy"},{"icon","☰"}});
    for (const QVariant &value:m_customTabs) {
        const QVariantMap tab=value.toMap();
        tabs.append(QVariantMap{{"id",tab.value("id")},{"label",tab.value("name")},{"icon",tab.value("icon","◈")},{"custom",true},{"type",tab.value("type","widgets")}});
    }
    return tabs;
}

QString DashboardLayoutManager::createCustomTab(const QString &name,const QString &icon,const QString &layoutTemplate)
{
    const QString cleanName = name.trimmed().left(32);
    if (cleanName.isEmpty())
        return {};
    const QString id = QStringLiteral("custom-") +
            QUuid::createUuid().toString(QUuid::Id128).left(16);
    QVariantList content;
    if (layoutTemplate.trimmed().toLower() != QStringLiteral("blank")) {
        content = defaultWidgets();
        packWidgets(content, true);
    }
    m_customTabs.append(QVariantMap{{"id",id},{"name",cleanName},{"icon",icon.trimmed().isEmpty()?QStringLiteral("◈"):icon.left(4)},
                                    {"type","widgets"},{"template",layoutTemplate},{"widgets",content},{"order",m_customTabs.size()}});
    if (!save())
        return {};
    emit layoutChanged();
    return id;
}

bool DashboardLayoutManager::renameCustomTab(const QString &tabId,const QString &name)
{int i=customTabIndex(tabId);QString clean=name.trimmed().left(32);if(i<0||clean.isEmpty())return false;QVariantMap tab=m_customTabs[i].toMap();tab["name"]=clean;m_customTabs[i]=tab;bool ok=save();emit layoutChanged();return ok;}

bool DashboardLayoutManager::deleteCustomTab(const QString &tabId)
{int i=customTabIndex(tabId);if(i<0)return false;m_customTabs.removeAt(i);if(m_defaultTab==tabId)m_defaultTab="system";if(m_homeTab==tabId)m_homeTab="system";bool ok=save();emit layoutChanged();return ok;}

bool DashboardLayoutManager::makeRunningAppTab(const QVariantMap &runtime)
{
    const QString appId=runtime.value("appId").toString().trimmed();
    if(appId.isEmpty())return false;
    for(const QVariant &v:m_customTabs)if(v.toMap().value("appId").toString()==appId)return true;
    const QString name=runtime.value("displayName",appId).toString().left(32);
    const QString id=QStringLiteral("custom-")+QUuid::createUuid().toString(QUuid::Id128).left(16);
    m_customTabs.append(QVariantMap{{"id",id},{"name",name},{"icon","▶"},{"type","app"},{"appId",appId},
                                    {"runtimeId",runtime.value("runtimeId")},{"poster",runtime.value("poster")},{"order",m_customTabs.size()}});
    bool ok=save();emit layoutChanged();return ok;
}

QVariantMap DashboardLayoutManager::customTab(const QString &tabId) const
{int i=customTabIndex(tabId);return i<0?QVariantMap():m_customTabs.at(i).toMap();}

QVariantList DashboardLayoutManager::widgetsForTab(const QString &tabId) const
{if(tabId==QStringLiteral("system"))return m_widgets;return customTab(tabId).value("widgets").toList();}

bool DashboardLayoutManager::setTabWidgetEnabled(const QString &tabId,const QString &widgetId,bool enabled)
{
    if (tabId == QStringLiteral("system")) return setWidgetEnabled(widgetId, enabled);
    const int tabIndex = customTabIndex(tabId);
    if (tabIndex < 0) return false;
    QVariantMap tab = m_customTabs.at(tabIndex).toMap();
    QVariantList items = tab.value(QStringLiteral("widgets")).toList();
    for (int index = 0; index < items.size(); ++index) {
        QVariantMap widget = items.at(index).toMap();
        if (widget.value(QStringLiteral("id")).toString() != widgetId) continue;
        widget[QStringLiteral("enabled")] = enabled;
        items[index] = widget;
        QVariantList compact = items;
        if (!packWidgets(items, true) && !packWidgets(compact, false)) return false;
        if (!layoutIsValid(items)) items = compact;
        tab[QStringLiteral("widgets")] = items;
        m_customTabs[tabIndex] = tab;
        const bool ok = save();
        emit layoutChanged();
        return ok;
    }
    return false;
}

bool DashboardLayoutManager::setTabWidgetSize(const QString &tabId,const QString &widgetId,const QString &size)
{
    if (tabId == QStringLiteral("system")) return setWidgetSize(widgetId, size);
    const int tabIndex = customTabIndex(tabId);
    if (tabIndex < 0) return false;
    QVariantMap tab = m_customTabs.at(tabIndex).toMap();
    QVariantList items = tab.value(QStringLiteral("widgets")).toList();
    for (int index = 0; index < items.size(); ++index) {
        QVariantMap widget = items.at(index).toMap();
        if (widget.value(QStringLiteral("id")).toString() != widgetId) continue;
        const QString variant = normalizedSize(widgetId, size);
        widget[QStringLiteral("size")] = variant;
        widget[QStringLiteral("variant")] = variant;
        widget[QStringLiteral("sizeFamily")] = variant == QStringLiteral("fixed") ? QStringLiteral("fixed") : variant.section(QLatin1Char('-'), 0, 0);
        widget[QStringLiteral("shape")] = variant == QStringLiteral("fixed") ? QStringLiteral("square") : variant.section(QLatin1Char('-'), 1, 1);
        items[index] = widget;
        QVariantList compact = items;
        if (!packWidgets(items, true) && !packWidgets(compact, false)) return false;
        if (!layoutIsValid(items)) items = compact;
        tab[QStringLiteral("widgets")] = items;
        m_customTabs[tabIndex] = tab;
        const bool ok = save();
        emit layoutChanged();
        return ok;
    }
    return false;
}

bool DashboardLayoutManager::moveTabWidget(const QString &tabId,const QString &widgetId,int delta)
{
    if (tabId == QStringLiteral("system"))
        return moveWidget(widgetId, delta);
    const int tabIndex = customTabIndex(tabId);
    if (tabIndex < 0)
        return false;
    QVariantMap tab = m_customTabs.at(tabIndex).toMap();
    QVariantList items = tab.value(QStringLiteral("widgets")).toList();
    int from = -1;
    for (int index = 0; index < items.size(); ++index) {
        if (items.at(index).toMap().value(QStringLiteral("id")).toString() == widgetId) {
            from = index;
            break;
        }
    }
    if (from < 0 || items.isEmpty())
        return false;
    const int to = std::clamp(from + delta, 0, static_cast<int>(items.size()) - 1);
    items.move(from, to);
    int visiblePosition = 0;
    for (int index = 0; index < items.size(); ++index) {
        QVariantMap widget = items.at(index).toMap();
        widget[QStringLiteral("order")] = index;
        widget[QStringLiteral("position")] = widget.value(QStringLiteral("enabled"), true).toBool()
                ? visiblePosition++ : -1;
        widget[QStringLiteral("gridColumn")] = -1;
        widget[QStringLiteral("gridRow")] = -1;
        items[index] = widget;
    }
    if (!packWidgets(items, false))
        return false;
    tab[QStringLiteral("widgets")] = items;
    m_customTabs[tabIndex] = tab;
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

bool DashboardLayoutManager::beginTabWidgetMove(const QString &tabId, const QString &widgetId)
{
    if (tabId == QStringLiteral("system"))
        return beginWidgetMove(widgetId);
    if (customTabIndex(tabId) < 0 || !m_movingTabId.isEmpty())
        return false;
    const QVariantList items = widgetsForTab(tabId);
    bool found = false;
    for (const QVariant &item : items)
        found |= item.toMap().value(QStringLiteral("id")).toString() == widgetId;
    if (!found)
        return false;
    m_customTabsMoveSnapshot = m_customTabs;
    m_movingTabId = tabId;
    m_movingWidgetId = widgetId;
    return true;
}

bool DashboardLayoutManager::previewTabWidgetMove(int delta)
{
    if (m_movingTabId.isEmpty() || m_movingWidgetId.isEmpty() || delta == 0)
        return false;
    return moveTabWidget(m_movingTabId, m_movingWidgetId, delta);
}

bool DashboardLayoutManager::commitTabWidgetMove()
{
    if (m_movingTabId.isEmpty())
        return false;
    m_customTabsMoveSnapshot.clear();
    m_movingTabId.clear();
    m_movingWidgetId.clear();
    return true;
}

bool DashboardLayoutManager::cancelTabWidgetMove()
{
    if (m_movingTabId.isEmpty())
        return false;
    m_customTabs = m_customTabsMoveSnapshot;
    m_customTabsMoveSnapshot.clear();
    m_movingTabId.clear();
    m_movingWidgetId.clear();
    const bool ok = save();
    emit layoutChanged();
    return ok;
}

void DashboardLayoutManager::resetLayout()
{
    m_moveSnapshot.clear();
    m_movingWidgetId.clear();
    m_defaultTab = QStringLiteral("desktop");
    m_homeTab = QStringLiteral("system");
    m_legacyAvailable = true;
    m_widgets = defaultWidgets();
    normalizeAndReflow();
    save();
    emit layoutChanged();
}
