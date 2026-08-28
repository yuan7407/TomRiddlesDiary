//
//  LatinStrokesTests.swift
//  模块：Tests（手写定义的拉丁字母与数字笔顺，计划 E1d）
//
//  文件职责：守住这 62 个**手写字形**里可以机器验证的部分，并渲染成字符画供人眼核对。
//
//  为什么强调「可以机器验证的部分」：
//  「这个 s 像不像 s」判断不了。但下面这些能判断，而且每一条都对应一种真实的失败：
//  - 覆盖完整：漏一个字母，英文单词里就会有一个空洞，而且只有真写到那个字母才发现。
//  - 落在字宽内：出界就压到下一个字。手写坐标时最容易犯——坐标空间是 0…1，
//    而 i 的字宽只有 0.28。
//  - 该顶到基准线的要顶到：b d f h k l 要够高，g j p q y 要够低。写错了整行会歪。
//  - 笔画不退化：长度接近 0 的「线」在纸上就是个墨点，看起来像少写了一笔。
//
//  形状本身靠 `testDumpAsciiPreviewForHumanReview` 渲染出来看。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class LatinStrokesTests: XCTestCase {
    private let spacing = GlyphStrokeProvider.smoothingTargetSpacing

    private let lowercaseLetters = "abcdefghijklmnopqrstuvwxyz"
    private let uppercaseLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private let digitCharacters = "0123456789"

    // MARK: 覆盖完整

    func testAllSixtyTwoGlyphsAreDefined() {
        for character in lowercaseLetters + uppercaseLetters + digitCharacters {
            XCTAssertNotNil(LatinStrokes.glyph(for: character), "「\(character)」没有定义")
        }
        XCTAssertEqual(LatinStrokes.table.count, 62, "应该正好 26 + 26 + 10 个字形")
    }

    /// 手写表之间不许有重复字符。重复会让某个字符莫名换形状或宽度，极难定位，
    /// 所以 `AuthoredGlyphStrokes` 遇到重复直接崩——这条确认现在没有重复。
    func testAuthoredTablesDoNotOverlap() {
        // 合表里除了标点与字母，还有两个「有宽度没墨迹」的空白字形。
        let whitespaceCount = 2

        XCTAssertEqual(
            AuthoredGlyphStrokes.table.count,
            PunctuationStrokes.table.count + LatinStrokes.table.count + whitespaceCount,
            "各张手写表的字符数相加应等于合表后的数量，不等说明有重复"
        )
    }

    /// 空格不是缺字：它有宽度、没有墨迹。
    ///
    /// 若把它报成「缺笔顺数据」，界面会告诉用户「这一页少了字符」，而实际什么都没少。
    /// 这种假警报会让人去查不存在的问题，也会让真正的缺字淹没在噪声里。
    func testSpaceHasWidthButNoInkAndIsNotReportedAsMissing() throws {
        let space = try XCTUnwrap(AuthoredGlyphStrokes.glyph(for: " "))

        XCTAssertTrue(space.moves.isEmpty, "空格不该有墨迹")
        XCTAssertGreaterThan(space.advanceWidth, 0, "空格必须有宽度，否则单词会连在一起")

        let laidOut = try GlyphStrokeLayout().layOut(
            "a b",
            configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: 40,
                lineWidth: 4_000,
                lineSpacingRatio: 1.6,
                origin: .zero
            )
        )
        XCTAssertTrue(laidOut.uncoveredCharacters.isEmpty, "空格不该被报成缺字")
    }

    /// 空格必须真的把后面的字推开，否则单词会挤成一团。
    func testSpaceSeparatesWords() throws {
        let configuration = GlyphStrokeLayoutConfiguration(
            glyphSize: 40,
            lineWidth: 4_000,
            lineSpacingRatio: 1.6,
            origin: .zero
        )
        let layout = GlyphStrokeLayout()

        func rightmostX(_ text: String) throws -> Double {
            try layout.layOut(text, configuration: configuration)
                .polylines.flatMap { $0.points.map(\.x) }.max() ?? 0
        }

        XCTAssertGreaterThan(try rightmostX("a b"), try rightmostX("ab"), "空格应该把后面的字推开")
    }

    // MARK: 落在字宽内

    /// 核心用例：每一笔都必须落在这个字形自己的字宽之内，否则压到下一个字。
    func testEveryStrokeFitsWithinItsAdvanceWidth() {
        for (character, glyph) in LatinStrokes.table {
            for (index, stroke) in glyph.strokes(spacing: spacing).enumerated() {
                for point in stroke.points {
                    XCTAssertGreaterThanOrEqual(
                        point.x, -0.02,
                        "「\(character)」第 \(index + 1) 笔向左出界到 \(point.x)"
                    )
                    XCTAssertLessThanOrEqual(
                        point.x, glyph.advanceWidth + 0.02,
                        "「\(character)」第 \(index + 1) 笔超出字宽 \(glyph.advanceWidth)，会压到下一个字"
                    )
                }
            }
        }
    }

    /// 字形也不该在字宽里缩成一小团——那样字距会看起来忽宽忽窄。
    /// 允许 i / l / . 这类天生很窄的字形例外（它们的墨迹本来就只有一竖）。
    func testGlyphsUseMostOfTheirAdvanceWidth() {
        let naturallyNarrow: Set<Character> = ["i", "j", "l", "t", "f", "I", "1"]

        for (character, glyph) in LatinStrokes.table where !naturallyNarrow.contains(character) {
            let xs = glyph.strokes(spacing: spacing).flatMap { $0.points.map(\.x) }
            let used = (xs.max() ?? 0) - (xs.min() ?? 0)

            XCTAssertGreaterThan(
                used, glyph.advanceWidth * 0.5,
                "「\(character)」只用了字宽的 \(used / glyph.advanceWidth)，字距会显得过宽"
            )
        }
    }

    func testAdvanceWidthsAreSane() {
        for (character, glyph) in LatinStrokes.table {
            XCTAssertGreaterThan(glyph.advanceWidth, 0.2, "「\(character)」字宽过小")
            XCTAssertLessThanOrEqual(glyph.advanceWidth, 1, "「\(character)」比一个汉字还宽")
        }
    }

    /// m 和 w 必须比 i 和 l 宽得多——这就是引入比例字宽的意义。
    func testWideLettersAreWiderThanNarrowOnes() throws {
        let wide = try XCTUnwrap(LatinStrokes.glyph(for: "m")?.advanceWidth)
        let narrow = try XCTUnwrap(LatinStrokes.glyph(for: "i")?.advanceWidth)

        XCTAssertGreaterThan(wide, narrow * 2, "m 应该明显比 i 宽")
    }

    // MARK: 基准线

    /// 上伸字母（b d f h k l）必须顶得够高，否则和 x 高的字母一样高，看不出区别。
    func testAscendersReachHighEnough() throws {
        for character in "bdfhkl" {
            let glyph = try XCTUnwrap(LatinStrokes.glyph(for: character))
            let top = glyph.strokes(spacing: spacing).flatMap { $0.points.map(\.y) }.min() ?? 1

            XCTAssertLessThan(top, 0.24, "「\(character)」是上伸字母，顶端只到 \(top)，不够高")
        }
    }

    /// 下伸字母（g j p q y）必须伸得够低。
    func testDescendersReachLowEnough() throws {
        for character in "gjpqy" {
            let glyph = try XCTUnwrap(LatinStrokes.glyph(for: character))
            let bottom = glyph.strokes(spacing: spacing).flatMap { $0.points.map(\.y) }.max() ?? 0

            XCTAssertGreaterThan(bottom, 0.84, "「\(character)」是下伸字母，底端只到 \(bottom)，不够低")
        }
    }

    /// x 高的小写字母（a c e m n o s u v w x z）不该顶到上伸部，也不该伸到下伸部。
    /// 顶了就说明坐标写错了基准线，整行字会高低不齐。
    func testXHeightLettersStayBetweenTheLines() throws {
        for character in "acemnosuvwxz" {
            let glyph = try XCTUnwrap(LatinStrokes.glyph(for: character))
            let ys = glyph.strokes(spacing: spacing).flatMap { $0.points.map(\.y) }

            XCTAssertGreaterThan(ys.min() ?? 0, 0.32, "「\(character)」不该顶到上伸部")
            XCTAssertLessThan(ys.max() ?? 1, 0.84, "「\(character)」不该伸到下伸部")
        }
    }

    /// 大写字母的高度必须一致地落在「大写顶 … 基线」之间。
    /// Q 的尾巴与 J 的勾会低于基线，是正常的，单独放宽。
    func testUppercaseLettersShareTheSameHeightBand() throws {
        for character in uppercaseLetters where character != "Q" {
            let glyph = try XCTUnwrap(LatinStrokes.glyph(for: character))
            let ys = glyph.strokes(spacing: spacing).flatMap { $0.points.map(\.y) }

            XCTAssertLessThan(ys.min() ?? 1, 0.24, "大写「\(character)」顶端不够高")
            XCTAssertGreaterThan(ys.max() ?? 0, 0.66, "大写「\(character)」底端没落到基线附近")
            XCTAssertLessThan(ys.max() ?? 1, 0.86, "大写「\(character)」伸得太低")
        }
    }

    // MARK: 笔画本身

    func testAllCoordinatesAreFinite() {
        for (character, glyph) in LatinStrokes.table {
            for stroke in glyph.strokes(spacing: spacing) {
                XCTAssertFalse(stroke.points.isEmpty, "「\(character)」有一笔是空的")
                for point in stroke.points {
                    XCTAssertTrue(
                        point.x.isFinite && point.y.isFinite,
                        "「\(character)」出现非有限坐标"
                    )
                }
            }
        }
    }

    /// 非墨点的笔画必须真的有长度。退化成一个点的「线」在纸上就是个墨点。
    func testNonDotStrokesHaveRealLength() {
        for (character, glyph) in LatinStrokes.table {
            for (index, move) in glyph.moves.enumerated() {
                if case .dot = move { continue }

                let points = move.points(spacing: spacing)
                let length = zip(points, points.dropFirst()).reduce(into: 0.0) { total, pair in
                    total += pair.0.distance(to: pair.1)
                }
                XCTAssertGreaterThan(
                    length, 0.08,
                    "「\(character)」第 \(index + 1) 笔长度只有 \(length)，几乎退化成一个点"
                )
            }
        }
    }

    /// 笔数不该多到不像手写。三四笔是常态，超过五笔说明拆得太碎。
    func testStrokeCountsAreReasonable() {
        for (character, glyph) in LatinStrokes.table {
            XCTAssertGreaterThan(glyph.moves.count, 0, "「\(character)」没有笔画")
            XCTAssertLessThanOrEqual(
                glyph.moves.count, 4,
                "「\(character)」拆成了 \(glyph.moves.count) 笔，手写不会这么碎"
            )
        }
    }

    /// i 和 j 必须带点，而且那个点必须是墨点笔画（这样才会用 A7 的洇开效果）。
    func testDottedLettersUseARealInkDot() throws {
        for character in "ij" {
            let glyph = try XCTUnwrap(LatinStrokes.glyph(for: character))
            let hasDot = glyph.moves.contains { move in
                if case .dot = move { return true }
                return false
            }
            XCTAssertTrue(hasDot, "「\(character)」的点应该是墨点笔画")
        }
    }

    // MARK: 接进排版

    /// 英文单词必须能完整排出来，一个字母都不缺。
    func testEnglishFlowsThroughLayoutWithNothingMissing() throws {
        let laidOut = try GlyphStrokeLayout().layOut(
            "Take your time.",
            configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: 40,
                lineWidth: 4_000,
                lineSpacingRatio: 1.6,
                origin: .zero
            )
        )

        XCTAssertTrue(laidOut.uncoveredCharacters.isEmpty, "缺了：\(laidOut.uncoveredCharacters)")
        XCTAssertFalse(laidOut.polylines.isEmpty)
    }

    /// 中英混排：汉字占满一格，字母各按自己的宽度，整句都要排得出来。
    func testMixedChineseAndEnglishFlowsThroughLayout() throws {
        let laidOut = try GlyphStrokeLayout().layOut(
            "我看见你写的 hello，慢一点。",
            configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: 40,
                lineWidth: 4_000,
                lineSpacingRatio: 1.6,
                origin: .zero
            )
        )

        XCTAssertTrue(laidOut.uncoveredCharacters.isEmpty, "缺了：\(laidOut.uncoveredCharacters)")
    }

    /// 比例字宽必须真的生效：`iii` 应该比 `mmm` 窄得多。
    /// 这条证明字宽接进了排版，而不是只存在于数据里。
    func testProportionalWidthsActuallyChangeTheLineLength() throws {
        let configuration = GlyphStrokeLayoutConfiguration(
            glyphSize: 40,
            lineWidth: 4_000,
            lineSpacingRatio: 1.6,
            origin: .zero
        )
        let layout = GlyphStrokeLayout()

        func rightmostX(_ text: String) throws -> Double {
            try layout.layOut(text, configuration: configuration)
                .polylines.flatMap { $0.points.map(\.x) }.max() ?? 0
        }

        XCTAssertLessThan(try rightmostX("iii"), try rightmostX("mmm"), "窄字母应该排得更紧")
    }

    /// 端到端：英文经字形笔画 → 引擎 → 可播完的逐笔序列。
    func testEnglishFeedsTheStrokeEngineEndToEnd() throws {
        let glyphSize = 40.0
        let laidOut = try GlyphStrokeLayout().layOut(
            "Take your time.",
            configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: glyphSize,
                lineWidth: 4_000,
                lineSpacingRatio: 1.6,
                origin: .zero
            )
        )
        let sequence = StrokePipeline().process(
            laidOut.polylines,
            configuration: HandwritingFeel.humanizerConfiguration(referenceScale: glyphSize),
            seed: HandwritingFeel.defaultSeed
        )

        XCTAssertEqual(sequence.strokes.count, laidOut.polylines.count)
        XCTAssertTrue(
            StrokeReplayTimeline(sequence: sequence).frame(at: sequence.totalDuration).isComplete,
            "时间轴应能播完"
        )
    }

    // MARK: 给人看的字符画

    /// 把 62 个字形渲染成字符画，写到 `/tmp/tomriddlesdiary-latin.txt`。
    /// 不做形状断言（那会变成把实现抄一遍当期望值）；底线是每个字形至少要落下墨迹。
    func testDumpAsciiPreviewForHumanReview() throws {
        var report = "拉丁字母与数字笔顺字符画（计划 E1d）\n"
        report += "坐标 0…1 的字面方格，原点左上、y 向下。│ 标出字宽（advanceWidth）。\n"
        report += "基准线：上伸部 0.14 / 大写顶 0.17 / x 高 0.40 / 基线 0.78 / 下伸部 0.95\n"
        report += "数字 1/2/3 表示第几笔，便于核对笔顺。\n\n"

        for character in lowercaseLetters + uppercaseLetters + digitCharacters {
            let glyph = try XCTUnwrap(LatinStrokes.glyph(for: character))
            let picture = GlyphAsciiPreview.render(
                strokes: glyph.strokes(spacing: spacing),
                advanceWidth: glyph.advanceWidth
            )

            XCTAssertGreaterThan(picture.inkedCells, 0, "「\(character)」渲染不出任何墨迹")
            report += "「\(character)」  \(glyph.moves.count) 笔  字宽 \(glyph.advanceWidth)\n"
            report += picture.text
            report += "\n"
        }

        let url = URL(fileURLWithPath: "/tmp/tomriddlesdiary-latin.txt")
        try report.write(to: url, atomically: true, encoding: .utf8)
        print("字符画已写入 \(url.path)")
    }
}
