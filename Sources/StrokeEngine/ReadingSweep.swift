//
//  ReadingSweep.swift
//  模块：StrokeEngine（纯逻辑层，只依赖 Foundation）
//
//  文件职责：「他在读」的时间轴。给定你这一轮写了多长的墨，算出：
//  读完要多久；读到某一刻时，重新变湿的是墨线上的哪一段、有多明显。
//
//  为什么要有这一段：
//  停笔之后、回应之前有一两秒系统在识别手写、在等模型。原来这段时间纸上什么都不发生，
//  用户分不清「它在读」和「它没反应」。现在这段时间里，墨沿着你下笔的顺序重新湿一遍，
//  像有人用指尖跟着读。它没有引入新的视觉语言：湿墨本来就表示「刚刚发生」。
//
//  它只是一段固定时长的表演，**不代表识别真的进行到了哪里**——系统识别不报告进度。
//  所以它的时长由墨的长度决定，与识别实际花多久无关；读完以后如果回应还没到，
//  接下来由「笔尖停在纸上」那一点墨表示还在等（见 `BookFeel.restingBlot…`）。
//

import Foundation

nonisolated struct ReadingSweepConfiguration: Equatable, Sendable {
    /// 读的速度：每秒走过多少个字高的墨。
    let speedInGlyphHeightsPerSecond: Double
    /// 再短的话也至少读这么久，不然一闪就没了。
    let shortestDuration: TimeInterval
    /// 再长的话也最多读这么久，不然让人等。
    let longestDuration: TimeInterval
    /// 湿的那一段占整条墨线的比例，以及它的上下限（字高的倍数）。
    let tailFractionOfInk: Double
    let shortestTailInGlyphHeights: Double
    let longestTailInGlyphHeights: Double
    /// 读完以后那一段湿墨多久褪回干墨。
    let fadeOutDuration: TimeInterval

    init(
        speedInGlyphHeightsPerSecond: Double,
        shortestDuration: TimeInterval,
        longestDuration: TimeInterval,
        tailFractionOfInk: Double,
        shortestTailInGlyphHeights: Double,
        longestTailInGlyphHeights: Double,
        fadeOutDuration: TimeInterval
    ) {
        precondition(speedInGlyphHeightsPerSecond > 0, "Reading speed must be positive")
        precondition(shortestDuration > 0 && longestDuration >= shortestDuration, "Reading duration bounds are inverted")
        precondition(tailFractionOfInk > 0 && tailFractionOfInk <= 1, "Tail fraction must be within 0...1")
        precondition(shortestTailInGlyphHeights > 0 && longestTailInGlyphHeights >= shortestTailInGlyphHeights, "Tail bounds are inverted")
        precondition(fadeOutDuration > 0, "Fade-out must take some time")
        self.speedInGlyphHeightsPerSecond = speedInGlyphHeightsPerSecond
        self.shortestDuration = shortestDuration
        self.longestDuration = longestDuration
        self.tailFractionOfInk = tailFractionOfInk
        self.shortestTailInGlyphHeights = shortestTailInGlyphHeights
        self.longestTailInGlyphHeights = longestTailInGlyphHeights
        self.fadeOutDuration = fadeOutDuration
    }
}

/// 某一刻重新变湿的那一段墨。
nonisolated struct ReadingSweepWindow: Equatable, Sendable {
    /// 这一段在长墨线上的起止位置（见 `InkRun.stretch`）。`head` 是读到的地方。
    let tail: Double
    let head: Double
    /// 有多明显，0…1。读的过程中是 1，读完以后褪到 0。
    let opacity: Double
    /// 还在往前读（true），还是已经读完、正在褪（false）。只有前者画笔尖那一点反光。
    let isAdvancing: Bool
}

nonisolated struct ReadingSweep: Equatable, Sendable {
    let inkLength: Double
    let glyphHeight: Double
    let configuration: ReadingSweepConfiguration

    init(inkLength: Double, glyphHeight: Double, configuration: ReadingSweepConfiguration) {
        precondition(glyphHeight > 0, "Glyph height must be positive")
        self.inkLength = max(0, inkLength)
        self.glyphHeight = glyphHeight
        self.configuration = configuration
    }

    /// 读完要多久。
    var duration: TimeInterval {
        let natural = inkLength / (configuration.speedInGlyphHeightsPerSecond * glyphHeight)
        return min(configuration.longestDuration, max(configuration.shortestDuration, natural))
    }

    /// 连同褪色在内，这段表演一共多久。之后 `window(at:)` 返回 nil。
    var totalDuration: TimeInterval { duration + configuration.fadeOutDuration }

    /// 读开始后 `elapsed` 秒时湿的是哪一段。还没开始、已经褪完、或者没有墨时返回 nil。
    func window(at elapsed: TimeInterval) -> ReadingSweepWindow? {
        guard inkLength > 0, elapsed.isFinite, elapsed >= 0, elapsed < totalDuration else { return nil }
        let advancing = elapsed < duration
        // 起步和收尾都慢一点（三次平滑）：指尖放到纸上、读到最后一个字，都不是匀速的。纯比例运算。
        let u = min(1, elapsed / duration)
        let eased = u * u * (3 - 2 * u)
        let head = inkLength * eased
        let tailLength = min(
            configuration.longestTailInGlyphHeights * glyphHeight,
            max(configuration.shortestTailInGlyphHeights * glyphHeight, inkLength * configuration.tailFractionOfInk)
        )
        let opacity = advancing ? 1 : max(0, 1 - (elapsed - duration) / configuration.fadeOutDuration)
        return ReadingSweepWindow(tail: max(0, head - tailLength), head: head, opacity: opacity, isAdvancing: advancing)
    }
}
