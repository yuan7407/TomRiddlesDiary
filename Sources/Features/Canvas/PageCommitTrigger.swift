//
//  PageCommitTrigger.swift
//  模块：Features/Canvas（判断「这一页写完了吗」）
//
//  文件职责：只回答一个问题——用户是不是写完了，可以让魂开始回应了。
//  纯判断，不碰界面、不碰 PencilKit、不做任何副作用，因此可以单独测。
//
//  为什么需要它（计划 E3c）：
//  这张纸上不许有按钮（决策 20），所以没有「发送」。「写完了」必须自己认出来。
//
//  ── 本文件最重要的设计：阈值不是一个固定秒数 ──
//
//  历史实现写的是「抬笔 2.8 秒就算写完」。它必然误触发，原因是**书写本身就充满停顿**。
//  2026-08-28 的实测数据：一页字里停顿占了总时长的 76%，笔间停顿的中位数是 0.51 秒，
//  而想词、换气、看一眼前一句随时会超过 2 秒。
//
//  真正能区分「还在写」和「写完了」的不是绝对时长，而是**这次停顿相对你自己平常
//  停顿有多长**。写得快的人和写得慢的人，「平常」能差好几倍，所以任何固定秒数
//  对其中一方一定是错的。因此：
//
//      等待时长 = 本页笔间停顿的中位数 × 一个倍数
//
//  倍数是这里唯一有物理含义的参数：「比你平常的停顿长几倍，就算写完了」。
//  它随用户自己的节奏自动缩放，不需要为不同人调参。
//  上下限（`shortestWait` / `longestWait`）只是护栏，不是主参数。
//
//  用中位数而不是平均值：一次走神（实测里出现过 53 秒）会把平均值拉到毫无意义，
//  中位数不受单个离群值影响。这一点由 `WritingRhythmTests` 单独验证过。
//
//  ── 四个信号的分工与优先级（决策 17）──
//
//  1. 长停顿：主信号，唯一必需的信号。上面那条公式就是它。
//  2. 终止标点：加速信号。写了句号问号，等待时长按比例缩短。它依赖识别结果，
//     识别不可用时这个信号自然消失，主信号照常工作——所以它是加速器不是兜底。
//  3. 可撤销预告：等待期的后段进入 `aboutToCommit`，界面给出「快要回应了」的提示，
//     此刻再写一笔即可取消。猜错必须零代价可救。
//  4. Pencil 悬停：笔悬在纸上说明你还在写，因此延长等待——但**只延长有界的一段**。
//     不能让悬停无限阻止成页：漏触发（写完了永远没反应）比早触发严重得多，
//     而且没有按钮可以救。硬件限制见 `InteractionSettings.pencilHoverGrace`。
//
//  ── 数值的诚实说明 ──
//  倍数、上下限、标点比例、悬停宽限全部只有一次模拟器鼠标书写的实测作参照
//  （中位 0.51 秒、最长 53 秒，两个数量级之差说明这条思路可行，但定不出准确的倍数）。
//  真机 + Apple Pencil 的停顿分布拿到之前，不得声称阈值已经校准。
//

import Foundation

/// 成页判断的可调参数。数值本身在 `InteractionSettings`，这里只定义含义。
nonisolated struct PageCommitConfiguration: Equatable, Sendable {
    /// 停顿中位数的倍数。「比你平常的停顿长几倍，就算写完了」。
    let pauseMultiplier: Double

    /// 等待时长的下限（秒）。写得极快的人的中位停顿可能只有 0.2 秒，
    /// 乘上倍数仍然太短，会在他还在想下一个字时就成页。
    let shortestWait: TimeInterval

    /// 等待时长的上限（秒）。也用作**节奏还量不出来时**的等待时长：
    /// 只写了一笔时没有笔间停顿可测，此时宁可等最久——但一定要响。
    let longestWait: TimeInterval

    /// 写了终止标点时，等待时长缩到原来的几分之几。
    let terminalPunctuationRatio: Double

    /// 笔悬在纸上时额外宽限多少秒。有界，不能无限延后。
    let hoverGrace: TimeInterval

    /// 预告期占整个等待时长的后段比例。0.45 表示等待走过 55% 后开始给提示。
    let hintFraction: Double

    init(
        pauseMultiplier: Double,
        shortestWait: TimeInterval,
        longestWait: TimeInterval,
        terminalPunctuationRatio: Double,
        hoverGrace: TimeInterval,
        hintFraction: Double
    ) {
        // 非法配置直接崩在定义处。这些值全部来自 `InteractionSettings` 的常量，
        // 崩溃只会发生在开发期改错数值的那一刻，而不是用户手里。
        // 夹到合法范围反而会让「我明明把倍数写成了 0.5」这类错误静默生效。
        precondition(pauseMultiplier > 1, "倍数必须大于 1，否则平常的停顿就会被当成写完了")
        precondition(shortestWait > 0, "等待下限必须为正数")
        precondition(longestWait >= shortestWait, "等待上限不能小于下限")
        precondition(
            terminalPunctuationRatio > 0 && terminalPunctuationRatio <= 1,
            "标点只能让等待变短，不能变长或变成零"
        )
        precondition(hoverGrace >= 0, "悬停宽限不能为负")
        precondition(hintFraction > 0 && hintFraction <= 1, "预告期必须占等待时长的一段")

        self.pauseMultiplier = pauseMultiplier
        self.shortestWait = shortestWait
        self.longestWait = longestWait
        self.terminalPunctuationRatio = terminalPunctuationRatio
        self.hoverGrace = hoverGrace
        self.hintFraction = hintFraction
    }
}

/// 某一刻的成页判断。
nonisolated enum PageCommitDecision: Equatable, Sendable {
    /// 还在等，界面上什么都不该变。
    case keepWaiting

    /// 预告期：马上就要成页了，此刻再写一笔即可取消。
    /// - remaining: 还剩多少秒。给诊断读数用。
    /// - imminence: 0…1，预告期走过了多少。给渲染用（墨越洇越开），
    ///   这样渲染层不需要知道等待时长是多少。
    case aboutToCommit(remaining: TimeInterval, imminence: Double)

    /// 成页：这一页写完了。
    case commit
}

/// 成页触发器。
nonisolated struct PageCommitTrigger: Sendable {
    let configuration: PageCommitConfiguration

    init(configuration: PageCommitConfiguration = InteractionSettings.pageCommit) {
        self.configuration = configuration
    }

    /// 这一页现在应该等多久才算写完。
    ///
    /// - Parameters:
    ///   - rhythm: 本页到目前为止的书写节奏。中位停顿是唯一的主依据。
    ///   - endsWithTerminalPunctuation: 目前认出来的文字是不是以句号问号之类收尾。
    ///     识别不可用时传 false，主信号不受影响。
    ///   - isPencilHovering: 笔是不是悬在纸上。硬件不支持悬停时恒为 false。
    /// - Returns: 从最后一次抬笔起算，要等这么多秒。
    func waitLength(
        rhythm: WritingRhythm,
        endsWithTerminalPunctuation: Bool,
        isPencilHovering: Bool
    ) -> TimeInterval {
        var wait: TimeInterval

        if let median = rhythm.medianPause, median > 0, median.isFinite {
            wait = median * configuration.pauseMultiplier
        } else {
            // 还没有第二笔，量不出「你平常停多久」。
            // 此时取上限：宁可让你多等，也不能不响——没有按钮可以救漏触发。
            wait = configuration.longestWait
        }

        // 标点先作用于原始值，再夹到上下限。这样「写了句号」最多能把等待压到下限，
        // 不会因为夹取顺序反过来失效。
        if endsWithTerminalPunctuation {
            wait *= configuration.terminalPunctuationRatio
        }
        wait = min(max(wait, configuration.shortestWait), configuration.longestWait)

        // 悬停宽限加在夹取之后：它是刻意超出常规范围的一段延长，
        // 而且因为是加法且宽限有界，绝不可能把成页无限推后。
        if isPencilHovering {
            wait += configuration.hoverGrace
        }

        return wait
    }

    /// 判断此刻该不该成页。
    /// - Parameter sinceLastLift: 距离最后一次抬笔过了多少秒。
    func decide(
        sinceLastLift: TimeInterval,
        rhythm: WritingRhythm,
        endsWithTerminalPunctuation: Bool,
        isPencilHovering: Bool
    ) -> PageCommitDecision {
        let wait = waitLength(
            rhythm: rhythm,
            endsWithTerminalPunctuation: endsWithTerminalPunctuation,
            isPencilHovering: isPencilHovering
        )

        // 非有限的经过时间只可能来自时钟异常。当成「刚抬笔」处理，
        // 而不是当成「等了无限久」立刻成页——后者会凭空触发一次回应。
        guard sinceLastLift.isFinite else { return .keepWaiting }

        guard sinceLastLift < wait else { return .commit }

        let remaining = wait - sinceLastLift
        let hintWindow = wait * configuration.hintFraction
        guard remaining <= hintWindow else { return .keepWaiting }

        return .aboutToCommit(
            remaining: remaining,
            imminence: min(1, max(0, 1 - remaining / hintWindow))
        )
    }

    /// 认出来的文字是不是以终止标点收尾。
    ///
    /// 先剥掉尾部的空白与收尾的引号括号：「写完了。」的句号在引号里面，
    /// 只看最后一个字符会看到引号而漏掉句号。
    ///
    /// 这个信号只用来**加速**，认错了最坏的后果是早响或没提速，
    /// 因此不需要完整的句法分析。识别本身认不出标点时（模拟器实测把感叹号
    /// 认成了 I）它就是失效状态，主信号照常工作。
    static func endsWithTerminalPunctuation(_ text: String?) -> Bool {
        guard let text else { return false }

        var tail = Substring(text)
        while let last = tail.last,
              last.isWhitespace || InteractionSettings.closingMarks.contains(last) {
            tail = tail.dropLast()
        }

        guard let last = tail.last else { return false }
        return InteractionSettings.sentenceEndingMarks.contains(last)
    }
}
