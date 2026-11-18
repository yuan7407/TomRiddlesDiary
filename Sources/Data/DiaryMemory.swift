//
//  DiaryMemory.swift
//  模块：Data（只依赖 Foundation）
//
//  文件职责：他记得的东西是什么、怎么增长、什么时候该压缩（计划 K 组，决策 84、86）。纯数据，可测。
//
//  记三样：
//  · 称呼：你告诉他怎么叫你（模型回答里的「称呼：…」那一行）。
//  · 他记得的事：更早的对话被模型压成的一小段话（K4）。
//  · 最近几轮：还没被压进去的对话，原样留着（你写的那句 + 他回的那句）。
//
//  为什么要压而不是一直攒：每一轮都要把记得的东西发给模型，攒得越多请求越慢越贵，
//  而且模型面对一长串旧对话反而抓不住重点。压的规则见 `InteractionSettings.Memory`。
//

import Foundation

nonisolated struct DiaryMemory: Codable, Equatable, Sendable {
    /// 你让他怎么叫你。nil = 还不知道。
    private(set) var name: String?
    /// 他记得的事（更早几轮被压成的一段话）。nil = 还没压过。
    private(set) var summary: String?
    /// 还没被压进去的对话，旧的在前。
    private(set) var turns: [OracleTurn] = []

    /// 记下一轮对话。模型这一轮如果读出了称呼，也一起记下（太长的不收，见 `nameMaxCharacters`）。
    mutating func record(_ turn: OracleTurn, name newName: String?) {
        turns.append(turn)
        if let newName = newName?.trimmingCharacters(in: .whitespacesAndNewlines), !newName.isEmpty,
           newName.count <= InteractionSettings.Memory.nameMaxCharacters {
            name = newName
        }
    }

    /// 该压了吗：原样的轮数攒到「保留轮数 + 一批」时，返回最旧的那一批；否则 nil。
    var turnsToFold: [OracleTurn]? {
        let m = InteractionSettings.Memory.self
        guard turns.count >= m.verbatimTurns + m.foldBatch else { return nil }
        return Array(turns.prefix(m.foldBatch))
    }

    /// 压好了：最旧的 `count` 轮已经写进新的「他记得的事」，从原样那堆里拿掉。
    /// - Precondition: 这 `count` 轮必须正是 `turnsToFold` 当时给出的那几轮（调用方保证压的过程中没人删轮）。
    mutating func folded(_ count: Int, into newSummary: String) {
        precondition(count <= turns.count, "压掉的轮数比现有的还多：\(count) > \(turns.count)")
        turns.removeFirst(count)
        summary = newSummary
    }
}
