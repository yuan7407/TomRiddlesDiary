//
//  MockOracleProvider.swift
//  模块：Oracle
//
//  文件职责：一个**假的**魂，用来在没有任何网络与密钥的情况下把整条链路跑通（计划 E6a）。
//
//  ── 为什么它包在 `#if DEBUG` 里 ──
//  `AGENTS.md` 明确禁止「返回 Mock 冒充成功」。这个文件不违反那一条，因为：
//  一、**Release 构建里它不存在**，连代码都编不进去。正式构建没配 provider 就是
//     `OracleFailure.notConfigured`，界面如实说魂接不上。
//  二、它被选中不是因为真 provider 失败了，而是因为**根本还没有真 provider**
//     （安全后端属计划 G）。「用 Mock 掩盖一次失败」和「还没接真的所以先用假的开发」
//     是两件事，前者是伪装成功，后者是正常的开发顺序。
//
//  ── 它诚实到什么程度 ──
//  它**完全不读你写的字**。它按轮次轮换几段固定文字，仅此而已。
//  这一点必须写在这里、也必须让用它的人知道，否则下一个人会以为「模拟器上魂能懂中文」。
//  它唯一证明的事情是：文字进来之后，落点、排版、手绘化、逐笔重播这四步真的会跑。
//
//  ── 为什么不做「按输入选回应」的假聪明 ──
//  比如按关键词匹配、按长度挑一句。那会让它看起来像懂了，而它没有。
//  一旦看起来像懂了，就没人能分清「模型不行」和「Mock 在骗人」。
//  轮换是刻意选的：明显机械、不可能被误认为理解。
//
//  ── 这些文字是从哪来的 ──
//  取自 `C1-response-quality-set.md` 的参考答案（第 1、3、8、10 段）。
//  用它们而不是随便编，是因为那批文字正好体现了要求的形状：短、不给建议、
//  结尾有一个把话递回来的邀请。所以逐笔写出来的时候，看到的就是产品该有的样子。
//

#if DEBUG
import Foundation

/// 假的魂。**只在 DEBUG 存在，且完全不读用户写的字。**
nonisolated struct MockOracleProvider: OracleProvider {
    /// 轮换用的固定文字，取自 C1 参考答案。
    ///
    /// 刻意都带一个收尾的邀请——那是回应该有的形状（见 `C1-response-quality-set.md`
    /// 的「回应的形状」一节）。也刻意都是中英混排里的纯中文加标点，
    /// 这样逐笔写出来能同时验证汉字笔顺、标点笔画两套数据。
    private static let cannedReplies = [
        "五点前赶到了，阳台空出来了。那块地方，你打算放什么？",
        "就一下，也算。它平时让你靠多近？",
        "这句还没写完。纸等着。后面那半句，现在写得出来吗？",
        "是写下来才发现的。这周里有哪一天，你现在还想得起细节？",
    ]

    /// 轮到第几句。用 actor 存是因为 provider 本身是 `Sendable` 的值类型，
    /// 而「上次说到哪了」是跨调用的状态。
    private let cursor: Cursor

    /// 假装思考多久。
    ///
    /// 为什么不设成 0：真 provider 一定有网络延迟，而「回应要等一会儿才来」
    /// 会暴露出真实的界面问题（等待期间纸上什么都不显示、用户以为坏了）。
    /// 让 Mock 也慢一点，那些问题现在就能看见，而不是接上真 API 才第一次撞到。
    /// 取 0.6 秒：够看出「有个等待」，又不至于测试变慢。
    private let thinkingTime: Duration

    init(thinkingTime: Duration = .milliseconds(600)) {
        cursor = Cursor()
        self.thinkingTime = thinkingTime
    }

    func respond(to request: OracleRequest) async throws -> OracleReply {
        // 识别没认出东西时照样报错，而不是硬回一句——
        // 这条路径必须和真 provider 一致，否则接上真的那天才发现界面没处理。
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OracleFailure.nothingToSay
        }

        try? await Task.sleep(for: thinkingTime)

        let index = await cursor.next(upperBound: Self.cannedReplies.count)
        return OracleReply(text: Self.cannedReplies[index])
    }

    /// 轮换游标。
    private actor Cursor {
        private var count = 0

        func next(upperBound: Int) -> Int {
            defer { count += 1 }
            return count % upperBound
        }
    }
}
#endif
