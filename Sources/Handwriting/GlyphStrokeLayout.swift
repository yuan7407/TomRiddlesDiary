//
//  GlyphStrokeLayout.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：把一段文字排成**页面坐标里的有序笔画**，直接可以喂给笔画引擎。
//
//  这是「模型返回的字符」到「引擎能逐笔画出来的东西」之间最后一段路。
//  输出的 `[Polyline]` 顺序就是书写顺序：第一个字的第一笔、第二笔……然后下一个字。
//
//  为什么不复用 `TextLayout`（那个基于 CoreText 的排版层）：
//  两者的字宽来源根本不同。`TextLayout` 用打包的手写体字体量字宽，而那个字体是
//  **比例字宽**（实测每 em 1000 单位下 我=858、的=631）；字形笔顺数据来自文鼎楷体，
//  是传统的**等宽字面方格**（每字占满一个 em）。若拿比例字宽去摆等宽字面的笔画，
//  字与字会互相压。等宽也正是中文传统排版的常态。
//  所以这里是一套独立的简单排版，而不是硬把两种字宽凑到一起。
//  代价是失去了 CoreText 的中文断行规则（标点不出现在行首等）——但当前数据集
//  本来就不含标点，等 E1c 补上标点笔画时再一并处理。
//
//  设计原因：
//  - 没有笔顺数据的字**如实报告**，不静默跳过。跳过会让页面上凭空少一个字，
//    而调用方完全不知道发生了什么。数据集只覆盖汉字，标点、拉丁字母、数字都缺
//    （属计划 E1c/E1d 要补的部分）。
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
}

nonisolated struct GlyphStrokeLayout: Sendable {
    private let provider: GlyphStrokeProvider

    init(provider: GlyphStrokeProvider = GlyphStrokeProvider()) {
        self.provider = provider
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
        // 一行放得下几个字。至少放一个，否则字比行宽还大时会死循环。
        let glyphsPerLine = max(1, Int(configuration.lineWidth / configuration.glyphSize))

        var polylines: [Polyline] = []
        var strokeCounts: [Int] = []
        var uncovered: [Character] = []
        var column = 0
        var line = 0

        for character in text {
            if character.isNewline {
                line += 1
                column = 0
                continue
            }
            if column >= glyphsPerLine {
                line += 1
                column = 0
            }

            do {
                let glyph = try provider.strokes(for: character)
                let originX = configuration.origin.x + Double(column) * configuration.glyphSize
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
            } catch GlyphStrokeLookupFailure.characterNotCovered {
                // 这个字画不出来。位置照样往前走，否则后面的字会挤上来，
                // 让「少了一个字」看起来像「排版错乱」。
                uncovered.append(character)
            }

            column += 1
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
