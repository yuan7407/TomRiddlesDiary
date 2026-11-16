//
//  LineBreaking.swift
//  模块：Handwriting（纯逻辑层；只依赖 Foundation）
//
//  文件职责：决定一段话在哪里换行。只回答「第几个字到第几个字是一行」，不碰坐标和笔画。
//  `GlyphStrokeLayout.layOut` 是唯一的调用方（试排 `measure` 直接复用 `layOut`，决策 52），
//  所以全工程的换行规则只有这一份。
//
//  解决的是 MEMORY 风险表里「中文断行规则仍然没有」那一条（计划 E2a）：
//  句号会落到行首、「会被留在行尾、stakeholder 会被拆成两截。
//
//  规则（前三条永远生效，第四条可以关）：
//  1. 行首禁则：句读和收尾的引号括号不出现在行首。
//  2. 行尾禁则：开头的引号括号不留在行尾。
//  3. 英文单词和数字不拆开。只有当一个词比整行还宽时才硬拆——否则会永远排不下去。
//  4. 按意思换行：一句或半句说完、这一行也排了一多半，就在这里换行，不非要顶到纸边。
//     这是「对开」设计里让回应读起来像一张字条而不是一块方阵的关键；
//     它会让文字块变高，所以默认关，只在魂的回应里打开（见 `BookFeel.lineBreaking`）。
//
//  禁则是怎么实现的——「粘」而不是「悬」：
//  常见的做法有两种。一种是让标点悬在行尾外面（悬挂），一种是把它前面的字一起带到下一行。
//  这里用后一种：收尾的标点粘在前一个字上，开头的引号粘在后一个字上，粘好的一组整体换行。
//  不用悬挂的原因是落点决策：`ReplyPlacementFinder` 给每个位置的行宽是「到可写区域右边缘为止」，
//  悬出去的标点会越过那条边，要么压到页边距，要么被占用图判成放不下。
//  「粘」的结果永远在声明的行宽之内，`ReplyPlacementTests` 里那条「排出来的块不超过行宽」不用改。
//
//  禁则字符集的来源：W3C《中文排版需求》（Requirements for Chinese Text Layout）的
//  行首行尾禁则一节，加上对应的西文标点。它和 `InteractionSettings` 里两份标点表的关系：
//  `sentenceEndingMarks`（句末标点）与 `closingMarks`（收尾的引号括号）都**是**行首禁则的一部分，
//  所以这里直接引用它们，不再抄一遍；行首禁则另外还包括逗号、顿号、分号、冒号这些句中标点，
//  那些不是「一句话说完了」的信号，成页触发用不上，所以原来的两张表里没有。
//
//  单位：宽度一律是页面点，和 `GlyphStrokeLayout` 用同一种累加方式。
//  特意不换算成「几个字宽」再比较：换算多一次除法，行宽恰好是整数个字时会因为浮点尾数多换或少换一行。
//

import Foundation

/// 换行规则数据。
nonisolated struct LineBreakRules: Equatable, Sendable {
    /// 不许出现在行首的字符。
    var notAtLineStart: Set<Character>
    /// 不许留在行尾的字符。
    var notAtLineEnd: Set<Character>
    /// 一句或半句说完的标点。「按意思换行」只在它们后面断。
    var clauseEnding: Set<Character>
    /// 这一行排到行宽的这个比例以上、又刚好说完一句，就换行。nil 表示不按意思换行。
    var phraseBreakFill: Double?
    /// 后面剩下的字不足这么多个字宽时，不为它们另起一行（否则最后一行只有一两个字）。
    var minimumRemainderInGlyphs: Double

    /// 只做禁则与不拆词，不按意思换行。排版层的默认值。
    static let standard = LineBreakRules(
        notAtLineStart: InteractionSettings.sentenceEndingMarks
            .union(InteractionSettings.closingMarks)
            .union(["，", "、", "；", "：", ",", ";", ":", "—", "～", "·", "%", "％"]),
        notAtLineEnd: ["「", "『", "“", "‘", "（", "(", "《", "〈", "【", "[", "{"],
        clauseEnding: InteractionSettings.sentenceEndingMarks.union(["，", "；", ",", ";"]),
        phraseBreakFill: nil,
        minimumRemainderInGlyphs: 2.2
    )
}

/// 一行里的一片：一个字，和它在行内占多宽。
nonisolated struct LinePiece: Equatable, Sendable {
    let character: Character
    /// 这个字往前推进多少（页面点）。
    let advance: Double
}

nonisolated enum LineBreaker {
    /// 把一串字分成行。返回每一行里各片在 `pieces` 中的下标。
    ///
    /// 换行符本身不出现在结果里；连续两个换行符之间是一个空行（空数组），行数照算。
    /// 结果至少有一行。
    static func lines(
        of pieces: [LinePiece],
        lineWidth: Double,
        glyphSize: Double,
        rules: LineBreakRules
    ) -> [[Int]] {
        var result: [[Int]] = []
        var paragraph: [Int] = []
        for (index, piece) in pieces.enumerated() {
            if piece.character.isNewline {
                result.append(contentsOf: breakParagraph(paragraph, pieces: pieces, lineWidth: lineWidth, glyphSize: glyphSize, rules: rules))
                paragraph = []
            } else {
                paragraph.append(index)
            }
        }
        result.append(contentsOf: breakParagraph(paragraph, pieces: pieces, lineWidth: lineWidth, glyphSize: glyphSize, rules: rules))
        return result
    }

    /// 没有换行符的一段。空段返回一个空行。
    private static func breakParagraph(
        _ indices: [Int],
        pieces: [LinePiece],
        lineWidth: Double,
        glyphSize: Double,
        rules: LineBreakRules
    ) -> [[Int]] {
        guard !indices.isEmpty else { return [[]] }

        // ① 把不能拆开的字粘成一组。
        var units: [[Int]] = []
        for index in indices {
            let character = pieces[index].character
            if let tail = units.last?.last {
                let previous = pieces[tail].character
                let sameWord = isWordCharacter(character) && isWordCharacter(previous)
                if sameWord || rules.notAtLineStart.contains(character) || rules.notAtLineEnd.contains(previous) {
                    units[units.count - 1].append(index)
                    continue
                }
            }
            units.append([index])
        }

        // ② 一组一组往行里放。
        var lines: [[Int]] = []
        var line: [Int] = []
        var cursor = 0.0
        var remaining = indices.reduce(0.0) { $0 + pieces[$1].advance }
        func isLoneSpace(_ unit: [Int]) -> Bool {
            unit.count == 1 && pieces[unit[0]].character.isWhitespace
        }

        for unit in units {
            let width = unit.reduce(0.0) { $0 + pieces[$1].advance }
            remaining -= width

            if cursor > 0, cursor + width > lineWidth {
                lines.append(line)
                line = []
                cursor = 0
            }
            // 因为放不下才另起的一行，行首的空格不占位置。段首的空格是原文的一部分，留着。
            if cursor == 0, !lines.isEmpty, isLoneSpace(unit) { continue }

            if width > lineWidth {
                // 比整行还宽的一组（很长的英文单词）：只能硬拆，一个字一个字放。
                for index in unit {
                    let advance = pieces[index].advance
                    if cursor > 0, cursor + advance > lineWidth {
                        lines.append(line)
                        line = []
                        cursor = 0
                    }
                    line.append(index)
                    cursor += advance
                }
            } else {
                line.append(contentsOf: unit)
                cursor += width
            }

            // ③ 按意思换行。
            //    句号后面跟着收尾引号（。」）时，要看的是引号前面那个标点。
            if let fill = rules.phraseBreakFill,
               let last = unit.last(where: { !InteractionSettings.closingMarks.contains(pieces[$0].character) }),
               rules.clauseEnding.contains(pieces[last].character),
               cursor >= fill * lineWidth,
               remaining > rules.minimumRemainderInGlyphs * glyphSize {
                lines.append(line)
                line = []
                cursor = 0
            }
        }
        if !line.isEmpty || lines.isEmpty { lines.append(line) }
        return lines
    }

    /// 英文单词和数字里的字符：拉丁字母、数字、撇号、连字符。
    private static func isWordCharacter(_ character: Character) -> Bool {
        if character == "'" || character == "’" || character == "-" { return true }
        return character.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || ("0" ... "9").contains(Character(scalar)))
        }
    }
}
