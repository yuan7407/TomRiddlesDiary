//
//  SoulPersona.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：读出「魂是谁、怎么说话」，并组装成交给模型的 system prompt（计划 E6d）。
//
//  ── 为什么 persona 必须从文件读，不能写进代码 ──
//  `AGENTS.md` 的 persona 隔离要求：persona = 名称 + system prompt + 风格，
//  集中在可替换配置里，通过 DEBUG/环境门控。三个理由都是实打实的：
//
//  一、**IP 隔离。** 内部测试用的占位人设涉及第三方 IP，它绝不能进公开面。
//     写进 Swift 源码就等于进了 Git、进了分发包，而门禁只能拦已知的禁用词，
//     拦不住「有人把人设写在代码里」这件事本身。
//  二、**换人设不该动代码。** 商业版要用完全原创的 persona。如果 prompt 写在代码里，
//     换人设就变成改代码 + 重测；从文件读则只是换一个 JSON。
//  三、**调 prompt 的频率很高。** 写 prompt 是反复试的过程，每次都改 Swift 源码
//     等于每次都重新编译整个 App。
//
//  ── `debugOnly` 是一道真闸门，不是注释 ──
//  标了 `debugOnly: true` 的 persona 在 Release 构建里**加载会失败**（下面有断言）。
//  这是为内部占位人设准备的：万一有人不小心用它出了个正式包，它会拒绝工作，
//  而不是悄悄把第三方 IP 带进分发面。
//
//  ── 文件放哪 ──
//  `Config/Persona.local.json`，已被 .gitignore 挡住（`Config/*.local.json`）。
//  可提交的模板是 `Config/Persona.example.json`，那份**禁止写任何第三方 IP 名**。
//
//  ── 为什么不打包进 App 的资源目录 ──
//  它是开发期配置，不是产品资源。放进 `Sources/Resources/` 会被打进包、被 Git 跟踪，
//  正好破坏上面第一条。所以走「构建时拷进包」那条路，只在 Debug 拷。
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

    /// 这个人设是否**只允许在开发期使用**。
    ///
    /// true 表示它含有不能进分发面的东西（典型情况：第三方 IP 占位）。
    /// 加载时会强制检查，Release 构建里加载它直接失败。
    let debugOnly: Bool
}

/// 加载 persona 失败的原因。
nonisolated enum SoulPersonaFailure: Error, Equatable, Sendable {
    /// 找不到人设文件。
    case fileMissing(path: String)
    /// 文件格式不对。
    case malformed(detail: String)
    /// 这个人设标了 `debugOnly`，而当前是正式构建。**这是拦 IP 泄漏的那道闸门。**
    case debugOnlyPersonaInReleaseBuild(id: String)

    var sentenceForDeveloper: String {
        switch self {
        case .fileMissing(let path):
            "找不到人设文件（\(path)）。复制 Config/Persona.example.json 成 Persona.local.json 再填。"
        case .malformed(let detail):
            "人设文件读不出来：\(detail)"
        case .debugOnlyPersonaInReleaseBuild(let id):
            "人设「\(id)」标了 debugOnly，不允许在正式构建里使用。商业版必须换成原创人设。"
        }
    }
}

nonisolated enum SoulPersonaLoader {
    /// 从一段 JSON 解出人设。
    /// - Parameter isReleaseBuild: 由调用方告知，方便测试两种情况都能覆盖。
    static func decode(_ data: Data, isReleaseBuild: Bool) throws -> SoulPersona {
        let persona: SoulPersona
        do {
            persona = try JSONDecoder().decode(SoulPersona.self, from: data)
        } catch {
            throw SoulPersonaFailure.malformed(detail: String(describing: error))
        }

        // 这道检查是拦 IP 泄漏的闸门，不是提醒。
        guard !(persona.debugOnly && isReleaseBuild) else {
            throw SoulPersonaFailure.debugOnlyPersonaInReleaseBuild(id: persona.id)
        }
        return persona
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
