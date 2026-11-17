//
//  PaperTexture.swift
//  模块：Features/Book（界面层；依赖 SwiftUI / CoreGraphics）
//
//  文件职责：把纸画出来——纸纹（计划 P1）和书脊阴影。
//
//  为什么程序生成而不是放一张纸的照片：
//  一，原型（决策 80 的规格源）就是这么做的，照搬它的算法才能「和网页版一样」；
//  二，照片要为每种屏幕尺寸各备一张，还会在 460 ppi 下被放大发糊，而程序生成按实际像素画；
//  三，固定种子（`PaperLook.textureSeed`）保证每次打开都是同一张纸，像同一本本子。
//
//  为什么纸纹画一次、缓存成位图：两千多根纤维、九千个斑点每帧重画不划算，而纸本身不变。
//  书脊阴影单独每次画：它跟着合页角度变（P7），而且只是两道渐变，便宜。
//
//  所有数值来自 `PaperLook`（原型 `PAPER()` / `drawGutter()` 的原值）；这里只有算法本身的常数
//  （比如角度取 0…π、颜色分量的 0/1）。
//

import SwiftUI

/// 一张纸：纸纹位图 + 书脊阴影。放在画布和他的字下面。
struct PaperBackground: View {
    let spread: SpreadGeometry
    /// 0 = 摊平，1 = 几乎合上。书脊阴影随它变宽变深。
    var spineDepth: Double = 0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            if let texture = PaperTexture.image(size: size, displayScale: displayScale) {
                context.draw(Image(decorative: texture, scale: displayScale), in: CGRect(origin: .zero, size: size))
            }
            if let fold = spread.fold, let vertical = spread.foldIsVertical {
                PaperTexture.drawSpine(in: &context, fold: fold, vertical: vertical, depth: spineDepth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
enum PaperTexture {
    /// 按像素尺寸缓存。转屏、开合会换尺寸，每种尺寸只画一次。
    private static var cache: [CacheKey: CGImage] = [:]

    private struct CacheKey: Hashable {
        let width: Int
        let height: Int
    }

    /// 某个尺寸（页面点）的纸纹位图。尺寸为 0 时返回 nil（视图第一次布局前会遇到）。
    static func image(size: CGSize, displayScale: CGFloat) -> CGImage? {
        let pixelWidth = Int((size.width * displayScale).rounded())
        let pixelHeight = Int((size.height * displayScale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let key = CacheKey(width: pixelWidth, height: pixelHeight)
        if let hit = cache[key] { return hit }
        let made = render(pixelWidth: pixelWidth, pixelHeight: pixelHeight, displayScale: displayScale)
        cache[key] = made
        return made
    }

    /// 原型 `PAPER()` 的移植。坐标用页面点，`context` 已按屏幕倍率缩放。
    private static func render(pixelWidth: Int, pixelHeight: Int, displayScale: CGFloat) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: displayScale, y: displayScale)

        let width = Double(pixelWidth) / displayScale
        let height = Double(pixelHeight) / displayScale
        let unit = PaperLook.pointsPerPrototypeUnit
        let areaInPrototypeUnits = (width / unit) * (height / unit)
        var random = SeededRandomNumberGenerator(seed: PaperLook.textureSeed)
        func next() -> Double { Double.random(in: 0 ..< 1, using: &random) }
        func pick(_ range: ClosedRange<Double>) -> Double { range.lowerBound + next() * (range.upperBound - range.lowerBound) }

        context.setFillColor(cgColor(PaperLook.base, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // 纤维
        context.setLineWidth(PaperLook.Fiber.lineWidth * unit)
        let fibers = Int((PaperLook.Fiber.densityPerSquareUnit * areaInPrototypeUnits).rounded())
        for _ in 0 ..< fibers {
            let x = next() * width, y = next() * height
            let angle = next() * Double.pi
            let length = pick(PaperLook.Fiber.lengthRange) * unit
            let color = next() < PaperLook.Fiber.darkShare
                ? cgColor(PaperLook.Fiber.darkTint, alpha: pick(PaperLook.Fiber.darkAlphaRange))
                : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: pick(PaperLook.Fiber.lightAlphaRange))
            context.setStrokeColor(color)
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
            context.strokePath()
        }

        // 斑点
        let specks = Int((PaperLook.Speck.densityPerSquareUnit * areaInPrototypeUnits).rounded())
        for _ in 0 ..< specks {
            context.setFillColor(cgColor(PaperLook.Speck.tint, alpha: pick(PaperLook.Speck.alphaRange)))
            context.fill(CGRect(x: next() * width, y: next() * height, width: unit, height: unit))
        }

        // 霉点：只在左右书口附近
        let band = PaperLook.Foxing.edgeBand * unit
        for _ in 0 ..< PaperLook.Foxing.count {
            let x = next() < 0.5 ? next() * band : width - next() * band
            let y = next() * height
            let radius = pick(PaperLook.Foxing.radiusRange) * unit
            radialGlow(context, center: CGPoint(x: x, y: y), from: 0, to: radius,
                       tint: PaperLook.Foxing.tint, innerAlpha: PaperLook.Foxing.centerAlpha, outerAlpha: 0, extendOutward: false)
        }

        // 暗角
        radialGlow(context, center: CGPoint(x: width / 2, y: height / 2),
                   from: height * PaperLook.Vignette.innerRadiusOfHeight,
                   to: width * PaperLook.Vignette.outerRadiusOfWidth,
                   tint: PaperLook.Vignette.tint, innerAlpha: 0, outerAlpha: PaperLook.Vignette.edgeAlpha, extendOutward: true)

        // 书口的细线
        let edge = PaperLook.EdgeLines.self
        for index in 0 ..< edge.count {
            let alpha = edge.firstAlpha - edge.alphaStep * Double(index)
            context.setFillColor(cgColor(edge.tint, alpha: alpha))
            let offset = Double(index) * edge.spacing
            context.fill(CGRect(x: (edge.firstInset + offset) * unit, y: 0, width: edge.lineWidth * unit, height: height))
            context.fill(CGRect(x: width - (edge.firstInsetRight + offset) * unit, y: 0, width: edge.lineWidth * unit, height: height))
        }

        return context.makeImage()
    }

    /// 书脊阴影：折缝中线两侧各一道渐变，靠缝最深、往外淡到没有。原型 `drawGutter(depth)`。
    static func drawSpine(in context: inout GraphicsContext, fold: PageRegion, vertical: Bool, depth: Double) {
        let spine = PaperLook.Spine.self
        let unit = PaperLook.pointsPerPrototypeUnit
        let span = (spine.halfSpan + spine.halfSpanGrowth * depth) * unit
        let alpha = spine.alpha + spine.alphaGrowth * depth
        let inner = color(spine.innerTint, alpha: alpha)
        let outer = color(spine.outerTint, alpha: 0)
        let center = vertical ? fold.left + fold.width / 2 : fold.top + fold.height / 2

        for direction in [-1.0, 1.0] {
            let far = center + direction * span
            let rect: CGRect
            let start: CGPoint, end: CGPoint
            if vertical {
                rect = CGRect(x: min(center, far), y: fold.top, width: span, height: fold.height)
                start = CGPoint(x: center, y: 0); end = CGPoint(x: far, y: 0)
            } else {
                rect = CGRect(x: fold.left, y: min(center, far), width: fold.width, height: span)
                start = CGPoint(x: 0, y: center); end = CGPoint(x: 0, y: far)
            }
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: [inner, outer]), startPoint: start, endPoint: end))
        }
    }

    // MARK: 小工具

    private static func cgColor(_ tint: PaperTint, alpha: Double) -> CGColor {
        CGColor(srgbRed: tint.red, green: tint.green, blue: tint.blue, alpha: alpha)
    }

    private static func color(_ tint: PaperTint, alpha: Double) -> Color {
        Color(.sRGB, red: tint.red, green: tint.green, blue: tint.blue, opacity: alpha)
    }

    private static func radialGlow(
        _ context: CGContext, center: CGPoint, from inner: Double, to outer: Double,
        tint: PaperTint, innerAlpha: Double, outerAlpha: Double, extendOutward: Bool
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [cgColor(tint, alpha: innerAlpha), cgColor(tint, alpha: outerAlpha)] as CFArray,
            locations: [0, 1]
        ) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: inner,
            endCenter: center, endRadius: outer,
            options: extendOutward ? [.drawsAfterEndLocation] : []
        )
    }
}
