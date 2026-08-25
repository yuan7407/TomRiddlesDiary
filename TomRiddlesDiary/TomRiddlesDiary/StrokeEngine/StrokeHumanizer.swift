//
//  StrokeHumanizer.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：把几何上完美的折线，变成“像人手画出来”的带压感、带节奏的笔画。
//
//  设计原因：
//  - 产品铁律：不指望大模型直接输出自然笔画。自然感必须由本地这一层负责，
//    模型只决定“画什么”，这里决定“像不像手画的”。
//  - 随机数使用固定 seed 的 SplitMix64：同一输入每次输出完全一致，
//    否则手感回归测试无法断言，问题也无法复现。
//  - 抖动刻意跳过首尾点：端点一旦漂移，相邻笔画的接头会错位、闭合图形会裂口。
//

import Foundation

/// 手绘化参数。默认值面向“较大画布上的中等速度书写”，Lab 会按夹具尺度覆盖。
nonisolated struct HumanizerConfiguration: Equatable, Sendable {
    /// 重采样间距：先把疏密不均的原始点铺成等距点，抖动和压感才不会忽强忽弱。
    var sampleSpacing: Double = 2
    var jitterAmplitude: Double = 0.6
    /// 每秒画多少长度单位，决定整体书写速度。
    var pointsPerSecond: Double = 220
    var durationVariation: Double = 0.1
    var minimumDuration: TimeInterval = 0.25
    var basePressure: Double = 0.72
    var pressureVariation: Double = 0.08
    var minimumPressure: Double = 0.12
    var maximumPressure: Double = 0.95
    /// 起笔/收笔渐细占整笔的比例，用于模拟落笔变重、收笔提起。
    var taperFraction: Double = 0.14
}

nonisolated struct StrokeHumanizer: Sendable {
    /// 手绘化一组有序笔画。
    /// - Note: 所有笔画共用同一个随机流，因此笔与笔之间的差异也可复现；
    ///         不要改成每笔重置种子，否则每笔抖动会呈现相同的规律。
    func humanize(
        _ polylines: [Polyline],
        configuration: HumanizerConfiguration = HumanizerConfiguration(),
        seed: UInt64 = 7
    ) -> StrokeSequence {
        validate(configuration)
        var random = SeededRandomNumberGenerator(seed: seed)
        // 空笔画（点数不足）直接丢弃，而不是产出零采样的笔，避免渲染层反复判空。
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
                // 端点固定：保证笔画接头与闭合图形不裂开。
                humanizedPoint = point
            } else {
                humanizedPoint = Point2D(
                    x: point.x + random.gaussian() * configuration.jitterAmplitude,
                    y: point.y + random.gaussian() * configuration.jitterAmplitude
                )
            }

            // 压感 = 受限的主体压力 × 起收笔渐细包络。
            // 先夹紧再乘包络，避免噪声把压感推到负值或超过上限。
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

        // 时长按实际长度算，长笔自然画得久；再乘一个轻微扰动，避免每笔节奏完全一致。
        let length = zip(samples, samples.dropFirst()).reduce(into: 0.0) { total, pair in
            total += pair.0.point.distance(to: pair.1.point)
        }
        let timingNoise = max(0.1, 1 + random.gaussian() * configuration.durationVariation)
        // 最小时长兜底：极短的笔如果瞬间完成，观感会像“闪现”而不是画出来。
        let duration = max(
            configuration.minimumDuration,
            length / configuration.pointsPerSecond * timingNoise
        )

        return TimedStroke(samples: samples, duration: duration)
    }

    /// 按等弧长重采样。原始折线的点可能极疏或极密，
    /// 不先规整就抖动，会让长直线几乎不抖、密集拐角抖成毛球。
    private func resample(_ input: [Point2D], spacing: Double) -> [Point2D] {
        guard let first = input.first else { return [] }

        // 先去掉重复点，否则累积长度里会出现零长段，插值时除零。
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

        // 目标距离必须包含 0 和总长，这样首尾点才会被精确保留。
        var targetDistances = [0.0]
        var nextDistance = spacing
        while nextDistance < totalLength {
            targetDistances.append(nextDistance)
            nextDistance += spacing
        }
        targetDistances.append(totalLength)

        // segmentIndex 单向前进，使整个重采样保持 O(n)，不对每个目标点重新查找。
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

    /// 起收笔包络：两端从 0 线性升到 1，中间恒为 1。
    /// 用线性而非曲线，是因为它足以表现“落笔变重、收笔提起”，且行为容易断言。
    private func taperEnvelope(at progress: Double, fraction: Double) -> Double {
        guard fraction > 0 else { return 1 }
        return min(1, min(progress / fraction, (1 - progress) / fraction))
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    /// 参数非法时直接崩在调用点，而不是静默产出畸形笔画。
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

/// SplitMix64 + Box–Muller。
/// 选它的原因：实现极短、无外部依赖、同 seed 完全可复现，
/// 而系统 RNG 无法复现，会让手感回归测试失去意义。
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

    /// 标准正态噪声。取对数前夹住下界，避免 log(0) 得到无穷。
    mutating func gaussian() -> Double {
        let first = max(unitInterval(), Double.leastNonzeroMagnitude)
        let second = unitInterval()
        return sqrt(-2 * log(first)) * cos(2 * .pi * second)
    }

    private mutating func unitInterval() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
