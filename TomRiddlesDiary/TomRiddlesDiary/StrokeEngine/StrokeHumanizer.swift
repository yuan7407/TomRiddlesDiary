import Foundation

nonisolated struct HumanizerConfiguration: Equatable, Sendable {
    var sampleSpacing: Double = 2
    var jitterAmplitude: Double = 0.6
    var pointsPerSecond: Double = 220
    var durationVariation: Double = 0.1
    var minimumDuration: TimeInterval = 0.25
    var basePressure: Double = 0.72
    var pressureVariation: Double = 0.08
    var minimumPressure: Double = 0.12
    var maximumPressure: Double = 0.95
    var taperFraction: Double = 0.14
}

/// Adds deterministic hand variation, pressure taper, and timing to ordered polylines.
nonisolated struct StrokeHumanizer: Sendable {
    func humanize(
        _ polylines: [Polyline],
        configuration: HumanizerConfiguration = HumanizerConfiguration(),
        seed: UInt64 = 7
    ) -> StrokeSequence {
        validate(configuration)
        var random = SeededRandomNumberGenerator(seed: seed)
        let strokes = polylines.compactMap { polyline in
            humanize(polyline, configuration: configuration, random: &random)
        }
        return StrokeSequence(strokes: strokes)
    }

    private func humanize(
        _ polyline: Polyline,
        configuration: HumanizerConfiguration,
        random: inout SeededRandomNumberGenerator
    ) -> TimedStroke? {
        let points = resample(polyline.points, spacing: configuration.sampleSpacing)
        guard !points.isEmpty else { return nil }

        let lastIndex = points.index(before: points.endIndex)
        let samples = points.enumerated().map { index, point in
            let isEndpoint = index == points.startIndex || index == lastIndex
            let progress = points.count == 1 ? 0.5 : Double(index) / Double(points.count - 1)

            let humanizedPoint: Point2D
            if isEndpoint || configuration.jitterAmplitude == 0 {
                humanizedPoint = point
            } else {
                humanizedPoint = Point2D(
                    x: point.x + random.gaussian() * configuration.jitterAmplitude,
                    y: point.y + random.gaussian() * configuration.jitterAmplitude
                )
            }

            let pressureNoise = random.gaussian() * configuration.pressureVariation
            let bodyPressure = clamp(
                configuration.basePressure + pressureNoise,
                lower: configuration.minimumPressure,
                upper: configuration.maximumPressure
            )
            let taper = taperEnvelope(at: progress, fraction: configuration.taperFraction)
            let pressure = configuration.minimumPressure
                + (bodyPressure - configuration.minimumPressure) * taper

            return StrokeSample(
                point: humanizedPoint,
                pressure: clamp(
                    pressure,
                    lower: configuration.minimumPressure,
                    upper: configuration.maximumPressure
                )
            )
        }

        let length = zip(samples, samples.dropFirst()).reduce(into: 0.0) { total, pair in
            total += pair.0.point.distance(to: pair.1.point)
        }
        let timingNoise = max(0.1, 1 + random.gaussian() * configuration.durationVariation)
        let duration = max(
            configuration.minimumDuration,
            length / configuration.pointsPerSecond * timingNoise
        )

        return TimedStroke(samples: samples, duration: duration)
    }

    private func resample(_ input: [Point2D], spacing: Double) -> [Point2D] {
        guard let first = input.first else { return [] }

        var points = [first]
        for point in input.dropFirst() where point.distance(to: points[points.count - 1]) > 1e-9 {
            points.append(point)
        }
        guard points.count > 1 else { return points }

        var cumulative = [0.0]
        for pair in zip(points, points.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + pair.0.distance(to: pair.1))
        }
        guard let totalLength = cumulative.last, totalLength > 0 else { return [first] }

        var targetDistances = [0.0]
        var nextDistance = spacing
        while nextDistance < totalLength {
            targetDistances.append(nextDistance)
            nextDistance += spacing
        }
        targetDistances.append(totalLength)

        var segmentIndex = 0
        return targetDistances.map { target in
            while segmentIndex < cumulative.count - 2 && cumulative[segmentIndex + 1] < target {
                segmentIndex += 1
            }

            let startDistance = cumulative[segmentIndex]
            let endDistance = cumulative[segmentIndex + 1]
            let segmentLength = endDistance - startDistance
            let fraction = segmentLength > 0 ? (target - startDistance) / segmentLength : 0
            return Point2D.interpolate(
                from: points[segmentIndex],
                to: points[segmentIndex + 1],
                fraction: fraction
            )
        }
    }

    private func taperEnvelope(at progress: Double, fraction: Double) -> Double {
        guard fraction > 0 else { return 1 }
        return min(1, min(progress / fraction, (1 - progress) / fraction))
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    private func validate(_ configuration: HumanizerConfiguration) {
        precondition(configuration.sampleSpacing > 0, "Sample spacing must be positive")
        precondition(configuration.jitterAmplitude >= 0, "Jitter cannot be negative")
        precondition(configuration.pointsPerSecond > 0, "Drawing speed must be positive")
        precondition(configuration.durationVariation >= 0, "Duration variation cannot be negative")
        precondition(configuration.minimumDuration >= 0, "Minimum duration cannot be negative")
        precondition(configuration.pressureVariation >= 0, "Pressure variation cannot be negative")
        precondition(configuration.minimumPressure >= 0, "Minimum pressure cannot be negative")
        precondition(configuration.maximumPressure >= configuration.minimumPressure, "Pressure bounds are invalid")
        precondition((0 ... 0.5).contains(configuration.taperFraction), "Taper fraction must be between 0 and 0.5")
    }
}

nonisolated private struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func gaussian() -> Double {
        let first = max(unitInterval(), Double.leastNonzeroMagnitude)
        let second = unitInterval()
        return sqrt(-2 * log(first)) * cos(2 * .pi * second)
    }

    private mutating func unitInterval() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
