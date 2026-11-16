//
//  InkTone.swift
//  模块：Configuration（集中配置。本文件只用 Foundation，可以脱离 Apple 平台单独测）
//
//  文件职责：一种墨色的三个分量，以及两种墨之间按比例混合。
//
//  为什么单独成一个文件、不直接用 SwiftUI 的 `Color`：
//  - 「对开」设计里，墨的颜色表示它是什么时候写的：刚落下是蓝黑，两三秒后干成墨黑。
//    湿到干是渐变的，要在两种墨之间按比例混；而 `Color` 取不出分量，混不了。
//  - 混色是纯算术，放在不依赖 SwiftUI 的文件里才能在 Linux 上直接跑测试。
//    换成 `Color` 的那一步留在 `PageAppearance`（那里本来就依赖 SwiftUI）。
//

import Foundation

/// 一种墨色的三个分量，各自在 0…1。
nonisolated struct InkTone: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    /// 与另一种墨按比例混合。`fraction` 为 0 是自己，为 1 是对方；超出范围时夹紧。
    /// 这是纯比例运算，没有经验常数。
    func mixed(with other: InkTone, fraction: Double) -> InkTone {
        let t = fraction.isNaN ? 0 : min(1, max(0, fraction))
        return InkTone(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }
}
