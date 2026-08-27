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

final class StrokeGrowthTests: XCTestCase {
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

    func testSingleSampleStrokeHasNoSegmentsToDraw() throws {
        let dot = TimedStroke(
            samples: [StrokeSample(point: Point2D(x: 5, y: 5), pressure: 0.5)],
            duration: 0.2
        )

        let partial = try XCTUnwrap(StrokeGrowth.partial(of: dot, progress: 0.5))

        // 墨点没有线段，也没有生长中的半段；怎么画墨点由渲染层决定。
        XCTAssertEqual(partial.completeSegmentCount, 0)
        XCTAssertNil(partial.growingTip)
    }

    func testMidSegmentProducesAnInterpolatedGrowingTip() throws {
        // 三段线段，进度 0.5 → 段进度 1.5，即第一段画完，第二段画了一半。
        let partial = try XCTUnwrap(StrokeGrowth.partial(of: makeStroke(), progress: 0.5))

        XCTAssertEqual(partial.completeSegmentCount, 1)
        XCTAssertEqual(partial.growingSegmentStartIndex, 1)

        let tip = try XCTUnwrap(partial.growingTip)
        XCTAssertEqual(tip.point, Point2D(x: 15, y: 0))
        // 压感必须一起插值，否则笔尖粗细会一格一格跳。
        XCTAssertEqual(tip.pressure, 0.5, accuracy: 1e-12)
    }

    func testProgressLandingExactlyOnASampleHasNoGrowingTip() throws {
        // 段进度恰好为 1，第一段刚画完，还没开始第二段。
        let partial = try XCTUnwrap(StrokeGrowth.partial(of: makeStroke(), progress: 1.0 / 3.0))

        XCTAssertEqual(partial.completeSegmentCount, 1)
        XCTAssertNil(partial.growingTip, "恰好落在采样点上时不该再多画半段")
    }

    func testFullProgressDrawsEveryCompleteSegmentAndNoTip() throws {
        let partial = try XCTUnwrap(StrokeGrowth.partial(of: makeStroke(), progress: 1))

        XCTAssertEqual(partial.completeSegmentCount, 3, "三段线段应全部画完")
        XCTAssertNil(partial.growingTip)
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
            let partial = try XCTUnwrap(StrokeGrowth.partial(of: stroke, progress: progress))

            // 用「已画完的段数 + 半段的推进比例」合成一个单调指标。
            let tipFraction: Double
            if let tip = partial.growingTip {
                let start = stroke.samples[partial.growingSegmentStartIndex].point
                let end = stroke.samples[partial.growingSegmentStartIndex + 1].point
                tipFraction = start.distance(to: tip.point) / start.distance(to: end)
            } else {
                tipFraction = 0
            }
            let drawnLength = Double(partial.completeSegmentCount) + tipFraction

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
            let partial = try XCTUnwrap(StrokeGrowth.partial(of: stroke, progress: progress))
            guard let tip = partial.growingTip else { continue }

            let index = partial.growingSegmentStartIndex
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
