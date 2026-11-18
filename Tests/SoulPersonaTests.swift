//
//  SoulPersonaTests.swift
//  模块：Tests（人设加载与 system prompt 组装，计划 E6d）
//
//  文件职责：守住三件事。
//
//  一、**人设读不出来要报清楚**，而不是给一个空人设让魂带着空 prompt 说话。
//
//  二、**渲染侧的硬约束永远会被追加。** 那几条（不要 Markdown、不要表情符号、
//     只输出要写的那段话）是纸和笔的限制，换人设也不会变。
//     少了它们，模型会输出带 `**` 和 emoji 的文本，而那些在纸上是缺字或者根本画不出来。
//
//  三、**打包的那份 `Persona.json` 本身能被解析**——它坏了，真的魂就装不起来。
//
//  ── 恢复记录（H12，2026-11-16）──
//  这 8 条里的大部分在 `d7b8f70`（删 IP 门禁那次）被一条写得太宽的删除误删，
//  只剩一个末尾多逗号的坏夹具，而当时报的测试总数里少了它们，没人发现。
//  这里以 `1c25cd2` 的版本为底恢复：仍然成立的断言照搬；
//  `debugOnly` 闸门那 3 条随闸门一起作废（决策 71、73），不恢复；
//  「模板不含禁用词」那条改成「打包的 Persona.json 能解析」，因为模板与禁用词都已删除。
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
          }
        }
        """.utf8)
    }

    // MARK: 加载

    func testWellFormedPersonaLoads() throws {
        let persona = try SoulPersonaLoader.decode(personaJSON(id: "abc"))
        XCTAssertEqual(persona.id, "abc")
        XCTAssertEqual(persona.displayName, "测试之魂")
        XCTAssertEqual(persona.style.tone, "安静、准确")
    }

    /// 格式不对要报清楚，而不是给一个空人设。
    ///
    /// 刻意不放「末尾多逗号」：被误删后留下的夹具就多一个逗号，我原以为它是坏的，
    /// 实测 iOS 27.3 的 `JSONDecoder` 照样能解（2026-11-16）。那是系统解析器的宽容，
    /// 不是我们要守的契约，写成断言只会在系统换行为时假红。
    func testMalformedPersonaThrows() {
        for junk in ["", "{}", "不是 JSON", #"{"id":"x"}"#] {
            XCTAssertThrowsError(
                try SoulPersonaLoader.decode(Data(junk.utf8)),
                "「\(junk)」应该报错"
            ) { error in
                guard case .malformed = error as? SoulPersonaFailure else {
                    return XCTFail("「\(junk)」报的不是 malformed：\(error)")
                }
            }
        }
    }

    /// 失败要有一句给开发者看的话，而且带上解析器给的细节。
    func testFailureExplainsItself() {
        let sentence = SoulPersonaFailure.malformed(detail: "细节在这").sentenceForDeveloper
        XCTAssertFalse(sentence.isEmpty)
        XCTAssertTrue(sentence.contains("细节在这"))
    }

    /// 打包进 App 的那份人设必须能解析，且不是空壳。
    /// 读仓库里的源文件而不是 `Bundle.main`：测试宿主的 bundle 是否带上资源取决于工程设置，
    /// 而这条要回答的只是「文件本身好不好」。
    func testBundledPersonaParses() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // 仓库根
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/Resources/Persona.json"))
        let persona = try SoulPersonaLoader.decode(data)
        XCTAssertFalse(persona.displayName.isEmpty)
        XCTAssertFalse(persona.systemPrompt.isEmpty)
        // 2026-11-18 用户：人设要让他一直写下去，不给他停下的理由；也不评论他的字。
        XCTAssertTrue(persona.systemPrompt.contains("绝不说「不说也行」"))
        XCTAssertTrue(persona.systemPrompt.contains("不评论他的字"))
    }

    // MARK: system prompt 组装

    /// 名字、人设正文、语气都要在。
    func testComposedPromptCarriesEverything() throws {
        let prompt = SoulSystemPrompt.compose(try SoulPersonaLoader.decode(personaJSON()))

        XCTAssertTrue(prompt.contains("测试之魂"), "名字没进 prompt")
        XCTAssertTrue(prompt.contains("每次回应 25 到 40 个字"), "人设正文没进 prompt")
        XCTAssertTrue(prompt.contains("安静、准确"), "语气没进 prompt")
    }

    /// **渲染约束永远会被追加**，不管人设里写了什么。
    func testRenderingConstraintsAreAlwaysAppended() throws {
        let prompt = SoulSystemPrompt.compose(try SoulPersonaLoader.decode(personaJSON()))

        for required in ["Markdown", "表情符号", "生僻字", "模型名"] {
            XCTAssertTrue(prompt.contains(required), "渲染约束里少了「\(required)」")
        }
    }

    /// 「下笔的样子」那一行（对开包，决策 79）必须在 prompt 里有说明，
    /// 否则模型会把那行括号当成用户写的字去回应，甚至复述里面的数字。
    func testPromptExplainsTheWritingMannerLine() throws {
        let prompt = SoulSystemPrompt.compose(try SoulPersonaLoader.decode(personaJSON()))
        XCTAssertTrue(prompt.contains("他下笔的样子"))
        XCTAssertTrue(prompt.contains("不评论他的字迹"), "2026-11-18 真机：「写这么重」「这句更乱」出戏")
    }

    /// 两个不同的人设组出来的 prompt 必须不同——人设文件真的在起作用，而不是被渲染约束淹没。
    func testDifferentPersonasComposeDifferentPrompts() throws {
        let first = try SoulPersonaLoader.decode(personaJSON())
        let second = try SoulPersonaLoader.decode(Data("""
        {"id":"p2","displayName":"另一个魂","systemPrompt":"别的说法。",
         "style":{"tone":"热烈","strokeFeel":"快","palette":"朱红"}}
        """.utf8))
        XCTAssertNotEqual(SoulSystemPrompt.compose(first), SoulSystemPrompt.compose(second))
    }
}
