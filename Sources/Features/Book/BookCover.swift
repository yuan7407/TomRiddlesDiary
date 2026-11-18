//
//  BookCover.swift
//  模块：Features/Book（界面层；依赖 SwiftUI）
//
//  文件职责：外屏那张旧书封面（计划 S 组，决策 83）——什么时候盖着、怎么翻开、怎么合回来。
//
//  规则（用户 2026-11-18 定）：
//  · 本子合上（外屏）时是封面，封面上不能写字；从右往左滑才翻开，翻开以后是纸。
//  · 摊开用内屏时没有封面，直接是纸。
//  · 合上本子、切到后台、锁屏回来，都回到封面。
//  这些规则全在 `CoverState` 里（纯数据，可测）；`BookCoverView` 只负责画和手势。
//
//  翻开的样子：封面绕左边的书脊转开（3D 透视），转离光源时变暗，压在纸上的那道影子跟着变淡；
//  手指拖着走，松手时过了一定比例或甩得够快就翻开，否则弹回。合上时倒着演一遍。
//  封面静着 3 秒没人碰，就有一点淡淡的光从书口往左滑过、封面跟着微微掀起，教你怎么翻（循环，无文字）。
//  系统设置「减少动态效果」时不转，只淡出淡入。
//

import SwiftUI

/// 封面盖不盖着。纯数据：姿态怎么变、什么时候翻开、什么时候回到封面。
nonisolated struct CoverState: Equatable, Sendable {
    /// 在外屏上已经翻开了。
    private(set) var openedOnOuter = false
    /// 下一次封面出现时要演「合回来」：从摊开合上时是；切后台回来不是（那时屏幕是黑的，演了也看不见）。
    private(set) var closesWithMotion = false

    /// 现在该不该盖着封面。
    /// - Parameters:
    ///   - posture: 合页姿态；nil 是启动的头一瞬还不知道。
    ///   - isPortrait: 屏幕是不是竖的。只在姿态还不知道时用：外屏是竖的、摊开的内屏是横的，
    ///     这一瞬先按屏幕形状猜，免得在外屏上先闪一下纸再盖上封面（姿态一到就以姿态为准）。
    func showsCover(posture: BookPosture?, isPortrait: Bool) -> Bool {
        guard !openedOnOuter else { return false }
        switch posture {
        case .closed: return true
        case .ajar, .flat: return false
        case nil: return isPortrait
        }
    }

    /// 在外屏上翻开了。
    mutating func opened() {
        openedOnOuter = true
        closesWithMotion = false
    }

    /// 合页姿态变了：从开着变成合上，就回到封面，并演一遍合回来。
    mutating func postureChanged(from old: BookPosture?, to new: BookPosture) {
        guard new == .closed, let old, old != .closed else { return }
        openedOnOuter = false
        closesWithMotion = true
    }

    /// 离开了 App（切到后台、锁屏）：回来时是封面，不演合上。
    mutating func leftTheApp() {
        openedOnOuter = false
        closesWithMotion = false
    }

    /// 合回来那一遍演完了。
    mutating func closeMotionPlayed() {
        closesWithMotion = false
    }
}

/// 封面本身：皮面、护角、名牌，加上翻开的手势。
struct BookCoverView: View {
    /// 出现时要不要先演一遍合回来（见 `CoverState.closesWithMotion`）。
    let closesWithMotion: Bool
    let onOpened: () -> Void
    let onCloseMotionPlayed: () -> Void

    /// 0 = 合着，1 = 完全翻开。
    @State private var progress: Double = 0
    @State private var thumps = 0
    /// 教你怎么翻的那一段演到哪了（0…1）；nil = 没在演。
    @State private var hint: Double?
    /// 碰过封面几次。每碰一次，提示就停下、重新开始数（`.task(id:)` 换 id 会取消上一轮）。
    @State private var touches = 0
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let m = CoverLook.Motion.self
            // 提示时封面右边跟着微微掀起（光滑到一半时最高）。
            let lift = hint.map { reduceMotion ? 0 : sin(Self.travel($0) * .pi) * m.hintLift } ?? 0
            let angle = max(progress, lift) * m.openAngleDegrees
            ZStack(alignment: .topLeading) {
                // 封面压在纸上的那道影子：封面右边缘投在纸上，掀得越开越淡。
                if !reduceMotion, progress > 0 {
                    let edge = size.width * cos(angle * .pi / 180)
                    LinearGradient(colors: [.black.opacity(m.pageShadowOpacity * (1 - progress)), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: m.pageShadowWidth)
                        .offset(x: max(0, edge))
                }

                CoverFace(size: size)
                    .overlay(Color.black.opacity(reduceMotion ? 0 : m.turnDarkening * sin(angle * .pi / 180)))
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : -angle), axis: (x: 0, y: 1, z: 0),
                                      anchor: .leading, perspective: m.perspective)
                    .opacity(reduceMotion ? 1 - progress : (angle >= 90 ? 0 : 1))

                if let hint {
                    HintGlow(phase: hint, size: size, moves: !reduceMotion)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(openGesture(width: size.width))
            .onAppear { appeared() }
            .task(id: touches) { await loopHint() }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: thumps)
        .accessibilityElement()
        .accessibilityLabel(CoverLook.Plate.text)
        .accessibilityHint("翻开这本日记")
        .accessibilityAction(named: "翻开") { finishOpening() }
    }

    private func openGesture(width: Double) -> some Gesture {
        let m = CoverLook.Motion.self
        return DragGesture(minimumDistance: m.minimumDrag)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    hint = nil
                    touches += 1
                }
                // 只认往左拖；往右拖封面不动（书脊在左边，封面没法往右翻）。
                progress = min(1, max(0, -value.translation.width / width))
            }
            .onEnded { value in
                dragging = false
                let flung = -value.predictedEndTranslation.width / width
                if progress > m.openProgress || flung > m.flingProgress {
                    finishOpening()
                } else {
                    withAnimation(.spring(duration: m.springBackDuration)) { progress = 0 }
                }
            }
    }

    private func finishOpening() {
        withAnimation(.easeOut(duration: CoverLook.Motion.finishOpenDuration)) {
            progress = 1
        } completion: {
            thumps += 1
            onOpened()
        }
    }

    private func appeared() {
        let m = CoverLook.Motion.self
        if closesWithMotion {
            // 合回来：从翻开的样子落回去，落定时闷闷的一下。
            progress = 1
            withAnimation(.easeIn(duration: m.closeDuration)) { progress = 0 } completion: {
                thumps += 1
                onCloseMotionPlayed()
            }
        }
    }

    /// 封面静着 3 秒就演一段提示（3 秒），然后再等 3 秒、再演，一直循环；碰一下就从头数。
    /// 用异步循环推进而不是 TimelineView（模拟器空闲时会冻结 TimelineView，见 MEMORY 已知陷阱）。
    private func loopHint() async {
        let m = CoverLook.Motion.self
        let frame = Duration.seconds(1.0 / 60)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(m.hintIdle))
            guard !Task.isCancelled, progress == 0, !dragging else { continue }
            let start = ContinuousClock.now
            while !Task.isCancelled {
                let t = (ContinuousClock.now - start).inSeconds / m.hintDuration
                if t >= 1 { break }
                hint = t
                try? await Task.sleep(for: frame)
            }
            hint = nil
        }
    }

    /// 提示里光点走到哪了：淡入时不动，之后缓入缓出地走，淡出时停在终点。0…1。
    nonisolated static func travel(_ phase: Double) -> Double {
        let m = CoverLook.Motion.self
        let u = min(1, max(0, (phase - m.hintFadeIn) / (m.hintFadeOutFrom - m.hintFadeIn)))
        return u * u * (3 - 2 * u)   // smoothstep：算法本身的常数
    }
}

/// 提示的那一点光：从书口往左滑，拖一小截尾巴。没有文字（用户要求）。
private struct HintGlow: View {
    let phase: Double
    let size: CGSize
    /// 「减少动态效果」时光点不走，只在书口那儿淡入淡出。
    let moves: Bool

    var body: some View {
        let m = CoverLook.Motion.self
        let fade = min(phase / m.hintFadeIn, 1) * min((1 - phase) / (1 - m.hintFadeOutFrom), 1)
        let radius = m.hintGlowRadius * size.width
        Canvas { context, _ in
            for k in 0 ... (moves ? m.hintTrailCount : 0) {
                let u = moves ? BookCoverView.travel(phase - Double(k) * m.hintTrailStep) : 0
                let x = size.width * (m.hintStartX + (m.hintEndX - m.hintStartX) * u)
                let y = size.height * m.hintY
                let falloff = 1 - Double(k) / Double(m.hintTrailCount + 1)
                let r = radius * (0.55 + 0.45 * falloff)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [CoverLook.Plate.goldLight.color.opacity(m.hintGlowOpacity * fade * falloff), .clear]),
                        center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 封面的正面：皮面 + 右边上下两只护角 + 名牌。
private struct CoverFace: View {
    let size: CGSize

    var body: some View {
        let l = CoverLook.Leather.self
        let arm = CoverLook.Corner.armLength * size.width
        let grooveX = l.grooveFromSpine * size.width
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.black)
                .colorEffect(ShaderLibrary.leather(
                    .float2(size), .float(l.grainCell), .float(l.seed),
                    .color(l.base.color), .color(l.light.color), .color(l.crease.color), .color(l.worn.color),
                    .float(grooveX), .float(l.edgeWear), .float(l.mottle)
                ))

            NamePlate(coverWidth: size.width)
                .position(x: grooveX + (size.width - grooveX) / 2, y: size.height * CoverLook.Plate.centerHeight)

            BrassCorner(placement: .topTrailing, arm: arm)
                .position(x: size.width - arm / 2, y: arm / 2)
            BrassCorner(placement: .bottomTrailing, arm: arm)
                .position(x: size.width - arm / 2, y: size.height - arm / 2)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 名牌：一小块黑皮贴在封面上，上面烫金字，金磨掉了一些（计划 S3）。
private struct NamePlate: View {
    let coverWidth: Double

    var body: some View {
        let p = CoverLook.Plate.self
        let fontSize = p.fontSize * coverWidth
        Text(p.text)
            .font(.custom(p.fontName, fixedSize: fontSize))
            .tracking(p.tracking * coverWidth)
            .foregroundStyle(LinearGradient(colors: [p.goldLight.color, p.gold.color, p.goldDark.color],
                                            startPoint: .top, endPoint: .bottom))
            .colorEffect(ShaderLibrary.wornGold(.float(p.seed), .float(p.goldWear)))
            // 烫进去的字：字的上沿压暗、下沿透一点光。
            .shadow(color: .black.opacity(0.8), radius: 0.4, x: 0, y: -0.6)
            .padding(.horizontal, fontSize * p.horizontalPadding)
            .padding(.vertical, fontSize * p.verticalPadding)
            .background {
                Rectangle()
                    .fill(.black)
                    .visualEffect { content, proxy in
                        content.colorEffect(ShaderLibrary.leather(
                            .float2(proxy.size), .float(p.grainCell), .float(p.seed),
                            .color(p.leather.color), .color(p.leatherLight.color), .color(p.leather.color),
                            .color(p.leatherLight.color), .float(-1), .float(2), .float(0.6)
                        ))
                    }
                    // 皮片的边：上沿暗、下沿被光照到。
                    .overlay(Rectangle().stroke(LinearGradient(colors: [.black, p.goldDark.color.opacity(0.35)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
            }
            // 皮片比封面高出一点点：影子落在右下（光从左上）。
            .compositingGroup()
            .shadow(color: .black.opacity(0.55), radius: 1.6, x: 0.8, y: 1.4)
    }
}
