//
//  StrokeReplayTimelineTests.swift
//  模块：Tests（重播时间轴）
//
//  文件职责：验证严格串行——后面的笔在前一笔完成前进度必须为 0，并覆盖零时长与异常时间。
//
//  设计原因：串行是“像真人逐笔作画”的核心观感，一旦多笔同时生长，魔法感立刻消失。
//

@testable import TomRiddlesDiary
import XCTest

@MainActor
final class StrokeReplayTimelineTests: XCTestCase {
    func testEmptySequenceIsImmediatelyComplete() {
        let timeline = StrokeReplayTimeline(sequence: StrokeSequence(strokes: []))

        XCTAssertEqual(timeline.totalDuration, 0)
        XCTAssertEqual(timeline.frame(at: 0), ReplayFrame(progressByStroke: []))
        XCTAssertTrue(timeline.frame(at: 0).isComplete)
    }

    func testBeforeStartAllStrokesAreHidden() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.frame(at: -1).progressByStroke, [0, 0])
    }

    func testMidpointAdvancesOnlyFirstStroke() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.frame(at: 1).progressByStroke, [0.5, 0])
        XCTAssertEqual(timeline.frame(at: 1).activeStrokeIndex, 0)
    }

    func testExactBoundaryCompletesPreviousWithoutStartingNext() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.frame(at: 2).progressByStroke, [1, 0])
    }

    func testSecondStrokeStartsAfterFirstCompletes() {
        let timeline = makeTimeline()
        XCTAssertEqual(timeline.frame(at: 2.5).progressByStroke, [1, 0.5])
        XCTAssertEqual(timeline.frame(at: 2.5).activeStrokeIndex, 1)
    }

    func testEndAndLaterFramesAreComplete() {
        let timeline = makeTimeline()

        XCTAssertEqual(timeline.frame(at: 3).progressByStroke, [1, 1])
        XCTAssertEqual(timeline.frame(at: 30).progressByStroke, [1, 1])
        XCTAssertTrue(timeline.frame(at: 3).isComplete)
    }

    func testStartTimesAndTotalDurationAreSequential() {
        let timeline = makeTimeline()

        XCTAssertEqual(timeline.startTime(forStrokeAt: 0), 0)
        XCTAssertEqual(timeline.startTime(forStrokeAt: 1), 2)
        XCTAssertEqual(timeline.totalDuration, 3)
    }

    func testZeroDurationStrokeCompletesWithoutDivisionByZero() {
        let stroke = TimedStroke(samples: [], duration: 0)
        let timeline = StrokeReplayTimeline(sequence: StrokeSequence(strokes: [stroke]))

        XCTAssertEqual(timeline.frame(at: 0).progressByStroke, [1])
        XCTAssertTrue(timeline.frame(at: 0).isComplete)
    }

    private func makeTimeline() -> StrokeReplayTimeline {
        let first = TimedStroke(samples: [StrokeSample(point: Point2D(x: 0, y: 0), pressure: 0.5)], duration: 2)
        let second = TimedStroke(samples: [StrokeSample(point: Point2D(x: 1, y: 1), pressure: 0.5)], duration: 1)
        return StrokeReplayTimeline(sequence: StrokeSequence(strokes: [first, second]))
    }
}
