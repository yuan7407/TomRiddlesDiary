import Foundation

nonisolated struct StrokeSample: Equatable, Sendable {
    let point: Point2D
    let pressure: Double
}

nonisolated struct TimedStroke: Equatable, Sendable {
    let samples: [StrokeSample]
    let duration: TimeInterval

    var length: Double {
        zip(samples, samples.dropFirst()).reduce(into: 0) { total, pair in
            total += pair.0.point.distance(to: pair.1.point)
        }
    }
}

nonisolated struct StrokeSequence: Equatable, Sendable {
    let strokes: [TimedStroke]

    var totalDuration: TimeInterval {
        strokes.reduce(into: 0) { $0 += max(0, $1.duration) }
    }
}

nonisolated struct ReplayFrame: Equatable, Sendable {
    let progressByStroke: [Double]

    var isComplete: Bool {
        progressByStroke.allSatisfy { $0 >= 1 }
    }

    var activeStrokeIndex: Int? {
        progressByStroke.firstIndex { $0 > 0 && $0 < 1 }
    }
}
