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
//  ── 2026-11-11：密度按设备家族取，不再只有 iPad 一个值 ──
//  项目从 iPad 转到 iPhone Duo。原来这里只有一个基准（iPad 的 132 点/英寸），
//  拿到 Duo 上所有毫米值都会偏小约 8%：9 毫米的字实际只有 8.3 毫米。
//  数值小，但它破坏的是「毫米是真的」这条契约，所以改在这唯一的换算点上。
//
//  为什么用机型标识而不是 `UIDevice.current.userInterfaceIdiom`：
//  `UIDevice` 绑在主线程上，而这个类型要能在任意线程被纯逻辑层读到
//  （工程默认隔离是 MainActor，这里标了 nonisolated）。机型标识是一个普通的系统字符串，
//  哪个线程都能读。
//
//  精度边界（必须知道的近似）：
//  iOS 没有公开的 ppi 接口（UIScreen 只给 scale，不给 ppi），所以只能按家族取基准：
//  · iPad：约 264 ppi、2 倍渲染 → 132 点/英寸。iPad mini 密度更高，会偏小约两成。
//  · iPhone：按 Duo 的内屏取。430 ppi 来自 MacRumors 的规格页（1878 × 2670，430 ppi），
//    **渲染倍率 3 倍是我的假设**（现有 iPhone 都是 3 倍），没有在真机上核对过。
//    验证办法：真机上量一个 9 毫米的字是不是 9 毫米。
//    普通 iPhone（约 460 ppi）用这个基准会偏大约 7%，这个项目不以它们为目标。
//

import Foundation

/// 各设备家族的屏幕密度，以及「现在跑在哪个家族上」。
nonisolated enum DisplayDensity {
    /// iPad：264 ppi ÷ 2 倍渲染。
    static let iPadPointsPerInch: Double = 132

    /// iPhone Duo 内屏：430 ppi ÷ 3 倍渲染（倍率是假设，见文件头）。
    static let iPhoneDuoPointsPerInch: Double = 430.0 / 3.0

    /// 按机型标识取密度。机型标识形如 `iPhone19,1`、`iPad16,3`。
    /// 认不出来的（比如 Mac 上跑的测试宿主）按 iPad 算：那是这个工程原来唯一的值，
    /// 保持旧行为比猜一个新值稳妥。
    static func pointsPerInch(forMachine machine: String) -> Double {
        machine.hasPrefix("iPhone") ? iPhoneDuoPointsPerInch : iPadPointsPerInch
    }

    /// 当前设备的机型标识。模拟器上 `hw.machine` 返回的是 Mac 的架构名，
    /// 真正的机型在环境变量里，所以先看环境变量。
    static let currentMachine: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        #if canImport(Darwin)
        var size = 0
        _ = sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        _ = sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
        #else
        // 非 Apple 平台（只在 Linux 上跑纯逻辑测试时会走到）：认不出机型，按文件头说的回退到 iPad 的密度。
        return ""
        #endif
    }()
}

/// 页面度量：毫米与页面点之间的换算。
nonisolated enum PageMetrics {
    /// 每英寸多少个页面点。按设备家族取，来源见 `DisplayDensity`。
    /// 这是本文件唯一的经验基准值，其余换算都由它导出。
    static let pointsPerInch: Double = DisplayDensity.pointsPerInch(forMachine: DisplayDensity.currentMachine)

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
