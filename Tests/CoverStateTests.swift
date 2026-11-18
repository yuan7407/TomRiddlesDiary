//
//  CoverStateTests.swift
//  测试目标：外屏封面什么时候盖着（计划 S 组，决策 83）。
//
//  为什么测这些：规则是用户逐条定的——合上是封面、外屏翻开以后是纸、摊开的内屏没有封面、
//  合上 / 切后台 / 锁屏都回到封面、从摊开合上时演一遍合回来。这些都是纯数据，机器能守住；
//  好不好看只能真机眼看（S10）。
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
}
