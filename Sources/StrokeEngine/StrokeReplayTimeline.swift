//
//  StrokeReplayTimeline.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：把“已经过去多少秒”换算成每一笔的绘制进度。
//
//  设计原因：
//  - 时间到进度的换算做成纯函数，不持有计时器：渲染层每帧问一次即可，
//    暂停、跳转、测试都不需要引擎配合，也不会出现两套时间源打架。
//  - 严格串行是产品要求：必须像真人一样一笔画完再画下一笔，
//    因此后面的笔在前一笔完成前进度必须恒为 0，不能提前露头。
//

import Foundation

nonisolated struct StrokeReplayTimeline: Sendable {
    let sequence: StrokeSequence

    var totalDuration: TimeInterval {
        sequence.totalDuration
    }

    /// 第 index 笔的起笔时刻，等于它前面所有笔的时长之和。
    /// 时长非负由 `TimedStroke` 的构造校验保证，这里不再重复夹取（计划 D3）。
    func startTime(forStrokeAt index: Int) -> TimeInterval {
        precondition(sequence.strokes.indices.contains(index), "Stroke index is out of range")
        return sequence.strokes[..<index].reduce(into: 0) { total, stroke in
            total += stroke.duration
        }
    }

    func frame(at elapsedTime: TimeInterval) -> ReplayFrame {
        // NaN/无穷会污染后续比较，直接当成“还没开始”，避免整帧渲染出错。
        let elapsed = elapsedTime.isFinite ? elapsedTime : 0
        var cursor: TimeInterval = 0
        var progress: [Double] = []
        progress.reserveCapacity(sequence.strokes.count)

        for stroke in sequence.strokes {
            // 时长非负由 TimedStroke 保证，这里不再重复夹取（计划 D3）。
            let duration = stroke.duration
            let strokeProgress: Double

            if duration == 0 {
                // 零时长的笔（例如单个墨点）不能除零，到点即视为完成。
                strokeProgress = elapsed >= cursor ? 1 : 0
            } else if elapsed <= cursor {
                strokeProgress = 0
            } else if elapsed >= cursor + duration {
                strokeProgress = 1
            } else {
                strokeProgress = (elapsed - cursor) / duration
            }

            progress.append(min(1, max(0, strokeProgress)))
            // cursor 累加后才处理下一笔，这就是“严格串行”的实现点。
            cursor += duration
        }

        return ReplayFrame(progressByStroke: progress)
    }
}
