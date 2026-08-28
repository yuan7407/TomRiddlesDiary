//
//  PencilStrokeReader.swift
//  模块：Features/Canvas（用户书写的那张纸）
//
//  文件职责：把 PencilKit 记录的手写笔画，读成笔画引擎能消费的有序坐标。
//
//  设计原因：
//  - 这是全工程**第一个真实的 `[Polyline]` 生产源**。位图路线删除后引擎一直
//    没有真实输入，只能靠手打夹具（那批夹具也已删除）。这一层补上这个缺口。
//  - 为什么不直接用 `PKStroke.path` 的控制点：`PKStrokePath` 存的是插值曲线的
//    控制点，点与点之间的间距取决于采样率与书写速度，快写时会很稀。
//    引擎的第一步本来就要等距重采样，所以这里按固定步长把曲线采出来，
//    交给引擎的重采样再规整一次；直接用控制点会让快写的笔画丢掉弯度。
//  - 为什么放在 Features/Canvas 而不是 StrokeEngine：它 import PencilKit，
//    而引擎按门禁规定只许依赖 Foundation。「读某个具体框架的数据」属画布层职责，
//    引擎只认 `[Polyline]` 这个中立格式。
//
//  关于压感（诚实记录，不要伪造）：
//  `PKStrokePoint.force` **不是 0…1 归一化的**，它的量程取决于设备与笔，
//  而 PencilKit 没有公开「本设备的最大力度」。因此这里不把 force 硬除以某个
//  猜来的分母凑成压感——那会是一个没有依据的魔数。
//  当前只输出几何（`[Polyline]`），并单独报告这批笔画**是否带有效力度信息**，
//  由调用方决定怎么用。真正的压感映射要等真机采到 force 的实际分布才能定
//  （计划 A10），在那之前不得声称用户压感已被读取。
//

import CoreGraphics
import Foundation
import PencilKit

/// 书写节奏：用户是怎么写的，而不是写了什么。
///
/// 为什么和几何一起读：两者来自同一份 `PKDrawing`，一次遍历就能都拿到，
/// 分成两次读同一份数据是重复。
///
/// 这些数据有两个明确用途，都不是现在就用：
/// 一、计划 E3c 的成页触发阈值必须**从真实停顿分布量出来**，不能像原来那个
/// 「抬笔 2.8 秒」一样拍一个数。要先能测，才能定。
/// 二、计划 C2 把书写节奏作为情绪信号——写得快还是犹豫，是纯文本拿不到的信息。
///
/// 时间来源的局限（诚实记录）：PencilKit 给的是 `Date`（墙上时钟），
/// 不是单调时钟。若系统在两笔之间校正了时间，算出的停顿就是错的。
/// 因此这里丢弃负数与非有限的间隔，但**无法**分辨「用户真的停了很久」和
/// 「时钟跳了」。这是数据源的限制，不是可以修的 bug。
nonisolated struct WritingRhythm: Equatable, Sendable {
    /// 笔间停顿（秒）：上一笔抬笔到下一笔落笔之间的时间。
    /// 长度比笔数少一；单笔或空白时为空。
    let pauses: [TimeInterval]

    /// 从第一笔落笔到最后一笔抬笔的总时长。
    let totalDuration: TimeInterval

    /// 全部笔画自身的书写时长之和（不含停顿）。
    let inkDuration: TimeInterval

    var longestPause: TimeInterval? { pauses.max() }

    /// 停顿的中位数。用中位数而不是平均值：一次长时间发呆会把平均值拉得毫无意义，
    /// 而我们想知道的是「平常写字时的停顿有多长」。
    var medianPause: TimeInterval? {
        guard !pauses.isEmpty else { return nil }
        let sorted = pauses.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

/// 从 PencilKit 读出来的一次手写内容。
nonisolated struct PencilStrokeReading: Equatable, Sendable {
    /// 每一笔的有序坐标，单位是画布坐标（在不缩放不滚动的一页里，等同页面点）。
    let polylines: [Polyline]

    /// 这批笔画里 force 是否真的在变化。
    ///
    /// false 有两种含义，调用方不该区分对待：设备/笔不支持压感（USB-C Apple Pencil、
    /// 第三方笔、模拟器的鼠标都不支持），或者用户全程力度一致。两种情况下都
    /// **没有可用的压感信息**，不得据此编造压感。
    let hasVaryingForce: Bool

    /// 观测到的 force 范围，用于计划 A10 的校准取样。
    /// 没有任何采样点时为 nil。
    let observedForceRange: ClosedRange<Double>?

    /// 书写节奏。服务于 E3c 的成页阈值与 C2 的情绪信号。
    let rhythm: WritingRhythm

    var isEmpty: Bool { polylines.isEmpty }
}

nonisolated struct PencilStrokeReader: Sendable {
    /// 沿笔画曲线的采样步长（画布坐标）。
    ///
    /// 取字高的一个比例而不是固定点数：字写得大，曲线也长，需要更多采样点才能
    /// 保住弯度。数值本身在 `HandwritingFeel`，这里只负责用。
    private var samplingStep: Double {
        HandwritingFeel.referenceGlyphHeightInPoints * HandwritingFeel.sampleSpacingRatio
    }

    /// 把一份 PencilKit 手写内容读成有序笔画。
    /// - Parameter drawing: PencilKit 的手写记录。
    /// - Returns: 笔画与力度观测。空手写返回空结果，不视为错误。
    func read(_ drawing: PKDrawing) -> PencilStrokeReading {
        var polylines: [Polyline] = []
        var minimumForce = Double.greatestFiniteMagnitude
        var maximumForce = -Double.greatestFiniteMagnitude
        var sawAnyPoint = false

        for stroke in drawing.strokes {
            var points: [Point2D] = []

            // `.distance` 步长让 PencilKit 自己沿曲线等距采样。用框架的插值而不是
            // 自己按参数值均分：参数值与弧长不是线性关系，自己均分会在曲率大的
            // 地方采得太疏。
            for sample in stroke.path.interpolatedPoints(by: .distance(samplingStep)) {
                // 笔画自身可能带仿射变换（缩放、旋转），必须应用后才是画布坐标。
                let located = sample.location.applying(stroke.transform)
                points.append(Point2D(x: located.x, y: located.y))

                sawAnyPoint = true
                let force = Double(sample.force)
                minimumForce = min(minimumForce, force)
                maximumForce = max(maximumForce, force)
            }

            // 单点的「笔画」（点一下）没有方向，引擎的重采样会把它塌缩成一个墨点，
            // 这里保留它，由引擎决定怎么处理。
            guard !points.isEmpty else { continue }
            polylines.append(Polyline(points: points))
        }

        let rhythm = readRhythm(drawing)

        guard sawAnyPoint else {
            return PencilStrokeReading(
                polylines: polylines,
                hasVaryingForce: false,
                observedForceRange: nil,
                rhythm: rhythm
            )
        }

        let range = minimumForce ... maximumForce
        // 用「范围有宽度」判断力度是否可用。不设经验阈值：只要 force 完全不变，
        // 就没有任何压感信息可提取，无论它恒为 0 还是恒为某个值。
        return PencilStrokeReading(
            polylines: polylines,
            hasVaryingForce: maximumForce > minimumForce,
            observedForceRange: range,
            rhythm: rhythm
        )
    }

    /// 读出书写节奏。
    ///
    /// 每一笔的落笔时刻是 `path.creationDate`，抬笔时刻是它加上最后一个控制点的
    /// `timeOffset`。停顿就是「上一笔抬笔」到「下一笔落笔」的间隔。
    /// 用控制点而不是插值采样点：`timeOffset` 是原始记录的时间，插值出来的点
    /// 时间是算出来的。
    private func readRhythm(_ drawing: PKDrawing) -> WritingRhythm {
        struct Span {
            let start: Date
            let end: Date
        }

        let spans: [Span] = drawing.strokes.compactMap { stroke in
            let path = stroke.path
            guard let lastOffset = path.last?.timeOffset else { return nil }
            return Span(
                start: path.creationDate,
                end: path.creationDate.addingTimeInterval(lastOffset)
            )
        }
        // 按落笔时刻排序：`strokes` 的顺序是绘制顺序，但排序能让计算不依赖这个假设。
        .sorted { $0.start < $1.start }

        guard let first = spans.first, let last = spans.max(by: { $0.end < $1.end }) else {
            return WritingRhythm(pauses: [], totalDuration: 0, inkDuration: 0)
        }

        let pauses = zip(spans, spans.dropFirst()).compactMap { previous, next -> TimeInterval? in
            let gap = next.start.timeIntervalSince(previous.end)
            // 丢弃负数与非有限值：那只可能来自时钟跳变或异常数据，不是真实停顿。
            guard gap.isFinite, gap >= 0 else { return nil }
            return gap
        }

        let inkDuration = spans.reduce(into: 0.0) { total, span in
            let duration = span.end.timeIntervalSince(span.start)
            total += duration.isFinite && duration > 0 ? duration : 0
        }

        return WritingRhythm(
            pauses: pauses,
            totalDuration: max(0, last.end.timeIntervalSince(first.start)),
            inkDuration: inkDuration
        )
    }
}
