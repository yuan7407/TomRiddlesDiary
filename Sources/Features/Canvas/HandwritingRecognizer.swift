//
//  HandwritingRecognizer.swift
//  模块：Features/Canvas（读懂用户在纸上写了什么）
//
//  文件职责：把用户的手写笔画识别成文字，并如实报告哪些语言在本机上不可用。
//
//  设计原因：
//  - 用系统内建的 `PKStrokeRecognizer`（iPadOS 27 起）而不是把手写渲染成图再做
//    图像 OCR。理由：它吃的是**笔画序列**，看得到笔顺、方向和停顿；图像 OCR 只
//    看得到最终像素。手写识别上前者信息更多。而且它端侧、免费、不联网，
//    日记内容一个字节都不出设备。
//  - 包一层而不是直接用：系统 API 返回的是「本机实际能用哪些语言」，
//    而产品要求的是「中文优先、中英混写」。两者不一致时必须**说出来**，
//    这一层的主要价值就是把这个差异变成显式数据（`RecognitionAvailability`），
//    而不是让调用方以为「识别不出来」是用户写得差。
//  - 放在 Features/Canvas：它 import PencilKit，而按门禁规定纯逻辑层不许依赖具体
//    框架。「读懂用户在这张纸上写了什么」和读笔画是同一件事的两面，放在一起。
//
//  不静默兜底（AGENTS.md 硬性要求）：
//  当请求的语言在本机没有模型时，系统会直接把它从可用列表里去掉，`recognizedText`
//  返回 nil——从外面看和「识别失败」一模一样。这里必须把两者分开：
//  「本机没有中文模型」是环境问题，要告诉用户去装/换设备；
//  「有模型但认不出」是写得太潦草或识别能力不足，是另一回事。
//  混成一句「识别失败」会让人查错方向。
//

import Foundation
import PencilKit

/// 识别能力的实际状况：请求了什么、本机能用什么、差了什么。
nonisolated struct RecognitionAvailability: Equatable, Sendable {
    /// 按产品要求请求的语言。
    let requested: [Locale.Language]

    /// 系统确认可用、识别时真正会用到的语言。
    let active: [Locale.Language]

    /// 请求了但本机没有模型的语言。非空即意味着**有一部分内容注定认不出来**，
    /// 必须让用户知道，不能等他反复重写。
    let unavailable: [Locale.Language]

    /// 是否至少有一种语言可用。全都不可用时识别毫无意义。
    var isUsable: Bool { !active.isEmpty }

    /// 请求的语言是否全部可用。
    var isComplete: Bool { unavailable.isEmpty }
}

/// 一次识别的结果。
nonisolated struct HandwritingRecognition: Equatable, Sendable {
    /// 识别出的文字。nil 表示这一页没认出任何内容，
    /// 具体是「没有可用语言」还是「有语言但认不出」要看 `availability`。
    let text: String?

    /// 识别时的语言状况。
    let availability: RecognitionAvailability

    /// 是否认出了内容。
    var hasText: Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 手写识别器。
///
/// 内部持有一个 `PKStrokeRecognizer`（它本身是 actor，因此可跨并发域安全传递）。
/// 复用同一个实例而不是每次识别都新建：新建会重新加载语言模型，代价不小。
nonisolated struct HandwritingRecognizer: Sendable {
    private let recognizer: PKStrokeRecognizer
    private let requestedLanguages: [Locale.Language]

    init(languages: [Locale.Language] = InteractionSettings.recognitionLanguages) {
        requestedLanguages = languages
        recognizer = PKStrokeRecognizer(preferredLanguages: languages)
    }

    /// 查询本机的识别能力。
    ///
    /// 用系统告知的 `languages`（识别器实际启用的）与请求列表比对，得出差集。
    /// 比对按语言代码而不是完整标识符：请求 `zh-Hans` 时系统可能报 `zh`，
    /// 那是同一种语言，不该被算成不可用。
    func availability() async -> RecognitionAvailability {
        let active = await recognizer.languages
        let activeCodes = Set(active.compactMap(\.languageCode))
        let unavailable = requestedLanguages.filter { requested in
            guard let code = requested.languageCode else { return true }
            return !activeCodes.contains(code)
        }

        return RecognitionAvailability(
            requested: requestedLanguages,
            active: active,
            unavailable: unavailable
        )
    }

    /// 识别一页手写内容。
    /// - Parameter drawing: 用户在这一页写下的全部笔画。
    /// - Returns: 识别结果，附带语言可用性——调用方必须区分「没有模型」与「认不出」。
    func recognize(_ drawing: PKDrawing) async -> HandwritingRecognition {
        let availability = await availability()

        // 一种可用语言都没有时不去调识别：那只会得到一个 nil，
        // 反而掩盖了「本机缺模型」这个真实原因。
        guard availability.isUsable else {
            return HandwritingRecognition(text: nil, availability: availability)
        }

        await recognizer.updateDrawing(drawing)
        let text = await recognizer.recognizedText()
        return HandwritingRecognition(text: text, availability: availability)
    }
}
