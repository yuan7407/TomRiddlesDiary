//
//  HandwritingFont.swift
//  模块：Configuration（集中配置）
//
//  文件职责：登记并加载手写体字体，是全 App 唯一知道字体文件名与字族名的地方。
//
//  设计原因：
//  - iOS 内置字体里**没有任何中文楷体或手写体**（实测 iOS 27 运行时只有 PingFang，
//    macOS 上的手札体、翩翩体、楷体在 iOS 上都不存在），所以必须自带字体。
//  - 用运行时注册（CoreText）而不是 Info.plist 的 UIAppFonts：UIAppFonts 加载失败
//    时系统会静默回落到默认字体，界面照样能画出来，只是字变成了印刷体——这正是
//    AGENTS.md 禁止的静默兜底。运行时注册能拿到明确的失败原因并如实上报。
//  - 字号不在这里定：字高属手感，归 `HandwritingFeel`。这里只管「哪个字体」。
//
//  这个字体是**计划 E8 的脚手架**，不是最终方案。字体存的是字的外框轮廓，不含笔顺，
//  所以它给不出逐笔生长。计划 E1 用字形笔顺数据替换它之后，这个字体可能仍保留，
//  但只用来提供排版所需的字宽，不再用来画字。
//

import CoreGraphics
import CoreText
import Foundation

/// 标为 nonisolated：排版层 `TextLayout` 是纯逻辑、不在主线程上，必须能读到字族名
/// 并触发注册。字体注册是进程级的一次性动作，用 `static let` 的惰性初始化保证
/// 只执行一次且线程安全。
nonisolated enum HandwritingFont {
    // MARK: 字体标识

    /// 打进 App 的字体文件名（不含扩展名）。
    static let resourceName = "ChillZhuo"

    /// 字体文件扩展名。选 OTF 而非同包内的 TTF：两者字形相同，OTF 约 3.9 MB、
    /// TTF 约 5.3 MB，iOS 对两者支持一致，取小的。
    static let resourceExtension = "otf"

    /// 注册成功后可用于 `UIFont(name:size:)` 的字族名。
    static let familyName = "ChillZhuo"

    // MARK: 来源与授权（分发前必须履行）

    /// 字体中文名，用于界面上的署名。
    static let displayName = "寒蝉手拙体"

    /// 作者要求的署名对象。README 原文：「分享请标注作者为寒蝉字型」。
    static let attribution = "寒蝉字型"

    /// 授权说明。作者在项目 README 中写明「免费授权全社会使用（包括商用）」。
    /// 注意：这是作者的声明式授权，**不是标准授权文件**（仓库没有 LICENSE，
    /// 字体 name 表里也没有授权字段）。分发前必须：
    /// 一、在 App 内可见位置标注作者；二、留存这份 README 声明的存档以备追溯。
    static let licenseNote = "免费授权全社会使用（包括商用），来源：寒蝉手拙体 v2.500 项目 README"

    /// 锁定的版本号。换版本时必须同时更新这里与 MEMORY 的记录，
    /// 否则「字体看起来变了」将无从追溯。
    static let pinnedVersion = "2.500"

    // MARK: 注册

    enum RegistrationError: Error, Sendable, CustomStringConvertible {
        case resourceMissing
        case unreadable
        case registrationRejected(String)

        var description: String {
            switch self {
            case .resourceMissing:
                "App 包里找不到手写体字体文件 \(resourceName).\(resourceExtension)"
            case .unreadable:
                "手写体字体文件存在但无法解析为字体"
            case .registrationRejected(let reason):
                "系统拒绝注册手写体字体：\(reason)"
            }
        }
    }

    /// 把打包的字体注册进系统，成功后即可按 `familyName` 取用。
    ///
    /// 只做一次；重复调用直接返回首次结果。失败时**抛出**而不是悄悄放过，
    /// 因为回落到系统字体会让「手写日记」变成印刷体，属于伪装成功。
    static func register() throws {
        try registrationResult.get()
    }

    private static let registrationResult: Result<Void, RegistrationError> = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            return .failure(.resourceMissing)
        }

        // 用 CTFontManagerRegisterFontsForURL 而不是已在 iOS 18 弃用的
        // CTFontManagerRegisterGraphicsFont。.process 作用域即注册到本进程，
        // 不影响系统其他 App。
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "未提供原因"
            // 文件读不出来和系统拒绝注册是两种不同的失败，分开报以便定位。
            return .failure(
                FileManager.default.isReadableFile(atPath: url.path)
                    ? .registrationRejected(reason)
                    : .unreadable
            )
        }
        return .success(())
    }()
}
