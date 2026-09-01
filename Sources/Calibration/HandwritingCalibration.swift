//
//  HandwritingCalibration.swift
//  模块：Calibration（纯逻辑；把真人笔迹量成数字，用来校准手感参数）
//
//  文件职责：从真人写的几页字里量出手感参数该是多少（计划 A10）。
//
//  ── 为什么必须有这一步 ──
//  `HandwritingFeel` 里有七个数值是**量级推算**，没有任何测量依据：
//  手抖幅度、手抖频率、书写速度、每字墨迹长度、压感起伏、转折加成、空中速度倍数、
//  抬落笔耗时。计划 A1–A8 是把**结构**改对（抖动是连续摆动而不是白噪声、
//  收笔真的收到零、起收笔有加减速……），A10 是把**数值**调对。顺序不能反：
//  在白噪声的实现上调幅度，只会调出一个「不那么难看的白噪声」。
//
//  现在结构改完了，所以这一步的条件才成立。
//
//  ── 哪些能量、哪些量不了（这一节最重要，别越过它）──
//
//  **能直接量、不需要任何额外信息的**：
//  - 手抖频率（赫兹）：残差过零的次数 ÷ 时长 ÷ 2。是个纯时间量。
//  - 抬落笔的固定耗时（秒）与空中速度倍数：对「跳跃距离 vs 笔间停顿」做直线拟合，
//    截距就是固定耗时，斜率的倒数就是空中速度；再除以落墨速度得到倍数。
//    两者都不需要知道字有多大。
//
//  **能量出绝对值，但换成「字高的比例」需要知道字有多大的**：
//  - 书写速度、手抖幅度。所以这里同时报绝对值（点 / 毫米）和按估算字高换算的比例，
//    并且把字高估算标成粗糙——它是个启发式，见 `estimatedGlyphHeight` 的说明。
//
//  **量不了的**：
//  - 压感起伏、转折加成。它们需要 force，而 USB-C 款 Apple Pencil 与第三方笔
//    经 PencilKit 都拿不到压感。这里如实报「没有力度信息」，
//    不拿速度或曲率去反推一个假压感——那会让「已校准」变成一句谎话。
//
//  ── 分析用的常量与产品参数的区别 ──
//  下面几个常量（低通窗口占比、最少样本数）是**分析方法**的一部分，不是手感参数。
//  它们不进 `HandwritingFeel`：改它们只影响「量得准不准」，不影响 App 的观感。
//

import Foundation

/// 一项测量结果：量到了什么，以及能不能用。
nonisolated enum CalibrationValue: Equatable, Sendable {
    /// 量到了。
    case measured(Double)

    /// 量不了，附上原因。**不给默认值**：给了就等于把猜测伪装成测量。
    case unmeasurable(String)

    var value: Double? {
        if case .measured(let value) = self { return value }
        return nil
    }

    /// 给控制台输出用的一行文字。
    func describe(unit: String, format: String = "%.3f") -> String {
        switch self {
        case .measured(let value):
            String(format: "\(format) \(unit)", value)
        case .unmeasurable(let reason):
            "量不了（\(reason)）"
        }
    }
}

/// 一次校准的全部结果。
nonisolated struct CalibrationReport: Equatable, Sendable {
    /// 参与统计的笔画数与笔间间隔数。样本太少的结论不可信，所以一起报出来。
    let strokeCount: Int
    let gapCount: Int

    /// 落墨总时长（秒）与墨迹总长（页面点）。
    let inkDuration: TimeInterval
    let inkLength: Double

    /// 书写速度（页面点/秒）。
    let inkSpeedInPoints: CalibrationValue

    /// 字高的粗糙估算（页面点）。见 `HandwritingCalibration.estimatedGlyphHeight`。
    let estimatedGlyphHeight: CalibrationValue

    /// 换算之前的原始值：最高四分之一笔画跨度的中位数（页面点）。
    /// 换算比例只对汉字成立，所以两个值都要报，好让人看出偏没偏。
    let rawStrokeExtent: CalibrationValue

    /// 书写速度换算成「每秒多少个字高」，对应 `HandwritingFeel.inkLengthPerSecondInReferenceScales`。
    let inkSpeedInGlyphHeights: CalibrationValue

    /// 手抖幅度（页面点），对应 `jitterAmplitudeRatio` 的分子。
    let tremorAmplitudeInPoints: CalibrationValue

    /// 手抖幅度换算成字高的比例，对应 `HandwritingFeel.jitterAmplitudeRatio`。
    let tremorAmplitudeRatio: CalibrationValue

    /// 手抖频率（赫兹），对应 `HandwritingFeel.handTremorFrequencyInHertz`。
    let tremorFrequencyInHertz: CalibrationValue

    /// 抬落笔的固定耗时（秒），对应 `HandwritingFeel.penLiftDuration`。
    let penLiftDuration: CalibrationValue

    /// 空中速度是落墨速度的几倍，对应 `HandwritingFeel.airSpeedMultipleOfInkSpeed`。
    let airSpeedMultiple: CalibrationValue

    /// 压感相关的项。硬件没有压感时全是 `unmeasurable`。
    let pressureVariation: CalibrationValue

    /// 这批笔迹里力度有没有真的在变。false 表示压感那几项注定量不了。
    let hasVaryingForce: Bool

    /// 这批数据像不像真笔写的。
    ///
    /// 判据是笔与屏幕的夹角有没有变化：手指与鼠标在 PencilKit 里报的是固定的垂直角，
    /// 真笔握着写时角度一直在变。
    ///
    /// **为什么这一条必须出现在报告里**：模拟器上只能用鼠标画，而鼠标画出来的速度、
    /// 抖动、停顿都不是人手的。拿那批数字调手感，等于把参数调到一个不存在的「人」身上，
    /// 而且调完还以为已经校准了。让报告自己说清来源，比指望人记得「这次是鼠标画的」可靠。
    let looksLikePenInput: Bool
}

nonisolated enum HandwritingCalibration {
    // MARK: 分析方法的常量（不是手感参数）

    /// 低通窗口占整笔长度的比例。
    ///
    /// 用来求「本来想画的那条线」：把笔迹沿弧长做滑动平均，平均掉的高频部分就是手抖。
    /// 取整笔的四分之一是为了避开循环论证——如果窗口取成「一个手抖波长」，
    /// 那就得先知道波长，而波长正是要量的东西之一。
    /// 取一个与笔画长度成比例的大窗口，则无论手抖多快都会被留在残差里。
    private static let lowPassWindowRatio: Double = 0.25

    /// 一项统计至少要几个样本才报结论。少于这个数就报「样本太少」，
    /// 而不是拿两三笔算个数字出来——那种数字看起来像测量，其实是噪声。
    private static let minimumSampleCount = 8

    /// 判定两点重合的容差。数值稳定性阈值。
    private static let coincidentPointTolerance: Double = 1e-9

    // MARK: 入口

    /// 分析一批真人笔迹。
    /// - Parameter traces: 按书写顺序排列的笔迹。
    static func analyze(_ traces: [PenTrace]) -> CalibrationReport {
        let usable = traces.filter { $0.samples.count > 2 && $0.duration > 0 }
        let gaps = penLiftGaps(of: traces)

        let inkDuration = usable.reduce(into: 0.0) { $0 += $1.duration }
        let inkLength = usable.reduce(into: 0.0) { $0 += $1.length }

        let speed: CalibrationValue = {
            guard usable.count >= minimumSampleCount else {
                return .unmeasurable("只有 \(usable.count) 笔，不足 \(minimumSampleCount) 笔")
            }
            guard inkDuration > 0 else { return .unmeasurable("落墨时长为 0") }
            return .measured(inkLength / inkDuration)
        }()

        let sizeEstimate = HandwritingSizeEstimator.estimate(
            from: usable.map { Polyline(points: $0.samples.map(\.point)) }
        )
        let glyphHeight: CalibrationValue = sizeEstimate.map { .measured($0.typical) }
            ?? .unmeasurable("可用笔画不足 \(HandwritingSizeEstimator.minimumStrokeCount) 笔，估不出字号")
        let rawExtent: CalibrationValue = sizeEstimate.map { .measured($0.rawStrokeExtent) }
            ?? .unmeasurable("同上")
        let tremor = tremorAmplitude(of: usable)
        let force = forceRange(of: usable)
        let hasVaryingForce = force.map { $0.upperBound > $0.lowerBound } ?? false
        let altitudes = usable.flatMap { $0.samples.map(\.altitude) }
        // 夹角完全不变就当成不是笔。用「有没有变化」而不是「等不等于 π/2」：
        // 后者要跟一个具体角度比，而那个角度是平台实现细节，不该写死在这里。
        let looksLikePenInput = (altitudes.max() ?? 0) - (altitudes.min() ?? 0) > coincidentPointTolerance

        let liftFit = fitPenLift(gaps: gaps, inkSpeed: speed.value)

        return CalibrationReport(
            strokeCount: usable.count,
            gapCount: gaps.count,
            inkDuration: inkDuration,
            inkLength: inkLength,
            inkSpeedInPoints: speed,
            estimatedGlyphHeight: glyphHeight,
            rawStrokeExtent: rawExtent,
            inkSpeedInGlyphHeights: ratio(speed, over: glyphHeight),
            tremorAmplitudeInPoints: tremor.amplitude,
            tremorAmplitudeRatio: ratio(tremor.amplitude, over: glyphHeight),
            tremorFrequencyInHertz: tremor.frequency,
            penLiftDuration: liftFit.liftDuration,
            airSpeedMultiple: liftFit.airSpeedMultiple,
            pressureVariation: hasVaryingForce
                ? .unmeasurable("这批笔迹有力度变化，但 force 的量程未公开，无法换算成 0…1 的压感")
                : .unmeasurable("这支笔没有压感（USB-C Apple Pencil 与第三方笔经 PencilKit 都拿不到）"),
            hasVaryingForce: hasVaryingForce,
            looksLikePenInput: looksLikePenInput
        )
    }

    // MARK: 字有多大

    // MARK: 手抖

    /// 手抖的幅度与频率。
    ///
    /// 做法：把每一笔沿弧长做滑动平均得到「本来想画的线」，
    /// 再看真实笔迹偏离它多少（沿法线方向的偏移）。
    /// - 幅度：全部偏移量的标准差。
    /// - 频率：偏移量沿时间过零的次数 ÷ 时长 ÷ 2（一个整周期过零两次）。
    static func tremorAmplitude(
        of traces: [PenTrace]
    ) -> (amplitude: CalibrationValue, frequency: CalibrationValue) {
        var offsets: [Double] = []
        var zeroCrossings = 0
        var totalDuration: TimeInterval = 0

        for trace in traces {
            let residual = perpendicularResidual(of: trace)
            guard residual.count > 2 else { continue }

            offsets.append(contentsOf: residual)
            zeroCrossings += residual.indices.dropFirst().count {
                (residual[$0] < 0) != (residual[$0 - 1] < 0)
            }
            totalDuration += trace.duration
        }

        guard offsets.count >= minimumSampleCount else {
            return (
                .unmeasurable("可用采样点只有 \(offsets.count) 个"),
                .unmeasurable("可用采样点只有 \(offsets.count) 个")
            )
        }

        let amplitude = standardDeviation(of: offsets)
        let frequency: CalibrationValue = totalDuration > 0
            // 一个整周期过零两次，所以除以 2。
            ? .measured(Double(zeroCrossings) / totalDuration / 2)
            : .unmeasurable("总时长为 0")

        return (.measured(amplitude), frequency)
    }

    /// 一笔相对它自己的低通版本的法线偏移。
    private static func perpendicularResidual(of trace: PenTrace) -> [Double] {
        let points = trace.samples.map(\.point)
        guard points.count > 4 else { return [] }

        // 窗口按点数算。至少 3 个点才有平均的意义。
        let window = max(3, Int(Double(points.count) * lowPassWindowRatio))
        let smoothed = movingAverage(points, window: window)

        return points.indices.compactMap { index -> Double? in
            guard index > 0, index < points.count - 1 else { return nil }

            // 法线取低通线的方向，而不是原始笔迹的方向——后者本身带着抖动，
            // 会让「偏离多少」和「往哪偏」互相污染。
            let previous = smoothed[index - 1]
            let next = smoothed[index + 1]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > coincidentPointTolerance else { return nil }

            let normal = Point2D(x: -dy / length, y: dx / length)
            let deviation = Point2D(
                x: points[index].x - smoothed[index].x,
                y: points[index].y - smoothed[index].y
            )
            return deviation.x * normal.x + deviation.y * normal.y
        }
    }

    /// 沿点序列的滑动平均。窗口在两端自动收窄，避免端点被拉向内侧。
    private static func movingAverage(_ points: [Point2D], window: Int) -> [Point2D] {
        let half = max(1, window / 2)
        return points.indices.map { index in
            let lower = max(0, index - half)
            let upper = min(points.count - 1, index + half)
            let slice = points[lower ... upper]
            let count = Double(slice.count)
            return Point2D(
                x: slice.reduce(0) { $0 + $1.x } / count,
                y: slice.reduce(0) { $0 + $1.y } / count
            )
        }
    }

    // MARK: 抬笔移动

    /// 一次抬笔：跳了多远、停了多久。
    private struct PenLiftGap {
        let distance: Double
        let duration: TimeInterval
    }

    private static func penLiftGaps(of traces: [PenTrace]) -> [PenLiftGap] {
        let ordered = traces
            .filter { !$0.samples.isEmpty }
            .sorted { $0.startedAt < $1.startedAt }

        return zip(ordered, ordered.dropFirst()).compactMap { previous, next in
            guard let from = previous.end, let to = next.start else { return nil }
            let duration = next.startedAt.timeIntervalSince(previous.endedAt)
            // 负数或非有限值只可能来自时钟跳变，不是真实停顿。
            guard duration.isFinite, duration > 0 else { return nil }
            return PenLiftGap(distance: from.distance(to: to), duration: duration)
        }
    }

    /// 对「跳跃距离 vs 停顿时长」做直线拟合：`时长 = 截距 + 距离 / 空中速度`。
    ///
    /// 截距就是抬笔离纸与落笔触纸的固定耗时（距离为 0 时仍要花的时间），
    /// 斜率的倒数就是空中速度。这正好对应引擎里那两个参数的定义，
    /// 所以量出来可以直接填进去，不需要再换算。
    ///
    /// 为什么要拟合而不是取平均：平均只能得到「平均停顿多久」，而引擎需要区分
    /// 「固定成本」和「随距离增长的部分」——同一个字里挨着的两笔和跨字的跳跃差别很大。
    private static func fitPenLift(
        gaps: [PenLiftGap],
        inkSpeed: Double?
    ) -> (liftDuration: CalibrationValue, airSpeedMultiple: CalibrationValue) {
        guard gaps.count >= minimumSampleCount else {
            let reason = "只有 \(gaps.count) 次抬笔，不足 \(minimumSampleCount) 次"
            return (.unmeasurable(reason), .unmeasurable(reason))
        }

        let n = Double(gaps.count)
        let meanX = gaps.reduce(0.0) { $0 + $1.distance } / n
        let meanY = gaps.reduce(0.0) { $0 + $1.duration } / n
        let covariance = gaps.reduce(0.0) { $0 + ($1.distance - meanX) * ($1.duration - meanY) }
        let variance = gaps.reduce(0.0) { $0 + ($1.distance - meanX) * ($1.distance - meanX) }

        guard variance > coincidentPointTolerance else {
            let reason = "所有抬笔的距离都差不多，分不出固定成本与随距离增长的部分"
            return (.unmeasurable(reason), .unmeasurable(reason))
        }

        let slope = covariance / variance
        let intercept = meanY - slope * meanX

        // 截距为负说明数据里「跳得越远反而越快」，拟合不成立（多半是停顿里混了思考时间）。
        let liftDuration: CalibrationValue = intercept > 0
            ? .measured(intercept)
            : .unmeasurable("拟合出的固定耗时是负数（\(String(format: "%.3f", intercept))s），数据里多半混了思考停顿")

        let airSpeedMultiple: CalibrationValue = {
            guard slope > coincidentPointTolerance else {
                return .unmeasurable("拟合斜率不为正，算不出空中速度")
            }
            guard let inkSpeed, inkSpeed > 0 else {
                return .unmeasurable("落墨速度未知，无法算倍数")
            }
            return .measured((1 / slope) / inkSpeed)
        }()

        return (liftDuration, airSpeedMultiple)
    }

    // MARK: 小工具

    private static func forceRange(of traces: [PenTrace]) -> ClosedRange<Double>? {
        let forces = traces.flatMap { $0.samples.map(\.force) }
        guard let low = forces.min(), let high = forces.max() else { return nil }
        return low ... high
    }

    private static func ratio(_ numerator: CalibrationValue, over denominator: CalibrationValue) -> CalibrationValue {
        guard let value = numerator.value else { return numerator }
        guard let scale = denominator.value, scale > 0 else {
            return .unmeasurable("字高未知，换不成比例")
        }
        return .measured(value / scale)
    }

    private static func standardDeviation(of values: [Double]) -> Double {
        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return variance.squareRoot()
    }
}
