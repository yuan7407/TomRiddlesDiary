//
//  WritingRhythmTests.swift
//  模块：Tests（书写节奏）
//
//  文件职责：验证笔间停顿算得对，因为它是成页阈值的唯一依据。
//
//  设计原因：
//  计划 E3c 的成页触发阈值必须从**真实停顿分布**量出来，不能像原来那个「抬笔
//  2.8 秒」一样拍一个数。既然阈值要靠这份测量，那这份测量本身必须先被验证——
//  测错了，后面所有基于它的判断都错，而且在界面上完全看不出来。
//
//  停顿定义：上一笔**抬笔**到下一笔**落笔**的间隔，不是两笔落笔时刻之差。
//  后者会把书写本身的时间算进停顿里，写得慢的人会被误判成一直在发呆。
//

import Foundation
import PencilKit
@testable import TomRiddlesDiary
import XCTest

nonisolated final class WritingRhythmTests: XCTestCase {
    private let reader = PencilStrokeReader()

    /// 造一笔：指定落笔时刻与书写时长。
    private func makeStroke(startingAt start: Date, lasting duration: TimeInterval) -> PKStroke {
        var points: [PKStrokePoint] = []
        let steps = 10
        for step in 0 ... steps {
            let t = Double(step) / Double(steps)
            points.append(PKStrokePoint(
                location: CGPoint(x: 20 + t * 80, y: 50),
                timeOffset: t * duration,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 0,
                azimuth: 0,
                altitude: .pi / 2
            ))
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: start)
        )
    }

    func testEmptyDrawingHasNoRhythm() {
        let rhythm = reader.read(PKDrawing()).rhythm

        XCTAssertTrue(rhythm.pauses.isEmpty)
        XCTAssertEqual(rhythm.totalDuration, 0)
        XCTAssertEqual(rhythm.inkDuration, 0)
        XCTAssertNil(rhythm.medianPause)
        XCTAssertNil(rhythm.longestPause)
    }

    func testSingleStrokeHasNoPauses() {
        let drawing = PKDrawing(strokes: [makeStroke(startingAt: Date(), lasting: 0.5)])
        let rhythm = reader.read(drawing).rhythm

        XCTAssertTrue(rhythm.pauses.isEmpty, "一笔之内没有笔间停顿")
        XCTAssertEqual(rhythm.inkDuration, 0.5, accuracy: 0.01)
        XCTAssertEqual(rhythm.totalDuration, 0.5, accuracy: 0.01)
    }

    /// 核心用例：停顿必须是「抬笔到落笔」，不是「落笔到落笔」。
    func testPauseIsMeasuredFromPenUpToPenDown() {
        let base = Date()
        // 第一笔 0.0→0.4 秒，第二笔 1.4→1.8 秒。抬笔到落笔的间隔是 1.0 秒。
        // 若错算成落笔时刻之差，会得到 1.4 秒。
        let drawing = PKDrawing(strokes: [
            makeStroke(startingAt: base, lasting: 0.4),
            makeStroke(startingAt: base.addingTimeInterval(1.4), lasting: 0.4),
        ])
        let rhythm = reader.read(drawing).rhythm

        XCTAssertEqual(rhythm.pauses.count, 1)
        XCTAssertEqual(rhythm.pauses[0], 1.0, accuracy: 0.02, "停顿应为 1.0 秒而不是 1.4 秒")
    }

    func testPauseCountIsOneFewerThanStrokeCount() {
        let base = Date()
        let drawing = PKDrawing(strokes: (0 ..< 5).map { index in
            makeStroke(startingAt: base.addingTimeInterval(Double(index)), lasting: 0.3)
        })
        let rhythm = reader.read(drawing).rhythm

        XCTAssertEqual(rhythm.pauses.count, 4, "五笔之间有四个停顿")
    }

    func testInkDurationExcludesPauses() {
        let base = Date()
        let drawing = PKDrawing(strokes: [
            makeStroke(startingAt: base, lasting: 0.5),
            makeStroke(startingAt: base.addingTimeInterval(10), lasting: 0.5),
        ])
        let rhythm = reader.read(drawing).rhythm

        XCTAssertEqual(rhythm.inkDuration, 1.0, accuracy: 0.02, "落墨时长只算笔画本身")
        XCTAssertEqual(rhythm.totalDuration, 10.5, accuracy: 0.02, "总时长含停顿")
    }

    /// 中位数而不是平均值：一次发呆不该把「平常停顿多长」这个判断带偏。
    /// 这直接关系到 E3c 的阈值会不会被一次走神污染。
    func testMedianPauseIgnoresOneLongOutlier() {
        let base = Date()
        var strokes: [PKStroke] = []
        var cursor = base
        // 四个 0.3 秒的短停顿，最后接一个 60 秒的长停顿。
        for gap in [0.3, 0.3, 0.3, 0.3, 60.0] {
            strokes.append(makeStroke(startingAt: cursor, lasting: 0.2))
            cursor = cursor.addingTimeInterval(0.2 + gap)
        }
        strokes.append(makeStroke(startingAt: cursor, lasting: 0.2))

        let rhythm = reader.read(PKDrawing(strokes: strokes)).rhythm

        let median = rhythm.medianPause
        XCTAssertNotNil(median)
        XCTAssertEqual(median ?? 0, 0.3, accuracy: 0.05, "中位数不该被一次 60 秒的发呆拉走")
        XCTAssertEqual(rhythm.longestPause ?? 0, 60, accuracy: 0.05, "但最长停顿要如实报告")
    }

    /// 笔画在数组里的顺序即使不是时间顺序，节奏也要算对。
    func testRhythmDoesNotDependOnStrokeArrayOrder() {
        let base = Date()
        let early = makeStroke(startingAt: base, lasting: 0.3)
        let late = makeStroke(startingAt: base.addingTimeInterval(2), lasting: 0.3)

        let forward = reader.read(PKDrawing(strokes: [early, late])).rhythm
        let reversed = reader.read(PKDrawing(strokes: [late, early])).rhythm

        XCTAssertEqual(forward.pauses.count, reversed.pauses.count)
        XCTAssertEqual(forward.pauses.first ?? -1, reversed.pauses.first ?? -2, accuracy: 0.02)
        XCTAssertEqual(forward.totalDuration, reversed.totalDuration, accuracy: 0.02)
    }
}
