//
//  InkTransfer.swift
//  模块：StrokeEngine（纯逻辑层，只依赖 Foundation）
//
//  文件职责：「他用你的墨写字」的那一步算术——
//  他的回应写到百分之多少，你这一轮的笔迹就按下笔的先后被抽走百分之多少。
//
//  为什么这样设计：
//  - iPhone Duo 的一页只有护照那么大。每一轮对话都留着墨，三四轮就写满了。
//    让你的字在他回应的同时沉进纸里，一页上就永远只有当前这一段对话是墨色的；
//    更早的话留在纸上的压痕里（斜光可见），也留在往回翻的旧页里。
//  - 抽墨的顺序用你下笔的顺序：先写的先走。这样看上去是墨被「读」走的，而不是随机消失。
//  - 被打断时自然停住：他停在半截字上（决策 14），你的墨也就只少了那么多。
//    没被他用掉的墨原样留在纸上，这和「半截字最诚实」是同一个道理。
//
//  这里只有比例运算，没有经验常数。
//

import Foundation

/// 某一刻你这一轮笔迹的样子：已经被抽走的、还留着的，以及正在被抽的那个位置。
nonisolated struct InkTransfer: Equatable, Sendable {
    /// 已经被抽走的部分。渲染成压痕。
    let drained: [Polyline]
    /// 还留在纸上的墨。
    let remaining: [Polyline]
    /// 正在被抽走的那个位置。一点都没抽、或者已经抽完时没有这个位置。
    let front: Point2D?

    /// 他的回应进行到 `replyElapsed` 时，你的墨该被抽走多少（0…1）。
    /// 回应时长为 0（空回应）时不抽：没有东西是用你的墨写的。
    static func drainedFraction(replyElapsed: TimeInterval, replyDuration: TimeInterval) -> Double {
        guard replyDuration > 0, replyElapsed.isFinite else { return 0 }
        return min(1, max(0, replyElapsed / replyDuration))
    }

    static func split(_ run: InkRun, drainedFraction: Double) -> InkTransfer {
        let fraction = drainedFraction.isNaN ? 0 : min(1, max(0, drainedFraction))
        let boundary = run.totalLength * fraction
        return InkTransfer(
            drained: run.stretch(from: 0, to: boundary),
            remaining: run.stretch(from: boundary, to: run.totalLength),
            front: fraction > 0 && fraction < 1 ? run.point(at: boundary) : nil
        )
    }
}
