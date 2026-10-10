#include "FractureEffect.h"

#include <QColor>
#include <QMatrix4x4>
#include <QSGFlatColorMaterial>
#include <QSGGeometryNode>
#include <QSGOpacityNode>
#include <QSGTextureMaterial>
#include <QSGTextureProvider>
#include <QDebug>
#include <QSGTransformNode>
#include <QtMath>

#include <algorithm>
#include <utility>

namespace {
class StableRandom {
public:
    explicit StableRandom(quint32 seed) : state(seed ? seed : 1) {}
    qreal unit() { state = state * 1664525u + 1013904223u; return qreal(state & 0x00ffffffu) / qreal(0x01000000u); }
    qreal between(qreal low, qreal high) { return low + (high - low) * unit(); }
private: quint32 state;
};

QPointF rotated(const QPointF &point, const QPointF &center, qreal radians)
{
    const qreal x = point.x() - center.x(), y = point.y() - center.y();
    return center + QPointF(x * qCos(radians) - y * qSin(radians), x * qSin(radians) + y * qCos(radians));
}
}

FractureEffect::FractureEffect(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

void FractureEffect::setProgress(qreal value)
{
    value = std::clamp(value, qreal(0), qreal(1));
    if (value > 0 && m_geometryDirty)
        regenerate();
    if (qFuzzyCompare(m_progress, value))
        return;
    m_progress = value;
    update();
    emit progressChanged();
}

void FractureEffect::setOriginX(qreal value) { if(qFuzzyCompare(m_origin.x(),value))return;m_origin.setX(value);m_geometryDirty=true;update();emit originChanged(); }
void FractureEffect::setOriginY(qreal value) { if(qFuzzyCompare(m_origin.y(),value))return;m_origin.setY(value);m_geometryDirty=true;update();emit originChanged(); }
void FractureEffect::setSeed(int value) { if(m_seed==value)return;m_seed=value;m_geometryDirty=true;update();emit seedChanged(); }
void FractureEffect::setSourceItem(QQuickItem *item) { if(m_sourceItem==item)return;m_sourceItem=item;m_textureReady.store(false,std::memory_order_release);update();emit sourceItemChanged(); }
void FractureEffect::setFallbackRenderer(bool enabled) { if(m_fallbackRenderer==enabled)return;m_fallbackRenderer=enabled;update();emit fallbackRendererChanged(); }

void FractureEffect::regenerate()
{
    m_geometryDirty = false;
    m_segments.clear(); m_shards.clear(); StableRandom random{static_cast<quint32>(m_seed)};
    const int branches = 16 + int(random.unit() * 4);
    for (int branch=0; branch<branches; ++branch) {
        qreal angle = (M_PI*2*branch/branches) + random.between(-.10,.10);
        QPointF point=m_origin;
        const int count=6+int(random.unit()*4);
        for(int i=0;i<count;++i){
            const qreal length=random.between(.048,.092)*(1.0-i*.045); angle+=random.between(-.18,.18);
            QPointF next=point+QPointF(qCos(angle)*length,qSin(angle)*length);
            // Every primary ray releases together. Previously branch zero was
            // visible alone for a frame, which appeared as a green starter
            // dash before the radial impact existed.
            const qreal primaryRelease = i == 0 ? .018
                                                : .028 + qreal(i) / qreal(count) * .19;
            m_segments.append({point,next,primaryRelease});
            if(i>0&&random.unit()>.43){
                qreal fork=angle+random.between(-.78,.78);
                QPointF forkEnd=next+QPointF(qCos(fork)*length*.58,qSin(fork)*length*.58);
                const qreal forkRelease=.055+qreal(i)/qreal(count)*.18;
                m_segments.append({next,forkEnd,forkRelease});
                if(i>2&&random.unit()>.54){
                    const qreal twig=fork+random.between(-.62,.62);
                    const QPointF twigEnd=forkEnd+QPointF(qCos(twig)*length*.31,qSin(twig)*length*.31);
                    m_segments.append({forkEnd,twigEnd,std::min(qreal(.27),forkRelease+.025)});
                }
            }
            point=next;
        }
    }
    // One shared jittered grid covers the entire captured lock surface. The
    // shared vertices prevent gaps before separation while producing 49
    // irregular, Pi-friendly textured shards rather than QML Image objects.
    constexpr int rows = 7, columns = 7;
    QPointF grid[rows + 1][columns + 1];
    for (int row = 0; row <= rows; ++row) {
        for (int column = 0; column <= columns; ++column) {
            qreal x = qreal(column) / columns;
            qreal y = qreal(row) / rows;
            if (column > 0 && column < columns)
                x += random.between(-.026, .026);
            if (row > 0 && row < rows)
                y += random.between(-.026, .026);
            grid[row][column] = QPointF(x, y);
        }
    }
    for (int row = 0; row < rows; ++row) {
        for (int column = 0; column < columns; ++column) {
            Shard shard;
            shard.points = {grid[row][column], grid[row][column + 1],
                            grid[row + 1][column + 1], grid[row + 1][column]};
            QPointF center;
            for (const QPointF &point : std::as_const(shard.points))
                center += point;
            center /= shard.points.size();
            const QPointF away = center - m_origin;
            shard.velocity = QPointF(away.x() * random.between(.28, .58) + random.between(-.16, .16),
                                     random.between(.12, .34) + away.y() * .06);
            shard.spin = random.between(-2.4, 2.4);
            const qreal distance = qSqrt(away.x() * away.x() + away.y() * away.y());
            shard.release = std::clamp(.31 + distance * .13 + random.between(0, .15), .31, .58);
            m_shards.append(shard);
        }
    }
    qInfo().noquote() << QStringLiteral("UNLOCK: SHARDS_CREATED=%1").arg(m_shards.size());
    emit geometryChanged();
}

QSGNode *FractureEffect::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    delete oldNode;
    auto *root=new QSGNode;
    if(width()<=0||height()<=0)return root;
    QSGTexture *texture=nullptr;
    if(m_sourceItem&&m_sourceItem->isTextureProvider()&&m_sourceItem->textureProvider())texture=m_sourceItem->textureProvider()->texture();
    m_textureReady.store(texture != nullptr, std::memory_order_release);
    if(m_progress<=0)return root;
    const qreal w=width(),h=height();
    const int availableShards = static_cast<int>(m_shards.size());
    // Never substitute generic flat polygons for the lockscreen. The QML
    // capture gate does not hide LoginScreen or begin motion until this
    // texture exists, so an unavailable provider remains visually inert.
    const int shardLimit = (texture || m_fallbackRenderer) ? availableShards : 0;
    for(int shardIndex = 0; shardIndex < shardLimit; ++shardIndex){
        const Shard &shard = m_shards.at(shardIndex);
        const qreal t=m_progress<shard.release?0:std::clamp((m_progress-shard.release)/(1.0-shard.release),qreal(0),qreal(1));
        QPointF center;for(const QPointF&p:shard.points)center+=p;center/=shard.points.size();
        auto *geometry=new QSGGeometry(QSGGeometry::defaultAttributes_TexturedPoint2D(),shard.points.size());geometry->setDrawingMode(QSGGeometry::DrawTriangleFan);
        auto *vertices=geometry->vertexDataAsTexturedPoint2D();
        for(int i=0;i<shard.points.size();++i){QPointF p=rotated(shard.points.at(i),center,shard.spin*t*t);p+=shard.velocity*t*t+QPointF(0,1.38*t*t);vertices[i].set(p.x()*w,p.y()*h,shard.points.at(i).x(),shard.points.at(i).y());}
        auto *node=new QSGGeometryNode;node->setGeometry(geometry);node->setFlag(QSGNode::OwnsGeometry);
        if (texture) {
            auto *material=new QSGTextureMaterial;material->setTexture(texture);material->setFiltering(QSGTexture::Linear);node->setMaterial(material);node->setFlag(QSGNode::OwnsMaterial);
        } else {
            // Renderer-failure safety only: keep a real 49-piece gravity and
            // rotation animation instead of stranding the authenticated user.
            auto *material=new QSGFlatColorMaterial;
            const int variation = (shardIndex * 23) % 42;
            material->setColor(QColor(8 + variation / 3, 34 + variation, 48 + variation, 238));
            node->setMaterial(material);node->setFlag(QSGNode::OwnsMaterial);
        }
        auto *opacityNode=new QSGOpacityNode;
        opacityNode->setOpacity(float(1.0-std::clamp((t-.84)/.16,qreal(0),qreal(1))));
        opacityNode->appendChildNode(node);
        root->appendChildNode(opacityNode);
    }
    // NEUTRONOS_FRACTURE_SHARDS_ONLY_V1
    //
    // Crack paths are still generated internally because they participate in
    // the fracture topology/release model, but they are intentionally not
    // rendered. The transition is now shards-only: the captured screen breaks
    // apart and falls away without any green/cyan/violet crack overlay.
    return root;
}
