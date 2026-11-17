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
//  你可以在纸上写字；停笔一会儿这一页会被收下、读懂（识别），交给魂（Oracle），
//  魂的回应在你那句话旁边找空位逐笔写出来；写满了自动翻页（E3f）。
//  纸上的非内容元素只有两类提示：「这台设备读不出哪些语言」（E4b：缺语言模型时
//  识别器会吐出看起来正常的垃圾，只能事先告知）和「魂这次没能回应」的诚实说明。
//
//  页边距从安全区内侧量起（2026-11-16，迁到 iPhone 时实测暴露）：
//  纸本身铺满全屏（`.ignoresSafeArea()`），但可书写区域与提示文字都要避开
//  状态栏、灵动岛和底部横条。iPad 上状态栏很窄，短边 8% 的页边距恰好盖住它，
//  所以原先只算页边距没出过问题；iPhone 上顶部安全区约 62 点而页边距只有约 32 点，
//  提示文字直接压在时间和电池图标上，魂的回应也可能落到灵动岛底下。
//  这里统一成「安全区 + 页边距」，可书写区域和提示共用 `pageInsets` 一处算法。
//
//  为什么不放一段示例回应在这里：
//  2026-08-28 之前这里有一段固定示例，进页面就自动逐字写出来。它当初的用途是
//  验证排版、字号、行距与书写节奏，那个任务已经完成（截图确认过）。但留着它会让
//  界面「看起来会回应」而实际不会——正是 AGENTS.md 审阅清单最后一条要防的
//  「看起来写完」。示例已挪进本文件底部的 Preview：只在 Xcode 里可见，
//  永远不会进入运行的 App。
//
//  三层的关系（计划 E3、P1）：
//  最下面是纸（`PaperBackground`：纸纹 + 书脊阴影）；中间是透明的 `HandwritingCanvas`（PencilKit），
//  承接用户手写；最上面是魂的回应。三层共用同一个页面坐标系。魂的笔画不塞进 PKDrawing，
//  是因为逐笔生长需要每帧精细控制。原先打算写完再落定进 PKDrawing 好让橡皮擦掉（决策 18），
//  但网页原型定了「字不会被删掉，只会沉进纸里」（决策 80），那一步不再做。
//  回应层不接受点击，否则它会挡住下面的纸让人写不了字。
//

import PencilKit
import SwiftUI

struct DiaryPageView: View {
    // 魂写字用带节奏、带笔法、按意思换行的那一套装配（`ReplyComposer.forSoul()`）。
    // 在这里换而不是改 `DiaryPageModel` 的默认值：模型的测试守的是状态机，不该跟着手感一起变期望值。
    @State private var model = DiaryPageModel(composer: .forSoul())
    /// 合页姿态（`BookHinge` 报上来）。nil = 还没报，启动的头一瞬。
    @State private var posture: BookPosture?
    /// 系统报告的折缝。只有半开时才有（2026-11-17 实测），摊平时靠 `SpreadGeometry.resolve` 推断。
    @State private var reportedFold: PageRegion?

    var body: some View {
        // 外层不忽略安全区，只用来读真实的安全区；内层铺满全屏，是纸和页面坐标系。
        // 不能只用内层读：一个 `.ignoresSafeArea()` 的 GeometryReader 读到的安全区恒为 0
        // （2026-11-16 在 iPhone 模拟器上实测，第一版就是这么写的，提示照样压在状态栏上）。
        GeometryReader { screen in
            GeometryReader { geometry in
                let insets = pageInsets(geometry.size, safe: screen.safeAreaInsets)
                let spread = SpreadGeometry.resolve(
                    bounds: PageRegion(left: 0, top: 0, width: geometry.size.width, height: geometry.size.height),
                    reported: reportedFold,
                    posture: posture,
                    assumedFoldWidth: PaperLook.foldWidthPoints
                )
                ZStack(alignment: .topLeading) {
                    // 纸（纸纹 + 书脊阴影）在最底下；画布是透明的，只承接笔迹（计划 P1）。
                    PaperBackground(spread: spread)
                    // 页眉日期与页码：印刷体，是系统说的话（计划 P2）。第几张对开先按「第几页」算，
                    // P4 改成一轮一张对开后跟着换。
                    PageFurniture(spread: spread, leafNumber: model.book.currentIndex + 1, dateLine: PageFurniture.dateLine(for: Date()), safe: screen.safeAreaInsets)

                    HandwritingCanvas(
                        drawing: model.book.current.drawing,
                        drawingRevision: model.pageTurnCount,
                        onStrokeBegan: { model.strokeBegan() },
                        onStrokeFinished: { model.strokeFinished($0) },
                        onPencilHoverChanged: { model.hoverChanged($0) }
                    )

                    // 魂已经写下、定格留在页上的那些。纸上的东西不该自己消失——
                    // 2026-09-01 之前只画「正在写的那一段」，于是第二段一开始写、
                    // 第一段就从纸上消失了。
                    ForEach(Array(model.settledReplies.enumerated()), id: \.offset) { _, settled in
                        HandwritingReplayView(sequence: settled.sequence, playback: settled.playback)
                            .allowsHitTesting(false)
                    }

                    if let reply = model.reply {
                        HandwritingReplayView(sequence: reply.sequence, playback: reply.playback)
                            .allowsHitTesting(false)
                    }

                    if let notice = recognitionNotice, model.phase == .nothingNew {
                        pageNotice(notice, insets: noticeInsets(insets, spread: spread, size: geometry.size, belowDateWithSafeTop: screen.safeAreaInsets.top), alignment: .top)
                    }

                    if case .soulSilent(let failure) = model.phase {
                        pageNotice(soulSilentNotice(failure), insets: noticeInsets(insets, spread: spread, size: geometry.size), alignment: .bottom)
                    }

                    #if DEBUG
                    // 大方地说清楚：这段回应是写死的，不是模型说的。
                    //
                    // 为什么必须写在纸上而不是只写在代码注释里（2026-09-01 实测暴露）：
                    // 用户写了「Who are you?」，纸上长出一段关于阳台纸箱的话，
                    // 反馈是「回应完全不相关，像从文档里随机抓出来的」——那正是 Mock 的
                    // 设计行为，但**写死的回应和真回应在纸上长得一模一样**，
                    // 拿着 App 测的人分不清「模型很傻」和「这根本不是模型」。
                    //
                    // 只在 DEBUG。Release 里没有 provider，走的是上面那条诚实提示。
                    if model.soulSaysCannedThings, !model.settledReplies.isEmpty || model.reply != nil {
                        pageNotice(
                            "⚠️ DEBUG：上面那段字是写死的假回应，它不读你写的内容。真正的魂还没接上（计划 E6d，要 API key）。",
                            insets: noticeInsets(insets, spread: spread, size: geometry.size),
                            alignment: .bottom
                        )
                    }
                    #endif
                }
                // 可书写区域由这里算（页边距是视图尺寸的函数，模型不认识视图）。
                // 没有它魂定不了落点，所以一有尺寸就要报过去。
                .animation(pageTurn, value: model.pageTurnCount)
                .onAppear { reportPageArea(geometry.size, insets: insets) }
                .onChange(of: geometry.size) { _, new in
                    reportPageArea(new, insets: pageInsets(new, safe: screen.safeAreaInsets))
                }
                .onChange(of: screen.safeAreaInsets) { _, newSafe in
                    reportPageArea(geometry.size, insets: pageInsets(geometry.size, safe: newSafe))
                }
                // 合页与折缝（计划 P1）：折缝同时交给书脊阴影（上面的 `PaperBackground`）
                // 和占用图（回应不跨书脊）。姿态怎么改变成页是 P7 的事，这里只用它分辨内外屏。
                .background(SpreadReader { reported in
                    Color.clear.onChange(of: reported.fold, initial: true) { _, fold in reportedFold = fold }
                })
                .onBookPostureChange { new in
                    posture = new
                    #if DEBUG
                    print("── 合页 ── 姿态：\(new)")
                    #endif
                }
                .onChange(of: ReplyComposer.facingColumns(spread: spread, safeTop: screen.safeAreaInsets.top,
                                                          safeBottom: screen.safeAreaInsets.bottom,
                                                          safeTrailing: screen.safeAreaInsets.trailing), initial: true) { _, columns in
                    model.facingColumnsChanged(columns)
                }
                .onChange(of: spread.fold, initial: true) { _, fold in
                    model.foldChanged(fold)
                    #if DEBUG
                    print("── 对开 ── 屏幕 \(Int(geometry.size.width))×\(Int(geometry.size.height)) 折缝 \(fold.map { "\($0)" } ?? "无") 安全区 \(screen.safeAreaInsets)")
                    #endif
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityLabel("日记页")
        .task { await model.loadRecognitionAvailability() }
    }

    /// 翻页动画的时长与曲线（计划 E3f，决策 33）。
    ///
    /// ── 为什么是滑动而不是 3D 翻卷 ──
    /// 翻卷（page curl）在 SwiftUI 里要自己做三维变换与阴影，是一整块活；
    /// 而它要传达的信息只有一个：**这一页结束了，换了一张新的纸**。
    /// 横向滑动把这件事说清楚了，代价是十几行。真正的翻卷记为 E3f-2，
    /// 等这一版的手感被实际用过之后再决定值不值得做。
    ///
    /// ── 为什么不做「翻页提示」──
    /// 用户明确要求纸上零控件。翻页本身就是提示：纸滑走了，你就知道换页了。
    /// 决策 33 里提的「DEBUG 提示」由控制台那行日志承担。
    private var pageTurn: Animation {
        // 0.45 秒：比一般界面转场慢一点。纸是有重量的东西，翻得太快像切页不像翻页。
        // 这个值是手感选择，没有测量依据。
        .easeInOut(duration: 0.45)
    }

    /// 纸边到可书写区域的距离：每条边 = 系统安全区 + 页边距。原因见文件头「页边距从安全区内侧量起」。
    ///
    /// 页边距仍按整张纸的短边算（`PageAppearance.pageMargin`），不按扣掉安全区之后的尺寸：
    /// 那是纸的属性，不该因为状态栏多高而变。
    private func pageInsets(_ size: CGSize, safe: EdgeInsets) -> EdgeInsets {
        let margin = PageAppearance.pageMargin(for: size)
        return EdgeInsets(
            top: safe.top + margin,
            leading: safe.leading + margin,
            bottom: safe.bottom + margin,
            trailing: safe.trailing + margin
        )
    }

    /// 纸上提示的边距：在 `pageInsets` 的基础上，有竖缝时把它限制在右页之内（计划 P2）。
    ///
    /// 为什么是右页：原型里「在这一页上手写」的提示和他的第一句话都在右页，左页留给你写；
    /// 2026-11-17 实测之前，识别提示是一整行横跨书脊的。没有缝（外屏）或缝是横的时，照旧用整页。
    /// - Parameter belowDateWithSafeTop: 提示放在页眉日期下面时传安全区顶边，提示会让开日期那一行；
    ///   放在页底的提示传 nil。
    private func noticeInsets(_ insets: EdgeInsets, spread: SpreadGeometry, size: CGSize, belowDateWithSafeTop: Double? = nil) -> EdgeInsets {
        var confined = insets
        if let safeTop = belowDateWithSafeTop {
            let p = PaperLook.Printed.self
            confined.top = max(insets.top, safeTop + (p.dateBaselineFromTop + p.noticeGapBelowDate) * PaperLook.pointsPerPrototypeUnit)
        }
        guard let fold = spread.fold, spread.foldIsVertical == true else { return confined }
        confined.leading = max(insets.leading, fold.right + PageAppearance.pageMargin(for: size))
        return confined
    }

    private func reportPageArea(_ size: CGSize, insets: EdgeInsets) {
        guard size.width > 0, size.height > 0 else { return }
        let glyph = HandwritingFeel.referenceGlyphHeightInPoints
        model.pageAreaChanged(PageRegion(
            left: insets.leading,
            top: insets.top,
            // 夹一个字高的下界：比一个字还窄的可书写区域没有意义，
            // 而 PageRegion 不接受负宽高。
            width: max(glyph, size.width - insets.leading - insets.trailing),
            height: max(glyph, size.height - insets.top - insets.bottom)
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
            return "这台设备的系统还没有手写识别（需要 iOS \(HandwritingRecognizer.requiredSystemVersion)）。"
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
        insets: EdgeInsets,
        alignment: VerticalAlignment
    ) -> some View {
        PrintedNotice(text: text)
            .padding(insets)
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
