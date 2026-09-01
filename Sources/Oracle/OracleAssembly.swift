//
//  OracleAssembly.swift
//  模块：Oracle（只许 import Foundation，门禁在管）
//
//  文件职责：决定「这个构建实际用哪个魂」，并把它装起来（计划 E6d）。
//
//  ── 三种情况，优先级从高到低 ──
//  ① key 配好了、人设也读到了 → 用真的（`ChatCompletionsOracle`）
//  ② 没配 key，但这是 DEBUG 构建 → 用假的（`MockOracleProvider`），纸上会说明它是假的
//  ③ 没配 key，而且是 Release 构建 → **什么都不用**，界面如实说魂接不上
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
    static func makeProvider(bundle: Bundle = .main) -> OracleProvider? {
        if let real = makeRealProvider(bundle: bundle) {
            return real
        }
        #if DEBUG
        // 没配上就退回假魂，好让链路能跑。它在纸上会自己承认是假的
        // （`producesCannedReplies`），所以不会被误认成模型的回答。
        return MockOracleProvider()
        #else
        return nil
        #endif
    }

    /// 试着装真 provider。任何一环缺失都返回 nil，并在 DEBUG 里说清缺的是哪一环。
    private static func makeRealProvider(bundle: Bundle) -> OracleProvider? {
        guard let endpoint = OracleEndpoint.fromBundle(bundle) else {
            report("没读到 key。在 Config/Secrets.xcconfig 里写一行：ORACLE_API_KEY = sk-你的key")
            return nil
        }
        guard let personaData = personaData(in: bundle) else {
            report("读不到 Sources/Resources/Persona.json")
            return nil
        }

        let persona: SoulPersona
        do {
            persona = try SoulPersonaLoader.decode(personaData)
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

    /// 人设文件的内容。`Sources/Resources/Persona.json`，一个普通的打包资源。
    private static func personaData(in bundle: Bundle) -> Data? {
        guard let url = bundle.url(forResource: "Persona", withExtension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
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
