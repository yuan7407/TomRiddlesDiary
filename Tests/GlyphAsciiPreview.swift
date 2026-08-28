//
//  GlyphAsciiPreview.swift
//  模块：Tests（测试辅助：把手写字形渲染成字符画）
//
//  文件职责：把 `PenStrokeGlyph` 画成字符网格，写进文件供人眼核对。
//
//  为什么需要它：
//  标点（E1c）与拉丁字母数字（E1d）的笔顺是**手写的坐标**，没有任何上游数据可以比对。
//  「这个 s 看起来像不像 s」机器判断不了，而这恰恰是最容易错、后果最直接的地方——
//  一个字母写歪了，页面上就是一个歪字母，测试全绿也照样歪。
//
//  为什么不写形状断言：
//  唯一能写的「期望形状」就是把当前实现的输出抄下来当期望值，那等于用自己证明自己，
//  一点问题都发现不了，还会在每次微调坐标时集体失败。所以这里只做渲染，
//  加上「至少要落下墨迹」这一条底线断言（那条能抓出「某一笔根本没画出来」）。
//
//  为什么放在测试目标里而不是做成 App 里的诊断界面：
//  它只在开发期用一次，不该进产品面。而测试目标本来就有跑起来的入口。
//

import Foundation
@testable import TomRiddlesDiary

nonisolated enum GlyphAsciiPreview {
    /// 渲染结果。
    struct Picture {
        let text: String
        /// 落下了多少个墨迹格。为 0 说明这个字形根本没画出来。
        let inkedCells: Int
    }

    /// 把若干笔渲染成字符网格。
    ///
    /// - Parameters:
    ///   - strokes: 归一化坐标（0…1 字面方格，y 向下）里的笔画。
    ///   - advanceWidth: 字宽，会在网格里用 `│` 标出来，便于看出有没有出界。
    ///   - columns / rows: 网格分辨率。宽比高多，因为终端里字符本身是竖长的。
    /// - Returns: 字符画与墨迹格数。
    static func render(
        strokes: [Polyline],
        advanceWidth: Double,
        columns: Int = 40,
        rows: Int = 20
    ) -> Picture {
        var grid = Array(repeating: Array(repeating: Character(" "), count: columns), count: rows)
        var inked = 0

        for (index, stroke) in strokes.enumerated() {
            // 用笔序号当墨迹字符，这样笔顺也能一眼看出来。
            // 超过 9 笔就统一用 * ——手写字形不会有那么多笔，真出现了也说明该复核。
            let label: Character = index < 9 ? Character(String(index + 1)) : "*"

            // 逐段细分：`.line` 只给两个端点，直接打点会只留下两个墨迹格。
            for point in interpolated(stroke.points) {
                let column = Int((point.x * Double(columns)).rounded(.down))
                let row = Int((point.y * Double(rows)).rounded(.down))
                guard grid.indices.contains(row), grid[row].indices.contains(column) else { continue }
                if grid[row][column] == " " { inked += 1 }
                grid[row][column] = label
            }
        }

        let widthColumn = min(columns - 1, Int((advanceWidth * Double(columns)).rounded(.down)))
        var text = ""
        for row in 0 ..< rows {
            text += "  "
            for column in 0 ..< columns {
                // 字宽线只在那一列没有墨迹时画，否则会把笔画擦掉、看起来像断笔。
                text.append(column == widthColumn && grid[row][column] == " " ? "│" : grid[row][column])
            }
            text += "\n"
        }
        return Picture(text: text, inkedCells: inked)
    }

    /// 把折线细分成密集的点，让字符网格上不会出现断点。
    /// 步长取得比一个网格格子还小，保证相邻墨迹格连得上。
    private static func interpolated(_ points: [Point2D], step: Double = 0.004) -> [Point2D] {
        guard points.count > 1 else { return points }

        var dense: [Point2D] = []
        for (start, end) in zip(points, points.dropFirst()) {
            let steps = max(1, Int((start.distance(to: end) / step).rounded(.up)))
            for index in 0 ... steps {
                dense.append(Point2D.interpolate(
                    from: start,
                    to: end,
                    fraction: Double(index) / Double(steps)
                ))
            }
        }
        return dense
    }
}
