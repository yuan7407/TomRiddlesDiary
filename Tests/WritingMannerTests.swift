//
//  WritingMannerTests.swift
//  测试目标：Oracle 的 WritingManner（他下笔的样子），以及它怎样随请求发给模型。
//
//  为什么这样测：
//  - 形状判别（点一下 / 一条线 / 一个圈 / 乱划 / 写字）每一类给一个最典型的例子。
//    判错的后果是魂对着一道线说「你写了很多」，所以每一类都要钉住。
//  - 写了字就什么都不发（2026-11-18 收窄：他拿到快慢就去评论你的字）；没写字才发，而且只发形状，不许出现坐标。
//  - 没有 `manner` 时，请求体必须和原来一字不差（现有调用处和测试都没传它）。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class WritingMannerTests: XCTestCase {
    private let thresholds = WritingMannerThresholds(
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
    }

    func testTheSentenceCarriesOnlyTheShape() throws {
        let manner = try XCTUnwrap(observe([trace([(123.456, 654.321), (124, 655)], startingAt: 0, seconds: 0.3)]))
        XCTAssertEqual(manner.shape, .tap)
        XCTAssertEqual(manner.sentenceForSoul, "（他下笔的样子：没有写字，只是在纸上点了一下。）")
    }

    // MARK: 随请求发出去

    func testRequestWithoutMannerSendsExactlyTheWords() {
        XCTAssertEqual(OracleRequest(text: "x", strokeCount: 1).userContent(text: "今天有点累。"), "今天有点累。")
    }

    /// 没写字时那一行跟在后面。
    func testRequestWithAGestureAppendsItOnItsOwnLine() {
        let line = WritingManner(shape: .line)
        XCTAssertEqual(OracleRequest(text: "x", strokeCount: 1, manner: line).userContent(text: "一"), "一\n" + line.sentenceForSoul)
    }

    /// 2026-11-18 真机：他拿到「写得很慢」「写得重」就去评论你的字。写了字就什么都不发。
    func testWritingIsNeverDescribedToHim() {
        let writing = WritingManner(shape: .writing)
        XCTAssertFalse(writing.isWorthMentioning)
        XCTAssertEqual(OracleRequest(text: "x", strokeCount: 40, manner: writing).userContent(text: "你好"), "你好")
    }

    /// 记得的东西在最前面：称呼、记得的事、最近几轮（旧的在前）、这一次的开场白，然后才是这一句。
    func testRememberedThingsComeFirst() {
        let turns = [OracleTurn(you: "hello", him: "Hello. Who is this?")]
        let content = OracleRequest(text: "x", strokeCount: 1, history: turns, opening: "你回来了，Harry。\n想写点什么？",
                                    name: "Harry", summary: "他说过他叫 Harry。").userContent(text: "Again.")
        XCTAssertTrue(content.hasPrefix("他让你叫他：Harry\n你记得的事（更早的对话，你自己记下的）：他说过他叫 Harry。\n\n之前的几轮（旧的在前）：\n他写：hello\n你回：Hello. Who is this?"))
        XCTAssertTrue(content.contains("这一次翻开本子时，你已经先在纸上写了：「你回来了，Harry。想写点什么？」"))
        let nothingRemembered = OracleRequest(text: "x", strokeCount: 1).userContent(text: "你好")
        XCTAssertEqual(nothingRemembered, "你好")
    }

    func testSystemPromptExplainsWhatTheBracketedLineIs() {
        XCTAssertTrue(SoulSystemPrompt.renderingConstraints.contains("他下笔的样子"), "模型要知道括号里那一行不是他写的字")
    }
}
