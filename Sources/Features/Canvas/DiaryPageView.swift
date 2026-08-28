//
//  DiaryPageView.swift
//  模块：Features/Canvas（用户书写的那张纸）
//
//  文件职责：App 的首屏，也是唯一的主界面——一张能写字的纸，以及写在纸上的回应。
//
//  取代原 ContentView.swift（2026-08-26）。原文件唯一的作用是把根视图指向
//  Magic Stroke Lab 诊断界面；Lab 已整体删除，这层空转的中转也一并去掉。
//
//  两层的关系（计划 E3）：
//  下层是 `HandwritingCanvas`（PencilKit），承接用户手写；上层是回应层。
//  两层共用同一份纸色与同一个页面坐标系。先做两层叠加而不是把魂的笔画塞进
//  同一份 PKDrawing，是因为逐笔生长需要每帧精细控制，塞进 PencilKit 的数据里
//  不好控；等回应写完再「落定」进 PKDrawing（用户就能用橡皮擦掉，决策 18），
//  那属于计划 E1 之后的事。
//
//  当前状态（E8 脚手架 + E3 画布）：
//  Oracle 还没接，所以回应层显示的是一段**固定示例文字**，进入页面后自动逐字
//  写出来。这段示例是开发期内容，接入真实 Oracle 时必须删掉（计划 E6）——
//  它不代表 AI 真的回应了什么。
//  用户手写目前只做到「能写 + 能读成引擎格式」，还没有拿它做任何事：
//  成页触发、识别、回应都还没接。页脚有一行 DEBUG 读数用来确认笔画真的被读到。
//
//  排版为什么放在 `.task` 里而不是 body 里：
//  第一版把排版写在 body 中，失败时返回 nil，结果是**纸上一片空白、没有任何提示**
//  ——这正是 AGENTS.md 禁止的静默兜底，而且当时确实因此看不出问题在哪。
//  现在用一个显式的三态（还没排 / 排好了 / 失败了），失败必须显示原因。
//

import PencilKit
import SwiftUI

struct DiaryPageView: View {
    /// 开发期示例回应。接入真实 Oracle 时删除（计划 E6）。
    private static let sampleResponse = """
    我看见你今天写得很慢。
    有些话不必写完，纸会替你记着。
    Take your time.
    """

    /// 页面的三种状态。刻意不用「可选值 + nil 当失败」：那样分不清「还没排」和
    /// 「排失败了」，而这两种情况在界面上必须表现不同。
    private enum PageState {
        case notLaidOut
        case ready(LaidOutText)
        case failed(String)
    }

    @State private var state: PageState = .notLaidOut
    @State private var pageSize: CGSize = .zero
    @State private var reading: PencilStrokeReading?

    private let reader = PencilStrokeReader()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 下层：用户手写。画布自带纸色，因此它就是这一页的纸。
                HandwritingCanvas { drawing in
                    reading = reader.read(drawing)
                }

                // 上层：魂的回应。不设背景，透出下面的纸。
                switch state {
                case .notLaidOut:
                    Color.clear
                case .ready(let laidOut):
                    HandwrittenTextView(
                        text: laidOut,
                        glyphHeight: HandwritingFeel.referenceGlyphHeightInPoints,
                        animated: true
                    )
                    .allowsHitTesting(false)
                case .failed(let reason):
                    failureNotice(reason, in: geometry.size)
                }

                #if DEBUG
                strokeReadout(in: geometry.size)
                #endif
            }
            .onAppear { pageSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in pageSize = newSize }
        }
        .ignoresSafeArea()
        .accessibilityLabel("日记页")
        .task(id: pageSize) {
            await layOut(in: pageSize)
        }
    }

    /// 排版失败时如实说明。不假装页面是空的——空白会让人以为「还没写」，
    /// 而实际上是写不出来。
    private func failureNotice(_ reason: String, in size: CGSize) -> some View {
        Text("这一页写不出来：\(reason)")
            .font(.footnote)
            .foregroundStyle(PageAppearance.ink)
            .padding(PageAppearance.pageMargin(for: size))
    }

    /// 开发期读数：确认手写真的被读成了引擎能用的笔画。
    /// 仅 DEBUG，产品面不该有任何这类控件或数字（计划 E3d 接成页触发时删除）。
    @ViewBuilder
    private func strokeReadout(in size: CGSize) -> some View {
        if let reading {
            let force = reading.observedForceRange.map {
                String(format: "%.3f…%.3f", $0.lowerBound, $0.upperBound)
            } ?? "无"
            Text("""
            DEBUG 笔画读数
            笔数 \(reading.polylines.count)　\
            采样点 \(reading.polylines.reduce(0) { $0 + $1.points.count })
            力度范围 \(force)　有效压感 \(reading.hasVaryingForce ? "是" : "否")
            """)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(PageAppearance.ink.opacity(0.55))
            .padding(PageAppearance.pageMargin(for: size))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
        }
    }

    private func layOut(in size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }

        let margin = PageAppearance.pageMargin(for: size)
        let configuration = TextLayoutConfiguration(
            glyphHeight: HandwritingFeel.referenceGlyphHeightInPoints,
            lineWidth: max(1, size.width - margin * 2),
            lineSpacingRatio: PageAppearance.lineSpacingRatio,
            origin: CGPoint(x: margin, y: margin)
        )

        do {
            let laidOut = try TextLayout().layOut(Self.sampleResponse, configuration: configuration)
            state = .ready(laidOut)
        } catch {
            state = .failed(String(describing: error))
        }
    }
}

#Preview {
    DiaryPageView()
}
