//
//  PageCommitTriggerTests.swift
//  模块：Tests（成页触发，计划 E3c）
//
//  文件职责：验证「这一页写完了吗」这个判断的行为，尤其是它**不会**做的事。
//
//  为什么这些用例值得写：
//  这张纸上没有按钮，成页判断错了没有任何补救入口。而它的两种错法在界面上
//  长得完全不一样但都很难定位——
//  早触发：你还在想下一个字，纸就自己回应了；
//  漏触发：你写完了放下笔，纸永远没反应，而且你不知道该怎么让它反应。
//  所以这里重点测三件事：阈值真的跟着用户自己的节奏走（不是固定秒数）、
//  加速与延长信号只在该起作用时起作用、以及**任何情况下都终究会成页**。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class PageCommitTriggerTests: XCTestCase {
    /// 测试用配置：数值取整，方便手算期望值，不依赖产品配置的具体取值。
    /// 产品配置本身另有一条用例单独校验它是合法的。
    private let configuration = PageCommitConfiguration(
        pauseMultiplier: 5,
        shortestWait: 1,
        longestWait: 10,
        terminalPunctuationRatio: 0.5,
        hoverGrace: 2,
        hintFraction: 0.5
    )

    private var trigger: PageCommitTrigger {
        PageCommitTrigger(configuration: configuration)
    }

    private func rhythm(pauses: [TimeInterval]) -> WritingRhythm {
        WritingRhythm(
            pauses: pauses,
            totalDuration: pauses.reduce(0, +),
            inkDuration: 0
        )
    }

    // MARK: 阈值跟着用户自己的节奏走

    /// 核心用例：同一个「等了 2 秒」，对写得快的人应该已经算写完，
    /// 对写得慢的人还不算。固定秒数做不到这件事，这就是不用固定秒数的理由。
    func testWaitLengthFollowsTheWritersOwnPace() {
        let fast = trigger.waitLength(
            rhythm: rhythm(pauses: [0.2, 0.2, 0.2]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )
        let slow = trigger.waitLength(
            rhythm: rhythm(pauses: [1.5, 1.5, 1.5]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )

        // 0.2 × 5 = 1.0，正好落在下限上；1.5 × 5 = 7.5。
        XCTAssertEqual(fast, 1.0, accuracy: 0.001)
        XCTAssertEqual(slow, 7.5, accuracy: 0.001)
        XCTAssertLessThan(fast, slow, "写得快的人阈值必须更短")
    }

    /// 中位数而不是平均值：一次走神不该把阈值拉到荒谬。
    /// （中位数本身由 WritingRhythmTests 验证，这里验证触发器真的用的是它。）
    func testOneLongPauseDoesNotInflateTheThreshold() {
        let withOutlier = trigger.waitLength(
            rhythm: rhythm(pauses: [0.4, 0.4, 0.4, 0.4, 53]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )

        XCTAssertEqual(withOutlier, 2.0, accuracy: 0.001, "0.4 × 5 = 2.0，53 秒那次不算")
    }

    func testWaitLengthIsClampedToShortestAndLongest() {
        let tooFast = trigger.waitLength(
            rhythm: rhythm(pauses: [0.01, 0.01, 0.01]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )
        let tooSlow = trigger.waitLength(
            rhythm: rhythm(pauses: [30, 30, 30]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )

        XCTAssertEqual(tooFast, configuration.shortestWait, accuracy: 0.001)
        XCTAssertEqual(tooSlow, configuration.longestWait, accuracy: 0.001)
    }

    /// 只写了一笔时量不出节奏。此时取上限：宁可让人多等，也绝不能不响。
    func testUnmeasuredRhythmWaitsTheLongestRatherThanTheShortest() {
        let single = trigger.waitLength(
            rhythm: .empty,
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )

        XCTAssertEqual(single, configuration.longestWait, accuracy: 0.001)
    }

    // MARK: 加速与延长信号

    func testTerminalPunctuationShortensTheWait() {
        let plain = trigger.waitLength(
            rhythm: rhythm(pauses: [1, 1, 1]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )
        let punctuated = trigger.waitLength(
            rhythm: rhythm(pauses: [1, 1, 1]),
            endsWithTerminalPunctuation: true,
            isPencilHovering: false
        )

        XCTAssertEqual(plain, 5.0, accuracy: 0.001)
        XCTAssertEqual(punctuated, 2.5, accuracy: 0.001)
    }

    /// 标点最多把等待压到下限，不能压到 0——句号之后完全可能继续写下一句。
    func testTerminalPunctuationNeverGoesBelowTheShortestWait() {
        let punctuated = trigger.waitLength(
            rhythm: rhythm(pauses: [0.3, 0.3, 0.3]),
            endsWithTerminalPunctuation: true,
            isPencilHovering: false
        )

        XCTAssertEqual(punctuated, configuration.shortestWait, accuracy: 0.001)
    }

    func testHoverExtendsTheWaitByABoundedGrace() {
        let idle = trigger.waitLength(
            rhythm: rhythm(pauses: [1, 1, 1]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )
        let hovering = trigger.waitLength(
            rhythm: rhythm(pauses: [1, 1, 1]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: true
        )

        XCTAssertEqual(hovering - idle, configuration.hoverGrace, accuracy: 0.001)
    }

    /// 最要紧的一条：悬停**不能**让成页永远不发生。
    /// 只要等得够久（上限 + 宽限），无论笔悬不悬着都必须成页。
    func testHoverCannotPostponeCommitForever() {
        let ceiling = configuration.longestWait + configuration.hoverGrace

        let decision = trigger.decide(
            sinceLastLift: ceiling,
            rhythm: rhythm(pauses: [30, 30, 30]),
            endsWithTerminalPunctuation: false,
            isPencilHovering: true
        )

        XCTAssertEqual(decision, .commit, "等到上限加宽限之后，悬停也拦不住成页")
    }

    // MARK: 判断的三段

    func testDecisionProgressesThroughWaitingHintAndCommit() {
        let pace = rhythm(pauses: [1, 1, 1]) // 阈值 5 秒，预告期是最后 2.5 秒

        XCTAssertEqual(
            trigger.decide(
                sinceLastLift: 1,
                rhythm: pace,
                endsWithTerminalPunctuation: false,
                isPencilHovering: false
            ),
            .keepWaiting
        )

        guard case .aboutToCommit(let remaining, let imminence) = trigger.decide(
            sinceLastLift: 4,
            rhythm: pace,
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        ) else {
            return XCTFail("等到 4 秒时应该进入预告期")
        }
        XCTAssertEqual(remaining, 1, accuracy: 0.001)
        // 预告期 2.5 秒，还剩 1 秒 → 走过了 60%。
        XCTAssertEqual(imminence, 0.6, accuracy: 0.001)

        XCTAssertEqual(
            trigger.decide(
                sinceLastLift: 5,
                rhythm: pace,
                endsWithTerminalPunctuation: false,
                isPencilHovering: false
            ),
            .commit
        )
    }

    /// 预告的浓度必须从 0 长到 1，否则渗墨会一出现就是全尺寸（跟 A7 的墨点同一类毛病）。
    func testImminenceRunsFromZeroToOneAcrossTheHintWindow() {
        let pace = rhythm(pauses: [1, 1, 1]) // 阈值 5 秒，预告期从第 2.5 秒开始

        guard case .aboutToCommit(_, let atStart) = trigger.decide(
            sinceLastLift: 2.5,
            rhythm: pace,
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        ) else {
            return XCTFail("2.5 秒正好是预告期的起点")
        }
        guard case .aboutToCommit(_, let atEnd) = trigger.decide(
            sinceLastLift: 4.999,
            rhythm: pace,
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        ) else {
            return XCTFail("成页前的最后一刻仍在预告期")
        }

        XCTAssertEqual(atStart, 0, accuracy: 0.001)
        XCTAssertGreaterThan(atEnd, 0.99)
    }

    /// 时钟异常给出的非有限值不能被当成「等了无限久」而凭空触发一次回应。
    func testNonFiniteElapsedTimeNeverCommits() {
        for broken in [TimeInterval.infinity, .nan] {
            XCTAssertEqual(
                trigger.decide(
                    sinceLastLift: broken,
                    rhythm: rhythm(pauses: [1, 1, 1]),
                    endsWithTerminalPunctuation: false,
                    isPencilHovering: false
                ),
                .keepWaiting,
                "非有限的经过时间必须当成刚抬笔"
            )
        }
    }

    // MARK: 终止标点识别

    func testTerminalPunctuationDetection() {
        for ending in ["今天很累。", "why?", "Stop!", "算了…", "真的吗？", "OK."] {
            XCTAssertTrue(
                PageCommitTrigger.endsWithTerminalPunctuation(ending),
                "\(ending) 应该算句子结束"
            )
        }

        for ending in ["我在想", "hello", "还有一件事，", "列表：", ""] {
            XCTAssertFalse(
                PageCommitTrigger.endsWithTerminalPunctuation(ending),
                "\(ending) 不该算句子结束"
            )
        }

        XCTAssertFalse(PageCommitTrigger.endsWithTerminalPunctuation(nil), "没有识别结果时信号失效")
    }

    /// 句号可能在引号里面。只看最后一个字符会看到引号而漏掉句号。
    func testTerminalPunctuationLooksPastClosingMarks()
    {
        XCTAssertTrue(PageCommitTrigger.endsWithTerminalPunctuation("他说「我知道了。」"))
        XCTAssertTrue(PageCommitTrigger.endsWithTerminalPunctuation("done.\n  "))
        XCTAssertFalse(PageCommitTrigger.endsWithTerminalPunctuation("（未完"))
    }

    // MARK: 产品配置本身

    /// 产品实际用的那套数值必须是合法配置。
    /// `PageCommitConfiguration` 的构造校验会在非法时直接崩，这条用例保证
    /// 那个崩溃发生在测试里而不是用户手里。
    func testShippingConfigurationIsValid() {
        let shipping = InteractionSettings.pageCommit

        XCTAssertGreaterThan(shipping.pauseMultiplier, 1)
        XCTAssertGreaterThan(shipping.shortestWait, 0)
        XCTAssertGreaterThanOrEqual(shipping.longestWait, shipping.shortestWait)
        XCTAssertTrue(shipping.terminalPunctuationRatio > 0 && shipping.terminalPunctuationRatio <= 1)
        XCTAssertGreaterThanOrEqual(shipping.hoverGrace, 0)
        XCTAssertTrue(shipping.hintFraction > 0 && shipping.hintFraction <= 1)
    }

    /// 预告期必须明显长于倒计时的检查间隔。
    ///
    /// 为什么要机器守着这条：两组数值分别在 `InteractionSettings` 的两个常量里，
    /// 单看都合理。但最短的预告期是 `shortestWait × hintFraction`，
    /// 一旦它短于检查间隔，一次轮询就跨过整个预告期，「可撤销的预告」就消失了。
    /// 症状是提示时有时无，不会报错，也不会有人想到去查那个间隔。
    /// 这条约束 2026-08-29 是被 `DiaryPageModelTests` 撞出来的，不是事先想到的。
    func testHintWindowOutlastsTheCheckInterval() {
        let shipping = InteractionSettings.pageCommit
        let shortestHintWindow = shipping.shortestWait * shipping.hintFraction
        let checkInterval = InteractionSettings.pageCommitCheckInterval.inSeconds

        XCTAssertGreaterThan(
            shortestHintWindow,
            checkInterval * 3,
            "最短的预告期要能容下好几次轮询，否则提示会被整个跳过"
        )
    }

    /// 用 2026-08-28 实测的停顿中位数（0.51 秒）走一遍产品配置，
    /// 确认算出来的阈值落在「比写字过程中的停顿长、比放下笔的时间短」这个区间里。
    /// 这不是精度校准（真机数据还没有），只是防止改配置时把量级改错。
    func testShippingConfigurationLandsInAPlausibleRangeForMeasuredPace() {
        let measured = rhythm(pauses: [0.51, 0.51, 0.51])
        let wait = PageCommitTrigger().waitLength(
            rhythm: measured,
            endsWithTerminalPunctuation: false,
            isPencilHovering: false
        )

        XCTAssertGreaterThan(wait, 1.5, "不能短到书写过程中的停顿都能触发")
        XCTAssertLessThan(wait, 6, "不能长到让人以为纸是死的")
    }
}
