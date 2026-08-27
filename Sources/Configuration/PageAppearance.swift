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
//
//  待办依赖：墨宽当前用「视图点」表达，数值来自早期离线验证时的肉眼调整，没有物理依据。
//  单位契约（计划 D1）会把它改成以毫米声明的真实笔尖粗细，再按页面缩放换算。
//

import SwiftUI

/// 纸与墨的外观。视图层只许从这里取值，不许在视图里写颜色或线宽字面量。
enum PageAppearance {
    /// 纸的底色。偏暖的米白，模拟旧纸而不是纯白屏幕。
    /// PencilKit 画布与回应渲染层必须同时使用这一个值。
    static let paper = Color(red: 0.985, green: 0.974, blue: 0.94)

    /// 墨色。偏暖的近黑，避免纯黑在暖色纸上显得像印刷。
    static let ink = Color(red: 0.12, green: 0.105, blue: 0.09)

    /// 压感为 0 时的墨线宽度（视图点）。不取 0，因为真实笔尖落纸就有宽度。
    static let inkMinimumWidth: Double = 1.15

    /// 压感由 0 升到 1 时额外增加的墨线宽度（视图点）。
    /// 与 inkMinimumWidth 相加即为最粗处宽度。
    static let inkPressureWidthGain: Double = 4.6

    /// 把 0…1 的压感换算成墨线宽度。压感超出范围时夹紧，避免异常数据画出负宽度。
    static func inkWidth(forPressure pressure: Double) -> Double {
        inkMinimumWidth + min(1, max(0, pressure)) * inkPressureWidthGain
    }
}
