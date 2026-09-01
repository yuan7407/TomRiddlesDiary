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
                    pageNotice(notice, in: geometry.size, alignment: .top)
                }

                if case .soulSilent(let failure) = model.phase {
                    pageNotice(soulSilentNotice(failure), in: geometry.size, alignment: .bottom)
                }
            }
            // 可书写区域由这里算（页边距是视图尺寸的函数，模型不认识视图）。
            // 没有它魂定不了落点，所以一有尺寸就要报过去。
            .onAppear { reportPageArea(geometry.size) }
            .onChange(of: geometry.size) { _, new in reportPageArea(new) }
        }
        .ignoresSafeArea()
        .accessibilityLabel("日记页")
        .task { await model.loadRecognitionAvailability() }
    }

    private func reportPageArea(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let margin = PageAppearance.pageMargin(for: size)
        let glyph = HandwritingFeel.referenceGlyphHeightInPoints
        model.pageAreaChanged(PageRegion(
            left: margin,
            top: margin,
            // 夹一个字高的下界：比一个字还窄的可书写区域没有意义，
            // 而 PageRegion 不接受负宽高。
            width: max(glyph, size.width - margin * 2),
            height: max(glyph, size.height - margin * 2)
        ))
    }

    /// 魂接不上时纸上说什么（决策 13：只做诚实硬提示，不做假对话）。
    ///
    /// 为什么必须显示：渗墨、成页、识别都发生过了，用户有理由期待回应。
    /// 什么都不说看起来像 bug；编一句「我在想…」是伪装成功。
    ///
    /// 缺笔顺数据的字也在这里说。它和「魂没接上」不是一回事，但都属于
    /// 「纸上本该有的东西没出现」，放在同一处，用户才不用在两个地方找原因。
    private func soulSilentNotice(_ failure: OracleFailure) -> String {
        var sentence = failure.sentenceForReader
        if !model.uncoveredCharacters.isEmpty {
            sentence += "（另外这段里有写不出来的字：\(String(model.uncoveredCharacters))）"
        }
        return sentence
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

    /// 纸上的一行说明文字。
    ///
    /// 为什么识别提示不禁止书写：能读的语言照样能用（模拟器上英文就是好的），
    /// 一句话说清代价比直接不让人写更有用。
    /// 识别提示只在这一轮还没落笔时显示（`.nothingNew`），因为它的全部价值就是「写之前」。
    ///
    /// 两种提示分开上下摆：识别提示在上（关于「你要写的」），魂的提示在下
    /// （关于「已经写完的」）。同一个位置会互相盖掉。
    private func pageNotice(
        _ text: String,
        in size: CGSize,
        alignment: VerticalAlignment
    ) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(PageAppearance.ink.opacity(PageAppearance.noticeInkOpacity))
            .multilineTextAlignment(.center)
            .padding(PageAppearance.pageMargin(for: size))
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: alignment == .top ? .top : .bottom
            )
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

#Preview("日记页（DEBUG 里魂会用假文字真的回你）") {
    // 这一个预览就是运行时的样子，没有任何替代实现。
    //
    // 2026-09-01 删掉了原来那个 `GlyphStrokeReplayPreview`（计划 E6a）。
    // 它当初存在的理由是「App 里没有任何回应的生产者，所以逐笔生长与落笔中断
    // 只能在预览里跑」。现在 `MockOracleProvider` 让 App 自己就能走完整条链路，
    // 那份预览就变成了同一件事的第二套实现——而 `ReplyComposer` 文件头写着
    // 为什么不能有两套：预览里好看、App 里错位，是最难查的一类问题。
    //
    // DEBUG 里魂用的是**写死的假文字**（会明说，见 `MockOracleProvider`），
    // Release 里没有 provider，纸上会如实说魂接不上。
    DiaryPageView()
}
