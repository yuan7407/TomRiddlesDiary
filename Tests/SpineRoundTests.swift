//
//  SpineRoundTests.swift
//  测试目标：对开时完整的一轮（写 → 成页 → 识别 → 魂回应 → 落点），计划 P3 的模型接线。
//
//  为什么要有这条：2026-11-17 用户在 Duo 模拟器上写了 hello，纸上显示「这一次没能把你写的话送出去」。
//  复现出来的原因是：鼠标写的字很大、横跨了书脊，他对面那一栏被你的字占着，隔着书脊放不下；
//  退回的旧排法按整张对开排、必然跨缝，翻到新一页后**又用旧排法**，于是新页上也放不下，整轮失败。
//  修法是翻页后仍然隔着书脊写（新页是空的）。单元测试只测 `composeAcrossSpine` 测不出这个——
//  故障在模型的「退回 → 翻页 → 再装配」这条链上，所以这里驱动整个模型。
//  坐标用 Duo 内屏实测值：951 × 669，折缝 x 455.5、宽 40，安全区右 84、下 34，页边距 53.5。
//

import PencilKit
import XCTest
@testable import TomRiddlesDiary

nonisolated final class SpineRoundTests: XCTestCase {
    private struct StubOracle: OracleProvider {
        let text: String
        func respond(to request: OracleRequest) async throws -> OracleReply { OracleReply(text: text) }
    }

    /// 真识别器读不出合成笔画，用固定结果顶上（同 OracleLoopTests 的理由）。
    private struct StubReader: HandwritingReading {
        func recognize(_ drawing: PKDrawing) async -> HandwritingRecognition {
            HandwritingRecognition(text: "hello", availability: RecognitionAvailability(
                requested: [Locale.Language(identifier: "en")], active: [Locale.Language(identifier: "en")],
                unavailable: [], systemProvidesRecognition: true
            ))
        }
        func availability() async -> RecognitionAvailability { await recognize(PKDrawing()).availability }
    }

    /// 一段 30 字上下的回应：原型的长度上限附近，最考验小屏。
    private let replyText = "你只写了这一个词。它是想问我什么，还是随手试试笔？"

    private let spread = SpreadGeometry(
        bounds: PageRegion(left: 0, top: 0, width: 951, height: 669),
        fold: PageRegion(left: 455.5, top: 0, width: 40, height: 669)
    )

    /// 五笔斜线，从 x0 开始往右排，占约 210 × 80。
    private func writing(from x0: CGFloat) -> PKDrawing {
        PKDrawing(strokes: (0 ..< 5).map { index in
            PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: (0 ... 8).map { step in
                let t = CGFloat(step) / 8
                return PKStrokePoint(
                    location: CGPoint(x: x0 + CGFloat(index) * 45 + t * 30, y: 230 + t * 80),
                    timeOffset: Double(t) * 0.1, size: CGSize(width: 3, height: 3),
                    opacity: 1, force: 0, azimuth: 0, altitude: .pi / 2
                )
            }, creationDate: Date()))
        })
    }

    @MainActor
    private func round(writingFrom x0: CGFloat, outerScreen: Bool = false) async -> DiaryPageModel {
        let trigger = PageCommitTrigger(configuration: PageCommitConfiguration(
            pauseMultiplier: 2, shortestWait: 0.4, longestWait: 0.6,
            terminalPunctuationRatio: 1, hoverGrace: 0, hintFraction: 0.5
        ))
        let model = DiaryPageModel(
            recognizer: StubReader(), trigger: trigger,
            oracle: StubOracle(text: replyText), composer: .forSoul()
        )
        if outerScreen {
            // 外屏 466 × 678：页边距 37.3（短边 8%），右边再让开 84 的状态栏，下边 34。
            model.pageAreaChanged(PageRegion(left: 37.3, top: 37.3, width: 466 - 37.3 * 2 - 84, height: 678 - 37.3 * 2 - 34))
        } else {
            model.pageAreaChanged(PageRegion(left: 53.5, top: 53.5, width: 951 - 53.5 - 137.5, height: 669 - 53.5 - 87.5))
            model.foldChanged(spread.fold)
            model.facingColumnsChanged(ReplyComposer.facingColumns(spread: spread, safeTop: 0, safeBottom: 34, safeTrailing: 84))
        }
        model.strokeFinished(writing(from: x0))
        for _ in 0 ..< 500 {
            if model.phase == .replying { break }
            if case .soulSilent = model.phase { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return model
    }

    @MainActor
    private func replyRegion(_ model: DiaryPageModel) throws -> PageRegion {
        let phase = model.phase
        let reply = try XCTUnwrap(model.reply, "他没写出来：\(phase)")
        return try XCTUnwrap(PageRegion.covering(reply.sequence.polylines))
    }

    @MainActor
    func testYouWriteLeftHeWritesRight() async throws {
        let model = await round(writingFrom: 100)
        XCTAssertEqual(model.phase, .replying)
        XCTAssertGreaterThan(try replyRegion(model).left, 495.5)
        XCTAssertEqual(model.pageTurnCount, 0)
    }

    @MainActor
    func testYouWriteRightHeWritesLeft() async throws {
        let model = await round(writingFrom: 560)
        XCTAssertLessThan(try replyRegion(model).right, 455.5)
    }

    /// 当时的故障：你的字横跨书脊，他对面那一栏被占，整轮失败。先修成「翻页后隔着书脊写」；
    /// P4 之后更彻底：成页时你的字被纸喝下去，对面那一栏本来就空着，连页都不用翻。
    @MainActor
    func testWritingAcrossTheSpineStillGetsAReply() async throws {
        let model = await round(writingFrom: 340)
        XCTAssertEqual(model.phase, .replying, "整轮失败了：\(model.phase)")
        XCTAssertEqual(model.pageTurnCount, 0, "你的字已被喝下去，不该再翻页")
        let region = try replyRegion(model)
        XCTAssertTrue(region.right < 455.5 || region.left > 495.5, "回应跨了书脊：\(region)")
    }

    /// 2026-11-17 用户实测：合上（外屏）写字永远没有回应。外屏能写字的宽度只有约 300 点，
    /// 旧排法按 9 毫米固定字号排、八行放不下，翻页后照样放不下。外屏也要用原型那套按长短挑字号的排法。
    @MainActor
    func testClosedOuterScreenStillGetsAReply() async throws {
        let model = await round(writingFrom: 60, outerScreen: true)
        XCTAssertEqual(model.phase, .replying, "外屏上整轮失败了：\(model.phase)")
        let region = try replyRegion(model)
        XCTAssertLessThanOrEqual(region.right, 466 - 84 + 1, "回应伸进了状态栏那一列")
    }
}
