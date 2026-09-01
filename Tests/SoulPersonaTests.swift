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
    private func personaJSON(id: String = "p1", debugOnly: Bool) -> Data {
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
          "debugOnly": \(debugOnly)
        }
        """.utf8)
    }

    // MARK: debugOnly 闸门

    /// **核心断言**：标了 `debugOnly` 的人设在正式构建里加载必须失败。
    func testDebugOnlyPersonaIsRefusedInReleaseBuilds() {
        XCTAssertThrowsError(
            try SoulPersonaLoader.decode(personaJSON(id: "ip-placeholder", debugOnly: true), isReleaseBuild: true)
        ) { error in
            XCTAssertEqual(
                error as? SoulPersonaFailure,
                .debugOnlyPersonaInReleaseBuild(id: "ip-placeholder")
            )
        }
    }

    /// 同一个人设在开发构建里照常可用。
    func testDebugOnlyPersonaLoadsInDebugBuilds() throws {
        let persona = try SoulPersonaLoader.decode(personaJSON(debugOnly: true), isReleaseBuild: false)
        XCTAssertEqual(persona.displayName, "测试之魂")
        XCTAssertTrue(persona.debugOnly)
    }

    /// 没标 debugOnly 的（将来的原创人设）两种构建都能用。
    func testOriginalPersonaLoadsEverywhere() throws {
        for isRelease in [true, false] {
            let persona = try SoulPersonaLoader.decode(personaJSON(debugOnly: false), isReleaseBuild: isRelease)
            XCTAssertFalse(persona.debugOnly)
        }
    }

    /// 格式不对要报清楚，而不是给一个空人设。
    func testMalformedPersonaThrows() {
        for junk in ["", "{}", "不是 JSON", #"{"id":"x"}"#] {
            XCTAssertThrowsError(
                try SoulPersonaLoader.decode(Data(junk.utf8), isReleaseBuild: false),
                "「\(junk)」应该报错"
            ) { error in
                guard case .malformed = error as? SoulPersonaFailure else {
                    return XCTFail("「\(junk)」报的不是 malformed：\(error)")
                }
            }
        }
    }

    /// 每种失败都要有一句给开发者看的话，而且三种不能一样。
    func testEveryFailureExplainsItself() {
        let sentences = Set([
            SoulPersonaFailure.fileMissing(path: "p"),
            .malformed(detail: "d"),
            .debugOnlyPersonaInReleaseBuild(id: "i"),
        ].map(\.sentenceForDeveloper))

        XCTAssertEqual(sentences.count, 3)
        XCTAssertFalse(sentences.contains { $0.isEmpty })
    }

    // MARK: system prompt 组装

    /// 名字、人设正文、语气、渲染约束都要在。
    func testComposedPromptCarriesEverything() throws {
        let persona = try SoulPersonaLoader.decode(personaJSON(debugOnly: true), isReleaseBuild: false)
        let prompt = SoulSystemPrompt.compose(persona)

        XCTAssertTrue(prompt.contains("测试之魂"), "名字没进 prompt")
        XCTAssertTrue(prompt.contains("每次回应 25 到 40 个字"), "人设正文没进 prompt")
        XCTAssertTrue(prompt.contains("安静、准确"), "语气没进 prompt")
    }

    /// **渲染约束永远会被追加**，不管人设里写了什么。
    /// 少了它们，模型会输出带 Markdown 和表情符号的文本，那些在纸上画不出来。
    func testRenderingConstraintsAreAlwaysAppended() throws {
        let persona = try SoulPersonaLoader.decode(personaJSON(debugOnly: true), isReleaseBuild: false)
        let prompt = SoulSystemPrompt.compose(persona)

        for required in ["Markdown", "表情符号", "生僻字", "模型名"] {
            XCTAssertTrue(prompt.contains(required), "渲染约束里少了「\(required)」")
        }
    }

    /// 打包的示例模板必须能被解析，而且**不许含任何第三方 IP 名**。
    ///
    /// 这条测的是可提交的那份模板（`Persona.example.json`）。
    /// 本地那份（`Persona.local.json`）是 gitignored 的内部占位，不在测试范围内——
    /// 它含 IP，靠 `debugOnly` 那道闸门管着（上面几条测的就是那道闸门）。
    ///
    /// ── 禁用词名单为什么从门禁脚本里读，而不是写在这里 ──
    /// 写在这里的话，**这个文件本身就含禁用词，门禁会拦住它**——
    /// 我第一版就是这么写的，当场被 `ip_firewall_check.sh` 拦下来了（它工作正常）。
    /// 从脚本读还有个额外好处：名单只有一份，以后往门禁里加词，这条测试自动跟上。
    func testCommittedTemplateIsCleanAndParsable() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // 仓库根

        let data = try Data(contentsOf: root.appendingPathComponent("Config/Persona.example.json"))
        let persona = try SoulPersonaLoader.decode(data, isReleaseBuild: false)
        XCTAssertFalse(persona.displayName.isEmpty)

        let banned = try Self.bannedTerms(gateScript: root.appendingPathComponent("scripts/ip_firewall_check.sh"))
        XCTAssertGreaterThan(banned.count, 5, "从门禁脚本里没读出禁用词，这条测试就成了空转")

        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for term in banned {
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains(term),
                "可提交的模板里出现了门禁的禁用词（第 \(banned.firstIndex(of: term) ?? -1) 个）"
            )
        }
    }

    /// 从门禁脚本里解出 `BANNED=( ... )` 那个数组。
    private static func bannedTerms(gateScript url: URL) throws -> [String] {
        let script = try String(contentsOf: url, encoding: .utf8)
        guard let start = script.range(of: "BANNED=("),
              let end = script.range(of: ")", range: start.upperBound ..< script.endIndex)
        else { return [] }

        return script[start.upperBound ..< end.lowerBound]
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty }
    }
}
