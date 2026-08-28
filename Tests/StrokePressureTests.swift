//
//  StrokePressureTests.swift
//  模块：Tests（压感的形状，计划 A2）
//
//  文件职责：证明压感沿笔画是**连续起伏**的，而且在转折处会变重。
//
//  为什么这两件事值得测：
//  A2 之前压感是逐点独立的随机数。线宽由压感决定，于是同一条线上粗细逐点乱跳，
//  看起来像一串珠子而不是一笔墨。这和 A1 的毛刺是同一类毛病，
//  改法也是同一套（沿弧长的平滑噪声），所以同一套判据也适用：
//  相邻两点的压感差必须远小于起伏幅度。白噪声下两个独立 N(0,σ) 之差的
//  平均绝对值约 1.13σ，连续起伏会低一个量级。
//
//  转折加成是另一件事：笔在急转处必须减速甚至几乎停住，笔尖停留久了墨渗得多，
//  所以拐角比直线段粗。没有它，横折竖折的转角会显得很塌。
//  这里断言的是「拐角确实更重」以及「这个效果由参数控制、能关掉」。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class StrokePressureTests: XCTestCase {
    private let humanizer = StrokeHumanizer()
    private let spacing: Double = 2

    /// 长直线，长度足够容纳多个压感波长。
    private var straightLine: Polyline {
        Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 400, y: 0)])
    }

    /// 直角折线：先向右 50，再向下 50。拐角正好落在第 25 个采样点上。
    private var rightAngle: Polyline {
        Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 50, y: 0), Point2D(x: 50, y: 50)])
    }

    private func pressures(
        of polyline: Polyline,
        variation: Double = 0,
        curvatureGain: Double = 0,
        taper: Double = 0,
        seed: UInt64 = 7
    ) throws -> [Double] {
        let configuration = HumanizerConfiguration.testBaseline(
            sampleSpacing: spacing,
            pressureVariation: variation,
            pressureWavelength: 20,
            curvaturePressureGain: curvatureGain,
            taperFraction: taper
        )
        return try XCTUnwrap(
            humanizer.humanize([polyline], configuration: configuration, seed: seed).strokes.first
        ).samples.map(\.pressure)
    }

    // MARK: 压感必须连续起伏，不能逐点乱跳

    /// 核心用例。判据取自白噪声的理论值 1.13σ，阈值留三倍余量取 0.35σ。
    func testPressureIsSmoothAlongTheStrokeNotWhiteNoise() throws {
        let variation = 0.2
        let values = try pressures(of: straightLine, variation: variation)
        let deltas = zip(values, values.dropFirst()).map { abs($1 - $0) }
        let meanDelta = deltas.reduce(0, +) / Double(deltas.count)

        XCTAssertLessThan(
            meanDelta,
            variation * 0.35,
            "相邻压感变化太大，线宽会逐点乱跳成一串珠子（白噪声的理论值约 1.13σ）"
        )
    }

    /// 起伏必须真的存在。这条防的是「为了让上面那条通过而把起伏改成 0」。
    func testPressureActuallyVaries() throws {
        let values = try pressures(of: straightLine, variation: 0.2)
        let span = (values.max() ?? 0) - (values.min() ?? 0)

        XCTAssertGreaterThan(span, 0.05, "压感几乎没有起伏")
    }

    /// 起伏为 0 时压感必须恒定——证明起伏确实只来自那一个参数。
    func testZeroVariationGivesConstantPressure() throws {
        let values = try pressures(of: straightLine, variation: 0)

        XCTAssertTrue(
            values.allSatisfy { abs($0 - (values.first ?? 0)) < 1e-12 },
            "关掉起伏之后压感应该完全一致"
        )
    }

    // MARK: 转折处更重

    /// 核心用例：直角拐角处的压感必须明显高于直线段。
    func testPressureIsHeavierAtASharpTurn() throws {
        let gain = 0.4
        let values = try pressures(of: rightAngle, curvatureGain: gain)

        // 拐角在弧长 50 处，采样间距 2，即索引 25。
        let corner = try XCTUnwrap(values.indices.contains(25) ? values[25] : nil)
        let straight = try XCTUnwrap(values.indices.contains(10) ? values[10] : nil)

        XCTAssertGreaterThan(corner, straight + 0.1, "急转处应该明显更重")
        // 直角是半个折回，所以加成应该约为 gain 的一半。
        XCTAssertEqual(corner - straight, gain * 0.5, accuracy: 0.02)
    }

    /// 加成为 0 时拐角和直线段一样重——证明这个效果由参数控制，能关掉。
    func testZeroCurvatureGainLeavesTheCornerUntouched() throws {
        let values = try pressures(of: rightAngle, curvatureGain: 0)

        XCTAssertEqual(values[25], values[10], accuracy: 1e-12)
    }

    /// 笔直的线上没有转折可加，加成再大也不该改变压感。
    func testStraightLineGetsNoCurvatureBoost() throws {
        let withGain = try pressures(of: straightLine, curvatureGain: 0.4)
        let withoutGain = try pressures(of: straightLine, curvatureGain: 0)

        for (a, b) in zip(withGain, withoutGain) {
            XCTAssertEqual(a, b, accuracy: 1e-9, "直线上不该出现转折加成")
        }
    }

    /// 加成再大也不许把压感顶出量程——线宽会算出负数或超粗。
    func testPressureStaysInRangeEvenWithAnExtremeCurvatureGain() throws {
        let configuration = HumanizerConfiguration.testBaseline(
            sampleSpacing: spacing,
            basePressure: 0.8,
            pressureVariation: 0.3,
            minimumPressure: 0.1,
            maximumPressure: 0.9,
            pressureWavelength: 20,
            curvaturePressureGain: 5,
            taperFraction: 0
        )
        let samples = try XCTUnwrap(
            humanizer.humanize([rightAngle], configuration: configuration, seed: 3).strokes.first
        ).samples

        XCTAssertTrue(
            samples.allSatisfy { $0.pressure.isFinite && (0.1 ... 0.9).contains($0.pressure) },
            "压感必须夹在量程内"
        )
    }

    // MARK: 生产配置

    /// 压感的波长必须比手抖的波长长得多：手抖是 10 Hz 的震颤，
    /// 而「按得多重」跟的是手臂用力，一秒变不了十次。
    /// 两者若取成同一个量级，粗细起伏就会和线条弯曲同步，看起来很假。
    func testShippingPressureWavelengthIsMuchLongerThanTheTremorWavelength() {
        let pressure = HandwritingFeel.pressureWavelengthInReferenceScales
        let tremor = HandwritingFeel.jitterWavelengthInReferenceScales

        XCTAssertGreaterThan(pressure, tremor * 2, "压感起伏应该比手抖慢一个量级")
    }
}
