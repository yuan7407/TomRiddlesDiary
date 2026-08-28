//
//  LatinStrokes.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：手写定义拉丁字母与数字的笔顺（计划 E1d）。
//
//  为什么要自己写：
//  汉字笔顺数据（makemeahanzi）只覆盖汉字，一个拉丁字母都没有。而这个产品要求
//  中英混排——用户会写 "hello"、魂也要能回 "Take your time."。在此之前这些字符
//  会被如实报成缺笔顺数据然后跳过，句子里就是一串空洞。
//
//  为什么是「印刷体手写」而不是连笔草书：
//  这一套是**手写印刷体**（manuscript / 楷书式的英文），每个字母各自独立、笔画分明。
//  连笔草书（cursive）虽然更像「一气写成」，但它的字母连接方式取决于前后字母，
//  一个字母不是一个固定形状，必须为每种连接关系单独定义——组合爆炸。
//  而且中英混排里连笔英文夹在方块汉字之间反而突兀。
//
//  ── 五条基准线（写成有名字的量，而不是散落的数字）──
//  与西文排版的惯例一致，坐标在 0…1 的字面方格内，y 向下：
//      上伸部 0.14   大写顶 0.17   x 高 0.40   基线 0.78   下伸部 0.95
//  小写 b d f h k l 顶到上伸部，g j p q y 伸到下伸部，其余在 x 高与基线之间。
//
//  ── 字宽 ──
//  拉丁字母是比例宽：i 和 l 很窄，m 和 w 很宽。每个字形各自声明 `advanceWidth`，
//  所有笔画必须落在 0…advanceWidth 之内（由测试守着），否则会压到下一个字。
//
//  ── 这批数据的可信度（诚实说明）──
//  形状由我按手写印刷体的常见写法写出，**没有权威字形数据可以比对**。
//  可机器验证的部分由 `LatinStrokesTests` 守住（笔数、落在字宽内、笔画不退化、
//  该顶到基准线的要顶到）。「看起来像不像那个字母」只能靠眼看，
//  为此 `testDumpAsciiPreviewForHumanReview` 会把 62 个字形渲染成字符画写进文件。
//  笔顺（先写哪一笔）按常见手写习惯定，但它对最终观感的影响远小于形状本身。
//

import Foundation

nonisolated enum LatinStrokes {
    // MARK: 基准线

    /// 小写 b d f h k l 的顶端。
    private static let ascender: Double = 0.14
    /// 大写字母与数字的顶端。
    private static let capTop: Double = 0.17
    /// 小写字母主体的顶端。
    private static let xHeight: Double = 0.40
    /// 字母下沿。
    private static let baseline: Double = 0.78
    /// 小写 g j p q y 尾巴的底端。
    private static let descender: Double = 0.95

    // MARK: 查表

    static let table: [Character: PenStrokeGlyph] = lowercase
        .merging(uppercase) { _, _ in preconditionFailure("小写与大写表出现重复字符") }
        .merging(digits) { _, _ in preconditionFailure("字母与数字表出现重复字符") }

    static func glyph(for character: Character) -> PenStrokeGlyph? {
        table[character]
    }

    // MARK: 小写

    private static let lowercase: [Character: PenStrokeGlyph] = [
        // a：先逆时针画碗（右上起笔，经上、左、下回到右下），再右侧一竖到基线。
        "a": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.44, y: 0.47), Point2D(x: 0.28, y: xHeight),
                    Point2D(x: 0.09, y: 0.52), Point2D(x: 0.10, y: 0.70),
                    Point2D(x: 0.28, y: baseline), Point2D(x: 0.44, y: 0.70),
                ]),
                .line(from: Point2D(x: 0.45, y: xHeight), to: Point2D(x: 0.45, y: baseline)),
            ],
            advanceWidth: 0.54
        ),

        // b：一长竖（上伸部到基线），再从竖的中部往右画碗。
        "b": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: ascender), to: Point2D(x: 0.08, y: baseline)),
                .through([
                    Point2D(x: 0.08, y: 0.48), Point2D(x: 0.25, y: xHeight),
                    Point2D(x: 0.43, y: 0.50), Point2D(x: 0.43, y: 0.68),
                    Point2D(x: 0.26, y: baseline), Point2D(x: 0.08, y: 0.72),
                ]),
            ],
            advanceWidth: 0.54
        ),

        // c：一笔，从右上起逆时针经上、左、下，收在右下。开口朝右。
        "c": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.44, y: 0.48), Point2D(x: 0.29, y: xHeight),
                Point2D(x: 0.11, y: 0.49), Point2D(x: 0.08, y: 0.60),
                Point2D(x: 0.12, y: 0.71), Point2D(x: 0.29, y: baseline),
                Point2D(x: 0.44, y: 0.70),
            ])],
            advanceWidth: 0.52
        ),

        // d：先碗，再右侧一长竖（上伸部到基线）。
        "d": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.44, y: 0.48), Point2D(x: 0.28, y: xHeight),
                    Point2D(x: 0.10, y: 0.50), Point2D(x: 0.10, y: 0.68),
                    Point2D(x: 0.28, y: baseline), Point2D(x: 0.44, y: 0.70),
                ]),
                .line(from: Point2D(x: 0.45, y: ascender), to: Point2D(x: 0.45, y: baseline)),
            ],
            advanceWidth: 0.54
        ),

        // e：先中间一横，再从横的右端绕上去、往左下兜一圈，收在右下。
        "e": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.09, y: 0.58), to: Point2D(x: 0.44, y: 0.58)),
                .through([
                    Point2D(x: 0.44, y: 0.58), Point2D(x: 0.42, y: 0.45),
                    Point2D(x: 0.26, y: xHeight), Point2D(x: 0.10, y: 0.50),
                    Point2D(x: 0.09, y: 0.66), Point2D(x: 0.24, y: baseline),
                    Point2D(x: 0.44, y: 0.71),
                ]),
            ],
            advanceWidth: 0.52
        ),

        // f：先一笔从右上弯下来变成长竖，再加一横。
        "f": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.36, y: 0.21), Point2D(x: 0.26, y: ascender),
                    Point2D(x: 0.17, y: 0.23), Point2D(x: 0.17, y: baseline),
                ]),
                .line(from: Point2D(x: 0.03, y: xHeight), to: Point2D(x: 0.34, y: xHeight)),
            ],
            advanceWidth: 0.38
        ),

        // g：碗，再右侧一竖伸到下伸部并往左勾。
        "g": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.44, y: 0.48), Point2D(x: 0.28, y: xHeight),
                    Point2D(x: 0.10, y: 0.50), Point2D(x: 0.10, y: 0.68),
                    Point2D(x: 0.28, y: baseline), Point2D(x: 0.44, y: 0.70),
                ]),
                .through([
                    Point2D(x: 0.45, y: xHeight), Point2D(x: 0.45, y: 0.86),
                    Point2D(x: 0.30, y: descender), Point2D(x: 0.13, y: 0.90),
                ]),
            ],
            advanceWidth: 0.54
        ),

        // h：一长竖，再一个拱肩落到基线。
        "h": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: ascender), to: Point2D(x: 0.08, y: baseline)),
                .through([
                    Point2D(x: 0.08, y: 0.50), Point2D(x: 0.22, y: xHeight),
                    Point2D(x: 0.40, y: 0.49), Point2D(x: 0.42, y: baseline),
                ]),
            ],
            advanceWidth: 0.52
        ),

        // i：短竖 + 上面一点。
        "i": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.14, y: xHeight), to: Point2D(x: 0.14, y: baseline)),
                .dot(Point2D(x: 0.14, y: 0.26)),
            ],
            advanceWidth: 0.28
        ),

        // j：短竖伸到下伸部并往左勾 + 上面一点。
        "j": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.22, y: xHeight), Point2D(x: 0.22, y: 0.86),
                    Point2D(x: 0.13, y: descender), Point2D(x: 0.03, y: 0.90),
                ]),
                .dot(Point2D(x: 0.22, y: 0.26)),
            ],
            advanceWidth: 0.32
        ),

        // k：一长竖，一斜进来，一斜出去。
        "k": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: ascender), to: Point2D(x: 0.08, y: baseline)),
                .line(from: Point2D(x: 0.42, y: xHeight), to: Point2D(x: 0.10, y: 0.62)),
                .line(from: Point2D(x: 0.20, y: 0.55), to: Point2D(x: 0.44, y: baseline)),
            ],
            advanceWidth: 0.50
        ),

        // l：一长竖。
        "l": PenStrokeGlyph(
            moves: [.line(from: Point2D(x: 0.13, y: ascender), to: Point2D(x: 0.13, y: baseline))],
            advanceWidth: 0.26
        ),

        // m：一竖 + 两个拱肩。
        "m": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.06, y: xHeight), to: Point2D(x: 0.06, y: baseline)),
                .through([
                    Point2D(x: 0.06, y: 0.49), Point2D(x: 0.18, y: xHeight),
                    Point2D(x: 0.32, y: 0.49), Point2D(x: 0.33, y: baseline),
                ]),
                .through([
                    Point2D(x: 0.33, y: 0.49), Point2D(x: 0.45, y: xHeight),
                    Point2D(x: 0.59, y: 0.49), Point2D(x: 0.60, y: baseline),
                ]),
            ],
            advanceWidth: 0.72
        ),

        // n：一竖 + 一个拱肩。
        "n": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: xHeight), to: Point2D(x: 0.08, y: baseline)),
                .through([
                    Point2D(x: 0.08, y: 0.49), Point2D(x: 0.22, y: xHeight),
                    Point2D(x: 0.40, y: 0.49), Point2D(x: 0.42, y: baseline),
                ]),
            ],
            advanceWidth: 0.52
        ),

        // o：一整圈。从顶端起笔逆时针（手写习惯）。
        "o": PenStrokeGlyph(
            moves: [.arc(
                center: Point2D(x: 0.27, y: 0.59),
                radius: 0.19,
                from: -.pi / 2,
                to: -.pi / 2 - 2 * .pi
            )],
            advanceWidth: 0.54
        ),

        // p：一竖从 x 高伸到下伸部，再往右画碗。
        "p": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: xHeight), to: Point2D(x: 0.08, y: descender)),
                .through([
                    Point2D(x: 0.08, y: 0.48), Point2D(x: 0.25, y: xHeight),
                    Point2D(x: 0.43, y: 0.50), Point2D(x: 0.43, y: 0.66),
                    Point2D(x: 0.26, y: 0.76), Point2D(x: 0.08, y: 0.70),
                ]),
            ],
            advanceWidth: 0.54
        ),

        // q：先碗，再右侧一竖伸到下伸部。
        "q": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.44, y: 0.48), Point2D(x: 0.28, y: xHeight),
                    Point2D(x: 0.10, y: 0.50), Point2D(x: 0.10, y: 0.68),
                    Point2D(x: 0.28, y: baseline), Point2D(x: 0.44, y: 0.70),
                ]),
                .line(from: Point2D(x: 0.45, y: xHeight), to: Point2D(x: 0.45, y: descender)),
            ],
            advanceWidth: 0.54
        ),

        // r：一竖 + 一个很短的肩。
        "r": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: xHeight), to: Point2D(x: 0.08, y: baseline)),
                .through([
                    Point2D(x: 0.08, y: 0.50), Point2D(x: 0.20, y: 0.41),
                    Point2D(x: 0.36, y: 0.44),
                ]),
            ],
            advanceWidth: 0.40
        ),

        // s：一笔 S 形，上小下大。
        "s": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.39, y: 0.46), Point2D(x: 0.25, y: xHeight),
                Point2D(x: 0.11, y: 0.47), Point2D(x: 0.16, y: 0.56),
                Point2D(x: 0.33, y: 0.62), Point2D(x: 0.39, y: 0.71),
                Point2D(x: 0.25, y: baseline), Point2D(x: 0.10, y: 0.72),
            ])],
            advanceWidth: 0.48
        ),

        // t：一竖（起笔比 x 高再高一点）+ 一横。
        "t": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.18, y: 0.26), to: Point2D(x: 0.18, y: baseline)),
                .line(from: Point2D(x: 0.03, y: xHeight), to: Point2D(x: 0.33, y: xHeight)),
            ],
            advanceWidth: 0.36
        ),

        // u：左竖下弯兜到右，再右侧一竖。
        "u": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.08, y: xHeight), Point2D(x: 0.08, y: 0.68),
                    Point2D(x: 0.24, y: baseline), Point2D(x: 0.42, y: 0.68),
                ]),
                .line(from: Point2D(x: 0.43, y: xHeight), to: Point2D(x: 0.43, y: baseline)),
            ],
            advanceWidth: 0.52
        ),

        // v：两斜相交于基线。
        "v": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.05, y: xHeight), to: Point2D(x: 0.25, y: baseline)),
                .line(from: Point2D(x: 0.25, y: baseline), to: Point2D(x: 0.45, y: xHeight)),
            ],
            advanceWidth: 0.52
        ),

        // w：两个 v 相连。
        "w": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.05, y: xHeight), Point2D(x: 0.19, y: baseline),
                    Point2D(x: 0.33, y: 0.48),
                ]),
                .through([
                    Point2D(x: 0.33, y: 0.48), Point2D(x: 0.47, y: baseline),
                    Point2D(x: 0.61, y: xHeight),
                ]),
            ],
            advanceWidth: 0.68
        ),

        // x：两斜交叉。
        "x": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.06, y: xHeight), to: Point2D(x: 0.44, y: baseline)),
                .line(from: Point2D(x: 0.44, y: xHeight), to: Point2D(x: 0.06, y: baseline)),
            ],
            advanceWidth: 0.52
        ),

        // y：左斜到中，右斜伸到下伸部并往左勾。
        "y": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.06, y: xHeight), to: Point2D(x: 0.26, y: 0.72)),
                .through([
                    Point2D(x: 0.46, y: xHeight), Point2D(x: 0.24, y: 0.86),
                    Point2D(x: 0.08, y: descender),
                ]),
            ],
            advanceWidth: 0.52
        ),

        // z：一横、一斜、一横，一笔写成。
        "z": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.07, y: 0.42), Point2D(x: 0.43, y: 0.42),
                Point2D(x: 0.09, y: 0.76), Point2D(x: 0.45, y: 0.76),
            ])],
            advanceWidth: 0.52
        ),
    ]

    // MARK: 大写

    private static let uppercase: [Character: PenStrokeGlyph] = [
        // A：左斜上、右斜下、中间一横。
        "A": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.04, y: baseline), to: Point2D(x: 0.30, y: capTop)),
                .line(from: Point2D(x: 0.30, y: capTop), to: Point2D(x: 0.56, y: baseline)),
                .line(from: Point2D(x: 0.14, y: 0.58), to: Point2D(x: 0.46, y: 0.58)),
            ],
            advanceWidth: 0.64
        ),

        // B：一长竖 + 上下两个碗。
        "B": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: capTop), to: Point2D(x: 0.08, y: baseline)),
                .through([
                    Point2D(x: 0.08, y: capTop), Point2D(x: 0.34, y: 0.20),
                    Point2D(x: 0.40, y: 0.33), Point2D(x: 0.29, y: 0.46),
                    Point2D(x: 0.08, y: 0.47),
                ]),
                .through([
                    Point2D(x: 0.08, y: 0.47), Point2D(x: 0.38, y: 0.50),
                    Point2D(x: 0.45, y: 0.63), Point2D(x: 0.33, y: 0.76),
                    Point2D(x: 0.08, y: baseline),
                ]),
            ],
            advanceWidth: 0.58
        ),

        // C：一笔大弧，开口朝右。
        "C": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.52, y: 0.28), Point2D(x: 0.35, y: capTop),
                Point2D(x: 0.16, y: 0.25), Point2D(x: 0.08, y: 0.45),
                Point2D(x: 0.11, y: 0.64), Point2D(x: 0.26, y: 0.76),
                Point2D(x: 0.45, y: 0.75), Point2D(x: 0.54, y: 0.65),
            ])],
            advanceWidth: 0.62
        ),

        // D：一长竖 + 一个大弧兜回来。
        "D": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: capTop), to: Point2D(x: 0.08, y: baseline)),
                .through([
                    Point2D(x: 0.08, y: capTop), Point2D(x: 0.34, y: 0.20),
                    Point2D(x: 0.51, y: 0.38), Point2D(x: 0.50, y: 0.60),
                    Point2D(x: 0.33, y: 0.76), Point2D(x: 0.08, y: baseline),
                ]),
            ],
            advanceWidth: 0.62
        ),

        // E：一长竖 + 上中下三横。
        "E": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.10, y: capTop), to: Point2D(x: 0.10, y: baseline)),
                .line(from: Point2D(x: 0.10, y: capTop), to: Point2D(x: 0.48, y: capTop)),
                .line(from: Point2D(x: 0.10, y: 0.47), to: Point2D(x: 0.42, y: 0.47)),
                .line(from: Point2D(x: 0.10, y: baseline), to: Point2D(x: 0.49, y: baseline)),
            ],
            advanceWidth: 0.56
        ),

        // F：E 去掉最下面那一横。
        "F": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.10, y: capTop), to: Point2D(x: 0.10, y: baseline)),
                .line(from: Point2D(x: 0.10, y: capTop), to: Point2D(x: 0.47, y: capTop)),
                .line(from: Point2D(x: 0.10, y: 0.47), to: Point2D(x: 0.41, y: 0.47)),
            ],
            advanceWidth: 0.54
        ),

        // G：C 的弧，收笔时往里勾一横。
        "G": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.52, y: 0.28), Point2D(x: 0.35, y: capTop),
                    Point2D(x: 0.16, y: 0.25), Point2D(x: 0.08, y: 0.45),
                    Point2D(x: 0.11, y: 0.64), Point2D(x: 0.27, y: 0.76),
                    Point2D(x: 0.47, y: 0.73), Point2D(x: 0.53, y: 0.60),
                ]),
                .line(from: Point2D(x: 0.53, y: 0.60), to: Point2D(x: 0.36, y: 0.60)),
            ],
            advanceWidth: 0.62
        ),

        // H：两竖 + 中间一横。
        "H": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: capTop), to: Point2D(x: 0.08, y: baseline)),
                .line(from: Point2D(x: 0.50, y: capTop), to: Point2D(x: 0.50, y: baseline)),
                .line(from: Point2D(x: 0.08, y: 0.48), to: Point2D(x: 0.50, y: 0.48)),
            ],
            advanceWidth: 0.60
        ),

        // I：一竖（不加上下横，与手写习惯一致）。
        "I": PenStrokeGlyph(
            moves: [.line(from: Point2D(x: 0.14, y: capTop), to: Point2D(x: 0.14, y: baseline))],
            advanceWidth: 0.30
        ),

        // J：一竖到下面往左勾。
        "J": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.34, y: capTop), Point2D(x: 0.34, y: 0.65),
                Point2D(x: 0.22, y: 0.77), Point2D(x: 0.06, y: 0.71),
            ])],
            advanceWidth: 0.44
        ),

        // K：一竖 + 一斜进来 + 一斜出去。
        "K": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: capTop), to: Point2D(x: 0.08, y: baseline)),
                .line(from: Point2D(x: 0.50, y: capTop), to: Point2D(x: 0.10, y: 0.50)),
                .line(from: Point2D(x: 0.22, y: 0.42), to: Point2D(x: 0.52, y: baseline)),
            ],
            advanceWidth: 0.58
        ),

        // L：一竖 + 一横。
        "L": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.10, y: capTop), to: Point2D(x: 0.10, y: baseline)),
                .line(from: Point2D(x: 0.10, y: baseline), to: Point2D(x: 0.47, y: baseline)),
            ],
            advanceWidth: 0.52
        ),

        // M：左竖上行、下斜到中、上斜到右顶、右竖下行。
        "M": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.06, y: baseline), to: Point2D(x: 0.06, y: capTop)),
                .line(from: Point2D(x: 0.06, y: capTop), to: Point2D(x: 0.36, y: 0.58)),
                .line(from: Point2D(x: 0.36, y: 0.58), to: Point2D(x: 0.66, y: capTop)),
                .line(from: Point2D(x: 0.66, y: capTop), to: Point2D(x: 0.66, y: baseline)),
            ],
            advanceWidth: 0.76
        ),

        // N：左竖上行、斜到右下、右竖上行。
        "N": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: baseline), to: Point2D(x: 0.08, y: capTop)),
                .line(from: Point2D(x: 0.08, y: capTop), to: Point2D(x: 0.52, y: baseline)),
                .line(from: Point2D(x: 0.52, y: baseline), to: Point2D(x: 0.52, y: capTop)),
            ],
            advanceWidth: 0.62
        ),

        // O：一整圈，从顶端起笔逆时针。
        "O": PenStrokeGlyph(
            moves: [.arc(
                center: Point2D(x: 0.32, y: 0.475),
                radius: 0.29,
                from: -.pi / 2,
                to: -.pi / 2 - 2 * .pi
            )],
            advanceWidth: 0.66
        ),

        // P：一长竖 + 上半个碗。
        "P": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: capTop), to: Point2D(x: 0.08, y: baseline)),
                .through([
                    Point2D(x: 0.08, y: capTop), Point2D(x: 0.36, y: 0.20),
                    Point2D(x: 0.43, y: 0.34), Point2D(x: 0.31, y: 0.47),
                    Point2D(x: 0.08, y: 0.49),
                ]),
            ],
            advanceWidth: 0.56
        ),

        // Q：O 加一条斜尾巴。
        "Q": PenStrokeGlyph(
            moves: [
                .arc(
                    center: Point2D(x: 0.32, y: 0.475),
                    radius: 0.29,
                    from: -.pi / 2,
                    to: -.pi / 2 - 2 * .pi
                ),
                .line(from: Point2D(x: 0.40, y: 0.62), to: Point2D(x: 0.61, y: 0.86)),
            ],
            advanceWidth: 0.66
        ),

        // R：P 再加一条右下的腿。
        "R": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: capTop), to: Point2D(x: 0.08, y: baseline)),
                .through([
                    Point2D(x: 0.08, y: capTop), Point2D(x: 0.36, y: 0.20),
                    Point2D(x: 0.43, y: 0.34), Point2D(x: 0.31, y: 0.47),
                    Point2D(x: 0.08, y: 0.49),
                ]),
                .line(from: Point2D(x: 0.27, y: 0.49), to: Point2D(x: 0.53, y: baseline)),
            ],
            advanceWidth: 0.60
        ),

        // S：一笔 S 形。
        "S": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.49, y: 0.27), Point2D(x: 0.33, y: capTop),
                Point2D(x: 0.14, y: 0.23), Point2D(x: 0.13, y: 0.37),
                Point2D(x: 0.30, y: 0.46), Point2D(x: 0.47, y: 0.56),
                Point2D(x: 0.47, y: 0.70), Point2D(x: 0.29, y: baseline),
                Point2D(x: 0.10, y: 0.70),
            ])],
            advanceWidth: 0.58
        ),

        // T：一横 + 一竖。
        "T": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.04, y: capTop), to: Point2D(x: 0.56, y: capTop)),
                .line(from: Point2D(x: 0.30, y: capTop), to: Point2D(x: 0.30, y: baseline)),
            ],
            advanceWidth: 0.60
        ),

        // U：一笔下去兜回来再上去。
        "U": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.08, y: capTop), Point2D(x: 0.08, y: 0.60),
                Point2D(x: 0.22, y: 0.76), Point2D(x: 0.40, y: 0.74),
                Point2D(x: 0.51, y: 0.58), Point2D(x: 0.51, y: capTop),
            ])],
            advanceWidth: 0.60
        ),

        // V：两斜相交于基线。
        "V": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.04, y: capTop), to: Point2D(x: 0.30, y: baseline)),
                .line(from: Point2D(x: 0.30, y: baseline), to: Point2D(x: 0.56, y: capTop)),
            ],
            advanceWidth: 0.60
        ),

        // W：四斜连成两个 V。
        "W": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.04, y: capTop), to: Point2D(x: 0.20, y: baseline)),
                .line(from: Point2D(x: 0.20, y: baseline), to: Point2D(x: 0.36, y: 0.30)),
                .line(from: Point2D(x: 0.36, y: 0.30), to: Point2D(x: 0.52, y: baseline)),
                .line(from: Point2D(x: 0.52, y: baseline), to: Point2D(x: 0.68, y: capTop)),
            ],
            advanceWidth: 0.76
        ),

        // X：两斜交叉。
        "X": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.06, y: capTop), to: Point2D(x: 0.52, y: baseline)),
                .line(from: Point2D(x: 0.52, y: capTop), to: Point2D(x: 0.06, y: baseline)),
            ],
            advanceWidth: 0.58
        ),

        // Y：两斜汇到中间，再一竖下来。
        "Y": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.05, y: capTop), to: Point2D(x: 0.29, y: 0.48)),
                .line(from: Point2D(x: 0.53, y: capTop), to: Point2D(x: 0.29, y: 0.48)),
                .line(from: Point2D(x: 0.29, y: 0.48), to: Point2D(x: 0.29, y: baseline)),
            ],
            advanceWidth: 0.58
        ),

        // Z：一横、一斜、一横，一笔写成。
        "Z": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.08, y: capTop), Point2D(x: 0.50, y: capTop),
                Point2D(x: 0.09, y: baseline), Point2D(x: 0.52, y: baseline),
            ])],
            advanceWidth: 0.58
        ),
    ]

    // MARK: 数字

    private static let digits: [Character: PenStrokeGlyph] = [
        // 0：一个竖长的椭圆。用控制点画而不是圆弧——数字比字母瘦高，圆弧会太胖。
        "0": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.28, y: capTop), Point2D(x: 0.47, y: 0.28),
                Point2D(x: 0.50, y: 0.48), Point2D(x: 0.42, y: 0.70),
                Point2D(x: 0.26, y: baseline), Point2D(x: 0.09, y: 0.68),
                Point2D(x: 0.05, y: 0.46), Point2D(x: 0.12, y: 0.25),
                Point2D(x: 0.28, y: capTop),
            ])],
            advanceWidth: 0.56
        ),

        // 1：起笔的小斜旗 + 一长竖。
        "1": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.08, y: 0.28), to: Point2D(x: 0.26, y: capTop)),
                .line(from: Point2D(x: 0.26, y: capTop), to: Point2D(x: 0.26, y: baseline)),
            ],
            advanceWidth: 0.42
        ),

        // 2：上面一个右弯，斜下来，底下一横。
        "2": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.07, y: 0.27), Point2D(x: 0.20, y: 0.18),
                Point2D(x: 0.39, y: 0.21), Point2D(x: 0.45, y: 0.36),
                Point2D(x: 0.30, y: 0.54), Point2D(x: 0.08, y: baseline),
                Point2D(x: 0.50, y: baseline),
            ])],
            advanceWidth: 0.56
        ),

        // 3：上下两个右凸的弧，中间收一下。
        "3": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.08, y: 0.24), Point2D(x: 0.26, y: capTop),
                Point2D(x: 0.43, y: 0.25), Point2D(x: 0.34, y: 0.42),
                Point2D(x: 0.22, y: 0.46), Point2D(x: 0.40, y: 0.50),
                Point2D(x: 0.47, y: 0.64), Point2D(x: 0.32, y: 0.77),
                Point2D(x: 0.10, y: 0.71),
            ])],
            advanceWidth: 0.54
        ),

        // 4：从顶点斜下到左，横过去，再一竖到底。
        "4": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.38, y: capTop), Point2D(x: 0.06, y: 0.58),
                    Point2D(x: 0.52, y: 0.58),
                ]),
                .line(from: Point2D(x: 0.38, y: capTop), to: Point2D(x: 0.38, y: baseline)),
            ],
            advanceWidth: 0.58
        ),

        // 5：上面一竖一折，下面一个右凸的碗。
        "5": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.11, y: capTop), Point2D(x: 0.11, y: 0.41),
                    Point2D(x: 0.30, y: 0.38), Point2D(x: 0.45, y: 0.48),
                    Point2D(x: 0.44, y: 0.66), Point2D(x: 0.26, y: 0.77),
                    Point2D(x: 0.08, y: 0.71),
                ]),
                .line(from: Point2D(x: 0.11, y: capTop), to: Point2D(x: 0.46, y: capTop)),
            ],
            advanceWidth: 0.54
        ),

        // 6：一笔从右上弯到左下，再兜出一个小圈。
        "6": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.44, y: 0.21), Point2D(x: 0.26, y: capTop),
                Point2D(x: 0.12, y: 0.33), Point2D(x: 0.08, y: 0.55),
                Point2D(x: 0.17, y: 0.73), Point2D(x: 0.35, y: 0.76),
                Point2D(x: 0.46, y: 0.63), Point2D(x: 0.36, y: 0.50),
                Point2D(x: 0.17, y: 0.51), Point2D(x: 0.09, y: 0.59),
            ])],
            advanceWidth: 0.54
        ),

        // 7：一横 + 一长斜。
        "7": PenStrokeGlyph(
            moves: [
                .line(from: Point2D(x: 0.06, y: capTop), to: Point2D(x: 0.50, y: capTop)),
                .line(from: Point2D(x: 0.50, y: capTop), to: Point2D(x: 0.22, y: baseline)),
            ],
            advanceWidth: 0.54
        ),

        // 8：一笔连成上下两个圈。
        "8": PenStrokeGlyph(
            moves: [.through([
                Point2D(x: 0.28, y: capTop), Point2D(x: 0.43, y: 0.25),
                Point2D(x: 0.35, y: 0.39), Point2D(x: 0.17, y: 0.47),
                Point2D(x: 0.10, y: 0.61), Point2D(x: 0.25, y: 0.76),
                Point2D(x: 0.42, y: 0.69), Point2D(x: 0.41, y: 0.54),
                Point2D(x: 0.21, y: 0.43), Point2D(x: 0.13, y: 0.28),
                Point2D(x: 0.28, y: capTop),
            ])],
            advanceWidth: 0.54
        ),

        // 9：上面一个小圈，再一竖弯下来。
        "9": PenStrokeGlyph(
            moves: [
                .through([
                    Point2D(x: 0.44, y: 0.31), Point2D(x: 0.34, y: capTop),
                    Point2D(x: 0.16, y: 0.21), Point2D(x: 0.11, y: 0.34),
                    Point2D(x: 0.25, y: 0.45), Point2D(x: 0.42, y: 0.39),
                    Point2D(x: 0.45, y: 0.27),
                ]),
                .through([
                    Point2D(x: 0.45, y: 0.27), Point2D(x: 0.45, y: 0.58),
                    Point2D(x: 0.34, y: 0.74), Point2D(x: 0.14, y: baseline),
                ]),
            ],
            advanceWidth: 0.54
        ),
    ]
}
