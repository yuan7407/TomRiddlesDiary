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
//  精度边界（必须知道的近似）：
//  iOS 的「页面点」是设备无关单位，一个点对应的物理长度取决于屏幕密度，
//  而 iOS 没有公开的 ppi 接口（UIScreen 只给 scale，不给 ppi）。
//  这里按主流 iPad 取基准；iPad mini 密度更高，用这个基准算出来的实际物理
//  尺寸会偏小约两成。由于字高与笔宽同比例变化，观感比例不变，只是整体略小，
//  在当前阶段可以接受。若将来需要精确，只能按设备型号查表。
//

import Foundation

/// 页面度量：毫米与页面点之间的换算。
nonisolated enum PageMetrics {
    /// 每英寸多少个页面点。
    /// 推导：主流 iPad 屏幕约 264 ppi，渲染倍率 2x，故每英寸 264 / 2 = 132 个页面点。
    /// 这是本文件唯一的经验基准值，其余换算都由它导出。
    static let pointsPerInch: Double = 132

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
