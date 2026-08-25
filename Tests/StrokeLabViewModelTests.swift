//
//  StrokeLabViewModelTests.swift
//  模块：Tests（StrokeLab 状态与重播生命周期）
//
//  文件职责：验证重播会自行收尾、切夹具会取消旧重播、连点重播不会被旧任务清状态。
//
//  设计原因：这三条都是曾真实出现过的缺陷（60 Hz 永不停止、过期任务误清状态），
//  因此按行为而非实现细节固化为回归测试。
//

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
