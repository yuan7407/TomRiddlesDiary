//
//  DiaryPageView.swift
//  模块：Features/Canvas（用户书写的那张纸）
//
//  文件职责：App 的首屏，也是唯一的主界面——一张能写字的纸。
//
//  取代原 ContentView.swift（2026-08-26）。原文件唯一的作用是把根视图指向
//  Magic Stroke Lab 诊断界面；Lab 已整体删除，这层空转的中转也一并去掉。
//
//  当前真实状态（诚实说明，别对着界面猜）：
//  你可以在纸上写字，笔画会被读成引擎能用的格式（页脚的 DEBUG 读数就是证据），
//  但**写完不会有任何回应**。因为成页触发（E3c）、手写识别（E4）和 Oracle（E6）
//  都还没接。这不是 bug，是当前进度。
//
//  为什么不放一段示例回应在这里：
//  2026-08-28 之前这里有一段固定示例，进页面就自动逐字写出来。它当初的用途是
//  验证排版、字号、行距与书写节奏，那个任务已经完成（截图确认过）。但留着它会让
//  界面「看起来会回应」而实际不会——正是 AGENTS.md 审阅清单最后一条要防的
//  「看起来写完」。示例已挪进本文件底部的 Preview：只在 Xcode 里可见，
//  永远不会进入运行的 App。
//
//  两层的关系（计划 E3）：
//  下层是 `HandwritingCanvas`（PencilKit），承接用户手写；上层留给回应。
//  两层共用同一份纸色与同一个页面坐标系。先做两层叠加而不是把魂的笔画塞进
//  同一份 PKDrawing，是因为逐笔生长需要每帧精细控制，塞进 PencilKit 的数据里
//  不好控；等回应写完再「落定」进 PKDrawing（用户就能用橡皮擦掉，决策 18），
//  那属于计划 E1 之后的事。
//
//  已知的未决产品问题：用户在哪写、魂在哪回应，目前两者共用整页、毫无分隔，
//  所以会互相压字。这个版式决定待用户拍板（见 `MEMORY.md` 待决项）。
//

import PencilKit
import SwiftUI

struct DiaryPageView: View {
    @State private var reading: PencilStrokeReading?

    private let reader = PencilStrokeReader()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 画布自带纸色，因此它就是这一页的纸。
                HandwritingCanvas { drawing in
                    reading = reader.read(drawing)
                }

                #if DEBUG
                strokeReadout(in: geometry.size)
                #endif
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("日记页")
    }

    /// 开发期读数：确认手写真的被读成了引擎能用的笔画。
    /// 仅 DEBUG，产品面不该有任何这类数字（计划 E3c 接成页触发时删除）。
    @ViewBuilder
    private func strokeReadout(in size: CGSize) -> some View {
        if let reading {
            let force = reading.observedForceRange.map {
                String(format: "%.3f…%.3f", $0.lowerBound, $0.upperBound)
            } ?? "无"
            let samples = reading.polylines.reduce(0) { $0 + $1.points.count }
            Text("""
            DEBUG 笔画读数
            笔数 \(reading.polylines.count)　采样点 \(samples)
            力度范围 \(force)　有效压感 \(reading.hasVaryingForce ? "是" : "否")
            """)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(PageAppearance.ink.opacity(0.55))
            .padding(PageAppearance.pageMargin(for: size))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Preview

/// 开发期预览：把回应层单独摆出来看排版、字号、行距与书写节奏。
/// 这段文字是假的，只存在于 Xcode 预览里，不会进入运行的 App。
#Preview("空白日记页（运行时的真实样子）") {
    DiaryPageView()
}

#Preview("回应渲染（假文字，仅供看排版）") {
    ResponseLayoutPreview()
}

private struct ResponseLayoutPreview: View {
    private static let sampleResponse = """
    我看见你今天写得很慢。
    有些话不必写完，纸会替你记着。
    Take your time.
    """

    @State private var laidOut: LaidOutText?
    @State private var failure: String?
    @State private var size: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                PageAppearance.paper

                if let failure {
                    Text("排不出来：\(failure)")
                        .font(.footnote)
                        .foregroundStyle(PageAppearance.ink)
                        .padding(PageAppearance.pageMargin(for: geometry.size))
                } else if let laidOut {
                    HandwrittenTextView(
                        text: laidOut,
                        glyphHeight: HandwritingFeel.referenceGlyphHeightInPoints,
                        animated: true
                    )
                }
            }
            .onAppear { size = geometry.size }
            .onChange(of: geometry.size) { _, new in size = new }
        }
        .ignoresSafeArea()
        .task(id: size) {
            guard size.width > 0, size.height > 0 else { return }
            let margin = PageAppearance.pageMargin(for: size)
            do {
                laidOut = try TextLayout().layOut(
                    Self.sampleResponse,
                    configuration: TextLayoutConfiguration(
                        glyphHeight: HandwritingFeel.referenceGlyphHeightInPoints,
                        lineWidth: max(1, size.width - margin * 2),
                        lineSpacingRatio: PageAppearance.lineSpacingRatio,
                        origin: CGPoint(x: margin, y: margin)
                    )
                )
            } catch {
                failure = String(describing: error)
            }
        }
    }
}
