//
//  PageInkMapTests.swift
//  模块：Tests（页面占用图，计划 E9b）
//
//  文件职责：验证「哪里已经有墨」记得对，以及「这块地方空不空」答得对。
//
//  为什么这一层的错误特别难查：
//  它的产出会决定回应画在哪。答错成「空的」，回应就压在用户的字上；
//  答错成「不空」，回应会被推到页面角落甚至说放不下。两种都不会报错，
//  而且都只在特定的书写位置才出现。
//
//  所以这里重点测三件事：
//  一、稀疏的采样点之间不能留下「假空隙」——字形中线的点很稀，
//     只标点不标线段会在长横中间留出一串空格子，回应就会被放到一条线的正中间。
//  二、预留间距真的生效——回应不能贴着已有的墨写。
//  三、宁可说放不下，也不说放得下却实际压字（保守方向）。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class PageInkMapTests: XCTestCase {
    private let glyphHeight = 40.0
    private let lineSpacingRatio = 1.6

    private var page: PageRegion {
        PageRegion(left: 0, top: 0, width: 800, height: 600)
    }

    private func makeMap() -> PageInkMap {
        PageInkMap(
            page: page,
            resolution: PageInkMap.Resolution(
                glyphHeight: glyphHeight,
                lineSpacingRatio: lineSpacingRatio
            )
        )
    }

    // MARK: 空白页

    func testEmptyMapHasEverythingFree() {
        let map = makeMap()

        XCTAssertTrue(map.canPlace(PageRegion(left: 10, top: 10, width: 200, height: 100)))
        XCTAssertEqual(map.occupancy, 0)
    }

    /// 页外的区域一律放不下，哪怕图上完全是空的。
    func testRegionsOutsideThePageCannotBePlaced() {
        let map = makeMap()

        XCTAssertFalse(map.canPlace(PageRegion(left: 700, top: 10, width: 200, height: 100)))
        XCTAssertFalse(map.canPlace(PageRegion(left: -50, top: 10, width: 100, height: 100)))
        XCTAssertFalse(map.canPlace(PageRegion(left: 10, top: 560, width: 100, height: 100)))
    }

    // MARK: 标记

    func testMarkedAreaIsNoLongerFree() {
        var map = makeMap()
        map.mark([Polyline(points: [Point2D(x: 100, y: 100), Point2D(x: 300, y: 100)])])

        XCTAssertFalse(map.isFree(PageRegion(left: 150, top: 90, width: 50, height: 20)))
        XCTAssertGreaterThan(map.occupancy, 0)
    }

    /// 核心用例：采样点很稀时，线段中间不能留下「假空隙」。
    ///
    /// 字形中线每笔平均只有 5.6 个点，一条长横可能只有两个端点。
    /// 只标端点的话，中间会是一串空格子，于是回应会被放到那条横线的正中间。
    func testSparsePointsDoNotLeaveGapsAlongTheStroke() {
        var map = makeMap()
        // 一条 400 点长的横线，只给两个端点。
        map.mark([Polyline(points: [Point2D(x: 100, y: 300), Point2D(x: 500, y: 300)])])

        // 沿线每隔一小段都查一次，全程都必须是「不空」。
        for x in stride(from: 110.0, through: 490.0, by: 7) {
            XCTAssertFalse(
                map.isFree(PageRegion(left: x, top: 298, width: 4, height: 4)),
                "线上 x=\(x) 处被判成空的，说明只标了端点没标线段"
            )
        }
    }

    /// 斜线同理：斜着穿过格子角的情况最容易被跳过。
    func testDiagonalStrokesAreMarkedContinuously() {
        var map = makeMap()
        map.mark([Polyline(points: [Point2D(x: 100, y: 100), Point2D(x: 400, y: 400)])])

        for step in stride(from: 0.1, through: 0.9, by: 0.05) {
            let x = 100 + 300 * step
            let y = 100 + 300 * step
            XCTAssertFalse(
                map.isFree(PageRegion(left: x - 2, top: y - 2, width: 4, height: 4)),
                "斜线上 (\(x), \(y)) 处被判成空的"
            )
        }
    }

    func testSinglePointStrokeIsMarked() {
        var map = makeMap()
        map.mark([Polyline(points: [Point2D(x: 200, y: 200)])])

        XCTAssertFalse(map.isFree(PageRegion(left: 199, top: 199, width: 2, height: 2)))
    }

    // MARK: 预留间距

    /// 回应不能**贴着**已有的墨写。紧挨着墨迹的区域必须被判成放不下。
    func testAreaImmediatelyNextToInkIsNotFree() {
        var map = makeMap()
        map.mark([Polyline(points: [Point2D(x: 100, y: 100), Point2D(x: 300, y: 100)])])

        let clearance = PageInkMap.Resolution.clearance(
            glyphHeight: glyphHeight,
            lineSpacingRatio: lineSpacingRatio
        )
        XCTAssertGreaterThan(clearance, 0, "行距大于 1 时必须留出间距")

        // 紧贴在墨迹下方一点点的位置：应当因为预留间距而被判成不空。
        XCTAssertFalse(map.isFree(PageRegion(
            left: 150,
            top: 100 + clearance / 2,
            width: 50,
            height: 4
        )))
    }

    /// 隔得足够远就该是空的，否则回应永远找不到落点。
    func testAreaFarFromInkIsFree() {
        var map = makeMap()
        map.mark([Polyline(points: [Point2D(x: 100, y: 100), Point2D(x: 300, y: 100)])])

        XCTAssertTrue(map.canPlace(PageRegion(left: 100, top: 400, width: 200, height: 80)))
    }

    /// 预留间距**不是新参数**：它直接来自行距。行距为 1（行贴行）时间距为 0。
    /// 这条盯着「有人把它改成一个独立的拍出来的数」。
    func testClearanceIsDerivedFromLineSpacingNotAnIndependentNumber() {
        XCTAssertEqual(
            PageInkMap.Resolution.clearance(glyphHeight: 40, lineSpacingRatio: 1),
            0,
            "行距为 1 时不该有间距"
        )
        XCTAssertEqual(
            PageInkMap.Resolution.clearance(glyphHeight: 40, lineSpacingRatio: 1.6),
            40 * 0.6 / 2,
            accuracy: 1e-9
        )
        // 字大了间距按比例跟着大，不需要第二处调参。
        XCTAssertEqual(
            PageInkMap.Resolution.clearance(glyphHeight: 80, lineSpacingRatio: 1.6),
            PageInkMap.Resolution.clearance(glyphHeight: 40, lineSpacingRatio: 1.6) * 2,
            accuracy: 1e-9
        )
    }

    /// 格子大小同样由字高推出：一个字高切两格。
    func testCellSizeIsDerivedFromGlyphHeight() {
        let resolution = PageInkMap.Resolution(glyphHeight: 40, lineSpacingRatio: 1.6)

        XCTAssertEqual(resolution.cellSize, 40 / PageInkMap.Resolution.cellsPerGlyph, accuracy: 1e-9)
        XCTAssertLessThan(resolution.cellSize, 40, "格子必须比一个字小，否则字间空隙会被整格吞掉")
    }

    // MARK: 保守方向

    /// 写满一页之后，占用比例应该明显上升——这是「写满了要翻页」（计划 E3f）的判据来源。
    func testOccupancyRisesAsThePageFillsUp() {
        var map = makeMap()
        let before = map.occupancy

        for line in 0 ..< 10 {
            let y = 60 + Double(line) * 50
            map.mark([Polyline(points: [Point2D(x: 40, y: y), Point2D(x: 760, y: y)])])
        }

        XCTAssertGreaterThan(map.occupancy, before)
        XCTAssertGreaterThan(map.occupancy, 0.1, "十行字应该占掉可观的比例")
        XCTAssertLessThan(map.occupancy, 1, "十行细线不该把整页填满")
    }

    /// 整页都有墨时，任何区域都放不下。宁可说放不下，也不能说放得下却压字。
    func testNothingCanBePlacedOnAFullyInkedPage() {
        var map = makeMap()
        // 密集横线铺满整页。
        for y in stride(from: 2.0, through: 598.0, by: 8) {
            map.mark([Polyline(points: [Point2D(x: 0, y: y), Point2D(x: 800, y: y)])])
        }

        XCTAssertFalse(map.canPlace(PageRegion(left: 100, top: 100, width: 100, height: 50)))
        XCTAssertGreaterThan(map.occupancy, 0.9)
    }
}
