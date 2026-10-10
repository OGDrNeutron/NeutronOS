#include "DashboardLayoutManager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSizeF>
#include <QTemporaryDir>

#include <algorithm>
#include <cstdlib>

namespace {
void require(bool condition, const char *message)
{
    if (!condition) {
        qCritical("%s", message);
        std::exit(1);
    }
}
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir root;
    require(root.isValid(), "temporary root must be available");

    DashboardLayoutManager layout(root.path());
    require(layout.defaultTab() == QStringLiteral("desktop"), "Desktop must be the initial tab");
    require(layout.homeTab() == QStringLiteral("system"), "home shortcut must initially target System Overview");
    require(layout.widgets().size() == 9, "all canonical widgets must exist");
    for (const QVariant &entry : layout.widgets())
        require(entry.toMap().value(QStringLiteral("enabled")).toBool(), "all canonical widgets must be enabled by default");
    require(layout.validateLayout(), "canonical logical placement must be bounded and collision-free");
    require(layout.gridColumns() == 15 && layout.gridRows() == 4, "responsive grid must use the canonical 15x4 composition");
    auto requirePlacement = [&layout](const QString &id, const QString &variant, int column, int row, int columnSpan, int rowSpan) {
        const QVariantMap value = layout.widget(id);
        require(value.value(QStringLiteral("variant")).toString() == variant, "default variant must match reference composition");
        require(value.value(QStringLiteral("gridColumn")).toInt() == column, "default column must match reference composition");
        require(value.value(QStringLiteral("gridRow")).toInt() == row, "default row must match reference composition");
        require(value.value(QStringLiteral("columnSpan")).toInt() == columnSpan, "default column span must match reference composition");
        require(value.value(QStringLiteral("rowSpan")).toInt() == rowSpan, "default row span must match reference composition");
    };
    requirePlacement(QStringLiteral("cpu"), QStringLiteral("small-square"), 0, 0, 2, 2);
    requirePlacement(QStringLiteral("memory"), QStringLiteral("small-square"), 2, 0, 2, 2);
    requirePlacement(QStringLiteral("storage"), QStringLiteral("medium-wide"), 4, 0, 4, 2);
    requirePlacement(QStringLiteral("media-storage"), QStringLiteral("medium-wide"), 8, 0, 4, 2);
    requirePlacement(QStringLiteral("uptime"), QStringLiteral("medium-wide"), 8, 0, 4, 2);
    requirePlacement(QStringLiteral("user-clock"), QStringLiteral("large-wide"), 0, 2, 6, 2);
    requirePlacement(QStringLiteral("temperature"), QStringLiteral("fixed"), 6, 2, 2, 2);
    requirePlacement(QStringLiteral("network"), QStringLiteral("medium-wide"), 8, 2, 4, 2);
    requirePlacement(QStringLiteral("security"), QStringLiteral("large-tall"), 12, 0, 3, 4);
    const QStringList allVariants = {QStringLiteral("small-square"), QStringLiteral("medium-square"),
                                     QStringLiteral("medium-wide"), QStringLiteral("medium-tall"),
                                     QStringLiteral("large-square"), QStringLiteral("large-wide"),
                                     QStringLiteral("large-tall")};
    const QVariantList reportedVariants = layout.availableSizeVariants(QStringLiteral("cpu"));
    for (const QString &variant : allVariants) {
        bool found = false;
        for (const QVariant &entry : reportedVariants)
            found |= entry.toMap().value(QStringLiteral("id")).toString() == variant;
        require(found, "every requested size/shape variant must be represented");
    }
    require(layout.availableSizeVariants(QStringLiteral("temperature")).size() == 1,
            "temperature must expose only its fixed compact footprint");

    for (const QSizeF usable : {QSizeF(1844, 750), QSizeF(2464, 1000),
                                QSizeF(3764, 1500), QSizeF(1524, 600)}) {
        const qreal gap = std::max<qreal>(10, std::min<qreal>(22, usable.width() * .007));
        const qreal cellWidth = (usable.width() - gap * 14) / 15;
        const qreal cellHeight = (usable.height() - gap * 3) / 4;
        for (const QVariant &entry : layout.widgets()) {
            const QVariantMap value = entry.toMap();
            if (!value.value(QStringLiteral("enabled")).toBool() ||
                    value.value(QStringLiteral("id")).toString() == QStringLiteral("uptime"))
                continue;
            const qreal x = value.value(QStringLiteral("gridColumn")).toInt() * (cellWidth + gap);
            const qreal y = value.value(QStringLiteral("gridRow")).toInt() * (cellHeight + gap);
            const qreal width = value.value(QStringLiteral("columnSpan")).toInt() * cellWidth +
                    (value.value(QStringLiteral("columnSpan")).toInt() - 1) * gap;
            const qreal height = value.value(QStringLiteral("rowSpan")).toInt() * cellHeight +
                    (value.value(QStringLiteral("rowSpan")).toInt() - 1) * gap;
            require(x >= 0 && y >= 0 && x + width <= usable.width() + .01 &&
                    y + height <= usable.height() + .01,
                    "logical placement must remain completely visible at every target geometry");
        }
    }
    require(layout.setActiveUser(QStringLiteral("alice")), "alice profile should load");
    require(layout.setDefaultTab(QStringLiteral("storage")), "default tab should persist");
    require(!layout.canSetWidgetSize(QStringLiteral("cpu"), QStringLiteral("large-square")), "full layout must disable an impossible size");
    require(layout.setWidgetEnabled(QStringLiteral("storage"), false), "space can be released deliberately");
    require(layout.canSetWidgetSize(QStringLiteral("cpu"), QStringLiteral("large-wide")), "released grid space should expose a legal variant");
    require(layout.setWidgetSize(QStringLiteral("cpu"), QStringLiteral("large-wide")), "legal CPU variant should change");
    require(layout.setWidgetSize(QStringLiteral("temperature"), QStringLiteral("large")), "temperature request should normalize");
    require(layout.widget(QStringLiteral("temperature")).value(QStringLiteral("size")).toString() == QStringLiteral("fixed"),
            "temperature must remain one size");
    require(layout.beginWidgetMove(QStringLiteral("cpu")), "move mode should begin");
    require(layout.previewWidgetMove(1), "move preview should reflow immediately");
    require(layout.widget(QStringLiteral("cpu")).value(QStringLiteral("gridColumn")).toInt() != 0,
            "move preview must update live geometry before confirmation");
    require(layout.cancelWidgetMove(), "move cancellation should restore the snapshot");
    require(layout.widget(QStringLiteral("cpu")).value(QStringLiteral("gridColumn")).toInt() == 0,
            "cancelled movement must restore original geometry");
    require(layout.beginWidgetMove(QStringLiteral("cpu")), "second move mode should begin");
    require(layout.previewWidgetMove(1), "committed move preview should succeed");
    require(layout.commitWidgetMove(), "move mode should commit and persist");
    const int movedColumn = layout.widget(QStringLiteral("cpu")).value(QStringLiteral("gridColumn")).toInt();
    require(layout.setLegacyAvailable(false), "Legacy can be hidden without deleting its state");
    require(!layout.setDefaultTab(QStringLiteral("legacy")), "hidden Legacy must not become the default");
    require(layout.setLegacyAvailable(true), "Legacy availability should enable per user");
    require(layout.setDefaultTab(QStringLiteral("legacy")), "available Legacy should become the default");
    const QString customId = layout.createCustomTab(QStringLiteral("Media"));
    require(customId.startsWith(QStringLiteral("custom-")), "custom tab creation must return a stable id");
    require(layout.renameCustomTab(customId, QStringLiteral("Servers")), "custom tab should rename");
    require(layout.setHomeTab(customId), "a custom tab can be the Circle x5 destination");
    require(layout.setTabWidgetEnabled(customId, QStringLiteral("storage"), false),
            "custom layout can free a bounded slot before requesting a larger variant");
    require(layout.setTabWidgetSize(customId, QStringLiteral("cpu"), QStringLiteral("large")), "custom widget size must update");
    require(layout.setTabWidgetEnabled(customId, QStringLiteral("memory"), false), "custom widget can be disabled");
    require(layout.beginTabWidgetMove(customId, QStringLiteral("security")), "custom widget move should begin");
    require(layout.previewTabWidgetMove(-1), "custom widget movement should visibly reflow");
    require(layout.cancelTabWidgetMove(), "custom movement can restore its snapshot");
    require(layout.makeRunningAppTab({{QStringLiteral("appId"), QStringLiteral("jellyfin")},
                                      {QStringLiteral("displayName"), QStringLiteral("Jellyfin")},
                                      {QStringLiteral("runtimeId"), QStringLiteral("runtime-1")},
                                      {QStringLiteral("poster"), QStringLiteral("jellyfin")}}),
            "running app should become one persistent tab");
    require(layout.makeRunningAppTab({{QStringLiteral("appId"), QStringLiteral("jellyfin")}}),
            "adding the same runtime again must reuse the existing app tab");

    DashboardLayoutManager reloaded(root.path());
    reloaded.setActiveUser(QStringLiteral("alice"));
    require(reloaded.defaultTab() == QStringLiteral("legacy"), "Legacy default must survive reload");
    require(reloaded.legacyAvailable(), "Legacy availability must survive reload");
    require(reloaded.homeTab() == customId, "home Dashboard tab must survive reload");
    require(reloaded.customTabs().size() == 2, "custom and running-app tabs must survive without duplication");
    require(reloaded.widget(QStringLiteral("cpu")).value(QStringLiteral("variant")).toString() == QStringLiteral("large-wide"),
            "widget size must survive reload");
    require(reloaded.widget(QStringLiteral("cpu")).value(QStringLiteral("gridColumn")).toInt() == movedColumn,
            "widget placement must survive reload");

    reloaded.setActiveUser(QStringLiteral("bob"));
    require(reloaded.defaultTab() == QStringLiteral("desktop"), "user settings must not leak between accounts");
    require(reloaded.legacyAvailable(), "fresh users should receive the visible Legacy selector default");
    require(reloaded.widget(QStringLiteral("cpu")).value(QStringLiteral("variant")).toString() == QStringLiteral("small-square"),
            "widget layout must be per-user");

    reloaded.setActiveUser(QStringLiteral("alice"));
    require(reloaded.setLegacyAvailable(false), "Legacy availability should disable safely");
    require(reloaded.defaultTab() == QStringLiteral("system"), "disabling active/default Legacy must fall back to System Overview");
    require(reloaded.widget(QStringLiteral("cpu")).value(QStringLiteral("variant")).toString() == QStringLiteral("large-wide"),
            "hiding Legacy must preserve the user's other Dashboard state");
    require(reloaded.setLegacyAvailable(true), "Legacy should re-enable without rebuilding state");
    require(reloaded.legacyAvailable(), "Legacy should be available again");
    require(reloaded.deleteCustomTab(customId), "custom tab deletion should succeed");
    require(reloaded.homeTab() == QStringLiteral("system"), "deleting the configured home tab must safely fall back");

    const QString brokenUserDir = root.path() + QStringLiteral("/state/users/broken");
    require(QDir().mkpath(brokenUserDir), "broken migration fixture directory should exist");
    QFile brokenFile(brokenUserDir + QStringLiteral("/dashboard.json"));
    require(brokenFile.open(QIODevice::WriteOnly), "broken migration fixture should open");
    brokenFile.write(R"({"schemaVersion":2,"widgets":[
        {"id":"cpu","size":"medium","order":0,"enabled":true},
        {"id":"memory","size":"medium","order":1,"enabled":true},
        {"id":"temperature","size":"fixed","order":2,"enabled":false},
        {"id":"storage","size":"medium","order":3,"enabled":false},
        {"id":"network","size":"medium","order":4,"enabled":false},
        {"id":"security","size":"medium","order":5,"enabled":false}]})");
    brokenFile.close();
    require(reloaded.setActiveUser(QStringLiteral("broken")), "broken generated layout should load");
    int enabledCount = 0;
    for (const QVariant &entry : reloaded.widgets())
        enabledCount += entry.toMap().value(QStringLiteral("enabled")).toBool() ? 1 : 0;
    require(enabledCount == 9, "known CPU/RAM-only generated layout must migrate to the full composition");

    const QString sixUserDir = root.path() + QStringLiteral("/state/users/six-default");
    require(QDir().mkpath(sixUserDir), "six-widget migration fixture directory should exist");
    QFile sixFile(sixUserDir + QStringLiteral("/dashboard.json"));
    require(sixFile.open(QIODevice::WriteOnly), "six-widget migration fixture should open");
    sixFile.write(R"({"schemaVersion":3,"legacyAvailable":true,"widgets":[
        {"id":"cpu","size":"medium","order":0,"enabled":true},
        {"id":"memory","size":"medium","order":1,"enabled":true},
        {"id":"temperature","size":"fixed","order":2,"enabled":true},
        {"id":"storage","size":"medium","order":3,"enabled":true},
        {"id":"network","size":"medium","order":4,"enabled":true},
        {"id":"security","size":"medium","order":5,"enabled":true}]})");
    sixFile.close();
    require(reloaded.setActiveUser(QStringLiteral("six-default")), "schema-three generated layout should load");
    require(reloaded.widgets().size() == 9, "schema-three generated default must gain the full inventory");
    require(reloaded.widget(QStringLiteral("media-storage")).value(QStringLiteral("enabled")).toBool(),
            "media storage must remain configured for authoritative runtime availability selection");
    require(reloaded.widget(QStringLiteral("user-clock")).value(QStringLiteral("enabled")).toBool(),
            "user and clock card should be in the repaired default");
    require(reloaded.widget(QStringLiteral("uptime")).value(QStringLiteral("enabled")).toBool(),
            "uptime fallback must remain configured in the shared secondary-storage slot");

    const QString offscreenUserDir = root.path() + QStringLiteral("/state/users/offscreen");
    require(QDir().mkpath(offscreenUserDir), "offscreen migration fixture directory should exist");
    QFile offscreenFile(offscreenUserDir + QStringLiteral("/dashboard.json"));
    require(offscreenFile.open(QIODevice::WriteOnly), "offscreen migration fixture should open");
    offscreenFile.write(R"({"schemaVersion":5,"widgets":[
        {"id":"cpu","variant":"small-square","size":"small-square","order":0,"enabled":true,
         "gridColumn":99,"gridRow":99,"columnSpan":2,"rowSpan":2}]})");
    offscreenFile.close();
    require(reloaded.setActiveUser(QStringLiteral("offscreen")), "offscreen layout should migrate");
    require(reloaded.validateLayout(), "offscreen persisted coordinates must be repaired into the logical viewport");
    require(reloaded.widget(QStringLiteral("cpu")).value(QStringLiteral("gridColumn")).toInt() < 15,
            "repaired CPU widget must be inside the grid");
    DashboardLayoutManager repaired(root.path());
    repaired.setActiveUser(QStringLiteral("offscreen"));
    require(repaired.validateLayout(), "repaired offscreen layout must persist across reconstruction");

    const QString swappedUserDir = root.path() + QStringLiteral("/state/users/swapped-v5");
    require(QDir().mkpath(swappedUserDir), "swapped migration fixture directory should exist");
    QFile swappedFile(swappedUserDir + QStringLiteral("/dashboard.json"));
    require(swappedFile.open(QIODevice::WriteOnly), "swapped migration fixture should open");
    swappedFile.write(R"({"schemaVersion":5,"widgets":[
        {"id":"cpu","variant":"small-square","enabled":true,"gridColumn":0,"gridRow":0},
        {"id":"memory","variant":"medium-wide","enabled":true,"gridColumn":2,"gridRow":0},
        {"id":"temperature","variant":"fixed","enabled":true,"gridColumn":6,"gridRow":0},
        {"id":"storage","variant":"medium-wide","enabled":true,"gridColumn":8,"gridRow":0},
        {"id":"media-storage","variant":"medium-wide","enabled":true,"gridColumn":0,"gridRow":2},
        {"id":"user-clock","variant":"small-square","enabled":true,"gridColumn":12,"gridRow":0},
        {"id":"network","variant":"small-square","enabled":true,"gridColumn":4,"gridRow":2},
        {"id":"security","variant":"large-wide","enabled":true,"gridColumn":6,"gridRow":2},
        {"id":"uptime","variant":"small-square","enabled":true,"gridColumn":0,"gridRow":2}]})");
    swappedFile.close();
    require(repaired.setActiveUser(QStringLiteral("swapped-v5")), "swapped schema-five layout should load");
    require(repaired.validateLayout(), "swapped schema-five generated layout must migrate to a legal layout");
    require(repaired.widget(QStringLiteral("user-clock")).value(QStringLiteral("variant")).toString() == QStringLiteral("large-wide"),
            "swapped user card must migrate to the canonical wide placement");
    require(repaired.widget(QStringLiteral("security")).value(QStringLiteral("variant")).toString() == QStringLiteral("large-tall"),
            "swapped Security card must migrate to the canonical far-right tall placement");
    require(repaired.widget(QStringLiteral("security")).value(QStringLiteral("gridColumn")).toInt() == 12,
            "migrated Security card must occupy the far-right column");
    return 0;
}
