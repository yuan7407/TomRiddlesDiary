@testable import TomRiddlesDiary
import XCTest

nonisolated enum MaskFixtures {
    static func mask(_ rows: [String]) -> BinaryMask {
        let width = rows.map(\.count).max() ?? 0
        precondition(rows.allSatisfy { $0.count == width }, "ASCII mask rows must have equal widths")

        var mask = BinaryMask(width: width, height: rows.count)
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() where character == "#" {
                mask[x, y] = true
            }
        }
        return mask
    }

    static func isEightConnected(_ mask: BinaryMask) -> Bool {
        guard let first = mask.foregroundPoints.first else { return true }
        var visited: Set<GridPoint> = [first]
        var queue = [first]

        while !queue.isEmpty {
            let point = queue.removeFirst()
            for dy in -1 ... 1 {
                for dx in -1 ... 1 where dx != 0 || dy != 0 {
                    let neighbor = GridPoint(x: point.x + dx, y: point.y + dy)
                    if mask.contains(neighbor), mask[neighbor], visited.insert(neighbor).inserted {
                        queue.append(neighbor)
                    }
                }
            }
        }

        return visited.count == mask.foregroundCount
    }
}
