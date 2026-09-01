//
//  DiaryBook.swift
//  模块：Features/Canvas
//
//  文件职责：这本日记有好几页，管住「哪一页是当前的、翻页时什么留在哪里」（计划 E3f）。
//
//  ── 为什么现在必须做（2026-09-01 实测逼出来的）──
//  用户和魂真的聊起来之后，第四轮就撞上了：
//      `说不出话：这一页放不下了，需要翻页（E3f 未实现）`
//  一页纸写满是**必然会发生**的事，不是边缘情况。撞上之后魂完全说不出话，
//  而用户看到的只是一句「这一次没能把你写的话送出去」。
//
//  ── 翻页的判据不是「写了多少字」──
//  是**落点决策找不到空位**（`ReplyPlacementFailure.noRoomOnThisPage`）。
//  这条判据比「occupancy 超过百分之几」准确得多：真正要紧的不是纸上有多少墨，
//  而是「这段话还放得下吗」——一段 30 字的回应和一段 3 字的回应对空间的要求差很多。
//  决策 33 当初就是这么定的，现在这条判据由 E9e 真的提供了。
//
//  ── 一页上有什么 ──
//  用户的手写（一份 `PKDrawing`）+ 魂在这一页上写下的每一段回应。
//  两者分开存而不是合成一份，因为它们的生命周期不同：
//  用户的笔画由 PencilKit 管（可撤销、可擦），魂的回应是我们自己逐笔画出来的。
//  合并成一份要等 E3g（让橡皮也能擦魂的字）。
//
//  ── 翻页之后旧页去哪 ──
//  留在 `pages` 里，不丢。翻回去应该能看见——虽然「翻回去」这个手势还没做
//  （现在只会往前翻），但数据必须先留住，否则将来加手势时那些内容已经没了。
//

import Foundation
import PencilKit

/// 一页日记。
nonisolated struct DiaryPage: Equatable, Sendable {
    /// 用户在这一页上的手写。
    var drawing = PKDrawing()

    /// 魂在这一页上写下、并且已经定格的回应。
    var settledReplies: [ReplyOnPage] = []

    /// 这一页上有没有任何东西。
    var isBlank: Bool {
        drawing.strokes.isEmpty && settledReplies.isEmpty
    }
}

/// 整本日记：好几页，其中一页是当前页。
///
/// 刻意做成值类型：翻页是「换一个当前页索引」这么简单的事，
/// 用引用类型会让「谁改了哪一页」变得难追。
nonisolated struct DiaryBook: Equatable, Sendable {
    private(set) var pages: [DiaryPage]

    /// 当前是第几页（从 0 开始）。
    private(set) var currentIndex: Int

    init() {
        pages = [DiaryPage()]
        currentIndex = 0
    }

    var current: DiaryPage {
        get { pages[currentIndex] }
        set { pages[currentIndex] = newValue }
    }

    /// 一共几页。
    var count: Int { pages.count }

    /// 当前页是不是最后一页。
    var isOnLastPage: Bool { currentIndex == pages.count - 1 }

    /// 往后翻一页。
    ///
    /// 已经在最后一页时新建一页；否则只是把索引往后挪
    /// （那种情况现在到不了，因为没有往回翻的手势——留着是为了让这个方法的语义完整，
    /// 而不是为了将来可能有的功能）。
    ///
    /// - Returns: 翻到了第几页。
    @discardableResult
    mutating func turnToNextPage() -> Int {
        if isOnLastPage {
            pages.append(DiaryPage())
        }
        currentIndex += 1
        return currentIndex
    }

    /// 往前翻一页。已经在第一页时什么都不做。
    @discardableResult
    mutating func turnToPreviousPage() -> Int {
        currentIndex = max(0, currentIndex - 1)
        return currentIndex
    }
}
