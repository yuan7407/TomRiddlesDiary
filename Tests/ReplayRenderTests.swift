//
//  ReplayRenderTests.swift
//  模块：Tests（渲染层真的把墨画出来了吗）
//
//  文件职责：把 `HandwritingReplayView` 真的渲染成一张图，检查图上**有墨**。
//
//  ── 为什么非要有这一条 ──
//  2026-09-01 白查了一轮：E6a 接通之后模拟器上写完字，魂那段回应完全看不见。
//  没有报错、没有提示、纸上一片空白。而「魂没说话」和「魂说了但没画出来」
//  在纸上长得**一模一样**，两者的修法却完全不同。
//
//  当时缺的正是这条断言。整条链路每一段都有测试，唯独最后一段
//  「笔画序列 → 屏幕上的像素」没有——因为那需要真的渲染，而渲染看起来不好测。
//  其实是能测的：`ImageRenderer` 会同步跑一遍视图并给出位图。
//
//  ── 这条测试**测得到**和**测不到**什么，必须说清 ──
//  测得到：给一个中途的进度，画笔的几何、线宽、颜色这些代码真的会在图上留下墨。
//  测不到：**动画会不会动。** `ImageRenderer` 强制渲染一次，绕过了「谁来触发重绘」
//  这个问题——而那恰恰是当时的真正故障点（模拟器空闲时冻结渲染循环，
//  `TimelineView` 只出一两帧就停，而 t≈0 那一帧本来就什么都没有）。
//  所以这条测试绿了**不代表**逐笔生长在设备上看得见；那件事只能人眼看。
//  把这个边界写在这里，是为了以后没人拿这条绿灯当「动画正常」的证据。
//

import SwiftUI
@testable import TomRiddlesDiary
import XCTest

nonisolated final class ReplayRenderTests: XCTestCase {
    /// 造一段真实的回应笔画：走和 App 完全相同的装配路径。
    /// 手搓假笔画会让这条测试变成「测我造的数据」，那证明不了渲染。
    private func makeReply(_ text: String = "就一下，也算。") throws -> StrokeSequence {
        let glyphSize = HandwritingFeel.referenceGlyphHeightInPoints
        let page = PageRegion(left: 0, top: 0, width: 700, height: 500)
        var map = PageInkMap(
            page: page,
            resolution: PageInkMap.Resolution(
                glyphHeight: glyphSize,
                lineSpacingRatio: PageAppearance.lineSpacingRatio
            )
        )
        map.mark([])

        return try ReplyComposer().compose(
            text,
            glyphSize: glyphSize,
            lineSpacingRatio: PageAppearance.lineSpacingRatio,
            after: nil,
            on: map,
            seed: 7
        ).sequence
    }

    /// 渲染成位图，数有多少个「明显是墨」的像素。
    @MainActor
    private func inkPixels(of sequence: StrokeSequence, playback: ReplayPlayback) throws -> Int {
        let renderer = ImageRenderer(
            content: HandwritingReplayView(sequence: sequence, playback: playback)
                .frame(width: 700, height: 500)
                .background(.white)
        )
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.uiImage, "ImageRenderer 没给出图")
        let cg = try XCTUnwrap(image.cgImage)

        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 阈值 200：墨是接近黑的，纸是接近白的，中间留足余量，
        // 不会因为抗锯齿的灰边把结论翻过来。
        return pixels.count { $0 < 200 }
    }

    /// **核心断言**：写到一半时，图上必须有墨。
    @MainActor
    func testMidwayProgressActuallyPutsInkOnTheImage() throws {
        let sequence = try makeReply()
        let half = sequence.totalDuration / 2

        let ink = try inkPixels(of: sequence, playback: .frozen(atElapsed: half))

        XCTAssertGreaterThan(ink, 100, "写到一半，图上却几乎没有墨——渲染层没把笔画画出来")
    }

    /// 起点该几乎没有墨，终点该明显更多。
    /// 这条守着「进度真的在影响画面」——如果两头一样多，说明进度被忽略了。
    @MainActor
    func testInkGrowsWithProgress() throws {
        let sequence = try makeReply()

        let atStart = try inkPixels(of: sequence, playback: .frozen(atElapsed: 0))
        let atHalf = try inkPixels(of: sequence, playback: .frozen(atElapsed: sequence.totalDuration / 2))
        let atEnd = try inkPixels(of: sequence, playback: .finished)

        XCTAssertLessThan(atStart, atHalf, "从起点到一半，墨没有变多")
        XCTAssertLessThan(atHalf, atEnd, "从一半到写完，墨没有变多")
    }

    /// 起播那一刻画面**几乎是空的**——这就是当初「一片空白」的真相。
    ///
    /// 留这条断言是为了把那次故障的机理固定下来：`t≈0` 本来就没有墨，
    /// 所以「只出一帧就停」的表现必然是永远空白。
    /// 谁要是以后又把重绘交给一个只出一帧的调度器，看到的还是这个。
    @MainActor
    func testThereIsAlmostNoInkAtTheVeryFirstMoment() throws {
        let sequence = try makeReply()

        let atStart = try inkPixels(of: sequence, playback: .frozen(atElapsed: 0))
        let atEnd = try inkPixels(of: sequence, playback: .finished)

        XCTAssertLessThan(
            Double(atStart), Double(atEnd) * 0.05,
            "起播那一刻就有不少墨？那说明生长的起点不对"
        )
    }

    /// 中英混排 + 标点也要画得出来（三套字形数据都走一遍）。
    @MainActor
    func testMixedContentRenders() throws {
        let sequence = try makeReply("我看见你写的 hello，慢一点。")
        let ink = try inkPixels(of: sequence, playback: .finished)
        XCTAssertGreaterThan(ink, 500, "中英混排画不出来")
    }
}
