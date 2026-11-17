//
//  FacingColumns.swift
//  模块：Handwriting（纯逻辑，只依赖 Foundation）
//
//  文件职责：对开时，左右两页各自能写字的那一栏在哪；以及他该写在哪一页（计划 P3）。
//
//  规则来自网页原型 `composeHis()`（决策 80）：**他隔着书脊写在你对面**——你写在左页，他写在右页；
//  你写在右页，他写在左页。一问一答隔着书脊相望，像一本真正的对开日记。
//  原先（决策 57–59）是挨着你的字放在同一页，被原型推翻。
//
//  这里只回答「哪一栏」。字号怎么挑、和你那句怎么齐平，需要排版器试排，属装配层（`ReplyComposer`）。
//  栏的具体边距由装配层从 `SoulHand` 算好传进来：这一层不读 Configuration。
//

import Foundation

nonisolated struct FacingColumns: Equatable, Sendable {
    /// 左页能写字的一栏（页面点）：左右边距、上下限都已扣好。
    let leading: PageRegion
    /// 右页那一栏。
    let trailing: PageRegion
    /// 折缝中线的 x。用来判断你写在哪一页。
    let spineX: Double

    /// 你这一轮写的字在哪一页，他就写在另一页。按你那片字的中心判断（原型用笔画点的重心）。
    func column(facing writing: PageRegion) -> PageRegion {
        writing.left + writing.width / 2 < spineX ? trailing : leading
    }
}
