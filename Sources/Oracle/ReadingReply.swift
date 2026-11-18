//
//  ReadingReply.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：把模型按五行写回来的话拆开（计划 R3，网页原型 RULES 的输出格式，加上 K2 的称呼）：
//      读到：<他认出你写了什么>
//      语气：<静 / 轻 / 重 / 暖>
//      回应：<写在纸上的话>
//      关照：<是 / 否>
//      称呼：<你在这一句里告诉他怎么叫你；没有写 无>
//
//  为什么要四行而不是只要一句回应：只有「回应」会写上纸；「读到」印在页脚，让你看见他读到了什么
//  （读错了你一眼就知道是识别的问题，而不是他答非所问）；「语气」改变他下笔的快慢轻重（P9）；
//  「关照」决定要不要在纸外弹出求助条（决策 67）。
//
//  解析宽松，失败不静默：模型偶尔不守格式（多一行、少一行、用了半角冒号）。
//  找不到「回应」那一行时，退回把整段当作回应——并且如实标记 `followedFormat = false`，
//  调用方打日志；不编一个「读到」顶上。
//

import Foundation

nonisolated struct ReadingReply: Equatable, Sendable {
    let heard: String?
    let mood: String?
    let said: String
    let needsCare: Bool
    /// 你在这一句里告诉他的称呼（K2）。「无」或没给这一行时为 nil。
    let name: String?
    /// 模型有没有按格式回。false 时 `said` 是整段原文。
    let followedFormat: Bool

    /// 四种语气（原型 MOODS 的键）。模型给了别的字就当没给。
    static let moods: Set<String> = ["静", "轻", "重", "暖"]
    /// 「称呼」那一行里表示「没说」的写法。
    static let noName: Set<String> = ["无", "没有", "不知道", "none", "None", "-", "—"]

    static func parse(_ raw: String) -> ReadingReply {
        var fields: [String: String] = [:]
        var current: String?
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let (key, value) = field(in: trimmed) {
                fields[key] = value
                current = key
            } else if let key = current, key == "回应", !trimmed.isEmpty {
                // 回应可能写成两行：接在后面，换行保留（他写字时会按意思换行）。
                fields[key, default: ""] += "\n" + trimmed
            }
        }
        guard let said = fields["回应"]?.trimmingCharacters(in: .whitespacesAndNewlines), !said.isEmpty else {
            return ReadingReply(heard: nil, mood: nil, said: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                                needsCare: false, name: nil, followedFormat: false)
        }
        let heard = fields["读到"].flatMap { $0.isEmpty ? nil : $0 }
        let mood = fields["语气"].flatMap { value in moods.first { value.contains($0) } }
        let care = fields["关照"].map { $0.hasPrefix("是") } ?? false
        let name = fields["称呼"].flatMap { value in value.isEmpty || noName.contains(value) ? nil : value }
        return ReadingReply(heard: heard, mood: mood, said: said, needsCare: care, name: name, followedFormat: true)
    }

    private static let keys = ["读到", "语气", "回应", "关照", "称呼"]

    /// 「读到：xxx」或「读到:xxx」→ ("读到", "xxx")。
    private static func field(in line: String) -> (String, String)? {
        for key in keys where line.hasPrefix(key) {
            let rest = line.dropFirst(key.count).drop { $0 == " " }
            guard let colon = rest.first, colon == "：" || colon == ":" else { continue }
            return (key, rest.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
