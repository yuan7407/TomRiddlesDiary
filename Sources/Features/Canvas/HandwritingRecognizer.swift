//
//  HandwritingRecognizer.swift
//  模块：Features/Canvas（读懂用户在纸上写了什么）
//
//  文件职责：把用户的手写笔画识别成文字，并如实报告这台设备**为什么**读不出来。
//
//  设计原因：
//  - 用系统内建的 `PKStrokeRecognizer`（iPadOS 27 起）而不是把手写渲染成图再做
//    图像 OCR。理由：它吃的是**笔画序列**，看得到笔顺、方向和停顿；图像 OCR 只
//    看得到最终像素。手写识别上前者信息更多。而且它端侧、免费、不联网，
//    日记内容一个字节都不出设备。
//  - 包一层而不是直接用：系统 API 返回的是「本机实际能用哪些语言」，
//    而产品要求的是「中文优先、中英混写」。两者不一致时必须**说出来**。
//
//  ── 三种「读不出来」必须分清（这是本文件存在的主要理由）──
//  它们的处置完全不同，混成一句「识别失败」会让人查错方向：
//
//  一、**系统太旧，根本没有这个 API**（iPadOS 26 及更早）。
//     这是设备/系统问题，用户升级系统就能解决。
//  二、**有 API，但本机没有某种语言的模型**。系统会直接把它从可用列表里去掉，
//     `recognizedText` 返回 nil——从外面看和「识别失败」一模一样。
//     更危险的是它**不一定返回 nil**：缺中文模型时写「你好」会得到 `15.47`，
//     也就是把笔画硬塞进它手上有的语言里，吐出一串看起来正常的垃圾。
//     而要判断「这几笔本来是中文」得先有中文模型——事后过滤不掉，只能事先告知。
//  三、**有模型但认不出**。写得太潦草或识别能力不足，是另一回事。
//
//  ── 为什么最低系统是 26 而识别要 27（2026-08-29 用户拍板）──
//  用户手里那台 iPad 是 iPadOS 26.6，而 iPadOS 27 至今只有 beta。
//  三件待验证的事里只有识别需要 27——`TimelineView` 连续动画与真实 Apple Pencil 的
//  停顿分布（计划 A10 与 E3c 阈值的唯一依据）在 26 上就能测。
//  所以部署目标降到 26，识别用 `#available` 门控，在 26 上如实报告「系统还没有这个能力」。
//  这不是放弃 27：识别仍然要 27，只是不再拿它挡住不需要它的测量。
//
//  ── 为什么缓存 `PKStrokeRecognizer` 实例（2026-08-31，有实测依据了）──
//  这件事反复过一次，记下来免得再来第三遍：
//
//  最初这里存着一个实例复用，理由写的是「新建会重新加载语言模型，代价不小」——
//  那句话当时**从未测量过**。部署目标降到 26 之后，存一个 iPadOS 27 才有的类型
//  会逼出 `AnyObject` 之类的绕法，于是改成每次识别时新建，并注明「若真机测出代价
//  可观再加回来」。
//
//  证据来了：用户在模拟器上写了 30 笔，控制台刷出**约六十条**
//  `Remote connection to handwritingd was invalidated`。每次新建识别器就要和系统的
//  手写守护进程建一次跨进程连接，识别器一销毁连接就断——每抬一次笔来两回。
//  这不只是日志噪声，是每写一笔都在拆建一条 XPC 连接。
//
//  所以恢复缓存，用一个 `@available(iOS 27, *)` 的 actor 按语言列表存。
//  用 actor 而不是加锁的全局字典：Swift 6 下这是唯一不需要 `@unchecked Sendable`
//  就能安全共享可变状态的做法，而 `@unchecked` 等于把并发正确性从编译器手里
//  拿回来自己保证。
//

import Foundation
import PencilKit

/// 识别能力的实际状况：请求了什么、本机能用什么、差了什么、以及系统本身有没有这个能力。
nonisolated struct RecognitionAvailability: Equatable, Sendable {
    /// 按产品要求请求的语言。
    let requested: [Locale.Language]

    /// 系统确认可用、识别时真正会用到的语言。
    let active: [Locale.Language]

    /// 请求了但本机没有模型的语言。非空即意味着**有一部分内容注定认不出来**，
    /// 必须让用户知道，不能等他反复重写。
    let unavailable: [Locale.Language]

    /// 这台设备的系统版本有没有提供手写识别 API。
    ///
    /// 为什么单独一个字段而不是让 `active` 为空就算了：两者的原因和处置完全不同。
    /// 「系统太旧」要告诉用户升级系统；「缺语言模型」要告诉用户这台设备读不出中文。
    /// 合成一个「不可用」会让用户按错的方向去解决。
    let systemProvidesRecognition: Bool

    /// 是否至少有一种语言可用。系统没有这个 API 时恒为 false。
    var isUsable: Bool { systemProvidesRecognition && !active.isEmpty }

    /// 请求的语言是否全部可用。
    var isComplete: Bool { systemProvidesRecognition && unavailable.isEmpty }

    /// 系统没有手写识别 API 时的状况：请求照旧记下来，可用为空，全部算缺失。
    /// 这样调用方不需要为「旧系统」写第二套分支，只要读 `systemProvidesRecognition`
    /// 就知道该说哪句话。
    static func systemTooOld(requested: [Locale.Language]) -> RecognitionAvailability {
        RecognitionAvailability(
            requested: requested,
            active: [],
            unavailable: requested,
            systemProvidesRecognition: false
        )
    }
}

/// 一次识别的结果。
nonisolated struct HandwritingRecognition: Equatable, Sendable {
    /// 识别出的文字。nil 表示这一页没认出任何内容，
    /// 具体原因要看 `availability`（系统太旧 / 缺语言模型 / 有模型但认不出）。
    let text: String?

    /// 识别时的语言与系统能力状况。
    let availability: RecognitionAvailability

    /// 是否认出了内容。
    var hasText: Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 系统识别器的缓存。
///
/// 为什么需要它：每新建一个 `PKStrokeRecognizer` 就要和系统的手写守护进程
/// （`handwritingd`）建一次跨进程连接，实例销毁时连接就断。实测每抬一次笔新建一个，
/// 30 笔会刷出约六十条 `Remote connection to handwritingd was invalidated`。
///
/// 为什么用 actor 而不是加锁的全局字典：Swift 6 下这是唯一不需要 `@unchecked Sendable`
/// 就能安全共享可变状态的做法。用 `@unchecked` 等于把并发正确性从编译器手里拿回来自己保证。
///
/// 缓存按语言列表分键：测试会构造只请求某一种语言的识别器，它们必须各自独立，
/// 否则一条用例设的语言会污染另一条。
@available(iOS 27, *)
private actor SystemRecognizerCache {
    static let shared = SystemRecognizerCache()

    private var byLanguages: [String: PKStrokeRecognizer] = [:]

    func recognizer(for languages: [Locale.Language]) -> PKStrokeRecognizer {
        let key = languages.map(\.minimalIdentifier).joined(separator: "|")
        if let existing = byLanguages[key] { return existing }

        let created = PKStrokeRecognizer(preferredLanguages: languages)
        byLanguages[key] = created
        return created
    }
}

/// 手写识别器。
nonisolated struct HandwritingRecognizer: Sendable {
    /// 手写识别 API 需要的最低系统版本。写成常量而不是散落在两处 `#available` 里，
    /// 也用于给用户的提示文案——用户看到的版本号和代码里门控的必须是同一个。
    static let requiredSystemVersion = 27

    private let requestedLanguages: [Locale.Language]

    init(languages: [Locale.Language] = InteractionSettings.recognitionLanguages) {
        requestedLanguages = languages
    }

    /// 查询本机的识别能力。
    func availability() async -> RecognitionAvailability {
        guard #available(iOS 27, *) else {
            return .systemTooOld(requested: requestedLanguages)
        }
        let recognizer = await SystemRecognizerCache.shared.recognizer(for: requestedLanguages)
        return await availability(of: recognizer)
    }

    /// 识别一页手写内容。
    /// - Parameter drawing: 用户在这一页写下的全部笔画。
    /// - Returns: 识别结果，附带能力状况——调用方必须区分「系统太旧」「没有模型」「认不出」。
    func recognize(_ drawing: PKDrawing) async -> HandwritingRecognition {
        guard #available(iOS 27, *) else {
            return HandwritingRecognition(
                text: nil,
                availability: .systemTooOld(requested: requestedLanguages)
            )
        }

        // 同一个实例既用来查能力也用来识别，而且整个 App 生命周期只有这一个
        // （见 `SystemRecognizerCache`）：每次新建都会拆建一条到 handwritingd 的连接。
        let recognizer = await SystemRecognizerCache.shared.recognizer(for: requestedLanguages)
        let availability = await availability(of: recognizer)

        // 一种可用语言都没有时不去调识别：那只会得到一个 nil，
        // 反而掩盖了「本机缺模型」这个真实原因。
        guard availability.isUsable else {
            return HandwritingRecognition(text: nil, availability: availability)
        }

        await recognizer.updateDrawing(drawing)
        let text = await recognizer.recognizedText()
        return HandwritingRecognition(text: text, availability: availability)
    }

    /// 用系统告知的 `languages`（识别器实际启用的）与请求列表比对，得出差集。
    ///
    /// 比对按语言代码而不是完整标识符：请求 `zh-Hans` 时系统可能报 `zh`，
    /// 那是同一种语言，不该被算成不可用。
    @available(iOS 27, *)
    private func availability(of recognizer: PKStrokeRecognizer) async -> RecognitionAvailability {
        let active = await recognizer.languages
        let activeCodes = Set(active.compactMap(\.languageCode))
        let unavailable = requestedLanguages.filter { requested in
            guard let code = requested.languageCode else { return true }
            return !activeCodes.contains(code)
        }

        return RecognitionAvailability(
            requested: requestedLanguages,
            active: active,
            unavailable: unavailable,
            systemProvidesRecognition: true
        )
    }
}
