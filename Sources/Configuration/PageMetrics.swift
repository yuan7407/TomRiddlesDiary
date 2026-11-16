//
//  PageMetrics.swift
//  模块：Configuration（集中配置，被上层读取，不被 StrokeEngine 依赖）
//
//  文件职责：全 App 唯一的「物理尺寸 ↔ 屏幕坐标」换算点。
//
//  设计原因：
//  - 手写这件事只有一个量需要物理含义——「字写多大」。字高一旦用毫米声明，
//    就能和真实纸笔直接比较（纸上手写汉字通常 7–12 mm），调参时有据可依。
//    其余所有长度都表达为字高的比例，因此整个工程只需要这一处换算。
//  - 换算集中在这里而不是散在视图里：屏幕密度是设备属性，属配置层；
//    StrokeEngine 是纯算法层，不许知道毫米、屏幕或设备的存在。
//
//  ── 2026-11-16：只剩 iPhone Duo 一个密度（决策 78：设备范围只要 iPhone） ──
//  iOS 没有公开的 ppi 接口（UIScreen 只给 scale），所以这里是一个按机型查来的基准值。
//  数值出处：Xcode 27.3 自带的 iPhone Duo 模拟器机型描述
//  （/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype 的
//  capabilities.plist）：内外两块屏都是 460 dpi、3 倍渲染 → 460 ÷ 3 ≈ 153.3 点/英寸。
//  为什么信它：同一批描述文件里 iPad mini 写 326、iPad 写 264，与真机规格一致，
//  说明这些是真实数值而不是占位。对开包原先用的「430 ppi」来自 MacRumors 规格页，
//  与 Apple 自己的描述不符，照它算 9 毫米的字只有 8.4 毫米。
//  删掉了按机型标识分家族的那套逻辑：iPad 不再是目标，而现有 3 倍 iPhone 也都是 460 ppi，
//  一个值对所有能跑这个 App 的设备都成立，分支只会留下永远走不到的死代码。
//  仍待验证：真机上量一个 9 毫米的字是不是 9 毫米。
//

import Foundation

/// 页面度量：毫米与页面点之间的换算。
nonisolated enum PageMetrics {
    /// 每英寸多少个页面点：iPhone Duo 屏幕 460 ppi ÷ 3 倍渲染。出处见文件头。
    /// 这是本文件唯一的经验基准值，其余换算都由它导出。
    static let pointsPerInch: Double = 460.0 / 3.0

    /// 英寸与毫米的定义换算（1 英寸 = 25.4 毫米），不是经验值。
    private static let millimetersPerInch: Double = 25.4

    /// 每毫米多少个页面点。
    static var pointsPerMillimeter: Double {
        pointsPerInch / millimetersPerInch
    }

    /// 毫米转页面点。
    static func points(fromMillimeters millimeters: Double) -> Double {
        millimeters * pointsPerMillimeter
    }

    /// 页面点转毫米。仅用于诊断与校准时把屏幕上量到的值换回物理单位。
    static func millimeters(fromPoints points: Double) -> Double {
        points / pointsPerMillimeter
    }
}
