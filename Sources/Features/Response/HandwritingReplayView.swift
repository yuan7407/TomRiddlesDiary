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
//  的——回应本来就是在你不看的时候写完的。要不要改成「回来后接着写」是产品决定。
//
//  播放状态（2026-08-29，计划 E3d）：
//  入参由 `replayStartedAt: Instant?` 改成 `ReplayPlayback` 三态。原因是打断必须
//  能表达「停在当时的进度上」——用可选时刻只能表达「在播」和「画完」两种，
//  打断只能被迫映射成画完，那正好把「你打断了它」这个信息抹掉。
//  三态的定义与打断规则见 `ReplayPlayback.swift`。
//

import SwiftUI

/// 逐笔重播一段已手绘化的回应。
/// - Parameters:
///   - sequence: 已经过 StrokeHumanizer 处理的笔画序列，坐标须为页面坐标系（页面点）。
///   - playback: 此刻的播放状态（在播 / 停在某个进度 / 已写完）。
struct HandwritingReplayView: View {
    let sequence: StrokeSequence
    let playback: ReplayPlayback

    var body: some View {
        // TimelineView 只用来驱动重绘；具体过了多少秒问单调时钟，不用它给的 Date。
        // 只有在播时才需要连续出帧，停住和写完都是静止画面。
        TimelineView(.animation(paused: !playback.isPlaying)) { _ in
            Canvas { context, _ in
                let elapsed = playback.elapsedSeconds(totalDuration: sequence.totalDuration)
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

    /// 画一笔当前该露出的部分。
    ///
    /// 「这一笔是点还是线」由引擎判定（`PartialStroke` 的两个 case），
    /// 本视图不再自己看采样点个数——那是几何决定，不属于渲染层（计划 A7）。
    private func draw(stroke: TimedStroke, progress: Double, in context: inout GraphicsContext) {
        guard let partial = StrokeGrowth.partial(of: stroke, progress: progress) else { return }

        switch partial {
        case .dot(let sample, let sizeFraction):
            drawDot(sample, sizeFraction: sizeFraction, in: &context)

        case .line(let completeSegmentCount, let growingTip):
            for index in 0 ..< completeSegmentCount {
                drawSegment(from: stroke.samples[index], to: stroke.samples[index + 1], in: &context)
            }
            if let tip = growingTip {
                drawSegment(from: stroke.samples[completeSegmentCount], to: tip, in: &context)
            }
        }
    }

    /// 画墨点。`sizeFraction` 是引擎算出的生长比例（计划 A7），
    /// 本视图只负责把它乘到直径上。
    private func drawDot(_ sample: StrokeSample, sizeFraction: Double, in context: inout GraphicsContext) {
        let center = viewPoint(sample.point)
        let width = PageAppearance.inkWidth(
            forPressure: sample.pressure,
            contact: sample.contact
        ) * sizeFraction
        // 尺寸还是 0 时不画：Path(ellipseIn:) 对零尺寸矩形没有意义，
        // 而且这一帧本来就该什么都看不见。
        guard width > 0 else { return }

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
                // 一段线用两端的平均值。接触也要一起平均——只平均压感的话，
                // 收笔那一段会保持满宽直到最后一刻，收不出渐细（计划 A5）。
                lineWidth: PageAppearance.inkWidth(
                    forPressure: (start.pressure + end.pressure) / 2,
                    contact: (start.contact + end.contact) / 2
                ),
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
