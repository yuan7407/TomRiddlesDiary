//
//  PageAppearance.swift
//  模块：Configuration（集中配置，被视图层读取，不被 StrokeEngine 依赖）
//
//  文件职责：定义「纸」与「墨」的外观参数，全 App 唯一一处。
//
//  设计原因：
//  - 纸色必须唯一。用户手写的 PencilKit 画布和「日记之魂」回应的渲染层会共处同一页，
//    两者的底色一旦有任何差异，墨水淡入过渡时会露出一条接缝。历史上这两个颜色
//    分别硬编码在两个文件里，属于必然会漂移的写法，因此收敛到这里。
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

import SwiftUI

/// 纸与墨的外观。视图层只许从这里取值，不许在视图里写颜色或线宽字面量。
nonisolated enum PageAppearance {
    /// 纸的底色。偏暖的米白，模拟旧纸而不是纯白屏幕。
    /// PencilKit 画布与回应渲染层必须同时使用这一个值。
    static let paper = Color(red: 0.985, green: 0.974, blue: 0.94)

    /// 墨色。偏暖的近黑，避免纯黑在暖色纸上显得像印刷。
    static let ink = Color(red: 0.12, green: 0.105, blue: 0.09)

    /// 说明性文字（开发期读数、诚实提示、缺字告知）的墨色浓度。
    /// 统一一处的原因：这类文字散在好几个视图里，各写一个透明度必然漂移成
    /// 深浅不一。它们的共同点是「要看得见但不能抢走手写内容」。
    static let noticeInkOpacity: Double = 0.55

    /// 说明性文字四周的留白（视图点）。
    /// 只服务于 DEBUG 横幅这类贴在页面上的说明块，与页边距是两回事。
    static let noticePadding: Double = 10

    /// DEBUG 横幅底色的浓度。刻意做得明显——它的用途是让开发期状态一眼可见，
    /// 不需要含蓄。产品面不出现任何这类横幅。
    static let debugBannerOpacity: Double = 0.82

    /// 行距，表达为字高的倍数。1.6 → 9 mm 的字行间约留 5.4 mm 空隙。
    /// 手写比印刷需要更松的行距：字有高低起伏，行贴太近会互相蹭到。
    /// 依据仍是量级推算（纸质笔记本行距通常是字高的 1.5–2 倍），待真机观感复核。
    static let lineSpacingRatio: Double = 1.6

    /// 页边距，表达为页面短边的比例。0.08 → 竖持 iPad 上约 65 点。
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
