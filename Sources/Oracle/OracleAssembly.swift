//
//  OracleAssembly.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：决定「这个构建实际用哪个魂」，并把它装起来（计划 E6d）。
//
//  ── 三种情况，优先级从高到低 ──
//  ① 端点与 key 都配好了、人设也读到了 → 用真的（`ChatCompletionsOracle`）
//  ② 没配好，但这是 DEBUG 构建 → 用假的（`MockOracleProvider`），纸上会说明它是假的
//  ③ 没配好，而且是 Release 构建 → **什么都不用**，界面如实说魂接不上
//
//  ── 为什么装配要单独一个文件 ──
//  这三种情况的判断散在别处会出两种问题：一是「为什么现在用的是假魂」变得很难查，
//  二是每个想知道答案的地方都得重复一遍判断，迟早有一处写错。
//  收在这里之后，`DiaryPageModel` 只问一句「给我这个构建该用的魂」。
//
//  ── 为什么装配失败不抛错 ──
//  「没配 provider」不是异常，是一种**正常状态**——现在就是这个状态。
//  所以返回 nil，由上层走 `OracleFailure.notConfigured` 那条诚实提示。
//  抛错会让每个调用点都得写 catch，而它们能做的也只是显示同一句话。
//  但**为什么**没装上必须能查到：DEBUG 里会打一行说明（见 `describeChoice`）。
//

import Foundation

nonisolated enum OracleAssembly {
    /// 这个构建该用哪个魂。nil 表示没有——上层会如实说魂接不上。
    ///
    /// - Parameters:
    ///   - bundle: 从哪读端点配置与人设文件。便于测试注入。
    ///   - isReleaseBuild: 是否正式构建。决定两件事：标了 `debugOnly` 的人设能不能用，
    ///     以及没配 provider 时要不要退回假魂。
    static func makeProvider(
        bundle: Bundle = .main,
        isReleaseBuild: Bool = OracleAssembly.isRelease
    ) -> OracleProvider? {
        if let real = makeRealProvider(bundle: bundle, isReleaseBuild: isReleaseBuild) {
            return real
        }
        #if DEBUG
        // 真的没配上就退回假魂，好让链路能跑。它在纸上会自己承认是假的
        // （`producesCannedReplies`），所以不会被误认成模型的回答。
        return isReleaseBuild ? nil : MockOracleProvider()
        #else
        return nil
        #endif
    }

    /// 试着装真 provider。任何一环缺失都返回 nil，并在 DEBUG 里说清缺的是哪一环。
    private static func makeRealProvider(bundle: Bundle, isReleaseBuild: Bool) -> OracleProvider? {
        guard let endpoint = OracleEndpoint.fromBundle(bundle) else {
            report("端点没配全（Config/Secrets.xcconfig 里填了 ORACLE_API_KEY 吗？变量名必须完全一致）")
            return nil
        }
        guard let personaData = personaData(in: bundle) else {
            report("读不到人设文件。复制 Config/Persona.example.json 成 Persona.local.json 再填。")
            return nil
        }

        let persona: SoulPersona
        do {
            persona = try SoulPersonaLoader.decode(personaData, isReleaseBuild: isReleaseBuild)
        } catch let failure as SoulPersonaFailure {
            report(failure.sentenceForDeveloper)
            return nil
        } catch {
            report("人设文件出了没预料到的错：\(error)")
            return nil
        }

        report("用真的魂：\(endpoint.descriptionWithoutKey)，人设「\(persona.displayName)」")
        return ChatCompletionsOracle(
            endpoint: endpoint,
            systemPrompt: SoulSystemPrompt.compose(persona)
        )
    }

    /// 人设文件的内容。
    ///
    /// 它由构建脚本在 **Debug** 时拷进包（见工程的「拷人设（仅 Debug）」构建阶段）。
    /// Release 构建里不会有这个文件——那是刻意的：当前的人设是内部 IP 占位，
    /// 绝不能进分发面。商业版要用原创人设，届时它会作为正常资源打包。
    private static func personaData(in bundle: Bundle) -> Data? {
        guard let url = bundle.url(forResource: "Persona.local", withExtension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// 当前是不是正式构建。
    ///
    /// 用编译条件而不是运行时判断（比如查有没有调试器）：编译条件在编译期就定了，
    /// 骗不过去；运行时判断可以被绕过，而这里挡的是 IP 进分发面，不能有活动余地。
    static var isRelease: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// 把「为什么用/没用真魂」打出来。只在 DEBUG。
    ///
    /// 这一行是刻意加的：上一轮吃过教训——关键路径上留了不打日志的分支，
    /// 结果「为什么没回应」在日志里完全查不到，白查一轮。
    private static func report(_ sentence: String) {
        #if DEBUG
        print("── 魂的装配（计划 E6d）── \(sentence)")
        #endif
    }
}
