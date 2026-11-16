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
//  断行规则（2026-11-12，计划 E2a）：
//  在哪里换行由 `LineBreaker` 决定（行首行尾禁则、英文单词不拆、可选的按意思换行），
//  这里只负责把它分好的每一行摆到坐标上。规则和理由都在 `LineBreaking.swift`。
//  `measure` 仍然直接调 `layOut`（决策 52），所以试排和真排用的必然是同一套换行。
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
    /// 换行规则。试排与真排必须用同一个 `GlyphStrokeLayout`，这样规则才只有一份。
    private let rules: LineBreakRules

    init(provider: GlyphStrokeProvider = GlyphStrokeProvider(), rules: LineBreakRules = .standard) {
        self.provider = provider
        self.rules = rules
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

        // ① 先查出每个字的字形和它占多宽。查不到的字照样占一个字宽（留出空位），并记进 uncovered。
        var glyphs: [GlyphStrokes?] = []
        var pieces: [LinePiece] = []
        for character in text {
            if character.isNewline {
                glyphs.append(nil)
                pieces.append(LinePiece(character: character, advance: 0))
                continue
            }
            let glyph: GlyphStrokes?
            do {
                glyph = try provider.strokes(for: character)
            } catch GlyphStrokeLookupFailure.characterNotCovered {
                // 单个字缺失不让整段失败：其余的字照常排，缺的字如实记下来。
                glyph = nil
            }
            glyphs.append(glyph)
            pieces.append(LinePiece(
                character: character,
                advance: (glyph?.advanceWidth ?? 1) * configuration.glyphSize
            ))
        }

        // ② 分行。规则只有 `LineBreaker` 这一份。
        let lines = LineBreaker.lines(
            of: pieces,
            lineWidth: configuration.lineWidth,
            glyphSize: configuration.glyphSize,
            rules: rules
        )

        // ③ 把每一行摆到坐标上。行内用游标推进，每个字按自己的宽度往前走。
        var polylines: [Polyline] = []
        var strokeCounts: [Int] = []
        var uncovered: [Character] = []
        for (line, indices) in lines.enumerated() {
            var cursorX = 0.0
            let originY = configuration.origin.y + Double(line) * lineHeight
            for index in indices {
                if let glyph = glyphs[index] {
                    let originX = configuration.origin.x + cursorX
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
                    uncovered.append(pieces[index].character)
                }
                cursorX += pieces[index].advance
            }
        }
        let lineCount = lines.count

        return LaidOutGlyphStrokes(
            polylines: polylines,
            strokeCountsPerGlyph: strokeCounts,
            uncoveredCharacters: uncovered,
            lineCount: lineCount,
            usedHeight: Double(lineCount) * lineHeight
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
