//
//  OracleEndpoint.swift
//  模块：Oracle（「说什么」那一侧；只许 import Foundation，门禁在管）
//
//  文件职责：读出「这个构建要调哪个端点、哪个模型、用什么 key」（计划 E6d）。
//
//  ── 值从哪来 ──
//  构建时由 `Config/Oracle.xcconfig` 写进 Info.plist，运行时从这里读出来。
//  那个 xcconfig **只挂在 App target 的 Debug 配置上**，所以：
//  · Debug 构建能读到；
//  · Release 构建的 Info.plist 里**连键名都没有**（已实测核对）。
//  也就是说分发包里不存在任何 key——不是藏得好，是没有。
//
//  ── 为什么不把这些值写进代码 ──
//  决策 4：模型名、Base URL、区域不得散落在业务代码里。换供应商时只该改配置。
//  而且 `AGENTS.md` 要求端点与模型可用性按实际账号页面复核——写进代码就等于
//  把一个没核对过的值固化了。
//
//  ── 为什么 https 是写死的 ──
//  它不是配置项，是安全约束：key 放在请求头里，走 http 等于把 key 明文广播。
//  做成配置就意味着有人能把它改错，而改错的后果是无声的。
//

import Foundation

/// 这个构建实际会调的端点。
nonisolated struct OracleEndpoint: Equatable, Sendable {
    /// 主机名，可带路径前缀（有些供应商的兼容模式端点是 host + 固定前缀）。
    let host: String
    /// 对话接口路径。
    let chatPath: String
    /// 模型名。
    let model: String
    /// API key。
    let apiKey: String

    /// 完整的请求地址。scheme 恒为 https，理由见文件头。
    var chatURL: URL? {
        URL(string: "https://" + host + chatPath)
    }

    /// 从 Info.plist 读。**读不到就是 nil，不给任何默认值**——
    /// 给了默认端点会让「没配」看起来像「配错了」，而两者的处置完全不同。
    ///
    /// - Parameter bundle: 便于测试注入。
    static func fromBundle(_ bundle: Bundle = .main) -> OracleEndpoint? {
        from { bundle.object(forInfoDictionaryKey: $0) as? String }
    }

    /// 真正的解析逻辑。抽成接一个闭包，是为了能在测试里喂任意值——
    /// `Bundle` 的 Info.plist 没法在测试里替换，而「空值算没配」这条规则必须测得到。
    static func from(_ read: (String) -> String?) -> OracleEndpoint? {
        func value(_ key: String) -> String? {
            guard let raw = read(key) else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // 空串按「没有」处理：xcconfig 里 `ORACLE_API_KEY =` 就会得到空串，
            // 那正是「这个构建没配 provider」的表达方式。
            // 也挡住模板占位值——填了 `sk-在这里粘贴...` 等于没填。
            guard !trimmed.isEmpty, !trimmed.contains("在这里粘贴"), !trimmed.hasPrefix("REPLACE") else {
                return nil
            }
            return trimmed
        }

        guard let host = value("OracleHost"),
              let chatPath = value("OracleChatPath"),
              let model = value("OracleModel"),
              let apiKey = value("OracleAPIKey")
        else { return nil }

        return OracleEndpoint(host: host, chatPath: chatPath, model: model, apiKey: apiKey)
    }

    /// 给日志用的一行说明。**刻意不含 key**，连前几位都不给——
    /// 日志会被贴进对话、贴进 issue，key 的任何片段都不该出现在那种地方。
    var descriptionWithoutKey: String {
        "host=\(host) path=\(chatPath) model=\(model) key=已配置(\(apiKey.count) 字符)"
    }
}
