//
//  SpreadGeometry.swift
//  模块：Spread（「对开」的纯逻辑层，只依赖 Foundation）
//
//  文件职责：一块能对折的屏幕上，两页纸各在哪里、折缝在哪里；
//  以及怎样让现有的落点决策不把一段话横跨在折缝上。
//
//  为什么不重写落点决策：
//  `ReplyPlacementFinder` 已经会「挨着你那句话的右边或下方，放不下就从页顶往下找」，
//  它靠一张占用图（`PageInkMap`）判断哪里有空。折缝在它眼里只需要是「已经有墨的地方」：
//  把折缝那一条标成占用，现有的规则就自然不会跨缝——向右的候选撞到折缝就失败，
//  改试下方；从页顶往下扫的时候两页都会被试到。
//  这样换行规则、间距规则都还是原来那一份（决策 52、57–59），没有新增第二条路径。
//
//  折缝的位置从哪来：真机上由系统给（iOS 27.1 的 `GeometryProxy.reservedRegions(kind: .division)`），
//  界面层读出来传进这里。没有折缝（普通 iPhone、iPad，或者合着用外屏）时 `fold` 为 nil，
//  整块屏幕就是一页，行为和原来完全一样。
//

import Foundation

nonisolated struct SpreadGeometry: Equatable, Sendable {
    enum Side: Equatable, Sendable {
        /// 折缝之前的那一页：竖折时是左页，横折（像小电脑那样立着）时是上页。
        case leading
        /// 折缝之后的那一页：竖折时是右页，横折时是下页。
        case trailing
    }

    let bounds: PageRegion
    /// 折缝占掉的那一条。nil 表示没有折缝。
    let fold: PageRegion?

    init(bounds: PageRegion, fold: PageRegion?) {
        self.bounds = bounds
        // 折缝完全在屏幕之外、或者是空的，都当作没有。
        if let fold, !fold.isEmpty, fold.intersects(bounds) {
            self.fold = fold
        } else {
            self.fold = nil
        }
    }

    var hasFold: Bool { fold != nil }

    /// 折缝是竖着的（把屏幕分成左右两页）还是横着的（分成上下两页）。没有折缝时为 nil。
    var foldIsVertical: Bool? {
        fold.map { $0.width <= $0.height }
    }

    /// 某一侧的那页纸。没有折缝时两侧都是整块屏幕。
    func page(_ side: Side) -> PageRegion {
        guard let fold, let vertical = foldIsVertical else { return bounds }
        switch (side, vertical) {
        case (.leading, true):
            return PageRegion(left: bounds.left, top: bounds.top, width: max(0, fold.left - bounds.left), height: bounds.height)
        case (.trailing, true):
            return PageRegion(left: fold.right, top: bounds.top, width: max(0, bounds.right - fold.right), height: bounds.height)
        case (.leading, false):
            return PageRegion(left: bounds.left, top: bounds.top, width: bounds.width, height: max(0, fold.top - bounds.top))
        case (.trailing, false):
            return PageRegion(left: bounds.left, top: fold.bottom, width: bounds.width, height: max(0, bounds.bottom - fold.bottom))
        }
    }

    /// 一个点落在哪一页。落在折缝里、或者没有折缝时返回 nil。
    func side(containing point: Point2D) -> Side? {
        guard hasFold else { return nil }
        if page(.leading).contains(point) { return .leading }
        if page(.trailing).contains(point) { return .trailing }
        return nil
    }

    /// 一片笔迹主要在哪一页（看它的中心）。没有折缝时返回 nil。
    func side(of writing: PageRegion) -> Side? {
        guard let fold, let vertical = foldIsVertical else { return nil }
        if vertical {
            return writing.left + writing.width / 2 < fold.left + fold.width / 2 ? .leading : .trailing
        }
        return writing.top + writing.height / 2 < fold.top + fold.height / 2 ? .leading : .trailing
    }

    /// 把折缝画成一排密密的线，交给 `PageInkMap.mark(_:)`，让占用图把那一条当成有墨。
    ///
    /// - Parameter spacing: 相邻两条线的间距。传占用图的格子边长即可：线距不超过格子边长，
    ///   折缝覆盖到的每一格就都会被标到。没有折缝时返回空。
    func foldBarrier(spacing: Double) -> [Polyline] {
        guard let fold, let vertical = foldIsVertical, spacing > 0 else { return [] }
        var lines: [Polyline] = []
        let span = vertical ? fold.width : fold.height
        let count = max(1, Int((span / spacing).rounded(.up)))
        for index in 0 ... count {
            let offset = min(span, Double(index) * spacing)
            if vertical {
                let x = fold.left + offset
                lines.append(Polyline(points: [Point2D(x: x, y: fold.top), Point2D(x: x, y: fold.bottom)]))
            } else {
                let y = fold.top + offset
                lines.append(Polyline(points: [Point2D(x: fold.left, y: y), Point2D(x: fold.right, y: y)]))
            }
        }
        return lines
    }
}
