import QtQuick
import QtQuick.Shapes
Item {
    id:root
    property string kind:"backup"
    property color color:"#b7e8ff"
    readonly property var paths:({
        backup:"M 8 13 C 8 2 56 2 56 13 C 56 24 8 24 8 13 Z M 8 13 L 8 48 C 8 61 56 61 56 48 L 56 13 M 8 28 C 8 40 56 40 56 28 M 8 42 C 8 54 56 54 56 42 M 45 47 L 60 47 L 56 43 M 60 47 L 56 51",
        restore:"M 12 26 A 24 24 0 1 1 13 46 M 12 26 L 12 12 M 12 26 L 26 26",
        trash:"M 15 17 L 49 17 L 46 56 L 18 56 Z M 10 13 L 54 13 M 23 13 L 23 6 L 41 6 L 41 13 M 25 24 L 25 49 M 32 24 L 32 49 M 39 24 L 39 49",
        drive:"M 16 12 L 48 12 L 52 18 L 52 55 L 12 55 L 12 18 Z M 24 12 L 24 5 L 40 5 L 40 12 M 21 46 L 24 46 M 40 46 L 43 46",
        tools:"M 32 8 L 37 16 L 46 15 L 49 24 L 57 29 L 54 38 L 48 41 L 45 52 L 36 50 L 31 58 L 25 50 L 15 51 L 14 41 L 7 35 L 11 27 L 15 23 L 18 14 L 27 17 Z M 32 22 A 11 11 0 1 0 32 44 A 11 11 0 1 0 32 22",
        power:"M 32 4 L 32 29 M 20 12 A 24 24 0 1 0 44 12",
        info:"M 32 5 A 27 27 0 1 0 32 59 A 27 27 0 1 0 32 5 M 32 29 L 32 47 M 32 18 L 32 20",
        secure:"M 32 5 L 52 12 L 52 31 C 52 44 32 58 32 58 C 32 58 12 44 12 31 L 12 12 Z M 21 31 L 29 39 L 43 23",
        unsecure:"M 32 5 L 52 12 L 52 31 C 52 44 32 58 32 58 C 32 58 12 44 12 31 L 12 12 Z M 23 23 L 41 41 M 41 23 L 23 41"
    })
    Item{width:64;height:64;anchors.centerIn:parent;scale:Math.min(root.width/64,root.height/64)
        Shape{anchors.fill:parent;preferredRendererType:Shape.CurveRenderer
            ShapePath{strokeColor:Qt.rgba(root.color.r,root.color.g,root.color.b,.2);strokeWidth:7;fillColor:"transparent";capStyle:ShapePath.RoundCap;joinStyle:ShapePath.RoundJoin;PathSvg{path:root.paths[root.kind]||root.paths.backup}}
            ShapePath{strokeColor:root.color;strokeWidth:2.8;fillColor:"transparent";capStyle:ShapePath.RoundCap;joinStyle:ShapePath.RoundJoin;PathSvg{path:root.paths[root.kind]||root.paths.backup}}
        }
    }
}
