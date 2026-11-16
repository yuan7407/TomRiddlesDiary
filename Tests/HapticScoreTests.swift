//
//  HapticScoreTests.swift
//  所属：测试（StrokeEngine 的触感乐谱）
//
//  这些测试守什么：乐谱的时刻必须和笔画时间轴一致（否则手上的顿和屏幕上的落笔对不上）；
//  停顿里没有任何触感；从半中间开始要乐谱时，过去的笔不出现、时间从 0 重新算。
//  「强度合不合适」机器判断不了，只能真机上用手试。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class HapticScoreTests: XCTestCase {
    private let configuration = HapticScoreConfiguration(
        tapIntensity: 0.2 ... 0.6,
        tapSharpness: 0.5,
        dragIntensity: 0.05 ... 0.25,
        dragSharpness: 0.2,
        shortestDrag: 0.15
    )

    private func stroke(duration: TimeInterval, pause: TimeInterval, pressure: Double = 0.5) -> TimedStroke {
        TimedStroke(
            samples: [
                StrokeSample(point: Point2D(x: 0, y: 0), pressure: pressure),
                StrokeSample(point: Point2D(x: 10, y: 0), pressure: pressure),
            ],
            duration: duration,
            pauseBefore: pause
        )
    }

    func testEachStrokeTapsWhenItLandsAndDragsWhileItRuns() {
        let sequence = StrokeSequence(strokes: [stroke(duration: 0.4, pause: 0), stroke(duration: 0.6, pause: 0.5)])
        let beats = HapticScore.beats(for: sequence, configuration: configuration)
        XCTAssertEqual(beats.map(\.kind), [.tap, .drag, .tap, .drag])
        XCTAssertEqual(beats[0].time, 0, accuracy: 1e-12)
        XCTAssertEqual(beats[1].duration, 0.4, accuracy: 1e-12)
        XCTAssertEqual(beats[2].time, 0.9, accuracy: 1e-12, "第二笔在第一笔写完再停 0.5 秒后落下")
        let lastEnd = beats[3].time + beats[3].duration
        XCTAssertEqual(lastEnd, sequence.totalDuration, accuracy: 1e-12, "最后一下结束的时刻要和整段时长对得上")
    }

    func testNothingIsFeltDuringPauses() {
        let sequence = StrokeSequence(strokes: [stroke(duration: 0.4, pause: 0), stroke(duration: 0.6, pause: 0.5)])
        let beats = HapticScore.beats(for: sequence, configuration: configuration)
        for beat in beats {
            let overlapsPause = beat.time < 0.9 && beat.time + beat.duration > 0.4
            XCTAssertFalse(overlapsPause, "0.4…0.9 秒是抬笔停顿，手上应该是空的")
        }
    }

    func testVeryShortStrokesOnlyTap() {
        let beats = HapticScore.beats(for: StrokeSequence(strokes: [stroke(duration: 0.1, pause: 0)]), configuration: configuration)
        XCTAssertEqual(beats.map(\.kind), [.tap])
    }

    func testHeavierStrokesFeelStronger() {
        let light = HapticScore.beats(for: StrokeSequence(strokes: [stroke(duration: 0.4, pause: 0, pressure: 0.1)]), configuration: configuration)
        let heavy = HapticScore.beats(for: StrokeSequence(strokes: [stroke(duration: 0.4, pause: 0, pressure: 0.9)]), configuration: configuration)
        XCTAssertLessThan(light[0].intensity, heavy[0].intensity)
        XCTAssertLessThan(light[1].intensity, heavy[1].intensity)
        for beat in light + heavy {
            XCTAssertTrue((0 ... 1).contains(beat.intensity))
        }
    }

    func testStartingPartWayDropsThePastAndRebasesTime() {
        let sequence = StrokeSequence(strokes: [stroke(duration: 0.4, pause: 0), stroke(duration: 0.6, pause: 0.5)])
        // 第 1.1 秒：第一笔早写完了，第二笔（0.9…1.5）写到一半。
        let beats = HapticScore.beats(for: sequence, startingAt: 1.1, configuration: configuration)
        XCTAssertEqual(beats.map(\.kind), [.drag], "写到一半的那一笔不再补落笔的那一下，只剩行笔")
        XCTAssertEqual(beats[0].time, 0, accuracy: 1e-12)
        XCTAssertEqual(beats[0].duration, 0.4, accuracy: 1e-12)
        XCTAssertTrue(HapticScore.beats(for: sequence, startingAt: 9, configuration: configuration).isEmpty, "全写完了就什么都没有")
    }

    func testShippedSettingsAreUsable() {
        let beats = HapticScore.beats(for: StrokeSequence(strokes: [stroke(duration: 0.4, pause: 0)]), configuration: BookFeel.haptics)
        XCTAssertEqual(beats.count, 2)
    }
}
