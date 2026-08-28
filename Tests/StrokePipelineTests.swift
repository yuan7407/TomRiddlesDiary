//
//  StrokePipelineTests.swift
//  模块：Tests（StrokeEngine 入口行为）
//
//  文件职责：验证 Pipeline 保留端点、可复现，并产出能播完的时间轴。
//
//  设计原因：
//  - 端点保真是硬要求：端点漂移会让笔画接头错位、闭合字形裂口，因此单独断言首尾坐标。
//  - 删除位图路线后，原有的 raster 用例已随算法一并移除，不保留失效断言。
//  - 参数与种子都显式传入：Pipeline 自 2026-08-27 起不再提供默认值，
//    因为尺度相关的参数没有普适默认值（计划 D1）。
//

@testable import TomRiddlesDiary
import XCTest

nonisolated final class StrokePipelineTests: XCTestCase {
    private let pipeline = StrokePipeline()

    func testOrderedSourcePreservesEndpoints() throws {
        let ordered = [Polyline(points: [Point2D(x: 2, y: 3), Point2D(x: 12, y: 3)])]
        // 基准夹具已关掉全部随机项，端点之外的差异不会干扰断言。
        let sequence = pipeline.process(
            ordered,
            configuration: HumanizerConfiguration.testBaseline(),
            seed: 7
        )
        let stroke = try XCTUnwrap(sequence.strokes.first)

        XCTAssertEqual(stroke.samples.first?.point, Point2D(x: 2, y: 3))
        XCTAssertEqual(stroke.samples.last?.point, Point2D(x: 12, y: 3))
    }

    func testPipelineProducesCompletableTimeline() {
        let sequence = pipeline.process(
            [Polyline(points: [Point2D(x: 0, y: 0), Point2D(x: 30, y: 8), Point2D(x: 55, y: 40)])],
            configuration: HumanizerConfiguration.testBaseline(jitterAmplitude: 0.5),
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
        let configuration = HumanizerConfiguration.testBaseline(
            jitterAmplitude: 0.5,
            durationVariation: 0.1,
            pressureVariation: 0.1
        )

        XCTAssertEqual(
            pipeline.process(input, configuration: configuration, seed: 123),
            pipeline.process(input, configuration: configuration, seed: 123)
        )
    }
}
