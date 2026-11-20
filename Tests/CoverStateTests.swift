//
//  CoverStateTests.swift
//  测试目标：外屏封面什么时候盖着（计划 S 组，决策 83）。
//
//  为什么测这些：规则是用户逐条定的——合上是封面、外屏翻开以后是纸、摊开的内屏没有封面、
//  合上 / 切后台 / 锁屏都回到封面、从摊开合上时演一遍合回来。这些都是纯数据，机器能守住；
//  好不好看只能真机眼看（S10）。
//  提示（教你掀开手机）的那条掀开曲线也在这里钉住：两头必须合严，否则循环时封面会跳一下。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class CoverStateTests: XCTestCase {
    func testClosedBookShowsTheCoverAndOpenBookNever() {
        let cover = CoverState()
        XCTAssertTrue(cover.showsCover(posture: .closed, isPortrait: true))
        XCTAssertFalse(cover.showsCover(posture: .flat, isPortrait: false), "摊开的内屏没有封面")
        XCTAssertFalse(cover.showsCover(posture: .ajar, isPortrait: false))
        XCTAssertFalse(cover.showsCover(posture: .flat, isPortrait: true), "内屏转成竖的也没有封面：以姿态为准")
    }

    /// 启动的头一瞬还不知道姿态：先按屏幕形状猜，免得在外屏上先闪一下纸。
    func testUnknownPostureGuessesFromTheScreenShape() {
        let cover = CoverState()
        XCTAssertTrue(cover.showsCover(posture: nil, isPortrait: true))
        XCTAssertFalse(cover.showsCover(posture: nil, isPortrait: false))
    }

    func testSwipingOpenRevealsThePaperOnTheOuterScreen() {
        var cover = CoverState()
        cover.opened()
        XCTAssertFalse(cover.showsCover(posture: .closed, isPortrait: true))
    }

    /// 合上本子：回到封面，并演一遍合回来。
    func testClosingTheBookBringsTheCoverBackWithMotion() {
        var cover = CoverState()
        cover.opened()
        cover.postureChanged(from: .flat, to: .closed)
        XCTAssertTrue(cover.showsCover(posture: .closed, isPortrait: true))
        XCTAssertTrue(cover.closesWithMotion)
        cover.closeMotionPlayed()
        XCTAssertFalse(cover.closesWithMotion)
    }

    /// 启动时第一次报姿态（从「不知道」到合上）不是「合上了本子」：不演合回来。
    func testFirstPostureReportIsNotAClose() {
        var cover = CoverState()
        cover.postureChanged(from: nil, to: .closed)
        XCTAssertFalse(cover.closesWithMotion)
    }

    /// 切到后台、锁屏：回来是封面，不演合上（那时屏幕是黑的）。
    func testLeavingTheAppBringsTheCoverBackQuietly() {
        var cover = CoverState()
        cover.opened()
        cover.leftTheApp()
        XCTAssertTrue(cover.showsCover(posture: .closed, isPortrait: true))
        XCTAssertFalse(cover.closesWithMotion)
    }

    /// 提示：慢慢掀开 → 停住 → 合回去。两头合严（循环不跳），中间到顶，任何时候都不超过 1。
    func testHintOpensTheCoverAndClosesItBeforeTheLoopRestarts() {
        let m = CoverLook.Motion.self
        XCTAssertEqual(BookCoverView.hintOpening(0), 0)
        XCTAssertEqual(BookCoverView.hintOpening(1), 0, "一段演完时没合严，下一段开头会跳")
        XCTAssertEqual(BookCoverView.hintOpening(m.hintClosedBy), 0, accuracy: 1e-9)
        XCTAssertEqual(BookCoverView.hintOpening((m.hintHoldFrom + m.hintCloseFrom) / 2), 1)
        let samples = stride(from: 0.0, through: 1.0, by: 0.01).map(BookCoverView.hintOpening)
        XCTAssertTrue(samples.allSatisfy { (0 ... 1).contains($0) })
        let rising = samples.prefix(Int(m.hintHoldFrom * 100))
        XCTAssertEqual(Array(rising), rising.sorted(), "掀开的那段不许忽开忽合")
    }
}
