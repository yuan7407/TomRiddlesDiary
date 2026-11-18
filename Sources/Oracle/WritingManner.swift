//
//  WritingManner.swift
//  模块：Oracle（「说什么」那一侧，只依赖 Foundation）
//
//  文件职责：把「他这一轮是怎么下笔的」概括成几个量，并写成一句可以交给魂的话。
//
//  为什么要做：
//  手写和打字的区别不只是字。同一句「我没事」，飞快写完和停了很久才写完，不是一回事。
//  原来交给魂的只有识别出来的文字（外加一个没有用上的笔画数），等于把手写降成了打字。
//  现在魂还知道：写了几笔、用了多久、快还是慢、中间有没有停很久、看着像字还是随手一划。
//  于是它可以说「你写得很急」——这是键盘上的聊天给不了的东西，也是这本日记像活物的地方。
//
//  发出去的是什么（隐私，必须知道）：
//  **只有这里的五个量**：笔数、秒数、快慢三档、最长停顿、形状五类。
//  不发坐标、不发笔迹图像、不发压感曲线。它们是从本机的笔迹里算出来的概括，
//  比文字本身敏感度低，但确实是比原来多发的数据。这一点已列进合并说明的「待你决定」。
//
//  形状判别里的几个数（转了多少弧度算乱划、首尾相距多近算一个圈）是判别算法本身的常数，
//  不是手感参数；写在 `WritingMannerThresholds` 里并各自说明。
//

import Foundation

nonisolated struct WritingMannerThresholds: Equatable, Sendable {
    /// 快于这个速度算写得快；慢于另一个算写得慢。单位：魂的字高/秒。
    let fastAboveGlyphHeightsPerSecond: Double
    let slowBelowGlyphHeightsPerSecond: Double
    /// 笔与笔之间停了多久才值得告诉魂（秒）。短于它的停顿人人都有。
    let pauseWorthMentioning: TimeInterval
    /// 全部墨迹短于这个长度（字高的倍数）算「只是点了一下」。
    let tapBelowGlyphHeights: Double
    /// 一笔画成的圈，墨迹至少要这么长（字高的倍数）才算圈，不然只是一个小勾。
    let loopAboveGlyphHeights: Double

    /// 一笔的首尾距离占这一笔长度的比例：高于它算直线。算法常数。
    static let straightLineRatio = 0.9
    /// 一笔的首尾距离占这一笔长度的比例：低于它（且够长）算首尾相接的圈。算法常数。
    static let closedLoopRatio = 0.22
    /// 一笔里方向累计转了多少弧度算乱划（约两圈多）。两三笔的情况门槛更高，因为正常写字也会转。算法常数。
    static let scribbleTurningSingleStroke = 14.0
    static let scribbleTurningFewStrokes = 22.0
}

nonisolated struct WritingManner: Equatable, Sendable {
    enum Pace: Equatable, Sendable { case slow, steady, fast }
    enum Shape: Equatable, Sendable { case tap, line, loop, scribble, writing }

    let strokeCount: Int
    /// 从第一笔落下到最后一笔抬起一共多久。
    let seconds: TimeInterval
    let pace: Pace
    /// 笔与笔之间最长的一次停顿。
    let longestPause: TimeInterval
    let shape: Shape
    /// 最长那次停顿值不值得说（由门槛决定）。存下来是为了让那句话不依赖配置。
    let pauseIsWorthMentioning: Bool

    /// 这一轮下笔的样子值不值得告诉魂：不像在写字（点、线、圈、乱划），或者快慢出了常态，或者停了很久。
    ///
    /// 为什么平常的一轮不发（2026-11-18 真机）：原来每一轮都发，而当时的门槛把手指的正常速度全算成
    /// 「写得很慢」，于是他每一轮都在说「你写得很慢」，你骂他他也只谈速度。平常就是平常，不必说。
    var isWorthMentioning: Bool { shape != .writing || pace != .steady || pauseIsWorthMentioning }

    /// 交给魂的那一句话。放在用户文字后面，用括号括起来；system prompt 里有一条说明它是什么。
    var sentenceForSoul: String {
        let paceWords: String = switch pace {
        case .slow: "写得很慢"
        case .steady: "不快不慢"
        case .fast: "写得很快"
        }
        let shapeWords: String = switch shape {
        case .tap: "只是在纸上点了一下"
        case .line: "画的是一条几乎笔直的线"
        case .loop: "画的是一个首尾相接的圈"
        case .scribble: "像是随手乱划"
        case .writing: "像是在写字"
        }
        let pauseWords = pauseIsWorthMentioning ? "，中间最长停了 \(Self.rounded(longestPause)) 秒" : ""
        return "（他下笔的样子：共 \(strokeCount) 笔，前后 \(Self.rounded(seconds)) 秒，\(paceWords)\(pauseWords)；\(shapeWords)。）"
    }

    /// 从这一轮的笔迹里看出下笔的样子。没有笔迹时返回 nil。
    ///
    /// - Parameter glyphHeight: 魂的字高（页面点）。速度和长度的门槛都以它为尺——
    ///   用户自己的字多大估不准（E9c 实测偏 2–2.5 倍），所以不拿它当尺。
    static func observe(
        _ traces: [PenTrace],
        glyphHeight: Double,
        thresholds: WritingMannerThresholds
    ) -> WritingManner? {
        // 按落笔时刻排序：`PKDrawing.strokes` 的顺序是叠放顺序，通常就是书写顺序，但这里不依赖这一点。
        let traces = traces.filter { !$0.samples.isEmpty }.sorted { $0.startedAt < $1.startedAt }
        guard let first = traces.first, let last = traces.last, glyphHeight > 0 else { return nil }

        var inkLength = 0.0
        var inkSeconds = 0.0
        var turning = 0.0
        var longestPause: TimeInterval = 0
        for (index, trace) in traces.enumerated() {
            inkLength += trace.length
            inkSeconds += max(0, trace.duration)
            turning += totalTurning(of: trace)
            if index > 0 {
                longestPause = max(longestPause, trace.startedAt.timeIntervalSince(traces[index - 1].endedAt))
            }
        }

        let speed = inkSeconds > 0 ? inkLength / inkSeconds / glyphHeight : 0
        let pace: Pace = speed > thresholds.fastAboveGlyphHeightsPerSecond ? .fast
            : (speed > 0 && speed < thresholds.slowBelowGlyphHeightsPerSecond) ? .slow
            : .steady

        let shape: Shape
        if inkLength < thresholds.tapBelowGlyphHeights * glyphHeight {
            shape = .tap
        } else if traces.count == 1, let start = first.start, let end = first.end {
            let closure = start.distance(to: end) / inkLength
            if closure > WritingMannerThresholds.straightLineRatio {
                shape = .line
            } else if closure < WritingMannerThresholds.closedLoopRatio,
                      inkLength > thresholds.loopAboveGlyphHeights * glyphHeight {
                shape = .loop
            } else {
                shape = turning > WritingMannerThresholds.scribbleTurningSingleStroke ? .scribble : .writing
            }
        } else if traces.count <= 3, turning > WritingMannerThresholds.scribbleTurningFewStrokes {
            shape = .scribble
        } else {
            shape = .writing
        }

        return WritingManner(
            strokeCount: traces.count,
            seconds: max(0, last.endedAt.timeIntervalSince(first.startedAt)),
            pace: pace,
            longestPause: max(0, longestPause),
            shape: shape,
            pauseIsWorthMentioning: longestPause > thresholds.pauseWorthMentioning
        )
    }

    /// 一笔里方向一共转了多少弧度（不分左右，累加绝对值）。
    private static func totalTurning(of trace: PenTrace) -> Double {
        let points = trace.samples.map(\.point)
        guard points.count > 2 else { return 0 }
        var total = 0.0
        var previousHeading: Double?
        for (a, b) in zip(points, points.dropFirst()) where a != b {
            let heading = atan2(b.y - a.y, b.x - a.x)
            if let previous = previousHeading {
                var delta = heading - previous
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                total += abs(delta)
            }
            previousHeading = heading
        }
        return total
    }

    /// 秒数只留一位小数：给魂看的是「大概多久」，不是测量值。
    private static func rounded(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds)
    }
}
