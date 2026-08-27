//
//  StrokePipeline.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：笔画生成的唯一入口，把有序向量交给 Humanizer 并产出可重播序列。
//
//  设计原因：
//  - 2026-08-25 删除位图路线后，这里不再需要 StrokeSourcePayload 枚举，入口直接收 [Polyline]。
//    原因：只剩一种源时，枚举只会假装“可切换”，反而掩盖真实实现。
//  - 仍保留 Pipeline 这一层而不是让 UI 直接调用 Humanizer：以后接入真实模型输出时，
//    格式转换和参数装配都应集中在这里，UI 与调用方不必改动。
//

nonisolated struct StrokePipeline: Sendable {
    private let humanizer = StrokeHumanizer()

    /// 把有序笔画转成带压感与时序的重播序列。
    /// - Parameters:
    ///   - polylines: 已排好顺序的笔画；调用方负责保证笔顺就是希望的作画顺序。
    ///   - seed: 固定随机种子，保证同一输入每次输出一致，便于回归测试。
    func process(
        _ polylines: [Polyline],
        configuration: HumanizerConfiguration = HumanizerConfiguration(),
        seed: UInt64 = 7
    ) -> StrokeSequence {
        humanizer.humanize(polylines, configuration: configuration, seed: seed)
    }
}
