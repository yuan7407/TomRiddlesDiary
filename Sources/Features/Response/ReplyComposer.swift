//
//  ReplyComposer.swift
//  模块：Features/Response（魂的回应；这里是把「一段文字」变成「纸上会长出来的笔画」的装配点）
//
//  文件职责：拿到魂说的一段文字，产出可以直接逐笔重播的笔画序列（计划 E6a）。
//
//  ── 为什么需要这个文件 ──
//  从「文字」到「纸上一笔一笔长出来的字」要走四步，而这四步**有严格顺序**：
//
//    ① 定落点（E9e）  → 得到「写在哪」和「这个位置能用多宽」
//    ② 排版（E1）     → 按那个宽度把文字排成有序笔画
//    ③ 手绘化（A 组） → 加手抖、压感、起收笔加减速、笔间抬笔移动
//    ④ 交给重播       → 逐笔生长
//
//  顺序不能反：**先排版再找位置**会得到一个宽度不合的文字块——排版时假定的行宽
//  和落点实际能给的宽度不一样，画出来就压字或者留一大片空白。
//
//  这四步以前散在 `DiaryPageView` 的 Xcode 预览里。Oracle 接上之后正式路径也要走同一条，
//  所以提成一个能单测的类型：预览里那份和 App 里那份如果是两套代码，
//  迟早出现「预览里好看、App 里错位」。
//
//  ── 为什么放在 Features 而不是 Handwriting ──
//  它是**装配**，不是算法：真正的判断都在 `ReplyPlacementFinder`、`GlyphStrokeLayout`、
//  `StrokePipeline` 里，这里只按正确顺序把它们串起来，并从 `Configuration` 取字号与行距。
//  Handwriting 那一层不该认识 `HandwritingFeel`（那是装配层的事），
//  也不该反过来依赖 StrokeEngine 的手绘化。
//
//  ── 字号目前不是量出来的 ──
//  用的是配置里的参考字高（9 mm）。E9c 的字号估算已经能跑，但实测偏 2–2.5 倍
//  （0.49 那个换算比例只对汉字成立），所以**刻意不接进来**——
//  接一个已知偏两倍的值，比用一个诚实的固定值更糟。见 `HandwritingSizeEstimator` 文件头。
//
//  ── 2026-11-11：装配顺序末尾多了一步「节奏」──
//  定落点 → 排版 → 手绘化（含整段 1.5 倍缩放）→ 节奏。节奏只改时间不改几何，所以放在最后；
//  默认不加（`cadence` 为 nil），App 在 `DiaryPageView` 构造模型时显式打开，现有测试不受影响。
//

import Foundation

/// 装配好的一段回应，可以直接交给 `DiaryPageModel.beginReply`。
nonisolated struct ComposedReply: Equatable, Sendable {
    /// 已手绘化的笔画序列，坐标在页面坐标系。
    let sequence: StrokeSequence

    /// 落在哪、用了多宽的行、实际占了多大。留着它是为了能诊断
    /// 「为什么这段回应跑到那儿去了」。
    let placement: ReplyPlacement

    /// 没有笔顺数据、因此纸上会少掉的字。
    ///
    /// 非空**必须让人知道**：页面上凭空少字而无人知晓，是最难查的一类问题。
    /// 这一层不替调用方决定怎么说，只如实带出来。
    let uncoveredCharacters: [Character]
}

nonisolated struct ReplyComposer: Sendable {
    private let placementFinder: ReplyPlacementFinder
    private let layout: GlyphStrokeLayout
    private let pipeline: StrokePipeline
    /// 说话的节奏（句读后的停顿、犹豫、最后一句放慢）。nil 表示不加，行为与加这一项之前完全相同。
    private let cadence: ReplyCadence?
    /// 楷书笔法（横轻竖重、撇出尖、捺有脚）。nil 表示不加，行为与加这一项之前完全相同。
    private let brush: BrushSettings?

    /// 笔法的两个旋钮。字高在装配时才知道，所以这里存的是比例。
    nonisolated struct BrushSettings: Equatable, Sendable {
        /// 0 完全不改，1 是 `BrushShaping` 里曲线的原样。
        let strength: Double
        /// 短于「这个比例 × 字高」的笔算作点。
        let dotLengthInGlyphHeights: Double
    }

    init(
        placementFinder: ReplyPlacementFinder = ReplyPlacementFinder(),
        layout: GlyphStrokeLayout = GlyphStrokeLayout(),
        pipeline: StrokePipeline = StrokePipeline(),
        cadence: ReplyCadence? = nil,
        brush: BrushSettings? = nil
    ) {
        self.placementFinder = placementFinder
        self.layout = layout
        self.pipeline = pipeline
        self.cadence = cadence
        self.brush = brush
    }

    /// 魂写字用的那一套：带节奏、带笔法。
    ///
    /// 为什么不直接改 `init` 的默认值：三百多条现有测试都用 `ReplyComposer()`，
    /// 它们守的是落点、排版与手感的基本行为，不该因为多了两层加工而全部改期望值。
    /// App 里把 `DiaryPageModel` 的默认装配点换成这个就行（一行，见 MERGE.md）。
    static func forSoul() -> ReplyComposer {
        // 落点决策（试排）和装配（真排）必须拿同一个排版器，换行规则才只有一份（决策 52）。
        let layout = GlyphStrokeLayout(rules: BookFeel.lineBreaking)
        return ReplyComposer(
            placementFinder: ReplyPlacementFinder(layout: layout),
            layout: layout,
            cadence: BookFeel.replyCadence,
            brush: BrushSettings(
                strength: BookFeel.brushStrength,
                dotLengthInGlyphHeights: BookFeel.brushDotLengthInGlyphHeights
            )
        )
    }

    /// 把一段文字装配成纸上会长出来的笔画。
    ///
    /// - Parameters:
    ///   - text: 魂说的话。
    ///   - glyphSize: 字面方格边长（页面点）。由调用方传入而不是这里读配置，
    ///     是为了让「这一次用多大的字」只有一个决定点——占用图也要用同一个值，
    ///     两处各自读配置迟早会不一致。
    ///   - lastWriting: 用户这一轮写的字占了哪块。nil 表示没有可挨着的。
    ///   - inkMap: 页面占用图，必须已经标好用户笔画与魂之前写下的回应。
    ///   - seed: 随机种子。同一种子必得同一结果（落点与手抖都可复现）。
    /// - Throws: `ReplyPlacementFailure`（放不下 / 一个字都排不出来）。
    ///   两者都不静默处理：放不下要翻页（E3f），排不出来要补字形数据。
    func compose(
        _ text: String,
        glyphSize: Double,
        lineSpacingRatio: Double,
        after lastWriting: PageRegion?,
        on inkMap: PageInkMap,
        seed: UInt64
    ) throws -> ComposedReply {
        // ① 先定落点，因为它决定了这一段能用多宽的行。
        let placement = try placementFinder.place(
            text,
            glyphSize: glyphSize,
            lineSpacingRatio: lineSpacingRatio,
            after: lastWriting,
            on: inkMap,
            seed: seed
        )

        // ② 按落点给的行宽真排一遍。
        //    `ReplyPlacementFinder` 内部已经用同样的参数试排过（`measure`），
        //    所以这里排出来的结果必然和 `placement.region` 一致——那条一致性
        //    由 `ReplyPlacementTests` 的端到端用例守着。
        let laidOut = try layout.layOut(text, configuration: GlyphStrokeLayoutConfiguration(
            glyphSize: glyphSize,
            lineWidth: placement.lineWidth,
            lineSpacingRatio: lineSpacingRatio,
            origin: CGPoint(x: placement.origin.x, y: placement.origin.y)
        ))

        // ③ 手绘化。参考尺度传当前字号，因为所有手感量都是「字高的比例」（决策 25）：
        //    字写得小，手抖幅度也该跟着小。
        let sequence = pipeline.process(
            laidOut.polylines,
            configuration: HandwritingFeel.humanizerConfiguration(referenceScale: glyphSize),
            seed: seed,
            // 魂写字比真人快（用户拍板 1.5 倍）。整体缩放而不是调书写速度，
            // 理由见 `HandwritingFeel.soulWritesFasterThanHumanBy`。
            timeScale: HandwritingFeel.soulWritesFasterThanHumanBy
        )

        // 笔法：只改粗细，不动形状和时间，所以放在手绘化之后、节奏之前都一样；
        // 放在这里是因为它和手绘化同属「怎么写」。拉丁字母、数字和标点不是楷书，原样不动。
        let glyphs = Self.laidOutGlyphs(of: text, uncovered: laidOut.uncoveredCharacters)
        let shaped = brush.map { brush in
            BrushShaping.shaped(
                sequence,
                configuration: BrushShapingConfiguration(
                    strength: brush.strength,
                    dotLength: glyphSize * brush.dotLengthInGlyphHeights,
                    lightestWidthRatio: HandwritingFeel.inkWidthAtLightestPressureRatio
                ),
                plainStrokes: Self.plainStrokeIndices(
                    glyphs: glyphs,
                    strokeCountsPerGlyph: laidOut.strokeCountsPerGlyph
                )
            )
        } ?? sequence

        // 节奏排在最后：它要的是「整段缩放之后」的时间（决策 77 的 1.5 倍已经在 pipeline 里做完），
        // 停顿表达的是他在斟酌，不跟着书写速度一起变快。
        let paced = cadence.map { cadence in
            cadence.apply(
                to: shaped,
                glyphs: glyphs,
                strokeCountsPerGlyph: laidOut.strokeCountsPerGlyph,
                seed: seed
            )
        } ?? shaped

        return ComposedReply(
            sequence: paced,
            placement: placement,
            uncoveredCharacters: laidOut.uncoveredCharacters
        )
    }

    /// 排版时真的排出来了的那些字，按顺序。
    ///
    /// `GlyphStrokeLayout.layOut` 的 `strokeCountsPerGlyph` 只给「排出来的字」记笔数：
    /// 换行不算字，字形数据里没有的字被记进 `uncoveredCharacters` 而不记笔数。
    /// 这里按同样的规则把原文筛一遍，两边才能一一对应。
    /// 缺的字按它在原文里出现的先后逐个扣除（同一个缺字出现两次就扣两次）。
    static func laidOutGlyphs(of text: String, uncovered: [Character]) -> [Character] {
        var missing = uncovered[...]
        var glyphs: [Character] = []
        for character in text where !character.isNewline {
            if let next = missing.first, next == character {
                missing = missing.dropFirst()
            } else {
                glyphs.append(character)
            }
        }
        return glyphs
    }

    /// 不该加楷书笔法的那些笔（按笔画下标）：拉丁字母、数字、标点的笔画。
    ///
    /// 判据是「这个字是不是汉字」，用 Unicode 的表意文字属性判断，而不是列一张标点表：
    /// 列表会漏（全角、半角、将来新补的字形），漏掉的后果是英文字母被画上撇捺的粗细。
    /// 数量对不上时返回空集——宁可全部按汉字处理，也不把笔法错位地安到别的字上。
    static func plainStrokeIndices(glyphs: [Character], strokeCountsPerGlyph: [Int]) -> Set<Int> {
        guard glyphs.count == strokeCountsPerGlyph.count else { return [] }
        var plain: Set<Int> = []
        var index = 0
        for (glyph, count) in zip(glyphs, strokeCountsPerGlyph) {
            let isHan = glyph.unicodeScalars.contains { $0.properties.isIdeographic }
            if !isHan { plain.formUnion(index ..< index + count) }
            index += count
        }
        return plain
    }
}
