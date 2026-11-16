//
//  InkAgeTests.swift
//  测试目标：StrokeEngine 的 InkDrying / InkAgeTimeline（墨的年纪），以及 Configuration 的 InkTone（墨色混合）。
//
//  为什么这样测：墨的年纪只影响颜色，错了不会有任何报错，只是「刚写的字看起来是干的」。
//  所以把几个不变量钉住：刚落下最湿、到点干透、越老越干、被打断后继续变干。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class InkAgeTests: XCTestCase {
    private let drying = InkDrying(dryingTime: 2, curveExponent: 1.5)

    private func stroke(duration: TimeInterval, pause: TimeInterval) -> TimedStroke {
        TimedStroke(
            samples: [
                StrokeSample(point: Point2D(x: 0, y: 0), pressure: 0.5),
                StrokeSample(point: Point2D(x: 10, y: 0), pressure: 0.5),
            ],
            duration: duration,
            pauseBefore: pause
        )
    }

    func testFreshInkIsFullyWetAndOldInkIsDry() {
        XCTAssertEqual(drying.wetness(age: 0), 1)
        XCTAssertEqual(drying.wetness(age: -3), 1, "还没写下去的按刚落下算")
        XCTAssertEqual(drying.wetness(age: 2), 0)
        XCTAssertEqual(drying.wetness(age: 50), 0)
        XCTAssertEqual(drying.wetness(age: .nan), 0)
    }

    func testInkOnlyEverGetsDrier() {
        var previous = 1.0
        for step in 1 ... 100 {
            let wetness = drying.wetness(age: 2.5 * Double(step) / 100)
            XCTAssertLessThanOrEqual(wetness, previous)
            XCTAssertGreaterThanOrEqual(wetness, 0)
            previous = wetness
        }
    }

    func testTimelineStartsEachStrokeAfterItsPause() {
        let sequence = StrokeSequence(strokes: [stroke(duration: 1, pause: 0), stroke(duration: 2, pause: 0.5)])
        let timeline = InkAgeTimeline(sequence: sequence)
        XCTAssertEqual(timeline.inkStartTimes, [0, 1.5])
        XCTAssertEqual(
            (timeline.inkStartTimes.last ?? 0) + (timeline.durations.last ?? 0),
            sequence.totalDuration,
            accuracy: 1e-12,
            "最后一笔写完的时刻要和整段时长对得上"
        )
    }

    func testTheStartOfAStrokeIsOlderThanItsEnd() {
        let timeline = InkAgeTimeline(sequence: StrokeSequence(strokes: [stroke(duration: 1, pause: 0), stroke(duration: 2, pause: 0.5)]))
        let head = timeline.age(ofStroke: 1, fraction: 0, secondsSinceStart: 3)
        let tail = timeline.age(ofStroke: 1, fraction: 1, secondsSinceStart: 3)
        XCTAssertEqual(head, 1.5, accuracy: 1e-12)
        XCTAssertEqual(tail, -0.5, accuracy: 1e-12, "还没写到的那一头年纪是负的")
        XCTAssertGreaterThan(head, tail)
        XCTAssertEqual(timeline.age(ofStroke: 9, fraction: 0, secondsSinceStart: 3), 0, "越界不崩，当作刚落下")
    }

    func testInkKeepsDryingOnTheWallClock() {
        let timeline = InkAgeTimeline(sequence: StrokeSequence(strokes: [stroke(duration: 1, pause: 0)]))
        let justWritten = drying.wetness(age: timeline.age(ofStroke: 0, fraction: 1, secondsSinceStart: 1))
        let later = drying.wetness(age: timeline.age(ofStroke: 0, fraction: 1, secondsSinceStart: 4))
        XCTAssertEqual(justWritten, 1)
        XCTAssertEqual(later, 0, "写完三秒后应该干透，不管播放有没有被打断")
    }

    func testMixingInkTonesInterpolatesEachChannelAndClamps() {
        let dry = InkTone(red: 0.1, green: 0.2, blue: 0.3)
        let wet = InkTone(red: 0.3, green: 0.0, blue: 0.7)
        XCTAssertEqual(dry.mixed(with: wet, fraction: 0), dry)
        XCTAssertEqual(dry.mixed(with: wet, fraction: 1), wet)
        let half = dry.mixed(with: wet, fraction: 0.5)
        XCTAssertEqual(half.red, 0.2, accuracy: 1e-12)
        XCTAssertEqual(half.green, 0.1, accuracy: 1e-12)
        XCTAssertEqual(half.blue, 0.5, accuracy: 1e-12)
        XCTAssertEqual(dry.mixed(with: wet, fraction: 7), wet)
        XCTAssertEqual(dry.mixed(with: wet, fraction: .nan), dry)
    }

    func testShippedDryingSettingsAreUsable() {
        XCTAssertEqual(BookFeel.inkDrying.wetness(age: 0), 1)
        XCTAssertEqual(BookFeel.inkDrying.wetness(age: BookFeel.inkDrying.dryingTime), 0)
    }
}
