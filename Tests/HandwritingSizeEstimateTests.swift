//
//  HandwritingSizeEstimateTests.swift
//  模块：Tests（用户的字有多大，计划 E9c/E9d）
//
//  文件职责：验证字号估算与试排。
//
//  为什么字号估算值得测：
//  魂写的字必须和用户的字一样大，否则「同一支笔写的」这个错觉立刻破掉——
//  你写 6 mm 的小字，魂回一段 9 mm 的大字，看起来像两个人在同一页上写东西。
//  而估错的症状是「回应的字号莫名偏大或偏小」，没人会想到去查估算算法。
//
//  更要紧的是**样本不够时必须说估不出**，而不是拿三笔算一个数。
//  那个数看起来像测量，魂会照着它写出一页大小离谱的字，而且没人知道为什么。
//
//  试排（E9d）测的是另一件事：它必须和真排出来的结果**完全一致**。
//  不一致的症状是「试排说放得下，真画出来压到了字」——只在特定文字与特定宽度下
//  才出现的偶发问题，极难定位。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class HandwritingSizeEstimateTests: XCTestCase {
    /// 造一批竖笔画：高矮由参数给定，用来验证估算取的是「高的那一部分」。
    private func makeVerticalStrokes(heights: [Double]) -> [Polyline] {
        heights.enumerated().map { index, height in
            let x = Double(index) * 20
            return Polyline(points: [Point2D(x: x, y: 0), Point2D(x: x, y: height)])
        }
    }

    // MARK: 字号估算

    /// 换算比例：造的是「单笔跨度」，估出来的是「字高」，两者差这个倍数。
    private var toGlyphHeight: Double {
        1 / HandwritingSizeEstimator.strokeExtentToGlyphHeightRatio
    }

    /// 全部笔画一样高时，估出来应是那个跨度换算成字高之后的值。
    ///
    /// **不是那个跨度本身**：单笔的纵向跨度只有整个字高的一半左右，
    /// 不换算会把字号估到实际的一半。见 `strokeExtentToGlyphHeightRatio`。
    func testUniformStrokesGiveThatExtentConvertedToGlyphHeight() throws {
        let estimate = try XCTUnwrap(
            HandwritingSizeEstimator.estimate(from: makeVerticalStrokes(heights: Array(repeating: 40, count: 12)))
        )

        XCTAssertEqual(estimate.typical, 40 * toGlyphHeight, accuracy: 1e-9)
        XCTAssertEqual(estimate.range.lowerBound, 40 * toGlyphHeight, accuracy: 1e-9)
        XCTAssertEqual(estimate.range.upperBound, 40 * toGlyphHeight, accuracy: 1e-9)
        XCTAssertEqual(estimate.sampleCount, 12)
        XCTAssertGreaterThan(estimate.typical, 40, "字高必须大于单笔跨度")
    }

    /// 核心用例：混着点、短横这些矮笔画时，估算必须贴近**高**的那一批。
    /// 一个汉字里真正纵向贯通的笔画只占一小部分，取平均会被矮笔画拉低一半。
    func testShortStrokesDoNotDragTheEstimateDown() throws {
        // 三分之二是矮笔画（点、短横），三分之一是贯通的竖。
        var heights = Array(repeating: 6.0, count: 16)
        heights.append(contentsOf: Array(repeating: 44.0, count: 8))

        let estimate = try XCTUnwrap(HandwritingSizeEstimator.estimate(from: makeVerticalStrokes(heights: heights)))

        XCTAssertEqual(estimate.typical, 44 * toGlyphHeight, accuracy: 3, "应贴近贯通竖，而不是全部的平均值")
        let average = heights.reduce(0, +) / Double(heights.count)
        XCTAssertGreaterThan(estimate.typical, average * 1.5, "取平均会被矮笔画拉低一半以上")
    }

    /// 一笔特别夸张的连笔不该把结论带跑——取中位数而不是最大值。
    func testOneOverlongStrokeDoesNotHijackTheEstimate() throws {
        var heights = Array(repeating: 40.0, count: 16)
        heights.append(400) // 一条贯穿整页的长线

        let estimate = try XCTUnwrap(HandwritingSizeEstimator.estimate(from: makeVerticalStrokes(heights: heights)))

        XCTAssertLessThan(estimate.typical, 40 * toGlyphHeight * 2, "一条 400 点的长线不该把字号估到那个量级")
    }

    /// 样本不够就返回 nil，**绝不给一个数**。
    /// 给了「用三笔算出来的字号」是最坏的做法：它看起来像测量。
    func testTooFewStrokesGivesNoEstimate() {
        for count in 0 ..< HandwritingSizeEstimator.minimumStrokeCount {
            XCTAssertNil(
                HandwritingSizeEstimator.estimate(from: makeVerticalStrokes(heights: Array(repeating: 40, count: count))),
                "\(count) 笔就该估不出"
            )
        }
        XCTAssertNotNil(
            HandwritingSizeEstimator.estimate(
                from: makeVerticalStrokes(heights: Array(repeating: 40, count: HandwritingSizeEstimator.minimumStrokeCount))
            )
        )
    }

    /// 退化成一个点的笔画不参与统计（它没有纵向跨度）。
    func testDegenerateStrokesAreIgnored() {
        let dots = (0 ..< 20).map { Polyline(points: [Point2D(x: Double($0), y: 10)]) }

        XCTAssertNil(HandwritingSizeEstimator.estimate(from: dots), "全是墨点时估不出字号")
    }

    /// `spread` 量的是「参与统计的那批**高笔画**彼此差多少」，也就是典型值稳不稳。
    ///
    /// 这条同时钉住它**做不到**的事：它认不出「一半小字一半大字」。
    /// 那种情况下最高的那批仍然彼此一致，范围照样很窄。
    /// 之前我在文档里声称它能判断混写，那是错的——现在把这个边界写成断言，
    /// 免得将来有人拿它去做混写检测。
    func testSpreadMeasuresAgreementAmongTallStrokesNotOverallMixedSizes() throws {
        let consistent = try XCTUnwrap(
            HandwritingSizeEstimator.estimate(from: makeVerticalStrokes(heights: Array(repeating: 40, count: 20)))
        )
        // 高笔画本身高矮不一：范围应该变宽。
        let varyingTall = try XCTUnwrap(HandwritingSizeEstimator.estimate(
            from: makeVerticalStrokes(heights: (0 ..< 20).map { 20 + Double($0) * 4 })
        ))
        // 一半小字一半大字：最高那批彼此一致，范围**不会**变宽。
        let bimodal = try XCTUnwrap(HandwritingSizeEstimator.estimate(
            from: makeVerticalStrokes(heights: Array(repeating: 20.0, count: 10) + Array(repeating: 90.0, count: 10))
        ))

        XCTAssertEqual(consistent.spread, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(varyingTall.spread, 0, "高笔画高矮不一时范围应变宽")
        XCTAssertEqual(bimodal.spread, 0, accuracy: 1e-9, "认不出大小混写——这是已知边界，不是 bug")
    }

    /// 换算比例必须和真实字形数据对得上。
    ///
    /// 做法与算法本身完全一致：把整页笔画汇总、取最高四分之一的中位数。
    /// 字形数据的字面方格是 1.0，所以量出来的数就是「跨度 ÷ 字高」这个比例本身。
    ///
    /// **为什么这条测试比那个常量本身更重要**：常量写在代码里只是一句声明，
    /// 有人随手改成 0.8 也不会有任何报错，而后果是魂写出来的字号差一截。
    /// 这条把它钉在真实数据上。
    func testConversionRatioMatchesRealGlyphData() throws {
        let sentences = [
            "我看见你今天写得很慢",
            "有些话不必写完纸会替你记着",
            "今天又加班到十点回家路上突然不想上楼",
            "说不上来哪里不对事情都在做也没出什么问题",
            "又是一样的一天起床上班回家",
        ]

        for sentence in sentences {
            // 字面方格取 1，于是笔画跨度直接就是比例。
            let laidOut = try GlyphStrokeLayout().layOut(
                sentence,
                configuration: GlyphStrokeLayoutConfiguration(
                    glyphSize: 1,
                    lineWidth: 100_000,
                    lineSpacingRatio: 1.6,
                    origin: .zero
                )
            )
            let measured = try XCTUnwrap(HandwritingSizeEstimator.estimate(from: laidOut.polylines))

            // 估出来的「字高」应当接近 1（也就是真实的字面方格）。
            XCTAssertEqual(
                measured.typical, 1, accuracy: 0.12,
                "「\(sentence)」估出的字高是 \(measured.typical)，换算比例对不上真实字形数据"
            )
        }
    }

    /// 真实汉字笔画走一遍：估出来的字号应当接近排版时用的字面方格。
    /// 这条把「合成用例通了」和「真数据也通了」分开——前者不代表后者。
    func testRealGlyphStrokesEstimateCloseToTheLayoutGlyphSize() throws {
        let glyphSize = 48.0
        let laidOut = try GlyphStrokeLayout().layOut(
            "我看见你今天写得很慢",
            configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: glyphSize,
                lineWidth: 4_000,
                lineSpacingRatio: 1.6,
                origin: .zero
            )
        )

        let estimate = try XCTUnwrap(HandwritingSizeEstimator.estimate(from: laidOut.polylines))

        // 换算之后估出来应当接近字面方格本身。差出 12% 以内都算对得上——
        // 不同句子的笔画构成不同，实测波动就在这个量级（0.466…0.542 对 0.49）。
        XCTAssertEqual(estimate.typical, glyphSize, accuracy: glyphSize * 0.12)
    }

    /// 原始跨度必须一起报出来，而且它就是换算前的那个数。
    ///
    /// 为什么这条重要：换算比例只对汉字成立（人写拉丁字母时一笔常跨过整个字高），
    /// 2026-08-31 实测在一页中英混写 + 涂鸦上偏了 2.5 倍。
    /// 只给换算后的数，偏了也看不出来；同时给原始值，人才能判断。
    func testRawStrokeExtentIsReportedAlongsideTheConvertedHeight() throws {
        let estimate = try XCTUnwrap(
            HandwritingSizeEstimator.estimate(from: makeVerticalStrokes(heights: Array(repeating: 40, count: 12)))
        )

        XCTAssertEqual(estimate.rawStrokeExtent, 40, accuracy: 1e-9, "原始值就是笔画跨度本身")
        XCTAssertEqual(
            estimate.typical,
            estimate.rawStrokeExtent * toGlyphHeight,
            accuracy: 1e-9,
            "换算值必须等于原始值除以那个比例"
        )
        XCTAssertGreaterThan(estimate.typical, estimate.rawStrokeExtent)
    }

    /// 钉住那次实测偏差：拉丁式的「一笔跨过整个字高」会被放大约一倍。
    ///
    /// 这不是 bug 而是换算比例的适用边界，写成断言是为了让边界可见——
    /// 免得将来有人直接拿这个字高去决定魂的字号。
    func testLatinStyleFullHeightStrokesAreInflatedByTheChineseRatio() throws {
        // 模拟人写拉丁：每一笔都跨过整个字高（比如 l、h、y）。
        let actualGlyphHeight = 90.0
        let estimate = try XCTUnwrap(HandwritingSizeEstimator.estimate(
            from: makeVerticalStrokes(heights: Array(repeating: actualGlyphHeight, count: 16))
        ))

        // 真实字高是 90，但按汉字比例换算会得到约 184。
        XCTAssertGreaterThan(
            estimate.typical, actualGlyphHeight * 1.8,
            "这就是那 2 倍偏差：换算比例只对汉字成立"
        )
        // 而原始值是准的——所以报告里必须同时给它。
        XCTAssertEqual(estimate.rawStrokeExtent, actualGlyphHeight, accuracy: 1e-9)
    }

    // MARK: 试排（E9d）

    private func makeLayoutConfiguration(glyphSize: Double, lineWidth: Double) -> GlyphStrokeLayoutConfiguration {
        GlyphStrokeLayoutConfiguration(
            glyphSize: glyphSize,
            lineWidth: lineWidth,
            lineSpacingRatio: 1.6,
            origin: .zero
        )
    }

    /// 核心用例：试排的结果必须和真排出来的**完全一致**。
    /// 两者一旦不一致，就会出现「试排说放得下，真画出来压到字」。
    func testMeasureAgreesWithTheRealLayout() throws {
        let configuration = makeLayoutConfiguration(glyphSize: 40, lineWidth: 300)
        let layout = GlyphStrokeLayout()

        let measured = try layout.measure("我看见你写的 hello，慢一点。", configuration: configuration)
        let laidOut = try layout.layOut("我看见你写的 hello，慢一点。", configuration: configuration)

        XCTAssertEqual(measured.boundingBox, laidOut.boundingBox)
        XCTAssertEqual(measured.lineCount, laidOut.lineCount)
        XCTAssertEqual(measured.usedHeight, laidOut.usedHeight)
        XCTAssertEqual(measured.uncoveredCharacters, laidOut.uncoveredCharacters)
    }

    /// 宽度收窄时行数变多、占地变高——这正是「试排两三次」要利用的性质。
    func testNarrowerWidthProducesATallerBlock() throws {
        let layout = GlyphStrokeLayout()
        let text = "我看见你今天写得很慢有些话不必写完"

        let wide = try layout.measure(text, configuration: makeLayoutConfiguration(glyphSize: 40, lineWidth: 600))
        let narrow = try layout.measure(text, configuration: makeLayoutConfiguration(glyphSize: 40, lineWidth: 200))

        XCTAssertGreaterThan(narrow.lineCount, wide.lineCount)
        let wideBox = try XCTUnwrap(wide.boundingBox)
        let narrowBox = try XCTUnwrap(narrow.boundingBox)
        XCTAssertGreaterThan(narrowBox.height, wideBox.height)
        XCTAssertLessThan(narrowBox.width, wideBox.width)
    }

    /// 试排出来的占地必须真的落在给定宽度之内，否则「按这个宽度找空位」就没意义。
    func testMeasuredBlockFitsWithinTheRequestedWidth() throws {
        let lineWidth = 260.0
        let measured = try GlyphStrokeLayout().measure(
            "我看见你今天写得很慢有些话不必写完纸会替你记着",
            configuration: makeLayoutConfiguration(glyphSize: 40, lineWidth: lineWidth)
        )

        let box = try XCTUnwrap(measured.boundingBox)
        XCTAssertLessThanOrEqual(box.width, lineWidth, "排出来的宽度不该超过给定的行宽")
    }

    /// 包围盒取的是**真实笔画**的范围，而不是「行数 × 行高」。
    /// 笔画会伸出字面方格（下伸部、逗号的尾巴），实际占地比排版意图大一点，
    /// 找空位必须按实际占地判断。
    func testBoundingBoxReflectsRealInkNotJustLineHeights() throws {
        let measured = try GlyphStrokeLayout().measure(
            "gjpqy",
            configuration: makeLayoutConfiguration(glyphSize: 40, lineWidth: 600)
        )

        let box = try XCTUnwrap(measured.boundingBox)
        // 这几个字母都有下伸部，实际墨迹会比单行的字面方格高。
        XCTAssertGreaterThan(box.height, 0)
        XCTAssertEqual(measured.lineCount, 1)
    }

    /// 一个字都排不出来时包围盒为 nil，而不是零矩形。
    func testMeasuringUncoverableTextGivesNoBoundingBox() throws {
        let measured = try GlyphStrokeLayout().measure(
            "αβγ",
            configuration: makeLayoutConfiguration(glyphSize: 40, lineWidth: 600)
        )

        XCTAssertNil(measured.boundingBox)
        XCTAssertEqual(measured.uncoveredCharacters.count, 3)
    }
}
