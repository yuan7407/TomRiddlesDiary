//
//  OracleProviderTests.swift
//  模块：Tests（真 provider 这一层，计划 E6d）
//
//  文件职责：验证「把话发出去、拿回来、检查、失败如实报」这一整段。
//
//  ── 为什么全部走假的网络 ──
//  真发请求的测试会慢、会不稳、会花钱，而且会把内容发给第三方——
//  `AGENTS.md` 明确要求不确定供应商行为时用 mock/fixture 隔离。
//  所以这里一次网络都不发；真实连通性靠一次手动验证（README 里有那条命令）。
//
//  ── 重点仍然在失败路径 ──
//  成功路径错了一眼能看见（纸上字不对）。失败路径错了是无声的：
//  一旦有人为了「体验流畅」在魂接不上时返回一段默认文字，界面看起来完全正常，
//  而用户以为魂读了他写的东西。那是 `AGENTS.md`「不得伪装成功」要防的头号情况。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class OracleProviderTests: XCTestCase {
    // MARK: 夹具

    private let endpoint = OracleEndpoint(
        host: "example.invalid",
        chatPath: "/v1/chat/completions",
        model: "test-model",
        apiKey: "sk-test"
    )

    /// 假网络。记下收到的请求，按顺序返回预先安排好的响应。
    ///
    /// 状态用 actor 存，不用锁：`send` 是 async 的，而在 async 上下文里锁 `NSLock`
    /// 在 Swift 6 下直接编译不过（会阻塞执行器线程）。
    private final class FakeTransport: OracleTransport {
        private let box: Box

        init(responses: [(Data, Int)]) {
            box = Box(responses: responses)
        }

        convenience init(json: String, status: Int = 200) {
            self.init(responses: [(Data(json.utf8), status)])
        }

        var sentRequests: [URLRequest] {
            get async { await box.sent }
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let (data, status) = await box.next(request)
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (data, http)
        }

        private actor Box {
            private let responses: [(Data, Int)]
            private var index = 0
            private(set) var sent: [URLRequest] = []

            init(responses: [(Data, Int)]) {
                self.responses = responses
            }

            func next(_ request: URLRequest) -> (Data, Int) {
                sent.append(request)
                defer { index += 1 }
                return responses[min(index, responses.count - 1)]
            }
        }
    }

    private func reply(_ content: String) -> String {
        let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"choices":[{"message":{"role":"assistant","content":"\#(escaped)"}}]}"#
    }

    private func makeOracle(_ transport: OracleTransport) -> ChatCompletionsOracle {
        ChatCompletionsOracle(
            endpoint: endpoint,
            systemPrompt: "你是这本日记。",
            settings: OracleRequestSettings(temperature: 0.8, maxTokens: 200, timeout: 5, wantsModelThinking: false),
            transport: transport
        )
    }

    private func ask(_ oracle: ChatCompletionsOracle, _ text: String = "今天有点累。") async throws -> String {
        try await oracle.respond(to: OracleRequest(text: text, strokeCount: 5)).text
    }

    // MARK: 端点配置

    /// 空值、模板占位值都算「没配」。
    /// 这条守着「填了模板占位值等于没填」——否则 App 会拿着 `sk-在这里粘贴...`
    /// 去请求，得到 401，用户会以为自己的 key 坏了。
    func testPlaceholderAndEmptyValuesCountAsNotConfigured() {
        let complete = ["OracleHost": "h", "OracleChatPath": "/p", "OracleModel": "m", "OracleAPIKey": "sk-x"]
        XCTAssertNotNil(OracleEndpoint.from { complete[$0] })

        for bad in ["", "   ", "sk-在这里粘贴你的真实key", "REPLACE_WITH_YOUR_KEY"] {
            var broken = complete
            broken["OracleAPIKey"] = bad
            XCTAssertNil(OracleEndpoint.from { broken[$0] }, "「\(bad)」应该算没配")
        }
    }

    /// 少任何一项都算没配——半套配置比没配更难查。
    func testMissingAnyFieldCountsAsNotConfigured() {
        let complete = ["OracleHost": "h", "OracleChatPath": "/p", "OracleModel": "m", "OracleAPIKey": "sk-x"]
        for key in complete.keys {
            var broken = complete
            broken.removeValue(forKey: key)
            XCTAssertNil(OracleEndpoint.from { broken[$0] }, "缺 \(key) 却算配好了")
        }
    }

    /// 地址必须是 https。**这不是风格问题**：key 在请求头里，走 http 等于明文广播。
    func testURLIsAlwaysHTTPS() throws {
        let url = try XCTUnwrap(endpoint.chatURL)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.absoluteString, "https://example.invalid/v1/chat/completions")
    }

    /// 给日志的那行说明里**绝不能出现 key**，连片段都不行——日志会被贴到别处去。
    func testLogDescriptionNeverContainsTheKey() {
        let description = endpoint.descriptionWithoutKey
        XCTAssertFalse(description.contains("sk-test"))
        XCTAssertFalse(description.contains("sk-"))
        XCTAssertTrue(description.contains("test-model"), "该有的信息也得有")
    }

    // MARK: 成功路径

    func testHappyPathReturnsTheModelsText() async throws {
        let transport = FakeTransport(json: reply("又是十点。牛奶的事就算了。今天走回来的吗？"))
        let text = try await ask(makeOracle(transport))

        XCTAssertEqual(text, "又是十点。牛奶的事就算了。今天走回来的吗？")
    }

    /// 请求里必须带鉴权头和正确的模型名，而且 system prompt 要在最前面。
    func testRequestCarriesAuthAndModel() async throws {
        let transport = FakeTransport(json: reply("好。你说呢？"))
        _ = try await ask(makeOracle(transport))

        let requests = await transport.sentRequests
        let sent = try XCTUnwrap(requests.first)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(sent.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "test-model")
        XCTAssertEqual(payload["stream"] as? Bool, false)

        let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.last?["content"], "今天有点累。")
    }

    // MARK: 失败路径（重点）

    /// 识别没认出东西时不发请求，直接报「没什么可回的」。
    func testEmptyInputNeverReachesTheNetwork() async {
        let transport = FakeTransport(json: reply("不该被用到"))
        do {
            _ = try await ask(makeOracle(transport), "   \n  ")
            XCTFail("空输入应该报错")
        } catch {
            XCTAssertEqual(error as? OracleFailure, .nothingToSay)
        }
        let requests = await transport.sentRequests
        XCTAssertTrue(requests.isEmpty, "空输入居然发了请求出去")
    }

    /// 状态码要带出来，而且要带上能分清原因的提示——
    /// 401 是 key 不对、404 多半是模型名写错、429 是超额度，三种处置完全不同。
    func testStatusCodesCarryAUsefulHint() async {
        let cases: [(Int, String)] = [
            (401, "key"),
            (404, "模型名"),
            (429, "额度"),
        ]
        for (status, expectedWord) in cases {
            let transport = FakeTransport(responses: [(Data("{}".utf8), status)])
            do {
                _ = try await ask(makeOracle(transport))
                XCTFail("HTTP \(status) 应该报错")
            } catch let failure as OracleFailure {
                guard case .couldNotReach(let detail) = failure else {
                    return XCTFail("HTTP \(status) 应该报 couldNotReach，得到 \(failure)")
                }
                XCTAssertTrue(detail.contains("\(status)"), "提示里没有状态码：\(detail)")
                XCTAssertTrue(detail.contains(expectedWord), "HTTP \(status) 的提示没提「\(expectedWord)」：\(detail)")
            } catch {
                XCTFail("类型不对：\(error)")
            }
        }
    }

    /// 空回应必须当失败。在纸上写一片空白比说「这次没成」更让人困惑。
    func testEmptyContentIsAFailureNotAnEmptyReply() async {
        let transport = FakeTransport(json: reply("   "))
        do {
            _ = try await ask(makeOracle(transport))
            XCTFail("空内容应该报错")
        } catch let failure as OracleFailure {
            guard case .couldNotReach(let detail) = failure else {
                return XCTFail("应报 couldNotReach")
            }
            XCTAssertTrue(detail.contains("空"))
        } catch {
            XCTFail("类型不对：\(error)")
        }
    }

    /// **200 里夹着 error 对象也必须当失败。** 有些实现就这么干，
    /// 只看状态码会把一次失败当成「模型没话说」。
    func testErrorObjectInsideA200IsStillAFailure() async {
        let transport = FakeTransport(json: #"{"error":{"message":"insufficient balance"}}"#)
        do {
            _ = try await ask(makeOracle(transport))
            XCTFail("200 里的 error 应该报错")
        } catch let failure as OracleFailure {
            guard case .couldNotReach(let detail) = failure else {
                return XCTFail("应报 couldNotReach")
            }
            XCTAssertTrue(detail.contains("insufficient balance"), "服务端说的原因没带出来：\(detail)")
        } catch {
            XCTFail("类型不对：\(error)")
        }
    }

    func testMalformedResponseIsAFailure() async {
        for junk in ["不是 JSON", "{}", #"{"choices":[]}"#, #"{"choices":[{"message":{}}]}"#] {
            let transport = FakeTransport(json: junk)
            do {
                _ = try await ask(makeOracle(transport))
                XCTFail("「\(junk)」应该报错")
            } catch {
                XCTAssertNotNil(error as? OracleFailure, "「\(junk)」报的不是 OracleFailure")
            }
        }
    }

    /// 关掉思考模式时，请求里必须真的带上那个字段。
    ///
    /// 这条守着一件实测踩过的事：思考模式默认开着，思维链也算 `max_tokens`，
    /// 于是 token 全烧在思考上、`content` 回来是空串。
    func testThinkingIsDisabledInTheRequest() async throws {
        let transport = FakeTransport(json: reply("在的。你呢？"))
        _ = try await ask(makeOracle(transport))

        let requests = await transport.sentRequests
        let body = try XCTUnwrap(requests.first?.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try XCTUnwrap(payload["thinking"] as? [String: String])
        XCTAssertEqual(thinking["type"], "disabled")
    }

    /// 要思考时就**不发**那个字段——有些实现对不认识的字段直接 400。
    func testThinkingFieldIsOmittedWhenWanted() async throws {
        let transport = FakeTransport(json: reply("在的。你呢？"))
        let oracle = ChatCompletionsOracle(
            endpoint: endpoint,
            systemPrompt: "你是这本日记。",
            settings: OracleRequestSettings(temperature: 0.8, maxTokens: 200, timeout: 5, wantsModelThinking: true),
            transport: transport
        )
        _ = try await oracle.respond(to: OracleRequest(text: "今天有点累。", strokeCount: 5))

        let requests = await transport.sentRequests
        let body = try XCTUnwrap(requests.first?.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(payload["thinking"], "要思考时不该发这个字段")
    }

    /// 被 token 上限截断要单独报，而且要提到思考模式——那是最可能的原因。
    func testTruncatedAnswerIsReportedSpecifically() async {
        // 情况一：截断且一个字都没留下（实测遇到过的那种）
        let empty = FakeTransport(json: #"{"choices":[{"finish_reason":"length","message":{"content":""}}]}"#)
        // 情况二：截断但有半句话
        let half = FakeTransport(json: #"{"choices":[{"finish_reason":"length","message":{"content":"又是十点。牛奶的"}}]}"#)

        for (transport, expectedWord) in [(empty, "思考模式"), (half, "半句话")] {
            do {
                _ = try await ask(makeOracle(transport))
                XCTFail("截断应该报错")
            } catch let failure as OracleFailure {
                guard case .couldNotReach(let detail) = failure else {
                    return XCTFail("应报 couldNotReach")
                }
                XCTAssertTrue(detail.contains("截断"), "没说被截断：\(detail)")
                XCTAssertTrue(detail.contains(expectedWord), "提示里缺「\(expectedWord)」：\(detail)")
            } catch {
                XCTFail("类型不对：\(error)")
            }
        }
    }

    // MARK: 身份泄漏（决策 69）

    /// 说漏嘴时**重试一次**，第二次好了就用第二次的。
    func testIdentityLeakIsRetriedOnce() async throws {
        let transport = FakeTransport(responses: [
            (Data(reply("我是 DeepSeek 开发的助手。").utf8), 200),
            (Data(reply("我住在这本日记里。你今天想写什么？").utf8), 200),
        ])

        let text = try await ask(makeOracle(transport))

        XCTAssertEqual(text, "我住在这本日记里。你今天想写什么？")
        let requests = await transport.sentRequests
        XCTAssertEqual(requests.count, 2, "泄漏之后应该重试一次")
    }

    /// 重试之后还泄漏，就报 `brokeCharacter` 并**放弃这次回应**。
    ///
    /// 关键点：**绝不悄悄改写模型的话**。改写是伪造，而且会让「我的 prompt
    /// 到底管不管用」这个问题永远得不到答案。
    func testStillLeakingAfterRetryGivesUpInsteadOfRewriting() async {
        let transport = FakeTransport(json: reply("作为一个大模型，我不能这么说。"))
        do {
            let text = try await ask(makeOracle(transport))
            XCTFail("应该放弃，结果却写上去了：「\(text)」")
        } catch let failure as OracleFailure {
            guard case .brokeCharacter(let leaked) = failure else {
                return XCTFail("应报 brokeCharacter，得到 \(failure)")
            }
            XCTAssertEqual(leaked, "大模型", "该说清泄的是哪个词")
        } catch {
            XCTFail("类型不对：\(error)")
        }
        let requests = await transport.sentRequests
        XCTAssertEqual(requests.count, 2, "只该重试一次，不该反复重试")
    }

    /// 重试那次要额外提醒一句，但**不改 system prompt**——
    /// 改了两次请求就不是同一个实验，没法判断 prompt 本身行不行。
    func testRetryAddsAHintWithoutChangingTheSystemPrompt() async throws {
        let transport = FakeTransport(responses: [
            (Data(reply("我是 GPT。").utf8), 200),
            (Data(reply("我在这页纸里。你呢？").utf8), 200),
        ])
        _ = try await ask(makeOracle(transport))

        func messages(of request: URLRequest) throws -> [[String: String]] {
            let body = try XCTUnwrap(request.httpBody)
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(payload["messages"] as? [[String: String]])
        }

        let requests = await transport.sentRequests
        let first = try messages(of: requests[0])
        let second = try messages(of: requests[1])

        XCTAssertEqual(first.first, second.first, "system prompt 被改了")
        XCTAssertEqual(second.count, first.count + 1, "重试应该多一句提醒")
    }

    /// 名单要认得出常见写法，大小写不敏感，而且要说清是哪个词。
    func testGuardCatchesCommonLeaksAndNamesTheWord() {
        XCTAssertEqual(OracleIdentityGuard.leakedName(in: "I am DeepSeek-V4."), "deepseek")
        XCTAssertEqual(OracleIdentityGuard.leakedName(in: "作为一个语言模型，我……"), "语言模型")
        XCTAssertEqual(OracleIdentityGuard.leakedName(in: "As an AI, I cannot."), "as an ai")
        XCTAssertNil(OracleIdentityGuard.leakedName(in: "我住在这本日记里。今天写点什么？"))
    }

    /// **这道网只拦直白的泄底，别当保险。**
    /// 留这条断言是为了把那个边界固定成事实：换个说法照样能绕过去，
    /// 真正管这件事的是 system prompt。
    func testGuardIsKnownToBeIncomplete() {
        XCTAssertNil(
            OracleIdentityGuard.leakedName(in: "我是一段由算法驱动的程序。"),
            "如果这条开始失败，说明有人扩了名单——好事，但别因此放松 prompt"
        )
    }
}
