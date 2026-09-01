//
//  StrokePipeline.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：笔画生成的唯一入口，把有序向量交给 Humanizer 并产出可重播序列。
//
//  设计原因：
//  - 2026-08-25 删除位图路线后，这里不再需要 StrokeSourcePayload 枚举，入口直接收 [Polyline]。
//    原因：只剩一种源时，枚举只会假装“可切换”，反而掩盖真实实现。
//  - 仍保留 Pipeline 这一层而不是让上层直接调用 Humanizer：接入字形笔画与排版层后，
//    格式转换和参数装配都应集中在这里，调用方不必改动。
//  - 参数与种子都不给默认值（2026-08-27，计划 D1/D2）。原因：参数是尺度相关的，
//    默认值只在某个特定画布尺寸下成立；而同一个默认种子曾在这里和 Humanizer
//    各写一份，属于同一参数两套值。现在唯一的生产来源是 `HandwritingFeel`。
//

nonisolated struct StrokePipeline: Sendable {
    private let humanizer = StrokeHumanizer()

    /// 把有序笔画转成带压感与时序的重播序列。
    /// - Parameters:
    ///   - polylines: 已排好顺序的笔画，坐标须为页面坐标系（页面点）；
    ///     调用方负责保证笔顺就是希望的书写顺序。
    ///   - configuration: 手绘化参数。尺度相关字段必须已按参照尺度换算成页面点。
    ///   - seed: 随机种子。同一输入配同一种子必然得到同一结果，手感回归测试依赖这一点。
    /// - Parameter timeScale: 整段时长的倍数，大于 1 表示写得更快。
    ///   默认 1（原速）——**引擎不替调用方决定魂该写多快**，那是产品选择。
    ///   实际值由 `HandwritingFeel.soulWritesFasterThanHumanBy` 提供，
    ///   在装配层（`ReplyComposer`）传进来。
    func process(
        _ polylines: [Polyline],
        configuration: HumanizerConfiguration,
        seed: UInt64,
        timeScale: Double = 1
    ) -> StrokeSequence {
        humanizer
            .humanize(polylines, configuration: configuration, seed: seed)
            .timeScaled(by: timeScale)
    }
}
