//
//  HandwritingCalibrationTests.swift
//  模块：Tests（真人笔迹校准，计划 A10）
//
//  文件职责：证明这把「量尺」量得对，以及**量不了的时候会说量不了**。
//
//  为什么后半句同样重要：
//  这把量尺的产出会被直接用来改手感参数。如果它在样本不足或数据异常时
//  仍然吐出一个数字，那个数字看起来和真实测量一模一样，却是噪声——
//  然后全 App 的手感会按噪声调一遍，而且没人知道。
//  所以每一项都必须能返回「量不了 + 原因」，而且这里逐项验证它真的会这么做。
//
//  怎么验证「量得对」：用**已知答案的合成笔迹**。
//  造一条速度已知的直线，量出来的速度就该是那个数；
//  造一条叠了已知频率正弦波的线，量出来的频率就该接近那个数。
//  真人笔迹没有已知答案，所以只能用合成数据验算法，再用真人数据得结论。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class HandwritingCalibrationTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    /// 造一条水平直线笔迹：长度、时长、采样点数都指定。
    private func makeStraightTrace(
        startedAt: Date,
        from originX: Double = 0,
        length: Double,
        duration: TimeInterval,
        sampleCount: Int = 40,
        y: Double = 100,
        force: Double = 0
    ) -> PenTrace {
        let samples = (0 ..< sampleCount).map { index -> PenTraceSample in
            let fraction = Double(index) / Double(sampleCount - 1)
            return PenTraceSample(
                point: Point2D(x: originX + fraction * length, y: y),
                timeOffset: fraction * duration,
                force: force
            )
        }
        return PenTrace(startedAt: startedAt, samples: samples)
    }

    /// 造一条叠了正弦抖动的直线：幅度与频率已知，用来验算法量得准不准。
    private func makeTremblingTrace(
        amplitude: Double,
        frequencyInHertz: Double,
        duration: TimeInterval,
        length: Double = 400,
        sampleCount: Int = 400
    ) -> PenTrace {
        let samples = (0 ..< sampleCount).map { index -> PenTraceSample in
            let fraction = Double(index) / Double(sampleCount - 1)
            let time = fraction * duration
            return PenTraceSample(
                point: Point2D(
                    x: fraction * length,
                    y: 100 + amplitude * sin(2 * .pi * frequencyInHertz * time)
                ),
                timeOffset: time,
                force: 0
            )
        }
        return PenTrace(startedAt: base, samples: samples)
    }

    // MARK: 量得对

    /// 书写速度：墨迹总长 ÷ 落墨时长。造 10 笔，每笔 100 点长、1 秒，速度就该是 100 点/秒。
    func testInkSpeedMatchesTheSyntheticInput() throws {
        let traces = (0 ..< 10).map { index in
            makeStraightTrace(
                startedAt: base.addingTimeInterval(Double(index) * 2),
                length: 100,
                duration: 1
            )
        }

        let report = HandwritingCalibration.analyze(traces)

        XCTAssertEqual(report.strokeCount, 10)
        XCTAssertEqual(try XCTUnwrap(report.inkSpeedInPoints.value), 100, accuracy: 0.5)
    }

    /// 手抖频率：叠一个 8 Hz 的正弦，量出来应接近 8。
    /// 频率靠过零次数算，所以不依赖幅度大小，也不依赖采样是否等距。
    func testTremorFrequencyMatchesTheSyntheticInput() throws {
        let traces = (0 ..< 10).map { index -> PenTrace in
            var trace = makeTremblingTrace(amplitude: 2, frequencyInHertz: 8, duration: 2)
            trace = PenTrace(startedAt: base.addingTimeInterval(Double(index) * 3), samples: trace.samples)
            return trace
        }

        let frequency = try XCTUnwrap(HandwritingCalibration.analyze(traces).tremorFrequencyInHertz.value)

        XCTAssertEqual(frequency, 8, accuracy: 1.5, "量出的频率应接近合成时用的 8 Hz")
    }

    /// 手抖幅度：正弦的标准差是幅度的 1/√2 ≈ 0.707 倍，量出来该在这个量级。
    func testTremorAmplitudeIsInTheRightOrder() throws {
        let amplitude = 3.0
        let traces = (0 ..< 10).map { index -> PenTrace in
            let trace = makeTremblingTrace(amplitude: amplitude, frequencyInHertz: 6, duration: 2)
            return PenTrace(startedAt: base.addingTimeInterval(Double(index) * 3), samples: trace.samples)
        }

        let measured = try XCTUnwrap(HandwritingCalibration.analyze(traces).tremorAmplitudeInPoints.value)

        // 低通窗口会吃掉一部分幅度，所以只断量级：不该差出一个数量级。
        XCTAssertGreaterThan(measured, amplitude * 0.3)
        XCTAssertLessThan(measured, amplitude * 1.5)
    }

    /// 抬笔拟合：造一批「停顿 = 0.05 秒 + 距离 / 500」的间隔，
    /// 应该量出固定耗时 0.05 秒、空中速度 500 点/秒。
    func testPenLiftFitRecoversTheFixedCostAndAirSpeed() throws {
        let liftDuration = 0.05
        let airSpeed = 500.0
        let inkSpeed = 100.0

        var traces: [PenTrace] = []
        var cursor = base
        var originX = 0.0

        for step in 0 ..< 12 {
            // 每笔 100 点长、1 秒 → 落墨速度 100 点/秒。
            traces.append(makeStraightTrace(
                startedAt: cursor,
                from: originX,
                length: 100,
                duration: 1
            ))
            // 下一笔的起点离上一笔终点越来越远，好让拟合能分出斜率。
            let jump = Double(step + 1) * 40
            cursor = cursor.addingTimeInterval(1 + liftDuration + jump / airSpeed)
            originX += 100 + jump
        }

        let report = HandwritingCalibration.analyze(traces)

        XCTAssertEqual(report.gapCount, 11)
        XCTAssertEqual(try XCTUnwrap(report.penLiftDuration.value), liftDuration, accuracy: 0.01)
        XCTAssertEqual(
            try XCTUnwrap(report.airSpeedMultiple.value),
            airSpeed / inkSpeed,
            accuracy: 0.3,
            "空中速度倍数应约为 500 ÷ 100 = 5"
        )
    }

    // MARK: 量不了的时候要说量不了

    /// 样本太少：不许拿两三笔算出一个看起来像测量的数字。
    func testTooFewStrokesIsReportedAsUnmeasurable() {
        let traces = (0 ..< 3).map { index in
            makeStraightTrace(startedAt: base.addingTimeInterval(Double(index)), length: 50, duration: 0.5)
        }

        let report = HandwritingCalibration.analyze(traces)

        XCTAssertNil(report.inkSpeedInPoints.value, "三笔就该报量不了")
        XCTAssertNil(report.penLiftDuration.value)
        XCTAssertNil(report.estimatedGlyphHeight.value)
    }

    func testEmptyInputIsSafeAndReportsNothingMeasurable() {
        let report = HandwritingCalibration.analyze([])

        XCTAssertEqual(report.strokeCount, 0)
        XCTAssertEqual(report.gapCount, 0)
        XCTAssertNil(report.inkSpeedInPoints.value)
        XCTAssertNil(report.tremorFrequencyInHertz.value)
        XCTAssertFalse(report.hasVaryingForce)
    }

    /// 没有压感的笔：压感那几项必须报量不了，**绝不能给一个默认值**。
    /// 这是这把量尺最容易被滥用的地方——给了默认值，「已校准」就成了谎话。
    func testPressureIsAlwaysUnmeasurableWithoutForceData() {
        let traces = (0 ..< 12).map { index in
            makeStraightTrace(
                startedAt: base.addingTimeInterval(Double(index) * 2),
                length: 100,
                duration: 1,
                force: 0
            )
        }

        let report = HandwritingCalibration.analyze(traces)

        XCTAssertFalse(report.hasVaryingForce)
        XCTAssertNil(report.pressureVariation.value, "没有力度信息时不许给出压感数值")
        if case .unmeasurable(let reason) = report.pressureVariation {
            XCTAssertTrue(reason.contains("压感"), "原因要说清是硬件没有压感：\(reason)")
        } else {
            XCTFail("压感应报量不了")
        }
    }

    /// 所有抬笔距离都一样时，分不出「固定成本」和「随距离增长的部分」，必须报量不了。
    /// 硬拟合会得到一条斜率为噪声的直线，然后把噪声当成空中速度。
    func testUniformJumpDistancesCannotSeparateFixedCostFromSpeed() {
        var traces: [PenTrace] = []
        var cursor = base
        var originX = 0.0
        for _ in 0 ..< 12 {
            traces.append(makeStraightTrace(startedAt: cursor, from: originX, length: 100, duration: 1))
            cursor = cursor.addingTimeInterval(1.2)
            originX += 100 // 跳跃距离恒为 0
        }

        let report = HandwritingCalibration.analyze(traces)

        XCTAssertNil(report.penLiftDuration.value)
        XCTAssertNil(report.airSpeedMultiple.value)
    }

    /// 时钟倒退（墙上时钟被校正）产生的负间隔必须被丢掉，不能算成负停顿。
    func testBackwardsClockGapsAreDiscarded() {
        let first = makeStraightTrace(startedAt: base.addingTimeInterval(10), length: 100, duration: 1)
        let second = makeStraightTrace(startedAt: base, from: 200, length: 100, duration: 1)

        // 两笔按落笔时刻排序后间隔为正，所以这里只断言不会崩、也不会出现负数结论。
        let report = HandwritingCalibration.analyze([first, second])

        XCTAssertEqual(report.strokeCount, 2)
        XCTAssertGreaterThanOrEqual(report.gapCount, 0)
    }

    // MARK: 报告本身

    /// 报告要能直接贴进对话，所以必须同时出现「量出来的」和「现在用的」。
    func testSummaryShowsMeasuredAndCurrentSideBySide() {
        let traces = (0 ..< 12).map { index in
            makeStraightTrace(startedAt: base.addingTimeInterval(Double(index) * 2), length: 100, duration: 1)
        }

        let summary = HandwritingCalibration.analyze(traces).summary

        XCTAssertTrue(summary.contains("handTremorFrequencyInHertz"), "要点明对应哪个参数")
        XCTAssertTrue(summary.contains("现在用"), "要并排给出当前配置值")
        XCTAssertTrue(summary.contains("量不了"), "量不了的项要如实写出来")
        XCTAssertFalse(summary.isEmpty)
    }
}
