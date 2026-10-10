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
 void quality_count_is_bounded(){GeminiFractureGeometry g;g.setColumns(1);QCOMPARE(g.columns(),10);g.setColumns(100000);QCOMPARE(g.columns(),36);}
};
QTEST_MAIN(GeometryTest)
#include "geometry_test.moc"
