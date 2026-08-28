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
    /// 还什么都没写。
    case blank

    /// 笔正在纸上。此时不做任何成页判断——你显然还在写。
    case writing

    /// 抬笔了，在等你是不是还要接着写。
    case waiting

    /// 预告期：马上要成页了。此刻再写一笔即可取消（决策 17 要求猜错零代价可救）。
    case aboutToRespond(remaining: TimeInterval, imminence: Double)

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

    private(set) var phase: DiaryPagePhase = .blank

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
        phase = .writing

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

    /// 抬笔：读这一页，并开始等「你是不是还要写」。
    func strokeFinished(_ drawing: PKDrawing) {
        lastDrawing = drawing
        reading = reader.read(drawing)

        guard reading?.isEmpty == false else {
            // 一笔都没有（例如用橡皮擦干净了）。没有内容就没有什么可回应的。
            phase = .blank
            lastLift = nil
            countdown?.cancel()
            countdown = nil
            return
        }

        lastLift = .now
        phase = .waiting
        startRecognition(of: drawing)
        startCountdown()
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
                    self.phase = .waiting
                case .aboutToCommit(let remaining, let imminence):
                    self.phase = .aboutToRespond(remaining: remaining, imminence: imminence)
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

    /// 成页：这一页收下了。
    ///
    /// 先做一次完整识别再收下，而不是复用等待期那次结果：等待期的识别可能还在跑，
    /// 或者只覆盖到倒数第二笔。收下的文字必须是整页的最终内容。
    private func commit() async {
        guard let drawing = lastDrawing else { return }

        phase = .understanding
        recognitionTask?.cancel()
        recognition = await recognizer.recognize(drawing)

        // 下一步（计划 E6）：把认出来的文字交给 Oracle，拿回应，
        // 用 `GlyphStrokeLayout` 排成笔画，装进 `reply` 开始逐笔写。
        // 现在没有 Oracle，所以到这里就结束了——阶段名字如实说明这一点。
        phase = .awaitingSoul
    }
}
