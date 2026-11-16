//
//  BrushShapingTests.swift
//  所属：测试（StrokeEngine 的笔法）
//
//  这些测试守什么：
//  笔法只许改粗细（压感与接触），不许动形状和时间——动了形状就是写错字，动了时间就会和节奏打架。
//  另外守住几条「看得出来的」性质：撇要出尖、横的收笔比中段重、拉丁字母原样不动。
//  「好不好看」机器判断不了，那一条在 MERGE.md 里列成了要用眼睛验的事。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class BrushShapingTests: XCTestCase {
    private let configuration = BrushShapingConfiguration(strength: 1, dotLength: 6, lightestWidthRatio: 0.6)

    /// 一条从 `from` 到 `to` 的直线笔画，压感和接触处处相同，方便看笔法单独加了什么。
    private func stroke(from: Point2D, to: Point2D, count: Int = 21) -> TimedStroke {
        TimedStroke(
            samples: (0 ..< count).map { index in
                let t = Double(index) / Double(count - 1)
                return StrokeSample(
                    point: Point2D(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t),
                    pressure: 0.7,
                    contact: 1
                )
            },
            duration: 0.4,
            pauseBefore: 0.1
        )
    }

    private func width(_ sample: StrokeSample) -> Double {
        (0.6 + sample.pressure * 0.4) * sample.contact
    }

    func testKindFollowsTheDirectionTheStrokeEndsIn() {
        func kind(_ dx: Double, _ dy: Double) -> BrushStrokeKind {
            BrushShaping.kind(of: stroke(from: Point2D(x: 0, y: 0), to: Point2D(x: dx, y: dy)).samples.map(\.point), dotLength: 6)
        }
        XCTAssertEqual(kind(40, 0), .horizontal)
        XCTAssertEqual(kind(0, 40), .vertical)
        XCTAssertEqual(kind(-30, 30), .leftFalling, "页面坐标 y 朝下：往左下是撇")
        XCTAssertEqual(kind(30, 30), .rightFalling)
        XCTAssertEqual(kind(20, -30), .rising)
        XCTAssertEqual(kind(3, 2), .dot, "比门槛短的算点")
    }

    func testShapingChangesOnlyPressureAndContact() {
        let original = StrokeSequence(strokes: [
            stroke(from: Point2D(x: 0, y: 0), to: Point2D(x: 40, y: 0)),
            stroke(from: Point2D(x: 40, y: 0), to: Point2D(x: 10, y: 30)),
        ])
        let shaped = BrushShaping.shaped(original, configuration: configuration)
        XCTAssertEqual(shaped.polylines, original.polylines, "形状不许动")
        XCTAssertEqual(shaped.totalDuration, original.totalDuration, "时间不许动")
        XCTAssertNotEqual(shaped, original, "但粗细应该变了")
        for sample in shaped.strokes.flatMap(\.samples) {
            XCTAssertTrue((0 ... 1).contains(sample.pressure))
            XCTAssertTrue((0 ... 1).contains(sample.contact))
        }
    }

    func testLeftFallingStrokeTapersToAPoint() throws {
        let shaped = BrushShaping.shaped(
            StrokeSequence(strokes: [stroke(from: Point2D(x: 40, y: 0), to: Point2D(x: 10, y: 30))]),
            configuration: configuration
        )
        let samples = try XCTUnwrap(shaped.strokes.first?.samples)
        XCTAssertLessThan(width(samples[samples.count - 1]), width(samples[samples.count / 2]) * 0.6, "撇的末端应明显比中段细")
        XCTAssertGreaterThan(width(samples[0]), width(samples[samples.count / 2]), "起笔顿一下，比中段重")
    }

    func testHorizontalStrokePressesAtTheEnd() throws {
        let shaped = BrushShaping.shaped(
            StrokeSequence(strokes: [stroke(from: Point2D(x: 0, y: 0), to: Point2D(x: 40, y: 0))]),
            configuration: configuration
        )
        let samples = try XCTUnwrap(shaped.strokes.first?.samples)
        XCTAssertGreaterThan(width(samples[samples.count - 1]), width(samples[samples.count / 2]), "横的收笔比行笔重")
    }

    func testZeroStrengthAndPlainStrokesAreLeftAlone() {
        let original = StrokeSequence(strokes: [
            stroke(from: Point2D(x: 0, y: 0), to: Point2D(x: 40, y: 0)),
            stroke(from: Point2D(x: 0, y: 0), to: Point2D(x: 0, y: 40)),
        ])
        let off = BrushShapingConfiguration(strength: 0, dotLength: 6, lightestWidthRatio: 0.6)
        XCTAssertEqual(BrushShaping.shaped(original, configuration: off), original)

        let onlySecond = BrushShaping.shaped(original, configuration: configuration, plainStrokes: [0])
        XCTAssertEqual(onlySecond.strokes[0], original.strokes[0], "标成「不是楷书」的笔原样不动")
        XCTAssertNotEqual(onlySecond.strokes[1], original.strokes[1])
    }

    func testPlainStrokeIndicesCoverLatinAndPunctuationButNotHan() {
        // 「我」7 笔、空格 0 笔、「ok」各 1 笔、「。」1 笔
        let plain = ReplyComposer.plainStrokeIndices(glyphs: ["我", " ", "o", "k", "。"], strokeCountsPerGlyph: [7, 0, 1, 1, 1])
        XCTAssertEqual(plain, [7, 8, 9])
        XCTAssertEqual(ReplyComposer.plainStrokeIndices(glyphs: ["我"], strokeCountsPerGlyph: [7, 1]), [], "对不上时宁可不标")
    }

    func testSoulComposerShapesHanButKeepsGeometryAndPlacement() throws {
        let page = PageRegion(left: 0, top: 0, width: 600, height: 800)
        let map = PageInkMap(page: page, resolution: PageInkMap.Resolution(glyphHeight: 40, lineSpacingRatio: 1.6))
        let plain = try ReplyComposer().compose("我在，ok。你呢？", glyphSize: 40, lineSpacingRatio: 1.6, after: nil, on: map, seed: 3)
        let soul = try ReplyComposer.forSoul().compose("我在，ok。你呢？", glyphSize: 40, lineSpacingRatio: 1.6, after: nil, on: map, seed: 3)
        XCTAssertEqual(soul.placement, plain.placement, "笔法和节奏都不许影响落点")
        XCTAssertEqual(soul.sequence.polylines, plain.sequence.polylines, "也不许动形状")
        XCTAssertGreaterThan(soul.sequence.totalDuration, plain.sequence.totalDuration, "句读处多了停顿")
    }
}
