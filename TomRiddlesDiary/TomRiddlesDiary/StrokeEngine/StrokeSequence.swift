//
//  StrokeSequence.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：定义“已经手绘化、可以逐笔重播”的数据结构。
//
//  设计原因：
//  - 把压感、时长和进度固化成不可变值类型，渲染层只负责读，不参与生成，
//    这样换渲染实现（Canvas / Metal）时手感不会跟着改变。
//  - 进度用 [Double] 而不是“当前第几笔”：一次重播里既有已完成的笔，也有正在生长的笔，
//    渲染层需要同时知道全部状态。
//

import Foundation

/// 一个采样点：位置 + 该点的压感（0…1，越大线越粗）。
nonisolated struct StrokeSample: Equatable, Sendable {
    let point: Point2D
    let pressure: Double
}

/// 一笔：采样点序列 + 这一笔应画多久。
nonisolated struct TimedStroke: Equatable, Sendable {
    let samples: [StrokeSample]
    let duration: TimeInterval

    var length: Double {
        zip(samples, samples.dropFirst()).reduce(into: 0) { total, pair in
            total += pair.0.point.distance(to: pair.1.point)
        }
    }
}

/// 一整幅回应的全部笔画，按作画顺序排列。
nonisolated struct StrokeSequence: Equatable, Sendable {
    let strokes: [TimedStroke]

    /// 全部笔画串行播放的总时长。负时长按 0 处理，避免异常数据把总时长算短。
    var totalDuration: TimeInterval {
        strokes.reduce(into: 0) { $0 += max(0, $1.duration) }
    }
}

/// 某一时刻的重播快照：每一笔各自画到了百分之几。
nonisolated struct ReplayFrame: Equatable, Sendable {
    let progressByStroke: [Double]

    var isComplete: Bool {
        progressByStroke.allSatisfy { $0 >= 1 }
    }

    /// 正在生长的那一笔。严格串行播放下最多只有一笔处于 0 与 1 之间。
    var activeStrokeIndex: Int? {
        progressByStroke.firstIndex { $0 > 0 && $0 < 1 }
    }
}
