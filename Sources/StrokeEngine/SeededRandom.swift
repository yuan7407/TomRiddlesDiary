//
//  SeededRandom.swift
//  模块：StrokeEngine（纯逻辑，不依赖 UI、网络或模型）
//
//  文件职责：可复现的随机数发生器。
//
//  为什么全工程只许用这一个（2026-08-31 从 `StrokeHumanizer` 提出来）：
//  它原本是手绘化层的私有类型。后来「回应落在哪」也需要随机（在几个同样合适的位置
//  之间挑一个），于是出现了第二个需要它的地方。复制一份是最糟的选择——
//  两份实现迟早在某个细节上分叉，而分叉的症状是「同一份输入、同一个种子，
//  这次和上次画出来不一样」，那会让所有手感回归测试同时失去意义。
//
//  为什么不用系统的随机数：
//  系统 RNG 无法复现。而这个产品的两件事都要求可复现——
//  手感回归测试要能断言「同一输入必得同一结果」，出问题时要能重放那一次的样子。
//
//  为什么是 SplitMix64：实现极短、无外部依赖、同 seed 完全可复现。
//  它不是密码学安全的随机数，也不需要是——这里的用途是手感与位置的抖动，
//  不涉及任何安全性。
//

import Foundation

nonisolated struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// 标准正态噪声（Box–Muller）。取对数前夹住下界，避免 log(0) 得到无穷。
    mutating func gaussian() -> Double {
        let first = max(unitInterval(), Double.leastNonzeroMagnitude)
        let second = unitInterval()
        return sqrt(-2 * log(first)) * cos(2 * .pi * second)
    }

    /// 0…1 之间的均匀随机数。
    mutating func unitInterval() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
