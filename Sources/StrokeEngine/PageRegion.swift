//
//  PageRegion.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：页面上的一块矩形区域，以及「这些笔画占了哪块地方」（计划 E9a）。
//
//  为什么放在 StrokeEngine 而不是排版层：
//  这里已经是 `Point2D` 与 `Polyline` 的家（`StrokeModels.swift`），排版层本来就在用它们。
//  矩形是同一族最基础的几何词汇，再开一个目录只会让「同样的东西在哪」多一个答案。
//  它同样只依赖 Foundation，门禁那条「引擎只许 import Foundation」照旧成立。
//
//  为什么不用 `CGRect`：
//  和当初不用 `CGPoint` 是同一个理由——纯算法层不该依赖 CoreGraphics，
//  否则引擎就没法脱离 Apple 平台单独测。而且 `CGRect` 允许负的宽高
//  （所谓「非标准矩形」），那种值在这里没有意义，只会让每个消费方都得先 normalize 一次。
//
//  y 向下：与全工程一致（页面坐标系原点左上）。所以 `minY` 是上边、`maxY` 是下边。
//  这一点很容易在写判断时弄反，所以下面的成员刻意叫 `top` / `bottom` 而不只叫 min/max。
//

import Foundation

/// 页面上的一块矩形区域。宽高恒为非负。
nonisolated struct PageRegion: Equatable, Sendable {
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    init(left: Double, top: Double, width: Double, height: Double) {
        // 负的宽高在这里没有任何含义。允许它进来，就等于要求每个消费方都先规范化一次，
        // 漏掉任何一处都会得到一个静默错误的相交判断。
        precondition(width >= 0, "Region width cannot be negative")
        precondition(height >= 0, "Region height cannot be negative")
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }

    var right: Double { left + width }
    var bottom: Double { top + height }
    var isEmpty: Bool { width == 0 || height == 0 }
    var area: Double { width * height }

    /// 由两个对角点构造，不要求谁在前。
    static func between(_ one: Point2D, _ other: Point2D) -> PageRegion {
        PageRegion(
            left: min(one.x, other.x),
            top: min(one.y, other.y),
            width: abs(other.x - one.x),
            height: abs(other.y - one.y)
        )
    }

    /// 这些笔画占了哪块地方——也就是「你刚写完的那句话在哪」（计划 E9a）。
    /// - Returns: 恰好框住全部采样点的矩形；没有任何点时返回 nil。
    ///   nil 而不是零矩形：「什么都没写」和「写了但占地为零」是两件事，
    ///   后者不可能发生，前者调用方必须单独处理。
    static func covering(_ polylines: [Polyline]) -> PageRegion? {
        let points = polylines.flatMap(\.points)
        guard let first = points.first else { return nil }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return PageRegion(left: minX, top: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 四周各向外撑开 `margin`。用来给已有墨迹留出「别贴着写」的余量。
    /// 负的 margin 会收缩，收到宽高为负时夹成 0——一块被收成空的区域仍然是一块空区域，
    /// 崩在这里没有意义。
    func expanded(by margin: Double) -> PageRegion {
        PageRegion(
            left: left - margin,
            top: top - margin,
            width: max(0, width + margin * 2),
            height: max(0, height + margin * 2)
        )
    }

    /// 两块区域是否有重叠。**边贴边不算重叠**：
    /// 一行字的下边缘正好等于下一行的上边缘时，它们没有真的压在一起。
    func intersects(_ other: PageRegion) -> Bool {
        left < other.right && other.left < right && top < other.bottom && other.top < bottom
    }

    /// 这块区域是否完整落在 `other` 之内。边贴边算在内。
    func isContained(in other: PageRegion) -> Bool {
        left >= other.left && right <= other.right && top >= other.top && bottom <= other.bottom
    }

    func contains(_ point: Point2D) -> Bool {
        point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
    }

    /// 把两块区域并成一块能同时框住它们的矩形。
    func union(_ other: PageRegion) -> PageRegion {
        PageRegion(
            left: min(left, other.left),
            top: min(top, other.top),
            width: max(right, other.right) - min(left, other.left),
            height: max(bottom, other.bottom) - min(top, other.top)
        )
    }
}
