/// Zhang–Suen thinning for binary masks.
///
/// The algorithm removes boundary pixels in two alternating sub-iterations while preserving
/// connected one-pixel-wide structure. It never adds foreground pixels or changes dimensions.
nonisolated struct Skeletonizer: Sendable {
    func skeletonize(_ input: BinaryMask) -> BinaryMask {
        guard input.width > 0, input.height > 0, input.foregroundCount > 0 else {
            return input
        }

        // The one-pixel background frame lets original edge pixels participate in thinning while
        // keeping neighbor access simple and preserving the caller's dimensions after cropping.
        var padded = BinaryMask(width: input.width + 2, height: input.height + 2)
        for point in input.foregroundPoints {
            padded[point.x + 1, point.y + 1] = true
        }

        while true {
            let firstPass = removalCandidates(in: padded, phase: .first)
            remove(firstPass, from: &padded)

            let secondPass = removalCandidates(in: padded, phase: .second)
            remove(secondPass, from: &padded)

            if firstPass.isEmpty && secondPass.isEmpty {
                var output = BinaryMask(width: input.width, height: input.height)
                for y in 0 ..< input.height {
                    for x in 0 ..< input.width where padded[x + 1, y + 1] {
                        output[x, y] = true
                    }
                }
                return output
            }
        }
    }

    private enum Phase {
        case first
        case second
    }

    private func removalCandidates(in mask: BinaryMask, phase: Phase) -> [GridPoint] {
        var candidates: [GridPoint] = []

        for y in 1 ..< (mask.height - 1) {
            for x in 1 ..< (mask.width - 1) {
                let point = GridPoint(x: x, y: y)
                guard mask[point] else { continue }

                let neighbors = clockwiseNeighbors(of: point, in: mask)
                let foregroundNeighbors = neighbors.reduce(into: 0) { count, value in
                    count += value ? 1 : 0
                }
                guard (2 ... 6).contains(foregroundNeighbors) else { continue }
                guard zeroToOneTransitions(in: neighbors) == 1 else { continue }

                let north = neighbors[0]
                let east = neighbors[2]
                let south = neighbors[4]
                let west = neighbors[6]

                let preservesConnectivity: Bool
                switch phase {
                case .first:
                    preservesConnectivity = !(north && east && south) && !(east && south && west)
                case .second:
                    preservesConnectivity = !(north && east && west) && !(north && south && west)
                }

                if preservesConnectivity {
                    candidates.append(point)
                }
            }
        }

        return preservingAtLeastOnePixelPerComponent(candidates, in: mask)
    }

    private func preservingAtLeastOnePixelPerComponent(
        _ candidates: [GridPoint],
        in mask: BinaryMask
    ) -> [GridPoint] {
        guard !candidates.isEmpty else { return [] }

        var removable = Set(candidates)
        var unvisited = Set(mask.foregroundPoints)

        while let start = unvisited.min() {
            var component: [GridPoint] = []
            var stack = [start]
            unvisited.remove(start)

            while let point = stack.popLast() {
                component.append(point)

                for offsetY in -1 ... 1 {
                    for offsetX in -1 ... 1 where offsetX != 0 || offsetY != 0 {
                        let neighbor = GridPoint(x: point.x + offsetX, y: point.y + offsetY)
                        if mask.contains(neighbor), mask[neighbor], unvisited.remove(neighbor) != nil {
                            stack.append(neighbor)
                        }
                    }
                }
            }

            if component.allSatisfy(removable.contains), let keeper = component.min() {
                removable.remove(keeper)
            }
        }

        return candidates.filter(removable.contains)
    }

    /// P2 ... P9 in clockwise order: N, NE, E, SE, S, SW, W, NW.
    private func clockwiseNeighbors(of point: GridPoint, in mask: BinaryMask) -> [Bool] {
        [
            mask[point.x, point.y - 1],
            mask[point.x + 1, point.y - 1],
            mask[point.x + 1, point.y],
            mask[point.x + 1, point.y + 1],
            mask[point.x, point.y + 1],
            mask[point.x - 1, point.y + 1],
            mask[point.x - 1, point.y],
            mask[point.x - 1, point.y - 1],
        ]
    }

    private func zeroToOneTransitions(in neighbors: [Bool]) -> Int {
        zip(neighbors, neighbors.dropFirst() + [neighbors[0]]).reduce(into: 0) { count, pair in
            if !pair.0 && pair.1 {
                count += 1
            }
        }
    }

    private func remove(_ points: [GridPoint], from mask: inout BinaryMask) {
        for point in points {
            mask[point] = false
        }
    }
}
