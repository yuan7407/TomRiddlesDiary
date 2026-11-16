//
//  InkRunTests.swift
//  测试目标：StrokeEngine 的 InkRun（长墨线上取一段）、InkTransfer（他用你的墨写字）、ReadingSweep（他在读）。
//
//  为什么这样测：三样东西都是「沿着你下笔的顺序走」，最容易错的是边界——
//  一段刚好跨过两笔之间、只点了一下的笔画、抽到 0% 和 100%。
//  这些错了不会崩，只会让纸上留下一个没被读到的墨点，或者墨凭空多出一截，所以逐条钉住。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class InkRunTests: XCTestCase {
    private func line(_ x0: Double, _ x1: Double, y: Double = 0) -> Polyline {
        Polyline(points: [Point2D(x: x0, y: y), Point2D(x: x1, y: y)])
    }

    private let sweepSettings = ReadingSweepConfiguration(
        speedInGlyphHeightsPerSecond: 10,
        shortestDuration: 0.5,
        longestDuration: 2,
        tailFractionOfInk: 0.5,
        shortestTailInGlyphHeights: 1,
        longestTailInGlyphHeights: 3,
        fadeOutDuration: 0.25
    )

    // MARK: InkRun

    func testTotalLengthAddsStrokesInWritingOrder() {
        let run = InkRun([line(0, 10), line(100, 130)], minimumStrokeLength: 1)
        XCTAssertEqual(run.totalLength, 40, accuracy: 1e-9)
    }

    func testStretchWithinOneStrokeInterpolatesBothEnds() {
        let run = InkRun([line(0, 10)], minimumStrokeLength: 1)
        let piece = run.stretch(from: 2.5, to: 7.5)
        XCTAssertEqual(piece.count, 1)
        XCTAssertEqual(piece[0].points.first?.x ?? .nan, 2.5, accuracy: 1e-9)
        XCTAssertEqual(piece[0].points.last?.x ?? .nan, 7.5, accuracy: 1e-9)
    }

    func testStretchAcrossTwoStrokesReturnsOnePiecePerStroke() {
        let run = InkRun([line(0, 10), line(100, 130)], minimumStrokeLength: 1)
        let pieces = run.stretch(from: 8, to: 15)
        XCTAssertEqual(pieces.count, 2, "跨过抬笔的那一段要拆成两截，不能把两笔连起来")
        XCTAssertEqual(pieces[0].points.last?.x ?? .nan, 10, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].points.first?.x ?? .nan, 100, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].points.last?.x ?? .nan, 105, accuracy: 1e-9)
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.length }, 7, accuracy: 1e-9)
    }

    func testATapStillOccupiesTheRunSoItCanBeReached() {
        let tap = Polyline(points: [Point2D(x: 50, y: 50)])
        let run = InkRun([line(0, 10), tap, line(100, 110)], minimumStrokeLength: 2)
        XCTAssertEqual(run.totalLength, 22, accuracy: 1e-9)
        let pieces = run.stretch(from: 10.5, to: 11)
        XCTAssertEqual(pieces, [tap], "只点了一下的笔画也要能被读到、被抽走")
    }

    func testStretchClampsAndRejectsEmptyRanges() {
        let run = InkRun([line(0, 10)], minimumStrokeLength: 1)
        XCTAssertTrue(run.stretch(from: 6, to: 6).isEmpty)
        XCTAssertTrue(run.stretch(from: 9, to: 3).isEmpty)
        XCTAssertEqual(run.stretch(from: -5, to: 99).first?.length ?? 0, 10, accuracy: 1e-9)
        XCTAssertTrue(InkRun([], minimumStrokeLength: 1).stretch(from: 0, to: 10).isEmpty)
    }

    func testPointAtFollowsTheRunAcrossStrokes() {
        let run = InkRun([line(0, 10), line(100, 130)], minimumStrokeLength: 1)
        XCTAssertEqual(run.point(at: 4)?.x ?? .nan, 4, accuracy: 1e-9)
        XCTAssertEqual(run.point(at: 25)?.x ?? .nan, 115, accuracy: 1e-9)
        XCTAssertEqual(run.point(at: 999)?.x ?? .nan, 130, accuracy: 1e-9)
        XCTAssertNil(InkRun([], minimumStrokeLength: 1).point(at: 0))
    }

    // MARK: InkTransfer

    func testDrainedAndRemainingAlwaysAddUpToAllTheInk() {
        let run = InkRun([line(0, 10), line(100, 130), line(0, 7, y: 40)], minimumStrokeLength: 1)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            let transfer = InkTransfer.split(run, drainedFraction: fraction)
            let total = (transfer.drained + transfer.remaining).reduce(0) { $0 + $1.length }
            XCTAssertEqual(total, run.totalLength, accuracy: 1e-6, "抽到 \(fraction) 时墨的总量变了")
        }
    }

    func testInkIsTakenInTheOrderItWasWritten() {
        let run = InkRun([line(0, 10), line(100, 130)], minimumStrokeLength: 1)
        let transfer = InkTransfer.split(run, drainedFraction: 0.25)
        XCTAssertEqual(transfer.drained, [line(0, 10)], "先写的那一笔先被抽走")
        XCTAssertEqual(transfer.remaining, [line(100, 130)])
        XCTAssertEqual(transfer.front?.x ?? .nan, 10, accuracy: 1e-9)
    }

    func testNothingIsTakenBeforeHeStartsAndEverythingWhenHeFinishes() {
        let run = InkRun([line(0, 10)], minimumStrokeLength: 1)
        let untouched = InkTransfer.split(run, drainedFraction: 0)
        XCTAssertTrue(untouched.drained.isEmpty)
        XCTAssertNil(untouched.front)
        let gone = InkTransfer.split(run, drainedFraction: 1)
        XCTAssertTrue(gone.remaining.isEmpty)
        XCTAssertNil(gone.front)
        XCTAssertEqual(InkTransfer.split(run, drainedFraction: .nan), untouched)
    }

    func testDrainedFractionFollowsHisProgressAndStopsWhenHeIsInterrupted() {
        XCTAssertEqual(InkTransfer.drainedFraction(replyElapsed: 3, replyDuration: 12), 0.25, accuracy: 1e-12)
        XCTAssertEqual(InkTransfer.drainedFraction(replyElapsed: 30, replyDuration: 12), 1)
        XCTAssertEqual(InkTransfer.drainedFraction(replyElapsed: -1, replyDuration: 12), 0)
        XCTAssertEqual(InkTransfer.drainedFraction(replyElapsed: 5, replyDuration: 0), 0, "空回应不用你的墨")
    }

    // MARK: ReadingSweep

    func testReadingTakesLongerForMoreInkButStaysWithinBounds() {
        let short = ReadingSweep(inkLength: 5, glyphHeight: 10, configuration: sweepSettings)
        let medium = ReadingSweep(inkLength: 100, glyphHeight: 10, configuration: sweepSettings)
        let long = ReadingSweep(inkLength: 9000, glyphHeight: 10, configuration: sweepSettings)
        XCTAssertEqual(short.duration, 0.5, accuracy: 1e-12)
        XCTAssertEqual(medium.duration, 1.0, accuracy: 1e-12)
        XCTAssertEqual(long.duration, 2.0, accuracy: 1e-12)
    }

    func testSweepStartsAtTheFirstStrokeAndEndsAtTheLast() throws {
        let sweep = ReadingSweep(inkLength: 100, glyphHeight: 10, configuration: sweepSettings)
        let start = try XCTUnwrap(sweep.window(at: 0))
        XCTAssertEqual(start.head, 0, accuracy: 1e-9)
        XCTAssertTrue(start.isAdvancing)
        let justBeforeEnd = try XCTUnwrap(sweep.window(at: sweep.duration - 1e-6))
        XCTAssertEqual(justBeforeEnd.head, 100, accuracy: 1e-3)
        XCTAssertEqual(justBeforeEnd.opacity, 1)
    }

    func testSweepHeadNeverMovesBackwardsAndTailStaysBehindIt() {
        let sweep = ReadingSweep(inkLength: 400, glyphHeight: 10, configuration: sweepSettings)
        var previousHead = -1.0
        for step in 0 ... 200 {
            guard let window = sweep.window(at: sweep.duration * Double(step) / 200) else { continue }
            XCTAssertGreaterThanOrEqual(window.head, previousHead)
            XCTAssertLessThanOrEqual(window.tail, window.head)
            XCTAssertLessThanOrEqual(window.head - window.tail, 30 + 1e-9, "湿的那一段不能超过上限（3 个字高）")
            previousHead = window.head
        }
    }

    func testSweepFadesAfterReadingThenDisappears() throws {
        let sweep = ReadingSweep(inkLength: 100, glyphHeight: 10, configuration: sweepSettings)
        let fading = try XCTUnwrap(sweep.window(at: sweep.duration + 0.125))
        XCTAssertFalse(fading.isAdvancing)
        XCTAssertEqual(fading.opacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(fading.head, 100, accuracy: 1e-9)
        XCTAssertNil(sweep.window(at: sweep.totalDuration))
        XCTAssertNil(sweep.window(at: -0.1))
        XCTAssertNil(ReadingSweep(inkLength: 0, glyphHeight: 10, configuration: sweepSettings).window(at: 0.1))
    }
}
