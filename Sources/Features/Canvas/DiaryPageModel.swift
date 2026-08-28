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
//  `phaseUpdateCount` 是为这件事加的**临时**计数器，只在 DEBUG 读数里显示：
//  如果改完墨还是消失、而计数很低，就说明上面这个推断是错的，得换方向查。
//  确认修好后删掉它。
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

    /// 读懂了，但魂还没接上。
    ///
    /// 这个名字是刻意的：当前 Oracle 完全没有接入（计划 E6），所以这一步之后
    /// **真的什么都不会发生**。叫 `.responding` 或 `.thinking` 会让代码读起来
    /// 像是在等一个不存在的东西返回，那是伪装成功。
    case awaitingSoul
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

    /// 阶段实际发布过多少次。**临时诊断用**，只给 DEBUG 读数看，确认笔画不再消失后删除。
    /// 一次「写字 → 等待 → 成页」应该只有个位数；如果又变成几十次，说明高频发布回来了。
    private(set) var phaseUpdateCount = 0

    /// 魂那段回应。E6 之前恒为 nil。
    private(set) var reply: ReplyOnPage?

    /// 笔是否悬在纸上。硬件不支持悬停时恒为 false（模拟器与 iPad 10 都不支持），
    /// 成页判断走没有悬停的那条路径，不需要兜底。
    private(set) var isPencilHovering = false

    private let reader: PencilStrokeReader
    private let recognizer: HandwritingRecognizer
    private let trigger: PageCommitTrigger

    /// 最后一次抬笔的时刻，单调时钟。nil 表示笔正在纸上或还没写过。
    private var lastLift: ContinuousClock.Instant?

    /// 最近一次抬笔时的整页内容。成页时要用它做最后一次识别。
    private var lastDrawing: PKDrawing?

    /// 上一轮成页时的分界时刻（计划 E3e）。晚于它落笔的才算「这一轮新写的」。
    /// nil 表示还没成过页，整页都算这一轮。
    private var committedBoundary: Date?

    private var countdown: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?

    init(
        reader: PencilStrokeReader = PencilStrokeReader(),
        recognizer: HandwritingRecognizer = HandwritingRecognizer(),
        trigger: PageCommitTrigger = PageCommitTrigger()
    ) {
        self.reader = reader
        self.recognizer = recognizer
        self.trigger = trigger
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
        lastDrawing = drawing

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

    /// 开始逐笔写一段回应。
    ///
    /// 正式调用方将是 Oracle 接入后的回应流程（计划 E6）。在那之前只有 Xcode 预览
    /// 会调它——那是 E3d 打断规则唯一能真正跑起来的地方。
    /// 刻意不在这里造任何示例内容：假回应留在运行界面里会让 App 看起来会回应而实际不会。
    func beginReply(_ sequence: StrokeSequence) {
        reply = ReplyOnPage(sequence: sequence, playback: .playing(since: .now))
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
        phaseUpdateCount += 1
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

    /// 成页：这一轮收下了。
    ///
    /// 为什么要重新识别一次而不是复用等待期那次结果：等待期的识别可能还在跑，
    /// 也可能只覆盖到倒数第二笔。收下的文字必须是这一轮的最终内容。
    ///
    /// 识别范围是**这一轮**，不是整页（计划 E3e）。
    private func commit() async {
        guard let drawing = lastDrawing else { return }

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

        // 下一步（计划 E6）：把认出来的文字交给 Oracle，拿回应，
        // 用 `GlyphStrokeLayout` 排成笔画，装进 `reply` 开始逐笔写。
        // 现在没有 Oracle，所以到这里就结束了——阶段名字如实说明这一点。
        setPhase(.awaitingSoul)
    }
}
