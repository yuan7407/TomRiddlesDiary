//
//  PrintedType.swift
//  模块：Features/Book（界面层；依赖 SwiftUI / CoreText）
//
//  文件职责：「印刷的是系统」（计划 P2）——系统说的话一律用凸版印刷体：页眉日期、页码、纸上的提示。
//  他的话永远是手写的（`HandwritingReplayView`），两者不混用：用户一眼就分得出哪句是日记写的、
//  哪句是这个 App 在说明情况。这是网页原型七条规矩里的一条（决策 80）。
//
//  字体：思源宋体子集（决策 81），两个字重，`scripts/subset_print_font.py` 生成，SIL OFL 1.1
//  （授权全文 `Resources/Fonts/OFL.txt`；原字体没有「保留字体名」条款，所以子集可以沿用原名）。
//  启动时用 CoreText 注册到本进程，不写进 Info.plist：Info.plist 只挂在 Debug 配置上（决策 70），
//  写进去 Release 就没有字了。注册失败时 SwiftUI 会悄悄回退到系统字体，所以失败在 DEBUG 里直接停住。
//
//  压印的样子：先在右下偏一点的位置印一道白色亮边，再在上面压灰褐色的墨（原型 `printed()`）。
//  定位按**基线**，和原型一致；SwiftUI 的 Text 只能按框定位，所以页眉页码用 Canvas 画、量出基线再放。
//

import CoreText
import SwiftUI

@MainActor
enum PrintedType {
    /// 启动时调一次：印刷体两个字重 + 封面名牌的字（计划 S3）。重复调用无害（CoreText 会报「已注册」，按成功处理）。
    ///
    /// 找不到字体文件、或注册失败，是打包出了错：DEBUG 里直接停住（`assertionFailure`），
    /// 不让 SwiftUI 悄悄换成系统字体、让人以为字体本来就长那样（2026-11-18 起，原来只打一行日志）。
    static func registerFonts() {
        let files = PaperLook.Printed.fontFiles.map { ($0, "otf") } + [(CoverLook.Plate.fontFile, "ttf")]
        for (name, ext) in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                assertionFailure("── 字体 ── 包里找不到 \(name).\(ext)")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    assertionFailure("── 字体 ── \(name) 注册失败（CoreText 错误 \(code)）")
                }
            }
        }
    }

    static func font(_ style: PaperLook.Printed.Style) -> Font {
        let name = style.semibold ? PaperLook.Printed.semiboldFontName : PaperLook.Printed.regularFontName
        return .custom(name, fixedSize: style.size * PaperLook.pointsPerPrototypeUnit)
    }

    static func ink(alpha: Double) -> Color {
        let tint = PaperLook.Printed.inkTint
        return Color(.sRGB, red: tint.red, green: tint.green, blue: tint.blue, opacity: alpha)
    }

    static func highlight(forInkAlpha alpha: Double) -> Color {
        let p = PaperLook.Printed.self
        return Color(.sRGB, white: 1, opacity: p.highlightAlphaFactor * min(1, alpha / p.highlightAlphaReference))
    }

    enum Anchor { case leading, trailing, center }

    /// 在 Canvas 里印一行：`baseline` 是基线的 y，`x` 是按 `anchor` 对齐的那条边（或中线）。
    static func draw(
        _ text: String, style: PaperLook.Printed.Style, alpha: Double? = nil,
        x: Double, baseline: Double, anchor: Anchor, in context: inout GraphicsContext
    ) {
        let unit = PaperLook.pointsPerPrototypeUnit
        let inkAlpha = alpha ?? style.alpha
        func resolved(_ color: Color) -> GraphicsContext.ResolvedText {
            context.resolve(Text(text).font(font(style)).tracking(style.tracking * unit).foregroundColor(color))
        }
        let ink = resolved(ink(alpha: inkAlpha))
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let size = ink.measure(in: unbounded)
        let top = baseline - ink.firstBaseline(in: size)
        let left: Double
        switch anchor {
        case .leading: left = x
        case .trailing: left = x - size.width
        case .center: left = x - size.width / 2
        }
        let p = PaperLook.Printed.self
        context.draw(resolved(highlight(forInkAlpha: inkAlpha)),
                     in: CGRect(x: left + p.highlightOffsetX * unit, y: top + p.highlightOffsetY * unit, width: size.width, height: size.height))
        context.draw(ink, in: CGRect(x: left, y: top, width: size.width, height: size.height))
    }
}

/// 页眉日期与页码（原型 `drawFurniture()`）。摊开时日期在右页右上角、两页各有页码；
/// 合上用外屏时只有一页，日期和页码都在右边。
struct PageFurniture: View {
    let spread: SpreadGeometry
    /// 第几张对开。左页页码 = 2n，右页 = 2n + 1（原型的编法：第 0 张是扉页）。
    let leafNumber: Int
    /// 页眉那一行（「十一月十七日　星期二」）。传文字而不是 `Date`：`Date()` 每次都不同，
    /// 会让页眉在每次界面刷新时都重画一遍（2026-11-17 卡顿排查）；同一天的文字相等，SwiftUI 就跳过它。
    let dateLine: String
    /// 系统安全区。页眉要避开状态栏，所以从安全区内侧量（与正文的页边距同一个道理）。
    let safe: EdgeInsets

    var body: some View {
        Canvas { context, size in
            let unit = PaperLook.pointsPerPrototypeUnit
            let p = PaperLook.Printed.self
            let rightEdge = size.width - safe.trailing - p.outerMargin * unit
            let leftEdge = safe.leading + p.outerMargin * unit
            let dateBaseline = safe.top + p.dateBaselineFromTop * unit
            let folioBaseline = size.height - safe.bottom - p.folioBaselineFromBottom * unit

            PrintedType.draw(dateLine, style: p.date, x: rightEdge, baseline: dateBaseline, anchor: .trailing, in: &context)
            if spread.hasFold {
                PrintedType.draw(ChineseNumerals.folio(leafNumber * 2), style: p.folio,
                                 x: leftEdge, baseline: folioBaseline, anchor: .leading, in: &context)
            }
            PrintedType.draw(ChineseNumerals.folio(leafNumber * 2 + 1), style: p.folio,
                             x: rightEdge, baseline: folioBaseline, anchor: .trailing, in: &context)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func dateLine(for date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day, .weekday], from: date)
        return ChineseNumerals.dateLine(month: parts.month ?? 1, day: parts.day ?? 1, weekday: parts.weekday ?? 1)
    }
}

/// 纸上一段会换行的印刷体提示。和页眉不同，它的长度不定，要在一页的宽度里折行，所以用 Text 排版。
struct PrintedNotice: View {
    let text: String
    var style: PaperLook.Printed.Style = PaperLook.Printed.notice

    var body: some View {
        let unit = PaperLook.pointsPerPrototypeUnit
        let p = PaperLook.Printed.self
        ZStack {
            Text(text)
                .foregroundColor(PrintedType.highlight(forInkAlpha: style.alpha))
                .offset(x: p.highlightOffsetX * unit, y: p.highlightOffsetY * unit)
            Text(text)
                .foregroundColor(PrintedType.ink(alpha: style.alpha))
        }
        .font(PrintedType.font(style))
        .tracking(style.tracking * unit)
        .multilineTextAlignment(.center)
    }
}

/// 他那页页脚的「他读到的是：「…」」（计划 R3/P9，原型 drawPresent 里的那一行）。
/// 他写在哪一页，就印在哪一页：看他那段字的中心在折缝哪一边。
struct HeardLine: View {
    let heard: String
    let replyBox: PageRegion
    let spread: SpreadGeometry
    let safeBottom: Double

    var body: some View {
        Canvas { context, size in
            let p = PaperLook.Printed.self
            let unit = PaperLook.pointsPerPrototypeUnit
            let shown = heard.count > p.heardMaxCharacters ? String(heard.prefix(p.heardMaxCharacters)) + "…" : heard
            let onLeading: Bool
            if let fold = spread.fold { onLeading = replyBox.left + replyBox.width / 2 < fold.left + fold.width / 2 } else { onLeading = true }
            let x = onLeading || spread.fold == nil
                ? p.outerMargin * unit
                : (spread.fold?.right ?? 0) + p.heardInsetFromFold * unit
            let baseline = size.height - safeBottom - p.heardBaselineFromBottom * unit
            PrintedType.draw("他读到的是：「\(shown)」", style: p.heard, x: x, baseline: baseline, anchor: .leading, in: &context)
        }
        .allowsHitTesting(false)
    }
}

/// 纸外的求助条（决策 67）：普通的系统界面，故意不像纸。文案与颜色在 `PaperLook.CareSlip`。
struct CareSlipView: View {
    let onDismiss: () -> Void

    var body: some View {
        let slip = PaperLook.CareSlip.self
        let ink = Color(.sRGB, red: slip.ink.red, green: slip.ink.green, blue: slip.ink.blue)
        HStack(alignment: .center, spacing: 16) {
            Text(slip.text)
                .font(.callout)
                .foregroundStyle(ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button(slip.dismiss, action: onDismiss)
                .buttonStyle(.bordered)
                .tint(ink)
        }
        .padding(slip.padding)
        .frame(maxWidth: slip.maxWidth)
        .background(Color(.sRGB, red: slip.background.red, green: slip.background.green, blue: slip.background.blue),
                    in: RoundedRectangle(cornerRadius: slip.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: slip.cornerRadius)
            .stroke(Color(.sRGB, red: slip.rule.red, green: slip.rule.green, blue: slip.rule.blue)))
    }
}
