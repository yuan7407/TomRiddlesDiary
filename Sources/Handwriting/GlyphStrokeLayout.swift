//
//  GlyphStrokeLayout.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：把一段文字排成**页面坐标里的有序笔画**，直接可以喂给笔画引擎。
//
//  这是「模型返回的字符」到「引擎能逐笔画出来的东西」之间最后一段路。
//  输出的 `[Polyline]` 顺序就是书写顺序：第一个字的第一笔、第二笔……然后下一个字。
//
//  为什么这里自己排版，而不是用 CoreText（2026-09-01 补记）：
//  E8 阶段曾有一个基于 CoreText + 手写体字体的排版层（`TextLayout`），
//  它随 H9 一起删掉了（字体是轮廓、不含笔顺，给不出逐笔生长，本来就是脚手架）。
//  但当初「不复用它」的理由现在依然成立，也是这个文件存在的原因，所以留在这儿：
//  **字宽来源根本不同。** CoreText 拿字体量字宽，手写体字体是**比例字宽**
//  （实测每 em 1000 单位下 我=858、的=631）；而字形笔顺数据来自文鼎楷体，
//  是传统的**等宽字面方格**（每字占满一个 em）。拿比例字宽去摆等宽字面的笔画，
//  字与字会互相压。等宽也正是中文传统排版的常态。
//
//  字宽（2026-08-29，计划 E1c）：
//  「等宽」只对汉字与全角标点成立。西文标点天生窄得多——一个英文句点占三成宽，
//  若也占满一格，英文句子里会全是空洞。所以行内位置改用**游标**推进，
//  每个字按自己的 `advanceWidth` 往前走，不再是「第几列 × 字宽」。
//
//  已知缺口：中文断行规则还没有（标点不该出现在行首、不该把「」拆开）。
//  CoreText 会做这件事，但它的字宽模型与等宽字面方格不兼容，所以这里没有。
//  标点刚补上（E1c），这条缺口现在才真正暴露出来，需要单独处理。
//
//  设计原因：
//  - 没有笔顺数据的字**如实报告**，不静默跳过。跳过会让页面上凭空少一个字，
//    而调用方完全不知道发生了什么。目前汉字与标点已覆盖，
//    拉丁字母与数字仍缺（属计划 E1d）。
//  - 输出直接是 `[Polyline]` 而不是「每个字 + 它的笔画」：引擎要的就是一串有序笔画，
//    多包一层结构只会让调用方再拆一次。按字的信息用 `strokeCountsPerGlyph` 单独给出，
//    需要按字做节奏（例如每写完一个字稍作停顿）时够用。
//

import CoreGraphics
import Foundation

/// 笔画排版参数。长度单位一律是页面点。
nonisolated struct GlyphStrokeLayoutConfiguration: Equatable, Sendable {
    /// 字面方格的边长。汉字是方的，所以既是字高也是字宽（等宽排版）。
    let glyphSize: Double

    /// 可书写区域的宽度（已扣掉页边距）。
    let lineWidth: Double

    /// 行距，表达为字面方格边长的倍数。
    let lineSpacingRatio: Double

    /// 文字块左上角在页面中的位置。
    let origin: CGPoint
}

/// 排好版的笔画。
nonisolated struct LaidOutGlyphStrokes: Equatable, Sendable {
    /// 全部笔画，按书写顺序排列，坐标已在页面坐标系。可直接交给 `StrokePipeline`。
    let polylines: [Polyline]

    /// 每个**画得出来**的字各有几笔，顺序与书写顺序一致。
    /// 累加它就能把 `polylines` 切回按字分组。
    let strokeCountsPerGlyph: [Int]

    /// 没有笔顺数据、因此没有出现在 `polylines` 里的字。
    /// 非空意味着页面上会少东西，调用方必须处理而不是忽略。
    let uncoveredCharacters: [Character]

    let lineCount: Int
    let usedHeight: Double

    var isEmpty: Bool { polylines.isEmpty }

    /// 这段文字实际占了页面上哪一块（计划 E9d）。
    ///
    /// 为什么用**真实笔画**的包围盒而不是「行数 × 行高」：后者只是排版意图，
    /// 而笔画会伸出字面方格（下伸部、逗号的尾巴），实际占地比意图大一点。
    /// 找空位要按实际占地判断，否则算出来放得下、画出来压到字。
    ///
    /// 一个字都画不出来时为 nil：那种情况下「占了哪块」没有意义，
    /// 调用方必须单独处理（它同时意味着 `uncoveredCharacters` 非空）。
    var boundingBox: PageRegion? { PageRegion.covering(polylines) }
}

/// 试排结果：这段文字按给定宽度排出来会占多大（计划 E9d）。
nonisolated struct GlyphStrokeMeasurement: Equatable, Sendable {
    /// 实际占地。一个字都画不出来时为 nil。
    let boundingBox: PageRegion?

    let lineCount: Int

    /// 排版层按行数与行高算出的高度。它与 `boundingBox.height` 会略有差别
    /// （笔画伸出字面方格），两个都给出来，因为一个是意图、一个是事实。
    let usedHeight: Double

    /// 没有笔顺数据、排不出来的字。
    let uncoveredCharacters: [Character]
}

nonisolated struct GlyphStrokeLayout: Sendable {
    private let provider: GlyphStrokeProvider

    init(provider: GlyphStrokeProvider = GlyphStrokeProvider()) {
        self.provider = provider
    }

    /// 试排：这段文字按给定宽度排出来会占多大（计划 E9d）。
    ///
    /// ── 为什么需要「试排」这个概念 ──
    /// 「回应排在哪」是一个环：要知道占多大必须先排版；排版要知道每行多宽；
    /// 多宽取决于放进哪块空位；选哪块空位又取决于占多大。
    /// 解开它的办法是把顺序定死——先假定一个宽度、排出来看占多大、
    /// 拿这个尺寸去找空位、找不到就换更窄的宽度再试。所以排版必须能「只算不落地」。
    ///
    /// ── 为什么直接调 `layOut` 而不另写一套只算尺寸的快路径 ──
    /// 另写一套就意味着同一个「怎么换行、每个字多宽」的规则存在两份。
    /// 它们迟早会不一致，而不一致的症状是：试排说放得下，真排出来压到了字——
    /// 一个只在特定文字与特定宽度下才出现的偶发问题，极难定位。
    /// 宁可多算一遍，也不要两套算法算出不同答案。
    ///
    /// 代价是试排会白生成一遍笔画几何。回应通常只有一两句话、试排两三次，
    /// 这个代价可以接受；真成为瓶颈时再优化（属计划 B 性能优化），
    /// 届时的正确做法是把「换行与推进」抽成一条两边共用的路径，而不是复制一份。
    func measure(
        _ text: String,
        configuration: GlyphStrokeLayoutConfiguration
    ) throws -> GlyphStrokeMeasurement {
        let laidOut = try layOut(text, configuration: configuration)
        return GlyphStrokeMeasurement(
            boundingBox: laidOut.boundingBox,
            lineCount: laidOut.lineCount,
            usedHeight: laidOut.usedHeight,
            uncoveredCharacters: laidOut.uncoveredCharacters
        )
    }

    /// 把文字排成页面坐标里的有序笔画。
    /// - Throws: 仅当字形数据资源本身不可用时抛出。个别字缺笔顺数据不抛错，
    ///   而是记进 `uncoveredCharacters`——一个标点缺笔画不该让整页写不出来。
    func layOut(
        _ text: String,
        configuration: GlyphStrokeLayoutConfiguration
    ) throws -> LaidOutGlyphStrokes {
        // 先探一次资源是否可用。资源级故障要立刻抛出，不能退化成「所有字都没覆盖」——
        // 那会把故障伪装成「数据集不全」，让人查错方向。
        try probeResource()

        let lineHeight = configuration.glyphSize * configuration.lineSpacingRatio

        var polylines: [Polyline] = []
        var strokeCounts: [Int] = []
        var uncovered: [Character] = []
        // 行内游标，相对行首。改用游标而不是「第几列 × 字宽」，是因为字宽不再统一：
        // 汉字与全角标点占满一格，西文标点只占三成（计划 E1c 起）。
        var cursorX = 0.0
        var line = 0

        for character in text {
            if character.isNewline {
                line += 1
                cursorX = 0
                continue
            }

            // 只吞「这个字没覆盖」，资源级故障必须继续往上抛。
            // 用 `try?` 会把两者混成一个 nil，于是资源坏掉时表现为「所有字都没覆盖」，
            // 把故障伪装成数据集不全，查错方向完全跑偏。
            let glyph: GlyphStrokes?
            do {
                glyph = try provider.strokes(for: character)
            } catch GlyphStrokeLookupFailure.characterNotCovered {
                glyph = nil
            }

            // 画不出来的字也要占位，否则后面的字会挤上来，让「少了一个字」
            // 看起来像「排版错乱」。宽度未知时按一整格算——它最可能是个汉字。
            let advance = (glyph?.advanceWidth ?? 1) * configuration.glyphSize

            // 换行：放不下就换。`cursorX > 0` 这个条件是必需的——
            // 某个字比整行还宽时，没有它会一直换行、永远放不下，成死循环。
            if cursorX > 0, cursorX + advance > configuration.lineWidth {
                line += 1
                cursorX = 0
            }

            if let glyph {
                let originX = configuration.origin.x + cursorX
                let originY = configuration.origin.y + Double(line) * lineHeight

                for stroke in glyph.strokes {
                    polylines.append(place(
                        stroke,
                        atX: originX,
                        y: originY,
                        size: configuration.glyphSize
                    ))
                }
                strokeCounts.append(glyph.strokes.count)
            } else {
                uncovered.append(character)
            }

            cursorX += advance
        }

        return LaidOutGlyphStrokes(
            polylines: polylines,
            strokeCountsPerGlyph: strokeCounts,
            uncoveredCharacters: uncovered,
            lineCount: line + 1,
            usedHeight: Double(line + 1) * lineHeight
        )
    }

    /// 把归一化的一笔放到页面上的指定字面方格里。
    private func place(_ stroke: Polyline, atX x: Double, y: Double, size: Double) -> Polyline {
        Polyline(points: stroke.points.map { point in
            Point2D(x: x + point.x * size, y: y + point.y * size)
        })
    }

    /// 用一个必然存在的常用字探测资源是否可用。
    /// 选「一」是因为它是最简单的汉字（单横一笔），任何覆盖汉字的数据集都该有它。
    private func probeResource() throws {
        do {
            _ = try provider.strokes(for: "一")
        } catch GlyphStrokeLookupFailure.characterNotCovered {
            // 「一」都没有说明数据集不是我们以为的那份，同样属资源问题。
            throw GlyphStrokeLookupFailure.resourceUnavailable("数据集里连「一」都没有，资源内容不符合预期")
        }
    }
}
