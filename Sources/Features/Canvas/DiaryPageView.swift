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
//  纸上的非内容元素只有印刷体的诚实说明：「他的记忆出了问题」（K3）和「魂这次没能回应」。
//  外屏合着时最上面盖一张封面（计划 S 组，`BookCover`），翻开才是纸。
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
    @State private var model = DiaryPageModel(composer: .forSoul(), memory: .onDevice())
    /// 合页姿态（`BookHinge` 报上来）。nil = 还没报，启动的头一瞬。
    @State private var posture: BookPosture?
    /// 系统报告的折缝。只有半开时才有（2026-11-17 实测），摊平时靠 `SpreadGeometry.resolve` 推断。
    @State private var reportedFold: PageRegion?
    /// 开场那句印刷体提示淡出来了没有（计划 P6）。
    @State private var openingHintShown = false
    /// 外屏的封面盖不盖着（计划 S 组）。规则全在 `CoverState`。
    @State private var cover = CoverState()
    /// 他写字时手上沙沙的触感（计划 P10）。
    @State private var haptics = WritingHaptics()
    @Environment(\.scenePhase) private var scenePhase

    /// 开场白（他的话，在 Persona.json）。读一次就够：人设在一次运行里不会变。
    private static let opening = OracleAssembly.bundledPersona()?.opening

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
                let showsCover = cover.showsCover(posture: posture, isPortrait: geometry.size.height > geometry.size.width)
                // 他什么时候先开口：纸露出来了才开（外屏要先翻开封面）；摊开的内屏还要等两页的栏位算好，
                // 否则会在内屏上按单页排开场。
                let openingReady = !showsCover && posture != nil && (posture == .closed || model.facingColumns != nil)
                ZStack(alignment: .topLeading) {
                    // 纸（纸纹 + 书脊阴影）在最底下；画布是透明的，只承接笔迹（计划 P1）。
                    PaperBackground(spread: spread)
                    // 页眉日期与页码：印刷体，是系统说的话（计划 P2）。第几张对开先按「第几页」算，
                    // P4 改成一轮一张对开后跟着换。
                    PageFurniture(spread: spread, leafNumber: model.leafNumber, dateLine: PageFurniture.dateLine(for: Date()), safe: screen.safeAreaInsets)

                    HandwritingCanvas(
                        drawing: model.book.current.drawing,
                        drawingRevision: model.drawingRevision,
                        onStrokeBegan: { model.strokeBegan() },
                        onStrokeFinished: { model.strokeFinished($0) },
                        onPencilHoverChanged: { model.hoverChanged($0) }
                    )

                    // 你这一轮被纸喝下去，喝完留一层压痕（计划 P4）。
                    if let drinking = model.drinking {
                        DrinkingInkView(ink: drinking)
                    }

                    // 他上一段话沉下去（计划 P4）。
                    ForEach(model.sinking) { item in
                        SinkingReplyView(item: item)
                    }

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

                    // 开场那道线下面的提示：印刷体，是系统说的话（计划 P6）。你落笔后模型会清掉它。
                    if let point = model.openingHintPoint {
                        PrintedNotice(text: SoulHand.Opening.hintText, style: PaperLook.Printed.openingHint)
                            .fixedSize()
                            .position(x: point.x, y: point.y)
                            .opacity(openingHintShown ? 1 : 0)
                            .allowsHitTesting(false)
                            .task {
                                try? await Task.sleep(for: .seconds(SoulHand.Opening.hintDelay - SoulHand.Opening.delay))
                                withAnimation(.easeIn(duration: SoulHand.Opening.hintFade)) { openingHintShown = true }
                            }
                    }

                    // 他读到的是什么：印在他那页的页脚（R3/P9）。读错了你一眼就知道是没看清，不是他答非所问。
                    if let heard = model.heard, let reply = model.reply,
                       let box = PageRegion.covering(reply.sequence.polylines) {
                        HeardLine(heard: heard, replyBox: box, spread: spread, safeBottom: screen.safeAreaInsets.bottom)
                    }

                    #if DEBUG
                    // R0 识别诊断 + 记忆（K）：这一轮交了几笔、手机认出什么、他读到什么；他记得什么。只在 DEBUG。
                    // 放在页顶日期下面：页脚是「他读到的是」那一行，放在下面会叠在一起（2026-11-18 真机截图）。
                    if let line = model.diagnosis?.line {
                        Text(line + "\n" + model.memory.debugLine)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.7))
                            .padding(noticeInsets(insets, spread: spread, size: geometry.size, belowDateWithSafeTop: screen.safeAreaInsets.top))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .allowsHitTesting(false)
                    }
                    #endif

                    if let problem = model.memory.problem {
                        // 记忆出了问题：如实印出来（K3），印在页顶日期下面。
                        pageNotice(problem.sentence, insets: noticeInsets(insets, spread: spread, size: geometry.size, belowDateWithSafeTop: screen.safeAreaInsets.top), alignment: .top)
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

                    // 外屏的封面盖在最上面（计划 S 组）：盖着时纸上什么都碰不到、写不了字。
                    if showsCover {
                        BookCoverView(
                            closesWithMotion: cover.closesWithMotion,
                            onOpened: { cover.opened() },
                            onCloseMotionPlayed: { cover.closeMotionPlayed() }
                        )
                    }
                }
                .statusBarHidden(showsCover)
                // 可书写区域由这里算（页边距是视图尺寸的函数，模型不认识视图）。
                // 没有它魂定不了落点，所以一有尺寸就要报过去。
                .animation(pageTurn, value: model.pageTurnCount)
                .onAppear { reportPageArea(geometry.size, insets: insets, safeTop: screen.safeAreaInsets.top) }
                .onChange(of: geometry.size) { _, new in
                    reportPageArea(new, insets: pageInsets(new, safe: screen.safeAreaInsets), safeTop: screen.safeAreaInsets.top)
                }
                .onChange(of: screen.safeAreaInsets) { _, newSafe in
                    reportPageArea(geometry.size, insets: pageInsets(geometry.size, safe: newSafe), safeTop: newSafe.top)
                }
                // 合页与折缝（计划 P1）：折缝同时交给书脊阴影（上面的 `PaperBackground`）
                // 和占用图（回应不跨书脊）。姿态怎么改变成页是 P7 的事，这里只用它分辨内外屏。
                .background(SpreadReader { reported in
                    Color.clear.onChange(of: reported.fold, initial: true) { _, fold in reportedFold = fold }
                })
                .onBookPostureChange { new in
                    cover.postureChanged(from: posture, to: new)
                    model.postureChanged(new)
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
                // 翻开本子他先开口（计划 P6、S6）：纸露出来才开，一次启动一次。
                // 知道你的称呼就说「你回来了，<称呼>」，不知道就问（称呼存在记忆里，K2）。
                .task(id: openingReady) {
                    guard openingReady, !model.openingShown, let opening = Self.opening else { return }
                    let hour = Calendar.current.component(.hour, from: Date())
                    guard let lines = opening.lines(hour: hour, name: model.memory.remembered.name) else { return }
                    await model.openBook(lines: lines, spreadHeight: geometry.size.height)
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
        // 纸外的求助条（决策 67）：盖在纸上面、普通系统样式，你点「知道了」就收起。
        .overlay(alignment: .bottom) {
            if model.needsCare { CareSlipView { model.dismissCare() }.padding(16) }
        }
        // 他一开始写，手上就有沙沙的触感；被你落笔打断、写完、沉下去时停（计划 P10）。
        // 合着本子时他接着写，触感也照样有——这是合上时唯一能感觉到他在写的东西。
        .onChange(of: model.reply?.playback) { _, playback in
            if case .playing(let since)? = playback, let reply = model.reply {
                haptics.play(reply.sequence, from: (ContinuousClock.now - since).inSeconds)
            } else {
                haptics.stop()
            }
        }
        // 切到后台、锁屏：回来时是封面（用户 2026-11-18 定）。
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cover.leftTheApp() }
        }
        .accessibilityLabel("日记页")
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

    /// 报给模型的「他能写字的区域」：页边距以内，并且从页眉日期下面开始——
    /// 2026-11-18 真机外屏，他的开场白「你来了。」写在了日期上面。你自己写字不受这个限制（画布是整张纸）。
    private func reportPageArea(_ size: CGSize, insets: EdgeInsets, safeTop: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let glyph = HandwritingFeel.referenceGlyphHeightInPoints
        let p = PaperLook.Printed.self
        let top = max(insets.top, safeTop + (p.dateBaselineFromTop + p.noticeGapBelowDate) * PaperLook.pointsPerPrototypeUnit)
        model.pageAreaChanged(PageRegion(
            left: insets.leading,
            top: top,
            // 夹一个字高的下界：比一个字还窄的可书写区域没有意义，
            // 而 PageRegion 不接受负宽高。
            width: max(glyph, size.width - insets.leading - insets.trailing),
            height: max(glyph, size.height - top - insets.bottom)
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

    /// 纸上的一行说明文字（印刷体，系统说的）。
    ///
    /// 两种提示分开上下摆：记忆出问题的在上，魂接不上的在下。同一个位置会互相盖掉。
    ///
    /// 2026-11-18 删掉了原来页顶的「这台设备读不出某种语言的手写」（计划 E4b）：R3 起每一轮都把笔迹图交给
    /// 模型读，手机认不认得出都不影响他读到你写的字，那句提示已经不是真的了。
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
