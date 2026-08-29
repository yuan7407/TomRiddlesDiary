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

nonisolated final class StrokeHumanizerTests: XCTestCase {
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

    /// 压感必须始终落在量程内，而**起收笔的渐细由「接触」负责，不是压低压感**
    /// （计划 A5，2026-08-29 起）。
    ///
    /// 之前这条断言的是「首尾压感等于压感下限」——那时渐细压在压感上。
    /// 但压感映射到线宽有 60% 的下限（那个下限本身是对的：手写时线不会细成头发），
    /// 于是渐细最多把线收到 60%，永远收不到零。两个概念分开之后，
    /// 压感保持它该有的范围，接触负责「笔尖离纸」。
    func testPressureStaysInRangeWhileContactTapersToZero() throws {
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

        // 压感：全程落在量程内，首尾不再被压到下限。
        XCTAssertTrue(samples.allSatisfy { $0.pressure.isFinite && (0.1 ... 0.9).contains($0.pressure) })

        // 接触：首尾为 0，中间为 1。这才是「收笔收到零宽」的来源。
        XCTAssertEqual(try XCTUnwrap(samples.first?.contact), 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(samples.last?.contact), 0, accuracy: 1e-12)
        XCTAssertEqual(samples[samples.count / 2].contact, 1, accuracy: 1e-12)
    }

    /// 核心用例：收笔的线宽必须真的收到 0。
    /// 这条是 A5 的验收条件——在此之前它最细只能到满宽的 60%。
    func testStrokeWidthReachesZeroAtBothEnds() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 30, y: 0)])
        let configuration = HumanizerConfiguration.testBaseline(
            sampleSpacing: 2,
            basePressure: 0.7,
            taperFraction: 0.2
        )

        let samples = try XCTUnwrap(
            humanizer.humanize([input], configuration: configuration, seed: 7).strokes.first
        ).samples
        let first = try XCTUnwrap(samples.first)
        let middle = samples[samples.count / 2]

        XCTAssertEqual(
            PageAppearance.inkWidth(forPressure: first.pressure, contact: first.contact),
            0,
            accuracy: 1e-12,
            "起笔的线宽应该是 0"
        )
        XCTAssertGreaterThan(
            PageAppearance.inkWidth(forPressure: middle.pressure, contact: middle.contact),
            0,
            "笔画中段必须有宽度"
        )
    }

    /// 收笔渐细必须是**逐渐**的，不能最后一步从满宽跳到零。
    func testWidthDecreasesMonotonicallyIntoTheEnd() throws {
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 40, y: 0)])
        let configuration = HumanizerConfiguration.testBaseline(
            sampleSpacing: 2,
            basePressure: 0.7,
            taperFraction: 0.25
        )

        let samples = try XCTUnwrap(
            humanizer.humanize([input], configuration: configuration, seed: 7).strokes.first
        ).samples

        // 取最后四分之一，宽度应当一路不增。
        let tail = samples.suffix(samples.count / 4)
        var previous = Double.greatestFiniteMagnitude
        for sample in tail {
            let width = PageAppearance.inkWidth(forPressure: sample.pressure, contact: sample.contact)
            XCTAssertLessThanOrEqual(width, previous + 1e-9, "收笔的宽度出现了回升")
            previous = width
        }
    }

    /// 等分重采样：首尾点精确落在笔画两端，而且**末尾不许出现退化线段**（计划 A8）。
    ///
    /// 原来的写法是按固定步长累加、走不到总长就停、最后再把总长补上。
    /// 若总长刚好只比上一个点多一点，末尾就会多出一段长度接近 0 的线段——
    /// 摆动要在那里算法线（方向退化）、收笔渐细要在那里判断位置、渲染要画一段看不见的线，
    /// 全都不会报错，只会让收笔处偶发地不对劲。
    func testResamplingLeavesNoDegenerateSegmentAtTheEnd() throws {
        // 总长 10.5，间距 2：老写法会在 10 和 10.5 之间留下一段 0.5 的碎尾。
        let input = Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 10.5, y: 0)])
        let configuration = HumanizerConfiguration.testBaseline(sampleSpacing: 2)

        let samples = try XCTUnwrap(
            humanizer.humanize([input], configuration: configuration, seed: 7).strokes.first
        ).samples

        XCTAssertEqual(samples.first?.point, Point2D(x: 0, y: 0))
        XCTAssertEqual(samples.last?.point, Point2D(x: 10.5, y: 0))

        let gaps = zip(samples, samples.dropFirst()).map { $0.point.distance(to: $1.point) }
        let shortest = gaps.min() ?? 0
        let longest = gaps.max() ?? 0
        XCTAssertEqual(shortest, longest, accuracy: 1e-9, "间距应当完全均匀，末尾没有碎段")
        XCTAssertGreaterThan(shortest, 1, "碎段（远小于间距的一段）不该存在")
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
