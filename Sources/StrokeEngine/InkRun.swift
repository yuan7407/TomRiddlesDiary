//
//  InkRun.swift
//  模块：StrokeEngine（纯逻辑层，只依赖 Foundation）
//
//  文件职责：把「一轮写下的全部笔画」看成一条按下笔先后接起来的长墨线，
//  回答一个问题：这条墨线上从第 a 点到第 b 点的那一段，是哪些折线？
//
//  为什么需要它：
//  「对开」设计里有两件事都在沿着用户的笔迹走——
//  · 他在读：一小段墨沿着你下笔的顺序重新变湿（`ReadingSweep`）；
//  · 他在写：他写多少，你的墨就按同样的顺序少多少（`InkTransfer`）。
//  两件事要的是同一个几何操作。只写一份，两处才不会对不上
//  （仓库里吃过「同一条规则在两处独立取值」的亏，见 MEMORY 的判断错误一节）。
//
//  关于「点一下」：
//  只点了一下的笔画长度是 0。如果按 0 算，它在这条长墨线上不占位置，
//  读的光永远扫不到它、抽墨也永远抽不到它，纸上会留下一个孤零零的墨点。
//  所以每一笔都至少算 `minimumStrokeLength` 那么长。这个值由调用方给（引擎不带默认参数）。
//

import Foundation

/// 一轮笔迹，按下笔先后接成的一条长墨线。
nonisolated struct InkRun: Equatable, Sendable {
    let polylines: [Polyline]
    /// 每一笔在长墨线上占的长度（不短于 `minimumStrokeLength`）。
    let strokeLengths: [Double]
    let totalLength: Double

    init(_ polylines: [Polyline], minimumStrokeLength: Double) {
        precondition(minimumStrokeLength > 0, "Minimum stroke length must be positive")
        let kept = polylines.filter { !$0.points.isEmpty }
        self.polylines = kept
        strokeLengths = kept.map { max(minimumStrokeLength, $0.length) }
        // 与 `stretch` 里的游标用同一种累加方式（逐笔相加），避免「刚好走完」差一个尾数。
        totalLength = strokeLengths.reduce(0, +)
    }

    var isEmpty: Bool { polylines.isEmpty }

    /// 长墨线上 `start` 到 `end` 之间的那一段。越界时夹紧；`start >= end` 时返回空。
    /// 被这一段碰到的「点一下」原样返回成只有一个点的折线。
    func stretch(from start: Double, to end: Double) -> [Polyline] {
        let low = max(0, start)
        let high = min(totalLength, end)
        guard high > low else { return [] }

        var pieces: [Polyline] = []
        var offset = 0.0
        for (polyline, length) in zip(polylines, strokeLengths) {
            defer { offset += length }
            guard offset + length > low else { continue }
            guard offset < high else { break }
            let geometric = polyline.length
            guard geometric > 0, polyline.points.count > 1 else {
                pieces.append(Polyline(points: [polyline.points[0]]))
                continue
            }
            // 这一笔在长墨线上占的长度可能被垫长过（见文件头）；按比例换回它自己的几何长度。
            let scale = geometric / length
            let piece = Self.slice(polyline, from: (low - offset) * scale, to: (high - offset) * scale)
            if !piece.points.isEmpty { pieces.append(piece) }
        }
        return pieces
    }

    /// 长墨线上某个位置的坐标。没有墨时返回 nil。
    func point(at distance: Double) -> Point2D? {
        guard !isEmpty else { return nil }
        let clamped = min(totalLength, max(0, distance))
        var offset = 0.0
        for (polyline, length) in zip(polylines, strokeLengths) {
            if clamped <= offset + length {
                let geometric = polyline.length
                guard geometric > 0 else { return polyline.points[0] }
                return Self.slice(polyline, from: 0, to: (clamped - offset) * geometric / length).points.last
            }
            offset += length
        }
        return polylines.last?.points.last
    }

    /// 一条折线上按弧长取一段。两端落在线段中间时插值出端点。
    private static func slice(_ polyline: Polyline, from start: Double, to end: Double) -> Polyline {
        let points = polyline.points
        var result: [Point2D] = []
        var travelled = 0.0
        for index in 0 ..< points.count - 1 {
            let a = points[index]
            let b = points[index + 1]
            let segment = a.distance(to: b)
            let segmentEnd = travelled + segment
            defer { travelled = segmentEnd }
            guard segment > 0, segmentEnd > start else { continue }
            guard travelled < end else { break }
            if result.isEmpty {
                let fraction = max(0, (start - travelled) / segment)
                result.append(Point2D.interpolate(from: a, to: b, fraction: fraction))
            }
            let fraction = min(1, (end - travelled) / segment)
            result.append(Point2D.interpolate(from: a, to: b, fraction: fraction))
        }
        return Polyline(points: result)
    }
}
