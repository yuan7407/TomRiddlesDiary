//
//  ReplayPlaybackTests.swift
//  模块：Tests（重播的播放状态与落笔中断，计划 E3d）
//
//  文件职责：验证「用户新落笔打断重播」之后，重播停在正确的地方。
//
//  为什么必须测：打断错了的三种症状在界面上很难分辨——瞬间闪到写完、
//  从头重播、停在错误的字上。三者看起来都只是「动画怪怪的」，
//  但含义完全不同，而用户会以为是自己手抖。
//
//  时刻一律显式传入，不取 `.now`：依赖真实时间的测试会偶发失败，
//  而偶发失败久了就会被当成噪音忽略，那比没有测试更糟。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class ReplayPlaybackTests: XCTestCase {
    private let totalDuration: TimeInterval = 10

    // MARK: 三种状态各自的已过秒数

    func testPlayingCountsFromTheStartInstant() {
        let start = ContinuousClock.now
        let playback = ReplayPlayback.playing(since: start)

        let elapsed = playback.elapsedSeconds(
            now: start.advanced(by: .milliseconds(2500)),
            totalDuration: totalDuration
        )

        XCTAssertEqual(elapsed, 2.5, accuracy: 0.001)
    }

    func testFrozenStaysAtTheInstantItWasInterrupted() {
        let playback = ReplayPlayback.frozen(atElapsed: 3.75)

        // 时间继续走，但停住的画面不该动。
        XCTAssertEqual(
            playback.elapsedSeconds(now: ContinuousClock.now, totalDuration: totalDuration),
            3.75,
            accuracy: 0.001
        )
    }

    func testFinishedShowsTheWholeSequence() {
        let playback = ReplayPlayback.finished

        XCTAssertEqual(
            playback.elapsedSeconds(now: ContinuousClock.now, totalDuration: totalDuration),
            totalDuration,
            accuracy: 0.001
        )
    }

    /// 只有在播时才需要连续出帧。停住和写完都是静止画面，
    /// 让 TimelineView 继续跑等于白烧电。
    func testOnlyPlayingNeedsFrames() {
        XCTAssertTrue(ReplayPlayback.playing(since: .now).isPlaying)
        XCTAssertFalse(ReplayPlayback.frozen(atElapsed: 1).isPlaying)
        XCTAssertFalse(ReplayPlayback.finished.isPlaying)
    }

    // MARK: 打断

    /// 核心用例：打断必须停在**当时的进度**上，不能跳到写完，也不能回到开头。
    /// 半截字留在页上就是这条断言的可见形态（决策 14）。
    func testInterruptingMidReplayFreezesAtTheCurrentProgress() {
        let start = ContinuousClock.now
        let frozen = ReplayInterruption.freeze(
            .playing(since: start),
            now: start.advanced(by: .milliseconds(4200)),
            totalDuration: totalDuration
        )

        guard case .frozen(let elapsed) = frozen else {
            return XCTFail("在播的重播被打断后应该停住，得到的是 \(frozen)")
        }
        XCTAssertEqual(elapsed, 4.2, accuracy: 0.001)
    }

    /// 已经写完之后再落笔，不该产生一个「停在 10 秒」的中间状态。
    /// 用 finished 表达，调用方就不用再比一次时长才知道还能不能接着播。
    func testInterruptingAfterTheReplayEndedIsFinishedNotFrozen() {
        let start = ContinuousClock.now
        let result = ReplayInterruption.freeze(
            .playing(since: start),
            now: start.advanced(by: .seconds(30)),
            totalDuration: totalDuration
        )

        XCTAssertEqual(result, .finished)
    }

    /// 打断一个没在播的东西不该产生任何变化。
    /// 否则每次落笔都会重写一遍状态，把真正的那一次打断覆盖掉。
    func testInterruptingSomethingThatIsNotPlayingChangesNothing() {
        let alreadyFrozen = ReplayPlayback.frozen(atElapsed: 2)
        let alreadyFinished = ReplayPlayback.finished

        XCTAssertEqual(
            ReplayInterruption.freeze(alreadyFrozen, now: .now, totalDuration: totalDuration),
            alreadyFrozen
        )
        XCTAssertEqual(
            ReplayInterruption.freeze(alreadyFinished, now: .now, totalDuration: totalDuration),
            alreadyFinished
        )
    }

    /// 打断后停住的那一帧，交给时间轴必须得到「前面几笔画完了、当前那笔画一半」
    /// 的进度，而不是全 0 或全 1。这条把播放状态和引擎的时间轴接在一起验证，
    /// 因为两边各自对都不代表连起来对。
    func testFrozenProgressMatchesWhatTheTimelineWouldDraw() {
        let sequence = StrokeSequence(strokes: [
            makeStroke(duration: 1),
            makeStroke(duration: 1),
            makeStroke(duration: 1),
        ])
        let playback = ReplayPlayback.frozen(atElapsed: 1.5)

        let frame = StrokeReplayTimeline(sequence: sequence).frame(
            at: playback.elapsedSeconds(now: .now, totalDuration: sequence.totalDuration)
        )

        XCTAssertEqual(frame.progressByStroke[0], 1, accuracy: 0.001, "第一笔已写完")
        XCTAssertEqual(frame.progressByStroke[1], 0.5, accuracy: 0.001, "第二笔停在一半——这就是半截字")
        XCTAssertEqual(frame.progressByStroke[2], 0, accuracy: 0.001, "第三笔还没起笔")
        XCTAssertFalse(frame.isComplete)
    }

    private func makeStroke(duration: TimeInterval) -> TimedStroke {
        TimedStroke(
            samples: [
                StrokeSample(point: Point2D(x: 0, y: 0), pressure: 0.5),
                StrokeSample(point: Point2D(x: 10, y: 0), pressure: 0.5),
            ],
            duration: duration
        )
    }
}
