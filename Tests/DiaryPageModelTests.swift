//
//  DiaryPageModelTests.swift
//  模块：Tests（一页日记的状态机，计划 E3c/E3d）
//
//  文件职责：验证成页倒计时这条**循环**真的会跑到成页，以及落笔真的会把它掐掉。
//
//  为什么单独测这一层：
//  `PageCommitTriggerTests` 测的是「给定已经等了多少秒，该不该成页」——那是纯函数。
//  但纯函数对了不代表循环对：循环可能根本没启动、可能读到过期的状态、
//  可能取消之后又自己跑起来。这几种错法的共同症状是「在模拟器上手写完什么都不发生」，
//  而那和「阈值太长」「识别没返回」长得一模一样，靠肉眼分不出来。
//
//  测试用的阈值刻意压到 0.1 秒量级：这里验证的是**流程**，不是手感。
//  用产品那套（3 秒起）会让每条用例都等好几秒，慢测试最后一定会被跳过。
//
//  识别用的是系统真实的识别器，没有替身。理由：模拟器上英文模型确实可用
//  （`HandwritingRecognizerTests` 已确认），而这里断言的是阶段有没有走到，
//  不是认出了什么。为此造一个替身反而会让测试离真实链路更远。
//

import Foundation
import PencilKit
@testable import TomRiddlesDiary
import XCTest

//  为什么类本身是 nonisolated 而测试方法是 @MainActor：
//  Swift 6 下给 XCTestCase 子类整体标 @MainActor 会与它继承来的 nonisolated
//  初始化方法冲突（编译器直接报错）。所以隔离标在需要它的方法上。
//
nonisolated final class DiaryPageModelTests: XCTestCase {
    /// 把阈值压到半秒量级，让流程用例跑得快。
    ///
    /// 为什么不压得更短：预告期（这里是 0.4 × 0.5 = 0.2 秒）必须明显长于
    /// 倒计时的检查间隔（0.1 秒），否则一次轮询就跨过了整个预告期，
    /// 用户根本看不到「可撤销」的提示。这条约束对产品配置同样成立，
    /// 由 `PageCommitTriggerTests` 的 `testHintWindowOutlastsTheCheckInterval` 守着。
    ///
    /// `terminalPunctuationRatio` 取 1（不加速）：这里不测标点信号，
    /// 留着它会让期望时长取决于识别认出了什么，那是不该有的耦合。
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
    private func makeModel() -> DiaryPageModel {
        DiaryPageModel(trigger: fastTrigger)
    }

    /// 造一笔。落笔时刻显式传入，这样「哪一笔属于哪一轮」可以精确断言。
    private func makeStroke(startingAt start: Date, row: Int = 0) -> PKStroke {
        var points: [PKStrokePoint] = []
        for step in 0 ... 8 {
            let t = CGFloat(step) / 8
            points.append(PKStrokePoint(
                location: CGPoint(x: 40 + t * 50, y: 80 + CGFloat(row) * 40),
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
            path: PKStrokePath(controlPoints: points, creationDate: start)
        )
    }

    /// 造一页手写：默认三笔，笔间停顿 0.05 秒，好让中位停顿量得出来。
    private func makeDrawing(strokeCount: Int = 3) -> PKDrawing {
        let base = Date()
        return PKDrawing(strokes: (0 ..< strokeCount).map { index in
            makeStroke(startingAt: base.addingTimeInterval(Double(index) * 0.15), row: index)
        })
    }

    private func makeSequence(totalDuration: TimeInterval) -> StrokeSequence {
        StrokeSequence(strokes: [TimedStroke(
            samples: [
                StrokeSample(point: Point2D(x: 0, y: 0), pressure: 0.5),
                StrokeSample(point: Point2D(x: 20, y: 0), pressure: 0.5),
            ],
            duration: totalDuration
        )])
    }

    /// 轮询等待某个条件成立。超时即失败——挂住不动和判断错一样要暴露。
    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("等待超时：\(description)")
    }

    // MARK: E3c 成页触发

    @MainActor
    func testBlankPageHasNothingNew() async {
        let model = makeModel()

        XCTAssertEqual(model.phase, .nothingNew)
        model.strokeFinished(PKDrawing())

        XCTAssertEqual(model.phase, .nothingNew, "一笔都没有就没有什么可回应的")
        // 空白页不该起倒计时。等到远超阈值仍应是空白。
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.phase, .nothingNew)
    }

    /// 核心用例：抬笔之后不再写，倒计时必须一路走到成页。
    /// 这条覆盖的是「手写完什么都不发生」这个最坏的失败。
    @MainActor
    func testCountdownReachesCommitAfterTheWriterStops() async {
        let model = makeModel()

        model.strokeFinished(makeDrawing())
        XCTAssertEqual(model.phase, .waiting, "抬笔后先进入等待")

        await waitUntil("成页并读懂这一页") { model.phase == .awaitingSoul }
        XCTAssertNotNil(model.recognition, "成页时必须已经识别过整页")
    }

    /// 预告期必须真的出现过，否则「可撤销」这件事用户永远看不到。
    @MainActor
    func testHintPhaseHappensBeforeCommit() async {
        let model = makeModel()
        var sawHint = false

        model.strokeFinished(makeDrawing())
        await waitUntil("经过预告期后成页") {
            if case .aboutToRespond = model.phase { sawHint = true }
            return model.phase == .awaitingSoul
        }

        XCTAssertTrue(sawHint, "成页之前必须先给过可撤销的预告")
    }

    /// 落笔即取消：笔在纸上时不许成页，无论等多久。
    @MainActor
    func testNewStrokeCancelsTheCountdown() async {
        let model = makeModel()

        model.strokeFinished(makeDrawing())
        model.strokeBegan()
        XCTAssertEqual(model.phase, .writing)

        // 远超阈值（0.2 秒上限）之后仍在写。
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.phase, .writing, "笔还在纸上，不能成页")
    }

    /// 抬笔、又落笔、又抬笔：倒计时要从最后一次抬笔重新开始，
    /// 而不是接着上一轮的进度——否则连续写字时会在中途成页。
    @MainActor
    func testEachLiftRestartsTheCountdown() async {
        let model = makeModel()

        model.strokeFinished(makeDrawing())
        try? await Task.sleep(for: .milliseconds(120))
        model.strokeBegan()
        model.strokeFinished(makeDrawing(strokeCount: 4))
        XCTAssertEqual(model.phase, .waiting, "新的一轮等待从头开始")

        await waitUntil("重新等待后成页") { model.phase == .awaitingSoul }
    }

    /// 回归守卫：一整轮等待期只许发布个位数次阶段变化。
    ///
    /// 这条是 2026-08-29「用户笔画写完就消失」那个 bug 的守卫。当时倒计时每 0.1 秒
    /// 往 `phase` 写一次值、值没变也写，界面每秒重建十次，PencilKit 的墨迹层被反复
    /// 标记为需要重绘却一直没重绘，墨就没了。数据全在、纸色也在，只有墨看不见——
    /// 这种症状极难从界面反推原因，所以必须有测试盯着「发布次数」这个可测量的量。
    @MainActor
    func testPhaseIsPublishedOnlyWhenItActuallyChanges() async {
        let model = makeModel()

        model.strokeFinished(makeDrawing())
        await waitUntil("成页") { model.phase == .awaitingSoul }

        // 一轮的合法变化是：等待 → 预告 → 读懂 → 已收下，也就是 4 次。
        // 留一点余量，但绝不能是几十次。
        XCTAssertLessThanOrEqual(
            model.publishedPhaseCount,
            6,
            "等待期内重复发布同一个阶段会让界面每秒重建十次，笔画会从纸上消失"
        )
    }

    /// 阈值必须由本页节奏算出来，写得慢的人阈值更长。
    /// 这条防的是「模型层没把节奏喂给触发器」——那种情况下阈值会恒为上限，
    /// 界面上完全看不出来。
    @MainActor
    func testWaitLengthReflectsTheMeasuredRhythm() {
        let model = DiaryPageModel()
        let unmeasured = model.commitWaitLength

        model.strokeFinished(makeDrawing())
        let measured = model.commitWaitLength

        XCTAssertEqual(unmeasured, InteractionSettings.pageCommit.longestWait, accuracy: 0.001,
                       "还没写过时取上限")
        XCTAssertLessThan(measured, unmeasured, "量到节奏之后阈值应该由节奏决定")
    }

    // MARK: E3e 只处理这一轮写的内容

    /// 成页之后如果只是把旧内容留在页上、没有写新东西，就不该再成页一次。
    /// 否则接上 Oracle 之后魂会把同一段话反复回应（还反复花钱）。
    @MainActor
    func testCommittedContentIsNotOfferedAgain() async {
        let model = makeModel()
        let page = makeDrawing()

        model.strokeFinished(page)
        await waitUntil("第一轮成页") { model.phase == .awaitingSoul }

        // 同一份内容再抬一次笔（例如用户点了一下又拿开，页面没变）。
        model.strokeBegan()
        model.strokeFinished(page)

        XCTAssertEqual(model.phase, .nothingNew, "没有新内容就不该有新一轮")
        // 等到远超阈值也不该成页。
        try? await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(model.phase, .nothingNew)
    }

    /// 成页之后接着写，必须开始新的一轮，而且读到的只有新写的那部分。
    @MainActor
    func testWritingAfterCommitStartsANewRoundWithOnlyTheNewStrokes() async {
        let model = makeModel()
        let firstRound = makeDrawing(strokeCount: 3)

        model.strokeFinished(firstRound)
        await waitUntil("第一轮成页") { model.phase == .awaitingSoul }

        // 页面上原有三笔，再加两笔新的（落笔时刻明显更晚）。
        let base = Date().addingTimeInterval(60)
        let extra = (0 ..< 2).map { index in
            makeStroke(startingAt: base.addingTimeInterval(Double(index) * 0.2))
        }
        model.strokeBegan()
        model.strokeFinished(PKDrawing(strokes: firstRound.strokes + extra))

        XCTAssertEqual(model.phase, .waiting, "有新内容就要开始新一轮")
        XCTAssertEqual(model.reading?.polylines.count, 2, "读到的应该只有新写的两笔，不含已收下的三笔")
    }

    // MARK: E4b 落笔前告知识别能力

    /// 识别能力必须能在**没有写任何东西之前**就查出来，否则「写之前告知」做不到。
    @MainActor
    func testRecognitionAvailabilityIsKnownBeforeAnyWriting() async {
        let model = makeModel()
        XCTAssertNil(model.recognitionAvailability, "还没查过")

        await model.loadRecognitionAvailability()

        let availability = model.recognitionAvailability
        XCTAssertNotNil(availability, "查完之后必须有结论，不能是 nil 含糊过去")
        XCTAssertEqual(model.phase, .nothingNew, "查询不该改变页面阶段")
        XCTAssertEqual(availability?.requested, InteractionSettings.recognitionLanguages)
    }

    // MARK: E3d 落笔中断

    @MainActor
    func testNewStrokeFreezesAPlayingReply() {
        let model = makeModel()
        model.beginReply(makeSequence(totalDuration: 10))
        XCTAssertEqual(model.reply?.playback.isPlaying, true)

        model.strokeBegan()

        guard case .frozen = model.reply?.playback else {
            return XCTFail("用户新落笔应该让重播停住，得到的是 \(String(describing: model.reply?.playback))")
        }
    }

    /// 停住之后再落笔不该重置成别的状态——半截字要一直留在页上。
    @MainActor
    func testFrozenReplyStaysFrozenOnFurtherStrokes() {
        let model = makeModel()
        model.beginReply(makeSequence(totalDuration: 10))
        model.strokeBegan()
        let firstFreeze = model.reply?.playback

        model.strokeFinished(makeDrawing())
        model.strokeBegan()

        XCTAssertEqual(model.reply?.playback, firstFreeze, "打断只发生一次，之后画面不再变")
    }
}
