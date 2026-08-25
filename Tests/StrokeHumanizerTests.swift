//
//  StrokeHumanizerTests.swift
//  模块：Tests（手绘化算法）
//
//  文件职责：验证重采样、端点固定、压感边界、时序与同 seed 可复现。
//
//  设计原因：手感无法自动判定“好看”，因此只断言可验证的不变量
//  （端点不漂移、压感在界内、同 seed 结果一致），主观手感留给真机评审。
//

@testable import TomRiddlesDiary
import XCTest

@MainActor
final class StrokeHumanizerTests: XCTestCase {
    private let humanizer = StrokeHumanizer()

    func testResamplingPreservesEndpointsAndUsesExpectedSpacing() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)])
        let configuration = HumanizerConfiguration(
            sampleSpacing: 2,
            jitterAmplitude: 3,
            durationVariation: 0,
            pressureVariation: 0
        )

        let stroke = try XCTUnwrap(humanizer.humanize([input], configuration: configuration).strokes.first)

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

        XCTAssertEqual(
            humanizer.humanize(input, seed: 42),
            humanizer.humanize(input, seed: 42)
        )
    }

    func testDifferentSeedsProduceDifferentVariation() {
        let input = [Polyline(points: [
            Point2D(x: 0, y: 0),
            Point2D(x: 10, y: 4),
            Point2D(x: 20, y: 0),
        ])]

        XCTAssertNotEqual(
            humanizer.humanize(input, seed: 1),
            humanizer.humanize(input, seed: 2)
        )
    }

    func testZeroJitterKeepsStraightGeometry() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 3), Point2D(x: 8, y: 3)])
        let configuration = HumanizerConfiguration(
            sampleSpacing: 2,
            jitterAmplitude: 0,
            durationVariation: 0,
            pressureVariation: 0
        )

        let stroke = try XCTUnwrap(humanizer.humanize([input], configuration: configuration).strokes.first)

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

        let stroke = try XCTUnwrap(humanizer.humanize([input]).strokes.first)

        XCTAssertEqual(stroke.samples.count, 1)
        XCTAssertEqual(stroke.samples[0].point, point)
        XCTAssertEqual(stroke.duration, 0.25, accuracy: 1e-12)
    }

    func testMinimumDurationIsEnforced() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0)])
        let configuration = HumanizerConfiguration(
            jitterAmplitude: 0,
            pointsPerSecond: 10_000,
            durationVariation: 0,
            minimumDuration: 0.4,
            pressureVariation: 0
        )

        let stroke = try XCTUnwrap(humanizer.humanize([input], configuration: configuration).strokes.first)
        XCTAssertEqual(stroke.duration, 0.4, accuracy: 1e-12)
    }

    func testDurationScalesWithLengthWhenVariationIsDisabled() {
        let configuration = HumanizerConfiguration(
            jitterAmplitude: 0,
            pointsPerSecond: 10,
            durationVariation: 0,
            minimumDuration: 0,
            pressureVariation: 0
        )
        let short = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)])
        let long = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 20, y: 0)])
        let sequence = humanizer.humanize([short, long], configuration: configuration)

        XCTAssertEqual(sequence.strokes[0].duration, 1, accuracy: 1e-12)
        XCTAssertEqual(sequence.strokes[1].duration, 2, accuracy: 1e-12)
    }

    func testPressureIsBoundedAndTapersAtBothEnds() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 30, y: 0)])
        let configuration = HumanizerConfiguration(
            sampleSpacing: 2,
            jitterAmplitude: 0,
            durationVariation: 0,
            basePressure: 0.8,
            pressureVariation: 0.2,
            minimumPressure: 0.1,
            maximumPressure: 0.9,
            taperFraction: 0.2
        )

        let samples = try XCTUnwrap(humanizer.humanize([input], configuration: configuration).strokes.first).samples

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

        _ = humanizer.humanize([original], seed: 99)

        XCTAssertEqual(original, snapshot)
    }
}
