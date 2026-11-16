//
//  BrushShaping.swift
//  模块：StrokeEngine（纯逻辑，只依赖 Foundation）
//
//  文件职责：按「这一笔是什么笔」给它加上粗细变化——起笔顿一下，横轻竖重，撇出尖，捺有脚。
//
//  为什么要有它：
//  `StrokeHumanizer` 给每一笔的粗细只有两样东西：一条缓慢起伏的压感，和两头对称的起收笔。
//  结果每一笔都是「中间一样粗、两头一样尖」的梭子形，一页字看起来像用同一个力气画出来的线。
//  真人用钢笔写楷书不是这样：横画行笔轻、收笔要顿；竖画起笔重、往下渐细；
//  撇是一路提笔出尖；捺是先轻后重、踩出一只脚再出锋。字的「精神」大半在这里。
//
//  为什么只看笔画末段的方向：
//  字形数据（笔顺中线）里没有「这是横还是撇」的标注，只有点列。
//  而这几种笔画的区别恰好就在最后往哪个方向走：往右平走是横，往下是竖，
//  往左下是撇，往右下是捺，往上是提或钩。只看末段，折笔（横折、竖钩）也能按收笔的那一段判断。
//  这是近似：横折会被当成竖，竖钩会被当成提。近似的代价是个别笔的轻重不够讲究，
//  不会写错字——形状和笔顺完全没动。
//
//  为什么是「事后加工」而不是改 `StrokeHumanizer`：
//  Humanizer 回答「人手怎么动」（抖动、节奏、压感起伏），对所有笔画一视同仁，
//  用户自己的手写也走它。这里回答的是「楷书这种字体的笔法」，只对魂的汉字成立，
//  对拉丁字母和用户手写都不该用。分成两步，各自能单独关掉。
//
//  怎么把「粗细」写进现有的两个量：
//  渲染层的线宽 = (最轻宽度 + 压感 × 其余宽度) × 接触（见 `PageAppearance.inkWidth`）。
//  要让这一段变细，就乘到「接触」上（提笔，可以细到零）；
//  要让这一段变粗，就把「压感」抬高到刚好让线宽变成想要的倍数（按下去，最多按到满宽）。
//  所以这里需要知道「最轻宽度占满宽的比例」，由配置层传进来，和渲染层用的是同一个数。
//
//  下面 `widthFactor` 里的曲线数值是笔法模型本身的形状常数，性质和字形数据一样。
//  它们是在网页原型里对着屏幕肉眼定的，**没有真人笔迹依据**；
//  整体轻重由 `strength` 一个旋钮控制，那个旋钮在 `HandwritingFeel`。
//

import Foundation

/// 一笔按收笔方向分出的种类。
nonisolated enum BrushStrokeKind: Equatable, Sendable {
    /// 点：太短，谈不上方向。
    case dot
    /// 提、钩：最后往上走。
    case rising
    /// 撇：最后往左下走。
    case leftFalling
    /// 捺：最后往右下走。
    case rightFalling
    /// 横：最后往右平走。
    case horizontal
    /// 竖：其余的，最后往下走。
    case vertical
}

nonisolated struct BrushShapingConfiguration: Equatable, Sendable {
    /// 笔法的强弱。0 完全不改，1 是下面曲线的原样。
    var strength: Double
    /// 短于这个长度（页面点）的笔算作「点」。
    var dotLength: Double
    /// 压感最轻时，线宽占满宽的比例。必须和渲染层是同一个值。
    var lightestWidthRatio: Double
}

nonisolated enum BrushShaping {
    /// 判断方向时看笔画最后这一段（占全长的比例）。纯粹的算法常数：太短会被收笔的抖动带偏，太长会把折笔前半段算进来。
    private static let tailFraction: Double = 0.3

    /// 这一笔是什么笔。页面坐标 y 朝下。
    static func kind(of points: [Point2D], dotLength: Double) -> BrushStrokeKind {
        guard points.count >= 2 else { return .dot }
        let length = Polyline(points: points).length
        guard length >= dotLength else { return .dot }

        let tailStart = max(0, Int((Double(points.count) * (1 - tailFraction)).rounded(.down)) - 1)
        let from = points[min(tailStart, points.count - 2)]
        let to = points[points.count - 1]
        let dx = to.x - from.x
        let dy = to.y - from.y
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude > 0 else { return .dot }
        let ux = dx / magnitude
        let uy = dy / magnitude

        if uy < -0.35 { return .rising }
        if ux < -0.3, uy > 0.2 { return .leftFalling }
        if ux > 0.35, uy > 0.35 { return .rightFalling }
        if abs(uy) < 0.4, ux > 0 { return .horizontal }
        return .vertical
    }

    /// 这一笔走到 `progress`（0…1）时，线宽是平常的多少倍。
    static func widthFactor(for kind: BrushStrokeKind, at progress: Double) -> Double {
        let u = min(1, max(0, progress))
        // 起笔顿一下：开头略粗，很快回到正常。提和点、捺有自己的起笔，不用这个。
        let head = 1 + 0.2 * exp(-(u / 0.1) * (u / 0.1))
        switch kind {
        case .dot:
            return (0.85 + 0.4 * smoothStep(0, 0.6, u)) * (1 - 0.45 * smoothStep(0.75, 1, u))
        case .leftFalling:
            return head * (1 - 0.72 * smoothStep(0.3, 1, u))
        case .rightFalling:
            return (0.72 + 0.6 * smoothStep(0.15, 0.78, u)) * (1 - 0.8 * smoothStep(0.84, 1, u))
        case .horizontal:
            return head * (0.82 + 0.28 * smoothStep(0.78, 0.96, u))
        case .rising:
            return 1.12 - 0.8 * smoothStep(0.15, 1, u)
        case .vertical:
            return head * (1 - 0.38 * smoothStep(0.72, 1, u))
        }
    }

    /// 给一段字加上笔法。`plainStrokes` 里的笔（按下标）原样不动——拉丁字母和标点不是楷书。
    static func shaped(
        _ sequence: StrokeSequence,
        configuration: BrushShapingConfiguration,
        plainStrokes: Set<Int> = []
    ) -> StrokeSequence {
        precondition((0 ... 1).contains(configuration.strength), "Brush strength must be between 0 and 1")
        precondition(
            configuration.lightestWidthRatio > 0 && configuration.lightestWidthRatio < 1,
            "Lightest width ratio must be between 0 and 1"
        )
        guard configuration.strength > 0 else { return sequence }

        let lightest = configuration.lightestWidthRatio
        return StrokeSequence(strokes: sequence.strokes.enumerated().map { index, stroke in
            guard !plainStrokes.contains(index), stroke.samples.count >= 2 else { return stroke }
            let kind = kind(of: stroke.samples.map(\.point), dotLength: configuration.dotLength)
            let lastIndex = Double(stroke.samples.count - 1)
            let samples = stroke.samples.enumerated().map { sampleIndex, sample -> StrokeSample in
                let raw = widthFactor(for: kind, at: Double(sampleIndex) / lastIndex)
                let factor = 1 + (raw - 1) * configuration.strength
                if factor <= 1 {
                    // 变细 = 提笔：乘到接触上。
                    return StrokeSample(point: sample.point, pressure: sample.pressure, contact: sample.contact * factor)
                }
                // 变粗 = 按下去：把压感抬到刚好让线宽变成 factor 倍，最多按到满宽。
                let width = lightest + sample.pressure * (1 - lightest)
                let pressed = (width * factor - lightest) / (1 - lightest)
                return StrokeSample(point: sample.point, pressure: min(1, max(0, pressed)), contact: sample.contact)
            }
            return TimedStroke(samples: samples, duration: stroke.duration, pauseBefore: stroke.pauseBefore)
        })
    }

    private static func smoothStep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }
}
