@testable import TomRiddlesDiary
import XCTest

@MainActor
final class StrokeTracerTests: XCTestCase {
    private let tracer = StrokeTracer()

    func testEmptyMaskProducesNoStrokes() {
        XCTAssertEqual(tracer.trace(BinaryMask(width: 5, height: 5)), [])
    }

    func testStraightLineIsOrderedEndpointToEndpoint() {
        let mask = MaskFixtures.mask([
            ".......",
            ".#####.",
            ".......",
        ])

        let strokes = tracer.trace(mask)

        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(strokes[0].points, [
            Point2D(x: 1, y: 1),
            Point2D(x: 2, y: 1),
            Point2D(x: 3, y: 1),
            Point2D(x: 4, y: 1),
            Point2D(x: 5, y: 1),
        ])
    }

    func testIsolatedPixelIsPreservedAsDotStroke() {
        let mask = MaskFixtures.mask([
            "...",
            ".#.",
            "...",
        ])

        XCTAssertEqual(tracer.trace(mask), [
            Polyline(points: [Point2D(x: 1, y: 1)]),
        ])
    }

    func testBranchGraphEmitsEveryEdgeExactlyOnce() {
        let mask = MaskFixtures.mask([
            ".......",
            "...#...",
            "...#...",
            ".#####.",
            "...#...",
            "...#...",
            ".......",
        ])

        assertExactEdgeCoverage(mask: mask, strokes: tracer.trace(mask))
    }

    func testClosedDegreeTwoCycleUsesDeterministicFallback() {
        let mask = MaskFixtures.mask([
            ".....",
            "..#..",
            ".#.#.",
            "..#..",
            ".....",
        ])

        let strokes = tracer.trace(mask)

        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(strokes[0].points.first, strokes[0].points.last)
        assertExactEdgeCoverage(mask: mask, strokes: strokes)
    }

    func testDisconnectedComponentsHaveStableTopToBottomOrder() {
        let mask = MaskFixtures.mask([
            ".......",
            ".###...",
            ".......",
            ".......",
            "...###.",
            ".......",
        ])

        let strokes = tracer.trace(mask)

        XCTAssertEqual(strokes.count, 2)
        XCTAssertEqual(strokes[0].points.first, Point2D(x: 1, y: 1))
        XCTAssertEqual(strokes[1].points.first, Point2D(x: 3, y: 4))
    }

    func testDiagonalPixelsUseEightConnectivity() {
        let mask = MaskFixtures.mask([
            "#..",
            ".#.",
            "..#",
        ])

        XCTAssertEqual(tracer.trace(mask), [
            Polyline(points: [
                Point2D(x: 0, y: 0),
                Point2D(x: 1, y: 1),
                Point2D(x: 2, y: 2),
            ]),
        ])
    }

    func testRepeatedTracingIsDeterministic() {
        let mask = MaskFixtures.mask([
            ".......",
            "..###..",
            "...#...",
            ".###...",
            ".......",
        ])

        XCTAssertEqual(tracer.trace(mask), tracer.trace(mask))
    }

    private func assertExactEdgeCoverage(mask: BinaryMask, strokes: [Polyline], file: StaticString = #filePath, line: UInt = #line) {
        let expected = graphEdges(in: mask)
        let emitted = strokes.flatMap { stroke in
            zip(stroke.points, stroke.points.dropFirst()).map { pair in
                TestEdge(gridPoint(pair.0), gridPoint(pair.1))
            }
        }

        XCTAssertEqual(Set(emitted), expected, file: file, line: line)
        XCTAssertEqual(emitted.count, expected.count, "An edge was emitted more than once", file: file, line: line)
    }

    private func graphEdges(in mask: BinaryMask) -> Set<TestEdge> {
        let foreground = Set(mask.foregroundPoints)
        var edges: Set<TestEdge> = []
        for point in foreground {
            for dy in -1 ... 1 {
                for dx in -1 ... 1 where dx != 0 || dy != 0 {
                    let neighbor = GridPoint(x: point.x + dx, y: point.y + dy)
                    if foreground.contains(neighbor) {
                        edges.insert(TestEdge(point, neighbor))
                    }
                }
            }
        }
        return edges
    }

    private func gridPoint(_ point: Point2D) -> GridPoint {
        GridPoint(x: Int(point.x), y: Int(point.y))
    }
}

nonisolated private struct TestEdge: Hashable {
    let first: GridPoint
    let second: GridPoint

    init(_ lhs: GridPoint, _ rhs: GridPoint) {
        if lhs < rhs {
            first = lhs
            second = rhs
        } else {
            first = rhs
            second = lhs
        }
    }
}
