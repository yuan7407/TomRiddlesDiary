@testable import TomRiddlesDiary
import XCTest

@MainActor
final class StrokePipelineTests: XCTestCase {
    private let pipeline = StrokePipeline()

    func testOrderedSourceBypassesRasterStagesAndPreservesEndpoints() throws {
        let ordered = [Polyline(points: [Point2D(x: 2, y: 3), Point2D(x: 12, y: 3)])]
        let configuration = HumanizerConfiguration(
            jitterAmplitude: 0,
            durationVariation: 0,
            pressureVariation: 0
        )

        let sequence = pipeline.process(.ordered(ordered), configuration: configuration)
        let stroke = try XCTUnwrap(sequence.strokes.first)

        XCTAssertEqual(stroke.samples.first?.point, Point2D(x: 2, y: 3))
        XCTAssertEqual(stroke.samples.last?.point, Point2D(x: 12, y: 3))
    }

    func testRasterSourceRunsSkeletonTraceHumanizeAndReplay() {
        let mask = MaskFixtures.mask([
            ".......",
            "..###..",
            "..###..",
            "..###..",
            "..###..",
            ".......",
        ])

        let sequence = pipeline.process(.raster(mask), seed: 11)
        let timeline = StrokeReplayTimeline(sequence: sequence)

        XCTAssertFalse(sequence.strokes.isEmpty)
        XCTAssertGreaterThan(sequence.totalDuration, 0)
        XCTAssertTrue(timeline.frame(at: timeline.totalDuration).isComplete)
    }

    func testWholePipelineIsDeterministicForSameSeed() {
        let mask = MaskFixtures.mask([
            ".....",
            ".###.",
            "..#..",
            "..#..",
            ".....",
        ])

        XCTAssertEqual(
            pipeline.process(.raster(mask), seed: 123),
            pipeline.process(.raster(mask), seed: 123)
        )
    }
}
