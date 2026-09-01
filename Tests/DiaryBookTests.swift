//
//  DiaryBookTests.swift
//  模块：Tests（翻页，计划 E3f；以及魂写字的速度倍数）
//
//  文件职责：守住两件 2026-09-01 实测逼出来的事。
//
//  一、**写满一页要翻页，而不是说不出话。**
//     实测里用户和魂聊到第四轮就撞上「这一页放不下了」，然后魂完全没反应。
//     一页纸写满是必然会发生的事，不是边缘情况。
//
//  二、**翻页不能把旧页弄丢。** 翻过去之后旧页的字必须还在 `pages` 里。
//     现在虽然还没有「翻回去」的手势，数据也必须先留住——
//     等将来加手势时那些内容已经没了就来不及了。
//

import Foundation
import PencilKit
@testable import TomRiddlesDiary
import XCTest

nonisolated final class DiaryBookTests: XCTestCase {
    // MARK: 本子本身

    func testStartsWithOneBlankPage() {
        let book = DiaryBook()
        XCTAssertEqual(book.count, 1)
        XCTAssertEqual(book.currentIndex, 0)
        XCTAssertTrue(book.current.isBlank)
        XCTAssertTrue(book.isOnLastPage)
    }

    /// 在最后一页往后翻会**新建**一页；已有的页不动。
    func testTurningOnTheLastPageCreatesANewOne() {
        var book = DiaryBook()
        book.current.settledReplies = [makeReply()]

        book.turnToNextPage()

        XCTAssertEqual(book.count, 2)
        XCTAssertEqual(book.currentIndex, 1)
        XCTAssertTrue(book.current.isBlank, "新页应该是空的")
        XCTAssertFalse(book.pages[0].isBlank, "旧页的内容被弄丢了")
    }

    /// 翻回去能看到原样的旧页。
    func testTurningBackShowsTheOldPageIntact() {
        var book = DiaryBook()
        let reply = makeReply()
        book.current.settledReplies = [reply]

        book.turnToNextPage()
        book.turnToPreviousPage()

        XCTAssertEqual(book.currentIndex, 0)
        XCTAssertEqual(book.current.settledReplies, [reply])
    }

    /// 第一页往前翻不动，也不该崩。
    func testTurningBackFromTheFirstPageDoesNothing() {
        var book = DiaryBook()
        book.turnToPreviousPage()
        XCTAssertEqual(book.currentIndex, 0)
    }

    // MARK: 写满自动翻页（本文件的重点）

    /// **核心断言**：这一页放不下时自动翻页并在新页上写，而不是报「说不出话」。
    ///
    /// 夹具要造的场景很具体：**这一页放不下，但一张同样大的空白页放得下**。
    /// 第一版我把页面做得太小，结果空白页也放不下，于是它正确地报了错、测试红了——
    /// 是夹具没造对场景，不是代码错了。所以这里用「用户把整页写满」来制造拥挤。
    @MainActor
    func testAFullPageTurnsInsteadOfFallingSilent() async {
        let model = makeModel(replyText: "我是这本日记。你写下的每一页，我都记得。")
        model.pageAreaChanged(pageArea)

        model.strokeFinished(makeFullPageDrawing())

        await waitUntil("翻页并开始写") { model.phase == .replying }

        XCTAssertEqual(model.book.count, 2, "应该翻到了新的一页")
        XCTAssertEqual(model.book.currentIndex, 1)
        XCTAssertNotNil(model.reply, "翻页之后应该真的在写")
        XCTAssertEqual(model.pageTurnCount, 1, "界面靠这个计数触发翻页动画")
    }

    /// 翻页之后旧页上用户写的字还在。
    @MainActor
    func testTheUsersInkStaysOnTheOldPageAfterTurning() async {
        let model = makeModel(replyText: "我是这本日记。你写下的每一页，我都记得。")
        model.pageAreaChanged(pageArea)

        let drawing = makeFullPageDrawing()
        model.strokeFinished(drawing)
        await waitUntil("翻页") { model.book.count == 2 }

        XCTAssertEqual(model.book.pages[0].drawing.strokes.count, drawing.strokes.count,
                       "旧页上用户的字丢了")
        XCTAssertTrue(model.book.current.drawing.strokes.isEmpty, "新页应该是空白的")
    }

    /// **不许无限翻页。** 一段回应在一张全新空白纸上都放不下时，
    /// 那它长得离谱，翻一百页也一样——循环只会翻出一叠空白页。
    @MainActor
    func testAnImpossiblyLongReplyDoesNotTurnPagesForever() async {
        let model = makeModel(replyText: String(repeating: "我看见你写的每一个字。", count: 20))
        // 小到任何回应都放不下。
        model.pageAreaChanged(PageRegion(left: 0, top: 0, width: 200, height: 60))

        model.strokeFinished(makeDrawing())

        await waitUntil("如实报错") {
            if case .soulSilent = model.phase { return true }
            return false
        }
        XCTAssertLessThanOrEqual(model.book.count, 2, "翻出了一叠空白页")
        XCTAssertNil(model.reply)
    }

    // MARK: 魂写字比真人快 1.5 倍

    /// 整段时长按倍数缩短，而且**每一笔的比例不变**。
    ///
    /// 比例不变是关键：只调「书写速度」那个参数的话，每次抬落笔的固定耗时不跟着变
    /// （实测 189 笔的回应里它占约 9 秒 / 37 秒），于是整体快不到 1.5 倍，
    /// 而且落墨与停顿的比例被改了——那是在改手感，不是在改速度。
    func testTimeScalingKeepsEveryProportion() {
        let original = StrokeSequence(strokes: [
            TimedStroke(samples: makeSamples(), duration: 0.9, pauseBefore: 0),
            TimedStroke(samples: makeSamples(), duration: 0.6, pauseBefore: 0.3),
        ])

        let faster = original.timeScaled(by: 1.5)

        XCTAssertEqual(faster.totalDuration, original.totalDuration / 1.5, accuracy: 1e-9)
        for (before, after) in zip(original.strokes, faster.strokes) {
            XCTAssertEqual(after.duration, before.duration / 1.5, accuracy: 1e-9)
            XCTAssertEqual(after.pauseBefore, before.pauseBefore / 1.5, accuracy: 1e-9)
            XCTAssertEqual(after.samples, before.samples, "缩放时间不该动几何")
        }
    }

    /// 倍数为 1 时原样返回（省掉一次无意义的重建）。
    func testScalingByOneChangesNothing() {
        let original = StrokeSequence(strokes: [
            TimedStroke(samples: makeSamples(), duration: 0.5, pauseBefore: 0.1),
        ])
        XCTAssertEqual(original.timeScaled(by: 1), original)
    }

    /// 装配出来的回应真的带上了那个倍数——光有 `timeScaled` 不接上等于没做。
    func testComposedReplyIsActuallyFaster() throws {
        let glyphSize = HandwritingFeel.referenceGlyphHeightInPoints
        let page = PageRegion(left: 0, top: 0, width: 800, height: 600)
        var map = PageInkMap(
            page: page,
            resolution: PageInkMap.Resolution(
                glyphHeight: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio
            )
        )
        map.mark([])

        let text = "我是这本日记。你写下的每一页，我都记得。"
        let composed = try ReplyComposer().compose(
            text,
            glyphSize: glyphSize,
            lineSpacingRatio: PageAppearance.lineSpacingRatio,
            after: nil,
            on: map,
            seed: 7
        )

        // 同样的笔画不缩放会有多长。
        let unscaled = StrokePipeline().process(
            try GlyphStrokeLayout().layOut(text, configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: glyphSize,
                lineWidth: composed.placement.lineWidth,
                lineSpacingRatio: PageAppearance.lineSpacingRatio,
                origin: CGPoint(x: composed.placement.origin.x, y: composed.placement.origin.y)
            )).polylines,
            configuration: HandwritingFeel.humanizerConfiguration(referenceScale: glyphSize),
            seed: 7
        )

        XCTAssertEqual(
            composed.sequence.totalDuration,
            unscaled.totalDuration / HandwritingFeel.soulWritesFasterThanHumanBy,
            accuracy: 0.01,
            "装配出来的回应没有按配置的倍数加快"
        )
    }

    // MARK: 夹具

    /// 一页纸的大小。刻意选得刚好：一段 20 字的回应在**空白**的这么大一页上放得下
    /// （两行 × 75 点行高 = 150 < 200），但整页写满之后放不下。
    private var pageArea: PageRegion {
        PageRegion(left: 0, top: 0, width: 900, height: 200)
    }

    /// 用户把整页写满。横线铺满整个可书写区域，一点空隙都不留。
    private func makeFullPageDrawing() -> PKDrawing {
        let base = Date()
        var strokes: [PKStroke] = []
        var y = 4.0
        var index = 0
        while y < pageArea.height {
            let points = (0 ... 8).map { step -> PKStrokePoint in
                let t = CGFloat(step) / 8
                return PKStrokePoint(
                    location: CGPoint(x: t * pageArea.width, y: y),
                    timeOffset: Double(t) * 0.1,
                    size: CGSize(width: 3, height: 3),
                    opacity: 1,
                    force: 0,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }
            strokes.append(PKStroke(
                ink: PKInk(.pen, color: .black),
                path: PKStrokePath(
                    controlPoints: points,
                    creationDate: base.addingTimeInterval(Double(index) * 0.15)
                )
            ))
            y += 12
            index += 1
        }
        return PKDrawing(strokes: strokes)
    }

    private func makeSamples() -> [StrokeSample] {
        [
            StrokeSample(point: Point2D(x: 0, y: 0), pressure: 0.5),
            StrokeSample(point: Point2D(x: 10, y: 0), pressure: 0.5),
        ]
    }

    private func makeReply() -> ReplyOnPage {
        ReplyOnPage(
            sequence: StrokeSequence(strokes: [
                TimedStroke(samples: makeSamples(), duration: 0.4),
            ]),
            playback: .finished
        )
    }

    /// 固定返回一句话的假识别器 + 假魂，好让链路走到落点决策那一步。
    private struct StubReader: HandwritingReading {
        func recognize(_ drawing: PKDrawing) async -> HandwritingRecognition {
            HandwritingRecognition(
                text: "今天写了一点东西。",
                availability: RecognitionAvailability(
                    requested: [Locale.Language(identifier: "zh-Hans")],
                    active: [Locale.Language(identifier: "zh-Hans")],
                    unavailable: [],
                    systemProvidesRecognition: true
                )
            )
        }

        func availability() async -> RecognitionAvailability {
            await recognize(PKDrawing()).availability
        }
    }

    private struct StubOracle: OracleProvider {
        let text: String
        func respond(to request: OracleRequest) async throws -> OracleReply {
            OracleReply(text: text)
        }
    }

    @MainActor
    private func makeModel(replyText: String) -> DiaryPageModel {
        DiaryPageModel(
            recognizer: StubReader(),
            trigger: PageCommitTrigger(configuration: PageCommitConfiguration(
                pauseMultiplier: 2,
                shortestWait: 0.4,
                longestWait: 0.6,
                terminalPunctuationRatio: 1,
                hoverGrace: 0,
                hintFraction: 0.5
            )),
            oracle: StubOracle(text: replyText)
        )
    }

    private func makeDrawing(strokeCount: Int = 3) -> PKDrawing {
        let base = Date()
        return PKDrawing(strokes: (0 ..< strokeCount).map { index in
            var points: [PKStrokePoint] = []
            for step in 0 ... 8 {
                let t = CGFloat(step) / 8
                points.append(PKStrokePoint(
                    location: CGPoint(x: 20 + t * 40, y: 20 + CGFloat(index) * 20),
                    timeOffset: Double(t) * 0.1,
                    size: CGSize(width: 3, height: 3),
                    opacity: 1,
                    force: 0,
                    azimuth: 0,
                    altitude: .pi / 2
                ))
            }
            return PKStroke(
                ink: PKInk(.pen, color: .black),
                path: PKStrokePath(
                    controlPoints: points,
                    creationDate: base.addingTimeInterval(Double(index) * 0.15)
                )
            )
        })
    }

    @MainActor
    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 4,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("等不到：\(what)")
    }
}
