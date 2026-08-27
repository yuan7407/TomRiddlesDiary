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
//  - 渲染层不生成任何手感数据，只读 ReplayFrame。手感的唯一来源是 StrokeHumanizer，
//    这样以后换渲染实现（Canvas / Metal / 落定进 PKDrawing）观感都不会漂移。
//  - 逐段画而非整条 Path：只有分段才能让每段用各自的压感线宽，
//    也才能画出「正在生长中的半条线段」——这是逐笔生长观感的实现核心。
//  - 坐标 1:1 直接映射，本视图不做任何缩放。原实现带一个 CanvasTransform，
//    会把全部笔画自动缩放到刚好填满视图；那是离线诊断界面的需要，
//    与产品要求正好相反（回应必须落在纸上的固定位置），已随迁移删除。
//    调用方负责传入页面坐标系里的笔画。
//  - 不设背景色：底色属于「纸」，由页面提供，本视图只负责墨。
//  - TimelineView 不指定 minimumInterval，跟随屏幕自身刷新率。
//    原实现写死 1/60，会让 120Hz ProMotion 屏只跑一半帧率，
//    而逐笔生长的顺滑度正是这个产品的核心观感。
//
//  已知未修复缺陷（属笔触修复计划，本次迁移刻意不夹带行为改动）：
//  - A5 收笔收不到零宽：taper 末端仍有最小宽度，配圆头端点会留一个钝头。
//  - A7 单点墨点在进度大于 0 的瞬间即以全尺寸填出，不生长。
//  - D4 已过时间来自 Date（墙上时钟，可能跳变），应换成单调时钟。
//

import SwiftUI

/// 逐笔重播一段已手绘化的回应。
/// - Parameters:
///   - sequence: 已经过 StrokeHumanizer 处理的笔画序列，坐标须为页面坐标系（页面点）。
///   - replayStartedAt: 起播时刻。传 nil 表示不在播放，此时直接显示画完的最终状态。
///   - referenceScale: 这段文字排版时用的字高（页面点）。墨的粗细按它换算，
///     所以写大字时墨也相应变粗，比例关系不变。
struct HandwritingReplayView: View {
    let sequence: StrokeSequence
    let replayStartedAt: Date?
    let referenceScale: Double

    var body: some View {
        TimelineView(.animation(paused: replayStartedAt == nil)) { timelineContext in
            Canvas { context, _ in
                let elapsed = replayStartedAt.map { max(0, timelineContext.date.timeIntervalSince($0)) }
                    ?? sequence.totalDuration
                let frame = StrokeReplayTimeline(sequence: sequence).frame(at: elapsed)
                render(frame: frame, in: &context)
            }
        }
        .accessibilityLabel("日记之魂正在逐笔写下回应")
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
        guard progress > 0, let first = stroke.samples.first else { return }

        if stroke.samples.count == 1 {
            let center = viewPoint(first.point)
            let width = inkWidth(forPressure: first.pressure)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - width / 2,
                    y: center.y - width / 2,
                    width: width,
                    height: width
                )),
                with: .color(PageAppearance.ink)
            )
            return
        }

        // 进度按采样点索引推进。重采样已把采样点铺成等弧长，
        // 因此索引推进等价于沿笔画弧长匀速推进。
        let segmentProgress = min(1, progress) * Double(stroke.samples.count - 1)
        let completeSegments = min(stroke.samples.count - 1, Int(segmentProgress.rounded(.down)))

        for index in 0 ..< completeSegments {
            drawSegment(from: stroke.samples[index], to: stroke.samples[index + 1], in: &context)
        }

        // 正在生长的那半条线段：位置与压感都要插值，否则笔尖会一格一格跳。
        let partial = segmentProgress - Double(completeSegments)
        if completeSegments < stroke.samples.count - 1, partial > 0 {
            let start = stroke.samples[completeSegments]
            let end = stroke.samples[completeSegments + 1]
            let partialEnd = StrokeSample(
                point: Point2D.interpolate(from: start.point, to: end.point, fraction: partial),
                pressure: start.pressure + (end.pressure - start.pressure) * partial
            )
            drawSegment(from: start, to: partialEnd, in: &context)
        }
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
                lineWidth: inkWidth(forPressure: (start.pressure + end.pressure) / 2),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func inkWidth(forPressure pressure: Double) -> Double {
        PageAppearance.inkWidth(forPressure: pressure, referenceScale: referenceScale)
    }

    /// 页面坐标到视图坐标：1:1，不缩放不平移。缩放是页面层的职责，不是墨层的。
    private func viewPoint(_ point: Point2D) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }
}
