@testable import TomRiddlesDiary
import XCTest

@MainActor
final class StrokeLabViewModelTests: XCTestCase {
    func testReplayStopsAnimationScheduleAfterSequenceCompletes() async throws {
        let model = makeModel()

        model.replay()
        XCTAssertNotNil(model.replayStartedAt)

        let delay = model.sequence.totalDuration + 0.2
        try await Task<Never, Never>.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        XCTAssertNil(model.replayStartedAt)
        XCTAssertTrue(
            StrokeReplayTimeline(sequence: model.sequence)
                .frame(at: model.sequence.totalDuration)
                .isComplete
        )
    }

    func testChangingSourceCancelsActiveReplay() {
        let model = makeModel()
        model.replay()

        model.sourceMode = .raster

        XCTAssertNil(model.replayStartedAt)
    }

    func testChangingFixtureCancelsActiveReplay() {
        let model = makeModel()
        model.replay()

        model.selectedFixtureID = model.fixtures[1].id

        XCTAssertNil(model.replayStartedAt)
    }

    func testRestartedReplayIgnoresFirstCompletion() async throws {
        let model = makeModel()
        let duration = model.sequence.totalDuration

        model.replay()
        try await sleep(seconds: duration * 0.65)
        model.replay()
        try await sleep(seconds: duration * 0.65)

        XCTAssertNotNil(model.replayStartedAt)

        try await sleep(seconds: duration * 0.5)
        XCTAssertNil(model.replayStartedAt)
    }

    private func sleep(seconds: TimeInterval) async throws {
        try await Task<Never, Never>.sleep(
            nanoseconds: UInt64(seconds * 1_000_000_000)
        )
    }

    private func makeModel() -> StrokeLabViewModel {
        StrokeLabViewModel(fixtures: [
            StrokeLabFixture(
                id: "test_fixture_one",
                title: "Test Fixture One",
                theme: "Test",
                strokes: [Polyline(points: [
                    Point2D(x: 4, y: 4),
                    Point2D(x: 76, y: 4),
                ])],
                seed: 1
            ),
            StrokeLabFixture(
                id: "test_fixture_two",
                title: "Test Fixture Two",
                theme: "Test",
                strokes: [Polyline(points: [
                    Point2D(x: 4, y: 4),
                    Point2D(x: 4, y: 76),
                ])],
                seed: 2
            ),
        ])
    }
}
