//
//  DurationSeconds.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：把 Swift 的 `Duration` 换成秒数（`TimeInterval`）。
//
//  设计原因：
//  - 计划 D4 把重播计时从 `Date`（墙上时钟，会因改系统时间或时间同步而跳变）
//    改成 `ContinuousClock`（单调时钟）。单调时钟两个时刻相减得到的是 `Duration`，
//    而时间轴 `StrokeReplayTimeline` 的接口是秒数，因此需要这一次换算。
//  - 标准库没有直接给 `Duration → Double 秒`，只给了 `components`（整秒 + 阿托秒）。
//    换算写成一处扩展，避免每个调用点各拼一遍浮点运算——那正是同一逻辑被复制的开端。
//  - 放在 StrokeEngine 而不是 Configuration：它是纯粹的单位换算，不含任何可调参数，
//    也不依赖 UI 或设备。
//

import Foundation

nonisolated extension Duration {
    /// 换算成秒。
    /// `components.attoseconds` 是 1e-18 秒，乘上它即可补齐不足一秒的部分。
    /// Double 的精度足够覆盖重播时长这个量级（秒到分钟），不需要更高精度的表示。
    var inSeconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) * 1e-18
    }
}
