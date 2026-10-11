#pragma once
#include <QtQuick3D/QQuick3DGeometry>

// Gemini-only mesh generation. Animation stays in GPU shaders/QML scene nodes.
class GeminiRingGeometry : public QQuick3DGeometry {
    Q_OBJECT
public:
    explicit GeminiRingGeometry(QQuick3DObject *parent = nullptr);
};

// Static closed toroidal strand. Only the scene transform animates; no per-frame mesh work.
class GeminiHelixGeometry : public QQuick3DGeometry {
    Q_OBJECT
    Q_PROPERTY(float tubeRadius READ tubeRadius WRITE setTubeRadius NOTIFY tubeRadiusChanged)
    Q_PROPERTY(int structure READ structure WRITE setStructure NOTIFY structureChanged)
public:
    explicit GeminiHelixGeometry(QQuick3DObject *parent = nullptr);
    int structure() const { return m_structure; }
    void setStructure(int value);
    float tubeRadius() const { return m_tubeRadius; }
    void setTubeRadius(float value);
signals:
    void tubeRadiusChanged();
    void structureChanged();
private:
    void rebuild();
    float m_tubeRadius = 3.4f;
    int m_structure = 0; // backbone, blue half-rungs, red half-rungs, molecular nodes
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
