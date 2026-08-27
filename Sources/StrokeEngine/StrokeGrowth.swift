//
//  StrokeGrowth.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：算出「一笔在某个进度下应该画到哪里」——完整画完了几段，
//  以及正在生长的那半条线段的末端在哪、压感多少。
//
//  设计原因：
//  - 这段几何是「逐笔生长」观感的实现核心。没有「半条线段」，笔画就是一个采样点
//    一个采样点地跳出来，不是长出来。
//  - 2026-08-27（计划 D4/D6）从 `HandwritingReplayView` 提出来，理由有两条：
//    一是它是纯数学，放在视图的私有方法里测不到，而视觉缺陷恰好都藏在这里；
//    二是「渲染层不生成任何手感数据」这条边界要求几何归引擎，视图只负责描边。
//  - 只提取线段几何，不把「单点墨点画多大」一起搬走：那是渲染决定，
//    且计划 A7 会改它的行为（现在墨点是瞬间全尺寸出现，应该改成长出来）。
//

import Foundation

/// 一笔画到某个进度时的可绘制部分。
nonisolated struct PartialStroke: Equatable, Sendable {
    /// 已经完整画完的线段数量。索引 0 ..< 这个值的线段应整段绘制。
    let completeSegmentCount: Int

    /// 正在生长的那半条线段的末端（位置与压感都已插值）。
    /// nil 表示此刻恰好没有半条线段——要么刚好落在采样点上，要么整笔已画完。
    let growingTip: StrokeSample?

    /// 半条线段的起点索引，也就是 `completeSegmentCount`。
    /// 单独取个名字是为了让渲染层读起来不必推理。
    var growingSegmentStartIndex: Int { completeSegmentCount }
}

nonisolated enum StrokeGrowth {
    /// 算出一笔在给定进度下的可绘制部分。
    /// - Parameters:
    ///   - stroke: 已手绘化的一笔。
    ///   - progress: 0…1 的绘制进度。超过 1 按 1 处理；小于等于 0 表示还没落笔。
    /// - Returns: 可绘制部分；返回 nil 表示这一笔此刻不该画出任何东西。
    ///
    /// - Note: 进度按采样点索引推进。重采样已把采样点铺成等弧长，
    ///   因此索引推进等价于沿笔画弧长匀速推进。
    ///   等计划 A3 加入起收笔加减速时，缓动应该在时间轴那一侧做，
    ///   传进来的 progress 已经是缓动后的值，本函数不必改。
    static func partial(of stroke: TimedStroke, progress: Double) -> PartialStroke? {
        guard progress > 0, !stroke.samples.isEmpty else { return nil }

        let segmentCount = stroke.samples.count - 1
        // 单采样点的笔（一个墨点）没有线段可画，交给渲染层按墨点处理。
        guard segmentCount > 0 else {
            return PartialStroke(completeSegmentCount: 0, growingTip: nil)
        }

        let segmentProgress = min(1, progress) * Double(segmentCount)
        let completeSegments = min(segmentCount, Int(segmentProgress.rounded(.down)))
        let partial = segmentProgress - Double(completeSegments)

        // 已经画到最后一个采样点时没有半条线段；partial 恰好为 0 时同理。
        guard completeSegments < segmentCount, partial > 0 else {
            return PartialStroke(completeSegmentCount: completeSegments, growingTip: nil)
        }

        let start = stroke.samples[completeSegments]
        let end = stroke.samples[completeSegments + 1]
        let tip = StrokeSample(
            point: Point2D.interpolate(from: start.point, to: end.point, fraction: partial),
            pressure: start.pressure + (end.pressure - start.pressure) * partial
        )

        return PartialStroke(completeSegmentCount: completeSegments, growingTip: tip)
    }
}
