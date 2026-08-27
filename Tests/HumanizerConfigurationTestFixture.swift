//
//  HumanizerConfigurationTestFixture.swift
//  模块：Tests（测试夹具）
//
//  文件职责：给测试提供一份数值显式、可逐项覆盖的手绘化参数。
//
//  设计原因：
//  - `HumanizerConfiguration` 刻意没有默认值（计划 D1/D2），因为它的前三个字段是
//    尺度相关的，任何默认值都只在某个特定字号下成立。但每个测试都写全十个参数
//    会把断言埋在噪声里，所以夹具集中放在这里，只在测试目标内可见。
//  - 夹具**故意不复用** `HandwritingFeel` 的生产数值。原因：生产参数会在计划 A10
//    用真人笔迹重新校准，若测试直接依赖它们，一次调参就会让一批与手感无关的
//    断言（采样点个数、时长、端点坐标）集体失败。这不违反「同一参数不得两套值」
//    ——那条规则约束的是生产参数，测试基准是独立的输入数据。
//  - 默认把抖动与各类随机浮动设为 0，让几何与时序断言可以精确比较；需要验证
//    随机性的测试再显式传入非零值。
//

import Foundation
@testable import TomRiddlesDiary

extension HumanizerConfiguration {
    /// 测试基准参数。所有数值与生产配置无关，仅为让断言稳定。
    static func testBaseline(
        sampleSpacing: Double = 2,
        jitterAmplitude: Double = 0,
        inkLengthPerSecond: Double = 10,
        durationVariation: Double = 0,
        minimumDuration: TimeInterval = 0,
        basePressure: Double = 0.7,
        pressureVariation: Double = 0,
        minimumPressure: Double = 0.12,
        maximumPressure: Double = 0.92,
        taperFraction: Double = 0.16
    ) -> HumanizerConfiguration {
        HumanizerConfiguration(
            sampleSpacing: sampleSpacing,
            jitterAmplitude: jitterAmplitude,
            inkLengthPerSecond: inkLengthPerSecond,
            durationVariation: durationVariation,
            minimumDuration: minimumDuration,
            basePressure: basePressure,
            pressureVariation: pressureVariation,
            minimumPressure: minimumPressure,
            maximumPressure: maximumPressure,
            taperFraction: taperFraction
        )
    }
}
