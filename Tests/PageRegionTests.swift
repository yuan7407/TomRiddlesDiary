//
//  PageRegionTests.swift
//  模块：Tests（页面区域几何，计划 E9a）
//
//  文件职责：验证「这些笔画占了哪块地方」和矩形之间的判断。
//
//  为什么这些琐碎的判断值得测：
//  它们是「回应排在哪」这条链的最底层。相交判断写反一个不等号，症状是
//  回应偶尔压在用户的字上——只在特定位置才出现，而且看起来像排版随机出错。
//  y 向下这件事更是重灾区：`top` 是较小的那个数，写判断时极容易按直觉弄反。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class PageRegionTests: XCTestCase {
    // MARK: 笔画占了哪块地方

    func testCoveringFramesAllPoints() throws {
        let polylines = [
            Polyline(points: [Point2D(x: 10, y: 20), Point2D(x: 30, y: 25)]),
            Polyline(points: [Point2D(x: 5, y: 40), Point2D(x: 50, y: 15)]),
        ]

        let region = try XCTUnwrap(PageRegion.covering(polylines))

        XCTAssertEqual(region.left, 5)
        XCTAssertEqual(region.top, 15)
        XCTAssertEqual(region.right, 50)
        XCTAssertEqual(region.bottom, 40)
    }

    /// 什么都没写时返回 nil，不返回零矩形。
    /// 「没写」和「写了但占地为零」是两件事，后者不可能发生，前者调用方必须单独处理。
    func testCoveringNothingIsNilNotAnEmptyRegion() {
        XCTAssertNil(PageRegion.covering([]))
        XCTAssertNil(PageRegion.covering([Polyline(points: [])]))
    }

    func testCoveringASinglePointGivesAZeroSizedRegionAtThatPoint() throws {
        let region = try XCTUnwrap(PageRegion.covering([Polyline(points: [Point2D(x: 7, y: 9)])]))

        XCTAssertEqual(region.left, 7)
        XCTAssertEqual(region.top, 9)
        XCTAssertTrue(region.isEmpty)
    }

    // MARK: 相交与包含

    /// **边贴边不算重叠。** 一行字的下边缘正好等于下一行的上边缘时，它们没有真的压在一起。
    /// 若把边贴边算成重叠，紧挨着的两行会被判成冲突，回应会被推得越来越远。
    func testTouchingEdgesDoNotCountAsOverlap() {
        let upper = PageRegion(left: 0, top: 0, width: 100, height: 50)
        let lower = PageRegion(left: 0, top: 50, width: 100, height: 50)

        XCTAssertFalse(upper.intersects(lower))
        XCTAssertFalse(lower.intersects(upper))
    }

    func testActualOverlapIsDetected() {
        let one = PageRegion(left: 0, top: 0, width: 100, height: 50)
        let other = PageRegion(left: 90, top: 40, width: 100, height: 50)

        XCTAssertTrue(one.intersects(other))
        XCTAssertTrue(other.intersects(one))
    }

    /// y 向下：`top` 是较小的数。这条专门盯着「按直觉写反」这个坑。
    func testVerticalOrderFollowsYDown() {
        let above = PageRegion(left: 0, top: 10, width: 10, height: 10)
        let below = PageRegion(left: 0, top: 100, width: 10, height: 10)

        XCTAssertLessThan(above.top, below.top, "视觉上更靠上的区域，top 必须更小")
        XCTAssertEqual(above.bottom, 20)
        XCTAssertFalse(above.intersects(below))
    }

    func testContainmentAllowsTouchingEdges() {
        let page = PageRegion(left: 0, top: 0, width: 100, height: 100)

        XCTAssertTrue(PageRegion(left: 0, top: 0, width: 100, height: 100).isContained(in: page))
        XCTAssertTrue(PageRegion(left: 10, top: 10, width: 10, height: 10).isContained(in: page))
        XCTAssertFalse(PageRegion(left: 95, top: 10, width: 10, height: 10).isContained(in: page))
        XCTAssertFalse(PageRegion(left: -1, top: 10, width: 10, height: 10).isContained(in: page))
    }

    // MARK: 撑开与合并

    func testExpandingGrowsOnAllFourSides() {
        let region = PageRegion(left: 10, top: 10, width: 20, height: 20).expanded(by: 5)

        XCTAssertEqual(region.left, 5)
        XCTAssertEqual(region.top, 5)
        XCTAssertEqual(region.right, 35)
        XCTAssertEqual(region.bottom, 35)
    }

    /// 收缩到负尺寸时夹成 0，而不是崩。
    /// 一块被收成空的区域仍然是一块空区域，这里崩掉没有意义。
    func testShrinkingBelowZeroClampsInsteadOfCrashing() {
        let region = PageRegion(left: 10, top: 10, width: 4, height: 4).expanded(by: -10)

        XCTAssertEqual(region.width, 0)
        XCTAssertEqual(region.height, 0)
        XCTAssertTrue(region.isEmpty)
    }

    func testUnionFramesBoth() {
        let one = PageRegion(left: 0, top: 0, width: 10, height: 10)
        let other = PageRegion(left: 50, top: 40, width: 10, height: 10)

        let combined = one.union(other)

        XCTAssertEqual(combined.left, 0)
        XCTAssertEqual(combined.top, 0)
        XCTAssertEqual(combined.right, 60)
        XCTAssertEqual(combined.bottom, 50)
    }

    func testBetweenDoesNotCareAboutCornerOrder() {
        let one = PageRegion.between(Point2D(x: 30, y: 40), Point2D(x: 10, y: 20))
        let other = PageRegion.between(Point2D(x: 10, y: 20), Point2D(x: 30, y: 40))

        XCTAssertEqual(one, other)
        XCTAssertEqual(one.left, 10)
        XCTAssertEqual(one.top, 20)
        XCTAssertEqual(one.width, 20)
        XCTAssertEqual(one.height, 20)
    }
}
