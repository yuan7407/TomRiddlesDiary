//
//  ChatCompletionsOracle.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：真的把这一页的文字发出去，拿回魂说的一段话（计划 E6d）。
//
//  ── 为什么叫 ChatCompletions 而不是 DeepSeek ──
//  它实现的是 **OpenAI 的 chat/completions 请求格式**，而那个格式现在是行业事实标准：
//  DeepSeek、阿里云百炼兼容模式、月之暗面、以及一堆自部署方案都收这一种。
//  按格式命名而不是按供应商命名，换供应商时只需要改配置里的 host 与 model
//  （决策 4：供应商不写进业务代码）。
//  哪家、哪个端点、哪个模型全部来自 `OracleEndpoint`，本文件里没有任何供应商字面量。
//
//  ── 网络层为什么可以替换 ──
//  `Transport` 是个只有一个方法的协议。理由不是「为了抽象」，是为了能测：
//  真发网络请求的测试会慢、会不稳、会花钱，而且会把内容发给第三方——
//  `AGENTS.md` 明确要求不确定供应商行为时用 mock/fixture 隔离。
//  所以单测全部走假的 transport，真实连通性靠一次手动验证。
//
//  ── 失败一律显式抛出 ──
//  没有任何一条路径会返回编出来的文字冒充成功。key 没配、网络断、模型返回空、
//  返回的东西格式不对——每一种都抛 `OracleFailure`，由界面如实告诉用户。
//  这是 `AGENTS.md` 的「不静默兜底」在这一层的具体形态。
//
//  ── 身份泄漏为什么在这一层拦 ──
//  用户问「你是谁」的时候，模型很容易回「我是某某模型」，那会当场毁掉世界观。
//  单靠 system prompt 不可靠：直接问身份恰好是最容易泄底的场景。
//  所以这里加一道检查——但**只检查，不改写**。改写模型的话是伪造，
//  而且会让人永远不知道 prompt 到底管不管用。检查到就当这次失败、重试一次。
//

import Foundation

/// 发一次 HTTP 请求。抽出来只为了能在测试里替换掉真实网络。
nonisolated protocol OracleTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// 真实网络。
nonisolated struct URLSessionOracleTransport: OracleTransport {
    private let session: URLSession

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        // 用 ephemeral：不写 cookie、不落磁盘缓存。日记内容不该在系统缓存里留副本。
        configuration.timeoutIntervalForRequest = timeout
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OracleFailure.couldNotReach(detail: "返回的不是 HTTP 响应")
        }
        return (data, http)
    }
}

nonisolated struct ChatCompletionsOracle: OracleProvider {
    private let endpoint: OracleEndpoint
    private let systemPrompt: String
    private let transport: OracleTransport
    private let settings: OracleRequestSettings

    init(
        endpoint: OracleEndpoint,
        systemPrompt: String,
        settings: OracleRequestSettings = InteractionSettings.oracleRequest,
        transport: OracleTransport? = nil
    ) {
        self.endpoint = endpoint
        self.systemPrompt = systemPrompt
        self.settings = settings
        self.transport = transport ?? URLSessionOracleTransport(timeout: settings.timeout)
    }

    func respond(to request: OracleRequest) async throws -> OracleReply {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OracleFailure.nothingToSay }

        // 试一次，泄漏身份就再试一次。**不改写模型的话**，理由见文件头。
        // 只重试一次而不是反复重试：如果 prompt 真的没管住它，重试十次也没用，
        // 而每次重试都要花钱、花时间，还要把内容再发一遍。
        for attempt in 0 ... 1 {
            let text = try await askOnce(trimmed, isRetry: attempt > 0)
            guard let leak = OracleIdentityGuard.leakedName(in: text) else {
                return OracleReply(text: text)
            }
            if attempt == 1 {
                throw OracleFailure.brokeCharacter(leaked: leak)
            }
        }
        // 上面的循环两条路径都会 return 或 throw，走不到这里。
        throw OracleFailure.couldNotReach(detail: "重试逻辑走到了不可能的分支")
    }

    // MARK: 内部

    private func askOnce(_ text: String, isRetry: Bool) async throws -> String {
        guard let url = endpoint.chatURL else {
            throw OracleFailure.couldNotReach(detail: "端点配置拼不出合法地址")
        }

        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        httpRequest.httpBody = try body(for: text, isRetry: isRetry)

        let (data, response) = try await transport.send(httpRequest)

        guard response.statusCode == 200 else {
            // 状态码要带出来——401 是 key 不对、429 是超额度、404 多半是模型名写错，
            // 三种的处置完全不同。但**不带响应体**：那里面可能有端点细节。
            throw OracleFailure.couldNotReach(
                detail: "HTTP \(response.statusCode)\(Self.hint(forStatus: response.statusCode))"
            )
        }

        return try Self.firstMessage(from: data)
    }

    private func body(for text: String, isRetry: Bool) throws -> Data {
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text],
        ]
        // 重试时额外提醒一句。不改 system prompt——那样两次请求就不是同一个实验了。
        if isRetry {
            messages.append([
                "role": "system",
                "content": "刚才那次回答里出现了模型名或技术身份。重新答一次，只用你在这本日记里的身份。",
            ])
        }

        var payload: [String: Any] = [
            "model": endpoint.model,
            "messages": messages,
            "temperature": settings.temperature,
            "max_tokens": settings.maxTokens,
            "stream": false,
        ]

        // 明确关掉思考模式。
        //
        // 这个字段不是 OpenAI 标准的一部分，是 DeepSeek 的扩展。放在这里而不是
        // 无条件发送，因为**有些实现会对不认识的字段直接 400**。
        // 为什么要关：见 `OracleRequestSettings.wantsModelThinking`（实测数据在那儿）。
        // 换供应商时如果新那家不认这个字段，把配置里的 `wantsModelThinking` 改成 true
        // 就不会发它了——但那样要连带把 maxTokens 放大，否则思维链会吃掉整个额度。
        if !settings.wantsModelThinking {
            payload["thinking"] = ["type": "disabled"]
        }

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw OracleFailure.couldNotReach(detail: "请求体拼不出来：\(error)")
        }
    }

    /// 从 OpenAI 兼容格式的响应里取出那段话。
    ///
    /// 刻意用 `JSONSerialization` 手挖而不是定义一整套 `Decodable`：
    /// 各家在这个格式上都有自己的扩展字段，用严格的 Decodable 会因为多一个字段就整体失败。
    /// 我们只需要一个值。
    static func firstMessage(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OracleFailure.couldNotReach(detail: "响应不是 JSON")
        }
        // 有些实现会在 200 里放 error 对象。这种情况必须当失败，不能当空回应。
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未说明"
            throw OracleFailure.couldNotReach(detail: "服务端报错：\(message)")
        }
        guard let choices = root["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw OracleFailure.couldNotReach(detail: "响应里没有 choices[0].message.content")
        }

        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 被 token 上限截断要单独说。它和「网络不通」的修法完全不同：
        // 要么放大 maxTokens，要么关掉思考模式（思维链也算 token）。
        // 实测踩过：max_tokens 给 32、思考模式开着，32 个 token 全烧在思考上，
        // content 回来是空串、finish_reason 是 length——只报「空内容」会让人查错方向。
        let truncated = (choice["finish_reason"] as? String) == "length"
        guard !text.isEmpty else {
            throw OracleFailure.couldNotReach(
                detail: truncated
                    ? "回答被 token 上限截断了，一个字都没留下（思维链也算 token，检查是否关了思考模式）"
                    : "模型返回了空内容"
            )
        }
        if truncated {
            // 有内容但被截断：这段话是半截的，写到纸上就是一句没说完的话。
            throw OracleFailure.couldNotReach(detail: "回答被 token 上限截断，是半句话，没有写上去")
        }
        return text
    }

    /// 常见状态码的一句人话。**只给开发期看**，帮着分清「key 错了」和「模型名错了」。
    private static func hint(forStatus code: Int) -> String {
        switch code {
        case 401, 403: "（key 不对或没权限）"
        case 404: "（地址或模型名不对，去账号页面核对实际可用的模型）"
        case 429: "（超了速率或额度）"
        case 500 ... 599: "（服务端的问题，可以再试）"
        default: ""
        }
    }
}
