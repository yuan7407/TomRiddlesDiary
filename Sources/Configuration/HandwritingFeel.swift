//
//  HandwritingFeel.swift
//  模块：Configuration（集中配置，被上层读取，不被 StrokeEngine 依赖）
//
//  文件职责：手写手感的全部可调参数，以及把它们装配成 `HumanizerConfiguration` 的
//  唯一生产入口。全 App 不允许在别处出现手感数值字面量。
//
//  设计原因（计划 D1/D2，2026-08-27）：
//  - **一个尺度概念**：所有长度都表达为「参照尺度」的比例，参照尺度就是一个字的高度。
//    只有字高本身用毫米声明，因为只有它需要和真实纸笔比较。这样换字号时，间距、
//    抖动、速度、笔宽全部自动跟着变，比例关系不变，不需要任何一处重新调参。
//  - **为什么必须这么做**：历史实现里这些参数直接是裸坐标值，于是「参数适配内容」
//    变成了「内容适配参数」——夹具坐标被硬除以 5，好让默认参数落在合理量级。
//    那个除法是症状，病根是参数没有物理含义。现在参数有了含义，除法不再需要。
//  - **为什么用比例而不是全用毫米**：真人写小字时手抖的绝对幅度也更小、下笔更快。
//    如果间距和抖动用绝对毫米，缩小字号会把字糊掉。比例天然表达了这种关系。
//  - 时长类参数是绝对秒数，因为时间不随字号变化。压感与渐细是无量纲比例。
//
//  数值来源（必须诚实看待）：
//  - 无量纲的压感与时长参数沿用已删除的离线验证界面里调过的值。它们不受尺度契约
//    影响，但同样**只是肉眼调过，没有真机测量**。
//  - 尺度相关的三项与笔宽是按真人书写的量级推算的起点，**没有任何测量依据**。
//  - 计划 A10 会用 PencilKit 采到的真实笔迹（抖动波长与幅度、压感变化率、笔内速度
//    曲线、笔间停顿）替换这些数字。在那之前，不得把这里的数值当成已验证的手感。
//

import Foundation

/// 手写手感参数。视图与调用方只许从这里取值。
nonisolated enum HandwritingFeel {
    // MARK: 参照尺度

    /// 一个字的高度（毫米）。全工程唯一需要物理单位的长度。
    /// 取值理由：纸上手写汉字通常 7–12 mm，9 mm 是偏舒适的日记字号。
    static let referenceGlyphHeightInMillimeters: Double = 9

    /// 一个字的高度换算成页面点。所有比例型参数都以它为基准。
    static var referenceGlyphHeightInPoints: Double {
        PageMetrics.points(fromMillimeters: referenceGlyphHeightInMillimeters)
    }

    // MARK: 尺度相关（表达为参照尺度的比例）

    /// 重采样间距占字高的比例。0.035 → 9 mm 的字约 0.32 mm 一个采样点，
    /// 即一个字高约 29 个点。够密以表现曲线，又不至于让抖动退化成高频毛刺。
    static let sampleSpacingRatio: Double = 0.035

    /// 手抖幅度（标准差）占字高的比例。0.018 → 约 0.16 mm。
    /// 注意：在计划 A1 把抖动改成沿笔画的相关噪声之前，这里仍是逐点独立的白噪声，
    /// 看起来会像毛刺而不是手抖，因此幅度刻意取小以免难看。
    static let jitterAmplitudeRatio: Double = 0.018

    /// 每秒画过多少个「字高」的墨迹长度。
    /// 推算：中文手写约每秒 1.5 个字，一个字的墨迹总长约 5 个字高，故约 7.5。
    static let inkLengthPerSecondInReferenceScales: Double = 7.5

    /// 一个汉字的墨迹总长约等于几个字高。
    /// 原先这个数只写在上一行的注释里，没有作为值存在，于是「每秒几个字」这件事
    /// 无法从配置推出来，只能在别处再拍一个数——那就成了同一关系的第二套值。
    /// 现在显式化，`glyphsPerSecond` 由它与书写速度算出。
    /// 依据同样只是量级推算（一个字六七笔、每笔平均不到一个字高），待 A10 用真人笔迹核实。
    static let inkLengthPerGlyphInReferenceScales: Double = 5

    // MARK: 无量纲比例与绝对时间

    /// 每笔时长的随机浮动比例。
    static let durationVariation: Double = 0.06

    /// 单笔最短时长（秒）。时间与字号无关，故为绝对值。
    static let minimumDuration: TimeInterval = 0.12

    static let basePressure: Double = 0.7
    static let pressureVariation: Double = 0.07
    static let minimumPressure: Double = 0.12
    static let maximumPressure: Double = 0.92

    /// 起笔与收笔渐细各占整笔的比例。
    static let taperFraction: Double = 0.16

    // MARK: 墨线宽度（表达为参照尺度的比例）

    /// 压感最轻时墨线宽度占满压宽度的比例。
    ///
    /// 满压宽度不在这里定，而是取用户手里那支笔的粗细（`PageAppearance.userInkWidth`）——
    /// 魂应该像用同一支笔写的，所以只需要一个参数描述「压感让它变细多少」。
    ///
    /// 2026-08-28 的修改依据（实测截图）：原先墨宽是按字高比例算的，满压达 1.11 mm，
    /// 是真实钢笔（0.3–0.6 mm）的两倍多、也是用户那支 0.5 mm 笔的 2.2 倍。
    /// 结果是笔画密集的汉字（「慢」14 笔挤在 9 mm 里）整个糊成一团，
    /// 而且与用户自己写的字质感明显不同。改成「同一支笔」既有物理依据，
    /// 又同时解决这两个问题，并且把两个反推来的比例换成了一个有含义的参数。
    static let inkWidthAtLightestPressureRatio: Double = 0.6

    // MARK: 随机种子

    /// 默认随机种子。同一输入配同一种子必然得到同一结果。
    /// 现状的副作用：同一段文字每次重播的抖动完全一样。等 Oracle 接入后应改为
    /// 由回应的标识派生种子，让不同回应的手写各不相同——那属计划 E6 的范围，
    /// 现在不提前抽象。
    static let defaultSeed: UInt64 = 7

    // MARK: 装配

    /// 每秒写出几个字。由书写速度与每字墨迹长度推出，不是独立参数——
    /// 改书写速度时它会自动跟着变，不会出现两个数打架。
    static var glyphsPerSecond: Double {
        inkLengthPerSecondInReferenceScales / inkLengthPerGlyphInReferenceScales
    }

    /// 按参照尺度装配出引擎需要的手绘化参数。
    /// - Parameter referenceScale: 一个字的高度（页面点）。传 nil 用默认字高。
    /// - Returns: 尺度相关字段已换算成页面点的配置。
    static func humanizerConfiguration(referenceScale: Double? = nil) -> HumanizerConfiguration {
        let scale = referenceScale ?? referenceGlyphHeightInPoints
        precondition(scale > 0, "参照尺度必须为正数")

        return HumanizerConfiguration(
            sampleSpacing: scale * sampleSpacingRatio,
            jitterAmplitude: scale * jitterAmplitudeRatio,
            inkLengthPerSecond: scale * inkLengthPerSecondInReferenceScales,
            durationVariation: durationVariation,
            minimumDuration: minimumDuration,
            basePressure: basePressure,
            pressureVariation: pressureVariation,
            minimumPressure: minimumPressure,
            maximumPressure: maximumPressure,
            taperFraction: taperFraction
        )
    }
}
