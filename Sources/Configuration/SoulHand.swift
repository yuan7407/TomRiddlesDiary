//
//  SoulHand.swift
//  模块：Configuration（集中配置，被装配层读取，不被 StrokeEngine / Handwriting 依赖）
//
//  文件职责：他的字怎么「排」——不排成方阵、字号随话的长短变、写在书脊对面（计划 P3）——
//  这一批常量的唯一定义处。
//
//  数值从哪来：全部照搬网页原型第二版（artifact `17m7Vat37j45NLc8NX7Sab`）的
//  `compose()`、`sizeFor`、`composeHis()`（决策 80）。原型是在 890 × 626 的对开上肉眼调的，
//  **没有真机复核**。长度凡是写「原型单位」的，乘 `PaperLook.pointsPerPrototypeUnit` 换成页面点；
//  写「字高」的是字高的比例，和引擎的单位契约（决策 25）一致。
//

import Foundation

nonisolated enum SoulHand {
    // MARK: 手排（原型 compose()）

    /// 每一行往右上走：行内每往右一个字高，往上 0.018 字高；每行再各自抖 ±0.007。
    static let lineSlope: Double = -0.018
    static let lineSlopeJitter: Double = 0.014
    /// 第二行起，行首往右错开 0…0.32 字高，左边不齐，像人写的。
    static let lineStartJitter: Double = 0.32
    /// 汉字大小 ±4.5%、其他字 ±2%（原型写的是总幅度 0.09 / 0.04）。
    static let hanSizeJitter: Double = 0.09
    static let otherSizeJitter: Double = 0.04
    /// 字的上下浮动，总幅度 0.05 字高。
    static let verticalJitter: Double = 0.05
    /// 右倾：x 随 y 偏移的比例。汉字 −0.07，拉丁字母 −0.15（手写英文斜得更厉害）。
    static let hanShear: Double = -0.07
    static let latinShear: Double = -0.15
    /// 字缩小时往下沉多少（比例），让小一点的字仍然坐在同一条线上而不是飘在上面。
    static let shrinkSink: Double = 0.62
    /// 汉字的字宽打九七折：方格之间挤一点，不像稿纸。
    static let hanAdvanceFactor: Double = 0.97
    /// 行距：字高的 1.5 倍（原型 lineGap）。
    static let lineSpacingRatio: Double = 1.5

    // MARK: 字号（原型 sizeFor 与五档试排）

    /// 按字数定基准字号（原型单位）：字少写大、字多写小。
    /// `(最多几个字, 字号)`，超过最后一档用 `smallestSize`。
    static let sizeSteps: [(maxCharacters: Int, size: Double)] = [(6, 56), (12, 48), (20, 42), (30, 37), (42, 33)]
    static let smallestSize: Double = 29
    /// 同一句话在这五个比例里各排一次，挑代价最低的：宁可字小一点，也不把一个词拆在两行。
    static let sizeTrials: [Double] = [1, 0.94, 0.88, 0.8, 0.7]
    /// 代价 = 行数 × 3 + 坏断行 × 4 + (1 − 比例) × 12；排出来比可用高度还高再 + 100。
    static let costPerLine: Double = 3
    static let costPerBadBreak: Double = 4
    static let costPerShrink: Double = 12
    static let costIfTooTall: Double = 100
    /// 最后一行少于这么多个字宽，算一次坏断行（只剩一两个字孤零零地挂着）。
    static let orphanWidthInGlyphs: Double = 2.2

    // MARK: 落点（原型 composeHis()）

    /// 隔着书脊写在你对面那页。各边距是原型单位，从纸边或折缝量起。
    /// 左页：离书口 50、离折缝 28；右页：离折缝 16、离书口 62（原型两页用同一个行宽 347，所以不对称）。
    static let leadingPageOuterInset: Double = 50
    static let leadingPageInnerInset: Double = 28
    static let trailingPageInnerInset: Double = 16
    static let trailingPageOuterInset: Double = 62
    /// 起笔的横向位置再随机往里挪 0…10。
    static let startJitter: Double = 10
    /// 上下：最高到离上边 64，最低到离下边 84。
    static let topInset: Double = 64
    static let bottomInset: Double = 84
    /// 和你那句齐平：他的第一行顶边 = 你那句的顶边 − 0.12 字高，再随机 ±7（原型单位）。
    static let alignRaise: Double = 0.12
    static let alignJitter: Double = 14

    // MARK: 开场（计划 P6，原型 startIntro() 与 composeHis 的 withLine）

    /// 他先开口。说什么在 Persona.json 的 `opening`（那是他的话）；这里只放「在哪、什么时候、线怎么划」。
    enum Opening {
        /// 翻开后多久落第一笔（秒）。原型 minAt = 开场 + 1.1：先让纸静一下，再开口。
        static let delay: TimeInterval = 1.1
        /// 他那两行和「你那一页」的哪个高度齐平：纸高的 0.25（原型 present.top = H × 0.25）。
        static let anchorTopOfHeight: Double = 0.25
        /// 替你划的那道线：在你那一页，从折缝外 60 原型单位起，长 250，纸高一半处，往右上抬 5。
        static let lineInsetFromFold: Double = 60
        static let lineLength: Double = 250
        static let lineHeightOfHeight: Double = 0.5
        static let lineRise: Double = 5
        /// 线上六个点的上下抖动（原型单位），首尾为 0。原型逐个写死的值，照抄。
        static let lineWobble: [Double] = [0, 1.5, -1, 1, -1.5, 0]
        /// 线下那句印刷体提示：线中点下方 44，翻开约 6 秒后淡出来（原型 smooth(5.5, 6.5)）。
        static let hintBelowLine: Double = 44
        static let hintDelay: TimeInterval = 5.5
        static let hintFade: TimeInterval = 1
        /// 系统说的话，不进人设。
        static let hintText = "在这一页上手写。停笔，他会读。"
        /// 外屏只有一页时（计划 S6）：线画在他那两句下面隔多远（原型单位），线最长占页宽的多少。
        /// 原型没有单页的版式，这两个数是在外屏上看着定的，未经真机验证。
        static let singlePageLineBelowText: Double = 70
        static let singlePageLineShare: Double = 0.7
    }
}
