//
//  PenTrace.swift
//  模块：Calibration（纯逻辑；把真人笔迹量成数字，用来校准手感参数）
//
//  文件职责：定义「一笔真实笔迹」的数据结构——每个点的位置、时刻、力度。
//
//  为什么需要一个和 `Polyline` 不同的类型（计划 A10）：
//  `Polyline` 只有坐标，因为笔画引擎只需要「画到哪」。但要校准手感参数，
//  必须知道**什么时候**画到那里——书写速度、手抖频率、抬笔移动的快慢，
//  全都是时间上的量。丢掉时间就什么都量不出来。
//
//  为什么单独一个 Calibration 目录而不是塞进 StrokeEngine：
//  引擎是产品运行时要跑的东西，而这里是**开发期的量尺**：它读真人笔迹、
//  算出该给引擎配什么参数，然后就没事了。混在一起会让引擎带上它永远不用的代码。
//  和引擎一样，这里只依赖 Foundation，不碰 UI、不碰 PencilKit——
//  「怎么从 PencilKit 读出这些数」是画布层的事（`PenTraceReader`）。
//
//  力度为什么可能全是 0（不是 bug，是硬件）：
//  USB-C 款 Apple Pencil 没有压感传感器，第三方笔经 PencilKit 也拿不到压感。
//  所以这里如实保留 force 原值，由分析层判断「这批数据有没有力度信息」，
//  没有就明说测不了，不拿别的量硬凑一个压感出来。
//

import Foundation

/// 真实笔迹里的一个采样点。
nonisolated struct PenTraceSample: Equatable, Sendable {
    /// 位置，单位与来源一致（当前是页面点）。
    let point: Point2D

    /// 相对这一笔起笔时刻过了多少秒。
    let timeOffset: TimeInterval

    /// 设备报告的力度原值。**量程未知且不公开**，所以不做任何归一化。
    /// 硬件不支持压感时全程为 0。
    let force: Double
}

/// 一笔真实笔迹。
nonisolated struct PenTrace: Equatable, Sendable {
    /// 这一笔落笔的时刻，用来算笔与笔之间的间隔。
    /// 来源是 PencilKit 的墙上时钟（它没有提供单调时钟的笔画时刻），
    /// 因此系统校时会让间隔算错——这是数据源的限制，不是可以修的 bug。
    let startedAt: Date

    /// 按书写顺序排列的采样点。
    let samples: [PenTraceSample]

    /// 这一笔画了多久。
    var duration: TimeInterval { samples.last?.timeOffset ?? 0 }

    /// 这一笔抬笔的时刻。
    var endedAt: Date { startedAt.addingTimeInterval(duration) }

    /// 这一笔的墨迹总长。
    var length: Double {
        zip(samples, samples.dropFirst()).reduce(into: 0.0) { total, pair in
            total += pair.0.point.distance(to: pair.1.point)
        }
    }

    /// 这一笔的起点与终点。
    var start: Point2D? { samples.first?.point }
    var end: Point2D? { samples.last?.point }

    /// 纵向跨度。用来粗略估字有多大（见 `HandwritingCalibration` 里对这个估算的说明）。
    var verticalExtent: Double {
        let ys = samples.map(\.point.y)
        guard let low = ys.min(), let high = ys.max() else { return 0 }
        return high - low
    }
}
