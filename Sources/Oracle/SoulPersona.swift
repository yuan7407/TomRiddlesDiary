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

}

/// 加载 persona 失败的原因。
nonisolated enum SoulPersonaFailure: Error, Equatable, Sendable {
    /// 找不到人设文件。
    case fileMissing(path: String)
    /// 文件格式不对。
    case malformed(detail: String)
    var sentenceForDeveloper: String {
        switch self {
        case .fileMissing(let path):
            "找不到人设文件（\(path)）。复制 Config/Persona.example.json 成 Persona.local.json 再填。"
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
    · 用常用汉字。生僻字在纸上会变成空缺。
    · 标点只用：。，、？！；：「」（）—…
    · 不要出现任何模型名、公司名或「语言模型」「AI 助手」这类说法。
    """

    static func compose(_ persona: SoulPersona) -> String {
        """
        你的名字是\(persona.displayName)。

        \(persona.systemPrompt)

        语气：\(persona.style.tone)
        \(renderingConstraints)
        """
    }
}
