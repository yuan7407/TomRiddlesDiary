//
//  BookHinge.swift
//  模块：Features/Book（界面层；依赖 SwiftUI）
//
//  文件职责：iPhone Duo 的两件硬件事实怎么进到这本日记里——
//  一，合页现在是合上、半开还是摊平（`BookPosture`）；
//  二，折缝在屏幕上的哪一条（`SpreadGeometry`）。
//  只有这一个文件碰 iOS 27.1 的折叠屏接口；其余代码只认 `BookPosture` 和 `SpreadGeometry` 这两个纯数据类型。
//
//  为什么要隔这一层：
//  折叠屏接口是 iOS 27.1 才有的，而工程的部署目标是 26.0，iPad 和普通 iPhone 根本没有合页。
//  把 `#available` 和「没有合页时怎么办」收在一处，别的地方就不用到处判断设备。
//  没有合页的设备一律当作「摊平、没有折缝」，这不是兜底：对它们来说这就是事实。
//
//  「姿态就是模式」（对开设计的第五条）：
//  · 摊平：写字。成页倒计时照常。
//  · 半开：拿在手里翻看旧页。此时不应该因为停笔而成页（`BookPosture.allowsCommitAfterPause`）。
//  · 合上：句号。没交出去的字立刻交出去（`BookPosture.commitsPendingWritingOnEntry`），
//    他在合着的本子里接着写，手上有触感（`WritingHaptics`）。
//
//  ⚠️ **假设，需要你在本机验证**——这个文件没有编译过，下面的接口我没有官方文档可查：
//  我依据的是 GitHub 上 artemnovichkov/iPhone-Duo-by-Examples 这个示例仓库
//  （它自己写明是在 iOS 27.1 的 iPhone Duo 模拟器上观察到的行为，不是文档保证）：
//  · `View.onHingeChange { 旧, 新 in … }`，`新.hinge` 是 `DeviceHinge?`；
//  · `DeviceHinge.angle` 是 `Angle`，`DeviceHinge.status` 有 `.closed`、`.partiallyOpen`、`.fullyOpen`；
//  · `GeometryProxy.reservedRegions(kind: .division, options: [])` 返回的每一项有 `.frame`（代理自己的坐标系）。
//  如果签名对不上，编译器会在这个文件里报错，改这里就够了。
//  验证办法：Xcode 27.1 + iPhone Duo 模拟器，开合合页时看 DEBUG 日志里的姿态是不是跟着变；
//  摊平时在折缝两侧各写一句，回应不应该压在折缝上。
//

import SwiftUI

extension View {
    /// 合页姿态变了就告诉调用方。iOS 27.1 起由系统报（启动时就报一次）；更早的系统没有合页接口，出现时报一次 `.flat`。
    func onBookPostureChange(_ action: @escaping (BookPosture) -> Void) -> some View {
        modifier(BookPostureReader(action: action))
    }
}

private struct BookPostureReader: ViewModifier {
    let action: (BookPosture) -> Void
    @State private var posture: BookPosture?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            // 不在出现时先猜一个「摊平」：系统在启动时就会报一次真的合页状态（2026-11-18 在 Duo 模拟器上
            // 实测，启动即收到 fullyOpen）。先猜的话，在外屏启动会先当成摊平、闪一下纸再盖上封面。
            content
                .onHingeChange { _, context in
                    report(Self.posture(of: context.hinge, previous: posture))
                }
        } else {
            content.onAppear { if posture == nil { report(.flat) } }
        }
    }

    private func report(_ next: BookPosture) {
        guard next != posture else { return }
        posture = next
        action(next)
    }

    @available(iOS 27.1, *)
    private static func posture(of hinge: DeviceHinge?, previous: BookPosture?) -> BookPosture {
        guard let hinge else { return .flat }
        // 优先用系统判好的状态：它知道这台机器的合页在什么角度算合上，我们不知道。
        if hinge.status == .closed { return .closed }
        if hinge.status == .fullyOpen { return .flat }
        if hinge.status == .partiallyOpen { return .ajar }
        // 将来系统多出一种状态时退回按角度判断，阈值在 `BookFeel.posture`。
        return BookPosture.classify(
            angleDegrees: hinge.angle.degrees,
            previous: previous,
            thresholds: BookFeel.posture
        )
    }
}

/// 量出这一刻的对开版面（整块屏幕 + 折缝），交给里面的内容去排。
struct SpreadReader<Content: View>: View {
    @ViewBuilder let content: (SpreadGeometry) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(Self.geometry(in: proxy))
        }
    }

    private static func geometry(in proxy: GeometryProxy) -> SpreadGeometry {
        let bounds = PageRegion(left: 0, top: 0, width: proxy.size.width, height: proxy.size.height)
        var fold: PageRegion?
        if #available(iOS 27.1, *) {
            if let frame = proxy.reservedRegions(kind: .division, options: []).first?.frame {
                fold = PageRegion(left: frame.minX, top: frame.minY, width: frame.width, height: frame.height)
            }
        }
        return SpreadGeometry(bounds: bounds, fold: fold)
    }
}
