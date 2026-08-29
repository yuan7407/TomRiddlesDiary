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

    /// 压感起伏的波长（单位：页面点，**尺度相关**）。
    /// 从一个力度极值走到下一个极值要走多长墨迹。它比手抖的波长长得多：
    /// 手抖是 10 Hz 的震颤，而「按得多重」跟的是手臂用力，一秒变不了十次。
    var pressureWavelength: Double

    /// 转折处的压感加成（无量纲）。原路折回（180°）时压感增加这么多，
    /// 笔直处不加。急转时笔尖停留更久、墨渗得更多，所以更粗。
    var curvaturePressureGain: Double

    /// 起笔/收笔渐细占整笔的比例，用于模拟落笔变重、收笔提起。
    var taperFraction: Double

    /// 抬笔在空中移动时，速度是落墨速度的几倍（计划 A4）。
    ///
    /// 为什么用倍数而不是直接写一个空中速度：空中速度和落墨速度是同一件事的两面
    /// （同一只手在动），写成倍数就只有一个物理关系，改书写速度时它自动跟着变，
    /// 不会出现两个数打架。笔在空中比在纸上快，因为它不需要沿途描出形状。
    var airSpeedMultiple: Double

    /// 抬笔离纸与落笔触纸的固定耗时（秒），与移动距离无关。
    /// 绝对时间：这段耗时来自手腕的动作，不随字号变化。
    var penLiftDuration: TimeInterval
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

        var strokes: [TimedStroke] = []
        strokes.reserveCapacity(polylines.count)
        // 上一笔的收笔位置。用来算下一笔的抬笔移动距离（计划 A4）。
        // nil 表示还没有前一笔，也就是这是第一笔，没有抬笔移动。
        var previousEnd: Point2D?

        for polyline in polylines {
            // 空笔画（点数不足）直接丢弃，而不是产出零采样的笔，避免渲染层反复判空。
            guard var stroke = humanize(polyline, configuration: configuration, random: &random),
                  let start = stroke.samples.first?.point
            else { continue }

            if let previousEnd {
                stroke = TimedStroke(
                    samples: stroke.samples,
                    duration: stroke.duration,
                    pauseBefore: penTravelDuration(
                        from: previousEnd,
                        to: start,
                        configuration: configuration,
                        random: &random
                    )
                )
            }

            previousEnd = stroke.samples.last?.point
            strokes.append(stroke)
        }

        return StrokeSequence(strokes: strokes)
    }

    /// 笔从上一笔的收笔处抬起、移到下一笔起点、再落下所花的时间（计划 A4）。
    ///
    /// 由**距离**推出而不是拍一个固定秒数：同一个字里相邻两笔往往挨得很近，
    /// 而换到下一个字要跨过整个字宽，两者的间隔本来就该不一样。
    /// 固定秒数会让紧挨着的两笔之间出现莫名的停顿，也让跨字的跳跃显得太急。
    private func penTravelDuration(
        from origin: Point2D,
        to destination: Point2D,
        configuration: HumanizerConfiguration,
        random: inout SeededRandomNumberGenerator
    ) -> TimeInterval {
        let distance = origin.distance(to: destination)
        let airSpeed = configuration.inkLengthPerSecond * configuration.airSpeedMultiple
        let travel = configuration.penLiftDuration + distance / airSpeed

        // 复用笔画时长的那份浮动比例，不为「停顿也要有随机性」再引入一个参数——
        // 它们描述的是同一件事：人的动作在时间上不完全一致。
        let noise = max(
            Self.minimumTimingNoiseFactor,
            1 + random.gaussian() * configuration.durationVariation
        )
        return travel * noise
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

        // 压感的两个来源都必须整笔一起算，理由和抖动一样：它们沿笔画是连续的。
        // 在逐点循环里现抽随机数得到的是白噪声，线看起来像串珠（计划 A2 修的就是这个）。
        let pressureNoise = smoothPressureNoise(
            of: points,
            wavelength: configuration.pressureWavelength,
            random: &random
        )
        // 曲率在**摆动之前**的点上量：笔慢下来是因为字形本身在转弯，
        // 而不是因为手抖出来的那点弯曲。
        let turns = turnFractions(of: points)

        let samples = wobbled.enumerated().map { index, point in
            let progress = wobbled.count == 1 ? 0.5 : Double(index) / Double(wobbled.count - 1)

            // 压感 = 受限的主体压力 × 起收笔渐细包络。
            // 先夹紧再乘包络，避免噪声把压感推到负值或超过上限。
            //
            // 主体压力由三部分组成：
            // 一、基准压力；
            // 二、沿笔画缓慢起伏的噪声（人的力度不是恒定的，但也不会逐点乱跳）；
            // 三、转折加成——急转处笔尖停留更久、墨渗得更多，所以更粗。
            //    这是钢笔与毛笔写字时看得见的效果，也是拐角显得有力的原因。
            let bodyPressure = clamp(
                configuration.basePressure
                    + pressureNoise[index] * configuration.pressureVariation
                    + turns[index] * configuration.curvaturePressureGain,
                lower: configuration.minimumPressure,
                upper: configuration.maximumPressure
            )
            // 起收笔的渐细现在作用在**接触**上，不再压在压感上（计划 A5）。
            // 原来的写法是 `压感 = 下限 + (主体压感 - 下限) × 渐细`，
            // 而压感映射到线宽有 60% 的下限，所以渐细最多把线收到 60%，收不到零。
            // 分开之后压感保持它该有的范围，接触负责「笔尖离纸」这件事。
            let contact = taperEnvelope(at: progress, fraction: configuration.taperFraction)

            // `bodyPressure` 已经在上面夹进了量程内，这里不再重复夹一遍——
            // 那属于防御性堆叠：真出现越界值，问题在产生它的地方，夹住只会藏起来。
            return StrokeSample(point: point, pressure: bodyPressure, contact: contact)
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

    /// 沿笔画缓慢起伏的压感噪声（计划 A2）。
    ///
    /// 与抖动共用同一套平滑噪声，只是波长长得多：手抖是 10 Hz 的震颤，
    /// 而「按得多重」跟的是手臂的用力，一秒变不了十次。
    /// 首尾不钉 0——起收笔的压感已经由渐细包络压到最低值，不需要再钉一次。
    private func smoothPressureNoise(
        of points: [Point2D],
        wavelength: Double,
        random: inout SeededRandomNumberGenerator
    ) -> [Double] {
        let cumulative = arcLengths(of: points)
        guard let totalLength = cumulative.last, totalLength > 0 else {
            // 单点或零长笔画没有弧长可依，给一个不起伏的常量噪声。
            // 不消耗随机数，保证「同一输入同一种子结果一致」这条不被打破。
            return Array(repeating: 0, count: points.count)
        }

        return smoothNoise(
            at: cumulative,
            totalLength: totalLength,
            wavelength: wavelength,
            pinEnds: false,
            random: &random
        )
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

        // 首尾必须归零，噪声才能与「端点不许移动」平滑接合。
        let noise = smoothNoise(
            at: cumulative,
            totalLength: totalLength,
            wavelength: wavelength,
            pinEnds: true,
            random: &random
        )

        return points.enumerated().map { index, point in
            guard let normal = normalDirection(of: points, at: index) else { return point }
            let offset = noise[index] * amplitude
            return Point2D(x: point.x + normal.x * offset, y: point.y + normal.y * offset)
        }
    }

    /// 沿弧长连续变化的噪声（value noise + smoothstep）。
    ///
    /// 抖动（A1）与压感（A2）都需要「一段一段缓慢起伏」而不是逐点乱跳，
    /// 所以这段生成逻辑抽出来共用。两者的区别只是波长不同、以及要不要把首尾钉成 0。
    ///
    /// 做法：每隔一个波长取一个正态随机控制值，中间用 smoothstep 插值。
    /// smoothstep 两端斜率为 0，所以控制点的拼接处不会出现折角。
    ///
    /// - Parameters:
    ///   - cumulative: 每个点的累积弧长（由 `arcLengths(of:)` 给出）。
    ///   - totalLength: 整笔弧长。
    ///   - wavelength: 从一个极值到下一个极值的弧长。
    ///   - pinEnds: 首尾控制值是否钉成 0。抖动必须钉（端点不许移动）；
    ///     压感不需要钉（起收笔已经由渐细包络压到最低值）。
    /// - Returns: 与 `cumulative` 等长的噪声值，量级约为标准正态。
    private func smoothNoise(
        at cumulative: [Double],
        totalLength: Double,
        wavelength: Double,
        pinEnds: Bool,
        random: inout SeededRandomNumberGenerator
    ) -> [Double] {
        // 控制点按波长铺满整笔。用 `totalLength / intervalCount` 而不是直接用波长，
        // 是为了让最后一个控制点正好落在笔尾——否则末尾会剩下不完整的一段，
        // 钉首尾时收笔处的偏移就不是 0，端点不动这条规则会被破坏。
        let intervalCount = max(1, Int((totalLength / wavelength).rounded()))
        let controlSpacing = totalLength / Double(intervalCount)

        var controls = [Double](repeating: 0, count: intervalCount + 1)
        // 钉首尾时只有中间的控制点取随机值，于是短到一个波长以内的笔完全不起伏——
        // 这是对的：笔尖还没走够半个周期，本来就不该看出变化。
        let range = pinEnds ? (1 ..< max(1, intervalCount)) : (0 ..< intervalCount + 1)
        for index in range {
            controls[index] = random.gaussian()
        }

        return cumulative.map { distance in
            let position = distance / controlSpacing
            let lowerIndex = min(intervalCount - 1, max(0, Int(position.rounded(.down))))
            let fraction = min(1, max(0, position - Double(lowerIndex)))
            let eased = fraction * fraction * (3 - 2 * fraction)
            return controls[lowerIndex] + (controls[lowerIndex + 1] - controls[lowerIndex]) * eased
        }
    }

    /// 每个点处的「转折程度」，0 表示笔直，1 表示原路折回（计划 A2）。
    ///
    /// 用前后两段的夹角除以 π 归一。因为重采样已经把点铺成等弧长，
    /// 同样的夹角就代表同样的弯曲程度，这个量与字号无关。
    /// 首尾点没有前后两段可比，记为 0。
    private func turnFractions(of points: [Point2D]) -> [Double] {
        guard points.count > 2 else { return Array(repeating: 0, count: points.count) }

        return points.indices.map { index in
            guard index > 0, index < points.count - 1 else { return 0 }

            let incoming = (x: points[index].x - points[index - 1].x, y: points[index].y - points[index - 1].y)
            let outgoing = (x: points[index + 1].x - points[index].x, y: points[index + 1].y - points[index].y)

            let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
            let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
            // 用 atan2 而不是 acos(dot/|a||b|)：后者在夹角接近 0 或 π 时精度很差，
            // 而且要先算两个模长再相除，多一次可能除零。
            let angle = abs(atan2(cross, dot))
            guard angle.isFinite else { return 0 }
            return min(1, angle / .pi)
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

        // 把总长等分成整数份，而不是按固定步长一路累加、最后硬塞一个总长（计划 A8）。
        //
        // 原来的写法是「每隔 spacing 放一个点，走不到总长就停，然后再把总长补上」。
        // 问题在最后那一补：如果总长刚好只比上一个点多出一丁点，末尾就会出现一段
        // 长度接近 0 的线段。后果不只是多一个点——
        // 摆动要在那里算法线（前后两点几乎重合，方向退化）、
        // 收笔渐细要在那里判断位置（两个点几乎同一个位置却分属不同的渐细阶段）、
        // 渲染要画一段看不见的线。这些都不会报错，只会让收笔处偶发地不对劲。
        //
        // 等分之后实际间距会与请求的 spacing 略有出入，这是对的：
        // spacing 是「大约多密」的目标，不是必须精确满足的硬约束；
        // 而「首尾点精确落在笔画两端」「没有退化线段」是不能让步的。
        let stepCount = max(1, Int((totalLength / spacing).rounded()))
        let targetDistances = (0 ... stepCount).map { step in
            totalLength * Double(step) / Double(stepCount)
        }

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
        precondition(configuration.airSpeedMultiple > 0, "Air speed multiple must be positive")
        precondition(configuration.pressureWavelength > 0, "Pressure wavelength must be positive")
        precondition(configuration.curvaturePressureGain >= 0, "Curvature pressure gain cannot be negative")
        precondition(configuration.penLiftDuration >= 0, "Pen lift duration cannot be negative")
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
