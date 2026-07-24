/// Converts a one-pixel binary skeleton into deterministic ordered polylines.
///
/// Foreground pixels form an 8-connected undirected graph. Every graph edge is emitted exactly
/// once. Paths begin at endpoints/junctions first; any remaining degree-two components are closed
/// cycles. Isolated pixels are preserved as one-point strokes.
nonisolated struct StrokeTracer: Sendable {
    func trace(_ skeleton: BinaryMask) -> [Polyline] {
        let foreground = Set(skeleton.foregroundPoints)
        guard !foreground.isEmpty else { return [] }

        let degrees = Dictionary(uniqueKeysWithValues: foreground.map { point in
            (point, neighbors(of: point, in: foreground).count)
        })
        var visitedEdges: Set<PixelEdge> = []
        var paths: [[GridPoint]] = []

        let nodes = foreground
            .filter { degrees[$0] != 2 }
            .sorted { lhs, rhs in
                let lhsPriority = priority(for: degrees[lhs, default: 0])
                let rhsPriority = priority(for: degrees[rhs, default: 0])
                return lhsPriority == rhsPriority ? lhs < rhs : lhsPriority < rhsPriority
            }

        for node in nodes {
            let adjacent = neighbors(of: node, in: foreground)
            if adjacent.isEmpty {
                paths.append([node])
                continue
            }

            for neighbor in adjacent {
                let firstEdge = PixelEdge(node, neighbor)
                guard !visitedEdges.contains(firstEdge) else { continue }
                paths.append(tracePath(
                    from: node,
                    through: neighbor,
                    foreground: foreground,
                    degrees: degrees,
                    visitedEdges: &visitedEdges
                ))
            }
        }

        // Every remaining edge belongs to a component made entirely of degree-two pixels.
        while let start = firstPointWithUnvisitedEdge(in: foreground, visitedEdges: visitedEdges) {
            guard let neighbor = neighbors(of: start, in: foreground)
                .first(where: { !visitedEdges.contains(PixelEdge(start, $0)) })
            else { break }

            paths.append(tracePath(
                from: start,
                through: neighbor,
                foreground: foreground,
                degrees: degrees,
                visitedEdges: &visitedEdges
            ))
        }

        return paths.map { points in
            Polyline(points: points.map { Point2D(x: Double($0.x), y: Double($0.y)) })
        }
    }

    private func tracePath(
        from start: GridPoint,
        through firstNeighbor: GridPoint,
        foreground: Set<GridPoint>,
        degrees: [GridPoint: Int],
        visitedEdges: inout Set<PixelEdge>
    ) -> [GridPoint] {
        var path = [start]
        var previous = start
        var current = firstNeighbor
        visitedEdges.insert(PixelEdge(previous, current))
        path.append(current)

        while true {
            if current == start {
                return path
            }
            if degrees[current, default: 0] != 2 {
                return path
            }

            guard let next = neighbors(of: current, in: foreground).first(where: { candidate in
                candidate != previous && !visitedEdges.contains(PixelEdge(current, candidate))
            }) else {
                return path
            }

            visitedEdges.insert(PixelEdge(current, next))
            previous = current
            current = next
            path.append(current)
        }
    }

    private func firstPointWithUnvisitedEdge(
        in foreground: Set<GridPoint>,
        visitedEdges: Set<PixelEdge>
    ) -> GridPoint? {
        foreground.sorted().first { point in
            neighbors(of: point, in: foreground).contains { neighbor in
                !visitedEdges.contains(PixelEdge(point, neighbor))
            }
        }
    }

    private func neighbors(of point: GridPoint, in foreground: Set<GridPoint>) -> [GridPoint] {
        var result: [GridPoint] = []
        for dy in -1 ... 1 {
            for dx in -1 ... 1 where dx != 0 || dy != 0 {
                let candidate = GridPoint(x: point.x + dx, y: point.y + dy)
                if foreground.contains(candidate) {
                    result.append(candidate)
                }
            }
        }
        return result.sorted()
    }

    private func priority(for degree: Int) -> Int {
        switch degree {
        case 1: 0 // endpoints first
        case 3...: 1 // junctions next
        case 0: 2 // isolated dots
        default: 3
        }
    }
}

nonisolated private struct PixelEdge: Hashable, Sendable {
    let first: GridPoint
    let second: GridPoint

    init(_ lhs: GridPoint, _ rhs: GridPoint) {
        if lhs < rhs {
            first = lhs
            second = rhs
        } else {
            first = rhs
            second = lhs
        }
    }
}
