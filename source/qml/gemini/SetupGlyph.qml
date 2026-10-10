import QtQuick
import QtQuick.Shapes
Item {
    id:root
    property string kind:"user"
    property color color:"#88D6FF"
    width:42;height:42
    readonly property var paths: ({
        lock:"M 9 18 L 33 18 L 33 37 L 9 37 Z M 14 18 L 14 11 A 7 7 0 0 1 28 11 L 28 18 M 21 26 L 21 31",
        info:"M 21 3 A 18 18 0 1 0 21 39 A 18 18 0 1 0 21 3 M 21 18 L 21 31 M 21 10 L 21 11",
        search:"M 17 3 A 13 13 0 1 0 17 29 A 13 13 0 1 0 17 3 M 27 27 L 39 39",
        list:"M 13 9 L 39 9 M 13 21 L 39 21 M 13 33 L 39 33 M 4 9 L 5 9 M 4 21 L 5 21 M 4 33 L 5 33",
        ban:"M 21 3 A 18 18 0 1 0 21 39 A 18 18 0 1 0 21 3 M 9 9 L 33 33",
        chip:"M 10 10 L 32 10 L 32 32 L 10 32 Z M 16 16 L 26 16 L 26 26 L 16 26 Z M 15 3 L 15 10 M 27 3 L 27 10 M 15 32 L 15 39 M 27 32 L 27 39 M 3 15 L 10 15 M 3 27 L 10 27 M 32 15 L 39 15 M 32 27 L 39 27",
        gavel:"M 21 4 L 35 18 L 29 24 L 15 10 Z M 22 17 L 7 32 M 4 38 L 24 38",
        brain:"M 21 7 C 6 -3 2 14 7 18 C 0 30 13 40 21 34 C 29 40 42 30 35 18 C 40 14 36 -3 21 7 Z M 21 7 L 21 34 M 10 13 L 15 18 L 12 25 M 32 13 L 27 18 L 30 25",
        chart:"M 6 36 L 6 21 L 12 21 L 12 36 Z M 18 36 L 18 8 L 24 8 L 24 36 Z M 30 36 L 30 16 L 36 16 L 36 36 Z",
        eye:"M 3 21 C 12 5 30 5 39 21 C 30 37 12 37 3 21 Z M 21 13 A 8 8 0 1 0 21 29 A 8 8 0 1 0 21 13 M 6 36 L 36 6",
        globe:"M 21 3 A 18 18 0 1 0 21 39 A 18 18 0 1 0 21 3 M 3 21 L 39 21 M 6 12 L 36 12 M 6 30 L 36 30 M 21 3 C 7 12 7 30 21 39 C 35 30 35 12 21 3 M 21 3 L 21 39",
        clock:"M 21 3 A 18 18 0 1 0 21 39 A 18 18 0 1 0 21 3 M 21 10 L 21 22 L 30 27",
        flag:"M 5 5 L 37 5 L 37 29 L 5 29 Z M 5 12 L 37 12 M 5 19 L 37 19 M 5 26 L 37 26",
        user:"M 21 4 A 7 7 0 1 0 21 18 A 7 7 0 1 0 21 4 M 7 36 C 7 19 35 19 35 36 Z",
        key:"M 26 5 A 9 9 0 1 0 26 23 A 9 9 0 1 0 26 5 M 19 22 L 5 36 L 5 29 L 11 29 L 11 24 L 16 24",
        controller:"M 12 12 C 4 12 2 33 8 33 L 16 27 L 26 27 L 34 33 C 40 33 38 12 30 12 Z M 10 19 L 18 19 M 14 15 L 14 23 M 29 18 L 30 18 M 33 23 L 34 23",
        audio:"M 5 16 L 13 16 L 24 6 L 24 36 L 13 26 L 5 26 Z M 29 13 C 38 17 38 25 29 29",
        display:"M 4 6 L 38 6 L 38 29 L 4 29 Z M 21 29 L 21 36 M 12 36 L 30 36",
        power:"M 21 3 L 21 20 M 11 8 A 16 16 0 1 0 31 8",
        shield:"M 21 3 L 36 9 L 36 22 C 36 31 21 39 21 39 C 21 39 6 31 6 22 L 6 9 Z",
        wifi:"M 4 13 C 13 4 29 4 38 13 M 10 20 C 16 14 26 14 32 20 M 16 27 C 19 24 23 24 26 27 M 21 33 L 21 34",
        storage:"M 5 6 L 37 6 L 37 36 L 5 36 Z M 10 29 L 12 29 M 29 29 L 32 29",
        ssh:"M 5 9 L 16 20 L 5 31 M 22 31 L 37 31",
        home:"M 3 20 L 21 3 L 39 20 M 8 17 L 8 37 L 34 37 L 34 17 M 16 37 L 16 25 L 26 25 L 26 37"
    })
    Item {width:42;height:42;anchors.centerIn:parent;scale:Math.min(root.width/42,root.height/42)
    Shape {anchors.fill:parent;ShapePath{strokeColor:root.color;strokeWidth:2.7;fillColor:"transparent";capStyle:ShapePath.RoundCap;joinStyle:ShapePath.RoundJoin;PathSvg{path:root.paths[root.kind] || root.paths.user}}}
    }
}
