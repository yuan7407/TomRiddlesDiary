//
//  ReplyCadence.swift
//  模块：StrokeEngine（纯逻辑层，只依赖 Foundation）
//
//  文件职责：给魂的一段回应加上说话的节奏——句读后面顿一下，开口说第二句之前犹豫一下，
//  最后那句话写得慢一点。
//
//  为什么需要它：
//  用户实测的反馈是回应「生硬」。原因之一：`StrokeHumanizer` 管的是手怎么动
//  （一笔之内的加减速、笔与笔之间按距离算的抬笔时间），它不知道文字的意思，
//  所以写「你来了。」后面的句号和写一个普通笔画之间的停顿是一样的。
//  一个人写字不是这样：写完一句会停，要问一个问题之前会想。
//
//  它动什么、不动什么（铁律：模型只决定说什么，本地引擎决定怎么写）：
//  - **只动时间**：某些笔画前面的停顿、最后一个分句里每一笔的时长。
//  - **不动任何采样点、压感、接触**，所以字形、粗细、抖动和原来逐点相同。
//  - 它不是 A 组的手感参数，也不参与决策 77 的整段 1.5 倍缩放：
//    调用方应该先做完整段缩放，再套节奏。停顿表达的是他在斟酌，不是手在移动，
//    魂写字快不等于魂想得快。
//
//  同一段话、同一个种子，结果完全相同。
//

import Foundation

nonisolated struct ReplyCadenceConfiguration: Equatable, Sendable {
    /// 每种句读后面多停多久（秒）。不在表里的字符后面不停。
    let pauseAfter: [Character: TimeInterval]
    /// 哪些算一句话的结束。第一处句末后面会犹豫；最后一处句末之后的部分算「最后那句话」。
    let sentenceEnds: Set<Character>
    /// 犹豫多久（秒）。每段回应只犹豫一次，时长在这个范围里按种子取。
    let hesitation: ClosedRange<TimeInterval>
    /// 最后那句话每一笔的时长乘以多少。大于 1 是变慢。
    let closingSlowdown: Double

    init(
        pauseAfter: [Character: TimeInterval],
        sentenceEnds: Set<Character>,
        hesitation: ClosedRange<TimeInterval>,
        closingSlowdown: Double
    ) {
        precondition(pauseAfter.values.allSatisfy { $0 >= 0 && $0.isFinite }, "Pauses cannot be negative")
        precondition(hesitation.lowerBound >= 0 && hesitation.upperBound.isFinite, "Hesitation cannot be negative")
        precondition(closingSlowdown > 0 && closingSlowdown.isFinite, "Closing slowdown must be positive")
        self.pauseAfter = pauseAfter
        self.sentenceEnds = sentenceEnds
        self.hesitation = hesitation
        self.closingSlowdown = closingSlowdown
    }
}

nonisolated struct ReplyCadence: Equatable, Sendable {
    let configuration: ReplyCadenceConfiguration

    /// 给一段回应套上节奏。
    ///
    /// - Parameters:
    ///   - sequence: 已经手绘化、也已经做完整段时间缩放的笔画序列。
    ///   - glyphs: 排版时**真的排出来了**的每一个字，按顺序（不含换行，不含字形数据里没有的字）。
    ///   - strokeCountsPerGlyph: 每个字有几笔，与 `glyphs` 一一对应（空格是 0 笔）。
    ///     就是 `LaidOutGlyphStrokes.strokeCountsPerGlyph`。
    ///   - seed: 决定犹豫多久。
    /// - Returns: 只改了时间的新序列。如果字数和笔数对不上（说明调用方传错了），原样返回——
    ///   节奏是锦上添花，对不上时宁可没有节奏，也不能把停顿加到错的笔画上。
    func apply(
        to sequence: StrokeSequence,
        glyphs: [Character],
        strokeCountsPerGlyph: [Int],
        seed: UInt64
    ) -> StrokeSequence {
        guard glyphs.count == strokeCountsPerGlyph.count,
              strokeCountsPerGlyph.reduce(0, +) == sequence.strokes.count,
              strokeCountsPerGlyph.allSatisfy({ $0 >= 0 })
        else {
            assertionFailure("ReplyCadence: glyphs and stroke counts do not describe this sequence")
            return sequence
        }

        // 句末如果就是整段话的最后一个字，它后面没有东西可停，也不算「后面还有一句」。
        let innerSentenceEnds = glyphs.indices.dropLast().filter { configuration.sentenceEnds.contains(glyphs[$0]) }
        let hesitationIndex = innerSentenceEnds.first
        let closingStart = innerSentenceEnds.last.map { $0 + 1 }

        var generator = SeededRandomNumberGenerator(seed: seed)
        let hesitationLength = configuration.hesitation.lowerBound
            + (configuration.hesitation.upperBound - configuration.hesitation.lowerBound) * generator.unitInterval()

        var strokes = sequence.strokes
        var strokeIndex = 0
        var owed: TimeInterval = 0
        for (glyphIndex, glyph) in glyphs.enumerated() {
            let count = strokeCountsPerGlyph[glyphIndex]
            let inClosing = closingStart.map { glyphIndex >= $0 } ?? false
            for offset in 0 ..< count {
                let stroke = strokes[strokeIndex + offset]
                let extraPause = offset == 0 ? owed : 0
                guard extraPause > 0 || inClosing else { continue }
                strokes[strokeIndex + offset] = TimedStroke(
                    samples: stroke.samples,
                    duration: inClosing ? stroke.duration * configuration.closingSlowdown : stroke.duration,
                    pauseBefore: stroke.pauseBefore + extraPause
                )
            }
            // 欠下的停顿只有落到一个真有笔画的字上才算还清；空格没有笔画，停顿顺延给下一个字。
            if count > 0 { owed = 0 }
            strokeIndex += count
            if let pause = configuration.pauseAfter[glyph] {
                owed += pause
                if glyphIndex == hesitationIndex { owed += hesitationLength }
            }
        }
        return StrokeSequence(strokes: strokes)
    }
}
