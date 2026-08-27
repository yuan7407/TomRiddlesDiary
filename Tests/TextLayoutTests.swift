//
//  TextLayoutTests.swift
//  模块：Tests（排版层）
//
//  文件职责：验证文字能被排到纸上，且位置符合基本不变量。
//
//  设计原因：
//  排版是从「模型返回的字符」到「纸上的位置」的唯一通道，E8 用字体画字、E1 用
//  字形笔画画字，两者都消费它的输出。它出错的表现是「纸上什么都没有」或者
//  「字叠在一起」，肉眼看得出来但说不清哪一步错了，所以必须有可断言的不变量：
//  字数对得上、同一行内横坐标递增且不重叠、换行后纵坐标增加、超宽必然换行。
//

import CoreGraphics
@testable import TomRiddlesDiary
import XCTest

final class TextLayoutTests: XCTestCase {
    private let layout = TextLayout()

    private func makeConfiguration(
        glyphHeight: Double = 40,
        lineWidth: Double = 400
    ) -> TextLayoutConfiguration {
        TextLayoutConfiguration(
            glyphHeight: glyphHeight,
            lineWidth: lineWidth,
            lineSpacingRatio: 1.6,
            origin: CGPoint(x: 20, y: 30)
        )
    }

    func testFontRegistersSuccessfully() throws {
        // 字体注册失败会让整段回应变成印刷体，属伪装成功，因此单独断言。
        XCTAssertNoThrow(try HandwritingFont.register())
    }

    func testEmptyTextProducesEmptyLayout() throws {
        let result = try layout.layOut("", configuration: makeConfiguration())

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.glyphs.count, 0)
    }

    func testChineseTextProducesOneGlyphPerCharacter() throws {
        let text = "我看见你"
        let result = try layout.layOut(text, configuration: makeConfiguration())

        XCTAssertEqual(result.glyphs.count, text.count, "每个字都该有一个位置")
        XCTAssertEqual(result.glyphs.map(\.character), Array(text))
    }

    func testLatinTextProducesOneGlyphPerCharacter() throws {
        let text = "Take your time"
        let result = try layout.layOut(text, configuration: makeConfiguration())

        XCTAssertEqual(result.glyphs.map(\.character), Array(text))
    }

    func testMixedChineseAndLatinKeepsEveryCharacter() throws {
        let text = "今天 Take 一下"
        let result = try layout.layOut(text, configuration: makeConfiguration())

        XCTAssertEqual(result.glyphs.map(\.character), Array(text))
    }

    func testGlyphsAdvanceLeftToRightWithinALine() throws {
        let result = try layout.layOut("我看见你今天", configuration: makeConfiguration(lineWidth: 4_000))

        XCTAssertEqual(result.lineCount, 1, "行宽足够时不该换行")
        let xs = result.glyphs.map(\.origin.x)
        XCTAssertEqual(xs, xs.sorted(), "同一行内横坐标必须递增")
        XCTAssertEqual(Set(xs).count, xs.count, "同一行内不该有两个字落在同一横坐标")
    }

    /// 排版层必须给出字体的上伸高度，否则渲染层没法把字对到基线上，
    /// 只能自己去问字体度量——那会把字体知识漏进渲染层。
    func testLayoutReportsFontAscent() throws {
        let configuration = makeConfiguration(glyphHeight: 40, lineWidth: 4_000)
        let result = try layout.layOut("我", configuration: configuration)

        XCTAssertGreaterThan(result.ascent, 0, "上伸高度必须为正，否则字会画到基线下面")
        XCTAssertLessThanOrEqual(
            result.ascent,
            configuration.glyphHeight * 1.5,
            "上伸高度远超字号说明取错了度量"
        )
    }

    func testEmptyLayoutReportsZeroAscent() throws {
        let result = try layout.layOut("", configuration: makeConfiguration())
        XCTAssertEqual(result.ascent, 0)
    }

    func testGlyphOriginsStartAtConfiguredOrigin() throws {
        let configuration = makeConfiguration(lineWidth: 4_000)
        let result = try layout.layOut("我", configuration: configuration)
        let first = try XCTUnwrap(result.glyphs.first)

        XCTAssertEqual(first.origin.x, configuration.origin.x, accuracy: 1e-9, "首字必须从左边距开始")
        // origin.y 是基线，位于该行顶部往下一个字高处。
        XCTAssertEqual(
            first.origin.y,
            configuration.origin.y + configuration.glyphHeight,
            accuracy: 1e-9
        )
    }

    func testTextWiderThanTheLineWraps() throws {
        // 行宽只够放两三个字，二十个字必然换行。
        let result = try layout.layOut(
            String(repeating: "我", count: 20),
            configuration: makeConfiguration(glyphHeight: 40, lineWidth: 100)
        )

        XCTAssertGreaterThan(result.lineCount, 1, "超出行宽必须换行")
        XCTAssertEqual(result.glyphs.count, 20, "换行不该丢字")

        let lineIndices = Set(result.glyphs.map(\.lineIndex))
        XCTAssertGreaterThan(lineIndices.count, 1)
    }

    func testLaterLinesAreLowerOnThePage() throws {
        let result = try layout.layOut(
            String(repeating: "我", count: 20),
            configuration: makeConfiguration(glyphHeight: 40, lineWidth: 100)
        )

        var lowestYByLine: [Int: Double] = [:]
        for glyph in result.glyphs {
            lowestYByLine[glyph.lineIndex] = glyph.origin.y
        }
        let sortedLines = lowestYByLine.keys.sorted()
        for (earlier, later) in zip(sortedLines, sortedLines.dropFirst()) {
            let earlierY = try XCTUnwrap(lowestYByLine[earlier])
            let laterY = try XCTUnwrap(lowestYByLine[later])
            XCTAssertGreaterThan(laterY, earlierY, "第 \(later) 行必须比第 \(earlier) 行更靠下")
        }
    }

    func testExplicitNewlineStartsANewLine() throws {
        let result = try layout.layOut("上\n下", configuration: makeConfiguration(lineWidth: 4_000))

        XCTAssertEqual(result.glyphs.map(\.character), ["上", "下"], "换行符本身不该产出字")
        let upper = try XCTUnwrap(result.glyphs.first)
        let lower = try XCTUnwrap(result.glyphs.last)
        XCTAssertEqual(upper.lineIndex, 0)
        XCTAssertEqual(lower.lineIndex, 1)
        XCTAssertGreaterThan(lower.origin.y, upper.origin.y)
    }

    func testAdvancesArePositiveAndProportional() throws {
        // 这个字体的字宽不等宽：实测拉丁 i 比 M 窄得多，汉字之间也有差异。
        // 若哪天换成等宽字体，这条会失败，提醒重新检查排版假设。
        let result = try layout.layOut("Mi", configuration: makeConfiguration(lineWidth: 4_000))

        XCTAssertEqual(result.glyphs.count, 2)
        let m = try XCTUnwrap(result.glyphs.first)
        let i = try XCTUnwrap(result.glyphs.last)
        XCTAssertGreaterThan(m.advance, 0)
        XCTAssertGreaterThan(i.advance, 0)
        XCTAssertGreaterThan(m.advance, i.advance, "M 应该比 i 宽")
    }

    func testUsedHeightGrowsWithLineCount() throws {
        let single = try layout.layOut("我", configuration: makeConfiguration(lineWidth: 4_000))
        let many = try layout.layOut(
            String(repeating: "我", count: 20),
            configuration: makeConfiguration(glyphHeight: 40, lineWidth: 100)
        )

        XCTAssertGreaterThan(many.usedHeight, single.usedHeight)
    }
}
