//
//  StrokeModels.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：定义笔画引擎共用的最小几何值类型。
//
//  设计原因：
//  - 使用 nonisolated 值类型，让纯算法能脱离 MainActor 在任意上下文复用与单测。
//  - 2026-08-25 起本工程只保留“有序向量”一条笔画源，服务于位图细化的
//    GridPoint / BinaryMask 已整体删除，引擎入口统一为 [Polyline]。
//    原因：位图抽骨架的实机效果明显差于有序向量，保留双源只会留下无人使用的分支。
//

import Foundation

/// 与 UI 无关的浮点坐标。故意不用 CGPoint，避免纯算法层依赖 CoreGraphics。
nonisolated struct Point2D: Equatable, Sendable {
    let x: Double
    let y: Double

    func distance(to other: Point2D) -> Double {
        hypot(other.x - x, other.y - y)
    }

    /// 按比例在两点之间取值，`fraction` 为 0 返回起点、1 返回终点。
    /// 重采样和逐笔重播的“半条线段”都依赖它，因此保持为纯函数。
    static func interpolate(from start: Point2D, to end: Point2D, fraction: Double) -> Point2D {
        Point2D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }
}

/// 一笔的有序采样点，代表“笔尖不离纸”的一条连续轨迹。
nonisolated struct Polyline: Equatable, Sendable {
    let points: [Point2D]

    /// 折线总长。Humanizer 用它推算这一笔应该画多久，因此长度必须按实际相邻距离累加。
    var length: Double {
        zip(points, points.dropFirst()).reduce(into: 0) { total, pair in
            total += pair.0.distance(to: pair.1)
        }
    }
}
