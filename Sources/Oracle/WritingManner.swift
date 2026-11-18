//
//  WritingManner.swift
//  模块：Oracle（「说什么」那一侧，只依赖 Foundation）
//
//  文件职责：看出这一轮你是不是根本没写字——只点了一下、划了一道线、画了一个圈、随手乱划——
//  并写成一句交给魂的话。写了字的时候什么都不说。
//
//  为什么只剩这一件（2026-11-18 真机后收窄，原来的决策 79 是「每轮都告诉他你写得快慢、停了多久」）：
//  · 他拿到「写得很慢 / 写得很急」，就去评论你的字：「写这么重」「这句比那句乱」「你写得很慢」。
//    用户：这类话出戏、让人困惑——你写的是话，他该回的是话。
//  · 手机上量不出压感，所谓「重」本来就是他编的。
//  所以写了字的轮次不再发这一行；没写字（一个点、一道线、一个圈、一团乱划）时才发——那时纸上没有话，
//  他只能回应你这个动作，这正是手写才有的东西。
//
//  发出去的是什么（隐私）：只有「形状」这一个结论。不发坐标、不发时间、不发笔迹（笔迹图另由 R3 发）。
//
//  形状判别里的几个数（转了多少弧度算乱划、首尾相距多近算一个圈）是判别算法本身的常数，
//  不是手感参数；写在 `WritingMannerThresholds` 里并各自说明。
//

import Foundation

nonisolated struct WritingMannerThresholds: Equatable, Sendable {
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
    enum Shape: Equatable, Sendable { case tap, line, loop, scribble, writing }

    let shape: Shape

    /// 值不值得告诉魂：只有没写字的时候。
    var isWorthMentioning: Bool { shape != .writing }

    /// 交给魂的那一句话。放在用户文字后面，用括号括起来；system prompt 里有一条说明它是什么。
    var sentenceForSoul: String {
        let shapeWords: String = switch shape {
        case .tap: "只是在纸上点了一下"
        case .line: "画了一道几乎笔直的线"
        case .loop: "画了一个首尾相接的圈"
        case .scribble: "随手乱划了几下"
        case .writing: "写了字"
        }
        return "（他下笔的样子：没有写字，\(shapeWords)。）"
    }

    /// 从这一轮的笔迹里看出是不是写了字。没有笔迹时返回 nil。
    ///
    /// - Parameter glyphHeight: 魂的字高（页面点），长度门槛以它为尺——
    ///   用户自己的字多大估不准（E9c 实测偏 2–2.5 倍），所以不拿它当尺。
    static func observe(
        _ traces: [PenTrace],
        glyphHeight: Double,
        thresholds: WritingMannerThresholds
    ) -> WritingManner? {
        let traces = traces.filter { !$0.samples.isEmpty }
        guard let first = traces.first, glyphHeight > 0 else { return nil }
        let inkLength = traces.reduce(0) { $0 + $1.length }
        let turning = traces.reduce(0) { $0 + totalTurning(of: $1) }

        if inkLength < thresholds.tapBelowGlyphHeights * glyphHeight { return WritingManner(shape: .tap) }
        if traces.count == 1, let start = first.start, let end = first.end {
            let closure = start.distance(to: end) / inkLength
            if closure > WritingMannerThresholds.straightLineRatio { return WritingManner(shape: .line) }
            if closure < WritingMannerThresholds.closedLoopRatio, inkLength > thresholds.loopAboveGlyphHeights * glyphHeight {
                return WritingManner(shape: .loop)
            }
            return WritingManner(shape: turning > WritingMannerThresholds.scribbleTurningSingleStroke ? .scribble : .writing)
        }
        if traces.count <= 3, turning > WritingMannerThresholds.scribbleTurningFewStrokes { return WritingManner(shape: .scribble) }
        return WritingManner(shape: .writing)
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
}
