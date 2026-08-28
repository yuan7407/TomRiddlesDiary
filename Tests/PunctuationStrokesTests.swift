//
//  PunctuationStrokesTests.swift
//  模块：Tests（手写定义的标点笔顺，计划 E1c）
//
//  文件职责：守住这批**手写数据**里可以机器验证的部分，并把不能机器验证的部分
//  渲染成字符画，让人能真的看一眼。
//
//  为什么这个文件的存在方式和别的测试不一样：
//  标点笔顺是我按印刷体的样子手写出来的坐标，**没有上游数据可以比对**。
//  「这个形状像不像逗号」是机器判断不了的，所以这里分两层：
//
//  一、能断言的照常断言：每个符号有几笔、笔画是否落在它自己的字宽内
//     （越界就会压到下一个字）、坐标是否有限、笔画有没有退化成一个点。
//  二、判断不了的**渲染出来**：`testDumpAsciiPreviewForHumanReview` 把每个符号画成
//     字符画写进文件。它不做形状断言（那会变成把当前实现抄一遍当期望值，毫无意义），
//     它的价值是让人扫一眼就发现「这个问号是反的」这类错误。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class PunctuationStrokesTests: XCTestCase {
    private let spacing = GlyphStrokeProvider.smoothingTargetSpacing

    // MARK: 可机器验证的部分

    /// 核心用例：每一笔都必须落在这个符号自己的字宽之内。
    ///
    /// 越界就会压到下一个字。这条最容易在手写坐标时出错——西文标点的字宽只有
    /// 0.26…0.50，而坐标空间是 0…1 的方格，随手写个 0.5 就出界了。
    func testEveryStrokeFitsWithinItsAdvanceWidth() {
        for (character, glyph) in PunctuationStrokes.table {
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

    /// 纵向可以稍微越界（逗号的尾巴会伸到基线以下，撇号会顶到方格上沿），
    /// 但不能离谱——那说明坐标写错了数量级。
    func testStrokesStayRoughlyInsideTheGlyphBoxVertically() {
        for (character, glyph) in PunctuationStrokes.table {
            for stroke in glyph.strokes(spacing: spacing) {
                for point in stroke.points {
                    XCTAssertTrue(
                        (-0.1 ... 1.1).contains(point.y),
                        "「\(character)」纵向跑到 \(point.y)，超出字面方格太多"
                    )
                }
            }
        }
    }

    func testAllCoordinatesAreFinite() {
        for (character, glyph) in PunctuationStrokes.table {
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

    /// 字宽必须是正数且不超过一格。
    func testAdvanceWidthsAreSane() {
        for (character, glyph) in PunctuationStrokes.table {
            XCTAssertGreaterThan(glyph.advanceWidth, 0, "「\(character)」字宽不是正数")
            XCTAssertLessThanOrEqual(glyph.advanceWidth, 1, "「\(character)」比一个字面方格还宽")
        }
    }

    /// 笔数是可核对的客观事实，逐个写明。
    /// 写死期望值是刻意的：这批是手写数据，笔数写错了没有别的办法发现。
    func testStrokeCountsAreAsIntended() {
        let expected: [Character: Int] = [
            "。": 1, "，": 1, "、": 1, "：": 2, "；": 2, "！": 2, "？": 2,
            "…": 3, "·": 1, "—": 1, "「": 1, "」": 1, "（": 1, "）": 1,
            "《": 2, "》": 2,
            ".": 1, ",": 1, ":": 2, ";": 2, "!": 2, "?": 2,
            "'": 1, "\"": 2, "(": 1, ")": 1, "-": 1,
        ]

        XCTAssertEqual(
            Set(expected.keys), Set(PunctuationStrokes.table.keys),
            "期望表与实现表的符号集合不一致——新增或删除符号时两边都要改"
        )
        for (character, count) in expected {
            XCTAssertEqual(
                PunctuationStrokes.table[character]?.moves.count, count,
                "「\(character)」应该是 \(count) 笔"
            )
        }
    }

    /// 非墨点的笔画必须真的有长度。退化成一个点的「线」在纸上就是一个墨点，
    /// 看起来像少写了一笔。
    func testNonDotStrokesHaveRealLength() {
        for (character, glyph) in PunctuationStrokes.table {
            for (index, move) in glyph.moves.enumerated() {
                if case .dot = move { continue }

                let points = move.points(spacing: spacing)
                let length = zip(points, points.dropFirst()).reduce(into: 0.0) { total, pair in
                    total += pair.0.distance(to: pair.1)
                }
                XCTAssertGreaterThan(
                    length, 0.05,
                    "「\(character)」第 \(index + 1) 笔长度只有 \(length)，几乎退化成一个点"
                )
            }
        }
    }

    /// 全角标点必须占满一格，西文标点必须明显更窄——这正是引入字宽的原因。
    func testFullwidthMarksAreSquareAndLatinMarksAreNarrow() throws {
        for character in "。，、：；！？…·—「」（）《》" {
            XCTAssertEqual(
                PunctuationStrokes.glyph(for: character)?.advanceWidth, 1,
                "全角标点「\(character)」应占满一格"
            )
        }
        for character in ".,:;!?'\"()-" {
            let width = try XCTUnwrap(PunctuationStrokes.glyph(for: character)?.advanceWidth)
            XCTAssertLessThan(width, 0.6, "西文标点「\(character)」不该占这么宽")
        }
    }

    /// 圆弧必须真的画出弧形，不能退化成一条直线。
    /// 「。」是整圆，首尾点应几乎重合；「（」是一段弧，中点应明显偏离首尾连线。
    func testArcsActuallyCurve() throws {
        let circle = try XCTUnwrap(PunctuationStrokes.glyph(for: "。")).strokes(spacing: spacing)[0].points
        let first = try XCTUnwrap(circle.first)
        let last = try XCTUnwrap(circle.last)
        XCTAssertLessThan(first.distance(to: last), 0.02, "「。」应该是闭合的圈")

        let paren = try XCTUnwrap(PunctuationStrokes.glyph(for: "（")).strokes(spacing: spacing)[0].points
        let start = try XCTUnwrap(paren.first)
        let end = try XCTUnwrap(paren.last)
        let middle = paren[paren.count / 2]
        // 中点到首尾连线中点的距离，就是这段弧的「鼓起来多少」。
        let chordMidpoint = Point2D(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        XCTAssertGreaterThan(middle.distance(to: chordMidpoint), 0.05, "「（」没有弧度")
    }

    /// 标点接进排版之后必须真的产出笔画，而且不再被报成缺字。
    func testPunctuationFlowsThroughLayout() throws {
        let laidOut = try GlyphStrokeLayout().layOut(
            "累了。",
            configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: 40,
                lineWidth: 4_000,
                lineSpacingRatio: 1.6,
                origin: .zero
            )
        )

        XCTAssertTrue(laidOut.uncoveredCharacters.isEmpty, "标点不该再被报成缺字")
        XCTAssertFalse(laidOut.polylines.isEmpty)
    }

    /// 西文标点的窄字宽必须真的让后面的字靠近。
    /// 这条证明 `advanceWidth` 接进了排版，而不是只存在于数据里。
    func testNarrowPunctuationPullsTheNextGlyphCloser() throws {
        let configuration = GlyphStrokeLayoutConfiguration(
            glyphSize: 40,
            lineWidth: 4_000,
            lineSpacingRatio: 1.6,
            origin: .zero
        )
        let layout = GlyphStrokeLayout()

        // 「一.一」里的西文句点只占三成宽；「一。一」里的全角句号占满一格。
        let narrow = try layout.layOut("一.一", configuration: configuration)
        let full = try layout.layOut("一。一", configuration: configuration)

        let narrowGap = narrow.polylines.last!.points[0].x - narrow.polylines[0].points[0].x
        let fullGap = full.polylines.last!.points[0].x - full.polylines[0].points[0].x

        XCTAssertLessThan(narrowGap, fullGap, "窄标点后面的字应该靠得更近")
    }

    // MARK: 给人看的字符画

    /// 把每个标点渲染成字符画，写到 `/tmp/tomriddlesdiary-punctuation.txt`。
    ///
    /// **这不是形状断言**，它只保证渲染这条路走得通（每个符号至少要落下几个墨点，
    /// 否则说明那一笔根本没画出来）。它真正的用途是让人打开文件扫一眼，
    /// 发现「这个问号是反的」「这个顿号斜错了」这类机器看不出来的错误——
    /// 而这批数据是手写的，没有上游可以对照，这是唯一的形状核对手段。
    ///
    /// 拉丁字母与数字（计划 E1d）用同一套渲染核对。
    func testDumpAsciiPreviewForHumanReview() throws {
        var report = "标点笔顺字符画（计划 E1c）\n"
        report += "坐标 0…1 的字面方格，原点左上、y 向下。│ 标出字宽（advanceWidth）。\n"
        report += "数字 1/2/3 表示第几笔，便于核对笔顺。\n\n"

        for character in PunctuationStrokes.table.keys.sorted() {
            let glyph = try XCTUnwrap(PunctuationStrokes.glyph(for: character))
            let strokes = glyph.strokes(spacing: spacing)
            let picture = GlyphAsciiPreview.render(
                strokes: strokes,
                advanceWidth: glyph.advanceWidth
            )

            XCTAssertGreaterThan(picture.inkedCells, 0, "「\(character)」渲染不出任何墨迹")
            report += "「\(character)」  \(glyph.moves.count) 笔  字宽 \(glyph.advanceWidth)\n"
            report += picture.text
            report += "\n"
        }

        let url = URL(fileURLWithPath: "/tmp/tomriddlesdiary-punctuation.txt")
        try report.write(to: url, atomically: true, encoding: .utf8)
        print("字符画已写入 \(url.path)")
    }

}
