//
//  HandwritingReplayView.swift
//  模块：Features/Response（渲染层，只消费 StrokeEngine 的输出）
//
//  文件职责：把「日记之魂」的回应按时间轴逐笔画出来，并让线宽跟随压感变化。
//
//  由 Features/StrokeLab/StrokeCanvasView.swift 迁移而来（2026-08-26）。改名原因：
//  接入 PencilKit 后画面上会同时存在 PKCanvasView（用户写字）和本视图（魂的回应），
//  原名 StrokeCanvasView 与前者极易混淆；新名字直接说明它做的事是「重播手写」。
//
//  设计原因：
//  - 渲染层不生成任何手感或几何数据。进度→帧由 `StrokeReplayTimeline` 算，
//    一笔画到哪里由 `StrokeGrowth` 算，本视图只负责把结果描成线。
//    这样换渲染实现（Canvas / Metal / 落定进 PKDrawing）观感都不会漂移。
//  - 逐段描边而非整条 Path：只有分段才能让每段用各自的压感线宽。
//  - 坐标 1:1 直接映射，本视图不做任何缩放。原实现带一个 CanvasTransform，
//    会把全部笔画自动缩放到刚好填满视图；那是离线诊断界面的需要，
//    与产品要求正好相反（回应必须落在纸上的固定位置），已随迁移删除。
//    调用方负责传入页面坐标系里的笔画。
//  - 不设背景色：底色属于「纸」，由页面提供，本视图只负责墨。
//  - TimelineView 不指定 minimumInterval，跟随屏幕自身刷新率。
//    原实现写死 1/60，会让 120Hz ProMotion 屏只跑一半帧率，
//    而逐笔生长的顺滑度正是这个产品的核心观感。
//
//  时钟（2026-08-27，计划 D4）：
//  起播时刻与「现在」都取自 `ContinuousClock`，不再用 `Date`。原因：`Date` 是墙上
//  时钟，用户改系统时间或系统做时间同步校正时会跳变，跳变会让重播瞬间闪到别的
//  进度。单调时钟不会倒退也不会跳。
//  已知行为：App 退到后台时 TimelineView 停止出帧，而单调时钟继续走，
//  所以切回来时会直接看到画完的状态，而不是从中断处接着画。这在当前阶段是可接受
//  的——回应本来就是在你不看的时候写完的。要不要改成「回来后接着写」是产品决定，
//  留到接入真实画布时（计划 E3）连同打断行为一起定。
//

import SwiftUI

/// 逐笔重播一段已手绘化的回应。
/// - Parameters:
///   - sequence: 已经过 StrokeHumanizer 处理的笔画序列，坐标须为页面坐标系（页面点）。
///   - replayStartedAt: 起播时刻，取自单调时钟 `ContinuousClock`。
///     传 nil 表示不在播放，此时直接显示画完的最终状态。
struct HandwritingReplayView: View {
    let sequence: StrokeSequence
    let replayStartedAt: ContinuousClock.Instant?

    var body: some View {
        // TimelineView 只用来驱动重绘；具体过了多少秒问单调时钟，不用它给的 Date。
        TimelineView(.animation(paused: replayStartedAt == nil)) { _ in
            Canvas { context, _ in
                let frame = StrokeReplayTimeline(sequence: sequence).frame(at: elapsedSeconds())
                render(frame: frame, in: &context)
            }
        }
        .accessibilityLabel("日记之魂正在逐笔写下回应")
    }

    /// 已过秒数。不在播放时返回总时长，也就是显示画完的状态。
    private func elapsedSeconds() -> TimeInterval {
        guard let replayStartedAt else { return sequence.totalDuration }
        return max(0, (ContinuousClock.now - replayStartedAt).inSeconds)
    }

    private func render(frame: ReplayFrame, in context: inout GraphicsContext) {
        for (strokeIndex, stroke) in sequence.strokes.enumerated() {
            let progress = frame.progressByStroke.indices.contains(strokeIndex)
                ? frame.progressByStroke[strokeIndex]
                : 0
            draw(stroke: stroke, progress: progress, in: &context)
        }
    }

    private func draw(stroke: TimedStroke, progress: Double, in context: inout GraphicsContext) {
        guard let partial = StrokeGrowth.partial(of: stroke, progress: progress) else { return }

        // 单采样点的笔就是一个墨点。
        // 已知缺陷（计划 A7）：这里一出现就是全尺寸，不随进度长出来。
        if stroke.samples.count == 1, let dot = stroke.samples.first {
            drawDot(dot, in: &context)
            return
        }

        for index in 0 ..< partial.completeSegmentCount {
            drawSegment(from: stroke.samples[index], to: stroke.samples[index + 1], in: &context)
        }

        if let tip = partial.growingTip {
            drawSegment(from: stroke.samples[partial.growingSegmentStartIndex], to: tip, in: &context)
        }
    }

    private func drawDot(_ sample: StrokeSample, in context: inout GraphicsContext) {
        let center = viewPoint(sample.point)
        let width = PageAppearance.inkWidth(forPressure: sample.pressure)
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - width / 2,
                y: center.y - width / 2,
                width: width,
                height: width
            )),
            with: .color(PageAppearance.ink)
        )
    }

    private func drawSegment(
        from start: StrokeSample,
        to end: StrokeSample,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: viewPoint(start.point))
        path.addLine(to: viewPoint(end.point))
        context.stroke(
            path,
            with: .color(PageAppearance.ink),
            style: StrokeStyle(
                lineWidth: PageAppearance.inkWidth(forPressure: (start.pressure + end.pressure) / 2),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    /// 页面坐标到视图坐标：1:1，不缩放不平移。缩放是页面层的职责，不是墨层的。
    private func viewPoint(_ point: Point2D) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }
}
