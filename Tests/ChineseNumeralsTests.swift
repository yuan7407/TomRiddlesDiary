//
//  ChineseNumeralsTests.swift
//  测试目标：Spread 的 ChineseNumerals（页眉日期与页码，计划 P2）。
//
//  为什么这样测：中文数字的读法有几个容易写错的边界（十、十几、整十、二十几），
//  写错不会报错，只会在纸上印出「一十七」这种没人这么写的字。页码与日期写法不同，各钉几条。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class ChineseNumeralsTests: XCTestCase {
    func testSpokenNumbersAcrossTheTrickyBoundaries() {
        let expected: [Int: String] = [0: "〇", 7: "七", 10: "十", 11: "十一", 17: "十七", 20: "二十", 21: "二十一", 30: "三十", 31: "三十一", 99: "九十九"]
        for (value, text) in expected {
            XCTAssertEqual(ChineseNumerals.spoken(value), text, "\(value)")
        }
    }

    func testFolioIsWrittenDigitByDigit() {
        XCTAssertEqual(ChineseNumerals.folio(2), "二")
        XCTAssertEqual(ChineseNumerals.folio(12), "一二")
        XCTAssertEqual(ChineseNumerals.folio(103), "一〇三")
    }

    func testDateLineMatchesThePrototype() {
        // 2026-11-17 是星期二（Calendar 的 weekday = 3）。
        XCTAssertEqual(ChineseNumerals.dateLine(month: 11, day: 17, weekday: 3), "十一月十七日　星期二")
        XCTAssertEqual(ChineseNumerals.dateLine(month: 1, day: 1, weekday: 1), "一月一日　星期日")
    }
}
