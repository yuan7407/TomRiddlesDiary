//
//  HandwrittenTextView.swift
//  模块：Features/Response（渲染层）
//
//  文件职责：把排好版的回应用手写体字体逐字显现在纸上。
//
//  **这是计划 E8 的脚手架，不是最终效果，也不该被当成最终效果的证据。**
//  字体存的是字的外框轮廓，不含笔顺，所以它给不出「逐笔生长」。这里能做到的
//  上限是「一个字一个字地出现」。它验证的是排版、字号、行距、节奏和链路，
//  验证不了这个产品的核心观感。核心观感要等计划 E1 用字形笔顺数据接上
//  `StrokeEngine` 之后，由 `HandwritingReplayView` 逐笔画出来。
//  也就是说：本视图跑通不代表 `StrokeEngine` 被验证——这条路上引擎没被调用。
//
//  设计原因：
//  - 逐字显现的速度取自 `HandwritingFeel.glyphsPerSecond`，与将来逐笔重播共用
//    同一个书写速度来源，不另立一套节奏参数。
//  - **用「异步循环推进状态」而不是 `TimelineView` 驱动**。两个理由：
//    一、这里每秒只多出一个字，是离散慢动作，不需要跟随屏幕刷新率；
//    二、实测发现模拟器空闲时会冻结渲染循环，`TimelineView` 的
//    `.animation` 与 `.periodic` 两种调度都只出一两帧就停（画面停在「我」一个字），
//    而由状态变化触发的重绘照常生效。状态驱动因此是当前唯一能在模拟器里
//    看到并评判书写节奏的方式。
//    注意这条同时意味着：`HandwritingReplayView` 的逐笔重播用的是 `TimelineView`，
//    **它的连续动画在模拟器里无法验证，必须真机确认**。
//  - 计数用 `Task.sleep` 逐字推进而不是每帧读时钟：这里的进度是整数个字，
//    多一次少一次不影响正确性；换成读时钟反而要额外一套重绘驱动。
//  - 只画字，不画背景：底色属于「纸」，由页面提供。
//

import SwiftUI

struct HandwrittenTextView: View {
    /// 已排好版的文字。
    let text: LaidOutText

    /// 一个字的高度（页面点），也就是画字用的字号。
    let glyphHeight: Double

    /// 是否逐字书写。传 false 表示直接显示写完的状态（例如翻回旧日记页）。
    let animated: Bool

    @State private var revealedCount = 0

    var body: some View {
        Canvas { context, _ in
            for glyph in text.glyphs.prefix(revealedCount) {
                draw(glyph, in: &context)
            }
        }
        .accessibilityLabel("日记之魂写下的回应")
        .accessibilityValue(String(text.glyphs.prefix(revealedCount).map(\.character)))
        .task(id: writingIdentity) {
            await write()
        }
    }

    /// 内容或书写方式变了就重新开始书写。用字数与首字作为身份，
    /// 避免把整段文字塞进 task 的 id。
    private var writingIdentity: String {
        "\(animated)-\(text.glyphs.count)-\(text.glyphs.first?.character.description ?? "")"
    }

    private func write() async {
        guard animated else {
            revealedCount = text.glyphs.count
            return
        }

        revealedCount = 0
        let interval = Duration.seconds(1 / HandwritingFeel.glyphsPerSecond)
        for count in 1 ... max(1, text.glyphs.count) {
            do {
                try await Task.sleep(for: interval)
            } catch {
                // 被取消就停在当前进度，不跳到写完——半截字留在页上是刻意的。
                return
            }
            revealedCount = min(count, text.glyphs.count)
        }
    }

    private func draw(_ glyph: PositionedGlyph, in context: inout GraphicsContext) {
        var resolved = context.resolve(
            Text(String(glyph.character))
                .font(.custom(HandwritingFont.familyName, fixedSize: glyphHeight))
        )
        resolved.shading = .color(PageAppearance.ink)

        // `origin.y` 是基线，而 `draw(at:anchor:)` 是按包围盒定位的。
        // 用 `.bottomLeading` 会把包围盒底部（含降部）对到基线上，整个字就偏高了。
        // 改为按包围盒左上角定位：左上角 = 基线往上一个 ascent。
        // ascent 由排版层提供，渲染层不必自己去问字体度量。
        context.draw(
            resolved,
            at: CGPoint(x: glyph.origin.x, y: glyph.origin.y - text.ascent),
            anchor: .topLeading
        )
    }
}
