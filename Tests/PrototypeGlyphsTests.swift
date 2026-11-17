//
//  PrototypeGlyphsTests.swift
//  测试目标：Handwriting 的 PrototypeGlyphs（从网页原型搬来的标点与拉丁字形，计划 P3）。
//
//  为什么这样测：数据是逐字搬来的一串编码，最可能出的错是**解码错了**——档位算偏一格、
//  反斜杠那一档没跳过、行没切开——而这类错误不报错，只会让所有标点整体歪一点。
//  所以拿原型里能手算的几个值钉住解码，再对全部字形做范围检查。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class PrototypeGlyphsTests: XCTestCase {
    /// 原型 `dec`：'#'(35) 是最低一档 → −0.06；'~'(126) 越过反斜杠后是第 90 档 → 1.06。
    func testDecodeMatchesThePrototypeFormula() {
        XCTAssertEqual(PrototypeGlyphs.decode("#"), -0.06, accuracy: 1e-12)
        XCTAssertEqual(PrototypeGlyphs.decode("~"), 1.06, accuracy: 1e-12)
        // ']'(93) 在反斜杠之后，要先减 1 → 第 57 档。
        XCTAssertEqual(PrototypeGlyphs.decode("]"), (57.0 / 90 * 1120 - 60) / 1000, accuracy: 1e-12)
    }

    func testEveryPrototypeLineWasDecoded() {
        let expected = "!\"#%&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz 。，、？！；：「」（）《》—…·～"
        for character in expected {
            XCTAssertNotNil(PrototypeGlyphs.glyph(for: character), "缺「\(character)」")
        }
        XCTAssertNotNil(PrototypeGlyphs.glyph(for: "\u{3000}"), "全角空格要补上")
    }

    /// 逗号：原型 `!ff0c!520!7d<f<k5s` → 字宽 0.52，一笔四个点，第一个点是 ('7','d')。
    func testCommaDecodesExactly() throws {
        let comma = try XCTUnwrap(PrototypeGlyphs.glyph(for: "，"))
        XCTAssertEqual(comma.advanceWidth, 0.52, accuracy: 1e-12)
        XCTAssertEqual(comma.strokes.count, 1)
        XCTAssertEqual(comma.strokes[0].count, 4)
        XCTAssertEqual(comma.strokes[0][0].x, PrototypeGlyphs.decode("7"), accuracy: 1e-12)
        XCTAssertEqual(comma.strokes[0][0].y, PrototypeGlyphs.decode("d"), accuracy: 1e-12)
    }

    func testSpaceHasWidthButNoInk() throws {
        let space = try XCTUnwrap(PrototypeGlyphs.glyph(for: " "))
        XCTAssertEqual(space.advanceWidth, 0.3, accuracy: 1e-12)
        XCTAssertTrue(space.strokes.isEmpty)
    }

    /// 每个点都在编码能表达的范围里，每一笔至少一个点，字宽为正。
    func testAllGlyphsAreWellFormed() {
        for character in "!\"#%&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz。，、？！；：「」（）《》—…·～" {
            guard let glyph = PrototypeGlyphs.glyph(for: character) else { continue }
            XCTAssertGreaterThan(glyph.advanceWidth, 0, "「\(character)」")
            XCTAssertFalse(glyph.strokes.isEmpty, "「\(character)」没有笔画")
            for stroke in glyph.strokes {
                XCTAssertFalse(stroke.isEmpty, "「\(character)」有一笔是空的")
                for point in stroke {
                    XCTAssertTrue((-0.06 ... 1.06).contains(point.x) && (-0.06 ... 1.06).contains(point.y), "「\(character)」越界 \(point)")
                }
            }
        }
    }
}
