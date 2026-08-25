//
//  StrokePipelineTests.swift
//  模块：Tests（StrokeEngine 入口行为）
//
//  文件职责：验证 Pipeline 保留端点、可复现，并产出能播完的时间轴。
//
//  设计原因：
//  - 端点保真是硬要求：端点漂移会让笔画接头错位，因此单独断言首尾坐标。
//  - 删除位图路线后，原有的 raster 用例已随算法一并移除，不保留失效断言。
//

@testable import TomRiddlesDiary
import XCTest

final class StrokePipelineTests: XCTestCase {
    private let pipeline = StrokePipeline()

    func testOrderedSourcePreservesEndpoints() throws {
        let ordered = [Polyline(points: [Point2D(x: 2, y: 3), Point2D(x: 12, y: 3)])]
        // 关掉全部随机项，这样端点之外的差异不会干扰断言。
        let configuration = HumanizerConfiguration(
            jitterAmplitude: 0,
            durationVariation: 0,
            pressureVariation: 0
        )

        let sequence = pipeline.process(ordered, configuration: configuration)
        let stroke = try XCTUnwrap(sequence.strokes.first)

        XCTAssertEqual(stroke.samples.first?.point, Point2D(x: 2, y: 3))
        XCTAssertEqual(stroke.samples.last?.point, Point2D(x: 12, y: 3))
    }

    func testPipelineProducesCompletableTimeline() {
        let sequence = pipeline.process(
            [Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 30, y: 8), Point2D(x: 55, y: 40)])],
            seed: 11
        )
        let timeline = StrokeReplayTimeline(sequence: sequence)

        XCTAssertFalse(sequence.strokes.isEmpty)
        XCTAssertGreaterThan(sequence.totalDuration, 0)
        XCTAssertTrue(timeline.frame(at: timeline.totalDuration).isComplete)
    }

    func testWholePipelineIsDeterministicForSameSeed() {
        let input = [
            Polyline(points: [Point2D(x: 1, y: 1), Point2D(x: 20, y: 1)]),
            Polyline(points: [Point2D(x: 20, y: 1), Point2D(x: 20, y: 25)]),
        ]

        XCTAssertEqual(
            pipeline.process(input, seed: 123),
            pipeline.process(input, seed: 123)
        )
    }
}
