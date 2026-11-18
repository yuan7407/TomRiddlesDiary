//
//  ReplyCadenceTests.swift
//  测试目标：StrokeEngine 的 ReplyCadence（说话的节奏），以及 ReplyComposer 里把原文筛成「真的排出来的字」的那一步。
//
//  为什么这样测：节奏的铁律是「只动时间，不动笔迹」。所以最重要的断言是
//  套完节奏以后每一个采样点都和原来相同；其次才是停顿加在了对的笔画上。
//  停顿加错位置不会报错，只会让他在一个字的中间愣住。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class ReplyCadenceTests: XCTestCase {
    private let cadence = ReplyCadence(configuration: ReplyCadenceConfiguration(
        pauseAfter: ["，": 0.1, "。": 0.3, "？": 0.4],
        sentenceEnds: ["。", "？"],
        hesitation: 0.5 ... 0.5,
        closingSlowdown: 2
    ))

    /// 造一段假的回应：每个字给定笔数，每一笔时长 1 秒、笔前停 0.05 秒。
    private func sequence(strokeCounts: [Int]) -> StrokeSequence {
        var strokes: [TimedStroke] = []
        for (glyph, count) in strokeCounts.enumerated() {
            for index in 0 ..< count {
                let x = Double(glyph * 10 + index)
                strokes.append(TimedStroke(
                    samples: [
                        StrokeSample(point: Point2D(x: x, y: 0), pressure: 0.4),
                        StrokeSample(point: Point2D(x: x, y: 5), pressure: 0.6),
                    ],
                    duration: 1,
                    pauseBefore: 0.05
                ))
            }
        }
        return StrokeSequence(strokes: strokes)
    }

    func testOnlyTimingChangesNeverTheInk() {
        let glyphs = Array("你好。在吗？")
        let counts = [2, 3, 1, 2, 2, 1]
        let original = sequence(strokeCounts: counts)
        let paced = cadence.apply(to: original, glyphs: glyphs, strokeCountsPerGlyph: counts, seed: 7)
        XCTAssertEqual(paced.strokes.count, original.strokes.count)
        XCTAssertEqual(paced.strokes.map(\.samples), original.strokes.map(\.samples), "节奏不许动任何采样点")
        XCTAssertGreaterThan(paced.totalDuration, original.totalDuration)
    }

    func testPauseLandsOnTheFirstStrokeAfterThePunctuation() {
        let glyphs = Array("好，在")
        let counts = [2, 1, 3]
        let paced = cadence.apply(to: sequence(strokeCounts: counts), glyphs: glyphs, strokeCountsPerGlyph: counts, seed: 1)
        let pauses = paced.strokes.map(\.pauseBefore)
        XCTAssertEqual(pauses[0], 0.05, accuracy: 1e-12)
        XCTAssertEqual(pauses[2], 0.05, accuracy: 1e-12, "逗号自己那一笔前面不多停")
        XCTAssertEqual(pauses[3], 0.15, accuracy: 1e-12, "逗号后面第一个字的第一笔多停 0.1 秒")
        XCTAssertEqual(pauses[4], 0.05, accuracy: 1e-12, "同一个字后面的笔画不多停")
    }

    func testHesitatesOnceAfterTheFirstSentenceAndSlowsTheLastOne() {
        let glyphs = Array("来。坐。说？")
        let counts = [1, 1, 1, 1, 1, 1]
        let paced = cadence.apply(to: sequence(strokeCounts: counts), glyphs: glyphs, strokeCountsPerGlyph: counts, seed: 3)
        XCTAssertEqual(paced.strokes[2].pauseBefore, 0.05 + 0.3 + 0.5, accuracy: 1e-12, "第一处句末后面：句号的停顿加一次犹豫")
        XCTAssertEqual(paced.strokes[4].pauseBefore, 0.05 + 0.3, accuracy: 1e-12, "第二处句末后面只有句号的停顿")
        XCTAssertEqual(paced.strokes.map(\.duration), [1, 1, 1, 1, 2, 2], "只有最后那句话写得慢")
    }

    func testASingleSentenceIsNeitherHesitatedNorSlowed() {
        let glyphs = Array("我在。")
        let counts = [2, 2, 1]
        let original = sequence(strokeCounts: counts)
        let paced = cadence.apply(to: original, glyphs: glyphs, strokeCountsPerGlyph: counts, seed: 3)
        XCTAssertEqual(paced, original, "只有一句、句号又在末尾：没有地方可停，也没有「最后那句」")
    }

    func testPauseOwedAcrossASpaceIsPaidByTheNextRealGlyph() {
        let glyphs = Array("ok, go")
        let counts = [1, 1, 1, 0, 1, 1]
        let english = ReplyCadence(configuration: ReplyCadenceConfiguration(
            pauseAfter: [",": 0.2], sentenceEnds: [], hesitation: 0 ... 0, closingSlowdown: 1
        ))
        let paced = english.apply(to: sequence(strokeCounts: counts), glyphs: glyphs, strokeCountsPerGlyph: counts, seed: 1)
        XCTAssertEqual(paced.strokes[3].pauseBefore, 0.25, accuracy: 1e-12, "空格没有笔画，逗号的停顿要落到 g 上")
    }

    func testSameSeedSameRhythm() {
        let wide = ReplyCadence(configuration: ReplyCadenceConfiguration(
            pauseAfter: ["。": 0.3], sentenceEnds: ["。"], hesitation: 0.2 ... 0.9, closingSlowdown: 1.2
        ))
        let glyphs = Array("好。走吧")
        let counts = [1, 1, 1, 1]
        let first = wide.apply(to: sequence(strokeCounts: counts), glyphs: glyphs, strokeCountsPerGlyph: counts, seed: 42)
        let again = wide.apply(to: sequence(strokeCounts: counts), glyphs: glyphs, strokeCountsPerGlyph: counts, seed: 42)
        XCTAssertEqual(first, again)
        let hesitation = first.strokes[2].pauseBefore - 0.05 - 0.3
        XCTAssertTrue((0.2 ... 0.9).contains(hesitation), "犹豫的时长要落在配置的范围里，实际是 \(hesitation)")
    }

    func testShippedCadenceKeepsEveryPauseShort() {
        let configuration = BookFeel.replyCadence.configuration
        XCTAssertTrue(configuration.pauseAfter.values.allSatisfy { $0 > 0 && $0 <= 0.6 }, "句读后的停顿超过 0.6 秒会像卡住")
        XCTAssertLessThanOrEqual(configuration.hesitation.upperBound, 1)
        XCTAssertTrue(configuration.sentenceEnds.isSubset(of: Set(configuration.pauseAfter.keys)), "算句末的标点都应该有停顿")
    }

    // MARK: 排版报的「排了哪些字」

    /// 字和笔数必须由排版一起给出：换行、缺字、折行处被吞掉的空格都只有排版知道。
    /// 2026-11-18 真机：外屏回一句英文，在空格处折行，空格不进任何一行；当时从原文推字，
    /// 多数了一个空格，`ReplyCadence` 断言把 App 停住，看上去就是卡死。
    func testPlacedCharactersMatchStrokeCountsEvenWhenAWrapSwallowsASpace() throws {
        for text in ["Hello... anyone there?", "你好\n吗", "你𠮷好𠮷", "Hello. Who is writing in me tonight?"] {
            for width in [120.0, 160, 200, 240] {
                let laidOut = try GlyphStrokeLayout().layOut(text, configuration: GlyphStrokeLayoutConfiguration(
                    glyphSize: 40, lineWidth: width, lineSpacingRatio: 1.5, origin: .zero, hand: ReplyComposer.hand(seed: 3)
                ))
                XCTAssertEqual(laidOut.placedCharacters.count, laidOut.strokeCountsPerGlyph.count, "「\(text)」宽 \(width)")
                XCTAssertFalse(laidOut.placedCharacters.contains("\n"))
                XCTAssertFalse(laidOut.placedCharacters.contains("𠮷"), "缺笔顺的字不算排出来")
            }
        }
    }
}
