//
//  PencilStrokeReaderTests.swift
//  模块：Tests（把手写读成引擎能吃的笔画）
//
//  文件职责：验证 PencilKit 的手写记录能被正确读成有序坐标，且力度信息如实报告。
//
//  设计原因：
//  这是全工程第一个真实的 `[Polyline]` 生产源，引擎此前一直没有真实输入。
//  它出错的表现是「写了字但引擎收到空的」或者「坐标错位」，在界面上看不出是哪一层
//  的问题，所以必须有可断言的不变量：笔数对得上、采样点按步长铺开、笔画自身的
//  仿射变换被应用、以及**没有压感时如实报告没有，而不是编一个出来**。
//
//  这些测试用程序构造的 PKDrawing，不需要 Apple Pencil，因此在模拟器里就能跑。
//  但它们只证明「读得对」，不证明「真人手写读出来好看」——后者要真机。
//

import CoreGraphics
import PencilKit
@testable import TomRiddlesDiary
import XCTest

nonisolated final class PencilStrokeReaderTests: XCTestCase {
    private let reader = PencilStrokeReader()

    /// 造一笔水平直线。force 可以给成固定值或按点变化。
    private func makeStroke(
        from start: CGPoint,
        to end: CGPoint,
        pointCount: Int = 24,
        force: (Int) -> CGFloat = { _ in 1 },
        transform: CGAffineTransform = .identity
    ) -> PKStroke {
        var points: [PKStrokePoint] = []
        for index in 0 ..< pointCount {
            let t = pointCount == 1 ? 0 : CGFloat(index) / CGFloat(pointCount - 1)
            points.append(PKStrokePoint(
                location: CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                ),
                timeOffset: Double(t) * 0.5,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: force(index),
                azimuth: 0,
                altitude: .pi / 2
            ))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path, transform: transform)
    }

    func testEmptyDrawingReadsAsEmpty() {
        let reading = reader.read(PKDrawing())

        XCTAssertTrue(reading.isEmpty)
        XCTAssertFalse(reading.hasVaryingForce)
        XCTAssertNil(reading.observedForceRange, "没有采样点就不该报告力度范围")
    }

    func testOneStrokeBecomesOnePolyline() {
        let stroke = makeStroke(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 210, y: 20))
        let reading = reader.read(PKDrawing(strokes: [stroke]))

        XCTAssertEqual(reading.polylines.count, 1)
        XCTAssertGreaterThan(reading.polylines[0].points.count, 2, "一条 200 点长的线该采出多个点")
    }

    func testThreeStrokesBecomeThreePolylinesInOrder() {
        let strokes = [
            makeStroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)),
            makeStroke(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50)),
            makeStroke(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 100, y: 100)),
        ]
        let reading = reader.read(PKDrawing(strokes: strokes))

        XCTAssertEqual(reading.polylines.count, 3)
        // 笔顺必须保持：引擎按数组顺序逐笔重播，顺序错了就是写字顺序错了。
        let firstYs = reading.polylines.compactMap { $0.points.first?.y }
        XCTAssertEqual(firstYs, firstYs.sorted(), "笔画顺序必须与书写顺序一致")
    }

    func testSampledPointsFollowTheStrokeGeometry() throws {
        let stroke = makeStroke(from: CGPoint(x: 30, y: 60), to: CGPoint(x: 230, y: 60))
        let reading = reader.read(PKDrawing(strokes: [stroke]))
        let points = try XCTUnwrap(reading.polylines.first).points

        // 水平线上所有采样点的 y 应该一致，x 应该递增。
        XCTAssertTrue(points.allSatisfy { abs($0.y - 60) < 0.5 }, "水平笔画的采样点不该偏离基准线")
        let xs = points.map(\.x)
        XCTAssertEqual(xs, xs.sorted(), "采样点必须沿书写方向推进")
        XCTAssertGreaterThan(xs.last ?? 0, xs.first ?? 0)
    }

    func testSamplingIsRoughlyEquidistant() throws {
        let stroke = makeStroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 300, y: 0))
        let reading = reader.read(PKDrawing(strokes: [stroke]))
        let points = try XCTUnwrap(reading.polylines.first).points

        let gaps = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        let longest = try XCTUnwrap(gaps.max())
        let shortest = try XCTUnwrap(gaps.min())

        // 不断言精确步长（那是框架实现细节），只断言没有异常稀疏的段落——
        // 采样过疏会让引擎丢掉笔画的弯度。
        XCTAssertGreaterThan(shortest, 0)
        XCTAssertLessThan(longest, shortest * 4, "采样间距不该忽疏忽密")
    }

    func testStrokeTransformIsApplied() throws {
        // 同一笔，一次不带变换，一次整体右移 500。读出来必须差 500。
        let plain = makeStroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let shifted = makeStroke(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            transform: CGAffineTransform(translationX: 500, y: 0)
        )

        let plainFirst = try XCTUnwrap(reader.read(PKDrawing(strokes: [plain])).polylines.first?.points.first)
        let shiftedFirst = try XCTUnwrap(reader.read(PKDrawing(strokes: [shifted])).polylines.first?.points.first)

        XCTAssertEqual(shiftedFirst.x - plainFirst.x, 500, accuracy: 1, "笔画自身的仿射变换必须被应用")
    }

    // MARK: 力度：如实报告，不编造

    func testConstantForceIsReportedAsNoUsablePressure() {
        // 模拟器的鼠标、USB-C Apple Pencil、第三方笔都给不出变化的力度。
        let stroke = makeStroke(from: .zero, to: CGPoint(x: 200, y: 0), force: { _ in 1 })
        let reading = reader.read(PKDrawing(strokes: [stroke]))

        XCTAssertFalse(reading.hasVaryingForce, "力度恒定就是没有压感信息，不得当成有")
        XCTAssertEqual(reading.observedForceRange?.lowerBound, reading.observedForceRange?.upperBound)
    }

    func testZeroForceIsAlsoReportedAsNoUsablePressure() {
        let stroke = makeStroke(from: .zero, to: CGPoint(x: 200, y: 0), force: { _ in 0 })
        let reading = reader.read(PKDrawing(strokes: [stroke]))

        XCTAssertFalse(reading.hasVaryingForce, "力度恒为 0 与恒为其他值一样，都是没有压感")
    }

    func testVaryingForceIsReportedWithItsObservedRange() throws {
        let stroke = makeStroke(
            from: .zero,
            to: CGPoint(x: 200, y: 0),
            pointCount: 20,
            force: { index in 0.2 + CGFloat(index) * 0.05 }
        )
        let reading = reader.read(PKDrawing(strokes: [stroke]))

        XCTAssertTrue(reading.hasVaryingForce)
        let range = try XCTUnwrap(reading.observedForceRange)
        XCTAssertLessThan(range.lowerBound, range.upperBound)
        // 不断言具体数值：force 的量程由设备决定，断言它等于我造的输入
        // 会把「PencilKit 的插值」也一起断言进来。只断言区间有宽度且有限。
        XCTAssertTrue(range.lowerBound.isFinite && range.upperBound.isFinite)
    }

    func testReadingFeedsTheStrokeEngineEndToEnd() throws {
        // 这条是本文件的意义所在：证明用户手写真的能一路走到可重播的笔画序列。
        // 引擎此前没有任何真实输入源，只能靠手打夹具（已删除）。
        let strokes = [
            makeStroke(from: CGPoint(x: 20, y: 40), to: CGPoint(x: 120, y: 40)),
            makeStroke(from: CGPoint(x: 70, y: 20), to: CGPoint(x: 70, y: 90)),
        ]
        let reading = reader.read(PKDrawing(strokes: strokes))

        let sequence = StrokePipeline().process(
            reading.polylines,
            configuration: HandwritingFeel.humanizerConfiguration(),
            seed: HandwritingFeel.defaultSeed
        )

        XCTAssertEqual(sequence.strokes.count, 2, "两笔手写应产出两笔可重播笔画")
        XCTAssertGreaterThan(sequence.totalDuration, 0)
        XCTAssertTrue(
            StrokeReplayTimeline(sequence: sequence).frame(at: sequence.totalDuration).isComplete,
            "时间轴应能播完"
        )
    }
}
