//
//  OldLeafViews.swift
//  模块：Features/Book（界面层；依赖 SwiftUI）
//
//  文件职责：旧页和印痕在纸上的样子（计划 P7「姿态就是模式」）。
//  · `InkImpression`：一组笔画按某种淡度、糊度压在纸上——旧页里的字、合上时印到对页的镜像都用它。
//  · `OldLeafView`：半合着往回翻时看到的那一张旧对开：纸、页码，和只剩压痕的两种字。
//  · `pageTurn`：翻旧页时整张对开绕着书脊转过去（原型「纸页绕着真的合页翻」）。
//
//  淡度、糊度、时长都在 `BookFeel.Impression`。
//

import SwiftUI

/// 一组笔画的压痕：沉下去的墨色，按给定的淡度与糊度画。
struct InkImpression: View {
    let polylines: [Polyline]
    let opacity: Double
    let blur: Double

    var body: some View {
        Canvas { context, _ in
            for line in polylines {
                guard let first = line.points.first else { continue }
                var path = Path()
                path.move(to: CGPoint(x: first.x, y: first.y))
                // 只有一个点的笔（问号下面那一点）：零长度的线配圆线帽，画出来就是一个点。
                if line.points.count == 1 { path.addLine(to: CGPoint(x: first.x, y: first.y)) }
                for point in line.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
                context.stroke(path, with: .color(PageAppearance.sunkInk.color),
                               style: StrokeStyle(lineWidth: PageAppearance.userInkWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .opacity(opacity)
        .blur(radius: blur)
        .allowsHitTesting(false)
    }
}

/// 一张翻过去的对开。
struct OldLeafView: View {
    let leaf: OldLeaf
    let spread: SpreadGeometry
    let dateLine: String
    let safe: EdgeInsets

    var body: some View {
        let look = BookFeel.Impression.self
        ZStack(alignment: .topLeading) {
            PaperBackground(spread: spread)
            PageFurniture(spread: spread, leafNumber: leaf.number, dateLine: dateLine, safe: safe)
            InkImpression(polylines: leaf.yourInk, opacity: look.yourOpacity, blur: look.yourBlur)
            InkImpression(polylines: leaf.hisInk, opacity: look.hisOpacity, blur: look.hisBlur)
            InkImpression(polylines: leaf.setOff, opacity: look.setOffOpacity, blur: look.setOffBlur)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("旧页，第 \(leaf.number * 2) 页")
    }
}

/// 翻旧页：整张对开绕着书脊转过来（`spineAnchor` 是书脊在宽度上的比例）。
extension AnyTransition {
    static func pageTurn(spineAnchor: Double, fromLeft: Bool) -> AnyTransition {
        .modifier(
            active: PageTurn(angle: fromLeft ? 90 : -90, anchor: spineAnchor),
            identity: PageTurn(angle: 0, anchor: spineAnchor)
        )
    }
}

private struct PageTurn: ViewModifier {
    let angle: Double
    let anchor: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0),
                              anchor: UnitPoint(x: anchor, y: 0.5), perspective: CoverLook.Motion.perspective)
            .opacity(abs(angle) >= 89 ? 0 : 1)
    }
}
