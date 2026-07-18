// Sources/App/MapGeometry.swift
//
// Baked, pre-projected low-poly geometry. No runtime geo pipeline: the
// polygons ARE the map. Coordinates are viewBox units (1000 × 620,
// y-down), hand-traced from an equirectangular Canada so the landmarks
// read: Hudson Bay and James Bay as negative space, the straight
// prairie meridian borders, BC's fjord coast + Vancouver Island, the
// Ungava peninsula, Gaspé, the Maritimes, and Baffin Island.
// Multi-polygon zones render as one path with multiple subpaths
// (M…Z M…Z) and hit-test each polygon.
import GridCore

struct ProvinceShape {
    let zone: Zone
    let polygons: [[(Double, Double)]]
}

enum MapGeometry {
    static let viewWidth = 1000.0
    static let viewHeight = 620.0

    static let shapes: [ProvinceShape] = [
        ProvinceShape(zone: .yt, polygons: [
            [(88, 68), (152, 62), (178, 205), (88, 205)],
        ]),
        ProvinceShape(zone: .nt, polygons: [
            [(152, 62), (300, 50), (430, 58), (430, 205), (178, 205)],
        ]),
        ProvinceShape(zone: .nu, polygons: [
            // Mainland, wrapping Hudson Bay's northwest shore.
            [(430, 58), (556, 66), (596, 132), (552, 198), (528, 205), (430, 205)],
            // Baffin Island.
            [(640, 50), (762, 40), (802, 96), (742, 118), (720, 152), (656, 120)],
            // Victoria Island hint.
            [(470, 28), (562, 24), (576, 56), (480, 58)],
        ]),
        ProvinceShape(zone: .bc, polygons: [
            [(88, 205), (210, 205), (218, 340), (258, 460), (196, 462), (180, 430),
             (160, 438), (148, 400), (128, 408), (112, 360), (96, 300), (88, 248)],
            // Vancouver Island.
            [(118, 430), (158, 452), (148, 470), (110, 450)],
        ]),
        ProvinceShape(zone: .ab, polygons: [
            [(210, 205), (330, 205), (330, 460), (258, 460), (218, 340)],
        ]),
        ProvinceShape(zone: .sk, polygons: [
            [(330, 205), (430, 205), (430, 460), (330, 460)],
        ]),
        ProvinceShape(zone: .mb, polygons: [
            // The northeast corner touches Hudson Bay at Churchill.
            [(430, 205), (528, 205), (553, 238), (565, 255), (520, 460), (430, 460)],
        ]),
        ProvinceShape(zone: .on, polygons: [
            // Hudson Bay + James Bay west shore, the 79°W border, and the
            // Great-Lakes toe.
            [(520, 460), (565, 255), (600, 285), (622, 325), (614, 395), (636, 402),
             (668, 470), (672, 520), (640, 585), (596, 540), (608, 492), (556, 502)],
        ]),
        ProvinceShape(zone: .qc, polygons: [
            // James/Hudson Bay east shore up to Ungava, the Labrador
            // border, and the St. Lawrence shore with the Gaspé bump.
            [(640, 398), (648, 310), (628, 252), (672, 192), (706, 168), (722, 206),
             (742, 180), (778, 210), (788, 270), (760, 330), (806, 318), (792, 388),
             (848, 420), (824, 448), (750, 452), (692, 470), (668, 470), (636, 402)],
        ]),
        ProvinceShape(zone: .nl, polygons: [
            // Labrador.
            [(778, 210), (812, 150), (886, 166), (862, 252), (806, 318), (760, 330), (788, 270)],
            // Island of Newfoundland.
            [(880, 380), (930, 360), (950, 405), (905, 440), (870, 415)],
        ]),
        ProvinceShape(zone: .nb, polygons: [
            [(750, 452), (792, 452), (800, 505), (748, 505)],
        ]),
        ProvinceShape(zone: .pe, polygons: [
            [(812, 470), (846, 462), (852, 472), (816, 480)],
        ]),
        ProvinceShape(zone: .ns, polygons: [
            // Mainland peninsula + a Cape Breton nub.
            [(800, 505), (852, 492), (900, 520), (926, 504), (940, 548), (898, 570),
             (852, 540), (806, 528)],
        ]),
    ]

    /// Visual anchor per zone — used for labels and arc endpoints. The
    /// concave shapes (ON, QC, BC) need hand-placed anchors; a vertex
    /// mean would drift into the bays.
    static let anchors: [Zone: (Double, Double)] = [
        .yt: (130, 140), .nt: (295, 135), .nu: (495, 140),
        .bc: (160, 320), .ab: (272, 335), .sk: (380, 335), .mb: (472, 335),
        .on: (590, 465), .qc: (712, 330), .nl: (828, 212),
        .nb: (772, 480), .pe: (830, 471), .ns: (866, 532),
    ]

    /// Southern anchor for each zone's US-export arrow.
    static let usAnchors: [Zone: (Double, Double)] = [
        .bc: (205, 461), .mb: (472, 461), .on: (622, 560), .qc: (705, 466), .nb: (774, 505),
    ]

    static func pathString(_ shape: ProvinceShape) -> String {
        shape.polygons.map { poly in
            "M" + poly.map { "\($0.0),\($0.1)" }.joined(separator: "L") + "Z"
        }.joined()
    }

    /// Hand-placed visual anchor, falling back to the vertex mean of the
    /// main polygon.
    static func centroid(_ zone: Zone) -> (Double, Double) {
        if let a = anchors[zone] { return a }
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
