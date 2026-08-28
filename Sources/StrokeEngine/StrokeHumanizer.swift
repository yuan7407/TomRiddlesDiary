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
//
//  ── 抖动：为什么是「沿笔画的连续摆动」而不是逐点随机（计划 A1，2026-08-29）──
//
//  原实现给每个采样点各加一个独立的正态随机数。那不是手抖，那是白噪声：
//  相邻两点的偏移毫无关系，于是线条边缘变成锯齿状的毛刺。实机截图上看得很清楚，
//  而且因为难看，抖动幅度只能被压到很小（0.018 字高），等于这个功能形同虚设。
//
//  真实的手抖是**连续的**：手在写的过程中缓慢地偏离理想路径再摆回来，
//  笔画整体是弯的，而不是每一点各自跳一下。所以改成：
//
//  一、噪声沿**弧长**平滑变化。做法是每隔一个波长取一个随机控制值，
//      中间用平滑插值（smoothstep）连起来——也就是常说的 value noise。
//      首尾控制值强制为 0，噪声因此自然从零开始、回到零结束，
//      端点不动这条规则不需要额外特判就成立（端点漂移会让笔画接头错位、闭合图形裂口）。
//  二、偏移方向是笔画的**法线**（垂直于行进方向），不是各自独立的 x 和 y。
//      沿切线方向推点只会改变点的疏密，看不出来；垂直方向推才会把线掰弯，
//      那才是手抖的样子。局部速度变化属于加减速（计划 A3），不在这里伪造。
//
//  波长不是拍出来的：见 `HandwritingFeel.handTremorFrequencyInHertz`，
//  它由「人的生理性手抖频率」与「书写速度」推出。
//

import Foundation

/// 手绘化参数。
///
/// 单位契约（2026-08-27 建立，计划 D1）：
/// 前三个字段是**尺度相关**的，单位一律是「页面点」，必须由调用方按参照尺度算出。
/// 其余字段无量纲或是绝对时间，与尺度无关。
///
/// 刻意不提供任何默认值。原因：历史上这里有一套默认值，调用方又有另一套，
/// 而默认那套从未对真实内容验证过，长期是死参数；同时因为参数是尺度相关的，
/// 任何默认值都只在某个特定画布尺寸下成立。现在唯一的生产来源是
/// `HandwritingFeel.humanizerConfiguration(referenceScale:)`，构造时必须交代尺度。
nonisolated struct HumanizerConfiguration: Equatable, Sendable {
    // MARK: 尺度相关（单位：页面点）

    /// 重采样间距。先把疏密不均的原始点铺成等距点，抖动和压感才不会忽强忽弱。
    var sampleSpacing: Double

    /// 手抖幅度（标准差），沿笔画法线方向的偏移量。
    var jitterAmplitude: Double

    /// 手抖波长：笔尖走过这么长的墨迹，抖动才从一个极值摆到下一个极值。
    ///
    /// 它决定「抖得粗还是抖得细」：波长远大于采样间距时线条是缓弯（像手抖），
    /// 波长接近采样间距时就退化成毛刺（就是 A1 之前的样子）。
    /// 因此它必须比 `sampleSpacing` 大若干倍才有意义。
    var jitterWavelength: Double

    /// 每秒画过的墨迹长度，决定书写速度。
    /// 名字刻意写明「墨迹长度」：旧名 `pointsPerSecond` 会被误读成「每秒多少个采样点」，
    /// 而它实际是「每秒多少个长度单位」。
    var inkLengthPerSecond: Double

    // MARK: 无量纲比例与绝对时间

    /// 每笔时长的随机浮动比例，避免所有笔节奏完全一致。
    var durationVariation: Double

    /// 单笔最短时长（秒）。时间不随字号变化，因此是绝对值。
    var minimumDuration: TimeInterval

    var basePressure: Double
    var pressureVariation: Double
    var minimumPressure: Double
    var maximumPressure: Double

    /// 起笔/收笔渐细占整笔的比例，用于模拟落笔变重、收笔提起。
    var taperFraction: Double
}

nonisolated struct StrokeHumanizer: Sendable {
    /// 时长扰动的下限系数。属算法安全下界（防止时长被噪声压到接近 0），不是手感参数。
    private static let minimumTimingNoiseFactor: Double = 0.1

    /// 判定两点重合的容差。重复点会在累积长度里产生零长段，插值时除零。
    /// 这是数值稳定性阈值，不是手感参数。
    private static let coincidentPointTolerance: Double = 1e-9

    /// 手绘化一组有序笔画。
    /// - Note: 所有笔画共用同一个随机流，因此笔与笔之间的差异也可复现；
    ///         不要改成每笔重置种子，否则每笔抖动会呈现相同的规律。
    func humanize(
        _ polylines: [Polyline],
        configuration: HumanizerConfiguration,
        seed: UInt64
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

        // 抖动先整笔算好再逐点用：它是沿弧长的一条连续曲线，不能在逐点循环里
        // 现抽随机数——那样得到的必然是白噪声。
        let wobbled = wobble(
            points,
            amplitude: configuration.jitterAmplitude,
            wavelength: configuration.jitterWavelength,
            random: &random
        )

        let samples = wobbled.enumerated().map { index, point in
            let progress = wobbled.count == 1 ? 0.5 : Double(index) / Double(wobbled.count - 1)

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
                point: point,
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
        // 时长扰动的下限：噪声再大也不能把时长压成接近 0，否则那一笔会“闪现”。
        // 这是算法自身的安全下界，不是可调手感，故留在此处而不进配置。
        let timingNoise = max(Self.minimumTimingNoiseFactor, 1 + random.gaussian() * configuration.durationVariation)
        // 最小时长兜底：极短的笔如果瞬间完成，观感会像“闪现”而不是画出来。
        let duration = max(
            configuration.minimumDuration,
            length / configuration.inkLengthPerSecond * timingNoise
        )

        return TimedStroke(samples: samples, duration: duration)
    }

    /// 让一笔沿法线方向缓慢摆动，模拟手抖（计划 A1）。
    ///
    /// - Parameters:
    ///   - points: 已等弧长重采样的点。
    ///   - amplitude: 摆动幅度（标准差）。为 0 时原样返回。
    ///   - wavelength: 摆动波长，见 `HumanizerConfiguration.jitterWavelength`。
    /// - Returns: 摆动后的点。首尾点必然与输入完全相同。
    private func wobble(
        _ points: [Point2D],
        amplitude: Double,
        wavelength: Double,
        random: inout SeededRandomNumberGenerator
    ) -> [Point2D] {
        // 少于三个点时没有「法线」可言（两点只能定义一条直线，动了就等于动端点），
        // 幅度为 0 时也没必要走这一遭。两种情况都原样返回，不消耗随机数。
        guard amplitude > 0, points.count > 2 else { return points }

        let cumulative = arcLengths(of: points)
        guard let totalLength = cumulative.last, totalLength > 0 else { return points }

        // 控制点按波长铺满整笔。用 `totalLength / intervalCount` 而不是直接用波长，
        // 是为了让最后一个控制点正好落在笔尾——否则末尾会剩下不完整的一段，
        // 收笔处的偏移就不是 0，端点不动这条规则会被破坏。
        let intervalCount = max(1, Int((totalLength / wavelength).rounded()))
        let controlSpacing = totalLength / Double(intervalCount)

        // 首尾控制值留 0：噪声从零起、回到零收，与固定端点平滑接合。
        // 只有中间的控制点消耗随机数，所以短到一个波长以内的笔画完全不抖——
        // 这是对的：笔尖还没走够半个摆动周期，本来就不该看出弯。
        var controls = [Double](repeating: 0, count: intervalCount + 1)
        for index in 1 ..< max(1, intervalCount) {
            controls[index] = random.gaussian()
        }

        return points.enumerated().map { index, point in
            guard let normal = normalDirection(of: points, at: index) else { return point }

            let position = cumulative[index] / controlSpacing
            let lowerIndex = min(intervalCount - 1, max(0, Int(position.rounded(.down))))
            let fraction = min(1, max(0, position - Double(lowerIndex)))
            // smoothstep：两端斜率为 0，因此拼接处不会出现折角。
            let eased = fraction * fraction * (3 - 2 * fraction)
            let offset = (controls[lowerIndex] + (controls[lowerIndex + 1] - controls[lowerIndex]) * eased)
                * amplitude

            return Point2D(x: point.x + normal.x * offset, y: point.y + normal.y * offset)
        }
    }

    /// 每个点到笔画起点的累积弧长。
    private func arcLengths(of points: [Point2D]) -> [Double] {
        var cumulative = [0.0]
        cumulative.reserveCapacity(points.count)
        for pair in zip(points, points.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + pair.0.distance(to: pair.1))
        }
        return cumulative
    }

    /// 第 index 点处的单位法线（垂直于行进方向）。
    ///
    /// 方向取前后两点的中心差分，这样拐角处的法线是两侧的折中，不会突然翻转。
    /// 首尾点返回 nil——它们不许移动。
    /// 前后两点重合（尖锐回折）时方向退化，也返回 nil：宁可这一点不抖，
    /// 也不拿一个没有意义的方向硬推。
    private func normalDirection(of points: [Point2D], at index: Int) -> Point2D? {
        guard index > 0, index < points.count - 1 else { return nil }

        let previous = points[index - 1]
        let next = points[index + 1]
        let dx = next.x - previous.x
        let dy = next.y - previous.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > Self.coincidentPointTolerance else { return nil }

        // 逆时针旋转 90°：(dx, dy) → (-dy, dx)。
        return Point2D(x: -dy / length, y: dx / length)
    }

    /// 按等弧长重采样。原始折线的点可能极疏或极密，
    /// 不先规整就抖动，会让长直线几乎不抖、密集拐角抖成毛球。
    private func resample(_ input: [Point2D], spacing: Double) -> [Point2D] {
        guard let first = input.first else { return [] }

        // 先去掉重复点，否则累积长度里会出现零长段，插值时除零。
        var points = [first]
        for point in input.dropFirst()
        where point.distance(to: points[points.count - 1]) > Self.coincidentPointTolerance {
            points.append(point)
        }
        guard points.count > 1 else { return points }

        let cumulative = arcLengths(of: points)
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
        // 波长必须大于采样间距，否则抖动会退化成逐点毛刺——那正是 A1 要修掉的东西。
        // 崩在这里而不是画出难看的线：毛刺在小字号下不容易看出来，会悄悄留下去。
        precondition(
            configuration.jitterAmplitude == 0 || configuration.jitterWavelength > configuration.sampleSpacing,
            "Jitter wavelength must exceed sample spacing, otherwise the wobble degrades into per-point burr"
        )
        precondition(configuration.inkLengthPerSecond > 0, "Ink length per second must be positive")
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
