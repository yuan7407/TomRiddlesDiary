//
//  ReplyPlacement.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：决定魂这段回应写在页面的哪里（计划 E9e）。
//
//  ── 用户定的版式 ──
//  「回应排在刚写完那句话旁边（右边或者下方），找个随机空位。写满了就翻页。」
//  这个文件就是那句话的实现。
//
//  ── 它需要的四样输入都已经建好 ──
//  E9a `PageRegion.covering`：你刚写的那句话占了哪块地方
//  E9b `PageInkMap`：页面上哪里已经有墨
//  E9c 字号：暂时用配置默认值（估算目前偏得太多，见 `HandwritingSizeEstimator` 文件头）
//  E9d `GlyphStrokeLayout.measure`：按某个宽度排出来占多大
//
//  ── 我之前把做法说得太粗，这里更正 ──
//  上一轮我描述成「先假定一个宽度 → 放不下就收窄重试」。那个说法有问题：
//  **收窄只会让文字块变高**，如果挡路的是下方的墨迹，收窄之后更放不下。
//  正确的形状是：每个候选位置**自带**它的可用宽度（从这个位置到页面右边距），
//  按那个宽度试排、看装不装得下，装不下就换下一个位置。宽度不是独立的旋钮。
//
//  ── 「隔多远」不是审美选择，是占用图逼出来的（第一版在这里写错了）──
//  第一版我给了一个 `gapInGlyphs = 0.3` 的参数，凭手感取值。结果是**右边和下方两个
//  位置几乎永远失败**，回应总是掉到扫描退路里。原因值得记下来：
//  同一条「别贴着写」的规则被写了两遍——这里的 gap 一遍，`PageInkMap.clearance` 一遍。
//  查询时占用图会把候选区域按 clearance 撑开，撑开量恰好把 gap 吃回去，
//  于是撑开后的边缘正好落在用户笔迹右端**所在的那个格子**里，判为占用。
//  所以间距必须**从占用图推出来**，而不是另取一个数：
//      gap = clearance + cellSize
//  clearance 是撑开量，cellSize 是格子量化的余量（笔迹右端所在那一整格都算占用，
//  最多向外多算一个 cellSize）。这个和就是「占用图真的会接受」的下界。
//  取下界而不是再放大：再大只会让回应离得莫名其妙的远。
//  同理，扫描步长就是 cellSize——占用图的答案在一个格子内部不会变化，扫得更细是白跑。
//
//  ── 候选位置的顺序 ──
//  1. 你那句话的**右边**（顶端与你的字对齐）
//  2. 你那句话的**下方**（左端与你的字对齐）
//  这两个都是「在你写的东西旁边」，谁更好并无定论，所以**顺序按种子随机**——
//  用户要的就是「随机空位」，固定优先级会让每次回应都落在同一个相对位置上，
//  一页写下来像表格。
//  3. 都放不下时，从页面顶部往下扫，找第一块放得下的整行宽度区域。
//     这一步不随机：它已经是退路，再随机只会让人更难预期。
//  4. 全都放不下 → 明确报 `noRoomOnThisPage`，那就是「该翻页了」（计划 E3f）的信号。
//
//  ── 为什么失败必须是显式的错误而不是「凑一个位置」──
//  找不到空位时硬塞一个位置，结果就是回应压在用户的字上。
//  报错让调用方必须处理（翻页），这正是「不静默兜底」。
//
//  ── 传进来的 `page` 应当已经是可书写区域 ──
//  也就是已经扣掉页边距的那块。这个文件不认识「页边距」这个概念，
//  它只会用到页面的右边缘来算可用宽度。谁建占用图，谁负责扣边距。
//

import CoreGraphics
import Foundation

/// 落点决策里**真正需要人来定**的两个数。
///
/// 其余的量（间距、扫描步长）都从占用图推出，不在这里出现——
/// 第一版把它们也做成参数，结果凭手感取的值与占用图的规则互相打架（见文件头）。
nonisolated struct ReplyPlacementConfiguration: Equatable, Sendable {
    /// 一行至少要能放下几个字。
    ///
    /// 比这更窄的位置不算候选：三四个字一行的中文读起来像竖排的窄条，
    /// 与其挤在那里，不如换个位置。
    let minimumLineWidthInGlyphs: Double

    /// 落点的随机抖动幅度，以字高为单位。
    ///
    /// 让回应不要每次都精确贴在同一个相对位置上——那样一页写下来像表格。
    /// 幅度刻意小：它是「不那么机械」，不是「随便放」。
    let jitterInGlyphs: Double

    init(minimumLineWidthInGlyphs: Double, jitterInGlyphs: Double) {
        precondition(minimumLineWidthInGlyphs > 0, "Minimum line width must be positive")
        precondition(jitterInGlyphs >= 0, "Jitter cannot be negative")
        self.minimumLineWidthInGlyphs = minimumLineWidthInGlyphs
        self.jitterInGlyphs = jitterInGlyphs
    }
}

/// 定下来的落点。
nonisolated struct ReplyPlacement: Equatable, Sendable {
    /// 这次落在哪一类位置上。留着它是为了能诊断「为什么回应跑到那儿去了」，
    /// 也为了将来评估哪种位置观感更好。
    nonisolated enum Slot: Equatable, Sendable {
        /// 在你那句话的右边。
        case rightOfWriting
        /// 在你那句话的下方。
        case belowWriting
        /// 前两个都放不下，从页面上扫出来的位置。
        case scanned
        /// 这一轮没有「你写的那句话」可以挨着（比如刚翻开一页就先收到回应），
        /// 于是从可书写区域的左上角写起。
        /// 注意它不代表「页面是空的」——页上可能还有更早的墨迹，
        /// 所以这一类之后仍然接扫描退路。
        case startOfPage
    }

    /// 文字块左上角在页面上的位置。可以直接当作排版的 origin。
    let origin: Point2D

    /// 排版时该用的行宽。
    let lineWidth: Double

    /// 实际占地（由试排量出来的真实墨迹范围）。
    let region: PageRegion

    let slot: Slot
}

/// 找不到落点的原因。**刻意不给一个「凑合的位置」**：
/// 硬塞一个位置的后果是回应压在用户的字上，而报错让调用方必须处理。
nonisolated enum ReplyPlacementFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// 这段文字一个字都排不出来（全是没有笔顺数据的字符）。
    case textProducesNoInk([Character])

    /// 这一页找不到放得下的空位——该翻页了（计划 E3f）。
    case noRoomOnThisPage

    var description: String {
        switch self {
        case .textProducesNoInk(let characters):
            "这段回应一个字都写不出来（缺笔顺数据：\(String(characters))）"
        case .noRoomOnThisPage:
            "这一页放不下这段回应了，需要翻页"
        }
    }
}

nonisolated struct ReplyPlacementFinder: Sendable {
    private let configuration: ReplyPlacementConfiguration
    private let layout: GlyphStrokeLayout

    init(
        configuration: ReplyPlacementConfiguration = InteractionSettings.replyPlacement,
        layout: GlyphStrokeLayout = GlyphStrokeLayout()
    ) {
        self.configuration = configuration
        self.layout = layout
    }

    /// 给这段回应找个位置。
    ///
    /// - Parameters:
    ///   - text: 回应文字。
    ///   - glyphSize: 字面方格边长（页面点）。
    ///   - lineSpacingRatio: 行距，字高的倍数。
    ///   - lastWriting: 用户刚写完那部分占的地方。nil 表示这一轮没有可挨着的字。
    ///   - inkMap: 页面占用图，已经标好所有已有墨迹。它的 `page` 应当是**已扣掉页边距**
    ///     的可书写区域。
    ///   - seed: 随机种子。同一种子必然得到同一结果，测试才能断言、出问题才能重放。
    /// - Throws: `ReplyPlacementFailure`。
    func place(
        _ text: String,
        glyphSize: Double,
        lineSpacingRatio: Double,
        after lastWriting: PageRegion?,
        on inkMap: PageInkMap,
        seed: UInt64
    ) throws -> ReplyPlacement {
        precondition(glyphSize > 0, "Glyph size must be positive")

        var random = SeededRandomNumberGenerator(seed: seed)
        let page = inkMap.page
        let minimumWidth = glyphSize * configuration.minimumLineWidthInGlyphs

        for candidate in candidateOrigins(
            lastWriting: lastWriting,
            inkMap: inkMap,
            random: &random
        ) {
            let jittered = jitter(candidate, glyphSize: glyphSize, random: &random)

            // 这个位置自带的可用宽度：从它的左边一直到可书写区域的右边缘。
            // 宽度不是独立的旋钮——它由位置决定（见文件头的更正）。
            let lineWidth = page.right - jittered.left
            guard lineWidth >= minimumWidth else { continue }

            let measured = try layout.measure(text, configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: glyphSize,
                lineWidth: lineWidth,
                lineSpacingRatio: lineSpacingRatio,
                origin: CGPoint(x: jittered.left, y: jittered.top)
            ))

            // 一个字都排不出来时不必再试别的位置：换位置也还是排不出来。
            // 报这个而不是 noRoomOnThisPage，因为处置完全不同——
            // 一个要补字形数据，一个要翻页。
            guard let region = measured.boundingBox else {
                throw ReplyPlacementFailure.textProducesNoInk(measured.uncoveredCharacters)
            }

            guard inkMap.canPlace(region) else { continue }

            return ReplyPlacement(
                origin: Point2D(x: jittered.left, y: jittered.top),
                lineWidth: lineWidth,
                region: region,
                slot: candidate.slot
            )
        }

        throw ReplyPlacementFailure.noRoomOnThisPage
    }

    // MARK: 候选位置

    private struct Candidate {
        let left: Double
        let top: Double
        let slot: ReplyPlacement.Slot
    }

    /// 候选位置与已有墨迹之间该隔多远。
    ///
    /// 从占用图推出，不是取一个手感值——理由见文件头那段「第一版在这里写错了」。
    private func gap(for inkMap: PageInkMap) -> Double {
        inkMap.resolution.clearance + inkMap.resolution.cellSize
    }

    /// 按尝试顺序给出候选位置。
    private func candidateOrigins(
        lastWriting: PageRegion?,
        inkMap: PageInkMap,
        random: inout SeededRandomNumberGenerator
    ) -> [Candidate] {
        let page = inkMap.page

        guard let lastWriting else {
            // 这一轮没有可挨着的字。从左上角写起，但后面仍然接扫描退路：
            // 「没有这一轮的字」不等于「页面是空的」，页上可能还有更早的墨迹。
            return [Candidate(left: page.left, top: page.top, slot: .startOfPage)]
                + scanned(inkMap: inkMap)
        }

        let gap = gap(for: inkMap)

        // 「右边」与「下方」都是「在你写的东西旁边」，谁更好并无定论，
        // 所以顺序按种子随机——固定优先级会让每次回应都落在同一个相对位置上，
        // 一页写下来像表格。
        var beside = [
            Candidate(left: lastWriting.right + gap, top: lastWriting.top, slot: .rightOfWriting),
            Candidate(left: lastWriting.left, top: lastWriting.bottom + gap, slot: .belowWriting),
        ]
        if random.unitInterval() < 0.5 {
            beside.reverse()
        }

        return beside + scanned(inkMap: inkMap)
    }

    /// 退路：从页面顶部往下扫，每一步都用整行宽度。
    ///
    /// 步长取占用图的格子大小：占用图的答案在一个格子内部不会变化，扫得更细是白跑；
    /// 更粗则可能跳过刚好放得下的位置。
    ///
    /// 这一步刻意**不随机**——它已经是退路，再随机只会让人更难预期回应会出现在哪。
    private func scanned(inkMap: PageInkMap) -> [Candidate] {
        let page = inkMap.page
        let step = inkMap.resolution.cellSize
        guard step > 0, page.height > 0 else { return [] }

        var candidates: [Candidate] = []
        var top = page.top
        while top < page.bottom {
            candidates.append(Candidate(left: page.left, top: top, slot: .scanned))
            top += step
        }
        return candidates
    }

    /// 给位置加一点随机抖动，让回应不要每次都精确贴在同一个相对位置上。
    ///
    /// 只往右、往下抖（都是正方向）：这两个方向都是「离已有墨迹更远」，
    /// 不会把刚算好的间距抖掉；往左往上则可能抖回墨迹里或越过页边距。
    private func jitter(
        _ candidate: Candidate,
        glyphSize: Double,
        random: inout SeededRandomNumberGenerator
    ) -> Candidate {
        let amplitude = glyphSize * configuration.jitterInGlyphs
        guard amplitude > 0 else { return candidate }

        return Candidate(
            left: candidate.left + random.unitInterval() * amplitude,
            top: candidate.top + random.unitInterval() * amplitude,
            slot: candidate.slot
        )
    }
}
