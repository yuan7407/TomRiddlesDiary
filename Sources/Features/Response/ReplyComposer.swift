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

    init(
        placementFinder: ReplyPlacementFinder = ReplyPlacementFinder(),
        layout: GlyphStrokeLayout = GlyphStrokeLayout(),
        pipeline: StrokePipeline = StrokePipeline()
    ) {
        self.placementFinder = placementFinder
        self.layout = layout
        self.pipeline = pipeline
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
            seed: seed
        )

        return ComposedReply(
            sequence: sequence,
            placement: placement,
            uncoveredCharacters: laidOut.uncoveredCharacters
        )
    }
}
