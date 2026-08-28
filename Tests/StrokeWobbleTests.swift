//
//  StrokeWobbleTests.swift
//  模块：Tests（手抖的形状，计划 A1）
//
//  文件职责：证明抖动是「沿笔画的连续摆动」而不是「逐点独立的白噪声」。
//
//  为什么这件事必须有测试盯着：
//  两者在代码上只差几行，在小字号的截图上也不容易分辨，但观感完全不同——
//  白噪声让线条边缘起锯齿（像画质差），连续摆动让线条整体轻微弯曲（像手写）。
//  A1 之前就是白噪声，而且因为难看，抖动幅度被压到几乎看不见，功能形同虚设。
//  如果哪天有人「顺手简化」回逐点随机，界面上不会报错，只会慢慢变丑。
//
//  怎么测「像手抖」这种主观的东西：
//  不去断言好看，而是断言两个可量化的几何性质——
//  一、相邻采样点的偏移量必须接近（相关噪声）。白噪声下相邻偏移是独立的，
//      两个独立正态变量之差的平均绝对值约为 1.13σ；连续摆动下这个数会小一个量级。
//  二、偏移方向必须垂直于笔画。沿切线推点只改变点的疏密，看不出来。
//
//  用一条水平直线做输入：这样每个点的法线都是 y 方向，偏移量就是 y 坐标本身，
//  不需要再反推，断言可以直接读。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class StrokeWobbleTests: XCTestCase {
    private let humanizer = StrokeHumanizer()

    private let spacing: Double = 2
    private let amplitude: Double = 1
    private let wavelength: Double = 20
    private let lineLength: Double = 400

    /// 水平直线，长度足够容纳二十个波长。
    private var straightLine: Polyline {
        Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: lineLength, y: 0)])
    }

    private var configuration: HumanizerConfiguration {
        .testBaseline(sampleSpacing: spacing, jitterAmplitude: amplitude, jitterWavelength: wavelength)
    }

    private func wobbledLine(seed: UInt64 = 7) throws -> [StrokeSample] {
        try XCTUnwrap(
            humanizer.humanize([straightLine], configuration: configuration, seed: seed).strokes.first
        ).samples
    }

    // MARK: 摆动的形状

    /// 核心用例：相邻点的偏移必须接近，也就是噪声沿笔画是连续的。
    ///
    /// 判据取自白噪声的理论值：两个独立 N(0, σ) 之差的平均绝对值是 2σ/√π ≈ 1.13σ。
    /// 连续摆动应该远低于它。阈值取 0.35σ——留了三倍余量，同时白噪声绝无可能通过。
    func testWobbleIsCorrelatedAlongTheStrokeNotWhiteNoise() throws {
        let offsets = try wobbledLine().map(\.point.y)
        let deltas = zip(offsets, offsets.dropFirst()).map { abs($1 - $0) }
        let meanDelta = deltas.reduce(0, +) / Double(deltas.count)

        XCTAssertLessThan(
            meanDelta,
            amplitude * 0.35,
            "相邻偏移变化太大，说明抖动退化成了逐点白噪声（白噪声的理论值约 1.13σ）"
        )
    }

    /// 摆动的方向翻转次数必须很少。白噪声下大约一半的相邻点之间就会换向。
    func testWobbleReversesDirectionOnlyAFewTimes() throws {
        let offsets = try wobbledLine().map(\.point.y)
        let reversals = zip(offsets, offsets.dropFirst()).count { previous, next in
            (previous < 0) != (next < 0)
        }

        // 二十个波长最多也就换向二十几次；白噪声在 200 个点上会换向近一百次。
        XCTAssertLessThan(reversals, 30, "换向太频繁，看起来会是毛刺而不是手抖")
    }

    /// 摆动必须真的存在，而且量级对得上幅度参数。
    /// 这条防的是「为了让上面两条通过而把抖动改成 0」。
    func testWobbleActuallyMovesTheLineByRoughlyTheAmplitude() throws {
        let offsets = try wobbledLine().map(\.point.y)
        let peak = offsets.map(abs).max() ?? 0

        XCTAssertGreaterThan(peak, amplitude * 0.5, "抖动几乎没有发生")
        XCTAssertLessThan(peak, amplitude * 5, "峰值远超幅度参数，说明量级算错了")
    }

    // MARK: 方向与端点

    /// 偏移必须垂直于笔画：水平线的 x 坐标应当保持等距不变。
    func testWobbleIsPerpendicularSoSpacingAlongTheStrokeIsUntouched() throws {
        let xs = try wobbledLine().map(\.point.x)

        for (index, x) in xs.enumerated() where index < xs.count - 1 {
            XCTAssertEqual(
                x, Double(index) * spacing, accuracy: 1e-9,
                "第 \(index) 点沿笔画方向被推动了，抖动不该改变点的疏密"
            )
        }
    }

    /// 端点绝对不许移动：笔画接头会错位、闭合图形会裂口。
    /// A1 之后这一点不靠特判保证，而是靠首尾控制值为 0 自然成立——
    /// 所以更需要测，实现方式变了它可能悄悄失效。
    func testEndpointsNeverMove() throws {
        for seed in [UInt64(1), 7, 42, 12345] {
            let samples = try wobbledLine(seed: seed)
            XCTAssertEqual(samples.first?.point, Point2D(x: 0, y: 0), "seed \(seed) 起点被移动了")
            XCTAssertEqual(samples.last?.point, Point2D(x: lineLength, y: 0), "seed \(seed) 终点被移动了")
        }
    }

    /// 短于一个波长的笔画完全不抖。这是刻意的：笔尖还没走够半个摆动周期，
    /// 本来就看不出弯。硬给它加抖动等于凭空编造。
    func testStrokesShorterThanOneWavelengthDoNotWobble() throws {
        let short = Polyline(points: [Point2D(x: 0, y: 5), Point2D(x: wavelength / 2, y: 5)])
        let samples = try XCTUnwrap(
            humanizer.humanize([short], configuration: configuration, seed: 7).strokes.first
        ).samples

        XCTAssertTrue(
            samples.allSatisfy { abs($0.point.y - 5) < 1e-12 },
            "短笔画不该有摆动"
        )
    }

    // MARK: 波长的作用

    /// 波长越长，线条弯得越缓。这条确认波长这个参数真的接上了，
    /// 而不是被忽略掉（被忽略时两组结果的平滑度会一样）。
    func testLongerWavelengthProducesSmootherWobble() throws {
        func meanDelta(wavelength: Double) throws -> Double {
            let samples = try XCTUnwrap(
                humanizer.humanize(
                    [straightLine],
                    configuration: .testBaseline(
                        sampleSpacing: spacing,
                        jitterAmplitude: amplitude,
                        jitterWavelength: wavelength
                    ),
                    seed: 7
                ).strokes.first
            ).samples
            let offsets = samples.map(\.point.y)
            let deltas = zip(offsets, offsets.dropFirst()).map { abs($1 - $0) }
            return deltas.reduce(0, +) / Double(deltas.count)
        }

        let tight = try meanDelta(wavelength: 8)
        let loose = try meanDelta(wavelength: 80)

        XCTAssertLessThan(loose, tight, "波长变长时线条应该弯得更缓")
    }

    /// 生产配置算出来的波长必须比采样间距大若干倍，否则摆动会退化成毛刺
    /// （手绘化里有 precondition 直接崩，这里让它在测试中先暴露）。
    func testShippingWavelengthIsMuchLargerThanSampleSpacing() {
        let ratio = HandwritingFeel.jitterWavelengthInReferenceScales / HandwritingFeel.sampleSpacingRatio

        XCTAssertGreaterThan(ratio, 5, "一个波长内至少要有若干个采样点，否则摆动画不出来")
    }
}
