//
//  WrittenLanguage.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：看一段字是英文、中文还是中英混写，以及他的回应语言对不对得上。
//
//  为什么要在代码里管（2026-11-18 真机）：你用英文写了一整句，他读对了（「读到」是那句英文），
//  却用中文回。system prompt 里那条「他只写英文你就用英文回」被整段中文的人设和中文的请求措辞淹没了，
//  只靠 prompt 不可靠。所以分两道：请求里明说「这一句是英文」，回来的话里还带汉字就再问一次。
//
//  判据刻意粗：只看有没有汉字、有没有拉丁字母。数字、标点不算任何一边。
//  中文和混写不管——混写本来就允许他照样混，中文回中文是默认。
//

import Foundation

nonisolated enum WrittenLanguage: Equatable, Sendable {
    case english
    case chinese
    case mixed

    /// 一段字是什么语言。既没有汉字也没有字母（只有数字、标点、空白）时为 nil：说不出来就不管。
    static func of(_ text: String) -> WrittenLanguage? {
        let scalars = text.unicodeScalars
        let hasHan = scalars.contains { $0.properties.isIdeographic }
        let hasLatin = scalars.contains { $0.isASCII && $0.properties.isAlphabetic }
        switch (hasHan, hasLatin) {
        case (true, true): return .mixed
        case (true, false): return .chinese
        case (false, true): return .english
        case (false, false): return nil
        }
    }

    /// 他的回应对得上你写的语言吗。只管一种情况：你只写了英文，他的话里不该有汉字。
    static func reply(_ said: String, suits written: WrittenLanguage?) -> Bool {
        guard written == .english else { return true }
        return !said.unicodeScalars.contains { $0.properties.isIdeographic }
    }

    /// 你只写了英文时，请求里加的那一句（说给模型听的，不上纸）。
    static let englishOnlyNote = "他这一句是用英文写的：你这一次只用英文回，一个汉字也不要。"
    /// 他还是用了中文，重问那一次额外的提醒。
    static let englishRetryReminder = "他写的是英文，你刚才用了中文。重新答一次，回应那一行只用英文。"
}
