//
//  WritingRoundTests.swift
//  模块：Tests（把一页手写切成一轮一轮，计划 E3e）
//
//  文件职责：验证「这一轮新写的」切得对。
//
//  为什么这件事值得单独测：
//  切错了不会报错，只会让魂把你之前聊过的内容一遍遍重读——越回越离题，
//  而且每一轮的输入都比上一轮长，钱一路涨上去。这两个后果在界面上都看不见，
//  你只会觉得「这个 AI 怎么老在说重复的话」。
//
//  另一个方向的错法更隐蔽：切得太狠，把真正的新内容漏掉，于是明明写了字却
//  没有反应。所以下面既测「旧的不许再交一遍」，也测「新的一笔都不许丢」。
//

import Foundation
import PencilKit
@testable import TomRiddlesDiary
import XCTest

nonisolated final class WritingRoundTests: XCTestCase {
    /// 造一笔，落笔时刻可指定。
    private func makeStroke(at start: Date, y: CGFloat = 50) -> PKStroke {
        var points: [PKStrokePoint] = []
        for step in 0 ... 6 {
            let t = CGFloat(step) / 6
            points.append(PKStrokePoint(
                location: CGPoint(x: 20 + t * 40, y: y),
                timeOffset: Double(t) * 0.2,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 0,
                azimuth: 0,
                altitude: .pi / 2
            ))
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: start)
        )
    }

    private let base = Date(timeIntervalSince1970: 1_000_000)

    /// 三笔，落笔时刻依次相差一秒。
    private func makePage(strokeCount: Int = 3) -> PKDrawing {
        PKDrawing(strokes: (0 ..< strokeCount).map {
            makeStroke(at: base.addingTimeInterval(Double($0)), y: 50 + CGFloat($0) * 30)
        })
    }

    // MARK: 没成过页时

    func testWithoutABoundaryTheWholePageIsThisRound() {
        let page = makePage()

        XCTAssertEqual(WritingRound.strokes(of: page, after: nil).count, 3)
        XCTAssertEqual(WritingRound.drawing(of: page, after: nil).strokes.count, 3)
    }

    func testEmptyPageHasNoBoundary() {
        XCTAssertNil(WritingRound.boundary(of: PKDrawing()))
        XCTAssertTrue(WritingRound.strokes(of: PKDrawing(), after: nil).isEmpty)
    }

    // MARK: 成过页之后

    /// 核心用例：分界点之后落笔的才算这一轮，之前的一笔都不许再交出去。
    func testOnlyStrokesWrittenAfterTheBoundaryCount() {
        let page = makePage(strokeCount: 5) // 落笔时刻 +0 +1 +2 +3 +4 秒
        let boundary = base.addingTimeInterval(2) // 前三笔已收下

        let round = WritingRound.strokes(of: page, after: boundary)

        XCTAssertEqual(round.count, 2, "只剩 +3 和 +4 两笔是新的")
        XCTAssertTrue(
            round.allSatisfy { $0.path.creationDate > boundary },
            "交出去的笔画必须全部晚于分界点"
        )
    }

    /// 分界点那一笔本身属于上一轮。用「严格大于」而不是「大于等于」，
    /// 否则每一轮都会把上一轮的最后一笔重复交一次。
    func testTheBoundaryStrokeItselfBelongsToThePreviousRound() {
        let page = makePage(strokeCount: 3)
        let boundary = WritingRound.boundary(of: page)

        XCTAssertTrue(
            WritingRound.strokes(of: page, after: boundary).isEmpty,
            "刚成页之后这一轮应该是空的"
        )
    }

    /// 成页之后又写了一笔，那一笔必须被认出来。
    /// 这条防的是切得太狠——明明写了字却没反应，那是最糟的失败。
    func testWritingAgainAfterCommitStartsANewRound() {
        var page = makePage(strokeCount: 3)
        let boundary = WritingRound.boundary(of: page)

        page = PKDrawing(strokes: page.strokes + [makeStroke(at: base.addingTimeInterval(10))])

        XCTAssertEqual(WritingRound.strokes(of: page, after: boundary).count, 1)
    }

    /// 分界点必须取最晚的落笔时刻，不能取数组里的最后一个元素。
    /// 顺序异常时取错会让一部分旧笔画被重复交出去。
    func testBoundaryIsTheLatestCreationDateRegardlessOfArrayOrder() {
        let early = makeStroke(at: base)
        let late = makeStroke(at: base.addingTimeInterval(5))

        XCTAssertEqual(WritingRound.boundary(of: PKDrawing(strokes: [early, late])), late.path.creationDate)
        XCTAssertEqual(WritingRound.boundary(of: PKDrawing(strokes: [late, early])), late.path.creationDate)
    }

    /// 擦掉这一轮刚写的内容之后，这一轮就应该是空的——
    /// 不能因为页面上还留着上一轮的字，就把上一轮当成新内容再回应一次。
    func testErasingThisRoundLeavesNothingNew() {
        let previous = makePage(strokeCount: 2)
        let boundary = WritingRound.boundary(of: previous)
        // 用户又写了一笔然后擦掉：页面回到只有上一轮的两笔。
        let afterErase = previous

        XCTAssertTrue(WritingRound.strokes(of: afterErase, after: boundary).isEmpty)
    }

    /// 刻意**不用笔画数量**当分界的原因：擦掉中间一笔再补写一笔，数量不变，
    /// 按数量切就会把新内容整个漏掉，而且完全无声。按时刻切不会。
    func testCountBasedSplittingWouldMissNewWorkButTimeBasedDoesNot() {
        let original = makePage(strokeCount: 3)
        let boundary = WritingRound.boundary(of: original)

        // 擦掉中间那一笔，再补写一笔新的。总数仍是 3。
        let kept = [original.strokes[0], original.strokes[2]]
        let rewritten = PKDrawing(strokes: kept + [makeStroke(at: base.addingTimeInterval(20))])

        XCTAssertEqual(rewritten.strokes.count, original.strokes.count, "总数没变，按数量切会看不出有新内容")
        XCTAssertEqual(
            WritingRound.strokes(of: rewritten, after: boundary).count, 1,
            "按落笔时刻切能认出那一笔是新的"
        )
    }
}
