//
//  StrokeTimingTests.swift
//  模块：Tests（笔内加减速 A3、笔间抬笔移动 A4）
//
//  文件职责：验证「一笔怎么起怎么收」和「两笔之间隔多久」。
//
//  为什么这两件事值得测：
//  它们都是时间上的性质，在静态截图上完全看不出来，只有盯着屏幕看重播才有感觉，
//  而「感觉」没法进 CI。所以断言的是可量化的替代指标——
//  A3：曲线两端必须走得慢（起笔从静止开始、收笔停在静止），中点必须对称；
//  A4：间隔必须随抬笔距离变长，且第一笔没有间隔。
//
//  另外守住一条很容易悄悄坏掉的性质：`frame(at: totalDuration)` 必须精确画完。
//  A4 把时间轴的累加拆成了「抬笔 + 落墨」两段，如果累加顺序与 `totalDuration`
//  不一致，笔数多了以后最后一笔会差一个浮点尾数画不完——线尾少一小截，
//  没有任何报错。这个问题当时确实发生了。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class StrokeTimingTests: XCTestCase {
    // MARK: A3 起笔加速、收笔减速

    func testEasingHitsBothEndsExactly() {
        XCTAssertEqual(StrokeEasing.progress(0), 0)
        XCTAssertEqual(StrokeEasing.progress(1), 1, accuracy: 1e-12)
    }

    /// 中点对称：加速用掉的时间和减速一样多。
    func testEasingIsSymmetricAtTheMidpoint() {
        XCTAssertEqual(StrokeEasing.progress(0.5), 0.5, accuracy: 1e-12)

        for t in [0.1, 0.25, 0.4] {
            XCTAssertEqual(
                StrokeEasing.progress(t) + StrokeEasing.progress(1 - t),
                1,
                accuracy: 1e-12,
                "曲线应关于中点对称"
            )
        }
    }

    /// 核心用例：两端必须走得比匀速慢很多，这就是「从静止开始、到静止结束」。
    /// 如果谁把缓动去掉换成线性，这条会立刻红。
    func testEasingStartsAndEndsFromRest() {
        // 时间过了 10%，线只该画出很小一截。线性的话正好是 10%。
        XCTAssertLessThan(StrokeEasing.progress(0.1), 0.02, "起笔应该是从静止加速")
        // 时间还剩 10% 时，线应该已经画掉九成九。
        XCTAssertGreaterThan(StrokeEasing.progress(0.9), 0.98, "收笔应该减速到静止")
    }

    func testEasingIsMonotonic() {
        var previous = -1.0
        for step in 0 ... 100 {
            let value = StrokeEasing.progress(Double(step) / 100)
            XCTAssertGreaterThanOrEqual(value, previous, "笔尖不许倒退")
            previous = value
        }
    }

    /// 非有限值来自上游时钟异常，必须当成「还没开始」而不是把 NaN 传下去。
    func testEasingRejectsNonFiniteInput() {
        XCTAssertEqual(StrokeEasing.progress(.nan), 0)
        XCTAssertEqual(StrokeEasing.progress(.infinity), 0)
    }

    /// 缓动必须真的接进时间轴，而不是只存在于那个函数里。
    func testTimelineAppliesEasingWithinAStroke() {
        let timeline = StrokeReplayTimeline(sequence: StrokeSequence(strokes: [
            TimedStroke(samples: [], duration: 10),
        ]))

        // 时间过半时进度也应该过半（对称点），但四分之一处必须明显小于 0.25。
        XCTAssertEqual(timeline.frame(at: 5).progressByStroke[0], 0.5, accuracy: 1e-9)
        XCTAssertLessThan(timeline.frame(at: 2.5).progressByStroke[0], 0.2, "笔内不该再是匀速")
    }

    // MARK: A4 笔间抬笔移动

    private func makeStroke(from origin: Point2D, to end: Point2D) -> Polyline {
        Polyline(points: [origin, end])
    }

    /// 抬笔移动的时间必须随距离变长：同一个字里挨着的两笔间隔短，
    /// 跨到下一个字的跳跃间隔长。固定秒数做不到这件事。
    func testPauseGrowsWithTheDistanceThePenTravels() throws {
        let configuration = HumanizerConfiguration.testBaseline(
            inkLengthPerSecond: 100,
            penLiftDuration: 0.02
        )

        func pause(jump: Double) throws -> TimeInterval {
            let sequence = StrokeHumanizer().humanize(
                [
                    makeStroke(from: Point2D(x: 0, y: 0), to: Point2D(x: 10, y: 0)),
                    makeStroke(from: Point2D(x: 10 + jump, y: 0), to: Point2D(x: 20 + jump, y: 0)),
                ],
                configuration: configuration,
                seed: 7
            )
            return try XCTUnwrap(sequence.strokes.last).pauseBefore
        }

        let near = try pause(jump: 5)
        let far = try pause(jump: 200)

        XCTAssertGreaterThan(near, 0, "两笔之间必须有抬笔移动的时间")
        XCTAssertGreaterThan(far, near * 2, "跳得远，抬笔移动就该明显更久")
    }

    /// 第一笔前面没有笔，所以没有抬笔移动。
    func testFirstStrokeHasNoPause() throws {
        let sequence = StrokeHumanizer().humanize(
            [makeStroke(from: Point2D(x: 0, y: 0), to: Point2D(x: 10, y: 0))],
            configuration: .testBaseline(penLiftDuration: 0.5),
            seed: 7
        )

        XCTAssertEqual(try XCTUnwrap(sequence.strokes.first).pauseBefore, 0)
    }

    /// 总时长必须把抬笔移动算进去，否则重播会在最后几笔还没画完时就「结束」。
    func testTotalDurationIncludesThePauses() {
        let sequence = StrokeSequence(strokes: [
            TimedStroke(samples: [], duration: 1, pauseBefore: 0),
            TimedStroke(samples: [], duration: 2, pauseBefore: 0.5),
        ])

        XCTAssertEqual(sequence.totalDuration, 3.5, accuracy: 1e-12)
    }

    /// 抬笔移动期间，那一笔还没落墨；前面的笔已经画完。
    func testNothingIsDrawnWhileThePenIsInTheAir() {
        let timeline = StrokeReplayTimeline(sequence: StrokeSequence(strokes: [
            TimedStroke(samples: [], duration: 1, pauseBefore: 0),
            TimedStroke(samples: [], duration: 1, pauseBefore: 1),
        ]))

        // 第一笔 0…1 落墨，然后 1…2 是抬笔移动，第二笔 2…3 落墨。
        let inTheAir = timeline.frame(at: 1.5).progressByStroke
        XCTAssertEqual(inTheAir[0], 1, "前一笔已经写完")
        XCTAssertEqual(inTheAir[1], 0, "笔还在空中，第二笔不该露头")
        XCTAssertNil(timeline.frame(at: 1.5).activeStrokeIndex, "空中阶段没有正在生长的笔")
    }

    func testStartTimeCountsThePauseBeforeTheStroke() {
        let timeline = StrokeReplayTimeline(sequence: StrokeSequence(strokes: [
            TimedStroke(samples: [], duration: 1, pauseBefore: 0),
            TimedStroke(samples: [], duration: 1, pauseBefore: 0.5),
            TimedStroke(samples: [], duration: 1, pauseBefore: 0.25),
        ]))

        XCTAssertEqual(timeline.startTime(forStrokeAt: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(timeline.startTime(forStrokeAt: 1), 1.5, accuracy: 1e-12, "1 落墨 + 0.5 抬笔")
        XCTAssertEqual(timeline.startTime(forStrokeAt: 2), 2.75, accuracy: 1e-12)
    }

    /// 回归守卫：笔数很多时，`frame(at: totalDuration)` 仍必须精确画完。
    ///
    /// A4 把时间轴拆成「抬笔 + 落墨」两段之后，如果累加顺序和 `totalDuration` 不一致，
    /// 浮点尾数会累积，最后一笔差一点点画不完——线尾少一小截，没有任何报错。
    /// 2026-08-29 这个问题真的发生过，被端到端用例抓到。
    func testLongSequenceCompletesExactlyAtTotalDuration() {
        let sequence = StrokeHumanizer().humanize(
            (0 ..< 60).map { index in
                let x = Double(index) * 7.3
                return Polyline(points: [Point2D(x: x, y: 0), Point2D(x: x + 5.7, y: 3.1)])
            },
            configuration: .testBaseline(
                jitterAmplitude: 0.4,
                durationVariation: 0.08,
                penLiftDuration: 0.031
            ),
            seed: 11
        )
        let timeline = StrokeReplayTimeline(sequence: sequence)

        XCTAssertEqual(sequence.strokes.count, 60)
        XCTAssertTrue(
            timeline.frame(at: sequence.totalDuration).isComplete,
            "到总时长时每一笔都必须画完，一个浮点尾数都不许差"
        )
    }
}
