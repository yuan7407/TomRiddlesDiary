//
//  StrokeGrowthTests.swift
//  模块：Tests（逐笔生长的几何）
//
//  文件职责：验证一笔在各个进度下画到哪里，尤其是「正在生长的半条线段」。
//
//  设计原因：
//  这段几何原先是 `StrokeCanvasView` 的私有方法，从来没有被测过——而它恰好是
//  逐笔生长观感的核心，也是几处视觉缺陷的所在。它有若干容易写错的边界：
//  向下取整的分段计数、进度恰好落在采样点上、进度为 1、进度越界。
//  提到 `StrokeGrowth`（计划 D4/D6）之后这些边界终于可以断言。
//

@testable import TomRiddlesDiary
import XCTest

nonisolated final class StrokeGrowthTests: XCTestCase {
    /// 四个采样点、三段线段，压感从 0.2 线性升到 0.8，便于验证插值。
    private func makeStroke() -> TimedStroke {
        TimedStroke(
            samples: [
                StrokeSample(point: Point2D(x: 0, y: 0), pressure: 0.2),
                StrokeSample(point: Point2D(x: 10, y: 0), pressure: 0.4),
                StrokeSample(point: Point2D(x: 20, y: 0), pressure: 0.6),
                StrokeSample(point: Point2D(x: 30, y: 0), pressure: 0.8),
            ],
            duration: 1
        )
    }

    func testNothingIsDrawnBeforeThePenTouchesDown() {
        XCTAssertNil(StrokeGrowth.partial(of: makeStroke(), progress: 0))
        XCTAssertNil(StrokeGrowth.partial(of: makeStroke(), progress: -1))
    }

    func testEmptyStrokeDrawsNothing() {
        let empty = TimedStroke(samples: [], duration: 0)
        XCTAssertNil(StrokeGrowth.partial(of: empty, progress: 0.5))
        XCTAssertNil(StrokeGrowth.partial(of: empty, progress: 1))
    }

    /// 单采样点的笔是墨点，不是线。引擎直接说出这件事，渲染层不必自己数采样点。
    func testSingleSampleStrokeIsReportedAsADot() throws {
        let sample = StrokeSample(point: Point2D(x: 5, y: 5), pressure: 0.5)
        let dot = TimedStroke(samples: [sample], duration: 0.2)

        guard case .dot(let reported, _) = try XCTUnwrap(StrokeGrowth.partial(of: dot, progress: 0.5)) else {
            return XCTFail("单采样点的笔应该被报成墨点")
        }
        XCTAssertEqual(reported, sample)
    }

    // MARK: A7 墨点生长

    /// 核心用例：墨点必须**长出来**，不能一出现就是全尺寸。
    /// 这条防的正是 A7 修掉的那个自相矛盾——别的笔都在长，只有点是啪一下出现的。
    func testDotGrowsFromNothingToFullSize() {
        XCTAssertEqual(StrokeGrowth.dotSizeFraction(progress: 0), 0)
        XCTAssertEqual(StrokeGrowth.dotSizeFraction(progress: 1), 1, accuracy: 1e-12)

        var previous = -1.0
        for step in 0 ... 50 {
            let fraction = StrokeGrowth.dotSizeFraction(progress: Double(step) / 50)
            XCTAssertGreaterThanOrEqual(fraction, previous, "墨点不该缩回去")
            XCTAssertTrue((0 ... 1).contains(fraction))
            previous = fraction
        }
    }

    /// 直径按时间的平方根长：墨量随时间线性增加，而面积与直径的平方成正比。
    /// 所以时间过了四分之一，直径应该已经到一半——先猛地洇开，再慢慢定住。
    func testDotDiameterFollowsTheSquareRootOfTime() {
        XCTAssertEqual(StrokeGrowth.dotSizeFraction(progress: 0.25), 0.5, accuracy: 1e-12)
        XCTAssertGreaterThan(
            StrokeGrowth.dotSizeFraction(progress: 0.1),
            0.1,
            "线性增长看起来是气球在放大，不是墨在洇开"
        )
    }

    /// 异常输入两条路径必须一致：线段那侧 `min(1, progress)` 把无穷大当画完，
    /// 墨点这侧也必须如此。NaN 则一律当成「还没开始」——它参与比较全是 false，
    /// 不单独挡掉的话夹取会静默返回 1，墨点凭空全尺寸出现。
    func testDotSizeHandlesNonFiniteProgressTheSameWayAsSegments() {
        XCTAssertEqual(StrokeGrowth.dotSizeFraction(progress: .nan), 0)
        XCTAssertEqual(StrokeGrowth.dotSizeFraction(progress: .infinity), 1, "无穷大按画完处理")
        XCTAssertEqual(StrokeGrowth.dotSizeFraction(progress: -5), 0)
    }

    func testMidSegmentProducesAnInterpolatedGrowingTip() throws {
        // 三段线段，进度 0.5 → 段进度 1.5，即第一段画完，第二段画了一半。
        guard case .line(let completeSegmentCount, let growingTip) =
            try XCTUnwrap(StrokeGrowth.partial(of: makeStroke(), progress: 0.5))
        else { return XCTFail("多采样点的笔应该被报成线") }

        XCTAssertEqual(completeSegmentCount, 1)

        let tip = try XCTUnwrap(growingTip)
        XCTAssertEqual(tip.point, Point2D(x: 15, y: 0))
        // 压感必须一起插值，否则笔尖粗细会一格一格跳。
        XCTAssertEqual(tip.pressure, 0.5, accuracy: 1e-12)
    }

    func testProgressLandingExactlyOnASampleHasNoGrowingTip() throws {
        // 段进度恰好为 1，第一段刚画完，还没开始第二段。
        XCTAssertEqual(
            try XCTUnwrap(StrokeGrowth.partial(of: makeStroke(), progress: 1.0 / 3.0)),
            .line(completeSegmentCount: 1, growingTip: nil),
            "恰好落在采样点上时不该再多画半段"
        )
    }

    func testFullProgressDrawsEveryCompleteSegmentAndNoTip() throws {
        XCTAssertEqual(
            try XCTUnwrap(StrokeGrowth.partial(of: makeStroke(), progress: 1)),
            .line(completeSegmentCount: 3, growingTip: nil),
            "三段线段应全部画完，且没有多出来的半段"
        )
    }

    func testProgressAboveOneIsTreatedAsComplete() throws {
        let clamped = try XCTUnwrap(StrokeGrowth.partial(of: makeStroke(), progress: 7))
        let exact = try XCTUnwrap(StrokeGrowth.partial(of: makeStroke(), progress: 1))

        XCTAssertEqual(clamped, exact, "进度越界必须按画完处理，不能越界索引")
    }

    /// 生长必须是单调的：进度越大，已画完的段数不减，且笔尖不会往回退。
    func testGrowthIsMonotonic() throws {
        let stroke = makeStroke()
        var previousDrawnLength = -1.0

        for step in 1 ... 200 {
            let progress = Double(step) / 200
            guard case .line(let completeSegmentCount, let growingTip) =
                try XCTUnwrap(StrokeGrowth.partial(of: stroke, progress: progress))
            else { return XCTFail("多采样点的笔应该被报成线") }

            // 用「已画完的段数 + 半段的推进比例」合成一个单调指标。
            let tipFraction: Double
            if let tip = growingTip {
                let start = stroke.samples[completeSegmentCount].point
                let end = stroke.samples[completeSegmentCount + 1].point
                tipFraction = start.distance(to: tip.point) / start.distance(to: end)
            } else {
                tipFraction = 0
            }
            let drawnLength = Double(completeSegmentCount) + tipFraction

            XCTAssertGreaterThanOrEqual(
                drawnLength,
                previousDrawnLength,
                "进度 \(progress) 处笔尖回退了，逐笔生长会出现抖动"
            )
            previousDrawnLength = drawnLength
        }
    }

    func testGrowingTipNeverExceedsTheSegmentItGrowsIn() throws {
        let stroke = makeStroke()

        for step in 1 ... 100 {
            let progress = Double(step) / 100
            guard case .line(let index, let maybeTip) =
                try XCTUnwrap(StrokeGrowth.partial(of: stroke, progress: progress))
            else { return XCTFail("多采样点的笔应该被报成线") }
            guard let tip = maybeTip else { continue }

            XCTAssertLessThan(index + 1, stroke.samples.count, "半段的终点索引越界")

            let start = stroke.samples[index]
            let end = stroke.samples[index + 1]
            // 笔尖必须落在这一段之内，压感也必须落在两端之间。
            XCTAssertLessThanOrEqual(start.point.distance(to: tip.point), start.point.distance(to: end.point) + 1e-9)
            XCTAssertTrue(
                (min(start.pressure, end.pressure) ... max(start.pressure, end.pressure)).contains(tip.pressure)
            )
        }
    }
}
