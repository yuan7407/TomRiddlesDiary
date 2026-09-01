//
//  PenTraceReader.swift
//  模块：Features/Canvas（用户书写的那张纸）
//
//  文件职责：把 PencilKit 记录的手写读成**带时间的**笔迹，供校准分析用（计划 A10）。
//
//  为什么不复用 `PencilStrokeReader`：
//  那一层的产出是 `[Polyline]`——只有坐标，因为笔画引擎只需要「画到哪」。
//  校准要量的是速度、手抖频率、抬笔移动的快慢，全是时间上的量，丢掉时间就什么都量不出。
//  两者读的是同一份 `PKDrawing`，但取的东西不同，硬塞进一个类型只会让引擎那条路
//  背上它不需要的字段。
//
//  为什么用**控制点**而不是插值采样点：
//  `timeOffset` 只有原始控制点是真实记录的，插值出来的点时间是算出来的。
//  量速度和频率必须用真实记录的时间，否则量到的是插值算法的性质，不是人的性质。
//  代价是点的疏密不均（快写时稀），但对这里的统计量影响不大——
//  速度用总长除总时长，频率用过零次数除时长，两者都不依赖点是否等距。
//
//  只在 DEBUG 里被调用：这是开发期的量尺，不是产品功能。
//

import Foundation
import PencilKit

nonisolated struct PenTraceReader: Sendable {
    /// 把一份手写读成带时间的笔迹。
    func read(_ drawing: PKDrawing) -> [PenTrace] {
        drawing.strokes.compactMap { stroke in
            let path = stroke.path
            guard !path.isEmpty else { return nil }

            let samples = (0 ..< path.count).map { index -> PenTraceSample in
                let point = path[index]
                // 笔画自身可能带仿射变换（缩放、旋转），必须应用后才是画布坐标。
                let located = point.location.applying(stroke.transform)
                return PenTraceSample(
                    point: Point2D(x: located.x, y: located.y),
                    timeOffset: point.timeOffset,
                    force: Double(point.force),
                    altitude: Double(point.altitude)
                )
            }

            return PenTrace(startedAt: path.creationDate, samples: samples)
        }
    }
}
