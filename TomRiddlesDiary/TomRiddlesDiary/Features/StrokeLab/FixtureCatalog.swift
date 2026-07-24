import Foundation

nonisolated enum StrokeLabSourceMode: String, CaseIterable, Identifiable, Sendable {
    case orderedVector = "Vector"
    case raster = "Raster"

    var id: Self { self }
}

nonisolated struct StrokeLabFixture: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let theme: String
    let strokes: [Polyline]
    let seed: UInt64
}

/// App-native versions of representative engineering fixtures. They are intentionally local and
/// deterministic: the lab exercises stroke mechanics without a model, API key, or network access.
nonisolated enum FixtureCatalog {
    static let canvasSize = 128

    static let fixtures: [StrokeLabFixture] = [
        StrokeLabFixture(
            id: "01_weary_flower",
            title: "Weary Flower",
            theme: "Organic hope · asymmetry",
            strokes: lines([
                [(335, 535), (329, 490), (324, 448), (318, 405), (315, 360), (319, 315), (312, 270)],
                [(312, 270), (285, 251), (266, 218), (276, 190), (305, 184), (324, 207)],
                [(324, 207), (350, 184), (381, 190), (390, 217), (374, 244), (340, 257), (312, 270)],
                [(320, 390), (353, 363), (384, 370), (360, 397), (320, 390)],
                [(317, 420), (288, 398), (269, 407), (288, 427), (317, 420)],
                [(190, 548), (275, 542), (360, 546), (450, 540)],
            ]),
            seed: 11
        ),
        StrokeLabFixture(
            id: "04_anger_cage",
            title: "Anger Cage",
            theme: "Jagged geometry · release",
            strokes: lines([
                [(250, 500), (235, 405), (247, 305), (239, 205), (250, 135)],
                [(295, 505), (286, 421), (292, 345)],
                [(292, 270), (286, 205), (294, 130)],
                [(345, 508), (350, 428), (347, 360)],
                [(348, 285), (353, 212), (348, 132)],
                [(395, 500), (408, 403), (399, 305), (410, 210), (398, 137)],
                [(196, 455), (245, 398), (217, 352), (285, 326), (253, 270), (322, 286),
                 (345, 214), (375, 278), (444, 249), (411, 325), (466, 356), (404, 397), (438, 463)],
                [(207, 115), (180, 82)],
                [(320, 101), (322, 58)],
                [(432, 116), (467, 82)],
                [(171, 285), (125, 274)],
                [(468, 292), (516, 282)],
            ]),
            seed: 29
        ),
        StrokeLabFixture(
            id: "05_crossroads_maze",
            title: "Crossroads Maze",
            theme: "Branching path · choice",
            strokes: lines([
                [(320, 575), (320, 510), (265, 470), (265, 412), (365, 412), (365, 350),
                 (225, 350), (225, 275), (420, 275), (420, 205), (305, 205), (305, 130)],
                [(320, 510), (405, 475), (455, 425), (505, 425)],
                [(265, 470), (190, 466), (145, 425), (95, 425)],
                [(145, 185), (145, 515), (495, 515)],
                [(495, 515), (495, 145), (205, 145)],
                [(205, 145), (205, 220), (430, 220)],
                [(95, 425), (75, 410), (95, 395)],
                [(505, 425), (525, 410), (505, 395)],
                [(305, 130), (290, 105), (320, 105), (305, 130)],
            ]),
            seed: 47
        ),
    ]

    static func source(for fixture: StrokeLabFixture, mode: StrokeLabSourceMode) -> StrokeSourcePayload {
        switch mode {
        case .orderedVector:
            return .ordered(fixture.strokes)
        case .raster:
            return .raster(rasterize(fixture.strokes))
        }
    }

    private static func lines(_ source: [[(Double, Double)]]) -> [Polyline] {
        source.map { points in
            Polyline(points: points.map { point in
                Point2D(x: point.0 / 5, y: point.1 / 5)
            })
        }
    }

    private static func rasterize(_ polylines: [Polyline]) -> BinaryMask {
        var mask = BinaryMask(width: canvasSize, height: canvasSize)

        for polyline in polylines {
            if let point = polyline.points.first {
                stamp(point, into: &mask)
            }
            for (start, end) in zip(polyline.points, polyline.points.dropFirst()) {
                let steps = max(1, Int(ceil(max(abs(end.x - start.x), abs(end.y - start.y)) * 2)))
                for step in 0 ... steps {
                    let fraction = Double(step) / Double(steps)
                    stamp(Point2D.interpolate(from: start, to: end, fraction: fraction), into: &mask)
                }
            }
        }

        return mask
    }

    private static func stamp(_ point: Point2D, into mask: inout BinaryMask) {
        let centerX = Int(point.x.rounded())
        let centerY = Int(point.y.rounded())

        for offsetY in -1 ... 1 {
            for offsetX in -1 ... 1 where offsetX * offsetX + offsetY * offsetY <= 2 {
                let gridPoint = GridPoint(x: centerX + offsetX, y: centerY + offsetY)
                if mask.contains(gridPoint) {
                    mask[gridPoint] = true
                }
            }
        }
    }
}
