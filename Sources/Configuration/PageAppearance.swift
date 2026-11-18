//
//  PageAppearance.swift
//  模块：Configuration（集中配置，被视图层读取，不被 StrokeEngine 依赖）
//
//  文件职责：定义「纸」与「墨」的外观参数，全 App 唯一一处。
//
//  设计原因：
//  - 纸不在这里了（2026-11-17，计划 P1）：纸有了纸纹，定义在 `PaperLook`、由 `PaperBackground` 画，
//    画布透明叠在上面，所以「画布与回应层各有一个纸色、会漂移」的老问题自然消失。
//  - 这里只放已经真实用到的值。字号、行距、页边距等排版参数要等排版层存在时再加，
//    提前建空壳只会变成没人维护的抽象。
//  - 本文件不叫 DesignSystem：当前只有颜色与墨宽两类值，还不足以支撑一套设计系统。
//    等排版与组件成形后再整体升格，届时只是搬家，不需要考古。
//  - 墨宽（2026-08-27 起，计划 D1）不再是裸的视图点数值，而是按参照尺度换算：
//    数值本身归 `HandwritingFeel`，这里只负责按当前字高把它算成视图点。
//    这样换字号时墨的粗细自动跟着变，不需要第二处调参。
//    取舍记录：也可以让墨宽是固定的物理粗细（像一支真笔，写大字也不变粗）。
//    选比例是因为当前只有一个尺度概念、实现最简单；等 PencilKit 接入后能看到
//    用户自己选的笔有多粗，再决定要不要改成绝对粗细（计划 A10 一并复核）。
//
//  ── 2026-11-11：墨有三个年纪 ──
//  「对开」设计里，墨的颜色表示它是什么时候写的：刚落下是蓝黑（湿），两三秒后干成墨黑，
//  沉进纸里以后是褐色。三种墨的分量定义在这里；按比例混合的算术在 `InkTone`（不依赖 SwiftUI）。
//  原来的 `ink` 改成由「干墨」导出，数值不变——同一个颜色不许有两处定义。
//

import SwiftUI

/// 纸与墨的外观。视图层只许从这里取值，不许在视图里写颜色或线宽字面量。
nonisolated enum PageAppearance {
    /// 墨色。偏暖的近黑，避免纯黑在暖色纸上显得像印刷。
    static let ink = dryInk.color

    /// 干透的墨：偏暖的近黑。2026-11-17 对齐网页原型的 DRYC = RGB(33, 28, 24)（决策 80），
    /// 原值 (0.12, 0.105, 0.09) 与它差不到 3/255，统一成原型的值免得两处各一份。
    static let dryInk = InkTone(red: 33.0 / 255, green: 28.0 / 255, blue: 24.0 / 255)

    /// 刚落下、还湿着的墨：蓝黑。
    ///
    /// 依据是真实墨水的行为：二十世纪上半叶通行的蓝黑墨水（铁胆墨水一类）刚写下时偏蓝，
    /// 氧化变干以后才转成黑褐。数值是 2026-11-11 在网页原型里对着纸色肉眼定的，**没有真机复核**。
    static let wetInk = InkTone(red: 0.078, green: 0.118, blue: 0.298)

    /// 沉进纸里的墨：褐色。老的铁胆墨迹年深日久就是这个颜色。同样是原型里肉眼定的。
    static let sunkInk = InkTone(red: 0.478, green: 0.361, blue: 0.235)

    /// 从干到湿的一排颜色，逐段上色时按湿度取。
    ///
    /// 为什么预先算好一排而不是每段现混：一段回应有几千条小线段，每帧都要重画，
    /// 每条线段新建一个 `Color` 是白花的开销。九档已经看不出台阶。
    static let inkRamp: [Color] = (0 ... inkRampSteps).map { step in
        dryInk.mixed(with: wetInk, fraction: Double(step) / Double(inkRampSteps)).color
    }

    /// 上面那排颜色分几档。纯粹的量化精度，不是手感参数。
    private static let inkRampSteps = 8

    /// 按湿度（0 干…1 湿）取墨色。
    static func ink(wetness: Double) -> Color {
        let clamped = wetness.isNaN ? 0 : min(1, max(0, wetness))
        return inkRamp[Int((clamped * Double(inkRampSteps)).rounded())]
    }



    /// 行距，表达为字高的倍数。1.6 → 9 mm 的字行间约留 5.4 mm 空隙。
    /// 手写比印刷需要更松的行距：字有高低起伏，行贴太近会互相蹭到。
    /// 依据仍是量级推算（纸质笔记本行距通常是字高的 1.5–2 倍），待真机观感复核。
    static let lineSpacingRatio: Double = 1.6

    /// 页边距，表达为页面短边的比例，从安全区内侧量起（见 `DiaryPageView`）。
    /// 0.08 → Duo 外屏约 37 点、摊开的内屏约 54 点（2026-11-16 按模拟器屏幕尺寸 466 / 669 点短边算出）。
    /// 用比例而不是固定点数：换设备或分屏时留白比例不变。
    static let pageMarginRatio: Double = 0.08

    /// 按页面尺寸算出页边距（视图点）。
    static func pageMargin(for size: CGSize) -> Double {
        min(size.width, size.height) * pageMarginRatio
    }

    /// 笔尖粗细（毫米）。**用户和「日记之魂」用的是同一支笔。**
    ///
    /// 用绝对毫米而不是字高的比例：真实的笔不会因为字写得小就变细。
    /// 2026-08-28 起魂的墨宽也由这个值推导（见 `inkWidth(forPressure:)`），
    /// 原因是实测发现按字高比例算出来的墨宽达 1.11 mm，笔画密集的汉字会糊成一团，
    /// 且与用户自己的字质感明显不同。
    ///
    /// 0.5 mm 对应常见中性笔。数值仍只是量级推算，真机手写观感待复核。
    static let userInkWidthInMillimeters: Double = 0.5

    /// 用户笔尖粗细换算成视图点。
    static var userInkWidth: Double {
        PageMetrics.points(fromMillimeters: userInkWidthInMillimeters)
    }

    /// 把压感与接触换算成魂的墨线宽度（视图点）。
    ///
    /// **是绝对宽度，不随字号缩放**：魂和用户用同一支笔，而真实的笔不会因为字写得小
    /// 就变细。满压等于用户笔宽，最轻是它的 `inkWidthAtLightestPressureRatio`。
    ///
    /// 两个入参各管一件事（计划 A5，2026-08-29）：
    /// - `pressure` 决定线宽落在 60%…100% 这个区间的哪里。**这个下限是对的**：
    ///   手写时线不会因为松一点力就细成头发。
    /// - `contact` 直接乘在结果上，所以起收笔（接触为 0）能真的收到零宽。
    ///
    /// 之前只有压感一个入参，起收笔靠把压感压低来表现，但压感有 60% 的下限，
    /// 于是**永远收不到零**——那正是 A5 要修的。
    ///
    /// - Parameters:
    ///   - pressure: 0…1 的压感。超出范围时夹紧，避免异常数据画出负宽度。
    ///   - contact: 0…1 的接触程度。同样夹紧。
    static func inkWidth(forPressure pressure: Double, contact: Double = 1) -> Double {
        let lightest = userInkWidth * HandwritingFeel.inkWidthAtLightestPressureRatio
        let span = userInkWidth - lightest
        let pressed = lightest + min(1, max(0, pressure)) * span
        return pressed * min(1, max(0, contact))
    }
}

extension InkTone {
    /// 换成 SwiftUI 的颜色。这一步放在这里而不是 `InkTone` 自己的文件里，
    /// 是为了让那个文件不依赖 SwiftUI、能在任何平台上跑测试。
    nonisolated var color: Color { Color(red: red, green: green, blue: blue) }
}
