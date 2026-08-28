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
//  你可以在纸上写字；停笔一会儿后纸边会渗出一点墨（成页预告），再写一笔就能取消；
//  不写就会成页，这一页被读懂。**但读懂之后什么都不会发生**——魂（Oracle）
//  还没接入（计划 E6）。界面会用一行字如实说出这一点，不假装在思考。
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
//  已知的未决产品问题：用户在哪写、魂在哪回应，目前两者共用整页、毫无分隔，
//  所以会互相压字。这个版式决定待用户拍板（见 `MEMORY.md` 待决项）。
//  成页预告那团墨的位置也因此是临时的。
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

                #if DEBUG
                if model.phase == .aboutToRespond {
                    commitHint(in: geometry.size)
                }
                #endif

                if model.phase == .awaitingSoul {
                    soulNotConnectedNotice(in: geometry.size)
                } else if let missing = unreadableLanguages, model.phase == .nothingNew {
                    unreadableLanguageNotice(missing, in: geometry.size)
                }

                #if DEBUG
                strokeReadout(in: geometry.size)
                #endif
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("日记页")
        .task { await model.loadRecognitionAvailability() }
    }

    /// 本机读不出来的语言。没有查完、或者全都能读时为 nil。
    private var unreadableLanguages: [Locale.Language]? {
        guard let availability = model.recognitionAvailability,
              !availability.unavailable.isEmpty
        else { return nil }
        return availability.unavailable
    }

    /// 落笔**之前**就告知这台设备读不出哪些语言（计划 E4b）。
    ///
    /// 为什么必须写在前面而不是等识别完再说：缺语言模型时识别器不会返回空，
    /// 它会把笔画硬塞进它手上有的语言里，吐出一串看起来正常的垃圾
    /// （实测写「你好」得到 `15.47`）。而要判断「这几笔本来是中文」，你得先有中文模型
    /// ——事后过滤不掉。等接上 Oracle 之后，魂会一本正经地回应那串垃圾，
    /// 而你只会觉得 AI 很傻，完全查不到是输入端就错了。
    ///
    /// 为什么不禁止书写：能读的语言照样能用（模拟器上英文就是好的），
    /// 一句话说清代价比直接不让人写更有用。
    ///
    /// 语言名字用系统本地化，不在代码里写「中文」这种字面量——请求的语言列表
    /// 是配置项，写死名字迟早对不上。
    /// 只在这一轮还没落笔时显示（`.nothingNew`），因为它的全部价值就是「写之前」。
    private func unreadableLanguageNotice(_ missing: [Locale.Language], in size: CGSize) -> some View {
        Text("这台设备读不出\(describeNames(missing))手写。写了也会被认成别的字符，而且不会报错。")
            .font(.footnote)
            .foregroundStyle(PageAppearance.ink.opacity(PageAppearance.noticeInkOpacity))
            .multilineTextAlignment(.center)
            .padding(PageAppearance.pageMargin(for: size))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    /// 把语言代码换成当前系统语言下的语言名。
    private func describeNames(_ languages: [Locale.Language]) -> String {
        let names = languages.compactMap { language in
            language.languageCode.flatMap {
                Locale.current.localizedString(forLanguageCode: $0.identifier)
            }
        }
        return names.isEmpty ? "部分语言的" : names.joined(separator: "、")
    }

    /// 成页预告，**仅 DEBUG**。
    ///
    /// 为什么从产品面撤下来（2026-08-29 用户实测判断）：
    /// 原先是页面左上角渗出一团墨，越接近成页洇得越开。用户的反馈是「看上去真的很像个 bug」——
    /// 一个淡淡的圆点出现在页边距、离你写字的地方半页远、只存在一秒半，
    /// 看不出是提示，只看得出页面上多了个不该有的东西。
    ///
    /// 「可撤销预告」这个需求没有撤销（决策 17 要求猜错零代价可救），只是它的**正确形态
    /// 取决于版式决定**：提示应该出现在魂即将落笔的地方，也就是你刚写完那句话旁边。
    /// 版式还没定（见 `MEMORY.md` 待决项），所以现在不猜一个位置糊上去。
    /// 在那之前 DEBUG 面用一条一眼看得懂的横幅代替，产品面什么都不显示。
    private func commitHint(in size: CGSize) -> some View {
        Text("DEBUG · 快要回应了 —— 现在写一笔可以取消")
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(PageAppearance.paper)
            .padding(.horizontal, PageAppearance.noticePadding)
            .padding(.vertical, PageAppearance.noticePadding / 2)
            .background(PageAppearance.ink.opacity(PageAppearance.debugBannerOpacity))
            .padding(PageAppearance.pageMargin(for: size))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityLabel("日记页快要回应了，此刻再写一笔可以取消")
    }

    /// 成页之后的诚实提示。
    ///
    /// **这是开发期文案，接上 Oracle（计划 E6）后删除。** 留它的理由：
    /// 成页预告渗出的墨会让人以为接着就有回应，而现在确实什么都不会来。
    /// 什么都不说会像 bug，编一句世界观内的台词（「我在想…」）则是伪装成功——
    /// 那正是 AGENTS.md 禁止的静默兜底。所以就说实话。
    private func soulNotConnectedNotice(in size: CGSize) -> some View {
        Text("这一页收下了。回应还没接上——魂（Oracle）尚未接入。")
            .font(.footnote)
            .foregroundStyle(PageAppearance.ink.opacity(PageAppearance.noticeInkOpacity))
            .multilineTextAlignment(.center)
            .padding(PageAppearance.pageMargin(for: size))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    /// 开发期读数：确认手写真的被读成了引擎能用的笔画，以及成页判断在按什么阈值走。
    /// 仅 DEBUG，产品面不该有任何这类数字。
    @ViewBuilder
    private func strokeReadout(in size: CGSize) -> some View {
        if let reading = model.reading {
            Text(readoutText(reading))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(PageAppearance.ink.opacity(PageAppearance.noticeInkOpacity))
                .padding(PageAppearance.pageMargin(for: size))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
        }
    }

    private func readoutText(_ reading: PencilStrokeReading) -> String {
        let force = reading.observedForceRange.map {
            String(format: "%.3f…%.3f", $0.lowerBound, $0.upperBound)
        } ?? "无"
        let samples = reading.polylines.reduce(0) { $0 + $1.points.count }
        let rhythm = reading.rhythm
        let median = rhythm.medianPause.map { String(format: "%.2f", $0) } ?? "—"
        let longest = rhythm.longestPause.map { String(format: "%.2f", $0) } ?? "—"

        var lines = [
            "DEBUG 读数",
            "本轮笔数 \(reading.polylines.count)　采样点 \(samples)",
            "力度 \(force)　有效压感 \(reading.hasVaryingForce ? "是" : "否")",
            String(
                format: "停顿 中位 %@s 最长 %@s　书写 %.1fs 落墨 %.1fs",
                median, longest, rhythm.totalDuration, rhythm.inkDuration
            ),
            String(
                format: "成页阈值 %.2fs　悬停 %@",
                model.commitWaitLength,
                model.isPencilHovering ? "是" : "否（本机硬件不支持）"
            ),
            // 阶段发布次数是查「笔画消失」的临时诊断（见 `DiaryPageModel` 文件头）。
            // 一轮书写应该只有个位数；几十次说明高频重建回来了。确认修好后删掉。
            "阶段 \(describe(model.phase))　阶段发布 \(model.phaseUpdateCount) 次",
        ]

        if let recognition = model.recognition {
            let availability = recognition.availability
            lines.append("识别语言 可用[\(describe(availability.active))]　缺失[\(describe(availability.unavailable))]")
            if !availability.isUsable {
                lines.append("识别不可用：本机没有任何请求语言的模型")
            } else if let text = recognition.text, recognition.hasText {
                lines.append("认出：\(text.replacingOccurrences(of: "\n", with: "⏎"))")
            } else {
                lines.append("认出：（无）——有可用语言但没认出内容")
            }
        } else {
            lines.append("识别中…")
        }

        // 落笔前查到的语言状况（E4b 的信号来源）。和上面那条不同：
        // 这一条不依赖有没有识别过，所以空白页上也看得见。
        if let availability = model.recognitionAvailability {
            lines.append("本机可读[\(describe(availability.active))]　读不出[\(describe(availability.unavailable))]")
        } else {
            lines.append("本机识别能力查询中…")
        }

        return lines.joined(separator: "\n")
    }

    private func describe(_ phase: DiaryPagePhase) -> String {
        switch phase {
        case .nothingNew: "这一轮没有新内容"
        case .writing: "正在写"
        case .waiting: "等你写完"
        case .aboutToRespond: "预告中（再写一笔可取消）"
        case .understanding: "正在读懂这一页"
        case .awaitingSoul: "已收下（魂未接入）"
        }
    }

    private func describe(_ languages: [Locale.Language]) -> String {
        languages.isEmpty ? "—" : languages.map(\.minimalIdentifier).joined(separator: ",")
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

/// 开发期预览：**真正的逐笔生长（E1）＋ 落笔中断（E3d）**。
///
/// 进来就把一段文字查成字形笔画、喂进笔画引擎、一笔一笔画出来；
/// 你在纸上写一笔，重播立刻停在当时的进度上，**半截字留在页上**（决策 14）。
/// 这是打断规则唯一能真正跑起来的地方——运行的 App 里还没有任何回应的生产者
/// （Oracle 属计划 E6），所以那条路径在 App 里到不了。
///
/// 文字是假的，只存在于 Xcode 预览里。
private struct GlyphStrokeReplayPreview: View {
    /// 纯汉字：当前字形数据集不含标点与拉丁字母（属计划 E1c/E1d），
    /// 用带标点的句子会看到缺字，反而看不清逐笔生长本身。
    private static let sampleResponse = "我看见你今天写得很慢"

    @State private var model = DiaryPageModel()
    @State private var uncovered: [Character] = []
    @State private var failure: String?
    @State private var size: CGSize = .zero

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
        }
        .ignoresSafeArea()
        .task(id: size) { await build() }
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

    private func build() async {
        guard size.width > 0, size.height > 0 else { return }
        let margin = PageAppearance.pageMargin(for: size)
        let glyphSize = HandwritingFeel.referenceGlyphHeightInPoints

        do {
            let laidOut = try GlyphStrokeLayout().layOut(
                Self.sampleResponse,
                configuration: GlyphStrokeLayoutConfiguration(
                    glyphSize: glyphSize,
                    lineWidth: max(glyphSize, size.width - margin * 2),
                    lineSpacingRatio: PageAppearance.lineSpacingRatio,
                    origin: CGPoint(x: margin, y: margin)
                )
            )
            let sequence = StrokePipeline().process(
                laidOut.polylines,
                configuration: HandwritingFeel.humanizerConfiguration(referenceScale: glyphSize),
                seed: HandwritingFeel.defaultSeed
            )
            uncovered = laidOut.uncoveredCharacters
            model.beginReply(sequence)
        } catch {
            failure = String(describing: error)
        }
    }
}
