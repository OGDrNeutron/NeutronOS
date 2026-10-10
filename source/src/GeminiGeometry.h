#pragma once
#include <QtQuick3D/QQuick3DGeometry>

// Gemini-only mesh generation. Animation stays in GPU shaders/QML scene nodes.
class GeminiRingGeometry : public QQuick3DGeometry {
    Q_OBJECT
public:
    explicit GeminiRingGeometry(QQuick3DObject *parent = nullptr);
};

class GeminiFractureGeometry : public QQuick3DGeometry {
    Q_OBJECT
    Q_PROPERTY(int columns READ columns WRITE setColumns NOTIFY columnsChanged)
public:
    explicit GeminiFractureGeometry(QQuick3DObject *parent = nullptr);
    int columns() const { return m_columns; }
    void setColumns(int value);
signals:
    void columnsChanged();
private:
    void rebuild();
    int m_columns = 24;
};
