//
//  InteractionSettings.swift
//  模块：Configuration（集中配置，被上层读取，不被 StrokeEngine 依赖）
//
//  文件职责：书写交互的行为设定。
//
//  设计原因：
//  这些不是手感数值，而是「怎么算一次输入」的行为决定，所以和 `HandwritingFeel`
//  分开：改「允许不允许用手指写」不该动到抖动幅度所在的文件。
//

import PencilKit

nonisolated enum InteractionSettings {
    /// 画布接受哪种输入。
    ///
    /// 取 `.anyInput`（手指与 Apple Pencil 都能写），有两个原因：
    /// 一、模拟器上没有 Apple Pencil，鼠标等同手指，取 `.pencilOnly` 会导致
    /// 怎么划都没反应，连开发都做不了；
    /// 二、没有笔的用户如果完全写不了字，等于 App 对他不可用。
    ///
    /// **这是一个待用户确认的产品决定，不是技术默认值。** 真实取舍是：
    /// 用笔写才符合「手写日记」的定位，而允许手指会带来误触（手掌搁在屏幕上就
    /// 画出一道）。若最终决定只认 Apple Pencil，按 AGENTS.md 必须明确告知
    /// 「这一页需要用 Apple Pencil 书写」，不能让用户对着毫无反应的纸猜。
    static let drawingPolicy: PKCanvasViewDrawingPolicy = .anyInput
}
