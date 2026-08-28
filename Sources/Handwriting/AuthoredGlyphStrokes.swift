//
//  AuthoredGlyphStrokes.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：把所有**手写定义**的字形合成一张表，作为汉字数据文件之外的第二个来源。
//
//  为什么要这一层而不是让 provider 直接查两张表：
//  手写定义的字形已经分成两批（标点 E1c、拉丁字母与数字 E1d），将来还可能有第三批
//  （希腊字母？箭头？）。让 provider 逐个 if 下去，每加一批就要改 provider，
//  而 provider 的职责是「查一个字怎么写」，不是「记住有几批手写数据」。
//  这一层把「有哪些手写来源」收在一处，provider 只认一个入口。
//
//  为什么分成多个文件而不是一个大表：
//  标点和字母的组织方式不同——标点讲全角半角与位置约定，字母讲基准线与字宽。
//  放在一个文件里两套说明会互相干扰，人工复核时也很难只看其中一批。
//
//  重复字符**直接崩**而不是静默取其一：
//  同一个字符在两批里各定义一次，说明有人重复劳动或者拆分边界错了。
//  静默取其一的后果是某个符号莫名换了形状或宽度，在页面上极难定位。
//

import Foundation

nonisolated enum AuthoredGlyphStrokes {
    /// 全部手写定义的字形。
    static let table: [Character: PenStrokeGlyph] = PunctuationStrokes.table
        .merging(LatinStrokes.table) { _, _ in
            preconditionFailure("标点表与拉丁字母表出现了重复字符")
        }
        .merging(whitespace) { _, _ in
            preconditionFailure("空白字符与其他手写字形出现了重复")
        }

    static func glyph(for character: Character) -> PenStrokeGlyph? {
        table[character]
    }

    /// 空白：**有宽度、没有墨迹**的字形（2026-08-29 被测试撞出来的缺口）。
    ///
    /// 为什么必须在这里定义，而不是让它落到「查不到」那条路：
    /// 空格不是缺字。若把它报成「缺笔顺数据」，界面就会告诉用户「这一页少了字符」，
    /// 而实际上什么都没少——一句 "Take your time." 会因为两个空格被当成两处缺失。
    /// 假警报和静默失败一样坏：它会让人去查一个不存在的问题，
    /// 也会让真正的缺字（生僻汉字）淹没在噪声里。
    ///
    /// 用「零笔画的字形」表达而不是在排版层特判：这样排版层不需要知道空白的存在，
    /// 它照常查字、照常按 `advanceWidth` 推进游标，只是这个字形没有笔可画。
    ///
    /// 宽度取值：西文词距通常约为字面方格的三分之一，取 0.30；
    /// 全角空格（U+3000）按定义占满一格。
    private static let whitespace: [Character: PenStrokeGlyph] = [
        " ": PenStrokeGlyph(moves: [], advanceWidth: 0.30),
        "\u{3000}": PenStrokeGlyph(moves: [], advanceWidth: 1),
    ]
}
