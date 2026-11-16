//
//  WritingMannerTests.swift
//  测试目标：Oracle 的 WritingManner（他下笔的样子），以及它怎样随请求发给模型。
//
//  为什么这样测：
//  - 形状判别（点一下 / 一条线 / 一个圈 / 乱划 / 写字）每一类给一个最典型的例子。
//    判错的后果是魂对着一道线说「你写了很多」，所以每一类都要钉住。
//  - 发给模型的那句话必须只含那五个概括量：不许出现坐标，否则就是多发了数据。
//  - 没有 `manner` 时，请求体必须和原来一字不差（现有调用处和测试都没传它）。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class WritingMannerTests: XCTestCase {
    private let thresholds = WritingMannerThresholds(
        fastAboveGlyphHeightsPerSecond: 15,
        slowBelowGlyphHeightsPerSecond: 3.75,
        pauseWorthMentioning: 1.8,
        tapBelowGlyphHeights: 0.4,
        loopAboveGlyphHeights: 2.6
    )
    private let glyphHeight = 40.0
    private let epoch = Date(timeIntervalSinceReferenceDate: 1000)

    /// 用一串点造一笔。`seconds` 是这一笔写了多久，点在时间上均匀分布。
    private func trace(_ points: [(Double, Double)], startingAt offset: TimeInterval, seconds: TimeInterval) -> PenTrace {
        PenTrace(
            startedAt: epoch.addingTimeInterval(offset),
            samples: points.enumerated().map { index, point in
                PenTraceSample(
                    point: Point2D(x: point.0, y: point.1),
                    timeOffset: points.count > 1 ? seconds * Double(index) / Double(points.count - 1) : 0,
                    force: 0,
                    altitude: 0
                )
            }
        )
    }

    private func circle(radius: Double, turns: Double, steps: Int = 80) -> [(Double, Double)] {
        (0 ... steps).map { step in
            let angle = 2 * Double.pi * turns * Double(step) / Double(steps)
            return (200 + cos(angle) * radius, 200 + sin(angle) * radius)
        }
    }

    private func observe(_ traces: [PenTrace]) -> WritingManner? {
        WritingManner.observe(traces, glyphHeight: glyphHeight, thresholds: thresholds)
    }

    func testNothingWrittenMeansNothingToObserve() {
        XCTAssertNil(observe([]))
    }

    func testATapIsATap() {
        let manner = observe([trace([(10, 10), (11, 11)], startingAt: 0, seconds: 0.05)])
        XCTAssertEqual(manner?.shape, .tap)
        XCTAssertEqual(manner?.strokeCount, 1)
    }

    func testOneStraightStrokeIsALine() {
        let manner = observe([trace([(0, 0), (60, 2), (120, 1), (200, 3)], startingAt: 0, seconds: 0.4)])
        XCTAssertEqual(manner?.shape, .line)
    }

    func testOneClosedStrokeIsALoop() {
        XCTAssertEqual(observe([trace(circle(radius: 40, turns: 1), startingAt: 0, seconds: 0.8)])?.shape, .loop)
    }

    func testASmallHookIsNotALoop() {
        XCTAssertEqual(observe([trace(circle(radius: 6, turns: 1), startingAt: 0, seconds: 0.2)])?.shape, .writing, "太小的圈只是一个勾")
    }

    func testOneStrokeGoingRoundAndRoundIsAScribble() {
        var points = circle(radius: 40, turns: 3.4)
        points.append((400, 400))
        XCTAssertEqual(observe([trace(points, startingAt: 0, seconds: 1.5)])?.shape, .scribble)
    }

    func testSeveralShortStrokesAreWriting() {
        let strokes = (0 ..< 6).map { index in
            trace([(Double(index) * 30, 0), (Double(index) * 30 + 8, 30)], startingAt: Double(index) * 0.5, seconds: 0.2)
        }
        let manner = observe(strokes)
        XCTAssertEqual(manner?.shape, .writing)
        XCTAssertEqual(manner?.strokeCount, 6)
        XCTAssertEqual(manner?.seconds ?? 0, 2.7, accuracy: 1e-9)
    }

    func testPaceIsJudgedAgainstTheSoulsGlyphHeight() {
        let long: [(Double, Double)] = [(0, 0), (400, 0), (400, 30), (0, 30)]
        XCTAssertEqual(observe([trace(long, startingAt: 0, seconds: 0.5), trace(long, startingAt: 1, seconds: 0.5)])?.pace, .fast)
        XCTAssertEqual(observe([trace(long, startingAt: 0, seconds: 3), trace(long, startingAt: 4, seconds: 3)])?.pace, .steady)
        XCTAssertEqual(observe([trace(long, startingAt: 0, seconds: 9), trace(long, startingAt: 10, seconds: 9)])?.pace, .slow)
    }

    func testLongestPauseIsMeasuredBetweenLiftAndNextTouch() throws {
        let first = trace([(0, 0), (20, 20)], startingAt: 0, seconds: 0.5)
        let second = trace([(30, 0), (50, 20)], startingAt: 3.5, seconds: 0.5)
        let third = trace([(60, 0), (80, 20)], startingAt: 4.3, seconds: 0.5)
        let manner = try XCTUnwrap(observe([first, second, third]))
        XCTAssertEqual(manner.longestPause, 3.0, accuracy: 1e-9)
        XCTAssertTrue(manner.pauseIsWorthMentioning)
        XCTAssertTrue(manner.sentenceForSoul.contains("停了 3.0 秒"))
    }

    func testTheSentenceCarriesOnlyTheSummary() throws {
        let manner = try XCTUnwrap(observe([trace([(123.456, 654.321), (140, 660)], startingAt: 0, seconds: 0.3)]))
        let sentence = manner.sentenceForSoul
        XCTAssertTrue(sentence.hasPrefix("（他下笔的样子："))
        XCTAssertFalse(sentence.contains("123"), "坐标不许出现在发给模型的话里")
        XCTAssertFalse(sentence.contains("654"))
        XCTAssertFalse(sentence.contains("停了"), "不值得说的停顿就不说")
    }

    // MARK: 随请求发出去

    func testRequestWithoutMannerSendsExactlyTheWords() {
        XCTAssertEqual(OracleRequest(text: "x", strokeCount: 1).userContent(text: "今天有点累。"), "今天有点累。")
    }

    func testRequestWithMannerAppendsItOnItsOwnLine() throws {
        let manner = try XCTUnwrap(observe([trace([(0, 0), (20, 20)], startingAt: 0, seconds: 0.5), trace([(30, 0), (50, 20)], startingAt: 1, seconds: 0.5)]))
        let content = OracleRequest(text: "x", strokeCount: 2, manner: manner).userContent(text: "今天有点累。")
        XCTAssertEqual(content, "今天有点累。\n" + manner.sentenceForSoul)
    }

    func testSystemPromptExplainsWhatTheBracketedLineIs() {
        XCTAssertTrue(SoulSystemPrompt.renderingConstraints.contains("他下笔的样子"), "模型要知道括号里那一行不是他写的字")
    }
}
