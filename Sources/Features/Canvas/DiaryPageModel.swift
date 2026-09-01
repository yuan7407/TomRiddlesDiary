//
//  DiaryPageModel.swift
//  模块：Features/Canvas（一页日记此刻的状态）
//
//  文件职责：管住「这一页正在发生什么」——你在写、写完了、要成页了、已经收下了，
//  以及魂那段回应播到哪儿了。落笔与抬笔的事件进来，阶段与打断的结果出去。
//
//  为什么要单独一个类而不是留在视图的 @State 里（2026-08-29）：
//  成页判断是一条**按时间轮询**的循环（每 0.1 秒问一次 `PageCommitTrigger`），
//  而它每次都要读三个会在等待期内变化的值：经过时间、笔是否悬停、识别有没有返回。
//  写在 SwiftUI 视图里的话，循环所在的闭包捕获的是视图那个**结构体值**，
//  读到的可能不是最新的状态，这类问题不会报错、只会偶发地判断错。
//  用一个引用类型持有这些状态，循环读到的一定是当前值。
//
//  ── 2026-08-29 修的一个自己造的 bug：用户写的笔画写完就从纸上消失 ──
//
//  症状：写完一笔，墨迹消失。但笔画数据全在（读数显示笔数 6、采样点 353，
//  识别也认出了 `hell`），纸的底色也还在——也就是说 PencilKit 的数据和视图都是好的，
//  只有已画的墨没被重绘出来。
//
//  原因：倒计时循环每 0.1 秒往 `phase` 写一次值，**而且值没变也写**
//  （`.waiting` → `.waiting`），再加上原先 `.aboutToRespond` 还带着每帧都在变的
//  「还剩几秒」。`@Observable` 不比较新旧值，于是从抬笔那一刻起界面每秒重建十次，
//  一直到成页。PencilKit 的墨迹层被反复标记为需要重绘，而模拟器空闲时会冻结
//  渲染循环（见 `MEMORY.md` 已知陷阱），重绘一直没发生，墨就没了。
//
//  两处改法：一、阶段只在真的变化时才发布（`setPhase`）；
//  二、阶段不再携带高频变化的数据。改完一次等待期只发布四次（等待 → 预告 →
//  读懂 → 已收下），而不是几十次。
//
//  这条修复的长期守卫是 `DiaryPageModelTests.testPhaseIsPublishedOnlyWhenItActuallyChanges`
//  （一轮等待期只许发布个位数次阶段变化）。当时另加的临时计数器已于同日删除——
//  它的用途只是让人从界面上读出发布次数，而那件事测试已经在管了。
//
//  已知的产品问题（不在本步解决，别当成已解决）：
//  一、成页时识别的是**整页**，也就是包含之前已经收下过的内容。真实产品里
//  魂不该把旧内容再读一遍。怎么切分「这一轮写的」取决于版式决定（用户在哪写、
//  魂在哪回应），那个决定还没做，见 `MEMORY.md` 待决项。
//  二、每抬一次笔就识别一次整页。这么做是有原因的——终止标点加速信号需要在
//  成页**之前**就知道你写了句号，而识别是异步的，等到成页再识别就永远来不及。
//  代价是识别频率随页面变长而变贵。真机测出识别延迟后若发现太贵，就把它降级成
//  只在成页时识别，同时失去标点加速（属计划 B 性能优化）。
//

import Foundation
import PencilKit

/// 这一页此刻处于哪个阶段。
nonisolated enum DiaryPagePhase: Equatable, Sendable {
    /// 这一轮没有新内容可回应。
    ///
    /// 两种情况都归这里：页面一片空白，或者你把这一轮刚写的字擦掉了。
    /// 原来叫 `.blank`，2026-08-29 改名——引入「一轮」的概念之后（计划 E3e），
    /// 页面上可能还留着上一轮的字，说它「空白」是假话。
    case nothingNew

    /// 笔正在纸上。此时不做任何成页判断——你显然还在写。
    case writing

    /// 抬笔了，在等你是不是还要接着写。
    case waiting

    /// 预告期：马上要成页了。此刻再写一笔即可取消（决策 17 要求猜错零代价可救）。
    ///
    /// **刻意不带「还剩几秒」这种每帧都在变的数据。** 原先它带了，结果每 0.1 秒
    /// 就发布一次新值，界面每秒重建十次——这正是 2026-08-29 那个「笔画写完就消失」
    /// 的头号嫌疑（详见 `DiaryPageModel` 文件头）。阶段就该是粗粒度的。
    case aboutToRespond

    /// 已成页，正在读懂这一页写了什么（识别在跑）。
    case understanding

    /// 读懂了，文字已经交给魂，在等它说话。
    ///
    /// 2026-09-01 从 `.awaitingSoul` 改名（计划 E6a）。旧名字的含义是
    /// 「魂还没接上，这一步之后真的什么都不会发生」——那在当时是实话。
    /// 现在真的会有东西发生了，所以名字必须跟着变：`askingSoul` 表示
    /// **请求已经在路上**，而不是「等一个不存在的东西」。
    case askingSoul

    /// 魂正在纸上一笔一笔写。
    case replying

    /// 魂接不上，而且**如实说出是哪一种接不上**。
    ///
    /// 带上原因而不是合成一个「失败」：三种原因的处置完全不同
    /// （没配 provider 要接后端、没读出字要重写、送不出去可以再试），
    /// 合成一个会让用户按错方向去解决。
    case soulSilent(OracleFailure)
}

extension DiaryPagePhase {
    /// 成页**已经走完**了吗（也就是分界点已经推进、这一轮真的交出去了）。
    ///
    /// 给测试用：关心「轮次怎么切」的用例只需要知道成页完成了，
    /// 不该被「这次魂回没回」的结果绑住——那是另一件事，换个 provider 就会变。
    ///
    /// **`.understanding` 刻意算 false**：那是成页**进行中**（识别还在跑、
    /// 分界点还没推进）。把它算成 true 会让测试在分界点推进之前就往下走，
    /// 于是「只读新写的笔画」这条断言拿到的是整页——这个坑本轮真踩到过一次。
    var isCommitted: Bool {
        switch self {
        case .askingSoul, .replying, .soulSilent: true
        case .nothingNew, .writing, .waiting, .aboutToRespond, .understanding: false
        }
    }
}

/// 魂已经写在这一页上的那段回应。
///
/// 目前**没有生产者**：唯一能产出回应的是 Oracle，而 Oracle 属计划 E6 还没接。
/// 打断规则仍然写在这里而不是留到以后，因为这里就是它的定义位置——
/// 「用户落笔要打断什么」这件事属于页面状态，不属于渲染层。
/// 可运行的证明在 `DiaryPageView` 的 Xcode 预览里。
nonisolated struct ReplyOnPage: Equatable, Sendable {
    let sequence: StrokeSequence
    var playback: ReplayPlayback

    /// 此刻纸上真的有墨的地方。给占用图用（计划 E9b）。
    var drawnPolylines: [Polyline] {
        sequence.drawnPolylines(
            at: playback.elapsedSeconds(totalDuration: sequence.totalDuration)
        )
    }
}

@MainActor
@Observable
final class DiaryPageModel {
    /// 最近一次读到的手写内容（笔画几何、力度观测、书写节奏）。
    private(set) var reading: PencilStrokeReading?

    /// 最近一次识别结果。含语言可用性——「本机没有中文模型」和「认不出」必须分开。
    private(set) var recognition: HandwritingRecognition?

    /// 本机的识别语言状况，**在你落笔之前就查好**（计划 E4b）。
    ///
    /// 为什么要提前查而不是等识别完再说：缺语言模型时识别器不会返回空，
    /// 它会把你的笔画硬塞进它手上有的语言里，吐出一串看起来正常的垃圾
    /// （实测写「你好」得到 `15.47`）。而要判断「这几笔本来是中文」，
    /// 你得先有中文模型——这是个死循环，事后过滤不掉。
    /// 所以唯一诚实的做法是在你开始写之前就告诉你：这台设备读不出哪些语言。
    ///
    /// nil 表示还没查完（查询要跨进程问系统，不是瞬时的）。
    private(set) var recognitionAvailability: RecognitionAvailability?

    private(set) var phase: DiaryPagePhase = .nothingNew

    /// 魂**正在写**的那段回应。写完或被新的一段接替后会移进 `settledReplies`。
    private(set) var reply: ReplyOnPage?

    /// 整本日记。翻页与「哪一页上有什么」都在里面（计划 E3f）。
    private(set) var book = DiaryBook()

    /// 魂在**当前页**上已经定格的那些回应。
    ///
    /// ── 为什么必须留着（2026-09-01 实测出来的 bug）──
    /// 原先只有 `reply` 一个位置，`beginReply` 直接替掉上一段，症状是
    /// 写第二轮时第一轮的回应**从纸上凭空消失了**。纸上的东西不该自己消失
    /// （决策 14 的同一个道理）。
    ///
    /// 定格时保留它当时的播放状态，而不是一律按「写完」：
    /// 被用户打断的那段就该停在半截字上（决策 14）。
    ///
    /// 已知的下一步（计划 E3g）：按决策 18，写完的笔画最终要**落定进 `PKDrawing`**，
    /// 这样用户能用系统橡皮擦掉它。卡在一个真冲突上：轮次按落笔时刻切，
    /// 而魂的笔画时刻也是「现在」，直接塞进去会让魂读到自己写的话。
    var settledReplies: [ReplyOnPage] { book.current.settledReplies }

    /// 翻到新一页时递增。界面用它触发翻页动画，也用它强制重建画布
    /// （`PKCanvasView` 要换掉整份 drawing）。
    private(set) var pageTurnCount = 0

    /// 笔是否悬在纸上。硬件不支持悬停时恒为 false（模拟器与 iPad 10 都不支持），
    /// 成页判断走没有悬停的那条路径，不需要兜底。
    private(set) var isPencilHovering = false

    /// 可书写区域（已扣掉页边距），由界面在知道自己多大之后告诉模型。
    ///
    /// 为什么模型自己算不出来：页边距是界面尺寸的函数（`PageAppearance.pageMargin`），
    /// 而模型不认识视图有多大。nil 表示界面还没报过尺寸，此时无法定落点。
    private(set) var writableArea: PageRegion?

    /// 已经回应过几轮。只用来给落点决策换种子，让每轮位置不同。
    private var replyRound: UInt64 = 0

    private let reader: PencilStrokeReader
    private let recognizer: HandwritingReading
    private let trigger: PageCommitTrigger
    private let oracle: OracleProvider?
    private let composer: ReplyComposer

    /// 最后一次抬笔的时刻，单调时钟。nil 表示笔正在纸上或还没写过。
    private var lastLift: ContinuousClock.Instant?



    /// 上一轮成页时的分界时刻（计划 E3e）。晚于它落笔的才算「这一轮新写的」。
    /// nil 表示还没成过页，整页都算这一轮。
    private var committedBoundary: Date?

    /// 阶段发布次数。仅供测试断言「等待期没有高频重建界面」——
    /// 那条断言守着 2026-08-29 的「笔画写完就消失」不再复发。
    /// 界面不读它（原先的 DEBUG 读数已删除）。
    private(set) var publishedPhaseCount = 0

    private var countdown: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?

    init(
        reader: PencilStrokeReader = PencilStrokeReader(),
        recognizer: HandwritingReading = HandwritingRecognizer(),
        trigger: PageCommitTrigger = PageCommitTrigger(),
        oracle: OracleProvider? = DiaryPageModel.defaultOracle,
        composer: ReplyComposer = ReplyComposer()
    ) {
        self.reader = reader
        self.recognizer = recognizer
        self.trigger = trigger
        self.oracle = oracle
        self.composer = composer
    }

    /// 这个构建默认用哪个魂。判断全在 `OracleAssembly` 里，这里只是转发。
    ///
    /// 三种情况：配好了用真的；没配好但是 DEBUG 用假的（纸上会说明是假的）；
    /// 没配好且是 Release 就什么都不用，界面如实说魂接不上。
    nonisolated static var defaultOracle: OracleProvider? {
        OracleAssembly.makeProvider()
    }

    // MARK: 版式（回应写在哪）

    /// 这一轮写的字占了哪块地方（计划 E9a）。魂的回应要挨着它写。
    ///
    /// 用**这一轮**而不是整页：回应该挨着你刚写的那句话，
    /// 而不是挨着整页所有内容的外框——那个框在写满半页之后就没有意义了。
    /// 这一轮什么都没写时为 nil，落点决策会退回从可书写区域左上角写起。
    var lastRoundRegion: PageRegion? {
        PageRegion.covering(reading?.polylines ?? [])
    }

    /// 整页此刻的占用图（计划 E9b）：你写的每一笔 **加上** 魂已经写下的回应。
    ///
    /// 两者必须合起来算。只算用户笔画的话，第二段回应会压在第一段上；
    /// 只算回应的话，回应会压在你的字上。
    ///
    /// - Parameters:
    ///   - writableArea: **已扣掉页边距**的可书写区域。页边距属于界面尺寸，
    ///     模型不认识它，所以由调用方算好传进来。
    ///   - glyphSize: 字高。占用图的格子大小与预留间距都由它推出。
    func inkMap(writableArea: PageRegion, glyphSize: Double) -> PageInkMap {
        var map = PageInkMap(
            page: writableArea,
            resolution: PageInkMap.Resolution(
                glyphHeight: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio
            )
        )
        // 当前页的全部用户笔画，不只是这一轮——之前几轮写的字同样占地方。
        map.mark(reader.read(book.current.drawing).polylines)
        // 魂自己写过的每一段也要算。标的是 `drawnPolylines`（此刻真的有墨的部分）
        // 而不是整段几何：一段被打断的回应停在半截字上，它「本来要写到的地方」
        // 其实是空白纸，用整段几何标会让后面的回应绕开一片其实空着的地方。
        for settled in settledReplies {
            map.mark(settled.drawnPolylines)
        }
        if let reply {
            map.mark(reply.drawnPolylines)
        }
        return map
    }

    /// 当前这一页要等多久才算写完。只给开发期读数用，让阈值这件事看得见。
    var commitWaitLength: TimeInterval {
        trigger.waitLength(
            rhythm: reading?.rhythm ?? .empty,
            endsWithTerminalPunctuation: PageCommitTrigger.endsWithTerminalPunctuation(recognition?.text),
            isPencilHovering: isPencilHovering
        )
    }

    // MARK: 画布事件

    /// 落笔。
    ///
    /// 这是 E3d 的触发点，也是 E3c 的取消点，两件事都必须在**落笔那一刻**发生
    /// 而不是等这一笔写完：正在写的时候纸不该有任何自己的动作。
    func strokeBegan() {
        countdown?.cancel()
        countdown = nil
        lastLift = nil
        setPhase(.writing)

        // E3d：新落笔立刻接管，重播停在当前进度，半截字留在页上（决策 14）。
        if let current = reply {
            reply = ReplyOnPage(
                sequence: current.sequence,
                playback: ReplayInterruption.freeze(
                    current.playback,
                    totalDuration: current.sequence.totalDuration
                )
            )
        }
    }

    /// 抬笔：读这一轮写的内容，并开始等「你是不是还要写」。
    ///
    /// 注意读的是**这一轮**而不是整页（计划 E3e）。除了避免把旧内容重复交给 Oracle，
    /// 还有一个好处：书写节奏也变成这一轮的节奏，成页阈值不会被上一轮的停顿污染。
    func strokeFinished(_ drawing: PKDrawing) {
        book.current.drawing = drawing

        let round = WritingRound.drawing(of: drawing, after: committedBoundary)
        reading = reader.read(round)

        guard reading?.isEmpty == false else {
            // 这一轮没有新笔画：页面空白，或者刚写的被橡皮擦掉了。
            // 两种情况都没有东西可回应，不该起倒计时。
            setPhase(.nothingNew)
            lastLift = nil
            countdown?.cancel()
            countdown = nil
            return
        }

        lastLift = .now
        setPhase(.waiting)
        startRecognition(of: round)
        startCountdown()
    }

    /// 查一次本机的识别语言状况（计划 E4b）。
    ///
    /// 由界面在出现时调用。查询要跨进程问系统，所以是异步的；只查一次，
    /// 因为「本机装了哪些手写模型」在一次运行里不会变。
    func loadRecognitionAvailability() async {
        guard recognitionAvailability == nil else { return }
        recognitionAvailability = await recognizer.availability()
    }

    /// 悬停状态变化。只有支持悬停的硬件会调到这里。
    func hoverChanged(_ hovering: Bool) {
        isPencilHovering = hovering
    }

    /// 界面告诉模型可书写区域有多大（已扣掉页边距）。
    ///
    /// 由界面算而不是模型算：页边距是视图尺寸的函数，模型不认识视图。
    /// 没有它就定不了落点，所以它是「魂能不能写」的前提之一。
    func pageAreaChanged(_ area: PageRegion) {
        writableArea = area
    }

    /// 这个构建里的魂是不是在说写死的话（见 `OracleProvider.producesCannedReplies`）。
    /// 界面用它在 DEBUG 里把「这不是模型说的」写在纸上。
    var soulSaysCannedThings: Bool { oracle?.producesCannedReplies ?? false }

    /// 魂这一轮想写但纸上写不出来的字（缺笔顺数据）。
    ///
    /// 非空必须让人知道：页面上凭空少字而无人知晓是最难查的一类问题。
    private(set) var uncoveredCharacters: [Character] = []

    /// 开始逐笔写一段回应。
    ///
    /// 正式调用方将是 Oracle 接入后的回应流程（计划 E6）。在那之前只有 Xcode 预览
    /// 会调它——那是 E3d 打断规则唯一能真正跑起来的地方。
    /// 刻意不在这里造任何示例内容：假回应留在运行界面里会让 App 看起来会回应而实际不会。
    func beginReply(_ sequence: StrokeSequence) {
        // 上一段先定格留在页上，再开始新的。漏掉这一步的后果实测过：
        // 第二段一开始写，第一段就从纸上消失了。
        settleCurrentReply()
        reply = ReplyOnPage(sequence: sequence, playback: .playing(since: .now))
    }

    /// 把当前这段回应定格，留在页上。
    ///
    /// 保留它**此刻**的进度而不是一律按「写完」：被打断的那段就该停在半截字上
    /// （决策 14）。因为「要留下来」而自己补完，等于抹掉用户打断过的痕迹。
    private func settleCurrentReply() {
        guard let current = reply else { return }

        let elapsed = current.playback.elapsedSeconds(
            totalDuration: current.sequence.totalDuration
        )
        book.current.settledReplies.append(ReplyOnPage(
            sequence: current.sequence,
            playback: .frozen(atElapsed: elapsed)
        ))
        reply = nil
    }

    // MARK: 内部

    /// 只在阶段真的变化时才发布。
    ///
    /// `@Observable` 不比较新旧值：把同一个值再写一遍，观察者照样收到变更通知，
    /// 界面照样重建一次。倒计时每 0.1 秒判断一次，其中绝大多数次结论都没变，
    /// 所以少了这道闸门就是每秒十次无意义的界面重建——2026-08-29 的笔画消失
    /// 就是这么来的。
    private func setPhase(_ next: DiaryPagePhase) {
        guard phase != next else { return }
        phase = next
        publishedPhaseCount += 1
    }


    /// 等待期的识别。它的产出有两个用途：喂终止标点加速信号，以及让开发期读数
    /// 能立刻看到认出了什么。上一次没跑完就取消，避免识别任务越积越多。
    private func startRecognition(of drawing: PKDrawing) {
        recognitionTask?.cancel()
        recognitionTask = Task { [weak self, recognizer] in
            let result = await recognizer.recognize(drawing)
            guard !Task.isCancelled else { return }
            self?.recognition = result
        }
    }

    /// 成页倒计时。
    ///
    /// 轮询而不是「睡到点」的理由写在 `InteractionSettings.pageCommitCheckInterval`。
    /// 循环本身很薄：判断全在 `PageCommitTrigger` 里，那部分是纯函数、可单测。
    private func startCountdown() {
        countdown?.cancel()
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let lift = self.lastLift else { return }

                let decision = self.trigger.decide(
                    sinceLastLift: (ContinuousClock.now - lift).inSeconds,
                    rhythm: self.reading?.rhythm ?? .empty,
                    endsWithTerminalPunctuation: PageCommitTrigger
                        .endsWithTerminalPunctuation(self.recognition?.text),
                    isPencilHovering: self.isPencilHovering
                )

                switch decision {
                case .keepWaiting:
                    self.setPhase(.waiting)
                case .aboutToCommit:
                    self.setPhase(.aboutToRespond)
                case .commit:
                    await self.commit()
                    return
                }

                do {
                    try await Task.sleep(for: InteractionSettings.pageCommitCheckInterval)
                } catch {
                    // 只可能是被取消（用户又落笔了）。取消不是错误，安静退出。
                    return
                }
            }
        }
    }

    #if DEBUG
    /// 开发期的一行识别结果。**只在 DEBUG 编译进来。**
    ///
    /// ── 这是对「日志不记日记内容」的一次刻意破例，理由要说清 ──
    /// `AGENTS.md` 要求生产日志不出现日记内容，这条规则不变——所以它包在 `#if DEBUG` 里，
    /// release 构建里连这行代码都不存在。
    ///
    /// 为什么非要有它：**不看识别出来的文字，就无法判断识别到底对不对。**
    /// 上一轮把页脚读数删掉之后，用户在 iPadOS 27 模拟器上写了「你好」，
    /// 而我们没有任何办法知道它被认成了什么。而这恰恰是整个输入端最要紧的未知：
    /// 缺中文模型时识别器不返回空，它会吐出一串看起来正常的垃圾（实测「你好」→ `15.47`）。
    /// 没有这一行，那种失败是完全无声的。
    ///
    /// 使用约定：只在自己的模拟器/开发机上写测试内容时看它。
    /// 真实日记内容不该出现在任何日志里，包括 DEBUG。
    private func debugRecognitionLine() -> String {
        guard let recognition else { return "识别：还没有结果" }

        let availability = recognition.availability
        guard availability.systemProvidesRecognition else {
            return "识别：这台系统没有手写识别 API（需要 iPadOS \(HandwritingRecognizer.requiredSystemVersion)）"
        }

        let active = describe(availability.active)
        let missing = describe(availability.unavailable)
        guard availability.isUsable else {
            return "识别：不可用——本机没有任何请求语言的模型（缺 \(missing)）"
        }
        guard let text = recognition.text, recognition.hasText else {
            return "识别：可用[\(active)] 缺失[\(missing)]　但这一轮没认出内容"
        }
        return "识别：可用[\(active)] 缺失[\(missing)]　认出「\(text.replacingOccurrences(of: "\n", with: "⏎"))」"
    }

    private func describe(_ languages: [Locale.Language]) -> String {
        languages.isEmpty ? "—" : languages.map(\.minimalIdentifier).joined(separator: ",")
    }
    #endif

    /// 成页：这一轮收下了。
    ///
    /// 为什么要重新识别一次而不是复用等待期那次结果：等待期的识别可能还在跑，
    /// 也可能只覆盖到倒数第二笔。收下的文字必须是这一轮的最终内容。
    ///
    /// 识别范围是**这一轮**，不是整页（计划 E3e）。
    private func commit() async {
        let drawing = book.current.drawing

        let round = WritingRound.drawing(of: drawing, after: committedBoundary)
        // 这一轮空了（成页判断跑完之前被擦干净）就直接说没有新内容，
        // 不去识别一张空图、更不能把上一轮的内容当成新的交出去。
        guard !round.strokes.isEmpty else {
            setPhase(.nothingNew)
            return
        }

        setPhase(.understanding)
        recognitionTask?.cancel()
        recognition = await recognizer.recognize(round)

        // 推进分界点：此刻页面上的所有笔画都算「已经交出去过」。
        // 用整页的最晚时刻而不是这一轮的，这样即使中途有笔画顺序异常也不会重复交。
        committedBoundary = WritingRound.boundary(of: drawing) ?? committedBoundary

        #if DEBUG
        // 计划 A10：把这一轮的真人笔迹量成数字，打进控制台。
        // 只在 DEBUG：这是开发期的量尺，不是产品功能。
        // 输出格式见 `CalibrationReport.summary`，可以直接贴进对话里对照当前配置。
        print(HandwritingCalibration.analyze(PenTraceReader().read(round)).summary)
        print(debugRecognitionLine())
        #endif

        await askSoul(strokeCount: round.strokes.count)
    }

    // MARK: 问魂（计划 E6a）

    /// 把这一轮读出来的文字交给魂，拿回一段话，装配成笔画开始写。
    ///
    /// 这里是那条链路上原先唯一空着的一环。它上游的四步（画布 → 成页 → 识别 → 切轮次）
    /// 和下游的四步（定落点 → 排版 → 手绘化 → 逐笔重播）早就通了。
    ///
    /// 每一种失败都走 `.soulSilent(原因)` 并如实显示，**绝不编一段话顶上**——
    /// 编一段的后果是用户以为魂读了他写的东西，而实际上根本没读到。
    private func askSoul(strokeCount: Int) async {
        guard let oracle else {
            // 这个构建没有配 provider。Release 当前就是这种状态，如实说。
            fallSilent(.notConfigured)
            return
        }
        guard let text = recognition?.text, recognition?.hasText == true else {
            fallSilent(.nothingToSay)
            return
        }

        setPhase(.askingSoul)

        let spoken: OracleReply
        do {
            spoken = try await oracle.respond(to: OracleRequest(text: text, strokeCount: strokeCount))
        } catch let failure as OracleFailure {
            fallSilent(failure)
            return
        } catch {
            // 非 OracleFailure 的错误也不能吞掉。带上类型名供开发期定位，
            // 但不把原始错误文本给用户看——那里面可能有端点或请求细节。
            fallSilent(.couldNotReach(detail: String(describing: type(of: error))))
            return
        }

        // 用户在等回应的时候又落笔了：这一轮作废，不要抢他正在写的位置。
        // 判据是阶段已经不是「在问魂」了（`strokeBegan` 会把它改成 `.writing`）。
        guard phase == .askingSoul else {
            #if DEBUG
            // 这条分支**静默返回**，纸上不会有任何变化。不打一行的话，
            // 「为什么没回应」在日志里完全查不到——2026-09-01 就因为这个白查了一轮。
            print("── 魂（E6a）── 回应到了，但你已经重新落笔（阶段 \(phase)），这一轮作废")
            #endif
            return
        }

        await writeOnPage(spoken.text)
    }

    /// 把魂说的话装配成笔画并开始逐笔写。
    private func writeOnPage(_ text: String) async {
        guard let writableArea else {
            // 界面还没报过尺寸，定不了落点。这属于接线错误而不是运行时状况，
            // 所以如实报「送不出去」而不是硬用一个猜的页面大小——
            // 猜出来的落点会把回应画到纸外。
            fallSilent(.couldNotReach(detail: "页面尺寸未知"))
            return
        }

        // 字号：用配置里的参考字高。E9c 的估算已经能跑但实测偏 2–2.5 倍，
        // 刻意不接（见 `ReplyComposer` 文件头）。
        let glyphSize = HandwritingFeel.referenceGlyphHeightInPoints

        do {
            let composed = try composer.compose(
                text,
                glyphSize: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio,
                after: lastRoundRegion,
                on: inkMap(writableArea: writableArea, glyphSize: glyphSize),
                // 每轮换种子，落点与手抖才会变。同一轮内重算得到同一结果。
                seed: HandwritingFeel.defaultSeed &+ replyRound
            )
            replyRound &+= 1
            uncoveredCharacters = composed.uncoveredCharacters
            beginReply(composed.sequence)
            setPhase(.replying)

            #if DEBUG
            // 成功也要打一行。
            //
            // 理由是 2026-09-01 那次白查出来的：**成功和「渲染层没画出来」在纸上
            // 长得一模一样**（都是一片空白）。没有这一行就分不清「魂没说话」和
            // 「魂说了但没画出来」，而两者的修法完全不同。
            // 只在 DEBUG：它带着回应的文字，属日记内容（同 `debugRecognitionLine`
            // 那次刻意破例，release 构建里这段代码不存在）。
            print("""
            ── 魂（计划 E6a）──
            这段话：「\(text)」（\(text.count) 字，逐笔约 \(String(format: "%.1f", composed.sequence.totalDuration)) 秒）
            落在：\(describe(composed.placement.slot))　行宽 \(Int(composed.placement.lineWidth)) 点
            占地：左 \(Int(composed.placement.region.left)) 上 \(Int(composed.placement.region.top)) \
            宽 \(Int(composed.placement.region.width)) 高 \(Int(composed.placement.region.height))
            笔画：\(composed.sequence.strokes.count) 笔　→ 已交给渲染层开始写
            \(composed.uncoveredCharacters.isEmpty ? "" : "⚠️ 写不出来的字：\(String(composed.uncoveredCharacters))")
            """)
            #endif
        } catch ReplyPlacementFailure.noRoomOnThisPage {
            // 这一页放不下了 → 翻页，在新的一页上写（计划 E3f，决策 33）。
            //
            // 翻页的判据就是这里：**落点决策找不到空位**。
            // 不用「occupancy 超过百分之几」那种判据——真正要紧的不是纸上有多少墨，
            // 而是「这段话还放得下吗」，而一段 30 字和一段 3 字的回应对空间的要求差很多。
            await turnPageAndWrite(text)
        } catch {
            fallSilent(.couldNotReach(detail: String(describing: error)))
        }
    }

    /// 翻到新一页，在那一页上写这段回应（计划 E3f）。
    ///
    /// 只试一次就翻一次页。**不循环重试**：如果一段回应在一张全新的空白纸上
    /// 都放不下，那它长得离谱，翻一百页也一样——循环只会翻出一叠空白页。
    /// 那种情况如实报错。
    private func turnPageAndWrite(_ text: String) async {
        // 当前这段（如果有）先定格在旧页上，别跟着翻过去。
        settleCurrentReply()

        book.turnToNextPage()
        pageTurnCount += 1
        // 新的一页上没有「这一轮写的字」可以挨着，也没有已收下的分界点可言。
        // 分界点推进到现在：新页从零开始。
        committedBoundary = Date()
        reading = nil

        #if DEBUG
        print("── 翻页（计划 E3f）── 这一页放不下了，翻到第 \(book.currentIndex + 1) 页")
        #endif

        guard let writableArea else {
            fallSilent(.couldNotReach(detail: "页面尺寸未知"))
            return
        }
        let glyphSize = HandwritingFeel.referenceGlyphHeightInPoints

        do {
            let composed = try composer.compose(
                text,
                glyphSize: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio,
                // 新页是空的，没有可挨着的字，所以从可书写区域左上角写起。
                after: nil,
                on: inkMap(writableArea: writableArea, glyphSize: glyphSize),
                seed: HandwritingFeel.defaultSeed &+ replyRound
            )
            replyRound &+= 1
            uncoveredCharacters = composed.uncoveredCharacters
            beginReply(composed.sequence)
            setPhase(.replying)
        } catch {
            // 一张空白纸都放不下，说明这段话长得离谱。如实报，不再翻页。
            fallSilent(.couldNotReach(detail: "翻到新一页也放不下这段回应：\(error)"))
        }
    }

    /// 魂说不出话，如实记下并显示。
    ///
    /// 收成一个方法是为了保证**每一条失败路径都会被打进日志**。
    /// 分散着写 `setPhase(.soulSilent(...))` 的话，总会漏掉某一条，
    /// 而漏掉的那条恰好就是查不出来的那次。
    private func fallSilent(_ failure: OracleFailure) {
        setPhase(.soulSilent(failure))
        #if DEBUG
        print("── 魂（计划 E6a）── 说不出话：\(failure)　纸上会显示：\(failure.sentenceForReader)")
        #endif
    }

    #if DEBUG
    private func describe(_ slot: ReplyPlacement.Slot) -> String {
        switch slot {
        case .rightOfWriting: "你那句话的右边"
        case .belowWriting: "你那句话的下方"
        case .scanned: "扫描出来的空位（右边和下方都放不下）"
        case .startOfPage: "可书写区域左上角（这一轮没有可挨着的字）"
        }
    }
    #endif
}
