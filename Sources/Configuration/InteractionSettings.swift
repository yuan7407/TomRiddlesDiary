//
//  InteractionSettings.swift
//  模块：Configuration（集中配置，被上层读取，不被 StrokeEngine 依赖）
//
//  文件职责：书写交互的行为设定。
//
//  设计原因：
//  这些不是手感数值，而是「怎么算一次输入」的行为决定，所以和 `HandwritingFeel`
//  分开：改「允许不允许用手指写」不该动到抖动幅度所在的文件。
//

import Foundation
import PencilKit

nonisolated enum InteractionSettings {
    /// 画布接受哪种输入。
    ///
    /// 取 `.anyInput`（手指与 Apple Pencil 都能写），有两个原因：
    /// 一、模拟器上没有 Apple Pencil，鼠标等同手指，取 `.pencilOnly` 会导致
    /// 怎么划都没反应，连开发都做不了；
    /// 二、没有笔的用户如果完全写不了字，等于 App 对他不可用。
    ///
    /// **这是一个待用户确认的产品决定，不是技术默认值。** 真实取舍是：
    /// 用笔写才符合「手写日记」的定位，而允许手指会带来误触（手掌搁在屏幕上就
    /// 画出一道）。若最终决定只认 Apple Pencil，按 AGENTS.md 必须明确告知
    /// 「这一页需要用 Apple Pencil 书写」，不能让用户对着毫无反应的纸猜。
    static let drawingPolicy: PKCanvasViewDrawingPolicy = .anyInput

    /// 请求识别的语言，按优先顺序。
    ///
    /// 中文在前是产品方向（首版中文优先），英文在后是为了中英混写。
    /// 系统只会启用**本机装了模型**的语言，装不了的那些必须如实告知，不得当作
    /// 识别失败或悄悄换成别的语言——见 `HandwritingRecognizer` 的说明。
    ///
    /// 已实测：iOS 27.0 beta 6 的模拟器只装了拉丁字母模型，请求中文会得到空列表；
    /// 中文模型是按需下载的系统资产，模拟器不带且不会触发下载。中文可用性只能真机验。
    static let recognitionLanguages: [Locale.Language] = [
        Locale.Language(identifier: "zh-Hans"),
        Locale.Language(identifier: "en"),
    ]

    // MARK: 成页触发（计划 E3c）

    /// 「这一页写完了吗」的判断参数。含义与推理写在 `PageCommitTrigger` 的文件头，
    /// 这里只放数值和取值理由。
    ///
    /// **全部数值只有一次模拟器鼠标书写的实测作参照**（笔间停顿中位 0.51 秒、
    /// 最长 53.37 秒），真机 + Apple Pencil 的分布拿到之前不得称已校准。
    static let pageCommit = PageCommitConfiguration(
        // 6 倍：实测中位停顿 0.51 秒 → 等待约 3.1 秒。
        // 这个量级正好落在「写字过程中的停顿」（不到 1 秒）和「写完了放下笔」
        // （好几秒）之间。倍数取太小会在想词时误触发，取太大会让人觉得纸是死的。
        pauseMultiplier: 6,
        // 1.5 秒：写得极快的人中位停顿可能只有 0.2 秒，6 倍才 1.2 秒，
        // 那比很多人写单个汉字中间的停顿还短。这条下限保证不会快到荒谬。
        shortestWait: 1.5,
        // 8 秒：也是「只写了一笔、还量不出节奏」时的等待时长。
        // 再长会让人以为纸坏了；再短则对写字慢的人误触发。
        longestWait: 8,
        // 0.45：写了句号问号说明这句话结束了，等待时长缩到不到一半。
        // 不缩到更小是因为句号之后完全可能继续写下一句。
        terminalPunctuationRatio: 0.45,
        // 2.5 秒：笔悬在纸上时的额外宽限。刻意有界——悬停不能无限阻止成页。
        hoverGrace: 2.5,
        // 0.45：等待走过 55% 后开始给「快要回应了」的提示。
        // 提示期太短来不及反应，太长会让提示一直亮着失去意义。
        hintFraction: 0.45
    )

    /// 成页判断的检查间隔。
    ///
    /// 为什么是轮询而不是「睡到点再判断」：判断依赖三个会在等待期内变化的输入——
    /// 经过时间、笔是否悬停、识别结果什么时候返回。睡固定时长等于假设这些事件
    /// 按某个固定顺序发生，而现实不保证。轮询让判断函数保持纯粹且可测。
    ///
    /// 0.1 秒：人察觉不到的延迟，同时一次等待最多也就检查几十次，开销可以忽略。
    /// 顺带的好处：这条循环用 `Task.sleep` 驱动，不受模拟器空闲时冻结渲染循环的影响
    /// （`TimelineView` 会停帧，见 `MEMORY.md` 已知陷阱）。
    ///
    /// **它和 `pageCommit` 不是互相独立的**（2026-08-29 被测试抓到）：
    /// 最短的预告期是 `shortestWait × hintFraction`。如果它小于这个检查间隔，
    /// 一次轮询就会跨过整个预告期，用户根本看不到「可撤销」的提示，
    /// 而界面上只会表现为「有时有提示有时没有」——很难查。
    /// 这条约束由 `PageCommitTriggerTests.testHintWindowOutlastsTheCheckInterval` 守着，
    /// 改这两组数值时不要绕过它。
    static let pageCommitCheckInterval: Duration = .milliseconds(100)

    // MARK: 问魂的请求参数（计划 E6d）

    /// 一次 Oracle 请求的参数。
    static let oracleRequest = OracleRequestSettings(
        // 0.85：这是个要有个性的角色，不是查资料。温度太低会变成一板一眼的客服口吻，
        // 太高会开始跑题、也更容易忘掉「短」这条铁律。
        // 这个值**没有测量依据**，是从「要有人味但要守规矩」这个目标推的起点，
        // 接上真模型跑过 C1 那 11 段之后应该重新评估。
        temperature: 0.85,
        // 回应上限 25–40 个汉字（见 C1 的长度硬约束）。中文一个字大致 1–2 个 token，
        // 留出三倍余量到 200：够它写完，又不至于在它跑题时白烧一大段。
        // 截断在这里是**兜底不是手段**——真正约束长度的是 system prompt，
        // 因为被 token 上限砍断的是半句话，比长更糟。
        maxTokens: 200,
        // 20 秒。用户已经等了成页判断的两三秒，再等太久会以为坏了；
        // 而这条链路后面还要花十几秒逐笔写出来，所以请求本身不该是主要的等待。
        timeout: 20
    )

    // MARK: 回应落点（计划 E9e）

    /// 魂这段回应写在哪——**只有这两个数需要人来定**。
    /// 间距与扫描步长都从占用图推出，不在这里出现（理由见 `ReplyPlacement` 文件头）。
    static let replyPlacement = ReplyPlacementConfiguration(
        // 6 个字：再窄的一行中文读起来像竖排的窄条。与其挤在那里，不如换个位置。
        minimumLineWidthInGlyphs: 6,
        // 0.25 个字高：让回应不要每次都精确贴在同一个相对位置上（那样一页看起来像表格），
        // 但幅度刻意小——它是「不那么机械」，不是「随便放」。
        jitterInGlyphs: 0.25
    )

    /// 算作句子结束的标点。中英文都要认，因为输出输入都支持中英混写。
    static let sentenceEndingMarks: Set<Character> = ["。", "．", ".", "！", "!", "？", "?", "…", "⋯"]

    /// 句末标点之后可能还跟着的收尾符号。判断终止标点时要先剥掉这些，
    /// 否则「写完了。」里最后一个字符是引号，句号会被漏掉。
    static let closingMarks: Set<Character> = [
        "」", "』", "”", "’", "\"", "'", "）", ")", "》", "〉", "】", "]", "}",
    ]

}
