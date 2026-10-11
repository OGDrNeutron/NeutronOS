#include <QtTest>
#include <QGuiApplication>
#include <QCryptographicHash>
#include "GeminiGeometry.h"
#include <cmath>
class GeometryTest:public QObject {
 Q_OBJECT
private slots:
 void fracture_covers_surface_without_gaps_data(){QTest::addColumn<int>("columns");for(int n:{14,24,32})QTest::newRow(qPrintable(QString::number(n)))<<n;}
 void fracture_covers_surface_without_gaps(){
  QFETCH(int,columns);GeminiFractureGeometry g;g.setColumns(columns);
  const QByteArray data=g.vertexData();const int stride=g.stride();QCOMPARE(stride,56);QVERIFY(data.size()>0);QCOMPARE(data.size()%(3*stride),0);
  double area=0;QSet<QPair<float,float>> centers;
  for(int i=0;i<data.size();i+=3*stride){
   const float *a=reinterpret_cast<const float*>(data.constData()+i),*b=reinterpret_cast<const float*>(data.constData()+i+stride),*c=reinterpret_cast<const float*>(data.constData()+i+2*stride);
   for(auto p:{a,b,c}){for(int j=0;j<14;j++)QVERIFY(std::isfinite(p[j]));QVERIFY(p[6]>=-0.0001&&p[6]<=1.0001);QVERIFY(p[7]>=-0.0001&&p[7]<=1.0001);QCOMPARE(p[8],a[8]);QCOMPARE(p[9],a[9]);}
   QCOMPARE(a[10],1.f);QCOMPARE(b[10],0.f);QCOMPARE(c[10],0.f);
   area+=std::abs(double(b[0]-a[0])*(c[1]-a[1])-double(b[1]-a[1])*(c[0]-a[0]))/2;
   centers.insert({a[8],a[9]});
  }
  QVERIFY2(std::abs(area-1672.*941.)/(1672.*941.)<0.0005,"Irregular fragments must cover the complete setup surface");
  QCOMPARE(centers.size(),columns*qRound(columns*941./1672.));
  GeminiFractureGeometry same;same.setColumns(columns);QCOMPARE(same.vertexData(),data);
 }
 void helix_is_closed_finite_outward_and_bounded(){
  GeminiHelixGeometry g;const auto data=g.vertexData();const int stride=g.stride();
  QCOMPARE(stride,32);QCOMPARE(data.size(),640*10*6*stride);
  for(int i=0;i<data.size();i+=3*stride){
   const float *a=reinterpret_cast<const float*>(data.constData()+i),*b=reinterpret_cast<const float*>(data.constData()+i+stride),*c=reinterpret_cast<const float*>(data.constData()+i+2*stride);
   for(auto v:{a,b,c}){
    for(int k=0;k<8;k++)QVERIFY(std::isfinite(v[k]));
    const double r=std::hypot(v[0],v[1]);QVERIFY(r>225&&r<296);QVERIFY(std::abs(v[2])<35);
    QVERIFY(std::abs(v[3]*v[3]+v[4]*v[4]+v[5]*v[5]-1)<.0001);
   }
   QVector3D ab(b[0]-a[0],b[1]-a[1],b[2]-a[2]),ac(c[0]-a[0],c[1]-a[1],c[2]-a[2]);
   QVERIFY(QVector3D::dotProduct(QVector3D::crossProduct(ab,ac),QVector3D(a[3],a[4],a[5]))>0);
  }
  // Closing seam matches the first ring, including normals, with no gap or phase jump.
  for(int j=0;j<10;j++){
   const float *first=reinterpret_cast<const float*>(data.constData()+j*6*stride);
   const float *last=reinterpret_cast<const float*>(data.constData()+((639*10+j)*6+1)*stride);
   for(int k=0;k<6;k++)QVERIFY(std::abs(first[k]-last[k])<.001);
  }
  GeminiHelixGeometry same;QCOMPARE(same.vertexData(),data);
  g.setTubeRadius(.65f);QCOMPARE(g.tubeRadius(),.65f);QCOMPARE(g.vertexData().size(),data.size());
 }
 void molecular_rungs_are_connected_and_center_is_open(){
  GeminiHelixGeometry blue;blue.setStructure(1);GeminiHelixGeometry red;red.setStructure(2);GeminiHelixGeometry nodes;nodes.setStructure(3);
  for(auto g:{&blue,&red,&nodes}){
   const auto data=g->vertexData();QVERIFY(!data.isEmpty());QVERIFY(data.size()<12*1024*1024);
   for(int i=0;i<data.size();i+=g->stride()){
    const float *p=reinterpret_cast<const float*>(data.constData()+i);
    for(int j=0;j<8;j++)QVERIFY(std::isfinite(p[j]));
    QVERIFY(std::hypot(p[0],p[1])>225);QVERIFY(std::hypot(p[0],p[1])<296);QVERIFY(std::abs(p[2])<35);
   }
  }
  // At the zero-angle rung, both half-bonds meet at radius 260 and reach each backbone.
  for(auto pair:{qMakePair(&blue,qMakePair(260.f,288.f)),qMakePair(&red,qMakePair(232.f,260.f))}){
   const auto data=pair.first->vertexData();float lo=1000,hi=-1000;
   for(int i=0;i<8*6*pair.first->stride();i+=pair.first->stride()){
    const float *p=reinterpret_cast<const float*>(data.constData()+i);lo=std::min(lo,p[0]);hi=std::max(hi,p[0]);
   }
   QVERIFY(std::abs(lo-pair.second.first)<.001);QVERIFY(std::abs(hi-pair.second.second)<.001);
  }
 }
 void quality_count_is_bounded(){GeminiFractureGeometry g;g.setColumns(1);QCOMPARE(g.columns(),10);g.setColumns(100000);QCOMPARE(g.columns(),36);}
};
QTEST_MAIN(GeometryTest)
#include "geometry_test.moc"
