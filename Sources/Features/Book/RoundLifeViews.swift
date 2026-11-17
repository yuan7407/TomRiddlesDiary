//
//  RoundLifeViews.swift
//  模块：Features/Book（界面层；依赖 SwiftUI）
//
//  文件职责：一轮的一生里纸上看得见的两件事（计划 P4，网页原型 drawDrink / drawSinking）——
//  一，成页时纸把你的字喝下去：从第一笔开始，一笔接一笔地变细、变褐、朝书脊偏、淡下去，
//      喝完只剩一层很淡、略糊的压痕；
//  二，他上一段话沉下去：变淡、变糊、朝书脊偏，然后离开这张对开。
//
//  为什么自己画而不留在 PencilKit 里：PencilKit 只会原样显示笔迹，画不出逐笔变细变褐。
//  模型在成页时把这一轮从 `PKDrawing` 里拿出来（`DiaryPageModel.beginNewRound`），交给这里。
//
//  动画怎么推进：和 `HandwritingReplayView` 一样，自己用异步循环推进「过了多少秒」，
//  画多少由这个秒数算出来、不数帧。原因见 MEMORY 已知陷阱：模拟器空闲时冻结渲染循环，
//  `TimelineView` 只出一两帧就停。喝完以后循环就停，压痕是静态的。
//
//  数值全部来自 `BookFeel.Drink`（照搬原型）。
//

import SwiftUI

/// 你这一轮被纸喝下去、以及喝完留下的压痕。
struct DrinkingInkView: View {
    let ink: DrinkingInk
    @State private var elapsed: TimeInterval = 0

    var body: some View {
        Canvas { context, _ in
            let drink = BookFeel.Drink.self
            let unit = PaperLook.pointsPerPrototypeUnit
            let q = min(1, max(0, elapsed / drink.duration))

            // 喝完留下的压痕：在喝到四成以后慢慢浮出来，很淡、略糊、朝书脊偏一点。
            let ghostAlpha = drink.ghostOpacity * smoothstep(drink.ghostAppearsFrom, 1, q)
            if ghostAlpha > 0 {
                var ghost = context
                ghost.opacity = ghostAlpha
                ghost.addFilter(.blur(radius: drink.ghostBlur))
                ghost.translateBy(x: ink.towardSpine * drink.shiftTowardSpine * unit, y: 0)
                for line in ink.polylines {
                    ghost.stroke(path(line), with: .color(PageAppearance.sunkInk.color),
                                 style: StrokeStyle(lineWidth: PageAppearance.userInkWidth, lineCap: .round, lineJoin: .round))
                }
            }

            // 正在喝：第 i 笔晚 i/n × 0.55 × 时长开始，每笔喝 0.45 × 时长（原型 drawDrink）。
            guard q < 1 else { return }
            let count = Double(max(1, ink.polylines.count))
            for (index, line) in ink.polylines.enumerated() {
                let start = Double(index) / count * drink.duration * drink.staggerShare
                let p = easeInOut((elapsed - start) / (drink.duration * drink.perStrokeShare))
                guard p < 1 else { continue }
                var layer = context
                layer.opacity = 1 - p * p
                layer.translateBy(x: ink.towardSpine * drink.shiftTowardSpine * unit * p, y: 0)
                let width = PageAppearance.userInkWidth * pow(1 - p, drink.widthExponent) + drink.widthFloor * unit
                let color = PageAppearance.dryInk.mixed(with: PageAppearance.sunkInk, fraction: p).color
                layer.stroke(path(line), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .task(id: ink.since) {
            // 喝完就停：之后只剩静态的压痕，不用再每帧画。
            let interval = Duration.seconds(1.0 / 60)
            while !Task.isCancelled {
                let seconds = (ContinuousClock.now - ink.since).inSeconds
                elapsed = seconds
                if seconds >= BookFeel.Drink.duration { break }
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func path(_ line: Polyline) -> Path {
        var path = Path()
        guard let first = line.points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        if line.points.count == 1 {
            // 只点了一下：画成一个小点（线帽是圆的，一段零长度的线就是一个点）。
            path.addLine(to: CGPoint(x: first.x, y: first.y))
        }
        for point in line.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        return path
    }
}

/// 他上一段话沉下去：变淡、变糊、朝书脊偏（原型 drawSinking）。
struct SinkingReplyView: View {
    let item: SinkingReply
    @State private var sunk = false

    var body: some View {
        let drink = BookFeel.Drink.self
        HandwritingReplayView(sequence: item.reply.sequence, playback: item.reply.playback)
            .opacity(sunk ? 0 : 1)
            .blur(radius: sunk ? drink.sinkBlur : 0)
            .offset(x: sunk ? item.towardSpine * drink.sinkShift * PaperLook.pointsPerPrototypeUnit : 0)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: drink.duration)) { sunk = true }
            }
    }
}

/// 原型的 smooth(a, b, x)：x 在 a…b 之间平滑地从 0 走到 1。算法本身的常数（3、2），不是经验值。
private func smoothstep(_ lower: Double, _ upper: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - lower) / (upper - lower)))
    return t * t * (3 - 2 * t)
}

/// 原型的 easeIO：前一半加速、后一半减速。算法本身的常数，不是经验值。
private func easeInOut(_ u: Double) -> Double {
    let t = min(1, max(0, u))
    return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
}
