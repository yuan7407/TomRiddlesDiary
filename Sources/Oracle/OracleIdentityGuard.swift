//
//  OracleIdentityGuard.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：检查魂有没有说漏嘴，把自己的技术身份说出来（计划 E6d，决策 69）。
//
//  ── 为什么需要它 ──
//  用户问「你是谁」，模型很容易回「我是某某模型」。那一句话会当场毁掉整个世界观——
//  一本会回应你的日记突然变成一个技术产品。
//  而**单靠 system prompt 拦不住**：直接被问身份恰好是模型最容易泄底的场景，
//  各家的对齐训练都在往「诚实说明自己是什么」的方向拉。
//
//  ── 为什么只检查、不改写 ──
//  把「我是某某模型」偷偷替换成「我是这本日记」是最容易想到的做法，也是错的：
//  一、那是**伪造模型的输出**。日志里、评测里看到的都不是模型真说的话，
//     于是「我的 prompt 到底管不管用」这个问题永远得不到答案。
//  二、它会掩盖一个真实的问题。prompt 没管住模型是需要改 prompt 的信号，
//     不是需要打补丁的地方。
//  所以这里只回答「泄了没有、泄的是哪个词」，怎么处置交给调用方
//  （`ChatCompletionsOracle` 的做法是重试一次，再失败就如实报错）。
//
//  ── 名单为什么放在这里而不是配置里 ──
//  它不是产品参数，是一份「不许出现的词」的事实清单，性质同门禁脚本里的禁用词。
//  放进 `InteractionSettings` 会让人以为它可调；它不可调，只会随着接入新供应商而追加。
//
//  ── 已知边界（别把它当保险）──
//  这是关键词匹配，只拦得住直白的泄底。模型换个说法（「我是一个由算法驱动的程序」）
//  照样能绕过去。真正管这件事的是 system prompt，这一层只是最后一道网。
//  所以**不要因为这道网存在就放松 prompt**。
//

import Foundation

nonisolated enum OracleIdentityGuard {
    /// 不许出现在回应里的词。
    ///
    /// 三类：供应商与模型名、技术身份的自称、以及中文里最常见的那几种说法。
    /// 大小写不敏感匹配，所以只写小写。
    static let forbiddenNames = [
        // 供应商与模型
        "deepseek", "qwen", "通义", "千问", "openai", "gpt", "chatgpt",
        "claude", "anthropic", "gemini", "文心", "kimi", "月之暗面", "豆包",
        "llama", "mistral", "glm", "智谱",
        // 技术身份的自称
        "语言模型", "大模型", "人工智能", "ai 助手", "ai助手", "ai 模型", "ai模型",
        "language model", "assistant developed", "i am an ai", "as an ai",
    ]

    /// 这段回应有没有说漏嘴。
    /// - Returns: 泄漏的那个词；没有则 nil。
    ///
    /// 刻意返回**具体是哪个词**而不是一个 Bool：调试时需要知道它说的是什么，
    /// 「泄漏了」这三个字对定位 prompt 问题毫无帮助。
    static func leakedName(in text: String) -> String? {
        let lowered = text.lowercased()
        return forbiddenNames.first { lowered.contains($0) }
    }
}
