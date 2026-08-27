//
//  StrokeHumanizerTests.swift
//  模块：Tests（手绘化算法）
//
//  文件职责：验证重采样、端点固定、压感边界、时序与同 seed 可复现。
//
//  设计原因：手感无法自动判定“好看”，因此只断言可验证的不变量
//  （端点不漂移、压感在界内、同 seed 结果一致），主观手感留给真机评审。
//  参数一律来自 `HumanizerConfiguration.testBaseline`，与生产调参解耦，
//  这样计划 A10 重新校准手感时不会让这些与手感无关的断言集体失败。
//

@testable import TomRiddlesDiary
import XCTest

final class StrokeHumanizerTests: XCTestCase {
    private let humanizer = StrokeHumanizer()

    func testResamplingPreservesEndpointsAndUsesExpectedSpacing() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)])
        // 抖动开得很大也不该动端点，这正是本例要证明的。
        let configuration = HumanizerConfiguration.testBaseline(sampleSpacing: 2, jitterAmplitude: 3)

        let stroke = try XCTUnwrap(
            humanizer.humanize([input], configuration: configuration, seed: 7).strokes.first
        )

        XCTAssertEqual(stroke.samples.count, 6)
        XCTAssertEqual(stroke.samples.first?.point, Point2D(x: 0, y: 0))
        XCTAssertEqual(stroke.samples.last?.point, Point2D(x: 10, y: 0))
    }

    func testSameSeedProducesIdenticalSequence() {
        let input = [Polyline(points: [
            Point2D(x: 0, y: 0),
            Point2D(x: 10, y: 4),
            Point2D(x: 20, y: 0),
        ])]
        // 必须开启抖动与浮动，否则「同 seed 结果一致」会因为根本没有随机项而恒真。
        let configuration = HumanizerConfiguration.testBaseline(
            jitterAmplitude: 0.5,
            durationVariation: 0.1,
            pressureVariation: 0.1
        )

        XCTAssertEqual(
            humanizer.humanize(input, configuration: configuration, seed: 42),
            humanizer.humanize(input, configuration: configuration, seed: 42)
        )
    }

    func testDifferentSeedsProduceDifferentVariation() {
        let input = [Polyline(points: [
            Point2D(x: 0, y: 0),
            Point2D(x: 10, y: 4),
            Point2D(x: 20, y: 0),
        ])]
        let configuration = HumanizerConfiguration.testBaseline(
            jitterAmplitude: 0.5,
            durationVariation: 0.1,
            pressureVariation: 0.1
        )

        XCTAssertNotEqual(
            humanizer.humanize(input, configuration: configuration, seed: 1),
            humanizer.humanize(input, configuration: configuration, seed: 2)
        )
    }

    func testZeroJitterKeepsStraightGeometry() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 3), Point2D(x: 8, y: 3)])
        let configuration = HumanizerConfiguration.testBaseline(sampleSpacing: 2)

        let stroke = try XCTUnwrap(
            humanizer.humanize([input], configuration: configuration, seed: 7).strokes.first
        )

        XCTAssertEqual(stroke.samples.map(\.point), [
            Point2D(x: 0, y: 3),
            Point2D(x: 2, y: 3),
            Point2D(x: 4, y: 3),
            Point2D(x: 6, y: 3),
            Point2D(x: 8, y: 3),
        ])
    }

    func testDuplicateZeroLengthPointsAreSafe() throws {
        let point = Point2D(x: 4, y: 9)
        let input = Polyline(points: [point, point, point])
        let configuration = HumanizerConfiguration.testBaseline(minimumDuration: 0.25)

        let stroke = try XCTUnwrap(
            humanizer.humanize([input], configuration: configuration, seed: 7).strokes.first
        )

        // 三个重合点塌缩成一个采样点（一个墨点），且靠最小时长兜底，不会瞬间闪现。
        XCTAssertEqual(stroke.samples.count, 1)
        XCTAssertEqual(stroke.samples[0].point, point)
        XCTAssertEqual(stroke.duration, 0.25, accuracy: 1e-12)
    }

    func testMinimumDurationIsEnforced() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0)])
        let configuration = HumanizerConfiguration.testBaseline(
            inkLengthPerSecond: 10_000,
            minimumDuration: 0.4
        )

        let stroke = try XCTUnwrap(
            humanizer.humanize([input], configuration: configuration, seed: 7).strokes.first
        )
        XCTAssertEqual(stroke.duration, 0.4, accuracy: 1e-12)
    }

    func testDurationScalesWithLengthWhenVariationIsDisabled() {
        let configuration = HumanizerConfiguration.testBaseline(inkLengthPerSecond: 10)
        let short = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)])
        let long = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 20, y: 0)])
        let sequence = humanizer.humanize([short, long], configuration: configuration, seed: 7)

        XCTAssertEqual(sequence.strokes[0].duration, 1, accuracy: 1e-12)
        XCTAssertEqual(sequence.strokes[1].duration, 2, accuracy: 1e-12)
    }

    func testPressureIsBoundedAndTapersAtBothEnds() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 30, y: 0)])
        let configuration = HumanizerConfiguration.testBaseline(
            sampleSpacing: 2,
            basePressure: 0.8,
            pressureVariation: 0.2,
            minimumPressure: 0.1,
            maximumPressure: 0.9,
            taperFraction: 0.2
        )

        let samples = try XCTUnwrap(
            humanizer.humanize([input], configuration: configuration, seed: 7).strokes.first
        ).samples

        let firstPressure = try XCTUnwrap(samples.first?.pressure)
        let lastPressure = try XCTUnwrap(samples.last?.pressure)
        XCTAssertEqual(firstPressure, 0.1, accuracy: 1e-12)
        XCTAssertEqual(lastPressure, 0.1, accuracy: 1e-12)
        XCTAssertGreaterThan(samples[samples.count / 2].pressure, 0.1)
        XCTAssertTrue(samples.allSatisfy { $0.pressure.isFinite && (0.1 ... 0.9).contains($0.pressure) })
    }

    func testHumanizationDoesNotMutateInputValue() {
        let original = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 5)])
        let snapshot = original

        _ = humanizer.humanize(
            [original],
            configuration: HumanizerConfiguration.testBaseline(jitterAmplitude: 0.5),
            seed: 99
        )

        XCTAssertEqual(original, snapshot)
    }
}
