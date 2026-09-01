//
//  OracleLoopTests.swift
//  模块：Tests（问魂这一环，计划 E6a）
//
//  文件职责：验证「文字交出去 → 拿回一段话 → 变成纸上的笔画」这一环。
//
//  ── 这里最要紧的不是成功路径，是失败路径 ──
//  成功路径错了，一眼就能看见（纸上没字，或者字画错地方）。
//  失败路径错了却是**无声的**：如果哪天有人为了「体验流畅」在魂接不上的时候
//  返回一段默认文字，界面看起来完全正常，用户会以为魂读了他写的东西并认真回了他，
//  而实际上那段字跟他写的毫无关系。那是 `AGENTS.md` 里「不得伪装成功」要防的头号情况。
//
//  所以下面每一种接不上都单独一条用例，断言：
//  一、`reply` 保持 nil（纸上不许出现任何字）；
//  二、阶段是 `.soulSilent(具体原因)`，而不是合成的「失败」——三种原因处置不同。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest
import PencilKit

nonisolated final class OracleLoopTests: XCTestCase {
    // MARK: 夹具

    /// 说什么就返回什么的假魂。测「拿到文字之后会发生什么」。
    private struct StubOracle: OracleProvider {
        let text: String
        func respond(to request: OracleRequest) async throws -> OracleReply {
            OracleReply(text: text)
        }
    }

    /// 永远失败的假魂，用来测每一种接不上。
    private struct FailingOracle: OracleProvider {
        let failure: OracleFailure
        func respond(to request: OracleRequest) async throws -> OracleReply {
            throw failure
        }
    }

    /// 抛一个**不是** `OracleFailure` 的错误。真实世界里网络层会抛各种东西，
    /// 模型不该因为错误类型不认识就把它吞掉。
    private struct WeirdOracle: OracleProvider {
        private struct SomethingElse: Error {}
        func respond(to request: OracleRequest) async throws -> OracleReply {
            throw SomethingElse()
        }
    }

    /// 固定返回一句话的假识别器。
    ///
    /// 为什么必须有它：真识别器读不出测试里造的合成笔画（几条横线不是字），
    /// 于是「问魂」那一环在测试里永远走不到，只会停在「这一页没读出字来」。
    /// 而这个文件要测的恰恰是那一环之后的事。
    private struct StubReader: HandwritingReading {
        let text: String?
        func recognize(_ drawing: PKDrawing) async -> HandwritingRecognition {
            HandwritingRecognition(
                text: text,
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

    private var pageArea: PageRegion {
        PageRegion(left: 40, top: 40, width: 900, height: 1_100)
    }

    /// 快到几乎立刻成页的触发器，免得测试等真实阈值。
    private var fastTrigger: PageCommitTrigger {
        PageCommitTrigger(configuration: PageCommitConfiguration(
            pauseMultiplier: 2,
            shortestWait: 0.4,
            longestWait: 0.6,
            terminalPunctuationRatio: 1,
            hoverGrace: 0,
            hintFraction: 0.5
        ))
    }

    @MainActor
    private func makeModel(
        oracle: OracleProvider?,
        recognizedText: String? = "今天写了一点东西。"
    ) -> DiaryPageModel {
        let model = DiaryPageModel(
            recognizer: StubReader(text: recognizedText),
            trigger: fastTrigger,
            oracle: oracle
        )
        model.pageAreaChanged(pageArea)
        return model
    }

    private func makeDrawing(strokeCount: Int = 3) -> PKDrawing {
        let base = Date()
        return PKDrawing(strokes: (0 ..< strokeCount).map { index in
            var points: [PKStrokePoint] = []
            for step in 0 ... 8 {
                let t = CGFloat(step) / 8
                points.append(PKStrokePoint(
                    location: CGPoint(x: 60 + t * 60, y: 100 + CGFloat(index) * 40),
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

    /// 轮询等条件成立。超时即失败——挂住不动和判断错一样要暴露。
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

    // MARK: 失败路径（本文件的重点）

    /// 没配 provider（Release 构建当前的真实状态）：纸上不许出现任何字。
    @MainActor
    func testNoProviderLeavesThePageEmptyAndSaysSo() async {
        let model = makeModel(oracle: nil)
        model.strokeFinished(makeDrawing())

        await waitUntil("如实说魂没接上") { model.phase == .soulSilent(.notConfigured) }
        XCTAssertNil(model.reply, "没配 provider 却在纸上写了字——这就是伪装成功")
    }

    /// 送不出去：同样什么都不写，而且原因要具体到能定位。
    @MainActor
    func testUnreachableSoulWritesNothing() async {
        let model = makeModel(oracle: FailingOracle(failure: .couldNotReach(detail: "测试")))
        model.strokeFinished(makeDrawing())

        await waitUntil("如实说送不出去") {
            if case .soulSilent(.couldNotReach) = model.phase { return true }
            return false
        }
        XCTAssertNil(model.reply)
    }

    /// **不认识的错误类型也不许吞掉。**
    /// 真实网络层会抛各种东西；只处理自己定义的错误类型，等于给静默失败留了个口子。
    @MainActor
    func testUnknownErrorStillSurfacesInsteadOfBeingSwallowed() async {
        let model = makeModel(oracle: WeirdOracle())
        model.strokeFinished(makeDrawing())

        await waitUntil("陌生错误也要如实报出来") {
            if case .soulSilent(.couldNotReach) = model.phase { return true }
            return false
        }
        XCTAssertNil(model.reply)
    }

    /// 每种失败必须有一句能给用户看的话，而且三种话不能一样——
    /// 合成一句会让用户按错方向去解决（接后端 / 重写 / 重试）。
    func testEveryFailureHasItsOwnSentence() {
        let sentences = Set([
            OracleFailure.notConfigured,
            .nothingToSay,
            .couldNotReach(detail: "x"),
        ].map(\.sentenceForReader))

        XCTAssertEqual(sentences.count, 3, "三种接不上应该有三句不同的话")
        XCTAssertFalse(sentences.contains { $0.isEmpty }, "每种都必须有话可说")
    }

    // MARK: 成功路径

    /// 魂说了话 → 纸上真的出现笔画，而且落在用户写的字旁边、不压字。
    @MainActor
    func testSoulReplyBecomesStrokesBesideTheUsersWriting() async {
        let model = makeModel(oracle: StubOracle(text: "就一下，也算。它平时让你靠多近？"))
        model.strokeFinished(makeDrawing())

        await waitUntil("魂开始写") { model.phase == .replying }

        let reply = try? XCTUnwrap(model.reply)
        XCTAssertNotNil(reply, "魂说了话，纸上却什么都没有")
        XCTAssertFalse(reply?.sequence.strokes.isEmpty ?? true, "笔画序列是空的")

        // 落点必须在可书写区域内。跑到纸外等于没写。
        let region = try? XCTUnwrap(PageRegion.covering(reply?.sequence.polylines ?? []))
        XCTAssertEqual(region?.isContained(in: pageArea), true, "回应画到了纸外")
    }

    /// 界面还没报过页面尺寸时，**不许猜一个页面大小硬写**——猜出来的落点会画到纸外。
    @MainActor
    func testUnknownPageSizeRefusesToGuess() async {
        // 刻意不调 pageAreaChanged。
        let model = DiaryPageModel(
            recognizer: StubReader(text: "今天写了一点东西。"),
            trigger: fastTrigger,
            oracle: StubOracle(text: "是写下来才发现的。")
        )
        model.strokeFinished(makeDrawing())

        await waitUntil("如实报送不出去而不是猜页面大小") {
            if case .soulSilent(.couldNotReach) = model.phase { return true }
            return false
        }
        XCTAssertNil(model.reply, "页面尺寸未知却还是写了——那是在猜")
    }

    /// 等回应的时候用户又落笔了：这一轮作废，不许抢他正在写的位置。
    @MainActor
    func testWritingWhileWaitingCancelsThatReply() async {
        /// 慢到足够让测试在它返回之前插一笔。
        struct SlowOracle: OracleProvider {
            func respond(to request: OracleRequest) async throws -> OracleReply {
                try? await Task.sleep(for: .milliseconds(400))
                return OracleReply(text: "是写下来才发现的。")
            }
        }

        let model = makeModel(oracle: SlowOracle())
        model.strokeFinished(makeDrawing())

        await waitUntil("已经把文字交给魂") { model.phase == .askingSoul }
        model.strokeBegan()

        // 等到魂那边肯定已经返回了。
        try? await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(model.phase, .writing, "用户在写，阶段却被回应改掉了")
        XCTAssertNil(model.reply, "用户已经重新落笔，这一轮回应还是写上去了")
    }

    // MARK: 装配（ReplyComposer）

    /// 装配出来的落点必须和真排出来的位置一致。
    /// 不一致的症状是「算的时候说放得下，画出来压到字」，只在特定文字下出现，极难定位。
    func testComposerPlacementMatchesWhatIsActuallyDrawn() throws {
        let glyphSize = HandwritingFeel.referenceGlyphHeightInPoints
        var map = PageInkMap(
            page: pageArea,
            resolution: PageInkMap.Resolution(
                glyphHeight: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio
            )
        )
        map.mark([])

        let composed = try ReplyComposer().compose(
            "又是十点。牛奶的事就算了。",
            glyphSize: glyphSize,
            lineSpacingRatio: PageAppearance.lineSpacingRatio,
            after: nil,
            on: map,
            seed: 5
        )

        XCTAssertTrue(map.canPlace(composed.placement.region))
        XCTAssertTrue(composed.placement.region.isContained(in: pageArea))
        XCTAssertTrue(composed.uncoveredCharacters.isEmpty, "这段文字应该全都写得出来")
        // 手绘化之后笔画会因为手抖略微超出排版框，所以比的是「同一个量级、位置对得上」，
        // 不是逐点相等。放宽到一个字高。
        let drawn = try XCTUnwrap(PageRegion.covering(composed.sequence.polylines))
        XCTAssertEqual(drawn.left, composed.placement.region.left, accuracy: glyphSize)
        XCTAssertEqual(drawn.top, composed.placement.region.top, accuracy: glyphSize)
    }

    /// 装配是可复现的：同一段文字、同一种子，必得同一结果。
    /// 这条守着「出问题时能重放那一次的样子」。
    func testComposingIsReproducible() throws {
        let glyphSize = HandwritingFeel.referenceGlyphHeightInPoints
        var map = PageInkMap(
            page: pageArea,
            resolution: PageInkMap.Resolution(
                glyphHeight: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio
            )
        )
        map.mark([])

        func once() throws -> ComposedReply {
            try ReplyComposer().compose(
                "这句还没写完。纸等着。",
                glyphSize: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio,
                after: nil,
                on: map,
                seed: 11
            )
        }

        XCTAssertEqual(try once(), try once())
    }

    // MARK: Mock 本身

    #if DEBUG
    /// Mock **必须诚实**：它不读用户写的字，所以同一句输入连着问两次，
    /// 回应会变（它在轮换）。这条断言的作用是把「它没有理解能力」这件事固定下来——
    /// 万一哪天有人给它加了按关键词挑答案的假聪明，这里会红。
    func testMockDoesNotPretendToUnderstand() async throws {
        let mock = MockOracleProvider(thinkingTime: .zero)
        let request = OracleRequest(text: "同一句话", strokeCount: 3)

        let first = try await mock.respond(to: request).text
        let second = try await mock.respond(to: request).text

        XCTAssertNotEqual(first, second, "同一句输入得到同一回应，说明它看起来像在理解")
    }

    /// Mock 在识别没认出东西时也要报错，不能硬回一句——
    /// 这条路径必须和真 provider 一致，否则接上真的那天才发现界面没处理。
    func testMockRefusesEmptyInput() async {
        let mock = MockOracleProvider(thinkingTime: .zero)
        do {
            _ = try await mock.respond(to: OracleRequest(text: "   \n ", strokeCount: 0))
            XCTFail("空输入应该报错")
        } catch {
            XCTAssertEqual(error as? OracleFailure, .nothingToSay)
        }
    }

    /// Mock 的每一句都应该带一个把话递回来的邀请（回应该有的形状，见 C1）。
    func testMockRepliesAllEndWithAnInvitation() async throws {
        let mock = MockOracleProvider(thinkingTime: .zero)
        let request = OracleRequest(text: "随便写点什么", strokeCount: 5)

        for _ in 0 ..< 4 {
            let text = try await mock.respond(to: request).text
            XCTAssertTrue(text.contains("？"), "「\(text)」没有把话递回来")
            // 也别太长：逐笔写按 1.5 字/秒算，40 字就要 27 秒。
            XCTAssertLessThanOrEqual(text.count, 40, "「\(text)」太长，写出来要等太久")
        }
    }
    #endif
}
