//
//  BrassCorner.swift
//  模块：Features/Book（界面层；依赖 SwiftUI）
//
//  文件职责：封面书口那一侧（右边）上下两只做旧的黄铜护角（计划 S2，决策 83）。
//
//  形状照参考图描的：两条边沿着书边伸出去，末端一个小圆耳，里侧一道内凹的弧收到对角线上的一个尖；
//  靠外角一簇四个圆点、每条边上一个菱形孔、对角线上再一个。
//  参考图上还有两颗錾刻的星，2026-11-18 删了：画出来像两个可以按的图标，用户真去按了。
//  形状以「护角一条边长 = 1」的单位正方形描述，外角在 (1, 0)，关于对角线对称——只描一半，另一半镜像出来，
//  两边永远一样。下边那只是同一个形状上下翻转。
//
//  立体与做旧：渐变底色 + 里侧一圈亮一圈暗（斜面）+ 着色器加铜绿、氧化斑、划痕、磨亮 + 投在皮面上的影子。
//  斜面的亮暗方向在屏幕坐标里定（光永远从左上来），所以翻转形状时不翻光。
//

import SwiftUI

struct BrassCorner: View {
    /// 护角在右上还是右下。
    enum Placement { case topTrailing, bottomTrailing }
    let placement: Placement
    /// 一条边多长（点）。
    let arm: Double

    var body: some View {
        let c = CoverLook.Corner.self
        let flip = placement == .bottomTrailing
        let bevel = c.bevelWidth
        ZStack {
            // 黄铜本体：渐变（光从左上）+ 斜面 + 做旧。
            CornerOutline(flipVertical: flip)
                .fill(LinearGradient(
                    colors: [c.highlight.color, c.body.color, c.shadow.color],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ).shadow(.inner(color: c.polished.color.opacity(0.85), radius: bevel, x: bevel, y: bevel))
                 .shadow(.inner(color: c.shadow.color, radius: bevel * 1.4, x: -bevel, y: -bevel)))
                .colorEffect(ShaderLibrary.agedBrass(.float(c.seed + (flip ? 1 : 0)), .color(c.patina.color), .color(c.polished.color)))

            // 包住书边的那一道翻边：沿外侧两条边的一线亮光。
            CornerLip(flipVertical: flip)
                .stroke(c.polished.color.opacity(0.7), lineWidth: 1.2)

            // 圆点与菱形孔：凹下去、露出底下的暗色。
            CornerHoles(flipVertical: flip)
                .fill(Color(.sRGB, red: 0.05, green: 0.05, blue: 0.07)
                    .shadow(.inner(color: .black, radius: 1, x: 1, y: 1))
                    .shadow(.inner(color: c.highlight.color.opacity(0.6), radius: 0.6, x: -0.6, y: -0.6)))
        }
        .frame(width: arm, height: arm)
        .compositingGroup()
        .shadow(color: .black.opacity(c.dropShadowOpacity), radius: c.dropShadowRadius,
                x: c.dropShadowOffset.x, y: c.dropShadowOffset.y)
        .accessibilityHidden(true)
    }
}

// MARK: 形状（单位正方形，外角在右上 (1, 0)；下边那只上下翻转）

nonisolated private enum CornerGeometry {
    /// 关于对角线的镜像：(x, y) → (1 − y, 1 − x)。外角 (1, 0) 不动。
    static func mirror(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.y, y: 1 - p.x) }

    static func place(_ p: CGPoint, in rect: CGRect, flip: Bool) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + (flip ? 1 - p.y : p.y) * rect.height)
    }

    /// 半边轮廓：从右边那条臂的末端，经过小圆耳，内凹地收到对角线上的尖。另一半是它的镜像。
    /// 每段是三次贝塞尔：(终点, 控制点 1, 控制点 2)。
    static let halfEdgeStart = CGPoint(x: 0.83, y: 1.0)
    static let halfEdge: [(to: CGPoint, c1: CGPoint, c2: CGPoint)] = [
        (to: CGPoint(x: 0.79, y: 0.85), c1: CGPoint(x: 0.76, y: 1.0), c2: CGPoint(x: 0.73, y: 0.89)),   // 圆耳
        (to: CGPoint(x: 0.60, y: 0.40), c1: CGPoint(x: 0.87, y: 0.74), c2: CGPoint(x: 0.67, y: 0.50)),   // 内凹的弧，收到尖
    ]
}

nonisolated private struct CornerOutline: Shape {
    let flipVertical: Bool
    func path(in rect: CGRect) -> Path {
        func at(_ p: CGPoint) -> CGPoint { CornerGeometry.place(p, in: rect, flip: flipVertical) }
        var path = Path()
        path.move(to: at(CGPoint(x: 0, y: 0)))
        path.addLine(to: at(CGPoint(x: 1, y: 0)))
        path.addLine(to: at(CGPoint(x: 1, y: 1)))
        path.addLine(to: at(CornerGeometry.halfEdgeStart))
        for s in CornerGeometry.halfEdge { path.addCurve(to: at(s.to), control1: at(s.c1), control2: at(s.c2)) }
        // 另一半：同样的几段倒着走、再镜像。
        let points = [CornerGeometry.halfEdgeStart] + CornerGeometry.halfEdge.map(\.to)
        for (index, s) in CornerGeometry.halfEdge.enumerated().reversed() {
            path.addCurve(to: at(CornerGeometry.mirror(points[index])), control1: at(CornerGeometry.mirror(s.c2)), control2: at(CornerGeometry.mirror(s.c1)))
        }
        path.addLine(to: at(CornerGeometry.mirror(CGPoint(x: 1, y: 1))))
        path.closeSubpath()
        return path
    }
}

/// 包住书边的翻边：沿上边（或下边）与右边。
nonisolated private struct CornerLip: Shape {
    let flipVertical: Bool
    func path(in rect: CGRect) -> Path {
        func at(_ p: CGPoint) -> CGPoint { CornerGeometry.place(p, in: rect, flip: flipVertical) }
        var path = Path()
        path.move(to: at(CGPoint(x: 0.02, y: 0.012)))
        path.addLine(to: at(CGPoint(x: 0.988, y: 0.012)))
        path.addLine(to: at(CGPoint(x: 0.988, y: 0.98)))
        return path
    }
}

/// 一簇四个圆点（靠外角）+ 三个菱形孔（两条臂上各一、对角线上一个）。
nonisolated private struct CornerHoles: Shape {
    let flipVertical: Bool
    func path(in rect: CGRect) -> Path {
        func at(_ p: CGPoint) -> CGPoint { CornerGeometry.place(p, in: rect, flip: flipVertical) }
        var path = Path()
        let dotRadius = 0.028 * rect.width
        let cluster = CGPoint(x: 0.84, y: 0.16)
        for (dx, dy) in [(-0.04, -0.04), (0.04, -0.04), (-0.04, 0.04), (0.04, 0.04)] {
            let center = at(CGPoint(x: cluster.x + dx, y: cluster.y + dy))
            path.addEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        }
        // 菱形：沿臂的方向长一点。(中心, 沿臂的半长, 横向的半宽, 臂是不是横的)
        let diamonds: [(CGPoint, Double, Double, Bool)] = [
            (CGPoint(x: 0.34, y: 0.1), 0.055, 0.032, true),
            (CornerGeometry.mirror(CGPoint(x: 0.34, y: 0.1)), 0.055, 0.032, false),
            (CGPoint(x: 0.71, y: 0.29), 0.045, 0.045, true),
        ]
        for (center, along, across, horizontal) in diamonds {
            let ax = horizontal ? along : across, ay = horizontal ? across : along
            path.move(to: at(CGPoint(x: center.x - ax, y: center.y)))
            path.addLine(to: at(CGPoint(x: center.x, y: center.y - ay)))
            path.addLine(to: at(CGPoint(x: center.x + ax, y: center.y)))
            path.addLine(to: at(CGPoint(x: center.x, y: center.y + ay)))
            path.closeSubpath()
        }
        return path
    }
}

extension CoverLook.RGB {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}
