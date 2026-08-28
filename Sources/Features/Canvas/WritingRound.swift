//
//  WritingRound.swift
//  模块：Features/Canvas（把一页手写切成一轮一轮）
//
//  文件职责：从整页手写里取出「这一轮新写的」那部分笔画。
//
//  为什么必须有这一层（计划 E3e，2026-08-29）：
//  一页纸上会有好几轮对话——你写一段、魂回一段、你再写一段。成页的时候如果把整页
//  都交给识别器，魂就会把你之前已经聊过的内容**再读一遍**，于是越回越离题，
//  而且每一轮的输入都比上一轮长，token 花费一路涨上去。
//
//  这不是「兜底」问题，是**纯缺陷**：之前的实现就是整页发出去，没有任何补偿逻辑。
//  修法也不需要什么聪明的设计，见下面的分界依据。
//
//  纠正一次此前的判断：我曾说过「怎么切分这一轮取决于版式决定（回应写在哪）」。
//  那是错的，两件事没关系。回应写在哪影响的是坐标，而「哪些笔画是新的」只取决于
//  时间——PencilKit 给的每一笔都带落笔时刻，上次成页之后落笔的就是这一轮的。
//
//  分界依据与它的已知局限（诚实记录）：
//  用 `PKStrokePath.creationDate`，也就是**墙上时钟**。PencilKit 没有提供单调时钟的
//  笔画时刻，所以没有别的选择。后果是：如果系统在两轮之间校正了时间并把时钟往回拨，
//  新笔画的时刻可能早于分界点，那一轮就会被当成「没有新内容」。
//  这是数据源的限制，不是可以修的 bug；同一个限制已经记在 `WritingRhythm` 上。
//  刻意**不用「笔画数量」当分界**：橡皮擦掉中间一笔再补写一笔，数量不变，
//  新内容就会被漏掉，而且完全无声。
//

import Foundation
import PencilKit

nonisolated enum WritingRound {
    /// 这一轮新写的笔画：落笔时刻晚于分界点的那些。
    /// - Parameters:
    ///   - drawing: 整页手写。
    ///   - boundary: 上一轮成页时的分界时刻。nil 表示还没成过页，整页都算这一轮。
    static func strokes(of drawing: PKDrawing, after boundary: Date?) -> [PKStroke] {
        guard let boundary else { return drawing.strokes }
        // 严格大于：分界时刻那一笔本身属于上一轮，已经交出去过了。
        // 极端情况下两笔的 creationDate 完全相同会让后者被一起算作旧的，
        // 概率极低（时间戳精度远高于人抬笔的间隔），且后果只是那一笔被漏掉一轮。
        return drawing.strokes.filter { $0.path.creationDate > boundary }
    }

    /// 这一轮新写的笔画，包成 `PKDrawing` 以便交给识别器与笔画读取器。
    ///
    /// 为什么要重新包一份而不是让下游自己过滤：识别器吃的是 `PKDrawing`，
    /// 笔画读取器也是。把「一轮」这个概念收在这里，下游就完全不需要知道轮次存在。
    static func drawing(of drawing: PKDrawing, after boundary: Date?) -> PKDrawing {
        guard boundary != nil else { return drawing }
        return PKDrawing(strokes: strokes(of: drawing, after: boundary))
    }

    /// 整页里最晚的落笔时刻，用作下一轮的分界点。
    /// nil 表示这一页还没有任何笔画。
    ///
    /// 取「最晚」而不是「最后一个元素」：`strokes` 的顺序是绘制顺序，
    /// 但不依赖这个假设更稳，代价只是一次遍历。
    static func boundary(of drawing: PKDrawing) -> Date? {
        drawing.strokes.map(\.path.creationDate).max()
    }
}
