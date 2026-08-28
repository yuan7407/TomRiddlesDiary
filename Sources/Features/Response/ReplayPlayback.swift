//
//  ReplayPlayback.swift
//  模块：Features/Response（回应在时间上处于什么状态）
//
//  文件职责：描述「魂写的那段字现在播到哪儿了」，以及被用户打断时该停在哪儿。
//
//  为什么要有这个类型（计划 E3d）：
//  原先渲染层的入参是 `replayStartedAt: ContinuousClock.Instant?`，nil 的含义是
//  「不在播放，直接显示画完的样子」。这个契约表达不了**被打断**——打断的正确
//  结果是停在当时的进度上，半截字留在页上（决策 14），既不是「继续播」也不是
//  「跳到画完」。用一个可选时刻表达三种状态，第三种就只能靠调用方自己拼，
//  拼错了画面会瞬间闪到写完的状态，把「你打断了它」这个信息完全抹掉。
//  所以把三种状态显式写成三个 case。
//
//  为什么打断不回退、不清空：
//  半截字是最诚实的表达——它就是当时真实发生的事。回退等于假装没写过，
//  清空等于抹掉用户的打断有过后果。
//
//  时钟：一律用单调时钟 `ContinuousClock`（计划 D4）。用 `Date` 的话，
//  系统校正时间会让「已过多少秒」跳变，重播会瞬间闪到别的进度。
//
//  本文件不 import 任何 UI 框架：状态判断是纯逻辑，要能单独测。
//

import Foundation

/// 一段回应此刻的播放状态。
nonisolated enum ReplayPlayback: Equatable, Sendable {
    /// 正在逐笔写。起播时刻取自单调时钟。
    case playing(since: ContinuousClock.Instant)

    /// 停住了，停在「已经过了这么多秒」的那一帧上。
    /// 目前唯一的来源是用户新落笔打断（E3d）。
    case frozen(atElapsed: TimeInterval)

    /// 写完了，显示最终状态。
    case finished

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    /// 换算成时间轴要的「已过秒数」。
    /// - Parameters:
    ///   - now: 当前时刻。默认取现在；测试传固定值以免依赖真实时间。
    ///   - totalDuration: 整段回应的总时长，`finished` 时返回它。
    func elapsedSeconds(now: ContinuousClock.Instant = .now, totalDuration: TimeInterval) -> TimeInterval {
        switch self {
        case .playing(let since):
            // 单调时钟不会倒退，但 now 早于 since 仍可能因调用方传错而出现，
            // 夹到 0 比画出负进度好定位。
            return max(0, (now - since).inSeconds)
        case .frozen(let elapsed):
            return max(0, elapsed)
        case .finished:
            return totalDuration
        }
    }
}

/// 打断规则：用户新落笔时，重播该停在哪儿。
///
/// 单独成一个类型而不是写在视图里，是因为这条规则要能被测——
/// 它错了的症状（闪到写完 / 从头重播 / 停在错误的字上）在界面上很难分辨。
nonisolated enum ReplayInterruption {
    /// 算出打断后的播放状态。
    /// - Parameters:
    ///   - playback: 被打断时的状态。已经停住或已写完时原样返回，
    ///     因为「打断一个没在播的东西」不该产生任何变化。
    ///   - now: 打断发生的时刻。
    ///   - totalDuration: 整段回应的总时长。
    /// - Returns: 停在当时进度上的 `frozen`；若那一刻其实已经写完，返回 `finished`
    ///   （停在总时长上和写完是同一幅画面，用 `finished` 表达更准确，也让
    ///   「还能不能接着播」这个判断不需要再比一次时长）。
    static func freeze(
        _ playback: ReplayPlayback,
        now: ContinuousClock.Instant = .now,
        totalDuration: TimeInterval
    ) -> ReplayPlayback {
        guard case .playing(let since) = playback else { return playback }

        let elapsed = (now - since).inSeconds
        guard elapsed.isFinite, elapsed < totalDuration else { return .finished }
        return .frozen(atElapsed: max(0, elapsed))
    }
}
