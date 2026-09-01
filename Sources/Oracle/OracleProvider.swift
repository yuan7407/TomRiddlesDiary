//
//  OracleProvider.swift
//  模块：Oracle（「说什么」这一侧。不负责手感，不碰 UI，不认识笔画）
//
//  文件职责：定义「把这一页写的话交出去、拿回一段回应」这件事的接口（计划 E6a）。
//
//  ── 这个文件为什么存在 ──
//  在它之前，整条链路断在同一个地方：用户写字 → 成页 → 识别出文字 → **然后什么都没有**。
//  排版、落点、手绘化、逐笔重播全都建好了，但没有任何东西能产出「要写什么」。
//  这个协议就是那个缺口的形状。
//
//  ── 铁律：这一层只决定「说什么」，绝不决定「怎么写」 ──
//  返回的是纯文字。字号、落点、笔顺、压感、节奏全部由本地引擎决定（`AGENTS.md` 核心分工）。
//  所以这个协议里没有任何跟外观有关的东西——一旦让模型能影响笔画，
//  手感就变成不可控的了，而那正是这个产品的卖点所在。
//
//  ── 为什么请求里只有文字，没有笔画 ──
//  两个理由，都不是偶然：
//  一、模型本来就只看得到文字。PencilKit 把手写变成一个字符串，模型永远不知道你的字
//     好不好看。把笔画也发过去除了增加数据量没有任何作用。
//  二、`AGENTS.md` 要求「只发送完成任务所需的最少数据，默认不上传原始 PencilKit 全量历史」。
//     协议层面就不给传笔画的口子，比靠实现方自觉更可靠。
//
//  ── 失败必须是显式的错误 ──
//  没有任何一种失败可以返回一段编出来的文字冒充成功（`AGENTS.md`：降级路径必须明确、
//  不得伪装成功）。所以这里抛错，由界面用世界观内的说法如实告诉用户。
//

import Foundation

/// 交给魂的东西。**只有文字**，理由见文件头。
nonisolated struct OracleRequest: Equatable, Sendable {
    /// 这一轮识别出来的文字。
    ///
    /// 注意它可能是**错的**——缺语言模型时识别器会吐出看起来正常的垃圾
    /// （实测中文页面得到 `#31`）。这一层不做纠正，也做不了：
    /// 要判断「这几笔本来是中文」得先有中文模型。用户在落笔前已经被告知过了（E4b）。
    let text: String

    /// 这一轮写了几笔。
    ///
    /// 目前**不发给任何模型**，只用于本地判断（例如将来区分「写了一整页」和「划了两下」）。
    /// 放在请求里是因为它属于「这一轮的事实」，而不是因为现在就要用它。
    let strokeCount: Int
}

/// 魂说的话。
nonisolated struct OracleReply: Equatable, Sendable {
    /// 要写在纸上的文字。
    ///
    /// 长度是有代价的：回应是**一笔一笔写出来**的，按当前配置约 1.5 字/秒，
    /// 30 字就要写 20 秒。所以 system prompt 必须约束长度——
    /// 这不是文风偏好，是功能要求（详见仓库根的 `C1-response-quality-set.md`）。
    /// 这一层不截断：截断会把一句话砍成半截，比长更糟。约束长度是 prompt 的责任。
    let text: String
}

/// 魂接不上的原因。**每一种都必须能对用户说清楚**，所以每种都带一句人话。
///
/// 刻意不提供「返回一段默认回应」的选项：那会让用户以为魂在回应他，
/// 而实际上他写的东西根本没被读过。
nonisolated enum OracleFailure: Error, Equatable, Sendable {
    /// 这个构建没有配任何 provider。
    ///
    /// 这是 Release 构建当前的真实状态——还没有安全后端（属计划 G），
    /// 所以正式构建里魂确实接不上，界面必须如实说，不能装作在思考。
    case notConfigured

    /// 这一轮没有可交出去的文字（识别没认出东西）。
    case nothingToSay

    /// 请求发出去了但没拿回可用的回应。`detail` 只用于开发期定位，不给用户看原文。
    case couldNotReach(detail: String)

    /// 给用户看的一句话。**世界观内的说法，但不掩盖「这是技术故障」这个事实。**
    var sentenceForReader: String {
        switch self {
        case .notConfigured:
            "这本日记还没有连上能回应你的那一半。你写的字都在，只是暂时没有人读。"
        case .nothingToSay:
            "这一页没读出字来，所以没什么可回的。"
        case .couldNotReach:
            "这一次没能把你写的话送出去。纸留着，可以再试。"
        }
    }
}

/// 「把话交出去、拿回一段回应」。
///
/// 具体供应商藏在这个协议后面（决策 4）：换模型、换区域、换端点都不该让画布、
/// 存储或笔画引擎知道。
nonisolated protocol OracleProvider: Sendable {
    /// - Throws: `OracleFailure`。绝不返回编出来的文字冒充成功。
    func respond(to request: OracleRequest) async throws -> OracleReply

    /// 这个 provider 的回应是不是**写死的**（也就是它根本不读用户写的字）。
    ///
    /// ── 为什么协议里需要这一条（2026-09-01 实测暴露）──
    /// 用户在模拟器上写了「Who are you?」，纸上长出一段关于阳台纸箱的话，
    /// 反馈是「回应完全不相关，像从文档里随机抓出来的」。
    /// 那**正是** Mock 的设计行为（轮换固定文字），可是**一段写死的回应和一段真回应
    /// 在纸上长得一模一样**——测的人分不清「模型很傻」和「这根本不是模型」。
    ///
    /// 光在代码注释里写清楚不够：拿着 App 测的人看不到注释。
    /// 所以界面必须能在 DEBUG 里当场说出来，而界面要能问到这件事。
    ///
    /// 默认 false：真 provider 不需要关心这件事。
    var producesCannedReplies: Bool { get }
}

/// 标 `nonisolated`：工程默认 actor 隔离是 MainActor，不标的话这个默认实现会被算成
/// 主线程隔离，于是任何在非主线程上下文里声明的 provider（比如测试里的桩）都会
/// 编译不过（「conformance crosses into main actor-isolated code」）。
/// provider 本来就该能在任意线程上被问话。
nonisolated extension OracleProvider {
    var producesCannedReplies: Bool { false }
}
