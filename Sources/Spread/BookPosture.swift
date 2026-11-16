//
//  BookPosture.swift
//  模块：Spread（「对开」的纯逻辑层，只依赖 Foundation）
//
//  文件职责：这本日记现在是哪种拿法——合着、半合着、摊平。
//
//  为什么姿态就是模式（决策 20：纸上零按钮）：
//  折叠屏多出来的那个自由度，正好可以顶替掉界面上本来要有的模式切换。
//  · 摊平：写。两页都是纸。
//  · 半合着拿在手里：读。往回翻旧页，这时不成页、不提交。
//  · 合上：句号。还没交出去的那句话立刻交出去（比任何「发送」按钮都自然），
//    他可以在合着的本子里接着写；再打开，回应已经在那儿了。
//
//  真机上优先用系统报告的状态（iOS 27.1 的 `DeviceHinge.Status`），那一步映射在界面层
//  （`Features/Book/HingeReader`）。这里的按角度分类只是后备：
//  拿不到状态、只拿得到角度时用；它带回差，免得停在临界角度时来回跳。
//

import Foundation

nonisolated struct BookPostureThresholds: Equatable, Sendable {
    let closedBelowDegrees: Double
    let flatAboveDegrees: Double
    /// 回差。已经处在某个姿态时，要多越过这么多度才算离开它。
    let hysteresisDegrees: Double

    init(closedBelowDegrees: Double, flatAboveDegrees: Double, hysteresisDegrees: Double) {
        precondition(closedBelowDegrees >= 0 && flatAboveDegrees <= 180, "Posture thresholds must lie within 0...180")
        precondition(hysteresisDegrees >= 0, "Hysteresis cannot be negative")
        precondition(
            closedBelowDegrees + hysteresisDegrees < flatAboveDegrees - hysteresisDegrees,
            "Closed and flat bands overlap once hysteresis is applied"
        )
        self.closedBelowDegrees = closedBelowDegrees
        self.flatAboveDegrees = flatAboveDegrees
        self.hysteresisDegrees = hysteresisDegrees
    }
}

nonisolated enum BookPosture: Equatable, Sendable {
    /// 合上：句号。
    case closed
    /// 半合着：翻看。
    case ajar
    /// 摊平：书写。
    case flat

    /// 这个姿态下，停笔之后可不可以成页。只有摊平时可以：
    /// 半合着是在翻旧页，这时把半句话交出去是误触发。
    var allowsCommitAfterPause: Bool { self == .flat }

    /// 进入这个姿态的那一刻，要不要把还没交出去的字立刻交出去。只有合上时要。
    var commitsPendingWritingOnEntry: Bool { self == .closed }

    /// 按合页角度分类。`previous` 是上一次的姿态，用来做回差；第一次没有就传 nil。
    static func classify(
        angleDegrees: Double,
        previous: BookPosture?,
        thresholds: BookPostureThresholds
    ) -> BookPosture {
        guard angleDegrees.isFinite else { return previous ?? .flat }
        let slack = thresholds.hysteresisDegrees
        // 已经合着的，要张开得比门槛再多一点才算打开；已经摊平的同理。
        let closedLimit = thresholds.closedBelowDegrees + (previous == .closed ? slack : 0)
        let flatLimit = thresholds.flatAboveDegrees - (previous == .flat ? slack : 0)
        if angleDegrees < closedLimit { return .closed }
        if angleDegrees > flatLimit { return .flat }
        return .ajar
    }
}
