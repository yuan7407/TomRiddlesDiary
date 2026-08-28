//
//  GlyphStrokeTests.swift
//  模块：Tests（字形笔顺数据与笔画排版）
//
//  文件职责：验证「字符 → 有笔顺的笔画 → 页面坐标」这条通路。
//
//  设计原因：
//  这是整个产品缺了最久的一块——模型只给字符，字符里没有笔顺；没有这份数据就画不出
//  「一笔一笔写」。它出错的表现是「字歪了」「字上下颠倒」「字叠在一起」或「凭空少字」，
//  都是肉眼能看出异常但说不清哪一层错的症状，所以必须有可断言的不变量。
//
//  坐标系那条断言尤其重要：原始数据是 y 轴朝上（字体惯例），屏幕是 y 轴朝下。
//  翻转写错的话字会上下颠倒，而「颠倒的汉字」在密集笔画下并不总是一眼就能看出来。
//  这里用「上」和「下」两个字反证方向——它们的笔画分布在垂直方向上截然不同。
//

import CoreGraphics
@testable import TomRiddlesDiary
import XCTest

nonisolated final class GlyphStrokeTests: XCTestCase {
    private let provider = GlyphStrokeProvider()

    // MARK: 数据可用性

    func testDataSetIsAvailableAndCoversCommonCharacters() throws {
        XCTAssertGreaterThan(
            GlyphStrokeProvider.coveredCharacterCount, 9_000,
            "数据集应覆盖 9000 以上汉字；数量骤降说明资源没打进包或被换了"
        )
        for character in "我看见你今天写得很慢累" {
            XCTAssertTrue(provider.covers(character), "常用字「\(character)」应有笔顺数据")
        }
    }

    /// 标点、拉丁字母、数字**不在**数据集里，这是已知缺口（计划 E1c/E1d 要补）。
    /// 断言它「确实缺」而不是假装有：哪天补上了，这条会失败并提醒我们更新。
    func testPunctuationAndLatinAreKnownGaps() {
        for character in "，。？！、abcABC123" {
            XCTAssertFalse(
                provider.covers(character),
                "「\(character)」意外地有了笔顺数据——若已补上，请更新此断言与 E1c/E1d 状态"
            )
        }
    }

    func testUncoveredCharacterThrowsTheSpecificReason() {
        // 必须能区分「这个字没覆盖」与「资源坏了」，两者的处置完全不同。
        XCTAssertThrowsError(try provider.strokes(for: "，")) { error in
            XCTAssertEqual(error as? GlyphStrokeLookupFailure, .characterNotCovered("，"))
        }
    }

    // MARK: 笔顺与笔画结构

    func testStrokeCountMatchesTheCharacter() throws {
        // 笔数是可查证的客观事实，用几个笔数明确的字守住。
        XCTAssertEqual(try provider.strokes(for: "一").strokes.count, 1)
        XCTAssertEqual(try provider.strokes(for: "十").strokes.count, 2)
        XCTAssertEqual(try provider.strokes(for: "口").strokes.count, 3)
        XCTAssertEqual(try provider.strokes(for: "我").strokes.count, 7)
    }

    func testEveryStrokeHasAtLeastTwoPoints() throws {
        for character in "我看见你今天写得很慢" {
            let glyph = try provider.strokes(for: character)
            for (index, stroke) in glyph.strokes.enumerated() {
                XCTAssertGreaterThanOrEqual(
                    stroke.points.count, 2,
                    "「\(character)」第 \(index + 1) 笔只有 \(stroke.points.count) 个点，画不出线"
                )
            }
        }
    }

    // MARK: 坐标系（y 轴翻转）

    /// 归一化坐标必须落在字面方格附近。允许略微越界：部分字的笔画会伸出方格一点，
    /// 这是字体设计的常态，不是错误。
    func testNormalizedCoordinatesStayNearTheGlyphBox() throws {
        for character in "我看见你今天写得很慢口日上下" {
            let glyph = try provider.strokes(for: character)
            for stroke in glyph.strokes {
                for point in stroke.points {
                    XCTAssertTrue(
                        (-0.2 ... 1.2).contains(point.x) && (-0.2 ... 1.2).contains(point.y),
                        "「\(character)」有点跑到 (\(point.x), \(point.y))，远超字面方格"
                    )
                }
            }
        }
    }

    /// 反证 y 轴翻转是对的：「上」的长横视觉上在最下方，「下」的横视觉上在最上方。
    /// 归一化后 y 向下，所以「上」的长横应有较大的 y，「下」的横应有较小的 y。
    /// 若翻转写反，这两条会同时失败。
    func testVerticalDirectionIsFlippedCorrectly() throws {
        // 「上」的最后一笔是贯穿字宽的长横，位于字的底部。
        let shang = try provider.strokes(for: "上")
        let shangLongHorizontal = try XCTUnwrap(shang.strokes.max { lhs, rhs in
            lhs.horizontalExtent < rhs.horizontalExtent
        })
        XCTAssertGreaterThan(
            shangLongHorizontal.averageY, 0.6,
            "「上」的长横应落在字面下部；若落在上部说明 y 轴没翻转"
        )

        // 「下」的第一笔是贯穿字宽的横，位于字的顶部。
        let xia = try provider.strokes(for: "下")
        let xiaLongHorizontal = try XCTUnwrap(xia.strokes.max { lhs, rhs in
            lhs.horizontalExtent < rhs.horizontalExtent
        })
        XCTAssertLessThan(
            xiaLongHorizontal.averageY, 0.4,
            "「下」的横应落在字面上部；若落在下部说明 y 轴没翻转"
        )
    }

    // MARK: 排版

    private func makeLayoutConfiguration(
        glyphSize: Double = 40,
        lineWidth: Double = 400
    ) -> GlyphStrokeLayoutConfiguration {
        GlyphStrokeLayoutConfiguration(
            glyphSize: glyphSize,
            lineWidth: lineWidth,
            lineSpacingRatio: 1.6,
            origin: CGPoint(x: 20, y: 30)
        )
    }

    func testLayoutProducesStrokesInWritingOrder() throws {
        let laidOut = try GlyphStrokeLayout().layOut("十口", configuration: makeLayoutConfiguration())

        // 十 两笔 + 口 三笔 = 五笔，且按字的顺序排列。
        XCTAssertEqual(laidOut.strokeCountsPerGlyph, [2, 3])
        XCTAssertEqual(laidOut.polylines.count, 5)
        XCTAssertTrue(laidOut.uncoveredCharacters.isEmpty)
    }

    func testLayoutPlacesEachGlyphInItsOwnCell() throws {
        let configuration = makeLayoutConfiguration(glyphSize: 40, lineWidth: 4_000)
        let laidOut = try GlyphStrokeLayout().layOut("十十", configuration: configuration)

        // 两个相同的字，第二个应整体右移一个字面方格。
        let first = try XCTUnwrap(laidOut.polylines.first)
        let second = laidOut.polylines[2] // 第二个「十」的第一笔
        XCTAssertEqual(
            second.points[0].x - first.points[0].x, configuration.glyphSize,
            accuracy: 1e-9,
            "等宽排版下相邻字应正好相隔一个字面方格"
        )
        XCTAssertEqual(second.points[0].y, first.points[0].y, accuracy: 1e-9, "同一行的字基线应一致")
    }

    func testLayoutWrapsWhenTheLineIsFull() throws {
        // 行宽只够放两个字。
        let configuration = makeLayoutConfiguration(glyphSize: 40, lineWidth: 85)
        let laidOut = try GlyphStrokeLayout().layOut("一一一一", configuration: configuration)

        XCTAssertEqual(laidOut.strokeCountsPerGlyph.count, 4, "换行不该丢字")
        XCTAssertGreaterThan(laidOut.lineCount, 1)

        // 第三个字应换到下一行：y 变大，x 回到行首。
        let firstGlyph = try XCTUnwrap(laidOut.polylines.first)
        let thirdGlyph = laidOut.polylines[2]
        XCTAssertGreaterThan(thirdGlyph.averageY, firstGlyph.averageY, "换行后应更靠下")
        XCTAssertEqual(thirdGlyph.points[0].x, firstGlyph.points[0].x, accuracy: 1e-9, "换行后应回到行首")
    }

    func testExplicitNewlineStartsANewLine() throws {
        let configuration = makeLayoutConfiguration(glyphSize: 40, lineWidth: 4_000)
        let laidOut = try GlyphStrokeLayout().layOut("一\n一", configuration: configuration)

        XCTAssertEqual(laidOut.polylines.count, 2)
        XCTAssertGreaterThan(laidOut.polylines[1].averageY, laidOut.polylines[0].averageY)
        XCTAssertEqual(laidOut.polylines[1].points[0].x, laidOut.polylines[0].points[0].x, accuracy: 1e-9)
    }

    /// 缺笔顺数据的字必须被报出来，而且**位置照样往前走**——否则后面的字会挤上来，
    /// 让「少了一个字」看起来像「排版错乱」。
    func testUncoveredCharacterIsReportedAndKeepsItsSlot() throws {
        let configuration = makeLayoutConfiguration(glyphSize: 40, lineWidth: 4_000)
        let laidOut = try GlyphStrokeLayout().layOut("一，一", configuration: configuration)

        XCTAssertEqual(laidOut.uncoveredCharacters, ["，"])
        XCTAssertEqual(laidOut.polylines.count, 2, "缺字不该产出笔画")

        // 两个「一」之间空出了逗号的位置：相隔两个字面方格而不是一个。
        let gap = laidOut.polylines[1].points[0].x - laidOut.polylines[0].points[0].x
        XCTAssertEqual(gap, configuration.glyphSize * 2, accuracy: 1e-9, "缺字应留出它的位置")
    }

    /// 端到端：文字 → 字形笔画 → 排版 → 引擎 → 可播完的逐笔序列。
    /// 这一条通了，才算笔画引擎真正被用上——它自建成以来一直没有真实输入。
    func testLayoutFeedsTheStrokeEngineEndToEnd() throws {
        let glyphSize = 40.0
        let laidOut = try GlyphStrokeLayout().layOut(
            "我看见你",
            configuration: makeLayoutConfiguration(glyphSize: glyphSize, lineWidth: 4_000)
        )
        let sequence = StrokePipeline().process(
            laidOut.polylines,
            configuration: HandwritingFeel.humanizerConfiguration(referenceScale: glyphSize),
            seed: HandwritingFeel.defaultSeed
        )

        XCTAssertEqual(sequence.strokes.count, laidOut.polylines.count, "每一笔都该进入重播序列")
        XCTAssertGreaterThan(sequence.totalDuration, 0)
        XCTAssertTrue(
            StrokeReplayTimeline(sequence: sequence).frame(at: sequence.totalDuration).isComplete,
            "时间轴应能播完"
        )
    }
}

// MARK: - 测试辅助

private nonisolated extension Polyline {
    var horizontalExtent: Double {
        let xs = points.map(\.x)
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }

    var averageY: Double {
        guard !points.isEmpty else { return 0 }
        return points.reduce(0) { $0 + $1.y } / Double(points.count)
    }
}
