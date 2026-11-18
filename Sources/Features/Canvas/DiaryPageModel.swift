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
/// 被纸喝下去的那一轮（计划 P4，原型 drawDrink）：你成页那一刻写下的笔画，
/// 从 PencilKit 里拿出来，由 `DrinkingInkView` 一笔接一笔地画成「变细、变褐、朝书脊偏、淡下去」，
/// 喝完留一层很淡的压痕。字不会被删掉，只会沉进纸里（原型凡例第三条）。
nonisolated struct DrinkingInk: Equatable, Sendable {
    /// 这一轮的笔画（页面坐标），按书写顺序。
    let polylines: [Polyline]
    /// 朝书脊的方向：+1 往右（你写在左页）、−1 往左（你写在右页）、0 没有书脊（外屏）。
    let towardSpine: Double
    /// 从什么时候开始喝。
    let since: ContinuousClock.Instant
}

/// 沉下去的那一段回应（计划 P4，原型 drawSinking）：下一轮成页时，他上一段话变淡、变糊、
/// 朝书脊偏，然后离开这张对开、进旧页。
nonisolated struct SinkingReply: Equatable, Sendable, Identifiable {
    let id: Int
    let reply: ReplyOnPage
    let towardSpine: Double
}

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

    /// 笔是否悬在纸上。硬件不支持悬停时恒为 false（模拟器与目前的 iPhone 都不支持），
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
    ///   - includingFold: 要不要把折缝标成墙。隔着书脊写的路径传 false：那一栏本来就让开了折缝，
    ///     墙只对会跨缝的旧排法有意义；再算一遍只会让占用检查的留白在靠书脊那一侧多挡一截。
    func inkMap(writableArea: PageRegion, glyphSize: Double, includingFold: Bool = true) -> PageInkMap {
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
        // 折缝当成一道已经有墨的墙（计划 P1，用对开包的 `foldBarrier`）：
        // 落点决策因此不会把一段话横跨在书脊上，落点规则本身一行不用改。
        // 2026-11-17 实测之前，回应会从左页一直写到右页。
        if includingFold, let fold {
            map.mark(SpreadGeometry(bounds: writableArea, fold: fold).foldBarrier(spacing: map.resolution.cellSize))
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
        // 开场那句「在这一页上手写」只在你落笔之前有用（原型 wroteOnce）。
        if openingHintPoint != nil { openingHintPoint = nil }

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

    /// 折缝在哪（页面坐标）。nil 表示这块屏幕没有折缝（外屏，或还不知道姿态）。
    /// 由界面从 `SpreadGeometry.resolve` 算好传进来：模型不认识合页传感器。
    private(set) var fold: PageRegion?

    func foldChanged(_ fold: PageRegion?) {
        guard fold != self.fold else { return }   // `@Observable` 不比较新旧值，见 MEMORY 已知陷阱
        self.fold = fold
    }

    /// 对开时两页各自能写字的那一栏（计划 P3）。nil = 没有竖缝（外屏），走原来的找空位。
    /// 由界面算（它知道安全区），模型只拿来交给装配点。
    private(set) var facingColumns: FacingColumns?

    func facingColumnsChanged(_ columns: FacingColumns?) {
        guard columns != facingColumns else { return }
        facingColumns = columns
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
            return "识别：这台系统没有手写识别 API（需要 iOS \(HandwritingRecognizer.requiredSystemVersion)）"
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
        // 他上一段沉下去、你这一轮被纸喝下去（计划 P4）。开场白也一样沉下去（原型 greetingGhost）。
        beginNewRound(round: round, previousBoundary: committedBoundary)

        // 这一轮画成图（R3 发给模型看；R2 交给 Vision 读）。先画再识别：画图在主线程、很快。
        let snapshot = HandwritingSnapshot.render(round)
        let started = ContinuousClock.now
        recognition = await recognizer.recognizeCarefully(round)
        let systemSeconds = (ContinuousClock.now - started).inSeconds
        // 系统识别没读出来，再让 Vision 读同一张图（R2）。两者都只作给模型的参考。
        var visionText: String?
        if recognition?.hasText != true, let snapshot {
            visionText = await HandwritingSnapshot.readWithVision(snapshot.cgImage)
        }

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

        // 他看的不只是字，还有你下笔的样子：写得急不急、中间停了多久、是不是只点了一下。
        // 这些只来自笔画的几何与时间，不含任何文字；量不出来（比如没有时间戳）时是 nil，请求里就不带这一行。
        let manner = WritingManner.observe(
            PenTraceReader().read(round),
            glyphHeight: HandwritingFeel.referenceGlyphHeightInPoints,
            thresholds: BookFeel.writingManner
        )
        let deviceText = recognition?.hasText == true ? recognition?.text : visionText
        #if DEBUG
        diagnosis = RoundDiagnosis(
            strokes: round.strokes.count,
            systemText: recognition?.text,
            systemSeconds: systemSeconds,
            visionText: visionText,
            imageBytes: snapshot?.png.count,
            activeLanguages: recognition?.availability.active.map(\.minimalIdentifier) ?? [],
            heard: nil
        )
        Self.saveDiagnosticImage(snapshot?.png, round: roundsCommitted)
        print("── 识别（R0）── \(diagnosis?.line ?? "")")
        #endif
        await askSoul(strokeCount: round.strokes.count, manner: manner, deviceText: deviceText, handwriting: snapshot?.png)
    }

    // MARK: 识别诊断（R0，只在 DEBUG）

    #if DEBUG
    /// 这一轮识别的经过。只在 DEBUG 构建里存在：它带着识别出的文字，属日记内容
    /// （同决策 56 的刻意破例：不看识别出来的字就无法判断识别对不对）。纸角会印出 `line`。
    struct RoundDiagnosis: Equatable {
        let strokes: Int
        let systemText: String?
        let systemSeconds: Double
        let visionText: String?
        let imageBytes: Int?
        let activeLanguages: [String]
        var heard: String?

        var line: String {
            let system = systemText.map { "「\($0)」" } ?? "无"
            let vision = visionText.map { "「\($0)」" } ?? "无"
            let image = imageBytes.map { "\($0 / 1024)KB" } ?? "无"
            let heardText = heard.map { "「\($0)」" } ?? "—"
            return "DEBUG \(strokes)笔｜系统识别\(system) \(String(format: "%.1f", systemSeconds))s｜Vision\(vision)｜图\(image)｜语言\(activeLanguages.joined(separator: ","))｜他读到\(heardText)"
        }
    }

    private(set) var diagnosis: RoundDiagnosis?

    /// 把这一轮的图存进 App 自己的文档目录（diagnostics/），只在 DEBUG。
    /// 用来在 Xcode 里下载容器、看看到底交出去的是什么样的笔迹。不上传、不进任何日志。
    private static func saveDiagnosticImage(_ png: Data?, round: Int) {
        guard let png,
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("diagnostics", isDirectory: true)
        else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? png.write(to: folder.appendingPathComponent("round-\(round).png"))
    }
    #endif

    // MARK: 问魂（计划 E6a）

    /// 把这一轮读出来的文字交给魂，拿回一段话，装配成笔画开始写。
    ///
    /// 这里是那条链路上原先唯一空着的一环。它上游的四步（画布 → 成页 → 识别 → 切轮次）
    /// 和下游的四步（定落点 → 排版 → 手绘化 → 逐笔重播）早就通了。
    ///
    /// 每一种失败都走 `.soulSilent(原因)` 并如实显示，**绝不编一段话顶上**——
    /// 编一段的后果是用户以为魂读了他写的东西，而实际上根本没读到。
    /// - Parameters:
    ///   - deviceText: 手机自己认出的字（系统识别，读不出时是 Vision 的）。可能为 nil 或认错。
    ///   - handwriting: 这一轮笔迹的图（R3）。有图时手机没认出字也照样问：图才是他写的东西。
    private func askSoul(strokeCount: Int, manner: WritingManner?, deviceText: String?, handwriting: Data?) async {
        guard let oracle else {
            // 这个构建没有配 provider。Release 当前就是这种状态，如实说。
            fallSilent(.notConfigured)
            return
        }
        let text = deviceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty || handwriting != nil else {
            fallSilent(.nothingToSay)
            return
        }

        setPhase(.askingSoul)

        let spoken: OracleReply
        do {
            spoken = try await oracle.respond(to: OracleRequest(
                text: text, strokeCount: strokeCount, manner: manner, handwriting: handwriting,
                history: recentTurns, opening: recentTurns.isEmpty ? openingSaid : nil
            ))
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

        // 他读到了什么、这句话的分量、要不要关照（R3 四行回答）。读到的那句印在他那页的页脚（P9）。
        heard = spoken.heard
        needsCare = spoken.needsCare
        // 记下这一轮，下一轮他才接得上话（原型：只有读到了字的轮次才记）。
        if let you = spoken.heard {
            recentTurns.append(OracleTurn(you: you, him: spoken.text))
            if recentTurns.count > InteractionSettings.oracleHistoryTurns {
                recentTurns.removeFirst(recentTurns.count - InteractionSettings.oracleHistoryTurns)
            }
        }
        #if DEBUG
        diagnosis?.heard = spoken.heard
        print("── 魂 ── 读到「\(spoken.heard ?? "—")」 语气 \(spoken.mood ?? "—") 关照 \(spoken.needsCare ? "是" : "否")")
        #endif
        await writeOnPage(spoken.text)
    }

    /// 最近几轮（你写的 + 他回的），问他时一起带上（计划 P9，见 `OracleRequest.history`）。只在内存里。
    private(set) var recentTurns: [OracleTurn] = []
    /// 开场时他写在纸上的话。第一轮问他时带上，让他知道自己已经开过口。
    private var openingSaid: String?

    /// 他认出你这一轮写的是什么（四行回答的「读到」）。新的一轮成页时清掉。
    private(set) var heard: String?
    /// 他觉得你需要真人的帮助（「关照：是」）。界面在纸外弹出求助条；你点「知道了」就收起。
    private(set) var needsCare = false

    func dismissCare() { needsCare = false }

    // MARK: 一轮的一生（计划 P4）

    /// 正在被喝下去、或已经喝完只剩压痕的那一轮。下一轮成页时被新的一轮换掉（旧压痕进旧页）。
    private(set) var drinking: DrinkingInk?
    /// 正在沉下去的回应。沉完（`BookFeel.Drink.duration`）就从这张对开上移走。
    private(set) var sinking: [SinkingReply] = []
    private var sinkingSerial = 0
    /// 成过几轮页。页码按它走：一个对开只放一轮（原型 drawFurniture(archive.length + 1)）。
    private(set) var roundsCommitted = 0
    /// 画布上的笔迹是第几版由模型给的（翻页、喝字都会从外面换掉整份笔迹）。见 `HandwritingCanvas.drawingRevision`。
    private(set) var drawingRevision = 0

    /// 这张对开是第几张：左页页码 2n、右页 2n + 1。
    var leafNumber: Int { max(1, roundsCommitted) + book.currentIndex }

    /// 成页那一刻：他上一段话沉下去，你这一轮被纸喝下去（原型 commit）。
    ///
    /// 为什么要把你的笔画从 `PKDrawing` 里拿走：PencilKit 只会原样显示笔迹，画不出「一笔一笔
    /// 变细变褐、朝书脊偏」；而且笔迹留在画布上，他对面那一栏就一直被你的字占着
    /// （2026-11-17 实测「放不下」的根源之一）。拿走以后由 `DrinkingInkView` 接着画，压痕留在纸上。
    private func beginNewRound(round: PKDrawing, previousBoundary: Date?) {
        let spineX = facingColumns?.spineX
        func direction(of polylines: [Polyline]) -> Double {
            guard let spineX, let box = PageRegion.covering(polylines) else { return 0 }
            return box.left + box.width / 2 < spineX ? 1 : -1
        }

        // ① 他上一段（含开场白、被打断停在半截的）沉下去。
        let leaving = settledReplies + (reply.map { [$0] } ?? [])
        if !leaving.isEmpty {
            var ids: [Int] = []
            for item in leaving {
                let frozen = ReplyOnPage(
                    sequence: item.sequence,
                    playback: ReplayInterruption.freeze(item.playback, totalDuration: item.sequence.totalDuration)
                )
                sinkingSerial += 1
                ids.append(sinkingSerial)
                sinking.append(SinkingReply(id: sinkingSerial, reply: frozen, towardSpine: direction(of: item.sequence.polylines)))
            }
            reply = nil
            book.current.settledReplies.removeAll()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(BookFeel.Drink.duration))
                self?.sinking.removeAll { ids.contains($0.id) }
            }
        }
        greetingOnPage = false
        heard = nil

        // ② 你这一轮被纸喝下去：从画布里拿出来，交给喝字的那一层。
        let polylines = reader.read(round).polylines
        drinking = DrinkingInk(polylines: polylines, towardSpine: direction(of: polylines), since: .now)
        let remaining = book.current.drawing.strokes.filter { stroke in
            guard let previousBoundary else { return false }
            return stroke.path.creationDate <= previousBoundary
        }
        book.current.drawing = PKDrawing(strokes: remaining)
        drawingRevision += 1
        roundsCommitted += 1
    }

    // MARK: 开场（计划 P6，原型 startIntro）

    /// 这次启动是否已经开过场。一次启动只开一次。
    private(set) var openingShown = false
    /// 纸上那段是开场白。第一次成页时它让开（见 `commit`）。
    private(set) var greetingOnPage = false
    /// 开场那道线下面那句提示的位置（中点、页面坐标）。你落笔后清掉；nil 表示不显示。
    private(set) var openingHintPoint: Point2D?

    /// 翻开本子：他先开口，再替你在右页划一道线。不问模型，所以不用等网络。
    ///
    /// 「你」默认在右页（原型 present.yourSide = 'R'），所以他写在左页，和右页纸高 0.25 处齐平。
    /// 只在对开（有两页的栏位）、纸上还什么都没有的时候开场：开到一半你已经在写，就不再插一段进来。
    /// - Parameters:
    ///   - lines: 他说的两行（`SoulPersona.Opening.lines`），中间换行。
    ///   - spreadHeight: 整张对开的高（页面点），用来定「纸高 0.25」和「纸高一半」。
    func openBook(lines: String, spreadHeight: Double) async {
        guard !openingShown, let facingColumns, let writableArea,
              reply == nil, settledReplies.isEmpty, phase == .nothingNew else { return }
        openingShown = true

        let unit = PaperLook.pointsPerPrototypeUnit
        let o = SoulHand.Opening.self
        let anchor = PageRegion(left: facingColumns.trailing.left, top: spreadHeight * o.anchorTopOfHeight, width: 1, height: 1)
        let foldRight = fold?.right ?? (facingColumns.spineX + PaperLook.foldWidthPoints / 2)
        let lineStart = foldRight + o.lineInsetFromFold * unit
        let lineY = spreadHeight * o.lineHeightOfHeight
        let steps = Double(max(1, o.lineWobble.count - 1))
        let line = Polyline(points: o.lineWobble.enumerated().map { index, wobble in
            let u = Double(index) / steps
            return Point2D(x: lineStart + u * o.lineLength * unit, y: lineY - u * o.lineRise * unit + wobble * unit)
        })

        let composed: ComposedReply
        do {
            composed = try composer.composeAcrossSpine(
                lines, facing: anchor, columns: facingColumns,
                on: inkMap(writableArea: writableArea, glyphSize: HandwritingFeel.referenceGlyphHeightInPoints, includingFold: false),
                seed: HandwritingFeel.defaultSeed, then: [line]
            )
        } catch {
            #if DEBUG
            print("── 开场 ── 排不出来：\(error)")
            #endif
            return
        }

        // 先让纸静一下再开口（原型 1.1 秒）。等的时候你已经落笔了，就不开场。
        try? await Task.sleep(for: .seconds(o.delay))
        guard reply == nil, settledReplies.isEmpty, phase == .nothingNew else { return }
        beginReply(composed.sequence)
        greetingOnPage = true
        openingSaid = lines
        openingHintPoint = Point2D(x: lineStart + o.lineLength * unit / 2, y: lineY + o.hintBelowLine * unit)
        #if DEBUG
        print("── 开场 ── 他先开口（\(composed.sequence.strokes.count) 笔，\(String(format: "%.1f", composed.sequence.totalDuration)) 秒）")
        #endif
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
            // 每轮换种子，落点与手抖才会变。同一轮内重算得到同一结果。
            let composed = try composeReply(
                text, facing: lastRoundRegion, writableArea: writableArea, glyphSize: glyphSize,
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

        // 你这一轮的字在哪一页：翻页之后它留在旧页上，但他仍然按它选对面那一栏（计划 P3）。
        let writing = lastRoundRegion
        book.turnToNextPage()
        pageTurnCount += 1
        drawingRevision += 1
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
            let composed = try composeReply(
                text, facing: writing, writableArea: writableArea, glyphSize: glyphSize,
                seed: HandwritingFeel.defaultSeed &+ replyRound,
                // 新页是空的，旧排法没有可挨着的字，从可书写区域左上角写起。
                fallbackAfter: .some(nil)
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

    /// 装配一段回应：对开时先隔着书脊写在你对面（计划 P3，原型）；没有对开（外屏）、
    /// 或者那一栏已经有字（P4 之前上一轮的回应还留在页上），退回原来的找空位，不压在别的字上。
    /// - Parameter fallbackAfter: 退回旧排法时挨着哪块字。默认就是 `writing`。
    private func composeReply(
        _ text: String, facing writing: PageRegion?, writableArea: PageRegion, glyphSize: Double,
        seed: UInt64, fallbackAfter: PageRegion?? = .none
    ) throws -> ComposedReply {
        if let facingColumns, let writing {
            do {
                return try composer.composeAcrossSpine(
                    text, facing: writing, columns: facingColumns,
                    on: inkMap(writableArea: writableArea, glyphSize: glyphSize, includingFold: false), seed: seed
                )
            } catch {
                #if DEBUG
                print("── 魂 ── 隔着书脊放不下（\(error)），退回找空位")
                #endif
            }
        } else if facingColumns == nil {
            // 只有一页（合上用外屏）：同一套按长短挑字号的排法，写在你那句下面或页顶（2026-11-17）。
            do {
                return try composer.composeOnSinglePage(
                    text, below: writing, page: writableArea,
                    on: inkMap(writableArea: writableArea, glyphSize: glyphSize), seed: seed
                )
            } catch {
                #if DEBUG
                print("── 魂 ── 外屏这一页放不下（\(error)），退回找空位")
                #endif
            }
        }
        return try composer.compose(
            text,
            glyphSize: glyphSize,
            lineSpacingRatio: PageAppearance.lineSpacingRatio,
            after: fallbackAfter ?? writing,
            on: inkMap(writableArea: writableArea, glyphSize: glyphSize),
            seed: seed
        )
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
        case .acrossSpine: "隔着书脊，你对面那页（和你那句齐平）"
        case .singlePage: "只有一页（外屏）：你那句下面或页顶"
        }
    }
    #endif
}
