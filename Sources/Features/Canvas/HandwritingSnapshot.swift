//
//  HandwritingSnapshot.swift
//  模块：Features/Canvas（界面层；依赖 PencilKit / UIKit / Vision）
//
//  文件职责：把你这一轮的手写画成一张白底黑字的图（计划 R2/R3），以及用 Vision 读这张图。
//
//  为什么要有这张图（2026-11-17 真机实测）：系统手写识别 `PKStrokeRecognizer` 对手指写的英文大多认不出，
//  中文九成认不出。原型的做法是把笔迹画成图交给能看图的模型读（R3）——这张图就是那张图。
//  同一张图也交给 iOS 自带的 Vision 文字识别读一遍（R2）：不联网、不花钱，系统识别读不出来时补一路。
//  Vision 面向印刷体，手写准确率没把握，所以它认出的字和系统识别一样，只作给模型的参考，以图为准。
//
//  只发「这一轮」：上一轮的字已经被纸喝下去了（P4），也不该再读一遍。
//

import PencilKit
import UIKit
import Vision

enum HandwritingSnapshot {
    struct Image: @unchecked Sendable {
        /// 发给模型的 PNG。
        let png: Data
        /// 交给 Vision 的位图（同一张）。CGImage 不可变，跨线程传递是安全的。
        let cgImage: CGImage
    }

    /// 画成图。空笔迹返回 nil。原型 snapshot()：留白、按最长边放大、白底。
    @MainActor
    static func render(_ drawing: PKDrawing) -> Image? {
        let bounds = drawing.bounds
        guard !drawing.strokes.isEmpty, bounds.width > 0 || bounds.height > 0 else { return nil }
        let pad = InteractionSettings.snapshotPadding
        let rect = bounds.insetBy(dx: -pad, dy: -pad)
        let range = InteractionSettings.snapshotScaleRange
        let scale = min(range.upperBound, max(range.lowerBound, InteractionSettings.snapshotTargetLongestSide / max(rect.width, rect.height)))

        let ink = drawing.image(from: rect, scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            ink.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        guard let png = image.pngData(), let cgImage = image.cgImage else { return nil }
        return Image(png: png, cgImage: cgImage)
    }

    /// 用 Vision 读这张图（R2）。读不出返回 nil。中文简体与英文都请求；
    /// 识别级别取「准确」而不是「快」：一轮只读一次，多几百毫秒换准确度值得。
    static func readWithVision(_ image: CGImage) async -> String? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = InteractionSettings.recognitionLanguages
        guard let observations = try? await request.perform(on: image) else { return nil }
        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
