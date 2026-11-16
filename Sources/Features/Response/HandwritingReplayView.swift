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
//  - 不设背景色：底色属于「纸」，由页面提供，本视图只负责墨。
//
//  ── 谁来触发重绘（2026-09-01 换掉了 TimelineView，这是本文件最重要的一段）──
//
//  症状：E6a 接通之后，模拟器上写完字、魂那段回应**完全看不见**。
//  没有报错，没有提示，纸上就是空的。
//
//  原因：原实现用 `TimelineView(.animation)` 驱动重绘。而模拟器空闲时会冻结渲染
//  循环（`MEMORY.md` 已知陷阱，2026-08-27 在另一个视图上实测过：两种调度都只出
//  一两帧就停）。它在 t≈0 出一帧——那一刻第一笔的进度还是 0，什么都没画——
//  然后就不再出帧了。于是页面永远停在「一片空白」，看起来像功能没做。
//
//  改法：**自己用异步循环推进 `@State`**。由状态变化触发的重绘在模拟器里照常生效
//  （这一点当初 E8 的逐字显现就是这么绕过去的，是这个仓库里已经验证过的办法）。
//
//  为什么换驱动是安全的：**画多少墨是从单调时钟算的，不是累加帧数。**
//  每一帧都重新问「从起播到现在过了几秒」，所以某一帧迟到或丢掉，下一帧照样画到
//  正确的位置，误差不会累积。驱动只决定「什么时候重画」，不决定「画什么」。
//
//  刷新率**必须问屏幕，不能写死 60**：120 Hz ProMotion 屏上写死 60 会只跑一半帧率，
//  而逐笔生长的顺滑度正是这个产品的核心观感。原实现（`TimelineView` 不指定
//  minimumInterval）是让系统替我们跟随屏幕刷新率；自己驱动之后这件事得自己做。
//
//  时钟（2026-08-27，计划 D4）：
//  起播时刻与「现在」都取自 `ContinuousClock`，不再用 `Date`。原因：`Date` 是墙上
//  时钟，用户改系统时间或系统做时间同步校正时会跳变，跳变会让重播瞬间闪到别的进度。
//  单调时钟不会倒退也不会跳。
//  已知行为：App 退到后台时循环会被 SwiftUI 取消，而单调时钟继续走，
//  所以切回来时会直接看到画完的状态，而不是从中断处接着画。这在当前阶段可接受
//  ——回应本来就是在你不看的时候写完的。要不要改成「回来后接着写」是产品决定。
//
//  播放状态（2026-08-29，计划 E3d）：
//  入参由 `replayStartedAt: Instant?` 改成 `ReplayPlayback` 三态。原因是打断必须
//  能表达「停在当时的进度上」——用可选时刻只能表达「在播」和「画完」两种，
//  打断只能被迫映射成画完，那正好把「你打断了它」这个信息抹掉。
//  三态的定义与打断规则见 `ReplayPlayback.swift`。
//
//
//  ── 2026-11-12：墨有年纪（湿 → 干）──
//  正在写的这一段，笔尖后面拖着一小段蓝黑色的湿墨，两三秒后干成墨黑。
//  做法：每一小段线各自算「写下去多久了」（`InkAgeTimeline`），换成湿度，再按湿度取颜色并略微加粗。
//  三件要知道的事：
//  · 只有 `.playing` 时才有湿墨。定格（被打断）和已写完的回应一律按干墨画：
//    `ReplayPlayback` 的这两种状态不带「是什么时候写的」，这里无从知道墨龄；
//    代价是被打断的那一瞬间，最后几笔会从蓝直接变黑。要做对得让 `ReplayPlayback.frozen` 多带一个时刻，
//    那是状态机的改动，这次没有动（列在 MERGE.md 的待办里）。
//  · 写完以后循环要多跑一个「干透时间」，否则最后几笔会永远停在蓝色上。
//  · **这一版没有在任何设备或模拟器上跑过**（我这边没有 Xcode）。`ReplayRenderTests` 应该仍然通过：
//    它数的是「有墨的像素」；如果它按颜色取样，需要把期望改成干墨湿墨都算。
//

import SwiftUI
import UIKit

/// 逐笔重播一段已手绘化的回应。
/// - Parameters:
///   - sequence: 已经过 StrokeHumanizer 处理的笔画序列，坐标须为页面坐标系（页面点）。
///   - playback: 此刻的播放状态（在播 / 停在某个进度 / 已写完）。
struct HandwritingReplayView: View {
    let sequence: StrokeSequence
    let playback: ReplayPlayback

    /// 当前该画到哪一帧。**这就是驱动重绘的东西**——它一变，body 重算，Canvas 重画。
    /// nil 表示还没算出第一帧（`.task` 立刻就会填上）。
    @State private var currentFrame: ReplayFrame?
    /// 这段回应从开始写到现在真实过去了几秒。只有正在写的时候才有值；nil 表示一律按干墨画。
    @State private var inkSeconds: TimeInterval?

    var body: some View {
        Canvas { context, _ in
            // `currentFrame` 为 nil 只发生在「第一次布局、`.task` 还没跑」那一瞬间。
            // 这里当场算一帧而不是画空白，有两个作用：
            // 一、第一帧就是对的，不会闪一下空白；
            // 二、万一 `.task` 因为任何原因没跑起来，看到的是**静止的正确画面**，
            //    而不是一片空白——空白会让人以为整个功能没做（这正是 2026-09-01
            //    白查一轮的症状），而静止画面一眼就能看出「画得出来，只是没动」。
            //    这不是拿默认值掩盖失败：算的是同一个时刻、同一个公式，只是同步算的。
            render(frame: currentFrame ?? frameForNow(), inkSeconds: inkSeconds, in: &context)
        }
        .accessibilityLabel("日记之魂正在逐笔写下回应")
        // id 用 playback：被打断（playing → frozen）时循环会被取消并重新起一次，
        // 新的那次只算一帧就停——停住的画面是静止的，不需要继续出帧。
        .task(id: playback) { await driveFrames() }
    }

    /// 推进帧。
    ///
    /// 不在播时只算一帧就返回：停住和写完都是静止画面，继续循环纯属白烧电。
    /// 「此刻」该画哪一帧。同步算，不碰状态。
    private func frameForNow() -> ReplayFrame {
        StrokeReplayTimeline(sequence: sequence)
            .frame(at: playback.elapsedSeconds(totalDuration: sequence.totalDuration))
    }

    @MainActor
    private func driveFrames() async {
        let total = sequence.totalDuration

        func drawNow() -> TimeInterval {
            let elapsed = playback.elapsedSeconds(totalDuration: total)
            currentFrame = frameForNow()
            // 高频赋值前先比较，不拿同一个值反复写（见 MEMORY「已知陷阱」）。
            let wet: TimeInterval? = playback.isPlaying ? elapsed : nil
            if inkSeconds != wet { inkSeconds = wet }
            return elapsed
        }

        guard playback.isPlaying else {
            _ = drawNow()
            return
        }

        let interval = Duration.seconds(1 / Self.displayRefreshRate())
        while !Task.isCancelled {
            // 画完了就停。判据用「已过秒数」而不是数帧，理由见文件头。
            // 写完以后再多画一个「干透时间」：最后几笔要有机会从蓝变黑。
            guard drawNow() < total + BookFeel.inkDrying.dryingTime else {
                inkSeconds = nil
                return
            }
            do {
                try await Task.sleep(for: interval)
            } catch {
                // 只可能是被取消（打断，或视图消失）。取消不是错误，安静退出。
                return
            }
        }
    }

    /// 屏幕的最高刷新率。
    ///
    /// 问屏幕而不是写死，理由见文件头。
    /// 拿不到时退回 60：那是不带 ProMotion 的屏幕的固定刷新率，也是**兜底下界不是目标值**——
    /// 正常情况下这个分支不该走到。宁可偏保守，也绝不能除以 0。
    @MainActor
    private static func displayRefreshRate() -> Double {
        let rates = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }
        guard let best = rates.max(), best > 0 else { return 60 }
        return Double(best)
    }

    private func render(frame: ReplayFrame, inkSeconds: TimeInterval?, in context: inout GraphicsContext) {
        // 每帧建一次（只是把各笔的起止时刻累加出来），不是每一笔建一次。
        let ages = inkSeconds.map { seconds in (timeline: InkAgeTimeline(sequence: sequence), seconds: seconds) }
        for (strokeIndex, stroke) in sequence.strokes.enumerated() {
            let progress = frame.progressByStroke.indices.contains(strokeIndex)
                ? frame.progressByStroke[strokeIndex]
                : 0
            draw(stroke: stroke, progress: progress, in: &context) { fraction in
                guard let ages else { return 0 }
                return BookFeel.inkDrying.wetness(
                    age: ages.timeline.age(ofStroke: strokeIndex, fraction: fraction, secondsSinceStart: ages.seconds)
                )
            }
        }
    }

    /// 画一笔当前该露出的部分。
    ///
    /// 「这一笔是点还是线」由引擎判定（`PartialStroke` 的两个 case），
    /// 本视图不再自己看采样点个数——那是几何决定，不属于渲染层（计划 A7）。
    /// - Parameter wetness: 给出这一笔上某个位置（0 起笔…1 收笔）现在有多湿。
    ///   用「沿笔画的位置」近似「这一笔里的时间」：起收笔有加减速，两者不完全相等，
    ///   但湿墨的渐变本来就是模糊的，差这一点看不出来。
    private func draw(
        stroke: TimedStroke,
        progress: Double,
        in context: inout GraphicsContext,
        wetness: (Double) -> Double
    ) {
        guard let partial = StrokeGrowth.partial(of: stroke, progress: progress) else { return }

        switch partial {
        case .dot(let sample, let sizeFraction):
            drawDot(sample, sizeFraction: sizeFraction, wetness: wetness(0), in: &context)

        case .line(let completeSegmentCount, let growingTip):
            for index in 0 ..< completeSegmentCount {
                drawSegment(
                    from: stroke.samples[index],
                    to: stroke.samples[index + 1],
                    wetness: wetness((Double(index) + 0.5) / Double(max(1, stroke.samples.count - 1))),
                    in: &context
                )
            }
            if let tip = growingTip {
                drawSegment(from: stroke.samples[completeSegmentCount], to: tip, wetness: wetness(1), in: &context)
            }
        }
    }

    /// 画墨点。`sizeFraction` 是引擎算出的生长比例（计划 A7），
    /// 本视图只负责把它乘到直径上。
    private func drawDot(
        _ sample: StrokeSample,
        sizeFraction: Double,
        wetness: Double,
        in context: inout GraphicsContext
    ) {
        let center = viewPoint(sample.point)
        let width = PageAppearance.inkWidth(
            forPressure: sample.pressure,
            contact: sample.contact
        ) * sizeFraction * (1 + BookFeel.wetInkWidthGain * wetness)
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
            with: .color(PageAppearance.ink(wetness: wetness))
        )
    }

    private func drawSegment(
        from start: StrokeSample,
        to end: StrokeSample,
        wetness: Double,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: viewPoint(start.point))
        path.addLine(to: viewPoint(end.point))
        context.stroke(
            path,
            with: .color(PageAppearance.ink(wetness: wetness)),
            style: StrokeStyle(
                // 一段线用两端的平均值。接触也要一起平均——只平均压感的话，
                // 收笔那一段会保持满宽直到最后一刻，收不出渐细（计划 A5）。
                lineWidth: PageAppearance.inkWidth(
                    forPressure: (start.pressure + end.pressure) / 2,
                    contact: (start.contact + end.contact) / 2
                ) * (1 + BookFeel.wetInkWidthGain * wetness),   // 湿墨略微鼓起来一点
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
