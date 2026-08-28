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

    /// 第 index 笔真正落墨的时刻。
    ///
    /// 等于「它前面所有笔占用的时间」加上「它自己那段抬笔移动」（计划 A4）：
    /// 抬笔移动发生在落墨之前，所以要算进起笔时刻里。
    /// 两个时长非负都由 `TimedStroke` 的构造校验保证，这里不再重复夹取（计划 D3）。
    func startTime(forStrokeAt index: Int) -> TimeInterval {
        precondition(sequence.strokes.indices.contains(index), "Stroke index is out of range")
        let before = sequence.strokes[..<index].reduce(into: 0.0) { total, stroke in
            total += stroke.totalDuration
        }
        return before + sequence.strokes[index].pauseBefore
    }

    func frame(at elapsedTime: TimeInterval) -> ReplayFrame {
        // NaN/无穷会污染后续比较，直接当成“还没开始”，避免整帧渲染出错。
        let elapsed = elapsedTime.isFinite ? elapsedTime : 0
        var cursor: TimeInterval = 0
        var progress: [Double] = []
        progress.reserveCapacity(sequence.strokes.count)

        for stroke in sequence.strokes {
            // 落墨的起止时刻。抬笔移动发生在落墨之前，那段时间这一笔还没出现（A4）。
            //
            // 这里刻意用 `cursor + stroke.totalDuration` 求终点，而不是先
            // `cursor += pauseBefore` 再比 `cursor + duration`：后者的浮点累加顺序与
            // `StrokeSequence.totalDuration` 不同，笔数多了以后
            // `frame(at: totalDuration)` 会差出一个尾数、最后一笔差一点点画不完。
            // 这个问题 2026-08-29 被 `GlyphStrokeTests` 的端到端用例抓到过。
            let inkStart = cursor + stroke.pauseBefore
            let inkEnd = cursor + stroke.totalDuration

            // 时长非负由 TimedStroke 保证，这里不再重复夹取（计划 D3）。
            let duration = stroke.duration
            let strokeProgress: Double

            if duration == 0 {
                // 零时长的笔（例如单个墨点）不能除零，到点即视为完成。
                strokeProgress = elapsed >= inkStart ? 1 : 0
            } else if elapsed <= inkStart {
                strokeProgress = 0
            } else if elapsed >= inkEnd {
                strokeProgress = 1
            } else {
                // 起笔加速、收笔减速（计划 A3）。时间是匀速流的，
                // 但「时间过了一半」不等于「线画了一半」——缓动就加在这里。
                // 为什么加在时间轴而不是几何那侧：`StrokeGrowth` 只负责
                // 「给定进度，线画到哪」，它不该知道时间的事。
                strokeProgress = StrokeEasing.progress((elapsed - inkStart) / duration)
            }

            progress.append(min(1, max(0, strokeProgress)))
            // cursor 累加后才处理下一笔，这就是“严格串行”的实现点。
            cursor += stroke.totalDuration
        }

        return ReplayFrame(progressByStroke: progress)
    }
}
