//
//  DiaryPageView.swift
//  模块：Features/Canvas（用户书写的那张纸）
//
//  文件职责：App 的首屏，也是唯一的主界面——一张能写字的纸。
//  只负责把状态画出来；「这一页现在处于什么阶段」由 `DiaryPageModel` 决定。
//
//  取代原 ContentView.swift（2026-08-26）。原文件唯一的作用是把根视图指向
//  Magic Stroke Lab 诊断界面；Lab 已整体删除，这层空转的中转也一并去掉。
//
//  当前真实状态（诚实说明，别对着界面猜）：
//  你可以在纸上写字；停笔一会儿这一页会被收下并读懂（识别）。**读懂之后什么都不会发生**
//  ——魂（Oracle）还没接入（计划 E6）。界面上不会有任何提示，因为那属于开发期脚手架，
//  2026-08-29 已按用户要求全部清掉（成页预告横幅、「魂尚未接入」文案、页脚 DEBUG 读数）。
//  纸上唯一保留的非内容元素是「这台设备读不出哪些语言」那句提示，它是真正的产品功能
//  （计划 E4b）：缺语言模型时识别器会吐出看起来正常的垃圾，只能事先告知。
//
//  为什么不放一段示例回应在这里：
//  2026-08-28 之前这里有一段固定示例，进页面就自动逐字写出来。它当初的用途是
//  验证排版、字号、行距与书写节奏，那个任务已经完成（截图确认过）。但留着它会让
//  界面「看起来会回应」而实际不会——正是 AGENTS.md 审阅清单最后一条要防的
//  「看起来写完」。示例已挪进本文件底部的 Preview：只在 Xcode 里可见，
//  永远不会进入运行的 App。
//
//  两层的关系（计划 E3）：
//  下层是 `HandwritingCanvas`（PencilKit），承接用户手写；上层是魂的回应。
//  两层共用同一份纸色与同一个页面坐标系。先做两层叠加而不是把魂的笔画塞进
//  同一份 PKDrawing，是因为逐笔生长需要每帧精细控制，塞进 PencilKit 的数据里
//  不好控；等回应写完再「落定」进 PKDrawing（用户就能用橡皮擦掉，决策 18）。
//  回应层不接受点击，否则它会挡住下面的纸让人写不了字。
//
//  已知的未决产品问题：用户在哪写、魂在哪回应。用户已定方向（排在刚写完那句话旁边
//  找空位），但还没有实现，所以现在两层共用整页、毫无分隔。
//

import PencilKit
import SwiftUI

struct DiaryPageView: View {
    @State private var model = DiaryPageModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 画布自带纸色，因此它就是这一页的纸。
                HandwritingCanvas(
                    onStrokeBegan: { model.strokeBegan() },
                    onStrokeFinished: { model.strokeFinished($0) },
                    onPencilHoverChanged: { model.hoverChanged($0) }
                )

                if let reply = model.reply {
                    HandwritingReplayView(sequence: reply.sequence, playback: reply.playback)
                        .allowsHitTesting(false)
                }

                if let notice = recognitionNotice, model.phase == .nothingNew {
                    recognitionNoticeView(notice, in: geometry.size)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("日记页")
        .task { await model.loadRecognitionAvailability() }
    }

    /// 落笔**之前**要告诉用户的话，没有则为 nil（计划 E4b）。
    ///
    /// 为什么必须写在前面而不是等识别完再说：缺语言模型时识别器**不返回空**，
    /// 它会把笔画硬塞进它手上有的语言里，吐出一串看起来正常的垃圾
    /// （实测写「你好」得到 `15.47`）。而要判断「这几笔本来是中文」得先有中文模型
    /// ——事后过滤不掉。等接上 Oracle 之后，魂会一本正经地回应那串垃圾，
    /// 而你只会觉得 AI 很傻，完全查不到是输入端就错了。
    ///
    /// 两种情况必须分开说，因为解决办法完全不同：
    /// 系统太旧要升级系统；缺语言模型是这台设备本身读不出那种文字。
    private var recognitionNotice: String? {
        guard let availability = model.recognitionAvailability else { return nil }

        if !availability.systemProvidesRecognition {
            return "这台设备的系统还没有手写识别（需要 iPadOS \(HandwritingRecognizer.requiredSystemVersion)）。"
                + "写下的字暂时读不出来。"
        }
        guard !availability.unavailable.isEmpty else { return nil }
        return "这台设备读不出\(describeNames(availability.unavailable))手写。写了也会被认成别的字符，而且不会报错。"
    }

    /// 为什么不禁止书写：能读的语言照样能用（模拟器上英文就是好的），
    /// 一句话说清代价比直接不让人写更有用。
    /// 只在这一轮还没落笔时显示（`.nothingNew`），因为它的全部价值就是「写之前」。
    private func recognitionNoticeView(_ text: String, in size: CGSize) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(PageAppearance.ink.opacity(PageAppearance.noticeInkOpacity))
            .multilineTextAlignment(.center)
            .padding(PageAppearance.pageMargin(for: size))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    /// 把语言代码换成当前系统语言下的语言名。
    /// 不在代码里写「中文」这种字面量——请求的语言列表是配置项，写死名字迟早对不上。
    private func describeNames(_ languages: [Locale.Language]) -> String {
        let names = languages.compactMap { language in
            language.languageCode.flatMap {
                Locale.current.localizedString(forLanguageCode: $0.identifier)
            }
        }
        return names.isEmpty ? "部分语言的" : names.joined(separator: "、")
    }
}

// MARK: - Preview

#Preview("空白日记页（运行时的真实样子）") {
    DiaryPageView()
}

#Preview("回应渲染 · 字体版（E8 脚手架）") {
    ResponseLayoutPreview()
}

#Preview("真笔画逐笔生长 + 落笔中断（E1 + E3d）") {
    GlyphStrokeReplayPreview()
}

/// 开发期预览：把回应层单独摆出来看排版、字号、行距与书写节奏。
/// 这段文字是假的，只存在于 Xcode 预览里，不会进入运行的 App。
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

/// 开发期预览：**逐笔生长（E1）＋ 落笔中断（E3d）＋ 落点决策（E9e）**。
///
/// 怎么用：在纸上写点什么，停笔别动，等成页；魂就在**你刚写的那句话旁边**
/// 一笔一笔写出一段回应（右边或者下方，位置每轮都不一样）。
/// 回应正在长的时候你再写一笔，它立刻停在当时的进度上，**半截字留在页上**（决策 14）。
///
/// 为什么这个演示只在 Xcode 预览里、不在运行的 App 里：
/// 里面那段回应是**写死的假文字**。真正的回应只能来自 Oracle（计划 E6），还没接。
/// 把假回应放进 App 会让它看起来会回应而实际不会，那是伪装成功。
/// 所以它留在预览里——这里同时也是 E3d 与 E9e 唯一能真正跑起来的地方。
///
/// 已知限制：`beginReply` 一次只持有一段回应，新的一段会替掉上一段（连同页面上的墨）。
/// 「魂写过的几段都留在页上」属于翻页与页面存储的范围（计划 E3f / D），还没做。
private struct GlyphStrokeReplayPreview: View {
    /// 中英混排 + 标点，覆盖三套字形数据（汉字数据文件、手写标点、手写拉丁字母）。
    private static let sampleResponse = "我看见你写的 hello，慢一点。"

    @State private var model = DiaryPageModel()
    @State private var uncovered: [Character] = []
    @State private var failure: String?
    @State private var size: CGSize = .zero

    /// 已经回应过几轮。只用来给落点决策换种子，让每一轮的位置都不一样。
    @State private var round: UInt64 = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                HandwritingCanvas(
                    onStrokeBegan: { model.strokeBegan() },
                    onStrokeFinished: { model.strokeFinished($0) },
                    onPencilHoverChanged: { model.hoverChanged($0) }
                )

                if let reply = model.reply {
                    HandwritingReplayView(sequence: reply.sequence, playback: reply.playback)
                        .allowsHitTesting(false)
                }

                footnote(in: geometry.size)
            }
            .onAppear { size = geometry.size }
            .onChange(of: geometry.size) { _, new in size = new }
            // 成页之后才回应，而不是一进来就画：落点要挨着「你刚写的那句话」，
            // 所以必须等到真的有那句话。
            .onChange(of: model.phase) { _, phase in
                guard phase == .awaitingSoul else { return }
                respond(in: geometry.size)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func footnote(in size: CGSize) -> some View {
        if let failure {
            Text("写不出来：\(failure)")
                .font(.footnote)
                .foregroundStyle(PageAppearance.ink)
                .padding(PageAppearance.pageMargin(for: size))
        } else if !uncovered.isEmpty {
            // 缺字如实说出来，不让页面凭空少东西而无人知晓。
            Text("缺笔顺数据：\(String(uncovered))")
                .font(.caption2)
                .foregroundStyle(PageAppearance.ink.opacity(PageAppearance.noticeInkOpacity))
                .padding(PageAppearance.pageMargin(for: size))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
        }
    }

    /// 走完一整条「回应落在哪、排成什么样、怎么长出来」的链路。
    ///
    /// 顺序是有讲究的：先定落点（E9e），再按落点给的行宽排版（E9d），
    /// 最后才手绘化。反过来（先排版再找位置）就会得到一个宽度不合的文字块。
    private func respond(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let margin = PageAppearance.pageMargin(for: size)
        let glyphSize = HandwritingFeel.referenceGlyphHeightInPoints
        // 可书写区域 = 整页扣掉页边距。落点决策不认识「页边距」，由这里算好交给它。
        let writableArea = PageRegion(
            left: margin,
            top: margin,
            width: max(glyphSize, size.width - margin * 2),
            height: max(glyphSize, size.height - margin * 2)
        )

        do {
            let placement = try ReplyPlacementFinder().place(
                Self.sampleResponse,
                glyphSize: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio,
                after: model.lastRoundRegion,
                on: model.inkMap(writableArea: writableArea, glyphSize: glyphSize),
                // 每轮换种子，位置才会变。同一轮内重算则得到同一个位置。
                seed: HandwritingFeel.defaultSeed &+ round
            )
            round &+= 1

            let laidOut = try GlyphStrokeLayout().layOut(
                Self.sampleResponse,
                configuration: GlyphStrokeLayoutConfiguration(
                    glyphSize: glyphSize,
                    lineWidth: placement.lineWidth,
                    lineSpacingRatio: PageAppearance.lineSpacingRatio,
                    origin: CGPoint(x: placement.origin.x, y: placement.origin.y)
                )
            )
            let sequence = StrokePipeline().process(
                laidOut.polylines,
                configuration: HandwritingFeel.humanizerConfiguration(referenceScale: glyphSize),
                seed: HandwritingFeel.defaultSeed
            )
            uncovered = laidOut.uncoveredCharacters
            failure = nil
            model.beginReply(sequence)
        } catch {
            // 找不到空位（该翻页了）也走这里，如实显示，不硬塞一个位置。
            failure = String(describing: error)
        }
    }
}
