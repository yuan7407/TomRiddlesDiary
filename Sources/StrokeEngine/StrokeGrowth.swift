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
//  - 2026-08-29（计划 A7）墨点的生长也搬了进来，返回类型从结构体改成两个 case 的
//    枚举。原先渲染层要自己判断 `samples.count == 1` 才知道该画点还是画线，
//    那是几何决定跑到了渲染层；而且结构体里的「已画完几段」「生长中的半段」
//    对墨点毫无意义，读的人得自己记住哪些字段该忽略。枚举让两种情况互斥，
//    渲染层照着 switch 画就行。
//

import Foundation

/// 一笔画到某个进度时的可绘制部分。
///
/// 两种情况互斥：一笔要么是一个墨点（只有一个采样点），要么是一条线。
nonisolated enum PartialStroke: Equatable, Sendable {
    /// 墨点：只有一个采样点的笔。
    /// - sizeFraction: 当前直径占最终直径的比例（0…1）。
    case dot(StrokeSample, sizeFraction: Double)

    /// 线：多个采样点的笔。
    /// - completeSegmentCount: 已经完整画完的线段数量，索引 0 ..< 这个值应整段绘制。
    ///   它同时就是正在生长那半段的起点索引。
    /// - growingTip: 正在生长的那半条线段的末端（位置与压感都已插值）。
    ///   nil 表示此刻恰好没有半条线段——要么刚好落在采样点上，要么整笔已画完。
    case line(completeSegmentCount: Int, growingTip: StrokeSample?)
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
        // 单采样点的笔就是一个墨点，没有线段可画，只有大小在长。
        guard segmentCount > 0 else {
            return .dot(stroke.samples[0], sizeFraction: dotSizeFraction(progress: progress))
        }

        let segmentProgress = min(1, progress) * Double(segmentCount)
        let completeSegments = min(segmentCount, Int(segmentProgress.rounded(.down)))
        let partial = segmentProgress - Double(completeSegments)

        // 已经画到最后一个采样点时没有半条线段；partial 恰好为 0 时同理。
        guard completeSegments < segmentCount, partial > 0 else {
            return .line(completeSegmentCount: completeSegments, growingTip: nil)
        }

        let start = stroke.samples[completeSegments]
        let end = stroke.samples[completeSegments + 1]
        // 压感与接触都要一起插值。接触漏掉的话，正在生长的笔尖会在最后一段
        // 突然从满宽跳到零宽，收笔看起来像被剪断（计划 A5）。
        let tip = StrokeSample(
            point: Point2D.interpolate(from: start.point, to: end.point, fraction: partial),
            pressure: start.pressure + (end.pressure - start.pressure) * partial,
            contact: start.contact + (end.contact - start.contact) * partial
        )

        return .line(completeSegmentCount: completeSegments, growingTip: tip)
    }

    /// 墨点当前直径占最终直径的比例（计划 A7）。
    ///
    /// 修的是什么：在此之前墨点在 `progress > 0` 的那一瞬间就以全尺寸填出来，
    /// 和整个产品的「逐笔生长」自相矛盾——一页字里别的笔都在长，只有点是啪一下出现的。
    ///
    /// 为什么是开平方而不是线性：笔尖停在纸上，墨以大致恒定的速率渗进纸里，
    /// 所以**墨量**随时间线性增加；而墨点是一片圆，面积与直径的平方成正比，
    /// 于是直径与时间的平方根成正比。观感上是「先猛地洇开、然后慢慢定住」，
    /// 这正是墨点的样子。线性增长看起来像一个圆在匀速放大，那是气球不是墨。
    ///
    /// 这里没有引入任何可调参数：关系由「墨量线性、面积∝直径²」两条推出来，
    /// 没有需要拍板的余地。
    static func dotSizeFraction(progress: Double) -> Double {
        // NaN 必须单独挡掉：它参与任何比较都返回 false，下面的夹取会静默给出
        // 一个看似正常的答案（`min(1, nan)` 在 Swift 里返回 1），墨点就会凭空全尺寸出现。
        guard !progress.isNaN else { return 0 }
        // 无穷大按「画完」处理，与线段那条路径的 `min(1, progress)` 保持一致。
        // 两条路径对同一个异常输入给出不同结果，是将来一定会咬人的那种不一致。
        return min(1, max(0, progress)).squareRoot()
    }
}
