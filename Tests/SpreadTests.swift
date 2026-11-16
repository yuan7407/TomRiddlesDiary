//
//  SpreadTests.swift
//  测试目标：Spread 层的 BookPosture（合着 / 半合 / 摊平）与 SpreadGeometry（两页纸和折缝）。
//
//  为什么这样测：
//  - 姿态分类带回差。没有回差时，手停在临界角度会在「写」和「翻看」之间来回跳，
//    而每跳一次都会取消或触发成页——所以专门测「在门槛附近抖动不换姿态」。
//  - 折缝的处理方式是「把它在占用图上标成有墨」。这条测试直接拿真的 `PageInkMap` 验：
//    标完以后，横跨折缝的一块地方必须放不下，两页各自的空白必须还放得下。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class SpreadTests: XCTestCase {
    private let thresholds = BookPostureThresholds(closedBelowDegrees: 25, flatAboveDegrees: 165, hysteresisDegrees: 6)

    // MARK: 姿态

    func testAnglesMapToThreePostures() {
        XCTAssertEqual(BookPosture.classify(angleDegrees: 0, previous: nil, thresholds: thresholds), .closed)
        XCTAssertEqual(BookPosture.classify(angleDegrees: 110, previous: nil, thresholds: thresholds), .ajar)
        XCTAssertEqual(BookPosture.classify(angleDegrees: 180, previous: nil, thresholds: thresholds), .flat)
    }

    func testJitterAroundAThresholdDoesNotFlipThePosture() {
        var posture = BookPosture.classify(angleDegrees: 172, previous: nil, thresholds: thresholds)
        XCTAssertEqual(posture, .flat)
        for angle in [163.0, 166, 161, 164, 160] {
            posture = BookPosture.classify(angleDegrees: angle, previous: posture, thresholds: thresholds)
            XCTAssertEqual(posture, .flat, "摊平以后合页在 \(angle)° 抖动，不该被当成半合")
        }
        posture = BookPosture.classify(angleDegrees: 150, previous: posture, thresholds: thresholds)
        XCTAssertEqual(posture, .ajar, "真的合到 150° 才算离开摊平")

        posture = BookPosture.classify(angleDegrees: 10, previous: posture, thresholds: thresholds)
        XCTAssertEqual(posture, .closed)
        posture = BookPosture.classify(angleDegrees: 28, previous: posture, thresholds: thresholds)
        XCTAssertEqual(posture, .closed, "合着的本子松开一点点不算打开")
        posture = BookPosture.classify(angleDegrees: 40, previous: posture, thresholds: thresholds)
        XCTAssertEqual(posture, .ajar)
    }

    func testUnreadableAngleKeepsThePreviousPosture() {
        XCTAssertEqual(BookPosture.classify(angleDegrees: .nan, previous: .ajar, thresholds: thresholds), .ajar)
        XCTAssertEqual(BookPosture.classify(angleDegrees: .infinity, previous: nil, thresholds: thresholds), .flat)
    }

    func testOnlyFlatAllowsCommitAndOnlyClosingForcesIt() {
        XCTAssertTrue(BookPosture.flat.allowsCommitAfterPause)
        XCTAssertFalse(BookPosture.ajar.allowsCommitAfterPause, "半合着是在翻旧页，这时停笔不该成页")
        XCTAssertFalse(BookPosture.closed.allowsCommitAfterPause)
        XCTAssertTrue(BookPosture.closed.commitsPendingWritingOnEntry, "合上就是句号")
        XCTAssertFalse(BookPosture.ajar.commitsPendingWritingOnEntry)
        XCTAssertFalse(BookPosture.flat.commitsPendingWritingOnEntry)
    }

    func testShippedPostureThresholdsLeaveRoomForReading() {
        let shipped = BookFeel.posture
        XCTAssertGreaterThan(shipped.flatAboveDegrees - shipped.closedBelowDegrees, 90, "半合这一档要足够宽，手拿着才稳")
    }

    // MARK: 两页纸

    /// iPhone Duo 内屏横着摊开时的点数（1878 × 2670 像素按 3 倍渲染），中间 40 点是折缝。
    private let duo = SpreadGeometry(
        bounds: PageRegion(left: 0, top: 0, width: 890, height: 626),
        fold: PageRegion(left: 425, top: 0, width: 40, height: 626)
    )

    func testVerticalFoldSplitsIntoLeftAndRightPages() {
        XCTAssertEqual(duo.foldIsVertical, true)
        XCTAssertEqual(duo.page(.leading), PageRegion(left: 0, top: 0, width: 425, height: 626))
        XCTAssertEqual(duo.page(.trailing), PageRegion(left: 465, top: 0, width: 425, height: 626))
        XCTAssertEqual(duo.side(containing: Point2D(x: 100, y: 300)), .leading)
        XCTAssertEqual(duo.side(containing: Point2D(x: 700, y: 300)), .trailing)
        XCTAssertNil(duo.side(containing: Point2D(x: 445, y: 300)), "落在折缝里的点不属于任何一页")
    }

    func testHorizontalFoldSplitsIntoUpperAndLowerPages() {
        let tabletop = SpreadGeometry(
            bounds: PageRegion(left: 0, top: 0, width: 626, height: 890),
            fold: PageRegion(left: 0, top: 425, width: 626, height: 40)
        )
        XCTAssertEqual(tabletop.foldIsVertical, false)
        XCTAssertEqual(tabletop.page(.leading).bottom, 425)
        XCTAssertEqual(tabletop.page(.trailing).top, 465)
        XCTAssertEqual(tabletop.side(of: PageRegion(left: 50, top: 600, width: 200, height: 80)), .trailing)
    }

    func testNoFoldMeansOneSheetAndNoBarrier() {
        let sheet = SpreadGeometry(bounds: PageRegion(left: 0, top: 0, width: 820, height: 1180), fold: nil)
        XCTAssertFalse(sheet.hasFold)
        XCTAssertEqual(sheet.page(.leading), sheet.bounds)
        XCTAssertEqual(sheet.page(.trailing), sheet.bounds)
        XCTAssertNil(sheet.side(containing: Point2D(x: 10, y: 10)))
        XCTAssertTrue(sheet.foldBarrier(spacing: 10).isEmpty)

        let offscreen = SpreadGeometry(bounds: sheet.bounds, fold: PageRegion(left: 2000, top: 0, width: 40, height: 100))
        XCTAssertFalse(offscreen.hasFold, "屏幕之外的折缝当作没有")
    }

    func testWritingBelongsToThePageItsCentreIsOn() {
        XCTAssertEqual(duo.side(of: PageRegion(left: 300, top: 100, width: 140, height: 60)), .leading)
        XCTAssertEqual(duo.side(of: PageRegion(left: 500, top: 100, width: 300, height: 60)), .trailing)
    }

    func testFoldBarrierStopsARegionFromStraddlingTheFoldButLeavesBothPagesFree() {
        let resolution = PageInkMap.Resolution(glyphHeight: 34, lineSpacingRatio: 1.6)
        var map = PageInkMap(page: duo.bounds, resolution: resolution)
        let across = PageRegion(left: 380, top: 200, width: 140, height: 40)
        XCTAssertTrue(map.isFree(across), "标折缝之前，空白纸上哪里都放得下")

        map.mark(duo.foldBarrier(spacing: resolution.cellSize))

        XCTAssertFalse(map.isFree(across), "标了折缝以后，一段话不能横跨在折缝上")
        for top in stride(from: 40.0, through: 560, by: 65) {
            XCTAssertFalse(map.isFree(PageRegion(left: 430, top: top, width: 30, height: 20)), "折缝从上到下每一段都要被标到，\(top) 处漏了")
        }
        let inset = resolution.clearance + resolution.cellSize
        XCTAssertTrue(map.isFree(PageRegion(left: 60, top: 200, width: 425 - 60 - inset, height: 60)), "左页的空白还在")
        XCTAssertTrue(map.isFree(PageRegion(left: 465 + inset, top: 200, width: 300, height: 60)), "右页的空白还在")
    }
}
