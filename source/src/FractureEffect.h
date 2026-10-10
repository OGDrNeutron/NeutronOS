#pragma once

#include <QPointF>
#include <QQuickItem>
#include <QVector>
#include <atomic>

class FractureEffect : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(qreal progress READ progress WRITE setProgress NOTIFY progressChanged)
    Q_PROPERTY(qreal originX READ originX WRITE setOriginX NOTIFY originChanged)
    Q_PROPERTY(qreal originY READ originY WRITE setOriginY NOTIFY originChanged)
    Q_PROPERTY(int seed READ seed WRITE setSeed NOTIFY seedChanged)
    Q_PROPERTY(QQuickItem *sourceItem READ sourceItem WRITE setSourceItem NOTIFY sourceItemChanged)
    Q_PROPERTY(bool fallbackRenderer READ fallbackRenderer WRITE setFallbackRenderer NOTIFY fallbackRendererChanged)
    Q_PROPERTY(bool textureReady READ textureReady NOTIFY sourceItemChanged)
    Q_PROPERTY(int shardCount READ shardCount NOTIFY geometryChanged)

public:
    explicit FractureEffect(QQuickItem *parent = nullptr);
    qreal progress() const { return m_progress; }
    qreal originX() const { return m_origin.x(); }
    qreal originY() const { return m_origin.y(); }
    int seed() const { return m_seed; }
    QQuickItem *sourceItem() const { return m_sourceItem; }
    bool fallbackRenderer() const { return m_fallbackRenderer; }
    bool textureReady() const { return m_textureReady.load(std::memory_order_acquire); }
    int shardCount() const { return static_cast<int>(m_shards.size()); }

    void setProgress(qreal value);
    void setOriginX(qreal value);
    void setOriginY(qreal value);
    void setSeed(int value);
    void setSourceItem(QQuickItem *item);
    void setFallbackRenderer(bool enabled);

signals:
    void progressChanged();
    void originChanged();
    void seedChanged();
    void sourceItemChanged();
    void fallbackRendererChanged();
    void geometryChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

private:
    struct Segment { QPointF a; QPointF b; qreal release = 0; };
    struct Shard { QVector<QPointF> points; QPointF velocity; qreal spin = 0; qreal release = 0; };
    void regenerate();

    qreal m_progress = 0;
    QPointF m_origin {0.5, 0.42};
    int m_seed = 0x4e657574;
    QQuickItem *m_sourceItem = nullptr;
    bool m_fallbackRenderer = false;
    std::atomic_bool m_textureReady {false};
    QVector<Segment> m_segments;
    QVector<Shard> m_shards;
    bool m_geometryDirty = true;
};
