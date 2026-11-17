//
//  ReadingReplyTests.swift
//  测试目标：计划 R3「让模型看图读你的字」——四行回答的解析、带图的请求格式、没认出字也照样问。
//
//  为什么这样测：
//  - 四行格式是模型和纸之间的契约：解析错了，「读到」会被写上纸，或者回应被当成「读到」印在页脚。
//    模型偶尔不守格式，解析必须宽松，但不许编造：没有「回应」那一行就整段当回应、如实标记。
//  - 带图请求的格式错了不会报错，只会让模型看不到图、照旧对着手机认错的字回话。
//  - 2026-11-17 真机实测，九成轮次手机认不出字，纸上印「没读出字来」——有图时这不该再发生。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class ReadingReplyTests: XCTestCase {
    // MARK: 四行解析

    func testFourLinesAreParsed() {
        let reply = ReadingReply.parse("读到：hello 你好\n语气：静\n回应：hello。你是第一次在这本子上写字吗？\n关照：否")
        XCTAssertTrue(reply.followedFormat)
        XCTAssertEqual(reply.heard, "hello 你好")
        XCTAssertEqual(reply.mood, "静")
        XCTAssertEqual(reply.said, "hello。你是第一次在这本子上写字吗？")
        XCTAssertFalse(reply.needsCare)
    }

    func testHalfWidthColonsAndCareAreUnderstood() {
        let reply = ReadingReply.parse("读到: 撑不住了\n语气: 重\n回应: 那就先不撑。\n关照: 是")
        XCTAssertEqual(reply.heard, "撑不住了")
        XCTAssertEqual(reply.mood, "重")
        XCTAssertTrue(reply.needsCare)
    }

    /// 回应写成两行：接起来，换行保留。
    func testMultiLineReplyIsKept() {
        let reply = ReadingReply.parse("读到：累\n语气：暖\n回应：累的是手，\n还是今天这一天？\n关照：否")
        XCTAssertEqual(reply.said, "累的是手，\n还是今天这一天？")
    }

    /// 模型没守格式：整段当回应，如实标记，不编一个「读到」。
    func testUnformattedReplyFallsBackToTheWholeText() {
        let reply = ReadingReply.parse("你来了。想写点什么？")
        XCTAssertFalse(reply.followedFormat)
        XCTAssertNil(reply.heard)
        XCTAssertEqual(reply.said, "你来了。想写点什么？")
    }

    func testUnknownMoodIsDropped() {
        XCTAssertNil(ReadingReply.parse("读到：x\n语气：开心\n回应：好。\n关照：否").mood)
    }

    // MARK: 带图的请求

    func testImageGoesOutAsAnInlinePNGBlock() throws {
        let oracle = ChatCompletionsOracle(
            endpoint: OracleEndpoint(host: "example.invalid", chatPath: "/v1/chat/completions", model: "test-model", apiKey: "sk-test"),
            systemPrompt: "你是这本日记。",
            settings: OracleRequestSettings(temperature: 0.8, maxTokens: 300, timeout: 5, wantsModelThinking: false)
        )
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let body = try oracle.body(for: "现在看附图。", image: png, isRetry: false)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages.first { $0["role"] as? String == "user" })
        let blocks = try XCTUnwrap(user["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.first?["type"] as? String, "text")
        let image = try XCTUnwrap(blocks.first { $0["type"] as? String == "image_url" }?["image_url"] as? [String: String])
        XCTAssertEqual(image["url"], "data:image/png;base64," + png.base64EncodedString())
    }

    func testDeviceTextIsOnlyAHintWhenThereIsAnImage() {
        let request = OracleRequest(text: "15.47", strokeCount: 5, handwriting: Data([1]))
        let content = request.userContent(text: "15.47")
        XCTAssertTrue(content.contains("只作参考"))
        XCTAssertTrue(content.contains("15.47"))
        XCTAssertTrue(OracleRequest(text: "", strokeCount: 5, handwriting: Data([1])).userContent(text: "").contains("没认出"))
    }

    func testSystemPromptCarriesTheReadingProtocol() {
        let persona = try! SoulPersonaLoader.decode(Data(#"{"id":"p","displayName":"魂","systemPrompt":"s","style":{"tone":"t","strokeFeel":"f","palette":"p"}}"#.utf8))
        let prompt = SoulSystemPrompt.compose(persona)
        for line in ["读到：", "语气：", "回应：", "关照："] { XCTAssertTrue(prompt.contains(line), "prompt 里没有「\(line)」") }
    }
}
