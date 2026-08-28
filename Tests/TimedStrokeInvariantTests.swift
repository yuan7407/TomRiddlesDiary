//
//  TimedStrokeInvariantTests.swift
//  模块：Tests（类型不变量与单位换算）
//
//  文件职责：验证 `TimedStroke` 的时长不变量真的生效，以及 `Duration → 秒` 换算正确。
//
//  设计原因：
//  计划 D3 把「时长非负」这条不变量从三处消费方的 `max(0, ...)` 挪进了构造校验。
//  挪动之后必须证明两件事：合法值照常通过，且消费方不再需要自己兜。
//  违规值会触发 `precondition` 直接崩溃，XCTest 无法捕获，因此这里不测崩溃路径——
//  那是刻意的设计（负时长没有可见症状，只能靠崩在产生它的地方来定位），
//  用注释记录取舍，而不是为了凑一个测试去把不变量改成静默夹取。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class TimedStrokeInvariantTests: XCTestCase {
    func testZeroAndPositiveDurationsAreAccepted() {
        XCTAssertEqual(TimedStroke(samples: [], duration: 0).duration, 0)
        XCTAssertEqual(TimedStroke(samples: [], duration: 1.5).duration, 1.5)
    }

    /// 总时长是各笔时长的直接累加。不变量已保证非负，消费方无需再夹。
    func testTotalDurationSumsWithoutDefensiveClamping() {
        let sequence = StrokeSequence(strokes: [
            TimedStroke(samples: [], duration: 0.5),
            TimedStroke(samples: [], duration: 0),
            TimedStroke(samples: [], duration: 2),
        ])

        XCTAssertEqual(sequence.totalDuration, 2.5, accuracy: 1e-12)
    }

    /// 起笔时刻同样只是前缀累加。
    func testStartTimesArePrefixSums() {
        let timeline = StrokeReplayTimeline(sequence: StrokeSequence(strokes: [
            TimedStroke(samples: [], duration: 0.5),
            TimedStroke(samples: [], duration: 1.5),
            TimedStroke(samples: [], duration: 1),
        ]))

        XCTAssertEqual(timeline.startTime(forStrokeAt: 0), 0)
        XCTAssertEqual(timeline.startTime(forStrokeAt: 1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(timeline.startTime(forStrokeAt: 2), 2, accuracy: 1e-12)
    }

    // MARK: 单调时钟的秒数换算（计划 D4）

    func testDurationConvertsToSeconds() {
        XCTAssertEqual(Duration.seconds(0).inSeconds, 0)
        XCTAssertEqual(Duration.seconds(3).inSeconds, 3, accuracy: 1e-12)
        XCTAssertEqual(Duration.milliseconds(250).inSeconds, 0.25, accuracy: 1e-9)
        XCTAssertEqual(Duration.milliseconds(1_500).inSeconds, 1.5, accuracy: 1e-9)
    }

    /// 单调时钟不会倒退：先后取两个时刻，差值必须非负。
    /// 这正是弃用 `Date` 的理由——墙上时钟在系统校正时间时可能给出负差值。
    func testContinuousClockDoesNotGoBackwards() {
        let clock = ContinuousClock()
        let first = clock.now
        let second = clock.now

        XCTAssertGreaterThanOrEqual((second - first).inSeconds, 0)
    }
}
