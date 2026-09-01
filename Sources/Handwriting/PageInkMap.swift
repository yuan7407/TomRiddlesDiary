//
//  PageInkMap.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：记录这一页**哪里已经有墨了**，并回答「这块矩形是空的吗」（计划 E9b）。
//
//  ── 为什么必须有它 ──
//  用户定的版式是「回应排在刚写完那句话旁边，找个空位」。要找空位，先得知道哪里不空。
//  在此之前工程里没有任何东西记录这件事：用户的笔画在 `PKDrawing` 里，
//  魂写过的回应在另一个数组里，两者从没合起来看过。
//  没有它，接上 Oracle 之后回应只能压在用户的字上——那正是之前截图里看到的问题。
//
//  ── 为什么用粗格子而不是精确几何 ──
//  要回答的问题是「这块地方放得下一段话吗」，不是「这两条线相交吗」。
//  精确几何要做几百条折线与矩形的求交，慢且没必要；
//  而按笔画的包围盒判断又太粗——一条斜撇的包围盒会把一大片空白也标成占用，
//  于是本来放得下的位置被判成放不下。
//  粗格子（把页面切成小方块，标记哪些方块碰到过墨）在这两者之间，
//  而且「这块矩形空不空」只是查一片格子，代价固定。
//
//  ── 两个尺寸都不是拍的 ──
//  格子大小与预留间距都从**字高**推出（见 `Resolution`），因为这张图的唯一用途
//  就是判断「一个字放不放得下」。字高变了它们自动跟着变，不需要第二处调参。
//
//  ── 已知的取舍 ──
//  格子是保守的：一条线只要碰到格子的一个角，整个格子就算占用。
//  所以它**宁可说放不下，也不会说放得下却实际压字**。方向是对的——
//  误判成「放不下」的代价是回应挪到别处，误判成「放得下」的代价是字压在一起。
//

import Foundation

nonisolated struct PageInkMap: Equatable, Sendable {
    /// 格子的尺寸与预留间距，全部由字高推出。
    nonisolated struct Resolution: Equatable, Sendable {
        /// 一个字高切成几格。
        ///
        /// 取 2：格子比一个字的一半还小就没意义了（放不下半个字），
        /// 比一个字还大又会把字与字之间的空隙整格吞掉。
        static let cellsPerGlyph: Double = 2

        /// 已有墨迹向外撑开多少，作为「别贴着写」的余量。
        ///
        /// **不是新参数**：直接用行距留出的那道空隙。行距是字高的
        /// `lineSpacingRatio` 倍，所以两行之间的空隙是 `(ratio - 1)` 个字高。
        /// 回应与用户笔迹之间留同样宽的空隙，看起来才像同一页上自然的两段文字，
        /// 而不是一段被硬塞进来的东西。
        static func clearance(glyphHeight: Double, lineSpacingRatio: Double) -> Double {
            glyphHeight * max(0, lineSpacingRatio - 1) / 2
        }

        let cellSize: Double
        let clearance: Double

        init(glyphHeight: Double, lineSpacingRatio: Double) {
            precondition(glyphHeight > 0, "Glyph height must be positive")
            cellSize = glyphHeight / Self.cellsPerGlyph
            clearance = Self.clearance(glyphHeight: glyphHeight, lineSpacingRatio: lineSpacingRatio)
        }
    }

    /// 整页范围。落在它之外的东西一律不算（也不该出现）。
    let page: PageRegion

    let resolution: Resolution

    private let columns: Int
    private let rows: Int
    private var occupied: [Bool]

    /// 建一张空的占用图。
    init(page: PageRegion, resolution: Resolution) {
        precondition(page.width > 0 && page.height > 0, "Page must have a positive size")
        self.page = page
        self.resolution = resolution
        // 向上取整：宁可多留一行一列，也不要页面右下角落在格子外面而无人覆盖。
        columns = max(1, Int((page.width / resolution.cellSize).rounded(.up)))
        rows = max(1, Int((page.height / resolution.cellSize).rounded(.up)))
        occupied = Array(repeating: false, count: columns * rows)
    }

    /// 把一批笔画标成已占用。
    ///
    /// 逐段标而不是只标采样点：采样点之间可能隔着好几个格子（字形数据的中线很稀），
    /// 只标点会在长直线中间留下一串「空」格子，于是回应会被放到一条横线的正中间。
    mutating func mark(_ polylines: [Polyline]) {
        for polyline in polylines {
            guard let first = polyline.points.first else { continue }
            guard polyline.points.count > 1 else {
                mark(point: first)
                continue
            }
            for (start, end) in zip(polyline.points, polyline.points.dropFirst()) {
                mark(segmentFrom: start, to: end)
            }
        }
    }

    /// 这块矩形是不是完全空的（含预留间距）。
    ///
    /// - Note: 查询时把矩形按 `clearance` 撑开——回应不能贴着已有的墨写。
    ///   撑开放在查询这一侧而不是标记那一侧，是因为同一张图还要回答别的问题
    ///   （例如将来判断「整页写满了吗」），标记时就撑开会让那些判断也被迫带上余量。
    func isFree(_ region: PageRegion) -> Bool {
        let padded = region.expanded(by: resolution.clearance)
        guard let span = cellSpan(of: padded) else { return false }

        for row in span.rows {
            for column in span.columns where occupied[row * columns + column] {
                return false
            }
        }
        return true
    }

    /// 这块矩形放不放得下——既要在页内，也要空着。
    /// 合成一个方法是因为两个条件漏掉任何一个都会让回应跑到纸外或压到字上。
    func canPlace(_ region: PageRegion) -> Bool {
        region.isContained(in: page) && isFree(region)
    }

    /// 已占用的格子占全页的比例。用来判断「这一页是不是快写满了」（服务于计划 E3f 翻页）。
    var occupancy: Double {
        guard !occupied.isEmpty else { return 0 }
        return Double(occupied.count { $0 }) / Double(occupied.count)
    }

    // MARK: 内部

    /// 一块矩形覆盖到的格子范围。完全落在页外时返回 nil。
    private func cellSpan(of region: PageRegion) -> (columns: Range<Int>, rows: Range<Int>)? {
        let lowColumn = Int(((region.left - page.left) / resolution.cellSize).rounded(.down))
        let highColumn = Int(((region.right - page.left) / resolution.cellSize).rounded(.down))
        let lowRow = Int(((region.top - page.top) / resolution.cellSize).rounded(.down))
        let highRow = Int(((region.bottom - page.top) / resolution.cellSize).rounded(.down))

        let clampedColumns = max(0, lowColumn) ..< min(columns, highColumn + 1)
        let clampedRows = max(0, lowRow) ..< min(rows, highRow + 1)
        guard !clampedColumns.isEmpty, !clampedRows.isEmpty else { return nil }
        return (clampedColumns, clampedRows)
    }

    private mutating func mark(point: Point2D) {
        let column = Int(((point.x - page.left) / resolution.cellSize).rounded(.down))
        let row = Int(((point.y - page.top) / resolution.cellSize).rounded(.down))
        guard (0 ..< columns).contains(column), (0 ..< rows).contains(row) else { return }
        occupied[row * columns + column] = true
    }

    /// 沿一段线均匀取点并标记。
    ///
    /// 步长取格子的一半：这样即使线段斜着穿过格子的角，也不会跳过整个格子。
    /// 取格子大小本身就可能漏——一步刚好跨过一个格子对角的情况是存在的。
    private mutating func mark(segmentFrom start: Point2D, to end: Point2D) {
        let distance = start.distance(to: end)
        let step = resolution.cellSize / 2
        let count = max(1, Int((distance / step).rounded(.up)))

        for index in 0 ... count {
            mark(point: Point2D.interpolate(
                from: start,
                to: end,
                fraction: Double(index) / Double(count)
            ))
        }
    }
}
