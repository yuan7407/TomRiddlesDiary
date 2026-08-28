//
//  StrokePathSmoothing.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：把稀疏的笔画中线加密成平滑曲线，让弯笔不再有棱角。
//
//  为什么需要它（2026-08-29）：
//  字形数据的中线**每笔平均只有 5.6 个点**——它记的是骨架的转折，不是一条细密的曲线。
//  而下游的重采样是在相邻点之间**走直线**的，于是一个弧形笔画（撇、弯钩、走之底）
//  会被画成三四段折线，转折处看得见硬角。字号越大越明显。
//
//  为什么不在引擎的重采样里顺手平滑：
//  引擎的重采样是通用的，它同样处理 PencilKit 读来的用户笔迹——那份数据本来就很密，
//  再平滑一次等于改动用户自己写的字。棱角的根源是**数据稀疏**，
//  所以修在数据这一侧，引擎的契约（「给我折线，我按等弧长重采样」）保持不变。
//
//  为什么用向心 Catmull-Rom 样条：
//  - 它**穿过每一个原始控制点**。中线是字形骨架，点的位置是数据本身的一部分，
//    不能被「近似」掉（贝塞尔那类逼近样条会把骨架磨圆，字会变形）。
//  - 「向心」指的是节点间距取相邻点距离的平方根（alpha = 0.5）。
//    这一点很关键：均匀参数化的 Catmull-Rom 在点距相差很大时会**冲出控制点之外**
//    甚至自交（打个圈），而中线的点距本来就很不均匀（长横只有两个点，
//    弯钩挤着好几个点）。向心参数化数学上保证不会出现这种自交与超射。
//  - 局部性：每一段只受相邻四个点影响，改一个点不会让整笔的形状漂移。
//
//  端点怎么办：第一段和最后一段各缺一个邻居。这里用**镜像**补一个虚拟点
//  （把第二个点关于第一个点对称过去），效果是端点处的切线沿着首段方向延伸出去，
//  笔画不会在起笔处莫名拐一下。首尾点本身**精确保留**，不做任何移动——
//  笔画接头和字形定位都依赖它们。
//

import Foundation

nonisolated enum StrokePathSmoothing {
    /// 向心参数化的指数。0.5 就是「向心」这个名字的来源；
    /// 0 是均匀参数化（会超射、可能自交），1 是弦长参数化（弯处会绷紧）。
    /// 取 0.5 不是调参调出来的，它是这类样条不自交的已知取值。
    private static let centripetalExponent: Double = 0.5

    /// 判定两点重合的容差。重合点会让节点间距为 0，样条公式除零。
    /// 数值稳定性阈值，不是手感参数。
    private static let coincidentPointTolerance: Double = 1e-9

    /// 把一条稀疏的中线加密成平滑曲线。
    ///
    /// - Parameters:
    ///   - points: 原始中线点。
    ///   - targetSpacing: 加密后相邻点的目标间距，单位与输入坐标一致。
    ///     必须为正数。它决定加密到多细，不决定形状。
    /// - Returns: 加密后的点。**首尾点与输入完全相同**；
    ///   少于三个点时原样返回（两点之间本来就是直线，没有曲率可言）。
    static func densified(_ points: [Point2D], targetSpacing: Double) -> [Point2D] {
        precondition(targetSpacing > 0, "Target spacing must be positive")

        let unique = removingCoincidentPoints(points)
        guard unique.count > 2 else { return unique }

        var result: [Point2D] = [unique[0]]
        result.reserveCapacity(unique.count * 4)

        for index in 0 ..< unique.count - 1 {
            // 每一段需要四个点：前一个、这一段的两端、后一个。
            // 首尾各缺一个邻居，用镜像补上（见文件头）。
            let p0 = index == 0
                ? mirrored(unique[1], about: unique[0])
                : unique[index - 1]
            let p1 = unique[index]
            let p2 = unique[index + 1]
            let p3 = index + 2 < unique.count
                ? unique[index + 2]
                : mirrored(unique[unique.count - 2], about: unique[unique.count - 1])

            // 这一段要切成几份：按弦长与目标间距推出，不写死份数。
            // 长段自然切得多，短段不会被无意义地加密。
            let chord = p1.distance(to: p2)
            let steps = max(1, Int((chord / targetSpacing).rounded(.up)))

            // 从 1 开始：第 0 个点就是 p1，已经在结果里了（或是上一段的终点）。
            for step in 1 ... steps {
                let fraction = Double(step) / Double(steps)
                result.append(interpolate(p0: p0, p1: p1, p2: p2, p3: p3, fraction: fraction))
            }
        }

        return result
    }

    // MARK: 内部

    /// 去掉相邻的重合点。留着会让节点间距为 0，样条公式除零。
    private static func removingCoincidentPoints(_ points: [Point2D]) -> [Point2D] {
        guard let first = points.first else { return [] }
        var kept = [first]
        for point in points.dropFirst()
        where point.distance(to: kept[kept.count - 1]) > coincidentPointTolerance {
            kept.append(point)
        }
        return kept
    }

    /// 把 `point` 关于 `pivot` 镜像过去，用来给首尾段补一个虚拟邻居。
    private static func mirrored(_ point: Point2D, about pivot: Point2D) -> Point2D {
        Point2D(x: 2 * pivot.x - point.x, y: 2 * pivot.y - point.y)
    }

    /// 向心 Catmull-Rom 在 p1…p2 这一段上按 `fraction`（0…1）取一点。
    ///
    /// 实现按 Barry–Goldman 的三层线性插值写（A → B → C），
    /// 而不是展开成矩阵形式：这样每一步都能看出「在哪两个点之间按什么比例插」，
    /// 出问题时能逐层核对。
    private static func interpolate(
        p0: Point2D,
        p1: Point2D,
        p2: Point2D,
        p3: Point2D,
        fraction: Double
    ) -> Point2D {
        // 节点：相邻点距离的 alpha 次方累加。距离为 0 的段已在去重时排除，
        // 但镜像补出来的虚拟点仍可能与本体重合（例如整笔只有两个不同点），
        // 因此这里再挡一次，退化时退回直线插值——直线是这种情况下唯一诚实的答案。
        let d1 = knotSpan(from: p0, to: p1)
        let d2 = knotSpan(from: p1, to: p2)
        let d3 = knotSpan(from: p2, to: p3)
        guard d1 > 0, d2 > 0, d3 > 0 else {
            return Point2D.interpolate(from: p1, to: p2, fraction: fraction)
        }

        let t0 = 0.0
        let t1 = t0 + d1
        let t2 = t1 + d2
        let t3 = t2 + d3
        let t = t1 + fraction * (t2 - t1)

        let a1 = blend(p0, p1, from: t0, to: t1, at: t)
        let a2 = blend(p1, p2, from: t1, to: t2, at: t)
        let a3 = blend(p2, p3, from: t2, to: t3, at: t)
        let b1 = blend(a1, a2, from: t0, to: t2, at: t)
        let b2 = blend(a2, a3, from: t1, to: t3, at: t)
        return blend(b1, b2, from: t1, to: t2, at: t)
    }

    private static func knotSpan(from origin: Point2D, to destination: Point2D) -> Double {
        let distance = origin.distance(to: destination)
        guard distance > coincidentPointTolerance else { return 0 }
        return pow(distance, centripetalExponent)
    }

    /// 在两点之间按节点参数线性插值。
    private static func blend(
        _ start: Point2D,
        _ end: Point2D,
        from startKnot: Double,
        to endKnot: Double,
        at knot: Double
    ) -> Point2D {
        let span = endKnot - startKnot
        guard span > 0 else { return start }
        return Point2D.interpolate(from: start, to: end, fraction: (knot - startKnot) / span)
    }
}
