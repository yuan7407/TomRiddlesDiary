import Foundation

/// Integer coordinate in a binary raster mask.
nonisolated struct GridPoint: Hashable, Comparable, Sendable {
    let x: Int
    let y: Int

    static func < (lhs: GridPoint, rhs: GridPoint) -> Bool {
        lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
    }
}

/// Compact, value-semantic foreground/background grid used by the pure stroke algorithms.
nonisolated struct BinaryMask: Equatable, Sendable {
    let width: Int
    let height: Int
    private var storage: [UInt8]

    init(width: Int, height: Int, fill: Bool = false) {
        precondition(width >= 0 && height >= 0, "Mask dimensions cannot be negative")
        self.width = width
        self.height = height
        storage = Array(repeating: fill ? 1 : 0, count: width * height)
    }

    init(width: Int, height: Int, foreground: some Sequence<GridPoint>) {
        self.init(width: width, height: height)
        for point in foreground where contains(point) {
            self[point] = true
        }
    }

    subscript(_ point: GridPoint) -> Bool {
        get {
            precondition(contains(point), "Point is outside mask bounds")
            return storage[index(of: point)] != 0
        }
        set {
            precondition(contains(point), "Point is outside mask bounds")
            storage[index(of: point)] = newValue ? 1 : 0
        }
    }

    subscript(x: Int, y: Int) -> Bool {
        get { self[GridPoint(x: x, y: y)] }
        set { self[GridPoint(x: x, y: y)] = newValue }
    }

    var foregroundCount: Int {
        storage.reduce(into: 0) { count, value in
            count += value == 0 ? 0 : 1
        }
    }

    var foregroundPoints: [GridPoint] {
        guard width > 0, height > 0 else { return [] }
        return (0 ..< height).flatMap { y in
            (0 ..< width).compactMap { x in
                let point = GridPoint(x: x, y: y)
                return self[point] ? point : nil
            }
        }
    }

    func contains(_ point: GridPoint) -> Bool {
        point.x >= 0 && point.x < width && point.y >= 0 && point.y < height
    }

    private func index(of point: GridPoint) -> Int {
        point.y * width + point.x
    }
}

/// UI-independent floating-point coordinate for traced and humanized strokes.
nonisolated struct Point2D: Equatable, Sendable {
    let x: Double
    let y: Double

    func distance(to other: Point2D) -> Double {
        hypot(other.x - x, other.y - y)
    }

    static func interpolate(from start: Point2D, to end: Point2D, fraction: Double) -> Point2D {
        Point2D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }
}

/// Ordered points that form one logical pen stroke.
nonisolated struct Polyline: Equatable, Sendable {
    let points: [Point2D]

    var length: Double {
        zip(points, points.dropFirst()).reduce(into: 0) { total, pair in
            total += pair.0.distance(to: pair.1)
        }
    }
}
