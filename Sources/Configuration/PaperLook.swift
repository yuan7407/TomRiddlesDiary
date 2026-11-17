//
//  PaperLook.swift
//  模块：Configuration（集中配置，被界面层读取，不被 StrokeEngine 依赖）
//
//  文件职责：纸长什么样——纸纹、书脊阴影、折缝宽度——这一批常量的唯一定义处（计划 P1）。
//
//  数值从哪来：全部照搬网页原型第二版（artifact `17m7Vat37j45NLc8NX7Sab`）里的 `PAPER()` 与
//  `drawGutter()`。用户拍板「规则冲突以原型为准」（决策 80），所以这里不另起炉灶，只做单位换算。
//  原型都是在一张 890 × 626 的对开上肉眼调的，**没有真机复核**；真机上要看的是纸纹在 460 ppi 下
//  会不会太细太碎、书脊阴影在真实折缝的反光下够不够。
//
//  单位：原型里的长度是「原型单位」（它那张 890 宽的对开上的一个 CSS 像素）。
//  换成页面点乘 `pointsPerPrototypeUnit`。为什么是一个常数而不是按屏幕宽度算：
//  Duo 外屏（466 宽、单页）和内屏（951 宽、对开）上同一根纸纤维应该一样长，
//  按各自屏幕宽度算的话外屏上的纸纹会缩成一半。数量（纤维、斑点）按面积换算，密度不变。
//

import Foundation

/// 一个颜色加透明度，0…1。Configuration 不依赖 SwiftUI / UIKit，界面层自己转成 CGColor。
nonisolated struct PaperTint: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    /// 原型里写的是 0…255 的整数，原样抄进来更好对照。
    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red / 255
        self.green = green / 255
        self.blue = blue / 255
    }
}

nonisolated enum PaperLook {
    /// 原型那张对开的宽高（原型单位）。只用来换算，不代表任何屏幕。
    static let prototypeSpreadWidth: Double = 890
    static let prototypeSpreadHeight: Double = 626

    /// 一个原型单位等于多少页面点。951 是 Duo 摊开内屏的宽（2026-11-17 模拟器实测），
    /// 原型对开与内屏的宽高比几乎相同（1.4217 对 1.4215），所以按宽度换算即可。
    static let pointsPerPrototypeUnit: Double = 951.0 / 890.0

    /// 折缝的宽度（页面点）。2026-11-17 在 Duo 模拟器半开时，系统报告的折缝是 40 点宽；
    /// 原型也是折缝两侧各留 20。摊平时系统不报折缝，就按这个宽度在屏幕正中推断（见 `SpreadGeometry.resolve`）。
    static let foldWidthPoints: Double = 40

    /// 纸纹用的随机种子。固定种子 = 每次打开纸纹都一样，像同一本本子，而不是每次换一张纸。原型取 1943。
    static let textureSeed: UInt64 = 1943

    // MARK: 纸的底色与纹理（原型 PAPER()）

    /// 纸的底色 #f5efdf。
    static let base = PaperTint(245, 239, 223)

    /// 纤维：短短的一道，一半偏褐、一半偏白。
    enum Fiber {
        /// 原型 890 × 626 上画 2600 根，换成每平方原型单位的密度。
        static let densityPerSquareUnit: Double = 2600 / (890 * 626)
        static let lengthRange: ClosedRange<Double> = 5 ... 23     // 原型单位：5 + r × 18
        static let lineWidth: Double = 0.6                         // 原型单位
        static let darkTint = PaperTint(120, 96, 60)
        static let darkAlphaRange: ClosedRange<Double> = 0.018 ... 0.048
        static let lightAlphaRange: ClosedRange<Double> = 0.05 ... 0.13
        /// 偏褐与偏白各占一半。比例运算，不是经验值。
        static let darkShare: Double = 0.5
    }

    /// 斑点：一个原型单位见方的小点。
    enum Speck {
        static let densityPerSquareUnit: Double = 9000 / (890 * 626)
        static let tint = PaperTint(90, 70, 40)
        static let alphaRange: ClosedRange<Double> = 0 ... 0.04
    }

    /// 霉点（foxing）：靠近左右书口的几团淡褐色晕。
    enum Foxing {
        static let count = 7
        /// 离左边或右边多远以内（原型单位）。
        static let edgeBand: Double = 90
        static let radiusRange: ClosedRange<Double> = 5 ... 21
        static let tint = PaperTint(150, 110, 60)
        static let centerAlpha: Double = 0.08
    }

    /// 暗角：中间亮、四周略褐。原型写的是「纸高 × 0.35 到纸宽 × 0.62」，在它那张 890 × 626 的对开上
    /// 就是 219 到 552 原型单位。这里存成**原型单位的定值**而不是按屏幕比例算：
    /// 2026-11-17 实测，按比例算到 466 宽的外屏上，内外半径只差 50 点，暗角缩成一个硬边的圆。
    enum Vignette {
        static let innerRadius: Double = 0.35 * 626
        static let outerRadius: Double = 0.62 * 890
        static let tint = PaperTint(140, 110, 60)
        static let edgeAlpha: Double = 0.17
    }

    /// 书口那几道细线（纸页叠在一起的边）。左右各三道。
    enum EdgeLines {
        static let count = 3
        static let firstInset: Double = 3            // 原型单位；右侧是 3.8
        static let firstInsetRight: Double = 3.8
        static let spacing: Double = 2.5
        static let lineWidth: Double = 0.8
        static let tint = PaperTint(80, 60, 30)
        static let firstAlpha: Double = 0.06
        static let alphaStep: Double = 0.014
    }

    // MARK: 印刷体（原型 printed() / drawFurniture()，计划 P2）

    /// 「手写的是他，印刷的是系统」：系统说的话用凸版压印的样子——
    /// 先在略偏下的位置印一道白色亮边，再在上面压一层灰褐墨，像铅字压进纸里。
    enum Printed {
        /// 思源宋体子集（决策 81，`scripts/subset_print_font.py` 生成）的 PostScript 名。
        static let regularFontName = "NotoSerifSC-Regular"
        static let semiboldFontName = "NotoSerifSC-SemiBold"
        static let fontFiles = ["NotoSerifSC-Print-Regular", "NotoSerifSC-Print-SemiBold"]

        static let inkTint = PaperTint(74, 56, 34)
        static let defaultAlpha: Double = 0.55
        /// 亮边相对墨字的偏移（原型单位）：往右下一点点，看起来是压下去的边。
        static let highlightOffsetX: Double = 0.5
        static let highlightOffsetY: Double = 0.7
        /// 亮边透明度 = 这个系数 × min(1, 墨的透明度 ÷ 参照值)。墨越淡亮边越淡，不会出现只剩一道白的字。
        static let highlightAlphaFactor: Double = 0.6
        static let highlightAlphaReference: Double = 0.5

        /// 一行印刷体的样式：字号与字距是原型单位，透明度 0…1。
        struct Style: Equatable, Sendable {
            let size: Double
            let tracking: Double
            let alpha: Double
            let semibold: Bool
        }

        /// 页眉日期：右页右上角。
        static let date = Style(size: 11.5, tracking: 2, alpha: 0.5, semibold: false)
        /// 页码：左右两页的下角。
        static let folio = Style(size: 10.5, tracking: 1.5, alpha: 0.42, semibold: false)
        /// 纸上的系统提示（读不出哪种文字、他这次没写出来……）。
        static let notice = Style(size: 12.5, tracking: 1.5, alpha: 0.62, semibold: false)

        /// 页眉、页码离纸边多远（原型单位）。离书口 46；日期基线离上边 44；页码基线离下边 30。
        static let outerMargin: Double = 46
        static let dateBaselineFromTop: Double = 44
        static let folioBaselineFromBottom: Double = 30
        /// 纸上提示的顶边比日期基线再低多少（原型单位）。**原型里没有这条提示**（它是 App 自己的
        /// 「读不出哪种文字」，计划 E4b），所以这个数不是照搬的：取日期字号的约两倍，让中间空出一行，
        /// 2026-11-17 在 Duo 模拟器截图上目测定的。
        static let noticeGapBelowDate: Double = 22
    }

    // MARK: 书脊阴影（原型 drawGutter(depth)）

    /// depth 0…1 是「本子正在合上」的程度：0 = 摊平。阴影的半宽与浓度随它线性变化。
    enum Spine {
        static let halfSpan: Double = 42             // 原型单位，摊平时
        static let halfSpanGrowth: Double = 36        // depth = 1 时再加这么多
        static let alpha: Double = 0.17
        static let alphaGrowth: Double = 0.36
        static let innerTint = PaperTint(40, 26, 10)  // 折缝处
        static let outerTint = PaperTint(46, 30, 12)  // 阴影外缘（透明度 0）
        /// 合页角度换成 depth 时乘的系数：原型 `(180 − θ) / 180 × 0.9`。
        static let depthPerClosingFraction: Double = 0.9
    }
}
