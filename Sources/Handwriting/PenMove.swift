//
//  PenMove.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：用一小套「笔怎么动」的词汇描述一笔，再把它展开成坐标点。
//
//  为什么要有这层词汇（计划 E1c/E1d，2026-08-29）：
//  汉字的笔顺有现成数据（makemeahanzi 的 medians），但标点、拉丁字母和数字都不在
//  数据集里，必须自己定义。直接写坐标点列是能写的，但会得到几百行这样的东西：
//
//      [[0.3, 0.56], [0.29, 0.68], [0.22, 0.82]]
//
//  没有人能看出那是个逗号，改错了也看不出来。而写成
//
//      .through([...])   // 从中部起笔，往左下勾出去
//
//  加上「直线」「圆弧」「墨点」这几个词，每一笔就能读出意图，人工复核才可能。
//  这一点在这个项目里格外要紧：这批数据是**手写的**，没有上游可以对照，
//  唯一的质量保证就是「看得懂 + 能渲染出来核对」。
//
//  坐标约定：一律在 0…1 的字面方格内，原点左上、**y 向下**，与
//  `GlyphStrokeProvider` 归一化之后的汉字数据完全一致——两套数据必须能混排。
//
//  为什么圆弧单独成一个词而不是也写成点列：
//  「。」是一个整圆，「(」是一段圆弧。写成点列要手算三角函数，写错了只能靠眼看；
//  写成圆心 + 半径 + 起止角，意图一目了然，而且加密的密度由程序按弧长算，
//  不需要人去数该放几个点。
//

import Foundation

/// 一笔的写法。
nonisolated enum PenMove: Equatable, Sendable {
    /// 一个墨点。展开成单点笔画，引擎会让它像墨一样洇开（计划 A7）。
    case dot(Point2D)

    /// 直线。直线不需要加密——引擎的重采样会按等弧长铺点。
    case line(from: Point2D, to: Point2D)

    /// 依次经过这些点的曲线。中间由 `StrokePathSmoothing` 平滑加密，
    /// 所以只需要给出转折处的控制点，不必手工铺密。
    case through([Point2D])

    /// 圆弧。
    /// - center: 圆心。
    /// - radius: 半径。
    /// - from / to: 起止角，单位弧度。0 指向右（+x），角度增大朝下（+y），
    ///   因为坐标系 y 向下。`to` 大于 `from` 即顺时针（视觉上）。
    case arc(center: Point2D, radius: Double, from: Double, to: Double)

    /// 展开成坐标点。
    /// - Parameter spacing: 目标点间距（字面方格单位）。用于圆弧的取点密度与曲线加密。
    func points(spacing: Double) -> [Point2D] {
        precondition(spacing > 0, "Spacing must be positive")

        switch self {
        case .dot(let point):
            return [point]

        case .line(let origin, let destination):
            return [origin, destination]

        case .through(let controls):
            return StrokePathSmoothing.densified(controls, targetSpacing: spacing)

        case .arc(let center, let radius, let from, let to):
            return arcPoints(center: center, radius: radius, from: from, to: to, spacing: spacing)
        }
    }

    /// 按弧长铺点：段数由「弧长 ÷ 目标间距」算出，不写死。
    /// 这样小圆（如「。」）不会被过度取点，大圆弧也不会稀到看出多边形。
    private func arcPoints(
        center: Point2D,
        radius: Double,
        from: Double,
        to: Double,
        spacing: Double
    ) -> [Point2D] {
        let sweep = to - from
        let arcLength = abs(sweep) * radius
        let steps = max(2, Int((arcLength / spacing).rounded(.up)))

        return (0 ... steps).map { step in
            let angle = from + sweep * Double(step) / Double(steps)
            return Point2D(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }
}

/// 一个手写定义的字形：按笔顺排列的笔，加上它占多宽。
nonisolated struct PenStrokeGlyph: Equatable, Sendable {
    /// 按笔顺排列的每一笔。
    let moves: [PenMove]

    /// 这个字占多宽，以字面方格边长为 1。
    ///
    /// 为什么需要它：汉字是等宽方格（都是 1），但拉丁字母和西文标点天生窄得多。
    /// 一个英文句点若也占满一个方格，句子里会出现巨大的空洞。
    /// 所有笔画都必须落在 0…`advanceWidth` 这个横向范围内，
    /// 否则会压到下一个字——这条由测试守着。
    let advanceWidth: Double

    /// 展开成归一化坐标里的有序笔画。
    func strokes(spacing: Double) -> [Polyline] {
        moves.map { Polyline(points: $0.points(spacing: spacing)) }
    }
}
