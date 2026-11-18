//
//  SoulPersona.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：读出「魂是谁、怎么说话」，并组装成交给模型的 system prompt（计划 E6d）。
//
//  ── 为什么 persona 从文件读，不写进代码 ──
//  一、**调 prompt 的频率很高。** 写 prompt 是反复试的过程，每次改 Swift 源码
//     等于每次重新编译整个 App。
//  二、**换人设不该动代码。** 换个魂只是换一个 JSON。
//
//  ── 文件放哪：`Sources/Resources/Persona.json`，一个普通的打包资源 ──
//  2026-09-01 简化：原先它是 `Config/Persona.local.json`（gitignored）+
//  `Persona.example.json`（模板）+ 一个「只在 Debug 拷进包」的构建脚本 + 一个
//  `debugOnly` 字段做二次闸门，一共四样东西。那套复杂度全部来自「人设含第三方 IP、
//  不能进分发面」这个前提。**用户明确取消了那个前提**（个人项目，IP 出现算惊喜），
//  所以四样东西塌成一个普通资源文件。
//
//  改人设只需要改这一个 JSON，不用动代码——这条才是 persona 独立成文件的真正理由
//  （写 prompt 是反复试的过程，每次改都要重编译整个 App 是不可接受的）。
//

import Foundation

/// 魂的人设。
nonisolated struct SoulPersona: Equatable, Sendable, Decodable {
    /// 内部标识。
    let id: String

    /// 魂的名字。会出现在 system prompt 里。
    let displayName: String

    /// 人设与说话规则的主体。**这是最要紧的一段**，写 prompt 的功夫都在这里。
    let systemPrompt: String

    /// 风格描述。目前只进 prompt 的语气部分，不影响笔画（手感永远由本地引擎决定）。
    nonisolated struct Style: Equatable, Sendable, Decodable {
        let tone: String
        let strokeFeel: String
        let palette: String
    }
    let style: Style

    /// 翻开本子时他先说的话（计划 P6）。可选：没有这一段的人设就不开场，不编一句顶上。
    let opening: Opening?

    nonisolated struct Opening: Equatable, Sendable, Decodable {
        /// 按钟点分组：`hour < before` 的第一组生效。
        nonisolated struct ByHour: Equatable, Sendable, Decodable {
            let before: Int
            let first: String
            let second: String
        }
        let byHour: [ByHour]
        let askName: String
        let returning: String

        /// 这一次翻开他写什么（原型 startIntro）：还不知道你叫什么，就是「问候 + 问称呼」；
        /// 知道了，就是「回来了，<称呼>」+ 第二句。`returning` 里的 `{称呼}` 换成你的称呼。
        ///
        /// 2026-11-18 起按「知不知道称呼」而不是「来过几次」：称呼存在加密的记忆里（K2），
        /// 来过却没告诉他称呼的人，下次他还会问。
        /// 两句之间换行。钟点落不进任何一组（数据写漏了）时返回 nil，由调用方不开场，而不是猜一句。
        func lines(hour: Int, name: String?) -> String? {
            guard let group = byHour.first(where: { hour < $0.before }) else { return nil }
            guard let name else { return group.first + "\n" + askName }
            return returning.replacingOccurrences(of: "{称呼}", with: name) + "\n" + group.second
        }
    }
}

/// 加载 persona 失败的原因。
///
/// 「找不到文件」不在这里：人设是普通打包资源，缺了由 `OracleAssembly` 当场报
/// （它是唯一知道去哪找的地方）。2026-11-16 删掉了原先的 `fileMissing`——
/// 全仓库没有地方构造它，提示文字还指向早已删除的 `Persona.example.json`。
nonisolated enum SoulPersonaFailure: Error, Equatable, Sendable {
    /// 文件格式不对。
    case malformed(detail: String)
    var sentenceForDeveloper: String {
        switch self {
        case .malformed(let detail):
            "人设文件读不出来：\(detail)"
        }
    }
}

nonisolated enum SoulPersonaLoader {
    /// 从一段 JSON 解出人设。
    static func decode(_ data: Data) throws -> SoulPersona {
        do {
            return try JSONDecoder().decode(SoulPersona.self, from: data)
        } catch {
            throw SoulPersonaFailure.malformed(detail: String(describing: error))
        }
    }
}

/// 把人设 + 手写渲染的硬约束合成一段 system prompt。
///
/// ── 为什么这里还要追加一段「渲染约束」 ──
/// 人设文件负责「谁在说话、怎么说」，而下面这几条是**纸和笔的物理限制**，
/// 换人设也不会变，所以不该让每个写人设的人都记得抄一遍：
/// · 输出只能是纸上写得出来的字符（字形数据覆盖 9574 汉字 + 27 标点 + 62 拉丁字母数字）
/// · 不能有 Markdown、表情符号、生僻字——那些在纸上会变成缺字或者根本画不出来
/// · 只输出要写的那段话本身，不要解释、不要加引号、不要分点
nonisolated enum SoulSystemPrompt {
    /// 渲染侧的硬约束。和人设无关，永远追加。
    static let renderingConstraints = """

    ————
    下面几条是纸和笔的限制，与你是谁无关，但必须遵守：
    · 只输出你要写在纸上的那段话本身。不要解释、不要加引号、不要分点、不要用 Markdown。
    · 不要用表情符号、颜文字、特殊符号。纸上写不出来。
    · 纸上写得出常用汉字、英文字母（a–z、A–Z）和数字。生僻字会变成空缺，不要用。
    · 他只写了英文（哪怕只有一个词，比如 hi），你就用英文回；他中英混写，你也照他的样子混写，英文词照他的拼写，不翻译。
    · 标点只用：。，、？！；：「」（）—… 以及英文的 , . ? ! ' :
    · 不要出现任何模型名、公司名或「语言模型」「AI 助手」这类说法。
    · 请求开头可能有「他让你叫他」「你记得的事」「之前的几轮」：那是你自己记下的，不是他这一次写的。
      称呼可以偶尔用，不要每句都叫；记得的事只在和他这一句有关时才提，不要为了显得记得而提。
    · 他写的话后面有时会跟一行括号，以「他下笔的样子」开头。那不是他写的字，是纸感觉到的：几笔、多久、快慢、停了多久。
      它只供你体会他的状态。先接住他写的话本身：他在骂你、冲你来、问你问题，或写了有分量的事，就回应那件事，不提下笔的样子。
      只在自然的时候偶尔提一句（比如「你写得很急」），不复述数字；之前几轮已经提过，就不要再提。
    """

    /// 读图与回答格式（计划 R3，照搬网页原型 RULES 的读图与输出部分；第五行「称呼」是 K2 加的）。
    /// 和人设无关，永远追加：`ReadingReply` 按这五行解析，格式一变就解析不出来。
    static let readingProtocol = """

    ————
    他的话是手写在纸上的。请求里常附一张图：那就是他刚写的字（中文或英文，可能潦草，可能只有几个字）。
    · 先认出他写了什么，以图为准。手机自己认的字常认错，只作参考。
    · 认不出就老实说看不清，请他写大一点再写一遍，不要猜着答。
    · 严格按下面五行输出，不要别的：
    读到：<照抄你认出的原文；认不出写 看不清>
    语气：<从 静、轻、重、暖 里选一个字，按他这句话的分量选>
    回应：<你写在纸上的话>
    关照：<他写了想伤害自己、活不下去的意思时写 是，否则写 否>
    称呼：<他在这一句里告诉你怎么叫他（回答你问的称呼、「我叫…」「叫我…」）时只写那个称呼，否则写 无>
    """

    static func compose(_ persona: SoulPersona) -> String {
        """
        你的名字是\(persona.displayName)。

        \(persona.systemPrompt)

        语气：\(persona.style.tone)
        \(renderingConstraints)
        \(readingProtocol)
        """
    }
}
