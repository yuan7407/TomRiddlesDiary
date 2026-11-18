//
//  MemoryPrompt.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：让模型把更早的对话压成「他记得的事」的那段说明（计划 K4，用户 2026-11-18 定由模型来写）。
//
//  为什么和人设分开：这不是「他说话」，是「他记事」。记事的规则（短、只记事实、不评判）换人设也不变，
//  所以不放进 Persona.json；和 `SoulSystemPrompt.readingProtocol` 一样是固定追加的规则。
//  压出来的那段话只发给模型、不上纸。
//

import Foundation

nonisolated enum MemoryPrompt {
    /// 系统说明。字数上限从 `InteractionSettings.Memory` 来（唯一定义处）。
    static var system: String {
        """
        你是一本日记里那个声音的记性。日记的主人手写，那个声音手写回应。
        你的活：把「原来记得的事」和「更早的几轮对话」合成一段新的「记得的事」，以后每一轮都会带着它去回应他。
        · 不超过 \(InteractionSettings.Memory.summaryMaxCharacters) 个字。用中文写，他用过的英文词照原样保留。
        · 称他为「他」。只记事实：他提到的人和事、反复出现的念头、他的说话方式和情绪的走向、他对这个声音的态度。
        · 新的压过旧的；原来记得的事里已经过时的就删掉，不要越攒越长。
        · 不评判、不下诊断、不写建议。不抄大段原话，只在一两个词特别要紧时保留原词。
        · 只输出那段话本身，不要标题、不要分点、不要引号。
        """
    }

    /// 交给模型的材料。
    static func userContent(previous: String?, turns: [OracleTurn]) -> String {
        var lines = ["原来记得的事：\(previous ?? "（还没有）")", "", "更早的几轮对话（旧的在前）："]
        for turn in turns { lines.append("他写：\(turn.you)\n你回：\(turn.him)") }
        return lines.joined(separator: "\n")
    }
}
