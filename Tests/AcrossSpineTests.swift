//
//  AcrossSpineTests.swift
//  测试目标：P3「他的字」——手排（GlyphStrokeLayout 的 HandSetting）、字号分档、隔着书脊的落点。
//
//  为什么这样测：这些规则来自网页原型（决策 80），观感好不好只能眼看，但有几条是机器能守的硬约定：
//  他写在你**对面**那页、和你那句**齐平**、不压在已有的字上、同一个种子排出同样的「手」、
//  手排的行确实往右上走。坐标用 Duo 内屏实测值：951 × 669，折缝 x 455.5、宽 40，安全区右 84、下 34。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class AcrossSpineTests: XCTestCase {
    private let spread = SpreadGeometry(
        bounds: PageRegion(left: 0, top: 0, width: 951, height: 669),
        fold: PageRegion(left: 455.5, top: 0, width: 40, height: 669)
    )

    private func columns() throws -> FacingColumns {
        try XCTUnwrap(ReplyComposer.facingColumns(spread: spread, safeTop: 0, safeBottom: 34, safeTrailing: 84))
    }

    private func emptyMap(glyph: Double = 50) -> PageInkMap {
        PageInkMap(page: spread.bounds, resolution: PageInkMap.Resolution(glyphHeight: glyph, lineSpacingRatio: 1.5))
    }

    // MARK: 栏位

    func testColumnsStayOffTheSpineAndOutOfTheStatusBar() throws {
        let c = try columns()
        XCTAssertLessThan(c.leading.right, 455.5, "左栏不许伸进折缝")
        XCTAssertGreaterThan(c.trailing.left, 495.5, "右栏不许伸进折缝")
        XCTAssertLessThanOrEqual(c.trailing.right, 951 - 84, "右栏要让开竖排状态栏")
        XCTAssertEqual(c.spineX, 475.5, accuracy: 1e-9)
    }

    func testHeWritesOnTheFacingPage() throws {
        let c = try columns()
        let onLeft = PageRegion(left: 80, top: 200, width: 200, height: 60)
        let onRight = PageRegion(left: 560, top: 200, width: 200, height: 60)
        XCTAssertEqual(c.column(facing: onLeft), c.trailing)
        XCTAssertEqual(c.column(facing: onRight), c.leading)
    }

    func testNoFacingColumnsWithoutAVerticalFold() {
        let outer = SpreadGeometry(bounds: PageRegion(left: 0, top: 0, width: 466, height: 678), fold: nil)
        XCTAssertNil(ReplyComposer.facingColumns(spread: outer, safeTop: 0, safeBottom: 0, safeTrailing: 0))
    }

    // MARK: 字号

    func testShortRepliesAreWrittenBiggerThanLongOnes() {
        XCTAssertEqual(ReplyComposer.baseGlyphSize(characterCount: 4), 56)
        XCTAssertEqual(ReplyComposer.baseGlyphSize(characterCount: 25), 37)
        XCTAssertEqual(ReplyComposer.baseGlyphSize(characterCount: 80), 29)
    }

    // MARK: 落点

    func testReplyLandsAcrossTheSpineLevelWithYourWriting() throws {
        let writing = PageRegion(left: 80, top: 240, width: 260, height: 70)
        let reply = try ReplyComposer.forSoul().composeAcrossSpine(
            "这个词你只写了一遍，没有别的。", facing: writing, columns: try columns(), on: emptyMap(), seed: 7
        )
        let region = reply.placement.region
        XCTAssertEqual(reply.placement.slot, .acrossSpine)
        XCTAssertGreaterThan(region.left, 495.5, "你写在左页，他应该写在右页")
        XCTAssertEqual(region.top, writing.top, accuracy: 40, "第一行应该和你那句大致齐平")
    }

    /// 他那一栏已经有字（P4 之前上一轮的回应还在）：报放不下，由调用方退回找空位，不压字。
    func testOccupiedFacingColumnIsRefused() throws {
        var map = emptyMap()
        let c = try columns()
        map.mark([Polyline(points: [Point2D(x: c.trailing.left, y: c.trailing.top), Point2D(x: c.trailing.right, y: c.trailing.bottom)]),
                  Polyline(points: [Point2D(x: c.trailing.right, y: c.trailing.top), Point2D(x: c.trailing.left, y: c.trailing.bottom)])])
        XCTAssertThrowsError(try ReplyComposer.forSoul().composeAcrossSpine(
            "你好。", facing: PageRegion(left: 80, top: 240, width: 200, height: 60), columns: c, on: map, seed: 1
        ))
    }

    // MARK: 手排

    private func handLayout(seed: UInt64) throws -> LaidOutGlyphStrokes {
        try GlyphStrokeLayout().layOut("一二三四五六七八", configuration: GlyphStrokeLayoutConfiguration(
            glyphSize: 40, lineWidth: 2000, lineSpacingRatio: 1.5, origin: CGPoint(x: 0, y: 100), hand: ReplyComposer.hand(seed: seed)
        ))
    }

    func testSameSeedSameHand() throws {
        XCTAssertEqual(try handLayout(seed: 3).polylines, try handLayout(seed: 3).polylines)
        XCTAssertNotEqual(try handLayout(seed: 3).polylines, try handLayout(seed: 4).polylines)
    }

    /// 原型的行往右上走（行斜 −0.018 ± 0.007）：一行八个字，末字应该比首字高。
    func testHandWrittenLineRisesToTheRight() throws {
        let laidOut = try handLayout(seed: 3)
        let first = try XCTUnwrap(laidOut.polylines.first?.points.first)
        let last = try XCTUnwrap(laidOut.polylines.last?.points.first)
        XCTAssertLessThan(last.y, first.y, "行尾应该比行首高（y 向下）")
    }
}
