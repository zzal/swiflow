// Sources/App/MapGeometry.swift
//
// Baked, pre-projected low-poly geometry. No runtime geo pipeline: the
// polygons ARE the map. Coordinates are viewBox units (1000 × 760,
// y-down). Multi-polygon zones render as one path with multiple
// subpaths (M…Z M…Z) and hit-test each polygon.
import GridCore

struct ProvinceShape {
    let zone: Zone
    let polygons: [[(Double, Double)]]
}

enum MapGeometry {
    static let viewWidth = 1000.0
    static let viewHeight = 760.0

    static let shapes: [ProvinceShape] = [
        ProvinceShape(zone: .yt, polygons: [[(60, 60), (150, 60), (150, 205), (100, 205), (60, 150)]]),
        ProvinceShape(zone: .nt, polygons: [[(150, 60), (330, 45), (355, 205), (150, 205)]]),
        ProvinceShape(zone: .nu, polygons: [[(330, 45), (700, 25), (760, 120), (700, 255), (430, 255), (355, 205)]]),
        ProvinceShape(zone: .bc, polygons: [[(75, 205), (210, 205), (210, 470), (158, 470), (118, 415), (75, 330)]]),
        ProvinceShape(zone: .ab, polygons: [[(210, 205), (300, 205), (300, 470), (210, 470)]]),
        ProvinceShape(zone: .sk, polygons: [[(300, 205), (385, 205), (385, 470), (300, 470)]]),
        ProvinceShape(zone: .mb, polygons: [[(385, 205), (470, 205), (470, 470), (385, 470)]]),
        ProvinceShape(zone: .on, polygons: [[(470, 205), (560, 225), (620, 255), (640, 315), (640, 420),
                                             (600, 470), (555, 555), (505, 535), (470, 470)]]),
        ProvinceShape(zone: .qc, polygons: [[(620, 255), (640, 205), (720, 175), (800, 215), (830, 300),
                                             (805, 415), (730, 470), (680, 430), (640, 420), (640, 315)]]),
        ProvinceShape(zone: .nl, polygons: [
            [(720, 175), (705, 95), (790, 80), (850, 150), (830, 215), (800, 215)],
            [(850, 330), (915, 320), (935, 368), (872, 392)],
        ]),
        ProvinceShape(zone: .nb, polygons: [[(770, 470), (828, 468), (834, 525), (776, 530)]]),
        ProvinceShape(zone: .pe, polygons: [[(845, 478), (882, 474), (886, 489), (850, 493)]]),
        ProvinceShape(zone: .ns, polygons: [[(838, 505), (928, 520), (940, 558), (852, 566), (824, 536)]]),
    ]

    /// Southern anchor for each zone's US-export arrow.
    static let usAnchors: [Zone: (Double, Double)] = [
        .bc: (160, 468), .mb: (427, 468), .on: (557, 553), .qc: (705, 462), .nb: (800, 528),
    ]

    static func pathString(_ shape: ProvinceShape) -> String {
        shape.polygons.map { poly in
            "M" + poly.map { "\($0.0),\($0.1)" }.joined(separator: "L") + "Z"
        }.joined()
    }

    /// Vertex mean of the first (main) polygon — good enough for labels
    /// and arc endpoints on a stylized map.
    static func centroid(_ zone: Zone) -> (Double, Double) {
        let poly = shapes.first { $0.zone == zone }!.polygons[0]
        let sx = poly.reduce(0.0) { $0 + $1.0 }
        let sy = poly.reduce(0.0) { $0 + $1.1 }
        return (sx / Double(poly.count), sy / Double(poly.count))
    }

    static func usAnchor(_ zone: Zone) -> (Double, Double) { usAnchors[zone]! }

    static func hitTest(x: Double, y: Double) -> Zone? {
        for shape in shapes {
            for poly in shape.polygons where contains(poly, x: x, y: y) {
                return shape.zone
            }
        }
        return nil
    }

    /// Standard even-odd ray cast.
    private static func contains(_ poly: [(Double, Double)], x: Double, y: Double) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let (xi, yi) = poly[i]
            let (xj, yj) = poly[j]
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
