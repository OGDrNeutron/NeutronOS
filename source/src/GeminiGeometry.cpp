#include "GeminiGeometry.h"
#include <QVector2D>
#include <QRandomGenerator>
#include <QVector>
#include <algorithm>
#include <cmath>

namespace {
constexpr float pi = 3.14159265358979323846f;
struct RingVertex { float p[3], n[3], uv[2]; };
struct FragmentVertex { float p[3], n[3], uv[2], center[2], edge[4]; };
QVector<QVector2D> clip(const QVector<QVector2D> &polygon, QVector2D n, float offset) {
    QVector<QVector2D> out;
    if (polygon.isEmpty()) return out;
    auto prev = polygon.last();
    float dp = QVector2D::dotProduct(prev, n) - offset;
    for (const auto &point : polygon) {
        float d = QVector2D::dotProduct(point, n) - offset;
        if ((d <= 0) != (dp <= 0)) out.append(prev + (point-prev) * (dp / (dp-d)));
        if (d <= 0) out.append(point);
        prev=point; dp=d;
    }
    return out;
}
}
GeminiRingGeometry::GeminiRingGeometry(QQuick3DObject *parent) : QQuick3DGeometry(parent) {
    constexpr int segments=180, sides=8;
    QByteArray data;
    data.reserve(segments*sides*6*sizeof(RingVertex));
    auto vertex = [&](int i, int j) {
        const float a=2*pi*i/segments, b=2*pi*j/sides;
        const float ca=std::cos(a), sa=std::sin(a), cb=std::cos(b), sb=std::sin(b);
        RingVertex v{{(110+1.25f*cb)*ca,(110+1.25f*cb)*sa,1.25f*sb},
                     {cb*ca,cb*sa,sb},{float(i)/segments,float(j)/sides}};
        data.append(reinterpret_cast<const char *>(&v),sizeof(v));
    };
    for(int i=0;i<segments;++i) for(int j=0;j<sides;++j) {
        vertex(i,j);vertex(i+1,j);vertex(i+1,j+1);
        vertex(i,j);vertex(i+1,j+1);vertex(i,j+1);
    }
    setStride(sizeof(RingVertex));
    addAttribute(Attribute::PositionSemantic,0,Attribute::F32Type);
    addAttribute(Attribute::NormalSemantic,12,Attribute::F32Type);
    addAttribute(Attribute::TexCoordSemantic,24,Attribute::F32Type);
    setPrimitiveType(PrimitiveType::Triangles);setVertexData(data);
    setBounds(QVector3D(-112,-112,-2),QVector3D(112,112,2));
}
GeminiHelixGeometry::GeminiHelixGeometry(QQuick3DObject *parent) : QQuick3DGeometry(parent) { rebuild(); }
void GeminiHelixGeometry::setTubeRadius(float value) {
    value=std::clamp(value,.4f,4.0f);
    if(qFuzzyCompare(value,m_tubeRadius))return;
    m_tubeRadius=value;rebuild();emit tubeRadiusChanged();
}
void GeminiHelixGeometry::setStructure(int value) {
    value=std::clamp(value,0,3);
    if(value==m_structure)return;
    m_structure=value;rebuild();emit structureChanged();
}
void GeminiHelixGeometry::rebuild() {
    clear();
    constexpr int segments=640,sides=10,twists=10,rungs=160;
    constexpr float radius=260.0f,amplitude=28.0f;
    QByteArray data;
    auto append=[&](QVector3D p,QVector3D n,float u,float v) {
        const RingVertex vertex{{p.x(),p.y(),p.z()},{n.x(),n.y(),n.z()},{u,v}};
        data.append(reinterpret_cast<const char*>(&vertex),sizeof(vertex));
    };
    auto center=[&](float theta,float sign) {
        return QVector3D(std::cos(theta),std::sin(theta),0)*(radius+sign*amplitude*std::cos(theta*twists))
            +QVector3D(0,0,sign*amplitude*std::sin(theta*twists));
    };
    auto sphere=[&](QVector3D origin,float size,float u) {
        constexpr int latitude=6,longitude=8;
        auto v=[&](int i,int j){
            const float a=pi*i/latitude,b=2*pi*j/longitude;
            const QVector3D n(std::sin(a)*std::cos(b),std::sin(a)*std::sin(b),std::cos(a));
            append(origin+n*size,n,u,float(i)/latitude);
        };
        for(int i=0;i<latitude;i++)for(int j=0;j<longitude;j++){
            if(i>0){v(i,j);v(i+1,j);v(i,j+1);}
            if(i<latitude-1){v(i,j+1);v(i+1,j);v(i+1,j+1);}
        }
    };
    auto rod=[&](QVector3D from,QVector3D to,float size,float u) {
        const QVector3D direction=(to-from).normalized();
        const QVector3D reference=std::abs(direction.z())>.9f?QVector3D(0,1,0):QVector3D(0,0,1);
        const QVector3D normal=QVector3D::crossProduct(direction,reference).normalized();
        const QVector3D binormal=QVector3D::crossProduct(normal,direction).normalized();
        auto v=[&](int end,int side){
            const float a=2*pi*side/8;
            const QVector3D n=normal*std::cos(a)+binormal*std::sin(a);
            append((end?to:from)+n*size,n,u,float(side)/8);
        };
        for(int j=0;j<8;j++){v(0,j);v(1,j);v(1,j+1);v(0,j);v(1,j+1);v(0,j+1);}
    };
    if(m_structure==0) {
        data.reserve(segments*sides*6*sizeof(RingVertex));
        auto vertex=[&](int i,int j) {
            const float theta=2*pi*i/segments,phi=theta*twists;
            const QVector3D radial(std::cos(theta),std::sin(theta),0),axis(0,0,1);
            const QVector3D tangent=QVector3D(-std::sin(theta),std::cos(theta),0)*(radius+amplitude*std::cos(phi))
                +radial*(-amplitude*twists*std::sin(phi))+axis*(amplitude*twists*std::cos(phi));
            const QVector3D normal=(radial*std::cos(phi)+axis*std::sin(phi)).normalized();
            const QVector3D binormal=QVector3D::crossProduct(normal,tangent.normalized()).normalized();
            const float a=2*pi*j/sides;
            const QVector3D n=normal*std::cos(a)+binormal*std::sin(a);
            append(center(theta,1)+n*m_tubeRadius,n,float(i)/segments,float(j)/sides);
        };
        for(int i=0;i<segments;++i)for(int j=0;j<sides;++j){
            vertex(i,j);vertex(i+1,j);vertex(i+1,j+1);
            vertex(i,j);vertex(i+1,j+1);vertex(i,j+1);
        }
    } else if(m_structure==1||m_structure==2) {
        for(int i=0;i<rungs;i++){
            const float theta=2*pi*i/rungs,u=float(i)/rungs;
            const QVector3D blue=center(theta,1),red=center(theta,-1),mid=(blue+red)*.5f;
            const QVector3D from=m_structure==1?blue:mid,to=m_structure==1?mid:red;
            rod(from,to,1.35f,u);
            for(float t:{.18f,.52f,.86f})sphere(from+(to-from)*t,2.35f,u);
        }
    } else {
        for(int i=0;i<rungs;i++)sphere(center(2*pi*i/rungs,1),i%8==0?6.3f:i%2==0?3.7f:2.8f,float(i)/rungs);
    }
    setStride(sizeof(RingVertex));
    addAttribute(Attribute::PositionSemantic,0,Attribute::F32Type);
    addAttribute(Attribute::NormalSemantic,12,Attribute::F32Type);
    addAttribute(Attribute::TexCoordSemantic,24,Attribute::F32Type);
    setPrimitiveType(PrimitiveType::Triangles);setVertexData(data);
    setBounds(QVector3D(-296,-296,-35),QVector3D(296,296,35));update();
}

GeminiFractureGeometry::GeminiFractureGeometry(QQuick3DObject *parent) : QQuick3DGeometry(parent) { rebuild(); }
void GeminiFractureGeometry::setColumns(int value) {
    value=std::clamp(value,10,36);
    if(value==m_columns)return;
    m_columns=value;rebuild();emit columnsChanged();
}
void GeminiFractureGeometry::rebuild() {
    clear();
    const int rows=qRound(m_columns*941.0/1672.0);
    const float dx=1.0f/m_columns,dy=1.0f/rows;
    QRandomGenerator random(0x053A70u);
    QVector<QVector2D> sites;
    for(int y=0;y<rows;++y)for(int x=0;x<m_columns;++x)
        sites.append(QVector2D((x+0.5f+0.7f*(random.generateDouble()-0.5f))*dx,
                               (y+0.5f+0.7f*(random.generateDouble()-0.5f))*dy));
    QByteArray data;
    auto vertex=[&](QVector2D p,QVector2D center,float edge) {
        FragmentVertex v{{(p.x()-0.5f)*1672,(0.5f-p.y())*941,0},{0,0,1},
                         {p.x(),p.y()},{center.x(),center.y()},{edge,0,0,1}};
        data.append(reinterpret_cast<const char *>(&v),sizeof(v));
    };
    for(int i=0;i<sites.size();++i) {
        const auto site=sites[i];
        QVector<QVector2D> polygon{{0,0},{1,0},{1,1},{0,1}};
        for(int j=0;j<sites.size()&&!polygon.isEmpty();++j) {
            if(i==j)continue;
            const auto neighbor=sites[j];
            if(std::abs(site.x()-neighbor.x())>3*dx||std::abs(site.y()-neighbor.y())>3*dy)continue;
            polygon=clip(polygon,neighbor-site,(neighbor.lengthSquared()-site.lengthSquared())*0.5f);
        }
        if(polygon.size()<3)continue;
        for(int j=0;j<polygon.size();++j) {
            vertex(site,site,1);vertex(polygon[(j+1)%polygon.size()],site,0);vertex(polygon[j],site,0);
        }
    }
    setStride(sizeof(FragmentVertex));
    addAttribute(Attribute::PositionSemantic,0,Attribute::F32Type);
    addAttribute(Attribute::NormalSemantic,12,Attribute::F32Type);
    addAttribute(Attribute::TexCoordSemantic,24,Attribute::F32Type);
    addAttribute(Attribute::TexCoord1Semantic,32,Attribute::F32Type);
    addAttribute(Attribute::ColorSemantic,40,Attribute::F32Type);
    setPrimitiveType(PrimitiveType::Triangles);setVertexData(data);
    // Vertex-shader gravity/depth moves fragments beyond their original plane.
    setBounds(QVector3D(-10000,-10000,-5000),QVector3D(10000,10000,5000));update();
}
