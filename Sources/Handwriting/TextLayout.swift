//
//  TextLayout.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：把一段文字排到纸上——算出每个字落在页面的哪个位置、多大。
//
//  设计原因：
//  - **为什么用 CoreText 而不是自己按格子排**：这个字体的字宽是不等宽的，
//    实测拉丁字母 A=490、a=314、i=239，汉字 我=858、的=631（每 em 1000 单位）。
//    也就是说连汉字都不是满格宽。按固定格子排会挤在一起或散开。
//    而且中文换行有真实规则（标点不能出现在行首、行末不能吊单个标点、
//    中英混排要插入间隙），自己写必然漏。CoreText 是系统的文字排版引擎，
//    这些都由它处理。
//  - CoreText 属文字排版，不是 UI 框架，放在纯逻辑层不破坏模块边界。
//  - **输出是「每个字 + 它的位置」而不是一整块可绘制的文本**：因为回应要一个字
//    一个字地出现，渲染层必须能单独控制每个字；而计划 E1 换成字形笔顺数据时，
//    也正好按同样的位置去画笔画，排版层不必重写。
//  - 字体只用来提供字宽与换行依据。E1 用笔画数据画字时仍可复用同一份排版结果，
//    这样从字体版切到笔画版，字的位置不会变。
//

import CoreGraphics
import CoreText
import Foundation

/// 一个已经定好位置的字。
nonisolated struct PositionedGlyph: Equatable, Sendable {
    /// 这个位置上的字符。E8 用字体画它，E1 会用它去查字形笔画。
    let character: Character

    /// 字在页面坐标系中的位置。以**左上角**为原点、y 向下，
    /// 与 SwiftUI 和 PencilKit 的坐标方向一致，渲染层不需要再翻转。
    let origin: CGPoint

    /// 这个字的排版宽度（页面点）。
    let advance: Double

    /// 这个字所在行的序号，从 0 开始。用于按行做节奏（例如换行时稍作停顿）。
    let lineIndex: Int
}

/// 排版结果。
nonisolated struct LaidOutText: Equatable, Sendable {
    let glyphs: [PositionedGlyph]

    /// 实际占用的高度（页面点）。调用方据此判断这一页放不放得下。
    let usedHeight: Double

    /// 行数。
    let lineCount: Int

    /// 字体的上伸高度（页面点）：基线到字形包围盒顶部的距离。
    ///
    /// 为什么由排版层给出：渲染层若想按「包围盒左上角」定位一个字，就得知道
    /// 基线到顶部有多远，而这个值来自字体度量。字体度量只有排版层手里有
    /// （它持有 CTFont），让渲染层自己去取会把字体知识漏进渲染层。
    /// 渲染层用 `glyph.origin.y - ascent` 即可得到包围盒左上角。
    let ascent: Double

    var isEmpty: Bool { glyphs.isEmpty }
}

/// 排版参数。全部长度单位是页面点。
nonisolated struct TextLayoutConfiguration: Equatable, Sendable {
    /// 一个字的高度，也是排版用的字号基准。
    let glyphHeight: Double

    /// 可书写区域的宽度（已扣掉页边距）。
    let lineWidth: Double

    /// 行距，表达为字高的倍数。1.0 表示行与行紧贴，手写通常需要更松。
    let lineSpacingRatio: Double

    /// 文字块左上角在页面中的位置。
    let origin: CGPoint
}

nonisolated struct TextLayout: Sendable {
    /// 把文字排成带位置的字序列。
    /// - Returns: 排版结果。空字符串返回空结果，不视为错误。
    /// - Throws: 字体未能注册时抛出——排版必须用手写体，回落到系统字体会让
    ///   整段回应变成印刷体，属于伪装成功。
    func layOut(_ text: String, configuration: TextLayoutConfiguration) throws -> LaidOutText {
        try HandwritingFont.register()

        let trimmed = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !trimmed.isEmpty else {
            return LaidOutText(glyphs: [], usedHeight: 0, lineCount: 0, ascent: 0)
        }

        let font = CTFontCreateWithName(
            HandwritingFont.familyName as CFString,
            configuration.glyphHeight,
            nil
        )
        let attributed = NSAttributedString(
            string: trimmed,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )

        // CTTypesetter 逐行断行。用它而不是 CTFramesetter，是因为我们要自己控制
        // 行距与起始位置，而 CTFramesetter 会把这些一并接管。
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let lineHeight = configuration.glyphHeight * configuration.lineSpacingRatio

        var glyphs: [PositionedGlyph] = []
        var lineIndex = 0
        var characterIndex = 0
        let totalLength = attributed.length
        let nsText = trimmed as NSString

        while characterIndex < totalLength {
            // 遇到显式换行：断在这里，跳过换行符本身。
            let explicitBreak = nsText.range(
                of: "\n",
                options: [],
                range: NSRange(location: characterIndex, length: totalLength - characterIndex)
            )
            let searchLimit = explicitBreak.location == NSNotFound ? totalLength : explicitBreak.location

            if searchLimit == characterIndex {
                // 空行：只推进行号，不产出字。
                characterIndex += 1
                lineIndex += 1
                continue
            }

            let breakCount = CTTypesetterSuggestLineBreak(
                typesetter,
                characterIndex,
                configuration.lineWidth
            )
            // 断行长度不得超过本段剩余部分，也不得为 0（否则死循环）。
            let lineLength = max(1, min(breakCount, searchLimit - characterIndex))
            let lineRange = CFRange(location: characterIndex, length: lineLength)
            let line = CTTypesetterCreateLine(typesetter, lineRange)

            let baselineY = configuration.origin.y + Double(lineIndex) * lineHeight + configuration.glyphHeight
            appendGlyphs(
                from: line,
                text: nsText,
                lineStart: characterIndex,
                lineIndex: lineIndex,
                originX: configuration.origin.x,
                baselineY: baselineY,
                into: &glyphs
            )

            characterIndex += lineLength
            // 吃掉紧跟其后的换行符，避免它自己占一行。
            if characterIndex < totalLength, nsText.character(at: characterIndex) == 0x0A {
                characterIndex += 1
            }
            lineIndex += 1
        }

        return LaidOutText(
            glyphs: glyphs,
            usedHeight: Double(max(lineIndex, 1)) * lineHeight,
            lineCount: max(lineIndex, 1),
            ascent: CTFontGetAscent(font)
        )
    }

    /// 从一行里取出每个字的位置。
    /// CTLine 由若干 CTRun 组成，每个 run 内的字形位置由 CoreText 给出，
    /// 已包含字距调整与中英混排的间隙。
    private func appendGlyphs(
        from line: CTLine,
        text: NSString,
        lineStart: Int,
        lineIndex: Int,
        originX: Double,
        baselineY: Double,
        into glyphs: inout [PositionedGlyph]
    ) {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return }

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            var indices = [CFIndex](repeating: 0, count: glyphCount)
            let all = CFRange(location: 0, length: glyphCount)
            CTRunGetPositions(run, all, &positions)
            CTRunGetAdvances(run, all, &advances)
            CTRunGetStringIndices(run, all, &indices)

            for slot in 0 ..< glyphCount {
                let stringIndex = indices[slot]
                guard stringIndex >= 0, stringIndex < text.length else { continue }

                // 用 rangeOfComposedCharacterSequence 取完整字符，
                // 否则 emoji、带声调的拉丁字母等由多个 UTF-16 单元组成的字会被切断。
                let composed = text.rangeOfComposedCharacterSequence(at: stringIndex)
                // 只在字符的首个单元产出，避免同一个字被多个字形重复登记。
                guard composed.location == stringIndex else { continue }

                let substring = text.substring(with: composed)
                guard let character = substring.first, !character.isNewline else { continue }

                glyphs.append(PositionedGlyph(
                    character: character,
                    origin: CGPoint(
                        x: originX + positions[slot].x,
                        y: baselineY
                    ),
                    advance: advances[slot].width,
                    lineIndex: lineIndex
                ))
            }
        }
    }
}
