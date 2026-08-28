//
//  PunctuationStrokes.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：手写定义标点符号的笔顺（计划 E1c）。
//
//  为什么要自己写：
//  汉字笔顺来自 makemeahanzi 数据集，而那份数据**只覆盖汉字**——标点一个都没有。
//  没有标点，魂写不出一个完整的句子：「今天很累」和「今天很累。」差的就是这一个字符，
//  而在此之前它会被如实报成「缺笔顺数据」然后跳过。
//
//  为什么标点值得单独一个文件：
//  它们数量少（下面这些就够写日记了）、形状固定、而且是**手写数据没有上游可对照**。
//  放在一起才能一眼看完、一眼核对。拉丁字母与数字（计划 E1d）会用同一套词汇，
//  但那是 62 个字形、还牵扯字宽与基线，属另一件事，不塞进这里。
//
//  ── 位置约定 ──
//  中日韩标点是**全角**的：占满一个字面方格，而符号本身只画在左下角一小块区域，
//  右上方大片留白——这就是中文里句号后面看起来有空隙的原因，是排版规范不是 bug。
//  西文标点是**比例宽**的：句点只占三成宽，所以必须给出各自的 `advanceWidth`，
//  否则一个英文句号会占掉一整个汉字的位置。
//
//  ── 这批数据的可信度（诚实说明）──
//  形状由我按印刷体标点的常见样子写出，**没有权威字形数据可以比对**。
//  已经用 `PunctuationStrokesTests` 守住了可机器验证的部分（笔数、落在字宽内、
//  笔画不退化成一个点等），但「看起来像不像那个标点」只能靠眼看。
//  `Tests/GlyphPreviewDump.swift` 会把每个符号渲染成字符画写到文件里，就是为此。
//  其中最没把握的一处已在下面单独标注（顿号的倾斜方向）。
//

import Foundation

nonisolated enum PunctuationStrokes {
    // MARK: 位置基准（写成有名字的量，而不是散落的数字）

    /// 全角标点符号本体的中心。中日韩标点画在字面方格的左下角。
    private static let fullwidthMarkCenter = Point2D(x: 0.3, y: 0.68)

    /// 全角句号那个小圈的半径。
    private static let fullwidthCircleRadius: Double = 0.13

    /// 西文基线的高度。字母的下沿落在这里，句点也画在它附近。
    private static let latinBaseline: Double = 0.76

    /// 西文大写字母顶部的高度。感叹号、问号的竖笔从这里起。
    private static let latinCapTop: Double = 0.18

    /// 西文标点里「点」与「上半部分」之间的垂直间隔（冒号、分号用）。
    private static let latinDotGap: Double = 0.28

    // MARK: 查表

    /// 所有已定义的标点。
    static let table: [Character: PenStrokeGlyph] = fullwidthMarks.merging(latinMarks) { fullwidth, _ in
        // 两张表不该有重叠的字符：全角与半角的码点不同。
        // 真撞上了保留全角那份并在这里崩掉，而不是静默取其中一个——
        // 静默的话某个符号会莫名变成另一种宽度，极难查。
        preconditionFailure("全角与西文标点表出现了重复字符：\(fullwidth)")
    }

    static func glyph(for character: Character) -> PenStrokeGlyph? {
        table[character]
    }

    // MARK: 全角（中日韩）标点

    private static let fullwidthMarks: [Character: PenStrokeGlyph] = [
        // 。句号：一个小圈。整圆，起笔在右侧顺时针画一整周。
        "。": PenStrokeGlyph(
            moves: [.arc(
                center: fullwidthMarkCenter,
                radius: fullwidthCircleRadius,
                from: 0,
                to: 2 * .pi
            )],
            advanceWidth: 1
        ),

        // ，逗号：从中部起笔，向下再往左下勾出去。
        "，": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.36, y: 0.54),
                Point2D(x: 0.34, y: 0.68),
                Point2D(x: 0.22, y: 0.84),
            ])],
            advanceWidth: 1
        ),

        // 、顿号：一短撇状的点。
        //
        // **这是这批数据里我最没把握的一处。** 顿号在手写里就是一个「点」笔画，
        // 而点笔画的走向在不同字体与不同书写习惯下并不一致（有从左上往右下的，
        // 也有反过来的）。这里取「左上起笔、往右下收」，因为它与楷体点笔画一致，
        // 而字形笔顺数据本身就是楷体。若渲染出来看着不对，改这两个坐标即可，
        // 不牵动任何别的东西。
        "、": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.22, y: 0.54),
                Point2D(x: 0.30, y: 0.66),
                Point2D(x: 0.40, y: 0.80),
            ])],
            advanceWidth: 1
        ),

        // ：冒号：上下两点。
        "：": PenStrokeGlyph(
            moves: [
                .dot(Point2D(x: 0.3, y: 0.44)),
                .dot(Point2D(x: 0.3, y: 0.72)),
            ],
            advanceWidth: 1
        ),

        // ；分号：上面一点，下面一个逗号。
        "；": PenStrokeGlyph(
            moves: [
                .dot(Point2D(x: 0.3, y: 0.44)),
                .through([
                    Point2D(x: 0.34, y: 0.64),
                    Point2D(x: 0.32, y: 0.74),
                    Point2D(x: 0.22, y: 0.86),
                ]),
            ],
            advanceWidth: 1
        ),

        // ！叹号：一竖，一点。
        "！": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.5, y: 0.18), to: Point2D(x: 0.5, y: 0.60)),
                .dot(Point2D(x: 0.5, y: 0.76)),
            ],
            advanceWidth: 1
        ),

        // ？问号：上面一个向右的钩转下来，下面一点。
        "？": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.30, y: 0.30),
                    Point2D(x: 0.38, y: 0.19),
                    Point2D(x: 0.54, y: 0.18),
                    Point2D(x: 0.64, y: 0.27),
                    Point2D(x: 0.60, y: 0.40),
                    Point2D(x: 0.49, y: 0.48),
                    Point2D(x: 0.47, y: 0.60),
                ]),
                .dot(Point2D(x: 0.47, y: 0.76)),
            ],
            advanceWidth: 1
        ),

        // …省略号：三点，横向排开，占满一格。
        "…": PenStrokeGlyph(
            moves: [
                .dot(Point2D(x: 0.18, y: 0.72)),
                .dot(Point2D(x: 0.50, y: 0.72)),
                .dot(Point2D(x: 0.82, y: 0.72)),
            ],
            advanceWidth: 1
        ),

        // ·间隔号：居中一点。
        "·": PenStrokeGlyph(
            moves: [.dot(Point2D(x: 0.5, y: 0.5))],
            advanceWidth: 1
        ),

        // —破折号：一条横线，占满一格（连排两个就是完整的破折号）。
        "—": PenStrokeGlyph(
            moves: [.line(from: Point2D(x: 0.02, y: 0.5), to: Point2D(x: 0.98, y: 0.5))],
            advanceWidth: 1
        ),

        // 「」直角引号：一笔画成的折角。开引号是「上横向左、再向下」，
        // 闭引号是「竖向下、再向左」，两者中心对称。
        "「": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.74, y: 0.18),
                Point2D(x: 0.32, y: 0.18),
                Point2D(x: 0.32, y: 0.58),
            ])],
            advanceWidth: 1
        ),
        "」": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.68, y: 0.42),
                Point2D(x: 0.68, y: 0.82),
                Point2D(x: 0.26, y: 0.82),
            ])],
            advanceWidth: 1
        ),

        // （）圆括号：一段圆弧。圆心落在括号开口那一侧，所以弧背朝外。
        "（": PenStrokeGlyph(
            moves: [.arc(
                center: Point2D(x: 0.78, y: 0.5),
                radius: 0.46,
                from: .pi - 0.62,
                to: .pi + 0.62
            )],
            advanceWidth: 1
        ),
        "）": PenStrokeGlyph(
            moves: [.arc(
                center: Point2D(x: 0.22, y: 0.5),
                radius: 0.46,
                from: -0.62,
                to: 0.62
            )],
            advanceWidth: 1
        ),

        // 《》书名号：两个朝同一方向的尖角。
        "《": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.44, y: 0.20),
                    Point2D(x: 0.22, y: 0.50),
                    Point2D(x: 0.44, y: 0.80),
                ]),
                .through([
                    Point2D(x: 0.78, y: 0.20),
                    Point2D(x: 0.56, y: 0.50),
                    Point2D(x: 0.78, y: 0.80),
                ]),
            ],
            advanceWidth: 1
        ),
        "》": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.22, y: 0.20),
                    Point2D(x: 0.44, y: 0.50),
                    Point2D(x: 0.22, y: 0.80),
                ]),
                .through([
                    Point2D(x: 0.56, y: 0.20),
                    Point2D(x: 0.78, y: 0.50),
                    Point2D(x: 0.56, y: 0.80),
                ]),
            ],
            advanceWidth: 1
        ),
    ]

    // MARK: 西文标点（比例宽）

    /// 窄标点（句点、逗号、冒号、分号、撇号）的宽度。
    private static let narrowWidth: Double = 0.30

    private static let latinMarks: [Character: PenStrokeGlyph] = [
        // . 句点
        ".": PenStrokeGlyph(
            moves: [.dot(Point2D(x: narrowWidth / 2, y: latinBaseline))],
            advanceWidth: narrowWidth
        ),

        // , 逗号：基线附近起笔，往左下勾出去（会伸到基线以下，这是正常的）。
        ",": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.19, y: 0.68),
                Point2D(x: 0.17, y: 0.78),
                Point2D(x: 0.08, y: 0.90),
            ])],
            advanceWidth: narrowWidth
        ),

        // : 冒号：上下两点。
        ":": PenStrokeGlyph(
            moves: [
                .dot(Point2D(x: narrowWidth / 2, y: latinBaseline - latinDotGap)),
                .dot(Point2D(x: narrowWidth / 2, y: latinBaseline)),
            ],
            advanceWidth: narrowWidth
        ),

        // ; 分号：上面一点，下面一个逗号。
        ";": PenStrokeGlyph(
            moves: [
                .dot(Point2D(x: narrowWidth / 2, y: latinBaseline - latinDotGap)),
                .through([
                    Point2D(x: 0.19, y: 0.70),
                    Point2D(x: 0.17, y: 0.80),
                    Point2D(x: 0.08, y: 0.92),
                ]),
            ],
            advanceWidth: narrowWidth
        ),

        // ' 撇号：字母上方一短撇。
        "'": PenStrokeGlyph(
            moves: [.line(
                from: Point2D(x: 0.18, y: latinCapTop),
                to: Point2D(x: 0.11, y: latinCapTop + 0.16)
            )],
            advanceWidth: 0.26
        ),

        // " 双引号：两短撇。
        "\"": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.16, y: latinCapTop), to: Point2D(x: 0.09, y: latinCapTop + 0.16)),
                .line(from: Point2D(x: 0.34, y: latinCapTop), to: Point2D(x: 0.27, y: latinCapTop + 0.16)),
            ],
            advanceWidth: 0.44
        ),

        // ! 叹号：一竖，一点。
        "!": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.16, y: latinCapTop), to: Point2D(x: 0.16, y: 0.58)),
                .dot(Point2D(x: 0.16, y: latinBaseline)),
            ],
            advanceWidth: 0.32
        ),

        // ? 问号：钩 + 点。形状同全角问号，横向压窄。
        "?": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.08, y: 0.30),
                    Point2D(x: 0.14, y: 0.20),
                    Point2D(x: 0.28, y: 0.18),
                    Point2D(x: 0.37, y: 0.27),
                    Point2D(x: 0.33, y: 0.40),
                    Point2D(x: 0.24, y: 0.48),
                    Point2D(x: 0.23, y: 0.58),
                ]),
                .dot(Point2D(x: 0.23, y: latinBaseline)),
            ],
            advanceWidth: 0.50
        ),

        // ( ) 圆括号：一段圆弧，弧背朝外。
        "(": PenStrokeGlyph(
            moves: [.arc(
                center: Point2D(x: 0.52, y: 0.48),
                radius: 0.44,
                from: .pi - 0.66,
                to: .pi + 0.66
            )],
            advanceWidth: 0.36
        ),
        ")": PenStrokeGlyph(
            moves: [.arc(
                center: Point2D(x: -0.16, y: 0.48),
                radius: 0.44,
                from: -0.66,
                to: 0.66
            )],
            advanceWidth: 0.36
        ),

        // - 连字符：中间一短横。
        "-": PenStrokeGlyph(
            moves: [.line(from: Point2D(x: 0.06, y: 0.50), to: Point2D(x: 0.36, y: 0.50))],
            advanceWidth: 0.42
        ),
    ]
}
