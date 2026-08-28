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
///
/// 不变量：`duration` 不为负，由构造时校验保证（2026-08-27，计划 D3）。
/// 原先这个字段是裸的 `TimeInterval`，允许负数，于是 `StrokeSequence.totalDuration`、
/// `StrokeReplayTimeline.startTime` 与 `frame` 三处各自 `max(0, ...)` 夹一遍。
/// 那是用防御性堆叠掩盖设计问题：只要类型允许非法值，每个消费方都得记着补一次，
/// 漏掉任何一处就会出错。现在非法值进不来，三处夹取全部删除。
///
/// 为什么用 precondition 崩掉而不是夹到 0：负时长不会有任何可见症状，它会让
/// 时间轴静默错位——后面的笔提前起笔、或者整段永远播不完。这类问题夹一下就
/// 看不见了，只能靠崩在产生它的地方来定位。
nonisolated struct TimedStroke: Equatable, Sendable {
    let samples: [StrokeSample]
    let duration: TimeInterval

    /// 这一笔落笔**之前**，笔在空中的时间（秒）。
    ///
    /// 为什么要有它（计划 A4，2026-08-29）：在此之前后一笔在前一笔结束的同一瞬间起笔，
    /// 笔尖从一个字的末端瞬移到下一笔的起点。真人写字时笔要抬起来、移过去、再落下，
    /// 这段时间是看得见的——它就是「一笔一笔写」的节奏所在。零间隔的观感是
    /// 「一条连续的线在自己爬」，而不是有人在写字。
    ///
    /// 为什么叫 before 而不是 after：第一笔天然没有这段时间（前面没有笔），
    /// 用 before 时它自然是 0；用 after 则要为最后一笔想一个没有意义的值。
    ///
    /// 默认 0 是**有含义的合法值**（第一笔、或者刻意不要间隔），
    /// 不是一个没验证过的猜测值——这一点和 `HumanizerConfiguration` 刻意不给默认值
    /// 的理由不冲突：那些参数是尺度相关的，任何默认值都只在某个字号下成立。
    let pauseBefore: TimeInterval

    init(samples: [StrokeSample], duration: TimeInterval, pauseBefore: TimeInterval = 0) {
        precondition(duration >= 0, "Stroke duration cannot be negative")
        precondition(duration.isFinite, "Stroke duration must be finite")
        precondition(pauseBefore >= 0, "Pause before a stroke cannot be negative")
        precondition(pauseBefore.isFinite, "Pause before a stroke must be finite")
        self.samples = samples
        self.duration = duration
        self.pauseBefore = pauseBefore
    }

    /// 这一笔在时间轴上占用的总长度：抬笔移动 + 落墨。
    var totalDuration: TimeInterval { pauseBefore + duration }

    var length: Double {
        zip(samples, samples.dropFirst()).reduce(into: 0) { total, pair in
            total += pair.0.point.distance(to: pair.1.point)
        }
    }
}

/// 一整幅回应的全部笔画，按作画顺序排列。
nonisolated struct StrokeSequence: Equatable, Sendable {
    let strokes: [TimedStroke]

    /// 全部笔画串行播放的总时长，**含笔间抬笔移动的时间**（计划 A4）。
    /// `TimedStroke` 已保证两个时长都非负且有限，直接累加即可。
    var totalDuration: TimeInterval {
        strokes.reduce(into: 0) { $0 += $1.totalDuration }
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
