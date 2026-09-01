//
//  HandwritingSizeEstimate.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：从用户自己的笔画估出「他的字有多大」（计划 E9c）。
//
//  ── 为什么产品需要这个，而不只是开发期需要 ──
//  魂写的字应该和用户的字**一样大**。字号不匹配会立刻破坏「同一支笔写的」这个错觉：
//  你写 6 mm 的小字，魂回一段 9 mm 的大字，那看起来像两个人在同一页上写东西。
//  所以字号不能是配置里那个固定值，必须跟着用户走。
//
//  它同时也是「回应排在哪」这条链的第一环（计划 E9d 的试排需要知道字多大才能算占多少地方）。
//
//  ── 估算办法 ──
//  两步：
//  一、取纵向跨度最大的那四分之一笔画，求它们跨度的中位数。
//     取最高的四分之一是为了避开点、短横这些天生很矮的笔画；
//     取中位数而不是平均，是为了让一笔特别夸张的连笔带不跑结论。
//  二、把这个中位数**除以一个换算比例**得到字高。这一步不能省：
//     单笔的纵向跨度远小于整个字的高度（一个字里很少有笔画从顶贯到底），
//     不换算会把字号估到实际的一半。
//
//  ── 那个换算比例是**量出来的，不是拍的** ──
//  用打包的字形笔顺数据当标准答案：那份数据的字面方格恰好是 1.0，
//  所以在它上面按上面第一步算出来的数，本身就是「跨度 ÷ 字高」这个比例。
//  实测七句真实长度的中文（7–23 字）：0.466 / 0.477 / 0.487 / 0.494 / 0.513 / 0.524 / 0.542，
//  中位数 0.49，波动很小。只有一两个字的样本会跳到 0.24 或 0.63，
//  而那种样本本来就被 `minimumStrokeCount` 挡掉了。
//  这个比例由 `HandwritingSizeEstimateTests` 从真实字形数据重新量一遍并断言，
//  所以它是被机器盯着的，不是一句注释里的声明。
//
//  ── 局限（2026-08-31 实测暴露，比原先估计的严重得多）──
//  用户在模拟器上写了一页（"hi" / 一个大涂鸦 / "i love you" / "你好" / 一个心形），
//  实际字高目测 90 点左右，这里估出 **251.5 点，约 2.5 倍**。
//
//  原因不只一个，而且都指向同一件事——0.49 这个比例只对**汉字**成立：
//  - **汉字与拉丁字母的构造不同。** 汉字由许多短笔画拼成，单笔很少从顶贯到底；
//    而人写拉丁字母时一个 l、y、h 往往一笔就跨过整个字高。所以同样的「最高四分之一
//    笔画跨度」，在汉字上约占字高的一半，在手写拉丁上接近全高。
//  - **涂鸦不是字。** 那个大涂鸦和心形在算法眼里就是「很高的笔画」，直接进了最高那批。
//  - 用打包字形数据量出的拉丁比例（0.55…0.64）也代表不了真人手写的拉丁：
//    那批字形是我自己按印刷体写的，笔画比人手写的短。
//
//  **所以这个估算目前还不能用来决定魂的字号。** 2.5 倍的偏差会让魂写出一页
//  明显过大的字，那比用固定字号更糟。它现在只作诊断值，报告里同时给出**原始跨度**
//  与换算值，并注明换算只对汉字成立，好让人一眼看出偏没偏。
//
//  已想到的修法（等真人笔迹与可用的识别结果，属计划 A10/E9c 续做）：
//  「每字几笔」能把两种文字分开——汉字五到十几笔一个字，拉丁一两笔一个字，
//  而成页时笔画数与认出的字数都是现成的。两个端点的比例都能量，中间插值。
//  但它依赖识别可用，而模拟器上中文识别本身就是坏的，所以现在做不了验证。
//
//  ── 样本不够时不猜 ──
//  少于 `minimumStrokeCount` 笔就返回 nil，由调用方回退到配置里的默认字高**并且知道
//  自己在回退**。返回一个「用三笔算出来的字号」是最坏的做法：它看起来像测量，
//  而魂会照着它写出一页大小离谱的字，没人知道为什么。
//

import Foundation

/// 用户手写字号的估算结果。
nonisolated struct HandwritingSizeEstimate: Equatable, Sendable {
    /// 典型字高（页面点）。魂写字时用这个。
    let typical: Double

    /// 近似范围（页面点），已按同一比例换算成字高。
    ///
    /// 它是「参与统计的那批**高笔画**彼此差多少」，也就是典型值稳不稳。
    /// **它不能用来判断这一页是不是大小字混写**——混写时最高的那批仍然彼此一致，
    /// 范围照样很窄。想知道混没混写要看整体分布，这里没做，因为产品用不到。
    let range: ClosedRange<Double>

    /// 参与统计的笔画数。太少的结论不可信，所以一起报出来。
    let sampleCount: Int

    /// 换算之前的原始值：最高四分之一笔画跨度的中位数（页面点）。
    ///
    /// 为什么要把它一起报出来：换算比例只对汉字成立（见 `strokeExtentToGlyphHeightRatio`），
    /// 拉丁手写会被放大约一倍。同时给出原始值，人才能一眼看出「这个字高是不是被放大了」——
    /// 只给换算后的数，偏了也看不出来。
    let rawStrokeExtent: Double

    /// 范围相对典型值有多宽（`range` 宽度 ÷ `typical`）。
    /// 越大说明**高笔画彼此**越不一致，典型值越不稳。见 `range` 的说明。
    var spread: Double { typical > 0 ? (range.upperBound - range.lowerBound) / typical : .infinity }
}

nonisolated enum HandwritingSizeEstimator {
    /// 至少要几笔才给结论。
    ///
    /// 一个汉字通常五到十几笔，所以八笔大约是「写了一两个字」。
    /// 少于这个数，纵向跨度最大的那四分之一就只剩一两笔，中位数没有意义。
    static let minimumStrokeCount = 8

    /// 「最高四分之一笔画跨度的中位数」占整个字高的比例，**只对汉字成立**。
    ///
    /// 量自打包的字形笔顺数据（字面方格为 1.0），七句真实长度的中文实测
    /// 落在 0.466…0.542，中位数 0.49。做法与算法本身完全一致（整页笔画汇总后取分位），
    /// 所以这个数可以直接拿来做逆运算。
    /// `HandwritingSizeEstimateTests` 会从真实字形数据重新量一遍并断言它对得上。
    ///
    /// **但它换不了手写拉丁字母**：人写 l、y、h 往往一笔跨过整个字高，比例接近 1 而不是 0.49，
    /// 于是估出来会大一倍。2026-08-31 的实测偏差达 2.5 倍，详见文件头。
    /// 因此这个换算目前只用于诊断，不用于决定魂的字号。
    static let strokeExtentToGlyphHeightRatio: Double = 0.49

    /// 只统计纵向跨度最高的这一部分笔画。
    ///
    /// 取四分之一：一个汉字里真正纵向贯通的笔画大约占四分之一到三分之一
    /// （长竖、竖钩、左右外框），其余是横、点、短撇。取太多会被矮笔画拉低，
    /// 取太少（比如只取最高的一笔）又会被一次夸张的连笔带跑。
    static let tallestFraction: Double = 0.25

    /// 估出用户的字有多大。
    /// - Parameter polylines: 用户这一轮写的笔画（页面坐标）。
    /// - Returns: 估算结果；笔画太少时返回 nil，**不给替代值**。
    static func estimate(from polylines: [Polyline]) -> HandwritingSizeEstimate? {
        let extents = polylines
            .compactMap { verticalExtent(of: $0) }
            .filter { $0 > 0 }
            .sorted()

        guard extents.count >= minimumStrokeCount else { return nil }

        let keep = max(1, Int((Double(extents.count) * tallestFraction).rounded()))
        let tallest = Array(extents.suffix(keep))

        guard let low = tallest.first, let high = tallest.last else { return nil }

        // 除以换算比例：单笔的纵向跨度只有整个字高的一半左右，
        // 不换算会把字号估到实际的一半，魂就会写出一页明显偏小的字。
        let toGlyphHeight = 1 / strokeExtentToGlyphHeightRatio
        let raw = median(ofSorted: tallest)
        return HandwritingSizeEstimate(
            typical: raw * toGlyphHeight,
            range: (low * toGlyphHeight) ... (high * toGlyphHeight),
            sampleCount: extents.count,
            rawStrokeExtent: raw
        )
    }

    /// 一笔的纵向跨度。点数不足或退化成一点时返回 nil（它不该参与统计）。
    private static func verticalExtent(of polyline: Polyline) -> Double? {
        let ys = polyline.points.map(\.y)
        guard let low = ys.min(), let high = ys.max() else { return nil }
        return high - low
    }

    private static func median(ofSorted sorted: [Double]) -> Double {
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
