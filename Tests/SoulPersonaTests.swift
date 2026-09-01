//
//  SoulPersonaTests.swift
//  模块：Tests（人设加载与 system prompt 组装，计划 E6d）
//
//  文件职责：守住两件事。
//
//  一、**`debugOnly` 是一道真闸门。** 当前的人设是内部 IP 占位，
//     它绝不能进分发面。「记得别用它出正式包」靠人记不可靠，所以加载时强制检查。
//     这条断言就是那道闸门的证明——它红了意味着 IP 可能跟着正式包出去。
//
//  二、**渲染侧的硬约束永远会被追加。** 那几条（不要 Markdown、不要表情符号、
//     只输出要写的那段话）是纸和笔的限制，换人设也不会变。
//     少了它们，模型会输出带 `**` 和 emoji 的文本，而那些在纸上是缺字或者根本画不出来。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class SoulPersonaTests: XCTestCase {
    private func personaJSON(id: String = "p1") -> Data {
        Data("""
        {
          "id": "\(id)",
          "displayName": "测试之魂",
          "systemPrompt": "你活在这本日记里。每次回应 25 到 40 个字。",
          "style": {
            "tone": "安静、准确",
            "strokeFeel": "慢",
            "palette": "深墨"
          },
        }
        """.utf8)
    }

    // MARK: debugOnly 闸门





}
