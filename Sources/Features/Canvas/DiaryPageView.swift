//
//  DiaryPageView.swift
//  模块：Features/Canvas（用户书写的那张纸）
//
//  文件职责：App 的首屏，也是唯一的主界面——一张纸，以及写在纸上的回应。
//
//  取代原 ContentView.swift（2026-08-26）。原文件唯一的作用是把根视图指向
//  Magic Stroke Lab 诊断界面；Lab 已整体删除，这层空转的中转也一并去掉。
//
//  当前状态（计划 E8 脚手架）：
//  Apple Pencil 输入（PencilKit）还没接，所以纸上不会有用户写的字。为了能看见
//  并评判排版、字号、行距与书写节奏，这里放一段**固定的示例回应**，进入页面后
//  自动逐字写出来。这段示例是开发期的临时内容，接入真实输入与 Oracle（计划 E3、
//  E6）时必须删掉——它不是产品内容，也不代表 AI 真的回应了什么。
//
//  排版为什么放在 `.task` 里而不是 body 里：
//  第一版把排版写在 body 中，失败时返回 nil，结果是**纸上一片空白、没有任何提示**
//  ——这正是 AGENTS.md 禁止的静默兜底，而且当时确实因此看不出问题在哪。
//  现在用一个显式的三态（还没排 / 排好了 / 失败了），失败必须显示原因。
//  顺带解决另一个问题：在 body 里排版意味着每次重绘都跑一遍 CoreText。
//

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

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                PageAppearance.paper

                switch state {
                case .notLaidOut:
                    // 还没排完版，纸上本就该是空的，不放任何加载提示。
                    Color.clear
                case .ready(let laidOut):
                    HandwrittenTextView(
                        text: laidOut,
                        glyphHeight: HandwritingFeel.referenceGlyphHeightInPoints,
                        animated: true
                    )
                case .failed(let reason):
                    failureNotice(reason, in: geometry.size)
                }
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
