//
//  StrokePathSmoothingTests.swift
//  模块：Tests（字形中线加密与平滑）
//
//  文件职责：验证稀疏中线被加密成平滑曲线，而且**没有把字形改坏**。
//
//  为什么这两面都要测：
//  加密的目的是让弯笔不再有棱角，但平滑很容易做过头——把字形骨架磨圆、
//  或者让曲线冲出控制点之外（均匀参数化的 Catmull-Rom 就会，点距不均时甚至自交打圈）。
//  字被磨变形和字有棱角一样是缺陷，只是前者更难发现：它看起来「很平滑」。
//  所以断言分三类——
//  一、真的变平滑了（转折角明显变小）；
//  二、原始控制点全部还在曲线上（骨架没被近似掉）；
//  三、没有超射（曲线不跑出控制点围成的范围太多），也不自交。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class StrokePathSmoothingTests: XCTestCase {
    private let spacing = 0.05

    /// 一条稀疏的弧线：四个点勾出一个转弯，正是中线数据的典型形状。
    private let sparseArc = [
        Point2D(x: 0, y: 0),
        Point2D(x: 0.4, y: 0.05),
        Point2D(x: 0.7, y: 0.3),
        Point2D(x: 0.75, y: 0.8),
    ]

    /// 每个点处前后两段的夹角（弧度）之和，用来量「总共拐了多少」。
    /// 同一条曲线加密之后总转角应该差不多，但**单点的最大转角**要明显变小——
    /// 那就是棱角。
    private func maximumTurn(_ points: [Point2D]) -> Double {
        guard points.count > 2 else { return 0 }
        var maximum = 0.0
        for index in 1 ..< points.count - 1 {
            let incoming = (x: points[index].x - points[index - 1].x, y: points[index].y - points[index - 1].y)
            let outgoing = (x: points[index + 1].x - points[index].x, y: points[index + 1].y - points[index].y)
            let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
            let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
            maximum = max(maximum, abs(atan2(cross, dot)))
        }
        return maximum
    }

    // MARK: 真的变平滑了

    /// 核心用例：加密之后单点的最大转角必须明显变小，那就是「棱角不见了」。
    func testDensifyingRemovesTheSharpCorners() {
        let densified = StrokePathSmoothing.densified(sparseArc, targetSpacing: spacing)

        XCTAssertGreaterThan(densified.count, sparseArc.count * 3, "点数应该明显变多")
        XCTAssertLessThan(
            maximumTurn(densified),
            maximumTurn(sparseArc) * 0.5,
            "加密之后每一步的转角应该小得多，否则棱角还在"
        )
    }

    /// 加密后的间距必须真的达到目标，否则「加密」名不副实。
    func testDensifiedSpacingRespectsTheTarget() {
        let densified = StrokePathSmoothing.densified(sparseArc, targetSpacing: spacing)

        for (a, b) in zip(densified, densified.dropFirst()) {
            XCTAssertLessThanOrEqual(
                a.distance(to: b),
                spacing * 1.5,
                "相邻点间距超出目标太多"
            )
        }
    }

    // MARK: 字形没被改坏

    /// 原始控制点必须**全部落在**加密后的曲线上。
    /// 中线是字形骨架，点的位置就是数据本身，不能被「近似」掉。
    func testEveryOriginalControlPointSurvives() {
        let densified = StrokePathSmoothing.densified(sparseArc, targetSpacing: spacing)

        for original in sparseArc {
            let closest = densified.map { $0.distance(to: original) }.min() ?? .infinity
            XCTAssertLessThan(closest, 1e-9, "控制点 \(original) 不在曲线上，骨架被改动了")
        }
    }

    /// 首尾点必须精确保留：笔画接头与字形定位都依赖它们。
    func testEndpointsAreExact() {
        let densified = StrokePathSmoothing.densified(sparseArc, targetSpacing: spacing)

        XCTAssertEqual(densified.first, sparseArc.first)
        XCTAssertEqual(densified.last, sparseArc.last)
    }

    /// 不许超射：曲线不能跑出控制点围成的范围太多。
    ///
    /// 这条专门防均匀参数化的 Catmull-Rom——中线的点距很不均匀（长横只有两个点，
    /// 弯钩挤着好几个点），均匀参数化在这种数据上会冲出控制点甚至自交打圈，
    /// 字就会多出一个不存在的环。向心参数化数学上保证不会。
    func testCurveDoesNotOvershootTheControlPolygon() {
        // 刻意造一个点距极不均匀的形状：两个点挨得很近，接着一个很长的跨度。
        let uneven = [
            Point2D(x: 0, y: 0),
            Point2D(x: 0.02, y: 0.01),
            Point2D(x: 0.9, y: 0.05),
            Point2D(x: 0.95, y: 0.9),
        ]
        let densified = StrokePathSmoothing.densified(uneven, targetSpacing: spacing)

        let minX = uneven.map(\.x).min() ?? 0
        let maxX = uneven.map(\.x).max() ?? 0
        let minY = uneven.map(\.y).min() ?? 0
        let maxY = uneven.map(\.y).max() ?? 0
        // 允许一点点外扩（样条本来就会略微鼓出去），但不能是「打个圈」那种量级。
        let margin = 0.15

        for point in densified {
            XCTAssertTrue(
                point.x >= minX - margin && point.x <= maxX + margin,
                "x 超射到 \(point.x)，控制点范围是 \(minX)…\(maxX)"
            )
            XCTAssertTrue(
                point.y >= minY - margin && point.y <= maxY + margin,
                "y 超射到 \(point.y)，控制点范围是 \(minY)…\(maxY)"
            )
        }
    }

    /// 直线加密之后还得是直线，不能自己弯起来。
    func testStraightLineStaysStraight() {
        let straight = [
            Point2D(x: 0, y: 0.5),
            Point2D(x: 0.3, y: 0.5),
            Point2D(x: 0.6, y: 0.5),
            Point2D(x: 1, y: 0.5),
        ]
        let densified = StrokePathSmoothing.densified(straight, targetSpacing: spacing)

        XCTAssertTrue(
            densified.allSatisfy { abs($0.y - 0.5) < 1e-9 },
            "直线被平滑成了曲线"
        )
    }

    // MARK: 退化输入

    func testTwoPointStrokeIsReturnedUnchanged() {
        let line = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 1)]

        // 两点之间本来就是直线，没有曲率可言，加密没有意义。
        XCTAssertEqual(StrokePathSmoothing.densified(line, targetSpacing: spacing), line)
    }

    func testEmptyAndSinglePointAreSafe() {
        XCTAssertEqual(StrokePathSmoothing.densified([], targetSpacing: spacing), [])

        let dot = [Point2D(x: 0.5, y: 0.5)]
        XCTAssertEqual(StrokePathSmoothing.densified(dot, targetSpacing: spacing), dot)
    }

    /// 重合点会让样条的节点间距为 0（除零）。必须先去掉。
    func testCoincidentPointsAreRemoved() {
        let withDuplicates = [
            Point2D(x: 0, y: 0),
            Point2D(x: 0, y: 0),
            Point2D(x: 0.5, y: 0.2),
            Point2D(x: 0.5, y: 0.2),
            Point2D(x: 1, y: 0),
        ]
        let densified = StrokePathSmoothing.densified(withDuplicates, targetSpacing: spacing)

        XCTAssertTrue(densified.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "出现了非有限坐标，说明除零了")
        for (a, b) in zip(densified, densified.dropFirst()) {
            XCTAssertGreaterThan(a.distance(to: b), 0, "加密结果里不该还有重合点")
        }
    }

    // MARK: 与引擎的关系

    /// 加密的目标间距必须不粗于引擎重采样的间距。
    ///
    /// 为什么要机器守着：两个数在两个文件里，单看都合理。但如果加密后的点距
    /// 比引擎的重采样间距还粗，引擎在重采样时仍然要跨过一段没有中间点的曲线、
    /// 只能走直线，棱角原封不动地回来——而加密的代价照付。
    /// 这类失效不会报错，只会让人以为「平滑做了但没用」。
    func testSmoothingIsFinerThanTheEngineResampling() {
        XCTAssertLessThan(
            GlyphStrokeProvider.smoothingTargetSpacing,
            HandwritingFeel.sampleSpacingRatio,
            "中线加密必须比引擎的重采样更细，否则加密等于没做"
        )
    }

    /// 真实字形数据走完加密之后，弯笔的棱角必须明显缓和。
    /// 这条把「合成用例通了」和「真数据也通了」分开——前者不代表后者。
    func testRealGlyphStrokesBecomeSmoother() throws {
        // 「的」有撇、有弯钩，是典型的带弧笔画。
        let glyph = try GlyphStrokeProvider().strokes(for: "的")

        XCTAssertFalse(glyph.strokes.isEmpty)
        for (index, stroke) in glyph.strokes.enumerated() {
            XCTAssertGreaterThan(
                stroke.points.count, 5,
                "第 \(index + 1) 笔只有 \(stroke.points.count) 个点，没有被加密"
            )
            XCTAssertLessThan(
                maximumTurn(stroke.points),
                .pi / 2,
                "第 \(index + 1) 笔还有接近直角的硬转折"
            )
        }
    }
}
