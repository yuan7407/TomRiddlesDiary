//
//  OracleMannerWireTests.swift
//  测试目标：ChatCompletionsOracle 真的把「他下笔的样子」放进了发给模型的用户消息里，
//  并且没有 `manner` 时请求体里的用户消息仍然只有他写的字。
//
//  为什么单独测「线上的字节」：`OracleRequest.userContent` 对了不等于 provider 用了它。
//  这里用一个只记录请求的假通道，直接解开发出去的 JSON 看。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class OracleMannerWireTests: XCTestCase {
    /// 只记录请求、固定回一句话的假通道。用 actor 存请求，不需要 `@unchecked Sendable`。
    private struct RecordingTransport: OracleTransport {
        private let box = Box()

        var sentBodies: [Data] {
            get async { await box.bodies }
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            await box.record(request.httpBody ?? Data())
            let reply = #"{"choices":[{"message":{"role":"assistant","content":"我在。慢慢写。"}}]}"#
            let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(reply.utf8), http)
        }

        private actor Box {
            private(set) var bodies: [Data] = []
            func record(_ body: Data) { bodies.append(body) }
        }
    }

    private func makeOracle(_ transport: OracleTransport) -> ChatCompletionsOracle {
        ChatCompletionsOracle(
            endpoint: OracleEndpoint(host: "example.invalid", chatPath: "/v1/chat/completions", model: "test-model", apiKey: "sk-test"),
            systemPrompt: "你是这本日记。",
            settings: OracleRequestSettings(temperature: 0.8, maxTokens: 200, timeout: 5, wantsModelThinking: false),
            transport: transport
        )
    }

    private func userMessage(in body: Data) throws -> String {
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])
        return try XCTUnwrap(messages.first { $0["role"] == "user" }?["content"])
    }

    private let manner = WritingManner(shape: .loop)

    func testWithoutMannerTheUserMessageIsOnlyTheWords() async throws {
        let transport = RecordingTransport()
        _ = try await makeOracle(transport).respond(to: OracleRequest(text: "  今天有点累。\n", strokeCount: 12))
        let bodies = await transport.sentBodies
        XCTAssertEqual(try userMessage(in: try XCTUnwrap(bodies.first)), "今天有点累。")
    }

    func testWithMannerTheUserMessageCarriesItOnASecondLine() async throws {
        let transport = RecordingTransport()
        _ = try await makeOracle(transport).respond(to: OracleRequest(text: "今天有点累。", strokeCount: 12, manner: manner))
        let bodies = await transport.sentBodies
        let message = try userMessage(in: try XCTUnwrap(bodies.first))
        XCTAssertEqual(message, "今天有点累。\n（他下笔的样子：没有写字，画了一个首尾相接的圈。）")
    }

    func testEmptyWritingStillHasNothingToSayEvenWithAManner() async {
        let transport = RecordingTransport()
        do {
            _ = try await makeOracle(transport).respond(to: OracleRequest(text: "   ", strokeCount: 1, manner: manner))
            XCTFail("没读出字时不该发请求")
        } catch {
            XCTAssertEqual(error as? OracleFailure, .nothingToSay)
        }
        let bodies = await transport.sentBodies
        XCTAssertTrue(bodies.isEmpty, "只有下笔的样子、没有字，不能当成有话可回")
    }
}
