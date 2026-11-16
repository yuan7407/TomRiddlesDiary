//
//  HapticScore.swift
//  模块：StrokeEngine（纯逻辑，只依赖 Foundation）
//
//  文件职责：把一段逐笔书写的时间轴翻译成「手里该感觉到什么」的乐谱——
//  每一笔落下有一下很轻的顿，行笔时有一层细细的沙沙感，抬笔和停顿时是空的。
//
//  为什么要有它：
//  折叠屏合起来以后屏幕朝里，看不见他在写。但决策「合上是句号」要求他在合着的本子里接着写完——
//  那一刻手是唯一还连着这本日记的东西。有了触感，「他正在里面写」这件事不看屏幕也成立。
//  摊开的时候它也在：和笔画同步的轻微触感，是屏幕上的墨第一次有了重量。
//
//  为什么乐谱在这里算、播放在界面层做：
//  「第几秒该有哪一下」完全由笔画时间轴决定，是纯计算，可以脱离设备测；
//  真正调用触感引擎的那几行依赖 CoreHaptics，放在 `Features/Book/WritingHaptics.swift`。
//  这样乐谱和画面用的是同一份 `StrokeSequence`，不可能各走各的。
//
//  强度为什么跟压感走：
//  压感是引擎自己生成的「这一笔用了多大劲」，画面上已经表现为粗细。
//  手上的轻重跟着同一个数，重的笔画又粗又沉，看到的和摸到的才是一回事。
//
//  这里不规定具体强度，只规定形状；数值在 `BookFeel`。全部**没有真机验证**。
//

import Foundation

/// 乐谱里的一下。时间从这段书写开始算起（秒）。
nonisolated struct HapticBeat: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        /// 落笔的那一下：短促。
        case tap
        /// 行笔：持续一小段。
        case drag
    }

    let kind: Kind
    let time: TimeInterval
    /// 持续多久。落笔那一下为 0。
    let duration: TimeInterval
    /// 0…1。
    let intensity: Double
    /// 0…1。越大越「脆」，越小越「闷」。
    let sharpness: Double
}

nonisolated struct HapticScoreConfiguration: Equatable, Sendable {
    /// 落笔那一下的强度范围：压感最轻到最重。
    var tapIntensity: ClosedRange<Double>
    var tapSharpness: Double
    /// 行笔沙沙感的强度范围。
    var dragIntensity: ClosedRange<Double>
    var dragSharpness: Double
    /// 短于这个时长的笔画只有落笔那一下，没有行笔（点、极短的笔）。
    var shortestDrag: TimeInterval
}

nonisolated enum HapticScore {
    /// 一段书写的整份乐谱，按时间排好。
    ///
    /// - Parameter startingAt: 从第几秒开始要（比如回应写到一半时本子才合上）。
    ///   这之前已经写完的笔不出现；正在写的那一笔只保留剩下的行笔，时间从 0 重新算。
    static func beats(
        for sequence: StrokeSequence,
        startingAt offset: TimeInterval = 0,
        configuration: HapticScoreConfiguration
    ) -> [HapticBeat] {
        var beats: [HapticBeat] = []
        // 和 `StrokeSequence.totalDuration`、`InkAgeTimeline` 用同一种累加方式，三者的时刻才对得上。
        var clock: TimeInterval = 0
        for stroke in sequence.strokes {
            let start = clock + stroke.pauseBefore
            let end = start + stroke.duration
            clock += stroke.totalDuration
            guard end > offset, !stroke.samples.isEmpty else { continue }

            let pressure = stroke.samples.reduce(0) { $0 + $1.pressure } / Double(stroke.samples.count)
            let weight = min(1, max(0, pressure))
            func scaled(_ range: ClosedRange<Double>) -> Double {
                range.lowerBound + (range.upperBound - range.lowerBound) * weight
            }

            if start >= offset {
                beats.append(HapticBeat(
                    kind: .tap,
                    time: start - offset,
                    duration: 0,
                    intensity: scaled(configuration.tapIntensity),
                    sharpness: configuration.tapSharpness
                ))
            }
            let dragStart = max(start, offset)
            let dragDuration = end - dragStart
            if stroke.duration >= configuration.shortestDrag, dragDuration > 0 {
                beats.append(HapticBeat(
                    kind: .drag,
                    time: dragStart - offset,
                    duration: dragDuration,
                    intensity: scaled(configuration.dragIntensity),
                    sharpness: configuration.dragSharpness
                ))
            }
        }
        return beats
    }
}
