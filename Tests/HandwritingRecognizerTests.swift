//
//  HandwritingRecognizerTests.swift
//  模块：Tests（手写识别的能力报告）
//
//  文件职责：验证识别器如实报告本机的语言可用性，而不是把「缺模型」混成「认不出」。
//
//  设计原因：
//  这一层的主要价值不是识别本身（那是系统做的），而是**把「请求的语言」与「本机
//  实际能用的语言」之间的差异变成显式数据**。这个差异如果被吞掉，用户会以为是
//  自己写得潦草而反复重写，而真实原因是这台设备根本没装那个语言的模型。
//  所以这里断言的是「报告是否诚实」，不是「识别准不准」。
//
//  识别准确率**不在这里测也测不了**：模拟器上用程序造的笔画不是手写，
//  鼠标画的也不是；准确率必须真机 + Apple Pencil 用真实手写样张评（计划 E4）。
//

import Foundation
import PencilKit
@testable import TomRiddlesDiary
import XCTest

nonisolated final class HandwritingRecognizerTests: XCTestCase {
    private func makeDrawing(strokeCount: Int = 1) -> PKDrawing {
        var strokes: [PKStroke] = []
        for index in 0 ..< strokeCount {
            var points: [PKStrokePoint] = []
            for step in 0 ... 12 {
                let t = CGFloat(step) / 12
                points.append(PKStrokePoint(
                    location: CGPoint(x: 40 + t * 60, y: 80 + CGFloat(index) * 50),
                    timeOffset: Double(t) * 0.3,
                    size: CGSize(width: 3, height: 3),
                    opacity: 1,
                    force: 0,
                    azimuth: 0,
                    altitude: .pi / 2
                ))
            }
            strokes.append(PKStroke(
                ink: PKInk(.pen, color: .black),
                path: PKStrokePath(controlPoints: points, creationDate: Date())
            ))
        }
        return PKDrawing(strokes: strokes)
    }

    func testEnglishIsAvailableInThisEnvironment() async {
        let recognizer = HandwritingRecognizer(languages: [Locale.Language(identifier: "en")])
        let availability = await recognizer.availability()

        XCTAssertTrue(availability.isUsable, "英文模型应在模拟器与真机上都可用")
        XCTAssertTrue(availability.isComplete, "只请求英文时不该有缺失语言")
        XCTAssertTrue(availability.active.contains { $0.languageCode == Locale.LanguageCode("en") })
    }

    /// 请求一个必然不存在的语言，验证它被报成「缺失」而不是被悄悄忽略。
    func testUnavailableLanguageIsReportedAsMissing() async {
        let nonsense = Locale.Language(identifier: "zxx-Zzzz")
        let recognizer = HandwritingRecognizer(languages: [nonsense])
        let availability = await recognizer.availability()

        XCTAssertFalse(availability.isComplete, "本机没有的语言必须出现在缺失列表里")
        XCTAssertEqual(availability.unavailable.count, 1)
        XCTAssertFalse(availability.isUsable, "一种可用语言都没有时不该报成可用")
    }

    /// 混合请求时，可用的要启用、不可用的要照实列出——不能因为有一个能用就当全都能用。
    func testMixedRequestSeparatesAvailableFromMissing() async {
        let recognizer = HandwritingRecognizer(languages: [
            Locale.Language(identifier: "en"),
            Locale.Language(identifier: "zxx-Zzzz"),
        ])
        let availability = await recognizer.availability()

        XCTAssertTrue(availability.isUsable, "英文可用，整体就该是可用的")
        XCTAssertFalse(availability.isComplete, "但缺失的那个必须照实报出来")
        XCTAssertEqual(availability.requested.count, 2)
    }

    /// 一种可用语言都没有时，不去调识别——那只会得到一个 nil，
    /// 反而掩盖了「本机缺模型」这个真实原因。
    func testRecognitionWithNoUsableLanguageReturnsNoTextButKeepsTheReason() async {
        let recognizer = HandwritingRecognizer(languages: [Locale.Language(identifier: "zxx-Zzzz")])
        let result = await recognizer.recognize(makeDrawing())

        XCTAssertNil(result.text)
        XCTAssertFalse(result.hasText)
        XCTAssertFalse(result.availability.isUsable, "结果里必须带着「为什么没认出」")
        XCTAssertFalse(result.availability.unavailable.isEmpty)
    }

    /// 空白页也要能安全走完，且照样报告语言状况。
    func testEmptyDrawingRecognizesSafely() async {
        let recognizer = HandwritingRecognizer(languages: [Locale.Language(identifier: "en")])
        let result = await recognizer.recognize(PKDrawing())

        XCTAssertFalse(result.hasText, "空白页不该认出内容")
        XCTAssertTrue(result.availability.isUsable, "空白页不影响语言可用性")
    }

    /// 程序造的笔画走完识别不崩、不挂起。这里**不断言认出什么**：
    /// 造出来的是几条线段，不是字，认不出是正确行为。
    func testRecognitionCompletesOnSyntheticStrokes() async {
        let recognizer = HandwritingRecognizer(languages: [Locale.Language(identifier: "en")])
        let result = await recognizer.recognize(makeDrawing(strokeCount: 3))

        XCTAssertTrue(result.availability.isUsable)
        // text 可能是 nil 也可能是被误认的字符，两者都不算失败。
        XCTAssertNoThrow(result.hasText)
    }

    /// 配置里请求的语言必须原样传下去，不能在中途被改写。
    func testConfiguredLanguagesArePassedThrough() async {
        let recognizer = HandwritingRecognizer()
        let availability = await recognizer.availability()

        XCTAssertEqual(availability.requested, InteractionSettings.recognitionLanguages)
    }
}
