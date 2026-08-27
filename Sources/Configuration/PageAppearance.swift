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
enum PageAppearance {
    /// 纸的底色。偏暖的米白，模拟旧纸而不是纯白屏幕。
    /// PencilKit 画布与回应渲染层必须同时使用这一个值。
    static let paper = Color(red: 0.985, green: 0.974, blue: 0.94)

    /// 墨色。偏暖的近黑，避免纯黑在暖色纸上显得像印刷。
    static let ink = Color(red: 0.12, green: 0.105, blue: 0.09)

    /// 把 0…1 的压感换算成墨线宽度（视图点）。
    /// - Parameters:
    ///   - pressure: 0…1 的压感。超出范围时夹紧，避免异常数据画出负宽度。
    ///   - referenceScale: 参照尺度，即一个字的高度（视图点）。传 nil 用默认字高。
    static func inkWidth(forPressure pressure: Double, referenceScale: Double? = nil) -> Double {
        let scale = referenceScale ?? HandwritingFeel.referenceGlyphHeightInPoints
        let minimum = scale * HandwritingFeel.inkMinimumWidthRatio
        let gain = scale * HandwritingFeel.inkPressureWidthGainRatio
        return minimum + min(1, max(0, pressure)) * gain
    }
}
