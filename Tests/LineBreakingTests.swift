//
//  LineBreakingTests.swift
//  所属：测试（Handwriting 的断行规则，计划 E2a）
//
//  这些测试守什么：
//  句读不落到行首、开引号不留在行尾、英文单词不拆、超长单词仍然排得出来（不死循环）、
//  试排和真排一致，以及「按意思换行」只在打开时生效。
//  用真的字形数据走 `GlyphStrokeLayout`，而不是只测 `LineBreaker`：
//  规则对不对最终要看排出来的行，而且这样顺带守住「换行只有一条路径」。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class LineBreakingTests: XCTestCase {
    private let size = 40.0

    private func configuration(glyphsPerLine: Double) -> GlyphStrokeLayoutConfiguration {
        GlyphStrokeLayoutConfiguration(
            glyphSize: size,
            lineWidth: size * glyphsPerLine,
            lineSpacingRatio: 1.5,
            origin: CGPoint(x: 0, y: 0)
        )
    }

    /// 直接问断行器：每一行是哪些字。字宽按「汉字 1、其余 0.5」给，够测规则。
    private func lines(_ text: String, glyphsPerLine: Double, rules: LineBreakRules = .standard) -> [String] {
        let pieces = text.map { character -> LinePiece in
            let isHan = character.unicodeScalars.contains { $0.properties.isIdeographic }
            return LinePiece(character: character, advance: character.isNewline ? 0 : (isHan ? size : size * 0.5))
        }
        return LineBreaker.lines(of: pieces, lineWidth: size * glyphsPerLine, glyphSize: size, rules: rules)
            .map { String($0.map { pieces[$0].character }) }
    }

    func testPeriodNeverStartsALine() {
        // 一行正好放四个汉字，句号是第五个：它不许独自落到下一行，要带着「字」一起下去。
        XCTAssertEqual(lines("今天写字。好", glyphsPerLine: 4), ["今天写", "字。好"])
        for line in lines("你写的每一个字，我都看得见。今天想从哪里说起？", glyphsPerLine: 5) {
            XCTAssertFalse(LineBreakRules.standard.notAtLineStart.contains(line.first ?? "字"), "行首出现了标点：\(line)")
        }
    }

    func testOpeningQuoteNeverEndsALine() {
        let broken = lines("他说过「纸等着」这句话", glyphsPerLine: 4)
        for line in broken {
            XCTAssertFalse(LineBreakRules.standard.notAtLineEnd.contains(line.last ?? "字"), "行尾留下了开引号：\(line)")
        }
        XCTAssertEqual(broken.joined(), "他说过「纸等着」这句话", "一个字都不能丢")
    }

    func testEnglishWordsAreKeptWhole() {
        let broken = lines("今天的 stakeholder 很多", glyphsPerLine: 7)
        XCTAssertTrue(broken.contains { $0.contains("stakeholder") }, "stakeholder 被拆开了：\(broken)")
    }

    func testWordWiderThanTheLineStillLaysOut() {
        // 整行只放得下 4 个半宽字母，而单词有 11 个：必须硬拆，且不能死循环、不能丢字。
        let broken = lines("stakeholder", glyphsPerLine: 2)
        XCTAssertGreaterThan(broken.count, 1)
        XCTAssertEqual(broken.joined(), "stakeholder")
    }

    func testSpaceAtTheStartOfAWrappedLineTakesNoRoom() {
        let broken = lines("今天很累 ok", glyphsPerLine: 4)
        XCTAssertEqual(broken, ["今天很累", "ok"], "因为放不下而另起的一行，行首空格不占位置")
        XCTAssertEqual(lines(" 好", glyphsPerLine: 4), [" 好"], "段首的空格是原文，留着")
    }

    func testNewlinesAreHonouredAndBlankLinesCount() {
        XCTAssertEqual(lines("早。\n\n你来了。", glyphsPerLine: 8), ["早。", "", "你来了。"])
        XCTAssertEqual(lines("", glyphsPerLine: 8), [""], "空文本也算一行，行数不能是 0")
    }

    func testPhraseBreakingOnlyHappensWhenTurnedOn() {
        let text = "墨还没干。你是想到哪里，才停下笔的？"
        var phrase = LineBreakRules.standard
        phrase.phraseBreakFill = 0.5
        XCTAssertEqual(lines(text, glyphsPerLine: 9), ["墨还没干。你是想到", "哪里，才停下笔的？"], "默认规则顶到纸边才换行")
        XCTAssertEqual(lines(text, glyphsPerLine: 9, rules: phrase), ["墨还没干。", "你是想到哪里，", "才停下笔的？"], "打开后在句读处换行")
    }

    func testPhraseBreakingDoesNotStrandAShortTail() {
        var phrase = LineBreakRules.standard
        phrase.phraseBreakFill = 0.5
        // 「我在，好。」逗号后面只剩两个字宽，不值得另起一行。
        XCTAssertEqual(lines("今天我在，好。", glyphsPerLine: 9, rules: phrase), ["今天我在，好。"])
    }

    func testEveryLineStaysWithinTheDeclaredWidth() throws {
        let layout = GlyphStrokeLayout(rules: BookFeel.lineBreaking)
        let config = configuration(glyphsPerLine: 6)
        let laidOut = try layout.layOut("你写的每一个字，我都看得见。今天的 review 想从哪里说起？", configuration: config)
        let box = try XCTUnwrap(laidOut.boundingBox)
        XCTAssertLessThanOrEqual(box.left + box.width, config.lineWidth + 1e-9, "粘在一起换行的标点也必须在行宽之内")
        XCTAssertTrue(laidOut.uncoveredCharacters.isEmpty)
    }

    func testMeasureAndLayOutAgree() throws {
        let layout = GlyphStrokeLayout(rules: BookFeel.lineBreaking)
        let config = configuration(glyphsPerLine: 6)
        let text = "他说过「纸等着」。后面那半句，现在写得出来吗？"
        let laidOut = try layout.layOut(text, configuration: config)
        let measured = try layout.measure(text, configuration: config)
        XCTAssertEqual(measured.lineCount, laidOut.lineCount)
        XCTAssertEqual(measured.boundingBox, laidOut.boundingBox)
        XCTAssertEqual(measured.usedHeight, laidOut.usedHeight)
    }
}
